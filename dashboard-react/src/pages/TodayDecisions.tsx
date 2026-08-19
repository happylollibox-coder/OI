import { useEffect, useMemo, useState } from 'react';
import { cubeLoadWithMeta } from '../hooks/useCubeData';
import { useDoQueue, findQueuedBid, findQueuedBudget, findQueuedNegates, type DoQueueItem } from '../hooks/useDoQueue';

// Weekly Run FRONT PAGE, part 2 of the 5-minute read: TODAY'S DECISIONS — one unified feed of
// every engine instruction, judged, from T_ENGINE_PREFLIGHT (EnginePreflight cube).
// Spec: architecture/WEEKLY_RUN_UX.md (Phase 6 plan Task 4).
//
// THE VERDICTS ARE THE SP'S. This file renders GO / REVIEW / EXCLUDE as stamped at snapshot
// time and never recomputes one. The single permitted piece of React glue is direction:
// INCREASE_BID vs REDUCE_BID by comparing suggested to current (the OobBudgetPhase:241
// precedent) — a queue-item label, not a decision.
//
// The 5-second anatomy, every actionable row, same order:
//   [item]  [now → proposed (the proposed value IS the queue toggle, ✓ when queued)]
//   [flags: REVIEW chip only — guards that passed are silent]  [why: reasonShort ?? reason,
//   one line, full reason always in the tooltip].
//
// Verdict rules, restated because they are the contract:
//   GO      — queueable; per-group `queue all` derives count AND click from ONE memoised list.
//   REVIEW  — amber chip; queues only through a per-item window.confirm(verdictReason). The
//             export-time gate on the DO page re-checks — two doors, same rule.
//   EXCLUDE — one collapsed faint line per group; expandable; NO queue affordance anywhere.
// One decision, one ✓ (Ori 2026-08-17): queued state is looked up by CANONICAL KEY (the
// useDoQueue findQueued* helpers), never by "did this surface queue it" — approving here shows
// ✓ in the criteria sections and vice versa. A key queued at a DIFFERENT value (the sections
// read live views; this feed reads the frozen snapshot) still renders ✓, with the queued value
// printed beside it; the click removes that item, and a second click re-queues at THIS value.
// $/day appears on BUDGET rows only — bid-level $/day would be invented precision.
// NEGATE rows (v27.72): no value — the toggle is the word "block"; queueing splits the
// ad-group list into one item per group, exactly as the panels do (upload report 29).

type Row = {
  rowId: string; engine: string; ownerEngine: string; lever: string; grain: string;
  verdict: string; verdictReason: string;
  campaignId: string; campaignName: string; keywordId: string; adGroupId: string;
  targetText: string; matchType: string; channel: string; action: string;
  currentBid: number | null; suggestedBid: number | null;
  currentBudget: number | null; suggestedBudget: number | null;
  reason: string; reasonShort: string | null; snapshotDate: string | null;
};

// The ownership order — LOW_STOCK outranks everything, COACH yields to all (v27.72).
const ENGINE_ORDER = ['LOW_STOCK', 'LAUNCH', 'OOB', 'REVERDICT', 'LIFT', 'COACH'];

const num = (v: unknown): number | null => (v == null || v === '' ? null : Number(v));
const str = (v: unknown): string | null => (v == null || v === '' ? null : String(v));
const money = (v: number | null) => (v == null ? '—' : `$${v.toFixed(2)}`);
const signedDay = (d: number) => `${d >= 0 ? '+' : '−'}$${Math.abs(d).toFixed(2)}/d`;

const isBudget = (r: Row) => r.lever === 'BUDGET';
const isNegate = (r: Row) => r.lever === 'NEGATE';
const hasKeys = (r: Row) => r.keywordId !== '' && r.adGroupId !== '';
// negates carry the term instead of a value/keys; that IS their payload
const hasValue = (r: Row) => (isNegate(r) ? r.targetText !== '' : isBudget(r) ? r.suggestedBudget != null : r.suggestedBid != null);
// The one permitted glue (OobBudgetPhase:241): the queue label follows the actual number.
const derivedAction = (r: Row) => ((r.suggestedBid ?? 0) >= (r.currentBid ?? 0) ? 'INCREASE_BID' : 'REDUCE_BID');
const whyShort = (r: Row) => r.reasonShort ?? r.reason;   // pre-Task-3 tolerance: short is often NULL

