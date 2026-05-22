CREATE OR REPLACE VIEW `onyga-482313.OI.V_FORECAST_DEMAND` AS

-- ═══════════════════════════════════════════════════════════════
-- V_FORECAST_DEMAND — Family-level daily-ramp demand forecast
-- with per-product share split, new-variant cannibalization,
-- and 3-phase model-based forecasting for new products.
--
-- Architecture:
--   Part A: Family-level daily ramp (holiday-relative day matching)
--   Part B: Product share split (history + cannibalization for non-model products)
--   Part C: Family-based output (Phase 3 mature products)
--   Part D: Model-based forecast (Phase 1 cold-start + Phase 2 hybrid)
--   Part E: UNION ALL — combines family-based and model-based
--
-- 3-Phase Model:
--   Phase 1 (0–30 days): model_daily_rate × model_seasonality × days
--   Phase 2 (30d–1y):    own_trailing_14d_rate × model_seasonality × days
--   Phase 3 (1+ year):   standard family-level forecast (Parts A–C)
--
-- Dependencies:
--   V_PRODUCT_LAUNCH_MODEL, V_PRODUCT_SEASONALITY_INDEX,
--   DE_NEW_PRODUCT_MODEL, T_UNIFIED_DAILY, DIM_US_HOLIDAYS
-- ═══════════════════════════════════════════════════════════════

WITH

-- ════════════════════════════════════════════════════════════
-- PART A: FAMILY-LEVEL DAILY RAMP FORECAST
-- ════════════════════════════════════════════════════════════

hist_year AS (
  SELECT EXTRACT(YEAR FROM CURRENT_DATE()) - 1 AS yr
),

-- A1: Holiday peak windows for historical year
holiday_windows_hist AS (
  SELECT h.holiday_name, h.peak_start AS ws,
    DATE_SUB(h.holiday_date, INTERVAL 1 DAY) AS we, h.holiday_date
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h, hist_year hy
  WHERE EXTRACT(YEAR FROM h.holiday_date) = hy.yr
    AND h.category = 'gift_season'
),

-- A2: Tag each historical date with holiday + days_before_holiday
all_dates_hist AS (
  SELECT d FROM hist_year hy,
    UNNEST(GENERATE_DATE_ARRAY(DATE(hy.yr, 1, 1), DATE(hy.yr, 12, 31))) d
),
date_holiday_match AS (
  SELECT ad.d, h.holiday_name,
    DATE_DIFF(h.holiday_date, ad.d, DAY) AS days_before,
    ROW_NUMBER() OVER (PARTITION BY ad.d ORDER BY ABS(DATE_DIFF(ad.d, h.holiday_date, DAY))) AS rn
  FROM all_dates_hist ad
  JOIN holiday_windows_hist h ON ad.d BETWEEN h.ws AND h.we
),
tagged_hist AS (
  SELECT ad.d,
    EXTRACT(MONTH FROM ad.d) AS hist_month,
    COALESCE(m.holiday_name, '__offseason__') AS season_tag,
    COALESCE(m.days_before, -1) AS days_before
  FROM all_dates_hist ad
  LEFT JOIN (SELECT d, holiday_name, days_before FROM date_holiday_match WHERE rn = 1) m USING (d)
),

-- A3: First sale date per family (to exclude launch ramp-up)
family_first_sale AS (
  SELECT family, MIN(date) AS first_sale_date
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE family IS NOT NULL AND units > 0
  GROUP BY 1
),

-- A3b: Per-FAMILY daily units from historical year (one row per family per date)
-- Excludes first 60 days of each family's life (launch ramp-up noise)
family_daily_hist AS (
  SELECT
    u.family,
    t.season_tag,
    t.days_before,
    t.hist_month,
    t.d AS hist_date,
    SUM(u.units) AS units
  FROM tagged_hist t
  JOIN `onyga-482313.OI.T_UNIFIED_DAILY` u ON u.date = t.d
  JOIN family_first_sale ffs ON ffs.family = u.family
  WHERE u.family IS NOT NULL
    AND t.d >= DATE_ADD(ffs.first_sale_date, INTERVAL 60 DAY)
  GROUP BY 1, 2, 3, 4, 5
),

