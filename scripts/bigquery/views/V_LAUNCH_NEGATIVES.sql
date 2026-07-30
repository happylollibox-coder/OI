-- =============================================
-- OI Database Project - V_LAUNCH_NEGATIVES
-- =============================================
--
-- Purpose: The negative phrases a NEW campaign must launch with, resolved per
--          (strategy_id, parent_name). Consumed by the bulksheet generator in
--          DoPage.tsx, which emits one Campaign Negative Keyword row per phrase
--          alongside the Campaign / Ad Group / Keyword / Product Ad rows.
--
-- Grain is (strategy_id, parent_name) — NOT campaign_id — because at bulksheet
-- generation time the campaign does not exist yet and has no id. The frontend
-- knows the strategy it is scaffolding and the product's family; that's the key.
--
-- Defense exclusion is ENFORCED HERE, not in the frontend: BRAND_DEFENSE and
-- PRODUCT_DEFENSE simply produce no rows. The _ALL bucket negates brand terms
-- (lolli / lollibox / lollime), which is exactly the traffic a defense campaign
-- exists to buy — pushing them in would negate its whole purpose. Previously this
-- rule lived only as prose in DE_PRODUCT_PHRASE_NEGATIVES.sql and
-- V_ADS_NEGATIVE_CONFLICTS.sql, which is why the frontend never applied it.
--
-- Usage (bulksheet generation):
--   SELECT phrase, match_type
--   FROM V_LAUNCH_NEGATIVES
--   WHERE strategy_id IN ('PHRASE','EXACT') AND parent_name = 'Lollibox'
--
-- Dependencies: V_PRODUCT_PHRASE_NEGATIVES, DIM_STRATEGY_TEMPLATE
-- Materialized to: T_LAUNCH_NEGATIVES (via SP_REFRESH_CUBE_TABLES)
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_LAUNCH_NEGATIVES`
AS
WITH

-- Strategies that are allowed to carry the curated negative list.
-- Defense strategies are excluded — see header.
eligible_strategies AS (
  SELECT strategy_id
  FROM `onyga-482313.OI.DIM_STRATEGY_TEMPLATE`
  WHERE strategy_id NOT IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE')
)

SELECT
  s.strategy_id,
  n.effective_parent_name AS parent_name,
  n.phrase,
  n.match_type,
  -- Amazon bulksheet tokens, so the frontend never maps these by hand
  CASE n.match_type
    WHEN 'Negative Phrase' THEN 'NEGATIVE_PHRASE'
    WHEN 'Negative Exact'  THEN 'NEGATIVE_EXACT'
  END AS bulksheet_match_type,
  n.source,
  n.origin_level
FROM `onyga-482313.OI.V_PRODUCT_PHRASE_NEGATIVES` n
CROSS JOIN eligible_strategies s;
