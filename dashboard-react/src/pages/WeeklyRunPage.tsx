import { useCallback, useEffect, useMemo, useState } from 'react';
import { cubeLoad } from '../hooks/useCubeData';
import { BudgetStep1, ALL_FAMILIES, ALL_STRATEGIES } from './BudgetStep1';
import { ALL_AGES } from './BudgetByAge';
import { CoachFlowchart } from './CoachFlowchart';
import { NewCampaignCards } from './NewCampaignCards';
import { OobBudgetPhase } from './OobBudgetPhase';

// Sections 2 (per-campaign budget table) & 3 (plan) were removed 2026-07-18 — budget now lives inside
// each campaign card in section 4. Flip to true to bring the old sections back.
const SHOW_STEP_2_3 = false;
import { RoleBudgetPanel } from './RoleBudgetPanel';
import { WeeklyBudgetCampaigns } from './WeeklyBudgetCampaigns';
import { useDoQueue } from '../hooks/useDoQueue';
import { useRecentApplied } from '../hooks/useRecentApplied';
import { CampaignManageModal, type ManageCampaign } from '../components/CampaignManageModal';
import { dataEntry, type WeeklyRunRow } from '../utils/dataEntry';
import type { FamilyName, PageId } from '../types';
import { fM } from '../utils';

// Weekly Run — guided, product-by-product weekly operating loop (Coacher D/F surface).
// Rail: every product (families + Store + Unknown) so all ad campaigns are covered. Top: 1 Total budget
// (global waterfall). Main (per product): 2 Budget (per-campaign allocation, edit + queue), 3 Plan
// (review & approve), 4 Actions (keyword bids + negatives), 5 Upload, 6 Done. Editing a campaign in
// step 2 bubbles its total up so the Total-budget grand total re-sums. All decision logic is backend
// (V_WEEKLY_RUN_* / V_BUDGET_STEP1_*); this is presentation.

const CORE_FAMILIES = ['Lollibox', 'LolliME', 'Bottle', 'Fresh'];
const fmtDay = (ds: string) => {
  const [y, m, d] = (ds || '').slice(0, 10).split('-').map(Number);
  return (y && m && d) ? new Date(y, m - 1, d).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) : ds || '';
};
const weekRange = (ds: string) => {
  const [y, m, d] = (ds || '').slice(0, 10).split('-').map(Number);
  if (!y || !m || !d) return '';
  const end = new Date(y, m - 1, d + 6);
  return `${fmtDay(ds)} – ${end.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}`;
};
// the 7-day window ENDING on the anchor (last complete day), for the mature 7-day measures
const last7Range = (ds: string) => {
  const [y, m, d] = (ds || '').slice(0, 10).split('-').map(Number);
  if (!y || !m || !d) return '';
  const start = new Date(y, m - 1, d - 6);
  return `${start.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })} – ${fmtDay(ds)}`;
};
const chip = (s: string | undefined) =>
  s === 'DONE' ? { label: '✓✓ Done', cls: 'text-emerald-400' }
  : s === 'APPROVED' ? { label: '✓ Approved', cls: 'text-blue-400' }
  : s === 'PENDING' ? { label: '○ Pending', cls: 'text-muted' }
  : { label: '— no plan', cls: 'text-faint' };
const npCls = (n: number | null) => n == null ? 'text-faint' : n > 0 ? 'text-emerald-400' : n < 0 ? 'text-red-400' : 'text-muted';
const num = (v: unknown): number | null => v == null ? null : Number(v);
const perDay = (v: number | null) => v == null ? null : v / 7;
const roasCls = (r: number | null) => r == null ? 'text-faint' : r >= 1.1 ? 'text-emerald-400' : r >= 1.0 ? 'text-amber-400' : 'text-red-400';
const RoasCell = ({ v }: { v: number | null }) => <span className={roasCls(v)}>{v != null ? `${v.toFixed(2)}×` : '—'}</span>;

type Bench = {
  lastPeakNet: number | null; lastPeakBiz: number | null; lastPeakSpend: number | null; lastPeakWeek: string;
  lastOffNet: number | null; lastOffBiz: number | null; lastOffSpend: number | null; lastOffWeek: string;
};
type PlanCell = { matchType: string; intentClass: string; campaignType: string; adFormat: string; purpose: string; strategyRole: string; plannedSpend: number; expNet: number | null; targetCpc: number | null; actualCpc: number | null; lastNet: number | null; lastSpend: number | null; lastUnits: number | null; lastCpc: number | null; units8w: number | null; avgNetOff: number | null; avgNetPeak: number | null };
// Compact ad-format label for the plan grid: SP → "SP"; SB video/collection → "SB·video"/"SB·collection".
const planFormatLabel = (ct: string, af: string): string =>
  !ct || ct === 'ALL' ? '' : af === 'BRAND_VIDEO' ? 'SB·video' : af === 'PRODUCT_COLLECTION' ? 'SB·collection' : ct;
const PURPOSE_ORDER: Record<string, number> = { SCALE: 0, DEFEND: 1, MAP: 2, PROBE: 3, CUT: 4, HOLD: 5 };
// Plain-language meaning of each plan "do" (cell purpose), shown as a tooltip on the do column.
const PURPOSE_TOOLTIP: Record<string, string> = {
  SCALE:  'profitable — grow it: give the winner more budget/bid to win more',
  DEFEND: "brand/defensive term — hold it so competitors can't take the space (kept even at thin margins)",
  CUT:    'losing money — trim or stop the spend here',
  PROBE:  'too little data — test at a set CPC to learn before committing budget',
  MAP:    'discovery — find which terms convert before funding them',
  HOLD:   'steady, within range — keep as-is, no change needed',
};
type ProductRow = { product: string; campaigns: number; recentDailySpend: number | null; adsNetDay: number | null; adsNetRoas: number | null; netProfitDay: number | null; currentDailyBudget: number | null; suggestedDailyBudget: number | null };
type CampRow = { id: string; product: string; campaignName: string; campaignType: string; recentDailySpend: number | null; adsNet60d: number | null; adsNetRoas60d: number | null; roas1w: number | null; roasPrev1w: number | null; roas4w: number | null; effRoas: number | null; isNewCampaign: boolean; coachMode: string; strategyType: string; strategyRole: string; strategyCategory: string; ageBucket: string; budgetAction: string; currentBudget: number | null; recommendedBudget: number | null; utilPct: number | null; daysSinceSuggestion: number | null; needsStrategy: boolean; currentStrategyId: string; suggestedFamily: string; suggestedStrategy: string; noCoachDecision: boolean };
type KwRow = { id: string; campaignId: string; campaignType: string; adGroupId: string; targeting: string; matchType: string; action: string; currentBid: number | null; newBid: number | null; pct: number | null; reason: string; isAction: boolean; priority: number; daysSinceChange: number | null; daysSinceSuggestion: number | null; targetCpc: number | null;
  w1ClkDay: number | null; w1Cpc: number | null; w1Roas: number | null; w1Units: number | null; w4ClkDay: number | null; w4Cpc: number | null; w4Roas: number | null; w4Units: number | null; pkClkDay: number | null; pkCpc: number | null; pkRoas: number | null; pkUnits: number | null };
type NegRow = { id: string; keywordId: string; campaignId: string; campaignName: string; adGroupId: string; targeting: string; searchTerm: string; reason: string; peakClicks: number | null; peakOrders: number | null; peakNet: number | null; peakConverts: boolean; heroAsin: string; heroProductName: string; heroCvr: number | null; wrongAsin: boolean };

// Plain-language explanation for a keyword row
function kwReason(k: KwRow): string {
  if (k.reason) return k.reason;
  const dir = kwDir(k);
  if (dir.label === 'raise') return 'profitable & has headroom → raise bid';
  if (dir.label === 'lower') return 'spend ahead of return → lower bid';
  if (k.action === 'PROBE') return 'too little data → probe at a set CPC';
  return 'performing within range → hold bid';
}
// Direction follows the ACTUAL bid change (current → recommended), not the engine's action label —
// the engine sometimes labels INCREASE_BID while recommending a lower bid; the bid number is what ships.
const kwDir = (k: KwRow) => {
  if (!k.isAction || k.newBid == null) return { label: 'hold', cls: 'text-faint' };
  if (k.currentBid != null) {
    if (k.newBid > k.currentBid + 0.001) return { label: 'raise', cls: 'text-emerald-400' };
    if (k.newBid < k.currentBid - 0.001) return { label: 'lower', cls: 'text-red-400' };
    return { label: 'hold', cls: 'text-faint' };
  }
  return k.action === 'PROBE' ? { label: 'probe', cls: 'text-amber-400' } : { label: 'set', cls: 'text-muted' };
};
// Keyword-action directions used by the step-3 action filter (default = all except HOLD).
const KW_DIRECTIONS = ['raise', 'lower', 'probe', 'set', 'hold'] as const;

// Days indicator for a keyword/campaign row. If WE uploaded a change for it within the 3-day cooldown
// (sug = days_since_suggestion, from the change-log), show a green "✓ applied" badge so an already-done
// item is visually distinct from a pending action. Otherwise show the days-since counter, preferring the
// change-log over the lagging SCD2 bid-change date (so a keyword changed today reads 0d, not 90d).
function AppliedDays({ sug, chg }: { sug: number | null; chg: number | null }) {
  if (sug != null && sug < 3)
    return <span className="font-mono shrink-0 text-emerald-400" title="you uploaded a change for this recently — it's in the 3-day cooldown (already done, not a pending action)">✓ applied {sug === 0 ? 'today' : `${sug}d ago`}</span>;
  const days = sug ?? chg;
  return days != null ? <span className="text-faint font-mono shrink-0" title="days since we last changed this (from the change-log)">{days}d</span> : null;
}

