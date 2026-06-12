/**
 * KpiPage — Customizable KPI Board
 *
 * Users pick measures from a catalog. Each appears as a premium glass card
 * with hero value, period-over-period delta, LY comparison, and sparkline.
 * Below the metrics grid: toggleable Pareto cards showing Winners / Losers / Other
 * for Ads Targets, Ads Terms, Ads Campaigns, and SQP Terms.
 * Fully connected to header filters (family, period, seasonality, product).
 */
import { useState, useMemo, useCallback, useEffect, useRef, Fragment } from 'react';
import type { DashboardData, TrendRow, TrendRowByAsin, ActionRow, SqpWeeklyRow, CoachCampaignRow, ProductRow, SupplyChainRow, DailyTrendRow } from '../types';
import { SparklineCanvas } from '../components/SparklineCanvas';
import { PriceScenarioCard } from '../components/PriceScenarioCard';
import { AlertsSummaryCard } from '../components/AlertsSummaryCard';
import { useFilters } from '../hooks/useFilters';
import {
  famFromType, weekRangeLabel, getPeriodsToInclude,
  shiftYear, fM, fP, fR, fShort, fmt, experimentMatchesFamily, addDays
} from '../utils';
import { filterBySeasonality } from '../seasonality';
import { Plus, X, TrendingUp, TrendingDown, Minus, GripVertical, Maximize2, Minimize2, ChevronRight, ChevronDown } from 'lucide-react';
import {
  DndContext, closestCenter, PointerSensor, useSensor, useSensors,
  type DragEndEvent,
} from '@dnd-kit/core';
import {
  SortableContext, useSortable, rectSortingStrategy,
  arrayMove,
} from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';

/* ── Extended measure catalog ── */
interface KpiMeasureDef {
  id: string;
  label: string;
  group: string;
  color: string;
  glow: string;
  fmt: (v: number) => string;
  fmtCompact: (v: number) => string;
  isAvg?: boolean; // averaged across families (not summed)
}

const KPI_CATALOG: KpiMeasureDef[] = [
  { id: 'sales',       label: 'Sales',       group: 'PnL',  color: '#3b82f6', glow: 'rgba(59,130,246,0.15)',  fmt: v => fM(v), fmtCompact: v => '$' + fShort(v) },
  { id: 'net_profit',  label: 'Net Profit',  group: 'PnL',  color: '#22c55e', glow: 'rgba(34,197,94,0.15)',   fmt: v => fM(v), fmtCompact: v => '$' + fShort(v) },
  { id: 'cogs',        label: 'COGS',        group: 'PnL',  color: '#f97316', glow: 'rgba(249,115,22,0.15)',  fmt: v => fM(v), fmtCompact: v => '$' + fShort(v) },
  { id: 'ad_cost',     label: 'Ads Spend',   group: 'Ads',  color: '#ef4444', glow: 'rgba(239,68,68,0.15)',   fmt: v => fM(v), fmtCompact: v => '$' + fShort(v) },
  { id: 'net_roas',    label: 'Net ROAS',    group: 'Ads',  color: '#a855f7', glow: 'rgba(168,85,247,0.15)',  fmt: v => fR(v), fmtCompact: v => fShort(v) + 'x', isAvg: true },
  { id: 'orders',      label: 'Orders',      group: 'SQP',  color: '#06b6d4', glow: 'rgba(6,182,212,0.15)',   fmt: v => v.toLocaleString(), fmtCompact: v => fShort(v) },
  { id: 'clicks',      label: 'Clicks',      group: 'SQP',  color: '#8b5cf6', glow: 'rgba(139,92,246,0.15)',  fmt: v => v.toLocaleString(), fmtCompact: v => fShort(v) },
  { id: 'sessions',    label: 'Sessions',    group: 'SQP',  color: '#64748b', glow: 'rgba(100,116,139,0.15)', fmt: v => v.toLocaleString(), fmtCompact: v => fShort(v) },
  { id: 'organic_pct', label: 'Organic %',   group: 'SQP',  color: '#10b981', glow: 'rgba(16,185,129,0.15)',  fmt: v => fP(v), fmtCompact: v => fShort(v) + '%', isAvg: true },
  { id: 'payment',     label: 'Payment',     group: 'Cash', color: '#38bdf8', glow: 'rgba(56,189,248,0.15)',  fmt: v => fM(v), fmtCompact: v => '$' + fShort(v) },
  { id: 'tacos',       label: 'TACoS',       group: 'Ads',  color: '#fb923c', glow: 'rgba(251,146,60,0.15)',  fmt: v => fP(v), fmtCompact: v => fShort(v) + '%', isAvg: true },
  { id: 'ads_acos',    label: 'Ads ACoS',    group: 'Ads',  color: '#e879f9', glow: 'rgba(232,121,249,0.15)', fmt: v => fP(v), fmtCompact: v => fShort(v) + '%', isAvg: true },
  { id: 'ads_cpc',     label: 'Ads CPC',     group: 'Ads',  color: '#fbbf24', glow: 'rgba(251,191,36,0.15)',  fmt: v => '$' + v.toFixed(2), fmtCompact: v => '$' + v.toFixed(2), isAvg: true },
  { id: 'ads_cvr',     label: 'Ads CVR',     group: 'Ads',  color: '#14b8a6', glow: 'rgba(20,184,166,0.15)',  fmt: v => fP(v), fmtCompact: v => fShort(v) + '%', isAvg: true },
  { id: 'ads_ctr',     label: 'Ads CTR',     group: 'Ads',  color: '#f97316', glow: 'rgba(249,115,22,0.15)',  fmt: v => fP(v), fmtCompact: v => fShort(v) + '%', isAvg: true },
  { id: 'np_per_unit', label: 'NP / Unit',   group: 'PnL',  color: '#34d399', glow: 'rgba(52,211,153,0.15)',  fmt: v => fM(v), fmtCompact: v => '$' + fShort(v), isAvg: true },
  { id: 'margin_pct',  label: 'Margin %',    group: 'PnL',  color: '#2dd4bf', glow: 'rgba(45,212,191,0.15)',  fmt: v => fP(v), fmtCompact: v => fShort(v) + '%', isAvg: true },
  { id: 'units',       label: 'Units',       group: 'PnL',  color: '#818cf8', glow: 'rgba(129,140,248,0.15)', fmt: v => v.toLocaleString(), fmtCompact: v => fShort(v) },
  { id: 'plan_vs_actual', label: 'Plan vs Actual', group: 'Plan', color: '#34d399', glow: 'rgba(52,211,153,0.15)', fmt: v => fP(v), fmtCompact: v => fShort(v) + '%', isAvg: true },
];

const CATALOG_MAP = Object.fromEntries(KPI_CATALOG.map(m => [m.id, m]));

const STORAGE_KEY = 'oi_kpi_board_selection';
const DEFAULT_IDS = ['sales', 'net_profit', 'net_roas', 'ad_cost', 'orders', 'organic_pct'];

function loadSelection(): string[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const arr = JSON.parse(raw) as string[];
      const valid = arr.filter(id => CATALOG_MAP[id]);
      if (valid.length > 0) return valid;
    }
  } catch { /* ignore */ }
  return DEFAULT_IDS;
}

function saveSelection(ids: string[]) {
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(ids)); } catch { /* ignore */ }
}

/* ── Pareto card types ── */
type ParetoCardId = 'ads_targets' | 'ads_terms' | 'ads_campaigns' | 'ads_cpc_buckets' | 'sqp_terms' | 'best_product_profit' | 'best_product_units' | 'profit_movers' | 'term_profit_movers' | 'keyword_profit_movers' | 'ads_strategy' | 'campaign_launch';

interface ParetoCardDef {
  id: ParetoCardId;
  label: string;
  icon: string;
  color: string;
  description: string;
  category: 'Focus Cards' | 'Trend Cards';
}

const PARETO_CARDS: ParetoCardDef[] = [
  { id: 'ads_targets',   label: 'Ads Targets',   icon: '🎯', color: '#8b5cf6', description: 'Keyword targets by net profit', category: 'Focus Cards' },
  { id: 'ads_terms',     label: 'Ads Terms',     icon: '🔍', color: '#f59e0b', description: 'Search terms by net profit', category: 'Focus Cards' },
  { id: 'ads_campaigns', label: 'Ads Campaigns', icon: '📢', color: '#3b82f6', description: 'Campaigns by net profit', category: 'Focus Cards' },
  { id: 'ads_cpc_buckets', label: 'Ads CPC Buckets', icon: '💲', color: '#06b6d4', description: 'Performance by CPC range', category: 'Focus Cards' },
  { id: 'sqp_terms',     label: 'SQP Terms',     icon: '📊', color: '#10b981', description: 'Search query terms by orders', category: 'Focus Cards' },
  { id: 'best_product_profit', label: 'Best Product (Profit)', icon: '💰', color: '#22c55e', description: 'Top products by net profit', category: 'Focus Cards' },
  { id: 'best_product_units',  label: 'Best Product (Units)',  icon: '📦', color: '#60a5fa', description: 'Top products by units sold', category: 'Focus Cards' },
  { id: 'profit_movers',       label: 'Product Profit Movers', icon: '🚀', color: '#ec4899', description: 'Period-over-period product profit changes', category: 'Trend Cards' },
  { id: 'term_profit_movers',  label: 'Term Profit Movers',    icon: '📈', color: '#f43f5e', description: 'Period-over-period term profit changes', category: 'Trend Cards' },
  { id: 'keyword_profit_movers', label: 'Keyword Profit Movers', icon: '🎯', color: '#8b5cf6', description: 'Period-over-period keyword profit changes', category: 'Trend Cards' },
  { id: 'ads_strategy', label: 'Ad Strategy', icon: '🧭', color: '#8b5cf6', description: 'Performance by ad strategy', category: 'Focus Cards' },
  { id: 'campaign_launch', label: 'Campaign Launch', icon: '🚀', color: '#f97316', description: 'First 3 months performance per campaign', category: 'Focus Cards' },
];

const PARETO_STORAGE_KEY = 'oi_kpi_pareto_cards';
const DEFAULT_PARETO: ParetoCardId[] = ['ads_targets', 'ads_campaigns', 'ads_terms', 'profit_movers', 'term_profit_movers', 'keyword_profit_movers', 'ads_strategy', 'campaign_launch'];

function loadPareto(): ParetoCardId[] {
  try {
    const raw = localStorage.getItem(PARETO_STORAGE_KEY);
    if (raw) {
      const arr = JSON.parse(raw) as ParetoCardId[];
      const valid = arr.filter(id => PARETO_CARDS.some(p => p.id === id));
      // Auto-add any new PARETO_CARDS not yet in the saved list
      const allKnown = PARETO_CARDS.map(p => p.id);
      const newCards = allKnown.filter(id => !valid.includes(id) && DEFAULT_PARETO.includes(id));
      if (valid.length > 0) return [...valid, ...newCards];
    }
  } catch { /* ignore */ }
  return DEFAULT_PARETO;
}

function savePareto(ids: ParetoCardId[]) {
  try { localStorage.setItem(PARETO_STORAGE_KEY, JSON.stringify(ids)); } catch { /* ignore */ }
}

/* ── Specials card types ── */
type SpecialCardId = 'price_scenario';

interface SpecialCardDef {
  id: SpecialCardId;
  label: string;
  icon: string;
  color: string;
  description: string;
}

const SPECIAL_CARDS: SpecialCardDef[] = [
  { id: 'price_scenario', label: 'Price Change Scenario', icon: '🏷️', color: '#ec4899', description: 'Simulate price impacts' },
];

const SPECIALS_STORAGE_KEY = 'oi_kpi_special_cards';
const DEFAULT_SPECIALS: SpecialCardId[] = ['price_scenario'];

function loadSpecials(): SpecialCardId[] {
  try {
    const raw = localStorage.getItem(SPECIALS_STORAGE_KEY);
    if (raw) {
      const arr = JSON.parse(raw) as SpecialCardId[];
      const valid = arr.filter(id => SPECIAL_CARDS.some(p => p.id === id));
      if (valid.length > 0) return valid;
    }
  } catch { /* ignore */ }
  return DEFAULT_SPECIALS;
}

function saveSpecials(ids: SpecialCardId[]) {
  try { localStorage.setItem(SPECIALS_STORAGE_KEY, JSON.stringify(ids)); } catch { /* ignore */ }
}

/* ── Measure card types ── */
type MeasureCardId = 'pnl_total' | 'pnl_per_unit' | 'daily_avg' | 'plan' | 'plan_trend' | 'ppc';

interface MeasureCardDef {
  id: MeasureCardId;
  label: string;
  color: string;
  description: string;
}

const MEASURE_CARDS: MeasureCardDef[] = [
  { id: 'pnl_total',    label: 'P&L',            color: '#f59e0b', description: 'Period totals for P&L' },
  { id: 'pnl_per_unit', label: 'P&L per Unit',   color: '#a78bfa', description: 'Per-unit cost breakdown' },
  { id: 'daily_avg',    label: 'Daily Average',   color: '#60a5fa', description: 'Daily averages for period' },
  { id: 'plan',         label: 'Plan',            color: '#34d399', description: 'Stock & forecast overview' },
  { id: 'plan_trend',   label: 'Plan Trend',      color: '#06b6d4', description: 'Actual vs forecast demand chart' },
  { id: 'ppc',          label: 'PPC',             color: '#ef4444', description: 'Ads performance metrics' },
];

const MEASURE_STORAGE_KEY = 'oi_kpi_measure_cards';
const DEFAULT_MEASURES: MeasureCardId[] = ['pnl_total', 'pnl_per_unit', 'daily_avg', 'plan', 'plan_trend', 'ppc'];

function loadMeasures(): MeasureCardId[] {
  try {
    const raw = localStorage.getItem(MEASURE_STORAGE_KEY);
    if (raw) {
      const arr = JSON.parse(raw) as MeasureCardId[];
      const allKnown = MEASURE_CARDS.map(m => m.id);
      const valid = arr.filter(id => allKnown.includes(id));
      // Add any new cards that weren't previously persisted
      const newCards = allKnown.filter(id => !valid.includes(id) && DEFAULT_MEASURES.includes(id));
      if (valid.length > 0) return [...valid, ...newCards];
    }
  } catch { /* ignore */ }
  return DEFAULT_MEASURES;
}

function saveMeasures(ids: MeasureCardId[]) {
  try { localStorage.setItem(MEASURE_STORAGE_KEY, JSON.stringify(ids)); } catch { /* ignore */ }
}

/* ── Card size persistence ── */
const SIZE_STORAGE_KEY = 'oi_kpi_card_sizes';
type CardSize = 'expanded' | 'detail';

function loadCardSizes(): Record<string, CardSize> {
  try {
    const raw = localStorage.getItem(SIZE_STORAGE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw) as Record<string, string>;
      // Migrate legacy 'compact' entries to 'expanded'
      const migrated: Record<string, CardSize> = {};
      for (const [k, v] of Object.entries(parsed)) {
        migrated[k] = v === 'detail' ? 'detail' : 'expanded';
      }
      return migrated;
    }
  } catch { /* ignore */ }
  return {};
}
function saveCardSizes(sizes: Record<string, CardSize>) {
  try { localStorage.setItem(SIZE_STORAGE_KEY, JSON.stringify(sizes)); } catch { /* ignore */ }
}

interface ParetoItem {
  name: string;
  spend: number;
  orders: number;
  profit: number;
  roas: number | null;
  bucket: 'winner' | 'loser' | 'other' | 'other_winners' | 'other_losers';
  count?: number;
  _sales?: number;
  children?: ParetoItem[];
}

/* ── Family / Product split inside KPI cards ── */
interface SplitItem {
  label: string;
  value: number;
  color: string;
}

// Stable, distinguishable palette for family/product split bars
const SPLIT_PALETTE = [
  '#3b82f6', '#ec4899', '#22c55e', '#f97316', '#a855f7',
  '#06b6d4', '#eab308', '#ef4444', '#14b8a6', '#8b5cf6',
];
const splitColorCache: Record<string, string> = {};
let splitColorIdx = 0;
function getSplitColor(key: string): string {
  if (!splitColorCache[key]) {
    splitColorCache[key] = SPLIT_PALETTE[splitColorIdx % SPLIT_PALETTE.length];
    splitColorIdx++;
  }
  return splitColorCache[key];
}

/* ── Aggregate helpers ── */
type Bucket = Record<string, { sum: number; count: number }>;

function emptyBucket(): Bucket {
  const b: Bucket = {};
  for (const m of KPI_CATALOG) b[m.id] = { sum: 0, count: 0 };
  // Helper components used by derived ratios (not displayed as KPI cards)
  b.impressions = { sum: 0, count: 0 };
  return b;
}

function addRowToBucket(bucket: Bucket, row: TrendRow) {
  const sl = row.sales || 0;
  const co = row.ad_cost || 0;
  const cg = row.cogs || 0;
  const np = row.net_profit || 0;
  const or = row.orders || 0;
  const un = row.units ?? or;

  const vals: Record<string, number> = {
    sales: sl, net_profit: np, cogs: cg, ad_cost: co,
    net_roas: row.net_roas || 0, orders: or, clicks: row.clicks || 0,
    sessions: row.sessions || 0, impressions: row.impressions || 0, organic_pct: row.organic_pct || 0,
    payment: 0,
    tacos: sl > 0 ? (co / sl) * 100 : 0,
    np_per_unit: un > 0 ? np / un : 0,
    margin_pct: sl > 0 ? (np / sl) * 100 : 0,
    units: un,
  };

  for (const [k, v] of Object.entries(vals)) {
    if (bucket[k]) { bucket[k].sum += v; bucket[k].count += 1; }
  }
}

function mergeBuckets(a: Bucket, b: Bucket): Bucket {
  const res: Bucket = emptyBucket();
  for (const k of Object.keys(res)) {
    if (a[k]) { res[k].sum += a[k].sum; res[k].count += a[k].count; }
    if (b[k]) { res[k].sum += b[k].sum; res[k].count += b[k].count; }
  }
  return res;
}

function resolveValue(bucket: Bucket, id: string): number {
  // Derived ratios — computed from component buckets, not their own bucket
  if (id === 'net_roas') {
    const sl = bucket.sales?.sum || 0;
    const cg = bucket.cogs?.sum || 0;
    const co = bucket.ad_cost?.sum || 0;
    return co > 0 ? (sl - cg) / co : 0;
  }
  if (id === 'tacos') {
    const sl = bucket.sales?.sum || 0;
    const co = bucket.ad_cost?.sum || 0;
    return sl > 0 ? (co / sl) * 100 : 0;
  }
  if (id === 'np_per_unit') {
    const np = bucket.net_profit?.sum || 0;
    const un = bucket.units?.sum || bucket.orders?.sum || 0;
    return un > 0 ? np / un : 0;
  }
  if (id === 'margin_pct') {
    const sl = bucket.sales?.sum || 0;
    const np = bucket.net_profit?.sum || 0;
    return sl > 0 ? (np / sl) * 100 : 0;
  }
  if (id === 'ads_acos') {
    const co = bucket.ad_cost?.sum || 0;
    const sl = bucket.sales?.sum || 0;
    return sl > 0 ? (co / sl) * 100 : 0;
  }
  if (id === 'ads_cpc') {
    const co = bucket.ad_cost?.sum || 0;
    const cl = bucket.clicks?.sum || 0;
    return cl > 0 ? co / cl : 0;
  }
  if (id === 'ads_cvr') {
    const or = bucket.orders?.sum || 0;
    const cl = bucket.clicks?.sum || 0;
    return cl > 0 ? (or / cl) * 100 : 0;
  }
  if (id === 'ads_ctr') {
    const cl = bucket.clicks?.sum || 0;
    const im = bucket.impressions?.sum || 0;
    return im > 0 ? (cl / im) * 100 : 0;
  }
  // Direct metrics — need at least one data point
  const b = bucket[id];
  if (!b || b.count === 0) return 0;
  const def = CATALOG_MAP[id];
  if (def?.isAvg) return b.sum / b.count;
  return b.sum;
}

