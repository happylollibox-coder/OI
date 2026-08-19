import { useEffect, useMemo, useState } from 'react';
import { cubeLoadWithMeta } from '../hooks/useCubeData';

// Weekly Run FRONT PAGE, line 1 of the 5-minute read: the run summary strip.
// Spec: architecture/WEEKLY_RUN_UX.md (Phase 6 plan Tasks 5 + 7-drill).
//
// EVERY NUMBER AND EVERY LABEL IS THE VIEW'S (V_RUN_SUMMARY via the RunSummary cube). This file
// does presentational aggregation only: Σ of the rows it renders, and the sanctioned HELD
// grouping — labels starting 'exclude — owned' collapse into one 'ownership' count (the
// constituent labels live in its tooltip); 'review…'/'no-op' rows stay distinct. $/day renders
// on budget labels only — the view emits it nowhere else, and bid-level $/day would be
// invented precision.
//
// Line 3 (UNCHANGED) drills: clicking a class lazy-loads V_RUN_UNCHANGED (RunUnchanged cube)
// filtered to that class, first open only — the strip itself stays a small-table query.
// Non-fatal everywhere: a failed strip is one line, never a blocked page.

type SummaryRow = { rowId: string; section: string; label: string; n: number; dollarsPerDay: number | null; detail: string | null };
type DrillRow = {
  rowId: string; campaignName: string; targetText: string; matchType: string; channel: string;
  settledClk90: number | null; settledRoas90: number | null; recordClass: string | null;
  nextCheckDate: string | null; nextCheckWhat: string | null; whyShort: string;
};

const num = (v: unknown): number | null => (v == null || v === '' ? null : Number(v));
const str = (v: unknown): string | null => (v == null || v === '' ? null : String(v));

// Signed $/day for budget labels — the view's number, display-formatted.
const signedDay = (d: number) => `${d >= 0 ? '+' : '−'}$${Math.abs(d).toFixed(2)}/d`;
// The record cell colors by the VIEW's record_class (the engine's own 1.0/0.6 bands) — never
// by a threshold invented here (feedback_all_logic_in_backend; review 2026-08-16 removed the
// old 1.1/0.7 comparison this file was making on its own).
const recordCls: Record<string, string> = {
  GOOD: 'text-emerald-400', MID: 'text-amber-400', BAD: 'text-red-400', NONE: 'text-faint',
};

const DRILL_CAP = 100;

