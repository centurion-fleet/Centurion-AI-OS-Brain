/**
 * POST /api/remote-relay/pair
 * Body: { install_id: string, device_label?: string, fingerprint?: string }
 * Mints a one-time pair token for the App Store iPhone (store hash only).
 */
import {
  assertAdmin,
  errorResponse,
  json,
  mintToken,
  supabaseFetch,
} from "../lib";

export const runtime = "nodejs";

export async function POST(req: Request): Promise<Response> {
  try {
    assertAdmin(req);
    const body = (await req.json()) as {
      install_id?: string;
      device_label?: string;
      fingerprint?: string;
    };
    const installId = (body.install_id || "").trim();
    if (!installId) {
      return json({ ok: false, error: "install_id required" }, 400);
    }
    const lookup = await supabaseFetch(
      `/rest/v1/remote_brain_installs?install_id=eq.${encodeURIComponent(installId)}&select=id,relay_enabled`,
      { method: "GET" }
    );
    if (!lookup.ok) {
      return json({ ok: false, error: await lookup.text() }, lookup.status);
    }
    const brains = (await lookup.json()) as Array<{
      id: string;
      relay_enabled: boolean;
    }>;
    if (!brains.length) {
      return json({ ok: false, error: "unknown install_id — call enable first" }, 404);
    }
    if (!brains[0].relay_enabled) {
      return json({ ok: false, error: "relay disabled for this Brain" }, 403);
    }
    const { token, tokenHash } = mintToken();
    const insert = await supabaseFetch("/rest/v1/remote_pair_tokens", {
      method: "POST",
      prefer: "return=representation",
      body: JSON.stringify({
        brain_id: brains[0].id,
        token_hash: tokenHash,
        device_label: body.device_label || null,
        fingerprint: body.fingerprint || null,
        revoked: false,
      }),
    });
    if (!insert.ok) {
      return json({ ok: false, error: await insert.text() }, insert.status);
    }
    const rows = (await insert.json()) as unknown[];
    return json({
      ok: true,
      token,
      pair: rows[0] || null,
      channel: `brain:${installId}`,
      note: "Show token once; store only the hash server-side.",
    });
  } catch (err) {
    return errorResponse(err);
  }
}