-- A4: Smoothed peak rates per family (7-day rolling avg within each holiday)
peak_daily AS (
  SELECT family, season_tag, days_before, units
  FROM family_daily_hist WHERE season_tag != '__offseason__'
),
peak_rates AS (
  SELECT DISTINCT family, season_tag, days_before,
    AVG(units) OVER (
      PARTITION BY family, season_tag
      ORDER BY days_before DESC
      ROWS BETWEEN 3 PRECEDING AND 3 FOLLOWING
    ) AS smoothed_rate
  FROM peak_daily
),

-- A5: Month-specific offseason rates per family
-- Only trust months with meaningful data (> 15 days and > 0 units)
offseason_rates AS (
  SELECT family, hist_month,
    SUM(units) / COUNT(DISTINCT hist_date) AS daily_rate
  FROM family_daily_hist WHERE season_tag = '__offseason__'
  GROUP BY 1, 2
  HAVING COUNT(DISTINCT hist_date) >= 15 AND SUM(units) > 0
),
-- Global offseason rate (across all available months)
offseason_global AS (
  SELECT family, SUM(units) / COUNT(DISTINCT hist_date) AS daily_rate
  FROM family_daily_hist WHERE season_tag = '__offseason__'
  GROUP BY 1
  HAVING SUM(units) > 0
),
-- Trailing 90-day rate: best fallback for products with < 12 months of data
-- Uses the most recent 90 days of non-peak data to estimate future offseason
trailing_rate AS (
  SELECT family,
    SUM(units) / COUNT(DISTINCT hist_date) AS daily_rate
  FROM family_daily_hist
  WHERE season_tag = '__offseason__'
    AND hist_date >= DATE_SUB((SELECT DATE(yr, 12, 31) FROM hist_year), INTERVAL 90 DAY)
  GROUP BY 1
  HAVING COUNT(DISTINCT hist_date) >= 10 AND SUM(units) > 0
),

-- A6: Family-level YoY lift (trailing 8 weeks)
yoy_lift AS (
  SELECT family,
    SAFE_DIVIDE(
      SUM(IF(date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 56 DAY)
                   AND DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY), units, 0)),
      NULLIF(SUM(IF(date BETWEEN DATE_SUB(DATE_SUB(CURRENT_DATE(), INTERVAL 1 YEAR), INTERVAL 56 DAY)
                         AND DATE_SUB(DATE_SUB(CURRENT_DATE(), INTERVAL 1 YEAR), INTERVAL 1 DAY), units, 0)), 0)
    ) AS raw_lift
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE family IS NOT NULL
  GROUP BY 1
),
family_lift AS (
  SELECT f.family,
    -- Direct clamped value (no sqrt dampening — trust 8-week actuals)
    ROUND(GREATEST(0.70, LEAST(2.00, COALESCE(yl.raw_lift, 1.0))), 3) AS sqrt_lift,
    ROUND(COALESCE(yl.raw_lift, 1.0), 3) AS raw_lift
  FROM (
    SELECT DISTINCT fm.family
    FROM `onyga-482313.OI.V_PRODUCT_FAMILY_MAP` fm
    JOIN `onyga-482313.OI.DIM_PRODUCT` dp ON fm.asin = dp.asin
    WHERE dp.is_active = true AND dp.oi_is_active = true AND fm.family IS NOT NULL AND fm.family NOT IN ('BFF 1', 'Popsicle')
  ) f
  LEFT JOIN yoy_lift yl ON f.family = yl.family
),

-- A7: Tag future dates with holiday + days_before
holiday_windows_future AS (
  SELECT h.holiday_name, h.peak_start AS ws,
    DATE_SUB(h.holiday_date, INTERVAL 1 DAY) AS we, h.holiday_date
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
  WHERE h.category = 'gift_season'
    AND h.holiday_date >= DATE_TRUNC(CURRENT_DATE(), YEAR)
    AND h.holiday_date <= DATE_ADD(CURRENT_DATE(), INTERVAL 14 MONTH)
),
future_dates AS (
  SELECT d FROM UNNEST(GENERATE_DATE_ARRAY(DATE_TRUNC(CURRENT_DATE(), YEAR), DATE_ADD(CURRENT_DATE(), INTERVAL 14 MONTH))) d
),
fut_match AS (
  SELECT fd.d, h.holiday_name,
    DATE_DIFF(h.holiday_date, fd.d, DAY) AS days_before,
    ROW_NUMBER() OVER (PARTITION BY fd.d ORDER BY ABS(DATE_DIFF(fd.d, h.holiday_date, DAY))) AS rn
  FROM future_dates fd
  JOIN holiday_windows_future h ON fd.d BETWEEN h.ws AND h.we
),
tagged_future AS (
  SELECT fd.d,
    EXTRACT(YEAR FROM fd.d) AS yr,
    EXTRACT(MONTH FROM fd.d) AS mo,
    COALESCE(fm.holiday_name, '__offseason__') AS season_tag,
    COALESCE(fm.days_before, -1) AS days_before
  FROM future_dates fd
  LEFT JOIN (SELECT d, holiday_name, days_before FROM fut_match WHERE rn = 1) fm USING (d)
),

