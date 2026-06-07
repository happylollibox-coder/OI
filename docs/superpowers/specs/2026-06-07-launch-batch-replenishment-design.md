# Mechanism B — Launch Batch Replenishment (just-launched products)

**Date:** 2026-06-07
**Component:** `scripts/bigquery/views/V_PLAN_FORECAST.sql` (the demand source for the replenishment engine). `SP_GENERATE_SHIPMENT_PLAN` and the React side are consumers, **unchanged**.
**Status:** Design approved (all forks resolved), pending spec review
**Builds on:** the run-rate forecast anchor (Mechanism A). A just-launched product has no clean own last-year month, so Mechanism A's forecast for it is a thin run-rate × reference shape — fine as a *demand curve*, but a launch should not be committed to a full-year inventory plan. This spec governs how such a product is **ordered**.

## Problem

The replenishment engine is server-side: `V_PLAN_FORECAST` computes each product's demand (`daily_rate`, `demand_90d`, `q4_demand`, `days_until_oos`, …) and `SP_GENERATE_SHIPMENT_PLAN` cascades it into batches (EMERGENCY → EMERGENCY-PO → AWD_MAINTENANCE → Q4_BULK). The SP **already** does batch-by-batch reorder off `daily_rate`, **already** re-runs on the daily refresh (so "recalc" is automatic), and **already** surfaces "additional PO needed" via its EMERGENCY/PO-NEEDED types.

For a **just-launched** product the `daily_rate` comes from the **model forecast** (`adjusted_units ÷ 30`) and the engine plans the **full horizon, including a Q4 pre-buy**. That over-commits inventory to an unproven SKU. A launch should instead be replenished **gradually, in small batches sized from its own earliest sales**, recalculated as real sales accrue.

## Decisions (locked)

1. **Where:** a demand override in **`V_PLAN_FORECAST`** only. The SP and React are unchanged — they consume the corrected demand and stage batches exactly as today.
2. **Detection:** *just-launched* = first real sale (or `estimated_start_selling_date`) within the last **60 days** (tunable). A new `is_launching` boolean.
3. **Demand = own early run-rate**, over a **widening window** `MIN(days_since_first_sale, 30)` of actual `PURCHASED_UNITS` — not the model forecast.
4. **Horizon cap = lead + 1 month** for just-launched products — the engine only commits the next batch; no Q4 pre-buy.
5. **Seed batch** (pre-sales, no rate yet) = a **manual PO** (not auto-generated).
6. **Recalc** = automatic via the existing daily SP re-run.
7. **Graduation** at 60 days → normal Mechanism-A plan demand.
8. **`V_PRODUCT_LAUNCH_MODEL`** = `first_sale_date` for detection/windowing only; **not** a demand multiplier (own sales only).

## Model

### 1. `is_launching` flag (new column)
```
first_sale_date = COALESCE(
  (MIN sale date in FACT_AMAZON_PERFORMANCE_DAILY where PURCHASED_UNITS > 0),
  V_PRODUCT_LAUNCH_MODEL.first_sale_date,
  DIM_PRODUCT.estimated_start_selling_date)
is_launching = first_sale_date IS NOT NULL
            AND DATE_DIFF(CURRENT_DATE(), first_sale_date, DAY) <= 60
```
A product with no first sale yet (pre-launch) has `is_launching = FALSE` here and relies on the manual seed PO; it enters the override once it has ≥3 selling days (below).

### 2. Launch run-rate (replaces `daily_rate` for launching rows)
```
launch_window_days = LEAST(GREATEST(DATE_DIFF(CURRENT_DATE(), first_sale_date, DAY), 1), 30)
launch_units       = Σ PURCHASED_UNITS over the last `launch_window_days` days (own product)
launch_selling_days= COUNT(DISTINCT sale days in that window)        -- robustness vs gaps
launch_daily_rate  = launch_units / launch_window_days
```
- **Widening window** = `MIN(days_since_first_sale, 30)`: at day 3–5 it's the first-few-days rate (sizes batch 2); by day 30 it's the 30-day rate (sizes batch 3); the daily SP re-run re-sizes every day in between.
- **Floor:** require `launch_selling_days >= 3` before trusting the rate; below that, `daily_rate` stays 0 for the auto-engine (the manual seed batch covers days 0–N). Avoids day-1 noise driving a PO.
- **Source:** `FACT_AMAZON_PERFORMANCE_DAILY.PURCHASED_UNITS` — the same own-sales source as the existing `last_30d_sales` CTE.

