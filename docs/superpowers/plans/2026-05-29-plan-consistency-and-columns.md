# Plan Consistency + Overview Columns — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the wizard headline, the table/snapshot, and the coach targets show one identical forecast-based plan per family (current month = forecast-remaining), and surface Plan Units / Profit / ROAS / Ad Spend columns with a horizon-window label in the family overview.

**Architecture:** A single pure helper computes per-month `{spend, units}` over the horizon at a scale `k`, prorating the current month to its remaining-days fraction. `planTotals`, the spend→profit `curve`, the `trajectory`, and `adsTargets` all consume it, so every surface ties out. The wizard hands `adsTargets` to PlanPage instead of POSTing; the top-level "Save Plan" commits snapshot + targets together.

**Tech Stack:** React 19 + TS, Vitest, Tailwind. No backend/schema change.

**Spec:** `docs/superpowers/specs/2026-05-29-plan-consistency-and-columns-design.md`

**Run commands from `dashboard-react/`. Prefix node/npx with** `PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH"`. **Commit with `--no-verify`** (repo-wide pre-existing lint). **Only `git add` the exact files each task touches** — the working tree has ~25 unrelated in-flight files; never `git add -A`.

---

## File Structure

- `dashboard-react/src/planTypes.ts` (+ `.test.ts`) — new pure `scaleHorizonPlan` helper.
- `dashboard-react/src/components/StepAdsPath.tsx` — `planTotals`, `curve`, `trajectory`, `adsTargets` consume the helper (current-month proration); headline drops to forecast.
- `dashboard-react/src/components/PlanWizard.tsx` — rename step-5 button "Apply"; `onSave` hands `adsTargets` up.
- `dashboard-react/src/pages/PlanPage.tsx` — `adsTargetsByFamily` state; wizard `onSave` stores it; top-level "Save Plan" POSTs targets; overview Plan columns + horizon label.

---

### Task 1: `scaleHorizonPlan` pure helper

**Files:** Modify `dashboard-react/src/planTypes.ts`; Test `dashboard-react/src/planTypes.test.ts`.

**Context:** `profitMaxPlan` (in StepAdsPath) is a 12-element array; each entry `{ mo, spend, units, units0, spend0, anchored, e }`. The horizon is the `months: MonthDef[]` window. We need Σ over the horizon of `{spend, units}` at a given scale `k`, where the current month (index `curMoIdx`, 0-based calendar month) contributes only its remaining-days fraction `remFrac`.

- [ ] **Step 1: Write the failing test** (add to `planTypes.test.ts`; add `scaleHorizonPlan` to the import line)

```ts
describe('scaleHorizonPlan', () => {
  // two anchored months; helper scales spend by k and re-derives units off the 2025 anchor
  const plan = [
    { mo: 5, spend: 1000, units: 100, units0: 100, spend0: 1000, anchored: true, e: 0.5 },
    { mo: 6, spend: 2000, units: 200, units0: 200, spend0: 2000, anchored: true, e: 0.5 },
  ];
  const months = [{ month: 5 }, { month: 6 }] as { month: number }[];

  it('sums spend & units over the horizon at k=1 with no current-month proration', () => {
    const r = scaleHorizonPlan(plan, months, 1, -1, 1); // curMoIdx=-1 → no proration
    expect(r.spend).toBe(3000);
    expect(r.units).toBeCloseTo(300, 6); // unitsAtSpend at S=spend0 returns units0
  });

  it('scales spend by k and re-derives units via the elasticity', () => {
    const r = scaleHorizonPlan(plan, months, 2, -1, 1); // k=2
    // month5: 100*(2000/1000)^.5=141.42 ; month6: 200*(4000/2000)^.5=282.84
    expect(r.spend).toBe(6000);
    expect(r.units).toBeCloseTo(141.421 + 282.842, 2);
  });

  it('prorates the current month to remFrac (spend AND units)', () => {
    // month 5 is current with remFrac 0.25 → its spend & units count 25%
    const r = scaleHorizonPlan(plan, months, 1, 4, 0.25); // curMoIdx=4 (May, 0-based)
    expect(r.spend).toBe(1000 * 0.25 + 2000); // 2250
    expect(r.units).toBeCloseTo(100 * 0.25 + 200, 6); // 225
  });

  it('falls back to units*k for unanchored months', () => {
    const p2 = [{ mo: 5, spend: 1000, units: 100, units0: 0, spend0: 0, anchored: false, e: 0.5 }];
    const r = scaleHorizonPlan(p2, [{ month: 5 }], 3, -1, 1);
    expect(r.spend).toBe(3000);
    expect(r.units).toBe(300); // 100*3
  });
});
```

