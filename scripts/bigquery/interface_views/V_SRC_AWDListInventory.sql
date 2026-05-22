-- =============================================
-- OI Database Project - V_SRC_AWDListInventory
-- =============================================
--
-- Purpose: Interface view to Daton AWD inventory report.
--          Deduplicates by SKU keeping the latest batch,
--          joins DIM_PRODUCT to resolve SKU → ASIN.
--
-- Source: daton-491514.BigQuery.amazon_selling_partner_AWDListInventory
-- Grain: One row per SKU (current snapshot, no history)
-- Sync: Daton syncs multiple times per day
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_SRC_AWDListInventory` AS

WITH ranked AS (
  SELECT
    sku,
    totalInboundQuantity AS inbound_quantity,
    totalOnhandQuantity AS onhand_quantity,
    (SELECT SUM(availableDistributableQuantity) FROM UNNEST(inventoryDetails)) AS available_quantity,
    (SELECT SUM(reservedDistributableQuantity) FROM UNNEST(inventoryDetails)) AS reserved_quantity,
    TIMESTAMP_MILLIS(CAST(_daton_batch_runtime AS INT64)) AS batch_time,
    _daton_batch_runtime,
    -- Deduplicate: keep the latest batch per SKU synced by Daton
    ROW_NUMBER() OVER (
      PARTITION BY sku
      ORDER BY _daton_batch_runtime DESC
    ) AS rn
  FROM `daton-491514.BigQuery.amazon_selling_partner_AWDListInventory`
  WHERE totalOnhandQuantity > 0
    AND CAST(_daton_batch_runtime AS INT64) >= (
      SELECT MAX(CAST(_daton_batch_runtime AS INT64)) - 3600000 
      FROM `daton-491514.BigQuery.amazon_selling_partner_AWDListInventory`
    )
)

SELECT
  p.asin,
  r.sku AS MSKU,
  p.product_short_name AS Title,
  r.inbound_quantity,
  r.onhand_quantity,
  r.available_quantity,
  r.reserved_quantity,
  r.batch_time AS last_updated_time
FROM ranked r
JOIN `onyga-482313.OI.DIM_PRODUCT` p
  ON p.sku = r.sku
  AND p.marketplace = 'ATVPDKIKX0DER'
WHERE r.rn = 1;
