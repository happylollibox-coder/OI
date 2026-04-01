import React from 'react';

/** Single 0-10 arc gauge. value can be null for N/A. */
export function ScoreGauge({
  value,
  color,
  size = 36,
  strokeWidth = 4,
}: {
  value: number | null;
  color: string;
  size?: number;
  strokeWidth?: number;
}) {
  const r = (size - strokeWidth) / 2;
  const cx = size / 2;
  const cy = size / 2;
  const semicircleLen = Math.PI * r;
  const pct = value == null ? 0 : Math.min(10, Math.max(0, value)) / 10;
  const dash = pct * semicircleLen;
  const gap = 999; // avoid repeat

  return (
    <svg width={size} height={size} className="shrink-0">
      {/* background arc (semicircle) */}
      <circle
        cx={cx}
        cy={cy}
        r={r}
        fill="none"
        stroke="rgba(63,63,70,.4)"
        strokeWidth={strokeWidth}
        strokeDasharray={`${semicircleLen} 999`}
        strokeDashoffset={0}
        transform={`rotate(180 ${cx} ${cy})`}
      />
      {/* value arc */}
      {value != null && dash > 0 && (
        <circle
          cx={cx}
          cy={cy}
          r={r}
          fill="none"
          stroke={color}
          strokeWidth={strokeWidth}
          strokeDasharray={`${dash} ${gap}`}
          strokeDashoffset={0}
          transform={`rotate(180 ${cx} ${cy})`}
        />
      )}
    </svg>
  );
}

const COLORS = ['#3b82f6', '#f59e0b', '#10b981'] as const;
const LABELS = ['ROAS', 'WoW', 'YoY'] as const;
const LEGEND = 'ROAS · Profit · Growth';

/** One gauge with 3 concentric arcs (different colors). Center shows average. Each arc has its score. */
export function ScoreGaugesRow({
  score1,
  score2,
  score3,
}: {
  score1: number;
  score2: number | null;
  score3: number;
}) {
  const avg =
    score2 != null
      ? (score1 + score2 + score3) / 3
      : (score1 + score3 * 2) / 3;

  const size = 180;
  const strokeWidth = 10;
  const gap = 5;
  const r1 = (size - strokeWidth) / 2;
  const r2 = r1 - strokeWidth - gap;
  const r3 = r2 - strokeWidth - gap;
  const radii = [r1, r2, r3];
  const scores = [score1, score2 ?? 0, score3];

  const arc = (r: number, pct: number) => {
    const semicircleLen = Math.PI * r;
    const dash = Math.min(1, Math.max(0, pct)) * semicircleLen;
    return { dash, semicircleLen };
  };

  const cx = size / 2;
  const cy = size / 2;

  return (
    <div className="flex flex-col items-center rounded-lg bg-card border border-border backdrop-blur-sm p-5 h-full min-h-0 shrink-0 shadow-lg shadow-black/20">
      <div className="text-[10px] font-semibold uppercase tracking-widest text-zinc-500 mb-2">Score</div>
      <div className="text-[9px] text-zinc-500/80 mb-2">{LEGEND}</div>
      <div className="relative">
        <svg width={size} height={size} className="shrink-0">
          {radii.map((r, i) => {
            const pct = scores[i] / 10;
            const { dash, semicircleLen } = arc(r, pct);
            return (
              <g key={i}>
                <circle cx={cx} cy={cy} r={r} fill="none" stroke="rgba(63,63,70,.35)" strokeWidth={strokeWidth}
                  strokeDasharray={`${semicircleLen} 999`} transform={`rotate(180 ${cx} ${cy})`} />
                {dash > 0 && (
                  <circle cx={cx} cy={cy} r={r} fill="none" stroke={COLORS[i]} strokeWidth={strokeWidth}
                    strokeDasharray={`${dash} 999`} transform={`rotate(180 ${cx} ${cy})`} strokeLinecap="round" />
                )}
              </g>
            );
          })}
          <text x={cx} y={cy} textAnchor="middle" dominantBaseline="central"
            className="font-mono text-4xl font-bold fill-white drop-shadow-sm">
            {avg.toFixed(1)}
          </text>
        </svg>
      </div>
      <div className="flex items-center justify-center gap-3 mt-3 pt-3 border-t border-zinc-700/50 w-full">
        {[0, 1, 2].map((i, idx) => (
          <React.Fragment key={i}>
            {idx > 0 && <span className="text-zinc-600 text-xs">|</span>}
            <div className="flex flex-col items-center gap-0.5">
              <span className="text-[9px] font-medium uppercase tracking-wider text-zinc-500">{LABELS[i]}</span>
              <span className="font-mono text-sm font-bold text-zinc-200">
                {score2 == null && i === 1 ? '—' : scores[i].toFixed(1)}
              </span>
            </div>
          </React.Fragment>
        ))}
      </div>
    </div>
  );
}
