import { useMemo, useState } from 'react';
import { XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, Legend, BarChart, Bar, LabelList, Cell } from 'recharts';
import { Shield, TrendingUp, TrendingDown, Eye, ShoppingCart, ChevronRight, ChevronDown, Info, Filter } from 'lucide-react';
import type { DashboardData, BrandStrengthWeeklyRow } from '../types';
import { useFilters } from '../hooks/useFilters';
import { sliceByPeriod } from '../utils';
import { Badge } from '../components/Badge';

// ─── Helpers ─────────────────────────────────────────
function avgN(nums: (number | null | undefined)[]): number | null {
  const valid = nums.filter((n): n is number => n != null);
  return valid.length ? valid.reduce((a, b) => a + b, 0) / valid.length : null;
}
function safeDivide(num: number, den: number): number | null {
  return den ? num / den : null;
}
function fmtPct(v: number | null | undefined): string {
  return v != null ? `${(v * 100).toFixed(1)}%` : '—';
}

// ─── Dominance Score Explanation ────────────────────────
const DOMINANCE_TARGETS = [
  {
    signal: 'Show Rate',
    icon: '👁️',
    target: '100%',
    floor: '0%',
    meaning: 'Nobody stole my brand terms',
    rationale: 'Full impression ownership on brand keywords. Below 100% means competitors are hijacking your search results.',
    benchmark: 'Industry standard: brand terms should always show 100%+ impression share.',
  },
  {
    signal: 'Brand CVR',
    icon: '🛒',
    target: '25%',
    floor: '0%',
    meaning: 'I am desirable',
    rationale: 'Top of the 15–25% industry range for brand keyword conversion. When shoppers search your name, 1 in 4 should buy.',
    benchmark: 'Industry: brand CVR 15–25%, non-brand CVR 4–12%. Brand terms should convert several times higher than non-brand.',
  },
  {
    signal: 'YoY SQP Growth',
    icon: '📈',
    target: '2.0× (100% growth)',
    floor: '0.5×',
    meaning: 'More people are looking for me',
    rationale: 'Aggressive target for a young brand. Doubling branded search volume year-over-year proves growth momentum.',
    benchmark: 'No universal benchmark — young brands should target consistent MoM growth. Ratchet down as you mature.',
  },
];

const DOMINANCE_EXPLANATION = {
  formula: 'Score per signal = CLAMP((actual − floor) ÷ (target − floor) × 100, 0, 100)  →  Dominance = avg of 3 scores',
  ranges: [
    { min: 75, label: 'Dominant', color: 'text-emerald-400', desc: 'Hitting targets across all signals' },
    { min: 50, label: 'Strong', color: 'text-blue-400', desc: 'On track, minor gaps to close' },
    { min: 25, label: 'Moderate', color: 'text-amber-400', desc: 'Visible but not defending position' },
    { min: 0, label: 'Weak', color: 'text-rose-400', desc: 'Below targets, needs investment' },
  ],
};

// ─── Aggregated row shape ────────────────────────────
interface AggRow {
  period: string;
  brand_keyword: string;
  phrase_type: string | null;
  requested_product: string | null;
  tag: string | null;
  sqp_impressions: number;
  sqp_clicks: number;
  sqp_conversions: number;
  ads_impressions: number;
  ads_clicks: number;
  ads_units: number;
  ads_spend: number;
  ads_cpc: number | null;
  avg_show_rate: number | null;
  avg_impression_share: number | null;
  brand_cvr: number | null;
  brand_dominance_score: number | null;
  sqp_month_impressions: number | null;
  sqp_ly_month_impressions: number | null;
}

