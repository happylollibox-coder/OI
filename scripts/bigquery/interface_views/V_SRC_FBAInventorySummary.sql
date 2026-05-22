-- =============================================
-- OI Database Project - V_SRC_FBAInventorySummary
-- =============================================
--
-- Purpose: Interface view to Daton FBA Manage Inventory report.
--          Deduplicates by (asin, fnsku) keeping the latest batch,
--          maps to the shape consumed by SRC_ACC_INVENTORY_FBA.
--
-- Source: daton-491514.BigQuery.amazon_selling_partner_FBAManageInventory
-- Grain: One row per ASIN × FNSKU (current snapshot, no history)
-- Sync: Daton syncs multiple times per day
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_SRC_FBAInventorySummary` AS

WITH ranked AS (
  SELECT
    asin,
    fnsku AS FNSKU,
    sku AS MSKU,
    product_name AS Title,
    `condition`,
    afn_fulfillable_quantity AS fulfillable_quantity,
    afn_reserved_quantity AS total_reserved_quantity,
    afn_inbound_working_quantity AS inbound_working_quantity,
    afn_inbound_shipped_quantity AS inbound_shipped_quantity,
    afn_inbound_receiving_quantity AS inbound_receiving_quantity,
    afn_total_quantity AS total_quantity,
    afn_unsellable_quantity AS total_unfulfillable_quantity,
    afn_researching_quantity AS total_researching_quantity,
    TIMESTAMP_MILLIS(CAST(_daton_batch_runtime AS INT64)) AS batch_time,
    _daton_batch_runtime,
    -- Deduplicate: keep latest batch per (asin, fnsku)
    ROW_NUMBER() OVER (
      PARTITION BY asin, fnsku
      ORDER BY _daton_batch_runtime DESC
    ) AS rn
  FROM `daton-491514.BigQuery.amazon_selling_partner_FBAManageInventory`
  WHERE asin IS NOT NULL
    AND afn_total_quantity > 0
)

SELECT
  asin,
  FNSKU,
  MSKU,
  Title,
  fulfillable_quantity,
  total_reserved_quantity,
  inbound_working_quantity,
  inbound_shipped_quantity,
  inbound_receiving_quantity,
  total_quantity,
  total_unfulfillable_quantity,
  total_researching_quantity,
  batch_time AS last_updated_time,
  batch_time AS _fivetran_synced
FROM ranked
WHERE rn = 1;
