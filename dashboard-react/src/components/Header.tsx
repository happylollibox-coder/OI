import { useMemo, useState } from 'react';
import type { DashboardData } from '../types';
import { formatDateRange, weekRangeLabel, latestSqpWeek, ACTION_META } from '../utils';

/* ─── Color map for bucket variants ──────────────────────────── */
const VARIANT_COLORS: Record<string, { bg: string; border: string; text: string; dot: string }> = {
  red:    { bg: 'rgba(239,68,68,.12)', border: 'rgba(239,68,68,.35)', text: '#f87171', dot: '#ef4444' },
  green:  { bg: 'rgba(34,197,94,.12)', border: 'rgba(34,197,94,.35)', text: '#4ade80', dot: '#22c55e' },
  blue:   { bg: 'rgba(59,130,246,.12)', border: 'rgba(59,130,246,.35)', text: '#60a5fa', dot: '#3b82f6' },
  amber:  { bg: 'rgba(245,158,11,.12)', border: 'rgba(245,158,11,.35)', text: '#fbbf24', dot: '#f59e0b' },
  purple: { bg: 'rgba(168,85,247,.12)', border: 'rgba(168,85,247,.35)', text: '#c084fc', dot: '#a855f7' },
  muted:  { bg: 'rgba(107,114,128,.12)', border: 'rgba(107,114,128,.35)', text: '#9ca3af', dot: '#6b7280' },
};

export function Header({ data, onNav }: { data: DashboardData; onNav?: (page: string) => void }) {
  const meta = data._meta || {};
  const refreshed = meta.refreshed_at ? new Date(meta.refreshed_at) : null;
  const isCubeLive = meta.cube_source === 'live';
  const dr = data._meta?.date_ranges?.summary_7d;
  const rangeStr = formatDateRange(dr?.start, dr?.end);

  /* ─── Action buckets ──────────────────────────────────────── */
  const buckets = useMemo(() => {
    const actions = data.actions || [];
    const counts: Record<string, number> = {};
    actions.forEach(a => {
      const key = a.action || '';
      if (key && key !== 'MONITOR') counts[key] = (counts[key] || 0) + 1;
    });
    // Order by ACTION_META keys to get consistent ordering
    return Object.entries(ACTION_META)
      .filter(([k]) => (counts[k] || 0) > 0)
      .map(([k, m]) => ({ key: k, label: m.label, count: counts[k], variant: m.variant, criteria: m.criteria }));
  }, [data.actions]);

  const totalActions = buckets.reduce((s, b) => s + b.count, 0);

  /* ─── Data freshness ──────────────────────────────────────── */
  const freshness = useMemo(() => {
    const sqpLast = latestSqpWeek(data.sqp_weekly || []);
    const df = meta.data_freshness;
    const fmtDate = (iso: string) => new Date(iso + 'T00:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric' });

    let adsLabel: string | null = null;
    let perfLabel: string | null = null;

    if (df?.ads_max_date) {
      adsLabel = fmtDate(df.ads_max_date);
    } else {
      const wt = data.weekly_trends || [];
      const maxAds = wt.filter(r => (r.ad_cost || 0) > 0).map(r => r.week_start || '').filter(Boolean).sort().pop();
      if (maxAds) { const d = new Date(maxAds + 'T00:00:00'); d.setDate(d.getDate() + 6); adsLabel = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }); }
    }

    if (df?.performance_max_date) {
      perfLabel = fmtDate(df.performance_max_date);
    } else {
      const wt = data.weekly_trends || [];
      const maxPerf = wt.filter(r => (r.sales || 0) > 0).map(r => r.week_start || '').filter(Boolean).sort().pop();
      if (maxPerf) { const d = new Date(maxPerf + 'T00:00:00'); d.setDate(d.getDate() + 6); perfLabel = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }); }
    }

    return {
      sqp: sqpLast ? weekRangeLabel(sqpLast) : null,
      ads: adsLabel ? 'thru ' + adsLabel : null,
      perf: perfLabel ? 'thru ' + perfLabel : null,
    };
  }, [data.sqp_weekly, data.weekly_trends, meta]);

  return (
    <header className="fixed top-0 left-0 right-0 h-14 bg-overlay backdrop-blur-2xl border-b border-border flex items-center px-5 gap-4 z-50">
      <div className="flex items-center gap-2.5 font-bold text-sm tracking-tight whitespace-nowrap shrink-0">
        <div className="w-2.5 h-2.5 rounded-full bg-gradient-to-br from-purple-500 to-blue-500 shadow-[0_0_8px_rgba(147,51,234,0.3)]" />
        HAPPY LOLLI OI
      </div>

      {rangeStr && <span className="text-[10px] text-faint font-mono shrink-0">{rangeStr}</span>}

      {/* ─── Action bucket pills ─── */}
      <div className="flex items-center gap-1.5 overflow-x-auto scrollbar-none">
        {buckets.map(b => {
          const vc = VARIANT_COLORS[b.variant] || VARIANT_COLORS.muted;
          return (
            <BucketPill
              key={b.key}
              label={b.label}
              count={b.count}
              colors={vc}
              criteria={b.criteria}
              onClick={() => onNav?.('actions')}
            />
          );
        })}
        {totalActions > 0 && (
          <span className="text-[10px] text-faint font-mono ml-1 shrink-0">{totalActions} total</span>
        )}
      </div>

      <div className="flex-1" />

      <div className="flex items-center gap-2 text-[10px] text-faint font-mono whitespace-nowrap shrink-0">
        {freshness.sqp && <span>SQP: {freshness.sqp}</span>}
        {freshness.sqp && freshness.ads && <span className="text-border">|</span>}
        {freshness.ads && <span>Ads: {freshness.ads}</span>}
        {freshness.ads && freshness.perf && <span className="text-border">|</span>}
        {freshness.perf && <span>Orders: {freshness.perf}</span>}
        {(refreshed || isCubeLive) && (
          <>
            <span className="text-border">|</span>
            <span className="flex items-center gap-1">
              {isCubeLive && <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 shadow-[0_0_6px_rgba(52,211,153,0.4)]" />}
              {isCubeLive ? 'Live' : refreshed ? `Refreshed ${refreshed.toLocaleDateString()} ${refreshed.toLocaleTimeString()}` : ''}
            </span>
          </>
        )}
      </div>
    </header>
  );
}

