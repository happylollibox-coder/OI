import { useEffect, useMemo, useRef, useState } from 'react';
import { cubeLoadWithMeta } from '../hooks/useCubeData';
import { useDoQueue, findQueuedBid, type DoQueueItem } from '../hooks/useDoQueue';

// Weekly Run — "Launch exemption": the families that are SUPPOSED to lose money while the right bid
// is found, and the coach decisions that are blocked because of it.
// Spec: architecture/LAUNCH_EXEMPTION.md · view: V_LAUNCH_EXEMPTION · gate: V_ADS_COACH.scored_exempt
//
// ADVISORY + DISPLAY-ONLY. Launch membership, the exemption end date, the envelope verdict, the
// protected-winner flag, the trim order and every sentence shown here are decided in the VIEW.
// This file must never compare an age to a boundary, a spend to an envelope, or a ROAS to a bar.
//
// The BUDGET half stays advisory and unqueueable by design — the exemption exists to BLOCK budget
// loss-cuts on a launch family, so there is no budget action here to apply, and adding one would
// invert the panel's whole purpose. v27.63 (Ori: "add actions and apply all button to revuvals, low
// stock, launch exemption") wires only the BID LADDER, which is the one thing this panel proposes:
// trims toward the launch bid. Ori's rule for launch is "find the right bid, never loss-cut", and
// a trim toward a computed launch bid is exactly that search — not a cut.
//
// v27.59 — THE BID LADDER (Ori 2026-08-13). The exemption's one downward lever: a gentle bid search
// on the SHORT window (V_PEAK_WINDOW_RULE — 7 days off peak, 3 in peak), read from
// V_LAUNCH_BID_LADDER via cube/schema/LaunchBidLadder.js. GP-ROAS < 0.5 trims the bid 10%, 0.5–0.7
// trims 5%, 0.7–0.9 ("improving") and >= 0.9 ("profitable") do nothing. The band, the factor, the
// anchor, the per-format floor ($0.20 SP / $0.25 SB video / $0.10 SB collection), the proposed bid
// and the reason sentence are ALL decided in the view; this file prints them and picks a colour.
// No budget column and no park/stop verb exists here — everything the exemption blocks stays
// blocked.

type Row = {
  campaignId: string; campaignName: string; campaignType: string; family: string;
  currentBudget: number | null;
  familyFirstSale: string | null; familyAgeMonths: number | null; launchWindowDays: number | null;
  exemptUntil: string | null; exemptDaysLeft: number | null; exemptUntilSource: string | null;
  sanctionedDaily: number | null; sanctionedMonthly: number | null;
  sanctionedStopDate: string | null; sanctionedNote: string | null;
  familyDailySpend7d: number | null; familyCampaigns: number | null;
  envelopeOverByDaily: number | null; envelopeState: string; escalateToOri: boolean;
  settledSpend: number | null; settledGp: number | null; settledGpRoas: number | null;
  settledClicks: number | null; settledOrders: number | null; spend7d: number | null;
  evidenceDays: number | null; protectedWinner: boolean; envelopeTrimRank: number | null;
  inGraceWindow: boolean;
  blocksEnforced: string; blocksPending: string; allows: string; exemptReason: string;
  coachBudgetAction: string | null; coachBudgetExplanation: string | null;
};

// One row per campaign × keyword/target from V_LAUNCH_BID_LADDER. Every verdict field on this type
// is a value the VIEW decided — nothing here is recomputed.
type LadderRow = {
  rowKey: string; family: string; campaignId: string; campaignName: string; campaignType: string;
  targeting: string; matchType: string | null; keywordId: string; adGroupId: string;
  windowStart: string | null; windowEnd: string | null; judgedWindowDays: number | null;
  inPeak: boolean; occurrenceType: string | null; wDaysReason: string | null;
  d1Clicks: number | null; d1GpRoas: number | null; d1Spend: number | null;
  wClicks: number | null; wOrders: number | null; wSpend: number | null; wGpRoas: number | null;
  evidenceGrade: string | null;
  gpRoasBand: string; bandTrimPct: number | null;
  currentBid: number | null; launchBid: number | null; launchBidSource: string | null;
  anchorSource: string | null; bidFloor: number | null; bidFloorSource: string | null;
  proposedBid: number | null; aboveLaunchBid: boolean; runsToLaunchBid: number | null;
  ceilingStepBid: number | null; floorBinding: boolean;
  bidChangePct: number | null; bidCutDollars: number | null;
  ladderAction: string; isProposal: boolean;
  coachTargetAction: string | null; coachRecommendedBid: number | null; conflictsWithCoach: boolean;
  ladderReason: string;
};

const num = (v: unknown): number | null => (v == null || v === '' ? null : Number(v));
const str = (v: unknown): string | null => (v == null || v === '' ? null : String(v));
const bool = (v: unknown): boolean => v === true || v === 'true';
const money = (v: number | null, d = 2) => (v == null ? '—' : `$${v.toFixed(d)}`);

