"""The desk's own page: the script parses, and every element it reaches for exists.

`node --check` catches a syntax error the browser would report only to a partner
who happened to open the page. The id check catches the quieter failure: a
control that references an element that was renamed, so a button does nothing
and no error is raised — which is the one failure this desk is not allowed to
have, because a control that looks live and is not is a lie in the UI.

Skipped when node is absent rather than passing silently: a skip is honest, a
green test that never ran is not.
"""

from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path

import pytest

STATIC = Path(__file__).resolve().parents[2] / "centurion_cli" / "practice_desk" / "static"


def _blocks(html: str):
    return re.findall(r"<script(?![^>]*src=)[^>]*>(.*?)</script>", html, re.S)


@pytest.mark.parametrize("page", ["desk.html", "signin.html"])
def test_the_page_script_is_valid_javascript(page, tmp_path):
    node = shutil.which("node")
    if not node:
        pytest.skip("node is not installed; the script was not syntax-checked")
    assert node  # narrows the type for the reader and the checker
    html = (STATIC / page).read_text()
    blocks = _blocks(html)
    assert blocks, f"{page} carries no inline script — did the page change shape?"
    for i, block in enumerate(blocks):
        script = tmp_path / f"{page}.{i}.mjs"
        script.write_text(block)
        result = subprocess.run(
            [node, "--check", str(script)], capture_output=True, text=True
        )
        assert result.returncode == 0, f"{page} block {i}: {result.stderr[:800]}"


def test_every_element_the_desk_reaches_for_exists():
    """`$("thing")` with no matching id is a dead control, not a console error."""
    html = (STATIC / "desk.html").read_text()
    ids = set(re.findall(r'id="([^"]+)"', html))
    refs = set(re.findall(r'\$\("([^"]+)"\)', html))
    assert refs, "the desk script reaches for no elements at all?"
    missing = sorted(refs - ids)
    assert not missing, f"the script references elements that do not exist: {missing}"


def _record_writes() -> set[str]:
    """Every action name the register can write, read out of the Python source.

    Two of them are f-strings — `person_{status}` and `draft_{to}` — so the
    closed sets of status and draft state are expanded here. If a new action is
    added without a phrase on the page, this test fails rather than the page
    quietly printing `client_access_refused` at a partner.
    """
    source = ""
    for name in ("store.py", "app.py"):
        source += (STATIC.parent / name).read_text()

    found = set()
    for pattern in (
        r'_audit\(\s*conn,\s*[^,]+,\s*f?"([a-z_]+)"',
        r'\.record\(\s*[^,]+,\s*f?"([a-z_]+)"',
        r'action=f?"([a-z_]+)"',
    ):
        found |= set(re.findall(pattern, source))

    if 'f"person_{status}"' in source:
        found |= {f"person_{s}" for s in ("invited", "active", "suspended", "departed")}
    if 'f"draft_{to}"' in source:
        found |= {"draft_awaiting_signature", "draft_signed", "draft_withdrawn"}
    return found


def test_every_action_the_register_writes_has_a_phrase_on_the_page():
    html = (STATIC / "desk.html").read_text()
    block = re.search(r"const ACTION_WORDS = \{(.*?)\n  \};", html, re.S)
    assert block, "ACTION_WORDS has moved or been renamed"
    mapped = set(re.findall(r"^\s*([a-z_]+):", block.group(1), re.M))

    written = _record_writes()
    assert written, "no action names found in the source — the extraction is stale"
    missing = sorted(written - mapped)
    assert not missing, (
        f"the register writes actions the record cannot put into words: {missing}. "
        "Add them to ACTION_WORDS in desk.html."
    )


def test_the_phrase_map_invents_no_actions_that_do_not_exist():
    """A key with no writer behind it is a phrase waiting to describe nothing."""
    html = (STATIC / "desk.html").read_text()
    block = re.search(r"const ACTION_WORDS = \{(.*?)\n  \};", html, re.S)
    mapped = set(re.findall(r"^\s*([a-z_]+):", block.group(1), re.M))
    written = _record_writes()
    invented = sorted(mapped - written)
    assert not invented, f"ACTION_WORDS names actions nothing writes: {invented}"