/* ── Main component ── */
export function KpiPage({ data }: { data: DashboardData }) {
  const { filters } = useFilters();
  const periodMode = filters.periodMode;
  const [selectedIds, setSelectedIds] = useState<string[]>(loadSelection);
  const [showCustomize, setShowCustomize] = useState(false);
  const [paretoIds, setParetoIds] = useState<ParetoCardId[]>(loadPareto);
  const [specialIds, setSpecialIds] = useState<SpecialCardId[]>(loadSpecials);
  const [measureIds, setMeasureIds] = useState<MeasureCardId[]>(loadMeasures);
  const [cardSizes, setCardSizes] = useState<Record<string, CardSize>>(loadCardSizes);

  // Persist selection + sizes
  useEffect(() => { saveSelection(selectedIds); }, [selectedIds]);
  useEffect(() => { savePareto(paretoIds); }, [paretoIds]);
  useEffect(() => { saveSpecials(specialIds); }, [specialIds]);
  useEffect(() => { saveMeasures(measureIds); }, [measureIds]);
  useEffect(() => { saveCardSizes(cardSizes); }, [cardSizes]);

  // DnD sensors — 8px activation distance prevents accidental drags
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 8 } }));

  const toggleMeasure = useCallback((id: string) => {
    setSelectedIds(prev => {
      if (prev.includes(id)) return prev.length > 1 ? prev.filter(x => x !== id) : prev;
      return [...prev, id];
    });
  }, []);

  const removeMeasure = useCallback((id: string) => {
    setSelectedIds(prev => prev.length > 1 ? prev.filter(x => x !== id) : prev);
  }, []);

  const togglePareto = useCallback((id: ParetoCardId) => {
    setParetoIds(prev => prev.includes(id) ? prev.filter(x => x !== id) : [...prev, id]);
  }, []);

  const removePareto = useCallback((id: ParetoCardId) => {
    setParetoIds(prev => prev.filter(x => x !== id));
  }, []);

  const toggleSpecial = useCallback((id: SpecialCardId) => {
    setSpecialIds(prev => prev.includes(id) ? prev.filter(x => x !== id) : [...prev, id]);
  }, []);

  const removeSpecial = useCallback((id: SpecialCardId) => {
    setSpecialIds(prev => prev.filter(x => x !== id));
  }, []);

  const toggleMeasureCard = useCallback((id: MeasureCardId) => {
    setMeasureIds(prev => prev.includes(id) ? prev.filter(x => x !== id) : [...prev, id]);
  }, []);

  const toggleSize = useCallback((id: string) => {
    setCardSizes(prev => {
      const cur = prev[id] || 'expanded';
      const next: CardSize = cur === 'expanded' ? 'detail' : 'expanded';
      return { ...prev, [id]: next };
    });
  }, []);

  // DnD handlers
  const handleKpiDragEnd = useCallback((event: DragEndEvent) => {
    const { active, over } = event;
    if (over && active.id !== over.id) {
      setSelectedIds(prev => {
        const oldIdx = prev.indexOf(String(active.id));
        const newIdx = prev.indexOf(String(over.id));
        return arrayMove(prev, oldIdx, newIdx);
      });
    }
  }, []);

  const handleParetoDragEnd = useCallback((event: DragEndEvent) => {
    const { active, over } = event;
    if (over && active.id !== over.id) {
      setParetoIds(prev => {
        const oldIdx = prev.indexOf(active.id as ParetoCardId);
        const newIdx = prev.indexOf(over.id as ParetoCardId);
        return arrayMove(prev, oldIdx, newIdx);
      });
    }
  }, []);

  const pk = data.peak?.[0] ?? null;

  // Filter trends by family, product, seasonality
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

  // Build period buckets
  const { periodBuckets, sortedPeriods, currentPeriod, prevPeriod } = useMemo(() => {
    const buckets: Record<string, Bucket> = {};

    if (periodMode === 'weeks') {
      filteredWeekly.forEach(r => {
        const k = r.week_start || '';
        if (!k) return;
        if (!buckets[k]) buckets[k] = emptyBucket();
        addRowToBucket(buckets[k], r);
      });
    } else if (periodMode === 'month') {
      filteredMonthly.forEach(r => {
        const k = (r.month_start || '').slice(0, 7);
        if (!k) return;
        if (!buckets[k]) buckets[k] = emptyBucket();
        addRowToBucket(buckets[k], r);
      });
    } else if (periodMode === 'quarter') {
      filteredMonthly.forEach(r => {
        const ms = r.month_start || '';
        const m = parseInt(ms.slice(5, 7), 10);
        const q = Math.ceil(m / 3);
        const k = `${ms.slice(0, 4)}-Q${q}`;
        if (!buckets[k]) buckets[k] = emptyBucket();
        addRowToBucket(buckets[k], r);
      });
    } else {
      // year
      filteredMonthly.forEach(r => {
        const k = (r.month_start || '').slice(0, 4);
        if (!k) return;
        if (!buckets[k]) buckets[k] = emptyBucket();
        addRowToBucket(buckets[k], r);
      });
    }

    const sorted = Object.keys(buckets).sort();
    const trendPeriods = getPeriodsToInclude(filters.specificPeriod, periodMode, sorted, filters.periodTrend);
    let cur: string;
    if (filters.specificPeriod) {
      cur = filters.specificPeriod;
      // Ensure bucket exists even if no trend data for this period
      if (!buckets[cur]) buckets[cur] = emptyBucket();
    } else {
      cur = sorted[sorted.length - 1] || '';
    }
    const curIdx = sorted.indexOf(cur);
    const prev = curIdx > 0 ? sorted[curIdx - 1] : '';

    return { periodBuckets: buckets, sortedPeriods: trendPeriods, currentPeriod: cur, prevPeriod: prev };
  }, [filteredWeekly, filteredMonthly, periodMode, filters.specificPeriod, filters.periodTrend]);

  // Find LY period
  const lyPeriod = useMemo(() => {
    if (!currentPeriod) return '';
    if (periodMode === 'weeks') return shiftYear(currentPeriod, -1);
    if (periodMode === 'month') {
      const [y, m] = currentPeriod.split('-');
      return `${parseInt(y, 10) - 1}-${m}`;
    }
    if (periodMode === 'quarter') {
      const [y, q] = currentPeriod.split('-');
      return `${parseInt(y, 10) - 1}-${q}`;
    }
    return String(parseInt(currentPeriod, 10) - 1);
  }, [currentPeriod, periodMode]);

  // ── Split buckets: per-family or per-product breakdown for current period ──
  const splitBuckets = useMemo<Record<string, Bucket>>(() => {
    const { family, product } = filters;
    // Don't split when a specific product is selected
    if (product) return {};

    // Use by-asin data grouped by family or by product_short_name
    const byAsinRows: TrendRowByAsin[] = periodMode === 'weeks'
      ? (data.weekly_trends_by_asin || [])
      : (data.monthly_trends_by_asin || []);

    // Filter to the current period
    const periodRows = byAsinRows.filter(r => {
      const dateKey = periodMode === 'weeks'
        ? (r.week_start || '')
        : periodMode === 'month'
          ? (r.month_start || '').slice(0, 7)
          : periodMode === 'quarter'
            ? (() => { const ms = r.month_start || ''; const m = parseInt(ms.slice(5, 7), 10); return `${ms.slice(0, 4)}-Q${Math.ceil(m / 3)}`; })()
            : (r.month_start || '').slice(0, 4);
      return dateKey === currentPeriod;
    });

    // Group: if family selected → group by product, otherwise → group by family
    const groupKey = family
      ? (r: TrendRowByAsin) => r.product_short_name || r.asin
      : (r: TrendRowByAsin) => famFromType(r.product_type) || r.product_type;

    // If family is selected, only include rows from that family
    const relevantRows = family
      ? periodRows.filter(r => famFromType(r.product_type) === family)
      : periodRows;

    const result: Record<string, Bucket> = {};
    relevantRows.forEach(r => {
      const k = groupKey(r);
      if (!k) return;
      if (!result[k]) result[k] = emptyBucket();
      addRowToBucket(result[k], r);
    });
    return result;
  }, [data.weekly_trends_by_asin, data.monthly_trends_by_asin, filters.family, filters.product, currentPeriod, periodMode]);

  // Plan vs Actual: compute from supply chain data (not period-based)
  const planVsActual = useMemo(() => {
    const prods = data.products || [];
    const famAsins = new Set(
      (filters.product ? prods.filter(p => p.asin === filters.product) : filters.family ? prods.filter(p => p.family_name === filters.family) : prods)
        .map(p => p.asin).filter(Boolean)
    );
    let supply = data.supply_chain || [];
    if (filters.product) supply = supply.filter(s => s.asin === filters.product);
    else if (filters.family) supply = supply.filter(s => famAsins.has(s.asin));
    let sold = 0, planned = 0;
    supply.forEach(s => { sold += s.last_30d_sold || 0; planned += s.last_30d_planned || 0; });
    const pct = planned > 0 ? (sold / planned) * 100 : 0;

    // Per-product/family splits for plan_vs_actual
    const splitMap: Record<string, { sold: number; planned: number }> = {};
    supply.forEach(s => {
      let label = '';
      if (filters.family || filters.product) {
        label = s.product_short_name || s.product_type || s.asin;
      } else {
        const pInfo = prods.find(p => p.asin === s.asin);
        const knownFamilies: Record<string, string> = {
          'Truth Or Dare': 'Bottle',
          'Fresh in Blue': 'Fresh', 'Fresh in Purple': 'Fresh', 'Fresh in Beige': 'Fresh', 'Fresh in Pink': 'Fresh',
          'Blue Lollibox': 'Lollibox', 'White Lollibox': 'Lollibox', 'Pink Lollibox': 'Lollibox', 'Purple Lollibox': 'Lollibox',
          'Pink LolliME': 'LolliME', 'Purple LolliME': 'LolliME', 'Mint LolliME': 'LolliME',
          'Love Bunny': 'Bunny', 'Awesome Bunny': 'Bunny', 'Unplug Bunny': 'Bunny', 'Birthday Bunny': 'Bunny', 'Choice Bunny': 'Bunny', 'Proud Bunny': 'Bunny', 'Brave Bunny': 'Bunny', 'Cheer Bunny': 'Bunny', 'Chill Bunny': 'Bunny', 'Hug Bunny': 'Bunny', 'Bestie Bunny': 'Bunny', 'Nope Bunny': 'Bunny',
          'Mint LolliBall': 'LolliBall', 'Blue LolliBall': 'LolliBall', 'Purple LolliBall': 'LolliBall', 'Pink LolliBall': 'LolliBall', 'White LolliBall': 'LolliBall'
        };
        const famName = pInfo?.family_name || knownFamilies[s.product_short_name || ''];
        label = famName || famFromType(s.product_short_name || s.product_type || '') || 'Unknown';
      }
      if (!splitMap[label]) splitMap[label] = { sold: 0, planned: 0 };
      splitMap[label].sold += s.last_30d_sold || 0;
      splitMap[label].planned += s.last_30d_planned || 0;
    });
    const splits: SplitItem[] = Object.entries(splitMap)
      .filter(([, v]) => v.sold > 0 || v.planned > 0)
      .map(([label, v]) => ({
        label,
        value: v.planned > 0 ? (v.sold / v.planned) * 100 : 0,
        color: getSplitColor(label),
      }));

    return { sold, planned, pct, splits };
  }, [data.supply_chain, data.products, filters.family, filters.product]);

  // Build card data for each selected measure
  const cards = useMemo(() => {
    return selectedIds.map(id => {
      const def = CATALOG_MAP[id];
      if (!def) return null;

      // plan_vs_actual is supply-chain-based, not period-based
      if (id === 'plan_vs_actual') {
        return {
          id, def,
          value: planVsActual.pct,
          prevValue: null, lyValue: null, delta: null,
          positive: planVsActual.pct >= 80, sentiment: planVsActual.pct >= 80,
          sparkline: [], cumulativeCY: [], cumulativeLY: [],
          splits: planVsActual.splits,
        };
      }

      let curBucket = periodBuckets[currentPeriod];
      let prevBucket = periodBuckets[prevPeriod];
      // LY: find nearest matching period in weekly mode
      let lyBucket: Bucket | undefined;
      let lyPeriodMatched = '';
      if (periodMode === 'weeks') {
        const allWeeks = Object.keys(periodBuckets).sort();
        const target = new Date(currentPeriod + 'T00:00:00');
        target.setDate(target.getDate() - 364);
        const targetTime = target.getTime();
        let best: string | null = null;
        let bestDiff = Infinity;
        for (const wk of allWeeks) {
          const diff = Math.abs(new Date(wk + 'T00:00:00').getTime() - targetTime);
          if (diff < bestDiff && diff <= 7 * 86400000) { bestDiff = diff; best = wk; }
        }
        if (best) { lyBucket = periodBuckets[best]; lyPeriodMatched = best; }
      } else {
        lyBucket = periodBuckets[lyPeriod];
        lyPeriodMatched = lyPeriod;
      }

      // Sparkline: last N periods (always single-period values)
      const sparkline = sortedPeriods.map(p => {
        const b = periodBuckets[p];
        return b ? resolveValue(b, id) : 0;
      });

      // Cumulative data: CY running sum + LY running sum aligned by month/week index
      let cumulativeCY: number[] = [];
      let cumulativeLY: number[] = [];
      const allSorted = Object.keys(periodBuckets).sort();
      let cyPeriods: string[] = [];
      let lyPeriods: string[] = [];

      if (allSorted.length > 0) {
        const curYear = currentPeriod ? currentPeriod.slice(0, 4) : allSorted[allSorted.length - 1].slice(0, 4);
        const lyYear = String(parseInt(curYear, 10) - 1);
        cyPeriods = allSorted.filter(p => p.startsWith(curYear));
        lyPeriods = allSorted.filter(p => p.startsWith(lyYear));
        
        let runCY = emptyBucket();
        cyPeriods.forEach(p => {
          const b = periodBuckets[p];
          if (b) runCY = mergeBuckets(runCY, b);
          cumulativeCY.push(resolveValue(runCY, id));
        });
        
        let runLY = emptyBucket();
        lyPeriods.forEach(p => {
          const b = periodBuckets[p];
          if (b) runLY = mergeBuckets(runLY, b);
          cumulativeLY.push(resolveValue(runLY, id));
        });

        if (filters.periodType === 'cumulative' && currentPeriod) {
          const curIdx = cyPeriods.indexOf(currentPeriod);
          if (curIdx >= 0) {
            let cumCur = emptyBucket();
            for (let i = 0; i <= curIdx; i++) {
              if (periodBuckets[cyPeriods[i]]) cumCur = mergeBuckets(cumCur, periodBuckets[cyPeriods[i]]);
            }
            curBucket = cumCur;
            
            if (curIdx > 0) {
              let cumPrev = emptyBucket();
              for (let i = 0; i <= curIdx - 1; i++) {
                if (periodBuckets[cyPeriods[i]]) cumPrev = mergeBuckets(cumPrev, periodBuckets[cyPeriods[i]]);
              }
              prevBucket = cumPrev;
            }
          }

          const lyIdx = lyPeriods.indexOf(lyPeriodMatched);
          if (lyIdx >= 0) {
            let cumLy = emptyBucket();
            for (let i = 0; i <= lyIdx; i++) {
              if (periodBuckets[lyPeriods[i]]) cumLy = mergeBuckets(cumLy, periodBuckets[lyPeriods[i]]);
            }
            lyBucket = cumLy;
          }
        }
      }

      const value = curBucket ? resolveValue(curBucket, id) : 0;
      const prevValue = prevBucket ? resolveValue(prevBucket, id) : null;
      const lyValue = lyBucket ? resolveValue(lyBucket, id) : null;

      const delta = prevValue != null && prevValue !== 0
        ? ((value - prevValue) / Math.abs(prevValue)) * 100
        : null;
      const positive = delta != null ? delta >= 0 : true;
      const costMeasures = new Set(['ad_cost', 'cogs', 'tacos', 'ads_acos', 'ads_cpc']);
      const sentiment = costMeasures.has(id) ? !positive : positive;

      // Build family/product splits for this KPI
      const splitEntries = Object.keys(splitBuckets).sort();
      const splits: SplitItem[] = splitEntries.map(label => ({
        label,
        value: resolveValue(splitBuckets[label], id),
        color: getSplitColor(label),
      })).filter(s => s.value !== 0 || splitEntries.length <= 6);

      return { id, def, value, prevValue, lyValue, delta, positive, sentiment, sparkline, cumulativeCY, cumulativeLY, splits };
    }).filter(Boolean) as NonNullable<ReturnType<typeof Array.prototype.map>[number]>[];
  }, [selectedIds, periodBuckets, currentPeriod, prevPeriod, lyPeriod, sortedPeriods, periodMode, splitBuckets, planVsActual]);

  // Period label
  const periodLabel = periodMode === 'weeks' && currentPeriod
    ? weekRangeLabel(currentPeriod)
    : currentPeriod || '--';

  // Group catalog by group
  const groupedCatalog = useMemo(() => {
    const groups: Record<string, KpiMeasureDef[]> = {};
    KPI_CATALOG.forEach(m => {
      if (!groups[m.group]) groups[m.group] = [];
      groups[m.group].push(m);
    });
    return Object.entries(groups);
  }, []);

  return (
    <div className="space-y-4">
      {/* Active Alerts at Top */}
      <div className="mb-2">
        <AlertsSummaryCard />
      </div>

      {/* Sticky Header Bar */}
      <div className="sticky top-[46px] z-30 -mx-4 px-4 py-2" style={{ background: 'var(--color-bg)', borderBottom: '1px solid var(--color-border)', backdropFilter: 'blur(12px)' }}>
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-[20px] font-bold tracking-tight" style={{ color: 'var(--color-text)' }}>
              KPI Board
            </h1>
            <p className="text-[12px] font-mono mt-0.5" style={{ color: 'var(--color-faint)' }}>
              {periodLabel} · {selectedIds.length} KPIs · {measureIds.length} measures
            </p>
          </div>

          {/* Customize button */}
          <div className="relative">
            <button
              onClick={() => setShowCustomize(p => !p)}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-[11px] font-semibold border transition-all cursor-pointer"
              style={{
                background: showCustomize ? 'rgba(96,165,250,0.08)' : 'var(--color-card)',
                borderColor: showCustomize ? 'rgba(96,165,250,0.3)' : 'var(--color-border)',
                color: showCustomize ? '#60a5fa' : 'var(--color-muted)',
              }}
            >
              <Plus size={12} />
              Customize
            </button>

            {showCustomize && (
              <>
                <div className="fixed inset-0 z-40" onClick={() => setShowCustomize(false)} />
                <div className="absolute right-0 top-full mt-1 z-50 w-[1100px] max-w-[95vw] max-h-[70vh] overflow-y-auto rounded-xl py-3 px-4 grid grid-cols-5 gap-6"
                  style={{ background: 'var(--color-card)', border: '1px solid var(--color-border)', boxShadow: 'var(--shadow-float)' }}>
                  
                  {/* Column 1: KPIs */}
                  <div>
                    <div className="text-[11px] uppercase font-bold tracking-wider mb-2" style={{ color: 'var(--color-text)', borderBottom: '1px solid var(--color-border)', paddingBottom: '4px' }}>
                      KPIs
                    </div>
                    {groupedCatalog.map(([group, items]) => (
                      <div key={group} className="mb-2">
                        <div className="text-[9px] uppercase font-semibold tracking-wider mt-1" style={{ color: 'var(--color-faint)' }}>
                          {group}
                        </div>
                        <div className="space-y-0.5">
                          {items.map(m => (
                            <label key={m.id} className="flex items-center gap-2.5 px-2 py-1 cursor-pointer transition-colors hover:bg-white/[.03] rounded">
                              <input type="checkbox" checked={selectedIds.includes(m.id)} onChange={() => toggleMeasure(m.id)} className="rounded border-border" />
                              <span className="w-2 h-2 rounded-full shrink-0" style={{ background: m.color }} />
                              <span className="text-[11px]" style={{ color: 'var(--color-text)' }}>{m.label}</span>
                            </label>
                          ))}
                        </div>
                      </div>
                    ))}
                    <div className="flex gap-2 mt-2 pt-2" style={{ borderTop: '1px solid var(--color-border)' }}>
                      <button onClick={() => setSelectedIds(DEFAULT_IDS)} className="text-[10px] font-medium" style={{ color: 'var(--color-faint)' }}>Reset</button>
                      <button onClick={() => setSelectedIds(KPI_CATALOG.map(m => m.id))} className="text-[10px] font-medium" style={{ color: '#60a5fa' }}>All</button>
                    </div>
                  </div>

                  {/* Column 2: Measures */}
                  <div>
                    <div className="text-[11px] uppercase font-bold tracking-wider mb-2" style={{ color: 'var(--color-text)', borderBottom: '1px solid var(--color-border)', paddingBottom: '4px' }}>
                      Measures
                    </div>
                    <div className="space-y-1">
                      {MEASURE_CARDS.map(m => (
                        <label key={m.id} className="flex items-center gap-2.5 px-2 py-1.5 cursor-pointer transition-colors hover:bg-white/[.03] rounded">
                          <input type="checkbox" checked={measureIds.includes(m.id)} onChange={() => toggleMeasureCard(m.id)} className="rounded border-border" />
                          <span className="w-2 h-2 rounded-full shrink-0" style={{ background: m.color }} />
                          <div className="flex flex-col">
                            <span className="text-[11px] font-medium" style={{ color: 'var(--color-text)' }}>{m.label}</span>
                            <span className="text-[9px]" style={{ color: 'var(--color-muted)' }}>{m.description}</span>
                          </div>
                        </label>
                      ))}
                    </div>
                    <div className="flex gap-2 mt-2 pt-2" style={{ borderTop: '1px solid var(--color-border)' }}>
                      <button onClick={() => setMeasureIds(DEFAULT_MEASURES)} className="text-[10px] font-medium" style={{ color: 'var(--color-faint)' }}>Reset</button>
                      <button onClick={() => setMeasureIds(MEASURE_CARDS.map(m => m.id))} className="text-[10px] font-medium" style={{ color: '#60a5fa' }}>All</button>
                    </div>
                  </div>

                  {/* Column 3: Specials */}
                  <div>
                    <div className="text-[11px] uppercase font-bold tracking-wider mb-2" style={{ color: 'var(--color-text)', borderBottom: '1px solid var(--color-border)', paddingBottom: '4px' }}>
                      Special Cards
                    </div>
                    <div className="space-y-1">
                      {SPECIAL_CARDS.map(m => (
                        <label key={m.id} className="flex items-center gap-2.5 px-2 py-1.5 cursor-pointer transition-colors hover:bg-white/[.03] rounded">
                          <input type="checkbox" checked={specialIds.includes(m.id)} onChange={() => toggleSpecial(m.id)} className="rounded border-border" />
                          <span className="text-[14px] shrink-0">{m.icon}</span>
                          <div className="flex flex-col">
                            <span className="text-[11px] font-medium" style={{ color: m.color }}>{m.label}</span>
                            <span className="text-[9px]" style={{ color: 'var(--color-muted)' }}>{m.description}</span>
                          </div>
                        </label>
                      ))}
                    </div>
                  </div>

                  {/* Column 4: Focus Cards */}
                  <div>
                      <div className="text-[11px] uppercase font-bold tracking-wider mb-2" style={{ color: 'var(--color-text)', borderBottom: '1px solid var(--color-border)', paddingBottom: '4px' }}>
                        Focus Cards
                      </div>
                      <div className="space-y-1">
                        {PARETO_CARDS.filter(m => m.category === 'Focus Cards').map(m => (
                          <label key={m.id} className="flex items-center gap-2.5 px-2 py-1.5 cursor-pointer transition-colors hover:bg-white/[.03] rounded">
                            <input type="checkbox" checked={paretoIds.includes(m.id)} onChange={() => togglePareto(m.id)} className="rounded border-border" />
                            <span className="text-[14px] shrink-0">{m.icon}</span>
                            <div className="flex flex-col">
                              <span className="text-[11px] font-medium" style={{ color: m.color }}>{m.label}</span>
                              <span className="text-[9px]" style={{ color: 'var(--color-muted)' }}>{m.description}</span>
                            </div>
                          </label>
                        ))}
                      </div>
                  </div>

                  {/* Column 5: Trend Cards */}
                  <div>
                      <div className="text-[11px] uppercase font-bold tracking-wider mb-2" style={{ color: 'var(--color-text)', borderBottom: '1px solid var(--color-border)', paddingBottom: '4px' }}>
                        Trend Cards
                      </div>
                      <div className="space-y-1">
                        {PARETO_CARDS.filter(m => m.category === 'Trend Cards').map(m => (
                          <label key={m.id} className="flex items-center gap-2.5 px-2 py-1.5 cursor-pointer transition-colors hover:bg-white/[.03] rounded">
                            <input type="checkbox" checked={paretoIds.includes(m.id)} onChange={() => togglePareto(m.id)} className="rounded border-border" />
                            <span className="text-[14px] shrink-0">{m.icon}</span>
                            <div className="flex flex-col">
                              <span className="text-[11px] font-medium" style={{ color: m.color }}>{m.label}</span>
                              <span className="text-[9px]" style={{ color: 'var(--color-muted)' }}>{m.description}</span>
                            </div>
                          </label>
                        ))}
                      </div>
                      <div className="flex gap-2 mt-4 pt-2" style={{ borderTop: '1px solid var(--color-border)' }}>
                        <button onClick={() => setParetoIds(DEFAULT_PARETO)} className="text-[10px] font-medium" style={{ color: 'var(--color-faint)' }}>Reset</button>
                        <button onClick={() => setParetoIds(PARETO_CARDS.map(m => m.id))} className="text-[10px] font-medium" style={{ color: '#60a5fa' }}>All</button>
                      </div>
                  </div>

                </div>
              </>
            )}
          </div>
        </div>
      </div>
      {/* KPI Grid — Drag & Drop */}
      <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleKpiDragEnd}>
        <SortableContext items={selectedIds} strategy={rectSortingStrategy}>
          <div className="grid gap-3" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))' }}>
            {cards.map((card, i) => (
              <SortableKpiCard
                key={card.id}
                card={card}
                stagger={i}
                onRemove={() => removeMeasure(card.id)}
                canRemove={selectedIds.length > 1}
                isDetail={(cardSizes[card.id] || 'expanded') === 'detail'}
                onToggleSize={() => toggleSize(card.id)}
                periodType={filters.periodType}
              />
            ))}
          </div>
        </SortableContext>
      </DndContext>

      {selectedIds.length === 0 && (
        <div className="text-center py-12 text-[14px]" style={{ color: 'var(--color-faint)' }}>
          Click <strong>Customize</strong> to add measures to your KPI board.
        </div>
      )}

      {/* ── Measures Section ── */}
      <MeasuresSection data={data} family={filters.family} product={filters.product} currentPeriod={currentPeriod} periodMode={periodMode} periodType={filters.periodType} measureIds={measureIds} />

      {/* ── Specials Section ── */}
      <div className="grid gap-3 mb-4" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))' }}>
        {specialIds.includes('price_scenario') && (
          <div className="relative group">
            <button onClick={() => removeSpecial('price_scenario')} className="absolute top-2 right-2 z-10 p-1 rounded hover:bg-white/10 opacity-0 group-hover:opacity-100 transition-opacity">
              <X size={12} className="text-[var(--color-faint)] hover:text-[var(--color-text)]" />
            </button>
            {(() => {
              const currentBucket = periodBuckets[currentPeriod] || null;
              const currentSales = currentBucket ? resolveValue(currentBucket, 'sales') : 0;
              const currentOrders = currentBucket ? resolveValue(currentBucket, 'orders') : 0;
              const currentCogs = currentBucket ? resolveValue(currentBucket, 'cogs') : 0;
              const currentAdCost = currentBucket ? resolveValue(currentBucket, 'ad_cost') : 0;
              const currentNetProfit = currentBucket ? resolveValue(currentBucket, 'net_profit') : 0;

              return (
                <PriceScenarioCard 
                  currentSales={currentSales}
                  currentOrders={currentOrders}
                  currentCogs={currentCogs}
                  currentAdCost={currentAdCost}
                  currentNetProfit={currentNetProfit}
                />
              );
            })()}
          </div>
        )}
      </div>

      {/* ── Pareto Section ── */}
      <ParetoSection
        data={data}
        paretoIds={paretoIds}
        family={filters.family}
        product={filters.product}
        currentPeriod={currentPeriod}
        prevPeriod={prevPeriod}
        periodMode={periodMode}
        periodType={filters.periodType}
        perfMaxDate={data._meta?.data_freshness?.performance_max_date || ''}
        togglePareto={togglePareto}
        removePareto={removePareto}
        sensors={sensors}
        onDragEnd={handleParetoDragEnd}
        cardSizes={cardSizes}
        toggleSize={toggleSize}
      />
    </div>
  );
}

