-- =============================================
-- V_COVERAGE_KEYWORD_MONTHLY
-- Per (keyword x month) 12-month trend for the coverage cockpit's keyword panel drill.
-- Grain: one row per (parent_name, match_type, keyword_text, month) over the last 12 months.
-- Source: V_KEYWORD_DAILY (true keyword report).
--
-- keyword_key = CONCAT(match_type,'|',LOWER(keyword_text)) — the stable join key the
-- frontend uses to attach a keyword's monthly rows.
-- units = SUM(units_14d): units_14d is a 14d-ROLLING attribution, so a monthly SUM is
-- DIRECTIONAL only (overlapping windows), never an exact unit count.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_COVERAGE_KEYWORD_MONTHLY` AS
WITH base AS (
  SELECT
    parent_name,
    match_type,
    LOWER(keyword_text) AS keyword_text,
    DATE_TRUNC(date, MONTH) AS month,
    clicks, cost, units_14d, impressions
  FROM `onyga-482313.OI.V_KEYWORD_DAILY`
  WHERE date >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 11 MONTH), MONTH)
    AND parent_name IS NOT NULL
    AND keyword_text IS NOT NULL
    AND match_type IS NOT NULL
)
SELECT
  parent_name,
  match_type,
  keyword_text,
  CONCAT(match_type, '|', keyword_text) AS keyword_key,
  month,
  SUM(clicks) AS clicks,
  ROUND(SUM(cost), 2) AS spend,
  CAST(SUM(units_14d) AS INT64) AS units,
  SUM(impressions) AS impressions
FROM base
GROUP BY parent_name, match_type, keyword_text, month;
