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
-- Grain: one row per (parent_name, campaign_name), stuck campaigns only.
-- Source: V_ADS_COACH (campaign-level fields), deduped to campaign via ANY_VALUE.
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
)
SELECT
  parent_name, campaign_name, campaign_state, budget_util_pct, budget,
  recent_orders, net_roas, share_8w, share_ly, days_since_budget_chg,
  CASE
    WHEN UPPER(campaign_state) != 'ENABLED'                                              THEN 'PAUSED'
    WHEN budget_util_pct >= 85                                                           THEN 'BUDGET_CAPPED'
    WHEN COALESCE(budget_util_pct, 0) = 0 AND days_since_budget_chg >= 60 AND share_ly > 0 THEN 'DORMANT'
    WHEN share_ly > 0 AND share_8w < share_ly * 0.6                                      THEN 'SHARE_DROPPED'
  END AS stuck_flag,
  CASE
    WHEN UPPER(campaign_state) != 'ENABLED'                                              THEN 'Paused — reactivate for the peak'
    WHEN budget_util_pct >= 85                                                           THEN CONCAT('Budget-capped at ', CAST(budget_util_pct AS STRING), '% on $', CAST(budget AS STRING), '/day — raise before the peak')
    WHEN COALESCE(budget_util_pct, 0) = 0 AND days_since_budget_chg >= 60 AND share_ly > 0 THEN CONCAT('Dormant ', CAST(days_since_budget_chg AS STRING), 'd (held ', CAST(ROUND(share_ly*100,1) AS STRING), '% share LY) — refresh')
    ELSE                                                                                     CONCAT('Impression share ', CAST(ROUND(share_8w*100,1) AS STRING), '% vs ', CAST(ROUND(share_ly*100,1) AS STRING), '% LY — losing ground')
  END AS reason
FROM camp
WHERE UPPER(campaign_state) != 'ENABLED'
   OR budget_util_pct >= 85
   OR (COALESCE(budget_util_pct, 0) = 0 AND days_since_budget_chg >= 60 AND share_ly > 0)
   OR (share_ly > 0 AND share_8w < share_ly * 0.6);
