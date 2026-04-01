-- =============================================
-- OI Database Project - SP_LOAD_DIM_COSTS_HISTORY
-- =============================================
--
-- Purpose: Load fee_preview_report + PO costs into DIM_COSTS_HISTORY as SCD Type 2
-- start_date < today: close row, insert new version. start_date = today: update in place.
-- Source: fivetran-hl.amazon_selling_partner.fee_preview_report, DE_PURCHASE_ORDERS, DE_MANUFACTURER_SHIPMENTS
-- Fallback: When PO data is missing, inherits last known cost_of_goods/shipping_cost from DIM_COSTS_HISTORY
-- Filter: marketplace_id = ATVPDKIKX0DER
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_LOAD_DIM_COSTS_HISTORY`()
OPTIONS (
  description = "Load fee_preview_report + PO costs into DIM_COSTS_HISTORY as SCD Type 2. Closes changed rows, inserts new versions. Carries forward COGS when PO data is missing."
)
BEGIN
  DECLARE closed_count INT64 DEFAULT 0;
  DECLARE updated_count INT64 DEFAULT 0;
  DECLARE inserted_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- CTE: latest PO cost_of_goods and shipping per ASIN (reused in all steps)
  CREATE TEMP TABLE _po_costs AS
  SELECT
    lpo.asin,
    lpo.unit_price AS cost_of_goods,
    AVG(s.unit_cost) AS shipping_cost
  FROM (
    SELECT product_asin AS asin, purchase_order_id, unit_price,
      ROW_NUMBER() OVER (PARTITION BY product_asin ORDER BY order_date DESC) AS rn
    FROM `onyga-482313.OI.DE_PURCHASE_ORDERS`
    WHERE product_asin IS NOT NULL AND unit_price IS NOT NULL
  ) lpo
  LEFT JOIN `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s
    ON lpo.purchase_order_id = s.purchase_order_id AND s.unit_cost IS NOT NULL
  WHERE lpo.rn = 1
  GROUP BY lpo.asin, lpo.unit_price;

  -- Fallback: last known cost_of_goods and shipping_cost per ASIN from history
  -- Used when PO data is missing (e.g. fake POs were deleted) to prevent NULL COGS
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

  -- Step 1a: Close rows where attributes changed AND start_date < today
  UPDATE `onyga-482313.OI.DIM_COSTS_HISTORY` acc
  SET end_date = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
  FROM (
    SELECT
      CAST(fee.marketplace_id AS STRING) AS marketplace_id,
      CAST(fee.asin AS STRING) AS asin,
      CAST(fee.sku AS STRING) AS sku,
      COALESCE(fee.estimated_pick_pack_fee_per_unit,
        fee.estimated_fee_total - fee.estimated_referral_fee_per_unit) AS estimated_pick_pack_fee_per_unit,
      fee.estimated_fee_total AS FBA_COST_estimated_fee_total,
      fee.estimated_referral_fee_per_unit AS FBA_COST_estimated_referral_fee_per_unit,
      COALESCE(po.cost_of_goods, prev.cost_of_goods) AS cost_of_goods,
      COALESCE(po.shipping_cost, prev.shipping_cost) AS shipping_cost
    FROM `fivetran-hl.amazon_selling_partner.fee_preview_report` fee
    LEFT JOIN _po_costs po ON po.asin = CAST(fee.asin AS STRING)
    LEFT JOIN _prev_costs prev ON prev.asin = CAST(fee.asin AS STRING)
    WHERE fee.asin IS NOT NULL
      AND fee.marketplace_id IS NOT NULL
      AND CAST(fee.marketplace_id AS STRING) = 'ATVPDKIKX0DER'
  ) src
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
    _fivetran_synced = src._fivetran_synced
  FROM (
    SELECT
      CAST(fee.marketplace_id AS STRING) AS marketplace_id,
      CAST(fee.asin AS STRING) AS asin,
      CAST(fee.sku AS STRING) AS sku,
      COALESCE(fee.estimated_pick_pack_fee_per_unit,
        fee.estimated_fee_total - fee.estimated_referral_fee_per_unit) AS estimated_pick_pack_fee_per_unit,
      fee.estimated_fee_total AS FBA_COST_estimated_fee_total,
      fee.estimated_referral_fee_per_unit AS FBA_COST_estimated_referral_fee_per_unit,
      COALESCE(po.cost_of_goods, prev.cost_of_goods) AS cost_of_goods,
      COALESCE(po.shipping_cost, prev.shipping_cost) AS shipping_cost,
      fee._fivetran_synced
    FROM `fivetran-hl.amazon_selling_partner.fee_preview_report` fee
    LEFT JOIN _po_costs po ON po.asin = CAST(fee.asin AS STRING)
    LEFT JOIN _prev_costs prev ON prev.asin = CAST(fee.asin AS STRING)
    WHERE fee.asin IS NOT NULL
      AND fee.marketplace_id IS NOT NULL
      AND CAST(fee.marketplace_id AS STRING) = 'ATVPDKIKX0DER'
  ) src
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

  -- Step 2a: Insert new rows for changed or new fee data
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
    CAST(NULL AS STRING) AS product_name,
    src._fivetran_synced,
    CURRENT_DATE() AS start_date,
    CAST(NULL AS DATE) AS end_date
  FROM (
    SELECT
      CAST(fee.marketplace_id AS STRING) AS marketplace_id,
      CAST(fee.asin AS STRING) AS asin,
      CAST(fee.sku AS STRING) AS sku,
      COALESCE(fee.estimated_pick_pack_fee_per_unit,
        fee.estimated_fee_total - fee.estimated_referral_fee_per_unit) AS estimated_pick_pack_fee_per_unit,
      fee.estimated_fee_total AS FBA_COST_estimated_fee_total,
      fee.estimated_referral_fee_per_unit AS FBA_COST_estimated_referral_fee_per_unit,
      COALESCE(po.cost_of_goods, prev.cost_of_goods) AS cost_of_goods,
      COALESCE(po.shipping_cost, prev.shipping_cost) AS shipping_cost,
      fee._fivetran_synced
    FROM `fivetran-hl.amazon_selling_partner.fee_preview_report` fee
    LEFT JOIN _po_costs po ON po.asin = CAST(fee.asin AS STRING)
    LEFT JOIN _prev_costs prev ON prev.asin = CAST(fee.asin AS STRING)
    WHERE fee.asin IS NOT NULL
      AND fee.marketplace_id IS NOT NULL
      AND CAST(fee.marketplace_id AS STRING) = 'ATVPDKIKX0DER'
  ) src
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

  -- Step 2b: Insert rows for products not in fee_preview_report (PO data only, no FBA fees yet)
  INSERT INTO `onyga-482313.OI.DIM_COSTS_HISTORY` (
    marketplace_id, asin, sku,
    estimated_pick_pack_fee_per_unit, FBA_COST_estimated_fee_total,
    FBA_COST_estimated_referral_fee_per_unit,
    cost_of_goods, shipping_cost, TOTAL_COST_PER_UNIT,
    fnsku, product_name, _fivetran_synced, start_date, end_date
  )
  SELECT
    dim.marketplace AS marketplace_id,
    dim.asin,
    dim.sku,
    CAST(NULL AS FLOAT64),
    CAST(NULL AS FLOAT64),
    CAST(NULL AS FLOAT64),
    COALESCE(po.cost_of_goods, prev.cost_of_goods) AS cost_of_goods,
    COALESCE(po.shipping_cost, prev.shipping_cost) AS shipping_cost,
    COALESCE(COALESCE(po.cost_of_goods, prev.cost_of_goods), 0) + COALESCE(COALESCE(po.shipping_cost, prev.shipping_cost), 0) AS TOTAL_COST_PER_UNIT,
    CAST(NULL AS STRING),
    dim.product_name,
    dim._fivetran_synced,
    CURRENT_DATE() AS start_date,
    CAST(NULL AS DATE) AS end_date
  FROM `onyga-482313.OI.DIM_PRODUCT` dim
  LEFT JOIN _po_costs po ON po.asin = dim.asin
  LEFT JOIN _prev_costs prev ON prev.asin = dim.asin
  WHERE dim.marketplace = 'ATVPDKIKX0DER'
    AND dim.asin IS NOT NULL
    AND dim.asin != 'UNKNOWN'
    AND NOT EXISTS (
      SELECT 1 FROM `fivetran-hl.amazon_selling_partner.fee_preview_report` fee
      WHERE CAST(fee.marketplace_id AS STRING) = dim.marketplace
        AND CAST(fee.asin AS STRING) = dim.asin
        AND (fee.sku = dim.sku OR (fee.sku IS NULL AND dim.sku IS NULL))
    )
    AND NOT EXISTS (
      SELECT 1 FROM `onyga-482313.OI.DIM_COSTS_HISTORY` acc
      WHERE acc.marketplace_id = dim.marketplace
        AND acc.asin = dim.asin
        AND (acc.sku = dim.sku OR (acc.sku IS NULL AND dim.sku IS NULL))
        AND acc.end_date IS NULL
    );

  SET inserted_count = inserted_count + @@row_count;

  DROP TABLE _po_costs;
  DROP TABLE _prev_costs;

  SELECT FORMAT(
    'SP_LOAD_DIM_COSTS_HISTORY completed: Closed %d rows, Updated %d rows, Inserted %d rows, Duration: %d seconds',
    closed_count, updated_count, inserted_count,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND)
  ) as operation_summary;
END;
