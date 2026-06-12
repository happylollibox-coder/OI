DECLARE v_fast_sea INT64 DEFAULT 30;
DECLARE v_slow_sea INT64 DEFAULT 45;
DECLARE v_awd_slow_sea INT64 DEFAULT 45;
DECLARE v_plan_lead INT64 DEFAULT 14;
DECLARE v_next_ship_wed DATE DEFAULT DATE_ADD(CURRENT_DATE(), INTERVAL MOD(11 - EXTRACT(DAYOFWEEK FROM CURRENT_DATE()), 7) + 1 DAY);

CREATE TEMP TABLE tmp_forecast AS SELECT * FROM `onyga-482313.OI.V_PLAN_FORECAST` WHERE product = 'Fresh in Blue';

CREATE TEMP TABLE tmp_products AS
SELECT
  p.product, p.asin, p.fba_stock, p.awd_stock, p.in_transit,
  p.available_stock, p.proportional_daily_demand,
  p.days_until_oos, p.emergency_priority, p.is_emergency,
  p.ready_to_ship, p.in_production, p.manufacture_day,
  p.supply_status, p.demand_90d, p.q4_demand, p.forecasted_sep1_pipeline, p.yearly_plan, p.ytd_sold,
  p.effective_growth, p.package_quantity,
  GREATEST(0, p.yearly_plan - p.ytd_sold - p.fba_stock - p.awd_stock - p.in_transit) AS total_shipment_budget,
  GREATEST(0, COALESCE(dw.demand_emergency, 0) - (COALESCE(c1.committed_qty, 0) + COALESCE(c2.committed_qty, 0))) AS demand_emergency,
  GREATEST(0, COALESCE(dw.demand_awd_maint, 0) - COALESCE(c3.committed_qty, 0)) AS demand_awd_maint,
  po_dates.po_ready_date,
  (COALESCE(c1.committed_qty, 0) + COALESCE(c2.committed_qty, 0)) AS committed_emergency,
  COALESCE(c3.committed_qty, 0) AS committed_awd,
  COALESCE(c4.committed_qty, 0) AS committed_q4
FROM tmp_forecast p
LEFT JOIN (
  SELECT fd.product,
    SUM(ROUND(fd.forecast_units * eg.growth) *
      GREATEST(0, DATE_DIFF(
        LEAST(DATE_ADD(CURRENT_DATE(), INTERVAL (v_slow_sea + 30 + 14 + 30) DAY), DATE_ADD(DATE(fd.forecast_year, fd.forecast_month, 1), INTERVAL 1 MONTH)),
        GREATEST(DATE_ADD(CURRENT_DATE(), INTERVAL v_fast_sea DAY), DATE(fd.forecast_year, fd.forecast_month, 1)),
        DAY)) / DATE_DIFF(DATE_ADD(DATE(fd.forecast_year, fd.forecast_month, 1), INTERVAL 1 MONTH), DATE(fd.forecast_year, fd.forecast_month, 1), DAY)
    ) AS demand_emergency,
    SUM(ROUND(fd.forecast_units * eg.growth) *
      GREATEST(0, DATE_DIFF(
        LEAST(DATE_ADD(CURRENT_DATE(), INTERVAL (v_slow_sea + 30 + 14 + 30 + 50) DAY), DATE_ADD(DATE(fd.forecast_year, fd.forecast_month, 1), INTERVAL 1 MONTH)),
        GREATEST(DATE_ADD(CURRENT_DATE(), INTERVAL (v_slow_sea + 30 + 14 + 30) DAY), DATE(fd.forecast_year, fd.forecast_month, 1)),
        DAY)) / DATE_DIFF(DATE_ADD(DATE(fd.forecast_year, fd.forecast_month, 1), INTERVAL 1 MONTH), DATE(fd.forecast_year, fd.forecast_month, 1), DAY)
    ) AS demand_awd_maint
  FROM `onyga-482313.OI.FACT_FORECAST_DEMAND` fd
  JOIN (SELECT product, effective_growth AS growth FROM tmp_forecast) eg ON fd.product = eg.product
  WHERE DATE_ADD(DATE(fd.forecast_year, fd.forecast_month, 1), INTERVAL 1 MONTH) > CURRENT_DATE()
    AND DATE(fd.forecast_year, fd.forecast_month, 1) < DATE_ADD(CURRENT_DATE(), INTERVAL 200 DAY)
  GROUP BY fd.product
) dw ON p.product = dw.product
LEFT JOIN (
  SELECT dp.asin, MIN(DATE_ADD(po.order_date, INTERVAL dp.manufacture_day DAY)) AS po_ready_date
  FROM `onyga-482313.OI.DE_PURCHASE_ORDERS` po
  JOIN `onyga-482313.OI.DIM_PRODUCT` dp ON dp.asin = po.product_asin
  LEFT JOIN (SELECT purchase_order_id, SUM(quantity_shipped) AS qty FROM `onyga-482313.OI.DE_SHIPMENT_LINES` GROUP BY 1) sh ON sh.purchase_order_id = po.purchase_order_id
  WHERE po.quantity - COALESCE(sh.qty, 0) > 0 AND DATE_DIFF(CURRENT_DATE(), po.order_date, DAY) < dp.manufacture_day
  GROUP BY dp.asin
) po_dates ON p.asin = po_dates.asin
LEFT JOIN (SELECT product, SUM(ship_qty) AS committed_qty FROM `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS` WHERE status IN ('APPROVED', 'SCHEDULED') AND shipment_type = 1 GROUP BY 1) c1 ON p.product = c1.product
LEFT JOIN (SELECT product, SUM(ship_qty) AS committed_qty FROM `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS` WHERE status IN ('APPROVED', 'SCHEDULED') AND shipment_type = 2 GROUP BY 1) c2 ON p.product = c2.product
LEFT JOIN (SELECT product, SUM(ship_qty) AS committed_qty FROM `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS` WHERE status IN ('APPROVED', 'SCHEDULED') AND shipment_type = 3 GROUP BY 1) c3 ON p.product = c3.product
LEFT JOIN (SELECT product, SUM(ship_qty) AS committed_qty FROM `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS` WHERE status IN ('APPROVED', 'SCHEDULED') AND shipment_type = 4 GROUP BY 1) c4 ON p.product = c4.product;

