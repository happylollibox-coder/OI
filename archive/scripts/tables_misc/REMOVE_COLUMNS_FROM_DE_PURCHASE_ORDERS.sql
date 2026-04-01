-- =============================================
-- Remove Columns from DE_PURCHASE_ORDERS
-- =============================================
-- 
-- Removes the following columns:
--   - LAST_PAYMENT_DATE
--   - LAST_SHIPMENT_DATE
--   - LAST_ESTIMATED_ARRIVAL_DATE
--   - END_DATE
--
-- Note: BigQuery does not support DROP COLUMN directly.
-- This script recreates the table without these columns.
--
-- WARNING: This is a destructive operation. Backup first!
-- =============================================

-- Step 1: Create backup (optional but recommended)
-- CREATE TABLE `onyga-482313.OI.DE_PURCHASE_ORDERS_BACKUP_YYYYMMDD` AS
-- SELECT * FROM `onyga-482313.OI.DE_PURCHASE_ORDERS`;

-- Step 2: Create new table without the columns
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_PURCHASE_ORDERS_NEW` (
  purchase_order_id STRING NOT NULL,
  order_date DATE NOT NULL,
  manufacturer_name STRING NOT NULL,
  product_id INT64,
  product_asin STRING,
  product_name STRING,
  quantity INT64 NOT NULL,
  unit_price FLOAT64 NOT NULL,
  total_amount FLOAT64 NOT NULL,
  currency STRING DEFAULT 'USD',
  payment_status STRING DEFAULT 'PENDING',
  notes STRING,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  PRIMARY KEY (purchase_order_id) NOT ENFORCED
)
PARTITION BY order_date
CLUSTER BY manufacturer_name;

-- Step 3: Copy data from old table to new table (excluding removed columns)
INSERT INTO `onyga-482313.OI.DE_PURCHASE_ORDERS_NEW` (
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
  created_at
)
SELECT 
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
  created_at
FROM `onyga-482313.OI.DE_PURCHASE_ORDERS`;

-- Step 4: Drop old table
-- DROP TABLE `onyga-482313.OI.DE_PURCHASE_ORDERS`;

-- Step 5: Rename new table
-- ALTER TABLE `onyga-482313.OI.DE_PURCHASE_ORDERS_NEW`
-- RENAME TO `DE_PURCHASE_ORDERS`;

-- =============================================
-- Manual Steps Required:
-- =============================================
-- 1. Review the data in DE_PURCHASE_ORDERS_NEW to ensure it's correct
-- 2. Verify row counts match: 
--    SELECT COUNT(*) FROM `onyga-482313.OI.DE_PURCHASE_ORDERS`;
--    SELECT COUNT(*) FROM `onyga-482313.OI.DE_PURCHASE_ORDERS_NEW`;
-- 3. If everything looks good, uncomment Step 4 and Step 5 above
-- 4. Run Step 4 and Step 5 to complete the migration
-- =============================================
