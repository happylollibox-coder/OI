-- =============================================
-- OI Database Project - SP_LOAD_FACT_INVENTORY_SNAPSHOT
-- =============================================
--
-- Purpose: Load FACT_INVENTORY_SNAPSHOT from V_UNIFIED_INVENTORY_SNAPSHOT
--          and add purchase order data (COGS_AMOUNT, SELL_AMOUNT) from FACT_PURCHASE_ORDER
--
-- Business Logic:
--   Source types in FACT_INVENTORY_SNAPSHOT:
--     FBA        = afn_fulfillable + afn_reserved - pending_customer_orders
--                  (units in Amazon's warehouses, excluding already-sold units)
--     In Transit = afn_inbound_shipped + afn_inbound_receiving
--                  (shipped to Amazon, not yet checked in; comes from V_UNIFIED)
--     AWD        = Amazon Warehousing & Distribution units (comes from V_UNIFIED)
--     Manufacturer = quantity_remaining_at_manufacturer from FACT_PURCHASE_ORDER
--                    (units still at factory; EXCLUDES quantity_remaining_at_shipment
--                     because those are already in Amazon's inbound_shipped)
--
--   Supply chain fields (populated on latest snapshot date only):
--     next_shipment_quantity      = total qty in next PENDING shipment per ASIN
--     next_shipment_arrival_date  = ETA of next PENDING shipment per ASIN
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_LOAD_FACT_INVENTORY_SNAPSHOT`()
BEGIN
  -- Create a temp table of dates we are loading
  CREATE TEMP TABLE _dates_to_load AS
  SELECT DISTINCT Date 
  FROM `onyga-482313.OI.V_UNIFIED_INVENTORY_SNAPSHOT`;

  -- Delete existing rows for dates that will be reloaded
  DELETE FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`
  WHERE Date IN (SELECT Date FROM _dates_to_load);

  -- Pre-compute next pending shipment per ASIN
  -- (earliest future shipment with status = PENDING)
  CREATE TEMP TABLE _next_shipment AS
  SELECT
    po.product_asin AS asin,
    MIN(s.estimated_arrival_date)  AS next_arrival_date,
    SUM(sl.quantity_shipped)       AS next_qty
  FROM `onyga-482313.OI.DE_SHIPMENT_LINES` sl
  JOIN `onyga-482313.OI.DE_PURCHASE_ORDERS` po
    ON po.purchase_order_id = sl.purchase_order_id
  JOIN `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s
    ON s.shipment_id = sl.shipment_id
  WHERE s.shipment_status = 'PENDING'
    AND s.estimated_arrival_date >= CURRENT_DATE()
  GROUP BY po.product_asin;


  -- Create a temp table for aggregated actual values
  CREATE TEMP TABLE _actual_values AS
  SELECT 
    Date, 
    ASIN, 
    SUM(quantity_balance) AS quantity_balance, 
    source_type,
    CAST(NULL AS FLOAT64) AS cogs_amount,
    CAST(NULL AS FLOAT64) AS sell_amount,
    CAST(NULL AS FLOAT64) AS paid_amount
  FROM `onyga-482313.OI.V_UNIFIED_INVENTORY_SNAPSHOT`
  GROUP BY Date, ASIN, source_type
  
  UNION ALL
  
  SELECT 
    po.snapshot_date AS Date,
    po.product_asin AS ASIN,
    SUM(COALESCE(po.quantity_remaining_at_manufacturer, 0)) AS quantity_balance,
    CASE 
      -- Use estimated_arrival_date when available
      WHEN depo.estimated_arrival_date IS NOT NULL AND po.snapshot_date < depo.estimated_arrival_date THEN 'In Production'
      WHEN depo.estimated_arrival_date IS NOT NULL AND po.snapshot_date >= depo.estimated_arrival_date THEN 'MFR Ready'
      -- Fallback: use order_date + manufacture_day from DIM_PRODUCT when no ETA is set
      WHEN depo.estimated_arrival_date IS NULL 
        AND po.snapshot_date < DATE_ADD(depo.order_date, INTERVAL COALESCE(dp.manufacture_day, 30) DAY) THEN 'In Production'
      ELSE 'MFR Ready'
    END AS source_type,
    SUM(COALESCE(po.cogs_remaining_at_manufacturer, 0)) AS cogs_amount,
    SUM(COALESCE(po.selling_price_remaining_at_manufacturer, 0)) AS sell_amount,
    SUM(COALESCE(po.cogs_remaining_at_manufacturer, 0) * LEAST(1.0, COALESCE(pay.total_paid, 0) / NULLIF(depo.total_amount, 0))) AS paid_amount
  FROM `onyga-482313.OI.FACT_PURCHASE_ORDER` po
  LEFT JOIN `onyga-482313.OI.DE_PURCHASE_ORDERS` depo
    ON po.purchase_order_id = depo.purchase_order_id
    AND po.product_asin = depo.product_asin
  LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` dp
    ON po.product_asin = dp.asin
  INNER JOIN _dates_to_load d ON po.snapshot_date = d.Date
  LEFT JOIN (
    SELECT p.purchase_order_id, d2.Date, SUM(p.payment_amount) as total_paid
    FROM `onyga-482313.OI.DE_VENDOR_PAYMENTS` p
    CROSS JOIN _dates_to_load d2
    WHERE p.shipment_id IS NULL AND p.payment_date <= d2.Date
    GROUP BY 1, 2
  ) pay
    ON po.purchase_order_id = pay.purchase_order_id AND d.Date = pay.Date
  GROUP BY 1, 2, 4;

  -- Insert data ensuring 4 rows per Date/ASIN (FBA, AWD, In Transit, Manufacturer)
  INSERT INTO `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT` (
    Date,
    ASIN,
    quantity_balance,
    source_type,
    COGS_AMOUNT,
    SELL_AMOUNT,
    PAID_AMOUNT,
    cost_of_goods,
    shipping_cost,
    factless_key,
    next_shipment_quantity,
    next_shipment_arrival_date,
    loaded_at
  )
  WITH source_types AS (
    SELECT 'FBA' AS source_type UNION ALL
    SELECT 'AWD' UNION ALL
    SELECT 'In Transit' UNION ALL
    SELECT 'MFR Ready' UNION ALL
    SELECT 'In Production'
  ),
  combos AS (
    SELECT 
      d.Date,
      p.asin AS ASIN,
      st.source_type
    FROM _dates_to_load d
    CROSS JOIN (
      SELECT asin 
      FROM `onyga-482313.OI.DIM_PRODUCT` 
      WHERE marketplace = 'ATVPDKIKX0DER'
    ) p
    CROSS JOIN source_types st
  )
  SELECT
    c.Date,
    c.ASIN,
    COALESCE(a.quantity_balance, 0) AS quantity_balance,
    c.source_type,
    
    -- Calculate COGS: use 'a.cogs_amount' if provided (Manufacturer), else fallback to standard cost
    COALESCE(
      a.cogs_amount, 
      COALESCE(a.quantity_balance, 0) * COALESCE(ch.TOTAL_COST_PER_UNIT, 0)
    ) AS COGS_AMOUNT,
    
    -- Calculate Sell Value: use 'a.sell_amount' if provided, else standard listing price
    COALESCE(
      a.sell_amount,
      COALESCE(a.quantity_balance, 0) * COALESCE(p.listing_price_amount, 0)
    ) AS SELL_AMOUNT,
    
    -- Calculate Paid Amount: use 'a.paid_amount' if provided (MFR), else assume FBA/AWD/Transit is fully paid
    COALESCE(
      a.paid_amount,
      COALESCE(a.quantity_balance, 0) * (COALESCE(ch.TOTAL_COST_PER_UNIT, 0))
    ) AS PAID_AMOUNT,
    
    ch.cost_of_goods,
    ch.shipping_cost,
    
    -- Factless Key: date_key - asin
    CONCAT(CAST(CAST(FORMAT_DATE('%Y%m%d', c.Date) AS INT64) AS STRING), '-', COALESCE(c.ASIN, 'UNKNOWN')) AS factless_key,
    
    ns.next_qty,
    ns.next_arrival_date,
    
    CURRENT_TIMESTAMP() AS loaded_at
    
  FROM combos c
  LEFT JOIN _actual_values a 
    ON c.Date = a.Date AND c.ASIN = a.ASIN AND c.source_type = a.source_type
  LEFT JOIN (
    SELECT asin, listing_price_amount 
    FROM `onyga-482313.OI.DIM_PRODUCT` 
    WHERE marketplace = 'ATVPDKIKX0DER'
  ) p ON p.asin = c.ASIN
  LEFT JOIN (
    SELECT asin, cost_of_goods, shipping_cost, TOTAL_COST_PER_UNIT,
      ROW_NUMBER() OVER (PARTITION BY asin ORDER BY start_date DESC) as rn
    FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  ) ch ON ch.asin = c.ASIN AND ch.rn = 1
  LEFT JOIN _next_shipment ns ON ns.asin = c.ASIN;

  -- Cleanup
  DROP TABLE IF EXISTS _next_shipment;
  DROP TABLE IF EXISTS _dates_to_load;
  DROP TABLE IF EXISTS _actual_values;
END;
