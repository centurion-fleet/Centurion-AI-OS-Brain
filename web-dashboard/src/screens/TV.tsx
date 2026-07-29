import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { useMissionStack } from "../hooks/useLife";
import { useSSE } from "../hooks/useSSE";
import { useDeckVisible } from "../hooks/useDeckVisible";
import { missionProgress } from "../types/life";
import { ProgressBar } from "../components/PrimaryCard";

type Slide = "progress" | "wins" | "thoughts";

const SLIDES: Slide[] = ["progress", "wins", "thoughts"];
const INTERVAL_MS = 8000;

export function TV() {
  const deckVisible = useDeckVisible();
  const { stack } = useMissionStack(20_000, deckVisible);
  const { thoughts, connected } = useSSE({ enabled: deckVisible });
  const [index, setIndex] = useState(0);

  useEffect(() => {
    if (!deckVisible) return;
    const id = setInterval(
      () => setIndex((i) => (i + 1) % SLIDES.length),
      INTERVAL_MS,
    );
    return () => clearInterval(id);
  }, [deckVisible]);

  const primary = stack?.primary;
  const progress = missionProgress(primary);
  const wins = useMemo(
    () =>
      thoughts.filter(
        (t) =>
          t.activity_type === "target_update" ||
          t.activity_type === "artifact" ||
          /complete|done|ship|win/i.test(t.summary),
      ),
    [thoughts],
  );

  const slide = SLIDES[index];

  return (
    <div className="relative flex min-h-screen flex-col overflow-hidden bg-canvas">
      <div className="pointer-events-none absolute inset-0 bg-horizon opacity-90" />

      <div className="relative z-10 flex items-center justify-between px-6 py-4 sm:px-10">
        <p className="text-[11px] font-semibold uppercase tracking-[0.2em] text-amber-soft/80">
          Centurion · TV Mode
        </p>
        <div className="flex items-center gap-4">
          <span
            className={`h-2 w-2 rounded-full ${connected ? "bg-amber-glow shadow-amber-sm" : "bg-white/20"}`}
          />
          <Link
            to="/"
            className="text-sm text-ink-dim transition hover:text-ink"
          >
            Exit
          </Link>
        </div>
      </div>

      <div className="relative z-10 flex flex-1 items-center justify-center px-6 pb-16 sm:px-12">
        <AnimatePresence mode="wait">
          <motion.div
            key={slide}
            initial={{ opacity: 0, y: 28, scale: 0.98 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -20, scale: 0.98 }}
            transition={{ type: "spring", stiffness: 100, damping: 20 }}
            className="w-full max-w-4xl"
          >
            {slide === "progress" && (
              <div className="text-center">
                <p className="text-sm uppercase tracking-[0.2em] text-ink-dim">
                  Primary progress
                </p>
                <h1 className="mt-4 font-display text-4xl font-semibold leading-tight text-ink sm:text-6xl md:text-7xl">
                  {primary?.title || "No primary mission"}
                </h1>
                <p className="mx-auto mt-6 max-w-2xl text-lg text-ink-muted sm:text-xl">
                  {primary?.statement || primary?.purpose || "Crown a mission to fill this wall."}
                </p>
                <div className="mx-auto mt-12 max-w-xl">
                  <p className="mb-4 font-display text-5xl font-semibold text-amber-glow sm:text-6xl">
                    {progress}%
                  </p>
                  <ProgressBar value={progress} height="h-3" />
                  <p className="mt-3 text-sm text-ink-dim">
                    {primary
                      ? `${primary.completed_target_count} of ${primary.target_count} targets`
                      : "—"}
                  </p>
                </div>
              </div>
            )}

            {slide === "wins" && (
              <div className="text-center">
                <p className="text-sm uppercase tracking-[0.2em] text-ink-dim">
                  Recent wins
                </p>
                <ul className="mx-auto mt-10 max-w-2xl space-y-5 text-left">
                  {(wins.length ? wins : thoughts).slice(0, 4).map((t) => (
                    <li
                      key={t.id}
                      className="glass rounded-2xl px-5 py-4 text-lg text-ink sm:text-xl"
                    >
                      <span className="mr-2" aria-hidden>
                        🎉
                      </span>
                      {t.summary}
                    </li>
                  ))}
                  {!wins.length && !thoughts.length && (
                    <li className="text-center text-ink-dim">
                      Wins will glow here as targets complete.
                    </li>
                  )}
                </ul>
              </div>
            )}

            {slide === "thoughts" && (
              <div className="text-center">
                <p className="text-sm uppercase tracking-[0.2em] text-ink-dim">
                  Thought stream
                </p>
                <div className="mx-auto mt-10 max-w-2xl space-y-4">
                  {thoughts.slice(0, 5).map((t) => (
                    <p
                      key={t.id}
                      className="font-display text-xl leading-relaxed text-ink sm:text-2xl"
                    >
                      “{t.summary}”
                    </p>
                  ))}
                  {!thoughts.length && (
                    <p className="text-ink-dim">Listening for the next thought…</p>
                  )}
                </div>
              </div>
            )}
          </motion.div>
        </AnimatePresence>
      </div>

      <div className="relative z-10 flex justify-center gap-2 pb-8">
        {SLIDES.map((s, i) => (
          <button
            key={s}
            type="button"
            aria-label={s}
            onClick={() => setIndex(i)}
            className={`h-1.5 rounded-full transition-all ${
              i === index ? "w-8 bg-amber-glow" : "w-1.5 bg-white/20"
            }`}
          />
        ))}
      </div>
    </div>
  );
}
