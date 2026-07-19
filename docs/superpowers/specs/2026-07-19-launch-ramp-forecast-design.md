# Launch-Ramp Forecast — Design Spec

**Date:** 2026-07-19
**Area:** `V_FORECAST_DEMAND` (Phase 1 & Phase 2, new-product forecasting)
**Status:** Approved design → ready for implementation plan

---

## Problem

For a new-product family, the demand forecast produces a nonsensical month-to-month
shape. Concretely, the Bunny family (all 12 SKUs `PHASE_2`, donor = `Mint LolliME`)
forecasts **July 233 → August 80 → September 150** — August craters to ~⅓ of July
even though neither month has a holiday and the product is a low-flat launch.

### Root causes (verified against the warehouse)

1. **Corrupted seasonality index.** `V_FORECAST_DEMAND` (Part D) reshapes a new
   product by its donor's calendar seasonality from `V_PRODUCT_SEASONALITY_INDEX`.
   LolliME's **August index = 0.251** — the lowest month of its year — is built from
   only **2 days / 11 units**: the 60-day launch-exclusion (`V_PRODUCT_SEASONALITY_INDEX.sql:40`)
   wipes out August 2025 (LolliME's first Aug, launched 2025-07-01), and August 2026
   hasn't happened. Every SKU cloned off LolliME inherits that 2-day artifact.

2. **Young donor can't define seasonality.** LolliME (~12 months old) samples each
   calendar month at a *different product age* — "July" index from mature Jul 2026
   (16/day), "September" index from mid-launch Sep 2025 (11/day). Its calendar shape
   is launch-ramp pollution, not real seasonality.

3. **No launch-growth term.** `PHASE_2` holds a flat trailing rate and only reshapes
   it by (corrupted) calendar seasonality. It cannot express a launch that ramps —
   the exact case for a new product with aggressive ad investment. LolliME itself grew
   **~2.4× over its first 6 months** (de-seasonalized); the model captures none of it.

### Verified reference data

House-blend seasonality (volume-weighted, ≥365-day products: Lollibox + Fresh + Bottle):

| Mon | Jan | Feb | Mar | Apr | May | Jun | Jul | Aug | Sep | Oct | Nov | Dec |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| idx | .556 | .562 | .648 | .903 | .480 | .470 | **.422** | **.588** | .641 | .712 | 1.686 | 4.169 |

Real low season is **summer (May–Jul)**, not August. With a real calendar Bunny's
August (.588) is *higher* than July (.422) — August rises, not craters.

LolliME de-seasonalized launch growth by age (÷ house-blend), normalized to age 1:

| Age (mo) | 1 | 2 | 3 | 4 | 5 | 6 | 7+ |
|---|---|---|---|---|---|---|---|
| ramp | 1.00 | 1.06 | 1.62 | 1.65 | 2.14 | 2.33 | ~2.4 (plateau) |

A clean S-curve: ramp for ~6 months, then plateau.

---

## Decisions (locked with owner)

1. **The donor is the user's launch-page choice** (`DE_NEW_PRODUCT_MODEL`, per family).
   The system does not override it. Pick LolliME → the product grows like LolliME.
2. **Clean growth + real calendar.** Separate the donor's launch *growth* (applied by
   product age) from *calendar seasonality* (applied by calendar month), so a
   May-launched product's Christmas lands in December — not at "launch-month 5".
3. **Donor drives the ramp always. Seasonality auto-falls-back:** the donor's own
   calendar seasonality is used only when the donor has ≥2 years of clean history;
   otherwise seasonality comes from the mature **house-blend**. LolliME (~1yr) → blend
   today; auto-switches to its own when it matures. (Christmas depth ≈ identical across
   all gift products, so the blend is a faithful stand-in.)
4. **Reasonableness cap (guard B)** on thin-history launches, so a not-yet-ramping
   product can't compound a large ramp × steep-Christmas into an implausible December
   off an 8-week trend. Ceilings lift automatically as real actuals raise the anchor.

---

## Model

For a new product **P**, forecast month **F** (Phase 1 & Phase 2 model path):

```
forecast(F) = anchor_rate
            × ramp(age_F)   / ramp(age_now)          -- donor launch growth, by product age
            × season(cal_F) / season(cal_now)        -- donor-own if ≥2yr else house-blend
            × days_in_month(F)
```

- `age_now` / `age_F` = P's age in months (from `estimated_start_selling_date`) at the
  current date / at month F. `age = DATE_DIFF(month_trunc(F), month_trunc(start), MONTH) + 1`.
- `anchor_rate` — **Phase 2:** P's own trailing daily rate (existing `trailing_14d`).
  **Phase 1** (cold-start, <30d own data): donor's month-1 daily rate (existing
  `model_first_month`, via `DE_NEW_PRODUCT_MODEL`).
- The `/ ramp(age_now)` and `/ season(cal_now)` terms de-stage and de-season the anchor;
  the numerators re-apply growth and season at the target month. Same de-seasonalize /
  re-seasonalize structure the current Phase-2 already uses — we add the `ramp` factor
  and replace the seasonality source.

