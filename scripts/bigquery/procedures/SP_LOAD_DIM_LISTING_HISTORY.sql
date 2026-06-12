-- =============================================
-- OI Database Project - SP_LOAD_DIM_LISTING_HISTORY
-- =============================================
--
-- Purpose: SCD Type 2 load for DIM_LISTING_HISTORY from V_SRC_ActiveListingsReport
-- Pattern: Close changed rows (set effective_to, is_current=FALSE), insert new versions
-- Tracked fields: price, Business_Price, Quantity_Price_Type,
--                 Quantity_Lower_Bound_1..5, Quantity_Price_1..5
-- Timing: effective_from = ReportstartDate from source
--         effective_to   = new ReportstartDate - 3 milliseconds (when closing)
-- Initial load: New listings get effective_from = MIN(ReportstartDate) from source history
-- Source: V_SRC_ActiveListingsReport (Daton)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_LOAD_DIM_LISTING_HISTORY`()
OPTIONS (
  description = "SCD2 load for DIM_LISTING_HISTORY. Closes changed rows and inserts new versions from V_SRC_ActiveListingsReport. New listings start from earliest known ReportstartDate."
)
BEGIN
  DECLARE closed_count INT64 DEFAULT 0;
  DECLARE inserted_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- Deduplicate source: keep only the latest per business key
  -- Also compute earliest_report_date per business key from raw source
  CREATE TEMP TABLE _src_listing AS
  SELECT
    v.ReportstartDate,
    v.ReportendDate,
    v.sellingPartnerId,
    v.marketplaceName,
    v.marketplaceId,
    v.listing_id,
    v.seller_sku,
    v.asin1,
    v.fulfillment_channel,
    v.price,
    v.Business_Price,
    v.Quantity_Price_Type,
    v.Quantity_Lower_Bound_1,
    v.Quantity_Price_1,
    v.Quantity_Lower_Bound_2,
    v.Quantity_Price_2,
    v.Quantity_Lower_Bound_3,
    v.Quantity_Price_3,
    v.Quantity_Lower_Bound_4,
    v.Quantity_Price_4,
    v.Quantity_Lower_Bound_5,
    v.Quantity_Price_5,
    CAST(v.ReportstartDate AS DATETIME) AS eff_from,
    -- Earliest date this listing appeared in the source
    CAST(e.earliest_report_date AS DATETIME) AS earliest_report_date
  FROM `onyga-482313.OI.V_SRC_ActiveListingsReport` v
  LEFT JOIN (
    SELECT
      sellingPartnerId,
      marketplaceId,
      listing_id,
      seller_sku,
      asin1,
      fulfillment_channel,
      MIN(ReportstartDate) AS earliest_report_date
    FROM `daton-491514.BigQuery.amazon_selling_partner_ActiveListingsReport`
    WHERE listing_id IS NOT NULL
    GROUP BY sellingPartnerId, marketplaceId, listing_id, seller_sku, asin1, fulfillment_channel
  ) e
    ON  v.sellingPartnerId = e.sellingPartnerId
    AND v.marketplaceId    = e.marketplaceId
    AND v.listing_id       = e.listing_id
    AND v.seller_sku       = e.seller_sku
    AND v.asin1            = e.asin1
    AND v.fulfillment_channel = e.fulfillment_channel;

  -- Step 1: Close rows where tracked attributes changed
  UPDATE `onyga-482313.OI.DIM_LISTING_HISTORY` dim
  SET
    effective_to = DATETIME_SUB(src.eff_from, INTERVAL 3 MILLISECOND),
    is_current = FALSE
  FROM _src_listing src
  WHERE dim.sellingPartnerId = src.sellingPartnerId
    AND dim.marketplaceId    = src.marketplaceId
    AND dim.listing_id       = src.listing_id
    AND dim.seller_sku       = src.seller_sku
    AND dim.asin1            = src.asin1
    AND dim.fulfillment_channel = src.fulfillment_channel
    AND dim.is_current = TRUE
    AND (
      dim.price                IS DISTINCT FROM src.price
      OR dim.Business_Price    IS DISTINCT FROM src.Business_Price
      OR dim.Quantity_Price_Type IS DISTINCT FROM src.Quantity_Price_Type
      OR dim.Quantity_Lower_Bound_1 IS DISTINCT FROM src.Quantity_Lower_Bound_1
      OR dim.Quantity_Price_1  IS DISTINCT FROM src.Quantity_Price_1
      OR dim.Quantity_Lower_Bound_2 IS DISTINCT FROM src.Quantity_Lower_Bound_2
      OR dim.Quantity_Price_2  IS DISTINCT FROM src.Quantity_Price_2
      OR dim.Quantity_Lower_Bound_3 IS DISTINCT FROM src.Quantity_Lower_Bound_3
      OR dim.Quantity_Price_3  IS DISTINCT FROM src.Quantity_Price_3
      OR dim.Quantity_Lower_Bound_4 IS DISTINCT FROM src.Quantity_Lower_Bound_4
      OR dim.Quantity_Price_4  IS DISTINCT FROM src.Quantity_Price_4
      OR dim.Quantity_Lower_Bound_5 IS DISTINCT FROM src.Quantity_Lower_Bound_5
      OR dim.Quantity_Price_5  IS DISTINCT FROM src.Quantity_Price_5
    );

  SET closed_count = @@row_count;

  -- Step 2: Insert new versions for changed rows + entirely new listings
  -- For NEW listings (not in DIM yet): effective_from = earliest_report_date
  -- For CHANGED listings (already in DIM, just closed): effective_from = current ReportstartDate
  INSERT INTO `onyga-482313.OI.DIM_LISTING_HISTORY` (
    sellingPartnerId, marketplaceId, listing_id, seller_sku, asin1, fulfillment_channel,
    marketplaceName,
    price, Business_Price, Quantity_Price_Type,
    Quantity_Lower_Bound_1, Quantity_Price_1,
    Quantity_Lower_Bound_2, Quantity_Price_2,
    Quantity_Lower_Bound_3, Quantity_Price_3,
    Quantity_Lower_Bound_4, Quantity_Price_4,
    Quantity_Lower_Bound_5, Quantity_Price_5,
    effective_from, effective_to, is_current
  )
  SELECT
    src.sellingPartnerId,
    src.marketplaceId,
    src.listing_id,
    src.seller_sku,
    src.asin1,
    src.fulfillment_channel,
    src.marketplaceName,
    src.price,
    src.Business_Price,
    src.Quantity_Price_Type,
    src.Quantity_Lower_Bound_1,
    src.Quantity_Price_1,
    src.Quantity_Lower_Bound_2,
    src.Quantity_Price_2,
    src.Quantity_Lower_Bound_3,
    src.Quantity_Price_3,
    src.Quantity_Lower_Bound_4,
    src.Quantity_Price_4,
    src.Quantity_Lower_Bound_5,
    src.Quantity_Price_5,
    -- New listings: use earliest known date; changed listings: use current date
    CASE
      WHEN NOT EXISTS (
        SELECT 1 FROM `onyga-482313.OI.DIM_LISTING_HISTORY` dim2
        WHERE dim2.sellingPartnerId = src.sellingPartnerId
          AND dim2.marketplaceId    = src.marketplaceId
          AND dim2.listing_id       = src.listing_id
          AND dim2.seller_sku       = src.seller_sku
          AND dim2.asin1            = src.asin1
          AND dim2.fulfillment_channel = src.fulfillment_channel
      )
      THEN src.earliest_report_date
      ELSE src.eff_from
    END AS effective_from,
    CAST(NULL AS DATETIME) AS effective_to,
    TRUE AS is_current
  FROM _src_listing src
  WHERE NOT EXISTS (
    SELECT 1
    FROM `onyga-482313.OI.DIM_LISTING_HISTORY` dim
    WHERE dim.sellingPartnerId = src.sellingPartnerId
      AND dim.marketplaceId    = src.marketplaceId
      AND dim.listing_id       = src.listing_id
      AND dim.seller_sku       = src.seller_sku
      AND dim.asin1            = src.asin1
      AND dim.fulfillment_channel = src.fulfillment_channel
      AND dim.is_current = TRUE
      AND dim.price                IS NOT DISTINCT FROM src.price
      AND dim.Business_Price       IS NOT DISTINCT FROM src.Business_Price
      AND dim.Quantity_Price_Type   IS NOT DISTINCT FROM src.Quantity_Price_Type
      AND dim.Quantity_Lower_Bound_1 IS NOT DISTINCT FROM src.Quantity_Lower_Bound_1
      AND dim.Quantity_Price_1     IS NOT DISTINCT FROM src.Quantity_Price_1
      AND dim.Quantity_Lower_Bound_2 IS NOT DISTINCT FROM src.Quantity_Lower_Bound_2
      AND dim.Quantity_Price_2     IS NOT DISTINCT FROM src.Quantity_Price_2
      AND dim.Quantity_Lower_Bound_3 IS NOT DISTINCT FROM src.Quantity_Lower_Bound_3
      AND dim.Quantity_Price_3     IS NOT DISTINCT FROM src.Quantity_Price_3
      AND dim.Quantity_Lower_Bound_4 IS NOT DISTINCT FROM src.Quantity_Lower_Bound_4
      AND dim.Quantity_Price_4     IS NOT DISTINCT FROM src.Quantity_Price_4
      AND dim.Quantity_Lower_Bound_5 IS NOT DISTINCT FROM src.Quantity_Lower_Bound_5
      AND dim.Quantity_Price_5     IS NOT DISTINCT FROM src.Quantity_Price_5
  );

  SET inserted_count = @@row_count;

  DROP TABLE IF EXISTS _src_listing;

  SELECT FORMAT(
    'SP_LOAD_DIM_LISTING_HISTORY completed: Closed %d rows, Inserted %d rows, Duration: %d seconds',
    closed_count, inserted_count,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND)
  ) as operation_summary;
END;
