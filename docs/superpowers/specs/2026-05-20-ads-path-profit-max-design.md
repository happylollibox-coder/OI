# Ads Path — 2025-Anchored Profit-Max Spend Allocation

**Date:** 2026-05-20
**Component:** `dashboard-react/src/components/StepAdsPath.tsx` (Plan wizard, Step 3)
**Status:** Design approved, pending implementation plan

## Problem

The Ads Path step exists to **simulate "if I assign more ad spend, what happens?"** and to feed that decision to the Ads Coach (per-month spend/bid targets in `DE_PLAN_ADS_TARGETS`). It is a critical step because the coach executes whatever spend schedule this produces.

The current model is wrong for that purpose:

- The spend→profit curve evaluated **one season's efficiency × 365 days** (defaulted to OFF-season), so it recommended *cutting* spend even though peak windows (Easter, Christmas) run at ~1.8–2.0× net ROAS and are profitable to fund.
- Validated against 2025 actuals: Easter 2026 cut ad spend ~44% vs 2025 and lost ~52% of net profit — each $1 cut lost ~$1.05 of profit. The cut was a mistake the model would *recommend*.
- Accumulated layers (`atK` + `seasonBenchmarks` + demand-index + double-count fixes) make per-month season ROAS inconsistent and hard to reason about.

## Goal

Replace the forecast path in Step 3 with a single, data-grounded model that:
1. Reproduces 2025 by construction (no calibration drift).
2. Auto-allocates spend across the year to **maximize total net profit** — fund profitable peaks, cut loss-making off-season.
3. Emits a per-month spend/CPC/units/ROAS schedule for the coach that ramps into peaks.

## Model

Per month `mo`, anchor to actual 2025 `(spend₂₀₂₅[mo], units₂₀₂₅[mo])` and extrapolate with the season elasticity `e[season]`:

```
units(S) = units₂₀₂₅[mo] × (S / spend₂₀₂₅[mo]) ^ e[season]
profit(S) = units(S) × margin − S
```

Profit-max spend per month (marginal ROAS = 1.0, i.e. `margin · dUnits/dS = 1`):

```
S*[mo] = ( (units₂₀₂₅[mo] · margin · e) / spend₂₀₂₅[mo]^e ) ^ (1 / (1 − e))
```

- At `S = spend₂₀₂₅[mo]` the formula returns exactly `units₂₀₂₅[mo]` — reproduces history.
- Total units (incl. organic halo) scale with spend. Justified empirically: in the 2025→2026 Easter pullback, organic units fell ~36% alongside ad units, i.e. ad spend drives organic discovery — so total units (not ad-only) is the correct response variable.
- `margin = asp − cost_per_unit` (family weighted).
- Season elasticities (derived from same-day demand-controlled campaign data, see prior analysis): **PEAK 0.65, OFF 0.58, BOOST 0.51**.

### Validation (Lollibox 2025, margin $23.81)

| | Spend | Units | Net profit |
|---|---|---|---|
| 2025 actual | $273K | 17,687 | $148K |
| Profit-max plan | $311K | 20,920 | **$187K (+26%)** |

Behavior confirmed: cuts loss-making off-season (May $30K→$4K, −$8K→+$3K), funds profitable peaks (Dec $74K→$157K, Nov $25K→$50K, Easter slight bump). Off-season months with marginal ROAS < 1 at their 2025 spend are scaled down; peak months with marginal ROAS > 1 are scaled up.

### Why ad decisions are family-grain (attribution)

Per-variation ad ROAS is **not** a usable signal — the hero variation's ad spend halos the whole listing. Lollibox 2025: White carried **73%** of family ad spend (35% organic), while Purple and Blue got **5% / 2%** of spend yet sold **~65–67% "organic"** — they ride the brand presence White's ads build. Amazon attributes a White-ad-driven *Purple* purchase to White's campaign, so Purple's "organic" overstates true organic and understates White's reach. The model therefore operates on **family** spend/units/ROAS, where this cross-variation attribution washes out. Do **not** surface or optimize per-variation ad efficiency — "Purple is 10× more efficient than White" is an attribution artifact, not a real signal.

## Data

All inputs come from `actuals2025` (already passed into `PlanWizard` and on to `StepAdsPath`):
- `units₂₀₂₅[mo]` = Σ product units per calendar month.
- `spend₂₀₂₅[mo]` = Σ product `adCost` per calendar month.
- `margin` = `asp − costPerUnit` (already available as props).

**No new BigQuery wiring.** Season classification reuses the existing `getSeasonType(mo, yr)` + `DIM_US_HOLIDAYS` windows.

## UX — "assign more spend"

- The spend→profit curve's x-axis becomes **total annual ad spend**; each plotted level is optimally allocated across months (highest marginal-ROAS months funded first). y = total net profit. The **profit-max allocation is the peak** of the curve.
- The user can dial total spend up or down from the profit-max point and see the profit/volume trade-off. The selected point is the plan.
- Default selection = the profit-max plan.

## Coach output

