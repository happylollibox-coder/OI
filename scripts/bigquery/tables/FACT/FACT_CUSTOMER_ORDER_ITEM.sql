-- =============================================
-- OI Database Project - FACT_CUSTOMER_ORDER_ITEM
-- =============================================
--
-- Purpose: Amazon customer-order LINE ITEMS — the only grain in the warehouse
--          that says which products travelled in the same order. Loaded by
--          SP_LOAD_FACT_CUSTOMER_ORDER_ITEM from V_SRC_ListOrderItems joined to
--          V_SRC_ListOrder for the date and status the item feed lacks.
--
-- Grain:  One row per (selling_partner_id, amazon_order_id, order_item_id)
--
-- Order-level attributes (purchase_date, order_status, ship_state, ...) are
-- DENORMALIZED onto every line so consumers never have to re-join the header.
-- order_units_total is the HEADER's own unit count, kept deliberately: comparing
-- it against SUM(quantity_ordered) for the order is how you detect line items
-- that have not synced yet.
--
-- Basket-level aggregates are NOT stored here. They are derived in
-- V_ORDER_BASKET, because an order's line count changes as items arrive and a
-- stored aggregate would go stale between loads.
--
-- is_mapped_product = FALSE marks ASINs absent from DIM_PRODUCT (~4% of units:
-- genuine retired Happy Lolli products). They are kept, and item_title carries
-- the label in place of the missing product_short_name.
--
-- Money: item_price_amount is the EXTENDED product price for quantity_ordered
-- units, before tax. It does not tie to the order total (which adds tax and
-- shipping) nor to SRC_ACC_SALES_TRAFFIC_DAILY.SALES_AMOUNT. Only units tie.
--
-- Spec: architecture/CUSTOMER_ORDER_BASKETS.md
--
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM` (
  -- Keys
  selling_partner_id         STRING,
  amazon_order_id            STRING,
  order_item_id               STRING,

  -- Order header, denormalized
  purchase_date              DATE,
  purchase_timestamp_utc     TIMESTAMP,
  order_status               STRING,
  is_canceled                BOOL,
  is_business_order          BOOL,
  ship_city                  STRING,
  ship_state                 STRING,
  order_units_total          INT64,

  -- Product
  asin                       STRING,
  seller_sku                 STRING,
  item_title                 STRING,
  parent_name                STRING,
  product_short_name         STRING,
  is_mapped_product          BOOL,

  -- Units
  quantity_ordered           INT64,
  quantity_shipped           INT64,

  -- Money (extended over quantity_ordered, pre-tax)
  item_price_amount          NUMERIC,
  item_tax_amount            NUMERIC,
  promotion_discount_amount  NUMERIC,
  unit_price_amount          NUMERIC,
  promotion_ids              STRING,
  is_gift                    BOOL,

  loaded_at                  TIMESTAMP
)
PARTITION BY purchase_date
CLUSTER BY asin, amazon_order_id
OPTIONS (
  description = "Amazon customer-order line items, one row per (selling_partner_id, amazon_order_id, order_item_id). THE basket-composition fact. Loaded by SP_LOAD_FACT_CUSTOMER_ORDER_ITEM. purchase_date is America/Los_Angeles and ties to SRC_ACC_SALES_TRAFFIC_DAILY.date on units. Consumers must filter NOT is_canceled AND quantity_ordered > 0 — canceled lines exist on Shipped orders. Spec: architecture/CUSTOMER_ORDER_BASKETS.md"
);
