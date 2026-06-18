import { useState, useEffect, useMemo, Fragment, type ReactNode } from 'react';
import { ComposedChart, Bar, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, LabelList } from 'recharts';
import { SeasonalReferenceLines, getXLabels } from '../components/SeasonalReferenceLines';
import type { DashboardData, Ads7dRow, SqpWeeklyRow, KeywordMapRow, HolidayRow } from '../types';
import { Card } from '../components/Card';
import { Section } from '../components/Section';
import { Empty } from '../components/Empty';
import { Th, SortTh, useSort, Tip, MEASURE_TIPS } from '../components/Tooltip';
import { MeasureSelector, useMeasureSelection, type MeasureDef } from '../components/MeasureSelector';
import { Badge, RoasBadge } from '../components/Badge';
import { fM, fP, fOrd, fClk, fR, fCpc, periodKey, getPeriodsToInclude, weekRangeLabel, weekRangeLabelCapped, addDays, ACTION_META, getCurrentWeekStart, getWeekStart } from '../utils';
import { useFilters } from '../hooks/useFilters';
import { formatSectionFilters } from '../utils/filterUtils';
import { ChevronRight, ChevronDown, TrendingDown, AlertTriangle, Zap, GripVertical } from 'lucide-react';
import { usePageSummary } from '../components/PageSummaryBar';

const HIERARCHY_OPTIONS = [
  { id: 'portfolio', label: 'Portfolio' },
  { id: 'campaign', label: 'Campaign' },
  { id: 'search_term', label: 'Search term' },
  { id: 'family', label: 'Family' },
  { id: 'collection', label: 'Collection' },
  { id: 'product', label: 'Product' },
  { id: 'day', label: 'Day' },
  { id: 'week', label: 'Week' },
  { id: 'month', label: 'Month' },
] as const;

const DEFAULT_HIERARCHY: (typeof HIERARCHY_OPTIONS)[number]['id'][] = ['portfolio', 'campaign', 'search_term'];

