import { useEffect, useMemo, useState } from 'react';
import { cubeLoad } from '../hooks/useCubeData';
import { apiFetch } from '../utils/apiFetch';
import { fM } from '../utils';
import { splitFamilies, applyOverrides, type FamilyWeight, type FamilyRow } from './budgetWaterfall';
import { BudgetByAge } from './BudgetByAge';

// Weekly Run Step 1 — the budget waterfall header. Ori sets one total daily ad budget; it splits across
// families by real net profit (winners take it, losers sit at the floor). The suggested total is
// profit-shaped: proven (net ROAS ≥ 0.8) spend is `provenPct`% of the budget (default = current split,
// best-practice preset = 80% per the 80/20 rule), leaving the rest as new-campaign headroom. The split
// recomputes live client-side (mirrors V_FAMILY_BUDGET_ALLOCATION); losers are auto-starved by the floor.

// Only the two fields that still seed the total — the rest of BudgetSuggestion fed the dial + suggestion
// text that were removed above the table.
type Sug = { recentAvgDailySpend: number; currentTotalSetting: number };
type FamData = FamilyWeight & { source: string; losing: number; margin: number; winning: number; total: number; lastCpc: number | null; currentBudget: number | null; adsNetProfit: number | null };
const FLOOR = 10;   // family_floor_daily (matches DE_BUDGET_CONFIG)
/** Sentinel for the table's "All" row — selecting it works the whole week's campaigns at once.
 *  Not a real parent_name, so it must never be sent to a cube filter. */
export const ALL_FAMILIES = '__ALL__';
/** Same idea for the strategy split: "All strategies" = no strategy_role filter. */
export const ALL_STRATEGIES = '__ALL_STRATEGIES__';

/** Strategy grain (cross-pool): the campaign's assigned strategy, Auto split out from Intent. */
export const STRATEGY_LABEL: Record<string, string> = {
  EXACT_BOOST: 'Exact Boost', BRAND_DEFENSE: 'Brand Defense', PRODUCT_DEFENSE: 'Product Defense',
  COMPETITOR: 'Competitors', INTENT: 'Intent', AUTO: 'Auto', OTHER: 'Other',
};
const STRATEGY_ORDER = ['EXACT', 'PHRASE', 'BRAND_DEFENSE', 'PRODUCT_DEFENSE', 'COMPETITOR', 'BROAD_SP', 'BROAD_VIDEO', 'BROAD_SPOTLIGHT', 'AUTO', 'OTHER'];

type StratRow = {
  strategyRole: string; nCampaigns: number; losing: number; margin: number; winning: number; total: number;
  lastCpc: number | null; adsNetProfit: number | null; currentBudget: number | null; allocated: number;
};

function num(v: unknown): number { const n = Number(v); return Number.isFinite(n) ? n : 0; }

