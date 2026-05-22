-- V_WEEKLY_STORAGE_COST
-- Assigns the monthly storage cost as a lump sum to the week containing the 10th of the following month.
-- Maps raw product_type to dashboard family names (Lollibox, LolliME, Fresh, Bottle)
CREATE OR REPLACE VIEW `onyga-482313.OI.V_WEEKLY_STORAGE_COST` AS
WITH monthly_totals AS (
  SELECT
    storage_month,
    asin,
    -- Map Amazon product_type to dashboard family name
    CASE product_type
      WHEN 'ACCESSORY' THEN 'Lollibox'
      WHEN 'ART_CRAFT_KIT' THEN 'LolliME'
      WHEN 'SKIN_CARE_AGENT' THEN 'Fresh'
      WHEN 'TABLETOP_GAME' THEN 'Bottle'
      WHEN 'GIFT_WRAP' THEN 'Lollibox'   -- gift wrap is Lollibox family
      ELSE product_type
    END AS product_type,
    SUM(storage_cost) AS monthly_storage_cost
  FROM `onyga-482313.OI.V_MONTHLY_STORAGE_COST`
  GROUP BY storage_month, asin, product_type
)
SELECT
  -- Shift cashflow to the week containing the 10th of the following month
  DATE_TRUNC(DATE_ADD(DATE_ADD(mt.storage_month, INTERVAL 1 MONTH), INTERVAL 9 DAY), WEEK(SUNDAY)) AS week_start_date,
  mt.asin,
  mt.product_type,
  -- Apply as a lump sum
  ROUND(mt.monthly_storage_cost, 2) AS weekly_storage_cost
FROM monthly_totals mt
WHERE mt.monthly_storage_cost > 0;
