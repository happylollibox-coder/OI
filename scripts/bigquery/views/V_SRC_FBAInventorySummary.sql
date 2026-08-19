-- =============================================
-- OI Database Project - V_SRC_FBAInventorySummary
-- =============================================
--
-- Purpose: Interface view to Daton FBA Manage Inventory report.
--          Deduplicates by (asin, fnsku) keeping the latest batch,
--          maps to the shape consumed by SRC_ACC_INVENTORY_FBA.
--          Enriched with the reserved breakdown from the SP-API
--          FBAInventorySummary report (customer-order / transshipment / FC-processing).
--
-- Source: daton-491514.BigQuery.amazon_selling_partner_FBAManageInventory
--         daton-491514.BigQuery.amazon_selling_partner_FBAInventorySummary (reserved split)
-- Grain: One row per ASIN × FNSKU (current snapshot, no history)
-- Sync: Daton syncs multiple times per day
--
-- Amazon's at-warehouse identity (verified against the raw report):
--   afn_warehouse_quantity = afn_fulfillable + afn_reserved + afn_fc_transfer
--   afn_reserved           = pending_customer_order + fc_processing   (fc_transfer is SEPARATE)
--
-- fba_available_quantity (2026-08-13): units physically in Amazon's network and not
--   already sold = fulfillable + reserved + FC transfer − pending customer orders.
--   FC-transfer units are mid-move between fulfillment centers: unsellable right now,
--   sellable in days, and they are stock we own — so supply planning counts them.
--   Prior definition omitted afn_fc_transfer_quantity and understated FBA by ~14%.
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_SRC_FBAInventorySummary` AS

WITH manage AS (
  SELECT
    asin,
    fnsku AS FNSKU,
    sku AS MSKU,
    product_name AS Title,
    afn_fulfillable_quantity AS fulfillable_quantity,
    afn_reserved_quantity AS total_reserved_quantity,
    afn_fc_transfer_quantity AS fc_transfer_quantity,
    afn_warehouse_quantity AS warehouse_quantity,
    afn_inbound_working_quantity AS inbound_working_quantity,
    afn_inbound_shipped_quantity AS inbound_shipped_quantity,
    afn_inbound_receiving_quantity AS inbound_receiving_quantity,
    afn_total_quantity AS total_quantity,
    afn_unsellable_quantity AS total_unfulfillable_quantity,
    afn_researching_quantity AS total_researching_quantity,
    TIMESTAMP_MILLIS(CAST(_daton_batch_runtime AS INT64)) AS batch_time,
    -- Deduplicate: keep latest batch per (asin, fnsku)
    ROW_NUMBER() OVER (
      PARTITION BY asin, fnsku
      ORDER BY _daton_batch_runtime DESC
    ) AS rn
  FROM `daton-491514.BigQuery.amazon_selling_partner_FBAManageInventory`
  WHERE asin IS NOT NULL
    AND afn_total_quantity > 0
),

-- Extract reserved breakdown from FBAInventorySummary
summary_reserved AS (
  SELECT
    asin,
    r.pendingCustomerOrderQuantity,
    r.pendingTransshipmentQuantity,
    r.fcProcessingQuantity,
    ROW_NUMBER() OVER (
      PARTITION BY asin
      ORDER BY _daton_batch_runtime DESC
    ) AS rn
  FROM `daton-491514.BigQuery.amazon_selling_partner_FBAInventorySummary`,
    UNNEST(inventoryDetails) d,
    UNNEST(d.reservedQuantity) r
  WHERE asin IS NOT NULL
)

SELECT
  m.asin, m.FNSKU, m.MSKU, m.Title,
  m.fulfillable_quantity, m.total_reserved_quantity,
  m.fc_transfer_quantity, m.warehouse_quantity,
  m.inbound_working_quantity, m.inbound_shipped_quantity, m.inbound_receiving_quantity,
  m.total_quantity, m.total_unfulfillable_quantity, m.total_researching_quantity,
  m.batch_time AS last_updated_time, m.batch_time AS _fivetran_synced,
  -- Reserved breakdown (from FBAInventorySummary)
  COALESCE(sr.pendingCustomerOrderQuantity, 0) AS pending_customer_order_quantity,
  COALESCE(sr.pendingTransshipmentQuantity, 0) AS pending_transshipment_quantity,
  COALESCE(sr.fcProcessingQuantity, 0) AS fc_processing_quantity,
  -- Computed fields for downstream use
  -- At Amazon, not already sold: fulfillable + reserved + FC transfer − pending customer orders
  m.fulfillable_quantity + m.total_reserved_quantity + COALESCE(m.fc_transfer_quantity, 0)
    - COALESCE(sr.pendingCustomerOrderQuantity, 0) AS fba_available_quantity,
  m.inbound_shipped_quantity + m.inbound_receiving_quantity AS in_transit_quantity
FROM manage m
LEFT JOIN summary_reserved sr
  ON sr.asin = m.asin AND sr.rn = 1
WHERE m.rn = 1;