export function BudgetStep1({ onAllocations, familyEdits = {}, mode = 'offense', selected, onSelect, statusByFamily = {},
  selectedStrategy, onSelectStrategy, selectedAge, onSelectAge }:
  { onAllocations?: (m: Record<string, number>) => void; familyEdits?: Record<string, number>; mode?: 'offense' | 'defense';
    selected?: string | null; onSelect?: (fam: string) => void; statusByFamily?: Record<string, { done?: boolean; escalation?: boolean }>;
    selectedStrategy?: string | null; onSelectStrategy?: (role: string) => void;
    selectedAge?: string | null; onSelectAge?: (bucket: string) => void } = {}) {
  const [sug, setSug] = useState<Sug | null>(null);
  const [fams, setFams] = useState<FamData[] | null>(null);
  const [strats, setStrats] = useState<StratRow[] | null>(null);
  const [total, setTotal] = useState<number>(0);
  const [overrides, setOverrides] = useState<Record<string, number>>({});
  const [seeded, setSeeded] = useState(false);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const [sRows, fRows, stRows] = await Promise.all([
          cubeLoad({ dimensions: ['BudgetSuggestion.recentAvgDailySpend', 'BudgetSuggestion.currentTotalSetting'] }),
          cubeLoad({ dimensions: ['FamilyBudgetStep1.parentName', 'FamilyBudgetStep1.weight', 'FamilyBudgetStep1.businessNetProfitAvg',
            'FamilyBudgetStep1.adsNetProfitAvg', 'FamilyBudgetStep1.allocatedDaily', 'FamilyBudgetStep1.source',
            'FamilyBudgetStep1.losingSpend7d', 'FamilyBudgetStep1.marginSpend7d', 'FamilyBudgetStep1.winningSpend7d',
            'FamilyBudgetStep1.totalSpend7d', 'FamilyBudgetStep1.lastCpc7d', 'FamilyBudgetStep1.currentBudget'] }),
          cubeLoad({ dimensions: ['StrategyBudgetStep1.strategyRole', 'StrategyBudgetStep1.nCampaigns',
            'StrategyBudgetStep1.losingSpend7d', 'StrategyBudgetStep1.marginSpend7d', 'StrategyBudgetStep1.winningSpend7d',
            'StrategyBudgetStep1.totalSpend7d', 'StrategyBudgetStep1.lastCpc7d', 'StrategyBudgetStep1.adsNetProfitAvg',
            'StrategyBudgetStep1.currentBudget', 'StrategyBudgetStep1.allocatedDaily'] }),
        ]);
        if (!alive) return;
        const s = (sRows as Record<string, unknown>[])[0];
        if (s) setSug({
          recentAvgDailySpend: num(s['BudgetSuggestion.recentAvgDailySpend']),
          currentTotalSetting: num(s['BudgetSuggestion.currentTotalSetting']),
        });
        setFams((fRows as Record<string, unknown>[]).map(r => ({
          parentName: String(r['FamilyBudgetStep1.parentName'] ?? ''),
          weight: num(r['FamilyBudgetStep1.weight']),
          netProfit: r['FamilyBudgetStep1.businessNetProfitAvg'] != null ? num(r['FamilyBudgetStep1.businessNetProfitAvg']) : num(r['FamilyBudgetStep1.adsNetProfitAvg']),
          adsNetProfit: r['FamilyBudgetStep1.adsNetProfitAvg'] != null ? num(r['FamilyBudgetStep1.adsNetProfitAvg']) : null,
          source: String(r['FamilyBudgetStep1.source'] ?? 'WATERFALL'),
          losing: num(r['FamilyBudgetStep1.losingSpend7d']), margin: num(r['FamilyBudgetStep1.marginSpend7d']),
          winning: num(r['FamilyBudgetStep1.winningSpend7d']), total: num(r['FamilyBudgetStep1.totalSpend7d']),
          lastCpc: r['FamilyBudgetStep1.lastCpc7d'] != null ? num(r['FamilyBudgetStep1.lastCpc7d']) : null,
          currentBudget: r['FamilyBudgetStep1.currentBudget'] != null ? num(r['FamilyBudgetStep1.currentBudget']) : null,
        })));
        setStrats((stRows as Record<string, unknown>[]).map(r => ({
          strategyRole: String(r['StrategyBudgetStep1.strategyRole'] ?? ''),
          nCampaigns: num(r['StrategyBudgetStep1.nCampaigns']),
          losing: num(r['StrategyBudgetStep1.losingSpend7d']), margin: num(r['StrategyBudgetStep1.marginSpend7d']),
          winning: num(r['StrategyBudgetStep1.winningSpend7d']), total: num(r['StrategyBudgetStep1.totalSpend7d']),
          lastCpc: r['StrategyBudgetStep1.lastCpc7d'] != null ? num(r['StrategyBudgetStep1.lastCpc7d']) : null,
          adsNetProfit: r['StrategyBudgetStep1.adsNetProfitAvg'] != null ? num(r['StrategyBudgetStep1.adsNetProfitAvg']) : null,
          currentBudget: r['StrategyBudgetStep1.currentBudget'] != null ? num(r['StrategyBudgetStep1.currentBudget']) : null,
          allocated: num(r['StrategyBudgetStep1.allocatedDaily']),
        })).sort((a, b) => {
          const ia = STRATEGY_ORDER.indexOf(a.strategyRole), ib = STRATEGY_ORDER.indexOf(b.strategyRole);
          return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib);
        }));
      } catch { if (alive) { setSug(null); setFams([]); setStrats([]); } }
    })();
    return () => { alive = false; };
  }, []);

  // seed the total from the backend once loaded. The dial that used to set this is gone (Ori 2026-07-16:
  // "the total budget is not relevant"), so the total is now purely the backend's own setting — the split
  // below still comes from it until the bottom-up redesign lands (architecture/CAMPAIGN_LAUNCH_RAMP.md).
  useEffect(() => {
    if (sug && !seeded) {
      setTotal(sug.currentTotalSetting || sug.recentAvgDailySpend || 0);
      setSeeded(true);
    }
  }, [sug, seeded]);

  const rows: FamilyRow[] = useMemo(() => {
    if (!fams) return [];
    const base = splitFamilies(fams, total || 0, FLOOR).map(a => ({ parentName: a.parentName, allocated: a.allocated, source: 'WATERFALL' as const }));
    return applyOverrides(base, overrides).sort((a, b) => b.allocated - a.allocated);
  }, [fams, total, overrides]);

  // Effective family budget = your campaign-level edits (step 2, bottom-up) when present, else the
  // waterfall's top-down split. The grand total re-sums to this so editing a campaign moves the total.
  const effectiveFam = (r: FamilyRow) => familyEdits[r.parentName] ?? r.allocated;
  const committed = useMemo(() => rows.reduce((s, r) => s + (familyEdits[r.parentName] ?? r.allocated), 0), [rows, familyEdits]);
  const overCommitted = committed > (total || 0) + 0.5;
  const hasRealEdits = rows.some(r => familyEdits[r.parentName] != null && Math.abs(familyEdits[r.parentName] - r.allocated) > 0.5);
  const dataByFam = useMemo(() => Object.fromEntries((fams ?? []).map(f => [f.parentName, f])), [fams]);

  // "All" — the table's first row and the default selection, so the week opens on every campaign at once
  // rather than one family at a time. Summed across families; CPC is spend-weighted (a plain average of
  // per-family CPCs would misreport, since families differ hugely in click volume).
  const allRow = useMemo(() => {
    const fs = fams ?? [];
    if (!fs.length) return null;
    const sum = (pick: (f: FamData) => number | null) => fs.reduce((s, f) => s + (pick(f) ?? 0), 0);
    const spend7d = sum(f => f.total);
    const cpcWeighted = spend7d > 0
      ? fs.reduce((s, f) => s + (f.lastCpc ?? 0) * f.total, 0) / spend7d
      : null;
    return {
      netProfit: sum(f => f.netProfit),
      adsNetProfit: fs.every(f => f.adsNetProfit == null) ? null : sum(f => f.adsNetProfit),
      lastCpc: cpcWeighted,
      losing: sum(f => f.losing), margin: sum(f => f.margin), winning: sum(f => f.winning), total: spend7d,
      currentBudget: fs.every(f => f.currentBudget == null) ? null : sum(f => f.currentBudget),
      newBudget: rows.reduce((s, r) => s + effectiveFam(r), 0),
    };
  }, [fams, rows, familyEdits]);   // eslint-disable-line react-hooks/exhaustive-deps -- effectiveFam reads familyEdits

  // any edit invalidates the "saved" flag
  useEffect(() => { setSaved(false); }, [total, overrides]);

  // publish the live family allocations (updates as the dial/total change) so the plan detail can
  // re-scale its per-cell new budget in step — no cube round-trip, no waiting for save.
  useEffect(() => { onAllocations?.(Object.fromEntries(rows.map(r => [r.parentName, r.allocated]))); }, [rows, onAllocations]);

  // Persist the chosen total + family overrides to the backend so the waterfall actually uses them.
  const save = async () => {
    setSaving(true);
    try {
      const res = await apiFetch('/api/budget', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ total_daily_budget: total, family_overrides: overrides }),
      });
      setSaved(res.ok);
    } catch { setSaved(false); } finally { setSaving(false); }
  };

  if (sug === null || fams === null) return <div className="text-label text-faint mb-4">Loading budget…</div>;

  // Defense mode — the offense waterfall panel doesn't apply. Defense is split across defense campaigns by
  // spend-need (backend defense_total_daily); reviewed/trimmed per family in step 2 below.
  if (mode === 'defense') {
    return (
      <section className="rounded-xl border border-border bg-card p-4 mb-4">
        <div className="text-label font-medium text-muted mb-1">1 · Defense budget — hold the line</div>
        <p className="text-label text-subtle">
          Your <span className="text-blue-300">defense</span> budget is split across defense campaigns by spend-need — fund where you’re actively defending, flag idle/losing defense to trim. Winners hold #1 (the coach’s brand-defense bid-raise). Review and adjust per family in step 2 below.
          <span className="text-faint"> (Settable defense dial + per-family split — next.)</span>
        </p>
      </section>
    );
  }

  return (
    <section className="rounded-xl border border-border bg-card p-4 mb-4">
      <div className="text-label font-medium text-muted mb-3">1 · Budget by family</div>

      {/* family split */}
      <div className="text-label text-faint mb-1">net profit, CPC &amp; spend columns are a daily average of the last 7 full days · budgets are current / proposed</div>
      <div className="overflow-x-auto">
        <table className="w-full text-body">
          <thead><tr className="text-label text-faint text-left border-b border-border">
            <th className="py-1 font-normal">family</th>
            <th className="py-1 font-normal text-right" title="real business net profit incl organic — the budget-split basis (this is what decides each family's budget)">net profit (incl organic)</th>
            <th className="py-1 font-normal text-right" title="ad-attributed net profit per day — this is what the step-2 offense campaigns sum to (often negative before the organic halo)">ad net profit</th>
            <th className="py-1 font-normal text-right" title="actual CPC (spend ÷ clicks)">CPC</th>
            <th className="py-1 font-normal text-right" title="campaign spend on losing campaigns (net ROAS < 0.8)">losing spend</th>
            <th className="py-1 font-normal text-right" title="campaign spend on margin campaigns (net ROAS 0.8–2.5)">margin spend</th>
            <th className="py-1 font-normal text-right" title="campaign spend on winning campaigns (net ROAS ≥ 2)">winning spend</th>
            <th className="py-1 font-normal text-right" title="total campaign ad spend">spend</th>
            <th className="py-1 font-normal text-right" title="current Amazon daily budget for this family (right now)">current budget</th>
            <th className="py-1 font-normal text-right" title="new daily budget from the split — tracks the proven% dial">new budget</th>
            <th className="py-1 font-normal text-right">override</th>
          </tr></thead>
          <tbody>
            {allRow && (() => {
              const isSel = selected === ALL_FAMILIES;
              const cell = (v: number | null, cls = '') => <td className={`py-1.5 text-right font-mono ${cls}`}>{v != null ? fM(v) : '—'}</td>;
              return (
                <tr onClick={() => onSelect?.(ALL_FAMILIES)}
                  className={`border-b border-border cursor-pointer font-semibold ${isSel ? 'bg-blue-500/10' : 'hover:bg-white/5'}`}>
                  <td className="py-1.5"><span className={isSel ? 'text-blue-200' : ''}>All</span></td>
                  {cell(allRow.netProfit, allRow.netProfit < 0 ? 'text-red-400' : 'text-emerald-400')}
                  {cell(allRow.adsNetProfit, allRow.adsNetProfit == null ? 'text-faint' : allRow.adsNetProfit < 0 ? 'text-red-400' : 'text-emerald-400')}
                  <td className="py-1.5 text-right font-mono text-muted">{allRow.lastCpc != null ? `$${allRow.lastCpc.toFixed(2)}` : '—'}</td>
                  {cell(allRow.losing / 7, 'text-red-400')}
                  {cell(allRow.margin / 7, 'text-amber-400')}
                  {cell(allRow.winning / 7, 'text-emerald-400')}
                  {cell(allRow.total / 7)}
                  {cell(allRow.currentBudget, 'text-muted')}
                  {cell(allRow.newBudget, 'text-blue-300')}
                  <td />
                </tr>
              );
            })()}
            {rows.map(r => {
              const d = dataByFam[r.parentName];
              const np = d?.netProfit ?? null;
              const anp = d?.adsNetProfit ?? null;
              const st = statusByFamily[r.parentName];
              const isSel = selected === r.parentName;
              return (
                <tr key={r.parentName} onClick={() => onSelect?.(r.parentName)}
                  className={`border-b border-border/50 cursor-pointer ${isSel ? 'bg-blue-500/10' : 'hover:bg-white/5'}`}>
                  <td className="py-1.5">
                    {st?.escalation && <span className="text-red-400 text-[9px] mr-1" title="escalation">●</span>}
                    <span className={isSel ? 'font-semibold text-blue-200' : ''}>{r.parentName}</span>
                    {st?.done && <span className="ml-1 text-emerald-400" title="done this week">✓</span>}
                    {r.source === 'MANUAL' && <span className="ml-1 text-label text-blue-300">·manual</span>}
                  </td>
                  <td className={`py-1.5 text-right font-mono ${np != null && np < 0 ? 'text-red-400' : 'text-emerald-400'}`}>{np != null ? fM(np) : '—'}</td>
                  <td className={`py-1.5 text-right font-mono ${anp == null ? 'text-faint' : anp < 0 ? 'text-red-400' : 'text-emerald-400'}`}>{anp != null ? fM(anp) : '—'}</td>
                  <td className="py-1.5 text-right font-mono text-muted">{d?.lastCpc != null ? `$${d.lastCpc.toFixed(2)}` : '—'}</td>
                  <td className="py-1.5 text-right font-mono text-red-400">{d?.losing ? fM(d.losing / 7) : '—'}</td>
                  <td className="py-1.5 text-right font-mono text-amber-400">{d?.margin ? fM(d.margin / 7) : '—'}</td>
                  <td className="py-1.5 text-right font-mono text-emerald-400">{d?.winning ? fM(d.winning / 7) : '—'}</td>
                  <td className="py-1.5 text-right font-mono">{d?.total ? fM(d.total / 7) : '—'}</td>
                  <td className="py-1.5 text-right font-mono text-muted">{d?.currentBudget != null ? fM(d.currentBudget) : '—'}</td>
                  {(() => {
                    const edited = familyEdits[r.parentName] != null && Math.abs(familyEdits[r.parentName] - r.allocated) > 0.5;
                    return (
                      <td className="py-1.5 text-right font-mono text-blue-300"
                        title={edited ? `waterfall split ${fM(r.allocated)} · adjusted to ${fM(familyEdits[r.parentName])} by your step-2 campaign edits` : undefined}>
                        {fM(effectiveFam(r))}{edited && <span className="text-amber-400 ml-0.5" title="reflects your step-2 campaign edits">✎</span>}
                      </td>
                    );
                  })()}
                  <td className="py-1.5 text-right" onClick={e => e.stopPropagation()}>
                    <input type="number" placeholder="—" value={overrides[r.parentName] ?? ''}
                      onChange={e => setOverrides(o => { const n = { ...o }; if (e.target.value === '') delete n[r.parentName]; else n[r.parentName] = Number(e.target.value); return n; })}
                      className="w-16 bg-transparent border border-border rounded px-1.5 py-0.5 font-mono text-label text-right" />
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <div className="flex items-center justify-between mt-2 text-label">
        <span className="text-faint">allocated across families{hasRealEdits ? ' (incl. your step-2 campaign edits)' : ''}</span>
        <div className="flex items-center gap-3">
          <span className={`font-mono ${overCommitted ? 'text-red-400' : 'text-muted'}`}>
            {fM(committed)} / {fM(total || 0)}{overCommitted && ' · over budget'}
          </span>
          {saved && <span className="text-emerald-400">saved ✓</span>}
          <button onClick={save} disabled={saving || !total}
            title={overCommitted ? 'over your total — your campaign edits (step 2) exceed the total; this saves the total + family overrides, campaign edits go to the bulksheet' : undefined}
            className="px-3 py-1 rounded border border-emerald-500/50 bg-emerald-500/10 text-emerald-300 disabled:opacity-40">
            {saving ? 'saving…' : 'save budget'}</button>
        </div>
      </div>

      {/* ── Budget by strategy (Coverage roles) — the second, independent slice of step 1 ──
          Family and strategy intersect: All + Auto = every auto campaign; LolliME + Auto = LolliME's.
          Rolled up backend-side (V_BUDGET_STEP1_STRATEGY) from the same per-campaign new_budget the
          step-2 table reads, so the two can never disagree. */}
      {strats && strats.length > 0 && (
        <div className="mt-6">
          <div className="text-label font-medium text-muted mb-1">Budget by strategy</div>
          <div className="text-label text-faint mb-1">
            by assigned strategy, all pools · brand &amp; product defense included (their budgets also have their own PPC-mode panels) · same 7-full-day averages as above
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-body">
              <thead><tr className="text-label text-faint text-left border-b border-border">
                <th className="py-1 font-normal">strategy</th>
                <th className="py-1 font-normal text-right">campaigns</th>
                <th className="py-1 font-normal text-right" title="ad-attributed net profit per day">ad net profit</th>
                <th className="py-1 font-normal text-right" title="actual CPC (spend ÷ clicks), spend-weighted across the role's campaigns">CPC</th>
                <th className="py-1 font-normal text-right" title="spend on losing campaigns (net ROAS < 0.8)">losing spend</th>
                <th className="py-1 font-normal text-right" title="spend on margin campaigns (net ROAS 0.8–2)">margin spend</th>
                <th className="py-1 font-normal text-right" title="spend on winning campaigns (net ROAS ≥ 2)">winning spend</th>
                <th className="py-1 font-normal text-right" title="total ad spend">spend</th>
                <th className="py-1 font-normal text-right" title="current Amazon daily budget across this role's campaigns">current budget</th>
                <th className="py-1 font-normal text-right" title="the waterfall's proposed daily budget for this role">new budget</th>
              </tr></thead>
              <tbody>
                {(() => {
                  const totals = strats.reduce((a, s) => ({
                    n: a.n + s.nCampaigns, adNet: a.adNet + (s.adsNetProfit ?? 0),
                    losing: a.losing + s.losing, margin: a.margin + s.margin, winning: a.winning + s.winning,
                    total: a.total + s.total, cur: a.cur + (s.currentBudget ?? 0), alloc: a.alloc + s.allocated,
                  }), { n: 0, adNet: 0, losing: 0, margin: 0, winning: 0, total: 0, cur: 0, alloc: 0 });
                  const isSel = !selectedStrategy || selectedStrategy === ALL_STRATEGIES;
                  return (
                    <tr onClick={() => onSelectStrategy?.(ALL_STRATEGIES)}
                      className={`border-b border-border cursor-pointer font-semibold ${isSel ? 'bg-blue-500/10' : 'hover:bg-white/5'}`}>
                      <td className="py-1.5"><span className={isSel ? 'text-blue-200' : ''}>All</span></td>
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
                  );
                })()}
                {strats.map(s => {
                  const isSel = selectedStrategy === s.strategyRole;
                  return (
                    <tr key={s.strategyRole} onClick={() => onSelectStrategy?.(s.strategyRole)}
                      className={`border-b border-border/50 cursor-pointer ${isSel ? 'bg-blue-500/10' : 'hover:bg-white/5'}`}>
                      <td className="py-1.5"><span className={isSel ? 'font-semibold text-blue-200' : ''}>{STRATEGY_LABEL[s.strategyRole] ?? s.strategyRole}</span></td>
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
      )}

      {/* Budget by age — sibling of Budget by strategy; selecting a bucket filters step 2 + step 4 */}
      <BudgetByAge selectedAge={selectedAge} onSelectAge={onSelectAge} />
    </section>
  );
}
