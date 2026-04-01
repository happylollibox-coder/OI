import React, { useState, useMemo } from 'react';
import { ComposedChart, Bar, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, Cell, LabelList, ReferenceLine, Legend } from 'recharts';
import { SeasonalReferenceLines, getXLabels } from '../components/SeasonalReferenceLines';
import type { DashboardData, FamilyName, TrendRow, Ads7dRow } from '../types';
import { FAMILIES } from '../types';
import { ChevronRight, ChevronDown } from 'lucide-react';
import { Card } from '../components/Card';
import { ChangesSummaryCell } from '../components/ChangesSummaryCell';
import { Section } from '../components/Section';
import { Badge, RoasBadge, ActionBadge } from '../components/Badge';
import { Empty } from '../components/Empty';
import { SortTh, useSort, MEASURE_TIPS } from '../components/Tooltip';
import { DashboardSummary } from '../components/DashboardSummary';
import { fM, fP, fR, fOrd, fClk, famFromType, weekRangeLabel, formatDateRange, ACTION_META, sqpCoverageWeeks, latestSqpWeek, periodDateKey, latestPeriodLabel, sliceByPeriod, getPeriodsToInclude, shiftYear, addDays, weeksInDateRange, weekOverlapsAdsGap, monthOverlapsAdsGap, scoreFromRoas, scoreFromProfitDelta, periodKey, experimentMatchesFamily } from '../utils';
import { filterBySeasonality, getSeasonality } from '../seasonality';
import { useFilters } from '../hooks/useFilters';
import { formatSectionFilters } from '../utils/filterUtils';
import { CHART_GRID, CHART_AXIS_TICK_LG, CHART_TOOLTIP_STYLE } from '../chartTheme';
import { MEASURE_META, type TrendMeasure } from '../constants';
import { MeasureSelector, useMeasureSelection, type MeasureDef } from '../components/MeasureSelector';
import { usePageSummary } from '../components/PageSummaryBar';

const ALL_MEASURES: TrendMeasure[] = ['sales', 'ad_cost', 'cogs', 'net_profit', 'net_roas', 'orders', 'clicks', 'sessions', 'organic_pct'];

