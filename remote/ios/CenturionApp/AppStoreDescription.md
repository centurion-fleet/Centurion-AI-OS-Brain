# Sovereign AI Remote — App Store Submission

> **Scope note (5 Nov 2026):** trimmed to the surface that actually ships. The
> app is now **one screen — Signum** — a secure chat with your own Sovereign.
> Previously this listing sold Life Mission / Soul / Autonomy settings, Thinking
> Service, Collaborations, family referrals and Adrian help as if they were on
> the phone. **None of them are reachable from Signum.** Those settings live on
> the Sovereign itself (its own desktop/Mission Deck), and describing them here
> would have failed App Review 2.1 — the reviewer opens the app, cannot find the
> described features, and rejects. If any of that surface is restored to the
> phone, add the matching paragraph back in the same commit.

## App Name
Sovereign AI Remote

*(In App Store Connect → App Information, set the listing name to **Sovereign AI Remote**.)*

## Subtitle
Your Sovereign in Your Pocket

## Price
**Free** — companion app for Centurion customers. A Centurion Sovereign (hardware you own) is required; the app is not useful without a linked Sovereign. No in-app subscription.

## Description

**Free for Centurion customers.** Sovereign AI Remote is the iPhone companion to your Sovereign — a private AI that lives on hardware you own, not in someone else's cloud. Download is free; you need a Centurion Sovereign to use it.

Not a public chatbot. Not a multi-tenant agent marketplace. Your Sovereign belongs to you alone — no shared cloud AI account, no one else's data mixed into your private counsel. This app is how you reach it: one secure conversation, from anywhere.

**ONE SCREEN, ONE CONVERSATION**

Open the app and you are talking to your Sovereign. There is no dashboard to learn, no tab bar to navigate. Ask a question, give an instruction, think out loud — the reply streams back as it is written. While your Sovereign is working you can see what it is doing, and you can stop it mid-turn if it is going somewhere you did not want.

**IT ASKS BEFORE IT ACTS**

When your Sovereign wants to run something that has consequences, it asks you first, on the phone, in plain language — with the choice to allow or deny. Nothing with a side effect happens behind your back.

**YOUR CONVERSATIONS, ON BOTH SIDES**

Open the conversation list to see the topics that exist on your Sovereign, and resume any of them from the phone. Delete one and it is gone from the phone and from the Sovereign — not hidden, not archived somewhere you cannot see.

**CRYPTO CHAT**

Crypto Chat is the end-to-end encrypted link between your iPhone and your Sovereign. Pair once on home Wi-Fi by scanning the QR your Sovereign displays. When you enable **Chat from anywhere** on your Sovereign, the same app continues Crypto Chat away from home over Centurion's outbound relay — no DIY port-forward, no typing a home IP. Message content stays end-to-end encrypted; Centurion's cloud sees connection metadata only.

**STRONG ENCRYPTION**

- X25519 ECDH key exchange (Curve25519 — the same curve family used by WireGuard and Signal)
- XSalsa20-Poly1305 authenticated encryption
- Per-session keys for Crypto Chat between your iPhone and your Sovereign
- Built with Apple frameworks plus the open-source libsodium cryptography library (swift-sodium)

**PRIVACY IS THE PRODUCT**

Centurion AI Agent Limited does not receive your private Crypto Chat, and does not train shared models on it. The app has no analytics SDK, no advertising identifier, and no third-party tracking. It collects nothing you did not type.

**SETTINGS LIVE ON THE SOVEREIGN**

Your Sovereign holds its own settings — how it speaks, what it works on, how much it does without asking. Those are changed on the Sovereign itself, deliberately, on a real screen: a private AI you configure from a phone is a private AI you configure by accident. The phone is the connection to your Sovereign, not the control panel for it.

**OWN IT ONCE**

Buy a Sovereign once and receive free lifetime updates for the Linux brain and this iPhone Remote. No monthly fees for the Sovereign platform.

**A Sovereign is required.** Visit 1human1ai.com to learn more. Support: help.1human1ai.com.

