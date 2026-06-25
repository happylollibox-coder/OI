-- =============================================
-- OI Database Project - DE_SHIPMENT_OTHER_PO Table
-- =============================================
-- Junction table linking shipments to Other POs (service/misc POs).
-- A shipment can connect multiple Other POs; their total_amount is rolled
-- into the shipment's landed-cost allocation.
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.DE_SHIPMENT_OTHER_PO` (
  link_id      STRING NOT NULL,   -- UUID, e.g. SOP_abc123
  shipment_id  STRING NOT NULL,   -- FK → DE_MANUFACTURER_SHIPMENTS
  other_po_id  STRING NOT NULL,   -- FK → DE_OTHER_PO
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),

  PRIMARY KEY (link_id) NOT ENFORCED
);
