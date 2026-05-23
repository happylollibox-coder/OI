# Wizard-Sourced Monthly Plan + Approved-Plan-vs-Reality — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Plan wizard's Ads Path the single source of a per-product per-month plan (actual + forecast) that drives the order correctly AND feeds an always-on "Approved Plan vs Reality" panel.

**Architecture:** The Ads Path's selected spend produces a per-month family trajectory; split it per product by demand share → per-product per-month forecast. Persist via the existing `snapshot_units_json` (no backend change). `orderOverrides[product]` becomes the yearly planned total (sold YTD + forecast) so the PR table's "Gap from Plan" = forecast − stock. A new panel compares the frozen plan (units per product; spend per family) against daily-updated actuals.

**Tech Stack:** React 19 + TypeScript (strict) + Vitest. Pure logic in `dashboard-react/src/planTypes.ts`. No backend/BigQuery changes — reuses `snapshot_units_json` and the existing `/api/plans/ads-targets/<family>` GET.

**Reference spec:** `docs/superpowers/specs/2026-05-23-wizard-monthly-plan-vs-reality-design.md`

**Key facts (verified against current code):**
- `MONTHS`/`getMonthsList()` (PlanPage.tsx:46) = current month → Feb'27 (anchored, shrinking). `MONTHS[0]` is always the current month. Each `MonthDef` = `{ key, label, days, year, month }`; `key` = lowercase 3-letter month + 2-digit year, e.g. `"may26"`, `"jan27"` (PlanPage.tsx:55).
- `actuals2026Full` / `actuals2025Full` = `Map<productName, Map<monthIdx0Based, { units; revenue; cogs; adCost }>>` (PlanPage.tsx:1005-1006).
- Wizard trajectory (`TrajMonth[]`) splits the **current** month into two slices: an `isActual:true` MTD slice and a forecast slice; future months are single entries (StepAdsPath.tsx:422-451).
- PR table "sold" comes from `parentGetSold(asin, name)` which falls back to product-name match (PlanPage.tsx:1160-1163), so `parentGetSold('', name)` resolves by name.
- `parentGetSold` is defined at component scope (PlanPage.tsx:1160) and is in scope inside the wizard `onSave` handler.

---

## File Structure

- `dashboard-react/src/planTypes.ts` — add 3 pure helpers: `monthKey`, `composeMonthlyPlan`, `splitTrajectoryToProducts`.
- `dashboard-react/src/planTypes.test.ts` — add tests for the 3 helpers.
- `dashboard-react/src/components/StepAdsPath.tsx` — bound `trajectoryMonths` + `adsTargets` loops to the `months` horizon (fixes 2 phantom months).
- `dashboard-react/src/components/PlanWizard.tsx` — add `plannedMonthly` to `WizardResult`; compute it from the trajectory; pass in `onSave`.
- `dashboard-react/src/pages/PlanPage.tsx` — `plannedMonthlyOverrides` state; rewrite the wizard `onSave` order write; merge into `buildPayloadRows` snapshot; `activeSnapshot` state on load; new `PlanVsRealityPanel` component (units + spend).

---

## Phase 1 — Pure helpers (TDD)

### Task 1: `monthKey(mo, yr)`

**Files:**
- Modify: `dashboard-react/src/planTypes.ts`
- Test: `dashboard-react/src/planTypes.test.ts`

- [ ] **Step 1: Write the failing test**

Add to `planTypes.test.ts`:

```ts
import { monthKey } from './planTypes';

describe('monthKey', () => {
  it('formats month + 2-digit year like the snapshot keys', () => {
    expect(monthKey(5, 2026)).toBe('may26');
    expect(monthKey(1, 2027)).toBe('jan27');
    expect(monthKey(12, 2026)).toBe('dec26');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd dashboard-react && npx vitest run src/planTypes.test.ts -t monthKey`
Expected: FAIL — `monthKey is not a function` / import error.

- [ ] **Step 3: Write minimal implementation**

Add near the top of `planTypes.ts` (after imports, before `allocateOrder`):

```ts
const MONTH_ABBR = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

// Snapshot/MonthDef key for a calendar month, e.g. monthKey(5, 2026) === "may26".
export function monthKey(mo: number, yr: number): string {
  return `${MONTH_ABBR[mo - 1]}${String(yr).slice(2)}`;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd dashboard-react && npx vitest run src/planTypes.test.ts -t monthKey`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/planTypes.ts dashboard-react/src/planTypes.test.ts
