-- =============================================
-- OI Database Project - DIM_BUDGET_CATEGORIES Table
-- =============================================
--
-- Purpose: List of Values (LOV) table for budget categories and subcategories
-- Used for 2026-2027 budgeting and financial planning
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- Create the budget categories dimension table
CREATE OR REPLACE TABLE `onyga-482313.OI.DIM_BUDGET_CATEGORIES` (
  -- Primary key
  category_id INT64 NOT NULL,

  -- Category hierarchy
  category_name STRING NOT NULL,
  subcategory_id INT64 NOT NULL,
  subcategory_name STRING NOT NULL,

  -- Metadata
  category_type STRING NOT NULL, -- 'INCOME', 'EXPENSE', 'TRANSFER'
  is_recurring BOOLEAN DEFAULT FALSE,
  budget_confidence STRING DEFAULT 'MEDIUM', -- 'HIGH', 'MEDIUM', 'LOW'
  forecast_multiplier FLOAT64 DEFAULT 1.0,

  -- Status and tracking
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),

  -- Constraints
  PRIMARY KEY (category_id, subcategory_id) NOT ENFORCED
)
CLUSTER BY category_name, subcategory_name;

-- =============================================
-- INSERT BUDGET CATEGORIES DATA
-- =============================================

-- Clear existing data
DELETE FROM `onyga-482313.OI.DIM_BUDGET_CATEGORIES` WHERE TRUE;

-- Insert Income Categories
INSERT INTO `onyga-482313.OI.DIM_BUDGET_CATEGORIES`
  (category_id, category_name, subcategory_id, subcategory_name, category_type, is_recurring, budget_confidence)
VALUES
  -- REVENUE Category
  (1, 'REVENUE', 101, 'Amazon Sales & Commissions', 'INCOME', TRUE, 'HIGH'),
  (1, 'REVENUE', 102, 'Consulting Services', 'INCOME', FALSE, 'MEDIUM'),
  (1, 'REVENUE', 103, 'Business Revenue', 'INCOME', TRUE, 'MEDIUM'),
  (1, 'REVENUE', 104, 'Other Income', 'INCOME', FALSE, 'LOW'),

  -- INVESTMENT & INTEREST Category
  (2, 'INVESTMENT & INTEREST', 201, 'Interest Income', 'INCOME', TRUE, 'HIGH'),
  (2, 'INVESTMENT & INTEREST', 202, 'Dividend Income', 'INCOME', TRUE, 'MEDIUM'),
  (2, 'INVESTMENT & INTEREST', 203, 'Currency Gains', 'INCOME', FALSE, 'LOW');

-- Insert Expense Categories
INSERT INTO `onyga-482313.OI.DIM_BUDGET_CATEGORIES`
  (category_id, category_name, subcategory_id, subcategory_name, category_type, is_recurring, budget_confidence)