-- A8: Day-level family forecast
families AS (
  SELECT DISTINCT fm.family
  FROM `onyga-482313.OI.V_PRODUCT_FAMILY_MAP` fm
  JOIN `onyga-482313.OI.DIM_PRODUCT` dp ON fm.asin = dp.asin
  WHERE dp.is_active = true AND dp.oi_is_active = true AND fm.family IS NOT NULL AND fm.family NOT IN ('BFF 1', 'Popsicle')
),
day_forecast AS (
  SELECT
    tf.d, tf.yr, tf.mo,
    f.family,
    tf.season_tag,
    CASE
      WHEN tf.season_tag != '__offseason__' THEN
        COALESCE(pr.smoothed_rate, osr.daily_rate, tr.daily_rate, osg.daily_rate, 0)
      ELSE
        COALESCE(osr.daily_rate, tr.daily_rate, osg.daily_rate, 0)
    END AS base_rate,
    fl.sqrt_lift
  FROM tagged_future tf
  CROSS JOIN families f
  LEFT JOIN peak_rates pr ON pr.family = f.family AND pr.season_tag = tf.season_tag AND pr.days_before = tf.days_before
  LEFT JOIN offseason_rates osr ON osr.family = f.family AND osr.hist_month = tf.mo
  LEFT JOIN trailing_rate tr ON tr.family = f.family
  LEFT JOIN offseason_global osg ON osg.family = f.family
  JOIN family_lift fl ON fl.family = f.family
),

-- A9: Monthly family forecast + peak/offseason day counts
family_forecast AS (
  SELECT
    family,
    yr, mo,
    ROUND(SUM(base_rate * sqrt_lift)) AS family_forecast_units,
    MAX(sqrt_lift) AS sqrt_lift,
    COUNTIF(season_tag != '__offseason__') AS peak_days,
    COUNTIF(season_tag = '__offseason__') AS offseason_days,
    STRING_AGG(DISTINCT CASE WHEN season_tag != '__offseason__' THEN season_tag END, ', ') AS peak_holidays
  FROM day_forecast
  GROUP BY 1, 2, 3
),


-- ════════════════════════════════════════════════════════════
-- PART B: PRODUCT SHARE SPLIT + CANNIBALIZATION
-- (Only for products NOT handled by model-based forecast)
-- ════════════════════════════════════════════════════════════

-- B0: Products with a model assignment — excluded from family share split
model_assigned AS (
  SELECT family, model_product
  FROM `onyga-482313.OI.DE_NEW_PRODUCT_MODEL`
),

-- B1: All active products per family (from DIM_PRODUCT)
active_products AS (
  SELECT
    fm.family,
    fm.product_short_name AS product,
    fm.asin,
    dp.is_active,
    COALESCE(
      dp.estimated_start_selling_date,
      (SELECT MIN(po.estimated_arrival_date) FROM `onyga-482313.OI.DE_PURCHASE_ORDERS` po WHERE po.product_asin = dp.asin),
      DATE_ADD(CURRENT_DATE(), INTERVAL (dp.manufacture_day + dp.shipment_days) DAY)
    ) AS estimated_start_selling_date
  FROM `onyga-482313.OI.V_PRODUCT_FAMILY_MAP` fm
  JOIN `onyga-482313.OI.DIM_PRODUCT` dp ON fm.asin = dp.asin
  WHERE dp.is_active = true AND dp.oi_is_active = true
    AND fm.family IS NOT NULL
    AND fm.family NOT IN ('BFF 1', 'Popsicle')
),

-- B2: Historical share = trailing share from available data
product_history AS (
  SELECT
    family,
    product_short_name AS product,
    MIN(date) AS first_seen,
    MAX(date) AS last_seen,
    DATE_DIFF(MAX(date), MIN(date), DAY) AS history_days,
    SUM(units) AS total_units
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE family IS NOT NULL
    AND date >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
  GROUP BY 1, 2
),

