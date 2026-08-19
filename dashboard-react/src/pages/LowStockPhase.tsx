import { Fragment, useEffect, useMemo, useRef, useState } from 'react';
import { cubeLoadWithMeta } from '../hooks/useCubeData';
import { useDoQueue, findQueuedBid, findQueuedBudget, type DoQueueItem } from '../hooks/useDoQueue';

// Weekly Run — criteria 1: "Low stock". Sits ABOVE Launch exemption and Revivals in the phase
// stack (Ori 2026-08-13: "low stock (this gets prioritised)").
//
// v3 (Ori 2026-08-13): "table format of critical low stock use the last day, 7 days window format."
// The money columns are the SHORT windows the rule actually judges — last day and the w-day window
// (7, or 3 in peak, from V_PEAK_WINDOW_RULE). The settled 28d column stays as context (the slow read
// is one glance away, never the trigger). The variation pipeline table survives only behind the
// collapsed "inventory detail" toggle.
//
// v4 (Ori 2026-08-13): "table format should be like portfolio 80/20; there should be actions and the
// why must be short and readable." The move table now carries the ELEVEN columns of
// OobBudgetPhase.tsx, in its order and its visual vocabulary — see the block above MoveTable for the
// slot-by-slot mapping. Two consequences worth stating up front:
//   · EVERY row carries an action and a → $, campaign rows included. They used to render blank.
//   · THE WHY IS ONE SHORT CLAUSE, on one line, no wrap. It is `action_reason_short` — written that
//     short IN THE VIEW (v27.62), not truncated here. The paragraph-length `action_reason` is the
//     same verdict in full and is the cell's title= tooltip.
//
// EVERY DECISION IS THE VIEW'S. Every verdict, threshold, dollar figure, rank, days-bought number
// and suggested value is decided in V_LOW_STOCK_ADS. This file must never compare a metric to a
// threshold, derive a risk state, decide whether a row is proposable, re-word or SHORTEN a reason,
// or do inventory/ads arithmetic. It renders `action`, both reason strings, `profit1d`/`profitW` and
// the suggested values as the view emits them.
//
// v27.63 (Ori 2026-08-13: "add actions and apply all button to revuvals, low stock, launch
// exemption") — the panel now WRITES to the DO queue, last of the three (Revivals and Launch
// exemption shipped first). Same reasoning as there: a decision you have to retype by hand is not a
// decision surface, it is a reading exercise. Nothing queues itself — every queue is a click, and
// what queues is exactly what the view priced: TARGET rows with is_proposal + suggested_bid become
// REDUCE_BID, CAMPAIGN rows with is_proposal + suggested_budget become BUDGET_CHANGE. FAMILY and
// ASIN rows never carry an affordance, and waste parks stay unqueueable from here (no park verb in
// this queue — a park is still Ori's hand move). THE CAPPED PAIRING travels with the queue: a
// capped campaign's suggested_budget is already budget − SUM(its proposed target cuts) — verified
// in the view's camp_agg before this was wired — so a budget row and its bid cuts move together;
// see the pairing block above the toggles for exactly which linkage fires when.
//
// ⚠️ The two short windows are UNSETTLED — SP sales accrue to D+7, SB to D+14, so a fresh day
// understates GP-ROAS. The guard is in the RULE, not here: a cut needs BOTH windows to fail. The
// column tooltips say so, and the view publishes profit1d / profitW as YES | NO | NO_SPEND so the
// panel never has to infer which of the three happened.
//
// v3 also changes what the header means: the risk grade is now driven by ACTUAL RECENT SALES
// (velocityActual = fastest of the 7/14/30-day trailing rates), with the FORECAST reading published
// beside it. Where the two disagree the header shows both — never one silently chosen.
//
// Row kinds consumed here: FAMILY (the one-line context header + inventory rollup), ASIN (the
// collapsed inventory detail), TARGET (the money), CAMPAIGN (optional — the paired budget cut that
// must accompany a target cut inside a CAPPED campaign, where the budget is spent regardless and
// parking one target only re-routes its dollars to its neighbours and sells the stock FASTER).

type Row = {
  rowId: string; rowKind: string; family: string; riskState: string; riskRank: number;
  riskReason: string; snapshotDate: string | null;
  asin: string | null; product: string | null;
  fbaQty: number | null; awdQty: number | null; sellableQty: number | null;
  inTransitQty: number | null; inTransitAwdQty: number | null;
  mfrReadyQty: number | null; inProductionQty: number | null;
  upstreamQty: number | null; totalPipelineQty: number | null;
  velocityUsed: number | null; velocityForecast: number | null; velocity30d: number | null;
  velocity14d: number | null; velocity7d: number | null;
  velocityActual: number | null; velocityActualBasis: string | null;
  daysOfCover: number | null; daysOfCoverAvail: number | null; coverBasis: string | null;
  // the FORECAST leg, published alongside the actual-sales grade (v27.59)
  daysOfCoverForecast: number | null; daysOfCoverAvailForecast: number | null;
  coverBasisForecast: string | null; riskStateForecast: string | null;
  bridgeGapDaysForecast: number | null; bindingCoverForecastDays: number | null;
  stockoutDate: string | null; poDeadline: string | null; tooLateToReplenish: boolean;
  fullLeadDays: number | null; bridgeGapDays: number | null;
  nextArrivalDate: string | null; daysToArrival: number | null; nextArrivalQty: number | null;
  seasonDemandUnits: number | null; seasonGapUnits: number | null;
  overduePendingQty: number | null; overduePendingOldestEta: string | null;
  units90d: number | null; familyUnitsSharePct: number | null;
  bindingAsin: string | null; bindingProduct: string | null;
  familySellableQty: number | null; familyVelocity: number | null;
  firstSaleDate: string | null; familyAgeMonths: number | null;
  campaigns: number | null; cappedCampaigns: number | null;
  campaignId: string | null; campaignName: string | null; channel: string | null;
  campaignBudget: number | null; isDefense: boolean; isCapped: boolean; daysCapped7d: number | null;
  keywordId: string | null; adGroupId: string | null; targetText: string | null; matchType: string | null;
  keywordState: string | null; currentBid: number | null; isPt: boolean; creativeType: string | null;
  settledThrough: string | null; settleDays: number | null;
  s28Clicks: number | null; s28Spend: number | null; s28Orders: number | null;
  s28Units: number | null; s28GpRoas: number | null;
  s90Clicks: number | null; s90Orders: number | null; s90GpRoas: number | null;
  // the SHORT windows the CRITICAL rule judges — unsettled by design, see the header
  lastAdsDay: string | null; wDays: number | null; inPeak: boolean; wDaysReason: string | null;
  d1Clicks: number | null; d1Spend: number | null; d1Orders: number | null; d1GpRoas: number | null;
  wClicks: number | null; wSpend: number | null; wOrders: number | null; wGpRoas: number | null;
  profit1d: string | null; profitW: string | null;   // YES | NO | NO_SPEND — the view's own verdict
  spendPerDay: number | null; unitsPerDay: number | null; pctOfFamilyVelocity: number | null;
  wSpendPerDay: number | null; wUnitsPerDay: number | null;
  targetClass: string | null; dollarsFreedPerDay: number | null;
  // v27.58: daysBoughtMax is GONE from the view. It was measured against the FAMILY's aggregate
  // cover (58d for LolliBall) while this header prints the BINDING variation's (26d) — two clocks
  // in one row. Both replacements are measured on the binding variation.
  daysBought: number | null;           // what THIS row's proposed action buys
  daysBoughtIfPaused: number | null;   // what a FULL pause would buy — the price of a protected winner
  dollarRank: number | null; proposalRank: number | null;
  // TWO reason strings, both written in V_LOW_STOCK_ADS (v27.62). `actionReason` is the full
  // paragraph and goes in the cell's title= tooltip; `actionReasonShort` is the same verdict as one
  // ~6-10 word clause and is the only thing the visible `why` column prints. The panel never
  // truncates or re-words either — shortening is a wording decision and wording lives in the view.
  action: string; actionReason: string | null; actionReasonShort: string | null;
  riskReasonShort: string | null;
  bidFloor: number | null; bidClampedToFloor: boolean | null;
  // ── the v27.59 short-window halve ──
  suggestedBid: number | null; suggestedBudget: number | null; isProposal: boolean | null;
  escalated: boolean; halveViable: boolean;
  launchExemptActive: boolean; launchExemptUntil: string | null;
  // the binding variation's OWN booked arrival, and the freshness warning when the shipments table
  // knows about a boat the daily inventory snapshot has not stamped yet
  bindingNextArrivalDate: string | null;
  arrivalFreshnessConflict: boolean; arrivalConflictNote: string | null;
  // family-level proposal roll-up (FAMILY rows) — every figure decided in the view
  escalatedTargets: number | null; parkTargets: number | null; bidCutTargets: number | null;
  notExecutableTargets: number | null;
  proposalTargets: number | null; proposalFreedPerDay: number | null; proposalDaysBought: number | null;
  protectedTargets: number | null; convDaysBoughtMax: number | null;
  budgetCutCampaigns: number | null; budgetCutPerDay: number | null;
  atRiskUnitsSharePctForecast: number | null;
};

const num = (v: unknown): number | null => (v == null || v === '' ? null : Number(v));
const str = (v: unknown): string | null => (v == null || v === '' ? null : String(v));
const bool = (v: unknown): boolean => v === true || v === 'true';
const boolOrNull = (v: unknown): boolean | null =>
  v == null || v === '' ? null : v === true || v === 'true';

const money = (v: number | null, d = 2) => (v == null ? '—' : `$${v.toFixed(d)}`);
const qty = (v: number | null) => (v == null ? '—' : v.toLocaleString());
const days = (v: number | null) => (v == null ? '—' : `${Math.round(v)}d`);
const shortDate = (d: string | null) => (d ? d.slice(5) : '—');

const riskCls = (s: string) =>
  s === 'CRITICAL' ? 'text-red-400' : s === 'THROTTLE' ? 'text-amber-400'
    : s === 'WATCH' ? 'text-sky-300' : 'text-emerald-400';

// Display only. 1.0 is the breakeven line of the metric itself (GP-ROAS = gross profit ÷ ad spend,
// tier COGS already charged), not a tuning threshold — the cut/keep decision is the view's.
const roasCls = (v: number | null) =>
  v == null ? 'text-faint' : v >= 1 ? 'text-emerald-400' : 'text-red-400';

