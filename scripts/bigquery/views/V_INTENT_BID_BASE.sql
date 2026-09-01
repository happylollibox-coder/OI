-- =============================================
-- V_INTENT_BID_BASE
-- The base bid we are willing to pay for a click, per (product x intent x month).
-- Grain: product_short_name x intent_key x month_of_year (1-12).
--
--   base_bid = cvr_hat x gp_per_order x INTENT_BID_PROFIT_SHARE
--
-- Read it as: a click on this intent, for this product, in this month, is worth
-- cvr_hat x gp_per_order in expected gross margin. We pay a share of that and bank the rest.
-- At the default share of 0.70 we keep 30% of every click's expected margin.
--
-- WHY THIS IS NOT THE SAME AS A ROAS RULE
-- The existing profit gates judge an intent on its blended, year-round return. LolliME
-- back-to-school reads 1.12 ROAS blended and was dropped — but that is 4.20 in season and
-- 1.12 out of it, and the blend hides both. A bid that is a function of the month says
-- "pay $0.55 in August, $0.26 in July" instead of "this intent is dead".
--
-- ADVISORY ONLY. Nothing here writes to a campaign. Wiring into V_ADS_COACH is Phase 2.
--
-- action:
--   RUN         base_bid >= floor and >= the CPC actually being paid -> room to bid
--   RUN_TIGHTEN base_bid >= floor but below the CPC being paid -> overpaying now
--   OFF         base_bid < floor -> not worth placing this month
--
-- gp_per_order COMES FROM THE HOUSE, NOT FROM HERE (2026-09-01, plan Task 10).
-- This view used to compute its own gp_per_order over a flat trailing 365 days. That produced a
-- clicks-weighted $19.31 on the view and $19.96 in the materialised T_ copy, against the house's
-- recency-weighted $13.39 -- 44-49% high. Because value_per_click = cvr_hat x gp_per_order, the
-- error MULTIPLIED every bid the catalog produced, and it ran opposite to a separate CVR
-- under-estimate, partially masking it. V_KEYWORD_RATES exists precisely so "the Catalog and the
-- engine cannot price against different money", so gp_per_order is now READ from it.
--
-- THE GRAIN IT IS READ AT, and why it is not the account scalar the plan sketched. A single
-- account-wide number would throw away variation the house has already measured as real:
-- gp_per_order is a family property (eta-squared 0.794), and the products here span $10.85
-- (Truth Or Dare) to $19.83 (Pink Lollibox) under the house definition. V_KEYWORD_RATES is
-- per campaign x keyword; campaign resolves to a product through the same
-- ASIN_BY_CAMPAIGN_NAME -> DIM_PRODUCT path this view already uses, so the shared figure can be
-- rolled up to PRODUCT. Measured 2026-09-01: every one of its 405 keyword rows maps to a
-- product, covering 9 of the catalog's 10 products. So the ladder is
--
--   HOUSE_PRODUCT -> HOUSE_FAMILY -> HOUSE_ACCOUNT -> LEGACY_FAMILY_365D
--
-- and gp_source names which rung fired, so a fallback is visible rather than silent.
-- Rungs 1 and 2 additionally require INTENT_GP_MIN_ORDERS weighted orders (see that threshold's
-- description for the derivation); a bucket thinner than that drops a rung rather than pricing a
-- whole product off a handful of transactions.
-- LEGACY_FAMILY_365D is the old self-computed family figure, kept ONLY as a last resort for the
-- case where V_KEYWORD_RATES returns nothing at all -- its join to the latest FACT_KEYWORD_STATE
-- snapshot is the kind of thing that can empty -- because a NULL gp_per_order would NULL
-- value_per_click and flip the entire catalog to OFF. It is a different definition of money and
-- it firing is a defect, which is why it is named in gp_source rather than blended in silently.
-- MEASURED 2026-09-01: it fires on 0 of 125,316 rows.
--
-- CAMPAIGN -> PRODUCT IS A DOMINANT-ASIN ASSIGNMENT, not a fact. Measured over the same 104-day
-- frame V_KEYWORD_RATES uses: 144 of 153 campaigns carry exactly one ASIN and the 9 that carry
-- two hold 3,804 of 182,336 clicks (2.1%). Those 9 are assigned to their highest-click ASIN.
--
-- Dependencies: V_INTENT_CVR_CURVE, V_KEYWORD_RATES, FACT_AMAZON_ADS, V_INTENT_RESOLVED,
--               DIM_PRODUCT, DE_COACH_THRESHOLDS
-- SOP: docs/superpowers/specs/2026-07-24-intent-coverage-phase0-design.md
--      docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md section 7
-- Project: onyga-482313 / Dataset: OI
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_INTENT_BID_BASE` AS

WITH params AS (
  SELECT
    MAX(IF(threshold_key = 'INTENT_BID_PROFIT_SHARE', threshold_value, NULL)) AS profit_share,
    MAX(IF(threshold_key = 'INTENT_BID_CEILING',      threshold_value, NULL)) AS bid_ceiling,
    MAX(IF(threshold_key = 'INTENT_BID_FLOOR',        threshold_value, NULL)) AS bid_floor,
    -- Band boundaries (spec 2026-07-25 §3). ALL from threshold rows, none hard-coded.
    MAX(IF(threshold_key = 'PROFITABLE_ROAS',         threshold_value, NULL)) AS roas_run,
    MAX(IF(threshold_key = 'VELOCITY_ROAS',           threshold_value, NULL)) AS roas_velocity,
    MAX(IF(threshold_key = 'INTENT_HOPELESS_ROAS',    threshold_value, NULL)) AS roas_hopeless,
    -- Support gate for the gp_per_order ladder below. Migration 2026-09-01_intent_gp_min_orders.
    MAX(IF(threshold_key = 'INTENT_GP_MIN_ORDERS',    threshold_value, NULL)) AS gp_min_orders
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  -- coach_mode AND product_family ARE PART OF THE KEY, not tags. Thresholds resolve
  -- strategy_id+coach_mode -> GLOBAL+coach_mode -> strategy_id+GUARDIAN -> GLOBAL+GUARDIAN, so a
  -- row written under BLITZ or COOLDOWN, or a family-scoped override, is not what a GUARDIAN read
  -- resolves. Without these two predicates MAX() would silently pick the largest of whatever rows
  -- happened to share the key. All seven rows this view reads are GUARDIAN / product_family NULL
  -- (verified 2026-09-01), so this filter is a no-op today and a guard against tomorrow.
  WHERE strategy_id = 'INTENT' AND coach_mode = 'GUARDIAN' AND product_family IS NULL
),

-- The ads watermark. Same definition V_KEYWORD_RATES uses for its own windows (MAX(date) over
-- FACT_AMAZON_ADS), so the campaign -> product map below is built over the same 104-day frame the
-- shared rates were measured on rather than over a CURRENT_DATE()-anchored one that drifts from it.
wm AS (SELECT MAX(date) AS watermark FROM `onyga-482313.OI.FACT_AMAZON_ADS`),

-- Campaign -> product, dominant ASIN by clicks. V_KEYWORD_RATES publishes campaign_id and a
-- keyword, not a product; this is the bridge that lets the shared margin be read at product grain.
camp_prod AS (
  SELECT cid, product_short_name, parent_name FROM (
    SELECT CAST(a.campaign_id AS STRING) AS cid, p.product_short_name, p.parent_name,
           ROW_NUMBER() OVER (PARTITION BY CAST(a.campaign_id AS STRING)
                              ORDER BY SUM(a.Ads_clicks) DESC, p.product_short_name) AS rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
    JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
    CROSS JOIN wm
    WHERE a.date > DATE_SUB(wm.watermark, INTERVAL 104 DAY)
      AND p.parent_name IS NOT NULL AND p.parent_name != 'UNKNOWN'
    GROUP BY 1, 2, 3
  ) WHERE rn = 1
),

-- THE SHARED DEFINITION OF MONEY, read once and rolled up three ways. Numerators and
-- denominators are summed BEFORE dividing, which is the only correct way to pool a ratio and is
-- also exactly how V_KEYWORD_RATES forms it per keyword — so a rung is the same estimator over a
-- wider bucket, not an average of averages.
house_kw AS (
  SELECT cp.product_short_name, cp.parent_name,
         r.weighted_orders AS wo, r.weighted_gross_profit AS wg
  FROM `onyga-482313.OI.V_KEYWORD_RATES` r
  JOIN camp_prod cp ON cp.cid = r.campaign_id
),
house_product AS (
  SELECT product_short_name, SUM(wo) AS wo,
         SAFE_DIVIDE(SUM(wg), NULLIF(SUM(wo), 0)) AS gp_per_order
  FROM house_kw GROUP BY 1
),
house_family AS (
  SELECT parent_name, SUM(wo) AS wo,
         SAFE_DIVIDE(SUM(wg), NULLIF(SUM(wo), 0)) AS gp_per_order
  FROM house_kw GROUP BY 1
),
house_account AS (
  SELECT SUM(wo) AS wo, SAFE_DIVIDE(SUM(wg), NULLIF(SUM(wo), 0)) AS gp_per_order FROM house_kw
),

-- LEGACY, LAST RESORT ONLY. The old self-computed 365-day figure, retained solely so a total
-- failure of V_KEYWORD_RATES leaves the catalog priced rather than NULL. Reaching it means two
-- definitions of money are live again; gp_source says so out loud.
gp_product AS (
  SELECT p.product_short_name, p.parent_name,
    SAFE_DIVIDE(SUM(a.GROSS_PROFIT), SUM(a.Ads_orders)) AS gp_per_order,
    SUM(a.Ads_orders) AS orders_365d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
  WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
    AND p.parent_name IS NOT NULL AND p.parent_name != 'UNKNOWN'
  GROUP BY 1, 2
),

-- Legacy family fallback, reached only beneath HOUSE_ACCOUNT. See gp_product above.
gp_family AS (
  SELECT parent_name,
    SAFE_DIVIDE(SUM(gp_per_order * orders_365d), SUM(orders_365d)) AS gp_per_order
  FROM gp_product GROUP BY 1
),

-- What we actually pay today for this product x intent x month, for comparison.
actual AS (
  SELECT p.product_short_name, i.intent_key, EXTRACT(MONTH FROM a.date) AS month_of_year,
    SUM(a.Ads_clicks) AS clicks,
    SAFE_DIVIDE(SUM(a.Ads_cost), SUM(a.Ads_clicks)) AS actual_cpc
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN `onyga-482313.OI.V_INTENT_RESOLVED` i ON i.search_term = a.search_term
  JOIN `onyga-482313.OI.DIM_PRODUCT` p             ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
  WHERE i.intent_key IS NOT NULL
  GROUP BY 1, 2, 3
),

priced AS (
  SELECT
    c.parent_name, c.product_short_name, c.intent_key, c.intent_type, c.month_of_year,
    c.base_cvr, c.season_index, c.cvr_hat, c.base_clicks, c.confidence, c.base_self_weight,
    -- THE LADDER. IF(wo >= gate, gp, NULL) rather than a WHERE: a bucket that exists but is too
    -- thin must DROP A RUNG, not vanish. A missing bucket gives wo = NULL and `NULL >= gate` is
    -- NULL, which COALESCE also steps past, so both cases behave the same by construction.
    COALESCE(IF(hp.wo >= pr.gp_min_orders, hp.gp_per_order, NULL),
             IF(hf.wo >= pr.gp_min_orders, hf.gp_per_order, NULL),
             ha.gp_per_order,
             gf.gp_per_order)                  AS gp_per_order,
    -- gp_is_family_fallback KEEPS ITS MEANING, WIDENED: "this row is NOT priced off its own
    -- product's margin". tools/intent_grid/backtest_2025.py reads `WHERE NOT gp_is_family_fallback`
    -- to pull per-product margins and still gets exactly that.
    NOT (hp.wo >= pr.gp_min_orders AND hp.gp_per_order IS NOT NULL) AS gp_is_family_fallback,
    CASE
      WHEN hp.wo >= pr.gp_min_orders AND hp.gp_per_order IS NOT NULL THEN 'HOUSE_PRODUCT'
      WHEN hf.wo >= pr.gp_min_orders AND hf.gp_per_order IS NOT NULL THEN 'HOUSE_FAMILY'
      WHEN ha.gp_per_order IS NOT NULL                               THEN 'HOUSE_ACCOUNT'
      WHEN gf.gp_per_order IS NOT NULL                               THEN 'LEGACY_FAMILY_365D'
      ELSE 'NONE'
    END                                        AS gp_source,
    c.cvr_hat * COALESCE(IF(hp.wo >= pr.gp_min_orders, hp.gp_per_order, NULL),
                         IF(hf.wo >= pr.gp_min_orders, hf.gp_per_order, NULL),
                         ha.gp_per_order,
                         gf.gp_per_order)      AS value_per_click,
    ac.actual_cpc, ac.clicks AS month_clicks,
    pr.profit_share, pr.bid_ceiling, pr.bid_floor,
    pr.roas_run, pr.roas_velocity, pr.roas_hopeless
  FROM `onyga-482313.OI.V_INTENT_CVR_CURVE` c
  LEFT JOIN house_product hp ON hp.product_short_name = c.product_short_name
  LEFT JOIN house_family  hf ON hf.parent_name        = c.parent_name
  LEFT JOIN gp_family     gf ON gf.parent_name        = c.parent_name
  LEFT JOIN actual        ac ON ac.product_short_name = c.product_short_name
                            AND ac.intent_key         = c.intent_key
                            AND ac.month_of_year      = c.month_of_year
  CROSS JOIN params pr
  CROSS JOIN house_account ha
)

SELECT
  parent_name, product_short_name, intent_key, intent_type, month_of_year,
  ROUND(base_cvr, 5)        AS base_cvr,
  season_index,
  ROUND(cvr_hat, 5)         AS cvr_hat,
  ROUND(gp_per_order, 2)    AS gp_per_order,
  gp_is_family_fallback,
  gp_source,
  ROUND(value_per_click, 3) AS value_per_click,
  -- max_bid is the BREAKEVEN CEILING — pay more than this and the click loses money.
  -- target_bid is the bid that also hits the margin goal. They are different questions and
  -- collapsing them was the first version's bug: it read "market is above my target" as
  -- "tighten" even when the market was also above breakeven (a money-loser), and read
  -- "target computed fine" as "run" even when the market cleared above the target and we
  -- would never win the auction.
  ROUND(LEAST(GREATEST(value_per_click, 0), bid_ceiling), 2)                AS max_bid,
  ROUND(LEAST(GREATEST(value_per_click * profit_share, 0), bid_ceiling), 2) AS target_bid,
  -- Band max CPCs (spec §3): willingness to pay per band.
  ROUND(LEAST(GREATEST(SAFE_DIVIDE(value_per_click, roas_run), 0), bid_ceiling), 2)      AS max_cpc_run,
  ROUND(LEAST(GREATEST(SAFE_DIVIDE(value_per_click, roas_velocity), 0), bid_ceiling), 2) AS max_cpc_velocity,
  ROUND(SAFE_DIVIDE(value_per_click, actual_cpc), 2) AS expected_net_roas_at_market,
  ROUND(actual_cpc, 2)      AS actual_cpc,
  month_clicks,
  base_clicks,
  base_self_weight,
  confidence,
  -- BAND assignment (spec 2026-07-25 §3, ratified four bands; boundaries all threshold
  -- rows). Hysteresis and the velocity-pace condition are STATEFUL — they live in the plan
  -- generator and checkpoint; this view reports the raw band only.
  CASE
    -- Not worth placing at any price.
    WHEN value_per_click < bid_floor THEN 'OFF'
    -- Never run, no market read: worth probing at target.
    WHEN actual_cpc IS NULL THEN 'RUN'
    WHEN SAFE_DIVIDE(value_per_click, actual_cpc) >= roas_run      THEN 'RUN'
    WHEN SAFE_DIVIDE(value_per_click, actual_cpc) >= roas_velocity THEN 'VELOCITY'
    WHEN SAFE_DIVIDE(value_per_click, actual_cpc) >= roas_hopeless THEN 'MARGINAL'
    ELSE 'OFF'
  END AS action,
  actual_cpc IS NULL AS no_market_read
FROM priced;
