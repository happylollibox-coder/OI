import { Fragment, useEffect, useMemo, useRef, useState } from 'react';
import { cubeLoad, cubeLoadWithMeta } from '../hooks/useCubeData';
import { findQueuedBid, findQueuedBudget, findQueuedNegates, useDoQueue } from '../hooks/useDoQueue';

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
  EASE_TO_TARGET: 'text-amber-400', CUT_TO_TARGET: 'text-red-400', RAISE_TO_TARGET: 'text-emerald-400', RESEARCH_EASE: 'text-violet-400', AUTO_TRIM: 'text-amber-400', AUTO_NUDGE: 'text-emerald-400', AUTO_DAY_RAISE: 'text-emerald-400', AUTO_DAY_TRIM: 'text-amber-400', AUTO_RAISE: 'text-emerald-400', AUTO_BRAKE: 'text-amber-400', AUTO_FIT: 'text-amber-400', VOLUME_LIFT: 'text-emerald-400', NUDGE_UP: 'text-emerald-400', CUT_TO_BREAKEVEN: 'text-red-400', APPLIED_HOLD: 'text-emerald-300/60',
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

// ── v27.64: OOB rows shown inside the Auto sections speak the OOB engine's grammar ──
// (actions/roles from V_OOB_KEYWORD — OobBudgetPhase's vocabulary, not the LIFT one above)
type OobKw = {
  campaignId: string; keywordId: string; adGroupId: string; text: string; matchType: string;
  isAuto: boolean; isPt: boolean; bid: number | null;
  clicks1d: number; spend1d: number; roas1d: number | null;
  clicksPrev2: number; roasPrev2: number | null;
  targetCpc: number | null; slots: number; seatRank: number; role: string;
  suggestedBid: number | null; bidAction: string; bidReason: string;
};
const OOB_ACT_CLS: Record<string, string> = {
  PROBE: 'text-emerald-400', SLOW: 'text-amber-400', APPLIED_HOLD: 'text-emerald-300/60', DARK_BRAKE: 'text-amber-400', PARK: 'text-red-400', TRIM_BID: 'text-amber-400', FIT_CPC: 'text-amber-400',
  PARK_WAIT: 'text-sky-300', ACTIVATE: 'text-emerald-400', RAISE_STRONG: 'text-emerald-400', RAISE_WEAK: 'text-emerald-400',
  HOLD: 'text-muted', NO_BID: 'text-faint',
};
const OOB_ROLE_CLS: Record<string, string> = {
  WINNER: 'text-emerald-400', WATCH: 'text-amber-400', PROBE: 'text-sky-300', CANDIDATE: 'text-sky-300',
  TRIAL: 'text-muted', PARKED: 'text-red-400', RETIRED: 'text-red-400', QUEUED: 'text-faint', IDLE: 'text-faint',
};
const OOB_ROLE_TIP: Record<string, string> = {
  WINNER: 'net ROAS ≥ 1.0 over the LAST 3 DAYS — always seated first; while the campaign caps its lever is the budget raise, never a bid raise. Over 4 clicks yesterday with no sale, a 90d-proven seat still brakes 5%/day.',
  WATCH: 'proven over 90 days but cold in the last 3 — holds its seat at up to 4 clicks/day; above 4 clicks yesterday the seat exemption stops and the bid brakes a flat 5%/day.',
  PROBE: 'mid-test — keeps its probe bid while it holds a seat; beyond the seats it pauses at $0.25.',
  CANDIDATE: 'parked and holding a seat — ACTIVATEs at max($1, min(1.5× target, $1.50)), paced by the 20% rule.',
  TRIAL: 'seated mid-test gathering clicks — TRIM/DARK_BRAKE only with real evidence (≥ 4 clicks / clicked yesterday).',
  RETIRED: 'tested ≥ 15 clicks/90d with 0 orders — permanent park; its seat goes to the next candidate.',
  QUEUED: 'beyond the seats (budget ÷ $4) — waits at $0.25 in the queue; the test resumes when a seat frees.',
};

