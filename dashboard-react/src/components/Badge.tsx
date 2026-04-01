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
    STOP: { l: 'STOP', v: 'red' }, REDUCE_BID: { l: 'REDUCE BID', v: 'red' }, NEGATE: { l: 'NEGATE', v: 'red' },
    BOOST: { l: 'SCALE', v: 'green' }, SCALE_UP: { l: 'SCALE UP', v: 'green' },
    PROMOTE_TO_EXACT: { l: 'PROMOTE', v: 'blue' }, START: { l: 'NEW', v: 'purple' },
    FIX_HERO: { l: 'FIX HERO', v: 'amber' }, SWITCH_HERO: { l: 'SWITCH HERO', v: 'amber' },
  };
  const m = META[action] || { l: action || '?', v: 'muted' };
  return <Badge variant={m.v}>{m.l}</Badge>;
}
