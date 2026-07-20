#!/usr/bin/env python3
"""Build Centurion IT & Security one-pager PDF from HTML.

Source: website/static/it-security/index.html
Output: website/static/it-security/centurion-it-security.pdf

Uses system Chrome/Chromium/Edge in headless print-to-PDF mode.
No extra Python packages required.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
HTML_PATH = REPO_ROOT / "website" / "static" / "it-security" / "index.html"
DEFAULT_PDF = REPO_ROOT / "website" / "static" / "it-security" / "centurion-it-security.pdf"

# Prefer branded email filename when copying for distribution; primary artifact
# stays at DEFAULT_PDF for the docs site.
EMAIL_PDF_NAME = "Centurion-IT-Security-One-Pager.pdf"

_BROWSER_CANDIDATES = [
    # macOS
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    # PATH names
    "google-chrome",
    "google-chrome-stable",
    "chromium",
    "chromium-browser",
    "chrome",
    "msedge",
]


def _find_browser() -> str | None:
    for candidate in _BROWSER_CANDIDATES:
        if "/" in candidate:
            if Path(candidate).is_file():
                return candidate
        else:
            found = shutil.which(candidate)
            if found:
                return found
    return None


def _print_fallback(html: Path, pdf: Path) -> None:
    print(
        "No Chrome/Chromium/Edge found for headless PDF generation.\n\n"
        "Manual fallback:\n"
        f"  1. Open: {html}\n"
        "  2. Browser → Print → Save as PDF (A4, background graphics on)\n"
        f"  3. Save as: {pdf}\n"
        f"  4. Optional email copy name: {EMAIL_PDF_NAME}\n",
        file=sys.stderr,
    )


def build_pdf(*, html: Path, pdf: Path, browser: str | None = None) -> int:
    if not html.is_file():
        print(f"HTML source not found: {html}", file=sys.stderr)
        return 1

    browser = browser or _find_browser()
    if not browser:
        _print_fallback(html, pdf)
        return 2

    pdf.parent.mkdir(parents=True, exist_ok=True)
    # file:// URL for local HTML
    html_url = html.resolve().as_uri()

    cmd = [
        browser,
        "--headless=new",
        "--disable-gpu",
        "--no-pdf-header-footer",
        "--no-first-run",
        "--no-default-browser-check",
        f"--print-to-pdf={pdf.resolve()}",
        html_url,
    ]

    print(f"Building PDF with: {browser}")
    print(f"  HTML → {html}")
    print(f"  PDF  → {pdf}")
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f"Browser PDF failed: {exc}", file=sys.stderr)
        _print_fallback(html, pdf)
        return 3

    if result.returncode != 0 or not pdf.is_file() or pdf.stat().st_size < 500:
        print("Headless print-to-PDF did not produce a valid PDF.", file=sys.stderr)
        if result.stderr:
            print(result.stderr.strip(), file=sys.stderr)
        _print_fallback(html, pdf)
        return 4

    # Also write the email-friendly filename next to the artifact.
    email_copy = pdf.parent / EMAIL_PDF_NAME
    shutil.copy2(pdf, email_copy)
    print(f"OK ({pdf.stat().st_size:,} bytes)")
    print(f"Email copy → {email_copy}")

    # Keep the sales-site public copy in lockstep when that checkout is present.
    sales_pdf = Path.home() / "-personal-centurion-website-v5" / "public" / EMAIL_PDF_NAME
    if sales_pdf.parent.is_dir():
        shutil.copy2(pdf, sales_pdf)
        print(f"Sales site copy → {sales_pdf}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--html",
        type=Path,
        default=HTML_PATH,
        help="Path to source HTML (default: website/static/it-security/index.html)",
    )
    parser.add_argument(
        "--pdf",
        type=Path,
        default=DEFAULT_PDF,
        help="Output PDF path",
    )
    parser.add_argument(
        "--browser",
        default=None,
        help="Path or name of Chrome/Chromium/Edge binary",
    )
    args = parser.parse_args(argv)
    return build_pdf(html=args.html, pdf=args.pdf, browser=args.browser)


if __name__ == "__main__":
    raise SystemExit(main())
