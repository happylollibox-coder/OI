-- =============================================
-- OI Database Project - V_BRAND_KEYWORD_CLASSIFICATION
-- =============================================
--
-- Purpose: Classify every (search_term, campaign) pair as BRAND or GENERIC
--          and flag template mismatches (brand keyword in non-defense template
--          or generic keyword in defense template).
--
-- Dependencies:
--   V_EXPERIMENT_TERM_RECOMMENDATIONS, DIM_PRODUCT
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_BRAND_KEYWORD_CLASSIFICATION`
AS
WITH

-- Brand term patterns derived from product names + known brand terms
brand_patterns AS (
  SELECT DISTINCT LOWER(product_short_name) as pattern
  FROM `onyga-482313.OI.DIM_PRODUCT`
  WHERE product_short_name IS NOT NULL AND product_short_name != 'Unknown'
),

-- All action rows from the recommendations view
classified AS (
  SELECT
    ar.search_term,
    ar.asin,
    ar.product_short_name,
    ar.campaign_id,
    ar.campaign_name,
    ar.portfolio_name,
    ar.experiment_id,
    ar.strategy_id,
    ar.strategy_name,
    ar.recommendation_type,
    ar.ads_signal,
    ar.ads_spend,
    ar.ads_orders,
    ar.ads_units,
    ar.ads_clicks,
    ar.cpc,
    ar.ads_cvr_pct,
    ar.ads_net_roas,
    ar.margin_per_unit,
    ar.sqp_purchases,
    ar.sqp_clicks,
    ar.sqp_impressions,

    -- Brand keyword detection
    CASE
      WHEN LOWER(ar.search_term) LIKE '%happy lolli%' THEN TRUE
      WHEN LOWER(ar.search_term) LIKE '%happylolli%' THEN TRUE
      WHEN LOWER(ar.search_term) LIKE '%happy lollipop%' THEN TRUE
      WHEN LOWER(ar.search_term) LIKE '%truth or dare%' THEN TRUE
      WHEN LOWER(ar.search_term) LIKE '%lollibox%' THEN TRUE
      WHEN LOWER(ar.search_term) LIKE '%lollime%' THEN TRUE
      WHEN LOWER(ar.search_term) LIKE '%lolli me%' THEN TRUE
      WHEN LOWER(ar.search_term) LIKE '%fresh in beige%' THEN TRUE
      WHEN LOWER(ar.search_term) LIKE '%fresh in pink%' THEN TRUE
      WHEN EXISTS (
        SELECT 1 FROM brand_patterns bp
        WHERE LOWER(ar.search_term) LIKE CONCAT('%', bp.pattern, '%')
      ) THEN TRUE
      ELSE FALSE
    END as is_brand_keyword,

    -- Template type: DEFENSE if strategy is brand defense
    CASE
      WHEN ar.strategy_id IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE') THEN 'DEFENSE'
      ELSE 'NON_DEFENSE'
    END as template_type

  FROM `onyga-482313.OI.V_EXPERIMENT_TERM_RECOMMENDATIONS` ar
)

SELECT
  *,
  CASE WHEN is_brand_keyword THEN 'BRAND' ELSE 'GENERIC' END as keyword_type,

  -- Mismatch detection
  CASE
    WHEN is_brand_keyword AND template_type = 'NON_DEFENSE' THEN TRUE
    WHEN NOT is_brand_keyword AND template_type = 'DEFENSE' THEN TRUE
    ELSE FALSE
  END as is_mismatched,

  -- Recommended action for mismatches
  CASE
    WHEN is_brand_keyword AND template_type = 'NON_DEFENSE' THEN 'REMOVE_FROM_TEMPLATE'
    WHEN NOT is_brand_keyword AND template_type = 'DEFENSE' THEN 'REMOVE_FROM_TEMPLATE'
    ELSE NULL
  END as template_action

FROM classified;