export function TodayDecisions() {
  const [rows, setRows] = useState<Row[] | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let alive = true;
    cubeLoadWithMeta({
      dimensions: ['EnginePreflight.rowId', 'EnginePreflight.engine', 'EnginePreflight.ownerEngine',
        'EnginePreflight.lever', 'EnginePreflight.grain', 'EnginePreflight.verdict',
        'EnginePreflight.verdictReason', 'EnginePreflight.campaignId', 'EnginePreflight.campaignName',
        'EnginePreflight.keywordId', 'EnginePreflight.adGroupId', 'EnginePreflight.targetText',
        'EnginePreflight.matchType', 'EnginePreflight.channel', 'EnginePreflight.action',
        'EnginePreflight.currentBid', 'EnginePreflight.suggestedBid',
        'EnginePreflight.currentBudget', 'EnginePreflight.suggestedBudget',
        'EnginePreflight.reason', 'EnginePreflight.reasonShort', 'EnginePreflight.snapshotDate'],
    }).then(res => {
      if (!alive) return;
      // {data: [], error} = the cube never answered; an empty feed would claim a clean run.
      if (res.error) { setFailed(true); return; }
      setRows((res.data as Record<string, unknown>[]).map(r => ({
        rowId: String(r['EnginePreflight.rowId'] ?? ''),
        engine: String(r['EnginePreflight.engine'] ?? ''),
        ownerEngine: String(r['EnginePreflight.ownerEngine'] ?? ''),
        lever: String(r['EnginePreflight.lever'] ?? ''),
        grain: String(r['EnginePreflight.grain'] ?? ''),
        verdict: String(r['EnginePreflight.verdict'] ?? ''),
        verdictReason: String(r['EnginePreflight.verdictReason'] ?? ''),
        campaignId: String(r['EnginePreflight.campaignId'] ?? ''),
        campaignName: String(r['EnginePreflight.campaignName'] ?? ''),
        keywordId: String(r['EnginePreflight.keywordId'] ?? ''),
        adGroupId: String(r['EnginePreflight.adGroupId'] ?? ''),
        targetText: String(r['EnginePreflight.targetText'] ?? ''),
        matchType: String(r['EnginePreflight.matchType'] ?? ''),
        channel: String(r['EnginePreflight.channel'] ?? 'SP'),
        action: String(r['EnginePreflight.action'] ?? ''),
        currentBid: num(r['EnginePreflight.currentBid']),
        suggestedBid: num(r['EnginePreflight.suggestedBid']),
        currentBudget: num(r['EnginePreflight.currentBudget']),
        suggestedBudget: num(r['EnginePreflight.suggestedBudget']),
        reason: String(r['EnginePreflight.reason'] ?? ''),
        reasonShort: str(r['EnginePreflight.reasonShort']),
        snapshotDate: str(r['EnginePreflight.snapshotDate']),
      })));
    }).catch(e => {
      console.error('[today-decisions] fetch failed:', e);
      if (alive) setFailed(true);
    });
    return () => { alive = false; };
  }, []);

  const byEngine = useMemo(() => {
    const m = new Map<string, Row[]>();
    for (const r of rows ?? []) { const a = m.get(r.engine) ?? []; a.push(r); m.set(r.engine, a); }
    return m;
  }, [rows]);
  const snapshotDate = (rows ?? []).find(r => r.snapshotDate)?.snapshotDate ?? null;

  return (
    <section className="mb-4 rounded-xl border border-border bg-card p-4">
      <div className="flex items-baseline gap-2 flex-wrap mb-1">
        {/* Ori 2026-08-16 cold read: "every engine, one place" + "microscope" are builder
            metaphors, not page language. Say what the section IS in the reader's words. */}
        <h2 className="text-body font-semibold">Today's decisions</h2>
        <span className="text-label text-faint">
          every change proposed for today — bids, budgets, revivals, blocked search terms — from
          all checks, in one list
          {snapshotDate ? ` · decided at the ${snapshotDate} snapshot` : ''} · each section further
          down shows one check's full detail
        </span>
      </div>
      {failed ? (
        <div className="text-label text-faint">preflight unavailable — the EnginePreflight cube isn't answering; the criteria sections below still work</div>
      ) : !rows ? (
        <div className="text-label text-faint">loading the judged snapshot…</div>
      ) : rows.length === 0 ? (
        <div className="text-label text-faint">no engine instructions in today's snapshot</div>
      ) : (
        <div className="flex flex-col gap-3">
          {ENGINE_ORDER.filter(e => byEngine.has(e)).map(e => (
            <EngineGroup key={e} engine={e} rows={byEngine.get(e)!} />
          ))}
          {/* engines outside the known order still render — nothing in the snapshot may vanish */}
          {[...byEngine.keys()].filter(e => !ENGINE_ORDER.includes(e)).map(e => (
            <EngineGroup key={e} engine={e} rows={byEngine.get(e)!} />
          ))}
        </div>
      )}
    </section>
  );
}

