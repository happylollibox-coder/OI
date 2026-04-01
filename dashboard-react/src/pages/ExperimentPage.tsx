import { useMemo, useState, useEffect, type ReactNode } from 'react';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, LineChart, Line, Legend } from 'recharts';
import { SeasonalReferenceLines, getXLabels } from '../components/SeasonalReferenceLines';
import type { DashboardData } from '../types';
import { KpiCard, Card } from '../components/Card';
import { Section } from '../components/Section';
import { Badge, RoasBadge } from '../components/Badge';
import { Empty } from '../components/Empty';
import { fM, fP, fR, fOrd, fClk, weekRangeLabel, periodKey, periodModeLabel, getPeriodsToInclude } from '../utils';
import { filterBySeasonality } from '../seasonality';
import { useFilters, type PeriodMode } from '../hooks/useFilters';
import { formatSectionFilters } from '../utils/filterUtils';
import { CHART_GRID, CHART_AXIS_TICK_MD, CHART_AXIS_TICK_LG, CHART_TOOLTIP_STYLE } from '../chartTheme';
import { SortTh, useSort, MEASURE_TIPS } from '../components/Tooltip';
import { MeasureSelector, useMeasureSelection, type MeasureDef } from '../components/MeasureSelector';
import { STRATEGY_META, DEFAULT_STRATEGY, CHART_MEASURE_META, ALL_CHART_MEASURES, type ChartMeasureId } from '../strategies';
import { usePageSummary } from '../components/PageSummaryBar';

