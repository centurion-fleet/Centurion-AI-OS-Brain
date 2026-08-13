# Expose TCP 9119 (legacy / power-user)

> **Product path:** Unbox & Go is **LAN-only** (Bonjour + QR on the same Wi‑Fi).
> Away-from-home for customers is a **Centurion-hosted relay** (Phase 2) — not
> DIY Cloudflare or port-forward. This document remains for lab / power users
> who still want a public `:9119` endpoint.

Sovereign AI Remote links over encrypted TCP **port 9119**. A public hostname
in the QR only matters if you are **not** using same-LAN Unbox pairing.

## Persist advertise host (power-user)

```bash
mkdir -p ~/.centurion/remote
echo 'brain.yourdomain.com' > ~/.centurion/remote/advertise-host

# Or export once and re-run install (writes the same file + systemd Environment=):
export CENTURION_REMOTE_ADVERTISE_HOST=brain.yourdomain.com
brain/linux/scripts/install-user.sh
```

`centurion remote pair` (when `--host` omitted) still reads
`CENTURION_REMOTE_ADVERTISE_HOST`, then that file, then LAN IP.

**Unbox note:** Sovereign AI Brain’s full-screen pairing QR always embeds the
**LAN IPv4** (never the tunnel advertise-host), so first-link Unbox works on
Wi‑Fi without router changes.

## Confirm the listener

```bash
systemctl --user status centurion-remote
# Should be active; listening on 0.0.0.0:9119 (or configured bind).
```

## Tunnel / public path (lab only)

### Port-forward / firewall

Allow inbound TCP 9119 to the Brain. Use public IP or DynDNS as `--host`.

### Reverse proxy (nginx stream / Caddy)

TCP pass-through to `127.0.0.1:9119`. Use your public DNS name as
`CENTURION_REMOTE_ADVERTISE_HOST`.

Cloudflare HTTP tunnels are **not** a substitute for raw Centurion TCP.

## Mint QR (power-user)

```bash
centurion remote pair --host "$CENTURION_REMOTE_ADVERTISE_HOST"
```

## Checklist (lab)

- [ ] `centurion-remote` active
- [ ] `nc -vz <host> 9119` succeeds from outside the Brain LAN
- [ ] Prefer Unbox LAN smoke first — see `ios/CenturionApp/DEVICE_SMOKE.md`