function EngineGroup({ engine, rows }: { engine: string; rows: Row[] }) {
  const doQueue = useDoQueue();
  const [showExcluded, setShowExcluded] = useState(false);

  const { go, review, excluded } = useMemo(() => {
    // Budgets first (few, and they set the group's $/day), then bids, then negates — a stable read.
    const tier = (r: Row) => (isBudget(r) ? 0 : isNegate(r) ? 2 : 1);
    const order = (a: Row, b: Row) =>
      tier(a) - tier(b)
      || a.campaignName.localeCompare(b.campaignName)
      || a.targetText.localeCompare(b.targetText);
    return {
      go: rows.filter(r => r.verdict === 'GO').sort(order),
      review: rows.filter(r => r.verdict === 'REVIEW').sort(order),
      excluded: rows.filter(r => r.verdict === 'EXCLUDE').sort(order),
    };
  }, [rows]);

  // Σ$/day for BUDGET rows only (GO) — presentational Σ of the two view numbers on each row.
  // Bid rows contribute nothing: bid-level $/day would be invented precision.
  const budgetDelta = useMemo(() => {
    const buds = go.filter(r => isBudget(r) && r.suggestedBudget != null && r.currentBudget != null);
    return buds.length ? buds.reduce((s, r) => s + (r.suggestedBudget! - r.currentBudget!), 0) : null;
  }, [go]);

  // ── the DO queue: CANONICAL-KEY lookups (Ori 2026-08-17: one decision, one ✓, every surface) ──
  const queuedItem = (r: Row): DoQueueItem | undefined =>
    isNegate(r) ? findQueuedNegates(doQueue.items, r.campaignId, r.targetText)[0]
      : isBudget(r) ? findQueuedBudget(doQueue.items, r.campaignId)
      : findQueuedBid(doQueue.items, r.keywordId);
  // Value-exact match — what THIS feed would queue. Used only to scope the bulk-unapply sweep;
  // the ✓ itself comes from queuedItem, whatever surface (and value) put it there.
  const ourItem = (r: Row): DoQueueItem | undefined => {
    const it = queuedItem(r);
    if (!it) return undefined;
    if (isNegate(r)) return it;   // a negate has no value to differ on
    if (isBudget(r)) return it.recommended_budget === r.suggestedBudget ? it : undefined;
    return it.action === derivedAction(r) && it.recommended_bid === r.suggestedBid ? it : undefined;
  };

  const queueRow = (r: Row) => {
    if (isNegate(r)) {
      // one item per ad group in the snapshot's comma-list — the panels' split (upload report 29);
      // SP with no listed group falls back to a Campaign Negative Keyword row ('')
      const ags = (r.adGroupId || '').split(',').map(s => s.trim()).filter(Boolean);
      (ags.length ? ags : ['']).forEach(ag => doQueue.addItem({
        search_term: r.targetText, action: 'NEGATE_TERM', campaign: r.campaignName, campaign_id: r.campaignId,
        ad_group_id: ag, targeting: r.targetText, keyword_id: '', match_type: 'NEGATIVE_EXACT',
        target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0, current_bid: null, recommended_bid: null,
        campaign_type: r.channel === 'SB' ? 'SPONSORED_BRANDS' : 'SPONSORED_PRODUCTS', product: 'Keyword',
        spend: 0, orders: 0, cpc: 0, conv_rate: 0, source: 'COACH',
      }));
    } else if (isBudget(r)) {
      // the OobBudgetPhase:211 queueBudget shape
      doQueue.addItem({
        search_term: `__budget__${r.campaignId}`, action: 'BUDGET_CHANGE', campaign: r.campaignName, campaign_id: r.campaignId,
        ad_group_id: '', targeting: '', keyword_id: '', match_type: '', target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0,
        current_bid: null, recommended_bid: null,
        campaign_type: r.channel === 'SB' ? 'SPONSORED_BRANDS' : 'SPONSORED_PRODUCTS', product: '',
        spend: 0, orders: 0, cpc: 0, conv_rate: 0, current_budget: r.currentBudget, recommended_budget: r.suggestedBudget,
        source: 'COACH',
      });
    } else {
      // the OobBudgetPhase:231 queueKwBid shape; direction = the one permitted glue above
      doQueue.addItem({
        campaign: r.campaignName, campaign_id: r.campaignId, ad_group_id: r.adGroupId, targeting: r.targetText, search_term: r.targetText,
        keyword_id: r.keywordId, match_type: (r.matchType || '').toUpperCase(),
        target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0,
        campaign_type: r.channel === 'SB' ? 'SPONSORED_BRANDS' : 'SPONSORED_PRODUCTS',
        product: (r.matchType || '').toUpperCase() === 'AUTOMATIC' ? 'Product Targeting' : 'Keyword', spend: 0, orders: 0, cpc: 0, conv_rate: 0,
        action: derivedAction(r), current_bid: r.currentBid, recommended_bid: r.suggestedBid, source: 'COACH',
      });
    }
  };

  // ONE list feeds both the count and the click, so `queue all N` can never disagree with what
  // it queues: GO ∧ has a value ∧ (budgets/negates key on campaign; bids need both upload keys).
  // Rows already queued — from ANY surface, at ANY value — count as done, not as skipped.
  const eligible = (r: Row) => hasValue(r) && (isBudget(r) || isNegate(r) || hasKeys(r));
  const applicable = useMemo(
    () => go.filter(r => eligible(r) && !queuedItem(r)),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [go, doQueue.items]);
  const queuedGo = useMemo(
    () => go.filter(r => eligible(r) && !!queuedItem(r)),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [go, doQueue.items]);
  const nApp = applicable.length;
  const allApplied = nApp === 0 && queuedGo.length > 0;
  const applyAll = () => {
    // bulk-unapply removes only value-exact items (what this feed queues) — a different value
    // queued from a section is one deliberate decision, removed by ITS row click, never a sweep
    if (allApplied) queuedGo.forEach(r => { const it = ourItem(r); if (it) removeRow(r, it); });
    else applicable.forEach(r => queueRow(r));
  };

  // negates split into one item per ad group — removing the term removes ALL its split items
  const removeRow = (r: Row, it: DoQueueItem) => {
    if (isNegate(r)) findQueuedNegates(doQueue.items, r.campaignId, r.targetText).forEach(n => doQueue.removeItem(n.id));
    else doQueue.removeItem(it.id);
  };

  const toggleRow = (r: Row) => {
    const it = queuedItem(r);
    if (it) { removeRow(r, it); return; }
    // REVIEW queues only through the per-item confirm — the DO page's export gate re-checks.
    if (r.verdict === 'REVIEW' && !window.confirm(`${r.verdictReason} — queue anyway?`)) return;
    queueRow(r);
  };

  // The proposed-value cell — the value IS the queue toggle (✓ when queued, from ANY surface).
  const valueCell = (r: Row) => {
    if (isNegate(r)) {
      const it = queuedItem(r);
      return (
        <td className="px-2 text-left whitespace-nowrap">
          <button onClick={() => toggleRow(r)}
            title={it ? 'queued to block — click to remove' : r.verdict === 'REVIEW' ? 'flagged for review — queueing asks you to confirm' : 'click to queue the negative'}
            className={it ? 'text-emerald-300' : 'text-emerald-400 hover:text-emerald-200'}>
            {it ? '✓ blocking' : 'block'}
          </button>
        </td>
      );
    }
    const now = isBudget(r) ? r.currentBudget : r.currentBid;
    const proposed = isBudget(r) ? r.suggestedBudget : r.suggestedBid;
    const it = queuedItem(r);
    const itVal = it ? (isBudget(r) ? it.recommended_budget : it.recommended_bid) : null;
    const valueDiffers = it != null && itVal != null && proposed != null && Math.abs(itVal - proposed) > 0.005;
    return (
      <td className="px-2 text-left whitespace-nowrap">
        <span className="text-faint">{money(now)}</span>
        <span className="text-faint"> → </span>
        {proposed == null ? (
          <span className="text-faint" title="the engine priced no value for this row">—</span>
        ) : !isBudget(r) && !hasKeys(r) ? (
          <span className="text-faint" title="no keyword/ad-group id — cannot become a bulksheet row">{money(proposed)}</span>
        ) : (
          <button onClick={() => toggleRow(r)}
            title={it
              ? valueDiffers
                ? `queued from another view at ${money(itVal)} — click to remove it (click again to queue at this value)`
                : 'queued — click to remove'
              : r.verdict === 'REVIEW' ? 'flagged for review — queueing asks you to confirm' : 'click to queue'}
            className={it ? 'text-emerald-300' : 'text-emerald-400 hover:text-emerald-200'}>
            {money(proposed)}{it ? (valueDiffers ? ` ✓ at ${money(itVal)}` : ' ✓') : ''}
          </button>
        )}
      </td>
    );
  };

  const decisionRow = (r: Row) => (
    <tr key={r.rowId} className="border-t border-border/40">
      {/* Ori 2026-08-16, reading the page cold: the item column had scrolled out of view (wide
          table + overflow-x) and budget rows led with '(budget)' instead of WHOSE budget. The
          item is the row's anchor — sticky-left so it can never scroll away, and budget rows
          lead with the campaign name. */}
      <td className="px-2 py-0.5 text-left whitespace-nowrap sticky left-0 bg-card z-10">
        {isBudget(r) ? (<>
          <span className="text-muted">{r.campaignName || r.campaignId}</span>
          <span className="text-faint text-label"> campaign budget · {r.channel}</span>
        </>) : isNegate(r) ? (<>
          <span className="text-muted">{r.targetText || '(no text)'}</span>
          <span className="text-faint text-label"> block search term · {r.channel} · {r.campaignName || r.campaignId}</span>
        </>) : (<>
          <span className="text-muted">{r.targetText || '(no text)'}</span>
          <span className="text-faint text-label">
            {r.matchType ? ` ${r.matchType}` : ''} · {r.channel} · {r.campaignName || r.campaignId}
          </span>
        </>)}
      </td>
      {valueCell(r)}
      <td className="px-2 text-left whitespace-nowrap">
        {/* guards that passed are silent — only REVIEW renders, one amber chip + reason */}
        {r.verdict === 'REVIEW'
          ? <span className="text-amber-400" title={r.verdictReason}>review</span>
          : null}
      </td>
      <td className="px-2 text-left text-faint max-w-[34rem] overflow-hidden text-ellipsis whitespace-nowrap" title={r.reason}>
        {whyShort(r)}
      </td>
    </tr>
  );

  return (
    <div className="rounded-md border border-border bg-surface/30 px-3 py-2">
      <div className="flex items-center gap-2 flex-wrap">
        {/* plain names on the page; the engine code lives in the tooltip (Ori's cold read:
            "LOW_STOCK · 41 GO" answered no question a reader has) */}
        <span className="text-label font-medium" title={`engine: ${engine}`}>
          {({ LOW_STOCK: 'Low stock', LAUNCH: 'Launch', OOB: 'Out of budget',
              REVERDICT: 'Revivals', LIFT: 'Portfolio 80/20', COACH: 'Coach' } as Record<string, string>)[engine] ?? engine}
        </span>
        <span className="text-label text-faint">
          · {go.length} ready
          {review.length > 0 ? <span className="text-amber-400"> · {review.length} review</span> : null}
          {budgetDelta != null && (
            <span title="Σ of the proposed budget moves in this group — budget rows only; bid rows carry no $/day (the snapshot holds no spend estimate, and fake precision breaks trust)">
              {' '}· <span className={`font-mono ${budgetDelta >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>{signedDay(budgetDelta)}</span> budget
            </span>
          )}
        </span>
        <span className="flex-1" />
        {(nApp > 0 || allApplied) && (
          <button onClick={applyAll}
            title={allApplied
              ? 'unapply this group (rows queued from a section at a different value keep their own decision — remove those on their row)'
              : `queue all ${nApp} not-yet-queued rows in this group (rows marked "review" need their own click; rows already queued anywhere count as done)`}
            className="text-label px-2 py-0.5 rounded border shrink-0 border-emerald-500/40 text-emerald-300 hover:bg-emerald-500/10">
            {allApplied ? `✓ queued ${queuedGo.length}` : `queue all ${nApp} ready`}
          </button>
        )}
      </div>

      {(go.length > 0 || review.length > 0) && (
        <div className="overflow-x-auto mt-1">
          <table className="text-label font-mono border-collapse">
            <thead>
              <tr className="text-faint text-left">
                <th className="font-normal px-2 py-0.5">item</th>
                <th className="font-normal px-2" title="current → proposed. The proposed value is the queue toggle — click it to queue, ✓ when queued.">now → proposed</th>
                <th className="font-normal px-2" title="flags — quiet means every check passed">flags</th>
                <th className="font-normal px-2" title="the engine's why, one clause; the full reason is this cell's tooltip">why</th>
              </tr>
            </thead>
            <tbody>
              {go.map(decisionRow)}
              {review.map(decisionRow)}
            </tbody>
          </table>
        </div>
      )}

      {excluded.length > 0 && (
        <div className="mt-1">
          <button className="text-label flex items-center gap-1 text-faint" onClick={() => setShowExcluded(o => !o)}>
            <span>{showExcluded ? '▾' : '▸'}</span>
            <span>{excluded.length} excluded — owned elsewhere</span>
          </button>
          {showExcluded && (
            <div className="overflow-x-auto">
              <table className="text-label font-mono border-collapse opacity-60">
                <tbody>
                  {excluded.map(r => (
                    <tr key={r.rowId} className="border-t border-border/20">
                      <td className="px-2 py-0.5 text-left whitespace-nowrap text-faint">
                        {isBudget(r) ? '(budget)' : (r.targetText || '(no text)')} · {r.channel} · {r.campaignName || r.campaignId}
                      </td>
                      <td className="px-2 text-left whitespace-nowrap text-faint">
                        {r.ownerEngine ? `owned by ${r.ownerEngine}` : 'no-op'}
                      </td>
                      <td className="px-2 text-left text-faint max-w-[34rem] overflow-hidden text-ellipsis whitespace-nowrap" title={r.verdictReason}>
                        {r.verdictReason}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export default TodayDecisions;
