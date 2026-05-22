-- =============================================
-- OI Database Project - SRC_ACC_REPEAT_PURCHASE Table
-- =============================================
--
-- Purpose: Permanent accumulation table for repeat purchase behavior data
-- Source: V_SRC_Seller_repeat_purchase (Daton RepeatPurchaseBehaviourReport)
-- Pattern: MERGE (incremental)
-- Project: onyga-482313
-- Dataset: OI
-- Created: 2026-04-03
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.SRC_ACC_REPEAT_PURCHASE` (
  asin STRING NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  marketplace_id STRING,
  orders INT64,
  unique_customers INT64,
  repeat_customers_pct_total NUMERIC,
  repeat_purchase_revenue_amount NUMERIC,
  repeat_purchase_revenue_currency_code STRING,
  -- Metadata
  source_file STRING DEFAULT 'DATON_API_AUTO',
  processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (asin, start_date, end_date) NOT ENFORCED
)
PARTITION BY DATE_TRUNC(start_date, YEAR)
CLUSTER BY asin, start_date
OPTIONS (
  description = "Permanent accumulation table for repeat purchase behavior data. Loaded by SP_SRC_ACC_REPEAT_PURCHASE from V_SRC_Seller_repeat_purchase."
);