const FAMILY_TABLE_COLUMNS: MeasureDef[] = [
  { id: 'family', label: 'Family', group: 'Info' },
  { id: 'sales', label: 'Sales', tip: MEASURE_TIPS.sales, group: 'PnL' },
  { id: 'share_pct', label: 'Share %', tip: 'Percentage of total sales across all families', group: 'PnL' },
  { id: 'cogs', label: 'COGS', tip: MEASURE_TIPS.cogs, group: 'PnL' },
  { id: 'ad_cost', label: 'Ads Spend', tip: MEASURE_TIPS.ad_cost, group: 'Ads' },
  { id: 'ads_sales', label: 'Ads Sales', tip: 'Sales attributed to ads campaigns', group: 'Ads' },
  { id: 'ads_units', label: 'Ads Units', tip: 'Units sold attributed to ads campaigns', group: 'Ads', defaultVisible: false },
  { id: 'net_profit', label: 'Net Profit', tip: MEASURE_TIPS.net_profit, group: 'PnL' },
  { id: 'np_per_unit', label: 'NP/Unit', tip: 'Net Profit divided by total units sold — your north-star metric', group: 'PnL' },
  { id: 'net_roas', label: 'Net ROAS', tip: MEASURE_TIPS.net_roas, group: 'Ads' },
  { id: 'ads_roas', label: 'Ads ROAS', tip: 'Ads Sales / Ads Spend — gross advertising return', group: 'Ads', defaultVisible: false },
  { id: 'tacos', label: 'TACoS', tip: 'Total Ads Cost of Sales — Ads Spend / Total Sales — measures ad dependency', group: 'Ads' },
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
  const [selectedMeasures, setSelectedMeasures] = useState<Set<TrendMeasure>>(new Set(['net_profit']));
  const [expandedFamily, setExpandedFamily] = useState<FamilyName | null>(null);
  const [familyCols, setFamilyCols] = useMeasureSelection('home_family', FAMILY_TABLE_COLUMNS);
  const visibleFamilyCols = useMemo(() => FAMILY_TABLE_COLUMNS.filter(c => familyCols.has(c.id)), [familyCols]);
  const urgentActions = useMemo(() => (data.actions || []).filter(a => a.action === 'REDUCE BID' || a.action === 'NEGATE').length, [data.actions]);

  const toggleMeasure = (m: TrendMeasure) => {
    setSelectedMeasures(prev => {
      const next = new Set(prev);
      if (next.has(m)) { if (next.size > 1) next.delete(m); }
      else next.add(m);
      return next;
    });
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

    if (periodMode === 'weeks') {
      const wt = filteredWeekly;
      const allWeeks = [...new Set(wt.map(r => r.week_start || ''))].filter(Boolean).sort();
      const allWeeksExtended = [...new Set([...allWeeks, ...sqpWeeks, ...adsPeriodKeys.weeks])].filter(Boolean).sort();
      let curWeek: string;
      if (filters.specificPeriod && allWeeksExtended.includes(filters.specificPeriod)) {
        curWeek = filters.specificPeriod;
      } else {
        // Default: second-to-last period (skip incomplete latest)
        const latestSqp = latestSqpWeek(data.sqp_weekly || []);
        const adsLatest = adsPeriodKeys.weeks.length ? adsPeriodKeys.weeks[adsPeriodKeys.weeks.length - 1] : null;
        const defaultLatest = latestSqp ?? adsLatest ?? (allWeeksExtended.length ? allWeeksExtended[allWeeksExtended.length - 1] : '');
        const defaultIdx = allWeeksExtended.indexOf(defaultLatest);
        curWeek = defaultIdx > 0 ? allWeeksExtended[defaultIdx - 1] : defaultLatest;
      }
      const curIdx = allWeeksExtended.indexOf(curWeek);
      const prvWeek = curIdx > 0 ? allWeeksExtended[curIdx - 1] : '';
      const cur = agg(wt.filter(r => r.week_start === curWeek), 'weeks', curWeek);
      const prv = prvWeek ? agg(wt.filter(r => r.week_start === prvWeek), 'weeks', prvWeek) : null;
      return { totals: cur, prevTotals: prv, kpiWeek: curWeek, kpiPrevWeek: prvWeek, kpiPeriodLabel: curWeek ? weekRangeLabel(curWeek) : '' };
    }

    if (periodMode === 'month') {
      const mt = filteredMonthly;
      const allMonths = [...new Set([...mt.map(r => (r.month_start || '').slice(0, 7)), ...adsPeriodKeys.months])].filter(Boolean).sort();
      const keep = new Set(getPeriodsToInclude(filters.specificPeriod, 'month', allMonths, 2));
      const periods = [...keep].sort();
      const curPeriod = periods[periods.length - 1] || '';
      const prvPeriod = periods.length >= 2 ? periods[periods.length - 2] : '';
      const cur = agg(mt.filter(r => (r.month_start || '').slice(0, 7) === curPeriod), 'month', curPeriod);
      const prv = prvPeriod ? agg(mt.filter(r => (r.month_start || '').slice(0, 7) === prvPeriod), 'month', prvPeriod) : null;
      return { totals: cur, prevTotals: prv, kpiWeek: curPeriod, kpiPrevWeek: prvPeriod, kpiPeriodLabel: curPeriod };
    }

    // periodMode === 'year'
    const mt = filteredMonthly;
    const allYears = [...new Set([...mt.map(r => (r.month_start || '').slice(0, 4)), ...adsPeriodKeys.years])].filter(Boolean).sort();
    const keep = new Set(getPeriodsToInclude(filters.specificPeriod, 'year', allYears, 2));
    const years = [...keep].sort();
    const curYear = years[years.length - 1] || '';
    const prvYear = years.length >= 2 ? years[years.length - 2] : '';
    const cur = agg(mt.filter(r => (r.month_start || '').slice(0, 4) === curYear), 'year', curYear);
    const prv = prvYear ? agg(mt.filter(r => (r.month_start || '').slice(0, 4) === prvYear), 'year', prvYear) : null;
    return { totals: cur, prevTotals: prv, kpiWeek: curYear, kpiPrevWeek: prvYear, kpiPeriodLabel: curYear };
  }, [filteredWeekly, filteredMonthly, sqpWeeks, adsPeriodKeys, filters.specificPeriod, periodMode, data.sqp_weekly]);

  // Ads Spend from ads_7d only (Cube Ads.spend) — same period + filters as Ads page. When no family filter, restrict to product-family campaigns so scope matches sales/cogs.
  const { effectiveTotals, effectivePrevTotals } = useMemo(() => {
    let ads7d: Ads7dRow[] = data.ads_7d_summary || [];
    if (famMatch) ads7d = ads7d.filter(r => famMatch.some(p => (r.campaign_name || '').toLowerCase().includes(p)));
    else ads7d = ads7d.filter(r => ALL_FAMILY_PATTERNS.some(p => (r.campaign_name || '').toLowerCase().includes(p)));
    if (expCampaignIds) {
      ads7d = ads7d.filter(r => expCampaignIds.has(r.campaign_id));
    }
    if (filters.keyword) {
      const campaignIdsWithKeyword = new Set(
        (data.campaign_search_terms || []).filter(r => r.search_term === filters.keyword).map(r => r.campaign_id)
      );
      ads7d = ads7d.filter(r => campaignIdsWithKeyword.has(r.campaign_id));
    }
    // Apply seasonality filter to ads data too
    if (filters.seasonality && pk) {
      ads7d = ads7d.filter(r => {
        const d = r.date || r.week_start || '';
        return d ? getSeasonality(d, pk) === filters.seasonality : false;
      });
    }
    const useDateFilter = periodMode !== 'weeks' && ads7d.some(r => r.date);
    const matchPeriod = (r: Ads7dRow, pk: string) => {
      if (useDateFilter) {
        const d = r.date || '';
        return periodMode === 'month' ? d.slice(0, 7) === pk : d.slice(0, 4) === pk;
      }
      return periodKey(r.week_start || '', periodMode) === pk;
    };
    const curRows = kpiWeek ? ads7d.filter(r => matchPeriod(r, kpiWeek)) : [];
    const prevRows = kpiPrevWeek ? ads7d.filter(r => matchPeriod(r, kpiPrevWeek)) : [];
    const coFromAds = curRows.reduce((s, r) => s + (r.spend || 0), 0);
    const prevCoFromAds = prevRows.reduce((s, r) => s + (r.spend || 0), 0);
    const npFromAds = totals.sl - totals.cg - coFromAds;
    const prevNpFromAds = prevTotals ? prevTotals.sl - prevTotals.cg - prevCoFromAds : 0;
    return {
      effectiveTotals: { ...totals, co: coFromAds, np: npFromAds },
      effectivePrevTotals: prevTotals ? { ...prevTotals, co: prevCoFromAds, np: prevNpFromAds } : null,
    };
  }, [data.ads_7d_summary, data.campaign_search_terms, kpiWeek, kpiPrevWeek, periodMode, totals, prevTotals, famMatch, expCampaignIds, filters.keyword, filters.seasonality, pk]);

  /** Ads spend per period (for Trend, miniTrend, kpiSparkline) — same filters as effectiveTotals. When no family filter, restrict to product-family campaigns. */
  const adsSpendByPeriod = useMemo(() => {
    let ads7d: Ads7dRow[] = data.ads_7d_summary || [];
    if (famMatch) ads7d = ads7d.filter(r => famMatch.some(p => (r.campaign_name || '').toLowerCase().includes(p)));
    else ads7d = ads7d.filter(r => ALL_FAMILY_PATTERNS.some(p => (r.campaign_name || '').toLowerCase().includes(p)));
    if (expCampaignIds) ads7d = ads7d.filter(r => expCampaignIds.has(r.campaign_id));
    if (filters.keyword) {
      const ids = new Set((data.campaign_search_terms || []).filter(r => r.search_term === filters.keyword).map(r => r.campaign_id));
      ads7d = ads7d.filter(r => ids.has(r.campaign_id));
    }
    if (filters.seasonality && pk) {
      ads7d = ads7d.filter(r => { const d = r.date || r.week_start || ''; return d ? getSeasonality(d, pk) === filters.seasonality : false; });
    }
    const useDateFilter = periodMode !== 'weeks' && ads7d.some(r => r.date);
    const getPk = (r: Ads7dRow) => useDateFilter
      ? (r.date || '').slice(0, periodMode === 'month' ? 7 : 4)
      : periodKey(r.week_start || '', periodMode);
    const map: Record<string, number> = {};
    ads7d.forEach(r => { const pk = getPk(r); if (pk) map[pk] = (map[pk] || 0) + (r.spend || 0); });
    return map;
  }, [data.ads_7d_summary, data.campaign_search_terms, periodMode, famMatch, expCampaignIds, filters.keyword, filters.seasonality, pk]);

  /** Ads spend per family per period (for Per Product Family) — campaign_name matches family patterns */
  /** Ads spend/sales/units per product per period.
   *  Uses ads_7d_summary (campaign-level, all campaigns) enriched with product mapping from ads_7d.
   *  Keyed as `productShortName|period`. Family-level helpers derived below. */
  const adsDataByProductAndPeriod = useMemo(() => {
    // Build campaignId → productShortName map from detailed ads_7d (has Product.productShortName)
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
      if (productName) ads7d = ads7d.filter(r => campaignToProduct[r.campaign_id] === productName);
    }
    const useDateFilter = periodMode !== 'weeks' && ads7d.some(r => r.date);
    const getPk = (r: Ads7dRow) => useDateFilter ? (r.date || '').slice(0, periodMode === 'month' ? 7 : 4) : periodKey(r.week_start || '', periodMode);
    const spendMap: Record<string, number> = {};
    const salesMap: Record<string, number> = {};
    const unitsMap: Record<string, number> = {};
    ads7d.forEach(r => {
      let name = r.product_short_name || campaignToProduct[r.campaign_id];
      const campName = String(r.campaign_name || campaignIdToName[r.campaign_id] || '');
      // Fallback: Infer family from campaign name if product mapping is missing
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

  // Product→Family mapping for aggregating product-level ads to family level
  const productToFamily = useMemo(() => {
    const map: Record<string, FamilyName> = {};
    for (const p of (data.products || [])) {
      const fam = famFromType(p.product_type || '') as FamilyName | null;
      if (fam && p.product_short_name) map[p.product_short_name] = fam;
    }
    return map;
  }, [data.products]);

  // Derive family-level ads maps by summing product-level data (backward compat for consumers)
  const { adsSpendByFamilyAndPeriod, adsSalesByFamilyAndPeriod, adsUnitsByFamilyAndPeriod } = useMemo(() => {
    const spendMap: Record<string, number> = {};
    const salesMap: Record<string, number> = {};
    const unitsMap: Record<string, number> = {};
    for (const [key, val] of Object.entries(adsDataByProductAndPeriod.spend)) {
      const [name, period] = key.split('|');
      const fam = productToFamily[name] || (['Lollibox', 'LolliME', 'Bottle', 'Fresh'].includes(name) ? name : null);
      if (fam && period) spendMap[`${fam}|${period}`] = (spendMap[`${fam}|${period}`] || 0) + val;
    }
    for (const [key, val] of Object.entries(adsDataByProductAndPeriod.sales)) {
      const [name, period] = key.split('|');
      const fam = productToFamily[name] || (['Lollibox', 'LolliME', 'Bottle', 'Fresh'].includes(name) ? name : null);
      if (fam && period) salesMap[`${fam}|${period}`] = (salesMap[`${fam}|${period}`] || 0) + val;
    }
    for (const [key, val] of Object.entries(adsDataByProductAndPeriod.units)) {
      const [name, period] = key.split('|');
      const fam = productToFamily[name] || (['Lollibox', 'LolliME', 'Bottle', 'Fresh'].includes(name) ? name : null);
      if (fam && period) unitsMap[`${fam}|${period}`] = (unitsMap[`${fam}|${period}`] || 0) + val;
    }
    return { adsSpendByFamilyAndPeriod: spendMap, adsSalesByFamilyAndPeriod: salesMap, adsUnitsByFamilyAndPeriod: unitsMap };
  }, [adsDataByProductAndPeriod, productToFamily]);

  const roas = effectiveTotals.co ? (effectiveTotals.sl - effectiveTotals.cg) / effectiveTotals.co : 0;
  const orgP = effectiveTotals.orgP;
  const orgOrd = effectiveTotals.or > 0 ? Math.round(effectiveTotals.or * orgP / 100) : 0;
  const sd = effectivePrevTotals?.sl ? ((effectiveTotals.sl - effectivePrevTotals.sl) / effectivePrevTotals.sl) * 100 : 0;
  const cd = effectivePrevTotals?.co ? ((effectiveTotals.co - effectivePrevTotals.co) / effectivePrevTotals.co) * 100 : 0;
  const pd = effectivePrevTotals?.np ? ((effectiveTotals.np - effectivePrevTotals.np) / Math.abs(effectivePrevTotals.np)) * 100 : 0;
  const margin = effectiveTotals.sl ? (effectiveTotals.np / effectiveTotals.sl) * 100 : 0;
  const prevRoas = effectivePrevTotals?.co ? (effectivePrevTotals.sl - effectivePrevTotals.cg) / effectivePrevTotals.co : 0;
  const roasDelta = prevRoas ? ((roas - prevRoas) / Math.abs(prevRoas)) * 100 : 0;
  const prevOrgP = effectivePrevTotals?.orgP || 0;
  const orgDelta = prevOrgP ? ((orgP - prevOrgP) / Math.abs(prevOrgP)) * 100 : 0;

  const acts = data.actions || [];
  const grouped = useMemo(() => {
    const g: Record<string, typeof acts> = { urgent: [], growth: [], experiment: [], fix: [] };
    acts.forEach(a => { const m = ACTION_META[a.action]; (g[m?.group || 'experiment'] || g.experiment).push(a); });
    return g;
  }, [acts]);

  // Trend chart data — aggregate across all families, supports multiple measures
  const activeMeasures = useMemo(() => [...selectedMeasures], [selectedMeasures]);
  const primaryMeta = MEASURE_META[activeMeasures[0]];

  // Compute effective period trend based on periodType
  const effectivePeriodTrend = useMemo(() => {
    if (filters.periodType === 'cumulative') {
      // Month: full year (12 months); Weeks: use periodTrend (default 4)
      if (periodMode === 'month') return 12;
      return filters.periodTrend; // weeks: use chosen period amount
    }
    if (filters.periodType === 'peak' && pk?.pre_peak_start && pk?.peak_end) {
      const preStart = new Date(pk.pre_peak_start + 'T00:00:00');
      const peakEnd = new Date(pk.peak_end + 'T00:00:00');
      const diffMs = peakEnd.getTime() - preStart.getTime();
      const diffWeeks = Math.max(1, Math.ceil(diffMs / (7 * 86400000)));
      if (periodMode === 'weeks') return diffWeeks;
      if (periodMode === 'month') return Math.max(1, Math.ceil(diffWeeks / 4));
      return 1;
    }
    return filters.periodTrend;
  }, [filters.periodType, filters.periodTrend, periodMode, pk]);

  const trendData = useMemo(() => {
    type BucketVal = Record<TrendMeasure, { sum: number; count: number }>;
    const emptyBucket = (): BucketVal => Object.fromEntries(ALL_MEASURES.map(m => [m, { sum: 0, count: 0 }])) as unknown as BucketVal;

    const addRow = (bucket: BucketVal, row: TrendRow) => {
      for (const m of ALL_MEASURES) {
        const v = row[m as keyof TrendRow];
        bucket[m].sum += (typeof v === 'number' ? v : 0);
        bucket[m].count += 1;
      }
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
      const byWeek: Record<string, BucketVal> = {};
      filteredWeekly.forEach(w => {
        const k = w.week_start || '';
        if (!byWeek[k]) byWeek[k] = emptyBucket();
        addRow(byWeek[k], w);
      });
      const weeks = Object.keys(byWeek).sort();
      const keep = new Set(getPeriodsToInclude(filters.specificPeriod, periodMode, weeks, pt));
      const entries = Object.entries(byWeek).filter(([w]) => keep.has(w)).sort(([a], [b]) => a.localeCompare(b));
      // Helper: find nearest week ~52 weeks back (±7 days tolerance)
      const findLyWeek = (w: string): string | null => {
        const target = new Date(w + 'T00:00:00');
        target.setDate(target.getDate() - 364); // ~52 weeks
        const targetTime = target.getTime();
        // find nearest week in allWeeks within ±7 days
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
        const co = adsSpendByPeriod[w] ?? 0;
        const sl = d?.sales?.sum ?? 0;
        const cg = d?.cogs?.sum ?? 0;
        const lyW = findLyWeek(w);
        const lyD = lyW ? byWeek[lyW] : null;
        const lyResolved: Record<string, number> = {};
        if (lyD && lyW) {
          for (const m of activeMeasures) {
            lyResolved[`ly_${m}`] = AVG_MEASURES.has(m) ? (lyD[m].count ? lyD[m].sum / lyD[m].count : 0) : lyD[m].sum;
          }
          const lyCo = adsSpendByPeriod[lyW] ?? 0;
          const lySl = lyD.sales?.sum ?? 0;
          const lyCg = lyD.cogs?.sum ?? 0;
          lyResolved.ly_ad_cost = lyCo;
          lyResolved.ly_net_profit = lySl - lyCg - lyCo;
        }
        return {
          label: weekRangeLabel(w),
          weekKey: w,
          hasSqp: sqpWeeks.has(w),
          ...r, ad_cost: co, net_profit: sl - cg - co,
          ...lyResolved,
        };
      });
      rawData = rawWeeks;
    } else if (periodMode === 'month') {
      const byMonth: Record<string, BucketVal> = {};
      filteredMonthly.forEach(r => {
        const k = (r.month_start || '').slice(0, 7);
        if (!byMonth[k]) byMonth[k] = emptyBucket();
        addRow(byMonth[k], r);
      });

      // For cumulative: full calendar year (Jan-Dec); for peak: 1 month before peak to peak end
      if (filters.periodType === 'cumulative' || filters.periodType === 'peak') {
        const allMonths = Object.keys(byMonth).sort();
        const latestMonth = allMonths[allMonths.length - 1] || '';
        const curYear = latestMonth.slice(0, 4);
        const lyYear = String(parseInt(curYear, 10) - 1);

        let monthSlots: string[];
        if (filters.periodType === 'peak' && pk?.pre_peak_start && pk?.peak_end) {
          // 1 month before peak start to peak end
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
          // Full calendar year: Jan to Dec
          monthSlots = Array.from({ length: 12 }, (_, i) => `${curYear}-${String(i + 1).padStart(2, '0')}`);
        }

        const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        rawData = monthSlots.map(m => {
          const d = byMonth[m] ?? emptyBucket();
          const r = resolve(d);
          const co = adsSpendByPeriod[m] ?? 0;
          const sl = d.sales?.sum ?? 0;
          const cg = d.cogs?.sum ?? 0;
          // LY data
          const lyM = lyYear + m.slice(4); // same month, previous year
          const lyD = byMonth[lyM] ?? emptyBucket();
          const lyResolved: Record<string, number> = {};
          for (const mKey of activeMeasures) {
            lyResolved[`ly_${mKey}`] = AVG_MEASURES.has(mKey) ? (lyD[mKey].count ? lyD[mKey].sum / lyD[mKey].count : 0) : lyD[mKey].sum;
          }
          const lyCo = adsSpendByPeriod[lyM] ?? 0;
          const lySl = lyD.sales?.sum ?? 0;
          const lyCg = lyD.cogs?.sum ?? 0;
          lyResolved.ly_ad_cost = lyCo;
          lyResolved.ly_net_profit = lySl - lyCg - lyCo;
          const monthIdx = parseInt(m.slice(5), 10) - 1;
          return { label: MONTH_NAMES[monthIdx] || m, weekKey: m, hasSqp: true, ...r, ad_cost: co, net_profit: sl - cg - co, ...lyResolved };
        });
      } else {
        const months = Object.keys(byMonth).sort();
        const keep = new Set(getPeriodsToInclude(filters.specificPeriod, periodMode, months, pt));
        const entries = Object.entries(byMonth).filter(([m]) => keep.has(m)).sort(([a], [b]) => a.localeCompare(b));
        rawData = entries.map(([m, d]) => { const r = resolve(d); const co = adsSpendByPeriod[m] ?? 0; const sl = d.sales?.sum ?? 0; const cg = d.cogs?.sum ?? 0; return { label: m, weekKey: m, hasSqp: true, ...r, ad_cost: co, net_profit: sl - cg - co }; });
      }
    } else {
      const byYear: Record<string, BucketVal> = {};
      filteredMonthly.forEach(r => {
        const y = (r.month_start || '').slice(0, 4);
        if (!byYear[y]) byYear[y] = emptyBucket();
        addRow(byYear[y], r);
      });
      const years = Object.keys(byYear).sort();
      const keep = new Set(getPeriodsToInclude(filters.specificPeriod, periodMode, years, pt));
      const entries = Object.entries(byYear).filter(([y]) => keep.has(y)).sort(([a], [b]) => a.localeCompare(b));
      rawData = entries.map(([y, d]) => { const r = resolve(d); const co = adsSpendByPeriod[y] ?? 0; const sl = d.sales?.sum ?? 0; const cg = d.cogs?.sum ?? 0; return { label: y, hasSqp: true, ...r, ad_cost: co, net_profit: sl - cg - co }; });
    }

    // Apply cumulative running-sum if periodType === 'cumulative' or 'peak'
    if ((filters.periodType === 'cumulative' || filters.periodType === 'peak') && rawData.length > 0) {
      const lyKeys = activeMeasures.map(m => `ly_${m}`);
      const cumulativeKeys = [...activeMeasures as unknown as string[], 'ad_cost', 'net_profit', ...lyKeys, 'ly_ad_cost', 'ly_net_profit'];
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
        return newRow;
      });
    }

    return rawData;
  }, [filteredWeekly, filteredMonthly, periodMode, activeMeasures, sqpWeeks, filters.specificPeriod, effectivePeriodTrend, adsSpendByPeriod, filters.periodType]);

  // Mini trend data for gauge + 3 cards — periods derived from trendData (header period) so x-axis matches
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
      });
      periodKeys.forEach(k => { if (!byWeek[k]) byWeek[k] = { sl: 0, cg: 0, co: 0 }; byWeek[k].co = adsSpendByPeriod[k] ?? 0; });
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
      });
      periodKeys.forEach(k => { if (!byMonth[k]) byMonth[k] = { sl: 0, cg: 0, co: 0 }; byMonth[k].co = adsSpendByPeriod[k] ?? 0; });
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
    const byYear: Record<string, { sl: number; cg: number; co: number }> = {};
    filteredMonthly.forEach(r => {
      const y = (r.month_start || '').slice(0, 4);
      if (!byYear[y]) byYear[y] = { sl: 0, cg: 0, co: 0 };
      byYear[y].sl += r.sales || 0;
      byYear[y].cg += r.cogs || 0;
    });
    periodKeys.forEach(k => { if (!byYear[k]) byYear[k] = { sl: 0, cg: 0, co: 0 }; byYear[k].co = adsSpendByPeriod[k] ?? 0; });
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
  }, [trendData, filteredWeekly, filteredMonthly, periodMode, adsSpendByPeriod]);

  // KPI sparkline data — all 5 metrics per period for bottom metric cards
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
        cur.or += w.orders || 0;
        cur.orgP += (w.organic_pct || 0) * (w.orders || 0);
      });
      periodKeys.forEach(k => { if (!byWeek[k]) byWeek[k] = { sl: 0, cg: 0, co: 0, or: 0, orgP: 0 }; byWeek[k].co = adsSpendByPeriod[k] ?? 0; });
      Object.keys(byWeek).forEach(k => {
        const c = byWeek[k];
        c.orgP = c.or ? c.orgP / c.or : 0;
      });
      // Build nearest-week LY lookup
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
      // LY for all metrics using nearest-week
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
        cur.or += r.orders || 0;
        cur.orgP += (r.organic_pct || 0) * (r.orders || 0);
      });
      periodKeys.forEach(k => { if (!byMonth[k]) byMonth[k] = { sl: 0, cg: 0, co: 0, or: 0, orgP: 0 }; byMonth[k].co = adsSpendByPeriod[k] ?? 0; });
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
    const byYear: Record<string, { sl: number; cg: number; co: number; or: number; orgP: number }> = {};
    filteredMonthly.forEach(r => {
      const y = (r.month_start || '').slice(0, 4);
      if (!byYear[y]) byYear[y] = { sl: 0, cg: 0, co: 0, or: 0, orgP: 0 };
      const cur = byYear[y];
      cur.sl += r.sales || 0;
      cur.cg += r.cogs || 0;
      cur.or += r.orders || 0;
      cur.orgP += (r.organic_pct || 0) * (r.orders || 0);
    });
    periodKeys.forEach(k => { if (!byYear[k]) byYear[k] = { sl: 0, cg: 0, co: 0, or: 0, orgP: 0 }; byYear[k].co = adsSpendByPeriod[k] ?? 0; });
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
  }, [trendData, filteredWeekly, filteredMonthly, periodMode, adsSpendByPeriod]);

  // Family-level trend table for selected period
  // In weeks mode, align to the same SQP week used for KPIs to avoid incomplete-week discrepancies
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
      periods = periodMode === 'weeks' ? allPeriods.filter(p => p === sp) : allPeriods.filter(p => p.startsWith(sp));
      if (!periods.length) periods = allPeriods.slice(-1);
    } else if (periodMode === 'year') {
      const years = [...new Set(allPeriods.map(p => p.slice(0, 4)))].sort();
      periods = allPeriods.filter(p => new Set(sliceByPeriod(years, null, periodsForTable)).has(p.slice(0, 4)));
    } else {
      periods = sliceByPeriod(allPeriods, null, periodsForTable);
    }

    if (!periods.length) return null;

    const families = filters.family
      ? [...new Set(srcAll.filter(r => famFromType(r.product_type) === filters.family).map(r => r.product_type))]
      : [...new Set(srcAll.map(r => r.product_type))].sort();

    let latest: string[];
    let prev: string[];
    if (filters.specificPeriod) {
      latest = periods;
      prev = [];
    } else if (periodMode === 'weeks') {
      // When Latest: use KPI week only (1 week). Previously could aggregate multiple weeks when kpiWeek not in periods.
      latest = kpiWeek ? [kpiWeek] : (periods.length ? [periods[periods.length - 1]] : []);
      prev = kpiPrevWeek ? [kpiPrevWeek] : [];
    } else if (periodMode === 'year') {
      // When Latest: split into cur year vs prev year (same as KPI logic). Previously lumped both into latest.
      const years = [...new Set(periods.map(p => p.slice(0, 4)))].sort();
      const keepYears = getPeriodsToInclude(null, 'year', years, periodsForTable);
      const curYear = keepYears[keepYears.length - 1] || '';
      const prvYear = keepYears.length >= 2 ? keepYears[keepYears.length - 2] : '';
      latest = curYear ? periods.filter(p => p.slice(0, 4) === curYear) : periods;
      prev = prvYear ? periods.filter(p => p.slice(0, 4) === prvYear) : [];
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


    const familyAds: Record<FamilyName, number> = { Lollibox: 0, LolliME: 0, Bottle: 0, Fresh: 0 };
    const familyAdsSales: Record<FamilyName, number> = { Lollibox: 0, LolliME: 0, Bottle: 0, Fresh: 0 };
    const familyAdsUnits: Record<FamilyName, number> = { Lollibox: 0, LolliME: 0, Bottle: 0, Fresh: 0 };
    (['Lollibox', 'LolliME', 'Bottle', 'Fresh'] as FamilyName[]).forEach(fn => {
      familyAds[fn] = latest.reduce((s, p) => s + (adsSpendByFamilyAndPeriod[`${fn}|${periodKey(p, periodMode)}`] || 0), 0);
      familyAdsSales[fn] = latest.reduce((s, p) => s + (adsSalesByFamilyAndPeriod[`${fn}|${periodKey(p, periodMode)}`] || 0), 0);
      familyAdsUnits[fn] = latest.reduce((s, p) => s + (adsUnitsByFamilyAndPeriod[`${fn}|${periodKey(p, periodMode)}`] || 0), 0);
    });
    const familySales: Record<FamilyName, number> = { Lollibox: 0, LolliME: 0, Bottle: 0, Fresh: 0 };
    families.forEach(f => {
      const fn = famFromType(f) as FamilyName | null;
      if (fn) familySales[fn] += aggRows(srcAll.filter(r => r.product_type === f && latest.includes(r[dateKey] || ''))).sales;
    });

    return families.map(fam => {
      const famRows = srcAll.filter(r => r.product_type === fam);
      const curRows = famRows.filter(r => latest.includes(r[dateKey] || ''));
      const prevRows = prev.length ? famRows.filter(r => prev.includes(r[dateKey] || '')) : [];
      const cur = aggRows(curRows);
      const prv = prevRows.length ? aggRows(prevRows) : null;
      const familyName = famFromType(fam) as FamilyName | null;
      const famAds = familyName ? familyAds[familyName] : 0;
      const famAdsSales = familyName ? familyAdsSales[familyName] : 0;
      const famAdsUnitsTotal = familyName ? familyAdsUnits[familyName] : 0;
      const famSales = familyName ? familySales[familyName] : 0;
      const curAds = familyName && famSales > 0 ? (cur.sales / famSales) * famAds : (familyName ? famAds : cur.ad_cost);
      const curAdsSales = familyName && famSales > 0 ? (cur.sales / famSales) * famAdsSales : (familyName ? famAdsSales : 0);
      const curAdsUnits = familyName && famSales > 0 ? (cur.sales / famSales) * famAdsUnitsTotal : (familyName ? famAdsUnitsTotal : 0);
      const curWithAds = { ...cur, ad_cost: curAds, ads_sales: curAdsSales, ads_units: Math.round(curAdsUnits), net_profit: cur.sales - cur.cogs - curAds };
      const net_roas = curWithAds.ad_cost ? (curWithAds.sales - curWithAds.cogs) / curWithAds.ad_cost : 0;
      const organic_pct = cur.orders > 0
        ? (curRows.reduce((s, r) => s + ((r.organic_pct || 0) * (r.orders || 0)), 0) / cur.orders)
        : 0;
      const organic_units = Math.round(cur.units * organic_pct / 100);
      const ad_orders = curWithAds.ads_units; // Use actual campaign-level ads units
      const sc = prv && prv.sales ? ((curWithAds.sales - prv.sales) / prv.sales) * 100 : 0;
      // Use units directly from the aggregated family row
      const units = cur.units;
      return { family: fam, ...curWithAds, units, net_roas, organic_pct, organic_units, ad_orders, clicks: curWithAds.clicks, sales_change: sc, sessions: curWithAds.sessions };
    });
  }, [data.weekly_trends, data.monthly_trends, data.weekly_trends_by_asin, data.monthly_trends_by_asin, data.products, periodMode, kpiWeek, kpiPrevWeek, filters.family, filters.product, filters.specificPeriod, filters.seasonality, pk, adsSpendByFamilyAndPeriod, adsSalesByFamilyAndPeriod, adsUnitsByFamilyAndPeriod]);

  // Variation-level data from SQP for expandable family rows (same period as familyPeriodData)
  const variationByFamily = useMemo(() => {
    const sqp = data.sqp_weekly || [];
    if (!kpiWeek || !sqp.length) return { Lollibox: [], LolliME: [], Bottle: [], Fresh: [] } as Record<FamilyName, { asin: string; name: string; orders: number; clicks: number; adsOrders: number }[]>;
    const matchWeek = (w: string) => {
      if (periodMode === 'weeks') return w === kpiWeek;
      if (periodMode === 'month') return w.slice(0, 7) === kpiWeek;
      return w.slice(0, 4) === kpiWeek;
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
    const result: Record<FamilyName, { asin: string; name: string; orders: number; clicks: number; adsOrders: number }[]> = { Lollibox: [], LolliME: [], Bottle: [], Fresh: [] };
    (Object.keys(byFamily) as FamilyName[]).forEach(fam => {
      result[fam] = Object.values(byFamily[fam]).sort((a, b) => b.orders - a.orders);
    });
    return result;
  }, [data.sqp_weekly, kpiWeek, periodMode, filters.product]);

  // Per-family Changes vs Prev (full deltas + status)
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
      if (periodMode === 'month') return v.slice(0, 7) === kpiWeek;
      return v.slice(0, 4) === kpiWeek;
    };
    const matchPrev = (r: TrendRow) => {
      const v = r[dateKey] || '';
      if (periodMode === 'weeks') return v === kpiPrevWeek;
      if (periodMode === 'month') return v.slice(0, 7) === kpiPrevWeek;
      return v.slice(0, 4) === kpiPrevWeek;
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
      const roas = curAds ? curNp / curAds : 0;
      const prevRoas = prvAds ? prvNp / prvAds : 0;
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

  // Per-variation P&L for current period (from trends_by_asin) — ad_cost overridden from ads_7d (allocated by sales ratio)
  const variationPnlByFamily = useMemo(() => {
    if (!kpiWeek) return { Lollibox: [], LolliME: [], Bottle: [], Fresh: [] } as Record<FamilyName, { asin: string; product_short_name: string; sales: number; cogs: number; ad_cost: number; net_profit: number; net_roas: number; orders: number; units: number; clicks: number; sessions: number; organic_pct: number; organic_units: number; ad_orders: number; ads_sales: number; ads_units: number }[]>;
    type Row = { product_type: string; asin: string; product_short_name: string; week_start?: string; month_start?: string; sales: number; ad_cost: number; cogs: number; net_profit: number; orders: number; units?: number; clicks?: number; sessions?: number; organic_pct?: number };
    const src = periodMode === 'weeks' ? (data.weekly_trends_by_asin || []) : (data.monthly_trends_by_asin || []);
    const dateKey = periodMode === 'weeks' ? 'week_start' : 'month_start';
    const matchCur = (r: Row) => {
      const v = r[dateKey] || '';
      if (periodMode === 'weeks') return v === kpiWeek;
      if (periodMode === 'month') return v.slice(0, 7) === kpiWeek;
      return v.slice(0, 4) === kpiWeek;
    };
    const result: Record<FamilyName, { asin: string; product_short_name: string; sales: number; cogs: number; ad_cost: number; net_profit: number; net_roas: number; orders: number; units: number; clicks: number; sessions: number; organic_pct: number; organic_units: number; ad_orders: number; ads_sales: number; ads_units: number }[]> = { Lollibox: [], LolliME: [], Bottle: [], Fresh: [] };
    src.forEach((r: Row) => {
      const fam = famFromType(r.product_type) as FamilyName | null;
      if (!fam || (filters.family && fam !== filters.family) || (filters.product && r.asin !== filters.product) || !matchCur(r)) return;
      const cogsVal = r.cogs || 0;
      const units = r.units || 0;
      result[fam].push({
        asin: r.asin,

        product_short_name: r.product_short_name || r.asin,
        sales: r.sales,
        cogs: cogsVal,
        ad_cost: 0,
        net_profit: r.net_profit,
        net_roas: 0,
        orders: r.orders || 0,
        units,
        clicks: r.clicks || 0,
        sessions: r.sessions || 0,
        organic_pct: r.organic_pct ?? 0,
        organic_units: 0,
        ad_orders: 0,
        ads_sales: 0,
        ads_units: 0,
      });
    });
    (Object.keys(result) as FamilyName[]).forEach(fam => {
      const rows = result[fam];
      rows.forEach(v => {
        // Direct product-level ads lookup — no more pro-rating!
        const productName = v.product_short_name;
        const periodKey_ = kpiWeek || '';
        v.ad_cost = adsDataByProductAndPeriod.spend[`${productName}|${periodKey_}`] || 0;
        v.ads_sales = adsDataByProductAndPeriod.sales[`${productName}|${periodKey_}`] || 0;
        v.ads_units = Math.round(adsDataByProductAndPeriod.units[`${productName}|${periodKey_}`] || 0);
        v.net_profit = v.sales - v.cogs - v.ad_cost;
        v.net_roas = v.ad_cost ? (v.sales - v.cogs) / v.ad_cost : 0;
        v.organic_units = Math.round((v.units || 0) * (v.organic_pct || 0) / 100);
        v.ad_orders = v.ads_units; // Use actual campaign-level ads orders, not derived estimate
      });
      result[fam].sort((a, b) => b.sales - a.sales);
    });
    return result;
  }, [data.weekly_trends_by_asin, data.monthly_trends_by_asin, data.products, periodMode, kpiWeek, filters.family, filters.product, adsDataByProductAndPeriod]);

  // Flat lookup: ASIN -> P&L (for enriching SQP variations when variationPnlByFamily is empty for a family)
  const pnlByAsin = useMemo(() => {
    const map = new Map<string, { sales: number; cogs: number; ad_cost: number; net_profit: number; net_roas: number; orders: number; units: number; clicks: number; sessions: number; organic_pct: number; organic_units: number; ad_orders: number; ads_sales: number; ads_units: number }>();
    (Object.values(variationPnlByFamily) as { asin: string; sales: number; cogs: number; ad_cost: number; net_profit: number; net_roas: number; orders: number; units: number; clicks: number; sessions: number; organic_pct: number; organic_units: number; ad_orders: number; ads_sales: number; ads_units: number }[][]).flat().forEach(v => {
      if (v.asin) map.set(v.asin, { sales: v.sales, cogs: v.cogs, ad_cost: v.ad_cost, net_profit: v.net_profit, net_roas: v.net_roas, orders: v.orders, units: v.units ?? 0, clicks: v.clicks, sessions: v.sessions ?? 0, organic_pct: v.organic_pct, organic_units: v.organic_units ?? 0, ad_orders: v.ad_orders ?? 0, ads_sales: v.ads_sales ?? 0, ads_units: v.ads_units ?? 0 });
    });
    return map;
  }, [variationPnlByFamily]);

  // Product lookup: ASIN -> per-unit costs (for FBA columns in variation rows)
  const productByAsin = useMemo(() => {
    const map = new Map<string, { pick_pack_fee: number; referral_fee: number; cogs: number; shipping_cost: number }>();
    (data.products || []).forEach(p => {
      if (p.asin) map.set(p.asin, { pick_pack_fee: p.pick_pack_fee ?? 0, referral_fee: p.referral_fee ?? 0, cogs: p.cogs ?? 0, shipping_cost: p.shipping_cost ?? 0 });
    });
    return map;
  }, [data.products]);

  // Per-variation Changes vs Prev from trends_by_asin
  const changesByVariation = useMemo(() => {
    if (!kpiWeek || !kpiPrevWeek) return { Lollibox: [], LolliME: [], Bottle: [], Fresh: [] } as Record<FamilyName, { asin: string; product_short_name: string; sd: number; cd: number; pd: number; roasDelta: number; orgDelta: number; status: string; prevSales: number; prevAdCost: number; prevNetProfit: number }[]>;
    type Row = { product_type: string; asin: string; product_short_name: string; week_start?: string; month_start?: string; sales: number; ad_cost: number; net_profit: number; orders: number; organic_pct?: number };
    const src = periodMode === 'weeks' ? (data.weekly_trends_by_asin || []) : (data.monthly_trends_by_asin || []);
    const dateKey = periodMode === 'weeks' ? 'week_start' : 'month_start';

    const matchCur = (r: Row) => {
      const v = r[dateKey] || '';
      if (periodMode === 'weeks') return v === kpiWeek;
      if (periodMode === 'month') return v.slice(0, 7) === kpiWeek;
      return v.slice(0, 4) === kpiWeek;
    };
    const matchPrev = (r: Row) => {
      const v = r[dateKey] || '';
      if (periodMode === 'weeks') return v === kpiPrevWeek;
      if (periodMode === 'month') return v.slice(0, 7) === kpiPrevWeek;
      return v.slice(0, 4) === kpiPrevWeek;
    };

    const byAsin: Record<string, { cur: Row; prev: Row }> = {};
    src.forEach(r => {
      const fam = famFromType(r.product_type) as FamilyName | null;
      if (!fam || (filters.family && fam !== filters.family) || (filters.product && r.asin !== filters.product)) return;
      const key = `${r.product_type}|${r.asin}`;
      if (matchCur(r)) {
        if (!byAsin[key]) byAsin[key] = { cur: r as Row, prev: null! };
        else byAsin[key].cur = r as Row;
      }
      if (matchPrev(r)) {
        if (!byAsin[key]) byAsin[key] = { cur: null!, prev: r as Row };
        else byAsin[key].prev = r as Row;
      }
    });

    const result: Record<FamilyName, { asin: string; product_short_name: string; sd: number; cd: number; pd: number; roasDelta: number; orgDelta: number; status: string; prevSales: number; prevAdCost: number; prevNetProfit: number }[]> = { Lollibox: [], LolliME: [], Bottle: [], Fresh: [] };

    Object.entries(byAsin).forEach(([key, { cur, prev }]) => {
      if (!cur || !prev) return;
      const [, asin] = key.split('|');
      const fam = famFromType(cur.product_type) as FamilyName | null;
      if (!fam) return;

      const sd = prev.sales ? ((cur.sales - prev.sales) / prev.sales) * 100 : 0;
      const cd = prev.ad_cost ? ((cur.ad_cost - prev.ad_cost) / prev.ad_cost) * 100 : 0;
      const pd = prev.net_profit ? ((cur.net_profit - prev.net_profit) / Math.abs(prev.net_profit)) * 100 : 0;
      const roas = cur.ad_cost ? cur.net_profit / cur.ad_cost : 0;
      const prevRoas = prev.ad_cost ? prev.net_profit / prev.ad_cost : 0;
      const roasDelta = prevRoas ? ((roas - prevRoas) / Math.abs(prevRoas)) * 100 : 0;
      const prevOrg = prev.organic_pct ?? 0;
      const orgDelta = prevOrg ? (((cur.organic_pct ?? 0) - prevOrg) / Math.abs(prevOrg)) * 100 : 0;

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

  // Peak-aligned 7-day YoY or same-period LY fallback. Zero ads spend for rows in ads gap.
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

        // Use actual LY holiday dates if available
        const holidays = data.holidays || [];
        const lyHoliday = holidays
          .filter(h => h.holiday_name === pk.holiday_name && h.holiday_date < pk.holiday_date)
          .sort((a, b) => b.holiday_date.localeCompare(a.holiday_date))[0];
        let startLy: string, endLy: string;
        if (lyHoliday?.pre_season_start) {
          startLy = addDays(lyHoliday.pre_season_start, -(daysUntil + 7) + (new Date(pk.peak_start + 'T00:00:00').getTime() - new Date(pk.pre_peak_start || pk.peak_start + 'T00:00:00').getTime()) / 86400000);
          // Align same offset from LY peak start
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
    // Fallback: same period last year
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

  // Check if current period has complete performance data
  const perfMaxDate = data._meta?.data_freshness?.performance_max_date || '';
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

  // Auto-generated narrative headline
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

  // Trend chart annotations from change_log and upcoming holidays
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

  // Sales share % for family table
  const totalFamilySales = useMemo(() => {
    return (familyPeriodData || []).reduce((s, r) => s + (r.sales || 0), 0);
  }, [familyPeriodData]);

  const eT = effectiveTotals;
  const netRoas = eT.co > 0 ? (eT.sl - eT.cg - eT.co) / eT.co : 0;
  // PageSummaryBar intentionally omitted on HOME — DashboardSummary sparkline cards
  // already display the same KPIs with additional sparkline context.
  usePageSummary({ title: 'Home', items: [] });

  if (!effectiveTotals.sl && !effectiveTotals.co && !effectiveTotals.or) return <Empty icon="📊" message="No summary data" hint="Summary data will appear once your Amazon performance data is synced." />;

  const prevLabel = periodMode === 'weeks' && kpiPrevWeek ? weekRangeLabel(kpiPrevWeek) : kpiPrevWeek || '';

  // Peak stage: only actual PEAK (Pre Peak / Pre Peak Boost are not considered peak)
  const isPeakStage = pk?.current_stage === 'PEAK';

  // Scores 0-10 for the 3 cards — suppress WoW when period data is incomplete
  const score1 = periodIncomplete ? 0 : scoreFromRoas(roas);
  const score2 = periodIncomplete ? null : (isPeakStage ? null : (effectivePrevTotals ? scoreFromProfitDelta(pd) : null));
  const score3 = peakYoYData && !periodIncomplete ? scoreFromProfitDelta(peakYoYData.profitYoy) : 0;

  const currentSeasonality = pk && kpiWeek ? getSeasonality(kpiWeek, pk) : null;
  const seasonalityLabel = currentSeasonality ? { PRE_PEAK: 'Pre Peak (2-4 wk)', PRE_PEAK_BOOST: 'Pre Peak Boost (1-2 wk)', PEAK: 'Peak', OFF_SEASON: 'Off Season' }[currentSeasonality] : null;

  const trendLabels = trendData.map(d => d.label);
  const card2Range = periodMode === 'weeks' && kpiWeek && kpiPrevWeek
    ? `${weekRangeLabel(kpiWeek)} vs ${weekRangeLabel(kpiPrevWeek)}`
    : prevLabel ? `Current vs ${prevLabel}` : rangeStr || '--';

  // eT and netRoas already computed above (before early return)

  return (
    <div className="animate-in">
      {periodIncomplete && (
        <div className="mb-3 px-3 py-2 rounded-lg border border-amber-500/30 bg-amber-500/5 text-[11px] text-amber-400 font-mono">
          Perf data through {perfMaxDate} — current period not complete, scores/comparisons suppressed
        </div>
      )}
      {/* Headline summary — above measure buttons */}
      {headline && (
        <div className="font-mono text-[14px] font-semibold text-white/60 truncate mb-1 px-1">{headline}</div>
      )}

      {/* Measure selector buttons — right aligned */}
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

      {/* Hero: KPI cards + Bar Trend Chart */}
      <div className="mb-1 h-[253px] min-h-[200px]">
        <DashboardSummary
        rangeStr={rangeStr || '--'}
        pk={pk}
        seasonalityLabel={seasonalityLabel}
        latestPeriodLabel={latestPeriodLabel(kpiWeek, periodMode)}
        trendLabels={trendLabels}
        metrics={[
          { label: 'SALES', value: fM(effectiveTotals.sl), prevValue: fM(effectivePrevTotals?.sl || 0), lyValue: peakYoYData ? fM(peakYoYData.salesLy) : undefined, delta: `${sd >= 0 ? '+' : ''}${sd.toFixed(1)}%`, positive: sd >= 0, warn: cd > sd ? 'Cost outpacing sales' : undefined, sub: sd > cd ? 'outgrowing cost' : '' },
          { label: 'ADS SPEND', value: fM(effectiveTotals.co), prevValue: fM(effectivePrevTotals?.co || 0), delta: `${cd >= 0 ? '+' : ''}${cd.toFixed(1)}%`, positive: cd <= 0, sub: `${fClk(effectiveTotals.cl)} clicks · ${effectiveTotals.ss.toLocaleString()} sess` },
          { label: 'NET PROFIT', value: fM(effectiveTotals.np), prevValue: fM(effectivePrevTotals?.np || 0), lyValue: peakYoYData ? fM(peakYoYData.npLy) : undefined, delta: `${pd >= 0 ? '+' : ''}${pd.toFixed(1)}%`, positive: pd >= 0, sub: `COGS ${fM(effectiveTotals.cg)} · margin ${fP(margin)}` },
          { label: 'NET ROAS', value: fR(roas), prevValue: fR(prevRoas), lyValue: peakYoYData && peakYoYData.npLy && peakYoYData.salesLy ? fR(peakYoYData.salesLy > 0 ? peakYoYData.npLy / peakYoYData.salesLy : 0) : undefined, delta: `${roasDelta >= 0 ? '+' : ''}${roasDelta.toFixed(1)}%`, positive: roasDelta >= 0, warn: roas < 1 && roas > 0 ? 'Below break-even' : undefined, sub: roas >= 1 ? 'above break-even' : '' },
          { label: 'ORGANIC %', value: fP(orgP), prevValue: fP(prevOrgP), delta: `${orgDelta >= 0 ? '+' : ''}${orgDelta.toFixed(1)}%`, positive: orgDelta >= 0, sub: `${fOrd(effectiveTotals.or)} total · ${fOrd(orgOrd)} organic` },
        ]}
        kpiSparklineData={kpiSparklineData}
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
                  <ComposedChart data={trendData} barCategoryGap="20%" margin={{ top: 18, right: 0, bottom: 0, left: 0 }}>
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
                    {/* LY dotted line — only when single measure selected */}
                    {selectedMeasures.size === 1 && activeMeasures.map(mKey => {
                      const meta = MEASURE_META[mKey];
                      const lyKey = `ly_${mKey}`;
                      const hasLyData = trendData.some((d: any) => d[lyKey] != null && d[lyKey] !== 0);
                      if (!hasLyData) return null;
                      return (
                        <Line key={`ly_${mKey}`} yAxisId="left" type="monotone" dataKey={lyKey}
                          stroke={meta.color} strokeWidth={1.5} strokeDasharray="6 3" strokeOpacity={0.4}
                          dot={false} activeDot={{ r: 3, strokeWidth: 1, fill: meta.color, fillOpacity: 0.6 }}
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

      {/* Family Table — reflects selected period */}
      <Section
        title="Per Product Family"
        count={periodLabel ? latestPeriodLabel(kpiWeek, periodMode) : undefined}
        headerRight={
          <MeasureSelector tableId="home_family" measures={FAMILY_TABLE_COLUMNS} selected={familyCols} onSelectedChange={setFamilyCols} />
        }
      >
        {familyPeriodData ? (
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
                {famSort.sorted(familyPeriodData).map((r, i) => {
                  const f = famFromType(r.family) as FamilyName | null;
                  const isExpanded = f && expandedFamily === f;
                  const varsPnl = f ? (variationPnlByFamily[f] || []) : [];
                  const varsSqp = f ? (variationByFamily[f] || []) : [];
                  const vars = varsPnl.length > 0
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
                        ads_sales: <td key="ads_sales" className="px-3 py-2 text-right font-mono text-[11px]">{hasPnl ? fM(v.ads_sales ?? 0) : '—'}</td>,
                        ads_units: <td key="ads_units" className="px-3 py-2 text-right font-mono text-[11px]">{hasPnl ? fOrd(v.ads_units ?? 0) : '—'}</td>,
                        net_profit: <td key="net_profit" className={`px-3 py-2 text-right font-mono text-[11px] ${hasPnl ? (v.net_profit > 0 ? 'text-emerald-400 font-bold' : 'text-red-400 font-bold') : 'text-faint'}`}>{hasPnl ? fM(v.net_profit) : '—'}</td>,
                        np_per_unit: <td key="np_per_unit" className={`px-3 py-2 text-right font-mono text-[11px] ${hasPnl && (v.units ?? 0) > 0 ? (v.net_profit / v.units > 0 ? 'text-emerald-400' : 'text-red-400') : 'text-faint'}`}>{hasPnl && (v.units ?? 0) > 0 ? fM(v.net_profit / v.units) : '—'}</td>,
                        net_roas: <td key="net_roas" className="px-3 py-2 text-right">{hasPnl ? <RoasBadge value={v.net_roas} /> : <span className="text-faint">—</span>}</td>,
                        tacos: <td key="tacos" className={`px-3 py-2 text-right font-mono text-[11px] ${hasPnl && v.sales > 0 ? ((v.ad_cost / v.sales) * 100 > 30 ? 'text-red-400' : (v.ad_cost / v.sales) * 100 > 15 ? 'text-amber-400' : 'text-emerald-400') : 'text-faint'}`}>{hasPnl && v.sales > 0 ? fP((v.ad_cost / v.sales) * 100) : '—'}</td>,
                        ads_roas: (() => { const ar = v.ad_cost > 0 ? (v.ads_sales ?? 0) / v.ad_cost : 0; return <td key="ads_roas" className="px-3 py-2 text-right">{hasPnl && ar > 0 ? <RoasBadge value={ar} /> : <span className="text-faint">—</span>}</td>; })(),
                        ad_orders: <td key="ad_orders" className="px-3 py-2 text-right font-mono text-[11px]">{hasPnl ? fOrd(v.ad_orders ?? 0) : '—'}</td>,
                        units: <td key="units" className="px-3 py-2 text-right font-mono text-[11px]">{hasPnl ? fOrd(v.units ?? 0) : '—'}</td>,
                        orders: <td key="orders" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{fOrd(v.orders)}</td>,
                        organic_units: <td key="organic_units" className="px-3 py-2 text-right font-mono text-[11px]">{hasPnl ? fOrd(v.organic_units ?? 0) : '—'}</td>,
                        clicks: <td key="clicks" className="px-3 py-2 text-right font-mono text-[11px]">{fClk(v.clicks)}</td>,
                        sessions: <td key="sessions" className="px-3 py-2 text-right font-mono text-[11px]">{(v.sessions ?? 0) > 0 ? (v.sessions ?? 0).toLocaleString() : '—'}</td>,
                        organic_pct: <td key="organic_pct" className="px-3 py-2 text-right font-mono text-[11px]">{hasPnl ? fP(v.organic_pct) : '—'}</td>,
                        sales_change: <td key="sales_change" className="px-3 py-2">{vc ? <ChangesSummaryCell data={vc} /> : <span className="text-faint">—</span>}</td>,
                        fba_pick_pack: (() => { const prod = v.asin ? productByAsin.get(v.asin) : undefined; return <td key="fba_pick_pack" className="px-3 py-2 text-right font-mono text-[11px]">{prod ? `$${prod.pick_pack_fee.toFixed(2)}` : '—'}</td>; })(),
                        fba_referral: (() => { const prod = v.asin ? productByAsin.get(v.asin) : undefined; return <td key="fba_referral" className="px-3 py-2 text-right font-mono text-[11px]">{prod ? `$${prod.referral_fee.toFixed(2)}` : '—'}</td>; })(),
                        cost_of_goods: (() => { const prod = v.asin ? productByAsin.get(v.asin) : undefined; return <td key="cost_of_goods" className="px-3 py-2 text-right font-mono text-[11px]">{prod ? `$${prod.cogs.toFixed(2)}` : '—'}</td>; })(),
                        shipping_cost_per_unit: (() => { const prod = v.asin ? productByAsin.get(v.asin) : undefined; return <td key="shipping_cost_per_unit" className="px-3 py-2 text-right font-mono text-[11px]">{prod ? `$${prod.shipping_cost.toFixed(2)}` : '—'}</td>; })(),
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
                      ad_cost: <td key="ad_cost" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{fM(r.ad_cost)}</td>,
                      ads_sales: <td key="ads_sales" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{fM(r.ads_sales || 0)}</td>,
                      ads_units: <td key="ads_units" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{fOrd(r.ads_units || 0)}</td>,
                      net_profit: <td key="net_profit" className={`px-3 py-2 text-right font-mono text-[11px] font-bold ${r.net_profit > 0 ? 'text-emerald-400' : 'text-red-400'}`}>{fM(r.net_profit)}</td>,
                      np_per_unit: <td key="np_per_unit" className={`px-3 py-2 text-right font-mono text-[11px] font-bold ${(r.units ?? 0) > 0 ? (r.net_profit / r.units > 0 ? 'text-emerald-400' : 'text-red-400') : 'text-faint'}`}>{(r.units ?? 0) > 0 ? fM(r.net_profit / r.units) : '—'}</td>,
                      net_roas: <td key="net_roas" className="px-3 py-2 text-right"><RoasBadge value={r.net_roas} /></td>,
                      tacos: <td key="tacos" className={`px-3 py-2 text-right font-mono text-[11px] font-bold ${r.sales > 0 ? ((r.ad_cost / r.sales) * 100 > 30 ? 'text-red-400' : (r.ad_cost / r.sales) * 100 > 15 ? 'text-amber-400' : 'text-emerald-400') : 'text-faint'}`}>{r.sales > 0 ? fP((r.ad_cost / r.sales) * 100) : '—'}</td>,
                      ads_roas: (() => { const ar = r.ad_cost > 0 ? (r.ads_sales || 0) / r.ad_cost : 0; return <td key="ads_roas" className="px-3 py-2 text-right">{ar > 0 ? <RoasBadge value={ar} /> : <span className="text-faint">—</span>}</td>; })(),
                      ad_orders: <td key="ad_orders" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{fOrd(r.ad_orders ?? 0)}</td>,
                      units: <td key="units" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{fOrd(r.units ?? 0)}</td>,
                      orders: <td key="orders" className="px-3 py-2 text-right">{fOrd(r.orders)}</td>,
                      organic_units: <td key="organic_units" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{fOrd(r.organic_units ?? 0)}</td>,
                      clicks: <td key="clicks" className="px-3 py-2 text-right">{fClk(r.clicks)}</td>,
                      sessions: <td key="sessions" className="px-3 py-2 text-right font-mono text-[11px]">{(r.sessions ?? 0) > 0 ? (r.sessions ?? 0).toLocaleString() : '—'}</td>,
                      organic_pct: <td key="organic_pct" className="px-3 py-2 text-right">{fP(r.organic_pct)}</td>,
                      sales_change: <td key="sales_change" className="px-3 py-2"><ChangesSummaryCell data={famChanges ?? { status: r.sales_change > 0 ? 'Sales up' : r.sales_change < 0 ? 'Sales down' : 'Flat vs previous period', sd: r.sales_change ?? 0, cd: 0, pd: 0, roasDelta: 0, orgDelta: 0 }} positiveCount={totalCount > 0 ? positiveCount : undefined} totalCount={totalCount > 0 ? totalCount : undefined} /></td>,
                      fba_pick_pack: <td key="fba_pick_pack" className="px-3 py-2 text-right font-mono text-[11px] text-faint">—</td>,
                      fba_referral: <td key="fba_referral" className="px-3 py-2 text-right font-mono text-[11px] text-faint">—</td>,
                      cost_of_goods: <td key="cost_of_goods" className="px-3 py-2 text-right font-mono text-[11px] text-faint">—</td>,
                      shipping_cost_per_unit: <td key="shipping_cost_per_unit" className="px-3 py-2 text-right font-mono text-[11px] text-faint">—</td>,
                    };
                    return cells[key] ?? <td key={key} className="px-3 py-2">—</td>;
                  };
                  return (
                    <React.Fragment key={i}>
                      <tr onClick={() => f && setExpandedFamily(isExpanded ? null : f)} className={`border-b border-border-faint last:border-b-0 hover:bg-white/[.02] cursor-pointer transition-colors ${r.net_profit > 0 ? 'profit-positive' : 'profit-negative'}`}>
                        {visibleFamilyCols.map(c => renderCell(c.id, false))}
                      </tr>
                      {isExpanded && vars.map((v, j) => (
                        <tr key={`${i}-${j}`} onClick={(e) => { e.stopPropagation(); if (f) { setFilter('product', v.asin || null); onNav('sqp', f); } }} className="border-b border-border-faint hover:bg-white/[.02] cursor-pointer bg-inset">
                          {visibleFamilyCols.map(c => c.id === 'family' ? <td key={c.id} className="px-3 py-2 pl-8 font-medium text-subtle"><span className="text-zinc-500 mr-1">↳</span>{v.product_short_name || v.asin}</td> : renderCell(c.id, true, v))}
                        </tr>
                      ))}
                    </React.Fragment>
                  );
                })}
                {/* Total row */}
                {familyPeriodData && familyPeriodData.length > 1 && (() => {
                  const tot = familyPeriodData.reduce((acc, r) => ({
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
                  // Use effectiveTotals.co for consistency with Hero/KPI cards
                  tot.ad_cost = effectiveTotals.co;
                  tot.net_profit = tot.sales - tot.cogs - tot.ad_cost;
                  const net_roas = tot.ad_cost ? (tot.sales - tot.cogs) / tot.ad_cost : 0;
                  const organic_pct = tot.units > 0 ? (tot.organic_units / tot.units) * 100 : 0;
                  const totalCells: Record<string, React.ReactNode> = {
                    family: <td key="family" className="px-3 py-2 font-bold">Total</td>,
                    sales: <td key="sales" className="px-3 py-2 text-right font-mono text-[11px] font-bold">{fM(tot.sales)}</td>,
                    share_pct: <td key="share_pct" className="px-3 py-2 text-right font-mono text-[11px] font-bold">100%</td>,
                    cogs: <td key="cogs" className="px-3 py-2 text-right font-mono text-[11px] font-bold">{fM(tot.cogs)}</td>,
                    ad_cost: <td key="ad_cost" className="px-3 py-2 text-right font-mono text-[11px] font-bold">{fM(tot.ad_cost)}</td>,
                    ads_sales: <td key="ads_sales" className="px-3 py-2 text-right font-mono text-[11px] font-bold">{fM(tot.ads_sales)}</td>,
                    ads_units: <td key="ads_units" className="px-3 py-2 text-right font-mono text-[11px] font-bold">{fOrd(tot.ads_units)}</td>,
                    net_profit: <td key="net_profit" className={`px-3 py-2 text-right font-mono text-[11px] font-bold ${tot.net_profit > 0 ? 'text-emerald-400' : 'text-red-400'}`}>{fM(tot.net_profit)}</td>,
                    np_per_unit: <td key="np_per_unit" className={`px-3 py-2 text-right font-mono text-[11px] font-bold ${tot.units > 0 ? (tot.net_profit / tot.units > 0 ? 'text-emerald-400' : 'text-red-400') : 'text-faint'}`}>{tot.units > 0 ? fM(tot.net_profit / tot.units) : '—'}</td>,
                    net_roas: <td key="net_roas" className="px-3 py-2 text-right"><RoasBadge value={net_roas} /></td>,
                    tacos: <td key="tacos" className={`px-3 py-2 text-right font-mono text-[11px] font-bold ${tot.sales > 0 ? ((tot.ad_cost / tot.sales) * 100 > 30 ? 'text-red-400' : (tot.ad_cost / tot.sales) * 100 > 15 ? 'text-amber-400' : 'text-emerald-400') : 'text-faint'}`}>{tot.sales > 0 ? fP((tot.ad_cost / tot.sales) * 100) : '—'}</td>,
                    ads_roas: (() => { const ar = tot.ad_cost > 0 ? tot.ads_sales / tot.ad_cost : 0; return <td key="ads_roas" className="px-3 py-2 text-right">{ar > 0 ? <RoasBadge value={ar} /> : <span className="text-faint">—</span>}</td>; })(),
                    ad_orders: <td key="ad_orders" className="px-3 py-2 text-right font-mono text-[11px] font-bold">{fOrd(tot.ad_orders)}</td>,
                    units: <td key="units" className="px-3 py-2 text-right font-mono text-[11px] font-bold">{fOrd(tot.units)}</td>,
                    orders: <td key="orders" className="px-3 py-2 text-right font-mono text-[11px] font-bold">{fOrd(tot.orders)}</td>,
                    organic_units: <td key="organic_units" className="px-3 py-2 text-right font-mono text-[11px] font-bold">{fOrd(tot.organic_units)}</td>,
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
      <Section title="Actions To Do" count={acts.length > 0 ? `${acts.length} pending` : undefined} filterItems={formatSectionFilters(filters)}>
        {!acts.length ? <Empty icon="✓" message="No pending actions" /> : (
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