export function AdsPerformancePage({ data }: { data: DashboardData }) {
  const { filters } = useFilters();
  const perfMaxDate = data._meta?.data_freshness?.performance_max_date || '';
  const [campaignHierarchy, setCampaignHierarchy] = useState<(typeof HIERARCHY_OPTIONS)[number]['id'][]>(DEFAULT_HIERARCHY);
  const [expandedKeys, setExpandedKeys] = useState<Set<string>>(new Set());
  const [drainerMinSpend, setDrainerMinSpend] = useState(5);
  const [includeCurrentWeek, setIncludeCurrentWeek] = useState(false);
  const [bestMinSpend, setBestMinSpend] = useState(3);
  const [campMinClicks, setCampMinClicks] = useState<number | null>(null);
  const campSort = useSort('spend');
  const ADS_TERMS_COLUMNS: MeasureDef[] = [
    { id: 'search_term', label: 'Search Term', group: 'Info' },
    { id: 'campaign_name', label: 'Campaign', group: 'Info' },
    { id: 'spend', label: 'Ads Spend', tip: MEASURE_TIPS.spend, group: 'Ads' },
    { id: 'orders', label: 'Ads Orders', tip: MEASURE_TIPS.orders, group: 'Ads' },
    { id: 'clicks', label: 'Ads Clicks', tip: MEASURE_TIPS.clicks, group: 'Ads' },
    { id: 'impressions', label: 'Ads Impr', tip: MEASURE_TIPS.impressions, group: 'Ads' },
    { id: 'conv_rate', label: 'Ads Conv%', tip: MEASURE_TIPS.conv_rate, group: 'Ads' },
    { id: 'cpc', label: 'Ads CPC', group: 'Ads' },
    { id: 'gross_roas', label: 'Ads ROAS', tip: MEASURE_TIPS.ads_roas, group: 'Ads' },
    { id: 'roas', label: 'Net ROAS', tip: MEASURE_TIPS.net_roas, group: 'Ads' },
    { id: 'sqp_volume', label: 'SQP Vol (4w)', tip: 'Amazon search volume last 4 weeks (SQP)', group: 'SQP' },
    { id: 'sqp_clicks', label: 'SQP Clicks', tip: 'SQP total clicks (last 4w)', group: 'SQP' },
    { id: 'sqp_cart_adds', label: 'SQP Cart Adds', tip: 'SQP cart adds (last 4w)', group: 'SQP' },
    { id: 'sqp_orders', label: 'SQP Orders', tip: 'Total orders from SQP (last 4w)', group: 'SQP' },
    { id: 'sqp_organic_units', label: 'SQP Organic Orders', tip: 'Organic orders = SQP Orders − SQP Ads Orders (last 4w)', group: 'SQP' },
    { id: 'sqp_organic_pct', label: 'SQP Organic %', tip: 'Organic orders / SQP orders (last 4w)', group: 'SQP' },
    { id: 'sqp_show_rate', label: 'SQP Show%', tip: 'SQP show rate (last 4w avg)', group: 'SQP' },
    { id: 'spend_4w', label: 'Ads Spend (4w)', tip: 'Ads spend last 4 weeks', group: 'Ads (4w)' },
    { id: 'orders_4w', label: 'Ads Ord (4w)', tip: 'Ads orders last 4 weeks', group: 'Ads (4w)' },
    { id: 'roas_4w', label: 'Ads ROAS (4w)', tip: 'Ads ROAS last 4 weeks', group: 'Ads (4w)' },
    { id: 'conv_rate_4w', label: 'Ads Conv% (4w)', tip: 'Ads conv% last 4 weeks', group: 'Ads (4w)' },
    { id: 'spend_ly_peak', label: 'Ads Spend (LY)', tip: 'Ads spend during matched peak period last year', group: 'Ads LY Peak' },
    { id: 'orders_ly_peak', label: 'Ads Ord (LY)', tip: 'Ads orders during matched peak period last year', group: 'Ads LY Peak' },
    { id: 'roas_ly_peak', label: 'Ads ROAS (LY)', tip: 'Ads ROAS during matched peak period last year', group: 'Ads LY Peak' },
    { id: 'sqp_volume_ly_peak', label: 'SQP Vol (LY)', tip: 'SQP search volume during matched peak period last year', group: 'SQP LY Peak' },
    { id: 'sqp_orders_ly_peak', label: 'SQP Ord (LY)', tip: 'SQP total orders during matched peak period last year', group: 'SQP LY Peak' },
    { id: 'action', label: 'Action', group: 'Info' },
  ];
  const ADS_HIER_COLUMNS: MeasureDef[] = [
    { id: 'label', label: 'Search Term → Product → Campaign', group: 'Info' },
    { id: 'spend', label: 'Ads Spend', tip: MEASURE_TIPS.spend, group: 'Ads' },
    { id: 'sales', label: 'Ads Sales', tip: MEASURE_TIPS.ads_sales, group: 'Ads' },
    { id: 'orders', label: 'Ads Orders', tip: MEASURE_TIPS.orders, group: 'Ads' },
    { id: 'clicks', label: 'Ads Clicks', tip: MEASURE_TIPS.clicks, group: 'Ads' },
    { id: 'impressions', label: 'Ads Impr', tip: MEASURE_TIPS.impressions, group: 'Ads' },
    { id: 'conv_rate', label: 'Ads Conv%', tip: MEASURE_TIPS.conv_rate, group: 'Ads' },
    { id: 'cpc', label: 'Ads CPC', group: 'Ads' },
    { id: 'gross_roas', label: 'Ads ROAS', tip: MEASURE_TIPS.ads_roas, group: 'Ads' },
    { id: 'roas', label: 'Net ROAS', tip: MEASURE_TIPS.net_roas, group: 'Ads' },
    { id: 'sqp_volume', label: 'SQP Vol', tip: 'Last month Amazon search volume', group: 'SQP' },
    { id: 'sqp_clicks', label: 'SQP Clicks', tip: 'SQP total clicks (last 4w)', group: 'SQP' },
    { id: 'sqp_cart_adds', label: 'SQP Cart Adds', tip: 'SQP cart adds (last 4w)', group: 'SQP' },
    { id: 'sqp_orders', label: 'SQP Orders', tip: 'Total orders from SQP (last 4w)', group: 'SQP' },
    { id: 'sqp_organic_units', label: 'SQP Organic Orders', tip: 'Organic orders = SQP Orders − SQP Ads Orders (last 4w)', group: 'SQP' },
    { id: 'sqp_organic_pct', label: 'SQP Organic %', tip: 'Organic orders / SQP orders (last 4w)', group: 'SQP' },
    { id: 'sqp_show_rate', label: 'SQP Show%', tip: 'SQP show rate (last 4w avg)', group: 'SQP' },
    { id: 'spend_4w', label: 'Ads Spend (4w)', tip: 'Ads spend last 4 weeks', group: 'Ads (4w)' },
    { id: 'orders_4w', label: 'Ads Ord (4w)', tip: 'Ads orders last 4 weeks', group: 'Ads (4w)' },
    { id: 'roas_4w', label: 'Ads ROAS (4w)', tip: 'Ads ROAS last 4 weeks', group: 'Ads (4w)' },
    { id: 'conv_rate_4w', label: 'Ads Conv% (4w)', tip: 'Ads conv% last 4 weeks', group: 'Ads (4w)' },
    { id: 'spend_ly_peak', label: 'Ads Spend (LY)', tip: 'Ads spend during matched peak period last year', group: 'Ads LY Peak' },
    { id: 'orders_ly_peak', label: 'Ads Ord (LY)', tip: 'Ads orders during matched peak period last year', group: 'Ads LY Peak' },
    { id: 'roas_ly_peak', label: 'Ads ROAS (LY)', tip: 'Ads ROAS during matched peak period last year', group: 'Ads LY Peak' },
    { id: 'sqp_volume_ly_peak', label: 'SQP Vol (LY)', tip: 'SQP search volume during matched peak period last year', group: 'SQP LY Peak' },
    { id: 'sqp_orders_ly_peak', label: 'SQP Ord (LY)', tip: 'SQP total orders during matched peak period last year', group: 'SQP LY Peak' },
    { id: 'action', label: 'Action', group: 'Info' },
  ];
  const ADS_CAMP_COLUMNS: MeasureDef[] = [
    { id: 'label', label: 'Hierarchy', group: 'Info' },
    { id: 'type', label: 'Type', group: 'Info' },
    { id: 'spend', label: 'Ads Spend', tip: MEASURE_TIPS.spend, group: 'Ads' },
    { id: 'sales', label: 'Ads Sales', tip: MEASURE_TIPS.ads_sales, group: 'Ads' },
    { id: 'orders', label: 'Ads Orders', tip: MEASURE_TIPS.orders, group: 'Ads' },
    { id: 'clicks', label: 'Ads Clicks', tip: MEASURE_TIPS.clicks, group: 'Ads' },
    { id: 'conv_rate', label: 'Ads Conv%', tip: MEASURE_TIPS.conv_rate, group: 'Ads' },
    { id: 'cpc', label: 'Ads CPC', group: 'Ads' },
    { id: 'gross_roas', label: 'Ads ROAS', tip: MEASURE_TIPS.ads_roas, group: 'Ads' },
    { id: 'roas', label: 'Net ROAS', tip: MEASURE_TIPS.net_roas, group: 'Ads' },
    { id: 'search_terms_count', label: 'Ads Terms', tip: 'Distinct search terms with spend', group: 'Ads' },
    { id: 'sqp_volume', label: 'SQP Vol (4w)', tip: 'Amazon search volume last 4 weeks (SQP)', group: 'SQP' },
    { id: 'sqp_clicks', label: 'SQP Clicks', tip: 'SQP total clicks (last 4w)', group: 'SQP' },
    { id: 'sqp_cart_adds', label: 'SQP Cart Adds', tip: 'SQP cart adds (last 4w)', group: 'SQP' },
    { id: 'sqp_orders', label: 'SQP Orders', tip: 'Total orders from SQP (last 4w)', group: 'SQP' },
    { id: 'sqp_organic_units', label: 'SQP Organic Orders', tip: 'Organic orders = SQP Orders − SQP Ads Orders (last 4w)', group: 'SQP' },
    { id: 'sqp_organic_pct', label: 'SQP Organic %', tip: 'Organic orders / SQP orders (last 4w)', group: 'SQP' },
    { id: 'sqp_show_rate', label: 'SQP Show%', tip: 'SQP show rate (last 4w avg)', group: 'SQP' },
    { id: 'spend_4w', label: 'Ads Spend (4w)', tip: 'Ads spend last 4 weeks', group: 'Ads (4w)' },
    { id: 'orders_4w', label: 'Ads Ord (4w)', tip: 'Ads orders last 4 weeks', group: 'Ads (4w)' },
    { id: 'roas_4w', label: 'Ads ROAS (4w)', tip: 'Ads ROAS last 4 weeks', group: 'Ads (4w)' },
    { id: 'conv_rate_4w', label: 'Ads Conv% (4w)', tip: 'Ads conv% last 4 weeks', group: 'Ads (4w)' },
    { id: 'spend_ly_peak', label: 'Ads Spend (LY)', tip: 'Ads spend during matched peak period last year', group: 'Ads LY Peak' },
    { id: 'orders_ly_peak', label: 'Ads Ord (LY)', tip: 'Ads orders during matched peak period last year', group: 'Ads LY Peak' },
    { id: 'roas_ly_peak', label: 'Ads ROAS (LY)', tip: 'Ads ROAS during matched peak period last year', group: 'Ads LY Peak' },
    { id: 'sqp_volume_ly_peak', label: 'SQP Vol (LY)', tip: 'SQP search volume during matched peak period last year', group: 'SQP LY Peak' },
    { id: 'sqp_orders_ly_peak', label: 'SQP Ord (LY)', tip: 'SQP total orders during matched peak period last year', group: 'SQP LY Peak' },
    { id: 'action', label: 'Action', group: 'Info' },
  ];
  const [adsTermsCols, setAdsTermsCols] = useMeasureSelection('ads_terms', ADS_TERMS_COLUMNS);
  const [adsHierCols, setAdsHierCols] = useMeasureSelection('ads_hier_terms', ADS_HIER_COLUMNS);
  const [adsCampCols, setAdsCampCols] = useMeasureSelection('ads_campaigns', ADS_CAMP_COLUMNS);

  // Moved to after rawRows definition below
  // (latestWeek and weeks4w placeholders)

  const lyPeakRange = useMemo(() => {
    const pk = data.peak?.[0];
    if (!pk) return null;
    const holidays = data.holidays || [];
    // Find the current holiday record
    const h = holidays.find(x => x.holiday_name === pk.holiday_name && x.holiday_date === pk.holiday_date);
    if (!h) return null;
    // Find the equivalent holiday from last year
    const ly = holidays
      .filter(x => x.holiday_name === h.holiday_name && x.holiday_date < h.holiday_date)
      .sort((a,b) => b.holiday_date.localeCompare(a.holiday_date))[0];
    if (!ly || !ly.pre_season_start) return null;
    
    // Peak ends 2 days before the actual holiday
    const peakEnd = addDays(ly.holiday_date, -2);
    return { start: ly.pre_season_start, end: peakEnd };
  }, [data.peak, data.holidays]);

  const getSignal = (m: any, node?: any) => {
    const signals: { type: keyof typeof ACTION_META; reason: string }[] = [];
    if (m.spend_4w >= 10 && m.orders_4w === 0) {
      signals.push({ type: 'NEGATE', reason: `High spend (${fM(m.spend_4w || 0)}) with 0 orders` });
    } else if (m.roas_4w != null && m.roas_4w < 1.0 && (m.spend_4w || 0) > 5) {
      signals.push({ type: 'REDUCE_BID', reason: `Low ROAS (${fR(m.roas_4w)}) on $5+ spend` });
    }
    if (m.roas_4w != null && m.roas_4w >= 2.5 && (m.spend_4w || 0) < 20 && (m.spend_4w || 0) > 0) {
      signals.push({ type: 'SCALE_UP', reason: `High ROAS (${fR(m.roas_4w)}) - increase bid` });
    }
    if (m.sqp_organic_units >= 5 && (m.spend_4w || 0) === 0) {
      signals.push({ type: 'START', reason: `High organic demand (${m.sqp_organic_units} ord) - add keyword` });
    }
    // Switch Hero logic: if this search term's top product revenue > 2x current campaign product revenue
    if (node?.level === 'search_term' && node?.children?.length > 1) {
       const sorted = [...node.children].sort((a: any, b: any) => (b.metrics.sales || 0) - (a.metrics.sales || 0));
       if (sorted[0].metrics.sales > sorted[1].metrics.sales * 2) {
          signals.push({ type: 'SWITCH_HERO', reason: `Product "${sorted[0].label}" selling 2x better than others` });
       }
    }
    return signals;
  };
  const visibleAdsTermsCols = useMemo(() => ADS_TERMS_COLUMNS.filter(c => adsTermsCols.has(c.id)), [adsTermsCols]);
  const visibleAdsHierCols = useMemo(() => ADS_HIER_COLUMNS.filter(c => adsHierCols.has(c.id)), [adsHierCols]);
  const visibleAdsCampCols = useMemo(() => ADS_CAMP_COLUMNS.filter(c => adsCampCols.has(c.id)), [adsCampCols]);

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

  const allRawRows = data.ads_7d || [];
  // When includeCurrentWeek is OFF and periodMode is 'weeks', exclude current week from raw rows
  const currentWeekStart = useMemo(() => getCurrentWeekStart(), []);
  const rawRows = useMemo(() => {
    if (includeCurrentWeek || filters.periodMode !== 'weeks') return allRawRows;
    return allRawRows.filter(r => !r.week_start || r.week_start < currentWeekStart);
  }, [allRawRows, includeCurrentWeek, filters.periodMode, currentWeekStart]);
  const hasWeekStart = rawRows.some(r => r.week_start);

  const latestWeek = useMemo(() => {
    const ws = [...new Set(rawRows.map(r => r.week_start || '').filter(Boolean))].sort();
    return ws[ws.length - 1] || null;
  }, [rawRows]);

  const weeks4w = useMemo(() => {
    if (!latestWeek) return new Set<string>();
    const ws = [...new Set(rawRows.map(r => r.week_start || '').filter(Boolean))].sort();
    const idx = ws.indexOf(latestWeek);
    return new Set(ws.slice(Math.max(0, idx - 3), idx + 1));
  }, [rawRows, latestWeek]);

  /** Period-filtered raw rows (before camp/term aggregation). Used for accurate totals. */
  const filteredRawRows = useMemo((): Ads7dRow[] => {
    if (!hasWeekStart || !rawRows.length) return rawRows;
    const periodMode = filters.periodMode;

    // Date mode: filter by specific date's week or latest week
    // Note: ads_7d data is weekly (has week_start, not daily date), so we find the
    // containing week for the selected date. KPIs will show that week's totals.
    if (periodMode === 'date') {
      // First try matching by actual date field (for rows that have daily data)
      const hasDateField = rawRows.some(r => r.date);
      if (hasDateField) {
        if (filters.specificPeriod) {
          return rawRows.filter(r => r.date === filters.specificPeriod);
        }
        const allDates = [...new Set(rawRows.map(r => r.date || '').filter(Boolean))].sort();
        const latestDate = allDates[allDates.length - 1];
        if (latestDate) return rawRows.filter(r => r.date === latestDate);
      }
      // Fallback: match by week containing the selected date (or latest week)
      if (filters.specificPeriod) {
        const targetWeek = getWeekStart(filters.specificPeriod);
        return rawRows.filter(r => r.week_start === targetWeek);
      }
      // No date selected — show latest week
      const allWeeks = [...new Set(rawRows.map(r => r.week_start || '').filter(Boolean))].sort();
      const latestWeek = allWeeks[allWeeks.length - 1];
      return latestWeek ? rawRows.filter(r => r.week_start === latestWeek) : rawRows;
    }

    const useDateFilter = periodMode !== 'weeks' && rawRows.some(r => r.date);
    const periodKeys = useDateFilter
      ? [...new Set(rawRows.map(r => (r.date || '').slice(0, periodMode === 'month' ? 7 : 4)).filter(Boolean))].sort()
      : [...new Set(rawRows.map(r => periodKey(r.week_start || '', periodMode)).filter(Boolean))].sort();
    if (!periodKeys.length) return rawRows;
    const keepPeriods = new Set(getPeriodsToInclude(filters.specificPeriod, filters.periodMode, periodKeys, 1));
    return rawRows.filter(r => {
      const pk = useDateFilter
        ? (r.date || '').slice(0, periodMode === 'month' ? 7 : 4)
        : periodKey(r.week_start || '', periodMode);
      return pk && keepPeriods.has(pk);
    });
  }, [rawRows, hasWeekStart, filters.periodMode, filters.specificPeriod]);

  const rows = useMemo((): Ads7dRow[] => {
    const filtered = filteredRawRows;
    if (filtered.length === 0) return [];
    const filteredSet = new Set(filtered);
    const campAgg: Record<string, Ads7dRow> = {};
    const termAgg: Record<string, Ads7dRow> = {};
    const productRevenueByTerm4w: Record<string, Record<string, number>> = {};

    const processRow = (r: Ads7dRow, target: Record<string, Ads7dRow>, key: string) => {
      const isCurrent = filteredSet.has(r);
      const is4w = weeks4w.has(r.week_start || '');
      const isLyPeak = lyPeakRange && r.date && (
        (r.date >= lyPeakRange.start && r.date <= lyPeakRange.end) || 
        (addDays(r.date, 6) >= lyPeakRange.start && r.date <= lyPeakRange.start)
      );

      if (!isCurrent && !is4w && !isLyPeak) return;

      if (!target[key]) {
        target[key] = {
          ...r, spend: 0, orders: 0, clicks: 0, impressions: 0, sales: 0, cogs: 0, gross_profit: 0, search_terms_count: 0,
          spend_4w: 0, orders_4w: 0, clicks_4w: 0, sales_4w: 0, spend_ly_peak: 0, orders_ly_peak: 0, sales_ly_peak: 0
        };
      }
      const a = target[key];
      if (isCurrent) {
        a.spend += r.spend; a.orders += r.orders; a.clicks += r.clicks; a.impressions += r.impressions; a.sales += r.sales;
        a.cogs = (a.cogs ?? 0) + (r.cogs ?? 0); a.gross_profit = (a.gross_profit ?? 0) + (r.gross_profit ?? 0);
        if (r.row_type === 'campaign') a.search_terms_count = (a.search_terms_count ?? 0) + (r.search_terms_count ?? 0);
      }
      if (is4w) { a.spend_4w! += r.spend; a.orders_4w! += r.orders; a.clicks_4w! += r.clicks; a.sales_4w! += r.sales; }
      if (isLyPeak) { a.spend_ly_peak! += r.spend; a.orders_ly_peak! += r.orders; a.sales_ly_peak! += r.sales; }
      
      const term = (r.search_term || '').toLowerCase().trim();
      if (term && is4w) {
        const prod = (r.product_short_name || '').trim();
        if (prod) {
          if (!productRevenueByTerm4w[term]) productRevenueByTerm4w[term] = {};
          productRevenueByTerm4w[term][prod] = (productRevenueByTerm4w[term][prod] || 0) + r.sales;
        }
      }
    };

    for (const r of rawRows) {
      if (r.row_type === 'campaign') processRow(r, campAgg, r.campaign_id);
      else processRow(r, termAgg, `${r.campaign_id}\0${r.search_term || ''}`);
    }
    // Derive campaign rows from term aggregates when Cube returns only search_term-level data (no campaign rows)
    const campFromTerms: Record<string, Ads7dRow> = {};
    for (const t of Object.values(termAgg)) {
      const k = t.campaign_id;
      if (!k) continue;
      if (!campFromTerms[k]) {
        campFromTerms[k] = { ...t, row_type: 'campaign', search_term: null, spend: 0, orders: 0, clicks: 0, impressions: 0, sales: 0, cogs: 0, search_terms_count: 0,
          spend_4w: 0, orders_4w: 0, clicks_4w: 0, sales_4w: 0, spend_ly_peak: 0, orders_ly_peak: 0, sales_ly_peak: 0
        };
      }
      const a = campFromTerms[k];
      a.spend += t.spend; a.orders += t.orders; a.clicks += t.clicks; a.impressions += t.impressions; a.sales += t.sales;
      a.cogs = (a.cogs ?? 0) + (t.cogs ?? 0); a.search_terms_count = (a.search_terms_count ?? 0) + 1;
      a.spend_4w! += t.spend_4w || 0; a.orders_4w! += t.orders_4w || 0; a.clicks_4w! += t.clicks_4w || 0; a.sales_4w! += t.sales_4w || 0;
      a.spend_ly_peak! += t.spend_ly_peak || 0; a.orders_ly_peak! += t.orders_ly_peak || 0; a.sales_ly_peak! += t.sales_ly_peak || 0;
    }
    const allCampAgg = { ...campAgg };
    for (const [k, c] of Object.entries(campFromTerms)) {
      if (allCampAgg[k]) {
        const a = allCampAgg[k];
        a.spend += c.spend; a.orders += c.orders; a.clicks += c.clicks; a.impressions += c.impressions; a.sales += c.sales;
        a.cogs = (a.cogs ?? 0) + (c.cogs ?? 0); a.search_terms_count = (a.search_terms_count ?? 0) + (c.search_terms_count ?? 0);
        a.spend_4w! += c.spend_4w || 0; a.orders_4w! += c.orders_4w || 0; a.clicks_4w! += c.clicks_4w || 0; a.sales_4w! += c.sales_4w || 0;
        a.spend_ly_peak! += c.spend_ly_peak || 0; a.orders_ly_peak! += c.orders_ly_peak || 0; a.sales_ly_peak! += c.sales_ly_peak || 0;
      } else {
        allCampAgg[k] = c;
      }
    }
    const finalize = (a: Ads7dRow) => {
      a.cpc = a.clicks > 0 ? a.spend / a.clicks : 0;
      a.conv_rate = a.clicks > 0 ? (a.orders * 100) / a.clicks : 0;
      a.roas = a.spend > 0 ? (a.sales - (a.cogs || 0)) / a.spend : 0;
      a.gross_roas = a.spend > 0 ? a.sales / a.spend : 0;
      a.roas_4w = (a.spend_4w || 0) > 0 ? (a.sales_4w! / a.spend_4w!) : 0;
      a.conv_rate_4w = (a.clicks_4w || 0) > 0 ? ((a.orders_4w || 0) * 100) / a.clicks_4w! : 0;
      a.roas_ly_peak = (a.spend_ly_peak || 0) > 0 ? (a.sales_ly_peak! / a.spend_ly_peak!) : 0;
    };
    const finalRows = [...Object.values(allCampAgg), ...Object.values(termAgg)];
    finalRows.forEach(a => {
      finalize(a);
      if (a.row_type === 'search_term' && a.search_term) {
        const term = (a.search_term || '').toLowerCase().trim();
        const prods = productRevenueByTerm4w[term];
        if (prods) {
          const top = Object.entries(prods).sort(([, v1], [, v2]) => v2 - v1)[0];
          if (top && top[1] > 0) (a as any).best_product_by_revenue_4w = top[0];
        }
      }
    });
    return finalRows;
  }, [filteredRawRows, rawRows, weeks4w, lyPeakRange]);

  const campaigns = useMemo(() => {
    let filtered = rows.filter(r => r.row_type === 'campaign');
    if (famMatch) filtered = filtered.filter(r => {
      const cn = (r.campaign_name || '').toLowerCase();
      return famMatch.some(p => cn.includes(p));
    });
    if (expCampaignIds) filtered = filtered.filter(r => expCampaignIds.has(r.campaign_id));
    if (filters.keyword) filtered = filtered.filter(c => {
      const terms = rows.filter(r => r.row_type === 'search_term' && r.campaign_id === c.campaign_id);
      return terms.some(t => t.search_term === filters.keyword);
    });
    return filtered.sort((a, b) => b.spend - a.spend);
  }, [rows, famMatch, expCampaignIds, filters.keyword]);
  const campIds = useMemo(() => new Set(campaigns.map(c => c.campaign_id)), [campaigns]);
  const sqpVolumeByTerm = useMemo(() => {
    // Primary: use pre-computed sqp_amazon_search_volume_4w from AdsCoachDecision (DB layer)
    const vol: Record<string, number> = {};
    for (const cd of data.coach_decisions || []) {
      const term = (cd.search_term || '').toLowerCase().trim();
      if (term && cd.sqp_amazon_search_volume_4w > 0) {
        vol[term] = (vol[term] || 0) + cd.sqp_amazon_search_volume_4w;
      }
    }
    if (Object.keys(vol).length > 0) return vol;
    // Fallback: reconstruct from sqp_weekly uploads (legacy path)
    const pre = data.sqp_volume_4w;
    if (pre && typeof pre === 'object' && !Array.isArray(pre) && Object.keys(pre).length > 0) return pre;
    return sqpVolumeByTermPastMonth(data.sqp_weekly || []);
  }, [data.coach_decisions, data.sqp_volume_4w, data.sqp_weekly]);
  const sqpDetailsByTerm = useMemo(() => {
    const out: Record<string, { clicks: number; cart_adds: number; orders: number; amazon_orders: number; ads_orders: number; show_rate_sum: number; show_rate_cnt: number; volume_ly_peak: number; orders_ly_peak: number }> = {};

    // Primary: 4w SQP data from coach_decisions (V_ADS_COACH_DECISION)
    for (const cd of data.coach_decisions || []) {
      const term = (cd.search_term || '').toLowerCase().trim();
      if (!term) continue;
      if (!out[term]) {
        out[term] = { clicks: 0, cart_adds: 0, orders: 0, amazon_orders: 0, ads_orders: 0, show_rate_sum: 0, show_rate_cnt: 0, volume_ly_peak: 0, orders_ly_peak: 0 };
      }
      const d = out[term];
      d.clicks = cd.sqp_clicks_4w || 0;
      d.cart_adds = cd.sqp_cart_adds_4w || 0;
      d.orders = cd.sqp_orders_4w || 0;
      d.ads_orders = (cd.sqp_orders_4w || 0) - (cd.sqp_organic_units_4w || 0); // reverse: ads = total - organic
      d.amazon_orders = 0; // not available in coach_decisions
      if (cd.sqp_show_rate_4w > 0) { d.show_rate_sum = cd.sqp_show_rate_4w; d.show_rate_cnt = 1; }
    }

    // LY Peak: still from sqp_weekly (needs historical weekly data)
    const sqp = data.sqp_weekly || [];
    if (lyPeakRange) {
      for (const r of sqp) {
        const term = (r.search_term || '').toLowerCase().trim();
        if (!term) continue;
        const ws = r.week_start || '';
        if ((ws >= lyPeakRange.start && ws <= lyPeakRange.end) ||
          (addDays(ws, 6) >= lyPeakRange.start && ws <= lyPeakRange.start)) {
          if (!out[term]) {
            out[term] = { clicks: 0, cart_adds: 0, orders: 0, amazon_orders: 0, ads_orders: 0, show_rate_sum: 0, show_rate_cnt: 0, volume_ly_peak: 0, orders_ly_peak: 0 };
          }
          out[term].volume_ly_peak += r.amazon_impressions || 0;
          out[term].orders_ly_peak += r.orders || 0;
        }
      }
    }

    // Fallback: if coach_decisions didn't provide 4w data, fill from sqp_weekly
    if ((data.coach_decisions || []).length === 0 && sqp.length > 0) {
      const latestWs = [...new Set(sqp.map(r => r.week_start || '').filter(Boolean))].sort();
      const weeks4wSqp = new Set(latestWs.slice(-4));
      for (const r of sqp) {
        const term = (r.search_term || '').toLowerCase().trim();
        if (!term) continue;
        const ws = r.week_start || '';
        if (!weeks4wSqp.has(ws)) continue;
        if (!out[term]) {
          out[term] = { clicks: 0, cart_adds: 0, orders: 0, amazon_orders: 0, ads_orders: 0, show_rate_sum: 0, show_rate_cnt: 0, volume_ly_peak: 0, orders_ly_peak: 0 };
        }
        const d = out[term];
        d.clicks += r.clicks || 0;
        d.cart_adds += r.cart_adds || 0;
        d.orders += r.orders || 0;
        d.amazon_orders += r.amazon_orders || 0;
        d.ads_orders += r.ads_orders || 0;
        if (r.show_rate_pct != null) { d.show_rate_sum += r.show_rate_pct; d.show_rate_cnt++; }
      }
    }

    return out;
  }, [data.coach_decisions, data.sqp_weekly, lyPeakRange]);
  const searchTerms = useMemo((): Ads7dRow[] => {
    // Prefer ads_7d search_term rows if available; otherwise synthesize from campaign_search_terms
    let fromAds = rows.filter(r => r.row_type === 'search_term');
    if (famMatch || expCampaignIds) fromAds = fromAds.filter(r => campIds.has(r.campaign_id));
    if (filters.keyword) fromAds = fromAds.filter(r => r.search_term === filters.keyword);
    
    if (fromAds.length > 0) {
      return fromAds.map(t => {
        const det = sqpDetailsByTerm[(t.search_term || '').toLowerCase().trim()];
        return {
          ...t,
          sqp_volume_ly_peak: det?.volume_ly_peak || 0,
          sqp_orders_ly_peak: det?.orders_ly_peak || 0,
          sqp_organic_units: det ? Math.max(0, det.orders - det.ads_orders) : 0,
          sqp_organic_pct: (det && det.orders > 0) ? (Math.max(0, det.orders - det.ads_orders) / det.orders) * 100 : 0,
        };
      });
    }

    // Synthesize from campaign_search_terms
    const cst = data.campaign_search_terms || [];
    if (!cst.length) return [];
    const campMap = new Map(campaigns.map(c => [c.campaign_id, c]));
    let synth = cst.filter(t => campMap.has(t.campaign_id)).map(t => {
      const camp = campMap.get(t.campaign_id)!;
      const sales = t.orders > 0 && camp.sales > 0 && camp.orders > 0 ? (t.orders / camp.orders) * camp.sales : 0;
      const cogs = t.orders > 0 && camp.cogs && camp.orders > 0 ? (t.orders / camp.orders) * (camp.cogs ?? 0) : 0;
      const det = sqpDetailsByTerm[(t.search_term || '').toLowerCase().trim()];
      return {
        row_type: 'search_term' as const,
        week_start: camp.week_start, date: camp.date,
        campaign_id: t.campaign_id, campaign_name: camp.campaign_name,
        campaign_type: camp.campaign_type, portfolio_name: camp.portfolio_name,
        product_short_name: camp.product_short_name, search_term: t.search_term,
        spend: t.spend, orders: t.orders, clicks: t.clicks, impressions: t.impressions,
        sales, cogs, gross_profit: null,
        cpc: t.cpc, conv_rate: t.conv_rate,
        roas: t.spend > 0 ? (sales - cogs) / t.spend : 0,
        gross_roas: t.spend > 0 ? sales / t.spend : 0,
        // campaign_search_terms is a 90-day aggregate — use as proxy for 4w metrics
        // so Money Bleeders and action signals can detect zero-order terms
        spend_4w: t.spend, orders_4w: t.orders, clicks_4w: t.clicks, sales_4w: sales,
        roas_4w: t.spend > 0 ? sales / t.spend : 0,
        conv_rate_4w: t.clicks > 0 ? (t.orders * 100) / t.clicks : 0,
        sqp_volume_ly_peak: det?.volume_ly_peak || 0,
        sqp_orders_ly_peak: det?.orders_ly_peak || 0,
        sqp_organic_units: det ? Math.max(0, det.orders - det.ads_orders) : 0,
        sqp_organic_pct: (det && det.orders > 0) ? (Math.max(0, det.orders - det.ads_orders) / det.orders) * 100 : 0,
      } as Ads7dRow;
    });
    if (filters.keyword) synth = synth.filter(r => r.search_term === filters.keyword);
    return synth;
  }, [rows, campaigns, data.campaign_search_terms, famMatch, expCampaignIds, campIds, filters.keyword, sqpDetailsByTerm]);

  const totals = useMemo(() => {
    const t = { spend: 0, orders: 0, clicks: 0, impressions: 0, sales: 0, gross_profit: 0, cogs: 0 };
    // When keyword filter is active, use search term data (keyword-specific) instead of campaign totals
    const src = filters.keyword ? searchTerms : campaigns;
    src.forEach(c => { t.spend += c.spend; t.orders += c.orders; t.clicks += c.clicks; t.impressions += c.impressions; t.sales += c.sales; t.gross_profit += (c.gross_profit ?? 0); t.cogs += (c.cogs ?? 0); });
    return t;
  }, [campaigns, searchTerms, filters.keyword]);

  const drainers = useMemo(() => {
    // Identify by 4w data: spend_4w ≥ min AND orders_4w = 0
    const bleeders = searchTerms.filter(t => (t.spend_4w || 0) >= drainerMinSpend && (t.orders_4w || 0) === 0);
    // Mark resolved: if last 7d had orders > 0, the term resolved recently
    return bleeders
      .map(t => ({ ...t, _resolved: t.orders > 0 }))
      .sort((a, b) => (a._resolved ? 1 : 0) - (b._resolved ? 1 : 0) || (b.spend_4w || 0) - (a.spend_4w || 0))
      .slice(0, 50);
  }, [searchTerms, drainerMinSpend]);

  const bestTerms = useMemo(() =>
    searchTerms.filter(t => t.spend >= bestMinSpend && t.orders > 0 && t.roas > 0)
      .sort((a, b) => b.roas - a.roas).slice(0, 50),
  [searchTerms, bestMinSpend]);

  const lowConvHighSpend = useMemo(() =>
    searchTerms.filter(t => t.spend >= 10 && t.clicks >= 20 && t.conv_rate < 3)
      .sort((a, b) => b.spend - a.spend).slice(0, 30),
  [searchTerms]);

  const toggleHierarchyLevel = (id: (typeof HIERARCHY_OPTIONS)[number]['id']) => {
    setCampaignHierarchy(prev => {
      if (prev.includes(id)) return prev.filter(x => x !== id);
      const idx = HIERARCHY_OPTIONS.findIndex(o => o.id === id);
      const insertIdx = prev.length === 0 ? 0 : Math.min(prev.findIndex(p => HIERARCHY_OPTIONS.findIndex(o => o.id === p) > idx) ?? prev.length, prev.length);
      const next = [...prev];
      next.splice(insertIdx, 0, id);
      return next;
    });
  };

  const moveHierarchyLevel = (fromIndex: number, toIndex: number) => {
    if (fromIndex === toIndex) return;
    setCampaignHierarchy(prev => {
      const next = [...prev];
      const [item] = next.splice(fromIndex, 1);
      next.splice(toIndex, 0, item);
      return next;
    });
  };

  const toggleExpanded = (key: string) => setExpandedKeys(p => { const n = new Set(p); n.has(key) ? n.delete(key) : n.add(key); return n; });

  const termsForCampaign = (campId: string) => searchTerms.filter(t => t.campaign_id === campId).sort((a, b) => b.spend - a.spend);

  const totalRoas = totals.spend > 0 ? totals.sales / totals.spend : 0;
  // Net Profit = Sales − COGS − Spend (matches trend chart formula)
  const totalNetProfit = totals.gross_profit !== 0
    ? totals.gross_profit - totals.spend  // gross_profit = sales - cogs from row finalize
    : totals.sales - totals.cogs - totals.spend;
  const totalNetRoas = totals.spend > 0 ? totalNetProfit / totals.spend : 0;
  const totalWasted = drainers.reduce((s, d) => s + (d.spend_4w || 0), 0);
  const resolvedCount = drainers.filter(d => (d as any)._resolved).length;
  const activeBleeders = drainers.filter(d => !(d as any)._resolved);

  const productByTerm = useMemo(() => productByTermMap(data.keyword_product_map || [], data.sqp_weekly || []), [data.keyword_product_map, data.sqp_weekly]);

  /** campaign_id -> product_short_name from that campaign's search terms (productByTerm). Used when ads row has no product_short_name. */
  const campaignToProduct = useMemo(() => {
    const out: Record<string, { prod: string; spend: number }> = {};
    for (const t of searchTerms) {
      const term = (t.search_term || '').toLowerCase().trim();
      if (!term) continue;
      const prod = productByTerm[term];
      if (!prod) continue;
      const cid = t.campaign_id;
      const s = t.spend || 0;
      if (!out[cid] || s > out[cid].spend) out[cid] = { prod, spend: s };
    }
    return Object.fromEntries(Object.entries(out).map(([k, v]) => [k, v.prod]));
  }, [searchTerms, productByTerm]);

  const effectivePeriod = useMemo(() => {
    if (!hasWeekStart || !rawRows.length) return null;
    const useDateFilter = filters.periodMode !== 'weeks' && rawRows.some(r => r.date);
    const periodKeys = useDateFilter
      ? [...new Set(rawRows.map(r => (r.date || '').slice(0, filters.periodMode === 'month' ? 7 : 4)).filter(Boolean))].sort()
      : [...new Set(rawRows.map(r => periodKey(r.week_start || '', filters.periodMode)).filter(Boolean))].sort();
    const periods = getPeriodsToInclude(filters.specificPeriod, filters.periodMode, periodKeys, 1);
    return periods[periods.length - 1] || null;
  }, [rawRows, hasWeekStart, filters.periodMode, filters.specificPeriod]);

  const periodLabel = useMemo(() => {
    if (!hasWeekStart) return 'Latest period';
    if (filters.periodMode === 'date') return filters.specificPeriod || 'Latest date';
    const period = filters.specificPeriod || effectivePeriod;
    if (!period) return 'Latest period';
    return filters.periodMode === 'weeks' ? weekRangeLabelCapped(period, perfMaxDate) : period;
  }, [hasWeekStart, filters.periodMode, filters.specificPeriod, effectivePeriod]);

  const totalCvr = totals.clicks > 0 ? (totals.orders * 100) / totals.clicks : 0;
  const totalCtr = totals.impressions > 0 ? (totals.clicks * 100) / totals.impressions : 0;

  usePageSummary({
    title: 'Ads',
    items: [
      { label: 'Spend', value: fM(totals.spend) },
      { label: 'Orders', value: fOrd(totals.orders) },
      { label: 'Sales', value: fM(totals.sales) },
      { label: 'ROAS', value: fR(totalRoas), color: totalRoas >= 1 ? 'green' : 'red' },
      { label: 'Net Profit', value: fM(totalNetProfit), color: totalNetProfit >= 0 ? 'green' : 'red' },
      { label: 'Net ROAS', value: fR(totalNetRoas), color: totalNetRoas >= 1 ? 'green' : 'red' },
      { label: 'CPC', value: fCpc(totals.clicks > 0 ? totals.spend / totals.clicks : 0) },
      { label: 'CVR', value: fP(totalCvr) },
      { label: 'CTR', value: fP(totalCtr) },
      { label: 'Wasted', value: fM(totalWasted), color: 'red' },
    ],
  });

  return (
    <div className="animate-in">
      <h1 className="text-[22px] font-extrabold tracking-tight mb-1">Ads Performance</h1>
      <div className="flex items-center gap-3 mb-5">
        <p className="text-xs text-subtle">{periodLabel} · Campaign & search term analysis</p>
        <button
          onClick={() => setIncludeCurrentWeek(p => !p)}
          className={`flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-[10px] font-semibold border transition-all ${
            includeCurrentWeek
              ? 'bg-amber-500/15 text-amber-400 border-amber-500/30'
              : 'text-faint border-border hover:text-muted hover:border-border-strong'
          }`}
          title={`Current week (${weekRangeLabelCapped(currentWeekStart, perfMaxDate)}) — data may be incomplete`}
        >
          <span className={`w-2 h-2 rounded-full transition-colors ${includeCurrentWeek ? 'bg-amber-400' : 'bg-zinc-600'}`} />
          This Week {includeCurrentWeek ? 'ON' : 'OFF'}
        </button>
      </div>

      {/* KPIs shown in PageSummaryBar above */}

      {/* Weekly Ads Trend — dynamic with measure selector */}
      <AdsTrendChart rawRows={rawRows} famMatch={famMatch} expCampaignIds={expCampaignIds} periodTrend={filters.periodTrend} holidays={data.holidays || []} perfMaxDate={perfMaxDate} />

      {/* Insight Cards */}
      <div className="grid grid-cols-2 gap-3.5 mb-6">
        <Card className="!p-4 border-emerald-500/20">
          <div className="flex items-center gap-2 mb-2">
            <Zap size={14} className="text-emerald-400" />
            <span className="text-xs font-bold text-emerald-400">What's Working</span>
          </div>
          <div className="text-[11px] text-subtle space-y-1">
            {bestTerms.slice(0, 3).map((t, i) => (
              <div key={i}>"{t.search_term}" — <span className="text-emerald-400 font-mono">{fR(t.roas)}</span> ROAS, {fOrd(t.orders)} orders at {fP(t.conv_rate)} conv</div>
            ))}
            {bestTerms.length === 0 && <div>No profitable terms found this week</div>}
          </div>
        </Card>
        <Card className="!p-4 border-red-500/20">
          <div className="flex items-center gap-2 mb-2">
            <AlertTriangle size={14} className="text-red-400" />
            <span className="text-xs font-bold text-red-400">Money Drains — Action Needed</span>
          </div>
          <div className="text-[11px] text-subtle space-y-1">
            {activeBleeders.slice(0, 3).map((t, i) => (
              <div key={i}>"{t.search_term}" — <span className="text-red-400 font-mono">{fM(t.spend_4w || 0)}</span> spent (4w), {fClk(t.clicks)} clicks, 0 orders → <span className="text-red-400 font-semibold">negate or reduce bid</span></div>
            ))}
            {activeBleeders.length === 0 && <div className="text-emerald-400">All bleeders resolved in the last 7 days ✅</div>}
            {resolvedCount > 0 && activeBleeders.length > 0 && <div className="text-emerald-400 text-[10px] mt-1">{resolvedCount} terms resolved (got orders in last 7d)</div>}
          </div>
        </Card>
      </div>

      {/* Campaigns */}
      <Section title="Campaigns" count={`${campaigns.length} active`} filterItems={formatSectionFilters(filters, { Hierarchy: campaignHierarchy.join(' → ') })} headerRight={<MeasureSelector tableId="ads_campaigns" measures={ADS_CAMP_COLUMNS} selected={adsCampCols} onSelectedChange={setAdsCampCols} />}>
        <div className="mb-3 flex flex-wrap items-center gap-2">
          <span className="text-[10px] text-subtle">Hierarchy:</span>
          <div className="flex flex-wrap items-center gap-1">
            {campaignHierarchy.map((id, index) => {
              const o = HIERARCHY_OPTIONS.find(x => x.id === id)!;
                return (
                <div
                  key={id}
                  draggable
                  onDragStart={e => {
                    e.dataTransfer.setData('text/plain', String(index));
                    e.dataTransfer.effectAllowed = 'move';
                  }}
                  onDragOver={e => {
                    e.preventDefault();
                    e.dataTransfer.dropEffect = 'move';
                  }}
                  onDrop={e => {
                    e.preventDefault();
                    const from = parseInt(e.dataTransfer.getData('text/plain'), 10);
                    moveHierarchyLevel(from, index);
                  }}
                  className="flex items-center gap-1 px-2 py-1 rounded text-[10px] font-medium bg-blue-500/20 text-blue-400 border border-blue-500/40 cursor-grab active:cursor-grabbing hover:bg-blue-500/30"
                >
                  <GripVertical size={12} className="text-faint shrink-0" />
                  {o.label}
                        </div>
                );
              })}
          </div>
          <span className="text-[10px] text-faint">|</span>
          {HIERARCHY_OPTIONS.filter(o => !campaignHierarchy.includes(o.id)).map(o => (
            <button
              key={o.id}
              onClick={() => toggleHierarchyLevel(o.id)}
              className="px-2 py-1 rounded text-[10px] text-faint border border-border hover:border-border-strong hover:text-muted"
            >
              + {o.label}
            </button>
          ))}
          <button
            onClick={() => setCampaignHierarchy(DEFAULT_HIERARCHY)}
            className="px-2 py-1 rounded text-[10px] text-faint border border-border hover:border-border-strong"
          >
            Reset
          </button>
        </div>
        <div className="mb-3 flex items-center gap-2">
          <span className="text-[10px] text-subtle">Min clicks:</span>
          {[null, 5, 15, 30, 50].map(v => (
            <button key={String(v)} onClick={() => setCampMinClicks(v)}
              className={`px-2 py-0.5 rounded text-[10px] font-mono border transition-all ${campMinClicks === v ? 'bg-blue-500/20 text-blue-400 border-blue-500/30' : 'text-faint border-border hover:border-border-strong'}`}>
              {v == null ? 'All' : `>${v}`}
            </button>
          ))}
        </div>
        <DynamicHierarchyCampaignsTable
          campaigns={campaigns}
          searchTerms={searchTerms}
          hierarchy={campaignHierarchy}
          expandedKeys={expandedKeys}
          onToggle={toggleExpanded}
          productByTerm={productByTerm}
          campaignToProduct={campaignToProduct}
          campSort={campSort}
          termsForCampaign={termsForCampaign}
          visibleCols={visibleAdsCampCols}
          sqpVolumeByTerm={sqpVolumeByTerm}
          sqpDetailsByTerm={sqpDetailsByTerm}
          getSignal={getSignal}
          minClicksFilter={campMinClicks}
        />
      </Section>

      {/* Best Search Terms */}
      <Section title="Best Search Terms" count={`Top ${bestTerms.length} · min ${fM(bestMinSpend)} spend`} filterItems={formatSectionFilters(filters, { 'Best min spend': fM(bestMinSpend) })} headerRight={<MeasureSelector tableId="ads_hier_terms" measures={ADS_HIER_COLUMNS} selected={adsHierCols} onSelectedChange={setAdsHierCols} />}>
        <div className="flex items-center gap-2 mb-2">
          <span className="text-[10px] text-subtle">Min spend:</span>
          {[3, 5, 10, 20].map(v => (
            <button key={v} onClick={() => setBestMinSpend(v)}
              className={`px-2 py-0.5 rounded text-[10px] font-mono border transition-all ${bestMinSpend === v ? 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30' : 'text-faint border-border hover:border-border-strong'}`}>
              ${v}
            </button>
          ))}
        </div>
        <HierarchicalTermsTable terms={bestTerms} highlight="best" sqpVolume={sqpVolumeByTerm} sqpDetails={sqpDetailsByTerm} sqpWeekly={data.sqp_weekly || []} keywordProductMap={data.keyword_product_map || []} visibleCols={visibleAdsHierCols} getSignal={getSignal} />
      </Section>

      {/* Drainer Search Terms */}
      <Section title="Money Bleeders — 0 Orders (4w)" count={`${drainers.length} terms · min ${fM(drainerMinSpend)} spend (4w)${resolvedCount > 0 ? ` · ${resolvedCount} resolved` : ''}`} filterItems={formatSectionFilters(filters, { 'Drainer min spend': fM(drainerMinSpend) })} headerRight={<MeasureSelector tableId="ads_terms" measures={ADS_TERMS_COLUMNS} selected={adsTermsCols} onSelectedChange={setAdsTermsCols} />}>
        <div className="flex items-center gap-2 mb-2">
          <span className="text-[10px] text-subtle">Min spend:</span>
          {[3, 5, 10, 20].map(v => (
            <button key={v} onClick={() => setDrainerMinSpend(v)}
              className={`px-2 py-0.5 rounded text-[10px] font-mono border transition-all ${drainerMinSpend === v ? 'bg-red-500/20 text-red-400 border-red-500/30' : 'text-faint border-border hover:border-border-strong'}`}>
              ${v}
            </button>
          ))}
        </div>
        <TermsTable terms={drainers} highlight="drain" visibleCols={visibleAdsTermsCols} sqpVolume={sqpVolumeByTerm} sqpDetails={sqpDetailsByTerm} getSignal={getSignal} />
      </Section>

      {/* Low Conversion High Spend */}
      {lowConvHighSpend.length > 0 && (
        <Section title="Low Conversion, High Spend" count={`${lowConvHighSpend.length} terms · ≥$10 spend, ≥20 clicks, <3% conv`} filterItems={formatSectionFilters(filters, { 'Min spend': '$10', 'Min clicks': '20', 'Max conv%': '3%' })} headerRight={<MeasureSelector tableId="ads_terms" measures={ADS_TERMS_COLUMNS} selected={adsTermsCols} onSelectedChange={setAdsTermsCols} />}>
          <div className="bg-amber-500/5 border border-amber-500/20 rounded-xl p-3 mb-3">
            <div className="flex items-center gap-2">
              <TrendingDown size={14} className="text-amber-400" />
              <span className="text-xs font-bold text-amber-400">Optimize or negate</span>
            </div>
            <div className="text-[10px] text-subtle mt-1">These terms get traffic but rarely convert. Review listing relevance, adjust bids, or negate.</div>
          </div>
          <TermsTable terms={lowConvHighSpend} highlight="warn" visibleCols={visibleAdsTermsCols} sqpVolume={sqpVolumeByTerm} sqpDetails={sqpDetailsByTerm} getSignal={getSignal} />
        </Section>
      )}
    </div>
  );
}

