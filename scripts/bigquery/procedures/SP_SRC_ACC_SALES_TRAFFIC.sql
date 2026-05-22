-- =============================================
-- OI Database Project - SP_SRC_ACC_SALES_TRAFFIC
-- =============================================
--
-- Purpose: Load SRC_ACC_SALES_TRAFFIC_DAILY from V_SRC_sales_and_traffic
-- Pattern: MERGE by child_asin + date (incremental, large table)
-- Source: V_SRC_sales_and_traffic_business_sku_report_daily
-- Project: onyga-482313
-- Dataset: OI
-- Created: 2026-04-03
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SRC_ACC_SALES_TRAFFIC`()
OPTIONS (
  description = "Load SRC_ACC_SALES_TRAFFIC_DAILY from V_SRC_sales_and_traffic. MERGE by child_asin + date."
)
BEGIN
  DECLARE v_processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE merge_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  MERGE `onyga-482313.OI.SRC_ACC_SALES_TRAFFIC_DAILY` T
  USING (
    SELECT
      child_asin, date, marketplace_id, parent_asin, sku,
      SALES_QUANTITY, SALES_AMOUNT, SALES_CURRENCY, SALES_ORDERS,
      asin_sessions, page_views
    FROM `onyga-482313.OI.V_SRC_sales_and_traffic_business_sku_report_daily`
  ) S
  ON T.child_asin = S.child_asin AND T.date = S.date
  WHEN MATCHED THEN
    UPDATE SET
      marketplace_id = S.marketplace_id,
      parent_asin = S.parent_asin,
      sku = S.sku,
      SALES_QUANTITY = S.SALES_QUANTITY,
      SALES_AMOUNT = S.SALES_AMOUNT,
      SALES_CURRENCY = S.SALES_CURRENCY,
      SALES_ORDERS = S.SALES_ORDERS,
      asin_sessions = S.asin_sessions,
      page_views = S.page_views,
      source_file = 'DATON_API_AUTO',
      processed_at = v_processed_at
  WHEN NOT MATCHED THEN
    INSERT (
      child_asin, date, marketplace_id, parent_asin, sku,
      SALES_QUANTITY, SALES_AMOUNT, SALES_CURRENCY, SALES_ORDERS,
      asin_sessions, page_views, source_file, processed_at
    ) VALUES (
      S.child_asin, S.date, S.marketplace_id, S.parent_asin, S.sku,
      S.SALES_QUANTITY, S.SALES_AMOUNT, S.SALES_CURRENCY, S.SALES_ORDERS,
      S.asin_sessions, S.page_views, 'DATON_API_AUTO', v_processed_at
    );

  SELECT FORMAT(
    'SP_SRC_ACC_SALES_TRAFFIC completed. Duration: %d seconds',
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND)
  ) as operation_summary;
END;
