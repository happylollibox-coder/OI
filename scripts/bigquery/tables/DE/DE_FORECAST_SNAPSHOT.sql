-- =============================================
-- DE_FORECAST_SNAPSHOT
-- =============================================
-- Purpose: Immutable monthly forecast snapshot, taken at plan approval time.
--          Used by SP_GENERATE_SALES_DEVIATION_ALERTS to compare actual sales
--          against the forecast that was active when the plan was approved.
--
-- Written once per plan approval. Never updated after creation.
-- Only future months (from approval date forward) are stored.
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_FORECAST_SNAPSHOT` (
  plan_id           STRING    NOT NULL,   -- FK → DE_PLAN_STRATEGY.plan_id
  product           STRING    NOT NULL,   -- Product short name (from V_FORECAST_DEMAND)
  asin              STRING,               -- Product ASIN (from DIM_PRODUCT)
  forecast_year     INT64     NOT NULL,   -- e.g. 2026
  forecast_month    INT64     NOT NULL,   -- 1-12
  forecast_units    INT64     NOT NULL,   -- Frozen forecast units for this month
  peak_days         INT64,                -- Days with peak demand in this month (0 = off-peak)
  approved_at       TIMESTAMP NOT NULL,   -- When this snapshot was taken
);
