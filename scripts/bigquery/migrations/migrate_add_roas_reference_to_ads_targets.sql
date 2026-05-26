-- Add LY/CY Net ROAS reference columns to DE_PLAN_ADS_TARGETS.
-- ly_/cy_ad_net_roas = ad-only Net ROAS (per channel row, from V_ADS_CHANNEL_EFFICIENCY).
-- ly_/cy_net_roas    = blended (organic-inclusive) Net ROAS (family-month, on all channel rows).
-- Frozen at plan-save time so the Ads Coach can judge halo (blended vs ad-only) and direction (LY→CY).
-- Non-destructive: nullable ADD COLUMN IF NOT EXISTS (idempotent).
ALTER TABLE `onyga-482313.OI.DE_PLAN_ADS_TARGETS` ADD COLUMN IF NOT EXISTS ly_ad_net_roas FLOAT64;
ALTER TABLE `onyga-482313.OI.DE_PLAN_ADS_TARGETS` ADD COLUMN IF NOT EXISTS cy_ad_net_roas FLOAT64;
ALTER TABLE `onyga-482313.OI.DE_PLAN_ADS_TARGETS` ADD COLUMN IF NOT EXISTS ly_net_roas FLOAT64;
ALTER TABLE `onyga-482313.OI.DE_PLAN_ADS_TARGETS` ADD COLUMN IF NOT EXISTS cy_net_roas FLOAT64;
