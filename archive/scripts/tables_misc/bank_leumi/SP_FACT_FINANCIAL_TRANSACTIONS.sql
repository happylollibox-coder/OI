-- =============================================
-- OI Database Project - SP_FACT_FINANCIAL_TRANSACTIONS Stored Procedure
-- =============================================
--
-- Purpose: Process and accumulate financial transactions into FACT table
-- Handles GENERAL_CONVERSION lookups and currency conversions
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_FACT_FINANCIAL_TRANSACTIONS`()
OPTIONS (
  description = "Process staging transactions into fact table with conversions and currency rates"
)
BEGIN
  -- Declare variables for logging
  DECLARE account_conversions_added INT64;
  DECLARE payment_src_conversions_added INT64;
  DECLARE transactions_merged INT64;
  DECLARE start_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- ==========================================
  -- STEP 1: Populate GENERAL_CONVERSION table
  -- ==========================================

  -- 1.1: Add Account-Nick-Name conversions
  INSERT INTO `onyga-482313.OI.GENERAL_CONVERSION` (
    conversion_id,
    list_of_values,
    SOURCE,
    `key`,
    target,
    example,
    transaction_count,
    transaction_sum,
    C_TARGET,
    date_inserted
  )
  SELECT
    CAST(FARM_FINGERPRINT(CONCAT('Account-Nick-Name|', distinct_accounts.source_system, '|', distinct_accounts.account_name)) AS INT64) as conversion_id,
    'Account-Nick-Name' as list_of_values,
    distinct_accounts.source_system as SOURCE,
    distinct_accounts.account_name as `key`,
    'Unknown' as target,
    NULL as example,
    0 as transaction_count,
    0.0 as transaction_sum,
    NULL as C_TARGET,  -- Will be calculated later
    CURRENT_TIMESTAMP() as date_inserted
  FROM (
    SELECT DISTINCT
      source_system,
      account_name
    FROM `onyga-482313.OI.STG_UNIFIED_TRANSACTION_SOURCES`
  ) distinct_accounts
  WHERE NOT EXISTS (
    SELECT 1
    FROM `onyga-482313.OI.GENERAL_CONVERSION` gc
    WHERE gc.list_of_values = 'Account-Nick-Name'
      AND gc.SOURCE = distinct_accounts.source_system
      AND gc.`key` = distinct_accounts.account_name
  );

  SET account_conversions_added = @@row_count;

  -- 1.2: Add payment_source conversions (maps transaction_description to payment_source)
  -- For BANK_LEUMI_FOREIGN and BANK_LEUMI_ILS: include account_name as part of SOURCE
  -- When 1 row becomes 2 rows (different account_names), all other columns copy same values
  INSERT INTO `onyga-482313.OI.GENERAL_CONVERSION` (
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
    date_inserted
  )
  SELECT
    CAST(FARM_FINGERPRINT(CONCAT('payment_source|', 
      CASE 
        WHEN distinct_sources.source_system IN ('BANK_LEUMI_FOREIGN', 'BANK_LEUMI_ILS') 
        THEN CONCAT(distinct_sources.source_system, '|', distinct_sources.account_name)
        ELSE distinct_sources.source_system
      END, 
      '|', distinct_sources.transaction_description)) AS INT64) as conversion_id,
    'payment_source' as list_of_values,
    CASE 
      WHEN distinct_sources.source_system IN ('BANK_LEUMI_FOREIGN', 'BANK_LEUMI_ILS') 
      THEN CONCAT(distinct_sources.source_system, '|', distinct_sources.account_name)
      ELSE distinct_sources.source_system
    END as SOURCE,
    distinct_sources.transaction_description as `key`,
    COALESCE(existing_gc.target, 'Unknown') as target,  -- Copy existing target if row exists
    existing_gc.Target_AI as Target_AI,  -- Copy existing Target_AI if row exists (NULL if new row)
    COALESCE(existing_gc.example, CAST(distinct_sources.amount AS STRING)) as example,  -- Copy existing example or use amount
    0 as transaction_count,
    0.0 as transaction_sum,
    COALESCE(existing_gc.C_TARGET, 
      CASE 
        WHEN existing_gc.target != 'Unknown' THEN existing_gc.target 
        ELSE existing_gc.Target_AI 
      END
    ) as C_TARGET,  -- Copy existing C_TARGET, or calculate from target/Target_AI if exists
    CURRENT_TIMESTAMP() as date_inserted
  FROM (
    SELECT DISTINCT
      source_system,
      account_name,
      transaction_description,
      FIRST_VALUE(amount) OVER (
        PARTITION BY 
          source_system,
          CASE WHEN source_system IN ('BANK_LEUMI_FOREIGN', 'BANK_LEUMI_ILS') THEN account_name ELSE NULL END,
          transaction_description
        ORDER BY transaction_date DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
      ) as amount
    FROM `onyga-482313.OI.STG_UNIFIED_TRANSACTION_SOURCES`
  ) distinct_sources
  -- Left join to existing GENERAL_CONVERSION to copy values when splitting rows by account_name
  -- This ensures when 1 row becomes 2 rows (different account_names), all other columns have same values
  -- Match on key (transaction_description) only to find the most common/recent value across all accounts
  LEFT JOIN (
    SELECT DISTINCT
      `key`,
      FIRST_VALUE(target) OVER (PARTITION BY `key` ORDER BY CASE WHEN target != 'Unknown' THEN 0 ELSE 1 END, date_inserted DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as target,
      FIRST_VALUE(Target_AI) OVER (PARTITION BY `key` ORDER BY CASE WHEN Target_AI IS NOT NULL THEN 0 ELSE 1 END, date_inserted DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as Target_AI,
      FIRST_VALUE(C_TARGET) OVER (PARTITION BY `key` ORDER BY CASE WHEN C_TARGET IS NOT NULL AND C_TARGET != target THEN 0 ELSE 1 END, date_inserted DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as C_TARGET,
      FIRST_VALUE(example) OVER (PARTITION BY `key` ORDER BY date_inserted DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as example
    FROM `onyga-482313.OI.GENERAL_CONVERSION`
    WHERE list_of_values = 'payment_source'
      AND `key` IS NOT NULL
  ) existing_gc
    ON existing_gc.`key` = distinct_sources.transaction_description
    AND distinct_sources.source_system IN ('BANK_LEUMI_FOREIGN', 'BANK_LEUMI_ILS')  -- Only for BANK_LEUMI sources
  WHERE NOT EXISTS (
    SELECT 1
    FROM `onyga-482313.OI.GENERAL_CONVERSION` gc
    WHERE gc.list_of_values = 'payment_source'
      AND gc.SOURCE = CASE 
        WHEN distinct_sources.source_system IN ('BANK_LEUMI_FOREIGN', 'BANK_LEUMI_ILS') 
        THEN CONCAT(distinct_sources.source_system, '|', distinct_sources.account_name)
        ELSE distinct_sources.source_system
      END
      AND gc.`key` = distinct_sources.transaction_description
  );

  SET payment_src_conversions_added = @@row_count;

  -- 1.3: Update Target_AI for payment_source conversions where target = 'Unknown'
  -- Extract merchant/provider name from transaction description
  -- IMPORTANT: This logic ONLY applies to list_of_values = 'payment_source'
  -- If no value can be extracted, defaults to 'Uncategorized Transactions'
  -- Examples:
  --   "Card charge (10WEB.IO)" → "10WEB.IO"
  --   "Card charge (CANVA* I04180-18852903)" → "CANVA"
  --   "Card charge (CANVA* I04545-22740479)" → "CANVA"
  --   Other descriptions → "Uncategorized Transactions"
  MERGE `onyga-482313.OI.GENERAL_CONVERSION` AS gc
  USING (
    SELECT
      conversion_id,
      COALESCE(
        NULLIF(
          TRIM(
            CASE
              -- Extract content within parentheses
              WHEN REGEXP_CONTAINS(gc_inner.`key`, r'\([^)]+\)') THEN
                CASE
                  -- If extracted content contains asterisk, get everything before asterisk
                  WHEN REGEXP_CONTAINS(REGEXP_EXTRACT(gc_inner.`key`, r'\(([^)]+)\)'), r'\*') THEN
                    REGEXP_EXTRACT(REGEXP_EXTRACT(gc_inner.`key`, r'\(([^)]+)\)'), r'^([^*]+)')
                  -- Otherwise, use the whole extracted content
                  ELSE
                    REGEXP_EXTRACT(gc_inner.`key`, r'\(([^)]+)\)')
                END
              -- If no parentheses but contains asterisk, extract everything before asterisk
              WHEN REGEXP_CONTAINS(gc_inner.`key`, r'\*') THEN
                REGEXP_EXTRACT(gc_inner.`key`, r'^([^*]+)')
              ELSE NULL
            END
          ),
          ''
        ),
        'Uncategorized Transactions'
      ) as extracted_merchant
    FROM `onyga-482313.OI.GENERAL_CONVERSION` gc_inner
    WHERE gc_inner.list_of_values = 'payment_source'  -- ONLY payment_source
      AND gc_inner.target = 'Unknown'
      AND gc_inner.`key` IS NOT NULL
  ) AS suggestions
  ON gc.conversion_id = suggestions.conversion_id
    AND gc.list_of_values = 'payment_source'  -- Ensure only payment_source rows are matched
  WHEN MATCHED THEN
    UPDATE SET
      Target_AI = suggestions.extracted_merchant,  -- Always set (never NULL)
      C_TARGET = CASE 
        WHEN gc.target != 'Unknown' THEN gc.target 
        ELSE suggestions.extracted_merchant
      END,
      updated_at = CURRENT_TIMESTAMP();

  -- 1.4: Update any remaining payment_source rows with NULL Target_AI
  -- This handles rows that may have been missed or newly inserted
  UPDATE `onyga-482313.OI.GENERAL_CONVERSION`
  SET 
    Target_AI = 'Uncategorized Transactions',
    C_TARGET = CASE 
      WHEN target != 'Unknown' THEN target 
      ELSE 'Uncategorized Transactions'
    END,
    updated_at = CURRENT_TIMESTAMP()
  WHERE list_of_values = 'payment_source'
    AND target = 'Unknown'
    AND Target_AI IS NULL;

  -- 1.5: Delete redundant payment_source rows that no longer exist in STG_UNIFIED_TRANSACTION_SOURCES
  -- Only delete rows where target = 'Unknown' (preserve manually set targets)
  -- This ensures GENERAL_CONVERSION stays in sync with staging data while preserving user mappings
  -- For BANK_LEUMI_FOREIGN and BANK_LEUMI_ILS: use source_system|account_name as SOURCE
  DELETE FROM `onyga-482313.OI.GENERAL_CONVERSION`
  WHERE list_of_values = 'payment_source'
    AND target = 'Unknown'  -- Only delete rows that haven't been manually mapped
    AND conversion_id NOT IN (
      SELECT DISTINCT
        CAST(FARM_FINGERPRINT(CONCAT('payment_source|', 
          CASE 
            WHEN stg.source_system IN ('BANK_LEUMI_FOREIGN', 'BANK_LEUMI_ILS') 
            THEN CONCAT(stg.source_system, '|', stg.account_name)
            ELSE stg.source_system
          END,
          '|', stg.transaction_description)) AS INT64)
      FROM `onyga-482313.OI.STG_UNIFIED_TRANSACTION_SOURCES` stg
    );

  -- 1.6: Delete old-format rows (without account_name) for BANK_LEUMI sources after new-format rows are created
  -- Only delete if new-format rows exist for the same transaction_description
  DELETE FROM `onyga-482313.OI.GENERAL_CONVERSION` gc_old
  WHERE gc_old.list_of_values = 'payment_source'
    AND gc_old.SOURCE IN ('BANK_LEUMI_FOREIGN', 'BANK_LEUMI_ILS')
    AND gc_old.SOURCE NOT LIKE '%|%'  -- Old format (without account_name)
    AND EXISTS (
      SELECT 1
      FROM `onyga-482313.OI.GENERAL_CONVERSION` gc_new
      WHERE gc_new.list_of_values = 'payment_source'
        AND gc_new.SOURCE LIKE CONCAT(gc_old.SOURCE, '|%')  -- New format (with account_name)
        AND gc_new.`key` = gc_old.`key`  -- Same transaction_description
    );

  -- ==========================================
  -- STEP 2: Update C_TARGET in GENERAL_CONVERSION before populating FACT
  -- ==========================================
  -- Recalculate C_TARGET based on current target values
  -- This ensures that manual changes to target are reflected in C_TARGET before FACT is populated
  UPDATE `onyga-482313.OI.GENERAL_CONVERSION` gc
  SET
    C_TARGET = CASE 
      WHEN gc.target != 'Unknown' THEN gc.target 
      ELSE gc.Target_AI 
    END,
    updated_at = CURRENT_TIMESTAMP()
  WHERE gc.list_of_values = 'payment_source'
    AND (
      gc.C_TARGET IS NULL
      OR gc.C_TARGET != CASE 
        WHEN gc.target != 'Unknown' THEN gc.target 
        ELSE gc.Target_AI 
      END
    );

  -- ==========================================
  -- STEP 3: Truncate and Insert into FACT_FINANCIAL_TRANSACTIONS
  -- ==========================================

  -- Truncate FACT table to ensure it matches STG exactly
  TRUNCATE TABLE `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS`;

  -- Insert all rows from STG (after deduplication and categorization)
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
    payment_source,
    payment_source_category,
    payment_source_sub_category,
    transaction_year,
    transaction_month,
    transaction_day,
    factless_transaction_key,
    source_metadata,
    processed_at,
    data_source_file,
    account_nick_name,
    effect_date,
    factless_effect_key,
    amount_usd,
    amount_ils,
    amount_hkd,
    factless_key
  )
  WITH categorized_staging AS (
    -- Select staging data (no categorization rules)
    SELECT
      transaction_date,
      amount,
      currency,
      transaction_description,
      transaction_type,
      source_system,
      source_transaction_id,
      account_name,
      source_metadata,
      processed_at,
      data_source_file,
      manual_effect_date
    FROM `onyga-482313.OI.STG_UNIFIED_TRANSACTION_SOURCES`
  ),
  with_conversions AS (
    SELECT
      cs.*,
      -- Lookup Account-Nick-Name from GENERAL_CONVERSION
      COALESCE(
        gc_account.target,
        'Unknown'
      ) as account_nick_name,
      -- Derive payment_direction from transaction logic
      CASE
        WHEN cs.amount > 0 THEN 'INCOMING'
        WHEN cs.amount < 0 THEN 'OUTGOING'
        WHEN cs.transaction_description LIKE '%העברה%' OR cs.transaction_description LIKE '%Transfer%' THEN 'INTERNAL_TRANSFER'
        ELSE 'UNKNOWN'
      END as payment_direction,
      -- Lookup payment_source from GENERAL_CONVERSION (use C_TARGET which is the consolidated field)
      COALESCE(
        gc_payment_src.C_TARGET,
        'Unknown'
      ) as payment_source,
      -- Lookup payment_source_category and payment_source_sub_category from DIM_PAYMENT_SOURCE_HIERARCHY
      COALESCE(
        h.category,
        'Unknown'
      ) as payment_source_category,
      COALESCE(
        h.sub_category,
        'Unknown'
      ) as payment_source_sub_category,
      -- Lookup effect_days_to_reduce from GENERAL_CONVERSION (payment_source)
      gc_payment_src.effect_days_to_reduce
    FROM categorized_staging cs
    -- Account-Nick-Name lookup
    LEFT JOIN `onyga-482313.OI.GENERAL_CONVERSION` gc_account
      ON gc_account.list_of_values = 'Account-Nick-Name'
      AND gc_account.SOURCE = cs.source_system
      AND gc_account.`key` = cs.account_name
    -- payment_source lookup from GENERAL_CONVERSION
    -- For BANK_LEUMI_FOREIGN and BANK_LEUMI_ILS: use source_system|account_name as SOURCE
    LEFT JOIN `onyga-482313.OI.GENERAL_CONVERSION` gc_payment_src
      ON gc_payment_src.list_of_values = 'payment_source'
      AND gc_payment_src.SOURCE = CASE 
        WHEN cs.source_system IN ('BANK_LEUMI_FOREIGN', 'BANK_LEUMI_ILS') 
        THEN CONCAT(cs.source_system, '|', cs.account_name)
        ELSE cs.source_system
      END
      AND gc_payment_src.`key` = cs.transaction_description
    -- Lookup payment_source hierarchy (category and sub_category) from DIM_PAYMENT_SOURCE_HIERARCHY
    LEFT JOIN `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY` h
      ON h.payment_source = COALESCE(gc_payment_src.C_TARGET, 'Unknown')
      AND h.is_active = TRUE  -- Only use active hierarchy entries
  ),
  currency_rates_by_date AS (
    -- Get the most recent exchange rate for each currency pair (latest date only)
    SELECT
      c.base_currency,
      c.target_currency,
      c.exchange_rate,
      c.exchange_date
    FROM `onyga-482313.OI.DIM_CURRENCY_RATES` c
    INNER JOIN (
      SELECT 
        base_currency,
        target_currency,
        MAX(exchange_date) as max_exchange_date
      FROM `onyga-482313.OI.DIM_CURRENCY_RATES`
      GROUP BY base_currency, target_currency
    ) m
      ON c.base_currency = m.base_currency
      AND c.target_currency = m.target_currency
      AND c.exchange_date = m.max_exchange_date
  ),
  with_currency_rates AS (
    SELECT
      wc.*,
      -- Currency conversion rates - use most recent rate available (latest date)
      cr_usd.exchange_rate as usd_rate,
      cr_ils.exchange_rate as ils_rate,
      cr_hkd.exchange_rate as hkd_rate
    FROM with_conversions wc
    LEFT JOIN (SELECT * FROM currency_rates_by_date WHERE target_currency = 'USD') cr_usd
      ON cr_usd.base_currency = wc.currency
    LEFT JOIN (SELECT * FROM currency_rates_by_date WHERE target_currency = 'ILS') cr_ils
      ON cr_ils.base_currency = wc.currency
    LEFT JOIN (SELECT * FROM currency_rates_by_date WHERE target_currency = 'HKD') cr_hkd
      ON cr_hkd.base_currency = wc.currency
    
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
    payment_source,
    payment_source_category,
    payment_source_sub_category,
    EXTRACT(YEAR FROM transaction_date) as transaction_year,
    EXTRACT(MONTH FROM transaction_date) as transaction_month,
    EXTRACT(DAY FROM transaction_date) as transaction_day,
    CONCAT(CAST(CAST(FORMAT_DATE('%Y%m%d', transaction_date) AS INT64) AS STRING), '-UNKNOWN') as factless_transaction_key,
    source_metadata,
    processed_at,
    data_source_file,
    account_nick_name,
    -- Effect Date: Priority 1) manual_effect_date, 2) transaction_date - effect_days_to_reduce, 3) transaction_date
    -- Logic: For accrual accounting, allows manual override or automatic date reduction based on payment_source
    CASE
      WHEN wc.manual_effect_date IS NOT NULL THEN wc.manual_effect_date
      WHEN wc.effect_days_to_reduce IS NOT NULL THEN DATE_SUB(wc.transaction_date, INTERVAL wc.effect_days_to_reduce DAY)
      ELSE wc.transaction_date
    END as effect_date,
    -- Factless Effect Key: date_key-UNKNOWN format based on effect_date
    CONCAT(CAST(CAST(FORMAT_DATE('%Y%m%d', 
      CASE
        WHEN wc.manual_effect_date IS NOT NULL THEN wc.manual_effect_date
        WHEN wc.effect_days_to_reduce IS NOT NULL THEN DATE_SUB(wc.transaction_date, INTERVAL wc.effect_days_to_reduce DAY)
        ELSE wc.transaction_date
      END
    ) AS INT64) AS STRING), '-UNKNOWN') as factless_effect_key,
    -- Currency conversions (use rate if available, otherwise NULL)
    CASE
      WHEN currency = 'USD' THEN amount
      WHEN usd_rate IS NOT NULL THEN amount * usd_rate
      ELSE NULL -- No rate available
    END as amount_usd,
    CASE
      WHEN currency = 'ILS' THEN amount
      WHEN ils_rate IS NOT NULL THEN amount * ils_rate
      ELSE NULL -- No rate available
    END as amount_ils,
    CASE
      WHEN currency = 'HKD' THEN amount
      WHEN hkd_rate IS NOT NULL THEN amount * hkd_rate
      ELSE NULL -- No rate available
    END as amount_hkd,
    -- Factless Key: date_key - asin (NULL if asin not available)
    CASE
      WHEN JSON_EXTRACT_SCALAR(wc.source_metadata, '$.asin') IS NOT NULL THEN
        CONCAT(CAST(CAST(FORMAT_DATE('%Y%m%d', wc.transaction_date) AS INT64) AS STRING), '-', JSON_EXTRACT_SCALAR(wc.source_metadata, '$.asin'))
      ELSE NULL
    END as factless_key
  FROM with_currency_rates wc;

  -- Get count of inserted rows
  SET transactions_merged = @@row_count;

  -- Note: TRUNCATE + INSERT ensures FACT table has exactly the same rows as STG
  -- This approach is simpler and ensures data consistency between STG and FACT
  -- All rows from STG are inserted into FACT (no deduplication)

  -- ==========================================
  -- STEP 4: Update transaction_count and transaction_sum in GENERAL_CONVERSION
  -- ==========================================

  -- 3.1: Update Account-Nick-Name conversions with counts and sums, and recalculate C_TARGET
  MERGE `onyga-482313.OI.GENERAL_CONVERSION` AS gc
  USING (
    SELECT
      CAST(FARM_FINGERPRINT(CONCAT('Account-Nick-Name|', fact.source_system, '|', fact.account_name)) AS INT64) as conversion_id,
      COUNT(*) as transaction_count,
      SUM(fact.amount) as transaction_sum
    FROM `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS` fact
    GROUP BY fact.source_system, fact.account_name
  ) AS stats
  ON gc.conversion_id = stats.conversion_id
    AND gc.list_of_values = 'Account-Nick-Name'
  WHEN MATCHED THEN
    UPDATE SET
      transaction_count = stats.transaction_count,
      transaction_sum = stats.transaction_sum,
      C_TARGET = CASE 
        WHEN gc.target != 'Unknown' THEN gc.target 
        ELSE gc.Target_AI 
      END,
      updated_at = CURRENT_TIMESTAMP();

  -- 3.2: Update payment_source conversions with counts and sums, and recalculate C_TARGET
  -- For BANK_LEUMI_FOREIGN and BANK_LEUMI_ILS: use source_system|account_name as SOURCE
  MERGE `onyga-482313.OI.GENERAL_CONVERSION` AS gc
  USING (
    SELECT
      CAST(FARM_FINGERPRINT(CONCAT('payment_source|', 
        CASE 
          WHEN fact.source_system IN ('BANK_LEUMI_FOREIGN', 'BANK_LEUMI_ILS') 
          THEN CONCAT(fact.source_system, '|', fact.account_name)
          ELSE fact.source_system
        END,
        '|', fact.transaction_description)) AS INT64) as conversion_id,
      COUNT(*) as transaction_count,
      SUM(fact.amount) as transaction_sum
    FROM `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS` fact
    GROUP BY 
      fact.source_system,
      fact.account_name,
      fact.transaction_description
  ) AS stats
  ON gc.conversion_id = stats.conversion_id
    AND gc.list_of_values = 'payment_source'
  WHEN MATCHED THEN
    UPDATE SET
      transaction_count = stats.transaction_count,
      transaction_sum = stats.transaction_sum,
      C_TARGET = CASE 
        WHEN gc.target != 'Unknown' THEN gc.target 
        ELSE gc.Target_AI 
      END,
      updated_at = CURRENT_TIMESTAMP();

  -- ==========================================
  -- STEP 5: Populate DIM_PAYMENT_SOURCE_HIERARCHY
  -- ==========================================

  -- 4.1: Insert new payment_source values from distinct C_TARGET in GENERAL_CONVERSION
  -- Initialize category and sub_category as 'Unknown' for new rows
  INSERT INTO `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY` (
    payment_source,
    sub_category,
    category,
    IS_FUTURE_REOCCURING,
    is_active,
    created_at,
    updated_at
  )
  SELECT DISTINCT
    gc.C_TARGET as payment_source,
    'Unknown' as sub_category,
    'Unknown' as category,
    TRUE as IS_FUTURE_REOCCURING,
    TRUE as is_active,
    CURRENT_TIMESTAMP() as created_at,
    CURRENT_TIMESTAMP() as updated_at
  FROM `onyga-482313.OI.GENERAL_CONVERSION` gc
  WHERE gc.list_of_values = 'payment_source'
    AND gc.C_TARGET IS NOT NULL
    AND gc.C_TARGET != ''
    AND NOT EXISTS (
      SELECT 1
      FROM `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY` h
      WHERE h.payment_source = gc.C_TARGET
    );

  -- 4.2: Update is_active based on existence in FACT_FINANCIAL_TRANSACTIONS
  -- Set is_active = TRUE for payment_sources that exist in FACT_FINANCIAL_TRANSACTIONS
  -- Set is_active = FALSE for payment_sources that don't exist in FACT_FINANCIAL_TRANSACTIONS
  MERGE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY` AS h
  USING (
    SELECT DISTINCT
      fact.payment_source
    FROM `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS` fact
    WHERE fact.payment_source IS NOT NULL
  ) AS fact_payment_sources
  ON h.payment_source = fact_payment_sources.payment_source
  WHEN MATCHED THEN
    UPDATE SET
      is_active = TRUE,
      updated_at = CURRENT_TIMESTAMP();

  -- 4.3: Set is_active = FALSE for payment_sources that no longer exist in FACT_FINANCIAL_TRANSACTIONS
  -- Only update if currently active to avoid unnecessary updates
  UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY` h
  SET
    is_active = FALSE,
    updated_at = CURRENT_TIMESTAMP()
  WHERE h.is_active = TRUE
    AND NOT EXISTS (
      SELECT 1
      FROM `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS` fact
      WHERE fact.payment_source = h.payment_source
        AND fact.payment_source IS NOT NULL
    );

  -- Log the operation results
  SELECT FORMAT(
    'SP_FACT_FINANCIAL_TRANSACTIONS completed: Added %d Account conversions, %d Payment Source conversions. MERGE affected %d rows (INSERT/UPDATE/DELETE). Duration: %d seconds',
    account_conversions_added,
    payment_src_conversions_added,
    transactions_merged,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND)
  ) as operation_summary;
END;