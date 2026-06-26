-- DE_PRODUCT_STRATEGY_PROFILE — per parent × season × match-type bid strategy (derived; editable)
-- Append/update only — NEVER CREATE OR REPLACE (preserves source='MANUAL' rows).
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE` (
  parent_name     STRING NOT NULL,
  season          STRING NOT NULL,          -- PEAK / OFF
  match_type      STRING NOT NULL,          -- BROAD/EXACT/PHRASE/AUTO/PRODUCT
  enabled         BOOL NOT NULL,            -- FALSE => suppress bid-up (when confidence=CONCLUSIVE)
  cpc_target      FLOAT64,
  cpc_min         FLOAT64,
  cpc_max         FLOAT64,
  launch_cpc      FLOAT64,
  raise_pace_pct  FLOAT64,
  net_per_dollar  FLOAT64,                  -- evidence: SUM(net)/SUM(cost)
  confidence      STRING,                   -- CONCLUSIVE / WEAK
  tos_target_pct  FLOAT64,                  -- nullable until foundation A
  borrowed_from   STRING,                   -- nullable until sub-project C
  source          STRING NOT NULL,          -- DERIVED / MANUAL / BORROWED
  status          STRING,                   -- MANUAL suggestions: PENDING / VALIDATED / REJECTED (NULL/ACTIVE for DERIVED)
  applied_at      TIMESTAMP,                -- when a MANUAL suggestion went live (for outcome scoring)
  updated_at      TIMESTAMP,
  updated_by      STRING
)
OPTIONS (description = 'Per-product (parent x season x match-type) bid strategy the coacher steers toward. Derived by tools/strategy_profile; MANUAL rows preserved.');
