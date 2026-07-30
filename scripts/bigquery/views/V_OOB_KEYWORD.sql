-- V_OOB_KEYWORD — keyword layer of the Out-of-budget phase (Weekly Run). Spec: architecture/OOB_BUDGET_PHASE.md §v2.
--
-- One row per (OOB campaign, SP target) — keywords, auto clauses AND product targets — with a bid
-- suggestion built from the SAME constants as the launch controller, applied to every out-of-budget
-- campaign regardless of engine (launch or working). SB campaigns are campaign-level only in this
-- phase; their targets already live on the SB launch track (V_SB_LAUNCH_TARGET).
--
-- WHY BIDS AT ALL: a bid cut does not reduce spend — the budget caps spend either way. It lowers
-- CPC so the SAME budget buys more hours of the day: dark ↓ while utilization stays ~100%, which is
-- the phase's goal. Measured 2026-07-30: 69% of dark-campaign spend sat on 6+-click keywords.
--
-- RULES (Ori 2026-07-30):
--   CONVERTING (net ROAS >= 1.0 on last day OR prior-2d) — EXEMPT from the click band:
--     campaign capping and not itself strong → HOLD (the budget raise is the lever, not the bid)
--     both windows > 1.5x → RAISE_STRONG +30% · last day > 1.2x → RAISE_WEAK +15% · cap $2.00
--   NOT CONVERTING → click band on the LAST COMPLETE DAY's clicks:
--     < 4 clicks → PROBE +5% (cap $1.50) · 4–5 → HOLD · >= 6 → SLOW −5% (floor $0.20)
--   1-day cooldown: changed < 1 day ago (FACT_PPC_CHANGE_LOG) → HOLD 'changed today'.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_OOB_KEYWORD` AS
WITH k AS (
  SELECT 1.5 AS strong_roas, 1.2 AS weak_roas,
         1.30 AS bid_raise_strong, 1.15 AS bid_raise_weak, 1.05 AS bid_probe, 0.95 AS bid_slow,
         0.20 AS bid_min, 1.50 AS bid_max, 2.00 AS bid_hard_cap,
         4 AS click_goal_day, 6 AS click_cap_day
),
wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
       FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
-- the phase's campaign population + campaign-level ROAS signals (for the hold-while-capping test)
oob AS (
  SELECT campaign_id, campaign_name, pct_dark, roas_1d AS c_roas1, roas_prev2 AS c_roas_prev2
  FROM `onyga-482313.OI.V_OOB_BUDGET_PHASE`
  WHERE channel = 'SP' AND pct_dark > 10
),
-- target-day perf, corrected gross profit (COGS by the product actually purchased — price tier)
tday AS (
  SELECT CAST(a.campaign_id AS STRING) cid, a.targeting, a.date,
    SUM(a.Ads_clicks) clk, SUM(a.Ads_cost) sp, SUM(a.Ads_units) units,
    SUM(a.Ads_sales - COALESCE(pct.tier_cost, a.TOTAL_COST_PER_UNIT)*a.Ads_units) gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN oob o ON o.campaign_id = CAST(a.campaign_id AS STRING)
  LEFT JOIN `onyga-482313.OI.T_PRICE_COST_TIER` pct
    ON a.Ads_units > 0 AND pct.unit_price = ROUND(SAFE_DIVIDE(a.Ads_sales, a.Ads_units), 2)
  WHERE a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 2 DAY) AND (SELECT d FROM wm)
  GROUP BY 1, 2, 3
),
tsig AS (
  SELECT cid, targeting,
    SUM(IF(date = (SELECT d FROM wm), clk, 0)) AS clk1,
    SUM(IF(date = (SELECT d FROM wm), sp, 0)) AS sp1,
    SUM(IF(date = (SELECT d FROM wm), units, 0)) AS units1,
    ROUND(SAFE_DIVIDE(SUM(IF(date = (SELECT d FROM wm), gp, 0)),
                      NULLIF(SUM(IF(date = (SELECT d FROM wm), sp, 0)), 0)), 2) AS roas1,
    SUM(IF(date < (SELECT d FROM wm), clk, 0)) AS clk2,
    SUM(IF(date < (SELECT d FROM wm), sp, 0)) AS sp2,
    SUM(IF(date < (SELECT d FROM wm), units, 0)) AS units2,
    ROUND(SAFE_DIVIDE(SUM(IF(date < (SELECT d FROM wm), gp, 0)),
                      NULLIF(SUM(IF(date < (SELECT d FROM wm), sp, 0)), 0)), 2) AS roas_prev2
  FROM tday GROUP BY 1, 2
),
-- current bid + ids: latest V_TARGET_DAILY row per (campaign, target); ad-group default as fallback
td AS (
  SELECT campaign_id, target_text, keyword_id, ad_group_id, match_type, keyword_bid
  FROM (
    SELECT CAST(campaign_id AS STRING) campaign_id, target_text, CAST(keyword_id AS STRING) keyword_id,
           CAST(ad_group_id AS STRING) ad_group_id, match_type, keyword_bid,
           ROW_NUMBER() OVER (PARTITION BY CAST(campaign_id AS STRING), target_text
                              ORDER BY date DESC, keyword_bid DESC NULLS LAST) rn
    FROM `onyga-482313.OI.V_TARGET_DAILY`
    WHERE date >= DATE_SUB((SELECT d FROM wm), INTERVAL 6 DAY)
  ) WHERE rn = 1
),
agb AS (SELECT ad_group_id, ANY_VALUE(default_bid) default_bid
        FROM `onyga-482313.OI.DIM_AD_GROUP` WHERE is_current GROUP BY 1),
-- 1-day cooldown: did we already upload a change for this keyword?
lc AS (
  SELECT keyword_id, DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), MAX(DATE(applied_at)), DAY) AS days_since
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE keyword_id IS NOT NULL GROUP BY 1
),
base AS (
  SELECT o.campaign_id, o.campaign_name, o.pct_dark, o.c_roas1, o.c_roas_prev2,
    t.targeting AS target_text, td.keyword_id, td.ad_group_id, td.match_type,
    LOWER(t.targeting) IN ('close-match','loose-match','substitutes','complements') AS is_auto,
    LOWER(t.targeting) LIKE 'asin%' AS is_pt,
    COALESCE(td.keyword_bid, agb.default_bid) AS current_bid,
    t.clk1, t.sp1, t.units1, t.roas1, t.clk2, t.sp2, t.units2, t.roas_prev2,
    (COALESCE(t.roas1, 0) >= 1.0 OR COALESCE(t.roas_prev2, 0) >= 1.0) AS converting,
    lc.days_since AS days_since_change
  FROM tsig t
  JOIN oob o ON o.campaign_id = t.cid
  LEFT JOIN td ON td.campaign_id = t.cid AND td.target_text = t.targeting
  LEFT JOIN agb ON agb.ad_group_id = td.ad_group_id
  LEFT JOIN lc ON lc.keyword_id = td.keyword_id
)
SELECT
  b.campaign_id, b.campaign_name, b.pct_dark,
  b.keyword_id, b.ad_group_id, b.target_text, b.match_type, b.is_auto, b.is_pt,
  ROUND(b.current_bid, 2) AS current_bid,
  b.clk1 AS clicks_1d, ROUND(b.sp1, 2) AS spend_1d, ROUND(SAFE_DIVIDE(b.sp1, NULLIF(b.clk1,0)), 2) AS cpc_1d,
  b.units1 AS units_1d, b.roas1 AS roas_1d,
  b.clk2 AS clicks_prev2, ROUND(b.sp2, 2) AS spend_prev2, ROUND(SAFE_DIVIDE(b.sp2, NULLIF(b.clk2,0)), 2) AS cpc_prev2,
  b.units2 AS units_prev2, b.roas_prev2,
  b.converting, b.days_since_change,
  CASE
    WHEN b.current_bid IS NULL THEN NULL
    WHEN COALESCE(b.days_since_change, 99) < 1 THEN NULL
    WHEN b.converting THEN CASE
      WHEN b.c_roas_prev2 <= x.strong_roas AND COALESCE(b.c_roas1, 0) <= x.weak_roas THEN NULL   -- hold while capping
      WHEN COALESCE(b.roas_prev2,0) > x.strong_roas AND COALESCE(b.roas1,0) > x.strong_roas
        THEN ROUND(LEAST(b.current_bid * x.bid_raise_strong, x.bid_hard_cap), 2)
      WHEN COALESCE(b.roas1,0) > x.weak_roas
        THEN ROUND(LEAST(b.current_bid * x.bid_raise_weak, x.bid_hard_cap), 2)
      ELSE NULL END
    WHEN b.clk1 < x.click_goal_day THEN ROUND(LEAST(b.current_bid * x.bid_probe, x.bid_max), 2)
    WHEN b.clk1 >= x.click_cap_day THEN ROUND(GREATEST(b.current_bid * x.bid_slow, x.bid_min), 2)
    ELSE NULL
  END AS suggested_bid,
  CASE
    WHEN b.current_bid IS NULL THEN 'NO_BID'
    WHEN COALESCE(b.days_since_change, 99) < 1 THEN 'HOLD'
    WHEN b.converting THEN CASE
      WHEN b.c_roas_prev2 <= x.strong_roas AND COALESCE(b.c_roas1, 0) <= x.weak_roas THEN 'HOLD'
      WHEN COALESCE(b.roas_prev2,0) > x.strong_roas AND COALESCE(b.roas1,0) > x.strong_roas THEN 'RAISE_STRONG'
      WHEN COALESCE(b.roas1,0) > x.weak_roas THEN 'RAISE_WEAK'
      ELSE 'HOLD' END
    WHEN b.clk1 < x.click_goal_day THEN 'PROBE'
    WHEN b.clk1 >= x.click_cap_day THEN 'SLOW'
    ELSE 'HOLD'
  END AS bid_action,
  CASE
    WHEN b.current_bid IS NULL THEN 'no bid on record'
    WHEN COALESCE(b.days_since_change, 99) < 1 THEN 'changed today — one suggestion per day'
    WHEN b.converting THEN CASE
      WHEN b.c_roas_prev2 <= x.strong_roas AND COALESCE(b.c_roas1, 0) <= x.weak_roas
        THEN 'converting — hold while the campaign caps; the budget raise is the lever'
      WHEN COALESCE(b.roas_prev2,0) > x.strong_roas AND COALESCE(b.roas1,0) > x.strong_roas
        THEN 'both windows > 1.5x — fund the winner (+30%, cap $2)'
      WHEN COALESCE(b.roas1,0) > x.weak_roas THEN 'last day > 1.2x — nudge up (+15%, cap $2)'
      ELSE 'converting, mid — hold' END
    WHEN b.clk1 < x.click_goal_day THEN 'under 4 clicks yesterday — probe +5% toward the 4-click goal'
    WHEN b.clk1 >= x.click_cap_day THEN '6+ clicks yesterday, not converting — slow −5%: cheaper clicks stretch the budget across the day'
    ELSE '4–5 clicks — hold and wait for a sale'
  END AS bid_reason
FROM base b CROSS JOIN k x
WHERE b.clk1 > 0 OR b.clk2 > 0;