-- Evaluate phases for ALL active products
product_phases AS (
  SELECT
    ap.product,
    ap.family,
    ap.estimated_start_selling_date,
    ma.model_product,
    ph.first_seen AS first_sale_date,
    COALESCE(ph.history_days, 0) AS history_days,
    COALESCE(ph.total_units, 0) AS total_units,
    -- Phase classification (automatic based on true product age)
    CASE
      WHEN ap.estimated_start_selling_date IS NULL
        OR DATE_DIFF(CURRENT_DATE(), ap.estimated_start_selling_date, DAY) < 30
        THEN 'PHASE_1'
      WHEN DATE_DIFF(CURRENT_DATE(), ap.estimated_start_selling_date, DAY) < 365
        THEN 'PHASE_2'
      ELSE 'PHASE_3' 
    END AS forecast_phase
  FROM active_products ap
  LEFT JOIN model_assigned ma ON LOWER(ap.family) = LOWER(ma.family)
  LEFT JOIN product_history ph ON ap.family = ph.family AND ap.product = ph.product
),

-- B3: Classify products as existing vs new
-- Exclude products that are actually assigned to a model AND are in Phase 1/2
product_classification AS (
  SELECT
    pp.family,
    pp.product,
    pp.history_days,
    pp.total_units,
    pp.first_sale_date AS first_seen,
    pp.estimated_start_selling_date,
    CASE
      WHEN pp.total_units = 0 THEN TRUE
      ELSE FALSE
    END AS is_new_product,
    CASE
      WHEN pp.total_units = 0 THEN TRUE
      WHEN pp.history_days < 60 THEN TRUE
      ELSE FALSE
    END AS is_draft
  FROM product_phases pp
  WHERE pp.forecast_phase = 'PHASE_3' OR pp.model_product IS NULL
),


-- B4: Compute base shares for existing products (historical share within family)
existing_shares AS (
  SELECT
    family, product, total_units,
    SAFE_DIVIDE(total_units, SUM(total_units) OVER (PARTITION BY family)) AS base_share
  FROM product_classification
  WHERE NOT is_new_product AND total_units > 0
),

-- B5: Count new products per family for cannibalization
new_product_counts AS (
  SELECT family, COUNT(*) AS num_new
  FROM product_classification
  WHERE is_new_product
  GROUP BY 1
),

-- B6: Apply cannibalization rule
product_shares AS (
  SELECT
    pc.family, pc.product, pc.is_new_product, pc.is_draft,
    pc.estimated_start_selling_date,
    es.base_share * GREATEST(0, 1 - 0.10 * COALESCE(npc.num_new, 0)) AS product_share
  FROM product_classification pc
  JOIN existing_shares es ON pc.family = es.family AND pc.product = es.product
  LEFT JOIN new_product_counts npc ON pc.family = npc.family
  WHERE NOT pc.is_new_product

  UNION ALL

  SELECT
    pc.family, pc.product, pc.is_new_product, pc.is_draft,
    pc.estimated_start_selling_date,
    0.10 AS product_share
  FROM product_classification pc
  WHERE pc.is_new_product
),


-- ════════════════════════════════════════════════════════════
-- PART C: FAMILY-BASED OUTPUT (Phase 3 + unassigned products)
-- ════════════════════════════════════════════════════════════

family_based AS (
  SELECT
    ps.product,
    ff.family,
    ff.yr AS forecast_year,
    ff.mo AS forecast_month,
    ff.family_forecast_units,
    ROUND(ps.product_share, 4) AS product_share,
    CASE
      WHEN ps.is_new_product
        AND ps.estimated_start_selling_date IS NOT NULL
        AND DATE(ff.yr, ff.mo, 1) < DATE_TRUNC(ps.estimated_start_selling_date, MONTH)
      THEN 0
      ELSE ROUND(ff.family_forecast_units * ps.product_share)
    END AS forecast_units,
    ps.is_new_product,
    ps.is_draft,
    ff.sqrt_lift,
    ff.peak_days,
    ff.offseason_days,
    ff.peak_holidays,
    'PHASE_3' AS forecast_phase,
    CAST(NULL AS STRING) AS model_product
  FROM family_forecast ff
  JOIN product_shares ps ON ff.family = ps.family
),


-- ════════════════════════════════════════════════════════════
-- PART D: MODEL-BASED FORECAST (Phase 1 & Phase 2)
-- For products assigned a launch model via DE_NEW_PRODUCT_MODEL
-- ════════════════════════════════════════════════════════════

