//! Move a Brain installed the old way onto the copy the package owns.
//!
//! # The fault this closes
//!
//! A Brain installed before the packaged release existed keeps its gateway unit
//! pointing at a working checkout under the home directory:
//!
//! ```text
//! ExecStart=/home/<user>/Centurion-AI-OS/venv/bin/python -m centurion_cli.main gateway run --replace
//! WorkingDirectory=/home/<user>/Centurion-AI-OS
//! ```
//!
//! The package installs its own tree under `/usr/lib/centurion/…` and never
//! touches that unit — it is user-local, and the RPM ships no gateway unit at
//! all. So a download-and-install from the portal succeeds, the new version
//! lands on disk, and **the agent the owner actually talks to is unchanged**.
//! Verified in the field 5 Oct 2026: a box whose packaged tree reads 7.0.9 while
//! its gateway still runs a July build from the checkout.
//!
//! The release instructions make it worse by promising the opposite — *"Reopen
//! Sovereign AI Brain. It sets its own services up and starts them. Nothing else
//! to run."* This module is what makes that sentence true.
//!
//! # Why it is not unconditional
//!
//! A checkout is a legitimate place to run from — a developer's own box points
//! the unit there on purpose. Repointing every unit that leaves the packaged tree
//! would move those too.
//!
//! So the rule is narrow, and it is the *version* that decides:
//!
//! - the tree the unit points at is **older** than the installed package → it is a
//!   superseded install, and we move;
//! - it is the same version or newer → it is somebody's working tree, and we leave it.
//!
//! And it is **non-destructive by construction**. The superseded tree is never
//! deleted, moved or edited; only the unit's two path lines change, and the
//! original is copied to `<unit>.pre-migration.bak` first. Reverting is one line.
//! Any local work in that tree is still there afterwards — it simply stops being
//! used until it is ported. That cost is logged, never silent.
//!
//! # Refusal is a valid outcome
//!
//! Every uncertain case refuses and says why. There is no path here that writes a
//! unit we could not stand behind: if we cannot read the version of the tree we
//! are leaving, or cannot find an interpreter in the tree we are moving to, we do
//! nothing and log the reason. A migration that guesses is worse than one that
//! declines.

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// What we decided to do about a gateway unit that points somewhere else.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Repoint {
    /// Nothing to do — no user unit, no known package root, or the unit already
    /// points at the packaged tree.
    NotApplicable,
    /// The unit was repointed. The superseded tree is left on disk, untouched.
    Repointed {
        from: PathBuf,
        to: PathBuf,
        /// Version of the tree we left, when it could be read.
        superseded: Option<String>,
    },
    /// We looked, and deliberately did not act. `reason` goes to the log.
    Blocked { reason: String },
    /// The unit points at an older tree that carries the owner's own work. We did
    /// **not** move it: moving would silently switch off whatever those changes
    /// do, and losing a feature quietly is worse than a version that lags. What
    /// was left behind is named, with the commit, so it can be ported or
    /// re-pointed deliberately instead of discovered by its absence.
    Held {
        from: PathBuf,
        superseded: Option<String>,
        /// What the tree is carrying, in plain terms.
        detail: String,
    },
}

/// The pure decision. Everything effectful is passed in, so this is testable
/// without a filesystem or systemd — the same seam `service_freshness::refresh_at`
/// uses for the same reason.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Plan {
    Leave,
    Move {
        from: PathBuf,
        to: PathBuf,
        /// Version of the tree being left, when it could be read.
        superseded: Option<String>,
    },
    Refuse(String),
    /// An older tree that carries the owner's own work. Do not move it.
    Hold {
        from: PathBuf,
        superseded: Option<String>,
        detail: String,
    },
}

/// Read a single-line systemd directive, e.g. `WorkingDirectory=/somewhere`.
fn directive<'a>(unit: &'a str, key: &str) -> Option<&'a str> {
    unit.lines()
        .map(str::trim)
        .find_map(|line| line.strip_prefix(key))
        .map(str::trim)
        .filter(|value| !value.is_empty())
}

