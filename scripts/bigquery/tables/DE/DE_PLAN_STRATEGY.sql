-- DE_PLAN_STRATEGY — Versioned plan strategies per family × month
-- Plans have lifecycle: DRAFT → APPROVED
-- Only one DRAFT plan at a time. Approved = locked until unapproved.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_PLAN_STRATEGY` (
  plan_id       STRING NOT NULL,
  plan_name     STRING NOT NULL,
  plan_year     INT64 NOT NULL,
  plan_version  INT64 NOT NULL,
  status        STRING NOT NULL,       -- 'DRAFT' | 'APPROVED'
  family        STRING NOT NULL,
  strategy      STRING,                -- 'OPTIMIZED' | 'HISTORIC' | 'SEASONAL' | 'CONSERVATIVE' | 'AGGRESSIVE'
  forecast_year  INT64,
  forecast_month INT64,
  multiplier    FLOAT64,
  target_roas   FLOAT64,
  base_roas     FLOAT64,
  growth_rate   FLOAT64,
  growth_json   STRING,                -- JSON: per-product growth overrides {"product": rate}
  order_overrides_json STRING,         -- JSON: per-product yearly planned units
  original_overrides_json STRING,      -- JSON: original overrides at first approval
  snapshot_units_json STRING,          -- JSON: frozen sim output {"product": {"YYYYMM": units}}
  updated_at    DATETIME,
  updated_by    STRING
);
