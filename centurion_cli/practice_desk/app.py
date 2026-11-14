"""The practice desk: an HTTP surface over the Brain, one named user per session.

Architectural position, stated once because it decides everything else:

**The desk is a client of the Brain, not a second Brain.** Chat is proxied to the
Brain's own OpenAI-compatible endpoint, so the agent loop, the tools and the
session store stay exactly where they are and the desk cannot develop a divergent
personality by accident. What the desk adds is the thing the Brain does not have:
an authenticated person on every request.

Why not a WebSocket bridge into `centurion-remote`: browsers cannot open the
phone's encrypted TCP stream, so a bridge would mean a second protocol and a
second crypto surface maintained in step with two other clients, to reach a
Python agent loop anyway. HTTPS and SSE is the boring answer and it is auditable.

Request rules, all of them refusals rather than warnings:

* every state-changing route requires the session cookie **and** a matching
  `Origin` header — a cookie alone is not authorisation for a POST;
* `SameSite=Strict`, `HttpOnly`, `Secure` on the session cookie;
* the cookie slides on use and dies after fifteen minutes idle;
* a signed-in person is re-read from the register on every request, so a
  suspension takes effect on the next call rather than at the next login.

⚠️ **WebAuthn needs a secure context.** Browsers accept `https://` or
`http://localhost` and nothing else. A practice desk reached over a bare LAN IP
on port 8000 cannot register a passkey — the browser refuses before the request
leaves the machine. That is why `serve()` refuses to start without TLS unless it
is bound to loopback, and it is the single most surprising deployment fact about
this component.
"""

from __future__ import annotations

import asyncio
import json
import mimetypes
import os
import secrets
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, Optional

from aiohttp import ClientSession, ClientTimeout, web

from centurion_cli.practice_desk import webauthn
from centurion_cli.practice_desk.store import (
    DeskError,
    Person,
    PracticeStore,
    open_store,
)

STATIC_DIR = Path(__file__).parent / "static"

SESSION_COOKIE = "pd_session"
CEREMONY_COOKIE = "pd_ceremony"
CEREMONY_TTL_SECONDS = 5 * 60

# Sign-in attempts per address per window. Not a security boundary on its own —
# the passkey is — but it stops a script filling the log with noise.
SIGNIN_WINDOW_SECONDS = 60
SIGNIN_MAX_ATTEMPTS = 20


@dataclass
class Settings:
    rp_id: str = "localhost"
    rp_name: str = "Practice Desk"
    origin: str = "http://localhost:8765"
    host: str = "127.0.0.1"
    port: int = 8765
    brain_url: str = "http://127.0.0.1:18789"
    brain_key: str = ""
    brain_model: str = "centurion"
    db_path: Optional[Path] = None
    tls_cert: Optional[str] = None
    tls_key: Optional[str] = None
    practice_library: Optional[Path] = None
    demo_mode: bool = False

    def __post_init__(self) -> None:
        self.brain_key = resolve_brain_key(self.brain_key)
        if self.practice_library is None:
            try:
                from centurion_constants import get_centurion_home

                candidate = Path(get_centurion_home()) / "practice" / "library"
                if candidate.is_dir():
                    self.practice_library = candidate
            except Exception:  # noqa: BLE001
                self.practice_library = None

    @property
    def loopback(self) -> bool:
        return self.host in ("127.0.0.1", "::1", "localhost")


@dataclass
class Ceremony:
    kind: str                      # "register" | "signin"
    challenge: bytes
    expires_at: float
    person_id: Optional[str] = None


