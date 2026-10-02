import { useEffect, useMemo, useState } from 'react';
import { cubeLoadWithMeta } from '../hooks/useCubeData';

// Weekly Run — "How did last week's changes do?": the settled OUTCOME half of Ori's
// "1 day for opportunity, 7 days for OUTCOME" doctrine. Spec: architecture/PPC_CLOSE_THE_LOOP.md.
//
// A change made on day T is graded on [T+1, T+7] (SB [T+1, T+14]) and may not be READ before T+14
// (SB T+21) — a trailing 7-day window ending yesterday sees only ~89% of its final sales, worst on
// the newest day, which is exactly the day the change affected most. Grade early and you reverse
// winners, then reverse the reversal. Rows that are not old enough never reach the view at all, so
// "no rows" honestly means "nothing has settled yet".
//
// ADVISORY + DISPLAY-ONLY. verdict, verdict_reason, remedy and remedy_value all come from
// V_CHANGE_SCORECARD. This file must never compare a GP-ROAS to 1.0, or derive a bid or a verdict.
// It does not write to the DO queue.

type Row = {
  changeId: string; changeDate: string; source: string; action: string; actionGroup: string;
  scopeGrain: string; channel: string; campaignId: string; campaignName: string; family: string | null;
  targeting: string | null; searchTerm: string | null; matchType: string | null;
  valueKind: string | null; oldValue: number | null; newValue: number | null; pctChange: number | null;
  windowStart: string | null; windowEnd: string | null; windowUsed: string; winDays: number | null;
  winClicks: number | null; winSpend: number | null; winOrders: number | null;
  winGpRoas: number | null; winCpc: number | null; winNetProfit: number | null;
  priorClicks: number | null; priorSpend: number | null; priorGpRoas: number | null; priorAvailable: boolean;
  supersededInWindow: boolean; nLaterChanges: number | null;
  verdict: string; verdictReason: string; remedy: string | null; remedyValue: number | null;
};

const num = (v: unknown): number | null => (v == null || v === '' ? null : Number(v));
const str = (v: unknown): string | null => (v == null || v === '' ? null : String(v));
const bool = (v: unknown): boolean => v === true || v === 'true';

const roasCls = (v: number | null) =>
  v == null ? 'text-faint' : v >= 1.1 ? 'text-emerald-400' : v >= 0.7 ? 'text-amber-400' : 'text-red-400';
const npCls = (n: number | null) => (n == null ? 'text-faint' : n > 0 ? 'text-emerald-400' : n < 0 ? 'text-red-400' : 'text-muted');
const money = (v: number | null, d = 2) => (v == null ? '—' : `$${v.toFixed(d)}`);
const shortDate = (d: string | null) => (d ? d.slice(5) : '—');

// Display order + copy for the four verdicts. The definitions live in the view; these are labels.
const VERDICTS = ['CONFIRMED', 'NEUTRAL', 'REVERSED', 'INSUFFICIENT'] as const;
const VERDICT_META: Record<string, { label: string; cls: string; short: string; desc: string; defaultOpen: boolean }> = {
  CONFIRMED:    { label: 'Confirmed', short: 'confirmed', cls: 'text-emerald-400', defaultOpen: true,
                  desc: 'the change paid — hold it; one more step in the same direction is allowed' },
  NEUTRAL:      { label: 'Neutral', short: 'neutral', cls: 'text-amber-400', defaultOpen: true,
                  desc: 'better than its own prior record but still under breakeven — hold, no further step' },
  REVERSED:     { label: 'Reversed', short: 'reversed', cls: 'text-red-400', defaultOpen: true,
                  desc: 'below breakeven AND below its own prior — put the pre-change value back. These land near breakeven, not disaster: the remedy is restore, never punish further.' },
  INSUFFICIENT: { label: 'Not enough evidence', short: 'insufficient', cls: 'text-faint', defaultOpen: false,
                  desc: 'under 10 settled clicks in the window — no verdict on thin evidence; it extends to T+21 instead' },
};

