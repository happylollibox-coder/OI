-- =============================================
-- OI Database Project - CFG_TRANSACTION_CATEGORIZATION_RULES Table
-- =============================================
--
-- Purpose: Lookup rules for mapping transactions to budget categories
-- Rules are applied in priority order (lower priority number = higher precedence)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- Create the transaction categorization rules table
CREATE OR REPLACE TABLE `onyga-482313.OI.CFG_TRANSACTION_CATEGORIZATION_RULES` (
  -- Primary key
  rule_id INT64 NOT NULL,

  -- Rule definition
  rule_name STRING NOT NULL,
  rule_description STRING,

  -- Source system filter (optional)
  source_system_filter STRING, -- 'BANK_LEUMI_ILS', 'BANK_LEUMI_FOREIGN', 'PAYONEER_ADVA_TAL', 'PAYONEER_HAPPY_LOLLI'

  -- Pattern matching criteria
  description_pattern STRING,    -- Regex pattern for transaction description
  amount_min FLOAT64,           -- Minimum amount threshold (optional)
  amount_max FLOAT64,           -- Maximum amount threshold (optional)
  currency_filter STRING,       -- Currency filter (optional)

  -- Target category assignment
  target_subcategory_id INT64 NOT NULL,

  -- Rule priority and status
  priority INT64 NOT NULL,      -- Lower number = higher priority
  is_active BOOLEAN DEFAULT TRUE,

  -- Metadata
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  created_by STRING DEFAULT 'SYSTEM',

  -- Constraints
  PRIMARY KEY (rule_id) NOT ENFORCED
)
CLUSTER BY priority, source_system_filter;

-- =============================================
-- INSERT CATEGORIZATION RULES
-- =============================================

-- Clear existing data
DELETE FROM `onyga-482313.OI.CFG_TRANSACTION_CATEGORIZATION_RULES` WHERE TRUE;

-- Insert categorization rules (ordered by priority)
INSERT INTO `onyga-482313.OI.CFG_TRANSACTION_CATEGORIZATION_RULES`
  (rule_id, rule_name, rule_description, source_system_filter, description_pattern, target_subcategory_id, priority)
VALUES
  -- High Priority Rules (Priority 1-10)

  -- Bank Leumi Transfers (highest priority)
  (1, 'Bank Leumi Inter-Account Transfers', 'Transfers between bank accounts', 'BANK_LEUMI_ILS', 'העברה.*חשבון מקושר', 1101, 1),
  (2, 'Bank Leumi Salary Income', 'Salary deposits from employers', 'BANK_LEUMI_ILS', 'משכורת|שכר', 701, 2),
  (3, 'Bank Leumi Loan Payments', 'Monthly loan repayments', 'BANK_LEUMI_ILS', 'פרעון הלוואה', 803, 3),
  (4, 'Bank Leumi Mortgage Payments', 'Mortgage payments', 'BANK_LEUMI_ILS', 'משכנתא|לאומי למשכנת', 1001, 4),

  -- Payoneer Rules (Priority 11-30)
  (11, 'Payoneer Google Ads', 'Google advertising payments', NULL, 'GOOGLE.*ADS', 302, 11),
  (12, 'Payoneer Helium10', 'Helium10 SEO tool payments', NULL, 'HELIUM10', 401, 12),
  (13, 'Payoneer Amazon Advertising', 'Amazon advertising costs', NULL, 'AMAZON.*ADVERTIS', 301, 13),
  (14, 'Payoneer Sylvia Payments', 'Contractor payments to Sylvia', NULL, 'SYLVIA', 702, 14),
  (15, 'Payoneer Amazon Commissions', 'Amazon sales commissions', NULL, 'Payment from Amazon', 101, 15),
  (16, 'Payoneer Adva Tal Transfers', 'Internal transfers to adva tal', NULL, 'Payment from adva tal', 1101, 16),
  (17, 'Payoneer Card Charges', 'Credit card processing fees', NULL, 'Card charge', 802, 17),

  -- Medium Priority Rules (Priority 31-50)
  (31, 'Generic Bank Fees', 'Bank service charges', 'BANK_LEUMI_ILS', 'עמלה|דמי.*שמירה', 801, 31),
  (32, 'Generic Bank Interest', 'Bank interest income', 'BANK_LEUMI_ILS', 'ריבית', 201, 32),
  (33, 'Generic Currency Conversion', 'FX conversion fees', NULL, 'המרה|conversion', 803, 33),

  -- Low Priority Fallback Rules (Priority 99)
  (99, 'Uncategorized Transactions', 'Fallback for unmatched transactions', NULL, '.*', 9901, 99);

-- =============================================
