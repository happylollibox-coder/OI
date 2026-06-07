# Forecast Starting Point = Weighted Run-Rate × Last-Year Seasonal Shape

**Date:** 2026-06-03 · **Revised:** 2026-06-07 (concrete recipe + scope locked via brainstorming)
**Component:** `dashboard-react/src/planTypes.ts` (pure builders), `dashboard-react/src/pages/PlanPage.tsx` (trailing daily data + LY shape), `dashboard-react/src/components/PlanWizard.tsx` (StepGrowth display) + `StepAdsPath.tsx` (order anchor)
**Status:** Design approved (all forks resolved), pending spec review
**Builds on:** the wizard-sourced-forecast + consistency work — the Ads Path profit-max engine is the single forecast source that drives the plan/order/coach.

## Problem

Both wizard forecasts anchor on the **same month in 2025**, and both break for a young/growing family because LolliME's 2025 baseline ≈ 0:

- **Step 3 (Ads Path / order):** `units(S) = units₂₅ × (S/spend₂₅)^e`. With `units₂₅ ≈ 0` (LolliME June 2025 = 0, pre-launch) the anchor collapses to a thin season benchmark → the order under-calls June at **~9/day** while LolliME actually sells **~40/day**.
- **Step 2 (Growth / "Monthly Demand by Channel" display):** future months = `LY_units[M] × YoY_growth`, where `YoY_growth = units₂₆(Jan–Jun) / units₂₅(Jan–Jun) = ~200 / ~0 = +98,900%`. A guard routes *off-season* future months to the within-year trend, but **peak months (Sep–Dec) skip the guard** (`isOffSeason` false) and compute `LY × 990` → **Dec 166,991, Year 8.3M units**.

Same zero, opposite roles (anchor *level* vs. growth *divisor*), opposite blow-ups. The cure is to stop anchoring on 2025 and instead anchor on the **current run-rate**, shaped by a **last-year seasonal curve** that is launch-aware and divide-by-zero-safe.

## Decisions (locked)

1. **Level = weighted trailing run-rate** (recency-weighted), not raw 2025.
2. **Seasonality = last-year monthly multipliers**, normalized so the **current month = 1**.
3. **Launch-ramp exclusion:** a product's own LY months are only trusted from **launch + 3** onward (drop the first 3 post-launch months — they're low because *new*, not seasonal).
4. **Reference fallback:** months a product can't supply (the current-month anchor + pre-launch + launch-ramp months) are borrowed from the **most-mature full-year family** (resolves to **Lollibox**), stitched onto the product's own clean months.
5. **Scope = both tables, one model:** the same shape drives **Step 2's display** and **Step 3's order anchor**, so they stop exploding/under-calling and stay consistent.

## Model

### 1. Level — weighted run-rate (pure: `weightedRunRate`)
Four trailing 7-day buckets ending at the latest data date (`latestDataDate`, already plumbed from `DataFreshness.maxDate`), weighted toward recency:

