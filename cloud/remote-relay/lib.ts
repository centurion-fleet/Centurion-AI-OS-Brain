/**
 * Centurion Remote relay — Vercel control plane (service role only).
 *
 * Deploy these routes on the Centurion Vercel project that already hosts
 * sales/help. They mint/revoke pair tokens and flip relay_enabled;
 * Supabase Realtime carries opaque E2E envelopes (see REMOTE_RELAY.md).
 *
 * Env (Vercel):
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY
 *   REMOTE_RELAY_ADMIN_TOKEN  (optional shared secret for Brain enable calls)
 */

import { createHash, randomBytes } from "node:crypto";

export type Json = Record<string, unknown>;

export function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing env ${name}`);
  return v;
}

/** Prefer Centurion Vercel naming; accept SUPABASE_URL as alias. */
export function supabaseUrl(): string {
  return (
    process.env.NEXT_PUBLIC_SUPABASE_URL ||
    process.env.SUPABASE_URL ||
    ""
  ).replace(/\/$/, "");
}

export function supabaseServiceKey(): string {
  return process.env.SUPABASE_SERVICE_ROLE_KEY || "";
}

export function requireSupabase(): { url: string; key: string } {
  const url = supabaseUrl();
  const key = supabaseServiceKey();
  if (!url) throw new Error("Missing env NEXT_PUBLIC_SUPABASE_URL (or SUPABASE_URL)");
  if (!key) throw new Error("Missing env SUPABASE_SERVICE_ROLE_KEY");
  return { url, key };
}

export function hashToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

export function mintToken(): { token: string; tokenHash: string } {
  const token = randomBytes(24).toString("base64url");
  return { token, tokenHash: hashToken(token) };
}

export function assertAdmin(req: Request): void {
  const expected = process.env.REMOTE_RELAY_ADMIN_TOKEN;
  if (!expected) return; // open in local/dev when unset
  const got = req.headers.get("x-centurion-relay-admin") || "";
  if (got !== expected) {
    const err = new Error("Unauthorized");
    (err as Error & { status: number }).status = 401;
    throw err;
  }
}

export async function supabaseFetch(
  path: string,
  init: RequestInit & { prefer?: string } = {}
): Promise<Response> {
  const { url, key } = requireSupabase();
  const headers = new Headers(init.headers || {});
  headers.set("apikey", key);
  headers.set("Authorization", `Bearer ${key}`);
  headers.set("Content-Type", "application/json");
  if (init.prefer) headers.set("Prefer", init.prefer);
  return fetch(url + path, { ...init, headers });
}

export function json(data: Json, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  });
}

export function errorResponse(err: unknown): Response {
  const status =
    typeof err === "object" && err && "status" in err
      ? Number((err as { status: number }).status)
      : 500;
  const message = err instanceof Error ? err.message : "Relay control error";
  return json({ ok: false, error: message }, status || 500);
}
