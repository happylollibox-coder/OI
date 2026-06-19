import React, { useState, useMemo, useEffect, createElement } from 'react';
import type { DashboardData, ExperimentTemplateRow, BusinessConclusion, ExperimentCampaignRow } from '../types';
import { Card } from '../components/Card';
import { Empty } from '../components/Empty';
import { Th, SortTh, useSort, MEASURE_TIPS } from '../components/Tooltip';
import { Badge, RoasBadge } from '../components/Badge';
import { fM, fP, fOrd, fR, fCpc, fClk, experimentMatchesFamily, weekRangeLabelCapped, periodKey, getPeriodsToInclude } from '../utils';
import { useFilters, type PeriodMode } from '../hooks/useFilters';
import { formatSectionFilters } from '../utils/filterUtils';
import { FilterInfoIcon } from '../components/FilterInfoIcon';
import { filterBySeasonality } from '../seasonality';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from 'recharts';
import { CHART_GRID, CHART_AXIS_TICK_LG, CHART_TOOLTIP_STYLE } from '../chartTheme';
import { type SeasonPhase, PHASE_META, ALL_PHASES, classifyPhase, filterByPhase } from '../phaseClassifier';

import { ChevronRight, ChevronDown, Target, BookOpen, TrendingUp, Lightbulb, CheckCircle2, GraduationCap, Circle, CircleDot, Sun, Flame, Zap } from 'lucide-react';
import { STRATEGY_META, DEFAULT_STRATEGY, CHART_MEASURE_META, ALL_CHART_MEASURES, DEFAULT_KPI_COLUMNS, type ChartMeasureId, type QuestionStatus, type DataCheck, type KpiColumnId } from '../strategies';
import { MeasureSelector, useMeasureSelection, type MeasureDef } from '../components/MeasureSelector';
import { usePageSummary } from '../components/PageSummaryBar';

const PHASE_ICONS: Record<SeasonPhase, typeof Sun> = { offseason: Sun, boost: Flame, peak: Zap };

const STRATEGIES_EXP_COLUMNS: MeasureDef[] = [
  { id: 'experiment_name', label: 'Experiment', group: 'Info' },
  { id: 'status', label: 'Status', group: 'Info' },
  { id: 'days_running', label: 'Days', group: 'Info' },
  { id: 'total_spend', label: 'Ads Spend', tip: MEASURE_TIPS.spend, group: 'Ads' },
  { id: 'total_orders', label: 'Ads Orders', tip: MEASURE_TIPS.orders, group: 'Ads' },
  { id: 'total_sales', label: 'Sales', group: 'PnL' },
  { id: 'conv_rate', label: 'Ads Conv%', tip: MEASURE_TIPS.conv_rate, group: 'Ads' },
  { id: 'cpc', label: 'Ads CPC', group: 'Ads' },
  { id: 'net_roas', label: 'Ads ROAS', group: 'Ads' },
  { id: 'organic_pct', label: 'Organic %', tip: 'Organic order percentage', group: 'SQP' },
  { id: 'unique_search_terms', label: 'Terms', group: 'SQP' },
  { id: 'outcome_score', label: 'Score', group: 'Info' },
];

const KPI_COL_META: Record<KpiColumnId, { label: string; right?: boolean }> = {
  spend:       { label: 'Ads Spend', right: true },
  orders:      { label: 'Ads Orders', right: true },
  sales:       { label: 'Sales', right: true },
  conv_rate:   { label: 'Ads Conv%', right: true },
  cpc:         { label: 'Ads CPC', right: true },
  net_roas:    { label: 'Ads ROAS' },
  search_terms: { label: 'Terms', right: true },
  organic_pct: { label: 'Organic %', right: true },
};

type PeriodMetrics = { spend: number; sales: number; orders: number; conv_rate: number; net_roas: number; cpc: number; organic_pct: number };

function resolveQuestionStatus(
  dataCheck: DataCheck,
  experiments: ExperimentTemplateRow[],
  conclusionCount: number,
  periodData: Record<string, PeriodMetrics>,
): QuestionStatus {
  const hasConcl = conclusionCount > 0;
  const hasCompleted = experiments.some(e => e.status !== 'ACTIVE');
  const checkMetric = (test: (e: ExperimentTemplateRow, pf?: PeriodMetrics) => boolean): QuestionStatus => {
    const has = experiments.some(e => test(e, periodData[e.experiment_id]));
    if (has && hasConcl) return 'answered';
    if (has) return 'has-data';
    return 'open';
  };
  switch (dataCheck) {
    case 'has_conclusions': return hasConcl ? 'answered' : experiments.length > 0 ? 'has-data' : 'open';
    case 'has_completed': return hasCompleted && hasConcl ? 'answered' : hasCompleted ? 'has-data' : 'open';
    case 'has_spend_data': return checkMetric((e, pf) => (pf?.spend ?? e.total_spend ?? 0) > 0);
    case 'has_orders_data': return checkMetric((e, pf) => (pf?.orders ?? e.total_orders ?? 0) > 0);
    case 'has_conv_data': return checkMetric((e, pf) => (pf?.conv_rate ?? e.conv_rate ?? 0) > 0);
    case 'has_organic_data': {
      const has = experiments.some(e => ['ACTIVE', 'COMPLETED'].includes(e.status));
      return has && hasConcl ? 'answered' : has ? 'has-data' : 'open';
    }
    case 'has_cpc_data': return checkMetric((e, pf) => (pf?.cpc ?? e.cpc ?? 0) > 0);
    case 'has_roas_data': return checkMetric((e, pf) => (pf?.net_roas ?? e.net_roas ?? 0) !== 0);
    case 'has_search_terms': return checkMetric(e => (e.unique_search_terms ?? 0) > 0);
    default: return 'open';
  }
}

function renderKpiCell(col: KpiColumnId, e: ExperimentTemplateRow, pf?: PeriodMetrics) {
  const spend = pf?.spend ?? e.total_spend ?? 0;
  const sales = pf?.sales ?? e.total_sales ?? 0;
  const orders = pf?.orders ?? e.total_orders ?? 0;
  const convRate = pf?.conv_rate ?? e.conv_rate ?? 0;
  const cpc = pf ? (pf.cpc > 0 ? pf.cpc : null) : e.cpc;
  const roas = pf?.net_roas ?? e.net_roas ?? 0;
  switch (col) {
    case 'spend': return <td key={col} className="px-3 py-2 text-right font-mono font-semibold">{fM(spend)}</td>;
    case 'sales': return <td key={col} className="px-3 py-2 text-right font-mono">{fM(sales)}</td>;
    case 'orders': return <td key={col} className="px-3 py-2 text-right font-mono">{fOrd(orders)}</td>;
    case 'conv_rate': return <td key={col} className="px-3 py-2 text-right font-mono">{fP(convRate)}</td>;
    case 'cpc': return <td key={col} className="px-3 py-2 text-right font-mono">{cpc != null ? fCpc(cpc) : '--'}</td>;
    case 'net_roas': return <td key={col} className="px-3 py-2"><RoasBadge value={roas} /></td>;
    case 'search_terms': return <td key={col} className="px-3 py-2 text-right font-mono text-faint">{e.unique_search_terms || '--'}</td>;
    case 'organic_pct': return <td key={col} className="px-3 py-2 text-right font-mono">{pf ? fP(pf.organic_pct) : '—'}</td>;
  }
}