/** Dynamic hierarchy campaigns table */
function DynamicHierarchyCampaignsTable({
  campaigns,
  searchTerms,
  hierarchy,
  expandedKeys,
  onToggle,
  productByTerm,
  campaignToProduct,
  campSort,
  termsForCampaign,
  visibleCols,
  sqpVolumeByTerm,
  sqpDetailsByTerm,
  getSignal,
  minClicksFilter,
}: {
  campaigns: Ads7dRow[];
  searchTerms: Ads7dRow[];
  hierarchy: (typeof HIERARCHY_OPTIONS)[number]['id'][];
  expandedKeys: Set<string>;
  onToggle: (key: string) => void;
  productByTerm: Record<string, string>;
  campaignToProduct: Record<string, string>;
  campSort: ReturnType<typeof useSort>;
  termsForCampaign: (campId: string) => Ads7dRow[];
  visibleCols: MeasureDef[];
  sqpVolumeByTerm: Record<string, number>;
  sqpDetailsByTerm: Record<string, any>;
  getSignal: (m: any, node?: any) => { type: keyof typeof ACTION_META; reason: string }[];
  minClicksFilter?: number | null;
}) {
  const getKey = (r: Ads7dRow, level: (typeof HIERARCHY_OPTIONS)[number]['id']): string => {
    if (level === 'portfolio') {
      const p = (r.portfolio_name || '').trim() || extractPortfolio(r.campaign_name || '');
      return p === 'TEENAGER' ? 'Other' : p || 'Other';
    }
    if (level === 'campaign') return r.campaign_id;
    if (level === 'search_term') return r.search_term || '';
    if (level === 'family') return extractFamilyFromCampaign(r.campaign_name || '');
    if (level === 'product') {
      const p = (r.product_short_name || '').trim();
      if (p) return p;
      const fromKwMap = r.search_term ? productByTerm[(r.search_term || '').toLowerCase().trim()] : null;
      if (fromKwMap) return fromKwMap;
      const fromCampaign = campaignToProduct[r.campaign_id || ''];
      if (fromCampaign) return fromCampaign;
      return '—';
    }
    if (level === 'collection') {
      return (r.parent_name || '').trim() || 'Other';
    }
    if (level === 'day') return r.week_start || '';
    if (level === 'week') return r.week_start || '';
    if (level === 'month') return (r.week_start || '').slice(0, 7);
    return '';
  };

  const { filters } = useFilters();
  type Node = { key: string; label: string; level: string; children: Node[]; rows: Ads7dRow[]; campaignIds?: Set<string>; metrics: { spend: number; sales: number; orders: number; clicks: number; conv_rate: number; cpc: number; roas: number; gross_roas: number; search_terms_count: number; sqp_volume: number; sqp_clicks: number; sqp_cart_adds: number; sqp_orders: number; sqp_organic_units: number; sqp_organic_pct: number; sqp_show_rate: number; spend_4w: number; orders_4w: number; clicks_4w: number; sales_4w: number; roas_4w: number; conv_rate_4w: number; spend_ly_peak: number; orders_ly_peak: number; sales_ly_peak: number; roas_ly_peak: number; sqp_volume_ly_peak: number; sqp_orders_ly_peak: number; } };
  // Index synthesized search-term rows by campaign once per data change, so buildTree
  // can look up a node's terms in O(1) instead of re-scanning the full searchTerms
  // array (up to ~100k rows) at every node — the cause of multi-second render freezes.
  const termsByCampaign = useMemo(() => {
    const m = new Map<string, Ads7dRow[]>();
    for (const t of searchTerms) {
      const arr = m.get(t.campaign_id);
      if (arr) arr.push(t);
      else m.set(t.campaign_id, [t]);
    }
    return m;
  }, [searchTerms]);
  const termsFor = (ids: Set<string>): Ads7dRow[] => {
    const out: Ads7dRow[] = [];
    for (const id of ids) {
      const arr = termsByCampaign.get(id);
      if (arr) for (const t of arr) out.push(t);
    }
    return out;
  };
  const buildTree = (rows: Ads7dRow[], levelIdx: number, _campaignIds?: Set<string>, sort: ReturnType<typeof useSort> = campSort, path: string[] = []): Node[] => {
    if (levelIdx >= hierarchy.length) return [];
    const level = hierarchy[levelIdx];
    const nextLevel = hierarchy[levelIdx + 1];
    const useCampaigns = level === 'portfolio' || level === 'family' || level === 'collection';
    const srcRows = useCampaigns ? rows.filter(r => r.row_type === 'campaign') : rows;
    const groups: Record<string, Ads7dRow[]> = {};
    for (const r of srcRows) {
      const k = getKey(r, level);
      if (!k) continue;
      if (!groups[k]) groups[k] = [];
      groups[k].push(r);
    }
    const nodes: Node[] = [];
    for (const [k, groupRows] of Object.entries(groups)) {
      // When keyword filter is active and this is a parent level (portfolio/family/collection/campaign),
      // use filtered search term rows for metric aggregation instead of campaign totals
      const ids = new Set(groupRows.map(r => r.campaign_id));
      const useTermMetrics = !!filters.keyword && (useCampaigns || level === 'campaign');
      const metricRows = useTermMetrics
        ? termsFor(ids)
        : groupRows;
      const spend = metricRows.reduce((s, r) => s + r.spend, 0);
      const sales = metricRows.reduce((s, r) => s + r.sales, 0);
      const orders = metricRows.reduce((s, r) => s + r.orders, 0);
      const clicks = metricRows.reduce((s, r) => s + r.clicks, 0);
      const cogs = groupRows.reduce((s, r) => s + (r.cogs ?? 0), 0);
      const search_terms_count = level === 'search_term'
        ? 1
        : level === 'product'
          ? new Set(groupRows.map(r => r.search_term).filter(Boolean)).size
          : groupRows.reduce((s, r) => s + (r.search_terms_count ?? 0), 0);
      let childRows: Ads7dRow[];
      if (nextLevel === 'search_term') {
        // Cap deep expansion: broad-match campaigns can have thousands of 90-day
        // search terms. Show the top spenders so expanding stays responsive (parent
        // metrics above still aggregate every term, so totals are unaffected).
        const allTerms = termsFor(ids);
        childRows = allTerms.length > 50
          ? [...allTerms].sort((a, b) => b.spend - a.spend).slice(0, 50)
          : allTerms;
      } else if (level === 'search_term' && nextLevel === 'campaign') {
        childRows = campaigns.filter(c => ids.has(c.campaign_id));
      } else {
        childRows = groupRows;
      }
      // For SQP aggregation: collect unique search terms from the search-term rows under these campaigns
      const sqpTermsForGroup = level === 'search_term'
        ? [k.toLowerCase().trim()]
        : [...new Set(termsFor(ids).map(t => (t.search_term || '').toLowerCase().trim()).filter(Boolean))];
      let sqp_volume = 0, sqp_clicks = 0, sqp_cart_adds = 0, sqp_orders = 0, sqp_ads_orders = 0, sqp_show_rate_sum = 0, sqp_show_rate_cnt = 0;
      let sqp_volume_ly = 0, sqp_orders_ly = 0;
      let spend_4w = 0, orders_4w = 0, clicks_4w = 0, sales_4w = 0, spend_ly_peak = 0, orders_ly_peak = 0, sales_ly_peak = 0;
      const seen = new Set<string>();
      for (const term of sqpTermsForGroup) {
        if (seen.has(term)) continue; seen.add(term);
        sqp_volume += lookupSqpVolume(sqpVolumeByTerm, term) ?? 0;
        const det = sqpDetailsByTerm[term];
        if (det) {
          sqp_clicks += det.clicks;
          sqp_cart_adds += det.cart_adds;
          sqp_orders += det.orders;
          sqp_ads_orders += det.ads_orders;
          sqp_show_rate_sum += det.show_rate_sum;
          sqp_show_rate_cnt += det.show_rate_cnt;
          sqp_volume_ly += det.volume_ly_peak || 0;
          sqp_orders_ly += det.orders_ly_peak || 0;
        }
      }
      for (const r of groupRows) {
        spend_4w += r.spend_4w || 0; orders_4w += r.orders_4w || 0; clicks_4w += r.clicks_4w || 0; sales_4w += r.sales_4w || 0;
        spend_ly_peak += r.spend_ly_peak || 0; orders_ly_peak += r.orders_ly_peak || 0; sales_ly_peak += r.sales_ly_peak || 0;
      }
      const sqp_organic_units = Math.max(0, sqp_orders - sqp_ads_orders);
      const sqp_organic_pct = sqp_orders > 0 ? (sqp_organic_units / sqp_orders) * 100 : 0;
      const sqp_show_rate = sqp_show_rate_cnt > 0 ? sqp_show_rate_sum / sqp_show_rate_cnt : 0;
      const metrics = {
        spend, sales, orders, clicks,
        conv_rate: clicks > 0 ? (orders * 100) / clicks : 0,
        cpc: clicks > 0 ? spend / clicks : 0,
        roas: spend > 0 ? (sales - cogs) / spend : 0,
        gross_roas: spend > 0 ? sales / spend : 0,
        search_terms_count,
        sqp_volume, sqp_clicks, sqp_cart_adds, sqp_orders, sqp_organic_units, sqp_organic_pct, sqp_show_rate,
        spend_4w, orders_4w, clicks_4w, sales_4w,
        roas_4w: spend_4w > 0 ? sales_4w / spend_4w : 0,
        conv_rate_4w: clicks_4w > 0 ? (orders_4w * 100) / clicks_4w : 0,
        spend_ly_peak, orders_ly_peak, sales_ly_peak,
        roas_ly_peak: spend_ly_peak > 0 ? sales_ly_peak / spend_ly_peak : 0,
        sqp_volume_ly_peak: sqp_volume_ly,
        sqp_orders_ly_peak: sqp_orders_ly,
      };
      // Build children lazily — only recurse for expanded nodes. Collapsed subtrees
      // are never rendered (renderRow gates child rows on isExp and has render-time
      // fallbacks), so eagerly building the entire tree every render wasted ~1.5s.
      const nodeKey = `${level}:${k}`;
      const isExpanded = expandedKeys.has([...path, nodeKey].join('\0'));
      const children = levelIdx + 1 < hierarchy.length && isExpanded
        ? buildTree(childRows, levelIdx + 1, ids, campSort, [...path, nodeKey])
        : [];
      const displayLabel = level === 'campaign' ? (groupRows[0]?.campaign_name || k) : k;
      nodes.push({ key: nodeKey, label: displayLabel, level, children, rows: groupRows, campaignIds: ids, metrics });
    }
    return sort.sorted(nodes, (n, k) => n.metrics[k as keyof typeof n.metrics]);
  };

  const initialRows = hierarchy.length > 0 && hierarchy[0] === 'search_term' ? searchTerms : campaigns;
  const buildTreeWithSort = (rows: Ads7dRow[], levelIdx: number, campaignIds?: Set<string>) =>
    buildTree(rows, levelIdx, campaignIds, campSort);
  const tree = useMemo(() => buildTreeWithSort(initialRows, 0), [campaigns, searchTerms, initialRows, hierarchy, productByTerm, campaignToProduct, campSort, sqpVolumeByTerm, expandedKeys]);

  const renderLevel = (level: string): string => {
    const o = HIERARCHY_OPTIONS.find(x => x.id === level);
    return o?.label || level;
  };

  const cellValues = (node: Node, m: any) => {
    const signals = getSignal(m, node);
    const actionCell = signals.length > 0 ? (
      <div className="flex flex-col gap-1 items-end pr-2">
        {signals.map((s, i) => (
          <Tip key={i} text={s.reason}>
             <Badge variant={ACTION_META[s.type]?.variant || 'zinc'} className="!text-[9px] cursor-help h-4 flex items-center">{ACTION_META[s.type]?.label || s.type}</Badge>
          </Tip>
        ))}
      </div>
    ) : null;

    return {
      label: node.label,
      sqp_volume: m.sqp_volume > 0 ? m.sqp_volume.toLocaleString() : '',
      sqp_clicks: m.sqp_clicks > 0 ? m.sqp_clicks.toLocaleString() : '',
      sqp_cart_adds: m.sqp_cart_adds > 0 ? m.sqp_cart_adds.toLocaleString() : '',
      sqp_orders: m.sqp_orders > 0 ? m.sqp_orders.toLocaleString() : '',
      sqp_organic_units: m.sqp_organic_units > 0 ? m.sqp_organic_units.toLocaleString() : '',
      sqp_organic_pct: m.sqp_orders > 0 ? fP(m.sqp_organic_pct) : '',
      sqp_show_rate: m.sqp_show_rate > 0 ? fP(m.sqp_show_rate) : '',
      spend_4w: fM(m.spend_4w),
      orders_4w: fOrd(m.orders_4w),
      roas_4w: <RoasBadge value={m.roas_4w} />,
      conv_rate_4w: fP(m.conv_rate_4w),
      spend_ly_peak: fM(m.spend_ly_peak),
      orders_ly_peak: fOrd(m.orders_ly_peak),
      roas_ly_peak: <RoasBadge value={m.roas_ly_peak} />,
      sqp_volume_ly_peak: m.sqp_volume_ly_peak > 0 ? m.sqp_volume_ly_peak.toLocaleString() : '',
      sqp_orders_ly_peak: m.sqp_orders_ly_peak > 0 ? m.sqp_orders_ly_peak.toLocaleString() : '',
      type: node.level === 'campaign' ? node.rows[0]?.campaign_type || '--' : '',
      spend: fM(m.spend),
      sales: fM(m.sales),
      orders: fOrd(m.orders),
      clicks: fClk(m.clicks),
      conv_rate: fP(m.conv_rate),
      cpc: fCpc(m.cpc),
      gross_roas: <RoasBadge value={m.gross_roas} />,
      roas: <RoasBadge value={m.roas} />,
      search_terms_count: m.search_terms_count > 0 ? m.search_terms_count : '—',
      action: actionCell,
    };
  };

  const renderRow = (node: Node, depth: number, path: string[]): React.ReactNode => {
    // Display-only filter: hide search_term nodes below min clicks threshold (aggregation unaffected)
    if (minClicksFilter != null && node.level === 'search_term' && node.metrics.clicks < minClicksFilter) return null;
    const fullKey = [...path, node.key].join('\0');
    const hasNextLevel = depth + 1 < hierarchy.length;
    const nextLevel = hierarchy[depth + 1];
    const hasChildren = node.level === 'campaign'
      ? termsForCampaign(node.rows[0]?.campaign_id || '').length > 0
      : (node.children.length > 0 || (hasNextLevel && node.rows.length > 0));
    const isExp = expandedKeys.has(fullKey);
    const m = node.metrics;
    const pl = depth * 12 + 12;
    const cells = cellValues(node, m);
    return (
      <Fragment key={fullKey}>
        <tr
          onClick={() => hasChildren && onToggle(fullKey)}
          className={`border-b border-border-faint hover:bg-white/[.02] ${hasChildren ? 'cursor-pointer' : ''} transition-colors`}
        >
          <td className="px-3 py-2 w-6" style={{ paddingLeft: pl }}>
            {hasChildren ? (isExp ? <ChevronDown size={12} className="text-faint" /> : <ChevronRight size={12} className="text-faint" />) : null}
          </td>
          {visibleCols.map(c => {
            const v = cells[c.id as keyof typeof cells];
            const right = ['sqp_volume', 'sqp_clicks', 'sqp_cart_adds', 'sqp_orders', 'sqp_organic_units', 'sqp_organic_pct', 'sqp_show_rate', 'spend', 'sales', 'orders', 'clicks', 'conv_rate', 'cpc', 'search_terms_count', 'spend_4w', 'orders_4w', 'roas_4w', 'conv_rate_4w', 'spend_ly_peak', 'orders_ly_peak', 'roas_ly_peak', 'sqp_volume_ly_peak', 'sqp_orders_ly_peak'].includes(c.id);
            const labelClass = c.id === 'label' ? 'font-semibold max-w-[250px] truncate' : '';
            const typeClass = c.id === 'type' || c.id === 'product' ? 'text-faint text-[10px]' : '';
            const orderClass = c.id === 'orders' ? (m.orders === 0 ? 'text-red-400' : 'text-emerald-400') : '';
            const spendClass = c.id === 'spend' ? 'font-semibold' : '';
            return (
              <td key={c.id} className={`px-3 py-2 ${right ? 'text-right font-mono' : ''} ${labelClass} ${typeClass} ${orderClass} ${spendClass} ${c.id === 'search_terms_count' ? 'text-faint' : ''}`} title={c.id === 'label' ? node.label : c.id === 'product' ? node.rows[0]?.product_short_name || '' : undefined}>
                {v}
              </td>
            );
          })}
        </tr>
        {isExp && node.level === 'search_term' && nextLevel === 'product' && node.children.length === 0 && node.rows.length > 0 && (() => {
          const byProduct: Record<string, Ads7dRow[]> = {};
          for (const r of node.rows) {
            const p = getKey(r, 'product');
            if (!byProduct[p]) byProduct[p] = [];
            byProduct[p].push(r);
          }
          return Object.entries(byProduct).map(([prod, prodRows], i) => {
            const m = prodRows.reduce((s, r) => ({
              spend: s.spend + r.spend,
              sales: s.sales + r.sales,
              orders: s.orders + r.orders,
              clicks: s.clicks + r.clicks,
              cogs: (s.cogs ?? 0) + (r.cogs ?? 0),
            }), { spend: 0, sales: 0, orders: 0, clicks: 0, cogs: 0 });
            const conv_rate = m.clicks > 0 ? (m.orders * 100) / m.clicks : 0;
            const cpc = m.clicks > 0 ? m.spend / m.clicks : 0;
            const roas = m.spend > 0 ? (m.sales - m.cogs) / m.spend : 0;
            const gross_roas = m.spend > 0 ? m.sales / m.spend : 0;
            const distinctTerms = new Set(prodRows.map(r => r.search_term).filter(Boolean)).size;
            const tCells: Record<string, ReactNode> = {
              label: prod,
              sqp_volume: '',
              sqp_clicks: '',
              sqp_cart_adds: '',
              sqp_orders: '',
              sqp_organic_units: '',
              sqp_organic_pct: '',
              sqp_show_rate: '',
              type: '',
              spend: fM(m.spend),
              sales: fM(m.sales),
              orders: fOrd(m.orders),
              clicks: fClk(m.clicks),
              conv_rate: fP(conv_rate),
              cpc: fCpc(cpc),
              gross_roas: <RoasBadge value={gross_roas} />,
              roas: <RoasBadge value={roas} />,
              search_terms_count: distinctTerms > 0 ? distinctTerms : '—',
            };
            return (
              <tr key={`${fullKey}-p-${i}`} className="border-b border-border-faint bg-inset">
                <td className="px-3 py-1 pl-8" />
                {visibleCols.map(col => {
                  const v = tCells[col.id];
                  const right = ['sqp_volume', 'sqp_clicks', 'sqp_cart_adds', 'sqp_orders', 'sqp_organic_units', 'sqp_organic_pct', 'sqp_show_rate', 'spend', 'sales', 'orders', 'clicks', 'conv_rate', 'cpc', 'search_terms_count'].includes(col.id);
                  const orderClass = col.id === 'orders' ? (m.orders === 0 ? 'text-red-400' : 'text-emerald-400') : '';
                  return (
                    <td key={col.id} className={`px-3 py-1 text-[11px] ${right ? 'text-right font-mono' : ''} ${col.id === 'label' ? 'font-medium max-w-[220px] truncate' : ''} ${col.id === 'type' || col.id === 'product' ? 'text-faint' : ''} ${orderClass} ${col.id === 'spend' ? 'font-semibold' : ''}`}>
                      {v}
                    </td>
                  );
                })}
              </tr>
            );
          });
        })()}
        {isExp && node.level === 'campaign' && node.children.length === 0 && (() => {
          const allTerms = termsForCampaign(node.rows[0]?.campaign_id || '');
          const terms = minClicksFilter != null ? allTerms.filter(t => t.clicks >= minClicksFilter) : allTerms;
          if (terms.length === 0) return null;
          return terms.slice(0, 50).map((t, i) => {
            const tSqpVol = lookupSqpVolume(sqpVolumeByTerm, t.search_term || '');
          const tSqpDet = sqpDetailsByTerm[(t.search_term || '').toLowerCase().trim()];
          const tOrganic = tSqpDet && tSqpDet.orders > 0 ? Math.max(0, tSqpDet.orders - tSqpDet.ads_orders) : 0;
          const tOrganicPct = tSqpDet && tSqpDet.orders > 0 ? (tOrganic / tSqpDet.orders) * 100 : 0;
            const tCells: Record<string, ReactNode> = {
              label: t.search_term,
              sqp_volume: tSqpVol != null ? tSqpVol.toLocaleString() : '',
              sqp_clicks: tSqpDet ? tSqpDet.clicks.toLocaleString() : '',
              sqp_cart_adds: tSqpDet ? tSqpDet.cart_adds.toLocaleString() : '',
              sqp_orders: tSqpDet ? tSqpDet.orders.toLocaleString() : '',
              sqp_organic_units: tSqpDet && tSqpDet.orders > 0 ? tOrganic.toLocaleString() : '',
              sqp_organic_pct: tSqpDet && tSqpDet.orders > 0 ? fP(tOrganicPct) : '',
              sqp_show_rate: tSqpDet?.show_rate_cnt ? fP(tSqpDet.show_rate_sum / tSqpDet.show_rate_cnt) : '',
              type: '',
              spend: fM(t.spend),
              sales: fM(t.sales),
              orders: fOrd(t.orders),
              clicks: fClk(t.clicks),
              conv_rate: fP(t.conv_rate),
              cpc: fCpc(t.cpc),
              gross_roas: <RoasBadge value={t.gross_roas} />,
              roas: <RoasBadge value={t.roas} />,
              search_terms_count: 1,
            };
            return (
              <tr key={`${fullKey}-t-${i}`} className="border-b border-border-faint bg-inset">
                <td className="px-3 py-1 pl-8" />
                {visibleCols.map(col => {
                  const v = tCells[col.id];
                  const right = ['sqp_volume', 'sqp_clicks', 'sqp_cart_adds', 'sqp_orders', 'sqp_organic_units', 'sqp_organic_pct', 'sqp_show_rate', 'spend', 'sales', 'orders', 'clicks', 'conv_rate', 'cpc', 'search_terms_count'].includes(col.id);
                  const orderClass = col.id === 'orders' ? (t.orders === 0 ? 'text-red-400' : 'text-emerald-400') : '';
                  return (
                    <td key={col.id} className={`px-3 py-1 text-[11px] ${right ? 'text-right font-mono' : ''} ${col.id === 'label' ? 'font-medium max-w-[220px] truncate' : ''} ${col.id === 'type' || col.id === 'product' ? 'text-faint' : ''} ${orderClass} ${col.id === 'spend' ? 'font-semibold' : ''}`}>
                      {v}
                    </td>
                  );
                })}
              </tr>
            );
          });
        })()}
        {isExp && node.children.length > 0 && node.children.map(c => renderRow(c, depth + 1, [...path, node.key]))}
      </Fragment>
    );
  };

  if (hierarchy.length === 0) return <Empty message="Select at least one hierarchy level" />;

  return (
    <div className="border border-border rounded-xl bg-card overflow-hidden" style={{ overflowX: 'auto' }}>
      <table className="w-full border-collapse text-xs">
        <thead><tr>
          <Th> </Th>
          {visibleCols.map(c => (
            ['label', 'type', 'product', 'search_terms_count'].includes(c.id)
              ? <Th key={c.id} right={!['label', 'type', 'product'].includes(c.id)} tip={c.tip}>{c.id === 'label' ? hierarchy.map(renderLevel).join(' → ') : c.label}</Th>
              : <SortTh key={c.id} k={c.id} sort={campSort.sort} toggle={campSort.toggle} right tip={c.tip}>{c.label}</SortTh>
          ))}
        </tr></thead>
        <tbody>
          {tree.map(n => renderRow(n, 0, []))}
        </tbody>
      </table>
    </div>
  );
}

