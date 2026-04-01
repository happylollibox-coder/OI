-- =============================================
-- Suggested Category and Sub-Category Updates
-- for DIM_PAYMENT_SOURCE_HIERARCHY
-- =============================================
--
-- This script contains suggested categorizations based on common
-- business classification. Review and adjust as needed before running.
--
-- =============================================

-- E-COMMERCE / MARKETPLACE
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'E-COMMERCE', sub_category = 'Marketplace', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN (
  'AMAZON', 'AMZN Mktp CA', 'AMAZON MX MARKETPLACE', 'AMAZON.COM AMAZON.CA', 
  'Amazon Mexico', 'Amazon', 'ETSY', 'ETSY.COM - LOLLICHICAC', 'Etsy.com',
  'WALMART SERVICES'
);

-- E-COMMERCE / PLATFORM
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'E-COMMERCE', sub_category = 'E-commerce Platform', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('SHOPIFY');

-- VENDORS / SAMPLING VENDORS
-- These are vendors used for purchasing product samples
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'VENDORS', sub_category = 'Sampling Vendors', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('aliexpress', 'Alibaba.com');

-- PRODUCT / MANUFACTURE
-- Product manufacturing
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'PRODUCT', sub_category = 'Manufacture', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('SYLVIA');

-- ADVERTISING / SEARCH ADVERTISING
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'ADVERTISING', sub_category = 'Search Advertising', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('GOOGLE ADS');

-- ADVERTISING / SOCIAL MEDIA ADVERTISING
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'ADVERTISING', sub_category = 'Social Media Advertising', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('FACEBK', 'Pinterest Ads');

-- ADVERTISING / DISPLAY ADVERTISING
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'ADVERTISING', sub_category = 'Display Advertising', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('TABOOLA.COM LTD', 'AWIN INC', 'SHAREASALE', 'REBATE KEY INC.');

-- BANKING / BANK FEES
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'BANKING', sub_category = 'Bank Fees', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('BANK Fee', 'BANK FEE', 'BANK STOCKS FEE');

-- BANKING / INTEREST
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'BANKING', sub_category = 'Interest', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('BANK INTEREST', 'Interest Income');

-- BANKING / LOANS
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'BANKING', sub_category = 'Loans', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('BANK LOAN', 'LOAN', 'משכנתא');

-- BANKING / CURRENCY CONVERSION
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'BANKING', sub_category = 'Currency Conversion', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('BANK CURRENCY CONV', 'Currency Conversion');

-- BANKING / CASH TRANSACTIONS
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'BANKING', sub_category = 'Cash Transactions', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('BANK CASH');

-- BANKING / INVESTMENT
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'BANKING', sub_category = 'Investment', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('BANK STOCKS', 'Stocks');

-- BANKING / SAVINGS
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'BANKING', sub_category = 'Savings', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('BANK SAVINGS', 'BANK Savings');

