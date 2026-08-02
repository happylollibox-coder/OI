-- V_OOB_BUDGET_PHASE — the "Out of budget" technical phase on the Weekly Run page.
-- Spec: architecture/OOB_BUDGET_PHASE.md.
--
-- GOAL (Ori 2026-07-30): campaigns should NOT be out of budget — but should use almost all of their
-- budget. One row per ENABLED campaign (SP AND SB, launch AND working) that Amazon reported
-- CAMPAIGN_OUT_OF_BUDGET at any point on its channel's anchor day, with ONE budget suggestion.
--
-- v3 TIER SPLIT (Ori 2026-07-30): evidence windows scale with the budget tier —
--   budget <= low-budget cap ($20 off / $30 peak): judged daily on last-day + prev-2d
--   budget >  cap (working): off-season judged on 7d + 28d · peak judged on 3d + 7d,
--     re-suggested only on the working cadence (last budget change >= 7d off / >= 3d peak)
-- STRONG needs BOTH windows; CUT needs BOTH windows bad (symmetric evidence, no one-day verdicts).
--
-- Status events come from the UNIFIED V_SRC interface (SP∪SB) — never the raw per-channel fivetran
-- tables and never DIM_CAMPAIGN for events (SCD2 samples 3x/day; flips that revert between loads
-- vanish). See architecture/CAMPAIGN_LAUNCH_RAMP.md §"Status source".
--
-- GRAIN: one row per campaign with pct_dark > 0 on its anchor day.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_OOB_BUDGET_PHASE` AS
WITH cfg AS (
  SELECT MAX(IF(config_key='campaign_launch_floor_daily', config_value, NULL)) AS floor_daily
  FROM `onyga-482313.OI.DE_BUDGET_CONFIG`
),
k AS (
  SELECT 0.10 AS dark_target, 1.5 AS strong_roas, 1.2 AS weak_roas, 0.9 AS cut_roas,
         -- slow slide (Ori 2026-07-30): -10%/day toward the $10 floor
         0.90 AS bud_cut, 2.0 AS bud_cap_weak, 3.0 AS bud_cap_strong
),
season AS (
  SELECT COUNTIF(CURRENT_DATE('America/New_York') BETWEEN boost_start AND cooldown_end) > 0 AS in_peak
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS` WHERE category IN ('gift_season', 'prime_event')
),
cap AS (SELECT in_peak, IF(in_peak, 30.0, 20.0) AS low_budget_cap FROM season),
wm_sp AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
          FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