/** Extract portfolio from campaign name (e.g. BOX-SP -> BOX, ME-VIDEO -> ME) */
function extractPortfolio(campaignName: string): string {
  const m = (campaignName || '').match(/^([A-Za-z]+)[-\s]/);
  return m ? m[1].toUpperCase() : (campaignName || '').split(/[\/-]/)[0]?.trim() || 'Other';
}

/** Extract family from campaign name for grouping */
function extractFamilyFromCampaign(campaignName: string): string {
  const cn = (campaignName || '').toLowerCase();
  if (cn.includes('box')) return 'Lollibox';
  if (cn.includes('me') || cn.includes('mint') || cn.includes('lollime')) return 'LolliME';
  if (cn.includes('bottle') || cn.includes('truth')) return 'Bottle';
  if (cn.includes('fresh')) return 'Fresh';
  if (cn.includes('brand')) return 'Brand';
  return 'Other';
}

/** Product name looks like a real product (e.g. "Fresh in Beige") vs person name (e.g. "Jenna") */
function looksLikeProduct(s: string): boolean {
  const lower = s.toLowerCase();
  if (/^[A-Z][a-z]+$/.test(s.trim())) return false; // single word like "Jenna"
  if (/gift for /i.test(lower)) return false;
  if (/fresh|beige|mint|truth|bottle|box|hunter|skin/i.test(lower)) return true;
  if (lower.includes(' in ') || lower.includes(', ')) return true; // "Fresh in Beige", "Hunter, Gift for Girl"
  return s.trim().length > 8; // longer strings tend to be product descriptors
}

