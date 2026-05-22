/**
 * DashboardSummary — Premium dashboard hero section
 *
 * Row 1: Dynamic Hero card (left ~22%) + Measure Trend dual-line chart (right ~78%)
 * Row 2: 5 compact KPI pill-cards — click to select as hero
 * Row 3: Summary info bar
 */
import { useState, useRef, useEffect } from 'react';
import { SparklineCanvas } from './SparklineCanvas';

/* ── Design tokens ─────────────────────────────────────────────────────────── */
const GLASS = {
  background: 'var(--color-card)',
  border: '1px solid var(--color-border)',
  backdropFilter: 'blur(16px)',
  WebkitBackdropFilter: 'blur(16px)',
  borderRadius: 10,
  boxShadow: 'var(--shadow-card)',
} as const;

const METRIC_KEYS = ['sales', 'ad_cost', 'profit', 'roas', 'organic'] as const;
type MetricKey = typeof METRIC_KEYS[number];

const METRIC: Record<MetricKey, { color: string; glow: string }> = {
  sales:   { color: '#60a5fa', glow: 'rgba(96,165,250,0.15)' },
  ad_cost: { color: '#fb923c', glow: 'rgba(251,146,60,0.15)' },
  profit:  { color: '#34d399', glow: 'rgba(52,211,153,0.15)' },
  roas:    { color: '#a78bfa', glow: 'rgba(167,139,250,0.15)' },
  organic: { color: '#2dd4bf', glow: 'rgba(45,212,191,0.15)' },
};

/* ── fmt helper ── */
const fmtVal = (n: number, isPercent?: boolean, isRatio?: boolean) => {
  if (isPercent) return `${n.toFixed(1)}%`;
  if (isRatio) return `${n.toFixed(2)}x`;
  const abs = Math.abs(n);
  if (abs >= 1000) return `${n < 0 ? '-' : ''}$${(abs / 1000).toFixed(1)}K`;
  return `${n < 0 ? '-' : ''}$${abs.toFixed(0)}`;
};

