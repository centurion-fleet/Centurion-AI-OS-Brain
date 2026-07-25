# Sovereign AI Remote — TestFlight What to Test (build 28)

**Version:** 5.1.0 (28)  
**Focus:** QR-first away pairing, gateway/sessions/approvals, App Store candidate

## Important
Delete the previous TestFlight install once before testing — iOS caches launch screens aggressively. After delete + install of **28**, cold-launch should show cream/ink + **SOVEREIGN AI REMOTE** / **1 Human 1 AI** (no app icon, no blank green). Allow camera when prompted (QR scan only).

## Must try
1. Delete app → install 28 → force-quit → cold launch.
2. Confirm wordmark splash, then straight into Chat/onboarding.
3. **Before link:** demo chats may appear. **After link:** Chat must be empty (or host-backed only) — no “Morning Briefing” samples.
4. Create a live Crypto Chat titled “Morning Briefing”, kill app, reconnect — thread must still be there.
5. Pairing (cellular): Brain shows QR → Connect → **Scan QR** → auto-link. Paste fallback still works.
6. You tab while disconnected: Link is the hero; no `!` badge if never linked.
7. Thinking Service: dial (or list with Reduce Motion / VoiceOver); change family + access code.
8. Smoke: Crypto Chat send/receive while linked; gateway control; tool approval card when autonomy < Max.
