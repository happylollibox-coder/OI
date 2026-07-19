-- V_LAUNCH_CARD_DAILY — per (launch campaign, target, day) measures for the Weekly Run "New campaigns"
-- card template (section 4). One row per target per each of the last 3 COMPLETE days, so the card can
-- show, per target (close-match / loose-match / substitutes / a keyword): Spend, Clicks, CTR, units
-- sold, net ROAS — for each of the 3 days. Launch campaigns only (those in V_LAUNCH_PHASE1).
-- Spec: architecture/CAMPAIGN_LAUNCH_RAMP.md §"Phase 1".
CREATE OR REPLACE VIEW `onyga-482313.OI.V_LAUNCH_CARD_DAILY` AS
WITH wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
            FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
camp AS (SELECT DISTINCT campaign_id FROM `onyga-482313.OI.V_LAUNCH_PHASE1`),
f AS (
  SELECT CAST(a.campaign_id AS STRING) AS campaign_id, a.targeting AS target_text,
    UPPER(a.targeting_type) AS targeting_type, a.date,
    SUM(a.Ads_cost) AS spend, SUM(a.Ads_clicks) AS clicks, SUM(a.Ads_impressions) AS impressions,
    SUM(a.Ads_units) AS units, SUM(a.GROSS_PROFIT) AS gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN camp c ON c.campaign_id = CAST(a.campaign_id AS STRING)
  WHERE a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 2 DAY) AND (SELECT d FROM wm)
  GROUP BY 1, 2, 3, 4
)
SELECT
  campaign_id, target_text, targeting_type, date,
  -- day_rank: 1 = most recent complete day, 2 = day before, 3 = two days before
  DATE_DIFF((SELECT d FROM wm), date, DAY) + 1 AS day_rank,
  ROUND(spend, 2)                              AS spend,
  clicks,
  ROUND(100 * SAFE_DIVIDE(clicks, NULLIF(impressions, 0)), 1) AS ctr,   -- %
  units,
  ROUND(SAFE_DIVIDE(gp, NULLIF(spend, 0)), 2)  AS net_roas
FROM f
ORDER BY campaign_id, target_text, day_rank;
