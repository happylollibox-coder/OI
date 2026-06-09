import React, { useState, useMemo } from 'react';
import { monthlyPlanTargets } from '../planTypes';
import { familyActuals, familyModes, dominantMode } from '../coachActuals';
import { FamilyPlanActuals } from './FamilyPlanActuals';
import type { DashboardData, ActionRow, CoachDecisionRow, StrategicPrediction } from '../types';
import { Badge, RoasBadge, ActionBadge } from '../components/Badge';
import { PageHeader } from '../components/PageHeader';
import { Empty } from '../components/Empty';
import { Th, SortTh, useSort, MEASURE_TIPS } from '../components/Tooltip';
import { fmt, fM, fP, fOrd, fCpc } from '../utils';
import { useFilters } from '../hooks/useFilters';
import { useDoQueue } from '../hooks/useDoQueue';
import { useProductFamily } from '../hooks/useProductFamily';

import { MeasureSelector, useMeasureSelection, type MeasureDef } from '../components/MeasureSelector'; // kept for type reference
import { usePageSummary } from '../components/PageSummaryBar';
import { Plus, Check, Download, CircleX, Ban, TrendingUp, TrendingDown, ShieldCheck, Eye, Crosshair, Sparkles, Wrench, ArrowRightLeft } from 'lucide-react';
import { PieChart, Pie, Cell, Tooltip, ResponsiveContainer } from 'recharts';
import { DecisionTreeViewer } from '../components/Actions/DecisionTreeViewer';
import KeywordIntelligencePanel from '../components/Actions/KeywordIntelligencePanel';
import { useKeywordIntelligence } from '../hooks/useCubeData';
import { CoachStrategyPanel } from '../components/CoachStrategyPanel';
// strategyRules is now DB-only; ActionType kept for potential future use in color mapping

import type { GroundTruth } from '../types';

/* ─── Pie chart bucket classification ─── */
const SPEND_BUCKETS = [
  { key: 'not_converting', label: 'Reduce/Negate', color: '#ef4444', actions: ['NEGATE_TERM', 'NEGATE_BOOST_SIMILAR_EXACT', 'REDUCE_BID', 'STOP_TARGET', 'STOP_SEASONAL', 'RESTORE_PRE_PEAK'] },
  { key: 'profitable', label: 'Profitable', color: '#22c55e', actions: ['KEEP', 'KEEP_TARGET'] },
  { key: 'opportunity', label: 'Opportunity', color: '#a855f7', actions: ['PROMOTE_TO_EXACT', 'START_TERM', 'INCREASE_BID'] },
  { key: 'monitor', label: 'Monitoring', color: '#6b7280', actions: ['MONITOR', 'MONITOR_TARGET', 'SWITCH_HERO', 'COOLDOWN_MONITOR', 'REDUCE_TO_BASELINE', 'CAMPAIGN_PAUSED', 'TARGET_PAUSED'] },
] as const;

/* ─── Strategy display names ─── */
const STRATEGY_DISPLAY: Record<string, string> = {
  HUNTER: 'Hunter', BRAND_DEFENSE: 'Brand Defense', PRODUCT_DEFENSE: 'Product Defense',
  LOW_COST_DISCOVERY: 'Low-Cost Discovery', EXACT_BOOST: 'Exact Boost',
  CATEGORY_CONQUEST: 'Category Conquest', COMPETITOR_CONQUEST: 'Competitor Conquest',
  SEASONAL_PUSH: 'Seasonal Push',
};
const humanizeStratId = (id: string) => STRATEGY_DISPLAY[id] || id.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());


const ACTIONS_TABLE_COLUMNS: MeasureDef[] = [
  // IDs
  { id: 'action_id', label: 'Action ID', group: 'Info' },
  { id: 'branch_id', label: 'Branch ID', group: 'Info' },
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
  { id: 'ads_roas', label: 'Ads ROAS(4w)', tip: 'Ads Sales ÷ Ads Spend (matches Amazon)', group: 'Ads 4w' },
  { id: 'net_roas', label: 'Net ROAS(4w)', tip: MEASURE_TIPS.net_roas, group: 'Ads 4w' },
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
  { id: 'action_explanation', label: 'Explanation', group: 'Info' },
  { id: 'hero_action_explanation', label: 'Hero Explanation', group: 'Hero', defaultVisible: false },
];


const ACTION_TYPES = [
  { id: 'HOT_SIGNAL', label: '🔥 Hot Signals', emoji: '🔥', desc: 'Real-time 3-day alerts' },
  { id: 'TERM',       label: '🎯 Term Actions', emoji: '🎯', desc: 'Search term level' },
  { id: 'PHRASE',     label: '🔫 Phrase Negatives', emoji: '🔫', desc: 'N-gram phrase negation' },
  { id: 'TARGET',     label: '🎚️ Target Actions', emoji: '🎚️', desc: 'Bid operations' },
  { id: 'BUDGET',     label: '💰 Budget Actions', emoji: '💰', desc: 'Campaign budget operations' },
] as const;

// Term actions: NEGATE, KEEP, MONITOR, PROMOTE_TO_EXACT
// Target actions: INCREASE_BID, REDUCE_BID, COOLDOWN_MONITOR, REDUCE_TO_BASELINE, RESTORE_PRE_PEAK, STOP_TARGET, SWITCH_HERO
const TARGET_ACTIONS = new Set(['INCREASE_BID', 'REDUCE_BID', 'COOLDOWN_MONITOR', 'REDUCE_TO_BASELINE', 'RESTORE_PRE_PEAK', 'STOP_TARGET', 'SWITCH_HERO', 'NEGATE_BOOST_SIMILAR_EXACT']);