/* ── Cumulative Bar + Line Canvas ── */
function CumulativeBarCanvas({ cy, ly, color, width, height }: {
  cy: number[]; ly: number[]; color: string; width: number; height: number;
}) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const cvs = ref.current;
    if (!cvs) return;
    const ctx = cvs.getContext('2d');
    if (!ctx) return;
    const dpr = window.devicePixelRatio || 1;
    cvs.width = width * dpr;
    cvs.height = height * dpr;
    ctx.scale(dpr, dpr);
    ctx.clearRect(0, 0, width, height);

    const all = [...cy, ...ly];
    const maxVal = Math.max(...all, 1);
    const n = Math.max(cy.length, ly.length, 1);
    const pad = 2;
    const barW = Math.max(2, (width - pad * 2) / n - 2);
    const usableH = height - pad * 2;

    // CY bars
    cy.forEach((v, i) => {
      const x = pad + i * ((width - pad * 2) / n) + 1;
      const h = (v / maxVal) * usableH;
      ctx.fillStyle = color + '60';
      ctx.fillRect(x, height - pad - h, barW, h);
    });

    // LY line
    if (ly.length > 1) {
      ctx.beginPath();
      ctx.strokeStyle = color;
      ctx.lineWidth = 1.5;
      ctx.setLineDash([3, 2]);
      ctx.globalAlpha = 0.5;
      ly.forEach((v, i) => {
        const x = pad + i * ((width - pad * 2) / n) + barW / 2 + 1;
        const y = height - pad - (v / maxVal) * usableH;
        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      });
      ctx.stroke();
      ctx.globalAlpha = 1;
      ctx.setLineDash([]);
    }
  }, [cy, ly, color, width, height]);

  return <canvas ref={ref} style={{ width, height }} />;
}

/* ── Sortable KPI Card ── */
type KpiCardData = {
  id: string;
  def: KpiMeasureDef;
  value: number;
  prevValue: number | null;
  lyValue: number | null;
  delta: number | null;
  positive: boolean;
  sentiment: boolean;
  sparkline: number[];
  cumulativeCY: number[];
  cumulativeLY: number[];
  splits: SplitItem[];
};

function SortableKpiCard({ card, stagger, onRemove, canRemove, isDetail, onToggleSize, periodType }: {
  card: KpiCardData;
  stagger: number;
  onRemove: () => void;
  canRemove: boolean;
  isDetail?: boolean;
  onToggleSize: () => void;
  periodType?: string;
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: card.id });
  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
    zIndex: isDragging ? 50 : 'auto' as const,
  };

  const { def, value, prevValue, lyValue, delta, sentiment, sparkline, cumulativeCY, cumulativeLY, splits } = card;
  const deltaColor = sentiment ? 'var(--color-positive)' : 'var(--color-negative)';
  const isCumulative = periodType === 'cumulative';

  return (
    <div
      ref={setNodeRef}
      style={{
        ...style,
        background: 'var(--color-card)',
        border: '1px solid var(--color-border)',
        borderLeft: `3px solid ${def.color}`,
        boxShadow: 'var(--shadow-card)',
        animationDelay: `${stagger * 0.04}s`,
      }}
      className="group relative rounded-xl p-4 transition-all duration-200 card-lift"
    >
      {/* Drag handle */}
      <button
        {...attributes}
        {...listeners}
        className="absolute top-2 left-2 opacity-0 group-hover:opacity-40 hover:!opacity-80 transition-opacity cursor-grab active:cursor-grabbing"
        style={{ color: 'var(--color-faint)' }}
        title="Drag to reorder"
      >
        <GripVertical size={12} />
      </button>

      {/* Top-right action buttons */}
      <div className="absolute top-2 right-2 flex items-center gap-2 opacity-0 group-hover:opacity-60 hover:!opacity-100 transition-opacity z-10">
        <button onClick={onToggleSize} className="p-1 hover:bg-white/5 rounded" style={{ color: 'var(--color-faint)' }} title={isDetail ? 'Collapse' : 'Expand'}>
          {isDetail ? <Minimize2 size={12} /> : <Maximize2 size={12} />}
        </button>
        {canRemove && (
          <button onClick={onRemove} className="p-1 hover:bg-white/5 rounded" style={{ color: 'var(--color-faint)' }}>
            <X size={14} />
          </button>
        )}
      </div>

      {/* Top row: Label */}
      <div className="flex items-center justify-between mb-1 pr-6">
        <span className="font-mono text-[11px] uppercase tracking-[0.1em] font-semibold" style={{ color: def.color }}>
          {def.label}
        </span>
      </div>

      {/* Hero value + Sparkline */}
      <div className="flex items-end justify-between">
        <div className="flex flex-col">
          <div className={`font-mono font-bold leading-none tracking-tight ${isDetail ? 'text-[28px]' : 'text-[24px]'}`} style={{ color: 'var(--color-text)' }}>
            {def.fmt(value)}
          </div>
          {/* Delta vs LY or Prev right under the value */}
          <div className="flex flex-col gap-0.5 mt-1">
            {delta != null && (
              <span className="font-mono text-[11px] font-bold" style={{ color: deltaColor }}>
                {sentiment ? '▲' : '▼'} {Math.abs(delta).toFixed(1)}%
              </span>
            )}
            {lyValue != null && lyValue !== 0 && (
              <div className="flex items-center gap-1.5 mt-0.5">
                <span className="font-mono text-[10px] uppercase tracking-wider" style={{ color: 'var(--color-faint)' }}>LY</span>
                <span className="font-mono text-[11px] font-medium" style={{ color: 'var(--color-subtle)' }}>
                  {def.fmtCompact(lyValue)}
                </span>
                {value !== 0 && lyValue !== 0 && (
                  <span className="font-mono text-[10px]" style={{
                    color: ((value - lyValue) / Math.abs(lyValue)) >= 0 ? 'var(--color-positive)' : 'var(--color-negative)',
                  }}>
                    {((value - lyValue) / Math.abs(lyValue) * 100) >= 0 ? '+' : ''}{((value - lyValue) / Math.abs(lyValue) * 100).toFixed(0)}%
                  </span>
                )}
              </div>
            )}
          </div>
        </div>
        
        {isCumulative && cumulativeCY.length > 1 ? (
          <div style={{ width: isDetail ? 160 : 100, height: isDetail ? 48 : 28 }}>
            <CumulativeBarCanvas cy={cumulativeCY} ly={cumulativeLY} color={def.color} width={isDetail ? 160 : 100} height={isDetail ? 48 : 28} />
          </div>
        ) : sparkline.length > 1 ? (
          <div style={{ width: isDetail ? 120 : 64, height: isDetail ? 36 : 20, position: 'relative' }}>
            <SparklineCanvas
              data={sparkline}
              color={def.color}
              glow={def.glow}
              width={isDetail ? 120 : 64}
              height={isDetail ? 36 : 20}
              padTop={2}
              padBottom={2}
              strokeWidth={isDetail ? 2 : 1.5}
              dotRadius={isDetail ? 3 : 2}
            />
            {isDetail && sparkline.length > 0 && (
              <span className="absolute -bottom-3 right-0 font-mono text-[8px] font-semibold" style={{ color: def.color }}>
                {def.fmtCompact(sparkline[sparkline.length - 1])}
              </span>
            )}
          </div>
        ) : null}
      </div>

      {/* Family / Product split */}
      {splits.length > 1 && (() => {
        const isRatio = !!def.isAvg;
        splits.sort((a, b) => b.value - a.value);
        const absValues = splits.map(s => Math.abs(s.value));
        const total = absValues.reduce((a, b) => a + b, 0);
        if (total === 0) return null;

        if (isRatio) {
          if (!isDetail) {
            return (
              <div className="flex flex-wrap gap-x-2.5 gap-y-1 mt-3 pt-2 border-t border-white/5">
                {splits.map((s, i) => (
                  <span key={i} className="font-mono text-[9.5px] flex items-center gap-1 leading-none" style={{ color: 'var(--color-subtle)' }}>
                    <span style={{ width: 4, height: 4, borderRadius: '50%', background: s.color }} />
                    {s.label.split(' ')[0]} <span style={{ color: 'var(--color-text)' }}>{def.fmtCompact(s.value)}</span>
                  </span>
                ))}
              </div>
            );
          }

          return (
            <div style={{ marginTop: 12, display: 'flex', flexDirection: 'column', gap: 6 }}>
              {splits.map((s, i) => (
                <div key={i} className="flex flex-col gap-1">
                  <div className="flex justify-between items-end">
                    <span className="font-mono text-[10px] text-[var(--color-muted)] flex items-center gap-1.5">
                      <span style={{ width: 6, height: 6, borderRadius: '50%', background: s.color }} />
                      {s.label}
                    </span>
                    <span className="font-mono text-[10px] font-bold" style={{ color: 'var(--color-text)' }}>
                      {def.fmtCompact(s.value)}
                    </span>
                  </div>
                  <div className="w-full h-1 bg-white/5 rounded-full overflow-hidden relative">
                    <div
                      className="absolute top-0 left-0 h-full rounded-full"
                      style={{
                        width: `${Math.min(Math.max(s.value, 0), 150)}%`,
                        background: s.color,
                        opacity: 0.8
                      }}
                    />
                    {/* Target line at 100% */}
                    <div className="absolute top-0 bottom-0 w-[1px] bg-[var(--color-text)] z-10 opacity-30" style={{ left: '100%' }} />
                  </div>
                </div>
              ))}
            </div>
          );
        }

        // Detail mode: donut chart
        if (isDetail) {
          const size = 80;
          const cx = size / 2, cy = size / 2, r = 28, sw = 10;
          let cumAngle = -Math.PI / 2;
          const arcs = splits.map((s, i) => {
            const share = absValues[i] / total;
            const angle = share * 2 * Math.PI;
            const startAngle = cumAngle;
            cumAngle += angle;
            const endAngle = cumAngle;
            const largeArc = angle > Math.PI ? 1 : 0;
            const x1 = cx + r * Math.cos(startAngle);
            const y1 = cy + r * Math.sin(startAngle);
            const x2 = cx + r * Math.cos(endAngle);
            const y2 = cy + r * Math.sin(endAngle);
            return { ...s, share, d: `M ${x1} ${y1} A ${r} ${r} 0 ${largeArc} 1 ${x2} ${y2}`, i };
          });
          return (
            <div style={{ display: 'flex', gap: 12, marginTop: 10, alignItems: 'center' }}>
              <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
                {arcs.map(a => (
                  <path key={a.i} d={a.d} fill="none" stroke={a.color} strokeWidth={sw}
                    strokeLinecap="butt" />
                ))}
              </svg>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
                {splits.map((s, i) => {
                  const share = absValues[i] / total;
                  return (
                    <span key={i} style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 10, color: 'var(--color-faint)', fontFamily: 'var(--font-mono, monospace)' }}>
                      <span style={{ width: 8, height: 8, borderRadius: '50%', background: s.color, flexShrink: 0 }} />
                      <span style={{ color: 'var(--color-subtle)' }}>{s.label}</span>
                      <span style={{ color: 'var(--color-text)', fontWeight: 600 }}>{`${(share * 100).toFixed(0)}%`}</span>
                      <span style={{ color: 'var(--color-faint)', fontWeight: 400 }}>{` (${def.fmtCompact(s.value)})`}</span>
                    </span>
                  );
                })}
              </div>
            </div>
          );
        }

        // Expanded mode: horizontal split bar
        return (
          <div style={{ marginTop: 8 }}>
            <div style={{ display: 'flex', height: 5, borderRadius: 3, overflow: 'hidden', gap: 1 }}>
              {splits.map((s, i) => {
                const share = absValues[i] / total;
                return (
                  <div
                    key={i}
                    title={`${s.label}: ${def.fmtCompact(s.value)} (${(share * 100).toFixed(0)}%)`}
                    style={{
                      flex: share * 100,
                      background: s.color,
                      minWidth: 2,
                      borderRadius: i === 0 ? '3px 0 0 3px' : i === splits.length - 1 ? '0 3px 3px 0' : 0,
                      cursor: 'default',
                    }}
                  />
                );
              })}
            </div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px 8px', marginTop: 4 }}>
              {splits.map((s, i) => {
                const share = absValues[i] / total;
                return (
                  <span key={i} style={{ display: 'flex', alignItems: 'center', gap: 3, fontSize: 9, color: 'var(--color-faint)', fontFamily: 'var(--font-mono, monospace)' }}>
                    <span style={{ width: 6, height: 6, borderRadius: '50%', background: s.color, flexShrink: 0 }} />
                    {s.label} {(share * 100).toFixed(0)}% <span style={{ color: 'var(--color-subtle)' }}>({def.fmtCompact(s.value)})</span>
                  </span>
                );
              })}
            </div>
          </div>
        );
      })()}
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════════════
   Pareto Section — Winners / Losers / Other for granular dimensions
   ═══════════════════════════════════════════════════════════════════ */

