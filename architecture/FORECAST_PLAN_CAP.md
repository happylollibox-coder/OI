# SOP — Plan cap vs supply demand in V_PLAN_FORECAST

**Status:** active · **Added:** 2026-08-13

## The rule

`V_PLAN_FORECAST` emits **two parallel demand paths**. Pick by what the number decides:

| Path | Columns | Basis | Read it for |
|---|---|---|---|
| **Plan** | `demand_30d/45d/60d/90d`, `daily_rate`, `proportional_daily_demand`, `sellable_doc_walk`, `fba_doc_walk` | `adjusted_units` — forecast **after** the `yearly_plan` cap | Financial planning, plan-vs-actual, anything labelled "planned" |
| **Supply** | `supply_demand_30d/45d/60d/90d`, `supply_daily_rate`, `supply_proportional_daily_demand`, `supply_sellable_doc_walk`, `supply_fba_doc_walk` | `supply_units` — forecast with **no** plan cap at any phase | AWD targets, days-of-cover, reorder sizing, stock alerts |

**Never size stock off the plan path.** A stale `yearly_plan` suppresses demand on exactly
the products that are selling best.

## Why

`effective_growth` back-solves growth from the plan:

```
growth = (yearly_plan − ytd_sold) / demand_base
```

Every unit sold shrinks the numerator, so **outperforming the plan lowers the forecast**.
On 2026-08-13: Fresh in Purple sold 89 units in 30 days while the capped forecast said 38
(growth 0.35, an 800-unit plan against 1,909 units of real forecast demand). Its AWD target
came out at 38/55 units and its FBA days-of-cover read 102 instead of 60.

Two prior defects, both fixed 2026-08-13:

1. **Zero-clamp.** `GREATEST(yearly_plan − ytd_sold, 0)` drove growth to **0** once a
   product outsold its plan, zeroing the rest of the year. Birthday Bunny: 107 sold against
   a 98 plan → forecast 0 while still selling 31/month → infinite DOC, no reorder ever.
   Beating plan now falls through to the normal growth path instead.
2. **`unconstrained_growth` is not a supply signal.** It deliberately keeps the plan
   back-calc for `PHASE_1`/`PHASE_2`, so it left every Bunny and LolliBall as suppressed as
   the capped path. `supply_growth` (= `growth_json` rate, else 1.0, never the plan
   back-calc) was added for the supply columns.

## Consumers

Everything that decides stock is on the supply path:

- `V_SUPPLY_CHAIN_SUMMARY` — `awd_target_min/max`, `awd_diff_pct`, `daily_velocity`,
  `days_of_coverage`, `fba_days_of_coverage`, `awd_days_of_coverage`
- `V_SHIPMENT_PLAN` — `ship_qty`, `po_qty`, and the `daily_rate > 0` gates
- `SP_GENERATE_ALERTS` — `tmp_data` aliases the supply columns over the plan names, so
  every rule reads uncapped numbers by construction rather than by remembering to
- Inside `V_PLAN_FORECAST` itself, these are supply-only and were switched **in place**
  (no plan twin, because none of them is a plan figure): `days_until_oos`,
  `emergency_priority`, `is_emergency`, `q4_demand`, `pre_q4_demand`,
  `forecasted_sep1_pipeline`, `demand_during_lead`, and the legacy flat-rate
  `fba_doc` / `fba_doc_effective` / `system_doc`

Deliberately still on the plan path: `next_30d_planned` / `next_31_60d_planned` /
`next_61_90d_planned` (they *are* the plan, and pair with `last_30d_planned` for
plan-vs-actual). Side effect: `awd_target_min` no longer duplicates `next_30d_planned`.

## Regression guard

When touching this view, join the rewritten SQL to the live one on `product` and confirm
`demand_30d`, `demand_90d`, `daily_rate`, `sellable_doc_walk` and `fba_doc_walk` are
unchanged. Every change above was verified that way — the plan path must never move as a
side effect of a supply change. Watch for blanket find-and-replace on `dwin.demand_90d`:
it also matches the two plan-path output columns.

## Caveat on the uncapped forecast

`supply_growth` falls back to 1.0, i.e. the raw `family_forecast_units × product_share`
model. For the Bunny and LolliBall families that model implies a 3–5× ramp into Q4 — fine
as a *stock* signal (erring toward cover), but **not** validated as a purchase commitment.
Do not copy `supply_*` numbers into `yearly_plan` overrides without a human check. See also
the open question of whether `growth_json` double-counts YoY growth already embedded in
`V_FORECAST_DEMAND`.
