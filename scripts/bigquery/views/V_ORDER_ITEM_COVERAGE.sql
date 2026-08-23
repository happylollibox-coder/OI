-- =============================================
-- OI Database Project - V_ORDER_ITEM_COVERAGE
-- =============================================
--
-- Purpose: The BACKFILL GATE for customer-order baskets. Reports, per calendar
--          month, how many order headers have their line items loaded yet.
--          Basket and cross-sell answers are only as good as this coverage --
--          a month at 40% coverage will produce confident, wrong pair counts.
--
-- Source: V_SRC_ListOrder (headers), V_SRC_ListOrderItems (lines)
-- Grain:  One row per purchase month
--
-- Canceled orders are excluded from the denominator: they carry zero units and
-- do not need line items, so counting them would understate real coverage.
--
-- READ THIS BEFORE TRUSTING V_ORDER_CROSS_SELL: a month whose coverage_pct is
-- below 99 is still filling. See architecture/CUSTOMER_ORDER_BASKETS.md.
--
-- is_month_complete is coverage_pct >= 99.99, NOT exact equality: SP-API may
-- never return items for a handful of very old orders, and a month that will
-- asymptote just under 100% must not stay flagged incomplete forever. This is
-- the same bar the downstream verification uses.
--
-- coverage_pct and units_missing must be read together: orders_with_items only
-- asks "does at least one item row exist for this order", not "have all its
-- lines arrived" -- a partially-synced order still counts as covered, and
-- units_missing is what catches that at month level.
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_ORDER_ITEM_COVERAGE` AS

WITH headers AS (
  SELECT
    DATE_TRUNC(purchase_date, MONTH) AS purchase_month,
    selling_partner_id,
    amazon_order_id,
    units_total
  FROM `onyga-482313.OI.V_SRC_ListOrder`
  WHERE NOT is_canceled
),

items AS (
  SELECT
    selling_partner_id,
    amazon_order_id,
    COUNT(*)               AS item_lines,
    SUM(quantity_ordered)  AS item_units
  FROM `onyga-482313.OI.V_SRC_ListOrderItems`
  GROUP BY 1, 2
)

SELECT
  h.purchase_month,
  COUNT(*)                                                        AS header_orders,
  COUNTIF(i.amazon_order_id IS NOT NULL)                          AS orders_with_items,
  ROUND(100 * COUNTIF(i.amazon_order_id IS NOT NULL) / COUNT(*), 2) AS coverage_pct,
  SUM(h.units_total)                                              AS header_units,
  SUM(COALESCE(i.item_units, 0))                                  AS item_units,
  SUM(h.units_total) - SUM(COALESCE(i.item_units, 0))             AS units_missing,
  ROUND(100 * COUNTIF(i.amazon_order_id IS NOT NULL) / COUNT(*), 2) >= 99.99  AS is_month_complete
FROM headers h
LEFT JOIN items i
  USING (selling_partner_id, amazon_order_id)
GROUP BY 1
ORDER BY 1;