function aggRows(rows: BrandStrengthWeeklyRow[], period: string, keyword: string): AggRow {
  const first = rows[0];
  const sqpI = rows.reduce((s, r) => s + r.sqp_impressions, 0);
  const sqpC = rows.reduce((s, r) => s + r.sqp_clicks, 0);
  const sqpConv = rows.reduce((s, r) => s + r.sqp_conversions, 0);
  const adsI = rows.reduce((s, r) => s + r.ads_impressions, 0);
  const adsC = rows.reduce((s, r) => s + r.ads_clicks, 0);
  const adsU = rows.reduce((s, r) => s + r.ads_units, 0);
  const adsS = rows.reduce((s, r) => s + r.ads_spend, 0);
  return {
    period,
    brand_keyword: keyword,
    phrase_type: first?.phrase_type ?? null,
    requested_product: first?.requested_product ?? null,
    tag: first?.tag ?? null,
    sqp_impressions: sqpI,
    sqp_clicks: sqpC,
    sqp_conversions: sqpConv,
    ads_impressions: adsI,
    ads_clicks: adsC,
    ads_units: adsU,
    ads_spend: adsS,
    ads_cpc: safeDivide(adsS, adsC),
    avg_show_rate: avgN(rows.map(r => r.avg_show_rate)),
    avg_impression_share: avgN(rows.map(r => r.avg_impression_share)),
    brand_cvr: safeDivide(sqpConv, sqpC),
    // Recompute dominance from aggregated metrics (not avg of per-keyword scores)
    // Target-based: ShowRate→100%, CVR→25%, YoY→2.0× (floor 0.5×), equal weights
    brand_dominance_score: (() => {
      const sr = avgN(rows.map(r => r.avg_show_rate)) ?? 0;
      const cvr = safeDivide(sqpConv, sqpC) ?? 0;
      const mImp = rows.reduce((s, r) => s + (r.sqp_month_impressions ?? 0), 0);
      const lyImp = rows.reduce((s, r) => s + (r.sqp_ly_month_impressions ?? 0), 0);
      const yoyRatio = lyImp > 0 ? mImp / lyImp : 1.0; // neutral if no LY data
      const clamp = (v: number) => Math.max(0, Math.min(100, v));
      const srScore = clamp(sr);                                    // target 100%, floor 0%
      const cvrScore = clamp((cvr / 0.25) * 100);                  // target 25%, floor 0%
      const yoyScore = clamp(((yoyRatio - 0.5) / 1.5) * 100);     // target 2.0×, floor 0.5×
      return Math.round(((srScore + cvrScore + yoyScore) / 3) * 10) / 10;
    })(),
    sqp_month_impressions: rows.reduce((s, r) => s + (r.sqp_month_impressions ?? 0), 0) || null,
    sqp_ly_month_impressions: rows.reduce((s, r) => s + (r.sqp_ly_month_impressions ?? 0), 0) || null,
  };
}

// ─── Metric card ─────────────────────────────────────
function MetricCard({ label, value, sub, icon, color, tooltip }: {
  label: string; value: string; sub?: string | React.ReactNode; icon: React.ReactNode; color: string; tooltip?: string;
}) {
  const [showTip, setShowTip] = useState(false);
  return (
    <div
      className="flex items-center gap-3 p-3.5 rounded-lg border border-border-faint bg-surface/50 relative"
      onMouseEnter={() => tooltip && setShowTip(true)}
      onMouseLeave={() => setShowTip(false)}
    >
      <div className={`w-9 h-9 rounded-lg flex items-center justify-center ${color}`}>
        {icon}
      </div>
      <div>
        <div className="text-[10px] uppercase tracking-wider text-faint font-bold flex items-center gap-1">
          {label}
          {tooltip && <Info size={10} className="text-faint/50" />}
        </div>
        <div className="text-lg font-bold text-foreground">{value}</div>
        {sub && <div className="text-[10px] text-muted">{sub}</div>}
      </div>
      {showTip && tooltip && (
        <div className="absolute bottom-full left-0 mb-2 z-50 w-72 p-3 rounded-lg bg-zinc-800 border border-zinc-700 shadow-xl text-[10px] text-zinc-300 leading-relaxed">
          {tooltip}
        </div>
      )}
    </div>
  );
}

// ─── Tiny trend arrow ────────────────────────────────
function TrendArrow({ current, previous }: { current: number; previous: number }) {
  if (!previous) return null;
  const pct = ((current - previous) / previous) * 100;
  const isUp = pct >= 0;
  return (
    <span className={`inline-flex items-center gap-0.5 text-[10px] font-mono ${isUp ? 'text-emerald-400' : 'text-rose-400'}`}>
      {isUp ? <TrendingUp size={10} /> : <TrendingDown size={10} />}
      {Math.abs(pct).toFixed(0)}%
    </span>
  );
}

// ─── Tooltip ─────────────────────────────────────────
function ChartTooltip({ active, payload, label }: { active?: boolean; payload?: Array<{ name: string; value: number; color: string }>; label?: string }) {
  if (!active || !payload?.length) return null;
  return (
    <div className="bg-surface border border-border rounded-lg px-3 py-2 shadow-lg text-[11px]">
      <div className="text-faint font-bold mb-1">{label}</div>
      {payload.map((p, i) => (
        <div key={i} className="flex items-center gap-2">
          <div className="w-2 h-2 rounded-full" style={{ background: p.color }} />
          <span className="text-muted">{p.name}:</span>
          <span className="font-mono font-medium text-foreground">{typeof p.value === 'number' ? p.value.toLocaleString(undefined, { maximumFractionDigits: 2 }) : p.value}</span>
        </div>
      ))}
    </div>
  );
}

