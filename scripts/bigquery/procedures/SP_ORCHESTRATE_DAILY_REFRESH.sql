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
  -- Refresh Task 0.1: SRC_ACC_PRODUCTS (Daton → V_SRC → SRC_ACC)
  -- ============================================
  SET procedure_name = 'SP_SRC_ACC_PRODUCTS';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_SRC_ACC_PRODUCTS`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name, TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  -- ============================================
  -- Refresh Task 0.2: SRC_ACC_SALES_TRAFFIC_DAILY (Daton → V_SRC → SRC_ACC)
  -- ============================================
  SET procedure_name = 'SP_SRC_ACC_SALES_TRAFFIC';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_SRC_ACC_SALES_TRAFFIC`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name, TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  -- ============================================
  -- Refresh Task 0.3: SRC_ACC_FEE_PREVIEW (Daton → V_SRC → SRC_ACC)
  -- ============================================
  SET procedure_name = 'SP_SRC_ACC_FEE_PREVIEW';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_SRC_ACC_FEE_PREVIEW`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name, TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  -- ============================================
  -- Refresh Task 0.4: SRC_ACC_REPEAT_PURCHASE (Daton → V_SRC → SRC_ACC)
  -- ============================================
  SET procedure_name = 'SP_SRC_ACC_REPEAT_PURCHASE';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_SRC_ACC_REPEAT_PURCHASE`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name, TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

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
  -- Refresh Task 1.1: FACT_CUSTOMER_ORDER_ITEM (depends on DIM_PRODUCT)
  -- Customer-order line items: the basket-composition fact. This FACT load
  -- joins DIM_PRODUCT (parent_name, product_short_name, is_mapped_product),
  -- so it must run after Task 1 (SP_MERGE_PRODUCT_DIM_SMART) refreshes the
  -- dimension -- not merely after the Daton source loads.
  -- ============================================
  SET procedure_name = 'SP_LOAD_FACT_CUSTOMER_ORDER_ITEM';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_LOAD_FACT_CUSTOMER_ORDER_ITEM`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name, TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
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
  -- Refresh Task 2: DIM_KEYWORD (SCD2, replaces DIM_AD_keyword)
  -- ============================================
  SET procedure_name = 'SP_LOAD_DIM_KEYWORD';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_LOAD_DIM_KEYWORD`();
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
  -- Refresh Task 2.1: DIM_CAMPAIGN (SCD2)
  -- ============================================
  SET procedure_name = 'SP_LOAD_DIM_CAMPAIGN';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_LOAD_DIM_CAMPAIGN`();
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
  -- Refresh Task 2.2: DIM_AD_GROUP (SCD2)
  -- ============================================
  SET procedure_name = 'SP_LOAD_DIM_AD_GROUP';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_LOAD_DIM_AD_GROUP`();
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
  -- Refresh Task 2.2a: SP_RECORD_OBSERVED_CHANGES (depends on DIM_KEYWORD, DIM_CAMPAIGN, DIM_AD_GROUP)
  --   Added 2026-10-01 (learning-system Task B). Writes every change the three SCD2 loads above
  --   saw on Amazon (bids, states, budgets, ad-group default bids) into FACT_PPC_CHANGE_LOG as
  --   source OBSERVED, upload_status OBSERVED_ON_AMAZON, naming the logged row each one confirms.
  --   It is the only record of changes made by hand in the console. Placed right after the last
  --   DIM load so it reads the versions this pass just wrote. Idempotent; re-runs insert nothing
  --   twice. V_PPC_CHANGE_LOG_APPLIED excludes these rows, so no engine step reads them;
  --   V_CHANGE_SCORECARD grades them through V_PPC_CHANGE_LOG_LANDED.
  -- ============================================
  SET procedure_name = 'SP_RECORD_OBSERVED_CHANGES';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_RECORD_OBSERVED_CHANGES`();
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
  -- Refresh Task 2.3: DIM_LISTING_HISTORY (SCD2)
  -- ============================================
  SET procedure_name = 'SP_LOAD_DIM_LISTING_HISTORY';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_LOAD_DIM_LISTING_HISTORY`();
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
  -- Refresh Task 7.9: Auto-assign new campaigns to experiments
  -- ============================================
  SET procedure_name = 'SP_AUTO_ASSIGN_CAMPAIGNS';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_AUTO_ASSIGN_CAMPAIGNS`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name, TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
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
  -- Refresh Task 10.5: SRC_ACC_INVENTORY_FBA (Daton → V_SRC → SRC_ACC)
  -- Accumulates daily FBA inventory snapshot from Fivetran.
  -- Replaces manual file uploads to SRC_ACC_INVENTORY_FBA.
  -- ============================================
  SET procedure_name = 'SP_SRC_ACC_INVENTORY_FBA';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_SRC_ACC_INVENTORY_FBA`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name, TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  -- ============================================
  -- Refresh Task 10.6: SRC_ACC_INVENTORY_AWD (Daton → V_SRC → SRC_ACC)
  -- Accumulates daily AWD inventory snapshot from Daton.
  -- Replaces manual file uploads to SRC_ACC_INVENTORY_AWD.
  -- ============================================
  SET procedure_name = 'SP_SRC_ACC_INVENTORY_AWD';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_SRC_ACC_INVENTORY_AWD`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name, TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  -- ============================================
  -- Refresh Task 11: Inventory Snapshot (depends on SRC_ACC_INVENTORY_FBA + SRC_ACC_INVENTORY_AWD + FACT_PURCHASE_ORDER)
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
  -- Refresh Task 16.1: SP_REFRESH_SEARCH_TERM_INTENT (depends on FACT_AMAZON_ADS, DE_SEARCH_TERM_INTENT)
  --   Added 2026-09-11. Refreshes intent suggestions, rebuilds T_INTENT_CVR_CURVE and
  --   T_INTENT_BID_BASE, then chains SP_SCORE_INTENT_INDEXES (index snapshots into
  --   T_INTENT_IDX_HISTORY, scorecard, tuning grid, bounded refit of INTENT_CVR_CALIBRATION).
  --   This step is the intent learning system's ONLY schedule; it was never in the pipeline
  --   before and the evidence tables went stale. Placed right after FACT_AMAZON_ADS because
  --   every table it builds reads it. Nothing else in this pipeline reads T_INTENT_* today;
  --   the consumers are the intent popup endpoint, the month-plan generator and
  --   tools/intent_grid, which read the T_ tables for pennies.
  -- ============================================
  SET procedure_name = 'SP_REFRESH_SEARCH_TERM_INTENT';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_REFRESH_SEARCH_TERM_INTENT`();
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
  -- Refresh Task 16.6: FACT_ADS_ADVERTISED_DAILY (advertised-ASIN grain, 30-day rolling window)
  -- ============================================
  SET procedure_name = 'SP_LOAD_FACT_ADS_ADVERTISED_DAILY';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_LOAD_FACT_ADS_ADVERTISED_DAILY`(NULL);
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
  -- Refresh Task 20.4: Sync owned negative registries from our change-log (depends on FACT_PPC_CHANGE_LOG)
  -- Folds every negative we've uploaded into DE_NEGATIVE_KEYWORDS / DE_NEGATIVE_TARGETS so the coach's
  -- NEGATE offers stop re-suggesting terms already negated in Amazon (kills the "already exists" bounces).
  -- Flask also calls this live on change-log insert; this is the daily safety net for when Flask was off
  -- or an upload wasn't logged in real time. Idempotent MERGE — cheap. MUST run before the coach/cube
  -- refresh below so the fresh registry is reflected in the materialized T_WEEKLY_RUN_NEGATIVE offers.
  -- ============================================
  SET procedure_name = 'SP_SYNC_NEGATIVES';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_SYNC_NEGATIVES`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name, TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  -- ============================================
  -- Refresh Task 20.5: Materialize Ads Coach Actions (depends on FACT_AMAZON_ADS + experiments)
  -- Populates FACT_ADS_COACH_ACTIONS with 4 INSERT statements at natural grain
  -- ============================================
  SET procedure_name = 'SP_REFRESH_ADS_COACH_ACTIONS';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_REFRESH_ADS_COACH_ACTIONS`();
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
  -- Refresh Task 20.5b: Coach loop (MUST run after SP_REFRESH_ADS_COACH_ACTIONS)
  -- SP_REVIEW_WEEKLY_PLAN (plan-vs-actual → DE_WEEKLY_PLAN learnings) +
  -- SP_REFRESH_PROBE_LOG (probe 15-click/14-day budgets → DE_PROBE_LOG).
  -- Folded in 2026-08-05 from the retired 'daily_coach_loop' scheduled query, which was
  -- misconfigured (destination dataset set on a CALL script) and never ran once.
  -- Both inner SPs are absolute recomputes — idempotent at every orchestrator run.
  -- ============================================
  -- ============================================
  -- Refresh Task 20.5c: Ads restatement snapshot (Ori 2026-08-06 "find the sweet spot that
  -- data is fully refreshed"). Appends the current spend/sales for the last 16 report dates so
  -- V_ADS_SETTLE_CURVE can MEASURE how long a day keeps moving instead of us guessing.
  -- Must run AFTER SP_FACT_AMAZON_ADS so it samples the freshly-loaded values.
  -- ============================================
  SET procedure_name = 'SP_SNAPSHOT_ADS_RESTATEMENT';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_SNAPSHOT_ADS_RESTATEMENT`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  -- ============================================
  -- Refresh Task 20.5d (v27.41): Season-context verdict snapshot (depends on FACT_AMAZON_ADS).
  -- MERGEs WIN/LOSS/INSUFFICIENT per (keyword, season-context occurrence) into
  -- FACT_KEYWORD_SEASON_VERDICT for occurrences fully settled (occurrence_end <= anchor-7).
  -- Idempotent; feeds cross-occurrence memory. Spec: architecture/SEASON_CONTEXT_LEDGER.md.
  -- Drives nothing until phase-3 wiring.
  -- ============================================
  SET procedure_name = 'SP_SNAPSHOT_SEASON_VERDICT';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_SNAPSHOT_SEASON_VERDICT`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  -- ============================================
  -- Refresh Task 20.5d2 (v27.52 FIX 4): HOIST the T_PRICE_COST_TIER rebuild above the settle
  -- snapshots. DEFECT (measured 2026-08-12): T_PRICE_COST_TIER was rebuilt ONLY inside
  -- SP_REFRESH_CUBE_TABLES (Task 21, ~07:57Z) — i.e. AFTER 20.5e/20.5f (~07:46Z). Both
  -- V_PARK_REVERDICT and V_KEYWORD_GUARD compute tier-COGS GP as
  --   Ads_sales - COALESCE(T_PRICE_COST_TIER.tier_cost, FACT.TOTAL_COST_PER_UNIT) * Ads_units
  -- so the snapshots ran on YESTERDAY's tier map while the engines (V_KEYWORD_LIFT /
  -- V_OOB_KEYWORD, and every T_* the cube builds after the rebuild) ran on TODAY's. Same
  -- keyword, same day, two different settled_roas90: 213 of 606 guard rows differed and 5
  -- flipped a decision boolean daily, ALL toward under-protection (2 corroborated losers
  -- published as settled_winner; 3 catastrophic rows published as non-catastrophic, so the
  -- MANUAL_HOLD catastrophic escape could not fire).
  -- WHY A HOIST AND NOT A MOVE: 20.5e/20.5f cannot move below Task 21 — SP_REFRESH_CUBE_TABLES
  -- builds T_LIFT_PROBES (and downstream T_RUN_TARGET / T_COACH_* / T_WEEKLY_RUN_*) from
  -- V_KEYWORD_LIFT, which reads FACT_KEYWORD_GUARD + FACT_PARK_REVERDICT. Moving the snapshots
  -- after the cube would put the entire Weekly Run surface a full day behind on settle doctrine.
  -- The rebuild in SP_REFRESH_CUBE_TABLES STAYS (standalone cube refreshes need it, and it must
  -- keep preceding T_RUN_TARGET there); this is an idempotent CREATE OR REPLACE of the same
  -- 21-row map, so the second rebuild inside Task 21 is a no-op re-materialization.
  -- SAFE HERE: V_PRICE_COST_TIER reads only DIM_COSTS_HISTORY (Task 1.8), DIM_PRODUCT (Task 1)
  -- and the raw Fivetran purchased-product tables — all settled far upstream; no task between
  -- this point and Task 21 writes any of them, and none reads T_PRICE_COST_TIER expecting the
  -- previous cycle's content.
  -- NOT IN SCOPE (reported, deliberately untouched): SP_FACT_AMAZON_ADS (Task 16) also reads
  -- the previous cycle's tier map into FACT_AMAZON_ADS.TOTAL_COST_PER_UNIT — documented and
  -- accepted in that SP's header; it is only the COALESCE fallback here.
  -- ============================================
  SET procedure_name = 'REBUILD_T_PRICE_COST_TIER';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CREATE OR REPLACE TABLE `onyga-482313.OI.T_PRICE_COST_TIER` AS
      SELECT * FROM `onyga-482313.OI.V_PRICE_COST_TIER`;
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  -- ============================================
  -- Refresh Task 20.5d3 (v27.80, Ori 2026-08-17): T_CAMPAIGN_PRODUCT_SCOPE — how many of OUR OWN
  -- products each campaign advertises, and the sole ASIN when it is exactly one. Materialization
  -- of V_CAMPAIGN_PRODUCT_SCOPE (74 rows @ 2026-08-17: 67 dedicated, 7 shared doorways).
  --
  -- WHY IT IS A TABLE AND WHY IT IS BUILT HERE: V_LOW_STOCK_ADS joins it to decide
  -- serves_only_binding — "is this campaign dedicated to the variation that is running dry?" —
  -- which is what lets a dedicated campaign brake normally inside a redirect-mode family
  -- (Ori: "BALL-SP/AUTO (Mint) is auto per product ... only reduce ads by reducing the bid").
  -- V_LOW_STOCK_ADS has NO measured planning headroom: it stopped planning outright on 2026-08-17
  -- and cost the whole v27.77 repair, so inlining one more VIEW into it was never an option
  -- (fact_oi_cube_table_planner_blowup — never inline a ceiling view, read a T_ built earlier).
  --
  -- ORDER IS THE CONTRACT: this must run BEFORE anything that reads V_LOW_STOCK_ADS — Task 20.5g
  -- SP_SNAPSHOT_PANEL_OWNERSHIP (whose step 1 slices the low-stock engine into
  -- T_LOW_STOCK_CAMPAIGN) and the later SP_SNAPSHOT_ENGINE_PROPOSALS. It sits here, immediately
  -- after the T_PRICE_COST_TIER hoist, for the same reason that one does: it is a tiny idempotent
  -- CREATE OR REPLACE whose only job is to be fresh before the snapshots compile against it.
  -- A MISSING TABLE BREAKS V_LOW_STOCK_ADS OUTRIGHT (the join is not optional), so this task must
  -- never be removed while that view names it.
  -- SAFE HERE: V_CAMPAIGN_PRODUCT_SCOPE reads only V_SRC_AmazonAds_advertised_product (straight
  -- through to Fivetran, no orchestrator task writes it) and DIM_PRODUCT (Task 1, far upstream).
  -- SP ONLY — Amazon publishes no advertised-product report for Sponsored Brands, so SB/video
  -- campaigns get no row and every consumer treats a missing row as UNKNOWN, never as dedicated.
  -- Spec: architecture/LOW_STOCK_CRITERIA.md (v27.80 section).
  -- ============================================
  SET procedure_name = 'REBUILD_T_CAMPAIGN_PRODUCT_SCOPE';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CREATE OR REPLACE TABLE `onyga-482313.OI.T_CAMPAIGN_PRODUCT_SCOPE` AS
      SELECT * FROM `onyga-482313.OI.V_CAMPAIGN_PRODUCT_SCOPE`;
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  -- ============================================
  -- Refresh Task 20.5e (v27.48): Park-reverdict snapshot (depends on FACT_AMAZON_ADS, the
  -- season verdicts of 20.5d and the context gate). Materializes V_PARK_REVERDICT into
  -- FACT_PARK_REVERDICT — the settled re-judgment of every parked/STOPped/recently-revived
  -- keyword (REVIVE / CONFIRM_PARK / PENDING_SETTLE / INSUFFICIENT, calibrated revive_bid,
  -- post-revival settle veto + manual holds). BOTH engines read the snapshot, never the view
  -- (planner-ceiling doctrine). Ori's rule: "no condemnation before settle, re-judgment at
  -- settle". Spec: architecture/SEASON_CONTEXT_LEDGER.md §7.
  -- ============================================
  SET procedure_name = 'SP_SNAPSHOT_PARK_REVERDICT';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_SNAPSHOT_PARK_REVERDICT`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  -- ============================================
  -- Refresh Task 20.5f (v27.48 part 2): Keyword-guard snapshot (depends on FACT_AMAZON_ADS,
  -- the season verdicts of 20.5d, cap state and the change log; runs AFTER the park reverdict
  -- of 20.5e so both settle-doctrine snapshots share the same daily frame). Materializes
  -- V_KEYWORD_GUARD into FACT_KEYWORD_GUARD — per-instance guard signals for BOTH engines:
  -- channel-aware settled 90d record + settle_ok/settle_due (general settle veto, Cause 1),
  -- scope lifetime record + LY conv CPC (probe record caps, Cause 2), MANUAL 7d hold with
  -- catastrophic escape (Cause 3), LY-pacing raise flags + calibrated target (Cause 4).
  -- Engines read the snapshot, never the view (planner-ceiling doctrine).
  -- Spec: architecture/SEASON_CONTEXT_LEDGER.md §7.6-7.9.
  -- ============================================
  SET procedure_name = 'SP_SNAPSHOT_KEYWORD_GUARD';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_SNAPSHOT_KEYWORD_GUARD`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  -- ============================================
  -- Refresh Task 20.5g-1 (Ori 2026-08-19): Family keyword-bar snapshot. Materializes
  -- V_FAMILY_BAR into T_FAMILY_BAR, exploded to CAMPAIGN grain (88 of 97 enabled campaigns @
  -- 2026-08-19; the 9 in the map's 'Unknown' bucket get no row and therefore no bar).
  --
  -- WHY A TABLE: the bid engines V_KEYWORD_LIFT and V_OOB_KEYWORD are each AT BigQuery's planning
  -- ceiling. Inlining one more view into them is the exact move that stopped V_PANEL_OWNERSHIP
  -- planning outright on 2026-08-17 (fact_oi_cube_table_planner_blowup — never inline a ceiling
  -- view, read a T_ built earlier in the SP). The engines LEFT JOIN this TABLE on campaign_id, a
  -- key they already publish, and COALESCE(keyword_bar, 1.0) so an unmapped campaign keeps exactly
  -- today's behaviour.
  --
  -- ORDER IS THE CONTRACT: it must run BEFORE the engine T_ builds of Task 21
  -- SP_REFRESH_CUBE_TABLES so the engines compile against the bars of the run they are part of,
  -- and it sits here beside 20.5g because its inputs (V_FAMILY_PNL, V_BOOK_ASSIGNMENT,
  -- V_CAMPAIGN_FAMILY_MAP -> DIM_CAMPAIGN + FACT_AMAZON_ADS + DIM_PRODUCT) are all loaded far
  -- upstream by Tasks 1-20.4. It is a tiny idempotent CREATE OR REPLACE.
  -- Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md §4.
  -- ============================================
  SET procedure_name = 'SP_SNAPSHOT_FAMILY_BAR';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_SNAPSHOT_FAMILY_BAR`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  -- ============================================
  -- Refresh Task 20.5g (v27.62, Ori 2026-08-13): Panel-ownership snapshot — the Weekly Run
  -- single-home ladder (LOW STOCK > LAUNCH > REVIVALS > engines). Materializes
  -- V_PANEL_OWNERSHIP into FACT_PANEL_OWNERSHIP: one row per ENABLED campaign carrying which
  -- criteria owns it and, when a FULL claim exists, the defer_action / defer_reason every lower
  -- panel prints instead of a second, contradictory number.
  --
  -- ORDER: it sits HERE, beside 20.5e/20.5f, for the same two reasons they do.
  --   (a) it depends on FACT_INVENTORY_SNAPSHOT and the ads FACT load — V_PANEL_OWNERSHIP reads
  --       V_LOW_STOCK_ADS, which reads both — so it must run after them;
  --   (b) it must run BEFORE Task 21 SP_REFRESH_CUBE_TABLES, because the engine T_ builds compile
  --       against this table and must see the ownership of the run they are part of. A T_ built
  --       against yesterday's ownership would put a claimed campaign back in two panels, which is
  --       the exact defect the object exists to remove.
  -- Engines and panels read the snapshot, never the view (planner-ceiling doctrine:
  -- V_PANEL_OWNERSHIP reads V_LOW_STOCK_ADS, which is at BigQuery's planning ceiling).
  -- Spec: architecture/PANEL_OWNERSHIP.md.
  -- ============================================
  SET procedure_name = 'SP_SNAPSHOT_PANEL_OWNERSHIP';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_SNAPSHOT_PANEL_OWNERSHIP`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  SET procedure_name = 'SP_REFRESH_COACH_LOOP';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_REFRESH_COACH_LOOP`();
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
  -- Refresh Task 20.6: Materialize Research Ranking (depends on FACT_AMAZON_ADS + FACT_SEARCH_QUERY)
  -- Populates FACT_RESEARCH_TERMS + FACT_RESEARCH_RANKED for the Research page
  -- ============================================
  SET procedure_name = 'SP_REFRESH_RESEARCH_RANKED';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_REFRESH_RESEARCH_RANKED`();
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
  -- Refresh Task 20.7: Research Recommendations (depends on SP_REFRESH_RESEARCH_RANKED)
  -- Weekly top-up of FACT_RESEARCH_RECOMMENDATIONS (5 new/type/family/week)
  -- ============================================
  SET procedure_name = 'SP_REFRESH_RESEARCH_RECOMMENDATIONS';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_REFRESH_RESEARCH_RECOMMENDATIONS`();
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
  -- Refresh Task 20.4: Materialize Demand Forecast (speeds up V_PLAN_FORECAST)
  -- ============================================
  SET procedure_name = 'SP_LOAD_FACT_FORECAST_DEMAND';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_LOAD_FACT_FORECAST_DEMAND`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name, TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s (Error at %s)', procedure_name, @@error.message, CAST(CURRENT_TIMESTAMP() AS STRING)) as log_message;
  END;

  -- ============================================
  -- Refresh Task 20.5: Generate Shipment Plan (depends on V_PLAN_FORECAST → inventory + forecast)
  -- Cascading allocation: Emergency → Emergency PO → AWD Maintenance → Q4 Bulk
  -- ============================================
  SET procedure_name = 'SP_GENERATE_SHIPMENT_PLAN';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_GENERATE_SHIPMENT_PLAN`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name, TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  -- ============================================
  -- Refresh Task 21: Inventory / Plan-Drift Alerts (daily)
  -- SP_GENERATE_ALERTS — CREATE_PO / PLAN_DRIFT / AWD alerts. Was previously only
  -- triggered on-demand via /api/alerts/generate, so these alerts went stale; now daily.
  -- ============================================
  SET procedure_name = 'SP_GENERATE_ALERTS';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_GENERATE_ALERTS`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name, TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  -- ============================================
  -- Refresh Task 22: Weekly Sales Deviation Alerts (runs only on Mondays)
  -- Compares actual YTD sales pace vs yearly plan. Creates SALES_DEVIATION alerts.
  -- ============================================
  IF EXTRACT(DAYOFWEEK FROM CURRENT_DATE()) = 2 THEN  -- Monday = 2

    SET procedure_name = 'SP_GENERATE_SALES_DEVIATION_ALERTS';
    SET procedure_start_time = CURRENT_TIMESTAMP();
    SET total_procedures = total_procedures + 1;

    BEGIN
      CALL `onyga-482313.OI.SP_GENERATE_SALES_DEVIATION_ALERTS`();
      SET success_count = success_count + 1;
      SET error_msg = NULL;
      INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
        (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
      VALUES
        (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
      SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name, TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
    EXCEPTION WHEN ERROR THEN
      SET failure_count = failure_count + 1;
      SET error_msg = @@error.message;
      INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
        (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
      VALUES
        (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
      SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
    END;

  END IF;

  -- ============================================
  -- Refresh Task 20.55 (2026-08-19, Ori: "start the holdout"): the randomized holdout arms.
  -- Assigns an arm to every eligible campaign that does not already have one, and NEVER touches a
  -- unit already assigned — the procedure's only write is one append-only INSERT anti-joined
  -- against the rows already there. Running it twice writes nothing the second time.
  --
  -- ORDER IS THE CONTRACT: this must run BEFORE the proposal snapshot (20.6) and therefore before
  -- the preflight gate (20.7). The gate reads DE_HOLDOUT_ASSIGNMENT to EXCLUDE every lever on a
  -- holdout campaign, and the snapshot must record the engine's opinion about that campaign anyway
  -- — the recorded-but-blocked proposal IS the trial's counterfactual, the thing that lets the
  -- readout ask "the engine wanted to cut and the coin said don't, what happened then?". If the
  -- arms were assigned after the snapshot, a campaign's first day would be judged against no arm.
  --
  -- WHY THE TRIAL EXISTS: Ori's question ("the main goal of ads is to make more total dollars that
  -- we would do without the changes") has no observational answer on this account. Matched
  -- difference-in-differences was measured on 2026-08-18 and failed outright: a pure SELECTION
  -- placebo — emulate the engine's ranking, change nothing — reads +$1,505..+$2,445 on the losers
  -- arm, about 90% of the account's entire 14-day net, and no untouched control pool exists (73.5%
  -- of active keywords and 85.1% of ad dollars are touched; what is untouched is untouched because
  -- it is dying). So a control is created by randomization instead. The unit is the CAMPAIGN, not
  -- the keyword, because Ori's own low-stock doctrine already says a capped campaign's budget is
  -- spent regardless — holding out a keyword just re-routes its money to its treated neighbours.
  -- READ architecture/HOLDOUT.md BEFORE TOUCHING ANYTHING HERE, especially the honest limits: the
  -- trial is a HARM DETECTOR (MDE $2,261 per 14 days), not a value certifier.
  -- Spec: architecture/HOLDOUT.md.
  -- ============================================
  SET procedure_name = 'SP_ASSIGN_HOLDOUT';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_ASSIGN_HOLDOUT`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  -- ============================================
  -- Refresh Task 20.6 (2026-08-15, Ori: "i can ask you daily what was planned, what actually
  -- happened and what are your action items"): Engine-proposal snapshot — writes every live
  -- engine instruction (LIFT/OOB/LOW_STOCK/LAUNCH/REVERDICT bids, budgets, revivals) into
  -- FACT_ENGINE_PROPOSALS for today. This is the engine's memory of its own OPINIONS — the
  -- change log remembers only what was APPLIED, so without this table "did the engine call it
  -- right?" is only answerable for suggestions that happened to be uploaded, and "Ori did X
  -- where the engine said Y" (the manual-divergence doctrine) is not answerable at all.
  -- ORDER: after SP_SNAPSHOT_PANEL_OWNERSHIP (the engines' deferrals read it) and after the
  -- coach refresh (the launch ladder reads the coach), before Task 21 — so the snapshot records
  -- the same opinions today's panels will show. Read by V_DAILY_BRIEF.
  -- Spec: architecture/DAILY_BRIEF.md.
  -- ============================================
  SET procedure_name = 'SP_SNAPSHOT_ENGINE_PROPOSALS';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_SNAPSHOT_ENGINE_PROPOSALS`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  -- ============================================
  -- Refresh Task 20.7 (2026-08-15, engine-finalization Task 1.1): the standing contradiction
  -- gate. Judges the proposal snapshot Task 20.6 just wrote — single owner per (campaign,
  -- keyword, lever) with precedence LOW_STOCK > LAUNCH > OOB > REVERDICT > LIFT, no-ops out,
  -- settled-winner cuts and >$2 bids to REVIEW — writing T_ENGINE_PREFLIGHT and stamping
  -- verdict/verdict_reason back onto FACT_ENGINE_PROPOSALS. Reads ONLY snapshot tables, runs in
  -- seconds. First run: 149 instructions -> 97 GO / 44 EXCLUDE / 8 REVIEW — a 29.5% contradiction
  -- rate, the same magnitude the one-off iteration-6 audit found, which is the whole argument for
  -- a STANDING gate. DoPage.exportBulksheet refuses EXCLUDE rows at export time.
  -- Spec: architecture/ENGINE_PREFLIGHT.md.
  -- ============================================
  SET procedure_name = 'SP_ENGINE_PREFLIGHT';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_ENGINE_PREFLIGHT`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  -- ============================================
  -- Refresh Task 20.8 (2026-08-16, engine-finalization Task 2.1): the keyword state machine —
  -- one row per (campaign, keyword) with state / owner / next appointment, assembled purely from
  -- the other snapshots' verdicts (guard, reverdict, panel ownership, today's preflight, change
  -- log). Two standing invariants (one state per keyword; no keyword without a next appointment,
  -- DEAD exempt) — V_ENGINE_HEALTH reads them. AFTER 20.7 so PACED_WINNER and the REVIVE-today
  -- appointment reflect the same day's instructions the panels show.
  -- Spec: architecture/KEYWORD_STATE.md.
  -- ============================================
  SET procedure_name = 'SP_SNAPSHOT_KEYWORD_STATE';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  -- ============================================
  -- Refresh Task 20.8a (2026-08-24, THREE_LAYERS violation 6): THE CATALOG KEEPS ITS MEMORY.
  -- Task 20.8 above is a CREATE OR REPLACE TABLE — every pass it destroys a day of the ladder's
  -- verdicts, permanently and unrecoverably. THREE_LAYERS.md §6.2: "a layer cannot be graded on
  -- predictions it does not keep"; §1.4: a layer needs "durable, queryable state of its own" a
  -- caller can read "directly AND HISTORICALLY"; §10.4 names dwell time — how long has this been
  -- stuck — as the single highest-value thing to fix first, because its absence obstructs the
  -- measurement of every other violation. This step appends the snapshot 20.8 just built into
  -- FACT_KEYWORD_STATE_HISTORY before anything can overwrite it.
  -- IMMEDIATELY AFTER 20.8 and before every reader below, so the memory can never lag the day.
  -- IT CHANGES NOTHING. It copies a table that was already written into a table no engine,
  -- generator, book or bulksheet reads. It writes nothing any other task consults and cannot move
  -- a bid, a budget or a pause. Every step below sees exactly what it would have seen without it.
  -- IT CANNOT BREAK THE PASS. The procedure is guarded internally (a missing or empty snapshot is
  -- a no-op, never an emptied partition) and wrapped here in the house exception handler, so a
  -- failure logs FAIL to LOG_PIPELINE_RUNS and the pass carries straight on to 20.8b.
  -- IDEMPOTENT ON A DOUBLE CALL, which the house assumes (SP_REFRESH_CUBE_TABLES already calls
  -- SP_MAINTAIN_FAMILY_SEATS a second time each pass): it INSERTs the whole snapshot stamped with
  -- this run's captured_at and then PRUNEs any snapshot_date carrying more than one captured_at
  -- down to its newest stamp — append-first, so a crash between the two can only leave a duplicate,
  -- never a lost day. Two passes on one snapshot_date leave one copy. The prune is keyed on the
  -- history's OWN duplicate stamps, not on the dates the live snapshot happens to carry, and runs
  -- before the append as well as after, so a strand on ANY date is repaired by ANY later call
  -- (v27.144 — the old date-scoped prune could never reach a strand left on the last pass of an LA
  -- day, because every later pass carried a different date).
  -- IT WILL NOT RESTAMP A BUILD THE HISTORY ALREADY HOLDS (v27.145). Task 20.8 above has its own
  -- exception handler, so a pass where the snapshot build FAILED still reaches this task with the
  -- previous build's table standing. Copying it again would move that partition's captured_at and
  -- give it a source_detail naming a read time at which the Catalog said nothing new. GUARD 3
  -- refuses it, and the test is on the BUILD rather than on the calendar: the procedure compares
  -- the snapshot table's own last-modified clock against the stamp the history already carries for
  -- that date, and a build that has not moved has nothing to add. The first shape of the guard
  -- asked only whether the date was older than the current LA date, which left it blind for the
  -- whole of the day it was running in — and since snapshot_date is CURRENT_DATE('America/
  -- Los_Angeles') while several passes run each night, sharing one LA date is the normal case, not
  -- an edge one. A snapshot carrying a date the history does NOT hold is still appended — that is
  -- memory gained, not provenance rewritten. Every row now records snapshot_built_at, so which
  -- build a partition came from is part of the memory rather than an assumption about it.
  -- Spec: architecture/THREE_LAYERS.md §8 violation 6, §10.4. SOP: architecture/KEYWORD_STATE.md.
  -- ============================================
  SET procedure_name = 'SP_APPEND_KEYWORD_STATE_HISTORY';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_APPEND_KEYWORD_STATE_HISTORY`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  -- ============================================
  -- Refresh Task 20.8b (2026-08-22, family seat register Task 1): the seat ledger. Reads the
  -- keyword-state snapshot Task 20.8 just wrote and keeps DE_FAMILY_SEAT_LEDGER honest for the
  -- WORKING families (HARVEST book): closes seats whose keyword left the occupant set (with a
  -- reason), admits new occupants at the family's lowest free seat number, never touches a
  -- continuing occupant. Idempotent on the same snapshot. No engine reads the ledger; the
  -- register (V_FAMILY_SEAT_REGISTER) reads it for seat numbers only.
  -- Spec: architecture/FAMILY_SEAT_REGISTER.md.
  -- ============================================
  SET procedure_name = 'SP_MAINTAIN_FAMILY_SEATS';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_MAINTAIN_FAMILY_SEATS`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;


  -- ============================================
  -- Refresh Task 20.8c (2026-08-23, next week's money Task 2): the plan. Reads the keyword-state
  -- snapshot (20.8) through V_PLAN_WINDOW_JUDGMENT and the seat ledger (20.8b), and writes today's
  -- partition of FACT_PLAN_NEXT_WEEK — both plans, every night (spec P-9). MUST run after 20.8b,
  -- because a continuing occupant's seat number comes from the ledger that step maintains, and
  -- after 20.8, whose snapshot the judgement view reads.
  -- IT ALSO ARMS TWO RULINGS. The judgement view reads this table back as the plan's MEMORY: the
  -- live rows' `side` becomes the P-14b guard's "was good" (the ladder is only the bootstrap for a
  -- keyword the plan has never seen), and `verdict = 'GRACE'` spends P-5's one quiet window. Until
  -- this step ran for the first time both memories were absent and grace was a permanent exemption.
  -- ONE PASS OF LAG, DELIBERATE AND MEASURED: the proposal snapshot (Task 20.6) and the preflight
  -- (20.7) run EARLIER in this pass than the keyword state machine (20.8) does — that ordering
  -- predates this plan and is not changed here. So the PLAN rows a given pass writes are read by
  -- the NEXT pass's proposal snapshot, exactly as the ladder's own snapshot is already read a pass
  -- late by everything below it. Closing the lag means moving 20.6 and 20.7 below 20.8c, which is a
  -- change to another owner's ordering — recorded as an open ruling for Ori, not taken here.
  -- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md. SOP: architecture/NEXT_WEEK_MONEY.md §3.
  -- ============================================

  SET procedure_name = 'SP_BUILD_NEXT_WEEK_PLAN';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;


  -- ============================================
  -- Refresh Task 20.8d (2026-08-25, plan step 5, THREE_LAYERS §6.0): THE BRAIN KEEPS ITS LEDGER.
  -- Task 20.8c above DELETEs and rewrites today's FACT_PLAN_NEXT_WEEK partition every pass, so the
  -- click target step 4 put on a seat is gone by tomorrow. A window that closes on 2026-09-08 has
  -- had every promise behind it overwritten a dozen times, and §6.0's grading would have nothing to
  -- grade against. This step copies the funded seats into FACT_SEAT_REQUEST, which is append-only.
  -- It is the same shape as Task 20.8a and exists for the same reason violation 6 did.
  -- MUST RUN IMMEDIATELY AFTER 20.8c and before anything below reads the plan, so the ledger can
  -- never lag the day it records.
  -- APPEND-THEN-PRUNE, so the failure mode leaves a duplicate the next call removes rather than a
  -- lost promise; the prune runs on entry as well as exit, keyed on the LEDGER's own duplicate
  -- stamps, so a strand on any date is healed by any later call including a manual one.
  -- It records what 20.8c already decided. It decides nothing, is read by nothing, and can move no
  -- bid, budget or pause. A failure here logs FAIL and the pass carries straight on.
  -- ============================================

  SET procedure_name = 'SP_APPEND_SEAT_REQUEST';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_APPEND_SEAT_REQUEST`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

  -- ============================================
  -- Refresh Task 20.8e: Record what the Catalog claimed tonight (FACT_CATALOG_FORECAST)
  -- Runs after 20.8d, and after the family bar (Task ~14) and keyword state (Task 20.7) it reads.
  -- WITHOUT THIS THE CATALOG CANNOT BE GRADED AT ALL. V_CATALOG_FORECAST is a live view over
  -- CREATE-OR-REPLACE snapshots, so tomorrow it answers from tomorrow's data and tonight's
  -- prediction is gone -- the actuals survive and the forecast does not, which makes the per-link
  -- scoring THREE_LAYERS.md §2.0.1 asks for impossible. This is the Catalog's memory.
  -- APPEND-THEN-PRUNE, so a crash leaves a duplicate the next call removes rather than a lost
  -- claim; the prune runs on entry as well as exit, keyed on the LEDGER's own duplicate stamps.
  -- It records what the Catalog already computed. It decides nothing, is read by nothing that
  -- acts, and can move no bid, budget or pause. A failure logs FAIL and the pass carries on.
  -- ============================================

  SET procedure_name = 'SP_APPEND_CATALOG_FORECAST';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_APPEND_CATALOG_FORECAST`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
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
