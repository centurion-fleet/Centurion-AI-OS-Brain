"""Tests for the update check mechanism in centurion_cli.banner."""

import json
import os
import threading
import time
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest


def test_version_string_no_v_prefix():
    """__version__ should be bare semver without a 'v' prefix."""
    from centurion_cli import __version__
    assert not __version__.startswith("v"), f"__version__ should not start with 'v', got {__version__!r}"


def test_check_for_updates_uses_cache(tmp_path, monkeypatch):
    """When cache is fresh, check_for_updates should return cached value without calling git."""
    from centurion_cli.banner import check_for_updates

    # Create a fake git repo and fresh cache
    repo_dir = tmp_path / "centurion-os"
    repo_dir.mkdir()
    (repo_dir / ".git").mkdir()

    cache_file = tmp_path / ".update_check"
    cache_file.write_text(json.dumps({"ts": time.time(), "behind": 3}))

    monkeypatch.setenv("CENTURION_HOME", str(tmp_path))
    with patch("centurion_cli.banner.subprocess.run") as mock_run:
        result = check_for_updates()

    assert result == 3
    mock_run.assert_not_called()


def test_check_for_updates_expired_cache(tmp_path, monkeypatch):
    """When cache is expired, check_for_updates should call git fetch."""
    from centurion_cli.banner import check_for_updates

    repo_dir = tmp_path / "centurion-os"
    repo_dir.mkdir()
    (repo_dir / ".git").mkdir()

    # Write an expired cache (timestamp far in the past)
    cache_file = tmp_path / ".update_check"
    cache_file.write_text(json.dumps({"ts": 0, "behind": 1}))

    mock_result = MagicMock(returncode=0, stdout="5\n")

    monkeypatch.setenv("CENTURION_HOME", str(tmp_path))
    with patch("centurion_cli.banner.subprocess.run", return_value=mock_result) as mock_run:
        result = check_for_updates()

    assert result == 5
    assert mock_run.call_count == 2  # git fetch + git rev-list


def test_check_for_updates_no_git_dir(tmp_path, monkeypatch):
    """Falls back to PyPI check when .git directory doesn't exist anywhere."""
    import centurion_cli.banner as banner

    # Create a fake banner.py so the fallback path also has no .git
    fake_banner = tmp_path / "centurion_cli" / "banner.py"
    fake_banner.parent.mkdir(parents=True, exist_ok=True)
    fake_banner.touch()

    monkeypatch.setattr(banner, "__file__", str(fake_banner))
    monkeypatch.setenv("CENTURION_HOME", str(tmp_path))
    with patch("centurion_cli.banner.subprocess.run") as mock_run:
        with patch("centurion_cli.banner.check_via_pypi", return_value=0):
            result = banner.check_for_updates()
    assert result == 0
    mock_run.assert_not_called()


def test_check_for_updates_fallback_to_project_root(tmp_path, monkeypatch):
    """Dev install: falls back to Path(__file__).parent.parent when CENTURION_HOME has no git repo."""
    import centurion_cli.banner as banner

    project_root = Path(banner.__file__).parent.parent.resolve()
    if not (project_root / ".git").exists():
        pytest.skip("Not running from a git checkout")

    # Point CENTURION_HOME at a temp dir with no centurion-os/.git
    monkeypatch.setenv("CENTURION_HOME", str(tmp_path))
    with patch("centurion_cli.banner.subprocess.run") as mock_run:
        mock_run.return_value = MagicMock(returncode=0, stdout="0\n")
        result = banner.check_for_updates()
    # Should have fallen back to project root and run git commands
    assert mock_run.call_count >= 1


def test_prefetch_non_blocking():
    """prefetch_update_check() should return immediately without blocking."""
    import centurion_cli.banner as banner

    # Reset module state
    banner._update_result = None
    banner._update_check_done = threading.Event()

    with patch.object(banner, "check_for_updates", return_value=5):
        start = time.monotonic()
        banner.prefetch_update_check()
        elapsed = time.monotonic() - start

        # Should return almost immediately (well under 1 second)
        assert elapsed < 1.0

        # Wait for the background thread to finish
        banner._update_check_done.wait(timeout=5)
        assert banner._update_result == 5


