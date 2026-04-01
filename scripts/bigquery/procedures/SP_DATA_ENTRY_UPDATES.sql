-- =============================================
-- Stored Procedure: SP_DATA_ENTRY_UPDATES
-- =============================================
-- 
-- Loads data from V_PO_SNAPSHOT view and calculates new fields:
--   1. LAST_PAYMENT_DATE - max of payment_date if all payments are paid
--   2. LAST_SHIPMENT_DATE - max of shipment_date if all shipments are created
--      (if shipment is_paid=true and paid_date is NULL, use shipment_date + 30 days)
--   3. LAST_ESTIMATED_ARRIVAL_DATE - max of estimated_arrival_date
--   4. END_DATE - greatest of LAST_PAYMENT_DATE, LAST_SHIPMENT_DATE, and max estimated_arrival_date
--      (only if both LAST_PAYMENT_DATE and LAST_SHIPMENT_DATE are not empty)
--
-- Flow:
--   1. Truncates STG_PURCHASE_ORDER
--   2. Inserts current snapshot from V_PO_SNAPSHOT into STG_PURCHASE_ORDER (with calculated fields)
--   3. Inserts from STG_PURCHASE_ORDER into FACT_PURCHASE_ORDER
--
-- Note: DE_PURCHASE_ORDERS is not modified (used for data entry only)
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_DATA_ENTRY_UPDATES`()
BEGIN
  TRUNCATE TABLE `onyga-482313.OI.STG_PURCHASE_ORDER`;
  
  -- Step 2: Insert all snapshots (2 calendar years: month-end dates + current date) from V_PO_SNAPSHOT into STG_PURCHASE_ORDER
  -- Calculate new fields (LAST_PAYMENT_DATE, LAST_SHIPMENT_DATE, etc.) based on payment and shipment data as of each snapshot date
  INSERT INTO `onyga-482313.OI.STG_PURCHASE_ORDER` (
    snapshot_date,
    year,
    month,
    quarter,
    is_current_date,
    is_month_end,
    purchase_order_id,
    order_date,
    manufacturer_name,
    product_id,
    product_asin,
    product_name,
    quantity,
    unit_price,
    total_amount,
    currency,
    payment_status,
    notes,
    created_at,
    LAST_PAYMENT_DATE,
    LAST_SHIPMENT_DATE,
    LAST_ESTIMATED_ARRIVAL_DATE,
    END_DATE,
    payments_remaining,
    quantity_remaining_at_manufacturer,
    quantity_remaining_at_shipment,
    cogs_remaining_at_manufacturer,
    cogs_remaining_at_shipment,
    selling_price_remaining_at_manufacturer,
    selling_price_remaining_at_shipment,
    is_fully_paid_as_of_snapshot,
    is_fully_shipped_as_of_snapshot,
    is_complete_as_of_snapshot,
    cost_of_goods,
    shipping_cost,
    loaded_at
  )
  SELECT 
    v.snapshot_date,
    v.year,
    v.month,
    v.quarter,
    v.is_current_date,
    v.is_month_end,
    v.purchase_order_id,
    v.order_date,
    v.manufacturer_name,
    v.product_id,
    v.product_asin,
    v.product_name,
    v.quantity,
    v.unit_price,
    v.total_amount,
    v.currency,
    v.payment_status,
    v.notes,
    v.created_at,
    
    -- Calculate LAST_PAYMENT_DATE: max of payment_date if all payments are paid
    CASE
      WHEN CAST(pp.total_paid AS FLOAT64) >= CAST(v.total_amount AS FLOAT64) - 0.01
        AND pp.total_paid > 0
      THEN pp.max_payment_date
      ELSE NULL
    END AS LAST_PAYMENT_DATE,
    
    -- Calculate LAST_SHIPMENT_DATE: max of shipment_date if all shipments are created
    -- (if shipment is_paid=true and paid_date is NULL, use shipment_date + 30 days)
    CASE
      WHEN ss.total_quantity_shipped >= v.quantity
        AND ss.total_quantity_shipped > 0
      THEN ss.max_shipment_date
      ELSE NULL
    END AS LAST_SHIPMENT_DATE,
    
    -- Calculate LAST_ESTIMATED_ARRIVAL_DATE: max of estimated_arrival_date
    ss.max_estimated_arrival_date AS LAST_ESTIMATED_ARRIVAL_DATE,
    
    -- Calculate END_DATE: greatest of LAST_PAYMENT_DATE, LAST_SHIPMENT_DATE, and max estimated_arrival_date
    -- (only if both LAST_PAYMENT_DATE and LAST_SHIPMENT_DATE are not empty)
    CASE
      WHEN CAST(pp.total_paid AS FLOAT64) >= CAST(v.total_amount AS FLOAT64) - 0.01
        AND pp.total_paid > 0
        AND ss.total_quantity_shipped >= v.quantity
        AND ss.total_quantity_shipped > 0
      THEN GREATEST(
        pp.max_payment_date,
        ss.max_shipment_date,
        COALESCE(ss.max_estimated_arrival_date, DATE('1900-01-01'))
      )
      ELSE NULL
    END AS END_DATE,
    
    v.payments_remaining,
    v.quantity_remaining_at_manufacturer,
    v.quantity_remaining_at_shipment,
    v.cogs_remaining_at_manufacturer,
    v.cogs_remaining_at_shipment,
    v.selling_price_remaining_at_manufacturer,
    v.selling_price_remaining_at_shipment,
    v.is_fully_paid_as_of_snapshot,
    v.is_fully_shipped_as_of_snapshot,
    v.is_complete_as_of_snapshot,
    v.cost_of_goods,
    v.shipping_cost,
    CURRENT_TIMESTAMP() AS loaded_at
    
  FROM `onyga-482313.OI.V_PO_SNAPSHOT` v
  
  LEFT JOIN (
    -- Payment summary: total paid and max payment date per PO as of snapshot date
    SELECT 
      v2.purchase_order_id,
      v2.snapshot_date,
      SUM(p.payment_amount) AS total_paid,
      MAX(p.payment_date) AS max_payment_date
    FROM `onyga-482313.OI.V_PO_SNAPSHOT` v2
    LEFT JOIN `onyga-482313.OI.DE_VENDOR_PAYMENTS` p ON (
      v2.purchase_order_id = p.purchase_order_id
      AND p.payment_date <= v2.snapshot_date
    )
    GROUP BY v2.purchase_order_id, v2.snapshot_date
  ) pp ON (
    v.purchase_order_id = pp.purchase_order_id
    AND v.snapshot_date = pp.snapshot_date
  )
  
  LEFT JOIN (
    -- Shipment summary: total quantity shipped, max shipment date, max estimated arrival date per PO as of snapshot date
    -- For LAST_SHIPMENT_DATE: if is_paid=true and paid_date is NULL, use shipment_date + 30 days
    SELECT 
      v2.purchase_order_id,
      v2.snapshot_date,
      SUM(sl.quantity_shipped) AS total_quantity_shipped,
      MAX(
        CASE 
          WHEN s.is_paid = TRUE AND s.paid_date IS NULL 
          THEN DATE_ADD(s.shipment_date, INTERVAL 30 DAY)
          ELSE s.shipment_date
        END
      ) AS max_shipment_date,
      MAX(s.estimated_arrival_date) AS max_estimated_arrival_date
    FROM `onyga-482313.OI.V_PO_SNAPSHOT` v2
    LEFT JOIN `onyga-482313.OI.DE_SHIPMENT_LINES` sl ON (
      v2.purchase_order_id = sl.purchase_order_id
    )
    LEFT JOIN `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s ON (
      sl.shipment_id = s.shipment_id
      AND s.shipment_date <= v2.snapshot_date
    )
    GROUP BY v2.purchase_order_id, v2.snapshot_date
  ) ss ON (
    v.purchase_order_id = ss.purchase_order_id
    AND v.snapshot_date = ss.snapshot_date
  );
  
  -- Step 3: Delete existing rows from FACT_PURCHASE_ORDER with the same snapshot_date as STG
  DELETE FROM `onyga-482313.OI.FACT_PURCHASE_ORDER`
  WHERE snapshot_date IN (
    SELECT DISTINCT snapshot_date 
    FROM `onyga-482313.OI.STG_PURCHASE_ORDER`
  );
  
  -- Step 4: Insert from STG_PURCHASE_ORDER into FACT_PURCHASE_ORDER
  INSERT INTO `onyga-482313.OI.FACT_PURCHASE_ORDER` (
    snapshot_date,
    year,
    month,
    quarter,
    is_current_date,
    is_month_end,
    purchase_order_id,
    order_date,
    manufacturer_name,
    product_id,
    product_asin,
    product_name,
    quantity,
    unit_price,
    total_amount,
    currency,
    payment_status,
    notes,
    created_at,
    LAST_PAYMENT_DATE,
    LAST_SHIPMENT_DATE,
    LAST_ESTIMATED_ARRIVAL_DATE,
    END_DATE,
    payments_remaining,
    quantity_remaining_at_manufacturer,
    quantity_remaining_at_shipment,
    cogs_remaining_at_manufacturer,
    cogs_remaining_at_shipment,
    selling_price_remaining_at_manufacturer,
    selling_price_remaining_at_shipment,
    is_fully_paid_as_of_snapshot,
    is_fully_shipped_as_of_snapshot,
    is_complete_as_of_snapshot,
    cost_of_goods,
    shipping_cost,
    factless_key,
    loaded_at
  )
  SELECT 
    snapshot_date,
    year,
    month,
    quarter,
    is_current_date,
    is_month_end,
    purchase_order_id,
    order_date,
    manufacturer_name,
    product_id,
    product_asin,
    product_name,
    quantity,
    unit_price,
    total_amount,
    currency,
    payment_status,
    notes,
    created_at,
    LAST_PAYMENT_DATE,
    LAST_SHIPMENT_DATE,
    LAST_ESTIMATED_ARRIVAL_DATE,
    END_DATE,
    payments_remaining,
    quantity_remaining_at_manufacturer,
    quantity_remaining_at_shipment,
    cogs_remaining_at_manufacturer,
    cogs_remaining_at_shipment,
    selling_price_remaining_at_manufacturer,
    selling_price_remaining_at_shipment,
    is_fully_paid_as_of_snapshot,
    is_fully_shipped_as_of_snapshot,
    is_complete_as_of_snapshot,
    cost_of_goods,
    shipping_cost,
    -- Factless Key: date_key - asin
    CONCAT(CAST(CAST(FORMAT_DATE('%Y%m%d', snapshot_date) AS INT64) AS STRING), '-', COALESCE(product_asin, 'UNKNOWN')) AS factless_key,
    loaded_at
  FROM `onyga-482313.OI.STG_PURCHASE_ORDER`;
END;
