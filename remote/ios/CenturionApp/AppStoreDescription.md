# Sovereign AI Remote — App Store Submission

## App Name
Sovereign AI Remote

*(In App Store Connect → App Information, set the listing name to **Sovereign AI Remote**.)*

## Subtitle
Your Sovereign in Your Pocket

## Price
**Free** — companion app for Centurion customers. A Centurion Sovereign (hardware you own) is required; the app is not useful without a linked Sovereign on your network. No in-app subscription for the Remote itself.

## Description

**Free for Centurion customers.** Sovereign AI Remote is the iPhone companion to your Sovereign — a private AI that lives on your desk, knows your Life Mission, and helps you live it. Download is free; you need a Centurion Sovereign to use it.

Not a public chatbot. Not a multi-tenant agent marketplace. Your Sovereign belongs to you alone — no shared cloud AI account, no one else’s data mixed into your private counsel. It runs on hardware you own, on your network. This app is how you talk to it through **Crypto Chat** — a private encrypted conversation channel that public AIs simply do not have.

**CRYPTO CHAT**

Crypto Chat is the end-to-end encrypted link between your iPhone and your Sovereign on your network. Your words stay between you and your Sovereign — not routed through a public AI product.

**LIFE MISSION, SOUL & AUTONOMY**

Set your Life Mission, shape how your Sovereign speaks (Soul), and choose Autonomy Level on the phone. When linked, those settings sync to your Sovereign and shape how it thinks and acts on the next conversation.

**THINKING SERVICE**

Choose which thinking service your Sovereign uses (BYOK families). Access codes stay on your Sovereign — never on this iPhone.

**COLLABORATIONS**

While you are away from the desk, your Sovereigns can work toward your Life Mission. Open Remote to orient, decide when something needs your choice, and receive finished work marked Ready for you — over the same private channel.

**ADRIAN (OPTIONAL HELP)**

Adrian is an optional online help guide for setup and support. Adrian works via the Centurion Help Center and does **not** see your Crypto Chat history. Crypto Chat and Adrian help are separate connections.

**STRONG ENCRYPTION**

- X25519 ECDH key exchange (Curve25519 — same curve family used by WireGuard and Signal)
- XSalsa20-Poly1305 authenticated encryption
- Per-session keys for Crypto Chat between your iPhone and your Sovereign
- Built with Apple frameworks plus the open-source libsodium cryptography library (swift-sodium)

**PRIVACY IS THE PRODUCT**

Centurion Limited does not receive your private Crypto Chat to train shared models. Adrian help is separate and never reads that private stream.

**OWN IT ONCE**

Buy a Sovereign once and receive free lifetime updates for the Linux brain and this iPhone Remote. No monthly fees for the Sovereign platform.

**A Sovereign is required.** Visit 1human1ai.com to learn more. Support: help.1human1ai.com.

## Keywords
Crypto Chat, privacy, personal AI, Sovereign AI Remote, life mission, local

## Support URL
https://help.1human1ai.com

## Marketing URL
https://www.1human1ai.com

## Privacy Policy URL
https://www.1human1ai.com/privacy

## Promotional Text
Free for Centurion customers. Link your Sovereign for private Crypto Chat, Life Mission, and collaborations — nothing works without your own Sovereign on your network.

## App Review Notes (paste into ASC)

Sovereign AI Remote is a **free** companion for **Centurion customers** who already own (or are provisioning) a Centurion Sovereign.

- There is **no cloud login** and **no demo account**. Pairing is **QR-first on home Wi‑Fi**: Sovereign AI Brain shows a QR encoding `token:…@lan-host:9119` (paste remains a fallback). **Chat from anywhere** (after enable on the Brain) uses Centurion’s outbound relay — the phone never dials a home IP or depends on port-forwarding. The owner must approve the iPhone on the brain if prompted.
- Camera permission is used **only** to scan that pairing QR (`NSCameraUsageDescription`).
- Without a linked Sovereign, core features (Crypto Chat, Thinking Service, Mission sync) are unavailable by design. Offline demo chats clear as soon as a live link succeeds.
- LAN / Bonjour discovery is optional convenience only — do not require same Wi‑Fi for review once Chat from anywhere is enabled for the review Brain.
- **App Review:** Please contact the developer for a time-boxed review pairing window (QR / pairing code + Brain with Chat from anywhere enabled).- Price: Free. No IAP for core Remote features.
- Encryption: standard TLS for optional Help (Adrian); Crypto Chat uses publicly available algorithms (X25519 + XSalsa20-Poly1305 via libsodium) between the owner’s iPhone and their own Sovereign. `ITSAppUsesNonExemptEncryption = false` (exemption).

## App Privacy notes (App Store Connect)

Disclose accurately:

- **Crypto Chat:** processed on-device / on the owner’s Sovereign; not sent to Centurion cloud for storage or training.
- **Adrian (optional):** when used, may send install id, app version, connection/thinking health labels, and a short mission summary (capped) to help.1human1ai.com for support answers only — not Crypto Chat transcripts.
