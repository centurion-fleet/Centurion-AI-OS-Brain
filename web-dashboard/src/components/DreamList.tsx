import { motion } from "framer-motion";
import type { Dream } from "../types/life";

interface DreamListProps {
  dreams: Dream[];
  onPromote?: (id: string) => void;
}

export function DreamList({ dreams, onPromote }: DreamListProps) {
  if (!dreams.length) return null;

  return (
    <section className="mt-8">
      <h2 className="mb-3 px-1 text-[11px] font-semibold uppercase tracking-[0.16em] text-ink-dim">
        Dreams
      </h2>
      <div className="glass flex flex-wrap gap-2 rounded-2xl p-3 sm:p-4">
        {dreams.map((d, i) => (
          <motion.button
            key={d.id}
            type="button"
            onClick={() => onPromote?.(d.id)}
            initial={{ opacity: 0, scale: 0.92 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{
              type: "spring",
              stiffness: 220,
              damping: 20,
              delay: i * 0.03,
            }}
            whileHover={{ scale: 1.04 }}
            whileTap={{ scale: 0.97 }}
            className="rounded-full border border-white/10 bg-white/[0.03] px-3.5 py-1.5 text-sm text-ink-muted transition-colors hover:border-amber-glow/40 hover:text-amber-soft"
            title={d.description || "Dream — click to promote"}
          >
            {d.title}
          </motion.button>
        ))}
      </div>
    </section>
  );
}
