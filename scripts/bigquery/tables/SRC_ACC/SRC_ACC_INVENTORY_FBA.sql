-- Accumulation table for FBA Inventory data
-- Same schema as SRC_INVENTORY_FBA plus insert_date and insert_file_name

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.SRC_ACC_INVENTORY_FBA` (
  Date DATE,
  FNSKU STRING,
  ASIN STRING,
  MSKU STRING,
  Title STRING,
  Disposition STRING,
  `Starting Warehouse Balance` INT64,
  `In Transit Between Warehouses` INT64,
  Receipts INT64,
  `Customer Shipments` INT64,
  `Customer Returns` INT64,
  `Vendor Returns` INT64,
  `Warehouse Transfer In_Out` INT64,
  Found INT64,
  Lost INT64,
  Damaged INT64,
  Disposed INT64,
  `Other Events` INT64,
  `Ending Warehouse Balance` INT64,
  `Unknown Events` INT64,
  Location STRING,
  Store STRING,
  -- Additional fields for tracking
  insert_date TIMESTAMP NOT NULL,
  insert_file_name STRING NOT NULL
)
PARTITION BY DATE_TRUNC(Date, MONTH)
CLUSTER BY FNSKU, Date;
