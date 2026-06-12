import { useId } from 'react';

/** Needle gauge 0–10 with gradient arc, tick marks, and hub. Based on score-gauge.jsx */
export function ScoreGaugeNeedle({
  score,
  size = 260,
  subLabel,
}: {
  score: number;
  size?: number;
  subLabel?: string;
}) {
  const max = 10;
  const pct = Math.min(max, Math.max(0, score)) / max;

  const gaugeW = size;
  const svgH = gaugeW * 0.54;
  const cx = gaugeW / 2;
  const cy = svgH + 10;
  const r = gaugeW * 0.38;
  const thick = gaugeW * 0.072;

  function arcD(p: number, radius: number) {
    const start = Math.PI;
    const sweep = Math.PI * p;
    const end = start + sweep;
    const x1 = cx + radius * Math.cos(start);
    const y1 = cy + radius * Math.sin(start);
    const x2 = cx + radius * Math.cos(end);
    const y2 = cy + radius * Math.sin(end);
    return `M${x1},${y1} A${radius},${radius} 0 ${sweep > Math.PI ? 1 : 0},1 ${x2},${y2}`;
  }

  const ticks = Array.from({ length: 11 }, (_, i) => {
    const angle = Math.PI + (Math.PI * i) / 10;
    const inner = r - thick * 0.9;
    const outer = r + thick * 0.9;
    return {
      x1: cx + inner * Math.cos(angle),
      y1: cy + inner * Math.sin(angle),
      x2: cx + outer * Math.cos(angle),
      y2: cy + outer * Math.sin(angle),
      major: i % 5 === 0,
    };
  });

  const id = useId().replace(/:/g, '');
  const needleAngle = Math.PI + Math.PI * pct;
  const needleLen = r + thick * 0.5;
  const nx = cx + needleLen * Math.cos(needleAngle);
  const ny = cy + needleLen * Math.sin(needleAngle);
  const nx2 = cx + needleLen * 0.15 * Math.cos(needleAngle + Math.PI);
  const ny2 = cy + needleLen * 0.15 * Math.sin(needleAngle + Math.PI);

  return (
    <div
      className="flex flex-col items-center"
      style={{
        borderRadius: 20,
        padding: '10px 0 12px',
      }}>
      <div
        className="font-mono text-[10px] tracking-[0.2em] text-faint mb-2"
        style={{ letterSpacing: '0.2em' }}>
        SCORE
      </div>

      <div className="relative overflow-hidden" style={{ width: gaugeW, height: svgH + 2 }}>
        <svg
          width={gaugeW}
          height={cy + thick + 10}
          className="absolute top-0 left-0 overflow-visible">
          <defs>
            <linearGradient id={`arcGrad-${id}`} x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stopColor="#ef4444" />
              <stop offset="40%" stopColor="#f59e0b" />
              <stop offset="75%" stopColor="#34d399" />
              <stop offset="100%" stopColor="#34d399" />
            </linearGradient>
            <filter id={`arcGlow-${id}`}>
              <feGaussianBlur stdDeviation="5" result="blur" />
              <feMerge>
                <feMergeNode in="blur" />
                <feMergeNode in="SourceGraphic" />
              </feMerge>
            </filter>
            <filter id={`needleGlow-${id}`}>
              <feGaussianBlur stdDeviation="3" result="blur" />
              <feMerge>
                <feMergeNode in="blur" />
                <feMergeNode in="SourceGraphic" />
              </feMerge>
            </filter>
            <radialGradient id={`hubGrad-${id}`} cx="50%" cy="50%" r="50%">
              <stop offset="0%" stopColor="#fff" stopOpacity="0.9" />
              <stop offset="100%" stopColor="#aaa" stopOpacity="0.6" />
            </radialGradient>
          </defs>

          <path d={arcD(1, r)} stroke="rgba(255,255,255,0.06)" strokeWidth={thick} fill="none" strokeLinecap="round" />

          {ticks.map((t, i) => (
            <line
              key={i}
              x1={t.x1}
              y1={t.y1}
              x2={t.x2}
              y2={t.y2}
              stroke={t.major ? 'rgba(255,255,255,0.25)' : 'rgba(255,255,255,0.1)'}
              strokeWidth={t.major ? 1.5 : 0.75}
            />
          ))}

          <g filter={`url(#arcGlow-${id})`}>
            <path d={arcD(pct, r)} stroke={`url(#arcGrad-${id})`} strokeWidth={thick} fill="none" strokeLinecap="round" />
          </g>

          <g filter={`url(#needleGlow-${id})`}>
            <line x1={nx2} y1={ny2} x2={nx} y2={ny} stroke="rgba(255,255,255,0.9)" strokeWidth={2} strokeLinecap="round" />
          </g>

          <circle cx={cx} cy={cy} r={thick * 0.35} fill={`url(#hubGrad-${id})`} />
          <circle cx={cx} cy={cy} r={thick * 0.18} fill="#09090b" />

          <text x={cx - r - thick * 0.5} y={cy + 14} fill="rgba(255,255,255,0.25)" fontSize={gaugeW * 0.045} fontFamily="ui-monospace, monospace" textAnchor="middle">
            0
          </text>
          <text x={cx + r + thick * 0.5} y={cy + 14} fill="rgba(255,255,255,0.25)" fontSize={gaugeW * 0.045} fontFamily="ui-monospace, monospace" textAnchor="middle">
            10
          </text>
        </svg>
      </div>

      <div className="-mt-1 text-center px-3">
        <span
          className="font-mono font-bold leading-none transition-colors duration-500"
          style={{
            fontSize: Math.min(72, size * 0.28),
            letterSpacing: '-0.04em',
            color: score >= 7 ? '#34d399' : score >= 5 ? '#4ade80' : score >= 3 ? '#fbbf24' : '#f87171',
            textShadow: `0 0 40px ${score >= 7 ? 'rgba(52,211,153,0.35)' : score >= 5 ? 'rgba(74,222,128,0.3)' : score >= 3 ? 'rgba(251,191,36,0.3)' : 'rgba(248,113,113,0.3)'}, 0 0 80px ${score >= 5 ? 'rgba(52,211,153,0.15)' : 'rgba(248,113,113,0.15)'}`,
          }}>
          {score.toFixed(1)}
        </span>
        <span className="font-mono text-faint ml-1.5 align-middle" style={{ fontSize: Math.min(20, size * 0.08) }}>/10</span>
      </div>

      {subLabel && (
        <div className="font-mono text-[10px] text-faint mt-1.5 px-3" style={{ letterSpacing: '0.1em' }}>
          {subLabel}
        </div>
      )}
    </div>
  );
}
