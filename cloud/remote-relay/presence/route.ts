/**
 * GET  /api/remote-relay/presence?install_id=
 * POST /api/remote-relay/presence  { install_id, online, conn_epoch }
 *
 * Service-role read/write so the App Store iPhone and Brain do not fight RLS
 * with the public anon key. install_id is the capability (unguessable).
 */
import { errorResponse, json, supabaseFetch } from "../lib";

export const runtime = "nodejs";

async function lookupBrainId(installId: string): Promise<string | null> {
  const lookup = await supabaseFetch(
    `/rest/v1/remote_brain_installs?install_id=eq.${encodeURIComponent(installId)}&select=id,relay_enabled`,
    { method: "GET" }
  );
  if (!lookup.ok) return null;
  const brains = (await lookup.json()) as Array<{
    id: string;
    relay_enabled?: boolean;
  }>;
  if (!brains.length) return null;
  return brains[0].id;
}

export async function GET(req: Request): Promise<Response> {
  try {
    const installId = new URL(req.url).searchParams.get("install_id")?.trim() || "";
    if (!installId) {
      return json({ ok: false, error: "install_id required" }, 400);
    }
    const brainId = await lookupBrainId(installId);
    if (!brainId) {
      return json({
        ok: true,
        online: false,
        conn_epoch: null,
        install_id: installId,
      });
    }
    const presence = await supabaseFetch(
      `/rest/v1/remote_brain_presence?brain_id=eq.${encodeURIComponent(brainId)}&select=online,conn_epoch`,
      { method: "GET" }
    );
    if (!presence.ok) {
      return json({ ok: false, error: await presence.text() }, presence.status);
    }
    const rows = (await presence.json()) as Array<{
      online?: boolean;
      conn_epoch?: string | null;
    }>;
    const row = rows[0] || {};
    return json({
      ok: true,
      online: Boolean(row.online),
      conn_epoch: row.conn_epoch || null,
      install_id: installId,
    });
  } catch (err) {
    return errorResponse(err);
  }
}

export async function POST(req: Request): Promise<Response> {
  try {
    const body = (await req.json()) as {
      install_id?: string;
      online?: boolean;
      conn_epoch?: string | null;
    };
    const installId = (body.install_id || "").trim();
    if (!installId) {
      return json({ ok: false, error: "install_id required" }, 400);
    }
    const brainId = await lookupBrainId(installId);
    if (!brainId) {
      return json(
        { ok: false, error: "unknown install_id — call enable first" },
        404
      );
    }
    const epoch = body.conn_epoch ? String(body.conn_epoch) : null;
    const upsert = await supabaseFetch(
      `/rest/v1/remote_brain_presence?on_conflict=brain_id`,
      {
        method: "POST",
        prefer: "resolution=merge-duplicates,return=representation",
        body: JSON.stringify({
          brain_id: brainId,
          online: Boolean(body.online),
          conn_epoch: epoch,
          updated_at: new Date().toISOString(),
        }),
      }
    );
    if (!upsert.ok) {
      return json({ ok: false, error: await upsert.text() }, upsert.status);
    }
    const rows = (await upsert.json()) as unknown[];
    return json({
      ok: true,
      install_id: installId,
      presence: rows[0] || {
        online: Boolean(body.online),
        conn_epoch: epoch,
      },
    });
  } catch (err) {
    return errorResponse(err);
  }
}
