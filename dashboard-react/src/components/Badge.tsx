const COLORS: Record<string, string> = {
  red:    'bg-red-500/12 text-red-400',
  green:  'bg-emerald-500/12 text-emerald-400',
  amber:  'bg-amber-500/12 text-amber-400',
  blue:   'bg-blue-500/12 text-blue-400',
  purple: 'bg-purple-500/12 text-purple-400',
  cyan:   'bg-cyan-500/12 text-cyan-400',
  muted:  'bg-zinc-700/30 text-zinc-400',
};

export function Badge({ children, variant = 'muted', className = '' }: {
  children: React.ReactNode;
  variant?: string;
  className?: string;
}) {
  return (
    <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-[10px] font-semibold tracking-wide whitespace-nowrap ${COLORS[variant] || COLORS.muted} ${className}`}>
      {children}
    </span>
  );
}

export function RoasBadge({ value }: { value: number | null | undefined }) {
  if (value == null) return <Badge variant="muted">--</Badge>;
  const v = value >= 2 ? 'green' : value >= 1 ? 'amber' : 'red';
  return <Badge variant={v}>{value.toFixed(2)}x</Badge>;
}

export function ActionBadge({ action }: { action: string }) {
  const META: Record<string, { l: string; v: string }> = {
    STOP_TERM: { l: 'STOP', v: 'red' }, STOP_TARGET: { l: 'STOP TARGET', v: 'red' }, STOP_SEASONAL: { l: 'STOP SEASONAL', v: 'red' },
    NEGATE_TERM: { l: 'NEGATE', v: 'red' }, NEGATE_BOOST_SIMILAR_EXACT: { l: 'NEGATE BOOST', v: 'red' },
    REDUCE_BID: { l: 'REDUCE BID', v: 'red' }, RESTORE_PRE_PEAK: { l: 'RESTORE', v: 'red' },
    REDUCE_TO_BASELINE: { l: 'REDUCE', v: 'amber' }, COOLDOWN_MONITOR: { l: 'HOLD', v: 'muted' },
    INCREASE_BID: { l: 'INCREASE BID', v: 'green' }, KEEP_TARGET: { l: 'KEEP', v: 'green' },
    PROMOTE_TO_EXACT: { l: 'PROMOTE', v: 'blue' }, START_TERM: { l: 'NEW', v: 'purple' },
    FIX_HERO: { l: 'FIX HERO', v: 'amber' }, SWITCH_HERO: { l: 'SWITCH HERO', v: 'amber' },
    MONITOR_TARGET: { l: 'MONITOR', v: 'muted' },
    GUARDIAN_BUDGET_INCREASE: { l: 'BUDGET ↑', v: 'green' }, GUARDIAN_BUDGET_DECREASE: { l: 'BUDGET ↓', v: 'red' },
    BLITZ_BUDGET_INCREASE: { l: 'BLITZ ↑', v: 'green' }, BLITZ_BUDGET_DECREASE: { l: 'BLITZ ↓', v: 'amber' },
    BUDGET_OK: { l: 'BUDGET OK', v: 'muted' },
    // Legacy
    STOP: { l: 'STOP', v: 'red' }, NEGATE: { l: 'NEGATE', v: 'red' },
    BOOST: { l: 'SCALE', v: 'green' }, SCALE_UP: { l: 'SCALE UP', v: 'green' },
    KEEP: { l: 'KEEP', v: 'green' }, MONITOR: { l: 'MONITOR', v: 'muted' },
    START: { l: 'NEW', v: 'purple' },
  };
  const m = META[action] || { l: action || '?', v: 'muted' };
  return <Badge variant={m.v}>{m.l}</Badge>;
}