// Colour only. The action strings and their meanings are the view's; this map assigns no semantics
// that the view has not already decided.
const LADDER_CLS: Record<string, string> = {
  LAUNCH_BID_TRIM_10: 'text-amber-400',
  LAUNCH_BID_TRIM_5: 'text-amber-300',
  LAUNCH_BID_HOLD_IMPROVING: 'text-sky-300',
  LAUNCH_BID_HOLD_PROFITABLE: 'text-emerald-400',
  LAUNCH_BID_HOLD_AT_FLOOR: 'text-faint',
  LAUNCH_BID_HOLD_NO_EVIDENCE: 'text-faint',
};

// The set of budget verdicts the exemption exists to block. Used ONLY to decide whether to show the
// "blocked" chip — the blocking itself happens in V_ADS_COACH; this list mirrors blocksEnforced.
const CUTS = new Set(['CAMPAIGN_STOP', 'GUARDIAN_BUDGET_DECREASE', 'BLITZ_BUDGET_DECREASE',
  'GUARDIAN_BUDGET_CONTAIN', 'COOLDOWN_BUDGET_REDUCE', 'RESTORE_BUDGET_PRE_PEAK']);

// The settled record, in one cell — the evidence, never a verdict.
function Settled({ r }: { r: Row }) {
  if (!r.settledClicks) return <span className="text-faint">no settled clicks</span>;
  return (
    <span
      className="whitespace-nowrap"
      title={`${r.evidenceDays ?? 28} settled days (${r.campaignType === 'SB' ? 'SB: through today−14' : 'SP: through today−7'})`
        + ` · GP ${money(r.settledGp)} on ${money(r.settledSpend)} spend`}
    >
      {r.settledClicks}c · {money(r.settledSpend)} ·{' '}
      <span className={r.protectedWinner ? 'text-emerald-400' : 'text-muted'}>
        {r.settledGpRoas != null ? `${r.settledGpRoas.toFixed(2)}×` : '—'}
      </span>
      {r.settledOrders ? <span className="text-faint"> · {r.settledOrders} ord</span> : null}
    </span>
  );
}

// ── the DO queue (v27.63, Ori: "add actions and apply all button to revuvals, low stock, launch
// exemption") ────────────────────────────────────────────────────────────────────────────────────
// `is_proposal` is the view's own column and the ONLY test of actionability here — this file never
// re-derives the band rule. Direction is likewise fixed upstream: the ladder only ever trims (the
// proposed bid is never above the current one), verified live at 0 raises across 35 proposals, so
// REDUCE_BID is a label, not a comparison React makes.
// A proposal with no keyword_id / ad_group_id cannot become a bulksheet row Amazon will accept, so
// it is excluded from apply-all and shown as such rather than queued into a silent rejection.
const ladderReady = (r: LadderRow) =>
  r.isProposal && r.proposedBid != null && !!r.keywordId && !!r.adGroupId;

// Ours = a trim to exactly this row's proposed bid — the ONLY thing bulk-unapply may sweep.
// DISPLAY is wider (canonical queue key, Ori 2026-08-17: "if i approve an action in section or
// snapshot, visual should show both approve"): the row's ✓ comes from findQueuedBid on keyword_id,
// so a bid queued from ANY surface at ANY value shows as queued here, and the row's own click
// removes it whatever queued it. Only the bulk button stays value-exact, so it can never sweep
// another panel's differently-valued bid off the queue.
const ourLadderItem = (items: DoQueueItem[], r: LadderRow) =>
  items.find(i => i.keyword_id === r.keywordId && i.action === 'REDUCE_BID'
    && i.recommended_bid === r.proposedBid);

const ladderQueueItem = (r: LadderRow): Omit<DoQueueItem, 'id' | 'addedAt'> => ({
  search_term: r.targeting, action: 'REDUCE_BID',
  campaign: r.campaignName, campaign_id: r.campaignId, ad_group_id: r.adGroupId,
  targeting: r.targeting, keyword_id: r.keywordId, match_type: (r.matchType ?? '').toUpperCase(),
  target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0,
  current_bid: r.currentBid, recommended_bid: r.proposedBid,
  campaign_type: r.campaignType === 'SB' ? 'SPONSORED_BRANDS' : 'SPONSORED_PRODUCTS',
  product: 'Keyword', spend: 0, orders: 0, cpc: 0, conv_rate: 0, source: 'COACH',
});

