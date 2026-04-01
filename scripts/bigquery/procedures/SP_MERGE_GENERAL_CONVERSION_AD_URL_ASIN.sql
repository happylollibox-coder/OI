-- =============================================
-- OI Database Project - SP_MERGE_GENERAL_CONVERSION_AD_URL_ASIN
-- =============================================
--
-- Purpose: Merge distinct AD_Advertised_ID values from V_SRC_AmazonAds_sb_ad_report
--          into GENERAL_CONVERSION table with list_of_values = 'ad_URL_ASIN'
--          AD_Advertised_ID uses custom_image_url if available, otherwise campaign_name|ad_group_name
-- Project: onyga-482313
-- Dataset: OI
--
-- Logic:
-- 1. Extract distinct AD_Advertised_ID from V_SRC_AmazonAds_sb_ad_report
--    - AD_Advertised_ID = custom_image_url if not empty, otherwise campaign_name|ad_group_name
-- 2. MERGE into GENERAL_CONVERSION with:
--    - list_of_values = 'ad_URL_ASIN'
--    - SOURCE = 'AMAZON_ADS_SB'
--    - key = AD_Advertised_ID
--    - target = 'Unknown' (to be populated manually or via ASIN extraction)
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_MERGE_GENERAL_CONVERSION_AD_URL_ASIN`()
OPTIONS (
  description = "Merge distinct AD_Advertised_ID values from V_SRC_AmazonAds_sb_ad_report into GENERAL_CONVERSION table with list_of_values = 'ad_URL_ASIN'. AD_Advertised_ID uses custom_image_url if available, otherwise campaign_name|ad_group_name."
)
BEGIN
  -- Declare variables for logging
  DECLARE records_inserted INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- MERGE distinct AD_Advertised_ID values into GENERAL_CONVERSION
  MERGE `onyga-482313.OI.GENERAL_CONVERSION` AS gc
  USING (
    SELECT DISTINCT
      AD_Advertised_ID
    FROM `onyga-482313.OI.V_SRC_AmazonAds_sb_ad_report`
    WHERE AD_Advertised_ID IS NOT NULL
      AND AD_Advertised_ID != ''
  ) AS source_data
  ON gc.list_of_values = 'ad_URL_ASIN'
    AND gc.SOURCE = 'AMAZON_ADS_SB'
    AND gc.`key` = source_data.AD_Advertised_ID
  WHEN NOT MATCHED THEN
    INSERT (
      conversion_id,
      list_of_values,
      SOURCE,
      `key`,
      target,
      Target_AI,
      example,
      transaction_count,
      transaction_sum,
      C_TARGET,
      date_inserted,
      updated_at
    )
    VALUES (
      CAST(FARM_FINGERPRINT(CONCAT('ad_URL_ASIN|AMAZON_ADS_SB|', source_data.AD_Advertised_ID)) AS INT64),
      'ad_URL_ASIN',
      'AMAZON_ADS_SB',
      source_data.AD_Advertised_ID,
      'Unknown',  -- ASIN to be populated manually or via extraction
      NULL,  -- Target_AI can be used for ASIN extraction suggestions
      NULL,  -- Example field for reference
      0,  -- transaction_count (not applicable for this conversion type)
      0.0,  -- transaction_sum (not applicable for this conversion type)
      NULL,  -- C_TARGET will be calculated when target is set
      CURRENT_TIMESTAMP(),
      CURRENT_TIMESTAMP()
    );

  SET records_inserted = @@row_count;

  -- Log the operation results
  SELECT FORMAT(
    'SP_MERGE_GENERAL_CONVERSION_AD_URL_ASIN completed:\n' ||
    '  New records inserted: %d\n' ||
    '  Duration: %d seconds\n' ||
    '  Completed at: %s',
    records_inserted,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND),
    CAST(CURRENT_TIMESTAMP() AS STRING)
  ) as operation_summary;
END;
