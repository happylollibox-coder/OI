# Forecast Starting Point = Current 30-Day Run-Rate (× holiday shape)

**Date:** 2026-06-03
**Component:** `dashboard-react/src/components/PlanWizard.tsx` (the `monthlyUnits2025` / `monthlySpend2025` anchors fed to `StepAdsPath`), `dashboard-react/src/pages/PlanPage.tsx` (trailing-30-day data), `dashboard-react/src/planTypes.ts` (pure anchor builder)
**Status:** Design approved (approach + forks), pending spec review
**Builds on:** the wizard-sourced-forecast + consistency work — the Ads Path profit-max engine is the single forecast source for planned families.

## Problem

The Ads Path engine anchors each month to the **same month in 2025** (`monthlyUnits2025` / `monthlySpend2025`, raw actuals). For a young/growing family this is stale: **LolliME June 2025 = 0 units** (pre-launch), so the Jun '26 forecast has no real anchor and falls back to a season-benchmark (~22/day) — while LolliME actually sells a steady **~40/day** in 2026. The family's YoY growth never reaches the Ads Path (the Step-2 growth factor only feeds the runSim/demand path). Result: young/growing families are systematically under-forecast in their ramp months.

## Decisions (from brainstorming)

- **Approach A:** for **established** products the **starting point = the current 30-day run-rate** (the *level*), projected forward with a **seasonal shape** (so Dec still peaks).
- **New products:** the 30-day run-rate is too thin → forecast off the **associated model product's first-year launch pattern** (the existing `demandMap` PHASE_1/PHASE_2 model). The model-product association is **per family** (`DE_NEW_PRODUCT_MODEL`) and becomes **display + editable in the wizard** (persisting via the existing endpoints).
- **Scope:** **all products** — established ones via run-rate, new ones via the model product. Both branches feed the **Ads Path anchor** (today new products there fall back to a generic season benchmark; the model product only feeds runSim, so this wires it in).
- **Seasonal shape source (established):** the **holiday demand model** (`V_FORECAST_DEMAND` / `demandMap`), new-product-aware and **not** distorted by a family's own 2025 ramp — unlike `computeSeasonality`.

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