// Plain-language summary of what each coach mode does, shown above the campaigns.
const MODE_RULES: Record<string, { label: string; rules: string[] }> = {
  GUARDIAN: { label: 'Guardian — protect profit', rules: [
    'Budget — engine net ROAS: cut if < 0.9 (losing; needs ≥ $25 spend/8w); raise if ≥ 1.1 AND using ≥90% of budget (last 7 days). At most one budget change per 3 days.',
    'Bids — know it, then act: a keyword needs ≥ 15 clicks in 12 months to be judged (proven seasonal keywords are held for their season, never "no data"). the last 7 days set the direction, the last 28 days confirm — moderate signals need both to agree; extreme weeks act alone. A proven 28-day winner (≥ 1.5×) is never cut on one weak week, and a cut is deferred while the last 3 days are improving. Winners step up to the CPC band (step-1 target). Sweet spot: a keyword still returning ≥ 2× net ROAS at its band is bid past it toward the $2 cap; one that slips below 1.5× is eased back to the band — the aim is a 1.5–2× equilibrium. One bid change per keyword per 7 days.',
    'Negate — a search term with 0 orders on ≥ 15 clicks (8w), still clicking in the last 5 days → negative exact. Peak converters get a ⚠ (seasonal — consider keeping); wrong-colour terms offer “+ hero” (advertise the right variant) instead of blocking.',
    'New campaigns (≤ 20 days) — separate launch controller: last-day + prior-2-day net ROAS drive bids & budget (not the 7/28d engine). Raise when out-of-budget & profitable, cut only when both windows are bad, negate a term at 15 clicks / 0 orders.',
  ] },
  BLITZ: { label: 'Blitz — peak push', rules: [
    'Budget — 8-week ROAS: +20% on profitable (≥ 1.1) maxed campaigns; still cut losers < 0.9. Faster cadence (peak: daily).',
    'Bids — toward the (higher) PEAK CPC band: raise winners aggressively up to the peak band; protect top-of-search. Peak-weighted ROAS picks the winners.',
    'Negate — 8 weeks: same loser rule (0 orders on ≥ 15 clicks, last-5-day recency).',
  ] },
  COOLDOWN: { label: 'Cooldown — ease back after peak', rules: [
    'Budget — post-peak window: restore toward pre-peak; reductions only, no raises.',
    'Bids / terms: reductions only, no new negatives.',
  ] },
};
// Hierarchy-0 strategic buckets.
const STRATEGY_META: Record<string, { label: string; cls: string; border: string; desc: string }> = {
  SCALE:  { label: 'SCALE',  cls: 'text-emerald-400', border: 'border-emerald-500/30', desc: 'profitable & budget-capped — give it more room' },
  MARGIN: { label: 'MARGIN', cls: 'text-blue-400',    border: 'border-blue-500/30',    desc: 'profitable & steady — hold, protect the margin' },
  CUT:    { label: 'CUT',    cls: 'text-red-400',     border: 'border-red-500/30',     desc: 'losing money — trim spend' },
};
const STRATEGY_ORDER: Record<string, number> = { SCALE: 0, MARGIN: 1, CUT: 2 };