/** Extract product: prefer product_short_name from ads data, then campaign-derived, then keyword_product_map.
 * product_short_name (from DIM_PRODUCT via most_advertised_asin) is the most accurate when available. */
function extractProduct(campaignName: string, searchTerm: string, productByTerm: Record<string, string>, productShortName?: string | null): string {
  if ((productShortName || '').trim()) return productShortName!.trim();
  const inParens = campaignName.match(/\(([^)]+)\)/)?.[1]?.trim();
  if (inParens && looksLikeProduct(inParens)) return inParens;
  const beforeSlash = campaignName.split('/')[0]?.trim();
  if (beforeSlash) {
    const base = beforeSlash.replace(/-SP|-SB|-VIDEO$/i, '').trim();
    if (base) return base;
  }
  const fromCampaign = inParens || campaignName;
  if (fromCampaign) return fromCampaign;
  const fromKwMap = searchTerm ? productByTerm[(searchTerm || '').toLowerCase().trim()] : null;
  return fromKwMap || '';
}

/** SQP Amazon volume for past month (last 4 weeks) by search term */
function sqpVolumeByTermPastMonth(sqp: SqpWeeklyRow[]): Record<string, number> {
  const weeks = [...new Set(sqp.map(r => r.week_start || '').filter(Boolean))].sort().slice(-4);
  const byTermWeek: Record<string, Record<string, number>> = {};
  for (const r of sqp) {
    const w = r.week_start || '';
    if (!weeks.includes(w)) continue;
    const term = (r.search_term || '').toLowerCase().trim();
    if (!term) continue;
    if (!byTermWeek[term]) byTermWeek[term] = {};
    byTermWeek[term][w] = (byTermWeek[term][w] || 0) + (r.amazon_impressions || 0);
  }
  const out: Record<string, number> = {};
  for (const term of Object.keys(byTermWeek)) {
    out[term] = Object.values(byTermWeek[term]).reduce((a, b) => a + b, 0);
  }
  return out;
}

