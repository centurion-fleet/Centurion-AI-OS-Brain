/**
 * POST /api/remote-relay/enable
 * Body: { install_id: string, display_name?: string }
 * Registers / updates a Brain install and sets relay_enabled=true.
 *
 * Customer Brains call this from Settings → Anywhere. install_id is the
 * capability — do not require REMOTE_RELAY_ADMIN_TOKEN here (pair/revoke stay gated).
 */
import { errorResponse, json, supabaseFetch } from "../lib";

export const runtime = "nodejs";

export async function POST(req: Request): Promise<Response> {
  try {
    const body = (await req.json()) as {
      install_id?: string;
      display_name?: string;
    };
    const installId = (body.install_id || "").trim();
    if (!installId) {
      return json({ ok: false, error: "install_id required" }, 400);
    }
    const res = await supabaseFetch("/rest/v1/remote_brain_installs", {
      method: "POST",
      prefer: "resolution=merge-duplicates,return=representation",
      body: JSON.stringify({
        install_id: installId,
        display_name: body.display_name || null,
        relay_enabled: true,
        last_seen_at: new Date().toISOString(),
      }),
      headers: {
        "Content-Type": "application/json",
        on_conflict: "install_id",
      },
    });
    // PostgREST upsert via Prefer + on_conflict query param
    if (!res.ok) {
      const alt = await supabaseFetch(
        `/rest/v1/remote_brain_installs?on_conflict=install_id`,
        {
          method: "POST",
          prefer: "resolution=merge-duplicates,return=representation",
          body: JSON.stringify({
            install_id: installId,
            display_name: body.display_name || null,
            relay_enabled: true,
            last_seen_at: new Date().toISOString(),
          }),
        }
      );
      if (!alt.ok) {
        return json(
          { ok: false, error: await alt.text() },
          alt.status
        );
      }
      const rows = (await alt.json()) as unknown[];
      return json({
        ok: true,
        install: rows[0] || null,
        channel: `brain:${installId}`,
      });
    }
    const rows = (await res.json()) as unknown[];
    return json({
      ok: true,
      install: rows[0] || null,
      channel: `brain:${installId}`,
    });
  } catch (err) {
    return errorResponse(err);
  }
}
