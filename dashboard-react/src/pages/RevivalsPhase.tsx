import { Fragment, useEffect, useMemo, useRef, useState } from 'react';
import { cubeLoadWithMeta } from '../hooks/useCubeData';
import { findQueuedBid, useDoQueue } from '../hooks/useDoQueue';

// Weekly Run — "Revivals": parked keywords whose SETTLED record now overturns the park.
// V_PARK_REVERDICT has been running since v27.48 but had no surface; these rows were sitting
// where nobody looks. Spec: architecture/SEASON_CONTEXT_LEDGER.md §7 (doctrine) and §7.11 (this).
//
// Every reverdict, revive bid, guard flag and reason sentence is decided in the view — this file
// must never compare a ROAS to a bar, derive a bid, or re-word a verdict.
//
// v27.63 (Ori 2026-08-13: "add actions and apply all button to revuvals, low stock, launch
// exemption"). The panel now WRITES to the DO queue. It used to be display-only on the reasoning
// that "reviving is Ori's decision" — but a decision you have to retype by hand is not a decision
// surface, it is a reading exercise, and these rows sat unread for exactly that reason. The
// judgement stays Ori's: nothing queues itself, apply-all is one deliberate click, and the two
// judgement-call classes below are deliberately EXCLUDED from it.
//   · manual_parked_recent  — Ori's own park, 14-day hold. The engines defer both directions, so a
//                             bulk button must not step on it. Still hand-queueable, one row at a time.
//   · season_relax_applied  — the row's OWN settled record loses money (0.80–1.00×) and it clears
//                             the bar only on a prior-season WIN. The view calls this "Ori's
//                             read-this-first flag"; read-this-first and apply-all are opposites.
// CONFIRM_PARK and PENDING_SETTLE carry NO instruction and can never enter the queue by any path.
//
//   REVIVE         — settled record clears the bar; the calibrated revive bid is ready.
//   CONFIRM_PARK   — re-judged at settle and the park stands (secondary, so a park is knowable).
//   PENDING_SETTLE — not enough settled evidence yet; re-judged on settle_due (secondary).
//   INSUFFICIENT   — the normal candidate queue (~450 rows); deliberately NOT surfaced, it is the
//                    null state, not news.

type Row = {
  rowId: string; campaignId: string; campaignName: string; family: string | null;
  keywordId: string; adGroupId: string; keywordText: string; matchType: string; channel: string; isPt: boolean;
  currentBid: number | null; preParkBid: number | null;
  parkDate: string | null; parkSource: string | null; parkEra: string | null; nParkEvents: number | null;
  settleDue: string | null; settledThrough: string | null;
  s90Clk: number | null; s90Sp: number | null; s90Ord: number | null; s90Gp: number | null;
  s90GpRoas: number | null; s90Cpc: number | null; lifeSettledClk: number | null;
  nWin: number | null; winLabels: string | null; contextLabel: string | null;
  stopReleased: boolean; reParkedThisOcc: boolean; manualParkedRecent: boolean;
  reviveSettling: boolean; engineImmune: boolean; immuneReason: string | null;
  seasonRelaxApplied: boolean;
  reviveBid: number | null; reverdict: string; reverdictReason: string;
};

const num = (v: unknown): number | null => (v == null || v === '' ? null : Number(v));
const str = (v: unknown): string | null => (v == null || v === '' ? null : String(v));
const bool = (v: unknown): boolean => v === true || v === 'true';

const roasCls = (v: number | null) =>
  v == null ? 'text-faint' : v >= 1.1 ? 'text-emerald-400' : v >= 0.7 ? 'text-amber-400' : 'text-red-400';

const money = (v: number | null, d = 2) => (v == null ? '—' : `$${v.toFixed(d)}`);
const shortDate = (d: string | null) => (d ? d.slice(5) : '—');   // MM-DD; the year is never in doubt here

