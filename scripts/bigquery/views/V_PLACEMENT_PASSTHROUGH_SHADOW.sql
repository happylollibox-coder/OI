-- =============================================================================
-- V_PLACEMENT_PASSTHROUGH_SHADOW
-- Status: SHADOW. Nothing reads it. Built 2026-08-11.
--
-- Per campaign x placement panel for measuring how much of a NOMINAL placement
-- bid adjustment actually reaches REALISED CPC ("pass-through").
--
-- Design: the placement adjustment is the ONLY placement-specific lever, so the
-- campaign's own un-adjusted placement is a valid within-campaign control and
-- the (unobservable, unreliable) stated bid cancels out of the ratio.
--   premium_p        = cpc_p / cpc_base
--   implied_pass_thr = (premium_p - intrinsic_premium_p) / (adjustment_p/100)
-- `intrinsic_premium_p` is supplied as the click-weighted mean premium of the
-- ZERO-adjustment campaigns on that same placement, computed inside the view.
--
-- CAVEATS baked into the column names, read them before using a number:
--  * adjustment_row_present  - SP omits 0% rows entirely, so a MISSING row means
--    0% for SP.  SB stores explicit 0 / negative rows, so for SB a missing row
--    means the campaign was not returned by the API (archived), NOT 0%.
--  * SNAPSHOT ONLY.  fivetran campaign_placement_bidding /
--    sb_campaign_bid_adjustments_by_placement carry one row per campaign+placement
--    with no history.  The adjustment is assumed constant across the window; it is
--    NOT.  (Verified counter-example: the four *-SP/PT (Product Defense) campaigns
--    had detail-page impression share 0.0-0.07 through May and 0.47-0.91 from June,
--    i.e. the +300% was switched on mid-window.)  Treat any single-campaign number
--    as an upper bound on the window-average dose.
--  * SB has no un-adjusted base placement in general (OTHER carries its own
--    adjustment), so SB rows report a RELATIVE dose vs the campaign's OTHER row.
--  * SB also carries a second, orthogonal multiplier - shopper-cohort adjustments,
--    up to +150% on the highest-volume SB campaigns.  Exposure share is not in any
--    report, so SB pass-through cannot be cleanly identified.  Column carried for
--    visibility only.
--  * 'Other on-Amazon' is rest-of-search + other on-Amazon surfaces and has no
--    adjustment lever; 'Off Amazon' likewise.  SITE_AMAZON_BUSINESS is a SITE
--    adjustment, not a placement - its clicks sit inside the four placement rows
--    and it is NOT netted out here.
-- =============================================================================
WITH win AS (
  SELECT DATE_SUB(MAX(date), INTERVAL 14 DAY)  AS d_end,
         DATE_SUB(MAX(date), INTERVAL 103 DAY) AS d_start
  FROM `fivetran-hl`.amazon_ads.campaign_placement_report
),

-- ---------- nominal adjustments (current snapshot, one row per campaign+placement)
adj AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id, 'SP' AS channel,
         CASE placement WHEN 'PLACEMENT_TOP'          THEN 'TOP_OF_SEARCH'
                        WHEN 'PLACEMENT_PRODUCT_PAGE' THEN 'DETAIL_PAGE'
                        WHEN 'SITE_AMAZON_BUSINESS'   THEN 'AMAZON_BUSINESS'
                        ELSE placement END AS placement,
         placement AS placement_raw_bidding,
         percentage AS adjustment_pct,
         _fivetran_synced AS adj_last_seen
  FROM `fivetran-hl`.amazon_ads.campaign_placement_bidding
  UNION ALL
  SELECT CAST(campaign_id AS STRING), 'SB',
         CASE placement WHEN 'HOME' THEN 'HOMEPAGE' ELSE placement END,
         placement, percentage, _fivetran_synced
  FROM `fivetran-hl`.amazon_ads.sb_campaign_bid_adjustments_by_placement
),