```
ratePerDay = 0.40·(Σwk1/7) + 0.30·(Σwk2/7) + 0.20·(Σwk3/7) + 0.10·(Σwk4/7)
```
- 28 days = 4×7 (reading "30 days" as 4 whole weeks; weights sum to 1.0).
- Computed **per product** for **units/day** and **ad-spend/day** from `V_UNIFIED_DAILY`, giving a coherent `(unitsPerDay, spendPerDay)` pair.
- Pure signature: `weightedRunRate(dailyValues: {date, value}[], asOf: Date, weights = [0.4,0.3,0.2,0.1]) → number`. Bucket *i* = days `[asOf-7i-6 … asOf-7i]`; a bucket with no days contributes 0 (its weight still divides by 7 so a partial recent week isn't over-counted). Robust to missing days.

### 2. Seasonal shape — `s[M]`, current month = 1 (pure: `seasonalShape`)
Per family (seasonality is a family trait; one shape used by both steps):

- `own[M]` = the family's 2025 monthly units, **only for clean months** `M ≥ launchMonth + 3`; else undefined. `launchMonth` = first 2025 month with units above a small floor.
- `ref[M]` = the reference family's (Lollibox) 2025 monthly units — full year, always defined.
- **Stitch scale** `a = mean over clean overlap months of ( own[M] / ref[M] )` (how much hotter/cooler this family runs vs the reference). If there is no clean overlap, `a = 1`.
- **Expected-units curve:**
  - `u[M] = own[M]` for clean own months (keeps the family's *real* holiday peak)
  - `u[M] = a · ref[M]` for every other month — **including the current month** (this is how the current-month anchor gets a non-zero value when own LY is 0)
- `s[M] = u[M] / u[currentMonth]` (so `s[currentMonth] = 1` by construction).

**Degenerate cases, same formula:** a fully-mature family (Lollibox itself) → all months clean → pure own shape, reference unused. A brand-new family (no clean months) → `a` undefined → pure reference shape (`s[M] = ref[M]/ref[currentMonth]`).

**Reference resolution:** the reference is derived, not hard-coded — the family with a complete 12-month 2025 history, a non-zero current month, and the largest annual volume → **Lollibox** today. (Per-family configurable reference via `DE_NEW_PRODUCT_MODEL` was offered and deferred — YAGNI for v1.)

**Worked example — LolliME, June current:** clean own = Oct/Nov/Dec; `a ≈ 1.23`. Forward shape: Jun **1.00** · Jul 0.72 · Aug 1.04 · Sep 1.46 · Oct 1.20 · Nov **3.58** · Dec **9.32**. (Dec ≈ 9× June, not the raw 21× — the 21× was inflated by the artificially-low launch-Jul base, now excluded.) Forecast Dec = 40/d × 31 × 9.32 ≈ **11,556 units** — sane, vs today's 166,991 (display) and ~9/d (order). Minor seam: the reference-borrowed Sep (1.46) slightly exceeds the own Oct (1.20) — an acceptable stitch artifact since `a` is a mean over the clean overlap.

### 3. Anchor (Step 3 — order)
```
anchorUnits[product][M] = unitsPerDay[product] · daysInMonth[M] · s[family][M]
anchorSpend[product][M] = spendPerDay[product] · daysInMonth[M] · s[family][M]
```
Family anchor = Σ products. **Replaces** `monthlyUnits2025` / `monthlySpend2025` feeding `StepAdsPath`. The profit-max engine, season elasticities, order logic, coach, and snapshot are **unchanged** — they receive a current-reality `(units, spend)` anchor instead of stale 2025. Current-month proration (forecast-remaining) is unchanged: `s[currentMonth] = 1` ⇒ current month = run-rate × remaining days.

### 4. Display (Step 2 — Growth table)
Replace the future-month projection (PlanWizard L499–511) for **both** channels:
```
proj_channel[M] = recentRate_channel · daysInMonth[M] · s[family][M]
```
- `recentRate_channel` = the existing per-channel current daily rate already computed by `offSeasonTrend` (`brandTrend.recentRate`, `nbTrend.recentRate`). Branded-search is monthly, so there's no clean daily channel split to re-weight; the existing recent-rate is the channel level. (The weighted run-rate from §1 is reserved for the order anchor, which has daily product data.)
- Drop the `noUsableBase` / `isOffSeason` gating and the `LY × growth` branch entirely — every future month uses run-rate × shape, so peak months can no longer explode. Current-month remaining is already `recentRate × daysRemaining` (= shape 1.0) and stays.
- The headline cards (+30 % / +49 % trend %) already use the trend path (prior fix `f84e507`) and are unchanged.

## Data

- **Trailing daily per product** (`V_UNIFIED_DAILY`, last 28 days, units + adCost per `productShortName`): a new PlanPage Cube query (or reuse a daily pull), passed into the wizard.
- **LY monthly units per family** (`own[M]`, `ref[M]`): from a 2025 monthly Cube pull per family (the Step-2 data already has family monthly units via `brandedSearch`; the reference needs full-year family units — add Lollibox to that pull or a small dedicated query).
- **`latestDataDate`** — already plumbed (FACT_AMAZON_PERFORMANCE_DAILY max).
- **`launchMonth`** — first 2025 month above a small floor (or reuse `offSeasonTrend(...).launch`).

No new BigQuery object (`V_UNIFIED_DAILY` exists).

## Consistency

The Ads Path is the single forecast source for planned families, so the new anchor flows automatically to the snapshot, coach targets, Plan-page columns, and the order. With Step 2 on the same `s[M]`, the Growth display and the order now agree on the shape. **Follow-up (not this spec):** align the `runSim` fallback (unplanned families) to the same run-rate start.

## Testing

- **Unit (`planTypes.ts`):**
  - `weightedRunRate` — exact weights (e.g. uniform 7/day across 4 weeks → 7), recency weighting (recent week dominates), missing-day robustness, partial recent week.
  - `seasonalShape` — `s[currentMonth] = 1` always; mature family → pure own shape (reference unused); young family (current-month own = 0) → stitched, `s[Dec]` finite and ≈ reference-scaled; brand-new (no clean months) → pure reference shape; launch-ramp months excluded; never divides by zero.
- **Live:** open the LolliME wizard → Step 2 shows a sane Dec (~11.5K, **not** 166,991) and a realistic Year total; Step 3 trajectory/curve mid-year ≈ ~40/day (not ~9), Dec peaks; both tables agree on the shape; Lollibox (mature) is unchanged.

## Scope

**Changes:** two pure builders + tests in `planTypes.ts` (`weightedRunRate`, `seasonalShape`); PlanPage computes the trailing-28-day per-product run-rate and the per-family LY-shape inputs (incl. the Lollibox reference); StepAdsPath anchor = run-rate × shape (replacing `monthlyUnits2025`/`monthlySpend2025`); StepGrowth future-month projection = recentRate × shape (removing the `LY × growth` explosion path).

**Keeps unchanged:** the profit-max math, order logic, coach/snapshot wiring, season elasticities, the headline trend cards, the current-month proration/cutoff (just-shipped), `computeSeasonality` (other callers).

**Out of scope:** aligning the `runSim` fallback (follow-up); per-family configurable reference via `DE_NEW_PRODUCT_MODEL` (deferred); re-weighting Step 2's channel level to a daily weighted run-rate (needs daily channel data); per-product (vs per-family) seasonal shape.

## Open questions / risks

- **Reference seasonality ≠ target seasonality.** Borrowing Lollibox's off-season/early-year shape for LolliME assumes similar seasonality outside the holiday peak. Accepted; LolliME's own peak (Oct–Dec) is preserved, only the low months are borrowed.
- **Stitch scale `a` on thin overlap.** With only 3 clean own months, `a` is a 3-point mean; an outlier month skews it. Mitigation: `a` is a mean (not a single ratio); revisit if a family looks off.
- **Step 2 vs Step 3 level mismatch.** Step 2 uses per-channel `recentRate` (monthly branded-search) while Step 3 uses the weighted daily run-rate — different universes (branded-search demand vs total units), so absolute levels won't match exactly. They share the *shape*; that's the consistency that matters. Documented, not reconciled.
- **`launchMonth` detection floor.** Needs a sensible units floor so a single stray early sale isn't treated as launch. Reuse `offSeasonTrend`'s launch detection for consistency.
