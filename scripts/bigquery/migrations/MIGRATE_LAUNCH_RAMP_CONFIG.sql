-- MIGRATE_LAUNCH_RAMP_CONFIG — knobs for V_CAMPAIGN_LAUNCH_RAMP (architecture/CAMPAIGN_LAUNCH_RAMP.md).
-- The ramp gets its OWN keys rather than reusing starved_clicks_per_day / budget_increase_pct, which
-- happen to hold the same values today but belong to the daily optimizer — retuning one must not
-- silently move the other. campaign_launch_floor_daily ($10) IS shared: it is the same launch budget.
-- Idempotent: re-running replaces the seeded rows.
DELETE FROM `onyga-482313.OI.DE_BUDGET_CONFIG` WHERE updated_by = 'launch_ramp_seed';
INSERT INTO `onyga-482313.OI.DE_BUDGET_CONFIG` (config_key, config_value, note, updated_at, updated_by) VALUES
  ('launch_ramp_days',         20,   'days a new campaign stays on the launch ramp before the coacher takes over', CURRENT_TIMESTAMP(), 'launch_ramp_seed'),
  ('launch_start_bid',         1.00, 'flat starting bid for every target on a ramping campaign',                   CURRENT_TIMESTAMP(), 'launch_ramp_seed'),
  ('launch_bid_cut_pct',       0.07, 'bid step-down per qualifying day (maxed budget + target over click trigger)', CURRENT_TIMESTAMP(), 'launch_ramp_seed'),
  ('launch_click_trigger',     3,    'a target cuts its bid on a day it took MORE than this many clicks',          CURRENT_TIMESTAMP(), 'launch_ramp_seed'),
  ('launch_budget_raise_pct',  0.10, 'budget step-up per qualifying day (maxed budget + trailing ROAS over bar)',  CURRENT_TIMESTAMP(), 'launch_ramp_seed'),
  ('launch_raise_roas',        1.5,  'trailing net ROAS above which a maxed ramping campaign raises budget',       CURRENT_TIMESTAMP(), 'launch_ramp_seed'),
  ('launch_raise_roas_days',   3,    'trailing window (days) for the budget-raise ROAS test',                      CURRENT_TIMESTAMP(), 'launch_ramp_seed');
