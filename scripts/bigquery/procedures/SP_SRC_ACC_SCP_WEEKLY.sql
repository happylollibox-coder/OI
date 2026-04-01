-- =============================================
-- OI Database Project - SP_SRC_ACC_SCP_WEEKLY
-- =============================================
--
-- Purpose: Upserts new SCP weekly data from the automated Daton source table.
--          Only processes ASIN/Week combinations where row counts differ from the target.
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SRC_ACC_SCP_WEEKLY`()
OPTIONS(
  description="Upserts SCP weekly data from Daton SP-API source based on row count comparison."
)
BEGIN
  DECLARE v_processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

  MERGE `onyga-482313.OI.SRC_ACC_SCP_WEEKLY` T
  USING (
    WITH SourcePartitions AS (
      SELECT endDate, asin, COUNT(*) as row_count
      FROM `daton-491514.BigQuery.amazon_selling_partner_SearchCatalogPerformanceReportWeekly`
      WHERE endDate > '2026-03-21'
      GROUP BY 1, 2
    ),
    TargetPartitions AS (
      SELECT Reporting_Date, ASIN, COUNT(*) as row_count
      FROM `onyga-482313.OI.SRC_ACC_SCP_WEEKLY`
      WHERE Reporting_Date > '2026-03-21'
      GROUP BY 1, 2
    ),
    PartitionsToUpdate AS (
      SELECT s.endDate, s.asin
      FROM SourcePartitions s
      LEFT JOIN TargetPartitions t 
        ON s.endDate = t.Reporting_Date AND s.asin = t.ASIN
      WHERE t.Reporting_Date IS NULL 
         OR s.row_count != t.row_count
    )
    SELECT d.* 
    FROM `daton-491514.BigQuery.amazon_selling_partner_SearchCatalogPerformanceReportWeekly` d
    INNER JOIN PartitionsToUpdate p 
      ON d.endDate = p.endDate AND d.asin = p.asin
  ) S
  ON T.Reporting_Date = S.endDate 
     AND T.ASIN = S.asin 
  WHEN MATCHED THEN
    UPDATE SET 
      Impressions_Impressions = S.impressionCount,
      Impressions_Price_Median = S.impressionMedianPrice_amount,
      Impressions_Same_Day_Shipping_Speed = S.sameDayShippingImpressionCount,
      Impressions_1D_Shipping_Speed = S.oneDayShippingImpressionCount,
      Impressions_2D_Shipping_Speed = S.twoDayShippingImpressionCount,
      Clicks_Clicks = S.clickCount,
      Clicks_Click_Rate_CTR = S.clickRate,
      Clicks_Price_Median = S.clickedMedianPrice_amount,
      Clicks_Same_Day_Shipping_Speed = S.sameDayShippingClickCount,
      Clicks_1D_Shipping_Speed = S.oneDayShippingClickCount,
      Clicks_2D_Shipping_Speed = S.twoDayShippingClickCount,
      Cart_Adds_Cart_Adds = S.cartAddCount,
      Cart_Adds_Price_Median = S.cartAddedMedianPrice_amount,
      Cart_Adds_Same_Day_Shipping_Speed = S.sameDayShippingCartAddCount,
      Cart_Adds_1D_Shipping_Speed = S.oneDayShippingCartAddCount,
      Cart_Adds_2D_Shipping_Speed = S.twoDayShippingCartAddCount,
      Purchases_Purchases = S.purchaseCount,
      Purchases_Search_Traffic_Sales = S.searchTrafficSales_amount,
      Purchases_Conversion_Rate = S.conversionRate,
      Purchases_Price_Median = S.purchaseMedianPrice_amount,
      Purchases_Same_Day_Shipping_Speed = S.sameDayShippingPurchaseCount,
      Purchases_1D_Shipping_Speed = S.oneDayShippingPurchaseCount,
      Purchases_2D_Shipping_Speed = S.twoDayShippingPurchaseCount,
      source_file = 'DATON_API_AUTO',
      processed_at = v_processed_at
  WHEN NOT MATCHED THEN
    INSERT (
      Reporting_Date, ASIN,
      Impressions_Impressions, Impressions_Price_Median,
      Impressions_Same_Day_Shipping_Speed, Impressions_1D_Shipping_Speed, Impressions_2D_Shipping_Speed,
      Clicks_Clicks, Clicks_Click_Rate_CTR, Clicks_Price_Median,
      Clicks_Same_Day_Shipping_Speed, Clicks_1D_Shipping_Speed, Clicks_2D_Shipping_Speed,
      Cart_Adds_Cart_Adds, Cart_Adds_Price_Median,
      Cart_Adds_Same_Day_Shipping_Speed, Cart_Adds_1D_Shipping_Speed, Cart_Adds_2D_Shipping_Speed,
      Purchases_Purchases, Purchases_Search_Traffic_Sales, Purchases_Conversion_Rate,
      Purchases_Price_Median,
      Purchases_Same_Day_Shipping_Speed, Purchases_1D_Shipping_Speed, Purchases_2D_Shipping_Speed,
      source_file, processed_at
    ) VALUES (
      S.endDate, S.asin,
      S.impressionCount, S.impressionMedianPrice_amount,
      S.sameDayShippingImpressionCount, S.oneDayShippingImpressionCount, S.twoDayShippingImpressionCount,
      S.clickCount, S.clickRate, S.clickedMedianPrice_amount,
      S.sameDayShippingClickCount, S.oneDayShippingClickCount, S.twoDayShippingClickCount,
      S.cartAddCount, S.cartAddedMedianPrice_amount,
      S.sameDayShippingCartAddCount, S.oneDayShippingCartAddCount, S.twoDayShippingCartAddCount,
      S.purchaseCount, S.searchTrafficSales_amount, S.conversionRate,
      S.purchaseMedianPrice_amount,
      S.sameDayShippingPurchaseCount, S.oneDayShippingPurchaseCount, S.twoDayShippingPurchaseCount,
      'DATON_API_AUTO', v_processed_at
    );

END;
