/**
 * GET /api/remote-relay/health
 * Public liveness + public Realtime endpoints (no service role).
 */
import { json, errorResponse, requireSupabase, supabaseAnonKey, supabaseUrl } from "../lib";

export const runtime = "nodejs";

export async function GET(): Promise<Response> {
  try {
    requireSupabase();
    const url = supabaseUrl();
    const anon = supabaseAnonKey();
    if (!anon) {
      return json(
        {
          ok: false,
          error: "Missing env NEXT_PUBLIC_SUPABASE_ANON_KEY",
        },
        500
      );
    }
    return json({
      ok: true,
      service: "centurion-remote-relay",
      pipe: "supabase-realtime",
      lan_crypto_chat_unchanged: true,
      supabase_url: url,
      supabase_anon_key: anon,
    });
  } catch (err) {
    return errorResponse(err);
  }
}
