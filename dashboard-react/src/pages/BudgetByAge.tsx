import { useEffect, useMemo, useState } from 'react';
import { cubeLoad } from '../hooks/useCubeData';
import { fM } from '../utils';

// Weekly Run — "Budget by age" split. Mirrors "Budget by strategy": campaigns bucketed by age with the
// same columns (spend by ROAS tier, CPC, net profit, budgets). Acts as a FILTER — selecting a bucket
// narrows step 2 (budget) and step 4 (bids) to that age, exactly like the strategy split. No inline
// editing here: budget is done in step 2, bids in step 4. Reads V_BUDGET_STEP1_AGE (cube AgeBudgetStep1).

/** "All ages" = no age filter. Not a real bucket, so never sent to a cube filter. */
export const ALL_AGES = '__ALL_AGES__';

const AGE_ORDER = ['NEW', '1-3MO', '4-9MO', '10MO+', 'UNKNOWN'];
export const AGE_LABEL: Record<string, string> = {
  NEW: 'New (0–20 days)', '1-3MO': '1–3 months', '4-9MO': '4–9 months', '10MO+': '10 months+', UNKNOWN: 'Unknown age',
};

function num(v: unknown): number { const n = Number(v); return Number.isFinite(n) ? n : 0; }

type AgeRow = {
  ageBucket: string; nCampaigns: number; losing: number; margin: number; winning: number; total: number;
  lastCpc: number | null; adsNetProfit: number | null; currentBudget: number | null; allocated: number;
};

