-- SQL script to update estimated_arrival_date for all existing shipments
-- Based on shipment_type and shipment_date:
--   SLOW_SEA: shipment_date + 33 days
--   FAST_SEA: shipment_date + 27 days
--   AIR: shipment_date + 10 days

-- Run this in BigQuery console or via bq command line

UPDATE `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS`
SET estimated_arrival_date = 
  CASE 
    WHEN shipment_type = 'SLOW_SEA' THEN DATE_ADD(shipment_date, INTERVAL 33 DAY)
    WHEN shipment_type = 'FAST_SEA' THEN DATE_ADD(shipment_date, INTERVAL 27 DAY)
    WHEN shipment_type = 'AIR' THEN DATE_ADD(shipment_date, INTERVAL 10 DAY)
    ELSE estimated_arrival_date  -- Keep existing value if type doesn't match
  END
WHERE shipment_date IS NOT NULL 
  AND shipment_type IS NOT NULL
  AND shipment_type IN ('SLOW_SEA', 'FAST_SEA', 'AIR');

-- Check results
SELECT 
  shipment_id,
  shipment_date,
  shipment_type,
  estimated_arrival_date,
  DATE_DIFF(estimated_arrival_date, shipment_date, DAY) as days_difference
FROM `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS`
WHERE shipment_date IS NOT NULL 
  AND shipment_type IS NOT NULL
  AND shipment_type IN ('SLOW_SEA', 'FAST_SEA', 'AIR')
ORDER BY shipment_date DESC
LIMIT 20;
