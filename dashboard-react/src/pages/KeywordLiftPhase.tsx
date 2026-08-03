import { Fragment, useEffect, useMemo, useState } from 'react';
import { cubeLoad } from '../hooks/useCubeData';
import { useDoQueue } from '../hooks/useDoQueue';

// "Portfolio 80/20" phase — working campaigns (budget > low-budget cap), below the Out-of-budget
// section on Weekly Run. Ori 2026-07-30: 80% of spend to winner keywords, 20% exploration; most
// losers parked at $0.25; 1–2 probes at a time lifted to min(1.5× target CPC, $2), verdict at
// 20 clicks. Pure presentation over V_KEYWORD_LIFT via the KeywordLift cube (same column grammar
// as the OOB panel). Spec: architecture/OOB_BUDGET_PHASE.md §"Lever 2B".

type Row = {
  campaignId: string; campaignName: string; channel: string; budget: number; wDays: number;
  spendW: number; loserShare: number | null; activeProbes: number;
  keywordId: string; adGroupId: string; text: string; matchType: string;
  isAuto: boolean; isPt: boolean; bid: number | null;
  clicksW: number; kwSpendW: number; ordersW: number; roasW: number | null;
  clicks7d: number; roas7d: number | null; clicks828: number; roas828: number | null;
  clicks1d: number; roas1d: number | null; clicksPrev2: number; roasPrev2: number | null;
  campClicks1d: number; campRoas1d: number | null; campClicksPrev2: number; campRoasPrev2: number | null;
  clicks3d: number; roas3d: number | null; clicks414: number; roas414: number | null; isAutoCampaign: boolean;
  campClicks3d: number; campRoas3d: number | null; campClicks414: number; campRoas414: number | null;
  campClicks7d: number; campRoas7d: number | null; campClicks828: number; campRoas828: number | null;
  spend1d: number; campSpend1d: number;
  pctDark: number; slots: number; seatRank: number; isDefense: boolean; isSeasonal: boolean; isResearch: boolean; seasonalNow: boolean;
  vSuggestedBudget: number | null; vBudgetReason: string;
  targetCpc: number | null; kwClass: string; probing: boolean;
  probeClicks: number; probeRoas: number | null;
  role: string; action: string; suggestedBid: number | null; reason: string;
};

const num = (v: unknown): number | null => (v == null || v === '' ? null : Number(v));
const bool = (v: unknown): boolean => v === true || v === 'true';

const ACT_CLS: Record<string, string> = {
  KEEP: 'text-emerald-400', WINNER_FOUND: 'text-emerald-400', PROBE_START: 'text-emerald-400',
  PROBE_ADJUST: 'text-amber-400', PROBE_WAIT: 'text-muted', KEEP_TAIL: 'text-muted',
  EASE_TO_TARGET: 'text-amber-400', CUT_TO_TARGET: 'text-red-400', RAISE_TO_TARGET: 'text-emerald-400', RESEARCH_EASE: 'text-violet-400', AUTO_TRIM: 'text-amber-400', AUTO_RAISE: 'text-emerald-400', AUTO_BRAKE: 'text-amber-400', AUTO_FIT: 'text-amber-400', VOLUME_LIFT: 'text-emerald-400',
  PARK: 'text-red-400', IDLE: 'text-faint',
};
const ROLE_CLS: Record<string, string> = {
  FUNDER: 'text-emerald-400', WATCH: 'text-amber-400', PROBE: 'text-sky-300', CANDIDATE: 'text-sky-300',
  TRIAL: 'text-muted', PARKED: 'text-red-400', RETIRED: 'text-red-400', QUEUED: 'text-faint', ANTENNA: 'text-violet-400',
  IDLE: 'text-faint', DEFENSE: 'text-violet-400',
};
const ROLE_TIP: Record<string, string> = {
  FUNDER: 'funds the campaign — net ROAS ≥ 1.1× over the last 28 DAYS with ≥ 4 clicks of evidence (a stable financier, not one lucky click). Never pulled down by the target; raises are earned via the coacher sweet-spot.',
  WATCH: 'earning but not funder-grade over 28d (below 1.1× or under 4 clicks) — monitored: glides down toward target when above it, up (+10%/day) in season when far below.',
  PROBE: 'mid-test — owns its bid everywhere until the 20-click verdict: ≥ 1.0× → winner, else park $0.25 and the next candidate promotes.',
  CANDIDATE: 'next probe — lifts to max($1, min(1.5× target, $2)) when applied; seasonal keywords jump this queue.',
  TRIAL: 'still in its 4-click trial — 1 click does not break; no park or cut until 4 clicks of evidence.',
  PARKED: 'loser beyond the 20% (40% peak) exploration allowance — parked $0.25; returns through the seat queue.',
  RETIRED: 'tested ≥ 15 clicks/90d with 0 orders — permanent park; only its season (a last-year order in this same 28d window) revives it.',
  ANTENNA: 'kept alive cheap at the floor — its search terms are the information: negate the bad ones, harvest the winners (research keywords seed new broads; auto clauses feed the negate layer).',
  QUEUED: 'beyond the seats (budget ÷ $4) — waits at $0.25; the test resumes when a seat frees.',
  IDLE: 'seated but every probe slot is busy (2 off-season / 4 peak) — first in line when a verdict lands.',
  DEFENSE: 'the moat — never ROAS-parked, never negated; budget is the only lever.',
};
const CLASS_CLS: Record<string, string> = {
  WINNER: 'text-emerald-400', MARGINAL: 'text-amber-400', LOSER: 'text-red-400', IDLE: 'text-faint',
};

