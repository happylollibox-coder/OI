import React, { useState, useMemo } from 'react';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, Legend, ComposedChart, Line, Cell } from 'recharts';
import { SeasonalReferenceLines, getXLabels } from '../components/SeasonalReferenceLines';
import type { DashboardData, FamilyName } from '../types';
import { FAMILIES } from '../types';
import { KpiCard, Card } from '../components/Card';
import { Badge, RoasBadge, ActionBadge } from '../components/Badge';
import { Empty } from '../components/Empty';
import { Th, SortTh, useSort, MEASURE_TIPS } from '../components/Tooltip';
import { MeasureSelector, useMeasureSelection, type MeasureDef } from '../components/MeasureSelector';
import { Section } from '../components/Section';
import { PageHeader } from '../components/PageHeader';
import { fM, fP, fOrd, fR, fClk, fCpc, famFromType, famFromProduct, weekRangeLabel, sqpCoverageWeeks, latestSqpWeek, periodKey, periodLabel, periodModeLabel, latestPeriodLabel, getPeriodsToInclude } from '../utils';
import { filterBySeasonality } from '../seasonality';
import { useFilters } from '../hooks/useFilters';
import { formatSectionFilters } from '../utils/filterUtils';
import { CHART_GRID, CHART_AXIS_TICK, CHART_AXIS_TICK_MD, CHART_AXIS_TICK_LG, CHART_TOOLTIP_STYLE } from '../chartTheme';
import { ChevronRight, ChevronDown, TrendingUp } from 'lucide-react';

type TrendMode = 'weeks' | 'month' | 'year' | 'peak';
import { MEASURE_META, type TrendMeasure } from '../constants';
import { usePageSummary } from '../components/PageSummaryBar';

const ZONE_LABELS: Record<string, string> = {
  upper_p1: 'P1 Top',
  mid_p1: 'P1 Mid',
  lower_p1: 'P1 Low',
  bottom_p1: 'P1 Bot',
  page_2_plus: 'P2+',
};
function zoneLabel(z: string): string { return ZONE_LABELS[z] || (z || '--'); }

