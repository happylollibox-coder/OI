-- =============================================
-- OI Database Project - SP_LOAD_FACT_CUSTOMER_ORDER_ITEM
-- =============================================
--
-- Purpose: Load FACT_CUSTOMER_ORDER_ITEM from the two order interface views.
-- Pattern: FULL MERGE on the composite key — no watermark.
--
-- Why a full MERGE and not an incremental window: the whole source is ~70k rows,
-- so a full pass is seconds, and orders RESTATE (an order shipped yesterday can
-- be canceled tomorrow, and Daton re-emits it). A date-windowed load would leave
-- stale is_canceled flags behind the window. Full MERGE is the cheap correct one.
--
-- The DIM_PRODUCT join is deduplicated with QUALIFY rather than ANY_VALUE:
-- picking parent_name and product_short_name with two separate ANY_VALUE calls
-- over one GROUP BY can pair a name from one row with a short name from another.
--
-- No DELETE arm: order items do not disappear from the source. If they ever do,
-- the acceptance test's row-count check (A1) is what surfaces it.
--
-- Spec: architecture/CUSTOMER_ORDER_BASKETS.md
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_LOAD_FACT_CUSTOMER_ORDER_ITEM`()
OPTIONS (
  description = "Load FACT_CUSTOMER_ORDER_ITEM from V_SRC_ListOrderItems joined to V_SRC_ListOrder. Full MERGE on (selling_partner_id, amazon_order_id, order_item_id) — restatement-safe, no watermark."
)
BEGIN
  DECLARE v_loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

  MERGE `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM` T
  USING (
    SELECT
      i.selling_partner_id,
      i.amazon_order_id,
      i.order_item_id,

      o.purchase_date,
      o.purchase_timestamp_utc,
      o.order_status,
      o.is_canceled,
      o.is_business_order,
      o.ship_city,
      o.ship_state,
      o.units_total AS order_units_total,

      i.asin,
      i.seller_sku,
      i.title AS item_title,
      d.parent_name,
      d.product_short_name,
      d.asin IS NOT NULL AS is_mapped_product,

      i.quantity_ordered,
      i.quantity_shipped,

      i.item_price_amount,
      i.item_tax_amount,
      i.promotion_discount_amount,
      i.unit_price_amount,
      i.promotion_ids,
      i.is_gift
    FROM `onyga-482313.OI.V_SRC_ListOrderItems` i
    JOIN `onyga-482313.OI.V_SRC_ListOrder` o
      USING (selling_partner_id, amazon_order_id)
    LEFT JOIN (
      SELECT asin, parent_name, product_short_name
      FROM `onyga-482313.OI.DIM_PRODUCT`
      QUALIFY ROW_NUMBER() OVER (PARTITION BY asin ORDER BY updated_at DESC, sku) = 1
    ) d
      ON d.asin = i.asin
  ) S
  ON  T.selling_partner_id = S.selling_partner_id
  AND T.amazon_order_id    = S.amazon_order_id
  AND T.order_item_id      = S.order_item_id

  WHEN MATCHED THEN UPDATE SET
    purchase_date             = S.purchase_date,
    purchase_timestamp_utc    = S.purchase_timestamp_utc,
    order_status              = S.order_status,
    is_canceled               = S.is_canceled,
    is_business_order         = S.is_business_order,
    ship_city                 = S.ship_city,
    ship_state                = S.ship_state,
    order_units_total         = S.order_units_total,
    asin                      = S.asin,
    seller_sku                = S.seller_sku,
    item_title                = S.item_title,
    parent_name               = S.parent_name,
    product_short_name        = S.product_short_name,
    is_mapped_product         = S.is_mapped_product,
    quantity_ordered          = S.quantity_ordered,
    quantity_shipped          = S.quantity_shipped,
    item_price_amount         = S.item_price_amount,
    item_tax_amount           = S.item_tax_amount,
    promotion_discount_amount = S.promotion_discount_amount,
    unit_price_amount         = S.unit_price_amount,
    promotion_ids             = S.promotion_ids,
    is_gift                   = S.is_gift,
    loaded_at                 = v_loaded_at

  WHEN NOT MATCHED THEN INSERT (
    selling_partner_id, amazon_order_id, order_item_id,
    purchase_date, purchase_timestamp_utc, order_status, is_canceled,
    is_business_order, ship_city, ship_state, order_units_total,
    asin, seller_sku, item_title, parent_name, product_short_name, is_mapped_product,
    quantity_ordered, quantity_shipped,
    item_price_amount, item_tax_amount, promotion_discount_amount,
    unit_price_amount, promotion_ids, is_gift,
    loaded_at
  ) VALUES (
    S.selling_partner_id, S.amazon_order_id, S.order_item_id,
    S.purchase_date, S.purchase_timestamp_utc, S.order_status, S.is_canceled,
    S.is_business_order, S.ship_city, S.ship_state, S.order_units_total,
    S.asin, S.seller_sku, S.item_title, S.parent_name, S.product_short_name, S.is_mapped_product,
    S.quantity_ordered, S.quantity_shipped,
    S.item_price_amount, S.item_tax_amount, S.promotion_discount_amount,
    S.unit_price_amount, S.promotion_ids, S.is_gift,
    v_loaded_at
  );
END;
