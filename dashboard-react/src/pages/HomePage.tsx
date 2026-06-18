import React, { useState, useMemo } from 'react';
import { ComposedChart, Bar, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, Cell, LabelList, ReferenceLine, Legend } from 'recharts';
import { SeasonalReferenceLines, getXLabels } from '../components/SeasonalReferenceLines';
import type { DashboardData, FamilyName, TrendRow, Ads7dRow, SupplyChainRow } from '../types';
import { FAMILIES } from '../types';
import { ChevronRight, ChevronDown } from 'lucide-react';
import { Card } from '../components/Card';
import { ChangesSummaryCell } from '../components/ChangesSummaryCell';
import { Section } from '../components/Section';
import { Badge, RoasBadge, ActionBadge } from '../components/Badge';
import { Empty } from '../components/Empty';
import { SortTh, useSort, MEASURE_TIPS } from '../components/Tooltip';
import { DashboardSummary } from '../components/DashboardSummary';
import { fmt, fM, fP, fR, fOrd, fClk, famFromType, weekRangeLabel, weekRangeLabelCapped, formatDateRange, ACTION_META, sqpCoverageWeeks, latestSqpWeek, periodDateKey, latestPeriodLabel, sliceByPeriod, getPeriodsToInclude, shiftYear, addDays, weeksInDateRange, weekOverlapsAdsGap, monthOverlapsAdsGap, scoreFromRoas, scoreFromProfitDelta, periodKey, periodDayCount, experimentMatchesFamily } from '../utils';
import { filterBySeasonality, getSeasonality } from '../seasonality';
import { useFilters } from '../hooks/useFilters';
import { formatSectionFilters } from '../utils/filterUtils';
import { CHART_GRID, CHART_AXIS_TICK_LG, CHART_TOOLTIP_STYLE } from '../chartTheme';
import { MEASURE_META, type TrendMeasure } from '../constants';
import { MeasureSelector, useMeasureSelection, type MeasureDef } from '../components/MeasureSelector';
import { usePageSummary } from '../components/PageSummaryBar';
import { apiFetch } from '../utils/apiFetch';

const ALL_MEASURES: TrendMeasure[] = ['sales', 'ad_cost', 'cogs', 'net_profit', 'net_roas', 'orders', 'units', 'clicks', 'sessions', 'organic_pct', 'payment'];

// All known families (drives inclusion + per-family record initialization). Derived from
// FAMILIES so new families (Bunny, LolliBall, …) are picked up without code edits.
const FAM_KEYS = Object.keys(FAMILIES) as FamilyName[];
function famRecord<T>(init: () => T): Record<FamilyName, T> {
  return Object.fromEntries(FAM_KEYS.map(k => [k, init()])) as Record<FamilyName, T>;
}
// Stock anywhere in the pipeline: FBA + AWD + in-transit + manufactured-ready.
const stockAnywhere = (sc: { fba_stock_qty?: number; awd_stock_qty?: number; in_transit_qty?: number; mfr_stock_qty?: number }): number =>
  (sc.fba_stock_qty || 0) + (sc.awd_stock_qty || 0) + (sc.in_transit_qty || 0) + (sc.mfr_stock_qty || 0);

const FAMILY_TABLE_COLUMNS: MeasureDef[] = [
  { id: 'family', label: 'Family', group: 'Info' },
  { id: 'sales', label: 'Sales', tip: MEASURE_TIPS.sales, group: 'PnL' },
  { id: 'share_pct', label: 'Share %', tip: 'Percentage of total sales across all families', group: 'PnL' },
  { id: 'cogs', label: 'COGS', tip: MEASURE_TIPS.cogs, group: 'PnL' },
  { id: 'ad_cost', label: 'Ads Spend', tip: MEASURE_TIPS.ad_cost, group: 'Ads' },
  { id: 'ads_sales', label: 'Ads Sales', tip: 'Sales attributed to ads campaigns', group: 'Ads' },
  { id: 'payment', label: 'Payment', tip: MEASURE_TIPS.payment, group: 'PnL' },
  { id: 'storage_cost', label: 'Storage Cost', tip: 'FBA+AWD monthly storage fees (avg inventory × cubic feet × seasonal rate)', group: 'PnL', defaultVisible: true },
  { id: 'ads_units', label: 'Ads Units', tip: 'Units sold attributed to ads campaigns', group: 'Ads', defaultVisible: false },
  { id: 'net_profit', label: 'Net Profit', tip: MEASURE_TIPS.net_profit, group: 'PnL' },
  { id: 'np_per_unit', label: 'NP/Unit', tip: 'Net Profit divided by total units sold — your north-star metric', group: 'PnL' },
  { id: 'net_roas', label: 'Net ROAS', tip: MEASURE_TIPS.net_roas, group: 'Ads' },
  { id: 'ads_roas', label: 'Ads ROAS', tip: 'Ads Sales / Ads Spend — gross advertising return', group: 'Ads', defaultVisible: false },
  { id: 'tacos', label: 'TACoS', tip: 'Total Ads Cost of Sales — Ads Spend / Total Sales — measures ad dependency', group: 'Ads' },
  { id: 'pct_ads_spend', label: '% Total Ads Spend', tip: 'Percentage of total ads spend', group: 'Ads', defaultVisible: true },
  { id: 'pct_net_profit', label: '% Total Net Profit', tip: 'Percentage of total net profit', group: 'PnL', defaultVisible: true },
  { id: 'ad_orders', label: 'Ads Orders', tip: 'Orders attributed to ads', group: 'Ads', defaultVisible: false },
  { id: 'units', label: 'Units', tip: 'Total units sold (COGS / cost per unit)', group: 'PnL', defaultVisible: false },
  { id: 'orders', label: 'Total Orders', tip: MEASURE_TIPS.orders, group: 'SQP' },
  { id: 'organic_units', label: 'Organic Units', tip: 'Total units minus ads-attributed units (purchased ASIN)', group: 'SQP', defaultVisible: false },
  { id: 'clicks', label: 'Clicks', tip: MEASURE_TIPS.clicks, group: 'SQP' },
  { id: 'sessions', label: 'Sessions', tip: 'Total sessions (Business)', group: 'SQP', defaultVisible: false },
  { id: 'organic_pct', label: 'Organic %', tip: MEASURE_TIPS.organic_pct, group: 'SQP' },
  { id: 'sales_change', label: 'Sales vs Prev', tip: MEASURE_TIPS.sales_change, group: 'Info' },
  { id: 'fba_pick_pack', label: 'FBA Pick&Pack', tip: 'FBA pick & pack fee per unit (from DIM_COSTS_HISTORY)', group: 'PnL', defaultVisible: false },
  { id: 'fba_referral', label: 'FBA Referral', tip: 'FBA referral fee per unit (from DIM_COSTS_HISTORY)', group: 'PnL', defaultVisible: false },
  { id: 'cost_of_goods', label: 'COGS/Unit', tip: 'Cost of goods per unit (from DIM_COSTS_HISTORY)', group: 'PnL', defaultVisible: false },
  { id: 'shipping_cost_per_unit', label: 'Shipping/Unit', tip: 'Shipping cost per unit (from DIM_COSTS_HISTORY)', group: 'PnL', defaultVisible: false },
  { id: 'fba_stock_qty', label: 'FBA Stock', tip: 'Current sellable inventory in FBA', group: 'Supply Chain', defaultVisible: true },
  { id: 'awd_stock_qty', label: 'AWD Stock', tip: 'Current inventory in AWD', group: 'Supply Chain', defaultVisible: true },
  { id: 'in_transit_qty', label: 'In Transit', tip: 'Units currently in transit (inbound shipments)', group: 'Supply Chain', defaultVisible: true },
  { id: 'mfr_stock_qty', label: 'Mfg Ready', tip: 'Units manufactured and ready to ship from the factory', group: 'Supply Chain', defaultVisible: true },
  { id: 'days_of_coverage', label: 'Days Cover', tip: 'Days of sellable inventory coverage at current velocity (FBA+AWD stock ÷ daily units sold)', group: 'Supply Chain', defaultVisible: true },
  { id: 'fba_days_of_coverage', label: 'Days Cover (FBA)', tip: 'Days of FBA inventory coverage at current velocity', group: 'Supply Chain', defaultVisible: true },
  { id: 'awd_days_of_coverage', label: 'Days Cover (AWD)', tip: 'Days of AWD inventory coverage at current velocity', group: 'Supply Chain', defaultVisible: true },
  { id: 'days_next_shipment', label: 'Days Next Ship', tip: 'Days until next pending shipment arrives', group: 'Supply Chain', defaultVisible: true },
  { id: 'qty_next_shipment', label: 'Qty Next Ship', tip: 'Quantity in next pending shipment', group: 'Supply Chain', defaultVisible: true },
  { id: 'last_30d_sold', label: 'Last 30d Sold', tip: 'Actual sales units in the last 30 days', group: 'Supply Chain', defaultVisible: true },
  { id: 'next_30d_planned', label: 'Next 30d Planned', tip: 'Planned demand for the next 30 days', group: 'Supply Chain', defaultVisible: true },
  { id: 'next_31_60d_planned', label: 'Next 31-60d Planned', tip: 'Planned demand for days 31-60', group: 'Supply Chain', defaultVisible: true },
  { id: 'next_61_90d_planned', label: 'Next 61-90d Planned', tip: 'Planned demand for days 61-90', group: 'Supply Chain', defaultVisible: true },
  { id: 'awd_min_defined', label: 'AWD Min (Defined)', tip: 'AWD target min system (and approved)', group: 'Supply Chain', defaultVisible: true },
  { id: 'awd_max_defined', label: 'AWD Max (Defined)', tip: 'AWD target max system (and approved)', group: 'Supply Chain', defaultVisible: true },
];
const AVG_MEASURES = new Set<TrendMeasure>(['net_roas', 'organic_pct']);
const STAGE_LABELS_SHORT: Record<string, string> = { READINESS: 'Readiness', PRE_PEAK: 'Pre Peak', PRE_PEAK_BOOST: 'Boost', PEAK: 'Peak', POST_PEAK: 'Post Peak' };

function getChangesStatus(d: { sd: number; cd: number; pd: number; roasDelta: number; orgDelta: number }): string {
  const { sd, cd, pd, roasDelta, orgDelta } = d;
  const phrases: string[] = [];
  if (pd > 0 && sd > 0 && cd < sd) phrases.push('Efficient scaling – profit and sales up, cost growing slower than revenue');
  else if (pd > 0 && sd > 0 && cd <= 0) phrases.push('Strong growth – profit and sales up, cost flat or down');
  else if (pd < 0 && cd > 0 && cd > sd) phrases.push('Cost pressure – spend outpacing revenue');
  else if (pd < 0 && sd < 0) phrases.push('Declining – sales and profit down');
  else if (pd > 0) phrases.push('Profit improving');
  else if (sd > 0) phrases.push('Sales up');
  else if (sd < 0) phrases.push('Sales down');
  if (roasDelta > 0) phrases.push('Ad efficiency improving');
  if (orgDelta > 0) phrases.push('Organic share gaining');
  if (orgDelta < 0 && orgDelta < -1) phrases.push('More ads-dependent');
  if (phrases.length === 0) return 'Flat vs previous period';
  return phrases.join('. ');
}