-- SB shopper-cohort multiplier (campaign grain; carried for visibility)
cohort AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id,
         MAX(percentage) AS sb_cohort_max_pct,
         COUNT(*)        AS sb_cohort_rows
  FROM `fivetran-hl`.amazon_ads.sb_campaign_bid_adjustments_shopper_cohort
  GROUP BY 1
),

-- ---------- realised placement performance
rpt AS (
  SELECT CAST(r.campaign_id AS STRING) AS campaign_id, 'SP' AS channel,
         CASE r.placement WHEN 'Top of Search on-Amazon' THEN 'TOP_OF_SEARCH'
                          WHEN 'Detail Page on-Amazon'   THEN 'DETAIL_PAGE'
                          WHEN 'Other on-Amazon'         THEN 'OTHER'
                          WHEN 'Off Amazon'              THEN 'OFF_AMAZON'
                          ELSE UPPER(REPLACE(r.placement,' ','_')) END AS placement,
         r.placement AS placement_raw_report,
         SUM(r.impressions) AS impressions, SUM(r.clicks) AS clicks, SUM(r.cost) AS cost,
         COUNT(DISTINCT r.date) AS days_with_data
  FROM `fivetran-hl`.amazon_ads.campaign_placement_report r, win
  WHERE r.date BETWEEN win.d_start AND win.d_end
  GROUP BY 1,2,3,4
  UNION ALL
  SELECT CAST(s.campaign_id AS STRING), 'SB',
         CASE s.placement WHEN 'Top of Search on-Amazon' THEN 'TOP_OF_SEARCH'
                          WHEN 'Detail Page on-Amazon'   THEN 'DETAIL_PAGE'
                          WHEN 'Other on-Amazon'         THEN 'OTHER'
                          WHEN 'Homepage on-Amazon'      THEN 'HOMEPAGE'
                          ELSE UPPER(REPLACE(s.placement,' ','_')) END,
         s.placement,
         SUM(s.impressions), SUM(s.clicks), SUM(s.cost), COUNT(DISTINCT s.report_date)
  FROM `fivetran-hl`.amazon_ads.sb_placement_report s, win
  WHERE s.report_date BETWEEN win.d_start AND win.d_end
  GROUP BY 1,2,3,4
),

-- ---------- the campaign's own base placement ('Other on-Amazon' = no lever on SP)
base AS (
  SELECT campaign_id, channel,
         SAFE_DIVIDE(SUM(cost), NULLIF(SUM(clicks),0)) AS base_cpc,
         SUM(clicks) AS base_clicks
  FROM rpt WHERE placement = 'OTHER'
  GROUP BY 1,2
),
camp_tot AS (
  SELECT campaign_id, channel, SUM(clicks) AS camp_clicks, SUM(impressions) AS camp_impr,
         SUM(cost) AS camp_cost
  FROM rpt GROUP BY 1,2
),

joined AS (
  SELECT
    r.channel, r.campaign_id, r.placement, r.placement_raw_report,
    a.placement_raw_bidding,
    a.adjustment_pct,
    a.adjustment_pct IS NOT NULL AS adjustment_row_present,
    -- SP: a missing row is a genuine 0%.  SB: a missing row is unknown.
    CASE WHEN a.adjustment_pct IS NOT NULL THEN a.adjustment_pct
         WHEN r.channel = 'SP' THEN 0
         ELSE NULL END AS adjustment_pct_effective,
    DATE(a.adj_last_seen) AS adjustment_last_seen_date,
    r.days_with_data, r.impressions, r.clicks, ROUND(r.cost,2) AS cost,
    SAFE_DIVIDE(r.cost, NULLIF(r.clicks,0)) AS cpc,
    SAFE_DIVIDE(r.clicks, NULLIF(t.camp_clicks,0))     AS click_share,
    SAFE_DIVIDE(r.impressions, NULLIF(t.camp_impr,0))  AS impression_share,
    t.camp_clicks, ROUND(t.camp_cost,2) AS campaign_cost,
    b.base_cpc, b.base_clicks,
    SAFE_DIVIDE(SAFE_DIVIDE(r.cost, NULLIF(r.clicks,0)), NULLIF(b.base_cpc,0)) AS premium_vs_base,
    c.sb_cohort_max_pct, c.sb_cohort_rows
  FROM rpt r
  LEFT JOIN adj  a ON a.campaign_id = r.campaign_id AND a.channel = r.channel AND a.placement = r.placement
  LEFT JOIN base b ON b.campaign_id = r.campaign_id AND b.channel = r.channel
  LEFT JOIN camp_tot t ON t.campaign_id = r.campaign_id AND t.channel = r.channel
  LEFT JOIN cohort c ON c.campaign_id = r.campaign_id AND r.channel = 'SB'
),

