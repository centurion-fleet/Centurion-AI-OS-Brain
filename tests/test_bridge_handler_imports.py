"""Every first-party import in the shipped tree must actually resolve.

WHY THIS TEST EXISTS
--------------------
Two fleet bridge actions -- ``fleet_status`` and ``fleet_ping`` -- did
``from tools.fleet_tools import ...`` for their entire life. ``tools/fleet_tools.py``
has never existed anywhere in the tree. Both handlers therefore raised on every
call and fell into their ``except Exception`` arm, which the UI renders as a
generic error.

Nothing in CI noticed, because the imports sit inside the handlers and the
handlers catch broadly. The customer-visible consequences were:

* ``fleet_ping`` backed the app's **Test** button. It had never worked.
* ``fleet_status`` builds the recipient list for the **Send** box, and that
  section only draws when the list is non-empty -- so two correctly-paired
  Brains were shown no way to speak to each other at all.

A dispatch-listed action is not a working action. This test makes the defect
class non-shippable: a handler written against a module that was never written
now fails at test time instead of on a customer's machine.

THE ALLOWLIST IS THE POINT
--------------------------
Some modules are *deliberately* absent -- optional enrichments that degrade to
nothing by design. A blanket "must resolve" rule would flag them, so they are
listed here individually, each with the reason it is allowed to be missing. If a
new import cannot resolve, the test fails and the author must either fix the
code or add an entry with a justification -- which is exactly the review we want.
An unexplained absence can no longer slip through unnoticed.

Do NOT add an entry to silence a real fault. ``tools.fleet_tools`` would not have
been eligible for this list: the action was advertised to the UI and expected to
work.
"""

from __future__ import annotations

import ast
import importlib.util
import os
import sys

import pytest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Directories that are not shipped runtime code.
_SKIP_DIRS = {
    "venv",
    ".venv",
    "build",
    "node_modules",
    ".git",
    "dist",
    "tests",
    "__pycache__",
    ".mypy_cache",
    ".pytest_cache",
}

# Top-level packages that are OURS and therefore must exist in this repo.
_FIRST_PARTY = {
    "tools",
    "centurion",
    "centurion_cli",
    "gateway",
    "agent",
    "plugins",
}

# Modules that are intentionally absent, with the reason each is allowed to be.
# Keep this list short and justified.
_OPTIONAL_BY_DESIGN = {
    # agent/system_prompt.py guards this in try/except: a presence/consent
    # enrichment that contributes nothing when the module is not present.
    "tools.choice_architecture": "optional prompt enrichment, guarded in agent/system_prompt.py",
    "tools.life_structure": "optional prompt enrichment, guarded in agent/system_prompt.py",
    # tui_gateway/render.py documents the fallback in its own docstring: without
    # the module the TUI uses its own markdown.tsx renderer.
    "agent.rich_output": "optional TUI renderer; documented fallback to markdown.tsx",
}


def _first_party_module(node: ast.AST) -> str | None:
    """Return the imported module name if it is one of ours, else None."""
    if isinstance(node, ast.ImportFrom) and node.module:
        return node.module if node.module.split(".")[0] in _FIRST_PARTY else None
    if isinstance(node, ast.Import):
        for alias in node.names:
            if alias.name.split(".")[0] in _FIRST_PARTY:
                return alias.name
    return None


def _iter_shipped_python_files():
    for dirpath, dirnames, filenames in os.walk(REPO_ROOT):
        dirnames[:] = [d for d in dirnames if d not in _SKIP_DIRS]
        for filename in filenames:
            if filename.endswith(".py"):
                yield os.path.join(dirpath, filename)


def _collect_first_party_imports():
    """-> {module_name: sorted set of repo-relative files importing it}."""
    found: dict[str, set[str]] = {}
    for path in _iter_shipped_python_files():
        try:
            with open(path, encoding="utf-8", errors="replace") as handle:
                tree = ast.parse(handle.read())
        except (SyntaxError, OSError):
            # Not this test's job to police syntax; other tests do that.
            continue
        rel = os.path.relpath(path, REPO_ROOT)
        for node in ast.walk(tree):
            module = _first_party_module(node)
            if module:
                found.setdefault(module, set()).add(rel)
    return found


def _resolves(module: str, cache: dict[str, bool]) -> bool:
    if module not in cache:
        if REPO_ROOT not in sys.path:
            sys.path.insert(0, REPO_ROOT)
        try:
            cache[module] = importlib.util.find_spec(module) is not None
        except (ImportError, ModuleNotFoundError, ValueError):
            cache[module] = False
    return cache[module]


def test_every_first_party_import_resolves():
    """The guard. This is the test that would have caught tools.fleet_tools."""
    imports = _collect_first_party_imports()
    assert imports, "found no first-party imports at all -- is the sweep broken?"

    cache: dict[str, bool] = {}
    missing = {
        module: sorted(files)
        for module, files in imports.items()
        if module not in _OPTIONAL_BY_DESIGN and not _resolves(module, cache)
    }

    if missing:
        lines = [
            "These first-party modules are imported but do not exist in the tree:",
            "",
        ]
        for module in sorted(missing):
            lines.append(f"  {module}")
            for ifile in missing[module]:
                lines.append(f"      imported by {ifile}")
        lines += [
            "",
            "Fix the code, or -- only if the module is optional BY DESIGN -- add it",
            "to _OPTIONAL_BY_DESIGN in this test with a one-line justification.",
            "See the module docstring: this exact shape shipped as the dead",
            "fleet_status / fleet_ping handlers.",
        ]
        pytest.fail("\n".join(lines))


def test_optional_allowlist_entries_are_still_genuinely_absent():
    """Keep the allowlist honest.

    If one of these modules is ever created, its entry here is stale and should
    be deleted -- otherwise a real future failure could hide behind an allowlist
    row that no longer means anything.
    """
    cache: dict[str, bool] = {}
    now_present = sorted(m for m in _OPTIONAL_BY_DESIGN if _resolves(m, cache))
    assert not now_present, (
        "These modules now exist, so their _OPTIONAL_BY_DESIGN entries are stale "
        f"and must be removed: {now_present}"
    )


def test_fleet_bridge_actions_have_live_handlers():
    """The specific surface that broke, asserted by name.

    The two fleet handlers must import something that exists, and the dispatch
    table must still route to them. Narrow on purpose: it names the fault so a
    future regression reads as the same bug rather than a generic import error.
    """
    bridge_path = os.path.join(REPO_ROOT, "centurion_cli", "remote_bridge.py")
    assert os.path.exists(bridge_path), bridge_path

    with open(bridge_path, encoding="utf-8") as handle:
        source = handle.read()
    tree = ast.parse(source)

    # The dispatch table itself must still list the actions the app calls.
    for action in ("fleet_status", "fleet_ping"):
        assert f'action == "{action}"' in source, (
            f"{action} is no longer dispatched -- the app calls it, so removing it "
            "would silently break the Connect screen."
        )

    # Every module the fleet handlers import must exist.
    handlers = {"_handle_fleet_status", "_handle_fleet_ping"}
    cache: dict[str, bool] = {}
    for node in ast.walk(tree):
        if not isinstance(node, ast.FunctionDef) or node.name not in handlers:
            continue
        for inner in ast.walk(node):
            module = _first_party_module(inner)
            if module:
                assert _resolves(module, cache), (
                    f"{node.name} imports '{module}', which does not exist. "
                    "This is the dead-handler defect: the action is reachable "
                    "from the UI and will fail on every call."
                )
