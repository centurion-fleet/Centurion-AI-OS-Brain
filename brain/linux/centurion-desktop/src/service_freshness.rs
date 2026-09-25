//! Keep the services that run the Brain in step with the code on disk.
//!
//! A package upgrade replaces files. It does **not** restart the long-running
//! Python services that are already in memory, so after an upgrade the machine
//! runs new code on disk with old code still loaded: the owner sees no change,
//! and we chase a bug whose fix is sitting on disk, unread.
//!
//! Asking an owner to reboot — or to run a command in a terminal — is not an
//! acceptable answer. The Brain notices the version change itself and restarts
//! its own services, once, silently, when the window opens.

use std::path::{Path, PathBuf};
use std::process::Command;

/// Services that carry the Brain's Python code, and so must be restarted when
/// that code changes. Anything not installed on this machine is skipped.
pub const SERVICE_UNITS: [&str; 2] = ["centurion-gateway.service", "centurion-remote.service"];

/// Deliberately NOT `desktop-build.json`. The launcher rewrites that stamp on
/// every launch, so it describes the code *on disk*; this file records the
/// version the *running* services were started from. Comparing the two is the
/// whole point.
const SERVICES_VERSION_FILE: &str = "services-version";

const LOG_FILE: &str = "service-refresh.log";

