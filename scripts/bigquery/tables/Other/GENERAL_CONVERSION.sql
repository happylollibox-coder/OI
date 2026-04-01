-- =============================================
-- OI Database Project - GENERAL_CONVERSION Table
-- =============================================
--
-- Purpose: General conversion/lookup table for various value mappings
-- Used for Account-Nick-Name and subcategory_id conversions
-- Project: onyga-482313
-- Dataset: OI
--
-- IMPORTANT: This table contains manually maintained 'target' values.
-- If you need to add/modify columns, use ALTER TABLE instead of CREATE OR REPLACE
-- to preserve existing data. CREATE OR REPLACE will delete all rows!
--
-- =============================================

-- Create the general conversion table
-- WARNING: CREATE OR REPLACE deletes all existing data!
-- Use ALTER TABLE ADD COLUMN for schema changes if table already exists.
CREATE OR REPLACE TABLE `onyga-482313.OI.GENERAL_CONVERSION` (
  -- Primary key
  conversion_id INT64 NOT NULL,

  -- Conversion type identifier
  list_of_values STRING(65535) NOT NULL, -- 'Account-Nick-Name', 'subcategory_id', etc.

  -- Source system identifier
  SOURCE STRING(65535) NOT NULL, -- 'BANK_LEUMI_ILS', 'PAYONEER_HAPPY_LOLLI', etc.

  -- Key for lookup (concatenated combination of source columns)
  `key` STRING(65535) NOT NULL,

  -- Target value (the converted/mapped value)
  target STRING(65535) NOT NULL,

  -- AI-suggested target value (based on categorization rules)
  Target_AI STRING(65535), -- Suggestion from CFG_TRANSACTION_CATEGORIZATION_RULES

  -- Computed target value: target if target != 'Unknown', otherwise Target_AI
  C_TARGET STRING(65535), -- Effective target value for lookups

  -- Example value for reference
  example STRING(65535),

  -- Transaction statistics
  transaction_count INT64 DEFAULT 0, -- Count of transactions matching this conversion key
  transaction_sum FLOAT64 DEFAULT 0.0, -- Sum of transaction amounts matching this conversion key

  -- Effect Date Reduction (for payment_source only)
  effect_days_to_reduce INT64, -- Number of days to subtract from transaction_date for effect_date calculation (nullable, for payment_source list_of_values only)

  -- Metadata
  date_inserted TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),

  -- Constraints
  PRIMARY KEY (conversion_id) NOT ENFORCED
)
CLUSTER BY list_of_values, SOURCE, `key`;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- This table serves as a flexible lookup/conversion table for various
-- value mappings across the system:
--
-- - Account-Nick-Name: Maps source_system + account_name to friendly names
-- - subcategory_id: Maps source_system + transaction_description to budget categories
-- - Future: Can be extended for other conversion needs
--
-- The key field stores concatenated values (e.g., "BANK_LEUMI_ILS|680-49923/21")
-- for efficient lookup matching.
--
-- =============================================