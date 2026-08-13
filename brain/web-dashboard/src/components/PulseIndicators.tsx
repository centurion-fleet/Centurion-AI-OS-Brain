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
        <span
          className={connected ? "live-dot" : "live-dot live-dot-off"}
          aria-hidden
        />
        {label || (connected ? "Live" : "Reconnecting")}
      </span>
      {loading && <span className="animate-pulse-soft">Syncing…</span>}
    </div>
  );
}