def test_invalidate_update_cache_clears_all_profiles(tmp_path):
    """_invalidate_update_cache() should delete .update_check from ALL profiles."""
    from centurion_cli.main import _invalidate_update_cache

    # Build a fake ~/.centurion with default + two named profiles
    default_home = tmp_path / ".centurion"
    default_home.mkdir()
    (default_home / ".update_check").write_text('{"ts":1,"behind":50}')

    profiles_root = default_home / "profiles"
    for name in ("ops", "dev"):
        p = profiles_root / name
        p.mkdir(parents=True)
        (p / ".update_check").write_text('{"ts":1,"behind":50}')

    with patch.object(Path, "home", return_value=tmp_path), \
         patch.dict(os.environ, {"CENTURION_HOME": str(default_home)}):
        _invalidate_update_cache()

    # All three caches should be gone
    assert not (default_home / ".update_check").exists(), "default profile cache not cleared"
    assert not (profiles_root / "ops" / ".update_check").exists(), "ops profile cache not cleared"
    assert not (profiles_root / "dev" / ".update_check").exists(), "dev profile cache not cleared"


def test_invalidate_update_cache_no_profiles_dir(tmp_path):
    """Works fine when no profiles directory exists (single-profile setup)."""
    from centurion_cli.main import _invalidate_update_cache

    default_home = tmp_path / ".centurion"
    default_home.mkdir()
    (default_home / ".update_check").write_text('{"ts":1,"behind":5}')

    with patch.object(Path, "home", return_value=tmp_path), \
         patch.dict(os.environ, {"CENTURION_HOME": str(default_home)}):
        _invalidate_update_cache()

    assert not (default_home / ".update_check").exists()


def test_cmd_update_check_json_up_to_date_git(tmp_path, monkeypatch, capsys):
    """centurion update --check --json reports up_to_date for a current git install."""
    from types import SimpleNamespace

    import centurion_cli.main as main_mod

    repo = tmp_path / "repo"
    repo.mkdir()
    (repo / ".git").mkdir()

    monkeypatch.setattr(main_mod, "PROJECT_ROOT", repo)
    monkeypatch.setenv("CENTURION_HOME", str(tmp_path / "home"))

    def fake_run(cmd, **kwargs):
        joined = " ".join(cmd) if isinstance(cmd, (list, tuple)) else str(cmd)
        mock = MagicMock()
        mock.returncode = 0
        mock.stdout = "0\n"
        mock.stderr = ""
        if "rev-list" in joined:
            mock.stdout = "0\n"
        elif "rev-parse" in joined and "@{u}" in joined:
            mock.returncode = 128
            mock.stdout = ""
            mock.stderr = "no upstream"
        elif "rev-parse" in joined and "abbrev-ref" in joined:
            mock.stdout = "main\n"
        elif "rev-parse" in joined and "HEAD" in joined:
            mock.stdout = "abc123\n"
        return mock

    args = SimpleNamespace(json=True, check=True, screen_version=None)
    with patch("centurion_cli.config.is_managed", return_value=False), \
         patch("centurion_cli.config.detect_install_method", return_value="git"), \
         patch("centurion_cli.config.recommended_update_command", return_value="centurion update"), \
         patch("centurion_cli.main.subprocess.run", side_effect=fake_run), \
         patch("centurion_cli.main._installed_desktop_binary", return_value=None):
        main_mod._cmd_update_check(args)

    payload = json.loads(capsys.readouterr().out.strip())
    assert payload["ok"] is True
    assert payload["status"] == "up_to_date"
    assert payload["method"] == "git"
    assert payload["behind"] == 0
    assert "os_version" in payload
    assert payload["recommended_command"] == "centurion update"