function ParetoSection({ data, paretoIds, family, product, currentPeriod, prevPeriod, periodMode, periodType, perfMaxDate, togglePareto, removePareto, sensors, onDragEnd, cardSizes, toggleSize }: {
  data: DashboardData;
  paretoIds: ParetoCardId[];
  family: string | null;
  product: string | null;
  currentPeriod: string;
  prevPeriod: string;
  periodMode: string;
  periodType: string;
  perfMaxDate: string;
  togglePareto: (id: ParetoCardId) => void;
  removePareto: (id: ParetoCardId) => void;
  sensors: ReturnType<typeof useSensors>;
  onDragEnd: (event: DragEndEvent) => void;
  cardSizes: Record<string, CardSize>;
  toggleSize: (id: string) => void;
}) {
  // Compute date range from selected period
  const { periodStart, periodEnd, prevPeriodStart, prevPeriodEnd } = useMemo(() => {
    if (!currentPeriod) return { periodStart: '', periodEnd: '', prevPeriodStart: '', prevPeriodEnd: '' };

    let pStart = '';
    let pEnd = '';
    let ppStart = '';
    let ppEnd = '';

    if (periodMode === 'weeks') {
      pStart = currentPeriod;
      const d = new Date(pStart + 'T12:00:00Z');
      d.setUTCDate(d.getUTCDate() + 6);
      pEnd = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
      // Prev week
      ppStart = addDays(pStart, -7);
      ppEnd = addDays(pEnd, -7);
    } else if (periodMode === 'month') {
      const [y, m] = currentPeriod.split('-');
      pStart = `${y}-${m}-01`;
      const last = new Date(Number(y), Number(m), 0);
      pEnd = `${y}-${m}-${String(last.getDate()).padStart(2, '0')}`;
      // Prev month
      const pd = new Date(Number(y), Number(m) - 2, 1); // month is 0-indexed, so m-2
      ppStart = `${pd.getFullYear()}-${String(pd.getMonth() + 1).padStart(2, '0')}-01`;
      const pLast = new Date(pd.getFullYear(), pd.getMonth() + 1, 0);
      ppEnd = `${pd.getFullYear()}-${String(pd.getMonth() + 1).padStart(2, '0')}-${String(pLast.getDate()).padStart(2, '0')}`;
    } else if (periodMode === 'quarter') {
      const [y, q] = currentPeriod.split('-');
      const qn = parseInt(q.replace('Q', ''), 10);
      const sm = (qn - 1) * 3 + 1;
      const em = sm + 2;
      pStart = `${y}-${String(sm).padStart(2, '0')}-01`;
      const last = new Date(Number(y), em, 0);
      pEnd = `${y}-${String(em).padStart(2, '0')}-${String(last.getDate()).padStart(2, '0')}`;
      // Prev quarter
      const pqn = qn === 1 ? 4 : qn - 1;
      const pqy = qn === 1 ? Number(y) - 1 : Number(y);
      const psm = (pqn - 1) * 3 + 1;
      const pem = psm + 2;
      ppStart = `${pqy}-${String(psm).padStart(2, '0')}-01`;
      const pLast = new Date(pqy, pem, 0);
      ppEnd = `${pqy}-${String(pem).padStart(2, '0')}-${String(pLast.getDate()).padStart(2, '0')}`;
    } else {
      // Year
      pStart = `${currentPeriod}-01-01`;
      pEnd = `${currentPeriod}-12-31`;
      ppStart = `${Number(currentPeriod) - 1}-01-01`;
      ppEnd = `${Number(currentPeriod) - 1}-12-31`;
    }

    // Cap current period end at perfMaxDate when the period is incomplete
    if (periodType === 'current' && perfMaxDate && perfMaxDate < pEnd) {
      pEnd = perfMaxDate;
      // Cap previous period to the same day offset for apples-to-apples comparison
      const curDays = Math.round((new Date(pEnd + 'T12:00:00Z').getTime() - new Date(pStart + 'T12:00:00Z').getTime()) / 86400000);
      ppEnd = addDays(ppStart, curDays);
    }

    return { periodStart: pStart, periodEnd: pEnd, prevPeriodStart: ppStart, prevPeriodEnd: ppEnd };
  }, [currentPeriod, periodMode, periodType, perfMaxDate]);

  // Filter actions by family and product (for term-level data — Coach snapshot)
  const actions = useMemo(() => {
    let rows = data.actions || [];
    if (family) rows = rows.filter(r => famFromType(r.parent_name) === family);
    if (product) {
      const pInfo = (data.products || []).find(p => p.asin === product);
      if (pInfo?.product_short_name) rows = rows.filter(r => r.product_short_name === pInfo.product_short_name);
      else rows = rows.filter(r => r.asin === product);
    }
    return rows;
  }, [data.actions, family, product, data.products]);

  // Filter ads_7d by period and family (for campaign-level, date-filterable)
  const ads7d = useMemo(() => {
    let rows = data.ads_7d || [];
    if (periodStart && periodEnd) {
      rows = rows.filter(r => {
        const d = r.date || r.week_start || '';
        return d >= periodStart && d <= periodEnd;
      });
    }
    if (product) {
      const pInfo = (data.products || []).find(p => p.asin === product);
      if (pInfo?.product_short_name) rows = rows.filter(r => r.product_short_name === pInfo.product_short_name);
      else rows = rows.filter(r => r.asin === product);
    }
    else if (family) rows = rows.filter(r => famFromType(r.parent_name ?? r.product_short_name ?? null) === family);
    return rows;
  }, [data.ads_7d, periodStart, periodEnd, family, product, data.products]);

  // Filter SQP by period and family
  const sqp = useMemo(() => {
    let rows = data.sqp_weekly || [];
    if (periodStart && periodEnd) {
      rows = rows.filter(r => r.week_start >= periodStart && r.week_start <= periodEnd);
    }
    if (product) {
      const pInfo = (data.products || []).find(p => p.asin === product);
      if (pInfo?.product_short_name) rows = rows.filter(r => r.product_short_name === pInfo.product_short_name);
      else rows = rows.filter(r => r.asin === product);
    }
    else if (family) rows = rows.filter(r => famFromType(r.product_type) === family);
    return rows;
  }, [data.sqp_weekly, periodStart, periodEnd, family, product, data.products]);

  // Build Pareto data for each dimension
  const paretoData = useMemo(() => {
    const result: Record<ParetoCardId, ParetoItem[]> = {
      ads_targets: [],
      ads_terms: [],
      ads_campaigns: [],
      ads_cpc_buckets: [],
      sqp_terms: [],
      best_product_profit: [],
      best_product_units: [],
      profit_movers: [],
      term_profit_movers: [],
      keyword_profit_movers: [],
      ads_strategy: [],
      campaign_launch: [],
    };

    // — Ads Targets: group actions by targeting keyword (Coach data) —
    // ads_7d doesn't include searchTerm dimension (too heavy), so Coach data
    // is the source for keyword-level metrics. Coach data is always Last 30 Days (_4w).
    const targetMap: Record<string, { spend: number; orders: number; profit: number; sales: number }> = {};
    actions.forEach(a => {
      // Skip rows where both targeting and search_term are null (SB/AUTO campaigns
      // where Amazon doesn't report keyword-level data — not actionable)
      if (!a.targeting && !a.search_term) return;
      const key = a.targeting || a.search_term || '(unknown)';
      if (!targetMap[key]) targetMap[key] = { spend: 0, orders: 0, profit: 0, sales: 0 };
      targetMap[key].spend += a.ads_spend_4w || 0;
      targetMap[key].orders += a.ads_orders_4w || 0;
      targetMap[key].profit += a.ads_net_profit_4w || 0;
      targetMap[key].sales += a.ads_sales_4w || 0;
    });
    result.ads_targets = Object.entries(targetMap)
      .map(([name, d]) => ({
        name,
        spend: d.spend,
        orders: d.orders,
        profit: d.profit,
        roas: d.spend > 0 ? d.sales / d.spend : null,
        bucket: classifyBucket(d.profit, d.spend),
      }));
    result.ads_targets.sort((a, b) => {
      if (a.bucket === 'loser' && b.bucket === 'loser') return a.profit - b.profit;
      return b.profit - a.profit;
    });

    // — Ads Terms (Focus Terms): Compute locally from actions
    const adsTermsMap: Record<string, { spend: number; orders: number; profit: number; sales: number; count: number }> = {};
    actions.forEach(a => {
      const st = a.search_term || '(unknown)';
      if (!adsTermsMap[st]) adsTermsMap[st] = { spend: 0, orders: 0, profit: 0, sales: 0, count: 0 };
      const sp = a.ads_spend_4w || 0;
      const ord = a.ads_orders_4w || 0;
      const np = a.ads_net_profit_4w ?? ((a.margin_per_unit || 0) * ord - sp);
      adsTermsMap[st].spend += sp;
      adsTermsMap[st].orders += ord;
      adsTermsMap[st].profit += np;
      adsTermsMap[st].sales += a.ads_sales_4w || 0;
      adsTermsMap[st].count += 1;
    });

    const allTerms = Object.entries(adsTermsMap).map(([key, d]) => ({
      name: key,
      spend: d.spend,
      orders: d.orders,
      profit: d.profit,
      roas: d.spend > 0 ? d.sales / d.spend : null,
      bucket: (d.profit >= 0 ? 'winner' : 'loser') as ParetoItem['bucket'],
      count: d.count,
    }));

    // Pre-aggregate into Top 10 + Other so the UI shows 'Other Losers' as a term
    const top10TermWinners = allTerms.filter(t => t.profit >= 0).sort((a, b) => b.profit - a.profit);
    const top10TermLosers = allTerms.filter(t => t.profit < 0).sort((a, b) => a.profit - b.profit);

    const finalAdsTerms: typeof allTerms = [];
    finalAdsTerms.push(...top10TermWinners.slice(0, 10));
    finalAdsTerms.push(...top10TermLosers.slice(0, 10));

    if (top10TermWinners.length > 10) {
      const rest = top10TermWinners.slice(10);
      finalAdsTerms.push({
        name: '__OTHER__other_winners',
        spend: rest.reduce((s, i) => s + i.spend, 0),
        orders: rest.reduce((s, i) => s + i.orders, 0),
        profit: rest.reduce((s, i) => s + i.profit, 0),
        roas: null,
        bucket: 'other_winners' as any,
        count: rest.reduce((s, i) => s + i.count, 0)
      });
    }

    if (top10TermLosers.length > 10) {
      const rest = top10TermLosers.slice(10);
      finalAdsTerms.push({
        name: '__OTHER__other_losers',
        spend: rest.reduce((s, i) => s + i.spend, 0),
        orders: rest.reduce((s, i) => s + i.orders, 0),
        profit: rest.reduce((s, i) => s + i.profit, 0),
        roas: null,
        bucket: 'other_losers' as any,
        count: rest.reduce((s, i) => s + i.count, 0)
      });
    }

    result.ads_terms = finalAdsTerms;
    result.ads_terms.sort((a, b) => {
      if (a.profit < 0 && b.profit < 0) return a.profit - b.profit;
      return b.profit - a.profit;
    });

    // — Ads Campaigns: group ads_7d campaign rows by campaign_name (date-filtered) —
    const campRows = ads7d.filter(r => r.row_type === 'campaign');

    // Fallback to ads_7d_summary (730 days) when ads_7d (180 days) has no data for the period
    let campaignSourceRows = campRows;
    if (campaignSourceRows.length === 0 && data.ads_7d_summary && periodStart && periodEnd) {
      let summaryRows = (data.ads_7d_summary || []).filter(r => {
        const d = r.date || r.week_start || '';
        return d >= periodStart && d <= periodEnd;
      });
      if (family) {
        const prodFamilyMap: Record<string, string> = {};
        (data.products || []).forEach(p => {
          if (p.product_short_name) prodFamilyMap[p.product_short_name] = famFromType(p.parent_name ?? p.product_short_name ?? null) || '';
        });
        const famLower = family.toLowerCase();
        summaryRows = summaryRows.filter(r => {
          const psnFamily = prodFamilyMap[r.product_short_name || ''];
          if (psnFamily) return psnFamily === family;
          const cn = (r.campaign_name || '').toLowerCase();
          return cn.includes(famLower);
        });
      }
      if (product) {
        const pInfo = (data.products || []).find(p => p.asin === product);
        if (pInfo?.product_short_name) summaryRows = summaryRows.filter(r => r.product_short_name === pInfo.product_short_name);
      }
      campaignSourceRows = summaryRows;
    }

    const campMap: Record<string, { spend: number; orders: number; profit: number; sales: number }> = {};
    campaignSourceRows.forEach(r => {
      const key = r.campaign_name || '(unknown)';
      if (!campMap[key]) campMap[key] = { spend: 0, orders: 0, profit: 0, sales: 0 };
      campMap[key].spend += r.spend || 0;
      campMap[key].orders += r.orders || 0;
      campMap[key].profit += (r.gross_profit || 0) - (r.spend || 0);
      campMap[key].sales += r.sales || 0;
    });
    result.ads_campaigns = Object.entries(campMap)
      .map(([name, d]) => ({
        name,
        spend: d.spend,
        orders: d.orders,
        profit: d.profit,
        roas: d.spend > 0 ? d.sales / d.spend : null,
        bucket: classifyBucket(d.profit, d.spend),
      }));
    result.ads_campaigns.sort((a, b) => {
      if (a.bucket === 'loser' && b.bucket === 'loser') return a.profit - b.profit;
      return b.profit - a.profit;
    });

    // — Ads CPC Buckets: group campaign rows by CPC range —
    // Reuse the same source rows (with summary fallback already applied)
    const cpcSourceRows = campaignSourceRows;
    const cpcBuckets: { label: string; min: number; max: number }[] = [
      { label: '$0 – $0.30', min: 0, max: 0.30 },
      { label: '$0.30 – $0.40', min: 0.30, max: 0.40 },
      { label: '$0.40 – $0.50', min: 0.40, max: 0.50 },
      { label: '$0.50 – $0.60', min: 0.50, max: 0.60 },
      { label: '$0.60 – $0.75', min: 0.60, max: 0.75 },
      { label: '$0.75 – $1.00', min: 0.75, max: 1.00 },
      { label: '$1.00 – $1.50', min: 1.00, max: 1.50 },
      { label: '$1.50+', min: 1.50, max: Infinity },
    ];
    const cpcBucketMap: Record<string, { spend: number; orders: number; profit: number; clicks: number }> = {};
    cpcBuckets.forEach(b => { cpcBucketMap[b.label] = { spend: 0, orders: 0, profit: 0, clicks: 0 }; });
    cpcSourceRows.forEach(r => {
      // Use per-row CPC: spend / clicks (more accurate than the reported cpc which is an average)
      const rowCpc = r.clicks > 0 ? (r.spend || 0) / r.clicks : 0;
      if (rowCpc <= 0 && (r.clicks || 0) === 0) return; // skip rows with no clicks
      const bucket = cpcBuckets.find(b => rowCpc >= b.min && rowCpc < b.max) || cpcBuckets[cpcBuckets.length - 1];
      cpcBucketMap[bucket.label].spend += r.spend || 0;
      cpcBucketMap[bucket.label].orders += r.orders || 0;
      cpcBucketMap[bucket.label].profit += (r.gross_profit || 0) - (r.spend || 0);
      cpcBucketMap[bucket.label].clicks += r.clicks || 0;
    });
    result.ads_cpc_buckets = cpcBuckets.map(b => ({
      name: b.label,
      spend: cpcBucketMap[b.label].spend,
      orders: cpcBucketMap[b.label].orders,
      profit: cpcBucketMap[b.label].profit,
      roas: cpcBucketMap[b.label].spend > 0
        ? cpcBucketMap[b.label].profit / cpcBucketMap[b.label].spend
        : null,
      bucket: 'other' as const,
    })).filter(b => b.spend > 0 || b.orders > 0);

    // — Profit Movers: WoW/MoM Profit Deltas per ASIN —
    // Use weekly data with date-range filtering for apples-to-apples comparison
    if (periodStart && prevPeriodStart) {
      let trendData: any[] = data.weekly_trends_by_asin || [];
      
      // Filter by global family / product constraints
      if (family) trendData = trendData.filter((r: any) => famFromType(r.product_type) === family);
      if (product) trendData = trendData.filter((r: any) => r.asin === product);

      const mapCurrent: Record<string, number> = {};
      const mapPrev: Record<string, number> = {};
      const mapCurrentSpend: Record<string, number> = {};
      const mapCurrentOrders: Record<string, number> = {};
      const nameMap: Record<string, string> = {};

      trendData.forEach((r: any) => {
        const d = r.week_start || '';
        const asin = r.asin;
        const shortName = r.product_short_name || asin;
        if (!asin || !d) return;
        
        nameMap[asin] = shortName;
        if (d >= periodStart && d <= periodEnd) {
          mapCurrent[asin] = (mapCurrent[asin] || 0) + (r.net_profit || 0);
          mapCurrentSpend[asin] = (mapCurrentSpend[asin] || 0) + (r.ad_cost || 0);
          mapCurrentOrders[asin] = (mapCurrentOrders[asin] || 0) + (r.orders || 0);
        }
        if (d >= prevPeriodStart && d <= prevPeriodEnd) mapPrev[asin] = (mapPrev[asin] || 0) + (r.net_profit || 0);
      });

      const allAsins = new Set([...Object.keys(mapCurrent), ...Object.keys(mapPrev)]);
      const moversAll: ParetoItem[] = [];

      allAsins.forEach(asin => {
        const curNp = mapCurrent[asin] || 0;
        const prevNp = mapPrev[asin] || 0;
        const delta = curNp - prevNp;
        
        // Only include if there's a non-zero change
        if (Math.abs(delta) >= 0.01) {
          moversAll.push({
            name: nameMap[asin] || asin,
            spend: mapCurrentSpend[asin] || 0,
            orders: mapCurrentOrders[asin] || 0,
            profit: delta, // Store delta in profit field for UI rendering
            roas: null,
            bucket: delta > 0 ? 'winner' : 'loser',
            count: 1,
          });
        }
      });

      // Split into winners and losers
      const mw = moversAll.filter(m => m.profit > 0).sort((a, b) => b.profit - a.profit);
      const ml = moversAll.filter(m => m.profit < 0).sort((a, b) => a.profit - b.profit); // Most negative first
      
      const finalMovers: typeof moversAll = [];
      finalMovers.push(...mw.slice(0, 10));
      finalMovers.push(...ml.slice(0, 10));
      
      if (mw.length > 10) {
        const rest = mw.slice(10);
        finalMovers.push({
          name: '__OTHER__other_winners',
          spend: 0, orders: 0, roas: null, count: rest.length,
          profit: rest.reduce((s, x) => s + x.profit, 0),
          bucket: 'other_winners'
        });
      }
      if (ml.length > 10) {
        const rest = ml.slice(10);
        finalMovers.push({
          name: '__OTHER__other_losers',
          spend: 0, orders: 0, roas: null, count: rest.length,
          profit: rest.reduce((s, x) => s + x.profit, 0),
          bucket: 'other_losers'
        });
      }
      
      result.profit_movers = finalMovers;
      result.profit_movers.sort((a, b) => {
        if (a.profit < 0 && b.profit < 0) return a.profit - b.profit;
        return b.profit - a.profit;
      });
    }

    // — Term Profit Movers: WoW Profit Deltas per Term —
    // Use focus-terms' own latest 2 weeks (may lag behind header period)
    if (data.ads_focus_terms && data.ads_focus_terms.length > 0) {
      const ftWeeks = [...new Set(data.ads_focus_terms.map(r => r.week_start))].sort();
      const ftCurrent = ftWeeks[ftWeeks.length - 1] || '';
      const ftPrev = ftWeeks.length > 1 ? ftWeeks[ftWeeks.length - 2] : '';
      if (ftCurrent && ftPrev) {
      
      const termCurrent: Record<string, number> = {};
      const termPrev: Record<string, number> = {};
      const termCurrentSpend: Record<string, number> = {};
      const termCurrentOrders: Record<string, number> = {};
      
      data.ads_focus_terms.forEach(r => {
        const pVal = r.week_start;
        const term = r.search_term;
        if (!term || term === '__OTHER__') return;
        if (pVal === ftCurrent) {
          termCurrent[term] = (termCurrent[term] || 0) + (r.net_profit || 0);
          termCurrentSpend[term] = (termCurrentSpend[term] || 0) + (r.spend || 0);
          termCurrentOrders[term] = (termCurrentOrders[term] || 0) + (r.orders || 0);
        }
        if (pVal === ftPrev) termPrev[term] = (termPrev[term] || 0) + (r.net_profit || 0);
      });

      const allTerms = new Set([...Object.keys(termCurrent), ...Object.keys(termPrev)]);
      const moversAll: ParetoItem[] = [];

      allTerms.forEach(term => {
        const curNp = termCurrent[term] || 0;
        const prevNp = termPrev[term] || 0;
        const delta = curNp - prevNp;
        
        if (Math.abs(delta) >= 0.01) {
          moversAll.push({
            name: term,
            spend: termCurrentSpend[term] || 0,
            orders: termCurrentOrders[term] || 0,
            roas: null, count: 1,
            profit: delta,
            bucket: delta > 0 ? 'winner' : 'loser',
          });
        }
      });

      // Split into winners and losers
      const mw = moversAll.filter(m => m.profit > 0).sort((a, b) => b.profit - a.profit);
      const ml = moversAll.filter(m => m.profit < 0).sort((a, b) => a.profit - b.profit);
      
      const finalMovers: typeof moversAll = [];
      finalMovers.push(...mw.slice(0, 10));
      finalMovers.push(...ml.slice(0, 10));
      
      if (mw.length > 10) {
        const rest = mw.slice(10);
        finalMovers.push({
          name: '__OTHER__other_winners', spend: 0, orders: 0, roas: null, count: rest.length,
          profit: rest.reduce((s, x) => s + x.profit, 0), bucket: 'other_winners'
        });
      }
      if (ml.length > 10) {
        const rest = ml.slice(10);
        finalMovers.push({
          name: '__OTHER__other_losers', spend: 0, orders: 0, roas: null, count: rest.length,
          profit: rest.reduce((s, x) => s + x.profit, 0), bucket: 'other_losers'
        });
      }
      
      result.term_profit_movers = finalMovers;
      result.term_profit_movers.sort((a, b) => {
        if (a.profit < 0 && b.profit < 0) return a.profit - b.profit;
        return b.profit - a.profit;
      });
      }
    }

    // — Keyword Profit Movers: WoW Profit Deltas per Keyword —
    if (data.ads_focus_keywords && data.ads_focus_keywords.length > 0) {
      const kwWeeks = [...new Set(data.ads_focus_keywords.map(r => r.week_start))].sort();
      const kwCurrent = kwWeeks[kwWeeks.length - 1] || '';
      const kwPrev = kwWeeks.length > 1 ? kwWeeks[kwWeeks.length - 2] : '';
      if (kwCurrent && kwPrev) {
        const kwCurMap: Record<string, number> = {};
        const kwPrevMap: Record<string, number> = {};
        const kwCurSpend: Record<string, number> = {};
        const kwCurOrders: Record<string, number> = {};
        data.ads_focus_keywords.forEach(r => {
          if (r.keyword === '__OTHER__') return;
          if (r.week_start === kwCurrent) {
            kwCurMap[r.keyword] = (kwCurMap[r.keyword] ?? 0) + r.net_profit;
            kwCurSpend[r.keyword] = (kwCurSpend[r.keyword] ?? 0) + (r.spend || 0);
            kwCurOrders[r.keyword] = (kwCurOrders[r.keyword] ?? 0) + (r.orders || 0);
          }
          if (r.week_start === kwPrev) kwPrevMap[r.keyword] = (kwPrevMap[r.keyword] ?? 0) + r.net_profit;
        });
        const allKw = new Set([...Object.keys(kwCurMap), ...Object.keys(kwPrevMap)]);
        const kwMovers: ProfitMoverItem[] = [];
        allKw.forEach(kw => {
          const cur = kwCurMap[kw] ?? 0;
          const prev = kwPrevMap[kw] ?? 0;
          const delta = cur - prev;
          if (delta !== 0) {
            kwMovers.push({ name: kw, profit: cur, delta, prevProfit: prev, type: 'keyword' as const, spend: kwCurSpend[kw] ?? 0, orders: kwCurOrders[kw] ?? 0 });
          }
        });
        result.keyword_profit_movers = kwMovers;
        result.keyword_profit_movers.sort((a, b) => {
          if (a.profit < 0 && b.profit < 0) return a.profit - b.profit;
          return b.profit - a.profit;
        });
      } else {
        result.keyword_profit_movers = [];
      }
    } else {
      result.keyword_profit_movers = [];
    }

    // — SQP Terms: aggregate sqp_weekly by search_term (period-filtered) —
    const sqpMap: Record<string, { impressions: number; clicks: number; orders: number; cartAdds: number }> = {};
    sqp.forEach(r => {
      const key = r.search_term || '(unknown)';
      if (!sqpMap[key]) sqpMap[key] = { impressions: 0, clicks: 0, orders: 0, cartAdds: 0 };
      sqpMap[key].impressions += r.impressions || 0;
      sqpMap[key].clicks += r.clicks || 0;
      sqpMap[key].orders += r.orders || 0;
      sqpMap[key].cartAdds += r.cart_adds || 0;
    });
    result.sqp_terms = Object.entries(sqpMap)
      .map(([name, d]) => ({
        name,
        spend: 0,
        orders: d.orders,
        profit: d.orders, // use orders as the ranking metric for SQP
        roas: d.clicks > 0 ? (d.orders / d.clicks) * 100 : null, // CVR
        bucket: d.orders >= 1 ? 'winner' as const : d.impressions > 500 && d.orders === 0 ? 'loser' as const : 'other' as const,
      }))
      .sort((a, b) => b.orders - a.orders);

    // — Best Products: group trends_by_asin by product (period-filtered) —
    const isW = periodMode === 'weeks';
    const tba: TrendRowByAsin[] = isW
      ? (data.weekly_trends_by_asin || [])
      : (data.monthly_trends_by_asin || []);
    const productPeriodRows = tba.filter(r => {
      if (product && r.asin !== product) return false;
      if (family && famFromType(r.product_type) !== family) return false;
      if (!periodStart || !periodEnd) return false;
      const d = (isW ? r.week_start : r.month_start) || '';
      if (isW) return d === periodStart;
      if (periodMode === 'month') return d.slice(0, 7) === periodStart.slice(0, 7);
      return d >= periodStart && d <= periodEnd;
    });
    const prodMap: Record<string, { name: string; netProfit: number; units: number; spend: number; orders: number }> = {};
    productPeriodRows.forEach(r => {
      const key = r.asin || '(unknown)';
      if (!prodMap[key]) prodMap[key] = { name: r.product_short_name || key, netProfit: 0, units: 0, spend: 0, orders: 0 };
      prodMap[key].netProfit += r.net_profit || 0;
      prodMap[key].units += r.units ?? r.orders ?? 0;
      prodMap[key].spend += r.ad_cost || 0;
      prodMap[key].orders += r.orders || 0;
    });
    const prodEntries = Object.values(prodMap);
    result.best_product_profit = prodEntries
      .sort((a, b) => b.netProfit - a.netProfit)
      .slice(0, 10)
      .map(d => ({
        name: d.name,
        spend: d.spend,
        orders: d.orders,
        profit: d.netProfit,
        roas: null,
        bucket: d.netProfit >= 0 ? 'winner' as const : 'loser' as const,
      }));
    result.best_product_units = prodEntries
      .sort((a, b) => b.units - a.units)
      .slice(0, 10)
      .map(d => ({
        name: d.name,
        spend: d.spend,
        orders: d.orders,
        profit: d.units, // use units as primary value for display
        roas: null,
        bucket: d.units > 0 ? 'winner' as const : 'other' as const,
      }));

    // — Profit Movers: Period over Period net profit delta by product —
    // Use weekly data for date-range filtering (works for any period mode)
    // This ensures apples-to-apples comparison when current period is incomplete
    const weeklyTba = data.weekly_trends_by_asin || [];
    const moversMap: Record<string, { name: string; curProfit: number; prevProfit: number; spend: number; orders: number }> = {};

    weeklyTba.forEach(r => {
      if (family && famFromType(r.product_type) !== family) return;
      if (product && r.asin !== product) return;
      const d = r.week_start || '';
      if (!d) return;

      const key = r.asin || '(unknown)';
      if (!moversMap[key]) moversMap[key] = { name: r.product_short_name || key, curProfit: 0, prevProfit: 0, spend: 0, orders: 0 };

      // Current period: week_start within [periodStart, periodEnd]
      if (d >= periodStart && d <= periodEnd) {
        moversMap[key].curProfit += r.net_profit || 0;
        moversMap[key].spend += r.ad_cost || 0;
        moversMap[key].orders += r.orders || 0;
      }
      // Previous period: week_start within [prevPeriodStart, prevPeriodEnd]
      else if (prevPeriodStart && d >= prevPeriodStart && d <= prevPeriodEnd) {
        moversMap[key].prevProfit += r.net_profit || 0;
      }
    });

    result.profit_movers = Object.values(moversMap)
      .filter(d => d.curProfit !== 0 || d.prevProfit !== 0)
      .map(d => {
        const delta = d.curProfit - d.prevProfit;
        return {
          name: d.name,
          spend: d.spend,
          orders: d.orders,
          profit: delta,
          roas: null,
          bucket: delta >= 0 ? 'winner' as const : 'loser' as const,
        };
      })
      .sort((a, b) => b.profit - a.profit);

    // — Ads Strategy: aggregate coach_campaigns by strategy_name, cross-referenced with ads_7d —
    {
      // Build campaign_id → metrics from ads_7d, filtered by PERIOD + FAMILY only (not product).
      // Campaign-level rows (row_type='campaign') don't carry product_short_name,
      // so the global `ads7d` (which is product-filtered) excludes them. Use raw data instead.
      let stratAds = data.ads_7d || [];
      if (periodStart && periodEnd) {
        stratAds = stratAds.filter(r => {
          const d = r.date || r.week_start || '';
          return d >= periodStart && d <= periodEnd;
        });
      }
      if (family) stratAds = stratAds.filter(r => famFromType(r.parent_name ?? r.product_short_name ?? null) === family);

      // Fallback to ads_7d_summary (730 days) when ads_7d (180 days) has no campaign rows
      // for the period (e.g. Year view where early months exceed ads_7d's 180-day window)
      let stratCampRows = stratAds.filter(r => r.row_type === 'campaign');
      if (stratCampRows.length === 0 && data.ads_7d_summary && periodStart && periodEnd) {
        let summaryRows = (data.ads_7d_summary || []).filter(r => {
          const d = r.date || r.week_start || '';
          return d >= periodStart && d <= periodEnd;
        });
        if (family) summaryRows = summaryRows.filter(r => famFromType(r.parent_name ?? r.product_short_name ?? null) === family);
        stratCampRows = summaryRows.filter(r => r.row_type === 'campaign');
      }

      // When product is selected, use the globally product-filtered `ads7d` to identify
      // which campaign_ids are associated with that product. ads7d is already filtered
      // by period + product (the PPC card uses the same source and correctly finds campaigns).
      let productCampaignIds: Set<string> | null = null;
      if (product) {
        productCampaignIds = new Set(ads7d.map(r => r.campaign_id).filter(Boolean));
      }

      // Build campaign-level metrics, filtered to product-relevant campaigns when applicable
      const campAdsForStrategy = stratCampRows.filter(r => !productCampaignIds || productCampaignIds.has(r.campaign_id));
      const adsByCampaign: Record<string, { clicks: number; sales: number; spend: number; orders: number; gross_profit: number }> = {};
      campAdsForStrategy.forEach(r => {
        const cid = r.campaign_id;
        if (!adsByCampaign[cid]) adsByCampaign[cid] = { clicks: 0, sales: 0, spend: 0, orders: 0, gross_profit: 0 };
        adsByCampaign[cid].clicks += r.clicks || 0;
        adsByCampaign[cid].sales += r.sales || 0;
        adsByCampaign[cid].spend += r.spend || 0;
        adsByCampaign[cid].orders += r.orders || 0;
        adsByCampaign[cid].gross_profit += r.gross_profit || 0;
      });

      // Coach campaigns have strategy_name & campaign_id
      let cc = data.coach_campaigns || [];
      if (family) {
        // Include campaigns that match by name OR whose campaign_id appears in the
        // already-family-filtered ads data. This ensures "No Strategy" campaigns
        // (whose names don't contain family keywords) still appear when they have
        // ads data linked to products in the selected family.
        const familyCampaignIds = new Set(Object.keys(adsByCampaign));
        cc = cc.filter(c => {
          if (familyCampaignIds.has(c.campaign_id)) return true;
          const famStr = c.experiment_name || c.campaign_name || '';
          return experimentMatchesFamily(famStr, family as any);
        });
      }
      // When product is selected, only include campaigns associated with that product
      if (productCampaignIds) {
        cc = cc.filter(c => productCampaignIds!.has(c.campaign_id));
      }

      // Pre-populate with all unique strategy names from the FULL coach_campaigns dataset + "No Strategy"
      const emptyStrat = () => ({ campaigns: new Set<string>(), spend: 0, clicks: 0, sales: 0, netProfit: 0, campaignDetails: {} as Record<string, { name: string; spend: number; clicks: number; sales: number; netProfit: number }> });
      const stratMap: Record<string, ReturnType<typeof emptyStrat>> = {};
      // Collect all strategy names from the full (unfiltered) dataset so they always appear
      (data.coach_campaigns || []).forEach(c => {
        const sn = c.strategy_name || 'No Strategy';
        if (!stratMap[sn]) stratMap[sn] = emptyStrat();
      });
      stratMap['No Strategy'] = stratMap['No Strategy'] || emptyStrat();

      cc.forEach(c => {
        const sName = c.strategy_name || 'No Strategy';
        if (!stratMap[sName]) stratMap[sName] = emptyStrat();
        stratMap[sName].campaigns.add(c.campaign_id);
        // Initialize per-campaign detail
        if (!stratMap[sName].campaignDetails[c.campaign_id]) {
          stratMap[sName].campaignDetails[c.campaign_id] = { name: c.campaign_name || c.campaign_id, spend: 0, clicks: 0, sales: 0, netProfit: 0 };
        }
        const detail = stratMap[sName].campaignDetails[c.campaign_id];
        // Use ads_7d period data when available (date-filtered); fall back to coach 4w data
        const adsData = adsByCampaign[c.campaign_id];
        if (adsData) {
          stratMap[sName].spend += adsData.spend;
          stratMap[sName].clicks += adsData.clicks;
          stratMap[sName].sales += adsData.sales;
          stratMap[sName].netProfit += (adsData.gross_profit || 0) - adsData.spend;
          detail.spend += adsData.spend;
          detail.clicks += adsData.clicks;
          detail.sales += adsData.sales;
          detail.netProfit += (adsData.gross_profit || 0) - adsData.spend;
        } else {
          // Fallback to coach's 4w data
          stratMap[sName].spend += c.total_spend_4w || 0;
          stratMap[sName].netProfit += c.total_net_profit_4w || 0;
          detail.spend += c.total_spend_4w || 0;
          detail.netProfit += c.total_net_profit_4w || 0;
        }
      });

      result.ads_strategy = Object.entries(stratMap)
        .map(([name, d]) => ({
          name,
          spend: d.spend,
          orders: d.campaigns.size, // repurpose orders field for campaign count
          profit: d.netProfit,
          roas: d.spend > 0 ? (d.netProfit + d.spend) / d.spend : null,
          bucket: d.netProfit >= 0 ? 'winner' as const : 'loser' as const,
          count: d.clicks, // repurpose count field for clicks
          _sales: d.sales,
          children: Object.values(d.campaignDetails)
            .map(cd => ({
              name: cd.name,
              spend: cd.spend,
              orders: 0,
              profit: cd.netProfit,
              roas: cd.spend > 0 ? (cd.netProfit + cd.spend) / cd.spend : null,
              bucket: cd.netProfit >= 0 ? 'winner' as const : 'loser' as const,
              count: cd.clicks,
              _sales: cd.sales,
            }))
            .sort((a, b) => b.spend - a.spend),
        }))
        .sort((a, b) => b.spend - a.spend);
    }

    // — Campaign Launch: first-3-month performance per campaign —
    {
      let launchRows = data.campaign_launch_monthly || [];
      // Apply Parent/Product filter
      if (product) launchRows = launchRows.filter(r => r.asin === product);
      else if (family) launchRows = launchRows.filter(r => famFromType(r.parent_name) === family);
      // Only include campaigns with any spend, sorted by monthly avg net profit desc
      result.campaign_launch = launchRows
        .filter(r => r.m1_ad_spend > 0 || r.m2_ad_spend > 0 || r.m3_ad_spend > 0)
        .sort((a, b) => b.net_profit_monthly_avg - a.net_profit_monthly_avg)
        .map(r => ({
          name: r.campaign_name,
          spend: r.m1_ad_spend + r.m2_ad_spend + r.m3_ad_spend,
          orders: r.m1_units + r.m2_units + r.m3_units,
          profit: r.total_net_profit,
          roas: null,
          bucket: r.net_profit_monthly_avg >= 0 ? 'winner' as const : 'loser' as const,
          count: 0,
          _sales: r.net_profit_monthly_avg,
        }));
    }

    return result;
  }, [actions, ads7d, sqp, data.ads_7d_summary, data.products, data.weekly_trends_by_asin, data.monthly_trends_by_asin, data.ads_focus_terms, data.ads_focus_keywords, data.coach_campaigns, data.campaign_launch_perf, data.campaign_launch_monthly, periodMode, periodStart, periodEnd, prevPeriodStart, prevPeriodEnd, family, product, currentPeriod, prevPeriod]);

  // Filtered monthly launch rows for the CampaignLaunchTable
  const launchMonthlyFiltered = useMemo(() => {
    let rows = data.campaign_launch_monthly || [];
    if (product) rows = rows.filter(r => r.asin === product);
    else if (family) rows = rows.filter(r => famFromType(r.parent_name) === family);
    return rows
      .filter(r => r.m1_ad_spend > 0 || r.m2_ad_spend > 0 || r.m3_ad_spend > 0)
      .sort((a, b) => b.net_profit_monthly_avg - a.net_profit_monthly_avg);
  }, [data.campaign_launch_monthly, family, product]);

  return (
    <div className="space-y-3 mt-2">
      {/* Section header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <h2 className="text-[16px] font-bold tracking-tight" style={{ color: 'var(--color-text)' }}>
            Focus Cards
          </h2>
          <span className="text-[10px] font-mono px-1.5 py-0.5 rounded" style={{ color: 'var(--color-faint)', background: 'var(--color-inset)' }}>
            Winners · Losers · Other
          </span>
        </div>
      </div>

      {/* Pareto cards grid — Drag & Drop */}
      <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={onDragEnd}>
        <SortableContext items={paretoIds} strategy={rectSortingStrategy}>
          <div className="grid gap-4" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(340px, 1fr))' }}>
            {paretoIds.map(id => {
              const def = PARETO_CARDS.find(p => p.id === id)!;
              const items = paretoData[id] || [];
              const isCoachSnapshot = id === 'ads_targets';
              let pLabel = isCoachSnapshot
                ? (periodMode === 'weeks' ? 'Last 7d' : 'Last 4w')
                : (periodMode === 'weeks' ? weekRangeLabel(currentPeriod) : currentPeriod);
              if (def.category === 'Trend Cards') {
                // Show actual date ranges being compared (respects day-capping)
                const fmtShort = (d: string) => { const [, m, dd] = d.split('-'); return `${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][Number(m)-1]} ${Number(dd)}`; };
                if (periodStart && periodEnd && prevPeriodStart && prevPeriodEnd) {
                  pLabel = `${fmtShort(periodStart)}\u2013${fmtShort(periodEnd)} vs ${fmtShort(prevPeriodStart)}\u2013${fmtShort(prevPeriodEnd)}`;
                } else {
                  pLabel = `${pLabel} vs Prev`;
                }
              }
              const isProduct = id === 'best_product_profit' || id === 'best_product_units';
              return (
                <SortableParetoCard
                  key={id}
                  def={def}
                  items={items}
                  isSqp={id === 'sqp_terms'}
                  isProduct={isProduct}
                  isUnits={id === 'best_product_units'}
                  isCpcBuckets={id === 'ads_cpc_buckets'}
                  isStrategy={id === 'ads_strategy'}
                  isLaunch={id === 'campaign_launch'}
                  launchMonthlyRows={id === 'campaign_launch' ? launchMonthlyFiltered : undefined}
                  periodLabel={pLabel}
                  onRemove={() => removePareto(id)}
                  isCompact={cardSizes[id] === 'compact'}
                  onToggleSize={() => toggleSize(id)}
                />
              );
            })}
          </div>
        </SortableContext>
      </DndContext>

      {paretoIds.length === 0 && (
        <div className="text-center py-8 text-[13px]" style={{ color: 'var(--color-faint)' }}>
          Click <strong>Add Card</strong> to add focus dimensions.
        </div>
      )}
    </div>
  );
}

