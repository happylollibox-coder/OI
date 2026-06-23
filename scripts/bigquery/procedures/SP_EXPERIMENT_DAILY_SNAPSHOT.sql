-- =============================================
-- OI Database Project - SP_EXPERIMENT_DAILY_SNAPSHOT Stored Procedure
-- =============================================
--
-- Purpose: Capture daily progress for active experiments into FACT_EXPERIMENT_DAILY
-- Method: MERGE (upsert on snapshot_date + experiment_id + asin)
-- Source: DIM_EXPERIMENT, DIM_EXPERIMENT_CAMPAIGN, FACT_AMAZON_ADS,
--         FACT_AMAZON_PERFORMANCE_DAILY, V_SEASONAL_INDEX_WEEKLY
-- Prefix convention:
--   ads_exp_*     = Amazon Ads, experiment campaigns only
--   ads_all_*     = Amazon Ads, all campaigns on this ASIN
--   performance_* = Business Reports (FACT_AMAZON_PERFORMANCE_DAILY)
--   seasonal_*    = Seasonally-adjusted metrics (using V_SEASONAL_INDEX_WEEKLY)
-- Schedule: Daily (added to SP_ORCHESTRATE_DAILY_REFRESH after FACT tables)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_EXPERIMENT_DAILY_SNAPSHOT`()
OPTIONS (
  description = "Capture daily progress snapshots for active experiments into FACT_EXPERIMENT_DAILY with seasonal adjustment"
)
BEGIN
  DECLARE snapshot_count INT64;

  -- =============================================
  -- For each active experiment, compute daily metrics and merge into FACT_EXPERIMENT_DAILY
  -- This backfills any missing days between experiment start_date and today
  -- Now includes seasonal adjustment from V_SEASONAL_INDEX_WEEKLY
  -- =============================================

  MERGE `onyga-482313.OI.FACT_EXPERIMENT_DAILY` AS target
  USING (
    WITH active_experiments AS (
      -- One row per experiment_id. DIM_EXPERIMENT has PRIMARY KEY (experiment_id)
      -- NOT ENFORCED, so BigQuery does not prevent duplicate rows (e.g. a
      -- double-submit from the Admin "assign campaign" endpoint, whose
      -- INSERT ... WHERE NOT EXISTS guard is not race-safe). A dup here would
      -- double the date spine and break the MERGE with
      -- "UPDATE/MERGE must match at most one source row". Keep the latest.
      SELECT
        e.experiment_id,
        e.start_date,
        COALESCE(e.end_date, CURRENT_DATE()) as effective_end_date,
        e.baseline_days,
        DATE_SUB(e.start_date, INTERVAL e.baseline_days DAY) as baseline_start
      FROM `onyga-482313.OI.DIM_EXPERIMENT` e
      WHERE e.status = 'ACTIVE'
      QUALIFY ROW_NUMBER() OVER (
        PARTITION BY e.experiment_id
        ORDER BY e.updated_at DESC, e.start_date DESC, e.baseline_days DESC
      ) = 1
    ),
    -- Generate date spine for each experiment (all dates from start to today)
    experiment_dates AS (
      SELECT
        ae.experiment_id,
        ae.start_date,
        ae.effective_end_date,
        ae.baseline_days,
        ae.baseline_start,
        d as snapshot_date
      FROM active_experiments ae,
      UNNEST(GENERATE_DATE_ARRAY(ae.start_date, LEAST(ae.effective_end_date, CURRENT_DATE()))) as d
    ),
    -- Get experiment ASINs
    experiment_asins AS (
      SELECT DISTINCT
        ec.experiment_id,
        fa.advertised_asins as asin
      FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
      JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec.campaign_id = fa.campaign_id
      WHERE fa.advertised_asins IS NOT NULL
        AND ec.experiment_id IN (SELECT experiment_id FROM active_experiments)
    ),
    -- Date x ASIN spine
    date_asin_spine AS (
      SELECT
        ed.experiment_id,
        ed.snapshot_date,
        ed.start_date,
        ed.baseline_start,
        ed.baseline_days,
        ea.asin,
        DATE_DIFF(ed.snapshot_date, ed.start_date, DAY) as day_number
      FROM experiment_dates ed
      JOIN experiment_asins ea ON ed.experiment_id = ea.experiment_id
    ),
    -- =============================================
    -- SEASONAL INDEX: Map each date to its weekly seasonal index
    -- SQP weeks run Sun-Sat; Reporting_Date = Saturday (week_end)
    -- =============================================
    seasonal_ref AS (
      SELECT
        iso_week,
        week_start,
        week_end,
        seasonal_index
      FROM `onyga-482313.OI.V_SEASONAL_INDEX_WEEKLY`
    ),
    -- Average seasonal index across each experiment's baseline period
    -- Uses range join on 2025 dates (baseline always falls in 2025 reference range)
    baseline_seasonal AS (
      SELECT
        das.experiment_id,
        das.asin,
        ROUND(AVG(si.seasonal_index), 4) as baseline_avg_seasonal_index
      FROM (SELECT DISTINCT experiment_id, asin, baseline_start, start_date FROM date_asin_spine) das
      LEFT JOIN seasonal_ref si
        ON si.week_end >= das.baseline_start
        AND si.week_start < das.start_date
      GROUP BY 1, 2
    ),
    -- Daily experiment campaign ads (ADS_ source)
    exp_ads_daily AS (
      SELECT
        ec.experiment_id,
        fa.date,
        fa.advertised_asins as asin,
        SUM(fa.Ads_orders) as orders,
        SUM(fa.Ads_units) as units,
        SUM(fa.Ads_cost) as cost,
        SUM(fa.Ads_sales) as sales
      FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
      JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec.campaign_id = fa.campaign_id
      WHERE ec.experiment_id IN (SELECT experiment_id FROM active_experiments)
      GROUP BY 1, 2, 3
    ),
    -- Daily ALL ads per ASIN (ADS_ source)
    all_ads_daily AS (
      SELECT
        das.experiment_id,
        fa.date,
        fa.advertised_asins as asin,
        SUM(fa.Ads_orders) as orders,
        SUM(fa.Ads_units) as units,
        SUM(fa.Ads_cost) as cost,
        SUM(fa.Ads_sales) as sales
      FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
      JOIN (SELECT DISTINCT experiment_id, asin FROM date_asin_spine) das
        ON fa.advertised_asins = das.asin
      WHERE fa.date >= (SELECT MIN(start_date) FROM active_experiments)
      GROUP BY 1, 2, 3
    ),
    -- Daily ASIN total performance (PERFORMANCE_ source: Business Reports)
    asin_perf_daily AS (
      SELECT
        fp.DATE as date,
        fp.PURCHASED_ASIN as asin,
        SUM(fp.PURCHASED_ORDERS) as performance_total_orders,
        SUM(fp.PURCHASED_UNITS) as performance_total_units,
        SUM(fp.PURCHASED_AMOUNT_USD) as performance_total_sales,
        SUM(fp.ASIN_SESSIONS) as performance_sessions,
        SUM(fp.ASIN_PAGE_VIEWS) as performance_page_views
      FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` fp
      WHERE fp.DATE >= (SELECT MIN(baseline_start) FROM active_experiments)
      GROUP BY 1, 2
    ),
    -- Baseline daily averages (PERFORMANCE_ source)
    baseline_avgs AS (
      SELECT
        das.experiment_id,
        das.asin,
        ROUND(AVG(COALESCE(ap.performance_total_orders, 0)), 4) as avg_daily_total_orders,
        ROUND(AVG(COALESCE(ap.performance_total_orders, 0) - COALESCE(aa.orders, 0)), 4) as avg_daily_organic_units,
        ROUND(AVG(COALESCE(ap.performance_total_sales, 0)), 4) as avg_daily_total_sales,
        ROUND(AVG(COALESCE(ap.performance_sessions, 0)), 4) as avg_daily_sessions
      FROM (SELECT DISTINCT experiment_id, asin, baseline_start, start_date FROM date_asin_spine) das
      LEFT JOIN asin_perf_daily ap
        ON ap.asin = das.asin
        AND ap.date >= das.baseline_start
        AND ap.date < das.start_date
      LEFT JOIN all_ads_daily aa
        ON aa.experiment_id = das.experiment_id
        AND aa.asin = das.asin
        AND aa.date = ap.date
      GROUP BY 1, 2
    ),
    -- Assemble daily rows
    daily_rows AS (
      SELECT
        das.snapshot_date,
        das.experiment_id,
        das.asin,
        das.day_number,

        -- Experiment ads (ADS_ source)
        COALESCE(ead.orders, 0) as ads_exp_orders,
        COALESCE(ead.units, 0) as ads_exp_units,
        COALESCE(ead.cost, 0) as ads_exp_cost,
        COALESCE(ead.sales, 0) as ads_exp_sales,

        -- All ads (ADS_ source)
        COALESCE(aad.orders, 0) as ads_all_orders,
        COALESCE(aad.units, 0) as ads_all_units,
        COALESCE(aad.cost, 0) as ads_all_cost,
        COALESCE(aad.sales, 0) as ads_all_sales,

        -- Total ASIN performance (PERFORMANCE_ source)
        COALESCE(apd.performance_total_orders, 0) as performance_total_orders,
        COALESCE(apd.performance_total_units, 0) as performance_total_units,
        COALESCE(apd.performance_total_sales, 0) as performance_total_sales,
        COALESCE(apd.performance_sessions, 0) as performance_sessions,
        COALESCE(apd.performance_page_views, 0) as performance_page_views,

        -- Organic (PERFORMANCE_ derived: total - all ads)
        COALESCE(apd.performance_total_units, 0) - COALESCE(aad.units, 0) as performance_organic_units,
        COALESCE(apd.performance_total_sales, 0) - COALESCE(aad.sales, 0) as performance_organic_sales,

        -- Cumulative (window functions)
        SUM(COALESCE(ead.orders, 0)) OVER (PARTITION BY das.experiment_id, das.asin ORDER BY das.snapshot_date) as cum_ads_exp_orders,
        SUM(COALESCE(ead.cost, 0)) OVER (PARTITION BY das.experiment_id, das.asin ORDER BY das.snapshot_date) as cum_ads_exp_cost,
        SUM(COALESCE(ead.sales, 0)) OVER (PARTITION BY das.experiment_id, das.asin ORDER BY das.snapshot_date) as cum_ads_exp_sales,
        SUM(COALESCE(aad.orders, 0)) OVER (PARTITION BY das.experiment_id, das.asin ORDER BY das.snapshot_date) as cum_ads_all_orders,
        SUM(COALESCE(apd.performance_total_orders, 0)) OVER (PARTITION BY das.experiment_id, das.asin ORDER BY das.snapshot_date) as cum_performance_total_orders,
        SUM(COALESCE(apd.performance_total_sales, 0)) OVER (PARTITION BY das.experiment_id, das.asin ORDER BY das.snapshot_date) as cum_performance_total_sales,
        SUM(COALESCE(apd.performance_total_orders, 0) - COALESCE(aad.orders, 0)) OVER (PARTITION BY das.experiment_id, das.asin ORDER BY das.snapshot_date) as cum_performance_organic_units,
        SUM(COALESCE(apd.performance_total_sales, 0) - COALESCE(aad.sales, 0)) OVER (PARTITION BY das.experiment_id, das.asin ORDER BY das.snapshot_date) as cum_performance_organic_sales,

        -- Baseline (PERFORMANCE_ source)
        ba.avg_daily_total_orders as performance_baseline_avg_daily_total_orders,
        ba.avg_daily_organic_units as performance_baseline_avg_daily_organic_units,
        ba.avg_daily_total_sales as performance_baseline_avg_daily_total_sales,
        ba.avg_daily_sessions as performance_baseline_avg_daily_sessions,

        -- Seasonal index for this day's week
        COALESCE(si.seasonal_index, 1.0) as seasonal_index,
        -- Baseline period avg seasonal index
        COALESCE(bsi.baseline_avg_seasonal_index, 1.0) as seasonal_index_baseline_avg,

        -- Seasonally-adjusted expected daily organic orders:
        -- "Given the baseline organic rate and the seasonal difference, how many orders should we expect today?"
        ROUND(
          ba.avg_daily_organic_units * SAFE_DIVIDE(
            COALESCE(si.seasonal_index, 1.0),
            NULLIF(COALESCE(bsi.baseline_avg_seasonal_index, 1.0), 0)
          )
        , 4) as performance_seasonal_expected_daily_orders,

        -- Cumulative seasonal expected (running sum of daily expected)
        SUM(
          ROUND(
            ba.avg_daily_organic_units * SAFE_DIVIDE(
              COALESCE(si.seasonal_index, 1.0),
              NULLIF(COALESCE(bsi.baseline_avg_seasonal_index, 1.0), 0)
            )
          , 4)
        ) OVER (PARTITION BY das.experiment_id, das.asin ORDER BY das.snapshot_date) as cum_performance_seasonal_expected_orders

      FROM date_asin_spine das
      LEFT JOIN exp_ads_daily ead
        ON ead.experiment_id = das.experiment_id AND ead.asin = das.asin AND ead.date = das.snapshot_date
      LEFT JOIN all_ads_daily aad
        ON aad.experiment_id = das.experiment_id AND aad.asin = das.asin AND aad.date = das.snapshot_date
      LEFT JOIN asin_perf_daily apd
        ON apd.asin = das.asin AND apd.date = das.snapshot_date
      LEFT JOIN baseline_avgs ba
        ON ba.experiment_id = das.experiment_id AND ba.asin = das.asin
      -- Join seasonal index: map snapshot_date to its SQP week by ISO week number
      -- This ensures 2026+ dates map to the same week-of-year seasonal pattern from 2025
      LEFT JOIN seasonal_ref si
        ON EXTRACT(ISOWEEK FROM das.snapshot_date) = si.iso_week
      -- Join baseline seasonal avg
      LEFT JOIN baseline_seasonal bsi
        ON bsi.experiment_id = das.experiment_id AND bsi.asin = das.asin
    )
    SELECT
      *,
      -- RAW organic lift vs baseline (no seasonal adjustment)
      ROUND(SAFE_DIVIDE(
        cum_performance_organic_units - (performance_baseline_avg_daily_organic_units * (day_number + 1)),
        NULLIF(performance_baseline_avg_daily_organic_units * (day_number + 1), 0)
      ), 4) as performance_organic_lift_vs_baseline,

      -- SEASONAL organic lift vs baseline
      -- Compares cumulative actual organic orders vs cumulative seasonally-adjusted expected orders
      ROUND(SAFE_DIVIDE(
        cum_performance_organic_units - cum_performance_seasonal_expected_orders,
        NULLIF(cum_performance_seasonal_expected_orders, 0)
      ), 4) as performance_seasonal_organic_lift_vs_baseline,

      -- factless_key for bridge joins (YYYYMMDD-ASIN)
      CONCAT(CAST(FORMAT_DATE('%Y%m%d', snapshot_date) AS STRING), '-', COALESCE(asin, 'UNKNOWN')) as factless_key
    FROM daily_rows
  ) AS source
  ON target.snapshot_date = source.snapshot_date
    AND target.experiment_id = source.experiment_id
    AND target.asin = source.asin
  WHEN MATCHED THEN UPDATE SET
    day_number = source.day_number,
    ads_exp_orders = source.ads_exp_orders,
    ads_exp_units = source.ads_exp_units,
    ads_exp_cost = source.ads_exp_cost,
    ads_exp_sales = source.ads_exp_sales,
    ads_all_orders = source.ads_all_orders,
    ads_all_units = source.ads_all_units,
    ads_all_cost = source.ads_all_cost,
    ads_all_sales = source.ads_all_sales,
    performance_total_orders = source.performance_total_orders,
    performance_total_units = source.performance_total_units,
    performance_total_sales = source.performance_total_sales,
    performance_sessions = source.performance_sessions,
    performance_page_views = source.performance_page_views,
    performance_organic_units = source.performance_organic_units,
    performance_organic_sales = source.performance_organic_sales,
    cum_ads_exp_orders = source.cum_ads_exp_orders,
    cum_ads_exp_cost = source.cum_ads_exp_cost,
    cum_ads_exp_sales = source.cum_ads_exp_sales,
    cum_ads_all_orders = source.cum_ads_all_orders,
    cum_performance_total_orders = source.cum_performance_total_orders,
    cum_performance_total_sales = source.cum_performance_total_sales,
    cum_performance_organic_units = source.cum_performance_organic_units,
    cum_performance_organic_sales = source.cum_performance_organic_sales,
    performance_baseline_avg_daily_total_orders = source.performance_baseline_avg_daily_total_orders,
    performance_baseline_avg_daily_organic_units = source.performance_baseline_avg_daily_organic_units,
    performance_baseline_avg_daily_total_sales = source.performance_baseline_avg_daily_total_sales,
    performance_baseline_avg_daily_sessions = source.performance_baseline_avg_daily_sessions,
    performance_organic_lift_vs_baseline = source.performance_organic_lift_vs_baseline,
    -- Seasonal columns
    seasonal_index = source.seasonal_index,
    seasonal_index_baseline_avg = source.seasonal_index_baseline_avg,
    performance_seasonal_expected_daily_orders = source.performance_seasonal_expected_daily_orders,
    cum_performance_seasonal_expected_orders = source.cum_performance_seasonal_expected_orders,
    performance_seasonal_organic_lift_vs_baseline = source.performance_seasonal_organic_lift_vs_baseline,
    factless_key = source.factless_key
  WHEN NOT MATCHED THEN INSERT (
    snapshot_date, experiment_id, asin, day_number,
    ads_exp_orders, ads_exp_units, ads_exp_cost, ads_exp_sales,
    ads_all_orders, ads_all_units, ads_all_cost, ads_all_sales,
    performance_total_orders, performance_total_units, performance_total_sales,
    performance_sessions, performance_page_views,
    performance_organic_units, performance_organic_sales,
    cum_ads_exp_orders, cum_ads_exp_cost, cum_ads_exp_sales,
    cum_ads_all_orders, cum_performance_total_orders, cum_performance_total_sales,
    cum_performance_organic_units, cum_performance_organic_sales,
    performance_baseline_avg_daily_total_orders, performance_baseline_avg_daily_organic_units,
    performance_baseline_avg_daily_total_sales, performance_baseline_avg_daily_sessions,
    performance_organic_lift_vs_baseline,
    seasonal_index, seasonal_index_baseline_avg,
    performance_seasonal_expected_daily_orders, cum_performance_seasonal_expected_orders,
    performance_seasonal_organic_lift_vs_baseline,
    factless_key
  ) VALUES (
    source.snapshot_date, source.experiment_id, source.asin, source.day_number,
    source.ads_exp_orders, source.ads_exp_units, source.ads_exp_cost, source.ads_exp_sales,
    source.ads_all_orders, source.ads_all_units, source.ads_all_cost, source.ads_all_sales,
    source.performance_total_orders, source.performance_total_units, source.performance_total_sales,
    source.performance_sessions, source.performance_page_views,
    source.performance_organic_units, source.performance_organic_sales,
    source.cum_ads_exp_orders, source.cum_ads_exp_cost, source.cum_ads_exp_sales,
    source.cum_ads_all_orders, source.cum_performance_total_orders, source.cum_performance_total_sales,
    source.cum_performance_organic_units, source.cum_performance_organic_sales,
    source.performance_baseline_avg_daily_total_orders, source.performance_baseline_avg_daily_organic_units,
    source.performance_baseline_avg_daily_total_sales, source.performance_baseline_avg_daily_sessions,
    source.performance_organic_lift_vs_baseline,
    source.seasonal_index, source.seasonal_index_baseline_avg,
    source.performance_seasonal_expected_daily_orders, source.cum_performance_seasonal_expected_orders,
    source.performance_seasonal_organic_lift_vs_baseline,
    source.factless_key
  );

  SET snapshot_count = @@row_count;

  SELECT FORMAT('SP_EXPERIMENT_DAILY_SNAPSHOT: Merged %d rows into FACT_EXPERIMENT_DAILY', snapshot_count) as log_message;
END;
