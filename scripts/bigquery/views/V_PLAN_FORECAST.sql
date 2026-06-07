-- V_PLAN_FORECAST: Master supply chain forecast
-- Single source of truth for:
--   effectiveGrowth, adjustedForecast, gap, DOC, supply readiness,
--   demand windows (90-day, Q4), OOS timing, emergency priority
-- Consumed by: SP_GENERATE_ALERTS, V_SUPPLY_CHAIN_SUMMARY, V_SHIPMENT_PLAN, PlanPage (via Cube)
--
-- Key design decisions:
--   1. growth_json from saved plan is used as fallback when no yearly_plan override exists
--   2. demand_during_lead walks monthly forecasts proportionally (not flat daily rate)
--   3. Emergency check: available stock (FBA+AWD+transit) DOC < 90 days
--   4. Three-tier supply readiness: READY / IN_PRODUCTION / NEEDS_PO
--   5. Transit days sourced from DE_LIST_OF_VALUES (Invariant #10: no hardcoded values)
--
-- Dependencies:
--   V_FORECAST_DEMAND, DE_PLAN_STRATEGY, DIM_PRODUCT,
--   FACT_INVENTORY_SNAPSHOT, V_SRC_sales_and_traffic_business_sku_report_daily,
--   DE_PURCHASE_ORDERS, DE_SHIPMENT_LINES, V_ADS_EFFICIENCY_PROFILE,
--   V_PRODUCT_FAMILY_MAP
--
-- Invariant #8: All business logic in SQL. Frontend reads pre-computed values via Cube.js.

CREATE OR REPLACE VIEW `onyga-482313.OI.V_PLAN_FORECAST` AS

WITH latest_inv_date AS (
  SELECT MAX(Date) AS max_date FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`
),

plan_config AS (
  -- Resolve APPROVED vs DRAFT plan status
  SELECT COALESCE(
    (SELECT status FROM `onyga-482313.OI.DE_PLAN_STRATEGY`
     WHERE plan_year = EXTRACT(YEAR FROM CURRENT_DATE()) AND status = 'APPROVED' LIMIT 1),
    'DRAFT'
  ) AS plan_status
),

-- 1. Yearly plan overrides per product (from order_overrides_json)
overrides AS (
  SELECT DISTINCT
    REGEXP_EXTRACT(kv, r'"([^"]+)"') AS product,
    SAFE_CAST(REGEXP_EXTRACT(kv, r':(\d+)') AS INT64) AS yearly_plan
  FROM `onyga-482313.OI.DE_PLAN_STRATEGY` ps
  CROSS JOIN plan_config pc
  CROSS JOIN UNNEST(REGEXP_EXTRACT_ALL(ps.order_overrides_json, r'"[^"]+"\s*:\s*\d+')) kv
  WHERE ps.plan_year = EXTRACT(YEAR FROM CURRENT_DATE())
    AND ps.status = pc.plan_status
    AND ps.order_overrides_json IS NOT NULL
),

-- 1b. Per-product growth multiplier from saved plan (growth_json)
-- This captures user-set growth rates that may not have a yearly_plan override.
-- growth_json is the same JSON on every row; extract it once.
plan_growth AS (
  SELECT DISTINCT
    REGEXP_EXTRACT(kv, r'"([^"]+)"') AS product,
    SAFE_CAST(REGEXP_EXTRACT(kv, r':([\d.]+)') AS FLOAT64) AS growth_rate
  FROM (
    SELECT growth_json FROM `onyga-482313.OI.DE_PLAN_STRATEGY` ps
    CROSS JOIN plan_config pc
    WHERE ps.plan_year = EXTRACT(YEAR FROM CURRENT_DATE())
      AND ps.status = pc.plan_status
      AND ps.growth_json IS NOT NULL
    LIMIT 1
  ) gj
  CROSS JOIN UNNEST(REGEXP_EXTRACT_ALL(gj.growth_json, r'"[^"]+"\s*:\s*[\d.]+')) kv
),

-- 2. Monthly multipliers (use Lollibox family as reference — same across all families)
multipliers AS (
  SELECT forecast_month, multiplier
  FROM `onyga-482313.OI.DE_PLAN_STRATEGY` ps
  CROSS JOIN plan_config pc
  WHERE ps.plan_year = EXTRACT(YEAR FROM CURRENT_DATE())
    AND ps.status = pc.plan_status
    AND ps.family = 'Lollibox'
),

-- 3. YTD sales per product
ytd_sales AS (
  SELECT dp.product_short_name AS product, SUM(f.PURCHASED_UNITS) AS ytd_sold
  FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` f
  JOIN `onyga-482313.OI.DIM_PRODUCT` dp ON dp.asin = f.PURCHASED_ASIN
  WHERE f.DATE >= DATE_TRUNC(CURRENT_DATE(), YEAR) AND dp.is_active = TRUE AND dp.oi_is_active = TRUE
  GROUP BY 1
),

-- 3b. Last date with loaded sales data (anchor for 30d window)
last_loaded_date AS (
  SELECT MAX(DATE) AS last_date
  FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
  WHERE Performance_TYPE = 'Organic'
),

-- 3c. Last 30 days actual sales per product (anchored to last loaded date, not CURRENT_DATE)
last_30d_sales AS (
  SELECT dp.product_short_name AS product, SUM(f.PURCHASED_UNITS) AS last_30d_sold
  FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` f
  JOIN `onyga-482313.OI.DIM_PRODUCT` dp ON dp.asin = f.PURCHASED_ASIN
  CROSS JOIN last_loaded_date lld
  WHERE f.DATE BETWEEN DATE_SUB(lld.last_date, INTERVAL 30 DAY) AND lld.last_date
    AND dp.is_active = TRUE AND dp.oi_is_active = TRUE
  GROUP BY 1
),

-- 4. Total demand base = SUM(forecast_units × adjFactor) for remaining months
total_demand_base AS (
  SELECT fd.product,
    MAX(fd.forecast_phase) AS forecast_phase,
    SUM(fd.forecast_units * (0.5 + 0.5 * COALESCE(m.multiplier, 1.0))) AS demand_base
  FROM `onyga-482313.OI.V_FORECAST_DEMAND` fd
  LEFT JOIN multipliers m ON fd.forecast_month = m.forecast_month
  WHERE (fd.forecast_year = EXTRACT(YEAR FROM CURRENT_DATE()) AND fd.forecast_month >= EXTRACT(MONTH FROM CURRENT_DATE()))
     OR (fd.forecast_year = EXTRACT(YEAR FROM CURRENT_DATE()) + 1 AND fd.forecast_month <= 2)
  GROUP BY 1
),

-- 5. effectiveGrowth per product
-- Priority: yearly_plan override (back-calculated) → saved growth_json → 1.0
effective_growth AS (
  SELECT tdb.product,
    CASE
      WHEN o.yearly_plan IS NOT NULL AND tdb.demand_base > 0
        THEN GREATEST(o.yearly_plan - COALESCE(ys.ytd_sold, 0), 0) / tdb.demand_base
      WHEN pg.growth_rate IS NOT NULL
        THEN pg.growth_rate
      ELSE 1.0
    END AS growth,
    CASE
      WHEN tdb.forecast_phase IN ('PHASE_1', 'PHASE_2') AND o.yearly_plan IS NOT NULL AND tdb.demand_base > 0
        THEN GREATEST(o.yearly_plan - COALESCE(ys.ytd_sold, 0), 0) / tdb.demand_base
      ELSE COALESCE(pg.growth_rate, 1.0)
    END AS unconstrained_growth,
    tdb.demand_base
  FROM total_demand_base tdb
  LEFT JOIN overrides o ON tdb.product = o.product
  LEFT JOIN plan_growth pg ON tdb.product = pg.product
  LEFT JOIN ytd_sales ys ON tdb.product = ys.product
),

-- 6. Adjusted monthly forecast
monthly_forecast AS (
  SELECT fd.product, fd.forecast_year, fd.forecast_month,
    fd.forecast_units AS base_units,
    COALESCE(m.multiplier, 1.0) AS multiplier,
    eg.growth AS effective_growth,
    (0.5 + 0.5 * COALESCE(m.multiplier, 1.0)) AS adj_factor,
    ROUND(fd.forecast_units * eg.growth * (0.5 + 0.5 * COALESCE(m.multiplier, 1.0))) AS adjusted_units,
    ROUND(fd.forecast_units * eg.unconstrained_growth * (0.5 + 0.5 * COALESCE(m.multiplier, 1.0))) AS unconstrained_units
  FROM `onyga-482313.OI.FACT_FORECAST_DEMAND` fd
  JOIN effective_growth eg ON fd.product = eg.product
  LEFT JOIN multipliers m ON fd.forecast_month = m.forecast_month
  WHERE (fd.forecast_year = EXTRACT(YEAR FROM CURRENT_DATE()) AND fd.forecast_month >= EXTRACT(MONTH FROM CURRENT_DATE()))
     OR (fd.forecast_year = EXTRACT(YEAR FROM CURRENT_DATE()) + 1 AND fd.forecast_month <= 2)
),

-- 7. Daily rate for current month
daily_rates AS (
  SELECT product,
    COALESCE(SUM(CASE
      WHEN forecast_year = EXTRACT(YEAR FROM CURRENT_DATE())
        AND forecast_month = EXTRACT(MONTH FROM CURRENT_DATE())
      THEN adjusted_units / 30.0
    END), 0) AS daily_rate
  FROM monthly_forecast
  GROUP BY product
),

-- 7b. Launch signal: first-sale date, is_launching (<=60d), and own early run-rate.
-- For just-launched products the engine orders off their OWN trailing sales (widening window
-- MIN(days_since_launch, 30)), not the model forecast. >=3 selling days required before a rate is
-- trusted (else 0 -- the manual seed PO covers days 0-N). Mirrors last_30d_sales' join pattern.
launch_signal AS (
  SELECT
    fsd.product,
    fsd.first_sale_date,
    DATE_DIFF(fsd.last_date, fsd.first_sale_date, DAY) AS days_since_launch,
    CASE
      WHEN COALESCE(lw.launch_selling_days, 0) >= 3
      THEN lw.launch_units / LEAST(GREATEST(DATE_DIFF(fsd.last_date, fsd.first_sale_date, DAY), 1), 30)
      ELSE 0
    END AS launch_daily_rate,
    (fsd.first_sale_date IS NOT NULL
      AND DATE_DIFF(fsd.last_date, fsd.first_sale_date, DAY) BETWEEN 0 AND 60) AS is_launching
  FROM (
    SELECT dp.product_short_name AS product,
      ANY_VALUE(lld.last_date) AS last_date,
      COALESCE(MIN(fs.first_sale), MIN(dp.estimated_start_selling_date)) AS first_sale_date
    FROM `onyga-482313.OI.DIM_PRODUCT` dp
    CROSS JOIN last_loaded_date lld
    LEFT JOIN (
      SELECT dp2.product_short_name AS product, MIN(f.DATE) AS first_sale
      FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` f
      JOIN `onyga-482313.OI.DIM_PRODUCT` dp2 ON dp2.asin = f.PURCHASED_ASIN
      WHERE f.PURCHASED_UNITS > 0
      GROUP BY 1
    ) fs ON fs.product = dp.product_short_name
    WHERE dp.is_active = TRUE AND dp.oi_is_active = TRUE
    GROUP BY dp.product_short_name
  ) fsd
  LEFT JOIN (
    SELECT dp3.product_short_name AS product,
      SUM(f.PURCHASED_UNITS) AS launch_units,
      COUNT(DISTINCT f.DATE) AS launch_selling_days
    FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` f
    JOIN `onyga-482313.OI.DIM_PRODUCT` dp3 ON dp3.asin = f.PURCHASED_ASIN
    CROSS JOIN last_loaded_date lld2
    WHERE f.DATE BETWEEN DATE_SUB(lld2.last_date, INTERVAL 29 DAY) AND lld2.last_date
      AND f.PURCHASED_UNITS > 0
    GROUP BY 1
  ) lw ON lw.product = fsd.product
),

-- 8. Inventory snapshot (latest date)
inventory AS (
  SELECT
    dp.product_type AS family, dp.product_short_name AS product, dp.asin, dp.package_quantity, dp.min_manuf_quantity,
    dp.share_carton_in_family,
    dp.manufacture_day, dp.shipment_days, dp.estimated_start_selling_date,
    dp.manufacture_day + dp.shipment_days AS full_lead_days,
    COALESCE(SUM(CASE WHEN fi.source_type = 'FBA' THEN fi.quantity_balance END), 0) AS fba_stock,
    COALESCE(SUM(CASE WHEN fi.source_type = 'AWD' THEN fi.quantity_balance END), 0) AS awd_stock,
    COALESCE(SUM(CASE WHEN fi.source_type = 'In Transit' THEN fi.quantity_balance END), 0) AS in_transit,
    COALESCE(SUM(CASE WHEN fi.source_type IN ('MFR Ready', 'In Production', 'Manufacturer') THEN fi.quantity_balance END), 0) AS at_manufacturer,
    COALESCE(SUM(fi.quantity_balance), 0) AS total_stock,
    COALESCE(SUM(CASE WHEN fi.source_type = 'AWD' THEN fi.quantity_balance END), 0) > 0 AS is_awd_product
  FROM `onyga-482313.OI.DIM_PRODUCT` dp
  CROSS JOIN latest_inv_date lid
  LEFT JOIN `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT` fi
    ON dp.asin = fi.ASIN AND fi.Date = lid.max_date
  WHERE dp.is_active = TRUE AND dp.oi_is_active = TRUE AND dp.asin != 'UNKNOWN'
  GROUP BY 1,2,3,4,5,6,7,8,9
),

-- 9. Supply readiness: PO-level manufacturing status
po_readiness AS (
  SELECT
    dp.product_short_name AS product,
    po.purchase_order_id, po.order_date,
    dp.manufacture_day, dp.shipment_days,
    DATE_DIFF(CURRENT_DATE(), po.order_date, DAY) AS days_since_order,
    GREATEST(0, dp.manufacture_day - DATE_DIFF(CURRENT_DATE(), po.order_date, DAY)) AS days_until_ready,
    CASE 
      WHEN po.estimated_arrival_date IS NOT NULL AND CURRENT_DATE() >= po.estimated_arrival_date THEN po.quantity - COALESCE(shipped.qty, 0)
      WHEN po.estimated_arrival_date IS NULL AND DATE_DIFF(CURRENT_DATE(), po.order_date, DAY) >= dp.manufacture_day THEN po.quantity - COALESCE(shipped.qty, 0)
      ELSE COALESCE(po.ready_quantity, 0)
    END AS ready_qty,
    CASE
      WHEN po.estimated_arrival_date IS NOT NULL AND CURRENT_DATE() >= po.estimated_arrival_date THEN 0
      WHEN po.estimated_arrival_date IS NULL AND DATE_DIFF(CURRENT_DATE(), po.order_date, DAY) >= dp.manufacture_day THEN 0
      ELSE GREATEST(0, po.quantity - COALESCE(po.ready_quantity, 0) - COALESCE(shipped.qty, 0))
    END AS inprod_qty
  FROM `onyga-482313.OI.DE_PURCHASE_ORDERS` po
  JOIN `onyga-482313.OI.DIM_PRODUCT` dp ON dp.asin = po.product_asin
  LEFT JOIN (
    SELECT purchase_order_id, SUM(quantity_shipped) AS qty
    FROM `onyga-482313.OI.DE_SHIPMENT_LINES` GROUP BY 1
  ) shipped ON shipped.purchase_order_id = po.purchase_order_id
  WHERE po.quantity - COALESCE(shipped.qty, 0) > 0
),

-- 10. Aggregate supply tiers per product
supply_tiers AS (
  SELECT product,
    SUM(ready_qty) AS ready_to_ship,
    SUM(inprod_qty) AS in_production,
    MIN(CASE WHEN ready_qty > 0 THEN shipment_days END) AS ready_lead_days,
    MIN(CASE WHEN inprod_qty > 0 THEN days_until_ready + shipment_days END) AS production_lead_days
  FROM po_readiness
  GROUP BY product
),

-- 11. Effective lead days per product (pre-computed for lead_demand)
product_lead AS (
  SELECT inv2.product,
    CASE
      WHEN COALESCE(st2.ready_to_ship, 0) > 0 THEN st2.ready_lead_days
      WHEN COALESCE(st2.in_production, 0) > 0 THEN st2.production_lead_days
      ELSE inv2.full_lead_days
    END AS effective_lead_days
  FROM inventory inv2
  LEFT JOIN supply_tiers st2 ON inv2.product = st2.product
),

-- 12. Demand during lead time — walk monthly forecasts proportionally
-- Sums adjusted_units × (overlap_days / days_in_month) for each month
-- that overlaps with the [today, today + effective_lead_days] window.
lead_demand AS (
  SELECT mf.product,
    SUM(
      mf.adjusted_units *
      GREATEST(0,
        DATE_DIFF(
          LEAST(DATE_ADD(CURRENT_DATE(), INTERVAL pl.effective_lead_days DAY), mf.month_end),
          GREATEST(CURRENT_DATE(), mf.month_start),
          DAY
        )
      ) / DATE_DIFF(mf.month_end, mf.month_start, DAY)
    ) AS demand_during_lead
  FROM (
    SELECT product, adjusted_units,
      DATE(forecast_year, forecast_month, 1) AS month_start,
      DATE_ADD(DATE(forecast_year, forecast_month, 1), INTERVAL 1 MONTH) AS month_end
    FROM monthly_forecast
  ) mf
  JOIN product_lead pl ON mf.product = pl.product
  WHERE mf.month_end > CURRENT_DATE()
    AND mf.month_start < DATE_ADD(CURRENT_DATE(), INTERVAL pl.effective_lead_days DAY)
  GROUP BY mf.product
),

-- 13. Transit days from DE_LIST_OF_VALUES (Invariant #10: no hardcoded values)
shipment_config AS (
  SELECT value_id, CAST(attr1_value AS INT64) AS transit_days
  FROM `onyga-482313.OI.DE_LIST_OF_VALUES`
  WHERE lov_set = 'SHIPMENT_TYPE'
),

-- 13b. Q4 PO feasibility deadline
-- Latest date to place a PO so units arrive at FBA before Q4 peak deadline
-- Working backwards: FBA arrival deadline - inbound buffer - FAST_SEA transit - manufacture_day
q4_deadline AS (
  SELECT
    DATE_SUB(
      DATE(
        EXTRACT(YEAR FROM CURRENT_DATE()),
        CAST(SUBSTR(deadline.attr1_value, 1, 2) AS INT64),
        CAST(SUBSTR(deadline.attr1_value, 3, 2) AS INT64)
      ),
      INTERVAL (CAST(buffer.attr1_value AS INT64) + fast_sea.transit_days) DAY
    ) AS latest_ship_date,
    fast_sea.transit_days AS fast_sea_days,
    CAST(buffer.attr1_value AS INT64) AS inbound_buffer_days
  FROM (
    SELECT attr1_value FROM `onyga-482313.OI.DE_LIST_OF_VALUES`
    WHERE lov_set = 'Q4_PEAK' AND value_id = 'FBA_ARRIVAL_DEADLINE'
  ) deadline
  CROSS JOIN (
    SELECT attr1_value FROM `onyga-482313.OI.DE_LIST_OF_VALUES`
    WHERE lov_set = 'Q4_PEAK' AND value_id = 'FBA_INBOUND_BUFFER_DAYS'
  ) buffer
  CROSS JOIN shipment_config fast_sea
  WHERE fast_sea.value_id = 'FAST_SEA'
),

-- 14. Proportional demand over next 90 days (for emergency/replenishment check)
-- Uses monthly_forecast adjusted_units prorated by overlap days
demand_windows AS (
  SELECT mf.product,
    SUM(
      mf.adjusted_units *
      GREATEST(0, DATE_DIFF(
        LEAST(DATE_ADD(CURRENT_DATE(), INTERVAL 90 DAY),
              DATE_ADD(DATE(mf.forecast_year, mf.forecast_month, 1), INTERVAL 1 MONTH)),
        GREATEST(CURRENT_DATE(), DATE(mf.forecast_year, mf.forecast_month, 1)),
        DAY
      )) / DATE_DIFF(
        DATE_ADD(DATE(mf.forecast_year, mf.forecast_month, 1), INTERVAL 1 MONTH),
        DATE(mf.forecast_year, mf.forecast_month, 1), DAY)
    ) AS demand_90d,
    SUM(
      mf.adjusted_units *
      GREATEST(0, DATE_DIFF(
        LEAST(DATE_ADD(CURRENT_DATE(), INTERVAL 45 DAY),
              DATE_ADD(DATE(mf.forecast_year, mf.forecast_month, 1), INTERVAL 1 MONTH)),
        GREATEST(CURRENT_DATE(), DATE(mf.forecast_year, mf.forecast_month, 1)),
        DAY
      )) / DATE_DIFF(
        DATE_ADD(DATE(mf.forecast_year, mf.forecast_month, 1), INTERVAL 1 MONTH),
        DATE(mf.forecast_year, mf.forecast_month, 1), DAY)
    ) AS demand_45d,
    SUM(
      mf.adjusted_units *
      GREATEST(0, DATE_DIFF(
        LEAST(DATE_ADD(CURRENT_DATE(), INTERVAL 60 DAY),
              DATE_ADD(DATE(mf.forecast_year, mf.forecast_month, 1), INTERVAL 1 MONTH)),
        GREATEST(CURRENT_DATE(), DATE(mf.forecast_year, mf.forecast_month, 1)),
        DAY
      )) / DATE_DIFF(
        DATE_ADD(DATE(mf.forecast_year, mf.forecast_month, 1), INTERVAL 1 MONTH),
        DATE(mf.forecast_year, mf.forecast_month, 1), DAY)
    ) AS demand_60d,
    SUM(
      mf.adjusted_units *
      GREATEST(0, DATE_DIFF(
        LEAST(DATE_ADD(CURRENT_DATE(), INTERVAL 30 DAY),
              DATE_ADD(DATE(mf.forecast_year, mf.forecast_month, 1), INTERVAL 1 MONTH)),
        GREATEST(CURRENT_DATE(), DATE(mf.forecast_year, mf.forecast_month, 1)),
        DAY
      )) / DATE_DIFF(
        DATE_ADD(DATE(mf.forecast_year, mf.forecast_month, 1), INTERVAL 1 MONTH),
        DATE(mf.forecast_year, mf.forecast_month, 1), DAY)
    ) AS demand_30d
  FROM monthly_forecast mf
  WHERE DATE_ADD(DATE(mf.forecast_year, mf.forecast_month, 1), INTERVAL 1 MONTH) > CURRENT_DATE()
    AND DATE(mf.forecast_year, mf.forecast_month, 1) < DATE_ADD(CURRENT_DATE(), INTERVAL 90 DAY)
  GROUP BY mf.product
),

-- 14b. Backward demand: forecast for [last_loaded_date - 30, last_loaded_date]
-- Reads from the approved plan's frozen snapshot (growth + adjFactor baked in)
-- Falls back to raw forecast_units if no snapshot exists
backward_demand AS (
  SELECT product,
    ROUND(SUM(planned_units_prorated)) AS last_30d_planned
  FROM (
    -- Branch A: snapshot-based using PARSE_JSON for dynamic key access
    SELECT
      p.product,
      LAX_INT64(j[p.product][mk]) *
        GREATEST(0, DATE_DIFF(
          LEAST(lld.last_date, DATE_ADD(
            DATE(2000 + CAST(RIGHT(mk, 2) AS INT64),
              CASE LEFT(mk, 3)
                WHEN 'jan' THEN 1 WHEN 'feb' THEN 2 WHEN 'mar' THEN 3 WHEN 'apr' THEN 4
                WHEN 'may' THEN 5 WHEN 'jun' THEN 6 WHEN 'jul' THEN 7 WHEN 'aug' THEN 8
                WHEN 'sep' THEN 9 WHEN 'oct' THEN 10 WHEN 'nov' THEN 11 WHEN 'dec' THEN 12
              END, 1),
            INTERVAL 1 MONTH)),
          GREATEST(DATE_SUB(lld.last_date, INTERVAL 30 DAY),
            DATE(2000 + CAST(RIGHT(mk, 2) AS INT64),
              CASE LEFT(mk, 3)
                WHEN 'jan' THEN 1 WHEN 'feb' THEN 2 WHEN 'mar' THEN 3 WHEN 'apr' THEN 4
                WHEN 'may' THEN 5 WHEN 'jun' THEN 6 WHEN 'jul' THEN 7 WHEN 'aug' THEN 8
                WHEN 'sep' THEN 9 WHEN 'oct' THEN 10 WHEN 'nov' THEN 11 WHEN 'dec' THEN 12
              END, 1)),
          DAY
        )) / NULLIF(DATE_DIFF(
          DATE_ADD(
            DATE(2000 + CAST(RIGHT(mk, 2) AS INT64),
              CASE LEFT(mk, 3)
                WHEN 'jan' THEN 1 WHEN 'feb' THEN 2 WHEN 'mar' THEN 3 WHEN 'apr' THEN 4
                WHEN 'may' THEN 5 WHEN 'jun' THEN 6 WHEN 'jul' THEN 7 WHEN 'aug' THEN 8
                WHEN 'sep' THEN 9 WHEN 'oct' THEN 10 WHEN 'nov' THEN 11 WHEN 'dec' THEN 12
              END, 1),
            INTERVAL 1 MONTH),
          DATE(2000 + CAST(RIGHT(mk, 2) AS INT64),
            CASE LEFT(mk, 3)
              WHEN 'jan' THEN 1 WHEN 'feb' THEN 2 WHEN 'mar' THEN 3 WHEN 'apr' THEN 4
              WHEN 'may' THEN 5 WHEN 'jun' THEN 6 WHEN 'jul' THEN 7 WHEN 'aug' THEN 8
              WHEN 'sep' THEN 9 WHEN 'oct' THEN 10 WHEN 'nov' THEN 11 WHEN 'dec' THEN 12
            END, 1),
          DAY), 0) AS planned_units_prorated
    FROM (
      SELECT SAFE.PARSE_JSON(snapshot_units_json) AS j
      FROM `onyga-482313.OI.DE_PLAN_STRATEGY`
      WHERE plan_year = 2026 AND status = 'APPROVED' AND snapshot_units_json IS NOT NULL
      LIMIT 1
    ) snap
    CROSS JOIN (SELECT DISTINCT product FROM `onyga-482313.OI.FACT_FORECAST_DEMAND`) p
    CROSS JOIN UNNEST(['jan26','feb26','mar26','apr26','may26','jun26','jul26','aug26','sep26','oct26','nov26','dec26','jan27','feb27','mar27']) AS mk
    CROSS JOIN last_loaded_date lld
    WHERE j[p.product][mk] IS NOT NULL
      AND DATE_ADD(
            DATE(2000 + CAST(RIGHT(mk, 2) AS INT64),
              CASE LEFT(mk, 3)
                WHEN 'jan' THEN 1 WHEN 'feb' THEN 2 WHEN 'mar' THEN 3 WHEN 'apr' THEN 4
                WHEN 'may' THEN 5 WHEN 'jun' THEN 6 WHEN 'jul' THEN 7 WHEN 'aug' THEN 8
                WHEN 'sep' THEN 9 WHEN 'oct' THEN 10 WHEN 'nov' THEN 11 WHEN 'dec' THEN 12
              END, 1),
            INTERVAL 1 MONTH) > DATE_SUB(lld.last_date, INTERVAL 30 DAY)
      AND DATE(2000 + CAST(RIGHT(mk, 2) AS INT64),
            CASE LEFT(mk, 3)
              WHEN 'jan' THEN 1 WHEN 'feb' THEN 2 WHEN 'mar' THEN 3 WHEN 'apr' THEN 4
              WHEN 'may' THEN 5 WHEN 'jun' THEN 6 WHEN 'jul' THEN 7 WHEN 'aug' THEN 8
              WHEN 'sep' THEN 9 WHEN 'oct' THEN 10 WHEN 'nov' THEN 11 WHEN 'dec' THEN 12
            END, 1) <= lld.last_date

    UNION ALL

    -- Branch B: fallback to raw forecast_units when no snapshot exists
    SELECT fd.product,
      fd.forecast_units *
        GREATEST(0, DATE_DIFF(
          LEAST(lld.last_date, DATE_ADD(DATE(fd.forecast_year, fd.forecast_month, 1), INTERVAL 1 MONTH)),
          GREATEST(DATE_SUB(lld.last_date, INTERVAL 30 DAY), DATE(fd.forecast_year, fd.forecast_month, 1)),
          DAY
        )) / NULLIF(DATE_DIFF(
          DATE_ADD(DATE(fd.forecast_year, fd.forecast_month, 1), INTERVAL 1 MONTH),
          DATE(fd.forecast_year, fd.forecast_month, 1), DAY), 0) AS planned_units_prorated
    FROM `onyga-482313.OI.FACT_FORECAST_DEMAND` fd
    CROSS JOIN last_loaded_date lld
    WHERE NOT EXISTS (
      SELECT 1 FROM `onyga-482313.OI.DE_PLAN_STRATEGY`
      WHERE plan_year = 2026 AND status = 'APPROVED' AND snapshot_units_json IS NOT NULL
    )
    AND DATE_ADD(DATE(fd.forecast_year, fd.forecast_month, 1), INTERVAL 1 MONTH) > DATE_SUB(lld.last_date, INTERVAL 30 DAY)
    AND DATE(fd.forecast_year, fd.forecast_month, 1) <= lld.last_date
  )
  GROUP BY product
),

-- 15. Q4 demand: Sep current year through Feb next year
q4_demand_cte AS (
  SELECT product, SUM(adjusted_units) AS q4_demand
  FROM monthly_forecast
  WHERE (forecast_year = EXTRACT(YEAR FROM CURRENT_DATE()) AND forecast_month >= 9)
     OR (forecast_year = EXTRACT(YEAR FROM CURRENT_DATE()) + 1 AND forecast_month <= 2)
  GROUP BY product
),

-- 16. Pre-Q4 demand: demand from current month through Aug
-- Used to forecast Sep 1 inventory = current_pipeline - pre_q4_demand
pre_q4_demand_cte AS (
  SELECT product, SUM(adjusted_units) AS pre_q4_demand
  FROM monthly_forecast
  WHERE forecast_year = EXTRACT(YEAR FROM CURRENT_DATE())
    AND forecast_month >= EXTRACT(MONTH FROM CURRENT_DATE())
    AND forecast_month <= 8
  GROUP BY product
),

-- 17. DOC Walkthrough: month-by-month stock depletion for accurate DOC
-- Prorates current month (only remaining days), then walks full months forward
-- until stock is exhausted. Interpolates within the final month.
monthly_demand_prorated AS (
  SELECT product, forecast_year, forecast_month,
    CASE
      WHEN forecast_year = EXTRACT(YEAR FROM CURRENT_DATE())
        AND forecast_month = EXTRACT(MONTH FROM CURRENT_DATE())
      THEN adjusted_units * DATE_DIFF(
        DATE_ADD(DATE(forecast_year, forecast_month, 1), INTERVAL 1 MONTH),
        CURRENT_DATE(), DAY
      ) / DATE_DIFF(
        DATE_ADD(DATE(forecast_year, forecast_month, 1), INTERVAL 1 MONTH),
        DATE(forecast_year, forecast_month, 1), DAY
      )
      ELSE CAST(adjusted_units AS FLOAT64)
    END AS prorated_demand,
    CASE
      WHEN forecast_year = EXTRACT(YEAR FROM CURRENT_DATE())
        AND forecast_month = EXTRACT(MONTH FROM CURRENT_DATE())
      THEN DATE_DIFF(
        DATE_ADD(DATE(forecast_year, forecast_month, 1), INTERVAL 1 MONTH),
        CURRENT_DATE(), DAY
      )
      ELSE DATE_DIFF(
        DATE_ADD(DATE(forecast_year, forecast_month, 1), INTERVAL 1 MONTH),
        DATE(forecast_year, forecast_month, 1), DAY
      )
    END AS period_days
  FROM monthly_forecast
  WHERE (forecast_year > EXTRACT(YEAR FROM CURRENT_DATE()))
     OR (forecast_year = EXTRACT(YEAR FROM CURRENT_DATE())
         AND forecast_month >= EXTRACT(MONTH FROM CURRENT_DATE()))
),

cum_demand_walk AS (
  SELECT
    product, forecast_year, forecast_month,
    prorated_demand, period_days,
    SUM(prorated_demand) OVER w AS cum_demand,
    SUM(period_days) OVER w AS cum_days,
    COALESCE(SUM(prorated_demand) OVER (PARTITION BY product ORDER BY forecast_year, forecast_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS prev_cum_demand,
    COALESCE(SUM(period_days) OVER (PARTITION BY product ORDER BY forecast_year, forecast_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS prev_cum_days
  FROM monthly_demand_prorated
  WINDOW w AS (PARTITION BY product ORDER BY forecast_year, forecast_month
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
),

doc_walkthrough AS (
  SELECT
    inv.product,
    -- Sellable DOC: FBA + AWD stock walked against forecast
    -- Only interpolate the FIRST month where cum_demand crosses the stock level
    COALESCE(MIN(CASE WHEN cd.cum_demand >= (inv.fba_stock + inv.awd_stock)
        AND cd.prev_cum_demand < (inv.fba_stock + inv.awd_stock)
        AND (inv.fba_stock + inv.awd_stock) > 0 THEN
      cd.prev_cum_days + CASE WHEN cd.prorated_demand > 0
        THEN ((inv.fba_stock + inv.awd_stock) - cd.prev_cum_demand)
             * cd.period_days / cd.prorated_demand
        ELSE cd.period_days END
    END), 999.0) AS sellable_doc_walk,
    -- FBA DOC: FBA stock only walked against forecast
    COALESCE(MIN(CASE WHEN cd.cum_demand >= inv.fba_stock
        AND cd.prev_cum_demand < inv.fba_stock
        AND inv.fba_stock > 0 THEN
      cd.prev_cum_days + CASE WHEN cd.prorated_demand > 0
        THEN (inv.fba_stock - cd.prev_cum_demand)
             * cd.period_days / cd.prorated_demand
        ELSE cd.period_days END
    END), 999.0) AS fba_doc_walk
  FROM inventory inv
  JOIN cum_demand_walk cd ON cd.product = inv.product
  GROUP BY inv.product
),

-- 18. Product → Family mapping (for ads efficiency join)
product_family AS (
  SELECT DISTINCT
    dp.product_short_name AS product,
    fm.family
  FROM `onyga-482313.OI.DIM_PRODUCT` dp
  JOIN `onyga-482313.OI.V_PRODUCT_FAMILY_MAP` fm ON dp.asin = fm.asin
  WHERE dp.is_active = TRUE AND dp.oi_is_active = TRUE
),

-- 19. Product share within family (to prorate family-level forecast to product)
-- Uses FACT_FORECAST_DEMAND remaining months as distribution weight
product_share AS (
  SELECT
    fd.product,
    pf.family,
    SUM(fd.forecast_units) AS product_base,
    SUM(SUM(fd.forecast_units)) OVER (PARTITION BY pf.family) AS family_base,
    SAFE_DIVIDE(
      SUM(fd.forecast_units),
      SUM(SUM(fd.forecast_units)) OVER (PARTITION BY pf.family)
    ) AS share_in_family
  FROM `onyga-482313.OI.FACT_FORECAST_DEMAND` fd
  JOIN product_family pf ON fd.product = pf.product
  WHERE (fd.forecast_year = EXTRACT(YEAR FROM CURRENT_DATE())
         AND fd.forecast_month >= EXTRACT(MONTH FROM CURRENT_DATE()))
     OR (fd.forecast_year = EXTRACT(YEAR FROM CURRENT_DATE()) + 1
         AND fd.forecast_month <= 2)
  GROUP BY 1, 2
),

-- 20. Ads efficiency: monthly targets from V_ADS_EFFICIENCY_PROFILE
-- Sum across all forecast months for each family to get total ads forecast
ads_efficiency_by_product AS (
  SELECT
    ps.product,
    ps.family,
    ps.share_in_family,
    -- Total ads forecast for this product (family forecast × product share)
    ROUND(SUM(aep.forecast_units) * ps.share_in_family) AS ads_forecast_units,
    -- Total suggested spend for this product
    ROUND(SUM(aep.suggested_spend) * ps.share_in_family) AS ads_suggested_spend,
    -- Weighted avg efficiency metrics (weight by suggested_spend per month)
    ROUND(SAFE_DIVIDE(
      SUM(aep.cpc * aep.suggested_spend),
      NULLIF(SUM(aep.suggested_spend), 0)
    ), 3) AS avg_cpc,
    ROUND(SAFE_DIVIDE(
      SUM(aep.unit_cvr_pct * aep.suggested_spend),
      NULLIF(SUM(aep.suggested_spend), 0)
    ), 2) AS avg_unit_cvr_pct,
    ROUND(SAFE_DIVIDE(
      SUM(aep.ads_share_pct * aep.suggested_spend),
      NULLIF(SUM(aep.suggested_spend), 0)
    )) AS avg_ads_share_pct,
    ROUND(SAFE_DIVIDE(
      SUM(aep.avg_net_roas * aep.suggested_spend),
      NULLIF(SUM(aep.suggested_spend), 0)
    ), 2) AS avg_net_roas
  FROM product_share ps
  LEFT JOIN `onyga-482313.OI.V_ADS_EFFICIENCY_PROFILE` aep
    ON aep.family = ps.family
  GROUP BY 1, 2, 3
)

-- Final output
SELECT
  inv.product, inv.asin, inv.package_quantity, inv.min_manuf_quantity,
  inv.share_carton_in_family,
  inv.manufacture_day, inv.shipment_days, inv.full_lead_days,
  inv.fba_stock, inv.awd_stock, inv.in_transit, inv.at_manufacturer,
  inv.total_stock, inv.is_awd_product,

  -- Forecast
  COALESCE(dr.daily_rate, 0) AS daily_rate,
  COALESCE(eg.growth, 1.0) AS effective_growth,
  ROUND(COALESCE(eg.unconstrained_growth, 1.0) * COALESCE(eg.demand_base, 0)) AS unconstrained_remaining_forecast,

  -- Plan
  COALESCE(o.yearly_plan, COALESCE(ys.ytd_sold, 0) + CAST(ROUND(COALESCE(eg.unconstrained_growth, 1.0) * COALESCE(eg.demand_base, 0)) AS INT64)) AS yearly_plan,
  COALESCE(ys.ytd_sold, 0) AS ytd_sold,
  COALESCE(l30.last_30d_sold, 0) AS last_30d_sold,
  COALESCE(bd.last_30d_planned, 0) AS last_30d_planned,
  GREATEST(COALESCE(o.yearly_plan, COALESCE(ys.ytd_sold, 0) + CAST(ROUND(COALESCE(eg.unconstrained_growth, 1.0) * COALESCE(eg.demand_base, 0)) AS INT64)) - inv.total_stock - COALESCE(ys.ytd_sold, 0), 0) AS gap_from_plan,

  -- Supply readiness tiers
  COALESCE(st.ready_to_ship, 0) AS ready_to_ship,
  COALESCE(st.in_production, 0) AS in_production,
  COALESCE(st.ready_lead_days, inv.shipment_days) AS ready_lead_days,
  COALESCE(st.production_lead_days, inv.full_lead_days) AS production_lead_days,

  -- Effective lead time
  COALESCE(pl.effective_lead_days, inv.full_lead_days) AS effective_lead_days,

  -- Supply readiness label
  CASE
    WHEN COALESCE(st.ready_to_ship, 0) > 0 THEN 'READY'
    WHEN COALESCE(st.in_production, 0) > 0 THEN 'IN_PRODUCTION'
    ELSE 'NEEDS_PO'
  END AS supply_status,

  -- FBA effective = FBA + in-transit (for display)
  inv.fba_stock + inv.in_transit AS fba_effective,

  -- Available stock = FBA + in-transit + AWD (AWD→FBA transfer = 3-5 days)
  inv.fba_stock + inv.in_transit + inv.awd_stock AS available_stock,

  -- Demand during effective lead time (month-by-month, not flat)
  ROUND(COALESCE(ld.demand_during_lead, 0)) AS demand_during_lead,

  -- Proportional 30, 45, 60 and 90-day demand and daily rate
  ROUND(COALESCE(dwin.demand_30d, 0)) AS demand_30d,
  ROUND(COALESCE(dwin.demand_45d, 0)) AS demand_45d,
  ROUND(COALESCE(dwin.demand_60d, 0)) AS demand_60d,
  ROUND(COALESCE(dwin.demand_90d, 0)) AS demand_90d,
  ROUND(COALESCE(dwin.demand_90d, 0) / 90, 2) AS proportional_daily_demand,

  -- Days until OOS (using proportional demand, accounts for seasonality)
  CASE WHEN COALESCE(dwin.demand_90d, 0) > 0
    THEN CAST(FLOOR((inv.fba_stock + inv.in_transit + inv.awd_stock) / (dwin.demand_90d / 90)) AS INT64)
    ELSE 999
  END AS days_until_oos,

  -- Emergency priority: CEIL(weeks_to_OOS) + 1
  CASE WHEN COALESCE(dwin.demand_90d, 0) > 0
    THEN CAST(CEIL(GREATEST(0, FLOOR((inv.fba_stock + inv.in_transit + inv.awd_stock) / (dwin.demand_90d / 90))) / 7.0) AS INT64) + 1
    ELSE 999
  END AS emergency_priority,

  -- Emergency check: available stock DOC < 90 days
  CASE
    WHEN COALESCE(dwin.demand_90d, 0) = 0 THEN FALSE
    WHEN (inv.fba_stock + inv.in_transit + inv.awd_stock) < COALESCE(dwin.demand_90d, 0) THEN TRUE
    ELSE FALSE
  END AS is_emergency,

  -- Q4 demand (Sep-Feb)
  COALESCE(q4d.q4_demand, 0) AS q4_demand,

  -- Pre-Q4 demand (current month through Aug)
  COALESCE(pq4d.pre_q4_demand, 0) AS pre_q4_demand,

  -- Forecasted Sep 1 pipeline
  GREATEST(0, (inv.fba_stock + inv.awd_stock + inv.in_transit) - COALESCE(pq4d.pre_q4_demand, 0)) AS forecasted_sep1_pipeline,

  -- DOC walkthrough (month-by-month depletion — accurate with seasonal demand)
  CAST(ROUND(dw.sellable_doc_walk) AS INT64) AS sellable_doc_walk,
  CAST(ROUND(dw.fba_doc_walk) AS INT64) AS fba_doc_walk,

  -- Legacy flat-rate DOC (kept for backward compat)
  CASE WHEN COALESCE(dr.daily_rate, 0) > 0
    THEN ROUND(inv.fba_stock / dr.daily_rate, 1) ELSE 999.0
  END AS fba_doc,
  CASE WHEN COALESCE(dr.daily_rate, 0) > 0
    THEN ROUND((inv.fba_stock + inv.in_transit) / dr.daily_rate, 1) ELSE 999.0
  END AS fba_doc_effective,
  CASE WHEN COALESCE(dr.daily_rate, 0) > 0
    THEN ROUND(inv.total_stock / dr.daily_rate, 1) ELSE 999.0
  END AS system_doc,

  -- Q4 PO feasibility
  DATE_SUB(q4dl.latest_ship_date, INTERVAL inv.manufacture_day DAY) AS po_deadline,
  CURRENT_DATE() <= DATE_SUB(q4dl.latest_ship_date, INTERVAL inv.manufacture_day DAY) AS po_feasible,

  -- Forecast phase (for model-based new product forecasting)
  CASE
    WHEN npm.model_product IS NULL THEN 'PHASE_3'
    WHEN inv.estimated_start_selling_date IS NULL
      OR DATE_DIFF(CURRENT_DATE(), inv.estimated_start_selling_date, DAY) < 30
      THEN 'PHASE_1'
    WHEN DATE_DIFF(CURRENT_DATE(), inv.estimated_start_selling_date, DAY) < 365
      THEN 'PHASE_2'
    ELSE 'PHASE_3'
  END AS forecast_phase,
  npm.model_product,

  -- Ads efficiency (from V_ADS_EFFICIENCY_PROFILE)
  COALESCE(ae.ads_forecast_units, 0) AS ads_forecast_units,
  COALESCE(ae.ads_suggested_spend, 0) AS ads_suggested_spend,
  ae.avg_cpc AS ads_cpc,
  ae.avg_unit_cvr_pct AS ads_unit_cvr_pct,
  ae.avg_ads_share_pct AS ads_share_pct,
  ae.avg_net_roas AS ads_net_roas,
  COALESCE(pf.family, 'Unknown') AS family

FROM inventory inv
LEFT JOIN daily_rates dr ON inv.product = dr.product
LEFT JOIN launch_signal ls ON inv.product = ls.product
LEFT JOIN effective_growth eg ON inv.product = eg.product
LEFT JOIN overrides o ON inv.product = o.product
LEFT JOIN ytd_sales ys ON inv.product = ys.product
LEFT JOIN last_30d_sales l30 ON inv.product = l30.product
LEFT JOIN backward_demand bd ON inv.product = bd.product
LEFT JOIN supply_tiers st ON inv.product = st.product
LEFT JOIN product_lead pl ON inv.product = pl.product
LEFT JOIN lead_demand ld ON inv.product = ld.product
LEFT JOIN demand_windows dwin ON inv.product = dwin.product
LEFT JOIN q4_demand_cte q4d ON inv.product = q4d.product
LEFT JOIN pre_q4_demand_cte pq4d ON inv.product = pq4d.product
LEFT JOIN doc_walkthrough dw ON inv.product = dw.product
LEFT JOIN `onyga-482313.OI.DE_NEW_PRODUCT_MODEL` npm ON inv.family = npm.family
LEFT JOIN product_family pf ON inv.product = pf.product
LEFT JOIN ads_efficiency_by_product ae ON inv.product = ae.product
CROSS JOIN q4_deadline q4dl;