def test_cmd_update_check_json_update_available_git(tmp_path, monkeypatch, capsys):
    """centurion update --check --json reports update_available when behind."""
    from types import SimpleNamespace

    import centurion_cli.main as main_mod

    repo = tmp_path / "repo"
    repo.mkdir()
    (repo / ".git").mkdir()
    monkeypatch.setattr(main_mod, "PROJECT_ROOT", repo)
    monkeypatch.setenv("CENTURION_HOME", str(tmp_path / "home"))

    def fake_run(cmd, **kwargs):
        joined = " ".join(cmd) if isinstance(cmd, (list, tuple)) else str(cmd)
        mock = MagicMock(returncode=0, stdout="0\n", stderr="")
        if "rev-list" in joined:
            mock.stdout = "3\n"
        elif "rev-parse" in joined and "@{u}" in joined:
            mock.returncode = 128
            mock.stdout = ""
        elif "rev-parse" in joined and "abbrev-ref" in joined:
            mock.stdout = "main\n"
        return mock

    args = SimpleNamespace(json=True, check=True, screen_version=None)
    with patch("centurion_cli.config.is_managed", return_value=False), \
         patch("centurion_cli.config.detect_install_method", return_value="git"), \
         patch("centurion_cli.config.recommended_update_command", return_value="centurion update"), \
         patch("centurion_cli.main.subprocess.run", side_effect=fake_run), \
         patch("centurion_cli.main._installed_desktop_binary", return_value=None):
        main_mod._cmd_update_check(args)

    payload = json.loads(capsys.readouterr().out.strip())
    assert payload["status"] == "update_available"
    assert payload["behind"] == 3
    assert "3 commits" in payload["message"]
    assert payload.get("update_action") == "full"


def test_cmd_update_check_json_managed(tmp_path, monkeypatch, capsys):
    """Managed installs return unavailable with the package-manager command."""
    from types import SimpleNamespace

    import centurion_cli.main as main_mod

    monkeypatch.setattr(main_mod, "PROJECT_ROOT", tmp_path)
    args = SimpleNamespace(json=True, check=True, screen_version=None)
    with patch("centurion_cli.config.is_managed", return_value=True), \
         patch("centurion_cli.config.detect_install_method", return_value="nixos"), \
         patch("centurion_cli.config.recommended_update_command", return_value="sudo nixos-rebuild switch"):
        main_mod._cmd_update_check(args)

    payload = json.loads(capsys.readouterr().out.strip())
    assert payload["ok"] is True
    assert payload["status"] == "unavailable"
    assert payload["method"] == "nixos"
    assert payload["recommended_command"] == "sudo nixos-rebuild switch"


def test_resolve_git_update_root_prefers_centurion_ai_repo(tmp_path, monkeypatch):
    import centurion_cli.main as main_mod

    pip_root = tmp_path / "site"
    pip_root.mkdir()
    repo = tmp_path / "checkout"
    repo.mkdir()
    (repo / ".git").mkdir()
    (repo / "brain" / "linux" / "scripts").mkdir(parents=True)
    (repo / "brain" / "linux" / "scripts" / "install-user.sh").write_text(
        "#!/bin/bash\n", encoding="utf-8"
    )
    monkeypatch.setattr(main_mod, "PROJECT_ROOT", pip_root)
    monkeypatch.setenv("CENTURION_AI_REPO", str(repo))
    assert main_mod._resolve_git_update_root() == repo.resolve()