// ─── Available metrics for dynamic chart ─────────────
const CHART_METRICS: { key: string; label: string; color: string, type: 'sum' | 'rate' }[] = [
  { key: 'dominance', label: 'Dominance Score', color: '#3b82f6', type: 'rate' },
  { key: 'showRate', label: 'Show Rate (%)', color: '#10b981', type: 'rate' },
  { key: 'cvr', label: 'Brand CVR (%)', color: '#14b8a6', type: 'rate' },
  { key: 'yoyImpRatio', label: 'YoY SQP Imp (%)', color: '#f59e0b', type: 'rate' },
  { key: 'sqpImpressions', label: 'SQP Impressions', color: '#3b82f6', type: 'sum' },
  { key: 'sqpClicks', label: 'SQP Clicks', color: '#22c55e', type: 'sum' },
  { key: 'sqpConversions', label: 'SQP Conversions', color: '#f59e0b', type: 'sum' },
  { key: 'adsImpressions', label: 'Ads Impressions', color: '#8b5cf6', type: 'sum' },
  { key: 'adsClicks', label: 'Ads Clicks', color: '#06b6d4', type: 'sum' },
  { key: 'adsUnits', label: 'Ads Units', color: '#ec4899', type: 'sum' },
  { key: 'adsSpend', label: 'Ads Spend ($)', color: '#ef4444', type: 'sum' },
  { key: 'adsCpc', label: 'Ads CPC ($)', color: '#f97316', type: 'rate' },
  { key: 'impShare', label: 'Avg Imp Share (%)', color: '#a855f7', type: 'rate' },
];

// ─── Product/Tag split colors ────────────────────────
const SPLIT_COLORS = ['#3b82f6', '#a855f7', '#22c55e', '#f59e0b', '#ef4444', '#06b6d4', '#ec4899', '#8b5cf6'];