export function RunSummaryStrip() {
  const [rows, setRows] = useState<SummaryRow[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [openClass, setOpenClass] = useState<string | null>(null);
  // Per-class drill cache — fetched once on first open, kept for the session.
  const [drills, setDrills] = useState<Record<string, DrillRow[] | 'loading' | 'error'>>({});

  useEffect(() => {
    let alive = true;
    cubeLoadWithMeta({
      dimensions: ['RunSummary.rowId', 'RunSummary.section', 'RunSummary.label', 'RunSummary.n',
        'RunSummary.dollarsPerDay', 'RunSummary.detail'],
    }).then(res => {
      if (!alive) return;
      // {data: [], error} = the cube never answered — an empty strip would be a lie (the
      // Revivals lesson, 2026-08-11). Render "unavailable", not zeros.
      if (res.error) { setFailed(true); return; }
      setRows((res.data as Record<string, unknown>[]).map(r => ({
        rowId: String(r['RunSummary.rowId'] ?? ''),
        section: String(r['RunSummary.section'] ?? ''),
        label: String(r['RunSummary.label'] ?? ''),
        n: num(r['RunSummary.n']) ?? 0,
        dollarsPerDay: num(r['RunSummary.dollarsPerDay']),
        detail: str(r['RunSummary.detail']),
      })));
    }).catch(e => {
      console.error('[run-summary] fetch failed:', e);
      if (alive) setFailed(true);
    });
    return () => { alive = false; };
  }, []);

  const { changes, heldOwned, heldOther, unchanged } = useMemo(() => {
    const all = rows ?? [];
    const byN = (a: SummaryRow, b: SummaryRow) => b.n - a.n;
    const held = all.filter(r => r.section === 'HELD').sort(byN);
    return {
      changes: all.filter(r => r.section === 'CHANGES').sort(byN),
      // The sanctioned presentational grouping: ownership excludes fold into one count.
      heldOwned: held.filter(r => r.label.startsWith('exclude — owned')),
      heldOther: held.filter(r => !r.label.startsWith('exclude — owned')),
      unchanged: all.filter(r => r.section === 'UNCHANGED').sort(byN),
    };
  }, [rows]);

  const changesTotal = changes.reduce((s, r) => s + r.n, 0);
  const heldTotal = heldOwned.reduce((s, r) => s + r.n, 0) + heldOther.reduce((s, r) => s + r.n, 0);
  const ownedTotal = heldOwned.reduce((s, r) => s + r.n, 0);
  const unchangedTotal = unchanged.reduce((s, r) => s + r.n, 0);

  const toggleClass = (label: string) => {
    setOpenClass(prev => (prev === label ? null : label));
    if (drills[label]) return;   // fetched (or fetching) already — first open only
    setDrills(p => ({ ...p, [label]: 'loading' }));
    cubeLoadWithMeta({
      dimensions: ['RunUnchanged.rowId', 'RunUnchanged.campaignName', 'RunUnchanged.targetText',
        'RunUnchanged.matchType', 'RunUnchanged.channel', 'RunUnchanged.settledClk90',
        'RunUnchanged.settledRoas90', 'RunUnchanged.recordClass', 'RunUnchanged.nextCheckDate',
        'RunUnchanged.nextCheckWhat', 'RunUnchanged.whyShort'],
      filters: [{ member: 'RunUnchanged.class', operator: 'equals', values: [label] }],
      limit: DRILL_CAP,
    }).then(res => {
      if (res.error) { setDrills(p => ({ ...p, [label]: 'error' })); return; }
      const mapped = (res.data as Record<string, unknown>[]).map(r => ({
        rowId: String(r['RunUnchanged.rowId'] ?? ''),
        campaignName: String(r['RunUnchanged.campaignName'] ?? ''),
        targetText: String(r['RunUnchanged.targetText'] ?? ''),
        matchType: String(r['RunUnchanged.matchType'] ?? ''),
        channel: String(r['RunUnchanged.channel'] ?? ''),
        settledClk90: num(r['RunUnchanged.settledClk90']),
        settledRoas90: num(r['RunUnchanged.settledRoas90']),
        recordClass: str(r['RunUnchanged.recordClass']),
        nextCheckDate: str(r['RunUnchanged.nextCheckDate']),
        nextCheckWhat: str(r['RunUnchanged.nextCheckWhat']),
        whyShort: String(r['RunUnchanged.whyShort'] ?? ''),
      })).sort((a, b) => (b.settledClk90 ?? 0) - (a.settledClk90 ?? 0));
      setDrills(p => ({ ...p, [label]: mapped }));
    }).catch(e => {
      console.error('[run-summary] drill failed:', e);
      setDrills(p => ({ ...p, [label]: 'error' }));
    });
  };

  if (failed) {
    return (
      <div className="mb-3 rounded-xl border border-border bg-card px-4 py-2 text-label text-faint">
        run summary unavailable — the RunSummary cube isn't answering; the sections below still work
      </div>
    );
  }

  const openRow = openClass ? unchanged.find(r => r.label === openClass) : undefined;
  const openDrill = openClass ? drills[openClass] : undefined;

  return (
    <div className="mb-3 rounded-xl border border-border bg-card px-4 py-3 text-label">
      {!rows ? (
        <div className="text-faint">Run summary — loading…</div>
      ) : (
        <div className="flex flex-col gap-1.5">
          {/* line 1 — CHANGES */}
          <div className="flex flex-wrap items-baseline gap-x-1.5 gap-y-0.5">
            <span className="font-mono text-body text-text">{changesTotal}</span>
            <span className="text-muted">changes proposed</span>
            {changes.map(r => (
              <span key={r.rowId} className="whitespace-nowrap" title={r.detail ?? undefined}>
                <span className="text-faint"> · </span>
                <span className="font-mono text-muted">{r.n}</span>{' '}
                <span className="text-muted">{r.label}</span>
                {/* $/day exists on budget moves only — the view's number, never derived here */}
                {r.label.includes('budget') && r.dollarsPerDay != null && (
                  <span className={`font-mono ${r.dollarsPerDay >= 0 ? 'text-emerald-400' : 'text-red-400'}`}> {signedDay(r.dollarsPerDay)}</span>
                )}
              </span>
            ))}
          </div>
          {/* line 2 — HELD (amber): ownership folds, review/no-op stay distinct */}
          <div className="flex flex-wrap items-baseline gap-x-1.5 gap-y-0.5">
            <span className="font-mono text-body text-amber-400">{heldTotal}</span>
            <span className="text-amber-400/80">held</span>
            {ownedTotal > 0 && (
              <span className="whitespace-nowrap" title={heldOwned.map(r => `${r.n} ${r.label}`).join(' · ')}>
                <span className="text-faint"> — </span>
                <span className="font-mono text-amber-400/80">{ownedTotal}</span>{' '}
                <span className="text-amber-400/80">ownership</span>
              </span>
            )}
            {heldOther.map(r => (
              <span key={r.rowId} className="whitespace-nowrap" title={r.detail ?? undefined}>
                <span className="text-faint"> · </span>
                <span className="font-mono text-amber-400/80">{r.n}</span>{' '}
                <span className="text-amber-400/80">{r.label.replace(/^exclude — /, '')}</span>
              </span>
            ))}
          </div>
          {/* line 3 — UNCHANGED (muted; each class opens its row-grain drill) */}
          <div className="flex flex-wrap items-baseline gap-x-1.5 gap-y-0.5">
            <span className="font-mono text-body text-muted">{unchangedTotal}</span>
            <span className="text-faint">unchanged</span>
            {unchanged.map((r, i) => (
              <span key={r.rowId} className="whitespace-nowrap">
                <span className="text-faint">{i === 0 ? ' — ' : ' · '}</span>
                <button onClick={() => toggleClass(r.label)}
                  title={`${r.n} ${r.label} — click for the row-level drill (who, record, next check, why)`}
                  className={openClass === r.label ? 'text-text underline' : 'text-faint hover:text-muted underline decoration-dotted'}>
                  <span className="font-mono">{r.n}</span> {r.label}
                </button>
              </span>
            ))}
          </div>

          {/* the UNCHANGED drill — lazy, first open only */}
          {openClass && (
            <div className="mt-1 border-t border-border/40 pt-2">
              {openDrill === 'loading' || openDrill === undefined ? (
                <div className="text-faint">loading {openClass}…</div>
              ) : openDrill === 'error' ? (
                <div className="text-faint">drill unavailable — the RunUnchanged cube isn't answering</div>
              ) : (
                <div className="overflow-x-auto">
                  <table className="text-label font-mono border-collapse">
                    <thead>
                      <tr className="text-faint text-left">
                        <th className="font-normal px-2 py-0.5">item</th>
                        {/* Ori 2026-08-16 "i do not know what is the window": the header NAMES its
                            window — a label whose window lives only in a tooltip fails the
                            5-second contract (WEEKLY_RUN_UX.md) */}
                        <th className="font-normal px-2" title="clicks · GP-ROAS over the last 90 days, SETTLED ONLY — clicks old enough that all their sales have attributed (SP: click ≥7 days old · SB: ≥14). This is the number verdicts are made on. 1.00× = breakeven after product cost.">settled 90d record</th>
                        <th className="font-normal px-2" title="the state machine's next appointment for this row">next check</th>
                        <th className="font-normal px-2">why</th>
                      </tr>
                    </thead>
                    <tbody>
                      {openDrill.map(d => (
                        <tr key={d.rowId} className="border-t border-border/20">
                          <td className="px-2 py-0.5 whitespace-nowrap">
                            <span className="text-muted">{d.targetText || '(no text)'}</span>
                            <span className="text-faint"> {d.matchType} · {d.channel} · {d.campaignName}</span>
                          </td>
                          <td className="px-2 whitespace-nowrap">
                            {d.settledClk90 ? (
                              <>
                                <span className="text-muted">{d.settledClk90}c</span>
                                <span className="text-faint"> · </span>
                                <span className={recordCls[d.recordClass ?? 'NONE'] ?? 'text-faint'}>{d.settledRoas90 != null ? `${d.settledRoas90.toFixed(2)}×` : '—'}</span>
                              </>
                            ) : <span className="text-faint">no settled clicks</span>}
                          </td>
                          <td className="px-2 whitespace-nowrap text-sky-300" title={d.nextCheckWhat ?? undefined}>{d.nextCheckDate ?? '—'}</td>
                          <td className="px-2 text-faint max-w-[30rem] overflow-hidden text-ellipsis whitespace-nowrap" title={d.whyShort}>{d.whyShort}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  {openRow && openRow.n > openDrill.length && (
                    <div className="text-faint mt-1">showing {openDrill.length} of {openRow.n}</div>
                  )}
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export default RunSummaryStrip;
