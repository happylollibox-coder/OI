DECLARE v_fast_sea INT64 DEFAULT 25;
DECLARE v_slow_sea INT64 DEFAULT 55;
DECLARE v_plan_lead INT64 DEFAULT 6;
DECLARE v_next_ship_wed DATE;
SET v_next_ship_wed = DATE_ADD(DATE_ADD(CURRENT_DATE(), INTERVAL v_plan_lead DAY), INTERVAL MOD(11 - EXTRACT(DAYOFWEEK FROM DATE_ADD(CURRENT_DATE(), INTERVAL v_plan_lead DAY)), 7) DAY);

SELECT
  p.product,
  p.is_emergency,
  ROUND(dw.demand_emergency) AS demand_emergency,
  COALESCE(c1.committed_qty, 0) AS c1_committed_qty,
  GREATEST(0, ROUND(dw.demand_emergency) - COALESCE(c1.committed_qty, 0)) AS net_demand_emergency,
  COALESCE(p.package_quantity, 1) as pkg_qty,
  FLOOR((ROUND(dw.demand_emergency) - COALESCE(c1.committed_qty, 0)) / GREATEST(COALESCE(p.package_quantity, 1), 1)) AS cartons
FROM `onyga-482313.OI.V_SUPPLY_CHAIN_SUMMARY` sc
RIGHT JOIN `onyga-482313.OI.V_PLAN_FORECAST` p ON p.product = sc.product_short_name
LEFT JOIN (
  SELECT fd.product,
    SUM(ROUND(fd.forecast_units * eg.effective_growth) * GREATEST(0, DATE_DIFF(LEAST(DATE_ADD(CURRENT_DATE(), INTERVAL (55 + 30 + 14 + 30) DAY), DATE_ADD(DATE(fd.forecast_year, fd.forecast_month, 1), INTERVAL 1 MONTH)), GREATEST(DATE_ADD(CURRENT_DATE(), INTERVAL 25 DAY), DATE(fd.forecast_year, fd.forecast_month, 1)), DAY)) / DATE_DIFF(DATE_ADD(DATE(fd.forecast_year, fd.forecast_month, 1), INTERVAL 1 MONTH), DATE(fd.forecast_year, fd.forecast_month, 1), DAY)) AS demand_emergency
  FROM `onyga-482313.OI.FACT_FORECAST_DEMAND` fd
  JOIN `onyga-482313.OI.V_PLAN_FORECAST` eg ON fd.product = eg.product
  GROUP BY fd.product
) dw ON p.product = dw.product
LEFT JOIN (
  SELECT product, SUM(ship_qty) AS committed_qty FROM `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS` WHERE status IN ('APPROVED', 'SCHEDULED') AND shipment_type = 1 GROUP BY product
) c1 ON p.product = c1.product
WHERE p.product LIKE '%Bunny%';
