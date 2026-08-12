/**
 * POST /api/remote-relay/revoke
 * Body: { token?: string, token_hash?: string, install_id?: string, all?: boolean }
 * Revokes a phone pair token (or all tokens for an install).
 */
import { assertAdmin, errorResponse, hashToken, json, supabaseFetch } from "../lib";

export const runtime = "nodejs";

export async function POST(req: Request): Promise<Response> {
  try {
    assertAdmin(req);
    const body = (await req.json()) as {
      token?: string;
      token_hash?: string;
      install_id?: string;
      all?: boolean;
    };

    if (body.all && body.install_id) {
      const lookup = await supabaseFetch(
        `/rest/v1/remote_brain_installs?install_id=eq.${encodeURIComponent(body.install_id)}&select=id`,
        { method: "GET" }
      );
      const brains = (await lookup.json()) as Array<{ id: string }>;
      if (!brains.length) {
        return json({ ok: false, error: "unknown install_id" }, 404);
      }
      const patch = await supabaseFetch(
        `/rest/v1/remote_pair_tokens?brain_id=eq.${brains[0].id}`,
        {
          method: "PATCH",
          body: JSON.stringify({ revoked: true }),
        }
      );
      if (!patch.ok) {
        return json({ ok: false, error: await patch.text() }, patch.status);
      }
      return json({ ok: true, revoked: "all" });
    }

    const tokenHash =
      (body.token_hash || "").trim() ||
      (body.token ? hashToken(body.token) : "");
    if (!tokenHash) {
      return json({ ok: false, error: "token or token_hash required" }, 400);
    }
    const patch = await supabaseFetch(
      `/rest/v1/remote_pair_tokens?token_hash=eq.${encodeURIComponent(tokenHash)}`,
      {
        method: "PATCH",
        body: JSON.stringify({ revoked: true }),
      }
    );
    if (!patch.ok) {
      return json({ ok: false, error: await patch.text() }, patch.status);
    }
    return json({ ok: true, revoked: tokenHash.slice(0, 8) });
  } catch (err) {
    return errorResponse(err);
  }
}