export function ExperimentPage({ data, experimentId }: { data: DashboardData; experimentId: string }) {
  const { filters } = useFilters();
  const exp = useMemo(() => (data.experiments || []).find(e => e.experiment_id === experimentId), [data.experiments, experimentId]);
  const bh = useMemo(() => (data.budget_health || []).find(b => b.experiment_id === experimentId), [data.budget_health, experimentId]);
  const pk = data.peak?.[0] ?? null;
  const periodMode: PeriodMode = filters.periodMode;
  const baseRows = useMemo(() => {
    let rows = (data.experiment_weekly || []).filter(w => w.experiment_id === experimentId);
    rows = filterBySeasonality(rows, 'week_start', filters.seasonality, pk);
    return rows.sort((a, b) => (a.week_start || '').localeCompare(b.week_start || ''));
  }, [data.experiment_weekly, data.peak, experimentId, filters.seasonality, pk]);

  const weeklyData = useMemo(() => {
    const allWeeks = baseRows.map(r => r.week_start || '');
    const keep = new Set(getPeriodsToInclude(filters.specificPeriod, 'weeks', allWeeks, filters.periodTrend));
    return baseRows.filter(r => keep.has(r.week_start || ''));
  }, [baseRows, filters.periodTrend, filters.specificPeriod]);
  const kwData = useMemo(() => (data.keyword_product_map || []).filter(k => k.experiment_id === experimentId), [data.keyword_product_map, experimentId]);
  const kwS = useSort('spend_60d');
  const chgS = useSort('change_date');
  const EXP_KW_COLUMNS: MeasureDef[] = [
    { id: 'search_term', label: 'Keyword', group: 'Info' },
    { id: 'product_short_name', label: 'Product', group: 'Info' },
    { id: 'spend_60d', label: 'Ads Spend', group: 'Ads' },
    { id: 'orders_60d', label: 'Ads Orders', group: 'Ads' },
    { id: 'clicks_60d', label: 'Ads Clicks', group: 'Ads' },
    { id: 'impression_share', label: 'Ads Imp Share', tip: MEASURE_TIPS.impression_share, group: 'Ads' },
    { id: 'conv_rate_60d', label: 'Ads Conv%', group: 'Ads' },
    { id: 'net_roas_60d', label: 'Ads ROAS', group: 'Ads' },
    { id: 'is_hero_match', label: 'Hero?', group: 'Info' },
    { id: 'action', label: 'Action', group: 'Info' },
  ];
  const EXP_CHG_COLUMNS: MeasureDef[] = [
    { id: 'change_date', label: 'Date', group: 'Info' },
    { id: 'change_type', label: 'Type', group: 'Info' },
    { id: 'field_changed', label: 'Field', group: 'Info' },
    { id: 'old_value', label: 'Old', group: 'Info' },
    { id: 'new_value', label: 'New', group: 'Info' },
    { id: 'reason', label: 'Reason', group: 'Info' },
  ];
  const [expKwCols, setExpKwCols] = useMeasureSelection('experiment_keywords', EXP_KW_COLUMNS);
  const [expChgCols, setExpChgCols] = useMeasureSelection('experiment_changelog', EXP_CHG_COLUMNS);
  const visibleExpKwCols = useMemo(() => EXP_KW_COLUMNS.filter(c => expKwCols.has(c.id)), [expKwCols]);
  const visibleExpChgCols = useMemo(() => EXP_CHG_COLUMNS.filter(c => expChgCols.has(c.id)), [expChgCols]);
  const changes = useMemo(() => (data.change_log || []).filter(c => c.experiment_id === experimentId).sort((a, b) => (b.change_date || b.created_at || '').localeCompare(a.change_date || a.created_at || '')), [data.change_log, experimentId]);

  // Business conclusions for this experiment
  const conclusions = useMemo(() => {
    try {
      const stored = localStorage.getItem('hl_conclusions');
      if (!stored) return [];
      return JSON.parse(stored).filter((c: { experiment_id?: string; status: string }) => c.experiment_id === experimentId && c.status === 'active');
    } catch { return []; }
  }, [experimentId]);

  if (!exp) return <Empty icon="🧪" message={`Experiment "${experimentId}" not found`} hint="Check experiment ID" />;

  const strategyMeta = STRATEGY_META[exp.strategy_id] || { ...DEFAULT_STRATEGY, label: exp.strategy_id };
  const strategyGoal = strategyMeta.goal || `Strategy: ${exp.strategy_id}`;
  const sig = exp.action_signal || exp.verdict || bh?.action_signal || '--';
  const sigColor = sig.includes('SCALE') ? 'green' as const : sig.includes('REDUCE') || sig.includes('STOP') ? 'red' as const : sig.includes('WATCH') ? 'amber' as const : 'blue' as const;

  // Chart measures for this strategy
  const chartMeasures = useMemo(() => {
    const ids = strategyMeta.chartMeasureIds ?? ALL_CHART_MEASURES;
    return ids.filter((id): id is ChartMeasureId => CHART_MEASURE_META[id] != null);
  }, [strategyMeta.chartMeasureIds]);

  const [selectedChartMeasures, setSelectedChartMeasures] = useState<Set<ChartMeasureId>>(new Set(['spend']));

  useEffect(() => {
    if (chartMeasures.length > 0) {
      const first = chartMeasures[0];
      setSelectedChartMeasures(prev => {
        const hasValid = chartMeasures.some(m => prev.has(m));
        return hasValid ? prev : new Set([first]);
      });
    }
  }, [experimentId, chartMeasures]);

  const toggleChartMeasure = (m: ChartMeasureId) => {
    setSelectedChartMeasures(prev => {
      const next = new Set(prev);
      if (next.has(m)) { if (next.size > 1) next.delete(m); }
      else next.add(m);
      return next;
    });
  };

  // Map chart measure IDs to trendChart data keys
  const measureToDataKey: Record<ChartMeasureId, string> = {
    spend: 'spend',
    sales: 'sales',
    orders: 'orders',
    conv_rate: 'conv_rate',
    net_roas: 'roas',
    organic_pct: 'organic_pct',
  };
  const dataKeyToMeasure: Record<string, ChartMeasureId> = Object.fromEntries(
    (Object.entries(measureToDataKey) as [ChartMeasureId, string][]).map(([k, v]) => [v, k])
  );

  // Trend chart data — respects periodMode (weeks / month / year)
  const trendChart = useMemo(() => {
    if (periodMode === 'weeks') {
      return weeklyData.map(w => {
        const orders = w.total_orders || 0;
        const organic = w.organic_units || 0;
        const organicPct = orders > 0 ? (organic / orders) * 100 : (w.organic_pct ?? 0);
        return {
          label: weekRangeLabel(w.week_start),
          sales: w.sales || 0,
          spend: w.ads_spend || 0,
          orders,
          organic,
          conv_rate: w.conv_rate ?? 0,
          organic_pct: organicPct,
          roas: w.net_roas ?? (w.ads_spend > 0 ? ((w.sales || 0) - w.ads_spend) / w.ads_spend : 0),
        };
      });
    }
    const byPeriod: Record<string, { sales: number; spend: number; orders: number; organic: number; sessions: number; conv_rate_sum: number; conv_rate_cnt: number; organic_pct_sum: number; organic_pct_cnt: number }> = {};
    baseRows.forEach(r => {
      const k = periodKey(r.week_start || '', periodMode);
      if (!byPeriod[k]) byPeriod[k] = { sales: 0, spend: 0, orders: 0, organic: 0, sessions: 0, conv_rate_sum: 0, conv_rate_cnt: 0, organic_pct_sum: 0, organic_pct_cnt: 0 };
      const d = byPeriod[k];
      d.sales += r.sales || 0;
      d.spend += r.ads_spend || 0;
      d.orders += r.total_orders || 0;
      d.organic += r.organic_units || 0;
      d.sessions += r.sessions || 0;
      if (r.conv_rate != null) { d.conv_rate_sum += r.conv_rate; d.conv_rate_cnt++; }
      if (r.organic_pct != null) { d.organic_pct_sum += r.organic_pct; d.organic_pct_cnt++; }
    });
    const periodKeys = Object.keys(byPeriod).sort();
    const keep = new Set(getPeriodsToInclude(filters.specificPeriod, periodMode, periodKeys, filters.periodTrend));
    const entries = Object.entries(byPeriod).filter(([k]) => keep.has(k)).sort(([a], [b]) => a.localeCompare(b));
    return entries.map(([label, d]) => {
      const roas = d.spend > 0 ? (d.sales - d.spend) / d.spend : 0;
      const organicPct = d.organic_pct_cnt > 0 ? d.organic_pct_sum / d.organic_pct_cnt : (d.orders > 0 ? (d.organic / d.orders) * 100 : 0);
      const convRate = d.conv_rate_cnt > 0 ? d.conv_rate_sum / d.conv_rate_cnt : 0;
      return {
        label,
        sales: d.sales,
        spend: d.spend,
        orders: d.orders,
        organic: d.organic,
        conv_rate: convRate,
        organic_pct: organicPct,
        roas,
      };
    });
  }, [periodMode, weeklyData, baseRows, filters.periodTrend, filters.specificPeriod]);

  // SQP share changes
  const hasSQP = exp.search_bl_impressions_share_pct != null || exp.search_exp_impressions_share_pct != null;
  const sqpMetrics = hasSQP ? [
    { label: 'Impressions Share', bl: exp.search_bl_impressions_share_pct, ex: exp.search_exp_impressions_share_pct, delta: exp.search_impressions_share_delta_pp },
    { label: 'Clicks Share', bl: exp.search_bl_clicks_share_pct, ex: exp.search_exp_clicks_share_pct, delta: exp.search_clicks_share_delta_pp },
    { label: 'Orders Share', bl: exp.search_bl_orders_share_pct, ex: exp.search_exp_orders_share_pct, delta: exp.search_orders_share_delta_pp },
    { label: 'Conversion Rate', bl: exp.search_bl_conversion_rate_pct, ex: exp.search_exp_conversion_rate_pct, delta: exp.search_conversion_rate_delta_pp },
    { label: 'CTR', bl: exp.search_bl_ctr_pct, ex: exp.search_exp_ctr_pct, delta: exp.search_ctr_delta_pp },
  ] : [];

  // Performance lift
  const hasPerf = exp.performance_baseline_total_orders != null && exp.performance_baseline_total_orders > 0;

  usePageSummary({ title: 'Experiment', items: [{ label: 'ID', value: experimentId }] });
  return (
    <div className="animate-in">
      {/* Header */}
      <div className="flex items-start justify-between mb-5">
        <div>
          <h1 className="text-[22px] font-extrabold tracking-tight">{exp.experiment_name || exp.experiment_id}</h1>
          <div className="text-xs text-subtle mt-1">{exp.strategy_id || ''} · {exp.status || ''} · Started {exp.start_date || '--'} · {exp.days_running || exp.days_active || '--'} days</div>
        </div>
        <div className="flex items-center gap-2">
          <Badge variant={sigColor} className="!text-xs">{sig}</Badge>
          <Badge variant={exp.organic_verdict === 'POSITIVE' ? 'green' : exp.organic_verdict === 'NEGATIVE' ? 'red' : 'muted'} className="!text-xs">
            {exp.organic_verdict || 'No verdict'}
          </Badge>
        </div>
      </div>

      {/* Goal / Expectation */}
      <Card className="!p-4 mb-6 !border-l-[3px] !border-l-blue-500">
        <div className="text-[10px] text-faint uppercase font-semibold tracking-wider mb-1">Strategy Goal & Expectations</div>
        <div className="text-xs text-subtle leading-relaxed">{strategyGoal}</div>
        {strategyMeta.expectedOutcome && (
          <div className="text-[11px] text-subtle mt-2 pt-2 border-t border-border-faint">{strategyMeta.expectedOutcome}</div>
        )}
        {exp.description && <div className="text-xs text-subtle mt-2 pt-2 border-t border-border-faint italic">{exp.description}</div>}
      </Card>

      {/* KPIs */}
      <div className="grid grid-cols-5 gap-3.5 mb-6">
        <KpiCard label="Ads Spend" value={fM(exp.ads_total_spend)} note={`${exp.days_running || '--'}d running`} />
        <KpiCard label="Total Revenue" value={fM(exp.ads_total_revenue)} />
        <KpiCard label="Ads ROAS" value={exp.ads_avg_roas != null ? fR(exp.ads_avg_roas) : '--'} note={exp.ads_avg_roas != null ? (exp.ads_avg_roas >= 0 ? 'Profitable' : 'Below break-even') : undefined} />
        <KpiCard label="Organic Lift" value={exp.search_avg_organic_lift_pct != null ? (exp.search_avg_organic_lift_pct > 0 ? '+' : '') + fP(exp.search_avg_organic_lift_pct) : '--'} note={`${exp.terms_positive_organic_lift || 0} pos / ${exp.terms_negative_organic_lift || 0} neg`} />
        <KpiCard label="Tracked Terms" value={String(exp.tracked_search_terms || 0)} note={`${exp.tracked_asins || 0} ASINs`} />
      </div>

      {/* Performance Lift */}
      {hasPerf && (
        <Section title="Performance Lift (Baseline vs Experiment)" filterItems={formatSectionFilters(filters)}>
          <div className="grid grid-cols-4 gap-3 mb-4">
            {[
              { label: 'Total Orders', bl: exp.performance_baseline_total_orders, ex: exp.performance_experiment_total_orders, lift: exp.performance_total_orders_lift_pct },
              { label: 'Organic Orders', bl: exp.performance_baseline_organic_units, ex: exp.performance_experiment_organic_units, lift: exp.performance_organic_units_lift_pct },
              { label: 'Total Sales', bl: exp.performance_baseline_total_sales, ex: exp.performance_experiment_total_sales, lift: null },
              { label: 'Sessions Lift', bl: null, ex: null, lift: exp.performance_sessions_lift_pct },
            ].map((m, i) => (
              <Card key={i} className="!p-3">
                <div className="text-[10px] text-faint uppercase font-semibold mb-1">{m.label}</div>
                {m.bl != null && m.ex != null ? (
                  <div className="flex items-baseline gap-2">
                    <span className="text-faint text-[11px]">{typeof m.bl === 'number' && m.label.includes('Sales') ? fM(m.bl) : String(m.bl)}</span>
                    <span className="text-faint">→</span>
                    <span className="font-bold text-sm font-mono">{typeof m.ex === 'number' && m.label.includes('Sales') ? fM(m.ex) : String(m.ex)}</span>
                  </div>
                ) : null}
                {m.lift != null && (
                  <div className={`font-bold font-mono text-sm ${m.lift > 0 ? 'text-emerald-400' : m.lift < 0 ? 'text-red-400' : 'text-zinc-400'}`}>
                    {m.lift > 0 ? '+' : ''}{fP(m.lift)}
                  </div>
                )}
              </Card>
            ))}
          </div>
        </Section>
      )}

      {/* SQP Share Changes */}
      {sqpMetrics.length > 0 && sqpMetrics.some(m => m.bl != null || m.ex != null) && (
        <Section title="Search Query Performance (SQP Share)" filterItems={formatSectionFilters(filters)}>
          <div className="border border-border rounded-xl bg-card overflow-hidden">
            <table className="w-full border-collapse text-xs">
              <thead><tr>
                {['Metric', 'Baseline', 'Experiment', 'Delta (pp)'].map(h => (
                  <th key={h} className="bg-inset text-subtle text-left px-3 py-2.5 font-semibold text-[10px] uppercase tracking-wider border-b border-border">{h}</th>
                ))}
              </tr></thead>
              <tbody>
                {sqpMetrics.map((m, i) => (
                  <tr key={i} className="border-b border-border-faint last:border-b-0">
                    <td className="px-3 py-2 font-semibold">{m.label}</td>
                    <td className="px-3 py-2 font-mono">{m.bl != null ? fP(m.bl) : '--'}</td>
                    <td className="px-3 py-2 font-mono">{m.ex != null ? fP(m.ex) : '--'}</td>
                    <td className={`px-3 py-2 font-mono font-bold ${(m.delta || 0) > 0 ? 'text-emerald-400' : (m.delta || 0) < 0 ? 'text-red-400' : ''}`}>
                      {m.delta != null ? ((m.delta > 0 ? '+' : '') + m.delta.toFixed(1) + 'pp') : '--'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Section>
      )}

      {/* Trend chart — template-driven, title reflects periodMode */}
      {trendChart.length > 0 && (
        <Section title={`${periodModeLabel(periodMode)} Trend`} filterItems={formatSectionFilters(filters)}>
          <Card className="!p-4">
            <div className="text-[10px] text-faint mb-2">Charts for {strategyMeta.label}</div>
            <div className="flex flex-wrap gap-1 mb-3">
              {chartMeasures.map(m => {
                const meta = CHART_MEASURE_META[m];
                const active = selectedChartMeasures.has(m);
                return (
                  <button key={m} onClick={() => toggleChartMeasure(m)}
                    className="px-2 py-0.5 rounded-lg text-[10px] font-semibold border transition-all"
                    style={{
                      borderColor: active ? meta.color : 'rgba(63,63,70,.45)',
                      background: active ? meta.color + '20' : 'transparent',
                      color: active ? meta.color : '#71717a',
                    }}
                  >{meta.label}</button>
                );
              })}
            </div>
            <ResponsiveContainer width="100%" height={200}>
              <LineChart data={trendChart}>
                <CartesianGrid {...CHART_GRID} />
                <XAxis dataKey="label" tick={CHART_AXIS_TICK_MD} tickLine={false} axisLine={false} />
                <YAxis yAxisId="left" tick={CHART_AXIS_TICK_LG} tickLine={false} axisLine={false} tickFormatter={v => '$' + (v / 1000).toFixed(0) + 'K'} />
                <YAxis yAxisId="right" orientation="right" tick={CHART_AXIS_TICK_LG} tickLine={false} axisLine={false} />
                <Tooltip
                  contentStyle={CHART_TOOLTIP_STYLE(11)}
                  formatter={(v: number | undefined, name?: string) => {
                    const mid = dataKeyToMeasure[name as string];
                    const m = mid ? CHART_MEASURE_META[mid] : null;
                    return [m ? m.fmt(v ?? 0) : String(v ?? 0), (m?.label || name) ?? ''];
                  }}
                />
                <Legend wrapperStyle={{ fontSize: 10 }} />
                <SeasonalReferenceLines holidays={data.holidays || []} xLabels={getXLabels(trendChart)} yAxisId="left" />
                {[...selectedChartMeasures].map(m => {
                  const dataKey = measureToDataKey[m];
                  const meta = CHART_MEASURE_META[m];
                  const yAxisId = m === 'spend' || m === 'sales' ? 'left' : 'right';
                  return (
                    <Line key={m} yAxisId={yAxisId} type="monotone" dataKey={dataKey} name={meta.label} stroke={meta.color} strokeWidth={2} dot={{ r: 3 }} />
                  );
                })}
              </LineChart>
            </ResponsiveContainer>
          </Card>
          {chartMeasures.includes('net_roas') && (
            <Card className="!p-4 mt-3">
              <div className="text-[10px] text-faint uppercase font-semibold mb-2">ROAS Trend</div>
              <ResponsiveContainer width="100%" height={120}>
                <BarChart data={trendChart}>
                  <CartesianGrid {...CHART_GRID} />
                  <XAxis dataKey="label" tick={CHART_AXIS_TICK_MD} tickLine={false} axisLine={false} />
                  <YAxis tick={CHART_AXIS_TICK_LG} tickLine={false} axisLine={false} tickFormatter={v => fR(v)} />
                  <Tooltip contentStyle={CHART_TOOLTIP_STYLE(11)} formatter={(v: number | undefined) => [v != null ? fR(v) : '--', 'ROAS']} />
                  <SeasonalReferenceLines holidays={data.holidays || []} xLabels={getXLabels(trendChart)} />
                  <Bar dataKey="roas" fill="#a855f7" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </Card>
          )}
        </Section>
      )}

      {/* Keywords in this experiment */}
      {kwData.length > 0 && (
        <Section title="Keywords" count={`${kwData.length} tracked`} filterItems={formatSectionFilters(filters)} headerRight={<MeasureSelector tableId="experiment_keywords" measures={EXP_KW_COLUMNS} selected={expKwCols} onSelectedChange={setExpKwCols} />}>
          <div className="border border-border rounded-xl bg-card overflow-x-auto" style={{ maxHeight: 400, overflowY: 'auto' }}>
            <table className="w-full border-collapse text-xs">
              <thead><tr>
                {visibleExpKwCols.map(c => (
                  <SortTh key={c.id} k={c.id} sort={kwS.sort} toggle={kwS.toggle} right={!['search_term', 'product_short_name', 'is_hero_match', 'action'].includes(c.id)} tip={c.tip}>{c.label}</SortTh>
                ))}
              </tr></thead>
              <tbody>
                {kwS.sorted(kwData).map((k, i) => {
                  const cells: Record<string, ReactNode> = {
                    search_term: <td key="search_term" className="px-3 py-2 font-semibold text-blue-400">{k.search_term}</td>,
                    product_short_name: <td key="product_short_name" className="px-3 py-2">{k.product_short_name}</td>,
                    spend_60d: <td key="spend_60d" className="px-3 py-2 font-mono text-[11px]">{fM(k.spend_60d)}</td>,
                    orders_60d: <td key="orders_60d" className="px-3 py-2">{fOrd(k.orders_60d)}</td>,
                    clicks_60d: <td key="clicks_60d" className="px-3 py-2">{fClk(k.clicks_60d || 0)}</td>,
                    impression_share: <td key="impression_share" className="px-3 py-2 font-mono text-[11px]">{k.impression_share ? fP(k.impression_share * 100) : '--'}</td>,
                    conv_rate_60d: <td key="conv_rate_60d" className="px-3 py-2">{fP(k.conv_rate_60d)}</td>,
                    net_roas_60d: <td key="net_roas_60d" className="px-3 py-2"><RoasBadge value={k.net_roas_60d} /></td>,
                    is_hero_match: <td key="is_hero_match" className="px-3 py-2">{k.is_hero_match ? <span className="text-emerald-400">✓</span> : <span className="text-red-400">✗</span>}</td>,
                    action: <td key="action" className="px-3 py-2"><Badge variant={k.action === 'KEEP' ? 'green' : k.action === 'STOP' || k.action === 'NEGATE' ? 'red' : 'blue'} className="!text-[10px]">{k.action}</Badge></td>,
                  };
                  return (
                    <tr key={i} className="border-b border-border-faint last:border-b-0 hover:bg-white/[.02]">
                      {visibleExpKwCols.map(c => cells[c.id])}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </Section>
      )}

      {/* Business Learnings */}
      {conclusions.length > 0 && (
        <Section title="Business Learnings" count={`${conclusions.length} approved`} filterItems={formatSectionFilters(filters)}>
          <div className="space-y-2">
            {conclusions.map((c: { id: string; conclusion: string; evidence: string; impact: string; tags: string[]; created_at: string }) => (
              <Card key={c.id} className="!p-3 !border-l-[3px] !border-l-emerald-500">
                <div className="text-xs font-semibold mb-1">{c.conclusion}</div>
                <div className="text-[11px] text-subtle">{c.evidence}</div>
                <div className="flex gap-2 mt-1.5">
                  <Badge variant={c.impact === 'scale' ? 'green' : c.impact === 'reduce' ? 'red' : 'blue'} className="!text-[10px]">{c.impact}</Badge>
                  {c.tags?.map(t => <Badge key={t} variant="muted" className="!text-[10px]">{t}</Badge>)}
                </div>
              </Card>
            ))}
          </div>
        </Section>
      )}

      {/* Change Log */}
      {changes.length > 0 && (
        <Section title="Change Log" count={`${changes.length} changes`} filterItems={formatSectionFilters(filters)} headerRight={<MeasureSelector tableId="experiment_changelog" measures={EXP_CHG_COLUMNS} selected={expChgCols} onSelectedChange={setExpChgCols} />}>
          <div className="border border-border rounded-xl bg-card overflow-hidden">
            <table className="w-full border-collapse text-xs">
              <thead><tr>
                {visibleExpChgCols.map(c => (
                  <SortTh key={c.id} k={c.id} sort={chgS.sort} toggle={chgS.toggle} right={['old_value', 'new_value'].includes(c.id)}>{c.label}</SortTh>
                ))}
              </tr></thead>
              <tbody>
                {chgS.sorted(changes).slice(0, 20).map((c, i) => {
                  const cells: Record<string, ReactNode> = {
                    change_date: <td key="change_date" className="px-3 py-2 font-mono text-[10px]">{c.change_date || c.created_at || '--'}</td>,
                    change_type: <td key="change_type" className="px-3 py-2"><Badge variant="muted" className="!text-[10px]">{c.change_type}</Badge></td>,
                    field_changed: <td key="field_changed" className="px-3 py-2">{c.field_changed || '--'}</td>,
                    old_value: <td key="old_value" className="px-3 py-2 text-red-400 font-mono text-[10px]">{c.old_value || '--'}</td>,
                    new_value: <td key="new_value" className="px-3 py-2 text-emerald-400 font-mono text-[10px]">{c.new_value || '--'}</td>,
                    reason: <td key="reason" className="px-3 py-2 text-subtle max-w-[200px] truncate">{c.reason || '--'}</td>,
                  };
                  return (
                    <tr key={i} className="border-b border-border-faint last:border-b-0 hover:bg-white/[.02]">
                      {visibleExpChgCols.map(col => cells[col.id])}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </Section>
      )}
    </div>
  );
}
