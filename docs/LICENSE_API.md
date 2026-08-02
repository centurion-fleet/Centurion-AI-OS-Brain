# Centurion License API Contract

Product licensing for Centurion OS (subscription / rent-to-own / outright).
Implemented on **personalcenturion.com** (Scutum). The OS client lives in
`centurion/license/` and talks to these endpoints.

Base URL: `{billing.fleet_api_url}` → default `https://personalcenturion.com/api/v1`

All request/response bodies are JSON. Timestamps are Unix epoch seconds (UTC)
unless noted.

---

## Economics (reference)

| Tier | Price | Phone-home | Unlock |
|------|-------|------------|--------|
| Subscription | £50 / month | Every 30 days | While active |
| Rent-to-own | £250 / month | Every 30 days until paid off | Cumulative £5,000 → permanent |
| Outright | £4,250 once | None | Day one, hardware-bound |

---

## `POST /license/checkin`

Periodic phone-home from subscription and rent-to-own installs.

### Request

```json
{
  "license_id": "lic_…",
  "install_id": "uuid",
  "machine_fingerprint": "sha256hex",
  "tier": "subscription|rent_to_own|trial",
  "os_version": "Darwin 25.5.0",
  "centurion_version": "5.x.y",
  "last_state": "subscription_active",
  "nonce": "hex16"
}
```

### Response `200`

```json
{
  "ok": true,
  "state": "subscription_active",
  "tier": "subscription",
  "balance_paid_gbp": 750.0,
  "balance_target_gbp": 5000.0,
  "next_check_by": 1780000000,
  "grace_until": null,
  "signed_attestation": "base64url(payload).base64url(sig)",
  "revoke_reason": null
}
```

### Revocation

Return `state: "locked"` and a non-null `revoke_reason`. The OS transitions
immediately to `locked` with **no grace**.

### Network failure (client behaviour)

OS does **not** lock on transport errors. Grace is computed from
`last_verified_at + check_interval_days` (default 30). Retry backoff:
1h → 6h → 24h → weekly.

---

## `POST /license/activate`

Start trial or bind a paid subscription / rent-to-own checkout.

### Request

```json
{
  "tier": "trial|subscription|rent_to_own",
  "machine_fingerprint": "sha256hex",
  "install_id": "uuid",
  "activation_code": "optional checkout code",
  "api_key": "optional",
  "trial_days": 14,
  "license_id": "optional client-proposed trial id"
}
```

### Response `200`

```json
{
  "ok": true,
  "license_id": "lic_…",
  "state": "subscription_active",
  "tier": "subscription",
  "balance_paid_gbp": 0,
  "balance_target_gbp": 5000,
  "next_check_by": 1780000000,
  "signed_attestation": "…",
  "customer_name": "Ada Lovelace",
  "trial_expires_at": null
}
```

---

## `POST /license/redeem`

Redeem an outright proof-of-purchase token and bind it to a machine fingerprint.

### Request

```json
{
  "token": "pop_…",
  "machine_fingerprint": "sha256hex",
  "install_id": "uuid"
}
```

### Response `200`

```json
{
  "ok": true,
  "license_id": "lic_…",
  "token_id": "pop_…",
  "state": "outright_owned",
  "tier": "outright",
  "signed_attestation": "…",
  "customer_name": "…"
}
```

Tokens are **one-time**. A second redeem for the same token with a different
fingerprint must fail unless a reissue was approved.

---

## `POST /license/reissue`

Hardware failure / replacement flow. Rate-limited and audited server-side.

### Request

```json
{
  "license_id": "lic_…",
  "token_id": "pop_…",
  "old_fingerprint": "sha256hex",
  "new_fingerprint": "sha256hex",
  "reason": "hardware_failure",
  "proof_of_purchase": "order_…"
}
```

### Response `200` (pending support)

```json
{
  "ok": true,
  "status": "pending_review",
  "message": "Reissue request submitted"
}
```

### Response `200` (auto / approved)

```json
{
  "ok": true,
  "status": "issued",
  "signed_attestation": "…",
  "message": "Reissue applied"
}
```

---

## Signed attestations

Format: `base64url(canonical_json_payload) + "." + base64url(ed25519_signature)`

Canonical JSON: UTF-8, `sort_keys=True`, separators `(",", ":")`.

### Payload fields

```json
{
  "kind": "paid_off|outright|subscription|rto_active",
  "license_id": "lic_…",
  "machine_fingerprint": "sha256hex",
  "state": "rent_to_own_paid_off",
  "tier": "rent_to_own",
  "balance_paid_gbp": 5000,
  "balance_target_gbp": 5000,
  "issued_at": 1770000000,
  "expires_at": null,
  "token_id": "optional"
}
```

The OS embeds / configures the ed25519 CA public key via
`license.ca_public_key_b64`. Local encrypted entitlement mirrors can be
tampered with; **ownership unlocks require a valid attestation**.

---

## Stripe webhooks (website-only)

| Event | Effect |
|-------|--------|
| `invoice.paid` (subscription) | Mark license active; extend `next_check_by` |
| `invoice.paid` (RTO) | Add £250 (or invoice amount) to `balance_paid_gbp` |
| RTO balance ≥ 5000 | Issue `paid_off` attestation; stop requiring phone-home |
| `customer.subscription.deleted` / unpaid | Next check-in returns expired / locked path |

---

## Fleet check-in extensions

`POST /fleet/checkin` may include (OS already sends when present):

```json
{
  "license_id": "lic_…",
  "tier": "outright",
  "fingerprint": "sha256hex",
  "shipment_id": "ship_…",
  "license_state": "outright_owned"
}
```

Used by DIF Y inventory to mark shipped machines as customer-online.

---

## Grace timeline (OS defaults)

| Window after due | Mode |
|------------------|------|
| 0–7 days | `warn` — full function + banner |
| 8–14 days | `restricted` — no new agent tool turns |
| ≥15 days | `locked` — activation / billing commands only |

Config knobs: `license.grace_warn_days`, `grace_restrict_days`, `grace_lock_days`.

---

## OS client entry points

| Surface | Path |
|---------|------|
| Package | `centurion/license/` |
| CLI | `centurion license status\|activate\|redeem\|…` |
| Slash | `/license` |
| Remote bridge | `license_status`, `license_activate`, `license_redeem` |
| Config | `license.*` in `config.yaml` |