/** Lookup SQP volume - exact match first, then try shorter prefixes (e.g. "teen girl gifts trendy" -> "teen girl gifts") */
function lookupSqpVolume(vol: Record<string, number>, term: string): number | undefined {
  const key = term.toLowerCase().trim();
  if (vol[key] != null) return vol[key];
  const words = key.split(/\s+/).filter(Boolean);
  for (let i = words.length - 1; i >= 2; i--) {
    const prefix = words.slice(0, i).join(' ');
    if (vol[prefix] != null) return vol[prefix];
  }
  return undefined;
}

/** Build search_term -> product_short_name from keyword_product_map + sqp_weekly (prefer kw map) */
function productByTermMap(kwMap: KeywordMapRow[], sqp: SqpWeeklyRow[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (const k of kwMap) {
    const term = (k.search_term || '').toLowerCase().trim();
    if (!term) continue;
    if (!out[term] || (k.spend_60d || 0) > 0) out[term] = k.product_short_name || '';
  }
  for (const r of sqp) {
    const term = (r.search_term || '').toLowerCase().trim();
    if (!term || out[term]) continue;
    out[term] = r.product_short_name || r.asin || '';
  }
  return out;
}

/** Hierarchy: search_term -> product -> campaign */
function HierarchicalTermsTable({ terms, highlight, sqpVolume: sqpVolumeProp, sqpDetails = {}, sqpWeekly, keywordProductMap, visibleCols, getSignal }: { terms: Ads7dRow[]; highlight: 'best' | 'drain' | 'warn'; sqpVolume?: Record<string, number>; sqpDetails?: Record<string, any>; sqpWeekly: SqpWeeklyRow[]; keywordProductMap: KeywordMapRow[]; visibleCols: MeasureDef[]; getSignal: (m: any, node?: any) => { type: keyof typeof ACTION_META; reason: string }[] }) {
  const [expandedTerms, setExpandedTerms] = useState<Set<string>>(new Set());
  const [expandedProducts, setExpandedProducts] = useState<Set<string>>(new Set());
  const s = useSort('spend');

  const sqpVolumeFromWeekly = useMemo(() => sqpVolumeByTermPastMonth(sqpWeekly), [sqpWeekly]);
  const sqpVolume = sqpVolumeProp && Object.keys(sqpVolumeProp).length > 0 ? sqpVolumeProp : sqpVolumeFromWeekly;
  const productByTerm = useMemo(() => productByTermMap(keywordProductMap, sqpWeekly), [keywordProductMap, sqpWeekly]);

  const hierarchy = useMemo(() => {
    const byTerm: Record<string, Record<string, Ads7dRow[]>> = {};
    for (const t of terms) {
      const term = t.search_term || '';
      const product = extractProduct(t.campaign_name || '', term, productByTerm, t.product_short_name);
      if (!byTerm[term]) byTerm[term] = {};
      if (!byTerm[term][product]) byTerm[term][product] = [];
      byTerm[term][product].push(t);
    }
    const termTotals: Record<string, { spend: number; sales: number; orders: number; clicks: number; impressions: number; cogs: number; conv_rate: number; cpc: number; roas: number; gross_roas: number }> = {};
    for (const term of Object.keys(byTerm)) {
      let spend = 0, orders = 0, sales = 0, clicks = 0, impressions = 0, cogs = 0;
      for (const rows of Object.values(byTerm[term])) {
        for (const r of rows) {
          spend += r.spend;
          orders += r.orders;
          sales += r.sales;
          clicks += r.clicks;
          impressions += r.impressions;
          cogs += r.cogs ?? 0;
        }
      }
      termTotals[term] = {
        spend,
        sales,
        orders,
        clicks,
        impressions,
        cogs,
        conv_rate: clicks > 0 ? (orders * 100) / clicks : 0,
        cpc: clicks > 0 ? spend / clicks : 0,
        roas: spend > 0 ? (sales - cogs) / spend : 0,
        gross_roas: spend > 0 ? sales / spend : 0,
      };
    }
    return { byTerm, termTotals };
  }, [terms]);

  const sortedTerms = useMemo(() => {
    const termRows = Object.keys(hierarchy.byTerm).map(term => ({
      term,
      ...hierarchy.termTotals[term],
      sqp_volume: lookupSqpVolume(sqpVolume, term || '') ?? 0,
    }));
    return s.sorted(termRows, (r, k) => r[k as keyof typeof r]).map(r => r.term);
  }, [hierarchy, s, sqpVolume]);

  const toggleTerm = (term: string) => setExpandedTerms(p => { const n = new Set(p); n.has(term) ? n.delete(term) : n.add(term); return n; });
  const toggleProduct = (key: string) => setExpandedProducts(p => { const n = new Set(p); n.has(key) ? n.delete(key) : n.add(key); return n; });

  if (!terms.length) return <Empty message="No matching terms" />;

  const filtered = visibleCols.filter(c => c.id !== 'action' || highlight === 'drain');
  const cols = filtered.length > 0 ? filtered : visibleCols;
  const volTip = 'Last month Amazon search volume (SQP)';
  const renderCell = (id: string, content: ReactNode, className = '') => (
    <td key={id} className={className}>{content}</td>
  );
  return (
    <div className="border border-border rounded-xl bg-card overflow-hidden" style={{ maxHeight: 500, overflowY: 'auto', overflowX: 'auto' }}>
      <table className="w-full border-collapse text-xs">
        <thead><tr>
          {cols.map(c => (
            <SortTh key={c.id} k={c.id} sort={s.sort} toggle={s.toggle} right={c.id !== 'label' && c.id !== 'action'} tip={c.tip || (c.id === 'sqp_volume' ? volTip : undefined)}>{c.label}</SortTh>
          ))}
        </tr></thead>
        <tbody>
          {sortedTerms.map(term => {
            const tot = hierarchy.termTotals[term];
            const isTermExp = expandedTerms.has(term);
            const products = Object.entries(hierarchy.byTerm[term]).sort(([, a], [, b]) => b.reduce((s, r) => s + r.spend, 0) - a.reduce((s, r) => s + r.spend, 0));
            const vol = lookupSqpVolume(sqpVolume, term || '') ?? 0;
            const det = sqpDetails[(term || '').toLowerCase().trim()];
            const detOrganic = det && det.orders > 0 ? Math.max(0, det.orders - det.ads_orders) : 0;
            const detOrganicPct = det && det.orders > 0 ? (detOrganic / det.orders) * 100 : 0;
            const termCells: Record<string, ReactNode> = {
              label: <span className="inline-flex items-center gap-1">{isTermExp ? <ChevronDown size={12} className="text-faint shrink-0" /> : <ChevronRight size={12} className="text-faint shrink-0" />}<span className="font-semibold text-blue-400" title={term}>{term}</span></span>,
              sqp_volume: vol > 0 ? vol.toLocaleString() : '',
              sqp_clicks: det ? det.clicks.toLocaleString() : '',
              sqp_cart_adds: det ? det.cart_adds.toLocaleString() : '',
              sqp_orders: det ? det.orders.toLocaleString() : '',
              sqp_organic_units: det && det.orders > 0 ? detOrganic.toLocaleString() : '',
              sqp_organic_pct: det && det.orders > 0 ? fP(detOrganicPct) : '',
              sqp_show_rate: det?.show_rate_cnt ? fP(det.show_rate_sum / det.show_rate_cnt) : '',
              spend: fM(tot.spend),
              sales: fM(tot.sales),
              orders: tot.orders,
              clicks: fClk(tot.clicks),
              impressions: tot.impressions.toLocaleString(),
              conv_rate: fP(tot.conv_rate),
              cpc: fCpc(tot.cpc),
              gross_roas: <RoasBadge value={tot.gross_roas} />,
              roas: <RoasBadge value={tot.roas} />,
              action: getSignal(tot, { level: 'search_term', key: term }).length > 0 ? (
                <div className="flex flex-col gap-1 items-end pr-2">
                  {getSignal(tot, { level: 'search_term', key: term }).map((s, i) => (
                    <Tip key={i} text={s.reason}>
                       <Badge variant={ACTION_META[s.type]?.variant || 'zinc'} className="!text-[9px] cursor-help h-4 flex items-center">{ACTION_META[s.type]?.label || s.type}</Badge>
                    </Tip>
                  ))}
                </div>
              ) : null,
            };
            return (
              <Fragment key={term}>
                <tr className="border-b border-border-faint hover:bg-white/[.02] cursor-pointer" onClick={() => toggleTerm(term)}>
                  {cols.map(c => {
                    const v = termCells[c.id];
                    const right = ['sqp_volume', 'sqp_clicks', 'sqp_cart_adds', 'sqp_orders', 'sqp_organic_units', 'sqp_organic_pct', 'sqp_show_rate', 'spend', 'sales', 'orders', 'clicks', 'impressions', 'conv_rate', 'cpc'].includes(c.id);
                    let cls = 'px-3 py-2';
                    if (right) cls += ' text-right font-mono';
                    if (c.id === 'orders') cls += tot.orders === 0 ? ' text-red-400' : ' text-emerald-400';
                    if (c.id === 'spend') cls += ' font-semibold';
                    return renderCell(c.id, v, cls);
                  })}
                </tr>
                {isTermExp && products.map(([product, rows]) => {
                  const prodSpend = rows.reduce((s, r) => s + r.spend, 0);
                  const prodOrders = rows.reduce((s, r) => s + r.orders, 0);
                  const prodSales = rows.reduce((s, r) => s + r.sales, 0);
                  const prodCogs = rows.reduce((s, r) => s + (r.cogs ?? 0), 0);
                  const prodGrossRoas = prodSpend > 0 ? prodSales / prodSpend : 0;
                  const prodRoas = prodSpend > 0 ? (prodSales - prodCogs) / prodSpend : 0;
                  const pKey = `${term}\0${product}`;
                  const isProdExp = expandedProducts.has(pKey);
                  const prodCells: Record<string, ReactNode> = {
                    label: <span className="inline-flex items-center gap-1">{isProdExp ? <ChevronDown size={11} className="text-faint shrink-0" /> : <ChevronRight size={11} className="text-faint shrink-0" />}<span className="text-[11px] text-subtle" title={product}>{product}</span></span>,
                    sqp_volume: '',
                    sqp_clicks: '',
                    sqp_cart_adds: '',
                    sqp_orders: '',
                    sqp_organic_units: '',
                    sqp_organic_pct: '',
                    sqp_show_rate: '',
                    spend: fM(prodSpend),
                    sales: fM(prodSales),
                    orders: prodOrders,
                    clicks: '',
                    impressions: '',
                    conv_rate: '',
                    cpc: '',
                    gross_roas: <RoasBadge value={prodGrossRoas} />,
                    roas: <RoasBadge value={prodRoas} />,
                    action: highlight === 'drain' ? null : undefined,
                  };
                  return (
                    <Fragment key={pKey}>
                      <tr className="border-b border-border-faint hover:bg-white/[.02] cursor-pointer bg-inset" onClick={e => { e.stopPropagation(); toggleProduct(pKey); }}>
                        {cols.map(c => {
                          const v = prodCells[c.id];
                          const right = ['sqp_volume', 'sqp_clicks', 'sqp_cart_adds', 'sqp_orders', 'sqp_organic_units', 'sqp_organic_pct', 'sqp_show_rate', 'spend', 'sales', 'orders', 'clicks', 'impressions', 'conv_rate', 'cpc'].includes(c.id);
                          let cls = 'px-3 py-1.5 text-[11px]';
                          if (c.id === 'label') cls += ' pl-8';
                          if (right) cls += ' text-right font-mono';
                          if (c.id === 'orders') cls += prodOrders === 0 ? ' text-red-400' : ' text-emerald-400';
                          return renderCell(c.id, v, cls);
                        })}
                      </tr>
                      {isProdExp && rows.map((t, i) => {
                        const rowSqpVol = lookupSqpVolume(sqpVolume, t.search_term || '');
                        const rowSqpDet = sqpDetails[(t.search_term || '').toLowerCase().trim()];
                        const rowOrg = rowSqpDet && rowSqpDet.orders > 0 ? Math.max(0, rowSqpDet.orders - rowSqpDet.ads_orders) : 0;
                        const rowOrgPct = rowSqpDet && rowSqpDet.orders > 0 ? (rowOrg / rowSqpDet.orders) * 100 : 0;
                        const rowCells: Record<string, ReactNode> = {
                          label: t.campaign_name,
                          sqp_volume: rowSqpVol != null ? rowSqpVol.toLocaleString() : '',
                          sqp_clicks: rowSqpDet ? rowSqpDet.clicks.toLocaleString() : '',
                          sqp_cart_adds: rowSqpDet ? rowSqpDet.cart_adds.toLocaleString() : '',
                          sqp_orders: rowSqpDet ? rowSqpDet.orders.toLocaleString() : '',
                          sqp_organic_units: rowSqpDet && rowSqpDet.orders > 0 ? rowOrg.toLocaleString() : '',
                          sqp_organic_pct: rowSqpDet && rowSqpDet.orders > 0 ? fP(rowOrgPct) : '',
                          sqp_show_rate: rowSqpDet?.show_rate_cnt ? fP(rowSqpDet.show_rate_sum / rowSqpDet.show_rate_cnt) : '',
                          spend: fM(t.spend),
                          sales: fM(t.sales),
                          orders: t.orders,
                          clicks: fClk(t.clicks),
                          impressions: t.impressions.toLocaleString(),
                          conv_rate: fP(t.conv_rate),
                          cpc: fCpc(t.cpc),
                          gross_roas: <RoasBadge value={t.gross_roas} />,
                          roas: <RoasBadge value={t.roas} />,
                          action: highlight === 'drain' ? <Badge variant="red" className="!text-[9px]">Negate</Badge> : null,
                        };
                        return (
                          <tr key={i} className="border-b border-zinc-800/10 hover:bg-white/[.02] bg-inset">
                            {cols.map(c => {
                              const v = rowCells[c.id];
                              const right = ['sqp_volume', 'sqp_clicks', 'sqp_cart_adds', 'sqp_orders', 'sqp_organic_units', 'sqp_organic_pct', 'sqp_show_rate', 'spend', 'sales', 'orders', 'clicks', 'impressions', 'conv_rate', 'cpc'].includes(c.id);
                              let cls = 'px-3 py-1 text-[11px]';
                              if (c.id === 'label') cls += ' pl-14 text-faint max-w-[220px] truncate';
                              if (right) cls += ' text-right font-mono';
                              if (c.id === 'spend') cls += ' font-semibold';
                              if (c.id === 'orders') cls += t.orders === 0 ? ' text-red-400' : ' text-emerald-400';
                              return renderCell(c.id, v, cls);
                            })}
                          </tr>
                        );
                      })}
                    </Fragment>
                  );
                })}
              </Fragment>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function TermsTable({ terms, highlight, visibleCols, sqpVolume = {}, sqpDetails = {}, getSignal }: { terms: Ads7dRow[]; highlight: 'best' | 'drain' | 'warn'; visibleCols: MeasureDef[]; sqpVolume?: Record<string, number>; sqpDetails?: Record<string, any>; getSignal: (m: any, node?: any) => { type: keyof typeof ACTION_META; reason: string }[] }) {
  const s = useSort('spend');
  if (!terms.length) return <Empty message="No matching terms" />;
  const filtered = visibleCols.filter(c => c.id !== 'action' || highlight === 'drain');
  const cols = filtered.length > 0 ? filtered : visibleCols;
  const volTip = 'Amazon search volume last 4 weeks (SQP)';
  return (
    <div className="border border-border rounded-xl bg-card overflow-hidden" style={{ maxHeight: 400, overflowY: 'auto', overflowX: 'auto' }}>
      <table className="w-full border-collapse text-xs" style={{ minWidth: cols.length * 100 }}>
        <thead><tr>
          {cols.map(c => (
            <SortTh key={c.id} k={c.id} sort={s.sort} toggle={s.toggle} right={!['search_term', 'campaign_name', 'action'].includes(c.id)} tip={c.tip || (c.id === 'sqp_volume' ? volTip : undefined)}>{c.label}</SortTh>
          ))}
        </tr></thead>
        <tbody>
          {s.sorted(terms).map((t, i) => {
            const volVal = lookupSqpVolume(sqpVolume, t.search_term || '');
            const det = sqpDetails[(t.search_term || '').toLowerCase().trim()];
            const orgOrders = det && det.orders > 0 ? Math.max(0, det.orders - det.ads_orders) : 0;
            const orgPct = det && det.orders > 0 ? (orgOrders / det.orders) * 100 : 0;
            const cells: Record<string, ReactNode> = {
              search_term: <td key="search_term" className="px-3 py-2 font-semibold text-blue-400 max-w-[200px] truncate" title={t.search_term || ''}>{t.search_term}</td>,
              campaign_name: <td key="campaign_name" className="px-3 py-2 text-[10px] text-faint max-w-[160px] truncate" title={t.campaign_name}>{t.campaign_name}</td>,
              spend: <td key="spend" className="px-3 py-2 text-right font-mono font-semibold">{fM(t.spend)}</td>,
              orders: <td key="orders" className={`px-3 py-2 text-right font-mono ${t.orders === 0 ? 'text-red-400' : 'text-emerald-400'}`}>{t.orders}</td>,
              clicks: <td key="clicks" className="px-3 py-2 text-right font-mono">{fClk(t.clicks)}</td>,
              impressions: <td key="impressions" className="px-3 py-2 text-right font-mono text-faint">{t.impressions.toLocaleString()}</td>,
              conv_rate: <td key="conv_rate" className="px-3 py-2 text-right font-mono">{fP(t.conv_rate)}</td>,
              cpc: <td key="cpc" className="px-3 py-2 text-right font-mono">{fCpc(t.cpc)}</td>,
              gross_roas: <td key="gross_roas" className="px-3 py-2"><RoasBadge value={t.gross_roas} /></td>,
              roas: <td key="roas" className="px-3 py-2"><RoasBadge value={t.roas} /></td>,
              sqp_volume: <td key="sqp_volume" className="px-3 py-2 text-right font-mono" title={volTip}>{volVal != null ? volVal.toLocaleString() : ''}</td>,
              sqp_clicks: <td key="sqp_clicks" className="px-3 py-2 text-right font-mono">{det ? det.clicks.toLocaleString() : ''}</td>,
              sqp_cart_adds: <td key="sqp_cart_adds" className="px-3 py-2 text-right font-mono">{det ? det.cart_adds.toLocaleString() : ''}</td>,
              sqp_orders: <td key="sqp_orders" className="px-3 py-2 text-right font-mono">{det ? det.orders.toLocaleString() : ''}</td>,
              sqp_organic_units: <td key="sqp_organic_units" className="px-3 py-2 text-right font-mono">{det && det.orders > 0 ? orgOrders.toLocaleString() : ''}</td>,
              sqp_organic_pct: <td key="sqp_organic_pct" className="px-3 py-2 text-right font-mono">{det && det.orders > 0 ? fP(orgPct) : ''}</td>,
              sqp_show_rate: <td key="sqp_show_rate" className="px-3 py-2 text-right font-mono">{det?.show_rate_cnt ? fP(det.show_rate_sum / det.show_rate_cnt) : ''}</td>,
              action: <td key="action" className="px-3 py-2">
                 {getSignal(t).length > 0 && (
                   <div className="flex flex-col gap-1 items-end">
                     {getSignal(t).map((s, i) => (
                       <Tip key={i} text={s.reason}>
                         <Badge variant={ACTION_META[s.type]?.variant || 'zinc'} className="!text-[9px] cursor-help h-4 flex items-center">{ACTION_META[s.type]?.label || s.type}</Badge>
                       </Tip>
                     ))}
                   </div>
                 )}
              </td>,
            };
            return (
            <tr key={i} className="border-b border-border-faint last:border-b-0 hover:bg-white/[.02]">
                {cols.map(col => cells[col.id])}
            </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

/* ─── Ads Trend Chart with dynamic measure selector ─── */
const ADS_TREND_MEASURES = [
  { key: 'spend', label: 'Ads Spend', color: '#ef4444', fmt: fM, type: 'bar' as const, axis: 'left' as const },
  { key: 'sales', label: 'Ads Sales', color: '#3b82f6', fmt: fM, type: 'bar' as const, axis: 'left' as const },
  { key: 'net_profit', label: 'Ads Net Profit', color: '#10b981', fmt: fM, type: 'bar' as const, axis: 'left' as const },
  { key: 'orders', label: 'Ads Orders', color: '#22c55e', fmt: fOrd, type: 'bar' as const, axis: 'left' as const },
  { key: 'clicks', label: 'Ads Clicks', color: '#8b5cf6', fmt: fClk, type: 'bar' as const, axis: 'left' as const },
  { key: 'impressions', label: 'Ads Impr', color: '#64748b', fmt: (v: number) => v >= 1000 ? `${(v / 1000).toFixed(0)}K` : String(v), type: 'bar' as const, axis: 'left' as const },
  { key: 'roas', label: 'Ads ROAS', color: '#a855f7', fmt: fR, type: 'bar' as const, axis: 'right' as const },
  { key: 'net_roas', label: 'Ads Net ROAS', color: '#06b6d4', fmt: fR, type: 'bar' as const, axis: 'right' as const },
  { key: 'cpc', label: 'Ads CPC', color: '#f59e0b', fmt: fCpc, type: 'bar' as const, axis: 'right' as const },
  { key: 'conv_rate', label: 'Ads CVR', color: '#14b8a6', fmt: fP, type: 'bar' as const, axis: 'right' as const },
  { key: 'ctr', label: 'Ads CTR', color: '#fb923c', fmt: fP, type: 'bar' as const, axis: 'right' as const },
] as const;

function AdsTrendChart({ rawRows, famMatch, expCampaignIds, periodTrend, holidays, perfMaxDate = '' }: {
  rawRows: Ads7dRow[];
  famMatch: string[] | null;
  expCampaignIds: Set<string> | null;
  periodTrend: number;
  holidays: HolidayRow[];
  perfMaxDate?: string;
}) {
  const [active, setActive] = useState<Set<string>>(new Set(['net_profit']));
  const [dailyRows, setDailyRows] = useState<Ads7dRow[] | null>(null);
  const [dailyLoading, setDailyLoading] = useState(false);
  const toggle = (key: string) => setActive(prev => {
    const next = new Set(prev);
    next.has(key) ? next.delete(key) : next.add(key);
    return next.size > 0 ? next : prev;
  });

  const { filters } = useFilters();
  const periodMode = filters.periodMode || 'weeks';
  const useDaily = periodMode === 'date';

  // Lazy-load daily data from Cube when entering date mode
  useEffect(() => {
    if (!useDaily || dailyRows) return;
    const CUBE_API = import.meta.env.VITE_CUBE_API_URL || (import.meta.env.DEV ? 'http://localhost:4000' : '');
    if (!CUBE_API) return;
    let cancelled = false;
    setDailyLoading(true);
    (async () => {
      try {
        let retries = 0;
        while (retries < 15) {
          const token = localStorage.getItem('dashboard_token');
          const headers: Record<string, string> = { 'Content-Type': 'application/json' };
          if (token) headers['Authorization'] = `Bearer ${token}`;

          const res = await fetch(`${CUBE_API}/cubejs-api/v1/load`, {
            method: 'POST',
            headers,
            body: JSON.stringify({ query: {
              measures: ['Ads.spend', 'Ads.orders', 'Ads.clicks', 'Ads.impressions', 'Ads.sales', 'Ads.cogs', 'Ads.grossProfit'],
              timeDimensions: [{ dimension: 'Ads.date', granularity: 'day', dateRange: 'Last 180 days' }],
              filters: [{ member: 'Ads.spend', operator: 'gt', values: ['0'] }],
              order: { 'Ads.date': 'asc' },
              limit: 5000,
            }}),
          });
          if (!res.ok) break;
          const json = await res.json();
          if (json.error === 'Continue wait') { retries++; await new Promise(r => setTimeout(r, 2000)); continue; }
          if (json.error) break;
          if (!cancelled) {
            const rows: Ads7dRow[] = (json.data ?? []).map((r: Record<string, unknown>) => {
              const dateStr = r['Ads.date'] ? String(r['Ads.date']).slice(0, 10) : '';
              const cogs = Number(r['Ads.cogs'] ?? 0);
              const grossProfit = r['Ads.grossProfit'] != null ? Number(r['Ads.grossProfit']) : null;
              return {
                row_type: 'campaign' as const,
                date: dateStr, week_start: '', campaign_id: 'ALL', campaign_name: '',
                campaign_type: null, search_term: null,
                spend: Number(r['Ads.spend'] ?? 0), orders: Number(r['Ads.orders'] ?? 0),
                clicks: Number(r['Ads.clicks'] ?? 0), impressions: Number(r['Ads.impressions'] ?? 0),
                sales: Number(r['Ads.sales'] ?? 0), cogs, gross_profit: grossProfit,
                cpc: 0, conv_rate: 0, roas: 0, search_terms_count: null,
              };
            });
            setDailyRows(rows);
          }
          break;
        }
      } catch (e) { console.warn('[AdsTrend] daily fetch failed:', e); }
      if (!cancelled) setDailyLoading(false);
    })();
    return () => { cancelled = true; };
  }, [useDaily, dailyRows]);

  const data = useMemo(() => {
    const sourceRows = useDaily ? (dailyRows || []) : rawRows;
    let adsRows = sourceRows;
    if (!useDaily) {
      if (famMatch) adsRows = adsRows.filter(r => famMatch.some(p => (r.campaign_name || '').toLowerCase().includes(p)));
      if (expCampaignIds) adsRows = adsRows.filter(r => expCampaignIds.has(r.campaign_id));
      if (filters.keyword) adsRows = adsRows.filter(r => r.row_type === 'search_term' && r.search_term === filters.keyword);
    }

    // Determine grouping key
    const getGroupKey = (r: Ads7dRow): string => {
      if (useDaily) return r.date || '';
      const w = r.week_start || '';
      if (!w) return '';
      if (periodMode === 'month') return w.slice(0, 7);
      if (periodMode === 'year') return w.slice(0, 4);
      return w;
    };

    const byKeyPeriod: Record<string, { spend: number; orders: number; sales: number; clicks: number; impressions: number; gross_profit: number; cogs: number }> = {};
    const campRowSeen = new Set<string>();
    for (const r of adsRows) {
      const p = getGroupKey(r);
      if (!p) continue;
      const ck = useDaily ? p : `${r.campaign_id}|${p}`;
      if (r.row_type === 'campaign') {
        if (!byKeyPeriod[ck]) byKeyPeriod[ck] = { spend: 0, orders: 0, sales: 0, clicks: 0, impressions: 0, gross_profit: 0, cogs: 0 };
        byKeyPeriod[ck].spend += r.spend; byKeyPeriod[ck].orders += r.orders;
        byKeyPeriod[ck].sales += r.sales; byKeyPeriod[ck].clicks += r.clicks;
        byKeyPeriod[ck].impressions += r.impressions; byKeyPeriod[ck].gross_profit += (r.gross_profit ?? 0);
        byKeyPeriod[ck].cogs += (r.cogs ?? 0);
        campRowSeen.add(ck);
      } else if (!campRowSeen.has(ck)) {
        if (!byKeyPeriod[ck]) byKeyPeriod[ck] = { spend: 0, orders: 0, sales: 0, clicks: 0, impressions: 0, gross_profit: 0, cogs: 0 };
        byKeyPeriod[ck].spend += r.spend; byKeyPeriod[ck].orders += r.orders;
        byKeyPeriod[ck].sales += r.sales; byKeyPeriod[ck].clicks += r.clicks;
        byKeyPeriod[ck].impressions += r.impressions; byKeyPeriod[ck].gross_profit += (r.gross_profit ?? 0);
        byKeyPeriod[ck].cogs += (r.cogs ?? 0);
      }
    }

    const byPeriod: Record<string, { spend: number; orders: number; sales: number; clicks: number; impressions: number; gross_profit: number; cogs: number }> = {};
    for (const [key, d] of Object.entries(byKeyPeriod)) {
      const p = useDaily ? key : key.split('|')[1];
      if (!byPeriod[p]) byPeriod[p] = { spend: 0, orders: 0, sales: 0, clicks: 0, impressions: 0, gross_profit: 0, cogs: 0 };
      byPeriod[p].spend += d.spend; byPeriod[p].orders += d.orders;
      byPeriod[p].sales += d.sales; byPeriod[p].clicks += d.clicks;
      byPeriod[p].impressions += d.impressions; byPeriod[p].gross_profit += d.gross_profit;
      byPeriod[p].cogs += d.cogs;
    }

    const formatLabel = (key: string): string => {
      if (useDaily) {
        const d = new Date(key + 'T00:00:00');
        return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
      }
      if (periodMode === 'month') return key;
      if (periodMode === 'year') return key;
      return weekRangeLabelCapped(key, perfMaxDate);
    };

    const sliceCount = periodTrend || 4;
    let sorted = Object.entries(byPeriod)
      .sort(([a], [b]) => a.localeCompare(b));

    if (useDaily) {
      // Daily mode: show 7 days in the past and up to 7 in the future from today
      const todayStr = new Date().toISOString().slice(0, 10);
      const past = sorted.filter(([p]) => p <= todayStr).slice(-7);
      const future = sorted.filter(([p]) => p > todayStr).slice(0, 7);
      sorted = [...past, ...future];
      // Filter out zero-spend days to avoid empty bars
      sorted = sorted.filter(([, d]) => d.spend > 0 || d.orders > 0);
    } else {
      const keys = sorted.map(([k]) => k);
      const keepKeys = new Set(getPeriodsToInclude(filters.specificPeriod, periodMode as any, keys, sliceCount));
      sorted = sorted.filter(([k]) => keepKeys.has(k));
    }

    return sorted
      .map(([p, d]) => ({
        week: formatLabel(p),
        weekKey: p,
        ...d,
        net_profit: d.gross_profit !== 0 ? d.gross_profit - d.spend : d.sales - d.cogs - d.spend,
        cpc: d.clicks > 0 ? d.spend / d.clicks : 0,
        roas: d.spend > 0 ? d.sales / d.spend : 0,
        net_roas: d.spend > 0 ? (d.gross_profit !== 0 ? d.gross_profit / d.spend : (d.sales - d.cogs) / d.spend) : 0,
        conv_rate: d.clicks > 0 ? (d.orders * 100) / d.clicks : 0,
        ctr: d.impressions > 0 ? (d.clicks * 100) / d.impressions : 0,
      }));
  }, [rawRows, dailyRows, famMatch, expCampaignIds, periodTrend, filters.keyword, filters.specificPeriod, periodMode, useDaily]);

  const activeMeasures = ADS_TREND_MEASURES.filter(m => active.has(m.key));
  const trendTitle = useDaily ? 'Daily Ads Trend' : periodMode === 'month' ? 'Monthly Ads Trend' : periodMode === 'quarter' ? 'Quarterly Ads Trend' : periodMode === 'year' ? 'Yearly Ads Trend' : 'Weekly Ads Trend';
  const showLabels = !useDaily || data.length <= 15; // show labels unless daily with many bars

  return (
    <div className="border border-border rounded-xl bg-card p-4 mb-6">
      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center gap-3">
          <div className="text-[11px] font-semibold text-subtle uppercase tracking-wider">{trendTitle}</div>
        </div>
        <div className="flex items-center gap-1 flex-wrap">
          {ADS_TREND_MEASURES.map(m => (
            <button key={m.key} onClick={() => toggle(m.key)}
              className="px-2 py-0.5 rounded-md text-[10px] font-semibold border transition-all"
              style={{
                borderColor: active.has(m.key) ? m.color : 'rgba(63,63,70,.45)',
                background: active.has(m.key) ? m.color + '18' : 'transparent',
                color: active.has(m.key) ? m.color : '#71717a',
              }}
            >{m.label}</button>
          ))}
        </div>
      </div>
      {dailyLoading && useDaily && (
        <div className="h-[200px] flex items-center justify-center text-xs text-subtle animate-pulse">Loading daily data…</div>
      )}
      {(!dailyLoading || !useDaily) && data.length < 2 && (
        <div className="h-[200px] flex items-center justify-center text-xs text-subtle">Not enough data points</div>
      )}
      {data.length >= 2 && !(dailyLoading && useDaily) && (
        <div className="h-[200px]">
          <ResponsiveContainer width="100%" height="100%">
            <ComposedChart data={data} barCategoryGap={useDaily ? '5%' : '20%'} margin={{ top: 20, right: 5, bottom: 0, left: 5 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.04)" />
              <XAxis dataKey="week" tick={{ fill: '#71717a', fontSize: useDaily ? 8 : 10, fontFamily: 'var(--font-mono)' }} tickLine={false} axisLine={false} interval={useDaily ? Math.max(0, Math.floor(data.length / 15)) : 0} angle={useDaily ? -45 : 0} textAnchor={useDaily ? 'end' : 'middle'} height={useDaily ? 40 : 30} />
              <YAxis yAxisId="left" hide />
              <YAxis yAxisId="right" orientation="right" hide />
              <Tooltip
                contentStyle={{ background: '#16161a', border: '1px solid rgba(63,63,70,0.45)', borderRadius: 8, fontSize: 11 }}
                formatter={((v: unknown, name?: string) => {
                  const n = Number(v) || 0;
                  const m = ADS_TREND_MEASURES.find(x => x.key === name);
                  return [m ? m.fmt(n) : String(n), m?.label || name || ''];
                }) as any}
              />
              {activeMeasures.map(m =>
                m.type === 'bar' ? (
                  <Bar key={m.key} yAxisId={m.axis} dataKey={m.key} name={m.key} fill={m.color} radius={[3, 3, 0, 0]} fillOpacity={0.7}>
                    {showLabels && <LabelList dataKey={m.key} position="top" offset={4}
                      formatter={(v: unknown) => m.fmt(typeof v === 'number' ? v : 0)}
                      style={{ fill: '#d4d4d8', fontSize: 10, fontWeight: 600, fontFamily: 'var(--font-mono)' }} />}
                  </Bar>
                ) : (
                  <Line key={m.key} yAxisId="right" dataKey={m.key} name={m.key} stroke={m.color} strokeWidth={useDaily ? 1.5 : 2}
                    dot={useDaily ? false : { r: 2.5, fill: m.color }} type="monotone" />
                )
              )}
              <SeasonalReferenceLines holidays={holidays} xLabels={getXLabels(data, 'week')} yAxisId="left" />
            </ComposedChart>
          </ResponsiveContainer>
        </div>
      )}
    </div>
  );
}