function classifyBucket(profit: number, spend: number): 'winner' | 'loser' | 'other' {
  if (profit > 0) return 'winner';
  if (spend > 0 && profit < 0) return 'loser';
  return 'other';
}

/* ── Strategy Hierarchy Table (Strategy → Campaign Name) ── */
/* ── Campaign Launch Table — monthly bucketed (M1/M2/M3) ── */
type LaunchMeasure = 'units' | 'cpc' | 'spend' | 'roas';
type LaunchSortKey = 'name' | 'created' | 'end' | 'avg_profit' | 'm1_units' | 'm1_cpc' | 'm1_spend' | 'm1_roas' | 'm2_units' | 'm2_cpc' | 'm2_spend' | 'm2_roas' | 'm3_units' | 'm3_cpc' | 'm3_spend' | 'm3_roas';
type LaunchMonthlyRow = import('../types').CampaignLaunchMonthlyRow;

function launchSortValue(r: LaunchMonthlyRow, key: LaunchSortKey): number | string {
  switch (key) {
    case 'name': return r.campaign_name.toLowerCase();
    case 'created': return r.creation_date;
    case 'end': return r.end_date_display ?? 'zzzz';
    case 'avg_profit': return r.net_profit_monthly_avg;
    case 'm1_units': return r.m1_units; case 'm1_cpc': return r.m1_cpc ?? 0; case 'm1_spend': return r.m1_ad_spend; case 'm1_roas': return r.m1_net_roas ?? 0;
    case 'm2_units': return r.m2_units; case 'm2_cpc': return r.m2_cpc ?? 0; case 'm2_spend': return r.m2_ad_spend; case 'm2_roas': return r.m2_net_roas ?? 0;
    case 'm3_units': return r.m3_units; case 'm3_cpc': return r.m3_cpc ?? 0; case 'm3_spend': return r.m3_ad_spend; case 'm3_roas': return r.m3_net_roas ?? 0;
    default: return 0;
  }
}

const LAUNCH_MEASURES: { id: LaunchMeasure; label: string; icon: string }[] = [
  { id: 'units', label: 'Units', icon: '📦' },
  { id: 'cpc', label: 'CPC', icon: '★' },
  { id: 'spend', label: 'Spend', icon: '💰' },
  { id: 'roas', label: 'ROAS', icon: '📈' },
];

function CampaignLaunchTable({ rows: allRows, color }: { rows: LaunchMonthlyRow[]; color: string }) {
  const [activeMeasures, setActiveMeasures] = useState<Set<LaunchMeasure>>(new Set(['cpc']));
  const [sortKey, setSortKey] = useState<LaunchSortKey>('avg_profit');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');

  // Filter to campaigns created >= 2025
  const rows = useMemo(() => allRows.filter(r => r.creation_date >= '2025-01-01'), [allRows]);

  const toggleMeasure = (m: LaunchMeasure) => {
    setActiveMeasures(prev => {
      const next = new Set(prev);
      if (next.has(m)) next.delete(m); else next.add(m);
      return next;
    });
  };

  const toggleSort = (key: LaunchSortKey) => {
    if (sortKey === key) setSortDir(d => d === 'asc' ? 'desc' : 'asc');
    else { setSortKey(key); setSortDir(key === 'name' || key === 'created' || key === 'end' ? 'asc' : 'desc'); }
  };

  const sorted = useMemo(() => {
    return [...rows].sort((a, b) => {
      const va = launchSortValue(a, sortKey);
      const vb = launchSortValue(b, sortKey);
      const cmp = typeof va === 'string' ? va.localeCompare(vb as string) : (va as number) - (vb as number);
      return sortDir === 'asc' ? cmp : -cmp;
    });
  }, [rows, sortKey, sortDir]);

  const arrow = (key: LaunchSortKey) => sortKey === key ? (sortDir === 'asc' ? ' ↑' : ' ↓') : '';
  const hdr = (label: string, key: LaunchSortKey, w: number, highlight?: boolean) => (
    <span
      className="text-[9px] font-mono font-bold uppercase text-right cursor-pointer select-none hover:opacity-80 transition-opacity whitespace-nowrap"
      style={{ color: highlight ? '#f59e0b' : 'var(--color-faint)', width: w, flexShrink: 0 }}
      onClick={() => toggleSort(key)}
    >{label}{arrow(key)}</span>
  );

  // Date formatter — yyyy-mm-dd
  const fDate = (d: string | null, isEnd?: boolean) => {
    if (!d && isEnd) return <span style={{ color: '#22c55e', fontWeight: 600 }}>Active</span>;
    if (!d) return '--';
    return d; // already in YYYY-MM-DD format
  };

  const fCpc = (v: number | null) => v != null ? `$${v.toFixed(2)}` : '--';
  const fRoas = (v: number | null) => v != null ? v.toFixed(2) + 'x' : '--';

  // Get value for a specific measure from a row for a specific month
  const getMVal = (r: LaunchMonthlyRow, m: 1 | 2 | 3, measure: LaunchMeasure) => {
    if (measure === 'units') return (m === 1 ? r.m1_units : m === 2 ? r.m2_units : r.m3_units).toLocaleString();
    if (measure === 'cpc') return fCpc(m === 1 ? r.m1_cpc : m === 2 ? r.m2_cpc : r.m3_cpc);
    if (measure === 'spend') return '$' + fmt(m === 1 ? r.m1_ad_spend : m === 2 ? r.m2_ad_spend : r.m3_ad_spend, 0);
    const roas = m === 1 ? r.m1_net_roas : m === 2 ? r.m2_net_roas : r.m3_net_roas;
    return fRoas(roas);
  };

  const getMColor = (r: LaunchMonthlyRow, m: 1 | 2 | 3, measure: LaunchMeasure) => {
    if (measure === 'units') return 'var(--color-text)';
    if (measure === 'cpc') return '#f59e0b';
    if (measure === 'spend') return 'var(--color-negative)';
    const roas = m === 1 ? r.m1_net_roas : m === 2 ? r.m2_net_roas : r.m3_net_roas;
    return roas != null && roas >= 1 ? 'var(--color-positive)' : 'var(--color-negative)';
  };

  const hasMeasures = activeMeasures.size > 0;

  return (
    <div className="px-3 py-2" style={{ overflowX: 'auto' }}>
      {/* Measure toggle chips */}
      <div className="flex items-center gap-1.5 mb-2">
        <span className="text-[9px] font-mono uppercase" style={{ color: 'var(--color-faint)' }}>Measures:</span>
        {LAUNCH_MEASURES.map(({ id, label, icon }) => {
          const active = activeMeasures.has(id);
          return (
            <button key={id} onClick={() => toggleMeasure(id)}
              className="text-[9px] font-mono font-bold px-2 py-0.5 rounded-full transition-all duration-200"
              style={{
                background: active ? (id === 'cpc' ? '#f59e0b' : color) : 'var(--color-inset)',
                color: active ? '#fff' : 'var(--color-faint)',
                border: `1px solid ${active ? (id === 'cpc' ? '#f59e0b' : color) : 'var(--color-border)'}`,
              }}
            >{icon} {label}</button>
          );
        })}
      </div>

      {/* Header */}
      <div className="flex items-center gap-1 pb-1.5 mb-0.5" style={{ borderBottom: '1px solid var(--color-border)', minWidth: 'fit-content' }}>
        <span className="text-[9px] font-mono font-bold uppercase cursor-pointer select-none hover:opacity-80" style={{ color: 'var(--color-faint)', flex: '1 1 0', minWidth: 140 }} onClick={() => toggleSort('name')}>Campaign{arrow('name')}</span>
        {hdr('Created', 'created', 72)}
        {hdr('End', 'end', 72)}
        {hdr('Avg $/mo', 'avg_profit', 60, true)}
        {/* For each active measure, show M1/M2/M3 headers */}
        {hasMeasures && Array.from(activeMeasures).map(measure => (
          <Fragment key={measure}>
            <span className="text-[8px] font-mono font-bold uppercase ml-1.5 px-1 py-0.5 rounded" style={{ color: measure === 'cpc' ? '#f59e0b' : color, background: measure === 'cpc' ? '#f59e0b15' : `${color}15`, flexShrink: 0 }}>
              {measure.toUpperCase()}
            </span>
            {hdr('M1', `m1_${measure}` as LaunchSortKey, 46, measure === 'cpc')}
            {hdr('M2', `m2_${measure}` as LaunchSortKey, 46, measure === 'cpc')}
            {hdr('M3', `m3_${measure}` as LaunchSortKey, 46, measure === 'cpc')}
          </Fragment>
        ))}
      </div>

      {/* Empty state */}
      {rows.length === 0 && (
        <div className="text-center py-4 text-[11px]" style={{ color: 'var(--color-faint)' }}>No launch data available (2025+)</div>
      )}

      {/* Rows */}
      {sorted.map((r) => {
        const maxSpend = Math.max(...rows.map(x => x.m1_ad_spend + x.m2_ad_spend + x.m3_ad_spend), 1);
        const totalSpend = r.m1_ad_spend + r.m2_ad_spend + r.m3_ad_spend;
        return (
          <div key={r.campaign_id} className="flex items-center gap-1 py-1 rounded-md px-1 hover:bg-white/[.03] transition-colors" style={{ position: 'relative', minWidth: 'fit-content' }}>
            <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: `${Math.max(1, (totalSpend / maxSpend) * 100)}%`, background: color, opacity: 0.05, borderRadius: '0.375rem' }} />
            {/* Campaign name + state badge */}
            <span className="text-[10px] font-semibold truncate" style={{ color: 'var(--color-text)', flex: '1 1 0', minWidth: 140, position: 'relative' }}>
              {r.campaign_name}
              {r.campaign_state !== 'ENABLED' && (
                <span className="text-[8px] font-mono ml-1 px-1 rounded" style={{
                  color: r.campaign_state === 'PAUSED' ? '#f59e0b' : '#ef4444',
                  background: r.campaign_state === 'PAUSED' ? '#f59e0b15' : '#ef444415',
                }}>{r.campaign_state === 'PAUSED' ? '⏸' : '⛔'}</span>
              )}
            </span>
            {/* Created — with year */}
            <span className="text-[10px] font-mono text-right" style={{ color: 'var(--color-muted)', width: 72, flexShrink: 0, position: 'relative' }}>
              {fDate(r.creation_date)}
            </span>
            {/* End — with year */}
            <span className="text-[10px] font-mono text-right" style={{ width: 72, flexShrink: 0, position: 'relative' }}>
              {fDate(r.end_date_display, true)}
            </span>
            {/* Avg Net Profit/mo */}
            <span className="text-[10px] font-mono text-right font-bold" style={{
              color: r.net_profit_monthly_avg >= 0 ? 'var(--color-positive)' : 'var(--color-negative)',
              width: 60, flexShrink: 0, position: 'relative',
            }}>
              {r.net_profit_monthly_avg >= 0 ? '+' : ''}{fShort(r.net_profit_monthly_avg)}
            </span>
            {/* Measure × month columns */}
            {hasMeasures && Array.from(activeMeasures).map(measure => (
              <Fragment key={measure}>
                <span style={{ width: 28, flexShrink: 0 }} />
                {([1, 2, 3] as const).map(m => (
                  <span key={m} className="text-[10px] font-mono text-right" style={{
                    color: getMColor(r, m, measure),
                    width: 46, flexShrink: 0,
                    fontWeight: measure === 'cpc' ? 600 : 400,
                  }}>{getMVal(r, m, measure)}</span>
                ))}
              </Fragment>
            ))}
          </div>
        );
      })}
    </div>
  );
}