/* ── Dual-line Trend chart (TY solid + LY dashed, both hoverable) ── */
function MeasureTrend({ dataTy, dataLy, labels, width, height, color, showValues, isPercent, isRatio }: {
  dataTy: number[]; dataLy: number[]; labels: string[]; width: number; height: number; color: string;
  showValues?: boolean; isPercent?: boolean; isRatio?: boolean;
}) {
  const [hov, setHov] = useState<{ idx: number; line: 'ty' | 'ly' } | null>(null);
  if (!dataTy.length) return <span className="text-zinc-600 text-[10px] font-mono">No data</span>;
  /* Typography scale: Captions/Axis=10px, Labels=12px, Body=14px, Hero=24px */

  const pL = 8, pR = 8, pT = showValues ? 18 : 8, pB = 20;
  const w = width - pL - pR, h = height - pT - pB;

  const cappedLy = dataLy;
  const allVals = [...dataTy, ...cappedLy.filter(v => v !== 0)];
  const dataMin = Math.min(...allVals);
  const dataMax = Math.max(...allVals);
  const padding = (dataMax - dataMin) * 0.15 || Math.abs(dataMax) * 0.15 || 1;
  const mn = dataMin - padding;
  const mx = dataMax + padding;
  const rng = mx - mn || 1;

  const toY = (v: number) => pT + h - ((v - mn) / rng) * h;
  const toX = (i: number, len: number) => pL + (len > 1 ? (i / (len - 1)) * w : 0);

  const buildPath = (data: number[]) => data.map((v, i) => {
    const x = toX(i, data.length), y = toY(v);
    if (i === 0) return `M${x},${y}`;
    const px = toX(i - 1, data.length), py = toY(data[i - 1]);
    const cx = (px + x) / 2;
    return `C${cx},${py} ${cx},${y} ${x},${y}`;
  }).join(' ');

  const tyPath = buildPath(dataTy);
  const hasLy = cappedLy.some(v => v !== 0);
  const lyPath = hasLy ? buildPath(cappedLy) : null;
  const ptsTy = dataTy.map((v, i) => ({ x: toX(i, dataTy.length), y: toY(v), val: v, lbl: labels[i] ?? '' }));
  const ptsLy = hasLy ? cappedLy.map((v, i) => ({ x: toX(i, cappedLy.length), y: toY(v), val: v, lbl: labels[i] ?? '' })) : [];
  const zeroY = dataMin < 0 ? toY(0) : null;

  const hovPt = hov?.line === 'ty' && hov.idx < ptsTy.length ? ptsTy[hov.idx]
              : hov?.line === 'ly' && hov.idx < ptsLy.length ? ptsLy[hov.idx]
              : null;
  const hovIsLy = hov?.line === 'ly';
  const hovOtherVal = hov?.line === 'ty' ? (dataLy[hov.idx] ?? null) : (dataTy[hov?.idx ?? 0] ?? null);
  const TW = 150, TH = 58;
  const tx = hovPt ? Math.max(0, Math.min(hovPt.x - TW / 2, width - TW)) : 0;
  const ty = hovPt ? Math.max(0, hovPt.y - TH - 12) : 0;

  return (
    <svg width={width} height={height} className="block" style={{ overflow: 'visible' }}>
      {zeroY != null && (
        <line x1={pL} y1={zeroY} x2={pL + w} y2={zeroY}
          stroke="rgba(255,255,255,0.06)" strokeWidth={1} strokeDasharray="4 4" />
      )}
      {hovPt && (
        <line x1={hovPt.x} y1={pT} x2={hovPt.x} y2={pT + h}
          stroke={color + '40'} strokeWidth={1} strokeDasharray="2 2" />
      )}
      {lyPath && (
        <>
          <defs>
            <linearGradient id="lyFill" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#fff" stopOpacity={0.03} />
              <stop offset="100%" stopColor="#fff" stopOpacity={0} />
            </linearGradient>
          </defs>
          <path d={`${lyPath} L${toX(cappedLy.length - 1, cappedLy.length)},${toY(mn)} L${toX(0, cappedLy.length)},${toY(mn)} Z`}
            fill="url(#lyFill)" />
          <path d={lyPath} stroke="rgba(255,255,255,0.18)" strokeWidth={1.5} fill="none"
            strokeLinecap="round" strokeDasharray="4 3" />
        </>
      )}
      <defs>
        <linearGradient id="tyFill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity={0.18} />
          <stop offset="100%" stopColor={color} stopOpacity={0.01} />
        </linearGradient>
      </defs>
      <path d={`${tyPath} L${ptsTy[ptsTy.length - 1].x},${toY(mn)} L${ptsTy[0].x},${toY(mn)} Z`}
        fill="url(#tyFill)" />
      <path d={tyPath} stroke={color} strokeWidth={2} fill="none" strokeLinecap="round" />

      {/* Value labels if space allows */}
      {showValues && ptsTy.map((p, i) => (
        <text key={`val-${i}`} x={p.x} y={p.y - 6} textAnchor="middle"
          fill={color + '88'} fontSize={10} fontFamily="'Fira Code',monospace" fontWeight={600}>
          {fmtVal(p.val, isPercent, isRatio)}
        </text>
      ))}

      {/* X-axis period labels — always visible */}
      {ptsTy.map((p, i) => {
        const lbl = p.lbl.replace(/^\d{4}-/, '').replace(/-/g, '/').slice(0, 5);
        return (
          <text key={`x-${i}`} x={p.x} y={pT + h + 13} textAnchor="middle"
            fill="rgba(255,255,255,0.18)" fontSize={10} fontFamily="'Fira Code',monospace">
            {lbl}
          </text>
        );
      })}

      {/* TY interactive points */}
      {ptsTy.map((p, i) => (
        <g key={`ty-${i}`} onMouseEnter={() => setHov({ idx: i, line: 'ty' })} onMouseLeave={() => setHov(null)} className="cursor-pointer">
          <circle cx={p.x} cy={p.y} r={12} fill="transparent" />
          <circle cx={p.x} cy={p.y} r={hov?.line === 'ty' && hov.idx === i ? 4 : 2}
            fill={hov?.line === 'ty' && hov.idx === i ? color : '#0f1520'}
            stroke={color} strokeWidth={1.5}
            style={{ transition: 'all 150ms ease-out', filter: hov?.line === 'ty' && hov.idx === i ? `drop-shadow(0 0 4px ${color}99)` : 'none' }} />
        </g>
      ))}
      {/* LY interactive points */}
      {ptsLy.map((p, i) => (
        <g key={`ly-${i}`} onMouseEnter={() => setHov({ idx: i, line: 'ly' })} onMouseLeave={() => setHov(null)} className="cursor-pointer">
          <circle cx={p.x} cy={p.y} r={12} fill="transparent" />
          <circle cx={p.x} cy={p.y} r={hov?.line === 'ly' && hov.idx === i ? 4 : 1.5}
            fill={hov?.line === 'ly' && hov.idx === i ? 'rgba(255,255,255,0.5)' : 'transparent'}
            stroke="rgba(255,255,255,0.2)" strokeWidth={1}
            style={{ transition: 'all 150ms ease-out' }} />
        </g>
      ))}

      {/* Tooltip */}
      {hovPt && (
        <foreignObject x={tx} y={ty} width={TW} height={TH} style={{ pointerEvents: 'none' }}>
          <div style={{
            background: 'rgba(8,12,30,0.92)',
            backdropFilter: 'blur(12px)',
            WebkitBackdropFilter: 'blur(12px)',
            border: `1px solid ${color}33`,
            borderRadius: 8,
            padding: '5px 8px',
            boxShadow: `0 4px 16px rgba(0,0,0,0.5), 0 0 12px ${color}1a`,
          }}>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 5, marginBottom: 2 }}>
              <span style={{ fontFamily: "'Fira Code',monospace", fontSize: 14, fontWeight: 700, color: hovIsLy ? 'rgba(255,255,255,0.5)' : color, lineHeight: 1 }}>
                {fmtVal(hovPt.val, isPercent, isRatio)}
              </span>
              <span style={{ fontFamily: "'Fira Code',monospace", fontSize: 10, color: 'rgba(255,255,255,0.30)' }}>{hovIsLy ? 'last year' : 'this year'}</span>
            </div>
            {hovOtherVal != null && hovOtherVal !== 0 && (
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 5, marginBottom: 1 }}>
                <span style={{ fontFamily: "'Fira Code',monospace", fontSize: 12, color: hovIsLy ? color : 'rgba(255,255,255,0.35)', lineHeight: 1 }}>
                  {fmtVal(hovOtherVal, isPercent, isRatio)}
                </span>
                <span style={{ fontFamily: "'Fira Code',monospace", fontSize: 10, color: 'rgba(255,255,255,0.20)' }}>{hovIsLy ? 'this year' : 'last year'}</span>
              </div>
            )}
            <div style={{ fontFamily: "'Fira Code',monospace", fontSize: 10, color: 'rgba(255,255,255,0.25)', lineHeight: 1 }}>{hovPt.lbl}</div>
          </div>
        </foreignObject>
      )}
      <g transform={`translate(${width - 110}, 2)`}>
        <line x1={0} y1={4} x2={12} y2={4} stroke={color} strokeWidth={2} />
        <text x={15} y={7} fill="rgba(255,255,255,0.3)" fontSize={9} fontFamily="'Fira Code',monospace">TY</text>
        {hasLy && (
          <>
            <line x1={35} y1={4} x2={47} y2={4} stroke="rgba(255,255,255,0.25)" strokeWidth={1.5} strokeDasharray="4 3" />
            <text x={50} y={7} fill="rgba(255,255,255,0.2)" fontSize={9} fontFamily="'Fira Code',monospace">LY</text>
          </>
        )}
      </g>
    </svg>
  );
}

