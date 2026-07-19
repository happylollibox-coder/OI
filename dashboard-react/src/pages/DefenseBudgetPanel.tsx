import { useEffect, useMemo, useState } from 'react';
import { cubeLoad } from '../hooks/useCubeData';
import { apiFetch } from '../utils/apiFetch';
import { fM } from '../utils';
import { splitFamilies, type FamilyWeight, type FamilyRow } from './budgetWaterfall';

// Weekly Run Step-1 — DEFENSE panel (PPC defense pool). Ori sets one defense daily budget; it splits
// across families by defense spend-need (weight = the backend defense allocation). Mirrors the offense
// panel but simpler: no proven% dial, no losing/margin/winning tiers. Pure preview + the settable cap;
// the canonical split is V_CAMPAIGN_BUDGET_BASE. Publishes per-family defense budget so step 2 tracks the dial.

type DefFam = FamilyWeight & { defenseSpend: number; currentBudget: number; nDefense: number; netRoas: number | null; netProfitDay: number; nUnderbid: number };
const FLOOR = 0;   // defense splits purely by need (no family floor), matching the backend
const npCls = (n: number | null) => n == null ? 'text-faint' : n > 0 ? 'text-emerald-400' : n < 0 ? 'text-red-400' : 'text-muted';
const roasCls = (r: number | null) => r == null ? 'text-faint' : r >= 2.5 ? 'text-emerald-400' : r >= 0.8 ? 'text-amber-400' : 'text-red-400';

function num(v: unknown): number { const n = Number(v); return Number.isFinite(n) ? n : 0; }