### ramp(age)
De-seasonalized donor growth by age, smoothed to be monotonic and **held flat after the
plateau age** (first age at which growth stops materially increasing, ~month 6). Holding
the plateau avoids the noisy de-seasonalized tail (a10–a12, where dividing low-season
summer months inflates). Beyond P's 365-day mark P becomes `PHASE_3` (family-based,
Parts A–C) and leaves this path entirely.

### season(cal)
- Donor's own `V_PRODUCT_SEASONALITY_INDEX` **iff** donor history ≥ 730 days AND every
  calendar month clears the `num_days ≥ 15` guard; **else** `V_HOUSE_SEASONALITY`.
- Today only Lollibox clearly qualifies for own-season; LolliME / Bottle / Fresh → blend.

### Reasonableness cap (guard B)
For a thin-history launch (P's own history < 120 days), bound each month:

- **RAMP_CEIL = 2.0** — de-seasonalized monthly units ≤ `RAMP_CEIL × anchor-month units`
  (the launch can at most ~double its baseline velocity via the ramp within the horizon).
- **SEASON_CEIL = 5.0** — total monthly forecast ≤ `SEASON_CEIL × anchor-month units`
  (an unproven launch's first Christmas is bounded to 5× its current run-rate month).

Both ceilings scale off `anchor_rate`, so they rise automatically as P accrues real
sales. Constants live in the view with a comment; promote to a `DE_` threshold row if
tuning proves necessary. **These two ceilings are the parameters to validate against real
numbers during implementation** (see Testing).

---

## Components

| # | Object | Type | Change |
|---|---|---|---|
| 1 | `V_HOUSE_SEASONALITY` | **new view** | Volume-weighted blended seasonality index across all ≥365-day products; `num_days ≥ 15` per month. Output: `calendar_month, house_season_index`. |
| 2 | `V_LAUNCH_RAMP` | **new view** | Donor's de-seasonalized growth by age-month, smoothed, monotonic, plateau-held. Output: `donor_product, launch_age_month, ramp_factor`. |
| 3 | `V_PRODUCT_SEASONALITY_INDEX` | edit | Add `num_days ≥ 15` guard so a thin month falls back (neighbor-avg / 1.0) instead of emitting a 2-day noise value. Gates the ≥2yr donor-own-season path. |
| 4 | `V_FORECAST_DEMAND` | edit | Replace Part D's `base_daily_rate / current_month_seasonality × seasonality_index` reshape with `anchor × ramp-ratio × season-ratio × days`, plus guard B. Parts A–C (Phase 3) untouched. |
| 5 | `config.yaml` | edit | Register the two new views. |

Untouched: `DE_NEW_PRODUCT_MODEL`, the launch-page UI, Phase 3 (Parts A–C), the
`SP_LOAD_FACT_FORECAST_DEMAND` → `FACT_FORECAST_DEMAND` → Cube chain (reads the same
view; only its Phase-1/2 rows change).

---

## Expected result — Bunny (donor LolliME, anchor ~7.5/day, age 3 / July)

| Month | Now (buggy) | New model | Guard-B capped |
|---|---|---|---|
| Jul | 233 | 233 | 233 |
| **Aug** | **80** | ~330 | ~330 |
| Sep | 150 | ~450 | ~450 |
| Oct | 152 | ~560 | ~560 |
| Nov | — | ~1,330 | ~1,165 (5× cap) |
| Dec | — | ~3,000+ | ~1,165 (5× cap) |

August stops cratering (80 → ~330); the near-term shape is corrected; guard B keeps the
first unproven Christmas bounded to 5× the current run-rate month until actuals confirm.

---

## Testing

1. **Unit / SQL sanity** — `V_HOUSE_SEASONALITY` sums to annual-avg ≈ 1.0 across months;
   `V_LAUNCH_RAMP` monotonic non-decreasing then flat; `num_days ≥ 15` guard removes the
   LolliME Aug row / replaces its index.
2. **Regression** — Phase-3 (mature) forecasts unchanged before/after (Parts A–C intact).
3. **Bunny end-to-end** — August no longer < July; full 2026 curve matches the table
   above within rounding; guard B binds only on Nov/Dec.
4. **LolliBall** — second LolliME-donor launch behaves consistently.
5. **Parameter validation** — inspect `RAMP_CEIL` / `SEASON_CEIL` effect on Bunny +
   LolliBall Nov/Dec; confirm the ceilings tame the compounding without clipping the
   near-term (Aug–Oct) fix. Adjust defaults if the capped Christmas looks wrong vs the
   owner's expectation.
6. **Refresh path** — after view deploy, run the `SP_LOAD_FACT_FORECAST_DEMAND` →
   Cube-table refresh and confirm the Plan page chart reflects the corrected curve.

---

## Out of scope

- 12-SKU fragmentation of Bunny (merchandising/ads-focus issue, not forecast).
- Reworking Phase-3 family-based logic (Parts A–C).
- Moving `RAMP_CEIL` / `SEASON_CEIL` into a `DE_` threshold table (do only if tuning
  demands it).
