-- ad_group_id for DO-queue exports (SB keyword updates require it in bulksheets).
ALTER TABLE `onyga-482313.OI.FACT_ADS_COACH_ACTIONS`
  ADD COLUMN IF NOT EXISTS ad_group_id STRING;
