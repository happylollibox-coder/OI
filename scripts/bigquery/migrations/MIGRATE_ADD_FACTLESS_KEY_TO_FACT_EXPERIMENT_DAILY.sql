-- =============================================
-- Migration: Add factless_key to FACT_EXPERIMENT_DAILY
-- =============================================
--
-- Purpose: Connect FACT_EXPERIMENT_DAILY to FACT_FACTLESS_BRIDGE
--   - Adds factless_key column (YYYYMMDD-ASIN format)
--   - SP_EXPERIMENT_DAILY_SNAPSHOT populates it on next run
--   - SP_POPULATE_FACTLESS_BRIDGE includes FACT_EXPERIMENT_DAILY keys
--
-- Run order:
--   1. This migration (ALTER TABLE)
--   2. CALL SP_EXPERIMENT_DAILY_SNAPSHOT() to backfill factless_key
--   3. CALL SP_POPULATE_FACTLESS_BRIDGE() to include experiment keys
--
-- =============================================

ALTER TABLE `onyga-482313.OI.FACT_EXPERIMENT_DAILY`
  ADD COLUMN IF NOT EXISTS factless_key STRING;