export function KeywordLiftPhase({ tier, defaultOpen }: { tier: 'LOW' | 'HIGH' | 'SEASONAL' | 'SEASONAL_LOW' | 'AUTO' | 'AUTO_LOW'; defaultOpen?: boolean }) {
  const doQueue = useDoQueue();
  // Ori 2026-08-17 ("when there is an open action hierarchy should be Expanded"): the page opens
  // sections that carry open actions via defaultOpen. openState stays null until the FIRST user
  // click, so a defaultOpen that arrives (or flips) later can never override an explicit close —
  // a click is final. The lazy fetch gates below key off the derived `open`, so defaultOpen
  // flipping it true triggers the fetch naturally.
  const [openState, setOpenState] = useState<boolean | null>(null);
  const open = openState ?? defaultOpen ?? false;
  const [openCamps, setOpenCamps] = useState<Record<string, boolean>>({});
  const [openWinners, setOpenWinners] = useState<Record<string, boolean>>({});
  // manual bid entry (Ori 2026-08-02): click the → $ cell on any keyword row to type a bid
  const [editBid, setEditBid] = useState<{ key: string; value: string } | null>(null);
  const [editBudget, setEditBudget] = useState<{ key: string; value: string } | null>(null);
  const [rows, setRows] = useState<Row[] | null>(null);
  const [failed, setFailed] = useState(false);

  type Neg = { campaignId: string; targetText: string; term: string; kind: string; clicks90: number; marketPurchases90: number; isBig: boolean; spend1d: number; adGroupIds: string };
  type WinTerm = { campaignId: string; targetText: string; term: string; kind: string; clicks90: number; orders90: number; roas90: number | null; isAddCandidate: boolean; adGroupIds: string };
  const [winTerms, setWinTerms] = useState<WinTerm[]>([]);
  type Bud = { budget: number; suggested: number | null; reason: string };
  const [budMap, setBudMap] = useState<Map<string, Bud>>(new Map());
  const [negs, setNegs] = useState<Neg[]>([]);
  const [oobIds, setOobIds] = useState<Set<string>>(new Set());
  // v27.64: the OOB engine's live keyword decisions for OOB-owned auto campaigns (fetch below)
  const [oobKws, setOobKws] = useState<OobKw[]>([]);
  // (v12: paused seasonal campaigns moved to their own "Seasonal Paused" section — PausedHistoryPhase)
  // LAZY SECTION (WEEKLY_RUN_UX.md: sections fetch ONLY on first expand). This one effect fires
  // FIVE cube queries (ownership, launch budgets ×2, negates, winners, the KeywordLift body) — and
  // the page renders six KeywordLiftPhase instances. On mount that was the bulk of the ~17
  // ceiling-view queries fired at page open, 40–120s each cold ("why is it not loading"). The
  // deferred-OOB effect below inherits the gate: deferIds stays [] until these rows land.
  const fetchedRef = useRef(false);
  useEffect(() => {
    if (!open || fetchedRef.current) return;
    fetchedRef.current = true;
    let alive = true;
    // SINGLE-HOME rule (Ori 2026-08-01): OOB-owned campaigns belong to the Out-of-budget
    // section — hide them here; they return when ownership clears.
    // v27.46: ownership is the BACKEND flag — V_CAMPAIGN_CAP_STATE.is_oob_owned via the OobBudget
    // cube (hysteresis ENTER days_capped_7d >= 2 / EXIT at 0), the same single membership function
    // both bid engines read. The old client-side derivation (v27.15: pctDark > 10 ||
    // utilization >= 1.0 — anchor-day only, blind to silent caps) survives ONLY as a fallback
    // while the cube cache still serves the pre-v27.46 schema; pctDark/utilization stay as
    // display values on the rows below.
    const legacyOwned = (r: Record<string, unknown>) =>
      (Number(r['OobBudget.pctDark']) || 0) > 10 || (Number(r['OobBudget.utilization']) || 0) >= 1.0;
    const toOobIds = (rs: Record<string, unknown>[], owned: (r: Record<string, unknown>) => boolean) =>
      new Set(rs.filter(owned).map(r => String(r['OobBudget.campaignId'] ?? '')));
    cubeLoadWithMeta({ dimensions: ['OobBudget.campaignId', 'OobBudget.pctDark', 'OobBudget.utilization', 'OobBudget.isOobOwned'] }).then(res => {
      if (!alive) return;
      if (res.error) {
        // stale cube schema rejects the unknown isOobOwned dimension as an API-level error —
        // cubeLoad* RESOLVES with {data: [], error} on that path (it never rejects), so the old
        // .catch fallback here was dead code (review 2026-08-16): branch on res.error instead
        // and retry the legacy shape.
        cubeLoadWithMeta({ dimensions: ['OobBudget.campaignId', 'OobBudget.pctDark', 'OobBudget.utilization'] }).then(res2 => {
          if (!alive) return;
          if (res2.error) { console.error('[lift] oob ownership fetch failed:', res2.error); return; }
          setOobIds(toOobIds(res2.data as Record<string, unknown>[], legacyOwned));
        });
        return;
      }
      const rows2 = res.data as Record<string, unknown>[];
      // flag absent from the response (cube cache lag) → degrade to the old derivation
      const hasFlag = rows2.some(r => r['OobBudget.isOobOwned'] !== undefined && r['OobBudget.isOobOwned'] !== null);
      setOobIds(toOobIds(rows2, hasFlag ? (r => bool(r['OobBudget.isOobOwned'])) : legacyOwned));
    });
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
      filters: [{ member: 'OobSearchTerm.engine', operator: 'equals', values: ['LIFT', 'OOB'] },
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
      filters: [{ member: 'OobSearchTerm.engine', operator: 'equals', values: ['LIFT', 'OOB'] },
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
  }, [open]);

  const byCamp = useMemo(() => {
    const m = new Map<string, Row[]>();
    for (const r of rows ?? []) { const a = m.get(r.campaignId) ?? []; a.push(r); m.set(r.campaignId, a); }
    for (const a of m.values()) a.sort((x, y) => y.kwSpendW - x.kwSpendW);
    return m;
  }, [rows]);

  const actionable = (r: Row) => r.suggestedBid != null && r.keywordId !== '' && ['PARK', 'PARK_WAIT', 'PROBE_START', 'PROBE_ADJUST', 'EASE_TO_TARGET', 'CUT_TO_TARGET', 'RAISE_TO_TARGET', 'RESEARCH_EASE', 'AUTO_TRIM', 'AUTO_NUDGE', 'AUTO_DAY_RAISE', 'AUTO_DAY_TRIM', 'AUTO_RAISE', 'AUTO_BRAKE', 'AUTO_FIT', 'VOLUME_LIFT', 'NUDGE_UP', 'CUT_TO_BREAKEVEN'].includes(r.action);
  // Unified queued-state (Ori 2026-08-17, "approve in section or snapshot → both show approve"):
  // display keys on the row's canonical id via the shared finders — queued from ANY surface at
  // ANY value (BOOST/SCALE_UP included) renders as queued, and the row click removes it whatever
  // its origin. Value-exact matching survives ONLY in bulk unapply (ourBidItem & co below).
  const bidItem = (r: Row) => findQueuedBid(doQueue.items, r.keywordId);
  // when the queued value is not this row's own suggestion (> $0.005 apart, or the row has no
  // suggestion at all), the ✓ carries the QUEUED value so the mark is honest about what applies
  const atValue = (queued: number | null | undefined, own: number | null | undefined): string =>
    queued != null && (own == null || Math.abs(queued - own) > 0.005) ? ` at $${queued.toFixed(2)}` : '';
  const queuedTitle = (at: string) =>
    at ? `queued from another view${at} — click to remove it` : 'queued — click to remove';
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
  const fast = tier === 'LOW' || tier === 'SEASONAL_LOW' || tier === 'AUTO_LOW';  // v27.2: auto-low reads at launch cadence too
  // AUTO section (Ori 2026-08-02): 7d + 8-28d off-season; 3d + 4-14d in peak
  const auto = tier === 'AUTO' || tier === 'AUTO_LOW';
  const inPeak = (rows ?? [])[0]?.wDays === 3;
  const autoPeak = tier === 'AUTO' && inPeak;  // AUTO_LOW stays on 1d/prev-2d even in peak

  // ── v27.64 (2026-08-16): close the AUTO deferral hole ─────────────────────────────────────
  // When the OOB engine owns an auto campaign (capped ≥2d of 7), LIFT stands down: every keyword
  // row arrives as DEFER_OOB — "out-of-budget engine owns the bids". But the OOB panel drops
  // auto campaigns on sight (v24: "auto campaigns live in the Auto section — never here"), and
  // this section never read the OobKeyword cube. Each engine pointed at the other, and the OOB
  // engine's live decisions — computed, correct, sitting in V_OOB_KEYWORD — rendered NOWHERE:
  // ~$46/day of near-zero-return spend (0.13× over 3d) carrying DARK_BRAKE rows nobody could see
  // or apply. Ori hit the hole himself: "this campaign in oob one keyword has 22 clicks and no
  // bid trimming. why?" — the trim existed; no surface showed it. So: for exactly the deferring
  // campaigns, fetch their V_OOB_KEYWORD rows and render THEM under the campaign row, in place
  // of the LIFT rows that all said the same sentence. Verdict precedence at export time stays
  // the preflight gate's job (architecture/ENGINE_PREFLIGHT.md) — this panel only makes the
  // decisions visible and queueable.
  const deferIds = useMemo(() => {
    if (tier !== 'AUTO' && tier !== 'AUTO_LOW') return [] as string[];
    const ids = new Set<string>();
    for (const r of rows ?? []) {
      if (r.action !== 'DEFER_OOB' || !r.isAutoCampaign) continue;
      if (tier === 'AUTO' ? r.budget > lowCap : r.budget <= lowCap) ids.add(r.campaignId);
    }
    return [...ids].sort();
  }, [rows, tier, lowCap]);
  useEffect(() => {
    // Lazy-gated via the main fetch (WEEKLY_RUN_UX.md): deferIds derives from rows, which stay
    // null until first expand — the !open belt keeps this true even if that coupling ever changes.
    // No one-shot ref here: this fetch legitimately re-fires when deferIds changes.
    if (!open) return;
    if (deferIds.length === 0) { setOobKws([]); return; }
    let alive = true;
    cubeLoad({
      dimensions: [
        'OobKeyword.campaignId', 'OobKeyword.keywordId', 'OobKeyword.adGroupId', 'OobKeyword.targetText',
        'OobKeyword.matchType', 'OobKeyword.isAuto', 'OobKeyword.isPt', 'OobKeyword.currentBid',
        'OobKeyword.clicks1d', 'OobKeyword.spend1d', 'OobKeyword.roas1d',
        'OobKeyword.clicksPrev2', 'OobKeyword.roasPrev2',
        'OobKeyword.targetCpc', 'OobKeyword.slots', 'OobKeyword.seatRank', 'OobKeyword.role',
        'OobKeyword.suggestedBid', 'OobKeyword.bidAction', 'OobKeyword.bidReason',
      ],
      // equals + id array = OR — one fetch for exactly the deferring campaigns, nothing else
      filters: [{ member: 'OobKeyword.campaignId', operator: 'equals', values: deferIds }],
    }).then(rs => {
      if (!alive) return;
      setOobKws((rs as Record<string, unknown>[]).map(r => ({
        campaignId: String(r['OobKeyword.campaignId'] ?? ''),
        keywordId: String(r['OobKeyword.keywordId'] ?? ''),
        adGroupId: String(r['OobKeyword.adGroupId'] ?? ''),
        text: String(r['OobKeyword.targetText'] ?? ''),
        matchType: String(r['OobKeyword.matchType'] ?? ''),
        isAuto: bool(r['OobKeyword.isAuto']),
        isPt: bool(r['OobKeyword.isPt']),
        bid: num(r['OobKeyword.currentBid']),
        clicks1d: num(r['OobKeyword.clicks1d']) ?? 0,
        spend1d: num(r['OobKeyword.spend1d']) ?? 0,
        roas1d: num(r['OobKeyword.roas1d']),
        clicksPrev2: num(r['OobKeyword.clicksPrev2']) ?? 0,
        roasPrev2: num(r['OobKeyword.roasPrev2']),
        targetCpc: num(r['OobKeyword.targetCpc']),
        slots: num(r['OobKeyword.slots']) ?? 1,
        seatRank: num(r['OobKeyword.seatRank']) ?? 99,
        role: String(r['OobKeyword.role'] ?? ''),
        suggestedBid: num(r['OobKeyword.suggestedBid']),
        bidAction: String(r['OobKeyword.bidAction'] ?? 'HOLD'),
        bidReason: String(r['OobKeyword.bidReason'] ?? ''),
      })));
    }).catch(e => {
      // NON-FATAL by design: with no OOB rows the deferring campaigns render exactly as before
      // this fix — DEFER_OOB reason visible on every keyword row. A broken fetch must never
      // blank the section.
      console.error('[lift] oob keyword fetch failed:', e);
    });
    return () => { alive = false; };
  }, [open, deferIds]);
  const oobByCamp = useMemo(() => {
    const m = new Map<string, OobKw[]>();
    for (const k of oobKws) { const a = m.get(k.campaignId) ?? []; a.push(k); m.set(k.campaignId, a); }
    for (const a of m.values()) a.sort((x, y) => y.spend1d - x.spend1d);
    return m;
  }, [oobKws]);

  const camps = [...byCamp.values()].filter(g => {
    const c = g[0];
    if (!c || c.isDefense) return false;
    // v24 + v27 (Ori 2026-08-03): auto campaigns have ONE home — the Auto sections, split by
    // tier like everything else — dark or not.
    if (tier === 'AUTO') return c.isAutoCampaign && c.budget > lowCap;
    if (tier === 'AUTO_LOW') return c.isAutoCampaign && c.budget <= lowCap;
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

  const budgetItem = (id: string) => findQueuedBudget(doQueue.items, id);
  const budgetSug = (c: Row): Bud | null => {
    // SINGLE SOURCE (Ori 2026-08-01 tuning, knob #5): healthy campaigns get ONE budget rule —
    // the view-computed loss cut (W AND today < 0.6x → −20%, seasonal floor). No launch fallback.
    if (c.vSuggestedBudget != null && Math.abs(c.vSuggestedBudget - c.budget) > 0.01)
      return { budget: c.budget, suggested: c.vSuggestedBudget, reason: c.vBudgetReason };
    // LAUNCH POPULATION: budMap only holds low-budget launch campaigns, whose budget engine is
    // the launch controller's ladder ("its BUDGET engine feeds the campaign rows here"). Its
    // graduation raise is the only path out of launch mode — it must be actionable, not just
    // narrated in the why-column while the amount shows "—". Knob #5 is untouched: healthy
    // non-launch campaigns never appear in budMap.
    const lb = budMap.get(c.campaignId);
    if (lb?.suggested != null && Math.abs(lb.suggested - c.budget) > 0.01)
      return { budget: c.budget, suggested: lb.suggested, reason: lb.reason };
    return null;
  };
  const budSugs = useMemo(() => camps.map(g => g[0]).filter(c => budgetSug(c)), [camps, budMap]);

  const sugs = (rows ?? []).filter(r => actionable(r) && campIds.has(r.campaignId));

  // ── v27.64: DO-queue wiring for the deferred-OOB rows ──
  // Same gate as OobBudgetPhase.bidSug; the INCREASE/REDUCE direction is the ONE permitted piece
  // of glue (the same comparison the OOB panel makes at queueKwBid) — everything else is view values.
  const oobActionable = (k: OobKw) => k.suggestedBid != null && k.keywordId !== '' && !['HOLD', 'NO_BID'].includes(k.bidAction);
  const oobDir = (k: OobKw) => ((k.suggestedBid ?? 0) >= (k.bid ?? 0) ? 'INCREASE_BID' : 'REDUCE_BID');
  // Ours = exactly this row's suggestion — the ONLY thing bulk unapply may remove (a foreign-
  // valued item comes off via its own row's click, never in bulk). Display and the row click
  // key on findQueuedBid alone: queued from any surface at any value shows (and removes) here.
  const ourOobItem = (k: OobKw) => {
    const it = findQueuedBid(doQueue.items, k.keywordId);
    return it && it.action === oobDir(k) && it.recommended_bid === k.suggestedBid ? it : undefined;
  };
  const queueOobBid = (k: OobKw) => {
    const c = (byCamp.get(k.campaignId) ?? [])[0];
    doQueue.addItem({
      campaign: c?.campaignName ?? '', campaign_id: k.campaignId, ad_group_id: k.adGroupId, targeting: k.text,
      search_term: k.text, keyword_id: k.keywordId,
      match_type: k.isAuto ? 'Automatic' : (k.matchType || '').toUpperCase(),
      target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0,
      campaign_type: 'SPONSORED_PRODUCTS',  // the defer population is SP autos — no SB auto campaigns exist
      product: k.isAuto || k.isPt ? 'Product Targeting' : 'Keyword', spend: 0, orders: 0, cpc: 0, conv_rate: 0,
      action: oobDir(k), current_bid: k.bid, recommended_bid: k.suggestedBid, source: 'COACH',
    });
  };
  // ONE memoised list feeds both the apply-all count and the set it queues (RevivalsPhase
  // discipline) — every row the view priced. Key-queued rows STAY in the list and count as DONE
  // (queued from any surface = approved); apply skips them at click time instead of excluding them.
  const oobApplicable = useMemo(
    () => oobKws.filter(k => oobActionable(k)),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [oobKws, doQueue.items]);

  // the ONE list behind "apply all N": LIFT bid sugs + negates + budgets + deferred-OOB bids —
  // the count shown and the set queued both come from these four, nothing else
  const nSug = sugs.length + visNegs.length + budSugs.length + oobApplicable.length;
  // "applied" = key-queued from ANY surface at ANY value — an approval elsewhere counts as done
  const allApplied = (sugs.length + oobApplicable.length) > 0
    && sugs.every(r => !!bidItem(r)) && oobApplicable.every(k => !!findQueuedBid(doQueue.items, k.keywordId));
  // Bulk unapply removes ONLY what this panel itself would queue — value-exact. A foreign-valued
  // item (another view, a MANUAL override) comes off via its own row's click, never in bulk.
  const ourBidItem = (r: Row) => {
    const it = bidItem(r);
    return it && it.action === ((r.suggestedBid ?? 0) >= (r.bid ?? 0) ? 'INCREASE_BID' : 'REDUCE_BID')
      && it.recommended_bid === r.suggestedBid ? it : undefined;
  };
  const ourBudgetItem = (c: Row) => {
    const it = budgetItem(c.campaignId);
    return it && it.action === 'BUDGET_CHANGE' && it.recommended_budget === budgetSug(c)?.suggested ? it : undefined;
  };
  const applyAll = () => {
    if (allApplied) {
      sugs.forEach(r => { const it = ourBidItem(r); if (it) doQueue.removeItem(it.id); });
      oobApplicable.forEach(k => { const it = ourOobItem(k); if (it) doQueue.removeItem(it.id); });
      // negates carry no value — every ad-group split item for the term is ours to remove
      visNegs.forEach(n => negItems(n).forEach(x => doQueue.removeItem(x.id)));
      budSugs.forEach(c => { const it = ourBudgetItem(c); if (it) doQueue.removeItem(it.id); });
      // Residual sweep (review 2026-08-16): match ONLY what THIS section proposed — the
      // (keyword_id, action, recommended value) triples built from its own rows. The old sweep
      // took EVERY bid/budget item in the section's campaigns ("campaign scope is safe" held
      // while sections were disjoint); TodayDecisions now queues into these same campaigns, so
      // a campaign-scoped sweep deleted the feed's items too. The v27.64 `foreign` exclusion is
      // subsumed: a foreign claim differs in action or value by construction, so it never
      // matches. Deliberate narrowing: a MANUAL override never falls to bulk unapply at all —
      // its value differs from the suggestion by construction, so only its own row's click
      // (which removes whatever is queued on the key) takes it.
      const proposed = new Set<string>([
        ...sugs.map(r => `${r.keywordId}|${(r.suggestedBid ?? 0) >= (r.bid ?? 0) ? 'INCREASE_BID' : 'REDUCE_BID'}|${r.suggestedBid}`),
        ...oobApplicable.map(k => `${k.keywordId}|${oobDir(k)}|${k.suggestedBid}`),
        ...budSugs.map(c => `${c.campaignId}|BUDGET_CHANGE|${budgetSug(c)?.suggested}`),
      ]);
      doQueue.items.filter(i => ['INCREASE_BID', 'REDUCE_BID', 'BUDGET_CHANGE'].includes(i.action) && campIds.has(i.campaign_id)
          && proposed.has(i.action === 'BUDGET_CHANGE'
            ? `${i.campaign_id}|BUDGET_CHANGE|${i.recommended_budget}`
            : `${i.keyword_id}|${i.action}|${i.recommended_bid}`))
        .forEach(i => doQueue.removeItem(i.id));
    } else {
      sugs.forEach(r => { if (!bidItem(r)) queueBid(r); });
      oobApplicable.forEach(k => { if (!findQueuedBid(doQueue.items, k.keywordId)) queueOobBid(k); });
      visNegs.forEach(n => { if (negItems(n).length === 0) queueNeg(n); });
      budSugs.forEach(c => { if (!budgetItem(c.campaignId)) queueBudget(c); });
    }
  };

  const queueBudget = (c: Row, manualBudget?: number) => {
    // SINGLE SOURCE (fix, Ori 2026-08-02 'budget without a v'): queue the SAME suggestion the
    // row displays — budgetSug (view-computed) — not the legacy launch-cube map, which lacks
    // most campaigns and made both apply-all and the budget button silently no-op.
    // Manual budgets (Ori 2026-08-04) bypass the suggestion gate — any campaign can take one.
    const newBudget = manualBudget ?? budgetSug(c)?.suggested;
    if (newBudget == null) return;
    const prev = budgetItem(c.campaignId);
    if (prev) doQueue.removeItem(prev.id);
    doQueue.addItem({
      search_term: `__budget__${c.campaignId}`, action: 'BUDGET_CHANGE', campaign: c.campaignName, campaign_id: c.campaignId,
      ad_group_id: '', targeting: '', keyword_id: '', match_type: '', target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0,
      current_bid: null, recommended_bid: null,
      campaign_type: c.channel === 'SB' ? 'SPONSORED_BRANDS' : 'SPONSORED_PRODUCTS', product: '',
      spend: 0, orders: 0, cpc: 0, conv_rate: 0, current_budget: c.budget, recommended_budget: newBudget,
      source: manualBudget != null ? 'MANUAL' : 'COACH',
    });
  };
  const commitManualBudget = (c: Row) => {
    const v = parseFloat(editBudget?.value ?? '');
    if (!isNaN(v) && v >= 1) queueBudget(c, Math.round(v * 100) / 100);  // Amazon budget floor $1
    setEditBudget(null);
  };
  // ALL split items for the term — SB negates queue one item per ad group, so display keys on
  // any of them and removal must take every one (the old single-item find left orphans behind).
  const negItems = (n: Neg) => findQueuedNegates(doQueue.items, n.campaignId, n.term);
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
        <button className="text-label flex items-center gap-1 flex-1 min-w-0" onClick={() => setOpenState(!open)}>
          <span className="text-faint">{open ? '▾' : '▸'}</span>
          <span className="font-medium text-sky-300">{tier === 'LOW' ? 'Low budget' : tier === 'SEASONAL' ? 'Seasonal' : tier === 'SEASONAL_LOW' ? 'Seasonal low budget' : tier === 'AUTO' ? 'Auto' : tier === 'AUTO_LOW' ? 'Auto low budget' : 'Portfolio 80/20'}</span>
          <span className="text-faint truncate">
            {failed ? '— unavailable' : rows
              ? `— ${camps.length} working campaigns · ${nParks} parks · ${nProbes} probes · ${nFound} winners found · ${visNegs.length} negates${deferIds.length > 0 ? ` · ${deferIds.length} OOB-owned` : ''}`
              : (open || fetchedRef.current) ? '— loading…' : '— expand to load'}
            {' '}· {auto ? 'goal: 4 fixed groups per campaign — negate bad terms, trim weak clauses, raise winners' : 'goal: 80% of spend on winners, 1–2 probes hunting the next one'}
          </span>
        </button>
        {rows && (sugs.length > 0 || oobApplicable.length > 0) && (
          <button onClick={applyAll}
            title={allApplied ? 'unapply this section’s suggestions — value-exact only; a row queued from another view at a different value comes off on its own row' : 'queue every suggestion not already queued — rows queued from any view count as done'}
            className={`text-label px-2 py-0.5 rounded border shrink-0 ${allApplied ? 'border-emerald-500/40 text-emerald-300' : 'border-sky-500/40 text-sky-300 hover:bg-sky-500/10'}`}>
            {allApplied ? `✓ applied ${nSug}` : `apply all ${nSug}`}
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
                {/* v27.21 (Ori 2026-08-06): the window strategies also need the LAST DAY — it is
                    the click gate. A seated keyword with 0 clicks yesterday is priced out of the
                    auction, so the 7d/8-28d windows it is judged on never refresh.
                    v27.63 (Ori 2026-08-13, "add prev day to table"): the AUTO/peak strategies get
                    it too. Their windows START at 3d, so yesterday was invisible in the one place
                    a 22-click, 0.00x day is the whole story. `fast` already leads with it. */}
                {!fast && (
                  <th className="font-normal px-2" title="last complete day — the CLICK GATE: a seated keyword with 0 clicks yesterday is priced out of the auction and gets nudged back up">last day</th>
                )}
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
                // v27.64: an OOB-owned auto campaign renders the OOB engine's live keyword rows
                // instead of a column of identical "capped Nd of 7" LIFT rows; the ownership note
                // moves to the campaign meta line (once — the reason is per-campaign). If the OOB
                // fetch failed or returned nothing, showOob stays false and the LIFT rows render
                // as before, reason string visible.
                const deferRow = auto ? kws.find(k => k.action === 'DEFER_OOB') : undefined;
                const oobRows = deferRow ? (oobByCamp.get(c.campaignId) ?? []) : [];
                const showOob = oobRows.length > 0;
                // display crop of the view's own sentence — the full reason stays in the title
                const capped = deferRow ? /capped \d+d of 7/.exec(deferRow.reason)?.[0] : undefined;
                // Ori 2026-08-17 ("open action → hierarchy Expanded"): a campaign holding at
                // least one still-open (not-yet-key-queued) suggestion starts expanded, one with
                // none starts collapsed. An explicit openCamps entry (a user click) is final and
                // wins over the derived default — which is why the toggle below must set
                // !expanded, not !o[id]: the map may hold no entry while the default shows open.
                const hasOpenSug = sugs.some(r => r.campaignId === c.campaignId && !bidItem(r))
                  || (showOob && oobRows.some(k => oobActionable(k) && !findQueuedBid(doQueue.items, k.keywordId)))
                  || visNegs.some(n => n.campaignId === c.campaignId && negItems(n).length === 0)
                  || (!!budgetSug(c) && !budgetItem(c.campaignId));
                const expanded = openCamps[c.campaignId] ?? hasOpenSug;
                const bIt = budgetItem(c.campaignId);
                const bAt = atValue(bIt?.recommended_budget, budgetSug(c)?.suggested);
                return (
                <Fragment key={c.campaignId}>
                <tr className="text-right border-t border-border/40">
                  <td className="text-left px-2 py-0.5 text-body whitespace-nowrap">
                    <button className="text-faint pr-1" onClick={() => setOpenCamps(o => ({ ...o, [c.campaignId]: !expanded }))}>{expanded ? '▾' : '▸'}</button>
                    {c.campaignName}
                    <span className="text-faint text-label"> {c.channel}{c.isResearch && <span className="text-violet-400"> · research</span>} · {c.slots} seats · spent ${c.spendW.toFixed(2)}/{fast ? 3 : c.wDays}d · {c.activeProbes} probing · losers {c.loserShare != null ? `${c.loserShare.toFixed(0)}%` : '—'}{showOob && <span className="text-amber-400" title={deferRow?.reason}> · OOB owns the bids{capped ? ` (${capped})` : ''}</span>}</span>
                  </td>
                  <td className={`px-2 ${c.pctDark > 10 ? 'text-amber-400' : 'text-faint'}`}>{c.pctDark.toFixed(0)}%</td>
                  <td className="px-2 text-muted whitespace-nowrap">${c.budget.toFixed(0)} <span className="text-faint">bud</span> <span className="text-faint" title="spent yesterday">· ${c.campSpend1d.toFixed(2)}</span></td>
                  {/* v27.21: campaign-level last day, so the added keyword column stays aligned */}
                  {!fast && (
                    <td className="px-2 text-muted whitespace-nowrap">{c.campClicks1d}c{c.campRoas1d != null ? ` ${c.campRoas1d.toFixed(2)}×` : ' —'}</td>
                  )}
                  <td className="px-2 text-muted whitespace-nowrap">{autoPeak ? <>{c.campClicks3d}c{c.campRoas3d != null ? ` ${c.campRoas3d.toFixed(2)}×` : ' —'}</> : fast ? <>{c.campClicks1d}c{c.campRoas1d != null ? ` ${c.campRoas1d.toFixed(2)}×` : ' —'}</> : <>{c.campClicks7d}c{c.campRoas7d != null ? ` ${c.campRoas7d.toFixed(2)}×` : ' —'}</>}</td>
                  <td className="px-2 text-muted whitespace-nowrap">{autoPeak ? <>{c.campClicks414}c{c.campRoas414 != null ? ` ${c.campRoas414.toFixed(2)}×` : ' —'}</> : fast ? <>{c.campClicksPrev2}c{c.campRoasPrev2 != null ? ` ${c.campRoasPrev2.toFixed(2)}×` : ' —'}</> : <>{c.campClicks828}c{c.campRoas828 != null ? ` ${c.campRoas828.toFixed(2)}×` : ' —'}</>}</td>
                  <td className="px-2" />
                  <td className="px-2" />
                  <td className={`px-2 text-left whitespace-nowrap ${budgetSug(c) ? 'text-emerald-400' : 'text-muted'}`}>{budgetSug(c) ? 'budget' : 'hold'}</td>
                  <td className="px-2">
                    {editBudget?.key === c.campaignId ? (
                      <input autoFocus type="number" step="1" min="1" value={editBudget.value}
                        onChange={e => setEditBudget({ key: c.campaignId, value: e.target.value })}
                        onKeyDown={e => { if (e.key === 'Enter') commitManualBudget(c); if (e.key === 'Escape') setEditBudget(null); }}
                        onBlur={() => setEditBudget(null)}
                        className="w-16 px-1 py-0 text-right font-mono bg-surface border border-blue-500/50 rounded" />
                    ) : (
                      <button title="click to set a budget manually (Enter queues it)"
                        onClick={() => setEditBudget({ key: c.campaignId, value: Number(budgetItem(c.campaignId)?.recommended_budget ?? budgetSug(c)?.suggested ?? c.budget).toFixed(2) })}
                        className="hover:text-blue-300">
                        {budgetItem(c.campaignId)?.source === 'MANUAL' ? `$${budgetItem(c.campaignId)!.recommended_budget?.toFixed(2)} ✎` : budgetSug(c) ? `$${budgetSug(c)!.suggested!.toFixed(2)}` : '—'}
                      </button>
                    )}
                  </td>
                  <td className="px-2">
                    {(budgetSug(c) || bIt) && (
                      <button onClick={() => { const it = budgetItem(c.campaignId); if (it) doQueue.removeItem(it.id); else queueBudget(c); }}
                        title={bIt ? queuedTitle(bAt) : 'queue this budget'}
                        className={`px-1.5 py-0 rounded border ${bIt ? 'border-emerald-500/40 text-emerald-300' : 'border-border text-muted hover:bg-surface'}`}>
                        {bIt ? `✓${bAt}` : 'budget'}
                      </button>
                    )}
                  </td>
                  <td className="px-2 text-left text-faint whitespace-nowrap">{budgetSug(c)?.reason || c.vBudgetReason || budMap.get(c.campaignId)?.reason || (c.pctDark > 10 ? `dark ${c.pctDark.toFixed(0)}% · mixed windows — the bid brakes carry it today` : (c.loserShare ?? 0) > 20 ? 'losers over the 20% budget — parking the worst' : 'split healthy')}</td>
                </tr>
                {expanded && !showOob && kws.map(k => {
                  const it = bidItem(k);
                  const kAt = atValue(it?.recommended_bid, k.suggestedBid);
                  const kWins = winTerms.filter(w => w.campaignId === c.campaignId && w.targetText === k.text);
                  const wKey = `${c.campaignId}|${k.text}`;
                  const wOpen = !!openWinners[wKey];
                  return (
                  <Fragment key={`${c.campaignId}|${k.keywordId || k.text}`}>
                  <tr className="text-right border-t border-border/20 bg-surface/40">
                    <td className="text-left pl-8 pr-2 py-0.5 text-muted whitespace-nowrap">{k.text}
                      <span className="text-faint"> ({k.isAuto ? 'auto' : k.isPt ? 'PT' : (k.matchType || '').toLowerCase()}){tier === 'AUTO_LOW' ? null : <> · <span className={CLASS_CLS[k.kwClass] ?? ''}>{k.kwClass.toLowerCase()}</span></>}{k.isAuto ? null : k.seatRank <= k.slots ? <span className="text-sky-300"> · seat {k.seatRank}/{k.slots}</span> : <span className="text-faint"> · queue #{k.seatRank - k.slots}</span>}{k.seasonalNow && <span className="text-sky-400"> · seasonal</span>} · spent ${k.kwSpendW.toFixed(2)}</span>
                      {kWins.length > 0 && (
                        <button onClick={() => setOpenWinners(o => ({ ...o, [wKey]: !o[wKey] }))}
                          className="text-emerald-400 pl-1" title="winning search terms (>= 1.1x net ROAS over 90d) — click to expand">
                          {wOpen ? '▾' : '▸'} {kWins.length} winner{kWins.length > 1 ? 's' : ''}
                        </button>
                      )}</td>
                    <td className="px-2" />
                    <td className="px-2 text-muted whitespace-nowrap">{k.bid != null ? <>${k.bid.toFixed(2)} <span className="text-faint">bid</span></> : '—'}<span className="text-faint" title="spent yesterday"> · ${k.spend1d.toFixed(2)}</span></td>
                    {/* v27.21: last-day click gate — 0 clicks on a seated keyword is the signal
                        the bid is priced out, so flag it amber rather than let it read as a quiet day. */}
                    {!fast && (
                      <td className={`px-2 whitespace-nowrap ${k.clicks1d === 0 && k.seatRank <= k.slots ? 'text-amber-400' : 'text-muted'}`}
                          title={k.clicks1d === 0 ? 'no clicks yesterday — priced out of the auction' : undefined}>
                        {k.clicks1d}c{k.roas1d != null ? ` ${k.roas1d.toFixed(2)}×` : ' —'}
                      </td>
                    )}
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
                          title={it ? queuedTitle(kAt) : 'queue this bid'}
                          className={`px-1.5 py-0 rounded border ${it ? 'border-emerald-500/40 text-emerald-300' : 'border-border text-muted hover:bg-surface'}`}>
                          {it ? `✓${kAt}` : 'bid'}
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
                {/* v27.64: the OOB engine's live rows for a deferring campaign. COLUMN HONESTY —
                    OobKeyword carries 1d + prev-2d windows only, so: 1d goes under "last day";
                    the wider window columns (3d & 4–14d in peak, 7d & 8–28d off-season) show "—"
                    with the prev-2d record in their tooltip, never a number under a header that
                    claims a window nobody measured. AUTO_LOW ('fast') headers are already
                    last day / prev-2d and map directly. The → $ cell is the queue toggle
                    (RevivalsPhase idiom). */}
                {expanded && showOob && oobRows.map(k => {
                  const qIt = findQueuedBid(doQueue.items, k.keywordId);
                  const qAt = atValue(qIt?.recommended_bid, k.suggestedBid);
                  const dashTitle = `no read for this window — the OOB engine judges on last day + prev-2d · prev-2d: ${k.clicksPrev2}c${k.roasPrev2 != null ? ` ${k.roasPrev2.toFixed(2)}×` : ' —'}`;
                  return (
                  <tr key={`${c.campaignId}|oob|${k.keywordId || k.text}`} className="text-right border-t border-border/20 bg-surface/40">
                    <td className="text-left pl-8 pr-2 py-0.5 text-muted whitespace-nowrap">{k.text}
                      <span className="text-faint"> ({k.isAuto ? 'auto' : k.isPt ? 'PT' : (k.matchType || '').toLowerCase()}){k.isAuto ? null : k.seatRank <= k.slots ? <span className="text-sky-300"> · seat {k.seatRank}/{k.slots}</span> : <span className="text-faint"> · queue #{k.seatRank - k.slots}</span>} · spent ${k.spend1d.toFixed(2)}</span>
                    </td>
                    <td className="px-2" />
                    <td className="px-2 text-muted whitespace-nowrap">{k.bid != null ? <>${k.bid.toFixed(2)} <span className="text-faint">bid</span></> : '—'}<span className="text-faint" title="spent yesterday"> · ${k.spend1d.toFixed(2)}</span></td>
                    {!fast && (
                      <td className="px-2 text-muted whitespace-nowrap" title="last complete day — clicks + net ROAS; the OOB engine's primary window">{k.clicks1d}c{k.roas1d != null ? ` ${k.roas1d.toFixed(2)}×` : ' —'}</td>
                    )}
                    {fast ? (<>
                      <td className="px-2 text-muted whitespace-nowrap">{k.clicks1d}c{k.roas1d != null ? ` ${k.roas1d.toFixed(2)}×` : ' —'}</td>
                      <td className="px-2 text-muted whitespace-nowrap">{k.clicksPrev2}c{k.roasPrev2 != null ? ` ${k.roasPrev2.toFixed(2)}×` : ' —'}</td>
                    </>) : (<>
                      <td className="px-2 text-faint" title={dashTitle}>—</td>
                      <td className="px-2 text-faint" title={dashTitle}>—</td>
                    </>)}
                    <td className="px-2 text-faint">{k.targetCpc != null ? `$${k.targetCpc.toFixed(2)}` : '—'}</td>
                    <td className={`px-2 text-left whitespace-nowrap ${OOB_ROLE_CLS[k.role] ?? 'text-faint'}`} title={OOB_ROLE_TIP[k.role] ?? ''}>{k.role.toLowerCase()}</td>
                    <td className={`px-2 text-left whitespace-nowrap ${OOB_ACT_CLS[k.bidAction] ?? 'text-muted'}`}>
                      {k.bidAction.toLowerCase().replace(/_/g, ' ')}
                    </td>
                    <td className="px-2">
                      {qIt || oobActionable(k) ? (
                        <button onClick={() => { const it = findQueuedBid(doQueue.items, k.keywordId); if (it) doQueue.removeItem(it.id); else queueOobBid(k); }}
                          title={qIt ? queuedTitle(qAt) : 'queue this OOB bid'}
                          className={qIt ? 'text-emerald-300' : 'hover:text-blue-300'}>
                          {qIt ? `${k.suggestedBid != null ? `$${k.suggestedBid.toFixed(2)} ` : ''}✓${qAt}` : `$${k.suggestedBid!.toFixed(2)}`}
                        </button>
                      ) : (
                        <span className="text-faint">{k.suggestedBid != null ? `$${k.suggestedBid.toFixed(2)}` : '—'}</span>
                      )}
                    </td>
                    <td className="px-2" />
                    <td className="px-2 text-left text-faint whitespace-nowrap">{k.bidReason}</td>
                  </tr>
                ); })}
                {expanded && visNegs.filter(n => n.campaignId === c.campaignId).map(n => {
                  const queued = negItems(n).length > 0;
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
                      {/* removal takes EVERY split item — SB queues one per ad group, and a term
                          queued from any other surface unqueues here all the same */}
                      <button onClick={() => { const xs = negItems(n); if (xs.length > 0) xs.forEach(x => doQueue.removeItem(x.id)); else queueNeg(n); }}
                        className={`px-1.5 py-0 rounded border ${queued ? 'border-emerald-500/40 text-emerald-300' : 'border-border text-muted hover:bg-surface'}`}>
                        {queued ? '✓' : 'neg'}
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