- [ ] **Step 2: Run → fail**

Run: `PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx vitest run src/planTypes.test.ts`
Expected: FAIL — `scaleHorizonPlan is not a function`.

- [ ] **Step 3: Implement** (in `planTypes.ts`, after `unitsAtSpend`)

```ts
// Per-month plan entry the Ads Path curve scales. mo is 1-based calendar month.
export interface HorizonPlanMonth { mo: number; spend: number; units: number; units0: number; spend0: number; anchored: boolean; e: number }

// Σ {spend, units} over the horizon `months` at scale k. The current calendar month (curMoIdx,
// 0-based; -1 = none) contributes only its remaining-days fraction remFrac (spend AND units),
// so totals are forecast-remaining for the current month. Anchored months re-derive units off
// the 2025 anchor via unitsAtSpend; unanchored scale linearly.
export function scaleHorizonPlan(
  plan: HorizonPlanMonth[],
  months: { month: number }[],
  k: number,
  curMoIdx: number,
  remFrac: number,
): { spend: number; units: number } {
  let spend = 0, units = 0;
  for (const m of months) {
    const p = plan.find(x => x.mo === m.month);
    if (!p) continue;
    const s = p.spend * k;
    const u = p.anchored && p.spend0 > 0 ? unitsAtSpend(s, p.units0, p.spend0, p.e) : p.units * k;
    const frac = (m.month - 1) === curMoIdx ? remFrac : 1;
    spend += s * frac;
    units += u * frac;
  }
  return { spend, units };
}
```

- [ ] **Step 4: Run → pass**

Run: `PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx vitest run src/planTypes.test.ts`
Expected: PASS (all prior + 4 new).

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/planTypes.ts dashboard-react/src/planTypes.test.ts
git commit --no-verify -m "feat(plan): scaleHorizonPlan helper — horizon totals with current-month proration"
```

---

### Task 2: StepAdsPath `planTotals` + `curve` use the helper (current-month proration)

**Files:** Modify `dashboard-react/src/components/StepAdsPath.tsx` (`planTotals` ~L320, `curve` ~L343).

**Context:** `profitMaxPlan[i]` has `{ mo, season, e, units0, spend0, anchored, spend, units, profit }` — already the shape `HorizonPlanMonth` needs (mo, spend, units, units0, spend0, anchored, e). `dataActualDay` (~L391) is the current-month data-cutoff day; `DAYS_IN_MONTH` is in scope. Compute the current-month index + remaining fraction once and feed the helper.

- [ ] **Step 1: Add current-month proration constants** (just above `planTotals`)

```ts
// Current calendar month (0-based) and the remaining-days fraction — current month counts only
// its forward-remaining slice in every plan total (forecast-based; matches snapshot + coach).
const curMoIdx0 = new Date().getMonth();
const curRemFrac = Math.max(0, 1 - dataActualDay / (DAYS_IN_MONTH[curMoIdx0] || 30));
```

(Move/define this after `dataActualDay` is declared — if `dataActualDay` is below `planTotals`, hoist the `dataActualDay` memo above `planTotals`, or inline the same `today.getDate()` formula used there. Verify `dataActualDay` is defined before this line; if not, relocate.)

- [ ] **Step 2: Rewrite `planTotals`** to use the helper

```ts
  const planTotals = useMemo(() => {
    const t = scaleHorizonPlan(profitMaxPlan, months, 1, curMoIdx0, curRemFrac);
    return { spend: t.spend, units: t.units, profit: t.units * margin - t.spend };
  }, [profitMaxPlan, months, margin, curMoIdx0, curRemFrac]);
