import { AnimatePresence, motion } from "framer-motion";
import type { Thought, ThoughtActivityType } from "../types/life";

const ICONS: Record<ThoughtActivityType | "default", string> = {
  thought: "🧠",
  tool_start: "📝",
  tool_result: "📄",
  target_update: "🎉",
  artifact: "📄",
  decision: "🗣️",
  handoff: "🗣️",
  default: "📝",
};

function iconFor(type: string): string {
  return ICONS[type as ThoughtActivityType] || ICONS.default;
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

  return (
    <section className="mt-8">
      <h2 className="mb-3 px-1 text-[11px] font-semibold uppercase tracking-[0.16em] text-ink-dim">
        {title}
      </h2>
      <div className="glass overflow-hidden rounded-2xl">
        {items.length === 0 ? (
          <p className="px-4 py-8 text-center text-sm text-ink-dim">
            Quiet for now — complete a target or Focus in Chat to light this up.
          </p>
        ) : (
          <ul className="divide-y divide-white/5">
            <AnimatePresence initial={false}>
              {items.map((t) => (
                <motion.li
                  key={t.id}
                  layout
                  initial={{ opacity: 0, height: 0 }}
                  animate={{ opacity: 1, height: "auto" }}
                  exit={{ opacity: 0 }}
                  transition={{ type: "spring", stiffness: 200, damping: 24 }}
                  className="flex gap-3 px-4 py-3"
                >
                  <span className="mt-0.5 text-base leading-none" aria-hidden>
                    {iconFor(t.activity_type)}
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
              ))}
            </AnimatePresence>
          </ul>
        )}
      </div>
    </section>
  );
}
