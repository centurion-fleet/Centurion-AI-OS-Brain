import { motion } from "framer-motion";

interface PulseIndicatorsProps {
  connected: boolean;
  loading?: boolean;
  label?: string;
}

export function PulseIndicators({
  connected,
  loading,
  label,
}: PulseIndicatorsProps) {
  return (
    <div className="flex items-center gap-3 text-xs text-ink-dim">
      <span className="inline-flex items-center gap-1.5">
        <motion.span
          className={`h-1.5 w-1.5 rounded-full ${
            connected ? "bg-amber-glow shadow-amber-sm" : "bg-white/25"
          }`}
          animate={
            connected
              ? { scale: [1, 1.35, 1], opacity: [0.7, 1, 0.7] }
              : { scale: 1, opacity: 0.4 }
          }
          transition={{ duration: 2.2, repeat: Infinity, ease: "easeInOut" }}
        />
        {label || (connected ? "Live" : "Reconnecting")}
      </span>
      {loading && <span className="animate-pulse-soft">Syncing…</span>}
    </div>
  );
}
