import { useEffect, useMemo, useState } from 'react';
import { cubeLoad } from '../hooks/useCubeData';
import { useDoQueue } from '../hooks/useDoQueue';
import { fM } from '../utils';

// Weekly Run — launch-window (0–20d) campaigns as a collapsible hierarchy:
//   campaign (age badge · totals · budget) → targets (auto groups / keywords, each with why + row2/row3
//   measures + bid/stop) → search terms (Spenders · Winners · Negates). Measures: CPC · clicks · TOS% · units · net ROAS.
// Data: RunTarget (measures + unified bid + reason), LaunchPhase1 (campaign day/budget/reason/roas), RunSearchTerm (level 3).

function num(v: unknown): number { const n = Number(v); return Number.isFinite(n) ? n : 0; }
const roasCls = (r: number) => r >= 2 ? 'text-emerald-400' : r >= 1 ? 'text-amber-400' : r > 0 ? 'text-red-400' : 'text-faint';
const prettyTarget = (t: string) => t.includes('-') && !t.includes(' ')
  ? t.split('-').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ') : t;
const isRaise = (a: string) => a === 'RAISE_STRONG' || a === 'RAISE_WEAK' || a === 'STARVE' || a === 'PROBE';
const isBleed = (a: string) => a === 'BLEED_CUT' || a === 'BLEED_TRIM';   // 0-conversion trims (reduce)
const actLabel = (a: string) => a === 'CUT' ? 'cut' : a === 'BRAKE' ? 'brake↓' : a === 'STARVE' ? 'starve' : a === 'PROBE' ? 'probe↑'
  : a === 'BLEED_CUT' ? '−40%' : a === 'BLEED_TRIM' ? '−20%' : a === 'BLEED_WATCH' ? 'watch' : a === 'BLEED_STALE' ? 'watch'
  : a === 'RAISE_STRONG' ? 'raise↑↑' : a === 'RAISE_WEAK' ? 'raise↑' : a === 'NO_BID' ? '—' : 'hold';
const actCls = (a: string) => (a === 'CUT' || isBleed(a)) ? 'text-red-400' : (a === 'BRAKE' || a === 'BLEED_WATCH' || a === 'BLEED_STALE') ? 'text-amber-400' : isRaise(a) ? 'text-emerald-400' : 'text-faint';
// short "why" for a launch-controller bid (mature rows carry their own reason)
const bidWhy = (a: string, reason: string, goodRoas = false,
  m?: { units: number; clicks: number; roas: number }): string => reason ? reason
  : a === 'HOLD' && goodRoas ? 'net ROAS ≥ 1.0× — held (not cut while the campaign caps)'
  : a === 'CUT' ? 'last day & prior-2d both < 0.9×'
  : a === 'BLEED_CUT' ? '≥15 clicks, still no sale — cut 40% (decision point)'
  : a === 'BLEED_TRIM' ? '≥8 clicks, still no sale — trim 20% (stop the bleed)'
  : a === 'BLEED_WATCH' ? '0 sales so far — hold & watch; trims at 8 clicks, not raised'
  : a === 'BLEED_STALE' ? '0 sales, but under 4 clicks last day — traffic dried up, hold (not cutting on stale clicks)'
  : a === 'BRAKE' ? 'campaign dark >10% & ROAS mid — lower bid to stop capping'
  : a === 'PROBE' ? 'under 4 clicks — raise slowly (+5%) to buy just enough traffic to reach a verdict (negate dead search terms in parallel)'
  : a === 'RAISE_STRONG' ? 'last day & prior-2d both > 1.5× — fund the winner'
  : a === 'RAISE_WEAK' ? 'last day > 1.2×'
  : a === 'STARVE' ? 'under-spending → raise to buy traffic'
  : a === 'NO_BID' ? 'auto group inherits the ad-group default bid'
  // launch never cuts bids on losses: ≥4 clicks with no sale → hold the bid; the dead search terms get negated instead
  : a === 'HOLD' && m && m.units === 0 && m.clicks >= 4 ? '≥4 clicks, still no sale — held (launch holds the bid, doesn’t cut; dead search terms get negated instead)'
  // genuine near-breakeven seller (has sales, net ROAS just under/at 1.0×) — hold, don't chase noise
  : a === 'HOLD' && m && m.roas >= 0.9 ? 'in the 0.9–1.2× deadband — hold'
  : 'unknown';

type STerm = { term: string; clicks: number; orders: number; spend: number; netRoas: number; acos: number; isWinner: boolean; isNegate: boolean;
  sp1: number; sp7: number; sp28: number; sl1: number; sl7: number; sl28: number };   // per-day-avg spend/sales @ 1d/7d/28d
type Tgt = { keywordId: string; adGroupId: string; text: string; isAuto: boolean; matchType: string;
  currentBid: number | null; suggestedBid: number | null; action: string; reason: string; daysSince: number | null;
  r2: number[]; r3: number[]; terms: STerm[] };
// SB target window measures — clicks/spend/CPC/sales/net-ROAS only (no impressions/CTR — undercounted at grain)
type SbWin = { clk: number; spend: number; cpc: number; sales: number; roas: number };
// one SB target (keyword OR product target) with its launch-controller bid suggestion — behaves like SP
type SbTgt = { targetId: string; adGroupId: string; text: string; targetType: string; matchType: string;
  bid: number; suggestedBid: number | null; action: string; reason: string; daysSince: number | null; r2: SbWin; r3: SbWin };
type Camp = { id: string; name: string; day: number; currentBudget: number; suggestedBudget: number; reason: string;
  roas1: number; roasPrev2: number; spendToday: number; pctDark: number; targets: Tgt[];
  // Sponsored-Brands campaigns: campaign-level measures (sbR2/sbR3) + a per-target drill (sbTgts) with the same
  // launch-controller bid/budget suggestions as SP, on SB-native data (sb_campaign_history + SB reports).
  isSb?: boolean; sbR2?: number[]; sbR3?: number[]; sbTgts?: SbTgt[] };

