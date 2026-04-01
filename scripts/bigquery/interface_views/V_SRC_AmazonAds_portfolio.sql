-- =============================================
-- OI Database Project - V_SRC_AmazonAds_portfolio
-- =============================================
--
-- @dialect: bigquery
-- Language: BigQuery SQL
--
-- Purpose: Portfolio history with temporal versioning
-- Business Logic: Tracks portfolio changes over time with validity periods
--
-- KEY CONCEPTS:
-- - OI_start_date: When this version of the portfolio became active
-- - OI_end_date: When this version was replaced (or current time if active)
-- - Uses window functions to create temporal validity ranges
--
-- Dependencies:
--   - fivetran-hl.amazon_ads.portfolio_history
--
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2026-02-05
--
-- =============================================

DROP VIEW IF EXISTS `onyga-482313.OI.V_SRC_AmazonAds_portfolio`;
CREATE VIEW `onyga-482313.OI.V_SRC_AmazonAds_portfolio` AS

-- ============================================================================
-- PORTFOLIO HISTORY WITH TEMPORAL VERSIONING
-- ============================================================================
WITH portfolio_versions AS (
  SELECT
    -- Core portfolio identifiers
    CAST(p.id AS STRING) AS portfolio_id,
    p.last_updated_date,
    p.name AS portfolio_name,
    p.profile_id,
    p.in_budget,
    p.state,
    p.serving_status,
    p.creation_date,
    p.budget_amount,
    p.budget_currency_code,
    p.budget_policy,
    p.budget_start_date,
    p.budget_end_date,

    -- Temporal versioning logic
    -- OI_start_date: Portfolio version start date
    -- OI_end_date: Portfolio version end date
    CASE
      WHEN p.last_updated_date = MIN(p.last_updated_date) OVER (
        PARTITION BY p.id
        ORDER BY p.last_updated_date
      )
      THEN TIMESTAMP '1900-01-01 00:00:00'  -- Default for first version
      ELSE p.last_updated_date
    END AS OI_start_date,

    -- End date is either next version's start date or current time
    TIMESTAMP_SUB(
      COALESCE(
        LEAD(p.last_updated_date) OVER (
          PARTITION BY p.id
          ORDER BY p.last_updated_date
        ),
        TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
      ),
      INTERVAL 1 SECOND
    ) AS OI_end_date

  FROM `fivetran-hl`.amazon_ads.portfolio_history p
)

-- ============================================================================
-- FINAL SELECT
-- ============================================================================
SELECT * FROM portfolio_versions;