export function HomePage({ data, onNav }: { data: DashboardData; onNav: (p: string, f?: FamilyName) => void }) {
  const { filters, setFilter } = useFilters();
  const periodMode = filters.periodMode;
  const perfMaxDate = data._meta?.data_freshness?.performance_max_date || '';
  // Total | /day toggle — divides additive measures by the days each period covers
  // (elapsed days for the in-progress period) so partial periods are comparable.
  const [perDay, setPerDay] = useState<boolean>(() => { try { return localStorage.getItem('oi_home_per_day') === '1'; } catch { return false; } });
  const setPerDayPersist = (v: boolean) => { setPerDay(v); try { localStorage.setItem('oi_home_per_day', v ? '1' : '0'); } catch { /* ignore */ } };
  const [selectedMeasures, setSelectedMeasures] = useState<Set<TrendMeasure>>(new Set(['sales', 'ad_cost', 'net_profit', 'net_roas']));
  const [approvedAwds, setApprovedAwds] = useState<Set<string>>(new Set());
  const [expandedFamily, setExpandedFamily] = useState<FamilyName | null>(null);
  const [familyCols, setFamilyCols] = useMeasureSelection('home_family', FAMILY_TABLE_COLUMNS);
  const visibleFamilyCols = useMemo(() => FAMILY_TABLE_COLUMNS.filter(c => familyCols.has(c.id)), [familyCols]);
  const urgentActions = useMemo(() => (data.actions || []).filter(a => a.action === 'REDUCE_BID' || a.action === 'NEGATE_TERM').length, [data.actions]);

  const toggleMeasure = (m: TrendMeasure) => {
    setSelectedMeasures(prev => {
      const next = new Set(prev);
      if (next.has(m)) { if (next.size > 1) next.delete(m); }
      else next.add(m);
      return next;
    });
  };

  const handleApproveAwd = async (asin: string, minUnits: number, maxUnits: number) => {
    try {
      const res = await apiFetch('/api/awd-settings', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ asin, min_units: minUnits, max_units: maxUnits }),
      });
      if (!res.ok) throw new Error('Failed to approve AWD settings');
      // Update local state instantly without reloading
      setApprovedAwds(prev => new Set(prev).add(asin));
    } catch (e) {
      console.error('AWD Approval error', e);
      alert('Failed to approve AWD target.');
    }
  };

  const pk = data.peak?.[0] ?? null;

  const expCampaignIds = useMemo(() => {
    if (!filters.experiment) return null;
    const ids = new Set((data.experiment_campaigns || []).filter(c => c.experiment_id === filters.experiment).map(c => c.campaign_id));
    return ids.size > 0 ? ids : null;
  }, [data.experiment_campaigns, filters.experiment]);

  const famMatch = useMemo(() => {
    if (!filters.family) return null;
    const patterns: Record<string, string[]> = {
      Lollibox: ['box'],
      LolliME: ['me-', 'me_', 'mint', 'lollime'],
      Bottle: ['bottle', 'truth', 'btl'],
      Fresh: ['fresh'],
    };
    return patterns[filters.family] || null;
  }, [filters.family]);

  const ALL_FAMILY_PATTERNS = ['box', 'me-', 'me_', 'mint', 'lollime', 'bottle', 'truth', 'btl', 'fresh'];

  // Apply global family, product (ASIN), and seasonality filters to trend data
  const filteredWeekly = useMemo(() => {
    let rows: TrendRow[] = filters.product
      ? (data.weekly_trends_by_asin || []).filter((r: TrendRow & { asin?: string }) => r.asin === filters.product)
      : (data.weekly_trends || []);
    if (filters.family) rows = rows.filter(r => famFromType(r.product_type) === filters.family);
    return filterBySeasonality(rows, 'week_start', filters.seasonality, pk);
  }, [data.weekly_trends, data.weekly_trends_by_asin, filters.family, filters.product, filters.seasonality, pk]);

  const filteredMonthly = useMemo(() => {
    let rows: TrendRow[] = filters.product
      ? (data.monthly_trends_by_asin || []).filter((r: TrendRow & { asin?: string }) => r.asin === filters.product)
      : (data.monthly_trends || []);
    if (filters.family) rows = rows.filter(r => famFromType(r.product_type) === filters.family);
    return filterBySeasonality(rows, 'month_start', filters.seasonality, pk);
  }, [data.monthly_trends, data.monthly_trends_by_asin, filters.family, filters.product, filters.seasonality, pk]);

  const sqpWeeks = useMemo(() => sqpCoverageWeeks(data.sqp_coverage_weeks || []), [data.sqp_coverage_weeks]);

  // Ads period keys — same source as Ads page for period alignment
  const adsPeriodKeys = useMemo(() => {
    const ads7d = data.ads_7d_summary || [];
    if (!ads7d.length) return { weeks: [] as string[], months: [] as string[], years: [] as string[] };
    const hasDate = ads7d.some(r => r.date);
    return {
      weeks: [...new Set(ads7d.map(r => r.week_start || '').filter(Boolean))].sort(),
      months: hasDate ? [...new Set(ads7d.map(r => (r.date || '').slice(0, 7)).filter(Boolean))].sort() : [],
      years: hasDate ? [...new Set(ads7d.map(r => (r.date || '').slice(0, 4)).filter(Boolean))].sort() : [],
    };
  }, [data.ads_7d_summary]);

  // KPIs — aggregate by periodMode (week / month / year). Zero ads spend for rows in ads gap (2025-03-11 to 2025-10-02).
  // Include ads period keys so "latest" aligns with Ads page when filters match.
  const { totals, prevTotals, kpiWeek, kpiPrevWeek, kpiPeriodLabel } = useMemo(() => {
    const zeroAds = (r: TrendRow, pm: typeof periodMode, periodKey: string) => {
      if (pm === 'weeks') return weekOverlapsAdsGap(r.week_start || '');
      if (pm === 'month') return monthOverlapsAdsGap(periodKey);
      if (pm === 'year') return (r.month_start && monthOverlapsAdsGap((r.month_start || '').slice(0, 7)));
      return false;
    };
    const agg = (rows: TrendRow[], pm: typeof periodMode, pk: string) => {
      const t = { sl: 0, co: 0, cg: 0, np: 0, or: 0, cl: 0, ss: 0, roas: 0, orgP: 0, _cnt: 0 };
      rows.forEach(r => {
        const adCost = zeroAds(r, pm, pk) ? 0 : (r.ad_cost || 0);
        t.sl += r.sales || 0; t.co += adCost; t.cg += r.cogs || 0;
        t.np += r.net_profit || 0; t.or += r.orders || 0;
        t.cl += r.clicks || 0; t.ss += r.sessions || 0;
        t.roas += r.net_roas || 0; t.orgP += r.organic_pct || 0; t._cnt += 1;
      });
      if (t._cnt > 0) { t.roas /= t._cnt; t.orgP /= t._cnt; }
      return t;
    };
    const filterForPeriod = (rDate: string, targetDate: string) => {
      if (!rDate || !targetDate) return false;
      if (filters.periodType !== 'cumulative') return rDate === targetDate;
      return rDate.slice(0, 4) === targetDate.slice(0, 4) && rDate <= targetDate;
    };

    if (periodMode === 'weeks') {
      const wt = filteredWeekly;
      const allWeeks = [...new Set(wt.map(r => r.week_start || ''))].filter(Boolean).sort();
      const allWeeksExtended = [...new Set([...allWeeks, ...sqpWeeks, ...adsPeriodKeys.weeks])].filter(Boolean).sort();
      let curWeek: string;
      if (filters.specificPeriod && allWeeksExtended.includes(filters.specificPeriod)) {
        curWeek = filters.specificPeriod;
      } else {
        curWeek = allWeeks.length ? allWeeks[allWeeks.length - 1] : (allWeeksExtended.length ? allWeeksExtended[allWeeksExtended.length - 1] : '');
      }
      const curIdx = allWeeksExtended.indexOf(curWeek);
      const prvWeek = curIdx > 0 ? allWeeksExtended[curIdx - 1] : '';
      const cur = agg(wt.filter(r => filterForPeriod(r.week_start || '', curWeek)), 'weeks', curWeek);
      const prv = prvWeek ? agg(wt.filter(r => filterForPeriod(r.week_start || '', prvWeek)), 'weeks', prvWeek) : null;
      return { totals: cur, prevTotals: prv, kpiWeek: curWeek, kpiPrevWeek: prvWeek, kpiPeriodLabel: curWeek ? weekRangeLabel(curWeek) : '' };
    }

    if (periodMode === 'month') {
      const mt = filteredMonthly;
      const allMonths = [...new Set([...mt.map(r => (r.month_start || '').slice(0, 7)), ...adsPeriodKeys.months])].filter(Boolean).sort();
      const keep = new Set(getPeriodsToInclude(filters.specificPeriod, 'month', allMonths, 2));
      const periods = [...keep].sort();
      const curPeriod = (filters.specificPeriod && allMonths.includes(filters.specificPeriod) ? filters.specificPeriod : null) || (filteredMonthly.length ? [...new Set(filteredMonthly.map(r => (r.month_start || '').slice(0, 7)))].sort().pop() : '') || periods[periods.length - 1] || '';
      const prvPeriod = periods.length >= 2 ? periods[periods.length - 2] : '';
      const cur = agg(mt.filter(r => filterForPeriod((r.month_start || '').slice(0, 7), curPeriod)), 'month', curPeriod);
      const prv = prvPeriod ? agg(mt.filter(r => filterForPeriod((r.month_start || '').slice(0, 7), prvPeriod)), 'month', prvPeriod) : null;
      return { totals: cur, prevTotals: prv, kpiWeek: curPeriod, kpiPrevWeek: prvPeriod, kpiPeriodLabel: curPeriod };
    }

    if (periodMode === 'quarter') {
      const mt = filteredMonthly;
      const allQuarters = [...new Set(mt.map(r => {
        const ms = r.month_start || '';
        const m = parseInt(ms.slice(5, 7), 10);
        const q = Math.ceil(m / 3);
        return `${ms.slice(0, 4)}-Q${q}`;
      }))].filter(Boolean).sort();
      const keep = new Set(getPeriodsToInclude(filters.specificPeriod, 'quarter', allQuarters, 2));
      const quarters = [...keep].sort();
      const curQuarter = (filters.specificPeriod && allQuarters.includes(filters.specificPeriod) ? filters.specificPeriod : null) || (filteredMonthly.length ? [...new Set(filteredMonthly.map(r => { const m = parseInt((r.month_start || '').slice(5, 7), 10); return `${(r.month_start || '').slice(0, 4)}-Q${Math.ceil(m / 3)}`; }))].filter(Boolean).sort().pop() : '') || quarters[quarters.length - 1] || '';
      const prvQuarter = quarters.length >= 2 ? quarters[quarters.length - 2] : '';
      const mapQ = (r: TrendRow) => {
        const ms = r.month_start || '';
        const m = parseInt(ms.slice(5, 7), 10);
        return `${ms.slice(0, 4)}-Q${Math.ceil(m / 3)}`;
      };
      const cur = agg(mt.filter(r => filterForPeriod(mapQ(r), curQuarter)), 'quarter', curQuarter);
      const prv = prvQuarter ? agg(mt.filter(r => filterForPeriod(mapQ(r), prvQuarter)), 'quarter', prvQuarter) : null;
      return { totals: cur, prevTotals: prv, kpiWeek: curQuarter, kpiPrevWeek: prvQuarter, kpiPeriodLabel: curQuarter };
    }

    const mt = filteredMonthly;
    const allYears = [...new Set([...mt.map(r => (r.month_start || '').slice(0, 4)), ...adsPeriodKeys.years])].filter(Boolean).sort();
    const keep = new Set(getPeriodsToInclude(filters.specificPeriod, 'year', allYears, 2));
    const years = [...keep].sort();
    const curYear = years[years.length - 1] || '';
    const prvYear = years.length >= 2 ? years[years.length - 2] : '';
    const cur = agg(mt.filter(r => filterForPeriod((r.month_start || '').slice(0, 4), curYear)), 'year', curYear);
    const prv = prvYear ? agg(mt.filter(r => filterForPeriod((r.month_start || '').slice(0, 4), prvYear)), 'year', prvYear) : null;
    return { totals: cur, prevTotals: prv, kpiWeek: curYear, kpiPrevWeek: prvYear, kpiPeriodLabel: curYear };
  }, [filteredWeekly, filteredMonthly, sqpWeeks, adsPeriodKeys, filters.specificPeriod, periodMode, data.sqp_weekly, filters.periodType]);

  const { effectiveTotals, effectivePrevTotals } = useMemo(() => {
    return {
      effectiveTotals: totals,
      effectivePrevTotals: prevTotals,
    };
  }, [totals, prevTotals]);

  const adsSpendByPeriod = useMemo(() => {
    let ads7d: Ads7dRow[] = data.ads_7d_summary || [];
    if (filters.product) {
      const productInfo = (data.products || []).find(p => p.asin === filters.product);
      const productName = productInfo?.product_short_name;
      if (productName) ads7d = ads7d.filter(r => r.product_short_name === productName);
    } else if (famMatch) {
      ads7d = ads7d.filter(r => famMatch.some(p => (r.campaign_name || '').toLowerCase().includes(p)));
    } else {
      ads7d = ads7d.filter(r => ALL_FAMILY_PATTERNS.some(p => (r.campaign_name || '').toLowerCase().includes(p)));
    }
    if (expCampaignIds) ads7d = ads7d.filter(r => expCampaignIds.has(r.campaign_id));
    if (filters.keyword) {
      const ids = new Set((data.campaign_search_terms || []).filter(r => r.search_term === filters.keyword).map(r => r.campaign_id));
      ads7d = ads7d.filter(r => ids.has(r.campaign_id));
    }
    if (filters.seasonality && pk) {
      ads7d = ads7d.filter(r => { const d = r.date || r.week_start || ''; return d ? getSeasonality(d, pk) === filters.seasonality : false; });
    }
    const useDateFilter = periodMode !== 'weeks' && ads7d.some(r => r.date);
    const getPk = (r: Ads7dRow) => {
      if (useDateFilter) return r.date ? periodKey(r.date, periodMode) : '';
      const ws = r.week_start || '';
      if (!ws) return '';
      if (periodMode === 'month' || periodMode === 'quarter') return periodKey(addDays(ws, 3), periodMode);
      return periodKey(ws, periodMode);
    };
    const map: Record<string, number> = {};
    ads7d.forEach(r => { const pk = getPk(r); if (pk) map[pk] = (map[pk] || 0) + (r.spend || 0); });
    return map;
  }, [data.ads_7d_summary, data.products, data.campaign_search_terms, periodMode, famMatch, expCampaignIds, filters.product, filters.keyword, filters.seasonality, pk]);

  const adsDataByProductAndPeriod = useMemo(() => {
    const campaignToProduct: Record<string, string> = {};
    const campaignIdToName: Record<string, string> = {};
    for (const r of (data.ads_7d || [])) {
      if (r.campaign_id) {
        if (r.campaign_name) campaignIdToName[r.campaign_id] = String(r.campaign_name);
        if (r.product_short_name && !campaignToProduct[r.campaign_id]) {
          campaignToProduct[r.campaign_id] = r.product_short_name;
        }
      }
    }

    let ads7d: Ads7dRow[] = data.ads_7d_summary || [];
    if (expCampaignIds) ads7d = ads7d.filter(r => expCampaignIds.has(r.campaign_id));
    if (filters.keyword) {
      const ids = new Set((data.campaign_search_terms || []).filter(r => r.search_term === filters.keyword).map(r => r.campaign_id));
      ads7d = ads7d.filter(r => ids.has(r.campaign_id));
    }
    if (filters.seasonality && pk) {
      ads7d = ads7d.filter(r => { const d = r.date || r.week_start || ''; return d ? getSeasonality(d, pk) === filters.seasonality : false; });
    }
    if (filters.product) {
      const productInfo = (data.products || []).find(p => p.asin === filters.product);
      const productName = productInfo?.product_short_name;
      if (productName) ads7d = ads7d.filter(r => r.product_short_name === productName);
    }
    const useDateFilter = periodMode !== 'weeks' && ads7d.some(r => r.date);
    const getPk = (r: Ads7dRow) => {
      if (useDateFilter) return r.date ? periodKey(r.date, periodMode) : '';
      const ws = r.week_start || '';
      if (!ws) return '';
      if (periodMode === 'month' || periodMode === 'quarter') return periodKey(addDays(ws, 3), periodMode);
      return periodKey(ws, periodMode);
    };
    const spendMap: Record<string, number> = {};
    const salesMap: Record<string, number> = {};
    const unitsMap: Record<string, number> = {};
    ads7d.forEach(r => {
      let name = r.product_short_name || campaignToProduct[r.campaign_id];
      const campName = String(r.campaign_name || campaignIdToName[r.campaign_id] || '');
      if (!name && campName) {
        if (experimentMatchesFamily(campName, 'Lollibox')) name = 'Lollibox';
        else if (experimentMatchesFamily(campName, 'LolliME')) name = 'LolliME';
        else if (experimentMatchesFamily(campName, 'Bottle')) name = 'Bottle';
        else if (experimentMatchesFamily(campName, 'Fresh')) name = 'Fresh';
      }
      if (!name) return;
      const p = getPk(r);
      if (!p) return;
      const key = `${name}|${p}`;
      spendMap[key] = (spendMap[key] || 0) + (r.spend || 0);
      salesMap[key] = (salesMap[key] || 0) + (r.sales || 0);
      unitsMap[key] = (unitsMap[key] || 0) + (r.orders || 0);
    });
    return { spend: spendMap, sales: salesMap, units: unitsMap };
  }, [data.ads_7d_summary, data.ads_7d, data.products, data.campaign_search_terms, periodMode, expCampaignIds, filters.keyword, filters.seasonality, filters.product, pk]);

  const productToFamily = useMemo(() => {
    // OI family lives in parent_name (falls back to product_short_name), NOT product_type
    // — product_type on DIM_PRODUCT is the Amazon category (e.g. KEYCHAIN).
    const map: Record<string, FamilyName> = {};
    for (const p of (data.products || [])) {
      const fam = (p.parent_name || p.product_short_name || '') as FamilyName;
      if (fam && p.product_short_name) map[p.product_short_name] = fam;
    }
    return map;
  }, [data.products]);

  // asin → OI family (parent_name || product_short_name), matching V_PRODUCT_FAMILY_MAP.
  const asinToFamily = useMemo(() => {
    const map = new Map<string, string>();
    for (const p of (data.products || [])) {
      if (p.asin) map.set(p.asin, p.parent_name || p.product_short_name || '');
    }
    return map;
  }, [data.products]);

  // Per-family inventory totals + the set of families that hold stock anywhere
  // (FBA / AWD / in-transit / manufactured). Drives "show everything with stock".
  const { supplyByFamily, familiesWithStock } = useMemo(() => {
    type FamSupply = { fba: number; awd: number; in_transit: number; mfr: number; sellable: number; velocity: number; next_ship_qty: number; last_30d_sold: number; next_30d: number; next_31_60: number; next_61_90: number };
    const agg: Record<string, FamSupply> = {};
    const withStock = new Set<string>();
    for (const sc of (data.supply_chain || [])) {
      const fam = asinToFamily.get(sc.asin) || '';
      if (!fam) continue;
      if (stockAnywhere(sc) > 0) withStock.add(fam);
      const a = agg[fam] || (agg[fam] = { fba: 0, awd: 0, in_transit: 0, mfr: 0, sellable: 0, velocity: 0, next_ship_qty: 0, last_30d_sold: 0, next_30d: 0, next_31_60: 0, next_61_90: 0 });
      a.fba += sc.fba_stock_qty || 0;
      a.awd += sc.awd_stock_qty || 0;
      a.in_transit += sc.in_transit_qty || 0;
      a.mfr += sc.mfr_stock_qty || 0;
      a.sellable += sc.sellable_qty || 0;
      a.velocity += sc.daily_velocity || 0;
      a.next_ship_qty += sc.next_shipment_qty || 0;
      a.last_30d_sold += sc.last_30d_sold || 0;
      a.next_30d += sc.next_30d_planned || 0;
      a.next_31_60 += sc.next_31_60d_planned || 0;
      a.next_61_90 += sc.next_61_90d_planned || 0;
    }
    return { supplyByFamily: agg, familiesWithStock: withStock };
  }, [data.supply_chain, asinToFamily]);

  const { adsSpendByFamilyAndPeriod } = useMemo(() => {
    const spendMap: Record<string, number> = {};
    const salesMap: Record<string, number> = {};
    const unitsMap: Record<string, number> = {};
    for (const [key, val] of Object.entries(adsDataByProductAndPeriod.spend)) {
      const [name, period] = key.split('|');
      const fam = productToFamily[name] || ((FAM_KEYS as string[]).includes(name) ? name : null);
      if (fam && period) spendMap[`${fam}|${period}`] = (spendMap[`${fam}|${period}`] || 0) + val;
    }
    for (const [key, val] of Object.entries(adsDataByProductAndPeriod.sales)) {
      const [name, period] = key.split('|');
      const fam = productToFamily[name] || ((FAM_KEYS as string[]).includes(name) ? name : null);
      if (fam && period) salesMap[`${fam}|${period}`] = (salesMap[`${fam}|${period}`] || 0) + val;
    }
    for (const [key, val] of Object.entries(adsDataByProductAndPeriod.units)) {
      const [name, period] = key.split('|');
      const fam = productToFamily[name] || ((FAM_KEYS as string[]).includes(name) ? name : null);
      if (fam && period) unitsMap[`${fam}|${period}`] = (unitsMap[`${fam}|${period}`] || 0) + val;
    }
    return { adsSpendByFamilyAndPeriod: spendMap, adsSalesByFamilyAndPeriod: salesMap, adsUnitsByFamilyAndPeriod: unitsMap };
  }, [adsDataByProductAndPeriod, productToFamily]);

  // ── Per-day denominators. dCur = elapsed days of the (possibly partial) current
  // period; dPrev = prev period days; dLy = full length (LY periods are complete). ──
  const dCur = Math.max(1, periodDayCount(kpiWeek, periodMode, perfMaxDate));
  const dPrev = Math.max(1, periodDayCount(kpiPrevWeek, periodMode, perfMaxDate));
  const dLy = Math.max(1, periodDayCount(kpiWeek, periodMode));
  const lyScale = perDay ? 1 / dLy : 1;
  const _sc = perDay ? 1 / dCur : 1;
  const _scp = perDay ? 1 / dPrev : 1;
  // Display totals — additive fields scaled per-day; ratios computed from them stay invariant.
  const eT2 = {
    sl: effectiveTotals.sl * _sc, co: effectiveTotals.co * _sc, cg: effectiveTotals.cg * _sc,
    np: effectiveTotals.np * _sc, or: effectiveTotals.or * _sc, cl: effectiveTotals.cl * _sc, ss: effectiveTotals.ss * _sc,
  };
  const eP2 = effectivePrevTotals ? {
    sl: effectivePrevTotals.sl * _scp, co: effectivePrevTotals.co * _scp,
    cg: effectivePrevTotals.cg * _scp, np: effectivePrevTotals.np * _scp,
  } : null;

  const roas = eT2.co ? (eT2.sl - eT2.cg) / eT2.co : 0;
  const orgP = effectiveTotals.orgP;
  const orgOrd = eT2.or > 0 ? Math.round(eT2.or * orgP / 100) : 0;
  const sd = eP2?.sl ? ((eT2.sl - eP2.sl) / eP2.sl) * 100 : 0;
  const cd = eP2?.co ? ((eT2.co - eP2.co) / eP2.co) * 100 : 0;
  const pd = eP2?.np ? ((eT2.np - eP2.np) / Math.abs(eP2.np)) * 100 : 0;
  const margin = eT2.sl ? (eT2.np / eT2.sl) * 100 : 0;
  const prevRoas = eP2?.co ? (eP2.sl - eP2.cg) / eP2.co : 0;
  const roasDelta = prevRoas ? ((roas - prevRoas) / Math.abs(prevRoas)) * 100 : 0;
  const prevOrgP = effectivePrevTotals?.orgP || 0;
  const orgDelta = prevOrgP ? ((orgP - prevOrgP) / Math.abs(prevOrgP)) * 100 : 0;

  const acts = data.actions || [];
  const grouped = useMemo(() => {
    const g: Record<string, typeof acts> = { urgent: [], growth: [], experiment: [], fix: [] };
    
    let filteredActs = acts;
    if (filters.family) {
      filteredActs = filteredActs.filter(a => {
        if ((a as any).parent_name && (a as any).parent_name === filters.family) return true;
        const pStr = (a as any).product_short_name || '';
        if (experimentMatchesFamily(pStr, filters.family as any)) return true;
        const famStr = (a as any).experiment_name || (a as any).campaign_name || '';
        return experimentMatchesFamily(famStr, filters.family as any);
      });
    }
    if (filters.product) {
      filteredActs = filteredActs.filter(a => {
        const pStr = (a as any).product_short_name || (a as any).asin || (a as any).experiment_name || (a as any).campaign_name || '';
        return pStr.toLowerCase().includes(filters.product!.toLowerCase());
      });
    }

    filteredActs.forEach(a => { const m = ACTION_META[a.action]; (g[m?.group || 'experiment'] || g.experiment).push(a); });
    return g;
  }, [acts, filters.family, filters.product]);

  const activeMeasures = useMemo(() => [...selectedMeasures], [selectedMeasures]);
  const primaryMeta = MEASURE_META[activeMeasures[0]];

  const effectivePeriodTrend = useMemo(() => {
    if (filters.periodType === 'cumulative') {
      if (periodMode === 'month') return 12;
      if (periodMode === 'quarter') return 4;
      return filters.periodTrend;
    }
    if (filters.periodType === 'peak' && pk?.pre_peak_start && pk?.peak_end) {
      const preStart = new Date(pk.pre_peak_start + 'T00:00:00');
      const peakEnd = new Date(pk.peak_end + 'T00:00:00');
      const diffMs = peakEnd.getTime() - preStart.getTime();
      const diffWeeks = Math.max(1, Math.ceil(diffMs / (7 * 86400000)));
      if (periodMode === 'weeks') return diffWeeks;
      if (periodMode === 'month') return Math.max(1, Math.ceil(diffWeeks / 4));
      if (periodMode === 'quarter') return Math.max(1, Math.ceil(diffWeeks / 13));
      return 1;
    }
    return filters.periodTrend;
  }, [filters.periodType, filters.periodTrend, periodMode, pk]);

  const amazonFeeRate = useMemo(() => {
    const products = data.products || [];
    const asinRows = data.weekly_trends_by_asin || [];
    const latestWeek = asinRows.length ? asinRows.reduce((best, r) => (r.week_start || '') > best ? (r.week_start || '') : best, '') : '';
    const latestAsinData = latestWeek ? asinRows.filter(r => r.week_start === latestWeek) : [];
    let totalUnits = 0;
    let totalFees = 0;
    for (const ar of latestAsinData) {
      const asin = (ar as { asin?: string }).asin || '';
      const prod = products.find(p => p.asin === asin);
      const u = ar.units || 0;
      if (prod && u > 0) {
        totalUnits += u;
        totalFees += u * (prod.fba_cost ?? 0);
      }
    }
    return totalUnits > 0 ? totalFees / totalUnits : 0;
  }, [data.products, data.weekly_trends_by_asin]);

  const storageCostLookup = useMemo(() => {
    const costs = data.storage_costs || [];
    const byWeek: Record<string, number> = {};
    const byFamilyWeek: Record<string, number> = {};
    const byAsinWeek: Record<string, number> = {};
    for (const c of costs) {
      const wk = c.week_start_date || '';
      byWeek[wk] = (byWeek[wk] || 0) + c.weekly_storage_cost;
      // Key the family rollup by asin→OI family — the storage view labels newer products
      // (e.g. Bunny) with their Amazon category, so product_type alone misses them.
      const fam = (c.asin && asinToFamily.get(c.asin)) || c.product_type;
      const fk = `${fam}|${wk}`;
      byFamilyWeek[fk] = (byFamilyWeek[fk] || 0) + c.weekly_storage_cost;
      if (c.asin) {
        const akWeek = `${c.asin}|${wk}`;
        byAsinWeek[akWeek] = (byAsinWeek[akWeek] || 0) + c.weekly_storage_cost;
      }
    }
    const byMonth: Record<string, number> = {};
    const byFamilyMonth: Record<string, number> = {};
    const byAsinMonth: Record<string, number> = {};
    for (const c of costs) {
      const mk = (c.week_start_date || '').slice(0, 7);
      if (!mk) continue;
      byMonth[mk] = (byMonth[mk] || 0) + c.weekly_storage_cost;
      const fam = (c.asin && asinToFamily.get(c.asin)) || c.product_type;
      const fk = `${fam}|${mk}`;
      byFamilyMonth[fk] = (byFamilyMonth[fk] || 0) + c.weekly_storage_cost;
      if (c.asin) {
        const akMonth = `${c.asin}|${mk}`;
        byAsinMonth[akMonth] = (byAsinMonth[akMonth] || 0) + c.weekly_storage_cost;
      }
    }
    return { byWeek, byMonth, byFamilyWeek, byFamilyMonth, byAsinWeek, byAsinMonth };
  }, [data.storage_costs, asinToFamily]);

  const trendData = useMemo(() => {
    type BucketVal = Record<TrendMeasure, { sum: number; count: number }>;
    type Bucket = BucketVal & { __units: number };
    const emptyBucket = (): Bucket => ({ ...Object.fromEntries(ALL_MEASURES.map(m => [m, { sum: 0, count: 0 }])) as unknown as BucketVal, __units: 0 });

    const addRow = (bucket: Bucket, row: TrendRow) => {
      for (const m of ALL_MEASURES) {
        const v = row[m as keyof TrendRow];
        bucket[m].sum += (typeof v === 'number' ? v : 0);
        bucket[m].count += 1;
      }
      bucket.__units += (row.units ?? row.orders ?? 0);
    };

    const resolve = (bucket: BucketVal): Record<string, number> => {
      const out: Record<string, number> = {};
      for (const m of activeMeasures) {
        const b = bucket[m];
        out[m] = b ? (AVG_MEASURES.has(m) ? (b.count ? b.sum / b.count : 0) : b.sum) : 0;
      }
      return out;
    };

    const pt = effectivePeriodTrend;
    let rawData: { label: string; hasSqp: boolean; ad_cost: number; net_profit: number; [k: string]: unknown }[] = [];
    if (periodMode === 'weeks') {
      const byWeek: Record<string, Bucket> = {};
      filteredWeekly.forEach(w => {
        const k = w.week_start || '';
        if (!byWeek[k]) byWeek[k] = emptyBucket();
        addRow(byWeek[k], w);
      });
      const weeks = Object.keys(byWeek).sort();
      const keep = new Set(getPeriodsToInclude(filters.specificPeriod, periodMode, weeks, pt));
      const entries = Object.entries(byWeek).filter(([w]) => keep.has(w)).sort(([a], [b]) => a.localeCompare(b));
      const findLyWeek = (w: string): string | null => {
        const target = new Date(w + 'T00:00:00');
        target.setDate(target.getDate() - 364);
        const targetTime = target.getTime();
        let best: string | null = null;
        let bestDiff = Infinity;
        for (const wk of weeks) {
          const diff = Math.abs(new Date(wk + 'T00:00:00').getTime() - targetTime);
          if (diff < bestDiff && diff <= 7 * 86400000) { bestDiff = diff; best = wk; }
        }
        return best;
      };
      const rawWeeks = entries.map(([w, d]) => {
        const r = resolve(d);
        const co = d?.ad_cost?.sum ?? 0;
        const sl = d?.sales?.sum ?? 0;
        const cg = d?.cogs?.sum ?? 0;
        const lyW = findLyWeek(w);
        const lyD = lyW ? byWeek[lyW] : null;
        const lyResolved: Record<string, number> = {};
        if (lyD && lyW) {
          for (const m of activeMeasures) {
            lyResolved[`ly_${m}`] = AVG_MEASURES.has(m) ? (lyD[m].count ? lyD[m].sum / lyD[m].count : 0) : lyD[m].sum;
          }
          const lyCo = lyD.ad_cost?.sum ?? 0;
          const lySl = lyD.sales?.sum ?? 0;
          const lyCg = lyD.cogs?.sum ?? 0;
          lyResolved.ly_ad_cost = lyCo;
          lyResolved.ly_net_profit = lyD.net_profit?.sum ?? (lySl - lyCg - lyCo);
        }
        return {
          label: weekRangeLabelCapped(w, perfMaxDate),
          weekKey: w,
          hasSqp: sqpWeeks.has(w),
          ...r, sales: sl, cogs: cg, ad_cost: co, net_profit: d?.net_profit?.sum ?? (sl - cg - co),
          net_roas: co ? (sl - cg) / co : 0,
          payment: 0,
          ...lyResolved,
        };
      });
      for (let i = 0; i < rawWeeks.length; i++) {
        const curWeekKey = entries[i][0];
        const curIdx = weeks.indexOf(curWeekKey);
        const prev2WeekKey = curIdx > 1 ? weeks[curIdx - 2] : '';
        const prev2Bucket = prev2WeekKey ? byWeek[prev2WeekKey] : null;
        const prev2Sales = prev2Bucket?.sales?.sum ?? 0;
        const curAdCost = entries[i][1]?.ad_cost?.sum ?? 0;
        const prev2Units = prev2Bucket?.__units ?? 0;
        const curStorage = curWeekKey ? (storageCostLookup.byWeek[curWeekKey] ?? 0) : 0;
        rawWeeks[i].payment = prev2Sales - curAdCost - (prev2Units * amazonFeeRate) - curStorage;
        (rawWeeks[i] as Record<string, unknown>).storage_cost = curStorage;
      }
      rawData = rawWeeks;
    } else if (periodMode === 'month') {
      const byMonth: Record<string, Bucket> = {};
      filteredMonthly.forEach(r => {
        const k = (r.month_start || '').slice(0, 7);
        if (!byMonth[k]) byMonth[k] = emptyBucket();
        addRow(byMonth[k], r);
      });

      if (filters.periodType === 'cumulative' || filters.periodType === 'peak') {
        const allMonths = Object.keys(byMonth).sort();
        const curYear = filters.specificPeriod
          ? filters.specificPeriod.slice(0, 4)
          : (allMonths[allMonths.length - 1] || '').slice(0, 4);
        const lyYear = String(parseInt(curYear, 10) - 1);
        const cyMonths = allMonths.filter(m => m.startsWith(curYear));
        const cutoffMonth = filters.specificPeriod
          ? (filters.specificPeriod.length >= 7 ? filters.specificPeriod.slice(0, 7) : `${curYear}-12`)
          : (cyMonths.length ? cyMonths[cyMonths.length - 1].slice(0, 7) : `${curYear}-12`);

        let monthSlots: string[];
        if (filters.periodType === 'peak' && pk?.pre_peak_start && pk?.peak_end) {
          const preStart = new Date(pk.pre_peak_start + 'T00:00:00');
          preStart.setMonth(preStart.getMonth() - 1);
          const peakEnd = new Date(pk.peak_end + 'T00:00:00');
          monthSlots = [];
          const cursor = new Date(preStart.getFullYear(), preStart.getMonth(), 1);
          while (cursor <= peakEnd) {
            const y = cursor.getFullYear();
            const m = String(cursor.getMonth() + 1).padStart(2, '0');
            monthSlots.push(`${y}-${m}`);
            cursor.setMonth(cursor.getMonth() + 1);
          }
        } else {
          monthSlots = Array.from({ length: 12 }, (_, i) => `${curYear}-${String(i + 1).padStart(2, '0')}`);
        }

        const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        rawData = monthSlots.map((m, idx) => {
          const mKey7 = m.slice(0, 7);
          const isCyActive = mKey7 <= cutoffMonth;

          let cyValues: Record<string, unknown> = {};
          if (isCyActive) {
            const d = byMonth[m] ?? emptyBucket();
            cyValues = resolve(d);
            const co = d.ad_cost?.sum ?? 0;
            const sl = d.sales?.sum ?? 0;
            const cg = d.cogs?.sum ?? 0;
            cyValues.sales = sl;
            cyValues.cogs = cg;
            cyValues.ad_cost = co;
            cyValues.net_profit = d.net_profit?.sum ?? (sl - cg - co);
            cyValues.net_roas = co ? (sl - cg) / co : 0;
            const prevMonth = idx > 0 ? monthSlots[idx - 1] : null;
            const prevSales = prevMonth ? (byMonth[prevMonth]?.sales?.sum ?? 0) : 0;
            const prevUnits = prevMonth ? (byMonth[prevMonth]?.__units ?? 0) : 0;
            const prevAdCost = prevMonth ? (byMonth[prevMonth]?.ad_cost?.sum ?? 0) : 0;
            const curUnits = d.__units ?? 0;
            const curMonthKey = m.slice(0, 7);
            const curStorage = curMonthKey ? (storageCostLookup.byMonth[curMonthKey] ?? 0) : 0;
            const prevNet = prevSales - prevAdCost - (prevUnits * amazonFeeRate);
            const curNet = sl - co - (curUnits * amazonFeeRate);
            cyValues.payment = 0.5 * prevNet + 0.5 * curNet - curStorage;
            cyValues.storage_cost = curStorage;
          } else {
            for (const mk of activeMeasures) cyValues[mk] = null;
            cyValues.ad_cost = null;
            cyValues.net_profit = null;
          }

          const lyM = lyYear + m.slice(4);
          const lyD = byMonth[lyM] ?? emptyBucket();
          const lyResolved: Record<string, number> = {};
          for (const mk of activeMeasures) {
            lyResolved[`ly_${mk}`] = AVG_MEASURES.has(mk) ? (lyD[mk].count ? lyD[mk].sum / lyD[mk].count : 0) : lyD[mk].sum;
          }
          const lyCo = lyD.ad_cost?.sum ?? 0;
          const lySl = lyD.sales?.sum ?? 0;
          const lyCg = lyD.cogs?.sum ?? 0;
          lyResolved.ly_ad_cost = lyCo;
          lyResolved.ly_net_profit = lyD.net_profit?.sum ?? (lySl - lyCg - lyCo);

          const monthIdx = parseInt(m.slice(5), 10) - 1;
          return { label: MONTH_NAMES[monthIdx] || m, weekKey: m, hasSqp: true, ...cyValues, ...lyResolved } as unknown as typeof rawData[0];
        });
      } else {
        const months = Object.keys(byMonth).sort();
        const keep = new Set(getPeriodsToInclude(filters.specificPeriod, periodMode, months, pt));
        const entries = Object.entries(byMonth).filter(([m]) => keep.has(m)).sort(([a], [b]) => a.localeCompare(b));
        rawData = entries.map(([m, d]) => { const r = resolve(d); const co = d.ad_cost?.sum ?? 0; const sl = d.sales?.sum ?? 0; const cg = d.cogs?.sum ?? 0; const np = d.net_profit?.sum ?? (sl - cg - co); const cu = d.__units ?? 0; const mIdx = months.indexOf(m); const prevMk = mIdx > 0 ? months[mIdx - 1] : ''; const prevBucket = prevMk ? byMonth[prevMk] : null; const prevSales = prevBucket?.sales?.sum ?? 0; const prevUnits = prevBucket?.__units ?? 0; const prevAd = prevBucket?.ad_cost?.sum ?? 0; const curMk = m.slice(0, 7); const curSt = curMk ? (storageCostLookup.byMonth[curMk] ?? 0) : 0; const prevNet = prevSales - prevAd - (prevUnits * amazonFeeRate); const curNet = sl - co - (cu * amazonFeeRate); return { label: m, weekKey: m, hasSqp: true, ...r, sales: sl, cogs: cg, ad_cost: co, net_profit: np, net_roas: co ? (sl - cg) / co : 0, payment: 0.5 * prevNet + 0.5 * curNet - curSt, storage_cost: curSt }; });
      }
    } else if (periodMode === 'quarter') {
      const byQuarter: Record<string, Bucket> = {};
      filteredMonthly.forEach(r => {
        const ms = r.month_start || '';
        const m = parseInt(ms.slice(5, 7), 10);
        const q = Math.ceil(m / 3);
        const k = `${ms.slice(0, 4)}-Q${q}`;
        if (!byQuarter[k]) byQuarter[k] = emptyBucket();
        addRow(byQuarter[k], r);
      });
      const quarters = Object.keys(byQuarter).sort();
      const keep = new Set(getPeriodsToInclude(filters.specificPeriod, periodMode, quarters, pt));
      const entries = Object.entries(byQuarter).filter(([q]) => keep.has(q)).sort(([a], [b]) => a.localeCompare(b));
      rawData = entries.map(([q, d], idx) => {
        const r = resolve(d);
        const co = d.ad_cost?.sum ?? 0;
        const sl = d.sales?.sum ?? 0;
        const cg = d.cogs?.sum ?? 0;
        const prevSales = idx > 0 ? (entries[idx - 1][1]?.sales?.sum ?? 0) : 0;
        const prevUnits = idx > 0 ? (entries[idx - 1][1]?.__units ?? 0) : 0;
        const prevAd = idx > 0 ? (entries[idx - 1][1]?.ad_cost?.sum ?? 0) : 0;
        const curUnits = d.__units ?? 0;
        const [yr, qtr] = q.split('-Q');
        const mStart = (parseInt(qtr, 10) - 1) * 3 + 1;
        let curSt = 0;
        for (let m = 0; m < 3; m++) {
          curSt += storageCostLookup.byMonth[`${yr}-${String(mStart + m).padStart(2, '0')}`] ?? 0;
        }
        const prevNet = prevSales - prevAd - (prevUnits * amazonFeeRate);
        const curNet = sl - co - (curUnits * amazonFeeRate);
        return { label: q, weekKey: q, hasSqp: true, ...r, sales: sl, cogs: cg, ad_cost: co, net_profit: d.net_profit?.sum ?? (sl - cg - co), net_roas: co ? (sl - cg) / co : 0, payment: 0.5 * prevNet + 0.5 * curNet - curSt, storage_cost: curSt };
      });
    } else {
      const byYear: Record<string, Bucket> = {};
      filteredMonthly.forEach(r => {
        const y = (r.month_start || '').slice(0, 4);
        if (!byYear[y]) byYear[y] = emptyBucket();
        addRow(byYear[y], r);
      });
      const years = Object.keys(byYear).sort();
      const keep = new Set(getPeriodsToInclude(filters.specificPeriod, periodMode, years, pt));
      const entries = Object.entries(byYear).filter(([y]) => keep.has(y)).sort(([a], [b]) => a.localeCompare(b));
      rawData = entries.map(([y, d], idx) => {
        const r = resolve(d);
        const co = d.ad_cost?.sum ?? 0;
        const sl = d.sales?.sum ?? 0;
        const cg = d.cogs?.sum ?? 0;
        const prevSales = idx > 0 ? (entries[idx - 1][1]?.sales?.sum ?? 0) : 0;
        const prevUnits = idx > 0 ? (entries[idx - 1][1]?.__units ?? 0) : 0;
        const prevAd = idx > 0 ? (entries[idx - 1][1]?.ad_cost?.sum ?? 0) : 0;
        const curUnits = d.__units ?? 0;
        let curSt = 0;
        for (let m = 1; m <= 12; m++) {
          curSt += storageCostLookup.byMonth[`${y}-${String(m).padStart(2, '0')}`] ?? 0;
        }
        const prevNet = prevSales - prevAd - (prevUnits * amazonFeeRate);
        const curNet = sl - co - (curUnits * amazonFeeRate);
        return { label: y, hasSqp: true, ...r, sales: sl, cogs: cg, ad_cost: co, net_profit: d.net_profit?.sum ?? (sl - cg - co), net_roas: co ? (sl - cg) / co : 0, payment: 0.5 * prevNet + 0.5 * curNet - curSt, storage_cost: curSt };
      });
    }

    if ((filters.periodType === 'cumulative' || filters.periodType === 'peak') && rawData.length > 0) {
      const lyKeys = activeMeasures.map(m => `ly_${m}`);
      // Exclude ratio measures from naive summation — they'll be recalculated
      const RATIO_MEASURES = new Set(['net_roas', 'organic_pct']);
      const sumMeasures = (activeMeasures as unknown as string[]).filter(m => !RATIO_MEASURES.has(m));
      const cumulativeKeys = [...new Set([...sumMeasures, 'ad_cost', 'net_profit', 'sales', 'cogs', ...lyKeys, 'ly_ad_cost', 'ly_net_profit', 'ly_sales', 'ly_cogs'])];
      const running: Record<string, number> = {};
      return rawData.map(row => {
        const newRow = { ...row };
        for (const key of cumulativeKeys) {
          const val = (row as Record<string, unknown>)[key];
          if (typeof val === 'number') {
            running[key] = (running[key] ?? 0) + val;
            (newRow as Record<string, unknown>)[key] = running[key];
          }
        }
        // Recalculate ratio measures from running totals
        const cumSales = running['sales'] ?? 0;
        const cumCogs = running['cogs'] ?? 0;
        const cumAdCost = running['ad_cost'] ?? 0;
        (newRow as Record<string, unknown>)['net_roas'] = cumAdCost ? (cumSales - cumCogs) / cumAdCost : 0;
        const cumOrders = running['orders'] ?? 0;
        const cumOrgPWeighted = running['organic_pct'] ?? 0;
        (newRow as Record<string, unknown>)['organic_pct'] = cumOrders ? cumOrgPWeighted / cumOrders : 0;
        return newRow;
      });
    }

    return rawData;
  }, [filteredWeekly, filteredMonthly, periodMode, activeMeasures, sqpWeeks, filters.specificPeriod, effectivePeriodTrend, filters.periodType, amazonFeeRate, storageCostLookup, perfMaxDate]);

  const miniTrendData = useMemo(() => {
    if (!trendData.length) return { roasTrend: [], pdTrend: [], profitYoyTrend: [], avgScoreTrend: [] };
    const getPeriodKey = (row: (typeof trendData)[0]) =>
      (row as { weekKey?: string }).weekKey || row.label;
    const periodKeys = trendData.map(getPeriodKey).filter(Boolean) as string[];
    if (!periodKeys.length) return { roasTrend: [], pdTrend: [], profitYoyTrend: [], avgScoreTrend: [] };
    if (periodMode === 'weeks') {
      const byWeek: Record<string, { sl: number; cg: number; co: number }> = {};
      filteredWeekly.forEach(w => {
        const k = w.week_start || '';
        if (!byWeek[k]) byWeek[k] = { sl: 0, cg: 0, co: 0 };
        byWeek[k].sl += w.sales || 0;
        byWeek[k].cg += w.cogs || 0;
        byWeek[k].co += w.ad_cost || 0;
      });
      const entries = periodKeys.map(k => [k, byWeek[k] ?? { sl: 0, cg: 0, co: 0 }] as const);
      const roasTrend = entries.map(([, d]) => d.co ? (d.sl - d.cg) / d.co : 0);
      const pdTrend = entries.map((_, i) => {
        if (i === 0) return 0;
        const cur = entries[i][1];
        const prev = entries[i - 1][1];
        const curNp = cur.sl - cur.cg - cur.co;
        const prevNp = prev.sl - prev.cg - prev.co;
        return prevNp ? ((curNp - prevNp) / Math.abs(prevNp)) * 100 : 0;
      });
      const profitYoyTrend = entries.map(([w]) => {
        const lyWeek = shiftYear(w, -1);
        const lyData = byWeek[lyWeek];
        if (!lyData) return 0;
        const lyNp = lyData.sl - lyData.cg - lyData.co;
        const cur = byWeek[w];
        if (!cur || !lyNp) return 0;
        const curNp = cur.sl - cur.cg - cur.co;
        return ((curNp - lyNp) / Math.abs(lyNp)) * 100;
      });
      const avgScoreTrend = entries.map((_, i) => {
        const s1 = scoreFromRoas(roasTrend[i]);
        const s2 = scoreFromProfitDelta(pdTrend[i]);
        const s3 = scoreFromProfitDelta(profitYoyTrend[i]);
        return (s1 + s2 + s3) / 3;
      });
      return { roasTrend, pdTrend, profitYoyTrend, avgScoreTrend };
    }
    if (periodMode === 'month') {
      const byMonth: Record<string, { sl: number; cg: number; co: number }> = {};
      filteredMonthly.forEach(r => {
        const k = (r.month_start || '').slice(0, 7);
        if (!byMonth[k]) byMonth[k] = { sl: 0, cg: 0, co: 0 };
        byMonth[k].sl += r.sales || 0;
        byMonth[k].cg += r.cogs || 0;
        byMonth[k].co += r.ad_cost || 0;
      });
      const entries = periodKeys.map(k => [k, byMonth[k] ?? { sl: 0, cg: 0, co: 0 }] as const);
      const roasTrend = entries.map(([, d]) => d.co ? (d.sl - d.cg) / d.co : 0);
      const pdTrend = entries.map((_, i) => {
        if (i === 0) return 0;
        const cur = entries[i][1];
        const prev = entries[i - 1][1];
        const curNp = cur.sl - cur.cg - cur.co;
        const prevNp = prev.sl - prev.cg - prev.co;
        return prevNp ? ((curNp - prevNp) / Math.abs(prevNp)) * 100 : 0;
      });
      const profitYoyTrend = entries.map(([m]) => {
        const ly = shiftYear(m + '-01', -1).slice(0, 7);
        const lyData = byMonth[ly];
        if (!lyData) return 0;
        const lyNp = lyData.sl - lyData.cg - lyData.co;
        const cur = byMonth[m];
        if (!cur || !lyNp) return 0;
        const curNp = cur.sl - cur.cg - cur.co;
        return ((curNp - lyNp) / Math.abs(lyNp)) * 100;
      });
      const avgScoreTrend = entries.map((_, i) => {
        const s1 = scoreFromRoas(roasTrend[i]);
        const s2 = scoreFromProfitDelta(pdTrend[i]);
        const s3 = scoreFromProfitDelta(profitYoyTrend[i]);
        return (s1 + s2 + s3) / 3;
      });
      return { roasTrend, pdTrend, profitYoyTrend, avgScoreTrend };
    }
    if (periodMode === 'quarter') {
      const byQuarter: Record<string, { sl: number; cg: number; co: number }> = {};
      filteredMonthly.forEach(r => {
        const k = periodKey(r.month_start || '', 'quarter');
        if (!byQuarter[k]) byQuarter[k] = { sl: 0, cg: 0, co: 0 };
        byQuarter[k].sl += r.sales || 0;
        byQuarter[k].cg += r.cogs || 0;
        byQuarter[k].co += r.ad_cost || 0;
      });
      const entries = periodKeys.map(k => [k, byQuarter[k] ?? { sl: 0, cg: 0, co: 0 }] as const);
      const roasTrend = entries.map(([, d]) => d.co ? (d.sl - d.cg) / d.co : 0);
      const pdTrend = entries.map((_, i) => {
        if (i === 0) return 0;
        const cur = entries[i][1];
        const prev = entries[i - 1][1];
        const curNp = cur.sl - cur.cg - cur.co;
        const prevNp = prev.sl - prev.cg - prev.co;
        return prevNp ? ((curNp - prevNp) / Math.abs(prevNp)) * 100 : 0;
      });
      const profitYoyTrend = entries.map(() => 0);
      const avgScoreTrend = entries.map((_, i) => {
        const s1 = scoreFromRoas(roasTrend[i]);
        const s2 = scoreFromProfitDelta(pdTrend[i]);
        const s3 = scoreFromProfitDelta(profitYoyTrend[i]);
        return (s1 + s2 + s3) / 3;
      });
      return { roasTrend, pdTrend, profitYoyTrend, avgScoreTrend };
    }
    const byYear: Record<string, { sl: number; cg: number; co: number }> = {};
    filteredMonthly.forEach(r => {
      const y = (r.month_start || '').slice(0, 4);
      if (!byYear[y]) byYear[y] = { sl: 0, cg: 0, co: 0 };
      byYear[y].sl += r.sales || 0;
      byYear[y].cg += r.cogs || 0;
      byYear[y].co += r.ad_cost || 0;
    });
    const entries = periodKeys.map(k => [k, byYear[k] ?? { sl: 0, cg: 0, co: 0 }] as const);
    const roasTrend = entries.map(([, d]) => d.co ? (d.sl - d.cg) / d.co : 0);
    const pdTrend = entries.map((_, i) => {
      if (i === 0) return 0;
      const cur = entries[i][1];
      const prev = entries[i - 1][1];
      const curNp = cur.sl - cur.cg - cur.co;
      const prevNp = prev.sl - prev.cg - prev.co;
      return prevNp ? ((curNp - prevNp) / Math.abs(prevNp)) * 100 : 0;
    });
    const profitYoyTrend = entries.map(([y]) => {
      const ly = String(Number(y) - 1);
      const lyData = byYear[ly];
      if (!lyData) return 0;
      const lyNp = lyData.sl - lyData.cg - lyData.co;
      const cur = byYear[y];
      if (!cur || !lyNp) return 0;
      const curNp = cur.sl - cur.cg - cur.co;
      return ((curNp - lyNp) / Math.abs(lyNp)) * 100;
    });
    const avgScoreTrend = entries.map((_, i) => {
      const s1 = scoreFromRoas(roasTrend[i]);
      const s2 = scoreFromProfitDelta(pdTrend[i]);
      const s3 = scoreFromProfitDelta(profitYoyTrend[i]);
      return (s1 + s2 + s3) / 3;
    });
    return { roasTrend, pdTrend, profitYoyTrend, avgScoreTrend };
  }, [trendData, filteredWeekly, filteredMonthly, periodMode]);

  const kpiSparklineData = useMemo(() => {
    if (!trendData.length) return { sales: [], ad_cost: [], profit: [], roas: [], organic: [] };
    const getPeriodKey = (row: (typeof trendData)[0]) =>
      (row as { weekKey?: string }).weekKey || row.label;
    const periodKeys = trendData.map(getPeriodKey).filter(Boolean) as string[];
    if (!periodKeys.length) return { sales: [], ad_cost: [], profit: [], roas: [], organic: [] };

    if (periodMode === 'weeks') {
      const byWeek: Record<string, { sl: number; cg: number; co: number; or: number; orgP: number }> = {};
      filteredWeekly.forEach(w => {
        const k = w.week_start || '';
        if (!byWeek[k]) byWeek[k] = { sl: 0, cg: 0, co: 0, or: 0, orgP: 0 };
        const cur = byWeek[k];
        cur.sl += w.sales || 0;
        cur.cg += w.cogs || 0;
        cur.co += w.ad_cost || 0;
        cur.or += w.orders || 0;
        cur.orgP += (w.organic_pct || 0) * (w.orders || 0);
      });
      Object.keys(byWeek).forEach(k => {
        const c = byWeek[k];
        c.orgP = c.or ? c.orgP / c.or : 0;
      });
      const allWeekKeys = Object.keys(byWeek).sort();
      const findLyWeek = (wk: string): string | null => {
        const target = new Date(wk + 'T00:00:00');
        target.setDate(target.getDate() - 364);
        const targetTime = target.getTime();
        let best: string | null = null, bestDiff = Infinity;
        for (const k2 of allWeekKeys) {
          const diff = Math.abs(new Date(k2 + 'T00:00:00').getTime() - targetTime);
          if (diff < bestDiff && diff <= 7 * 86400000) { bestDiff = diff; best = k2; }
        }
        return best;
      };
      const sales = periodKeys.map(k => (byWeek[k] ?? { sl: 0 }).sl);
      const ad_cost = periodKeys.map(k => (byWeek[k] ?? { co: 0 }).co);
      const profit = periodKeys.map(k => {
        const d = byWeek[k];
        return d ? d.sl - d.cg - d.co : 0;
      });
      const roas = periodKeys.map(k => {
        const d = byWeek[k];
        return d?.co ? (d.sl - d.cg) / d.co : 0;
      });
      const organic = periodKeys.map(k => (byWeek[k] ?? { orgP: 0 }).orgP);
      const salesLy = periodKeys.map(k => { const ly = findLyWeek(k); const d = ly ? byWeek[ly] : null; return d ? d.sl : 0; });
      const ad_costLy = periodKeys.map(k => { const ly = findLyWeek(k); const d = ly ? byWeek[ly] : null; return d ? d.co : 0; });
      const profitLy = periodKeys.map(k => { const ly = findLyWeek(k); const d = ly ? byWeek[ly] : null; return d ? d.sl - d.cg - d.co : 0; });
      const roasLy = periodKeys.map(k => { const ly = findLyWeek(k); const d = ly ? byWeek[ly] : null; return d?.co ? (d.sl - d.cg) / d.co : 0; });
      const organicLy = periodKeys.map(k => { const ly = findLyWeek(k); const d = ly ? byWeek[ly] : null; return d ? d.orgP : 0; });
      return { sales, ad_cost, profit, roas, organic, salesLy, ad_costLy, profitLy, roasLy, organicLy };
    }
    if (periodMode === 'month') {
      const byMonth: Record<string, { sl: number; cg: number; co: number; or: number; orgP: number }> = {};
      filteredMonthly.forEach(r => {
        const k = (r.month_start || '').slice(0, 7);
        if (!byMonth[k]) byMonth[k] = { sl: 0, cg: 0, co: 0, or: 0, orgP: 0 };
        const cur = byMonth[k];
        cur.sl += r.sales || 0;
        cur.cg += r.cogs || 0;
        cur.co += r.ad_cost || 0;
        cur.or += r.orders || 0;
        cur.orgP += (r.organic_pct || 0) * (r.orders || 0);
      });
      Object.keys(byMonth).forEach(k => {
        const c = byMonth[k];
        c.orgP = c.or ? c.orgP / c.or : 0;
      });
      const sales = periodKeys.map(k => (byMonth[k] ?? { sl: 0 }).sl);
      const ad_cost = periodKeys.map(k => (byMonth[k] ?? { co: 0 }).co);
      const profit = periodKeys.map(k => {
        const d = byMonth[k];
        return d ? d.sl - d.cg - d.co : 0;
      });
      const profitLy = periodKeys.map(k => {
        const lyK = shiftYear(k + '-01', -1).slice(0, 7);
        const d = byMonth[lyK];
        return d ? d.sl - d.cg - d.co : 0;
      });
      const roas = periodKeys.map(k => {
        const d = byMonth[k];
        return d?.co ? (d.sl - d.cg) / d.co : 0;
      });
      const organic = periodKeys.map(k => (byMonth[k] ?? { orgP: 0 }).orgP);
      return { sales, ad_cost, profit, profitLy, roas, organic };
    }
    if (periodMode === 'quarter') {
      const byQuarter: Record<string, { sl: number; cg: number; co: number; or: number; orgP: number }> = {};
      filteredMonthly.forEach(r => {
        const k = periodKey(r.month_start || '', 'quarter');
        if (!byQuarter[k]) byQuarter[k] = { sl: 0, cg: 0, co: 0, or: 0, orgP: 0 };
        const cur = byQuarter[k];
        cur.sl += r.sales || 0;
        cur.cg += r.cogs || 0;
        cur.co += r.ad_cost || 0;
        cur.or += r.orders || 0;
        cur.orgP += (r.organic_pct || 0) * (r.orders || 0);
      });
      Object.keys(byQuarter).forEach(k => {
        const c = byQuarter[k];
        c.orgP = c.or ? c.orgP / c.or : 0;
      });
      const sales = periodKeys.map(k => (byQuarter[k] ?? { sl: 0 }).sl);
      const ad_cost = periodKeys.map(k => (byQuarter[k] ?? { co: 0 }).co);
      const profit = periodKeys.map(k => {
        const d = byQuarter[k];
        return d ? d.sl - d.cg - d.co : 0;
      });
      const roas = periodKeys.map(k => {
        const d = byQuarter[k];
        return d?.co ? (d.sl - d.cg) / d.co : 0;
      });
      const organic = periodKeys.map(k => (byQuarter[k] ?? { orgP: 0 }).orgP);
      return { sales, ad_cost, profit, roas, organic };
    }
    const byYear: Record<string, { sl: number; cg: number; co: number; or: number; orgP: number }> = {};
    filteredMonthly.forEach(r => {
      const y = (r.month_start || '').slice(0, 4);
      if (!byYear[y]) byYear[y] = { sl: 0, cg: 0, co: 0, or: 0, orgP: 0 };
      const cur = byYear[y];
      cur.sl += r.sales || 0;
      cur.cg += r.cogs || 0;
      cur.co += r.ad_cost || 0;
      cur.or += r.orders || 0;
      cur.orgP += (r.organic_pct || 0) * (r.orders || 0);
    });
    Object.keys(byYear).forEach(k => {
      const c = byYear[k];
      c.orgP = c.or ? c.orgP / c.or : 0;
    });
    const sales = periodKeys.map(k => (byYear[k] ?? { sl: 0 }).sl);
    const ad_cost = periodKeys.map(k => (byYear[k] ?? { co: 0 }).co);
    const profit = periodKeys.map(k => {
      const d = byYear[k];
      return d ? d.sl - d.cg - d.co : 0;
    });
    const profitLy = periodKeys.map(k => {
      const lyK = String(Number(k) - 1);
      const d = byYear[lyK];
      return d ? d.sl - d.cg - d.co : 0;
    });
    const roas = periodKeys.map(k => {
      const d = byYear[k];
      return d?.co ? (d.sl - d.cg) / d.co : 0;
    });
    const organic = periodKeys.map(k => (byYear[k] ?? { orgP: 0 }).orgP);
    return { sales, ad_cost, profit, profitLy, roas, organic };
  }, [trendData, filteredWeekly, filteredMonthly, periodMode]);

  const familyPeriodData = useMemo(() => {
    const dateKey = periodDateKey(periodMode);
    let srcAll: TrendRow[] = filters.product
      ? (periodMode === 'weeks' ? (data.weekly_trends_by_asin || []) : (data.monthly_trends_by_asin || []))
          .filter((r: TrendRow & { asin?: string }) => r.asin === filters.product)
      : (periodMode === 'weeks' ? (data.weekly_trends || []) : (data.monthly_trends || []));
    srcAll = filterBySeasonality(srcAll, dateKey, filters.seasonality, pk);

    const allPeriods = [...new Set(srcAll.map(r => r[dateKey] || ''))].filter(Boolean).sort();
    const periodsForTable = 2;
    let periods: string[];
    if (filters.specificPeriod) {
      const sp = filters.specificPeriod;
      if (periodMode === 'weeks') {
        periods = allPeriods.filter(p => p === sp);
      } else if (periodMode === 'quarter') {
        periods = allPeriods.filter(p => periodKey(p, 'quarter') === sp);
      } else {
        periods = allPeriods.filter(p => p.startsWith(sp));
      }
      if (!periods.length) periods = allPeriods.slice(-1);
    } else if (periodMode === 'year') {
      const years = [...new Set(allPeriods.map(p => p.slice(0, 4)))].sort();
      periods = allPeriods.filter(p => new Set(sliceByPeriod(years, null, periodsForTable)).has(p.slice(0, 4)));
    } else if (periodMode === 'quarter') {
      const allQuarters = [...new Set(allPeriods.map(p => periodKey(p, 'quarter')))].sort();
      const keepQ = sliceByPeriod(allQuarters, null, periodsForTable);
      const keepQSet = new Set(keepQ);
      periods = allPeriods.filter(p => keepQSet.has(periodKey(p, 'quarter')));
    } else {
      periods = sliceByPeriod(allPeriods, null, periodsForTable);
    }

    if (!periods.length) return null;

    // Show a family if it had sales this period OR holds stock anywhere (FBA/AWD/in-transit/mfr).
    // Families with stock but no sales (e.g. newly launched) are surfaced too.
    const familiesWithSales = [...new Set(srcAll.map(r => r.product_type))].filter(Boolean);
    const families = filters.family
      ? (familiesWithSales.includes(filters.family) || familiesWithStock.has(filters.family) ? [filters.family] : [])
      : [...new Set([...familiesWithSales, ...familiesWithStock])].filter(Boolean).sort();

    let latest: string[];
    let prev: string[];
    if (filters.specificPeriod) {
      latest = periods;
      prev = [];
    } else if (periodMode === 'weeks') {
      latest = kpiWeek ? [kpiWeek] : (periods.length ? [periods[periods.length - 1]] : []);
      prev = kpiPrevWeek ? [kpiPrevWeek] : [];
    } else if (periodMode === 'year') {
      const years = [...new Set(periods.map(p => p.slice(0, 4)))].sort();
      const keepYears = getPeriodsToInclude(null, 'year', years, periodsForTable);
      const curYear = keepYears[keepYears.length - 1] || '';
      const prvYear = keepYears.length >= 2 ? keepYears[keepYears.length - 2] : '';
      latest = curYear ? periods.filter(p => p.slice(0, 4) === curYear) : periods;
      prev = prvYear ? periods.filter(p => p.slice(0, 4) === prvYear) : [];
    } else if (periodMode === 'quarter') {
      const allQuarters = [...new Set(periods.map(p => periodKey(p, 'quarter')))].sort();
      const keepQ = getPeriodsToInclude(null, 'quarter', allQuarters, periodsForTable);
      const curQ = keepQ[keepQ.length - 1] || '';
      const prvQ = keepQ.length >= 2 ? keepQ[keepQ.length - 2] : '';
      latest = curQ ? periods.filter(p => periodKey(p, 'quarter') === curQ) : periods;
      prev = prvQ ? periods.filter(p => periodKey(p, 'quarter') === prvQ) : [];
    } else {
      latest = [periods[periods.length - 1]];
      prev = periods.length >= 2 ? [periods[periods.length - 2]] : [];
    }

    const aggRows = (rows: TrendRow[]) => {
      const t = { sales: 0, ad_cost: 0, cogs: 0, net_profit: 0, orders: 0, clicks: 0, sessions: 0, units: 0, _cnt: 0 };
      rows.forEach(r => {
        t.sales += r.sales || 0; t.ad_cost += r.ad_cost || 0; t.cogs += r.cogs || 0;
        t.net_profit += r.net_profit || 0; t.orders += r.orders || 0; t.clicks += r.clicks || 0;
        t.sessions += r.sessions || 0; t.units += r.units || 0; t._cnt += 1;
      });
      return t;
    };

    const familyAds = famRecord<number>(() => 0);
    const familyAdsSales = famRecord<number>(() => 0);
    const familyAdsUnits = famRecord<number>(() => 0);
    for (const [key, val] of Object.entries(adsDataByProductAndPeriod.spend)) {
      const [name, period] = key.split('|');
      const fam = productToFamily[name] || ((FAM_KEYS as string[]).includes(name) ? name as FamilyName : null);
      if (fam && latest.some(p => periodKey(p, periodMode) === period)) familyAds[fam] += val;
    }
    for (const [key, val] of Object.entries(adsDataByProductAndPeriod.sales)) {
      const [name, period] = key.split('|');
      const fam = productToFamily[name] || ((FAM_KEYS as string[]).includes(name) ? name as FamilyName : null);
      if (fam && latest.some(p => periodKey(p, periodMode) === period)) familyAdsSales[fam] += val;
    }
    for (const [key, val] of Object.entries(adsDataByProductAndPeriod.units)) {
      const [name, period] = key.split('|');
      const fam = productToFamily[name] || ((FAM_KEYS as string[]).includes(name) ? name as FamilyName : null);
      if (fam && latest.some(p => periodKey(p, periodMode) === period)) familyAdsUnits[fam] += val;
    }

    return families.map(fam => {
      const famRows = srcAll.filter(r => r.product_type === fam);
      const curRows = famRows.filter(r => latest.includes(r[dateKey] || ''));
      const prevRows = prev.length ? famRows.filter(r => prev.includes(r[dateKey] || '')) : [];
      const cur = aggRows(curRows);
      const prv = prevRows.length ? aggRows(prevRows) : null;
      const familyName = famFromType(fam) as FamilyName | null;
      const curAdsSales = familyName ? familyAdsSales[familyName] : 0;
      const curAdsUnits = familyName ? familyAdsUnits[familyName] : 0;
      const curWithAds = { ...cur, ads_sales: curAdsSales, ads_units: Math.round(curAdsUnits) };
      const net_roas = curWithAds.ad_cost ? (curWithAds.sales - curWithAds.cogs) / curWithAds.ad_cost : 0;
      const organic_pct = cur.orders > 0
        ? (curRows.reduce((s, r) => s + ((r.organic_pct || 0) * (r.orders || 0)), 0) / cur.orders)
        : 0;
      const organic_units = Math.round(cur.units * organic_pct / 100);
      const ad_orders = curWithAds.ads_units;
      const sc = prv && prv.sales ? ((curWithAds.sales - prv.sales) / prv.sales) * 100 : 0;
      const units = cur.units;
      const famProducts = (data.products || []).filter(p => famFromType(p.product_type || '') === familyName);
      let famFeeTotal = 0;
      if (prv && famProducts.length > 0) {
        const asinUnits: Record<string, number> = {};
        for (const r of prevRows) {
          const asin = (r as { asin?: string }).asin || '';
          if (asin) asinUnits[asin] = (asinUnits[asin] || 0) + (r.units || 0);
        }
        for (const [asin, u] of Object.entries(asinUnits)) {
          const prod = famProducts.find(p => p.asin === asin);
          if (prod) famFeeTotal += u * (prod.fba_cost ?? 0);
          else famFeeTotal += u * amazonFeeRate;
        }
        if (Object.keys(asinUnits).length === 0) famFeeTotal = (prv.units || 0) * amazonFeeRate;
      } else if (prv) {
        famFeeTotal = (prv.units || 0) * amazonFeeRate;
      }
      let curFeeTotal = 0;
      if (famProducts.length > 0) {
        const curAsinUnits: Record<string, number> = {};
        for (const r of curRows) {
          const asin = (r as { asin?: string }).asin || '';
          if (asin) curAsinUnits[asin] = (curAsinUnits[asin] || 0) + (r.units || 0);
        }
        for (const [asin, u] of Object.entries(curAsinUnits)) {
          const prod = famProducts.find(p => p.asin === asin);
          if (prod) curFeeTotal += u * (prod.fba_cost ?? 0);
          else curFeeTotal += u * amazonFeeRate;
        }
        if (Object.keys(curAsinUnits).length === 0) curFeeTotal = (cur.units || 0) * amazonFeeRate;
      } else {
        curFeeTotal = (cur.units || 0) * amazonFeeRate;
      }
      const prevAdCost = prv ? prv.ad_cost : 0;
      const prevNet = (prv ? prv.sales : 0) - prevAdCost - famFeeTotal;
      const curNet = curWithAds.sales - curWithAds.ad_cost - curFeeTotal;
      const payment_no_storage = 0.5 * prevNet + 0.5 * curNet;
      let famStorageCost = 0;
      if (latest.length > 0) {
        const lookup = periodMode === 'weeks' ? storageCostLookup.byFamilyWeek : storageCostLookup.byFamilyMonth;
        for (const pd of latest) {
          const key = periodMode === 'weeks' ? `${fam}|${pd}` : `${fam}|${pd.slice(0, 7)}`;
          famStorageCost += lookup[key] ?? 0;
        }
      }
      const storage_cost = famStorageCost;
      const payment = payment_no_storage - storage_cost;
      // Per-family inventory totals (snapshot — not period-scaled). Coverage is recomputed
      // from summed stock ÷ summed velocity since days-of-coverage isn't additive.
      const supply = supplyByFamily[fam];
      const velocity = supply?.velocity ?? 0;
      const cov = (qty: number) => (velocity > 0 ? Math.round(qty / velocity) : null);
      return {
        family: fam, ...curWithAds, units, net_roas, organic_pct, organic_units, ad_orders,
        clicks: curWithAds.clicks, sales_change: sc, sessions: curWithAds.sessions, payment, storage_cost,
        fba_stock_qty: supply?.fba ?? 0, awd_stock_qty: supply?.awd ?? 0,
        in_transit_qty: supply?.in_transit ?? 0, mfr_stock_qty: supply?.mfr ?? 0,
        days_of_coverage: cov(supply?.sellable ?? 0),
        fba_days_of_coverage: cov(supply?.fba ?? 0),
        awd_days_of_coverage: cov(supply?.awd ?? 0),
        qty_next_shipment: supply?.next_ship_qty ?? 0, last_30d_sold: supply?.last_30d_sold ?? 0,
        next_30d_planned: supply?.next_30d ?? 0, next_31_60d_planned: supply?.next_31_60 ?? 0, next_61_90d_planned: supply?.next_61_90 ?? 0,
      };
    });
  }, [data.weekly_trends, data.monthly_trends, data.weekly_trends_by_asin, data.monthly_trends_by_asin, data.products, periodMode, kpiWeek, kpiPrevWeek, filters.family, filters.product, filters.specificPeriod, filters.seasonality, pk, adsDataByProductAndPeriod, productToFamily, amazonFeeRate, storageCostLookup, supplyByFamily]);

  const variationByFamily = useMemo(() => {
    const sqp = data.sqp_weekly || [];
    if (!kpiWeek || !sqp.length) return famRecord(() => []) as Record<FamilyName, { asin: string; name: string; orders: number; clicks: number; adsOrders: number }[]>;
    const matchWeek = (w: string) => {
      if (periodMode === 'weeks') return w === kpiWeek;
      return periodKey(w, periodMode) === kpiWeek;
    };
    let filtered = sqp.filter(r => matchWeek(r.week_start || ''));
    if (filters.product) filtered = filtered.filter(r => r.asin === filters.product);
    const byFamily: Record<string, Record<string, { asin: string; name: string; orders: number; clicks: number; adsOrders: number }>> = {};
    filtered.forEach(r => {
      const fam = famFromType(r.product_type) as FamilyName | null;
      if (!fam) return;
      if (!byFamily[fam]) byFamily[fam] = {};
      const key = r.asin || r.product_short_name || '';
      if (!byFamily[fam][key]) byFamily[fam][key] = { asin: r.asin || '', name: r.product_short_name || r.asin || '', orders: 0, clicks: 0, adsOrders: 0 };
      byFamily[fam][key].orders += r.orders || 0;
      byFamily[fam][key].clicks += r.clicks || 0;
      byFamily[fam][key].adsOrders += r.ads_orders || 0;
    });
    const result: Record<FamilyName, { asin: string; name: string; orders: number; clicks: number; adsOrders: number }[]> = famRecord(() => []);
    (Object.keys(byFamily) as FamilyName[]).forEach(fam => {
      result[fam] = Object.values(byFamily[fam]).sort((a, b) => b.orders - a.orders);
    });
    return result;
  }, [data.sqp_weekly, kpiWeek, periodMode, filters.product]);

  const changesByFamily = useMemo(() => {
    if (!effectivePrevTotals || !kpiWeek || !kpiPrevWeek) return [];
    const dateKey = periodDateKey(periodMode);
    let srcAll: TrendRow[] = filters.product
      ? (periodMode === 'weeks' ? (data.weekly_trends_by_asin || []) : (data.monthly_trends_by_asin || []))
          .filter((r: TrendRow & { asin?: string }) => r.asin === filters.product)
      : (periodMode === 'weeks' ? (data.weekly_trends || []) : (data.monthly_trends || []));
    srcAll = filterBySeasonality(srcAll, dateKey, filters.seasonality, pk);

    const matchCur = (r: TrendRow) => {
      const v = r[dateKey] || '';
      if (periodMode === 'weeks') return v === kpiWeek;
      return periodKey(v, periodMode) === kpiWeek;
    };
    const matchPrev = (r: TrendRow) => {
      const v = r[dateKey] || '';
      if (periodMode === 'weeks') return v === kpiPrevWeek;
      return periodKey(v, periodMode) === kpiPrevWeek;
    };

    const families = filters.family
      ? [...new Set(srcAll.filter(r => famFromType(r.product_type) === filters.family).map(r => r.product_type))]
      : [...new Set(srcAll.map(r => r.product_type))].sort();

    const aggRows = (rows: TrendRow[]) => {
      const t = { sales: 0, ad_cost: 0, net_profit: 0, orders: 0, organic_pct: 0 };
      rows.forEach(r => {
        t.sales += r.sales || 0; t.ad_cost += r.ad_cost || 0; t.net_profit += r.net_profit || 0;
        t.orders += r.orders || 0;
      });
      t.organic_pct = t.orders > 0
        ? rows.reduce((s, r) => s + ((r.organic_pct || 0) * (r.orders || 0)), 0) / t.orders
        : 0;
      return t;
    };

    return families.map(fam => {
      const famRows = srcAll.filter(r => r.product_type === fam);
      const cur = aggRows(famRows.filter(matchCur));
      const prv = aggRows(famRows.filter(matchPrev));
      const familyName = famFromType(fam) as FamilyName | null;
      const curAds = adsSpendByFamilyAndPeriod[`${familyName}|${kpiWeek}`] ?? 0;
      const prvAds = adsSpendByFamilyAndPeriod[`${familyName}|${kpiPrevWeek}`] ?? 0;
      if (!familyName || (!cur.sales && !curAds)) return null;

      const curNp = cur.net_profit + (cur.ad_cost - curAds);
      const prvNp = (prv?.net_profit ?? 0) + ((prv?.ad_cost ?? 0) - prvAds);

      const sd = prv.sales ? ((cur.sales - prv.sales) / prv.sales) * 100 : 0;
      const cd = prvAds ? ((curAds - prvAds) / prvAds) * 100 : 0;
      const pd = prvNp ? ((curNp - prvNp) / Math.abs(prvNp)) * 100 : 0;
      const roas = curAds ? (curNp + curAds) / curAds : 0;
      const prevRoas = prvAds ? (prvNp + prvAds) / prvAds : 0;
      const roasDelta = prevRoas ? ((roas - prevRoas) / Math.abs(prevRoas)) * 100 : 0;
      const orgDelta = prv.organic_pct ? ((cur.organic_pct - prv.organic_pct) / Math.abs(prv.organic_pct)) * 100 : 0;

      return {
        family: familyName,
        sd, cd, pd, roasDelta, orgDelta,
        status: getChangesStatus({ sd, cd, pd, roasDelta, orgDelta }),
        prevSales: prv.sales,
        prevAdCost: prvAds,
        prevNetProfit: prvNp,
      };
    }).filter((x): x is NonNullable<typeof x> => x != null);
  }, [data.weekly_trends, data.monthly_trends, data.weekly_trends_by_asin, data.monthly_trends_by_asin, periodMode, kpiWeek, kpiPrevWeek, effectivePrevTotals, filters.family, filters.product, filters.seasonality, pk, adsSpendByFamilyAndPeriod]);

  const variationPnlByFamily = useMemo(() => {
    if (!kpiWeek) return famRecord(() => []) as Record<FamilyName, { asin: string; product_short_name: string; sales: number; cogs: number; ad_cost: number; storage_cost: number; net_profit: number; net_roas: number; orders: number; units: number; clicks: number; sessions: number; organic_pct: number; organic_units: number; ad_orders: number; ads_sales: number; ads_units: number }[]>;
    type Row = { product_type: string; asin: string; product_short_name: string; week_start?: string; month_start?: string; sales: number; ad_cost: number; cogs: number; net_profit: number; orders: number; units?: number; clicks?: number; sessions?: number; organic_pct?: number };
    const src = periodMode === 'weeks' ? (data.weekly_trends_by_asin || []) : (data.monthly_trends_by_asin || []);
    const dateKey = periodMode === 'weeks' ? 'week_start' : 'month_start';
    const matchCur = (r: Row) => {
      const v = r[dateKey] || '';
      if (periodMode === 'weeks') return v === kpiWeek;
      return periodKey(v, periodMode) === kpiWeek;
    };
    const result: Record<FamilyName, { asin: string; product_short_name: string; sales: number; cogs: number; ad_cost: number; storage_cost: number; net_profit: number; net_roas: number; orders: number; units: number; clicks: number; sessions: number; organic_pct: number; organic_units: number; ad_orders: number; ads_sales: number; ads_units: number }[]> = famRecord(() => []);
    const tempMap: Record<FamilyName, Map<string, { asin: string; product_short_name: string; sales: number; cogs: number; ad_cost: number; storage_cost: number; net_profit: number; orders: number; units: number; clicks: number; sessions: number; organic_pct_weighted: number }>> = famRecord(() => new Map());
    src.forEach((r: Row) => {
      const fam = famFromType(r.product_type) as FamilyName | null;
      if (!fam || !tempMap[fam] || (filters.family && fam !== filters.family) || (filters.product && r.asin !== filters.product) || !matchCur(r)) return;
      const periodKey_ = periodMode === 'weeks' ? r.week_start : (r.month_start || '').slice(0, 7);
      const asinKey = `${r.asin}|${periodKey_}`;
      const sCost = periodMode === 'weeks' ? (storageCostLookup.byAsinWeek[asinKey] || 0) : (storageCostLookup.byAsinMonth[asinKey] || 0);
      const existing = tempMap[fam].get(r.asin);
      if (existing) {
        existing.sales += r.sales || 0;
        existing.cogs += r.cogs || 0;
        existing.ad_cost += r.ad_cost || 0;
        existing.storage_cost += sCost;
        existing.net_profit += r.net_profit || 0;
        existing.orders += r.orders || 0;
        existing.units += r.units || 0;
        existing.clicks += r.clicks || 0;
        existing.sessions += r.sessions || 0;
        existing.organic_pct_weighted += (r.organic_pct ?? 0) * (r.orders || 0);
      } else {
        tempMap[fam].set(r.asin, {
          asin: r.asin,
          product_short_name: r.product_short_name || r.asin,
          sales: r.sales || 0,
          cogs: r.cogs || 0,
          ad_cost: r.ad_cost || 0,
          storage_cost: sCost,
          net_profit: r.net_profit || 0,
          orders: r.orders || 0,
          units: r.units || 0,
          clicks: r.clicks || 0,
          sessions: r.sessions || 0,
          organic_pct_weighted: (r.organic_pct ?? 0) * (r.orders || 0),
        });
      }
    });
    (Object.keys(tempMap) as FamilyName[]).forEach(fam => {
      tempMap[fam].forEach(v => {
        const adCost = v.ad_cost;
        const grossMargin = v.sales - v.cogs;
        const productName = v.product_short_name;
        const periodKey_ = kpiWeek || '';
        result[fam].push({
          asin: v.asin,
          product_short_name: v.product_short_name,
          sales: v.sales,
          cogs: v.cogs,
          ad_cost: adCost,
          storage_cost: v.storage_cost,
          net_profit: grossMargin - adCost - v.storage_cost,
          net_roas: adCost ? grossMargin / adCost : 0,
          orders: v.orders,
          units: v.units,
          clicks: v.clicks,
          sessions: v.sessions,
          organic_pct: v.orders > 0 ? v.organic_pct_weighted / v.orders : 0,
          organic_units: Math.round((v.units || 0) * (v.orders > 0 ? v.organic_pct_weighted / v.orders : 0) / 100),
          ad_orders: 0,
          ads_sales: adsDataByProductAndPeriod.sales[`${productName}|${periodKey_}`] || 0,
          ads_units: Math.round(adsDataByProductAndPeriod.units[`${productName}|${periodKey_}`] || 0),
        });
      });
    });
    // Inject products that hold stock anywhere but had no sales this period, so newly-stocked
    // (or temporarily zero-sales) items still appear under their family with their inventory.
    for (const sc of (data.supply_chain || [])) {
      const fam = (asinToFamily.get(sc.asin) || '') as FamilyName;
      if (!fam || !result[fam]) continue;
      if (filters.family && fam !== filters.family) continue;
      if (filters.product && sc.asin !== filters.product) continue;
      if (stockAnywhere(sc) <= 0) continue;
      if (result[fam].some(v => v.asin === sc.asin)) continue;
      result[fam].push({
        asin: sc.asin, product_short_name: sc.product_short_name || sc.asin,
        sales: 0, cogs: 0, ad_cost: 0, storage_cost: 0, net_profit: 0, net_roas: 0,
        orders: 0, units: 0, clicks: 0, sessions: 0, organic_pct: 0, organic_units: 0,
        ad_orders: 0, ads_sales: 0, ads_units: 0,
      });
    }
    (Object.keys(result) as FamilyName[]).forEach(fam => {
      result[fam].sort((a, b) => b.sales - a.sales);
    });
    return result;
  }, [data.weekly_trends_by_asin, data.monthly_trends_by_asin, data.products, data.supply_chain, asinToFamily, periodMode, kpiWeek, filters.family, filters.product, adsDataByProductAndPeriod, storageCostLookup]);

  const pnlByAsin = useMemo(() => {
    const map = new Map<string, { payment: number; storage_cost: number; sales: number; cogs: number; ad_cost: number; net_profit: number; net_roas: number; orders: number; units: number; clicks: number; sessions: number; organic_pct: number; organic_units: number; ad_orders: number; ads_sales: number; ads_units: number }>();
    (Object.values(variationPnlByFamily) as { asin: string; sales: number; cogs: number; ad_cost: number; storage_cost: number; net_profit: number; net_roas: number; orders: number; units: number; clicks: number; sessions: number; organic_pct: number; organic_units: number; ad_orders: number; ads_sales: number; ads_units: number }[][]).flat().forEach(v => {
      if (v.asin) map.set(v.asin, { payment: 0, storage_cost: v.storage_cost, sales: v.sales, cogs: v.cogs, ad_cost: v.ad_cost, net_profit: v.net_profit, net_roas: v.net_roas, orders: v.orders, units: v.units ?? 0, clicks: v.clicks, sessions: v.sessions ?? 0, organic_pct: v.organic_pct, organic_units: v.organic_units ?? 0, ad_orders: v.ad_orders ?? 0, ads_sales: v.ads_sales ?? 0, ads_units: v.ads_units ?? 0 });
    });
    return map;
  }, [variationPnlByFamily]);

  const productByAsin = useMemo(() => {
    const map = new Map<string, { pick_pack_fee: number; referral_fee: number; cogs: number; shipping_cost: number }>();
    (data.products || []).forEach(p => {
      if (p.asin) map.set(p.asin, { pick_pack_fee: p.pick_pack_fee ?? 0, referral_fee: p.referral_fee ?? 0, cogs: p.cogs ?? 0, shipping_cost: p.shipping_cost ?? 0 });
    });
    return map;
  }, [data.products]);

  const supplyChainByAsin = useMemo(() => {
    const map = new Map<string, SupplyChainRow>();
    (data.supply_chain || []).forEach(sc => { if (sc.asin) map.set(sc.asin, sc); });
    return map;
  }, [data.supply_chain]);

  const changesByVariation = useMemo(() => {
    if (!kpiWeek || !kpiPrevWeek) return famRecord(() => []) as Record<FamilyName, { asin: string; product_short_name: string; sd: number; cd: number; pd: number; roasDelta: number; orgDelta: number; status: string; prevSales: number; prevAdCost: number; prevNetProfit: number }[]>;
    type Row = { product_type: string; asin: string; product_short_name: string; week_start?: string; month_start?: string; sales: number; ad_cost: number; net_profit: number; orders: number; organic_pct?: number };
    const src = periodMode === 'weeks' ? (data.weekly_trends_by_asin || []) : (data.monthly_trends_by_asin || []);
    const dateKey = periodMode === 'weeks' ? 'week_start' : 'month_start';

    const matchCur = (r: Row) => {
      const v = r[dateKey] || '';
      if (periodMode === 'weeks') return v === kpiWeek;
      return periodKey(v, periodMode) === kpiWeek;
    };
    const matchPrev = (r: Row) => {
      const v = r[dateKey] || '';
      if (periodMode === 'weeks') return v === kpiPrevWeek;
      return periodKey(v, periodMode) === kpiPrevWeek;
    };

    const byAsin: Record<string, { cur: { sales: number; ad_cost: number; net_profit: number; orders: number; organic_pct_weighted: number; product_type: string; product_short_name: string }; prev: { sales: number; ad_cost: number; net_profit: number; orders: number; organic_pct_weighted: number } }> = {};
    const emptyAgg = () => ({ sales: 0, ad_cost: 0, net_profit: 0, orders: 0, organic_pct_weighted: 0 });
    src.forEach(r => {
      const fam = famFromType(r.product_type) as FamilyName | null;
      if (!fam || (filters.family && fam !== filters.family) || (filters.product && r.asin !== filters.product)) return;
      const key = `${r.product_type}|${r.asin}`;
      if (!byAsin[key]) byAsin[key] = { cur: { ...emptyAgg(), product_type: r.product_type, product_short_name: r.product_short_name }, prev: emptyAgg() as any };
      if (matchCur(r)) {
        const c = byAsin[key].cur;
        c.sales += r.sales || 0; c.ad_cost += r.ad_cost || 0; c.net_profit += r.net_profit || 0;
        c.orders += r.orders || 0; c.organic_pct_weighted += (r.organic_pct ?? 0) * (r.orders || 0);
      }
      if (matchPrev(r)) {
        const p = byAsin[key].prev;
        p.sales += r.sales || 0; p.ad_cost += r.ad_cost || 0; p.net_profit += r.net_profit || 0;
        p.orders += r.orders || 0; p.organic_pct_weighted += (r.organic_pct ?? 0) * (r.orders || 0);
      }
    });

    const result: Record<FamilyName, { asin: string; product_short_name: string; sd: number; cd: number; pd: number; roasDelta: number; orgDelta: number; status: string; prevSales: number; prevAdCost: number; prevNetProfit: number }[]> = famRecord(() => []);

    Object.entries(byAsin).forEach(([key, { cur, prev }]) => {
      if (!cur.orders && !prev.orders) return;
      const [, asin] = key.split('|');
      const fam = famFromType(cur.product_type) as FamilyName | null;
      if (!fam || !result[fam]) return;

      const sd = prev.sales ? ((cur.sales - prev.sales) / prev.sales) * 100 : 0;
      const cd = prev.ad_cost ? ((cur.ad_cost - prev.ad_cost) / prev.ad_cost) * 100 : 0;
      const pd = prev.net_profit ? ((cur.net_profit - prev.net_profit) / Math.abs(prev.net_profit)) * 100 : 0;
      const roas = cur.ad_cost ? (cur.net_profit + cur.ad_cost) / cur.ad_cost : 0;
      const prevRoas = prev.ad_cost ? (prev.net_profit + prev.ad_cost) / prev.ad_cost : 0;
      const roasDelta = prevRoas ? ((roas - prevRoas) / Math.abs(prevRoas)) * 100 : 0;
      const curOrgPct = cur.orders > 0 ? cur.organic_pct_weighted / cur.orders : 0;
      const prevOrgPct = prev.orders > 0 ? prev.organic_pct_weighted / prev.orders : 0;
      const orgDelta = prevOrgPct ? ((curOrgPct - prevOrgPct) / Math.abs(prevOrgPct)) * 100 : 0;

      result[fam].push({
        asin,
        product_short_name: cur.product_short_name || asin,
        sd, cd, pd, roasDelta, orgDelta,
        status: getChangesStatus({ sd, cd, pd, roasDelta, orgDelta }),
        prevSales: prev.sales,
        prevAdCost: prev.ad_cost,
        prevNetProfit: prev.net_profit,
      });
    });

    (Object.keys(result) as FamilyName[]).forEach(f => {
      result[f].sort((a, b) => Math.abs(b.sd) - Math.abs(a.sd));
    });
    return result;
  }, [data.weekly_trends_by_asin, data.monthly_trends_by_asin, periodMode, kpiWeek, kpiPrevWeek, filters.family, filters.product]);

  function buildPeakYoYTooltip(ty: { sl: number; cg: number; co: number; np: number; or: number; cl: number; orgP: number; ordSum: number }, ly: typeof ty): string {
    const yoy = (t: number, l: number) => (l ? ((t - l) / Math.abs(l)) * 100 : 0);
    const lines = [
      `Sales: ${fM(ty.sl)} vs ${fM(ly.sl)} (${yoy(ty.sl, ly.sl) >= 0 ? '+' : ''}${yoy(ty.sl, ly.sl).toFixed(1)}%)`,
      `COGS: ${fM(ty.cg)} vs ${fM(ly.cg)} (${yoy(ty.cg, ly.cg) >= 0 ? '+' : ''}${yoy(ty.cg, ly.cg).toFixed(1)}%)`,
      `Ads Spend: ${fM(ty.co)} vs ${fM(ly.co)} (${yoy(ty.co, ly.co) >= 0 ? '+' : ''}${yoy(ty.co, ly.co).toFixed(1)}%)`,
      `Net Profit: ${fM(ty.np)} vs ${fM(ly.np)} (${yoy(ty.np, ly.np) >= 0 ? '+' : ''}${yoy(ty.np, ly.np).toFixed(1)}%)`,
      `Orders: ${fOrd(ty.or)} vs ${fOrd(ly.or)} (${yoy(ty.or, ly.or) >= 0 ? '+' : ''}${yoy(ty.or, ly.or).toFixed(1)}%)`,
      `Clicks: ${fClk(ty.cl)} vs ${fClk(ly.cl)} (${yoy(ty.cl, ly.cl) >= 0 ? '+' : ''}${yoy(ty.cl, ly.cl).toFixed(1)}%)`,
    ];
    const tyOrg = ty.ordSum ? ty.orgP / ty.ordSum : 0;
    const lyOrg = ly.ordSum ? ly.orgP / ly.ordSum : 0;
    lines.push(`Organic %: ${fP(tyOrg)} vs ${fP(lyOrg)} (${yoy(tyOrg, lyOrg) >= 0 ? '+' : ''}${yoy(tyOrg, lyOrg).toFixed(1)}%)`);
    return lines.join('\n');
  }

  const peakYoYData = useMemo(() => {
    const wt: TrendRow[] = filters.product
      ? (data.weekly_trends_by_asin || []).filter((r: TrendRow & { asin?: string }) => r.asin === filters.product)
      : (data.weekly_trends || []);
    const mt: TrendRow[] = filters.product
      ? (data.monthly_trends_by_asin || []).filter((r: TrendRow & { asin?: string }) => r.asin === filters.product)
      : (data.monthly_trends || []);
    const agg = (r: TrendRow[]) => r.reduce((t, x) => {
      const adCost = (x.week_start && weekOverlapsAdsGap(x.week_start)) || (x.month_start && monthOverlapsAdsGap((x.month_start || '').slice(0, 7))) ? 0 : (x.ad_cost || 0);
      return {
        sl: t.sl + (x.sales || 0), cg: t.cg + (x.cogs || 0), co: t.co + adCost,
        np: t.np + (x.net_profit || 0), or: t.or + (x.orders || 0), cl: t.cl + (x.clicks || 0),
        orgP: t.orgP + ((x.organic_pct || 0) * (x.orders || 0)), ordSum: t.ordSum + (x.orders || 0),
      };
    }, { sl: 0, cg: 0, co: 0, np: 0, or: 0, cl: 0, orgP: 0, ordSum: 0 });

    if (pk?.peak_start && pk.days_until_peak_start != null && pk.days_until_peak_start >= 0 && periodMode === 'weeks') {
      const daysUntil = pk.days_until_peak_start;
        const startTy = addDays(pk.peak_start, -(daysUntil + 7));
        const endTy = addDays(startTy, 6);
        const holidays = data.holidays || [];
        const lyHoliday = holidays
          .filter(h => h.holiday_name === pk.holiday_name && h.holiday_date < pk.holiday_date)
          .sort((a, b) => b.holiday_date.localeCompare(a.holiday_date))[0];
        let startLy: string, endLy: string;
        if (lyHoliday?.pre_season_start) {
          startLy = addDays(lyHoliday.pre_season_start, -(daysUntil + 7) + (new Date(pk.peak_start + 'T00:00:00').getTime() - new Date(pk.pre_peak_start || pk.peak_start + 'T00:00:00').getTime()) / 86400000);
          const tyOffsetFromPeak = Math.round((new Date(startTy + 'T00:00:00').getTime() - new Date(pk.peak_start + 'T00:00:00').getTime()) / 86400000);
          startLy = addDays(lyHoliday.pre_season_start, tyOffsetFromPeak);
          endLy = addDays(startLy, 6);
        } else {
          startLy = shiftYear(startTy, -1);
          endLy = shiftYear(endTy, -1);
        }
        const allWeeks = [...new Set(wt.map(r => r.week_start || ''))].filter(Boolean);
        const tyWeeks = weeksInDateRange(startTy, endTy, allWeeks);
        const lyWeeks = weeksInDateRange(startLy, endLy, allWeeks);
        let tyRows = wt.filter(r => tyWeeks.includes(r.week_start || ''));
        let lyRows = wt.filter(r => lyWeeks.includes(r.week_start || ''));
        if (filters.family) {
          tyRows = tyRows.filter(r => famFromType(r.product_type) === filters.family);
          lyRows = lyRows.filter(r => famFromType(r.product_type) === filters.family);
        }
        const ty = agg(tyRows);
        const ly = agg(lyRows);
        const salesYoy = ly.sl ? ((ty.sl - ly.sl) / ly.sl) * 100 : 0;
        const profitYoy = ly.np ? ((ty.np - ly.np) / Math.abs(ly.np)) * 100 : 0;
        const lyLabel = lyHoliday ? `${pk.holiday_name} ${lyHoliday.holiday_date.slice(0, 4)}` : 'last year';
        const dateRange = `${formatDateRange(startTy, endTy)} vs ${formatDateRange(startLy, endLy)} (${lyLabel})`;
        const tooltipLines = buildPeakYoYTooltip(ty, ly);
        return { salesTy: ty.sl, salesLy: ly.sl, npTy: ty.np, npLy: ly.np, salesYoy, profitYoy, dateRange, label: `D-${daysUntil + 7} to D-${daysUntil} vs peak`, isPeak: true, tooltipLines };
    }
    if (!kpiWeek) return null;
    if (periodMode === 'weeks') {
      const lyWeek = shiftYear(kpiWeek, -1);
      let tyRows = wt.filter(r => r.week_start === kpiWeek);
      let lyRows = wt.filter(r => r.week_start === lyWeek);
      if (filters.family) {
        tyRows = tyRows.filter(r => famFromType(r.product_type) === filters.family);
        lyRows = lyRows.filter(r => famFromType(r.product_type) === filters.family);
      }
      const ty = agg(tyRows);
      const ly = agg(lyRows);
      const salesYoy = ly.sl ? ((ty.sl - ly.sl) / ly.sl) * 100 : 0;
      const profitYoy = ly.np ? ((ty.np - ly.np) / Math.abs(ly.np)) * 100 : 0;
      const dateRange = `${formatDateRange(kpiWeek, addDays(kpiWeek, 6))} vs ${formatDateRange(lyWeek, addDays(lyWeek, 6))} last year`;
      const tooltipLines = buildPeakYoYTooltip(ty, ly);
      return { salesTy: ty.sl, salesLy: ly.sl, npTy: ty.np, npLy: ly.np, salesYoy, profitYoy, dateRange, label: 'vs same week last year', isPeak: false, tooltipLines };
    }
    if (periodMode === 'month') {
      const lyKey = shiftYear(kpiWeek + '-01', -1).slice(0, 7);
      let tyRows = mt.filter(r => (r.month_start || '').slice(0, 7) === kpiWeek);
      let lyRows = mt.filter(r => (r.month_start || '').slice(0, 7) === lyKey);
      if (filters.family) {
        tyRows = tyRows.filter(r => famFromType(r.product_type) === filters.family);
        lyRows = lyRows.filter(r => famFromType(r.product_type) === filters.family);
      }
      const ty = agg(tyRows);
      const ly = agg(lyRows);
      const salesYoy = ly.sl ? ((ty.sl - ly.sl) / ly.sl) * 100 : 0;
      const profitYoy = ly.np ? ((ty.np - ly.np) / Math.abs(ly.np)) * 100 : 0;
      const tyLabel = new Date(kpiWeek + '-01').toLocaleDateString('en-US', { month: 'short', year: 'numeric' });
      const lyLabel = new Date(lyKey + '-01').toLocaleDateString('en-US', { month: 'short', year: 'numeric' });
      const dateRange = `${tyLabel} vs ${lyLabel}`;
      const tooltipLines = buildPeakYoYTooltip(ty, ly);
      return { salesTy: ty.sl, salesLy: ly.sl, npTy: ty.np, npLy: ly.np, salesYoy, profitYoy, dateRange, label: 'vs same month last year', isPeak: false, tooltipLines };
    }
    if (periodMode === 'quarter') {
      const lyKey = `${parseInt(kpiWeek.slice(0, 4), 10) - 1}${kpiWeek.slice(4)}`;
      const matchQ = (r: TrendRow, qk: string) => {
        const ms = r.month_start || '';
        return periodKey(ms, 'quarter') === qk;
      };
      let tyRows = mt.filter(r => matchQ(r, kpiWeek));
      let lyRows = mt.filter(r => matchQ(r, lyKey));
      if (filters.family) {
        tyRows = tyRows.filter(r => famFromType(r.product_type) === filters.family);
        lyRows = lyRows.filter(r => famFromType(r.product_type) === filters.family);
      }
      const ty = agg(tyRows);
      const ly = agg(lyRows);
      const salesYoy = ly.sl ? ((ty.sl - ly.sl) / ly.sl) * 100 : 0;
      const profitYoy = ly.np ? ((ty.np - ly.np) / Math.abs(ly.np)) * 100 : 0;
      const dateRange = `${kpiWeek} vs ${lyKey}`;
      const tooltipLines = buildPeakYoYTooltip(ty, ly);
      return { salesTy: ty.sl, salesLy: ly.sl, npTy: ty.np, npLy: ly.np, salesYoy, profitYoy, dateRange, label: 'vs same quarter last year', isPeak: false, tooltipLines };
    }
    const lyYear = (parseInt(kpiWeek, 10) - 1).toString();
    let tyRows = mt.filter(r => (r.month_start || '').slice(0, 4) === kpiWeek);
    let lyRows = mt.filter(r => (r.month_start || '').slice(0, 4) === lyYear);
    if (filters.family) {
      tyRows = tyRows.filter(r => famFromType(r.product_type) === filters.family);
      lyRows = lyRows.filter(r => famFromType(r.product_type) === filters.family);
    }
    const ty = agg(tyRows);
    const ly = agg(lyRows);
    const salesYoy = ly.sl ? ((ty.sl - ly.sl) / ly.sl) * 100 : 0;
    const profitYoy = ly.np ? ((ty.np - ly.np) / Math.abs(ly.np)) * 100 : 0;
    const dateRange = `${kpiWeek} vs ${lyYear}`;
    const tooltipLines = buildPeakYoYTooltip(ty, ly);
    return { salesTy: ty.sl, salesLy: ly.sl, npTy: ty.np, npLy: ly.np, salesYoy, profitYoy, dateRange, label: 'vs same year last year', isPeak: false, tooltipLines };
  }, [data.weekly_trends, data.monthly_trends, data.weekly_trends_by_asin, data.monthly_trends_by_asin, data.holidays, pk, kpiWeek, periodMode, filters.family, filters.product]);

  const periodLabel = useMemo(() =>
    trendData.length ? trendData[0].label + ' – ' + trendData[trendData.length - 1].label : '',
  [trendData]);

  const famSort = useSort('sales');
  const rangeStr = periodMode === 'weeks' && kpiWeek ? weekRangeLabel(kpiWeek) : kpiPeriodLabel || '';

  const periodIncomplete = useMemo(() => {
    if (!kpiWeek || !perfMaxDate) return false;
    if (periodMode === 'weeks') {
      const periodEnd = addDays(kpiWeek, 6);
      return perfMaxDate < periodEnd;
    }
    if (periodMode === 'month') {
      const [y, m] = kpiWeek.split('-').map(Number);
      const lastDay = new Date(y, m, 0).getDate();
      const periodEnd = `${kpiWeek}-${String(lastDay).padStart(2, '0')}`;
      return perfMaxDate < periodEnd;
    }
    return false;
  }, [kpiWeek, perfMaxDate, periodMode]);

  const headline = useMemo(() => {
    if (!effectiveTotals.sl && !effectiveTotals.co) return '';
    const parts: string[] = [];
    const salesDir = sd > 2 ? 'up' : sd < -2 ? 'down' : 'flat';
    const profitDir = pd > 5 ? 'surging' : pd > 0 ? 'up' : pd < -5 ? 'dropped' : pd < 0 ? 'dipped' : 'flat';
    parts.push(`Sales ${salesDir} ${Math.abs(sd).toFixed(0)}%`);
    parts.push(`profit ${profitDir} ${Math.abs(pd).toFixed(0)}%`);
    if (roas >= 2) parts.push(`ROAS healthy at ${fR(roas)}`);
    else if (roas < 1 && roas > 0) parts.push(`ROAS below breakeven (${fR(roas)})`);
    const urgentCount = (grouped.urgent || []).length;
    if (urgentCount > 0) parts.push(`${urgentCount} urgent action${urgentCount > 1 ? 's' : ''}`);
    if (pk?.current_stage === 'PEAK') parts.push('peak is live');
    else if (pk?.current_stage === 'PRE_PEAK_BOOST') parts.push('boost phase active');
    else if (pk?.days_until_peak_start != null && pk.days_until_peak_start <= 14 && pk.days_until_peak_start > 0) parts.push(`${pk.days_until_peak_start}d to peak`);
    return parts.join(' · ');
  }, [sd, pd, roas, grouped.urgent, pk, effectiveTotals.sl, effectiveTotals.co]);

  const trendAnnotations = useMemo(() => {
    const annotations: { label: string; x: string; color: string }[] = [];
    const labels = trendData.map(d => d.label);
    if (!labels.length) return annotations;
    (data.change_log || []).forEach(cl => {
      const d = cl.change_date || cl.created_at || '';
      if (!d) return;
      const weekKey = labels.find(l => l === d.slice(0, 10) || (d >= l && d <= l.slice(0, 8) + String(parseInt(l.slice(8), 10) + 6).padStart(2, '0')));
      if (weekKey) {
        const short = cl.change_type === 'BID_CHANGE' ? 'Bid' : cl.change_type === 'BUDGET_CHANGE' ? 'Budget' : cl.change_type?.slice(0, 6) || '?';
        annotations.push({ label: short, x: weekKey, color: '#facc15' });
      }
    });
    (data.upcoming || []).forEach(ev => {
      const hd = ev.holiday_date || '';
      const matchLabel = labels.find(l => hd >= l && hd <= (l.slice(0, 8) + String(parseInt(l.slice(8), 10) + 6).padStart(2, '0')));
      if (matchLabel) annotations.push({ label: ev.holiday_name?.slice(0, 8) || 'Holiday', x: matchLabel, color: '#f472b6' });
    });
    return annotations;
  }, [trendData, data.change_log, data.upcoming]);

  // ── Per-day display data (Total | /day toggle) ──
  // Post-process the source aggregates: divide additive "flow" fields by each period's
  // day-count. Ratios (net_roas, organic_pct) and last-year values are handled per surface.
  const trendDataDisplay = useMemo(() => {
    if (!perDay) return trendData;
    const ADD = ['sales', 'ad_cost', 'cogs', 'net_profit', 'payment', 'storage_cost', 'orders', 'units', 'clicks', 'sessions'];
    return trendData.map(d => {
      const key = (d as { weekKey?: string }).weekKey || '';
      const dc = Math.max(1, periodDayCount(key, periodMode, perfMaxDate));
      const dFull = Math.max(1, periodDayCount(key, periodMode)); // LY is always complete → full length
      const o: Record<string, unknown> = { ...d };
      for (const m of ADD) {
        if (typeof o[m] === 'number') o[m] = (o[m] as number) / dc;
        const ly = `ly_${m}`;
        if (typeof o[ly] === 'number') o[ly] = (o[ly] as number) / dFull;
      }
      return o as typeof trendData[number];
    });
  }, [trendData, perDay, periodMode, perfMaxDate]);

  const kpiSparklineDisplay = useMemo(() => {
    if (!perDay) return kpiSparklineData;
    const keys = trendData.map(d => (d as { weekKey?: string }).weekKey || d.label);
    const divs = keys.map(k => Math.max(1, periodDayCount(k, periodMode, perfMaxDate)));
    const scale = (arr?: number[]) => (arr || []).map((v, i) => (divs[i] ? v / divs[i] : v));
    return { ...kpiSparklineData, sales: scale(kpiSparklineData.sales), ad_cost: scale(kpiSparklineData.ad_cost), profit: scale(kpiSparklineData.profit) };
  }, [kpiSparklineData, perDay, trendData, periodMode, perfMaxDate]);

  const familyPeriodDataDisplay = useMemo(() => {
    const base = familyPeriodData;
    if (!perDay || !base) return base;
    const d = Math.max(1, periodDayCount(kpiWeek, periodMode, perfMaxDate));
    if (d <= 1) return base;
    const FLOW = ['sales', 'cogs', 'ad_cost', 'ads_sales', 'ads_units', 'net_profit', 'orders', 'units', 'clicks', 'sessions', 'organic_units', 'ad_orders', 'payment', 'storage_cost'];
    return base.map(row => {
      const o = { ...row } as Record<string, unknown>;
      for (const k of FLOW) if (typeof o[k] === 'number') o[k] = (o[k] as number) / d;
      return o;
    }) as typeof familyPeriodData;
  }, [familyPeriodData, perDay, kpiWeek, periodMode, perfMaxDate]);

  const totalFamilySales = useMemo(() => {
    return (familyPeriodDataDisplay || []).reduce((s, r) => s + (r.sales || 0), 0);
  }, [familyPeriodDataDisplay]);
  const totalFamilyAdCost = useMemo(() => {
    return (familyPeriodDataDisplay || []).reduce((s, r) => s + (r.ad_cost || 0), 0);
  }, [familyPeriodDataDisplay]);
  const totalFamilyNetProfit = useMemo(() => {
    return (familyPeriodDataDisplay || []).reduce((s, r) => s + (r.net_profit || 0), 0);
  }, [familyPeriodDataDisplay]);

  const eT = effectiveTotals;
  const netRoas = eT.co > 0 ? (eT.sl - eT.cg - eT.co) / eT.co : 0;
  usePageSummary({ title: 'Home', items: [] });

  if (!effectiveTotals.sl && !effectiveTotals.co && !effectiveTotals.or) return <Empty icon="📊" message="No summary data" hint="Summary data will appear once your Amazon performance data is synced." />;

  const prevLabel = periodMode === 'weeks' && kpiPrevWeek ? weekRangeLabel(kpiPrevWeek) : kpiPrevWeek || '';
  const isPeakStage = pk?.current_stage === 'PEAK';
  const score1 = periodIncomplete ? 0 : scoreFromRoas(roas);
  const score2 = periodIncomplete ? null : (isPeakStage ? null : (effectivePrevTotals ? scoreFromProfitDelta(pd) : null));
  const score3 = peakYoYData && !periodIncomplete ? scoreFromProfitDelta(peakYoYData.profitYoy) : 0;
  const currentSeasonality = pk && kpiWeek ? getSeasonality(kpiWeek, pk) : null;
  const seasonalityLabel = currentSeasonality ? { PRE_PEAK: 'Pre Peak (2-4 wk)', PRE_PEAK_BOOST: 'Pre Peak Boost (1-2 wk)', PEAK: 'Peak', OFF_SEASON: 'Off Season' }[currentSeasonality] : null;

  const trendLabels = trendData.map(d => d.label);

  // Divisor for the family table's current period (variation sub-rows + direct-source cells).
  const famDiv = perDay ? Math.max(1, periodDayCount(kpiWeek, periodMode, perfMaxDate)) : 1;
  const pdSuffix = perDay ? '/d' : '';

  return (
    <div className="animate-in">
      {periodIncomplete && (
        <div className="mb-3 px-3 py-2 rounded-lg border border-amber-500/30 bg-amber-500/5 text-[11px] text-amber-400 font-mono">
          Perf data through {perfMaxDate} — current period not complete, scores/comparisons suppressed
        </div>
      )}
      <div className="flex items-center justify-between gap-2 mb-1 px-1">
        <div className="font-mono text-[14px] font-semibold text-muted truncate">{headline || ''}</div>
        {/* Total | /day — divides additive measures by the days in each period (elapsed days
            for the in-progress period), making partial/uneven periods comparable. Ratios unchanged. */}
        <div className="flex items-center rounded-lg border overflow-hidden shrink-0" style={{ borderColor: 'var(--color-border)' }}
          title="Per-day divides additive measures (sales, ads spend, net profit, orders…) by the days in the period — using elapsed days for the in-progress period — so periods of different lengths are comparable. Ratios (Net ROAS, Organic %) are unchanged.">
          {(['total', 'perday'] as const).map(mode => {
            const active = (mode === 'perday') === perDay;
            return (
              <button key={mode} onClick={() => setPerDayPersist(mode === 'perday')}
                className="px-2.5 py-1 text-[11px] font-semibold transition-all cursor-pointer"
                style={{ background: active ? 'var(--color-accent, #3b82f6)' : 'transparent', color: active ? '#fff' : 'var(--color-faint)' }}>
                {mode === 'total' ? 'Total' : '/day'}
              </button>
            );
          })}
        </div>
      </div>

      <div className="flex items-center justify-end gap-1 mb-1 flex-wrap">
        {ALL_MEASURES.map(m => {
          const meta = MEASURE_META[m];
          const active = selectedMeasures.has(m);
          return (
            <button key={m} onClick={() => toggleMeasure(m)} title={MEASURE_TIPS[m] || ''}
              className="px-2.5 py-1 rounded-lg text-[11px] font-semibold border transition-all"
              style={{
                borderColor: active ? meta.color : 'rgba(63,63,70,.45)',
                background: active ? meta.color + '20' : 'transparent',
                color: active ? meta.color : '#71717a',
              }}
            >{meta.label}</button>
          );
        })}
      </div>

      <div className="mb-1 h-[253px] min-h-[200px]">
        <DashboardSummary
        rangeStr={rangeStr || '--'}
        pk={pk}
        seasonalityLabel={seasonalityLabel}
        latestPeriodLabel={latestPeriodLabel(kpiWeek, periodMode)}
        trendLabels={trendLabels}
        metrics={[
          { label: 'SALES', value: fM(eT2.sl) + pdSuffix, prevValue: fM(eP2?.sl || 0), lyValue: peakYoYData ? fM(peakYoYData.salesLy * lyScale) : undefined, delta: `${sd >= 0 ? '+' : ''}${sd.toFixed(1)}%`, positive: sd >= 0, warn: cd > sd ? 'Cost outpacing sales' : undefined, sub: sd > cd ? 'outgrowing cost' : '' },
          { label: 'ADS SPEND', value: fM(eT2.co) + pdSuffix, prevValue: fM(eP2?.co || 0), delta: `${cd >= 0 ? '+' : ''}${cd.toFixed(1)}%`, positive: cd <= 0, sub: `${fClk(Math.round(eT2.cl))} clicks · ${Math.round(eT2.ss).toLocaleString()} sess` },
          { label: 'NET PROFIT', value: fM(eT2.np) + pdSuffix, prevValue: fM(eP2?.np || 0), lyValue: peakYoYData ? fM(peakYoYData.npLy * lyScale) : undefined, delta: `${pd >= 0 ? '+' : ''}${pd.toFixed(1)}%`, positive: pd >= 0, sub: `COGS ${fM(eT2.cg)}${pdSuffix} · margin ${fP(margin)}` },
          { label: 'NET ROAS', value: fR(roas), prevValue: fR(prevRoas), lyValue: peakYoYData && peakYoYData.npLy && peakYoYData.salesLy ? fR(peakYoYData.salesLy > 0 ? peakYoYData.npLy / peakYoYData.salesLy : 0) : undefined, delta: `${roasDelta >= 0 ? '+' : ''}${roasDelta.toFixed(1)}%`, positive: roasDelta >= 0, warn: roas < 1 && roas > 0 ? 'Below break-even' : undefined, sub: roas >= 1 ? 'above break-even' : '' },
          { label: 'ORGANIC %', value: fP(orgP), prevValue: fP(prevOrgP), delta: `${orgDelta >= 0 ? '+' : ''}${orgDelta.toFixed(1)}%`, positive: orgDelta >= 0, sub: `${fOrd(Math.round(eT2.or))} total · ${fOrd(orgOrd)} organic` },
        ]}
        kpiSparklineData={kpiSparklineDisplay}
        headline={headline}
        onMetricSelect={(key) => {
          const map: Record<string, TrendMeasure> = { sales: 'sales', ad_cost: 'ad_cost', profit: 'net_profit', roas: 'net_roas', organic: 'organic_pct' };
          const tm = map[key];
          if (tm) setSelectedMeasures(new Set([tm]));
        }}
        trendContent={
          trendData.length > 0 ? (
            <div className="w-full h-full flex flex-col">
              <div className="flex-1 min-h-0">
                <ResponsiveContainer width="100%" height="100%">
                  <ComposedChart data={trendDataDisplay} barCategoryGap="20%" margin={{ top: 18, right: 0, bottom: 0, left: 0 }}>
                    <CartesianGrid {...CHART_GRID} />
                    <XAxis dataKey="label" tick={CHART_AXIS_TICK_LG} tickLine={false} axisLine={false} />
                    <YAxis yAxisId="left" hide />
                      <Tooltip
                        contentStyle={CHART_TOOLTIP_STYLE(11)}
                        formatter={(v: any, name: any) => {
                          const isLy = name?.startsWith('ly_');
                          const baseName = isLy ? name!.slice(3) : name;
                          const m = MEASURE_META[baseName as TrendMeasure];
                          const prefix = isLy ? 'LY ' : '';
                          return [m ? m.fmt(v ?? 0) : String(v ?? 0), prefix + ((m?.label || baseName) ?? '')];
                        }}
                      />
                    {trendAnnotations.map((ann, ai) => (
                      <ReferenceLine key={`ann-${ai}`} yAxisId="left" x={ann.x} stroke={ann.color} strokeDasharray="3 3" strokeWidth={1.5}
                        ifOverflow="hidden"
                        label={{ value: ann.label, position: 'top', fill: ann.color, fontSize: 8, fontFamily: 'ui-monospace, monospace' }} />
                    ))}
                    <SeasonalReferenceLines holidays={data.holidays || []} xLabels={getXLabels(trendData)} yAxisId="left" />
                    {activeMeasures.map(mKey => {
                      const meta = MEASURE_META[mKey];
                      return (
                        <Bar key={mKey} yAxisId="left" dataKey={mKey} radius={[4, 4, 0, 0]} fill={meta.color}
                          onClick={(data: any) => {
                            if (data?.weekKey) setFilter('specificPeriod', data.weekKey);
                            else if (data?.label) {
                              const match = trendData.find(d => d.label === data.label);
                              if (match && (match as any).weekKey) setFilter('specificPeriod', (match as any).weekKey);
                            }
                          }}
                          cursor="pointer">
                          <LabelList dataKey={mKey} position="top" offset={4} formatter={(v: unknown) => (meta.fmtShort ?? meta.fmt)(typeof v === 'number' ? v : 0)}
                            style={{ fill: '#d4d4d8', fontSize: 10, fontWeight: 600, fontFamily: 'var(--font-mono)' }} />
                          {periodMode === 'weeks' && trendData.map((entry, idx) => (
                            <Cell key={idx} fill={meta.color}
                              fillOpacity={entry.hasSqp ? 1 : 0.35}
                              stroke={!entry.hasSqp ? meta.color : undefined}
                              strokeWidth={!entry.hasSqp ? 1.5 : 0}
                              strokeDasharray={!entry.hasSqp ? '4 2' : undefined} />
                          ))}
                        </Bar>
                      );
                    })}
                    {(filters.periodType !== 'regular' || selectedMeasures.size === 1) && activeMeasures.map(mKey => {
                      const meta = MEASURE_META[mKey];
                      const lyKey = `ly_${mKey}`;
                      const hasLyData = trendData.some((d: any) => d[lyKey] != null && d[lyKey] !== 0);
                      if (!hasLyData) return null;
                      const isCumulative = filters.periodType === 'cumulative' || filters.periodType === 'peak';
                      return (
                        <Line key={`ly_${mKey}`} yAxisId="left" type="monotone" dataKey={lyKey}
                          stroke={meta.color} strokeWidth={isCumulative ? 2 : 1.5}
                          strokeDasharray={isCumulative ? undefined : '6 3'}
                          strokeOpacity={isCumulative ? 0.5 : 0.4}
                          dot={isCumulative ? { r: 2.5, fill: meta.color, fillOpacity: 0.5, strokeWidth: 0 } : false}
                          activeDot={{ r: 3, strokeWidth: 1, fill: meta.color, fillOpacity: 0.6 }}
                          name={`ly_${mKey}`} connectNulls />
                      );
                    })}
                  </ComposedChart>
                </ResponsiveContainer>
              </div>
            </div>
          ) : <Empty message={`No data for ${periodMode} view`} />
        }
        />
      </div>

      <Section
        title="Per Product Family"
        count={periodLabel ? latestPeriodLabel(kpiWeek, periodMode) : undefined}
        headerRight={
          <MeasureSelector tableId="home_family" measures={FAMILY_TABLE_COLUMNS} selected={familyCols} onSelectedChange={setFamilyCols} />
        }
      >
        {familyPeriodDataDisplay ? (
          <div className="border border-border rounded-xl bg-card overflow-x-auto">
            <table className="w-full border-collapse text-xs min-w-[900px]">
              <thead>
                <tr>
                  {visibleFamilyCols.map(c => (
                    <SortTh key={c.id} k={c.id} sort={famSort.sort} toggle={famSort.toggle} right={c.id !== 'family'} tip={c.tip}>{c.label}</SortTh>
                  ))}
                </tr>
              </thead>
              <tbody>
                {(() => {
                  const sortedData = famSort.sorted(familyPeriodDataDisplay);
                  const totalAdCost = sortedData.reduce((s, r) => s + (r.ad_cost || 0), 0);
                  const totalNetProfit = sortedData.reduce((s, r) => s + (r.net_profit || 0), 0);
                  return sortedData.map((r, i) => {
                    const f = famFromType(r.family) as FamilyName | null;
                    const isExpanded = f && expandedFamily === f;
                  const varsPnl = f ? (variationPnlByFamily[f] || []) : [];
                  const varsSqp = f ? (variationByFamily[f] || []) : [];
                  const varsRaw = varsPnl.length > 0
                    ? varsPnl
                    : varsSqp.map(v => {
                        const pnl = v.asin ? pnlByAsin.get(v.asin) : undefined;
                        const orders = pnl?.orders ?? v.orders ?? 0;
                        const organic_pct = pnl?.organic_pct ?? 0;
                        const organic_units = pnl ? pnl.organic_units : Math.round(orders * organic_pct / 100);
                        const ad_orders = pnl ? pnl.ad_orders : (v.adsOrders ?? orders - organic_units);
                        return {
                          asin: v.asin,
                          product_short_name: v.name,
                          sales: pnl?.sales ?? 0,
                          cogs: pnl?.cogs ?? 0,
                          ad_cost: pnl?.ad_cost ?? 0,
                          net_profit: pnl?.net_profit ?? 0,
                          net_roas: pnl?.net_roas ?? 0,
                          orders,
                          units: pnl?.units ?? 0,
                          clicks: pnl?.clicks ?? v.clicks ?? 0,
                          sessions: pnl?.sessions ?? 0,
                          organic_pct,
                          organic_units,
                          ad_orders,
                          ads_sales: pnl?.ads_sales ?? 0,
                          ads_units: pnl?.ads_units ?? 0,
                        };
                      });
                  // Per-day: scale variation flow fields by the current period's day-count (ratios untouched).
                  const vars = famDiv > 1
                    ? varsRaw.map(v => ({ ...v, sales: v.sales / famDiv, cogs: v.cogs / famDiv, ad_cost: v.ad_cost / famDiv, net_profit: v.net_profit / famDiv, orders: v.orders / famDiv, units: v.units / famDiv, clicks: v.clicks / famDiv, sessions: v.sessions / famDiv, organic_units: v.organic_units / famDiv, ad_orders: v.ad_orders / famDiv, ads_sales: (v.ads_sales ?? 0) / famDiv, ads_units: (v.ads_units ?? 0) / famDiv }))
                    : varsRaw;
                  const famChanges = f ? changesByFamily.find(c => c.family === f) : null;
                  const varChanges = f ? (changesByVariation[f] || []) : [];
                  const positiveCount = varChanges.filter(v => v.pd > 0).length;
                  const totalCount = varChanges.length;
                  const renderCell = (key: string, isVar: boolean, v?: { sales: number; cogs: number; ad_cost: number; net_profit: number; net_roas: number; orders: number; units: number; clicks: number; sessions: number; organic_pct: number; organic_units: number; ad_orders: number; ads_sales: number; ads_units: number; product_short_name?: string; asin?: string }) => {
                    if (key === 'family' && !isVar) return (
                      <td key={key} className="px-3 py-2 font-semibold">
                        <span className="inline-flex items-center gap-1">
                          {(varsPnl.length > 0 || varsSqp.length > 0) ? (isExpanded ? <ChevronDown size={14} className="text-faint" /> : <ChevronRight size={14} className="text-faint" />) : null}
                          <span style={{ color: f ? FAMILIES[f]?.color ?? '#fff' : undefined }}>{r.family || '--'}</span>
                        </span>
                      </td>
                    );
                    if (isVar && v) {
                      const hasPnl = varsPnl.length > 0 || (v.asin ? pnlByAsin.has(v.asin) : false);
                      const vc = varChanges.find(x => x.asin === v.asin || x.product_short_name === v.product_short_name);
                      const vSharePct = totalFamilySales > 0 ? (v.sales / totalFamilySales) * 100 : 0;
                      const cells: Record<string, React.ReactNode> = {
                        sales: <td key="sales" className="px-3 py-2 text-right font-mono text-[11px]">{hasPnl ? fM(v.sales) : '—'}</td>,
                        share_pct: <td key="share_pct" className="px-3 py-2 text-right font-mono text-[11px] text-faint">{hasPnl ? fP(vSharePct) : '—'}</td>,
                        cogs: <td key="cogs" className="px-3 py-2 text-right font-mono text-[11px]">{hasPnl ? fM(v.cogs) : '—'}</td>,
                        ad_cost: <td key="ad_cost" className="px-3 py-2 text-right font-mono text-[11px]">{hasPnl ? fM(v.ad_cost) : '—'}</td>,
                        pct_ads_spend: <td key="pct_ads_spend" className="px-3 py-2 text-right font-mono text-[11px] text-faint">{hasPnl && totalFamilyAdCost > 0 ? fP((v.ad_cost / totalFamilyAdCost) * 100) : '—'}</td>,
                        pct_net_profit: <td key="pct_net_profit" className={`px-3 py-2 text-right font-mono text-[11px] ${hasPnl && totalFamilyNetProfit !== 0 ? ((v.net_profit / totalFamilyNetProfit) * 100 < 0 ? 'text-red-400' : 'text-emerald-400') : 'text-faint'}`}>{hasPnl && totalFamilyNetProfit !== 0 ? fP((v.net_profit / totalFamilyNetProfit) * 100) : '—'}</td>,
                        ads_sales: <td key="ads_sales" className="px-3 py-2 text-right font-mono text-[11px]">{hasPnl ? fM(v.ads_sales ?? 0) : '—'}</td>,
                        ads_units: <td key="ads_units" className="px-3 py-2 text-right font-mono text-[11px]">{hasPnl ? fmt(v.ads_units ?? 0) : '—'}</td>,
                        net_profit: <td key="net_profit" className={`px-3 py-2 text-right font-mono text-[11px] ${hasPnl ? (v.net_profit > 0 ? 'text-emerald-400 font-bold' : 'text-red-400 font-bold') : 'text-faint'}`}>{hasPnl ? fM(v.net_profit) : '—'}</td>,
                        np_per_unit: <td key="np_per_unit" className={`px-3 py-2 text-right font-mono text-[11px] ${hasPnl && (v.units ?? 0) > 0 ? (v.net_profit / v.units > 0 ? 'text-emerald-400' : 'text-red-400') : 'text-faint'}`}>{hasPnl && (v.units ?? 0) > 0 ? fM(v.net_profit / v.units) : '—'}</td>,
                        net_roas: <td key="net_roas" className="px-3 py-2 text-right">{hasPnl ? <RoasBadge value={v.net_roas} /> : <span className="text-faint">—</span>}</td>,
                        tacos: <td key="tacos" className={`px-3 py-2 text-right font-mono text-[11px] ${hasPnl && v.sales > 0 ? ((v.ad_cost / v.sales) * 100 > 30 ? 'text-red-400' : (v.ad_cost / v.sales) * 100 > 15 ? 'text-amber-400' : 'text-emerald-400') : 'text-faint'}`}>{hasPnl && v.sales > 0 ? fP((v.ad_cost / v.sales) * 100) : '—'}</td>,
                        ads_roas: (() => { const ar = v.ad_cost > 0 ? (v.ads_sales ?? 0) / v.ad_cost : 0; return <td key="ads_roas" className="px-3 py-2 text-right">{hasPnl && ar > 0 ? <RoasBadge value={ar} /> : <span className="text-faint">—</span>}</td>; })(),
                        payment: <td key="payment" className={`px-3 py-2 text-right font-mono text-[11px] ${hasPnl ? 'text-sky-400 font-bold' : 'text-faint'}`}>{hasPnl ? fM((pnlByAsin.get(v.asin!)?.payment ?? 0) / famDiv) : '—'}</td>,
                        storage_cost: <td key="storage_cost" className="px-3 py-2 text-right font-mono text-[11px] text-amber-400">{hasPnl && (pnlByAsin.get(v.asin!)?.storage_cost ?? 0) / famDiv > 0 ? fM((pnlByAsin.get(v.asin!)?.storage_cost ?? 0) / famDiv) : '—'}</td>,
                        ad_orders: <td key="ad_orders" className="px-3 py-2 text-right font-mono text-[11px]">{hasPnl ? fmt(v.ad_orders) : '—'}</td>,
                        units: <td key="units" className="px-3 py-2 text-right font-mono text-[11px]">{hasPnl ? fmt(v.units) : '—'}</td>,
                        orders: <td key="orders" className="px-3 py-2 text-right font-mono text-[11px]">{fmt(v.orders)}</td>,
                        organic_units: <td key="organic_units" className="px-3 py-2 text-right font-mono text-[11px]">{hasPnl ? fmt(v.organic_units) : '—'}</td>,
                        clicks: <td key="clicks" className="px-3 py-2 text-right font-mono text-[11px]">{fClk(v.clicks)}</td>,
                        sessions: <td key="sessions" className="px-3 py-2 text-right font-mono text-[11px]">{v.sessions > 0 ? v.sessions.toLocaleString() : '—'}</td>,
                        organic_pct: <td key="organic_pct" className="px-3 py-2 text-right font-mono text-[11px]">{hasPnl ? fP(v.organic_pct) : '—'}</td>,
                        sales_change: <td key="sales_change" className="px-3 py-2">{vc ? <ChangesSummaryCell data={vc} /> : <span className="text-faint">—</span>}</td>,
                        fba_pick_pack: (() => { const prod = v.asin ? productByAsin.get(v.asin) : undefined; return <td key="fba_pick_pack" className="px-3 py-2 text-right font-mono text-[11px]">{prod ? `$${prod.pick_pack_fee.toFixed(2)}` : '—'}</td>; })(),
                        fba_referral: (() => { const prod = v.asin ? productByAsin.get(v.asin) : undefined; return <td key="fba_referral" className="px-3 py-2 text-right font-mono text-[11px]">{prod ? `$${prod.referral_fee.toFixed(2)}` : '—'}</td>; })(),
                        cost_of_goods: (() => { const prod = v.asin ? productByAsin.get(v.asin) : undefined; return <td key="cost_of_goods" className="px-3 py-2 text-right font-mono text-[11px]">{prod ? `$${prod.cogs.toFixed(2)}` : '—'}</td>; })(),
                        shipping_cost_per_unit: (() => { const prod = v.asin ? productByAsin.get(v.asin) : undefined; return <td key="shipping_cost_per_unit" className="px-3 py-2 text-right font-mono text-[11px]">{prod ? `$${prod.shipping_cost.toFixed(2)}` : '—'}</td>; })(),
                        fba_stock_qty: (() => { const sc = v.asin ? supplyChainByAsin.get(v.asin) : undefined; const q = sc?.fba_stock_qty; return <td key="fba_stock_qty" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{q != null && q > 0 ? fmt(q) : '—'}</td>; })(),
                        awd_stock_qty: (() => { const sc = v.asin ? supplyChainByAsin.get(v.asin) : undefined; const q = sc?.awd_stock_qty; return <td key="awd_stock_qty" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{q != null && q > 0 ? fmt(q) : '—'}</td>; })(),
                        in_transit_qty: (() => { const sc = v.asin ? supplyChainByAsin.get(v.asin) : undefined; const q = sc?.in_transit_qty; return <td key="in_transit_qty" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{q != null && q > 0 ? fmt(q) : '—'}</td>; })(),
                        mfr_stock_qty: (() => { const sc = v.asin ? supplyChainByAsin.get(v.asin) : undefined; const q = sc?.mfr_stock_qty; return <td key="mfr_stock_qty" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{q != null && q > 0 ? fmt(q) : '—'}</td>; })(),
                        days_of_coverage: (() => { const sc = v.asin ? supplyChainByAsin.get(v.asin) : undefined; const d = sc?.days_of_coverage; return <td key="days_of_coverage" className={`px-3 py-2 text-right font-mono text-[11px] font-bold ${d != null ? (d < 70 ? 'text-red-400' : d < 100 ? 'text-amber-400' : 'text-emerald-400') : 'text-faint'}`}>{d != null ? d : '—'}</td>; })(),
                        fba_days_of_coverage: (() => { const sc = v.asin ? supplyChainByAsin.get(v.asin) : undefined; const d = sc?.fba_days_of_coverage; return <td key="fba_days_of_coverage" className={`px-3 py-2 text-right font-mono text-[11px] ${d != null ? (d <= 20 ? 'text-red-400 font-bold' : d < 30 ? 'text-amber-400' : d <= 45 ? 'text-emerald-400' : d <= 60 ? 'text-amber-400' : 'text-red-400 font-bold') : 'text-faint'}`}>{d != null ? d : '—'}</td>; })(),
                        awd_days_of_coverage: (() => { const sc = v.asin ? supplyChainByAsin.get(v.asin) : undefined; const d = sc?.awd_days_of_coverage; return <td key="awd_days_of_coverage" className={`px-3 py-2 text-right font-mono text-[11px] ${d != null ? (d < 50 ? 'text-amber-400' : 'text-emerald-400') : 'text-faint'}`}>{d != null ? d : '—'}</td>; })(),
                        days_next_shipment: (() => { const sc = v.asin ? supplyChainByAsin.get(v.asin) : undefined; const d = sc?.days_to_next_shipment; return <td key="days_next_shipment" className={`px-3 py-2 text-right font-mono text-[11px] ${d != null ? (d <= 3 ? 'text-emerald-400 font-bold' : d <= 14 ? 'text-sky-400' : 'text-subtle') : 'text-faint'}`}>{d != null ? d : '—'}</td>; })(),
                        qty_next_shipment: (() => { const sc = v.asin ? supplyChainByAsin.get(v.asin) : undefined; const q = sc?.next_shipment_qty; return <td key="qty_next_shipment" className="px-3 py-2 text-right font-mono text-[11px]">{q != null ? fmt(q) : '—'}</td>; })(),
                        last_30d_sold: (() => { const sc = v.asin ? supplyChainByAsin.get(v.asin) : undefined; const q = sc?.last_30d_sold; return <td key="last_30d_sold" className="px-3 py-2 text-right font-mono text-[11px]">{q != null ? fmt(q) : '—'}</td>; })(),
                        next_30d_planned: (() => { const sc = v.asin ? supplyChainByAsin.get(v.asin) : undefined; const q = sc?.next_30d_planned; return <td key="next_30d_planned" className="px-3 py-2 text-right font-mono text-[11px]">{q != null ? fmt(q) : '—'}</td>; })(),
                        next_31_60d_planned: (() => { const sc = v.asin ? supplyChainByAsin.get(v.asin) : undefined; const q = sc?.next_31_60d_planned; return <td key="next_31_60d_planned" className="px-3 py-2 text-right font-mono text-[11px]">{q != null ? fmt(q) : '—'}</td>; })(),
                        next_61_90d_planned: (() => { const sc = v.asin ? supplyChainByAsin.get(v.asin) : undefined; const q = sc?.next_61_90d_planned; return <td key="next_61_90d_planned" className="px-3 py-2 text-right font-mono text-[11px]">{q != null ? fmt(q) : '—'}</td>; })(),
                        awd_min_defined: (() => {
                          const sc = v.asin ? supplyChainByAsin.get(v.asin) : undefined;
                          if (!sc || (sc.awd_stock_qty || 0) <= 0) return <td key="awd_min_defined" className="px-3 py-2 text-right font-mono text-[11px] text-faint">—</td>;
                          return <td key="awd_min_defined" className="px-3 py-2 text-right font-mono text-[11px]">{sc.awd_target_min != null ? fmt(sc.awd_target_min) : '—'} <span className="text-faint">({sc.awd_approved_min != null ? fmt(sc.awd_approved_min) : '—'})</span></td>;
                        })(),
                        awd_max_defined: (() => {
                          const sc = supplyChainByAsin.get(v.asin!);
                          if (!sc || !sc.awd_stock_qty) return <td key="awd_max_defined" className="px-3 py-2 text-right font-mono text-[11px] text-faint">—</td>;
                          const hasApprovalNeeds = sc.awd_diff_pct != null && sc.awd_diff_pct > 10;
                          const isJustApproved = approvedAwds.has(v.asin!);
                          const diff = sc.awd_diff_pct || 0;
                          const needsApp = hasApprovalNeeds && !isJustApproved;
                          return (
                            <td key="awd_max_defined" className={`px-3 py-2 text-right font-mono text-[11px] font-bold ${needsApp ? (diff > 30 ? 'text-red-400' : diff > 20 ? 'text-orange-400' : 'text-amber-400') : 'text-emerald-400'}`}>
                              <div className="flex items-center justify-end gap-2">
                                <span>{sc.awd_target_max != null ? fmt(sc.awd_target_max) : '—'} <span className="text-faint">({sc.awd_approved_max > 0 ? fmt(sc.awd_approved_max) : '—'})</span></span>
                                {needsApp && (
                                  <button onClick={(e) => { e.stopPropagation(); handleApproveAwd(v.asin!, Math.round(sc.awd_target_min || 0), Math.round(sc.awd_target_max || 0)); }} className={`px-2 py-0.5 rounded text-[10px] font-medium transition-colors ${diff > 30 ? 'bg-red-500/20 text-red-300 hover:bg-red-500/40' : diff > 20 ? 'bg-orange-500/20 text-orange-300 hover:bg-orange-500/40' : 'bg-amber-500/20 text-amber-300 hover:bg-amber-500/40'}`}>
                                    Approve
                                  </button>
                                )}
                              </div>
                            </td>
                          );
                        })(),
                      };
                      return cells[key] ?? <td key={key} className="px-3 py-2">—</td>;
                    }
                    const sharePct = totalFamilySales > 0 ? (r.sales / totalFamilySales) * 100 : 0;
                    const cells: Record<string, React.ReactNode> = {
                      sales: <td key="sales" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{fM(r.sales)}</td>,
                      share_pct: (
                        <td key="share_pct" className="px-3 py-2 text-right">
                          <div className="flex items-center justify-end gap-1.5">
                            <div className="w-14 h-1.5 bg-zinc-800 rounded-full overflow-hidden">
                              <div className="h-full rounded-full" style={{ width: `${Math.min(100, sharePct)}%`, background: f ? FAMILIES[f]?.color ?? '#3b82f6' : '#3b82f6' }} />
                            </div>
                            <span className="font-mono text-[11px] text-subtle">{fP(sharePct)}</span>
                          </div>
                        </td>
                      ),
                      cogs: <td key="cogs" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{fM(r.cogs)}</td>,
                      ad_cost: <td key="ad_cost" className="px-3 py-2 text-right font-mono text-[11px] text-red-400">{fM(r.ad_cost)}</td>,
                      pct_ads_spend: <td key="pct_ads_spend" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{totalAdCost > 0 ? fP((r.ad_cost / totalAdCost) * 100) : '—'}</td>,
                      net_profit: <td key="net_profit" className="px-3 py-2 text-right font-mono text-[11px] font-bold text-sky-400">{fM(r.net_profit)}</td>,
                      pct_net_profit: <td key="pct_net_profit" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{totalNetProfit > 0 && r.net_profit > 0 ? fP((r.net_profit / totalNetProfit) * 100) : '—'}</td>,
                      net_roas: <td key="net_roas" className="px-3 py-2 text-right"><RoasBadge value={r.net_roas} /></td>,
                      tacos: <td key="tacos" className={`px-3 py-2 text-right font-mono text-[11px] font-bold ${r.sales > 0 ? ((r.ad_cost / r.sales) * 100 > 30 ? 'text-red-400' : (r.ad_cost / r.sales) * 100 > 15 ? 'text-amber-400' : 'text-emerald-400') : 'text-faint'}`}>{r.sales > 0 ? fP((r.ad_cost / r.sales) * 100) : '—'}</td>,
                      ads_roas: (() => { const ar = r.ad_cost > 0 ? (r.ads_sales || 0) / r.ad_cost : 0; return <td key="ads_roas" className="px-3 py-2 text-right">{ar > 0 ? <RoasBadge value={ar} /> : <span className="text-faint">—</span>}</td>; })(),
                      ad_orders: <td key="ad_orders" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{fmt(r.ad_orders ?? 0)}</td>,
                      units: <td key="units" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{fmt(r.units ?? 0)}</td>,
                      orders: <td key="orders" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{fmt(r.orders)}</td>,
                      clicks: <td key="clicks" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{fClk(r.clicks)}</td>,
                      sessions: <td key="sessions" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{(r.sessions ?? 0) > 0 ? (r.sessions ?? 0).toLocaleString() : '—'}</td>,
                      sales_change: <td key="sales_change" className="px-3 py-2"><ChangesSummaryCell data={famChanges ?? { status: r.sales_change > 0 ? 'Sales up' : r.sales_change < 0 ? 'Sales down' : 'Flat vs previous period', sd: r.sales_change ?? 0, cd: 0, pd: 0, roasDelta: 0, orgDelta: 0 }} positiveCount={totalCount > 0 ? positiveCount : undefined} totalCount={totalCount > 0 ? totalCount : undefined} /></td>,
                      // Summable / derivable family-level aggregates (previously rendered as "—").
                      ads_sales: <td key="ads_sales" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{fM(r.ads_sales ?? 0)}</td>,
                      ads_units: <td key="ads_units" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{fmt(r.ads_units ?? 0)}</td>,
                      payment: <td key="payment" className="px-3 py-2 text-right font-mono text-[11px] font-bold text-sky-400">{fM(r.payment ?? 0)}</td>,
                      storage_cost: <td key="storage_cost" className="px-3 py-2 text-right font-mono text-[11px] text-amber-400">{(r.storage_cost ?? 0) !== 0 ? fM(r.storage_cost) : '—'}</td>,
                      np_per_unit: <td key="np_per_unit" className={`px-3 py-2 text-right font-mono text-[11px] font-medium ${(r.units ?? 0) > 0 ? (r.net_profit / r.units > 0 ? 'text-emerald-400' : 'text-red-400') : 'text-faint'}`}>{(r.units ?? 0) > 0 ? fM(r.net_profit / r.units) : '—'}</td>,
                      organic_units: <td key="organic_units" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{fmt(r.organic_units ?? 0)}</td>,
                      organic_pct: <td key="organic_pct" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{fP(r.organic_pct ?? 0)}</td>,
                      // Per-family inventory totals (summed across the family's ASINs).
                      fba_stock_qty: <td key="fba_stock_qty" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{(r.fba_stock_qty ?? 0) > 0 ? fmt(r.fba_stock_qty) : '—'}</td>,
                      awd_stock_qty: <td key="awd_stock_qty" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{(r.awd_stock_qty ?? 0) > 0 ? fmt(r.awd_stock_qty) : '—'}</td>,
                      in_transit_qty: <td key="in_transit_qty" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{(r.in_transit_qty ?? 0) > 0 ? fmt(r.in_transit_qty) : '—'}</td>,
                      mfr_stock_qty: <td key="mfr_stock_qty" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{(r.mfr_stock_qty ?? 0) > 0 ? fmt(r.mfr_stock_qty) : '—'}</td>,
                      days_of_coverage: (() => { const d = r.days_of_coverage; return <td key="days_of_coverage" className={`px-3 py-2 text-right font-mono text-[11px] font-bold ${d != null ? (d < 70 ? 'text-red-400' : d < 100 ? 'text-amber-400' : 'text-emerald-400') : 'text-faint'}`}>{d != null ? d : '—'}</td>; })(),
                      fba_days_of_coverage: (() => { const d = r.fba_days_of_coverage; return <td key="fba_days_of_coverage" className={`px-3 py-2 text-right font-mono text-[11px] ${d != null ? (d <= 20 ? 'text-red-400 font-bold' : d < 30 ? 'text-amber-400' : d <= 45 ? 'text-emerald-400' : d <= 60 ? 'text-amber-400' : 'text-red-400 font-bold') : 'text-faint'}`}>{d != null ? d : '—'}</td>; })(),
                      awd_days_of_coverage: (() => { const d = r.awd_days_of_coverage; return <td key="awd_days_of_coverage" className={`px-3 py-2 text-right font-mono text-[11px] ${d != null ? (d < 50 ? 'text-amber-400' : 'text-emerald-400') : 'text-faint'}`}>{d != null ? d : '—'}</td>; })(),
                      qty_next_shipment: <td key="qty_next_shipment" className="px-3 py-2 text-right font-mono text-[11px]">{(r.qty_next_shipment ?? 0) > 0 ? fmt(r.qty_next_shipment) : '—'}</td>,
                      last_30d_sold: <td key="last_30d_sold" className="px-3 py-2 text-right font-mono text-[11px]">{(r.last_30d_sold ?? 0) > 0 ? fmt(r.last_30d_sold) : '—'}</td>,
                      next_30d_planned: <td key="next_30d_planned" className="px-3 py-2 text-right font-mono text-[11px]">{(r.next_30d_planned ?? 0) > 0 ? fmt(r.next_30d_planned) : '—'}</td>,
                      next_31_60d_planned: <td key="next_31_60d_planned" className="px-3 py-2 text-right font-mono text-[11px]">{(r.next_31_60d_planned ?? 0) > 0 ? fmt(r.next_31_60d_planned) : '—'}</td>,
                      next_61_90d_planned: <td key="next_61_90d_planned" className="px-3 py-2 text-right font-mono text-[11px]">{(r.next_61_90d_planned ?? 0) > 0 ? fmt(r.next_61_90d_planned) : '—'}</td>,
                    };
                    return cells[key] ?? <td key={key} className="px-3 py-2">—</td>;
                  };
                  return (
                    <React.Fragment key={i}>
                      <tr onClick={() => f && setExpandedFamily(isExpanded ? null : f)} className={`border-b border-border-faint last:border-b-0 hover:bg-white/[.02] cursor-pointer transition-colors`}>
                        {visibleFamilyCols.map(c => renderCell(c.id, false))}
                      </tr>
                      {isExpanded && vars.map((v, j) => (
                        <tr key={`${i}-${j}`} onClick={(e) => { e.stopPropagation(); if (f) { setFilter('product', v.asin || null); onNav('sqp', f); } }} className="border-b border-border-faint hover:bg-white/[.02] cursor-pointer bg-inset">
                          {visibleFamilyCols.map(c => c.id === 'family' ? <td key={c.id} className="px-3 py-2 pl-8 font-medium text-subtle"><span className="text-zinc-500 mr-1">↳</span>{v.product_short_name || v.asin}</td> : renderCell(c.id, true, v))}
                        </tr>
                      ))}
                    </React.Fragment>
                  );
                });
              })()}
              {/* Total row */}
              {familyPeriodDataDisplay && familyPeriodDataDisplay.length > 1 && (() => {
                  const tot = familyPeriodDataDisplay.reduce((acc, r) => ({
                    sales: acc.sales + r.sales,
                    cogs: acc.cogs + r.cogs,
                    ad_cost: acc.ad_cost + r.ad_cost,
                    ads_sales: acc.ads_sales + (r.ads_sales || 0),
                    ads_units: acc.ads_units + (r.ads_units || 0),
                    net_profit: acc.net_profit + r.net_profit,
                    orders: acc.orders + r.orders,
                    units: acc.units + (r.units || 0),
                    clicks: acc.clicks + r.clicks,
                    sessions: acc.sessions + (r.sessions || 0),
                    organic_units: acc.organic_units + r.organic_units,
                    ad_orders: acc.ad_orders + r.ad_orders,
                  }), { sales: 0, cogs: 0, ad_cost: 0, ads_sales: 0, ads_units: 0, net_profit: 0, orders: 0, units: 0, clicks: 0, sessions: 0, organic_units: 0, ad_orders: 0 });
                  const net_roas = tot.ad_cost ? (tot.sales - tot.cogs) / tot.ad_cost : 0;
                  const organic_pct = tot.units > 0 ? (tot.organic_units / tot.units) * 100 : 0;
                  const totalCells: Record<string, React.ReactNode> = {
                    family: <td key="family" className="px-3 py-2 font-bold">Total</td>,
                    sales: <td key="sales" className="px-3 py-2 text-right font-mono text-[11px] font-bold">{fM(tot.sales)}</td>,
                    share_pct: <td key="share_pct" className="px-3 py-2 text-right font-mono text-[11px] font-bold">100%</td>,
                    cogs: <td key="cogs" className="px-3 py-2 text-right font-mono text-[11px] font-bold">{fM(tot.cogs)}</td>,
                    ad_cost: <td key="ad_cost" className="px-3 py-2 text-right font-mono text-[11px] font-bold">{fM(tot.ad_cost)}</td>,
                    pct_ads_spend: <td key="pct_ads_spend" className="px-3 py-2 text-right font-mono text-[11px] font-bold">100%</td>,
                    ads_sales: <td key="ads_sales" className="px-3 py-2 text-right font-mono text-[11px] font-bold">{fM(tot.ads_sales)}</td>,
                    ads_units: <td key="ads_units" className="px-3 py-2 text-right font-mono text-[11px] font-bold">{fmt(tot.ads_units)}</td>,
                    net_profit: <td key="net_profit" className={`px-3 py-2 text-right font-mono text-[11px] font-bold ${tot.net_profit > 0 ? 'text-emerald-400' : 'text-red-400'}`}>{fM(tot.net_profit)}</td>,
                    pct_net_profit: <td key="pct_net_profit" className="px-3 py-2 text-right font-mono text-[11px] font-bold">100%</td>,
                    np_per_unit: <td key="np_per_unit" className={`px-3 py-2 text-right font-mono text-[11px] font-bold ${tot.units > 0 ? (tot.net_profit / tot.units > 0 ? 'text-emerald-400' : 'text-red-400') : 'text-faint'}`}>{tot.units > 0 ? fM(tot.net_profit / tot.units) : '—'}</td>,
                    net_roas: <td key="net_roas" className="px-3 py-2 text-right"><RoasBadge value={net_roas} /></td>,
                    tacos: <td key="tacos" className={`px-3 py-2 text-right font-mono text-[11px] font-bold ${tot.sales > 0 ? ((tot.ad_cost / tot.sales) * 100 > 30 ? 'text-red-400' : (tot.ad_cost / tot.sales) * 100 > 15 ? 'text-amber-400' : 'text-emerald-400') : 'text-faint'}`}>{tot.sales > 0 ? fP((tot.ad_cost / tot.sales) * 100) : '—'}</td>,
                    ads_roas: (() => { const ar = tot.ad_cost > 0 ? tot.ads_sales / tot.ad_cost : 0; return <td key="ads_roas" className="px-3 py-2 text-right">{ar > 0 ? <RoasBadge value={ar} /> : <span className="text-faint">—</span>}</td>; })(),
                    payment: (() => { const totPayment = familyPeriodDataDisplay.reduce((s, r) => s + (r.payment ?? 0), 0); return <td key="payment" className={`px-3 py-2 text-right font-mono text-[11px] font-bold ${totPayment > 0 ? 'text-sky-400' : 'text-red-400'}`}>{fM(totPayment)}</td>; })(),
                    storage_cost: (() => { const totStorage = familyPeriodDataDisplay.reduce((s, r) => s + (r.storage_cost ?? 0), 0); return <td key="storage_cost" className="px-3 py-2 text-right font-mono text-[11px] font-bold text-amber-400">{totStorage > 0 ? fM(totStorage) : '—'}</td>; })(),
                    ad_orders: <td key="ad_orders" className="px-3 py-2 text-right font-mono text-[11px] font-bold">{fmt(tot.ad_orders)}</td>,
                    units: <td key="units" className="px-3 py-2 text-right font-mono text-[11px] font-bold">{fmt(tot.units)}</td>,
                    orders: <td key="orders" className="px-3 py-2 text-right font-mono text-[11px] font-bold">{fmt(tot.orders)}</td>,
                    organic_units: <td key="organic_units" className="px-3 py-2 text-right font-mono text-[11px] font-bold">{fmt(tot.organic_units)}</td>,
                    clicks: <td key="clicks" className="px-3 py-2 text-right font-mono text-[11px] font-bold">{fClk(tot.clicks)}</td>,
                    sessions: <td key="sessions" className="px-3 py-2 text-right font-mono text-[11px] font-bold">{tot.sessions > 0 ? tot.sessions.toLocaleString() : '—'}</td>,
                    organic_pct: <td key="organic_pct" className="px-3 py-2 text-right font-mono text-[11px] font-bold">{fP(organic_pct)}</td>,
                    sales_change: <td key="sales_change" className="px-3 py-2" />,
                  };
                  return (
                    <tr className="border-t-2 border-zinc-600 bg-inset">
                      {visibleFamilyCols.map(c => totalCells[c.id] ?? <td key={c.id} className="px-3 py-2">—</td>)}
                    </tr>
                  );
                })()}
              </tbody>
            </table>
          </div>
        ) : <Empty message="No trend data" />}
      </Section>

      {/* Actions Summary */}
      {(() => {
        const filteredActsCount = Object.values(grouped).reduce((s, arr) => s + arr.length, 0);
        return (
          <Section title="Actions To Do" count={filteredActsCount > 0 ? `${filteredActsCount} pending` : undefined} filterItems={formatSectionFilters(filters)}>
            {!filteredActsCount ? <Empty icon="✓" message="No pending actions" /> : (
              <div className="space-y-3.5">
                {([
                  { k: 'urgent', t: 'Urgent', v: 'red' },
                  { k: 'growth', t: 'Growth', v: 'green' },
                  { k: 'experiment', t: 'Experiments', v: 'blue' },
                  { k: 'fix', t: 'Fix', v: 'amber' },
                ] as const).map(({ k, t, v }) => {
              const items = grouped[k];
              if (!items.length) return null;
              return (
                <div key={k}>
                  <Badge variant={v} className="mb-2">{t} ({items.length})</Badge>
                  {items.slice(0, 3).map((a, i) => (
                    <Card key={i} onClick={() => onNav('actions')} className="!p-3 mb-1">
                      <div className="flex justify-between items-center">
                        <div className="flex items-center gap-2">
                          <span className="font-mono text-[10px] text-faint">{i + 1}</span>
                          <strong className="text-xs text-blue-400">"{a.search_term || '--'}"</strong>
                          <span className="text-[11px] text-subtle">{a.product_short_name || ''}</span>
                        </div>
                        <ActionBadge action={a.action} />
                      </div>
                      {a.reason && <div className="text-[11px] text-subtle mt-1 pl-5 truncate">{a.reason}</div>}
                      <div className="flex gap-3 mt-1 pl-5 text-[10px] font-mono text-faint">
                        {(a.spend || a.ads_spend) ? <span>Spend: {fM(a.spend || a.ads_spend || 0)}</span> : null}
                        {(a.orders || a.ads_orders) ? <span>Orders: {fOrd(a.orders || a.ads_orders || 0)}</span> : null}
                        {a.net_roas ? <span>ROAS: {fR(a.net_roas)}</span> : null}
                      </div>
                    </Card>
                  ))}
                  {items.length > 3 && (
                    <div className="text-[11px] text-faint pl-5 cursor-pointer hover:text-blue-400" onClick={() => onNav('actions')}>
                      + {items.length - 3} more →
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </Section>
      );})()}
      {/* Upcoming */}
      <Section title="Near Future" filterItems={formatSectionFilters(filters)}>
        {!(data.upcoming || []).length ? <Empty message="No upcoming events" /> : (
          <div className="space-y-1.5">
            {(data.upcoming || []).slice(0, 6).map((e, i) => {
              const isPeakHoliday = pk && pk.holiday_name === e.holiday_name;
              const peakExps = isPeakHoliday ? (data.experiments || []).filter(ex =>
                (ex.status === 'ACTIVE' || ex.status === 'RUNNING') &&
                (ex.experiment_name || '').toLowerCase().includes((e.holiday_name || '').toLowerCase())
              ) : [];
              const readinessItems: string[] = [];
              if (isPeakHoliday && pk) {
                if (peakExps.length > 0) readinessItems.push(`${peakExps.length} active experiment${peakExps.length > 1 ? 's' : ''}`);
                else readinessItems.push('No peak experiments yet');
                if (pk.current_stage) readinessItems.push(`Stage: ${STAGE_LABELS_SHORT[pk.current_stage] || pk.current_stage}`);
              }
              return (
                <Card key={i} className={`!p-3 ${isPeakHoliday ? '!border-l-[3px] !border-l-amber-500' : ''}`}>
                  <div className="flex justify-between items-center mb-1">
                    <div>
                      <strong>{e.holiday_name || '--'}</strong>
                      <span className="text-[11px] text-subtle ml-2">{e.holiday_date || ''}</span>
                      {isPeakHoliday && <Badge variant="amber" className="ml-2 !text-[9px]">PEAK</Badge>}
                    </div>
                    <div className="flex items-center gap-1.5">
                      <Badge variant={e.status === 'ACTIVE' ? 'green' : e.status === 'UPCOMING' ? 'blue' : 'muted'}>{e.status || '--'}</Badge>
                      {e.days_until_holiday != null && <span className="font-mono text-[11px] text-subtle">{e.days_until_holiday}d</span>}
                    </div>
                  </div>
                  <div className="text-[11px] text-subtle">
                    Category: {e.category || '--'} · Pre-season: {e.pre_season_start || '--'}
                    {e.days_until_pre_season != null && e.days_until_pre_season > 0 ? ` (in ${e.days_until_pre_season}d)` : e.days_until_pre_season != null && e.days_until_pre_season <= 0 ? ' (started)' : ''}
                  </div>
                  {readinessItems.length > 0 && (
                    <div className="flex flex-wrap gap-2 mt-1.5">
                      {readinessItems.map((item, j) => (
                        <span key={j} className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-zinc-800/60 text-faint border border-zinc-700/30">{item}</span>
                      ))}
                    </div>
                  )}
                </Card>
              );
            })}
          </div>
        )}
      </Section>
    </div>
  );
}
