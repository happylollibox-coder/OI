-- DE_WEEKLY_PLAN — per-cell weekly plan (history-retained). Coacher D.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_WEEKLY_PLAN` (
  week_start          DATE NOT NULL,
  horizon             STRING,         -- CURRENT | FUTURE
  parent_name         STRING NOT NULL,
  season              STRING,         -- PEAK | OFF
  match_type          STRING,
  intent_class        STRING,
  purpose             STRING,         -- SCALE | MAP | PROBE | DEFEND | CUT | HOLD
  objective           STRING,
  success_metric      STRING,         -- NET_PROFIT | CLICKS | TOS_SHARE | SPEND_DOWN | HOLD
  expected_value      FLOAT64,
  target_cpc          FLOAT64,        -- SCALE only (from profile cpc_target)
  planned_spend       FLOAT64,
  spend_mode          STRING,         -- SCALE | CAP
  expected_net_profit FLOAT64,        -- product-level trend projection (repeated on each cell)
  plan_net_profit     FLOAT64,        -- business-plan target (best-effort; may be NULL)
  coach_mode_hint     STRING,         -- GUARDIAN | BLITZ | COOLDOWN
  status              STRING,         -- PROPOSED | ON_PLAN | OFF_PLAN | MET | MISSED
  actual_value        FLOAT64,        -- written back by the review (SP_REVIEW_WEEKLY_PLAN)
  source              STRING,         -- DERIVED | MANUAL
  updated_at          TIMESTAMP,
  updated_by          STRING
);
