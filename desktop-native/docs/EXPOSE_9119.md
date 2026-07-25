# Expose TCP 9119 for away-from-home pairing

Sovereign AI Remote links over encrypted TCP **port 9119**. The QR / connection
string embeds a hostname the iPhone can reach from **cellular** (not only home
Wi‑Fi). Choose one path below, then mint a pairing QR that uses that host.

## Persist advertise host

```bash
mkdir -p ~/.centurion/remote
echo 'brain.yourdomain.com' > ~/.centurion/remote/advertise-host

# Or export once and re-run install (writes the same file + systemd Environment=):
export CENTURION_REMOTE_ADVERTISE_HOST=brain.yourdomain.com
desktop-native/scripts/install-user.sh
```

GTK **Link iPhone** and `centurion remote pair` (when `--host` omitted) read
`CENTURION_REMOTE_ADVERTISE_HOST`, then that file, then LAN IP.


## 2. Confirm the listener

```bash
systemctl --user status centurion-remote
# Should be active; listening on 0.0.0.0:9119 (or configured bind).
```

## 3. Tunnel / public path (pick one)

### Cloudflare Tunnel (recommended)

1. Install `cloudflared` and authenticate.
2. Create a TCP tunnel to the Brain:

```bash
cloudflared tunnel create centurion-remote
# Route hostname → localhost:9119 (TCP). Exact config depends on your CF setup.
cloudflared tunnel run --url tcp://127.0.0.1:9119 <tunnel-name>
```

3. Point DNS (`brain.yourdomain.com`) at the tunnel.
4. Verify from another network:

```bash
nc -vz brain.yourdomain.com 9119
```

### Reverse proxy (nginx stream / Caddy)

TCP pass-through to `127.0.0.1:9119`. Use your public DNS name as
`CENTURION_REMOTE_ADVERTISE_HOST`.

### Port-forward / firewall

Allow inbound TCP 9119 to the Brain. Use public IP or DynDNS as `--host`.

## 4. Mint QR and pair

```bash
centurion remote pair --host "$CENTURION_REMOTE_ADVERTISE_HOST"
# TTY: ASCII QR + connection string
# Or: Sovereign AI Brain → Link iPhone — show QR
```

On the iPhone (cellular): Connect → **Scan QR code**.

## Checklist

- [ ] `centurion-remote` active
- [ ] `CENTURION_REMOTE_ADVERTISE_HOST` is a public/tunnel hostname (not `127.0.0.1`)
- [ ] `nc -vz <host> 9119` succeeds from outside the Brain LAN
- [ ] QR scan on cellular completes pairing
