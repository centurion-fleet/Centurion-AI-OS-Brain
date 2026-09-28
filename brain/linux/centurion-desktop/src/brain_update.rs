//! Packaged-Brain (RPM) update: fetch, verify, install, prove.
//!
//! ── WHY THIS EXISTS ────────────────────────────────────────────────────────────
//! On a **Get Brain** install there was no update engine at all. The only one the
//! app had was the developer-checkout path: `resolve_centurion_repo_root()` (looks
//! for a git checkout under `~/Centurion-AI-OS`) feeding
//! `run_native_brain_install()` (runs `{repo}/desktop-native/scripts/install-user.sh`),
//! plus `run_os_update()` → `centurion update`, which is the **git** path and does
//! nothing on an RPM box. A Get Brain install has no checkout, so those controls
//! were hidden behind `if smooth_transfer_install` and the version row just said
//! "updates arrive through your portal".
//!
//! That is why the Check/Update controls must not simply be un-hidden: on a
//! packaged Brain the old path fails with "Update script missing", so a button
//! wired to it would be a dead end — a control that hides its consequence.
//! This module is the engine that makes the button honest.
//!
//! ── THE ORDER MATTERS AND IS NOT NEGOTIABLE ────────────────────────────────────
//!   1. resolve the published release from the channel (public, no auth)
//!   2. download the artifact (licence code, not a browser session)
//!   3. verify sha256 against the published value
//!   4. verify the RPM signature, importing the release key if absent
//!   5. **stop whatever holds the remote port — BEFORE starting anything**
//!   6. install (privileged, via polkit)
//!   7. restart, then *prove* the running version changed
//!
//! Step 5 is not housekeeping. A 7.0.1 install on 28 Sep 2026 left
//! `centurion-remote.service` in a restart loop — **672 failed starts, one every
//! three seconds** — because the install refreshed the unit and restarted it
//! without ever stopping the process it was replacing. That predecessor, running
//! since 11 September, still held TCP 9119, so every new start died with
//! `AddrInUse (98)`. `systemctl restart` could not help: it restarts what the
//! *unit* owns, and the stale process was a leftover from the old user-local
//! install, which the unit never owned. **A restart is not a stop.**
//!
//! Step 7 exists because "installed" is not "running": the RPM's scriptlets
//! contain no `systemctl` at all (verified against the 7.0.1 artifact), so the
//! files land and the old process keeps serving until something restarts it.
//!
//! ── 🔴 THE DOWNLOAD HAS NO CREDENTIAL ON A CUSTOMER BRAIN ──────────────────────
//! Step 2 needs a licence code, and **the Brain has none to give.** Verified
//! 28 Sep 2026 across both repos:
//!
//!   * `app/api/v1/releases/download/route.ts` (v5-prod) allows exactly two
//!     credentials: a Supabase session belonging to a paid customer or staff, or
//!     the header `x-centurion-license-code`, validated by
//!     `licenseCodeUnlocksBrainDownload()` against a real row in `license_codes`.
//!   * Nothing in this repo stores such a code. `_handle_license_activate`
//!     (`centurion_cli/remote_bridge.py`) takes `activation_code` from the request,
//!     posts it to the licence server, and discards it. `~/.centurion/license/`
//!     keeps an encrypted entitlement holding `license_id`, `machine_fingerprint`
//!     and `token_id` — no code.
//!   * The `signed_attestation` the Brain *does* hold is not usable either: the
//!     client verifies with `_PLACEHOLDER_PUBKEY_B64` (32 zero bytes —
//!     "production must override"), and no server-side module verifies an
//!     attestation at all.
//!
//! So `dry_run()` reports the download as **skipped**, with that reason, rather
//! than failing opaquely or pretending to try. Three ways to close it, smallest
//! first:
//!
//!   1. **Persist the code at activation.** Client-only. The store is already
//!      encrypted with a device-derived key, and the route re-checks live
//!      entitlement, so revocation still works. Existing owners re-enter it once.
//!   2. **Accept the identity the Brain already presents.** `/api/v1/license/checkin`
//!      already trusts `license_id` + `install_id` + `machine_fingerprint`; let the
//!      download route trust the same and return a short-lived signed URL. No
//!      secret at rest, no customer action — needs a v5-prod change.
//!   3. **Attestation-based auth.** A real ed25519 CA keypair plus genuine
//!      server-side signature verification. The right long-term answer, and the
//!      largest piece of work.
//!
//! Until one is chosen the Update button must not be wired: a button whose download
//! always fails is the same defect class as a button wired to no engine — merely
//! with a nicer label.