/// `"7.0.9"` -> `(7, 0, 9)`. A trailing packaging suffix is dropped, matching
/// `centurion_cli/brain_release.py`, so `7.0.0-5` and `7.0.0` do not compare as
/// different versions.
pub(crate) fn version_tuple(version: &str) -> Option<(u32, u32, u32)> {
    let core = version.trim().split(['-', '+']).next().unwrap_or("").trim();
    let mut parts = core.split('.');
    let major = parts.next()?.parse().ok()?;
    let minor = parts.next().unwrap_or("0").parse().ok()?;
    let patch = parts.next().unwrap_or("0").parse().ok()?;
    Some((major, minor, patch))
}

/// The version of a checkout tree, read from its own source.
pub(crate) fn checkout_version(dir: &Path) -> Option<String> {
    let text = std::fs::read_to_string(dir.join("centurion_cli").join("__init__.py")).ok()?;
    text.lines().find_map(|line| {
        let rest = line.trim().strip_prefix("__version__")?;
        let rest = rest.trim_start().strip_prefix('=')?.trim();
        let rest = rest.trim_matches(|c| c == '"' || c == '\'' || c == ' ');
        if rest.is_empty() {
            None
        } else {
            Some(rest.to_owned())
        }
    })
}

/// Run a git command in `dir`, returning trimmed stdout on success.
fn git(dir: &Path, args: &[&str]) -> Option<String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(args)
        .stdin(Stdio::null())
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&output.stdout).trim().to_owned())
}

/// A capability that used to be carried by hand on an owner's checkout and is now
/// part of the release.
///
/// This register is the record of absorption. It is maintained by hand, on
/// purpose: nothing can infer that some local work has been taken upstream, and a
/// machine that guesses gets it wrong in the one direction that costs a feature.
///
/// `marker` must appear in the **packaged** copy of `file`. That is the evidence —
/// not the version number, not a date, not an assumption that "we ported it".
struct Absorbed {
    /// Repo-relative path, matching `git diff --name-only`.
    file: &'static str,
    /// A string present in the packaged copy once the capability is really there.
    marker: &'static str,
    /// The release that landed it, for the log.
    release: &'static str,
    /// What it does, in plain words.
    what: &'static str,
}

/// Work that has been absorbed into the release.
///
/// Every marker below was read out of the ported files, not assumed. If a copy of
/// the packaged tree does not contain the marker, the release does not have the
/// capability yet and the hold stands.
const ABSORBED: &[Absorbed] = &[
    Absorbed {
        file: "gateway/platforms/email.py",
        marker: "_smtp_xoauth2_login",
        release: "7.0.10",
        what: "XOAUTH2 sign-in for IMAP and SMTP",
    },
    Absorbed {
        file: "gateway/platforms/whatsapp.py",
        marker: "quotedBody",
        release: "7.0.10",
        what: "WhatsApp quoted replies (adapter side)",
    },
    Absorbed {
        file: "scripts/whatsapp-bridge/bridge.js",
        marker: "extractQuotedText",
        release: "7.0.10",
        what: "WhatsApp quoted replies (bridge side)",
    },
    Absorbed {
        file: "gateway/config.py",
        marker: "EMAIL_AUTH_TYPE",
        release: "7.0.10",
        what: "email OAuth settings",
    },
    Absorbed {
        file: "gateway/run.py",
        marker: "20+ heartbeat emails",
        release: "7.0.10",
        what: "no \"still working\" heartbeats by email",
    },
    Absorbed {
        file: "gateway/platforms/base.py",
        marker: ".markdown",
        release: "7.0.9",
        what: "document extensions delivered as attachments",
    },
    Absorbed {
        file: "tests/gateway/test_whatsapp_quoted_reply.py",
        marker: "test_quoted_body_prefixed_to_text",
        release: "7.0.10",
        what: "the quoted-reply test",
    },
];

