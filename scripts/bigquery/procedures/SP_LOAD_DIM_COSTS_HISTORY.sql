-- =============================================
-- OI Database Project - SP_LOAD_DIM_COSTS_HISTORY
-- =============================================
--
-- Purpose: Load fee_preview_report + PO costs into DIM_COSTS_HISTORY as SCD Type 2
-- start_date < today: close row, insert new version. start_date = today: update in place.
-- Source: SRC_ACC_FEE_PREVIEW (from Daton FeePreviewReport), DE_PURCHASE_ORDERS, DE_SHIPMENT_LINES
-- Fallback: When PO/Shipment data is missing, inherits last known cost_of_goods/shipping_cost from DIM_COSTS_HISTORY
-- Filter: marketplace_id = ATVPDKIKX0DER
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_LOAD_DIM_COSTS_HISTORY`()
OPTIONS (
  description = "Load fee_preview_report + PO/Shipment costs into DIM_COSTS_HISTORY as SCD Type 2. Closes changed rows, inserts new versions. Carries forward COGS/Shipping when PO data is missing."
)
BEGIN
  DECLARE closed_count INT64 DEFAULT 0;
  DECLARE updated_count INT64 DEFAULT 0;
  DECLARE inserted_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- CTE: latest PO cost_of_goods per ASIN
  CREATE TEMP TABLE _po_costs AS
  SELECT
    product_asin AS asin,
    unit_price AS cost_of_goods,
    CAST(NULL AS FLOAT64) AS shipping_cost
  FROM (
    SELECT product_asin, unit_price,
      ROW_NUMBER() OVER (PARTITION BY product_asin ORDER BY order_date DESC) AS rn
    FROM `onyga-482313.OI.DE_PURCHASE_ORDERS`
    WHERE product_asin IS NOT NULL AND unit_price IS NOT NULL
  )
  WHERE rn = 1;

  -- CTE: latest Shipment shipping_cost per ASIN
  CREATE TEMP TABLE _shipment_costs AS
  SELECT
    asin,
    shipping_cost
  FROM (
    SELECT 
      po.product_asin AS asin,
      sl.allocated_cost / NULLIF(sl.quantity_shipped, 0) AS shipping_cost,
      ROW_NUMBER() OVER (PARTITION BY po.product_asin ORDER BY sl.created_at DESC) AS rn
    FROM `onyga-482313.OI.DE_SHIPMENT_LINES` sl
    JOIN `onyga-482313.OI.DE_PURCHASE_ORDERS` po ON sl.purchase_order_id = po.purchase_order_id
    WHERE sl.quantity_shipped > 0 AND sl.allocated_cost IS NOT NULL
  )
  WHERE rn = 1;

  -- Fallback: last known cost_of_goods and shipping_cost per ASIN from history
  -- Used when PO/Shipment data is missing to prevent NULL COGS
  CREATE TEMP TABLE _prev_costs AS
  SELECT asin, cost_of_goods, shipping_cost
  FROM (
    SELECT asin, cost_of_goods, shipping_cost,
      ROW_NUMBER() OVER (PARTITION BY marketplace_id, asin ORDER BY start_date DESC) AS rn
    FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
    WHERE marketplace_id = 'ATVPDKIKX0DER'
      AND cost_of_goods IS NOT NULL
  )
  WHERE rn = 1;

  CREATE TEMP TABLE _all_costs_src AS
  SELECT
    COALESCE(fee.marketplace_id, dim.marketplace) AS marketplace_id,
    COALESCE(fee.asin, dim.asin) AS asin,
    CAST(COALESCE(fee.sku, dim.sku) AS STRING) AS sku,
    CASE
      WHEN fee.estimated_pick_pack_fee_per_unit IS NULL OR fee.estimated_pick_pack_fee_per_unit = 0
      THEN fee.estimated_fee_total - fee.estimated_referral_fee_per_unit
      ELSE fee.estimated_pick_pack_fee_per_unit
    END AS estimated_pick_pack_fee_per_unit,
    fee.estimated_fee_total AS FBA_COST_estimated_fee_total,
    fee.estimated_referral_fee_per_unit AS FBA_COST_estimated_referral_fee_per_unit,
    COALESCE(po.cost_of_goods, prev.cost_of_goods) AS cost_of_goods,
    COALESCE(sh.shipping_cost, po.shipping_cost, prev.shipping_cost) AS shipping_cost,
    COALESCE(fee.processed_at, dim._fivetran_synced) AS processed_at,
    dim.product_name
  FROM `onyga-482313.OI.SRC_ACC_FEE_PREVIEW` fee
  FULL OUTER JOIN `onyga-482313.OI.DIM_PRODUCT` dim
    ON fee.marketplace_id = dim.marketplace
   AND fee.asin = dim.asin
   AND (fee.sku = dim.sku OR (fee.sku IS NULL AND dim.sku IS NULL))
  LEFT JOIN _po_costs po ON po.asin = COALESCE(fee.asin, dim.asin)
  LEFT JOIN _shipment_costs sh ON sh.asin = COALESCE(fee.asin, dim.asin)
  LEFT JOIN _prev_costs prev ON prev.asin = COALESCE(fee.asin, dim.asin)
  WHERE COALESCE(fee.marketplace_id, dim.marketplace) = 'ATVPDKIKX0DER'
    AND COALESCE(fee.asin, dim.asin) IS NOT NULL
    AND COALESCE(fee.asin, dim.asin) != 'UNKNOWN';

  -- Step 1a: Close rows where attributes changed AND start_date < today
  UPDATE `onyga-482313.OI.DIM_COSTS_HISTORY` acc
  SET end_date = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
  FROM _all_costs_src src
  WHERE acc.marketplace_id = src.marketplace_id
    AND acc.asin = src.asin
    AND (acc.sku = src.sku OR (acc.sku IS NULL AND src.sku IS NULL))
    AND acc.end_date IS NULL
    AND acc.start_date < CURRENT_DATE()
    AND (
      acc.estimated_pick_pack_fee_per_unit IS DISTINCT FROM src.estimated_pick_pack_fee_per_unit
      OR acc.FBA_COST_estimated_fee_total IS DISTINCT FROM src.FBA_COST_estimated_fee_total
      OR acc.FBA_COST_estimated_referral_fee_per_unit IS DISTINCT FROM src.FBA_COST_estimated_referral_fee_per_unit
      OR acc.cost_of_goods IS DISTINCT FROM src.cost_of_goods
      OR acc.shipping_cost IS DISTINCT FROM src.shipping_cost
    );

  SET closed_count = @@row_count;

  -- Step 1b: Update in place when start_date = today (same day, no new row)
  UPDATE `onyga-482313.OI.DIM_COSTS_HISTORY` acc
  SET
    estimated_pick_pack_fee_per_unit = src.estimated_pick_pack_fee_per_unit,
    FBA_COST_estimated_fee_total = src.FBA_COST_estimated_fee_total,
    FBA_COST_estimated_referral_fee_per_unit = src.FBA_COST_estimated_referral_fee_per_unit,
    cost_of_goods = src.cost_of_goods,
    shipping_cost = src.shipping_cost,
    TOTAL_COST_PER_UNIT = COALESCE(src.cost_of_goods, 0) + COALESCE(src.FBA_COST_estimated_fee_total, 0) + COALESCE(src.shipping_cost, 0),
    _fivetran_synced = src.processed_at
  FROM _all_costs_src src
  WHERE acc.marketplace_id = src.marketplace_id
    AND acc.asin = src.asin
    AND (acc.sku = src.sku OR (acc.sku IS NULL AND src.sku IS NULL))
    AND acc.end_date IS NULL
    AND acc.start_date = CURRENT_DATE()
    AND (
      acc.estimated_pick_pack_fee_per_unit IS DISTINCT FROM src.estimated_pick_pack_fee_per_unit
      OR acc.FBA_COST_estimated_fee_total IS DISTINCT FROM src.FBA_COST_estimated_fee_total
      OR acc.FBA_COST_estimated_referral_fee_per_unit IS DISTINCT FROM src.FBA_COST_estimated_referral_fee_per_unit
      OR acc.cost_of_goods IS DISTINCT FROM src.cost_of_goods
      OR acc.shipping_cost IS DISTINCT FROM src.shipping_cost
    );

  SET updated_count = @@row_count;

  -- Step 2a: Insert new rows for changed or new fee data (including new PO costs)
  INSERT INTO `onyga-482313.OI.DIM_COSTS_HISTORY` (
    marketplace_id, asin, sku,
    estimated_pick_pack_fee_per_unit, FBA_COST_estimated_fee_total,
    FBA_COST_estimated_referral_fee_per_unit,
    cost_of_goods, shipping_cost, TOTAL_COST_PER_UNIT,
    fnsku, product_name, _fivetran_synced, start_date, end_date
  )
  SELECT
    src.marketplace_id, src.asin, src.sku,
    src.estimated_pick_pack_fee_per_unit, src.FBA_COST_estimated_fee_total,
    src.FBA_COST_estimated_referral_fee_per_unit,
    src.cost_of_goods, src.shipping_cost,
    COALESCE(src.cost_of_goods, 0) + COALESCE(src.FBA_COST_estimated_fee_total, 0) + COALESCE(src.shipping_cost, 0) AS TOTAL_COST_PER_UNIT,
    CAST(NULL AS STRING) AS fnsku,
    src.product_name,
    src.processed_at,
    CURRENT_DATE() AS start_date,
    CAST(NULL AS DATE) AS end_date
  FROM _all_costs_src src
  WHERE NOT EXISTS (
    SELECT 1
    FROM `onyga-482313.OI.DIM_COSTS_HISTORY` acc
    WHERE acc.marketplace_id = src.marketplace_id
      AND acc.asin = src.asin
      AND (acc.sku = src.sku OR (acc.sku IS NULL AND src.sku IS NULL))
      AND acc.end_date IS NULL
      AND acc.estimated_pick_pack_fee_per_unit IS NOT DISTINCT FROM src.estimated_pick_pack_fee_per_unit
      AND acc.FBA_COST_estimated_fee_total IS NOT DISTINCT FROM src.FBA_COST_estimated_fee_total
      AND acc.FBA_COST_estimated_referral_fee_per_unit IS NOT DISTINCT FROM src.FBA_COST_estimated_referral_fee_per_unit
      AND acc.cost_of_goods IS NOT DISTINCT FROM src.cost_of_goods
      AND acc.shipping_cost IS NOT DISTINCT FROM src.shipping_cost
  );

  SET inserted_count = @@row_count;

  DROP TABLE _po_costs;
  DROP TABLE _shipment_costs;
  DROP TABLE _prev_costs;
  DROP TABLE _all_costs_src;

  SELECT FORMAT(
    'SP_LOAD_DIM_COSTS_HISTORY completed: Closed %d rows, Updated %d rows, Inserted %d rows, Duration: %d seconds',
    closed_count, updated_count, inserted_count,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND)
  ) as operation_summary;
END;
