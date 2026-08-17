"""Family Beneficiary + lead capture → GoHighLevel / DrivenAction.

Brain You and iPhone You capture (1) a family-beneficiary first name and
(2) colleague leads (name, email, phone). This module upserts those contacts
into GHL (DrivenAction) for nurture and, on snapshot refresh, checks GHL tags
to credit successful purchases toward the Family Beneficiary fee machine
(4 purchases → complimentary Centurion).

Secrets (Brain ``~/.centurion/.env`` only — never ship in the iPhone binary):
  GHL_API_KEY
  GHL_LOCATION_ID

All network calls are best-effort.
"""

from __future__ import annotations

import json
import logging
import os
import re
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

logger = logging.getLogger(__name__)

GHL_BASE = "https://services.leadconnectorhq.com"
GHL_VERSION = "2021-07-28"

# Tags that mean "this referral bought Centurion" for fee-machine credit.
_PURCHASED_TAGS = frozenset(
    {
        "centurion-referral-purchased",
        "centurion-customer",
        "centurion-purchased",
    }
)


def _ghl_credentials() -> tuple[str, str] | None:
    api_key = (os.environ.get("GHL_API_KEY") or "").strip()
    location_id = (os.environ.get("GHL_LOCATION_ID") or "").strip()
    if not api_key or not location_id:
        try:
            from centurion_cli.config import load_config

            cfg = load_config() or {}
            section = cfg.get("ghl") if isinstance(cfg.get("ghl"), dict) else {}
            api_key = api_key or str(section.get("api_key") or "").strip()
            location_id = location_id or str(section.get("location_id") or "").strip()
        except Exception:
            pass
    if not api_key or not location_id:
        return None
    return api_key, location_id


def is_ghl_configured() -> bool:
    return _ghl_credentials() is not None


def _install_id() -> str:
    try:
        from centurion_cli.remote_relay_service import ensure_install_id

        return ensure_install_id()
    except Exception:
        return ""


def _slug(value: str, *, max_len: int = 32) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", (value or "").strip().lower()).strip("-")
    return s[:max_len]


def _split_name(name: str) -> tuple[str | None, str | None]:
    parts = (name or "").strip().split()
    if not parts:
        return None, None
    if len(parts) == 1:
        return parts[0], None
    return parts[0], " ".join(parts[1:])


def _request(
    method: str,
    path: str,
    *,
    body: dict[str, Any] | None = None,
    timeout: float = 12.0,
) -> dict[str, Any] | None:
    creds = _ghl_credentials()
    if not creds:
        return None
    api_key, _location = creds
    url = f"{GHL_BASE}{path}"
    data = None if body is None else json.dumps(body).encode("utf-8")
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Version": GHL_VERSION,
        "Accept": "application/json",
        "User-Agent": "Centurion-Brain-GHL/1.0",
    }
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            if not raw:
                return {}
            return json.loads(raw)
    except HTTPError as exc:
        detail = ""
        try:
            detail = exc.read().decode("utf-8", errors="replace")[:400]
        except Exception:
            pass
        logger.warning("GHL HTTP %s %s: %s", exc.code, path, detail)
        return None
    except (URLError, TimeoutError, json.JSONDecodeError, OSError) as exc:
        logger.warning("GHL unreachable: %s", exc)
        return None


def _referral_tags(*, pending: bool = False, purchased: bool = False) -> list[str]:
    tags = [
        "drivenaction",
        "drivenaction-lead",
        "centurion-referral",
        "centurion-family-beneficiary",
    ]
    if pending:
        tags.append("centurion-referral-pending")
    if purchased:
        tags.extend(["centurion-referral-purchased", "centurion-customer"])
    install = _install_id()
    if install:
        tags.append(f"centurion-referrer-{_slug(install)}")
    return tags


