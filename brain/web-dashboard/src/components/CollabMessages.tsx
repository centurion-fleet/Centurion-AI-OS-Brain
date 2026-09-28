import { useCallback, useEffect, useMemo, useState } from "react";
import { bridgeCall } from "../hooks/useBridge";
import type { BridgeOk } from "../types/life";

/**
 * What two connected Centurions actually say to each other.
 *
 * The transport, the inbox and the send path were built and tested before this
 * screen existed — which meant two owners could pair their Brains and then find
 * nothing to do with the link. A connection with no way to speak is not a
 * collaboration, it is a handshake. This is the part that makes it mean
 * something.
 *
 * Two rules carried over from the backend, both deliberate:
 *
 *   1. Never dress a failure up as a success. The bridge answers "sent" or
 *      "queued" and this screen repeats whichever it was, in those words.
 *   2. Nothing is sent or approved behind the owner's back. They write it, they
 *      press Send, they read what arrives. The hand on the wheel stays theirs.
 */

interface FleetMessage {
  message_id: string;
  sender_id: string;
  sender_name: string;
  recipient_id: string;
  subject: string;
  body: string;
  priority: string;
  timestamp: number;
  received_at: number;
  read: boolean;
}

interface InboxResponse extends BridgeOk {
  messages: FleetMessage[];
  count: number;
  unread: number;
}

interface SendResponse extends BridgeOk {
  delivered?: boolean;
  queued?: boolean;
  message?: string;
}

interface PeerRow {
  id: string;
  name: string;
  address: string;
  status: string;
}

/** "just now", "20 minutes ago", "yesterday" — enough to order a short list. */
function when(seconds: number): string {
  if (!seconds) return "";
  const delta = Math.max(0, Date.now() / 1000 - seconds);
  if (delta < 90) return "just now";
  const mins = Math.round(delta / 60);
  if (mins < 60) return `${mins} minute${mins === 1 ? "" : "s"} ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours} hour${hours === 1 ? "" : "s"} ago`;
  const days = Math.round(hours / 24);
  if (days === 1) return "yesterday";
  if (days < 30) return `${days} days ago`;
  return new Date(seconds * 1000).toLocaleDateString();
}