function StrategyHierarchyTable({ items, def }: { items: ParetoItem[]; def: ParetoCardDef }) {
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const toggle = (name: string) => setExpanded(prev => ({ ...prev, [name]: !prev[name] }));
  const maxSpend = Math.max(...items.map(i => i.spend), 1);

  return (
    <div className="px-4 py-2">
      {/* Header */}
      <div className="flex items-center gap-2 pb-2 mb-1" style={{ borderBottom: '1px solid var(--color-border)' }}>
        <span className="text-[10px] font-mono font-bold uppercase" style={{ color: 'var(--color-faint)', flex: '1 1 0', paddingLeft: 20 }}>Strategy</span>
        <span className="text-[10px] font-mono font-bold uppercase text-right" style={{ color: 'var(--color-faint)', width: 45 }}># Camps</span>
        <span className="text-[10px] font-mono font-bold uppercase text-right" style={{ color: 'var(--color-faint)', width: 60 }}>Ad Spend</span>
        <span className="text-[10px] font-mono font-bold uppercase text-right" style={{ color: 'var(--color-faint)', width: 50 }}>Clicks</span>
        <span className="text-[10px] font-mono font-bold uppercase text-right" style={{ color: 'var(--color-faint)', width: 55 }}>Sales</span>
        <span className="text-[10px] font-mono font-bold uppercase text-right" style={{ color: 'var(--color-faint)', width: 52 }}>Net ROAS</span>
        <span className="text-[10px] font-mono font-bold uppercase text-right" style={{ color: 'var(--color-faint)', width: 60 }}>Net Profit</span>
      </div>
      {items.length === 0 && (
        <div className="text-center py-4 text-[11px]" style={{ color: 'var(--color-faint)' }}>No strategy data available</div>
      )}
      {items.map((item, i) => {
        const netRoas = item.roas;
        const clicks = item.count ?? 0;
        const campaigns = item.orders;
        const sales = item._sales ?? 0;
        const isExpanded = expanded[item.name] ?? false;
        const hasChildren = (item.children?.length ?? 0) > 0;
        return (
          <div key={item.name + i}>
            {/* Strategy row */}
            <div
              className="flex items-center gap-2 py-1.5 rounded-lg px-1 hover:bg-white/[.02]"
              style={{ position: 'relative', cursor: hasChildren ? 'pointer' : 'default' }}
              onClick={() => hasChildren && toggle(item.name)}
            >
              {/* Background spend bar */}
              <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: `${Math.max(2, (item.spend / maxSpend) * 100)}%`, background: def.color, opacity: 0.07, borderRadius: '0.5rem' }} />
              <span className="flex items-center gap-1 text-[11px] font-semibold truncate" style={{ color: 'var(--color-text)', flex: '1 1 0', position: 'relative' }}>
                {hasChildren ? (
                  <span className="shrink-0 transition-transform duration-150" style={{ display: 'inline-flex', transform: isExpanded ? 'rotate(0deg)' : 'rotate(0deg)' }}>
                    {isExpanded ? <ChevronDown size={13} style={{ color: 'var(--color-faint)' }} /> : <ChevronRight size={13} style={{ color: 'var(--color-faint)' }} />}
                  </span>
                ) : (
                  <span style={{ width: 13, display: 'inline-block' }} />
                )}
                <span className="truncate">{item.name}</span>
              </span>
              <span className="text-[10px] font-mono text-right font-semibold" style={{ color: 'var(--color-text)', width: 45, position: 'relative' }}>
                {campaigns}
              </span>
              <span className="text-[10px] font-mono text-right font-semibold" style={{ color: 'var(--color-text)', width: 60, position: 'relative' }}>
                {fM(item.spend)}
              </span>
              <span className="text-[10px] font-mono text-right font-semibold" style={{ color: 'var(--color-text)', width: 50, position: 'relative' }}>
                {clicks > 0 ? clicks.toLocaleString() : '--'}
              </span>
              <span className="text-[10px] font-mono text-right font-semibold" style={{ color: 'var(--color-text)', width: 55, position: 'relative' }}>
                {sales > 0 ? fM(sales) : '--'}
              </span>
              <span className="text-[10px] font-mono text-right font-semibold" style={{ color: netRoas != null && netRoas >= 1 ? 'var(--color-positive)' : 'var(--color-negative)', width: 52, position: 'relative' }}>
                {netRoas != null ? `${netRoas.toFixed(2)}x` : '--'}
              </span>
              <span className="text-[10px] font-mono text-right font-semibold" style={{ color: item.profit >= 0 ? 'var(--color-positive)' : 'var(--color-negative)', width: 60, position: 'relative' }}>
                {item.profit >= 0 ? '+' : '-'}${fShort(Math.abs(item.profit))}
              </span>
            </div>
            {/* Expanded campaign rows */}
            {isExpanded && item.children && item.children.map((child, ci) => {
              const cClicks = child.count ?? 0;
              const cSales = child._sales ?? 0;
              const cRoas = child.roas;
              return (
                <div key={child.name + ci} className="flex items-center gap-2 py-1 rounded-lg px-1 hover:bg-white/[.02]" style={{ position: 'relative' }}>
                  <span className="text-[10px] truncate" style={{ color: 'var(--color-muted)', flex: '1 1 0', position: 'relative', paddingLeft: 24 }}>
                    {child.name}
                  </span>
                  <span className="text-[10px] font-mono text-right" style={{ color: 'var(--color-faint)', width: 45, position: 'relative' }}>
                  </span>
                  <span className="text-[10px] font-mono text-right" style={{ color: 'var(--color-muted)', width: 60, position: 'relative' }}>
                    {fM(child.spend)}
                  </span>
                  <span className="text-[10px] font-mono text-right" style={{ color: 'var(--color-muted)', width: 50, position: 'relative' }}>
                    {cClicks > 0 ? cClicks.toLocaleString() : '--'}
                  </span>
                  <span className="text-[10px] font-mono text-right" style={{ color: 'var(--color-muted)', width: 55, position: 'relative' }}>
                    {cSales > 0 ? fM(cSales) : '--'}
                  </span>
                  <span className="text-[10px] font-mono text-right" style={{ color: cRoas != null && cRoas >= 1 ? 'var(--color-positive)' : 'var(--color-negative)', width: 52, position: 'relative' }}>
                    {cRoas != null ? `${cRoas.toFixed(2)}x` : '--'}
                  </span>
                  <span className="text-[10px] font-mono text-right" style={{ color: child.profit >= 0 ? 'var(--color-positive)' : 'var(--color-negative)', width: 60, position: 'relative' }}>
                    {child.profit >= 0 ? '+' : '-'}${fShort(Math.abs(child.profit))}
                  </span>
                </div>
              );
            })}
          </div>
        );
      })}
      {/* Totals row */}
      {items.length > 0 && (() => {
        const tCamps = items.reduce((s, i) => s + i.orders, 0);
        const tSpend = items.reduce((s, i) => s + i.spend, 0);
        const tClicks = items.reduce((s, i) => s + (i.count ?? 0), 0);
        const tSales = items.reduce((s, i) => s + (i._sales ?? 0), 0);
        const tProfit = items.reduce((s, i) => s + i.profit, 0);
        const tRoas = tSpend > 0 ? (tProfit + tSpend) / tSpend : null;
        return (
          <div className="flex items-center gap-2 pt-2 mt-1 px-1" style={{ borderTop: '1px solid var(--color-border)' }}>
            <span className="text-[10px] font-mono font-bold uppercase" style={{ color: 'var(--color-faint)', flex: '1 1 0', paddingLeft: 20 }}>Total</span>
            <span className="text-[10px] font-mono text-right font-bold" style={{ color: 'var(--color-text)', width: 45 }}>{tCamps}</span>
            <span className="text-[10px] font-mono text-right font-bold" style={{ color: 'var(--color-text)', width: 60 }}>{fM(tSpend)}</span>
            <span className="text-[10px] font-mono text-right font-bold" style={{ color: 'var(--color-text)', width: 50 }}>{tClicks > 0 ? tClicks.toLocaleString() : '--'}</span>
            <span className="text-[10px] font-mono text-right font-bold" style={{ color: 'var(--color-text)', width: 55 }}>{tSales > 0 ? fM(tSales) : '--'}</span>
            <span className="text-[10px] font-mono text-right font-bold" style={{ color: tRoas != null && tRoas >= 1 ? 'var(--color-positive)' : 'var(--color-negative)', width: 52 }}>{tRoas != null ? `${tRoas.toFixed(2)}x` : '--'}</span>
            <span className="text-[10px] font-mono text-right font-bold" style={{ color: tProfit >= 0 ? 'var(--color-positive)' : 'var(--color-negative)', width: 60 }}>{tProfit >= 0 ? '+' : '-'}${fShort(Math.abs(tProfit))}</span>
          </div>
        );
      })()}
    </div>
  );
}

const TOP_N = 10;

function SortableParetoCard({ def, items, isSqp, isProduct, isUnits, isCpcBuckets, isStrategy, isLaunch, launchMonthlyRows, periodLabel, onRemove, isCompact, onToggleSize }: {
  def: ParetoCardDef;
  items: ParetoItem[];
  isSqp: boolean;
  isProduct?: boolean;
  isUnits?: boolean;
  isCpcBuckets?: boolean;
  isStrategy?: boolean;
  isLaunch?: boolean;
  launchMonthlyRows?: import('../types').CampaignLaunchMonthlyRow[];
  periodLabel: string;
  onRemove: () => void;
  isCompact: boolean;
  onToggleSize: () => void;
}) {
  const measureLabel = isLaunch ? 'Created · End · Avg Profit · M1 · M2 · M3' : isStrategy ? '# Camps · Spend · Clicks · Sales · ROAS · Profit' : isCpcBuckets ? 'Units · Spend · Profit · ROAS' : isSqp ? 'Orders' : isUnits ? 'Units' : 'Net Profit';
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: def.id });
  const style = { transform: CSS.Transform.toString(transform), transition, opacity: isDragging ? 0.5 : 1, zIndex: isDragging ? 50 : 'auto' as const, ...(isStrategy ? { gridColumn: '1 / -1' as const } : {}), ...(isLaunch ? { gridColumn: '1 / -1' as const } : {}) };
  const [tab, setTab] = useState<'winner' | 'loser' | 'other_winners' | 'other_losers'>('winner');
  const [showAll, setShowAll] = useState(false);
  const displayLimit = showAll ? 10 : 5;

  const isPreAggregated = useMemo(() => items.some(i => i.name.startsWith('__OTHER__')), [items]);

  // Rank-based: Winners, Losers, Other Winners, Other Losers
  // Note: we calculate the tops based on the full TOP_10 in backend but only display `displayLimit` in UI.
  // Actually, we can slice by displayLimit.
  const allWinners = useMemo(() => isPreAggregated ? items.filter(i => i.bucket === 'winner') : [...items].sort((a, b) => b.profit - a.profit).filter(i => i.profit > 0), [items, isPreAggregated]);
  const allLosers = useMemo(() => isPreAggregated ? items.filter(i => i.bucket === 'loser') : [...items].sort((a, b) => a.profit - b.profit).filter(i => i.profit <= 0), [items, isPreAggregated]);
  const topWinners = useMemo(() => allWinners.slice(0, displayLimit), [allWinners, displayLimit]);
  const bottomLosers = useMemo(() => allLosers.slice(0, displayLimit), [allLosers, displayLimit]);
  
  const otherWinners = useMemo(() => {
    if (isPreAggregated) return items.filter(i => i.bucket === 'other_winners');
    const topSet = new Set(topWinners.map(i => i.name));
    return items.filter(i => i.profit > 0 && !topSet.has(i.name));
  }, [items, isPreAggregated, topWinners]);
  
  const otherLosers = useMemo(() => {
    if (isPreAggregated) return items.filter(i => i.bucket === 'other_losers');
    const botSet = new Set(bottomLosers.map(i => i.name));
    return items.filter(i => i.profit <= 0 && !botSet.has(i.name));
  }, [items, isPreAggregated, bottomLosers]);

  useEffect(() => {
    if (tab === 'loser' && bottomLosers.length === 0) setTab('winner');
    if (tab === 'other_losers' && otherLosers.length === 0) setTab('winner');
    if (tab === 'other_winners' && otherWinners.length === 0) setTab('winner');
  }, [tab, bottomLosers.length, otherLosers.length, otherWinners.length]);

  const displayItems = tab === 'winner' ? topWinners : tab === 'loser' ? bottomLosers : tab === 'other_winners' ? otherWinners.slice(0, displayLimit) : otherLosers.slice(0, displayLimit);
  const winnerProfit = topWinners.reduce((s, i) => s + i.profit, 0);
  const loserProfit = bottomLosers.reduce((s, i) => s + i.profit, 0);
  const otherWinnersProfit = otherWinners.reduce((s, i) => s + i.profit, 0);
  const otherLosersProfit = otherLosers.reduce((s, i) => s + i.profit, 0);

  return (
    <div ref={setNodeRef} style={{ ...style, background: 'var(--color-card)', border: '1px solid var(--color-border)', boxShadow: 'var(--shadow-card)' }}
      className="group rounded-xl overflow-hidden transition-all duration-200">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3" style={{ borderBottom: isCompact ? 'none' : '1px solid var(--color-border)' }}>
        <div className="flex items-center gap-2">
          <button {...attributes} {...listeners} className="opacity-0 group-hover:opacity-40 hover:!opacity-80 transition-opacity cursor-grab active:cursor-grabbing" style={{ color: 'var(--color-faint)' }} title="Drag to reorder">
            <GripVertical size={12} />
          </button>
          <span className="text-[16px]">{def.icon}</span>
          <div>
            <span className="text-[13px] font-bold" style={{ color: 'var(--color-text)' }}>{def.label}</span>
            <span className="text-[10px] font-mono ml-2" style={{ color: 'var(--color-faint)' }}>{items.length} total</span>
            <span className="text-[9px] font-mono ml-1.5 px-1.5 py-0.5 rounded" style={{ color: 'var(--color-faint)', background: 'var(--color-inset)' }}>{periodLabel}</span>
            <span className="text-[9px] font-mono ml-1.5 px-1.5 py-0.5 rounded" style={{ color: def.color, background: 'var(--color-inset)' }}>{measureLabel}</span>
          </div>
        </div>
        <div className="flex items-center gap-2 opacity-0 group-hover:opacity-60 hover:!opacity-100 transition-opacity">
          <button onClick={onToggleSize} className="p-2 -m-2" style={{ color: 'var(--color-faint)' }} title={isCompact ? 'Expand' : 'Compact'}>
            {isCompact ? <Maximize2 size={12} /> : <Minimize2 size={12} />}
          </button>
          <button onClick={onRemove} className="p-2 -m-2" style={{ color: 'var(--color-faint)' }}><X size={14} /></button>
        </div>
      </div>



      {/* Product focus: simple ranked list */}
      {isProduct && !isCompact && (() => {
        const maxVal = Math.max(...items.map(i => Math.abs(i.profit)), 1);
        return (
          <div className="px-4 py-2 space-y-1">
            {items.length === 0 && (
              <div className="text-center py-4 text-[11px]" style={{ color: 'var(--color-faint)' }}>No data available</div>
            )}
            {items.slice(0, displayLimit).map((item, i) => (
              <div key={item.name + i} className="flex items-center gap-2 py-1 rounded-lg px-2 hover:bg-white/[.02]">
                <span className="text-[10px] font-mono w-4 shrink-0 font-bold" style={{ color: def.color }}>{item.name.startsWith('__OTHER__') ? '*' : i + 1}</span>
                <span className="text-[11px] truncate font-medium" style={{ color: 'var(--color-text)', flex: '0 1 40%' }}>
                  {item.name === '__OTHER__other_losers' ? 'Other Losers' : item.name === '__OTHER__other_winners' ? 'Other Winners' : item.name.startsWith('__OTHER__') ? 'Other' : item.name}
                </span>
                <div className="flex-1 h-[6px] rounded-full overflow-hidden" style={{ background: 'var(--color-inset)' }}>
                  <div className="h-full rounded-full transition-all" style={{ width: `${Math.max(2, (Math.abs(item.profit) / maxVal) * 100)}%`, background: item.profit >= 0 ? def.color : 'var(--color-negative)' }} />
                </div>
                <span className="text-[10px] font-mono shrink-0 font-semibold" style={{ color: item.profit >= 0 ? 'var(--color-positive)' : 'var(--color-negative)' }}>
                  {isUnits ? `${item.profit.toLocaleString()} units` : `${item.profit >= 0 ? '+' : '-'}$${fShort(Math.abs(item.profit))}`}
                </span>
              </div>
            ))}
            {items.length > 5 && (
              <div className="pt-2 pb-1 flex justify-center">
                <button onClick={() => setShowAll(!showAll)} className="text-[10px] font-semibold px-3 py-1 rounded-md transition-colors hover:bg-white/[.06]" style={{ color: 'var(--color-text)', background: 'var(--color-inset)', border: '1px solid var(--color-border)' }}>
                  {showAll ? '▲ Show less' : '▼ Show more'}
                </button>
              </div>
            )}
          </div>
        );
      })()}

      {/* CPC Buckets: table-style rows per CPC range */}
      {isCpcBuckets && !isCompact && (() => {
        const maxSpend = Math.max(...items.map(i => i.spend), 1);
        return (
          <div className="px-4 py-2">
            {/* Header */}
            <div className="flex items-center gap-2 pb-2 mb-1" style={{ borderBottom: '1px solid var(--color-border)' }}>
              <span className="text-[10px] font-mono font-bold uppercase" style={{ color: 'var(--color-faint)', flex: '0 0 24%' }}>CPC Range</span>
              <span className="text-[10px] font-mono font-bold uppercase text-right" style={{ color: 'var(--color-faint)', flex: '0 0 14%' }}>Units</span>
              <span className="text-[10px] font-mono font-bold uppercase text-right" style={{ color: 'var(--color-faint)', flex: '0 0 18%' }}>Spend</span>
              <span className="text-[10px] font-mono font-bold uppercase text-right" style={{ color: 'var(--color-faint)', flex: '0 0 18%' }}>Net Profit</span>
              <span className="text-[10px] font-mono font-bold uppercase text-right" style={{ color: 'var(--color-faint)', flex: '0 0 16%' }}>Net ROAS</span>
            </div>
            {items.length === 0 && (
              <div className="text-center py-4 text-[11px]" style={{ color: 'var(--color-faint)' }}>No data available</div>
            )}
            {items.map((item, i) => {
              const netRoas = item.spend > 0 ? (item.profit + item.spend) / item.spend : null;
              return (
              <div key={item.name + i} className="flex items-center gap-2 py-1.5 rounded-lg px-1 hover:bg-white/[.02]" style={{ position: 'relative' }}>
                {/* Background spend bar */}
                <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: `${Math.max(2, (item.spend / maxSpend) * 100)}%`, background: def.color, opacity: 0.07, borderRadius: '0.5rem' }} />
                <span className="text-[11px] font-semibold" style={{ color: 'var(--color-text)', flex: '0 0 24%', position: 'relative' }}>
                  {item.name}
                </span>
                <span className="text-[10px] font-mono text-right font-semibold" style={{ color: 'var(--color-text)', flex: '0 0 14%', position: 'relative' }}>
                  {item.orders.toLocaleString()}
                </span>
                <span className="text-[10px] font-mono text-right font-semibold" style={{ color: 'var(--color-negative)', flex: '0 0 18%', position: 'relative' }}>
                  ${fShort(item.spend)}
                </span>
                <span className="text-[10px] font-mono text-right font-semibold" style={{ color: item.profit >= 0 ? 'var(--color-positive)' : 'var(--color-negative)', flex: '0 0 18%', position: 'relative' }}>
                  {item.profit >= 0 ? '+' : '-'}${fShort(Math.abs(item.profit))}
                </span>
                <span className="text-[10px] font-mono text-right font-semibold" style={{ color: netRoas != null && netRoas >= 1 ? 'var(--color-positive)' : 'var(--color-negative)', flex: '0 0 16%', position: 'relative' }}>
                  {netRoas != null ? `${netRoas.toFixed(2)}x` : '--'}
                </span>
              </div>
              );
            })}
            {/* Totals row */}
            {items.length > 0 && (() => {
              const tUnits = items.reduce((s, i) => s + i.orders, 0);
              const tSpend = items.reduce((s, i) => s + i.spend, 0);
              const tProfit = items.reduce((s, i) => s + i.profit, 0);
              const tRoas = tSpend > 0 ? (tProfit + tSpend) / tSpend : null;
              return (
                <div className="flex items-center gap-2 pt-2 mt-1 px-1" style={{ borderTop: '1px solid var(--color-border)' }}>
                  <span className="text-[10px] font-mono font-bold uppercase" style={{ color: 'var(--color-faint)', flex: '0 0 24%' }}>Total</span>
                  <span className="text-[10px] font-mono text-right font-bold" style={{ color: 'var(--color-text)', flex: '0 0 14%' }}>{tUnits.toLocaleString()}</span>
                  <span className="text-[10px] font-mono text-right font-bold" style={{ color: 'var(--color-negative)', flex: '0 0 18%' }}>${fShort(tSpend)}</span>
                  <span className="text-[10px] font-mono text-right font-bold" style={{ color: tProfit >= 0 ? 'var(--color-positive)' : 'var(--color-negative)', flex: '0 0 18%' }}>{tProfit >= 0 ? '+' : '-'}${fShort(Math.abs(tProfit))}</span>
                  <span className="text-[10px] font-mono text-right font-bold" style={{ color: tRoas != null && tRoas >= 1 ? 'var(--color-positive)' : 'var(--color-negative)', flex: '0 0 16%' }}>{tRoas != null ? `${tRoas.toFixed(2)}x` : '--'}</span>
                </div>
              );
            })()}
          </div>
        );
      })()}

      {/* Ad Strategy table — hierarchical: Strategy → Campaign Name */}
      {isStrategy && !isCompact && <StrategyHierarchyTable items={items} def={def} />}

      {/* Campaign Launch table — monthly bucketed performance */}
      {isLaunch && !isCompact && <CampaignLaunchTable rows={launchMonthlyRows || []} color={def.color} />}

      {/* Tabs + Items — hidden in compact mode, hidden for product/CPC-bucket cards */}
      {!isCompact && !isProduct && !isCpcBuckets && !isStrategy && !isLaunch && (
        <>
          <div className="flex px-4 pt-2 gap-1 overflow-x-auto no-scrollbar">
            {(['winner', 'loser', 'other_winners', 'other_losers'] as const)
              .filter(t => {
                if (t === 'winner') return true; // Always show winner
                if (t === 'loser') return bottomLosers.length > 0;
                if (t === 'other_winners') return isPreAggregated && otherWinners.length > 0;
                if (t === 'other_losers') return isPreAggregated && otherLosers.length > 0;
                return false;
              })
              .map(t => {
              const tabList = t === 'winner' ? topWinners : t === 'loser' ? bottomLosers : t === 'other_winners' ? otherWinners : otherLosers;
              const totalProfit = t === 'winner' ? winnerProfit : t === 'loser' ? loserProfit : t === 'other_winners' ? otherWinnersProfit : otherLosersProfit;
              
              let activeColor = 'var(--color-muted)';
              let bgColor = 'var(--color-inset)';
              if (t === 'winner' || t === 'other_winners') {
                activeColor = '#22c55e';
                bgColor = 'rgba(34,197,94,0.1)';
              } else if (t === 'loser' || t === 'other_losers') {
                activeColor = '#ef4444';
                bgColor = 'rgba(239,68,68,0.1)';
              }

              const valLabel = isSqp
                ? `${tabList.reduce((s, i) => s + i.orders, 0)} ord`
                : `${totalProfit >= 0 ? '+' : ''}$${fShort(totalProfit)}`;
                
              let tabLabel = '';
              if (t === 'winner') tabLabel = `Top ${topWinners.length} Winners`;
              else if (t === 'loser') tabLabel = `Top ${bottomLosers.length} Losers`;
              else if (t === 'other_winners') tabLabel = isPreAggregated ? 'Other Winners' : `Other Winners (${otherWinners.length})`;
              else if (t === 'other_losers') tabLabel = isPreAggregated ? 'Other Losers' : `Other Losers (${otherLosers.length})`;
              return (
                <button key={t} onClick={() => setTab(t)} className="px-2.5 py-1 rounded-lg text-[10px] font-semibold transition-all whitespace-nowrap"
                  style={{ background: tab === t ? bgColor : 'transparent', color: tab === t ? activeColor : 'var(--color-faint)' }}>
                  {tabLabel} <span className="font-mono ml-0.5 opacity-80">({valLabel})</span>
                </button>
              );
            })}
          </div>
          <div className="px-4 py-2 space-y-0.5">
            {displayItems.length === 0 && (
              <div className="text-center py-4 text-[11px]" style={{ color: 'var(--color-faint)' }}>No {tab.replace('_', ' ')} found</div>
            )}
            {displayItems.map((item, i) => (
              <div key={item.name + i} className="flex items-center gap-2 py-1.5 rounded-lg px-2 hover:bg-white/[.02]">
                <span className="text-[10px] font-mono w-4 shrink-0" style={{ color: 'var(--color-faint)' }}>{i + 1}</span>
                <span className="text-[11px] truncate flex-1 font-medium" style={{ color: 'var(--color-text)' }}>
                  {item.name === '__OTHER__other_losers' ? 'Other Losers' : item.name === '__OTHER__other_winners' ? 'Other Winners' : item.name === '__OTHER__' ? `Other ${tab.includes('winner') ? 'Winners' : 'Losers'} (${item.count || 0})` : item.name}
                </span>
                {!isSqp ? (
                  <>
                    <span className="text-[10px] font-mono shrink-0" style={{ color: item.profit >= 0 ? 'var(--color-positive)' : 'var(--color-negative)' }}>{item.profit >= 0 ? '+' : ''}${fShort(item.profit)}</span>
                    <span className="text-[10px] font-mono shrink-0" style={{ color: 'var(--color-faint)' }}>${fShort(item.spend)} spend</span>
                    <span className="text-[10px] font-mono shrink-0" style={{ color: 'var(--color-faint)' }}>{item.orders} ord</span>
                  </>
                ) : (
                  <>
                    <span className="text-[10px] font-mono shrink-0" style={{ color: 'var(--color-text)' }}>{item.orders} ord</span>
                    {item.roas != null && <span className="text-[10px] font-mono shrink-0" style={{ color: 'var(--color-faint)' }}>{item.roas.toFixed(1)}% CVR</span>}
                  </>
                )}
              </div>
            ))}
            {(tab === 'winner' ? allWinners.length : tab === 'loser' ? allLosers.length : tab === 'other_winners' ? otherWinners.length : otherLosers.length) > 5 && (
              <div className="pt-2 pb-1 flex justify-center">
                <button onClick={() => setShowAll(!showAll)} className="text-[10px] font-semibold px-3 py-1 rounded-md transition-colors hover:bg-white/[.06]" style={{ color: 'var(--color-text)', background: 'var(--color-inset)', border: '1px solid var(--color-border)' }}>
                  {showAll ? '▲ Show less' : '▼ Show more'}
                </button>
              </div>
            )}
          </div>
          {(tab === 'other_winners' && otherWinners.length > displayLimit) && (
            <div className="px-4 pb-2"><span className="text-[9px] font-mono" style={{ color: 'var(--color-faint)' }}>Showing top {displayLimit} of {otherWinners.length}</span></div>
          )}
          {(tab === 'other_losers' && otherLosers.length > displayLimit) && (
            <div className="px-4 pb-2"><span className="text-[9px] font-mono" style={{ color: 'var(--color-faint)' }}>Showing top {displayLimit} of {otherLosers.length}</span></div>
          )}
        </>
      )}
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════════════
   Measures Section — P&L per Unit, Daily Averages, Stock
   ═══════════════════════════════════════════════════════════════════ */