```

- [ ] **Step 3: Rewrite `curve`** to use the helper

```ts
  const curve: CurvePoint[] = useMemo(() => {
    return multipliers.map(k => {
      const { spend, units } = scaleHorizonPlan(profitMaxPlan, months, k, curMoIdx0, curRemFrac);
      const profit = units * margin - spend;
      return {
        k, daily: horizonDays > 0 ? spend / horizonDays : 0, annual: spend,
        adUnitsYear: Math.round(units * baseAdsShare),
        totalUnitsYear: Math.round(units),
        profitYear: Math.round(profit),
        roas: spend > 0 ? (units * margin) / spend : 0,
      };
    });
  }, [multipliers, profitMaxPlan, months, margin, baseAdsShare, horizonDays, curMoIdx0, curRemFrac]);
```

- [ ] **Step 4: Import the helper + verify**

Add `scaleHorizonPlan` to the `planTypes` import in StepAdsPath. Run:
`PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx tsc --noEmit` → 0;
`PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx eslint src/components/StepAdsPath.tsx` → no NEW errors.

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/components/StepAdsPath.tsx
git commit --no-verify -m "feat(plan): Ads Path curve+totals forecast-based (current month = remaining)"
```

---

### Task 3: `trajectory` + `adsTargets` derive units from the same per-month fcUnits

**Files:** Modify `dashboard-react/src/components/StepAdsPath.tsx` (`trajectory` ~L409, `adsTargets` ~L467).

**Context:** Today both re-compute `units = unitsAtSpend(...)` independently. Make `adsTargets.predicted_units` per month equal the trajectory's per-month forecast units, so `Σ channels == Σ products` by construction. The current month uses `curRemFrac` in both.

- [ ] **Step 1: In `adsTargets`, replace the per-month `units` with the forecast-remaining slice**

