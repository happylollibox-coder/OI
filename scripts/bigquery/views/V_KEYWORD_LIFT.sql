-- V_KEYWORD_LIFT — the 80/20 portfolio + probe rotation for WORKING campaigns (budget > low-budget
-- cap), SP v1. Spec: architecture/OOB_BUDGET_PHASE.md §"Lever 2B". Ori 2026-07-30:
--   "80% of spend should go to winner keywords and 20% to losers. most losers parked; 1-2 probes
--    raise the bid to check if they are profitable; after 20 clicks each, if profitable continue,
--    else park and probe the next 1-2. the goal is the best keyword for intent at the best bid so
--    all keywords are profitable per 7 days off-season / 3 days peak."
--
-- WINDOW W = 7d off-season / 3d peak. CLASSES over W (corrected net ROAS):
--   WINNER >= 1.1 with >= 1 order · MARGINAL 0.7-1.1 with orders · LOSER < 0.7 or clicks w/ 0 orders
--   IDLE = no clicks in W (parked / dormant — the probe candidate pool, with untested keywords)
--
-- PROBE EPISODES ARE STATELESS: an episode = the last INCREASE_BID upload for the keyword
-- (FACT_PPC_CHANGE_LOG) within the last 14 days; test evidence = FACT activity AFTER that date.
-- Verdict at 20 episode clicks: net ROAS >= 1.0 → WINNER_FOUND (joins the 80% pool), else PARK.
-- While testing, the keyword is exempt from PARK here and (by design) from the coacher's pullback.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_KEYWORD_LIFT` AS
WITH season AS (
  SELECT COUNTIF(CURRENT_DATE('America/New_York') BETWEEN boost_start AND cooldown_end) > 0 AS in_peak
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS` WHERE category IN ('gift_season', 'prime_event')
),
cap AS (SELECT in_peak, IF(in_peak, 30.0, 20.0) AS low_cap, IF(in_peak, 3, 7) AS w_days FROM season),
wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
       FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
camps AS (
  SELECT c.campaign_id, c.campaign_name, c.daily_budget AS budget
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` c, cap k
  WHERE c.campaign_type = 'SP' AND c.campaign_state = 'ENABLED'
    AND c.serving_status IN ('CAMPAIGN_STATUS_ENABLED', 'CAMPAIGN_OUT_OF_BUDGET')
    AND c.daily_budget > k.low_cap
),
-- window W performance per (campaign, target) — corrected GP (price-tier COGS)
kwW AS (
  SELECT CAST(a.campaign_id AS STRING) cid, a.targeting,
    SUM(a.Ads_clicks) clk_w, SUM(a.Ads_cost) sp_w, SUM(a.Ads_orders) ord_w,
    SUM(a.Ads_sales - COALESCE(pct.tier_cost, a.TOTAL_COST_PER_UNIT)*a.Ads_units) gp_w,
    SUM(IF(a.date = (SELECT d FROM wm), a.Ads_clicks, 0)) clk1
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN camps c ON c.campaign_id = CAST(a.campaign_id AS STRING)
  CROSS JOIN cap k
  LEFT JOIN `onyga-482313.OI.T_PRICE_COST_TIER` pct
    ON a.Ads_units > 0 AND pct.unit_price = ROUND(SAFE_DIVIDE(a.Ads_sales, a.Ads_units), 2)
  WHERE a.date > DATE_SUB((SELECT d FROM wm), INTERVAL k.w_days DAY)
  GROUP BY 1, 2
),
-- full target list (idle keywords included — the candidate pool), ids + current bid
td AS (
  SELECT campaign_id, target_text, keyword_id, ad_group_id, match_type, keyword_bid
  FROM (
    SELECT CAST(campaign_id AS STRING) campaign_id, target_text, CAST(keyword_id AS STRING) keyword_id,
           CAST(ad_group_id AS STRING) ad_group_id, match_type, keyword_bid,
           ROW_NUMBER() OVER (PARTITION BY CAST(campaign_id AS STRING), target_text
                              ORDER BY date DESC, keyword_bid DESC NULLS LAST) rn
    FROM `onyga-482313.OI.V_TARGET_DAILY`
    WHERE date >= DATE_SUB((SELECT d FROM wm), INTERVAL 13 DAY)
  ) WHERE rn = 1
),
agb AS (SELECT ad_group_id, ANY_VALUE(default_bid) default_bid
        FROM `onyga-482313.OI.DIM_AD_GROUP` WHERE is_current GROUP BY 1),
