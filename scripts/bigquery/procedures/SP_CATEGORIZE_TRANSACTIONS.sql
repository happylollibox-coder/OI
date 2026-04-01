-- =============================================
-- OI Database Project - SP_CATEGORIZE_TRANSACTIONS Stored Procedure
-- =============================================
--
-- Purpose: Stored procedure to categorize transactions using lookup rules
-- Applies categorization rules in priority order and assigns budget categories
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_CATEGORIZE_TRANSACTIONS`(
  source_table_name STRING,
  target_table_name STRING
)
OPTIONS (
  description = "Categorize transactions from source table and insert into target table with budget categories"
)
BEGIN
  -- Declare variables
  DECLARE query STRING;

  -- Build dynamic query to categorize transactions
  SET query = FORMAT("""
    INSERT INTO `%s` (
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
    WITH categorized_transactions AS (
      -- Apply categorization rules in priority order
      SELECT
        t.transaction_date,
        t.amount,
        t.currency,
        t.transaction_description,
        t.transaction_type,
        t.source_system,
        t.source_transaction_id,
        t.account_name,
        t.payment_direction,
        t.transaction_category,
        t.payment_source,
        t.transaction_year,
        t.transaction_month,
        t.transaction_day,
        t.source_metadata,
        t.processed_at,
        t.data_source_file,

        -- Apply first matching categorization rule (by priority)
        COALESCE(
          FIRST_VALUE(c.subcategory_name IGNORE NULLS) OVER (
            PARTITION BY t.transaction_date, t.source_transaction_id, t.source_system
            ORDER BY r.priority ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
          ),
          'Uncategorized Transactions'
        ) as budget_subcategory,

        COALESCE(
          FIRST_VALUE(c.category_name IGNORE NULLS) OVER (
            PARTITION BY t.transaction_date, t.source_transaction_id, t.source_system
            ORDER BY r.priority ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
          ),
          'UNKNOWN'
        ) as budget_category,

        COALESCE(
          FIRST_VALUE(c.subcategory_id IGNORE NULLS) OVER (
            PARTITION BY t.transaction_date, t.source_transaction_id, t.source_system
            ORDER BY r.priority ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
          ),
          9901
        ) as subcategory_id,

        COALESCE(
          FIRST_VALUE(c.is_recurring IGNORE NULLS) OVER (
            PARTITION BY t.transaction_date, t.source_transaction_id, t.source_system
            ORDER BY r.priority ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
          ),
          FALSE
        ) as is_recurring,

        COALESCE(
          FIRST_VALUE(c.budget_confidence IGNORE NULLS) OVER (
            PARTITION BY t.transaction_date, t.source_transaction_id, t.source_system
            ORDER BY r.priority ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
          ),
          'LOW'
        ) as budget_confidence,

        COALESCE(
          FIRST_VALUE(c.forecast_multiplier IGNORE NULLS) OVER (
            PARTITION BY t.transaction_date, t.source_transaction_id, t.source_system
            ORDER BY r.priority ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
          ),
          1.0
        ) as forecast_multiplier

      FROM `%s` t
      LEFT JOIN `onyga-482313.OI.CFG_TRANSACTION_CATEGORIZATION_RULES` r
        ON (r.source_system_filter IS NULL OR r.source_system_filter = t.source_system)
        AND (r.description_pattern IS NULL OR REGEXP_CONTAINS(t.transaction_description, r.description_pattern))
        AND (r.amount_min IS NULL OR t.amount >= r.amount_min)
        AND (r.amount_max IS NULL OR t.amount <= r.amount_max)
        AND (r.currency_filter IS NULL OR r.currency_filter = t.currency)
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
      transaction_year,
      transaction_month,
      transaction_day,
      source_metadata,
      processed_at,
      data_source_file
    FROM categorized_transactions
    GROUP BY
      transaction_date, amount, currency, transaction_description, transaction_type,
      source_system, source_transaction_id, account_name, payment_direction,
      transaction_category, budget_category, budget_subcategory, subcategory_id,
      is_recurring, budget_confidence, forecast_multiplier, payment_source,
      transaction_year, transaction_month, transaction_day, source_metadata,
      processed_at, data_source_file
  """, target_table_name, source_table_name);

  -- Execute the dynamic query
  EXECUTE IMMEDIATE(query);

  -- Log completion
  SELECT FORMAT('Successfully categorized transactions from %s into %s', source_table_name, target_table_name) as status;
END;
