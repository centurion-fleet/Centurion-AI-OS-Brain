# Centurion License API Contract

Product licensing for Centurion OS. **A Centurion licence is a monthly
subscription — the only licence level there is.** The fee governs the service,
never the being: non-payment suspends service and never removes a Centurion, so
there is no rent-to-own path, no pay-off, and no terminal "owned" state. What a
customer pays up front is the implementation fee, which is a separate commercial
matter from the licence itself.

Implemented on **personalcenturion.com** (Scutum). The OS client lives in
`centurion/license/` and talks to these endpoints.

Base URL: `{billing.fleet_api_url}` → default `https://personalcenturion.com/api/v1`

All request/response bodies are JSON. Timestamps are Unix epoch seconds (UTC)
unless noted.

> **Wire retirement (29 Sep 2026).** The `owned` / `rent_to_own` vocabulary was
> retired by decision — every Centurion pays a monthly subscription, so there is
> no permanent state and no machine is ever marked as owned. The old wire fields
> (`balance_paid_eur`, `balance_target_eur`, `balance_remaining`, `total_paid`,
> `owned`) are still **accepted and echoed** for backward compatibility with
> Brains already in the field, but are now **always neutral** (`0` / `false`).
> See *Superseded history* at the end of this document — kept, not erased.

---

## Economics (reference)

| Tier | Price | Phone-home | Unlock |
|------|-------|------------|--------|
| Subscription | £50 / month | Every 30 days | While `current_period_end` is in the future |

A licence is a **monthly subscription only**. Entitlement follows
`current_period_end` (the end of the paid or credited period) — never a balance.
There is no cumulative pay-off and no permanently-owned tier.