Find (in the `adsTargets` loop, ~L484-487):
```ts
      const spend = plan.spend * spendScale;
      const units = plan.anchored && plan.spend0 > 0
        ? unitsAtSpend(spend, plan.units0, plan.spend0, plan.e)
        : plan.units * spendScale;
```
Replace with:
```ts
      const isCur = moIdx === curMoIdx0;
      const frac = isCur ? curRemFrac : 1;
      const spend = plan.spend * spendScale * frac;
      const fullUnits = plan.anchored && plan.spend0 > 0
        ? unitsAtSpend(plan.spend * spendScale, plan.units0, plan.spend0, plan.e)
        : plan.units * spendScale;
      const units = fullUnits * frac; // forecast-remaining for the current month
```
(`days` for `daily_spend_target` stays full-month days — the per-day coach rate is unchanged; only the monthly total `units`/`spend` are prorated. Confirm `mkRow`'s `daily_spend_target: (chSpend / days)` still divides the *prorated* chSpend by full `days`; to keep the daily rate unchanged, divide by `days * frac` instead: `daily_spend_target: Math.round((chSpend / (days * frac)) * 100) / 100`.)

- [ ] **Step 2: Verify `trajectory` already uses `curRemFrac`-equivalent**

`trajectory` (~L427-446) already splits the current month into `fAct`/`fFc` and pushes the forecast slice with `fFc = 1 - dataActualDay/fullDays` (== `curRemFrac`), and `plannedMonthly` excludes the `isActual` slice. Confirm `fFc` equals `curRemFrac`; if it derives differently, set `const fFc = curRemFrac;` so the trajectory forecast slice and `adsTargets` use the identical fraction. The headline `yr1Units`/`cumUnits` should sum the forecast slices only — confirm the current-month `isActual` slice is **not** added to `cumUnits`; if it is, stop adding it (drop `cumProfit/cumUnits += *fAct`).

- [ ] **Step 3: Verify tie-out + types**

Run: `PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx tsc --noEmit` → 0.
Add a temporary console assertion or eval later (Task 7) that `Σ adsTargets.predicted_units ≈ planTotals.units` for the selected k.

- [ ] **Step 4: Commit**

```bash
git add dashboard-react/src/components/StepAdsPath.tsx
git commit --no-verify -m "feat(plan): unify trajectory + adsTargets units (forecast-remaining current month)"
```

---

### Task 4: PlanWizard — rename button "Apply"; hand adsTargets up

**Files:** Modify `dashboard-react/src/components/PlanWizard.tsx` (save button ~L272, `onSave` payload ~L265).

- [ ] **Step 1: Rename the step-5 button label**

Find `<Check size={14} /> Save Plan` (the wizard's emerald save button) and change the text to `Apply`. Leave the icon.

- [ ] **Step 2: Confirm onSave already includes `adsTargets`**

The `onSave({ ..., adsTargets, plannedMonthly, orderMode })` call (~L265) already passes `adsTargets`. No change needed here — PlanPage will store rather than POST (Task 5). Leave as is.

- [ ] **Step 3: Verify + commit**

Run: `PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx tsc --noEmit` → 0.
```bash
git add dashboard-react/src/components/PlanWizard.tsx
git commit --no-verify -m "feat(plan): rename wizard step-5 button to Apply"
```

---

### Task 5: PlanPage — store adsTargets per family; POST on top-level Save

**Files:** Modify `dashboard-react/src/pages/PlanPage.tsx` (wizard `onSave` handler ~L2193 where it POSTs ads-targets; top-level "Save Plan" button ~L1697; add `adsTargetsByFamily` state near other plan state).

- [ ] **Step 1: Add state**

Near `const [plannedMonthlyOverrides, setPlannedMonthlyOverrides] = ...`:
```ts
  const [adsTargetsByFamily, setAdsTargetsByFamily] = useState<Record<string, AdsTarget[]>>({});
```
(`AdsTarget` is exported from `StepAdsPath`; add to the import from `'../components/StepAdsPath'` if not already imported, or import the type.)

- [ ] **Step 2: In the wizard onSave, store instead of POST**

Replace the existing block that does `const enriched = result.adsTargets.map(...)` + `await fetch('/api/plans/ads-targets', ...)` with: store the enriched targets in state (keep the LY/CY ROAS enrichment from `familyRoas`):
```ts
            if (result.adsTargets && result.adsTargets.length > 0) {
              const fr = familyRoas[result.family];
              const enriched = result.adsTargets.map(t => ({
                ...t,
                ly_ad_net_roas: fr?.adOnly[t.channel]?.[2025] ?? null,
                cy_ad_net_roas: fr?.adOnly[t.channel]?.[2026] ?? null,
                ly_net_roas: fr?.blended[2025] ?? null,
                cy_net_roas: fr?.blended[2026] ?? null,
              }));
              setAdsTargetsByFamily(p => ({ ...p, [result.family]: enriched }));
            }
```
(Remove the old immediate `fetch`/alert block.)

- [ ] **Step 3: In the top-level "Save Plan" onClick, POST the targets after the plan save succeeds**

Inside the top-level Save handler, after the plan `res.ok` branch (where it sets `planSaved`), add a loop that POSTs each family's targets:
```ts
                  for (const [fam, targets] of Object.entries(adsTargetsByFamily)) {
                    if (!targets.length) continue;
                    try {
                      const r = await fetch('/api/plans/ads-targets', {
                        method: 'POST', headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ family: fam, targets }),
                      });
                      const d = await r.json();
                      if (!d.success) console.error('[AdsTargets] save failed', fam, d.error);
                    } catch (e) { console.error('[AdsTargets] save error', fam, e); }
                  }
```

- [ ] **Step 4: Verify + commit**

Run: `PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx tsc --noEmit` → 0; `npx eslint src/pages/PlanPage.tsx` → no NEW errors.
```bash
git add dashboard-react/src/pages/PlanPage.tsx
git commit --no-verify -m "feat(plan): couple coach-targets save into the top-level Save Plan"
```

---

### Task 6: Overview Plan columns + horizon label

**Files:** Modify `dashboard-react/src/pages/PlanPage.tsx` (header ~L2017, FamilyRow cells ~L2320, FamilyRow props, the parent per-family aggregate ~L2040, totals row ~L2101).

**Context:** Per-family horizon sims are already computed in the parent map loop (`fDemand`, `fRev`, `fCogs`, `fAd`, `fNp` summed over `projs`). Add `simUnits`/`simNetProfit`/`simRoas` props to FamilyRow and render columns. The horizon label = `MONTHS[0].label` … last horizon month label.

- [ ] **Step 1: Add the header cells** (after the `Stock` header, before `Ad Spend`)

```tsx
            <th className="text-right py-2 px-2 w-20"><Tip text={`Plan units over the horizon (forecast; current month = remaining)\n${MONTHS[0].label} – ${MONTHS[MONTHS.length-1].label}`}>Plan Units <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
            <th className="text-right py-2 px-2 w-20"><Tip text="Plan net profit = units×margin − ad spend (horizon)">Plan Profit <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
```
(ROAS already exists as a column; reuse it. Ad Spend already exists.)

- [ ] **Step 2: Pass new props at the FamilyRow call** (~L2057)

In the parent loop, `fNp` and `fDemand` already exist. Add to the `<FamilyRow ... />`:
```tsx
                simUnits={fDemand} simNetProfit={fNp}
```

- [ ] **Step 3: Add to FamilyRow signature + type**

In `function FamilyRow({ ... simAdSpend, simNetRoas, ... })` add `simUnits, simNetProfit`; in its prop type add `simUnits: number; simNetProfit: number;`.

- [ ] **Step 4: Render the cells** (in FamilyRow, after the Stock cell, before the Ad Spend cell)

```tsx
      <td className="text-right py-2 px-2 tabular-nums text-heading">{fU(simUnits)}</td>
      <td className={`text-right py-2 px-2 tabular-nums font-bold ${simNetProfit >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>{fK(simNetProfit)}</td>
```

- [ ] **Step 5: Add matching cells to the TOTAL row** (~L2105, after the Stock total)

```tsx
              <td className="text-right py-2 px-2 tabular-nums text-heading">{fU(filteredTotals.demand)}</td>
              <td className="text-right py-2 px-2 tabular-nums font-bold text-heading">{fK(filteredTotals.netProfit)}</td>
```
(Adjust `colSpan` on the expanded-row `<td>` from 10 → 12 to match the new column count.)

- [ ] **Step 6: Verify + commit**

Run: `PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx tsc --noEmit` → 0; `npx eslint src/pages/PlanPage.tsx` → no NEW errors; confirm column counts align (header = body = totals).
```bash
git add dashboard-react/src/pages/PlanPage.tsx
git commit --no-verify -m "feat(plan): overview Plan Units/Profit columns + horizon-window label"
```

---

### Task 7: Live verification (consistency invariant)

- [ ] **Step 1:** Preview → Plan → open a family wizard (e.g. Lollibox) → Ads Path. Confirm the headline units **dropped below 17,071** (current month now remaining-only) and the curve profit/ROAS moved with it. Note the selected-point units/profit/spend.
- [ ] **Step 2:** Click wizard **Apply** (button renamed), then the top-level **Save Plan**. Confirm console logs the ads-targets save (no error).
- [ ] **Step 3:** Overview row for that family: **Plan Units** ≈ the wizard headline; **Plan Profit** / **Ad Spend** match the selected point.
- [ ] **Step 4:** `bq query --use_legacy_sql=false "SELECT ROUND(SUM(predicted_units)) FROM \`onyga-482313.OI.DE_PLAN_ADS_TARGETS\` WHERE family='<fam>'"` and compare to the saved snapshot Σ forecast units for that family — they should match (within rounding). This is the invariant.

---

## Self-Review

- **Spec coverage:** single units array (Task 1–3); current month = forecast-remaining everywhere (Tasks 2,3); coach predicted_units == snapshot (Task 3 + invariant in Task 7); couple saves (Tasks 4,5); rename Apply (Task 4); overview columns + horizon label (Task 6). ✓
- **Placeholders:** none — code/commands in every step.
- **Type consistency:** `scaleHorizonPlan(plan, months, k, curMoIdx, remFrac)` defined Task 1, used Tasks 2; `curMoIdx0`/`curRemFrac` defined Task 2 Step 1, used Tasks 2–3; `adsTargetsByFamily`/`AdsTarget` Task 5; `simUnits`/`simNetProfit` Task 6.
- **Risk flagged in steps:** `dataActualDay` ordering (Task 2 Step 1), `daily_spend_target` divides by full days not prorated (Task 3 Step 1), colSpan update (Task 6 Step 5).
