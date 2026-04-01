export function Card({ children, className = '', onClick }: {
  children: React.ReactNode;
  className?: string;
  onClick?: () => void;
}) {
  return (
    <div
      onClick={onClick}
      className={`bg-card border border-border rounded-lg p-5 transition-all duration-200 backdrop-blur-xl hover:border-border-strong hover:shadow-card card-lift ${onClick ? 'cursor-pointer' : ''} ${className}`}
    >
      {children}
    </div>
  );
}

import { Tip, MEASURE_TIPS } from './Tooltip';

export function KpiCard({ label, value, delta, note, tip, accent }: {
  label: string;
  value: string;
  delta?: number | null;
  note?: string;
  tip?: string;
  accent?: 'emerald' | 'blue';
}) {
  const dc = delta == null ? null : delta > 0 ? 'up' : delta < 0 ? 'down' : 'flat';
  const dcl = dc === 'up'
    ? 'bg-emerald-500/12 text-emerald-400'
    : dc === 'down'
    ? 'bg-amber-500/12 text-amber-400'
    : 'bg-zinc-700/30 text-zinc-400';

  const tipText = tip || MEASURE_TIPS[label.toLowerCase().replace(/\s+/g, '_')] || '';
  const isWarning = note && (note.includes('break-even') || note.includes('outpacing') || note.includes('Below'));
  const accentCls = accent === 'emerald' ? 'border-l-emerald-500/50' : accent === 'blue' ? 'border-l-blue-500/50' : '';

  return (
    <Card className={accent ? `!border-l-2 ${accentCls}` : ''}>
      <div className="text-[11px] font-medium text-subtle uppercase tracking-wider mb-1.5">
        {tipText ? <Tip text={tipText}>{label} <span className="text-zinc-600 text-[9px]">ⓘ</span></Tip> : label}
      </div>
      <div className="font-mono text-[26px] font-bold tracking-tight leading-none">{value}</div>
      {dc && (
        <div className={`inline-flex items-center gap-1 font-mono text-[11px] font-semibold px-1.5 py-0.5 rounded-md mt-1.5 ${dcl}`}>
          {delta! > 0 ? '↑' : '↓'} {delta! > 0 ? '+' : ''}{delta?.toFixed(1)}%
        </div>
      )}
      {note && (
        <div className={`mt-1.5 leading-snug ${isWarning ? 'inline-flex items-center gap-1 px-2 py-1 rounded-lg bg-amber-500/15 text-amber-400/90 text-[11px] font-medium' : 'text-[11px] text-subtle'}`}>
          {isWarning && <span aria-hidden>⚠</span>}
          {note}
        </div>
      )}
    </Card>
  );
}
