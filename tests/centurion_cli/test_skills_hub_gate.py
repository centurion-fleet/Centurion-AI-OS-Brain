"""Skills hub install gate + tools_skills_snapshot provenance buckets."""

from __future__ import annotations


def test_public_hub_installs_blocked_by_default(monkeypatch, tmp_path):
    from centurion_cli import skills_hub as sh

    monkeypatch.setenv("CENTURION_HOME", str(tmp_path / ".centurion"))
    (tmp_path / ".centurion").mkdir(parents=True)

    cfg = {"skills": {"allow_public_hub": False}}
    monkeypatch.setattr("centurion_cli.config.load_config", lambda: cfg)
    assert sh.public_hub_installs_allowed() is False

    class _C:
        def print(self, *a, **k):
            return None

    # Must return before any network/fetch work.
    sh.do_install("openai/skills/skill-creator", skip_confirm=True, console=_C())


def test_public_hub_installs_allowed_when_enabled(monkeypatch):
    from centurion_cli import skills_hub as sh

    cfg = {"skills": {"allow_public_hub": True}}
    monkeypatch.setattr("centurion_cli.config.load_config", lambda: cfg)
    assert sh.public_hub_installs_allowed() is True


def test_tools_skills_snapshot_buckets(monkeypatch, tmp_path):
    from centurion_cli import remote_bridge as rb

    home = tmp_path / ".centurion"
    skills = home / "skills"
    skills.mkdir(parents=True)
    monkeypatch.setenv("CENTURION_HOME", str(home))

    local = skills / "my-local-skill"
    local.mkdir()
    (local / "SKILL.md").write_text("---\nname: my-local-skill\n---\n# Local\n", encoding="utf-8")

    bundled = skills / "bundled-one"
    bundled.mkdir()
    (bundled / "SKILL.md").write_text("---\nname: bundled-one\n---\n# Bundled\n", encoding="utf-8")
    (skills / ".bundled_manifest").write_text("bundled-one:abc\n", encoding="utf-8")

    hub_dir = skills / ".hub"
    hub_dir.mkdir()
    hub_skill = skills / "hub-skill"
    hub_skill.mkdir()
    (hub_skill / "SKILL.md").write_text("---\nname: hub-skill\n---\n# Hub\n", encoding="utf-8")
    import json

    (hub_dir / "lock.json").write_text(
        json.dumps(
            {
                "installed": {
                    "hub-skill": {
                        "name": "hub-skill",
                        "install_path": str(hub_skill),
                        "source": "github",
                        "trust_level": "community",
                    }
                }
            }
        ),
        encoding="utf-8",
    )

    monkeypatch.setattr(
        "centurion_cli.config.load_config",
        lambda: {"skills": {"allow_public_hub": False}, "tools": {}},
    )
    monkeypatch.setattr(
        "centurion_cli.tools_config._get_platform_tools",
        lambda *_a, **_k: ["terminal", "file"],
    )

    resp = rb._handle_tools_skills_snapshot("t1")
    assert resp["ok"] is True
    assert resp["policy"]["allow_public_hub"] is False
    self_names = {e["name"] for e in resp["self_built"]}
    bundled_names = {e["name"] for e in resp["bundled"]}
    hub_names = {e["name"] for e in resp["hub_reference"]}
    assert "my-local-skill" in self_names
    assert "bundled-one" in bundled_names
    assert "hub-skill" in hub_names