const D = 'LowStockAds.';
const DIMS = [
  'rowId', 'rowKind', 'family', 'riskState', 'riskRank', 'riskReason', 'snapshotDate',
  'asin', 'product', 'fbaQty', 'awdQty', 'sellableQty', 'inTransitQty', 'inTransitAwdQty',
  'mfrReadyQty', 'inProductionQty', 'upstreamQty', 'totalPipelineQty',
  'velocityUsed', 'velocityForecast', 'velocity30d', 'velocity14d', 'velocity7d',
  'velocityActual', 'velocityActualBasis',
  'daysOfCover', 'daysOfCoverAvail', 'coverBasis', 'stockoutDate', 'poDeadline',
  'daysOfCoverForecast', 'daysOfCoverAvailForecast', 'coverBasisForecast', 'riskStateForecast',
  'bridgeGapDaysForecast', 'bindingCoverForecastDays', 'atRiskUnitsSharePctForecast',
  'tooLateToReplenish', 'fullLeadDays', 'bridgeGapDays',
  'nextArrivalDate', 'daysToArrival', 'nextArrivalQty', 'seasonDemandUnits', 'seasonGapUnits',
  'overduePendingQty', 'overduePendingOldestEta', 'units90d', 'familyUnitsSharePct',
  'bindingAsin', 'bindingProduct', 'bindingNextArrivalDate',
  'arrivalFreshnessConflict', 'arrivalConflictNote',
  'familySellableQty', 'familyVelocity', 'firstSaleDate', 'familyAgeMonths',
  'campaigns', 'cappedCampaigns',
  'escalatedTargets', 'parkTargets', 'bidCutTargets', 'notExecutableTargets',
  'proposalTargets', 'proposalFreedPerDay', 'proposalDaysBought',
  'protectedTargets', 'convDaysBoughtMax', 'budgetCutCampaigns', 'budgetCutPerDay',
  'campaignId', 'campaignName', 'channel', 'campaignBudget', 'isDefense', 'isCapped', 'daysCapped7d',
  'launchExemptActive', 'launchExemptUntil',
  'keywordId', 'targetText', 'matchType', 'keywordState', 'currentBid', 'isPt', 'creativeType',
  'settledThrough', 'settleDays',
  's28Clicks', 's28Spend', 's28Orders', 's28Units', 's28GpRoas',
  's90Clicks', 's90Orders', 's90GpRoas',
  'lastAdsDay', 'wDays', 'inPeak', 'wDaysReason',
  'd1Clicks', 'd1Spend', 'd1Orders', 'd1GpRoas',
  'wClicks', 'wSpend', 'wOrders', 'wGpRoas', 'profit1d', 'profitW',
  'spendPerDay', 'unitsPerDay', 'wSpendPerDay', 'wUnitsPerDay', 'pctOfFamilyVelocity',
  'targetClass', 'dollarsFreedPerDay', 'daysBought', 'daysBoughtIfPaused',
  'dollarRank', 'proposalRank', 'escalated', 'halveViable', 'action', 'actionReason',
].map(d => D + d);

// The priced move (`→ $`) and the backend's own "is this proposable" flag. These were fetched in a
// separate query while the view had not published them yet — a Cube query naming a dimension the
// schema does not have fails as a whole, and that must never take the stock panel down. They ship
// with V_LOW_STOCK_ADS v27.58 now, but the split is KEPT: V_LOW_STOCK_ADS is a ~50-70 s view on a
// cold cache and this second request is served from the same cube cache as the first, so it costs
// nothing — while still meaning a schema/view skew degrades the `→ $` column instead of the panel.
// v27.62 rides in this same tolerant request: `actionReasonShort` / `riskReasonShort` (the one-clause
// `why`) and `bidFloor` (the floor named in the bid tooltips — it was being read off Row without ever
// being fetched). Same reasoning as above: on a view/schema skew the panel falls back to the LONG
// reason string and a floor-less tooltip instead of the stock panel going dark.
// v27.63 adds `adGroupId`, the upload key (view emits it on TARGET rows as of Task 1.10). It rides
// here rather than in DIMS because it only matters to the queue: without it the → $ toggles simply
// never light up, which is the same graceful degradation the suggested values already have.
const EXT_DIMS = ['rowId', 'suggestedBid', 'suggestedBudget', 'isProposal', 'bidClampedToFloor',
  'bidFloor', 'actionReasonShort', 'riskReasonShort', 'adGroupId'].map(d => D + d);

// ── display maps (labels + colour only; the decision is the view's `action` string) ──────────────
const ACTION_LABEL: Record<string, string> = {
  STOCK_CUT_WASTE: 'park',
  STOCK_CUT_WASTE_AND_BUDGET: 'park + cut budget',
  // v27.59 — the CRITICAL rule: not profitable on the last day AND not on the w-day window → −50%
  STOCK_BID_HALVE: 'halve bid −50%',
  STOCK_BID_HALVE_AND_BUDGET: 'halve bid + cut budget',
  STOCK_AT_FLOOR: 'already at floor',
  STOCK_NO_BID: 'no bid to cut',
  STOCK_TRIM_STALLED: 'trim',
  STOCK_PROTECT: 'protect',
  STOCK_WATCH: 'watch',
  STOCK_NONE: 'no action',
  // CAMPAIGN grain — the paired budget lever
  STOCK_BUDGET_CUT: 'cut budget (paired)',
  STOCK_BUDGET_HOLD: 'budget unchanged',
};
const ACTION_CLS: Record<string, string> = {
  STOCK_CUT_WASTE: 'text-red-400',
  STOCK_CUT_WASTE_AND_BUDGET: 'text-amber-400',
  STOCK_BID_HALVE: 'text-red-400',
  STOCK_BID_HALVE_AND_BUDGET: 'text-red-400',
  STOCK_AT_FLOOR: 'text-faint',
  STOCK_NO_BID: 'text-faint',
  STOCK_TRIM_STALLED: 'text-amber-400',
  STOCK_PROTECT: 'text-emerald-400',
  STOCK_WATCH: 'text-faint',
  STOCK_NONE: 'text-faint',
  STOCK_BUDGET_CUT: 'text-amber-400',
  STOCK_BUDGET_HOLD: 'text-muted',
};
// Any action the view invents later still renders: STOCK_CUT_BELOW_BREAKEVEN → "cut below breakeven".
const actionLabel = (a: string) =>
  ACTION_LABEL[a] ?? (a ? a.replace(/^STOCK_/, '').toLowerCase().replace(/_/g, ' ') : '—');
const actionCls = (a: string) => ACTION_CLS[a] ?? 'text-amber-400';

// The `role` slot of the OobBudgetPhase row shape, filled with this panel's equivalent: the target's
// SETTLED CLASS, decided in the view (target_class). Colour + lowercase label only — no verdict, no
// threshold, no prose. An unknown class the view invents later still renders.
const CLASS_CLS: Record<string, string> = {
  CONVERTING: 'text-emerald-400', NON_CONVERTING: 'text-red-400', STALLED: 'text-amber-400',
  THIN: 'text-faint', DEFENSE: 'text-violet-400', ALREADY_OFF: 'text-faint',
};
const classLabel = (c: string | null) => (c ? c.toLowerCase().replace(/_/g, ' ') : '');
const classCls = (c: string | null) => (c ? CLASS_CLS[c] ?? 'text-muted' : 'text-faint');

// Grouping fallback for panels running against a view that has not published `is_proposal` yet.
// Not a threshold and not a verdict — these are the view's own "nothing proposed here" states.
const NOT_PROPOSED = new Set(['STOCK_PROTECT', 'STOCK_WATCH', 'STOCK_NONE', 'STOCK_BUDGET_HOLD',
  'STOCK_AT_FLOOR', 'STOCK_NO_BID', '']);
const isProposalRow = (r: Row) => (r.isProposal != null ? r.isProposal : !NOT_PROPOSED.has(r.action));

// ── the DO queue (v27.63, Ori: "add actions and apply all button to revuvals, low stock, launch
// exemption") ────────────────────────────────────────────────────────────────────────────────────
// `is_proposal` and the suggested values are the view's own columns and the ONLY test of
// actionability here — this file still compares no metric to any threshold. Direction is fixed
// upstream too: a stock move only ever cuts (bid × 0.5 floored, budget − freed), so REDUCE_BID and
// BUDGET_CHANGE are labels, not comparisons React makes. A proposal with no keyword/ad-group id
// cannot become a bulksheet row Amazon accepts, so it is not queueable — a guard, not a decision
// (the view stamps ad_group_id on every TARGET proposal as of v27.63; verified 0 missing).
const bidReady = (r: Row) =>
  r.rowKind === 'TARGET' && r.isProposal === true && r.suggestedBid != null
  && !!r.keywordId && !!r.adGroupId;
// CAMPAIGN budget rows key on Campaign ID alone — the view emits no ad-group on them, by design.
const budgetReady = (r: Row) =>
  r.rowKind === 'CAMPAIGN' && r.isProposal === true && r.suggestedBudget != null && !!r.campaignId;

// ── unified queued-state (Ori 2026-08-17: "if i approve an action in section or snapshot, visual
// should show both approve") ─────────────────────────────────────────────────────────────────────
// The ✓ reads from the CANONICAL queue identity — findQueuedBid (keyword_id, any bid action) /
// findQueuedBudget (campaign_id, any budget action) — never from "did this panel queue it". A key
// queued from ANY surface at ANY value renders queued here; when the queued value differs from
// this row's suggestion it is printed beside the ✓, so a decision made elsewhere reads as decided,
// never silently re-priced. Ours = an item at exactly this row's suggested value — the only thing
// bulk unapply may sweep. A foreign-valued item is removed only by its own row's click.
const ourBidItem = (items: DoQueueItem[], r: Row) => {
  const it = findQueuedBid(items, r.keywordId);
  return it && it.action === 'REDUCE_BID' && it.recommended_bid === r.suggestedBid ? it : undefined;
};
const ourBudgetItem = (items: DoQueueItem[], r: Row) => {
  const it = findQueuedBudget(items, r.campaignId);
  return it && it.action === 'BUDGET_CHANGE' && it.recommended_budget === r.suggestedBudget ? it : undefined;
};
// The queued value when it differs from the row's own suggestion by more than half a cent —
// under that is float noise, not a different decision.
const queuedDrift = (queuedVal: number | null | undefined, rowVal: number | null): number | null =>
  queuedVal != null && rowVal != null && Math.abs(queuedVal - rowVal) > 0.005 ? queuedVal : null;

const stockBidQueueItem = (r: Row): Omit<DoQueueItem, 'id' | 'addedAt'> => ({
  search_term: r.targetText ?? '', action: 'REDUCE_BID',
  campaign: r.campaignName ?? '', campaign_id: r.campaignId ?? '', ad_group_id: r.adGroupId ?? '',
  targeting: r.targetText ?? '', keyword_id: r.keywordId ?? '',
  match_type: (r.matchType ?? '').toUpperCase(),
  target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0,
  current_bid: r.currentBid, recommended_bid: r.suggestedBid,
  campaign_type: r.channel === 'SB' ? 'SPONSORED_BRANDS' : 'SPONSORED_PRODUCTS',
  product: r.isPt ? 'Product Targeting' : 'Keyword',
  spend: 0, orders: 0, cpc: 0, conv_rate: 0, source: 'COACH',
});
// Budget rows mirror OobBudgetPhase.queueBudget — the __budget__ search_term is what the DO page
// keys campaign-budget rows on.
const stockBudgetQueueItem = (r: Row): Omit<DoQueueItem, 'id' | 'addedAt'> => ({
  search_term: `__budget__${r.campaignId}`, action: 'BUDGET_CHANGE',
  campaign: r.campaignName ?? '', campaign_id: r.campaignId ?? '',
  ad_group_id: '', targeting: '', keyword_id: '', match_type: '',
  target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0,
  current_bid: null, recommended_bid: null,
  campaign_type: r.channel === 'SB' ? 'SPONSORED_BRANDS' : 'SPONSORED_PRODUCTS', product: '',
  spend: 0, orders: 0, cpc: 0, conv_rate: 0,
  current_budget: r.campaignBudget, recommended_budget: r.suggestedBudget, source: 'COACH',
});

