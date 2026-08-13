import type { Dream } from "../types/life";

interface DreamListProps {
  dreams: Dream[];
  onPromote?: (id: string) => void;
}

export function DreamList({ dreams, onPromote }: DreamListProps) {
  if (!dreams.length) return null;

  return (
    <section className="mt-12">
      <h2 className="mb-3 px-1 text-[11px] font-semibold uppercase tracking-[0.16em] text-ink-dim">
        Dreams
      </h2>
      <div className="surface flex flex-wrap gap-2 rounded-2xl p-3 sm:p-4">
        {dreams.map((d) => (
          <button
            key={d.id}
            type="button"
            onClick={() => onPromote?.(d.id)}
            className="rounded-full border border-white/10 bg-white/[0.02] px-3.5 py-1.5 text-sm text-ink-muted transition-colors hover:border-amber-glow/40 hover:text-amber-soft"
            title={d.description || "Dream — click to promote"}
          >
            {d.title}
          </button>
        ))}
      </div>
    </section>
  );
}