The selected per-month plan produces `DE_PLAN_ADS_TARGETS` rows (per month, per channel where applicable):
- `daily_spend_target` = `S*[mo] / days[mo]` (or the user-selected level's per-month allocation).
- `cpc_target`, `predicted_cvr` = season-specific (operational bid guidance).
- `predicted_units`, `predicted_net_profit`, `predicted_roas` = from the plan at that month.

This is the season-ramped schedule that funds Easter/Christmas — the fix for the operational under-spend.

## Guardrails

- **Extrapolation cap:** clamp each month's `S*` to ≤ 3× its 2025 spend. The elasticity is fit near observed spend; the model notes >5× is unreliable. (Lollibox Dec lands at 2.1×.)
- **Supply check:** the plan's units must be orderable. Surface a flag if a month/family's profit-max units materially exceed what the Order step can stock; the order remains the inventory constraint.
- **Order split by per-product gap, not by family-gap × demand-share or ad spend:** each variation orders `max(0, itsDemandShare×forecast − its OWN stock)`, carton-rounded. Splitting the *family* gap by demand share ignores uneven per-variation stock — a colour overstocked on its own demand (e.g. Pink: stock 3,002 vs forecast 2,819) would still be reordered, while a short colour (White) gets under-ordered. Per-product gap fixes this: Pink → 0, White → its full gap. Never split by ad-spend share (hero variations carry most budget while organic-fed colours sell on the halo). `allocateOrder` takes `(variations, target, forecastTotal, friendly)` and weights by gap; `target` (editable) scales the gaps, default = Σ per-product gaps.
- **Manual override:** the user can always cap total spend below profit-max.
- **Missing-anchor fallback:** if a month has no 2025 spend or units (e.g. a new product/family), fall back to the `runSim` demand forecast for that month (the same fallback retained in Scope) rather than dividing by zero.

## Scope

**Replaces** (forecast path in `StepAdsPath`): the per-`k` `atK` curve, the `seasonBenchmarks × seasonView × 365` annual projection, and the demand-index/season-CVR double-count handling for the spend simulation.

**Keeps unchanged:** Step 2 (Brand/Non-brand demand split), the Order step's carton/100 rounding and product-keyed overrides, and `runSim` as the fallback when no 2025 anchor exists. (The Order step's *allocation* changes from family-gap × demand-share to per-product gap — see Guardrails.)

**Out of scope:** changing the coach's own bidding logic; per-week (vs per-month) granularity; modeling a hard demand ceiling beyond the 3× extrapolation cap.

## Season CPC ceilings (bucket-aware, baked v1)

2025 ads, ROAS by season × CPC bucket (account-wide), shows the profitable-CPC ceiling is sharply season-dependent:

| CPC | PEAK | BOOST | OFF |
|---|---|---|---|
| <$.40 | 1.46× | 1.14× | 0.91× ✗ |
| $.40–.60 | 1.48× | 1.06× | 0.85× ✗ |
| $.60–.80 | 1.49× | 0.77× ✗ | 1.00× |
| $.80–1.0 | 1.38× | 0.94× ✗ | 0.86× ✗ |
| $1.0+ | 1.14–1.16× | 0.43× ✗ | 0.90× ✗ |

So PEAK pays through ~$1.50 CPC, BOOST to ~$0.60, OFF barely pays at any CPC.

**v1 (implemented):** bake per-season max-profitable-CPC constants — `SEASON_MAX_CPC = { PEAK: 1.50, BOOST: 0.60, OFF: 0.45 }` in `StepAdsPath` (derived offline like the elasticity exponents). Used two ways:
1. **Step 3 UI** — a "Profitable CPC ceiling" line (`PEAK ≤$1.50 · BOOST ≤$0.60 · OFF ≤$0.45 — bid above and clicks lose money`).
2. **Coach target** — each month's `AdsTarget` carries `max_cpc = SEASON_MAX_CPC[season]` as a per-season bid cap.

The per-month *spend level* already reflects season profitability via the elasticity + 2025 anchor (off-season is cut); the CPC ceiling is the complementary **bid-level** guard the spend model can't express.

**Follow-up (not v1):** persist `max_cpc` to `DE_PLAN_ADS_TARGETS` (needs a backend/DE column) so the coach actually consumes the cap; and the "live CPC-bucket curves" upgrade (per-family × season × bucket Cube measure) for per-family ceilings + true marginal per-bucket trimming.

## Open questions / risks

- The elasticity is pooled across families; per-family elasticities are not estimated. Acceptable for v1 (exponent is more stable than levels), revisit if a family looks off.
- Profit-max can recommend large peak budgets (Dec 2.1×); the 3× cap + supply check + manual override bound this, but the user should sanity-check peak budgets against cash/inventory.
- **Halo dependency:** variation organic sales depend on the hero's ad spend. Cutting the hero's budget can drop other variations' organic sales (seen in the Easter-2026 cut: organic −36% alongside ads). Family-ROAS captures the net, but per-variation spend is **not** independently optimizable — the model must keep ad spend at family grain and never "rebalance" budget toward a variation that merely looks efficient.
