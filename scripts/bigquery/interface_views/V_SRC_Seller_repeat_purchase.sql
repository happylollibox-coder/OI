-- =============================================
-- OI Database Project - V_SRC_Seller_repeat_purchase
-- =============================================
--
-- Purpose: Repeat purchase behavior analysis for seller performance
-- Business Logic: Flattens nested revenue struct, deduplicates, filters US marketplace
-- Dependencies: daton-491514.BigQuery.amazon_selling_partner_RepeatPurchaseBehaviourReport
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2026-04-03 (migrated from fivetran-hl)
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_SRC_Seller_repeat_purchase`
AS
SELECT
  asin,
  startDate AS start_date,
  endDate AS end_date,
  marketplaceId AS marketplace_id,
  orders,
  uniqueCustomers AS unique_customers,
  repeatCustomersPctTotal AS repeat_customers_pct_total,
  rev.amount AS repeat_purchase_revenue_amount,
  rev.currencyCode AS repeat_purchase_revenue_currency_code
FROM (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY asin, startDate, endDate
      ORDER BY _daton_batch_runtime DESC
    ) AS rn
  FROM `daton-491514.BigQuery.amazon_selling_partner_RepeatPurchaseBehaviourReport`
  WHERE marketplaceId = 'ATVPDKIKX0DER'
)
LEFT JOIN UNNEST(repeatPurchaseRevenue) rev
WHERE rn = 1
  AND orders IS NOT NULL;