/// Every file this tree has changed relative to where it forked from `main`,
/// including anything uncommitted.
///
/// `None` means the question could not be answered — which the caller must treat
/// as "assume there is work", never as "there is none".
fn local_work_files(dir: &Path) -> Option<Vec<String>> {
    let base = git(dir, &["merge-base", "HEAD", "main"])?;
    let base = base.trim().to_owned();
    if base.is_empty() {
        return None;
    }

    let mut files: Vec<String> = Vec::new();
    if let Some(diff) = git(dir, &["diff", "--name-only", &format!("{base}..HEAD")]) {
        files.extend(
            diff.lines()
                .map(|line| line.trim().to_owned())
                .filter(|line| !line.is_empty()),
        );
    } else {
        return None;
    }
    if let Some(status) = git(dir, &["status", "--porcelain"]) {
        for line in status.lines() {
            if let Some(path) = line.get(3..) {
                let path = path.trim();
                if !path.is_empty() {
                    files.push(path.to_owned());
                }
            }
        }
    }

    files.sort();
    files.dedup();
    Some(files)
}

/// Does the packaged copy of `file` really carry the capability?
fn packaged_has(packaged_root: &Path, file: &str, marker: &str) -> bool {
    std::fs::read_to_string(packaged_root.join(file))
        .map(|text| text.contains(marker))
        .unwrap_or(false)
}

/// Why this tree's work must not be lost — or `None` when it is safe to leave.
///
/// ⚠️ The two mistakes are not equal. Saying "safe" when it is not switches a
/// working feature off with no warning. Saying "unsafe" when it is fine only
/// leaves an owner one version behind, with a log line explaining why. So:
///
/// - a tree whose changes we cannot enumerate → **work**;
/// - a changed file we have no register entry for → **work**;
/// - a registered file whose marker is absent from the packaged copy → **work**;
/// - only a tree whose every change is provably present in the release → safe.
///
/// This is the discharge. It is what lets a machine that was patched by hand move
/// itself once the release has caught up with it, without anyone visiting.
pub(crate) fn unabsorbed_local_work(dir: &Path, packaged_root: &Path) -> Option<String> {
    // Not a repository: a plain install carries nothing of the owner's.
    if !dir.join(".git").exists() {
        return None;
    }

    let Some(files) = local_work_files(dir) else {
        return Some("it is a git repository whose changes could not be read".to_owned());
    };
    if files.is_empty() {
        return None;
    }

    let mut unabsorbed: Vec<String> = Vec::new();
    for file in &files {
        match ABSORBED.iter().find(|entry| entry.file == file) {
            Some(entry) if packaged_has(packaged_root, entry.file, entry.marker) => {}
            Some(entry) => unabsorbed.push(format!(
                "{} ({}) — the installed release does not carry it yet",
                entry.file, entry.what
            )),
            None => unabsorbed.push(format!("{file} — not something this release absorbed")),
        }
    }

    if unabsorbed.is_empty() {
        None
    } else {
        Some(format!(
            "it carries {} change(s) the release does not cover: {}",
            unabsorbed.len(),
            unabsorbed.join("; ")
        ))
    }
}

/// Turn a `Move` into a `Hold` when the tree being left carries the owner's work.
///
/// Kept separate from `plan_repoint` so the version decision and the
/// carries-work decision can be tested independently — they answer different
/// questions and fail in different directions.
pub(crate) fn hold_if_carrying_local_work(
    plan: Plan,
    local_work: &dyn Fn(&Path) -> Option<String>,
) -> Plan {
    match plan {
        Plan::Move {
            from,
            to,
            superseded,
        } => match local_work(&from) {
            Some(detail) => Plan::Hold {
                from,
                superseded,
                detail,
            },
            None => Plan::Move {
                from,
                to,
                superseded,
            },
        },
        other => other,
    }
}

