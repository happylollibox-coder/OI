-- DE_PROBE_LOG — tracks each keyword probe's decision budget (15 clicks / 14 days). Coacher C.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_PROBE_LOG` (
  keyword_id          STRING NOT NULL,
  parent_name         STRING,
  season              STRING,
  match_type          STRING,
  intent_class        STRING,
  probe_launch_cpc    FLOAT64,
  probe_started_at    DATE,
  clicks_accumulated  INT64,
  status              STRING,        -- ACTIVE | GRADUATED | EXHAUSTED
  decided_at          DATE,
  updated_at          TIMESTAMP
);
