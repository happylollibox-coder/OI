-- =============================================
-- OI Database Project - V_SRC_ListOrder
-- =============================================
--
-- Purpose: Interface view to the Daton Amazon SP-API Orders feed.
--          The ORDER-HEADER half of customer-order data. Supplies the
--          purchase date, status and channel that ListOrderItems lacks —
--          without this table a basket cannot be dated or filtered.
--
-- Source: daton-491514.BigQuery.amazon_selling_partner_ListOrder
-- Grain:  One row per (selling_partner_id, amazon_order_id) — latest Daton batch wins
-- Sync:   Daton Orders API; enabled 2026-08-22. History floors at ~2024-08-22
--         (the SP-API Orders 2-year window), which predates the 2024-09-05
--         start of ads data, so baskets cover the whole advertised era.
--
-- TIMEZONE — the one thing to get right here:
--   PurchaseDate / LastUpdateDate arrive as naive DATETIME in **UTC**.
--   purchase_date (America/Los_Angeles) is the BUSINESS date and ties out
--   exactly to SRC_ACC_SALES_TRAFFIC_DAILY.date; the raw UTC date does not
--   (measured 2026-08-22 over 2024-08-26..2024-09-10: LA matched on 15 of 16
--   days, UTC was off by as much as 21 units/day). Join on purchase_date.
--
-- JOIN CONTRACT: join to V_SRC_ListOrderItems on
--   (selling_partner_id, amazon_order_id) — both columns, always.
--   Only one selling partner exists today (AE97SA4TCRHH), so partner is a
--   no-op right now; it is in the key because sellingPartnerId is part of
--   Daton's grain, and a second seller account added to the connector would
--   otherwise make the dedup PARTITION BY silently pick one row across
--   partners and let the join collide. (Ori, 2026-08-22.)
--
-- SHAPE NOTES (Daton wraps every single-value object as a REPEATED record):
--   OrderTotal / ShippingAddress / etc. are arrays of at most one element —
--   read them with [SAFE_OFFSET(0)], never plain dot access.
--   * OrderStatus spells it 'Canceled' (one L), not 'Cancelled'.
--   * Canceled orders carry zero units and no OrderTotal / ShippingAddress,
--     so they are kept, not filtered — downstream decides.
--   * ShippingAddress.PostalCode is NULL for every row (Amazon redacts it on
--     this seller's Orders feed). City and StateOrRegion ARE populated.
--   * ~1.5% of Shipped orders arrive with an empty OrderTotal array.
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_SRC_ListOrder` AS

WITH deduped AS (
  SELECT
    sellingPartnerId,
    AmazonOrderId,
    SellerOrderId,
    PurchaseDate,
    LastUpdateDate,
    OrderStatus,
    FulfillmentChannel,
    SalesChannel,
    OrderChannel,
    OrderType,
    ShipServiceLevel,
    ShipmentServiceLevelCategory,
    NumberOfItemsShipped,
    NumberOfItemsUnshipped,
    OrderTotal,
    ShippingAddress,
    IsBusinessOrder,
    IsPrime,
    IsPremiumOrder,
    IsReplacementOrder,
    ReplacedOrderId,
    MarketplaceId,
    _daton_batch_runtime,
    ROW_NUMBER() OVER (
      PARTITION BY sellingPartnerId, AmazonOrderId
      ORDER BY _daton_batch_runtime DESC, LastUpdateDate DESC
    ) AS rn
  FROM `daton-491514.BigQuery.amazon_selling_partner_ListOrder`
  WHERE MarketplaceId = 'ATVPDKIKX0DER'   -- US only
    AND AmazonOrderId IS NOT NULL
)

SELECT
  sellingPartnerId                                                 AS selling_partner_id,
  AmazonOrderId                                                    AS amazon_order_id,
  SellerOrderId                                                    AS seller_order_id,

  -- Dates: raw UTC preserved, LA local is the business date
  TIMESTAMP(PurchaseDate, 'UTC')                                   AS purchase_timestamp_utc,
  DATE(TIMESTAMP(PurchaseDate, 'UTC'), 'America/Los_Angeles')      AS purchase_date,
  TIMESTAMP(LastUpdateDate, 'UTC')                                 AS last_update_timestamp_utc,
  DATE(TIMESTAMP(LastUpdateDate, 'UTC'), 'America/Los_Angeles')    AS last_update_date,

  -- Status / channel
  OrderStatus                                                      AS order_status,
  OrderStatus = 'Canceled'                                         AS is_canceled,
  FulfillmentChannel                                               AS fulfillment_channel,
  SalesChannel                                                     AS sales_channel,
  OrderChannel                                                     AS order_channel,
  OrderType                                                        AS order_type,
  ShipServiceLevel                                                 AS ship_service_level,
  ShipmentServiceLevelCategory                                     AS shipment_service_level_category,

  -- Units (order header count; the authoritative per-ASIN split is in V_SRC_ListOrderItems)
  COALESCE(NumberOfItemsShipped, 0)                                AS units_shipped,
  COALESCE(NumberOfItemsUnshipped, 0)                              AS units_unshipped,
  COALESCE(NumberOfItemsShipped, 0)
    + COALESCE(NumberOfItemsUnshipped, 0)                          AS units_total,

  -- Money
  OrderTotal[SAFE_OFFSET(0)].Amount                                AS order_total_amount,
  OrderTotal[SAFE_OFFSET(0)].CurrencyCode                          AS order_total_currency,

  -- Ship-to (PostalCode intentionally omitted — always NULL on this feed)
  ShippingAddress[SAFE_OFFSET(0)].City                             AS ship_city,
  ShippingAddress[SAFE_OFFSET(0)].StateOrRegion                    AS ship_state,
  ShippingAddress[SAFE_OFFSET(0)].CountryCode                      AS ship_country,

  -- Flags
  COALESCE(IsBusinessOrder, FALSE)                                 AS is_business_order,
  COALESCE(IsPrime, FALSE)                                         AS is_prime,
  COALESCE(IsPremiumOrder, FALSE)                                  AS is_premium_order,
  COALESCE(IsReplacementOrder, FALSE)                              AS is_replacement_order,
  ReplacedOrderId                                                  AS replaced_order_id,

  MarketplaceId                                                    AS marketplace_id,
  TIMESTAMP_MILLIS(CAST(_daton_batch_runtime AS INT64))            AS batch_time
FROM deduped
WHERE rn = 1;