export function NewCampaignCards({ product: _product, actionFilter = 'all' }: { product?: string | null; actionFilter?: 'todo' | 'done' | 'all' }) {
  const doQueue = useDoQueue();
  const [camps, setCamps] = useState<Camp[] | null>(null);
  const [drafts, setDrafts] = useState<Record<string, number>>({});
  const [bidDrafts, setBidDrafts] = useState<Record<string, number>>({});
  const [open, setOpen] = useState<Record<string, boolean>>({});   // default collapsed
  const [openTerms, setOpenTerms] = useState<Record<string, boolean>>({});   // search-term section, default collapsed

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const [p1, rt, st, sb, sbk] = await Promise.all([
          cubeLoad({ dimensions: ['LaunchPhase1.campaignId', 'LaunchPhase1.campaignName', 'LaunchPhase1.dayOfRamp',
            'LaunchPhase1.currentBudget', 'LaunchPhase1.suggestedBudget', 'LaunchPhase1.budgetReason',
            'LaunchPhase1.campRoas1d', 'LaunchPhase1.campRoasPrev2', 'LaunchPhase1.spendToday', 'LaunchPhase1.pctDark'] }),
          cubeLoad({ dimensions: ['RunTarget.campaignId', 'RunTarget.keywordId', 'RunTarget.adGroupId', 'RunTarget.targetText',
            'RunTarget.isAutoGroup', 'RunTarget.matchType', 'RunTarget.currentBid', 'RunTarget.suggestedBid', 'RunTarget.bidAction', 'RunTarget.bidReason', 'RunTarget.daysSinceSuggestion',
            'RunTarget.r2Spend', 'RunTarget.r2Cpc', 'RunTarget.r2Clk', 'RunTarget.r2Ctr', 'RunTarget.r2Tos', 'RunTarget.r2Units', 'RunTarget.r2Roas', 'RunTarget.r2Acos', 'RunTarget.r2RoasCorr', 'RunTarget.r2Impr',
            'RunTarget.r3Spend', 'RunTarget.r3Cpc', 'RunTarget.r3Clk', 'RunTarget.r3Ctr', 'RunTarget.r3Tos', 'RunTarget.r3Units', 'RunTarget.r3Roas', 'RunTarget.r3Acos', 'RunTarget.r3RoasCorr', 'RunTarget.r3Impr'],
            filters: [{ member: 'RunTarget.isNew', operator: 'equals', values: ['true'] }] }),
          cubeLoad({ dimensions: ['RunSearchTerm.campaignId', 'RunSearchTerm.keywordId', 'RunSearchTerm.searchTerm',
            'RunSearchTerm.clicks', 'RunSearchTerm.orders', 'RunSearchTerm.spend', 'RunSearchTerm.netRoas',
            'RunSearchTerm.acos', 'RunSearchTerm.isWinner', 'RunSearchTerm.isNegate',
            'RunSearchTerm.d1Spend', 'RunSearchTerm.d1Sales', 'RunSearchTerm.d7Spend', 'RunSearchTerm.d7Sales',
            'RunSearchTerm.d28Spend', 'RunSearchTerm.d28Sales'] }),
          cubeLoad({ dimensions: ['SbLaunchCampaign.campaignId', 'SbLaunchCampaign.currentBudget', 'SbLaunchCampaign.suggestedBudget', 'SbLaunchCampaign.budgetReason', 'SbLaunchCampaign.spendToday', 'SbLaunchCampaign.pctDark',
            'SbLaunchCampaign.r2Spend', 'SbLaunchCampaign.r2Cpc', 'SbLaunchCampaign.r2Clk', 'SbLaunchCampaign.r2Ctr', 'SbLaunchCampaign.r2Tos', 'SbLaunchCampaign.r2Roas', 'SbLaunchCampaign.r2Acos', 'SbLaunchCampaign.r2Impr',
            'SbLaunchCampaign.r3Spend', 'SbLaunchCampaign.r3Cpc', 'SbLaunchCampaign.r3Clk', 'SbLaunchCampaign.r3Ctr', 'SbLaunchCampaign.r3Tos', 'SbLaunchCampaign.r3Roas', 'SbLaunchCampaign.r3Acos', 'SbLaunchCampaign.r3Impr'] }),
          cubeLoad({ dimensions: ['SbLaunchTarget.campaignId', 'SbLaunchTarget.targetId', 'SbLaunchTarget.adGroupId', 'SbLaunchTarget.targetText', 'SbLaunchTarget.targetType', 'SbLaunchTarget.matchType', 'SbLaunchTarget.bid', 'SbLaunchTarget.suggestedBid', 'SbLaunchTarget.bidAction', 'SbLaunchTarget.bidReason', 'SbLaunchTarget.daysSinceSuggestion',
            'SbLaunchTarget.r2Clk', 'SbLaunchTarget.r2Spend', 'SbLaunchTarget.r2Cpc', 'SbLaunchTarget.r2Sales', 'SbLaunchTarget.r2Roas',
            'SbLaunchTarget.r3Clk', 'SbLaunchTarget.r3Spend', 'SbLaunchTarget.r3Cpc', 'SbLaunchTarget.r3Sales', 'SbLaunchTarget.r3Roas'] }),
        ]);
        if (!alive) return;
        const byCamp = new Map<string, Camp>();
        for (const r of p1 as Record<string, unknown>[]) {
          const id = String(r['LaunchPhase1.campaignId'] ?? '');
          if (byCamp.has(id)) continue;
          byCamp.set(id, { id, name: String(r['LaunchPhase1.campaignName'] ?? ''), day: num(r['LaunchPhase1.dayOfRamp']),
            currentBudget: num(r['LaunchPhase1.currentBudget']), suggestedBudget: num(r['LaunchPhase1.suggestedBudget']),
            reason: String(r['LaunchPhase1.budgetReason'] ?? ''), roas1: num(r['LaunchPhase1.campRoas1d']),
            roasPrev2: num(r['LaunchPhase1.campRoasPrev2']), spendToday: num(r['LaunchPhase1.spendToday']),
            pctDark: num(r['LaunchPhase1.pctDark']), targets: [] });
        }
        for (const r of rt as Record<string, unknown>[]) {
          const c = byCamp.get(String(r['RunTarget.campaignId'] ?? '')); if (!c) continue;
          c.targets.push({
            keywordId: String(r['RunTarget.keywordId'] ?? ''), adGroupId: String(r['RunTarget.adGroupId'] ?? ''),
            text: String(r['RunTarget.targetText'] ?? ''),
            isAuto: r['RunTarget.isAutoGroup'] === true || r['RunTarget.isAutoGroup'] === 'true',
            matchType: String(r['RunTarget.matchType'] ?? ''),
            currentBid: r['RunTarget.currentBid'] != null ? num(r['RunTarget.currentBid']) : null,
            suggestedBid: r['RunTarget.suggestedBid'] != null ? num(r['RunTarget.suggestedBid']) : null,
            action: String(r['RunTarget.bidAction'] ?? 'HOLD'), reason: String(r['RunTarget.bidReason'] ?? ''),
            daysSince: r['RunTarget.daysSinceSuggestion'] != null ? num(r['RunTarget.daysSinceSuggestion']) : null,
            // order: [spend, cpc, clk, ctr, tos, units, roas, acos, roas_corr, impr]
            r2: ['r2Spend', 'r2Cpc', 'r2Clk', 'r2Ctr', 'r2Tos', 'r2Units', 'r2Roas', 'r2Acos', 'r2RoasCorr', 'r2Impr'].map(k => num(r[`RunTarget.${k}`])),
            r3: ['r3Spend', 'r3Cpc', 'r3Clk', 'r3Ctr', 'r3Tos', 'r3Units', 'r3Roas', 'r3Acos', 'r3RoasCorr', 'r3Impr'].map(k => num(r[`RunTarget.${k}`])),
            terms: [],
          });
        }
        // level 3 — attach search terms to their keyword
        const tgtByKw = new Map<string, Tgt>();
        for (const c of byCamp.values()) for (const t of c.targets) tgtByKw.set(c.id + '|' + t.keywordId, t);
        for (const r of st as Record<string, unknown>[]) {
          const t = tgtByKw.get(String(r['RunSearchTerm.campaignId'] ?? '') + '|' + String(r['RunSearchTerm.keywordId'] ?? '')); if (!t) continue;
          t.terms.push({ term: String(r['RunSearchTerm.searchTerm'] ?? ''), clicks: num(r['RunSearchTerm.clicks']),
            orders: num(r['RunSearchTerm.orders']), spend: num(r['RunSearchTerm.spend']), netRoas: num(r['RunSearchTerm.netRoas']),
            acos: num(r['RunSearchTerm.acos']), isWinner: r['RunSearchTerm.isWinner'] === true || r['RunSearchTerm.isWinner'] === 'true',
            isNegate: r['RunSearchTerm.isNegate'] === true || r['RunSearchTerm.isNegate'] === 'true',
            sp1: num(r['RunSearchTerm.d1Spend']), sp7: num(r['RunSearchTerm.d7Spend']), sp28: num(r['RunSearchTerm.d28Spend']),
            sl1: num(r['RunSearchTerm.d1Sales']), sl7: num(r['RunSearchTerm.d7Sales']), sl28: num(r['RunSearchTerm.d28Sales']) });
        }
        // Sponsored-Brands launch campaigns: replace the FACT-based (undercounted) per-target rows with correct
        // campaign-level measures from sb_campaign_report. No per-keyword drill — that data does not exist.
        // Measure order matches MeasTable: [spend, cpc, clk, ctr, tos, units, roas(est), acos, roasCorr(=est)].
        // TOS and units are NaN → rendered "—": SB's report has no competitive top-of-search IS (the one field
        // is placement mix, which contradicts Amazon's <5%) and no unit count. NaN keeps them out honestly.
        const sbMeas = (r: Record<string, unknown>, w: 'r2' | 'r3') => {
          const g = (k: string) => num(r[`SbLaunchCampaign.${w}${k}`]);
          return [g('Spend'), g('Cpc'), g('Clk'), g('Ctr'), NaN, NaN, g('Roas'), g('Acos'), g('Roas')];
        };
        for (const r of sb as Record<string, unknown>[]) {
          const c = byCamp.get(String(r['SbLaunchCampaign.campaignId'] ?? '')); if (!c) continue;
          c.isSb = true; c.targets = []; c.sbTgts = [];
          c.sbR2 = sbMeas(r, 'r2'); c.sbR3 = sbMeas(r, 'r3');
          // SB-native budget/spend/dark (V_LAUNCH_PHASE1 gives SB NULL budget + undercounted FACT spend — override)
          c.currentBudget = num(r['SbLaunchCampaign.currentBudget']);
          c.suggestedBudget = num(r['SbLaunchCampaign.suggestedBudget']);
          c.reason = String(r['SbLaunchCampaign.budgetReason'] ?? '');
          c.spendToday = num(r['SbLaunchCampaign.spendToday']);
          c.pctDark = num(r['SbLaunchCampaign.pctDark']);
        }
        // per-target drill under each SB campaign (keyword + product targets, with launch-controller bid suggestions)
        const sbWin = (r: Record<string, unknown>, w: 'r2' | 'r3'): SbWin => ({
          clk: num(r[`SbLaunchTarget.${w}Clk`]), spend: num(r[`SbLaunchTarget.${w}Spend`]),
          cpc: num(r[`SbLaunchTarget.${w}Cpc`]), sales: num(r[`SbLaunchTarget.${w}Sales`]), roas: num(r[`SbLaunchTarget.${w}Roas`]),
        });
        for (const r of sbk as Record<string, unknown>[]) {
          const c = byCamp.get(String(r['SbLaunchTarget.campaignId'] ?? '')); if (!c || !c.isSb) continue;
          (c.sbTgts ??= []).push({
            targetId: String(r['SbLaunchTarget.targetId'] ?? ''), adGroupId: String(r['SbLaunchTarget.adGroupId'] ?? ''),
            text: String(r['SbLaunchTarget.targetText'] ?? ''), targetType: String(r['SbLaunchTarget.targetType'] ?? ''),
            matchType: String(r['SbLaunchTarget.matchType'] ?? ''), bid: num(r['SbLaunchTarget.bid']),
            suggestedBid: r['SbLaunchTarget.suggestedBid'] != null ? num(r['SbLaunchTarget.suggestedBid']) : null,
            action: String(r['SbLaunchTarget.bidAction'] ?? 'HOLD'), reason: String(r['SbLaunchTarget.bidReason'] ?? ''),
            daysSince: r['SbLaunchTarget.daysSinceSuggestion'] != null ? num(r['SbLaunchTarget.daysSinceSuggestion']) : null,
            r2: sbWin(r, 'r2'), r3: sbWin(r, 'r3'),
          });
        }
        for (const c of byCamp.values()) if (c.sbTgts) c.sbTgts.sort((a, b) => b.r2.spend - a.r2.spend);
        for (const c of byCamp.values()) c.targets.sort((a, b) => b.r2[1] - a.r2[1]);
        setCamps([...byCamp.values()].sort((a, b) => a.day - b.day || a.name.localeCompare(b.name)));
      } catch { if (alive) setCamps([]); }
    })();
    return () => { alive = false; };
  }, []);

  const shown = useMemo(() => (camps ?? []).filter(c => c.targets.length > 0 || c.suggestedBudget > 0 || c.isSb), [camps]);
  if (!camps) return <div className="text-label text-faint">Loading new campaigns…</div>;
  if (shown.length === 0) return null;

  const budgetVal = (c: Camp) => drafts[c.id] ?? c.suggestedBudget;
  const budgetQueued = (c: Camp) => doQueue.items.some(i => i.action === 'BUDGET_CHANGE' && i.campaign_id === c.id);
  const approveBudget = (c: Camp) => doQueue.addItem({
    search_term: `__budget__${c.id}`, action: 'BUDGET_CHANGE', campaign: c.name, campaign_id: c.id,
    ad_group_id: '', targeting: '', keyword_id: '', match_type: '', target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0,
    current_bid: null, recommended_bid: null, campaign_type: 'SPONSORED_PRODUCTS', product: '',
    spend: 0, orders: 0, cpc: 0, conv_rate: 0, current_budget: c.currentBudget, recommended_budget: budgetVal(c), source: 'COACH',
  });
  const bidVal = (t: Tgt) => bidDrafts[t.keywordId] ?? (t.suggestedBid ?? t.currentBid ?? 0);
  const bidQueued = (t: Tgt) => doQueue.items.some(i => i.keyword_id === t.keywordId && ['INCREASE_BID', 'REDUCE_BID'].includes(i.action));
  const stopQueued = (t: Tgt) => doQueue.items.some(i => i.keyword_id === t.keywordId && i.action === 'STOP_TARGET');
  const base = (c: Camp, t: Tgt) => ({ campaign: c.name, campaign_id: c.id, ad_group_id: t.adGroupId, targeting: t.text,
    keyword_id: t.keywordId, match_type: t.isAuto ? 'Automatic' : (t.matchType || '').toUpperCase(),
    target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0, campaign_type: 'SPONSORED_PRODUCTS',
    product: t.isAuto ? 'Product Targeting' : 'Keyword', spend: 0, orders: 0, cpc: 0, conv_rate: 0 });
  const queueBid = (c: Camp, t: Tgt) => doQueue.addItem({ ...base(c, t), search_term: t.text,
    action: isRaise(t.action) || bidVal(t) > (t.currentBid ?? 0) ? 'INCREASE_BID' : 'REDUCE_BID',
    current_bid: t.currentBid, recommended_bid: bidVal(t), source: 'COACH' });
  const queueStop = (c: Camp, t: Tgt) => doQueue.addItem({ ...base(c, t), search_term: t.text, action: 'STOP_TARGET',
    current_bid: t.currentBid, recommended_bid: null });
  // level-3 search-term negate (queued by term text)
  const stNegQueued = (term: string) => doQueue.items.some(i => i.action === 'NEGATE_TERM' && i.search_term === term);
  const queueStNeg = (c: Camp, term: string) => doQueue.addItem({
    search_term: term, action: 'NEGATE_TERM', campaign: c.name, campaign_id: c.id, ad_group_id: '',
    targeting: term, keyword_id: '', match_type: 'NEGATIVE_EXACT', target_spend_8w: 0, target_orders_8w: 0,
    target_net_roas_8w: 0, current_bid: null, recommended_bid: null, campaign_type: 'SPONSORED_PRODUCTS', product: 'Keyword',
    spend: 0, orders: 0, cpc: 0, conv_rate: 0, source: 'COACH' });

  // toggles — clicking an already-applied suggestion unapplies it (removes it from the queue)
  const bidItem = (t: Tgt) => doQueue.items.find(i => i.keyword_id === t.keywordId && ['INCREASE_BID', 'REDUCE_BID'].includes(i.action));
  const stopItem = (t: Tgt) => doQueue.items.find(i => i.keyword_id === t.keywordId && i.action === 'STOP_TARGET');
  const budgetItem = (c: Camp) => doQueue.items.find(i => i.action === 'BUDGET_CHANGE' && i.campaign_id === c.id);
  const stNegItem = (term: string) => doQueue.items.find(i => i.action === 'NEGATE_TERM' && i.search_term === term);
  const toggleBid = (c: Camp, t: Tgt) => { const it = bidItem(t); if (it) doQueue.removeItem(it.id); else queueBid(c, t); };
  const toggleStop = (c: Camp, t: Tgt) => { const it = stopItem(t); if (it) doQueue.removeItem(it.id); else queueStop(c, t); };
  const toggleBudget = (c: Camp) => { const it = budgetItem(c); if (it) doQueue.removeItem(it.id); else approveBudget(c); };
  const toggleStNeg = (c: Camp, term: string) => { const it = stNegItem(term); if (it) doQueue.removeItem(it.id); else queueStNeg(c, term); };

  // per-campaign "apply all": every actionable bid (action ≠ HOLD/NO_BID) + the budget change (if it differs).
  // Click again once all applied → unapply them all. Clicking an individual applied row still toggles just it.
  const sugTargets = (c: Camp) => c.targets.filter(t => t.currentBid != null && !['HOLD', 'NO_BID', 'BLEED_WATCH', 'BLEED_STALE'].includes(t.action));
  const sugSbTargets = (c: Camp) => (c.sbTgts ?? []).filter(t => t.suggestedBid != null && !['HOLD', 'NO_BID', 'BLEED_WATCH', 'BLEED_STALE'].includes(t.action));
  const budgetSug = (c: Camp) => c.suggestedBudget > 0 && Math.abs(c.suggestedBudget - c.currentBudget) > 0.01;
  // top Not-applied / Already-applied filter (per target row): "applied" = we uploaded a change today (days_since < 1).
  const appliedToday = (d: number | null) => d != null && d < 1;
  const inFilter = (d: number | null) => actionFilter === 'done' ? appliedToday(d) : actionFilter === 'todo' ? !appliedToday(d) : true;
  const visTargets = (c: Camp) => c.targets.filter(t => inFilter(t.daysSince));
  const visSbTargets = (c: Camp) => (c.sbTgts ?? []).filter(t => inFilter(t.daysSince));
  // a card shows under the filter if it has any visible target — or, under Not-applied, a still-pending budget change.
  const cardVisible = (c: Camp) => actionFilter === 'all' ? true
    : ((c.isSb ? visSbTargets(c).length : visTargets(c).length) > 0 ? true
      : actionFilter === 'todo' && budgetSug(c));
  // negate search terms suggested across this campaign's targets (deduped by term text). SB has no
  // search-term drill, so c.targets is empty → no negates. "apply all" queues these alongside bids/budget.
  const campNegTerms = (c: Camp) => [...new Set(c.targets.flatMap(t => t.terms.filter(x => x.isNegate).map(x => x.term)))];
  const nSug = (c: Camp) => (c.isSb ? sugSbTargets(c).length : sugTargets(c).length) + (budgetSug(c) ? 1 : 0) + campNegTerms(c).length;
  const allApplied = (c: Camp) => nSug(c) > 0
    && (c.isSb ? sugSbTargets(c).every(t => !!sbBidItem(t)) : sugTargets(c).every(t => !!bidQueued(t)))
    && (!budgetSug(c) || budgetQueued(c))
    && campNegTerms(c).every(term => stNegQueued(term));
  const applyAll = (c: Camp) => {
    if (allApplied(c)) {
      if (c.isSb) sugSbTargets(c).forEach(t => { const it = sbBidItem(t); if (it) doQueue.removeItem(it.id); });
      else sugTargets(c).forEach(t => { const it = bidItem(t); if (it) doQueue.removeItem(it.id); });
      const b = budgetItem(c); if (b) doQueue.removeItem(b.id);
      campNegTerms(c).forEach(term => { const it = stNegItem(term); if (it) doQueue.removeItem(it.id); });
    } else {
      if (c.isSb) sugSbTargets(c).forEach(t => { if (!sbBidItem(t)) queueSbBid(c, t); });
      else sugTargets(c).forEach(t => { if (!bidQueued(t)) queueBid(c, t); });
      if (budgetSug(c) && !budgetQueued(c)) approveBudget(c);
      campNegTerms(c).forEach(term => { if (!stNegQueued(term)) queueStNeg(c, term); });
    }
  };

  // SB per-target bid editing — queues as SPONSORED_BRANDS. Default value = the launch-controller suggestion.
  const sbBidVal = (k: SbTgt) => bidDrafts[k.targetId] ?? (k.suggestedBid ?? k.bid);
  const sbBidItem = (k: SbTgt) => doQueue.items.find(i => i.keyword_id === k.targetId && ['INCREASE_BID', 'REDUCE_BID'].includes(i.action));
  const queueSbBid = (c: Camp, k: SbTgt) => doQueue.addItem({
    campaign: c.name, campaign_id: c.id, ad_group_id: k.adGroupId, targeting: k.text, search_term: k.text,
    keyword_id: k.targetId, match_type: (k.matchType || '').toUpperCase(), target_spend_8w: 0, target_orders_8w: 0,
    target_net_roas_8w: 0, campaign_type: 'SPONSORED_BRANDS', product: k.targetType === 'PRODUCT' ? 'Product Targeting' : 'Keyword',
    spend: 0, orders: 0, cpc: 0, conv_rate: 0,
    action: sbBidVal(k) >= k.bid ? 'INCREASE_BID' : 'REDUCE_BID', current_bid: k.bid, recommended_bid: sbBidVal(k), source: 'COACH' });
  const toggleSbBid = (c: Camp, k: SbTgt) => { const it = sbBidItem(k); if (it) doQueue.removeItem(it.id); else queueSbBid(c, k); };

  // compact SB per-target measures: spend · clicks · CPC · sales · net ROAS(est). No impressions/CTR (undercounted).
  const SbKwMeas = ({ rows }: { rows: { label: string; m: SbWin }[] }) => (
    <table className="text-label font-mono border-collapse">
      <thead><tr className="text-faint text-right">
        <th /><th className="font-normal px-2 py-0.5">spend</th><th className="font-normal px-2 py-0.5">clicks</th>
        <th className="font-normal px-2 py-0.5">CPC</th><th className="font-normal px-2 py-0.5">sales</th>
        <th className="font-normal px-2 py-0.5" title="net ROAS estimate = est. gross profit ÷ ad spend (COGS via list price; SB reports no units)">net ROAS ✓</th>
      </tr></thead>
      <tbody>{rows.map(r => (
        <tr key={r.label} className="text-right">
          <td className="text-faint text-left pr-2">{r.label}</td>
          <td className="text-muted px-2">${r.m.spend.toFixed(2)}</td>
          <td className="text-muted px-2">{r.m.clk}</td>
          <td className="text-muted px-2">{r.m.cpc ? `$${r.m.cpc.toFixed(2)}` : '—'}</td>
          <td className="text-muted px-2">${r.m.sales.toFixed(2)}</td>
          <td className={`px-2 ${r.m.clk ? roasCls(r.m.roas) : 'text-faint'}`}>{r.m.clk ? `${r.m.roas.toFixed(2)}×` : '—'}</td>
        </tr>
      ))}</tbody>
    </table>
  );

  // clicks-weighted aggregate of a campaign's targets → campaign-level last-day / prior-2d measures.
  // ROAS uses the campaign's authoritative net ROAS (LaunchPhase1), not a re-derivation.
  // exact aggregate of a campaign's targets. Order [spend,cpc,clk,ctr,tos,units,roas,acos].
  // CTR and ACoS are recomputed from summed raw amounts (impressions/sales backed out of each target's
  // ratio) — NOT a mean of ratios, which badly misleads. ROAS uses the campaign's authoritative net ROAS.
  const aggWin = (ts: Tgt[], win: 'r2' | 'r3', roas: number): number[] => {
    const sum = (f: (t: Tgt) => number) => ts.reduce((s, t) => s + f(t), 0);
    const spend = sum(t => t[win][0]), clk = sum(t => t[win][2]), units = sum(t => t[win][5]);
    const impr = sum(t => t[win][9] ?? 0);                                    // raw true impressions (exact)
    const sales = sum(t => t[win][7] > 0 ? 100 * t[win][0] / t[win][7] : 0);  // sales from ACoS
    const ctr = impr ? 100 * clk / impr : 0;
    // TOS is impression-weighted (Amazon's basis), NOT clicks-weighted — a high-TOS keyword with few
    // impressions shouldn't dominate. Weight each target's TOS by its true impressions.
    const tos = impr ? sum(t => t[win][4] * (t[win][9] ?? 0)) / impr : 0;
    const acos = sales ? 100 * spend / sales : 0;
    // corrected net ROAS = spend-weighted mean of targets' corrected ROAS (= Σ gp_corr ÷ Σ spend)
    const roasCorr = spend ? sum(t => (t[win][8] ?? 0) * t[win][0]) / spend : 0;
    return [spend, clk ? spend / clk : 0, clk, Math.round(ctr * 10) / 10, Math.round(tos), units, roas, Math.round(acos), roasCorr];
  };

  // subtle aligned measures table (Amazon-style: spend · CPC · clicks · CTR · TOS · units · net ROAS · ACoS).
  const MeasTable = ({ rows }: { rows: { label: string; m: number[] }[] }) => (
    <table className="text-label font-mono border-collapse">
      <thead><tr className="text-faint text-right">
        <th /><th className="font-normal px-2 py-0.5">spend</th><th className="font-normal px-2 py-0.5">CPC</th><th className="font-normal px-2 py-0.5">clicks</th>
        <th className="font-normal px-2 py-0.5">CTR</th><th className="font-normal px-2 py-0.5">TOS</th><th className="font-normal px-2 py-0.5">units</th>
        <th className="font-normal px-2 py-0.5" title="net ROAS = gross profit ÷ ad spend (1.0× = breakeven), with COGS charged to the product actually PURCHASED (by sale price), not the advertised one">net ROAS ✓</th>
        <th className="font-normal px-2 py-0.5" title="ad spend ÷ ad sales, like Amazon">ACoS</th>
      </tr></thead>
      <tbody>{rows.map(r => (
        <tr key={r.label} className="text-right">
          <td className="text-faint text-left pr-2">{r.label}</td>
          <td className="text-muted px-2">${r.m[0].toFixed(2)}</td>
          <td className="text-muted px-2">${r.m[1].toFixed(2)}</td>
          <td className="text-muted px-2">{r.m[2]}</td>
          <td className="text-muted px-2">{r.m[3]}%</td>
          <td className="text-muted px-2">{Number.isFinite(r.m[4]) ? `${r.m[4]}%` : '—'}</td>
          <td className="text-muted px-2">{Number.isFinite(r.m[5]) ? r.m[5] : '—'}</td>
          <td className={`px-2 ${r.m[8] != null ? roasCls(r.m[8]) : 'text-faint'}`}>{r.m[8] != null ? `${r.m[8].toFixed(2)}×` : '—'}</td>
          <td className="text-muted px-2">{r.m[7] ? `${r.m[7]}%` : '—'}</td>
        </tr>
      ))}</tbody>
    </table>
  );

  // level-3 search terms under a keyword: Spenders · Winners · Negates, each top-3 + "other".
  const TermGroups = ({ c, t }: { c: Camp; t: Tgt }) => {
    if (!t.terms.length) return null;
    const spenders = [...t.terms].sort((a, b) => b.spend - a.spend);
    const winners = t.terms.filter(x => x.isWinner).sort((a, b) => b.netRoas - a.netRoas);
    const negates = t.terms.filter(x => x.isNegate).sort((a, b) => b.spend - a.spend);
    // subtle inline negate — plain faint text, reddens on hover, ticks green once queued
    const NegBtn = ({ term }: { term: string }) => (
      <button onClick={() => toggleStNeg(c, term)} title={stNegQueued(term) ? 'applied — click to unapply' : 'negate this search term (exact)'}
        className={`text-[10px] shrink-0 ${stNegQueued(term) ? 'text-emerald-400' : 'text-faint hover:text-red-400'}`}>
        {stNegQueued(term) ? '✓ negated' : 'negate'}</button>
    );
    const more = (rest: STerm[]) => rest.length > 0
      ? <div className="text-label text-faint">+ {rest.length} other · {fM(rest.reduce((s, x) => s + x.spend, 0))}</div> : null;
    // per-day-average spend & sales run-rate across 1d / 7d / 28d (one aligned table). Used by Spenders + Winners.
    const PerDayGroup = ({ label, items, cls }: { label: string; items: STerm[]; cls: string }) => items.length === 0 ? null : (
      <div className="flex flex-col gap-0.5">
        <div className={`text-label font-medium ${cls}`}>{label} <span className="text-faint font-normal">({items.length})</span></div>
        <div className="overflow-x-auto">
          <table className="text-[11px] font-mono border-collapse">
            <thead>
              <tr className="text-faint">
                <th />
                <th colSpan={3} className="font-normal px-2 pb-0.5 text-center border-b border-border/20" title="average spend per campaign-day">spend/day</th>
                <th colSpan={3} className="font-normal px-2 pb-0.5 text-center border-b border-l border-border/20" title="average sales per campaign-day">sales/day</th>
                <th />
              </tr>
              <tr className="text-faint text-right">
                <th />
                <th className="font-normal px-2.5">1d</th><th className="font-normal px-2.5">7d</th><th className="font-normal px-2.5">28d</th>
                <th className="font-normal px-2.5 pl-3.5 border-l border-border/30">1d</th><th className="font-normal px-2.5">7d</th><th className="font-normal px-2.5">28d</th>
                <th />
              </tr>
            </thead>
            <tbody>{items.slice(0, 3).map(x => (
              <tr key={x.term} className="text-right">
                <td className="text-left text-muted pr-5 whitespace-nowrap" title={x.term}>“{x.term}”</td>
                <td className="text-faint px-2.5">${x.sp1.toFixed(2)}</td><td className="text-faint px-2.5">${x.sp7.toFixed(2)}</td><td className="text-faint px-2.5">${x.sp28.toFixed(2)}</td>
                <td className="text-faint px-2.5 pl-3.5 border-l border-border/30">${x.sl1.toFixed(2)}</td><td className="text-faint px-2.5">${x.sl7.toFixed(2)}</td><td className="text-faint px-2.5">${x.sl28.toFixed(2)}</td>
                <td className="pl-4 text-left"><NegBtn term={x.term} /></td>
              </tr>
            ))}</tbody>
          </table>
        </div>
        {more(items.slice(3))}
      </div>
    );
    // Negates — one compact line each, with the subtle negate
    const LineGroup = ({ label, items, cls }: { label: string; items: STerm[]; cls: string }) => items.length === 0 ? null : (
      <div className="flex flex-col gap-0.5">
        <div className={`text-label font-medium ${cls}`}>{label} <span className="text-faint font-normal">({items.length})</span></div>
        {items.slice(0, 3).map(x => (
          <div key={x.term} className="flex items-center gap-2 text-label leading-tight">
            <span className="flex-1 min-w-0 truncate text-muted" title={x.term}>“{x.term}”</span>
            <span className="font-mono text-faint shrink-0">{fM(x.spend)} · {x.clicks}c · {x.orders}o</span>
            <span className={`font-mono shrink-0 ${roasCls(x.netRoas)}`}>{x.netRoas.toFixed(2)}×</span>
            <NegBtn term={x.term} />
          </div>
        ))}
        {more(items.slice(3))}
      </div>
    );
    return (
      <div className="mt-1 pl-3 flex flex-col gap-1.5 border-l border-border/20">
        <PerDayGroup label="Spenders" items={spenders} cls="text-muted" />
        <PerDayGroup label="Winners" items={winners} cls="text-emerald-400" />
        <LineGroup label="Negates" items={negates} cls="text-red-400" />
      </div>
    );
  };

  return (
    <div className="flex flex-col gap-2">
      {shown.filter(cardVisible).map(c => {
        const isOpen = open[c.id];
        const nAction = c.targets.filter(t => !['HOLD', 'NO_BID', 'BLEED_WATCH', 'BLEED_STALE'].includes(t.action)).length;
        const nNeg = c.targets.reduce((s, t) => s + t.terms.filter(x => x.isNegate).length, 0);
        return (
          <div key={c.id} className="rounded-lg border border-violet-500/30 bg-violet-500/5 px-3 py-2">
            {/* header: chevron · name · age badge · counts · dark */}
            <div className="flex items-center gap-2">
              <button onClick={() => setOpen(p => ({ ...p, [c.id]: !isOpen }))} className="text-faint w-4 shrink-0" title={isOpen ? 'collapse' : 'expand'}>{isOpen ? '▾' : '▸'}</button>
              <span className="font-medium text-body truncate">{c.name}</span>
              <span className="text-label px-1.5 py-0.5 rounded bg-violet-600 text-white shrink-0">New · day {c.day}/20</span>
              {c.isSb && <span className="text-label px-1.5 py-0.5 rounded bg-amber-600/80 text-white shrink-0" title="Sponsored Brands — header is campaign-level (true CTR/impr); the drill is per-target clicks/spend/sales with launch-controller bids">SB</span>}
              <span className="text-label text-faint shrink-0">{c.isSb ? (() => { const n = c.sbTgts?.length ?? 0; const ch = sugSbTargets(c).length; return <>{n} tgt{ch ? ` · ${ch} to change` : ''}</>; })() : <>{c.targets.length} tgt{nAction ? ` · ${nAction} to change` : ''}{nNeg ? <span className="text-red-400"> · {nNeg} to negate</span> : null}</>}</span>
              <span className="flex-1" />
              {actionFilter !== 'done' && nSug(c) > 0 && (
                <button onClick={() => applyAll(c)} title={allApplied(c) ? 'unapply all suggestions for this campaign' : 'apply all suggestions for this campaign'}
                  className={`text-label px-2 py-0.5 rounded border shrink-0 ${allApplied(c) ? 'border-emerald-500/40 text-emerald-400' : 'border-violet-500/40 text-violet-300 hover:bg-violet-500/10'}`}>
                  {allApplied(c) ? `✓ applied ${nSug(c)}` : `apply all ${nSug(c)}`}</button>
              )}
              <span className="text-label font-mono text-faint shrink-0" title="spend today · % of day out of budget">{fM(c.spendToday)} · dark {c.pctDark}%</span>
            </div>
            {/* campaign aggregation — always visible so you can read the campaign at a glance.
                SB reads campaign-level measures from sb_campaign_report; SP aggregates its targets. */}
            <div className="mt-1 pl-6 overflow-x-auto">
              <MeasTable rows={c.isSb
                ? [{ label: 'last day', m: c.sbR2! }, { label: 'prior-2d', m: c.sbR3! }]
                : [{ label: 'last day', m: aggWin(c.targets, 'r2', c.roas1) }, { label: 'prior-2d', m: aggWin(c.targets, 'r3', c.roasPrev2) }]} />
            </div>
            {c.isSb && <div className="mt-0.5 pl-6 text-[11px] text-amber-400/70 leading-snug">Sponsored Brands — header is campaign-level (true CTR/impr from the campaign report); net ROAS estimated (no per-unit COGS); TOS &amp; units not reported. Expand for per-target clicks/spend/sales &amp; launch-controller bids.</div>}
            {/* budget row */}
            <div className="flex items-center gap-2 mt-1 pl-6">
              <span className="text-label text-faint flex-1 min-w-0 truncate" title={c.reason}>{c.reason}</span>
              <span className="text-label text-faint font-mono shrink-0">{fM(c.currentBudget)} → $</span>
              <input type="number" min={0} step={1} value={Number(budgetVal(c).toFixed(2))}
                onChange={e => setDrafts(p => ({ ...p, [c.id]: Math.max(0, Number(e.target.value) || 0) }))}
                className="w-16 text-label font-mono text-right rounded px-1.5 py-0.5 bg-surface/40 border border-blue-500/40 text-blue-300 focus:outline-none focus:ring-1 focus:ring-blue-500/40" />
              <button onClick={() => toggleBudget(c)} title={budgetQueued(c) ? 'applied — click to unapply' : 'queue this budget'}
                className={`text-label px-2 py-0.5 rounded border shrink-0 ${budgetQueued(c) ? 'border-emerald-500/40 text-emerald-400' : 'border-border text-muted hover:bg-white/5'}`}>{budgetQueued(c) ? '✓' : 'budget'}</button>
            </div>

            {!c.isSb && isOpen && (
              <div className="mt-2 pl-6 flex flex-col gap-2">
                {visTargets(c).map(t => {
                  const bq = bidQueued(t), sq = stopQueued(t);
                  const tNeg = t.terms.filter(x => x.isNegate).length;   // negate search terms under this group/keyword
                  return (
                    <div key={t.keywordId} className="border-t border-border/20 first:border-t-0 pt-1.5">
                      {/* row 1 — target + bid controls */}
                      <div className="flex items-center gap-2 text-label">
                        <span className={`w-12 shrink-0 font-medium ${actCls(t.action)}`}>{actLabel(t.action)}</span>
                        <span className="flex-1 min-w-0 truncate text-muted" title={t.text}>{prettyTarget(t.text)} <span className="text-faint">({t.isAuto ? 'auto' : t.matchType.toLowerCase()})</span></span>
                        {tNeg > 0 && <span className="text-red-400 shrink-0" title="search terms to negate under this group — expand ‘search terms’ to review">· {tNeg} to negate</span>}
                        {t.currentBid != null ? <>
                          <span className="text-faint font-mono shrink-0">${t.currentBid.toFixed(2)} → $</span>
                          <input type="number" min={0} step={0.05} value={Number(bidVal(t).toFixed(2))}
                            onChange={e => setBidDrafts(p => ({ ...p, [t.keywordId]: Math.max(0, Number(e.target.value) || 0) }))}
                            className="w-[4.2rem] font-mono rounded px-1.5 py-0.5 bg-surface/40 border border-blue-500/40 text-blue-300 focus:outline-none focus:ring-1 focus:ring-blue-500/40" />
                          <button onClick={() => toggleBid(c, t)} title={bq ? 'applied — click to unapply' : 'queue this bid'} className={`px-2 py-0.5 rounded border shrink-0 ${bq ? 'border-emerald-500/40 text-emerald-400' : 'border-border text-muted hover:bg-white/5'}`}>{bq ? '✓' : 'bid'}</button>
                        </> : <span className="text-faint shrink-0">no bid</span>}
                        <button onClick={() => toggleStop(c, t)} title={sq ? 'applied — click to unapply' : 'stop (pause) this target'} className={`px-2 py-0.5 rounded border shrink-0 ${sq ? 'border-emerald-500/40 text-emerald-400' : 'border-red-500/40 text-red-400 hover:bg-red-500/10'}`}>{sq ? '✓' : 'stop'}</button>
                      </div>
                      {/* measures table + why */}
                      <div className="pl-14 mt-0.5 overflow-x-auto">
                        <MeasTable rows={[{ label: 'last day', m: t.r2 }, { label: 'prior-2d', m: t.r3 }]} />
                      </div>
                      <div className="pl-14 text-label text-faint leading-snug">{bidWhy(t.action, t.reason, Math.max(t.r2[8] ?? 0, t.r3[8] ?? 0) >= 1.0, { units: (t.r2[5] ?? 0) + (t.r3[5] ?? 0), clicks: (t.r2[2] ?? 0) + (t.r3[2] ?? 0), roas: Math.max(t.r2[8] ?? 0, t.r3[8] ?? 0) })}</div>
                      {/* level 3 — collapsible search terms (Spenders · Winners · Negates) */}
                      {t.terms.length > 0 && (() => {
                        const to = openTerms[t.keywordId];
                        return (
                          <div className="pl-14 mt-0.5">
                            <button onClick={() => setOpenTerms(p => ({ ...p, [t.keywordId]: !to }))}
                              className="text-label text-faint hover:text-muted">{to ? '▾' : '▸'} search terms ({t.terms.length})</button>
                            {to && <TermGroups c={c} t={t} />}
                          </div>
                        );
                      })()}
                    </div>
                  );
                })}
              </div>
            )}

            {/* SB per-target drill — bid + launch-controller suggestion; clicks/spend/sales from SB reports; no per-target impr/CTR */}
            {c.isSb && isOpen && (
              <div className="mt-2 pl-6 flex flex-col gap-2">
                <div className="text-[11px] text-faint leading-snug">Per-target clicks · spend · sales &amp; bids, with the same launch-controller suggestion as SP (impressions/CTR omitted — undercounted at this grain).</div>
                {(c.sbTgts ?? []).length === 0 && <div className="text-label text-faint">No enabled targets.</div>}
                {visSbTargets(c).map(k => {
                  const bq = !!sbBidItem(k);
                  return (
                    <div key={k.targetId} className="border-t border-border/20 first:border-t-0 pt-1.5">
                      <div className="flex items-center gap-2 text-label">
                        <span className={`w-12 shrink-0 font-medium ${actCls(k.action)}`}>{actLabel(k.action)}</span>
                        <span className="flex-1 min-w-0 truncate text-muted" title={k.text}>{k.text} <span className="text-faint">({k.targetType === 'PRODUCT' ? 'product' : k.matchType.toLowerCase()})</span></span>
                        <span className="text-faint font-mono shrink-0">${k.bid.toFixed(2)} → $</span>
                        <input type="number" min={0} step={0.05} value={Number(sbBidVal(k).toFixed(2))}
                          onChange={e => setBidDrafts(p => ({ ...p, [k.targetId]: Math.max(0, Number(e.target.value) || 0) }))}
                          className="w-[4.2rem] font-mono rounded px-1.5 py-0.5 bg-surface/40 border border-blue-500/40 text-blue-300 focus:outline-none focus:ring-1 focus:ring-blue-500/40" />
                        <button onClick={() => toggleSbBid(c, k)} title={bq ? 'applied — click to unapply' : 'queue this bid'} className={`px-2 py-0.5 rounded border shrink-0 ${bq ? 'border-emerald-500/40 text-emerald-400' : 'border-border text-muted hover:bg-white/5'}`}>{bq ? '✓' : 'bid'}</button>
                      </div>
                      <div className="pl-14 mt-0.5 overflow-x-auto">
                        <SbKwMeas rows={[{ label: 'last day', m: k.r2 }, { label: 'prior-2d', m: k.r3 }]} />
                      </div>
                      <div className="pl-14 text-label text-faint leading-snug">{bidWhy(k.action, k.reason, Math.max(k.r2.roas ?? 0, k.r3.roas ?? 0) >= 1.0, { units: ((k.r2.sales ?? 0) + (k.r3.sales ?? 0)) > 0 ? 1 : 0, clicks: (k.r2.clk ?? 0) + (k.r3.clk ?? 0), roas: Math.max(k.r2.roas ?? 0, k.r3.roas ?? 0) })}</div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}