// Plain-language label for each action group. The grouping itself is the view's action_group.
const ACTION_LABEL: Record<string, string> = {
  BID_UP: 'bid raised', BID_DOWN: 'bid cut',
  BUDGET_UP: 'budget raised', BUDGET_DOWN: 'budget cut',
  NEGATE: 'term negated', UNNEGATE: 'negative removed',
  PAUSE_TARGET: 'target paused', ADD_TARGET: 'target added',
  OTHER: 'change',
};
const REMEDY_LABEL: Record<string, string> = {
  RESTORE_BID: 'put the bid back',
  RESTORE_BUDGET: 'put the budget back',
  RE_APPLY_NEGATIVE: 're-apply the negative',
  REVIEW: 'review by hand',
};

// Who made the change — copy + colour for the view's `source`. Colour marks a change a person made
// (MANUAL logged on the DO page, OBSERVED seen on Amazon only); OI-built rows (the coach, the weekly
// book's tiers, tagged '<TIER>:<book source>') stay faint. Labels only — the view does the split.
// OBSERVED rows do not reach this panel today: cube/schema/ChangeScorecard.js reads the view with
// source != 'OBSERVED', as the morning brief does, until Ori decides graded hand changes belong
// here (architecture/PPC_CLOSE_THE_LOOP.md §Observed changes). The OBSERVED label is for that day.
const BOOK_TIER_TITLE: Record<string, string> = {
  CATALOG: "the weekly book's Catalog tier decided it — whether this is worth having (pause, negate, park)",
  BRAIN: "the weekly book's Brain tier decided it — where the money goes (budgets, seat moves)",
  PACING: "the weekly book's Pacing tier decided it — a bid move to get the clicks the plan asked for",
};
function sourceMeta(source: string): { cls: string; title: string } {
  if (source === 'MANUAL') return { cls: 'text-violet-400', title: 'you made this change by hand and logged it in OI' };
  if (source === 'OBSERVED') return { cls: 'text-pink-400', title: 'seen on Amazon, not logged by OI — usually a change you made in the console' };
  if (source === 'COACH') return { cls: 'text-faint', title: 'the coach suggested it' };
  const tier = BOOK_TIER_TITLE[source.split(':')[0]];
  return { cls: 'text-faint', title: tier ?? `source: ${source}` };
}

// What the change was, in one cell: campaign ▸ target / term, at the grain the view scored it on.
function ItemCell({ r }: { r: Row }) {
  const leaf = r.scopeGrain === 'TERM' ? r.searchTerm : r.scopeGrain === 'TARGET' ? r.targeting : null;
  return (
    <td className="text-left px-2 py-0.5 text-body whitespace-nowrap">
      <span className="text-muted">{r.campaignName || r.campaignId}</span>
      {leaf && <><span className="text-faint"> ▸ </span><span className="text-muted">{leaf}</span></>}
      <span className="text-faint text-label"> {r.channel}{r.matchType ? ` · ${r.matchType}` : ''}{r.family ? ` · ${r.family}` : ''}</span>
    </td>
  );
}