export function DefenseBudgetPanel({ onAllocations }: { onAllocations?: (m: Record<string, number>) => void } = {}) {
  const [fams, setFams] = useState<DefFam[] | null>(null);
  const [total, setTotal] = useState<number>(0);
  const [seeded, setSeeded] = useState(false);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const rows = await cubeLoad({
          dimensions: ['DefenseBudgetFamily.parentName', 'DefenseBudgetFamily.weight', 'DefenseBudgetFamily.defenseAllocated',
            'DefenseBudgetFamily.defenseSpend7d', 'DefenseBudgetFamily.defenseCurrentBudget', 'DefenseBudgetFamily.nDefense',
            'DefenseBudgetFamily.adsNetRoas', 'DefenseBudgetFamily.adsNetProfitDay', 'DefenseBudgetFamily.nUnderbid'],
        });
        if (!alive) return;
        setFams((rows as Record<string, unknown>[]).map(r => ({
          parentName: String(r['DefenseBudgetFamily.parentName'] ?? ''),
          weight: num(r['DefenseBudgetFamily.weight']),
          netProfit: num(r['DefenseBudgetFamily.defenseAllocated']),
          defenseSpend: num(r['DefenseBudgetFamily.defenseSpend7d']),
          currentBudget: num(r['DefenseBudgetFamily.defenseCurrentBudget']),
          nDefense: num(r['DefenseBudgetFamily.nDefense']),
          netRoas: r['DefenseBudgetFamily.adsNetRoas'] != null ? num(r['DefenseBudgetFamily.adsNetRoas']) : null,
          netProfitDay: num(r['DefenseBudgetFamily.adsNetProfitDay']),
          nUnderbid: num(r['DefenseBudgetFamily.nUnderbid']),
        })));
      } catch { if (alive) setFams([]); }
    })();
    return () => { alive = false; };
  }, []);

  // Seed the dial from the current defense_total (= Σ backend defense allocation).
  useEffect(() => {
    if (fams && !seeded) {
      setTotal(Math.round(fams.reduce((s, f) => s + f.netProfit, 0)));
      setSeeded(true);
    }
  }, [fams, seeded]);

  const rows: FamilyRow[] = useMemo(() => {
    if (!fams) return [];
    return splitFamilies(fams, total || 0, FLOOR)
      .map(a => ({ parentName: a.parentName, allocated: a.allocated, source: 'WATERFALL' as const }))
      .sort((a, b) => b.allocated - a.allocated);
  }, [fams, total]);

  const dataByFam = useMemo(() => Object.fromEntries((fams ?? []).map(f => [f.parentName, f])), [fams]);
  const allocated = useMemo(() => rows.reduce((s, r) => s + r.allocated, 0), [rows]);
  const currentTotal = useMemo(() => (fams ?? []).reduce((s, f) => s + f.currentBudget, 0), [fams]);

  useEffect(() => { setSaved(false); }, [total]);
  useEffect(() => { onAllocations?.(Object.fromEntries(rows.map(r => [r.parentName, r.allocated]))); }, [rows, onAllocations]);

  const save = async () => {
    setSaving(true);
    try {
      const res = await apiFetch('/api/budget', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ defense_total_daily: total }),
      });
      setSaved(res.ok);
    } catch { setSaved(false); } finally { setSaving(false); }
  };

  if (fams === null) return <div className="text-label text-faint mb-4">Loading defense budget…</div>;

  return (
    <section className="rounded-xl border border-border bg-card p-4 mb-4">
      <div className="flex items-center justify-between mb-3">
        <div className="text-label font-medium text-muted">1 · Defense budget — hold the line</div>
        <div className="text-label text-faint">split across families by defense spend-need · current defense budgets total {fM(currentTotal)}</div>
      </div>

      <div className="flex items-center gap-2 mb-3">
        <span className="text-label text-faint">defense daily budget</span>
        <span className="text-muted">$</span>
        <input type="number" value={total || ''} onChange={e => setTotal(Math.max(0, Number(e.target.value)))}
          className="w-24 bg-transparent border border-border rounded px-2 py-1 font-mono text-body" />
        <span className="text-label text-faint">/day — protect where you’re actively defending; idle defense is trimmed in step 2</span>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full text-body">
          <thead><tr className="text-label text-faint text-left border-b border-border">
            <th className="py-1 font-normal">family</th>
            <th className="py-1 font-normal text-right" title="number of defense campaigns">defense campaigns</th>
            <th className="py-1 font-normal text-right" title="defense ad net ROAS = gross profit ÷ ad spend (last 7 full days)">ads net ROAS</th>
            <th className="py-1 font-normal text-right" title="defense ad net profit per day (last 7 full days)">ads net profit</th>
            <th className="py-1 font-normal text-right" title="defense ad spend per day (7d avg)">defense spend</th>
            <th className="py-1 font-normal text-right" title="current Amazon daily budget across this family's defense campaigns">current budget</th>
            <th className="py-1 font-normal text-right" title="new defense budget from the split — tracks the dial">new budget</th>
          </tr></thead>
          <tbody>
            {rows.map(r => {
              const d = dataByFam[r.parentName];
              return (
                <tr key={r.parentName} className="border-b border-border/50">
                  <td className="py-1.5">{r.parentName}{d && d.nUnderbid > 0 && <span className="text-red-400 text-label ml-1" title={`${d.nUnderbid} defense keyword${d.nUnderbid > 1 ? 's' : ''} bidding below 1.5× CPC — not owning page 1. Raise in step 2 → Actions.`}>⚠ {d.nUnderbid} under-bid</span>}</td>
                  <td className="py-1.5 text-right font-mono text-muted">{d?.nDefense ?? '—'}</td>
                  <td className={`py-1.5 text-right font-mono ${roasCls(d?.netRoas ?? null)}`}>{d?.netRoas != null ? `${d.netRoas.toFixed(2)}×` : '—'}</td>
                  <td className={`py-1.5 text-right font-mono ${npCls(d?.netProfitDay ?? null)}`}>{d ? fM(d.netProfitDay) : '—'}</td>
                  <td className="py-1.5 text-right font-mono text-muted">{d ? fM(d.defenseSpend) : '—'}</td>
                  <td className="py-1.5 text-right font-mono text-faint">{d ? fM(d.currentBudget) : '—'}</td>
                  <td className="py-1.5 text-right font-mono text-blue-300">{fM(r.allocated)}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <div className="flex items-center justify-between mt-2 text-label">
        <span className="text-faint">allocated across families</span>
        <div className="flex items-center gap-3">
          <span className="font-mono text-muted">{fM(allocated)} / {fM(total || 0)}</span>
          {saved && <span className="text-emerald-400">saved ✓</span>}
          <button onClick={save} disabled={saving || !total}
            className="px-3 py-1 rounded border border-blue-500/50 bg-blue-500/10 text-blue-300 disabled:opacity-40">
            {saving ? 'saving…' : 'save defense budget'}</button>
        </div>
      </div>
    </section>
  );
}

export default DefenseBudgetPanel;