// ─── Main component ──────────────────────────────────
export function BrandPage({ data }: { data: DashboardData }) {
  const rows = data.brand_strength_weekly ?? [];
  const [expandedPeriods, setExpandedPeriods] = useState<Set<string>>(new Set());
  const [selectedMetrics, setSelectedMetrics] = useState<Set<string>>(new Set(['dominance']));
  const [showDominanceExplain, setShowDominanceExplain] = useState(false);
  const [activeTag, setActiveTag] = useState<string | null>(null);
  const [activeProduct, setActiveProduct] = useState<string | null>(null);
  const [showSplits, setShowSplits] = useState(true);
  const { filters } = useFilters();
  const periodMode = filters.periodMode || 'weeks';
  const periodTrend = filters.periodTrend || 4;

  // Toggle period expansion
  const togglePeriod = (period: string) => {
    setExpandedPeriods(prev => {
      const next = new Set(prev);
      if (next.has(period)) next.delete(period);
      else next.add(period);
      return next;
    });
  };

  // Toggle metric selection
  const toggleMetric = (key: string) => {
    setSelectedMetrics(prev => {
      const next = new Set(prev);
      if (next.has(key)) { if (next.size > 1) next.delete(key); } // keep at least 1
      else next.add(key);
      return next;
    });
  };

  // Extract unique tags and products for filter chips
  const { tags, products } = useMemo(() => {
    const tagSet = new Set<string>();
    const prodSet = new Set<string>();
    rows.forEach(r => {
      if (r.tag) tagSet.add(r.tag);
      if (r.requested_product) prodSet.add(r.requested_product);
    });
    return { tags: [...tagSet].sort(), products: [...prodSet].sort() };
  }, [rows]);

  // Apply tag/product/family filters
  const filteredRows = useMemo(() => {
    let out = rows;
    // Apply header family filter (parent_name)
    if (filters.family) out = out.filter(r => r.parent_name === filters.family);
    if (activeTag) out = out.filter(r => r.tag === activeTag);
    if (activeProduct) out = out.filter(r => r.requested_product === activeProduct);
    return out;
  }, [rows, filters.family, activeTag, activeProduct]);

  // Sort all rows ascending by date
  const allSorted = useMemo(() =>
    [...filteredRows].sort((a, b) => a.week_start_date.localeCompare(b.week_start_date)),
    [filteredRows]
  );

  // Group by period key → keyword
  type PeriodBucket = { period: string; total: AggRow; keywords: AggRow[] };
  const grouped: PeriodBucket[] = useMemo(() => {
    const buckets: Record<string, BrandStrengthWeeklyRow[]> = {};
    for (const r of allSorted) {
      const key = periodMode === 'weeks' ? r.week_start_date
        : periodMode === 'month' ? (r.week_start_date || '').slice(0, 7)
        : (r.week_start_date || '').slice(0, 4);
      if (!key) continue;
      (buckets[key] ??= []).push(r);
    }
    return Object.entries(buckets)
      .map(([period, rr]) => {
        // Group by keyword
        const kwBuckets: Record<string, BrandStrengthWeeklyRow[]> = {};
        for (const r of rr) {
          const kw = r.brand_keyword || 'other';
          (kwBuckets[kw] ??= []).push(r);
        }
        const keywords = Object.entries(kwBuckets)
          .map(([kw, kwRows]) => aggRows(kwRows, period, kw))
          .sort((a, b) => b.sqp_impressions - a.sqp_impressions || b.ads_impressions - a.ads_impressions);
        const total = aggRows(rr, period, '__total__');
        return { period, total, keywords };
      })
      .sort((a, b) => a.period.localeCompare(b.period));
  }, [allSorted, periodMode]);

  // Slice by specificPeriod + periodTrend
  const visible = useMemo(() => {
    const allKeys = grouped.map(g => g.period);
    const keep = new Set(sliceByPeriod(allKeys, filters.specificPeriod, periodTrend));
    return grouped.filter(g => keep.has(g.period));
  }, [grouped, filters.specificPeriod, periodTrend]);

  // Grand total across visible periods
  const grandTotal = useMemo(() => {
    const allRows = visible.flatMap(v => {
      const periodsRows = allSorted.filter(r => {
        const key = periodMode === 'weeks' ? r.week_start_date
          : periodMode === 'month' ? (r.week_start_date || '').slice(0, 7)
          : (r.week_start_date || '').slice(0, 4);
        return key === v.period;
      });
      return periodsRows;
    });
    return aggRows(allRows, 'TOTAL', '__grand__');
  }, [visible, allSorted, periodMode]);

  // Chart data from visible period totals
  const chartData = useMemo(() =>
    visible.map(v => {
      const mImp = v.total.sqp_month_impressions ?? 0;
      const lyImp = v.total.sqp_ly_month_impressions ?? 0;
      const yoyRatio = lyImp > 0 ? (mImp / lyImp) * 100 : (mImp > 0 ? 100 : 0);
      return {
        period: periodMode === 'weeks' ? v.period.slice(5) : v.period,
        periodFull: v.period,
        sqpImpressions: v.total.sqp_impressions,
        sqpClicks: v.total.sqp_clicks,
        sqpConversions: v.total.sqp_conversions,
        adsImpressions: v.total.ads_impressions,
        adsClicks: v.total.ads_clicks,
        adsUnits: v.total.ads_units,
        adsSpend: v.total.ads_spend,
        adsCpc: v.total.ads_cpc ?? 0,
        showRate: v.total.avg_show_rate ?? 0,
        impShare: v.total.avg_impression_share ?? 0,
        dominance: v.total.brand_dominance_score ?? 0,
        cvr: v.total.brand_cvr != null ? v.total.brand_cvr * 100 : 0,
        yoyImpRatio: Math.round(yoyRatio),
      };
    }),
    [visible, periodMode]
  );

  // Product split on dominance score (latest period)
  const productSplitData = useMemo(() => {
    if (visible.length === 0) return [];
    const latestBucket = visible[visible.length - 1];
    const byProduct: Record<string, { score: number; count: number }> = {};
    for (const kw of latestBucket.keywords) {
      const prod = kw.requested_product || 'Unassigned';
      if (!byProduct[prod]) byProduct[prod] = { score: 0, count: 0 };
      byProduct[prod].score += kw.brand_dominance_score ?? 0;
      byProduct[prod].count += 1;
    }
    return Object.entries(byProduct)
      .map(([name, d]) => ({ name, score: Math.round(d.score / d.count) }))
      .sort((a, b) => b.score - a.score);
  }, [visible]);

  // Tag split on dominance score (latest period)
  const tagSplitData = useMemo(() => {
    if (visible.length === 0) return [];
    const latestBucket = visible[visible.length - 1];
    const byTag: Record<string, { score: number; count: number }> = {};
    for (const kw of latestBucket.keywords) {
      const tag = kw.tag || 'Untagged';
      if (!byTag[tag]) byTag[tag] = { score: 0, count: 0 };
      byTag[tag].score += kw.brand_dominance_score ?? 0;
      byTag[tag].count += 1;
    }
    return Object.entries(byTag)
      .map(([name, d]) => ({ name, score: Math.round(d.score / d.count) }))
      .sort((a, b) => b.score - a.score);
  }, [visible]);

  // Latest + prev for summary cards
  const latest = visible.length > 0 ? visible[visible.length - 1].total : null;
  const prev = visible.length > 1 ? visible[visible.length - 2].total : null;

  const periodLabel = periodMode === 'weeks' ? 'weeks' : periodMode === 'month' ? 'months' : 'years';
  const tableLabel = periodMode === 'weeks' ? 'Weekly' : periodMode === 'month' ? 'Monthly' : 'Yearly';

  if (!rows.length) {
    return (
      <div className="py-20 text-center text-muted text-sm">
        <Shield size={32} className="mx-auto mb-3 text-faint" />
        No brand strength data available yet. Data will appear once SQP + Ads brand keyword data is loaded.
      </div>
    );
  }

  const dominanceScore = latest?.brand_dominance_score ?? 0;
  const dominanceRange = DOMINANCE_EXPLANATION.ranges.find(r => dominanceScore >= r.min) || DOMINANCE_EXPLANATION.ranges[3];

  return (
    <div className="space-y-5">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-xl font-bold text-foreground flex items-center gap-2.5">
            <Shield size={22} className="text-blue-400" />
            Brand Strength
          </h2>
          <p className="text-xs text-muted mt-1">Brand keyword health across SQP and Ads — {visible.length} {periodLabel} of data</p>
        </div>
      </div>

      {/* Filter Chips — Tags and Products */}
      {(tags.length > 0 || products.length > 0) && (
        <div className="space-y-2">
          {tags.length > 0 && (
            <div className="flex items-center gap-2 flex-wrap">
              <span className="text-[9px] uppercase tracking-widest text-faint font-bold flex items-center gap-1">
                <Filter size={10} /> Tags
              </span>
              <button
                onClick={() => setActiveTag(null)}
                className={`px-2 py-0.5 rounded-md text-[10px] font-semibold border transition-all ${
                  !activeTag ? 'border-blue-500/40 bg-blue-500/10 text-blue-400' : 'border-transparent text-muted hover:text-foreground hover:bg-white/[.04]'
                }`}
              >All</button>
              {tags.map(t => (
                <button
                  key={t}
                  onClick={() => setActiveTag(activeTag === t ? null : t)}
                  className={`px-2 py-0.5 rounded-md text-[10px] font-semibold border transition-all ${
                    activeTag === t ? 'border-blue-500/40 bg-blue-500/10 text-blue-400' : 'border-transparent text-muted hover:text-foreground hover:bg-white/[.04]'
                  }`}
                >{t}</button>
              ))}
            </div>
          )}
          {products.length > 0 && (
            <div className="flex items-center gap-2 flex-wrap">
              <span className="text-[9px] uppercase tracking-widest text-faint font-bold flex items-center gap-1">
                <Filter size={10} /> Products
              </span>
              <button
                onClick={() => setActiveProduct(null)}
                className={`px-2 py-0.5 rounded-md text-[10px] font-semibold border transition-all ${
                  !activeProduct ? 'border-purple-500/40 bg-purple-500/10 text-purple-400' : 'border-transparent text-muted hover:text-foreground hover:bg-white/[.04]'
                }`}
              >All</button>
              {products.map(p => (
                <button
                  key={p}
                  onClick={() => setActiveProduct(activeProduct === p ? null : p)}
                  className={`px-2 py-0.5 rounded-md text-[10px] font-semibold border transition-all ${
                    activeProduct === p ? 'border-purple-500/40 bg-purple-500/10 text-purple-400' : 'border-transparent text-muted hover:text-foreground hover:bg-white/[.04]'
                  }`}
                >{p}</button>
              ))}
            </div>
          )}
        </div>
      )}

      {/* KPI Cards — the 3 dominance sub-components + score */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <MetricCard
          label="Dominance Score"
          value={latest?.brand_dominance_score?.toFixed(0) ?? '—'}
          sub={prev ? <TrendArrow current={latest?.brand_dominance_score ?? 0} previous={prev?.brand_dominance_score ?? 0} /> : undefined}
          icon={<Shield size={16} />}
          color="bg-blue-500/15 text-blue-400"
          tooltip="Target-based score (0–100). Each signal scores 0–100 vs its target, then averaged equally. Show Rate → 100%, Brand CVR → 25%, YoY Growth → 2.0×."
        />
        <MetricCard
          label="Impression Show Rate"
          value={latest?.avg_show_rate != null ? `${latest.avg_show_rate.toFixed(1)}%` : '—'}
          sub={prev ? <TrendArrow current={latest?.avg_show_rate ?? 0} previous={prev?.avg_show_rate ?? 0} /> : undefined}
          icon={<Eye size={16} />}
          color="bg-emerald-500/15 text-emerald-400"
          tooltip="How often your brand appears when shoppers search brand keywords. Target: 100% — nobody stealing your terms. Score = show_rate / 100."
        />
        <MetricCard
          label="Brand CVR"
          value={fmtPct(latest?.brand_cvr)}
          sub={prev ? <TrendArrow current={(latest?.brand_cvr ?? 0) * 100} previous={(prev?.brand_cvr ?? 0) * 100} /> : undefined}
          icon={<ShoppingCart size={16} />}
          color="bg-cyan-500/15 text-cyan-400"
          tooltip="Conversion rate on brand keywords. Target: 25% — top of industry range (15–25%). Your non-brand CVR is ~4.4%, so brand should be 3–6× higher."
        />
        <MetricCard
          label="YoY SQP Impressions"
          value={(() => {
            const mImp = latest?.sqp_month_impressions ?? 0;
            const lyImp = latest?.sqp_ly_month_impressions ?? 0;
            if (lyImp > 0) return `${Math.round((mImp / lyImp) * 100)}%`;
            return mImp > 0 ? '∞' : '—';
          })()}
          sub={latest?.sqp_ly_month_impressions ? `LY: ${latest.sqp_ly_month_impressions.toLocaleString()}` : 'No LY data'}
          icon={<TrendingUp size={16} />}
          color="bg-amber-500/15 text-amber-400"
          tooltip="This month SQP impressions ÷ same month last year. Target: 2.0× (100% YoY growth) — aggressive for a young brand. Floor: 0.5× (declining)."
        />
      </div>

      {/* Dominance Score Explanation Panel */}
      <div className="border border-border-faint rounded-lg bg-surface/30 overflow-hidden">
        <button
          onClick={() => setShowDominanceExplain(p => !p)}
          className="flex items-center gap-2 w-full text-left px-4 py-2.5 hover:bg-white/[.02] transition-colors"
        >
          <Info size={14} className="text-blue-400 flex-shrink-0" />
          <span className="text-xs font-bold text-foreground">Dominance Score Explained</span>
          <Badge variant={dominanceRange.color.includes('emerald') ? 'green' : dominanceRange.color.includes('blue') ? 'blue' : dominanceRange.color.includes('amber') ? 'amber' : 'red'}>
            {dominanceRange.label}: {dominanceScore.toFixed(0)}
          </Badge>
          <ChevronRight size={12} className={`text-faint ml-auto transition-transform ${showDominanceExplain ? 'rotate-90' : ''}`} />
        </button>
        {showDominanceExplain && (
          <div className="px-4 pb-4 pt-2 border-t border-border-faint animate-in space-y-3">
            {/* Methodology */}
            <div className="text-[10px] text-muted font-mono bg-zinc-800/50 rounded px-2.5 py-1.5">
              {DOMINANCE_EXPLANATION.formula}
            </div>

            {/* Target cards for each signal */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
              {DOMINANCE_TARGETS.map(t => (
                <div key={t.signal} className="rounded-lg border border-border-faint bg-zinc-900/40 p-3 space-y-1.5">
                  <div className="flex items-center gap-2">
                    <span className="text-base">{t.icon}</span>
                    <span className="text-xs font-bold text-foreground">{t.signal}</span>
                  </div>
                  <div className="text-[11px] font-semibold text-blue-400 italic">"{t.meaning}"</div>
                  <div className="flex gap-3 text-[10px]">
                    <span className="px-1.5 py-0.5 rounded bg-emerald-500/10 text-emerald-400 font-mono font-bold">Target: {t.target}</span>
                    <span className="px-1.5 py-0.5 rounded bg-zinc-700/50 text-faint font-mono">Floor: {t.floor}</span>
                  </div>
                  <div className="text-[10px] text-muted leading-relaxed">{t.rationale}</div>
                  <div className="text-[9px] text-faint border-t border-border-faint/50 pt-1 mt-1">{t.benchmark}</div>
                </div>
              ))}
            </div>

            {/* Score ranges */}
            <div className="grid grid-cols-4 gap-2">
              {DOMINANCE_EXPLANATION.ranges.map(r => (
                <div key={r.label} className={`text-center p-2 rounded-lg border ${dominanceScore >= r.min && (r.min === 75 || dominanceScore < (DOMINANCE_EXPLANATION.ranges.find(x => x.min > r.min)?.min ?? 101)) ? 'border-blue-500/30 bg-blue-500/5' : 'border-border-faint'}`}>
                  <div className={`text-sm font-bold ${r.color}`}>{r.min}+</div>
                  <div className="text-[10px] font-semibold text-foreground">{r.label}</div>
                  <div className="text-[9px] text-faint">{r.desc}</div>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>

      {/* Product & Tag Split Visuals on Dominance Score */}
      {(productSplitData.length > 0 || tagSplitData.length > 0) && (
        <div className="border border-border-faint rounded-lg bg-surface/30 overflow-hidden">
          <button
            onClick={() => setShowSplits(p => !p)}
            className="flex items-center gap-2 w-full text-left px-4 py-2.5 hover:bg-white/[.02] transition-colors"
          >
            <Shield size={14} className="text-purple-400 flex-shrink-0" />
            <span className="text-xs font-bold text-foreground">Dominance by Product & Tag</span>
            <span className="text-[10px] text-faint ml-1">(latest period)</span>
            <ChevronRight size={12} className={`text-faint ml-auto transition-transform ${showSplits ? 'rotate-90' : ''}`} />
          </button>
          {showSplits && (
            <div className="px-4 pb-4 pt-2 border-t border-border-faint animate-in">
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                {/* Product Split */}
                {productSplitData.length > 0 && (
                  <div>
                    <div className="text-[9px] uppercase tracking-widest text-faint font-bold mb-2">By Product <span className="text-[8px] text-muted font-normal">(click to filter)</span></div>
                    <div className="h-48 cursor-pointer">
                      <ResponsiveContainer width="100%" height="100%">
                        <BarChart data={productSplitData} layout="vertical" barSize={18} onClick={(e) => { if (e?.activeLabel) { const name = String(e.activeLabel) === 'Unassigned' ? null : String(e.activeLabel); setActiveProduct(activeProduct === name ? null : name); } }}>
                          <CartesianGrid strokeDasharray="3 3" horizontal={false} stroke="var(--color-border-faint)" />
                          <XAxis type="number" domain={[0, 100]} tick={{ fontSize: 9, fill: 'var(--color-muted)' }} />
                          <YAxis type="category" dataKey="name" width={100} tick={{ fontSize: 10, fill: 'var(--color-muted)' }} />
                          <Tooltip content={<ChartTooltip />} />
                          <Bar dataKey="score" name="Dominance Score" radius={[0, 4, 4, 0]}>
                            {productSplitData.map((d, i) => (
                              <Cell key={i} fill={SPLIT_COLORS[i % SPLIT_COLORS.length]} fillOpacity={!activeProduct || activeProduct === d.name ? 0.85 : 0.25} stroke={activeProduct === d.name ? '#fff' : 'none'} strokeWidth={activeProduct === d.name ? 1.5 : 0} />
                            ))}
                            <LabelList dataKey="score" position="right" style={{ fontSize: 10, fill: 'var(--color-foreground)', fontFamily: 'var(--font-mono, monospace)' }} />
                          </Bar>
                        </BarChart>
                      </ResponsiveContainer>
                    </div>
                  </div>
                )}
                {/* Tag Split */}
                {tagSplitData.length > 0 && (
                  <div>
                    <div className="text-[9px] uppercase tracking-widest text-faint font-bold mb-2">By Tag <span className="text-[8px] text-muted font-normal">(click to filter)</span></div>
                    <div className="h-48 cursor-pointer">
                      <ResponsiveContainer width="100%" height="100%">
                        <BarChart data={tagSplitData} layout="vertical" barSize={18} onClick={(e) => { if (e?.activeLabel) { const name = String(e.activeLabel) === 'Untagged' ? null : String(e.activeLabel); setActiveTag(activeTag === name ? null : name); } }}>
                          <CartesianGrid strokeDasharray="3 3" horizontal={false} stroke="var(--color-border-faint)" />
                          <XAxis type="number" domain={[0, 100]} tick={{ fontSize: 9, fill: 'var(--color-muted)' }} />
                          <YAxis type="category" dataKey="name" width={100} tick={{ fontSize: 10, fill: 'var(--color-muted)' }} />
                          <Tooltip content={<ChartTooltip />} />
                          <Bar dataKey="score" name="Dominance Score" radius={[0, 4, 4, 0]}>
                            {tagSplitData.map((d, i) => (
                              <Cell key={i} fill={SPLIT_COLORS[(i + 3) % SPLIT_COLORS.length]} fillOpacity={!activeTag || activeTag === d.name ? 0.85 : 0.25} stroke={activeTag === d.name ? '#fff' : 'none'} strokeWidth={activeTag === d.name ? 1.5 : 0} />
                            ))}
                            <LabelList dataKey="score" position="right" style={{ fontSize: 10, fill: 'var(--color-foreground)', fontFamily: 'var(--font-mono, monospace)' }} />
                          </Bar>
                        </BarChart>
                      </ResponsiveContainer>
                    </div>
                  </div>
                )}
              </div>
            </div>
          )}
        </div>
      )}

      {/* Dynamic metric picker */}
      <div>
        <div className="text-[9px] uppercase tracking-widest text-faint font-bold mb-1.5">Select metrics to chart</div>
        <div className="flex flex-wrap gap-1">
          {CHART_METRICS.map(m => (
            <button
              key={m.key}
              onClick={() => toggleMetric(m.key)}
              className={`px-2.5 py-1 rounded-md text-[10px] font-bold transition-all border ${
                selectedMetrics.has(m.key)
                  ? 'border-blue-500/40 bg-blue-500/10 text-blue-400'
                  : 'border-transparent text-muted hover:text-foreground hover:bg-white/[.04]'
              }`}
            >
              {m.label}
            </button>
          ))}
        </div>
      </div>

      {/* Chart — all bars */}
      <div className="h-64 -mx-2">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={chartData} barCategoryGap="15%" barGap={2}>
            <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--color-border-faint)" />
            <XAxis dataKey="period" tick={{ fontSize: 10, fill: 'var(--color-muted)' }} />
            <YAxis tick={{ fontSize: 10, fill: 'var(--color-muted)' }} />
            <Tooltip content={<ChartTooltip />} />
            <Legend wrapperStyle={{ fontSize: 10, color: 'var(--color-muted)' }} />
            {CHART_METRICS.filter(m => selectedMetrics.has(m.key)).map(m => (
              <Bar key={m.key} dataKey={m.key} name={m.label} fill={m.color} opacity={0.75} radius={[2, 2, 0, 0]}>
                <LabelList dataKey={m.key} position="top" style={{ fontSize: 9, fill: 'var(--color-muted)', fontFamily: 'var(--font-mono, monospace)' }} formatter={((v: unknown) => { const n = Number(v ?? 0); return n >= 1000 ? `${(n / 1000).toFixed(1)}k` : n >= 1 ? n.toFixed(0) : n.toFixed(2); }) as never} />
              </Bar>
            ))}
          </BarChart>
        </ResponsiveContainer>
      </div>

      {/* Hierarchical Data Table */}
      <div>
        <h3 className="text-sm font-bold text-foreground mb-2">{tableLabel} Breakdown</h3>
        <div className="overflow-x-auto max-h-[420px] overflow-y-auto">
          <table className="w-full text-[11px]">
            <thead className="sticky top-0 bg-surface z-10">
              <tr className="text-faint uppercase tracking-wider font-bold border-b border-border-faint text-[9px]">
                <th className="text-left py-2 px-2 w-48">Period / Keyword</th>
                <th className="text-left px-2 w-20">Type</th>
                <th className="text-left px-2 w-24">Req Prod</th>
                <th className="text-left px-2 w-16">Tag</th>
                <th className="text-right px-2">Score</th>
                <th className="text-right px-2">Show Rate</th>
                <th className="text-right px-2">Imp Share</th>
                <th className="text-right px-2">SQP Imp</th>
                <th className="text-right px-2">SQP Clicks</th>
                <th className="text-right px-2">SQP Conv</th>
                <th className="text-right px-2">CVR</th>
                <th className="text-right px-2">Ads Imp</th>
                <th className="text-right px-2">Ads Clicks</th>
                <th className="text-right px-2">Ads Units</th>
                <th className="text-right px-2">Ads CPC</th>
                <th className="text-right px-2">Ads Spend</th>
              </tr>
            </thead>
            <tbody>
              {/* Grand Total */}
              <tr className="bg-blue-500/5 font-bold border-b border-border">
                <td className="py-2 px-2 text-foreground">TOTAL</td>
                <td></td>
                <td></td>
                <td></td>
                <DataCells row={grandTotal} />
              </tr>

              {/* Period rows (newest first) */}
              {[...visible].reverse().map(bucket => {
                const isExpanded = expandedPeriods.has(bucket.period);
                return (
                  <PeriodGroup
                    key={bucket.period}
                    bucket={bucket}
                    isExpanded={isExpanded}
                    onToggle={() => togglePeriod(bucket.period)}
                  />
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

// ─── Period group (date row + keyword children) ──────
function PeriodGroup({ bucket, isExpanded, onToggle }: {
  bucket: { period: string; total: AggRow; keywords: AggRow[] };
  isExpanded: boolean;
  onToggle: () => void;
}) {
  return (
    <>
      {/* Period header row */}
      <tr
        className="border-b border-border-faint/50 hover:bg-white/[.03] cursor-pointer transition-colors"
        onClick={onToggle}
      >
        <td className="py-1.5 px-2 font-mono text-foreground font-semibold">
          <span className="inline-flex items-center gap-1">
            {isExpanded ? <ChevronDown size={12} className="text-muted" /> : <ChevronRight size={12} className="text-muted" />}
            {bucket.period}
            <span className="text-[9px] text-faint font-normal ml-1">({bucket.keywords.length} kw)</span>
          </span>
        </td>
        <td></td>
        <td></td>
        <td></td>
        <DataCells row={bucket.total} />
      </tr>

      {/* Keyword children */}
      {isExpanded && bucket.keywords.map(kw => (
        <tr key={kw.brand_keyword} className="border-b border-border-faint/30 hover:bg-white/[.02] transition-colors bg-white/[.01]">
          <td className="py-1 px-2 pl-7 text-muted truncate max-w-[160px]" title={kw.brand_keyword}>
            {kw.brand_keyword || 'other'}
          </td>
          <td className="px-2 text-[9px] uppercase tracking-wider text-faint">{kw.phrase_type || '—'}</td>
          <td className="px-2 text-muted truncate max-w-[100px]" title={kw.requested_product || ''}>{kw.requested_product || '—'}</td>
          <td className="px-2 text-blue-400 font-mono text-[10px] truncate max-w-[80px]" title={kw.tag || ''}>{kw.tag || '—'}</td>
          <DataCells row={kw} />
        </tr>
      ))}
    </>
  );
}

// ─── Shared data cells for a row ─────────────────────
function DataCells({ row }: { row: AggRow }) {
  return (
    <>
      <td className="text-right px-2">
        <span className={`font-bold ${(row.brand_dominance_score ?? 0) >= 50 ? 'text-emerald-400' : (row.brand_dominance_score ?? 0) >= 25 ? 'text-amber-400' : 'text-rose-400'}`}>
          {row.brand_dominance_score?.toFixed(0) ?? '—'}
        </span>
      </td>
      <td className="text-right px-2 text-muted">{row.avg_show_rate?.toFixed(0) ?? '—'}%</td>
      <td className="text-right px-2 text-muted">{row.avg_impression_share?.toFixed(0) ?? '—'}%</td>
      <td className="text-right px-2 text-foreground">{row.sqp_impressions.toLocaleString()}</td>
      <td className="text-right px-2 text-foreground">{row.sqp_clicks.toLocaleString()}</td>
      <td className="text-right px-2 text-foreground">{row.sqp_conversions.toLocaleString()}</td>
      <td className="text-right px-2">
        <span className={`font-mono ${(row.brand_cvr ?? 0) > 0.1 ? 'text-emerald-400' : 'text-muted'}`}>
          {fmtPct(row.brand_cvr)}
        </span>
      </td>
      <td className="text-right px-2 text-foreground">{row.ads_impressions.toLocaleString()}</td>
      <td className="text-right px-2 text-foreground">{row.ads_clicks.toLocaleString()}</td>
      <td className="text-right px-2 text-foreground">{row.ads_units.toLocaleString()}</td>
      <td className="text-right px-2 text-amber-400 font-mono">{row.ads_cpc != null ? `$${row.ads_cpc.toFixed(2)}` : '—'}</td>
      <td className="text-right px-2 text-muted font-mono">${row.ads_spend.toFixed(0)}</td>
    </>
  );
}
