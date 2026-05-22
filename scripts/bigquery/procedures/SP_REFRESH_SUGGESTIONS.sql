-- SP_REFRESH_SUGGESTIONS: On-demand refresh of all Plan page dependencies
-- Runs only the supply-chain-relevant SPs in correct dependency order
-- so that shipment suggestions are computed from fully fresh data.
--
-- Execution order:
--   1. SP_MERGE_PRODUCT_DIM_SMART    — refresh DIM_PRODUCT (stock levels, costs, manufacturing days)
--   2. SP_SRC_ACC_INVENTORY_FBA      — accumulate latest FBA inventory from Daton
--   3. SP_SRC_ACC_INVENTORY_AWD      — accumulate latest AWD inventory from Daton
--   4. SP_LOAD_FACT_INVENTORY_SNAPSHOT — build today's inventory snapshot from FBA + AWD + MFR
--   5. SP_LOAD_FACT_FORECAST_DEMAND  — materialize demand forecast (feeds V_PLAN_FORECAST)
--   6. SP_GENERATE_SHIPMENT_PLAN     — generate SUGGESTED rows in DE_SCHEDULED_SHIPMENTS
--
-- Triggered by: Admin page "Refresh Suggestions" button
-- Typical runtime: ~3-8 minutes

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_REFRESH_SUGGESTIONS`()
OPTIONS (
  description = "On-demand refresh of Plan page supply chain data. Refreshes DIM_PRODUCT, inventory snapshot, demand forecast, and generates shipment suggestions."
)
BEGIN
  DECLARE step_start TIMESTAMP;
  DECLARE step_name STRING;
  DECLARE step_count INT64 DEFAULT 0;
  DECLARE ok_count INT64 DEFAULT 0;
  DECLARE fail_count INT64 DEFAULT 0;
  DECLARE t0 TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

  -- ============================================
  -- Step 1: Refresh DIM_PRODUCT
  -- Ensures latest product attributes, costs, manufacturing days, oi_is_active flag
  -- ============================================
  SET step_name = 'SP_MERGE_PRODUCT_DIM_SMART';
  SET step_start = CURRENT_TIMESTAMP();
  SET step_count = step_count + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_MERGE_PRODUCT_DIM_SMART`();
    SET ok_count = ok_count + 1;
    SELECT FORMAT('OK [%d/%d] %s (%ds)', step_count, 6, step_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), step_start, SECOND)) AS log_message;
  EXCEPTION WHEN ERROR THEN
    SET fail_count = fail_count + 1;
    SELECT FORMAT('FAIL [%d/%d] %s: %s', step_count, 6, step_name, @@error.message) AS log_message;
  END;

  -- ============================================
  -- Step 2: Accumulate FBA inventory (Daton → SRC_ACC)
  -- ============================================
  SET step_name = 'SP_SRC_ACC_INVENTORY_FBA';
  SET step_start = CURRENT_TIMESTAMP();
  SET step_count = step_count + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_SRC_ACC_INVENTORY_FBA`();
    SET ok_count = ok_count + 1;
    SELECT FORMAT('OK [%d/%d] %s (%ds)', step_count, 6, step_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), step_start, SECOND)) AS log_message;
  EXCEPTION WHEN ERROR THEN
    SET fail_count = fail_count + 1;
    SELECT FORMAT('FAIL [%d/%d] %s: %s', step_count, 6, step_name, @@error.message) AS log_message;
  END;

  -- ============================================
  -- Step 3: Accumulate AWD inventory (Daton → SRC_ACC)
  -- ============================================
  SET step_name = 'SP_SRC_ACC_INVENTORY_AWD';
  SET step_start = CURRENT_TIMESTAMP();
  SET step_count = step_count + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_SRC_ACC_INVENTORY_AWD`();
    SET ok_count = ok_count + 1;
    SELECT FORMAT('OK [%d/%d] %s (%ds)', step_count, 6, step_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), step_start, SECOND)) AS log_message;
  EXCEPTION WHEN ERROR THEN
    SET fail_count = fail_count + 1;
    SELECT FORMAT('FAIL [%d/%d] %s: %s', step_count, 6, step_name, @@error.message) AS log_message;
  END;

  -- ============================================
  -- Step 4: Build inventory snapshot (FBA + AWD + MFR → FACT_INVENTORY_SNAPSHOT)
  -- ============================================
  SET step_name = 'SP_LOAD_FACT_INVENTORY_SNAPSHOT';
  SET step_start = CURRENT_TIMESTAMP();
  SET step_count = step_count + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_LOAD_FACT_INVENTORY_SNAPSHOT`();
    SET ok_count = ok_count + 1;
    SELECT FORMAT('OK [%d/%d] %s (%ds)', step_count, 6, step_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), step_start, SECOND)) AS log_message;
  EXCEPTION WHEN ERROR THEN
    SET fail_count = fail_count + 1;
    SELECT FORMAT('FAIL [%d/%d] %s: %s', step_count, 6, step_name, @@error.message) AS log_message;
  END;

  -- ============================================
  -- Step 5: Materialize demand forecast (V_FORECAST_DEMAND → FACT_FORECAST_DEMAND)
  -- ============================================
  SET step_name = 'SP_LOAD_FACT_FORECAST_DEMAND';
  SET step_start = CURRENT_TIMESTAMP();
  SET step_count = step_count + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_LOAD_FACT_FORECAST_DEMAND`();
    SET ok_count = ok_count + 1;
    SELECT FORMAT('OK [%d/%d] %s (%ds)', step_count, 6, step_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), step_start, SECOND)) AS log_message;
  EXCEPTION WHEN ERROR THEN
    SET fail_count = fail_count + 1;
    SELECT FORMAT('FAIL [%d/%d] %s: %s', step_count, 6, step_name, @@error.message) AS log_message;
  END;

  -- ============================================
  -- Step 6: Generate shipment suggestions (cascading allocation engine)
  -- ============================================
  SET step_name = 'SP_GENERATE_SHIPMENT_PLAN';
  SET step_start = CURRENT_TIMESTAMP();
  SET step_count = step_count + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_GENERATE_SHIPMENT_PLAN`();
    SET ok_count = ok_count + 1;
    SELECT FORMAT('OK [%d/%d] %s (%ds)', step_count, 6, step_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), step_start, SECOND)) AS log_message;
  EXCEPTION WHEN ERROR THEN
    SET fail_count = fail_count + 1;
    SELECT FORMAT('FAIL [%d/%d] %s: %s', step_count, 6, step_name, @@error.message) AS log_message;
  END;

  -- ============================================
  -- Summary
  -- ============================================
  SELECT FORMAT(
    'SP_REFRESH_SUGGESTIONS: %d/%d OK, %d FAILED, total %ds',
    ok_count, step_count, fail_count,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), t0, SECOND)
  ) AS summary;
END;
