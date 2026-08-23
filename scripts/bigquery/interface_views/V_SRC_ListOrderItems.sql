-- =============================================
-- OI Database Project - V_SRC_ListOrderItems
-- =============================================
--
-- Purpose: Interface view to the Daton Amazon SP-API Order Items feed.
--          The LINE-ITEM half of customer-order data, and the only source in
--          the warehouse that says which products travelled in the SAME order.
--          Group by amazon_order_id to get basket composition.
--
-- Source: daton-491514.BigQuery.amazon_selling_partner_ListOrderItems
-- Grain:  One row per (selling_partner_id, amazon_order_id, order_item_id)
--         — latest Daton batch wins
-- Sync:   Daton Order Items API; enabled 2026-08-22 alongside ListOrder.
--
-- THIS VIEW CANNOT BE USED ALONE. The SP-API getOrderItems payload carries no
-- purchase date and no order status — those exist only on the order header.
-- Join to V_SRC_ListOrder on amazon_order_id for purchase_date / order_status
-- before dating, trending or filtering anything. (_daton_batch_runtime is a
-- sync timestamp, NOT a business date — never use it as one.)
--
-- JOIN CONTRACT: join to V_SRC_ListOrder on
--   (selling_partner_id, amazon_order_id) — both columns, always.
--   Only one selling partner exists today (AE97SA4TCRHH), so partner is a
--   no-op right now; it is in the key because sellingPartnerId is part of
--   Daton's grain, and a second seller account added to the connector would
--   otherwise make the dedup PARTITION BY silently pick one row across
--   partners and let the join collide. (Ori, 2026-08-22.)
--
-- CASE TRAP: the source column is lower-camel `amazonOrderId` here but
-- upper-camel `AmazonOrderId` in ListOrder. Both are exposed as
-- amazon_order_id so downstream never has to care.
--
-- SHAPE NOTES: Daton wraps every single-value money object as a REPEATED
-- record of at most one element — read with [SAFE_OFFSET(0)].
--   * ItemPrice is the EXTENDED price for QuantityOrdered units, not unit price.
--   * PromotionIds is a plain STRING, not an array.
--   * ProductInfo.NumberOfItems is Amazon's pack count for the listing.
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_SRC_ListOrderItems` AS

WITH deduped AS (
  SELECT
    sellingPartnerId,
    amazonOrderId,
    OrderItemId,
    ASIN,
    SellerSKU,
    Title,
    QuantityOrdered,
    QuantityShipped,
    ProductInfo,
    ItemPrice,
    ItemTax,
    ShippingPrice,
    ShippingDiscount,
    PromotionDiscount,
    PromotionIds,
    IsGift,
    ConditionId,
    marketplaceId,
    _daton_batch_runtime,
    ROW_NUMBER() OVER (
      PARTITION BY sellingPartnerId, amazonOrderId, OrderItemId
      ORDER BY _daton_batch_runtime DESC
    ) AS rn
  FROM `daton-491514.BigQuery.amazon_selling_partner_ListOrderItems`
  WHERE marketplaceId = 'ATVPDKIKX0DER'   -- US only
    AND amazonOrderId IS NOT NULL
)

SELECT
  sellingPartnerId                                       AS selling_partner_id,
  amazonOrderId                                          AS amazon_order_id,
  OrderItemId                                            AS order_item_id,
  ASIN                                                   AS asin,
  SellerSKU                                              AS seller_sku,
  Title                                                  AS title,

  -- Units
  COALESCE(QuantityOrdered, 0)                           AS quantity_ordered,
  COALESCE(QuantityShipped, 0)                           AS quantity_shipped,
  ProductInfo[SAFE_OFFSET(0)].NumberOfItems              AS pack_number_of_items,

  -- Money (extended over quantity_ordered, not per unit)
  ItemPrice[SAFE_OFFSET(0)].Amount                       AS item_price_amount,
  ItemPrice[SAFE_OFFSET(0)].CurrencyCode                 AS item_price_currency,
  ItemTax[SAFE_OFFSET(0)].Amount                         AS item_tax_amount,
  ShippingPrice[SAFE_OFFSET(0)].Amount                   AS shipping_price_amount,
  ShippingDiscount[SAFE_OFFSET(0)].Amount                AS shipping_discount_amount,
  PromotionDiscount[SAFE_OFFSET(0)].Amount               AS promotion_discount_amount,
  SAFE_DIVIDE(ItemPrice[SAFE_OFFSET(0)].Amount,
              NULLIF(QuantityOrdered, 0))                AS unit_price_amount,

  PromotionIds                                           AS promotion_ids,
  COALESCE(IsGift, FALSE)                                AS is_gift,
  ConditionId                                            AS condition_id,

  marketplaceId                                          AS marketplace_id,
  TIMESTAMP_MILLIS(CAST(_daton_batch_runtime AS INT64))  AS batch_time
FROM deduped
WHERE rn = 1;