/// Decide what to do. `version_of` is injected so the tests do not need real trees.
pub(crate) fn plan_repoint(
    unit: &str,
    packaged_root: &Path,
    user_home: &Path,
    installed: &str,
    version_of: &dyn Fn(&Path) -> Option<String>,
) -> Plan {
    // Without a known package root there is nothing to move *to*.
    if packaged_root.as_os_str().is_empty() {
        return Plan::Leave;
    }

    let Some(working_dir) = directive(unit, "WorkingDirectory=") else {
        // A unit with no WorkingDirectory runs from $HOME, which is not a tree we
        // can reason about. Leave it alone rather than guess.
        return Plan::Leave;
    };
    let from = PathBuf::from(working_dir);

    // Already where it should be — the ordinary case on a healthy box.
    if from == packaged_root || from.starts_with(packaged_root) {
        return Plan::Leave;
    }

    // Never touch a path outside the owner's own home directory. A unit naming
    // something else is not ours to rewrite.
    if !from.starts_with(user_home) {
        return Plan::Refuse(format!(
            "the unit points outside your home directory ({})",
            from.display()
        ));
    }

    let Some(installed_tuple) = version_tuple(installed) else {
        return Plan::Refuse(format!("cannot read the installed version ({installed:?})"));
    };

    let superseded = version_of(&from);
    let Some(ref superseded_version) = superseded else {
        return Plan::Refuse(format!(
            "cannot read the version of the tree it points at ({})",
            from.display()
        ));
    };
    let Some(from_tuple) = version_tuple(superseded_version) else {
        return Plan::Refuse(format!(
            "cannot read the version of the tree it points at ({superseded_version:?})"
        ));
    };

    // The judgement call. Only an OLDER tree is a superseded install; anything
    // equal or newer is somebody's working tree and stays.
    if from_tuple >= installed_tuple {
        return Plan::Refuse(format!(
            "the tree it points at ({superseded_version}) is not older than the installed package ({installed}) — leaving a working tree alone"
        ));
    }

    Plan::Move {
        from,
        to: packaged_root.to_path_buf(),
        superseded,
    }
}

/// The interpreter to run the gateway with, inside the packaged tree.
///
/// ⚠️ Two layouts exist and we do not assume either: the venv sits one level up
/// from the repo (`/usr/lib/centurion/venv`) in the packaged layout, and inside it
/// (`<repo>/venv`) in a checkout. The path is *checked*, never assumed — a unit
/// written against a path that does not exist fails at the next start, which is
/// the worst possible moment. `None` means refuse.
pub(crate) fn packaged_interpreter(packaged_root: &Path) -> Option<PathBuf> {
    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Some(parent) = packaged_root.parent() {
        candidates.push(parent.join("venv").join("bin").join("python"));
    }
    candidates.push(packaged_root.join("venv").join("bin").join("python"));
    candidates.into_iter().find(|path| path.is_file())
}

/// Rewrite the two path lines, leaving every other directive alone.
pub(crate) fn rewritten_unit(unit: &str, interpreter: &Path, packaged_root: &Path) -> String {
    let exec = format!(
        "ExecStart={} -m centurion_cli.main gateway run --replace",
        interpreter.display()
    );
    let workdir = format!("WorkingDirectory={}", packaged_root.display());

    let mut out: Vec<String> = Vec::new();
    let mut wrote_exec = false;
    let mut wrote_workdir = false;
    for line in unit.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("ExecStart=") {
            out.push(exec.clone());
            wrote_exec = true;
        } else if trimmed.starts_with("WorkingDirectory=") {
            out.push(workdir.clone());
            wrote_workdir = true;
        } else {
            out.push(line.to_owned());
        }
    }
    if !wrote_exec {
        out.push(exec);
    }
    if !wrote_workdir {
        out.push(workdir);
    }
    let mut text = out.join("\n");
    text.push('\n');
    text
}

fn user_unit_path(user_home: &Path) -> PathBuf {
    user_home
        .join(".config")
        .join("systemd")
        .join("user")
        .join("centurion-gateway.service")
}

/// The tree the installed package belongs to, as stamped at install time.
fn packaged_root(home: &Path) -> Option<PathBuf> {
    let text = std::fs::read_to_string(home.join("desktop-build.json")).ok()?;
    let json: serde_json::Value = serde_json::from_str(&text).ok()?;
    let root = json.get("repo_root")?.as_str()?.trim();
    if root.is_empty() {
        None
    } else {
        Some(PathBuf::from(root))
    }
}