// The settled 90-day record, in one cell — the evidence that earned (or denied) the revival.
function Settled({ r }: { r: Row }) {
  if (!r.s90Clk) return <span className="text-faint">no settled clicks</span>;
  return (
    <span
      className="whitespace-nowrap"
      title={`settled through ${r.settledThrough ?? '—'} · CPC ${money(r.s90Cpc)} · GP ${money(r.s90Gp)}`
        + ` · ${r.lifeSettledClk ?? 0} settled clicks lifetime`
        + (r.contextLabel ? ` · season context ${r.contextLabel}` : '')}
    >
      {r.s90Clk}c · {money(r.s90Sp)} · <span className={roasCls(r.s90GpRoas)}>{r.s90GpRoas != null ? `${r.s90GpRoas.toFixed(2)}×` : '—'}</span>
      {r.s90Ord ? <span className="text-faint"> · {r.s90Ord} ord</span> : null}
    </span>
  );
}

// Anti-churn guard state — flags straight from the view, no logic here beyond showing them.
function Guards({ r }: { r: Row }) {
  const chips: { label: string; cls: string; tip: string }[] = [];
  if (r.reParkedThisOcc) chips.push({ label: 're-parked this season', cls: 'text-amber-400', tip: 'one revive per season occurrence — it already came back once this occurrence' });
  if (r.manualParkedRecent) chips.push({ label: 'your park · 14d hold', cls: 'text-violet-400', tip: 'you parked this yourself — the engines stay off it for 14 days, both directions' });
  if (r.engineImmune) chips.push({ label: 'engine-immune', cls: 'text-sky-300', tip: r.immuneReason ?? 'the engines cannot condemn this row right now' });
  if (r.reviveSettling) chips.push({ label: 'settling', cls: 'text-faint', tip: 'already revived — its new clicks have not settled yet' });
  if (r.stopReleased) chips.push({ label: 'STOP released', cls: 'text-emerald-300', tip: 'a current-occurrence settled record released the STOP gate' });
  if (r.nWin) chips.push({ label: `${r.nWin} season win${r.nWin === 1 ? '' : 's'}`, cls: 'text-emerald-300/70', tip: r.winLabels ?? '' });
  if (!chips.length) return <span className="text-faint">—</span>;
  return (
    <span className="whitespace-nowrap">
      {chips.map((c, i) => (
        <Fragment key={c.label}>
          {i > 0 && <span className="text-faint"> · </span>}
          <span className={c.cls} title={c.tip}>{c.label}</span>
        </Fragment>
      ))}
    </span>
  );
}

function KwCell({ r, indent }: { r: Row; indent?: boolean }) {
  return (
    <td className={`text-left px-2 py-0.5 text-body whitespace-nowrap ${indent ? 'pl-6' : ''}`}>
      <span className="text-muted">{r.keywordText || <span className="text-faint">(no text)</span>}</span>
      <span className="text-faint text-label"> {r.matchType}{r.isPt ? ' · PT' : ''} · {r.channel}</span>
      <span className="text-faint text-label"> · {r.campaignName || r.campaignId}</span>
      {r.family && <span className="text-faint text-label"> · {r.family}</span>}
    </td>
  );
}

