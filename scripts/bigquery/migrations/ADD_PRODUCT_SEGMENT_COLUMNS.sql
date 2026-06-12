-- =============================================
-- Migration: Add product segmentation columns to DIM_PRODUCT
-- =============================================
-- Date: 2026-06-07
-- Purpose: Store product-level segmentation (multi-value, comma-separated)
--          Auto-derived from ad purchase data, manually overridable.
-- =============================================

ALTER TABLE `onyga-482313`.OI.DIM_PRODUCT
  ADD COLUMN IF NOT EXISTS seg_gender STRING
    OPTIONS(description='Target gender(s), comma-separated. e.g. Female,Male');

ALTER TABLE `onyga-482313`.OI.DIM_PRODUCT
  ADD COLUMN IF NOT EXISTS seg_age_group STRING
    OPTIONS(description='Target age group(s), comma-separated. e.g. 5-9 (Kid),10-12 (Tween)');

ALTER TABLE `onyga-482313`.OI.DIM_PRODUCT
  ADD COLUMN IF NOT EXISTS seg_occasion STRING
    OPTIONS(description='Target occasion(s), comma-separated. e.g. Birthday,Christmas');

ALTER TABLE `onyga-482313`.OI.DIM_PRODUCT
  ADD COLUMN IF NOT EXISTS seg_product_type STRING
    OPTIONS(description='Shopper product type(s), comma-separated. e.g. Accessories,Gift Sets');
