import { AnimatePresence, m as motion, useReducedMotion } from "framer-motion";
import type { Thought, ThoughtActivityType } from "../types/life";

const MARKS: Record<ThoughtActivityType | "default", string> = {
  thought: "·",
  tool_start: "›",
  tool_result: "›",
  target_update: "◆",
  artifact: "◇",
  decision: "○",
  handoff: "→",
  default: "·",
};

function markFor(type: string): string {
  return MARKS[type as ThoughtActivityType] || MARKS.default;
}

function timeLabel(iso?: string): string {
  if (!iso) return "";
  try {
    const d = new Date(iso);
    return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  } catch {
    return "";
  }
}

interface ActivityFeedProps {
  thoughts: Thought[];
  title?: string;
  max?: number;
}

export function ActivityFeed({
  thoughts,
  title = "Activity",
  max = 24,
}: ActivityFeedProps) {
  const items = thoughts.slice(0, max);
  const newestId = items[0]?.id;
  const reduce = useReducedMotion();

  return (
    <section className="mt-12">
      <h2 className="mb-3 px-1 text-[11px] font-semibold uppercase tracking-[0.16em] text-ink-dim">
        {title}
      </h2>
      <div className="surface overflow-hidden rounded-2xl">
        {items.length === 0 ? (
          <p className="px-4 py-8 text-center text-sm text-ink-dim">
            Quiet for now — complete a target or talk in Chat to light this up.
          </p>
        ) : (
          <ul className="divide-y divide-white/5">
            <AnimatePresence initial={false}>
              {items.map((t) => {
                const isNewest = t.id === newestId && !reduce;
                return (
                  <motion.li
                    key={t.id}
                    initial={isNewest ? { opacity: 0 } : false}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    transition={
                      isNewest ? { duration: 0.28, ease: "easeOut" } : { duration: 0 }
                    }
                    className="flex gap-3 px-4 py-3"
                  >
                    <span
                      className="mt-0.5 w-4 shrink-0 text-center text-sm text-amber-soft"
                      aria-hidden
                    >
                      {markFor(t.activity_type)}
                    </span>
                    <div className="min-w-0 flex-1">
                      <p className="text-sm leading-snug text-ink">{t.summary}</p>
                      {t.detail && (
                        <p className="mt-0.5 line-clamp-2 text-xs text-ink-dim">
                          {t.detail}
                        </p>
                      )}
                    </div>
                    <time className="shrink-0 text-[11px] text-ink-dim">
                      {timeLabel(t.created_at)}
                    </time>
                  </motion.li>
                );
              })}
            </AnimatePresence>
          </ul>
        )}
      </div>
    </section>
  );
}