export function RevivalsPhase({ defaultOpen }: { defaultOpen?: boolean }) {
  // defaultOpen (Ori 2026-08-17: "when there is an open action hierarchy should be Expanded"):
  // null until the user clicks the header, so a defaultOpen that arrives/flips later can never
  // override an explicit close — the user's click is final.
  const [openState, setOpenState] = useState<boolean | null>(null);
  const open = openState ?? defaultOpen ?? false;
  const [openConfirm, setOpenConfirm] = useState(false);
  const [openPending, setOpenPending] = useState(false);
  const [rows, setRows] = useState<Row[] | null>(null);
  const [failed, setFailed] = useState(false);
  const doQueue = useDoQueue();

  // LAZY SECTION (WEEKLY_RUN_UX.md: sections fetch ONLY on first expand). V_PARK_REVERDICT is one
  // of the ~17 ceiling views that all fired at page open (40–120s each cold — the "why is it not
  // loading" incident). The feed is the read; this microscope earns its query on the click.
  const fetchedRef = useRef(false);
  useEffect(() => {
    if (!open || fetchedRef.current) return;
    fetchedRef.current = true;
    let alive = true;
    cubeLoadWithMeta({
      dimensions: [
        'ParkReverdict.rowId', 'ParkReverdict.campaignId', 'ParkReverdict.campaignName', 'ParkReverdict.family',
        'ParkReverdict.keywordId', 'ParkReverdict.adGroupId', 'ParkReverdict.keywordText', 'ParkReverdict.matchType', 'ParkReverdict.channel', 'ParkReverdict.isPt',
        'ParkReverdict.currentBid', 'ParkReverdict.preParkBid',
        'ParkReverdict.parkDate', 'ParkReverdict.parkSource', 'ParkReverdict.parkEra', 'ParkReverdict.nParkEvents',
        'ParkReverdict.settleDue', 'ParkReverdict.settledThrough',
        'ParkReverdict.s90Clk', 'ParkReverdict.s90Sp', 'ParkReverdict.s90Ord', 'ParkReverdict.s90Gp',
        'ParkReverdict.s90GpRoas', 'ParkReverdict.s90Cpc', 'ParkReverdict.lifeSettledClk',
        'ParkReverdict.nWin', 'ParkReverdict.winLabels', 'ParkReverdict.contextLabel',
        'ParkReverdict.stopReleased', 'ParkReverdict.reParkedThisOcc', 'ParkReverdict.manualParkedRecent',
        'ParkReverdict.reviveSettling', 'ParkReverdict.engineImmune', 'ParkReverdict.immuneReason',
        'ParkReverdict.seasonRelaxApplied',
        'ParkReverdict.reviveBid', 'ParkReverdict.reverdict', 'ParkReverdict.reverdictReason',
      ],
      // v27.68 (Task 2.4): SIBLING_REVIVE (family evidence overturns the park) renders in the
      // revive table, hand-queue only; REDUNDANT (family already serves the term — reviving would
      // double-bid) renders under Park confirmed with the sibling named in its reason.
      filters: [{ member: 'ParkReverdict.reverdict', operator: 'equals', values: ['REVIVE', 'SIBLING_REVIVE', 'CONFIRM_PARK', 'REDUNDANT', 'PENDING_SETTLE'] }],
    }).then(res => {
      if (!alive) return;
      // A failed/stale cube returns {data: [], error}. Without this the panel would render its
      // empty state and claim there is nothing to show, which is a lie (verifier, 2026-08-11).
      if (res.error) { setFailed(true); return; }
      const rs = res.data;
      setRows((rs as Record<string, unknown>[]).map(r => ({
        rowId: String(r['ParkReverdict.rowId'] ?? ''),
        campaignId: String(r['ParkReverdict.campaignId'] ?? ''),
        campaignName: String(r['ParkReverdict.campaignName'] ?? ''),
        family: str(r['ParkReverdict.family']),
        keywordId: String(r['ParkReverdict.keywordId'] ?? ''),
        adGroupId: String(r['ParkReverdict.adGroupId'] ?? ''),
        keywordText: String(r['ParkReverdict.keywordText'] ?? ''),
        matchType: String(r['ParkReverdict.matchType'] ?? ''),
        channel: String(r['ParkReverdict.channel'] ?? 'SP'),
        isPt: bool(r['ParkReverdict.isPt']),
        currentBid: num(r['ParkReverdict.currentBid']), preParkBid: num(r['ParkReverdict.preParkBid']),
        parkDate: str(r['ParkReverdict.parkDate']), parkSource: str(r['ParkReverdict.parkSource']),
        parkEra: str(r['ParkReverdict.parkEra']), nParkEvents: num(r['ParkReverdict.nParkEvents']),
        settleDue: str(r['ParkReverdict.settleDue']), settledThrough: str(r['ParkReverdict.settledThrough']),
        s90Clk: num(r['ParkReverdict.s90Clk']), s90Sp: num(r['ParkReverdict.s90Sp']),
        s90Ord: num(r['ParkReverdict.s90Ord']), s90Gp: num(r['ParkReverdict.s90Gp']),
        s90GpRoas: num(r['ParkReverdict.s90GpRoas']), s90Cpc: num(r['ParkReverdict.s90Cpc']),
        lifeSettledClk: num(r['ParkReverdict.lifeSettledClk']),
        nWin: num(r['ParkReverdict.nWin']), winLabels: str(r['ParkReverdict.winLabels']),
        contextLabel: str(r['ParkReverdict.contextLabel']),
        stopReleased: bool(r['ParkReverdict.stopReleased']),
        reParkedThisOcc: bool(r['ParkReverdict.reParkedThisOcc']),
        manualParkedRecent: bool(r['ParkReverdict.manualParkedRecent']),
        reviveSettling: bool(r['ParkReverdict.reviveSettling']),
        engineImmune: bool(r['ParkReverdict.engineImmune']),
        immuneReason: str(r['ParkReverdict.immuneReason']),
        seasonRelaxApplied: bool(r['ParkReverdict.seasonRelaxApplied']),
        reviveBid: num(r['ParkReverdict.reviveBid']),
        reverdict: String(r['ParkReverdict.reverdict'] ?? ''),
        reverdictReason: String(r['ParkReverdict.reverdictReason'] ?? ''),
      })));
    }).catch(e => {
      // Stale cube schema / missing dimension / cube down — degrade to an empty state.
      // Weekly Run must never fail to render because this panel has no data.
      console.error('[revivals] fetch failed:', e);
      if (alive) setFailed(true);
    });
    return () => { alive = false; };
  }, [open]);

  const { revive, confirmPark, pending } = useMemo(() => {
    const all = rows ?? [];
    const bySettled = (a: Row, b: Row) => (b.s90GpRoas ?? 0) - (a.s90GpRoas ?? 0) || (b.s90Clk ?? 0) - (a.s90Clk ?? 0);
    return {
      revive: all.filter(r => r.reverdict === 'REVIVE' || r.reverdict === 'SIBLING_REVIVE').sort(bySettled),
      confirmPark: all.filter(r => r.reverdict === 'CONFIRM_PARK' || r.reverdict === 'REDUNDANT').sort(bySettled),
      pending: all.filter(r => r.reverdict === 'PENDING_SETTLE')
        .sort((a, b) => String(a.settleDue ?? '').localeCompare(String(b.settleDue ?? ''))),
    };
  }, [rows]);

  // ── the DO queue (v27.63) ───────────────────────────────────────────────────────────────────
  // A revival is always a RAISE and the view fixes the direction, so INCREASE_BID is a label here,
  // not a decision: the population is bid <= $0.26 (V_PARK_REVERDICT k.park_bid_max) and revive_bid
  // is floored at $0.31 (k.revive_floor). Deliberately NOT the `newBid >= bid ? INCREASE : REDUCE`
  // comparison OobBudgetPhase uses — that would be React re-deriving what the view already fixed.
  const queueRevive = (r: Row) => doQueue.addItem({
    search_term: r.keywordText, action: 'INCREASE_BID',
    campaign: r.campaignName, campaign_id: r.campaignId, ad_group_id: r.adGroupId,
    targeting: r.keywordText, keyword_id: r.keywordId, match_type: (r.matchType || '').toUpperCase(),
    target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0,
    current_bid: r.currentBid, recommended_bid: r.reviveBid,
    campaign_type: r.channel === 'SB' ? 'SPONSORED_BRANDS' : 'SPONSORED_PRODUCTS',
    product: r.isPt ? 'Product Targeting' : 'Keyword',
    spend: 0, orders: 0, cpc: 0, conv_rate: 0, source: 'COACH',
  });

  // Unified queued-state (Ori 2026-08-17: "if i approve an action in section or snapshot, visual
  // should show both approve"): the row's ✓ keys on the KEYWORD via findQueuedBid — any bid action,
  // any value, any surface. The old "other panel owns it" refusal display is gone: one decision on
  // one lever must look decided everywhere, and the row's own click removes the queued item
  // whatever its origin. Value-exact "ours" survives for ONE job — scoping the bulk-unapply sweep,
  // so apply-all's undo never rips out a bid another view priced differently.
  const ourItem = (r: Row) => {
    const it = findQueuedBid(doQueue.items, r.keywordId);
    return it && it.action === 'INCREASE_BID' && it.recommended_bid === r.reviveBid ? it : undefined;
  };

  // ONE memo feeds both the count and the button, so "apply all N" can never disagree with what it
  // queues. Eligible = the view priced it and no judgement-call guard holds it; applicable =
  // eligible rows whose keyword is not already key-queued from ANY surface — key-queued rows count
  // as DONE, not skipped, so they move to the applied tally instead of shrinking the offer.
  const { eligible, applicable } = useMemo(() => {
    // v27.68: SIBLING_REVIVE stays hand-queued (like season-relax) until the class earns bulk
    // trust — the view calls both "read-this-first" revivals, and read-first excludes apply-all.
    const el = revive.filter(r => r.reviveBid != null && !r.manualParkedRecent && !r.seasonRelaxApplied
                                  && r.reverdict !== 'SIBLING_REVIVE');
    return { eligible: el, applicable: el.filter(r => !findQueuedBid(doQueue.items, r.keywordId)) };
  }, [revive, doQueue.items]);
  const nSug = applicable.length;
  const nDone = eligible.length - applicable.length;
  const allApplied = eligible.length > 0 && applicable.length === 0;
  const applyAll = () => {
    // Unapply sweeps ONLY value-exact ourItems — a foreign-valued bid on the same keyword is
    // another view's pricing and is removed by its own row click, never by this sweep.
    if (allApplied) eligible.forEach(r => { const it = ourItem(r); if (it) doQueue.removeItem(it.id); });
    else applicable.forEach(r => queueRevive(r));
  };

  const headline = failed
    ? '— unavailable'
    : !rows
    ? (open || fetchedRef.current) ? '— loading…' : '— expand to load'
    : `— ${revive.length} ready to revive · ${confirmPark.length} park confirmed · ${pending.length} still settling`;

  return (
    <div className="mb-3 rounded-md border border-border bg-surface/30 px-3 py-2">
      <div className="flex items-center gap-1">
        <button className="text-label flex items-center gap-1 flex-1 min-w-0" onClick={() => setOpenState(!open)}>
          <span className="text-faint">{open ? '▾' : '▸'}</span>
          <span className="font-medium text-emerald-300">Revivals</span>
          {/* count stays visible while collapsed once fetched; pre-fetch the front-page feed carries
              the news (WEEKLY_RUN_UX.md — the lazy gate above trades the eager count for page load) */}
          <span className="text-faint truncate">
            {headline}
            {' '}· parked keywords whose settled record now overturns the park · you decide
          </span>
        </button>
        {rows && eligible.length > 0 && (
          <button onClick={applyAll}
            title={allApplied
              ? `unapply the revivals queued at this panel's bid (a keyword queued from another view at its own value stays — remove it from its row)`
              : `queue the ${nSug} calibrated revive bids not yet queued`
                + (nDone > 0 ? ` — ${nDone} already queued from any view count as done` : '')
                + ` (judgement-call rows — your own recent parks and season-relaxed revivals — are excluded and stay hand-queued)`}
            className={`text-label px-2 py-0.5 rounded border shrink-0 ${allApplied ? 'border-emerald-500/40 text-emerald-300' : 'border-emerald-500/40 text-emerald-300 hover:bg-emerald-500/10'}`}>
            {allApplied ? `✓ applied ${eligible.length}` : `apply all ${nSug}`}
          </button>
        )}
      </div>

      {open && failed && (
        <div className="mt-2 text-label text-faint">
          Reverdict data unavailable — the ParkReverdict cube isn't answering (stale schema or cube restart pending).
        </div>
      )}

      {open && rows && (
        <div className="mt-2 flex flex-col gap-3">
          {/* ── REVIVE — the primary list ── */}
          {revive.length === 0 ? (
            <div className="text-label text-faint">No revivals right now — nothing parked has a settled record that clears the bar.</div>
          ) : (
            <div className="overflow-x-auto">
              <table className="text-label font-mono border-collapse">
                <thead>
                  <tr className="text-faint text-right">
                    <th className="font-normal text-left px-2 py-0.5">keyword — match · channel · campaign · family</th>
                    <th className="font-normal px-2 text-left" title="when it was parked, and by whom (COACH = the engine, MANUAL = you). 'unknown era' = parked before the change log covered it.">parked</th>
                    <th className="font-normal px-2 text-left" title="the settled 90-day record that earned the revival — clicks · spend · GP-ROAS · orders. Settled = old enough that the sales are fully attributed.">settled record</th>
                    <th className="font-normal px-2 text-left" title="what this row proposes. Every row here is a revive — 'hand-check' marks the two judgement-call classes apply-all deliberately skips.">action</th>
                    <th className="font-normal px-2 text-left" title="the calibrated revive bid from the view (never the $1 probe entry — a proven record has an anchor). Click it to queue or unqueue this revival.">bid now → revive at</th>
                    <th className="font-normal px-2 text-left" title="anti-churn guards — reasons this revival is held, or extra evidence behind it">guards</th>
                    <th className="font-normal px-2 text-left">why</th>
                  </tr>
                </thead>
                <tbody>
                  {revive.map(r => {
                    // Key-queued from ANY surface at ANY value ⇒ this row renders queued. A foreign
                    // value (> $0.005 off this row's calibrated bid) shows beside the ✓ so the one
                    // decision is visible here without pretending this panel priced it.
                    const queued = findQueuedBid(doQueue.items, r.keywordId);
                    const qVal = queued?.recommended_bid ?? null;
                    const foreignVal = queued != null && qVal != null
                      && (r.reviveBid == null || Math.abs(qVal - r.reviveBid) > 0.005);
                    return (
                    <tr key={r.rowId} className="border-t border-border/40">
                      <KwCell r={r} />
                      <td className="px-2 text-left whitespace-nowrap text-muted">
                        {r.parkEra === 'UNKNOWN' || !r.parkDate
                          ? <span className="text-faint" title="no logged park event — the revive bid falls back to 1.10× settled CPC">unknown era</span>
                          : <>{shortDate(r.parkDate)}<span className="text-faint"> · {(r.parkSource ?? '').toLowerCase() || '—'}{(r.nParkEvents ?? 0) > 1 ? ` · ${r.nParkEvents}×` : ''}</span></>}
                      </td>
                      <td className="px-2 text-left"><Settled r={r} /></td>
                      <td className="px-2 text-left whitespace-nowrap">
                        {r.reviveBid == null
                          ? <span className="text-faint" title="the view priced no revive bid for this row">revive · no bid</span>
                          : r.reverdict === 'SIBLING_REVIVE'
                          ? <span className="text-violet-300" title="its OWN record fails the bar — the revival rests on a SIBLING campaign proving the same term in this family. Read the why (it names the sibling and its record), then queue it on its own if you agree. Apply-all skips it.">revive · sibling</span>
                          : r.manualParkedRecent || r.seasonRelaxApplied
                          ? <span className="text-violet-300" title={r.manualParkedRecent
                              ? 'you parked this yourself less than 14 days ago — the engines defer, so apply-all skips it. You can still queue it on its own.'
                              : 'its own settled record loses money; it clears the bar only on a prior-season win. Read the why, then queue it on its own if you agree.'}>revive · hand-check</span>
                          : <span className="text-emerald-400">revive</span>}
                      </td>
                      <td className="px-2 text-left whitespace-nowrap">
                        <span className="text-faint">{money(r.currentBid)}</span>
                        <span className="text-faint"> → </span>
                        {!queued && r.reviveBid == null ? (
                          <span className="text-faint">{money(r.reviveBid)}</span>
                        ) : (
                          <button
                            onClick={() => { if (queued) doQueue.removeItem(queued.id); else queueRevive(r); }}
                            title={(queued
                                ? foreignVal
                                  ? `queued from another view at $${qVal!.toFixed(2)} — click to remove it`
                                  : 'queued — click to remove'
                                : 'click to queue this revival')
                              + (r.preParkBid != null ? ` · pre-park bid was ${money(r.preParkBid)}` : '')}
                            className={queued ? 'text-emerald-300' : 'text-emerald-400 hover:text-emerald-200'}>
                            {money(r.reviveBid)}{queued ? ` ✓${foreignVal ? ` at $${qVal!.toFixed(2)}` : ''}` : ''}
                          </button>
                        )}
                      </td>
                      <td className="px-2 text-left"><Guards r={r} /></td>
                      <td className="px-2 text-left text-faint whitespace-normal max-w-[30rem]">{r.reverdictReason}</td>
                    </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}

          {/* ── secondary: a parked keyword's state should be knowable without hunting ── */}
          <div className="border-t border-border/40 pt-2 flex flex-col gap-2">
            <button className="text-label flex items-center gap-1 text-left" onClick={() => setOpenConfirm(o => !o)}>
              <span className="text-faint">{openConfirm ? '▾' : '▸'}</span>
              <span className="text-muted">Park confirmed</span>
              <span className="text-faint">— {confirmPark.length} · re-judged at settle and the park stands; the engines will not resurface these</span>
            </button>
            {openConfirm && (
              <div className="overflow-x-auto">
                <table className="text-label font-mono border-collapse">
                  <thead>
                    <tr className="text-faint text-right">
                      <th className="font-normal text-left px-2 py-0.5">keyword</th>
                      <th className="font-normal px-2 text-left">parked</th>
                      <th className="font-normal px-2 text-left">settled record</th>
                      <th className="font-normal px-2 text-left">why</th>
                    </tr>
                  </thead>
                  <tbody>
                    {confirmPark.map(r => (
                      <tr key={r.rowId} className="border-t border-border/20">
                        <KwCell r={r} indent />
                        <td className="px-2 text-left whitespace-nowrap text-muted">
                          {r.parkEra === 'UNKNOWN' || !r.parkDate ? <span className="text-faint">unknown era</span> : <>{shortDate(r.parkDate)}<span className="text-faint"> · {(r.parkSource ?? '').toLowerCase() || '—'}</span></>}
                        </td>
                        <td className="px-2 text-left"><Settled r={r} /></td>
                        <td className="px-2 text-left text-faint whitespace-normal max-w-[30rem]">{r.reverdictReason}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            <button className="text-label flex items-center gap-1 text-left" onClick={() => setOpenPending(o => !o)}>
              <span className="text-faint">{openPending ? '▾' : '▸'}</span>
              <span className="text-muted">Still settling</span>
              <span className="text-faint">— {pending.length} · not enough settled evidence yet; re-judged on the settle date, no verdict before then</span>
            </button>
            {openPending && (
              <div className="overflow-x-auto">
                <table className="text-label font-mono border-collapse">
                  <thead>
                    <tr className="text-faint text-right">
                      <th className="font-normal text-left px-2 py-0.5">keyword</th>
                      <th className="font-normal px-2 text-left">parked</th>
                      <th className="font-normal px-2 text-left" title="last pre-park click + 7 days (SP) / 14 days (SB) — when the sales are attributed and the row gets re-judged">re-judged on</th>
                      <th className="font-normal px-2 text-left">settled so far</th>
                      <th className="font-normal px-2 text-left">why</th>
                    </tr>
                  </thead>
                  <tbody>
                    {pending.map(r => (
                      <tr key={r.rowId} className="border-t border-border/20">
                        <KwCell r={r} indent />
                        <td className="px-2 text-left whitespace-nowrap text-muted">
                          {r.parkEra === 'UNKNOWN' || !r.parkDate ? <span className="text-faint">unknown era</span> : <>{shortDate(r.parkDate)}<span className="text-faint"> · {(r.parkSource ?? '').toLowerCase() || '—'}</span></>}
                        </td>
                        <td className="px-2 text-left whitespace-nowrap text-sky-300">{r.settleDue ?? '—'}</td>
                        <td className="px-2 text-left"><Settled r={r} /></td>
                        <td className="px-2 text-left text-faint whitespace-normal max-w-[30rem]">{r.reverdictReason}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          <div className="text-label text-subtle">
            Queued revivals go to the DO queue only — nothing uploads until you export the bulksheet,
            and the export-time preflight gate re-checks every row. Source: V_PARK_REVERDICT (backend);
            the bar, the revive bid and every guard are decided there, never here.
          </div>
        </div>
      )}
    </div>
  );
}

export default RevivalsPhase;
