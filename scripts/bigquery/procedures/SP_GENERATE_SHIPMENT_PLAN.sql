-- SP_GENERATE_SHIPMENT_PLAN: Cascading shipment allocation engine
-- Reads demand from V_PLAN_FORECAST (Invariant #9: single source of truth)
-- Carton rounding: ship_qty is FLOOR'd to full cartons (package_quantity from DIM_PRODUCT)
-- Transit days from DE_LIST_OF_VALUES (Invariant #10: no hardcoded values)
--
-- Deduplication: Reads DE_SCHEDULED_SHIPMENTS (APPROVED + SCHEDULED)
-- and deducts committed quantities before generating suggestions.
--
-- Cascade order:
--   Type 1: EMERGENCY — MFR→FBA via FAST_SEA using existing mfr_ready
--   Type 2: EMERGENCY (NEW PO NEEDED) — new PO for shortfall → MFR→FBA via FAST_SEA
--   Type 3: AWD_MAINTENANCE — remaining mfr_ready → AWD via SLOW_SEA
--   Type 4: Q4_BULK — remaining + future production → AWD via AWD_SLOW_SEA
--
-- Priority = shipment_type_base + CEIL(weeks_to_OOS)
--   Type 1 = 100, Type 2 = 200, Type 3 = 300, Type 4 = 400
--
-- Output: Writes SUGGESTED rows to DE_SCHEDULED_SHIPMENTS (clears old SUGGESTED, preserves APPROVED/SCHEDULED/SHIPPED)

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_GENERATE_SHIPMENT_PLAN`()
BEGIN
  DECLARE v_fast_sea INT64;
  DECLARE v_slow_sea INT64;
  DECLARE v_awd_slow_sea INT64;
  DECLARE v_awd_fba_buffer INT64 DEFAULT 5;
  DECLARE v_plan_lead INT64 DEFAULT 6;
  DECLARE v_next_ship_wed DATE;

  SET v_fast_sea = (SELECT CAST(attr1_value AS INT64) FROM `onyga-482313.OI.DE_LIST_OF_VALUES` WHERE lov_set = 'SHIPMENT_TYPE' AND value_id = 'FAST_SEA');
  SET v_slow_sea = (SELECT CAST(attr1_value AS INT64) FROM `onyga-482313.OI.DE_LIST_OF_VALUES` WHERE lov_set = 'SHIPMENT_TYPE' AND value_id = 'SLOW_SEA');
  SET v_awd_slow_sea = (SELECT CAST(attr1_value AS INT64) FROM `onyga-482313.OI.DE_LIST_OF_VALUES` WHERE lov_set = 'SHIPMENT_TYPE' AND value_id = 'AWD_SLOW_SEA');

  -- Next Wednesday: if today is Wednesday, ship today; otherwise find the soonest Wednesday
  SET v_next_ship_wed = DATE_ADD(
    CURRENT_DATE(),
    INTERVAL MOD(11 - EXTRACT(DAYOFWEEK FROM CURRENT_DATE()), 7) DAY
  );

  -- ============================================================
  -- 0. Load committed shipments (APPROVED + SCHEDULED) for deduplication
  -- ============================================================

  -- 0.5 Merge duplicate APPROVED shipments (same product, type, date)
  -- This ensures that if a user approves two split shipments, they are consolidated
  CREATE TEMP TABLE tmp_merged_approved AS
  SELECT 
    MIN(schedule_id) as schedule_id,
    product, asin, shipment_type, shipment_type_name, route, transit_type, transit_days, priority,
    SUM(ship_qty) as ship_qty, SUM(ship_cartons) as ship_cartons,
    amazon_plan_date, arrival_date,
    MAX(shipment_num) as shipment_num,
    MAX(status) as status
  FROM `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS`
  WHERE status = 'APPROVED'
  GROUP BY product, asin, shipment_type, shipment_type_name, route, transit_type, transit_days, priority, amazon_plan_date, arrival_date
  HAVING COUNT(*) > 1;

  IF (SELECT COUNT(*) FROM tmp_merged_approved) > 0 THEN
    -- Delete the unmerged ones
    DELETE FROM `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS` 
    WHERE status = 'APPROVED' 
      AND FORMAT('%s-%d-%t', product, shipment_type, amazon_plan_date) IN (
        SELECT FORMAT('%s-%d-%t', product, shipment_type, amazon_plan_date) FROM tmp_merged_approved
      );

    -- Insert the merged ones
    INSERT INTO `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS` (
      schedule_id, product, asin, shipment_type, shipment_type_name, route, transit_type, transit_days, priority,
      ship_qty, ship_cartons, amazon_plan_date, arrival_date, shipment_num, status
    )
    SELECT schedule_id, product, asin, shipment_type, shipment_type_name, route, transit_type, transit_days, priority,
      ship_qty, ship_cartons, amazon_plan_date, arrival_date, shipment_num, status
    FROM tmp_merged_approved;
  END IF;
  DROP TABLE IF EXISTS tmp_merged_approved;

  -- ============================================================
  -- 0.6 Auto-reschedule past-due APPROVED shipments
  -- If ship_wednesday < TODAY and no real shipment was created,
  -- push dates forward to next available Wednesday.
  -- ============================================================
  UPDATE `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS`
  SET
    ship_wednesday = v_next_ship_wed,
    amazon_plan_date = DATE_SUB(v_next_ship_wed, INTERVAL v_plan_lead DAY),
    arrival_date = DATE_ADD(v_next_ship_wed, INTERVAL transit_days DAY)
  WHERE status = 'APPROVED'
    AND ship_wednesday < CURRENT_DATE()
    AND (linked_shipment_id IS NULL OR linked_shipment_id = '');

  CREATE TEMP TABLE tmp_committed AS
  SELECT product, shipment_type,
    SUM(ship_qty) AS committed_qty
  FROM `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS`
  WHERE status IN ('APPROVED', 'SCHEDULED')
  GROUP BY product, shipment_type;

  -- ============================================================
  -- 1. Materialize complex views via dynamic SQL to avoid BigQuery query planner limits
  -- ============================================================
  EXECUTE IMMEDIATE 'CREATE TEMP TABLE tmp_forecast AS SELECT * FROM `onyga-482313.OI.V_PLAN_FORECAST`';

  -- ============================================================
  -- 2. Base product data + demand windows + PO ready date
  -- ============================================================
  CREATE TEMP TABLE tmp_products AS
  SELECT
    p.product, p.asin, p.fba_stock, p.awd_stock, p.in_transit,
    p.available_stock, p.proportional_daily_demand,
    p.days_until_oos, p.emergency_priority, p.is_emergency,
    p.ready_to_ship, p.in_production, p.manufacture_day,
    p.supply_status, p.demand_90d, p.q4_demand, p.forecasted_sep1_pipeline, p.yearly_plan, p.ytd_sold,
    p.effective_growth, p.package_quantity, p.share_carton_in_family,
    -- Total shipment budget: what we still need to send to Amazon to hit the yearly plan
    GREATEST(0, p.yearly_plan - p.ytd_sold - p.fba_stock - p.awd_stock - p.in_transit - (COALESCE(c1.committed_qty, 0) + COALESCE(c2.committed_qty, 0) + COALESCE(c3.committed_qty, 0) + COALESCE(c4.committed_qty, 0))) AS total_shipment_budget,
    -- Reduce demand by committed qty per type
    GREATEST(0, COALESCE(dw.demand_emergency, 0) - (COALESCE(c1.committed_qty, 0) + COALESCE(c2.committed_qty, 0))) AS demand_emergency,
    GREATEST(0, COALESCE(dw.demand_awd_maint, 0) - COALESCE(c3.committed_qty, 0)) AS demand_awd_maint,
    po_dates.po_ready_date,
    -- Track committed for reason text
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
    -- Earliest in-production PO ready date per ASIN
    SELECT dp.asin,
      MIN(COALESCE(po.estimated_arrival_date, DATE_ADD(po.order_date, INTERVAL dp.manufacture_day DAY))) AS po_ready_date
    FROM `onyga-482313.OI.DE_PURCHASE_ORDERS` po
    JOIN `onyga-482313.OI.DIM_PRODUCT` dp ON dp.asin = po.product_asin
    LEFT JOIN (SELECT purchase_order_id, SUM(quantity_shipped) AS qty FROM `onyga-482313.OI.DE_SHIPMENT_LINES` GROUP BY 1) sh ON sh.purchase_order_id = po.purchase_order_id
    WHERE po.quantity - COALESCE(sh.qty, 0) > 0
      AND CURRENT_DATE() < COALESCE(po.estimated_arrival_date, DATE_ADD(po.order_date, INTERVAL dp.manufacture_day DAY))
    GROUP BY dp.asin
  ) po_dates ON p.asin = po_dates.asin
  -- Committed qty per type for deduction
  LEFT JOIN tmp_committed c1 ON p.product = c1.product AND c1.shipment_type = 1
  LEFT JOIN tmp_committed c2 ON p.product = c2.product AND c2.shipment_type = 2
  LEFT JOIN tmp_committed c3 ON p.product = c3.product AND c3.shipment_type = 3
  LEFT JOIN tmp_committed c4 ON p.product = c4.product AND c4.shipment_type = 4
  WHERE (p.daily_rate > 0 OR dw.demand_emergency > 0 OR dw.demand_awd_maint > 0 OR p.q4_demand > 0);

  -- ============================================================
  -- 2a. OOS Cannibalization: boost healthy variant demand when siblings are OOS or near-OOS
  -- Near-OOS = days_until_oos <= 30; Healthy = days_until_oos > 30
  -- Rule: uplift = MIN(20% of own q4_demand, 20% of family OOS combined q4_demand)
  -- ============================================================
  UPDATE tmp_products p
  SET
    q4_demand = p.q4_demand + cannibal.uplift,
    demand_90d = p.demand_90d + ROUND(cannibal.uplift * 90.0 / 180), -- spread Q4 uplift proportionally
    proportional_daily_demand = (p.demand_90d + ROUND(cannibal.uplift * 90.0 / 180)) / 90.0
  FROM (
    SELECT
      alive.product,
      CAST(LEAST(
        alive.q4_demand * 0.20,
        oos_fam.oos_q4_total * 0.20
      ) AS INT64) AS uplift
    FROM tmp_products alive
    JOIN `onyga-482313.OI.DIM_PRODUCT` dp_alive ON dp_alive.product_short_name = alive.product
    JOIN (
      -- Sum of Q4 demand from OOS siblings within the same family
      SELECT dp.product_type AS family,
        SUM(dead.q4_demand) AS oos_q4_total,
        COUNT(*) AS oos_count
      FROM tmp_products dead
      JOIN `onyga-482313.OI.DIM_PRODUCT` dp ON dp.product_short_name = dead.product
      WHERE dead.days_until_oos <= 30
      GROUP BY dp.product_type
    ) oos_fam ON dp_alive.product_type = oos_fam.family
    WHERE alive.days_until_oos > 30  -- only boost healthy variants (not near-OOS themselves)
      AND alive.q4_demand > 0
  ) cannibal
  WHERE p.product = cannibal.product AND cannibal.uplift > 0;

  -- ============================================================
  -- 2b. Mfr pool tracker — also deduct committed emergency qty from pool
  -- ============================================================
  CREATE TEMP TABLE tmp_mfr_pool AS
  SELECT p.product,
    GREATEST(0, p.ready_to_ship - COALESCE(ce.committed_qty, 0)) AS remaining_ready,
    p.in_production AS remaining_in_prod
  FROM tmp_products p
  LEFT JOIN (
    SELECT product, SUM(committed_qty) AS committed_qty
    FROM tmp_committed
    WHERE shipment_type IN (1, 3) -- Types 1 and 3 consume mfr_ready
    GROUP BY product
  ) ce ON p.product = ce.product;

  -- ============================================================
  -- 2b. Budget pool tracker
  -- ============================================================
  CREATE TEMP TABLE tmp_budget_pool AS
  SELECT p.product,
    p.total_shipment_budget AS remaining_budget
  FROM tmp_products p;

  -- ================================================================
  -- TYPE 1A: EMERGENCY — mfr_ready → FBA via FAST_SEA
  -- ================================================================
  CREATE TEMP TABLE tmp_type1_ready AS
  SELECT
    p.product, p.asin, 1 AS shipment_type, 'EMERGENCY' AS shipment_type_name,
    'MFR→FBA' AS route, 
    CASE WHEN p.days_until_oos < 45 THEN 'FAST_SEA' ELSE 'SLOW_SEA' END AS transit_type, 
    CASE WHEN p.days_until_oos < 45 THEN v_fast_sea ELSE v_slow_sea END AS transit_days,
    100 + CAST(CEIL(GREATEST(0, p.days_until_oos) / 7.0) AS INT64) AS priority,
    p.days_until_oos,
    DATE_ADD(CURRENT_DATE(), INTERVAL p.days_until_oos DAY) AS oos_date,
    DATE_ADD(CURRENT_DATE(), INTERVAL CAST(p.days_until_oos - CASE WHEN p.days_until_oos < 45 THEN v_fast_sea ELSE v_slow_sea END AS INT64) DAY) AS last_day_to_ship,
    CASE 
      WHEN p.share_carton_in_family = TRUE THEN CAST(LEAST(pool.remaining_ready, ROUND(p.demand_emergency), budget.remaining_budget) AS INT64)
      ELSE CAST(FLOOR(LEAST(pool.remaining_ready, ROUND(p.demand_emergency), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) * GREATEST(COALESCE(p.package_quantity, 1), 1) AS INT64)
    END AS ship_qty,
    CASE 
      WHEN p.share_carton_in_family = TRUE THEN CAST(CEIL(LEAST(pool.remaining_ready, ROUND(p.demand_emergency), budget.remaining_budget) / CAST(GREATEST(COALESCE(p.package_quantity, 1), 1) AS FLOAT64)) AS INT64)
      ELSE CAST(FLOOR(LEAST(pool.remaining_ready, ROUND(p.demand_emergency), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) AS INT64)
    END AS ship_cartons,
    pool.remaining_ready AS mfr_ready_before,
    p.in_production,
    0 AS prior_type_allocations,
    FALSE AS needs_new_po, CAST(NULL AS INT64) AS new_po_qty,
    p.po_ready_date,
    v_next_ship_wed AS ship_wednesday,
    DATE_SUB(v_next_ship_wed, INTERVAL v_plan_lead DAY) AS amazon_plan_date,
    DATE_ADD(v_next_ship_wed, INTERVAL CASE WHEN p.days_until_oos < 45 THEN v_fast_sea ELSE v_slow_sea END DAY) AS arrival_date,
    CAST(NULL AS INT64) AS shipment_num,
    p.available_stock, p.fba_stock, p.awd_stock, p.in_transit,
    ROUND(p.demand_emergency) AS demand_window,
    ROUND(p.demand_awd_maint) AS demand_awd_window,
    CASE WHEN p.committed_emergency > 0 THEN
      FORMAT('DOC %dd < 90d threshold. %d already committed. Remaining emergency demand: %d.',
        p.days_until_oos, p.committed_emergency, CAST(ROUND(p.demand_emergency) AS INT64))
    ELSE
      FORMAT('DOC %dd < 90d threshold. FBA: %d, AWD: %d, Transit: %d = %d available vs %d demand in 90d.',
        p.days_until_oos, p.fba_stock, p.awd_stock, p.in_transit, p.available_stock,
        CAST(p.demand_90d AS INT64))
    END AS shipment_trigger_reason,
    FORMAT('MIN(mfr_ready %d, emergency demand: %d) = %d units via %s %dd to FBA.',
      pool.remaining_ready, CAST(ROUND(p.demand_emergency) AS INT64),
      LEAST(pool.remaining_ready, CAST(ROUND(p.demand_emergency) AS INT64)),
      CASE WHEN p.days_until_oos < 45 THEN 'FAST_SEA' ELSE 'SLOW_SEA' END,
      CASE WHEN p.days_until_oos < 45 THEN v_fast_sea ELSE v_slow_sea END) AS ship_qty_reason
  FROM tmp_products p
  JOIN tmp_mfr_pool pool ON p.product = pool.product
  JOIN tmp_budget_pool budget ON p.product = budget.product
  WHERE p.is_emergency = TRUE AND pool.remaining_ready > 0 AND p.demand_emergency > 0
    AND CASE 
      WHEN p.share_carton_in_family = TRUE THEN CAST(LEAST(pool.remaining_ready, ROUND(p.demand_emergency), budget.remaining_budget) AS INT64)
      ELSE CAST(FLOOR(LEAST(pool.remaining_ready, ROUND(p.demand_emergency), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) AS INT64)
    END > 0;

  UPDATE tmp_mfr_pool pool SET pool.remaining_ready = pool.remaining_ready - t1.ship_qty
  FROM tmp_type1_ready t1 WHERE pool.product = t1.product;

  UPDATE tmp_products p SET p.demand_emergency = p.demand_emergency - t1.ship_qty
  FROM tmp_type1_ready t1 WHERE p.product = t1.product;

  UPDATE tmp_budget_pool budget SET budget.remaining_budget = budget.remaining_budget - t1.ship_qty
  FROM tmp_type1_ready t1 WHERE budget.product = t1.product;

  -- ================================================================
  -- TYPE 1B: EMERGENCY — in_production → FBA via FAST_SEA
  -- ================================================================
  CREATE TEMP TABLE tmp_type1_inprod AS
  SELECT
    p.product, p.asin, 1 AS shipment_type, 'EMERGENCY' AS shipment_type_name,
    'MFR→FBA' AS route, 
    CASE WHEN p.days_until_oos < 45 THEN 'FAST_SEA' ELSE 'SLOW_SEA' END AS transit_type, 
    CASE WHEN p.days_until_oos < 45 THEN v_fast_sea ELSE v_slow_sea END AS transit_days,
    101 + CAST(CEIL(GREATEST(0, p.days_until_oos) / 7.0) AS INT64) AS priority,
    p.days_until_oos,
    DATE_ADD(CURRENT_DATE(), INTERVAL p.days_until_oos DAY) AS oos_date,
    DATE_ADD(CURRENT_DATE(), INTERVAL CAST(p.days_until_oos - CASE WHEN p.days_until_oos < 45 THEN v_fast_sea ELSE v_slow_sea END AS INT64) DAY) AS last_day_to_ship,
    CASE 
      WHEN p.share_carton_in_family = TRUE THEN CAST(LEAST(pool.remaining_in_prod, ROUND(p.demand_emergency), budget.remaining_budget) AS INT64)
      ELSE CAST(FLOOR(LEAST(pool.remaining_in_prod, ROUND(p.demand_emergency), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) * GREATEST(COALESCE(p.package_quantity, 1), 1) AS INT64)
    END AS ship_qty,
    CASE 
      WHEN p.share_carton_in_family = TRUE THEN CAST(CEIL(LEAST(pool.remaining_in_prod, ROUND(p.demand_emergency), budget.remaining_budget) / CAST(GREATEST(COALESCE(p.package_quantity, 1), 1) AS FLOAT64)) AS INT64)
      ELSE CAST(FLOOR(LEAST(pool.remaining_in_prod, ROUND(p.demand_emergency), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) AS INT64)
    END AS ship_cartons,
    pool.remaining_ready AS mfr_ready_before,
    p.in_production,
    p.ready_to_ship - pool.remaining_ready AS prior_type_allocations,
    FALSE AS needs_new_po, CAST(NULL AS INT64) AS new_po_qty,
    p.po_ready_date,
    GREATEST(COALESCE(p.po_ready_date, v_next_ship_wed), v_next_ship_wed) AS ship_wednesday,
    DATE_SUB(GREATEST(COALESCE(p.po_ready_date, v_next_ship_wed), v_next_ship_wed), INTERVAL v_plan_lead DAY) AS amazon_plan_date,
    DATE_ADD(GREATEST(COALESCE(p.po_ready_date, v_next_ship_wed), v_next_ship_wed), INTERVAL CASE WHEN p.days_until_oos < 45 THEN v_fast_sea ELSE v_slow_sea END DAY) AS arrival_date,
    CAST(NULL AS INT64) AS shipment_num,
    p.available_stock, p.fba_stock, p.awd_stock, p.in_transit,
    ROUND(p.demand_emergency) AS demand_window,
    ROUND(p.demand_awd_maint) AS demand_awd_window,
    FORMAT('Emergency demand remains (%d). No mfr_ready left. Using in_production stock.', CAST(ROUND(p.demand_emergency) AS INT64)) AS shipment_trigger_reason,
    FORMAT('MIN(in_production %d, emergency demand: %d) = %d units via %s %dd to FBA upon PO completion.',
      pool.remaining_in_prod, CAST(ROUND(p.demand_emergency) AS INT64),
      LEAST(pool.remaining_in_prod, CAST(ROUND(p.demand_emergency) AS INT64)),
      CASE WHEN p.days_until_oos < 45 THEN 'FAST_SEA' ELSE 'SLOW_SEA' END,
      CASE WHEN p.days_until_oos < 45 THEN v_fast_sea ELSE v_slow_sea END) AS ship_qty_reason
  FROM tmp_products p
  JOIN tmp_mfr_pool pool ON p.product = pool.product
  JOIN tmp_budget_pool budget ON p.product = budget.product
  WHERE p.is_emergency = TRUE AND pool.remaining_in_prod > 0 AND p.demand_emergency > 0
    AND CASE 
      WHEN p.share_carton_in_family = TRUE THEN CAST(LEAST(pool.remaining_in_prod, ROUND(p.demand_emergency), budget.remaining_budget) AS INT64)
      ELSE CAST(FLOOR(LEAST(pool.remaining_in_prod, ROUND(p.demand_emergency), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) AS INT64)
    END > 0;

  UPDATE tmp_mfr_pool pool SET pool.remaining_in_prod = pool.remaining_in_prod - t1.ship_qty
  FROM tmp_type1_inprod t1 WHERE pool.product = t1.product;

  UPDATE tmp_products p SET p.demand_emergency = p.demand_emergency - t1.ship_qty
  FROM tmp_type1_inprod t1 WHERE p.product = t1.product;

  UPDATE tmp_budget_pool budget SET budget.remaining_budget = budget.remaining_budget - t1.ship_qty
  FROM tmp_type1_inprod t1 WHERE budget.product = t1.product;

  -- ================================================================
  -- TYPE 2: EMERGENCY PO
  -- ================================================================
  CREATE TEMP TABLE tmp_type2 AS
  SELECT
    p.product, p.asin, 2 AS shipment_type, 'EMERGENCY (NEW PO NEEDED)' AS shipment_type_name,
    'PO→MFR→FBA' AS route, 'FAST_SEA' AS transit_type, v_fast_sea AS transit_days,
    200 + CAST(CEIL(GREATEST(0, p.days_until_oos) / 7.0) AS INT64) AS priority,
    p.days_until_oos,
    DATE_ADD(CURRENT_DATE(), INTERVAL p.days_until_oos DAY) AS oos_date,
    DATE_ADD(CURRENT_DATE(), INTERVAL CAST(p.days_until_oos - v_fast_sea AS INT64) DAY) AS last_day_to_ship,
    CASE 
      WHEN p.share_carton_in_family = TRUE THEN CAST(LEAST(ROUND(p.demand_emergency), budget.remaining_budget) AS INT64)
      ELSE CAST(FLOOR(LEAST(ROUND(p.demand_emergency), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) * GREATEST(COALESCE(p.package_quantity, 1), 1) AS INT64)
    END AS ship_qty,
    CASE 
      WHEN p.share_carton_in_family = TRUE THEN CAST(CEIL(LEAST(ROUND(p.demand_emergency), budget.remaining_budget) / CAST(GREATEST(COALESCE(p.package_quantity, 1), 1) AS FLOAT64)) AS INT64)
      ELSE CAST(FLOOR(LEAST(ROUND(p.demand_emergency), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) AS INT64)
    END AS ship_cartons,
    pool.remaining_ready AS mfr_ready_before,
    p.in_production,
    p.ready_to_ship - pool.remaining_ready AS prior_type_allocations,
    TRUE AS needs_new_po,
    CAST(ROUND(p.demand_emergency) AS INT64) AS new_po_qty,
    p.po_ready_date,
    GREATEST(
      DATE_ADD(DATE_ADD(CURRENT_DATE(), INTERVAL p.manufacture_day DAY),
        INTERVAL MOD(11 - EXTRACT(DAYOFWEEK FROM DATE_ADD(CURRENT_DATE(), INTERVAL p.manufacture_day DAY)), 7) DAY),
      v_next_ship_wed) AS ship_wednesday,
    DATE_SUB(GREATEST(
      DATE_ADD(DATE_ADD(CURRENT_DATE(), INTERVAL p.manufacture_day DAY),
        INTERVAL MOD(11 - EXTRACT(DAYOFWEEK FROM DATE_ADD(CURRENT_DATE(), INTERVAL p.manufacture_day DAY)), 7) DAY),
      v_next_ship_wed), INTERVAL v_plan_lead DAY) AS amazon_plan_date,
    DATE_ADD(GREATEST(
      DATE_ADD(DATE_ADD(CURRENT_DATE(), INTERVAL p.manufacture_day DAY),
        INTERVAL MOD(11 - EXTRACT(DAYOFWEEK FROM DATE_ADD(CURRENT_DATE(), INTERVAL p.manufacture_day DAY)), 7) DAY),
      v_next_ship_wed), INTERVAL v_fast_sea DAY) AS arrival_date,
    CAST(NULL AS INT64) AS shipment_num,
    p.available_stock, p.fba_stock, p.awd_stock, p.in_transit,
    ROUND(p.demand_emergency) AS demand_window,
    ROUND(p.demand_awd_maint) AS demand_awd_window,
    FORMAT('Emergency demand %d remains. No mfr_ready and no production pipeline. New PO required.',
      CAST(ROUND(p.demand_emergency) AS INT64)) AS shipment_trigger_reason,
    FORMAT('Emergency shortfall: demand %d. New PO for %d, manufacture %dd then FAST_SEA %dd.',
      CAST(ROUND(p.demand_emergency) AS INT64),
      CAST(ROUND(p.demand_emergency) AS INT64),
      p.manufacture_day, v_fast_sea) AS ship_qty_reason
  FROM tmp_products p
  JOIN tmp_mfr_pool pool ON p.product = pool.product
  JOIN tmp_budget_pool budget ON p.product = budget.product
  WHERE p.is_emergency = TRUE
    AND CAST(ROUND(p.demand_emergency) AS INT64) > 0
    AND pool.remaining_ready = 0 AND pool.remaining_in_prod = 0
    AND CASE 
      WHEN p.share_carton_in_family = TRUE THEN CAST(LEAST(ROUND(p.demand_emergency), budget.remaining_budget) AS INT64)
      ELSE CAST(FLOOR(LEAST(ROUND(p.demand_emergency), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) AS INT64)
    END > 0;

  UPDATE tmp_products p SET p.demand_emergency = p.demand_emergency - t2.ship_qty
  FROM tmp_type2 t2 WHERE p.product = t2.product;

  UPDATE tmp_budget_pool budget SET budget.remaining_budget = budget.remaining_budget - t2.ship_qty
  FROM tmp_type2 t2 WHERE budget.product = t2.product;

  -- ================================================================
  -- TYPE 3A: AWD MAINTENANCE — mfr_ready → AWD via SLOW_SEA
  -- ================================================================
  CREATE TEMP TABLE tmp_type3_ready AS
  SELECT
    p.product, p.asin, 3 AS shipment_type, 'AWD_MAINTENANCE' AS shipment_type_name,
    'MFR→AWD' AS route, 'AWD_SLOW_SEA' AS transit_type, v_awd_slow_sea AS transit_days,
    300 + CAST(CEIL(GREATEST(0, p.days_until_oos) / 7.0) AS INT64) AS priority,
    p.days_until_oos,
    DATE_ADD(CURRENT_DATE(), INTERVAL p.days_until_oos DAY) AS oos_date,
    DATE_ADD(CURRENT_DATE(), INTERVAL CAST(p.days_until_oos - v_awd_slow_sea - v_awd_fba_buffer AS INT64) DAY) AS last_day_to_ship,
    CASE 
      WHEN p.share_carton_in_family = TRUE THEN CAST(LEAST(pool.remaining_ready, ROUND(p.demand_awd_maint), budget.remaining_budget) AS INT64)
      ELSE CAST(FLOOR(LEAST(pool.remaining_ready, ROUND(p.demand_awd_maint), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) * GREATEST(COALESCE(p.package_quantity, 1), 1) AS INT64)
    END AS ship_qty,
    CASE 
      WHEN p.share_carton_in_family = TRUE THEN CAST(CEIL(LEAST(pool.remaining_ready, ROUND(p.demand_awd_maint), budget.remaining_budget) / CAST(GREATEST(COALESCE(p.package_quantity, 1), 1) AS FLOAT64)) AS INT64)
      ELSE CAST(FLOOR(LEAST(pool.remaining_ready, ROUND(p.demand_awd_maint), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) AS INT64)
    END AS ship_cartons,
    pool.remaining_ready AS mfr_ready_before,
    p.in_production,
    p.ready_to_ship - pool.remaining_ready AS prior_type_allocations,
    FALSE AS needs_new_po, CAST(NULL AS INT64) AS new_po_qty,
    p.po_ready_date,
    v_next_ship_wed AS ship_wednesday,
    DATE_SUB(v_next_ship_wed, INTERVAL v_plan_lead DAY) AS amazon_plan_date,
    DATE_ADD(v_next_ship_wed, INTERVAL v_awd_slow_sea DAY) AS arrival_date,
    CAST(NULL AS INT64) AS shipment_num,
    p.available_stock, p.fba_stock, p.awd_stock, p.in_transit,
    ROUND(p.demand_emergency) AS demand_window,
    ROUND(p.demand_awd_maint) AS demand_awd_window,
    CASE WHEN p.committed_awd > 0 THEN
      FORMAT('AWD stock %d = %dd DOC (< 50d). %d already committed AWD. Remaining AWD demand: %d.',
        p.awd_stock,
        CASE WHEN p.proportional_daily_demand > 0 THEN CAST(ROUND(p.awd_stock / p.proportional_daily_demand) AS INT64) ELSE 999 END,
        p.committed_awd, CAST(ROUND(p.demand_awd_maint) AS INT64))
    ELSE
      FORMAT('AWD stock %d = %dd DOC (< 50d threshold). Refill needed for next 50 days after SLOW_SEA arrival.',
        p.awd_stock,
        CASE WHEN p.proportional_daily_demand > 0
          THEN CAST(ROUND(p.awd_stock / p.proportional_daily_demand) AS INT64) ELSE 999 END)
    END AS shipment_trigger_reason,
    FORMAT('MIN(remaining mfr_ready %d after emergency, AWD demand d%d–d%d: %d) = %d units via AWD_SLOW_SEA %dd to AWD.',
        pool.remaining_ready, v_awd_slow_sea, v_awd_slow_sea + 50,
        CAST(ROUND(p.demand_awd_maint) AS INT64),
        LEAST(pool.remaining_ready, CAST(ROUND(p.demand_awd_maint) AS INT64)), v_awd_slow_sea) AS ship_qty_reason
  FROM tmp_products p
  JOIN tmp_mfr_pool pool ON p.product = pool.product
  JOIN tmp_budget_pool budget ON p.product = budget.product
  WHERE CASE WHEN p.proportional_daily_demand > 0
      THEN p.awd_stock / p.proportional_daily_demand < 50 ELSE TRUE END
    AND p.demand_awd_maint > 0 AND pool.remaining_ready > 0
    AND CASE 
      WHEN p.share_carton_in_family = TRUE THEN CAST(LEAST(pool.remaining_ready, ROUND(p.demand_awd_maint), budget.remaining_budget) AS INT64)
      ELSE CAST(FLOOR(LEAST(pool.remaining_ready, ROUND(p.demand_awd_maint), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) AS INT64)
    END > 0;

  UPDATE tmp_mfr_pool pool SET pool.remaining_ready = pool.remaining_ready - t3.ship_qty
  FROM tmp_type3_ready t3 WHERE pool.product = t3.product;

  UPDATE tmp_products p SET p.demand_awd_maint = p.demand_awd_maint - t3.ship_qty
  FROM tmp_type3_ready t3 WHERE p.product = t3.product;

  UPDATE tmp_budget_pool budget SET budget.remaining_budget = budget.remaining_budget - t3.ship_qty
  FROM tmp_type3_ready t3 WHERE budget.product = t3.product;

  -- ================================================================
  -- TYPE 3B: AWD MAINTENANCE — in_production → AWD via SLOW_SEA
  -- ================================================================
  CREATE TEMP TABLE tmp_type3_inprod AS
  SELECT
    p.product, p.asin, 3 AS shipment_type, 'AWD_MAINTENANCE' AS shipment_type_name,
    'MFR→AWD' AS route, 'AWD_SLOW_SEA' AS transit_type, v_awd_slow_sea AS transit_days,
    301 + CAST(CEIL(GREATEST(0, p.days_until_oos) / 7.0) AS INT64) AS priority,
    p.days_until_oos,
    DATE_ADD(CURRENT_DATE(), INTERVAL p.days_until_oos DAY) AS oos_date,
    DATE_ADD(CURRENT_DATE(), INTERVAL CAST(p.days_until_oos - v_awd_slow_sea - v_awd_fba_buffer AS INT64) DAY) AS last_day_to_ship,
    CASE 
      WHEN p.share_carton_in_family = TRUE THEN CAST(LEAST(pool.remaining_in_prod, ROUND(p.demand_awd_maint), budget.remaining_budget) AS INT64)
      ELSE CAST(FLOOR(LEAST(pool.remaining_in_prod, ROUND(p.demand_awd_maint), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) * GREATEST(COALESCE(p.package_quantity, 1), 1) AS INT64)
    END AS ship_qty,
    CASE 
      WHEN p.share_carton_in_family = TRUE THEN CAST(CEIL(LEAST(pool.remaining_in_prod, ROUND(p.demand_awd_maint), budget.remaining_budget) / CAST(GREATEST(COALESCE(p.package_quantity, 1), 1) AS FLOAT64)) AS INT64)
      ELSE CAST(FLOOR(LEAST(pool.remaining_in_prod, ROUND(p.demand_awd_maint), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) AS INT64)
    END AS ship_cartons,
    pool.remaining_ready AS mfr_ready_before,
    p.in_production,
    p.ready_to_ship - pool.remaining_ready AS prior_type_allocations,
    FALSE AS needs_new_po, CAST(NULL AS INT64) AS new_po_qty,
    p.po_ready_date,
    GREATEST(COALESCE(p.po_ready_date, v_next_ship_wed), v_next_ship_wed) AS ship_wednesday,
    DATE_SUB(GREATEST(COALESCE(p.po_ready_date, v_next_ship_wed), v_next_ship_wed), INTERVAL v_plan_lead DAY) AS amazon_plan_date,
    DATE_ADD(GREATEST(COALESCE(p.po_ready_date, v_next_ship_wed), v_next_ship_wed), INTERVAL v_awd_slow_sea DAY) AS arrival_date,
    CAST(NULL AS INT64) AS shipment_num,
    p.available_stock, p.fba_stock, p.awd_stock, p.in_transit,
    ROUND(p.demand_emergency) AS demand_window,
    ROUND(p.demand_awd_maint) AS demand_awd_window,
    FORMAT('AWD demand remains (%d). No mfr_ready left. Using in_production stock.', CAST(ROUND(p.demand_awd_maint) AS INT64)) AS shipment_trigger_reason,
    FORMAT('MIN(remaining in_production %d, AWD demand %d) = %d units via AWD_SLOW_SEA %dd to AWD upon PO completion.',
        pool.remaining_in_prod, CAST(ROUND(p.demand_awd_maint) AS INT64),
        LEAST(pool.remaining_in_prod, CAST(ROUND(p.demand_awd_maint) AS INT64)), v_awd_slow_sea) AS ship_qty_reason
  FROM tmp_products p
  JOIN tmp_mfr_pool pool ON p.product = pool.product
  JOIN tmp_budget_pool budget ON p.product = budget.product
  WHERE CASE WHEN p.proportional_daily_demand > 0
      THEN p.awd_stock / p.proportional_daily_demand < 50 ELSE TRUE END
    AND p.demand_awd_maint > 0 AND pool.remaining_in_prod > 0
    AND CASE 
      WHEN p.share_carton_in_family = TRUE THEN CAST(LEAST(pool.remaining_in_prod, ROUND(p.demand_awd_maint), budget.remaining_budget) AS INT64)
      ELSE CAST(FLOOR(LEAST(pool.remaining_in_prod, ROUND(p.demand_awd_maint), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) AS INT64)
    END > 0;

  UPDATE tmp_mfr_pool pool SET pool.remaining_in_prod = pool.remaining_in_prod - t3.ship_qty
  FROM tmp_type3_inprod t3 WHERE pool.product = t3.product;

  UPDATE tmp_products p SET p.demand_awd_maint = p.demand_awd_maint - t3.ship_qty
  FROM tmp_type3_inprod t3 WHERE p.product = t3.product;

  UPDATE tmp_budget_pool budget SET budget.remaining_budget = budget.remaining_budget - t3.ship_qty
  FROM tmp_type3_inprod t3 WHERE budget.product = t3.product;

  -- ================================================================
  -- TYPE 3C: AWD MAINTENANCE — New PO Needed
  -- ================================================================
  CREATE TEMP TABLE tmp_type3_po AS
  SELECT
    p.product, p.asin, 3 AS shipment_type, 'AWD_MAINTENANCE' AS shipment_type_name,
    'PO→MFR→AWD' AS route, 'AWD_SLOW_SEA' AS transit_type, v_awd_slow_sea AS transit_days,
    302 + CAST(CEIL(GREATEST(0, p.days_until_oos) / 7.0) AS INT64) AS priority,
    p.days_until_oos,
    DATE_ADD(CURRENT_DATE(), INTERVAL p.days_until_oos DAY) AS oos_date,
    DATE_ADD(CURRENT_DATE(), INTERVAL CAST(p.days_until_oos - v_awd_slow_sea - v_awd_fba_buffer AS INT64) DAY) AS last_day_to_ship,
    CASE 
      WHEN p.share_carton_in_family = TRUE THEN CAST(LEAST(ROUND(p.demand_awd_maint), budget.remaining_budget) AS INT64)
      ELSE CAST(FLOOR(LEAST(ROUND(p.demand_awd_maint), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) * GREATEST(COALESCE(p.package_quantity, 1), 1) AS INT64)
    END AS ship_qty,
    CASE 
      WHEN p.share_carton_in_family = TRUE THEN CAST(CEIL(LEAST(ROUND(p.demand_awd_maint), budget.remaining_budget) / CAST(GREATEST(COALESCE(p.package_quantity, 1), 1) AS FLOAT64)) AS INT64)
      ELSE CAST(FLOOR(LEAST(ROUND(p.demand_awd_maint), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) AS INT64)
    END AS ship_cartons,
    pool.remaining_ready AS mfr_ready_before,
    p.in_production,
    p.ready_to_ship - pool.remaining_ready AS prior_type_allocations,
    TRUE AS needs_new_po,
    CAST(ROUND(p.demand_awd_maint) AS INT64) AS new_po_qty,
    p.po_ready_date,
    GREATEST(DATE_ADD(DATE_ADD(CURRENT_DATE(), INTERVAL p.manufacture_day DAY),
      INTERVAL MOD(11 - EXTRACT(DAYOFWEEK FROM DATE_ADD(CURRENT_DATE(), INTERVAL p.manufacture_day DAY)), 7) DAY), v_next_ship_wed) AS ship_wednesday,
    DATE_SUB(GREATEST(DATE_ADD(DATE_ADD(CURRENT_DATE(), INTERVAL p.manufacture_day DAY),
      INTERVAL MOD(11 - EXTRACT(DAYOFWEEK FROM DATE_ADD(CURRENT_DATE(), INTERVAL p.manufacture_day DAY)), 7) DAY), v_next_ship_wed), INTERVAL v_plan_lead DAY) AS amazon_plan_date,
    DATE_ADD(GREATEST(DATE_ADD(DATE_ADD(CURRENT_DATE(), INTERVAL p.manufacture_day DAY),
      INTERVAL MOD(11 - EXTRACT(DAYOFWEEK FROM DATE_ADD(CURRENT_DATE(), INTERVAL p.manufacture_day DAY)), 7) DAY), v_next_ship_wed), INTERVAL v_awd_slow_sea DAY) AS arrival_date,
    CAST(NULL AS INT64) AS shipment_num,
    p.available_stock, p.fba_stock, p.awd_stock, p.in_transit,
    ROUND(p.demand_emergency) AS demand_window,
    ROUND(p.demand_awd_maint) AS demand_awd_window,
    FORMAT('AWD demand %d remains. No mfr_ready and no production pipeline. New PO required.', CAST(ROUND(p.demand_awd_maint) AS INT64)) AS shipment_trigger_reason,
    FORMAT('AWD shortfall: demand %d. New PO for %d, manufacture %dd then AWD_SLOW_SEA %dd.',
        CAST(ROUND(p.demand_awd_maint) AS INT64), CAST(ROUND(p.demand_awd_maint) AS INT64), p.manufacture_day, v_awd_slow_sea) AS ship_qty_reason
  FROM tmp_products p
  JOIN tmp_mfr_pool pool ON p.product = pool.product
  JOIN tmp_budget_pool budget ON p.product = budget.product
  WHERE CASE WHEN p.proportional_daily_demand > 0
      THEN p.awd_stock / p.proportional_daily_demand < 50 ELSE TRUE END
    AND p.demand_awd_maint > 0 AND pool.remaining_ready = 0 AND pool.remaining_in_prod = 0
    AND CASE 
      WHEN p.share_carton_in_family = TRUE THEN CAST(LEAST(ROUND(p.demand_awd_maint), budget.remaining_budget) AS INT64)
      ELSE CAST(FLOOR(LEAST(ROUND(p.demand_awd_maint), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) AS INT64)
    END > 0;

  UPDATE tmp_products p SET p.demand_awd_maint = p.demand_awd_maint - t3.ship_qty
  FROM tmp_type3_po t3 WHERE p.product = t3.product;

  UPDATE tmp_budget_pool budget SET budget.remaining_budget = budget.remaining_budget - t3.ship_qty
  FROM tmp_type3_po t3 WHERE budget.product = t3.product;

  -- ================================================================
  -- TYPE 4: Q4 BULK — deduct committed Q4 from demand
  -- ================================================================
  CREATE TEMP TABLE tmp_type4 AS
  WITH q4_wed AS (
    SELECT d AS ship_date, DATE_SUB(d, INTERVAL 6 DAY) AS amazon_plan_date,
      ROW_NUMBER() OVER (ORDER BY d) AS shipment_num
    FROM UNNEST(GENERATE_DATE_ARRAY(
      DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 6, 1),
      DATE(EXTRACT(YEAR FROM CURRENT_DATE()), 8, 20), INTERVAL 1 DAY)) d
    WHERE EXTRACT(DAYOFWEEK FROM d) = 4
  ),
  q4_cnt AS (SELECT COUNT(*) AS n FROM q4_wed)
  SELECT
    p.product, p.asin, 4 AS shipment_type, 'Q4_BULK' AS shipment_type_name,
    'MFR→AWD' AS route, 'AWD_SLOW_SEA' AS transit_type, v_awd_slow_sea AS transit_days,
    400 + CAST(CEIL(GREATEST(0, p.days_until_oos) / 7.0) AS INT64) AS priority,
    p.days_until_oos,
    DATE_ADD(CURRENT_DATE(), INTERVAL p.days_until_oos DAY) AS oos_date,
    CAST(NULL AS DATE) AS last_day_to_ship,
        CASE
      WHEN p.share_carton_in_family = TRUE THEN
        CAST((
          FLOOR(CAST(LEAST(GREATEST(0, p.q4_demand - p.committed_q4 - p.forecasted_sep1_pipeline), budget.remaining_budget) AS INT64) / c.n)
          + IF(w.shipment_num <= MOD(CAST(LEAST(GREATEST(0, p.q4_demand - p.committed_q4 - p.forecasted_sep1_pipeline), budget.remaining_budget) AS INT64), c.n), 1, 0)
        ) AS INT64)
      ELSE
        CAST((
          FLOOR(CAST(CEIL(LEAST(GREATEST(0, p.q4_demand - p.committed_q4 - p.forecasted_sep1_pipeline), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) AS INT64) / c.n)
          + IF(w.shipment_num <= MOD(CAST(CEIL(LEAST(GREATEST(0, p.q4_demand - p.committed_q4 - p.forecasted_sep1_pipeline), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) AS INT64), c.n), 1, 0)
        ) * GREATEST(COALESCE(p.package_quantity, 1), 1) AS INT64)
    END AS ship_qty,
    CASE
      WHEN p.share_carton_in_family = TRUE THEN
        CAST(CEIL((
          FLOOR(CAST(LEAST(GREATEST(0, p.q4_demand - p.committed_q4 - p.forecasted_sep1_pipeline), budget.remaining_budget) AS INT64) / c.n)
          + IF(w.shipment_num <= MOD(CAST(LEAST(GREATEST(0, p.q4_demand - p.committed_q4 - p.forecasted_sep1_pipeline), budget.remaining_budget) AS INT64), c.n), 1, 0)
        ) / CAST(GREATEST(COALESCE(p.package_quantity, 1), 1) AS FLOAT64)) AS INT64)
      ELSE
        CAST(
          FLOOR(CAST(CEIL(LEAST(GREATEST(0, p.q4_demand - p.committed_q4 - p.forecasted_sep1_pipeline), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) AS INT64) / c.n)
          + IF(w.shipment_num <= MOD(CAST(CEIL(LEAST(GREATEST(0, p.q4_demand - p.committed_q4 - p.forecasted_sep1_pipeline), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) AS INT64), c.n), 1, 0)
        AS INT64)
    END AS ship_cartons,
    pool.remaining_ready AS mfr_ready_before,
    p.in_production,
    p.ready_to_ship - pool.remaining_ready AS prior_type_allocations,
    (pool.remaining_ready + pool.remaining_in_prod) < LEAST(GREATEST(0, p.q4_demand - p.committed_q4 - p.forecasted_sep1_pipeline), budget.remaining_budget) AS needs_new_po,
    CASE WHEN (pool.remaining_ready + pool.remaining_in_prod) < LEAST(GREATEST(0, p.q4_demand - p.committed_q4 - p.forecasted_sep1_pipeline), budget.remaining_budget)
      THEN CAST(LEAST(GREATEST(0, p.q4_demand - p.committed_q4 - p.forecasted_sep1_pipeline), budget.remaining_budget) AS INT64) - pool.remaining_ready - pool.remaining_in_prod ELSE NULL END AS new_po_qty,
    p.po_ready_date,
    w.ship_date AS ship_wednesday, w.amazon_plan_date,
    DATE_ADD(w.ship_date, INTERVAL v_awd_slow_sea DAY) AS arrival_date,
    CAST(w.shipment_num AS INT64) AS shipment_num,
    p.available_stock, p.fba_stock, p.awd_stock, p.in_transit,
    ROUND(p.demand_emergency) AS demand_window,
    ROUND(p.demand_awd_maint) AS demand_awd_window,
    FORMAT('Q4 peak (Jun–Aug). Q4 demand: %d, forecasted Sep1 pipeline: %d, committed: %d, net remaining: %d. Split into %d shipments.',
      CAST(p.q4_demand AS INT64), CAST(p.forecasted_sep1_pipeline AS INT64), p.committed_q4,
      CAST(GREATEST(0, p.q4_demand - p.committed_q4 - p.forecasted_sep1_pipeline) AS INT64), c.n)
    AS shipment_trigger_reason,
    FORMAT('Q4 net remaining %d (demand %d - forecasted Sep1 pipeline %d - committed %d) / %d weeks = %d/ship. MFR: %d ready + %d in prod.',
      CAST(LEAST(GREATEST(0, p.q4_demand - p.committed_q4 - p.forecasted_sep1_pipeline), budget.remaining_budget) AS INT64),
      CAST(p.q4_demand AS INT64), CAST(p.forecasted_sep1_pipeline AS INT64), p.committed_q4, c.n,
      CAST(CEIL(LEAST(GREATEST(0, p.q4_demand - p.committed_q4 - p.forecasted_sep1_pipeline), budget.remaining_budget) / c.n) AS INT64),
      pool.remaining_ready, pool.remaining_in_prod) AS ship_qty_reason
  FROM tmp_products p
  CROSS JOIN q4_wed w CROSS JOIN q4_cnt c
  JOIN tmp_mfr_pool pool ON p.product = pool.product
  JOIN tmp_budget_pool budget ON p.product = budget.product
  WHERE LEAST(GREATEST(0, p.q4_demand - p.committed_q4 - p.forecasted_sep1_pipeline), budget.remaining_budget) >= GREATEST(COALESCE(p.package_quantity, 1), 1) * 2
    AND CASE
      WHEN p.share_carton_in_family = TRUE THEN CAST(LEAST(GREATEST(0, p.q4_demand - p.committed_q4 - p.forecasted_sep1_pipeline), budget.remaining_budget) AS INT64)
      ELSE CAST(FLOOR(LEAST(GREATEST(0, p.q4_demand - p.committed_q4 - p.forecasted_sep1_pipeline), budget.remaining_budget) / GREATEST(COALESCE(p.package_quantity, 1), 1)) AS INT64)
    END > 0
    AND w.ship_date >= CURRENT_DATE()
    -- Exclude weeks that already have an APPROVED Q4 shipment for this product
    AND NOT EXISTS (
      SELECT 1 FROM `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS` ex
      WHERE ex.product = p.product AND ex.shipment_type = 4
        AND ex.status = 'APPROVED' AND ex.ship_wednesday = w.ship_date
    );

  -- ── Q4 BULK post-processing: push dates based on stock availability ──
  -- If cumulative Q4 demand exceeds MFR pool (ready + in_prod),
  -- those shipments must wait for a new PO to be manufactured.
  UPDATE tmp_type4 t4
  SET
    ship_wednesday = adj.adjusted_wed,
    amazon_plan_date = DATE_SUB(adj.adjusted_wed, INTERVAL v_plan_lead DAY),
    arrival_date = DATE_ADD(adj.adjusted_wed, INTERVAL t4.transit_days DAY)
  FROM (
    SELECT
      t.product, t.shipment_num,
      SUM(t.ship_qty) OVER (PARTITION BY t.product ORDER BY t.shipment_num) AS cumulative_qty,
      pool.remaining_ready + pool.remaining_in_prod AS available_now,
      -- Push to whichever is later: original date or new-PO-ready Wednesday
      GREATEST(
        t.ship_wednesday,
        DATE_ADD(
          DATE_ADD(CURRENT_DATE(), INTERVAL p.manufacture_day DAY),
          INTERVAL MOD(11 - EXTRACT(DAYOFWEEK FROM DATE_ADD(CURRENT_DATE(), INTERVAL p.manufacture_day DAY)), 7) DAY
        )
      ) AS adjusted_wed
    FROM tmp_type4 t
    JOIN tmp_mfr_pool pool ON t.product = pool.product
    JOIN tmp_products p ON t.product = p.product
  ) adj
  WHERE t4.product = adj.product AND t4.shipment_num = adj.shipment_num
    AND adj.cumulative_qty > adj.available_now
    AND adj.adjusted_wed > t4.ship_wednesday;

  UPDATE tmp_mfr_pool pool SET pool.remaining_ready = pool.remaining_ready - t4.total_ship_qty
  FROM (SELECT product, SUM(ship_qty) AS total_ship_qty FROM tmp_type4 GROUP BY 1) t4 
  WHERE pool.product = t4.product AND pool.remaining_ready > 0;

  UPDATE tmp_mfr_pool pool SET pool.remaining_in_prod = pool.remaining_in_prod - t4.total_ship_qty
  FROM (SELECT product, SUM(ship_qty) AS total_ship_qty FROM tmp_type4 GROUP BY 1) t4 
  WHERE pool.product = t4.product AND pool.remaining_ready = 0 AND pool.remaining_in_prod > 0;

  UPDATE tmp_budget_pool budget SET budget.remaining_budget = budget.remaining_budget - t4.total_ship_qty
  FROM (SELECT product, SUM(ship_qty) AS total_ship_qty FROM tmp_type4 GROUP BY 1) t4 
  WHERE budget.product = t4.product;

  -- ============================================================
  -- OUTPUT: Write SUGGESTED rows to DE_SCHEDULED_SHIPMENTS
  -- ============================================================
  -- 1. Clear old suggestions (preserve APPROVED/SCHEDULED/SHIPPED)
  DELETE FROM `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS` WHERE status = 'SUGGESTED';

  -- 2. Insert fresh suggestions with auto-generated IDs (broken into separate inserts to avoid query complexity limit)
  INSERT INTO `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS`
    (schedule_id, product, asin, shipment_type, shipment_type_name, route, transit_type,
     transit_days, priority, days_until_oos, ship_qty, ship_cartons,
     mfr_ready_before, in_production, prior_type_allocations, needs_new_po, new_po_qty, po_ready_date,
     ship_wednesday, amazon_plan_date, arrival_date, shipment_num,
     available_stock, fba_stock, awd_stock, in_transit, demand_window, demand_awd_window,
     shipment_trigger_reason, ship_qty_reason, status)
  SELECT
    GENERATE_UUID(), product, asin, shipment_type, shipment_type_name, route, transit_type,
    transit_days, priority, days_until_oos, ship_qty, ship_cartons,
    mfr_ready_before, in_production, prior_type_allocations, needs_new_po, new_po_qty, po_ready_date,
    ship_wednesday, amazon_plan_date, arrival_date, shipment_num,
    available_stock, fba_stock, awd_stock, in_transit, demand_window, demand_awd_window,
    shipment_trigger_reason, ship_qty_reason, 'SUGGESTED'
  FROM tmp_type1_ready WHERE ship_qty > 0;

  INSERT INTO `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS`
    (schedule_id, product, asin, shipment_type, shipment_type_name, route, transit_type,
     transit_days, priority, days_until_oos, ship_qty, ship_cartons,
     mfr_ready_before, in_production, prior_type_allocations, needs_new_po, new_po_qty, po_ready_date,
     ship_wednesday, amazon_plan_date, arrival_date, shipment_num,
     available_stock, fba_stock, awd_stock, in_transit, demand_window, demand_awd_window,
     shipment_trigger_reason, ship_qty_reason, status)
  SELECT GENERATE_UUID(), product, asin, shipment_type, shipment_type_name, route, transit_type, transit_days, priority, days_until_oos, ship_qty, ship_cartons, mfr_ready_before, in_production, prior_type_allocations, needs_new_po, new_po_qty, po_ready_date, ship_wednesday, amazon_plan_date, arrival_date, shipment_num, available_stock, fba_stock, awd_stock, in_transit, demand_window, demand_awd_window, shipment_trigger_reason, ship_qty_reason, 'SUGGESTED' FROM tmp_type1_inprod WHERE ship_qty > 0;

  INSERT INTO `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS`
    (schedule_id, product, asin, shipment_type, shipment_type_name, route, transit_type,
     transit_days, priority, days_until_oos, ship_qty, ship_cartons,
     mfr_ready_before, in_production, prior_type_allocations, needs_new_po, new_po_qty, po_ready_date,
     ship_wednesday, amazon_plan_date, arrival_date, shipment_num,
     available_stock, fba_stock, awd_stock, in_transit, demand_window, demand_awd_window,
     shipment_trigger_reason, ship_qty_reason, status)
  SELECT GENERATE_UUID(), product, asin, shipment_type, shipment_type_name, route, transit_type, transit_days, priority, days_until_oos, ship_qty, ship_cartons, mfr_ready_before, in_production, prior_type_allocations, needs_new_po, new_po_qty, po_ready_date, ship_wednesday, amazon_plan_date, arrival_date, shipment_num, available_stock, fba_stock, awd_stock, in_transit, demand_window, demand_awd_window, shipment_trigger_reason, ship_qty_reason, 'SUGGESTED' FROM tmp_type2 WHERE ship_qty > 0;

  INSERT INTO `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS`
    (schedule_id, product, asin, shipment_type, shipment_type_name, route, transit_type,
     transit_days, priority, days_until_oos, ship_qty, ship_cartons,
     mfr_ready_before, in_production, prior_type_allocations, needs_new_po, new_po_qty, po_ready_date,
     ship_wednesday, amazon_plan_date, arrival_date, shipment_num,
     available_stock, fba_stock, awd_stock, in_transit, demand_window, demand_awd_window,
     shipment_trigger_reason, ship_qty_reason, status)
  SELECT GENERATE_UUID(), product, asin, shipment_type, shipment_type_name, route, transit_type, transit_days, priority, days_until_oos, ship_qty, ship_cartons, mfr_ready_before, in_production, prior_type_allocations, needs_new_po, new_po_qty, po_ready_date, ship_wednesday, amazon_plan_date, arrival_date, shipment_num, available_stock, fba_stock, awd_stock, in_transit, demand_window, demand_awd_window, shipment_trigger_reason, ship_qty_reason, 'SUGGESTED' FROM tmp_type3_ready WHERE ship_qty > 0;

  INSERT INTO `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS`
    (schedule_id, product, asin, shipment_type, shipment_type_name, route, transit_type,
     transit_days, priority, days_until_oos, ship_qty, ship_cartons,
     mfr_ready_before, in_production, prior_type_allocations, needs_new_po, new_po_qty, po_ready_date,
     ship_wednesday, amazon_plan_date, arrival_date, shipment_num,
     available_stock, fba_stock, awd_stock, in_transit, demand_window, demand_awd_window,
     shipment_trigger_reason, ship_qty_reason, status)
  SELECT GENERATE_UUID(), product, asin, shipment_type, shipment_type_name, route, transit_type, transit_days, priority, days_until_oos, ship_qty, ship_cartons, mfr_ready_before, in_production, prior_type_allocations, needs_new_po, new_po_qty, po_ready_date, ship_wednesday, amazon_plan_date, arrival_date, shipment_num, available_stock, fba_stock, awd_stock, in_transit, demand_window, demand_awd_window, shipment_trigger_reason, ship_qty_reason, 'SUGGESTED' FROM tmp_type3_inprod WHERE ship_qty > 0;

  INSERT INTO `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS`
    (schedule_id, product, asin, shipment_type, shipment_type_name, route, transit_type,
     transit_days, priority, days_until_oos, ship_qty, ship_cartons,
     mfr_ready_before, in_production, prior_type_allocations, needs_new_po, new_po_qty, po_ready_date,
     ship_wednesday, amazon_plan_date, arrival_date, shipment_num,
     available_stock, fba_stock, awd_stock, in_transit, demand_window, demand_awd_window,
     shipment_trigger_reason, ship_qty_reason, status)
  SELECT GENERATE_UUID(), product, asin, shipment_type, shipment_type_name, route, transit_type, transit_days, priority, days_until_oos, ship_qty, ship_cartons, mfr_ready_before, in_production, prior_type_allocations, needs_new_po, new_po_qty, po_ready_date, ship_wednesday, amazon_plan_date, arrival_date, shipment_num, available_stock, fba_stock, awd_stock, in_transit, demand_window, demand_awd_window, shipment_trigger_reason, ship_qty_reason, 'SUGGESTED' FROM tmp_type3_po WHERE ship_qty > 0;

  INSERT INTO `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS`
    (schedule_id, product, asin, shipment_type, shipment_type_name, route, transit_type,
     transit_days, priority, days_until_oos, ship_qty, ship_cartons,
     mfr_ready_before, in_production, prior_type_allocations, needs_new_po, new_po_qty, po_ready_date,
     ship_wednesday, amazon_plan_date, arrival_date, shipment_num,
     available_stock, fba_stock, awd_stock, in_transit, demand_window, demand_awd_window,
     shipment_trigger_reason, ship_qty_reason, status)
  SELECT GENERATE_UUID(), product, asin, shipment_type, shipment_type_name, route, transit_type, transit_days, priority, days_until_oos, ship_qty, ship_cartons, mfr_ready_before, in_production, prior_type_allocations, needs_new_po, new_po_qty, po_ready_date, ship_wednesday, amazon_plan_date, arrival_date, shipment_num, available_stock, fba_stock, awd_stock, in_transit, demand_window, demand_awd_window, shipment_trigger_reason, ship_qty_reason, 'SUGGESTED' FROM tmp_type4 WHERE ship_qty > 0;

  DROP TABLE IF EXISTS tmp_products;
  DROP TABLE IF EXISTS tmp_forecast;
  DROP TABLE IF EXISTS tmp_mfr_pool;
  DROP TABLE IF EXISTS tmp_committed;
  DROP TABLE IF EXISTS tmp_type1_ready;
  DROP TABLE IF EXISTS tmp_type1_inprod;
  DROP TABLE IF EXISTS tmp_type2;
  DROP TABLE IF EXISTS tmp_type3_ready;
  DROP TABLE IF EXISTS tmp_type3_inprod;
  DROP TABLE IF EXISTS tmp_type3_po;
  DROP TABLE IF EXISTS tmp_type4;
END;