export function WeeklyRunPage({ onNav }: { onNav: (page: PageId, family?: FamilyName) => void }) {
  const [products, setProducts] = useState<ProductRow[] | null>(null);
  const [runByName, setRunByName] = useState<Record<string, WeeklyRunRow>>({});
  const [week, setWeek] = useState('');
  const [sel, setSel] = useState<string | null>(null);
  // Strategy (Coverage role) filter — independent of the family pick; the two intersect.
  const [selStrategy, setSelStrategy] = useState<string>(ALL_STRATEGIES);
  const [selAge, setSelAge] = useState<string>(ALL_AGES);
  const [anchor, setAnchor] = useState<string>('');   // the "last complete day" the data is anchored on
  const [loading, setLoading] = useState(true);

  // pull the actual anchor date the launch data uses, so the window labels are unambiguous
  useEffect(() => {
    let alive = true;
    cubeLoad({ dimensions: ['RunTarget.anchorDate'], limit: 1 })
      .then(rows => { if (alive) { const d = (rows as Record<string, unknown>[])[0]?.['RunTarget.anchorDate']; if (d) setAnchor(String(d).slice(0, 10)); } })
      .catch(() => {});
    return () => { alive = false; };
  }, []);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState('');
  const [bench, setBench] = useState<Bench | null>(null);
  const [planCells, setPlanCells] = useState<PlanCell[] | null>(null);
  const [famBudget, setFamBudget] = useState<number | null>(null);   // selected family's waterfall daily budget (Step-1, cube fallback)
  const [liveAllocs, setLiveAllocs] = useState<Record<string, number>>({});   // live OFFENSE family allocations from the Total-budget panel (updates with the dial)
  const [defenseAllocs, setDefenseAllocs] = useState<Record<string, number>>({});  // live DEFENSE family allocations from the defense panel
  const [familyEdits, setFamilyEdits] = useState<Record<string, number>>({});  // each family's edited campaign total (Step-2) → bubbles up to the grand total
  // PPC mode: OFFENSE (grow, default) vs DEFENSE (hold the line) — two independent budget pools, same layout.
  type PpcMode = 'offense' | 'brand_defense' | 'product_defense';
  // Pools unified — always the offense-style view; the strategy filter reaches every pool.
  const [ppcMode] = useState<PpcMode>('offense');
  const [camps, setCamps] = useState<CampRow[] | null>(null);
  const [kws, setKws] = useState<KwRow[] | null>(null);
  const [negs, setNegs] = useState<NegRow[] | null>(null);
  const [kwBidDraft, setKwBidDraft] = useState<Record<string, number>>({});
  const [openCamp, setOpenCamp] = useState<Record<string, boolean>>({});
  // Step-3 filter: hide what's already uploaded (in the 3-day cooldown) so "what's left to do" is
  // front-and-centre. Default 'todo' (not applied). 'done' = only the recently-applied; 'all' = both.
  const [actionFilter, setActionFilter] = useState<'todo' | 'done' | 'all'>('todo');
  // Step-3 action filter: single-select direction to focus. null = default (all actionable; HOLD hidden).
  const [dirFilter, setDirFilter] = useState<string | null>(null);
  const [manageCamp, setManageCamp] = useState<ManageCampaign | null>(null);
  const doQueue = useDoQueue();
  const { effectiveDaysSince } = useRecentApplied();  // live 'already applied' from the change-log
  // Launch-card target counts, reported up by NewCampaignCards so the applied chips are PAGE-WIDE.
  const [launchCts, setLaunchCts] = useState({ all: 0, done: 0 });
  const reportLaunchCounts = useCallback(
    (all: number, done: number) => setLaunchCts(p => (p.all === all && p.done === done ? p : { all, done })),
    [],
  );
  // Stable callback so the child effect doesn't re-fire every render. Records each family's live
  // campaign total; the Total-budget panel re-sums the grand total across families from this map.
  const handleFamilyTotal = useCallback((fam: string, t: number) => {
    setFamilyEdits(p => Math.abs((p[fam] ?? -1) - t) < 0.005 ? p : { ...p, [fam]: t });
  }, []);

  const load = useCallback(async () => {
    try {
      const [prodRaw, run] = await Promise.all([
        cubeLoad({ dimensions: ['CoachRunProduct.product', 'CoachRunProduct.campaigns', 'CoachRunProduct.recentDailySpend',
          'CoachRunProduct.adsNetDay', 'CoachRunProduct.adsNetRoas', 'CoachRunProduct.netProfitDay',
          'CoachRunProduct.currentDailyBudget', 'CoachRunProduct.suggestedDailyBudget'] }),
        dataEntry.getWeeklyRun().catch(() => [] as WeeklyRunRow[]),
      ]);
      const prods: ProductRow[] = (prodRaw as Record<string, unknown>[]).map(r => ({
        product: String(r['CoachRunProduct.product'] ?? ''),
        campaigns: Number(r['CoachRunProduct.campaigns'] ?? 0),
        recentDailySpend: num(r['CoachRunProduct.recentDailySpend']),
        adsNetDay: num(r['CoachRunProduct.adsNetDay']),
        adsNetRoas: num(r['CoachRunProduct.adsNetRoas']),
        netProfitDay: num(r['CoachRunProduct.netProfitDay']),
        currentDailyBudget: num(r['CoachRunProduct.currentDailyBudget']),
        suggestedDailyBudget: num(r['CoachRunProduct.suggestedDailyBudget']),
      })).sort((a, b) => (b.recentDailySpend ?? 0) - (a.recentDailySpend ?? 0));
      const byName: Record<string, WeeklyRunRow> = {};
      run.forEach(r => { byName[r.parent_name] = r; });
      setProducts(prods); setRunByName(byName); setWeek(run[0]?.week_start ?? '');
      setSel(s => s ?? ALL_FAMILIES); setErr(null);   // default: the whole week's campaigns, not one family
    } catch (e) { setErr(String(e)); }
    finally { setLoading(false); }
  }, []);
  useEffect(() => { void load(); }, [load]);

  // "All" (the default) works every product's campaigns at once — its header row sums the rail.
  const isAll = sel === ALL_FAMILIES;
  const allProduct: ProductRow | null = useMemo(() => {
    if (!isAll || !products?.length) return null;
    const sum = (pick: (p: ProductRow) => number | null) => products.reduce((s, p) => s + (pick(p) ?? 0), 0);
    const spend = sum(p => p.recentDailySpend);
    return {
      product: ALL_FAMILIES, campaigns: sum(p => p.campaigns), recentDailySpend: spend,
      adsNetDay: sum(p => p.adsNetDay), netProfitDay: sum(p => p.netProfitDay),
      // ROAS must be re-derived from the summed pieces — averaging per-product ROAS would weight a $2/day
      // product the same as a $300/day one.
      adsNetRoas: spend > 0 ? (sum(p => p.adsNetDay) + spend) / spend : null,
      currentDailyBudget: sum(p => p.currentDailyBudget), suggestedDailyBudget: sum(p => p.suggestedDailyBudget),
    };
  }, [isAll, products]);
  const current = isAll ? allProduct : (products?.find(p => p.product === sel) ?? null);
  const currentRun: WeeklyRunRow | undefined = sel && !isAll ? runByName[sel] : undefined;
  const isFamily = !!currentRun;

  // Per-product detail loads (plan/benchmark only for families; campaigns/keywords for all)
  useEffect(() => {
    let alive = true;
    setBench(null); setPlanCells(null); setCamps(null); setKws(null); setNegs(null); setNote('');
    if (!sel) return;
    // "All" has no single parent_name to filter on — omit the filter entirely and load every row.
    // ALL_FAMILIES is a sentinel, never a real parent_name, so it must not reach a cube filter.
    const selAll = sel === ALL_FAMILIES;
    const byProduct = (member: string) => selAll ? [] : [{ member, operator: 'equals' as const, values: [sel] }];
    const family = !selAll && runByName[sel] ? sel : null;
    if (family) {
      (async () => {
        try {
          const b = await cubeLoad({
            dimensions: ['CoachWeeklyBenchmark.lastPeakNet', 'CoachWeeklyBenchmark.lastPeakBizNet', 'CoachWeeklyBenchmark.lastPeakSpend', 'CoachWeeklyBenchmark.lastPeakWeek',
              'CoachWeeklyBenchmark.lastOffNet', 'CoachWeeklyBenchmark.lastOffBizNet', 'CoachWeeklyBenchmark.lastOffSpend', 'CoachWeeklyBenchmark.lastOffWeek'],
            filters: [{ member: 'CoachWeeklyBenchmark.parentName', operator: 'equals', values: [family] }],
          });
          if (!alive) return;
          const r = (b as Record<string, unknown>[])[0] || {};
          setBench({
            lastPeakNet: num(r['CoachWeeklyBenchmark.lastPeakNet']), lastPeakBiz: num(r['CoachWeeklyBenchmark.lastPeakBizNet']),
            lastPeakSpend: num(r['CoachWeeklyBenchmark.lastPeakSpend']), lastPeakWeek: String(r['CoachWeeklyBenchmark.lastPeakWeek'] ?? ''),
            lastOffNet: num(r['CoachWeeklyBenchmark.lastOffNet']), lastOffBiz: num(r['CoachWeeklyBenchmark.lastOffBizNet']),
            lastOffSpend: num(r['CoachWeeklyBenchmark.lastOffSpend']), lastOffWeek: String(r['CoachWeeklyBenchmark.lastOffWeek'] ?? ''),
          });
        } catch { /* benchmark optional */ }
      })();
      (async () => {
        try {
          const rows = await cubeLoad({
            dimensions: ['CoachWeeklyPlan.matchType', 'CoachWeeklyPlan.intentClass', 'CoachWeeklyPlan.campaignType', 'CoachWeeklyPlan.adFormat', 'CoachWeeklyPlan.purpose', 'CoachWeeklyPlan.strategyRole',
              'CoachWeeklyPlan.plannedSpendDim', 'CoachWeeklyPlan.expectedValue', 'CoachWeeklyPlan.targetCpc', 'CoachWeeklyPlan.actualCpc',
              'CoachWeeklyPlan.lastNet', 'CoachWeeklyPlan.lastSpend', 'CoachWeeklyPlan.lastUnits', 'CoachWeeklyPlan.lastCpc', 'CoachWeeklyPlan.units8w',
              'CoachWeeklyPlan.avgNetDayOff', 'CoachWeeklyPlan.avgNetDayPeak'],
            filters: [
              { member: 'CoachWeeklyPlan.parentName', operator: 'equals', values: [family] },
              { member: 'CoachWeeklyPlan.horizon', operator: 'equals', values: ['CURRENT'] },
            ],
          });
          if (!alive) return;
          setPlanCells((rows as Record<string, unknown>[]).map(r => ({
            matchType: String(r['CoachWeeklyPlan.matchType'] ?? ''), intentClass: String(r['CoachWeeklyPlan.intentClass'] ?? ''),
            campaignType: String(r['CoachWeeklyPlan.campaignType'] ?? ''), adFormat: String(r['CoachWeeklyPlan.adFormat'] ?? ''),
            purpose: String(r['CoachWeeklyPlan.purpose'] ?? ''), strategyRole: String(r['CoachWeeklyPlan.strategyRole'] ?? 'OTHER'),
            plannedSpend: Number(r['CoachWeeklyPlan.plannedSpendDim'] ?? 0),
            expNet: num(r['CoachWeeklyPlan.expectedValue']), targetCpc: num(r['CoachWeeklyPlan.targetCpc']), actualCpc: num(r['CoachWeeklyPlan.actualCpc']),
            lastNet: num(r['CoachWeeklyPlan.lastNet']), lastSpend: num(r['CoachWeeklyPlan.lastSpend']),
            lastUnits: num(r['CoachWeeklyPlan.lastUnits']), lastCpc: num(r['CoachWeeklyPlan.lastCpc']), units8w: num(r['CoachWeeklyPlan.units8w']),
            avgNetOff: num(r['CoachWeeklyPlan.avgNetDayOff']), avgNetPeak: num(r['CoachWeeklyPlan.avgNetDayPeak']),
          })));
        } catch { if (alive) setPlanCells([]); }
      })();
      (async () => {   // the family's waterfall daily budget (Step-1) — to re-scale the plan's per-cell budget
        try {
          const fb = await cubeLoad({
            dimensions: ['FamilyBudgetStep1.allocatedDaily'],
            filters: [{ member: 'FamilyBudgetStep1.parentName', operator: 'equals', values: [family] }],
          });
          if (!alive) return;
          const r = (fb as Record<string, unknown>[])[0] || {};
          setFamBudget(r['FamilyBudgetStep1.allocatedDaily'] != null ? Number(r['FamilyBudgetStep1.allocatedDaily']) : null);
        } catch { if (alive) setFamBudget(null); }
      })();
    } else { setBench(null); setPlanCells([]); setFamBudget(null); }
    // campaigns (level 1) for this product
    (async () => {
      try {
        const rows = await cubeLoad({
          dimensions: ['CoachRunCampaign.id', 'CoachRunCampaign.product', 'CoachRunCampaign.campaignName', 'CoachRunCampaign.campaignType',
            'CoachRunCampaign.recentDailySpend', 'CoachRunCampaign.adsNet60d', 'CoachRunCampaign.adsNetRoas60d',
            'CoachRunCampaign.adsNetRoas1w', 'CoachRunCampaign.adsNetRoasPrev1w', 'CoachRunCampaign.adsNetRoas4w',
            'CoachRunCampaign.effRoas', 'CoachRunCampaign.isNewCampaign',
            'CoachRunCampaign.coachMode', 'CoachRunCampaign.strategyType', 'CoachRunCampaign.strategyRole', 'CoachRunCampaign.daysSinceSuggestion',
            'CoachRunCampaign.needsStrategy', 'CoachRunCampaign.currentStrategyId', 'CoachRunCampaign.suggestedFamily', 'CoachRunCampaign.suggestedStrategy',
            'CoachRunCampaign.budgetAction', 'CoachRunCampaign.currentBudget', 'CoachRunCampaign.recommendedBudget', 'CoachRunCampaign.utilPct', 'CoachRunCampaign.noCoachDecision', 'CoachRunCampaign.ageBucket', 'CoachRunCampaign.strategyCategory'],
          filters: byProduct('CoachRunCampaign.product'),
        });
        if (!alive) return;
        const cs: CampRow[] = (rows as Record<string, unknown>[]).map(r => ({
          id: String(r['CoachRunCampaign.id'] ?? ''), product: String(r['CoachRunCampaign.product'] ?? ''),
          campaignName: String(r['CoachRunCampaign.campaignName'] ?? ''), campaignType: String(r['CoachRunCampaign.campaignType'] ?? ''),
          recentDailySpend: num(r['CoachRunCampaign.recentDailySpend']), adsNet60d: num(r['CoachRunCampaign.adsNet60d']), adsNetRoas60d: num(r['CoachRunCampaign.adsNetRoas60d']),
          roas1w: num(r['CoachRunCampaign.adsNetRoas1w']), roasPrev1w: num(r['CoachRunCampaign.adsNetRoasPrev1w']), roas4w: num(r['CoachRunCampaign.adsNetRoas4w']),
          effRoas: num(r['CoachRunCampaign.effRoas']), isNewCampaign: r['CoachRunCampaign.isNewCampaign'] === true || r['CoachRunCampaign.isNewCampaign'] === 'true',
          coachMode: String(r['CoachRunCampaign.coachMode'] ?? ''), strategyType: String(r['CoachRunCampaign.strategyType'] ?? 'MARGIN'),
          strategyRole: String(r['CoachRunCampaign.strategyRole'] ?? 'OTHER'), strategyCategory: String(r['CoachRunCampaign.strategyCategory'] ?? 'OTHER'), ageBucket: String(r['CoachRunCampaign.ageBucket'] ?? ''),
          budgetAction: String(r['CoachRunCampaign.budgetAction'] ?? ''), currentBudget: num(r['CoachRunCampaign.currentBudget']),
          recommendedBudget: num(r['CoachRunCampaign.recommendedBudget']), utilPct: num(r['CoachRunCampaign.utilPct']),
          daysSinceSuggestion: num(r['CoachRunCampaign.daysSinceSuggestion']),
          needsStrategy: r['CoachRunCampaign.needsStrategy'] === true || r['CoachRunCampaign.needsStrategy'] === 'true',
          currentStrategyId: String(r['CoachRunCampaign.currentStrategyId'] ?? ''), suggestedFamily: String(r['CoachRunCampaign.suggestedFamily'] ?? ''), suggestedStrategy: String(r['CoachRunCampaign.suggestedStrategy'] ?? ''),
          noCoachDecision: r['CoachRunCampaign.noCoachDecision'] === true || r['CoachRunCampaign.noCoachDecision'] === 'true',
        })).sort((a, b) => (b.recentDailySpend ?? 0) - (a.recentDailySpend ?? 0));
        setCamps(cs);
      } catch { if (alive) setCamps([]); }
    })();
    // keywords (level 2) for this product. Load for ANY selected product — NOT gated on the plan
    // (runByName): a product with "no plan" (unapproved / new week) still has campaigns + keywords to
    // manage. Store/Unknown selections simply return no rows (no keyword has parent_name 'Store').
    if (sel) {
      (async () => {
        try {
          const rows = await cubeLoad({
            dimensions: ['CoachRunKeyword.id', 'CoachRunKeyword.campaignId', 'CoachRunKeyword.campaignType', 'CoachRunKeyword.adGroupId', 'CoachRunKeyword.targeting', 'CoachRunKeyword.matchType',
              'CoachRunKeyword.action', 'CoachRunKeyword.currentBid', 'CoachRunKeyword.recommendedBid', 'CoachRunKeyword.bidChangePct',
              'CoachRunKeyword.reason', 'CoachRunKeyword.isAction', 'CoachRunKeyword.priorityScore', 'CoachRunKeyword.daysSinceChange', 'CoachRunKeyword.daysSinceSuggestion', 'CoachRunKeyword.targetCpc',
              'CoachRunKeyword.w1ClkDay', 'CoachRunKeyword.w1Cpc', 'CoachRunKeyword.w1Roas', 'CoachRunKeyword.w1Units', 'CoachRunKeyword.w4ClkDay', 'CoachRunKeyword.w4Cpc', 'CoachRunKeyword.w4Roas', 'CoachRunKeyword.w4Units', 'CoachRunKeyword.pkClkDay', 'CoachRunKeyword.pkCpc', 'CoachRunKeyword.pkRoas', 'CoachRunKeyword.pkUnits'],
            filters: byProduct('CoachRunKeyword.parentName'),
          });
          if (!alive) return;
          const mapped = (rows as Record<string, unknown>[]).map(r => ({
            id: String(r['CoachRunKeyword.id'] ?? ''), campaignId: String(r['CoachRunKeyword.campaignId'] ?? ''), campaignType: String(r['CoachRunKeyword.campaignType'] ?? ''), adGroupId: String(r['CoachRunKeyword.adGroupId'] ?? ''),
            targeting: String(r['CoachRunKeyword.targeting'] ?? ''), matchType: String(r['CoachRunKeyword.matchType'] ?? ''),
            action: String(r['CoachRunKeyword.action'] ?? ''), currentBid: num(r['CoachRunKeyword.currentBid']),
            newBid: num(r['CoachRunKeyword.recommendedBid']), pct: num(r['CoachRunKeyword.bidChangePct']),
            reason: String(r['CoachRunKeyword.reason'] ?? ''),
            isAction: r['CoachRunKeyword.isAction'] === true || r['CoachRunKeyword.isAction'] === 'true',
            priority: num(r['CoachRunKeyword.priorityScore']) ?? 0,
            daysSinceChange: num(r['CoachRunKeyword.daysSinceChange']), daysSinceSuggestion: num(r['CoachRunKeyword.daysSinceSuggestion']), targetCpc: num(r['CoachRunKeyword.targetCpc']),
            w1ClkDay: num(r['CoachRunKeyword.w1ClkDay']), w1Cpc: num(r['CoachRunKeyword.w1Cpc']), w1Roas: num(r['CoachRunKeyword.w1Roas']), w1Units: num(r['CoachRunKeyword.w1Units']),
            w4ClkDay: num(r['CoachRunKeyword.w4ClkDay']), w4Cpc: num(r['CoachRunKeyword.w4Cpc']), w4Roas: num(r['CoachRunKeyword.w4Roas']), w4Units: num(r['CoachRunKeyword.w4Units']),
            pkClkDay: num(r['CoachRunKeyword.pkClkDay']), pkCpc: num(r['CoachRunKeyword.pkCpc']), pkRoas: num(r['CoachRunKeyword.pkRoas']), pkUnits: num(r['CoachRunKeyword.pkUnits']),
          }));
          setKws(mapped);
          // Self-heal: repair stale queued keyword rows (queued before the ad-group fix)
          // that lost their ad_group_id, so the next bulksheet export carries it.
          const agLookup: Record<string, string> = {};
          for (const k of mapped) { if (k.id && k.adGroupId) agLookup[k.id] = k.adGroupId; }
          doQueue.backfillAdGroups(agLookup);
        } catch { if (alive) setKws([]); }
      })();
      // negatives (level 3) — engine NEGATE_TERM terms per keyword
      (async () => {
        try {
          const rows = await cubeLoad({
            dimensions: ['CoachRunNegative.id', 'CoachRunNegative.keywordId', 'CoachRunNegative.campaignId', 'CoachRunNegative.campaignName',
              'CoachRunNegative.adGroupId', 'CoachRunNegative.targeting', 'CoachRunNegative.searchTerm', 'CoachRunNegative.reason',
              'CoachRunNegative.peakClicks', 'CoachRunNegative.peakOrders', 'CoachRunNegative.peakNet', 'CoachRunNegative.peakConverts',
              'CoachRunNegative.heroAsin', 'CoachRunNegative.heroProductName', 'CoachRunNegative.heroCvr', 'CoachRunNegative.wrongAsin'],
            filters: byProduct('CoachRunNegative.parentName'),
          });
          if (!alive) return;
          setNegs((rows as Record<string, unknown>[]).map(r => ({
            id: String(r['CoachRunNegative.id'] ?? ''), keywordId: String(r['CoachRunNegative.keywordId'] ?? ''),
            campaignId: String(r['CoachRunNegative.campaignId'] ?? ''), campaignName: String(r['CoachRunNegative.campaignName'] ?? ''),
            adGroupId: String(r['CoachRunNegative.adGroupId'] ?? ''), targeting: String(r['CoachRunNegative.targeting'] ?? ''),
            searchTerm: String(r['CoachRunNegative.searchTerm'] ?? ''), reason: String(r['CoachRunNegative.reason'] ?? ''),
            peakClicks: num(r['CoachRunNegative.peakClicks']), peakOrders: num(r['CoachRunNegative.peakOrders']), peakNet: num(r['CoachRunNegative.peakNet']),
            peakConverts: r['CoachRunNegative.peakConverts'] === true || r['CoachRunNegative.peakConverts'] === 'true',
            heroAsin: String(r['CoachRunNegative.heroAsin'] ?? ''), heroProductName: String(r['CoachRunNegative.heroProductName'] ?? ''),
            heroCvr: num(r['CoachRunNegative.heroCvr']), wrongAsin: r['CoachRunNegative.wrongAsin'] === true || r['CoachRunNegative.wrongAsin'] === 'true',
          })));
        } catch { if (alive) setNegs([]); }
      })();
    } else { setKws([]); setNegs([]); }
    return () => { alive = false; };
  }, [sel, runByName]);

  const famArg = (name: string): FamilyName | undefined => CORE_FAMILIES.includes(name) ? name as FamilyName : undefined;
  const doneCount = Object.values(runByName).filter(r => r.status === 'DONE').length;
  const familyCount = Object.keys(runByName).length;
  // Weekly-run status per family, for the step-1 table (which now doubles as the family selector).
  const statusByFamily = useMemo(() => Object.fromEntries(
    Object.entries(runByName).map(([f, r]) => [f, { done: r.status === 'DONE', escalation: !!r.has_escalation }])
  ), [runByName]);

  // ── Queue integration (shared Do queue → Upload exports the bulksheet) ──
  const queuedItem = (search_term: string, action: string, campaign: string) =>
    doQueue.items.find(i => i.search_term === search_term && i.action === action && i.campaign === campaign);
  // The bid shown in each keyword's input: manual draft > coacher's suggested new bid > current bid.
  // Defense dominance rule: a defense keyword's bid should be ≥ 1.5× its CPC (own the top of page 1,
  // make the term expensive for competitors). CPC = 28d, fallback 7d.
  const defenseCpc = (k: KwRow): number | null => k.w4Cpc ?? k.w1Cpc ?? null;
  const defenseMinBid = (k: KwRow): number | null => { const c = defenseCpc(k); return c != null && c > 0 ? Math.round(c * 1.5 * 100) / 100 : null; };
  const kwBidValue = (k: KwRow): number | null => {
    const base = kwBidDraft[k.id] ?? k.newBid ?? k.currentBid ?? null;
    // In defense mode, pre-fill to at least 1.5× CPC (unless the user typed a manual override).
    if (ppcMode === 'brand_defense' && kwBidDraft[k.id] == null) {
      const mb = defenseMinBid(k);
      if (mb != null && (base == null || base < mb)) return mb;
    }
    return base;
  };
  const defenseUnderBid = (k: KwRow): boolean => {
    if (ppcMode !== 'brand_defense' || k.currentBid == null) return false;
    const mb = defenseMinBid(k);
    return mb != null && k.currentBid < mb - 0.001;
  };
  // Step-3 filter predicates. "Applied" = a change was uploaded inside the 3-day cooldown (same test the
  // ✓-applied badge uses). A keyword also stays under "not applied" while it still has terms to negate,
  // since negatives carry no cooldown of their own.
  const isApplied = (days: number | null): boolean => days != null && days < 3;
  // Effective days-since = MIN(cube value, live change-log value) so a just-uploaded bulksheet registers
  // immediately instead of waiting for the next cube rebuild (Ori 2026-07-25). kwDss is the per-keyword form.
  const kwDss = (k: KwRow): number | null => effectiveDaysSince(k.id, k.daysSinceSuggestion);
  const kwVisible = (k: KwRow): boolean => {
    const hasNegs = (negs ?? []).some(n => n.keywordId === k.id);
    const label = kwDir(k).label;
    // Direction filter (single-select). Default (null): show all actionable directions but hide the
    // no-change HOLD rows — unless a HOLD row still has negatives to action, so it isn't lost. A picked
    // direction is strict: show ONLY that direction (negatives don't override, or the focus is useless
    // when many keywords have pending negatives).
    if (dirFilter === null) {
      if (label === 'hold' && !hasNegs) return false;
    } else if (label !== dirFilter) {
      return false;
    }
    if (actionFilter === 'all') return true;
    if (actionFilter === 'done') return isApplied(kwDss(k));
    return !isApplied(kwDss(k)) || hasNegs;
  };
  // Single-select: click a direction to focus it; click the active one again to clear back to default.
  const pickDir = (d: string) => setDirFilter(prev => (prev === d ? null : d));
  // Per-value counts for the filter chips ("amount of action per value"). Facet totals over the
  // in-scope keywords: every keyword has exactly one direction, so the direction counts sum to All,
  // and Not applied + Already applied = All. Independent of the current filter selection.
  // Keywords in the current strategy slice. The chip counts must respect it too, or "raise 12" would
  // count keywords the strategy filter has hidden from the list below.
  const campById = useMemo(() => Object.fromEntries((camps ?? []).map(c => [c.id, c])), [camps]);
  // Is the launch-controller section (NewCampaignCards) actually rendered right now? Must mirror the
  // render condition below. New campaigns are owned by that section, so the mature table below hides
  // them to avoid showing the same campaign twice (Ori 2026-07-24). Gated on "is it shown" rather than
  // just membership so a launch campaign can never disappear from BOTH lists under a filter combo.
  const launchCardsShown = ppcMode === 'offense' && (selAge === ALL_AGES || selAge === 'LOW_BUDGET');
  // Membership keys off ageBucket (== the launch population), NOT isNewCampaign: the coach flag is NULL
  // for a low-budget campaign that has no V_ADS_COACH rows yet, which would leak it into the mature
  // table. ageBucket comes straight from V_LAUNCH_POPULATION, so the two lists agree by construction.
  const ownedByLaunch = useCallback(
    (c?: CampRow) => launchCardsShown && c?.ageBucket === 'LOW_BUDGET',
    [launchCardsShown],
  );
  const kwInStrategy = useCallback((k: KwRow): boolean => {
    const c = campById[k.campaignId];
    // Keywords of launch-owned campaigns must leave the mature action chips too, or "raise 12"
    // would count work that lives in the launch cards above.
    if (ownedByLaunch(c)) return false;
    if (selAge !== ALL_AGES && (!c || c.ageBucket !== selAge)) return false;
    if (ppcMode !== 'offense' || selStrategy === ALL_STRATEGIES) return true;
    return !!c && c.strategyCategory === selStrategy;
  }, [ppcMode, selStrategy, selAge, campById, ownedByLaunch]);
  const scopedKws = useMemo(() => (kws ?? []).filter(kwInStrategy), [kws, kwInStrategy]);
  const dirCounts = useMemo(() => {
    const c: Record<string, number> = { raise: 0, lower: 0, probe: 0, set: 0, hold: 0 };
    scopedKws.forEach(k => { const l = kwDir(k).label; if (l in c) c[l] += 1; });
    return c;
  }, [scopedKws]);
  const appliedCounts = useMemo(() => {
    // PAGE-WIDE: mature keywords + launch targets (only when the launch section is actually shown, matching
    // the filter's effect). "done" = already uploaded, on both sides, via the live change-log signal.
    const lc = launchCardsShown ? launchCts : { all: 0, done: 0 };
    const all = scopedKws.length + lc.all;
    const done = scopedKws.filter(k => isApplied(kwDss(k))).length + lc.done;
    return { todo: all - done, done, all };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [scopedKws, effectiveDaysSince, launchCts, launchCardsShown]);
  const campVisible = (c: CampRow): boolean => {
    // New campaigns live in the launch-controller cards above — never list them twice.
    if (ownedByLaunch(c)) return false;
    // PPC mode gate — each mode shows ONLY its own role's campaigns (offense / brand-defense / product-defense).
    // (pool gate removed — all pools show; strategy filter narrows)
    // Strategy gate (offense only — the strategy split is an offense-role slice). Keywords nest under
    // their campaign in step 4, so gating the campaign filters its keywords with it.
    if (ppcMode === 'offense' && selStrategy !== ALL_STRATEGIES && c.strategyCategory !== selStrategy) return false;
    // Age gate — the "Budget by age" filter (independent of strategy; both AND together).
    if (selAge !== ALL_AGES && c.ageBucket !== selAge) return false;
    const anyKw = (kws ?? []).some(k => k.campaignId === c.id && kwVisible(k));
    // Focused on a keyword direction → only show campaigns that actually contain such a keyword,
    // so "raise" really means "the campaigns with a raise", not every campaign with a raise nested.
    if (dirFilter !== null) return anyKw;
    if (actionFilter === 'all') return true;
    if (actionFilter === 'done') return isApplied(c.daysSinceSuggestion) || anyKw;
    return !isApplied(c.daysSinceSuggestion) || anyKw;
  };
  // A queued bid change for this keyword (any direction), matched by keyword_id so text collisions don't matter.
  const bidQueuedItem = (k: KwRow) => doQueue.items.find(i => i.keyword_id === k.id && ['INCREASE_BID', 'REDUCE_BID', 'PROBE'].includes(i.action));
  const stopQueuedItem = (k: KwRow) => doQueue.items.find(i => i.keyword_id === k.id && i.action === 'STOP_TARGET');
  const kwItem = (k: KwRow, campaignName: string, bid: number) => {
    // If the queued bid equals the coacher's own suggestion, keep its action+COACH source (clean scorecard
    // attribution); otherwise it's a manual override → direction-derived action + MANUAL source.
    const isCoach = k.newBid != null && Math.abs(bid - k.newBid) < 0.001 && ['INCREASE_BID', 'REDUCE_BID', 'PROBE'].includes(k.action);
    const action = isCoach ? k.action : (bid >= (k.currentBid ?? 0) ? 'INCREASE_BID' : 'REDUCE_BID');
    return {
      search_term: k.targeting, action, campaign: campaignName, campaign_id: k.campaignId,
      ad_group_id: k.adGroupId, targeting: k.targeting, keyword_id: k.id, match_type: k.matchType,
      target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0, current_bid: k.currentBid, recommended_bid: bid,
      campaign_type: k.campaignType, product: k.targeting, spend: 0, orders: 0, cpc: 0, conv_rate: 0,
      source: (isCoach ? 'COACH' : 'MANUAL') as 'COACH' | 'MANUAL',
    };
  };
  const stopItem = (k: KwRow, campaignName: string) => ({
    // Pause the keyword/target so it stops spending (STOP_TARGET → state=paused in the bulksheet).
    search_term: k.targeting, action: 'STOP_TARGET', campaign: campaignName, campaign_id: k.campaignId,
    ad_group_id: k.adGroupId, targeting: k.targeting, keyword_id: k.id, match_type: k.matchType,
    target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0, current_bid: k.currentBid, recommended_bid: null,
    campaign_type: k.campaignType, product: k.targeting, spend: 0, orders: 0, cpc: 0, conv_rate: 0, source: 'MANUAL' as const,
  });
  const openManage = (c: CampRow) => setManageCamp({ id: c.id, campaignName: c.campaignName, product: c.product, isSB: /SB|BRAND|VIDEO|STORE/i.test(`${c.campaignType} ${c.campaignName}`), currentStrategyId: c.currentStrategyId, suggestedFamily: c.suggestedFamily, suggestedStrategy: c.suggestedStrategy });
  const toggleKwQ = (k: KwRow, campaignName: string) => {
    const ex = bidQueuedItem(k);
    if (ex) { doQueue.removeItem(ex.id); return; }
    const bid = kwBidValue(k);
    if (bid == null) return;
    doQueue.addItem(kwItem(k, campaignName, bid));
  };
  const toggleStopQ = (k: KwRow, campaignName: string) => { const ex = stopQueuedItem(k); if (ex) doQueue.removeItem(ex.id); else doQueue.addItem(stopItem(k, campaignName)); };
  const negItem = (n: NegRow, campaignType: string) => ({
    search_term: n.searchTerm, action: 'NEGATE_TERM', campaign: n.campaignName, campaign_id: n.campaignId,
    ad_group_id: n.adGroupId, targeting: n.targeting, keyword_id: '', match_type: 'NEGATIVE_EXACT',
    target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0, current_bid: null, recommended_bid: null,
    campaign_type: campaignType, product: n.searchTerm, spend: 0, orders: 0, cpc: 0, conv_rate: 0, source: 'COACH' as const,
  });
  const toggleNegQ = (n: NegRow, campaignType: string) => { const ex = queuedItem(n.searchTerm, 'NEGATE_TERM', n.campaignName); if (ex) doQueue.removeItem(ex.id); else doQueue.addItem(negItem(n, campaignType)); };
  // Separate from negate: add the hero (best-converting) variant as a product ad in the SAME ad group,
  // so the wrong-colour term gets the right product shown instead of just being blocked. One row per
  // (ad group, hero ASIN) — deduped by campaign+ad_group+asin so two terms sharing a hero don't double-add.
  const heroAdItem = (n: NegRow, campaignType: string) => ({
    search_term: n.heroProductName, action: 'ADD_PRODUCT_AD', campaign: n.campaignName, campaign_id: n.campaignId,
    ad_group_id: n.adGroupId, targeting: '', keyword_id: '', match_type: '',
    target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0, current_bid: null, recommended_bid: null,
    campaign_type: campaignType, product: n.heroProductName, asin: n.heroAsin, spend: 0, orders: 0, cpc: 0, conv_rate: 0, source: 'COACH' as const,
  });
  const heroAdQueued = (n: NegRow) => doQueue.items.some(i => i.action === 'ADD_PRODUCT_AD' && i.campaign_id === n.campaignId && i.ad_group_id === n.adGroupId && i.asin === n.heroAsin);
  const toggleHeroAdQ = (n: NegRow, campaignType: string) => { const ex = doQueue.items.find(i => i.action === 'ADD_PRODUCT_AD' && i.campaign_id === n.campaignId && i.ad_group_id === n.adGroupId && i.asin === n.heroAsin); if (ex) doQueue.removeItem(ex.id); else doQueue.addItem(heroAdItem(n, campaignType)); };

  const approve = async () => {
    if (!currentRun) return;
    setBusy(true);
    try { await dataEntry.approveWeeklyRun({ parent_name: currentRun.parent_name, week_start: currentRun.week_start, note: note || undefined }); await load(); }
    catch { /* keep state */ } finally { setBusy(false); }
  };
  const markDone = async () => {
    if (!currentRun) return;
    setBusy(true);
    try {
      await dataEntry.doneWeeklyRun({ parent_name: currentRun.parent_name, week_start: currentRun.week_start, note: note || undefined });
      await load();
      const nextPending = (products ?? []).find(p => runByName[p.product] && runByName[p.product].status !== 'DONE' && p.product !== currentRun.parent_name);
      if (nextPending) setSel(nextPending.product);
    } catch { /* keep state */ } finally { setBusy(false); }
  };

  if (loading) return <div className="p-6 text-muted">Loading…</div>;
  if (err) return <div className="p-6 text-red-400">Couldn't load Weekly Run: {err}</div>;
  if (!products) return <div className="p-6 text-muted">No products.</div>;

  return (
    <div className="max-w-[1600px] mx-auto px-4 py-6 text-text">
      <div className="flex items-baseline justify-between mb-4">
        <h1 className="text-title font-medium">Weekly Run{week ? <span className="text-muted font-normal"> · {weekRange(week)}</span> : ''}</h1>
        <span className="text-label text-muted">{doneCount} of {familyCount} done · {products.length} products</span>
      </div>
      {anchor && (
        <div className="mb-4 flex flex-wrap items-center gap-x-4 gap-y-1 text-label rounded-lg border border-border/60 bg-surface/40 px-3 py-1.5">
          <span className="text-faint">Windows anchor on the last complete day (America/Los_Angeles):</span>
          <span className="font-mono text-muted"><span className="text-faint">last day</span> = {fmtDay(anchor)}</span>
          <span className="font-mono text-muted"><span className="text-faint">last 7 days</span> = {last7Range(anchor)}</span>
        </div>
      )}

      {/* PPC pools unified (Ori 2026-07-18): no mode toggle — every pool's campaigns show in one list;
          the cross-pool "Budget by strategy" filter (incl. Brand/Product Defense) narrows step 2 & 4. */}

      {ppcMode === 'brand_defense'
        ? <RoleBudgetPanel role="BRAND_DEFENSE" configKey="defense_total_daily" title="Brand Defense budget — own the brand SERP" subtitle="split across families by defense spend-need; control the video slot, bid to stay #1" showUnderbid selected={sel} onSelect={setSel} statusByFamily={statusByFamily} onAllocations={setDefenseAllocs} />
        : ppcMode === 'product_defense'
        ? <RoleBudgetPanel role="PRODUCT_DEFENSE" configKey="product_defense_total_daily" title="Product Defense budget — cross-sell learning" subtitle="each campaign starts at $30 to learn the best product-on-product pairings; ROI-managed" selected={sel} onSelect={setSel} statusByFamily={statusByFamily} onAllocations={setDefenseAllocs} />
        : <BudgetStep1 onAllocations={setLiveAllocs} familyEdits={familyEdits} mode="offense" selected={sel} onSelect={setSel} statusByFamily={statusByFamily}
            selectedStrategy={selStrategy} onSelectStrategy={setSelStrategy} selectedAge={selAge} onSelectAge={setSelAge} />}

      {familyCount > 0 && doneCount === familyCount && (
        <div className="text-emerald-400 text-label mb-2">Week complete 🎉</div>
      )}

      {/* ── Selected product stepper (full width; the step-1 family table above is the selector) ── */}
      <main className="min-w-0">
          {!current ? <div className="text-muted">Click a family in the table above to manage its campaigns.</div> : (
            <div className="flex flex-col gap-4">
              <div className="flex items-center gap-3">
                <h2 className="text-body font-semibold">{isAll ? 'All families' : current.product}</h2>
                {isAll
                  ? <span className="text-label text-faint">· every campaign · {doneCount} of {familyCount} families done</span>
                  : <>
                      <span className={`text-label ${chip(currentRun?.status).cls}`}>{chip(currentRun?.status).label}</span>
                      {currentRun?.has_escalation && <span className="text-label text-red-400">· {currentRun.escalation_severity?.toLowerCase()} ({fM(currentRun.escalation_net)})</span>}
                      {!isFamily && <span className="text-label text-faint">· {current.product === 'Unknown' ? 'unmapped campaigns' : 'cross-product'}</span>}
                    </>}
              </div>

              {/* Step 2 — Budget (per-campaign waterfall allocation; edit + queue). Shown for every product.
                  Reports its live total up so the Total-budget panel's grand total re-sums. */}
              {/* liveAlloc is the FAMILY's Step-1 budget, which covers all its campaigns — so it must not
                  be passed while a strategy is picked, or step 2 would show "Step-1 target $414.16" over
                  a list of just that family's Auto campaigns. Null → the panel targets Σ of what's shown. */}
              {/* Sections 2 (per-campaign budget) & 3 (plan) removed (Ori 2026-07-18): budget is now decided
                  inside each campaign card in section 4. Kept behind a disabled guard for easy revert. */}
              {SHOW_STEP_2_3 && <WeeklyBudgetCampaigns family={current.product} strategy={ppcMode === 'offense' ? selStrategy : ALL_STRATEGIES}
                ageBucket={ppcMode === 'offense' ? selAge : ALL_AGES}
                liveAlloc={ppcMode === 'offense'
                  ? (selStrategy === ALL_STRATEGIES && selAge === ALL_AGES ? (liveAllocs[current.product] ?? famBudget) : null)
                  : (defenseAllocs[current.product] ?? null)}
                onFamilyTotal={handleFamilyTotal} mode={ppcMode} />}

              {/* Step 3 — Plan (removed; see note above) */}
              {SHOW_STEP_2_3 && (isFamily && currentRun ? (
                <section className="rounded-xl border border-border bg-card p-4">
                  <div className="text-label font-medium text-muted mb-2">3 · Plan — review &amp; approve</div>
                  <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 text-body mb-3">
                    <div><div className="text-label text-faint">purposes</div><div className="text-muted">{currentRun.purposes || '—'}</div></div>
                    <div><div className="text-label text-faint">cells</div><div className="font-mono">{currentRun.cells} ({currentRun.scale_cells} scale)</div></div>
                    <div><div className="text-label text-faint">daily planned spend</div><div className="font-mono" title={`${fM(currentRun.planned_spend)} / week`}>{fM(perDay(currentRun.planned_spend))}/day</div></div>
                    <div><div className="text-label text-faint">current budget</div><div className="font-mono text-faint" title="the family's current daily budget on Amazon (sum of its campaigns)">{fM(current.currentDailyBudget)}/day</div></div>
                    <div><div className="text-label text-faint">new budget</div><div className="font-mono text-blue-300" title="the family's Step-1 waterfall allocation (from the total-budget panel)">{fM(liveAllocs[current.product] ?? famBudget)}/day</div></div>
                    <div><div className="text-label text-faint">est. ads profit</div><div className={`font-mono ${npCls(currentRun.forward_ads_net)}`} title={currentRun.scale_cells > 0 ? `${fM(currentRun.forward_ads_net)} / week` : undefined}>{currentRun.scale_cells > 0 ? `${fM(perDay(currentRun.forward_ads_net))}/day` : 'cut only'}</div></div>
                  </div>
                  {bench && (() => {
                    const peakTip = `Last peak week${bench.lastPeakWeek ? ' ' + weekRange(bench.lastPeakWeek) : ''} — what this product did the most recent peak week`;
                    const offTip = `Last offseason week${bench.lastOffWeek ? ' ' + weekRange(bench.lastOffWeek) : ''} — what this product did the most recent off-season week`;
                    return (
                      <div className="text-body mb-3 flex flex-col gap-1.5">
                        <div title={peakTip} className="cursor-help"><span className="text-faint">Last peak week:</span>{' '}ads profit <span className={npCls(bench.lastPeakNet)}>{fM(bench.lastPeakNet)}</span>{' · '}total profit w/ organic <span className={npCls(bench.lastPeakBiz)}>{fM(bench.lastPeakBiz)}</span>{' · '}ad spend <span className="text-muted">{fM(perDay(bench.lastPeakSpend))}/day</span></div>
                        <div title={offTip} className="cursor-help"><span className="text-faint">Last off-season week:</span>{' '}ads profit <span className={npCls(bench.lastOffNet)}>{fM(bench.lastOffNet)}</span>{' · '}total profit w/ organic <span className={npCls(bench.lastOffBiz)}>{fM(bench.lastOffBiz)}</span>{' · '}ad spend <span className="text-muted">{fM(perDay(bench.lastOffSpend))}/day</span></div>
                      </div>
                    );
                  })()}
                  {planCells && planCells.length > 0 && (() => {
                    // PPC mode gate — defense mode shows only DEFEND cells; offense mode the rest.
                    // Offense = non-DEFEND cells; Brand Defense = DEFEND cells; Product Defense has no keyword plan cells (ASIN targeting).
                    const modeCells = (ppcMode === 'product_defense' ? [] : planCells.filter(c => ppcMode === 'brand_defense' ? c.purpose === 'DEFEND' : c.purpose !== 'DEFEND'))
                      // Strategy gate — same slice as steps 2 & 4 (offense only; the plan's role is
                      // derived from its match type / campaign type in the CoachWeeklyPlan cube).
                      .filter(c => ppcMode !== 'offense' || selStrategy === ALL_STRATEGIES || c.strategyRole === selStrategy);
                    if (modeCells.length === 0) return null;
                    const sorted = [...modeCells].sort((a, b) => (PURPOSE_ORDER[a.purpose] ?? 9) - (PURPOSE_ORDER[b.purpose] ?? 9) || (b.expNet ?? 0) - (a.expNet ?? 0));
                    const scale = modeCells.filter(c => c.purpose === 'SCALE');
                    const scaleTotal = scale.reduce((s, c) => s + (c.expNet ?? 0), 0);
                    // re-scale the plan's per-cell budget to the family's waterfall daily budget (Step-1),
                    // so "new budget" tracks your total. Falls back to the plan's raw split if not loaded.
                    // NOT while a strategy is picked: the family budget covers ALL its cells, so dividing
                    // it over a filtered subset would hand the family's whole budget to the few visible
                    // cells (Lollibox + Auto showed one cell holding all $414.16). Filtered = show the
                    // plan's own per-cell budget, unscaled.
                    const sumPlannedDaily = sorted.reduce((s, c) => s + (c.plannedSpend || 0) / 7, 0);
                    const strategyFiltered = ppcMode === 'offense' && selStrategy !== ALL_STRATEGIES;
                    const effFamBudget = (ppcMode === 'offense' ? liveAllocs[current.product] : defenseAllocs[current.product]) ?? famBudget;   // live Step-1 value wins; cube fetch is the fallback
                    const budScale = (!strategyFiltered && effFamBudget != null && sumPlannedDaily > 0) ? effFamBudget / sumPlannedDaily : 1;
                    return (
                      <details className="text-label mb-3">
                        <summary className="text-faint cursor-pointer">plan detail — {sorted.length} cells, est. ads profit {fM(perDay(scaleTotal))}/day</summary>
                        <div className="text-faint mb-1">$ &amp; unit columns are per day (daily average) · net = ad net profit</div>
                        <table className="w-full border-collapse mt-1">
                          <thead><tr className="text-faint text-left">
                            <th className="font-normal py-1">do</th>
                            <th className="font-normal py-1">match · intent</th>
                            <th className="font-normal py-1 text-right" title="the cell's current daily ad spend (prior complete week ÷ 7)">spend</th>
                            <th className="font-normal py-1 text-right" title="the plan's per-cell split, scaled to this family's Step-1 waterfall budget — sums to the family's new budget">new budget</th>
                            <th className="font-normal py-1 text-right">target CPC</th>
                            <th className="font-normal py-1 text-right" title="expected ad net profit per day (SCALE cells)">est</th>
                            <th className="font-normal py-1 text-right" title="prior complete week's ad net profit ÷ 7">last net</th>
                            <th className="font-normal py-1 text-right" title="prior complete week's actual CPC (spend ÷ clicks)">last CPC</th>
                            <th className="font-normal py-1 text-right" title="ad units sold per day, prior complete week">sold 7d</th>
                            <th className="font-normal py-1 text-right" title="ad units sold per day, trailing 8 weeks — the volume behind the organic halo">sold 8w</th>
                            <th className="font-normal py-1 text-right" title="lifetime avg ad net profit per day for this cell, off-season">off net</th>
                            <th className="font-normal py-1 text-right" title="lifetime avg ad net profit per day for this cell, during its relevant peaks">peak net</th>
                          </tr></thead>
                          <tbody>{sorted.map((c, i) => (
                            <tr key={i} className="border-t border-border/50">
                              <td className="py-1 font-medium" title={PURPOSE_TOOLTIP[c.purpose] || undefined}>{c.purpose.toLowerCase()}</td>
                              <td className="py-1 text-muted">{c.matchType} · {c.intentClass.toLowerCase()}{planFormatLabel(c.campaignType, c.adFormat) && <span className="text-faint"> · {planFormatLabel(c.campaignType, c.adFormat)}</span>}</td>
                              <td className="py-1 text-right font-mono">{c.lastSpend != null ? <span className="text-muted">{fM(perDay(c.lastSpend))}</span> : <span className="text-faint">—</span>}</td>
                              <td className="py-1 text-right font-mono">{c.plannedSpend ? <span className="text-blue-300">{fM((c.plannedSpend / 7) * budScale)}</span> : <span className="text-faint">—</span>}</td>
                              <td className="py-1 text-right font-mono">{c.targetCpc != null ? (() => { const above = c.actualCpc != null && c.targetCpc! > c.actualCpc; return <span className={`underline ${above ? 'text-red-400' : ''}`} title={c.actualCpc != null ? `actual CPC $${c.actualCpc.toFixed(2)}` : undefined}>${c.targetCpc!.toFixed(2)}{above ? ` (act $${c.actualCpc!.toFixed(2)})` : ''}</span>; })() : '—'}</td>
                              <td className="py-1 text-right font-mono">{c.purpose === 'SCALE' ? <span className={npCls(c.expNet)}>{fM(perDay(c.expNet))}</span> : (c.purpose === 'MAP' || c.purpose === 'PROBE') ? <span className="text-muted">{Math.round(c.expNet ?? 0)} clk/wk</span> : <span className="text-faint">—</span>}</td>
                              <td className="py-1 text-right font-mono">{c.lastNet != null ? <span className={npCls(c.lastNet)}>{fM(perDay(c.lastNet))}</span> : <span className="text-faint">—</span>}</td>
                              <td className="py-1 text-right font-mono">{c.lastCpc != null ? <span className="text-muted">${c.lastCpc.toFixed(2)}</span> : <span className="text-faint">—</span>}</td>
                              <td className="py-1 text-right font-mono" title={c.lastUnits != null ? `${c.lastUnits} sold last week (total)` : undefined}>{c.lastUnits != null && c.lastUnits > 0 ? <span className="text-muted">{Math.round(c.lastUnits / 7)}</span> : <span className="text-faint">—</span>}</td>
                              <td className="py-1 text-right font-mono" title={c.units8w != null ? `${c.units8w} sold over 8 weeks (total)` : undefined}>{c.units8w != null && c.units8w > 0 ? <span className="text-muted">{Math.round(c.units8w / 56)}</span> : <span className="text-faint">—</span>}</td>
                              <td className="py-1 text-right font-mono">{c.avgNetOff != null ? <span className={npCls(c.avgNetOff)}>{fM(c.avgNetOff)}</span> : <span className="text-faint">—</span>}</td>
                              <td className="py-1 text-right font-mono">{c.avgNetPeak != null ? <span className={npCls(c.avgNetPeak)}>{fM(c.avgNetPeak)}</span> : <span className="text-faint">—</span>}</td>
                            </tr>
                          ))}</tbody>
                        </table>
                      </details>
                    );
                  })()}
                  <button disabled={busy} onClick={approve}
                    className="text-label px-3 py-1.5 rounded-md border border-emerald-500/40 text-emerald-400 hover:bg-emerald-500/10 disabled:opacity-50">
                    {currentRun.status === 'PENDING' ? 'Approve plan' : '✓ Approved'}
                  </button>
                </section>
              ) : (
                <section className="rounded-xl border border-border bg-card p-4">
                  <div className="text-label font-medium text-muted mb-1">3 · Plan</div>
                  <p className="text-label text-subtle">{current.product === 'Unknown' ? 'These campaigns aren’t mapped to a product, so there’s no plan. Map them (Admin → Campaign Mapping); set their budgets in step 2 above.' : 'This bucket spans multiple product lines — no single plan. Set budgets in step 2 above; manage keywords below.'}</p>
                </section>
              ))}

              {/* Step 4 — Actions (keywords, negatives & per-campaign budget) */}
              <section className="rounded-xl border border-border bg-card p-4">
                <div className="text-label font-medium text-muted mb-2">4 · Actions — keywords, negatives &amp; budget</div>
                {/* Filter by what's still open vs. already uploaded (inside the 3-day cooldown). Default = Not applied. */}
                <div className="flex items-center flex-wrap gap-1 mb-3">
                  {([['todo', 'Not applied', appliedCounts.todo], ['done', 'Already applied', appliedCounts.done], ['all', 'All', appliedCounts.all]] as const).map(([val, label, n]) => (
                    <button key={val} onClick={() => setActionFilter(val)}
                      className={`text-label px-2.5 py-1 rounded-md border ${actionFilter === val ? 'border-blue-500/50 bg-blue-500/10 text-blue-300' : 'border-border text-muted hover:bg-white/5'}`}>
                      {label} <span className="font-mono opacity-60">{n}</span>
                    </button>
                  ))}
                  <span className="text-label text-faint ml-1">— what’s left to do vs. already uploaded (3-day cooldown)</span>
                </div>
                {/* Action filter — which keyword directions to show. Default = all except HOLD. */}
                <div className="flex items-center flex-wrap gap-1 mb-3">
                  <span className="text-label text-faint mr-1">action</span>
                  {KW_DIRECTIONS.map(d => (
                    <button key={d} onClick={() => pickDir(d)}
                      className={`text-label px-2.5 py-1 rounded-md border ${dirFilter === d ? 'border-blue-500/50 bg-blue-500/10 text-blue-300' : 'border-border text-muted hover:bg-white/5'}`}>
                      {d} <span className="font-mono opacity-60">{dirCounts[d]}</span>
                    </button>
                  ))}
                  <span className="text-label text-faint ml-1">— click one to focus; HOLD hidden by default</span>
                </div>
                {/* coach logic as a flow chart (strategy toggles) — the engine driving every decision below */}
                <CoachFlowchart />
                {/* out-of-budget technical phase — dark campaigns + one budget suggestion each (V_OOB_BUDGET_PHASE) */}
                <OobBudgetPhase />
                {/* New campaigns (0–20d) launch-controller cards — co-located directly under the coach logic, above the mature actions */}
                {ppcMode === 'offense' && (selAge === ALL_AGES || selAge === 'LOW_BUDGET') && (
                  <div className="mt-3 mb-4">
                    <div className="text-label text-violet-300 mb-1">Low budget — launch controller (≤ $20 · $30 peak)</div>
                    <NewCampaignCards product={current.product} actionFilter={actionFilter} onCounts={reportLaunchCounts} />
                  </div>
                )}
                {camps === null ? <div className="text-label text-faint">Loading campaigns…</div>
                  : camps.length === 0 ? <div className="text-label text-subtle">No campaigns for this product.</div>
                  : (() => {
                    return (
                      <>
                        <p className="text-label text-subtle mb-3">Keyword bids &amp; search terms to negate.</p>
                        <div className="flex flex-col gap-4">
                          {camps.filter(campVisible).length === 0 && (
                            <div className="text-label text-subtle px-2 py-3">
                              {/* Don't say "nothing to do" when the campaigns simply moved to the launch
                                  section above — that reads as a bug. */}
                              {launchCardsShown && camps.some(c => c.ageBucket === 'LOW_BUDGET') && !camps.some(c => c.ageBucket !== 'LOW_BUDGET')
                                ? 'Only low-budget campaigns here — they’re managed in the launch controller above.'
                                : actionFilter === 'done' ? 'Nothing applied in the last 3 days.'
                                : 'Nothing left to do — everything is either applied or holding.'}
                              {' '}<button onClick={() => setActionFilter('all')} className="text-blue-400 hover:underline">Show all</button>
                            </div>
                          )}
                          {(['SCALE', 'MARGIN', 'CUT'] as const).map(stype => {
                            const group = camps.filter(c => c.strategyType === stype && campVisible(c));
                            if (!group.length) return null;
                            const sm = STRATEGY_META[stype];
                            const groupSpend = group.reduce((s, c) => s + (c.recentDailySpend ?? 0), 0);
                            return (
                              <div key={stype} className="flex flex-col gap-1.5">
                                {/* H0 — strategic bucket */}
                                <div className={`flex items-baseline gap-2 pl-2 border-l-2 ${sm.border}`}>
                                  <span className={`text-body font-semibold ${sm.cls}`}>{sm.label}</span>
                                  <span className="text-label text-faint">{group.length} campaign{group.length > 1 ? 's' : ''} · {sm.desc} · spend {fM(groupSpend)}/day</span>
                                </div>
                          {group.map(c => {
                            const ckws = (kws ?? []).filter(k => k.campaignId === c.id && kwVisible(k)).sort((a, b) => Number(b.isAction) - Number(a.isAction) || b.priority - a.priority);
                            const actCount = ckws.filter(k => k.isAction).length;
                            const cNegCount = (negs ?? []).filter(n => n.campaignId === c.id).length;
                            const open = openCamp[c.id] ?? false;
                            return (
                              <div key={c.id} className="rounded-lg border border-border/70">
                                {/* H1 — campaign header (budget is in step 2; here it groups the keyword actions) */}
                                <div className="flex items-center gap-2 px-2 py-1.5">
                                  <button onClick={() => setOpenCamp(p => ({ ...p, [c.id]: !open }))} className="text-faint w-4 shrink-0" title={ckws.length ? 'keywords' : 'no keywords'}>{ckws.length ? (open ? '▾' : '▸') : '·'}</button>
                                  <div className="min-w-0 flex-1">
                                    <div className="text-body text-muted truncate" title={c.campaignName}>{c.campaignName}</div>
                                    <div className="text-label text-faint leading-snug">{c.needsStrategy && <button onClick={() => openManage(c)} className="text-amber-400 hover:underline mr-1" title="this campaign has no strategy — the coach can't manage it until you assign one">⚠ assign strategy ·</button>}{ckws.length ? `${ckws.length} kw${actCount ? `, ${actCount} to change` : ''}` : 'no keywords'}{cNegCount ? <span className="text-red-400">, {cNegCount} to negate</span> : ''}</div>
                                    {/* per-campaign net ROAS (GROSS_PROFIT/spend) by window — context for the keyword calls below */}
                                    <div className="text-label font-mono leading-snug mt-0.5" title="net ROAS = gross profit ÷ ad spend, by window">
                                      <span className="text-faint">net ROAS </span>
                                      <span className="text-faint">7d </span><RoasCell v={c.roas1w} />
                                      <span className="text-faint"> · 14d </span><RoasCell v={c.roasPrev1w} />
                                      <span className="text-faint"> · 28d </span><RoasCell v={c.roas4w} />
                                      <span className="text-faint"> · spend </span><span className="text-muted">{fM(c.recentDailySpend)}/day</span>
                                      {c.adsNet60d != null && <><span className="text-faint"> · net </span><span className={npCls(c.adsNet60d / 60)} title="ads net profit per day (60-day average, matching spend)">{fM(c.adsNet60d / 60)}/day</span></>}
                                    </div>
                                  </div>
                                  <div className="flex items-center gap-1 shrink-0 text-label">
                                    <AppliedDays sug={c.daysSinceSuggestion} chg={null} />
                                    <button onClick={() => openManage(c)} className="px-1.5 py-0.5 rounded border border-border text-muted hover:bg-white/5" title="manage — map / rename / pause">⋯</button>
                                  </div>
                                </div>
                                {/* H2 — keywords */}
                                {open && ckws.length > 0 && (
                                  <div className="border-t border-border/50 px-2 py-1 text-label">
                                    {ckws.map(k => {
                                      const d = kwDir(k);
                                      const kq = !!bidQueuedItem(k);
                                      const sq = !!stopQueuedItem(k);
                                      const kNegs = (negs ?? []).filter(n => n.keywordId === k.id);
                                      // Coacher suggested a change (raise/trim/probe) → its new bid pre-fills the input.
                                      const suggests = d.label !== 'hold' && k.newBid != null;
                                      return (
                                        <div key={k.id} className="border-t border-border/30 first:border-t-0 py-1.5">
                                          <div className="flex items-center gap-2">
                                            <span className={`font-medium ${d.cls} w-10 shrink-0`}>{d.label}</span>
                                            <span className="text-muted flex-1 min-w-0 truncate" title={k.targeting}>{k.targeting} <span className="text-faint">({k.matchType.toLowerCase()})</span>{kNegs.length > 0 && <span className="text-red-400"> · {kNegs.length} to negate</span>}</span>
                                            <AppliedDays sug={k.daysSinceSuggestion} chg={k.daysSinceChange} />
                                            {defenseUnderBid(k) && <span className="font-mono shrink-0 text-red-400" title={`bid is below 1.5× CPC ($${defenseMinBid(k)?.toFixed(2)}) — raise to own page 1 and make it costly for competitors`}>⚠ &lt;1.5×CPC</span>}
                                            {k.targetCpc != null && <span className="font-mono shrink-0 underline text-blue-400/80" title="plan-approved target CPC (the band the bid steers toward)">tgt ${k.targetCpc.toFixed(2)}</span>}
                                            {/* Manual bid override — editable on every row, even when the coacher holds. Pre-filled with
                                                the coacher's suggested bid if it proposed one, else the current bid. */}
                                            <span className="text-faint font-mono shrink-0" title="current bid">{k.currentBid != null ? `$${k.currentBid.toFixed(2)}` : '—'}</span>
                                            <span className="text-faint shrink-0">→ $</span>
                                            <input type="number" min={0} step={0.05}
                                              value={Number((kwBidValue(k) ?? 0).toFixed(2))}
                                              onChange={e => setKwBidDraft(p => ({ ...p, [k.id]: Math.max(0, Number(e.target.value) || 0) }))}
                                              title={suggests ? "coacher's suggested bid — edit to override" : 'set a manual bid'}
                                              className={`w-[4.5rem] font-mono rounded px-1.5 py-0.5 focus:outline-none focus:ring-1 focus:ring-blue-500/40 bg-surface/40 border ${suggests ? 'border-blue-500/40 text-blue-300' : 'border-border'}`} />
                                            <button onClick={() => toggleKwQ(k, c.campaignName)} title="queue this bid" className={`px-2 py-0.5 rounded border shrink-0 ${kq ? 'border-emerald-500/40 text-emerald-400' : 'border-border text-muted hover:bg-white/5'}`}>{kq ? '✓' : 'bid'}</button>
                                            <button onClick={() => toggleStopQ(k, c.campaignName)} title="stop (pause) this keyword/target so it stops spending" className={`px-2 py-0.5 rounded border shrink-0 ${sq ? 'border-emerald-500/40 text-emerald-400' : 'border-red-500/40 text-red-400 hover:bg-red-500/10'}`}>{sq ? '✓' : 'stop'}</button>
                                          </div>
                                          <div className="pl-12 pr-2 mt-0.5 leading-snug flex flex-wrap gap-x-3" title="clicks/day · CPC · net ROAS · units sold, by window">
                                            {([['7d', k.w1ClkDay, k.w1Cpc, k.w1Roas, k.w1Units], ['28d', k.w4ClkDay, k.w4Cpc, k.w4Roas, k.w4Units], ['peak', k.pkClkDay, k.pkCpc, k.pkRoas, k.pkUnits]] as [string, number | null, number | null, number | null, number | null][]).map(([label, cd, cpc, ro, u]) => (
                                              <span key={label}><span className="text-faint">{label} </span>{cd != null ? <span className="text-muted">{cd}/d</span> : <span className="text-faint">—</span>}{cpc != null ? <> · <span className="text-muted">${cpc.toFixed(2)}</span></> : ''}{ro != null ? <> · <span className={roasCls(ro)}>{ro.toFixed(2)}×</span></> : ''}{u != null && u > 0 ? <> · <span className="text-muted" title="units sold in this window">{u}u</span></> : ''}</span>
                                            ))}
                                          </div>
                                          <div className="text-faint pl-12 pr-2 leading-snug">{kwReason(k)}</div>
                                          {/* H3 — non-converting search terms to negate */}
                                          {kNegs.length > 0 && (
                                            <div className="pl-12 pr-2 mt-1 flex flex-col gap-1">
                                              {kNegs.map(n => {
                                                const nq = !!queuedItem(n.searchTerm, 'NEGATE_TERM', n.campaignName);
                                                const peak = n.peakConverts
                                                  ? <span className="text-amber-400">⚠ peak: {n.peakOrders} order{n.peakOrders === 1 ? '' : 's'} · <span className={npCls(n.peakNet)}>{fM(n.peakNet)}</span> net — converts at peak, consider keeping (seasonal)</span>
                                                  : (n.peakClicks ?? 0) > 0
                                                    ? <span className="text-faint">peak: 0 orders on {n.peakClicks} clicks — dead at peak too ✓</span>
                                                    : <span className="text-faint">no peak history</span>;
                                                return (
                                                  <div key={n.id} className={`flex items-start gap-2 border-l-2 pl-2 ${n.peakConverts ? 'border-amber-500/40' : 'border-red-500/30'}`}>
                                                    <span className={`font-medium w-12 shrink-0 ${n.peakConverts ? 'text-amber-400' : 'text-red-400'}`}>negate</span>
                                                    <div className="min-w-0 flex-1">
                                                      <div className="text-muted break-words" title={n.searchTerm}>“{n.searchTerm}”</div>
                                                      <div className="text-faint leading-snug">{n.reason}</div>
                                                      <div className="leading-snug">{peak}</div>
                                                    </div>
                                                    <div className="flex flex-col gap-1 shrink-0 items-end">
                                                      <button onClick={() => toggleNegQ(n, c.campaignType)} className={`px-2 py-0.5 rounded border ${nq ? 'border-emerald-500/40 text-emerald-400' : n.peakConverts ? 'border-amber-500/50 text-amber-400 hover:bg-amber-500/10' : 'border-red-500/40 text-red-400 hover:bg-red-500/10'}`}>{nq ? '✓' : 'negate'}</button>
                                                      {/* SP only — SB ads use creative ASINs, a Product-Ad row would be rejected */}
                                                      {c.campaignType !== 'SB' && n.wrongAsin && n.heroAsin && (() => { const hq = heroAdQueued(n); return (
                                                        <button onClick={() => toggleHeroAdQ(n, c.campaignType)} title={`add ${n.heroProductName} (${n.heroCvr}% CVR here) as a product ad in this ad group — shows the right colour instead of negating`} className={`px-2 py-0.5 rounded border whitespace-nowrap ${hq ? 'border-emerald-500/40 text-emerald-400' : 'border-blue-500/40 text-blue-400 hover:bg-blue-500/10'}`}>{hq ? '✓' : `+ ${n.heroProductName}`}</button>
                                                      ); })()}
                                                    </div>
                                                  </div>
                                                );
                                              })}
                                            </div>
                                          )}
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
                          })}
                        </div>
                        <p className="text-label text-subtle mt-3">Grouped by <span className="text-muted">SCALE / MARGIN / CUT</span>. Campaign = header (budgets are in step 2). Level 2 = keywords (why each changes or holds). Level 3 = <span className="text-red-400">search terms to negate</span>.</p>
                      </>
                    );
                  })()}
              </section>

              {/* Step 5 — Upload */}
              <section className="rounded-xl border border-border bg-card p-4">
                <div className="text-label font-medium text-muted mb-2">5 · Upload — export &amp; send to Amazon</div>
                <p className="text-label text-subtle mb-3">{doQueue.items.length} row{doQueue.items.length === 1 ? '' : 's'} queued (budgets + bids). Export the bulksheet and upload it in Amazon Ads.</p>
                <button onClick={() => onNav('do', famArg(current.product))}
                  className="text-label px-3 py-1.5 rounded-md border border-blue-500/40 text-blue-400 hover:bg-blue-500/10">
                  Export bulksheet →
                </button>
              </section>

            </div>
          )}
        </main>

      <div className="text-label text-subtle mt-4">
        Click a family in the step-1 table to manage it. Every ad campaign appears there: families by plan, plus <span className="text-muted">Unknown</span> (unmapped) and <span className="text-muted">Store</span> (cross-product). Budgets (step 2) are daily, split from your total by the waterfall; keywords &amp; negatives in step 4. Source: V_WEEKLY_RUN_* / V_BUDGET_STEP1_* (backend).
      </div>
      {manageCamp && <CampaignManageModal camp={manageCamp} onClose={() => setManageCamp(null)} />}
    </div>
  );
}

export default WeeklyRunPage;