## Keywords
private AI, encrypted chat, sovereign AI, own your AI, local AI, self-hosted, Crypto Chat, privacy

## Support URL
https://help.1human1ai.com

## Marketing URL
https://www.1human1ai.com

## Privacy Policy URL
https://www.1human1ai.com/privacy

## Promotional Text
Free for Centurion customers. Pair on home Wi-Fi for Crypto Chat; enable Chat from anywhere on your Sovereign to keep talking away from home. Nothing works without your own Sovereign.

## App Review Notes (paste into ASC)

Sovereign AI Remote is a **free** companion for **Centurion customers** who already own (or are provisioning) a Centurion Sovereign. Version **5.5.0**, build **75**.

- There is **no cloud login** and **no demo account**. Pairing is **QR-first on home Wi-Fi**: the Sovereign's Brain shows a QR encoding `token:…@lan-host:9119` (paste remains a fallback). **Chat from anywhere** (after enabling on the Brain) uses Centurion's outbound relay — the phone never dials a home IP and does not depend on port-forwarding. **Contact the developer for a time-boxed review pairing window (QR + Brain online); we will have a Sovereign running for the review team.**
- Camera permission is used **only** to scan that pairing QR (`NSCameraUsageDescription`).
- **The entire user-facing surface is one screen:** a chat with the linked Sovereign, a conversation list (open, resume, delete), and tool-approval cards. There is no settings tab and no account screen **in the app** — deliberately. Per-account configuration lives on the Sovereign. If a reviewer looks for settings inside the app, that is the explanation, and it is intentional, not missing.
- Without a linked Sovereign there is no chat. The unlinked state shows an explicit **Not linked to a Brain** state with a Pair action — it never presents a fake or demo conversation.
- While a linked Sovereign is thinking, the send control becomes **Stop**; a failed turn can be retried without duplicating the question. Nothing here calls a third-party AI service from the phone.
- Price: Free. No in-app purchases. No account creation, no subscriptions, no ads.
- Data: conversation content is carried end-to-end encrypted between the owner's iPhone and the owner's own Sovereign. No analytics or advertising SDK is linked.
- Encryption: Crypto Chat uses publicly available algorithms (X25519 + XSalsa20-Poly1305 via libsodium) between the owner's iPhone and their own Sovereign. `ITSAppUsesNonExemptEncryption = false` (exemption).

## App Privacy notes (App Store Connect)

Disclose accurately — the app collects nothing beyond what is needed to connect:

- **Crypto Chat:** processed on-device and on the owner's Sovereign; content is not sent to Centurion's cloud for storage or training. Away mode may use Centurion's relay for presence/routing metadata only.
- **Pairing data:** the Sovereign token and host address are stored locally on the iPhone (Keychain/App storage) to reconnect. Not transmitted to Centurion.
- **Diagnostics:** none collected by the app. No analytics SDK, no IDFA, no crash-reporting SDK.
- **What is NOT reachable in this build:** the referral / Family Beneficiary surface and the optional support chat. Their view code still exists but no route in Signum leads to them, so no such data is collected in this version. (Earlier drafts of this file described both as live features; that was wrong and is why the listing was rewritten.)

## Still to verify before upload

- [ ] `NSCameraUsageDescription` string still matches the QR-only use (onboarding scan).
- [ ] `NSContactsUsageDescription` (line 77 of `project.yml`) is still declared for the referral flow, which is now unreachable. Either strip it in this release or accept a declared-but-unused permission — a reviewer who sees a contacts prompt they cannot trigger is a question you do not want to answer in a rejection. My recommendation: strip it, then re-upload.
- [ ] App Privacy answers in ASC match the "nothing collected" set above — remove any earlier answers for Contact Info / Referrals.
- [ ] Screenshots regenerated from Signum (cream-and-ink chat, conversation list, pairing) — old five-tab screenshots must not ship.
- [ ] China/encryption compliance answer unchanged (`ITSAppUsesNonExemptEncryption = false`).
