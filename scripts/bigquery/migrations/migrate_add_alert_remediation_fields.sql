-- Migration to add remediation fields for alerts

ALTER TABLE `onyga-482313.OI.DE_ALERTS`
ADD COLUMN IF NOT EXISTS action_type STRING,
ADD COLUMN IF NOT EXISTS action_payload JSON,
ADD COLUMN IF NOT EXISTS snooze_until TIMESTAMP,
ADD COLUMN IF NOT EXISTS related_plan_id STRING,
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP;
