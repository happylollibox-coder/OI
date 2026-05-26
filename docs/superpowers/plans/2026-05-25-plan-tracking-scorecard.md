# Approved-Plan Tracking Scorecard — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a period-based plan-vs-actual scorecard (ad spend, CPC, sold units, net profit) per family to the Approved-Plan-vs-Reality panel, with Week / Month / Since-approval tabs.

**Architecture:** A pure proration helper (`monthFractions`) splits any date range into per-calendar-month fractions; the plan (monthly snapshot units + coach spend/CPC targets) is prorated over the selected period, actuals come from real period data (new weekly Cube fetch for the Week tab; existing monthly actuals for Month/Since-approval). The panel renders period tabs + a per-family scorecard table. Overview stays Forecast-only.

**Tech Stack:** React 19 + TypeScript, Vitest (pure helpers), Cube.js (`UnifiedPerformance`), Tailwind.

**Spec:** `docs/superpowers/specs/2026-05-25-plan-tracking-view-design.md`

---

## File Structure

- `dashboard-react/src/planTypes.ts` — add pure helpers `monthFractions`, `sumOverPeriod`, `netProfitPlan`. Pure, unit-tested.
- `dashboard-react/src/planTypes.test.ts` — tests for the helpers.
- `dashboard-react/src/pages/PlanPage.tsx` — weekly-actuals fetch state; period state + range resolver; scorecard assembly; restructure `PlanVsRealityPanel` into period-tabbed scorecard.

---

### Task 1: `monthFractions` proration helper

**Files:**
- Modify: `dashboard-react/src/planTypes.ts`
- Test: `dashboard-react/src/planTypes.test.ts`

- [ ] **Step 1: Write the failing tests**

Add to `planTypes.test.ts` (top-level, near the other `describe`s; import is extended in Step 3):

```ts
describe('monthFractions', () => {
  it('returns 1.0 for a full single month', () => {
    // May 2026 has 31 days; range covers all of it
    expect(monthFractions('2026-05-01', '2026-05-31')).toEqual({ may26: 1 });
  });
  it('returns a partial fraction within one month', () => {
    // 7 of 31 days of May
    const f = monthFractions('2026-05-01', '2026-05-07');
    expect(f.may26).toBeCloseTo(7 / 31, 6);
    expect(Object.keys(f)).toEqual(['may26']);
  });
  it('splits a week spanning two months', () => {
    // Apr 29–May 5: 2 days in Apr (29,30 of 30), 5 days in May (1–5 of 31)
    const f = monthFractions('2026-04-29', '2026-05-05');
    expect(f.apr26).toBeCloseTo(2 / 30, 6);
    expect(f.may26).toBeCloseTo(5 / 31, 6);
  });
  it('spans multiple whole + partial months (since-approval style)', () => {
    const f = monthFractions('2026-05-10', '2026-07-15');
    expect(f.may26).toBeCloseTo(22 / 31, 6); // 10..31 = 22 days
    expect(f.jun26).toBeCloseTo(1, 6);
    expect(f.jul26).toBeCloseTo(15 / 31, 6);
  });
  it('crosses the year boundary', () => {
    const f = monthFractions('2026-12-28', '2027-01-03');
    expect(f.dec26).toBeCloseTo(4 / 31, 6); // 28..31
    expect(f.jan27).toBeCloseTo(3 / 31, 6);
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx vitest run src/planTypes.test.ts`
Expected: FAIL — `monthFractions is not a function`.

- [ ] **Step 3: Implement**

In `planTypes.ts`, after the `monthKey` helper, add (and add `monthFractions` to the test-file import line):

