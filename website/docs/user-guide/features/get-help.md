---
title: Get Help
sidebar_position: 41
---

# Get Help

CenturionAI Remote includes a single **Get Help** flow on iPhone and matching **Support Tools** on the GTK desktop. Together they give support staff structured diagnostics without exposing secrets on the LAN wire.

## On iPhone

1. Open **You** → **Get Help** (or **Connect** → **Get Help**).
2. Tap **Send to Support** to create a short support code (for example `ABC-123`).
3. Share the code with your advisor.
4. Tap **Try to Fix Automatically** to restore the last working thinking-service setup safely.

The iPhone never shows raw logs, API keys, or terminal output.

## On your Centurion computer (GTK)

Open **Settings** → **Support Tools**:

- **Run Health Check** — plain-language summary of thinking service and configuration
- **Generate Support Bundle** — creates the same support code format
- **Look Up Support Code** — opens the saved structured bundle for support staff

### Transition (early Centurions only)

If you started with the Telegram bot before Crypto Chat, open **Settings** → **Transition** → **Bring over Telegram history**. This is a one-time host-side step for the first customers — it is not part of CenturionAI Remote on iPhone.

CLI equivalent: `centurion telegram import` (add `--dry-run` to preview).

## Support code lifetime

Support codes expire after 24 hours and are stored under `state/support_bundles/` in your Centurion home directory.

## Related

See [Provider recovery](provider-recovery.md) for thinking-service health and last-known-good restore behavior.
