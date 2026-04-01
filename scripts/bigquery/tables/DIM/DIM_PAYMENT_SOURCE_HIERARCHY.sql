-- =============================================
-- OI Database Project - DIM_PAYMENT_SOURCE_HIERARCHY Table
-- =============================================
--
-- Purpose: Hierarchical lookup table for payment sources with categories and subcategories
-- Used for organizing payment sources into business categories
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- Create the payment source hierarchy table
-- WARNING: This table is populated automatically by SP_FACT_FINANCIAL_TRANSACTIONS
-- Do not manually insert rows unless you want to override the automatic population
CREATE OR REPLACE TABLE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY` (
  -- Primary key (payment_source from C_TARGET in GENERAL_CONVERSION)
  payment_source STRING(65535) NOT NULL, -- 'AMAZON', 'GOOGLE_ADS', 'HELIUM10', 'BANK Fee', etc.

  -- Hierarchy levels (initialized to 'Unknown', can be manually set)
  sub_category STRING(65535) DEFAULT 'Unknown', -- Sub-category grouping
  category STRING(65535) DEFAULT 'Unknown', -- Main category grouping

  -- Business attributes
  IS_FUTURE_REOCCURING BOOL DEFAULT TRUE, -- Indicates if the payment source is recurring

  -- Metadata
  is_active BOOLEAN DEFAULT TRUE, -- Set to FALSE if payment_source no longer exists in FACT_FINANCIAL_TRANSACTIONS
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),

  -- Constraints
  PRIMARY KEY (payment_source) NOT ENFORCED
)
CLUSTER BY category, sub_category, payment_source;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- This table provides a hierarchical structure for payment sources:
-- - category: Top-level grouping (e.g., 'ADVERTISING', 'E-COMMERCE', 'SERVICES')
-- - sub_category: Mid-level grouping (e.g., 'Search Ads', 'Marketplace', 'Tools')
-- - payment_source: Specific entity (e.g., 'GOOGLE_ADS', 'AMAZON', 'HELIUM10')
--
-- Example hierarchy:
--   category: 'ADVERTISING'
--     sub_category: 'Search Ads'
--       payment_source: 'GOOGLE_ADS'
--     sub_category: 'Social Media'
--       payment_source: 'FACEBOOK_ADS'
--
--   category: 'E-COMMERCE'
--     sub_category: 'Marketplace'
--       payment_source: 'AMAZON'
--
-- =============================================