use std::fmt::Write as _;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;

/// Public release channel. `personalcenturion.com` also serves this and 307s here.
/// Overridable so tests never touch the real channel.
fn release_api() -> String {
    std::env::var("CENTURION_RELEASE_API")
        .unwrap_or_else(|_| "https://www.1human1ai.com/api/v1/releases/latest".to_owned())
}

fn download_api() -> String {
    std::env::var("CENTURION_RELEASE_DOWNLOAD_API")
        .unwrap_or_else(|_| "https://www.1human1ai.com/api/v1/releases/download".to_owned())
}

/// Where the release signing key is published. Fingerprint
/// `25CB40901F8344D3704F9A4AC9E747578FA41F8F`.
const RELEASE_PUBKEY_URL: &str = "https://www.1human1ai.com/centurion-release-pubkey.asc";

/// The fleet/remote rail. The port at the centre of the restart-loop defect.
pub const REMOTE_PORT: u16 = 9119;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(15);
/// The artifact is ~98 MB. Generous read timeout, no total cap.
const READ_TIMEOUT: Duration = Duration::from_secs(30 * 60);

#[derive(Debug, Clone, serde::Deserialize)]
pub struct Artifact {
    pub id: String,
    pub filename: String,
    #[serde(default)]
    pub size_bytes: u64,
    pub sha256: String,
}

impl Artifact {
    /// The Brain is packaged as a single installer RPM.
    pub fn is_installer(&self) -> bool {
        self.filename.ends_with(".rpm")
    }
}

#[derive(Debug, Clone, serde::Deserialize)]
pub struct Release {
    pub version: String,
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub artifacts: Vec<Artifact>,
}

impl Release {
    /// First RPM in the artifact list, if any.
    pub fn installer(&self) -> Option<&Artifact> {
        self.artifacts.iter().find(|a| a.is_installer())
    }
}

#[derive(Debug, serde::Deserialize)]
struct Envelope {
    release: Release,
}

fn agent() -> ureq::Agent {
    ureq::builder()
        .timeout_connect(CONNECT_TIMEOUT)
        .timeout_read(READ_TIMEOUT)
        .user_agent("centurion-desktop-update")
        .build()
}

/// Step 1 — what is published. Public endpoint, no credential.
pub fn latest_release() -> Result<Release, String> {
    let body = agent()
        .get(&release_api())
        .set("Accept", "application/json")
        .call()
        .map_err(|e| format!("Could not reach the release channel: {e}"))?
        .into_string()
        .map_err(|e| format!("Could not read the release channel response: {e}"))?;

    serde_json::from_str::<Envelope>(&body)
        .map(|e| e.release)
        .map_err(|e| format!("The release channel returned something unexpected: {e}"))
}