-- D1.5: Count of Phase 1 products per family to split the forecast
phase1_split AS (
  SELECT family, model_product, COUNT(product) as phase1_product_count
  FROM product_phases
  WHERE forecast_phase = 'PHASE_1' AND model_product IS NOT NULL
  GROUP BY 1, 2
),

-- D2: Model product's seasonality index (calendar month shape)
model_seasonality AS (
  SELECT product, calendar_month, seasonality_index
  FROM `onyga-482313.OI.V_PRODUCT_SEASONALITY_INDEX`
),

-- D3: Model product's first-month daily rate (for Phase 1 cold start)
model_first_month AS (
  SELECT product, daily_rate AS month1_daily_rate
  FROM `onyga-482313.OI.V_PRODUCT_LAUNCH_MODEL`
  WHERE month_num = 2  -- Use month 2 (first full month, month 1 is partial)
),

-- D4: Trailing 14-day daily rate per product (for Phase 2)
trailing_14d AS (
  SELECT
    product_short_name AS product,
    SAFE_DIVIDE(SUM(units), 14.0) AS trailing_daily_rate
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
  GROUP BY 1
),

-- D5: Model-based monthly forecast
-- Phase 1: model_daily_rate × seasonality_index × days_in_month
-- Phase 2: own_trailing_14d_rate × seasonality_index × days_in_month
model_forecast AS (
  SELECT
    mp.product,
    mp.family,
    tf.yr AS forecast_year,
    tf.mo AS forecast_month,
    mp.forecast_phase,
    mp.model_product,
    mp.estimated_start_selling_date,
    -- Base daily rate depends on phase
    CASE
      WHEN mp.forecast_phase = 'PHASE_1'
        THEN COALESCE(SAFE_DIVIDE(mfm.month1_daily_rate, p1s.phase1_product_count), 0)
      WHEN mp.forecast_phase = 'PHASE_2'
        THEN COALESCE(t14.trailing_daily_rate, mfm.month1_daily_rate, 0)
      ELSE 0
    END AS base_daily_rate,
    -- Seasonality index from the model product
    COALESCE(ms.seasonality_index, 1.0) AS seasonality_index,
    -- Days in this forecast month
    DATE_DIFF(
      DATE_ADD(DATE(tf.yr, tf.mo, 1), INTERVAL 1 MONTH),
      DATE(tf.yr, tf.mo, 1),
      DAY
    ) AS days_in_month
  FROM product_phases mp
  CROSS JOIN (
    SELECT DISTINCT yr, mo FROM tagged_future
  ) tf
  LEFT JOIN model_seasonality ms
    ON ms.product = mp.model_product AND ms.calendar_month = tf.mo
  LEFT JOIN model_first_month mfm ON mfm.product = mp.model_product
  LEFT JOIN phase1_split p1s ON p1s.family = mp.family AND p1s.model_product = mp.model_product
  LEFT JOIN trailing_14d t14 ON t14.product = mp.product
  WHERE mp.forecast_phase IN ('PHASE_1', 'PHASE_2') AND mp.model_product IS NOT NULL
),

-- D6: Final model-based output
model_based AS (
  SELECT
    mf.product,
    mf.family,
    mf.forecast_year,
    mf.forecast_month,
    CAST(NULL AS INT64) AS family_forecast_units,
    CAST(NULL AS FLOAT64) AS product_share,
    -- Zero forecast before launch date
    CASE
      WHEN mf.estimated_start_selling_date IS NOT NULL
        AND DATE(mf.forecast_year, mf.forecast_month, 1)
            < DATE_TRUNC(mf.estimated_start_selling_date, MONTH)
      THEN 0
      ELSE ROUND(mf.base_daily_rate * mf.seasonality_index * mf.days_in_month)
    END AS forecast_units,
    TRUE AS is_new_product,
    TRUE AS is_draft,
    CAST(NULL AS FLOAT64) AS sqrt_lift,
    0 AS peak_days,
    CAST(mf.days_in_month AS INT64) AS offseason_days,
    CAST(NULL AS STRING) AS peak_holidays,
    mf.forecast_phase,
    mf.model_product
  FROM model_forecast mf
),


-- ════════════════════════════════════════════════════════════
-- PART E: UNION ALL — Combine family-based and model-based
-- ════════════════════════════════════════════════════════════

final AS (
  SELECT * FROM family_based
  UNION ALL
  SELECT * FROM model_based
)

SELECT * FROM final;
