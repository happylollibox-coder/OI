import { useId } from 'react';

/** Sparkline with optional dots, labels, baseline, gradient fill. Values normalized to 0-1 for display. */
export function MiniTrend({
  values,
  color = '#71717a',
  height = 24,
  width = 48,
  showValues = false,
  valueFormat = (v: number) => v.toFixed(1),
  baseline,
}: {
  values: number[];
  color?: string;
  height?: number;
  width?: number;
  showValues?: boolean;
  valueFormat?: (v: number) => string;
  /** Baseline value (e.g. 5 for score target) — draws horizontal reference line */
  baseline?: number;
}) {
  if (!values.length) return null;
  const gradId = useId().replace(/:/g, '');
  const min = Math.min(...values);
  const max = Math.max(...values);
  const range = max - min || 1;
  const labelH = showValues ? 16 : 0;
  const padX = 8;
  const padY = showValues ? 6 + labelH : 6;
  const w = width - padX * 2;
  const h = height - padY * 2 - (showValues ? labelH : 0);
  const step = values.length > 1 ? w / (values.length - 1) : 0;
  const coords = values.map((v, i) => {
    const x = padX + i * step;
    const y = padY + h - ((v - min) / range) * h;
    return { x, y, v };
  });
  const d = `M ${coords.map(c => `${c.x},${c.y}`).join(' L ')}`;
  const dotR = showValues ? 5 : 0;
  const strokeW = 2;
  const fillD = `${d} L ${coords[coords.length - 1].x} ${padY + h} L ${coords[0].x} ${padY + h} Z`;
  const baselineY = baseline != null && range >= 0
    ? padY + h - ((baseline - min) / range) * h
    : null;
  return (
    <svg width={width} height={height} className="shrink-0">
      {/* Gradient fill beneath line */}
      <defs>
        <linearGradient id={gradId} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity={0.25} />
          <stop offset="100%" stopColor={color} stopOpacity={0.02} />
        </linearGradient>
      </defs>
      <path d={fillD} fill={`url(#${gradId})`} />
      {baselineY != null && baselineY >= padY && baselineY <= padY + h && (
        <line x1={padX} y1={baselineY} x2={width - padX} y2={baselineY} stroke="rgba(113,113,122,0.4)" strokeWidth={1} strokeDasharray="4 2" />
      )}
      {baselineY != null && (
        <text x={width - padX - 2} y={baselineY - 4} textAnchor="end" className="text-[9px] fill-zinc-500">Target</text>
      )}
      <path d={d} fill="none" stroke={color} strokeWidth={strokeW} strokeLinecap="round" strokeLinejoin="round" />
      {showValues && coords.map((c, i) => (
        <g key={i}>
          <circle cx={c.x} cy={c.y} r={dotR} fill={color} stroke="rgba(0,0,0,.2)" strokeWidth={1.5} />
          <text x={c.x} y={padY - 4} textAnchor="middle" className="font-mono text-[11px] font-semibold fill-zinc-300">
            {valueFormat(c.v)}
          </text>
        </g>
      ))}
    </svg>
  );
}