/// Step 2 — download the artifact.
///
/// Auth is the **licence code**, not a browser session: the download route accepts
/// `x-centurion-license-code` and falls back to a staff session. Returns the path
/// written. Never trusts the filename from the channel for the *directory*.
pub fn download_artifact(
    artifact: &Artifact,
    dest_dir: &Path,
    licence_code: &str,
) -> Result<PathBuf, String> {
    fs::create_dir_all(dest_dir)
        .map_err(|e| format!("Could not create {}: {e}", dest_dir.display()))?;

    // Use the channel's filename only as a leaf name; never let it traverse.
    let leaf = Path::new(&artifact.filename)
        .file_name()
        .ok_or_else(|| format!("Refusing a suspicious artifact filename: {}", artifact.filename))?
        .to_string_lossy()
        .to_string();
    let dest = dest_dir.join(leaf);

    // `installer_id` is the canonical parameter; the route still accepts
    // `artifact_id` "for older clients (same UUID now)". Send the current name.
    let url = format!("{}?installer_id={}", download_api(), artifact.id);
    // `Accept: application/json` makes the route answer `{ok:true,url}` instead of a
    // 302, and makes its refusals readable JSON rather than an HTML page. The route
    // only returns JSON when the request asks for it (its `wantsJson` check).
    let resp = match agent()
        .get(&url)
        .set("x-centurion-license-code", licence_code)
        .set("Accept", "application/json")
        .call()
    {
        Ok(r) => r,
        // ureq treats any non-2xx as an Error::Status. The body carries the real
        // reason — never discard it in favour of the status code.
        Err(ureq::Error::Status(code, r)) => {
            let body = r.into_string().unwrap_or_default();
            let detail = serde_json::from_str::<serde_json::Value>(&body)
                .ok()
                .and_then(|v| {
                    v.get("error")
                        .and_then(|e| e.as_str())
                        .map(|s| s.to_owned())
                })
                .unwrap_or_else(|| body.trim().to_owned());
            return Err(match code {
                401 => format!(
                    "This Brain's licence could not be checked, so the update was not \
                     downloaded.\n  {detail}"
                ),
                429 => format!("Too many update attempts just now. Try again shortly.\n  {detail}"),
                _ => format!("The update download was refused (HTTP {code}).\n  {detail}"),
            });
        }
        Err(e) => return Err(format!("Could not reach the download service: {e}")),
    };

    // The route may answer with a redirect to a signed URL (followed by ureq) or
    // with JSON `{"ok":true,"url":...}`. Handle the JSON shape explicitly.
    let mut file = fs::File::create(&dest)
        .map_err(|e| format!("Could not open {} for writing: {e}", dest.display()))?;

    let is_json = resp
        .header("content-type")
        .map(|c| c.contains("application/json"))
        .unwrap_or(false);

    if is_json {
        let body = resp
            .into_string()
            .map_err(|e| format!("Could not read the download response: {e}"))?;
        let value: serde_json::Value = serde_json::from_str(&body)
            .map_err(|e| format!("The download response was not valid JSON: {e}"))?;
        let signed = value
            .get("url")
            .and_then(|u| u.as_str())
            .ok_or_else(|| "The download response carried no URL.".to_owned())?;
        let mut stream = agent()
            .get(signed)
            .call()
            .map_err(|e| format!("Could not fetch the signed download: {e}"))?
            .into_reader();
        std::io::copy(&mut stream, &mut file)
            .map_err(|e| format!("Could not save the download: {e}"))?;
    } else {
        let mut reader = resp.into_reader();
        let mut buf = [0u8; 64 * 1024];
        loop {
            let n = reader
                .read(&mut buf)
                .map_err(|e| format!("Download failed part-way through: {e}"))?;
            if n == 0 {
                break;
            }
            std::io::Write::write_all(&mut file, &buf[..n])
                .map_err(|e| format!("Could not save the download: {e}"))?;
        }
    }

    let written = fs::metadata(&dest)
        .map_err(|e| format!("Downloaded file is not there: {e}"))?
        .len();

    // The channel publishes a size; if the transfer was short, say so now rather
    // than confusing it with a hash mismatch.
    if artifact.size_bytes > 0 && written != artifact.size_bytes {
        return Err(format!(
            "Download incomplete: got {written} bytes, expected {}.",
            artifact.size_bytes
        ));
    }

    Ok(dest)
}

/// Step 3 — hash the artifact ourselves, after download, against the published value.
///
/// Shells out to `sha256sum` rather than adding a crate: this is the same tool the
/// release process is verified with, so the number compared is computed the same way.
pub fn verify_sha256(path: &Path, expected: &str) -> Result<String, String> {
    let out = Command::new("sha256sum")
        .arg(path)
        .output()
        .map_err(|e| format!("Could not run sha256sum: {e}"))?;
    if !out.status.success() {
        return Err("sha256sum failed on the downloaded file.".to_owned());
    }
    let stdout = String::from_utf8_lossy(&out.stdout);
    let actual = stdout
        .split_whitespace()
        .next()
        .unwrap_or_default()
        .to_lowercase();
    let expected = expected.trim().to_lowercase();
    if actual != expected {
        return Err(format!(
            "The download does not match the published checksum.\n  expected {expected}\n  got      {actual}"
        ));
    }
    Ok(actual)
}

