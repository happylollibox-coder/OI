import { useEffect, useMemo, useState } from 'react';
import { cubeLoad } from '../hooks/useCubeData';
import { apiFetch } from '../utils/apiFetch';
import { fM } from '../utils';
import { splitFamilies, type FamilyWeight, type FamilyRow } from './budgetWaterfall';

// Weekly Run Step-1 — role budget panel (Brand Defense or Product Defense). Ori sets one daily budget for
// the role; it splits across families by the backend allocation (weight). Mirrors the offense panel but
// simpler. Publishes per-family allocation so step 2 tracks the dial. configKey persists to DE_BUDGET_CONFIG.

type RoleFam = FamilyWeight & { spend: number; currentBudget: number; n: number; netRoas: number | null; netProfitDay: number; nUnderbid: number };
const FLOOR = 0;
function num(v: unknown): number { const n = Number(v); return Number.isFinite(n) ? n : 0; }
const npCls = (n: number | null) => n == null ? 'text-faint' : n > 0 ? 'text-emerald-400' : n < 0 ? 'text-red-400' : 'text-muted';
const roasCls = (r: number | null) => r == null ? 'text-faint' : r >= 2.0 ? 'text-emerald-400' : r >= 0.8 ? 'text-amber-400' : 'text-red-400';

export function RoleBudgetPanel({ role, configKey, title, subtitle, showUnderbid = false, onAllocations, selected, onSelect, statusByFamily = {} }:
  { role: string; configKey: string; title: string; subtitle: string; showUnderbid?: boolean; onAllocations?: (m: Record<string, number>) => void;
    selected?: string | null; onSelect?: (fam: string) => void; statusByFamily?: Record<string, { done?: boolean; escalation?: boolean }> }) {
  const [fams, setFams] = useState<RoleFam[] | null>(null);
  const [total, setTotal] = useState<number>(0);
  const [seeded, setSeeded] = useState(false);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    let alive = true;
    setFams(null); setSeeded(false);
    (async () => {
      try {
        const rows = await cubeLoad({
          dimensions: ['RoleBudgetFamily.parentName', 'RoleBudgetFamily.weight', 'RoleBudgetFamily.allocated', 'RoleBudgetFamily.spend7d',
            'RoleBudgetFamily.currentBudget', 'RoleBudgetFamily.n', 'RoleBudgetFamily.adsNetRoas', 'RoleBudgetFamily.adsNetProfitDay', 'RoleBudgetFamily.nUnderbid'],
          filters: [{ member: 'RoleBudgetFamily.role', operator: 'equals', values: [role] }],
        });
        if (!alive) return;
        setFams((rows as Record<string, unknown>[]).map(r => ({
          parentName: String(r['RoleBudgetFamily.parentName'] ?? ''),
          weight: num(r['RoleBudgetFamily.weight']),
          netProfit: num(r['RoleBudgetFamily.allocated']),
          spend: num(r['RoleBudgetFamily.spend7d']),
          currentBudget: num(r['RoleBudgetFamily.currentBudget']),
          n: num(r['RoleBudgetFamily.n']),
          netRoas: r['RoleBudgetFamily.adsNetRoas'] != null ? num(r['RoleBudgetFamily.adsNetRoas']) : null,
          netProfitDay: num(r['RoleBudgetFamily.adsNetProfitDay']),
          nUnderbid: num(r['RoleBudgetFamily.nUnderbid']),
        })));
      } catch { if (alive) setFams([]); }
    })();
    return () => { alive = false; };
  }, [role]);

  useEffect(() => {
    if (fams && !seeded) { setTotal(Math.round(fams.reduce((s, f) => s + f.netProfit, 0))); setSeeded(true); }
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
        body: JSON.stringify({ [configKey]: total }),
      });
      setSaved(res.ok);
    } catch { setSaved(false); } finally { setSaving(false); }
  };

  if (fams === null) return <div className="text-label text-faint mb-4">Loading budget…</div>;

  return (
    <section className="rounded-xl border border-border bg-card p-4 mb-4">
      <div className="flex items-center justify-between mb-3">
        <div className="text-label font-medium text-muted">1 · {title}</div>
        <div className="text-label text-faint">{subtitle} · current budgets total {fM(currentTotal)}</div>
      </div>

      <div className="flex items-center gap-2 mb-3">
        <span className="text-label text-faint">daily budget</span>
        <span className="text-muted">$</span>
        <input type="number" value={total || ''} onChange={e => setTotal(Math.max(0, Number(e.target.value)))}
          className="w-24 bg-transparent border border-border rounded px-2 py-1 font-mono text-body" />
        <span className="text-label text-faint">/day</span>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full text-body">
          <thead><tr className="text-label text-faint text-left border-b border-border">
            <th className="py-1 font-normal">family</th>
            <th className="py-1 font-normal text-right">campaigns</th>
            <th className="py-1 font-normal text-right" title="ad net ROAS = gross profit ÷ ad spend (last 7 full days)">ads net ROAS</th>
            <th className="py-1 font-normal text-right" title="ad net profit per day (last 7 full days)">ads net profit</th>
            <th className="py-1 font-normal text-right" title="ad spend per day (7d avg)">spend</th>
            <th className="py-1 font-normal text-right" title="current Amazon daily budget for this family's campaigns in this pool">current budget</th>
            <th className="py-1 font-normal text-right" title="new budget from the split — tracks the dial">new budget</th>
          </tr></thead>
          <tbody>
            {rows.map(r => {
              const d = dataByFam[r.parentName];
              const st = statusByFamily[r.parentName];
              const isSel = selected === r.parentName;
              return (
                <tr key={r.parentName} onClick={() => onSelect?.(r.parentName)}
                  className={`border-b border-border/50 cursor-pointer ${isSel ? 'bg-blue-500/10' : 'hover:bg-white/5'}`}>
                  <td className="py-1.5">
                    {st?.escalation && <span className="text-red-400 text-[9px] mr-1" title="escalation">●</span>}
                    <span className={isSel ? 'font-semibold text-blue-200' : ''}>{r.parentName}</span>
                    {st?.done && <span className="ml-1 text-emerald-400" title="done this week">✓</span>}
                    {showUnderbid && d && d.nUnderbid > 0 && <span className="text-red-400 text-label ml-1" title={`${d.nUnderbid} keyword${d.nUnderbid > 1 ? 's' : ''} bidding below 1.5× CPC — not owning page 1. Raise in the campaign actions.`}>⚠ {d.nUnderbid} under-bid</span>}
                  </td>
                  <td className="py-1.5 text-right font-mono text-muted">{d?.n ?? '—'}</td>
                  <td className={`py-1.5 text-right font-mono ${roasCls(d?.netRoas ?? null)}`}>{d?.netRoas != null ? `${d.netRoas.toFixed(2)}×` : '—'}</td>
                  <td className={`py-1.5 text-right font-mono ${npCls(d?.netProfitDay ?? null)}`}>{d ? fM(d.netProfitDay) : '—'}</td>
                  <td className="py-1.5 text-right font-mono text-muted">{d ? fM(d.spend) : '—'}</td>
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
            {saving ? 'saving…' : 'save budget'}</button>
        </div>
      </div>
    </section>
  );
}

export default RoleBudgetPanel;
