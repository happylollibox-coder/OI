-- =============================================
-- OI Database Project - DE_VENDOR_PAYMENTS Table
-- =============================================
-- Ultra-lean table for payments
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.DE_VENDOR_PAYMENTS` (
  payment_id STRING NOT NULL,
  purchase_order_id STRING NOT NULL,
  payment_date DATE NOT NULL,
  payment_amount FLOAT64 NOT NULL,
  bank_fee FLOAT64,
  currency STRING DEFAULT 'USD',
  payment_method STRING,
  vendor_name STRING NOT NULL,
  notes STRING,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  
  PRIMARY KEY (payment_id) NOT ENFORCED
)
PARTITION BY payment_date
CLUSTER BY vendor_name;
