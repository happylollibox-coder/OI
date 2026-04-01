-- =============================================
-- OI Database Project - DIM_EXPERIMENT_CHANGE_LOG Table
-- =============================================
--
-- Purpose: Track setting changes made to experiments over time.
--          Enables splitting FACT_EXPERIMENT_DAILY into periods
--          (before change vs after change) for variation comparison.
--
-- Method: Manual INSERT (user logs changes when making them in Seller Central)
--         Future: auto-detection via SP_DETECT_SETTING_CHANGES
--
-- Downstream: V_EXPERIMENT_VARIATION_COMPARISON (splits performance by period)
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DIM_EXPERIMENT_CHANGE_LOG` (
  -- Primary Key
  change_id STRING NOT NULL,

  -- Which experiment changed
  experiment_id STRING NOT NULL,  -- FK to DIM_EXPERIMENT

  -- When and what changed
  change_date DATE NOT NULL,       -- Date the change took effect in Seller Central
  change_type STRING NOT NULL,     -- ADD_CAMPAIGN, REMOVE_CAMPAIGN, BID_CHANGE, BUDGET_CHANGE, TOS_CHANGE, PP_CHANGE, KEYWORD_CHANGE, BIDDING_STRATEGY_CHANGE, STATUS_CHANGE, OTHER

  -- Change detail
  campaign_id STRING,              -- Which campaign was affected (NULL if experiment-level change)
  field_changed STRING,            -- e.g. "top_of_search_pct", "daily_budget", "avg_bid"
  old_value STRING,                -- Previous value (as string)
  new_value STRING,                -- New value (as string)

  -- Context
  reason STRING,                   -- Why this change was made (manual, always helpful)
  source STRING DEFAULT 'MANUAL',  -- MANUAL or AUTO (for future auto-detection)

  -- Metadata
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),

  PRIMARY KEY (change_id) NOT ENFORCED
)
OPTIONS (
  description = "Tracks setting changes to experiments. Enables period-based variation comparison. Manual INSERT now; AUTO detection planned for future."
);