### 3b. New products — model-product launch pattern (not run-rate)
For a product where `metaMap[product].isNew` is true, **do not** use its (thin) 30-day run-rate. Instead set the Ads Path anchor from the model-based forecast that already exists per product in `demandMap` (driven by the family's `model_product` via `DE_NEW_PRODUCT_MODEL`, PHASE_1/PHASE_2):
```
anchorUnits[product][m] = demandMap[product][m]                 // model launch-pattern units
anchorSpend[product][m] = anchorUnits[product][m] × spendPerUnit  // see below
```
`spendPerUnit` for a new product comes from the family's recent ad efficiency (the season-benchmark spend÷units already used by the profit-max fallback) or the model product's spend-per-unit — so the `(units, spend)` anchor pair is coherent. This is the branch that actually **wires the model product into the Ads Path** (currently absent — new products there get the generic season fallback).

**Selection per product:** `isNew ? modelAnchor (3b) : runRateAnchor (3)`. Both replace the raw-2025 anchor.

### 4. Profit-max engine unchanged
`profitMaxSpend` / `unitsAtSpend` / the season elasticities are untouched — they just receive the current-reality `(anchorUnits, anchorSpend)` instead of stale 2025. At the anchor spend the model reproduces the current run-rate × seasonality; it then optimizes spend around that.

### 5. Current month
The trailing-30-day rate **is** the current pace, so the current month's forecast = `runUnitsPerDay × remainingDays × shapeFactor[current]` (= run-rate × remaining days, since `shapeFactor[current]=1`) — consistent with the forecast-remaining rule already in place.

## Wizard — model-product editor (display + edit)

For families that contain new products, the wizard surfaces the **model product** that drives their launch forecast, and lets the user change it:
- **Display:** in the wizard (Baseline or Growth step), show `family → model_product` (e.g. "New products modeled on: Mint LolliME"). Today this only appears as a MODEL/HYBRID tooltip badge in the family table.
- **Edit:** a dropdown of candidate established products (from `GET /api/products`, excluding new/draft items), defaulting to the current `model_product`. On change, `POST` the upsert to **`DE_NEW_PRODUCT_MODEL`** (`{ family, model_product }`) via the existing endpoint (~app.py:6602, which UPSERTs + should `clear_data_cache()`).
- **No new backend:** the GET (~app.py:6541), the upsert POST, and `/api/products` already exist.

**Recompute timing (flagged):** `demandMap`/`V_FORECAST_DEMAND` is server-computed from the model product, so changing it persists immediately but the **forecast curve reflects the new model only after `V_FORECAST_DEMAND` recomputes** (next data refresh / SP run). v1: persist now + show the new association immediately, with a note that the forecast updates on the next refresh. (Client-side recompute from the chosen model's pattern is a possible follow-up.)

## Data

- **Trailing-30-day per product** (`runUnitsPerDay`, `runSpendPerDay`): a new aggregate — either a small `V_UNIFIED_DAILY` Cube/SQL query on PlanPage (Σ units, Σ adCost over the last 30 days per `productShortName`) passed into the wizard, or derived from the existing weekly actuals (`actualsWeekly`, last ~4 weeks). Prefer the explicit 30-day query for accuracy.
- **`demandMap`** — already loaded in the wizard (props).
- **`daysInMonth`** — existing constant.

No new BigQuery object (V_UNIFIED_DAILY exists; demandMap exists).

## Consistency

The Ads Path is the single forecast source for planned families (per the prior work), so changing its anchor flows automatically to the snapshot, the coach targets, the Plan-page columns, and the order. **Follow-up (not this spec):** align the `runSim` fallback path to the same run-rate start so un-planned families match too; today runSim uses its own growth + new-product model.

## Testing

- **Unit (`planTypes.ts`):** a pure `runRateAnchor(runPerDay, shapeByMonth, daysByMonth, months)` builder — verifies `anchor[m] = runPerDay × days[m] × shape[m]`, `shape[current]=1` ⇒ current month = run-rate, and the zero/missing-shape fallback to 1.
- **Unit (branch selection):** a pure `productAnchor` selector — `isNew` product → uses the model/`demandMap` units; established → uses the run-rate anchor. Verifies the switch and that a new product never produces a near-zero anchor from thin run-rate data.
- **Live:** open the LolliME wizard → Ads Path/Spend Plan → confirm the mid-year months (Jun–Oct '26) forecast **≈ the current ~40/day run-rate × seasonality**, not the old ~22/day; Dec still peaks; the headline/curve/columns all reflect it.

## Scope

**Changes:** PlanPage computes the trailing-30-day per-product run-rate; PlanWizard builds the Ads Path anchor per product — established = run-rate × holiday shape, new = `demandMap` model launch pattern (replacing `monthlyUnits2025`/`monthlySpend2025`); a pure anchor builder + test in `planTypes.ts`; a wizard model-product display+edit control wired to the existing `DE_NEW_PRODUCT_MODEL` GET/upsert + `/api/products`.

**Keeps unchanged:** the profit-max math, the order logic, the coach/snapshot wiring, the season elasticities, `V_FORECAST_DEMAND` (consumed, not changed), the new-product-model backend endpoints (reused), `computeSeasonality` (no longer the Ads Path shape source, but other callers keep it).

**Out of scope:** aligning the `runSim` fallback (follow-up); client-side recompute on model-product change (follow-up); re-keying `DE_NEW_PRODUCT_MODEL` to per-product (staying per-family); per-product elasticities.

## Open questions / risks

- **`isNew` flag = the branch switch.** New products use the model launch pattern (3b); established use the 30-day run-rate (3). The `metaMap[product].isNew` flag (from `ForecastDemand`) is the discriminator — confirm it's reliable (a product transitions new→established over time; when it does it should move to the run-rate branch automatically once it has a real 30-day history).
- **Model-edit recompute lag** (above): changing the model product reflects in the forecast only after `V_FORECAST_DEMAND` recomputes. Accepted for v1.
- **Shape normalization month** (established): normalizing to the *current* calendar month assumes `demandMap[current]` is representative; if the current month is a holiday outlier, the whole curve shifts. Acceptable; revisit if a family looks off.
- **Spend re-leveling:** re-leveling spend by the same factor assumes current efficiency holds across seasons; the season elasticity still adjusts marginal returns, so this only sets the anchor, not the optimum.
