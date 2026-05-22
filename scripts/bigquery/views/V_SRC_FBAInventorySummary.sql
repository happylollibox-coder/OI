-- =============================================
-- OI Database Project - V_SRC_FBAInventorySummary
-- =============================================
--
-- Purpose: Interface view over Daton's FBAManageInventory + FBAInventorySummary
--          Provides latest point-in-time FBA inventory with reserved breakdown.
--
-- Source: daton-491514.BigQuery.amazon_selling_partner_FBAManageInventory (main)
--         daton-491514.BigQuery.amazon_selling_partner_FBAInventorySummary (reserved detail)
--
-- Business Logic:
--   FBA quantity = afn_fulfillable_quantity + afn_reserved_quantity - pendingCustomerOrderQuantity
--   In Transit   = afn_inbound_shipped_quantity
--   Customer orders reserved are excluded from FBA because those units are "sold"
--
-- Project: onyga-482313
-- Dataset: OI
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
    afn_inbound_working_quantity AS inbound_working_quantity,
    afn_inbound_shipped_quantity AS inbound_shipped_quantity,
    afn_inbound_receiving_quantity AS inbound_receiving_quantity,
    afn_total_quantity AS total_quantity,
    afn_unsellable_quantity AS total_unfulfillable_quantity,
    afn_researching_quantity AS total_researching_quantity,
    TIMESTAMP_MILLIS(CAST(_daton_batch_runtime AS INT64)) AS batch_time,
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
  m.inbound_working_quantity, m.inbound_shipped_quantity, m.inbound_receiving_quantity,
  m.total_quantity, m.total_unfulfillable_quantity, m.total_researching_quantity,
  m.batch_time AS last_updated_time, m.batch_time AS _fivetran_synced,
  -- Reserved breakdown (from FBAInventorySummary)
  COALESCE(sr.pendingCustomerOrderQuantity, 0) AS pending_customer_order_quantity,
  COALESCE(sr.pendingTransshipmentQuantity, 0) AS pending_transshipment_quantity,
  COALESCE(sr.fcProcessingQuantity, 0) AS fc_processing_quantity,
  -- Computed fields for downstream use
  m.fulfillable_quantity + m.total_reserved_quantity
    - COALESCE(sr.pendingCustomerOrderQuantity, 0) AS fba_available_quantity,
  m.inbound_shipped_quantity + m.inbound_receiving_quantity AS in_transit_quantity
FROM manage m
LEFT JOIN summary_reserved sr
  ON sr.asin = m.asin AND sr.rn = 1
WHERE m.rn = 1;