-- BANKING / ACCOUNT MANAGEMENT
-- (No payment sources in this category - removed Chase JP Morgan as it's a service)

-- PAYMENT PROCESSING / CARDS
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'PAYMENT_PROCESSING', sub_category = 'Card Transactions', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN (
  'CARD MAX', 'CARD VISA', 'CARD LEUMI', 'CARD LEUMI MASTERCARD', 
  'CARD', 'CARD DINERS', 'CARD DEBIT'
);

-- PAYMENT PROCESSING / DIGITAL WALLETS
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'PAYMENT_PROCESSING', sub_category = 'Digital Wallets', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('PAYONEER FEE');

-- PAYMENT PROCESSING / OTHER
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'PAYMENT_PROCESSING', sub_category = 'Other Payment Methods', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('CHECK', 'Bank Check');

-- INTERNAL_TRANSFERS / ACCOUNT_TRANSFERS
-- These are the user's own accounts - money moved between their own accounts
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'INTERNAL_TRANSFERS', sub_category = 'Account Transfers', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN (
  'Leumi Business', 'Leumi Personal', 'Mercury', 
  'Payoneer Happy Lolli', 'Payoneer Adva Tal'
);

-- SOFTWARE / BUSINESS TOOLS
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'SOFTWARE', sub_category = 'Business Tools', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('MONDAY.COM', 'monday.com');

-- SOFTWARE / E-COMMERCE TOOLS
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'SOFTWARE', sub_category = 'E-commerce Tools', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN (
  'HELIUM 10', 'HELIUM10.COM', 'SELLERBOARD STANDARD'
);

-- SOFTWARE / BUSINESS TOOLS (Additional - Security/VPN)
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'SOFTWARE', sub_category = 'Business Tools', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('EXPRESSVPN.COM');

-- SOFTWARE / CREATIVE TOOLS
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'SOFTWARE', sub_category = 'Creative Tools', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('CANVA');

-- SERVICES / ACCOUNTING SERVICES
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'SERVICES', sub_category = 'Accounting Services', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN (
  'אייל רואה חשבון', ' וורסל רואה חשבון', '1800ACCOUNTANT'
);

-- SERVICES / PROFESSIONAL SERVICES
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'SERVICES', sub_category = 'Professional Services', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN (
  'BUSINESS FILINGS', 'FIVERR', 'FiverrInc', 'service - product pictures',
  'AGORASTAKI KATERINA M', 'External Inventory', 'DOAR ISRAEL KARGO FOKO',
  'Chase JP Morgan'  -- Service for opening American company
);

-- PRODUCT / SHIPMENT
-- Product shipment/logistics
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'PRODUCT', sub_category = 'Shipment', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('ANNA');

-- SERVICES / PERSONAL SERVICES
-- Personal services (non-business)
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'SERVICES', sub_category = 'Personal Services', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('דפנה');

-- SERVICES / WEB SERVICES
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'SERVICES', sub_category = 'Web Services', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('10WEB.IO', 'SITEGROUND HOSTING', 'DATADIVE.TOOLS');

-- TAXES / INCOME TAX
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'TAXES', sub_category = 'Income Tax', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('מס הכנסה', 'מס');

-- TAXES / SOCIAL SECURITY
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'TAXES', sub_category = 'Social Security', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('ביטוח לאומי', 'ועד', 'קצבת ילדים');

-- INSURANCE / INSURANCE PAYMENTS
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'INSURANCE', sub_category = 'Insurance Payments', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('מגדל', 'Migdal');

-- SERVICES / PERSONAL SERVICES (Additional)
-- פסיפס moved from Insurance to Personal Services
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'SERVICES', sub_category = 'Personal Services', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('פסיפס');

-- PERSONAL / PERSONAL EXPENSES
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'PERSONAL', sub_category = 'Personal Expenses', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('personal', 'Personal', 'רכב', 'מתנות', 'בת מצווה');

-- PERSONAL / GIFTS AND CELEBRATIONS
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'PERSONAL', sub_category = 'Gifts and Celebrations', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('מתנות', 'בת מצווה', 'רבקה ודוד');

-- PERSONAL / SALARIES
-- Personal salary payments (not business employee salaries)
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'PERSONAL', sub_category = 'Salaries', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('opyo', 'TEVA');

-- PERSONAL / HOUSING
-- Personal housing payments
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'PERSONAL', sub_category = 'Housing', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('מורשת שינויים');

-- EMPLOYEE / SALARIES
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'EMPLOYEE', sub_category = 'Salaries', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('משכורת אדווה');

-- EMPLOYEE / OTHER PAYMENTS
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'EMPLOYEE', sub_category = 'Other Payments', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('ERIKA', 'CHERRY OLD');

-- INVESTMENT / INVESTMENT ACCOUNTS
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'INVESTMENT', sub_category = 'Investment Accounts', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('BIT', 'גמל');

-- SAVINGS / SAVINGS ACCOUNTS
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'SAVINGS', sub_category = 'Savings Accounts', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('BANK SAVINGS', 'BANK Savings');

-- BUSINESS EXPENSES / OPERATIONAL
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'BUSINESS_EXPENSES', sub_category = 'Operational', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('Happylollibox');

-- E-COMMERCE / MARKETPLACE (Additional)
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'E-COMMERCE', sub_category = 'Marketplace', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('AMAZON MKTPL');

-- BANKING / LOANS (Additional)
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'BANKING', sub_category = 'Loans', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('Loan');

-- PAYMENT_PROCESSING / DIGITAL WALLETS (Additional)
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'PAYMENT_PROCESSING', sub_category = 'Digital Wallets', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('PAYPAL', 'PP', 'PAIS');

-- INTERNAL_TRANSFERS / ACCOUNT_TRANSFERS (Additional)
-- Old account name variation
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'INTERNAL_TRANSFERS', sub_category = 'Account Transfers', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('Payoneer happy lolli inc - old');

-- SOFTWARE / BUSINESS TOOLS (Additional)
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'SOFTWARE', sub_category = 'Business Tools', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('MICROSOFT#G116932592', 'Microsoft-G114988943', 'SIMPLY BUSINESS');

-- SOFTWARE / CREATIVE TOOLS (Additional)
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'SOFTWARE', sub_category = 'Creative Tools', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('MIDJOURNEY INC.');

-- SERVICES / PROFESSIONAL SERVICES (Additional)
-- Legal services, business services
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'SERVICES', sub_category = 'Professional Services', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('תביעה אלמוג');

-- PERSONAL / HOUSING (Additional)
-- ליטל נעים - new house payment
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'PERSONAL', sub_category = 'Housing', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('ליטל נעים');

-- SERVICES / PERSONAL SERVICES (Additional)
-- Educational services
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'SERVICES', sub_category = 'Personal Services', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('אנגלית גאיה');

-- TAXES / INCOME TAX (Additional)
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'TAXES', sub_category = 'Income Tax', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('מס חברה');

-- PERSONAL / HOUSING (Additional)
-- Construction and real estate related payments
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'PERSONAL', sub_category = 'Housing', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('TAAMAN (MORESHET)', 'קו מור לבניה', 'קו מור מורשת', 'אחים לוי');

-- PERSONAL / GIFTS AND CELEBRATIONS (Additional)
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'PERSONAL', sub_category = 'Gifts and Celebrations', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('מתנה');

-- PERSONAL / PERSONAL PURCHASES
-- Personal shopping/clothing purchases
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'PERSONAL', sub_category = 'Personal Purchases', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source IN ('ZARA HELLAS CHANIA');

-- SERVICES / ACCOUNTING SERVICES (Additional)
-- Fix for payment sources with leading spaces or exact match
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'SERVICES', sub_category = 'Accounting Services', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source LIKE '%אייל רואה חשבון%' 
   OR TRIM(payment_source) = 'אייל רואה חשבון'
   OR payment_source LIKE '% וורסל רואה חשבון%';

-- SERVICES / PROFESSIONAL SERVICES (Additional)
-- Fix for Chase JP Morgan (handle variations with LIKE pattern)
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET category = 'SERVICES', sub_category = 'Professional Services', updated_at = CURRENT_TIMESTAMP()
WHERE payment_source LIKE '%Chase%JP%Morgan%' 
   OR payment_source LIKE '%CHASE%JPMORGAN%' 
   OR TRIM(payment_source) = 'Chase JP Morgan';

-- VENDORS / SAMPLING VENDORS
-- These are vendors used for purchasing product samples (added above)

-- UNCategorized / TO BE REVIEWED
-- Keep this as 'Unknown' for manual review:
-- 'Uncategorized Transactions' - Needs manual categorization based on transaction descriptions (transaction by transaction)
-- All other payment sources have been categorized above

-- =============================================
-- NOTES:
-- =============================================
-- 1. Review all categorizations before running this script
-- 2. Some payment sources may belong to multiple categories - adjust as needed
-- 3. Hebrew payment sources have been categorized based on common Israeli business practices
-- 4. 'Uncategorized Transactions' should be reviewed transaction by transaction
-- 5. After running, verify the results and adjust any incorrect categorizations
-- =============================================
