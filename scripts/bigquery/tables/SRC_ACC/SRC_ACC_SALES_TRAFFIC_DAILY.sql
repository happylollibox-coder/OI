-- =============================================
-- OI Database Project - SRC_ACC_SALES_TRAFFIC_DAILY Table
-- =============================================
--
-- Purpose: Permanent accumulation table for daily sales and traffic data
-- Source: V_SRC_sales_and_traffic_business_sku_report_daily
-- Pattern: MERGE (incremental, large table)
-- Project: onyga-482313
-- Dataset: OI
-- Created: 2026-04-03
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.SRC_ACC_SALES_TRAFFIC_DAILY` (
  child_asin STRING NOT NULL,
  date DATE NOT NULL,
  marketplace_id STRING,
  parent_asin STRING,
  sku STRING,
  SALES_QUANTITY INT64,
  SALES_AMOUNT NUMERIC,
  SALES_CURRENCY STRING,
  SALES_ORDERS INT64,
  asin_sessions INT64,
  page_views INT64,
  -- Metadata
  source_file STRING DEFAULT 'DATON_API_AUTO',
  processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (child_asin, date) NOT ENFORCED
)
PARTITION BY DATE_TRUNC(date, YEAR)
CLUSTER BY child_asin, date
OPTIONS (
  description = "Permanent accumulation table for daily sales and traffic data. Loaded by SP_SRC_ACC_SALES_TRAFFIC from V_SRC_sales_and_traffic_business_sku_report_daily."
);
