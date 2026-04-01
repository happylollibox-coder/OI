-- =============================================
-- OI Database Project - SP_ACCUMULATE_FINANCIAL_TRANSACTIONS Stored Procedure
-- =============================================
--
-- Purpose: Accumulate categorized transactions into FACT_FINANCIAL_TRANSACTIONS
-- Checks for existing records and only inserts new/updated transactions
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_ACCUMULATE_FINANCIAL_TRANSACTIONS`()
OPTIONS (
  description = "Accumulate categorized transactions from staging into fact table"
)
BEGIN
  -- Declare variables for logging
  DECLARE processed_count INT64;
  DECLARE start_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- Insert new transactions from staging table into fact table
  -- Only insert records that don't already exist (based on the primary key combination)
  INSERT INTO `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS` (
    transaction_date,
    amount,
    currency,
    transaction_description,
    transaction_type,
    source_system,
    source_transaction_id,
    account_name,
    payment_direction,
    transaction_category,
    budget_category,
    budget_subcategory,
    subcategory_id,
    is_recurring,
    budget_confidence,
    forecast_multiplier,
    payment_source,
    transaction_year,
    transaction_month,
    transaction_day,
    source_metadata,
    processed_at,
    data_source_file
  )
  WITH categorized_staging AS (
    -- Apply categorization rules to staging data
    SELECT
      stg.transaction_date,
      stg.amount,
      stg.currency,
      stg.transaction_description,
      stg.transaction_type,
      stg.source_system,
      stg.source_transaction_id,
      stg.account_name,
      stg.source_metadata,
      stg.processed_at,
      stg.data_source_file,

      -- Apply first matching categorization rule (by priority)
      COALESCE(
        FIRST_VALUE(c.subcategory_name IGNORE NULLS) OVER (
          PARTITION BY stg.transaction_date, stg.source_transaction_id, stg.source_system
          ORDER BY r.priority ASC
          ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ),
        'Uncategorized Transactions'
      ) as budget_subcategory,

      COALESCE(
        FIRST_VALUE(c.category_name IGNORE NULLS) OVER (
          PARTITION BY stg.transaction_date, stg.source_transaction_id, stg.source_system
          ORDER BY r.priority ASC
          ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ),
        'UNKNOWN'
      ) as budget_category,

      COALESCE(
        FIRST_VALUE(c.subcategory_id IGNORE NULLS) OVER (
          PARTITION BY stg.transaction_date, stg.source_transaction_id, stg.source_system
          ORDER BY r.priority ASC
          ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ),
        9901
      ) as subcategory_id,

      COALESCE(
        FIRST_VALUE(c.is_recurring IGNORE NULLS) OVER (
          PARTITION BY stg.transaction_date, stg.source_transaction_id, stg.source_system
          ORDER BY r.priority ASC
          ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ),
        FALSE
      ) as is_recurring,

      COALESCE(
        FIRST_VALUE(c.budget_confidence IGNORE NULLS) OVER (
          PARTITION BY stg.transaction_date, stg.source_transaction_id, stg.source_system
          ORDER BY r.priority ASC
          ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ),
        'LOW'
      ) as budget_confidence,

      COALESCE(
        FIRST_VALUE(c.forecast_multiplier IGNORE NULLS) OVER (
          PARTITION BY stg.transaction_date, stg.source_transaction_id, stg.source_system
          ORDER BY r.priority ASC
          ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ),
        1.0
      ) as forecast_multiplier,

      -- Default values for fields not in staging
      'UNKNOWN' as payment_direction,
      'OTHER' as transaction_category,
      'OTHER' as payment_source

    FROM `onyga-482313.OI.STG_UNIFIED_TRANSACTION_SOURCES` stg
    LEFT JOIN `onyga-482313.OI.CFG_TRANSACTION_CATEGORIZATION_RULES` r
      ON (r.source_system_filter IS NULL OR r.source_system_filter = stg.source_system)
      AND (r.description_pattern IS NULL OR REGEXP_CONTAINS(stg.transaction_description, r.description_pattern))
      AND (r.amount_min IS NULL OR stg.amount >= r.amount_min)
      AND (r.amount_max IS NULL OR stg.amount <= r.amount_max)
      AND (r.currency_filter IS NULL OR r.currency_filter = stg.currency)
      AND r.is_active = TRUE
    LEFT JOIN `onyga-482313.OI.DIM_BUDGET_CATEGORIES` c
      ON r.target_subcategory_id = c.subcategory_id
  )
  SELECT
    transaction_date,
    amount,
    currency,
    transaction_description,
    transaction_type,
    source_system,
    source_transaction_id,
    account_name,
    payment_direction,
    transaction_category,
    budget_category,
    budget_subcategory,
    subcategory_id,
    is_recurring,
    budget_confidence,
    forecast_multiplier,
    payment_source,
    EXTRACT(YEAR FROM transaction_date) as transaction_year,
    EXTRACT(MONTH FROM transaction_date) as transaction_month,
    EXTRACT(DAY FROM transaction_date) as transaction_day,
    source_metadata,
    processed_at,
    data_source_file
  FROM categorized_staging cs
  WHERE NOT EXISTS (
    -- Check if this combination already exists in the fact table
    SELECT 1
    FROM `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS` ft
    WHERE ft.source_system = cs.source_system
      AND ft.source_transaction_id = cs.source_transaction_id
      AND ft.transaction_date = cs.transaction_date
  );

  SET processed_count = @@row_count;

  -- Log the operation results
  SELECT FORMAT(
    'FACT_FINANCIAL_TRANSACTIONS accumulation completed: Processed %d new transactions, Duration: %d seconds',
    processed_count,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND)
  ) as operation_summary;
END;