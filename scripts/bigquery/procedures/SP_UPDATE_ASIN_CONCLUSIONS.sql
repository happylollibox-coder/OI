-- =============================================
-- OI Database Project - SP_UPDATE_ASIN_CONCLUSIONS Stored Procedure
-- =============================================
--
-- Purpose: Generate strategy-level conclusions from active experiments with 14+ days.
--          Creates/updates DRAFT rows; skips DISABLED rows.
--          Grain: asin + strategy_id + experiment_segment + season_context
--
-- Sources:
--   DIM_EXPERIMENT + DIM_EXPERIMENT_CAMPAIGN (experiment metadata)
--   FACT_EXPERIMENT_DAILY (daily performance snapshots)
--   FACT_AMAZON_ADS (per-campaign, per-format, per-term ad data)
--   FACT_SEARCH_QUERY (SQP weekly data for organic halo)
--   DIM_PRODUCT + DIM_COSTS_HISTORY (unit economics)
--
-- Schedule: Daily (after SP_EXPERIMENT_DAILY_SNAPSHOT in orchestrator)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_UPDATE_ASIN_CONCLUSIONS`()
OPTIONS (
  description = "Generate strategy-level conclusions from experiments with 14+ days. DRAFT rows auto-update; DISABLED rows are skipped."
)
BEGIN
  DECLARE conclusion_count INT64;

  MERGE `onyga-482313.OI.FACT_ASIN_CONCLUSIONS` AS target
  USING (
    WITH eligible_experiments AS (
      SELECT
        e.experiment_id,
        e.strategy_id,
        COALESCE(
          REGEXP_EXTRACT(e.experiment_id, CONCAT(e.strategy_id, '_(.+)$')),
          'UNKNOWN'
        ) as experiment_segment,
        e.start_date,
        COALESCE(e.end_date, CURRENT_DATE()) as effective_end_date,
        COALESCE(e.season_context, 'NORMAL') as season_context,
        DATE_DIFF(COALESCE(e.end_date, CURRENT_DATE()), e.start_date, DAY) as experiment_days
      FROM `onyga-482313.OI.DIM_EXPERIMENT` e
      WHERE e.status IN ('ACTIVE', 'COMPLETED')
        AND e.strategy_id IS NOT NULL
        AND DATE_DIFF(COALESCE(e.end_date, CURRENT_DATE()), e.start_date, DAY) >= 14
    ),

    asin_economics AS (
      SELECT
        p.asin,
        p.product_short_name,
        p.parent_name,
        COALESCE(ch.TOTAL_COST_PER_UNIT, 0) as total_cost,
        p.listing_price_amount - COALESCE(ch.TOTAL_COST_PER_UNIT, 0) as margin
      FROM `onyga-482313.OI.DIM_PRODUCT` p
      LEFT JOIN (
        SELECT asin, TOTAL_COST_PER_UNIT,
          ROW_NUMBER() OVER (PARTITION BY asin ORDER BY end_date DESC) as rn
        FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
      ) ch ON p.asin = ch.asin AND ch.rn = 1
      WHERE p.asin IS NOT NULL
    ),

    -- Tier 1+2: ASIN-level and ads-only metrics from FACT_EXPERIMENT_DAILY
    experiment_daily_agg AS (
      SELECT
        ee.experiment_id,
        ee.strategy_id,
        ee.experiment_segment,
        ee.season_context,
        ee.experiment_days,
        fed.asin,
        ue.product_short_name,
        ue.margin,
        SUM(fed.ads_exp_cost) as ad_spend,
        SUM(fed.ads_exp_orders) as ads_orders,
        SUM(fed.ads_exp_units) as ads_units,
        SUM(fed.ads_exp_sales) as ads_revenue,
        SUM(fed.performance_total_units) as total_units,
        SUM(fed.performance_total_units * ue.margin) as asin_net_revenue,
        SUM(fed.ads_exp_units * ue.margin) as ads_net_revenue,
        COUNT(DISTINCT fed.snapshot_date) as days_with_data
      FROM eligible_experiments ee
      JOIN `onyga-482313.OI.FACT_EXPERIMENT_DAILY` fed ON ee.experiment_id = fed.experiment_id
      JOIN asin_economics ue ON fed.asin = ue.asin
      GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
    ),

    -- Per ad-format breakdown from FACT_AMAZON_ADS
    format_breakdown AS (
      SELECT
        ec.experiment_id,
        fa.advertised_asins as asin,
        CASE
          WHEN fa.campaign_type = 'SB' AND UPPER(fa.campaign_name) LIKE '%VIDEO%' THEN 'SB_VIDEO'
          WHEN fa.campaign_type = 'SB' THEN 'SB_STORE'
          ELSE 'SP'
        END as ad_format,
        SUM(fa.Ads_cost) as fmt_cost,
        SUM(fa.Ads_orders) as fmt_orders,
        SUM(fa.Ads_units) as fmt_units,
        SUM(fa.Ads_clicks) as fmt_clicks
      FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
      JOIN eligible_experiments ee ON ec.experiment_id = ee.experiment_id
      JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
        ON ec.campaign_id = fa.campaign_id
        AND fa.date >= ee.start_date
        AND fa.date <= ee.effective_end_date
      WHERE fa.advertised_asins IS NOT NULL
      GROUP BY 1, 2, 3
    ),

    -- Tier 3: SQP metrics from FACT_SEARCH_QUERY
    sqp_metrics AS (
      SELECT
        ec.experiment_id,
        fa_terms.asin,
        SUM(fsq.conversions) as sqp_purchases,
        COUNT(DISTINCT fsq.query_text) as sqp_matched_terms,
        COUNT(DISTINCT fsq.week_end_date) as sqp_weeks
      FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
      JOIN eligible_experiments ee ON ec.experiment_id = ee.experiment_id
      JOIN (
        SELECT DISTINCT campaign_id, LOWER(search_term) as search_term, advertised_asins as asin
        FROM `onyga-482313.OI.FACT_AMAZON_ADS`
        WHERE search_term IS NOT NULL AND search_term != ''
      ) fa_terms ON ec.campaign_id = fa_terms.campaign_id
      JOIN `onyga-482313.OI.FACT_SEARCH_QUERY` fsq
        ON LOWER(fsq.query_text) = fa_terms.search_term
        AND fsq.ASIN = fa_terms.asin
        AND fsq.data_source = 'SQP'
        AND fsq.week_end_date >= ee.start_date
      GROUP BY 1, 2
    ),

    -- Ads CPC data
    ads_bidding AS (
      SELECT
        ec.experiment_id,
        SAFE_DIVIDE(SUM(fa.Ads_cost), NULLIF(SUM(fa.Ads_clicks), 0)) as avg_cpc
      FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
      JOIN eligible_experiments ee ON ec.experiment_id = ee.experiment_id
      JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
        ON ec.campaign_id = fa.campaign_id
        AND fa.date >= ee.start_date
      WHERE fa.Ads_clicks > 0
      GROUP BY 1
    ),

    -- Parent-family metrics: cross-sibling impact
    experiment_family_members AS (
      SELECT DISTINCT
        ee.experiment_id,
        ue_exp.parent_name,
        ue_sib.asin as sibling_asin,
        COALESCE(ue_sib.margin, 0) as sibling_margin
      FROM eligible_experiments ee
      JOIN `onyga-482313.OI.FACT_EXPERIMENT_DAILY` fed ON ee.experiment_id = fed.experiment_id
      JOIN asin_economics ue_exp ON fed.asin = ue_exp.asin
      JOIN asin_economics ue_sib ON ue_exp.parent_name = ue_sib.parent_name
      WHERE ue_exp.parent_name IS NOT NULL
        AND ue_sib.asin IS NOT NULL AND ue_sib.asin != 'UNKNOWN'
    ),

    parent_family_units AS (
      SELECT
        efm.experiment_id,
        efm.parent_name,
        SUM(fp.PURCHASED_UNITS) as family_units,
        SUM(fp.PURCHASED_UNITS * efm.sibling_margin) as family_gross_margin
      FROM experiment_family_members efm
      JOIN eligible_experiments ee ON efm.experiment_id = ee.experiment_id
      JOIN `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` fp
        ON efm.sibling_asin = fp.PURCHASED_ASIN
        AND fp.DATE >= ee.start_date
        AND fp.DATE <= ee.effective_end_date
      GROUP BY 1, 2
    ),

    parent_family_ads_deduped AS (
      SELECT DISTINCT
        efm.experiment_id,
        efm.parent_name,
        fa.campaign_id,
        fa.date,
        fa.advertised_asins,
        fa.search_term,
        fa.Ads_cost
      FROM experiment_family_members efm
      JOIN eligible_experiments ee ON efm.experiment_id = ee.experiment_id
      JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
        ON REGEXP_CONTAINS(fa.advertised_asins, efm.sibling_asin)
        AND fa.date >= ee.start_date
        AND fa.date <= ee.effective_end_date
      WHERE fa.advertised_asins IS NOT NULL
    ),

    parent_family_ad_spend AS (
      SELECT experiment_id, parent_name, SUM(Ads_cost) as family_ad_cost
      FROM parent_family_ads_deduped
      GROUP BY 1, 2
    ),

    parent_family_perf AS (
      SELECT
        pfu.experiment_id,
        pfu.parent_name,
        COALESCE(pfu.family_units, 0) as parent_family_units,
        ROUND(COALESCE(pfu.family_gross_margin, 0) - COALESCE(pfas.family_ad_cost, 0), 2) as parent_family_net_profit,
        ROUND(SAFE_DIVIDE(pfu.family_gross_margin, NULLIF(pfas.family_ad_cost, 0)), 2) as parent_family_net_roas,
        ROUND(COALESCE(pfas.family_ad_cost, 0), 2) as parent_family_ad_spend
      FROM parent_family_units pfu
      LEFT JOIN parent_family_ad_spend pfas
        ON pfu.experiment_id = pfas.experiment_id AND pfu.parent_name = pfas.parent_name
    ),

    -- Assemble per experiment+asin conclusions
    experiment_conclusions AS (
      SELECT
        eda.asin,
        eda.strategy_id,
        eda.experiment_segment,
        eda.season_context,
        eda.experiment_id,
        eda.product_short_name,
        eda.margin,
        eda.experiment_days,
        eda.ad_spend,
        eda.ads_orders,
        eda.ads_units,
        eda.ads_revenue,
        eda.days_with_data,
        -- Tier 2: ads only
        SAFE_DIVIDE(eda.ads_net_revenue, NULLIF(eda.ad_spend, 0)) as ads_only_net_roas,
        -- Tier 3: SQP
        SAFE_DIVIDE(sqp.sqp_purchases * eda.margin, NULLIF(eda.ad_spend, 0)) as sqp_net_roas,
        sqp.sqp_purchases,
        sqp.sqp_matched_terms,
        sqp.sqp_weeks,
        -- Tier 1: ASIN level
        SAFE_DIVIDE(eda.asin_net_revenue, NULLIF(eda.ad_spend, 0)) as asin_net_roas,
        -- Traditional
        SAFE_DIVIDE(eda.ads_revenue, NULLIF(eda.ad_spend, 0)) as trad_roas,
        -- Per format
        sp.fmt_cost as sp_cost, sp.fmt_orders as sp_orders,
        SAFE_DIVIDE(sp.fmt_units * eda.margin, NULLIF(sp.fmt_cost, 0)) as sp_net_roas,
        vid.fmt_cost as vid_cost, vid.fmt_orders as vid_orders,
        SAFE_DIVIDE(vid.fmt_units * eda.margin, NULLIF(vid.fmt_cost, 0)) as vid_net_roas,
        st.fmt_cost as st_cost, st.fmt_orders as st_orders,
        SAFE_DIVIDE(st.fmt_units * eda.margin, NULLIF(st.fmt_cost, 0)) as st_net_roas,
        -- Bidding
        ab.avg_cpc,
        -- Parent family
        pfp.parent_name,
        pfp.parent_family_units,
        pfp.parent_family_net_profit,
        pfp.parent_family_net_roas,
        pfp.parent_family_ad_spend
      FROM experiment_daily_agg eda
      LEFT JOIN sqp_metrics sqp ON eda.experiment_id = sqp.experiment_id AND eda.asin = sqp.asin
      LEFT JOIN format_breakdown sp ON eda.experiment_id = sp.experiment_id AND eda.asin = sp.asin AND sp.ad_format = 'SP'
      LEFT JOIN format_breakdown vid ON eda.experiment_id = vid.experiment_id AND eda.asin = vid.asin AND vid.ad_format = 'SB_VIDEO'
      LEFT JOIN format_breakdown st ON eda.experiment_id = st.experiment_id AND eda.asin = st.asin AND st.ad_format = 'SB_STORE'
      LEFT JOIN ads_bidding ab ON eda.experiment_id = ab.experiment_id
      LEFT JOIN parent_family_perf pfp ON eda.experiment_id = pfp.experiment_id
      WHERE eda.ad_spend > 0
    ),

    -- Aggregate across experiments with same asin+strategy+segment+season
    aggregated AS (
      SELECT
        ec.asin,
        ec.strategy_id,
        ec.experiment_segment,
        ec.season_context,
        -- 3-tier ROAS (weighted by spend)
        ROUND(SAFE_DIVIDE(SUM(ec.ads_only_net_roas * ec.ad_spend), NULLIF(SUM(ec.ad_spend), 0)), 2) as ads_only_net_roas,
        ROUND(SAFE_DIVIDE(SUM(ec.sqp_net_roas * ec.ad_spend), NULLIF(SUM(CASE WHEN ec.sqp_net_roas IS NOT NULL THEN ec.ad_spend END), 0)), 2) as sqp_net_roas,
        ROUND(SAFE_DIVIDE(SUM(ec.asin_net_roas * ec.ad_spend), NULLIF(SUM(ec.ad_spend), 0)), 2) as asin_net_roas,
        ROUND(SAFE_DIVIDE(SUM(ec.trad_roas * ec.ad_spend), NULLIF(SUM(ec.ad_spend), 0)), 2) as traditional_roas,
        -- SQP totals
        SUM(ec.sqp_purchases) as sqp_organic_purchases,
        MAX(ec.sqp_matched_terms) as sqp_matched_terms,
        MAX(ec.sqp_weeks) as sqp_weeks_observed,
        -- Per format
        ROUND(SAFE_DIVIDE(SUM(ec.sp_net_roas * ec.sp_cost), NULLIF(SUM(ec.sp_cost), 0)), 2) as sp_net_roas,
        ROUND(SUM(ec.sp_cost), 2) as sp_cost,
        SUM(ec.sp_orders) as sp_orders,
        ROUND(SAFE_DIVIDE(SUM(ec.vid_net_roas * ec.vid_cost), NULLIF(SUM(ec.vid_cost), 0)), 2) as sb_video_net_roas,
        ROUND(SUM(ec.vid_cost), 2) as sb_video_cost,
        SUM(ec.vid_orders) as sb_video_orders,
        ROUND(SAFE_DIVIDE(SUM(ec.st_net_roas * ec.st_cost), NULLIF(SUM(ec.st_cost), 0)), 2) as sb_store_net_roas,
        ROUND(SUM(ec.st_cost), 2) as sb_store_cost,
        SUM(ec.st_orders) as sb_store_orders,
        -- Budget and bidding
        ROUND(SAFE_DIVIDE(SUM(ec.ad_spend), NULLIF(SUM(ec.days_with_data), 0)), 2) as proven_daily_budget,
        ROUND(SAFE_DIVIDE(SUM(ec.avg_cpc * ec.ad_spend), NULLIF(SUM(ec.ad_spend), 0)), 2) as avg_cpc,
        CAST(NULL AS FLOAT64) as avg_bid,
        -- Data backing
        COUNT(DISTINCT ec.experiment_id) as experiment_count,
        SUM(ec.experiment_days) as total_experiment_days,
        ROUND(SUM(ec.ad_spend), 2) as total_ad_spend,
        ARRAY_AGG(DISTINCT ec.experiment_id) as contributing_experiment_ids,
        -- Context
        MAX(ec.product_short_name) as product_short_name,
        ROUND(AVG(ec.margin), 2) as avg_margin_per_unit,
        -- Parent family (take from most recent / largest experiment)
        MAX(ec.parent_name) as parent_name,
        ROUND(AVG(ec.parent_family_net_profit), 2) as parent_family_net_profit,
        ROUND(SAFE_DIVIDE(
          SUM(ec.parent_family_net_roas * ec.ad_spend),
          NULLIF(SUM(CASE WHEN ec.parent_family_net_roas IS NOT NULL THEN ec.ad_spend END), 0)
        ), 2) as parent_family_net_roas,
        ROUND(AVG(ec.parent_family_ad_spend), 2) as parent_family_ad_spend,
        CAST(ROUND(AVG(ec.parent_family_units), 0) AS INT64) as parent_family_units
      FROM experiment_conclusions ec
      GROUP BY 1, 2, 3, 4
    ),

    -- Generate learning_summary text
    final AS (
      SELECT
        a.*,
        CONCAT(
          a.strategy_id, ' on ', COALESCE(a.product_short_name, a.asin),
          ' (', a.experiment_segment, '/',  a.season_context, '): ',
          CASE
            WHEN a.ads_only_net_roas >= 1.5 THEN 'PROFITABLE'
            WHEN a.ads_only_net_roas >= 1.0 THEN 'BREAK-EVEN'
            WHEN a.ads_only_net_roas IS NOT NULL THEN 'LOSING'
            ELSE 'NO DATA'
          END,
          ' ads ROAS ', COALESCE(CAST(a.ads_only_net_roas AS STRING), 'N/A'),
          CASE WHEN a.sqp_net_roas IS NOT NULL THEN CONCAT(', SQP ROAS ', CAST(a.sqp_net_roas AS STRING)) ELSE '' END,
          '. ',
          CASE
            WHEN a.sp_cost > 0 AND a.sb_video_cost > 0
              THEN CONCAT('SP ROAS=', COALESCE(CAST(a.sp_net_roas AS STRING), '?'), ' VIDEO ROAS=', COALESCE(CAST(a.sb_video_net_roas AS STRING), '?'), '. ')
            WHEN a.sp_cost > 0
              THEN CONCAT('SP only (ROAS=', COALESCE(CAST(a.sp_net_roas AS STRING), '?'), '). ')
            ELSE ''
          END,
          'Spend $', CAST(ROUND(a.total_ad_spend, 0) AS STRING),
          ' over ', CAST(a.total_experiment_days AS STRING), ' days',
          CASE WHEN a.sqp_organic_purchases IS NOT NULL AND a.sqp_organic_purchases > 0
            THEN CONCAT(', ', CAST(a.sqp_organic_purchases AS STRING), ' organic+ads purchases on ', CAST(a.sqp_matched_terms AS STRING), ' search terms')
            ELSE ''
          END,
          '. ',
          CASE WHEN a.parent_name IS NOT NULL AND a.parent_family_net_roas IS NOT NULL
            THEN CONCAT('Family (', a.parent_name, '): net profit $', CAST(ROUND(a.parent_family_net_profit, 0) AS STRING),
                         ', ROAS ', CAST(a.parent_family_net_roas AS STRING), '.')
            ELSE ''
          END
        ) as learning_summary
      FROM aggregated a
    )
    SELECT * FROM final
  ) AS source
  ON target.asin = source.asin
    AND target.strategy_id = source.strategy_id
    AND target.experiment_segment = source.experiment_segment
    AND target.season_context = source.season_context
    AND target.status != 'DISABLED'
  WHEN MATCHED THEN UPDATE SET
    updated_at = CURRENT_TIMESTAMP(),
    ads_only_net_roas = source.ads_only_net_roas,
    sqp_net_roas = source.sqp_net_roas,
    asin_net_roas = source.asin_net_roas,
    traditional_roas = source.traditional_roas,
    sqp_organic_purchases = source.sqp_organic_purchases,
    sqp_matched_terms = source.sqp_matched_terms,
    sqp_weeks_observed = source.sqp_weeks_observed,
    sp_net_roas = source.sp_net_roas,
    sp_cost = source.sp_cost,
    sp_orders = source.sp_orders,
    sb_video_net_roas = source.sb_video_net_roas,
    sb_video_cost = source.sb_video_cost,
    sb_video_orders = source.sb_video_orders,
    sb_store_net_roas = source.sb_store_net_roas,
    sb_store_cost = source.sb_store_cost,
    sb_store_orders = source.sb_store_orders,
    proven_daily_budget = source.proven_daily_budget,
    avg_cpc = source.avg_cpc,
    avg_bid = source.avg_bid,
    experiment_count = source.experiment_count,
    total_experiment_days = source.total_experiment_days,
    total_ad_spend = source.total_ad_spend,
    contributing_experiment_ids = source.contributing_experiment_ids,
    learning_summary = source.learning_summary,
    product_short_name = source.product_short_name,
    avg_margin_per_unit = source.avg_margin_per_unit,
    parent_name = source.parent_name,
    parent_family_net_profit = source.parent_family_net_profit,
    parent_family_net_roas = source.parent_family_net_roas,
    parent_family_ad_spend = source.parent_family_ad_spend,
    parent_family_units = source.parent_family_units
  WHEN NOT MATCHED THEN INSERT (
    asin, strategy_id, experiment_segment, season_context,
    status, created_at, updated_at,
    ads_only_net_roas, sqp_net_roas, asin_net_roas, traditional_roas,
    sqp_organic_purchases, sqp_matched_terms, sqp_weeks_observed,
    sp_net_roas, sp_cost, sp_orders,
    sb_video_net_roas, sb_video_cost, sb_video_orders,
    sb_store_net_roas, sb_store_cost, sb_store_orders,
    proven_daily_budget, avg_cpc, avg_bid,
    experiment_count, total_experiment_days, total_ad_spend, contributing_experiment_ids,
    learning_summary, product_short_name, avg_margin_per_unit,
    parent_name, parent_family_net_profit, parent_family_net_roas, parent_family_ad_spend, parent_family_units
  ) VALUES (
    source.asin, source.strategy_id, source.experiment_segment, source.season_context,
    'DRAFT', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(),
    source.ads_only_net_roas, source.sqp_net_roas, source.asin_net_roas, source.traditional_roas,
    source.sqp_organic_purchases, source.sqp_matched_terms, source.sqp_weeks_observed,
    source.sp_net_roas, source.sp_cost, source.sp_orders,
    source.sb_video_net_roas, source.sb_video_cost, source.sb_video_orders,
    source.sb_store_net_roas, source.sb_store_cost, source.sb_store_orders,
    source.proven_daily_budget, source.avg_cpc, source.avg_bid,
    source.experiment_count, source.total_experiment_days, source.total_ad_spend, source.contributing_experiment_ids,
    source.learning_summary, source.product_short_name, source.avg_margin_per_unit,
    source.parent_name, source.parent_family_net_profit, source.parent_family_net_roas, source.parent_family_ad_spend, source.parent_family_units
  );

  SET conclusion_count = @@row_count;

  SELECT FORMAT(
    'SP_UPDATE_ASIN_CONCLUSIONS: %d conclusions created/updated. DISABLED conclusions preserved.',
    conclusion_count
  ) as log_message;
END;