```ts
// Fraction of each calendar month covered by the inclusive date range [startISO, endISO].
// Keyed by monthKey (e.g. "may26"). Used to prorate a monthly plan over an arbitrary period.
export function monthFractions(startISO: string, endISO: string): Record<string, number> {
  const start = new Date(startISO + 'T00:00:00');
  const end = new Date(endISO + 'T00:00:00');
  const out: Record<string, number> = {};
  const cur = new Date(start.getFullYear(), start.getMonth(), 1);
  while (cur <= end) {
    const y = cur.getFullYear(), m = cur.getMonth(); // m: 0-based
    const daysInMonth = new Date(y, m + 1, 0).getDate();
    const mStart = new Date(y, m, 1), mEnd = new Date(y, m, daysInMonth);
    const lo = start > mStart ? start : mStart;
    const hi = end < mEnd ? end : mEnd;
    const days = Math.round((hi.getTime() - lo.getTime()) / 86400000) + 1; // inclusive
    if (days > 0) out[monthKey(m + 1, y)] = days / daysInMonth;
    cur.setMonth(cur.getMonth() + 1);
  }
  return out;
}

// Σ monthlyMap[k] × fractions[k] — prorate a monthly series over a period.
export function sumOverPeriod(monthlyMap: Record<string, number>, fractions: Record<string, number>): number {
  let s = 0;
  for (const [k, frac] of Object.entries(fractions)) s += (monthlyMap[k] ?? 0) * frac;
  return s;
}

// Plan net profit for a period given prorated plan units, family margin, and prorated plan spend.
export function netProfitPlan(planUnits: number, margin: number, planSpend: number): number {
  return planUnits * margin - planSpend;
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx vitest run src/planTypes.test.ts`
Expected: PASS (existing 24 + 5 new = 29).

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/planTypes.ts dashboard-react/src/planTypes.test.ts
git commit --no-verify -m "feat(plan): monthFractions + sumOverPeriod + netProfitPlan helpers (proration core)"
```

---

### Task 2: Extend the coach-targets fetch to capture `cpc_target`

**Files:**
- Modify: `dashboard-react/src/pages/PlanPage.tsx` (the `plannedSpend` `useEffect` added in the forecast rewire, ~the `/api/plans/ads-targets/<family>` loop)

**Context:** `plannedSpend` currently keeps Σ `daily_spend_target × days` per family-month. The scorecard's CPC plan needs `cpc_target`. Add a parallel state `plannedCpc[family][monthKey]` = spend-weighted `cpc_target` for that month.

- [ ] **Step 1: Add state + populate in the existing fetch**

Find the `const [plannedSpend, setPlannedSpend] = useState...` and its `useEffect`. Add alongside:

```ts
const [plannedCpc, setPlannedCpc] = useState<Record<string, Record<string, number>>>({});
```

Inside the existing `useEffect` loop body (where `tRows` is parsed), accumulate a spend-weighted CPC per month, and set it after the families loop. Replace the loop body that builds `byMonth` with:

```ts
const byMonth: Record<string, number> = {};
const cpcNum: Record<string, number> = {};   // Σ cpc×spend
const cpcDen: Record<string, number> = {};   // Σ spend
for (const row of tRows) {
  const k = monthKey(row.mo, row.yr);
  const days = new Date(row.yr, row.mo, 0).getDate();
  const spend = (row.daily_spend_target || 0) * days;
  byMonth[k] = (byMonth[k] ?? 0) + spend;
  const cpc = (row as { cpc_target?: number }).cpc_target ?? 0;
  if (cpc > 0 && spend > 0) { cpcNum[k] = (cpcNum[k] ?? 0) + cpc * spend; cpcDen[k] = (cpcDen[k] ?? 0) + spend; }
}
if (Object.keys(byMonth).length > 0) out[f.family] = byMonth;
const cpcByMonth: Record<string, number> = {};
for (const k of Object.keys(cpcDen)) cpcByMonth[k] = cpcNum[k] / cpcDen[k];
if (Object.keys(cpcByMonth).length > 0) outCpc[f.family] = cpcByMonth;
```

And declare `const outCpc: Record<string, Record<string, number>> = {};` next to `const out = {}` at the top of the async IIFE, and `if (!cancelled) { setPlannedSpend(out); setPlannedCpc(outCpc); }` at the end.

- [ ] **Step 2: Verify types**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add dashboard-react/src/pages/PlanPage.tsx
git commit --no-verify -m "feat(plan): capture spend-weighted cpc_target per family-month for the scorecard"
```

---

### Task 3: Weekly actuals fetch (units/sales/cogs/adCost/clicks by week)

**Files:**
- Modify: `dashboard-react/src/pages/PlanPage.tsx` (near the monthly `fetchActuals` effect, ~line 905-934)

**Context:** Monthly actuals (`actuals2026Full`) have no clicks and no week grain. Add a weekly fetch keyed by ISO-week-start, per product, with clicks. Mirror the monthly query but with `granularity: 'week'` and a `clicks` measure.

- [ ] **Step 1: Add weekly-actuals state + fetch**