VALUES
  -- MARKETING & ADVERTISING Category
  (3, 'MARKETING & ADVERTISING', 301, 'Amazon Advertising', 'EXPENSE', TRUE, 'HIGH'),
  (3, 'MARKETING & ADVERTISING', 302, 'Google Ads', 'EXPENSE', TRUE, 'HIGH'),
  (3, 'MARKETING & ADVERTISING', 303, 'Social Media Marketing', 'EXPENSE', TRUE, 'MEDIUM'),
  (3, 'MARKETING & ADVERTISING', 304, 'Other Digital Marketing', 'EXPENSE', FALSE, 'MEDIUM'),

  -- BUSINESS TOOLS & SOFTWARE Category
  (4, 'BUSINESS TOOLS & SOFTWARE', 401, 'SEO & Research Tools', 'EXPENSE', TRUE, 'HIGH'),
  (4, 'BUSINESS TOOLS & SOFTWARE', 402, 'E-commerce Platforms', 'EXPENSE', TRUE, 'HIGH'),
  (4, 'BUSINESS TOOLS & SOFTWARE', 403, 'Accounting & Finance Software', 'EXPENSE', TRUE, 'HIGH'),
  (4, 'BUSINESS TOOLS & SOFTWARE', 404, 'Other Business Tools', 'EXPENSE', FALSE, 'MEDIUM'),

  -- PROFESSIONAL SERVICES Category
  (5, 'PROFESSIONAL SERVICES', 501, 'Consulting Fees', 'EXPENSE', FALSE, 'MEDIUM'),
  (5, 'PROFESSIONAL SERVICES', 502, 'Legal & Accounting', 'EXPENSE', TRUE, 'HIGH'),
  (5, 'PROFESSIONAL SERVICES', 503, 'Web Development', 'EXPENSE', FALSE, 'MEDIUM'),
  (5, 'PROFESSIONAL SERVICES', 504, 'Other Professional Services', 'EXPENSE', FALSE, 'LOW'),

  -- OPERATIONAL COSTS Category
  (6, 'OPERATIONAL COSTS', 601, 'Office Supplies', 'EXPENSE', TRUE, 'MEDIUM'),
  (6, 'OPERATIONAL COSTS', 602, 'Internet & Communications', 'EXPENSE', TRUE, 'HIGH'),
  (6, 'OPERATIONAL COSTS', 603, 'Travel & Transportation', 'EXPENSE', FALSE, 'MEDIUM'),
  (6, 'OPERATIONAL COSTS', 604, 'Miscellaneous Expenses', 'EXPENSE', FALSE, 'LOW'),

  -- PERSONNEL & PAYROLL Category
  (7, 'PERSONNEL & PAYROLL', 701, 'Salary & Wages', 'EXPENSE', TRUE, 'HIGH'),
  (7, 'PERSONNEL & PAYROLL', 702, 'Contractor Payments', 'EXPENSE', TRUE, 'HIGH'),
  (7, 'PERSONNEL & PAYROLL', 703, 'Benefits & Taxes', 'EXPENSE', TRUE, 'HIGH'),
  (7, 'PERSONNEL & PAYROLL', 704, 'Bonuses & Commissions', 'EXPENSE', FALSE, 'MEDIUM'),

  -- FINANCIAL FEES Category
  (8, 'FINANCIAL FEES', 801, 'Bank Fees', 'EXPENSE', TRUE, 'HIGH'),
  (8, 'FINANCIAL FEES', 802, 'Payment Processing Fees', 'EXPENSE', TRUE, 'HIGH'),
  (8, 'FINANCIAL FEES', 803, 'Currency Conversion Fees', 'EXPENSE', TRUE, 'MEDIUM'),
  (8, 'FINANCIAL FEES', 804, 'Other Financial Charges', 'EXPENSE', FALSE, 'LOW'),

  -- BUSINESS INVESTMENT Category
  (9, 'BUSINESS INVESTMENT', 901, 'Equipment & Assets', 'EXPENSE', FALSE, 'MEDIUM'),
  (9, 'BUSINESS INVESTMENT', 902, 'Software Licenses', 'EXPENSE', FALSE, 'MEDIUM'),
  (9, 'BUSINESS INVESTMENT', 903, 'Training & Education', 'EXPENSE', TRUE, 'MEDIUM'),
  (9, 'BUSINESS INVESTMENT', 904, 'Business Development', 'EXPENSE', FALSE, 'LOW'),

  -- TAXES & REGULATORY Category
  (10, 'TAXES & REGULATORY', 1001, 'Income Taxes', 'EXPENSE', TRUE, 'HIGH'),
  (10, 'TAXES & REGULATORY', 1002, 'Sales Taxes', 'EXPENSE', TRUE, 'HIGH'),
  (10, 'TAXES & REGULATORY', 1003, 'Business Licenses', 'EXPENSE', TRUE, 'HIGH'),
  (10, 'TAXES & REGULATORY', 1004, 'Legal Compliance', 'EXPENSE', FALSE, 'MEDIUM'),

  -- ACCOUNT TRANSFERS Category (Internal)
  (11, 'ACCOUNT TRANSFERS', 1101, 'Inter-Account Transfers', 'TRANSFER', TRUE, 'HIGH'),
  (11, 'ACCOUNT TRANSFERS', 1102, 'Currency Conversions', 'TRANSFER', TRUE, 'HIGH'),
  (11, 'ACCOUNT TRANSFERS', 1103, 'Balance Adjustments', 'TRANSFER', FALSE, 'LOW'),

  -- UNKNOWN Category (Fallback)
  (99, 'UNKNOWN', 9901, 'Uncategorized Transactions', 'UNKNOWN', FALSE, 'LOW');

-- =============================================
