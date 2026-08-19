import { Fragment, useEffect, useRef, useState } from 'react';
import { cubeLoad } from '../hooks/useCubeData';

// Weekly Run v12 (Ori 2026-08-02): paused campaigns in the same table grammar as the Seasonal
// section, but with HISTORIC measures only — nothing spends while paused, so there are no
// actions here. Two variants:
//   SEASONAL_PAUSED — paused seasonal campaigns, showing ONLY the relevant season's last
//                     occurrence (e.g. Easter 2026 window) — the revival evidence.
//   OTHER           — paused non-seasonal campaigns: last month · last 3 months · last year.
// Pure presentation over V_PAUSED_CAMPAIGN_HISTORY via the PausedHistory cube.

type Row = {
  campaignId: string; campaignName: string; channel: string; budget: number;
  seasonHoliday: string; seasonStart: string; seasonEnd: string;
  targetText: string | null;
  clicksM1: number; spendM1: number; roasM1: number | null;
  clicksM3: number; spendM3: number; roasM3: number | null;
  clicksY1: number; spendY1: number; ordersY1: number; roasY1: number | null;
  clicksSeason: number; spendSeason: number; ordersSeason: number; roasSeason: number | null;
};

const num = (v: unknown): number | null => (v == null || v === '' ? null : Number(v));

const roasCls = (v: number | null) =>
  v == null ? 'text-faint' : v >= 1.1 ? 'text-emerald-400' : v >= 0.7 ? 'text-amber-400' : 'text-red-400';

function Win({ clk, sp, roas }: { clk: number; sp: number; roas: number | null }) {
  if (!clk && !sp) return <span className="text-faint">—</span>;
  return (
    <span className="whitespace-nowrap">
      {clk}c · ${sp.toFixed(2)} · <span className={roasCls(roas)}>{roas != null ? `${roas.toFixed(2)}×` : '—'}</span>
    </span>
  );
}