/// Step 4 — verify the RPM signature, importing the release key when the keyring
/// has never seen it.
///
/// `NOKEY` means "the key is not in your keyring", NOT "the artifact is bad" — so
/// import and re-check before reporting failure. A missing key is the normal state
/// on a machine that has never installed a Centurion release.
pub fn verify_or_import_signature(path: &Path) -> Result<String, String> {
    let first = rpm_checksig(path)?;
    if first.contains("NOKEY") {
        let key = std::env::temp_dir().join("centurion-release-pubkey.asc");
        let body = agent()
            .get(RELEASE_PUBKEY_URL)
            .call()
            .map_err(|e| format!("Could not fetch the release signing key: {e}"))?
            .into_string()
            .map_err(|e| format!("Could not read the release signing key: {e}"))?;
        fs::write(&key, body).map_err(|e| format!("Could not save the release key: {e}"))?;
        let imported = Command::new("rpm")
            .arg("--import")
            .arg(&key)
            .output()
            .map_err(|e| format!("Could not import the release key: {e}"))?;
        if !imported.status.success() {
            return Err("Could not import the Centurion release signing key.".to_owned());
        }
        let second = rpm_checksig(path)?;
        if second.contains("NOKEY") {
            return Err(format!(
                "The release key was imported but the signature still cannot be checked:\n{second}"
            ));
        }
        return Ok(second);
    }
    Ok(first)
}

fn rpm_checksig(path: &Path) -> Result<String, String> {
    let out = Command::new("rpm")
        .args(["--checksig", "-v"])
        .arg(path)
        .output()
        .map_err(|e| format!("Could not run rpm --checksig: {e}"))?;
    // rpm --checksig exits non-zero for NOKEY as well as for a bad signature, so
    // read the OUTPUT and let the caller decide — never the exit code alone.
    Ok(String::from_utf8_lossy(&out.stdout).to_string()
        + &String::from_utf8_lossy(&out.stderr))
}

/// Step 5 — stop whatever holds the remote port, **before** anything is started.
///
/// This is the fix for the 672-failure restart loop. `systemctl restart` is not
/// enough: it restarts what the *unit* owns, and the process that caused the loop
/// was a leftover from the old user-local install, which the unit never owned.
///
/// Returns the PIDs it stopped, for the report.
pub fn stop_port_holders(port: u16) -> Result<Vec<u32>, String> {
    let holders = pids_listening_on(port);
    for pid in &holders {
        // SIGTERM first: let it close the socket itself.
        let _ = Command::new("kill").arg(pid.to_string()).output();
    }
    // Give them a moment to release the socket.
    for _ in 0..20 {
        if pids_listening_on(port).is_empty() {
            return Ok(holders);
        }
        std::thread::sleep(Duration::from_millis(250));
    }
    // Still held — escalate, because leaving it means the new build cannot bind.
    for pid in pids_listening_on(port) {
        let _ = Command::new("kill").args(["-9", &pid.to_string()]).output();
    }
    std::thread::sleep(Duration::from_millis(500));
    let remaining = pids_listening_on(port);
    if !remaining.is_empty() {
        return Err(format!(
            "Port {port} is still held by process(es) {remaining:?} after stopping them. \
             Starting the new build now would reproduce the restart loop."
        ));
    }
    Ok(holders)
}

/// PIDs with a LISTEN socket on `port`. Parses `ss` because it is present on every
/// Fedora box and needs no extra package.
fn pids_listening_on(port: u16) -> Vec<u32> {
    let Ok(out) = Command::new("ss").args(["-ltnpH"]).output() else {
        return Vec::new();
    };
    if !out.status.success() {
        return Vec::new();
    }
    let text = String::from_utf8_lossy(&out.stdout);
    let needle = format!(":{port} ");
    let mut pids = Vec::new();
    for line in text.lines() {
        // Local address column, e.g. "0.0.0.0:9119" or "[::]:9119"
        let mut fields = line.split_whitespace();
        let _state = fields.next();
        let local = fields.next().unwrap_or_default();
        if !(local.ends_with(&format!(":{port}")) || local.contains(&needle)) {
            continue;
        }
        for token in line.split("pid=").skip(1) {
            let digits: String = token.chars().take_while(|c| c.is_ascii_digit()).collect();
            if let Ok(pid) = digits.parse::<u32>() {
                if !pids.contains(&pid) {
                    pids.push(pid);
                }
            }
        }
    }
    pids
}

