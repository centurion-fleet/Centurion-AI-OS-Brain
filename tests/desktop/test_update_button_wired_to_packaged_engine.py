"""Guard: the update button must reach the packaged update engine on a packaged Brain.

Defect class (NR-001 fault 1, 29 Sep 2026):

    `brain_update` implements the complete seven-step packaged update — resolve,
    download, verify sha256, verify signature, free the port, install the RPM, prove
    the newer build is running. It was called from the GUI exactly ONCE, and only on
    the `--update-dry-run` CLI path.

    The button's own pipeline, `run_full_brain_update_pipeline()`, went straight to
    `resolve_centurion_repo_root()` + `run_native_brain_install()` — the developer
    git path. An RPM install has no checkout, so EVERY packaged Brain hit a dead end:
    the banner said "tap Update below" and the update could never run.

The rule this guard enforces:

    A packaged Brain must route to `run_packaged_update_pipeline()`, and that
    pipeline must walk all seven steps of `brain_update` — not skip the ones that
    are inconvenient, and never report success from the install step alone.

Prove this guard by making it fail: delete the packaged branch from
`run_full_brain_update_pipeline` and re-run.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
MAIN = REPO_ROOT / "brain" / "linux" / "centurion-desktop" / "src" / "main.rs"

# Every step of the packaged update, in the order brain_update defines them.
REQUIRED_STEPS = [
    "brain_update::latest_release()",
    "brain_update::download_artifact(",
    "brain_update::verify_sha256(",
    "brain_update::verify_or_import_signature(",
    "brain_update::stop_port_holders(brain_update::REMOTE_PORT)",
    "brain_update::install_rpm(",
    "brain_update::restart_services()",
    "brain_update::verify_running_version(",
]


@pytest.fixture(scope="module")
def src() -> str:
    assert MAIN.exists(), f"desktop main.rs not found at {MAIN}"
    return MAIN.read_text(encoding="utf-8")


def _packaged_pipeline(src: str) -> str:
    start = src.find("fn run_packaged_update_pipeline()")
    assert start != -1, (
        "there is no packaged update pipeline — a packaged Brain has no route to "
        "brain_update, which is the original NR-001 fault 1 defect"
    )
    end = src.find("\n    /// Full Brain update:", start)
    return src[start: end if end != -1 else start + 6000]


def test_pipeline_exists_and_is_wired(src: str) -> None:
    """The button's pipeline must branch to the packaged path, not assume a checkout."""
    assert "run_packaged_update_pipeline()" in src, "no call site for the packaged pipeline"
    branch = re.search(
        r"fn run_full_brain_update_pipeline\(\)[^{]*\{(.{0,900})",
        src,
        re.S,
    )
    assert branch, "could not find run_full_brain_update_pipeline"
    head = branch.group(1)
    assert "resolve_centurion_repo_root().is_err()" in head and "run_packaged_update_pipeline()" in head, (
        "run_full_brain_update_pipeline no longer routes to the packaged update when "
        "there is no checkout — every RPM Brain is back to a dead end:\n" + head
    )
    # ...and the branch must come BEFORE the git path, or it never runs.
    assert head.index("run_packaged_update_pipeline()") < head.index("run_os_update()"), (
        "the packaged branch sits after the developer path, so a packaged Brain never "
        "reaches it"
    )


def test_every_step_is_walked(src: str) -> None:
    """Skip a step and the update either fails or lies about succeeding."""
    body = _packaged_pipeline(src)
    missing = [step for step in REQUIRED_STEPS if step not in body]
    assert not missing, (
        "the packaged pipeline skips steps it cannot afford to skip — an update that "
        f"takes a shortcut is an update nobody can trust: {missing}"
    )


def test_success_is_never_claimed_from_the_install_alone(src: str) -> None:
    """Step 7 exists because 'installed' is not 'running'."""
    body = _packaged_pipeline(src)
    assert "RunningState::Unknown" in body, (
        "the pipeline no longer handles the 'we could not tell' state, so an "
        "unverifiable update can be reported as a success"
    )
    assert "StillRunningOld" in body, (
        "the pipeline no longer handles installed-but-not-running — the trap where a "
        "fix is on disk and systemd never reloaded it"
    )
