import { useCallback, useEffect, useState } from "react";
import { bridgeCall } from "../hooks/useBridge";
import type { BridgeOk } from "../types/life";

interface PeerRow {
  id: string;
  name: string;
  address: string;
  status: string;
  has_token: boolean;
}

interface PeerStatus extends BridgeOk {
  reachable: boolean;
  listening: boolean;
  host: string;
  port: number;
  address: string;
  has_secret: boolean;
  peers: PeerRow[];
  peer_count: number;
  message?: string | null;
}

/**
 * Connect this Brain to another Brain.
 *
 * Two halves of one job: make *this* Brain reachable, then pair with a peer.
 * The reachable half only binds after a Brain restart, so we say that plainly
 * rather than implying the link is already live.
 */
export function CollabBrains() {
  const [open, setOpen] = useState(false);
  const [status, setStatus] = useState<PeerStatus | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [secret, setSecret] = useState<string | null>(null);
  const [justEnabled, setJustEnabled] = useState(false);
  const [busy, setBusy] = useState(false);

  const [address, setAddress] = useState("");
  const [token, setToken] = useState("");
  const [peerName, setPeerName] = useState("");

  const load = useCallback(async () => {
    try {
      const res = await bridgeCall<PeerStatus>("fleet_peer_status");
      setStatus(res);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }, []);

  useEffect(() => {
    if (!open) return;
    void load();
  }, [open, load]);

  async function enable() {
    setBusy(true);
    setError(null);
    setNote(null);
    try {
      const res = await bridgeCall<{
        ok: boolean;
        address?: string;
        port?: number;
        secret?: string;
        message?: string;
      }>("fleet_peer_enable");
      if (res.secret) setSecret(res.secret);
      setJustEnabled(true);
      setNote(
        res.message ||
          "This Brain will accept other Brains. Restart the Brain to start listening.",
      );
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function connect() {
    if (!address.trim()) {
      setError("Enter the other Brain's address, like 192.168.10.42:18789.");
      return;
    }
    setBusy(true);
    setError(null);
    setNote(null);
    try {
      const res = await bridgeCall<{ ok: boolean; message?: string }>(
        "fleet_peer_connect",
        {
          address: address.trim(),
          token: token.trim(),
          peer_name: peerName.trim(),
        },
      );
      setNote(res.message || "Linked.");
      setAddress("");
      setToken("");
      setPeerName("");
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function forget(peerId: string) {
    setBusy(true);
    setError(null);
    try {
      await bridgeCall("fleet_peer_remove", { peer_id: peerId });
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  const peers = status?.peers ?? [];

  return (
    <section className="mb-6">
      <button
        type="button"
        className="min-h-11 rounded-full px-4 text-sm font-semibold glass text-ink"
        onClick={() => setOpen((v) => !v)}
      >
        {open ? "Hide Brains" : `Connect another Brain · ${peers.length}`}
      </button>

      {open && (
        <div className="mt-3 glass rounded-2xl p-5">
          {(error || note) && (
            <p
              className="mb-4 rounded-xl border border-amber-glow/40 bg-amber-muted px-3 py-2 text-sm text-ink"
              role="alert"
            >
              {error || note}
            </p>
          )}

          {status && (
            <p className="text-sm text-muted">
              {status.message ||
                (status.reachable
                  ? `This Brain is reachable at ${status.address}.`
                  : "This Brain currently only listens on itself — no other Brain can reach it yet.")}
            </p>
          )}

          {status && status.reachable && !status.listening && (
            <p className="mt-2 text-xs text-muted">
              Nothing is accepting connections on port {status.port} yet. Give the
              other Brain this address once the Brain has restarted:{" "}
              <span className="select-all font-mono">{status.address}</span>
            </p>
          )}

          {status && !status.reachable && (
            <button
              type="button"
              className="mt-3 inline-flex min-h-11 items-center rounded-full bg-accent px-4 text-sm font-semibold text-[var(--on-accent)]"
              onClick={() => void enable()}
              disabled={busy}
            >
              {busy ? "Opening…" : "Make this Brain reachable"}
            </button>
          )}

          {secret && (
            <div className="mt-4 rounded-xl border border-border bg-canvas px-3 py-3">
              <p className="text-xs font-semibold uppercase tracking-[0.14em] text-muted">
                Shared secret
              </p>
              <p className="mt-1 select-all break-all font-mono text-sm text-ink">
                {secret}
              </p>
              <p className="mt-2 text-xs text-muted">
                Give this to the other person and nobody else. Both Brains need
                the same one.
              </p>
              {justEnabled && (
                <p className="mt-2 text-xs text-muted">
                  Restart the Brain so it starts listening.
                </p>
              )}
            </div>
          )}

          <div className="mt-5 border-t border-border pt-5">
            <p className="text-sm font-semibold text-ink">
              Pair with a Brain that is already reachable
            </p>
            <div className="mt-3 flex flex-col gap-2">
              <input
                className="w-full rounded-xl border border-border bg-canvas px-3 py-2 text-sm text-ink"
                placeholder="Address — 192.168.10.42:18789"
                value={address}
                onChange={(e) => setAddress(e.target.value)}
              />
              <input
                className="w-full rounded-xl border border-border bg-canvas px-3 py-2 text-sm text-ink"
                placeholder="Shared secret"
                value={token}
                onChange={(e) => setToken(e.target.value)}
              />
              <input
                className="w-full rounded-xl border border-border bg-canvas px-3 py-2 text-sm text-ink"
                placeholder="Name it — ASTRA (optional)"
                value={peerName}
                onChange={(e) => setPeerName(e.target.value)}
              />
            </div>
            <button
              type="button"
              className="mt-3 inline-flex min-h-11 items-center rounded-full bg-accent px-4 text-sm font-semibold text-[var(--on-accent)]"
              onClick={() => void connect()}
              disabled={busy}
            >
              {busy ? "Pairing…" : "Pair"}
            </button>
          </div>

          {peers.length > 0 && (
            <div className="mt-5 border-t border-border pt-5">
              <p className="text-sm font-semibold text-ink">
                Connected Brains · {peers.length}
              </p>
              <div className="mt-2 flex flex-col gap-2">
                {peers.map((p) => (
                  <div
                    key={p.id}
                    className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-border bg-canvas px-3 py-2"
                  >
                    <div>
                      <p className="text-sm text-ink">{p.name || p.id}</p>
                      <p className="text-xs text-muted">
                        {p.address} · {p.status}
                      </p>
                    </div>
                    <button
                      type="button"
                      className="rounded-full px-2 py-1 text-[11px] font-semibold text-muted hover:bg-accent/15 hover:text-ink"
                      disabled={busy}
                      onClick={() => void forget(p.id)}
                    >
                      Forget
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}
    </section>
  );
}