-- probe episodes: last INCREASE_BID per keyword (change log), evidence AFTER the upload date
lastinc AS (
  SELECT keyword_id, MAX(DATE(applied_at)) AS inc_date,
         ARRAY_AGG(new_bid ORDER BY applied_at DESC LIMIT 1)[OFFSET(0)] AS probe_bid
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE action = 'INCREASE_BID' AND keyword_id IS NOT NULL AND keyword_id != ''
  GROUP BY 1
),
episode AS (
  SELECT CAST(a.campaign_id AS STRING) cid, a.targeting,
    SUM(a.Ads_clicks) ep_clk, SUM(a.Ads_cost) ep_sp, SUM(a.Ads_orders) ep_ord,
    SUM(a.Ads_sales - COALESCE(pct.tier_cost, a.TOTAL_COST_PER_UNIT)*a.Ads_units) ep_gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN camps c ON c.campaign_id = CAST(a.campaign_id AS STRING)
  JOIN td ON td.campaign_id = CAST(a.campaign_id AS STRING) AND td.target_text = a.targeting
  JOIN lastinc li ON li.keyword_id = td.keyword_id
  LEFT JOIN `onyga-482313.OI.T_PRICE_COST_TIER` pct
    ON a.Ads_units > 0 AND pct.unit_price = ROUND(SAFE_DIVIDE(a.Ads_sales, a.Ads_units), 2)
  WHERE a.date > li.inc_date
  GROUP BY 1, 2
),
-- target CPC (probe entry anchor): LY same-28d-last-year else band (keywords only)
ly AS (
  SELECT LOWER(TRIM(targeting)) AS kw, ROUND(SAFE_DIVIDE(SUM(Ads_cost), SUM(Ads_clicks)), 2) AS ly_cpc,
         SUM(Ads_clicks) AS ly_clk
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 391 DAY)
                 AND DATE_SUB((SELECT d FROM wm), INTERVAL 364 DAY)
  GROUP BY 1 HAVING SUM(Ads_clicks) >= 10
),
camp_parent AS (
  SELECT CAST(f.campaign_id AS STRING) cid, ANY_VALUE(p.parent_name) parent_name
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = f.ASIN_BY_CAMPAIGN_NAME AND p.parent_name IS NOT NULL
  GROUP BY 1
),
band AS (
  SELECT parent_name, UPPER(match_type) AS match_type, ROUND(AVG(cpc_target), 2) AS cpc_target
  FROM `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE`, season s
  WHERE enabled AND cpc_target IS NOT NULL AND confidence = 'CONCLUSIVE'
    AND COALESCE(campaign_type, 'ALL') = 'ALL' AND COALESCE(ad_format, 'ALL') = 'ALL'
    AND season = IF(s.in_peak, 'PEAK', 'OFF')
  GROUP BY 1, 2
),
base AS (
  SELECT c.campaign_id, c.campaign_name, c.budget,
    td.target_text, td.keyword_id, td.ad_group_id, td.match_type,
    LOWER(td.target_text) IN ('close-match','loose-match','substitutes','complements') AS is_auto,
    LOWER(td.target_text) LIKE 'asin%' AS is_pt,
    COALESCE(td.keyword_bid, agb.default_bid) AS current_bid,
    COALESCE(w.clk_w, 0) clk_w, COALESCE(w.sp_w, 0) sp_w, COALESCE(w.ord_w, 0) ord_w,
    ROUND(SAFE_DIVIDE(w.gp_w, NULLIF(w.sp_w, 0)), 2) AS roas_w, COALESCE(w.clk1, 0) clk1,
    li.inc_date, li.probe_bid,
    COALESCE(ep.ep_clk, 0) ep_clk, ROUND(SAFE_DIVIDE(ep.ep_gp, NULLIF(ep.ep_sp, 0)), 2) AS ep_roas,
    COALESCE(ep.ep_ord, 0) ep_ord,
    ROUND(COALESCE(IF(LOWER(td.target_text) IN ('close-match','loose-match','substitutes','complements')
                      OR LOWER(td.target_text) LIKE 'asin%', NULL, l.ly_cpc), bd.cpc_target), 2) AS tcpc,
    COALESCE(l.ly_clk, 0) AS ly_clk
  FROM camps c
  JOIN td ON td.campaign_id = c.campaign_id
  LEFT JOIN agb ON agb.ad_group_id = td.ad_group_id
  LEFT JOIN kwW w ON w.cid = c.campaign_id AND w.targeting = td.target_text
  LEFT JOIN lastinc li ON li.keyword_id = td.keyword_id
  LEFT JOIN episode ep ON ep.cid = c.campaign_id AND ep.targeting = td.target_text
  LEFT JOIN ly l ON l.kw = LOWER(TRIM(td.target_text))
  LEFT JOIN camp_parent cp ON cp.cid = c.campaign_id
  LEFT JOIN band bd ON bd.parent_name = cp.parent_name
    AND bd.match_type = CASE WHEN LOWER(td.target_text) LIKE 'asin%' THEN 'PRODUCT'
                             WHEN LOWER(td.target_text) IN ('close-match','loose-match','substitutes','complements') THEN 'AUTO'
                             ELSE UPPER(COALESCE(td.match_type, '')) END
),
classed AS (
  SELECT b.*,
    CASE
      WHEN b.ord_w >= 1 AND COALESCE(b.roas_w, 0) >= 1.1 THEN 'WINNER'
      WHEN b.ord_w >= 1 AND COALESCE(b.roas_w, 0) >= 0.7 THEN 'MARGINAL'
      WHEN b.clk_w > 0 THEN 'LOSER'
      ELSE 'IDLE'
    END AS class,
    -- active probe: raised within 14d and still under 20 episode clicks
    (b.inc_date IS NOT NULL
     AND b.inc_date > DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY)
     AND b.ep_clk < 20) AS probing,
    -- probe just finished its 20 clicks — verdict due
    (b.inc_date IS NOT NULL
     AND b.inc_date > DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY)
     AND b.ep_clk >= 20) AS probe_done
  FROM base b
),
agg AS (
  SELECT c.*,
    SUM(c.sp_w) OVER (PARTITION BY c.campaign_id) AS camp_sp,
    SUM(IF(c.class = 'LOSER', c.sp_w, 0)) OVER (PARTITION BY c.campaign_id) AS loser_sp,
    SUM(IF(c.probing, 1, 0)) OVER (PARTITION BY c.campaign_id) AS active_probes,
    -- winners' avg CPC — the probe entry fallback anchor
    ROUND(SAFE_DIVIDE(SUM(IF(c.class IN ('WINNER','MARGINAL'), c.sp_w, 0)) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(IF(c.class IN ('WINNER','MARGINAL'), c.clk_w, 0)) OVER (PARTITION BY c.campaign_id), 0)), 2) AS win_cpc,
    -- keep-allowance ranking: best losers first (roas desc), cumulative spend against the 20% pool
    SUM(IF(c.class = 'LOSER' AND NOT c.probing, c.sp_w, 0))
      OVER (PARTITION BY c.campaign_id ORDER BY IF(c.class = 'LOSER' AND NOT c.probing, COALESCE(c.roas_w, 0), 999) DESC, c.sp_w
            ROWS UNBOUNDED PRECEDING) AS loser_cum_sp,
    -- candidate rank for probe promotion: anchored first, then LY volume, then least-tested
    ROW_NUMBER() OVER (PARTITION BY c.campaign_id
      ORDER BY IF(c.class = 'IDLE' AND NOT c.probing AND NOT c.probe_done, 0, 1),
               IF(c.tcpc IS NOT NULL, 0, 1), c.ly_clk DESC, c.clk_w ASC) AS cand_rank
  FROM classed c
)
SELECT
  a.campaign_id, a.campaign_name, ROUND(a.budget, 0) AS budget,
  (SELECT in_peak FROM season) AS in_peak, (SELECT w_days FROM cap) AS w_days,
  ROUND(a.camp_sp, 2) AS campaign_spend_w,
  ROUND(100 * SAFE_DIVIDE(a.loser_sp, NULLIF(a.camp_sp, 0))) AS loser_share_pct,
  a.active_probes,
  a.keyword_id, a.ad_group_id, a.target_text, a.match_type, a.is_auto, a.is_pt,
  ROUND(a.current_bid, 2) AS current_bid,
  a.clk_w AS clicks_w, ROUND(a.sp_w, 2) AS spend_w, a.ord_w AS orders_w, a.roas_w,
  a.tcpc AS target_cpc, a.class,
  a.probing, a.inc_date AS probe_started, a.ep_clk AS probe_clicks, a.ep_roas AS probe_roas,
  CASE
    -- probe verdicts first
    WHEN a.probe_done AND COALESCE(a.ep_roas, 0) >= 1.0 THEN 'WINNER_FOUND'
    WHEN a.probe_done THEN 'PARK'
    -- active probes: daily movement by the click methodology
    WHEN a.probing AND a.clk1 > 6 AND a.ep_ord = 0 THEN 'PROBE_ADJUST'
    WHEN a.probing THEN 'PROBE_WAIT'
    -- the 80% pool
    WHEN a.class IN ('WINNER','MARGINAL') THEN 'KEEP'
    -- losers beyond the 20% allowance → park (worst first; the cum-sum keeps the best within it)
    WHEN a.class = 'LOSER' AND a.loser_cum_sp > 0.20 * a.camp_sp AND COALESCE(a.current_bid, 0) > 0.30 THEN 'PARK'
    WHEN a.class = 'LOSER' THEN 'KEEP_TAIL'
    -- idle pool: promote the next candidates into probes when slots are free
    WHEN a.class = 'IDLE' AND a.active_probes < 2 AND a.cand_rank <= (2 - a.active_probes)
         AND COALESCE(a.tcpc, a.win_cpc) IS NOT NULL THEN 'PROBE_START'
    ELSE 'IDLE'
  END AS action,
  CASE
    WHEN a.probe_done AND COALESCE(a.ep_roas, 0) >= 1.0 THEN NULL
    WHEN a.probe_done THEN 0.25
    WHEN a.probing AND a.clk1 > 6 AND a.ep_ord = 0 THEN ROUND(GREATEST(a.current_bid * 0.95, 0.20), 2)
    WHEN a.probing THEN NULL
    WHEN a.class IN ('WINNER','MARGINAL') THEN NULL
    WHEN a.class = 'LOSER' AND a.loser_cum_sp > 0.20 * a.camp_sp AND COALESCE(a.current_bid, 0) > 0.30 THEN 0.25
    WHEN a.class = 'LOSER' THEN NULL
    WHEN a.class = 'IDLE' AND a.active_probes < 2 AND a.cand_rank <= (2 - a.active_probes)
         AND COALESCE(a.tcpc, a.win_cpc) IS NOT NULL
      THEN ROUND(LEAST(COALESCE(1.5 * a.tcpc, a.win_cpc), 2.00), 2)
    ELSE NULL
  END AS suggested_bid,
  CASE
    WHEN a.probe_done AND COALESCE(a.ep_roas, 0) >= 1.0
      THEN CONCAT('probe verdict: ', CAST(a.ep_clk AS STRING), ' clicks at ', CAST(COALESCE(a.ep_roas,0) AS STRING),
                  'x — WINNER found; joins the 80% pool, FIT/ROAS logic takes over')
    WHEN a.probe_done
      THEN CONCAT('probe verdict: ', CAST(a.ep_clk AS STRING), ' clicks at ', CAST(COALESCE(a.ep_roas,0) AS STRING),
                  'x — not profitable, park $0.25 and promote the next candidate')
    WHEN a.probing AND a.clk1 > 6 AND a.ep_ord = 0
      THEN CONCAT('probing (', CAST(a.ep_clk AS STRING), '/20 clicks) — 6+ clicks yesterday, no sale yet: -5% daily descent')
    WHEN a.probing
      THEN CONCAT('probing (', CAST(a.ep_clk AS STRING), '/20 clicks since ', CAST(a.inc_date AS STRING), ') — let the test run')
    WHEN a.class = 'WINNER' THEN CONCAT('winner: ', CAST(COALESCE(a.roas_w,0) AS STRING), 'x over ', CAST((SELECT w_days FROM cap) AS STRING), 'd — funds the campaign')
    WHEN a.class = 'MARGINAL' THEN CONCAT('marginal: ', CAST(COALESCE(a.roas_w,0) AS STRING), 'x — in the 80% pool, watch')
    WHEN a.class = 'LOSER' AND a.loser_cum_sp > 0.20 * a.camp_sp AND COALESCE(a.current_bid, 0) > 0.30
      THEN 'loser beyond the 20% exploration budget — park $0.25 (spend goes to the winners)'
    WHEN a.class = 'LOSER' THEN 'loser inside the 20% allowance — keep gathering'
    WHEN a.class = 'IDLE' AND a.active_probes < 2 AND a.cand_rank <= (2 - a.active_probes)
         AND COALESCE(a.tcpc, a.win_cpc) IS NOT NULL
      THEN CONCAT('next probe candidate — lift to $',
                  CAST(ROUND(LEAST(COALESCE(1.5 * a.tcpc, a.win_cpc), 2.00), 2) AS STRING),
                  ' (', IF(a.tcpc IS NOT NULL, '1.5x target CPC', "winners' avg CPC"), '), verdict at 20 clicks')
    ELSE 'idle — waiting for a probe slot'
  END AS reason
FROM agg a;