export function PausedHistoryPhase({ variant }: { variant: 'SEASONAL_PAUSED' | 'OTHER' }) {
  const [open, setOpen] = useState(false);
  const [openCamps, setOpenCamps] = useState<Record<string, boolean>>({});
  const [rows, setRows] = useState<Row[] | null>(null);
  const [failed, setFailed] = useState(false);
  const seasonal = variant === 'SEASONAL_PAUSED';

  // LAZY SECTION (WEEKLY_RUN_UX.md: "the 17 criteria sections as LAZY drill-downs — a section
  // fetches ONLY on first expand"). Every section fetching on mount fired ~17 ceiling-view
  // queries at page open, 40–120s each cold — the "why is it not loading" incident. The front
  // page carries the first read; this one earns its query on the click.
  const fetchedRef = useRef(false);
  useEffect(() => {
    if (!open || fetchedRef.current) return;
    fetchedRef.current = true;
    let alive = true;
    cubeLoad({
      dimensions: [
        'PausedHistory.campaignId', 'PausedHistory.campaignName', 'PausedHistory.channel', 'PausedHistory.budget',
        'PausedHistory.seasonHoliday', 'PausedHistory.seasonStart', 'PausedHistory.seasonEnd', 'PausedHistory.targetText',
        'PausedHistory.clicksM1', 'PausedHistory.spendM1', 'PausedHistory.roasM1',
        'PausedHistory.clicksM3', 'PausedHistory.spendM3', 'PausedHistory.roasM3',
        'PausedHistory.clicksY1', 'PausedHistory.spendY1', 'PausedHistory.ordersY1', 'PausedHistory.roasY1',
        'PausedHistory.clicksSeason', 'PausedHistory.spendSeason', 'PausedHistory.ordersSeason', 'PausedHistory.roasSeason',
      ],
      filters: [
        { member: 'PausedHistory.isSeasonal', operator: 'equals', values: [seasonal ? 'true' : 'false'] },
        { member: 'PausedHistory.isDefense', operator: 'equals', values: ['false'] },
      ],
    }).then(rs => {
      if (!alive) return;
      setRows((rs as Record<string, unknown>[]).map(r => ({
        campaignId: String(r['PausedHistory.campaignId'] ?? ''),
        campaignName: String(r['PausedHistory.campaignName'] ?? ''),
        channel: String(r['PausedHistory.channel'] ?? 'SP'),
        budget: num(r['PausedHistory.budget']) ?? 0,
        seasonHoliday: String(r['PausedHistory.seasonHoliday'] ?? ''),
        seasonStart: String(r['PausedHistory.seasonStart'] ?? ''),
        seasonEnd: String(r['PausedHistory.seasonEnd'] ?? ''),
        targetText: r['PausedHistory.targetText'] == null || r['PausedHistory.targetText'] === '' ? null : String(r['PausedHistory.targetText']),
        clicksM1: num(r['PausedHistory.clicksM1']) ?? 0, spendM1: num(r['PausedHistory.spendM1']) ?? 0, roasM1: num(r['PausedHistory.roasM1']),
        clicksM3: num(r['PausedHistory.clicksM3']) ?? 0, spendM3: num(r['PausedHistory.spendM3']) ?? 0, roasM3: num(r['PausedHistory.roasM3']),
        clicksY1: num(r['PausedHistory.clicksY1']) ?? 0, spendY1: num(r['PausedHistory.spendY1']) ?? 0,
        ordersY1: num(r['PausedHistory.ordersY1']) ?? 0, roasY1: num(r['PausedHistory.roasY1']),
        clicksSeason: num(r['PausedHistory.clicksSeason']) ?? 0, spendSeason: num(r['PausedHistory.spendSeason']) ?? 0,
        ordersSeason: num(r['PausedHistory.ordersSeason']) ?? 0, roasSeason: num(r['PausedHistory.roasSeason']),
      })));
    }).catch(e => { console.error('[paused-history] fetch failed:', e); if (alive) setFailed(true); });
    return () => { alive = false; };
  }, [open, seasonal]);

  // campaign rollup rows carry the header; keyword rows nest under them
  const camps = (rows ?? []).filter(r => r.targetText === null)
    .sort((a, b) => (seasonal ? b.spendSeason - a.spendSeason : b.spendM3 - a.spendM3 || b.spendY1 - a.spendY1));
  const kwsOf = (id: string) => (rows ?? []).filter(r => r.campaignId === id && r.targetText !== null)
    .sort((a, b) => (seasonal ? b.spendSeason - a.spendSeason : b.spendY1 - a.spendY1));

  const title = seasonal ? 'Seasonal Paused' : 'Other';
  const desc = seasonal
    ? 'paused for their season — showing the relevant season, last occurrence; re-enable in Amazon when it nears'
    : 'paused, not seasonal — historic record only; nothing spends here';

  return (
    <div className="mb-3 rounded-md border border-border bg-surface/30 px-3 py-2">
      <div className="flex items-center gap-1">
        <button className="text-label flex items-center gap-1 flex-1 min-w-0" onClick={() => setOpen(o => !o)}>
          <span className="text-faint">{open ? '▾' : '▸'}</span>
          <span className="font-medium text-amber-300">{title}</span>
          <span className="text-faint truncate">
            {failed ? '— unavailable' : rows ? `— ${camps.length} campaigns · ${desc}` : (open || fetchedRef.current) ? '— loading…' : '— expand to load'}
          </span>
        </button>
      </div>
      {open && rows && (
        <div className="mt-2 overflow-x-auto">
          <table className="text-label font-mono border-collapse">
            <thead>
              <tr className="text-faint text-right">
                <th className="font-normal text-left px-2 py-0.5">item — campaign ▸ keyword</th>
                {seasonal ? (
                  <th className="font-normal px-2 text-left" title="the campaign's season, most recent occurrence — clicks · spend · est. net ROAS">season (last occurrence)</th>
                ) : (
                  <>
                    <th className="font-normal px-2 text-left" title="last 28 days — clicks · spend · est. net ROAS">last month</th>
                    <th className="font-normal px-2 text-left" title="last 91 days">last 3 mo</th>
                    <th className="font-normal px-2 text-left" title="last 365 days">last year</th>
                  </>
                )}
              </tr>
            </thead>
            <tbody>
              {camps.map(c => {
                const expanded = !!openCamps[c.campaignId];
                const kws = kwsOf(c.campaignId);
                return (
                  <Fragment key={c.campaignId}>
                    <tr className="border-t border-border/40">
                      <td className="text-left px-2 py-0.5 text-body whitespace-nowrap">
                        <button className="text-faint pr-1" onClick={() => setOpenCamps(p => ({ ...p, [c.campaignId]: !expanded }))}>{kws.length ? (expanded ? '▾' : '▸') : '·'}</button>
                        <span className="text-amber-400 pr-1">⏸</span>{c.campaignName}
                        <span className="text-faint text-label"> {c.channel} · ${c.budget.toFixed(0)} bud · paused{seasonal && c.seasonHoliday ? ` · ${c.seasonHoliday} ${c.seasonStart} → ${c.seasonEnd}` : ''}</span>
                      </td>
                      {seasonal ? (
                        <td className="px-2 text-left"><Win clk={c.clicksSeason} sp={c.spendSeason} roas={c.roasSeason} />{c.ordersSeason > 0 && <span className="text-faint"> · {c.ordersSeason} ord</span>}</td>
                      ) : (
                        <>
                          <td className="px-2 text-left"><Win clk={c.clicksM1} sp={c.spendM1} roas={c.roasM1} /></td>
                          <td className="px-2 text-left"><Win clk={c.clicksM3} sp={c.spendM3} roas={c.roasM3} /></td>
                          <td className="px-2 text-left"><Win clk={c.clicksY1} sp={c.spendY1} roas={c.roasY1} /></td>
                        </>
                      )}
                    </tr>
                    {expanded && kws.map(k => (
                      <tr key={k.targetText} className="border-t border-border/20">
                        <td className="text-left px-2 py-0.5 pl-8 whitespace-nowrap text-muted">{k.targetText}</td>
                        {seasonal ? (
                          <td className="px-2 text-left"><Win clk={k.clicksSeason} sp={k.spendSeason} roas={k.roasSeason} />{k.ordersSeason > 0 && <span className="text-faint"> · {k.ordersSeason} ord</span>}</td>
                        ) : (
                          <>
                            <td className="px-2 text-left"><Win clk={k.clicksM1} sp={k.spendM1} roas={k.roasM1} /></td>
                            <td className="px-2 text-left"><Win clk={k.clicksM3} sp={k.spendM3} roas={k.roasM3} /></td>
                            <td className="px-2 text-left"><Win clk={k.clicksY1} sp={k.spendY1} roas={k.roasY1} /></td>
                          </>
                        )}
                      </tr>
                    ))}
                  </Fragment>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