function MeasuresSection({ data, family, product, currentPeriod, periodMode, periodType, measureIds }: {
  data: DashboardData; family: string | null; product: string | null; currentPeriod: string; periodMode: string; periodType: string; measureIds: MeasureCardId[];
}) {
  const measures = useMemo(() => {
    const filterForPeriod = (rDate: string, targetDate: string) => {
      if (!rDate || !targetDate) return false;
      if (periodType !== 'cumulative') return rDate === targetDate;
      return rDate.slice(0, 4) === targetDate.slice(0, 4) && rDate <= targetDate;
    };

    // Filter products by family + product (use family_name for correct family matching)
    let prods = data.products || [];
    if (product) prods = prods.filter(p => p.asin === product);
    else if (family) prods = prods.filter(p => p.family_name === family);

    // Filter supply chain by ASIN-based lookup (same pattern as HomePage)
    const famAsins = new Set(prods.map(p => p.asin).filter(Boolean));
    let supply = data.supply_chain || [];
    if (product) supply = supply.filter(s => s.asin === product);
    else if (family) supply = supply.filter(s => famAsins.has(s.asin));

    // Trend data — use by-asin when product selected
    const isW = periodMode === 'weeks';
    let trends: TrendRow[];
    if (product) {
      trends = isW
        ? (data.weekly_trends_by_asin || []).filter((r: TrendRow & { asin?: string }) => r.asin === product)
        : (data.monthly_trends_by_asin || []).filter((r: TrendRow & { asin?: string }) => r.asin === product);
    } else {
      trends = isW ? (data.weekly_trends || []) : (data.monthly_trends || []);
    }

    const periodRows = trends.filter(r => {
      if (!product && family && famFromType(r.product_type) !== family) return false;
      if (!currentPeriod) return false;
      let rDate = '';
      if (isW) rDate = r.week_start || '';
      else if (periodMode === 'month') rDate = (r.month_start || '').slice(0, 7);
      else if (periodMode === 'quarter') { const ms = r.month_start || ''; const m = parseInt(ms.slice(5, 7), 10); rDate = `${ms.slice(0, 4)}-Q${Math.ceil(m / 3)}`; }
      else rDate = (r.month_start || '').slice(0, 4);
      return filterForPeriod(rDate, currentPeriod);
    });

    let tS = 0, tO = 0, tU = 0, tA = 0, tC = 0, tN = 0;
    periodRows.forEach(r => { tS += r.sales || 0; tO += r.orders || 0; tU += r.units ?? r.orders ?? 0; tA += r.ad_cost || 0; tC += r.cogs || 0; tN += r.net_profit || 0; });

    // Per-unit P&L from product dimension
    const n = prods.length || 1;
    const avg = (f: (p: ProductRow) => number) => prods.reduce((s, p) => s + f(p), 0) / n;
    const wCogs = avg(p => p.cogs || 0), wShip = avg(p => p.shipping_cost || 0), wPP = avg(p => p.pick_pack_fee || 0), wRef = avg(p => p.referral_fee || 0), wFba = avg(p => p.fba_cost || 0);
    const wSP = tU > 0 ? tS / tU : 0;

    // Storage — filter by family/product AND by current period
    let sc = data.storage_costs || [];
    if (product) {
      sc = sc.filter(s => s.asin === product);
    } else if (family) {
      const familyAsins = new Set(prods.filter(p => {
        const knownFamilies: Record<string, string> = {
          'Truth Or Dare': 'Bottle', 'Fresh in Blue': 'Fresh', 'Fresh in Purple': 'Fresh', 'Fresh in Beige': 'Fresh', 'Fresh in Pink': 'Fresh',
          'Blue Lollibox': 'Lollibox', 'White Lollibox': 'Lollibox', 'Pink Lollibox': 'Lollibox', 'Purple Lollibox': 'Lollibox',
          'Pink LolliME': 'LolliME', 'Purple LolliME': 'LolliME', 'Mint LolliME': 'LolliME',
          'Love Bunny': 'Bunny', 'Awesome Bunny': 'Bunny', 'Unplug Bunny': 'Bunny', 'Birthday Bunny': 'Bunny', 'Choice Bunny': 'Bunny', 'Proud Bunny': 'Bunny', 'Brave Bunny': 'Bunny', 'Cheer Bunny': 'Bunny', 'Chill Bunny': 'Bunny', 'Hug Bunny': 'Bunny', 'Bestie Bunny': 'Bunny', 'Nope Bunny': 'Bunny',
          'Mint LolliBall': 'LolliBall', 'Blue LolliBall': 'LolliBall', 'Purple LolliBall': 'LolliBall', 'Pink LolliBall': 'LolliBall', 'White LolliBall': 'LolliBall'
        };
        const famName = p.family_name || knownFamilies[p.product_short_name || ''];
        return famName === family;
      }).map(p => p.asin));
      sc = sc.filter(s => s.asin && familyAsins.has(s.asin));
    }
    // Filter storage to current period only
    const periodSc = sc.filter(r => {
      if (!currentPeriod) return false;
      let rDate = '';
      if (isW) rDate = r.week_start_date || '';
      else if (periodMode === 'month') rDate = (r.week_start_date || '').slice(0, 7);
      else if (periodMode === 'quarter') { const ms = r.week_start_date || ''; const m = parseInt(ms.slice(5, 7), 10); rDate = `${ms.slice(0, 4)}-Q${Math.ceil(m / 3)}`; }
      else rDate = (r.week_start_date || '').slice(0, 4);
      return filterForPeriod(rDate, currentPeriod);
    });
    const totalStorage = periodSc.reduce((s, r) => s + (r.weekly_storage_cost || 0), 0);

    // Per-unit storage cost split into FBA vs AWD
    // Primary: compute from package cubic feet × rate (when available from Cube)
    // Fallback: split actual storage proportionally by FBA/AWD rate ratio
    const avgCubicFeet = prods.length > 0
      ? prods.reduce((s, p) => s + (p.package_cubic_feet || 0), 0) / prods.length
      : 0;
    const storagePeriodMonth = periodMode === 'weeks' && currentPeriod
      ? parseInt(currentPeriod.slice(5, 7), 10)
      : periodMode === 'month' && currentPeriod
        ? parseInt(currentPeriod.slice(5, 7), 10)
        : new Date().getMonth() + 1;
    const fbaRate = storagePeriodMonth >= 10 && storagePeriodMonth <= 12 ? 2.40 : 0.87;
    const awdRate = 0.51; // $0.51/cu ft/month (West Coast Smart Storage — matches V_MONTHLY_STORAGE_COST)
    // AWD one-time fees per unit:
    // - Processing fees are per BOX → divide by package_quantity to get per unit
    // - Transportation is per cubic foot
    const avgPkgQty = prods.length > 0
      ? prods.reduce((s, p) => s + (p.package_quantity || 1), 0) / prods.length
      : 1;
    const awdInboundPU = 1.40 / avgPkgQty;   // $1.40/box inbound processing
    const awdOutboundPU = 1.40 / avgPkgQty;   // $1.40/box outbound processing (AWD→FBA)
    const awdTransportPU = avgCubicFeet * 1.40; // $1.40/cu ft transportation

    // Period label for storage display
    const storagePeriodLabel = periodMode === 'weeks' ? 'weekly' : periodMode === 'month' ? 'monthly' : periodMode === 'quarter' ? 'quarterly' : 'yearly';

    let storageFbaPU: number;
    let storageAwdPU: number;
    if (avgCubicFeet > 0) {
      // Cubic-feet approach: unit_cubic_feet × rate, prorated to period
      let periodDays = 7;
      if (periodMode === 'month') { const [y2, m2] = (currentPeriod || '2026-01').split('-'); periodDays = new Date(Number(y2), Number(m2), 0).getDate(); }
      else if (periodMode === 'quarter') periodDays = 91;
      else if (periodMode === 'year') periodDays = 365;
      const periodFraction = periodDays / 30.44;
      storageFbaPU = avgCubicFeet * fbaRate * periodFraction;
      storageAwdPU = avgCubicFeet * awdRate * periodFraction;
    } else {
      // Fallback: split actual storage per unit by FBA/AWD rate ratio
      const storPU = tU > 0 ? totalStorage / tU : 0;
      const totalRate = fbaRate + awdRate;
      storageFbaPU = storPU * (fbaRate / totalRate);
      storageAwdPU = storPU * (awdRate / totalRate);
    }

    const gpPU = wSP - wCogs - wShip - wFba, adsPU = tU > 0 ? tA / tU : 0, npPU = tU > 0 ? tN / tU : 0;

    // Days in period
    let days = 7;
    if (periodMode === 'month') { const [y, m] = (currentPeriod || '2026-01').split('-'); days = new Date(Number(y), Number(m), 0).getDate(); }
    else if (periodMode === 'quarter') days = 91;
    else if (periodMode === 'year') days = 365;

    // Stock — aggregate all supply chain fields (same calc as HomePage)
    let sFba = 0, sAwd = 0, sTransit = 0, sMfr = 0, sAvail = 0, sVel = 0, sSellable = 0;
    let sAwdTargetMin = 0, sAwdTargetMax = 0, sAwdApprovedMin = 0, sAwdApprovedMax = 0;
    let sLast30d = 0, sLast30dPlanned = 0, sNext30d = 0, sNext31_60d = 0, sNext61_90d = 0;
    supply.forEach(s => {
      sFba += s.fba_stock_qty || 0;
      sAwd += s.awd_stock_qty || 0;
      sTransit += s.in_transit_qty || 0;
      sMfr += s.mfr_stock_qty || 0;
      sAvail += s.total_available_qty || 0;
      sSellable += s.sellable_qty || 0;
      sVel += s.daily_velocity || 0;
      sAwdTargetMin += s.awd_target_min ?? 0;
      sAwdTargetMax += s.awd_target_max ?? 0;
      sAwdApprovedMin += s.awd_approved_min ?? 0;
      sAwdApprovedMax += s.awd_approved_max ?? 0;
      sLast30d += s.last_30d_sold || 0;
      sLast30dPlanned += s.last_30d_planned || 0;
      sNext30d += s.next_30d_planned || 0;
      sNext31_60d += s.next_31_60d_planned || 0;
      sNext61_90d += s.next_61_90d_planned || 0;
    });
    const docAll = sVel > 0 ? Math.round(sAvail / sVel) : 0;
    const docFba = sVel > 0 ? Math.round(sFba / sVel) : 0;
    const docAwd = sVel > 0 ? Math.round((sSellable - sFba) / sVel) : 0;

    const docColor = (d: number) => d <= 20 ? 'var(--color-negative)' : d < 30 ? '#f59e0b' : d <= 45 ? 'var(--color-positive)' : d <= 60 ? '#f59e0b' : 'var(--color-negative)';

    // Ads Sales/Units from ads_7d (keyword-level data filtered to period)
    const adsMetrics = (() => {
      let rows = data.ads_7d || [];
      const isW2 = periodMode === 'weeks';
      if (currentPeriod) {
        rows = rows.filter(r => {
          const d = r.date || r.week_start || '';
          if (!d) return false;
          if (isW2) { const dt = new Date(currentPeriod + 'T12:00:00Z'); dt.setUTCDate(dt.getUTCDate() + 6); return d >= currentPeriod && d <= `${dt.getUTCFullYear()}-${String(dt.getUTCMonth()+1).padStart(2,'0')}-${String(dt.getUTCDate()).padStart(2,'0')}`; }
          if (periodMode === 'month') return (d).slice(0,7) === currentPeriod || (r.week_start || '').slice(0,7) === currentPeriod;
          if (periodMode === 'quarter') { const [y,q] = currentPeriod.split('-'); const qn = parseInt(q.replace('Q',''),10); const sm = (qn-1)*3+1; const em = sm+2; return d >= `${y}-${String(sm).padStart(2,'0')}-01` && d <= `${y}-${String(em).padStart(2,'0')}-31`; }
          return d.slice(0,4) === currentPeriod;
        });
      }
      if (product) {
        const productInfo = prods[0];
        const productName = productInfo?.product_short_name;
        if (productName) rows = rows.filter(r => r.product_short_name === productName);
      } else if (family) {
        rows = rows.filter(r => famFromType(r.parent_name ?? r.product_short_name ?? null) === family);
      }
      const campaigns = rows.filter(r => r.row_type === 'campaign');
      return {
        sales: campaigns.reduce((s, r) => s + (r.sales || 0), 0),
        units: campaigns.reduce((s, r) => s + (r.orders || 0), 0), // ads orders = ads units
      };
    })();

    const measures = {
      pnl: [
        { l: 'Sale Price', v: fM(wSP), c: 'var(--color-positive)' },
        { l: 'COGS', v: fM(wCogs), c: 'var(--color-negative)' },
        { l: 'Shipping', v: fM(wShip), c: 'var(--color-negative)' },
        { l: 'Pick & Pack', v: fM(wPP), c: 'var(--color-negative)' },
        { l: 'Referral Fee', v: fM(wRef), c: 'var(--color-negative)' },
        { l: 'Gross Profit', v: fM(gpPU), c: gpPU >= 0 ? 'var(--color-positive)' : 'var(--color-negative)' },
        { l: 'Ads Cost', v: fM(adsPU), c: 'var(--color-negative)' },
        { l: 'Net Profit', v: fM(npPU), c: npPU >= 0 ? 'var(--color-positive)' : 'var(--color-negative)' },
        { l: 'Margin', v: fP(wSP > 0 ? npPU / wSP : 0), c: npPU >= 0 ? 'var(--color-positive)' : 'var(--color-negative)' },
        // Storage per unit of inventory (not part of P&L — depends on inventory, not sales)
        { l: `Storage FBA (${storagePeriodLabel})`, v: fM(storageFbaPU), c: 'var(--color-faint)', it: true },
        { l: `Storage AWD (${storagePeriodLabel})`, v: fM(storageAwdPU), c: 'var(--color-faint)', it: true },
        { l: 'AWD Inbound', v: fM(awdInboundPU), c: 'var(--color-faint)', it: true },
        { l: 'AWD → FBA', v: fM(awdOutboundPU + awdTransportPU), c: 'var(--color-faint)', it: true },
      ] as { l: string; v: string; c: string; it?: boolean }[],
      daily: [
        { l: 'Orders', v: fmt(tO / days, 1), c: 'var(--color-text)' },
        { l: 'Units Sold', v: fmt(tU / days, 1), c: 'var(--color-text)' },
        { l: 'Sale Forecast', v: fmt(sLast30dPlanned / 30, 1), c: 'var(--color-text)' },
        { l: 'Sales', v: fM(tS / days), c: 'var(--color-text)' },
        { l: 'Net Profit', v: fM(tN / days), c: tN >= 0 ? 'var(--color-positive)' : 'var(--color-negative)' },
        { l: 'Ads Cost', v: fM(tA / days), c: 'var(--color-negative)' },
        { l: 'Ads Units Sold', v: fmt(adsMetrics.units / days, 1), c: 'var(--color-text)' },
        { l: 'Ads Sales', v: fM(adsMetrics.sales / days), c: 'var(--color-text)' },
      ],
      stock: [
        { l: 'FBA', v: fmt(sFba, 0), c: 'var(--color-text)' },
        { l: 'AWD', v: fmt(sAwd, 0), c: 'var(--color-text)' },
        { l: 'In Transit', v: fmt(sTransit, 0), c: 'var(--color-text)' },
        { l: 'MFR Stock', v: fmt(sMfr, 0), c: 'var(--color-text)' },
        { l: 'Total Available', v: fmt(sAvail, 0), c: 'var(--color-text)' },
        { l: '30d Sales vs Expected', v: (() => {
          const pct = sLast30dPlanned > 0 ? Math.round((sLast30d / sLast30dPlanned) * 100) : 0;
          const endStr = data._meta?.data_freshness?.performance_max_date;
          const end = endStr ? new Date(`${endStr}T12:00:00Z`) : (() => { const d = new Date(); d.setDate(d.getDate() - 1); return d; })();
          const start = new Date(end);
          start.setDate(end.getDate() - 29);
          const fmtDate = (d: Date) => d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
          return (
            <div className="flex flex-col items-end leading-tight">
              <span>{pct}%  ({fmt(sLast30d, 0)} sold / {fmt(sLast30dPlanned, 0)} plan)</span>
              <span className="text-[9px] mt-0.5 font-normal" style={{ color: 'var(--color-faint)', fontFamily: 'var(--font-sans, sans-serif)' }}>{fmtDate(start)} – {fmtDate(end)}</span>
            </div>
          );
        })(), c: (() => {
          const pct = sLast30dPlanned > 0 ? (sLast30d / sLast30dPlanned) * 100 : 0;
          return pct >= 90 ? 'var(--color-positive)' : pct >= 70 ? '#f59e0b' : 'var(--color-negative)';
        })() },
        { l: 'Days Cover', v: `${docAll}`, c: docColor(docAll) },
        { l: 'Days Cover (FBA)', v: `${docFba}`, c: docColor(docFba) },
        { l: 'Days Cover (AWD)', v: `${docAwd}`, c: docColor(docAwd) },
        { l: 'AWD Min (Defined)', v: `${fmt(sAwdTargetMin, 0)} (${fmt(sAwdApprovedMin, 0)})`, c: 'var(--color-text)' },
        { l: 'AWD Max (Defined)', v: `${fmt(sAwdTargetMax, 0)} (${fmt(sAwdApprovedMax, 0)})`, c: 'var(--color-text)' },
      ],
      forecast: { next30: sNext30d, next31_60: sNext31_60d, next61_90: sNext61_90d, last30: sLast30d },
    };

    // PPC metrics — computed from period trends (already filtered by family/product)
    const tClicks = periodRows.reduce((s, r) => s + (r.clicks || 0), 0);
    const tSessions = periodRows.reduce((s, r) => s + (r.sessions || 0), 0);
    const tImpressions = periodRows.reduce((s, r) => s + (r.impressions || 0), 0);
    const ppcAcos = adsMetrics.sales > 0 ? (tA / adsMetrics.sales) * 100 : 0;
    const ppcTacos = tS > 0 ? (tA / tS) * 100 : 0;
    const ppcRoas = tA > 0 ? (tS - tC) / tA : 0;
    const ppcCvr = tClicks > 0 ? (tO / tClicks) * 100 : 0;
    const ppcCtr = tImpressions > 0 ? (tClicks / tImpressions) * 100 : 0;
    const ppcCpc = tClicks > 0 ? tA / tClicks : 0;

    // Campaign count from ads_7d (period-filtered, has product_short_name for ASIN matching)
    const ppcAds7d = (() => {
      let rows = data.ads_7d || [];
      // Date filter
      const isW2 = periodMode === 'weeks';
      if (currentPeriod) {
        rows = rows.filter(r => {
          const d = r.date || r.week_start || '';
          if (!d) return false;
          if (isW2) return d >= currentPeriod && d <= (() => { const dt = new Date(currentPeriod + 'T12:00:00Z'); dt.setUTCDate(dt.getUTCDate() + 6); return `${dt.getUTCFullYear()}-${String(dt.getUTCMonth()+1).padStart(2,'0')}-${String(dt.getUTCDate()).padStart(2,'0')}`; })();
          if (periodMode === 'month') return (d).slice(0,7) === currentPeriod || (r.week_start || '').slice(0,7) === currentPeriod;
          if (periodMode === 'quarter') { const [y,q] = currentPeriod.split('-'); const qn = parseInt(q.replace('Q',''),10); const sm = (qn-1)*3+1; const em = sm+2; return d >= `${y}-${String(sm).padStart(2,'0')}-01` && d <= `${y}-${String(em).padStart(2,'0')}-31`; }
          return d.slice(0,4) === currentPeriod;
        });
      }
      // Product / Family filter (like HomePage: use product_short_name)
      if (product) {
        const productInfo = prods[0];
        const productName = productInfo?.product_short_name;
        if (productName) rows = rows.filter(r => r.product_short_name === productName);
      } else if (family) {
        rows = rows.filter(r => famFromType(r.parent_name ?? r.product_short_name ?? null) === family);
      }
      return rows.filter(r => r.row_type === 'campaign');
    })();
    // Deduplicate by campaign_id
    const uniqueCampaigns = new Map<string, { name: string; type: string | null }>();
    ppcAds7d.forEach(r => { if (!uniqueCampaigns.has(r.campaign_id)) uniqueCampaigns.set(r.campaign_id, { name: r.campaign_name, type: r.campaign_type }); });
    const numCampaigns = uniqueCampaigns.size;
    const campArr = [...uniqueCampaigns.values()];
    const numVideo = campArr.filter(c => c.type === 'SB' && ((c.name || '').toUpperCase().includes('VIDEO') || (c.name || '').toUpperCase().includes('_SBV_'))).length;
    const numBrand = campArr.filter(c => c.type === 'SB' && !((c.name || '').toUpperCase().includes('VIDEO') || (c.name || '').toUpperCase().includes('_SBV_'))).length;
    const numProduct = campArr.filter(c => c.type === 'SP').length;
    
    // Wasted spend from coach_campaigns (still best source for this metric)
    const campFamily2 = product ? (prods[0]?.family_name ?? family) : family;
    let coachCampaigns = data.coach_campaigns || [];
    if (campFamily2) coachCampaigns = coachCampaigns.filter(c => {
      const famStr = c.experiment_name || c.campaign_name || '';
      return experimentMatchesFamily(famStr, campFamily2 as any);
    });
    const wastedSpend = coachCampaigns.reduce((s, c) => s + (c.spend_on_negate_terms || 0), 0);

    // Unfiltered totals for % calculations
    const allTrends = isW ? (data.weekly_trends || []) : (data.monthly_trends || []);
    const allPeriodRows = allTrends.filter(r => {
      if (!currentPeriod) return false;
      let rDate = '';
      if (isW) rDate = r.week_start || '';
      else if (periodMode === 'month') rDate = (r.month_start || '').slice(0, 7);
      else if (periodMode === 'quarter') { const ms = r.month_start || ''; const m = parseInt(ms.slice(5, 7), 10); rDate = `${ms.slice(0, 4)}-Q${Math.ceil(m / 3)}`; }
      else rDate = (r.month_start || '').slice(0, 4);
      return filterForPeriod(rDate, currentPeriod);
    });
    const totalAdSpend = allPeriodRows.reduce((s, r) => s + (r.ad_cost || 0), 0);
    const totalNetProfit = allPeriodRows.reduce((s, r) => s + (r.net_profit || 0), 0);
    const pctAdsSpend = totalAdSpend > 0 ? (tA / totalAdSpend) * 100 : 0;
    const pctNetProfit = totalNetProfit !== 0 ? (tN / totalNetProfit) * 100 : 0;

    const ppc: { l: string; v: string; c: string }[] = [
      { l: 'Ads Spend', v: fM(tA), c: 'var(--color-negative)' },
      { l: 'Sales', v: fM(tS), c: 'var(--color-positive)' },
      { l: 'Ads ACoS', v: fP(ppcAcos), c: ppcAcos > 30 ? 'var(--color-negative)' : ppcAcos > 15 ? '#f59e0b' : 'var(--color-positive)' },
      { l: 'Ads TACoS', v: fP(ppcTacos), c: ppcTacos > 30 ? 'var(--color-negative)' : ppcTacos > 15 ? '#f59e0b' : 'var(--color-positive)' },
      { l: 'Ads ROAS', v: fR(ppcRoas), c: ppcRoas >= 3 ? 'var(--color-positive)' : ppcRoas >= 2 ? '#f59e0b' : 'var(--color-negative)' },
      { l: 'Ads CVR', v: fP(ppcCvr), c: 'var(--color-text)' },
      { l: 'Ads CTR', v: fP(ppcCtr), c: 'var(--color-text)' },
      { l: 'Ads CPC', v: '$' + ppcCpc.toFixed(2), c: 'var(--color-text)' },
      { l: 'Campaigns', v: `${fmt(numCampaigns, 0)} (${numProduct} PD, ${numVideo} Vid, ${numBrand} Brand)`, c: 'var(--color-text)' },
      { l: 'Wasted Ad Spend', v: fM(wastedSpend), c: wastedSpend > 0 ? 'var(--color-negative)' : 'var(--color-text)' },
      { l: '% Total Ads Spend', v: (family || product) ? fP(pctAdsSpend) : '100.0%', c: 'var(--color-text)' },
      { l: '% Total Net Profit', v: (family || product) ? fP(pctNetProfit) : '100.0%', c: pctNetProfit < 0 ? 'var(--color-negative)' : 'var(--color-text)' },
    ];

    // P&L totals for the period (not per-unit)
    const totalShip = wShip * tU, totalPP = wPP * tU, totalRef = wRef * tU;
    const totalGP = tS - tC - totalShip - (wFba * tU);
    const totalNPMargin = tS > 0 ? (tN / tS) * 100 : 0;

    const pnl_total: { l: string; v: string; c: string; it?: boolean }[] = [
      { l: 'Sales', v: fM(tS), c: 'var(--color-positive)' },
      { l: 'Units', v: fmt(tU, 0), c: 'var(--color-text)' },
      { l: 'COGS', v: fM(tC), c: 'var(--color-negative)' },
      { l: 'Shipping', v: fM(totalShip), c: 'var(--color-negative)' },
      { l: 'Pick & Pack', v: fM(totalPP), c: 'var(--color-negative)' },
      { l: 'Referral Fee', v: fM(totalRef), c: 'var(--color-negative)' },
      { l: 'Storage (actual)', v: fM(totalStorage), c: 'var(--color-negative)', it: true },
      { l: 'Gross Profit', v: fM(totalGP), c: totalGP >= 0 ? 'var(--color-positive)' : 'var(--color-negative)' },
      { l: 'Ads Cost', v: fM(tA), c: 'var(--color-negative)' },
      { l: 'Net Profit', v: fM(tN), c: tN >= 0 ? 'var(--color-positive)' : 'var(--color-negative)' },
      { l: 'Margin', v: fP(totalNPMargin), c: tN >= 0 ? 'var(--color-positive)' : 'var(--color-negative)' },
    ];

    return { ...measures, ppc, pnl_total };
  }, [data, family, product, currentPeriod, periodMode, periodType]);

  // Build the cards array in order of measureIds, filtering to only selected ones
  const ALL_MEASURE_MAP: Record<MeasureCardId, { t: string; col: string; items: { l: string; v: string; c: string; it?: boolean }[]; forecast?: typeof measures.forecast }> = {
    pnl_total:    { t: 'P&L',            col: '#f59e0b', items: measures.pnl_total },
    pnl_per_unit: { t: 'P&L per Unit',   col: '#a78bfa', items: measures.pnl },
    daily_avg:    { t: 'Daily Average',   col: '#60a5fa', items: measures.daily },
    plan:         { t: 'Plan',            col: '#34d399', items: measures.stock, forecast: measures.forecast },
    plan_trend:   { t: 'Plan Trend',      col: '#06b6d4', items: [] },
    ppc:          { t: 'PPC',             col: '#ef4444', items: measures.ppc },
  };

  const GS = measureIds.map(id => ({ id, ...ALL_MEASURE_MAP[id] })).filter(g => g.items !== undefined);

  if (GS.length === 0) return null;

  return (
    <div className="space-y-3 mt-2">
      <h2 className="text-[16px] font-bold tracking-tight" style={{ color: 'var(--color-text)' }}>Measures</h2>
      <div className="grid gap-3" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(260px, 1fr))' }}>
        {GS.map(g => g.id === 'plan_trend' ? (
          <PlanTrendCard key={g.t} data={data} family={family} product={product} />
        ) : (
          <div key={g.t} className="rounded-xl overflow-hidden" style={{ background: 'var(--color-card)', border: '1px solid var(--color-border)', boxShadow: 'var(--shadow-card)' }}>
            <div className="px-4 py-2" style={{ borderBottom: '1px solid var(--color-border)' }}>
              <span className="font-mono text-[10px] uppercase tracking-[0.12em] font-bold" style={{ color: g.col }}>{g.t}</span>
            </div>
            <div className="px-4 py-2 space-y-1">
              {(() => {
                const mainItems = g.items.filter(m => !m.it);
                const italicItems = g.items.filter(m => m.it);
                return (
                  <>
                    {mainItems.map(m => (
                      <div key={m.l} className="flex items-center justify-between py-0.5">
                        <span className="text-[11px]" style={{ color: 'var(--color-muted)' }}>{m.l}</span>
                        <span className="font-mono text-[12px] font-semibold" style={{ color: m.c }}>{m.v}</span>
                      </div>
                    ))}
                    {italicItems.length > 0 && (
                      <>
                        <div className="my-1" style={{ borderTop: '1px dashed var(--color-border)' }} />
                        {italicItems.map(m => (
                          <div key={m.l} className="flex items-center justify-between py-0.5">
                            <span className="text-[10px] italic" style={{ color: 'var(--color-faint)' }}>{m.l}</span>
                            <span className="font-mono text-[11px] italic" style={{ color: m.c }}>{m.v}</span>
                          </div>
                        ))}
                      </>
                    )}
                  </>
                );
              })()}
            </div>
            {/* Forecast timeline bar for the Stock card */}
            {g.forecast && (() => {
              const { next30, next31_60, next61_90 } = g.forecast;
              const total = next30 + next31_60 + next61_90;
              if (total === 0) return null;
              const segments = [
                { label: '30d', units: next30, color: '#34d399' },
                { label: '60d', units: next31_60, color: '#60a5fa' },
                { label: '90d', units: next61_90, color: '#a78bfa' },
              ];
              return (
                <div className="px-4 py-3" style={{ borderTop: '1px solid var(--color-border)' }}>
                  <div className="text-[10px] font-mono uppercase tracking-wider font-bold mb-2" style={{ color: 'var(--color-muted)' }}>Planned Forecast</div>
                  <div className="relative flex items-center h-[28px] rounded-md overflow-hidden" style={{ background: 'var(--color-inset)' }}>
                    {segments.map((seg, i) => {
                      const pct = (seg.units / total) * 100;
                      if (pct < 0.5) return null;
                      return (
                        <div
                          key={seg.label}
                          className="h-full flex items-center justify-center relative"
                          style={{
                            width: `${pct}%`,
                            background: seg.color,
                            borderRight: i < segments.length - 1 ? '2px solid var(--color-card)' : 'none',
                          }}
                        >
                          <span className="text-[10px] font-bold text-white drop-shadow-sm" style={{ textShadow: '0 1px 2px rgba(0,0,0,0.3)' }}>
                            {fmt(seg.units, 0)}u
                          </span>
                        </div>
                      );
                    })}
                  </div>
                  <div className="flex mt-1">
                    {segments.map((seg, i) => {
                      const pct = (seg.units / total) * 100;
                      if (pct < 0.5) return null;
                      return (
                        <div key={seg.label} className="flex items-center justify-center" style={{ width: `${pct}%` }}>
                          <span className="text-[9px] font-mono" style={{ color: seg.color }}>{seg.label}</span>
                        </div>
                      );
                    })}
                  </div>
                </div>
              );
            })()}
          </div>
        ))}
      </div>
    </div>
  );
}

