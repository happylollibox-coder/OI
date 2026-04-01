-- =============================================
-- OI Database Project - SP_ORCHESTRATE_DAILY_REFRESH
-- =============================================
--
-- Purpose: Master orchestrator that runs all daily refresh procedures in dependency order.
--          Each task is wrapped in BEGIN...EXCEPTION to ensure one failure does not stop the pipeline.
--
-- Execution order (layers):
--   DIM  -> SRC/SRC_ACC -> STG -> FACT -> Analytics -> Financial
--
-- Schedule: Daily via BigQuery Scheduled Query (see setup_daily_orchestrator.sql)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_ORCHESTRATE_DAILY_REFRESH`()
OPTIONS (
  description = "Master daily refresh orchestrator. Runs all DIM, SRC_ACC, STG, FACT procedures in dependency order. Logs results to LOG_PIPELINE_RUNS."
)
BEGIN
  DECLARE overall_start_time TIMESTAMP;
  DECLARE procedure_start_time TIMESTAMP;
  DECLARE procedure_name STRING;
  DECLARE success_count INT64 DEFAULT 0;
  DECLARE failure_count INT64 DEFAULT 0;
  DECLARE total_procedures INT64 DEFAULT 0;
  DECLARE run_id STRING;
  DECLARE error_msg STRING DEFAULT NULL;

  SET overall_start_time = CURRENT_TIMESTAMP();
  SET run_id = GENERATE_UUID();

  SELECT FORMAT(
    'SP_ORCHESTRATE_DAILY_REFRESH: Starting run %s at %s',
    run_id,
    CAST(overall_start_time AS STRING)
  ) as log_message;

  -- ============================================
  -- Refresh Task 1: PRODUCT_DIM
  -- ============================================
  SET procedure_name = 'SP_MERGE_PRODUCT_DIM_SMART';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_MERGE_PRODUCT_DIM_SMART`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 1.5: REMOVED - STG_PRODUCT_COST_DATA dropped on 2026-02-22.
  -- Cost data now sourced from DE_PURCHASE_ORDERS via SP_MERGE_PRODUCT_DIM.
  -- ============================================

  -- ============================================
  -- Refresh Task 1.8: DIM_COSTS_HISTORY SCD2 (depends on DIM_PRODUCT cost fields)
  -- ============================================
  SET procedure_name = 'SP_LOAD_DIM_COSTS_HISTORY';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_LOAD_DIM_COSTS_HISTORY`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 2: DIM_AD_keyword
  -- ============================================
  SET procedure_name = 'SP_LOAD_DIM_AD_keyword';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_LOAD_DIM_AD_keyword`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 5.5: Auto SQP & SCP Daton Uploads (SRC -> SRC_ACC)
  -- Replaces SP_PROCESS_MANUAL_UPLOADS
  -- ============================================
  SET procedure_name = 'SP_SRC_ACC_SQP_WEEKLY';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_SRC_ACC_SQP_WEEKLY`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  SET procedure_name = 'SP_SRC_ACC_SCP_WEEKLY';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_SRC_ACC_SCP_WEEKLY`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 6: SCP Weekly Data (OpenBridge)
  -- ============================================
  SET procedure_name = 'SP_MERGE_SCP_WEEKLY';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_MERGE_SCP_WEEKLY`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 7: SQP Weekly Data (OpenBridge)
  -- ============================================
  SET procedure_name = 'SP_MERGE_SQP_WEEKLY';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_MERGE_SQP_WEEKLY`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 7.5: SRC_ACC_AmazonAds_purchased_product (accumulate from view, preserve 1d)
  -- ============================================
  SET procedure_name = 'SP_ACC_AmazonAds_purchased_product';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_ACC_AmazonAds_purchased_product`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 7.8: GENERAL_CONVERSION ad URL ASIN merge (SB ad data)
  -- ============================================
  SET procedure_name = 'SP_MERGE_GENERAL_CONVERSION_AD_URL_ASIN';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_MERGE_GENERAL_CONVERSION_AD_URL_ASIN`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 8: FACT_SEARCH_QUERY (reads from SRC_ACC_SQP_WEEKLY + STG_SCP_WEEKLY)
  -- ============================================
  SET procedure_name = 'SP_LOAD_FACT_SEARCH_QUERY';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_LOAD_FACT_SEARCH_QUERY`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 5: Currency Rates
  -- ============================================
  SET procedure_name = 'SP_UPDATE_CURRENCY_RATES';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_UPDATE_CURRENCY_RATES`(
      CURRENT_DATE(),  -- start_date
      CURRENT_DATE(),  -- end_date
      FALSE            -- is_historical_load
    );
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 10: Data Entry Updates (Purchase Orders)
  -- ============================================
  SET procedure_name = 'SP_DATA_ENTRY_UPDATES';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_DATA_ENTRY_UPDATES`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 11: Inventory Snapshot (depends on FACT_PURCHASE_ORDER)
  -- ============================================
  SET procedure_name = 'SP_LOAD_FACT_INVENTORY_SNAPSHOT';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_LOAD_FACT_INVENTORY_SNAPSHOT`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 12: STG_AMAZON_PERFORMANCE (before STG_AMAZON_ADS)
  -- ============================================
  SET procedure_name = 'SP_LOAD_STG_AMAZON_PERFORMANCE';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_LOAD_STG_AMAZON_PERFORMANCE`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 13: STG_AmazonAds_purchased_product (depends on SRC_ACC_AmazonAds_purchased_product)
  -- ============================================
  SET procedure_name = 'SP_AmazonAds_purchased_product';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_AmazonAds_purchased_product`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 14: STG_AMAZON_ADS
  -- ============================================
  SET procedure_name = 'SP_LOAD_STG_AMAZON_ADS';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_LOAD_STG_AMAZON_ADS`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 14.5: STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY (depends on SRC_ACC_SQP_WEEKLY and SRC_ACC_SCP_WEEKLY)
  -- ============================================
  SET procedure_name = 'SP_LOAD_STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_LOAD_STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 14.8: COMPARE_QUANTITY_CLICKS_BY_ASIN (depends on STG_AMAZON_ADS)
  -- ============================================
  SET procedure_name = 'SP_LOAD_COMPARE_QUANTITY_CLICKS_BY_ASIN';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_LOAD_COMPARE_QUANTITY_CLICKS_BY_ASIN`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 15: FACT_AMAZON_PERFORMANCE_DAILY (depends on STG_AMAZON_PERFORMANCE, STG_AmazonAds_purchased_product)
  -- REPLACED: SP_AMAZON_PERFORMANCE_DAILY -> SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY (newer version)
  -- ============================================
  SET procedure_name = 'SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 16: FACT_AMAZON_ADS (depends on STG_AMAZON_ADS)
  -- ============================================
  SET procedure_name = 'SP_FACT_AMAZON_ADS';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_FACT_AMAZON_ADS`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 16.5: FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY (depends on STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY)
  -- ============================================
  SET procedure_name = 'SP_LOAD_FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_LOAD_FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 16.6: Accumulate Brand Phrases (depends on FACT_AMAZON_ADS)
  -- ============================================
  SET procedure_name = 'SP_ACCUMULATE_BRAND_PHRASES';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_ACCUMULATE_BRAND_PHRASES`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 16.7: Auto-Link Pending Experiment Campaigns (before snapshot)
  -- ============================================
  SET procedure_name = 'SP_AUTO_LINK_EXPERIMENT_CAMPAIGNS';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_AUTO_LINK_EXPERIMENT_CAMPAIGNS`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 16.8: Experiment Daily Snapshot (depends on FACT_AMAZON_ADS + FACT_AMAZON_PERFORMANCE_DAILY)
  -- ============================================
  SET procedure_name = 'SP_EXPERIMENT_DAILY_SNAPSHOT';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_EXPERIMENT_DAILY_SNAPSHOT`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 16.9: ASIN Conclusions (depends on FACT_EXPERIMENT_DAILY + DIM_COSTS_HISTORY)
  -- ============================================
  SET procedure_name = 'SP_UPDATE_ASIN_CONCLUSIONS';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_UPDATE_ASIN_CONCLUSIONS`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 17: Factless Fact Bridge (depends on all fact tables)
  -- ============================================
  SET procedure_name = 'SP_POPULATE_FACTLESS_BRIDGE';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_POPULATE_FACTLESS_BRIDGE`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 17.2: Experiment Weekly Review (WEEKLY - runs on Mondays only)
  -- Generates experiment recommendations from completed experiments
  -- ============================================
  IF EXTRACT(DAYOFWEEK FROM CURRENT_DATE()) = 2 THEN
    SET procedure_name = 'SP_EXPERIMENT_WEEKLY_REVIEW';
    SET procedure_start_time = CURRENT_TIMESTAMP();
    SET total_procedures = total_procedures + 1;

    BEGIN
      CALL `onyga-482313.OI.SP_EXPERIMENT_WEEKLY_REVIEW`();
      SET success_count = success_count + 1;
      SELECT FORMAT(
        'OK %s completed successfully in %d seconds',
        procedure_name,
        TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
      ) as log_message;
    EXCEPTION WHEN ERROR THEN
      SET failure_count = failure_count + 1;
      SELECT FORMAT(
        'FAIL %s failed: %s (Error at %s)',
        procedure_name,
        @@error.message,
        CAST(CURRENT_TIMESTAMP() AS STRING)
      ) as log_message;
    END;
  END IF;

  -- ============================================
  -- Refresh Task 17.5: DIM_TIME Traffic Multipliers (WEEKLY - runs on Mondays only)
  -- Updates DIM_TIME with traffic multiplier columns from V_TRAFFIC_MULTIPLIER_WEEKLY
  -- ============================================
  IF EXTRACT(DAYOFWEEK FROM CURRENT_DATE()) = 2 THEN
    SET procedure_name = 'SP_UPDATE_DIM_TIME_TRAFFIC_MULTIPLIERS';
    SET procedure_start_time = CURRENT_TIMESTAMP();
    SET total_procedures = total_procedures + 1;

    BEGIN
      CALL `onyga-482313.OI.SP_UPDATE_DIM_TIME_TRAFFIC_MULTIPLIERS`();
      SET success_count = success_count + 1;
      SELECT FORMAT(
        'OK %s completed successfully in %d seconds',
        procedure_name,
        TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
      ) as log_message;
    EXCEPTION WHEN ERROR THEN
      SET failure_count = failure_count + 1;
      SELECT FORMAT(
        'FAIL %s failed: %s (Error at %s)',
        procedure_name,
        @@error.message,
        CAST(CURRENT_TIMESTAMP() AS STRING)
      ) as log_message;
    END;
  END IF;

  -- ============================================
  -- Refresh Task 18: Bank Uploads Processing (MERGE SRC to SRC_ACC, prevents duplicates)
  -- ============================================
  SET procedure_name = 'SP_PROCESS_BANK_UPLOADS';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_PROCESS_BANK_UPLOADS`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 19: STG_UNIFIED_TRANSACTION_SOURCES (depends on bank views)
  -- ============================================
  SET procedure_name = 'SP_STG_UNIFIED_TRANSACTION_SOURCES';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_STG_UNIFIED_TRANSACTION_SOURCES`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 20: FACT_FINANCIAL_TRANSACTIONS (depends on STG_UNIFIED_TRANSACTION_SOURCES)
  -- ============================================
  SET procedure_name = 'SP_FACT_FINANCIAL_TRANSACTIONS';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_FACT_FINANCIAL_TRANSACTIONS`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Refresh Task 21: Refresh Cube Tables (T_*)
  -- Convert all Cube-facing V_* logical views into physical T_* snapshot tables
  -- ============================================
  SET procedure_name = 'SP_REFRESH_CUBE_TABLES';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_REFRESH_CUBE_TABLES`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'OK %s completed successfully in %d seconds',
      procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)
    ) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT(
      'FAIL %s failed: %s (Error at %s)',
      procedure_name,
      @@error.message,
      CAST(CURRENT_TIMESTAMP() AS STRING)
    ) as log_message;
  END;

  -- ============================================
  -- Final Summary
  -- ============================================
  SELECT FORMAT(
    '====================================================================\n' ||
    'SP_ORCHESTRATE_DAILY_REFRESH: COMPLETED\n' ||
    '====================================================================\n' ||
    'Total Procedures: %d\n' ||
    'Successful: %d\n' ||
    'Failed: %d\n' ||
    'Total Duration: %d seconds\n' ||
    'Completed at: %s\n' ||
    '====================================================================',
    total_procedures,
    success_count,
    failure_count,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), overall_start_time, SECOND),
    CAST(CURRENT_TIMESTAMP() AS STRING)
  ) as orchestration_summary;
END;