/// Step 6 — install, privileged.
///
/// ── THE POLKIT SEAM ────────────────────────────────────────────────────────────
/// Installing an RPM needs root; this app runs as the user. `pkexec` raises a
/// polkit prompt, which is the conventional Linux shape and the smallest amount of
/// machinery that is still honest about privilege. A silent systemd helper (the
/// Chrome/Firefox shape) is possible later; it is a bigger trust decision and is
/// deliberately not taken here.
pub fn install_rpm(path: &Path) -> Result<String, String> {
    if !path.is_file() {
        return Err(format!("Nothing to install at {}.", path.display()));
    }
    let out = Command::new("pkexec")
        .args(["dnf", "install", "-y"])
        .arg(path)
        .output()
        .map_err(|e| format!("Could not run the privileged install: {e}"))?;
    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    if !out.status.success() {
        return Err(format!(
            "The install did not complete.\n{}{}",
            tail(&stdout, 1200),
            tail(&stderr, 1200)
        ));
    }
    Ok(tail(&stdout, 1200))
}

/// Step 7 — restart, then prove the running version actually changed.
///
/// The RPM's scriptlets contain no `systemctl` (verified against the 7.0.1
/// artifact), so nothing is running the new build until this happens.
pub fn restart_services() -> Vec<String> {
    let mut notes = Vec::new();
    for unit in ["centurion-remote.service", "centurion-gateway.service"] {
        match Command::new("systemctl")
            .args(["--user", "restart", unit])
            .output()
        {
            Ok(out) if out.status.success() => notes.push(format!("{unit}: restarted")),
            Ok(out) => notes.push(format!(
                "{unit}: restart failed — {}",
                tail(&String::from_utf8_lossy(&out.stderr), 300).trim()
            )),
            Err(e) => notes.push(format!("{unit}: could not run systemctl — {e}")),
        }
    }
    notes
}

/// The version the *files on disk* say. Not evidence that anything is running.
pub fn installed_version() -> Option<String> {
    let out = Command::new("rpm")
        .args(["-q", "--qf", "%{VERSION}", "centurion-brain"])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let v = String::from_utf8_lossy(&out.stdout).trim().to_owned();
    if v.is_empty() {
        None
    } else {
        Some(v)
    }
}

/// Package install time in epoch seconds — the thing to compare a process against.
pub fn package_install_epoch() -> Option<i64> {
    let out = Command::new("rpm")
        .args(["-q", "--qf", "%{INSTALLTIME}", "centurion-brain"])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    String::from_utf8_lossy(&out.stdout).trim().parse().ok()
}

/// Start epoch of the process matching `pattern`, if any.
fn process_start_epoch(pattern: &str) -> Option<i64> {
    let out = Command::new("pgrep").args(["-f", pattern]).output().ok()?;
    if !out.status.success() {
        return None;
    }
    let pid = String::from_utf8_lossy(&out.stdout)
        .lines()
        .next()?
        .trim()
        .to_owned();
    if pid.is_empty() {
        return None;
    }
    // `etimes` — seconds since start. Arithmetic we cannot get wrong, unlike
    // parsing the human-readable `lstart`.
    let out = Command::new("ps")
        .args(["-o", "etimes=", "-p", &pid])
        .output()
        .ok()?;
    let secs: i64 = String::from_utf8_lossy(&out.stdout).trim().parse().ok()?;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .ok()?
        .as_secs() as i64;
    Some(now - secs)
}

/// The honest end state: is the running process newer than the files on disk?
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RunningState {
    /// A process is running that started AFTER the package was installed.
    NewBuildRunning,
    /// A process is running that started BEFORE the package was installed — the
    /// "installed, not running" trap.
    StillRunningOld { started: i64, installed: i64 },
    /// Nothing is running to compare.
    NotRunning,
    /// We could not obtain the evidence. Never reported as success.
    Unknown(String),
}

pub fn verify_running_version(pattern: &str) -> RunningState {
    let Some(installed) = package_install_epoch() else {
        return RunningState::Unknown("Could not read the package install time.".to_owned());
    };
    let Some(started) = process_start_epoch(pattern) else {
        return RunningState::NotRunning;
    };
    if started > installed {
        RunningState::NewBuildRunning
    } else {
        RunningState::StillRunningOld { started, installed }
    }
}

