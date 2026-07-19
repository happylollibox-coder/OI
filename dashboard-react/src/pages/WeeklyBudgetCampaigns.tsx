import { useEffect, useMemo, useState } from 'react';
import { cubeLoad } from '../hooks/useCubeData';
import { useDoQueue } from '../hooks/useDoQueue';
import { fM } from '../utils';
import { ALL_FAMILIES, ALL_STRATEGIES, STRATEGY_LABEL } from './BudgetStep1';
import { ALL_AGES, AGE_LABEL } from './BudgetByAge';

// Weekly Run — per-family Step-2 Budget table, driven by the PPC mode toggle (two independent pools):
//   • OFFENSE — offense campaigns split the family's offense budget by net ROAS tier (Winning/Margin/Losing),
//     tracking the live Step-1 dial.
//   • DEFENSE — defense campaigns split the family's defense budget (defense_total by spend-need); idle/losing
//     defense is highlighted to trim. Winners hold position (bids handled by the coach's BRAND_DEFENSE raise).
// Same layout both modes. Ori edits any campaign and queues it; the family total re-sums. Pure presentation.

type PpcMode = 'offense' | 'brand_defense' | 'product_defense';
const MODE_ROLE: Record<PpcMode, string> = { offense: 'OFFENSE', brand_defense: 'BRAND_DEFENSE', product_defense: 'PRODUCT_DEFENSE' };
type CampBudRow = {
  id: string; name: string; type: string; tier: string; role: string; rampDay: number | null; rampDays: number | null;
  netRoas: number | null; netProfitDay: number | null; spendDay: number | null; lastCpc: number | null;
  currentBudget: number | null; newBudget: number | null; isFloor: boolean; isDefense: boolean;
};

const num = (v: unknown): number | null => v == null ? null : Number(v);
const npCls = (n: number | null) => n == null ? 'text-faint' : n > 0 ? 'text-emerald-400' : n < 0 ? 'text-red-400' : 'text-muted';
const roasCls = (r: number | null) => r == null ? 'text-faint' : r >= 2.0 ? 'text-emerald-400' : r >= 0.8 ? 'text-amber-400' : 'text-red-400';
const round2 = (n: number) => Math.round(n * 100) / 100;

// Tier meta, framed per mode (offense = ROI; defense = hold-the-line).
// NEW is listed first in both modes: a campaign in its launch-ramp grace has no ROAS verdict yet, so it
// belongs beside the judged tiers rather than inside them. Its budget comes from the ramp
// (architecture/CAMPAIGN_LAUNCH_RAMP.md), not the waterfall.
const NEW_TIER = { key: 'NEW', label: 'New', cls: 'text-violet-400', border: 'border-violet-500/40',
  desc: 'inside the launch-ramp grace — budget set by the ramp ($10 start, +10% on a maxed profitable day); not judged on ROAS yet' };
const TIERS = {
  offense: [
    NEW_TIER,
    { key: 'WINNING', label: 'Winning', cls: 'text-emerald-400', border: 'border-emerald-500/40', desc: 'net ROAS ≥ 2× — scale, give it more room' },
    { key: 'MARGIN',  label: 'Margin',  cls: 'text-blue-400',    border: 'border-blue-500/40',    desc: 'net ROAS 0.8–2× — profitable & steady, hold at spend +10%' },
    { key: 'LOSING',  label: 'Losing',  cls: 'text-red-400',     border: 'border-red-500/40',     desc: 'net ROAS < 0.8× — cut to the floor' },
  ],
  defense: [
    NEW_TIER,
    { key: 'WINNING', label: 'Dominating', cls: 'text-emerald-400', border: 'border-emerald-500/40', desc: 'holding & converting (≥ 2×) — keep it #1' },
    { key: 'MARGIN',  label: 'Holding',    cls: 'text-blue-400',    border: 'border-blue-500/40',    desc: 'defending at thin margin (0.8–2×) — hold' },
    { key: 'LOSING',  label: 'Idle / losing', cls: 'text-red-400',  border: 'border-red-500/40',     desc: 'not converting / barely spending — trim or pause' },
  ],
} as const;