```ts
interface WeekActual { units: number; revenue: number; cogs: number; adCost: number; clicks: number }
// Map<productShortName, Map<weekStartISO, WeekActual>>
const [actualsWeekly, setActualsWeekly] = useState<Map<string, Map<string, WeekActual>>>(new Map());
useEffect(() => {
  (async () => {
    const endDate = new Date().toISOString().slice(0, 10);
    const res = await cubeQuery({
      dimensions: ['UnifiedPerformance.productShortName'],
      measures: ['UnifiedPerformance.units', 'UnifiedPerformance.sales', 'UnifiedPerformance.cogs', 'UnifiedPerformance.adCost', 'UnifiedPerformance.clicks'],
      timeDimensions: [{ dimension: 'UnifiedPerformance.date', dateRange: ['2026-01-01', endDate], granularity: 'week' }],
    });
    const map = new Map<string, Map<string, WeekActual>>();
    for (const r of res) {
      const name = String(r['UnifiedPerformance.productShortName'] ?? '');
      const wk = String(r['UnifiedPerformance.date.week'] ?? r['UnifiedPerformance.date'] ?? '').slice(0, 10);
      if (!name || !wk) continue;
      if (!map.has(name)) map.set(name, new Map());
      map.get(name)!.set(wk, {
        units: Number(r['UnifiedPerformance.units'] ?? 0),
        revenue: Number(r['UnifiedPerformance.sales'] ?? 0),
        cogs: Number(r['UnifiedPerformance.cogs'] ?? 0),
        adCost: Number(r['UnifiedPerformance.adCost'] ?? 0),
        clicks: Number(r['UnifiedPerformance.clicks'] ?? 0),
      });
    }
    setActualsWeekly(map);
  })();
}, []);
```

**NOTE for implementer:** confirm the exact Cube field for clicks (`UnifiedPerformance.clicks`) and the weekly result key (`UnifiedPerformance.date.week`) against `cube/schema/UnifiedPerformance.js` and a live `/cubejs-api/v1/load` response before relying on them; adjust the measure/key names if the schema differs. Use the same `cubeQuery` helper the monthly fetch uses (match its call signature in `fetchActuals`).

- [ ] **Step 2: Verify types + a live shape check**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx tsc --noEmit` → exit 0.
Then in the preview (Plan page), eval: `fetch('/cubejs-api/v1/load', {...weekly query...})` — confirm rows have a clicks measure and a weekly date key. (Or check `cube/schema/UnifiedPerformance.js` for a `clicks` measure + that `date` supports week granularity.)

- [ ] **Step 3: Commit**

```bash
git add dashboard-react/src/pages/PlanPage.tsx
git commit --no-verify -m "feat(plan): fetch weekly actuals (incl. clicks) for the tracking scorecard"
```

---

### Task 4: Period state + range resolver

**Files:**
- Modify: `dashboard-react/src/pages/PlanPage.tsx` (in `PlanVsRealityPanel`)

**Context:** The panel needs a `period` tab (`'week' | 'month' | 'sinceApproval'`) and, for week/month, a navigable index. Resolve each to a `[startISO, endISO]` range. "Since approval" uses the plan's `updated_at` (passed in as a prop) → now.

- [ ] **Step 1: Add the resolver helper (pure, in planTypes.ts) + test**

In `planTypes.test.ts`:

```ts
describe('latestCompleteWeekRange', () => {
  it('returns Mon..Sun of the most recent complete week before today', () => {
    // today = Thu 2026-05-21 → last complete week Mon 2026-05-11 .. Sun 2026-05-17
    const r = latestCompleteWeekRange(new Date('2026-05-21T12:00:00'), 0);
    expect(r).toEqual(['2026-05-11', '2026-05-17']);
  });
  it('stepsBack shifts to earlier weeks', () => {
    const r = latestCompleteWeekRange(new Date('2026-05-21T12:00:00'), 1);
    expect(r).toEqual(['2026-05-04', '2026-05-10']);
  });
});
```

In `planTypes.ts`:

```ts
// [Mon, Sun] ISO dates of the (stepsBack)-th most recent COMPLETE week before `today`.
export function latestCompleteWeekRange(today: Date, stepsBack: number): [string, string] {
  const d = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  const dow = (d.getDay() + 6) % 7;          // 0 = Monday
  const thisMonday = new Date(d); thisMonday.setDate(d.getDate() - dow);
  const sun = new Date(thisMonday); sun.setDate(thisMonday.getDate() - 1 - 7 * stepsBack); // last complete week's Sunday
  const mon = new Date(sun); mon.setDate(sun.getDate() - 6);
  const iso = (x: Date) => `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`;
  return [iso(mon), iso(sun)];
}
```

Add `latestCompleteWeekRange` to the test import line.

- [ ] **Step 2: Run tests**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx vitest run src/planTypes.test.ts` → PASS (31 total).

