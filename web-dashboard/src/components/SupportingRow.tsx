import { motion } from "framer-motion";
import type { Mission } from "../types/life";
import { missionProgress } from "../types/life";
import { ProgressBar } from "./PrimaryCard";

interface SupportingRowProps {
  missions: Mission[];
  onOpen: (id: string) => void;
  onMakePrimary?: (id: string) => void;
}

export function SupportingRow({
  missions,
  onOpen,
  onMakePrimary,
}: SupportingRowProps) {
  if (!missions.length) return null;

  return (
    <section className="mt-8">
      <h2 className="mb-3 px-1 text-[11px] font-semibold uppercase tracking-[0.16em] text-ink-dim">
        Supporting
      </h2>
      <div className="hide-scrollbar -mx-4 flex gap-3 overflow-x-auto px-4 pb-2 sm:-mx-6 sm:px-6">
        {missions.map((m, i) => {
          const progress = missionProgress(m);
          return (
            <motion.div
              key={m.id}
              initial={{ opacity: 0, x: 24 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{
                type: "spring",
                stiffness: 180,
                damping: 22,
                delay: i * 0.05,
              }}
              whileHover={{ y: -4 }}
              className="glass min-w-[220px] max-w-[260px] shrink-0 rounded-2xl p-4 text-left shadow-glass transition-colors hover:bg-glass-hover sm:min-w-[240px]"
            >
              <button
                type="button"
                onClick={() => onOpen(m.id)}
                className="w-full text-left"
              >
                <p className="line-clamp-2 font-display text-lg font-semibold leading-snug text-ink">
                  {m.title || "Untitled"}
                </p>
                <p className="mt-2 line-clamp-2 text-xs text-ink-dim">
                  {m.statement || m.purpose || "Supporting mission"}
                </p>
                <div className="mt-4">
                  <div className="mb-1.5 flex justify-between text-[11px] text-ink-dim">
                    <span>
                      {m.completed_target_count}/{m.target_count}
                    </span>
                    <span className="text-amber-soft">{progress}%</span>
                  </div>
                  <ProgressBar value={progress} height="h-1.5" />
                </div>
              </button>
              {onMakePrimary && (
                <button
                  type="button"
                  onClick={(e) => {
                    e.stopPropagation();
                    onMakePrimary(m.id);
                  }}
                  className="mt-3 w-full rounded-full border border-amber-glow/35 bg-amber-muted/60 px-3 py-1.5 text-[11px] font-semibold text-amber-bright transition hover:bg-amber-glow/25"
                >
                  Set as Primary
                </button>
              )}
            </motion.div>
          );
        })}
      </div>
    </section>
  );
}