/// What happened when we asked systemd about one unit.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UnitOutcome {
    /// systemctl restarted the unit.
    Restarted,
    /// This machine has no unit by that name — nothing to restart.
    Absent,
    /// systemctl was asked and refused.
    Failed(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Refresh {
    /// The running services already match the code on disk.
    UpToDate,
    /// The version changed and every installed service was restarted.
    Refreshed { from: Option<String>, to: String },
    /// The version changed but at least one service would not restart.
    Failed {
        from: Option<String>,
        to: String,
        detail: String,
    },
}

pub fn services_version_path(home: &Path) -> PathBuf {
    home.join("run").join(SERVICES_VERSION_FILE)
}

/// The version the running services were last started from, if we ever saw one.
pub fn recorded_services_version(home: &Path) -> Option<String> {
    let text = std::fs::read_to_string(services_version_path(home)).ok()?;
    let version = text.trim().to_owned();
    if version.is_empty() {
        None
    } else {
        Some(version)
    }
}

fn record_services_version(home: &Path, version: &str) {
    let path = services_version_path(home);
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let _ = std::fs::write(&path, format!("{version}\n"));
}

fn log_line(home: &Path, text: &str) {
    let dir = home.join("logs");
    if std::fs::create_dir_all(&dir).is_err() {
        return;
    }
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let previous = std::fs::read_to_string(dir.join(LOG_FILE)).unwrap_or_default();
    let _ = std::fs::write(dir.join(LOG_FILE), format!("{previous}{stamp} {text}\n"));
}

/// Compare `installed` (the code on disk) with what the running services were
/// started from, and restart them if they differ.
///
/// A missing record counts as a difference. On the very first launch after this
/// check ships we cannot prove the services are current, and the two mistakes
/// are not equally bad: a needless restart costs a few seconds at startup, while
/// a wrong "up to date" leaves the owner running the old Brain with no signal at
/// all. So we restart, record, and are honest in the log about which it was.
///
/// The run is injectable so the decision can be tested without touching systemd.
pub fn refresh_at(home: &Path, installed: &str, run: &dyn Fn(&str) -> UnitOutcome) -> Refresh {
    let installed = installed.trim();
    let from = recorded_services_version(home);

    // No trustworthy version to compare — do not restart on a guess.
    if installed.is_empty() || installed == "unknown" {
        return Refresh::UpToDate;
    }
    if from.as_deref() == Some(installed) {
        return Refresh::UpToDate;
    }

    let mut failures: Vec<String> = Vec::new();
    for unit in SERVICE_UNITS {
        match run(unit) {
            UnitOutcome::Restarted | UnitOutcome::Absent => {}
            UnitOutcome::Failed(detail) => failures.push(format!("{unit}: {detail}")),
        }
    }

    if failures.is_empty() {
        record_services_version(home, installed);
        Refresh::Refreshed {
            from,
            to: installed.to_owned(),
        }
    } else {
        // Deliberately do not record. The record means "the services are running
        // this version", and they are not — so the next launch tries again
        // rather than settling into a lie.
        Refresh::Failed {
            from,
            to: installed.to_owned(),
            detail: failures.join("; "),
        }
    }
}

fn systemctl_restart(unit: &str) -> UnitOutcome {
    // A unit that is not installed must not be reported as a failure; it just
    // means this machine has nothing by that name to restart.
    if let Ok(show) = Command::new("systemctl")
        .args(["--user", "show", unit, "-p", "LoadState"])
        .output()
    {
        if String::from_utf8_lossy(&show.stdout).contains("LoadState=not-found") {
            return UnitOutcome::Absent;
        }
    }
    match Command::new("systemctl")
        .args(["--user", "restart", unit])
        .output()
    {
        Ok(output) if output.status.success() => UnitOutcome::Restarted,
        Ok(output) => {
            let detail = String::from_utf8_lossy(&output.stderr).trim().to_owned();
            UnitOutcome::Failed(if detail.is_empty() {
                format!("systemctl --user restart {unit} failed")
            } else {
                detail
            })
        }
        Err(error) => UnitOutcome::Failed(error.to_string()),
    }
}

pub fn refresh_if_stale(home: &Path, installed: &str) -> Refresh {
    refresh_at(home, installed, &systemctl_restart)
}

/// Called once as the Brain window opens. Never blocks the UI, never fails
/// loudly — the outcome goes to `~/.centurion/logs/service-refresh.log`.
pub fn refresh_services_in_background(installed: String) {
    std::thread::spawn(move || {
        let home = PathBuf::from(crate::bridge_actions::resolve_centurion_home());
        match refresh_if_stale(&home, &installed) {
            Refresh::UpToDate => {}
            Refresh::Refreshed { from, to } => log_line(
                &home,
                &format!(
                    "restarted {} : {} -> {to}",
                    SERVICE_UNITS.join(", "),
                    from.as_deref().unwrap_or("unrecorded")
                ),
            ),
            Refresh::Failed { from, to, detail } => log_line(
                &home,
                &format!(
                    "FAILED to restart after {} -> {to}: {detail}",
                    from.as_deref().unwrap_or("unrecorded")
                ),
            ),
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    fn temp_home(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "centurion-freshness-{tag}-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("temp home");
        dir
    }

    #[test]
    fn matching_version_does_not_restart_anything() {
        let home = temp_home("up-to-date");
        record_services_version(&home, "6.0.9");
        let asked: RefCell<Vec<String>> = RefCell::new(Vec::new());
        let outcome = refresh_at(&home, "6.0.9", &|unit| {
            asked.borrow_mut().push(unit.to_owned());
            UnitOutcome::Restarted
        });
        assert_eq!(outcome, Refresh::UpToDate);
        assert!(
            asked.borrow().is_empty(),
            "nothing should have been asked of systemd"
        );
    }

    #[test]
    fn an_absent_record_is_treated_as_stale_and_restarts_once() {
        let home = temp_home("first-run");
        let asked: RefCell<Vec<String>> = RefCell::new(Vec::new());
        let outcome = refresh_at(&home, "6.0.9", &|unit| {
            asked.borrow_mut().push(unit.to_owned());
            UnitOutcome::Restarted
        });
        assert_eq!(
            outcome,
            Refresh::Refreshed {
                from: None,
                to: "6.0.9".to_owned()
            }
        );
        assert_eq!(asked.borrow().len(), SERVICE_UNITS.len());
        assert_eq!(recorded_services_version(&home).as_deref(), Some("6.0.9"));
    }

    #[test]
    fn a_changed_version_restarts_and_reports_both_ends() {
        let home = temp_home("changed");
        record_services_version(&home, "6.0.7");
        let outcome = refresh_at(&home, "6.0.9", &|_| UnitOutcome::Restarted);
        assert_eq!(
            outcome,
            Refresh::Refreshed {
                from: Some("6.0.7".to_owned()),
                to: "6.0.9".to_owned()
            }
        );
        assert_eq!(recorded_services_version(&home).as_deref(), Some("6.0.9"));
    }

    #[test]
    fn a_unit_this_machine_does_not_have_is_not_a_failure() {
        let home = temp_home("absent-unit");
        record_services_version(&home, "6.0.7");
        let outcome = refresh_at(&home, "6.0.9", &|unit| {
            if unit == "centurion-remote.service" {
                UnitOutcome::Absent
            } else {
                UnitOutcome::Restarted
            }
        });
        assert!(matches!(outcome, Refresh::Refreshed { .. }));
        assert_eq!(recorded_services_version(&home).as_deref(), Some("6.0.9"));
    }

    #[test]
    fn a_service_that_will_not_restart_is_reported_and_not_recorded() {
        let home = temp_home("failed");
        record_services_version(&home, "6.0.7");
        let outcome = refresh_at(&home, "6.0.9", &|unit| {
            if unit == "centurion-gateway.service" {
                UnitOutcome::Failed("Unit not active".to_owned())
            } else {
                UnitOutcome::Restarted
            }
        });
        match outcome {
            Refresh::Failed { detail, from, to } => {
                assert_eq!(from.as_deref(), Some("6.0.7"));
                assert_eq!(to, "6.0.9");
                assert!(
                    detail.contains("centurion-gateway.service"),
                    "detail was {detail}"
                );
            }
            other => panic!("expected Failed, got {other:?}"),
        }
        // The record must not claim a version the services are not running, or
        // the next launch would skip the retry.
        assert_eq!(recorded_services_version(&home).as_deref(), Some("6.0.7"));
    }

    #[test]
    fn an_unreadable_installed_version_is_left_alone() {
        let home = temp_home("unknown");
        record_services_version(&home, "6.0.7");
        let asked: RefCell<Vec<String>> = RefCell::new(Vec::new());
        for candidate in ["", "   ", "unknown"] {
            let outcome = refresh_at(&home, candidate, &|unit| {
                asked.borrow_mut().push(unit.to_owned());
                UnitOutcome::Restarted
            });
            assert_eq!(outcome, Refresh::UpToDate, "candidate {candidate:?}");
        }
        assert!(asked.borrow().is_empty());
        assert_eq!(recorded_services_version(&home).as_deref(), Some("6.0.7"));
    }

    #[test]
    fn the_record_survives_a_second_check_in_the_same_version() {
        let home = temp_home("idempotent");
        let runs = RefCell::new(0usize);
        let run = |_unit: &str| {
            *runs.borrow_mut() += 1;
            UnitOutcome::Restarted
        };
        assert!(matches!(
            refresh_at(&home, "6.0.9", &run),
            Refresh::Refreshed { .. }
        ));
        let after_first = *runs.borrow();
        assert_eq!(after_first, SERVICE_UNITS.len());
        assert_eq!(refresh_at(&home, "6.0.9", &run), Refresh::UpToDate);
        assert_eq!(
            *runs.borrow(),
            after_first,
            "a repeat check must not restart again"
        );
    }
}
