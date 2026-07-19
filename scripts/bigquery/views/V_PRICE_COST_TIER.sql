-- V_PRICE_COST_TIER — empirical per-unit sale-price → true-COGS lookup.
--
-- WHY: FACT_AMAZON_ADS charges the ADVERTISED ASIN's cost, but ~80% of ad-attributed units are a DIFFERENT
-- (usually cheaper) product. The purchased-product report knows the true ASIN but under-covers (~31% of
-- FACT units have no row). The sale PRICE, however, is on every row and cleanly identifies the product's
-- price tier / family (validated: each family has a distinct price; the one collision — $13.99 Bunny vs
-- LolliBall — is cost-harmless since both cost ~$9.5–10.3).
--
-- This view learns the map from ground truth: for each observed unit price, the units-weighted TRUE cost of
-- what was actually purchased at that price (from V_SRC_AmazonAds_purchased_product joined to the current
-- landed cost). tier_cost is the drop-in COGS for any FACT row at that price; cost_spread flags tiers where
-- imputation is less certain. Prices with < 3 units are dropped (noise) → caller falls back to advertised cost.
-- Uses current cost (end_date IS NULL); costs are stable enough for a price→tier map. Grain: one row per unit_price.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PRICE_COST_TIER` AS
WITH cost AS (
  SELECT asin, TOTAL_COST_PER_UNIT AS cost FROM (
    SELECT asin, TOTAL_COST_PER_UNIT,
      ROW_NUMBER() OVER (PARTITION BY marketplace_id, asin ORDER BY start_date DESC) AS rn
    FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
    WHERE marketplace_id = 'ATVPDKIKX0DER' AND end_date IS NULL
  ) WHERE rn = 1
),
pp AS (
  SELECT ROUND(SAFE_DIVIDE(sales, units), 2) AS unit_price, purchased_asin, units
  FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`
  WHERE units > 0 AND sales > 0
    AND date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 180 DAY)
)
SELECT
  pp.unit_price,
  SUM(pp.units) AS units,
  ROUND(SAFE_DIVIDE(SUM(c.cost * pp.units), SUM(pp.units)), 2) AS tier_cost,          -- units-weighted TRUE cost at this price
  ROUND(MIN(c.cost), 2) AS min_cost, ROUND(MAX(c.cost), 2) AS max_cost,
  ROUND(MAX(c.cost) - MIN(c.cost), 2) AS cost_spread,                                  -- 0 = single cost, higher = more ambiguous
  COUNT(DISTINCT pp.purchased_asin) AS n_asins,
  STRING_AGG(DISTINCT d.parent_name ORDER BY d.parent_name) AS families
FROM pp
JOIN cost c ON c.asin = pp.purchased_asin
LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` d ON d.asin = pp.purchased_asin
GROUP BY 1
HAVING SUM(pp.units) >= 3;
