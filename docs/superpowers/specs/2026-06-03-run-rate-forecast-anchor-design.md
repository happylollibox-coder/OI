# Forecast Starting Point = Current 30-Day Run-Rate (× holiday shape)

**Date:** 2026-06-03
**Component:** `dashboard-react/src/components/PlanWizard.tsx` (the `monthlyUnits2025` / `monthlySpend2025` anchors fed to `StepAdsPath`), `dashboard-react/src/pages/PlanPage.tsx` (trailing-30-day data), `dashboard-react/src/planTypes.ts` (pure anchor builder)
**Status:** Design approved (approach + forks), pending spec review
**Builds on:** the wizard-sourced-forecast + consistency work — the Ads Path profit-max engine is the single forecast source for planned families.

## Problem

The Ads Path engine anchors each month to the **same month in 2025** (`monthlyUnits2025` / `monthlySpend2025`, raw actuals). For a young/growing family this is stale: **LolliME June 2025 = 0 units** (pre-launch), so the Jun '26 forecast has no real anchor and falls back to a season-benchmark (~22/day) — while LolliME actually sells a steady **~40/day** in 2026. The family's YoY growth never reaches the Ads Path (the Step-2 growth factor only feeds the runSim/demand path). Result: young/growing families are systematically under-forecast in their ramp months.

## Decisions (from brainstorming)

- **Approach A:** the per-product **starting point = the current 30-day run-rate** (the *level*), projected forward with a **seasonal shape** (so Dec still peaks).
- **Scope:** **all products** (established families' run-rate ≈ their 2025 anyway, so little change there; young families get fixed).
- **Seasonal shape source:** the **holiday demand model** (`V_FORECAST_DEMAND` / `demandMap`), which is new-product-aware (model products) and **not** distorted by a family's own 2025 ramp — unlike `computeSeasonality`.

## Model

Replace the Ads Path anchors `monthlyUnits2025[m]` / `monthlySpend2025[m]` with a **current-reality anchor**:

### 1. Level — per-product trailing-30-day run-rate
From `V_UNIFIED_DAILY` (latest 30 days ending at the latest data date):
- `runUnitsPerDay[product]` = Σ units (last 30d) ÷ 30
- `runSpendPerDay[product]` = Σ adCost (last 30d) ÷ 30

### 2. Shape — holiday demand curve, normalized to "now"
From `demandMap[product][yearMonth]` (already loaded; holiday-driven, new-product-aware):
```
shapeFactor[product][m] = demandMap[product][m] / demandMap[product][currentMonth]
```
So `shapeFactor[currentMonth] = 1`, Dec lifts to its peak multiple, etc. **Fallbacks:** if `demandMap[product][currentMonth]` is 0/missing, fall back to the family-level demand ratio; if that's also absent, `shapeFactor = 1` (flat). Never divide by zero.

### 3. New anchor (replaces the 2025 anchors)
```
anchorUnits[product][m] = runUnitsPerDay[product] × daysInMonth[m] × shapeFactor[product][m]
anchorSpend[product][m] = runSpendPerDay[product] × daysInMonth[m] × shapeFactor[product][m]
```
Re-leveling **both** units and spend by the same factor keeps a coherent `(units, spend)` pair every month — the anchor efficiency = the product's **current** units-per-ad-dollar, with **no 2025 dependency and no divide-by-zero** on pre-launch months. The family anchors fed to `StepAdsPath` are the per-product anchors summed over the family.

### 4. Profit-max engine unchanged
`profitMaxSpend` / `unitsAtSpend` / the season elasticities are untouched — they just receive the current-reality `(anchorUnits, anchorSpend)` instead of stale 2025. At the anchor spend the model reproduces the current run-rate × seasonality; it then optimizes spend around that.

### 5. Current month
The trailing-30-day rate **is** the current pace, so the current month's forecast = `runUnitsPerDay × remainingDays × shapeFactor[current]` (= run-rate × remaining days, since `shapeFactor[current]=1`) — consistent with the forecast-remaining rule already in place.

## Data

- **Trailing-30-day per product** (`runUnitsPerDay`, `runSpendPerDay`): a new aggregate — either a small `V_UNIFIED_DAILY` Cube/SQL query on PlanPage (Σ units, Σ adCost over the last 30 days per `productShortName`) passed into the wizard, or derived from the existing weekly actuals (`actualsWeekly`, last ~4 weeks). Prefer the explicit 30-day query for accuracy.
- **`demandMap`** — already loaded in the wizard (props).
- **`daysInMonth`** — existing constant.

No new BigQuery object (V_UNIFIED_DAILY exists; demandMap exists).

## Consistency

The Ads Path is the single forecast source for planned families (per the prior work), so changing its anchor flows automatically to the snapshot, the coach targets, the Plan-page columns, and the order. **Follow-up (not this spec):** align the `runSim` fallback path to the same run-rate start so un-planned families match too; today runSim uses its own growth + new-product model.

## Testing

- **Unit (`planTypes.ts`):** a pure `runRateAnchor(runPerDay, shapeByMonth, daysByMonth, months)` builder — verifies `anchor[m] = runPerDay × days[m] × shape[m]`, `shape[current]=1` ⇒ current month = run-rate, and the zero/missing-shape fallback to 1.
- **Live:** open the LolliME wizard → Ads Path/Spend Plan → confirm the mid-year months (Jun–Oct '26) forecast **≈ the current ~40/day run-rate × seasonality**, not the old ~22/day; Dec still peaks; the headline/curve/columns all reflect it.

## Scope

**Changes:** PlanPage computes the trailing-30-day per-product run-rate; PlanWizard builds `anchorUnits`/`anchorSpend` from run-rate × holiday-shape (replacing `monthlyUnits2025`/`monthlySpend2025`); a pure builder + test in `planTypes.ts`.

**Keeps unchanged:** the profit-max math, the order logic, the coach/snapshot wiring, the season elasticities, `computeSeasonality` (no longer the Ads Path shape source, but other callers keep it).

**Out of scope:** aligning the `runSim` fallback (follow-up); changing `V_FORECAST_DEMAND`; per-product elasticities.

## Open questions / risks

- **Thin 30-day data for brand-new products** (just launched, <30 days of sales): the run-rate is noisy/low. Mitigation: if a product has < N days of data, fall back to its `demandMap` level for the current month (don't force a near-zero run-rate). Confirm N (e.g. 14 days) at implementation.
- **Shape normalization month:** normalizing to the *current* calendar month assumes `demandMap[current]` is representative; if the current month is itself a holiday outlier, the whole curve shifts. Acceptable; revisit if a family looks off.
- **Spend re-leveling:** re-leveling spend by the same factor assumes the current efficiency holds across seasons; the season elasticity still adjusts marginal returns, so this only sets the anchor, not the optimum.
