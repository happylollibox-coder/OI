import React, { useState, useMemo } from 'react';
import type { DashboardData, ActionRow, CoachDecisionRow, StrategicPrediction } from '../types';
import { Badge, RoasBadge, ActionBadge } from '../components/Badge';
import { PageHeader } from '../components/PageHeader';
import { Empty } from '../components/Empty';
import { Th, SortTh, useSort, MEASURE_TIPS } from '../components/Tooltip';
import { fmt, fM, fP, fOrd, fCpc, famFromProduct, ACTION_META } from '../utils';
import { useFilters } from '../hooks/useFilters';
import { useDoQueue } from '../hooks/useDoQueue';

import { MeasureSelector, useMeasureSelection, type MeasureDef } from '../components/MeasureSelector';
import { usePageSummary } from '../components/PageSummaryBar';
import { Plus, Check, Download, CircleX, Ban, TrendingUp, TrendingDown, ShieldCheck, Eye, Crosshair, Sparkles, Target, Wrench, ArrowRightLeft } from 'lucide-react';
import { PieChart, Pie, Cell, Tooltip, ResponsiveContainer } from 'recharts';
import { DecisionTreeViewer } from '../components/Actions/DecisionTreeViewer';
// strategyRules is now DB-only; ActionType kept for potential future use in color mapping

import type { GroundTruth } from '../types';

/* ─── Pie chart bucket classification ─── */
const SPEND_BUCKETS = [
  { key: 'not_converting', label: 'Not Converting', color: '#ef4444', actions: ['STOP', 'NEGATE'] },
  { key: 'losing', label: 'Losing', color: '#f59e0b', actions: ['REDUCE_BID', 'FIX_HERO', 'SWITCH_HERO'] },
  { key: 'profitable', label: 'Profitable', color: '#22c55e', actions: ['KEEP'] },
  { key: 'scale', label: 'Scale', color: '#3b82f6', actions: ['BOOST', 'SCALE_UP', 'INCREASE_BID'] },
  { key: 'opportunity', label: 'Opportunity', color: '#a855f7', actions: ['PROMOTE_TO_EXACT', 'START'] },
] as const;


const ACTIONS_TABLE_COLUMNS: MeasureDef[] = [
  // Info
  { id: 'search_term', label: 'Keyword', group: 'Info' },
  { id: 'product_short_name', label: 'Product', group: 'Info' },
  { id: 'experiment_id', label: 'Experiment', group: 'Info', defaultVisible: false },
  { id: 'strategy_id', label: 'Strategy', group: 'Info', defaultVisible: false },
  // Ads 4w
  { id: 'spend', label: 'Ads Spend(4w)', tip: MEASURE_TIPS.spend, group: 'Ads 4w' },
  { id: 'orders', label: 'Ads Orders(4w)', tip: MEASURE_TIPS.orders, group: 'Ads 4w' },
  { id: 'conv_rate', label: 'Ads Conv%(4w)', tip: MEASURE_TIPS.conv_rate, group: 'Ads 4w' },
  { id: 'cpc', label: 'Ads CPC(4w)', tip: MEASURE_TIPS.cpc, group: 'Ads 4w' },
  { id: 'net_roas', label: 'Ads ROAS(4w)', tip: MEASURE_TIPS.net_roas, group: 'Ads 4w' },
  { id: 'ads_clicks_4w', label: 'Ads Clicks(4w)', group: 'Ads 4w', defaultVisible: false },
  { id: 'ads_impressions_4w', label: 'Ads Impressions(4w)', group: 'Ads 4w', defaultVisible: false },
  { id: 'ads_units_4w', label: 'Ads Units(4w)', group: 'Ads 4w', defaultVisible: false },
  { id: 'ads_sales_4w', label: 'Ads Sales(4w)', group: 'Ads 4w', defaultVisible: false },
  { id: 'ads_net_profit_4w', label: 'Ads Net Profit(4w)', group: 'Ads 4w', defaultVisible: false },
  { id: 'ads_cost_per_order_4w', label: 'Ads CPO(4w)', group: 'Ads 4w', defaultVisible: false },
  // Ads LY Peak
  { id: 'ads_spend_ly_peak', label: 'Ads Spend(LY Peak)', group: 'Ads LY', defaultVisible: false },
  { id: 'ads_orders_ly_peak', label: 'Ads Orders(LY Peak)', group: 'Ads LY', defaultVisible: false },
  { id: 'ads_clicks_ly_peak', label: 'Ads Clicks(LY Peak)', group: 'Ads LY', defaultVisible: false },
  { id: 'ads_impressions_ly_peak', label: 'Ads Impressions(LY Peak)', group: 'Ads LY', defaultVisible: false },
  { id: 'ads_units_ly_peak', label: 'Ads Units(LY Peak)', group: 'Ads LY', defaultVisible: false },
  { id: 'ads_sales_ly_peak', label: 'Ads Sales(LY Peak)', group: 'Ads LY', defaultVisible: false },
  { id: 'ads_cpc_ly_peak', label: 'Ads CPC(LY Peak)', group: 'Ads LY', defaultVisible: false },
  { id: 'ads_cvr_pct_ly_peak', label: 'Ads Conv%(LY Peak)', group: 'Ads LY', defaultVisible: false },
  { id: 'ads_net_roas_ly_peak', label: 'Ads ROAS(LY Peak)', group: 'Ads LY', defaultVisible: false },
  // Ads Lifetime
  { id: 'ads_spend_lifetime', label: 'Ads Spend(LT)', group: 'Ads LT', defaultVisible: false },
  { id: 'ads_orders_lifetime', label: 'Ads Orders(LT)', group: 'Ads LT', defaultVisible: false },
  { id: 'ads_net_roas_lifetime', label: 'Ads ROAS(LT)', group: 'Ads LT', defaultVisible: false },
  // SQP 4w Your ASIN
  { id: 'sqp_impressions_4w', label: 'SQP Impressions(4w)', group: 'SQP 4w', defaultVisible: false },
  { id: 'sqp_clicks_4w', label: 'SQP Clicks(4w)', group: 'SQP 4w', defaultVisible: false },
  { id: 'sqp_cart_adds_4w', label: 'SQP Cart Adds(4w)', group: 'SQP 4w', defaultVisible: false },
  { id: 'sqp_orders_4w', label: 'SQP Orders(4w)', group: 'SQP 4w', defaultVisible: false },
  { id: 'sqp_sales_4w', label: 'SQP Sales(4w)', group: 'SQP 4w', defaultVisible: false },
  { id: 'sqp_organic_units_4w', label: 'SQP Organic Orders(4w)', group: 'SQP 4w', defaultVisible: false },
  { id: 'sqp_show_rate_4w', label: 'SQP Show Rate(4w)', group: 'SQP 4w', defaultVisible: false },
  { id: 'sqp_impression_share_4w', label: 'SQP Imp Share(4w)', group: 'SQP 4w', defaultVisible: false },
  { id: 'sqp_organic_rank_4w', label: 'SQP Org Rank(4w)', group: 'SQP 4w', defaultVisible: false },
  // SQP 4w Amazon market
  { id: 'sqp_amazon_impressions_4w', label: 'SQP Amazon Impressions(4w)', group: 'SQP Amazon 4w', defaultVisible: false },
  { id: 'sqp_amazon_clicks_4w', label: 'SQP Amazon Clicks(4w)', group: 'SQP Amazon 4w', defaultVisible: false },
  { id: 'sqp_amazon_cart_adds_4w', label: 'SQP Amazon Cart Adds(4w)', group: 'SQP Amazon 4w', defaultVisible: false },
  { id: 'sqp_amazon_orders_4w', label: 'SQP Amazon Orders(4w)', group: 'SQP Amazon 4w', defaultVisible: false },
  { id: 'sqp_amazon_search_volume_4w', label: 'SQP Amazon Volume(4w)', group: 'SQP Amazon 4w', defaultVisible: false },
  // SQP LY Peak Your ASIN
  { id: 'sqp_impressions_ly_peak', label: 'SQP Impressions(LY Peak)', group: 'SQP LY', defaultVisible: false },
  { id: 'sqp_clicks_ly_peak', label: 'SQP Clicks(LY Peak)', group: 'SQP LY', defaultVisible: false },
  { id: 'sqp_cart_adds_ly_peak', label: 'SQP Cart Adds(LY Peak)', group: 'SQP LY', defaultVisible: false },
  { id: 'sqp_orders_ly_peak', label: 'SQP Orders(LY Peak)', group: 'SQP LY', defaultVisible: false },
  { id: 'sqp_sales_ly_peak', label: 'SQP Sales(LY Peak)', group: 'SQP LY', defaultVisible: false },
  { id: 'sqp_show_rate_ly_peak', label: 'SQP Show Rate(LY Peak)', group: 'SQP LY', defaultVisible: false },
  { id: 'sqp_impression_share_ly_peak', label: 'SQP Imp Share(LY Peak)', group: 'SQP LY', defaultVisible: false },
  { id: 'sqp_organic_rank_ly_peak', label: 'SQP Org Rank(LY Peak)', group: 'SQP LY', defaultVisible: false },
  // SQP LY Peak Amazon market
  { id: 'sqp_amazon_impressions_ly_peak', label: 'SQP Amazon Impressions(LY Peak)', group: 'SQP Amazon LY', defaultVisible: false },
  { id: 'sqp_amazon_clicks_ly_peak', label: 'SQP Amazon Clicks(LY Peak)', group: 'SQP Amazon LY', defaultVisible: false },
  { id: 'sqp_amazon_cart_adds_ly_peak', label: 'SQP Amazon Cart Adds(LY Peak)', group: 'SQP Amazon LY', defaultVisible: false },
  { id: 'sqp_amazon_orders_ly_peak', label: 'SQP Amazon Orders(LY Peak)', group: 'SQP Amazon LY', defaultVisible: false },
  { id: 'sqp_amazon_search_volume_ly_peak', label: 'SQP Amazon Volume(LY Peak)', group: 'SQP Amazon LY', defaultVisible: false },
  // PnL
  { id: 'margin_per_unit', label: 'Margin/Unit', group: 'PnL', defaultVisible: false },
  // Bid context — default-visible so user understands the recommended action
  { id: 'current_bid', label: 'Current Bid', group: 'Bid' },
  { id: 'recommended_bid', label: 'Rec. Bid', group: 'Bid' },
  { id: 'bid_change_pct', label: 'Bid Δ%', group: 'Bid' },
  // Meta
  { id: 'signal', label: 'Signal', group: 'Info' },
  { id: 'action', label: 'Action', group: 'Info' },
  { id: 'reason', label: 'Reason', group: 'Info' },
  { id: 'hero_action', label: 'Hero Action', group: 'Hero', defaultVisible: false },
  { id: 'hero_product_name', label: 'Hero Product', group: 'Hero' },
  { id: 'hero_net_roas', label: 'Hero ROAS', group: 'Hero', defaultVisible: false },
  { id: 'hero_total_orders', label: 'Hero Orders', group: 'Hero', defaultVisible: false },
  { id: 'negate_as', label: 'Negate', group: 'Hero', defaultVisible: false },
  { id: 'action_explanation', label: 'Decision Tree', group: 'Hero', defaultVisible: false },
  { id: 'hero_action_explanation', label: 'Hero Explanation', group: 'Hero', defaultVisible: false },
];