export function BudgetByAge({ selectedAge, onSelectAge }:
  { selectedAge?: string | null; onSelectAge?: (bucket: string) => void } = {}) {
  const [rows, setRows] = useState<AgeRow[] | null>(null);

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const res = await cubeLoad({ dimensions: ['AgeBudgetStep1.ageBucket', 'AgeBudgetStep1.nCampaigns',
          'AgeBudgetStep1.losingSpend7d', 'AgeBudgetStep1.marginSpend7d', 'AgeBudgetStep1.winningSpend7d',
          'AgeBudgetStep1.totalSpend7d', 'AgeBudgetStep1.lastCpc7d', 'AgeBudgetStep1.adsNetProfitAvg',
          'AgeBudgetStep1.currentBudget', 'AgeBudgetStep1.allocatedDaily'] });
        if (!alive) return;
        setRows((res as Record<string, unknown>[]).map(r => ({
          ageBucket: String(r['AgeBudgetStep1.ageBucket'] ?? ''),
          nCampaigns: num(r['AgeBudgetStep1.nCampaigns']),
          losing: num(r['AgeBudgetStep1.losingSpend7d']), margin: num(r['AgeBudgetStep1.marginSpend7d']),
          winning: num(r['AgeBudgetStep1.winningSpend7d']), total: num(r['AgeBudgetStep1.totalSpend7d']),
          lastCpc: r['AgeBudgetStep1.lastCpc7d'] != null ? num(r['AgeBudgetStep1.lastCpc7d']) : null,
          adsNetProfit: r['AgeBudgetStep1.adsNetProfitAvg'] != null ? num(r['AgeBudgetStep1.adsNetProfitAvg']) : null,
          currentBudget: r['AgeBudgetStep1.currentBudget'] != null ? num(r['AgeBudgetStep1.currentBudget']) : null,
          allocated: num(r['AgeBudgetStep1.allocatedDaily']),
        })).sort((a, b) => {
          const ia = AGE_ORDER.indexOf(a.ageBucket), ib = AGE_ORDER.indexOf(b.ageBucket);
          return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib);
        }));
      } catch { if (alive) setRows([]); }
    })();
    return () => { alive = false; };
  }, []);

  const totals = useMemo(() => (rows ?? []).reduce((a, s) => ({
    n: a.n + s.nCampaigns, adNet: a.adNet + (s.adsNetProfit ?? 0),
    losing: a.losing + s.losing, margin: a.margin + s.margin, winning: a.winning + s.winning,
    total: a.total + s.total, cur: a.cur + (s.currentBudget ?? 0), alloc: a.alloc + s.allocated,
  }), { n: 0, adNet: 0, losing: 0, margin: 0, winning: 0, total: 0, cur: 0, alloc: 0 }), [rows]);

  if (!rows || rows.length === 0) return null;
  const allSel = !selectedAge || selectedAge === ALL_AGES;

  return (
    <div className="mt-6">
      <div className="text-label font-medium text-muted mb-1">Budget by age</div>
      <div className="text-label text-faint mb-1">
        campaigns bucketed by age · same 7-full-day averages as above · click a bucket to filter budget (step 2) &amp; bids (step 4) — New (0–20d) is driven by the launch controller
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-body">
          <thead><tr className="text-label text-faint text-left border-b border-border">
            <th className="py-1 font-normal">age</th>
            <th className="py-1 font-normal text-right">campaigns</th>
            <th className="py-1 font-normal text-right" title="ad-attributed net profit per day">ad net profit</th>
            <th className="py-1 font-normal text-right" title="actual CPC (spend ÷ clicks), spend-weighted across the bucket's campaigns">CPC</th>
            <th className="py-1 font-normal text-right" title="spend on losing campaigns (net ROAS < 0.8)">losing spend</th>
            <th className="py-1 font-normal text-right" title="spend on margin campaigns (net ROAS 0.8–2)">margin spend</th>
            <th className="py-1 font-normal text-right" title="spend on winning campaigns (net ROAS ≥ 2)">winning spend</th>
            <th className="py-1 font-normal text-right" title="total ad spend">spend</th>
            <th className="py-1 font-normal text-right" title="current Amazon daily budget across the bucket">current budget</th>
            <th className="py-1 font-normal text-right" title="the waterfall's proposed daily budget for this bucket">new budget</th>
          </tr></thead>
          <tbody>
            <tr onClick={() => onSelectAge?.(ALL_AGES)}
              className={`border-b border-border cursor-pointer font-semibold ${allSel ? 'bg-blue-500/10' : 'hover:bg-white/5'}`}>
              <td className="py-1.5"><span className={allSel ? 'text-blue-200' : ''}>All</span></td>
              <td className="py-1.5 text-right font-mono text-muted">{totals.n}</td>
              <td className={`py-1.5 text-right font-mono ${totals.adNet < 0 ? 'text-red-400' : 'text-emerald-400'}`}>{fM(totals.adNet)}</td>
              <td className="py-1.5 text-right font-mono text-muted">—</td>
              <td className="py-1.5 text-right font-mono text-red-400">{fM(totals.losing / 7)}</td>
              <td className="py-1.5 text-right font-mono text-amber-400">{fM(totals.margin / 7)}</td>
              <td className="py-1.5 text-right font-mono text-emerald-400">{fM(totals.winning / 7)}</td>
              <td className="py-1.5 text-right font-mono">{fM(totals.total / 7)}</td>
              <td className="py-1.5 text-right font-mono text-muted">{fM(totals.cur)}</td>
              <td className="py-1.5 text-right font-mono text-blue-300">{fM(totals.alloc)}</td>
            </tr>
            {rows.map(s => {
              const isSel = selectedAge === s.ageBucket;
              const isNew = s.ageBucket === 'NEW';
              return (
                <tr key={s.ageBucket} onClick={() => onSelectAge?.(s.ageBucket)}
                  className={`border-b border-border/50 cursor-pointer ${isSel ? 'bg-blue-500/10' : 'hover:bg-white/5'}`}>
                  <td className="py-1.5">
                    <span className={isSel ? 'font-semibold text-blue-200' : isNew ? 'text-blue-200' : ''}>{AGE_LABEL[s.ageBucket] ?? s.ageBucket}</span>
                    {isNew && <span className="ml-2 text-label text-faint">launch controller</span>}
                  </td>
                  <td className="py-1.5 text-right font-mono text-muted">{s.nCampaigns}</td>
                  <td className={`py-1.5 text-right font-mono ${s.adsNetProfit == null ? 'text-faint' : s.adsNetProfit < 0 ? 'text-red-400' : 'text-emerald-400'}`}>{s.adsNetProfit != null ? fM(s.adsNetProfit) : '—'}</td>
                  <td className="py-1.5 text-right font-mono text-muted">{s.lastCpc != null ? `$${s.lastCpc.toFixed(2)}` : '—'}</td>
                  <td className="py-1.5 text-right font-mono text-red-400">{s.losing ? fM(s.losing / 7) : '—'}</td>
                  <td className="py-1.5 text-right font-mono text-amber-400">{s.margin ? fM(s.margin / 7) : '—'}</td>
                  <td className="py-1.5 text-right font-mono text-emerald-400">{s.winning ? fM(s.winning / 7) : '—'}</td>
                  <td className="py-1.5 text-right font-mono">{s.total ? fM(s.total / 7) : '—'}</td>
                  <td className="py-1.5 text-right font-mono text-muted">{s.currentBudget != null ? fM(s.currentBudget) : '—'}</td>
                  <td className="py-1.5 text-right font-mono text-blue-300">{fM(s.allocated)}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
