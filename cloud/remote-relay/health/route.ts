/**
 * GET /api/remote-relay/health
 * POST body unused — liveness for Brain / ops.
 */
import { json, errorResponse, requireSupabase } from "../lib";

export const runtime = "nodejs";

export async function GET(): Promise<Response> {
  try {
    // Touch env so misconfigured deploys fail closed.
    requireSupabase();
    return json({
      ok: true,
      service: "centurion-remote-relay",
      pipe: "supabase-realtime",
      lan_crypto_chat_unchanged: true,
    });
  } catch (err) {
    return errorResponse(err);
  }
}