/* ─── Bucket pill with hover tooltip ─────────────────────────── */
function BucketPill({ label, count, colors, criteria, onClick }: {
  label: string; count: number; colors: { bg: string; border: string; text: string; dot: string }; criteria: string; onClick: () => void;
}) {
  const [hover, setHover] = useState(false);
  return (
    <div className="relative" onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}>
      <button
        onClick={onClick}
        className="flex items-center gap-1.5 text-[11px] px-2.5 py-1 rounded-lg whitespace-nowrap transition-all duration-200 cursor-pointer border"
        style={{ background: colors.bg, borderColor: colors.border, color: colors.text }}
      >
        <span className="w-1.5 h-1.5 rounded-full shrink-0" style={{ background: colors.dot, boxShadow: `0 0 6px ${colors.dot}40` }} />
        <span className="font-semibold text-[10px] tracking-wide">{label}</span>
        <span className="font-mono font-bold text-[12px]">{count}</span>
      </button>
      {hover && (
        <div className="absolute top-full left-1/2 -translate-x-1/2 mt-1.5 z-[60] w-64 px-3 py-2 rounded-lg border border-border bg-surface text-[10px] text-subtle leading-relaxed shadow-xl pointer-events-none">
          <div className="font-bold text-text text-[11px] mb-1">{label} — Methodology</div>
          <div>{criteria}</div>
          <div className="mt-1 text-faint text-[9px]">Source: V_ADS_COACH_DECISION (4w = last 28 days)</div>
        </div>
      )}
    </div>
  );
}

