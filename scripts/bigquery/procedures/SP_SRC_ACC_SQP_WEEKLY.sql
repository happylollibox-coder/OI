-- =============================================
-- OI Database Project - SP_SRC_ACC_SQP_WEEKLY
-- =============================================
--
-- Purpose: Upserts new SQP weekly data from the automated Daton source table.
--          Only processes ASIN/Week combinations where row counts differ from the target.
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SRC_ACC_SQP_WEEKLY`()
OPTIONS(
  description="Upserts SQP weekly data from Daton SP-API source based on row count comparison."
)
BEGIN
  DECLARE v_processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

  MERGE `onyga-482313.OI.SRC_ACC_SQP_WEEKLY` T
  USING (
    WITH SourcePartitions AS (
      SELECT endDate, asin, COUNT(*) as row_count
      FROM `daton-491514.BigQuery.amazon_selling_partner_SearchQueryPerformanceReportWeekly`
      WHERE endDate > '2026-03-21'
      GROUP BY 1, 2
    ),
    TargetPartitions AS (
      SELECT Reporting_Date, ASIN, COUNT(*) as row_count
      FROM `onyga-482313.OI.SRC_ACC_SQP_WEEKLY`
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
    FROM `daton-491514.BigQuery.amazon_selling_partner_SearchQueryPerformanceReportWeekly` d
    INNER JOIN PartitionsToUpdate p 
      ON d.endDate = p.endDate AND d.asin = p.asin
  ) S
  ON T.Reporting_Date = S.endDate 
     AND T.ASIN = S.asin 
     AND T.Search_Query = S.searchQuery
  WHEN MATCHED THEN
    UPDATE SET 
      Search_Query_Score = S.searchQueryScore,
      Search_Query_Volume = S.searchQueryVolume,
      Impressions_Total_Count = S.totalQueryImpressionCount,
      Impressions_ASIN_Count = S.asinImpressionCount,
      Impressions_ASIN_Share = S.asinImpressionShare,
      Clicks_Total_Count = S.totalClickCount,
      Clicks_Click_Rate = S.totalClickRate,
      Clicks_ASIN_Count = S.asinClickCount,
      Clicks_ASIN_Share = S.asinClickShare,
      Clicks_Price_Median = S.totalMedianClickPrice_amount,
      Clicks_ASIN_Price_Median = S.asinMedianClickPrice_amount,
      Clicks_Same_Day_Shipping_Speed = S.totalSameDayShippingClickCount,
      Clicks_1D_Shipping_Speed = S.totalOneDayShippingClickCount,
      Clicks_2D_Shipping_Speed = S.totalTwoDayShippingClickCount,
      Cart_Adds_Total_Count = S.totalCartAddCount,
      Cart_Adds_Cart_Add_Rate = S.totalCartAddRate,
      Cart_Adds_ASIN_Count = S.asinCartAddCount,
      Cart_Adds_ASIN_Share = S.asinCartAddShare,
      Cart_Adds_Price_Median = S.totalMedianCartAddPrice_amount,
      Cart_Adds_ASIN_Price_Median = S.asinMedianCartAddPrice_amount,
      Cart_Adds_Same_Day_Shipping_Speed = S.totalSameDayShippingCartAddCount,
      Cart_Adds_1D_Shipping_Speed = S.totalOneDayShippingCartAddCount,
      Cart_Adds_2D_Shipping_Speed = S.totalTwoDayShippingCartAddCount,
      Purchases_Total_Count = S.totalPurchaseCount,
      Purchases_Purchase_Rate = S.totalPurchaseRate,
      Purchases_ASIN_Count = S.asinPurchaseCount,
      Purchases_ASIN_Share = S.asinPurchaseShare,
      Purchases_Price_Median = S.totalMedianPurchasePrice_amount,
      Purchases_ASIN_Price_Median = S.asinMedianPurchasePrice_amount,
      Purchases_Same_Day_Shipping_Speed = S.totalSameDayShippingPurchaseCount,
      Purchases_1D_Shipping_Speed = S.totalOneDayShippingPurchaseCount,
      Purchases_2D_Shipping_Speed = S.totalTwoDayShippingPurchaseCount,
      source_file = 'DATON_API_AUTO',
      processed_at = v_processed_at
  WHEN NOT MATCHED THEN
    INSERT (
      Search_Query, Search_Query_Score, Search_Query_Volume,
      Impressions_Total_Count, Impressions_ASIN_Count, Impressions_ASIN_Share,
      Clicks_Total_Count, Clicks_Click_Rate, Clicks_ASIN_Count, Clicks_ASIN_Share,
      Clicks_Price_Median, Clicks_ASIN_Price_Median,
      Clicks_Same_Day_Shipping_Speed, Clicks_1D_Shipping_Speed, Clicks_2D_Shipping_Speed,
      Cart_Adds_Total_Count, Cart_Adds_Cart_Add_Rate, Cart_Adds_ASIN_Count, Cart_Adds_ASIN_Share,
      Cart_Adds_Price_Median, Cart_Adds_ASIN_Price_Median,
      Cart_Adds_Same_Day_Shipping_Speed, Cart_Adds_1D_Shipping_Speed, Cart_Adds_2D_Shipping_Speed,
      Purchases_Total_Count, Purchases_Purchase_Rate, Purchases_ASIN_Count, Purchases_ASIN_Share,
      Purchases_Price_Median, Purchases_ASIN_Price_Median,
      Purchases_Same_Day_Shipping_Speed, Purchases_1D_Shipping_Speed, Purchases_2D_Shipping_Speed,
      Reporting_Date, ASIN, source_file, processed_at
    ) VALUES (
      S.searchQuery, S.searchQueryScore, S.searchQueryVolume,
      S.totalQueryImpressionCount, S.asinImpressionCount, S.asinImpressionShare,
      S.totalClickCount, S.totalClickRate, S.asinClickCount, S.asinClickShare,
      S.totalMedianClickPrice_amount, S.asinMedianClickPrice_amount,
      S.totalSameDayShippingClickCount, S.totalOneDayShippingClickCount, S.totalTwoDayShippingClickCount,
      S.totalCartAddCount, S.totalCartAddRate, S.asinCartAddCount, S.asinCartAddShare,
      S.totalMedianCartAddPrice_amount, S.asinMedianCartAddPrice_amount,
      S.totalSameDayShippingCartAddCount, S.totalOneDayShippingCartAddCount, S.totalTwoDayShippingCartAddCount,
      S.totalPurchaseCount, S.totalPurchaseRate, S.asinPurchaseCount, S.asinPurchaseShare,
      S.totalMedianPurchasePrice_amount, S.asinMedianPurchasePrice_amount,
      S.totalSameDayShippingPurchaseCount, S.totalOneDayShippingPurchaseCount, S.totalTwoDayShippingPurchaseCount,
      S.endDate, S.asin, 'DATON_API_AUTO', v_processed_at
    );

END;