git commit -m "feat(plan): add monthKey helper"
```

### Task 2: `composeMonthlyPlan(orderedKeys, actualByMonth, forecastByMonth)`

**Files:**
- Modify: `dashboard-react/src/planTypes.ts`
- Test: `dashboard-react/src/planTypes.test.ts`

Semantics: per month, planned units = actual + forecast (additive). Elapsed months carry only actuals; future months only forecast; the current month carries actual-MTD + forecast-remainder — so a plain sum is correct for all three.

- [ ] **Step 1: Write the failing test**

```ts
import { composeMonthlyPlan } from './planTypes';

describe('composeMonthlyPlan', () => {
  const keys = ['jan26', 'may26', 'jun26', 'jan27'];

  it('sums actual + forecast per month and totals over ordered keys', () => {
    const actual = { jan26: 100, may26: 30 };   // elapsed + current-MTD
    const forecast = { may26: 20, jun26: 80, jan27: 50 }; // current-remainder + future
    const r = composeMonthlyPlan(keys, actual, forecast);
    expect(r.byMonth).toEqual({ jan26: 100, may26: 50, jun26: 80, jan27: 50 });
    expect(r.total).toBe(280);
  });

  it('treats missing months as zero', () => {
    const r = composeMonthlyPlan(['jan26', 'feb26'], {}, { jan26: 10 });
    expect(r.byMonth).toEqual({ jan26: 10, feb26: 0 });
    expect(r.total).toBe(10);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd dashboard-react && npx vitest run src/planTypes.test.ts -t composeMonthlyPlan`
Expected: FAIL — `composeMonthlyPlan is not a function`.

- [ ] **Step 3: Write minimal implementation**

Add to `planTypes.ts`:

```ts
export interface MonthlyPlan { byMonth: Record<string, number>; total: number }

// Merge actual (elapsed + current-MTD) over forecast (current-remainder + future) across an
// ordered set of month keys. Additive: the current month's actual-MTD and forecast-remainder
// are disjoint slices, so summing is correct everywhere.
export function composeMonthlyPlan(
  orderedKeys: string[],
  actualByMonth: Record<string, number>,
  forecastByMonth: Record<string, number>,
): MonthlyPlan {
  const byMonth: Record<string, number> = {};
  let total = 0;
  for (const k of orderedKeys) {
    const u = (actualByMonth[k] ?? 0) + (forecastByMonth[k] ?? 0);
    byMonth[k] = u;
    total += u;
  }
  return { byMonth, total };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd dashboard-react && npx vitest run src/planTypes.test.ts -t composeMonthlyPlan`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/planTypes.ts dashboard-react/src/planTypes.test.ts
git commit -m "feat(plan): add composeMonthlyPlan helper"
```

### Task 3: `splitTrajectoryToProducts(trajectory, variations, inHorizon)`

**Files:**
- Modify: `dashboard-react/src/planTypes.ts`
- Test: `dashboard-react/src/planTypes.test.ts`

Splits the family per-month trajectory into per-product per-month forecast by demand share. Excludes `isActual` slices (the current-month MTD comes from real actuals downstream, not the wizard's estimate). Horizon-filtered.

- [ ] **Step 1: Write the failing test**

```ts
import { splitTrajectoryToProducts } from './planTypes';

describe('splitTrajectoryToProducts', () => {
  const vars = [
    { name: 'White', splitPct: 0.75 },
    { name: 'Purple', splitPct: 0.25 },
  ];
  const inHorizon = () => true;

  it('splits forecast slices by share and keys by month', () => {
    const traj = [
      { mo: 5, yr: 2026, totalUnits: 40, isActual: true },  // current MTD — excluded
      { mo: 5, yr: 2026, totalUnits: 60, isActual: false },  // current remainder
      { mo: 6, yr: 2026, totalUnits: 200 },                  // future
    ];
    const out = splitTrajectoryToProducts(traj, vars, inHorizon);
    expect(out.White).toEqual({ may26: 45, jun26: 150 });
    expect(out.Purple).toEqual({ may26: 15, jun26: 50 });
  });

  it('drops months outside the horizon', () => {
    const traj = [{ mo: 3, yr: 2027, totalUnits: 100 }];
    const out = splitTrajectoryToProducts(traj, vars, (mo, yr) => !(mo === 3 && yr === 2027));
    expect(out.White).toEqual({});
    expect(out.Purple).toEqual({});
  });

  it('equal-splits when no product has share data', () => {
    const traj = [{ mo: 6, yr: 2026, totalUnits: 100 }];
    const out = splitTrajectoryToProducts(traj, [{ name: 'A', splitPct: 0 }, { name: 'B', splitPct: 0 }], inHorizon);
    expect(out.A).toEqual({ jun26: 50 });
    expect(out.B).toEqual({ jun26: 50 });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd dashboard-react && npx vitest run src/planTypes.test.ts -t splitTrajectoryToProducts`
Expected: FAIL — `splitTrajectoryToProducts is not a function`.

- [ ] **Step 3: Write minimal implementation**

Add to `planTypes.ts`:

```ts
// Split a family's per-month trajectory into per-product per-month forecast by demand share.
// Excludes isActual slices (current-month MTD is taken from real actuals downstream). Only
// keeps months for which inHorizon(mo, yr) is true.
export function splitTrajectoryToProducts(
  trajectory: { mo: number; yr: number; totalUnits: number; isActual?: boolean }[],
  variations: { name: string; splitPct: number }[],
  inHorizon: (mo: number, yr: number) => boolean,
): Record<string, Record<string, number>> {
  const totalShare = variations.reduce((s, v) => s + (v.splitPct > 0 ? v.splitPct : 0), 0);
  const n = variations.length;
  const out: Record<string, Record<string, number>> = {};
  for (const v of variations) out[v.name] = {};
  for (const t of trajectory) {
    if (t.isActual) continue;
    if (!inHorizon(t.mo, t.yr)) continue;
    const key = monthKey(t.mo, t.yr);
    for (const v of variations) {
      const share = totalShare > 0 ? (v.splitPct > 0 ? v.splitPct : 0) : (n > 0 ? 1 / n : 0);
      out[v.name][key] = (out[v.name][key] ?? 0) + t.totalUnits * share;
    }
  }
  return out;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd dashboard-react && npx vitest run src/planTypes.test.ts -t splitTrajectoryToProducts`
Expected: PASS (all 3 cases).

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/planTypes.ts dashboard-react/src/planTypes.test.ts
git commit -m "feat(plan): add splitTrajectoryToProducts helper"
```

---

## Phase 2 — StepAdsPath: bound loops to the horizon

### Task 4: Iterate `months` instead of hardcoded `for i<12`

**Files:**
- Modify: `dashboard-react/src/components/StepAdsPath.tsx` (`trajectoryMonths` ~401-454; `adsTargets` ~462-508)

Fixes the bug where the trajectory and coach targets emit 2 phantom months (Mar/Apr'27) beyond the Feb'27 horizon. `months[0]` is always the current month, so the `i === 0` current-month split still applies.

- [ ] **Step 1: Rewrite the `trajectoryMonths` loop header**

In `trajectoryMonths` (the `useMemo` starting ~line 401), replace:

```ts
    const now = new Date();
    const startMo = now.getMonth();
    const startYr = now.getFullYear();
    const result: TrajMonth[] = [];
    let cumProfit = 0, cumUnits = 0;

    for (let i = 0; i < 12; i++) {
      const moIdx = (startMo + i) % 12;
      const yr = startYr + Math.floor((startMo + i) / 12);
      const fullDays = DAYS_IN_MONTH[moIdx];
      const plan = profitMaxPlan[moIdx];
```

with:

```ts
    const result: TrajMonth[] = [];
    let cumProfit = 0, cumUnits = 0;

    for (let i = 0; i < months.length; i++) {
      const moIdx = months[i].month - 1;
      const yr = months[i].year;
      const fullDays = DAYS_IN_MONTH[moIdx];
      const plan = profitMaxPlan[moIdx];
```

Leave the loop body unchanged (the `i === 0` branch, the `else` branch, `result.push(...)`).

- [ ] **Step 2: Add `months` to the `trajectoryMonths` dependency array**

Change the dep array (currently `}, [profitMaxPlan, spendScale, margin, baseAdsShare, dataActualDay]);`) to:

```ts
  }, [profitMaxPlan, spendScale, margin, baseAdsShare, dataActualDay, months]);
```

- [ ] **Step 3: Rewrite the `adsTargets` loop header**

In `adsTargets` (~line 462), replace:

```ts
    const now = new Date();
    const startMo = now.getMonth();
    const startYr = now.getFullYear();
    const targets: AdsTarget[] = [];

    for (let i = 0; i < 12; i++) {
      const moIdx = (startMo + i) % 12;
      const yr = startYr + Math.floor((startMo + i) / 12);
      const days = DAYS_IN_MONTH[moIdx];
```

with:

```ts
    const targets: AdsTarget[] = [];

    for (let i = 0; i < months.length; i++) {
      const moIdx = months[i].month - 1;
      const yr = months[i].year;
      const days = DAYS_IN_MONTH[moIdx];
```

Leave the rest of the body unchanged.

- [ ] **Step 4: Add `months` to the `adsTargets` dependency array**

Change `}, [profitMaxPlan, spendScale, seasonBenchmarks, baseAdsShare, margin]);` to:

```ts
  }, [profitMaxPlan, spendScale, seasonBenchmarks, baseAdsShare, margin, months]);
```

- [ ] **Step 5: Typecheck + existing tests**

Run: `cd dashboard-react && npx tsc --noEmit && npx vitest run src/components/StepAdsPath.test.ts`
Expected: tsc 0 errors; existing `atK` tests PASS.

- [ ] **Step 6: Commit**

```bash
git add dashboard-react/src/components/StepAdsPath.tsx
git commit -m "fix(plan): bound Ads Path trajectory + coach targets to the horizon (no phantom months)"
```

---

## Phase 3 — PlanWizard: emit per-product per-month forecast

### Task 5: Add `plannedMonthly` to `WizardResult` and compute it

**Files:**
- Modify: `dashboard-react/src/components/PlanWizard.tsx` (interface ~19-27; import ~9; body ~62-148; `onSave` call ~216)

- [ ] **Step 1: Extend the import**

Change (line 9):

```ts
import { MFR, SHIP, allocateOrder } from '../planTypes';
```

to:

```ts
import { MFR, SHIP, allocateOrder, splitTrajectoryToProducts } from '../planTypes';
```

- [ ] **Step 2: Add the field to `WizardResult`**

In the `WizardResult` interface (~line 19), add after `adsTargets?`:

```ts
  // Per-product per-month FORECAST over the horizon (excludes elapsed actuals).
  // Keyed by product name → { "may26": units, ... }.
  plannedMonthly: Record<string, Record<string, number>>;
```

- [ ] **Step 3: Compute `plannedMonthly` in the component body**

After the `monthlySpend2025` memo (~line 127), add:

```ts
  // Per-product per-month forecast from the chosen Ads Path, split by demand share.
  const inHorizon = useCallback(
    (mo: number, yr: number) => months.some(m => m.month === mo && m.year === yr),
    [months],
  );
  const plannedMonthly = useMemo(
    () => splitTrajectoryToProducts(trajectory, f.variations, inHorizon),
    [trajectory, f.variations, inHorizon],
  );
```

(`useCallback`/`useMemo` are already imported in this file; confirm and add to the React import if tsc flags it.)

- [ ] **Step 4: Pass it in `onSave`**

In the Save button handler (~line 216), change the `onSave({ ... })` argument to include `plannedMonthly`:

```ts
onSave({ family: f.family, brandGrowth, adsPath, customDailySpend: adsPath === 'custom' ? customDaily : undefined, orderQty: alloc.total, orderByProduct: alloc.byProduct, adsTargets, plannedMonthly });
```

- [ ] **Step 5: Typecheck**

Run: `cd dashboard-react && npx tsc --noEmit`
Expected: 0 errors. (If `PlanPage.tsx`'s `onSave` handler now errors because `WizardResult` requires `plannedMonthly`, that is resolved in Task 6 — proceed.)

- [ ] **Step 6: Commit**

```bash
git add dashboard-react/src/components/PlanWizard.tsx
git commit -m "feat(plan): wizard emits per-product per-month forecast (plannedMonthly)"
```

---

## Phase 4 — PlanPage: order fix + snapshot wiring

### Task 6: Wizard `onSave` writes the yearly planned total + stores `plannedMonthly`

**Files:**
- Modify: `dashboard-react/src/pages/PlanPage.tsx` (state near ~1147; `onSave` handler ~2151-2160)

The wizard's order gap write is replaced: `orderOverrides[product]` becomes `sold YTD + Σ forecast` (the yearly planned total). The PR table then derives "Gap from Plan" = `planned − sold − stock` = `forecast − stock`.

- [ ] **Step 1: Add the `plannedMonthlyOverrides` state**

Next to `const [orderOverrides, setOrderOverrides] = useState<...>({});` (~line 1147), add:

```ts
  const [plannedMonthlyOverrides, setPlannedMonthlyOverrides] = useState<Record<string, Record<string, number>>>({});
```

- [ ] **Step 2: Add the `composeMonthlyPlan` / `monthKey` import**

Find the existing `planTypes` import in `PlanPage.tsx` and add `composeMonthlyPlan` and `monthKey` to it. (If PlanPage does not yet import from `planTypes`, add: `import { composeMonthlyPlan, monthKey } from '../planTypes';` near the other imports.)

- [ ] **Step 3: Replace the order-gap write in `onSave`**

Replace this block (~line 2151-2160):

```ts
            // Apply per-product order overrides (keyed by product name to match the PO machinery)
            if (result.orderByProduct && Object.keys(result.orderByProduct).length > 0) {
              setOrderOverrides(p => {
                const next = { ...p };
                for (const [name, qty] of Object.entries(result.orderByProduct)) {
                  if (qty > 0) next[name] = qty;
                }
                return next;
              });
            }
```

with:

```ts
            // Store the wizard's per-product per-month forecast (feeds the frozen snapshot)
            // and set orderOverrides to the YEARLY PLANNED TOTAL (sold YTD + forecast) so the
            // PR table's "Gap from Plan" = planned − sold − stock = forecast − stock.
            if (result.plannedMonthly && Object.keys(result.plannedMonthly).length > 0) {
              setPlannedMonthlyOverrides(prev => ({ ...prev, ...result.plannedMonthly }));
              setOrderOverrides(p => {
                const next = { ...p };
                for (const [name, byMonth] of Object.entries(result.plannedMonthly)) {
                  const forecast = Object.values(byMonth).reduce((a, b) => a + b, 0);
                  const sold = parentGetSold('', name); // resolves by product name
                  next[name] = Math.round(sold + forecast);
                }
                return next;
              });
            }
```

- [ ] **Step 4: Typecheck**

Run: `cd dashboard-react && npx tsc --noEmit`
Expected: 0 errors (the `WizardResult.plannedMonthly` requirement from Task 5 is now satisfied at the call site).

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/pages/PlanPage.tsx
git commit -m "fix(plan): wizard order = yearly planned total (sold + forecast), not a gap"
```

### Task 7: `buildPayloadRows` composes the wizard snapshot

**Files:**
- Modify: `dashboard-react/src/pages/PlanPage.tsx` (`buildPayloadRows` ~1224-1290)

For wizard-sourced products, replace the per-product snapshot series with `actual (elapsed + MTD) + wizard forecast`, over the full calendar (Jan'26 → Feb'27). Non-wizard products keep their existing runSim/demandMap snapshot.

- [ ] **Step 1: Add the override pass before `return`**

In `buildPayloadRows`, immediately before `return { rows, order_overrides_json: ..., snapshot_units_json: ... };` (~line 1285), insert:

```ts
    // Override wizard-sourced products: per-product per-month = actual (elapsed + MTD) + forecast.
    if (Object.keys(plannedMonthlyOverrides).length > 0) {
      const allCalKeys: string[] = [];
      for (let mo = 1; mo <= 12; mo++) allCalKeys.push(`${monthLabels[mo - 1]}26`); // jan26..dec26
      for (const m of MONTHS) if (m.year === 2027) allCalKeys.push(m.key);           // jan27, feb27
      for (const [prod, forecastByMonth] of Object.entries(plannedMonthlyOverrides)) {
        const actualByMonth: Record<string, number> = {};
        const am = actuals2026Full.get(prod);
        if (am) for (const [mi, v] of am.entries()) actualByMonth[`${monthLabels[mi]}26`] = v.units;
        snapshotMap[prod] = composeMonthlyPlan(allCalKeys, actualByMonth, forecastByMonth).byMonth;
      }
    }
```

(`monthLabels` — the lowercase array — is already declared in this function at ~line 1249.)

- [ ] **Step 2: Add `plannedMonthlyOverrides` to the `buildPayloadRows` dependency array**

The `useCallback` dep array (~line 1290) currently ends `..., actuals2026Full, actuals2025Full]);`. Change to:

```ts
  }, [families, mults, strategies, forecastMap, growthOverrides, effectiveGrowth, demandMap, orderOverrides, actuals2026Full, actuals2025Full, plannedMonthlyOverrides]);
```

- [ ] **Step 3: Typecheck**

Run: `cd dashboard-react && npx tsc --noEmit`
Expected: 0 errors.

- [ ] **Step 4: Manual verification (preview)**

Start/refresh the preview ("Vite Dashboard"), open the Lollibox wizard, pick a spend, Save the family, then click the top-level "Save" (plan). In the PR table, the family's products should now show a non-zero "Gap from Plan" equal to `forecast − stock` (NOT "✓ OK / 0"). Confirm the per-product order looks sane (e.g. White > 0).

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/pages/PlanPage.tsx
git commit -m "feat(plan): compose wizard snapshot (actual + forecast) per product"
```

---

## Phase 5 — Approved-Plan-vs-Reality panel (units)

### Task 8: Capture the active plan snapshot + render the units panel

**Files:**
- Modify: `dashboard-react/src/pages/PlanPage.tsx` (`loadPlanData` ~1300-1343; new state ~1147; new component + render in the approved section)

- [ ] **Step 1: Add `activeSnapshot` state**

Near `plannedMonthlyOverrides` (~line 1147), add:

```ts
  const [activeSnapshot, setActiveSnapshot] = useState<Record<string, Record<string, number>> | null>(null);
```

- [ ] **Step 2: Parse the snapshot on plan load**

`loadPlanData(rows)` receives the plan rows. Inside it, in the `if (!overridesParsed) { ... }` block (~line 1323-1332), after parsing overrides, add a snapshot parse:

```ts
        if (r.snapshot_units_json) {
          try { setActiveSnapshot(JSON.parse(String(r.snapshot_units_json))); } catch { /* ignore */ }
        }
```

- [ ] **Step 3: Add the panel component**

Add this component near the other section components (e.g. above `PurchaseRequestSection`):

```tsx
function PlanVsRealityPanel({ families, snapshot, actuals2026Full }: {
  families: FamilyBaseline[];
  snapshot: Record<string, Record<string, number>> | null;
  actuals2026Full: Map<string, Map<number, { units: number; revenue: number; cogs: number; adCost: number }>>;
}) {
  if (!snapshot) return null;
  // Columns: Jan'26 (idx 0) → Feb'27 (idx 13). MONTHS keys map onto calendar idx.
  const monthIdxs = Array.from({ length: 14 }, (_, i) => i);
  const colLabel = (i: number) => i < 12
    ? ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][i] + "'26"
    : ['Jan', 'Feb'][i - 12] + "'27";
  const keyForIdx = (i: number) => MONTHS.find(m => (m.year === 2026 ? m.month - 1 : m.month + 11) === i)?.key;
  const planUnits = (prod: string, i: number): number | null => {
    const k = keyForIdx(i);
    if (k && snapshot[prod]?.[k] != null) return snapshot[prod][k];
    // elapsed (not in MONTHS) — plan equals actual by construction
    if (i <= 11) return actuals2026Full.get(prod)?.get(i)?.units ?? null;
    return null;
  };
  const actUnits = (prod: string, i: number): number | null =>
    i <= 11 ? (actuals2026Full.get(prod)?.get(i)?.units ?? null) : null;

  return (
    <div className="mt-6">
      <h3 className="text-sm font-bold text-heading mb-2">Approved Plan vs Reality — Units</h3>
      <div className="overflow-x-auto">
        <table className="w-full text-[11px]">
          <thead>
            <tr className="text-muted border-b border-border">
              <th className="text-left py-1.5 px-1.5">Product</th>
              <th className="text-left py-1.5 px-1.5"></th>
              {monthIdxs.map(i => <th key={i} className="text-right py-1.5 px-1.5">{colLabel(i)}</th>)}
            </tr>
          </thead>
          <tbody>
            {families.flatMap(f => [...f.variations].sort((a, b) => a.name.localeCompare(b.name))).map(v => {
              const planRow = monthIdxs.map(i => planUnits(v.name, i));
              const actRow = monthIdxs.map(i => actUnits(v.name, i));
              return (
                <Fragment key={v.name}>
                  <tr className="border-b border-border/10">
                    <td className="py-1 px-1.5 font-medium" rowSpan={2}>
                      <span className="inline-flex items-center gap-1">
                        <span className="w-1.5 h-1.5 rounded-full" style={{ background: PROD_COLORS[v.name] ?? '#666' }} />{v.name}
                      </span>
                    </td>
                    <td className="py-1 px-1.5 text-blue-400">Plan</td>
                    {planRow.map((u, i) => <td key={i} className="text-right py-1 px-1.5 tabular-nums">{u == null ? '—' : Math.round(u)}</td>)}
                  </tr>
                  <tr className="border-b border-border/20">
                    <td className="py-1 px-1.5 text-emerald-400">Actual</td>
                    {actRow.map((u, i) => {
                      const p = planRow[i];
                      const cls = u == null || p == null ? '' : u >= p ? 'text-emerald-400' : 'text-red-400';
                      return <td key={i} className={`text-right py-1 px-1.5 tabular-nums ${cls}`}>{u == null ? '—' : Math.round(u)}</td>;
                    })}
                  </tr>
                </Fragment>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
```

(`Fragment`, `PROD_COLORS`, `MONTHS`, `FamilyBaseline` are already in scope in this file. If `Fragment` is not imported, add it to the React import.)

- [ ] **Step 4: Render it in the approved section**

Find where the approved plan content renders (the `isApproved` branch of the Purchase Request / replenishment area). Render the panel when approved, passing the active snapshot:

```tsx
{isApproved && <PlanVsRealityPanel families={families} snapshot={activeSnapshot} actuals2026Full={actuals2026Full} />}
```

Place it inside the same component that has `isApproved`, `families`, `activeSnapshot`, and `actuals2026Full` in scope. If those props are not all present in that child, render the panel at the top-level Plan page body instead (where `families`, `activeSnapshot`, `actuals2026Full`, and `isApproved` are all defined) — adjust by passing them down as props if needed.

- [ ] **Step 5: Typecheck + lint the touched file**

Run: `cd dashboard-react && npx tsc --noEmit && npx eslint src/pages/PlanPage.tsx`
Expected: tsc 0 errors; eslint clean for this file (ignore pre-existing repo-wide errors in other files).

- [ ] **Step 6: Manual verification**

With an APPROVED plan loaded, the panel appears: per-product Plan vs Actual rows, columns Jan'26→Feb'27. Elapsed months: Plan == Actual. Current month: Actual (MTD) ≤ Plan. Future months: Actual blank.

- [ ] **Step 7: Commit**

```bash
git add dashboard-react/src/pages/PlanPage.tsx
git commit -m "feat(plan): always-on Approved-Plan-vs-Reality units panel"
```

---

## Phase 6 — Spend view in the panel (per family)

### Task 9: Fetch planned spend + add Units/Spend toggle

**Files:**
- Modify: `dashboard-react/src/pages/PlanPage.tsx` (`PlanVsRealityPanel`)

Planned spend per family-month comes from the existing GET `/api/plans/ads-targets/<family>` (sum `daily_spend_target × days` across channels). Actual spend = Σ `actuals2026Full` `adCost` for the family's products per month. Spend is **family-grain** (per the spec: per-variation ad spend is an attribution artifact).

- [ ] **Step 1: Add a Units/Spend mode toggle + planned-spend fetch to `PlanVsRealityPanel`**

At the top of `PlanVsRealityPanel`, add:

```tsx
  const [mode, setMode] = useState<'units' | 'spend'>('units');
  // planned spend per family per calendar idx (0=Jan'26 .. 13=Feb'27)
  const [plannedSpend, setPlannedSpend] = useState<Record<string, (number | null)[]>>({});
  useEffect(() => {
    if (mode !== 'spend') return;
    let cancelled = false;
    (async () => {
      const out: Record<string, (number | null)[]> = {};
      const daysInMonth = (i: number) => new Date(i < 12 ? 2026 : 2027, (i % 12) + 1, 0).getDate();
      for (const f of families) {
        try {
          const r = await fetch(`/api/plans/ads-targets/${encodeURIComponent(f.family)}`);
          const rows: { yr: number; mo: number; daily_spend_target: number }[] = r.ok ? await r.json() : [];
          const arr: (number | null)[] = Array.from({ length: 14 }, () => null);
          for (const row of rows) {
            const i = row.yr === 2026 ? row.mo - 1 : row.mo + 11;
            if (i < 0 || i > 13) continue;
            arr[i] = (arr[i] ?? 0) + (row.daily_spend_target || 0) * daysInMonth(i);
          }
          out[f.family] = arr;
        } catch { out[f.family] = Array.from({ length: 14 }, () => null); }
      }
      if (!cancelled) setPlannedSpend(out);
    })();
    return () => { cancelled = true; };
  }, [mode, families]);
```

(`useState`, `useEffect` already imported in this file.)

- [ ] **Step 2: Compute actual family spend + render the toggle and the spend table**

Add a helper inside the component:

```tsx
  const actualFamilySpend = (fam: FamilyBaseline, i: number): number | null => {
    if (i > 11) return null; // no 2026 actuals beyond Dec
    let s = 0, any = false;
    for (const v of fam.variations) {
      const c = actuals2026Full.get(v.name)?.get(i)?.adCost;
      if (c != null) { s += c; any = true; }
    }
    return any ? s : null;
  };
```

Add the toggle just under the `<h3>` title:

```tsx
      <div className="flex gap-1 mb-2">
        <button onClick={() => setMode('units')} className={`px-2 py-0.5 rounded text-[11px] ${mode === 'units' ? 'bg-blue-500/20 text-blue-300' : 'text-muted'}`}>Units</button>
        <button onClick={() => setMode('spend')} className={`px-2 py-0.5 rounded text-[11px] ${mode === 'spend' ? 'bg-blue-500/20 text-blue-300' : 'text-muted'}`}>Spend</button>
      </div>
```

Then wrap the existing units `<table>` in `{mode === 'units' && ( ... )}` and add the spend table for `{mode === 'spend' && ( ... )}`, structured the same way but rows = families (Plan = `plannedSpend[f.family][i]`, Actual = `actualFamilySpend(f, i)`), formatted with the money formatter used elsewhere in the file (e.g. `fK`/`fmt` — match the local convention; cells show `$` thousands).

- [ ] **Step 3: Typecheck + lint**

Run: `cd dashboard-react && npx tsc --noEmit && npx eslint src/pages/PlanPage.tsx`
Expected: tsc 0; eslint clean for this file.

- [ ] **Step 4: Manual verification**

With an approved plan, toggle to Spend: family rows show planned monthly spend (ramping into peaks) vs actual ad spend; future months actual blank.

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/pages/PlanPage.tsx
git commit -m "feat(plan): add per-family spend view to plan-vs-reality panel"
```

---

## Final verification

- [ ] `cd dashboard-react && npx tsc --noEmit` → 0 errors.
- [ ] `cd dashboard-react && npx vitest run` → all green (existing + new helper tests).
- [ ] `cd dashboard-react && npx eslint src/planTypes.ts src/components/StepAdsPath.tsx src/components/PlanWizard.tsx src/pages/PlanPage.tsx` → clean for touched files.
- [ ] Preview end-to-end: wizard save → plan save → PR "Gap from Plan" = forecast − stock (non-zero); approve → panel shows units (per product) + spend (per family) plan vs actuals; coach `adsTargets` count = `MONTHS.length × 2` channels (no Mar/Apr'27).

## Notes / deferred (out of scope)

- Backend `/fulfillment` `plan_qty` now reads the yearly planned total (was treated as order qty); fulfillment % semantics are a known follow-up, not changed here.
- The wizard Order step (Step 5) `target`/friendly-100 controls become a preview only; the binding order is the PR-table carton-rounded gap.
- Deferred from the prior spec: `max_cpc` persistence to `DE_PLAN_ADS_TARGETS` (B1/B2), live per-family CPC ceilings (C), panel metrics beyond units + spend.