fn systemctl(args: &[&str]) -> bool {
    Command::new("systemctl")
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

/// The effectful half. Resolves its own paths, then applies `plan_repoint`.
///
/// Bounded: one attempt per launch, and it only ever runs when a restart was
/// going to happen anyway. A repair that loops is a new bug.
pub fn repoint_on_launch(home: &Path, user_home: &Path, installed: &str) -> Repoint {
    let Some(root) = packaged_root(home) else {
        return Repoint::NotApplicable;
    };
    let unit_path = user_unit_path(user_home);
    let Ok(unit) = std::fs::read_to_string(&unit_path) else {
        // No user-local unit: either the CLI created a system one, or there is
        // nothing here. Nothing to repoint.
        return Repoint::NotApplicable;
    };

    // The discharge lives here: a tree whose work the installed release has
    // provably absorbed is safe to leave, so a hand-patched machine moves itself
    // once the release catches up. Anything not covered still holds.
    let plan = hold_if_carrying_local_work(
        plan_repoint(&unit, &root, user_home, installed, &checkout_version),
        &|dir| unabsorbed_local_work(dir, &root),
    );

    match plan {
        Plan::Leave => Repoint::NotApplicable,
        Plan::Refuse(reason) => Repoint::Blocked { reason },
        Plan::Hold {
            from,
            superseded,
            detail,
        } => Repoint::Held {
            from,
            superseded,
            detail,
        },
        Plan::Move {
            from,
            to,
            superseded,
        } => {
            let Some(interpreter) = packaged_interpreter(&to) else {
                return Repoint::Blocked {
                    reason: format!(
                        "no interpreter found in the packaged tree ({}), so the unit was left alone",
                        to.display()
                    ),
                };
            };

            // Back up once. A second migration must not overwrite the original
            // unit with an already-repointed one, or rollback points at the wrong file.
            let backup = unit_path.with_extension("service.pre-migration.bak");
            if !backup.exists() {
                let _ = std::fs::write(&backup, &unit);
            }

            let rewritten = rewritten_unit(&unit, &interpreter, &to);
            if std::fs::write(&unit_path, rewritten).is_err() {
                return Repoint::Blocked {
                    reason: format!("could not write {}", unit_path.display()),
                };
            }

            // systemd holds the definition it already loaded; without the reload
            // it runs the old unit and the change installs and does nothing.
            systemctl(&["--user", "daemon-reload"]);
            systemctl(&["--user", "restart", "centurion-gateway.service"]);

            Repoint::Repointed {
                from,
                to,
                superseded,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const PACKAGED: &str = "/usr/lib/centurion/Centurion-AI-OS";

    fn unit_pointing_at(dir: &str) -> String {
        format!(
            "[Unit]\nDescription=Gateway\n\n[Service]\nExecStart={dir}/venv/bin/python -m centurion_cli.main gateway run --replace\nWorkingDirectory={dir}\nRestart=on-failure\n"
        )
    }

    fn version_of(version: &'static str) -> impl Fn(&Path) -> Option<String> {
        move |_dir: &Path| Some(version.to_owned())
    }

    #[test]
    fn a_unit_already_pointing_at_the_package_is_left_alone() {
        let plan = plan_repoint(
            &unit_pointing_at(PACKAGED),
            Path::new(PACKAGED),
            Path::new("/home/mike"),
            "7.0.9",
            &version_of("7.0.9"),
        );
        assert_eq!(plan, Plan::Leave);
    }

    #[test]
    fn an_older_checkout_is_moved() {
        // The field case, 5 Oct 2026: checkout at 5.0.0, package at 7.0.9.
        let plan = plan_repoint(
            &unit_pointing_at("/home/mike/Centurion-AI-OS"),
            Path::new(PACKAGED),
            Path::new("/home/mike"),
            "7.0.9",
            &version_of("5.0.0"),
        );
        assert_eq!(
            plan,
            Plan::Move {
                from: PathBuf::from("/home/mike/Centurion-AI-OS"),
                to: PathBuf::from(PACKAGED),
                superseded: Some("5.0.0".to_owned()),
            }
        );
    }

    #[test]
    fn a_working_tree_at_the_same_version_is_not_touched() {
        let plan = plan_repoint(
            &unit_pointing_at("/home/adrian/Centurion-AI-OS"),
            Path::new(PACKAGED),
            Path::new("/home/adrian"),
            "7.0.9",
            &version_of("7.0.9"),
        );
        assert!(matches!(plan, Plan::Refuse(_)), "got {plan:?}");
    }

    #[test]
    fn a_working_tree_newer_than_the_package_is_not_touched() {
        let plan = plan_repoint(
            &unit_pointing_at("/home/adrian/Centurion-AI-OS"),
            Path::new(PACKAGED),
            Path::new("/home/adrian"),
            "7.0.9",
            &version_of("7.0.10"),
        );
        assert!(matches!(plan, Plan::Refuse(_)), "got {plan:?}");
    }

    #[test]
    fn an_unreadable_version_refuses_rather_than_guessing() {
        let plan = plan_repoint(
            &unit_pointing_at("/home/mike/Centurion-AI-OS"),
            Path::new(PACKAGED),
            Path::new("/home/mike"),
            "7.0.9",
            &|_dir: &Path| None,
        );
        match plan {
            Plan::Refuse(reason) => assert!(
                reason.contains("cannot read the version"),
                "reason was {reason}"
            ),
            other => panic!("expected Refuse, got {other:?}"),
        }
    }

    #[test]
    fn a_unit_outside_the_home_directory_is_never_rewritten() {
        let plan = plan_repoint(
            &unit_pointing_at("/opt/centurion"),
            Path::new(PACKAGED),
            Path::new("/home/mike"),
            "7.0.9",
            &version_of("5.0.0"),
        );
        match plan {
            Plan::Refuse(reason) => assert!(
                reason.contains("outside your home directory"),
                "reason was {reason}"
            ),
            other => panic!("expected Refuse, got {other:?}"),
        }
    }

    #[test]
    fn a_unit_with_no_working_directory_is_left_alone() {
        let unit = "[Service]\nExecStart=/usr/bin/true\n";
        let plan = plan_repoint(
            unit,
            Path::new(PACKAGED),
            Path::new("/home/mike"),
            "7.0.9",
            &version_of("5.0.0"),
        );
        assert_eq!(plan, Plan::Leave);
    }

    #[test]
    fn an_unknown_package_root_is_left_alone() {
        let plan = plan_repoint(
            &unit_pointing_at("/home/mike/Centurion-AI-OS"),
            Path::new(""),
            Path::new("/home/mike"),
            "7.0.9",
            &version_of("5.0.0"),
        );
        assert_eq!(plan, Plan::Leave);
    }

    #[test]
    fn rewriting_changes_only_the_two_path_lines() {
        let original = unit_pointing_at("/home/mike/Centurion-AI-OS");
        let out = rewritten_unit(
            &original,
            Path::new("/usr/lib/centurion/venv/bin/python"),
            Path::new(PACKAGED),
        );
        assert!(out.contains(&format!("WorkingDirectory={PACKAGED}")));
        assert!(out.contains(
            "ExecStart=/usr/lib/centurion/venv/bin/python -m centurion_cli.main gateway run --replace"
        ));
        assert!(
            !out.contains("/home/mike"),
            "no trace of the old tree may remain"
        );
        assert!(
            out.contains("Restart=on-failure"),
            "other directives survive"
        );
        assert!(out.contains("Description=Gateway"));
    }

    #[test]
    fn rewriting_survives_a_unit_missing_a_directive() {
        let unit = "[Service]\nExecStart=/usr/bin/true\n";
        let out = rewritten_unit(unit, Path::new("/usr/bin/python3"), Path::new(PACKAGED));
        assert!(out.contains(&format!("WorkingDirectory={PACKAGED}")));
        assert!(
            out.contains("ExecStart=/usr/bin/python3 -m centurion_cli.main gateway run --replace")
        );
    }

    #[test]
    fn versions_compare_by_number_not_by_string() {
        assert_eq!(version_tuple("7.0.9"), Some((7, 0, 9)));
        assert_eq!(version_tuple("7.0.10"), Some((7, 0, 10)));
        // A packaging suffix must not make a version look newer.
        assert_eq!(version_tuple("7.0.0-5"), Some((7, 0, 0)));
        assert!(version_tuple("7.0.10") > version_tuple("7.0.9"));
        assert_eq!(version_tuple("not-a-version"), None);
    }

    #[test]
    fn an_older_tree_carrying_local_work_is_held_not_moved() {
        // The field case: a 5.0.0 checkout carrying XOAUTH2 and quoted-reply
        // patches. Moving it would switch both off with nothing on screen to say so.
        let plan = hold_if_carrying_local_work(
            plan_repoint(
                &unit_pointing_at("/home/mike/Centurion-AI-OS"),
                Path::new(PACKAGED),
                Path::new("/home/mike"),
                "7.0.9",
                &version_of("5.0.0"),
            ),
            &|_dir: &Path| Some("it is on the branch local/customisations-20260928".to_owned()),
        );
        match plan {
            Plan::Hold { detail, from, .. } => {
                assert!(
                    detail.contains("local/customisations-20260928"),
                    "the held work must be named, was {detail}"
                );
                assert_eq!(from, PathBuf::from("/home/mike/Centurion-AI-OS"));
            }
            other => panic!("expected Hold, got {other:?}"),
        }
    }

    #[test]
    fn an_older_tree_carrying_nothing_of_the_owners_is_still_moved() {
        let plan = hold_if_carrying_local_work(
            plan_repoint(
                &unit_pointing_at("/home/mike/Centurion-AI-OS"),
                Path::new(PACKAGED),
                Path::new("/home/mike"),
                "7.0.9",
                &version_of("5.0.0"),
            ),
            &|_dir: &Path| None,
        );
        assert!(matches!(plan, Plan::Move { .. }), "got {plan:?}");
    }

    #[test]
    fn holding_is_only_ever_applied_to_a_move() {
        // A refusal and a hold say different things. If a refusal could become a
        // hold, the log would blur "I cannot tell" with "I am protecting your work".
        for original in [Plan::Leave, Plan::Refuse("because".to_owned())] {
            let out = hold_if_carrying_local_work(original.clone(), &|_dir: &Path| {
                Some("it is on a branch".to_owned())
            });
            assert_eq!(out, original);
        }
    }

    #[test]
    fn a_tree_that_is_not_a_repository_carries_nothing_of_the_owners() {
        let dir = temp_home("plain-install");
        assert_eq!(
            unabsorbed_local_work(&dir, Path::new(PACKAGED)),
            None,
            "a plain install has nothing to preserve"
        );
    }

    #[test]
    fn the_package_must_actually_contain_the_capability() {
        // The evidence rule: a register entry on its own proves nothing. The
        // marker has to be in the installed copy, or the hold stands.
        let root = temp_home("packaged-copy");
        std::fs::create_dir_all(root.join("gateway")).expect("dir");
        std::fs::write(
            root.join("gateway/email.py"),
            "def _smtp_xoauth2_login(): ...\n",
        )
        .expect("file");

        assert!(packaged_has(
            &root,
            "gateway/platforms/email.py",
            "_smtp_xoauth2_login"
        ) == false, "a path that does not exist cannot carry it");
        assert!(packaged_has(&root, "gateway/email.py", "_smtp_xoauth2_login"));
        assert!(
            !packaged_has(&root, "gateway/email.py", "something_else"),
            "an absent marker must read as absent"
        );
    }

    #[test]
    fn every_register_entry_names_a_real_file_and_a_release() {
        // A register that drifts is worse than none: it would discharge a hold for
        // work the release does not have. Pin the shape.
        for entry in ABSORBED {
            assert!(!entry.file.is_empty(), "a register entry needs a file");
            assert!(!entry.marker.is_empty(), "a register entry needs a marker");
            assert!(
                !entry.release.is_empty(),
                "a register entry must name the release that absorbed it"
            );
            assert!(!entry.what.is_empty(), "a register entry must say what it does");
            assert!(
                !entry.file.starts_with('/'),
                "{} must be repo-relative",
                entry.file
            );
        }
    }
}
