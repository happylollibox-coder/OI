-- =============================================
-- V_PEAK_STUCK_CAMPAIGNS — campaigns to refresh before a peak
-- =============================================
--
-- Surfaces campaigns that won't capture peak demand as-is, per family:
--   PAUSED        — not ENABLED (reactivate for the peak)
--   BUDGET_CAPPED — budget utilization >= 85% (raise budget so it doesn't run out)
--   DORMANT       — spending ~nothing for >=60d but held real impression share last year
--   SHARE_DROPPED — current impression share collapsed vs last year (<60% of LY)
--
-- Track-record gate: only show a stuck campaign that was a SUCCESS at some point — lifetime
-- (all-time) orders >= 1 AND lifetime Ads ROAS (sales/cost) >= 1.0. Drops perpetual money-losers
-- AND never-sold pilots (no point reviving a campaign that never worked). Low-volume-but-
-- profitable campaigns (e.g. brand defense) are kept. Lifetime stats appended to the reason.
--
-- Grain: one row per (parent_name, campaign_name), stuck + worth-refreshing only.
-- Sources: V_ADS_COACH (campaign health), FACT_AMAZON_ADS (lifetime performance).
-- Consumer: PeakStuckCampaigns cube → Peak page "Stuck campaigns" card.
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_PEAK_STUCK_CAMPAIGNS` AS

WITH camp AS (
  SELECT
    campaign_name,
    ANY_VALUE(parent_name)                          AS parent_name,
    ANY_VALUE(campaign_state)                       AS campaign_state,
    ROUND(ANY_VALUE(camp_budget_util_pct), 0)       AS budget_util_pct,
    ANY_VALUE(current_budget)                       AS budget,
    ANY_VALUE(pp_campaign_orders)                   AS recent_orders,
    ROUND(ANY_VALUE(pp_campaign_net_roas), 2)       AS net_roas,
    ROUND(ANY_VALUE(sqp_impression_share_8w), 3)    AS share_8w,
    ROUND(ANY_VALUE(sqp_ly_impression_share), 3)    AS share_ly,
    ANY_VALUE(days_since_last_budget_change)        AS days_since_budget_chg
  FROM `onyga-482313.OI.V_ADS_COACH`
  WHERE campaign_name IS NOT NULL
  GROUP BY campaign_name
),

-- Lifetime track record per campaign (all dates) — was it ever a success?
lifetime AS (
  SELECT
    campaign_name,
    SUM(Ads_orders) AS lt_orders,
    ROUND(SUM(Ads_cost), 0) AS lt_spend,
    ROUND(SAFE_DIVIDE(SUM(Ads_sales), NULLIF(SUM(Ads_cost), 0)), 2) AS lt_roas
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE campaign_name IS NOT NULL
  GROUP BY campaign_name
)

SELECT
  c.parent_name, c.campaign_name, c.campaign_state, c.budget_util_pct, c.budget,
  c.recent_orders, c.net_roas, c.share_8w, c.share_ly, c.days_since_budget_chg,
  l.lt_orders, l.lt_roas,
  CASE
    WHEN UPPER(c.campaign_state) != 'ENABLED'                                                  THEN 'PAUSED'
    WHEN c.budget_util_pct >= 85                                                               THEN 'BUDGET_CAPPED'
    WHEN COALESCE(c.budget_util_pct, 0) = 0 AND c.days_since_budget_chg >= 60 AND c.share_ly > 0 THEN 'DORMANT'
    WHEN c.share_ly > 0 AND c.share_8w < c.share_ly * 0.6                                       THEN 'SHARE_DROPPED'
  END AS stuck_flag,
  CONCAT(
    CASE
      WHEN UPPER(c.campaign_state) != 'ENABLED'                                                  THEN 'Paused — reactivate for the peak'
      WHEN c.budget_util_pct >= 85                                                               THEN CONCAT('Budget-capped at ', CAST(c.budget_util_pct AS STRING), '% on $', CAST(c.budget AS STRING), '/day — raise before the peak')
      WHEN COALESCE(c.budget_util_pct, 0) = 0 AND c.days_since_budget_chg >= 60 AND c.share_ly > 0 THEN CONCAT('Dormant ', CAST(c.days_since_budget_chg AS STRING), 'd (held ', CAST(ROUND(c.share_ly*100,1) AS STRING), '% share LY) — refresh')
      ELSE                                                                                          CONCAT('Impression share ', CAST(ROUND(c.share_8w*100,1) AS STRING), '% vs ', CAST(ROUND(c.share_ly*100,1) AS STRING), '% LY — losing ground')
    END,
    ' · lifetime ', CAST(COALESCE(l.lt_orders, 0) AS STRING), ' ord / ', CAST(COALESCE(l.lt_roas, 0) AS STRING), 'x ROAS'
  ) AS reason
FROM camp c
LEFT JOIN lifetime l ON l.campaign_name = c.campaign_name
WHERE (
       UPPER(c.campaign_state) != 'ENABLED'
    OR c.budget_util_pct >= 85
    OR (COALESCE(c.budget_util_pct, 0) = 0 AND c.days_since_budget_chg >= 60 AND c.share_ly > 0)
    OR (c.share_ly > 0 AND c.share_8w < c.share_ly * 0.6)
  )
  -- Track-record gate: only campaigns that were a success at some point (lifetime).
  AND COALESCE(l.lt_orders, 0) >= 1
  AND COALESCE(l.lt_roas, 0) >= 1.0;