export function KeywordLiftPhase({ tier }: { tier: 'LOW' | 'HIGH' | 'SEASONAL' | 'SEASONAL_LOW' | 'AUTO' }) {
  const doQueue = useDoQueue();
  const [open, setOpen] = useState(false);
  const [openCamps, setOpenCamps] = useState<Record<string, boolean>>({});
  const [openWinners, setOpenWinners] = useState<Record<string, boolean>>({});
  // manual bid entry (Ori 2026-08-02): click the → $ cell on any keyword row to type a bid
  const [editBid, setEditBid] = useState<{ key: string; value: string } | null>(null);
  const [rows, setRows] = useState<Row[] | null>(null);
  const [failed, setFailed] = useState(false);

  type Neg = { campaignId: string; targetText: string; term: string; kind: string; clicks90: number; marketPurchases90: number; isBig: boolean; spend1d: number; adGroupIds: string };
  type WinTerm = { campaignId: string; targetText: string; term: string; kind: string; clicks90: number; orders90: number; roas90: number | null; isAddCandidate: boolean; adGroupIds: string };
  const [winTerms, setWinTerms] = useState<WinTerm[]>([]);
  type Bud = { budget: number; suggested: number | null; reason: string };
  const [budMap, setBudMap] = useState<Map<string, Bud>>(new Map());
  const [negs, setNegs] = useState<Neg[]>([]);
  const [oobIds, setOobIds] = useState<Set<string>>(new Set());
  // (v12: paused seasonal campaigns moved to their own "Seasonal Paused" section — PausedHistoryPhase)
  useEffect(() => {
    let alive = true;
    // SINGLE-HOME rule (Ori 2026-08-01): capping campaigns (dark > 10%) are owned by the
    // Out-of-budget section — hide them here; they return when darkness clears.
    cubeLoad({ dimensions: ['OobBudget.campaignId', 'OobBudget.pctDark'] }).then(rs => {
      if (!alive) return;
      const ids = new Set((rs as Record<string, unknown>[])
        .filter(r => (Number(r['OobBudget.pctDark']) || 0) > 10)
        .map(r => String(r['OobBudget.campaignId'] ?? '')));
      setOobIds(ids);
    }).catch(e => console.error('[lift] oob ownership fetch failed:', e));
    // campaign budget suggestions — the launch controller's budget ladder lives on (Ori 2026-08-01:
    // "the launch controller cards should be part of Portfolio 80/20"): its BUDGET engine feeds the
    // campaign rows here; its bid logic is superseded by the seat mechanism.
    Promise.all([
      cubeLoad({ dimensions: ['LaunchPhase1.campaignId', 'LaunchPhase1.currentBudget', 'LaunchPhase1.suggestedBudget', 'LaunchPhase1.budgetReason'] }).catch(() => []),
      cubeLoad({ dimensions: ['SbLaunchCampaign.campaignId', 'SbLaunchCampaign.currentBudget', 'SbLaunchCampaign.suggestedBudget', 'SbLaunchCampaign.budgetReason'] }).catch(() => []),
    ]).then(([sp, sb]) => {
      if (!alive) return;
      const m = new Map<string, Bud>();
      for (const [rows2, pre] of [[sp, 'LaunchPhase1'], [sb, 'SbLaunchCampaign']] as const) {
        for (const r of rows2 as Record<string, unknown>[]) {
          const id = String(r[`${pre}.campaignId`] ?? '');
          if (!id || m.has(id)) continue;
          m.set(id, { budget: num(r[`${pre}.currentBudget`]) ?? 0, suggested: num(r[`${pre}.suggestedBudget`]), reason: String(r[`${pre}.budgetReason`] ?? '') });
        }
      }
      setBudMap(m);
    });
    // negates layer (Ori 2026-08-01): the same two-window negate doctrine, for working campaigns —
    // kills the tier-list negate exception so each campaign truly shows once.
    cubeLoad({
      dimensions: ['OobSearchTerm.campaignId', 'OobSearchTerm.targetText', 'OobSearchTerm.searchTerm',
        'OobSearchTerm.kind', 'OobSearchTerm.clicks90d', 'OobSearchTerm.marketPurchases90d', 'OobSearchTerm.isBig', 'OobSearchTerm.spend1d', 'OobSearchTerm.adGroupIds'],
      filters: [{ member: 'OobSearchTerm.engine', operator: 'equals', values: ['LIFT'] },
                { member: 'OobSearchTerm.isNegate', operator: 'equals', values: ['true'] }],
    }).then(ts => {
      if (!alive) return;
      setNegs((ts as Record<string, unknown>[]).map(r => ({
        campaignId: String(r['OobSearchTerm.campaignId'] ?? ''),
        targetText: String(r['OobSearchTerm.targetText'] ?? ''),
        term: String(r['OobSearchTerm.searchTerm'] ?? ''),
        kind: String(r['OobSearchTerm.kind'] ?? ''),
        clicks90: num(r['OobSearchTerm.clicks90d']) ?? 0,
        marketPurchases90: num(r['OobSearchTerm.marketPurchases90d']) ?? 0,
        isBig: r['OobSearchTerm.isBig'] === true || r['OobSearchTerm.isBig'] === 'true',
        spend1d: num(r['OobSearchTerm.spend1d']) ?? 0,
        adGroupIds: String(r['OobSearchTerm.adGroupIds'] ?? ''),
      })));
    }).catch(() => {});
    // winners hierarchy (Ori 2026-08-02): terms that EARN 1.1x/90d, collapsed under their keyword
    cubeLoad({
      dimensions: ['OobSearchTerm.campaignId', 'OobSearchTerm.targetText', 'OobSearchTerm.searchTerm',
        'OobSearchTerm.kind', 'OobSearchTerm.clicks90d', 'OobSearchTerm.orders90d', 'OobSearchTerm.netRoas90d', 'OobSearchTerm.isAddCandidate', 'OobSearchTerm.adGroupIds'],
      filters: [{ member: 'OobSearchTerm.engine', operator: 'equals', values: ['LIFT'] },
                { member: 'OobSearchTerm.isWinner', operator: 'equals', values: ['true'] }],
    }).then(ts => {
      if (!alive) return;
      setWinTerms((ts as Record<string, unknown>[]).map(r => ({
        campaignId: String(r['OobSearchTerm.campaignId'] ?? ''),
        targetText: String(r['OobSearchTerm.targetText'] ?? ''),
        term: String(r['OobSearchTerm.searchTerm'] ?? ''),
        kind: String(r['OobSearchTerm.kind'] ?? ''),
        clicks90: num(r['OobSearchTerm.clicks90d']) ?? 0,
        orders90: num(r['OobSearchTerm.orders90d']) ?? 0,
        roas90: num(r['OobSearchTerm.netRoas90d']),
        isAddCandidate: r['OobSearchTerm.isAddCandidate'] === true || r['OobSearchTerm.isAddCandidate'] === 'true',
        adGroupIds: String(r['OobSearchTerm.adGroupIds'] ?? ''),
      })));
    }).catch(() => {});
    cubeLoad({
      dimensions: [
        'KeywordLift.campaignId', 'KeywordLift.campaignName', 'KeywordLift.channel', 'KeywordLift.budget', 'KeywordLift.wDays',
        'KeywordLift.campaignSpendW', 'KeywordLift.loserSharePct', 'KeywordLift.activeProbes',
        'KeywordLift.keywordId', 'KeywordLift.adGroupId', 'KeywordLift.targetText', 'KeywordLift.matchType',
        'KeywordLift.isAuto', 'KeywordLift.isPt', 'KeywordLift.currentBid',
        'KeywordLift.clicksW', 'KeywordLift.spendW', 'KeywordLift.ordersW', 'KeywordLift.roasW',
        'KeywordLift.targetCpc', 'KeywordLift.kwClass', 'KeywordLift.probing',
        'KeywordLift.probeClicks', 'KeywordLift.probeRoas',
        'KeywordLift.clicks7d', 'KeywordLift.roas7d', 'KeywordLift.clicks828', 'KeywordLift.roas828',
        'KeywordLift.clicks1d', 'KeywordLift.roas1d', 'KeywordLift.clicksPrev2', 'KeywordLift.roasPrev2',
        'KeywordLift.campClicks1d', 'KeywordLift.campRoas1d', 'KeywordLift.campClicksPrev2', 'KeywordLift.campRoasPrev2',
        'KeywordLift.clicks3d', 'KeywordLift.roas3d', 'KeywordLift.clicks414', 'KeywordLift.roas414', 'KeywordLift.isAutoCampaign',
        'KeywordLift.campClicks3d', 'KeywordLift.campRoas3d', 'KeywordLift.campClicks414', 'KeywordLift.campRoas414',
        'KeywordLift.campClicks7d', 'KeywordLift.campRoas7d', 'KeywordLift.campClicks828', 'KeywordLift.campRoas828',
        'KeywordLift.spend1d', 'KeywordLift.campSpend1d',
        'KeywordLift.pctDark', 'KeywordLift.slots', 'KeywordLift.seatRank',
        'KeywordLift.isDefense', 'KeywordLift.isSeasonal', 'KeywordLift.isResearch', 'KeywordLift.seasonalNow', 'KeywordLift.suggestedBudget', 'KeywordLift.budgetReason',
        'KeywordLift.role', 'KeywordLift.action', 'KeywordLift.suggestedBid', 'KeywordLift.reason',
      ],
    }).then(rs => {
      if (!alive) return;
      setRows((rs as Record<string, unknown>[]).map(r => ({
        campaignId: String(r['KeywordLift.campaignId'] ?? ''),
        campaignName: String(r['KeywordLift.campaignName'] ?? ''),
        channel: String(r['KeywordLift.channel'] ?? 'SP'),
        budget: num(r['KeywordLift.budget']) ?? 0,
        wDays: num(r['KeywordLift.wDays']) ?? 7,
        spendW: num(r['KeywordLift.campaignSpendW']) ?? 0,
        loserShare: num(r['KeywordLift.loserSharePct']),
        activeProbes: num(r['KeywordLift.activeProbes']) ?? 0,
        keywordId: String(r['KeywordLift.keywordId'] ?? ''),
        adGroupId: String(r['KeywordLift.adGroupId'] ?? ''),
        text: String(r['KeywordLift.targetText'] ?? ''),
        matchType: String(r['KeywordLift.matchType'] ?? ''),
        isAuto: bool(r['KeywordLift.isAuto']),
        isPt: bool(r['KeywordLift.isPt']),
        bid: num(r['KeywordLift.currentBid']),
        clicksW: num(r['KeywordLift.clicksW']) ?? 0,
        kwSpendW: num(r['KeywordLift.spendW']) ?? 0,
        ordersW: num(r['KeywordLift.ordersW']) ?? 0,
        roasW: num(r['KeywordLift.roasW']),
        targetCpc: num(r['KeywordLift.targetCpc']),
        kwClass: String(r['KeywordLift.kwClass'] ?? ''),
        probing: bool(r['KeywordLift.probing']),
        probeClicks: num(r['KeywordLift.probeClicks']) ?? 0,
        probeRoas: num(r['KeywordLift.probeRoas']),
        clicks1d: num(r['KeywordLift.clicks1d']) ?? 0,
        roas1d: num(r['KeywordLift.roas1d']),
        clicksPrev2: num(r['KeywordLift.clicksPrev2']) ?? 0,
        roasPrev2: num(r['KeywordLift.roasPrev2']),
        campClicks1d: num(r['KeywordLift.campClicks1d']) ?? 0,
        campRoas1d: num(r['KeywordLift.campRoas1d']),
        campClicksPrev2: num(r['KeywordLift.campClicksPrev2']) ?? 0,
        campRoasPrev2: num(r['KeywordLift.campRoasPrev2']),
        clicks3d: num(r['KeywordLift.clicks3d']) ?? 0,
        roas3d: num(r['KeywordLift.roas3d']),
        clicks414: num(r['KeywordLift.clicks414']) ?? 0,
        roas414: num(r['KeywordLift.roas414']),
        isAutoCampaign: r['KeywordLift.isAutoCampaign'] === true || r['KeywordLift.isAutoCampaign'] === 'true',
        campClicks3d: num(r['KeywordLift.campClicks3d']) ?? 0,
        campRoas3d: num(r['KeywordLift.campRoas3d']),
        campClicks414: num(r['KeywordLift.campClicks414']) ?? 0,
        campRoas414: num(r['KeywordLift.campRoas414']),
        clicks7d: num(r['KeywordLift.clicks7d']) ?? 0,
        roas7d: num(r['KeywordLift.roas7d']),
        clicks828: num(r['KeywordLift.clicks828']) ?? 0,
        roas828: num(r['KeywordLift.roas828']),
        campClicks7d: num(r['KeywordLift.campClicks7d']) ?? 0,
        campRoas7d: num(r['KeywordLift.campRoas7d']),
        campClicks828: num(r['KeywordLift.campClicks828']) ?? 0,
        campRoas828: num(r['KeywordLift.campRoas828']),
        spend1d: num(r['KeywordLift.spend1d']) ?? 0,
        campSpend1d: num(r['KeywordLift.campSpend1d']) ?? 0,
        pctDark: num(r['KeywordLift.pctDark']) ?? 0,
        slots: num(r['KeywordLift.slots']) ?? 1,
        seatRank: num(r['KeywordLift.seatRank']) ?? 99,
        isDefense: r['KeywordLift.isDefense'] === true || r['KeywordLift.isDefense'] === 'true',
        isSeasonal: r['KeywordLift.isSeasonal'] === true || r['KeywordLift.isSeasonal'] === 'true',
        isResearch: r['KeywordLift.isResearch'] === true || r['KeywordLift.isResearch'] === 'true',
        seasonalNow: r['KeywordLift.seasonalNow'] === true || r['KeywordLift.seasonalNow'] === 'true',
        vSuggestedBudget: num(r['KeywordLift.suggestedBudget']),
        vBudgetReason: String(r['KeywordLift.budgetReason'] ?? ''),
        role: String(r['KeywordLift.role'] ?? ''),
        action: String(r['KeywordLift.action'] ?? 'IDLE'),
        suggestedBid: num(r['KeywordLift.suggestedBid']),
        reason: String(r['KeywordLift.reason'] ?? ''),
      })));
    }).catch(() => { if (alive) setFailed(true); });
    return () => { alive = false; };
  }, []);

  const byCamp = useMemo(() => {
    const m = new Map<string, Row[]>();
    for (const r of rows ?? []) { const a = m.get(r.campaignId) ?? []; a.push(r); m.set(r.campaignId, a); }
    for (const a of m.values()) a.sort((x, y) => y.kwSpendW - x.kwSpendW);
    return m;
  }, [rows]);

  const actionable = (r: Row) => r.suggestedBid != null && r.keywordId !== '' && ['PARK', 'PARK_WAIT', 'PROBE_START', 'PROBE_ADJUST', 'EASE_TO_TARGET', 'CUT_TO_TARGET', 'RAISE_TO_TARGET', 'RESEARCH_EASE', 'AUTO_TRIM', 'AUTO_RAISE', 'AUTO_BRAKE', 'AUTO_FIT', 'VOLUME_LIFT'].includes(r.action);
  const bidItem = (r: Row) => doQueue.items.find(i => i.keyword_id === r.keywordId && ['INCREASE_BID', 'REDUCE_BID'].includes(i.action));
  const queueBid = (r: Row, manualBid?: number) => {
    const newBid = manualBid ?? r.suggestedBid;
    const prev = bidItem(r);
    if (prev) doQueue.removeItem(prev.id);
    doQueue.addItem({
      campaign: r.campaignName, campaign_id: r.campaignId, ad_group_id: r.adGroupId, targeting: r.text,
      search_term: r.text, keyword_id: r.keywordId,
      match_type: r.isAuto ? 'Automatic' : (r.matchType || '').toUpperCase(),
      target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0,
      campaign_type: r.channel === 'SB' ? 'SPONSORED_BRANDS' : 'SPONSORED_PRODUCTS',
      product: r.isAuto || r.isPt ? 'Product Targeting' : 'Keyword', spend: 0, orders: 0, cpc: 0, conv_rate: 0,
      action: (newBid ?? 0) >= (r.bid ?? 0) ? 'INCREASE_BID' : 'REDUCE_BID',
      current_bid: r.bid, recommended_bid: newBid, source: manualBid != null ? 'MANUAL' : 'COACH',
    });
  };
  const commitManual = (r: Row) => {
    const v = parseFloat(editBid?.value ?? '');
    if (!isNaN(v) && v >= 0.02 && r.keywordId) queueBid(r, Math.round(v * 100) / 100);
    setEditBid(null);
  };

  const lowCap = (rows ?? [])[0]?.wDays === 3 ? 30 : 20;   // peak cap $30, off-season $20
  // low-budget tiers read at launch cadence — last day + prev-2d, the OOB format (Ori 2026-08-02)
  const fast = tier === 'LOW' || tier === 'SEASONAL_LOW';
  // AUTO section (Ori 2026-08-02): 7d + 8-28d off-season; 3d + 4-14d in peak
  const auto = tier === 'AUTO';
  const inPeak = (rows ?? [])[0]?.wDays === 3;
  const autoPeak = auto && inPeak;
  const camps = [...byCamp.values()].filter(g => {
    const c = g[0];
    if (!c || c.isDefense) return false;
    // v24 (Ori 2026-08-02): auto campaigns have ONE home — the Auto section — dark or not.
    if (tier === 'AUTO') return c.isAutoCampaign;
    if (c.isAutoCampaign) return false;
    if (oobIds.has(c.campaignId)) return false;
    // v9 + v20 (Ori 2026-08-02): seasonal campaigns get their own sections, split by tier
    // like the evergreen 2x2 ("separate seasonal to seasonal low budget and seasonal").
    if (tier === 'SEASONAL') return c.isSeasonal && c.budget > lowCap;
    if (tier === 'SEASONAL_LOW') return c.isSeasonal && c.budget <= lowCap;
    if (c.isSeasonal) return false;
    return tier === 'LOW' ? c.budget <= lowCap : c.budget > lowCap;
  });
  const campIds = new Set(camps.map(g => g[0].campaignId));
  const visNegs = negs.filter(n => campIds.has(n.campaignId));

  const budgetItem = (id: string) => doQueue.items.find(i => i.action === 'BUDGET_CHANGE' && i.campaign_id === id);
  const budgetSug = (c: Row): Bud | null => {
    // SINGLE SOURCE (Ori 2026-08-01 tuning, knob #5): healthy campaigns get ONE budget rule —
    // the view-computed loss cut (W AND today < 0.6x → −20%, seasonal floor). No launch fallback.
    if (c.vSuggestedBudget != null && Math.abs(c.vSuggestedBudget - c.budget) > 0.01)
      return { budget: c.budget, suggested: c.vSuggestedBudget, reason: c.vBudgetReason };
    return null;
  };
  const budSugs = useMemo(() => camps.map(g => g[0]).filter(c => budgetSug(c)), [camps, budMap]);

  const sugs = (rows ?? []).filter(r => actionable(r) && campIds.has(r.campaignId));
  const allApplied = sugs.length > 0 && sugs.every(r => !!bidItem(r));
  const applyAll = () => {
    if (allApplied) {
      sugs.forEach(r => { const it = bidItem(r); if (it) doQueue.removeItem(it.id); });
      visNegs.forEach(n => { const it = negItem(n); if (it) doQueue.removeItem(it.id); });
      budSugs.forEach(c => { const it = budgetItem(c.campaignId); if (it) doQueue.removeItem(it.id); });
      // unapply also clears MANUAL bids in this section's campaigns (Ori 2026-08-02: "unapplied
      // did not effect the override manual bid") — sections are disjoint, so campaign scope is safe
      doQueue.items.filter(i => ['INCREASE_BID', 'REDUCE_BID'].includes(i.action) && campIds.has(i.campaign_id))
        .forEach(i => doQueue.removeItem(i.id));
    } else {
      sugs.forEach(r => { if (!bidItem(r)) queueBid(r); });
      visNegs.forEach(n => { if (!negItem(n)) queueNeg(n); });
      budSugs.forEach(c => { if (!budgetItem(c.campaignId)) queueBudget(c); });
    }
  };

  const queueBudget = (c: Row) => {
    // SINGLE SOURCE (fix, Ori 2026-08-02 'budget without a v'): queue the SAME suggestion the
    // row displays — budgetSug (view-computed) — not the legacy launch-cube map, which lacks
    // most campaigns and made both apply-all and the budget button silently no-op.
    const sug = budgetSug(c); if (!sug || sug.suggested == null) return;
    doQueue.addItem({
      search_term: `__budget__${c.campaignId}`, action: 'BUDGET_CHANGE', campaign: c.campaignName, campaign_id: c.campaignId,
      ad_group_id: '', targeting: '', keyword_id: '', match_type: '', target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0,
      current_bid: null, recommended_bid: null,
      campaign_type: c.channel === 'SB' ? 'SPONSORED_BRANDS' : 'SPONSORED_PRODUCTS', product: '',
      spend: 0, orders: 0, cpc: 0, conv_rate: 0, current_budget: sug.budget, recommended_budget: sug.suggested, source: 'COACH',
    });
  };
  const negItem = (n: Neg) => doQueue.items.find(i => i.action === 'NEGATE_TERM' && i.campaign_id === n.campaignId && i.search_term === n.term);
  const addItemFor = (w: { campaignId: string; term: string }) =>
    doQueue.items.find(i => i.action === 'ADD_KEYWORD' && i.campaign_id === w.campaignId && i.search_term === w.term);
  // research mode (Ori 2026-08-02): a winning term with no keyword of its own becomes a new
  // BROAD keyword at the $1 entry floor — the engine proposing exactly the manual playbook
  const queueAdd = (w: WinTerm) => {
    const c = (byCamp.get(w.campaignId) ?? [])[0];
    doQueue.addItem({
      search_term: w.term, action: 'ADD_KEYWORD', campaign: c?.campaignName ?? '', campaign_id: w.campaignId,
      ad_group_id: (w.adGroupIds || '').split(',')[0] || '', targeting: w.term, keyword_id: '',
      match_type: 'BROAD', target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0,
      current_bid: null, recommended_bid: 1.00,
      campaign_type: c?.channel === 'SB' ? 'SPONSORED_BRANDS' : 'SPONSORED_PRODUCTS', product: 'Keyword',
      spend: 0, orders: 0, cpc: 0, conv_rate: 0, source: 'COACH',
    });
  };
  const queueNeg = (n: Neg) => {
    const c = (byCamp.get(n.campaignId) ?? [])[0];
    // SB negatives REQUIRE an Ad Group Id (upload report 29): one row per ad group the term
    // ran in. SP falls back to Campaign Negative Keyword when the id is empty.
    const ags = n.adGroupIds ? n.adGroupIds.split(',') : [''];
    ags.forEach(ag => doQueue.addItem({
      search_term: n.term, action: 'NEGATE_TERM', campaign: c?.campaignName ?? '', campaign_id: n.campaignId, ad_group_id: ag,
      targeting: n.term, keyword_id: '', match_type: 'NEGATIVE_EXACT', target_spend_8w: 0, target_orders_8w: 0,
      target_net_roas_8w: 0, current_bid: null, recommended_bid: null,
      campaign_type: c?.channel === 'SB' ? 'SPONSORED_BRANDS' : 'SPONSORED_PRODUCTS', product: 'Keyword',
      spend: 0, orders: 0, cpc: 0, conv_rate: 0, source: 'COACH',
    }));
  };
  const nParks = sugs.filter(r => r.action === 'PARK').length;
  const nProbes = sugs.filter(r => r.action.startsWith('PROBE')).length;
  const nFound = (rows ?? []).filter(r => r.action === 'WINNER_FOUND' && campIds.has(r.campaignId)).length;

  return (
    <div className="mb-3 rounded-md border border-border bg-surface/30 px-3 py-2">
      <div className="flex items-center gap-1">
        <button className="text-label flex items-center gap-1 flex-1 min-w-0" onClick={() => setOpen(o => !o)}>
          <span className="text-faint">{open ? '▾' : '▸'}</span>
          <span className="font-medium text-sky-300">{tier === 'LOW' ? 'Low budget' : tier === 'SEASONAL' ? 'Seasonal' : tier === 'SEASONAL_LOW' ? 'Seasonal low budget' : tier === 'AUTO' ? 'Auto' : 'Portfolio 80/20'}</span>
          <span className="text-faint truncate">
            {failed ? '— unavailable' : rows
              ? `— ${camps.length} working campaigns · ${nParks} parks · ${nProbes} probes · ${nFound} winners found · ${visNegs.length} negates`
              : '— loading…'}
            {' '}· {auto ? 'goal: 4 fixed groups per campaign — negate bad terms, trim weak clauses, raise winners' : 'goal: 80% of spend on winners, 1–2 probes hunting the next one'}
          </span>
        </button>
        {rows && sugs.length > 0 && (
          <button onClick={applyAll}
            title={allApplied ? 'unapply all portfolio suggestions' : 'queue every park and probe bid'}
            className={`text-label px-2 py-0.5 rounded border shrink-0 ${allApplied ? 'border-emerald-500/40 text-emerald-300' : 'border-sky-500/40 text-sky-300 hover:bg-sky-500/10'}`}>
            {allApplied ? `✓ applied ${sugs.length + visNegs.length + budSugs.length}` : `apply all ${sugs.length + visNegs.length + budSugs.length}`}
          </button>
        )}
      </div>
      {open && rows && (
        <div className="mt-2 overflow-x-auto">
          <table className="text-label font-mono border-collapse">
            <thead>
              <tr className="text-faint text-right">
                <th className="font-normal text-left px-2 py-0.5">item — campaign ▸ keyword</th>
                <th className="font-normal px-2" title="share of the day out of budget (campaign) — Portfolio campaigns are ≤10% by ownership; losers % shown in the campaign meta">dark</th>
                <th className="font-normal px-2">now $</th>
                {autoPeak ? (<>
                  <th className="font-normal px-2" title="last 3 complete days — clicks + net ROAS (peak windows)">last 3d</th>
                  <th className="font-normal px-2" title="day 4 till 14 — same format">4–14d</th>
                </>) : fast ? (<>
                  <th className="font-normal px-2" title="last complete day — clicks + net ROAS">last day</th>
                  <th className="font-normal px-2" title="the 2 days before — same format">prev-2d</th>
                </>) : (<>
                  <th className="font-normal px-2" title="last 7 complete days — clicks + net ROAS">last 7d</th>
                  <th className="font-normal px-2" title="the 21 days before (day 8 till 28) — same format">8–28d</th>
                </>)}
                <th className="font-normal px-2" title="target CPC (last-year / band)">CPC/target</th>
                <th className="font-normal px-2 text-left" title="the keyword's job in the campaign economy">role</th>
                <th className="font-normal px-2 text-left">action</th>
                <th className="font-normal px-2">→ $</th>
                <th className="font-normal px-2"></th>
                <th className="font-normal px-2 text-left">why</th>
              </tr>
            </thead>
            <tbody>
              {camps.map(kws => {
                const c = kws[0];
                const expanded = !!openCamps[c.campaignId];
                return (
                <Fragment key={c.campaignId}>
                <tr className="text-right border-t border-border/40">
                  <td className="text-left px-2 py-0.5 text-body whitespace-nowrap">
                    <button className="text-faint pr-1" onClick={() => setOpenCamps(o => ({ ...o, [c.campaignId]: !o[c.campaignId] }))}>{expanded ? '▾' : '▸'}</button>
                    {c.campaignName}
                    <span className="text-faint text-label"> {c.channel}{c.isResearch && <span className="text-violet-400"> · research</span>} · {c.slots} seats · spent ${c.spendW.toFixed(2)}/{c.wDays}d · {c.activeProbes} probing · losers {c.loserShare != null ? `${c.loserShare.toFixed(0)}%` : '—'}</span>
                  </td>
                  <td className={`px-2 ${c.pctDark > 10 ? 'text-amber-400' : 'text-faint'}`}>{c.pctDark.toFixed(0)}%</td>
                  <td className="px-2 text-muted whitespace-nowrap">${c.budget.toFixed(0)} <span className="text-faint">bud</span> <span className="text-faint" title="spent yesterday">· ${c.campSpend1d.toFixed(2)}</span></td>
                  <td className="px-2 text-muted whitespace-nowrap">{autoPeak ? <>{c.campClicks3d}c{c.campRoas3d != null ? ` ${c.campRoas3d.toFixed(2)}×` : ' —'}</> : fast ? <>{c.campClicks1d}c{c.campRoas1d != null ? ` ${c.campRoas1d.toFixed(2)}×` : ' —'}</> : <>{c.campClicks7d}c{c.campRoas7d != null ? ` ${c.campRoas7d.toFixed(2)}×` : ' —'}</>}</td>
                  <td className="px-2 text-muted whitespace-nowrap">{autoPeak ? <>{c.campClicks414}c{c.campRoas414 != null ? ` ${c.campRoas414.toFixed(2)}×` : ' —'}</> : fast ? <>{c.campClicksPrev2}c{c.campRoasPrev2 != null ? ` ${c.campRoasPrev2.toFixed(2)}×` : ' —'}</> : <>{c.campClicks828}c{c.campRoas828 != null ? ` ${c.campRoas828.toFixed(2)}×` : ' —'}</>}</td>
                  <td className="px-2" />
                  <td className="px-2" />
                  <td className={`px-2 text-left whitespace-nowrap ${budgetSug(c) ? 'text-emerald-400' : 'text-muted'}`}>{budgetSug(c) ? 'budget' : 'hold'}</td>
                  <td className="px-2">{budgetSug(c) ? `$${budgetSug(c)!.suggested!.toFixed(2)}` : '—'}</td>
                  <td className="px-2">
                    {budgetSug(c) && (
                      <button onClick={() => { const it = budgetItem(c.campaignId); if (it) doQueue.removeItem(it.id); else queueBudget(c); }}
                        className={`px-1.5 py-0 rounded border ${budgetItem(c.campaignId) ? 'border-emerald-500/40 text-emerald-300' : 'border-border text-muted hover:bg-surface'}`}>
                        {budgetItem(c.campaignId) ? '✓' : 'budget'}
                      </button>
                    )}
                  </td>
                  <td className="px-2 text-left text-faint whitespace-nowrap">{budMap.get(c.campaignId)?.reason || (c.pctDark > 10 ? `dark ${c.pctDark.toFixed(0)}% · mixed windows — the bid brakes carry it today` : (c.loserShare ?? 0) > 20 ? 'losers over the 20% budget — parking the worst' : 'split healthy')}</td>
                </tr>
                {expanded && kws.map(k => {
                  const it = bidItem(k);
                  const kWins = winTerms.filter(w => w.campaignId === c.campaignId && w.targetText === k.text);
                  const wKey = `${c.campaignId}|${k.text}`;
                  const wOpen = !!openWinners[wKey];
                  return (
                  <Fragment key={`${c.campaignId}|${k.keywordId || k.text}`}>
                  <tr className="text-right border-t border-border/20 bg-surface/40">
                    <td className="text-left pl-8 pr-2 py-0.5 text-muted whitespace-nowrap">{k.text}
                      <span className="text-faint"> ({k.isAuto ? 'auto' : k.isPt ? 'PT' : (k.matchType || '').toLowerCase()}) · <span className={CLASS_CLS[k.kwClass] ?? ''}>{k.kwClass.toLowerCase()}</span>{k.isAuto ? null : k.seatRank <= k.slots ? <span className="text-sky-300"> · seat {k.seatRank}/{k.slots}</span> : <span className="text-faint"> · queue #{k.seatRank - k.slots}</span>}{k.seasonalNow && <span className="text-sky-400"> · seasonal</span>} · spent ${k.kwSpendW.toFixed(2)}</span>
                      {kWins.length > 0 && (
                        <button onClick={() => setOpenWinners(o => ({ ...o, [wKey]: !o[wKey] }))}
                          className="text-emerald-400 pl-1" title="winning search terms (>= 1.1x net ROAS over 90d) — click to expand">
                          {wOpen ? '▾' : '▸'} {kWins.length} winner{kWins.length > 1 ? 's' : ''}
                        </button>
                      )}</td>
                    <td className="px-2" />
                    <td className="px-2 text-muted whitespace-nowrap">{k.bid != null ? <>${k.bid.toFixed(2)} <span className="text-faint">bid</span></> : '—'}<span className="text-faint" title="spent yesterday"> · ${k.spend1d.toFixed(2)}</span></td>
                    <td className="px-2 text-muted whitespace-nowrap">{autoPeak ? <>{k.clicks3d}c{k.roas3d != null ? ` ${k.roas3d.toFixed(2)}×` : ' —'}</> : fast ? <>{k.clicks1d}c{k.roas1d != null ? ` ${k.roas1d.toFixed(2)}×` : ' —'}</> : <>{k.clicks7d}c{k.roas7d != null ? ` ${k.roas7d.toFixed(2)}×` : ' —'}</>}</td>
                    <td className="px-2 text-muted whitespace-nowrap">{autoPeak ? <>{k.clicks414}c{k.roas414 != null ? ` ${k.roas414.toFixed(2)}×` : ' —'}</> : fast ? <>{k.clicksPrev2}c{k.roasPrev2 != null ? ` ${k.roasPrev2.toFixed(2)}×` : ' —'}</> : <>{k.clicks828}c{k.roas828 != null ? ` ${k.roas828.toFixed(2)}×` : ' —'}</>}</td>
                    <td className="px-2 text-faint">{k.targetCpc != null ? `$${k.targetCpc.toFixed(2)}` : '—'}</td>
                    <td className={`px-2 text-left whitespace-nowrap ${ROLE_CLS[k.role] ?? 'text-faint'}`} title={ROLE_TIP[k.role] ?? ''}>{k.role.toLowerCase()}</td>
                    <td className={`px-2 text-left whitespace-nowrap ${ACT_CLS[k.action] ?? 'text-muted'}`}>{k.action.toLowerCase().replace(/_/g, ' ')}</td>
                    <td className="px-2">
                      {editBid?.key === `${c.campaignId}|${k.keywordId}` ? (
                        <input autoFocus type="number" step="0.01" min="0.02" value={editBid.value}
                          onChange={e => setEditBid({ key: editBid.key, value: e.target.value })}
                          onKeyDown={e => { if (e.key === 'Enter') commitManual(k); if (e.key === 'Escape') setEditBid(null); }}
                          onBlur={() => setEditBid(null)}
                          className="w-16 px-1 py-0 text-right font-mono bg-surface border border-blue-500/50 rounded" />
                      ) : (
                        <button title="click to set a bid manually (Enter queues it)"
                          onClick={() => k.keywordId && setEditBid({ key: `${c.campaignId}|${k.keywordId}`, value: (k.suggestedBid ?? k.bid ?? 1).toFixed(2) })}
                          className="hover:text-blue-300">
                          {bidItem(k)?.source === 'MANUAL' ? `$${bidItem(k)!.recommended_bid?.toFixed(2)} ✎` : k.suggestedBid != null ? `$${k.suggestedBid.toFixed(2)}` : '—'}
                        </button>
                      )}
                    </td>
                    <td className="px-2">
                      {(actionable(k) || it) && (
                        <button onClick={() => { const x = bidItem(k); if (x) doQueue.removeItem(x.id); else queueBid(k); }}
                          title={it ? 'queued — click to remove' : 'queue this bid'}
                          className={`px-1.5 py-0 rounded border ${it ? 'border-emerald-500/40 text-emerald-300' : 'border-border text-muted hover:bg-surface'}`}>
                          {it ? '✓' : 'bid'}
                        </button>
                      )}
                    </td>
                    <td className="px-2 text-left text-faint whitespace-nowrap">{k.reason}</td>
                  </tr>
                  {wOpen && kWins.map(w => (
                    <tr key={`${wKey}|${w.term}`} className="text-right border-t border-border/10">
                      <td className="text-left pl-14 pr-2 py-0.5 text-faint whitespace-nowrap">“{w.term}” <span>({w.kind.toLowerCase()})</span></td>
                      <td className="px-2" /><td className="px-2" />
                      <td className="px-2 text-faint whitespace-nowrap" colSpan={2}>{w.clicks90}c · {w.orders90} ord /90d</td>
                      <td className="px-2" /><td className="px-2" />
                      <td className="px-2 text-left text-emerald-400 whitespace-nowrap">winner {w.roas90 != null ? `${w.roas90.toFixed(2)}×` : ''}</td>
                      <td className="px-2" /><td className="px-2" />
                      <td className="px-2 text-left text-faint whitespace-nowrap">earns ≥1.1× net over 90d — never negated{w.isAddCandidate && <span className="text-violet-400"> · no keyword of its own</span>}</td>
                      <td className="px-2">
                        {w.isAddCandidate && (
                          <button onClick={() => { const it = addItemFor(w); if (it) doQueue.removeItem(it.id); else queueAdd(w); }}
                            title="add this winning term as a new BROAD keyword at $1 (research mode)"
                            className={`px-1.5 py-0 rounded border whitespace-nowrap ${addItemFor(w) ? 'border-emerald-500/40 text-emerald-300' : 'border-violet-500/40 text-violet-400 hover:bg-violet-500/10'}`}>
                            {addItemFor(w) ? '✓' : '+ broad'}
                          </button>
                        )}
                      </td>
                    </tr>
                  ))}
                  </Fragment>
                ); })}
                {expanded && visNegs.filter(n => n.campaignId === c.campaignId).map(n => {
                  const it = negItem(n);
                  return (
                  <tr key={`${c.campaignId}|neg|${n.term}`} className="text-right border-t border-border/20 bg-surface/40">
                    <td className="text-left pl-12 pr-2 py-0.5 text-muted whitespace-nowrap">{n.term}
                      <span className="text-faint"> · term under "{n.targetText}" ({n.kind.toLowerCase()})</span></td>
                    <td className="px-2" />
                    <td className="px-2 text-faint whitespace-nowrap" title="spent yesterday">{n.spend1d > 0 ? `$${n.spend1d.toFixed(2)}` : '—'}</td>
                    <td className="px-2" colSpan={4} />
                    <td className="px-2 text-left text-red-400 whitespace-nowrap">negate</td>
                    <td className="px-2" />
                    <td className="px-2">
                      <button onClick={() => { const x = negItem(n); if (x) doQueue.removeItem(x.id); else queueNeg(n); }}
                        className={`px-1.5 py-0 rounded border ${it ? 'border-emerald-500/40 text-emerald-300' : 'border-border text-muted hover:bg-surface'}`}>
                        {it ? '✓' : 'neg'}
                      </button>
                    </td>
                    <td className="px-2 text-left text-faint whitespace-nowrap">
                      {n.isBig
                        ? `big word — ${n.marketPurchases90.toLocaleString()} Amazon purchases/90d (SQP), full 90d trial here, no sales`
                        : `small word — ${n.clicks90} clicks · 0 sales here`}
                    </td>
                  </tr>
                ); })}
                </Fragment>
              ); })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
