-- =============================================
-- OI Database Project - V_SRC_sales_and_traffic_business_sku_report_daily
-- =============================================
--
-- Purpose: Standardized view for daily sales and traffic data by SKU/ASIN
-- Business Logic: Maps Daton column names to standardized OI naming convention
-- Dependencies:
--   - daton-491514.BigQuery.amazon_selling_partner_SalesAndTrafficReportByChildASIN
--   - daton-491514.BigQuery.amazon_selling_partner_ListingsItemsSummary (for SKU)
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2026-04-03 (migrated from fivetran-hl)
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_SRC_sales_and_traffic_business_sku_report_daily` AS

WITH deduped_sales AS (
  SELECT
    childAsin,
    date,
    marketplaceId,
    parentAsin,
    unitsOrdered,
    orderedProductSales_amount,
    orderedProductSales_currencyCode,
    totalOrderItems,
    sessions,
    pageViews,
    ROW_NUMBER() OVER (
      PARTITION BY childAsin, date
      ORDER BY _daton_batch_runtime DESC
    ) AS rn
  FROM `daton-491514.BigQuery.amazon_selling_partner_SalesAndTrafficReportByChildASIN`
  WHERE marketplaceId = 'ATVPDKIKX0DER'
),
sku_lookup AS (
  SELECT
    asin,
    ReferenceSKU AS sku,
    ROW_NUMBER() OVER (PARTITION BY asin ORDER BY _daton_batch_runtime DESC) AS rn
  FROM `daton-491514.BigQuery.amazon_selling_partner_ListingsItemsSummary`
  WHERE marketplaceId = 'ATVPDKIKX0DER'
)

SELECT
  s.childAsin AS child_asin,
  s.date AS date,
  s.marketplaceId AS marketplace_id,
  s.parentAsin AS parent_asin,
  l.sku,
  s.unitsOrdered AS SALES_QUANTITY,
  s.orderedProductSales_amount AS SALES_AMOUNT,
  s.orderedProductSales_currencyCode AS SALES_CURRENCY,
  s.totalOrderItems AS SALES_ORDERS,
  s.sessions AS asin_sessions,
  s.pageViews AS page_views
FROM deduped_sales s
LEFT JOIN sku_lookup l ON s.childAsin = l.asin AND l.rn = 1
WHERE s.rn = 1;

-- =============================================
-- VIEW DESCRIPTION
-- =============================================
--
-- This view provides standardized access to daily sales and traffic data from Amazon Seller Central.
-- Migrated from fivetran-hl to daton-491514 on 2026-04-03.
--
-- Key Fields:
-- - child_asin: Product ASIN
-- - date: Report date
-- - marketplace_id: Marketplace identifier
-- - parent_asin: Parent product ASIN
-- - sku: Merchant SKU (from ListingsItemsSummary)
-- - SALES_QUANTITY: Units ordered
-- - SALES_AMOUNT: Total sales amount
-- - SALES_CURRENCY: Currency code
-- - SALES_ORDERS: Total order items
-- - asin_sessions: Unique sessions
-- - page_views: Page views
--
-- =============================================
