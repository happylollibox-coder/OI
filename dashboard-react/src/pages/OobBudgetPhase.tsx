import { useEffect, useState } from 'react';
import { cubeLoad } from '../hooks/useCubeData';

// "Out of budget" technical phase — sits directly below the Coach-logic flowchart on Weekly Run.
// Goal (Ori 2026-07-30): campaigns should never be out of budget, but use almost all their budget.
// Pure presentation: every number, action and reason comes from V_OOB_BUDGET_PHASE via the OobBudget
// cube (the launch controller's dark-gated ladder applied uniformly to SP+SB, launch AND working).
// Spec: architecture/OOB_BUDGET_PHASE.md.

type Row = {
  name: string; channel: string; engine: string; budget: number; spend: number;
  util: number | null; dark: number; roas1: number | null; roasPrev2: number | null;
  daysSince: number | null; action: string; suggested: number | null; reason: string;
};

const num = (v: unknown): number | null => (v == null || v === '' ? null : Number(v));

const ACTION_CLS: Record<string, string> = {
  RAISE_STRONG: 'text-emerald-400',
  RAISE_WEAK: 'text-emerald-400',
  CUT: 'text-red-400',
  HOLD: 'text-muted',
  WATCH: 'text-faint',
};

export function OobBudgetPhase() {
  const [open, setOpen] = useState(false);
  const [rows, setRows] = useState<Row[] | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let alive = true;
    cubeLoad({
      dimensions: [
        'OobBudget.campaignName', 'OobBudget.channel', 'OobBudget.engine',
        'OobBudget.currentBudget', 'OobBudget.spend1d', 'OobBudget.utilization',
        'OobBudget.pctDark', 'OobBudget.roas1d', 'OobBudget.roasPrev2',
        'OobBudget.daysSinceBudgetChange', 'OobBudget.action',
        'OobBudget.suggestedBudget', 'OobBudget.reason',
      ],
    }).then(rs => {
      if (!alive) return;
      const mapped = (rs as Record<string, unknown>[]).map(r => ({
        name: String(r['OobBudget.campaignName'] ?? ''),
        channel: String(r['OobBudget.channel'] ?? ''),
        engine: String(r['OobBudget.engine'] ?? ''),
        budget: num(r['OobBudget.currentBudget']) ?? 0,
        spend: num(r['OobBudget.spend1d']) ?? 0,
        util: num(r['OobBudget.utilization']),
        dark: num(r['OobBudget.pctDark']) ?? 0,
        roas1: num(r['OobBudget.roas1d']),
        roasPrev2: num(r['OobBudget.roasPrev2']),
        daysSince: num(r['OobBudget.daysSinceBudgetChange']),
        action: String(r['OobBudget.action'] ?? ''),
        suggested: num(r['OobBudget.suggestedBudget']),
        reason: String(r['OobBudget.reason'] ?? ''),
      }));
      mapped.sort((a, b) => b.dark - a.dark);
      setRows(mapped);
    }).catch(() => { if (alive) setFailed(true); });
    return () => { alive = false; };
  }, []);

  const n = rows?.length ?? 0;
  const nMoves = rows?.filter(r => r.action.startsWith('RAISE') || r.action === 'CUT').length ?? 0;

  return (
    <div className="mb-3 rounded-md border border-border bg-surface/30 px-3 py-2">
      <button className="text-label flex items-center gap-1" onClick={() => setOpen(o => !o)}>
        <span className="text-faint">{open ? '▾' : '▸'}</span>
        <span className="font-medium text-rose-300">Out of budget</span>
        <span className="text-faint">
          {failed ? '— unavailable' : rows
            ? `— ${n} dark yesterday · ${nMoves} budget moves`
            : '— loading…'}
          {' '}· goal: never out of budget, spend ~all of it
        </span>
      </button>
      {open && rows && (
        <div className="mt-2 overflow-x-auto">
          <table className="text-label font-mono border-collapse">
            <thead>
              <tr className="text-faint text-right">
                <th className="font-normal text-left px-2 py-0.5">campaign</th>
                <th className="font-normal px-2"></th>
                <th className="font-normal px-2">budget</th>
                <th className="font-normal px-2">spent</th>
                <th className="font-normal px-2" title="spend ÷ budget on the last complete day. SB can exceed 100% — Amazon overdelivers SB up to 2× its daily budget">used</th>
                <th className="font-normal px-2" title="share of the day Amazon reported CAMPAIGN_OUT_OF_BUDGET">dark</th>
                <th className="font-normal px-2" title="net ROAS, last complete day (1.0× = breakeven)">last day</th>
                <th className="font-normal px-2" title="net ROAS, the 2 days before">prev-2d</th>
                <th className="font-normal px-2 text-left">action</th>
                <th className="font-normal px-2">budget →</th>
                <th className="font-normal px-2 text-left">why</th>
              </tr>
            </thead>
            <tbody>
              {rows.map(r => (
                <tr key={r.name} className="text-right border-t border-border/40">
                  <td className="text-left px-2 py-0.5 text-body whitespace-nowrap">{r.name}</td>
                  <td className="px-2 text-faint whitespace-nowrap">{r.channel}{r.engine === 'LAUNCH' ? ' · launch' : ''}</td>
                  <td className="px-2 text-muted">${r.budget.toFixed(0)}</td>
                  <td className="px-2 text-muted">${r.spend.toFixed(2)}</td>
                  <td className={`px-2 ${r.util != null && r.util > 1.2 ? 'text-amber-400' : 'text-muted'}`}>{r.util != null ? `${Math.round(r.util * 100)}%` : '—'}</td>
                  <td className={`px-2 ${r.dark > 10 ? 'text-amber-400' : 'text-muted'}`}>{r.dark.toFixed(0)}%</td>
                  <td className="px-2 text-muted">{r.roas1 != null ? `${r.roas1.toFixed(2)}×` : '—'}</td>
                  <td className="px-2 text-muted">{r.roasPrev2 != null ? `${r.roasPrev2.toFixed(2)}×` : '—'}</td>
                  <td className={`px-2 text-left whitespace-nowrap ${ACTION_CLS[r.action] ?? 'text-muted'}`}>{r.action.toLowerCase().replace('_', ' ')}</td>
                  <td className="px-2">{r.suggested != null ? `$${r.suggested.toFixed(2)}` : '—'}</td>
                  <td className="px-2 text-left text-faint whitespace-nowrap">
                    {r.reason}
                    {r.daysSince != null && r.daysSince <= 3 ? ` · budget changed ${r.daysSince}d ago` : ''}
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
