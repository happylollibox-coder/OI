-- =============================================
-- OI Database Project - DIM_EXPERIMENT Table
-- =============================================
--
-- Purpose: Experiment definitions for ad-to-organic impact tracking
-- Method: Manual INSERT (user defines experiments)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DIM_EXPERIMENT` (
  -- Primary Key
  experiment_id STRING NOT NULL,

  -- Experiment definition
  experiment_name STRING NOT NULL,
  description STRING,

  -- Date range
  start_date DATE NOT NULL,
  end_date DATE,  -- NULL = still running
  baseline_days INT64 NOT NULL,  -- days before start_date for pre-period comparison (default 28)

  -- Strategy link (FK to DIM_STRATEGY_TEMPLATE, nullable for ad-hoc experiments)
  strategy_id STRING,

  -- Status
  status STRING NOT NULL,  -- PLANNED, ACTIVE, COMPLETED, CANCELLED

  -- Lifecycle stage (experiment roadmap toward becoming a permanent rule)
  lifecycle_stage STRING,  -- HYPOTHESIS, ACTIVE, REVIEW, VALIDATED, GRADUATED, FAILED, PAUSED, INCONCLUSIVE

  -- Graduation metadata (populated when lifecycle_stage = GRADUATED)
  graduation_date DATE,
  graduation_confidence STRING,      -- LOW, MEDIUM, HIGH
  graduation_criteria_met STRING,    -- comma-separated list of passed criteria

  -- Seasonal context of this experiment
  season_context STRING,             -- PEAK, OFF_SEASON, NORMAL, MIXED

  -- Outcome (populated when experiment is completed)
  outcome_score FLOAT64,  -- 0-100 composite score (organic lift + ROAS)
  outcome_tags STRING,  -- comma-separated: "brand,exact,pre-holiday,successful"
  outcome_notes STRING,  -- free text learnings

  -- Metadata
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),

  PRIMARY KEY (experiment_id) NOT ENFORCED
)
OPTIONS (
  description = "Experiment definitions for ad-to-organic impact tracking. Each row defines an experiment with strategy template, start/end dates, baseline period, and outcome scoring."
);