export function FamilyPage({ data, family, onNavExperiment }: {
  data: DashboardData; family: FamilyName | null; onNavExperiment?: (eid: string) => void;
}) {
  const { filters, setFilter } = useFilters();
  const showAllFamilies = family == null;
  const info = family ? (FAMILIES[family] || { code: family, color: '#3b82f6' }) : { code: 'All', color: '#3b82f6' };
  const trendMode: TrendMode = filters.seasonality ? 'peak' : filters.periodMode === 'weeks' ? 'weeks' : filters.periodMode === 'month' ? 'month' : 'year';
  const [trendMeasure, setTrendMeasure] = useState<TrendMeasure>('sales');
  const [expandedKw, setExpandedKw] = useState<Set<string>>(new Set());
  const [sqpSearch, setSqpSearch] = useState('');
  const [expandedCollection, setExpandedCollection] = useState<FamilyName | null>(null);

  const selectedSqpTerm = filters.keyword;
  const setSelectedSqpTerm = (kw: string | null) => setFilter('keyword', kw);
  const selectedVariation = filters.product;
  const setSelectedVariation = (v: string | null) => setFilter('product', v);

  const colSort = useSort('orders');
  const sqpSort = useSort('totalOrders');
  const kwSort = useSort('marketVol');
  const FAMILY_COL_COLUMNS: MeasureDef[] = [
    { id: 'collection', label: 'Collection', group: 'Info' },
    { id: 'variations', label: 'Variations', group: 'Info' },
    { id: 'keywords', label: 'Keywords', tip: 'Total keywords tracked in SQP', group: 'SQP' },
    { id: 'heroKeywords', label: 'Hero KWs', tip: 'Keywords where a variation has the best conversion rate', group: 'SQP' },
    { id: 'orders', label: 'SQP Orders', tip: MEASURE_TIPS.orders, group: 'SQP' },
    { id: 'adsOrders', label: 'Ads Orders', group: 'Ads' },
    { id: 'organicUnits', label: 'SQP Org Ord', group: 'SQP' },
    { id: 'clicks', label: 'SQP Clicks', group: 'SQP' },
    { id: 'ctr', label: 'CTR%', group: 'SQP' },
    { id: 'convRate', label: 'SQP Conv%', group: 'SQP' },
    { id: 'impressions', label: 'Impr', group: 'SQP' },
    { id: 'bestShowRate', label: 'Best Share', tip: MEASURE_TIPS.show_rate, group: 'SQP' },
    { id: 'bestZone', label: 'Best Page', tip: MEASURE_TIPS.estimated_organic_rank, group: 'SQP' },
    { id: 'p1TopCount', label: 'P1 Top', group: 'SQP' },
    { id: 'p2PlusCount', label: 'P2+', group: 'SQP' },
  ];
  const FAMILY_ORG_COLUMNS: MeasureDef[] = [
    { id: 'term', label: 'Keyword', group: 'Info' },
    { id: 'marketVol', label: 'SQP Mkt Vol', tip: MEASURE_TIPS.market_volume, group: 'SQP' },
    { id: 'totalSpend', label: 'Ads Spend 60d', group: 'Ads' },
    { id: 'totalOrders', label: 'Ads Orders', group: 'Ads' },
    { id: 'organicInfo', label: 'Organic Signal', tip: MEASURE_TIPS.organic_lift, group: 'SQP' },
    { id: 'impShare', label: 'Imp Share', tip: MEASURE_TIPS.impression_share, group: 'Ads' },
    { id: 'avgRoas', label: 'Ads ROAS', group: 'Ads' },
    { id: 'bestAction', label: 'Action', group: 'Info' },
  ];
  const FAMILY_KW_COLUMNS: MeasureDef[] = [
    { id: 'term', label: 'Keyword', group: 'Info' },
    { id: 'marketVol', label: 'SQP Mkt Vol', tip: MEASURE_TIPS.market_volume, group: 'SQP' },
    { id: 'totalSpend', label: 'Ads Spend', group: 'Ads' },
    { id: 'totalOrders', label: 'Ads Orders', group: 'Ads' },
    { id: 'totalClicks', label: 'Ads Clicks', group: 'Ads' },
    { id: 'avgConv', label: 'Ads Conv%', group: 'Ads' },
    { id: 'impShare', label: 'Ads Imp Share', tip: MEASURE_TIPS.impression_share, group: 'Ads' },
    { id: 'avgRoas', label: 'Ads ROAS', group: 'Ads' },
    { id: 'hasOrganicLift', label: 'Organic', tip: MEASURE_TIPS.organic_lift, group: 'SQP' },
    { id: 'bestAction', label: 'Action', group: 'Info' },
  ];
  const FAMILY_SQP_COLUMNS: MeasureDef[] = [
    { id: 'search_term', label: 'Keyword', group: 'Info' },
    { id: 'asin', label: 'ASIN', group: 'Info' },
    { id: 'product_short_name', label: 'Product', group: 'Info' },
    { id: 'sqp_impressions', label: 'SQP Impr', group: 'SQP' },
    { id: 'sqp_clicks', label: 'SQP Clicks', group: 'SQP' },
    { id: 'sqp_conversions', label: 'SQP Conv', group: 'SQP' },
    { id: 'sqp_ctr_pct', label: 'SQP CTR', group: 'SQP' },
    { id: 'sqp_cvr_pct', label: 'SQP CVR', group: 'SQP' },
    { id: 'ads_spend', label: 'Ads Spend', group: 'Ads' },
    { id: 'ads_net_roas', label: 'Ads ROAS', group: 'Ads' },
  ];
  const FAMILY_DRIVER_COLUMNS: MeasureDef[] = [
    { id: 'search_term', label: 'Keyword', group: 'Info' },
    { id: 'product_short_name', label: 'Product', group: 'Info' },
    { id: 'spend', label: 'Ads Spend', group: 'Ads' },
    { id: 'orders', label: 'Ads Orders', group: 'Ads' },
    { id: 'conv_rate', label: 'Ads Conv%', group: 'Ads' },
    { id: 'net_roas', label: 'Ads ROAS', group: 'Ads' },
    { id: 'action', label: 'Action', group: 'Info' },
  ];
  const FAMILY_DRAIN_COLUMNS: MeasureDef[] = [
    { id: 'search_term', label: 'Keyword', group: 'Info' },
    { id: 'product_short_name', label: 'Product', group: 'Info' },
    { id: 'spend', label: 'Ads Spend', group: 'Ads' },
    { id: 'clicks', label: 'Ads Clicks', group: 'Ads' },
    { id: 'orders', label: 'Ads Orders', group: 'Ads' },
    { id: 'conv_rate', label: 'Ads Conv%', group: 'Ads' },
    { id: 'net_roas', label: 'Ads ROAS', group: 'Ads' },
    { id: 'organic', label: 'Organic Lift', tip: MEASURE_TIPS.organic_lift, group: 'SQP' },
    { id: 'action', label: 'Action', group: 'Info' },
  ];
  const [familyColCols, setFamilyColCols] = useMeasureSelection('family_collections', FAMILY_COL_COLUMNS);
  const [familyOrgCols, setFamilyOrgCols] = useMeasureSelection('family_organic_lift', FAMILY_ORG_COLUMNS);
  const [familyKwCols, setFamilyKwCols] = useMeasureSelection('family_search_terms', FAMILY_KW_COLUMNS);
  const [familySqpCols, setFamilySqpCols] = useMeasureSelection('family_sqp_perf', FAMILY_SQP_COLUMNS);
  const [familyDriverCols, setFamilyDriverCols] = useMeasureSelection('family_drivers', FAMILY_DRIVER_COLUMNS);
  const [familyDrainCols, setFamilyDrainCols] = useMeasureSelection('family_drains', FAMILY_DRAIN_COLUMNS);
  const visibleColCols = useMemo(() => FAMILY_COL_COLUMNS.filter(c => familyColCols.has(c.id)), [familyColCols]);
  const visibleOrgCols = useMemo(() => FAMILY_ORG_COLUMNS.filter(c => familyOrgCols.has(c.id)), [familyOrgCols]);
  const visibleKwCols = useMemo(() => FAMILY_KW_COLUMNS.filter(c => familyKwCols.has(c.id)), [familyKwCols]);
  const visibleSqpCols = useMemo(() => FAMILY_SQP_COLUMNS.filter(c => familySqpCols.has(c.id)), [familySqpCols]);
  const visibleDriverCols = useMemo(() => FAMILY_DRIVER_COLUMNS.filter(c => familyDriverCols.has(c.id)), [familyDriverCols]);
  const visibleDrainCols = useMemo(() => FAMILY_DRAIN_COLUMNS.filter(c => familyDrainCols.has(c.id)), [familyDrainCols]);
  const sqpWeeks = useMemo(() => sqpCoverageWeeks(data.sqp_coverage_weeks || []), [data.sqp_coverage_weeks]);
  const latestSqp = useMemo(() => latestSqpWeek(data.sqp_weekly || []), [data.sqp_weekly]);

  const sm = useMemo(() => {
    if (showAllFamilies) return null;
    return (data.summary || []).find(r => famFromType(r.product_type) === family);
  }, [data.summary, family, showAllFamilies]);

  const heroes = useMemo(() => {
    if (showAllFamilies) return (data.hero_asins || []).filter(h => famFromType(h.product_type) != null);
    return (data.hero_asins || []).filter(h => famFromType(h.product_type) === family || h.parent_name === family);
  }, [data.hero_asins, family, showAllFamilies]);

  const bestRoiProduct = useMemo(() => {
    if (heroes.length > 0) return { name: heroes[0].product_short_name || heroes[0].asin || '--', source: 'hero' as const };
    const byAsin = data.weekly_trends_by_asin || [];
    const candidates = showAllFamilies
      ? byAsin.filter(r => famFromType(r.product_type) != null)
      : byAsin.filter(r => famFromType(r.product_type) === family);
    if (!candidates.length) return null;
    const agg: Record<string, { name: string; sales: number; adCost: number }> = {};
    candidates.forEach(r => {
      if (!r.asin) return;
      if (!agg[r.asin]) agg[r.asin] = { name: r.product_short_name || r.asin, sales: 0, adCost: 0 };
      agg[r.asin].sales += r.sales || 0;
      agg[r.asin].adCost += r.ad_cost || 0;
    });
    let best: { name: string; roi: number } | null = null;
    Object.values(agg).forEach(a => {
      if (a.adCost <= 0) return;
      const roi = a.sales / a.adCost;
      if (!best || roi > best.roi) best = { name: a.name, roi };
    });
    return best ? { name: best.name, source: 'trend' as const } : null;
  }, [heroes, data.weekly_trends_by_asin, family, showAllFamilies]);

  const drivers = useMemo(() => {
    let d = showAllFamilies ? (data.drivers || []) : (data.drivers || []).filter(d => famFromType(d.product_type) === family);
    if (selectedSqpTerm) d = d.filter(r => r.search_term === selectedSqpTerm);
    return d;
  }, [data.drivers, family, selectedSqpTerm, showAllFamilies]);
  const tops = useMemo(() => drivers.filter(d => d.net_roas != null && d.net_roas >= 1).sort((a, b) => (b.orders || 0) - (a.orders || 0)).slice(0, 10), [drivers]);
  const drains = useMemo(() => drivers.filter(d => d.net_roas != null && d.net_roas < 1).sort((a, b) => (b.spend || 0) - (a.spend || 0)).slice(0, 15), [drivers]);

  const kwData = useMemo(() => {
    let rows = showAllFamilies ? (data.keyword_product_map || []).filter(k => famFromProduct(k.product_short_name) != null) : (data.keyword_product_map || []).filter(k => famFromProduct(k.product_short_name) === family);
    if (selectedSqpTerm) rows = rows.filter(k => k.search_term === selectedSqpTerm);
    return rows;
  }, [data.keyword_product_map, family, selectedSqpTerm, showAllFamilies]);

  // Group keywords by search_term, aggregate across experiments
  const kwGrouped = useMemo(() => {
    const map: Record<string, {
      term: string; totalSpend: number; totalOrders: number; totalClicks: number;
      totalImpressions: number; avgConv: number; avgRoas: number; marketVol: number;
      impShare: number; products: Set<string>; experiments: Set<string>;
      hasOrganicLift: boolean; organicInfo: string; heroMatch: boolean;
      bestAction: string; entries: typeof kwData;
    }> = {};
    kwData.forEach(k => {
      if (!map[k.search_term]) {
        map[k.search_term] = {
          term: k.search_term, totalSpend: 0, totalOrders: 0, totalClicks: 0,
          totalImpressions: 0, avgConv: 0, avgRoas: 0, marketVol: k.market_volume || 0,
          impShare: k.impression_share || 0, products: new Set(), experiments: new Set(),
          hasOrganicLift: false, organicInfo: '', heroMatch: true, bestAction: k.action,
          entries: [],
        };
      }
      const g = map[k.search_term];
      g.totalSpend += k.spend_60d || 0;
      g.totalOrders += k.orders_60d || 0;
      g.totalClicks += k.clicks_60d || 0;
      g.totalImpressions += k.impressions_60d || 0;
      g.products.add(k.product_short_name);
      if (k.experiment_id) g.experiments.add(k.experiment_id);
      if (!k.is_hero_match) g.heroMatch = false;
      g.entries.push(k);
      // Extract organic lift from reason
      const reason = k.reason || '';
      if (reason.includes('organic purchase') || reason.includes('organic lift') || reason.includes('SQP shows')) {
        g.hasOrganicLift = true;
        const m = reason.match(/SQP shows (\d+) organic/);
        if (m) g.organicInfo = `${m[1]} organic purchases (SQP)`;
      }
    });
    Object.values(map).forEach(g => {
      g.avgConv = g.totalClicks ? (g.totalOrders / g.totalClicks) * 100 : 0;
      g.avgRoas = g.totalSpend ? ((g.totalOrders * 24) - g.totalSpend) / g.totalSpend : 0;
    });
    return Object.values(map).sort((a, b) => b.marketVol - a.marketVol);
  }, [kwData]);

  // SQP data from hero_asins for this family
  const sqpData = useMemo(() => {
    return heroes.filter(h => (h.sqp_impressions || 0) > 0 || (h.sqp_clicks || 0) > 0 || (h.sqp_conversions || 0) > 0);
  }, [heroes]);

  // Keywords with organic lift potential
  const organicLiftKw = useMemo(() => kwGrouped.filter(k => k.hasOrganicLift), [kwGrouped]);

  const pk = data.peak?.[0] ?? null;

  // Aggregated KPIs — respects periodMode (weeks: latest week, month: latest month, year: selected year)
  const kpis = useMemo(() => {
    const mode = filters.periodMode;
    if (mode === 'weeks') {
      if (!showAllFamilies) return sm;
      // Aggregate all family summaries for "All Families" view
      const allSm = (data.summary || []).filter(r => famFromType(r.product_type) != null);
      if (!allSm.length) return null;
      const sales = allSm.reduce((s, r) => s + (r.sales_7d || 0), 0);
      const ad_cost = allSm.reduce((s, r) => s + (r.ad_cost_7d || 0), 0);
      const cogs = allSm.reduce((s, r) => s + (r.cogs_7d || 0), 0);
      const np = allSm.reduce((s, r) => s + (r.net_profit_7d || 0), 0);
      const orders = allSm.reduce((s, r) => s + (r.orders_7d || 0), 0);
      const net_roas = ad_cost ? (sales - cogs) / ad_cost : 0;
      const organic_pct = allSm.length ? allSm.reduce((s, r) => s + (r.organic_pct || 0), 0) / allSm.length : 0;
      const organic_units = Math.round(orders * organic_pct / 100);
      return { sales, ad_cost, cogs, net_profit: np, orders, net_roas, organic_pct, organic_units };
    }
    const mt = showAllFamilies ? (data.monthly_trends || []).filter(r => famFromType(r.product_type) != null) : (data.monthly_trends || []).filter(r => famFromType(r.product_type) === family);
    if (!mt.length) return sm;
    const allMonths = [...new Set(mt.map(r => (r.month_start || '').slice(0, 7)))].filter(Boolean).sort();
    let keep: Set<string>;
    if (mode === 'month') {
      const picked = getPeriodsToInclude(filters.specificPeriod, 'month', allMonths, 1);
      keep = new Set(picked);
    } else {
      const allYears = [...new Set(allMonths.map(m => m.slice(0, 4)))].sort();
      const picked = getPeriodsToInclude(filters.specificPeriod, 'year', allYears, 1);
      keep = new Set(allMonths.filter(m => picked.includes(m.slice(0, 4))));
    }
    const rows = mt.filter(r => keep.has((r.month_start || '').slice(0, 7)));
    if (!rows.length) return sm;
    const sales = rows.reduce((s, r) => s + (r.sales || 0), 0);
    const ad_cost = rows.reduce((s, r) => s + (r.ad_cost || 0), 0);
    const cogs = rows.reduce((s, r) => s + (r.cogs || 0), 0);
    const np = rows.reduce((s, r) => s + (r.net_profit || 0), 0);
    const orders = rows.reduce((s, r) => s + (r.orders || 0), 0);
    const cnt = rows.length;
    const net_roas = ad_cost ? (sales - cogs) / ad_cost : 0;
    const organic_pct = cnt ? rows.reduce((s, r) => s + (r.organic_pct || 0), 0) / cnt : 0;
    const organic_units = Math.round(orders * organic_pct / 100);
    return { sales, ad_cost, cogs, net_profit: np, orders, net_roas, organic_pct, organic_units };
  }, [sm, data.summary, data.monthly_trends, family, filters.periodMode, filters.specificPeriod, showAllFamilies]);

  // All SQP weekly data for this family (or all families when family=null) — unfiltered by period, used for variation list
  const sqpWeeklyRaw = useMemo(() => {
    if (showAllFamilies) return (data.sqp_weekly || []).filter(s => famFromType(s.product_type) != null);
    return (data.sqp_weekly || []).filter(s => famFromType(s.product_type) === family);
  }, [data.sqp_weekly, family, showAllFamilies]);

  // Period-filtered SQP data from ALL families — single period (latest or selected) for tables
  const sqpWeeklyAllFamilies = useMemo(() => {
    const allRaw = (data.sqp_weekly || []).filter(s => famFromType(s.product_type) != null);
    const seasonalityFiltered = filterBySeasonality(allRaw, 'week_start', filters.seasonality, pk);
    const sp = filters.specificPeriod;
    const mode = filters.periodMode;
    const allWeeks = [...new Set(seasonalityFiltered.map(r => r.week_start || ''))].filter(Boolean).sort();
    const count = 1; // always single period for tables (latest or selected)
    if (mode === 'weeks') {
      const keepWeeks = new Set(getPeriodsToInclude(sp, mode, allWeeks, count));
      return seasonalityFiltered.filter(r => keepWeeks.has(r.week_start || ''));
    }
    const allPeriods = [...new Set(allWeeks.map(w => periodKey(w, mode)))].sort();
    const keepPeriods = new Set(getPeriodsToInclude(sp, mode, allPeriods, count));
    return seasonalityFiltered.filter(r => keepPeriods.has(periodKey(r.week_start || '', mode)));
  }, [data.sqp_weekly, filters.specificPeriod, filters.seasonality, filters.periodMode, pk]);

  // Period-filtered SQP data — single period (latest or selected) for tables
  const sqpWeeklyAll = useMemo(() => {
    const seasonalityFiltered = filterBySeasonality(sqpWeeklyRaw, 'week_start', filters.seasonality, pk);
    const sp = filters.specificPeriod;
    const mode = filters.periodMode;
    const allWeeks = [...new Set(seasonalityFiltered.map(r => r.week_start || ''))].filter(Boolean).sort();
    const count = 1; // always single period for tables (latest or selected)
    if (mode === 'weeks') {
      const keepWeeks = new Set(getPeriodsToInclude(sp, mode, allWeeks, count));
      return seasonalityFiltered.filter(r => keepWeeks.has(r.week_start || ''));
    }
    const allPeriods = [...new Set(allWeeks.map(w => periodKey(w, mode)))].sort();
    const keepPeriods = new Set(getPeriodsToInclude(sp, mode, allPeriods, count));
    return seasonalityFiltered.filter(r => keepPeriods.has(periodKey(r.week_start || '', mode)));
  }, [sqpWeeklyRaw, filters.specificPeriod, filters.seasonality, filters.periodMode, pk]);

  // SQP data for trend charts only (multiple periods on x-axis)
  const sqpWeeklyAllForTrend = useMemo(() => {
    const seasonalityFiltered = filterBySeasonality(sqpWeeklyRaw, 'week_start', filters.seasonality, pk);
    const pt = filters.periodTrend;
    const sp = filters.specificPeriod;
    const mode = filters.periodMode;
    const allWeeks = [...new Set(seasonalityFiltered.map(r => r.week_start || ''))].filter(Boolean).sort();
    const count = sp ? 1 : pt;
    if (mode === 'weeks') {
      const keepWeeks = new Set(getPeriodsToInclude(sp, mode, allWeeks, count));
      return seasonalityFiltered.filter(r => keepWeeks.has(r.week_start || ''));
    }
    const allPeriods = [...new Set(allWeeks.map(w => periodKey(w, mode)))].sort();
    const keepPeriods = new Set(getPeriodsToInclude(sp, mode, allPeriods, count));
    return seasonalityFiltered.filter(r => keepPeriods.has(periodKey(r.week_start || '', mode)));
  }, [sqpWeeklyRaw, filters.periodTrend, filters.specificPeriod, filters.seasonality, filters.periodMode, pk]);

  const sqpWeeklyAllFamiliesForTrend = useMemo(() => {
    const allRaw = (data.sqp_weekly || []).filter(s => famFromType(s.product_type) != null);
    const seasonalityFiltered = filterBySeasonality(allRaw, 'week_start', filters.seasonality, pk);
    const pt = filters.periodTrend;
    const sp = filters.specificPeriod;
    const mode = filters.periodMode;
    const allWeeks = [...new Set(seasonalityFiltered.map(r => r.week_start || ''))].filter(Boolean).sort();
    const count = sp ? 1 : pt;
    if (mode === 'weeks') {
      const keepWeeks = new Set(getPeriodsToInclude(sp, mode, allWeeks, count));
      return seasonalityFiltered.filter(r => keepWeeks.has(r.week_start || ''));
    }
    const allPeriods = [...new Set(allWeeks.map(w => periodKey(w, mode)))].sort();
    const keepPeriods = new Set(getPeriodsToInclude(sp, mode, allPeriods, count));
    return seasonalityFiltered.filter(r => keepPeriods.has(periodKey(r.week_start || '', mode)));
  }, [data.sqp_weekly, filters.periodTrend, filters.specificPeriod, filters.seasonality, filters.periodMode, pk]);

  // SQP data for trend charts — filtered by variation when selected
  const sqpWeeklyForTrend = useMemo(() => {
    if (!selectedVariation) return sqpWeeklyAllForTrend;
    return sqpWeeklyAllForTrend.filter(r => r.asin === selectedVariation);
  }, [sqpWeeklyAllForTrend, selectedVariation]);

  // Available variations in this family (from ALL SQP data, not period-filtered)
  const variations = useMemo(() => {
    const map: Record<string, { asin: string; name: string; totalOrders: number }> = {};
    sqpWeeklyRaw.forEach(r => {
      if (!r.asin) return;
      if (!map[r.asin]) map[r.asin] = { asin: r.asin, name: r.product_short_name || r.asin, totalOrders: 0 };
      map[r.asin].totalOrders += r.orders || 0;
    });
    return Object.values(map).sort((a, b) => b.totalOrders - a.totalOrders);
  }, [sqpWeeklyRaw]);

  const variationStats = useMemo(() => {
    if (!sqpWeeklyAll.length) return [];
    let pool = sqpWeeklyAll;
    if (selectedSqpTerm) pool = pool.filter(r => r.search_term === selectedSqpTerm);

    // In weeks mode: latest week only. In month/year: aggregate entire period-filtered pool.
    let aggRows: typeof pool;
    if (filters.periodMode === 'weeks') {
      const latest = pool.reduce((max, r) => (r.week_start || '') > max ? (r.week_start || '') : max, '');
      aggRows = pool.filter(r => r.week_start === latest);
    } else {
      aggRows = pool;
    }

    const byAsin: Record<string, {
      asin: string; name: string; collection: string;
      impressions: number; clicks: number; orders: number; cartAdds: number;
      amazonImpressions: number; amazonClicks: number; amazonOrders: number;
      adsImpressions: number; adsClicks: number; adsOrders: number;
      keywords: number; bestShowRate: number; bestZone: string;
      p1TopCount: number; p1MidCount: number; p2PlusCount: number;
    }> = {};
    // Deduplicate keywords per ASIN (in month/year mode, same kw+asin appears many weeks)
    const seenKw = new Set<string>();
    aggRows.forEach(r => {
      if (!r.asin) return;
      if (!byAsin[r.asin]) byAsin[r.asin] = {
        asin: r.asin, name: r.product_short_name || r.asin, collection: famFromType(r.product_type) || r.product_type || '',
        impressions: 0, clicks: 0, orders: 0, cartAdds: 0,
        amazonImpressions: 0, amazonClicks: 0, amazonOrders: 0,
        adsImpressions: 0, adsClicks: 0, adsOrders: 0,
        keywords: 0, bestShowRate: 0, bestZone: '',
        p1TopCount: 0, p1MidCount: 0, p2PlusCount: 0,
      };
      const a = byAsin[r.asin];
      a.impressions += r.impressions || 0;
      a.clicks += r.clicks || 0;
      a.orders += r.orders || 0;
      a.cartAdds += r.cart_adds || 0;
      a.amazonImpressions += r.amazon_impressions || 0;
      a.amazonClicks += r.amazon_clicks || 0;
      a.amazonOrders += r.amazon_orders || 0;
      a.adsImpressions += r.ads_impressions || 0;
      a.adsClicks += r.ads_clicks || 0;
      a.adsOrders += r.ads_orders || 0;
      const kwKey = `${r.asin}::${r.search_term}`;
      if (!seenKw.has(kwKey)) { a.keywords += 1; seenKw.add(kwKey); }
      const sr = r.show_rate_pct || 0;
      if (sr > a.bestShowRate) { a.bestShowRate = sr; a.bestZone = r.organic_rank_zone || ''; }
      const z = r.organic_rank_zone || '';
      if (z === 'upper_p1') a.p1TopCount++;
      else if (z === 'mid_p1' || z === 'lower_p1' || z === 'bottom_p1') a.p1MidCount++;
      else if (z === 'page_2_plus') a.p2PlusCount++;
    });

    const kwByTerm: Record<string, { asin: string; convRate: number }[]> = {};
    aggRows.forEach(r => {
      if (!r.asin) return;
      const conv = (r.clicks || 0) > 0 ? (r.orders || 0) / (r.clicks || 1) : 0;
      if (!kwByTerm[r.search_term]) kwByTerm[r.search_term] = [];
      kwByTerm[r.search_term].push({ asin: r.asin, convRate: conv });
    });
    const heroCount: Record<string, number> = {};
    Object.values(kwByTerm).forEach(asins => {
      if (!asins.length) return;
      const best = asins.reduce((a, b) => b.convRate > a.convRate ? b : a, asins[0]);
      heroCount[best.asin] = (heroCount[best.asin] || 0) + 1;
    });

    return Object.values(byAsin).map(a => ({
      ...a,
      ctr: a.impressions > 0 ? (a.clicks / a.impressions) * 100 : 0,
      convRate: a.clicks > 0 ? (a.orders / a.clicks) * 100 : 0,
      organicUnits: Math.max(a.orders - a.adsOrders, 0),
      heroKeywords: heroCount[a.asin] || 0,
      totalKeywords: Object.keys(kwByTerm).length,
    })).sort((a, b) => b.orders - a.orders);
  }, [sqpWeeklyAll, selectedSqpTerm, filters.periodMode]);
  void variationStats; // reserved for future family-scoped variation view

  // Variation stats from ALL families — for Collections table with expandable variations
  const variationStatsAll = useMemo(() => {
    if (!sqpWeeklyAllFamilies.length) return [];
    let pool = sqpWeeklyAllFamilies;
    if (selectedSqpTerm) pool = pool.filter(r => r.search_term === selectedSqpTerm);
    let aggRows: typeof pool;
    if (filters.periodMode === 'weeks') {
      const latest = pool.reduce((max, r) => (r.week_start || '') > max ? (r.week_start || '') : max, '');
      aggRows = pool.filter(r => r.week_start === latest);
    } else {
      aggRows = pool;
    }
    const byAsin: Record<string, {
      asin: string; name: string; collection: string;
      impressions: number; clicks: number; orders: number; cartAdds: number;
      amazonImpressions: number; amazonClicks: number; amazonOrders: number;
      adsImpressions: number; adsClicks: number; adsOrders: number;
      keywords: number; bestShowRate: number; bestZone: string;
      p1TopCount: number; p1MidCount: number; p2PlusCount: number;
    }> = {};
    const seenKw = new Set<string>();
    aggRows.forEach(r => {
      if (!r.asin) return;
      const coll = famFromType(r.product_type) as FamilyName | null;
      if (!coll) return;
      if (!byAsin[r.asin]) byAsin[r.asin] = {
        asin: r.asin, name: r.product_short_name || r.asin, collection: coll,
        impressions: 0, clicks: 0, orders: 0, cartAdds: 0,
        amazonImpressions: 0, amazonClicks: 0, amazonOrders: 0,
        adsImpressions: 0, adsClicks: 0, adsOrders: 0,
        keywords: 0, bestShowRate: 0, bestZone: '',
        p1TopCount: 0, p1MidCount: 0, p2PlusCount: 0,
      };
      const a = byAsin[r.asin];
      a.impressions += r.impressions || 0;
      a.clicks += r.clicks || 0;
      a.orders += r.orders || 0;
      a.cartAdds += r.cart_adds || 0;
      a.amazonImpressions += r.amazon_impressions || 0;
      a.amazonClicks += r.amazon_clicks || 0;
      a.amazonOrders += r.amazon_orders || 0;
      a.adsImpressions += r.ads_impressions || 0;
      a.adsClicks += r.ads_clicks || 0;
      a.adsOrders += r.ads_orders || 0;
      const kwKey = `${r.asin}::${r.search_term}`;
      if (!seenKw.has(kwKey)) { a.keywords += 1; seenKw.add(kwKey); }
      const sr = r.show_rate_pct || 0;
      if (sr > a.bestShowRate) { a.bestShowRate = sr; a.bestZone = r.organic_rank_zone || ''; }
      const z = r.organic_rank_zone || '';
      if (z === 'upper_p1') a.p1TopCount++;
      else if (z === 'mid_p1' || z === 'lower_p1' || z === 'bottom_p1') a.p1MidCount++;
      else if (z === 'page_2_plus') a.p2PlusCount++;
    });
    const kwByTerm: Record<string, { asin: string; convRate: number }[]> = {};
    aggRows.forEach(r => {
      if (!r.asin) return;
      const conv = (r.clicks || 0) > 0 ? (r.orders || 0) / (r.clicks || 1) : 0;
      if (!kwByTerm[r.search_term]) kwByTerm[r.search_term] = [];
      kwByTerm[r.search_term].push({ asin: r.asin, convRate: conv });
    });
    const heroCount: Record<string, number> = {};
    Object.values(kwByTerm).forEach(asins => {
      if (!asins.length) return;
      const best = asins.reduce((a, b) => b.convRate > a.convRate ? b : a, asins[0]);
      heroCount[best.asin] = (heroCount[best.asin] || 0) + 1;
    });
    return Object.values(byAsin).map(a => ({
      ...a,
      ctr: a.impressions > 0 ? (a.clicks / a.impressions) * 100 : 0,
      convRate: a.clicks > 0 ? (a.orders / a.clicks) * 100 : 0,
      organicUnits: Math.max(a.orders - a.adsOrders, 0),
      heroKeywords: heroCount[a.asin] || 0,
      totalKeywords: Object.keys(kwByTerm).length,
    })).sort((a, b) => b.orders - a.orders);
  }, [sqpWeeklyAllFamilies, selectedSqpTerm, filters.periodMode]);

  // Collection-level stats (aggregated from variationStatsAll)
  const collectionStats = useMemo(() => {
    const COLLECTIONS: FamilyName[] = ['Lollibox', 'LolliME', 'Bottle', 'Fresh'];
    return COLLECTIONS.map(coll => {
      const vars = variationStatsAll.filter(v => v.collection === coll);
      if (!vars.length) return { collection: coll, variations: 0, orders: 0, clicks: 0, impressions: 0, adsOrders: 0, organicUnits: 0, keywords: 0, heroKeywords: 0, totalKeywords: 0, ctr: 0, convRate: 0, bestShowRate: 0, bestZone: '', p1TopCount: 0, p2PlusCount: 0 };
      return {
        collection: coll,
        variations: vars.length,
        orders: vars.reduce((s, v) => s + v.orders, 0),
        clicks: vars.reduce((s, v) => s + v.clicks, 0),
        impressions: vars.reduce((s, v) => s + v.impressions, 0),
        adsOrders: vars.reduce((s, v) => s + v.adsOrders, 0),
        organicUnits: vars.reduce((s, v) => s + v.organicUnits, 0),
        keywords: vars.reduce((s, v) => s + v.keywords, 0),
        heroKeywords: vars.reduce((s, v) => s + v.heroKeywords, 0),
        totalKeywords: vars[0]?.totalKeywords ?? 0,
        ctr: vars.reduce((s, v) => s + v.impressions, 0) > 0 ? (vars.reduce((s, v) => s + v.clicks, 0) / vars.reduce((s, v) => s + v.impressions, 0)) * 100 : 0,
        convRate: vars.reduce((s, v) => s + v.clicks, 0) > 0 ? (vars.reduce((s, v) => s + v.orders, 0) / vars.reduce((s, v) => s + v.clicks, 0)) * 100 : 0,
        bestShowRate: Math.max(...vars.map(v => v.bestShowRate)),
        bestZone: vars.reduce((best, v) => v.bestShowRate > best.bestShowRate ? v : best, vars[0]).bestZone,
        p1TopCount: vars.reduce((s, v) => s + v.p1TopCount, 0),
        p2PlusCount: vars.reduce((s, v) => s + v.p2PlusCount, 0),
      };
    }).filter(c => c.variations > 0).sort((a, b) => b.orders - a.orders);
  }, [variationStatsAll]);

  // Latest period value for display (actual date, not just "latest")
  const latestPeriodValue = useMemo(() => {
    const pool = sqpWeeklyAllFamilies.length ? sqpWeeklyAllFamilies : sqpWeeklyAll;
    if (!pool.length) return '';
    const weeks = [...new Set(pool.map(r => r.week_start || ''))].filter(Boolean).sort();
    if (!weeks.length) return '';
    const latestWeek = weeks[weeks.length - 1];
    if (filters.periodMode === 'weeks') return latestWeek;
    if (filters.periodMode === 'month') return latestWeek.slice(0, 7);
    return latestWeek.slice(0, 4);
  }, [sqpWeeklyAllFamilies, sqpWeeklyAll, filters.periodMode]);

  // Filtered SQP data based on selected variation
  const sqpWeekly = useMemo(() => {
    if (!selectedVariation) return sqpWeeklyAll;
    return sqpWeeklyAll.filter(r => r.asin === selectedVariation);
  }, [sqpWeeklyAll, selectedVariation]);

  // All SQP keywords — full 13-month list with period-filtered current measures + 13-month max values
  const sqpTopTerms = useMemo(() => {
    // Step 1: Build full keyword list + 13-month max values from ALL raw data (filtered by variation if selected)
    let rawSrc = selectedVariation ? sqpWeeklyRaw.filter(r => r.asin === selectedVariation) : sqpWeeklyRaw;
    if (selectedSqpTerm) rawSrc = rawSrc.filter(r => r.search_term === selectedSqpTerm);
    type TermEntry = { term: string; totalOrders: number; totalClicks: number; totalCartAdds: number; totalImpressions: number;
      latestAmazonImpressions: number; totalAdsClicks: number; totalAdsOrders: number; totalAdsImpressions: number;
      maxAmazonImpressions: number; maxConvRate: number;
      latestRank: number; latestZone: string; latestShowRate: number; latestCtr: number; latestConvRate: number;
      latestVariation: string; weeks: number };
    const byTerm: Record<string, TermEntry> = {};
    const makeTerm = (term: string): TermEntry => ({ term, totalOrders: 0, totalClicks: 0, totalCartAdds: 0, totalImpressions: 0,
      latestAmazonImpressions: 0, totalAdsClicks: 0, totalAdsOrders: 0, totalAdsImpressions: 0,
      maxAmazonImpressions: 0, maxConvRate: 0,
      latestRank: 0, latestZone: '', latestShowRate: 0, latestCtr: 0, latestConvRate: 0,
      latestVariation: '', weeks: 0 });

    // Collect all keywords from 13-month raw data + compute max values
    rawSrc.forEach(r => {
      if (!r.search_term) return;
      if (!byTerm[r.search_term]) byTerm[r.search_term] = makeTerm(r.search_term);
      const t = byTerm[r.search_term];
      t.maxAmazonImpressions = Math.max(t.maxAmazonImpressions, r.amazon_impressions || 0);
      const conv = (r.clicks || 0) > 0 ? ((r.orders || 0) / (r.clicks || 1)) * 100 : 0;
      t.maxConvRate = Math.max(t.maxConvRate, conv);
    });

    // Step 2: Overlay period-filtered measures from sqpWeekly
    const overallLatestWeek = sqpWeekly.reduce((max, r) => (r.week_start || '') > max ? (r.week_start || '') : max, '');
    sqpWeekly.forEach(r => {
      if (!r.search_term) return;
      if (selectedSqpTerm && r.search_term !== selectedSqpTerm) return;
      if (!byTerm[r.search_term]) byTerm[r.search_term] = makeTerm(r.search_term);
      const t = byTerm[r.search_term];
      t.totalOrders += r.orders || 0;
      t.totalClicks += r.clicks || 0;
      t.totalCartAdds += r.cart_adds || 0;
      t.totalImpressions += r.impressions || 0;
      t.totalAdsClicks += r.ads_clicks || 0;
      t.totalAdsOrders += r.ads_orders || 0;
      t.totalAdsImpressions += r.ads_impressions || 0;
      t.weeks += 1;
      if (r.week_start === overallLatestWeek) {
        t.latestAmazonImpressions = Math.max(t.latestAmazonImpressions, r.amazon_impressions || 0);
      }
    });

    // Step 3: Latest-week rank/zone/showRate/CTR/convRate from period-filtered data
    const sorted = [...sqpWeekly].sort((a, b) => (b.week_start || '').localeCompare(a.week_start || ''));
    const seen = new Set<string>();
    sorted.forEach(r => {
      const sr = r.show_rate_pct || 0;
      const key = selectedVariation ? r.search_term : `${r.search_term}__${r.asin}`;
      if (!seen.has(key) && byTerm[r.search_term]) {
        seen.add(key);
        const t = byTerm[r.search_term];
        if (sr > t.latestShowRate) {
          t.latestRank = sr > 0 ? Math.max(1, Math.round(48 * (1 - Math.min(sr, 100) / 100))) : 52;
          t.latestZone = r.organic_rank_zone;
          t.latestShowRate = sr;
          t.latestCtr = (r.impressions || 0) > 0 ? ((r.clicks || 0) / (r.impressions || 1)) * 100 : 0;
          t.latestConvRate = (r.clicks || 0) > 0 ? ((r.orders || 0) / (r.clicks || 1)) * 100 : 0;
          t.latestVariation = r.product_short_name || r.asin || '';
        }
      }
    });
    return Object.values(byTerm).map(t => ({
      ...t,
      adCtr: t.totalAdsImpressions > 0 ? (t.totalAdsClicks / t.totalAdsImpressions) * 100 : 0,
      adCvr: t.totalAdsClicks > 0 ? (t.totalAdsOrders / t.totalAdsClicks) * 100 : 0,
      periodConvRate: t.totalClicks > 0 ? (t.totalOrders / t.totalClicks) * 100 : (t.totalOrders > 0 ? 100 : 0),
    })).sort((a, b) => b.totalOrders - a.totalOrders);
  }, [sqpWeeklyRaw, sqpWeekly, selectedVariation, selectedSqpTerm]);

  // SQP trend — aggregated by periodMode, uses periodTrend for multiple periods. When keyword selected, use ALL families for that keyword (fixes organic=0 bug when keyword spans families).
  const sqpTermTrend = useMemo(() => {
    const mode = filters.periodMode;
    const src = selectedSqpTerm ? sqpWeeklyAllFamiliesForTrend : sqpWeeklyForTrend;
    const rows = selectedSqpTerm ? src.filter(r => r.search_term === selectedSqpTerm) : src;
    if (!rows.length) return [];

    type Bucket = { key: string; amazonVol: number; myOrders: number; adsOrders: number; bestShowRate: number; bestZone: string; totalImpr: number; totalClicks: number; totalOrders: number; variation: string };

    const makeBucket = (key: string): Bucket => ({ key, amazonVol: 0, myOrders: 0, adsOrders: 0, bestShowRate: 0, bestZone: '', totalImpr: 0, totalClicks: 0, totalOrders: 0, variation: selectedVariation ? '' : 'All' });

    const buckets: Record<string, Bucket> = {};
    rows.forEach(r => {
      const k = periodKey(r.week_start || '', mode);
      if (!buckets[k]) buckets[k] = makeBucket(k);
      const b = buckets[k];
      b.amazonVol = mode === 'weeks' ? Math.max(b.amazonVol, r.amazon_orders || 0) : b.amazonVol + (r.amazon_orders || 0);
      b.myOrders += r.orders || 0;
      b.adsOrders += r.ads_orders || 0;
      b.totalImpr += r.impressions || 0;
      b.totalClicks += r.clicks || 0;
      b.totalOrders += r.orders || 0;
      if (selectedVariation) b.variation = r.product_short_name || r.asin || '';
      const sr = r.show_rate_pct || 0;
      if (sr > b.bestShowRate) { b.bestShowRate = sr; b.bestZone = r.organic_rank_zone || ''; }
    });

    return Object.values(buckets).sort((a, b) => a.key.localeCompare(b.key))
      .map(b => ({
        label: periodLabel(b.key, mode),
        amazonVol: b.amazonVol,
        myOrders: b.myOrders,
        adsOrders: b.adsOrders,
        organicUnits: Math.max(b.myOrders - b.adsOrders, 0),
        showRate: b.bestShowRate,
        rank: b.bestShowRate > 0 ? Math.max(1, Math.round(48 * (1 - Math.min(b.bestShowRate, 100) / 100))) : 52,
        zone: b.bestZone,
        impressions: b.totalImpr,
        ctr: b.totalImpr > 0 ? (b.totalClicks / b.totalImpr) * 100 : 0,
        convRate: b.totalClicks > 0 ? (b.totalOrders / b.totalClicks) * 100 : 0,
        variation: b.variation,
      }));
  }, [sqpWeeklyForTrend, sqpWeeklyAllFamiliesForTrend, selectedSqpTerm, selectedVariation, filters.periodMode]);

  // Per-variation breakdown for selected keyword (shown when "All" is selected)
  // In weeks mode: latest week only. In month/year: aggregate by variation across the period.
  const sqpTermVariationBreakdown = useMemo(() => {
    if (!selectedSqpTerm || selectedVariation) return [];
    const rows = sqpWeeklyAll.filter(r => (showAllFamilies || famFromType(r.product_type) === family) && r.search_term === selectedSqpTerm);
    if (!rows.length) return [];

    if (filters.periodMode === 'weeks') {
      const latestWeek = rows.reduce((max, r) => (r.week_start || '') > max ? (r.week_start || '') : max, '');
      return rows.filter(r => r.week_start === latestWeek)
        .sort((a, b) => (b.show_rate_pct || 0) - (a.show_rate_pct || 0));
    }

    // Month/year mode: aggregate by ASIN across the period
    const byAsin: Record<string, {
      asin: string; product_short_name: string; impressions: number; clicks: number; orders: number;
      ads_orders: number; ads_clicks: number; ads_impressions: number;
      show_rate_pct: number; organic_rank_zone: string;
    }> = {};
    rows.forEach(r => {
      if (!r.asin) return;
      if (!byAsin[r.asin]) byAsin[r.asin] = {
        asin: r.asin, product_short_name: r.product_short_name || r.asin,
        impressions: 0, clicks: 0, orders: 0, ads_orders: 0, ads_clicks: 0, ads_impressions: 0,
        show_rate_pct: 0, organic_rank_zone: '',
      };
      const a = byAsin[r.asin];
      a.impressions += r.impressions || 0;
      a.clicks += r.clicks || 0;
      a.orders += r.orders || 0;
      a.ads_orders += r.ads_orders || 0;
      a.ads_clicks += r.ads_clicks || 0;
      a.ads_impressions += r.ads_impressions || 0;
      if ((r.show_rate_pct || 0) > a.show_rate_pct) {
        a.show_rate_pct = r.show_rate_pct || 0;
        a.organic_rank_zone = r.organic_rank_zone || '';
      }
    });
    return Object.values(byAsin)
      .sort((a, b) => (b.show_rate_pct || 0) - (a.show_rate_pct || 0));
  }, [sqpWeeklyAll, family, selectedSqpTerm, selectedVariation, filters.periodMode, showAllFamilies]);

  // Period label for Per-Variation Breakdown (actual date when weeks, or period when month/year)
  const breakdownPeriodLabel = useMemo(() => {
    if (!selectedSqpTerm || selectedVariation) return '';
    const rows = sqpWeeklyAll.filter(r => (showAllFamilies || famFromType(r.product_type) === family) && r.search_term === selectedSqpTerm);
    if (!rows.length) return '';
    if (filters.periodMode === 'weeks') {
      const latestWeek = rows.reduce((max, r) => (r.week_start || '') > max ? (r.week_start || '') : max, '');
      return latestPeriodLabel(latestWeek, 'weeks');
    }
    return latestPeriodLabel(latestPeriodValue, filters.periodMode);
  }, [sqpWeeklyAll, family, selectedSqpTerm, selectedVariation, filters.periodMode, latestPeriodValue, showAllFamilies]);

  const mKey = trendMeasure;
  const mMeta = MEASURE_META[mKey];
  const isAvg = mKey === 'net_roas' || mKey === 'organic_pct';

  const trendData = useMemo(() => {
    const getVal = (r: unknown) => ((r as Record<string, unknown>)[mKey] as number) || 0;
    const sp = filters.specificPeriod;
    const pt = filters.periodTrend;
    const count = pt; // Always show periodTrend periods in trend charts (specificPeriod anchors the end)
    const trendFamFilter = (r: { product_type?: string }) => showAllFamilies ? famFromType(r.product_type) != null : famFromType(r.product_type) === family;
    if (trendMode === 'weeks') {
      let rows = (data.weekly_trends || []).filter(w => trendFamFilter(w));
      rows = filterBySeasonality(rows, 'week_start', filters.seasonality, pk);
      rows = rows.sort((a, b) => (a.week_start || '').localeCompare(b.week_start || ''));
      const allWeeks = [...new Set(rows.map(r => r.week_start || '').filter(Boolean))].sort();
      const keep = new Set(getPeriodsToInclude(sp, 'weeks', allWeeks, count));
      const byWeek: Record<string, { sum: number; count: number }> = {};
      rows.filter(r => keep.has(r.week_start || '')).forEach(r => {
        const k = r.week_start || '';
        if (!byWeek[k]) byWeek[k] = { sum: 0, count: 0 };
        byWeek[k].sum += getVal(r);
        byWeek[k].count += 1;
      });
      return Object.entries(byWeek).sort(([a], [b]) => a.localeCompare(b))
        .map(([w, d]) => ({ label: weekRangeLabel(w), value: isAvg ? (d.count ? d.sum / d.count : 0) : d.sum, hasSqp: sqpWeeks.has(w) }));
    } else if (trendMode === 'month') {
      let rows = (data.monthly_trends || []).filter(m => trendFamFilter(m));
      rows = filterBySeasonality(rows, 'month_start', filters.seasonality, pk);
      const allMonths = [...new Set(rows.map(r => (r.month_start || '').slice(0, 7)))].sort();
      const keep = new Set(getPeriodsToInclude(sp, 'month', allMonths, count));
      const byMonth: Record<string, { sum: number; count: number }> = {};
      rows.filter(r => keep.has((r.month_start || '').slice(0, 7))).forEach(r => {
        const k = (r.month_start || '').slice(0, 7);
        if (!byMonth[k]) byMonth[k] = { sum: 0, count: 0 };
        byMonth[k].sum += getVal(r);
        byMonth[k].count += 1;
      });
      return Object.entries(byMonth).sort(([a], [b]) => a.localeCompare(b))
        .map(([m, d]) => ({ label: m, value: isAvg ? (d.count ? d.sum / d.count : 0) : d.sum, hasSqp: true }));
    } else if (trendMode === 'year') {
      let mo = (data.monthly_trends || []).filter(m => trendFamFilter(m));
      mo = filterBySeasonality(mo, 'month_start', filters.seasonality, pk);
      const byYr: Record<string, { sum: number; count: number }> = {};
      mo.forEach(m => { const y = (m.month_start || '').slice(0, 4); if (!byYr[y]) byYr[y] = { sum: 0, count: 0 }; byYr[y].sum += getVal(m); byYr[y].count += 1; });
      const years = Object.keys(byYr).sort();
      const keep = new Set(getPeriodsToInclude(sp, 'year', years, count));
      const entries = Object.entries(byYr).filter(([y]) => keep.has(y)).sort(([a], [b]) => a.localeCompare(b));
      return entries.map(([y, d]) => ({ label: y, value: isAvg ? (d.count ? d.sum / d.count : 0) : d.sum, hasSqp: true }));
    } else {
      // trendMode === 'peak': when seasonality filter is set, use it; else use local peak date range
      const aggWeeks = (src: typeof data.weekly_trends) => {
        const bw: Record<string, { sum: number; count: number }> = {};
        src.forEach(w => {
          const k = w.week_start || '';
          if (!bw[k]) bw[k] = { sum: 0, count: 0 };
          bw[k].sum += getVal(w);
          bw[k].count += 1;
        });
        return Object.entries(bw).sort(([a], [b]) => a.localeCompare(b))
          .map(([w, d]) => ({ label: weekRangeLabel(w), value: isAvg ? (d.count ? d.sum / d.count : 0) : d.sum, hasSqp: sqpWeeks.has(w) }));
      };
      if (filters.seasonality && pk) {
        let rows = (data.weekly_trends || []).filter(w => trendFamFilter(w));
        rows = filterBySeasonality(rows, 'week_start', filters.seasonality, pk);
        return aggWeeks(rows);
      }
      const peakPk = (data.peak || [])[0];
      if (!peakPk) return [];
      const ps = peakPk.peak_start || peakPk.pre_peak_start;
      const pe = peakPk.peak_end || peakPk.holiday_date;
      if (!ps || !pe) return [];
      const start = new Date(ps); start.setDate(start.getDate() - 30); const startS = start.toISOString().slice(0, 10);
      const end = new Date(pe); end.setDate(end.getDate() - 2); const endS = end.toISOString().slice(0, 10);
      return aggWeeks((data.weekly_trends || []).filter(w => trendFamFilter(w) && (w.week_start || '') >= startS && (w.week_start || '') <= endS));
    }
  }, [data, family, trendMode, mKey, isAvg, sqpWeeks, filters.specificPeriod, filters.periodTrend, filters.seasonality, pk, showAllFamilies]);

  const experiments = useMemo(() => {
    let exps = (data.experiments || []).filter(e => {
      if (showAllFamilies) return true;
      const n = (e.experiment_name || e.experiment_id || '').toLowerCase();
      if (family === 'Lollibox') return n.includes('lollibox') || n.includes('_box') || n.includes('box_') || n.includes('box-');
      if (family === 'LolliME') return n.includes('lollime') || n.includes('_me_') || n.includes('me-') || n.includes('mint') || n.includes('me_');
      if (family === 'Bottle') return n.includes('bottle') || n.includes('truth');
      if (family === 'Fresh') return n.includes('fresh');
      return false;
    });
    if (filters.experiment) exps = exps.filter(e => e.experiment_id === filters.experiment);
    return exps;
  }, [data.experiments, family, filters.experiment, showAllFamilies]);

  const budgetHealth = data.budget_health || [];

  const adsVsSqpTrend = useMemo(() => {
    const mode = filters.periodMode;
    const byPeriod: Record<string, { sqpImpr: number; adsImpr: number; sqpClicks: number; adsClicks: number; sqpOrders: number; adsOrders: number }> = {};
    let src = selectedVariation ? sqpWeeklyForTrend : sqpWeeklyAllForTrend;
    if (selectedSqpTerm) src = src.filter(r => r.search_term === selectedSqpTerm);
    src.forEach(r => {
      const k = periodKey(r.week_start || '', mode);
      if (!k) return;
      if (!byPeriod[k]) byPeriod[k] = { sqpImpr: 0, adsImpr: 0, sqpClicks: 0, adsClicks: 0, sqpOrders: 0, adsOrders: 0 };
      byPeriod[k].sqpImpr += r.impressions || 0;
      byPeriod[k].adsImpr += r.ads_impressions || 0;
      byPeriod[k].sqpClicks += r.clicks || 0;
      byPeriod[k].adsClicks += r.ads_clicks || 0;
      byPeriod[k].sqpOrders += r.orders || 0;
      byPeriod[k].adsOrders += r.ads_orders || 0;
    });
    return Object.entries(byPeriod)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([k, d]) => ({
        week: periodLabel(k, mode),
        sqpImpressions: d.sqpImpr,
        adsImpressions: d.adsImpr,
        sqpClicks: d.sqpClicks,
        adsClicks: d.adsClicks,
        sqpOrders: d.sqpOrders,
        adsOrders: d.adsOrders,
        adsShareOfImpr: d.sqpImpr > 0 ? Math.round(d.adsImpr / d.sqpImpr * 100) : 0,
      }));
  }, [sqpWeeklyAllForTrend, sqpWeeklyForTrend, selectedVariation, selectedSqpTerm, filters.periodMode]);

  const toggleKw = (term: string) => setExpandedKw(p => { const n = new Set(p); n.has(term) ? n.delete(term) : n.add(term); return n; });

  usePageSummary({ title: family || 'Family', items: [{ label: 'Family', value: family || 'All' }] });
  return (
    <div className="animate-in">
      <PageHeader title={showAllFamilies ? 'All Families' : family} subtitle={showAllFamilies ? 'SQP across all product families' : info.code + ' Product Family'} />

      {bestRoiProduct && (
        <div className="mb-3.5">
          <Badge variant="green" className="!text-xs !px-3 !py-1">⭐ Hero: {bestRoiProduct.name}</Badge>
          <span className="text-[11px] text-subtle ml-1.5">
            Best ROI in family{bestRoiProduct.source === 'trend' ? ' (from sales/ad ratio)' : ''}
          </span>
        </div>
      )}

      {/* KPIs */}
      <div className="grid grid-cols-5 gap-3.5 mb-6">
        {selectedSqpTerm ? (() => {
          // Keyword-specific KPIs from filtered SQP + ads data
          const sqpT = sqpTopTerms[0]; // only one term when keyword filtered
          const kwT = kwGrouped[0];
          const sqpOrders = sqpT?.totalOrders ?? 0;
          const sqpClicks = sqpT?.totalClicks ?? 0;
          const adsOrders = sqpT?.totalAdsOrders ?? kwT?.totalOrders ?? 0;
          const adsSpend = kwT?.totalSpend ?? 0;
          const organicUnits = Math.max(sqpOrders - adsOrders, 0);
          const organicPct = sqpOrders > 0 ? (organicUnits / sqpOrders) * 100 : 0;
          const showRate = sqpT?.latestShowRate ?? 0;
          const convRate = sqpClicks > 0 ? (sqpOrders / sqpClicks) * 100 : 0;
          return (<>
            <KpiCard label="Ads Spend" value={fM(adsSpend)} note="60d total for this keyword" />
            <KpiCard label="Ads Orders" value={fOrd(adsOrders)} note={`Conv% ${fP(convRate)}`} />
            <KpiCard label={`SQP Orders (${periodModeLabel(filters.periodMode, 'lower')})`} value={fOrd(sqpOrders)} note={`${fOrd(sqpClicks)} clicks`} />
            <KpiCard label="Organic %" value={fP(organicPct)} note={`${fOrd(sqpOrders)} total · ${fOrd(organicUnits)} organic`} />
            <KpiCard label="Show Rate" value={fP(showRate)} note={sqpT?.latestZone ? `Page: ${zoneLabel(sqpT.latestZone)}` : ''} />
          </>);
        })() : kpis ? (filters.periodMode === 'weeks' && sm ? (<>
          <KpiCard label="Net Profit" value={fM(sm.net_profit_7d)} note={`COGS ${fM(sm.cogs_7d)} · margin ${fP(sm.sales_7d ? (sm.net_profit_7d / sm.sales_7d) * 100 : 0)}`} />
          <KpiCard label="Ads Spend" value={fM(sm.ad_cost_7d)} />
          <KpiCard label="Ads ROAS" value={fR(sm.net_roas)} delta={sm.net_roas_prev ? ((sm.net_roas - sm.net_roas_prev) / Math.abs(sm.net_roas_prev)) * 100 : undefined} note={sm.net_roas >= 0 ? (sm.net_roas >= 1 ? 'Above break-even' : 'Profitable') : 'Below break-even'} />
          <KpiCard label="Organic %" value={fP(sm.organic_pct)} delta={sm.organic_pct_prev ? ((sm.organic_pct - sm.organic_pct_prev) / Math.abs(sm.organic_pct_prev)) * 100 : undefined} note={`${fOrd(sm.orders_7d)} total · ${fOrd(sm.organic_units_7d)} organic`} />
          <KpiCard label="Ads Orders 7d" value={fOrd(sm.orders_7d)} />
        </>) : (() => {
          const a = kpis as { net_profit: number; cogs: number; sales: number; ad_cost: number; orders: number; organic_units: number; net_roas: number; organic_pct: number };
          return (<>
            <KpiCard label="Net Profit" value={fM(a.net_profit)} note={`COGS ${fM(a.cogs)} · margin ${fP(a.sales ? (a.net_profit / a.sales) * 100 : 0)}`} />
            <KpiCard label="Ads Spend" value={fM(a.ad_cost)} />
            <KpiCard label="Ads ROAS" value={fR(a.net_roas)} note={a.net_roas >= 0 ? (a.net_roas >= 1 ? 'Above break-even' : 'Profitable') : 'Below break-even'} />
            <KpiCard label="Organic %" value={fP(a.organic_pct)} note={`${fOrd(a.orders)} total · ${fOrd(a.organic_units)} organic`} />
            <KpiCard label={`SQP Orders (${periodModeLabel(filters.periodMode, 'lower')})`} value={fOrd(a.orders)} />
          </>);
        })()) : (<Card className="col-span-5"><Empty message="No summary data" /></Card>)}
      </div>

      {/* Collections (expandable to show variations) */}
      {collectionStats.length > 0 && (
        <Section title="Collections" count={`${collectionStats.length} collections · ${latestPeriodLabel(latestPeriodValue, filters.periodMode)}`} filterItems={formatSectionFilters(filters)} headerRight={<MeasureSelector tableId="family_collections" measures={FAMILY_COL_COLUMNS} selected={familyColCols} onSelectedChange={setFamilyColCols} />}>
          <div className="border border-border rounded-xl bg-card overflow-hidden">
            <table className="w-full border-collapse text-xs">
              <thead><tr>
                {visibleColCols.map(c => (
                  <SortTh key={c.id} k={c.id} sort={colSort.sort} toggle={colSort.toggle} right={!['collection', 'variations', 'bestZone'].includes(c.id)} tip={c.tip}>{c.label}</SortTh>
                ))}
              </tr></thead>
              <tbody>
                {colSort.sorted(collectionStats).map(c => {
                  const isExpanded = expandedCollection === c.collection;
                  const vars = variationStatsAll.filter(v => v.collection === c.collection).sort((a, b) => b.orders - a.orders);
                  const zc = c.bestZone === 'upper_p1' ? 'text-emerald-400' : c.bestZone === 'mid_p1' ? 'text-blue-400' : c.bestZone === 'lower_p1' ? 'text-amber-400' : c.bestZone === 'page_2_plus' ? 'text-red-400' : 'text-zinc-400';
                  const heroRatio = c.totalKeywords > 0 ? c.heroKeywords / c.totalKeywords : 0;
                  const heroColor = heroRatio > 0.4 ? 'text-emerald-400' : heroRatio > 0.2 ? 'text-blue-400' : heroRatio > 0 ? 'text-amber-400' : 'text-zinc-500';
                  const collCells: Record<string, React.ReactNode> = {
                    collection: <td key="collection" className="px-3 py-2.5 font-semibold"><span className="inline-flex items-center gap-1">{isExpanded ? <ChevronDown size={14} className="text-faint" /> : <ChevronRight size={14} className="text-faint" />}<span style={{ color: FAMILIES[c.collection]?.color ?? '#fff' }}>{c.collection}</span></span></td>,
                    variations: <td key="variations" className="px-3 py-2.5 font-mono text-[10px] text-faint">{c.variations}</td>,
                    keywords: <td key="keywords" className="px-3 py-2.5 text-right font-mono">{c.keywords}</td>,
                    heroKeywords: <td key="heroKeywords" className={`px-3 py-2.5 text-right font-mono font-semibold ${heroColor}`}>{c.heroKeywords} <span className="text-[9px] text-faint font-normal">/ {c.totalKeywords}</span></td>,
                    orders: <td key="orders" className="px-3 py-2.5 text-right font-mono font-semibold">{c.orders}</td>,
                    adsOrders: <td key="adsOrders" className="px-3 py-2.5 text-right font-mono text-[11px]">{c.adsOrders}</td>,
                    organicUnits: <td key="organicUnits" className="px-3 py-2.5 text-right font-mono text-[11px] text-emerald-400">{c.organicUnits}</td>,
                    clicks: <td key="clicks" className="px-3 py-2.5 text-right font-mono text-[11px]">{c.clicks}</td>,
                    ctr: <td key="ctr" className="px-3 py-2.5 text-right font-mono text-[11px]">{fP(c.ctr)}</td>,
                    convRate: <td key="convRate" className="px-3 py-2.5 text-right font-mono text-[11px]">{fP(c.convRate)}</td>,
                    impressions: <td key="impressions" className="px-3 py-2.5 text-right font-mono text-[11px]">{c.impressions.toLocaleString()}</td>,
                    bestShowRate: <td key="bestShowRate" className="px-3 py-2.5 text-right font-mono text-[11px]">{fP(c.bestShowRate)}</td>,
                    bestZone: <td key="bestZone" className={`px-3 py-2.5 font-mono text-[11px] ${zc}`}>{zoneLabel(c.bestZone)}</td>,
                    p1TopCount: <td key="p1TopCount" className="px-3 py-2.5 text-right font-mono text-[11px] text-emerald-400">{c.p1TopCount}</td>,
                    p2PlusCount: <td key="p2PlusCount" className="px-3 py-2.5 text-right font-mono text-[11px] text-red-400">{c.p2PlusCount}</td>,
                  };
                  return (
                    <React.Fragment key={c.collection}>
                      <tr className="border-b border-border-faint hover:bg-white/[.02] cursor-pointer transition-colors"
                        onClick={() => setExpandedCollection(isExpanded ? null : c.collection)}>
                        {visibleColCols.map(col => collCells[col.id])}
                      </tr>
                      {isExpanded && vars.map((v) => {
                        const vZc = v.bestZone === 'upper_p1' ? 'text-emerald-400' : v.bestZone === 'mid_p1' ? 'text-blue-400' : v.bestZone === 'lower_p1' ? 'text-amber-400' : v.bestZone === 'page_2_plus' ? 'text-red-400' : 'text-zinc-400';
                        const vHeroRatio = v.totalKeywords > 0 ? v.heroKeywords / v.totalKeywords : 0;
                        const vHeroColor = vHeroRatio > 0.4 ? 'text-emerald-400' : vHeroRatio > 0.2 ? 'text-blue-400' : vHeroRatio > 0 ? 'text-amber-400' : 'text-zinc-500';
                        const varCells: Record<string, React.ReactNode> = {
                          collection: <td key="collection" className={`px-3 py-2 pl-8 font-medium ${selectedVariation === v.asin ? 'text-blue-400' : 'text-subtle'}`}><span className="text-zinc-500 mr-1">↳</span>{v.name}</td>,
                          variations: <td key="variations" className="px-3 py-2 font-mono text-[10px] text-faint">{v.asin}</td>,
                          keywords: <td key="keywords" className="px-3 py-2 text-right font-mono">{v.keywords}</td>,
                          heroKeywords: <td key="heroKeywords" className={`px-3 py-2 text-right font-mono font-semibold ${vHeroColor}`}>{v.heroKeywords} <span className="text-[9px] text-faint font-normal">/ {v.totalKeywords}</span></td>,
                          orders: <td key="orders" className="px-3 py-2 text-right font-mono font-semibold">{v.orders}</td>,
                          adsOrders: <td key="adsOrders" className="px-3 py-2 text-right font-mono text-[11px]">{v.adsOrders}</td>,
                          organicUnits: <td key="organicUnits" className="px-3 py-2 text-right font-mono text-[11px] text-emerald-400">{v.organicUnits}</td>,
                          clicks: <td key="clicks" className="px-3 py-2 text-right font-mono text-[11px]">{v.clicks}</td>,
                          ctr: <td key="ctr" className="px-3 py-2 text-right font-mono text-[11px]">{fP(v.ctr)}</td>,
                          convRate: <td key="convRate" className="px-3 py-2 text-right font-mono text-[11px]">{fP(v.convRate)}</td>,
                          impressions: <td key="impressions" className="px-3 py-2 text-right font-mono text-[11px]">{v.impressions.toLocaleString()}</td>,
                          bestShowRate: <td key="bestShowRate" className="px-3 py-2 text-right font-mono text-[11px]">{fP(v.bestShowRate)}</td>,
                          bestZone: <td key="bestZone" className={`px-3 py-2 font-mono text-[11px] ${vZc}`}>{zoneLabel(v.bestZone)}</td>,
                          p1TopCount: <td key="p1TopCount" className="px-3 py-2 text-right font-mono text-[11px] text-emerald-400">{v.p1TopCount}</td>,
                          p2PlusCount: <td key="p2PlusCount" className="px-3 py-2 text-right font-mono text-[11px] text-red-400">{v.p2PlusCount}</td>,
                        };
                        return (
                          <tr key={v.asin} className="border-b border-border-faint hover:bg-white/[.02] cursor-pointer bg-inset"
                            onClick={e => { e.stopPropagation(); setSelectedVariation(selectedVariation === v.asin ? null : v.asin); setFilter('family', v.collection as FamilyName); setSelectedSqpTerm(null); }}>
                            {visibleColCols.map(col => varCells[col.id])}
                          </tr>
                        );
                      })}
                    </React.Fragment>
                  );
                })}
              </tbody>
            </table>
          </div>
          {selectedVariation && (
            <div className="mt-2 text-[11px] text-blue-400 flex items-center gap-1.5">
              Filtering SQP data to: <strong>{variationStatsAll.find(v => v.asin === selectedVariation)?.name ?? variations.find(v => v.asin === selectedVariation)?.name}</strong>
              <button onClick={() => { setSelectedVariation(null); setSelectedSqpTerm(null); }} className="ml-1 px-2 py-0.5 rounded bg-zinc-800 text-faint hover:text-white transition-colors text-[10px]">Clear</button>
            </div>
          )}
        </Section>
      )}

      {/* WHERE TO INVEST: Organic Lift Opportunities */}
      {organicLiftKw.length > 0 && (
        <Section title="Organic Lift Opportunities" count={`${organicLiftKw.length} keywords with organic signal`} filterItems={formatSectionFilters(filters)} headerRight={<MeasureSelector tableId="family_organic_lift" measures={FAMILY_ORG_COLUMNS} selected={familyOrgCols} onSelectedChange={setFamilyOrgCols} />}>
          <div className="bg-emerald-500/5 border border-emerald-500/20 rounded-xl p-4 mb-4">
            <div className="flex items-center gap-2 mb-2">
              <TrendingUp size={16} className="text-emerald-400" />
              <span className="text-sm font-bold text-emerald-400">Strong organic lift potential</span>
            </div>
            <div className="text-[11px] text-subtle">These keywords show organic purchases beyond ad-driven orders (SQP data). Investing here amplifies organic visibility.</div>
          </div>
          <div className="border border-border rounded-xl bg-card overflow-hidden">
            <table className="w-full border-collapse text-xs">
              <thead><tr>
                {visibleOrgCols.map(c => (
                  <Th key={c.id} right={!['term', 'organicInfo', 'bestAction'].includes(c.id)} tip={c.tip}>{c.label}</Th>
                ))}
              </tr></thead>
              <tbody>
                {organicLiftKw.map((k, i) => {
                  const cells: Record<string, React.ReactNode> = {
                    term: <td key="term" className="px-3 py-2 font-semibold text-blue-400">{k.term}</td>,
                    marketVol: <td key="marketVol" className="px-3 py-2 font-mono text-[11px]">{k.marketVol ? Math.round(k.marketVol) + ' ord/wk' : '--'}</td>,
                    totalSpend: <td key="totalSpend" className="px-3 py-2 font-mono text-[11px]">{fM(k.totalSpend)}</td>,
                    totalOrders: <td key="totalOrders" className="px-3 py-2">{fOrd(k.totalOrders)}</td>,
                    organicInfo: <td key="organicInfo" className="px-3 py-2"><Badge variant="green" className="!text-[10px]">{k.organicInfo || 'Organic lift detected'}</Badge></td>,
                    impShare: <td key="impShare" className="px-3 py-2 font-mono text-[11px]">{k.impShare ? fP(k.impShare * 100) : '--'}</td>,
                    avgRoas: <td key="avgRoas" className="px-3 py-2"><RoasBadge value={k.avgRoas} /></td>,
                    bestAction: <td key="bestAction" className="px-3 py-2"><ActionBadge action={k.bestAction} /></td>,
                  };
                  return (
                    <tr key={i} className="border-b border-border-faint last:border-b-0 hover:bg-white/[.02]">
                      {visibleOrgCols.map(col => cells[col.id])}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </Section>
      )}

      {/* SQP Weekly Keyword Trends */}
      {sqpTopTerms.length > 0 && (
        <Section title={`Keyword ${periodModeLabel(filters.periodMode)} Trends (SQP)`} count={`${sqpTopTerms.length} keywords · ${sqpWeekly.length > 0 ? latestPeriodLabel([...sqpWeekly].sort((a, b) => (b.week_start || '').localeCompare(a.week_start || ''))[0]?.week_start || '', filters.periodMode) : '--'}`} filterItems={formatSectionFilters(filters)}>
          {/* Variation Filter */}
          {variations.length > 1 && (
            <div className="flex items-center gap-1.5 mb-3 flex-wrap">
              <span className="text-[10px] text-subtle uppercase font-semibold tracking-wider mr-1">Variation:</span>
              <button onClick={() => { setSelectedVariation(null); setSelectedSqpTerm(null); }}
                className={`px-3 py-1.5 rounded-lg text-xs font-semibold border transition-all ${!selectedVariation ? 'text-white border-transparent bg-blue-500/20 text-blue-400' : 'text-faint border-border hover:text-muted hover:border-border-strong'}`}>
                All ({variations.length})
              </button>
              {variations.map(v => (
                <button key={v.asin} onClick={() => { setSelectedVariation(v.asin); setSelectedSqpTerm(null); }}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold border transition-all ${selectedVariation === v.asin ? 'text-white border-transparent bg-blue-500/20 text-blue-400' : 'text-faint border-border hover:text-muted hover:border-border-strong'}`}>
                  {v.name} <span className="font-mono text-[10px] opacity-60">({v.totalOrders} ord)</span>
                </button>
              ))}
            </div>
          )}
          <div className="grid grid-cols-[640px_1fr] gap-4">
            {/* Keyword picker */}
            <div className="border border-border rounded-xl bg-card overflow-hidden flex flex-col" style={{ maxHeight: 600 }}>
              <div className="px-3 py-2 border-b border-border bg-inset flex items-center gap-2">
                <input
                  type="text" placeholder="Search keywords…" value={sqpSearch}
                  onChange={e => setSqpSearch(e.target.value)}
                  className="flex-1 bg-transparent border border-border rounded-lg px-2.5 py-1 text-[11px] text-white placeholder:text-faint focus:outline-none focus:border-blue-500"
                />
                {sqpSearch && <button onClick={() => setSqpSearch('')} className="text-faint hover:text-white text-xs">✕</button>}
                <span className="text-[10px] text-faint font-mono">{sqpTopTerms.length}</span>
              </div>
              <div className="overflow-y-auto flex-1">
              <table className="w-full border-collapse text-xs">
                <thead><tr>
                  <SortTh k="term" sort={sqpSort.sort} toggle={sqpSort.toggle}>Keyword</SortTh>
                  <SortTh k="totalOrders" sort={sqpSort.sort} toggle={sqpSort.toggle} tip="Total orders from SQP for this keyword (SQP)">SQP Orders</SortTh>
                  <SortTh k="totalClicks" sort={sqpSort.sort} toggle={sqpSort.toggle} tip="Total clicks for this keyword (SQP)">SQP Clicks</SortTh>
                  <SortTh k="totalCartAdds" sort={sqpSort.sort} toggle={sqpSort.toggle} tip="Add to cart count for this keyword (SQP)">Add to Cart</SortTh>
                  <SortTh k="totalAdsClicks" sort={sqpSort.sort} toggle={sqpSort.toggle} tip="Ad clicks for this keyword (SQP)">Ads Clicks</SortTh>
                  <SortTh k="totalAdsOrders" sort={sqpSort.sort} toggle={sqpSort.toggle} tip="Ad orders for this keyword (SQP)">Ads Orders</SortTh>
                  <SortTh k="adCtr" sort={sqpSort.sort} toggle={sqpSort.toggle} tip="Ad CTR: ad clicks / ad impressions (SQP)">Ad CTR</SortTh>
                  <SortTh k="adCvr" sort={sqpSort.sort} toggle={sqpSort.toggle} tip="Ad CVR: ad orders / ad clicks (SQP)">Ad CVR</SortTh>
                  <SortTh k="latestAmazonImpressions" sort={sqpSort.sort} toggle={sqpSort.toggle} tip="Amazon search impressions for this keyword (latest week) (SQP)">Amz Vol</SortTh>
                  <SortTh k="maxAmazonImpressions" sort={sqpSort.sort} toggle={sqpSort.toggle} tip="Peak Amazon search impressions across all 13 months (SQP)">Max Vol</SortTh>
                  <Th tip={MEASURE_TIPS.estimated_organic_rank}>Page</Th>
                  <SortTh k="latestShowRate" sort={sqpSort.sort} toggle={sqpSort.toggle} tip={MEASURE_TIPS.show_rate}>Share</SortTh>
                  <SortTh k="latestCtr" sort={sqpSort.sort} toggle={sqpSort.toggle} tip="Click-through rate: clicks / impressions — desire rate (SQP)">CTR</SortTh>
                  <SortTh k="periodConvRate" sort={sqpSort.sort} toggle={sqpSort.toggle} tip="Conversion rate: orders / clicks for selected period (SQP)">Conv</SortTh>
                  <SortTh k="maxConvRate" sort={sqpSort.sort} toggle={sqpSort.toggle} tip="Peak conversion rate across all 13 months (SQP)">Max Conv</SortTh>
                  {!selectedVariation && <Th tip="Best-ranking variation for this keyword (SQP)">Best ASIN</Th>}
                </tr></thead>
                <tbody>
                  {sqpSort.sorted(sqpSearch ? sqpTopTerms.filter(t => (t.term || '').toLowerCase().includes(sqpSearch.toLowerCase())) : sqpTopTerms).map((t, i) => {
                    const isSelected = selectedSqpTerm === t.term;
                    const zoneColor = t.latestZone === 'upper_p1' ? 'text-emerald-400' : t.latestZone === 'mid_p1' ? 'text-blue-400' : t.latestZone === 'lower_p1' ? 'text-amber-400' : t.latestZone === 'bottom_p1' ? 'text-orange-400' : t.latestZone === 'page_2_plus' ? 'text-red-400' : 'text-zinc-500';
                    return (
                      <tr key={i} onClick={() => setSelectedSqpTerm(isSelected ? null : t.term)}
                        className={`border-b border-border-faint cursor-pointer transition-colors ${isSelected ? 'bg-blue-500/10 border-l-2 border-l-blue-500' : 'hover:bg-white/[.02]'}`}>
                        <td className="px-2 py-1.5 font-semibold text-blue-400 max-w-[140px] truncate" title={t.term}>{t.term}</td>
                        <td className="px-2 py-1.5 font-mono text-[10px]">{t.totalOrders}</td>
                        <td className="px-2 py-1.5 font-mono text-[10px] text-faint">{t.totalClicks}</td>
                        <td className="px-2 py-1.5 font-mono text-[10px] text-faint">{t.totalCartAdds}</td>
                        <td className="px-2 py-1.5 font-mono text-[10px] text-faint">{t.totalAdsClicks}</td>
                        <td className="px-2 py-1.5 font-mono text-[10px] text-faint">{t.totalAdsOrders}</td>
                        <td className="px-2 py-1.5 font-mono text-[10px] text-faint">{t.totalAdsImpressions > 0 ? fP((t.totalAdsClicks / t.totalAdsImpressions) * 100) : '--'}</td>
                        <td className="px-2 py-1.5 font-mono text-[10px] text-faint">{t.totalAdsClicks > 0 ? fP((t.totalAdsOrders / t.totalAdsClicks) * 100) : '--'}</td>
                        <td className="px-2 py-1.5 font-mono text-[10px] text-faint">{t.latestAmazonImpressions ? t.latestAmazonImpressions.toLocaleString() : '--'}</td>
                        <td className="px-2 py-1.5 font-mono text-[10px] text-faint">{t.maxAmazonImpressions ? t.maxAmazonImpressions.toLocaleString() : '--'}</td>
                        <td className={`px-2 py-1.5 font-mono text-[10px] ${zoneColor}`} title={t.latestZone}>{t.latestZone ? zoneLabel(t.latestZone) : '--'}</td>
                        <td className="px-2 py-1.5 font-mono text-[10px]">{t.latestShowRate > 0 ? fP(t.latestShowRate) : '--'}</td>
                        <td className="px-2 py-1.5 font-mono text-[10px]">{t.latestCtr > 0 ? fP(t.latestCtr) : '--'}</td>
                        <td className="px-2 py-1.5 font-mono text-[10px]">{t.totalOrders > 0 ? fP(t.periodConvRate) : '--'}</td>
                        <td className="px-2 py-1.5 font-mono text-[10px] text-amber-400">{t.maxConvRate > 0 ? fP(t.maxConvRate) : '--'}</td>
                        {!selectedVariation && <td className="px-2 py-1.5 text-[9px] text-subtle truncate max-w-[80px]" title={t.latestVariation}>{t.latestVariation}</td>}
                      </tr>
                    );
                  })}
                </tbody>
              </table>
              </div>
            </div>
            {/* Trend charts for selected keyword */}
            <div>
              {sqpTermTrend.length > 0 ? (
                <div className="space-y-3">
                  <div className="text-xs font-bold text-blue-400 mb-1">
                    {selectedSqpTerm ? `"${selectedSqpTerm}"` : 'All Keywords'}
                    {selectedVariation && <span className="text-subtle font-normal ml-2">— {variations.find(v => v.asin === selectedVariation)?.name}</span>}
                    {!selectedVariation && <span className="text-subtle font-normal ml-2">— All variations{selectedSqpTerm ? ' (best show rate)' : ''}</span>}
                  </div>

                  {/* Per-variation breakdown table (only in "All" mode) */}
                  {!selectedVariation && sqpTermVariationBreakdown.length > 0 && (
                    <Card className="!p-3">
                      <div className="text-[10px] text-faint uppercase font-semibold mb-1.5">Per-Variation Breakdown ({breakdownPeriodLabel || '--'})</div>
                      <table className="w-full border-collapse text-[11px]">
                        <thead><tr className="text-subtle">
                          <th className="text-left py-1 px-2 font-semibold">Variation</th>
                          <th className="text-right py-1 px-2 font-semibold">Show Rate</th>
                          <th className="text-center py-1 px-2 font-semibold">Page</th>
                          <th className="text-right py-1 px-2 font-semibold">SQP Impr</th>
                          <th className="text-right py-1 px-2 font-semibold">SQP Clicks</th>
                          <th className="text-right py-1 px-2 font-semibold">CTR%</th>
                          <th className="text-right py-1 px-2 font-semibold">SQP Orders</th>
                          <th className="text-right py-1 px-2 font-semibold">SQP Conv%</th>
                          <th className="text-right py-1 px-2 font-semibold">Organic</th>
                        </tr></thead>
                        <tbody>
                          {sqpTermVariationBreakdown.map((r, i) => {
                            const zc = r.organic_rank_zone === 'upper_p1' ? 'text-emerald-400' : r.organic_rank_zone === 'mid_p1' ? 'text-blue-400' : r.organic_rank_zone === 'lower_p1' ? 'text-amber-400' : r.organic_rank_zone === 'page_2_plus' ? 'text-red-400' : 'text-zinc-400';
                            const orgOrd = Math.max((r.orders || 0) - (r.ads_orders || 0), 0);
                            const ctr = (r.impressions || 0) > 0 ? ((r.clicks || 0) / (r.impressions || 1)) * 100 : 0;
                            const conv = (r.clicks || 0) > 0 ? ((r.orders || 0) / (r.clicks || 1)) * 100 : 0;
                            return (
                              <tr key={i} className="border-t border-border-faint hover:bg-white/[.02] cursor-pointer" onClick={() => { setSelectedVariation(r.asin); setSelectedSqpTerm(selectedSqpTerm); }}>
                                <td className="py-1 px-2 font-semibold">{r.product_short_name || r.asin}</td>
                                <td className="py-1 px-2 text-right font-mono">{fP(r.show_rate_pct || 0)}</td>
                                <td className={`py-1 px-2 text-center font-mono ${zc}`}>{zoneLabel(r.organic_rank_zone)}</td>
                                <td className="py-1 px-2 text-right font-mono">{r.impressions}</td>
                                <td className="py-1 px-2 text-right font-mono">{r.clicks}</td>
                                <td className="py-1 px-2 text-right font-mono">{fP(ctr)}</td>
                                <td className="py-1 px-2 text-right font-mono">{r.orders}</td>
                                <td className="py-1 px-2 text-right font-mono">{fP(conv)}</td>
                                <td className="py-1 px-2 text-right font-mono text-emerald-400">{orgOrd}</td>
                              </tr>
                            );
                          })}
                        </tbody>
                      </table>
                    </Card>
                  )}

                  <Card className="!p-3">
                    <div className="text-[10px] text-faint uppercase font-semibold mb-1">Orders: You vs Amazon Total</div>
                    <ResponsiveContainer width="100%" height={140}>
                      <ComposedChart data={sqpTermTrend}>
                        <CartesianGrid {...CHART_GRID} />
                        <XAxis dataKey="label" tick={CHART_AXIS_TICK} tickLine={false} axisLine={false} />
                        <YAxis yAxisId="left" tick={CHART_AXIS_TICK_MD} tickLine={false} axisLine={false} />
                        <YAxis yAxisId="right" orientation="right" tick={CHART_AXIS_TICK_MD} tickLine={false} axisLine={false} />
                        <Tooltip contentStyle={CHART_TOOLTIP_STYLE()} />
                        <Legend wrapperStyle={{ fontSize: 9 }} />
                        <Bar yAxisId="right" dataKey="amazonVol" name="Amazon Total" fill="rgba(63,63,70,.4)" radius={[3, 3, 0, 0]} />
                        <Line yAxisId="left" type="monotone" dataKey="myOrders" name="My Orders" stroke="#3b82f6" strokeWidth={2} dot={{ r: 3 }} />
                        <Line yAxisId="left" type="monotone" dataKey="adsOrders" name="Ads Orders" stroke="#ef4444" strokeWidth={1.5} dot={{ r: 2 }} strokeDasharray="4 2" />
                        <Line yAxisId="left" type="monotone" dataKey="organicUnits" name="Organic Orders" stroke="#22c55e" strokeWidth={1.5} dot={{ r: 2 }} />
                        <SeasonalReferenceLines holidays={data.holidays || []} xLabels={getXLabels(sqpTermTrend)} yAxisId="left" />
                      </ComposedChart>
                    </ResponsiveContainer>
                  </Card>
                  <Card className="!p-3">
                    <div className="text-[10px] text-faint uppercase font-semibold mb-1">Show Rate % & Est. Page Position</div>
                    <ResponsiveContainer width="100%" height={120}>
                      <ComposedChart data={sqpTermTrend}>
                        <CartesianGrid {...CHART_GRID} />
                        <XAxis dataKey="label" tick={CHART_AXIS_TICK} tickLine={false} axisLine={false} />
                        <YAxis yAxisId="left" tick={CHART_AXIS_TICK_MD} tickLine={false} axisLine={false} tickFormatter={v => v + '%'} />
                        <YAxis yAxisId="right" orientation="right" reversed tick={CHART_AXIS_TICK_MD} tickLine={false} axisLine={false} tickFormatter={v => '#' + v} />
                        <Tooltip contentStyle={CHART_TOOLTIP_STYLE()} />
                        <Legend wrapperStyle={{ fontSize: 9 }} />
                        <Bar yAxisId="left" dataKey="showRate" name="Show Rate %" fill="#a855f7" radius={[3, 3, 0, 0]} />
                        <Line yAxisId="right" type="monotone" dataKey="rank" name="Est. Position" stroke="#f59e0b" strokeWidth={2} dot={{ r: 3 }} />
                        <SeasonalReferenceLines holidays={data.holidays || []} xLabels={getXLabels(sqpTermTrend)} yAxisId="left" />
                      </ComposedChart>
                    </ResponsiveContainer>
                  </Card>
                  <Card className="!p-3">
                    <div className="text-[10px] text-faint uppercase font-semibold mb-1">Click Rate (Desire) & Conversion Rate</div>
                    <ResponsiveContainer width="100%" height={120}>
                      <ComposedChart data={sqpTermTrend}>
                        <CartesianGrid {...CHART_GRID} />
                        <XAxis dataKey="label" tick={CHART_AXIS_TICK} tickLine={false} axisLine={false} />
                        <YAxis tick={CHART_AXIS_TICK_MD} tickLine={false} axisLine={false} tickFormatter={v => v + '%'} />
                        <Tooltip contentStyle={CHART_TOOLTIP_STYLE()} formatter={(v: number | undefined) => fP(v ?? 0)} />
                        <Legend wrapperStyle={{ fontSize: 9 }} />
                        <Bar dataKey="ctr" name="CTR % (Desire)" fill="#06b6d4" radius={[3, 3, 0, 0]} />
                        <Line type="monotone" dataKey="convRate" name="Conv %" stroke="#f43f5e" strokeWidth={2} dot={{ r: 3 }} />
                        <SeasonalReferenceLines holidays={data.holidays || []} xLabels={getXLabels(sqpTermTrend)} />
                      </ComposedChart>
                    </ResponsiveContainer>
                  </Card>
                </div>
              ) : (
                <div className="h-full flex items-center justify-center border border-border rounded-xl bg-card">
                  <div className="text-center p-8">
                    <div className="text-faint text-sm mb-1">No SQP data</div>
                    <div className="text-[11px] text-subtle">No SQP data available for this period and filters</div>
                  </div>
                </div>
              )}
            </div>
          </div>

          {/* Ads vs SQP Impressions Correlation */}
          {adsVsSqpTrend.length > 0 && (
            <div className="mt-4">
              <div className="text-xs font-bold mb-2 tracking-tight">Ads vs SQP Impressions Correlation <span className="font-normal text-faint">— {periodModeLabel(filters.periodMode, 'lower')}{selectedSqpTerm ? ` · filtered: "${selectedSqpTerm}"` : ''}</span></div>
              <div className="grid grid-cols-2 gap-3">
                <Card className="!p-3">
                  <div className="text-[10px] text-faint uppercase font-semibold mb-1">Impressions: Ads vs SQP (Your Listings)</div>
                  <ResponsiveContainer width="100%" height={160}>
                    <ComposedChart data={adsVsSqpTrend}>
                      <CartesianGrid {...CHART_GRID} />
                      <XAxis dataKey="week" tick={CHART_AXIS_TICK} tickLine={false} axisLine={false} />
                      <YAxis yAxisId="impr" tick={CHART_AXIS_TICK_MD} tickLine={false} axisLine={false} tickFormatter={(v: number) => v >= 1000 ? (v / 1000).toFixed(0) + 'k' : String(v)} />
                      <YAxis yAxisId="pct" orientation="right" tick={CHART_AXIS_TICK_MD} tickLine={false} axisLine={false} tickFormatter={(v: number) => v + '%'} />
                      <Tooltip contentStyle={CHART_TOOLTIP_STYLE()}
                        formatter={(v: number | undefined, name?: string) => name === 'Ads % of SQP' ? (v ?? 0) + '%' : (v ?? 0).toLocaleString()} />
                      <Legend wrapperStyle={{ fontSize: 9 }} />
                      <Bar yAxisId="impr" dataKey="sqpImpressions" name="SQP Impressions" fill="#8b5cf6" radius={[3, 3, 0, 0]} />
                      <Bar yAxisId="impr" dataKey="adsImpressions" name="Ads Impressions" fill="#3b82f6" radius={[3, 3, 0, 0]} />
                      <Line yAxisId="pct" type="monotone" dataKey="adsShareOfImpr" name="Ads % of SQP" stroke="#f59e0b" strokeWidth={2} dot={{ r: 3, fill: '#f59e0b' }} />
                    </ComposedChart>
                  </ResponsiveContainer>
                </Card>
                <Card className="!p-3">
                  <div className="text-[10px] text-faint uppercase font-semibold mb-1">Orders: Ads vs SQP (Total)</div>
                  <ResponsiveContainer width="100%" height={160}>
                    <ComposedChart data={adsVsSqpTrend}>
                      <CartesianGrid {...CHART_GRID} />
                      <XAxis dataKey="week" tick={CHART_AXIS_TICK} tickLine={false} axisLine={false} />
                      <YAxis tick={CHART_AXIS_TICK_MD} tickLine={false} axisLine={false} />
                      <Tooltip contentStyle={CHART_TOOLTIP_STYLE()} />
                      <Legend wrapperStyle={{ fontSize: 9 }} />
                      <Bar dataKey="sqpOrders" name="SQP Total Orders" fill="#10b981" radius={[3, 3, 0, 0]} />
                      <Bar dataKey="adsOrders" name="Ads Orders" fill="#ef4444" radius={[3, 3, 0, 0]} />
                      <Bar dataKey="sqpClicks" name="SQP Clicks" fill="#06b6d480" radius={[3, 3, 0, 0]} />
                      <Bar dataKey="adsClicks" name="Ads Clicks" fill="#f59e0b80" radius={[3, 3, 0, 0]} />
                    </ComposedChart>
                  </ResponsiveContainer>
                </Card>
              </div>
            </div>
          )}
        </Section>
      )}

      {/* Search Terms & SQP Detail */}
      <Section title="Search Terms" count={`${kwGrouped.length} keywords`} filterItems={formatSectionFilters(filters)} headerRight={<MeasureSelector tableId="family_search_terms" measures={FAMILY_KW_COLUMNS} selected={familyKwCols} onSelectedChange={setFamilyKwCols} />}>
        <div className="border border-border rounded-xl bg-card overflow-hidden">
          <table className="w-full border-collapse text-xs">
            <thead><tr>
              <Th> </Th>
              {visibleKwCols.map(c => (
                <SortTh key={c.id} k={c.id} sort={kwSort.sort} toggle={kwSort.toggle} right={!['term', 'hasOrganicLift', 'bestAction'].includes(c.id)} tip={c.tip}>{c.label}</SortTh>
              ))}
            </tr></thead>
            <tbody>
              {kwSort.sorted(kwGrouped).map((k) => {
                const isExp = expandedKw.has(k.term);
                return (
                  <><tr key={k.term} onClick={() => toggleKw(k.term)} className="border-b border-border-faint hover:bg-white/[.02] cursor-pointer transition-colors">
                    <td className="px-3 py-2 w-6">{isExp ? <ChevronDown size={12} className="text-faint" /> : <ChevronRight size={12} className="text-faint" />}</td>
                    {visibleKwCols.map(c => {
                      const cells: Record<string, React.ReactNode> = {
                        term: <td key="term" className="px-3 py-2 font-semibold text-blue-400">{k.term}</td>,
                        marketVol: <td key="marketVol" className="px-3 py-2 text-right font-mono text-[11px]">{k.marketVol ? Math.round(k.marketVol) : '--'}</td>,
                        totalSpend: <td key="totalSpend" className="px-3 py-2 text-right font-mono text-[11px]">{fM(k.totalSpend)}</td>,
                        totalOrders: <td key="totalOrders" className="px-3 py-2 text-right">{fOrd(k.totalOrders)}</td>,
                        totalClicks: <td key="totalClicks" className="px-3 py-2 text-right">{fClk(k.totalClicks)}</td>,
                        avgConv: <td key="avgConv" className="px-3 py-2 text-right">{fP(k.avgConv)}</td>,
                        impShare: <td key="impShare" className="px-3 py-2 text-right font-mono text-[11px]">{k.impShare ? fP(k.impShare * 100) : '--'}</td>,
                        avgRoas: <td key="avgRoas" className="px-3 py-2"><RoasBadge value={k.avgRoas} /></td>,
                        hasOrganicLift: <td key="hasOrganicLift" className="px-3 py-2">{k.hasOrganicLift ? <Badge variant="green" className="!text-[10px]">Organic</Badge> : <span className="text-faint">--</span>}</td>,
                        bestAction: <td key="bestAction" className="px-3 py-2"><ActionBadge action={k.bestAction} /></td>,
                      };
                      return cells[c.id];
                    })}
                  </tr>
                  {isExp && (
                    <tr key={k.term + '-detail'}>
                      <td colSpan={visibleKwCols.length + 1} className="p-0">
                        <div className="bg-inset px-4 py-3 border-b border-border-faint">
                          <div className="text-[10px] text-faint uppercase font-semibold mb-2 tracking-wider">Per-Experiment Breakdown</div>
                          <table className="w-full text-[11px]">
                            <thead><tr className="text-subtle">
                              <th className="text-left py-1 px-2 font-semibold">Experiment</th>
                              <th className="text-left py-1 px-2 font-semibold">Product</th>
                              <th className="text-right py-1 px-2 font-semibold">Ads Spend</th>
                              <th className="text-right py-1 px-2 font-semibold">Ads Orders</th>
                              <th className="text-right py-1 px-2 font-semibold">Ads Clicks</th>
                              <th className="text-right py-1 px-2 font-semibold">Ads Impr</th>
                              <th className="text-right py-1 px-2 font-semibold">Ads CPC</th>
                              <th className="text-right py-1 px-2 font-semibold">Ads Conv%</th>
                              <th className="text-right py-1 px-2 font-semibold">Ads ROAS</th>
                              <th className="text-left py-1 px-2 font-semibold">Hero?</th>
                            </tr></thead>
                            <tbody>
                              {k.entries.map((e, ei) => (
                                <tr key={ei} className="border-t border-border-faint">
                                  <td className="py-1 px-2 font-mono text-[10px]">{e.experiment_id}</td>
                                  <td className="py-1 px-2">{e.product_short_name}</td>
                                  <td className="py-1 px-2 text-right font-mono">{fM(e.spend_60d)}</td>
                                  <td className="py-1 px-2 text-right">{fOrd(e.orders_60d)}</td>
                                  <td className="py-1 px-2 text-right">{fClk(e.clicks_60d)}</td>
                                  <td className="py-1 px-2 text-right font-mono">{(e.impressions_60d || 0).toLocaleString()}</td>
                                  <td className="py-1 px-2 text-right font-mono">{fCpc(e.cpc_60d)}</td>
                                  <td className="py-1 px-2 text-right">{fP(e.conv_rate_60d)}</td>
                                  <td className="py-1 px-2 text-right"><RoasBadge value={e.net_roas_60d} /></td>
                                  <td className="py-1 px-2">{e.is_hero_match ? <span className="text-emerald-400">✓</span> : <span className="text-red-400">✗</span>}</td>
                                </tr>
                              ))}
                            </tbody>
                          </table>
                          {k.entries[0]?.reason && (
                            <div className="mt-2 text-[10px] text-subtle italic border-t border-border-faint pt-2">{k.entries[0].reason}</div>
                          )}
                        </div>
                      </td>
                    </tr>
                  )}
                  </>
                );
              })}
            </tbody>
          </table>
        </div>
      </Section>

      {/* SQP Detail */}
      {sqpData.length > 0 && (
        <Section title="SQP Performance (Search Query Performance)" count={`${sqpData.length} terms with SQP data`} filterItems={formatSectionFilters(filters)} headerRight={<MeasureSelector tableId="family_sqp_perf" measures={FAMILY_SQP_COLUMNS} selected={familySqpCols} onSelectedChange={setFamilySqpCols} />}>
          <div className="border border-border rounded-xl bg-card overflow-hidden">
            <table className="w-full border-collapse text-xs">
              <thead><tr>
                {visibleSqpCols.map(c => (
                  <Th key={c.id} right={!['search_term', 'asin', 'product_short_name'].includes(c.id)} tip={c.tip}>{c.label}</Th>
                ))}
              </tr></thead>
              <tbody>
                {sqpData.map((h, i) => {
                  const cells: Record<string, React.ReactNode> = {
                    search_term: <td key="search_term" className="px-3 py-2 font-semibold text-blue-400">{h.search_term || '--'}</td>,
                    asin: <td key="asin" className="px-3 py-2 font-mono text-[10px]">{h.asin}</td>,
                    product_short_name: <td key="product_short_name" className="px-3 py-2">{h.product_short_name}</td>,
                    sqp_impressions: <td key="sqp_impressions" className="px-3 py-2 font-mono text-[11px]">{(h.sqp_impressions || 0).toLocaleString()}</td>,
                    sqp_clicks: <td key="sqp_clicks" className="px-3 py-2 font-mono text-[11px]">{(h.sqp_clicks || 0).toLocaleString()}</td>,
                    sqp_conversions: <td key="sqp_conversions" className="px-3 py-2 font-mono text-[11px]">{(h.sqp_conversions || 0).toLocaleString()}</td>,
                    sqp_ctr_pct: <td key="sqp_ctr_pct" className="px-3 py-2">{h.sqp_ctr_pct != null ? fP(h.sqp_ctr_pct) : '--'}</td>,
                    sqp_cvr_pct: <td key="sqp_cvr_pct" className="px-3 py-2">{h.sqp_cvr_pct != null ? fP(h.sqp_cvr_pct) : '--'}</td>,
                    ads_spend: <td key="ads_spend" className="px-3 py-2 font-mono text-[11px]">{fM(h.ads_spend)}</td>,
                    ads_net_roas: <td key="ads_net_roas" className="px-3 py-2"><RoasBadge value={h.ads_net_roas} /></td>,
                  };
                  return (
                    <tr key={i} className="border-b border-border-faint last:border-b-0 hover:bg-white/[.02]">
                      {visibleSqpCols.map(col => cells[col.id])}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </Section>
      )}

      {/* Top Performers & Drains side by side */}
      <div className="grid grid-cols-2 gap-3.5 mb-6">
        <Section title="Top Performers" filterItems={formatSectionFilters(filters)} headerRight={<MeasureSelector tableId="family_drivers" measures={FAMILY_DRIVER_COLUMNS} selected={familyDriverCols} onSelectedChange={setFamilyDriverCols} />}>
          <DriverTable rows={tops} visibleCols={visibleDriverCols} />
        </Section>
        <Section title="Money Drains" count={drains.length > 0 ? `${drains.length} keywords` : undefined} filterItems={formatSectionFilters(filters)} headerRight={<MeasureSelector tableId="family_drains" measures={FAMILY_DRAIN_COLUMNS} selected={familyDrainCols} onSelectedChange={setFamilyDrainCols} />}>
          <DrainTable rows={drains} kwData={kwData} visibleCols={visibleDrainCols} />
        </Section>
      </div>

      {/* Trend Chart */}
      <Section title={`${mMeta.label} Trend`} count={latestSqp ? `SQP through ${latestPeriodLabel(latestSqp, 'weeks')}` : undefined} filterItems={formatSectionFilters(filters)}>
        <div className="flex items-center gap-2 mb-3 flex-wrap">
          <select value={trendMeasure} onChange={e => setTrendMeasure(e.target.value as TrendMeasure)}
            className="px-2.5 py-1 rounded-lg text-xs font-semibold border border-border bg-card text-white cursor-pointer appearance-none hover:border-border-strong transition-colors">
            {(Object.entries(MEASURE_META) as [TrendMeasure, typeof mMeta][]).map(([k, m]) => (<option key={k} value={k}>{m.label}</option>))}
          </select>
        </div>
        {trendData.length > 0 ? (
          <Card className="!p-4">
            {(trendMode === 'weeks' || trendMode === 'peak') && trendData.some(d => !d.hasSqp) && (
              <div className="flex items-center gap-3 mb-2 text-[10px] text-faint">
                <span className="flex items-center gap-1"><span className="inline-block w-2.5 h-2.5 rounded-sm" style={{ background: mMeta.color }} /> With SQP</span>
                <span className="flex items-center gap-1"><span className="inline-block w-2.5 h-2.5 rounded-sm border border-dashed" style={{ background: mMeta.color, opacity: 0.35, borderColor: mMeta.color }} /> Missing SQP</span>
              </div>
            )}
            <ResponsiveContainer width="100%" height={180}>
              <BarChart data={trendData}>
                <CartesianGrid {...CHART_GRID} />
                <XAxis dataKey="label" tick={CHART_AXIS_TICK_MD} tickLine={false} axisLine={false} />
                <YAxis tick={CHART_AXIS_TICK_LG} tickLine={false} axisLine={false} tickFormatter={v => mMeta.fmt(v)} />
                <Tooltip contentStyle={CHART_TOOLTIP_STYLE(11)} formatter={(v: any) => [mMeta.fmt(v ?? 0), mMeta.label]} />
                <Bar dataKey="value" radius={[4, 4, 0, 0]}>
                  {trendData.map((entry, idx) => (
                    <Cell key={idx} fill={mMeta.color} fillOpacity={entry.hasSqp ? 1 : 0.35} stroke={!entry.hasSqp ? mMeta.color : undefined} strokeWidth={!entry.hasSqp ? 1.5 : 0} strokeDasharray={!entry.hasSqp ? '4 2' : undefined} />
                  ))}
                </Bar>
                <SeasonalReferenceLines holidays={data.holidays || []} xLabels={getXLabels(trendData)} />
              </BarChart>
            </ResponsiveContainer>
          </Card>
        ) : <Empty message={`No data for ${trendMode} view`} />}
      </Section>

      {/* Experiments */}
      <Section title="Experiments" filterItems={formatSectionFilters(filters)}>
        {!experiments.length ? <Empty message="No experiments" /> : (
          <div className="space-y-2">
            {experiments.map(e => {
              const h = budgetHealth.find(x => x.experiment_id === e.experiment_id);
              const sig = e.action_signal || e.verdict || h?.action_signal || '--';
              const sc = sig.includes('SCALE') ? 'green' as const : sig.includes('REDUCE') || sig.includes('STOP') ? 'red' as const : sig.includes('WATCH') ? 'amber' as const : 'blue' as const;
              return (
                <Card key={e.experiment_id} className="!p-4 cursor-pointer hover:border-border-strong transition-colors" onClick={() => onNavExperiment?.(e.experiment_id)}>
                  <div className="flex justify-between items-start mb-1.5">
                    <div>
                      <strong className="text-[13px]">{e.experiment_name || e.experiment_id || '--'}</strong>
                      <div className="text-[11px] text-subtle">{e.strategy_id || ''} · {e.status || ''} · {e.days_running || e.days_active || '--'}d</div>
                    </div>
                    <Badge variant={sc}>{sig}</Badge>
                  </div>
                  <div className="grid grid-cols-[repeat(auto-fill,minmax(130px,1fr))] gap-x-3.5 gap-y-1 text-[11px] p-2.5 bg-inset rounded-lg">
                    {e.total_ad_spend != null && <div><span className="text-subtle">Spend:</span> <span className="font-mono font-medium">{fM(e.total_ad_spend)}</span></div>}
                    {e.total_orders != null && <div><span className="text-subtle">Orders:</span> {e.total_orders}</div>}
                    {e.net_roas != null && <div><span className="text-subtle">Ads ROAS:</span> <RoasBadge value={e.net_roas} /></div>}
                    {e.organic_lift_pct != null && <div><span className="text-subtle">Organic Lift:</span> <span className={`font-semibold ${e.organic_lift_pct > 0 ? 'text-emerald-400' : 'text-red-400'}`}>{e.organic_lift_pct > 0 ? '+' : ''}{e.organic_lift_pct.toFixed(1)}%</span></div>}
                    {h?.budget_utilization_pct != null && <div><span className="text-subtle">Budget Util:</span> {h.budget_utilization_pct.toFixed(1)}%</div>}
                    {e.tracked_search_terms != null && e.tracked_search_terms > 0 && <div><span className="text-subtle">Tracked Terms:</span> {e.tracked_search_terms}</div>}
                    {e.terms_positive_organic_lift != null && e.terms_positive_organic_lift > 0 && <div><span className="text-subtle">Pos Organic:</span> <span className="text-emerald-400">{e.terms_positive_organic_lift} terms</span></div>}
                    {e.search_avg_organic_lift_pct != null && <div><span className="text-subtle">Avg Lift:</span> <span className={e.search_avg_organic_lift_pct > 0 ? 'text-emerald-400' : 'text-red-400'}>{e.search_avg_organic_lift_pct > 0 ? '+' : ''}{fP(e.search_avg_organic_lift_pct)}</span></div>}
                  </div>
                </Card>
              );
            })}
          </div>
        )}
      </Section>
    </div>
  );
}

function DriverTable({ rows, visibleCols }: { rows: { search_term: string; product_short_name: string; spend: number; orders: number; clicks?: number; conv_rate: number; net_roas: number; action: string }[]; visibleCols: MeasureDef[] }) {
  const s = useSort('orders');
  if (!rows.length) return <div className="border border-border rounded-xl bg-card p-8 text-center text-faint text-sm">No data</div>;
  return (
    <div className="border border-border rounded-xl bg-card overflow-x-auto" style={{ maxHeight: 320, overflowY: 'auto' }}>
      <table className="w-full border-collapse text-xs">
        <thead><tr>
          {visibleCols.map(c => (
            <SortTh key={c.id} k={c.id} sort={s.sort} toggle={s.toggle} right={!['search_term', 'product_short_name', 'action'].includes(c.id)} tip={c.tip}>{c.label}</SortTh>
          ))}
        </tr></thead>
        <tbody>
          {s.sorted(rows).map((r, i) => {
            const cells: Record<string, React.ReactNode> = {
              search_term: <td key="search_term" className="px-3 py-2">{r.search_term || '--'}</td>,
              product_short_name: <td key="product_short_name" className="px-3 py-2">{r.product_short_name || '--'}</td>,
              spend: <td key="spend" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{fM(r.spend)}</td>,
              orders: <td key="orders" className="px-3 py-2 text-right">{fOrd(r.orders)}</td>,
              conv_rate: <td key="conv_rate" className="px-3 py-2 text-right">{fP(r.conv_rate)}</td>,
              net_roas: <td key="net_roas" className="px-3 py-2 text-right"><RoasBadge value={r.net_roas} /></td>,
              action: <td key="action" className="px-3 py-2"><ActionBadge action={r.action} /></td>,
            };
            return (
              <tr key={i} className="border-b border-border-faint last:border-b-0 hover:bg-white/[.02]">
                {visibleCols.map(col => cells[col.id])}
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function DrainTable({ rows, kwData, visibleCols }: { rows: { search_term: string; product_short_name: string; spend: number; orders: number; clicks?: number; conv_rate: number; net_roas: number; action: string; cpc?: number }[]; kwData: DashboardData['keyword_product_map']; visibleCols: MeasureDef[] }) {
  const s = useSort('spend');
  if (!rows.length) return <div className="border border-border rounded-xl bg-card p-8 text-center text-faint text-sm">No data</div>;

  const getOrganic = (term: string) => {
    const entries = kwData.filter(k => k.search_term === term);
    const reason = entries.find(e => e.reason?.includes('organic') || e.reason?.includes('SQP'))?.reason || '';
    const m = reason.match(/SQP shows (\d+) organic/);
    return m ? `${m[1]} org` : reason.includes('organic') ? 'Has organic' : '';
  };

  return (
    <div className="border border-border rounded-xl bg-card overflow-x-auto" style={{ maxHeight: 400, overflowY: 'auto' }}>
      <table className="w-full border-collapse text-xs">
        <thead><tr>
          {visibleCols.map(c => (
            <SortTh key={c.id} k={c.id} sort={s.sort} toggle={s.toggle} right={!['search_term', 'product_short_name', 'organic', 'action'].includes(c.id)} tip={c.tip}>{c.label}</SortTh>
          ))}
        </tr></thead>
        <tbody>
          {s.sorted(rows).map((r, i) => {
            const org = getOrganic(r.search_term);
            const lowClicks = (r.clicks || 0) < 50;
            const cells: Record<string, React.ReactNode> = {
              search_term: <td key="search_term" className="px-3 py-2">{r.search_term || '--'}</td>,
              product_short_name: <td key="product_short_name" className="px-3 py-2">{r.product_short_name || '--'}</td>,
              spend: <td key="spend" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{fM(r.spend)}</td>,
              clicks: <td key="clicks" className={`px-3 py-2 text-right font-mono text-[11px] ${lowClicks ? 'text-amber-400' : ''}`}>{fClk(r.clicks || 0)}{lowClicks && <span className="text-[9px] text-amber-400 ml-1">low</span>}</td>,
              orders: <td key="orders" className="px-3 py-2 text-right">{fOrd(r.orders)}</td>,
              conv_rate: <td key="conv_rate" className="px-3 py-2 text-right">{fP(r.conv_rate)}</td>,
              net_roas: <td key="net_roas" className="px-3 py-2"><RoasBadge value={r.net_roas} /></td>,
              organic: <td key="organic" className="px-3 py-2">{org ? <Badge variant="green" className="!text-[10px]">{org}</Badge> : <span className="text-faint">--</span>}</td>,
              action: <td key="action" className="px-3 py-2"><ActionBadge action={r.action} /></td>,
            };
            return (
              <tr key={i} className="border-b border-border-faint last:border-b-0 hover:bg-white/[.02]">
                {visibleCols.map(col => cells[col.id])}
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