CREATE TEMP TABLE tmp_budget_pool AS SELECT product, total_shipment_budget AS remaining_budget FROM tmp_products;
CREATE TEMP TABLE tmp_mfr_pool AS SELECT product, ready_to_ship AS remaining_ready, in_production AS remaining_in_prod FROM tmp_products;

CREATE TEMP TABLE tmp_type1_ready AS
SELECT p.product, CAST(FLOOR(LEAST(pool.remaining_ready, ROUND(p.demand_emergency), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) * GREATEST(COALESCE(p.package_quantity, 1), 1) AS INT64) AS ship_qty
FROM tmp_products p JOIN tmp_mfr_pool pool ON p.product = pool.product JOIN tmp_budget_pool budget ON p.product = budget.product
WHERE p.is_emergency = TRUE AND pool.remaining_ready > 0 AND p.demand_emergency > 0
  AND FLOOR(LEAST(pool.remaining_ready, ROUND(p.demand_emergency), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) > 0;

UPDATE tmp_budget_pool budget SET budget.remaining_budget = budget.remaining_budget - t1.ship_qty FROM tmp_type1_ready t1 WHERE budget.product = t1.product;

CREATE TEMP TABLE tmp_type1_inprod AS
SELECT p.product, CAST(FLOOR(LEAST(pool.remaining_in_prod, ROUND(p.demand_emergency), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) * GREATEST(COALESCE(p.package_quantity, 1), 1) AS INT64) AS ship_qty
FROM tmp_products p JOIN tmp_mfr_pool pool ON p.product = pool.product JOIN tmp_budget_pool budget ON p.product = budget.product
WHERE p.is_emergency = TRUE AND pool.remaining_in_prod > 0 AND p.demand_emergency > 0
  AND FLOOR(LEAST(pool.remaining_in_prod, ROUND(p.demand_emergency), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) > 0;

UPDATE tmp_budget_pool budget SET budget.remaining_budget = budget.remaining_budget - t1.ship_qty FROM tmp_type1_inprod t1 WHERE budget.product = t1.product;

SELECT 'After Type1' AS step, * FROM tmp_budget_pool;