export function ChangeScorecardPanel() {
  const [open, setOpen] = useState(false);
  const [openGroup, setOpenGroup] = useState<Record<string, boolean>>(
    Object.fromEntries(VERDICTS.map(v => [v, VERDICT_META[v].defaultOpen])),
  );
  const [rows, setRows] = useState<Row[] | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let alive = true;
    cubeLoadWithMeta({
      dimensions: [
        'ChangeScorecard.changeId', 'ChangeScorecard.changeDate', 'ChangeScorecard.source',
        'ChangeScorecard.action', 'ChangeScorecard.actionGroup', 'ChangeScorecard.scopeGrain', 'ChangeScorecard.channel',
        'ChangeScorecard.campaignId', 'ChangeScorecard.campaignName', 'ChangeScorecard.family',
        'ChangeScorecard.targeting', 'ChangeScorecard.searchTerm', 'ChangeScorecard.matchType',
        'ChangeScorecard.valueKind', 'ChangeScorecard.oldValue', 'ChangeScorecard.newValue', 'ChangeScorecard.pctChange',
        'ChangeScorecard.windowStart', 'ChangeScorecard.windowEnd', 'ChangeScorecard.windowUsed', 'ChangeScorecard.winDays',
        'ChangeScorecard.winClicks', 'ChangeScorecard.winSpend', 'ChangeScorecard.winOrders',
        'ChangeScorecard.winGpRoas', 'ChangeScorecard.winCpc', 'ChangeScorecard.winNetProfit',
        'ChangeScorecard.priorClicks', 'ChangeScorecard.priorSpend', 'ChangeScorecard.priorGpRoas', 'ChangeScorecard.priorAvailable',
        'ChangeScorecard.supersededInWindow', 'ChangeScorecard.nLaterChanges',
        'ChangeScorecard.verdict', 'ChangeScorecard.verdictReason', 'ChangeScorecard.remedy', 'ChangeScorecard.remedyValue',
      ],
    }).then(res => {
      if (!alive) return;
      // A failed/stale cube returns {data: [], error}. Without this the panel would render its
      // empty state and claim there is nothing to show, which is a lie (verifier, 2026-08-11).
      if (res.error) { setFailed(true); return; }
      const rs = res.data;
      setRows((rs as Record<string, unknown>[]).map(r => ({
        changeId: String(r['ChangeScorecard.changeId'] ?? ''),
        changeDate: String(r['ChangeScorecard.changeDate'] ?? ''),
        source: String(r['ChangeScorecard.source'] ?? ''),
        action: String(r['ChangeScorecard.action'] ?? ''),
        actionGroup: String(r['ChangeScorecard.actionGroup'] ?? 'OTHER'),
        scopeGrain: String(r['ChangeScorecard.scopeGrain'] ?? ''),
        channel: String(r['ChangeScorecard.channel'] ?? 'SP'),
        campaignId: String(r['ChangeScorecard.campaignId'] ?? ''),
        campaignName: String(r['ChangeScorecard.campaignName'] ?? ''),
        family: str(r['ChangeScorecard.family']),
        targeting: str(r['ChangeScorecard.targeting']),
        searchTerm: str(r['ChangeScorecard.searchTerm']),
        matchType: str(r['ChangeScorecard.matchType']),
        valueKind: str(r['ChangeScorecard.valueKind']),
        oldValue: num(r['ChangeScorecard.oldValue']), newValue: num(r['ChangeScorecard.newValue']),
        pctChange: num(r['ChangeScorecard.pctChange']),
        windowStart: str(r['ChangeScorecard.windowStart']), windowEnd: str(r['ChangeScorecard.windowEnd']),
        windowUsed: String(r['ChangeScorecard.windowUsed'] ?? 'PRIMARY'), winDays: num(r['ChangeScorecard.winDays']),
        winClicks: num(r['ChangeScorecard.winClicks']), winSpend: num(r['ChangeScorecard.winSpend']),
        winOrders: num(r['ChangeScorecard.winOrders']), winGpRoas: num(r['ChangeScorecard.winGpRoas']),
        winCpc: num(r['ChangeScorecard.winCpc']), winNetProfit: num(r['ChangeScorecard.winNetProfit']),
        priorClicks: num(r['ChangeScorecard.priorClicks']), priorSpend: num(r['ChangeScorecard.priorSpend']),
        priorGpRoas: num(r['ChangeScorecard.priorGpRoas']),
        priorAvailable: bool(r['ChangeScorecard.priorAvailable']),
        supersededInWindow: bool(r['ChangeScorecard.supersededInWindow']),
        nLaterChanges: num(r['ChangeScorecard.nLaterChanges']),
        verdict: String(r['ChangeScorecard.verdict'] ?? ''),
        verdictReason: String(r['ChangeScorecard.verdictReason'] ?? ''),
        remedy: str(r['ChangeScorecard.remedy']), remedyValue: num(r['ChangeScorecard.remedyValue']),
      })));
    }).catch(e => {
      // Stale cube schema / missing dimension / cube down — degrade to an empty state.
      // Weekly Run must never fail to render because this panel has no data.
      console.error('[change-scorecard] fetch failed:', e);
      if (alive) setFailed(true);
    });
    return () => { alive = false; };
  }, []);

  // newest change first, biggest window spend first within a day — no verdict logic here
  const byVerdict = useMemo(() => {
    const out: Record<string, Row[]> = { CONFIRMED: [], NEUTRAL: [], REVERSED: [], INSUFFICIENT: [] };
    for (const r of rows ?? []) if (out[r.verdict]) out[r.verdict].push(r);
    for (const v of VERDICTS) {
      out[v].sort((a, b) => b.changeDate.localeCompare(a.changeDate) || (b.winSpend ?? 0) - (a.winSpend ?? 0));
    }
    return out;
  }, [rows]);

  const graded = rows?.length ?? 0;
  const latest = useMemo(() => (rows ?? []).reduce((m, r) => (r.changeDate > m ? r.changeDate : m), ''), [rows]);

  const headline = failed
    ? '— unavailable'
    : !rows
    ? '— loading…'
    : graded === 0
    ? '— nothing has settled yet'
    : `— ${VERDICTS.map(v => `${byVerdict[v].length} ${VERDICT_META[v].short}`).join(' · ')}`;

  return (
    <section className="mb-4 rounded-xl border border-border bg-card px-4 py-3">
      <div className="flex items-center gap-1">
        <button className="text-label flex items-center gap-1 flex-1 min-w-0 text-left" onClick={() => setOpen(o => !o)}>
          <span className="text-faint">{open ? '▾' : '▸'}</span>
          <span className="font-medium text-blue-300">How did last week's changes do?</span>
          <span className="text-faint truncate">
            {headline}
            {' '}· {graded} settled change{graded === 1 ? '' : 's'}{latest ? `, through ${latest}` : ''}
          </span>
        </button>
      </div>

      {open && failed && (
        <div className="mt-2 text-label text-faint">
          Scorecard unavailable — the ChangeScorecard cube isn't answering (stale schema or cube restart pending).
        </div>
      )}

      {open && rows && graded === 0 && (
        <div className="mt-2 text-label text-faint">
          Nothing has settled yet. A change made on day T is graded on [T+1, T+7] and only read from T+14
          (SB: [T+1, T+14], read from T+21) — reading earlier under-reads your own change, because the newest
          day of the window is the least complete and it is exactly the day the change moved most.
        </div>
      )}

      {open && rows && graded > 0 && (
        <div className="mt-2 flex flex-col gap-3">
          {VERDICTS.map(v => {
            const list = byVerdict[v];
            const meta = VERDICT_META[v];
            const isOpen = !!openGroup[v];
            return (
              <div key={v}>
                <button className="text-label flex items-center gap-1 text-left w-full" onClick={() => setOpenGroup(p => ({ ...p, [v]: !isOpen }))}>
                  <span className="text-faint">{list.length ? (isOpen ? '▾' : '▸') : '·'}</span>
                  <span className={`font-medium ${meta.cls}`}>{meta.label}</span>
                  <span className="text-faint truncate">— {list.length} · {meta.desc}</span>
                </button>
                {isOpen && list.length > 0 && (
                  <div className="mt-1 overflow-x-auto">
                    <table className="text-label font-mono border-collapse">
                      <thead>
                        <tr className="text-faint text-right">
                          <th className="font-normal text-left px-2 py-0.5">when · what</th>
                          <th className="font-normal px-2 text-left">item — campaign ▸ target / term</th>
                          <th className="font-normal px-2 text-left" title="the value before → the value after">change</th>
                          <th className="font-normal px-2 text-left" title="the SETTLED grading window [T+1,T+7] (SB [T+1,T+14]) — clicks · spend · GP-ROAS · ad net profit">settled result</th>
                          <th className="font-normal px-2 text-left" title="the entity's own record over [T-28,T-1], settled by construction — greyed when there was too little prior traffic to compare">its prior</th>
                          {v === 'REVERSED' && <th className="font-normal px-2 text-left" title="the pre-change value to put back — restore, never go lower">restore</th>}
                          <th className="font-normal px-2 text-left">why</th>
                        </tr>
                      </thead>
                      <tbody>
                        {list.map(r => (
                          <tr key={r.changeId} className="border-t border-border/40">
                            <td className="text-left px-2 py-0.5 whitespace-nowrap">
                              <span className="text-muted">{shortDate(r.changeDate)}</span>
                              <span className="text-faint"> · {ACTION_LABEL[r.actionGroup] ?? r.action.toLowerCase()}</span>
                              <span className={sourceMeta(r.source).cls} title={sourceMeta(r.source).title}> · {r.source.toLowerCase()}</span>
                              {r.supersededInWindow && (
                                <span className="text-amber-400" title={`${r.nLaterChanges ?? 0} later change${r.nLaterChanges === 1 ? '' : 's'} landed on this entity inside the grading window — the result is contaminated, read it as a hint not a verdict`}> · ⚠ superseded</span>
                              )}
                              {r.windowUsed !== 'PRIMARY' && (
                                <span className="text-sky-300" title="thin evidence at T+7, so the window was extended and re-graded at T+21"> · extended</span>
                              )}
                            </td>
                            <ItemCell r={r} />
                            <td className="px-2 text-left whitespace-nowrap">
                              {r.oldValue == null && r.newValue == null
                                ? <span className="text-faint">—</span>
                                : <>
                                    <span className="text-faint">{money(r.oldValue)}</span>
                                    <span className="text-faint"> → </span>
                                    <span className="text-muted">{money(r.newValue)}</span>
                                    {r.pctChange != null && <span className="text-faint"> ({r.pctChange > 0 ? '+' : ''}{r.pctChange.toFixed(0)}%)</span>}
                                    {r.valueKind && <span className="text-faint"> {r.valueKind.toLowerCase()}</span>}
                                  </>}
                            </td>
                            <td className="px-2 text-left whitespace-nowrap" title={r.windowStart ? `window ${r.windowStart} → ${r.windowEnd}${r.winDays ? ` (${r.winDays}d)` : ''}${r.winCpc != null ? ` · CPC ${money(r.winCpc)}` : ''}${r.winOrders != null ? ` · ${r.winOrders} ord` : ''}` : undefined}>
                              {r.winClicks ? (
                                <>
                                  {r.winClicks}c · {money(r.winSpend)} · <span className={roasCls(r.winGpRoas)}>{r.winGpRoas != null ? `${r.winGpRoas.toFixed(2)}×` : '—'}</span>
                                  <span className={npCls(r.winNetProfit)}> · {money(r.winNetProfit)}</span>
                                </>
                              ) : <span className="text-faint">no clicks in the window</span>}
                            </td>
                            <td className={`px-2 text-left whitespace-nowrap ${r.priorAvailable ? '' : 'opacity-50'}`}
                                title={r.priorAvailable ? `prior spend ${money(r.priorSpend)} over [T-28,T-1]` : 'too little prior traffic to compare — this row was judged on the absolute bar alone'}>
                              {r.priorClicks ? (
                                <>
                                  <span className={roasCls(r.priorGpRoas)}>{r.priorGpRoas != null ? `${r.priorGpRoas.toFixed(2)}×` : '—'}</span>
                                  <span className="text-faint"> on {r.priorClicks}c</span>
                                </>
                              ) : <span className="text-faint">no prior</span>}
                            </td>
                            {v === 'REVERSED' && (
                              <td className="px-2 text-left whitespace-nowrap">
                                {r.remedy
                                  ? <span className="text-red-300" title={REMEDY_LABEL[r.remedy] ?? r.remedy}>
                                      {REMEDY_LABEL[r.remedy] ?? r.remedy}{r.remedyValue != null ? ` → ${money(r.remedyValue)}` : ''}
                                    </span>
                                  : <span className="text-faint">—</span>}
                              </td>
                            )}
                            <td className="px-2 text-left text-faint whitespace-normal max-w-[32rem]">{r.verdictReason}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            );
          })}

          <div className="text-label text-subtle">
            Advisory only — nothing here is queued or uploaded. Source: V_CHANGE_SCORECARD (backend).
            Changes younger than their read gate (T+14, SB T+21) are deliberately absent: grading before
            the sales settle under-reads your own change and makes you reverse winners.
            Changes seen on Amazon that OI never logged (usually ones you made by hand in the console) are
            graded too, but they are not listed here or in the morning brief until you decide they should be.
          </div>
        </div>
      )}
    </section>
  );
}

export default ChangeScorecardPanel;
