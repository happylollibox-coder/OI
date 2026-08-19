-- V_CAMPAIGN_CAP_STATE — THE single membership function for the capped-campaign engines (v27.45).
-- Spec: architecture/OOB_BUDGET_PHASE.md §v27.45.
--
-- WHY (iteration-4 D3/D5 + iteration-5 3.2/3.7, ~$5.2k/wk): three views disagreed about who owns
-- a capped campaign. V_OOB_BUDGET_PHASE membership was an ANCHOR-DAY test (pd>0 OR spend>=budget,
-- v27.15) — 25 chronically-capped campaigns ($3,227/7d) were invisible to the budget ladder
-- because their anchor day happened to come in light, incl. a Brand Defense campaign and the
-- 1.37x GP-ROAS ME-VIDEO/BROAD Hunter. V_OOB_KEYWORD filtered further to pct_dark > 10, leaving
-- 12 PHASE campaigns outside the bid engine entirely. This view is the ONE membership function:
-- both V_OOB_BUDGET_PHASE membership and V_OOB_KEYWORD population read is_oob_owned from HERE.
--
-- GRAIN: one row per ENABLED campaign (campaign_state = ENABLED, serving_status in
-- CAMPAIGN_STATUS_ENABLED / CAMPAIGN_OUT_OF_BUDGET) at its channel's anchor day.
--
-- capped_day (per-day v27.15 dual signal, computed per DAY not just the anchor):
--   >= 1 CAMPAIGN_OUT_OF_BUDGET event in V_SRC_AmazonAds_campaign_history that
--   America/Los_Angeles day (equivalent to per-day pd>0 under the view's midnight-seed replay)
--   OR day spend >= day budget (budget from DIM_CAMPAIGN SCD2 effective ranges; SP spend from
--   FACT_AMAZON_ADS, SB spend from sb_campaign_report — mirrors V_OOB_BUDGET_PHASE's channel
--   split; per-channel anchors LEAST(MAX(date), FN_ADS_ANCHOR_CAP())).
--
-- is_oob_owned — CALIBRATED HYSTERESIS (read-only calibration 2026-08-08, 14 anchors):
--   ENTER when days_capped_7d >= 2 · EXIT only when days_capped_7d = 0 (ownership holds while
--   >= 1 once entered). Chosen over fixed N>=1 (7 weak-evidence ownerships incl. a 22%-util
--   campaign), N>=2 (same capture, 1.8x the flip rate — 27.5 flips/wk, counts hover at the 1<->2
--   boundary), N>=3 (DISQUALIFIED: recreates the silent-cap gap it exists to close). Hysteresis:
--   49 owned, $7,306.67/7d governed (76% of ENABLED spend), 15.1 flips/wk, all 12 silent-caps +
--   Brand Defense + ME-VIDEO/BROAD captured. PARITY: the anchor-day capped flag reproduced the
--   live v27.15 membership 28/28 exactly, so the grid is a faithful per-day extension.
--   STATELESS IMPLEMENTATION (both formulations tested identically over 14 anchors): entered =
--   any of the last 7 anchor days had days_capped_7d >= 2 computed AT that day, still >= 1 now —
--   no persisted state. Exit-at-0 tail: a campaign that stops capping stays owned for up to 7
--   days after its last capped day — the price of stability, consistent with 'OOB owns while
--   dark' since the dark evidence is still inside the 7d window.
--
-- CONSUMERS: V_OOB_BUDGET_PHASE (membership + is_oob_owned/days_capped_7d passthrough columns),
-- V_OOB_KEYWORD (population via PHASE), V_KEYWORD_LIFT (DEFER_OOB routing). DEFENSE doctrine:
-- ownership never moves a defense campaign's bids — its keywords stay DEFENSE/hold in both
-- engines; the budget ladder is its only remedy (is_defense is exposed here for that routing).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_CAP_STATE` AS
WITH
wm_sp AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
          FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
wm_sb AS (SELECT LEAST(MAX(report_date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
          FROM `fivetran-hl.amazon_ads.sb_campaign_report`),
camp AS (
  SELECT campaign_id, campaign_name, campaign_type AS channel, daily_budget AS budget_now,
         LOWER(campaign_name) LIKE '%brand defense%' AS is_defense,
         REGEXP_CONTAINS(LOWER(campaign_name), r'christmas|xmas|valentine|easter|halloween|thanksgiving|black friday|bfcm|cyber monday|back to school|mother.?s day|father.?s day|santa|advent|holiday') AS is_seasonal,
         CAST(campaign_id AS STRING) IN (
           SELECT DISTINCT CAST(campaign_id AS STRING) FROM `onyga-482313.OI.DIM_KEYWORD`
           WHERE is_current AND UPPER(state) = 'ENABLED'
             AND LOWER(keyword_text) IN ('close-match','loose-match','substitutes','complements')) AS is_auto_campaign
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT`
  WHERE campaign_state = 'ENABLED'
    AND serving_status IN ('CAMPAIGN_STATUS_ENABLED', 'CAMPAIGN_OUT_OF_BUDGET')
),
anchor AS (
  SELECT c.*, IF(c.channel = 'SB', (SELECT d FROM wm_sb), (SELECT d FROM wm_sp)) AS anchor_d
  FROM camp c
),
-- 14-day spine per campaign: day anchor-13 .. anchor. The hysteresis needs days_capped_7d at
-- each of the last 7 anchor days (oldest capped flag needed: anchor-12); util_14d needs
-- spend/budget back to anchor-13. 14 days covers both exactly.
spine AS (
  SELECT a.campaign_id, a.campaign_name, a.channel, a.is_defense, a.is_seasonal,
         a.is_auto_campaign, a.budget_now, a.anchor_d, day
  FROM anchor a, UNNEST(GENERATE_DATE_ARRAY(DATE_SUB(a.anchor_d, INTERVAL 13 DAY), a.anchor_d)) AS day
),
-- signal 1: the dark clock fired that LA day (unified SP∪SB event log — never the raw per-channel
-- fivetran tables, and never DIM_CAMPAIGN for events; see CAMPAIGN_LAUNCH_RAMP.md §Status source)
ev_day AS (
  SELECT s.campaign_id AS cid, DATE(s.date, 'America/Los_Angeles') AS day,
         LOGICAL_OR(s.serving_status = 'CAMPAIGN_OUT_OF_BUDGET') AS dark_fired
  FROM `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` s
  WHERE DATE(s.date, 'America/Los_Angeles')
        >= DATE_SUB(LEAST((SELECT d FROM wm_sp), (SELECT d FROM wm_sb)), INTERVAL 13 DAY)
  GROUP BY 1, 2
),
-- signal 2 inputs: per-day spend by channel
sp_spend AS (
  SELECT CAST(campaign_id AS STRING) AS cid, date AS day, ROUND(SUM(Ads_cost), 2) AS spend
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date >= DATE_SUB((SELECT d FROM wm_sp), INTERVAL 13 DAY)
  GROUP BY 1, 2
),
sb_spend AS (
  SELECT CAST(campaign_id AS STRING) AS cid, report_date AS day, ROUND(SUM(cost), 2) AS spend
  FROM `fivetran-hl.amazon_ads.sb_campaign_report`
  WHERE report_date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 13 DAY)
  GROUP BY 1, 2
),
-- the budget in force ON that day — DIM_CAMPAIGN SCD2, latest effective_from <= day
bud AS (
  SELECT s.campaign_id, s.day, dc.daily_budget AS budget_day
  FROM (SELECT DISTINCT campaign_id, day FROM spine) s
  JOIN `onyga-482313.OI.DIM_CAMPAIGN` dc
    ON dc.campaign_id = s.campaign_id AND DATE(dc.effective_from) <= s.day
  QUALIFY ROW_NUMBER() OVER (PARTITION BY s.campaign_id, s.day ORDER BY dc.effective_from DESC) = 1
),
d AS (
  SELECT sp.*,
    COALESCE(IF(sp.channel = 'SB', sb.spend, s1.spend), 0) AS spend,
    COALESCE(b.budget_day, sp.budget_now) AS budget_day,
    COALESCE(e.dark_fired, FALSE) AS dark_fired,
    -- the per-day v27.15 dual signal
    (COALESCE(e.dark_fired, FALSE)
      OR COALESCE(IF(sp.channel = 'SB', sb.spend, s1.spend), 0) >= COALESCE(b.budget_day, sp.budget_now)) AS capped
  FROM spine sp
  LEFT JOIN ev_day e ON e.cid = sp.campaign_id AND e.day = sp.day
  LEFT JOIN sp_spend s1 ON sp.channel <> 'SB' AND s1.cid = CAST(sp.campaign_id AS STRING) AND s1.day = sp.day
  LEFT JOIN sb_spend sb ON sp.channel = 'SB' AND sb.cid = CAST(sp.campaign_id AS STRING) AND sb.day = sp.day
  LEFT JOIN bud b ON b.campaign_id = sp.campaign_id AND b.day = sp.day
),
roll AS (
  SELECT *,
    CAST(SUM(IF(capped, 1, 0)) OVER w7 AS INT64) AS days_capped_7d,
    CAST(SUM(IF(capped, 1, 0)) OVER w14 AS INT64) AS days_capped_14d,
    CAST(SUM(IF(dark_fired, 1, 0)) OVER w7 AS INT64) AS dark_days_7d,
    ROUND(SUM(spend) OVER w7, 2) AS spend_7d,
    ROUND(SUM(budget_day) OVER w7, 2) AS budget_7d,
    ROUND(SUM(spend) OVER w14, 2) AS spend_14d,
    ROUND(SUM(budget_day) OVER w14, 2) AS budget_14d
  FROM d
  WINDOW w7 AS (PARTITION BY campaign_id ORDER BY UNIX_DATE(day) ROWS BETWEEN 6 PRECEDING AND CURRENT ROW),
         w14 AS (PARTITION BY campaign_id ORDER BY UNIX_DATE(day) ROWS BETWEEN 13 PRECEDING AND CURRENT ROW)
),
-- the stateless hysteresis: did the ENTRY test (days_capped_7d >= 2) fire on any of the last 7
-- anchor days (incl. today)? Every day evaluated here has a full 7-day capped window inside the
-- spine (anchor-6 .. anchor need days back to anchor-12; the spine starts at anchor-13).
own AS (
  SELECT *,
    MAX(days_capped_7d) OVER (PARTITION BY campaign_id ORDER BY UNIX_DATE(day)
                              ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS max_dc7_last7
  FROM roll
)
SELECT
  campaign_id, campaign_name, channel, is_defense, is_seasonal, is_auto_campaign,
  anchor_d AS anchor_date,
  capped AS capped_today, dark_fired AS dark_fired_today,
  days_capped_7d, days_capped_14d, dark_days_7d,
  spend_7d, budget_7d, spend_14d, budget_14d,
  ROUND(SAFE_DIVIDE(spend_7d, NULLIF(budget_7d, 0)), 2) AS util_7d,
  ROUND(SAFE_DIVIDE(spend_14d, NULLIF(budget_14d, 0)), 2) AS util_14d,
  (max_dc7_last7 >= 2) AS entered_7d,
  -- ENTER >= 2, EXIT only at 0: owned = entry fired within the last 7 anchors AND still >= 1 now
  (days_capped_7d >= 1 AND max_dc7_last7 >= 2) AS is_oob_owned
FROM own
WHERE day = anchor_d;