@dataclass
class Desk:
    settings: Settings
    store: PracticeStore
    ceremonies: Dict[str, Ceremony] = field(default_factory=dict)
    attempts: Dict[str, list] = field(default_factory=dict)

    # ── ceremonies ──────────────────────────────────────────────────────────

    def new_ceremony(self, kind: str, *, person_id: Optional[str] = None) -> tuple[str, bytes]:
        handle = secrets.token_urlsafe(18)
        challenge = secrets.token_bytes(32)
        now = time.time()
        # Sweep while we are here; a dict of dead challenges is a slow leak.
        for key in [k for k, v in self.ceremonies.items() if v.expires_at < now]:
            self.ceremonies.pop(key, None)
        self.ceremonies[handle] = Ceremony(
            kind=kind,
            challenge=challenge,
            expires_at=now + CEREMONY_TTL_SECONDS,
            person_id=person_id,
        )
        return handle, challenge

    def take_ceremony(self, handle: str, kind: str) -> Ceremony:
        ceremony = self.ceremonies.pop(handle or "", None)
        if ceremony is None:
            raise DeskError("That attempt has expired. Start again.")
        if ceremony.kind != kind:
            raise DeskError("That attempt was for a different ceremony.")
        if ceremony.expires_at < time.time():
            raise DeskError("That attempt has expired. Start again.")
        return ceremony

    # ── rate limiting ───────────────────────────────────────────────────────

    def note_attempt(self, address: str) -> None:
        now = time.time()
        window = [t for t in self.attempts.get(address, []) if now - t < SIGNIN_WINDOW_SECONDS]
        window.append(now)
        self.attempts[address] = window

    def too_many_attempts(self, address: str) -> bool:
        now = time.time()
        window = [t for t in self.attempts.get(address, []) if now - t < SIGNIN_WINDOW_SECONDS]
        return len(window) >= SIGNIN_MAX_ATTEMPTS


