-- Physical materialization of V_FORECAST_DEMAND to avoid query planner complexity explosions in V_PLAN_FORECAST.

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_FORECAST_DEMAND` (
  product STRING,
  family STRING,
  forecast_year INT64,
  forecast_month INT64,
  family_forecast_units INT64,
  product_share FLOAT64,
  forecast_units FLOAT64,
  is_new_product BOOL,
  is_draft BOOL,
  sqrt_lift FLOAT64,
  peak_days INT64,
  offseason_days INT64,
  peak_holidays STRING,
  forecast_phase STRING,
  model_product STRING
);