/* ─── Action-level colors & ordering ─── */
const ACTION_ORDER = ['STOP_TERM', 'STOP_TARGET', 'NEGATE_TERM', 'REDUCE_BID', 'FIX_HERO', 'SWITCH_HERO', 'KEEP_TARGET', 'INCREASE_BID', 'PROMOTE_TO_EXACT', 'START_TERM', 'MONITOR_TARGET', 'KEEP', 'MONITOR'] as const;
const ACTION_COLORS: Record<string, { bg: string; border: string; text: string }> = {
  STOP_TERM:        { bg: 'bg-red-500/12',     border: 'border-l-red-500',     text: 'text-red-400' },
  STOP_TARGET:      { bg: 'bg-red-500/12',     border: 'border-l-red-500',     text: 'text-red-400' },
  NEGATE_TERM:      { bg: 'bg-red-500/12',     border: 'border-l-red-500',     text: 'text-red-400' },
  REDUCE_BID:       { bg: 'bg-amber-500/12',   border: 'border-l-amber-500',   text: 'text-amber-400' },
  FIX_HERO:         { bg: 'bg-amber-500/12',   border: 'border-l-amber-500',   text: 'text-amber-400' },
  SWITCH_HERO:      { bg: 'bg-amber-500/12',   border: 'border-l-amber-500',   text: 'text-amber-400' },
  KEEP_TARGET:      { bg: 'bg-emerald-500/12', border: 'border-l-emerald-500', text: 'text-emerald-400' },
  INCREASE_BID:     { bg: 'bg-emerald-500/12', border: 'border-l-emerald-500', text: 'text-emerald-400' },
  PROMOTE_TO_EXACT: { bg: 'bg-blue-500/12',   border: 'border-l-blue-500',   text: 'text-blue-400' },
  START_TERM:       { bg: 'bg-purple-500/12',  border: 'border-l-purple-500', text: 'text-purple-400' },
  MONITOR_TARGET:   { bg: 'bg-zinc-500/12',    border: 'border-l-zinc-500',   text: 'text-zinc-400' },
  // Legacy fallbacks
  STOP:             { bg: 'bg-red-500/12',     border: 'border-l-red-500',     text: 'text-red-400' },
  NEGATE:           { bg: 'bg-red-500/12',     border: 'border-l-red-500',     text: 'text-red-400' },
  KEEP:             { bg: 'bg-emerald-500/12', border: 'border-l-emerald-500', text: 'text-emerald-400' },
  BOOST:            { bg: 'bg-emerald-500/12', border: 'border-l-emerald-500', text: 'text-emerald-400' },
  SCALE_UP:         { bg: 'bg-emerald-500/12', border: 'border-l-emerald-500', text: 'text-emerald-400' },
  START:            { bg: 'bg-purple-500/12',  border: 'border-l-purple-500', text: 'text-purple-400' },
  MONITOR:          { bg: 'bg-zinc-500/12',    border: 'border-l-zinc-500',   text: 'text-zinc-400' },
};
const defaultActionColor = { bg: 'bg-zinc-500/12', border: 'border-l-zinc-500', text: 'text-zinc-400' };

/* ─── Lucide icon per action ─── */
const ACTION_ICONS: Record<string, React.ComponentType<{ size?: number; className?: string }>> = {
  STOP_TERM: CircleX, STOP_TARGET: CircleX, STOP: CircleX,
  NEGATE_TERM: Ban, NEGATE: Ban,
  REDUCE_BID: TrendingDown,
  FIX_HERO: Wrench, SWITCH_HERO: ArrowRightLeft,
  KEEP_TARGET: ShieldCheck, KEEP: ShieldCheck,
  INCREASE_BID: TrendingUp, BOOST: TrendingUp, SCALE_UP: TrendingUp,
  PROMOTE_TO_EXACT: Crosshair,
  START_TERM: Sparkles, START: Sparkles,
  MONITOR_TARGET: Eye, MONITOR: Eye,
};

/* ─── Section header classification ─── */
const TERM_ACTIONS = new Set(['STOP_TERM', 'NEGATE_TERM', 'PROMOTE_TO_EXACT', 'START_TERM', 'STOP', 'NEGATE', 'START']);


