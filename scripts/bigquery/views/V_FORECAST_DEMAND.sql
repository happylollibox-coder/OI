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
    ) AS raw_lift,
    -- Last-year 56-day denominator, to detect a near-zero (launch/first-year) baseline.
    SUM(IF(date BETWEEN DATE_SUB(DATE_SUB(CURRENT_DATE(), INTERVAL 1 YEAR), INTERVAL 56 DAY)
                  AND DATE_SUB(DATE_SUB(CURRENT_DATE(), INTERVAL 1 YEAR), INTERVAL 1 DAY), units, 0)) AS ly_56d_units
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE family IS NOT NULL
  GROUP BY 1
),
-- A6b: Recent trailing run-rate (28 complete days, ending 3 days back to clear the 1-2d data lag).
-- Anchor for first-year families whose YoY denominator is a launch-period near-zero.
run_rate AS (
  SELECT family,
    SAFE_DIVIDE(
      SUM(IF(date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY) AND DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY), units, 0)),
      28.0
    ) AS daily_rate
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE family IS NOT NULL
  GROUP BY 1
),
family_lift AS (
  SELECT f.family,
    CASE
      -- FIRST-YEAR / launch-baseline guard: when the YoY ratio blows up (raw_lift >= 3) the last-year
      -- denominator was a launch-period near-zero, so the clamped 2.0x lift over-projects. Anchor to the
      -- recent run-rate instead: lift = run_rate / historical offseason base — this re-levels the whole
      -- curve so off-season ≈ run_rate and peaks scale proportionally, keeping last year's seasonal shape.
      WHEN COALESCE(yl.raw_lift, 0) >= 3.0
           AND COALESCE(rr.daily_rate, 0) > 0
           AND COALESCE(osg.daily_rate, 0) > 0
        THEN ROUND(LEAST(3.0, GREATEST(0.30, rr.daily_rate / osg.daily_rate)), 3)
      -- Direct clamped value (no sqrt dampening — trust 8-week actuals)
      ELSE ROUND(GREATEST(0.70, LEAST(2.00, COALESCE(yl.raw_lift, 1.0))), 3)
    END AS sqrt_lift,
    ROUND(COALESCE(yl.raw_lift, 1.0), 3) AS raw_lift
  FROM (
    SELECT DISTINCT fm.family
    FROM `onyga-482313.OI.V_PRODUCT_FAMILY_MAP` fm
    JOIN `onyga-482313.OI.DIM_PRODUCT` dp ON fm.asin = dp.asin
    WHERE dp.is_active = true AND dp.oi_is_active = true AND fm.family IS NOT NULL AND fm.family NOT IN ('BFF 1', 'Popsicle')
  ) f
  LEFT JOIN yoy_lift yl ON f.family = yl.family
  LEFT JOIN run_rate rr ON f.family = rr.family
  LEFT JOIN offseason_global osg ON f.family = osg.family
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

-- B2b: Families that have a real historical envelope (family_forecast > 0).
-- Only these carve their forecast among variations by share; envelope-less
-- (brand-new) families fall through to the model-based cold start (Part D).
family_has_envelope AS (
  SELECT family FROM family_forecast GROUP BY family HAVING MAX(family_forecast_units) > 0
),

-- B3: Trailing daily rates per product (the "recent rate" signal)
--   < 90 days old (or not yet steady) → trailing 7d (last week, responsive)
--   ≥ 90 days AND steady              → trailing 28d (locked "determined daily units")
trailing_7d AS (
  SELECT product_short_name AS product, SAFE_DIVIDE(SUM(units), 7.0) AS rate7
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
  GROUP BY 1
),
trailing_28d AS (
  SELECT product_short_name AS product, SAFE_DIVIDE(SUM(units), 28.0) AS rate28
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
  GROUP BY 1
),

-- B4: Week-to-week variance over the last 12 weeks → coefficient of variation.
-- Used as the stability gate for graduating from the 7d to the 28d rate.
product_weekly_cov AS (
  SELECT product, SAFE_DIVIDE(STDDEV(wk_units), NULLIF(AVG(wk_units), 0)) AS cov
  FROM (
    SELECT product_short_name AS product, DATE_TRUNC(date, WEEK) AS wk, SUM(units) AS wk_units
    FROM `onyga-482313.OI.T_UNIFIED_DAILY`
    WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 84 DAY)
    GROUP BY 1, 2
  )
  GROUP BY 1
),

