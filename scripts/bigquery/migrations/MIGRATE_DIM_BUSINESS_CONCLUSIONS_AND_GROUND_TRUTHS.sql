-- DIM_BUSINESS_CONCLUSIONS: User-approved business conclusions (from Learn page)
-- DIM_GROUND_TRUTHS: User-approved ground truths for action validation (from Action page)
-- Run: bq query --use_legacy_sql=false < MIGRATE_DIM_BUSINESS_CONCLUSIONS_AND_GROUND_TRUTHS.sql

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DIM_BUSINESS_CONCLUSIONS` (
  id STRING NOT NULL,
  conclusion STRING,
  evidence STRING,
  recommendation STRING,
  family STRING,
  experiment_id STRING,
  impact STRING,
  status STRING,
  created_at DATE,
  tags ARRAY<STRING>,
  updated_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DIM_GROUND_TRUTHS` (
  id STRING NOT NULL,
  experiment_id STRING,
  experiment_name STRING,
  metric STRING,
  op STRING,
  ref STRING,
  source_week STRING,
  description STRING,
  approved_at DATE,
  keyword STRING,
  updated_at TIMESTAMP
);
