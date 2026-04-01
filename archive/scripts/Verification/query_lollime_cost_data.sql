-- =============================================
-- Query LolliME Cost Data from DIM_PRODUCT
-- =============================================
-- Purpose: Retrieve complete cost and logistics data for LolliME products
-- Project: onyga-482313
-- Dataset: OI
-- Date: 2026-01-17
-- =============================================

-- Query 1: Complete LolliME Cost Data
SELECT 
  asin,
  parent_name,
  sku,
  cost_of_goods as COGS,
  shipping_cost,
  fba_cost,
  (cost_of_goods + shipping_cost + fba_cost) as total_cost,
  manufacture_day,
  shipment_days,
  (manufacture_day + shipment_days) as total_lead_time_days,
  listing_price_amount as list_price,
  CASE 
    WHEN listing_price_amount > 0 AND (cost_of_goods + shipping_cost + fba_cost) > 0 THEN 
      ROUND(((listing_price_amount - (cost_of_goods + shipping_cost + fba_cost)) / listing_price_amount) * 100, 2)
    ELSE NULL
  END as margin_percent,
  CASE 
    WHEN listing_price_amount > 0 AND (cost_of_goods + shipping_cost + fba_cost) > 0 THEN 
      ROUND(((listing_price_amount - (cost_of_goods + shipping_cost + fba_cost)) / listing_price_amount) * 100, 2)
    ELSE NULL
  END as break_even_acos_percent
FROM `onyga-482313.OI.DIM_PRODUCT`
WHERE parent_name = 'LolliME'
   OR asin IN ('B0F9XDSVYB', 'B0F9XFXQRW', 'B0F9X95K5H')
ORDER BY sku;
