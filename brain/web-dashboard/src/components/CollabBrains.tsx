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
  /** Returned so the owner can hand it over. Empty when no secret is set. */
  secret: string;
  peers: PeerRow[];
  peer_count: number;
  message?: string | null;
}

/**
 * Invite another owner onto this Brain — or join one that invited you.
 *
 * Two halves of one job: this Brain has to be reachable before anyone can reach
 * it, and the listener only binds after a Brain restart, so we say that plainly
 * rather than implying the link is already live.
 *
 * The invite is deliberately built from two things the owner can read straight
 * off this screen — an address and a shared secret. The secret is shown here
 * because without it an owner who enabled last week has nothing to hand over,
 * and an invite nobody can act on is not an invite.
 */
export function CollabBrains() {
  const [open, setOpen] = useState(false);
  const [status, setStatus] = useState<PeerStatus | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [justEnabled, setJustEnabled] = useState(false);
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState<string | null>(null);

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
    // Load even while collapsed. This panel sits behind a toggle, so a bridge that
    // cannot answer previously failed in total silence: the control that would have
    // appeared simply never rendered, leaving the owner with nothing to explain it.
    // Adrian, 25 Sep 2026 — he went hunting for a button that was never going to be
    // drawn, because an un-restarted Brain serves an older bridge than its deck.
    void load();
  }, [load]);

  useEffect(() => {
    if (!open) return;
    void load();
  }, [open, load]);

  async function copy(text: string, which: string) {
    if (!text) return;
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      // WebKitGTK can refuse the async clipboard API. Fall back to a selection
      // based copy so the button still does something on the shipped WebView.
      const ta = document.createElement("textarea");
      ta.value = text;
      ta.setAttribute("readonly", "");
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      try {
        document.execCommand("copy");
      } catch {
        setError("Could not copy automatically — select the text and copy it.");
        document.body.removeChild(ta);
        return;
      }
      document.body.removeChild(ta);
    }
    setCopied(which);
    window.setTimeout(() => setCopied(null), 2000);
  }

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
    if (!address.trim() || !token.trim()) {
      setError(
        "Enter both the other Brain's address and the shared secret they gave you.",
      );
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

  const handOver =
    status && status.reachable && status.has_secret && status.secret
      ? [
          { which: "address", label: "Address", value: status.address, secret: false },
          { which: "secret", label: "Shared secret", value: status.secret, secret: true },
        ]
      : [];

  return (
    <section className="mb-6">
      <button
        type="button"
        className="min-h-11 rounded-full px-4 text-sm font-semibold glass text-ink"
        onClick={() => setOpen((v) => !v)}
      >
        {open
          ? "Hide invite & join"
          : error
            ? "Invite another owner · join a collaboration — this Brain did not answer (tap to see why)"
            : `Invite another owner · join a collaboration · ${peers.length}`}
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

          {/* ── Invite: produce the two details the other person needs ── */}
          <p className="text-sm font-semibold text-ink">Invite to collaboration</p>
          <p className="mt-1 text-xs text-muted">
            Bring another owner in. Give them the two details below — they enter
            them on their own Brain under “Join a collaboration”.
          </p>

          {status && !status.reachable && (
            <>
              <p className="mt-3 text-sm text-muted">
                {status.message ||
                  "This Brain only listens on itself, so nobody can reach it yet."}
              </p>
              <button
                type="button"
                className="mt-3 inline-flex min-h-11 items-center rounded-full bg-accent px-4 text-sm font-semibold text-[var(--on-accent)]"
                onClick={() => void enable()}
                disabled={busy}
              >
                {busy ? "Opening…" : "Make this Brain reachable"}
              </button>
            </>
          )}

          {handOver.length > 0 && (
            <>
              <div className="mt-3 flex flex-col gap-2">
                {handOver.map((row) => (
                  <div
                    key={row.which}
                    className="rounded-xl border border-border bg-canvas px-3 py-2"
                  >
                    <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-muted">
                      {row.label}
                    </p>
                    <div className="mt-1 flex items-start justify-between gap-3">
                      <p
                        className={`select-all break-all font-mono text-sm text-ink ${
                          row.secret ? "" : ""
                        }`}
                      >
                        {row.value}
                      </p>
                      <button
                        type="button"
                        className="shrink-0 rounded-full px-2 py-1 text-[11px] font-semibold text-muted hover:bg-accent/15 hover:text-ink"
                        onClick={() => void copy(row.value, row.which)}
                      >
                        {copied === row.which ? "Copied" : "Copy"}
                      </button>
                    </div>
                  </div>
                ))}
              </div>
              <p className="mt-2 text-xs text-muted">
                Keep the secret private. Anyone holding both of these can reach
                this Brain.
              </p>
            </>
          )}

          {status && status.reachable && !status.listening && (
            <p className="mt-2 text-sm text-ink">
              Nothing is accepting connections on port {status.port} yet. Restart
              the Brain — the address above only goes live after that.
            </p>
          )}

          {justEnabled && status?.listening === false && (
            <p className="mt-2 text-xs text-muted">
              Restart the Brain so it starts listening.
            </p>
          )}

          {/* ── Join: enter what the other person gave you ── */}
          <div className="mt-5 border-t border-border pt-5">
            <p className="text-sm font-semibold text-ink">Join a collaboration</p>
            <p className="mt-1 text-xs text-muted">
              Enter the address and shared secret another owner gave you. The
              link is only saved once their Brain actually answers.
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
                placeholder="Name it — Eve (optional)"
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
              {busy ? "Joining…" : "Join collaboration"}
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