export function WeeklyBudgetCampaigns({ family, strategy = ALL_STRATEGIES, ageBucket = ALL_AGES, liveAlloc, onFamilyTotal, mode = 'offense' }:
  { family: string; strategy?: string; ageBucket?: string; liveAlloc: number | null; onFamilyTotal?: (family: string, total: number) => void; mode?: PpcMode }) {
  const [rows, setRows] = useState<CampBudRow[] | null>(null);
  const [drafts, setDrafts] = useState<Record<string, number>>({});   // explicit user edits ($/day)
  const doQueue = useDoQueue();

  useEffect(() => {
    let alive = true;
    setRows(null); setDrafts({});
    (async () => {
      try {
        const r = await cubeLoad({
          dimensions: ['CampaignBudgetStep1.campaignId', 'CampaignBudgetStep1.campaignName', 'CampaignBudgetStep1.campaignType',
            'CampaignBudgetStep1.tier', 'CampaignBudgetStep1.netRoas', 'CampaignBudgetStep1.netProfitDay', 'CampaignBudgetStep1.spendDay',
            'CampaignBudgetStep1.lastCpc', 'CampaignBudgetStep1.currentBudget', 'CampaignBudgetStep1.newBudget',
            'CampaignBudgetStep1.isFloor', 'CampaignBudgetStep1.isDefense', 'CampaignBudgetStep1.role',
            'CampaignBudgetStep1.strategyRole', 'CampaignBudgetStep1.ageBucket',
            'CampaignBudgetStep1.rampDay', 'CampaignBudgetStep1.rampDays'],
          // Family and strategy are independent filters that intersect. Each sentinel means "no filter"
          // — neither is a real parent_name / strategy_role, so they must never reach the cube.
          filters: [
            ...(family === ALL_FAMILIES ? [] : [{ member: 'CampaignBudgetStep1.parentName', operator: 'equals' as const, values: [family] }]),
            ...(strategy === ALL_STRATEGIES ? [] : [{ member: 'CampaignBudgetStep1.strategyCategory', operator: 'equals' as const, values: [strategy] }]),
            ...(ageBucket === ALL_AGES ? [] : [{ member: 'CampaignBudgetStep1.ageBucket', operator: 'equals' as const, values: [ageBucket] }]),
          ],
        });
        if (!alive) return;
        setRows((r as Record<string, unknown>[]).map(x => ({
          id: String(x['CampaignBudgetStep1.campaignId'] ?? ''), name: String(x['CampaignBudgetStep1.campaignName'] ?? ''),
          type: String(x['CampaignBudgetStep1.campaignType'] ?? 'SP'), tier: String(x['CampaignBudgetStep1.tier'] ?? 'LOSING'),
          rampDay: x['CampaignBudgetStep1.rampDay'] != null ? num(x['CampaignBudgetStep1.rampDay']) : null,
          rampDays: x['CampaignBudgetStep1.rampDays'] != null ? num(x['CampaignBudgetStep1.rampDays']) : null,
          role: String(x['CampaignBudgetStep1.role'] ?? 'OFFENSE'),
          netRoas: num(x['CampaignBudgetStep1.netRoas']), netProfitDay: num(x['CampaignBudgetStep1.netProfitDay']),
          spendDay: num(x['CampaignBudgetStep1.spendDay']), lastCpc: num(x['CampaignBudgetStep1.lastCpc']),
          currentBudget: num(x['CampaignBudgetStep1.currentBudget']), newBudget: num(x['CampaignBudgetStep1.newBudget']),
          isFloor: x['CampaignBudgetStep1.isFloor'] === true || x['CampaignBudgetStep1.isFloor'] === 'true',
          isDefense: x['CampaignBudgetStep1.isDefense'] === true || x['CampaignBudgetStep1.isDefense'] === 'true',
        })));
      } catch { if (alive) setRows([]); }
    })();
    return () => { alive = false; };
  }, [family, strategy, ageBucket]);

  const isDefenseMode = mode !== 'offense';   // brand or product defense — highlight idle/losing
  const targetRole = MODE_ROLE[mode];
  // Only this mode's campaigns are shown/managed here.
  // Pools unified — the cube already scopes by family/strategy/age, so show every campaign returned
  // (offense + defense). The old r.role === targetRole filter hid defense campaigns.
  const modeRows = useMemo(() => (rows ?? []), [rows]);
  const modeBaseSum = useMemo(() => modeRows.reduce((s, r) => s + (r.newBudget ?? 0), 0), [modeRows]);
  const modeNetSum = useMemo(() => modeRows.reduce((s, r) => s + Math.max(r.netProfitDay ?? 0, 0), 0), [modeRows]);
  // Both pools track their Step-1 dial (liveAlloc): offense = total-budget panel, defense = defense panel.
  const modeTarget = liveAlloc != null ? liveAlloc : modeBaseSum;
  const weight = (r: CampBudRow) =>
    modeBaseSum > 0.01 ? (r.newBudget ?? 0) / modeBaseSum
    : modeNetSum > 0.01 ? Math.max(r.netProfitDay ?? 0, 0) / modeNetSum
    : (modeRows.length ? 1 / modeRows.length : 0);
  const scaledNew = (r: CampBudRow) => modeTarget * weight(r);
  const budgetValue = (r: CampBudRow) => drafts[r.id] ?? scaledNew(r);
  const famTotal = useMemo(() => modeRows.reduce((s, r) => s + budgetValue(r), 0), [modeRows, drafts, modeTarget, modeBaseSum]);
  const losingTotal = useMemo(() => modeRows.filter(r => r.tier === 'LOSING').reduce((s, r) => s + budgetValue(r), 0), [modeRows, drafts, modeTarget, modeBaseSum]);
  // Report the family's live total up (offense only — the Step-1 grand total is the offense pool).
  // Suppressed in two cases, both of which would make Step 1 lie:
  //   • the "All" sentinel — Step 1 keys these by family and sums them, so an __ALL__ entry would
  //     double-count every campaign into the grand total;
  //   • a strategy filter — famTotal is then only that role's campaigns, so reporting it would show
  //     the family's whole budget as having shrunk to (say) just its Auto slice.
  const hasRows = !!(rows && rows.length);
  const isAll = family === ALL_FAMILIES;
  const isStrategyFiltered = strategy !== ALL_STRATEGIES;
  const isAgeFiltered = ageBucket !== ALL_AGES;
  const reportTotal = hasRows && !isDefenseMode && !isAll && !isStrategyFiltered && !isAgeFiltered;
  useEffect(() => { if (reportTotal) onFamilyTotal?.(family, famTotal); }, [famTotal, reportTotal, family, onFamilyTotal]);

  // ── Queue (shared Do queue → bulksheet) ──
  const budgetItem = (r: CampBudRow, newBud: number) => ({
    search_term: '', action: newBud > (r.currentBudget ?? 0) ? 'GUARDIAN_BUDGET_INCREASE' : 'GUARDIAN_BUDGET_DECREASE',
    campaign: r.name, campaign_id: r.id, ad_group_id: '', targeting: '', keyword_id: '', match_type: '',
    target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0, current_bid: null, recommended_bid: null,
    campaign_type: r.type, product: r.name, spend: 0, orders: 0, cpc: 0, conv_rate: 0,
    current_budget: r.currentBudget, recommended_budget: newBud, source: 'COACH' as const,
  });
  const queued = (id: string) => doQueue.items.some(i => i.campaign_id === id && i.action.includes('BUDGET'));
  const toggle = (r: CampBudRow) => {
    const ex = doQueue.items.find(i => i.campaign_id === r.id && i.action.includes('BUDGET'));
    if (ex) doQueue.removeItem(ex.id); else doQueue.addItem(budgetItem(r, round2(budgetValue(r))));
  };

  const target = liveAlloc != null ? liveAlloc : modeBaseSum;
  const overTarget = target != null && famTotal > target + 0.005;
  // Brand Defense = hold-the-line tiers; Offense + Product Defense = ROI tiers (product-defense is ROI-managed).
  const tiers = mode === 'brand_defense' ? TIERS.defense : TIERS.offense;
  const modeLabel = mode === 'brand_defense' ? 'brand defense' : mode === 'product_defense' ? 'product defense' : 'offense';

  const campRow = (r: CampBudRow) => {
    const q = queued(r.id);
    const losing = r.tier === 'LOSING';
    return (
      <tr key={r.id} className={`border-t border-border/50 ${losing && isDefenseMode ? 'bg-red-500/5' : ''}`}>
        <td className="py-1 pr-2 text-muted max-w-[24rem] truncate" title={r.name}>
          {r.name}<span className="text-faint"> · {r.type}</span>
          {r.rampDay != null && r.rampDays != null && (
            <span className="text-violet-400" title="on the launch ramp — its budget and bids come from the ramp until the grace ends, then the coacher takes over">
              {' '}· day {r.rampDay} of {r.rampDays}
            </span>
          )}
          {losing && isDefenseMode && <span className="text-red-400" title="idle/losing defense — trim or pause to redirect the defense budget"> · ⚠ trim?</span>}
        </td>
        <td className="py-1 text-right font-mono"><span className={roasCls(r.netRoas)}>{r.netRoas != null ? `${r.netRoas.toFixed(2)}×` : '—'}</span></td>
        <td className="py-1 text-right font-mono"><span className={npCls(r.netProfitDay)}>{r.netProfitDay != null ? fM(r.netProfitDay) : '—'}</span></td>
        <td className="py-1 text-right font-mono text-muted">{fM(r.spendDay)}</td>
        <td className="py-1 text-right font-mono text-muted">{r.lastCpc != null ? `$${r.lastCpc.toFixed(2)}` : '—'}</td>
        <td className="py-1 text-right font-mono text-faint">{r.currentBudget != null ? fM(r.currentBudget) : '—'}</td>
        <td className="py-1 text-right whitespace-nowrap">
          <span className="text-faint">$</span>
          <input type="number" min={0} step={1} value={Number(budgetValue(r).toFixed(2))}
            onChange={e => setDrafts(p => ({ ...p, [r.id]: Math.max(0, Number(e.target.value) || 0) }))}
            className="w-20 font-mono text-right bg-surface/40 border border-border rounded px-1.5 py-0.5 focus:outline-none focus:ring-1 focus:ring-blue-500/40" />
        </td>
        <td className="py-1 pl-2 text-right">
          <button onClick={() => toggle(r)} title="queue this budget for the bulksheet"
            className={`px-2 py-0.5 rounded border ${q ? 'border-emerald-500/40 text-emerald-400' : 'border-border text-muted hover:bg-white/5'}`}>{q ? '✓' : 'queue'}</button>
        </td>
      </tr>
    );
  };

  const headRow = (
    <tr className="text-faint text-left">
      <th className="font-normal py-1">campaign</th>
      <th className="font-normal py-1 text-right" title="net ROAS = gross profit ÷ ad spend, last 7 full days">net ROAS</th>
      <th className="font-normal py-1 text-right" title="ad net profit per day, last 7 days">net profit</th>
      <th className="font-normal py-1 text-right" title="campaign ad spend per day, last 7 days">spend</th>
      <th className="font-normal py-1 text-right" title="cost per click, last 7 days">CPC</th>
      <th className="font-normal py-1 text-right" title="current daily budget on Amazon">current</th>
      <th className="font-normal py-1 text-right" title="the pool's waterfall split — edit to override">new budget</th>
      <th className="font-normal py-1"></th>
    </tr>
  );

  return (
    <section className="rounded-xl border border-border bg-card p-4">
      <div className="text-label font-medium text-muted mb-1">
        2 · Budget — {modeLabel} allocation for {isAll ? 'all families' : family}
        {isStrategyFiltered && <span className="text-blue-300"> · {STRATEGY_LABEL[strategy] ?? strategy} only</span>}
        {isAgeFiltered && <span className="text-blue-300"> · {AGE_LABEL[ageBucket] ?? ageBucket} only</span>}
      </div>
      <p className="text-label text-subtle mb-3">
        {mode === 'brand_defense'
          ? <>Your <span className="text-blue-300">brand-defense</span> budget, split by spend-need. Winners hold #1 (bid ≥ 1.5× CPC); idle/losing defense is flagged to trim. Columns are per-day (last 7 full days).</>
          : mode === 'product_defense'
          ? <>Your <span className="text-violet-300">product-defense</span> budget — each campaign starts at $30 to learn the best product-on-product pairings, then ROI decides. Idle/losing is flagged to trim. Columns are per-day.</>
          : <>Your <span className="text-amber-300">offense</span> budget, split across offense campaigns by net ROAS. Edit any campaign and <span className="text-muted">queue</span> it — the family total re-sums. Columns are per-day (last 7 full days). Tiers by 7-day net ROAS (gross profit ÷ ad spend): <span className="text-red-400">losing &lt; 0.8×</span> · <span className="text-blue-400">margin 0.8–2×</span> · <span className="text-emerald-400">winning ≥ 2×</span>; a campaign in its first 20 days is <span className="text-violet-400">New</span> (no verdict yet — budget from the launch ramp).</>}
      </p>

      <div className={`flex items-center justify-between text-label mb-3 px-2.5 py-1.5 rounded-md border ${overTarget ? 'border-red-500/40 bg-red-500/5' : 'border-border'}`}>
        <span className="text-faint">{isDefenseMode ? 'defense budget = Σ campaigns' : 'family budget = Σ campaigns'}</span>
        <span className="font-mono">
          <span className={overTarget ? 'text-red-400' : (isDefenseMode ? 'text-blue-300' : 'text-amber-300')}>{fM(famTotal)}/day</span>
          {target != null && <span className="text-faint"> · Step-1 target {fM(target)}{overTarget ? <span className="text-red-400"> ({fM(famTotal - target)} over)</span> : ''}</span>}
          {isDefenseMode && losingTotal > 0.5 && <span className="text-red-400"> · ⚠ {fM(losingTotal)}/day idle/losing — trim</span>}
        </span>
      </div>

      {rows === null ? <div className="text-label text-faint">Loading campaigns…</div>
        : modeRows.length === 0 ? <div className="text-label text-subtle">No {modeLabel} campaigns for this product.</div>
        : (
          <div className="overflow-x-auto">
            <div className="flex flex-col gap-4 min-w-[720px]">
              {tiers.map(t => {
                const group = modeRows.filter(r => r.tier === t.key).sort((a, b) => (b.spendDay ?? 0) - (a.spendDay ?? 0));
                if (!group.length) return null;
                const groupNew = group.reduce((s, r) => s + budgetValue(r), 0);
                const groupSpend = group.reduce((s, r) => s + (r.spendDay ?? 0), 0);
                return (
                  <div key={t.key} className="flex flex-col gap-1">
                    <div className={`flex items-baseline gap-2 pl-2 border-l-2 ${t.border}`}>
                      <span className={`text-body font-semibold ${t.cls}`}>{t.label}</span>
                      <span className="text-label text-faint">{group.length} campaign{group.length > 1 ? 's' : ''} · {t.desc} · spend {fM(groupSpend)}/day → budget {fM(groupNew)}/day</span>
                    </div>
                    <table className="w-full border-collapse text-label">
                      <thead>{headRow}</thead>
                      <tbody>{group.map(r => campRow(r))}</tbody>
                    </table>
                  </div>
                );
              })}
            </div>
          </div>
        )}
    </section>
  );
}

export default WeeklyBudgetCampaigns;