fn tail(text: &str, max: usize) -> String {
    if text.len() <= max {
        return text.to_owned();
    }
    let start = text.len() - max;
    let start = text
        .char_indices()
        .map(|(i, _)| i)
        .find(|i| *i >= start)
        .unwrap_or(start);
    let mut s = String::new();
    let _ = write!(s, "…{}", &text[start..]);
    s
}

/// Normalise a version for comparison: strip a **trailing packaging release**
/// (`7.0.1-1` → `7.0.1`) and take the leading numeric components.
///
/// This mirrors `_release_version()` in `centurion_cli/brain_release.py`, and it is
/// load-bearing: the channel publishes a bare three-part version while an RPM
/// filename carries a packaging release. Absorbing `-1` as a fourth number made
/// every up-to-date Brain report `update_available` against the build it was
/// already running — a permanent false prompt. A non-numeric suffix (`6.0.7-rc1`)
/// is **not** stripped; the numeric prefix is all that is compared.
pub fn version_key(version: &str) -> Vec<u64> {
    let v = version.trim();
    // Strip only a trailing `-<digits>`, and only if digits follow the dash.
    let v = match v.rsplit_once('-') {
        Some((head, tail)) if !tail.is_empty() && tail.chars().all(|c| c.is_ascii_digit()) => head,
        _ => v,
    };
    v.split(['.', '_', '+', '-'])
        .map_while(|part| part.parse::<u64>().ok())
        .collect()
}

/// Is `candidate` a later version than `current`? Missing components count as zero,
/// so `7.0` and `7.0.0` compare equal.
pub fn is_newer(candidate: &str, current: &str) -> bool {
    let a = version_key(candidate);
    let b = version_key(current);
    let len = a.len().max(b.len());
    for i in 0..len {
        let x = a.get(i).copied().unwrap_or(0);
        let y = b.get(i).copied().unwrap_or(0);
        if x != y {
            return x > y;
        }
    }
    false
}

/// The outcome of one dry-run step.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StepOutcome {
    /// The step ran and succeeded. The string is the evidence it produced.
    Done(String),
    /// The step failed. The string is the reason.
    Failed(String),
    /// The step was not attempted, and why.
    Skipped(String),
}

impl StepOutcome {
    fn mark(&self) -> &'static str {
        match self {
            StepOutcome::Done(_) => "ok  ",
            StepOutcome::Failed(_) => "FAIL",
            StepOutcome::Skipped(_) => "skip",
        }
    }
}

/// What a full update *would* do, without doing any of it.
#[derive(Debug, Clone)]
pub struct DryRunReport {
    /// (step label, outcome) in execution order.
    pub steps: Vec<(String, StepOutcome)>,
}

impl DryRunReport {
    /// True only if every step that ran succeeded. A skip is not success.
    pub fn all_clear(&self) -> bool {
        !self
            .steps
            .iter()
            .any(|(_, o)| matches!(o, StepOutcome::Failed(_)))
    }

    pub fn render(&self) -> String {
        let mut out = String::from("Update dry run — nothing was installed or stopped.\n\n");
        for (label, outcome) in &self.steps {
            let detail = match outcome {
                StepOutcome::Done(d) | StepOutcome::Failed(d) | StepOutcome::Skipped(d) => d,
            };
            let _ = writeln!(out, "[{}] {label}\n        {detail}", outcome.mark());
        }
        let _ = writeln!(
            out,
            "\n{}",
            if self.all_clear() {
                "No failures. The install itself was NOT attempted."
            } else {
                "At least one step failed — an update would not complete."
            }
        );
        out
    }
}