// ── THE CAPPED PAIRING, on the queue side ────────────────────────────────────────────────────────
// Verified in V_LOW_STOCK_ADS camp_agg before this was wired: the CAMPAIGN row's suggested_budget
// is GREATEST(budget − SUM(that campaign's proposed target cuts), min budget) — the paired cut,
// ALREADY SUMMED in the view. So the two grains travel together, asymmetrically:
//   · queueing/unqueueing the BUDGET row queues/unqueues the bid cuts it was sized from — shipping
//     the budget cut without its target cuts starves the campaign: the bids still want the old
//     spend but the ceiling is gone.
//   · a TARGET cut may go alone — cutting a bid without the budget cut under-frees, never starves.
//   · unqueueing a TARGET whose campaign budget row is queued pulls the BUDGET row out too — the
//     budget number embeds that target's freed dollars, and shipping it without the cut it was
//     sized from starves the campaign twice.
type Dq = ReturnType<typeof useDoQueue>;

const toggleStockBid = (dq: Dq, r: Row, camp: Row | null) => {
  const it = findQueuedBid(dq.items, r.keywordId);
  if (!it) { dq.addItem(stockBidQueueItem(r)); return; }   // alone is safe: under-frees, never starves
  dq.removeItem(it.id);   // whatever its origin or value — the row's click undoes the row's key
  if (camp && budgetReady(camp)) {
    // OUR paired budget embeds this target's freed dollars, so it leaves no matter which view
    // queued the bid item just removed. A foreign-valued budget was sized elsewhere — it stays.
    const b = ourBudgetItem(dq.items, camp);
    if (b) dq.removeItem(b.id);
  }
};

const toggleStockBudget = (dq: Dq, camp: Row, paired: Row[]) => {
  const b = findQueuedBudget(dq.items, camp.campaignId);
  if (b) {
    dq.removeItem(b.id);   // whatever its origin or value
    // The sized-from cuts leave only when the removed budget IS this panel's own pair. A
    // foreign-valued budget was not sized from these cuts — and a bid cut left standing alone
    // under-frees, never starves, so it is safe to stay.
    if (b.action === 'BUDGET_CHANGE' && b.recommended_budget === camp.suggestedBudget) {
      for (const t of paired) { const it = ourBidItem(dq.items, t); if (it) dq.removeItem(it.id); }
    }
  } else {
    dq.addItem(stockBudgetQueueItem(camp));
    // queue the cuts the budget was sized from — skipping any keyword already queued from ANY view
    // (one lever, one key, one item: a second bid row on the same keyword would fork the decision)
    for (const t of paired) {
      if (!findQueuedBid(dq.items, t.keywordId)) dq.addItem(stockBidQueueItem(t));
    }
  }
};

function toRow(r: Record<string, unknown>): Row {
  const g = (k: string) => r[D + k];
  return {
    rowId: String(g('rowId') ?? ''), rowKind: String(g('rowKind') ?? ''),
    family: String(g('family') ?? ''), riskState: String(g('riskState') ?? 'OK'),
    riskRank: Number(g('riskRank') ?? 4), riskReason: String(g('riskReason') ?? ''),
    snapshotDate: str(g('snapshotDate')),
    asin: str(g('asin')), product: str(g('product')),
    fbaQty: num(g('fbaQty')), awdQty: num(g('awdQty')), sellableQty: num(g('sellableQty')),
    inTransitQty: num(g('inTransitQty')), inTransitAwdQty: num(g('inTransitAwdQty')),
    mfrReadyQty: num(g('mfrReadyQty')), inProductionQty: num(g('inProductionQty')),
    upstreamQty: num(g('upstreamQty')), totalPipelineQty: num(g('totalPipelineQty')),
    velocityUsed: num(g('velocityUsed')), velocityForecast: num(g('velocityForecast')),
    velocity30d: num(g('velocity30d')), velocity14d: num(g('velocity14d')),
    velocity7d: num(g('velocity7d')), velocityActual: num(g('velocityActual')),
    velocityActualBasis: str(g('velocityActualBasis')),
    daysOfCover: num(g('daysOfCover')), daysOfCoverAvail: num(g('daysOfCoverAvail')),
    coverBasis: str(g('coverBasis')),
    daysOfCoverForecast: num(g('daysOfCoverForecast')),
    daysOfCoverAvailForecast: num(g('daysOfCoverAvailForecast')),
    coverBasisForecast: str(g('coverBasisForecast')), riskStateForecast: str(g('riskStateForecast')),
    bridgeGapDaysForecast: num(g('bridgeGapDaysForecast')),
    bindingCoverForecastDays: num(g('bindingCoverForecastDays')),
    atRiskUnitsSharePctForecast: num(g('atRiskUnitsSharePctForecast')),
    stockoutDate: str(g('stockoutDate')),
    poDeadline: str(g('poDeadline')), tooLateToReplenish: bool(g('tooLateToReplenish')),
    fullLeadDays: num(g('fullLeadDays')), bridgeGapDays: num(g('bridgeGapDays')),
    nextArrivalDate: str(g('nextArrivalDate')), daysToArrival: num(g('daysToArrival')),
    nextArrivalQty: num(g('nextArrivalQty')),
    seasonDemandUnits: num(g('seasonDemandUnits')), seasonGapUnits: num(g('seasonGapUnits')),
    overduePendingQty: num(g('overduePendingQty')),
    overduePendingOldestEta: str(g('overduePendingOldestEta')),
    units90d: num(g('units90d')), familyUnitsSharePct: num(g('familyUnitsSharePct')),
    bindingAsin: str(g('bindingAsin')), bindingProduct: str(g('bindingProduct')),
    bindingNextArrivalDate: str(g('bindingNextArrivalDate')),
    arrivalFreshnessConflict: bool(g('arrivalFreshnessConflict')),
    arrivalConflictNote: str(g('arrivalConflictNote')),
    familySellableQty: num(g('familySellableQty')), familyVelocity: num(g('familyVelocity')),
    firstSaleDate: str(g('firstSaleDate')), familyAgeMonths: num(g('familyAgeMonths')),
    campaigns: num(g('campaigns')), cappedCampaigns: num(g('cappedCampaigns')),
    escalatedTargets: num(g('escalatedTargets')), parkTargets: num(g('parkTargets')),
    bidCutTargets: num(g('bidCutTargets')), notExecutableTargets: num(g('notExecutableTargets')),
    proposalTargets: num(g('proposalTargets')),
    proposalFreedPerDay: num(g('proposalFreedPerDay')),
    proposalDaysBought: num(g('proposalDaysBought')),
    protectedTargets: num(g('protectedTargets')), convDaysBoughtMax: num(g('convDaysBoughtMax')),
    budgetCutCampaigns: num(g('budgetCutCampaigns')), budgetCutPerDay: num(g('budgetCutPerDay')),
    campaignId: str(g('campaignId')), campaignName: str(g('campaignName')),
    channel: str(g('channel')), campaignBudget: num(g('campaignBudget')),
    isDefense: bool(g('isDefense')), isCapped: bool(g('isCapped')), daysCapped7d: num(g('daysCapped7d')),
    launchExemptActive: bool(g('launchExemptActive')), launchExemptUntil: str(g('launchExemptUntil')),
    keywordId: str(g('keywordId')), targetText: str(g('targetText')), matchType: str(g('matchType')),
    keywordState: str(g('keywordState')), currentBid: num(g('currentBid')), isPt: bool(g('isPt')),
    creativeType: str(g('creativeType')),
    settledThrough: str(g('settledThrough')), settleDays: num(g('settleDays')),
    s28Clicks: num(g('s28Clicks')), s28Spend: num(g('s28Spend')), s28Orders: num(g('s28Orders')),
    s28Units: num(g('s28Units')), s28GpRoas: num(g('s28GpRoas')),
    s90Clicks: num(g('s90Clicks')), s90Orders: num(g('s90Orders')), s90GpRoas: num(g('s90GpRoas')),
    lastAdsDay: str(g('lastAdsDay')), wDays: num(g('wDays')), inPeak: bool(g('inPeak')),
    wDaysReason: str(g('wDaysReason')),
    d1Clicks: num(g('d1Clicks')), d1Spend: num(g('d1Spend')), d1Orders: num(g('d1Orders')),
    d1GpRoas: num(g('d1GpRoas')),
    wClicks: num(g('wClicks')), wSpend: num(g('wSpend')), wOrders: num(g('wOrders')),
    wGpRoas: num(g('wGpRoas')), profit1d: str(g('profit1d')), profitW: str(g('profitW')),
    spendPerDay: num(g('spendPerDay')), unitsPerDay: num(g('unitsPerDay')),
    wSpendPerDay: num(g('wSpendPerDay')), wUnitsPerDay: num(g('wUnitsPerDay')),
    pctOfFamilyVelocity: num(g('pctOfFamilyVelocity')),
    targetClass: str(g('targetClass')), dollarsFreedPerDay: num(g('dollarsFreedPerDay')),
    daysBought: num(g('daysBought')), daysBoughtIfPaused: num(g('daysBoughtIfPaused')),
    dollarRank: num(g('dollarRank')), proposalRank: num(g('proposalRank')),
    escalated: bool(g('escalated')), halveViable: bool(g('halveViable')),
    action: String(g('action') ?? ''), actionReason: str(g('actionReason')),
    // filled from the second (tolerant) request — see EXT_DIMS
    actionReasonShort: null, riskReasonShort: null,
    bidFloor: null, bidClampedToFloor: null,
    suggestedBid: null, suggestedBudget: null, isProposal: null,
    adGroupId: null,
  };
}

// the whole pipeline in one cell — the stages Ori reads on the Supply page, in the same order
function Pipeline({ r }: { r: Row }) {
  const parts: string[] = [];
  if (r.fbaQty) parts.push(`FBA ${qty(r.fbaQty)}`);
  if (r.awdQty) parts.push(`AWD ${qty(r.awdQty)}`);
  if (r.inTransitQty) parts.push(`transit ${qty(r.inTransitQty)}`);
  if (r.inTransitAwdQty) parts.push(`→AWD ${qty(r.inTransitAwdQty)}`);
  if (r.mfrReadyQty) parts.push(`factory ${qty(r.mfrReadyQty)}`);
  if (r.inProductionQty) parts.push(`making ${qty(r.inProductionQty)}`);
  return (
    <span className="whitespace-nowrap" title="FBA at Amazon · AWD · In Transit · In Transit to AWD · Manufacturing ready · In Production — every stage, from FACT_INVENTORY_SNAPSHOT">
      <span className="text-muted">{qty(r.totalPipelineQty)}</span>
      <span className="text-faint text-label"> ({parts.join(' · ') || 'empty'})</span>
    </span>
  );
}