The historical Rent-to-own and Outright tiers are recorded under
[Superseded history](#superseded-history) and must not be quoted as live.

---

## `state` values

These five are the whole vocabulary the OS reads:

| `state` | Meaning |
|---------|---------|
| `subscription_active` | Inside the paid / credited period (`now ≤ current_period_end`) |
| `grace` | Past `current_period_end`, within one check interval (default 30 days) |
| `expired` | Past grace, not yet locked |
| `pending` | Not yet activated |
| `locked` | Revoked, or a replaced device (no grace) |

`owned`, `outright_owned`, `rent_to_own_active` and `rent_to_own_paid_off` are
**retired** — nothing can produce them any more. Internally the OS maps
`expired` → `subscription_expired` and `pending` → `unactivated` (see
`centurion/license/states.py`).

---

## `POST /license/checkin`

Periodic phone-home from subscription installs.

### Request

```json
{
  "license_id": "lic_…",
  "install_id": "uuid",
  "machine_fingerprint": "sha256hex",
  "tier": "subscription|trial",
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
  "expires_at": "2027-01-01T00:00:00Z",
  "next_check_by": 1780000000,
  "grace_until": null,
  "revoke_reason": null,
  "balance_paid_eur": 0,
  "balance_target_eur": 0,
  "balance_remaining": 0,
  "total_paid": 0,
  "owned": false
}
```

> **Deprecated — kept for wire compatibility, not live behaviour.**
> `balance_paid_eur`, `balance_target_eur`, `balance_remaining`, `total_paid`
> and `owned` are still emitted so an older Brain in the field keeps parsing the
> response, but they are **always neutral** (`0` / `false`) and carry no
> entitlement meaning. Clients must not branch on them — entitlement is `state`
> plus `expires_at`. (The OS mirror of the two balance keys is
> `balance_paid_gbp` / `balance_target_gbp`; same rule, always `0`.)

### Revocation

Return `state: "locked"` and a non-null `revoke_reason`. The OS transitions
immediately to `locked` with **no grace**.

### Network failure (client behaviour)

OS does **not** lock on transport errors. Grace is computed from
`last_verified_at + check_interval_days` (default 30). Retry backoff:
1h → 6h → 24h → weekly.

---

## `POST /license/activate`

Start a trial or bind a paid monthly-subscription checkout.

### Request

```json
{
  "tier": "trial|subscription",
  "machine_fingerprint": "sha256hex",
  "install_id": "uuid",
  "activation_code": "optional checkout code",
  "api_key": "optional",
  "trial_days": 14,
  "license_id": "optional client-proposed trial id"
}
```

> `rent_to_own` and `owned` / `outright` are no longer valid tiers. The OS client
> still tolerates the stale strings for robustness, but no server path issues
> them.

### Response `200`

```json
{
  "ok": true,
  "license_id": "lic_…",
  "state": "subscription_active",
  "tier": "subscription",
  "expires_at": "2027-01-01T00:00:00Z",
  "next_check_by": 1780000000,
  "customer_name": "Ada Lovelace",
  "trial_expires_at": null
}
```

---

## Signed attestations — REMOVED 29 Sep 2026

There are none. The server no longer signs an attestation and the Brain no longer
stores one. Nothing ever verified it, so it protected nothing.

Why it went: the signature was HMAC-SHA256 — symmetric, so any party able to verify
could also forge — and the OS side had no verifier at all (`tokens.py`'s
`verify_attestation` had zero callers). Removing it beats carrying a control that
only looks like one. If attestation is wanted later it should be designed fresh,
verified client-side, over an asymmetric key.

Consequently `LICENSE_ATTESTATION_SECRET` is no longer read by the application, and
the `signed_attestation` key is gone from every response payload.

---

## Stripe webhooks (website-only)

| Event | Effect |
|-------|--------|
| `invoice.paid` (subscription) | Mark licence active; extend `current_period_end` by one month; extend `next_check_by` |
| `invoice.payment_failed` | Mark the billing record `past_due`. Does **not** revoke the licence — the 30-day check-in with 30-day grace governs access |
| `customer.subscription.deleted` / unpaid | Next check-in returns the expired / locked path |

There is no separate rent-to-own branch: a paid licence invoice is always a
subscription period extension. (This used to fork on a `metadata.license_level`
hint to decide between a subscription extension and a rent-to-own credit — see
*Superseded history*.)

---

## Fleet check-in extensions

`POST /fleet/checkin` may include (OS already sends when present):

```json
{
  "license_id": "lic_…",
  "tier": "subscription",
  "fingerprint": "sha256hex",
  "shipment_id": "ship_…",
  "license_state": "subscription_active"
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

Config knobs: `license.grace_warn_days`, `license.grace_restrict_days`, `license.grace_lock_days`.

---

## OS client entry points

| Surface | Path |
|---------|------|
| Package | `centurion/license/` |
| CLI | `centurion license status\|activate\|redeem\|…` |
| Slash | `/license` |
| Remote bridge | `license_status`, `license_activate`, `license_redeem` |
| Config | `license.*` in `config.yaml` |

---

## Superseded history (do not act on)

Kept deliberately so the retirement is legible rather than silently dropped.
Nothing in this section is live.

### Rent-to-own (retired 29 Sep 2026)

The old economics table row:

| Tier | Price | Phone-home | Unlock |
|------|-------|------------|--------|
| Rent-to-own | £250 / month | Every 30 days until paid off | Cumulative £5,000 → permanent |

The old wire vocabulary that went with it:

- tier value `rent_to_own`
- `state` values `rent_to_own_active` and `rent_to_own_paid_off`
- `kind` `rto_active` and `paid_off` in attestation payloads
- `invoice.paid` (RTO) added £250 (or the invoice amount) to a balance, and a
  balance ≥ 5000 issued a `paid_off` attestation and stopped requiring
  phone-home

All of it is gone: there is no cumulative balance and no paid-off state to
reach. The client-side constants (`DEFAULT_RTO_TARGET_GBP`, `LicenseTier.RENT_TO_OWN`
handling) survive only as tolerant no-ops. Signed attestations were removed
entirely on 29 Sep 2026 — see the section above.

### Outright / `owned` (retired 29 Sep 2026)

The old table row:

| Tier | Price | Phone-home | Unlock |
|------|-------|------------|--------|
| Outright | £4,250 once | None | Day one, hardware-bound |

The old `outright_owned` / `owned` states and the `outright` tier are retired —
there is one licence level, `subscription`. The `/license/redeem` endpoint and
its proof-of-purchase (`pop_…`) tokens are retained only as legacy, hardware-bound
grant machinery; no new outright grants are issued. `/license/reissue` remains a
live hardware-failure / device-replace flow.

### Retired wire fields

`balance_paid_eur`, `balance_target_eur`, `balance_remaining`, `total_paid` and
`owned` were the rent-to-own bookkeeping surface. They are still accepted and
echoed for backward compatibility with Brains in the field, but are **always
neutral** (`0` / `false`). Do not sum them, do not display them, do not branch
on them.
