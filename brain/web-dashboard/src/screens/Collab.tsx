import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useDeckVisible } from "../hooks/useDeckVisible";
import { useCollab } from "../hooks/useCollab";
import { bridgeCall } from "../hooks/useBridge";
import {
  COLUMNS,
  type CollabCard,
  type CollabColumn,
  type CollabSwarm,
} from "../types/collab";

export function Collab() {
  const visible = useDeckVisible();
  const { swarms, loading, error, refresh, applySnapshot } = useCollab(visible);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [goal, setGoal] = useState("");
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [gatewayRunning, setGatewayRunning] = useState<boolean | null>(null);
  const [gatewayHint, setGatewayHint] = useState("");
  const [showAdvanced, setShowAdvanced] = useState(false);
  const formingRef = useRef(false);

  const selected = useMemo(() => {
    if (!swarms.length) return null;
    return swarms.find((s) => s.id === selectedId) ?? swarms[0];
  }, [swarms, selectedId]);

  useEffect(() => {
    if (selected && selected.id !== selectedId) setSelectedId(selected.id);
  }, [selected, selectedId]);

  const probeGateway = useCallback(async () => {
    try {
      const res = await bridgeCall<{
        ok: true;
        status?: { running?: boolean };
      }>("gateway_status");
      const running = Boolean(res.status?.running);
      setGatewayRunning(running);
      setGatewayHint(
        running
          ? "Gateway is running — workers can dispatch."
          : "Gateway is stopped. Form can still create the board; workers wait until it starts.",
      );
    } catch (e) {
      setGatewayRunning(false);
      setGatewayHint(e instanceof Error ? e.message : "Could not read gateway status.");
    }
  }, []);

  useEffect(() => {
    if (!visible) return;
    void probeGateway();
  }, [visible, probeGateway]);

  async function startGateway() {
    setBusy(true);
    setFormError(null);
    try {
      await bridgeCall("gateway_start");
      await probeGateway();
    } catch (e) {
      setFormError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function formSwarm() {
    const text = goal.trim();
    if (!text) {
      setFormError("Describe what the collaboration should achieve.");
      return;
    }
    if (formingRef.current) return;
    formingRef.current = true;
    setBusy(true);
    setFormError(null);
    try {
      const profilesRes = await bridgeCall<{
        ok: true;
        profiles?: { name: string }[];
      }>("profiles_list");
      const names = (profilesRes.profiles || [])
        .map((p) => p.name)
        .filter(Boolean);
      const first = names.includes("default") ? "default" : names[0] || "default";
      const second = names.find((n) => n !== first) || first;
      const created = await bridgeCall("swarm_create", {
        goal: text,
        name: "",
        // Gateway dispatcher picks up ready workers. Inline dispatch can hang
        // the Brain WebView click with no feedback.
        dispatch: false,
        workers: [
          { profile: first, title: "Research", body: text },
          { profile: second, title: "Draft", body: text },
        ],
        verifier_assignee: first,
        synthesizer_assignee: second,
      });
      let snap = await refresh();
      if (!snap?.swarms?.length) {
        snap = applySnapshot(created);
      }
      if (!snap?.swarms?.length) {
        setFormError(
          "The collaboration was created but the board did not appear. Try Form swarm again.",
        );
        return;
      }
      setGoal("");
      await probeGateway();
    } catch (e) {
      setFormError(e instanceof Error ? e.message : String(e));
    } finally {
      formingRef.current = false;
      setBusy(false);
    }
  }

  async function moveCard(card: CollabCard, column: CollabColumn) {
    if (!selected) return;
    setBusy(true);
    setFormError(null);
    try {
      await bridgeCall("swarm_move_card", {
        board: selected.id,
        task_id: card.id,
        column,
      });
      await refresh();
    } catch (e) {
      setFormError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  const empty = swarms.length === 0;

  return (
    <div className="mx-auto min-h-screen max-w-7xl px-4 pb-20 pt-8 sm:px-6 sm:pt-10">
      <header className="mb-6">
        <p className="text-[11px] font-semibold uppercase tracking-[0.16em] text-muted">
          Collaborate
        </p>
        <h1 className="font-display mt-1 text-3xl font-medium tracking-tight text-ink sm:text-4xl">
          Give your Sovereign a goal
        </h1>
        <p className="mt-2 max-w-2xl text-sm text-muted">
          Workers on this Brain research, draft, check, then synthesize. Gateway
          must be running on the desk for live dispatch.
        </p>
      </header>

      {gatewayRunning === false && (
        <div className="mb-6 flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-border bg-surface px-4 py-3">
          <p className="text-sm text-ink">{gatewayHint}</p>
          <button
            type="button"
            className="inline-flex min-h-11 items-center rounded-full bg-accent px-4 text-sm font-semibold text-[var(--on-accent)]"
            onClick={() => void startGateway()}
            disabled={busy}
          >
            Start gateway
          </button>
        </div>
      )}

      {(error || formError) && (
        <p
          className="mb-4 rounded-2xl border border-amber-glow/40 bg-amber-muted px-4 py-3 text-sm text-ink"
          role="alert"
        >
          {formError || error}
        </p>
      )}

      {loading && empty && (
        <p className="mb-4 text-sm text-muted">Opening collaborations…</p>
      )}

      {empty ? (
        <FirstRunForm
          goal={goal}
          setGoal={setGoal}
          busy={busy}
          onForm={() => void formSwarm()}
          showAdvanced={showAdvanced}
          setShowAdvanced={setShowAdvanced}
        />
      ) : (
        <>
          <div className="mb-4 flex flex-wrap items-center gap-2">
            {swarms.map((swarm) => (
              <button
                key={swarm.id}
                type="button"
                onClick={() => setSelectedId(swarm.id)}
                className={`min-h-11 rounded-full px-4 text-sm font-semibold ${
                  selected?.id === swarm.id
                    ? "bg-accent text-[var(--on-accent)]"
                    : "glass text-ink"
                }`}
              >
                {swarm.display_name}
                {swarm.pending_signal_count
                  ? ` · ${swarm.pending_signal_count}`
                  : ""}
              </button>
            ))}
            <button
              type="button"
              className="min-h-11 rounded-full px-4 text-sm font-semibold glass text-ink"
              onClick={() => setShowAdvanced((v) => !v)}
            >
              Form swarm
            </button>
          </div>

          {showAdvanced && (
            <div className="mb-6">
              <FirstRunForm
                goal={goal}
                setGoal={setGoal}
                busy={busy}
                onForm={() => void formSwarm()}
                showAdvanced={showAdvanced}
                setShowAdvanced={setShowAdvanced}
                compact
              />
            </div>
          )}

          {selected && (
            <Board
              swarm={selected}
              busy={busy}
              onMove={moveCard}
            />
          )}
        </>
      )}
    </div>
  );
}

function FirstRunForm({
  goal,
  setGoal,
  busy,
  onForm,
  showAdvanced,
  setShowAdvanced,
  compact = false,
}: {
  goal: string;
  setGoal: (v: string) => void;
  busy: boolean;
  onForm: () => void;
  showAdvanced: boolean;
  setShowAdvanced: (v: boolean) => void;
  compact?: boolean;
}) {
  return (
    <form
      className={compact ? "glass rounded-2xl p-5" : "glass-strong rounded-3xl p-6 sm:p-8"}
      onSubmit={(e) => {
        e.preventDefault();
        onForm();
      }}
    >
      <label className="block text-sm font-semibold text-ink">
        What should they work on?
        <textarea
          className="mt-2 w-full rounded-2xl border border-border bg-canvas px-4 py-3 text-ink outline-none"
          rows={compact ? 3 : 4}
          value={goal}
          onChange={(e) => setGoal(e.target.value)}
          placeholder="Draft a weekly briefing from this week’s research."
          onKeyDown={(e) => {
            if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
              e.preventDefault();
              onForm();
            }
          }}
        />
      </label>
      <div className="mt-4 flex flex-wrap items-center gap-3">
        <button
          type="button"
          className="inline-flex min-h-11 cursor-pointer items-center rounded-full bg-accent px-5 text-sm font-semibold text-[var(--on-accent,#FAFAF9)] disabled:opacity-50"
          disabled={busy}
          onMouseDown={(e) => {
            // WebKitGTK often eats the click after textarea blur; form on press.
            if (e.button !== 0 || busy) return;
            e.preventDefault();
            onForm();
          }}
          onClick={(e) => {
            e.preventDefault();
            onForm();
          }}
        >
          {busy ? "Forming…" : "Form swarm"}
        </button>
        <button
          type="button"
          className="cursor-pointer text-sm font-medium text-muted underline-offset-4 hover:underline"
          onClick={() => setShowAdvanced(!showAdvanced)}
        >
          {showAdvanced ? "Hide advanced" : "Join another owner (Mission Control)"}
        </button>
      </div>
      {showAdvanced && <AdvancedJoin />}
    </form>
  );
}

function AdvancedJoin() {
  const [token, setToken] = useState("");
  const [projectId, setProjectId] = useState("");
  const [installId, setInstallId] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function join() {
    setBusy(true);
    setMessage(null);
    try {
      await bridgeCall("swarm_connect", {
        token: token.trim(),
        project_id: projectId.trim(),
        install_id: installId.trim(),
      });
      setMessage("Joined.");
    } catch (e) {
      setMessage(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mt-5 space-y-3 border-t border-border pt-5">
      <p className="text-sm text-muted">
        Paste a Mission Control project token. A down portal shows an error — it
        does not save a silent empty board.
      </p>
      <input
        className="w-full rounded-xl border border-border bg-canvas px-3 py-2 text-sm text-ink"
        placeholder="ctk_proj_…"
        value={token}
        onChange={(e) => setToken(e.target.value)}
      />
      <input
        className="w-full rounded-xl border border-border bg-canvas px-3 py-2 text-sm text-ink"
        placeholder="Project id"
        value={projectId}
        onChange={(e) => setProjectId(e.target.value)}
      />
      <input
        className="w-full rounded-xl border border-border bg-canvas px-3 py-2 text-sm text-ink"
        placeholder="Install id"
        value={installId}
        onChange={(e) => setInstallId(e.target.value)}
      />
      <button
        type="button"
        className="inline-flex min-h-11 items-center rounded-full glass px-4 text-sm font-semibold text-ink"
        disabled={busy}
        onClick={() => void join()}
      >
        Join collaboration
      </button>
      {message && <p className="text-sm text-ink">{message}</p>}
    </div>
  );
}

function Board({
  swarm,
  busy,
  onMove,
}: {
  swarm: CollabSwarm;
  busy: boolean;
  onMove: (card: CollabCard, column: CollabColumn) => void;
}) {
  const cards = swarm.cards || [];
  return (
    <section>
      <div className="mb-4 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-xl font-medium text-ink">{swarm.display_name}</h2>
          <p className="mt-1 max-w-2xl text-sm text-muted">{swarm.objective}</p>
        </div>
      </div>
      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        {COLUMNS.map((col) => {
          const colCards = cards.filter((c) => c.column === col.id);
          return (
            <div key={col.id} className="glass rounded-2xl p-3">
              <p className="mb-3 px-1 text-[11px] font-semibold uppercase tracking-[0.14em] text-muted">
                {col.label} · {colCards.length}
              </p>
              <div className="flex flex-col gap-2">
                {colCards.map((card) => (
                  <article
                    key={card.id}
                    className="rounded-xl border border-border bg-canvas p-3"
                  >
                    <p className="text-sm font-semibold text-ink">{card.title}</p>
                    <p className="mt-1 text-xs text-muted">
                      {card.assignee || "Unassigned"}
                      {card.role !== "task" ? ` · ${card.role}` : ""}
                    </p>
                    {card.body && (
                      <p className="mt-2 line-clamp-3 text-xs text-muted">{card.body}</p>
                    )}
                    <div className="mt-3 flex flex-wrap gap-1">
                      {COLUMNS.filter((c) => c.id !== col.id && c.id !== "doing").map(
                          (dest) => (
                            <button
                              key={dest.id}
                              type="button"
                              disabled={busy}
                              className="rounded-full px-2 py-1 text-[11px] font-semibold text-muted hover:bg-accent/15 hover:text-ink"
                              onClick={() => onMove(card, dest.id)}
                            >
                              {dest.label}
                            </button>
                          ),
                        )}
                    </div>
                  </article>
                ))}
                {colCards.length === 0 && (
                  <p className="px-1 py-6 text-center text-xs text-muted">None</p>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </section>
  );
}