/* ═══════════════════════════════════════════════════════════════════════════════
   Main Export — DashboardSummary
   ═══════════════════════════════════════════════════════════════════════════════ */
export function DashboardSummary({
  rangeStr, pk, seasonalityLabel, latestPeriodLabel,
  metrics, kpiSparklineData, trendLabels, headline,
  trendContent, onMetricSelect,
}: {
  rangeStr: string;
  pk: { holiday_name?: string; days_until_peak_start?: number } | null;
  seasonalityLabel: string | null;
  latestPeriodLabel: string;
  metrics: Array<{ label: string; value: string; prevValue?: string; lyValue?: string; delta: string; positive: boolean; warn?: string; sub?: string }>;
  kpiSparklineData: Record<string, number[]>;
  trendLabels: string[];
  headline?: string;
  /** Render slot for the trend chart (right 78% of hero row) */
  trendContent?: React.ReactNode;
  /** Called when a KPI card is clicked — passes the metric key */
  onMetricSelect?: (key: string) => void;
}) {
  const rootRef = useRef<HTMLDivElement>(null);
  const [dims, setDims] = useState({ w: 0, h: 0 });
  const [selected, setSelected] = useState<MetricKey>('profit');

  useEffect(() => {
    const obs = new ResizeObserver(([e]) => setDims({ w: e.contentRect.width, h: e.contentRect.height }));
    if (rootRef.current) obs.observe(rootRef.current);
    return () => obs.disconnect();
  }, []);

  const { w, h } = dims;

  const selectedIdx = METRIC_KEYS.indexOf(selected);
  const heroMetric = metrics[selectedIdx] ?? metrics[2];
  const heroColor = METRIC[selected].color;

  const GAP = 6;
  const ROW2_H = 44;
  const ROW1_H = h - ROW2_H - GAP;
  const heroW = Math.floor(w * 0.22);

  return (
    <div ref={rootRef} className="w-full h-full flex flex-col">
      {w > 0 && (
        <>
          {/* ── Row 1: Hero Card + Measure Trend ─── */}
          <div className="flex shrink-0" style={{ height: ROW1_H, gap: GAP }}>
            {/* Hero Card */}
            <div className="flex flex-col justify-center shrink-0 rounded-lg px-3"
              style={{ width: heroW, ...GLASS, borderLeft: `3px solid ${heroMetric?.positive ? heroColor : '#f87171'}` }}>
              <span className="font-mono text-[12px] tracking-[0.15em] uppercase"
                style={{ color: heroColor + 'bb' }}>{heroMetric?.label ?? '--'}</span>
              <span className="font-mono text-[24px] font-bold leading-none tracking-tight"
                style={{ color: 'var(--color-text)', textShadow: `0 0 16px ${heroColor}20` }}>
                {heroMetric?.value ?? '--'}
              </span>
              {heroMetric && (
                <div className="flex items-center gap-1 mt-0.5">
                  <span className="font-mono text-[12px] font-semibold px-1 py-px rounded"
                    style={{ color: heroMetric.positive ? '#34d399' : '#f87171', background: (heroMetric.positive ? '#34d399' : '#f87171') + '12' }}>
                    {heroMetric.positive ? '▲' : '▼'}{heroMetric.delta}
                  </span>
                  {heroMetric.prevValue && (
                    <span className="font-mono text-[12px]" style={{ color: 'var(--color-muted)' }}>prev {heroMetric.prevValue}</span>
                  )}
                </div>
              )}
              {heroMetric?.lyValue && (
                <div className="flex items-center gap-1 mt-0.5">
                  <span className="font-mono text-[12px]" style={{ color: 'var(--color-faint)' }}>LY</span>
                  <span className="font-mono text-[12px] font-medium" style={{ color: 'var(--color-subtle)' }}>{heroMetric.lyValue}</span>
                </div>
              )}
              {heroMetric?.sub && (
                <div className="font-mono text-[10px] mt-0.5 leading-tight line-clamp-2" style={{ color: 'var(--color-faint)' }}>{heroMetric.sub}</div>
              )}
            </div>

            {/* Trend Chart — provided by parent */}
            <div className="flex-1 rounded-lg min-w-0 overflow-hidden flex flex-col" style={GLASS}>
              <div className="flex-1 min-h-0">
                {trendContent}
              </div>
            </div>
          </div>

          {/* ── Row 2: Compact KPI cards ─── */}
          <div className="flex" style={{ height: ROW2_H, gap: GAP, marginTop: GAP }}>
            {metrics.map((m, i) => {
              const key = METRIC_KEYS[i];
              const { color, glow } = METRIC[key];
              const isActive = selected === key;
              const sparkData = kpiSparklineData[key] ?? [];
              const dC = m.positive ? '#34d399' : '#f87171';

              return (
                <div key={key}
                  onClick={() => { setSelected(key); onMetricSelect?.(key); }}
                  className="flex-1 min-w-0 rounded-lg flex items-center gap-1 px-2 cursor-pointer transition-all duration-200"
                  style={{
                    ...GLASS,
                    height: ROW2_H,
                    borderLeft: `2px solid ${isActive ? color : 'var(--color-border-faint)'}`,
                    background: isActive ? `${color}0d` : GLASS.background,
                    boxShadow: isActive ? `0 0 12px ${color}10` : 'none',
                  }}>
                  <div className="flex flex-col min-w-0 shrink-0">
                    <span className="font-mono text-[10px] uppercase tracking-wider leading-none"
                      style={{ color: color + (isActive ? 'ee' : '99') }}>{m.label}</span>
                    <span className="font-mono text-[14px] font-bold leading-none tracking-tight" style={{ color: 'var(--color-text)' }}>{m.value}</span>
                  </div>
                  <span className="font-mono text-[10px] font-semibold px-0.5 rounded shrink-0"
                    style={{ color: dC, background: dC + '0d' }}>
                    {m.positive ? '▲' : '▼'}{m.delta}
                  </span>
                  {sparkData.length > 0 && (
                    <div className="ml-auto opacity-35" style={{ width: 40, height: 14 }}>
                      <SparklineCanvas data={sparkData} color={color} glow={glow}
                        width={40} height={14} padTop={1} padBottom={1} strokeWidth={1} dotRadius={0} />
                    </div>
                  )}
                </div>
              );
            })}
          </div>


        </>
      )}
    </div>
  );
}