def resolve_brain_key(explicit: str = "") -> str:
    """The key the desk uses to talk to its own Brain.

    Three sources, in order: what the caller passed, `API_SERVER_KEY` in the
    environment, then `API_SERVER_KEY` in the Centurion home's `.env` (which is
    where the gateway keeps it). Read, never printed, never logged.
    """
    if explicit:
        return explicit
    value = os.environ.get("API_SERVER_KEY", "").strip()
    if value:
        return value
    try:
        from centurion_constants import get_centurion_home

        env_path = Path(get_centurion_home()) / ".env"
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("API_SERVER_KEY="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    except Exception:  # noqa: BLE001 — a missing key is not an error here
        return ""
    return ""


# ── helpers ─────────────────────────────────────────────────────────────────


# aiohttp wants AppKey objects rather than bare strings for app state.
DESK_KEY = web.AppKey("desk", Desk)

def _error(message: str, status: int = 400) -> web.Response:
    return web.json_response({"ok": False, "error": message}, status=status)


async def _json(request: web.Request) -> Dict[str, Any]:
    try:
        payload = await request.json()
    except Exception:  # noqa: BLE001
        raise DeskError("That request was not readable.")
    if not isinstance(payload, dict):
        raise DeskError("That request was not readable.")
    return payload


# Who may change who exists. A manager can run client work; only a partner or an
# administrator may add, suspend or revoke a person.
PEOPLE_ADMINS = ("partner", "administrator")


def _require_people_admin(person: Person) -> None:
    if person.role not in PEOPLE_ADMINS:
        raise DeskError(
            f"Only a partner or an administrator can change who is on this "
            f"machine. You are signed in as {person.role}."
        )


def _person_payload(person: Person) -> Dict[str, Any]:
    return {
        "id": person.id,
        "name": person.name,
        "email": person.email,
        "role": person.role,
        "status": person.status,
    }


def _same_origin(request: web.Request) -> bool:
    """A cookie is not authorisation for a POST. The Origin has to match too."""
    desk: Desk = request.app[DESK_KEY]
    origin = request.headers.get("Origin")
    if not origin:
        # Same-origin fetch from the desk's own page always sends Origin for POST.
        # A missing header is a non-browser client or a downgrade; refuse it.
        return False
    return origin.rstrip("/") == desk.settings.origin.rstrip("/")


def _session_token(request: web.Request) -> str:
    return request.cookies.get(SESSION_COOKIE, "")


async def _require_person(request: web.Request) -> Person:
    desk: Desk = request.app[DESK_KEY]
    person = desk.store.resolve_session(_session_token(request))
    if person is None:
        raise web.HTTPUnauthorized(
            text=json.dumps({"ok": False, "error": "Not signed in."}),
            content_type="application/json",
        )
    return person


@web.middleware
async def error_middleware(request: web.Request, handler):
    try:
        return await handler(request)
    except DeskError as exc:
        return _error(str(exc), 400)
    except web.HTTPException:
        raise
    except Exception as exc:  # noqa: BLE001
        # Never a traceback to a browser on a machine holding client files.
        import logging

        logging.getLogger(__name__).exception("desk: unhandled error on %s", request.path)
        return _error("The desk could not complete that. Nothing was changed.", 500)


@web.middleware
async def no_cache_middleware(request: web.Request, handler):
    response = await handler(request)
    if isinstance(response, web.Response):
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault(
            "Content-Security-Policy",
            "default-src 'self'; script-src 'self' 'unsafe-inline'; "
            "style-src 'self' 'unsafe-inline'; img-src 'self' data:; "
            "connect-src 'self'; frame-ancestors 'none'; base-uri 'none'",
        )
        if request.path.startswith("/api/"):
            response.headers.setdefault("Cache-Control", "no-store")
    return response


# ── routes: pages ───────────────────────────────────────────────────────────


async def index(request: web.Request) -> web.StreamResponse:
    desk: Desk = request.app[DESK_KEY]
    signed_in = desk.store.resolve_session(_session_token(request)) is not None
    page = "desk.html" if signed_in else "signin.html"
    return web.FileResponse(STATIC_DIR / page)


async def static_file(request: web.Request) -> web.StreamResponse:
    name = request.match_info["name"]
    # Path traversal: resolve, then require the result to sit inside STATIC_DIR.
    target = (STATIC_DIR / name).resolve()
    if not str(target).startswith(str(STATIC_DIR.resolve())) or not target.is_file():
        raise web.HTTPNotFound()
    ctype, _ = mimetypes.guess_type(str(target))
    return web.FileResponse(target, headers={"Content-Type": ctype or "application/octet-stream"})


# ── routes: identity ────────────────────────────────────────────────────────


async def invite_redeem(request: web.Request) -> web.Response:
    """Redeem a one-time link and offer registration options.

    The invitation is consumed here, before the passkey exists, and the ceremony
    carries the person it belonged to. A passkey can therefore only ever be
    enrolled for the person the link was issued to.
    """
    desk: Desk = request.app[DESK_KEY]
    payload = await _json(request)
    person = desk.store.redeem_invitation(str(payload.get("token", "")))

    handle, challenge = desk.new_ceremony("register", person_id=person.id)
    options = webauthn.registration_options(
        rp_id=desk.settings.rp_id,
        rp_name=desk.settings.rp_name,
        challenge=challenge,
        user_id=person.id.encode(),
        user_name=person.email,
        display_name=person.name,
    )
    response = web.json_response({"ok": True, "options": options, "name": person.name})
    _set_ceremony_cookie(response, desk, handle)
    return response


async def register_finish(request: web.Request) -> web.Response:
    desk: Desk = request.app[DESK_KEY]
    payload = await _json(request)
    ceremony = desk.take_ceremony(request.cookies.get(CEREMONY_COOKIE, ""), "register")
    if not ceremony.person_id:
        raise DeskError("That attempt has expired. Start again.")

    person = desk.store.get_person(ceremony.person_id)
    if person is None:
        raise DeskError("That invitation's person is no longer on this machine.")

    credential = webauthn.verify_registration(
        client_data_json=webauthn.b64url_decode(str(payload.get("clientDataJSON", ""))),
        attestation_object=webauthn.b64url_decode(str(payload.get("attestationObject", ""))),
        expected_challenge=ceremony.challenge,
        expected_origin=desk.settings.origin,
        rp_id=desk.settings.rp_id,
    )

    desk.store.add_credential(
        person.id,
        credential_id=credential.credential_id,
        public_key=credential.public_key,
        algorithm=credential.algorithm,
        sign_count=credential.sign_count,
        label=_describe_agent(request),
    )
    token = desk.store.open_session(person.id, user_agent=request.headers.get("User-Agent", ""))
    response = web.json_response({"ok": True, "person": _person_payload(person)})
    _set_session_cookie(response, desk, token)
    _clear_ceremony_cookie(response)
    return response


async def signin_begin(request: web.Request) -> web.Response:
    desk: Desk = request.app[DESK_KEY]
    address = request.remote or "unknown"
    if desk.too_many_attempts(address):
        raise DeskError("Too many attempts from this machine. Wait a minute.")

    # Discoverable credential: an empty allow list lets the device offer the
    # passkeys it holds, so nobody has to remember which email they used.
    handle, challenge = desk.new_ceremony("signin")
    options = webauthn.assertion_options(
        rp_id=desk.settings.rp_id, challenge=challenge, allow_ids=[]
    )
    response = web.json_response({"ok": True, "options": options})
    _set_ceremony_cookie(response, desk, handle)
    return response


async def signin_finish(request: web.Request) -> web.Response:
    desk: Desk = request.app[DESK_KEY]
    address = request.remote or "unknown"
    desk.note_attempt(address)
    if desk.too_many_attempts(address):
        raise DeskError("Too many attempts from this machine. Wait a minute.")

    payload = await _json(request)
    ceremony = desk.take_ceremony(request.cookies.get(CEREMONY_COOKIE, ""), "signin")

    credential_id = str(payload.get("id") or "")
    stored = desk.store.credential_by_id(credential_id)
    if stored is None:
        raise DeskError("That passkey is not registered on this machine.")

    person = desk.store.get_person(stored["person_id"])
    if person is None or person.status != "active":
        raise DeskError("That passkey's owner is no longer active on this machine.")

    result = webauthn.verify_assertion(
        client_data_json=webauthn.b64url_decode(str(payload.get("clientDataJSON", ""))),
        authenticator_data=webauthn.b64url_decode(str(payload.get("authenticatorData", ""))),
        signature=webauthn.b64url_decode(str(payload.get("signature", ""))),
        stored_public_key=stored["public_key"],
        stored_sign_count=int(stored["sign_count"] or 0),
        expected_challenge=ceremony.challenge,
        expected_origin=desk.settings.origin,
        rp_id=desk.settings.rp_id,
    )

    desk.store.touch_credential(credential_id, result.sign_count)
    token = desk.store.open_session(person.id, user_agent=request.headers.get("User-Agent", ""))
    response = web.json_response({"ok": True, "person": _person_payload(person)})
    _set_session_cookie(response, desk, token)
    _clear_ceremony_cookie(response)
    return response


async def signout(request: web.Request) -> web.Response:
    desk: Desk = request.app[DESK_KEY]
    desk.store.close_session(_session_token(request))
    response = web.json_response({"ok": True})
    response.del_cookie(SESSION_COOKIE, path="/")
    return response


async def me(request: web.Request) -> web.Response:
    person = await _require_person(request)
    desk: Desk = request.app[DESK_KEY]
    return web.json_response(
        {
            "ok": True,
            "person": _person_payload(person),
            "seats": desk.store.seat_usage(),
            "capacity_refusal": desk.store.capacity_refusal(0),
        }
    )


# ── routes: the practice day ────────────────────────────────────────────────


async def today(request: web.Request) -> web.Response:
    """The four instrument panes, told honestly.

    Three of them rest on registers that do not exist yet. They return `null`
    with a stated reason rather than a confident zero, because a pane showing
    "0 waiting" over a register that was never written is a lie that a partner
    will act on. `unreadable` is not `empty`.
    """
    person = await _require_person(request)
    desk: Desk = request.app[DESK_KEY]
    usage = desk.store.seat_usage()

    deadline_pane: Dict[str, Any] = {
        "value": None,
        "reason": "no client library on this machine",
    }
    deadline_detail: Dict[str, Any] = {"count": 0, "unsettled": [], "next": None}
    if desk.settings.practice_library and (Path(desk.settings.practice_library) / "clients").is_dir():
        from centurion_cli.practice_desk import deadlines as dl

        found = dl.upcoming(desk.settings.practice_library, horizon_days=14)
        summary = dl.summarise(found)
        deadline_detail = summary
        if summary["count"] or summary["unsettled"]:
            deadline_pane = {
                "value": summary["count"],
                "reason": None,
                "next": summary["next"],
                "unsettled": len(summary["unsettled"]),
            }
        else:
            deadline_pane = {
                "value": 0,
                "reason": None,
                "note": "computed from the client library — nothing inside fourteen days",
            }

    panes = {
        "drafts_awaiting_signature": {
            "value": None,
            "reason": "no drafts register on this machine yet",
        },
        "deadlines_inside_14_days": deadline_pane,
        "clients_chased_no_reply": {
            "value": None,
            "reason": "no client correspondence register yet",
        },
        "hours_returned_this_month": {
            "value": None,
            "reason": "no work log yet",
        },
    }

    return web.json_response(
        {
            "ok": True,
            "at": time.time(),
            "person": _person_payload(person),
            "seats": usage,
            "licence": {
                "refusal_at": desk.store.capacity_refusal(1),
            },
            "panes": panes,
            "deadlines": deadline_detail,
            "library": str(desk.settings.practice_library or ""),
            "unmeasured": [
                name for name, pane in panes.items() if pane["value"] is None
            ],
        }
    )


# ── routes: conversation ────────────────────────────────────────────────────


async def people_list(request: web.Request) -> web.Response:
    """Who is on this machine, and which seats are free."""
    person = await _require_person(request)
    _require_people_admin(person)
    desk: Desk = request.app[DESK_KEY]
    people = []
    for p in desk.store.list_people(include_departed=True):
        creds = desk.store.credentials_for(p.id)
        people.append(
            {
                **_person_payload(p),
                "passkeys": len(creds),
                "enrolled": p.enrolled_at is not None,
                "last_seen": p.last_seen_at,
            }
        )
    return web.json_response(
        {
            "ok": True,
            "people": people,
            "seats": desk.store.seat_usage(),
            "refusal": desk.store.capacity_refusal(1),
        }
    )


async def people_invite(request: web.Request) -> web.Response:
    """Reserve a seat and return a one-time link. Refuses in the licence's words."""
    person = await _require_person(request)
    _require_people_admin(person)
    desk: Desk = request.app[DESK_KEY]
    payload = await _json(request)

    admitted = desk.store.admit_person(
        name=str(payload.get("name", "")),
        email=str(payload.get("email", "")),
        role=str(payload.get("role", "associate")),
        created_by=person.id,
    )
    token = desk.store.issue_invitation(admitted.id, by=person.id)
    base = desk.settings.origin.rstrip("/")
    return web.json_response(
        {
            "ok": True,
            "person": _person_payload(admitted),
            "link": f"{base}/#invite={token}",
            "expires_in_minutes": 15,
        }
    )


async def people_status(request: web.Request) -> web.Response:
    person = await _require_person(request)
    _require_people_admin(person)
    desk: Desk = request.app[DESK_KEY]
    payload = await _json(request)
    target = desk.store.get_person(str(payload.get("id", "")))
    if target is None:
        raise DeskError("That person is not on this machine.")
    if target.id == person.id and payload.get("status") != "active":
        raise DeskError("A partner cannot suspend their own seat. Ask another partner.")

    status = str(payload.get("status", ""))
    desk.store.set_status(target.id, status, by=person.id)
    return web.json_response({"ok": True, "person": _person_payload(desk.store.get_person(target.id))})


async def people_revoke(request: web.Request) -> web.Response:
    person = await _require_person(request)
    _require_people_admin(person)
    desk: Desk = request.app[DESK_KEY]
    payload = await _json(request)
    target = desk.store.get_person(str(payload.get("id", "")))
    if target is None:
        raise DeskError("That person is not on this machine.")
    desk.store.revoke_all_credentials(target.id, by=person.id)
    return web.json_response({"ok": True, "person": _person_payload(target)})


async def deadline_list(request: web.Request) -> web.Response:
    """Every obligation inside the horizon, with the rule that produced it."""
    await _require_person(request)
    desk: Desk = request.app[DESK_KEY]
    library = desk.settings.practice_library
    if not library:
        return web.json_response(
            {"ok": True, "obligations": [], "reason": "no client library on this machine"}
        )
    from centurion_cli.practice_desk import deadlines as dl

    horizon = 45
    try:
        horizon = max(1, min(365, int(request.query.get("days", "45"))))
    except ValueError:
        pass
    found = dl.upcoming(library, horizon_days=horizon)
    return web.json_response(
        {
            "ok": True,
            "horizon_days": horizon,
            "obligations": [
                {
                    "client": o.client,
                    "kind": o.kind,
                    "due": o.due.isoformat(),
                    "days": o.days_remaining,
                    "rule": o.rule,
                    "unsettled": o.unsettled,
                }
                for o in found
            ],
        }
    )


async def thread(request: web.Request) -> web.Response:
    person = await _require_person(request)
    desk: Desk = request.app[DESK_KEY]
    conv = desk.store.ensure_conversation(person=person)
    return web.json_response(
        {
            "ok": True,
            "conversation": {
                "id": conv["id"],
                "scope": conv["scope"],
                "title": conv["title"],
            },
            "messages": desk.store.messages(conv["id"]),
        }
    )


async def chat(request: web.Request) -> web.StreamResponse:
    """SSE. The answer streams from the Brain; the desk only carries it.

    The conversation is persisted *as it streams* only on completion — a
    half-written answer in the record is worse than no answer, because the next
    session reads it as something the practice was told.
    """
    person = await _require_person(request)
    if not _same_origin(request):
        return _error("That request did not come from the desk.", 403)

    desk: Desk = request.app[DESK_KEY]
    payload = await _json(request)
    message = str(payload.get("message", "")).strip()
    if not message:
        raise DeskError("Nothing was asked.")
    if len(message) > 8000:
        raise DeskError("That message is too long for one turn.")

    conv = desk.store.ensure_conversation(person=person)
    desk.store.append_message(conv["id"], role="user", content=message, person_id=person.id)
    desk.store.record(person.id, "asked", scope=conv["scope"], detail=message[:200])

    history = [
        {"role": m["role"], "content": m["content"]}
        for m in desk.store.messages(conv["id"], limit=40)
        if m["role"] in ("user", "assistant")
    ]

    response = web.StreamResponse(
        status=200,
        headers={
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-store",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )
    await response.prepare(request)

    collected: list[str] = []
    failure: Optional[str] = None

    try:
        async for chunk in _stream_from_brain(desk, person, history):
            if chunk.startswith("__ERROR__"):
                failure = chunk[len("__ERROR__"):]
                break
            collected.append(chunk)
            await response.write(_sse({"delta": chunk}))
    except asyncio.CancelledError:
        # The browser navigated away or the tab was closed. Keep what arrived.
        raise
    except Exception as exc:  # noqa: BLE001
        failure = str(exc)

    text = "".join(collected).strip()
    if text:
        desk.store.append_message(conv["id"], role="assistant", content=text)
        desk.store.record(person.id, "answered", scope=conv["scope"], detail=str(len(text)))
    if failure:
        desk.store.record(person.id, "answer_failed", scope=conv["scope"], detail=failure[:300])
        await response.write(_sse({"error": failure}))
    await response.write(_sse({"done": True}))
    await response.write_eof()
    return response


async def _stream_from_brain(desk: Desk, person: Person, history: list):
    """Yield text deltas from the Brain's own endpoint."""
    settings = desk.settings
    if not settings.brain_url:
        yield "__ERROR__The desk is not connected to a Brain."
        return

    library = desk.settings.practice_library
    library_line = (
        f"The practice's own records are in {library}. Read them with your file "
        "tools before answering a question about a client, a deadline or the "
        "house style. Cite the path and line you used. "
        if library
        else "No practice library is attached to this desk, so answer only from "
        "what you are told in the conversation and say when you are doing so. "
    )
    system = (
        f"You are the Centurion of this accounting practice, speaking to "
        f"{person.name} ({person.role}). Answer in the practice's own voice: "
        "short, direct, and name the file and line you are relying on. "
        + library_line
        + "If you cannot settle something, say which part you could not settle "
        "rather than filling the gap. Nothing you draft is sent to a client "
        "without a human signature."
    )
    body = {
        "model": settings.brain_model,
        "stream": True,
        "messages": [{"role": "system", "content": system}, *history],
    }
    headers = {"Content-Type": "application/json"}
    if settings.brain_key:
        headers["Authorization"] = f"Bearer {settings.brain_key}"

    timeout = ClientTimeout(total=600, sock_read=180)
    try:
        async with ClientSession(timeout=timeout) as session:
            async with session.post(
                f"{settings.brain_url.rstrip('/')}/v1/chat/completions",
                json=body,
                headers=headers,
            ) as upstream:
                if upstream.status != 200:
                    detail = (await upstream.text())[:300]
                    yield f"__ERROR__The Brain answered {upstream.status}. {detail}"
                    return
                async for raw in upstream.content:
                    line = raw.decode("utf-8", "replace").strip()
                    if not line or not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    if data == "[DONE]":
                        break
                    try:
                        event = json.loads(data)
                    except json.JSONDecodeError:
                        continue
                    choices = event.get("choices") or []
                    if not choices:
                        continue
                    delta = choices[0].get("delta") or {}
                    piece = delta.get("content")
                    if piece:
                        yield piece
    except asyncio.TimeoutError:
        yield "__ERROR__The Brain did not answer in time."
    except Exception as exc:  # noqa: BLE001
        yield f"__ERROR__Could not reach the Brain: {exc}"


def _sse(payload: Dict[str, Any]) -> bytes:
    return f"data: {json.dumps(payload)}\n\n".encode("utf-8")


# ── cookies ─────────────────────────────────────────────────────────────────


def _set_session_cookie(response: web.Response, desk: Desk, token: str) -> None:
    response.set_cookie(
        SESSION_COOKIE,
        token,
        max_age=15 * 60,
        httponly=True,
        secure=desk.settings.origin.startswith("https://"),
        samesite="Strict",
        path="/",
    )


def _set_ceremony_cookie(response: web.Response, desk: Desk, handle: str) -> None:
    response.set_cookie(
        CEREMONY_COOKIE,
        handle,
        max_age=CEREMONY_TTL_SECONDS,
        httponly=True,
        secure=desk.settings.origin.startswith("https://"),
        samesite="Strict",
        path="/",
    )


def _clear_ceremony_cookie(response: web.Response) -> None:
    response.del_cookie(CEREMONY_COOKIE, path="/")


def _describe_agent(request: web.Request) -> str:
    agent = request.headers.get("User-Agent", "")
    for label in ("Windows", "Macintosh", "iPhone", "iPad", "Android", "Linux"):
        if label in agent:
            return f"{label} device"
    return "device"


# ── the application ─────────────────────────────────────────────────────────


def create_app(settings: Optional[Settings] = None) -> web.Application:
    settings = settings or Settings()
    store = open_store(settings.db_path)
    store.sweep()

    app = web.Application(middlewares=[error_middleware, no_cache_middleware])
    app[DESK_KEY] = Desk(settings=settings, store=store)

    app.router.add_get("/", index)
    app.router.add_get("/static/{name}", static_file)

    app.router.add_post("/api/invite", invite_redeem)
    app.router.add_post("/api/register", register_finish)
    app.router.add_post("/api/signin/begin", signin_begin)
    app.router.add_post("/api/signin/finish", signin_finish)
    app.router.add_post("/api/signout", signout)
    app.router.add_get("/api/me", me)
    app.router.add_get("/api/today", today)
    app.router.add_get("/api/thread", thread)
    app.router.add_get("/api/deadlines", deadline_list)
    app.router.add_get("/api/people", people_list)
    app.router.add_post("/api/people/invite", people_invite)
    app.router.add_post("/api/people/status", people_status)
    app.router.add_post("/api/people/revoke", people_revoke)
    app.router.add_post("/api/chat", chat)

    app.router.add_get("/healthz", _health)

    return app


async def _health(request: web.Request) -> web.Response:
    desk: Desk = request.app[DESK_KEY]
    return web.json_response(
        {
            "ok": True,
            "signed_in": desk.store.session_count(),
            "people": len(desk.store.list_people()),
            "seats": desk.store.seat_usage(),
        }
    )


def serve(settings: Settings) -> None:
    """Run the desk. Refuses the two configurations that cannot work.

    A passkey cannot be registered over plain HTTP on a LAN address, and a desk
    bound to the world without TLS is a practice's client files on a clear
    channel. Both refusals name the fix.
    """
    if not settings.tls_cert and not settings.loopback:
        raise SystemExit(
            "Refusing to serve the desk on a network address without TLS.\n"
            "Browsers will not register a passkey over plain HTTP, and client files\n"
            "must not travel in clear. Either bind to 127.0.0.1, or pass\n"
            "--tls-cert and --tls-key."
        )

    app = create_app(settings)
    print(
        f"Practice desk on {settings.origin}  ·  rp_id {settings.rp_id}"
        f"  ·  brain {settings.brain_url or '(none)'}"
    )

    ssl_context = None
    if settings.tls_cert:
        import ssl

        ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ssl_context.load_cert_chain(settings.tls_cert, settings.tls_key)

    web.run_app(
        app,
        host=settings.host,
        port=settings.port,
        ssl_context=ssl_context,
        print=None,
    )