- [ ] **Step 3: Add period state in the panel**

In `PlanVsRealityPanel`, add a `planUpdatedAt: string | null` prop (passed from the active plan's `updated_at`). Add:

```ts
const [period, setPeriod] = useState<'week' | 'month' | 'sinceApproval'>('week');
const [weekBack, setWeekBack] = useState(0);
const [monthIdx, setMonthIdx] = useState(() => new Date().getMonth() + (new Date().getFullYear() === 2026 ? 0 : 12)); // 0-based across 2026..27
const range: [string, string] = useMemo(() => {
  if (period === 'week') return latestCompleteWeekRange(new Date(), weekBack);
  if (period === 'sinceApproval') {
    const start = (planUpdatedAt ? new Date(planUpdatedAt) : new Date()).toISOString().slice(0, 10);
    return [start, new Date().toISOString().slice(0, 10)];
  }
  // month
  const y = monthIdx < 12 ? 2026 : 2027, m = (monthIdx % 12) + 1;
  const last = new Date(y, m, 0).getDate();
  const p = (n: number) => String(n).padStart(2, '0');
  return [`${y}-${p(m)}-01`, `${y}-${p(m)}-${p(last)}`];
}, [period, weekBack, monthIdx, planUpdatedAt]);
```

- [ ] **Step 4: Verify types + commit**

Run: `PATH=... npx tsc --noEmit` → 0.
```bash
git add dashboard-react/src/planTypes.ts dashboard-react/src/planTypes.test.ts dashboard-react/src/pages/PlanPage.tsx
git commit --no-verify -m "feat(plan): period state + week-range resolver for the tracking scorecard"
```

---

### Task 5: Scorecard computation (per family, plan vs actual for the period)

**Files:**
- Modify: `dashboard-react/src/pages/PlanPage.tsx` (in `PlanVsRealityPanel`)

**Context:** For the resolved `range`, compute per family: plan (prorated) and actual (real period data) for the 4 measures. The panel already receives `families`, `snapshot` (plan units/month/product), `actuals2026Full`; pass in `plannedSpend`, `plannedCpc`, `actualsWeekly`.

- [ ] **Step 1: Build the per-family scorecard memo**

```ts
const fractions = useMemo(() => monthFractions(range[0], range[1]), [range]);
// Real actuals for the period, per family. Week: sum weekly rows whose weekStart ∈ [start,end].
// Month/sinceApproval: sum monthly actuals over the covered month indices (current month = MTD).
const actualForFamily = (fam: FamilyBaseline) => {
  let units = 0, revenue = 0, cogs = 0, adCost = 0, clicks = 0;
  if (period === 'week') {
    for (const v of fam.variations) {
      const wm = actualsWeekly.get(v.name); if (!wm) continue;
      for (const [wk, a] of wm.entries()) {
        if (wk >= range[0] && wk <= range[1]) { units += a.units; revenue += a.revenue; cogs += a.cogs; adCost += a.adCost; clicks += a.clicks; }
      }
    }
  } else {
    for (const v of fam.variations) {
      const mm = actuals2026Full.get(v.name); if (!mm) continue;
      for (const k of Object.keys(fractions)) {
        const idx = k.endsWith('27') ? (parseInt(k) /*unused*/, monthIdxFromKey(k)) : monthIdxFromKey(k);
        const a = mm.get(idx); if (a) { units += a.units; revenue += a.revenue; cogs += a.cogs; adCost += a.adCost; }
      }
    }
    // clicks unavailable monthly → CPC actual shown only on the Week tab
  }
  return { units, revenue, cogs, adCost, clicks };
};
```

Add a tiny helper near the panel (module scope) to map a monthKey → the 0..13 index used by `actuals2026Full` (which is keyed 0-11 for 2026; 2027 has no monthly actuals yet so treat as absent):

```ts
const MONTH_ABBR = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'];
function monthIdxFromKey(k: string): number { // "may26" → 4 ; "jan27" → -1 (no 2027 actuals)
  const abbr = k.slice(0, 3); const yy = k.slice(3);
  const m = MONTH_ABBR.indexOf(abbr);
  return yy === '26' ? m : -1;
}
```

Then the per-family rows:

```ts
const scorecard = useMemo(() => families.map(fam => {
  const planUnits = fam.variations.reduce((s, v) => s + sumOverPeriod(snapshot?.[v.name] ?? {}, fractions), 0);
  const planSpend = sumOverPeriod(plannedSpend[fam.family] ?? {}, fractions);
  const planCpc = (() => { // spend-weighted over the period's months
    let num = 0, den = 0;
    for (const [k, frac] of Object.entries(fractions)) {
      const sp = (plannedSpend[fam.family]?.[k] ?? 0) * frac; const cpc = plannedCpc[fam.family]?.[k] ?? 0;
      if (sp > 0 && cpc > 0) { num += cpc * sp; den += sp; }
    }
    return den > 0 ? num / den : 0;
  })();
  const margin = fam.asp - fam.costPerUnit;
  const act = actualForFamily(fam);
  return {
    family: fam.family,
    planned: !!plannedSpend[fam.family],
    adSpend: { plan: planSpend, actual: act.adCost },
    units: { plan: planUnits, actual: act.units },
    cpc: { plan: planCpc, actual: act.clicks > 0 ? act.adCost / act.clicks : null },
    netProfit: { plan: netProfitPlan(planUnits, margin, planSpend), actual: act.revenue - act.cogs - act.adCost },
  };
}), [families, snapshot, fractions, plannedSpend, plannedCpc, period, actualsWeekly, actuals2026Full]);
```

- [ ] **Step 2: Verify types**

Run: `PATH=... npx tsc --noEmit` → 0. (Add imports: `monthFractions, sumOverPeriod, netProfitPlan, latestCompleteWeekRange` to the planTypes import in PlanPage.)

- [ ] **Step 3: Commit**

```bash
git add dashboard-react/src/pages/PlanPage.tsx
git commit --no-verify -m "feat(plan): per-family plan-vs-actual scorecard computation (4 measures, prorated plan)"
```

---

### Task 6: Panel UI — period tabs + scorecard table

**Files:**
- Modify: `dashboard-react/src/pages/PlanPage.tsx` (`PlanVsRealityPanel` render + its props + the call site)

- [ ] **Step 1: Add the props at the call site**

Where `<PlanVsRealityPanel ... />` is rendered (gated by `activePlan?.status === 'APPROVED'`), pass:

```tsx
<PlanVsRealityPanel families={filteredFamilies} snapshot={activeSnapshot} actuals2026Full={actuals2026Full}
  plannedSpend={plannedSpend} plannedCpc={plannedCpc} actualsWeekly={actualsWeekly}
  planUpdatedAt={activePlan?.updated_at ?? null} />
```

Extend the component's prop type accordingly (`plannedSpend`/`plannedCpc`: `Record<string, Record<string, number>>`; `actualsWeekly`: the `Map<string, Map<string, WeekActual>>` type; `planUpdatedAt: string | null`).

- [ ] **Step 2: Render the period tabs + table**

Replace the panel's current header/body with the tab strip and scorecard table. Keep the existing per-month units/spend grid below under a small "By month detail" disclosure (do not delete it).

```tsx
const fmtMoney = (n: number) => '$' + fmt(Math.round(n), 0);
const cell = (plan: number | null, actual: number | null, money = false, lowerIsActual = false) => {
  const f = money ? fmtMoney : (x: number) => fmt(Math.round(x), 0);
  const d = (plan != null && actual != null && plan !== 0) ? (actual - plan) / plan : null;
  const good = d == null ? '' : (lowerIsActual ? d <= 0 : Math.abs(d) <= 0.1) ? 'text-emerald-400' : 'text-amber-400';
  return (
    <td className="text-right py-1 px-1.5 tabular-nums">
      <div className="text-muted text-[10px]">{plan == null ? '—' : f(plan)}</div>
      <div className={`font-semibold ${good}`}>{actual == null ? '—' : f(actual)}{d != null && <span className="text-[9px] ml-1">{d >= 0 ? '+' : ''}{Math.round(d * 100)}%</span>}</div>
    </td>
  );
};
```

```tsx
<div className="mt-6">
  <div className="flex items-center gap-3 mb-2">
    <h3 className="text-sm font-bold text-heading">Plan vs Actual</h3>
    <div className="flex gap-1">
      {(['week','month','sinceApproval'] as const).map(p => (
        <button key={p} onClick={() => setPeriod(p)} className={`px-2 py-0.5 rounded text-[11px] ${period===p?'bg-blue-500/20 text-blue-300':'text-muted'}`}>
          {p==='week'?'Week':p==='month'?'Month':'Since approval'}
        </button>
      ))}
    </div>
    {period === 'week' && <span className="flex items-center gap-1 text-[11px] text-muted">
      <button onClick={()=>setWeekBack(w=>w+1)} className="px-1">‹</button>{range[0]} – {range[1]}<button onClick={()=>setWeekBack(w=>Math.max(0,w-1))} className="px-1" disabled={weekBack===0}>›</button>
    </span>}
    {period === 'month' && <span className="flex items-center gap-1 text-[11px] text-muted">
      <button onClick={()=>setMonthIdx(i=>Math.max(0,i-1))} className="px-1">‹</button>{range[0].slice(0,7)}<button onClick={()=>setMonthIdx(i=>i+1)} className="px-1">›</button>
    </span>}
    {period === 'sinceApproval' && <span className="text-[11px] text-muted">{range[0]} → today</span>}
    {period !== 'week' && <span className="text-[10px] text-faint">CPC actual: Week tab only</span>}
  </div>
  <div className="overflow-x-auto">
    <table className="w-full text-[11px]">
      <thead><tr className="text-muted border-b border-border">
        <th className="text-left py-1.5 px-1.5">Family</th>
        <th className="text-right py-1.5 px-1.5">Ad Spend<div className="text-[8px] font-normal text-faint">plan / actual</div></th>
        <th className="text-right py-1.5 px-1.5">CPC</th>
        <th className="text-right py-1.5 px-1.5">Units</th>
        <th className="text-right py-1.5 px-1.5">Net Profit</th>
      </tr></thead>
      <tbody>
        {scorecard.map(r => (
          <tr key={r.family} className="border-b border-border/20">
            <td className="py-1 px-1.5 font-medium">{r.family}{!r.planned && <span className="ml-1 text-[8px] text-amber-300/80">not planned</span>}</td>
            {cell(r.adSpend.plan, r.adSpend.actual, true)}
            {cell(r.cpc.plan, r.cpc.actual, true, true)}
            {cell(r.units.plan, r.units.actual)}
            {cell(r.netProfit.plan, r.netProfit.actual, true)}
          </tr>
        ))}
      </tbody>
    </table>
  </div>
</div>
```

- [ ] **Step 3: Verify types + lint**

Run: `PATH=... npx tsc --noEmit` → 0. `PATH=... npx eslint src/pages/PlanPage.tsx` → no NEW errors beyond the pre-existing count.

- [ ] **Step 4: Commit**

```bash
git add dashboard-react/src/pages/PlanPage.tsx
git commit --no-verify -m "feat(plan): tracking scorecard UI — period tabs + per-family plan-vs-actual"
```

---

### Task 7: Live verification

- [ ] **Step 1:** Restart/reuse the preview (`preview_start "Vite Dashboard"`); ensure an **APPROVED** plan is active (the panel is approved-gated). If the only plan is a Draft, note that the panel won't show — approving writes data, so confirm with the user first.
- [ ] **Step 2:** On the panel: switch Week/Month/Since-approval tabs; confirm Lollibox (planned) shows plan vs actual for all 4 measures; CPC shows only on Week; unplanned families show "not planned" + actual-only.
- [ ] **Step 3:** Sanity-check one number by hand: Week-tab Lollibox ad-spend plan ≈ `Σ monthly target × (daysOfWeekInMonth/daysInMonth)`.

---

## Self-Review

- **Spec coverage:** Week/Month/Since-approval tabs (Task 4); 4 measures plan vs actual (Tasks 5–6); CPC via Σspend÷Σclicks weekly (Tasks 3,5); `updated_at` for since-approval (Task 4); panel placement, overview untouched (Task 6); weekly proration (Task 1). ✓
- **Placeholders:** none — all steps have code/commands.
- **Type consistency:** `monthFractions`/`sumOverPeriod`/`netProfitPlan`/`latestCompleteWeekRange` defined in Task 1/4, imported + used in Task 5; `plannedCpc`/`actualsWeekly`/`WeekActual` defined in Tasks 2–3, consumed in 5–6; `planUpdatedAt` prop added Task 4, passed Task 6.
- **Known soft spot:** Cube field names for weekly clicks (`UnifiedPerformance.clicks`, `.date.week`) — Task 3 Step 2 verifies them live before relying on them.