-- B5: Recent daily rate per product, with the 7d→28d graduation rule.
--   is_stable = ≥1 year old, OR ≥90 days old with low week-to-week variance (CoV < 0.30).
--   Stable products use the smooth 28d rate ("determined daily units"); still-maturing
--   products use the responsive 7d rate (falling back to 28d, then the launch model for a
--   brand-new SKU that hasn't sold yet). Established products are never dropped to 7d.
product_recent_rate AS (
  SELECT
    family, product, estimated_start_selling_date, age_days, is_stable,
    COALESCE(
      CASE
        WHEN is_stable THEN rate28
        ELSE COALESCE(NULLIF(rate7, 0), rate28, CASE WHEN age_days < 90 THEN lm_rate END)
      END, 0) AS recent_daily_rate
  FROM (
    SELECT
      pp.family,
      pp.product,
      pp.estimated_start_selling_date,
      DATE_DIFF(CURRENT_DATE(), pp.estimated_start_selling_date, DAY) AS age_days,
      (DATE_DIFF(CURRENT_DATE(), pp.estimated_start_selling_date, DAY) >= 365
         OR (DATE_DIFF(CURRENT_DATE(), pp.estimated_start_selling_date, DAY) >= 90
             AND COALESCE(cov.cov, 999) < 0.30)) AS is_stable,
      t7.rate7,
      t28.rate28,
      lm.daily_rate AS lm_rate
    FROM product_phases pp
    LEFT JOIN trailing_7d t7 ON t7.product = pp.product
    LEFT JOIN trailing_28d t28 ON t28.product = pp.product
    LEFT JOIN product_weekly_cov cov ON cov.product = pp.product
    LEFT JOIN `onyga-482313.OI.V_PRODUCT_LAUNCH_MODEL` lm
      ON lm.product = pp.model_product AND lm.month_num = 2
    JOIN family_has_envelope fhe ON fhe.family = pp.family
  )
),

-- B6: Carve-out shares — each variation's recent rate ÷ the family's total recent
-- rate. New colors take share FROM the envelope (cannibalize) instead of adding on top.
product_shares AS (
  SELECT
    prr.family,
    prr.product,
    prr.estimated_start_selling_date,
    prr.is_stable,
    SAFE_DIVIDE(prr.recent_daily_rate,
                NULLIF(SUM(prr.recent_daily_rate) OVER (PARTITION BY prr.family), 0)) AS product_share,
    (prr.age_days < 90) AS is_new_product,
    (NOT prr.is_stable) AS is_draft
  FROM product_recent_rate prr
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
      WHEN ps.estimated_start_selling_date IS NOT NULL
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
    CAST(NULL AS STRING) AS model_product,
    ps.is_stable
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

-- D-const: reasonableness-cap knobs (guard B) + plateau reference
model_const AS (
  SELECT 2.0 AS ramp_ceil, 5.0 AS season_ceil, 120 AS thin_history_days
),

-- D1: current-date anchors
now_ref AS (
  SELECT EXTRACT(YEAR FROM CURRENT_DATE()) AS cur_yr,
         EXTRACT(MONTH FROM CURRENT_DATE()) AS cur_mo,
         DATE_TRUNC(CURRENT_DATE(), MONTH) AS cur_month_start
),

-- D2: anchor daily rate per model product.
--   Phase 2 -> own trailing-14d rate; Phase 1 -> donor month-1 rate / phase1 split.
trailing_14d AS (
  SELECT product_short_name AS product, SAFE_DIVIDE(SUM(units), 14.0) AS trailing_daily_rate
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
  GROUP BY 1
),
model_first_month AS (
  SELECT product, daily_rate AS month1_daily_rate
  FROM `onyga-482313.OI.V_PRODUCT_LAUNCH_MODEL`
  WHERE month_num = 2
),

-- D3: donor plateau ramp (for target ages beyond the donor's known ages)
donor_plateau AS (
  SELECT donor_product, MAX(ramp_factor) AS plateau_ramp
  FROM `onyga-482313.OI.V_LAUNCH_RAMP` GROUP BY 1
),

-- D4: donor maturity — donor uses its OWN seasonality only if it has >=730 days
-- of history; else fall back to house blend. (Today only Lollibox qualifies.)
donor_maturity AS (
  SELECT product_short_name AS donor,
    DATE_DIFF(CURRENT_DATE(), MIN(date), DAY) >= 730 AS donor_is_mature
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE units > 0 AND product_short_name IS NOT NULL
  GROUP BY 1
),

-- D5: per-product own history length (gates guard B)
product_history_days AS (
  SELECT product_short_name AS product, DATE_DIFF(MAX(date), MIN(date), DAY) AS hist_days
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE units > 0 GROUP BY 1
),

-- D6: month grid x phase-1/2 products (envelope-less families only, as before)
model_grid AS (
  SELECT mp.product, mp.family, mp.model_product, mp.forecast_phase,
    mp.estimated_start_selling_date,
    tf.yr AS forecast_year, tf.mo AS forecast_month,
    DATE_DIFF(DATE_TRUNC(CURRENT_DATE(), MONTH),
              DATE_TRUNC(mp.estimated_start_selling_date, MONTH), MONTH) + 1 AS age_now,
    DATE_DIFF(DATE(tf.yr, tf.mo, 1),
              DATE_TRUNC(mp.estimated_start_selling_date, MONTH), MONTH) + 1 AS age_f,
    DATE_DIFF(DATE_ADD(DATE(tf.yr, tf.mo, 1), INTERVAL 1 MONTH), DATE(tf.yr, tf.mo, 1), DAY) AS days_in_month
  FROM product_phases mp
  CROSS JOIN (SELECT DISTINCT yr, mo FROM tagged_future) tf
  LEFT JOIN family_has_envelope fhe ON fhe.family = mp.family
  WHERE mp.forecast_phase IN ('PHASE_1', 'PHASE_2') AND mp.model_product IS NOT NULL
    AND fhe.family IS NULL
),

-- D7: assemble factors
model_forecast AS (
  SELECT
    g.product, g.family, g.model_product, g.forecast_phase,
    g.estimated_start_selling_date, g.forecast_year, g.forecast_month, g.days_in_month,
    g.age_now, g.age_f,
    CASE
      WHEN g.forecast_phase = 'PHASE_1'
        THEN COALESCE(SAFE_DIVIDE(mfm.month1_daily_rate, p1s.phase1_product_count), 0)
      ELSE COALESCE(t14.trailing_daily_rate, mfm.month1_daily_rate, 0)
    END AS anchor_rate,
    COALESCE(r_now.ramp_factor, dp.plateau_ramp, 1.0) AS ramp_now,
    COALESCE(r_f.ramp_factor,   dp.plateau_ramp, 1.0) AS ramp_f,
    COALESCE(CASE WHEN dm.donor_is_mature THEN own_now.seasonality_index END,
             hs_now.house_season_index, 1.0) AS season_now,
    COALESCE(CASE WHEN dm.donor_is_mature THEN own_f.seasonality_index END,
             hs_f.house_season_index, 1.0) AS season_f,
    COALESCE(ph.hist_days, 0) AS hist_days
  FROM model_grid g
  CROSS JOIN now_ref nr
  LEFT JOIN trailing_14d t14 ON t14.product = g.product
  LEFT JOIN model_first_month mfm ON mfm.product = g.model_product
  LEFT JOIN phase1_split p1s ON p1s.family = g.family AND p1s.model_product = g.model_product
  LEFT JOIN `onyga-482313.OI.V_LAUNCH_RAMP` r_now
    ON r_now.donor_product = g.model_product
    AND r_now.launch_age_month = CASE WHEN g.forecast_phase = 'PHASE_1' THEN 1 ELSE g.age_now END
  LEFT JOIN `onyga-482313.OI.V_LAUNCH_RAMP` r_f
    ON r_f.donor_product = g.model_product AND r_f.launch_age_month = g.age_f
  LEFT JOIN donor_plateau dp ON dp.donor_product = g.model_product
  LEFT JOIN donor_maturity dm ON dm.donor = g.model_product
  LEFT JOIN `onyga-482313.OI.V_PRODUCT_SEASONALITY_INDEX` own_now
    ON own_now.product = g.model_product AND own_now.calendar_month = nr.cur_mo
  LEFT JOIN `onyga-482313.OI.V_PRODUCT_SEASONALITY_INDEX` own_f
    ON own_f.product = g.model_product AND own_f.calendar_month = g.forecast_month
  LEFT JOIN `onyga-482313.OI.V_HOUSE_SEASONALITY` hs_now ON hs_now.calendar_month = nr.cur_mo
  LEFT JOIN `onyga-482313.OI.V_HOUSE_SEASONALITY` hs_f ON hs_f.calendar_month = g.forecast_month
  LEFT JOIN product_history_days ph ON ph.product = g.product
),

-- D8: final model-based output (same columns as family_based)
model_based AS (
  SELECT
    mf.product, mf.family, mf.forecast_year, mf.forecast_month,
    CAST(NULL AS INT64)   AS family_forecast_units,
    CAST(NULL AS FLOAT64) AS product_share,
    CASE
      WHEN mf.estimated_start_selling_date IS NULL THEN 0
      WHEN mf.estimated_start_selling_date IS NOT NULL
        AND DATE(mf.forecast_year, mf.forecast_month, 1)
            < DATE_TRUNC(mf.estimated_start_selling_date, MONTH)
      THEN 0
      ELSE (
        SELECT
          CASE
            WHEN mf.hist_days < mc.thin_history_days
              THEN LEAST(
                     ROUND(mf.anchor_rate
                           * LEAST(SAFE_DIVIDE(mf.ramp_f, NULLIF(mf.ramp_now,0)), mc.ramp_ceil)
                           * SAFE_DIVIDE(mf.season_f, NULLIF(mf.season_now,0))
                           * mf.days_in_month),
                     ROUND(mc.season_ceil * mf.anchor_rate * mf.days_in_month))
            ELSE ROUND(mf.anchor_rate
                       * SAFE_DIVIDE(mf.ramp_f, NULLIF(mf.ramp_now,0))
                       * SAFE_DIVIDE(mf.season_f, NULLIF(mf.season_now,0))
                       * mf.days_in_month)
          END
        FROM model_const mc
      )
    END AS forecast_units,
    TRUE  AS is_new_product,
    TRUE  AS is_draft,
    CAST(NULL AS FLOAT64) AS sqrt_lift,
    0     AS peak_days,
    CAST(mf.days_in_month AS INT64) AS offseason_days,
    CAST(NULL AS STRING) AS peak_holidays,
    mf.forecast_phase,
    mf.model_product,
    FALSE AS is_stable
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