def test_cmd_update_check_json_feature_branch_behind(tmp_path, monkeypatch, capsys):
    """Check finds commits on the current branch tip even when main is current."""
    from types import SimpleNamespace

    import centurion_cli.main as main_mod

    repo = tmp_path / "repo"
    repo.mkdir()
    (repo / ".git").mkdir()
    monkeypatch.setattr(main_mod, "PROJECT_ROOT", repo)
    monkeypatch.setenv("CENTURION_HOME", str(tmp_path / "home"))

    def fake_run(cmd, **kwargs):
        joined = " ".join(cmd) if isinstance(cmd, (list, tuple)) else str(cmd)
        mock = MagicMock(returncode=0, stdout="0\n", stderr="")
        if "fetch" in joined:
            return mock
        if "rev-list" in joined and "upstream/main" in joined:
            mock.stdout = "0\n"
        elif "rev-list" in joined and "origin/fix/feature" in joined:
            mock.stdout = "2\n"
        elif "rev-parse" in joined and "@{u}" in joined:
            mock.stdout = "origin/fix/feature\n"
        elif "rev-parse" in joined and "abbrev-ref" in joined:
            mock.stdout = "fix/feature\n"
        return mock

    args = SimpleNamespace(json=True, check=True, screen_version=None)
    with patch("centurion_cli.config.is_managed", return_value=False), \
         patch("centurion_cli.config.detect_install_method", return_value="git"), \
         patch("centurion_cli.config.recommended_update_command", return_value="centurion update"), \
         patch("centurion_cli.main.subprocess.run", side_effect=fake_run), \
         patch("centurion_cli.main._installed_desktop_binary", return_value=None):
        main_mod._cmd_update_check(args)

    payload = json.loads(capsys.readouterr().out.strip())
    assert payload["status"] == "update_available"
    assert payload["behind"] == 2
    assert payload["branch_behind"] == 2
    assert "origin/fix/feature" in payload["message"]


def test_cmd_update_check_json_screen_version_stale(tmp_path, monkeypatch, capsys):
    """Check offers a screen rebuild when the checkout is newer than --screen-version."""
    from types import SimpleNamespace

    import centurion_cli.main as main_mod

    repo = tmp_path / "repo"
    repo.mkdir()
    (repo / ".git").mkdir()
    desktop = repo / "brain"
    desktop.mkdir()
    (desktop / "Cargo.toml").write_text(
        '[workspace]\nmembers = []\n\n[workspace.package]\nversion = "5.2.5"\n',
        encoding="utf-8",
    )
    monkeypatch.setattr(main_mod, "PROJECT_ROOT", repo)
    monkeypatch.setenv("CENTURION_HOME", str(tmp_path / "home"))

    def fake_run(cmd, **kwargs):
        joined = " ".join(cmd) if isinstance(cmd, (list, tuple)) else str(cmd)
        mock = MagicMock(returncode=0, stdout="0\n", stderr="")
        if "rev-list" in joined:
            mock.stdout = "0\n"
        elif "rev-parse" in joined and "@{u}" in joined:
            mock.returncode = 128
            mock.stdout = ""
        elif "rev-parse" in joined and "abbrev-ref" in joined:
            mock.stdout = "fix/app-store-submission-readiness\n"
        elif "rev-parse" in joined and "HEAD" in joined:
            mock.stdout = "deadbeef\n"
        return mock

    args = SimpleNamespace(json=True, check=True, screen_version="5.2.2")
    with patch("centurion_cli.config.is_managed", return_value=False), \
         patch("centurion_cli.config.detect_install_method", return_value="git"), \
         patch("centurion_cli.config.recommended_update_command", return_value="centurion update"), \
         patch("centurion_cli.main.subprocess.run", side_effect=fake_run), \
         patch("centurion_cli.main._installed_desktop_binary", return_value=None):
        main_mod._cmd_update_check(args)

    payload = json.loads(capsys.readouterr().out.strip())
    assert payload["status"] == "update_available"
    assert payload["behind"] == 0
    assert payload["screen_rebuild_available"] is True
    assert payload["update_action"] == "rebuild_screen"
    assert payload["screen_checkout_version"] == "5.2.5"
    assert "5.2.5" in payload["message"]
    assert "5.2.2" in payload["message"]


def test_version_newer_helper():
    import centurion_cli.main as main_mod

    assert main_mod._version_newer("5.2.5", "5.2.2")
    assert not main_mod._version_newer("5.2.2", "5.2.5")
    assert not main_mod._version_newer("5.2.4", "5.2.4")