wm_sb AS (SELECT LEAST(MAX(report_date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
          FROM `fivetran-hl.amazon_ads.sb_campaign_report`),
-- latest identity + budget per campaign (consolidated source per prefer-DIM/FACT rule)
camp AS (
  SELECT campaign_id, campaign_name, campaign_type AS channel, campaign_state AS state,
         serving_status, daily_budget AS budget,
         LOWER(campaign_name) LIKE '%brand defense%' AS is_defense,
         -- v9 (Ori 2026-08-02): seasonal campaigns get their own Weekly Run sections
         REGEXP_CONTAINS(LOWER(campaign_name), r'christmas|xmas|valentine|easter|halloween|thanksgiving|black friday|bfcm|cyber monday|back to school|mother.?s day|father.?s day|santa|advent|holiday') AS is_seasonal,
         -- v24 (Ori 2026-08-02): auto campaigns have their own Weekly Run section (data-truth:
         -- an enabled auto clause exists in the campaign's current config)
         CAST(campaign_id AS STRING) IN (SELECT DISTINCT CAST(campaign_id AS STRING) FROM `onyga-482313.OI.DIM_KEYWORD`
                         WHERE is_current AND UPPER(state) = 'ENABLED'
                           AND LOWER(keyword_text) IN ('close-match','loose-match','substitutes','complements')) AS is_auto_campaign
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT`
),
anchor AS (
  SELECT c.campaign_id, IF(c.channel='SB', (SELECT d FROM wm_sb), (SELECT d FROM wm_sp)) AS d
  FROM camp c
),
-- %dark on the anchor day — event replay over the unified SP∪SB log
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
-- SP performance over 28d: corrected gross profit (COGS by product actually purchased, price-tier)
sp_day AS (
  SELECT CAST(a.campaign_id AS STRING) AS cid, a.date,
    SUM(a.Ads_sales - COALESCE(pct.tier_cost, a.TOTAL_COST_PER_UNIT)*a.Ads_units) AS gp,
    SUM(a.Ads_cost) AS sp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  LEFT JOIN `onyga-482313.OI.T_PRICE_COST_TIER` pct
    ON a.Ads_units > 0 AND pct.unit_price = ROUND(SAFE_DIVIDE(a.Ads_sales, a.Ads_units), 2)
  WHERE a.date BETWEEN DATE_SUB((SELECT d FROM wm_sp), INTERVAL 27 DAY) AND (SELECT d FROM wm_sp)
  GROUP BY 1, 2
),
sp_sig AS (
  SELECT cid,
    ROUND(SAFE_DIVIDE(SUM(IF(date = (SELECT d FROM wm_sp), gp, 0)),
                      NULLIF(SUM(IF(date = (SELECT d FROM wm_sp), sp, 0)), 0)), 2) AS r1,
    ROUND(SAFE_DIVIDE(SUM(IF(date < (SELECT d FROM wm_sp) AND date >= DATE_SUB((SELECT d FROM wm_sp), INTERVAL 2 DAY), gp, 0)),
                      NULLIF(SUM(IF(date < (SELECT d FROM wm_sp) AND date >= DATE_SUB((SELECT d FROM wm_sp), INTERVAL 2 DAY), sp, 0)), 0)), 2) AS rprev2,
    ROUND(SAFE_DIVIDE(SUM(IF(date >= DATE_SUB((SELECT d FROM wm_sp), INTERVAL 2 DAY), gp, 0)),
                      NULLIF(SUM(IF(date >= DATE_SUB((SELECT d FROM wm_sp), INTERVAL 2 DAY), sp, 0)), 0)), 2) AS r3,
    ROUND(SAFE_DIVIDE(SUM(IF(date >= DATE_SUB((SELECT d FROM wm_sp), INTERVAL 6 DAY), gp, 0)),
                      NULLIF(SUM(IF(date >= DATE_SUB((SELECT d FROM wm_sp), INTERVAL 6 DAY), sp, 0)), 0)), 2) AS r7,
    ROUND(SAFE_DIVIDE(SUM(gp), NULLIF(SUM(sp), 0)), 2) AS r28,
    ROUND(SUM(IF(date = (SELECT d FROM wm_sp), sp, 0)), 2) AS spend_1d
  FROM sp_day GROUP BY 1
),
-- SB performance: est net ROAS via the campaign's mapped-ASIN cost ratio
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
    SUM(r.attributed_sales_14_d * (1 - COALESCE(pr.cost_ratio, 0))) AS gp,
    SUM(r.cost) AS sp
  FROM `fivetran-hl.amazon_ads.sb_campaign_report` r
  LEFT JOIN prod pr ON pr.cid = CAST(r.campaign_id AS STRING)
  WHERE r.report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 27 DAY) AND (SELECT d FROM wm_sb)
  GROUP BY 1, 2
),
sb_sig AS (
  SELECT cid,
    ROUND(SAFE_DIVIDE(SUM(IF(date = (SELECT d FROM wm_sb), gp, 0)),
                      NULLIF(SUM(IF(date = (SELECT d FROM wm_sb), sp, 0)), 0)), 2) AS r1,
    ROUND(SAFE_DIVIDE(SUM(IF(date < (SELECT d FROM wm_sb) AND date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 2 DAY), gp, 0)),
                      NULLIF(SUM(IF(date < (SELECT d FROM wm_sb) AND date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 2 DAY), sp, 0)), 0)), 2) AS rprev2,
    ROUND(SAFE_DIVIDE(SUM(IF(date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 2 DAY), gp, 0)),
                      NULLIF(SUM(IF(date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 2 DAY), sp, 0)), 0)), 2) AS r3,
    ROUND(SAFE_DIVIDE(SUM(IF(date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 6 DAY), gp, 0)),
                      NULLIF(SUM(IF(date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 6 DAY), sp, 0)), 0)), 2) AS r7,
    ROUND(SAFE_DIVIDE(SUM(gp), NULLIF(SUM(sp), 0)), 2) AS r28,
    ROUND(SUM(IF(date = (SELECT d FROM wm_sb), sp, 0)), 2) AS spend_1d
  FROM sb_day GROUP BY 1
),
bc AS (
  SELECT campaign_id, DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), MAX(DATE(applied_at)), DAY) AS days_since_budget_change
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE action = 'BUDGET_CHANGE'
  GROUP BY 1
),
base AS (
  SELECT
    c.campaign_id, c.campaign_name, c.channel, c.is_defense, c.is_seasonal, c.is_auto_campaign,
    IF(lp.campaign_id IS NOT NULL, 'LAUNCH', 'WORKING') AS engine,
    a.d AS anchor_date,
    ROUND(c.budget, 2) AS budget,
    COALESCE(s1.spend_1d, s2.spend_1d) AS spend_1d,
    d.pd,
    COALESCE(s1.r1, s2.r1) AS r1, COALESCE(s1.rprev2, s2.rprev2) AS rprev2,
    COALESCE(s1.r3, s2.r3) AS r3, COALESCE(s1.r7, s2.r7) AS r7, COALESCE(s1.r28, s2.r28) AS r28,
    bcx.days_since_budget_change AS dsb,
    kk.low_budget_cap, kk.in_peak,
    (c.budget <= kk.low_budget_cap) AS is_low_tier,
    -- working cadence throttle: > cap re-suggests only every 7d (off) / 3d (peak)
    (c.budget > kk.low_budget_cap AND COALESCE(bcx.days_since_budget_change, 99) < IF(kk.in_peak, 3, 7)) AS throttled
  FROM camp c
  CROSS JOIN cap kk
  JOIN anchor a ON a.campaign_id = c.campaign_id
  JOIN dark d ON d.cid = c.campaign_id AND d.pd > 0
  LEFT JOIN sp_sig s1 ON c.channel = 'SP' AND s1.cid = c.campaign_id
  LEFT JOIN sb_sig s2 ON c.channel = 'SB' AND s2.cid = c.campaign_id
  LEFT JOIN (SELECT DISTINCT campaign_id FROM `onyga-482313.OI.V_LAUNCH_POPULATION`) lp
    ON lp.campaign_id = c.campaign_id
  LEFT JOIN bc bcx ON bcx.campaign_id = c.campaign_id
  WHERE c.state = 'ENABLED'
    AND c.serving_status IN ('CAMPAIGN_STATUS_ENABLED', 'CAMPAIGN_OUT_OF_BUDGET')
)
SELECT
  b.campaign_id, b.campaign_name, b.channel, b.engine, b.anchor_date, b.is_defense, b.is_seasonal, b.is_auto_campaign,
  b.budget AS current_budget, b.spend_1d,
  ROUND(SAFE_DIVIDE(b.spend_1d, b.budget), 2) AS utilization,
  ROUND(b.pd * 100) AS pct_dark,
  b.r1 AS roas_1d, b.rprev2 AS roas_prev2, b.r3 AS roas_3d, b.r7 AS roas_7d, b.r28 AS roas_28d,
  b.dsb AS days_since_budget_change,
  b.is_low_tier, b.in_peak,
  -- ═══ BUDGET LADDER v4 (Ori 2026-08-01 tuning) ═══
  -- Both tiers key raises on TODAY + PREV-2D. Low tier raises harder (x2/x1.5) than working
  -- (x1.5/x1.25). Cuts need BOTH the tier's evidence window AND today under 0.6x -> -20% with a
  -- seasonal floor ($10 off / $15 peak). Evidence window: low = prev-2d · working = 7d off / 3d peak.
  CASE
    WHEN b.pd <= x.dark_target THEN 'WATCH'
    WHEN b.is_low_tier THEN CASE
      WHEN COALESCE(b.r1,0) >= x.weak_roas AND COALESCE(b.rprev2,0) >= x.strong_roas THEN 'RAISE_STRONG'
      WHEN COALESCE(b.r1,0) >= x.weak_roas THEN 'RAISE_WEAK'
      WHEN COALESCE(b.r1,0) < 0.6 AND COALESCE(b.rprev2,0) < 0.6 THEN 'CUT'
      ELSE 'HOLD' END
    WHEN b.throttled THEN 'HOLD'
    ELSE CASE
      WHEN COALESCE(b.r1,0) >= x.weak_roas AND COALESCE(b.rprev2,0) >= x.strong_roas THEN 'RAISE_STRONG'
      WHEN COALESCE(b.r1,0) >= x.weak_roas THEN 'RAISE_WEAK'
      WHEN COALESCE(IF(b.in_peak, b.r3, b.r7),0) < 0.6 AND COALESCE(b.r1,0) < 0.6 THEN 'CUT'
      ELSE 'HOLD' END
  END AS action,
  CASE
    WHEN b.pd <= x.dark_target THEN NULL
    WHEN b.is_low_tier THEN CASE
      WHEN COALESCE(b.r1,0) >= x.weak_roas AND COALESCE(b.rprev2,0) >= x.strong_roas THEN ROUND(b.budget * 2.0, 2)
      WHEN COALESCE(b.r1,0) >= x.weak_roas THEN ROUND(b.budget * 1.5, 2)
      WHEN COALESCE(b.r1,0) < 0.6 AND COALESCE(b.rprev2,0) < 0.6
        THEN ROUND(GREATEST(b.budget * 0.8, IF(b.in_peak, 15.0, 10.0)), 2)
      ELSE NULL END
    WHEN b.throttled THEN NULL
    ELSE CASE
      WHEN COALESCE(b.r1,0) >= x.weak_roas AND COALESCE(b.rprev2,0) >= x.strong_roas THEN ROUND(b.budget * 1.5, 2)
      WHEN COALESCE(b.r1,0) >= x.weak_roas THEN ROUND(b.budget * 1.25, 2)
      WHEN COALESCE(IF(b.in_peak, b.r3, b.r7),0) < 0.6 AND COALESCE(b.r1,0) < 0.6
        THEN ROUND(GREATEST(b.budget * 0.8, IF(b.in_peak, 15.0, 10.0)), 2)
      ELSE NULL END
  END AS suggested_budget,
  CASE
    WHEN b.pd <= x.dark_target
      THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% — barely capped, watch')
    WHEN b.is_low_tier THEN CASE
      WHEN COALESCE(b.r1,0) >= x.weak_roas AND COALESCE(b.rprev2,0) >= x.strong_roas
        THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · today ', CAST(b.r1 AS STRING),
                    'x AND prev-2d ', CAST(b.rprev2 AS STRING), 'x → strong raise ×2')
      WHEN COALESCE(b.r1,0) >= x.weak_roas
        THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · today ', CAST(b.r1 AS STRING), 'x → raise ×1.5')
      WHEN COALESCE(b.r1,0) < 0.6 AND COALESCE(b.rprev2,0) < 0.6
        THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · today AND prev-2d both under 0.6x → cut 20% (floor $',
                    CAST(CAST(IF(b.in_peak,15,10) AS INT64) AS STRING), ')')
      ELSE CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · mixed windows → hold budget, bids do the work') END
    WHEN b.throttled
      THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · budget changed ', CAST(b.dsb AS STRING),
                  'd ago — working cadence (', IF(b.in_peak, '3d in peak', '7d off-season'), ') not due yet')
    ELSE CASE
      WHEN COALESCE(b.r1,0) >= x.weak_roas AND COALESCE(b.rprev2,0) >= x.strong_roas
        THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · today ', CAST(b.r1 AS STRING),
                    'x AND prev-2d ', CAST(b.rprev2 AS STRING), 'x → strong raise ×1.5')
      WHEN COALESCE(b.r1,0) >= x.weak_roas
        THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · today ', CAST(b.r1 AS STRING), 'x → raise ×1.25')
      WHEN COALESCE(IF(b.in_peak, b.r3, b.r7),0) < 0.6 AND COALESCE(b.r1,0) < 0.6
        THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · ', IF(b.in_peak,'3d','7d'), ' ',
                    CAST(COALESCE(IF(b.in_peak, b.r3, b.r7),0) AS STRING), 'x AND today under 0.6x → cut 20% (floor $',
                    CAST(CAST(IF(b.in_peak,15,10) AS INT64) AS STRING), ')')
      ELSE CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · evidence mid → hold budget, bids do the work') END
  END AS reason
FROM base b
CROSS JOIN k x
CROSS JOIN cfg cf;
