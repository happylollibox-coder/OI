-- =============================================
-- OI Database Project - V_SRC_ActiveListingsReport
-- =============================================
--
-- Purpose: Interface view over Daton ActiveListingsReport for listing pricing data
-- Business Logic: Deduplicates by business key, keeps latest batch per listing
-- Source: daton-491514.BigQuery.amazon_selling_partner_ActiveListingsReport
-- Grain: One row per (sellingPartnerId, marketplaceId, listing_id, seller_sku, asin1, fulfillment_channel)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_SRC_ActiveListingsReport`
AS
WITH ranked AS (
  SELECT
    ReportstartDate,
    ReportendDate,
    sellingPartnerId,
    marketplaceName,
    marketplaceId,
    listing_id,
    seller_sku,
    asin1,
    fulfillment_channel,
    CAST(price AS FLOAT64) AS price,
    CAST(Business_Price AS FLOAT64) AS Business_Price,
    Quantity_Price_Type,
    CAST(Quantity_Lower_Bound_1 AS FLOAT64) AS Quantity_Lower_Bound_1,
    CAST(Quantity_Price_1 AS FLOAT64) AS Quantity_Price_1,
    CAST(Quantity_Lower_Bound_2 AS FLOAT64) AS Quantity_Lower_Bound_2,
    CAST(Quantity_Price_2 AS FLOAT64) AS Quantity_Price_2,
    CAST(Quantity_Lower_Bound_3 AS FLOAT64) AS Quantity_Lower_Bound_3,
    CAST(Quantity_Price_3 AS FLOAT64) AS Quantity_Price_3,
    CAST(Quantity_Lower_Bound_4 AS FLOAT64) AS Quantity_Lower_Bound_4,
    CAST(Quantity_Price_4 AS FLOAT64) AS Quantity_Price_4,
    CAST(Quantity_Lower_Bound_5 AS FLOAT64) AS Quantity_Lower_Bound_5,
    CAST(Quantity_Price_5 AS FLOAT64) AS Quantity_Price_5,
    _daton_batch_runtime,
    ROW_NUMBER() OVER (
      PARTITION BY sellingPartnerId, marketplaceId, listing_id, seller_sku, asin1, fulfillment_channel
      ORDER BY _daton_batch_runtime DESC
    ) AS rn
  FROM `daton-491514.BigQuery.amazon_selling_partner_ActiveListingsReport`
  WHERE listing_id IS NOT NULL
)
SELECT
  ReportstartDate,
  ReportendDate,
  sellingPartnerId,
  marketplaceName,
  marketplaceId,
  listing_id,
  seller_sku,
  asin1,
  fulfillment_channel,
  price,
  Business_Price,
  Quantity_Price_Type,
  Quantity_Lower_Bound_1,
  Quantity_Price_1,
  Quantity_Lower_Bound_2,
  Quantity_Price_2,
  Quantity_Lower_Bound_3,
  Quantity_Price_3,
  Quantity_Lower_Bound_4,
  Quantity_Price_4,
  Quantity_Lower_Bound_5,
  Quantity_Price_5
FROM ranked
WHERE rn = 1;
