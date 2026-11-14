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