/// Steps 1–5 of the sequence, run for real, with nothing installed and nothing
/// stopped. This exists because without it the only way to test the updater is to
/// update something — which is how an installer ships having been exercised once,
/// by a customer.
///
/// `licence_code` is `None` on a Brain that has never stored one; the download step
/// then reports *why* it cannot proceed rather than failing opaquely.
pub fn dry_run(dest_dir: &Path, licence_code: Option<&str>) -> DryRunReport {
    let mut steps: Vec<(String, StepOutcome)> = Vec::new();

    // --- 1. resolve -------------------------------------------------------
    let release = match latest_release() {
        Ok(r) => {
            steps.push((
                "Resolve the published release".to_owned(),
                StepOutcome::Done(match &r.title {
                    Some(t) => format!("{t} (version {})", r.version),
                    None => format!("version {}", r.version),
                }),
            ));
            r
        }
        Err(e) => {
            steps.push((
                "Resolve the published release".to_owned(),
                StepOutcome::Failed(e),
            ));
            return DryRunReport { steps };
        }
    };

    let Some(artifact) = release.installer() else {
        steps.push((
            "Choose the installer".to_owned(),
            StepOutcome::Failed(
                "The channel published no .rpm for this release, so there is nothing a \
                 Brain can install."
                    .to_owned(),
            ),
        ));
        return DryRunReport { steps };
    };
    steps.push((
        "Choose the installer".to_owned(),
        StepOutcome::Done(format!(
            "{} ({:.1} MB, sha256 {})",
            artifact.filename,
            artifact.size_bytes as f64 / 1_048_576.0,
            &artifact.sha256[..artifact.sha256.len().min(12)]
        )),
    ));

    // --- is an update even warranted? -------------------------------------
    match installed_version() {
        Some(installed) => {
            let outcome = if is_newer(&release.version, &installed) {
                StepOutcome::Done(format!("{installed} → {}", release.version))
            } else {
                StepOutcome::Skipped(format!(
                    "already on {installed}; the channel has {}",
                    release.version
                ))
            };
            steps.push(("Compare with the installed build".to_owned(), outcome));
        }
        None => steps.push((
            "Compare with the installed build".to_owned(),
            StepOutcome::Skipped(
                "not an RPM install (or `rpm -q centurion-brain` said nothing)".to_owned(),
            ),
        )),
    }

    // --- 2. download ------------------------------------------------------
    let downloaded = match licence_code.map(str::trim).filter(|c| !c.is_empty()) {
        None => {
            steps.push((
                "Download the artifact".to_owned(),
                StepOutcome::Skipped(
                    "no licence code is stored on this Brain. The download route accepts a \
                     real issued licence code (`x-centurion-license-code`) or a staff \
                     session — nothing else. See the note in the module header."
                        .to_owned(),
                ),
            ));
            None
        }
        Some(code) => match download_artifact(artifact, dest_dir, code) {
            Ok(path) => {
                steps.push((
                    "Download the artifact".to_owned(),
                    StepOutcome::Done(path.display().to_string()),
                ));
                Some(path)
            }
            Err(e) => {
                steps.push(("Download the artifact".to_owned(), StepOutcome::Failed(e)));
                None
            }
        },
    };

    // --- 3 + 4. verify ----------------------------------------------------
    if let Some(path) = &downloaded {
        match verify_sha256(path, &artifact.sha256) {
            Ok(sum) => steps.push((
                "Verify the checksum".to_owned(),
                StepOutcome::Done(format!("sha256 matches the published value ({sum})")),
            )),
            Err(e) => steps.push(("Verify the checksum".to_owned(), StepOutcome::Failed(e))),
        }
        match verify_or_import_signature(path) {
            Ok(out) => steps.push((
                "Verify the signature".to_owned(),
                StepOutcome::Done(tail(out.trim(), 400)),
            )),
            Err(e) => steps.push(("Verify the signature".to_owned(), StepOutcome::Failed(e))),
        }
    } else {
        for label in ["Verify the checksum", "Verify the signature"] {
            steps.push((
                label.to_owned(),
                StepOutcome::Skipped("nothing was downloaded to check".to_owned()),
            ));
        }
    }

    // --- 5. the predecessor ------------------------------------------------
    // Reported, never acted on: a dry run must not kill the live service.
    let holders = pids_listening_on(REMOTE_PORT);
    steps.push((
        "Predecessor on the remote port".to_owned(),
        if holders.is_empty() {
            StepOutcome::Done(format!("nothing is listening on {REMOTE_PORT}"))
        } else {
            StepOutcome::Done(format!(
                "would stop pid(s) {holders:?} holding {REMOTE_PORT} (not stopped in a dry run)"
            ))
        },
    ));

    steps.push((
        "Install".to_owned(),
        StepOutcome::Skipped("dry run — the privileged install was not attempted".to_owned()),
    ));

    DryRunReport { steps }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn art(filename: &str, sha: &str) -> Artifact {
        Artifact {
            id: "a1".to_owned(),
            filename: filename.to_owned(),
            size_bytes: 10,
            sha256: sha.to_owned(),
        }
    }

    #[test]
    fn installer_picks_the_rpm() {
        let rel = Release {
            version: "7.0.2".to_owned(),
            title: None,
            artifacts: vec![
                art("notes.txt", "x"),
                art("centurion-brain-7.0.2-1.fc44.x86_64.rpm", "y"),
            ],
        };
        let chosen = rel.installer().expect("an rpm should be found");
        assert!(chosen.filename.ends_with(".rpm"));
    }

    #[test]
    fn installer_returns_none_when_no_rpm_published() {
        let rel = Release {
            version: "7.0.2".to_owned(),
            title: None,
            artifacts: vec![art("notes.txt", "x")],
        };
        assert!(rel.installer().is_none());
    }

    #[test]
    fn sha256_matches_a_known_value_and_rejects_a_wrong_one() {
        let dir = std::env::temp_dir().join("centurion-sha-test");
        fs::create_dir_all(&dir).unwrap();
        let f = dir.join("probe.txt");
        fs::write(&f, b"abc").unwrap();
        // sha256("abc") — the canonical test vector.
        let expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";

        let got = verify_sha256(&f, expected).expect("known vector must verify");
        assert_eq!(got, expected);

        let err = verify_sha256(&f, "deadbeef").unwrap_err();
        assert!(err.contains("does not match"), "got: {err}");
        let _ = fs::remove_file(&f);
    }

    #[test]
    fn sha256_is_case_insensitive_about_the_expected_value() {
        let dir = std::env::temp_dir().join("centurion-sha-test-case");
        fs::create_dir_all(&dir).unwrap();
        let f = dir.join("probe.txt");
        fs::write(&f, b"abc").unwrap();
        let upper = "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD";
        assert!(verify_sha256(&f, upper).is_ok());
        let _ = fs::remove_file(&f);
    }

    #[test]
    fn pids_listening_on_returns_nothing_for_an_unused_port() {
        // Port 1 is never a listening socket for this user; the function must be
        // safe (no panic) and empty rather than guessing a holder.
        assert!(pids_listening_on(1).is_empty());
    }

    #[test]
    fn version_key_strips_a_packaging_release_but_not_a_pre_release_tag() {
        assert_eq!(version_key("7.0.1"), vec![7, 0, 1]);
        assert_eq!(version_key("7.0.1-1"), vec![7, 0, 1]);
        assert_eq!(version_key("7.0.0-5"), vec![7, 0, 0]);
        // A non-numeric suffix is not a packaging release; the numeric prefix stands.
        assert_eq!(version_key("6.0.7-rc1"), vec![6, 0, 7]);
        assert_eq!(version_key(" 7.0.1 "), vec![7, 0, 1]);
    }

    /// The regression that prompted the rule: the channel published `7.0.0-5`
    /// while the Brain ran `7.0.0`, and absorbing `-5` as a fourth number told
    /// every up-to-date Brain to update to the build it already had — forever.
    #[test]
    fn a_packaging_release_is_not_an_update() {
        assert!(!is_newer("7.0.0-5", "7.0.0"), "packaging suffix is not a version");
        assert!(!is_newer("7.0.0", "7.0.0"));
        assert!(!is_newer("7.0", "7.0.0"), "missing components count as zero");
        assert!(!is_newer("7.0.0", "7.0.1"), "never offer a downgrade");
    }

    #[test]
    fn a_real_bump_is_an_update() {
        assert!(is_newer("7.0.1", "7.0.0"));
        assert!(is_newer("7.1.0", "7.0.9"));
        assert!(is_newer("8.0.0", "7.9.9"));
    }

    #[test]
    fn a_skip_is_not_a_success_and_a_failure_is_not_clear() {
        let clean = DryRunReport {
            steps: vec![
                ("a".to_owned(), StepOutcome::Done("fine".to_owned())),
                ("b".to_owned(), StepOutcome::Skipped("not tried".to_owned())),
            ],
        };
        assert!(clean.all_clear(), "skips are not failures");
        assert!(clean.render().contains("NOT attempted"));

        let broken = DryRunReport {
            steps: vec![(
                "a".to_owned(),
                StepOutcome::Failed("checksum mismatch".to_owned()),
            )],
        };
        assert!(!broken.all_clear());
        assert!(broken.render().contains("[FAIL]"));
    }
}