export function CollabMessages({ peers }: { peers: PeerRow[] }) {
  const [messages, setMessages] = useState<FleetMessage[]>([]);
  const [unread, setUnread] = useState(0);
  const [inboxError, setInboxError] = useState<string | null>(null);
  const [loaded, setLoaded] = useState(false);

  const [to, setTo] = useState("");
  const [subject, setSubject] = useState("");
  const [body, setBody] = useState("");
  const [sending, setSending] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const [sendError, setSendError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const res = await bridgeCall<InboxResponse>("fleet_inbox", { limit: 50 });
      setMessages(res.messages ?? []);
      setUnread(res.unread ?? 0);
      setInboxError(null);
    } catch (e) {
      setInboxError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoaded(true);
    }
  }, []);

  useEffect(() => {
    void load();
    const t = window.setInterval(() => void load(), 15_000);
    return () => window.clearInterval(t);
  }, [load]);

  // Default the picker to the only peer, so the common case is one press.
  useEffect(() => {
    if (to || peers.length === 0) return;
    setTo(peers[0].name || peers[0].id);
  }, [peers, to]);

  // A peer that has been forgotten should not stay selected.
  useEffect(() => {
    if (!to) return;
    const still = peers.some((p) => (p.name || p.id) === to);
    if (!still) setTo(peers[0] ? peers[0].name || peers[0].id : "");
  }, [peers, to]);

  async function gotIt(id: string) {
    try {
      await bridgeCall("fleet_mark_read", { message_id: id });
      setMessages((prev) =>
        prev.map((m) => (m.message_id === id ? { ...m, read: true } : m)),
      );
      setUnread((n) => Math.max(0, n - 1));
    } catch (e) {
      setInboxError(e instanceof Error ? e.message : String(e));
    }
  }

  async function send() {
    if (!to) {
      setSendError("Choose which Centurion to send to.");
      return;
    }
    if (!body.trim()) {
      setSendError("There is nothing to send — write the message first.");
      return;
    }
    setSending(true);
    setSendError(null);
    setResult(null);
    try {
      const res = await bridgeCall<SendResponse>("fleet_send", {
        peer_id: to,
        subject: subject.trim() || "(no subject)",
        body: body.trim(),
      });
      // Repeat what the bridge said happened, in its own terms.
      setResult(
        res.message ||
          (res.delivered
            ? "Sent — the other Centurion has it."
            : res.queued
              ? "Queued — the other Brain is not answering yet. It will go when it does."
              : "Handed to the other Centurion."),
      );
      setSubject("");
      setBody("");
      await load();
    } catch (e) {
      setSendError(e instanceof Error ? e.message : String(e));
    } finally {
      setSending(false);
    }
  }

  const ordered = useMemo(
    () => [...messages].sort((a, b) => (b.received_at || 0) - (a.received_at || 0)),
    [messages],
  );

  return (
    <div className="mt-5 border-t border-border pt-5">
      {/* ── What has arrived ─────────────────────────────────────────── */}
      <p className="text-sm font-semibold text-ink">
        Messages from other Centurions
        {unread > 0 ? ` · ${unread} new` : ""}
      </p>
      <p className="mt-1 text-xs text-muted">
        Newest first. Press <b>Got it</b> once you have read and dealt with one —
        it stops being new.
      </p>

      {inboxError && (
        <p
          className="mt-3 rounded-xl border border-amber-glow/40 bg-amber-muted px-3 py-2 text-sm text-ink"
          role="alert"
        >
          {inboxError}
        </p>
      )}

      {!inboxError && loaded && ordered.length === 0 && (
        <p className="mt-3 text-sm text-muted">
          Nothing yet. When the other Centurion sends something, it lands here.
        </p>
      )}

      {ordered.length > 0 && (
        <div className="mt-3 flex flex-col gap-2">
          {ordered.map((m) => (
            <div
              key={m.message_id}
              className={`rounded-xl border px-3 py-2 ${
                m.read
                  ? "border-border bg-canvas"
                  : "border-accent/40 bg-accent/10"
              }`}
            >
              <div className="flex flex-wrap items-start justify-between gap-2">
                <div className="min-w-0">
                  <p
                    className={`text-sm text-ink ${m.read ? "" : "font-semibold"}`}
                  >
                    {m.subject || "(no subject)"}
                  </p>
                  <p className="mt-0.5 text-xs text-muted">
                    from {m.sender_name || m.sender_id || "another Centurion"}
                    {m.received_at ? ` · ${when(m.received_at)}` : ""}
                  </p>
                </div>
                {!m.read && (
                  <button
                    type="button"
                    className="shrink-0 rounded-full bg-accent px-3 py-1 text-[11px] font-semibold text-[var(--on-accent)]"
                    onClick={() => void gotIt(m.message_id)}
                  >
                    Got it
                  </button>
                )}
              </div>
              {m.body && (
                <p className="mt-2 whitespace-pre-wrap text-sm text-ink">{m.body}</p>
              )}
            </div>
          ))}
        </div>
      )}

      {/* ── What you send ────────────────────────────────────────────── */}
      <div className="mt-5 border-t border-border pt-5">
        <p className="text-sm font-semibold text-ink">
          Send something to the other Centurion
        </p>
        <p className="mt-1 text-xs text-muted">
          The subject is what they see first, so make it say the job —
          “Check the pricing sheet”.
        </p>

        {(sendError || result) && (
          <p
            className={`mt-3 rounded-xl border px-3 py-2 text-sm text-ink ${
              sendError
                ? "border-amber-glow/40 bg-amber-muted"
                : "border-accent/40 bg-accent/10"
            }`}
            role="alert"
          >
            {sendError || result}
          </p>
        )}

        <div className="mt-3 flex flex-col gap-2">
          <select
            className="w-full rounded-xl border border-border bg-canvas px-3 py-2 text-sm text-ink"
            value={to}
            onChange={(e) => setTo(e.target.value)}
          >
            {peers.map((p) => (
              <option key={p.id} value={p.name || p.id}>
                {p.name || p.id}
                {p.status && p.status !== "online" ? ` · ${p.status}` : ""}
              </option>
            ))}
          </select>
          <input
            className="w-full rounded-xl border border-border bg-canvas px-3 py-2 text-sm text-ink"
            placeholder="Subject — Check the pricing sheet"
            value={subject}
            onChange={(e) => setSubject(e.target.value)}
          />
          <textarea
            className="min-h-[96px] w-full rounded-xl border border-border bg-canvas px-3 py-2 text-sm text-ink"
            placeholder="Write the message."
            value={body}
            onChange={(e) => setBody(e.target.value)}
          />
        </div>

        <button
          type="button"
          className="mt-3 inline-flex min-h-11 items-center rounded-full bg-accent px-4 text-sm font-semibold text-[var(--on-accent)] disabled:opacity-60"
          onClick={() => void send()}
          disabled={sending}
        >
          {sending ? "Sending…" : "Send"}
        </button>

        <p className="mt-3 text-xs text-muted">
          Messages travel over your own network and are authenticated — another
          machine cannot post into this Brain without the secret. They are not yet
          encrypted in transit, so keep client names, figures and passwords out of
          the message itself.
        </p>
      </div>
    </div>
  );
}
