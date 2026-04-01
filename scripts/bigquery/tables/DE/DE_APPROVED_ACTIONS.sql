-- DE_APPROVED_ACTIONS
-- Stores user-approved bid/keyword actions from the Actions page.
-- Status flow: PENDING → EXPORTED → APPLIED
-- Part of: Sprint 2 — Negate Actions & Actions Page
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_APPROVED_ACTIONS` (
  id STRING NOT NULL,                    -- UUID
  approved_at TIMESTAMP NOT NULL,        -- When user clicked approve

  -- What to do
  action STRING NOT NULL,                -- STOP, INCREASE_BID, REDUCE_BID, PROMOTE_TO_EXACT
  negate_as STRING,                      -- NEGATIVE_EXACT or NULL

  -- Where to do it
  search_term STRING NOT NULL,
  campaign_id STRING,
  campaign_name STRING,
  asin STRING,
  experiment_id STRING,
  strategy_id STRING,

  -- Bid details (for bid changes)
  current_bid FLOAT64,
  suggested_bid FLOAT64,
  bid_change_pct FLOAT64,

  -- Context
  peak_phase STRING,
  occasion STRING,
  reason STRING,
  total_net_roas FLOAT64,
  ads_spend FLOAT64,
  ads_orders INT64,

  -- Status tracking
  status STRING NOT NULL,                     -- PENDING, EXPORTED, APPLIED
  exported_at TIMESTAMP,
  applied_at TIMESTAMP,
  bulksheet_filename STRING,                  -- Reference to exported .xlsx

  -- Audit
  created_by STRING,
  notes STRING
);
