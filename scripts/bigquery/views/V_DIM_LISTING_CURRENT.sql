-- =============================================
-- OI Database Project - V_DIM_LISTING_CURRENT
-- =============================================
--
-- Purpose: Current listing pricing — one row per listing from SCD2 DIM_LISTING_HISTORY.
--          Convenience view filtering to is_current = TRUE.
-- Source: DIM_LISTING_HISTORY
-- Pattern: Same as V_DIM_CAMPAIGN_CURRENT
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_DIM_LISTING_CURRENT` AS
SELECT
  sellingPartnerId,
  marketplaceId,
  listing_id,
  seller_sku,
  asin1,
  fulfillment_channel,
  marketplaceName,
  price,
  Business_Price,
  Quantity_Price_Type,
  Quantity_Lower_Bound_1,
  Quantity_Price_1,
  Quantity_Lower_Bound_2,
  Quantity_Price_2,
  Quantity_Lower_Bound_3,
  Quantity_Price_3,
  Quantity_Lower_Bound_4,
  Quantity_Price_4,
  Quantity_Lower_Bound_5,
  Quantity_Price_5,
  effective_from,
  effective_to,
  is_current
FROM `onyga-482313.OI.DIM_LISTING_HISTORY`
WHERE is_current = TRUE;
