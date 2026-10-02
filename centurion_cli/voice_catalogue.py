"""The voice catalogue — a free house voice per language, premium male/female above it.

The hybrid voice model, in one place:

* **One free house voice per language.** Every licence has it, it cannot be locked
  out, and it is what a Centurion speaks in for that market. Intelligibility is
  the floor, not a product: a Centurion sold into Italy that cannot speak Italian
  is broken, so no language is ever gated behind a subscription.
* **Premium male and female per language.** High-quality character voices above
  the free one, unlocked by a voice-pack subscription.

The premium set is gated on the **licence tier** already carried by the
entitlement mirror (``centurion.license.store.load_entitlement().tier``) — the same
authority that governs every other paid capability.

Two independent conditions must both hold before a premium voice can be used:

1. **The licence carries the pack** — a tier named in ``tts.voice_pack_tiers``.
   That list ships EMPTY, so a stock install cannot leak a paid voice.
2. **The voice is actually configured** — a real ``voice_id`` from the provider's
   live voice library. An empty id means the slot exists in the catalogue but is
   not yet fillable, and it will NOT be served.

The second condition is the important one in practice: it is what stops an
invented or placeholder provider id reaching a customer's ears. A voice id that
was never verified is worse than a missing feature — it fails in front of a
buyer, in their own language.

Any locked, unknown, unconfigured or malformed request degrades to the free house
voice, and says what it refused rather than substituting silently.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

FREE_TIER = "free"
PREMIUM_TIER = "voicepack"
GENDERS = ("female", "male")


def _tts_config() -> Dict[str, Any]:
    try:
        from centurion_cli.config import load_config

        return (load_config() or {}).get("tts") or {}
    except Exception:
        return {}


def _licence_tier() -> str:
    try:
        from centurion.license.store import load_entitlement

        return str(load_entitlement().tier or "").strip().lower()
    except Exception:
        return ""


def _pack_tiers(tts: Optional[Dict[str, Any]]) -> set:
    tts = _tts_config() if tts is None else tts
    if not isinstance(tts, dict):  # a malformed config must not crash a voice pick
        return set()
    return {str(t).strip().lower() for t in (tts.get("voice_pack_tiers") or [])}


def _plan(tts: Dict[str, Any]) -> Dict[str, Any]:
    plan = tts.get("voice_plan")
    return plan if isinstance(plan, dict) else {}


def _pack_carried(tier: Optional[str], pack_tiers: set) -> bool:
    if tier is None:
        tier = _licence_tier()
    return str(tier).strip().lower() in pack_tiers


def _fallback_base(tts: Dict[str, Any]) -> List[Dict[str, Any]]:
    """A stock install with no plan still has one usable voice."""
    return [
        {
            "id": "base",
            "provider": tts.get("provider") or "edge",
            "voice_id": "",
            "display": "Base voice",
            "language": "",
            "gender": "",
            "tier": FREE_TIER,
            "unlocked": True,
            "configured": False,
        }
    ]


def catalogue(
    *, tier: Optional[str] = None, tts: Optional[Dict[str, Any]] = None
) -> List[Dict[str, Any]]:
    """Every voice this licence can see, each marked ``unlocked`` and ``configured``."""
    tts = _tts_config() if tts is None else tts
    if not isinstance(tts, dict):  # a malformed config must not crash the catalogue
        tts = {}
    tiers = _pack_tiers(tts)
    carried = _pack_carried(tier, tiers)
    provider = tts.get("provider") or "edge"

    rows: List[Dict[str, Any]] = []
    for lang in _plan(tts).get("languages") or []:
        if not isinstance(lang, dict):
            continue
        code = str(lang.get("code") or "").strip()
        if not code:
            continue
        label = str(lang.get("label") or code)

        house = str(lang.get("house_voice") or "").strip()
        rows.append(
            {
                "id": f"{code}-house",
                "provider": provider,
                "voice_id": house,
                "display": f"{label} — house voice",
                "language": code,
                "gender": str(lang.get("house_gender") or ""),
                "tier": FREE_TIER,
                # The free house voice is never lockable — only ever unconfigured.
                "unlocked": True,
                "configured": bool(house),
            }
        )

        premium_ids = lang.get("premium_voice_ids")
        premium_ids = premium_ids if isinstance(premium_ids, dict) else {}
        premium_provider = str(lang.get("premium_provider") or "elevenlabs")
        quality = lang.get("premium_quality")
        quality = quality if isinstance(quality, dict) else {}
        for gender in GENDERS:
            vid = str(premium_ids.get(gender) or "").strip()
            configured = bool(vid)
            rows.append(
                {
                    "id": f"{code}-premium-{'f' if gender == 'female' else 'm'}",
                    "provider": premium_provider,
                    "voice_id": vid,
                    "display": f"{label} — premium ({gender})",
                    "language": code,
                    "gender": gender,
                    # Provider-declared audio quality where the source states one.
                    "quality": str(quality.get(gender) or ""),
                    # ⚠️ No voice provider catalog we ingest carries a gender field.
                    # The gender above is a reading of the voice NAME. Recorded so
                    # nothing downstream mistakes it for a verified fact.
                    "gender_verified": False,
                    "tier": PREMIUM_TIER,
                    # BOTH conditions: the licence carries the pack AND the slot is filled.
                    "unlocked": configured and carried,
                    "configured": configured,
                }
            )

    return rows or _fallback_base(tts)


def resolve(
    voice_id: Optional[str] = None,
    *,
    language: Optional[str] = None,
    tier: Optional[str] = None,
    tts: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """The effective voice.

    Order: the requested voice when it exists, is configured and is unlocked →
    otherwise the free house voice for ``language`` → otherwise the first free
    voice. Why a request was refused is named (``locked_out`` / ``unconfigured`` /
    ``unknown``) so the caller can say so plainly instead of substituting silently.
    """
    rows = catalogue(tier=tier, tts=tts)

    def house(lang: Optional[str]) -> Dict[str, Any]:
        free = [r for r in rows if r.get("tier") == FREE_TIER and r.get("configured")]
        if lang:
            want = str(lang).strip().lower()
            exact = next((r for r in free if str(r.get("language", "")).lower() == want), None)
            if exact:
                return exact
            stem = want.split("-")[0]
            near = next(
                (r for r in free if str(r.get("language", "")).lower().split("-")[0] == stem), None
            )
            if near:
                return near
        return free[0] if free else next((r for r in rows if r.get("tier") == FREE_TIER), rows[0])

    base = dict(house(language))

    if voice_id:
        want = next((r for r in rows if r.get("id") == voice_id), None)
        if want is None:
            return dict(base, unknown=voice_id)
        # A refusal must land in the SAME language as the voice refused — a German
        # buyer asking for a German voice must not be answered in English.
        same_lang = house(want.get("language") or language)
        if not want.get("configured"):
            return dict(same_lang, unconfigured=voice_id)
        if not want.get("unlocked"):
            return dict(same_lang, locked_out=voice_id)
        return want

    return dict(base)


def languages(*, tts: Optional[Dict[str, Any]] = None) -> List[str]:
    """The codes this installation offers — the markets it can actually speak to."""
    return [r["language"] for r in catalogue(tts=tts) if r.get("tier") == FREE_TIER and r.get("language")]