### 3. Horizon cap (for launching rows)
The SP reads several demand windows off `daily_rate`. For `is_launching` rows, cap the long windows to a **single next-batch** of demand:
```
launch_horizon_days = full_lead_days + 30                     -- lead time + 1 review month
launch_demand_cap   = ROUND(launch_daily_rate * launch_horizon_days)
```
Apply the cap to the windows the SP uses for sizing the *forward* batches — `q4_demand`, `demand_90d`, and any window longer than `launch_horizon_days` → `LEAST(window, launch_demand_cap)`. Leave the **near-term/emergency** window and `days_until_oos = available_stock / daily_rate` as-is, so a low-stock launch still triggers its next batch. Net effect: the engine reorders to cover ~lead + 1 month at the current launch rate and **never pre-buys Q4** for a launch.

### 4. Everything downstream unchanged
`SP_GENERATE_SHIPMENT_PLAN` consumes the corrected `daily_rate` + capped windows and produces the same batch types; its daily re-run is the monthly recalc; its EMERGENCY/PO-NEEDED types are the "additional PO needed" signal. The React shipment timeline renders the resulting SUGGESTED rows with no change.

## Data

- `FACT_AMAZON_PERFORMANCE_DAILY` (`PURCHASED_UNITS`, `DATE`) — own early sales (already used by `last_30d_sales`).
- `V_PRODUCT_LAUNCH_MODEL.first_sale_date` / `DIM_PRODUCT.estimated_start_selling_date` — launch-date fallbacks for detection.
- `DIM_PRODUCT` `manufacture_day + shipment_days = full_lead_days` — already in V_PLAN_FORECAST's `inventory` CTE.

No new BigQuery object. The `V_PLAN_FORECAST` change must be re-registered in `config.yaml` (view definition update) per the project rule.

## Testing

- **SQL unit (dry-run / sample rows):**
  - A product launched 4 days ago with 3+ selling days → `is_launching = TRUE`, `launch_window_days = 4`, `daily_rate = launch_units/4`, windows capped to `(lead+30)×rate`, `q4_demand` ≤ cap.
  - A product launched 40 days ago → `launch_window_days = 30` (widened/clamped).
  - A product launched 70 days ago → `is_launching = FALSE` → unchanged Mechanism-A demand.
  - A pre-launch product (no sales) → `is_launching = FALSE`, `daily_rate = 0` (seed PO covers it); no auto-batch.
  - A launching product with only 1–2 selling days → rate floored to 0 (no PO from noise).
- **Live (compare SUGGESTED shipments before/after the view change):**
  - **Bunny** (launched ~May 2026, ~2/day): gets short next-batch suggestions off its own ~2/day, **no Q4_BULK pre-buy**; total committed ≈ lead + 1 month, not a year.
  - **LolliME / Lollibox** (established): SUGGESTED shipments **unchanged** (not launching).
  - Re-run `SP_GENERATE_SHIPMENT_PLAN` after deploying the view; confirm the Plan-page Shipment Plan reflects it.

## Scope

**Changes:** `V_PLAN_FORECAST.sql` — add `first_sale_date` + `is_launching`; for launching rows override `daily_rate` with the widening-window launch run-rate (with the ≥3-selling-day floor) and cap the long demand windows to `full_lead_days + 30` of demand. Re-register in `config.yaml`. Redeploy the view + re-run `SP_GENERATE_SHIPMENT_PLAN`.

**Keeps unchanged:** `SP_GENERATE_SHIPMENT_PLAN`, all React (`ShipmentEngine`, the wizard, Mechanism A), the 4 batch types, the daily refresh orchestration, `V_FORECAST_DEMAND`.

**Out of scope:** auto-generating the seed batch (stays a manual PO); a dedicated "LAUNCH" shipment type; using `V_PRODUCT_LAUNCH_MODEL`'s ramp as a demand multiplier; surfacing a launch-specific UI in the wizard (the existing Shipment Plan already shows the batches).

## Open questions / risks

- **`first_sale_date` reliability.** Prefer the actual first `PURCHASED_UNITS > 0` date; fall back to launch-model / `estimated_start_selling_date`. A returns-only or backfilled early row could mis-date the launch — the ≥3-selling-day floor mitigates noise.
- **Thin early rate is volatile.** A 3–5 day rate swings with a single big day. Accepted by design (the user wants to size off early sales); the lead+1-month horizon cap bounds the over-commit, and the daily re-run self-corrects.
- **60-day boundary cliff.** At day 61 the product flips from launch run-rate to the full Mechanism-A plan in one step. If the model plan diverges from the trailing rate, the suggested batch could jump. Acceptable; revisit with a blend if a graduation looks jarring.
- **`full_lead_days` per product.** The horizon uses `manufacture_day + shipment_days` from DIM_PRODUCT; a missing/zero lead would shorten the cap. Floor `full_lead_days` to a sane minimum if null.