// ── one campaign and the targets under it, exactly as the view grouped and ranked them ───────────
type Group = { campaignId: string; camp: Row | null; head: Row; targets: Row[] };

function toGroups(targets: Row[], campRows: Map<string, Row>): Group[] {
  const byCamp = new Map<string, Row[]>();
  for (const t of targets) {
    const key = t.campaignId ?? '';
    const a = byCamp.get(key) ?? [];
    a.push(t);
    byCamp.set(key, a);
  }
  // proposal_rank is the view's own ordering — dollars freed first, days of cover bought second
  // (Ori 2026-08-13). dollar_rank is the older per-class spend order and is only a fallback.
  const rank = (r: Row) => r.proposalRank ?? r.dollarRank ?? 9e9;
  const groups: Group[] = [];
  for (const [campaignId, list] of byCamp) {
    list.sort((a, b) => rank(a) - rank(b) || (a.targetText ?? '').localeCompare(b.targetText ?? ''));
    const camp = campRows.get(campaignId) ?? null;
    groups.push({ campaignId, camp, head: camp ?? list[0], targets: list });
  }
  // campaign order follows the view's own rank on its best row — the panel never re-scores anything
  groups.sort((a, b) =>
    Math.min(...a.targets.map(rank)) - Math.min(...b.targets.map(rank))
    || (a.head.campaignName ?? '').localeCompare(b.head.campaignName ?? ''));
  return groups;
}

const SETTLE_TIP = (r: Row) =>
  `settled through ${r.settledThrough ?? '—'} — the window is cut at D+${r.settleDays ?? 7}`
  + ` (${r.channel ?? 'SP'}: SP sales accrue to D+7, SB to D+14), so nothing is condemned for orders`
  + ' that simply have not landed yet. Context here, never the trigger.';

// The two SHORT windows the CRITICAL rule judges. Deliberately UNSETTLED — the guard is that BOTH
// must fail, and that guard lives in the view, not here.
const SHORT_TIP = (r: Row, which: 'd1' | 'w') =>
  (which === 'd1'
    ? `LAST COMPLETE ADS DAY (${r.lastAdsDay ?? '—'}).`
    : `LAST ${r.wDays ?? 7} DAYS ending ${r.lastAdsDay ?? '—'}${r.inPeak ? ' — peak window' : ''}.`
      + (r.wDaysReason ? `\n${r.wDaysReason}` : ''))
  + '\nGP-ROAS = gross profit / ad spend, tier COGS already charged; 1.0 = breakeven AFTER product'
  + ' cost.\n⚠️ UNSETTLED: SP sales accrue to D+7, SB to D+14, so this understates ROAS. That is why'
  + ' a cut needs BOTH this window and the other one to fail.';

// YES / NO / NO_SPEND straight from the view — the panel never re-derives which one it is.
const PROFIT_MARK: Record<string, { s: string; cls: string; tip: string }> = {
  YES: { s: '✓', cls: 'text-emerald-400', tip: 'profitable on this window — 1.0x or better' },
  NO: { s: '✗', cls: 'text-red-400', tip: 'not profitable on this window — under 1.0x on real spend' },
  NO_SPEND: { s: '·', cls: 'text-faint', tip: 'no spend on this window — neither profitable nor a failure, and nothing to slow down' },
};

function Window({ clicks, orders, roas, spend, profit, tip }:
  { clicks: number | null; orders: number | null; roas: number | null; spend?: number | null;
    profit?: string | null; tip: string }) {
  const p = profit ? PROFIT_MARK[profit] : undefined;
  return (
    <span className="whitespace-nowrap" title={tip
      + `\n${clicks ?? 0} clicks · ${orders ?? 0} orders`
      + (spend != null ? ` · ${money(spend)} spend` : '')
      + (p ? `\n${p.tip}` : '')}>
      <span className="text-muted">{clicks ?? 0}c</span>
      <span className="text-faint"> · </span>
      <span className={roasCls(roas)}>{roas != null ? `${roas.toFixed(2)}x` : '—'}</span>
      {p && <span className={`${p.cls} pl-0.5`}>{p.s}</span>}
    </span>
  );
}

// (the "capped n/7" badge that used to hang off the campaign name is gone — capped is a COLUMN now,
// in the slot OobBudgetPhase gives to `dark`, so the constraint reads in the same place on both
// panels instead of hiding inside the name cell.)

// The launch exemption blocks ROAS-driven CAMPAIGN BUDGET cuts inside V_ADS_COACH. It is
// deliberately NOT applied to this criteria — a stock action is a supply constraint, not a ROAS
// verdict on a young family — so an exempt campaign shows the exemption NEXT TO a live proposal
// instead of quietly disappearing. The decision is the view's; this badge only reports it.
function ExemptBadge({ r }: { r: Row }) {
  if (!r.launchExemptActive) return null;
  return (
    <span className="text-violet-400 text-label"
      title={`launch-exempt until ${r.launchExemptUntil ?? '—'} — that exemption blocks ROAS-driven campaign budget cuts in the coach (CAMPAIGN_STOP, GUARDIAN_BUDGET_DECREASE and friends). It does NOT block this: the moves here are stock decisions taken on settled profit evidence, and "cut the bid to breakeven" is the launch doctrine's own verb — find the right bid, never loss-cut.`}>
      {' '}· launch-exempt
    </span>
  );
}