// The bid ladder, one target per row. Format mirrors the other Weekly Run panels
// (item — campaign ▸ target | now $ | last day | window | action | → $ | why).
function BidLadderTable({ rows }: { rows: LadderRow[] }) {
  const doQueue = useDoQueue();
  // Starts expanded only when it holds open work: at least one queueable trim whose keyword is not
  // already queued from ANY surface (canonical key). Initial state only — the user's click rules
  // after mount; the queue changing later never re-collapses an open table.
  const [open, setOpen] = useState(
    () => rows.some(r => ladderReady(r) && !findQueuedBid(doQueue.items, r.keywordId)));
  const head = rows[0];
  const props = rows.filter(r => r.isProposal);
  const cutTotal = props.reduce((s, r) => s + (r.bidCutDollars ?? 0), 0);
  const wLabel = `${head.judgedWindowDays ?? 7}d`;

  return (
    <div className="mt-1">
      <button className="text-label flex items-center gap-1" onClick={() => setOpen(o => !o)}>
        <span className="text-faint">{open ? '▾' : '▸'}</span>
        <span className="text-muted">bid ladder</span>
        <span className="text-faint">
          {' '}— {props.length} of {rows.length} target{rows.length === 1 ? '' : 's'} propose a trim
          {props.length ? ` (${money(cutTotal)} of bid off in total)` : ''}
          {' '}· judged on the last {wLabel}{head.inPeak ? ` (peak${head.occurrenceType ? ` — ${head.occurrenceType}` : ''})` : ''}
          {head.windowStart ? `, ${head.windowStart}..${head.windowEnd}` : ''}
        </span>
      </button>

      {open && (
        <div className="mt-1 overflow-x-auto">
          <table className="text-label font-mono border-collapse">
            <thead>
              <tr className="text-faint text-right">
                <th className="font-normal text-left px-2 py-0.5">item — campaign ▸ target</th>
                <th className="font-normal px-2" title="the current keyword bid">now $</th>
                <th className="font-normal px-2" title="last complete day: clicks · GP-ROAS (gross profit ÷ ad spend, tier COGS charged — 1.00× is breakeven AFTER product cost). Published, not judged.">last day</th>
                <th className="font-normal px-2" title={head.wDaysReason ?? 'the judged window: clicks · GP-ROAS. The band is taken on THIS window.'}>{wLabel} window</th>
                <th className="font-normal px-2 text-left" title="which GP-ROAS band the window lands in: under 0.5 → −10%, 0.5–0.7 → −5%, 0.7–0.9 improving, ≥0.9 profitable">band</th>
                <th className="font-normal px-2 text-left" title="the launch bid V_ADS_COACH computed for this target — the destination the ladder walks toward, never recomputed here">launch bid</th>
                <th className="font-normal px-2 text-left">action</th>
                <th className="font-normal px-2" title="the proposed new bid — never below this row's platform/house floor, never above the current bid">→ $</th>
                <th className="font-normal px-2 text-left">why</th>
              </tr>
            </thead>
            <tbody>
              {rows.map(r => (
                <tr key={r.rowKey} className="text-right border-t border-border/30">
                  <td className="text-left px-2 py-0.5 whitespace-nowrap">
                    <span className="text-faint">{r.campaignName} ▸ </span>
                    <span className="text-muted">{r.targeting}</span>
                    <span className="text-faint"> ({(r.matchType ?? '').toLowerCase()}) · {r.campaignType}</span>
                  </td>
                  <td className="px-2 text-muted whitespace-nowrap">
                    {money(r.currentBid)}
                    <span className="text-faint" title={`${r.bidFloorSource ?? ''} floor`}> · floor {money(r.bidFloor)}</span>
                  </td>
                  <td className="px-2 text-muted whitespace-nowrap">
                    {r.d1Clicks ?? 0}c{r.d1GpRoas != null ? ` ${r.d1GpRoas.toFixed(2)}×` : ' —'}
                  </td>
                  <td className="px-2 text-muted whitespace-nowrap" title={`${money(r.wSpend)} spend · ${r.wOrders ?? 0} orders`}>
                    {r.wClicks ?? 0}c{r.wGpRoas != null ? ` ${r.wGpRoas.toFixed(2)}×` : ' —'}
                    {r.evidenceGrade === 'THIN' && <span className="text-faint" title="under 3 clicks in the window — legible as a thin verdict; it changes no action"> thin</span>}
                  </td>
                  <td className="px-2 text-left text-faint whitespace-nowrap">
                    {r.gpRoasBand.replace(/_/g, ' ').toLowerCase()}
                    {r.bandTrimPct ? <span className="text-muted"> · −{r.bandTrimPct}%</span> : null}
                  </td>
                  <td className="px-2 text-left whitespace-nowrap" title={r.anchorSource ?? undefined}>
                    <span className="text-faint">{money(r.launchBid)}</span>
                    {r.launchBidSource && <span className="text-faint"> ({r.launchBidSource})</span>}
                    {r.aboveLaunchBid && (
                      <span className="text-amber-400" title={`the bid is above the sanctioned launch bid; the ladder walks it down at the band's step instead of jumping (one step would be ${money(r.ceilingStepBid)})`}>
                        {' '}· {r.runsToLaunchBid ?? '—'} runs
                      </span>
                    )}
                  </td>
                  <td className={`px-2 text-left whitespace-nowrap ${LADDER_CLS[r.ladderAction] ?? 'text-muted'}`}>
                    {r.ladderAction.replace('LAUNCH_BID_', '').replace(/_/g, ' ').toLowerCase()}
                  </td>
                  <td className="px-2 whitespace-nowrap">
                    {r.proposedBid == null ? <span className="text-faint">—</span> : (() => {
                      // Canonical queued-state: keyed on keyword_id, any bid action, any value —
                      // an approval made in another view must render as approved here too.
                      const queued = findQueuedBid(doQueue.items, r.keywordId);
                      const foreignAt = queued && queued.recommended_bid != null && r.proposedBid != null
                        && Math.abs(queued.recommended_bid - r.proposedBid) > 0.005
                        ? money(queued.recommended_bid) : null;
                      const pct = <>
                        <span className="text-faint"> {r.bidChangePct != null ? `${r.bidChangePct.toFixed(1)}%` : ''}</span>
                        {r.floorBinding && <span className="text-faint" title="the floor held the trim up — the realised trim is smaller than the band"> ⌊</span>}
                      </>;
                      if (!queued && !ladderReady(r)) return <><span className="text-faint" title={r.isProposal ? 'no keyword/ad-group id on this row — it cannot become a bulksheet row, so it is not queueable' : undefined}>{money(r.proposedBid)}</span>{pct}</>;
                      return <>
                        <button
                          onClick={() => { if (queued) doQueue.removeItem(queued.id); else doQueue.addItem(ladderQueueItem(r)); }}
                          title={queued
                            ? foreignAt
                              ? `queued from another view at ${foreignAt} — click to remove it`
                              : 'queued — click to remove'
                            : 'click to queue this trim'}
                          className={queued ? 'text-emerald-300' : 'text-amber-300 hover:text-amber-200'}>
                          {money(r.proposedBid)}{queued ? ` ✓${foreignAt ? ` at ${foreignAt}` : ''}` : ''}
                        </button>{pct}
                      </>;
                    })()}
                  </td>
                  <td className="px-2 text-left text-faint whitespace-normal max-w-[40rem]">
                    {r.ladderReason}
                    {r.conflictsWithCoach && (
                      <span className="text-subtle" title="the coach's own standing bid decision for this target — published, never overridden by the ladder">
                        {' '}· coach says {r.coachTargetAction} {money(r.coachRecommendedBid)}
                      </span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

export function LaunchExemptionPhase({ defaultOpen }: { defaultOpen?: boolean } = {}) {
  // defaultOpen (Ori 2026-08-17: "when there is an open action hierarchy should be Expanded else
  // collapse by default"): null until the user clicks, so a defaultOpen that arrives or flips
  // later can never override an explicit close — the user's click is final. The lazy fetch gates
  // below key off the DERIVED `open`, so defaultOpen=true fires the first-expand fetch exactly as
  // a click would.
  const [openState, setOpenState] = useState<boolean | null>(null);
  const open = openState ?? defaultOpen ?? false;
  const [rows, setRows] = useState<Row[] | null>(null);
  const [ladder, setLadder] = useState<LadderRow[]>([]);
  const [failed, setFailed] = useState(false);
  const doQueue = useDoQueue();

  // LAZY SECTION (WEEKLY_RUN_UX.md: sections fetch ONLY on first expand). Both effects below —
  // the ladder and the exemption rows — gate on the same first expand, one ref each; on mount they
  // were 2 of the ~17 ceiling-view queries the page fired at open (40–120s each cold — the "why
  // is it not loading" incident).
  // The ladder is a SEPARATE, non-fatal fetch: a stale LaunchBidLadder cube must never take the
  // exemption panel down with it (the exemption is the thing that blocks the cuts).
  const ladderFetchedRef = useRef(false);
  useEffect(() => {
    if (!open || ladderFetchedRef.current) return;
    ladderFetchedRef.current = true;
    let alive = true;
    const L = (k: string) => `LaunchBidLadder.${k}`;
    cubeLoadWithMeta({
      dimensions: [
        'rowKey', 'family', 'campaignId', 'campaignName', 'campaignType', 'targeting', 'matchType',
        'keywordId', 'adGroupId',
        'windowStart', 'windowEnd', 'judgedWindowDays', 'inPeak', 'occurrenceType', 'wDaysReason',
        'd1Clicks', 'd1GpRoas', 'd1Spend',
        'wClicks', 'wOrders', 'wSpend', 'wGpRoas', 'evidenceGrade',
        'gpRoasBand', 'bandTrimPct',
        'currentBid', 'launchBid', 'launchBidSource', 'anchorSource',
        'bidFloor', 'bidFloorSource', 'proposedBid',
        'aboveLaunchBid', 'runsToLaunchBid', 'ceilingStepBid', 'floorBinding',
        'bidChangePct', 'bidCutDollars', 'ladderAction', 'isProposal',
        'coachTargetAction', 'coachRecommendedBid', 'conflictsWithCoach', 'ladderReason',
      ].map(L),
    }).then(res => {
      if (!alive || res.error) return;
      setLadder((res.data as Record<string, unknown>[]).map(r => ({
        rowKey: String(r[L('rowKey')] ?? ''),
        family: String(r[L('family')] ?? ''),
        campaignId: String(r[L('campaignId')] ?? ''),
        campaignName: String(r[L('campaignName')] ?? ''),
        campaignType: String(r[L('campaignType')] ?? ''),
        targeting: String(r[L('targeting')] ?? ''),
        matchType: str(r[L('matchType')]),
        keywordId: String(r[L('keywordId')] ?? ''), adGroupId: String(r[L('adGroupId')] ?? ''),
        windowStart: str(r[L('windowStart')]), windowEnd: str(r[L('windowEnd')]),
        judgedWindowDays: num(r[L('judgedWindowDays')]),
        inPeak: bool(r[L('inPeak')]), occurrenceType: str(r[L('occurrenceType')]),
        wDaysReason: str(r[L('wDaysReason')]),
        d1Clicks: num(r[L('d1Clicks')]), d1GpRoas: num(r[L('d1GpRoas')]), d1Spend: num(r[L('d1Spend')]),
        wClicks: num(r[L('wClicks')]), wOrders: num(r[L('wOrders')]),
        wSpend: num(r[L('wSpend')]), wGpRoas: num(r[L('wGpRoas')]),
        evidenceGrade: str(r[L('evidenceGrade')]),
        gpRoasBand: String(r[L('gpRoasBand')] ?? ''), bandTrimPct: num(r[L('bandTrimPct')]),
        currentBid: num(r[L('currentBid')]), launchBid: num(r[L('launchBid')]),
        launchBidSource: str(r[L('launchBidSource')]), anchorSource: str(r[L('anchorSource')]),
        bidFloor: num(r[L('bidFloor')]), bidFloorSource: str(r[L('bidFloorSource')]),
        proposedBid: num(r[L('proposedBid')]),
        aboveLaunchBid: bool(r[L('aboveLaunchBid')]), runsToLaunchBid: num(r[L('runsToLaunchBid')]),
        ceilingStepBid: num(r[L('ceilingStepBid')]), floorBinding: bool(r[L('floorBinding')]),
        bidChangePct: num(r[L('bidChangePct')]), bidCutDollars: num(r[L('bidCutDollars')]),
        ladderAction: String(r[L('ladderAction')] ?? ''), isProposal: bool(r[L('isProposal')]),
        coachTargetAction: str(r[L('coachTargetAction')]),
        coachRecommendedBid: num(r[L('coachRecommendedBid')]),
        conflictsWithCoach: bool(r[L('conflictsWithCoach')]),
        ladderReason: String(r[L('ladderReason')] ?? ''),
      })));
    }).catch(e => {
      console.error('[launch-bid-ladder] fetch failed:', e);
    });
    return () => { alive = false; };
  }, [open]);

  // Lazy gate #2 — same first-expand rule as the ladder above (WEEKLY_RUN_UX.md).
  const fetchedRef = useRef(false);
  useEffect(() => {
    if (!open || fetchedRef.current) return;
    fetchedRef.current = true;
    let alive = true;
    cubeLoadWithMeta({
      dimensions: [
        'LaunchExemption.campaignId', 'LaunchExemption.campaignName', 'LaunchExemption.campaignType',
        'LaunchExemption.family', 'LaunchExemption.currentBudget',
        'LaunchExemption.familyFirstSale', 'LaunchExemption.familyAgeMonths', 'LaunchExemption.launchWindowDays',
        'LaunchExemption.exemptUntil', 'LaunchExemption.exemptDaysLeft', 'LaunchExemption.exemptUntilSource',
        'LaunchExemption.sanctionedDaily', 'LaunchExemption.sanctionedMonthly',
        'LaunchExemption.sanctionedStopDate', 'LaunchExemption.sanctionedNote',
        'LaunchExemption.familyDailySpend7d', 'LaunchExemption.familyCampaigns',
        'LaunchExemption.envelopeOverByDaily', 'LaunchExemption.envelopeState', 'LaunchExemption.escalateToOri',
        'LaunchExemption.settledSpend', 'LaunchExemption.settledGp', 'LaunchExemption.settledGpRoas',
        'LaunchExemption.settledClicks', 'LaunchExemption.settledOrders', 'LaunchExemption.spend7d',
        'LaunchExemption.evidenceDays', 'LaunchExemption.protectedWinner', 'LaunchExemption.envelopeTrimRank',
        'LaunchExemption.inGraceWindow',
        'LaunchExemption.blocksEnforced', 'LaunchExemption.blocksPending', 'LaunchExemption.allows',
        'LaunchExemption.exemptReason',
        'LaunchExemption.coachBudgetAction', 'LaunchExemption.coachBudgetExplanation',
      ],
    }).then(res => {
      if (!alive) return;
      // A failed/stale cube returns {data: [], error}. Without this the panel would render its empty
      // state and claim no family is in launch phase, which is a lie.
      if (res.error) { setFailed(true); return; }
      setRows((res.data as Record<string, unknown>[]).map(r => ({
        campaignId: String(r['LaunchExemption.campaignId'] ?? ''),
        campaignName: String(r['LaunchExemption.campaignName'] ?? ''),
        campaignType: String(r['LaunchExemption.campaignType'] ?? ''),
        family: String(r['LaunchExemption.family'] ?? ''),
        currentBudget: num(r['LaunchExemption.currentBudget']),
        familyFirstSale: str(r['LaunchExemption.familyFirstSale']),
        familyAgeMonths: num(r['LaunchExemption.familyAgeMonths']),
        launchWindowDays: num(r['LaunchExemption.launchWindowDays']),
        exemptUntil: str(r['LaunchExemption.exemptUntil']),
        exemptDaysLeft: num(r['LaunchExemption.exemptDaysLeft']),
        exemptUntilSource: str(r['LaunchExemption.exemptUntilSource']),
        sanctionedDaily: num(r['LaunchExemption.sanctionedDaily']),
        sanctionedMonthly: num(r['LaunchExemption.sanctionedMonthly']),
        sanctionedStopDate: str(r['LaunchExemption.sanctionedStopDate']),
        sanctionedNote: str(r['LaunchExemption.sanctionedNote']),
        familyDailySpend7d: num(r['LaunchExemption.familyDailySpend7d']),
        familyCampaigns: num(r['LaunchExemption.familyCampaigns']),
        envelopeOverByDaily: num(r['LaunchExemption.envelopeOverByDaily']),
        envelopeState: String(r['LaunchExemption.envelopeState'] ?? ''),
        escalateToOri: bool(r['LaunchExemption.escalateToOri']),
        settledSpend: num(r['LaunchExemption.settledSpend']), settledGp: num(r['LaunchExemption.settledGp']),
        settledGpRoas: num(r['LaunchExemption.settledGpRoas']),
        settledClicks: num(r['LaunchExemption.settledClicks']), settledOrders: num(r['LaunchExemption.settledOrders']),
        spend7d: num(r['LaunchExemption.spend7d']), evidenceDays: num(r['LaunchExemption.evidenceDays']),
        protectedWinner: bool(r['LaunchExemption.protectedWinner']),
        envelopeTrimRank: num(r['LaunchExemption.envelopeTrimRank']),
        inGraceWindow: bool(r['LaunchExemption.inGraceWindow']),
        blocksEnforced: String(r['LaunchExemption.blocksEnforced'] ?? ''),
        blocksPending: String(r['LaunchExemption.blocksPending'] ?? ''),
        allows: String(r['LaunchExemption.allows'] ?? ''),
        exemptReason: String(r['LaunchExemption.exemptReason'] ?? ''),
        coachBudgetAction: str(r['LaunchExemption.coachBudgetAction']),
        coachBudgetExplanation: str(r['LaunchExemption.coachBudgetExplanation']),
      })));
    }).catch(e => {
      // Stale cube schema / missing dimension / cube down — degrade to an empty state.
      // Weekly Run must never fail to render because this panel has no data.
      console.error('[launch-exemption] fetch failed:', e);
      if (alive) setFailed(true);
    });
    return () => { alive = false; };
  }, [open]);

  // Grouping is presentation, not logic: the view already stamps every row with its family's
  // verdicts, so the group header just reads them off the first row of the group.
  const families = useMemo(() => {
    const byFam = new Map<string, Row[]>();
    for (const r of rows ?? []) {
      const list = byFam.get(r.family) ?? [];
      list.push(r);
      byFam.set(r.family, list);
    }
    const ladderByFam = new Map<string, LadderRow[]>();
    for (const r of ladder) {
      const list = ladderByFam.get(r.family) ?? [];
      list.push(r);
      ladderByFam.set(r.family, list);
    }
    return [...byFam.entries()]
      .map(([family, list]) => ({
        family,
        head: list[0],
        camps: [...list].sort((a, b) => (a.envelopeTrimRank ?? 0) - (b.envelopeTrimRank ?? 0)),
        blocked: list.filter(r => r.coachBudgetAction && CUTS.has(r.coachBudgetAction)).length,
        held: list.filter(r => r.coachBudgetAction === 'LAUNCH_EXEMPT_HOLD').length,
        // ordering is presentation: proposals first, then by the money actually moving
        ladder: [...(ladderByFam.get(family) ?? [])].sort((a, b) =>
          Number(b.isProposal) - Number(a.isProposal) || (b.wSpend ?? 0) - (a.wSpend ?? 0)),
      }))
      .sort((a, b) => (a.head.familyAgeMonths ?? 0) - (b.head.familyAgeMonths ?? 0));
  }, [rows, ladder]);

  const totals = useMemo(() => ({
    camps: (rows ?? []).length,
    fams: families.length,
    protectedNow: families.reduce((s, f) => s + f.held + f.blocked, 0),
    overEnvelope: families.filter(f => f.head.envelopeState === 'OVER_ENVELOPE').length,
    ladderProps: ladder.filter(r => r.isProposal).length,
  }), [rows, families, ladder]);

  // Section-level apply-all over EVERY family's ladder. One memoised list feeds both the count and
  // the click, so the number on the button can never disagree with what it queues. A row whose
  // keyword is already queued — from ANY surface, at ANY value — counts as DONE, not skipped: it
  // leaves `applicable` but stays in `eligible`, so "✓ applied" means every trim is queued
  // somewhere, not that this panel queued them all.
  const eligible = useMemo(() => ladder.filter(ladderReady), [ladder]);
  const applicable = useMemo(
    () => eligible.filter(r => !findQueuedBid(doQueue.items, r.keywordId)),
    [eligible, doQueue.items]);
  const nSug = applicable.length;
  const nDone = eligible.length - nSug;
  const allApplied = eligible.length > 0 && nSug === 0;
  // Bulk unapply stays value-exact (ourLadderItem): it removes only what THIS panel would queue;
  // a foreign-valued bid on the same keyword is removed on its own row, never swept from here.
  const applyAll = () => {
    if (allApplied) eligible.forEach(r => { const it = ourLadderItem(doQueue.items, r); if (it) doQueue.removeItem(it.id); });
    else applicable.forEach(r => doQueue.addItem(ladderQueueItem(r)));
  };

  const headline = failed
    ? '— unavailable'
    : !rows
    // Deliberate ref read in render (pre-dates the lint rule): a section collapsed while its first
    // fetch is still in flight must keep saying "loading…", not lie with "expand to load".
    // eslint-disable-next-line react-hooks/refs
    ? (open || fetchedRef.current) ? '— loading…' : '— expand to load'
    : totals.camps === 0
    ? '— no family is in launch phase right now'
    : `— ${totals.fams} launch famil${totals.fams === 1 ? 'y' : 'ies'} · ${totals.camps} campaigns protected from budget loss-cuts`
      + (totals.overEnvelope ? ` · ${totals.overEnvelope} over sanctioned envelope` : '')
      + (totals.ladderProps ? ` · ${totals.ladderProps} bid trims proposed` : '');

  return (
    <div className="mb-3 rounded-md border border-border bg-surface/30 px-3 py-2">
      <div className="flex items-center gap-1">
        <button className="text-label flex items-center gap-1 flex-1 min-w-0" onClick={() => setOpenState(!open)}>
          <span className="text-faint">{open ? '▾' : '▸'}</span>
          <span className="font-medium text-sky-300">Launch exemption</span>
          <span className="text-faint truncate">
            {headline}
            {' '}· a launch family is supposed to lose money while the right bid is found · you decide
          </span>
        </button>
        {rows && eligible.length > 0 && (
          <button onClick={applyAll}
            title={allApplied
              ? 'unapply the launch bid trims this panel queued — a bid queued from another view at a different value is removed on its own row, not here'
              : `queue the ${nSug} bid trims toward the launch bid not yet queued`
                + (nDone ? ` (${nDone} already queued from another view — counted as done)` : '')
                + ' (budgets are never queued here — the exemption exists to protect them)'}
            className={`text-label px-2 py-0.5 rounded border shrink-0 ${allApplied ? 'border-emerald-500/40 text-emerald-300' : 'border-sky-500/40 text-sky-300 hover:bg-sky-500/10'}`}>
            {allApplied ? `✓ applied ${eligible.length}` : `apply all ${nSug}`}
          </button>
        )}
      </div>

      {open && failed && (
        <div className="mt-2 text-label text-faint">
          Launch-exemption data unavailable — the LaunchExemption cube isn't answering (stale schema or cube restart pending).
          The gate itself lives in V_ADS_COACH and keeps working regardless of this panel.
        </div>
      )}

      {open && rows && rows.length === 0 && (
        <div className="mt-2 text-label text-faint">
          No family is inside its launch window today — every family is older than its launch boundary, or its
          sanctioned stop date has passed. Normal coaching applies everywhere.
        </div>
      )}

      {open && rows && rows.length > 0 && (
        <div className="mt-2 flex flex-col gap-4">
          {families.map(f => (
            <div key={f.family} className="flex flex-col gap-1">
              {/* ── family header: the licence, its ceiling and its end date ── */}
              <div className="text-label">
                <span className="text-muted font-medium">{f.family}</span>
                <span className="text-faint">
                  {' '}· {f.head.familyAgeMonths ?? '—'} months old (first sale {f.head.familyFirstSale ?? '—'})
                  {' '}· {f.head.familyCampaigns ?? f.camps.length} campaigns
                </span>
              </div>
              <div className="text-label text-subtle whitespace-normal max-w-[60rem]">{f.head.exemptReason}</div>
              <div className="text-label">
                <span className="text-faint">exempt until </span>
                <span className="text-sky-300">{f.head.exemptUntil ?? '—'}</span>
                <span className="text-faint">
                  {' '}({f.head.exemptDaysLeft ?? '—'} days left,{' '}
                  {f.head.exemptUntilSource === 'SANCTIONED_STOP_DATE'
                    ? 'your dated stop gate'
                    : `family-age boundary, ${f.head.launchWindowDays ?? 183}d from first sale`})
                </span>
                {f.head.sanctionedDaily != null && (
                  <>
                    <span className="text-faint"> · sanctioned </span>
                    <span className="text-muted">{money(f.head.sanctionedDaily, 0)}/day</span>
                    <span className="text-faint"> (≈{money(f.head.sanctionedMonthly, 0)}/month) · actually spending </span>
                    <span className={f.head.envelopeState === 'OVER_ENVELOPE' ? 'text-amber-400' : 'text-emerald-400'}>
                      {money(f.head.familyDailySpend7d, 2)}/day
                    </span>
                    {f.head.envelopeState === 'OVER_ENVELOPE' && (
                      <span className="text-amber-400"> · over by {money(f.head.envelopeOverByDaily, 2)}/day</span>
                    )}
                  </>
                )}
              </div>
              {f.head.escalateToOri && (
                <div className="text-label text-amber-400/90 whitespace-normal max-w-[60rem]">
                  Over the envelope you sanctioned. Taking money out is your budget decision — the order below is
                  worst settled record first, protected winners last. The coach is NOT allowed to make that cut on
                  a ROAS verdict.
                </div>
              )}

              <div className="overflow-x-auto">
                <table className="text-label font-mono border-collapse">
                  <thead>
                    <tr className="text-faint text-right">
                      <th className="font-normal text-left px-2 py-0.5">campaign — type</th>
                      <th className="font-normal px-2 text-left" title="the campaign's current daily budget">budget</th>
                      <th className="font-normal px-2 text-left" title="spend over the last 7 complete days">spend 7d</th>
                      <th className="font-normal px-2 text-left" title="settled record: clicks · spend · GP-ROAS (tier COGS charged) · orders. Settled = old enough that the sales are fully attributed (SP D+7, SB D+14).">settled record</th>
                      <th className="font-normal px-2 text-left" title="the coach's standing budget decision from the last coach run. LAUNCH_EXEMPT_HOLD = the exemption blocked a cut.">coach says</th>
                      <th className="font-normal px-2 text-left" title="if money must come out of this family, this is the order: worst settled record first, protected winners last">trim order</th>
                    </tr>
                  </thead>
                  <tbody>
                    {f.camps.map(r => (
                      <tr key={r.campaignId} className="border-t border-border/40">
                        <td className="text-left px-2 py-0.5 whitespace-nowrap">
                          <span className="text-muted">{r.campaignName || r.campaignId}</span>
                          <span className="text-faint"> · {r.campaignType}</span>
                          {r.inGraceWindow && (
                            <span className="text-faint" title="first 14 days — a broken launch (>$25 spent, ZERO orders) can still be contained at $10/day; that is a waste trim, not a ROAS cut"> · grace</span>
                          )}
                        </td>
                        <td className="px-2 text-left text-muted whitespace-nowrap">{money(r.currentBudget, 0)}</td>
                        <td className="px-2 text-left text-faint whitespace-nowrap">{money(r.spend7d, 0)}</td>
                        <td className="px-2 text-left"><Settled r={r} /></td>
                        <td className="px-2 text-left whitespace-nowrap" title={r.coachBudgetExplanation ?? undefined}>
                          {r.coachBudgetAction === 'LAUNCH_EXEMPT_HOLD'
                            ? <span className="text-sky-300">held by exemption</span>
                            : r.coachBudgetAction && CUTS.has(r.coachBudgetAction)
                            ? <span className="text-amber-400">{r.coachBudgetAction} — blocked</span>
                            : <span className="text-faint">{r.coachBudgetAction ?? 'no budget decision'}</span>}
                        </td>
                        <td className="px-2 text-left whitespace-nowrap">
                          {r.protectedWinner
                            ? <span className="text-emerald-400" title="settled winner — never pulled down">protected</span>
                            : <span className="text-faint">#{r.envelopeTrimRank ?? '—'}</span>}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              {f.ladder.length > 0 && <BidLadderTable rows={f.ladder} />}
            </div>
          ))}

          {/* ── the policy, in the view's own words ── */}
          <div className="border-t border-border/40 pt-2 flex flex-col gap-1 text-label">
            <div className="whitespace-normal max-w-[60rem]">
              <span className="text-muted">Blocked: </span>
              <span className="text-faint">{rows[0].blocksEnforced}</span>
            </div>
            <div className="whitespace-normal max-w-[60rem]">
              <span className="text-muted">Still allowed: </span>
              <span className="text-faint">{rows[0].allows}</span>
            </div>
            <div className="whitespace-normal max-w-[60rem]">
              <span className="text-muted">Declared but not wired: </span>
              <span className="text-faint">{rows[0].blocksPending}</span>
            </div>
          </div>

          <div className="text-label text-subtle">
            Queued bid trims go to the DO queue only — nothing uploads until you export the bulksheet, and the
            export-time preflight gate re-checks every row. Budgets stay unqueueable here by design. Source:
            V_LAUNCH_EXEMPTION (backend); membership, the end date, the envelope verdict and the trim order are
            all decided there. The exemption's one real effect is that a blocked budget cut never reaches the
            bulksheet.
          </div>
        </div>
      )}
    </div>
  );
}

export default LaunchExemptionPhase;