/* ─── CSV Export (comprehensive) ─── */
function exportActionsToCSV(
  rows: ActionRow[],
  cdByTerm: Record<string, CoachDecisionRow>,
  predByTerm: Record<string, StrategicPrediction>,
) {
  if (!rows.length) return;

  const esc = (v: unknown): string => {
    const s = v == null ? '' : String(v);
    return s.includes(',') || s.includes('"') || s.includes('\n') ? `"${s.replace(/"/g, '""')}"` : s;
  };

  type Col = { label: string; get: (a: ActionRow, cd?: CoachDecisionRow, p?: StrategicPrediction) => unknown };
  const pClicks = (a: ActionRow) => a.spend && a.cpc ? Math.round(a.spend / a.cpc) : 0;

  const cols: Col[] = [
    // Core Info
    { label: 'Keyword',        get: a => a.search_term },
    { label: 'Product',        get: a => a.product_short_name },
    { label: 'Campaign',       get: a => a.campaign_name },
    { label: 'Portfolio',      get: a => a.portfolio_name },
    { label: 'Experiment',     get: a => a.experiment_id },
    { label: 'Strategy',       get: a => a.strategy_id },
    { label: 'Action',         get: a => a.action },
    { label: 'Signal',         get: a => a.ads_signal },
    { label: 'Priority Score', get: a => a.priority_score },
    { label: 'Hero ASIN',      get: a => a.hero_asin },
    { label: 'Is Hero Match',  get: a => a.is_hero_match },
    { label: 'Reason',         get: a => a.reason },
    { label: 'Hero Action',    get: a => a.hero_action },
    { label: 'Hero Product',   get: a => a.hero_product_name },
    { label: 'Hero ROAS',      get: a => a.hero_net_roas },
    { label: 'Hero Orders',    get: a => a.hero_total_orders },
    { label: 'Negate',         get: a => a.negate_as },
    { label: 'Action Explanation', get: a => a.action_explanation },
    { label: 'Hero Explanation',   get: a => a.hero_action_explanation },
    // Per-Campaign Ads Metrics
    { label: 'Ads Spend(4w)',        get: a => a.spend },
    { label: 'Ads Orders(4w)',       get: a => a.orders },
    { label: 'Ads Clicks(4w)',       get: a => a.clicks },
    { label: 'Ads Recent Clicks(3d)', get: a => a.ads_clicks_recent },
    { label: 'Ads Conv%(4w)',        get: a => { const c = pClicks(a); return c > 0 ? +((a.orders * 100) / c).toFixed(2) : a.conv_rate; } },
    { label: 'Ads CPC(4w)',          get: a => a.cpc },
    { label: 'Ads Net ROAS(4w)',     get: a => a.net_roas },
    { label: 'Margin/Unit',         get: a => a.margin_per_unit },
    { label: 'Impression Share',    get: a => a.impression_share },
    { label: 'Market Volume',       get: a => a.market_volume },
    // Coach Decision: Ads 4w
    { label: 'CD Ads Clicks(4w)',      get: (_a, cd) => cd?.ads_clicks_4w },
    { label: 'CD Ads Impressions(4w)', get: (_a, cd) => cd?.ads_impressions_4w },
    { label: 'CD Ads Units(4w)',       get: (_a, cd) => cd?.ads_units_4w },
    { label: 'CD Ads Sales(4w)',       get: (_a, cd) => cd?.ads_sales_4w },
    { label: 'CD Ads Net Profit(4w)',  get: (_a, cd) => cd?.ads_net_profit_4w },
    { label: 'CD Ads CPO(4w)',         get: (_a, cd) => cd?.ads_cost_per_order_4w },
    // Coach Decision: Ads LY Peak
    { label: 'CD Ads Spend(LY)',  get: (_a, cd) => cd?.ads_spend_ly_peak },
    { label: 'CD Ads Orders(LY)', get: (_a, cd) => cd?.ads_orders_ly_peak },
    { label: 'CD Ads Clicks(LY)', get: (_a, cd) => cd?.ads_clicks_ly_peak },
    { label: 'CD Ads CPC(LY)',    get: (_a, cd) => cd?.ads_cpc_ly_peak },
    { label: 'CD Ads Conv%(LY)',   get: (_a, cd) => cd?.ads_cvr_pct_ly_peak },
    { label: 'CD Ads ROAS(LY)',    get: (_a, cd) => cd?.ads_net_roas_ly_peak },
    // Coach Decision: Ads Lifetime
    { label: 'CD Ads Spend(LT)',  get: (_a, cd) => cd?.ads_spend_lifetime },
    { label: 'CD Ads Orders(LT)', get: (_a, cd) => cd?.ads_orders_lifetime },
    { label: 'CD Ads ROAS(LT)',   get: (_a, cd) => cd?.ads_net_roas_lifetime },
    // Coach Decision: SQP 4w
    { label: 'CD SQP Impressions(4w)',  get: (_a, cd) => cd?.sqp_impressions_4w },
    { label: 'CD SQP Clicks(4w)',       get: (_a, cd) => cd?.sqp_clicks_4w },
    { label: 'CD SQP Cart Adds(4w)',    get: (_a, cd) => cd?.sqp_cart_adds_4w },
    { label: 'CD SQP Orders(4w)',       get: (_a, cd) => cd?.sqp_orders_4w },
    { label: 'CD SQP Show Rate(4w)',    get: (_a, cd) => cd?.sqp_show_rate_4w },
    { label: 'CD SQP Imp Share(4w)',    get: (_a, cd) => cd?.sqp_impression_share_4w },
    { label: 'CD SQP Org Rank(4w)',     get: (_a, cd) => cd?.sqp_organic_rank_4w },
    { label: 'CD SQP Organic Units(4w)', get: (_a, cd) => cd?.sqp_organic_units_4w },
    // Coach Decision: Amazon Market 4w
    { label: 'CD Amazon Volume(4w)', get: (_a, cd) => cd?.sqp_amazon_search_volume_4w },
    { label: 'CD Amazon Impressions(4w)', get: (_a, cd) => cd?.sqp_amazon_impressions_4w },
    { label: 'CD Amazon Clicks(4w)', get: (_a, cd) => cd?.sqp_amazon_clicks_4w },
    { label: 'CD Amazon Orders(4w)', get: (_a, cd) => cd?.sqp_amazon_orders_4w },
    // Strategic Prediction
    { label: 'Predicted Net ROAS',      get: (_a, _cd, p) => p?.predicted_net_roas },
    { label: 'Prediction Confidence',   get: (_a, _cd, p) => p?.prediction_confidence != null ? +(p.prediction_confidence * 100).toFixed(0) + '%' : '' },
    { label: 'Strategic Signal',        get: (_a, _cd, p) => p?.strategic_signal },
    { label: 'Season Multiplier',       get: (_a, _cd, p) => p?.has_seasonal_data ? p.seasonality_multiplier : 'N/A' },
    { label: 'Best Season Month',       get: (_a, _cd, p) => p?.best_season_month },
    { label: 'Hero Product (Season)',    get: (_a, _cd, p) => p?.hero_product_name },
    { label: 'CPC Inflation Ratio',     get: (_a, _cd, p) => p?.cpc_inflation_ratio },
    { label: 'TOS CVR Boost',           get: (_a, _cd, p) => p?.tos_cvr_boost },
    { label: 'Organic Halo',            get: (_a, _cd, p) => p?.organic_halo_multiplier },
    { label: 'Organic Weekly Velocity',  get: (_a, _cd, p) => p?.organic_weekly_velocity },
    { label: 'LT Net ROAS',             get: (_a, _cd, p) => p?.lifetime_net_roas },
    { label: 'LT Orders',               get: (_a, _cd, p) => p?.total_orders },
    { label: 'LT Spend',                get: (_a, _cd, p) => p?.total_spend },
    { label: 'LT Days',                 get: (_a, _cd, p) => p?.days_with_data },
    // Decision Trace
    { label: 'Decision Trace', get: a => {
      if (!a.decision_trace) return '';
      return a.decision_trace.map(s => `${s.label}: ${s.value} [${s.pass ? 'YES' : 'NO'}]`).join(' | ') + ` => ${a.action}`;
    }},
  ];

  const headers = cols.map(c => c.label);
  const csvRows = rows.map(a => {
    const cd = cdByTerm[(a.search_term || '').toLowerCase()];
    const pred = predByTerm[(a.search_term || '').toLowerCase()];
    return cols.map(c => esc(c.get(a, cd, pred))).join(',');
  });

  const csv = [headers.join(','), ...csvRows].join('\n');
  const blob = new Blob(['\uFEFF' + csv], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = `actions_export_${new Date().toISOString().slice(0, 10)}.csv`;
  link.style.display = 'none';
  document.body.appendChild(link);
  link.click();
  setTimeout(() => {
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  }, 100);
}


export function ActionsPage({ data, matchAction }: { data: DashboardData; matchAction: (a: { search_term?: string; experiment_id?: string; net_roas?: number; cpc?: number; conv_rate?: number }) => { gt: GroundTruth; supported: boolean }[] }) {
  const { filters } = useFilters();
  const doQueue = useDoQueue();
  const acts = data.actions || [];
  const [typeFilter, setTypeFilter] = useState('all');
  const [stratFilter, setStratFilter] = useState('all');
  const [famFilter, setFamFilter] = useState('all');
  const [bucketFilter, setBucketFilter] = useState<string | null>(null);
  const [expandedKeys, setExpandedKeys] = useState<Set<string>>(new Set());

  const effectiveFam = filters.family || (famFilter !== 'all' ? famFilter : null);

  const types = useMemo(() => [...new Set(acts.map(a => a.action).filter(Boolean))].sort(), [acts]);
  const strategies = useMemo(() => [...new Set(acts.map(a => a.strategy_id).filter(Boolean))].sort(), [acts]);
  const fams = useMemo(() => [...new Set(acts.map(a => famFromProduct(a.product_short_name)).filter(Boolean))].sort(), [acts]);

  /* ─── Coach decisions enrichment: lookup SQP + extended Ads by search_term ─── */
  const cdByTerm = useMemo(() => {
    const map: Record<string, typeof data.coach_decisions[0]> = {};
    for (const cd of data.coach_decisions || []) {
      const key = (cd.search_term || '').toLowerCase();
      if (key && !map[key]) map[key] = cd;
    }
    return map;
  }, [data.coach_decisions]);

  /* ── Enrich actions with targeting from coach_terms ── */
  const enrichedActs = useMemo(() => {
    const ctMap: Record<string, { targeting: string | null; keyword_id: string | null; match_type: string | null; target_action: string | null; target_net_roas_8w: number | null; target_orders_8w: number | null; target_spend_8w: number | null; effective_roas: number | null; target_decision_trace: import('../types').DecisionStep[] | null; recommendation_object: 'TARGET' | 'TERM'; current_bid: number | null; recommended_bid: number | null; bid_change_pct: number | null }> = {};
    for (const ct of data.coach_terms || []) {
      const key = `${(ct.search_term || '').toLowerCase()}|${ct.campaign_id || ''}`;
      if (!ctMap[key]) ctMap[key] = {
        targeting: ct.targeting, keyword_id: ct.keyword_id, match_type: ct.match_type, target_action: ct.target_action,
        target_net_roas_8w: ct.target_net_roas_8w, target_orders_8w: ct.target_orders_8w,
        target_spend_8w: ct.target_spend_8w, effective_roas: ct.effective_roas,
        target_decision_trace: ct.target_decision_trace, recommendation_object: ct.recommendation_object,
        current_bid: ct.current_bid, recommended_bid: ct.recommended_bid, bid_change_pct: ct.bid_change_pct,
      };
    }
    return acts.map(a => {
      const key = `${(a.search_term || '').toLowerCase()}|${a.campaign_id || ''}`;
      const ct = ctMap[key];
      if (!ct) return a;
      return { ...a, targeting: ct.targeting, keyword_id: ct.keyword_id, match_type: ct.match_type, target_action: ct.target_action, target_net_roas_8w: ct.target_net_roas_8w, target_orders_8w: ct.target_orders_8w, target_spend_8w: ct.target_spend_8w, effective_roas: ct.effective_roas, target_decision_trace: ct.target_decision_trace, recommendation_object: ct.recommendation_object, current_bid: ct.current_bid, recommended_bid: ct.recommended_bid, bid_change_pct: ct.bid_change_pct };
    });
  }, [acts, data.coach_terms]);

  /* ── Strategic keyword predictions lookup ── */
  const predByTerm = useMemo(() => {
    const map: Record<string, StrategicPrediction> = {};
    for (const p of data.keyword_predictions || []) {
      const key = (p.search_term || '').toLowerCase();
      if (key && !map[key]) map[key] = p;
    }
    return map;
  }, [data.keyword_predictions]);

  const filtered = useMemo(() => {
    let f = [...enrichedActs];
    // Hide actions already uploaded to Amazon
    // Check both search_term and targeting — target actions are queued with targeting keyword as search_term
    f = f.filter(a => !doQueue.isUploaded(a.search_term, a.campaign_id)
      && !(a.targeting && doQueue.isUploaded(a.targeting, a.campaign_id)));
    if (typeFilter !== 'all') f = f.filter(a => a.action === typeFilter);
    if (stratFilter !== 'all') f = f.filter(a => a.strategy_id === stratFilter);
    if (effectiveFam) f = f.filter(a => famFromProduct(a.product_short_name) === effectiveFam);
    else if (famFilter !== 'all') f = f.filter(a => famFromProduct(a.product_short_name) === famFilter);
    if (filters.experiment) f = f.filter(a => a.experiment_id === filters.experiment);
    if (filters.keyword) f = f.filter(a => a.search_term === filters.keyword);
    if (bucketFilter) {
      const bucket = SPEND_BUCKETS.find(b => b.key === bucketFilter);
      if (bucket) f = f.filter(a => (bucket.actions as readonly string[]).includes(a.action));
    }
    f.sort((a, b) => (b.priority_score || 0) - (a.priority_score || 0));
    return f;
  }, [enrichedActs, typeFilter, stratFilter, famFilter, effectiveFam, filters.experiment, filters.keyword, bucketFilter, doQueue.isUploaded]);

  /* ── Pie chart: classify spend by bucket ── */
  const bucketSpend = useMemo(() => {
    return SPEND_BUCKETS.map(b => ({
      ...b,
      value: filtered
        .filter(a => (b.actions as readonly string[]).includes(a.action))
        .reduce((s, a) => s + (a.spend || 0), 0),
    })).filter(b => b.value > 0);
  }, [filtered]);

  const totalBucketSpend = bucketSpend.reduce((s, b) => s + b.value, 0);


  const actSort = useSort('priority_score');
  const [actionCols, setActionCols] = useMeasureSelection('actions', ACTIONS_TABLE_COLUMNS);
  const visibleActionCols = useMemo(() => ACTIONS_TABLE_COLUMNS.filter(c => actionCols.has(c.id)), [actionCols]);

  const toggleKey = (key: string) => {
    setExpandedKeys(prev => { const n = new Set(prev); n.has(key) ? n.delete(key) : n.add(key); return n; });
  };

  /* ── Tree: Portfolio → Campaign → Action → Target (bid ops) / Keyword (search-term ops) ── */
  type TreeNode = {
    key: string; label: string; level: 'portfolio' | 'campaign' | 'action' | 'target' | 'keyword';
    children: TreeNode[]; rows: ActionRow[];
    metrics: { spend: number; orders: number; count: number; targetAction?: string; targetRoas?: number; targetOrders?: number; matchType?: string; targetDecisionTrace?: import('../types').DecisionStep[] | null };
  };

  /* ── TERM TREE: Action → Family → Product → Term ── */
  const termTree = useMemo((): TreeNode[] => {
    const termRows = filtered.filter(r => {
      const a = r.action || '';
      return a.endsWith('_TERM') || a === 'PROMOTE_TO_EXACT' || a === 'STOP' || a === 'NEGATE' || a === 'START';
    });
    if (!termRows.length) return [];

    // Group by Action first
    const byAction: Record<string, ActionRow[]> = {};
    for (const r of termRows) {
      const a = r.action || 'OTHER';
      if (!byAction[a]) byAction[a] = [];
      byAction[a].push(r);
    }

    return Object.entries(byAction).sort((a, b) => {
      const ai = ACTION_ORDER.indexOf(a[0] as any);
      const bi = ACTION_ORDER.indexOf(b[0] as any);
      return (ai === -1 ? 99 : ai) - (bi === -1 ? 99 : bi);
    }).map(([actKey, actRows]) => {
      const actSpend = actRows.reduce((s, r) => s + (r.spend || 0), 0);
      const actOrders = actRows.reduce((s, r) => s + (r.orders || 0), 0);

      // Group by Family
      const byFamily: Record<string, ActionRow[]> = {};
      for (const r of actRows) {
        const fam = famFromProduct(r.product_short_name) || 'Other';
        if (!byFamily[fam]) byFamily[fam] = [];
        byFamily[fam].push(r);
      }

      const famChildren = Object.entries(byFamily).sort(([, a], [, b]) => 
        b.reduce((s, r) => s + (r.spend || 0), 0) - a.reduce((s, r) => s + (r.spend || 0), 0)
      ).map(([famKey, famRows]) => {
        const famSpend = famRows.reduce((s, r) => s + (r.spend || 0), 0);
        const famOrders = famRows.reduce((s, r) => s + (r.orders || 0), 0);

        // Group by Product within Family
        const byProduct: Record<string, ActionRow[]> = {};
        for (const r of famRows) {
          const p = r.product_short_name || 'Other';
          if (!byProduct[p]) byProduct[p] = [];
          byProduct[p].push(r);
        }

        const prodChildren = Object.entries(byProduct).map(([prodKey, prodRows]) => {
          const prodSpend = prodRows.reduce((s, r) => s + (r.spend || 0), 0);
          const prodOrders = prodRows.reduce((s, r) => s + (r.orders || 0), 0);

          // Group by search term
          const byTerm: Record<string, ActionRow[]> = {};
          for (const r of prodRows) {
            const t = r.search_term || '--';
            if (!byTerm[t]) byTerm[t] = [];
            byTerm[t].push(r);
          }

          const termChildren = Object.entries(byTerm).map(([termKey, tRows]) => {
            const termSpend = tRows.reduce((s, r) => s + (r.spend || 0), 0);
            const termOrd = tRows.reduce((s, r) => s + (r.orders || 0), 0);
            return {
              key: `term:${actKey}:${famKey}:${prodKey}:${termKey}`,
              label: termKey,
              level: 'keyword' as const,
              children: [],
              rows: tRows,
              metrics: { spend: termSpend, orders: termOrd, count: tRows.length },
            };
          }).sort((a, b) => b.metrics.spend - a.metrics.spend);

          return {
            key: `prod:${actKey}:${famKey}:${prodKey}`,
            label: prodKey,
            level: 'campaign' as const, // product level uses campaign styling
            children: termChildren,
            rows: prodRows,
            metrics: { spend: prodSpend, orders: prodOrders, count: prodRows.length },
          };
        }).sort((a, b) => b.metrics.spend - a.metrics.spend);

        return {
          key: `fam:${actKey}:${famKey}`,
          label: famKey,
          level: 'portfolio' as const, // family level uses portfolio styling
          children: prodChildren,
          rows: famRows,
          metrics: { spend: famSpend, orders: famOrders, count: famRows.length },
        };
      });

      return {
        key: `act:${actKey}`,
        label: actKey,
        level: 'action' as const,
        children: famChildren,
        rows: actRows,
        metrics: { spend: actSpend, orders: actOrders, count: actRows.length },
      };
    });
  }, [filtered]);

  /* ── TARGET TREE: Portfolio → Campaign → Action → Target (bid ops) ── */
  const targetTree = useMemo((): TreeNode[] => {
    const targetRows = filtered.filter(r => {
      const a = r.action || '';
      const isTermAction = a.endsWith('_TERM') || a === 'PROMOTE_TO_EXACT' || a === 'STOP' || a === 'NEGATE' || a === 'START';
      return !isTermAction;
    });
    if (!targetRows.length) return [];

    // Group by action
    const byAction: Record<string, ActionRow[]> = {};
    for (const a of targetRows) {
      const k = (a as any).target_action || a.action || 'OTHER';
      if (!byAction[k]) byAction[k] = [];
      byAction[k].push(a);
    }

    return Object.keys(byAction).sort((a, b) => {
      const ai = ACTION_ORDER.indexOf(a as any); const bi = ACTION_ORDER.indexOf(b as any);
      return (ai === -1 ? 99 : ai) - (bi === -1 ? 99 : bi);
    }).map(actKey => {
      const actRows = byAction[actKey];
      const actSpend = actRows.reduce((s, r) => s + (r.spend || 0), 0);
      const actOrders = actRows.reduce((s, r) => s + (r.orders || 0), 0);

      // Group by portfolio
      const byPortfolio: Record<string, ActionRow[]> = {};
      for (const r of actRows) {
        const p = r.portfolio_name || 'Unassigned';
        if (!byPortfolio[p]) byPortfolio[p] = [];
        byPortfolio[p].push(r);
      }

      const portChildren = Object.keys(byPortfolio).sort().map(portKey => {
        const portRows = byPortfolio[portKey];
        const portSpend = portRows.reduce((s, r) => s + (r.spend || 0), 0);
        const portOrders = portRows.reduce((s, r) => s + (r.orders || 0), 0);

        // Group by campaign
        const byCamp: Record<string, ActionRow[]> = {};
        for (const r of portRows) {
          const c = r.campaign_name || 'Unknown';
          if (!byCamp[c]) byCamp[c] = [];
          byCamp[c].push(r);
        }

        const campChildren = Object.entries(byCamp).map(([campKey, campRows]) => {
          const campSpend = campRows.reduce((s, r) => s + (r.spend || 0), 0);
          const campOrders = campRows.reduce((s, r) => s + (r.orders || 0), 0);

          // Group by targeting keyword
          const byTarget: Record<string, ActionRow[]> = {};
          for (const r of campRows) {
            const t = r.targeting || 'Other Terms';
            if (!byTarget[t]) byTarget[t] = [];
            byTarget[t].push(r);
          }

          const targetChildren = Object.entries(byTarget).map(([targetKey, tgtRows]) => {
            const targetSpend = tgtRows.reduce((s, r) => s + (r.spend || 0), 0);
            const targetOrd = tgtRows.reduce((s, r) => s + (r.orders || 0), 0);
            const tRoas = tgtRows[0]?.target_net_roas_8w ?? undefined;
            const tOrders = tgtRows[0]?.target_orders_8w ?? undefined;
            const tMatchType = (tgtRows[0] as any)?.match_type || '';
            const tDecisionTrace = (tgtRows[0] as any)?.target_decision_trace ?? null;

            const kwChildren: TreeNode[] = tgtRows.map(r => ({
              key: `kw:${r.search_term || ''}:${r.campaign_id || ''}`,
              label: r.search_term || '--',
              level: 'keyword' as const,
              children: [],
              rows: [r],
              metrics: { spend: r.spend || 0, orders: r.orders || 0, count: 1 },
            }));

            return {
              key: `tgt:${actKey}:${portKey}:${campKey}:${targetKey}`,
              label: targetKey,
              level: 'target' as const,
              children: kwChildren,
              rows: tgtRows,
              metrics: {
                spend: targetSpend, orders: targetOrd, count: tgtRows.length,
                targetRoas: tRoas, targetOrders: tOrders, matchType: tMatchType,
                targetDecisionTrace: tDecisionTrace,
              },
            };
          }).sort((a, b) => (b.metrics.targetRoas ?? 0) - (a.metrics.targetRoas ?? 0));

          return {
            key: `camp:${actKey}:${portKey}:${campKey}`,
            label: campKey,
            level: 'campaign' as const,
            children: targetChildren,
            rows: campRows,
            metrics: { spend: campSpend, orders: campOrders, count: campRows.length },
          };
        }).sort((a, b) => b.metrics.spend - a.metrics.spend);

        return {
          key: `port:${actKey}:${portKey}`,
          label: portKey,
          level: 'portfolio' as const,
          children: campChildren,
          rows: portRows,
          metrics: { spend: portSpend, orders: portOrders, count: portRows.length },
        };
      });

      return {
        key: `act:${actKey}`,
        label: actKey,
        level: 'action' as const,
        children: portChildren,
        rows: actRows,
        metrics: { spend: actSpend, orders: actOrders, count: actRows.length },
      };
    });
  }, [filtered]);

  /* ── Section counts ── */
  const termCount = termTree.reduce((s, n) => s + n.metrics.count, 0);
  const termSpend = termTree.reduce((s, n) => s + n.metrics.spend, 0);
  const targetCount = targetTree.reduce((s, n) => s + n.metrics.count, 0);
  const targetSpend = targetTree.reduce((s, n) => s + n.metrics.spend, 0);

  /* ── Summary counts from flat action list ── */
  const stopCount = filtered.filter(r => TERM_ACTIONS.has(r.action) && (r.action.includes('STOP') || r.action.includes('NEGATE'))).length;
  const stopSpend2 = filtered.filter(r => TERM_ACTIONS.has(r.action) && (r.action.includes('STOP') || r.action.includes('NEGATE'))).reduce((s, r) => s + (r.spend || 0), 0);
  const keepCount = filtered.filter(r => r.action === 'KEEP' || r.action === 'KEEP_TARGET' || (r as any).target_action === 'KEEP_TARGET').length;
  const growCount = filtered.filter(r => ['PROMOTE_TO_EXACT', 'INCREASE_BID'].includes(r.action) || (r as any).target_action === 'INCREASE_BID').length;
  const newCount = filtered.filter(r => r.action === 'START_TERM' || r.action === 'START').length;

  usePageSummary({
    title: 'Actions',
    breadcrumbs: [
      { label: 'Home', onClick: () => window.dispatchEvent(new CustomEvent('nav', { detail: 'home' })) },
      { label: 'Actions' },
    ],
    items: [
      { label: 'Stop', value: `${stopCount}`, color: 'red' },
      { label: 'Wasted Spend', value: fM(stopSpend2), color: 'red' },
      { label: 'Keep', value: `${keepCount}`, color: 'green' },
      { label: 'Growth', value: `${growCount}`, color: 'green' },
      { label: 'Opportunities', value: `${newCount}`, color: 'blue' },
      { label: 'Total', value: `${filtered.length}` },
    ],
  });

  if (!acts.length) return <Empty icon="⚡" message="No pending actions" hint="Actions appear when keyword data detects bid changes, negations, or opportunities." />;

  /* ── Render a tree node row ── */
  const renderNode = (node: TreeNode, depth: number, parentPath: string): React.ReactNode[] => {
    const fullKey = parentPath ? `${parentPath}\0${node.key}` : node.key;
    const isExpanded = expandedKeys.has(fullKey);
    const hasChildren = node.children.length > 0;
    const pl = depth * 20 + 12;

    if (node.level === 'keyword') {
      // Keyword leaf row → full ActionRowComponent
      const a = node.rows[0];
      if (!a) return [];
      return [
        <ActionRowComponent
          key={fullKey} action={a} cd={cdByTerm[(a.search_term || '').toLowerCase()]}
          prediction={predByTerm[(a.search_term || '').toLowerCase()]}
          expanded={isExpanded}
          onToggle={() => {
            const next = new Set(expandedKeys);
            isExpanded ? next.delete(fullKey) : next.add(fullKey);
            setExpandedKeys(next);
          }}
          matchAction={matchAction} visibleCols={visibleActionCols} indent={pl}
        />
      ];
    }

    const rows: React.ReactNode[] = [];

    if (node.level === 'portfolio') {
      // Portfolio header row
      rows.push(
        <tr key={fullKey} onClick={() => toggleKey(fullKey)}
          className="cursor-pointer transition-all hover:brightness-110 border-b border-border bg-surface/80">
          <td colSpan={visibleActionCols.length} className="px-0 py-0">
            <div className="flex items-center gap-2 text-xs font-bold px-3.5 py-2.5 border-l-[3px] border-blue-500"
              style={{ paddingLeft: pl }}>
              <span className={`transition-transform duration-200 text-[10px] ${isExpanded ? 'rotate-90' : ''}`}>▶</span>
              <span>📁</span>
              <Badge variant="muted">{node.label}</Badge>
              <span className="text-white/80 font-semibold">({node.metrics.count})</span>
              <span className="font-mono text-[10px] opacity-60 ml-1">{fM(node.metrics.spend)}</span>
              {node.metrics.orders > 0 && <span className="font-mono text-[10px] opacity-60">· {fOrd(node.metrics.orders)}</span>}
            </div>
          </td>
        </tr>
      );
    } else if (node.level === 'campaign') {
      // Campaign sub-header
      rows.push(
        <tr key={fullKey} onClick={() => toggleKey(fullKey)}
          className="cursor-pointer border-b border-border-faint hover:bg-white/[.02] transition-colors">
          <td colSpan={visibleActionCols.length} className="px-0 py-0">
            <div className="flex items-center gap-2 text-[11px] font-semibold text-subtle px-3.5 py-2"
              style={{ paddingLeft: pl }}>
              <span className={`transition-transform duration-200 text-[9px] ${isExpanded ? 'rotate-90' : ''}`}>▶</span>
              <span className="text-zinc-300 font-mono truncate max-w-[350px]" title={node.label}>{node.label}</span>
              <span className="text-faint">({node.metrics.count})</span>
              <span className="font-mono text-[10px] text-faint ml-1">{fM(node.metrics.spend)}</span>
              {node.metrics.orders > 0 && <span className="font-mono text-[10px] text-faint">· {fOrd(node.metrics.orders)}</span>}
            </div>
          </td>
        </tr>
      );
    } else if (node.level === 'target') {
      // Target keyword row — add as a single target-level queue item
      const firstRow = node.rows[0];
      const targetAction = (firstRow as any)?.target_action || firstRow?.action || 'KEEP';
      const targetCampaign = firstRow?.campaign_name || firstRow?.strategy_id || 'Other';
      const targetLabel = node.label; // the targeting keyword itself
      const allInQueue = doQueue.hasItem(targetLabel, targetAction, targetCampaign);
      const handleTargetQueue = (e: React.MouseEvent) => {
        e.stopPropagation();
        if (allInQueue) {
          const match = doQueue.items.find(p => p.search_term === targetLabel && p.action === targetAction && p.campaign === targetCampaign);
          if (match) doQueue.removeItem(match.id);
        } else {
          doQueue.addItem({
            search_term: targetLabel,
            action: targetAction,
            campaign: targetCampaign,
            campaign_id: firstRow?.campaign_id || '',
            ad_group_id: firstRow?.ad_group_id || '',
            targeting: firstRow?.targeting || targetLabel,
            keyword_id: firstRow?.keyword_id || '',
            match_type: firstRow?.match_type || '',
            target_spend_8w: firstRow?.target_spend_8w || 0,
            target_orders_8w: firstRow?.target_orders_8w || 0,
            target_net_roas_8w: firstRow?.target_net_roas_8w || 0,
            current_bid: firstRow?.current_bid ?? null,
            recommended_bid: firstRow?.recommended_bid ?? null,
            campaign_type: (firstRow as any)?.campaign_type || '',
            product: firstRow?.hero_asin || firstRow?.asin || firstRow?.product_short_name || '',
            spend: node.metrics.spend || 0,
            orders: node.metrics.orders || 0,
            cpc: firstRow?.cpc || 0,
            conv_rate: firstRow?.conv_rate || 0,
          });
        }
      };

      rows.push(
        <tr key={fullKey} onClick={() => toggleKey(fullKey)}
          className="cursor-pointer transition-all hover:bg-white/[.02] border-b border-border-faint">
          <td colSpan={visibleActionCols.length} className="px-0 py-0">
            <div className="flex items-center gap-2 text-[11px] font-semibold px-3.5 py-2"
              style={{ paddingLeft: pl }}>
              <span className={`transition-transform duration-200 text-[9px] ${isExpanded ? 'rotate-90' : ''}`}>▶</span>
              <Target size={12} className="text-zinc-400 shrink-0" />
              <span className="text-zinc-200 font-mono">{node.label}</span>
              {node.metrics.matchType && (
                <span className="text-[9px] px-1.5 py-0.5 rounded bg-zinc-700/50 text-zinc-400 font-mono uppercase">
                  {node.metrics.matchType}
                </span>
              )}
              <span className="text-white/70 font-semibold">({node.metrics.count})</span>
              <span className="font-mono text-[10px] opacity-60 ml-1">{fM(node.metrics.spend)}</span>
              {/* Bid pill: current → recommended */}
              {(() => {
                const firstRow = node.rows?.[0];
                const curBid = (firstRow as any)?.current_bid;
                const recBid = (firstRow as any)?.recommended_bid;
                const bidPct = (firstRow as any)?.bid_change_pct;
                if (curBid && recBid && curBid !== recBid) {
                  const isUp = recBid > curBid;
                  return (
                    <span className={`flex items-center gap-1 ml-1 font-mono text-[10px] px-1.5 py-0.5 rounded-full border ${
                      isUp ? 'bg-emerald-500/10 border-emerald-500/25 text-emerald-400' : 'bg-red-500/10 border-red-500/25 text-red-400'
                    }`}>
                      ${curBid.toFixed(2)} → ${recBid.toFixed(2)}
                      {bidPct != null && <span className="opacity-70">({isUp ? '+' : ''}{bidPct.toFixed(0)}%)</span>}
                    </span>
                  );
                }
                return null;
              })()}
              {node.metrics.targetRoas != null && <span className={`font-mono text-[10px] ml-1 ${node.metrics.targetRoas >= 1 ? 'text-emerald-400/70' : 'text-amber-400/70'}`}>ROAS {node.metrics.targetRoas.toFixed(2)}</span>}
              {node.metrics.targetOrders != null && node.metrics.targetOrders > 0 && <span className="font-mono text-[10px] opacity-60">· {node.metrics.targetOrders} ord</span>}
              {/* Decision trace steps */}
              {node.metrics.targetDecisionTrace && node.metrics.targetDecisionTrace.length > 0 && (
                <span className="flex items-center gap-1 ml-2">
                  {node.metrics.targetDecisionTrace.map(step => (
                    <span key={step.id}
                      className={`text-[9px] px-1.5 py-0.5 rounded font-mono ${
                        step.pass
                          ? 'bg-emerald-500/10 text-emerald-400/80 border border-emerald-500/20'
                          : 'bg-red-500/10 text-red-400/80 border border-red-500/20'
                      }`}
                      title={`${step.label}: ${step.value} (${step.rule}) → ${step.pass ? 'PASS' : 'FAIL'}`}
                    >
                      {step.pass ? '✓' : '✗'} {step.label.replace('Target ', '').replace(' 8w', '')}: {step.value}
                    </span>
                  ))}
                </span>
              )}
              <div className="flex-1" />
              <div className="flex items-center gap-3">
                {(() => {
                  const tr = node.rows?.[0];
                  const actionStr = (tr as any)?.target_action || tr?.action;
                  return actionStr ? <ActionBadge action={actionStr} /> : null;
                })()}
                <button
                  onClick={handleTargetQueue}
                  className={`w-6 h-6 rounded-full flex items-center justify-center transition-all shrink-0 ${
                    allInQueue
                      ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/40'
                      : 'bg-white/5 text-zinc-400 border border-zinc-600 hover:border-blue-500/50 hover:text-blue-400 hover:bg-blue-500/10'
                  }`}
                  title={allInQueue ? 'Remove target from queue' : 'Add target to DO queue'}
                >
                  {allInQueue ? <Check size={12} /> : <Plus size={12} />}
                </button>
              </div>
            </div>
          </td>
        </tr>
      );
    } else if (node.level === 'action') {
      // Action banner row
      const ac = ACTION_COLORS[node.label] || defaultActionColor;
      const ActionIcon = ACTION_ICONS[node.label] || Eye;
      const criteria = ACTION_META[node.label]?.criteria;
      rows.push(
        <tr key={fullKey} onClick={() => toggleKey(fullKey)}
          className={`cursor-pointer transition-all hover:brightness-110 border-b border-border ${ac.bg}`}>
          <td colSpan={visibleActionCols.length} className="px-0 py-0">
            <div className={`flex items-center gap-2 text-xs font-bold px-3.5 py-2 border-l-[3px] ${ac.border}`}
              style={{ paddingLeft: pl }}>
              <span className={`transition-transform duration-200 text-[10px] ${isExpanded ? 'rotate-90' : ''}`}>▶</span>
              <ActionIcon size={13} className={`shrink-0 ${ac.text}`} />
              <ActionBadge action={node.label} />
              <span className="text-white/80 font-semibold">({node.metrics.count})</span>
              <span className="font-mono text-[10px] opacity-60 ml-1">{fM(node.metrics.spend)}</span>
              {node.metrics.orders > 0 && <span className="font-mono text-[10px] opacity-60">· {fOrd(node.metrics.orders)}</span>}
              {criteria && <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-inset text-muted font-normal ml-auto truncate max-w-[300px]" title={criteria}>{criteria}</span>}
            </div>
          </td>
        </tr>
      );
    }

    // Render children if expanded
    if (isExpanded && hasChildren) {
      for (const child of node.children) {
        rows.push(...renderNode(child, depth + 1, fullKey));
      }
    }

    return rows;
  };

  return (
    <div className="animate-in">
      <PageHeader title="Detailed Actions" subtitle="Every action justified by measures" />

      {/* ── Filter bar ── */}
      <div className="flex gap-2 items-center flex-wrap p-2.5 bg-surface/50 backdrop-blur border border-border rounded-xl mb-3.5">
        <label className="text-[10px] text-subtle uppercase tracking-wider font-semibold">Action</label>
        <select value={typeFilter} onChange={e => setTypeFilter(e.target.value)} className="bg-[#09090b] border border-border text-white px-2.5 py-1.5 rounded-lg text-[11px] focus:outline-none focus:border-blue-500">
          <option value="all">All</option>
          {types.map(t => <option key={t} value={t}>{t}</option>)}
        </select>
        <label className="text-[10px] text-subtle uppercase tracking-wider font-semibold ml-2">Strategy</label>
        <select value={stratFilter} onChange={e => setStratFilter(e.target.value)} className="bg-[#09090b] border border-border text-white px-2.5 py-1.5 rounded-lg text-[11px] focus:outline-none focus:border-blue-500">
          <option value="all">All</option>
          {strategies.map(s => <option key={s!} value={s!}>{s}</option>)}
        </select>
        <label className="text-[10px] text-subtle uppercase tracking-wider font-semibold ml-2">Family</label>
        <select value={famFilter} onChange={e => setFamFilter(e.target.value)} className="bg-[#09090b] border border-border text-white px-2.5 py-1.5 rounded-lg text-[11px] focus:outline-none focus:border-blue-500">
          <option value="all">All</option>
          {fams.map(f => <option key={f!} value={f!}>{f}</option>)}
        </select>
        {bucketFilter && (
          <button
            onClick={() => setBucketFilter(null)}
            className="flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-[11px] font-semibold bg-blue-500/15 text-blue-400 border border-blue-500/30 hover:bg-blue-500/25 transition-colors"
          >
            {SPEND_BUCKETS.find(b => b.key === bucketFilter)?.label || bucketFilter}
            <span className="text-blue-300/60 ml-0.5">×</span>
          </button>
        )}
        <div className="ml-auto">
          <button
            onClick={() => exportActionsToCSV(filtered, cdByTerm, predByTerm)}
            className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-[11px] font-semibold text-subtle border border-border hover:border-border-strong hover:text-white hover:bg-white/[.04] transition-all"
          >
            <Download size={12} />
            Export
          </button>
        </div>
      </div>

      {/* ── Summary badges ── */}
      <div className="flex gap-2 flex-wrap text-xs mb-3.5">
        <Badge variant="red">{stopCount} stop · {fM(stopSpend2)}</Badge>
        <Badge variant="green">{keepCount} keep</Badge>
        <Badge variant="green">{growCount} growth</Badge>
        <Badge variant="blue">{newCount} opportunities</Badge>
        <Badge variant="muted">{filtered.length} total</Badge>
      </div>

      {/* ── Ads Spend Allocation: Pie + Family Breakdown ── */}
      {bucketSpend.length > 0 && (() => {
        const famTotalSpend = (() => {
          const byFam: Record<string, number> = {};
          const adsRows = data.ads_7d || [];
          for (const r of adsRows) {
            if (r.row_type !== 'campaign') continue;
            const fam = famFromProduct(r.product_short_name || r.parent_name || null);
            if (fam) byFam[fam] = (byFam[fam] || 0) + (r.spend || 0);
          }
          return Object.entries(byFam)
            .map(([family, total]) => ({ family, total }))
            .filter(f => f.total > 0)
            .sort((a, b) => b.total - a.total);
        })();
        // Per-family bucket breakdown (from action rows)
        const famBuckets = (() => {
          const families = [...new Set([...famTotalSpend.map(f => f.family), ...filtered.map(a => famFromProduct(a.product_short_name)).filter(Boolean)])] as string[];
          return families.map(fam => {
            const famActions = filtered.filter(a => famFromProduct(a.product_short_name) === fam);
            const buckets = SPEND_BUCKETS.map(b => ({
              key: b.key,
              label: b.label,
              color: b.color,
              value: famActions
                .filter(a => (b.actions as readonly string[]).includes(a.action))
                .reduce((s, a) => s + (a.spend || 0), 0),
            }));
            const totalFromBuckets = buckets.reduce((s, b) => s + b.value, 0);
            const totalFromAds = famTotalSpend.find(f => f.family === fam)?.total || totalFromBuckets;
            return { family: fam, buckets: buckets.filter(b => b.value > 0), total: totalFromAds, bucketTotal: totalFromBuckets };
          }).filter(f => f.total > 0).sort((a, b) => b.total - a.total);
        })();
        const maxFamSpend = Math.max(...famBuckets.map(f => f.total), 1);

        return (
          <div className="border border-border rounded-xl bg-card p-4 mb-4 flex gap-6 flex-wrap">
            {/* Left: Pie Chart */}
            <div className="flex items-center gap-5 shrink-0">
              <div>
                <div className="text-[11px] font-semibold text-subtle uppercase tracking-wider mb-1">Ads Spend Allocation</div>
                <div className="text-[22px] font-mono font-bold">{fM(totalBucketSpend)}</div>
              </div>
              <div className="w-[140px] h-[140px]">
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie data={bucketSpend} dataKey="value" nameKey="label" cx="50%" cy="50%" innerRadius={36} outerRadius={62} paddingAngle={2} stroke="none" style={{ cursor: 'pointer' }}>
                      {bucketSpend.map((b, i) => (
                        <Cell
                          key={i}
                          fill={b.color}
                          opacity={bucketFilter && bucketFilter !== b.key ? 0.3 : 1}
                          stroke={bucketFilter === b.key ? '#fff' : 'none'}
                          strokeWidth={bucketFilter === b.key ? 2 : 0}
                          style={{ cursor: 'pointer', transition: 'opacity 0.2s' }}
                          onClick={() => setBucketFilter(prev => prev === b.key ? null : b.key)}
                        />
                      ))}
                    </Pie>
                    <Tooltip
                      formatter={(v: unknown) => fM(Number(v) || 0)}
                      contentStyle={{ background: '#16161a', border: '1px solid rgba(63,63,70,0.45)', borderRadius: 8, fontSize: 11 }}
                      itemStyle={{ color: '#fafafa' }}
                    />
                  </PieChart>
                </ResponsiveContainer>
              </div>
              <div className="flex flex-col gap-1.5">
                {bucketSpend.map(b => (
                  <div
                    key={b.key}
                    className={`flex items-center gap-2 text-[11px] cursor-pointer rounded-md px-1.5 py-0.5 -mx-1.5 transition-all duration-200 hover:bg-white/[.04] ${bucketFilter === b.key ? 'bg-white/[.06] ring-1 ring-white/10' : ''} ${bucketFilter && bucketFilter !== b.key ? 'opacity-40' : ''}`}
                    onClick={() => setBucketFilter(prev => prev === b.key ? null : b.key)}
                  >
                    <span className="w-2.5 h-2.5 rounded-full shrink-0" style={{ background: b.color }} />
                    <span className="text-subtle font-medium">{b.label}</span>
                    <span className="font-mono font-semibold ml-auto">{fM(b.value)}</span>
                    <span className="text-faint font-mono w-10 text-right">{totalBucketSpend ? (b.value / totalBucketSpend * 100).toFixed(0) : 0}%</span>
                  </div>
                ))}
              </div>
            </div>

            {/* Right: Family Stacked Bar Chart */}
            {famBuckets.length > 0 && (
              <div className="flex-1 min-w-[280px] border-l border-border pl-5">
                <div className="text-[11px] font-semibold text-subtle uppercase tracking-wider mb-3">Per Family Breakdown</div>
                <div className="space-y-2.5">
                  {famBuckets.map(f => (
                    <div
                      key={f.family}
                      className={`cursor-pointer rounded-lg px-1.5 py-1 -mx-1.5 transition-all duration-200 hover:bg-white/[.04] ${famFilter === f.family ? 'bg-white/[.06] ring-1 ring-white/10' : ''}`}
                      onClick={() => setFamFilter(prev => prev === f.family ? 'all' : f.family)}
                    >
                      <div className="flex items-center justify-between mb-1">
                        <span className="text-[11px] font-semibold">{f.family}</span>
                        <span className="text-[10px] font-mono text-faint">{fM(f.total)}</span>
                      </div>
                      <div className="flex h-5 rounded-md overflow-hidden" title={[...f.buckets.map(b => `${b.label}: ${fM(b.value)}`), `Total: ${fM(f.total)}`].join(' · ')}>
                        {f.buckets.map(b => (
                          <div
                            key={b.key}
                            className="relative group transition-all duration-200 hover:brightness-125 cursor-pointer"
                            style={{ width: `${(b.value / maxFamSpend) * 100}%`, background: b.color }}
                            onClick={(e) => {
                              e.stopPropagation();
                              const clearing = famFilter === f.family && bucketFilter === b.key;
                              setFamFilter(clearing ? 'all' : f.family);
                              setBucketFilter(clearing ? null : b.key);
                            }}
                          >
                            {(b.value / f.total) >= 0.12 && (
                              <span className="absolute inset-0 flex items-center justify-center text-[8px] font-mono font-bold text-white/80">
                                {fM(b.value)}
                              </span>
                            )}
                          </div>
                        ))}

                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        );
      })()}

      {/* ── ⚡ Hot Signals — Last 3 Days ── */}
      {(() => {
        // Apply same filters as main actions table
        let hs = (data.hot_signals || []).filter(s => {
          if (effectiveFam && famFromProduct(s.product_short_name) !== effectiveFam) return false;
          if (filters.experiment && s.experiment_id !== filters.experiment) return false;
          if (filters.keyword && s.search_term !== filters.keyword) return false;
          if (stratFilter !== 'all' && s.strategy_id !== stratFilter) return false;
          return true;
        });
        if (!hs.length) return null;

        const urgentStops = hs.filter(s => s.hot_signal === 'URGENT_STOP');
        const hotWinners = hs.filter(s => s.hot_signal === 'HOT_WINNER');
        const rapidDeclines = hs.filter(s => s.hot_signal === 'RAPID_DECLINE');

        const SIGNAL_META: Record<string, { icon: React.ReactNode; color: string; bgColor: string; borderColor: string; label: string; doAction: string }> = {
          URGENT_STOP: { icon: <CircleX size={14} />, color: 'text-red-400', bgColor: 'bg-red-500/8', borderColor: 'border-red-500/25', label: 'Urgent Stop', doAction: 'STOP' },
          HOT_WINNER: { icon: <TrendingUp size={14} />, color: 'text-emerald-400', bgColor: 'bg-emerald-500/8', borderColor: 'border-emerald-500/25', label: 'Hot Winner', doAction: 'INCREASE_BID' },
          RAPID_DECLINE: { icon: <TrendingDown size={14} />, color: 'text-amber-400', bgColor: 'bg-amber-500/8', borderColor: 'border-amber-500/25', label: 'Rapid Decline', doAction: 'REDUCE_BID' },
        };

        return (
          <div className="border border-border rounded-xl bg-card overflow-hidden mb-4">
            <div className="flex items-center gap-3 px-4 py-2.5 border-b border-border bg-surface/50">
              <Sparkles size={14} className="text-amber-400" />
              <span className="text-[11px] font-bold uppercase tracking-wider text-white/90">⚡ Hot Signals — Last 3 Days</span>
              <span className="text-[10px] font-mono text-muted">
                {urgentStops.length > 0 && <span className="text-red-400 mr-2">{urgentStops.length} urgent</span>}
                {hotWinners.length > 0 && <span className="text-emerald-400 mr-2">{hotWinners.length} winners</span>}
                {rapidDeclines.length > 0 && <span className="text-amber-400">{rapidDeclines.length} declining</span>}
              </span>
              <span className="text-[9px] text-subtle ml-auto">Ads-only · strong signals only</span>
            </div>
            <div className="p-3 grid gap-2">
              {[...urgentStops, ...rapidDeclines, ...hotWinners].map((s, i) => {
                const meta = SIGNAL_META[s.hot_signal];
                const isQueued = doQueue.isUploaded(s.search_term, s.campaign_id);
                return (
                  <div key={`hs-${i}`} className={`flex items-start gap-3 p-3 rounded-lg border ${meta.borderColor} ${meta.bgColor} transition-all hover:brightness-110`}>
                    <div className={`mt-0.5 ${meta.color}`}>{meta.icon}</div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-1">
                        <span className={`text-[10px] font-bold uppercase tracking-wider ${meta.color}`}>{meta.label}</span>
                        {s.coach_8w_action && s.hot_signal === 'URGENT_STOP' && (
                          <span className="text-[9px] font-semibold px-1.5 py-0.5 rounded bg-red-500/20 text-red-300 border border-red-500/30">
                            ⚠️ Overrides: {s.coach_8w_action}
                          </span>
                        )}
                      </div>
                      <div className="text-[12px] text-white font-semibold truncate">{s.search_term}</div>
                      <div className="text-[10px] text-subtle mt-0.5 truncate">
                        Campaign: {s.campaign_name} · {s.product_short_name}
                      </div>
                      <div className="text-[10px] text-faint mt-1">{s.hot_signal_reason}</div>
                    </div>
                    <div className="flex gap-4 text-right shrink-0 items-start">
                      <div>
                        <div className="text-[9px] text-subtle uppercase">Spend</div>
                        <div className="text-[12px] font-mono text-white">{fM(s.spend_3d)}</div>
                      </div>
                      <div>
                        <div className="text-[9px] text-subtle uppercase">Clicks</div>
                        <div className="text-[12px] font-mono text-white">{s.clicks_3d}</div>
                      </div>
                      <div>
                        <div className="text-[9px] text-subtle uppercase">Orders</div>
                        <div className={`text-[12px] font-mono ${s.orders_3d > 0 ? 'text-emerald-400' : 'text-red-400'}`}>{s.orders_3d}</div>
                      </div>
                      {s.ads_roas_3d != null && s.ads_roas_3d > 0 && (
                        <div>
                          <div className="text-[9px] text-subtle uppercase">ROAS 3d</div>
                          <div className="text-[12px] font-mono text-white">{s.ads_roas_3d.toFixed(1)}x</div>
                        </div>
                      )}
                      {s.coach_8w_roas != null && s.coach_8w_roas > 0 && (
                        <div>
                          <div className="text-[9px] text-subtle uppercase">ROAS 8w</div>
                          <div className="text-[12px] font-mono text-faint">{s.coach_8w_roas.toFixed(1)}x</div>
                        </div>
                      )}
                      {s.sqp_search_volume_4w > 0 && (
                        <div>
                          <div className="text-[9px] text-subtle uppercase">SQP VOL 4w</div>
                          <div className="text-[12px] font-mono text-blue-300">{fmt(s.sqp_search_volume_4w)}</div>
                        </div>
                      )}
                      {s.sqp_organic_rank != null && s.sqp_organic_rank > 0 && (
                        <div>
                          <div className="text-[9px] text-subtle uppercase">Org Rank</div>
                          <div className={`text-[12px] font-mono ${s.sqp_organic_rank <= 5 ? 'text-emerald-400' : 'text-faint'}`}>#{s.sqp_organic_rank}</div>
                        </div>
                      )}
                      <div className="flex items-center gap-1.5 mt-1">
                        <button
                          onClick={() => {
                            if (isQueued) return;
                            doQueue.addItem({
                              search_term: s.search_term,
                              action: meta.doAction,
                              campaign: s.campaign_name,
                              campaign_id: s.campaign_id,
                              ad_group_id: s.ad_group_id,
                              targeting: s.search_term,
                              keyword_id: '',
                              match_type: '',
                              target_spend_8w: 0,
                              target_orders_8w: 0,
                              target_net_roas_8w: s.coach_8w_roas ?? 0,
                              current_bid: null,
                              recommended_bid: null,
                              campaign_type: s.campaign_type,
                              product: s.asin || s.product_short_name || '',
                              spend: s.spend_3d,
                              orders: s.orders_3d,
                              cpc: s.cpc_3d ?? 0,
                              conv_rate: s.cvr_3d ?? 0,
                            });
                          }}
                          className={`w-6 h-6 rounded-full flex items-center justify-center transition-all shrink-0 ${
                            isQueued
                              ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/40 cursor-default'
                              : 'bg-white/5 text-zinc-400 border border-zinc-600 hover:border-blue-500/50 hover:text-blue-400 hover:bg-blue-500/10 cursor-pointer'
                          }`}
                          title={isQueued ? 'Already in DO queue' : `Add "${meta.doAction}" to DO queue`}
                        >
                          {isQueued ? <Check size={12} /> : <Plus size={12} />}
                        </button>
                        <span className={`flex items-center gap-1 px-2 py-1 rounded-lg text-[10px] font-bold uppercase tracking-wider ${meta.bgColor} ${meta.color} border ${meta.borderColor}`}>
                          {ACTION_ICONS[meta.doAction] ? React.createElement(ACTION_ICONS[meta.doAction], { size: 11 }) : meta.icon}
                          {meta.doAction.replace(/_/g, ' ')}
                        </span>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        );
      })()}

      {/* ── Hierarchical Action Tree ── */}
      {/* ═══ TERM ACTIONS SECTION ═══ */}
      {termTree.length > 0 && (
        <div className="border border-border rounded-xl bg-card overflow-hidden mb-4">
          <div className="flex items-center gap-3 px-4 py-2.5 border-b border-border bg-surface/50">
            <Ban size={14} className="text-red-400" />
            <span className="text-[11px] font-bold uppercase tracking-wider text-white/90">Term Actions</span>
            <span className="text-[10px] font-mono text-muted">{termCount} terms · {fM(termSpend)}</span>
            <span className="text-[9px] text-subtle ml-auto">What to do with each search term</span>
            <div className="ml-2">
              <MeasureSelector tableId="actions" measures={ACTIONS_TABLE_COLUMNS} selected={actionCols} onSelectedChange={setActionCols} />
            </div>
          </div>
          <table className="w-full border-collapse text-xs">
            <thead>
              <tr>
                {visibleActionCols.map(c => (
                  ['signal', 'action', 'experiment_id', 'strategy_id'].includes(c.id) ? (
                    <Th key={c.id}>{c.label}</Th>
                  ) : (
                    <SortTh key={c.id} k={c.id} sort={actSort.sort} toggle={actSort.toggle} right={!['search_term', 'product_short_name'].includes(c.id)} tip={c.tip}>{c.label}</SortTh>
                  )
                ))}
              </tr>
            </thead>
            <tbody>
              {termTree.flatMap(node => renderNode(node, 0, ''))}
            </tbody>
          </table>
        </div>
      )}

      {/* ═══ TARGET ACTIONS SECTION ═══ */}
      {targetTree.length > 0 && (
        <div className="border border-border rounded-xl bg-card overflow-hidden">
          <div className="flex items-center gap-3 px-4 py-2.5 border-b border-border bg-surface/50">
            <Target size={14} className="text-emerald-400" />
            <span className="text-[11px] font-bold uppercase tracking-wider text-white/90">Target Actions</span>
            <span className="text-[10px] font-mono text-muted">{targetCount} targets · {fM(targetSpend)}</span>
            <span className="text-[9px] text-subtle ml-auto">Bid changes per campaign × keyword</span>
            <div className="ml-2">
              <MeasureSelector tableId="actions" measures={ACTIONS_TABLE_COLUMNS} selected={actionCols} onSelectedChange={setActionCols} />
            </div>
          </div>
          <table className="w-full border-collapse text-xs">
            <thead>
              <tr>
                {visibleActionCols.map(c => (
                  ['signal', 'action', 'experiment_id', 'strategy_id'].includes(c.id) ? (
                    <Th key={c.id}>{c.label}</Th>
                  ) : (
                    <SortTh key={c.id} k={c.id} sort={actSort.sort} toggle={actSort.toggle} right={!['search_term', 'product_short_name'].includes(c.id)} tip={c.tip}>{c.label}</SortTh>
                  )
                ))}
              </tr>
            </thead>
            <tbody>
              {targetTree.flatMap(node => renderNode(node, 0, ''))}
            </tbody>
          </table>
        </div>
      )}

      {/* ═══ PHRASE NEGATIVES SECTION ═══ */}
      {(data.coach_phrase_negatives?.length ?? 0) > 0 && (() => {
        const phrases = data.coach_phrase_negatives!;
        const safeCount = phrases.filter(p => p.action === 'NEGATE_PHRASE').length;
        const seasonalCount = phrases.filter(p => p.action === 'PROMOTE_TO_PEAK_PHRASE').length;

        // Build set of queued phrase-campaign combos for cascade logic
        const queuedPhrases = new Set(
          doQueue.items
            .filter(q => q.action === 'NEGATE_PHRASE' || q.action === 'PROMOTE_TO_PEAK_PHRASE')
            .map(q => `${q.campaign_id}::${q.search_term}`)
        );

        // Cascade: check if a phrase is "covered" by a shorter queued phrase in the same campaign
        const isCoveredByCascade = (phrase: string, campaignId: string): boolean => {
          for (const key of queuedPhrases) {
            const [qCampId, qPhrase] = key.split('::');
            if (qCampId === campaignId && qPhrase !== phrase && phrase.includes(qPhrase)) {
              return true; // this phrase contains an already-queued shorter phrase
            }
          }
          return false;
        };

        // Build hierarchy: Action → Gram Size → Phrases
        const byAction: Record<string, typeof phrases> = {};
        for (const p of phrases) {
          const act = p.action || 'OTHER';
          if (!byAction[act]) byAction[act] = [];
          byAction[act].push(p);
        }

        const phraseActionOrder = ['NEGATE_PHRASE', 'PROMOTE_TO_PEAK_PHRASE'];
        const gramLabels: Record<number, string> = { 1: '1-gram (single words)', 2: '2-gram (word pairs)', 3: '3-gram (word triplets)' };

        return (
        <div className="border border-border rounded-xl bg-card overflow-hidden">
          <div className="flex items-center gap-3 px-4 py-2.5 border-b border-border bg-surface/50">
            <Ban size={14} className="text-red-400" />
            <span className="text-[11px] font-bold uppercase tracking-wider text-white/90">Phrase Negatives</span>
            <span className="text-[10px] font-mono text-muted">
              {safeCount > 0 && <><span className="text-red-400">{safeCount} negate</span> · </>}
              {seasonalCount > 0 && <><span className="text-purple-400">{seasonalCount} peak promote</span> · </>}
              {fM(phrases.reduce((s, p) => s + p.phrase_spend_8w, 0))} spend(8w)
            </span>
            <span className="text-[9px] text-subtle ml-auto">N-gram analysis · 1-year profitability check applied</span>
          </div>

          <div className="divide-y divide-border-faint">
            {phraseActionOrder.filter(a => byAction[a]?.length).map(actionKey => {
              const actionPhrases = byAction[actionKey];
              const isNeg = actionKey === 'NEGATE_PHRASE';
              const totalSpend = actionPhrases.reduce((s, p) => s + p.phrase_spend_8w, 0);
              const actionExpKey = `phrase-act:${actionKey}`;
              const isActionExpanded = expandedKeys.has(actionExpKey);

              // Group by ngram_size
              const byGram: Record<number, typeof phrases> = {};
              for (const p of actionPhrases) {
                const g = p.ngram_size || 2;
                if (!byGram[g]) byGram[g] = [];
                byGram[g].push(p);
              }

              const ac = ACTION_COLORS[actionKey] || defaultActionColor;
              const ActionIcon = ACTION_ICONS[actionKey] || (isNeg ? Ban : Eye);

              return (
                <div key={actionKey}>
                  {/* ── Action banner ── */}
                  <div
                    onClick={() => { const n = new Set(expandedKeys); isActionExpanded ? n.delete(actionExpKey) : n.add(actionExpKey); setExpandedKeys(n); }}
                    className={`flex items-center gap-2 px-4 py-2.5 cursor-pointer transition-all hover:brightness-110 ${ac.bg} border-l-[3px] ${ac.border}`}
                  >
                    <span className={`transition-transform duration-200 text-[10px] ${isActionExpanded ? 'rotate-90' : ''}`}>▶</span>
                    <ActionIcon size={13} className={`shrink-0 ${ac.text}`} />
                    <ActionBadge action={actionKey} />
                    <span className="text-white/80 font-semibold text-xs">({actionPhrases.length})</span>
                    <span className="font-mono text-[10px] opacity-60 ml-1">{fM(totalSpend)}</span>
                    {ACTION_META[actionKey]?.criteria && <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-inset text-muted font-normal ml-auto truncate max-w-[300px]" title={ACTION_META[actionKey].criteria}>{ACTION_META[actionKey].criteria}</span>}
                  </div>

                  {/* ── Gram buckets under this action ── */}
                  {isActionExpanded && [1, 2, 3].filter(g => byGram[g]?.length).map(gramSize => {
                    const gramPhrases = byGram[gramSize];
                    const gramExpKey = `phrase-gram:${actionKey}:${gramSize}`;
                    const isGramExpanded = expandedKeys.has(gramExpKey);
                    const gramSpend = gramPhrases.reduce((s, p) => s + p.phrase_spend_8w, 0);

                    return (
                      <div key={gramExpKey}>
                        {/* Gram bucket row */}
                        <div
                          onClick={() => { const n = new Set(expandedKeys); isGramExpanded ? n.delete(gramExpKey) : n.add(gramExpKey); setExpandedKeys(n); }}
                          className="flex items-center gap-2 pl-10 pr-4 py-2 cursor-pointer hover:bg-white/[.02] transition-colors border-t border-border-faint"
                        >
                          <span className={`transition-transform duration-200 text-[9px] ${isGramExpanded ? 'rotate-90' : ''}`}>▶</span>
                          <span className="text-zinc-300 font-semibold text-[11px]">{gramLabels[gramSize] || `${gramSize}-gram`}</span>
                          <span className="text-faint text-[11px]">({gramPhrases.length})</span>
                          <span className="font-mono text-[10px] text-faint ml-1">{fM(gramSpend)}</span>
                        </div>

                        {/* Phrase rows under this gram bucket */}
                        {isGramExpanded && (
                          <table className="w-full border-collapse text-xs">
                            <thead>
                              <tr>
                                <th className="pl-16 pr-3 py-1 text-left text-[9px] font-semibold text-muted uppercase tracking-wider">Phrase</th>
                                <th className="px-3 py-1 text-left text-[9px] font-semibold text-muted uppercase tracking-wider">Campaign</th>
                                <th className="px-3 py-1 text-right text-[9px] font-semibold text-muted uppercase tracking-wider">Terms</th>
                                <th className="px-3 py-1 text-right text-[9px] font-semibold text-muted uppercase tracking-wider">Spend(8w)</th>
                                <th className="px-3 py-1 text-right text-[9px] font-semibold text-muted uppercase tracking-wider">Clicks(8w)</th>
                                <th className="px-3 py-1 text-right text-[9px] font-semibold text-muted uppercase tracking-wider">Ord(8w)</th>
                                <th className="px-3 py-1 text-right text-[9px] font-semibold text-muted uppercase tracking-wider">ROAS(1y)</th>
                                <th className="px-3 py-1 w-8" />
                              </tr>
                            </thead>
                            <tbody>
                              {gramPhrases
                                .sort((a, b) => b.phrase_spend_8w - a.phrase_spend_8w)
                                .map((p, i) => {
                                  const inQ = queuedPhrases.has(`${p.campaign_id}::${p.phrase}`);
                                  const cascaded = !inQ && isCoveredByCascade(p.phrase, p.campaign_id);
                                  const isPeak = p.action === 'PROMOTE_TO_PEAK_PHRASE';

                                  if (cascaded) return null; // hide rows covered by a shorter queued phrase

                                  return (
                                    <tr
                                      key={`${gramExpKey}:${i}`}
                                      className={`border-t transition-colors hover:bg-surface/30 ${
                                        isNeg ? 'border-red-500/20' : 'border-purple-500/20 bg-purple-500/[0.03]'
                                      }`}
                                      title={p.reason}
                                    >
                                      <td className="pl-16 pr-3 py-2">
                                        <strong className={isNeg ? 'text-blue-400' : 'text-purple-300'}>"{p.phrase}"</strong>
                                        {isPeak && <div className="text-[9px] text-purple-400/80 mt-0.5">Theme: {p.seasonal_theme}</div>}
                                      </td>
                                      <td className="px-3 py-2 text-[10px] text-zinc-400 font-mono truncate max-w-[220px]" title={p.campaign_name}>{p.campaign_name}</td>
                                      <td className="px-3 py-2 text-right font-mono text-[11px]">{fmt(p.phrase_term_count)}</td>
                                      <td className="px-3 py-2 text-right font-mono text-[11px] font-medium text-red-400">{fM(p.phrase_spend_8w)}</td>
                                      <td className="px-3 py-2 text-right font-mono text-[11px]">{fmt(p.phrase_clicks_8w)}</td>
                                      <td className="px-3 py-2 text-right font-mono text-[11px]">0</td>
                                      <td className="px-3 py-2 text-right font-mono text-[11px]">
                                        {p.phrase_roas_1y > 0 ? (
                                          <span className={!isNeg ? 'text-purple-400 font-medium' : 'text-zinc-400'} title={`1-year Sales: ${fM(p.phrase_sales_1y)} / Spend: ${fM(p.phrase_spend_1y)}\nTop 3 months: ${Math.round(p.top3_months_pct * 100)}% of orders`}>
                                            {p.phrase_roas_1y.toFixed(2)}x
                                          </span>
                                        ) : (
                                          <span className="text-zinc-500">0.00x</span>
                                        )}
                                      </td>
                                      <td className="px-3 py-2">
                                        <button
                                          className={`p-1 rounded transition-colors ${inQ ? 'text-emerald-400' : 'text-zinc-500 hover:text-white'}`}
                                          onClick={() => {
                                            if (inQ) return;
                                            doQueue.addItem({
                                              search_term: p.phrase,
                                              action: p.action,
                                              campaign: p.campaign_name,
                                              campaign_id: p.campaign_id,
                                              ad_group_id: '',
                                              targeting: p.phrase,
                                              keyword_id: '',
                                              match_type: 'PHRASE',
                                              target_spend_8w: p.phrase_spend_8w,
                                              target_orders_8w: p.phrase_orders_8w,
                                              target_net_roas_8w: 0,
                                              current_bid: null,
                                              recommended_bid: null,
                                              campaign_type: p.campaign_type || 'SPONSORED_PRODUCTS',
                                              product: 'Keyword',
                                              spend: 0, orders: 0, cpc: 0, conv_rate: 0,
                                              seasonal_theme: p.seasonal_theme
                                            });
                                          }}
                                          title={`Queue ${p.action}`}
                                        >
                                          {inQ ? <Check size={14} /> : <Plus size={14} />}
                                        </button>
                                      </td>
                                    </tr>
                                  );
                                })}
                            </tbody>
                          </table>
                        )}
                      </div>
                    );
                  })}
                </div>
              );
            })}
          </div>
        </div>
        );
      })()}
    </div>
  );
}

const SIGNAL_COLORS: Record<string, { bg: string; text: string; emoji: string }> = {
  SCALE_WINNER:           { bg: 'bg-emerald-500/15', text: 'text-emerald-400', emoji: '🚀' },
  SEASONAL_OPPORTUNITY:   { bg: 'bg-amber-500/15',   text: 'text-amber-300',   emoji: '📅' },
  PROFITABLE_HOLD:        { bg: 'bg-green-500/12',   text: 'text-green-400',   emoji: '✅' },
  ORGANIC_ASSISTED:       { bg: 'bg-blue-500/12',    text: 'text-blue-400',    emoji: '🌱' },
  CPC_SQUEEZE:            { bg: 'bg-orange-500/15',  text: 'text-orange-400',  emoji: '💸' },
  UNPROFITABLE:           { bg: 'bg-red-500/15',     text: 'text-red-400',     emoji: '🛑' },
  MARGINAL:               { bg: 'bg-zinc-500/15',    text: 'text-zinc-400',    emoji: '⚖️' },
  MONITOR:                { bg: 'bg-zinc-500/10',    text: 'text-zinc-500',    emoji: '👀' },
};
const defaultSignalColor = { bg: 'bg-zinc-500/10', text: 'text-zinc-500', emoji: '❓' };

function ActionRowComponent({ action: a, cd, prediction: pred, expanded, onToggle, matchAction, visibleCols, indent }: { action: ActionRow; cd?: CoachDecisionRow; prediction?: StrategicPrediction; expanded: boolean; onToggle: () => void; matchAction: (a: { search_term?: string; experiment_id?: string; net_roas?: number; cpc?: number; conv_rate?: number }) => { gt: GroundTruth; supported: boolean }[]; visibleCols: MeasureDef[]; indent?: number }) {
  const gtm = matchAction(a);
  const isNotTargeted = a.ads_signal === 'NOT_TARGETED';
  const na = <span className="text-zinc-500">—</span>;
  const numTd = (v: number | undefined | null, f: (n: number) => string = fmt) =>
    <td className="px-3 py-2 text-right font-mono text-[11px]">{v != null && v !== 0 ? f(v) : na}</td>;
  const pctTd = (v: number | undefined | null) =>
    <td className="px-3 py-2 text-right font-mono text-[11px]">{v != null && v !== 0 ? fP(v) : na}</td>;
  const monTd = (v: number | undefined | null) =>
    <td className="px-3 py-2 text-right font-mono text-[11px] font-medium">{v != null && v !== 0 ? fM(v) : na}</td>;
  const pSpend = a.spend || 0;
  const pOrders = a.orders || 0;
  const pClicks = a.spend && a.cpc ? Math.round(a.spend / a.cpc) : 0;
  const pConvRate = a.conv_rate || (pClicks > 0 ? (pOrders * 100) / pClicks : 0);
  const pCpc = a.cpc || (pClicks > 0 ? pSpend / pClicks : 0);
  const pNetRoas = a.net_roas ?? (pSpend > 0 ? (pOrders * (a.margin_per_unit || 0)) / pSpend : 0);
  const cells: Record<string, React.ReactNode> = {
    search_term: <td key="search_term" className="px-3 py-2" style={indent ? { paddingLeft: indent } : undefined}><strong className="text-blue-400">{a.search_term || '--'}</strong></td>,
    product_short_name: <td key="product_short_name" className="px-3 py-2">{a.product_short_name || '--'}</td>,
    experiment_id: <td key="experiment_id" className="px-3 py-2 text-[11px] text-subtle">{a.experiment_id || '--'}</td>,
    strategy_id: <td key="strategy_id" className="px-3 py-2 text-[11px] text-subtle">{a.strategy_id || '--'}</td>,
    spend: <td key="spend" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{isNotTargeted ? na : fM(pSpend)}</td>,
    orders: <td key="orders" className="px-3 py-2 text-right">{isNotTargeted ? na : fOrd(pOrders)}</td>,
    conv_rate: <td key="conv_rate" className="px-3 py-2 text-right">{isNotTargeted ? na : fP(pConvRate)}</td>,
    cpc: <td key="cpc" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{isNotTargeted ? na : fCpc(pCpc)}</td>,
    net_roas: <td key="net_roas" className="px-3 py-2 text-right">{isNotTargeted ? na : <RoasBadge value={pNetRoas} />}</td>,
    ads_clicks_4w: <td key="ads_clicks_4w" className="px-3 py-2 text-right font-mono text-[11px]">{cd?.ads_clicks_4w != null ? fmt(cd.ads_clicks_4w) : na}</td>,
    ads_impressions_4w: <td key="ads_impressions_4w" className="px-3 py-2 text-right font-mono text-[11px]">{cd?.ads_impressions_4w != null ? fmt(cd.ads_impressions_4w) : na}</td>,
    ads_units_4w: <td key="ads_units_4w" className="px-3 py-2 text-right font-mono text-[11px]">{cd?.ads_units_4w != null ? fmt(cd.ads_units_4w) : na}</td>,
    ads_sales_4w: <td key="ads_sales_4w" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{cd?.ads_sales_4w != null ? fM(cd.ads_sales_4w) : na}</td>,
    ads_net_profit_4w: <td key="ads_net_profit_4w" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{cd?.ads_net_profit_4w != null ? fM(cd.ads_net_profit_4w) : na}</td>,
    ads_cost_per_order_4w: <td key="ads_cost_per_order_4w" className="px-3 py-2 text-right font-mono text-[11px]">{cd?.ads_cost_per_order_4w != null ? fM(cd.ads_cost_per_order_4w) : na}</td>,
    ads_spend_ly_peak: monTd(cd?.ads_spend_ly_peak),
    ads_orders_ly_peak: numTd(cd?.ads_orders_ly_peak, fOrd),
    ads_clicks_ly_peak: numTd(cd?.ads_clicks_ly_peak),
    ads_impressions_ly_peak: numTd(cd?.ads_impressions_ly_peak),
    ads_units_ly_peak: numTd(cd?.ads_units_ly_peak),
    ads_sales_ly_peak: monTd(cd?.ads_sales_ly_peak),
    ads_cpc_ly_peak: monTd(cd?.ads_cpc_ly_peak),
    ads_cvr_pct_ly_peak: pctTd(cd?.ads_cvr_pct_ly_peak),
    ads_net_roas_ly_peak: <td key="ads_net_roas_ly_peak" className="px-3 py-2 text-right">{cd?.ads_net_roas_ly_peak != null && cd.ads_net_roas_ly_peak !== 0 ? <RoasBadge value={cd.ads_net_roas_ly_peak} /> : na}</td>,
    ads_spend_lifetime: monTd(cd?.ads_spend_lifetime),
    ads_orders_lifetime: numTd(cd?.ads_orders_lifetime, fOrd),
    ads_net_roas_lifetime: <td key="ads_net_roas_lifetime" className="px-3 py-2 text-right">{cd?.ads_net_roas_lifetime != null && cd.ads_net_roas_lifetime !== 0 ? <RoasBadge value={cd.ads_net_roas_lifetime} /> : na}</td>,
    sqp_impressions_4w: numTd(cd?.sqp_impressions_4w),
    sqp_clicks_4w: numTd(cd?.sqp_clicks_4w),
    sqp_cart_adds_4w: numTd(cd?.sqp_cart_adds_4w),
    sqp_orders_4w: numTd(cd?.sqp_orders_4w, fOrd),
    sqp_sales_4w: monTd(cd?.sqp_sales_4w),
    sqp_organic_units_4w: numTd(cd?.sqp_organic_units_4w),
    sqp_show_rate_4w: pctTd(cd?.sqp_show_rate_4w),
    sqp_impression_share_4w: pctTd(cd?.sqp_impression_share_4w),
    sqp_organic_rank_4w: <td key="sqp_organic_rank_4w" className="px-3 py-2 text-right font-mono text-[11px]">{cd?.sqp_organic_rank_4w != null && cd.sqp_organic_rank_4w !== 0 ? cd.sqp_organic_rank_4w.toFixed(1) : na}</td>,
    sqp_amazon_impressions_4w: numTd(cd?.sqp_amazon_impressions_4w),
    sqp_amazon_clicks_4w: numTd(cd?.sqp_amazon_clicks_4w),
    sqp_amazon_cart_adds_4w: numTd(cd?.sqp_amazon_cart_adds_4w),
    sqp_amazon_orders_4w: numTd(cd?.sqp_amazon_orders_4w, fOrd),
    sqp_amazon_search_volume_4w: numTd(cd?.sqp_amazon_search_volume_4w),
    sqp_impressions_ly_peak: numTd(cd?.sqp_impressions_ly_peak),
    sqp_clicks_ly_peak: numTd(cd?.sqp_clicks_ly_peak),
    sqp_cart_adds_ly_peak: numTd(cd?.sqp_cart_adds_ly_peak),
    sqp_orders_ly_peak: numTd(cd?.sqp_orders_ly_peak, fOrd),
    sqp_sales_ly_peak: monTd(cd?.sqp_sales_ly_peak),
    sqp_show_rate_ly_peak: pctTd(cd?.sqp_show_rate_ly_peak),
    sqp_impression_share_ly_peak: pctTd(cd?.sqp_impression_share_ly_peak),
    sqp_organic_rank_ly_peak: <td key="sqp_organic_rank_ly_peak" className="px-3 py-2 text-right font-mono text-[11px]">{cd?.sqp_organic_rank_ly_peak != null && cd.sqp_organic_rank_ly_peak !== 0 ? cd.sqp_organic_rank_ly_peak.toFixed(1) : na}</td>,
    sqp_amazon_impressions_ly_peak: numTd(cd?.sqp_amazon_impressions_ly_peak),
    sqp_amazon_clicks_ly_peak: numTd(cd?.sqp_amazon_clicks_ly_peak),
    sqp_amazon_cart_adds_ly_peak: numTd(cd?.sqp_amazon_cart_adds_ly_peak),
    sqp_amazon_orders_ly_peak: numTd(cd?.sqp_amazon_orders_ly_peak, fOrd),
    sqp_amazon_search_volume_ly_peak: numTd(cd?.sqp_amazon_search_volume_ly_peak),
    margin_per_unit: <td key="margin_per_unit" className="px-3 py-2 text-right font-mono text-[11px]">{a.margin_per_unit != null ? fM(a.margin_per_unit) : '--'}</td>,
    signal: <td key="signal" className="px-3 py-2">
      {a.ads_signal && <Badge variant="muted">{a.ads_signal}</Badge>}
      {gtm.length > 0 ? gtm.map((m, i) => (
        <span key={i} className={`inline-block ml-1 px-1.5 py-px rounded text-[9px] font-bold ${m.supported ? 'bg-emerald-500/12 text-emerald-400' : 'bg-amber-500/12 text-amber-400'}`} title={m.gt.description || ''}>
          {m.supported ? '✓' : '⚠'} {m.gt.metric}
        </span>
      )) : null}
    </td>,
    action: <td key="action" className="px-3 py-2">
      <div className="flex items-center gap-1">
        <ActionBadge action={a.action} />
        {(a.action === 'NEGATE' || a.action === 'STOP' || a.action === 'REDUCE_BID') && cd && !cd.ads_active_last_7d && (
          <span className="inline-flex items-center gap-0.5 px-1.5 py-px rounded text-[8px] font-bold bg-amber-500/12 text-amber-400 whitespace-nowrap" title="No ads impressions in last 7 days — action may be unnecessary">
            ⏸ No recent ads
          </span>
        )}
      </div>
    </td>,
    reason: <td key="reason" className="px-3 py-2 max-w-[200px]"><span className="text-[10px] text-subtle truncate block" title={a.reason || ''}>{a.reason || '—'}</span></td>,
  };

  const sc = pred ? (SIGNAL_COLORS[pred.strategic_signal] || defaultSignalColor) : null;
  const factorBar = (label: string, val: number, base: number = 1) => {
    const pct = Math.round((val - base) * 100);
    const color = pct >= 10 ? 'text-emerald-400' : pct <= -10 ? 'text-red-400' : 'text-zinc-400';
    return <span className={`font-mono text-[10px] ${color}`}>{label}: {pct >= 0 ? '+' : ''}{pct}%</span>;
  };

  return (
    <>
      <tr onClick={onToggle} className="border-b border-border-faint hover:bg-white/[.02] cursor-pointer transition-colors">
        {visibleCols.map(c => cells[c.id])}
      </tr>
      {expanded && (
        <tr>
          <td colSpan={visibleCols.length} className="p-0">
            <div className="px-3.5 py-2.5 bg-inset text-[11px] text-subtle leading-relaxed">
              <strong className="text-muted">Campaign:</strong> {a.campaign_name || '--'}
              {a.portfolio_name && <> · <strong className="text-muted">Portfolio:</strong> {a.portfolio_name}</>}
              <br />
              <strong className="text-muted">Reason:</strong> {a.reason || '--'}<br />
              <strong className="text-muted">Margin/unit:</strong> {fM(a.margin_per_unit)}
              {a.impression_share != null && <> · <strong className="text-muted">Share:</strong> {fP(a.impression_share)}</>}
              {a.strategy_id && <> · <strong className="text-muted">Strategy:</strong> {a.strategy_id}</>}
              <DecisionTreeViewer row={a} />

              {/* ── Strategic Prediction ── */}
              {pred && sc && (
                <div className="mt-2.5 pt-2.5 border-t border-border-faint">
                  <div className="flex items-center gap-2 mb-1.5">
                    <span className="text-[10px] uppercase tracking-wider text-faint font-bold">Strategic Prediction</span>
                    <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold ${sc.bg} ${sc.text}`}>
                      {sc.emoji} {pred.strategic_signal.replace(/_/g, ' ')}
                    </span>
                    <span className="font-mono text-[10px] text-zinc-400">
                      Predicted Net ROAS: <strong className={pred.predicted_net_roas >= 1 ? 'text-emerald-400' : pred.predicted_net_roas >= 0.7 ? 'text-amber-400' : 'text-red-400'}>{pred.predicted_net_roas.toFixed(2)}</strong>
                    </span>
                    <span className="font-mono text-[9px] text-faint ml-1" title="How much data backs this prediction (0-100)">
                      🎯 {Math.round(pred.prediction_confidence)}% confidence
                    </span>
                  </div>
                  <div className="flex flex-wrap gap-x-3 gap-y-0.5 text-[10px]">
                    {pred.has_seasonal_data
                      ? <>
                          {factorBar('Season', pred.seasonality_multiplier)}
                          {pred.best_season_month != null && (
                            <span className="font-mono text-[10px] text-amber-300">📅 Peak: {['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][pred.best_season_month - 1]}</span>
                          )}
                          {pred.hero_product_name && pred.hero_product_name !== pred.product_short_name && (
                            <span className="font-mono text-[10px] text-cyan-300">🏆 Hero: {pred.hero_product_name}</span>
                          )}
                        </>
                      : <span className="font-mono text-[10px] text-zinc-600">Season: N/A</span>
                    }
                    {pred.peak_multiplier > 1 && factorBar('Peak', pred.peak_multiplier)}
                    {factorBar('CPC Δ', 1 / pred.cpc_inflation_ratio)}
                    {factorBar('TOS', pred.tos_cvr_boost)}
                    {factorBar('Organic Halo', pred.organic_halo_multiplier)}
                    <span className="font-mono text-[10px] text-zinc-500">Lifetime: {pred.total_orders} ord / {pred.days_with_data}d / {fM(pred.total_spend)}</span>
                    {pred.peak_description && <span className="text-amber-300 text-[10px]">📅 {pred.peak_description}</span>}
                  </div>
                </div>
              )}
            </div>
          </td>
        </tr>
      )}
    </>
  );
}