/* ── Plan Trend Card ── */
type FcMap = Record<string, number>; // YYYY-MM → forecast units

function PlanTrendCard({ data, family, product }: { data: DashboardData; family: string | null; product: string | null }) {
  const [tab, setTab] = useState<'daily' | 'weekly' | 'monthly'>('daily');
  const [fcMap, setFcMap] = useState<FcMap>({});

  // Load forecast demand from Cube (monthly granularity per product)
  useEffect(() => {
    (async () => {
      try {
        const { cubeLoad } = await import('../hooks/useCubeData');
        const rows = await cubeLoad({
          dimensions: ['ForecastDemand.product', 'ForecastDemand.family', 'ForecastDemand.forecastYear', 'ForecastDemand.forecastMonth'],
          measures: ['ForecastDemand.forecastUnits'],
        }) as Record<string, unknown>[];
        const prods = data.products || [];
        const map: FcMap = {};
        for (const r of rows) {
          const prod = String(r['ForecastDemand.product'] ?? '');
          const fam = String(r['ForecastDemand.family'] ?? '');
          const yr = Number(r['ForecastDemand.forecastYear'] ?? 0);
          const mo = Number(r['ForecastDemand.forecastMonth'] ?? 0);
          const units = Number(r['ForecastDemand.forecastUnits'] ?? 0);
          if (!yr || !mo) continue;
          // Apply family/product filter
          if (product) {
            const p = prods.find(pp => pp.asin === product);
            if (!p || (p.product_short_name !== prod && famFromType(p.product_type) !== fam)) continue;
            // For product filter, only include matching product rows
            if (p.product_short_name !== prod) continue;
          } else if (family) {
            if (fam !== family) continue;
          }
          const key = `${yr}-${String(mo).padStart(2, '0')}`;
          map[key] = (map[key] || 0) + units;
        }
        setFcMap(map);
      } catch (e) { console.warn('[PlanTrendCard] forecast load failed', e); }
    })();
  }, [data.products, family, product]);

  // Helper: get forecast daily rate for a date from monthly forecast map
  const getFcDaily = useCallback((dateStr: string): number => {
    const ym = dateStr.slice(0, 7); // YYYY-MM
    const fcUnits = fcMap[ym];
    if (!fcUnits) return 0;
    const [y, m] = ym.split('-').map(Number);
    const daysInMonth = new Date(y, m, 0).getDate();
    return fcUnits / daysInMonth;
  }, [fcMap]);

  const trendData = useMemo(() => {
    const perfMax = data._meta?.data_freshness?.performance_max_date || '';
    if (!perfMax) return [];

    const toISO = (d: Date) => d.toISOString().slice(0, 10);

    if (tab === 'daily') {
      let daily = data.daily_trends || [];
      if (product) {
        const prod = (data.products || []).find(p => p.asin === product);
        if (prod) daily = daily.filter(d => d.product_type === prod.product_type);
        else daily = [];
      } else if (family) {
        daily = daily.filter(d => famFromType(d.product_type) === family);
      }

      const byDate: Record<string, number> = {};
      for (const r of daily) {
        if (!r.date) continue;
        byDate[r.date] = (byDate[r.date] || 0) + (r.orders || 0);
      }

      const allDates = Object.keys(byDate).filter(d => d <= perfMax).sort();
      const last7 = allDates.slice(-7);

      const cutoff = new Date(perfMax + 'T00:00:00');
      const forecastDays: { label: string; value: number; planned: number; isForecast: boolean }[] = [];
      for (let i = 1; i <= 7; i++) {
        const d = new Date(cutoff);
        d.setDate(d.getDate() + i);
        const ds = toISO(d);
        const fc = Math.round(getFcDaily(ds));
        forecastDays.push({ label: ds.slice(5), value: fc, planned: 0, isForecast: true });
      }

      const actualDays = last7.map(d => ({ label: d.slice(5), value: byDate[d] || 0, planned: Math.round(getFcDaily(d)), isForecast: false }));
      return [...actualDays, ...forecastDays];
    }

    if (tab === 'weekly') {
      let weekly: TrendRow[] = product
        ? (data.weekly_trends_by_asin || []).filter((r: TrendRow & { asin?: string }) => r.asin === product)
        : (data.weekly_trends || []);
      if (family) weekly = weekly.filter(r => famFromType(r.product_type) === family);

      const byWeek: Record<string, number> = {};
      for (const r of weekly) {
        const ws = r.week_start || '';
        if (!ws) continue;
        byWeek[ws] = (byWeek[ws] || 0) + (r.orders || 0);
      }

      const allWeeks = Object.keys(byWeek).filter(w => w <= perfMax).sort();
      const last4 = allWeeks.slice(-4);

      // Compute weekly forecast from monthly map: sum daily rate for 7 days starting at week_start
      const weekFc = (ws: string): number => {
        let total = 0;
        const start = new Date(ws + 'T00:00:00');
        for (let d = 0; d < 7; d++) {
          const dt = new Date(start);
          dt.setDate(dt.getDate() + d);
          total += getFcDaily(toISO(dt));
        }
        return Math.round(total);
      };

      const lastWeekDate = last4.length > 0 ? new Date(last4[last4.length - 1] + 'T00:00:00') : new Date(perfMax + 'T00:00:00');
      const forecastWeeks: { label: string; value: number; planned: number; isForecast: boolean }[] = [];
      for (let i = 1; i <= 4; i++) {
        const d = new Date(lastWeekDate);
        d.setDate(d.getDate() + i * 7);
        const ds = toISO(d);
        const fc = weekFc(ds);
        forecastWeeks.push({ label: ds.slice(5), value: fc, planned: 0, isForecast: true });
      }

      const actualWeeks = last4.map(w => ({ label: w.slice(5), value: byWeek[w] || 0, planned: weekFc(w), isForecast: false }));
      return [...actualWeeks, ...forecastWeeks];
    }

    // Monthly
    let monthly: TrendRow[] = product
      ? (data.monthly_trends_by_asin || []).filter((r: TrendRow & { asin?: string }) => r.asin === product)
      : (data.monthly_trends || []);
    if (family) monthly = monthly.filter(r => famFromType(r.product_type) === family);

    const byMonth: Record<string, number> = {};
    for (const r of monthly) {
      const ms = (r.month_start || '').slice(0, 7);
      if (!ms) continue;
      byMonth[ms] = (byMonth[ms] || 0) + (r.orders || 0);
    }

    const perfMonth = perfMax.slice(0, 7);
    const allMonths = Object.keys(byMonth).filter(m => m <= perfMonth).sort();
    const last4m = allMonths.slice(-4);

    const MNAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const lastMonth = last4m.length > 0 ? last4m[last4m.length - 1] : perfMonth;
    const [lastY, lastM] = lastMonth.split('-').map(Number);
    const forecastMonths: { label: string; value: number; planned: number; isForecast: boolean }[] = [];
    for (let i = 1; i <= 4; i++) {
      const m = ((lastM - 1 + i) % 12);
      const y = lastY + Math.floor((lastM - 1 + i) / 12);
      const key = `${y}-${String(m + 1).padStart(2, '0')}`;
      forecastMonths.push({ label: MNAMES[m], value: fcMap[key] || 0, planned: 0, isForecast: true });
    }

    const actualMonths = last4m.map(m => ({
      label: MNAMES[parseInt(m.slice(5), 10) - 1],
      value: byMonth[m] || 0,
      planned: fcMap[m] || 0,
      isForecast: false,
    }));
    return [...actualMonths, ...forecastMonths];
  }, [data, family, product, tab, fcMap, getFcDaily]);

  const maxVal = Math.max(...trendData.map(d => Math.max(d.value, d.planned)), 1);

  return (
    <div className="rounded-xl overflow-hidden" style={{ background: 'var(--color-card)', border: '1px solid var(--color-border)', boxShadow: 'var(--shadow-card)' }}>
      <div className="px-4 py-2 flex items-center justify-between" style={{ borderBottom: '1px solid var(--color-border)' }}>
        <span className="font-mono text-[10px] uppercase tracking-[0.12em] font-bold" style={{ color: '#06b6d4' }}>Plan Trend</span>
        <div className="flex gap-0.5">
          {(['daily', 'weekly', 'monthly'] as const).map(t => (
            <button key={t} onClick={() => setTab(t)}
              className="text-[9px] px-2 py-0.5 rounded-full font-medium transition-colors"
              style={{
                background: tab === t ? 'rgba(6,182,212,0.15)' : 'transparent',
                color: tab === t ? '#06b6d4' : 'var(--color-faint)',
                border: tab === t ? '1px solid rgba(6,182,212,0.3)' : '1px solid transparent',
              }}
            >{t.charAt(0).toUpperCase() + t.slice(1)}</button>
          ))}
        </div>
      </div>
      <div className="px-3 py-3">
        {trendData.length === 0 ? (
          <div className="text-center py-4 text-[11px]" style={{ color: 'var(--color-faint)' }}>No data available</div>
        ) : (
          <>
            {/* Legend */}
            <div className="flex items-center gap-3 mb-2">
              <span className="flex items-center gap-1 text-[9px]" style={{ color: 'var(--color-muted)' }}>
                <span className="w-2.5 h-2.5 rounded-sm" style={{ background: '#06b6d4' }} /> Actual
              </span>
              <span className="flex items-center gap-1 text-[9px]" style={{ color: 'var(--color-muted)' }}>
                <span className="w-2.5 h-2.5 rounded-sm" style={{ background: '#06b6d4', opacity: 0.3 }} /> Forecast
              </span>
              <span className="flex items-center gap-1 text-[9px]" style={{ color: 'var(--color-muted)' }}>
                <span className="w-2.5 h-[2px]" style={{ background: '#f59e0b' }} /> Plan
              </span>
            </div>
            {/* Bar chart */}
            <div className="flex items-end gap-[3px]" style={{ height: '90px' }}>
              {trendData.map((d, i) => {
                const h = maxVal > 0 ? (d.value / maxVal) * 100 : 0;
                const ph = d.planned > 0 && maxVal > 0 ? (d.planned / maxVal) * 100 : 0;
                const containerH = Math.max(h, ph, 2);
                return (
                  <div key={i} className="flex-1 flex flex-col items-center justify-end h-full min-w-0 relative">
                    <span className="text-[8px] font-mono mb-0.5 tabular-nums" style={{ color: d.isForecast ? 'rgba(6,182,212,0.5)' : '#06b6d4' }}>
                      {d.value > 999 ? `${(d.value / 1000).toFixed(1)}k` : d.value}
                    </span>
                    <div className="w-full relative" style={{ height: `${containerH}%` }}>
                      {/* Actual / forecast bar */}
                      <div
                        className="absolute bottom-0 left-0 right-0 rounded-t-sm transition-all"
                        style={{
                          height: `${h > 0 ? (h / containerH) * 100 : 2}%`,
                          background: d.isForecast ? 'rgba(6,182,212,0.2)' : '#06b6d4',
                          border: d.isForecast ? '1px dashed rgba(6,182,212,0.4)' : 'none',
                          borderBottom: 'none',
                        }}
                      />
                      {/* Plan line marker — only on actual bars */}
                      {!d.isForecast && ph > 0 && (
                        <div
                          className="absolute left-0 right-0"
                          style={{
                            bottom: `${(ph / containerH) * 100}%`,
                            height: '2px',
                            background: '#f59e0b',
                            borderRadius: '1px',
                            boxShadow: '0 0 3px rgba(245,158,11,0.4)',
                          }}
                          title={`Plan: ${d.planned}`}
                        />
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
            {/* Labels */}
            <div className="flex gap-[3px] mt-1">
              {trendData.map((d, i) => (
                <div key={i} className="flex-1 text-center min-w-0">
                  <span className="text-[7px] font-mono block truncate" style={{ color: d.isForecast ? 'var(--color-faint)' : 'var(--color-muted)' }}>
                    {d.label}
                  </span>
                </div>
              ))}
            </div>
          </>
        )}
      </div>
    </div>
  );
}

