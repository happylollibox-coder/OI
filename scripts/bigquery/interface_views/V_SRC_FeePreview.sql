-- =============================================
-- OI Database Project - V_SRC_FeePreview
-- =============================================
--
-- Purpose: Standardized fee preview data from Daton FeePreviewReport
-- Business Logic: Deduplicates by latest batch, filters to US marketplace
-- Dependencies: daton-491514.BigQuery.amazon_selling_partner_FeePreviewReport
-- Project: onyga-482313
-- Dataset: OI
-- Created: 2026-04-03
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_SRC_FeePreview`
AS
SELECT
  CAST(marketplaceId AS STRING) AS marketplace_id,
  CAST(asin AS STRING) AS asin,
  CAST(sku AS STRING) AS sku,
  CAST(fnsku AS STRING) AS fnsku,
  product_name,
  your_price,
  sales_price,
  estimated_fee_total,
  estimated_referral_fee_per_unit,
  estimated_variable_closing_fee,
  estimated_order_handling_fee_per_order,
  estimated_pick_pack_fee_per_unit,
  estimated_weight_handling_fee_per_unit,
  expected_fulfillment_fee_per_unit,
  product_size_tier,
  currency,
  TIMESTAMP_MILLIS(CAST(_daton_batch_runtime AS INT64)) AS _synced_at
FROM (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY asin, sku
      ORDER BY _daton_batch_runtime DESC
    ) AS rn
  FROM `daton-491514.BigQuery.amazon_selling_partner_FeePreviewReport`
  WHERE marketplaceId = 'ATVPDKIKX0DER'
    AND asin IS NOT NULL
    AND currency = 'USD'
)
WHERE rn = 1;
