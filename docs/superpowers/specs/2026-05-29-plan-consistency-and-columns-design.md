# Plan Consistency (wizard = table = coach) + Plan Columns in the Family Overview

**Date:** 2026-05-29
**Components:** `dashboard-react/src/components/StepAdsPath.tsx`, `PlanWizard.tsx`, `dashboard-react/src/pages/PlanPage.tsx`, `planTypes.ts`
**Status:** Design — pending review

## Problem

Selecting a point in the wizard's Ads Path (e.g. Lollibox **17,071 units / $150K / $258.5K**) produces three *different* numbers downstream:

| Surface | Lollibox units | source |
|---|---|---|
| Wizard Ads Path (live) | 17,071 | `trajectory` total |
| Table / forecast | 13,674 | saved `snapshot_units_json` |
| Coach | 24,806 | saved `adsTargets.predicted_units` |

The user wants the table to show the chosen plan, and all three to agree. (Confirmed scope: **make all three agree**, then add the columns.)

## Root cause (confirmed in code)

The per-month unit *formula* is already shared — `adsTargets` (StepAdsPath L485) and `trajectory` (L421) both call `unitsAtSpend(plan.spend*spendScale, plan.units0, plan.spend0, plan.e)`. The divergence is **operational**:

1. **Decoupled persistence.** `adsTargets` is POSTed by the *wizard's* onSave (step 5). The `snapshot_units_json` is persisted by the *separate top-level* "Save Plan" button (`buildPayloadRows` → `/api/plans`). Saved at different selections/times → coach and table drift.
2. **Window / current-month mismatch.** `trajectory`→`plannedMonthly`→snapshot is horizon-bound and splits the current month into actual + forecast (excluding the actual slice); `adsTargets` loops its own window with the full current month. Even at one selection the totals don't tie.

## Design (Approach A — one units array + coupled saves)

### 1. One per-month family plan in `StepAdsPath`

Introduce a single memo `familyPlanByMonth: { mo, yr, spend, fcUnits }[]` over the **horizon** (`months`), where for each month:
- `spend = profitMaxPlan[moIdx].spend * spendScale` (current month also prorated to remaining days — see below)
- `units = unitsAtSpend(spend, units0, spend0, e)` (anchored) or `plan.units*spendScale`
- **current month uses FORECAST-REMAINING** (per the user): `fcUnits = units * (remainingDays / daysInMonth)`; the elapsed MTD actual does **not** contribute to any plan total. Other months `fcUnits = units`.

This is the single rule everywhere — so the wizard headline drops **below** 17,071 (the current month now contributes only its forward-remaining slice, not the full/elapsed month), and matches the snapshot, the coach, and the column exactly.

Everything downstream derives from this one array:
- **`trajectory` / curve headline** = Σ `fcUnits` (+ profit/ROAS from the same spend) — forecast-based, lower than the old 17,071. The "✓ actual" row may remain as informational context but is **excluded from the totals**.
- **`plannedMonthly`** (→ snapshot/table) = `splitTrajectoryToProducts` over the `fcUnits` slices (already forecast-remaining for the current month — matches PlanPage `plannedUnits`).
- **`adsTargets.predicted_units`** (→ coach) = the **same `fcUnits`** per month, split into BRAND/NON_BRAND by channel weight. So `Σ channels[mo] === fcUnits[mo] === Σ products[mo]` by construction.

Result: per month, **coach predicted_units == snapshot forecast == curve/headline == the column**. No formula drift, no current-month special-casing divergence.

### 2. Couple the saves

The wizard onSave stops POSTing `adsTargets` directly. Instead it hands `adsTargets` to PlanPage, stored as `adsTargetsByFamily[family]` (alongside the existing `plannedMonthlyOverrides`). The **top-level "Save Plan"** becomes the single commit point: it persists the snapshot (as today) **and** POSTs `adsTargets` for every family in `adsTargetsByFamily`. One commit → snapshot and coach targets always reflect the same selection.

The wizard's step-5 button is **renamed "Apply"** (it applies the family's plan to the in-memory plan); the top-level "Save Plan" commits everything. This matches today's snapshot behaviour, which already only persists on the top-level save.

### 3. Plan columns in the family overview

Add to the overview table (sourced from `projs`, already wizard-sourced), summed over the horizon — all **forecast-based** (current month = remaining), so they tie to the wizard headline with no add-back:
- **Plan Units** = Σ horizon `projs.demand` (forecast; current month already = remaining via PlanPage `plannedUnits`).
- **Plan Profit** = Σ horizon `projs.netProfit` (= units×margin − spend).
- **Plan ROAS** = `(Σrev − Σcogs) / ΣadSpend`.
- **Ad Spend** = Σ horizon `projs.adSpend` (already a column — group it with the new ones).

Header carries the **horizon window label**, e.g. `Plan · Jun '26 – Feb '27` (computed from `MONTHS[0]` … last horizon month). Unplanned families keep the "est · not planned" badge; their columns read the runSim fallback.

## Consistency invariant (what we guarantee)

> For a saved, wizard-planned family, all per-month and totalled: `coach predicted_units == snapshot forecast units == curve/headline units == overview Plan Units` — every surface forecast-based (current month = remaining), so they're equal with no add-back.

## Testing

- Unit (`planTypes.test.ts`): a helper that derives channel-split `predicted_units` from a family `fcUnits` total sums back to that total (Σ channels == total). Reuse `splitTrajectoryToProducts` test pattern for the product split.
- Live: save Lollibox at a known point; assert the overview Plan Units == wizard headline, and `bq` `Σ predicted_units == Σ snapshot forecast` for that family.

## Scope

**Changes:** `StepAdsPath` single `familyPlanByMonth` + adsTargets derive from `fcUnits`; PlanWizard hands `adsTargets` up instead of POSTing; PlanPage `adsTargetsByFamily` state + top-level Save POSTs them; 4 overview columns + horizon label.

**Keeps unchanged:** the profit-max engine, `buildEffectiveProjs`, the order math, the tracking scorecard, the coach's decision logic, the DE schemas (no backend change).

**Out of scope:** changing the per-month unit *formula*; per-week granularity; the deferred `max_cpc` persistence.

## Decisions (locked)

- **Wizard step-5 button renamed "Apply"** — applies the family plan to memory; the top-level "Save Plan" commits snapshot + targets together.
- **Current month = forecast-remaining everywhere** — the wizard headline drops below 17,071 and matches snapshot/coach/column with no MTD add-back.

## Remaining risk

- **Stale targets for un-re-saved families** — coupling fixes drift going forward, but families whose targets were POSTed under the old (immediate-POST) flow keep their old rows until the next top-level Save. A one-time re-save per family clears it.
- **Curve "✓ actual" row** — kept as informational context but excluded from totals; needs a small label so it's clearly not part of the plan total.
