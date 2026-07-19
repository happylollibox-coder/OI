-- =============================================
-- DE_PRODUCT_BOM — per-product Bill of Materials
-- =============================================
-- Backs the Price Calculator's Bill of Materials builder (dashboard Products page).
-- One row per ASIN. The BOM (volume tiers + component per-unit prices) is stored as
-- JSON so tiers/components stay flexible:
--   bom_json = {
--     "tiers":      [500, 1000, 3000],          -- volume tier quantities
--     "activeTier": 1,                          -- index of the selected volume
--     "components": [ { "name": "Bunny Doll", "prices": [2.3, 2.2, 1.9] }, ... ]
--   }
-- Written by the Flask data-entry API (/api/products/bom).
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_PRODUCT_BOM` (
  asin       STRING NOT NULL OPTIONS(description="Product ASIN this BOM belongs to"),
  bom_json   STRING          OPTIONS(description="Bill of materials: tiers + components with per-tier unit prices (JSON)"),
  updated_at TIMESTAMP       OPTIONS(description="Last save time"),
  updated_by STRING          OPTIONS(description="User who last saved")
);
