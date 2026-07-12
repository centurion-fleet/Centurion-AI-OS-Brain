/* ------------------------------------------------------------------ */
/*  Constellation hero — attention-weighted Swarm orbs for /mission    */
/* ------------------------------------------------------------------ */

import { useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { cn } from '@/lib/utils'
import type { SwarmSummary, SwarmPulse } from './types'

const PULSE_LABELS: Record<SwarmPulse, string> = {
  idle: 'Working smoothly',
  active: 'In progress',
  attention: 'Needs your choice',
  waiting: 'Waiting for you',
  blocked: 'Paused',
  complete: 'Finished for you',
  forming: 'Starting up',
}

function orbSize(rank: number, pulse: SwarmPulse): number {
  const base = rank === 0 ? 108 : rank === 1 ? 88 : 76
  return pulse === 'waiting' || pulse === 'attention' ? base + 8 : base
}

function SwarmOrbGraphic({
  swarm,
  size,
  showLabel = true,
}: {
  swarm: SwarmSummary
  size: number
  showLabel?: boolean
}) {
  const core = size * 0.18
  const halo = size * 0.92
  const pulseClass = `swarm-orb-pulse-${swarm.pulse}`

  return (
    <div className="flex flex-col items-center gap-2" style={{ width: size + 40 }}>
      <div
        className={cn('relative flex items-center justify-center', pulseClass)}
        style={{ width: size, height: size }}
        aria-label={`${swarm.display_name}. ${PULSE_LABELS[swarm.pulse]}`}
      >
        <span
          className="absolute rounded-full border border-[var(--centurion-gold)]/30"
          style={{ width: halo, height: halo }}
        />
        <span
          className="absolute rounded-full bg-[var(--centurion-gold)]/15"
          style={{ width: size * 0.36, height: size * 0.36 }}
        />
        <span
          className="absolute rounded-full bg-[var(--centurion-gold)] shadow-[0_0_12px_color-mix(in_srgb,var(--centurion-gold)_45%,transparent)]"
          style={{ width: core, height: core, opacity: swarm.pulse === 'complete' ? 0.35 : 0.85 }}
        />
        {swarm.participants
          .filter((p) => p.kind === 'centurion')
          .slice(0, 4)
          .map((p, i) => {
            const angle = (i / Math.max(1, swarm.participants.length)) * Math.PI * 2
            const orbit = size * 0.34
            return (
              <span
                key={p.id}
                className={cn(
                  'absolute rounded-full',
                  p.is_active ? 'bg-[var(--centurion-gold)]' : 'bg-[var(--centurion-gold)]/35',
                )}
                style={{
                  width: p.is_active ? 10 : 7,
                  height: p.is_active ? 10 : 7,
                  transform: `translate(${Math.cos(angle) * orbit}px, ${Math.sin(angle) * orbit}px)`,
                }}
              />
            )
          })}
      </div>
      {showLabel && (
        <>
          <p className="text-sm font-semibold text-foreground truncate max-w-full">{swarm.display_name}</p>
          <p className="text-xs text-muted-foreground truncate max-w-full">{PULSE_LABELS[swarm.pulse]}</p>
        </>
      )}
    </div>
  )
}

export function SwarmConstellationHero({
  swarms,
  onShowAll,
}: {
  swarms: SwarmSummary[]
  onShowAll?: () => void
}) {
  const navigate = useNavigate()
  const maxVisible = 3

  const visible = useMemo(
    () =>
      [...swarms]
        .sort((a, b) => (b.attention_score ?? 0) - (a.attention_score ?? 0))
        .slice(0, maxVisible),
    [swarms],
  )

  const overflow = Math.max(0, swarms.length - maxVisible)

  if (visible.length === 0) return null

  return (
    <div className="rounded-lg border border-border bg-card/80 p-4">
      <div className="flex items-center justify-between mb-3">
        <p className="text-sm font-semibold text-muted-foreground">Your collaborations</p>
        {(overflow > 0 || swarms.length > 1) && onShowAll && (
          <button
            type="button"
            onClick={onShowAll}
            className="text-xs font-medium text-[var(--centurion-gold)] hover:underline"
          >
            See all
          </button>
        )}
      </div>
      <div className="flex items-end justify-center gap-4 flex-wrap">
        {visible.map((swarm, index) => (
          <button
            key={swarm.id}
            type="button"
            className="cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--centurion-gold)] rounded-lg"
            onClick={() => navigate(`/mission/${swarm.id}`)}
          >
            <SwarmOrbGraphic swarm={swarm} size={orbSize(index, swarm.pulse)} />
          </button>
        ))}
        {overflow > 0 && onShowAll && (
          <button
            type="button"
            onClick={onShowAll}
            className="flex h-[52px] w-[52px] items-center justify-center rounded-full bg-[var(--centurion-gold)]/12 text-sm font-semibold text-[var(--centurion-gold)]"
            aria-label={`${overflow} more collaborations`}
          >
            +{overflow}
          </button>
        )}
      </div>
    </div>
  )
}

export { SwarmOrbGraphic, PULSE_LABELS }
