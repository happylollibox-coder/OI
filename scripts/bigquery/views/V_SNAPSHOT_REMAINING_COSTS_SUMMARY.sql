-- =============================================
-- Snapshot Summary View: Aggregated Remaining Costs
-- =============================================
-- 
-- Aggregated summary of remaining costs by snapshot date
-- Shows totals for remaining manufactured, shipments, and estimations
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_SNAPSHOT_REMAINING_COSTS_SUMMARY` AS

SELECT 
  snapshot_date,
  year,
  month,
  month_key,
  is_current_date,
  is_month_end,
  
  -- Counts
  COUNT(DISTINCT purchase_order_id) AS total_purchase_orders,
  COUNT(DISTINCT shipment_id) AS total_shipments,
  
  -- Remaining Quantities
  SUM(remaining_quantity_to_ship_as_of_snapshot) AS total_remaining_quantity_to_ship,
  
  -- Remaining Costs (by currency)
  SUM(CASE WHEN currency = 'USD' THEN remaining_manufactured_cost ELSE 0 END) AS remaining_manufactured_cost_usd,
  SUM(CASE WHEN currency = 'USD' THEN remaining_shipments_cost ELSE 0 END) AS remaining_shipments_cost_usd,
  SUM(CASE WHEN currency = 'USD' THEN remaining_shipments_estimated_cost ELSE 0 END) AS remaining_shipments_estimated_cost_usd,
  
  SUM(CASE WHEN currency != 'USD' THEN remaining_manufactured_cost ELSE 0 END) AS remaining_manufactured_cost_other,
  SUM(CASE WHEN currency != 'USD' THEN remaining_shipments_cost ELSE 0 END) AS remaining_shipments_cost_other,
  SUM(CASE WHEN currency != 'USD' THEN remaining_shipments_estimated_cost ELSE 0 END) AS remaining_shipments_estimated_cost_other,
  
  -- Total Remaining Costs
  SUM(remaining_manufactured_cost) AS total_remaining_manufactured_cost,
  SUM(remaining_shipments_cost) AS total_remaining_shipments_cost,
  SUM(remaining_shipments_estimated_cost) AS total_remaining_shipments_estimated_cost,
  
  -- Grand Total
  SUM(remaining_manufactured_cost + remaining_shipments_cost + remaining_shipments_estimated_cost) AS total_remaining_costs

FROM `onyga-482313.OI.V_SNAPSHOT_REMAINING_COSTS`
GROUP BY 
  snapshot_date,
  year,
  month,
  month_key,
  is_current_date,
  is_month_end
ORDER BY 
  snapshot_date DESC;
