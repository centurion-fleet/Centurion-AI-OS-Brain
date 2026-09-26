import { useMemo, useState, type ReactNode } from "react";
import { useNavigate } from "react-router-dom";
import { FocusBackBar } from "../components/FocusBackBar";
import { AnimatePresence, m as motion } from "framer-motion";
import { bridgeCall } from "../hooks/useBridge";

type Step = "welcome" | "dump" | "prioritise" | "crown" | "done";

interface Candidate {
  title: string;
  kind: "dream" | "mission";
}

function parseDump(text: string): Candidate[] {
  const lines = text
    .split(/[\n,;]+/)
    .map((l) => l.replace(/^[-*•\d.)\s]+/, "").trim())
    .filter((l) => l.length >= 2);
  const unique: string[] = [];
  for (const l of lines) {
    if (!unique.some((u) => u.toLowerCase() === l.toLowerCase())) {
      unique.push(l.slice(0, 120));
    }
  }
  return unique.slice(0, 12).map((title) => ({ title, kind: "dream" as const }));
}

export function Discovery() {
  const navigate = useNavigate();
  const [step, setStep] = useState<Step>("welcome");
  const [dump, setDump] = useState("");
  const [candidates, setCandidates] = useState<Candidate[]>([]);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [primaryTitle, setPrimaryTitle] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const selectedList = useMemo(
    () => candidates.filter((c) => selected.has(c.title)),
    [candidates, selected],
  );

  function startDump() {
    setStep("dump");
  }

  function goPrioritise() {
    const parsed = parseDump(dump);
    if (!parsed.length) {
      setError("Share a few aspirations — one per line is perfect.");
      return;
    }
    setError(null);
    setCandidates(parsed);
    setSelected(new Set(parsed.slice(0, Math.min(3, parsed.length)).map((c) => c.title)));
    setStep("prioritise");
  }

  function toggle(title: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(title)) next.delete(title);
      else next.add(title);
      return next;
    });
  }

  function goCrown() {
    if (!selectedList.length) {
      setError("Pick at least one to carry forward.");
      return;
    }
    setError(null);
    setPrimaryTitle(selectedList[0].title);
    setStep("crown");
  }

  async function commit() {
    if (!primaryTitle) return;
    setBusy(true);
    setError(null);
    try {
      // Ensure a subject exists
      let subjectId: string | undefined;
      const subjectsRes = await bridgeCall<{
        ok: true;
        subjects: { id: string; name: string }[];
      }>("life_subjects_list");
      const subjects = subjectsRes.subjects || [];
      if (subjects.length) {
        subjectId = subjects[0].id;
      } else {
        const put = await bridgeCall<{
          ok: true;
          subject: { id: string };
        }>("life_subject_put", {
          name: "Life",
          icon: "sparkles",
        });
        subjectId = put.subject.id;
      }

      // Dreams for non-primary selections
      for (const c of selectedList) {
        if (c.title === primaryTitle) continue;
        await bridgeCall("life_dream_put", {
          title: c.title,
          description: "From Discovery",
        });
      }

      // Unselected dump items → dreams too (whisper shelf)
      for (const c of candidates) {
        if (selected.has(c.title)) continue;
        await bridgeCall("life_dream_put", {
          title: c.title,
          description: "Parked from Discovery",
        });
      }

      const missionRes = await bridgeCall<{
        ok: true;
        mission: { id: string };
      }>("life_mission_put", {
        mission: {
          subject_id: subjectId,
          title: primaryTitle,
          statement: `I am building toward: ${primaryTitle}`,
          situation: dump.slice(0, 500),
          why: "Chosen during Discovery as the mission that matters most right now.",
          purpose: primaryTitle,
          mission_type: "primary",
          phase: "discovery",
          targets: [
            {
              title: "Clarify the next concrete milestone",
              target_type: "essential",
            },
            {
              title: "Define success for this season",
              target_type: "shouldHave",
            },
            {
              title: "Capture supporting dreams",
              target_type: "niceToHave",
            },
          ],
        },
      });

      const missionId = missionRes.mission.id;
      await bridgeCall("life_stack_set_primary", { mission_id: missionId });
      setStep("done");
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mx-auto flex min-h-screen max-w-xl flex-col bg-surface/40 px-4 pb-16 pt-0 sm:px-6">
      <FocusBackBar eyebrow="Discovery" title="Shape a primary mission" />

      <AnimatePresence mode="wait">
        <motion.div
          key={step}
          initial={{ opacity: 0, y: 18 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -12 }}
          transition={{ type: "spring", stiffness: 160, damping: 22 }}
          className="flex flex-1 flex-col"
        >
          {step === "welcome" && (
            <Ceremony
              eyebrow="Discovery"
              title="What are you building toward?"
              body="A short ceremony — dump everything on your mind, gently prioritise, then crown one primary mission. Everything stays on your Brain."
              cta="Begin"
              onCta={startDump}
            />
          )}

          {step === "dump" && (
            <>
              <Ceremony
                eyebrow="Step 1 · Brain dump"
                title="Empty it out"
                body="List aspirations, projects, worries, dreams — one per line. No order needed."
              />
              <textarea
                value={dump}
                onChange={(e) => setDump(e.target.value)}
                rows={10}
                placeholder={"Ship the product launch\nGet stronger\nWrite the book\nFamily trip to Japan"}
                className="glass mt-6 w-full resize-none rounded-2xl px-4 py-3 text-base text-ink placeholder:text-ink-dim focus:outline-none focus:ring-1 focus:ring-amber-glow/50"
              />
              {error && <p className="mt-3 text-sm text-amber-soft">{error}</p>}
              <PrimaryButton onClick={goPrioritise}>Continue</PrimaryButton>
            </>
          )}

          {step === "prioritise" && (
            <>
              <Ceremony
                eyebrow="Step 2 · Prioritise"
                title="What belongs on the board?"
                body="Tap the ones that matter this season. The rest become quiet dreams."
              />
              <div className="mt-6 flex flex-wrap gap-2">
                {candidates.map((c) => {
                  const on = selected.has(c.title);
                  return (
                    <button
                      key={c.title}
                      type="button"
                      onClick={() => toggle(c.title)}
                      className={`rounded-full border px-3.5 py-2 text-sm transition ${
                        on
                          ? "border-amber-glow/50 bg-amber-muted text-amber-bright"
                          : "border-white/10 bg-white/[0.03] text-ink-muted"
                      }`}
                    >
                      {c.title}
                    </button>
                  );
                })}
              </div>
              {error && <p className="mt-3 text-sm text-amber-soft">{error}</p>}
              <PrimaryButton onClick={goCrown}>Continue</PrimaryButton>
            </>
          )}

          {step === "crown" && (
            <>
              <Ceremony
                eyebrow="Step 3 · Crown"
                title="Which is primary?"
                body="One mission leads. Supporting work and dreams stay close — but this is the north star."
              />
              <div className="mt-6 space-y-2">
                {selectedList.map((c) => (
                  <button
                    key={c.title}
                    type="button"
                    onClick={() => setPrimaryTitle(c.title)}
                    className={`glass w-full rounded-2xl px-4 py-4 text-left transition ${
                      primaryTitle === c.title
                        ? "ring-1 ring-amber-glow/60 shadow-amber-sm"
                        : "hover:bg-glass-hover"
                    }`}
                  >
                    <p className="font-display text-lg font-semibold text-ink">
                      {c.title}
                    </p>
                    {primaryTitle === c.title && (
                      <p className="mt-1 text-xs uppercase tracking-wider text-amber-soft">
                        Primary
                      </p>
                    )}
                  </button>
                ))}
              </div>
              {error && <p className="mt-3 text-sm text-amber-soft">{error}</p>}
              <PrimaryButton onClick={() => void commit()} disabled={busy || !primaryTitle}>
                {busy ? "Writing to Brain…" : "Set primary mission"}
              </PrimaryButton>
            </>
          )}

          {step === "done" && (
            <Ceremony
              eyebrow="Ready"
              title="Primary is set — go live it"
              body={`“${primaryTitle}” is your north star. Supporting work and dreams stay close on Stillpoint.`}
              cta="Open Stillpoint"
              onCta={() => navigate("/")}
            />
          )}
        </motion.div>
      </AnimatePresence>
    </div>
  );
}

function Ceremony({
  eyebrow,
  title,
  body,
  cta,
  onCta,
}: {
  eyebrow: string;
  title: string;
  body: string;
  cta?: string;
  onCta?: () => void;
}) {
  return (
    <div>
      <p className="text-[11px] font-semibold uppercase tracking-[0.18em] text-amber-soft">
        {eyebrow}
      </p>
      <h1 className="mt-3 font-display text-3xl font-semibold leading-tight text-ink sm:text-4xl">
        {title}
      </h1>
      <p className="mt-4 text-base leading-relaxed text-ink-muted">{body}</p>
      {cta && onCta && <PrimaryButton onClick={onCta}>{cta}</PrimaryButton>}
    </div>
  );
}

function PrimaryButton({
  children,
  onClick,
  disabled,
}: {
  children: ReactNode;
  onClick: () => void;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className="mt-8 w-full rounded-full bg-accent py-3.5 text-sm font-semibold text-[var(--on-accent)] transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-50"
    >
      {children}
    </button>
  );
}