def push_colleague_referral(referral: dict[str, Any]) -> None:
    """Upsert a colleague referral into GHL for nurture + later purchase tracking."""
    if not _ghl_credentials():
        logger.info("GHL referral push skipped — set GHL_API_KEY and GHL_LOCATION_ID")
        return

    api_key_location = _ghl_credentials()
    assert api_key_location is not None
    _, location_id = api_key_location

    name = str(referral.get("name") or "").strip()
    email = str(referral.get("email") or "").strip().lower()
    phone = str(referral.get("phone") or "").strip()
    referral_id = str(referral.get("id") or "").strip()
    if not name or (not email and not phone):
        return

    first, last = _split_name(name)
    body: dict[str, Any] = {
        "locationId": location_id,
        "source": "centurion-iphone-family-referral | DrivenAction",
        "tags": _referral_tags(pending=True),
    }
    if email:
        body["email"] = email
    if phone:
        body["phone"] = phone
    if first:
        body["firstName"] = first
    if last:
        body["lastName"] = last
    note_bits = [f"Family Beneficiary referral {referral_id}"]
    install = _install_id()
    if install:
        note_bits.append(f"referrer install {install}")
    body["source"] = f"centurion-iphone | DrivenAction | {' | '.join(note_bits)}"

    # Prefer upsert when we have email; otherwise create-only with phone.
    path = "/contacts/upsert" if email else "/contacts/"
    result = _request("POST", path, body=body)
    if result is not None:
        logger.info("GHL referral upserted id=%s email=%s", referral_id, email or "(phone)")


def push_family_nomination(first_name: str) -> None:
    """Upsert a family-beneficiary nomination into GHL / DrivenAction.

    Nominations are first-name only. GHL upsert accepts firstName + lastName
    without email/phone, which is enough to land the lead for nurture.
    """
    name = str(first_name or "").strip()
    if not name:
        return
    if not _ghl_credentials():
        logger.info("GHL family nomination skipped — set GHL_API_KEY and GHL_LOCATION_ID")
        return

    api_key_location = _ghl_credentials()
    assert api_key_location is not None
    _, location_id = api_key_location

    install = _install_id()
    tags = [
        "drivenaction",
        "drivenaction-lead",
        "centurion-family-beneficiary",
        "centurion-family-nominee",
    ]
    if install:
        tags.append(f"centurion-referrer-{_slug(install)}")

    note_bits = [f"Family beneficiary nominated: {name}"]
    if install:
        note_bits.append(f"referrer install {install}")

    body: dict[str, Any] = {
        "locationId": location_id,
        "firstName": name,
        "lastName": "Family nominee",
        "source": f"centurion-family-nomination | DrivenAction | {' | '.join(note_bits)}",
        "tags": tags,
    }
    result = _request("POST", "/contacts/upsert", body=body)
    if result is not None:
        logger.info("GHL family nomination upserted name=%s", name)


def _contact_tags(contact: dict[str, Any]) -> set[str]:
    raw = contact.get("tags") or []
    tags: set[str] = set()
    if isinstance(raw, list):
        for item in raw:
            if isinstance(item, str):
                tags.add(item.strip().lower())
            elif isinstance(item, dict):
                name = item.get("name") or item.get("tag") or ""
                if name:
                    tags.add(str(name).strip().lower())
    return tags


def _lookup_contact_by_email(email: str) -> dict[str, Any] | None:
    creds = _ghl_credentials()
    if not creds or not email:
        return None
    _, location_id = creds
    # Duplicate lookup is the lightest path for a single email.
    path = (
        f"/contacts/search/duplicate"
        f"?locationId={quote(location_id)}&email={quote(email)}"
    )
    result = _request("GET", path)
    if not result:
        return None
    contact = result.get("contact")
    if isinstance(contact, dict):
        return contact
    # Some payloads nest under "contacts"
    contacts = result.get("contacts")
    if isinstance(contacts, list) and contacts and isinstance(contacts[0], dict):
        return contacts[0]
    return None


def fetch_successful_referral_ids(pending: list[dict[str, Any]]) -> list[str]:
    """Return referral ids whose GHL contact carries a purchased/customer tag."""
    if not _ghl_credentials() or not pending:
        return []

    out: list[str] = []
    for row in pending:
        if not isinstance(row, dict):
            continue
        rid = str(row.get("id") or "").strip()
        email = str(row.get("email") or "").strip().lower()
        if not rid or not email:
            continue
        contact = _lookup_contact_by_email(email)
        if not contact:
            continue
        tags = _contact_tags(contact)
        if tags & _PURCHASED_TAGS:
            out.append(rid)
    return out