-- intrinsic (zero-dose) premium per channel x placement, click-weighted,
-- from campaigns that carry NO uplift on that placement
intrinsic AS (
  SELECT channel, placement,
         SAFE_DIVIDE(SUM(w * premium_vs_base), NULLIF(SUM(w),0)) AS intrinsic_premium,
         COUNT(*) AS intrinsic_n_campaigns,
         SUM(clicks) AS intrinsic_clicks
  FROM (
    SELECT channel, placement, premium_vs_base, clicks,
           SAFE_DIVIDE(1, SAFE_DIVIDE(1,clicks) + SAFE_DIVIDE(1,base_clicks)) AS w
    FROM joined
    WHERE placement <> 'OTHER'
      AND COALESCE(adjustment_pct_effective, -999) = 0
      AND clicks >= 10 AND base_clicks >= 10 AND premium_vs_base IS NOT NULL
  )
  GROUP BY 1,2
)

SELECT
  j.channel,
  j.campaign_id,
  dc.campaign_name,
  fam.parent_name        AS family,
  dc.state               AS campaign_state,
  dc.bidding_strategy,                       -- LEGACY_FOR_SALES = dynamic bids down-only
  j.placement,
  j.placement_raw_report,
  j.placement_raw_bidding,
  j.adjustment_row_present,
  j.adjustment_pct,                          -- raw, NULL when no row
  j.adjustment_pct_effective,                -- SP: NULL->0.  SB: stays NULL.
  j.adjustment_last_seen_date,
  j.days_with_data, j.impressions, j.clicks, j.cost,
  ROUND(j.cpc, 4)              AS cpc,
  ROUND(j.click_share, 4)      AS click_share,
  ROUND(j.impression_share, 4) AS impression_share,
  j.camp_clicks                AS campaign_clicks,
  j.campaign_cost,
  ROUND(j.base_cpc, 4)         AS base_cpc,
  j.base_clicks,
  ROUND(j.premium_vs_base, 4)  AS premium_vs_base,
  ROUND(i.intrinsic_premium, 4) AS intrinsic_premium,
  i.intrinsic_n_campaigns,
  -- the estimate.  NULL unless there is a real dose and both arms have volume.
  CASE WHEN j.adjustment_pct_effective > 0
        AND j.clicks >= 10 AND j.base_clicks >= 10
        AND i.intrinsic_premium IS NOT NULL
       THEN ROUND(SAFE_DIVIDE(j.premium_vs_base - i.intrinsic_premium,
                              j.adjustment_pct_effective/100.0), 4)
  END AS implied_pass_through,
  -- power flags
  (j.clicks >= 10 AND j.base_clicks >= 10)  AS has_both_arms,
  (j.clicks >= 30 AND j.base_clicks >= 30)  AS has_both_arms_30,
  COALESCE(j.adjustment_pct_effective,0) > 0 AS is_dosed,
  j.sb_cohort_max_pct,
  j.sb_cohort_rows,
  (SELECT d_start FROM win) AS window_start,
  (SELECT d_end   FROM win) AS window_end
FROM joined j
LEFT JOIN intrinsic i ON i.channel = j.channel AND i.placement = j.placement
LEFT JOIN `onyga-482313.OI.DIM_CAMPAIGN` dc
       ON dc.campaign_id = j.campaign_id AND dc.is_current
LEFT JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_FAMILY` fam
       ON fam.campaign_id = j.campaign_id
WHERE j.clicks > 0
