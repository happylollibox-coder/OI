-- V_OOB_BUDGET_PHASE — the "Out of budget" technical phase on the Weekly Run page.
-- Spec: architecture/OOB_BUDGET_PHASE.md.
--
-- GOAL (Ori 2026-07-30): campaigns should NOT be out of budget — but should use almost all of their
-- budget. One row per ENABLED campaign (SP AND SB, launch AND working) that Amazon reported
-- CAMPAIGN_OUT_OF_BUDGET at any point on its channel's anchor day, with ONE straightforward budget
-- suggestion. Rules = the launch controller's dark-gated ladder (identical constants to
-- V_LAUNCH_PHASE1.k), applied uniformly to every campaign regardless of engine:
--   dark <= 10%                          → WATCH  (touched the cap but barely — no move)
--   prev-2d net ROAS >= 1.5x             → RAISE_STRONG  LEAST(budget / %active, budget x 3)
--   last-day net ROAS >= 1.2x            → RAISE_WEAK    LEAST(budget / %active, budget x 2)
--   prev-2d net ROAS <  0.9x             → CUT           GREATEST(budget x 0.9, $10 floor)
--     (Ori 2026-07-30: "lower budget slowly until minimum" — 10% steps repeated daily while dark
--      and losing, NOT the launch controller's one-shot -40%; a recovery any day stops the slide)
--   otherwise (mid)                      → HOLD          (budget stays; bids do the work)
--
-- Status events come from the UNIFIED V_SRC interface (SP∪SB) — never the raw per-channel fivetran
-- tables (an SP-only read missed all 9 dark SB campaigns on 2026-07-29) and never DIM_CAMPAIGN for
-- events (SCD2 samples 3x/day; flips that revert between loads vanish). See
-- architecture/CAMPAIGN_LAUNCH_RAMP.md §"Status source".
--
-- GRAIN: one row per campaign with pct_dark > 0 on its anchor day.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_OOB_BUDGET_PHASE` AS
WITH cfg AS (
  SELECT MAX(IF(config_key='campaign_launch_floor_daily', config_value, NULL)) AS floor_daily
  FROM `onyga-482313.OI.DE_BUDGET_CONFIG`
),
-- constants — IDENTICAL to V_LAUNCH_PHASE1.k so the phase's suggestion matches the launch engine's
k AS (
  SELECT 0.10 AS dark_target, 1.5 AS strong_roas, 1.2 AS weak_roas, 0.9 AS cut_roas,
         -- slow slide (Ori 2026-07-30): -10%/day toward the $10 floor, not the launch -40% one-shot
         0.90 AS bud_cut, 2.0 AS bud_cap_weak, 3.0 AS bud_cap_strong
),
-- each channel anchors on its own last complete day (mirrors the two launch engines)
wm_sp AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
          FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
wm_sb AS (SELECT LEAST(MAX(report_date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
          FROM `fivetran-hl.amazon_ads.sb_campaign_report`),
-- latest identity + budget per campaign
-- 2026-07-30: consolidated source (V_DIM_CAMPAIGN_CURRENT / DIM_*) per prefer-DIM/FACT rule; was V_SRC_AmazonAds_campaign_history
camp AS (
  SELECT campaign_id,
    campaign_name,
    campaign_type AS channel,
    campaign_state AS state,
    serving_status,
    daily_budget AS budget
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT`
),
anchor AS (
  SELECT c.campaign_id, IF(c.channel='SB', (SELECT d FROM wm_sb), (SELECT d FROM wm_sp)) AS d
  FROM camp c
),
-- %dark on the anchor day — same event-replay method as the launch controllers
h AS (
  SELECT s.campaign_id AS cid, DATETIME(s.date,'America/Los_Angeles') AS ts, s.serving_status
  FROM `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` s
  JOIN anchor a ON a.campaign_id = s.campaign_id
  WHERE DATE(s.date,'America/Los_Angeles') = a.d
),
ev AS (
  SELECT cid, ts, serving_status FROM h
  UNION ALL
  SELECT hc.cid, DATETIME(a.d, TIME '00:00:00'), 'CAMPAIGN_STATUS_ENABLED'
  FROM (SELECT DISTINCT cid FROM h) hc JOIN anchor a ON a.campaign_id = hc.cid
),
sq AS (SELECT cid, ts, serving_status, LEAD(ts) OVER (PARTITION BY cid ORDER BY ts) AS nxt FROM ev),
dark AS (
  SELECT s.cid,
    SUM(IF(s.serving_status='CAMPAIGN_OUT_OF_BUDGET',
        DATETIME_DIFF(COALESCE(s.nxt, DATETIME(DATE_ADD(a.d, INTERVAL 1 DAY))), s.ts, MINUTE), 0)) / 1440.0 AS pd
  FROM sq s JOIN anchor a ON a.campaign_id = s.cid
  GROUP BY 1
),
-- SP performance: corrected gross profit (COGS by product actually purchased, price-tier) — same as V_LAUNCH_PHASE1.cday
sp_day AS (
  SELECT CAST(a.campaign_id AS STRING) AS cid, a.date,
    SAFE_DIVIDE(SUM(a.Ads_sales - COALESCE(pct.tier_cost, a.TOTAL_COST_PER_UNIT)*a.Ads_units), SUM(a.Ads_cost)) AS roas,
    SUM(a.Ads_cost) AS sp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  LEFT JOIN `onyga-482313.OI.T_PRICE_COST_TIER` pct
    ON a.Ads_units > 0 AND pct.unit_price = ROUND(SAFE_DIVIDE(a.Ads_sales, a.Ads_units), 2)
  WHERE a.date BETWEEN DATE_SUB((SELECT d FROM wm_sp), INTERVAL 2 DAY) AND (SELECT d FROM wm_sp)
  GROUP BY 1, 2
),
sp_sig AS (
  SELECT cid,
    ROUND(MAX(IF(date=(SELECT d FROM wm_sp), roas, NULL)), 2) AS roas_1d,
    -- prev-2d: spend-pooled ratio over the 2 prior days (simple + stable at campaign grain)
    ROUND(SAFE_DIVIDE(SUM(IF(date<(SELECT d FROM wm_sp), roas*sp, 0)),
                      NULLIF(SUM(IF(date<(SELECT d FROM wm_sp), sp, 0)), 0)), 2) AS roas_prev2,
    ROUND(SUM(IF(date=(SELECT d FROM wm_sp), sp, 0)), 2) AS spend_1d
  FROM sp_day GROUP BY 1
),
-- SB performance: est net ROAS via the campaign's mapped-ASIN cost ratio — same as V_SB_LAUNCH_CAMPAIGN
prod AS (
  SELECT CAST(f.campaign_id AS STRING) AS cid,
    SAFE_DIVIDE(ANY_VALUE(c.cost), NULLIF(ANY_VALUE(p.listing_price_amount), 0)) AS cost_ratio
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = f.ASIN_BY_CAMPAIGN_NAME
  LEFT JOIN (SELECT asin, TOTAL_COST_PER_UNIT cost FROM (
      SELECT asin, TOTAL_COST_PER_UNIT, ROW_NUMBER() OVER (PARTITION BY marketplace_id, asin ORDER BY start_date DESC) rn
      FROM `onyga-482313.OI.DIM_COSTS_HISTORY` WHERE marketplace_id='ATVPDKIKX0DER' AND end_date IS NULL) WHERE rn=1) c
    ON c.asin = f.ASIN_BY_CAMPAIGN_NAME
  GROUP BY 1
),
sb_day AS (
  SELECT CAST(r.campaign_id AS STRING) AS cid, r.report_date AS date,
    SAFE_DIVIDE(SUM(r.attributed_sales_14_d * (1 - COALESCE(pr.cost_ratio, 0))), NULLIF(SUM(r.cost), 0)) AS roas,
    SUM(r.cost) AS sp
  FROM `fivetran-hl.amazon_ads.sb_campaign_report` r
  LEFT JOIN prod pr ON pr.cid = CAST(r.campaign_id AS STRING)
  WHERE r.report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 2 DAY) AND (SELECT d FROM wm_sb)
  GROUP BY 1, 2
),
sb_sig AS (
  SELECT cid,
    ROUND(MAX(IF(date=(SELECT d FROM wm_sb), roas, NULL)), 2) AS roas_1d,
    ROUND(SAFE_DIVIDE(SUM(IF(date<(SELECT d FROM wm_sb), roas*sp, 0)),
                      NULLIF(SUM(IF(date<(SELECT d FROM wm_sb), sp, 0)), 0)), 2) AS roas_prev2,
    ROUND(SUM(IF(date=(SELECT d FROM wm_sb), sp, 0)), 2) AS spend_1d
  FROM sb_day GROUP BY 1
),
-- days since we last uploaded a budget change (context: a fresh change means "give it a day")
bc AS (
  SELECT campaign_id, DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), MAX(DATE(applied_at)), DAY) AS days_since_budget_change
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE action = 'BUDGET_CHANGE'
  GROUP BY 1
)
SELECT
  c.campaign_id, c.campaign_name, c.channel,
  IF(lp.campaign_id IS NOT NULL, 'LAUNCH', 'WORKING') AS engine,
  a.d AS anchor_date,
  ROUND(c.budget, 2) AS current_budget,
  COALESCE(sps.spend_1d, sbs.spend_1d) AS spend_1d,
  ROUND(SAFE_DIVIDE(COALESCE(sps.spend_1d, sbs.spend_1d), c.budget), 2) AS utilization,
  ROUND(d.pd * 100) AS pct_dark,
  COALESCE(sps.roas_1d, sbs.roas_1d) AS roas_1d,
  COALESCE(sps.roas_prev2, sbs.roas_prev2) AS roas_prev2,
  bcx.days_since_budget_change,
  CASE
    WHEN d.pd <= x.dark_target THEN 'WATCH'
    WHEN COALESCE(sps.roas_prev2, sbs.roas_prev2, 0) >= x.strong_roas THEN 'RAISE_STRONG'
    WHEN COALESCE(sps.roas_1d,   sbs.roas_1d,   0) >= x.weak_roas   THEN 'RAISE_WEAK'
    WHEN COALESCE(sps.roas_prev2, sbs.roas_prev2, 0) <  x.cut_roas   THEN 'CUT'
    ELSE 'HOLD'
  END AS action,
  CASE
    WHEN d.pd <= x.dark_target THEN NULL
    WHEN COALESCE(sps.roas_prev2, sbs.roas_prev2, 0) >= x.strong_roas
      THEN ROUND(LEAST(SAFE_DIVIDE(c.budget, 1 - d.pd), c.budget * x.bud_cap_strong), 2)
    WHEN COALESCE(sps.roas_1d, sbs.roas_1d, 0) >= x.weak_roas
      THEN ROUND(LEAST(SAFE_DIVIDE(c.budget, 1 - d.pd), c.budget * x.bud_cap_weak), 2)
    WHEN COALESCE(sps.roas_prev2, sbs.roas_prev2, 0) < x.cut_roas
      THEN ROUND(GREATEST(c.budget * x.bud_cut, CAST(cf.floor_daily AS FLOAT64)), 2)
    ELSE NULL
  END AS suggested_budget,
  CASE
    WHEN d.pd <= x.dark_target
      THEN CONCAT('Dark ', CAST(ROUND(d.pd*100) AS STRING), '% — barely capped, watch')
    WHEN COALESCE(sps.roas_prev2, sbs.roas_prev2, 0) >= x.strong_roas
      THEN CONCAT('Dark ', CAST(ROUND(d.pd*100) AS STRING), '% · prev-2d ',
                  CAST(COALESCE(sps.roas_prev2, sbs.roas_prev2) AS STRING), 'x → fund full-day demand (cap 3x)')
    WHEN COALESCE(sps.roas_1d, sbs.roas_1d, 0) >= x.weak_roas
      THEN CONCAT('Dark ', CAST(ROUND(d.pd*100) AS STRING), '% · last day ',
                  CAST(COALESCE(sps.roas_1d, sbs.roas_1d) AS STRING), 'x → raise (cap 2x)')
    WHEN COALESCE(sps.roas_prev2, sbs.roas_prev2, 0) < x.cut_roas
      THEN CONCAT('Dark ', CAST(ROUND(d.pd*100) AS STRING), '% · prev-2d ',
                  CAST(COALESCE(sps.roas_prev2, sbs.roas_prev2, 0) AS STRING), 'x losing → step down 10% (floor $10)')
    ELSE CONCAT('Dark ', CAST(ROUND(d.pd*100) AS STRING), '% · mid ROAS → hold budget, bids do the work')
  END AS reason
FROM camp c
CROSS JOIN k x
CROSS JOIN cfg cf
JOIN anchor a ON a.campaign_id = c.campaign_id
JOIN dark d ON d.cid = c.campaign_id AND d.pd > 0
LEFT JOIN sp_sig sps ON c.channel = 'SP' AND sps.cid = c.campaign_id
LEFT JOIN sb_sig sbs ON c.channel = 'SB' AND sbs.cid = c.campaign_id
LEFT JOIN (SELECT DISTINCT campaign_id FROM `onyga-482313.OI.V_LAUNCH_POPULATION`) lp
  ON lp.campaign_id = c.campaign_id
LEFT JOIN bc bcx ON bcx.campaign_id = c.campaign_id
WHERE c.state = 'ENABLED'
  AND c.serving_status IN ('CAMPAIGN_STATUS_ENABLED', 'CAMPAIGN_OUT_OF_BUDGET');