const ACTION_ICONS: Record<string, React.ComponentType<{ size?: number; className?: string }>> = {
  STOP_TERM: CircleX, STOP_TARGET: CircleX, STOP: CircleX, STOP_SEASONAL: CircleX,
  NEGATE_TERM: Ban, NEGATE: Ban, NEGATE_BOOST_SIMILAR_EXACT: Ban,
  REDUCE_BID: TrendingDown, REDUCE_TO_BASELINE: TrendingDown, RESTORE_PRE_PEAK: TrendingDown,
  COOLDOWN_MONITOR: Eye,
  FIX_HERO: Wrench, SWITCH_HERO: ArrowRightLeft,
  KEEP_TARGET: ShieldCheck, KEEP: ShieldCheck,
  INCREASE_BID: TrendingUp, BOOST: TrendingUp, SCALE_UP: TrendingUp,
  PROMOTE_TO_EXACT: Crosshair,
  START_TERM: Sparkles, START: Sparkles,
  MONITOR_TARGET: Eye, MONITOR: Eye,
  RESTORE_BUDGET: TrendingDown, REDUCE_BUDGET: TrendingDown,
  GUARDIAN_BUDGET_INCREASE: TrendingUp, BLITZ_BUDGET_INCREASE: TrendingUp,
  GUARDIAN_BUDGET_DECREASE: TrendingDown, BLITZ_BUDGET_DECREASE: TrendingDown,
};



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
    // IDs
    { label: 'Action ID',     get: a => a.action_id },
    { label: 'Branch ID',     get: a => a.decision_branch_id || '' },
    // Core Info
    { label: 'Keyword',        get: a => a.search_term },
    { label: 'Product',        get: a => a.product_short_name },
    { label: 'Campaign',       get: a => a.campaign_name },
    { label: 'Portfolio',      get: a => a.portfolio_name },
    { label: 'Experiment',     get: a => a.experiment_id },
    { label: 'Strategy',       get: a => a.strategy_id },
    { label: 'Coach Mode',     get: a => a.coach_mode },
    { label: 'Strategic Task', get: a => a.strategic_task },
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
    { label: 'Ads Sales(4w)',        get: a => a.ads_sales },
    { label: 'Ads Spend(4w)',        get: a => a.spend },
    { label: 'Ads Orders(4w)',       get: a => a.orders },
    { label: 'Ads Clicks(4w)',       get: a => a.clicks },
    { label: 'Ads Recent Clicks(3d)', get: a => a.ads_clicks_recent },
    { label: 'Ads Conv%(4w)',        get: a => { const c = pClicks(a); return c > 0 ? +((a.orders * 100) / c).toFixed(2) : a.conv_rate; } },
    { label: 'Ads CPC(4w)',          get: a => a.cpc },
    { label: 'Ads ROAS(4w)',          get: a => a.ads_roas || (a.ads_sales && a.spend > 0 ? +(a.ads_sales / a.spend).toFixed(2) : 0) },
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
  const { getFamily } = useProductFamily();
  const acts = useMemo(() => {
    return (data.actions || []).map(ct => ({
      ...ct,
      spend: ct.ads_spend_4w,
      ads_sales: ct.ads_sales_4w,
      ads_roas: ct.ads_roas_4w,
      orders: ct.ads_orders_4w,
      clicks: ct.ads_clicks_4w,
      cpc: ct.ads_cpc_4w,
      conv_rate: ct.ads_cvr_pct_4w,
      net_roas: ct.ads_net_roas_4w,
      ads_signal: ct.ads_signal || 'UNKNOWN',
    }) as unknown as ActionRow);
  }, [data.actions]);
  const [typeFilter, setTypeFilter] = useState('all');
  const [stratFilter, setStratFilter] = useState('all');
  const [famFilter, setFamFilter] = useState('all');
  const [coachFilter, setCoachFilter] = useState('all');
  const [bucketFilter, setBucketFilter] = useState<string | null>(null);
  const [strategicTaskFilter, setStrategicTaskFilter] = useState<string | null>(null);
  const [expandedKeys, setExpandedKeys] = useState<Set<string>>(new Set());
  const [intelligenceKeyword, setIntelligenceKeyword] = useState<string | null>(null);
  const [hideMonitor, setHideMonitor] = useState(true);
  const [hierarchy, setHierarchy] = useState<'campaign' | 'action' | 'action_type' | 'strategy' | 'branch'>('campaign');
  const { data: intelligenceData, loading: intelligenceLoading } = useKeywordIntelligence(intelligenceKeyword);

  const effectiveFam = filters.family || (famFilter !== 'all' ? famFilter : null);

  const types = useMemo(() => [...new Set(acts.map(a => a.action).filter(Boolean))].sort(), [acts]);
  const strategies = useMemo(() => [...new Set(acts.map(a => a.strategy_id).filter(Boolean))].sort(), [acts]);
  const fams = useMemo(() => [...new Set(acts.map(a => getFamily(a.product_short_name)).filter(Boolean))].sort(), [acts, getFamily]);

  /* ─── Coach decisions enrichment: lookup SQP + extended Ads by search_term ─── */
  const cdByTerm = useMemo(() => {
    const map: Record<string, typeof data.coach_decisions[0]> = {};
    for (const cd of data.coach_decisions || []) {
      const key = (cd.search_term || '').toLowerCase();
      if (key && !map[key]) map[key] = cd;
    }
    return map;
  }, [data.coach_decisions]);

  /* ─── Plan targets: this month's planned ad cost / CPC / ROAS per family (from the Plan wizard) ─── */
  const planTargets = useMemo(() => {
    const d = new Date();
    return monthlyPlanTargets(data.plan_ads_targets || [], d.getFullYear(), d.getMonth() + 1);
  }, [data.plan_ads_targets]);
  const planMoLabel = new Date().toLocaleString('en-US', { month: 'short' });

  /* ─── Last-week actuals per family vs the (daily) plan guidelines:
       • SPEND/d + CPC = last 7 days from daily_trends (product_type = family; ad_cost & clicks are
         ad-only) — clean, recent, non-overlapping.
       • net ROAS = last 4w, ad-only, spend-weighted over the family's coach term rows — the only
         ad-only ROAS available (a daily_trends ROAS would be blended/halo, not comparable to the
         ad-only plan target). ─── */
  const famActuals = useMemo(
    () => familyActuals(acts, data.daily_trends || [], getFamily),
    [acts, getFamily, data.daily_trends],
  );

  // Per-family dominant coach mode (keyed by getFamily) — each family is judged on its OWN mode.
  const famModes = useMemo(() => familyModes(data.actions || [], getFamily), [data.actions, getFamily]);

  /* ── Strategic keyword predictions lookup ── */
  const predByTerm = useMemo(() => {
    const map: Record<string, StrategicPrediction> = {};
    for (const p of data.keyword_predictions || []) {
      const key = (p.search_term || '').toLowerCase();
      if (key && !map[key]) map[key] = p;
    }
    return map;
  }, [data.keyword_predictions]);

  // Effective coach mode: respect filter dropdown, otherwise detect dominant mode from data
  const effectiveCoachMode = useMemo(() => {
    if (coachFilter !== 'all') return coachFilter;
    return dominantMode(data.actions || []);
  }, [coachFilter, data.actions]);

  const filtered = useMemo(() => {
    let f = [...acts];
    // COOLDOWN mode: suppress negates and hot-signal-like actions — cooldown itself handles wind-down
    if (effectiveCoachMode === 'COOLDOWN') {
      f = f.filter(a => !(a.action === 'NEGATE_TERM' || a.action === 'REDUCE_BID'));
    }
    // Hide actions already uploaded to Amazon
    // Check both search_term and targeting — target actions are queued with targeting keyword as search_term
    f = f.filter(a => !doQueue.isUploaded(a.search_term, a.campaign_id)
      && !(a.targeting && doQueue.isUploaded(a.targeting, a.campaign_id)));
    // Hide actions already marked as done in Do queue
    f = f.filter(a => !doQueue.isDone(a.search_term, a.campaign_id)
      && !(a.targeting && doQueue.isDone(a.targeting, a.campaign_id)));
    if (typeFilter !== 'all') f = f.filter(a => a.action === typeFilter);
    if (stratFilter !== 'all') f = f.filter(a => a.strategy_id === stratFilter);
    if (effectiveFam) f = f.filter(a => getFamily(a.product_short_name) === effectiveFam);
    else if (famFilter !== 'all') f = f.filter(a => getFamily(a.product_short_name) === famFilter);
    // Header product filter: filter by ASIN
    if (filters.product) f = f.filter(a => a.asin === filters.product);
    if (filters.experiment) f = f.filter(a => a.experiment_id === filters.experiment);
    if (filters.keyword) f = f.filter(a => a.search_term === filters.keyword);
    if (coachFilter !== 'all') f = f.filter(a => a.coach_mode === coachFilter);
    if (strategicTaskFilter) {
      // RESTORE_BUDGETS: budget rows are injected from coachTerms in the tree — no action rows needed
      if (strategicTaskFilter === 'RESTORE_BUDGETS') {
        f = [];
      } else {
        f = f.filter(a => a.strategic_task === strategicTaskFilter);
      }
    }
    if (bucketFilter) {
      const bucket = SPEND_BUCKETS.find(b => b.key === bucketFilter);
      if (bucket) f = f.filter(a => (bucket.actions as readonly string[]).includes(a.action));
    }
    // Default: hide monitor/passive actions unless user explicitly shows them
    if (hideMonitor) {
      f = f.filter(a => !['MONITOR', 'MONITOR_TARGET', 'COOLDOWN_MONITOR', 'KEEP', 'KEEP_TARGET', 'BUDGET_OK', 'SWITCH_HERO', 'FIX_HERO'].includes(a.action));
    }
    f.sort((a, b) => (b.priority_score || 0) - (a.priority_score || 0));
    return f;
  }, [acts, typeFilter, stratFilter, famFilter, effectiveFam, filters.product, filters.experiment, filters.keyword, coachFilter, bucketFilter, strategicTaskFilter, doQueue.isUploaded, doQueue.isDone, effectiveCoachMode, hideMonitor]);

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



  const toggleKey = (key: string) => {
    setExpandedKeys(prev => { const n = new Set(prev); n.has(key) ? n.delete(key) : n.add(key); return n; });
  };

  /* ── Tree: Portfolio → Campaign → Action → Target (bid ops) / Keyword (search-term ops) ── */
  type TreeNode = {
    key: string; label: string; level: 'portfolio' | 'campaign' | 'action' | 'target' | 'keyword';
    children: TreeNode[]; rows: ActionRow[];
    metrics: { spend: number; orders: number; count: number; targetAction?: string; targetRoas?: number; targetOrders?: number; matchType?: string; targetDecisionTrace?: import('../types').DecisionStep[] | null };
  };

  /* ── Compute cross-keyword campaign counts for complexity badges ── */
  const keywordCampaignCounts = useMemo(() => {
    const counts: Record<string, Set<string>> = {};
    for (const r of acts) {
      const k = (r.search_term || '').toLowerCase();
      if (!k) continue;
      if (!counts[k]) counts[k] = new Set();
      if (r.campaign_id) counts[k].add(r.campaign_id);
    }
    return Object.fromEntries(Object.entries(counts).map(([k, s]) => [k, s.size]));
  }, [acts]);

  /* ── UNIFIED TREE: builds hierarchy based on selected mode ── */
  const unifiedTree = useMemo((): TreeNode[] => {
    type QueueItem = { spend: number; type: 'TERM' | 'TARGET' | 'HOT_SIGNAL' | 'PHRASE' | 'BUDGET'; signal: string; term: string; campaign: string; campaignId: string; row?: ActionRow; hotSignal?: any; phrase?: any; budgetRow?: any; campaignCount: number; action?: string };

    const items: QueueItem[] = [];

    // 1) SQL-driven Unpivoted Actions
    for (const r of filtered) {
      if (!r.action_type) continue;
      
      const termLower = (r.search_term || '').toLowerCase();
      const campaignCount = keywordCampaignCounts[termLower] || 1;
      const campaignLabel = r.campaign_name || 'Unassigned';
      const campaignId = r.campaign_id || '';
      let itemType: 'TERM' | 'TARGET' | 'BUDGET' | 'HOT_SIGNAL' | 'PHRASE';
      if (r.action_type === 'BUDGET') itemType = 'BUDGET';
      else if (r.action_type === 'TARGET') itemType = 'TARGET';
      else if (r.action_type === 'HERO') itemType = 'TERM';
      else itemType = 'TERM';

      const tSpend = r.action_type === 'TARGET' ? (r.target_spend_8w || r.spend || 0) : (r.spend || 0);

      items.push({
        spend: tSpend,
        type: itemType,
        signal: r.ads_signal || '',
        term: r.action_type === 'BUDGET' ? (r.campaign_name || '--') : (r.search_term || r.targeting || '--'),
        campaign: campaignLabel,
        campaignId,
        row: r,
        campaignCount,
        budgetRow: r.action_type === 'BUDGET' ? r : undefined,
        action: r.action || 'MONITOR',
      });
    }

    // 2) Hot signals — suppressed in COOLDOWN
    if (effectiveCoachMode !== 'COOLDOWN') {
      let hotSignals = (data.hot_signals || []).filter(s => {
        if (effectiveFam && getFamily(s.product_short_name) !== effectiveFam) return false;
        if (filters.product && s.asin !== filters.product) return false;
        if (filters.experiment && s.experiment_id !== filters.experiment) return false;
        if (filters.keyword && s.search_term !== filters.keyword) return false;
        if (stratFilter !== 'all' && s.strategy_id !== stratFilter) return false;
        return true;
      });
      for (const s of hotSignals) {
        items.push({
          spend: s.spend_3d || 0, type: 'HOT_SIGNAL', signal: s.hot_signal || 'HOT_WINNER',
          term: s.search_term || '--', campaign: s.campaign_name || 'Unassigned', campaignId: s.campaign_id || '',
          hotSignal: s, campaignCount: 1, action: s.hot_signal || 'HOT_SIGNAL',
        });
      }
    }

    // 3) Phrase negatives — suppressed in COOLDOWN
    // Phrase negatives: suppress when product filter is active (phrases have no product context)
    if (effectiveCoachMode !== 'COOLDOWN' && !filters.product) {
      for (const p of (data.coach_phrase_negatives || [])) {
        items.push({
          spend: p.phrase_spend_8w || 0, type: 'PHRASE', signal: p.action || 'NEGATE_PHRASE',
          term: p.phrase || '--', campaign: p.campaign_name || 'Unassigned', campaignId: p.campaign_id || '',
          phrase: p, campaignCount: 1, action: p.action || 'NEGATE_PHRASE',
        });
      }
    }

    if (!items.length) return [];

    // ── Helper: build leaf nodes from items ──
    const buildLeaves = (leafItems: QueueItem[], keyPrefix: string): TreeNode[] => {
      const hotItems = leafItems.filter(i => i.type === 'HOT_SIGNAL');
      const phraseItems = leafItems.filter(i => i.type === 'PHRASE');
      const budgetItems = leafItems.filter(i => i.type === 'BUDGET');
      const regularItems = leafItems.filter(i => !['HOT_SIGNAL', 'PHRASE', 'BUDGET'].includes(i.type));

      const leaves: TreeNode[] = [];
      for (const item of hotItems) {
        leaves.push({ key: `${keyPrefix}:hot:${item.term}`, label: item.term, level: 'keyword', children: [], rows: [], metrics: { spend: item.spend, orders: item.hotSignal?.orders_3d || 0, count: 1, hotSignalData: item.hotSignal } });
      }
      for (const item of phraseItems) {
        leaves.push({ key: `${keyPrefix}:phr:${item.term}`, label: item.term, level: 'keyword', children: [], rows: [], metrics: { spend: item.spend, orders: 0, count: 1, phraseData: item.phrase } });
      }
      for (const item of budgetItems) {
        leaves.push({ key: `${keyPrefix}:bud:${item.term}`, label: item.term, level: 'keyword', children: [], rows: [item.row!], metrics: { spend: item.spend, orders: 0, count: 1, budgetRow: item.budgetRow } });
      }
      // Group regular items by term
      const byTerm: Record<string, QueueItem[]> = {};
      for (const item of regularItems) { if (!byTerm[item.term]) byTerm[item.term] = []; byTerm[item.term].push(item); }
      for (const [termKey, tItems] of Object.entries(byTerm)) {
        leaves.push({
          key: `${keyPrefix}:kw:${termKey}`,
          label: termKey, level: 'keyword', children: [],
          rows: tItems.filter(i => i.row).map(i => i.row!),
          metrics: { spend: tItems.reduce((s, i) => s + i.spend, 0), orders: tItems.reduce((s, i) => s + (i.row?.orders || 0), 0), count: tItems.length },
        });
      }
      return leaves.sort((a, b) => b.metrics.spend - a.metrics.spend);
    };

    // ═══ HIERARCHY: By Campaign (default) ═══
    if (hierarchy === 'campaign') {
      const byCampaign: Record<string, QueueItem[]> = {};
      for (const item of items) { const key = item.campaign || 'Unassigned'; if (!byCampaign[key]) byCampaign[key] = []; byCampaign[key].push(item); }

      return Object.entries(byCampaign)
        .map(([campaignName, campItems]) => {
          const campSpend = campItems.reduce((s, i) => s + i.spend, 0);
          const campOrders = campItems.filter(i => i.row).reduce((s, i) => s + (i.row!.orders || 0), 0);

          const typeNodes: TreeNode[] = [];
          for (const typeDef of ACTION_TYPES) {
            const typeItems = campItems.filter(i => i.type === typeDef.id);
            if (!typeItems.length) continue;
            const typeSpend = typeItems.reduce((s, i) => s + i.spend, 0);
            const typeOrders = typeItems.filter(i => i.row).reduce((s, i) => s + (i.row!.orders || 0), 0);
            const leafNodes = buildLeaves(typeItems, `type:${campaignName}:${typeDef.id}`);

            typeNodes.push({
              key: `type:${campaignName}:${typeDef.id}`,
              label: typeDef.id, level: 'action', children: leafNodes,
              rows: typeItems.filter(i => i.row).map(i => i.row!),
              metrics: { spend: typeSpend, orders: typeOrders, count: typeItems.length },
            });
          }

          return {
            key: `camp:${campaignName}`,
            label: campaignName, level: 'campaign' as const, children: typeNodes,
            rows: campItems.filter(i => i.row).map(i => i.row!),
            metrics: { spend: campSpend, orders: campOrders, count: campItems.length },
          };
        })
        .sort((a, b) => b.metrics.spend - a.metrics.spend);
    }

    // ═══ HIERARCHY: By Action ═══
    if (hierarchy === 'action') {
      const byAction: Record<string, QueueItem[]> = {};
      for (const item of items) { const key = item.action || 'MONITOR'; if (!byAction[key]) byAction[key] = []; byAction[key].push(item); }

      return Object.entries(byAction)
        .map(([actionName, actionItems]) => {
          const actionSpend = actionItems.reduce((s, i) => s + i.spend, 0);
          const actionOrders = actionItems.filter(i => i.row).reduce((s, i) => s + (i.row!.orders || 0), 0);

          // Group by campaign under each action
          const byCampaign: Record<string, QueueItem[]> = {};
          for (const item of actionItems) { const key = item.campaign || 'Unassigned'; if (!byCampaign[key]) byCampaign[key] = []; byCampaign[key].push(item); }

          const campNodes: TreeNode[] = Object.entries(byCampaign)
            .map(([campName, campItems]) => {
              const leaves = buildLeaves(campItems, `action:${actionName}:${campName}`);
              return {
                key: `action:${actionName}:camp:${campName}`,
                label: campName, level: 'campaign' as const, children: leaves,
                rows: campItems.filter(i => i.row).map(i => i.row!),
                metrics: { spend: campItems.reduce((s, i) => s + i.spend, 0), orders: campItems.reduce((s, i) => s + (i.row?.orders || 0), 0), count: campItems.length },
              };
            })
            .sort((a, b) => b.metrics.spend - a.metrics.spend);

          return {
            key: `action:${actionName}`,
            label: actionName, level: 'action' as const, children: campNodes,
            rows: actionItems.filter(i => i.row).map(i => i.row!),
            metrics: { spend: actionSpend, orders: actionOrders, count: actionItems.length },
          };
        })
        .sort((a, b) => b.metrics.spend - a.metrics.spend);
    }

    // ═══ HIERARCHY: By Strategy → Campaign → Action Type → Leaves ═══
    if (hierarchy === 'strategy') {
      const byStrategy: Record<string, QueueItem[]> = {};
      for (const item of items) { 
        const key = item.row?.strategy_id || item.hotSignal?.strategy_id || item.phrase?.strategy_id || 'No Strategy'; 
        if (!byStrategy[key]) byStrategy[key] = []; 
        byStrategy[key].push(item);
      }

      return Object.entries(byStrategy)
        .map(([stratId, stratItems]) => {
          const stratSpend = stratItems.reduce((s, i) => s + i.spend, 0);
          const stratOrders = stratItems.filter(i => i.row).reduce((s, i) => s + (i.row!.orders || 0), 0);
          const displayName = humanizeStratId(stratId);

          // Level 2: Group by campaign
          const byCampaign: Record<string, QueueItem[]> = {};
          for (const item of stratItems) { const key = item.campaign || 'Unassigned'; if (!byCampaign[key]) byCampaign[key] = []; byCampaign[key].push(item); }

          const campNodes: TreeNode[] = Object.entries(byCampaign)
            .map(([campName, campItems]) => {
              const campSpend = campItems.reduce((s, i) => s + i.spend, 0);
              const campOrders = campItems.filter(i => i.row).reduce((s, i) => s + (i.row?.orders || 0), 0);

              // Level 3: Group by action type within campaign
              const typeNodes: TreeNode[] = [];
              for (const typeDef of ACTION_TYPES) {
                const typeItems = campItems.filter(i => i.type === typeDef.id);
                if (!typeItems.length) continue;
                const typeSpend = typeItems.reduce((s, i) => s + i.spend, 0);
                const typeOrders = typeItems.filter(i => i.row).reduce((s, i) => s + (i.row!.orders || 0), 0);
                const leafNodes = buildLeaves(typeItems, `strat:${stratId}:${campName}:${typeDef.id}`);

                typeNodes.push({
                  key: `strat:${stratId}:${campName}:${typeDef.id}`,
                  label: typeDef.id, level: 'action', children: leafNodes,
                  rows: typeItems.filter(i => i.row).map(i => i.row!),
                  metrics: { spend: typeSpend, orders: typeOrders, count: typeItems.length },
                });
              }

              return {
                key: `strat:${stratId}:camp:${campName}`,
                label: campName, level: 'campaign' as const, children: typeNodes,
                rows: campItems.filter(i => i.row).map(i => i.row!),
                metrics: { spend: campSpend, orders: campOrders, count: campItems.length },
              };
            })
            .sort((a, b) => b.metrics.spend - a.metrics.spend);

          return {
            key: `strat:${stratId}`,
            label: `🎯 ${displayName}`, level: 'portfolio' as const, children: campNodes,
            rows: stratItems.filter(i => i.row).map(i => i.row!),
            metrics: { spend: stratSpend, orders: stratOrders, count: stratItems.length },
          };
        })
        .sort((a, b) => b.metrics.spend - a.metrics.spend);
    }

    // ═══ HIERARCHY: By Action Type ═══
    if (hierarchy === 'action_type') {
      const byType: Record<string, QueueItem[]> = {};
      for (const item of items) { const key = item.type; if (!byType[key]) byType[key] = []; byType[key].push(item); }

      return ACTION_TYPES
        .filter(typeDef => byType[typeDef.id]?.length)
        .map(typeDef => {
          const typeItems = byType[typeDef.id]!;
          const typeSpend = typeItems.reduce((s, i) => s + i.spend, 0);
          const typeOrders = typeItems.filter(i => i.row).reduce((s, i) => s + (i.row!.orders || 0), 0);

          // Group by action within each type
          const byAction: Record<string, QueueItem[]> = {};
          for (const item of typeItems) { const key = item.action || 'MONITOR'; if (!byAction[key]) byAction[key] = []; byAction[key].push(item); }

          const actionNodes: TreeNode[] = Object.entries(byAction)
            .map(([actionName, actionItems]) => {
              // Group by campaign under each action
              const byCampaign: Record<string, QueueItem[]> = {};
              for (const item of actionItems) { const key = item.campaign || 'Unassigned'; if (!byCampaign[key]) byCampaign[key] = []; byCampaign[key].push(item); }

              const campNodes: TreeNode[] = Object.entries(byCampaign)
                .map(([campName, campItems]) => {
                  const leaves = buildLeaves(campItems, `atype:${typeDef.id}:${actionName}:${campName}`);
                  return {
                    key: `atype:${typeDef.id}:${actionName}:camp:${campName}`,
                    label: campName, level: 'campaign' as const, children: leaves,
                    rows: campItems.filter(i => i.row).map(i => i.row!),
                    metrics: { spend: campItems.reduce((s, i) => s + i.spend, 0), orders: campItems.reduce((s, i) => s + (i.row?.orders || 0), 0), count: campItems.length },
                  };
                })
                .sort((a, b) => b.metrics.spend - a.metrics.spend);

              return {
                key: `atype:${typeDef.id}:action:${actionName}`,
                label: actionName, level: 'action' as const, children: campNodes,
                rows: actionItems.filter(i => i.row).map(i => i.row!),
                metrics: { spend: actionItems.reduce((s, i) => s + i.spend, 0), orders: actionItems.reduce((s, i) => s + (i.row?.orders || 0), 0), count: actionItems.length },
              };
            })
            .sort((a, b) => b.metrics.spend - a.metrics.spend);

          return {
            key: `atype:${typeDef.id}`,
            label: `${typeDef.emoji} ${typeDef.id}`, level: 'campaign' as const, children: actionNodes,
            rows: typeItems.filter(i => i.row).map(i => i.row!),
            metrics: { spend: typeSpend, orders: typeOrders, count: typeItems.length },
          };
        });
    }

    // ═══ HIERARCHY: By Branch ID ═══
    if (hierarchy === 'branch') {
      const byBranch: Record<string, QueueItem[]> = {};
      for (const item of items) {
        const key = item.row?.decision_branch_id || 'No Branch';
        if (!byBranch[key]) byBranch[key] = [];
        byBranch[key].push(item);
      }

      return Object.entries(byBranch)
        .map(([branchId, branchItems]) => {
          const branchSpend = branchItems.reduce((s, i) => s + i.spend, 0);
          const branchOrders = branchItems.filter(i => i.row).reduce((s, i) => s + (i.row!.orders || 0), 0);

          // Level 2: Group by action type
          const byType: Record<string, QueueItem[]> = {};
          for (const item of branchItems) {
            const key = item.type;
            if (!byType[key]) byType[key] = [];
            byType[key].push(item);
          }

          const typeNodes: TreeNode[] = ACTION_TYPES
            .filter(typeDef => byType[typeDef.id]?.length)
            .map(typeDef => {
              const typeItems = byType[typeDef.id]!;
              const typeSpend = typeItems.reduce((s, i) => s + i.spend, 0);
              const typeOrders = typeItems.filter(i => i.row).reduce((s, i) => s + (i.row!.orders || 0), 0);

              const leaves = buildLeaves(typeItems, `branch:${branchId}:${typeDef.id}`);

              return {
                key: `type:branch:${branchId}:${typeDef.id}`, // start with type: to trigger Action Type banner
                label: typeDef.id, // pure ID so the banner can find the typeDef
                level: 'action' as const, children: leaves,
                rows: typeItems.filter(i => i.row).map(i => i.row!),
                metrics: { spend: typeSpend, orders: typeOrders, count: typeItems.length },
              };
            })
            // Under Branch ID, user wants to order by amount of actions (count) descending
            .sort((a, b) => b.metrics.count - a.metrics.count);

          return {
            key: `branch:${branchId}`,
            label: `🔀 ${branchId}`, level: 'portfolio' as const, children: typeNodes,
            rows: branchItems.filter(i => i.row).map(i => i.row!),
            metrics: { spend: branchSpend, orders: branchOrders, count: branchItems.length },
          };
        })
        .sort((a, b) => b.metrics.count - a.metrics.count);
    }

    return [];
  }, [filtered, data.hot_signals, data.coach_phrase_negatives, data.actions, keywordCampaignCounts, effectiveFam, famFilter, filters, filters.product, stratFilter, effectiveCoachMode, hierarchy]);

  /* ── Section counts ── */
  const totalQueueCount = unifiedTree.reduce((s, n) => s + n.metrics.count, 0);
  const totalQueueSpend = unifiedTree.reduce((s, n) => s + n.metrics.spend, 0);

  /* ── Summary counts from flat action list ── */
  const negateCount = filtered.filter(r => r.action === 'NEGATE_TERM' || r.action === 'REDUCE_BID').length;
  const negateSpend = filtered.filter(r => r.action === 'NEGATE_TERM' || r.action === 'REDUCE_BID').reduce((s, r) => s + (r.spend || 0), 0);
  const keepCount = filtered.filter(r => r.action === 'KEEP' || r.action === 'KEEP_TARGET').length;
  const growCount = filtered.filter(r => r.action === 'PROMOTE_TO_EXACT' || r.action === 'INCREASE_BID' || r.action === 'START_TERM').length;
  const newCount = filtered.filter(r => r.action === 'START_TERM' || r.action === 'START').length;

  usePageSummary({
    title: 'Actions',
    breadcrumbs: [
      { label: 'Home', onClick: () => window.dispatchEvent(new CustomEvent('nav', { detail: 'home' })) },
      { label: 'Actions' },
    ],
    items: [
      { label: 'Negate', value: `${negateCount}`, color: 'red' },
      { label: 'Wasted Spend', value: fM(negateSpend), color: 'red' },
      { label: 'Keep', value: `${keepCount}`, color: 'green' },
      { label: 'Growth', value: `${growCount}`, color: 'green' },
      { label: 'Opportunities', value: `${newCount}`, color: 'blue' },
      { label: 'Total', value: `${filtered.length}` },
    ],
  });

  // Derive active coach mode per family from coach_terms (has parent_name)
  const familyCoachModes = useMemo(() => {
    const map: Record<string, { mode: string; occasion: string; phase: string; count: number }> = {};
    for (const ct of data.actions || []) {
      const fam = ct.parent_name;
      if (!fam || !ct.coach_mode) continue;
      // Respect header filters
      if (effectiveFam && fam !== effectiveFam) continue;
      if (filters.product && ct.asin !== filters.product) continue;
      if (!map[fam]) map[fam] = { mode: ct.coach_mode, occasion: ct.active_occasion || 'NONE', phase: ct.current_phase || 'OFF_SEASON', count: 0 };
      map[fam].count++;
    }
    return map;
  }, [data.actions, effectiveFam, filters.product]);

  // Most urgent mode across all families: COOLDOWN > BLITZ > GUARDIAN
  const activeCoachMode = useMemo(() => {
    const modes = Object.values(familyCoachModes).map(f => f.mode);
    if (modes.includes('COOLDOWN')) return 'COOLDOWN';
    if (modes.includes('BLITZ')) return 'BLITZ';
    if (modes.some(m => m && m !== 'GUARDIAN')) return modes.find(m => m && m !== 'GUARDIAN') || null;
    return modes.length ? 'GUARDIAN' : null;
  }, [familyCoachModes]);

  if (!acts.length) return <Empty icon="⚡" message="No pending actions" hint="Actions appear when keyword data detects bid changes, negations, or opportunities." />;

  /* ── Render a tree node row ── */
  const renderNode = (node: TreeNode, depth: number, parentPath: string): React.ReactNode[] => {
    const fullKey = parentPath ? `${parentPath}\0${node.key}` : node.key;
    const isExpanded = expandedKeys.has(fullKey);
    const hasChildren = node.children.length > 0;
    const pl = depth * 20 + 12;

    /* ─── KEYWORD / LEAF ─── */
    if (node.level === 'keyword') {
      // Hot signal leaf
      const hotData = (node.metrics as any).hotSignalData;
      if (hotData) {
         const SIGNAL_META_MAP: Record<string, { icon: React.ReactNode; color: string; bgColor: string; borderColor: string; label: string; doAction: string }> = {
          URGENT_STOP: { icon: <CircleX size={14} />, color: 'text-red-400', bgColor: 'bg-red-500/8', borderColor: 'border-red-500/25', label: 'Urgent Stop', doAction: 'STOP' },
          HOT_WINNER: { icon: <TrendingUp size={14} />, color: 'text-emerald-400', bgColor: 'bg-emerald-500/8', borderColor: 'border-emerald-500/25', label: 'Hot Winner', doAction: 'INCREASE_BID' },
          RAPID_DECLINE: { icon: <TrendingDown size={14} />, color: 'text-amber-400', bgColor: 'bg-amber-500/8', borderColor: 'border-amber-500/25', label: 'Rapid Decline', doAction: 'REDUCE_BID' },
          POST_PEAK_REDUCE: { icon: <TrendingDown size={14} />, color: 'text-cyan-400', bgColor: 'bg-cyan-500/8', borderColor: 'border-cyan-500/25', label: 'Post-Peak Reduce', doAction: 'REDUCE_BID' },
        };
        const meta = SIGNAL_META_MAP[hotData.hot_signal] || SIGNAL_META_MAP.HOT_WINNER;
        const wasUploaded = doQueue.isUploaded(hotData.search_term, hotData.campaign_id);
        const pendingItem = doQueue.items.find(i => i.search_term === hotData.search_term && i.action === meta.doAction && i.campaign === hotData.campaign_name);
        const inPending = !!pendingItem;
        if (wasUploaded) return []; // hide uploaded hot signals
        return [
          <div key={fullKey}>
            <div className="p-0">
              <div className={`flex items-start gap-3 p-3 mx-2 my-1 rounded-lg border ${meta.borderColor} ${meta.bgColor} transition-all hover:brightness-110`}
                style={{ marginLeft: pl }}>
                <div className={`mt-0.5 ${meta.color}`}>{meta.icon}</div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <span className={`text-[10px] font-bold uppercase tracking-wider ${meta.color}`}>{meta.label}</span>
                    {hotData.coach_8w_action && hotData.hot_signal === 'URGENT_STOP' && (
                      <span className="text-[9px] font-semibold px-1.5 py-0.5 rounded bg-red-500/20 text-red-300 border border-red-500/30">⚠️ Overrides: {hotData.coach_8w_action}</span>
                    )}
                    {hotData.hot_signal === 'POST_PEAK_REDUCE' && hotData.current_bid != null && hotData.recommended_bid != null && (
                      <span className="text-[10px] font-mono font-semibold px-1.5 py-0.5 rounded bg-cyan-500/15 text-cyan-300 border border-cyan-500/25">
                        ${hotData.current_bid.toFixed(2)} → ${hotData.recommended_bid.toFixed(2)}
                      </span>
                    )}
                  </div>
                  <div className="text-[12px] text-white font-semibold truncate">{hotData.search_term}</div>
                  <div className="text-[10px] text-subtle mt-0.5 truncate">Campaign: {hotData.campaign_name} · {hotData.product_short_name}</div>
                  <div className="text-[10px] text-faint mt-1">{hotData.hot_signal_reason}</div>
                </div>
                <div className="flex gap-4 text-right shrink-0 items-start">
                  {hotData.hot_signal === 'POST_PEAK_REDUCE' ? (
                    <>
                      <div><div className="text-[9px] text-subtle uppercase">Bid</div><div className="text-[12px] font-mono text-white">${hotData.current_bid?.toFixed(2)}</div></div>
                      <div><div className="text-[9px] text-subtle uppercase">Target</div><div className="text-[12px] font-mono text-cyan-400">${hotData.recommended_bid?.toFixed(2)}</div></div>
                      <div><div className="text-[9px] text-subtle uppercase">Save</div><div className="text-[12px] font-mono text-emerald-400">-{((hotData.current_bid ?? 0) - (hotData.recommended_bid ?? 0)).toFixed(2)}</div></div>
                    </>
                  ) : (
                    <>
                      <div><div className="text-[9px] text-subtle uppercase">Spend</div><div className="text-[12px] font-mono text-white">{fM(hotData.spend_3d)}</div></div>
                      <div><div className="text-[9px] text-subtle uppercase">Clicks</div><div className="text-[12px] font-mono text-white">{hotData.clicks_3d}</div></div>
                      <div><div className="text-[9px] text-subtle uppercase">Orders</div><div className={`text-[12px] font-mono ${hotData.orders_3d > 0 ? 'text-emerald-400' : 'text-red-400'}`}>{hotData.orders_3d}</div></div>
                    </>
                  )}
                  <div className="flex items-center gap-1.5 mt-1">
                    <button onClick={() => { if (inPending && pendingItem) { doQueue.removeItem(pendingItem.id); return; } doQueue.addItem({ search_term: hotData.search_term, action: meta.doAction, campaign: hotData.campaign_name, campaign_id: hotData.campaign_id, ad_group_id: hotData.ad_group_id, targeting: hotData.search_term, keyword_id: hotData.keyword_id ?? '', match_type: '', target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: hotData.coach_8w_roas ?? 0, current_bid: hotData.current_bid ?? null, recommended_bid: hotData.recommended_bid ?? null, campaign_type: hotData.campaign_type, product: hotData.asin || hotData.product_short_name || '', spend: hotData.spend_3d, orders: hotData.orders_3d, cpc: hotData.cpc_3d ?? 0, conv_rate: hotData.cvr_3d ?? 0 }); }}
                      className={`w-6 h-6 rounded-full flex items-center justify-center transition-all shrink-0 ${inPending ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/40 cursor-pointer hover:bg-red-500/20 hover:text-red-400 hover:border-red-500/40' : 'bg-white/5 text-zinc-400 border border-zinc-600 hover:border-blue-500/50 hover:text-blue-400 hover:bg-blue-500/10 cursor-pointer'}`}
                      title={inPending ? 'Click to remove from DO queue' : `Add "${meta.doAction}" to DO queue`}>{inPending ? <Check size={12} /> : <Plus size={12} />}</button>
                    <span className={`flex items-center gap-1 px-2 py-1 rounded-lg text-[10px] font-bold uppercase tracking-wider ${meta.bgColor} ${meta.color} border ${meta.borderColor}`}>
                      {ACTION_ICONS[meta.doAction] ? React.createElement(ACTION_ICONS[meta.doAction], { size: 11 }) : meta.icon} {meta.doAction.replace(/_/g, ' ')}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        ];
      }

      // Phrase negative leaf
      const phraseData = (node.metrics as any).phraseData;
      if (phraseData) {
        const isNeg = phraseData.action === 'NEGATE_PHRASE';
        const inQ = doQueue.items.some(q => q.campaign_id === phraseData.campaign_id && q.search_term === phraseData.phrase);
        const sampleTerms: { search_term: string; ads_spend_8w: number; ads_orders_8w: number; ads_clicks_8w: number }[] = phraseData.sample_terms || [];
        const phraseExpandKey = `phr-detail:${phraseData.phrase}|${phraseData.campaign_id}`;
        const isPhraseExpanded = expandedKeys.has(phraseExpandKey);
        return [
          <div key={fullKey} className={`flex items-center gap-2 px-3 py-2 border-t transition-colors hover:bg-surface/30 cursor-pointer ${isNeg ? 'border-red-500/20' : 'border-purple-500/20 bg-purple-500/[0.03]'}`}
            onClick={() => toggleKey(phraseExpandKey)}
            style={{ paddingLeft: pl }}
          >
            <div className="flex items-center gap-1.5 min-w-[180px] shrink-0">
              <span className={`text-[10px] transition-transform ${isPhraseExpanded ? 'rotate-90' : ''}`}>▶</span>
              <div>
                <strong className={isNeg ? 'text-blue-400 text-[12px]' : 'text-purple-300 text-[12px]'}>"{phraseData.phrase}"</strong>
                {!isNeg && <div className="text-[9px] text-purple-400/80 mt-0.5">Theme: {phraseData.seasonal_theme}</div>}
              </div>
            </div>

            <div className="flex items-center gap-1 shrink-0">
              <span onClick={e => e.stopPropagation()}>
                <button className={`p-0.5 rounded transition-colors ${inQ ? 'text-emerald-400' : 'text-zinc-500 hover:text-white'}`}
                  onClick={() => { if (inQ) return; doQueue.addItem({ search_term: phraseData.phrase, action: phraseData.action, campaign: phraseData.campaign_name, campaign_id: phraseData.campaign_id, ad_group_id: '', targeting: phraseData.phrase, keyword_id: '', match_type: 'PHRASE', target_spend_8w: phraseData.phrase_spend_8w, target_orders_8w: phraseData.phrase_orders_8w, target_net_roas_8w: 0, current_bid: null, recommended_bid: null, campaign_type: phraseData.campaign_type || 'SPONSORED_PRODUCTS', product: 'Keyword', spend: 0, orders: 0, cpc: 0, conv_rate: 0, seasonal_theme: phraseData.seasonal_theme }); }}
                >{inQ ? <Check size={13} /> : <Plus size={13} />}</button>
              </span>
              <span className={`text-[9px] font-bold px-1.5 py-0.5 rounded border border-white/10 ${isNeg ? 'bg-red-500/20 text-red-300' : 'bg-purple-500/20 text-purple-300'}`}>
                {isNeg ? 'NEGATE' : 'PROMOTE_PEAK'}
              </span>
            </div>

            <div className="flex items-center gap-2 flex-1 min-w-0">
              <div className="text-[10px] text-zinc-400 font-mono truncate max-w-[160px]" title={phraseData.campaign_name}>{phraseData.campaign_name}</div>
              <span className="text-[10px] text-zinc-500 font-mono pl-2 border-l border-zinc-700">{fmt(phraseData.phrase_term_count)} terms</span>
              <span className="text-[11px] font-mono font-medium text-red-400">{fM(phraseData.phrase_spend_8w)}</span>
              {phraseData.phrase_clicks_8w > 0 && <span className="text-[10px] text-zinc-500 font-mono">{fmt(phraseData.phrase_clicks_8w)} cl</span>}
            </div>

            <div className="text-[9px] text-zinc-600 truncate max-w-[200px]" title={phraseData.reason}>{phraseData.reason}</div>
          </div>,
          // Expanded detail: show included search terms
          ...(isPhraseExpanded && sampleTerms.length > 0 ? [
            <div key={`${fullKey}-detail`} className="border-t border-zinc-800/40">
              <div style={{ paddingLeft: pl + 24 }} className="py-2">
                <div className="text-[10px] text-zinc-500 mb-1.5 font-medium">Top keywords containing "{phraseData.phrase}" — {phraseData.phrase_term_count} total</div>
                <div className="grid gap-0.5">
                  {sampleTerms.map((st: any, i: number) => (
                    <div key={i} className="flex items-center gap-3 text-[10px] font-mono py-0.5 px-2 rounded bg-zinc-800/30 hover:bg-zinc-800/50">
                      <span className="text-zinc-400 w-4 text-right">{i + 1}.</span>
                      <span className="text-zinc-200 flex-1 truncate">{st.search_term}</span>
                      <span className="text-red-400/80 w-16 text-right">{fM(st.ads_spend_8w)}</span>
                      <span className={`w-10 text-right ${st.ads_orders_8w > 0 ? 'text-emerald-400' : 'text-zinc-500'}`}>
                        {st.ads_orders_8w > 0 ? `${st.ads_orders_8w} ord` : '0 ord'}
                      </span>
                      <span className="text-zinc-500 w-12 text-right">{st.ads_clicks_8w} cl</span>
                    </div>
                  ))}
                  {phraseData.phrase_term_count > 5 && (
                    <div className="text-[9px] text-zinc-600 mt-0.5">… and {phraseData.phrase_term_count - 5} more terms</div>
                  )}
                </div>
                <div className="text-[9px] text-zinc-600 mt-2 italic">{phraseData.reason}</div>
              </div>
            </div>
          ] : []),
        ];
      }

      // Standard term/target keyword leaf → ActionRowComponent + optional intelligence panel
      const a = node.rows[0];
      if (!a) return [];
      const termLower = (a.search_term || '').toLowerCase();
      const campaignCount = keywordCampaignCounts[termLower] || 1;
      const isComplex = campaignCount >= 3;
      const isIntelExpanded = intelligenceKeyword === a.search_term;

      const result: React.ReactNode[] = [
        <ActionRowComponent
          key={fullKey} action={a} cd={cdByTerm[termLower]}
          prediction={predByTerm[termLower]}
          expanded={isExpanded}
          onToggle={() => {
            const next = new Set(expandedKeys);
            isExpanded ? next.delete(fullKey) : next.add(fullKey);
            setExpandedKeys(next);
          }}
          matchAction={matchAction} indent={pl}
          complexityBadge={isComplex ? campaignCount : undefined}
          onIntelligenceClick={isComplex ? () => {
            setIntelligenceKeyword(prev => prev === a.search_term ? null : (a.search_term || null));
          } : undefined}
          isIntelExpanded={isIntelExpanded}
          doQueue={doQueue}
        />
      ];

      if (isIntelExpanded) {
        result.push(
          <div key={`${fullKey}:intel`}>
            <div className="p-0">
              {intelligenceLoading ? (
                <div className="px-12 py-4 text-zinc-400 text-xs">Loading keyword intelligence...</div>
              ) : intelligenceData ? (
                <div className="pl-8 pr-4 pb-2">
                  <KeywordIntelligencePanel
                    data={intelligenceData}
                    termActions={acts.filter(x => x.search_term?.toLowerCase() === intelligenceKeyword?.toLowerCase())}
                    coachDecision={cdByTerm[intelligenceKeyword?.toLowerCase() || ''] || null}
                    onAddToDoQueue={doQueue.addItem}
                    isInDoQueue={doQueue.hasItem}
                  />
                </div>
              ) : (
                <div className="px-12 py-3 text-zinc-500 text-xs">No intelligence data available.</div>
              )}
            </div>
          </div>
        );
      }
      return result;
    }

    /* ─── NON-LEAF NODES (campaign / type) ─── */
    const rows: React.ReactNode[] = [];

    if (node.key.startsWith('camp:')) {
      // Campaign banner
      rows.push(
        <div key={fullKey} onClick={() => toggleKey(fullKey)}
          className="cursor-pointer transition-all hover:brightness-110 border-b border-border bg-gradient-to-r from-zinc-800/60 via-zinc-900/40 to-transparent">
          <div className="px-0 py-0">
            <div className="flex items-center gap-2.5 text-sm font-bold px-4 py-3 border-l-[4px] border-blue-500/40">
              <span className={`transition-transform duration-200 text-[10px] ${isExpanded ? 'rotate-90' : ''}`}>▶</span>
              <span className="text-base">📦</span>
              <span className="text-white font-bold truncate max-w-[400px]" title={node.label}>{node.label}</span>
              <span className="text-white/80 font-semibold text-xs">({node.metrics.count})</span>
              <span className="font-mono text-[11px] opacity-60">{fM(node.metrics.spend)}</span>
              {node.metrics.orders > 0 && <span className="font-mono text-[10px] opacity-60">· {fOrd(node.metrics.orders)} ord</span>}
            </div>
          </div>
        </div>
      );
    } else if (node.key.startsWith('type:')) {
      // Action type banner
      const typeDef = ACTION_TYPES.find(t => t.id === node.label);
      const td2 = typeDef || ACTION_TYPES[1];
      rows.push(
        <div key={fullKey} onClick={() => toggleKey(fullKey)}
          className="cursor-pointer transition-all hover:brightness-110 border-b border-border-faint bg-surface/40">
          <div className="px-0 py-0">
            <div className="flex items-center gap-2 text-[11px] font-bold px-3.5 py-2"
              style={{ paddingLeft: pl }}>
              <span className={`transition-transform duration-200 text-[9px] ${isExpanded ? 'rotate-90' : ''}`}>▶</span>
              <span className="text-sm">{td2.emoji}</span>
              <span className="text-zinc-300 font-semibold">{td2.label.replace(/^[^ ]+ /, '')}</span>
              <span className="text-faint">({node.metrics.count})</span>
              <span className="font-mono text-[10px] text-faint ml-1">{fM(node.metrics.spend)}</span>
              <span className="text-[9px] text-muted font-normal ml-2">{td2.desc}</span>
            </div>
          </div>
        </div>
      );
    } else {
      // Fallback: generic collapsible header
      rows.push(
        <div key={fullKey} onClick={() => toggleKey(fullKey)}
          className="cursor-pointer border-b border-border-faint hover:bg-white/[.02]">
          <div className="px-0 py-0">
            <div className="flex items-center gap-2 text-[11px] font-semibold text-subtle px-3.5 py-2"
              style={{ paddingLeft: pl }}>
              <span className={`transition-transform duration-200 text-[9px] ${isExpanded ? 'rotate-90' : ''}`}>▶</span>
              <span>{node.label}</span>
              <span className="text-faint">({node.metrics.count})</span>
              <span className="font-mono text-[10px] text-faint ml-1">{fM(node.metrics.spend)}</span>
            </div>
          </div>
        </div>
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

  const COACH_THEMES: Record<string, { emoji: string; label: string; gradient: string; borderColor: string; bgColor: string; textColor: string; desc: string }> = {
    BLITZ: { emoji: '🔥', label: 'Blitz', gradient: 'from-amber-500/20 via-orange-500/10 to-transparent', borderColor: 'border-amber-500/40', bgColor: 'bg-amber-500/10', textColor: 'text-amber-400', desc: 'Scale up, push volume, promote aggressively' },
    COOLDOWN: { emoji: '❄️', label: 'Cooldown', gradient: 'from-cyan-500/20 via-blue-500/10 to-transparent', borderColor: 'border-cyan-500/40', bgColor: 'bg-cyan-500/10', textColor: 'text-cyan-400', desc: 'Wind down bids, cascade -30%/day' },
    GUARDIAN: { emoji: '🛡', label: 'Guardian', gradient: 'from-emerald-500/12 via-zinc-500/5 to-transparent', borderColor: 'border-emerald-500/30', bgColor: 'bg-emerald-500/8', textColor: 'text-emerald-400', desc: 'Protect margins, strict ROAS' },
  };

  return (
    <div className="animate-in">
      {/* ── Coach Mode Banner ── */}
      {activeCoachMode && COACH_THEMES[activeCoachMode] && (() => {
        const theme = COACH_THEMES[activeCoachMode];
        const activeFamilies = Object.entries(familyCoachModes).filter(([, v]) => v.mode === activeCoachMode);
        const guardianFamilies = Object.entries(familyCoachModes).filter(([, v]) => v.mode === 'GUARDIAN');
        return (
          <div className={`mb-3 px-4 py-2.5 rounded-xl border ${theme.borderColor} bg-gradient-to-r ${theme.gradient} flex items-center gap-3`}>
            <span className="text-xl">{theme.emoji}</span>
            <div>
              <span className={`text-sm font-bold ${theme.textColor}`}>{theme.label} Mode</span>
              <span className="text-[11px] text-subtle ml-2">{theme.desc}</span>
            </div>
            {activeCoachMode !== 'GUARDIAN' && (
              <div className="ml-auto flex items-center gap-2">
                {activeFamilies.map(([fam, info]) => (
                  <span key={fam} className={`text-[10px] font-semibold px-2 py-0.5 rounded-full ${theme.bgColor} ${theme.textColor} border ${theme.borderColor}`}>
                    {fam} · {info.occasion}
                  </span>
                ))}
                {guardianFamilies.length > 0 && (
                  <span className="text-[10px] font-semibold px-2 py-0.5 rounded-full bg-emerald-500/8 text-emerald-400 border border-emerald-500/30">
                    🛡 {guardianFamilies.map(([f]) => f).join(', ')}
                  </span>
                )}
              </div>
            )}
          </div>
        );
      })()}

      <PageHeader title="Detailed Actions" subtitle="Every action justified by measures" />

      {/* ── Coach Strategy Panel ── */}
      {(() => {
        // Filter coach terms by header parent & product filters
        let coachTerms = data.actions || [];
        if (effectiveFam) coachTerms = coachTerms.filter(ct => ct.parent_name === effectiveFam);
        if (filters.product) coachTerms = coachTerms.filter(ct => ct.asin === filters.product);
        // Determine dominant mode from filtered data
        const activeMode = coachFilter !== 'all' ? coachFilter : dominantMode(coachTerms);
        const activeOccasion = coachTerms.find(ct => ct.coach_mode === activeMode && ct.active_occasion)?.active_occasion;
        return (
          <CoachStrategyPanel
            strategy={data.coach_strategy || []}
            actions={coachTerms}
            activeMode={activeMode}
            activeFilter={strategicTaskFilter}
            onFilterChange={setStrategicTaskFilter}
            activeOccasion={activeOccasion}
          />
        );
      })()}

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
          {strategies.map(s => <option key={s!} value={s!}>{humanizeStratId(s!)}</option>)}
        </select>
        <label className="text-[10px] text-subtle uppercase tracking-wider font-semibold ml-2">Family</label>
        <select value={famFilter} onChange={e => setFamFilter(e.target.value)} className="bg-[#09090b] border border-border text-white px-2.5 py-1.5 rounded-lg text-[11px] focus:outline-none focus:border-blue-500">
          <option value="all">All</option>
          {fams.map(f => <option key={f!} value={f!}>{f}</option>)}
        </select>
        <label className="text-[10px] text-subtle uppercase tracking-wider font-semibold ml-2">Coach</label>
        <select value={coachFilter} onChange={e => setCoachFilter(e.target.value)} className="bg-[#09090b] border border-border text-white px-2.5 py-1.5 rounded-lg text-[11px] focus:outline-none focus:border-blue-500">
          <option value="all">All</option>
          <option value="BLITZ">🔥 Blitz</option>
          <option value="COOLDOWN">❄️ Cooldown</option>
          <option value="GUARDIAN">🛡 Guardian</option>
        </select>
        <label className="text-[10px] text-subtle uppercase tracking-wider font-semibold ml-2">Group by</label>
        <select value={hierarchy} onChange={e => { setHierarchy(e.target.value as any); setExpandedKeys(new Set()); }} className="bg-[#09090b] border border-border text-white px-2.5 py-1.5 rounded-lg text-[11px] focus:outline-none focus:border-blue-500">
          <option value="campaign">📂 Campaign</option>
          <option value="action">⚡ Action</option>
          <option value="action_type">🏷️ Action Type</option>
          <option value="strategy">🎯 Strategy</option>
          <option value="branch">🔀 Branch ID</option>
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
        <button
          onClick={() => setHideMonitor(h => !h)}
          className={`flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-[11px] font-semibold transition-colors ${
            hideMonitor
              ? 'text-zinc-500 border border-zinc-700 hover:border-zinc-500 hover:text-zinc-300'
              : 'bg-zinc-500/15 text-zinc-300 border border-zinc-500/30 hover:bg-zinc-500/25'
          }`}
          title={hideMonitor ? 'Monitor/Keep actions are hidden — click to show' : 'Showing all actions including Monitor/Keep — click to hide'}
        >
          <Eye size={12} />
          {hideMonitor ? 'Show Monitor' : 'Hide Monitor'}
        </button>
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
        <Badge variant="red">{negateCount} negate · {fM(negateSpend)}</Badge>
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
            const fam = getFamily(r.product_short_name || r.parent_name || null);
            if (fam) byFam[fam] = (byFam[fam] || 0) + (r.spend || 0);
          }
          return Object.entries(byFam)
            .map(([family, total]) => ({ family, total }))
            .filter(f => f.total > 0)
            .sort((a, b) => b.total - a.total);
        })();
        // Per-family bucket breakdown (from action rows)
        const famBuckets = (() => {
          const families = [...new Set([...famTotalSpend.map(f => f.family), ...filtered.map(a => getFamily(a.product_short_name)).filter(Boolean)])] as string[];
          return families.map(fam => {
            const famActions = filtered.filter(a => getFamily(a.product_short_name) === fam);
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
                <div className="text-[11px] font-semibold text-subtle uppercase tracking-wider mb-3">Per Family Breakdown <span className="text-faint normal-case font-normal">· {effectiveCoachMode} mode</span></div>
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
                      <FamilyPlanActuals
                        planTarget={planTargets.get(f.family)}
                        actual={famActuals.get(f.family)}
                        mode={famModes.get(f.family) ?? effectiveCoachMode}
                        planMoLabel={planMoLabel}
                      />
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

      {/* ── 📋 Unified Daily Queue ── */}
      {unifiedTree.length > 0 && (
        <div className="border border-border rounded-xl bg-card overflow-hidden mb-4">
          <div className="flex items-center gap-3 px-4 py-2.5 border-b border-border bg-surface/50">
            <span className="text-base">📋</span>
            <span className="text-[11px] font-bold uppercase tracking-wider text-white/90">Daily Queue</span>
            <span className="text-[10px] font-mono text-muted">{totalQueueCount} items · {fM(totalQueueSpend)}</span>
            <span className="text-[9px] text-subtle ml-auto">Campaign → Type → Term / Target</span>
          </div>
          <div className="divide-y divide-border-faint">
              {unifiedTree.flatMap(node => renderNode(node, 0, ''))}
          </div>
        </div>
      )}
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

function ActionRowComponent({ action: a, cd, prediction: pred, expanded, onToggle, matchAction, indent, complexityBadge, onIntelligenceClick, isIntelExpanded, doQueue }: { action: ActionRow; cd?: CoachDecisionRow; prediction?: StrategicPrediction; expanded: boolean; onToggle: () => void; matchAction: (a: { search_term?: string; experiment_id?: string; net_roas?: number; cpc?: number; conv_rate?: number }) => { gt: GroundTruth; supported: boolean }[]; indent?: number; complexityBadge?: number; onIntelligenceClick?: () => void; isIntelExpanded?: boolean; doQueue?: ReturnType<typeof useDoQueue> }) {
  const inQ = doQueue?.items.some(q => q.search_term === a.search_term && q.campaign_id === a.campaign_id && q.targeting === (a.targeting || '')) ?? false;

  // Measure pill helpers — always rendered; null OR (0+0) = N/A
  const roasPill = (label: string, tooltip: string, roas: number | null | undefined, orders: number | null | undefined, dateRange?: string) => {
    // No data = null means no spend in the period; roas=0 means spend exists but no profit → show 0.0
    const noData = roas == null;
    const r = noData ? 0 : roas;
    const color = noData ? 'text-zinc-500 border-zinc-700/40 bg-zinc-800/30'
      : r >= 1.0 ? 'text-emerald-400 border-emerald-500/25 bg-emerald-500/8'
      : r >= 0.5 ? 'text-amber-400 border-amber-500/25 bg-amber-500/8'
      : 'text-red-400 border-red-500/25 bg-red-500/8';
    const tip = noData ? `${tooltip}: No data${dateRange ? ` (${dateRange})` : ''}` : `${tooltip}: Net ROAS ${r.toFixed(2)}${orders != null && orders > 0 ? `, ${orders} units` : ''}${dateRange ? ` (${dateRange})` : ''}`;
    return (
      <span className={`inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded border text-[9px] font-mono ${color}`} title={tip}>
        <span className="text-zinc-500 font-sans text-[8px]">{label}</span>
        {noData ? <span className="text-zinc-600">N/A</span> : r.toFixed(1)}
        {!noData && orders != null && orders > 0 && <span className="text-zinc-500">({orders} units)</span>}
      </span>
    );
  };

  const volPill = (label: string, tooltip: string, value: number | null | undefined) => {
    const noData = value == null || value === 0;
    const tip = noData ? `${tooltip}: No data` : `${tooltip}: ${fmt(value)}`;
    const cls = noData ? 'text-zinc-500 border-zinc-700/40 bg-zinc-800/30' : 'text-blue-400 border-blue-500/25 bg-blue-500/8';
    return (
      <span className={`inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded border text-[9px] font-mono ${cls}`} title={tip}>
        <span className="text-zinc-500 font-sans text-[8px]">{label}</span>
        {noData ? <span className="text-zinc-600">N/A</span> : value >= 1000 ? `${(value / 1000).toFixed(1)}K` : fmt(value)}
      </span>
    );
  };

  const monPill = (label: string, tooltip: string, value: number | null | undefined, hasSiblingData?: boolean) => {
    // For SQP $: show $0 when there IS SQP data but no sales; show N/A when no SQP data at all
    const noData = value == null || (value === 0 && !hasSiblingData);
    const tip = noData ? `${tooltip}: No data` : `${tooltip}: ${fM(value)}`;
    const cls = noData ? 'text-zinc-500 border-zinc-700/40 bg-zinc-800/30' : 'text-purple-400 border-purple-500/25 bg-purple-500/8';
    return (
      <span className={`inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded border text-[9px] font-mono ${cls}`} title={tip}>
        <span className="text-zinc-500 font-sans text-[8px]">{label}</span>
        {noData ? <span className="text-zinc-600">N/A</span> : fM(value)}
      </span>
    );
  };

  // Format date as "YY.M.D" (e.g. "25.12.5")
  const shortDate = (d: string | null) => {
    if (!d) return '?';
    const p = d.split('-');
    return `${p[0].slice(2)}.${parseInt(p[1])}.${parseInt(p[2])}`;
  };

  // Build LY Peak tooltip with occasion context
  const lyTip = a.occasion && a.occasion !== 'NONE' ? `Last Year ${a.occasion} Peak` : 'Last Year Peak';

  // Compute date ranges for ROAS windows (Pacific time, matching BigQuery)
  const today = new Date();
  const fmtD = (d: Date) => `${d.getMonth() + 1}.${d.getDate()}`;
  const daysAgo = (n: number) => { const d = new Date(today); d.setDate(d.getDate() - n); return d; };
  const dr3d = `${fmtD(daysAgo(3))}–${fmtD(daysAgo(1))}`;
  const dr7d = `${fmtD(daysAgo(7))}–${fmtD(daysAgo(1))}`;
  const dr4w = `${fmtD(daysAgo(31))}–${fmtD(daysAgo(4))}`;
  const dr12m = a.lt_first_seen && a.lt_last_seen ? `${shortDate(a.lt_first_seen)}–${shortDate(a.lt_last_seen)}` : undefined;

  // SQP sibling check: has ANY SQP data?
  const hasSqpData = (a.sqp_amazon_search_volume_8w != null && a.sqp_amazon_search_volume_8w > 0) ||
                     (a.sqp_clicks_8w != null && a.sqp_clicks_8w > 0);

  return (
    <>
      <div onClick={onToggle} className="flex items-center gap-2 px-3 py-2 hover:bg-white/[.02] cursor-pointer transition-colors"
        style={{ paddingLeft: indent }}>
        {/* Keyword / Target name */}
        <div className="flex items-center gap-1.5 min-w-[180px] shrink-0">
          <strong className="text-blue-400 text-[12px] truncate max-w-[200px]">{a.action_type === 'BUDGET' ? (a.campaign_name || '--') : (a.search_term || a.targeting || '--')}</strong>
          {complexityBadge != null && complexityBadge >= 3 && (
            <button
              onClick={(e) => { e.stopPropagation(); onIntelligenceClick?.(); }}
              className={`flex items-center gap-0.5 text-[9px] px-1.5 py-0.5 rounded-full border font-mono font-bold transition-all cursor-pointer ${
                isIntelExpanded
                  ? 'bg-indigo-500/20 border-indigo-500/40 text-indigo-400'
                  : complexityBadge >= 5
                    ? 'bg-red-500/10 border-red-500/25 text-red-400 hover:bg-red-500/20'
                    : 'bg-amber-500/10 border-amber-500/25 text-amber-400 hover:bg-amber-500/20'
              }`}
              title={`${complexityBadge} campaigns targeting this keyword — click for intelligence`}
            >
              {complexityBadge >= 5 ? '🛡️' : '⚠️'} {complexityBadge}
            </button>
          )}
        </div>

        {/* Action badge + DO queue button */}
        <div className="flex items-center gap-1 shrink-0">
          <span onClick={e => e.stopPropagation()}>
            <button className={`p-0.5 rounded transition-colors ${inQ ? 'text-emerald-400' : 'text-zinc-500 hover:text-white'}`}
              onClick={() => { if (inQ || !doQueue) return; doQueue.addItem({ search_term: a.search_term || '', action: a.action || '', campaign: a.campaign_name || '', campaign_id: a.campaign_id || '', ad_group_id: (a as any).ad_group_id || '', targeting: a.targeting || '', keyword_id: a.keyword_id || '', match_type: a.match_type || '', target_spend_8w: a.ads_spend_4w || 0, target_orders_8w: a.ads_orders_4w || 0, target_net_roas_8w: a.ads_net_roas_4w || 0, current_bid: a.current_bid ?? null, recommended_bid: a.recommended_bid ?? null, campaign_type: a.campaign_type || '', product: a.product_short_name || '', spend: a.ads_spend_4w || 0, orders: a.ads_orders_4w || 0, cpc: a.ads_cpc_4w || 0, conv_rate: a.ads_cvr_pct_4w || 0, current_budget: a.current_budget ?? null, recommended_budget: a.recommended_budget ?? null }); }}
              title={inQ ? 'Already in DO queue' : 'Add to DO queue'}
            >{inQ ? <Check size={13} /> : <Plus size={13} />}</button>
          </span>
          <ActionBadge action={a.action_type} />
          {a.decision_branch_id && (
            <span className="text-[9px] font-mono text-zinc-600 truncate max-w-[60px]" title={`Branch: ${a.decision_branch_id}`}>
              {a.decision_branch_id}
            </span>
          )}
        </div>

        {/* Measure pills */}
        <div className="flex flex-wrap items-center gap-1 flex-1 min-w-0">
          {roasPill('3d', 'Ads Net ROAS — Last 3 Days', a.ads_net_roas_3d, a.ads_units_3d, dr3d)}
          {roasPill('7d', 'Ads Net ROAS — Last 7 Days', a.ads_net_roas_1w, a.ads_units_1w, dr7d)}
          {roasPill('4w', 'Ads Net ROAS — Last 4 Weeks', a.ads_net_roas_4w, a.ads_units_4w, dr4w)}
          {roasPill('12m', 'Ads Net ROAS — All Campaigns × Term × Product (12 months)', a.lt_net_roas, a.lt_units, dr12m)}
          {roasPill('LY', lyTip, a.ly_net_roas, a.ly_units)}
          {roasPill('Dec', 'Ads Net ROAS — Q4 December Peak', a.q4_peak_net_roas, a.q4_peak_units)}
          {/* SQP pills: only for term/target level, not campaign-level BUDGET actions */}
          {a.action_type !== 'BUDGET' && volPill('SQP Vol', 'SQP Amazon Search Volume — Last 8 Weeks', a.sqp_amazon_search_volume_8w)}
          {a.action_type !== 'BUDGET' && volPill('SQP Cl', 'SQP Clicks (our product) — Last 8 Weeks', a.sqp_clicks_8w)}
          {a.action_type !== 'BUDGET' && monPill('SQP $', 'SQP Sales (our product) — Last 8 Weeks', a.sqp_sales_8w, hasSqpData)}
          
          {volPill('Cl 7d', 'Ads Clicks — Last 7 Days', a.ads_clicks_1w)}
          {volPill('Impr 7d', 'Ads Impressions — Last 7 Days', a.ads_impressions_1w)}
          {monPill('Spend 7d', 'Ads Spend — Last 7 Days', a.ads_spend_1w)}
          {monPill('CPC 7d', 'Ads Cost Per Click — Last 7 Days', a.ads_cpc_1w)}
          
          {/* Data period pill */}
          {a.lt_first_seen && (
            <span className="inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded border text-[9px] font-mono text-zinc-400 border-zinc-700/40 bg-zinc-800/20"
              title={`Ads data range: ${a.lt_first_seen} to ${a.lt_last_seen || '?'}`}>
              <span className="text-zinc-500 font-sans text-[8px]">📅</span>
              {shortDate(a.lt_first_seen)}–{shortDate(a.lt_last_seen)}
            </span>
          )}
        </div>

        {/* Expand indicator */}
        <span className={`text-[9px] text-zinc-500 transition-transform shrink-0 ${expanded ? 'rotate-90' : ''}`}>▶</span>
      </div>

      {/* Expanded detail panel */}
      {expanded && (
        <div className="px-3.5 py-2.5 bg-inset text-[11px] text-subtle leading-relaxed border-t border-border-faint" style={{ paddingLeft: (indent || 12) + 8 }}>
          <strong className="text-muted">Campaign:</strong> {a.campaign_name || '--'}
          <br />
          <strong className="text-muted">Reason:</strong> {a.reason || '--'}<br />
          <strong className="text-muted">Margin/unit:</strong> {fM(a.margin_per_unit)}
          {a.strategy_id && <> · <strong className="text-muted">Strategy:</strong> {a.strategy_id}</>}
          {a.current_bid != null && <> · <strong className="text-muted">Bid:</strong> {fCpc(a.current_bid)} → {a.recommended_bid != null ? fCpc(a.recommended_bid) : '—'}</>}
          <DecisionTreeViewer row={a} />

          {/* Strategic Prediction */}
          {pred && (() => {
            const sc = SIGNAL_COLORS[pred.strategic_signal] || defaultSignalColor;
            return (
              <div className="mt-2.5 pt-2.5 border-t border-border-faint">
                <div className="flex items-center gap-2 mb-1.5">
                  <span className="text-[10px] uppercase tracking-wider text-faint font-bold">Strategic Prediction</span>
                  <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold ${sc.bg} ${sc.text}`}>
                    {sc.emoji} {pred.strategic_signal.replace(/_/g, ' ')}
                  </span>
                  <span className="font-mono text-[10px] text-zinc-400">
                    Predicted Net ROAS: <strong className={pred.predicted_net_roas >= 1 ? 'text-emerald-400' : pred.predicted_net_roas >= 0.7 ? 'text-amber-400' : 'text-red-400'}>{pred.predicted_net_roas.toFixed(2)}</strong>
                  </span>
                </div>
              </div>
            );
          })()}
        </div>
      )}
    </>
  );
}

