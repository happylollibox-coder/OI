-- V_ADS_COST_CORRECTED — correct per-unit ad COGS from the PURCHASED product, not the advertised one.
--
-- WHY: FACT_AMAZON_ADS.GROSS_PROFIT charges the ADVERTISED ASIN's cost (via a broken
-- most_advertised_asin_purchased field). But ~80-85% of ad-attributed units are a DIFFERENT ASIN than
-- advertised (a box ad drives a cheaper LolliBall sale). Charging the $29.69 box cost against a $13.99
-- ball sale fabricates a −$15.70 loss where the truth is +$4.25. This view rebuilds the per-unit cost
-- from V_SRC_AmazonAds_purchased_product, which carries the TRUE purchased_asin at (campaign, ad_group,
-- keyword, date) grain — the same grain the launch controller / coacher aggregate to.
--
-- OUTPUT: one row per (date, campaign_id, ad_group_id, keyword_id) with correct_cost_per_unit =
-- units-weighted mean cost of what was actually PURCHASED. Drop-in replacement for FACT's
-- TOTAL_COST_PER_UNIT: corrected GROSS_PROFIT = Ads_sales − correct_cost_per_unit × Ads_units.
-- Rows with no purchased-cost on file are flagged (purch_units_no_cost) and excluded from the mean.
-- Grain matches DIM_COSTS_HISTORY date-effective ranges (deduped like SP_FACT_AMAZON_ADS).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_COST_CORRECTED` AS
WITH cost AS (
  SELECT asin, start_date, end_date, TOTAL_COST_PER_UNIT FROM (
    SELECT asin, start_date, end_date, TOTAL_COST_PER_UNIT,
      ROW_NUMBER() OVER (PARTITION BY marketplace_id, asin, start_date, COALESCE(end_date, DATE '9999-12-31')
        ORDER BY COALESCE(sku,'')) AS rn
    FROM `onyga-482313.OI.DIM_COSTS_HISTORY` WHERE marketplace_id = 'ATVPDKIKX0DER'
  ) WHERE rn = 1
),
pp AS (
  SELECT date,
    CAST(campaign_id AS STRING)  AS campaign_id,
    CAST(ad_group_id AS STRING)  AS ad_group_id,
    CAST(keyword_id  AS STRING)  AS keyword_id,
    purchased_asin, advertised_asin, units, sales
  FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product`
  WHERE units > 0 AND keyword_id IS NOT NULL
),
j AS (
  SELECT pp.*, c.TOTAL_COST_PER_UNIT AS purch_cpu
  FROM pp
  LEFT JOIN cost c ON c.asin = pp.purchased_asin
    AND pp.date >= c.start_date AND (c.end_date IS NULL OR pp.date <= c.end_date)
)
SELECT
  date, campaign_id, ad_group_id, keyword_id,
  SUM(units) AS purchased_units,
  ROUND(SUM(sales), 4) AS purchased_sales,
  -- units-weighted mean cost of what was actually purchased (over units that HAVE a cost on file)
  ROUND(SAFE_DIVIDE(SUM(IF(purch_cpu IS NULL, 0, purch_cpu * units)),
                    NULLIF(SUM(IF(purch_cpu IS NULL, 0, units)), 0)), 4) AS correct_cost_per_unit,
  SUM(IF(purch_cpu IS NULL, units, 0)) AS purch_units_no_cost,
  LOGICAL_OR(purchased_asin != advertised_asin) AS any_divergent,
  ANY_VALUE(advertised_asin) AS advertised_asin,
  -- most-purchased ASIN for display/trace
  ARRAY_AGG(purchased_asin ORDER BY units DESC LIMIT 1)[OFFSET(0)] AS top_purchased_asin
FROM j
GROUP BY 1, 2, 3, 4;
