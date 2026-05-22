-- =============================================
-- OI Database Project - SP_SRC_ACC_REPEAT_PURCHASE
-- =============================================
--
-- Purpose: Load SRC_ACC_REPEAT_PURCHASE from V_SRC_Seller_repeat_purchase
-- Pattern: MERGE by asin + start_date + end_date (incremental)
-- Source: V_SRC_Seller_repeat_purchase (Daton RepeatPurchaseBehaviourReport)
-- Project: onyga-482313
-- Dataset: OI
-- Created: 2026-04-03
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SRC_ACC_REPEAT_PURCHASE`()
OPTIONS (
  description = "Load SRC_ACC_REPEAT_PURCHASE from V_SRC_Seller_repeat_purchase. MERGE by asin + start_date + end_date."
)
BEGIN
  DECLARE v_processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE start_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  MERGE `onyga-482313.OI.SRC_ACC_REPEAT_PURCHASE` T
  USING (
    SELECT
      asin, start_date, end_date, marketplace_id, orders,
      unique_customers, repeat_customers_pct_total,
      repeat_purchase_revenue_amount, repeat_purchase_revenue_currency_code
    FROM `onyga-482313.OI.V_SRC_Seller_repeat_purchase`
  ) S
  ON T.asin = S.asin AND T.start_date = S.start_date AND T.end_date = S.end_date
  WHEN MATCHED THEN
    UPDATE SET
      marketplace_id = S.marketplace_id,
      orders = S.orders,
      unique_customers = S.unique_customers,
      repeat_customers_pct_total = S.repeat_customers_pct_total,
      repeat_purchase_revenue_amount = S.repeat_purchase_revenue_amount,
      repeat_purchase_revenue_currency_code = S.repeat_purchase_revenue_currency_code,
      source_file = 'DATON_API_AUTO',
      processed_at = v_processed_at
  WHEN NOT MATCHED THEN
    INSERT (
      asin, start_date, end_date, marketplace_id, orders,
      unique_customers, repeat_customers_pct_total,
      repeat_purchase_revenue_amount, repeat_purchase_revenue_currency_code,
      source_file, processed_at
    ) VALUES (
      S.asin, S.start_date, S.end_date, S.marketplace_id, S.orders,
      S.unique_customers, S.repeat_customers_pct_total,
      S.repeat_purchase_revenue_amount, S.repeat_purchase_revenue_currency_code,
      'DATON_API_AUTO', v_processed_at
    );

  SELECT FORMAT(
    'SP_SRC_ACC_REPEAT_PURCHASE completed. Duration: %d seconds',
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND)
  ) as operation_summary;
END;
