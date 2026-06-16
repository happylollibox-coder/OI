# Coacher Self-Brand Cross-Sell Recommendations — Design

**Date:** 2026-06-16
**Status:** Approved (design), pending implementation plan
**Owner:** Ori

## Problem / Goal

When a shopper lands on a Happy Lolli product detail page, we want our *own* products to occupy the sponsored slots — both to keep competitors off the page (defense) and to cross-sell within the brand so the shopper "eventually buys something from my brand." Today the coacher has no recommendation for this.

Add a coacher action that proposes **"advertise product B on product A's listing"**, chosen from proven in-brand co-purchase affinity. Approving it queues a product-targeting row for the Do-page bulksheet export, routed into the **PRODUCT_DEFENSE** campaign type.

## Signal & pairing logic

- **Source:** `V_SRC_AmazonAds_purchased_product` — columns `advertised_asin`, `purchased_asin`, `orders/units/sales` with `1d/7d/14d/30d` attribution windows.
- A strong **`advertised_asin = A` → `purchased_asin = B`** pair means *A-shoppers bought B* ⇒ recommend product-targeting **A's listing with an ad for B** (`target_asin = A`, `advertise_asin = B`). The direction falls straight out of the data.

## Engine view: `V_ADS_COACH_CROSSSELL`

- **Grain:** `(target_asin = A, advertise_asin = B)`.
- **Build:** aggregate `V_SRC_AmazonAds_purchased_product` over the **last 30 days**; `cross_orders_30d = SUM(orders)`, `cross_sales_30d = SUM(sales)` per (A→B). Keep a pair when:
  - `A != B`
  - **both ASINs are ours** (inner-join `DIM_PRODUCT` on both `target_asin` and `advertise_asin`)
  - `cross_orders_30d >= th_crosssell_min_orders` (new `DE_COACH_THRESHOLDS` key `CROSS_SELL_MIN_ORDERS`, GLOBAL default **3**)
- **Gating (gaps only):** exclude pairs already covered — drop where a live product-target ad exists (target = A, advertised = B) in recent `FACT_AMAZON_ADS` (product-target rows where `targeting` resolves to `asin="A"` and advertised ASIN = B). Mirrors the PROMOTE_TO_EXACT dedupe-against-live pattern.
- **Output columns:** `target_asin`, `advertise_asin`, product short names + parent_name for both, `cross_orders_30d`, `cross_sales_30d`, and a `confidence` tier by order volume.
- All thresholds/rules live in SQL + `DE_COACH_THRESHOLDS` (standing rule: coacher logic in the engine, not the dashboard).

## Action / card

- New action type **`ADD_CROSS_SELL_TARGET`**, its own card variant (ASIN-pair grain, separate from the search-term DecisionCards).
- Card copy: *"Advertise **{B name}** on **{A name}**'s listing — {cross_orders_30d} shoppers bought {B} after engaging ads for {A} (30d), ${cross_sales_30d}."*
- Approve → queue → Do page (same flow as other coacher actions).

## Do-page bulksheet export

- An approved pair becomes a Sponsored Products **product-targeting** bulksheet row: advertise product **B**, target expression `asin="A"`.
- **Routed into the PRODUCT_DEFENSE campaign type** — reuses the existing Do-page generator and the `PRODUCT_DEFENSE` row of `DIM_STRATEGY_CAMPAIGN_TEMPLATE` for campaign/ad-group/bid/budget defaults (no fabricated values — per the no-auto-fill rule). Dedupe against live campaigns as the generator already does.

## Plumbing

- `V_ADS_COACH_CROSSSELL` (view) → `T_ADS_COACH_CROSSSELL` (add a `CREATE OR REPLACE TABLE ... AS SELECT *` line to `SP_REFRESH_CUBE_TABLES`) → new `AdsCoachCrossSell` Cube schema → `CoachCrossSellRow` type + `useCubeData` mapping → dashboard card.
- New `DE_COACH_THRESHOLDS` row `CROSS_SELL_MIN_ORDERS` = 3 (GLOBAL); reflect in the threshold seed.
- Register `V_ADS_COACH_CROSSSELL` + `T_ADS_COACH_CROSSSELL` in `config.yaml`.
- Update SOP `architecture/ADS_COACH_DECISION_MATRIX.md` (new action + view).

## Notes / non-goals

- Net ROAS is ads-only (no halo); this feature is intentionally an **affinity/halo play**, so the card surfaces co-purchase *evidence* (orders/sales), not a net-ROAS gate.
- Out of scope: choosing bids/budgets beyond the PRODUCT_DEFENSE template defaults; multi-window blending (30d only for v1); reverse-direction pairs beyond the A→B reading.

## Settled decisions

1. Output = coacher action → approve → Do-page bulksheet (not a standalone report).
2. Pairing = curated via co-purchase (`V_SRC_AmazonAds_purchased_product`), direction A→B ⇒ advertise B on A.
3. Bar = `cross_orders_30d >= 3` (tunable), both ours, A≠B, surface all qualifying.
4. Gating = gaps only (dedupe vs live product targets).
5. Campaign structure = **PRODUCT_DEFENSE** type.
