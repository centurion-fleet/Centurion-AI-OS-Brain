# Centurion Remote relay — Vercel control plane

Copy these App Router handlers into the Centurion Vercel Next.js app
(sales site / shared cloud) under `app/api/remote-relay/`:

| Route | File |
|-------|------|
| `GET /api/remote-relay/health` | `health/route.ts` (returns public `supabase_url` + `supabase_anon_key`) |
| `POST /api/remote-relay/enable` | `enable/route.ts` (customer Brain; no admin token) |
| `GET/POST /api/remote-relay/presence` | `presence/route.ts` |
| `POST /api/remote-relay/pair` | `pair/route.ts` (admin-gated) |
| `POST /api/remote-relay/revoke` | `revoke/route.ts` (admin-gated) |
| shared helpers | `lib.ts` → `app/api/remote-relay/_lib.ts` (adjust imports) |

Env: `NEXT_PUBLIC_SUPABASE_URL` (or `SUPABASE_URL`), `NEXT_PUBLIC_SUPABASE_ANON_KEY`,
`SUPABASE_SERVICE_ROLE_KEY`, optional `REMOTE_RELAY_ADMIN_TOKEN` (pair/revoke only).

Staged copy (sales site): `-personal-centurion-website-v5/app/api/remote-relay/`.

Apply schema: `brain/linux/docs/remote-relay-supabase.sql`.

Brain: `centurion_cli.remote_relay_service` + bridge actions `remote_relay_*`.
LAN `:9119` Crypto Chat stays preferred when reachable.