const QUESTION_STATUS_CONFIG: Record<QuestionStatus, { icon: typeof CheckCircle2; color: string; label: string }> = {
  answered: { icon: CheckCircle2, color: 'text-emerald-400', label: 'Answered — see learnings below' },
  'has-data': { icon: CircleDot, color: 'text-amber-400', label: 'Data available — needs conclusion' },
  open: { icon: Circle, color: 'text-zinc-600', label: 'No data yet' },
};

export function StrategiesPage({ data }: { data: DashboardData }) {
  const { filters } = useFilters();
  const perfMaxDate = data._meta?.data_freshness?.performance_max_date || '';
  const [selectedStrategy, setSelectedStrategy] = useState<string | null>(null);
  const [expandedExps, setExpandedExps] = useState<Set<string>>(new Set());
  const [activePhase, setActivePhase] = useState<SeasonPhase | null>(null);
  const expSort = useSort('total_spend');
  const [stratCols, setStratCols] = useMeasureSelection('strategies_experiments', STRATEGIES_EXP_COLUMNS);
  const visibleStratCols = useMemo(() => STRATEGIES_EXP_COLUMNS.filter(c => stratCols.has(c.id)), [stratCols]);
  const holidays = data.holidays || [];
  const templates = useMemo(() => {
    let t = data.experiment_templates || [];
    if (filters.family) {
      t = t.filter(exp => experimentMatchesFamily(exp.experiment_name || exp.experiment_id, filters.family!));
    }
    if (filters.experiment) {
      t = t.filter(exp => exp.experiment_id === filters.experiment);
    }
    if (filters.keyword) {
      const expIdsWithKw = new Set(
        (data.keyword_product_map || [])
          .filter(k => k.search_term === filters.keyword && k.experiment_id)
          .map(k => k.experiment_id!)
      );
      if (expIdsWithKw.size > 0) t = t.filter(exp => expIdsWithKw.has(exp.experiment_id));
    }
    if (filters.product) {
      const expIdsWithProduct = new Set(
        (data.keyword_product_map || [])
          .filter(k => k.hero_asin === filters.product && k.experiment_id)
          .map(k => k.experiment_id!)
      );
      if (expIdsWithProduct.size > 0) t = t.filter(exp => expIdsWithProduct.has(exp.experiment_id));
    }
    return t;
  }, [data.experiment_templates, data.keyword_product_map, filters.family, filters.experiment, filters.keyword, filters.product]);

  // Auto-expand to show the selected experiment's strategy
  useEffect(() => {
    if (filters.experiment && templates.length) {
      const exp = templates.find(t => t.experiment_id === filters.experiment);
      if (exp) {
        setSelectedStrategy(exp.strategy_id);
        setExpandedExps(new Set([exp.experiment_id]));
      }
    }
  }, [filters.experiment, templates]);

  const conclusions = useMemo<BusinessConclusion[]>(() => {
    try { return JSON.parse(localStorage.getItem('businessConclusions') || '[]'); } catch { return []; }
  }, []);

  const pk = data.peak?.[0] ?? null;

  // Period-filtered metrics per experiment (from experiment_weekly) — non-trend, single period
  const periodFilteredByExp = useMemo(() => {
    const periodMode: PeriodMode = filters.periodMode;
    const sp = filters.specificPeriod;
    let rows = data.experiment_weekly || [];
    rows = filterBySeasonality(rows, 'week_start', filters.seasonality, pk);
    // Apply phase filter
    rows = filterByPhase(rows, 'week_start', activePhase, holidays);

    const byExp: Record<string, { spend: number; sales: number; orders: number; organic_units: number; conv_rate_sum: number; conv_rate_cnt: number; net_roas_sum: number; net_roas_cnt: number }> = {};

    if (periodMode === 'weeks') {
      const allWeeks = [...new Set(rows.map(r => r.week_start || ''))].filter(Boolean).sort();
      const keep = new Set(getPeriodsToInclude(sp, periodMode, allWeeks, 1));
      rows = rows.filter(r => keep.has(r.week_start || ''));
    } else {
      const periodKeys = [...new Set(rows.map(r => periodKey(r.week_start || '', periodMode)))].filter(Boolean).sort();
      const keep = new Set(getPeriodsToInclude(sp, periodMode, periodKeys, 1));
      rows = rows.filter(r => keep.has(periodKey(r.week_start || '', periodMode)));
    }

    rows.forEach(r => {
      const eid = r.experiment_id || '';
      if (!byExp[eid]) byExp[eid] = { spend: 0, sales: 0, orders: 0, organic_units: 0, conv_rate_sum: 0, conv_rate_cnt: 0, net_roas_sum: 0, net_roas_cnt: 0 };
      const d = byExp[eid];
      d.spend += r.ads_spend || 0;
      d.sales += r.sales || 0;
      d.orders += r.total_orders || 0;
      d.organic_units += r.organic_units || 0;
      if (r.conv_rate != null) { d.conv_rate_sum += r.conv_rate; d.conv_rate_cnt++; }
      if (r.net_roas != null) { d.net_roas_sum += r.net_roas; d.net_roas_cnt++; }
    });

    const out: Record<string, PeriodMetrics> = {};
    Object.entries(byExp).forEach(([eid, d]) => {
      const roas = d.spend > 0 ? (d.sales - d.spend) / d.spend : 0;
      out[eid] = {
        spend: d.spend,
        sales: d.sales,
        orders: d.orders,
        conv_rate: d.conv_rate_cnt ? d.conv_rate_sum / d.conv_rate_cnt : 0,
        net_roas: d.net_roas_cnt ? d.net_roas_sum / d.net_roas_cnt : roas,
        cpc: 0, // experiment_weekly has no clicks
        organic_pct: d.orders > 0 ? d.organic_units / d.orders : 0, // organic share of total orders
      };
    });
    return out;
  }, [data.experiment_weekly, pk, filters.periodMode, filters.specificPeriod, filters.seasonality, activePhase, holidays]);

  const periodLabel = useMemo(() => {
    const m = filters.periodMode;
    const sp = filters.specificPeriod;
    if (m === 'weeks') return sp ? `Week ending ${sp}` : 'Latest week';
    if (m === 'month') return sp ? `Month ${sp}` : 'Latest month';
    return sp ? `Year ${sp}` : 'Latest year';
  }, [filters.periodMode, filters.specificPeriod]);

  const strategies = useMemo(() => {
    const byStrat: Record<string, ExperimentTemplateRow[]> = {};
    templates.forEach(t => { (byStrat[t.strategy_id] = byStrat[t.strategy_id] || []).push(t); });
    return Object.entries(byStrat).map(([id, exps]) => {
      const active = exps.filter(e => e.status === 'ACTIVE');
      const completed = exps.filter(e => e.status !== 'ACTIVE');
      const pf = periodFilteredByExp;
      const totalSpend = exps.reduce((s, e) => s + (pf[e.experiment_id]?.spend ?? e.total_spend ?? 0), 0);
      const totalOrders = exps.reduce((s, e) => s + (pf[e.experiment_id]?.orders ?? e.total_orders ?? 0), 0);
      const totalSales = exps.reduce((s, e) => s + (pf[e.experiment_id]?.sales ?? e.total_sales ?? 0), 0);
      const avgRoas = totalSpend > 0 ? (totalSales - totalSpend) / totalSpend : 0;
      const avgConv = exps.filter(e => (pf[e.experiment_id]?.conv_rate ?? e.conv_rate) != null).reduce((s, e) => s + (pf[e.experiment_id]?.conv_rate ?? e.conv_rate ?? 0), 0) / Math.max(exps.filter(e => (pf[e.experiment_id]?.conv_rate ?? e.conv_rate) != null).length, 1);
      const meta = STRATEGY_META[id] || { ...DEFAULT_STRATEGY, label: id };
      return { ...meta, id, experiments: exps, active, completed, totalSpend, totalOrders, totalSales, avgRoas, avgConv };
    }).sort((a, b) => b.totalSpend - a.totalSpend);
  }, [templates, periodFilteredByExp]);

  // Pre-compute per-phase aggregates for each strategy (used in strategy cards)
  const phaseMetricsByStrategy = useMemo(() => {
    const result: Record<string, Record<SeasonPhase, { spend: number; sales: number; orders: number; roas: number; weeks: number }>> = {};
    const allRows = filterBySeasonality(data.experiment_weekly || [], 'week_start', filters.seasonality, pk);
    const templatesByStrat: Record<string, Set<string>> = {};
    templates.forEach(t => {
      if (!templatesByStrat[t.strategy_id]) templatesByStrat[t.strategy_id] = new Set();
      templatesByStrat[t.strategy_id].add(t.experiment_id);
    });
    Object.entries(templatesByStrat).forEach(([stratId, expIds]) => {
      const init = () => ({ spend: 0, sales: 0, orders: 0, roas: 0, weeks: 0 });
      const phases: Record<SeasonPhase, { spend: number; sales: number; orders: number; roas: number; weeks: number }> = { offseason: init(), boost: init(), peak: init() };
      const weeksSeen: Record<SeasonPhase, Set<string>> = { offseason: new Set(), boost: new Set(), peak: new Set() };
      allRows.filter(r => expIds.has(r.experiment_id)).forEach(r => {
        const phase = classifyPhase(r.week_start || '', holidays);
        phases[phase].spend += r.ads_spend || 0;
        phases[phase].sales += r.sales || 0;
        phases[phase].orders += r.total_orders || 0;
        weeksSeen[phase].add(r.week_start || '');
      });
      ALL_PHASES.forEach(p => {
        phases[p].weeks = weeksSeen[p].size;
        phases[p].roas = phases[p].spend > 0 ? (phases[p].sales - phases[p].spend) / phases[p].spend : 0;
      });
      result[stratId] = phases;
    });
    return result;
  }, [data.experiment_weekly, templates, pk, filters.seasonality, holidays]);

  // Phase summary for the selected strategy (KPI row)
  const selectedPhaseMetrics = useMemo(() => {
    if (!selectedStrategy) return null;
    return phaseMetricsByStrategy[selectedStrategy] || null;
  }, [selectedStrategy, phaseMetricsByStrategy]);

  const toggleExp = (id: string) => setExpandedExps(p => { const n = new Set(p); n.has(id) ? n.delete(id) : n.add(id); return n; });

  const selected = strategies.find(s => s.id === selectedStrategy);
  const trendMeasures = useMemo(() => {
    const ids = selected?.chartMeasureIds ?? ALL_CHART_MEASURES;
    return ids.filter((id): id is ChartMeasureId => CHART_MEASURE_META[id] != null);
  }, [selected]);
  const [selectedTrendMeasures, setSelectedTrendMeasures] = useState<Set<ChartMeasureId>>(new Set(['spend']));

  useEffect(() => {
    if (trendMeasures.length > 0) {
      const first = trendMeasures[0];
      setSelectedTrendMeasures(prev => {
        const hasValid = trendMeasures.some(m => prev.has(m));
        return hasValid ? prev : new Set([first]);
      });
    }
  }, [selectedStrategy, trendMeasures]);

  const toggleTrendMeasure = (m: ChartMeasureId) => {
    setSelectedTrendMeasures(prev => {
      const next = new Set(prev);
      if (next.has(m)) { if (next.size > 1) next.delete(m); }
      else next.add(m);
      return next;
    });
  };

  // Trend by period — aggregated across strategy experiments, uses periodTrend
  const strategyTrendData = useMemo(() => {
    if (!selected) return [] as { label: string; spend: number; sales: number; orders: number; conv_rate: number; net_roas: number; organic_pct: number; cpc: number }[];
    const expIds = new Set(selected.experiments.map(e => e.experiment_id));
    let rows = (data.experiment_weekly || []).filter(r => expIds.has(r.experiment_id));
    rows = filterBySeasonality(rows, 'week_start', filters.seasonality, pk);
    // Apply phase filter to trend
    rows = filterByPhase(rows, 'week_start', activePhase, holidays);
    const periodMode: PeriodMode = filters.periodMode;
    const pt = filters.periodTrend;
    const sp = filters.specificPeriod;

    const agg = () => ({
      spend: 0, sales: 0, orders: 0, clicks: 0,
      conv_rate_sum: 0, conv_rate_cnt: 0,
      net_roas_sum: 0, net_roas_cnt: 0,
      organic_pct_sum: 0, organic_pct_cnt: 0,
    });

    if (periodMode === 'weeks') {
      const allWeeks = [...new Set(rows.map(r => r.week_start || ''))].filter(Boolean).sort();
      const keep = new Set(getPeriodsToInclude(sp, periodMode, allWeeks, pt));
      const filtered = rows.filter(r => keep.has(r.week_start || ''));
      const byWeek: Record<string, ReturnType<typeof agg>> = {};
      filtered.forEach(r => {
        const k = r.week_start || '';
        if (!byWeek[k]) byWeek[k] = agg();
        const d = byWeek[k];
        d.spend += r.ads_spend || 0;
        d.sales += r.sales || 0;
        d.orders += r.total_orders || 0;
        // Derive clicks from conv_rate: clicks = ads_orders * 100 / conv_rate
        if (r.conv_rate && r.conv_rate > 0 && r.ads_orders) {
          d.clicks += (r.ads_orders * 100) / r.conv_rate;
        }
        if (r.conv_rate != null) { d.conv_rate_sum += r.conv_rate; d.conv_rate_cnt++; }
        if (r.net_roas != null) { d.net_roas_sum += r.net_roas; d.net_roas_cnt++; }
        if (r.organic_pct != null) { d.organic_pct_sum += r.organic_pct; d.organic_pct_cnt++; }
      });
      const weeks = Object.keys(byWeek).sort();
      return weeks.map(w => {
        const d = byWeek[w];
        const roas = d.spend > 0 ? (d.sales - d.spend) / d.spend : 0;
        return {
          label: weekRangeLabelCapped(w, perfMaxDate),
          spend: d.spend,
          sales: d.sales,
          orders: d.orders,
          conv_rate: d.conv_rate_cnt ? d.conv_rate_sum / d.conv_rate_cnt : 0,
          net_roas: d.net_roas_cnt ? d.net_roas_sum / d.net_roas_cnt : roas,
          organic_pct: d.organic_pct_cnt ? d.organic_pct_sum / d.organic_pct_cnt : 0,
          cpc: d.clicks > 0 ? d.spend / d.clicks : 0,
        };
      });
    }
    const byPeriod: Record<string, ReturnType<typeof agg>> = {};
    rows.forEach(r => {
      const k = periodKey(r.week_start || '', periodMode);
      if (!byPeriod[k]) byPeriod[k] = agg();
      const d = byPeriod[k];
      d.spend += r.ads_spend || 0;
      d.sales += r.sales || 0;
      d.orders += r.total_orders || 0;
      if (r.conv_rate && r.conv_rate > 0 && r.ads_orders) {
        d.clicks += (r.ads_orders * 100) / r.conv_rate;
      }
      if (r.conv_rate != null) { d.conv_rate_sum += r.conv_rate; d.conv_rate_cnt++; }
      if (r.net_roas != null) { d.net_roas_sum += r.net_roas; d.net_roas_cnt++; }
      if (r.organic_pct != null) { d.organic_pct_sum += r.organic_pct; d.organic_pct_cnt++; }
    });
    const periodKeys = Object.keys(byPeriod).sort();
    const keep = new Set(getPeriodsToInclude(sp, periodMode, periodKeys, pt));
    const entries = Object.entries(byPeriod).filter(([k]) => keep.has(k)).sort(([a], [b]) => a.localeCompare(b));
    return entries.map(([label, d]) => {
      const roas = d.spend > 0 ? (d.sales - d.spend) / d.spend : 0;
      return {
        label,
        spend: d.spend,
        sales: d.sales,
        orders: d.orders,
        conv_rate: d.conv_rate_cnt ? d.conv_rate_sum / d.conv_rate_cnt : 0,
        net_roas: d.net_roas_cnt ? d.net_roas_sum / d.net_roas_cnt : roas,
        organic_pct: d.organic_pct_cnt ? d.organic_pct_sum / d.organic_pct_cnt : 0,
        cpc: d.clicks > 0 ? d.spend / d.clicks : 0,
      };
    });
  }, [selected, data.experiment_weekly, data.peak, filters.periodMode, filters.periodTrend, filters.specificPeriod, filters.seasonality, activePhase, holidays]);

  const activeTrendMeasures = useMemo(() => [...selectedTrendMeasures], [selectedTrendMeasures]);

  const campaignsByExp = useMemo(() => {
    const map: Record<string, ExperimentCampaignRow[]> = {};
    (data.experiment_campaigns || []).forEach(c => {
      const eid = c.experiment_id || '';
      if (!map[eid]) map[eid] = [];
      map[eid].push(c);
    });
    Object.keys(map).forEach(eid => map[eid].sort((a, b) => b.spend - a.spend));
    return map;
  }, [data.experiment_campaigns]);

  const stratConclusions = useMemo(() =>
    conclusions.filter(c => c.status === 'approved'),
  [conclusions]);

  const kpiCols = useMemo<KpiColumnId[]>(() => selected?.kpiColumns ?? DEFAULT_KPI_COLUMNS, [selected]);

  const questionStatuses = useMemo(() => {
    if (!selected) return [];
    const relevantConclusions = stratConclusions.filter(c =>
      selected.experiments.some(e => e.experiment_id === (c.experiment_id || ''))
    ).length;
    return selected.learningQuestions.map(q => ({
      question: q,
      status: resolveQuestionStatus(q.dataCheck, selected.experiments, relevantConclusions, periodFilteredByExp),
    }));
  }, [selected, stratConclusions, periodFilteredByExp]);

  const qCounts = useMemo(() => {
    const answered = questionStatuses.filter(q => q.status === 'answered').length;
    const hasData = questionStatuses.filter(q => q.status === 'has-data').length;
    const open = questionStatuses.filter(q => q.status === 'open').length;
    return { answered, hasData, open, total: questionStatuses.length };
  }, [questionStatuses]);

  const strategyFilterItems = formatSectionFilters(filters);

  usePageSummary({ title: 'Strategies', items: [{ label: 'Strategy Management', value: 'Active' }] });
  return (
    <div className="animate-in">
      <div className="flex items-center gap-2 mb-1">
        <h1 className="text-[22px] font-extrabold tracking-tight">Experiment Strategies</h1>
        {strategyFilterItems.length > 0 && <FilterInfoIcon items={strategyFilterItems} />}
      </div>
      <p className="text-xs text-subtle mb-1">Learn from experiments to become a smarter advertiser</p>
      <p className="text-[10px] text-faint font-mono mb-5">Data: {periodLabel}</p>

      {/* Strategy Cards Grid */}
      <div className="grid grid-cols-4 gap-3 mb-6">
        {strategies.map(s => (
          <Card key={s.id}
            className={`!p-4 cursor-pointer transition-all hover:border-[${s.color}]/30 ${selectedStrategy === s.id ? `!border-[${s.color}]/50 ring-1 ring-[${s.color}]/20` : ''}`}
            onClick={() => setSelectedStrategy(selectedStrategy === s.id ? null : s.id)}>
            <div className="flex items-center gap-2 mb-2" style={{ color: s.color }}>
              {s.icon && createElement(s.icon, { size: 16 })}
              <span className="font-bold text-sm">{s.label}</span>
            </div>
            <div className="text-[10px] text-subtle leading-relaxed mb-3">{s.goal.slice(0, 100)}{s.goal.length > 100 ? '...' : ''}</div>
            <div className="grid grid-cols-3 gap-2 text-center">
              <div>
                <div className="text-[9px] text-faint uppercase">Active</div>
                <div className="font-mono font-bold text-sm" style={{ color: s.color }}>{s.active.length}</div>
              </div>
              <div>
                <div className="text-[9px] text-faint uppercase">Ads Spend</div>
                <div className="font-mono font-bold text-sm">{fM(s.totalSpend)}</div>
              </div>
              <div>
                <div className="text-[9px] text-faint uppercase">Ads ROAS</div>
                <div className={`font-mono font-bold text-sm ${s.avgRoas >= 1 ? 'text-emerald-400' : s.avgRoas >= 0 ? 'text-amber-400' : 'text-red-400'}`}>{fR(s.avgRoas)}</div>
              </div>
            </div>
            {/* Per-phase ROAS mini indicators */}
            {phaseMetricsByStrategy[s.id] && (
              <div className="flex items-center gap-3 mt-2.5 pt-2.5 border-t border-border-faint">
                {ALL_PHASES.map(p => {
                  const pm = phaseMetricsByStrategy[s.id][p];
                  const meta = PHASE_META[p];
                  return (
                    <div key={p} className="flex items-center gap-1 text-[9px]">
                      <span className="w-1.5 h-1.5 rounded-full" style={{ backgroundColor: pm.weeks > 0 ? meta.color : '#3f3f46' }} />
                      <span className="text-faint">{meta.label.split(' ')[0]}</span>
                      <span className="font-mono font-semibold" style={{ color: pm.weeks > 0 ? meta.color : '#52525b' }}>
                        {pm.weeks > 0 ? fR(pm.roas) : '—'}
                      </span>
                    </div>
                  );
                })}
              </div>
            )}
          </Card>
        ))}
      </div>

      {/* Selected Strategy Detail */}
      {selected && (
        <div className="mb-6 animate-in">
          <div className="flex items-start gap-4 mb-4">
            <div className="w-10 h-10 rounded-xl flex items-center justify-center" style={{ backgroundColor: selected.color + '20', color: selected.color }}>
              {selected.icon && createElement(selected.icon, { size: 16 })}
            </div>
            <div className="flex-1">
              <h2 className="text-lg font-bold" style={{ color: selected.color }}>{selected.label}</h2>
              <p className="text-xs text-subtle mt-1">{selected.goal}</p>
            </div>
          </div>

          {/* Phase Tab Bar */}
          <div className="flex items-center gap-1.5 mb-4">
            <button
              onClick={() => setActivePhase(null)}
              className="px-3 py-1.5 rounded-lg text-[11px] font-semibold border transition-all"
              style={{
                borderColor: !activePhase ? selected.color + '60' : 'rgba(63,63,70,.45)',
                background: !activePhase ? selected.color + '15' : 'transparent',
                color: !activePhase ? selected.color : '#71717a',
              }}
            >All Phases</button>
            {ALL_PHASES.map(p => {
              const meta = PHASE_META[p];
              const Icon = PHASE_ICONS[p];
              const isActive = activePhase === p;
              const phaseData = selectedPhaseMetrics?.[p];
              return (
                <button key={p} onClick={() => setActivePhase(isActive ? null : p)}
                  className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-[11px] font-semibold border transition-all"
                  style={{
                    borderColor: isActive ? meta.color + '60' : 'rgba(63,63,70,.45)',
                    background: isActive ? meta.color + '15' : 'transparent',
                    color: isActive ? meta.color : '#71717a',
                  }}
                >
                  <Icon size={12} />
                  {meta.label}
                  {phaseData && phaseData.weeks > 0 && (
                    <span className="text-[9px] font-mono opacity-70">{phaseData.weeks}w</span>
                  )}
                </button>
              );
            })}
          </div>

          {/* Phase Summary KPI Row */}
          {selectedPhaseMetrics && (
            <div className="grid grid-cols-3 gap-3 mb-4">
              {ALL_PHASES.map(p => {
                const pm = selectedPhaseMetrics[p];
                const meta = PHASE_META[p];
                const Icon = PHASE_ICONS[p];
                return (
                  <Card key={p} className={`!p-4 ${activePhase === p ? 'ring-1' : ''}`}
                    style={activePhase === p ? { borderColor: meta.color + '40' } : {}}
                  >
                    <div className="flex items-center gap-2 mb-3">
                      <div className="w-7 h-7 rounded-lg flex items-center justify-center" style={{ backgroundColor: meta.color + '20', color: meta.color }}>
                        <Icon size={14} />
                      </div>
                      <div>
                        <div className="text-xs font-bold" style={{ color: meta.color }}>{meta.label}</div>
                        <div className="text-[9px] text-faint font-mono">{pm.weeks} weeks data</div>
                      </div>
                    </div>
                    {pm.weeks > 0 ? (
                      <div className="grid grid-cols-3 gap-2 text-center">
                        <div>
                          <div className="text-[9px] text-faint uppercase">Ads Spend</div>
                          <div className="font-mono font-bold text-sm">{fM(pm.spend)}</div>
                        </div>
                        <div>
                          <div className="text-[9px] text-faint uppercase">Ads ROAS</div>
                          <div className={`font-mono font-bold text-sm ${pm.roas >= 1 ? 'text-emerald-400' : pm.roas >= 0 ? 'text-amber-400' : 'text-red-400'}`}>{fR(pm.roas)}</div>
                        </div>
                        <div>
                          <div className="text-[9px] text-faint uppercase">Ads Orders</div>
                          <div className="font-mono font-bold text-sm">{fOrd(pm.orders)}</div>
                        </div>
                      </div>
                    ) : (
                      <div className="text-[11px] text-faint italic text-center py-2">No data in this phase</div>
                    )}
                  </Card>
                );
              })}
            </div>
          )}

          {/* Questions to Answer — per-strategy, prominent */}
          <Card className="!p-5 mb-4" style={{ borderColor: selected.color + '30' }}>
            <div className="flex items-center gap-2 mb-3">
              <Lightbulb size={16} style={{ color: selected.color }} />
              <span className="text-sm font-bold" style={{ color: selected.color }}>Questions to Answer</span>
              {qCounts.total > 0 && (
                <span className="text-[10px] text-faint ml-auto font-mono">
                  {qCounts.answered} answered · {qCounts.hasData} in progress · {qCounts.open} open
                </span>
              )}
            </div>
            {qCounts.total > 0 && (
              <div className="flex h-1.5 rounded-full overflow-hidden bg-zinc-800/50 mb-4">
                {qCounts.answered > 0 && <div className="bg-emerald-500 transition-all" style={{ width: `${(qCounts.answered / qCounts.total) * 100}%` }} />}
                {qCounts.hasData > 0 && <div className="bg-amber-500 transition-all" style={{ width: `${(qCounts.hasData / qCounts.total) * 100}%` }} />}
              </div>
            )}
            <div className="space-y-2.5">
              {questionStatuses.map((qs, i) => {
                const cfg = QUESTION_STATUS_CONFIG[qs.status];
                return (
                  <div key={i} className="flex items-start gap-3">
                    {createElement(cfg.icon, { size: 14, className: `${cfg.color} mt-0.5 shrink-0` })}
                    <div className="flex-1">
                      <div className={`text-[11px] leading-relaxed ${qs.status === 'answered' ? 'text-zinc-300' : qs.status === 'has-data' ? 'text-zinc-400' : 'text-zinc-500'}`}>
                        {qs.question.text}
                      </div>
                      <div className="text-[9px] text-faint mt-0.5">{cfg.label}</div>
                    </div>
                  </div>
                );
              })}
            </div>
          </Card>

          <div className="grid grid-cols-2 gap-3.5 mb-5">
            {/* Expectation */}
            <Card className="!p-4">
              <div className="flex items-center gap-2 mb-2">
                <Target size={14} className="text-blue-400" />
                <span className="text-xs font-bold text-blue-400">Expected Outcome</span>
              </div>
              <p className="text-[11px] text-subtle leading-relaxed mb-3">{selected.expectedOutcome}</p>
              {strategyTrendData.length > 0 && (
                <div className="mt-2">
                  <div className="text-[9px] text-faint uppercase font-semibold mb-1">Weekly Trend</div>
                  <div className="flex items-center gap-3 mb-1.5">
                    {(selected.chartMeasureIds ?? ALL_CHART_MEASURES).slice(0, 2).map(mKey => {
                      const meta = CHART_MEASURE_META[mKey];
                      return meta ? (
                        <div key={mKey} className="flex items-center gap-1 text-[9px]">
                          <span className="w-1.5 h-1.5 rounded-full" style={{ backgroundColor: meta.color }} />
                          <span className="text-faint">{meta.label}</span>
                        </div>
                      ) : null;
                    })}
                  </div>
                  <ResponsiveContainer width="100%" height={80}>
                    <BarChart data={strategyTrendData} barCategoryGap="20%">
                      <XAxis dataKey="label" tick={{ fontSize: 8, fill: '#71717a' }} tickLine={false} axisLine={false} />
                      <Tooltip
                        contentStyle={CHART_TOOLTIP_STYLE(9)}
                        formatter={(v: any, name?: any) => {
                          const m = CHART_MEASURE_META[name as ChartMeasureId];
                          return [m ? m.fmt(Number(v ?? 0)) : String(v ?? 0), (m?.label || name) ?? ''];
                        }}
                      />
                      {(selected.chartMeasureIds ?? ALL_CHART_MEASURES).slice(0, 2).map(mKey => {
                        const meta = CHART_MEASURE_META[mKey];
                        return meta ? (
                          <Bar key={mKey} dataKey={mKey} radius={[2, 2, 0, 0]} fill={meta.color} opacity={0.7} />
                        ) : null;
                      })}
                    </BarChart>
                  </ResponsiveContainer>
                </div>
              )}
            </Card>

            {/* Key Metrics */}
            <Card className="!p-4">
              <div className="flex items-center gap-2 mb-2">
                <TrendingUp size={14} className="text-emerald-400" />
                <span className="text-xs font-bold text-emerald-400">Key Metrics to Track</span>
              </div>
              <div className="space-y-1.5">
                {selected.keyMetrics.map((m, i) => (
                  <div key={i} className="flex items-center gap-2 text-[11px] text-subtle">
                    <span className="w-1.5 h-1.5 rounded-full" style={{ backgroundColor: selected.color }} />
                    {m}
                  </div>
                ))}
              </div>
            </Card>
          </div>

          {/* Strategy Performance: Table + Trend by Period */}
          <div className="grid grid-cols-1 lg:grid-cols-[1fr,320px] gap-4 mb-4">
            <Card className="!p-4">
              <div className="text-xs font-bold mb-3">Strategy Performance by Experiment</div>
              {selected.experiments.filter(e => (periodFilteredByExp[e.experiment_id]?.spend ?? e.total_spend) > 0).length > 0 ? (
                <div className="overflow-x-auto">
                  <table className="w-full border-collapse text-xs">
                    <thead><tr>
                      <Th>Experiment</Th>
                      {kpiCols.map(col => {
                        const meta = KPI_COL_META[col];
                        return <Th key={col} right={meta.right}>{meta.label}</Th>;
                      })}
                    </tr></thead>
                    <tbody>
                      {selected.experiments
                        .filter(e => (periodFilteredByExp[e.experiment_id]?.spend ?? e.total_spend ?? 0) > 0)
                        .sort((a, b) => (periodFilteredByExp[b.experiment_id]?.spend ?? b.total_spend ?? 0) - (periodFilteredByExp[a.experiment_id]?.spend ?? a.total_spend ?? 0))
                        .map(e => (
                          <tr key={e.experiment_id} className="border-b border-border-faint last:border-b-0 hover:bg-white/[.02]">
                            <td className="px-3 py-2 font-semibold max-w-[180px] truncate" title={e.experiment_name}>{e.experiment_name}</td>
                            {kpiCols.map(col => renderKpiCell(col, e, periodFilteredByExp[e.experiment_id]))}
                          </tr>
                        ))}
                    </tbody>
                  </table>
                </div>
              ) : <Empty message="No spend data yet" />}
            </Card>

            <Card className="!p-4">
              <div className="text-xs font-bold mb-2">Trend by Period</div>
              <div className="flex flex-wrap gap-1 mb-3">
                {trendMeasures.map(m => {
                  const meta = CHART_MEASURE_META[m];
                  const active = selectedTrendMeasures.has(m);
                  return (
                    <button key={m} onClick={() => toggleTrendMeasure(m)}
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
              {strategyTrendData.length > 0 ? (
                <ResponsiveContainer width="100%" height={200}>
                  <BarChart data={strategyTrendData} barCategoryGap="20%">
                    <CartesianGrid {...CHART_GRID} />
                    <XAxis dataKey="label" tick={CHART_AXIS_TICK_LG} tickLine={false} axisLine={false} />
                    <YAxis yAxisId="left" tick={CHART_AXIS_TICK_LG} tickLine={false} axisLine={false}
                      tickFormatter={v => {
                        const meta = activeTrendMeasures[0] ? CHART_MEASURE_META[activeTrendMeasures[0]] : null;
                        return meta ? (meta.fmtShort ?? meta.fmt)(v) : String(v);
                      }} />
                    <Tooltip
                      contentStyle={CHART_TOOLTIP_STYLE(10)}
                      formatter={(v: number | undefined, name?: string) => {
                        const m = CHART_MEASURE_META[name as ChartMeasureId];
                        return [m ? m.fmt(v ?? 0) : String(v ?? 0), (m?.label || name) ?? ''];
                      }}
                    />
                    {activeTrendMeasures.map(mKey => {
                      const meta = CHART_MEASURE_META[mKey];
                      return (
                        <Bar key={mKey} yAxisId="left" dataKey={mKey} radius={[4, 4, 0, 0]} fill={meta.color} />
                      );
                    })}
                  </BarChart>
                </ResponsiveContainer>
              ) : <Empty message="No weekly data for period" />}
            </Card>
          </div>

          {/* Experiments Table */}
          <Card className="!p-0 overflow-hidden mb-4">
            <div className="px-4 py-3 border-b border-border flex items-center">
              <span className="text-xs font-bold">{selected.experiments.length} Experiments</span>
              <span className="text-[10px] text-faint ml-2">{selected.active.length} active · {selected.completed.length} completed</span>
              <div className="ml-auto"><MeasureSelector tableId="strategies_experiments" measures={STRATEGIES_EXP_COLUMNS} selected={stratCols} onSelectedChange={setStratCols} /></div>
            </div>
            <table className="w-full border-collapse text-xs">
              <thead><tr>
                <Th> </Th>
                {visibleStratCols.map(c => (
                  <SortTh key={c.id} k={c.id} sort={expSort.sort} toggle={expSort.toggle} right={c.id !== 'experiment_name' && c.id !== 'status'} tip={c.tip}>{c.label}</SortTh>
                ))}
              </tr></thead>
              <tbody>
                {expSort.sorted(selected.experiments.map(e => {
                  const pf = periodFilteredByExp[e.experiment_id];
                  return { ...e, total_spend: pf?.spend ?? e.total_spend, total_orders: pf?.orders ?? e.total_orders, total_sales: pf?.sales ?? e.total_sales, conv_rate: pf?.conv_rate ?? e.conv_rate, cpc: pf?.cpc ?? e.cpc, net_roas: pf?.net_roas ?? e.net_roas };
                })).map(e => {
                  const pf = periodFilteredByExp[e.experiment_id];
                  const spend = pf?.spend ?? e.total_spend ?? 0;
                  const orders = pf?.orders ?? e.total_orders ?? 0;
                  const sales = pf?.sales ?? e.total_sales ?? 0;
                  const convRate = pf?.conv_rate ?? e.conv_rate ?? 0;
                  const cpc = pf ? (pf.cpc > 0 ? pf.cpc : null) : e.cpc;
                  const roas = pf?.net_roas ?? e.net_roas ?? 0;
                  const isExp = expandedExps.has(e.experiment_id);
                    const cells: Record<string, React.ReactNode> = {
                    experiment_name: <td key="experiment_name" className="px-3 py-2 font-semibold max-w-[200px] truncate" title={e.experiment_name}>{e.experiment_name}</td>,
                    status: <td key="status" className="px-3 py-2"><StatusBadge status={e.status} /></td>,
                    days_running: <td key="days_running" className="px-3 py-2 text-right font-mono text-faint">{e.days_running}d</td>,
                    total_spend: <td key="total_spend" className="px-3 py-2 text-right font-mono font-semibold">{fM(spend)}</td>,
                    total_orders: <td key="total_orders" className="px-3 py-2 text-right font-mono">{fOrd(orders)}</td>,
                    total_sales: <td key="total_sales" className="px-3 py-2 text-right font-mono">{fM(sales)}</td>,
                    conv_rate: <td key="conv_rate" className="px-3 py-2 text-right font-mono">{fP(convRate)}</td>,
                    cpc: <td key="cpc" className="px-3 py-2 text-right font-mono">{cpc != null ? fCpc(cpc) : '--'}</td>,
                    net_roas: <td key="net_roas" className="px-3 py-2"><RoasBadge value={roas} /></td>,
                    organic_pct: <td key="organic_pct" className="px-3 py-2 text-right font-mono">{pf ? fP(pf.organic_pct) : '—'}</td>,
                    unique_search_terms: <td key="unique_search_terms" className="px-3 py-2 text-right font-mono text-faint">{e.unique_search_terms || '--'}</td>,
                    outcome_score: <td key="outcome_score" className="px-3 py-2">{e.outcome_score != null ? <ScoreBadge score={e.outcome_score} /> : <span className="text-faint">--</span>}</td>,
                  };
                  return (
                    <React.Fragment key={e.experiment_id}>
                    <tr onClick={() => toggleExp(e.experiment_id)}
                      className="border-b border-border-faint hover:bg-white/[.02] cursor-pointer transition-colors">
                      <td className="px-3 py-2 w-6">{isExp ? <ChevronDown size={12} className="text-faint" /> : <ChevronRight size={12} className="text-faint" />}</td>
                      {visibleStratCols.map(c => cells[c.id])}
                    </tr>
                    {isExp && (
                      <tr key={e.experiment_id + '-detail'}>
                        <td colSpan={visibleStratCols.length + 1} className="p-0">
                          <ExperimentDetail exp={e} conclusions={stratConclusions} campaigns={campaignsByExp[e.experiment_id] || []} periodFiltered={periodFilteredByExp[e.experiment_id]} />
                        </td>
                      </tr>
                    )}
                    </React.Fragment>
                  );
                })}
              </tbody>
            </table>
          </Card>

          {/* Approved Learnings for this strategy */}
          <Card className="!p-4">
            <div className="flex items-center gap-2 mb-3">
              <GraduationCap size={14} className="text-emerald-400" />
              <span className="text-xs font-bold text-emerald-400">Approved Business Learnings</span>
              <span className="text-[10px] text-faint ml-1">from all "{selected.label}" experiments</span>
            </div>
            {(() => {
              const relevant = stratConclusions.filter(c => {
                const expIds = selected.experiments.map(e => e.experiment_id);
                return expIds.includes(c.experiment_id || '');
              });
              if (!relevant.length) return <div className="text-[11px] text-faint italic">No approved learnings yet. Approve business conclusions on the Learn page.</div>;
              return (
                <div className="space-y-2">
                  {relevant.map((c, i) => (
                    <div key={i} className="flex items-start gap-2 p-2.5 rounded-lg bg-emerald-500/5 border border-emerald-500/10">
                      <CheckCircle2 size={13} className="text-emerald-400 mt-0.5 shrink-0" />
                      <div>
                        <div className="text-[11px] font-semibold">{c.conclusion}</div>
                        {c.recommendation && <div className="text-[10px] text-subtle mt-0.5">→ {c.recommendation}</div>}
                      </div>
                    </div>
                  ))}
                </div>
              );
            })()}
          </Card>
        </div>
      )}

      {!selectedStrategy && strategies.length > 0 && (
        <Card className="!p-6 text-center">
          <BookOpen size={24} className="mx-auto text-blue-400 mb-2" />
          <div className="text-sm font-bold mb-1">Select a strategy above to explore</div>
          <div className="text-xs text-subtle">See experiment performance, learnings, and recommendations for each advertising strategy</div>
        </Card>
      )}

      {strategies.length === 0 && <Empty message="No experiment template data" hint="Create experiments in the data-entry app to see strategies here." />}
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  const v = status === 'ACTIVE' ? 'green' : status === 'PAUSED' ? 'yellow' : status === 'COMPLETED' ? 'blue' : 'muted';
  return <Badge variant={v as any}>{status.toLowerCase()}</Badge>;
}

function ScoreBadge({ score }: { score: number }) {
  const color = score >= 7 ? 'text-emerald-400' : score >= 4 ? 'text-amber-400' : 'text-red-400';
  return <span className={`font-mono font-bold ${color}`}>{score.toFixed(1)}</span>;
}

function ExperimentDetail({ exp, conclusions, campaigns, periodFiltered }: { exp: ExperimentTemplateRow; conclusions: BusinessConclusion[]; campaigns: ExperimentCampaignRow[]; periodFiltered?: { spend: number; sales: number; orders: number; conv_rate: number; net_roas: number; cpc: number } }) {
  const expConclusions = conclusions.filter(c => c.experiment_id === exp.experiment_id);
  const spend = periodFiltered?.spend ?? exp.total_spend ?? 0;
  const orders = periodFiltered?.orders ?? exp.total_orders ?? 0;
  const sales = periodFiltered?.sales ?? exp.total_sales ?? 0;
  const convRate = periodFiltered?.conv_rate ?? exp.conv_rate ?? 0;
  const cpc = periodFiltered ? (periodFiltered.cpc > 0 ? periodFiltered.cpc : null) : exp.cpc;
  const roas = periodFiltered?.net_roas ?? exp.net_roas ?? 0;

  return (
    <div className="bg-inset px-4 py-3 border-b border-border-faint space-y-3">
      {/* Campaigns table */}
      {campaigns.length > 0 && (
        <div>
          <div className="text-[9px] text-faint uppercase font-semibold mb-2">Campaigns ({campaigns.length})</div>
          <div className="overflow-x-auto rounded-lg border border-border">
            <table className="w-full border-collapse text-xs">
              <thead><tr className="bg-inset">
                <Th>Campaign</Th>
                <Th>Type</Th>
                <Th right>Ads Spend</Th>
                <Th right>Ads Orders</Th>
                <Th right>Ads Clicks</Th>
                <Th right>Ads Impr</Th>
                <Th right>Ads CPC</Th>
                <Th right>Ads Conv%</Th>
              </tr></thead>
              <tbody>
                {campaigns.map(c => (
                  <tr key={c.campaign_id} className="border-t border-border-faint hover:bg-white/[.02]">
                    <td className="px-3 py-2 font-medium max-w-[200px] truncate" title={c.campaign_name}>{c.campaign_name}</td>
                    <td className="px-3 py-2 text-faint">{c.campaign_type || '--'}</td>
                    <td className="px-3 py-2 text-right font-mono font-semibold">{fM(c.spend)}</td>
                    <td className="px-3 py-2 text-right font-mono">{fOrd(c.orders)}</td>
                    <td className="px-3 py-2 text-right font-mono">{fClk(c.clicks)}</td>
                    <td className="px-3 py-2 text-right font-mono text-faint">{c.impressions?.toLocaleString() ?? '--'}</td>
                    <td className="px-3 py-2 text-right font-mono">{fCpc(c.clicks > 0 ? c.spend / c.clicks : 0)}</td>
                    <td className="px-3 py-2 text-right font-mono">{fP(c.clicks > 0 ? (c.orders / c.clicks) * 100 : 0)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Description & metadata */}
      <div className="grid grid-cols-3 gap-3">
        <div>
          <div className="text-[9px] text-faint uppercase font-semibold mb-1">Description</div>
          <div className="text-[11px] text-subtle">{exp.description || 'No description'}</div>
        </div>
        <div>
          <div className="text-[9px] text-faint uppercase font-semibold mb-1">Timeline</div>
          <div className="text-[11px] text-subtle">
            {exp.start_date && <span>Started: {exp.start_date}</span>}
            {exp.end_date && <span className="ml-3">Ended: {exp.end_date}</span>}
            {exp.baseline_days && <span className="ml-3">Baseline: {exp.baseline_days}d</span>}
          </div>
          {exp.lifecycle_stage && (
            <div className="text-[10px] text-faint mt-1">Stage: {exp.lifecycle_stage} {exp.graduation_confidence && `· Confidence: ${exp.graduation_confidence}`}</div>
          )}
        </div>
        <div>
          <div className="text-[9px] text-faint uppercase font-semibold mb-1">Outcome</div>
          {exp.outcome_tags && <div className="text-[11px] text-subtle">{exp.outcome_tags}</div>}
          {exp.outcome_notes && <div className="text-[10px] text-faint mt-1">{exp.outcome_notes}</div>}
          {!exp.outcome_tags && !exp.outcome_notes && <div className="text-[10px] text-faint italic">No outcome recorded</div>}
        </div>
      </div>

      {/* Performance metrics */}
      {(spend > 0 || (exp.total_spend ?? 0) > 0) && (
        <div className="grid grid-cols-6 gap-2">
          {[
            { label: 'Spend', val: fM(spend) },
            { label: 'Orders', val: fOrd(orders) },
            { label: 'Sales', val: fM(sales) },
            { label: 'Conv%', val: fP(convRate) },
            { label: 'CPC', val: cpc != null ? fCpc(cpc) : '--' },
            { label: 'Ads ROAS', val: fR(roas), color: (roas || 0) >= 1 ? 'text-emerald-400' : 'text-red-400' },
          ].map((m, i) => (
            <div key={i} className="text-center p-2 rounded-lg bg-zinc-800/40">
              <div className="text-[9px] text-faint uppercase">{m.label}</div>
              <div className={`font-mono text-sm font-bold ${m.color || ''}`}>{m.val}</div>
            </div>
          ))}
        </div>
      )}

      {/* Approved learnings */}
      {expConclusions.length > 0 && (
        <div>
          <div className="text-[9px] text-faint uppercase font-semibold mb-1.5 flex items-center gap-1">
            <Lightbulb size={10} className="text-amber-400" /> Learnings from this experiment
          </div>
          <div className="space-y-1.5">
            {expConclusions.map((c, i) => (
              <div key={i} className="flex items-start gap-2 text-[11px]">
                <CheckCircle2 size={11} className="text-emerald-400 mt-0.5 shrink-0" />
                <span className="text-subtle">{c.conclusion}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
