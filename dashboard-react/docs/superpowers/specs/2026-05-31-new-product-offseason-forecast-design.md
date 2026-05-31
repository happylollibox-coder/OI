# New-Product Off-Season Forecast (Growth Step)

**Date:** 2026-05-31
**Area:** `dashboard-react` — Planning Wizard, Step 2 (Growth), `StepGrowth` in `PlanWizard.tsx`
**Status:** Approved design → implementation

## Problem

The Growth step forecasts future demand as `LY_same_month × growth`, where
`growth = thisYear_YTD / lastYear_YTD` and defaults to `×1.0` when last year is zero
(`PlanWizard.tsx:415`). For a product launched mid-prior-year (e.g. LolliME, first sales
≈ Jun 2025), the early-year months have **no 2025 baseline**, so:

- The growth cards show a meaningless "30 vs 0 → 0%".
- The forecast for Jan–Jun 2026 collapses to ≈0 (and "MayF" renders "—"), even though
  2026 actuals show LolliME is now an established seller (~800–900 units/mo).

YoY is the wrong comparison when there is no comparable prior-year season.

## Goal

For forecast months that lack a usable prior-year base, derive demand from the product's
**own within-year off-season momentum** instead of copying a non-existent prior year —
comparing like season to like season (off→off), and never using the unsteady launch period.

## Decisions (from brainstorming)

1. **Scope:** Apply the new method **only** to forecast months whose prior-year same-month
   value is ~0 (no usable LY base). Months with a real 2025 base keep current YoY.
2. **Warmup exclusion:** A product's **first 3 months post-launch** are excluded from all
   baseline/growth/window math (still ramping, not steady-state).
3. **Output:** **Trended run-rate.** Base = recent off-season units/day; momentum from
   "last off-season month vs prior 2 off-season months"; forecast carried forward gently
   trended. Growth card shows this momentum (labeled as off-season trend, not YoY).
4. **Window grain:** **Monthly approximation** — "last 30 off-season days" ≈ most recent
   completed off-season month; "30–90 days" ≈ the prior 2 off-season months. Day-normalized.
5. **Channels:** Computed independently for **Brand** and **Non-brand** (matches existing
   `brandGrowth` / `nbGrowth`).

## Method (per channel)

Inputs: per-month units (both years), off-season classifier, launch month, cutoff (current
month + elapsed fraction `prorateFactor`).

1. **Launch + warmup:** launch month = first chronological month with non-trivial demand
   (units > threshold). Drop launch month + next 2 from all calcs. *(Family-level, since the
   Growth step is family-grained.)*
2. **Off-season month set:** a calendar month is off-season when its `seasonMap` entry has
   `peakDays === 0`. Only post-warmup off-season months are "usable".
3. **Two-period split** (over ALL usable off-season months, chronological): split the list in
   half — **first period** (earlier) and **second period** (later). Day-normalize each:
   `firstRate = Σunits(first)/Σdays(first)`, `secondRate = Σunits(second)/Σdays(second)`.
   The current/cutoff month is prorated by `prorateFactor`. A single usable month → no trend.
4. **Momentum:** `m = clamp(secondRate / firstRate, 0.5, 1.8)`. This is a robust period-to-period
   trend over the whole usable window (not a noisy single-month comparison).
5. **Forecast for a missing-LY off-season month** `M`:
   `units(M) = secondRate × daysInMonth(M) × g^k`, where the period-to-period momentum is spread
   into a **per-month** rate `g = m^(1/gap)` (`gap` = months between the two period midpoints),
   `k` = months from the most recent usable off-season month to `M`. Spreading by `gap` prevents
   a multi-month trend from re-compounding monthly into explosive values.

## Trigger (per future month, per channel)

- LY same-month usable (`> threshold`) → **keep current YoY** (`LY × growth`).
- LY ~0 **and** month is **off-season** → **trended run-rate** (above).
- LY ~0 **and** month is **peak/pre-peak** (product launched after last peak — rare; LolliME
  does not hit this) → **fallback to current behavior**, surface a flag. Out of scope to
  forecast a never-observed peak.

## Growth cards

For a new product, replace "X vs 0 → 0%" with the within-year **off-season trend** (`m` as %),
labeled clearly (show the two window run-rates) so it reads as off-season-vs-off-season.

## Guards / fallbacks

- < 1 usable recent + 1 usable prior off-season month after warmup → drop trend, use flat
  `recentRate`; if nothing usable, current `×1` behavior.
- Momentum clamped to [0.5, 1.8].

## Implementation shape

- **Pure helper** in `planTypes.ts`:
  `offSeasonTrend(history, isOffSeason, launchYM, cutoff)` → `{ recentRate, priorRate,
  momentum, usable, forecastUnits(year, month) }`. Unit-tested in isolation (TDD).
- **Wiring:** in `StepGrowth`'s `brandComparison` future-month branch (`PlanWizard.tsx`
  ~464–472), for a missing-LY off-season month call the helper instead of `LY × growth`.
  Pass `seasonMap` into `StepGrowth` (already a `PlanWizard` prop).
- Forecast flows downstream unchanged (Ads Path / Spend Plan / Order consume it).

## Tests (pure helper)

- LolliME-like: early off-season months filled from off-season run-rate, trend applied.
- Warmup exclusion: first 3 months ignored.
- Insufficient data → flat / passthrough fallback.
- Momentum clamp at both ends.
- "LY exists" months untouched (helper not invoked).

## Out of scope

- Per-product (vs family-level) warmup detection.
- Forecasting a never-observed peak for a post-peak launch.
- Weekly/daily window grain.