// ── THE ROW FORMAT ───────────────────────────────────────────────────────────────────────────────
// Ori 2026-08-13: "table format should be like portfolio 80/20; there should be actions and the why
// must be short and readable." The reference is OobBudgetPhase.tsx, whose header row is
//
//   item — campaign ▸ keyword ▸ term | dark | now $ | last day | prev-2d | CPC/target | role
//     | action | → $ | (spacer) | why
//
// Eleven columns, and this table now carries the SAME ELEVEN in the same order, the same alignment
// (everything right-aligned except item / role / action / why) and the same visual vocabulary. Where
// the measure differs the slot keeps its JOB rather than its label:
//
//   dark        → capped n/7 — the same question ("is this campaign budget-constrained?"), which is
//                 what decides whether a target cut frees money or just re-routes it
//   now $       → the money setting at this grain, with the daily run-rate riding in the same cell
//                 the way OOB packs "$40 bud · $39.87 spent"
//   prev-2d     → the w-day short window (7, or 3 in peak) — this panel's second window
//   CPC/target  → settled 28d, the slow reference read
//   role        → the target's SETTLED CLASS from the view (converting / non-converting / …)
//   (spacer)    → days bought. OOB uses that slot for its apply button; here the apply toggle rides
//                 the → $ value itself (v27.63), so the slot carries the number the action is
//                 ranked on.
//
// THE WHY IS ONE SHORT CLAUSE and it comes from the view as one short clause (action_reason_short,
// ~6-10 words, v27.62). The paragraph-length action_reason is the cell's title= TOOLTIP. The panel
// does not truncate, ellipsise, split or re-word either string — shortening is a wording decision
// and every word on this page is written in V_LOW_STOCK_ADS.
function MoveTable({ groups, extLive, pairedTargets }:
  { groups: Group[]; extLive: boolean; pairedTargets: Map<string, Row[]> }) {
  const doQueue = useDoQueue();
  // header labels come off the view's own window length — the panel does not know what 7 or 3 means
  const wd = groups.find(g => g.head.wDays != null)?.head.wDays ?? 7;
  const peak = groups.some(g => g.head.inPeak);
  return (
    <div className="overflow-x-auto">
      <table className="text-label font-mono border-collapse">
        <thead>
          <tr className="text-faint text-right">
            <th className="font-normal text-left px-2 py-0.5">item — campaign ▸ target</th>
            <th className="font-normal px-2" title="days out of budget in the last 7, from V_CAMPAIGN_CAP_STATE. A capped campaign spends its whole budget regardless, so a target cut there does not return money — it re-routes it to the targets beside it and sells the last stock FASTER. That is why those rows come paired with a budget cut.">capped</th>
            <th className="font-normal px-2" title="the current money setting at this level — campaign daily budget (bud) or target bid (bid) — and beside it what the row actually costs per day over the SHORT window, the same window the cut is decided on. The settled 28-day rate and the dollars the view says the move FREES are in the tooltip on the cell; they differ inside a capped campaign, where the budget is spent either way.">now $</th>
            <th className="font-normal px-2" title="LAST COMPLETE ADS DAY — clicks and GP-ROAS, with the view's own profitable/not/no-spend mark. ⚠️ Unsettled, so it understates ROAS; a cut needs this AND the window beside it to fail.">last day</th>
            <th className="font-normal px-2" title={`LAST ${wd} DAYS${peak ? ' (peak window — V_PEAK_WINDOW_RULE returns 3 in peak unless last year proved 7 is better)' : ''} — clicks and GP-ROAS, with the view's profitable/not/no-spend mark. This is the window the −50% rule is decided and sized on.`}>{wd}d{peak ? ' ᵖ' : ''}</th>
            <th className="font-normal px-2" title="SETTLED 28 days — context, never the trigger. Cut at D+7 (SP) / D+14 (SB) so orders have landed.">settled 28d</th>
            <th className="font-normal px-2 text-left" title="the target's settled class, decided in the view (target_class) — the job it does in this campaign's economy.">class</th>
            <th className="font-normal px-2 text-left">action</th>
            <th className="font-normal px-2" title={extLive
              ? 'the suggested new value for the setting in "now $" — priced by the view. Click it to queue or unqueue the move; a campaign budget cut and the target cuts it was sized from travel together.'
              : 'the view has not published suggested values yet — nothing is invented here'}>→ $</th>
            <th className="font-normal px-2" title="days of cover on the BINDING variation this move buys, from the view — the same clock the family header prints, not the family's aggregate cover. Upper bound: it assumes the stopped traffic loses 100% of its units with zero organic recapture, so the truth is smaller. 0.0 means the row sold nothing, so it buys no cover. On a protected row the bracket shows what a full pause WOULD buy — the option is priced, never proposed.">days bought</th>
            <th className="font-normal px-2 text-left">why</th>
          </tr>
        </thead>
        <tbody>
          {groups.map(g => (
            <Fragment key={g.campaignId || g.head.rowId}>
              <tr className="text-right border-t border-border/40">
                <td className="text-left px-2 py-0.5 text-body whitespace-nowrap">
                  {g.head.campaignName ?? g.campaignId}
                  <span className="text-faint text-label"> {g.head.channel}</span>
                  <ExemptBadge r={g.head} />
                </td>
                <td className={`px-2 whitespace-nowrap ${g.head.isCapped ? 'text-amber-400' : 'text-muted'}`}
                  title={g.head.isCapped
                    ? `out of budget ${g.head.daysCapped7d ?? 0} of the last 7 days — the budget is spent regardless, so every target cut below is paired with a budget cut`
                    : 'never out of budget in the last 7 days — the dollars a target cut frees genuinely leave'}>
                  {g.head.daysCapped7d != null ? `${g.head.daysCapped7d}/7` : '—'}
                </td>
                <td className="px-2 text-muted whitespace-nowrap"
                  title={g.camp ? `the campaign spends ${money(g.camp.wSpendPerDay)}/day over the last ${g.camp.wDays ?? 7} days (settled 28-day rate: ${money(g.camp.spendPerDay)}/day)`
                    + (g.camp.dollarsFreedPerDay != null ? ` · the proposed moves free ${money(g.camp.dollarsFreedPerDay)}/day` : '') : 'campaign daily budget'}>
                  {g.head.campaignBudget != null
                    ? <>{money(g.head.campaignBudget, 0)} <span className="text-faint">bud</span></>
                    : '—'}
                  {g.camp?.wSpendPerDay != null && <span className="text-faint"> · {money(g.camp.wSpendPerDay)}/d</span>}
                </td>
                <td className="px-2">
                  {g.camp && <Window clicks={g.camp.d1Clicks} orders={g.camp.d1Orders} roas={g.camp.d1GpRoas} spend={g.camp.d1Spend} tip={SHORT_TIP(g.camp, 'd1')} />}
                </td>
                <td className="px-2">
                  {g.camp && <Window clicks={g.camp.wClicks} orders={g.camp.wOrders} roas={g.camp.wGpRoas} spend={g.camp.wSpend} tip={SHORT_TIP(g.camp, 'w')} />}
                </td>
                <td className="px-2">
                  {g.camp && <Window clicks={g.camp.s28Clicks} orders={g.camp.s28Orders} roas={g.camp.s28GpRoas} spend={g.camp.s28Spend} tip={SETTLE_TIP(g.camp)} />}
                </td>
                {/* the class slot is blank on a campaign row, exactly as OOB leaves `role` blank on
                    its campaign row — a class is a property of a target, not of a campaign */}
                <td className="px-2" />
                <td className={`px-2 text-left whitespace-nowrap ${g.camp ? actionCls(g.camp.action) : 'text-faint'}`}>
                  {g.camp ? actionLabel(g.camp.action) : <span title="the view published no campaign row for this group — nothing is invented here">—</span>}
                </td>
                <td className="px-2 text-sky-300">
                  {(() => {
                    const c = g.camp;
                    if (c?.suggestedBudget == null) return <span className="text-faint">—</span>;
                    // queued from ANY surface at ANY value = queued here; a drifted value is
                    // printed beside the ✓ (the user's one decision must look decided everywhere)
                    const queued = findQueuedBudget(doQueue.items, c.campaignId);
                    const drift = queuedDrift(queued?.recommended_budget, c.suggestedBudget);
                    const mark = queued ? ` ✓${drift != null ? ` at ${money(drift)}` : ''}` : '';
                    if (!budgetReady(c)) return queued
                      ? (
                        <span className="text-emerald-300"
                          title={drift != null ? `queued from another view at ${money(drift)}` : 'queued'}>
                          {money(c.suggestedBudget)}{mark}
                        </span>
                      )
                      : <span>{money(c.suggestedBudget)}</span>;
                    const paired = pairedTargets.get(c.campaignId ?? '') ?? [];
                    const n = paired.length;
                    return (
                      <button onClick={() => toggleStockBudget(doQueue, c, paired)}
                        title={queued
                          ? (drift != null
                            ? `queued from another view at ${money(drift)} — click to remove it`
                            : `queued — click to remove. The ${n} bid cut${n === 1 ? '' : 's'} queued with it from this campaign leave${n === 1 ? 's' : ''} too: the budget number is the sum of those cuts, so the pair never ships half.`)
                          : `click to queue this paired budget cut AND the ${n} proposed bid cut${n === 1 ? '' : 's'} it was sized from — a capped campaign spends its budget regardless, so the cut only frees money when the budget comes down with it`}
                        className={queued ? 'text-emerald-300' : 'text-amber-300 hover:text-amber-200'}>
                        {money(c.suggestedBudget)}{mark}
                      </button>
                    );
                  })()}
                </td>
                <td className="px-2 whitespace-nowrap">
                  {g.camp?.daysBought != null
                    ? <span className={g.camp.daysBought > 0 ? 'text-sky-300' : 'text-faint'}>{g.camp.daysBought.toFixed(1)}d</span>
                    : <span className="text-faint">—</span>}
                </td>
                <td className="px-2 text-left text-faint whitespace-nowrap" title={g.camp?.actionReason ?? ''}>
                  {g.camp?.actionReasonShort ?? g.camp?.actionReason ?? ''}
                </td>
              </tr>
              {g.targets.map(r => (
                <tr key={r.rowId} className="text-right border-t border-border/20 bg-surface/40">
                  <td className="text-left pl-8 pr-2 py-0.5 text-muted whitespace-nowrap">
                    {/* The "· both windows failed" badge is GONE (v4). It repeated, in ~20 characters
                        of the widest column, what the two ✗ marks beside it already say and what the
                        short why now says in the view's own words — and it pushed the `why` column
                        off the right edge, which is the exact complaint this revision answers. The
                        escalation still reads: red ✗ on last day AND on the w-day window. */}
                    {r.targetText || <span className="text-faint">(no text)</span>}
                    <span className="text-faint text-label"> ({r.isPt ? 'PT' : (r.matchType ?? '').toLowerCase()})</span>
                  </td>
                  <td className="px-2" />
                  <td className="px-2 text-muted whitespace-nowrap"
                    title={`current bid${r.bidFloor != null ? ` · floor $${r.bidFloor.toFixed(2)} (${r.channel ?? 'SP'}${r.creativeType ? ` ${r.creativeType.toLowerCase()}` : ''}) — no trim may land below it` : ''}`
                      + `\nspends ${money(r.wSpendPerDay)}/day over the last ${r.wDays ?? 7} days (settled 28-day rate: ${money(r.spendPerDay)}/day)`
                      + (r.dollarsFreedPerDay != null ? ` · the view prices this move at ${money(r.dollarsFreedPerDay)}/day freed` : '')
                      + (r.isCapped ? ' · capped campaign: the dollars are only truly freed once the campaign budget comes down with it' : '')}>
                    {r.currentBid != null ? <>{money(r.currentBid)} <span className="text-faint">bid</span></> : '—'}
                    {r.wSpendPerDay != null && <span className="text-faint"> · {money(r.wSpendPerDay)}/d</span>}
                  </td>
                  <td className="px-2">
                    <Window clicks={r.d1Clicks} orders={r.d1Orders} roas={r.d1GpRoas} spend={r.d1Spend} profit={r.profit1d} tip={SHORT_TIP(r, 'd1')} />
                  </td>
                  <td className="px-2">
                    <Window clicks={r.wClicks} orders={r.wOrders} roas={r.wGpRoas} spend={r.wSpend} profit={r.profitW} tip={SHORT_TIP(r, 'w')} />
                  </td>
                  <td className="px-2">
                    <Window clicks={r.s28Clicks} orders={r.s28Orders} roas={r.s28GpRoas} spend={r.s28Spend} tip={SETTLE_TIP(r)} />
                  </td>
                  <td className={`px-2 text-left whitespace-nowrap ${classCls(r.targetClass)}`}>{classLabel(r.targetClass)}</td>
                  <td className={`px-2 text-left whitespace-nowrap ${actionCls(r.action)}`}>{actionLabel(r.action)}</td>
                  <td className="px-2 text-sky-300">
                    {(() => {
                      if (r.suggestedBid == null) return <span className="text-faint">—</span>;
                      const clampTip = `bid × 0.5, floored at $${(r.bidFloor ?? 0).toFixed(2)}`
                        + (r.bidClampedToFloor
                           ? ' — a straight 50% would land under the floor, so this is clamped up to it' : '');
                      // queued from ANY surface at ANY value = queued here; a drifted value is
                      // printed beside the ✓ (one decision, decided everywhere)
                      const queued = findQueuedBid(doQueue.items, r.keywordId);
                      const drift = queuedDrift(queued?.recommended_bid, r.suggestedBid);
                      const mark = queued ? ` ✓${drift != null ? ` at ${money(drift)}` : ''}` : '';
                      if (!bidReady(r)) return queued
                        ? (
                          <span className="text-emerald-300"
                            title={`${clampTip}\n${drift != null ? `queued from another view at ${money(drift)}` : 'queued'}`}>
                            {money(r.suggestedBid)}{mark}
                          </span>
                        )
                        : <span title={clampTip}>{money(r.suggestedBid)}</span>;
                      const budgetQueued = !!(g.camp && budgetReady(g.camp) && ourBudgetItem(doQueue.items, g.camp));
                      return (
                        <button onClick={() => toggleStockBid(doQueue, r, g.camp)}
                          title={clampTip + '\n' + (queued
                            ? (drift != null
                              ? `queued from another view at ${money(drift)} — click to remove it`
                              : (budgetQueued
                                ? "queued — click to remove. The campaign's paired budget cut leaves with it: that budget number was sized from this cut, and shipping the budget without it would starve the campaign twice."
                                : 'queued — click to remove'))
                            : 'click to queue this bid cut — on its own it under-frees, never starves, so it needs no budget row to ride along')}
                          className={queued ? 'text-emerald-300' : 'text-amber-300 hover:text-amber-200'}>
                          {money(r.suggestedBid)}{mark}
                        </button>
                      );
                    })()}
                  </td>
                  <td className="px-2 whitespace-nowrap">
                    {r.daysBought != null
                      ? <span className={r.daysBought > 0 ? 'text-sky-300' : 'text-faint'}>{r.daysBought.toFixed(1)}d</span>
                      : <span className="text-faint" title="the view did not price this one — this target carries too much of the family's velocity for a rate model to answer honestly">not priced</span>}
                    {r.action === 'STOCK_PROTECT' && r.daysBoughtIfPaused != null && r.daysBoughtIfPaused > 0 && (
                      <span className="text-faint text-label"
                        title="what pausing this protected target WOULD buy. The option is priced, never proposed — cutting a real winner to save stock is a call only you make.">
                        {' '}({r.daysBoughtIfPaused.toFixed(1)}d if paused)
                      </span>
                    )}
                  </td>
                  {/* ONE CLAUSE, one line, no wrap. The paragraph is the tooltip; both are the view's. */}
                  <td className="px-2 text-left text-faint whitespace-nowrap" title={r.actionReason ?? ''}>
                    {r.actionReasonShort ?? r.actionReason}
                  </td>
                </tr>
              ))}
            </Fragment>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function FamilyHead({ f }: { f: Row }) {
  return (
    <div className="flex flex-col gap-0.5 text-left">
      <div className="text-body">
        <span className={`font-medium ${riskCls(f.riskState)}`}>{f.riskState}</span>
        <span className="text-muted"> · {f.family}</span>
        {f.familyAgeMonths != null && (
          <span className="text-faint text-label" title={`first sale ${f.firstSaleDate ?? '—'}`}> · {f.familyAgeMonths}mo old</span>
        )}
        <span className="text-faint text-label">
          {' '}· binding: {f.bindingProduct ?? '—'} ·{' '}
          {/* the grade's own clock: ACTUAL recent sales. The forecast reading rides beside it. */}
          <span title={`cover at the rate this variation is ACTUALLY selling — ${f.velocityActual?.toFixed(2) ?? '—'}/day`
            + ` (${f.velocityActualBasis === '7D' ? 'last 7 days' : f.velocityActualBasis === '14D' ? 'last 14 days'
                 : f.velocityActualBasis === '30D' ? 'last 30 days' : 'no sales in 30 days'},`
            + ' the fastest of the 7/14/30-day trailing rates), plus inbound Amazon has already registered.'
            + ' This is what the grade is taken on (Ori 2026-08-13).'}>
            {days(f.daysOfCoverAvail)} cover
          </span>
          {f.stockoutDate ? ` · dry ${shortDate(f.stockoutDate)}` : ''}
          {/* the BINDING variation's own boat — it is what sets the verdict. The family's earliest
              boat can be for a sibling and would tell the wrong story here. */}
          {f.bindingNextArrivalDate
            ? ` · next boat ${shortDate(f.bindingNextArrivalDate)}`
            : ' · NOTHING BOOKED'}
          {f.nextArrivalDate && !f.bindingNextArrivalDate
            ? ` (family boat ${shortDate(f.nextArrivalDate)}, ${qty(f.nextArrivalQty)}u — other variations)`
            : ''}
        </span>
      </div>
      {/* ⚠️ THE SEASON IS A SEPARATE QUESTION AND IS LABELLED AS ONE (Ori 2026-08-13). The grade above
          answers "am I about to go dark at the rate I am selling NOW". The forecast line answers
          "will I have enough for Q4". Never conflated — where they disagree, both are shown. */}
      {(f.riskStateForecast != null && f.riskStateForecast !== f.riskState) && (
        <div className="text-label whitespace-normal">
          <span className="text-faint">forecast view: </span>
          <span className={riskCls(f.riskStateForecast)}>{f.riskStateForecast}</span>
          <span className="text-faint"
            title={'The SAME three tests run on the seasonal forecast rate instead of actual sales.'
              + ` Forecast ${f.velocityForecast?.toFixed(2) ?? '—'}/day vs actual ${f.velocityActual?.toFixed(2) ?? '—'}/day.`
              + ' The GRADE follows ACTUAL — a forecast that runs ahead of real selling was making every'
              + ' family look at-risk. This line exists so the seasonal reading is never lost, only'
              + ' un-merged: it is the answer to "will I have enough for Q4", not to "am I going dark now".'}>
            {' '}· {days(f.bindingCoverForecastDays)} cover at the forecast rate
            {f.velocityForecast != null && f.velocityActual != null && f.velocityActual > 0
              ? ` (${(f.velocityForecast / f.velocityActual).toFixed(1)}× actual)` : ''}
            {' '}— a PO question, not today's ads question
          </span>
        </div>
      )}
      {(f.seasonGapUnits ?? 0) > 0 && (
        <div className="text-label text-amber-400/80 whitespace-normal"
          title={`rest-of-year demand ${qty(f.seasonDemandUnits)} units vs the whole pipeline ${qty(f.totalPipelineQty)}.`
            + ' Measured on the FORECAST rate on purpose: trailing actual sales going into a season'
            + ' understate what the season will take. Separate signal, separate column — it never'
            + ' moves the risk grade above.'}>
          season: −{qty(f.seasonGapUnits)} units for the rest of the year (forecast basis — a PO decision, not an ads one)
        </div>
      )}
      <div className="text-label text-faint whitespace-normal">{f.riskReason}</div>
      {/* the verdict may be one snapshot load out of date — the view detects it, we relay its words */}
      {f.arrivalFreshnessConflict && f.arrivalConflictNote && (
        <div className="text-label text-amber-400 whitespace-normal border border-amber-500/30 rounded px-2 py-1 mt-1">
          {f.arrivalConflictNote}
        </div>
      )}
    </div>
  );
}

// What this family's proposal adds up to. Every figure is read from the FAMILY row — the panel does
// not sum the target rows, because the joint days-bought figure is NOT the sum of the per-row ones.
function ProposalSummary({ f }: { f: Row }) {
  if (!f.proposalTargets) return null;
  return (
    <div className="text-label text-faint whitespace-normal">
      <span className="text-muted font-medium">{f.proposalTargets} action{f.proposalTargets === 1 ? '' : 's'}</span>
      {' '}· frees <span className="text-emerald-400">{money(f.proposalFreedPerDay)}/day</span>
      {' '}· buys{' '}
      <span className="text-sky-300" title="days of cover on the binding variation if all of it is done at once — the joint figure, never the sum of the rows. Upper bound: zero organic recapture assumed, so the truth is smaller.">
        {f.proposalDaysBought != null ? `${f.proposalDaysBought.toFixed(1)} days` : 'not priced'}
      </span>
      {' '}of cover · <span className="text-red-400" title="targets whose bid the view proposes halving: not profitable on the last day AND not on the short window">{f.bidCutTargets ?? 0} halved −50%</span>,
      {' '}<span className="text-amber-400" title="non-converting targets parked outright — they bought no units on the settled windows, so this saves cash but buys no days of cover">{f.parkTargets ?? 0} waste parked</span>,
      {' '}<span className="text-emerald-400">{f.protectedTargets ?? 0} protected</span>
      {(f.notExecutableTargets ?? 0) > 0 && (
        <span className="text-faint" title="the rule fired on these but there was nothing executable left — the bid is already at its floor, or the target carries no bid of its own (SB product target). Counted so the escalated total reconciles.">
          {' '}· {f.notExecutableTargets} with no room left
        </span>
      )}
      {(f.budgetCutCampaigns ?? 0) > 0 && (
        <span className="text-amber-400" title="a capped campaign spends its budget regardless, so each target cut is PAIRED with a budget cut of the same size — unpaired, the money re-routes to the targets beside it and sells the last stock faster">
          {' '}· {f.budgetCutCampaigns} paired budget cut{f.budgetCutCampaigns === 1 ? '' : 's'} ({money(f.budgetCutPerDay)}/day)
        </span>
      )}
      {f.convDaysBoughtMax != null && (
        <span title="for scale only, never a proposal: pausing EVERY converting target including the winners is the most this family could buy.">
          {' '}· ceiling if every converting target were paused: {f.convDaysBoughtMax.toFixed(1)} days
        </span>
      )}
    </div>
  );
}

// the v1 variation table — kept, but out of the main flow (Ori: this is the ads page, not Supply)
function InventoryDetail({ f, asins }: { f: Row; asins: Row[] }) {
  return (
    <div className="overflow-x-auto">
      <table className="text-label font-mono border-collapse">
        <thead>
          <tr className="text-faint text-right">
            <th className="font-normal text-left px-2 py-0.5">variation</th>
            <th className="font-normal px-2 text-left" title="units sellable today (FBA + AWD)">sellable</th>
            <th className="font-normal px-2 text-left" title="every stage of the pipeline — sellable, inbound, and still at the factory">whole pipeline</th>
            <th className="font-normal px-2 text-left" title="units/day the product is ACTUALLY selling — the fastest of the 7/14/30-day trailing rates. This is the rate the grade is taken on (Ori 2026-08-13). The forecast rate is the second figure and it grades nothing.">rate actual / forecast</th>
            <th className="font-normal px-2 text-left" title="strict = sellable only; avail = plus the inbound Amazon has already registered. The verdict is taken on avail, at the ACTUAL sales rate. The forecast cover is shown beneath it wherever the two disagree.">cover strict → avail</th>
            <th className="font-normal px-2 text-left" title="the next PENDING shipment with a future ETA">next boat</th>
            <th className="font-normal px-2 text-left" title="rest-of-year demand minus the whole pipeline. Positive = short for the season even counting everything.">season gap</th>
            <th className="font-normal px-2 text-left" title="last date a replacement batch can start and still land before the shelf empties">PO by</th>
            <th className="font-normal px-2 text-left">why</th>
          </tr>
        </thead>
        <tbody>
          {asins.map(a => (
            <tr key={a.rowId} className="border-t border-border/20">
              <td className="text-left px-2 py-0.5 whitespace-nowrap">
                <span className={a.asin === f.bindingAsin ? 'text-muted font-medium' : 'text-muted'}>{a.product}</span>
                {a.asin === f.bindingAsin && <span className="text-amber-400 text-label" title="the variation that sets this family's verdict">{' '}◂ binding</span>}
                {a.familyUnitsSharePct != null && <span className="text-faint text-label"> · {a.familyUnitsSharePct}% of family</span>}
              </td>
              <td className="px-2 text-left text-muted">{qty(a.sellableQty)}</td>
              <td className="px-2 text-left"><Pipeline r={a} /></td>
              <td className="px-2 text-left whitespace-nowrap"
                title={`trailing actual: 7d ${a.velocity7d ?? '—'}/day · 14d ${a.velocity14d ?? '—'}/day · 30d ${a.velocity30d ?? '—'}/day`
                  + ` — the grade uses the fastest (${a.velocityActualBasis ?? '—'}).`
                  + `\nforecast rate ${a.velocityForecast ?? '—'}/day — published, but it grades nothing.`}>
                <span className="text-muted">{a.velocityActual != null ? `${a.velocityActual.toFixed(1)}` : '—'}</span>
                <span className="text-faint text-label">{a.velocityActualBasis ? ` ${a.velocityActualBasis.toLowerCase()}` : ''}</span>
                <span className="text-faint"> / {a.velocityForecast != null ? a.velocityForecast.toFixed(1) : '—'}</span>
              </td>
              <td className="px-2 text-left whitespace-nowrap">
                <span className="text-faint">{days(a.daysOfCover)}</span>
                <span className="text-faint"> → </span>
                <span className={riskCls(a.riskState)}>{days(a.daysOfCoverAvail)}</span>
                <span className="text-faint text-label"> {a.coverBasis}</span>
                {a.riskStateForecast != null && a.riskStateForecast !== a.riskState && (
                  <span className="text-faint text-label"
                    title="the same tests on the forecast rate. The grade follows ACTUAL; this is here so the seasonal reading is never lost.">
                    {' '}(fc {days(a.daysOfCoverAvailForecast)} → {a.riskStateForecast})
                  </span>
                )}
              </td>
              <td className="px-2 text-left whitespace-nowrap">
                {a.nextArrivalDate
                  ? <span className="text-muted">{shortDate(a.nextArrivalDate)} · {qty(a.nextArrivalQty)}u{a.bridgeGapDays != null ? <span className={a.bridgeGapDays < 0 ? 'text-red-400' : 'text-faint'}> · {a.bridgeGapDays > 0 ? '+' : ''}{Math.round(a.bridgeGapDays)}d</span> : null}</span>
                  : <span className="text-red-400">nothing booked</span>}
                {!!a.overduePendingQty && (
                  <span className="text-amber-400 text-label" title={`${qty(a.overduePendingQty)} units on shipments whose ETA passed (oldest ${a.overduePendingOldestEta ?? '—'}) and that were never marked received — arrival is user-confirmed in this system`}>
                    {' '}· {qty(a.overduePendingQty)} overdue
                  </span>
                )}
              </td>
              <td className="px-2 text-left">
                {a.seasonGapUnits != null && a.seasonGapUnits > 0
                  ? <span className="text-amber-400" title={`rest-of-year demand ${qty(a.seasonDemandUnits)} vs whole pipeline ${qty(a.totalPipelineQty)}`}>−{qty(a.seasonGapUnits)}</span>
                  : <span className="text-faint">covered</span>}
              </td>
              <td className="px-2 text-left whitespace-nowrap">
                {a.tooLateToReplenish
                  ? <span className="text-red-400" title={`lead is ${a.fullLeadDays ?? '—'} days — that date has passed`}>passed {shortDate(a.poDeadline)}</span>
                  : <span className="text-faint">{shortDate(a.poDeadline)}</span>}
              </td>
              {/* same rule as the move table: one clause visible, the paragraph in the tooltip,
                  both written in the view (risk_reason_short / risk_reason, v27.62) */}
              <td className="px-2 text-left text-faint whitespace-nowrap" title={a.riskReason}>
                {a.riskReasonShort ?? a.riskReason}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

type Bucket = { asins: Row[]; proposed: Group[]; protectedG: Group[]; quiet: Group[]; nProposed: number; nProtected: number; nQuiet: number };
type Sug = { bid: number | null; budget: number | null; flag: boolean | null; clamped: boolean | null;
  floor: number | null; why: string | null; riskWhy: string | null; adGroupId: string | null };

export function LowStockPhase({ defaultOpen }: { defaultOpen?: boolean }) {
  // defaultOpen (Ori 2026-08-17: "when there is an open action hierarchy should be Expanded else
  // collapse by default") — the parent may tell the section to start open, but a user click is
  // FINAL: openState stays null until the first click, so a defaultOpen arriving (or flipping)
  // later can never override an explicit close. The lazy fetch gates below key off `open`, so
  // defaultOpen flipping it true triggers the first fetch naturally.
  const [openState, setOpenState] = useState<boolean | null>(null);
  const open = openState ?? defaultOpen ?? false;
  const [openOk, setOpenOk] = useState(false);
  const [openFam, setOpenFam] = useState<Record<string, boolean>>({});
  const [openProt, setOpenProt] = useState<Record<string, boolean>>({});
  const [openQuiet, setOpenQuiet] = useState<Record<string, boolean>>({});
  const [openInv, setOpenInv] = useState<Record<string, boolean>>({});
  const [rows, setRows] = useState<Row[] | null>(null);
  const [sug, setSug] = useState<Map<string, Sug>>(new Map());
  const [extLive, setExtLive] = useState(false);
  const [failed, setFailed] = useState(false);
  const doQueue = useDoQueue();

  // LAZY SECTION (WEEKLY_RUN_UX.md: sections fetch ONLY on first expand). V_LOW_STOCK_ADS alone is
  // a ~50-70 s view cold — exactly the kind of query that, fired 17-sections-at-once on mount,
  // made page open take minutes (the "why is it not loading" incident). Both effects below gate on
  // the same first expand, one ref each.
  const fetchedRef = useRef(false);
  useEffect(() => {
    if (!open || fetchedRef.current) return;
    fetchedRef.current = true;
    let alive = true;
    // 60 retries, not the default 20: V_LOW_STOCK_ADS is a ~50-70 s view on a cold cache (the
    // supply-chain leg alone is ~11 s) and 20 × 2 s gives up at 40 s — the panel then says
    // "unavailable" for a query that was about to answer. The cube keeps the query alive across
    // the Continue-wait poll, so this only costs patience.
    cubeLoadWithMeta({ dimensions: DIMS }, 60).then(res => {
      if (!alive) return;
      // A failed/stale cube returns {data: [], error}. Without this the panel renders its empty
      // state and claims there is nothing at risk, which for a stock-out criteria is the most
      // expensive lie the page could tell.
      if (res.error) { console.error('[low-stock] cube error:', res.error); setFailed(true); return; }
      setRows((res.data as Record<string, unknown>[]).map(toRow));
    }).catch(e => {
      console.error('[low-stock] fetch failed:', e);
      if (alive) setFailed(true);
    });
    return () => { alive = false; };
  }, [open]);

  // Separate request, on purpose (see EXT_DIMS): it must never delay or break the rows above. If
  // the view has not published the suggested values yet this simply never arrives and "→ $" stays
  // blank — the panel does not invent a number.
  const extFetchedRef = useRef(false);
  useEffect(() => {
    if (!open || extFetchedRef.current) return;  // lazy gate #2 — same first-expand rule
    extFetchedRef.current = true;
    let alive = true;
    cubeLoadWithMeta({ dimensions: EXT_DIMS }).then(res => {
      if (!alive) return;
      if (res.error) { console.warn('[low-stock] suggested values unavailable:', res.error); return; }
      const m = new Map<string, Sug>();
      for (const e of res.data as Record<string, unknown>[]) {
        m.set(String(e[D + 'rowId'] ?? ''), {
          bid: num(e[D + 'suggestedBid']), budget: num(e[D + 'suggestedBudget']),
          flag: boolOrNull(e[D + 'isProposal']),
          clamped: boolOrNull(e[D + 'bidClampedToFloor']),
          floor: num(e[D + 'bidFloor']),
          why: str(e[D + 'actionReasonShort']), riskWhy: str(e[D + 'riskReasonShort']),
          adGroupId: str(e[D + 'adGroupId']),
        });
      }
      setSug(m);
      setExtLive(true);
    }).catch(e => console.warn('[low-stock] suggested values unavailable:', e));
    return () => { alive = false; };
  }, [open]);

  const { atRisk, ok, byFamily, snapshotDate, merged } = useMemo(() => {
    const all = (rows ?? []).map(r => {
      const s = sug.get(r.rowId);
      return s ? { ...r, suggestedBid: s.bid, suggestedBudget: s.budget, isProposal: s.flag,
                   bidClampedToFloor: s.clamped, bidFloor: s.floor,
                   actionReasonShort: s.why, riskReasonShort: s.riskWhy,
                   adGroupId: s.adGroupId } : r;
    });
    const fams = all.filter(r => r.rowKind === 'FAMILY')
      .sort((a, b) => a.riskRank - b.riskRank
        || (a.daysOfCoverAvail ?? 9e9) - (b.daysOfCoverAvail ?? 9e9)
        || a.family.localeCompare(b.family));
    const raw: Record<string, { asins: Row[]; camps: Map<string, Row>; proposed: Row[]; prot: Row[]; quiet: Row[] }> = {};
    for (const f of fams) raw[f.family] = { asins: [], camps: new Map(), proposed: [], prot: [], quiet: [] };
    for (const r of all) {
      const b = raw[r.family];
      if (!b) continue;
      if (r.rowKind === 'ASIN') b.asins.push(r);
      else if (r.rowKind === 'CAMPAIGN') { if (r.campaignId) b.camps.set(r.campaignId, r); }
      else if (r.rowKind === 'TARGET') {
        if (isProposalRow(r)) b.proposed.push(r);
        else if (r.action === 'STOCK_PROTECT') b.prot.push(r);
        else b.quiet.push(r);
      }
    }
    const byFamily: Record<string, Bucket> = {};
    for (const key of Object.keys(raw)) {
      const b = raw[key];
      b.asins.sort((a, c) => (a.daysOfCoverAvail ?? 9e9) - (c.daysOfCoverAvail ?? 9e9));
      const proposed = toGroups(b.proposed, b.camps);
      // A CAMPAIGN row whose targets all landed in another bucket still carries a real move (the
      // paired budget cut). Grouping is by target, so it would otherwise be dropped silently.
      const seen = new Set(proposed.map(g => g.campaignId));
      let orphans = 0;
      for (const [cid, camp] of b.camps) {
        if (seen.has(cid) || !isProposalRow(camp)) continue;
        proposed.push({ campaignId: cid, camp, head: camp, targets: [] });
        orphans++;
      }
      byFamily[key] = {
        asins: b.asins,
        proposed,
        protectedG: toGroups(b.prot, b.camps),
        quiet: toGroups(b.quiet, b.camps),
        nProposed: b.proposed.length + orphans, nProtected: b.prot.length, nQuiet: b.quiet.length,
      };
    }
    return {
      atRisk: fams.filter(f => f.riskState !== 'OK'),
      ok: fams.filter(f => f.riskState === 'OK'),
      byFamily,
      snapshotDate: fams[0]?.snapshotDate ?? null,
      merged: all,
    };
  }, [rows, sug]);

  // The bid cuts each campaign's paired budget was sized from — the map the CAMPAIGN toggle uses,
  // built once here so it is the same list no matter which table section the campaign row renders in.
  const pairedTargets = useMemo(() => {
    const m = new Map<string, Row[]>();
    for (const r of merged) {
      if (!bidReady(r) || !r.campaignId) continue;
      const a = m.get(r.campaignId) ?? [];
      a.push(r);
      m.set(r.campaignId, a);
    }
    return m;
  }, [merged]);

  // ONE list feeds both the count and the button (the Revivals idiom), so "apply all N" can never
  // disagree with what it queues. ELIGIBLE = the view priced it (is_proposal + a suggested value)
  // and it can become a bulksheet row. APPLICABLE = eligible AND its key — keyword for bids,
  // campaign for budgets — is not already queued from ANY surface at ANY value: a key-queued row
  // counts as DONE, not skipped, because the decision on that lever is already made wherever it
  // was made. Budgets AND the bid cuts they were sized from are both in the list — apply-all
  // ships both sides of every pair.
  const eligible = useMemo(() => merged.filter(r => bidReady(r) || budgetReady(r)), [merged]);
  const applicable = useMemo(
    () => eligible.filter(r => r.rowKind === 'TARGET'
      ? !findQueuedBid(doQueue.items, r.keywordId)
      : !findQueuedBudget(doQueue.items, r.campaignId)),
    [eligible, doQueue.items]);
  // Bulk unapply sweeps ONLY value-exact items this panel would have queued — a foreign-valued
  // item is another view's decision and leaves only from its own row's click.
  const ourItem = (r: Row) =>
    r.rowKind === 'TARGET' ? ourBidItem(doQueue.items, r) : ourBudgetItem(doQueue.items, r);
  const nElig = eligible.length;
  const nSug = applicable.length;
  const nDone = nElig - nSug;
  const nBudgets = applicable.filter(r => r.rowKind === 'CAMPAIGN').length;
  const nBids = nSug - nBudgets;
  const allApplied = nElig > 0 && nSug === 0;
  const applyAll = () => {
    if (allApplied) eligible.forEach(r => { const it = ourItem(r); if (it) doQueue.removeItem(it.id); });
    else applicable.forEach(r => {
      doQueue.addItem(r.rowKind === 'TARGET' ? stockBidQueueItem(r) : stockBudgetQueueItem(r));
    });
  };

  // Contract B.4 (Ori 2026-08-17): a family still holding at least one OPEN — proposed and not
  // yet queued from any view — suggestion starts EXPANDED; one with nothing left to decide starts
  // collapsed. isProposalRow (not bidReady) on purpose: it answers before the tolerant EXT request
  // lands too, so a view/schema skew degrades to the proposal-based default, not to
  // everything-collapsed. A queued key from ANY surface counts as decided.
  const famOpenDefault = useMemo(() => {
    const s = new Set<string>();
    for (const r of merged) {
      if (r.rowKind === 'TARGET'
        ? isProposalRow(r) && !findQueuedBid(doQueue.items, r.keywordId)
        : r.rowKind === 'CAMPAIGN' && isProposalRow(r) && !findQueuedBudget(doQueue.items, r.campaignId)) {
        s.add(r.family);
      }
    }
    return s;
  }, [merged, doQueue.items]);

  const headline = failed
    ? '— unavailable'
    : !rows
    ? (open || fetchedRef.current) ? '— loading…' : '— expand to load'
    : atRisk.length === 0
    ? `— every family reaches its next arrival (${ok.length} checked)`
    : `— ${atRisk.map(f => `${f.family} ${f.riskState}`).join(' · ')}`;

  return (
    <div className="mb-3 rounded-md border border-border bg-surface/30 px-3 py-2">
      <div className="flex items-center gap-1">
        <button className="text-label flex items-center gap-1 flex-1 min-w-0" onClick={() => setOpenState(!open)}>
          <span className="text-faint">{open ? '▾' : '▸'}</span>
          <span className="font-medium text-red-300">Low stock</span>
          <span className="text-faint truncate">
            {headline}
            {' '}· the campaigns and targets to pull while a family runs dry · you decide
          </span>
        </button>
        {rows && nElig > 0 && (
          <button onClick={applyAll}
            title={allApplied
              ? `every stock move here is queued — click to unapply the ones queued at this panel's own values. A move queued from another view at a different value is that view's decision: it leaves only from its own row's click.`
              : `queue the ${nSug} open stock moves — ${nBids} bid cut${nBids === 1 ? '' : 's'} and ${nBudgets} paired budget cut${nBudgets === 1 ? '' : 's'}.`
                + (nDone > 0 ? ` ${nDone} more ${nDone === 1 ? 'is' : 'are'} already queued (from this or another view) and count${nDone === 1 ? 's' : ''} as done.` : '')
                + ` A capped campaign's budget cut is already the SUM of its proposed target cuts, so budgets and their targets travel together — apply-all ships both sides of every pair. Protected winners and waste parks are not touched.`}
            className={`text-label px-2 py-0.5 rounded border shrink-0 ${allApplied ? 'border-emerald-500/40 text-emerald-300' : 'border-rose-500/40 text-rose-300 hover:bg-rose-500/10'}`}>
            {allApplied ? `✓ applied ${nElig}` : nDone > 0 ? `apply ${nSug} more` : `apply all ${nSug}`}
          </button>
        )}
      </div>

      {open && failed && (
        <div className="mt-2 text-label text-faint">
          Stock data unavailable — the LowStockAds cube isn't answering (stale schema or cube restart pending).
          Do not read this as "nothing at risk".
        </div>
      )}

      {open && rows && (
        <div className="mt-2 flex flex-col gap-4">
          {atRisk.length === 0 ? (
            <div className="text-label text-faint">
              No family is heading for a stock-out — every material variation reaches its next booked arrival
              with buffer, and the whole pipeline covers the rest of the year.
            </div>
          ) : atRisk.map(f => {
            const b = byFamily[f.family];
            // A family with at least one OPEN (proposed, not-yet-queued) suggestion expands; one
            // with nothing left to decide collapses to its header (Ori 2026-08-17 — supersedes the
            // CRITICAL-always-open default: a CRITICAL family whose every move is already queued
            // is done deciding, however red it is). A click is final — an explicit openFam entry
            // always wins over the computed default.
            const famOpen = openFam[f.family] ?? famOpenDefault.has(f.family);
            return (
              <div key={f.rowId} className="flex flex-col gap-2 border-t border-border/40 pt-2 first:border-t-0 first:pt-0">
                <button className="flex items-start gap-1 text-left"
                  onClick={() => setOpenFam(o => ({ ...o, [f.family]: !famOpen }))}>
                  <span className="text-faint pt-0.5">{famOpen ? '▾' : '▸'}</span>
                  <FamilyHead f={f} />
                </button>

                {famOpen && b && (
                  <>
                    {b.nProposed === 0 ? (
                      <div className="text-label text-faint">
                        The view proposes no move on this family's targets right now.
                      </div>
                    ) : (
                      <>
                        <ProposalSummary f={f} />
                        <MoveTable groups={b.proposed} extLive={extLive} pairedTargets={pairedTargets} />
                      </>
                    )}

                    {b.nProtected > 0 && (
                      <div className="flex flex-col gap-1">
                        <button className="text-label flex items-center gap-1 text-left"
                          onClick={() => setOpenProt(o => ({ ...o, [f.family]: !o[f.family] }))}>
                          <span className="text-faint">{openProt[f.family] ? '▾' : '▸'}</span>
                          <span className="text-muted">Protected</span>
                          <span className="text-faint">
                            — {b.nProtected} target{b.nProtected === 1 ? '' : 's'} the view priced but did not
                            propose. Cutting a real winner to save stock is a call only you make.
                          </span>
                        </button>
                        {openProt[f.family] && <MoveTable groups={b.protectedG} extLive={extLive} pairedTargets={pairedTargets} />}
                      </div>
                    )}

                    {b.nQuiet > 0 && (
                      <div className="flex flex-col gap-1">
                        <button className="text-label flex items-center gap-1 text-left"
                          onClick={() => setOpenQuiet(o => ({ ...o, [f.family]: !o[f.family] }))}>
                          <span className="text-faint">{openQuiet[f.family] ? '▾' : '▸'}</span>
                          <span className="text-muted">No action</span>
                          <span className="text-faint">— {b.nQuiet} target{b.nQuiet === 1 ? '' : 's'} — the view's own words in the why column</span>
                        </button>
                        {openQuiet[f.family] && <MoveTable groups={b.quiet} extLive={extLive} pairedTargets={pairedTargets} />}
                      </div>
                    )}

                    {b.asins.length > 0 && (
                      <div className="flex flex-col gap-1">
                        <button className="text-label flex items-center gap-1 text-left"
                          onClick={() => setOpenInv(o => ({ ...o, [f.family]: !o[f.family] }))}>
                          <span className="text-faint">{openInv[f.family] ? '▾' : '▸'}</span>
                          <span className="text-muted">Inventory detail</span>
                          <span className="text-faint">— {b.asins.length} variation{b.asins.length === 1 ? '' : 's'} · the pipeline behind the verdict (Supply page numbers)</span>
                        </button>
                        {openInv[f.family] && <InventoryDetail f={f} asins={b.asins} />}
                      </div>
                    )}
                  </>
                )}
              </div>
            );
          })}

          {/* ── families that are fine — knowable without hunting ── */}
          <div className="border-t border-border/40 pt-2 flex flex-col gap-2">
            <button className="text-label flex items-center gap-1 text-left" onClick={() => setOpenOk(o => !o)}>
              <span className="text-faint">{openOk ? '▾' : '▸'}</span>
              <span className="text-muted">Covered</span>
              <span className="text-faint">— {ok.length} · cover reaches the next arrival and the pipeline covers the season</span>
            </button>
            {openOk && (
              <div className="overflow-x-auto">
                <table className="text-label font-mono border-collapse">
                  <thead>
                    <tr className="text-faint text-right">
                      <th className="font-normal text-left px-2 py-0.5">family</th>
                      <th className="font-normal px-2 text-left">binding variation</th>
                      <th className="font-normal px-2 text-left">cover</th>
                      <th className="font-normal px-2 text-left">whole pipeline</th>
                      <th className="font-normal px-2 text-left">next boat</th>
                      <th className="font-normal px-2 text-left">season gap</th>
                    </tr>
                  </thead>
                  <tbody>
                    {ok.map(f => (
                      <tr key={f.rowId} className="border-t border-border/20">
                        <td className="text-left px-2 py-0.5 pl-6 text-muted">{f.family}</td>
                        <td className="px-2 text-left text-faint">{f.bindingProduct ?? '—'}</td>
                        <td className="px-2 text-left text-emerald-400">{days(f.daysOfCoverAvail)}</td>
                        <td className="px-2 text-left"><Pipeline r={f} /></td>
                        <td className="px-2 text-left text-faint">
                          {f.nextArrivalDate ? `${shortDate(f.nextArrivalDate)} · ${qty(f.nextArrivalQty)}u` : 'nothing booked'}
                        </td>
                        <td className="px-2 text-left text-faint">
                          {f.seasonGapUnits != null && f.seasonGapUnits > 0 ? `−${qty(f.seasonGapUnits)}` : 'covered'}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          <div className="text-label text-subtle">
            Nothing queues itself — the → $ toggles and apply-all queue to the DO page on your click,
            and every value queued is the view's own suggested value (v27.63).
            {' '}Source: V_LOW_STOCK_ADS (backend); the risk
            state, every threshold, the action, its reason — the short clause in the table AND the full
            paragraph on hover — the rank, the dollars and the days-bought numbers are all decided there.
            Inventory snapshot {snapshotDate ?? '—'}.
            {' '}The grade answers <em>am I about to go dark at the rate I am selling now</em> and runs on
            ACTUAL trailing sales; the season gap is a separate, forecast-based signal answering
            {' '}<em>will I have enough for Q4</em> — the two are never merged.
            {' '}The −50% rule in a CRITICAL family judges the LAST DAY and the short window, both
            deliberately UNSETTLED (SP accrues to D+7, SB to D+14): requiring BOTH to fail is the guard,
            and the settled 28-day column is there as context, never as the trigger.
            {!extLive && ' Suggested values (→ $) are not published by the view yet, so that column is blank.'}
          </div>
        </div>
      )}
    </div>
  );
}

export default LowStockPhase;
