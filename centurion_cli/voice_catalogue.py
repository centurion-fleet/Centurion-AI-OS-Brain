"""The voice catalogue — one standard male and one standard female per language.

Deliberately this and nothing more:

* **One male and one female voice per language.** Both free, always. A Centurion
  sold into Italy that cannot speak Italian is broken, not upsold, and a man and
  a woman are the two registers a person actually wants to be spoken to in.
* **Nothing is gated.** There is no premium tier and no licence is consulted, so
  there is no gate to leak and none to break. (The former ``voice_pack_tiers`` /
  Piper premium machinery is retired.)

The voices are Edge neural voices — free at any volume, verified against Edge's
live voice list. Gender is the provider's own ``Gender`` field, not a reading of
the name.

A slot with no ``voice_id`` means the entry exists in the catalogue but cannot
actually be spoken, and it will NOT be served: a voice that fails in front of a
buyer is worse than a missing feature.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

GENDERS = ("female", "male")


def _tts_config() -> Dict[str, Any]:
    try:
        from centurion_cli.config import load_config

        return (load_config() or {}).get("tts") or {}
    except Exception:
        return {}


def _plan(tts: Dict[str, Any]) -> Dict[str, Any]:
    plan = tts.get("voice_plan")
    return plan if isinstance(plan, dict) else {}


def _voices(lang: Dict[str, Any]) -> Dict[str, Any]:
    voices = lang.get("voices")
    return voices if isinstance(voices, dict) else {}


def catalogue(*, tts: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
    """Every voice this installation offers, each marked ``configured``."""
    tts = _tts_config() if tts is None else tts
    if not isinstance(tts, dict):  # a malformed config must not crash a voice pick
        tts = {}
    provider = tts.get("provider") or "edge"

    rows: List[Dict[str, Any]] = []
    for lang in _plan(tts).get("languages") or []:
        if not isinstance(lang, dict):
            continue
        code = str(lang.get("code") or "").strip()
        if not code:
            continue
        label = str(lang.get("label") or code)
        voices = _voices(lang)
        for gender in GENDERS:
            vid = str(voices.get(gender) or "").strip()
            rows.append(
                {
                    "id": f"{code}-{'f' if gender == 'female' else 'm'}",
                    "provider": provider,
                    "voice_id": vid,
                    "display": f"{label} — {gender}",
                    "language": code,
                    "gender": gender,
                    "configured": bool(vid),
                }
            )
    return rows


def resolve(
    voice_id: Optional[str] = None,
    *,
    language: Optional[str] = None,
    gender: Optional[str] = None,
    tts: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """The effective voice.

    Order: the requested voice when it exists and is configured → otherwise the
    configured voice for ``language`` and ``gender`` → otherwise the first
    configured voice. Why a request was refused is named (``unconfigured`` /
    ``unknown``) so the caller can say so plainly rather than substituting
    silently.
    """
    rows = catalogue(tts=tts)

    def pick(lang: Optional[str], want_gender: Optional[str]) -> Optional[Dict[str, Any]]:
        usable = [r for r in rows if r.get("configured")]
        if lang:
            want = str(lang).strip().lower()
            stem = want.split("-")[0]
            same = [r for r in usable if str(r.get("language", "")).lower() == want]
            if not same:
                # A German buyer's region (de-AT) still lands on German.
                same = [
                    r
                    for r in usable
                    if str(r.get("language", "")).lower().split("-")[0] == stem
                ]
            if same:
                usable = same
        if want_gender:
            by_gender = next((r for r in usable if r.get("gender") == want_gender), None)
            if by_gender:
                return by_gender
        return usable[0] if usable else None

    base = pick(language, gender)
    if base is None:
        return {
            "id": None,
            "provider": None,
            "voice_id": "",
            "display": "",
            "language": "",
            "gender": "",
            "configured": False,
        }
    base = dict(base)

    if voice_id:
        want = next((r for r in rows if r.get("id") == voice_id), None)
        if want is None:
            return dict(base, unknown=voice_id)
        # A refusal must land in the SAME language as the voice refused — a German
        # buyer asking for a German voice must not be answered in English.
        same = pick(want.get("language") or language, want.get("gender") or gender)
        if not want.get("configured"):
            return dict(same or base, unconfigured=voice_id)
        return want

    return base


def languages(*, tts: Optional[Dict[str, Any]] = None) -> List[str]:
    """The codes this installation offers — the markets it can actually speak to."""
    return sorted({r["language"] for r in catalogue(tts=tts) if r.get("language")})
