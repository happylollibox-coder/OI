-- DE_BUDGET_CONFIG — knobs for the Weekly Run budget waterfall + daily optimizer.
-- Keyed like DE_COACH_THRESHOLDS so Ori can edit a single value without a code deploy.
-- Idempotent: re-running this file recreates the table (if absent) and re-seeds the defaults.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_BUDGET_CONFIG` (
  config_key   STRING NOT NULL,
  config_value FLOAT64,
  note         STRING,
  updated_at   TIMESTAMP,
  updated_by   STRING
);

DELETE FROM `onyga-482313.OI.DE_BUDGET_CONFIG` WHERE updated_by = 'plan_seed';
INSERT INTO `onyga-482313.OI.DE_BUDGET_CONFIG` (config_key, config_value, note, updated_at, updated_by) VALUES
  ('total_daily_budget',         700, 'total daily ad spend cap',                       CURRENT_TIMESTAMP(), 'plan_seed'),
  ('family_floor_daily',          10, 'per-family daily floor',                         CURRENT_TIMESTAMP(), 'plan_seed'),
  ('campaign_launch_floor_daily', 10, 'per-campaign floor / launch budget',             CURRENT_TIMESTAMP(), 'plan_seed'),
  ('margin_roas_threshold',      0.8, 'organic-halo breakeven net ROAS',                CURRENT_TIMESTAMP(), 'plan_seed'),
  ('boost_roas_threshold',       2.5, 'net ROAS above which budget +30%',               CURRENT_TIMESTAMP(), 'plan_seed'),
  ('close_roas_threshold',       0.6, 'net ROAS below which a floor campaign closes',   CURRENT_TIMESTAMP(), 'plan_seed'),
  ('floor_probation_days',        30, 'days on floor before graduate/close',            CURRENT_TIMESTAMP(), 'plan_seed'),
  ('starved_clicks_per_day',       3, 'below this many clicks/day = starved',           CURRENT_TIMESTAMP(), 'plan_seed'),
  ('budget_increase_pct',       0.10, 'daily +10% for winners',                         CURRENT_TIMESTAMP(), 'plan_seed'),
  ('boost_increase_pct',        0.30, 'daily +30% for strong winners',                  CURRENT_TIMESTAMP(), 'plan_seed'),
  ('bid_cut_pct',               0.10, 'worst-keyword bid cut',                          CURRENT_TIMESTAMP(), 'plan_seed'),
  ('out_of_budget_util',        0.90, 'yesterday spend / budget ratio = out of budget', CURRENT_TIMESTAMP(), 'plan_seed');
