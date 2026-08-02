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
--
-- v2 (2026-07-30): + SB ARM — the same machinery on SB-native sources, the way V_SB_LAUNCH_TARGET
-- mirrors V_LAUNCH_PHASE1. Targets + live bids from the sb_keyword / sb_product_target config
-- mirrors; performance from sb_search_term_report (keyword grain) ∪ sb_target_report (product
-- targets) — NOT sb_keyword_report (died 2025-12-29; sb_product_target_report does not exist);
-- net ROAS is the SB ESTIMATE sales × (1 − mapped-ASIN cost_ratio) ÷ spend (SB has no per-unit
-- COGS). Target-CPC precedence: LY same-28d → FINE band (SB × ad_format via DIM_AD_GROUP
-- creative_type × match) → coarse ALL/ALL band. Capped guard: PROBE_START requires the campaign
-- NOT capping (dark ≤ 10% on the anchor day) — probing a capped campaign is a budget artifact.
-- `channel` ('SP'/'SB') routes panel rows to the right bulksheet tab.
--
-- v3 (2026-07-30): capped guard mirrored into the SP arm (sp_h/sp_ev/sp_sqd/sp_dark on SP
-- campaign_history events, anchored at FACT's watermark `wm`) — both arms now gate PROBE_START.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_KEYWORD_LIFT` AS
WITH season AS (
  SELECT COUNTIF(CURRENT_DATE('America/New_York') BETWEEN boost_start AND cooldown_end) > 0 AS in_peak
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS` WHERE category IN ('gift_season', 'prime_event')
),
cap AS (SELECT in_peak, IF(in_peak, 30.0, 20.0) AS low_cap, IF(in_peak, 3, 7) AS w_days FROM season),
wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
       FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
camps AS (
  SELECT c.campaign_id, c.campaign_name, c.daily_budget AS budget,
    LOWER(c.campaign_name) LIKE '%brand defense%' AS is_defense,
    -- v9 (Ori 2026-08-02): seasonal campaigns get their own Weekly Run home — name-based like
    -- is_defense ('prime'/'season' deliberately not matched, too ambiguous)
    REGEXP_CONTAINS(LOWER(c.campaign_name), r'christmas|xmas|valentine|easter|halloween|thanksgiving|black friday|bfcm|cyber monday|back to school|mother.?s day|father.?s day|santa|advent|holiday') AS is_seasonal
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` c, cap k
  -- v4 (Ori 2026-08-01): ANY budget — the Portfolio absorbs the launch controller; low-budget
  -- healthy campaigns run the same seat mechanism (slots = budget/$4). OOB owns them while dark.
  WHERE c.campaign_type = 'SP' AND c.campaign_state = 'ENABLED'
    AND c.serving_status IN ('CAMPAIGN_STATUS_ENABLED', 'CAMPAIGN_OUT_OF_BUDGET')
),
-- window W performance per (campaign, target) — corrected GP (price-tier COGS)
kwW AS (
  SELECT CAST(a.campaign_id AS STRING) cid, a.targeting,
    SUM(IF(a.date > DATE_SUB((SELECT d FROM wm), INTERVAL k.w_days DAY), a.Ads_clicks, 0)) clk_w,
    SUM(IF(a.date > DATE_SUB((SELECT d FROM wm), INTERVAL k.w_days DAY), a.Ads_cost, 0)) sp_w,
    SUM(IF(a.date > DATE_SUB((SELECT d FROM wm), INTERVAL k.w_days DAY), a.Ads_orders, 0)) ord_w,
    SUM(IF(a.date > DATE_SUB((SELECT d FROM wm), INTERVAL k.w_days DAY), a.Ads_sales - COALESCE(pct.tier_cost, a.TOTAL_COST_PER_UNIT)*a.Ads_units, 0)) gp_w,
    SUM(IF(a.date = (SELECT d FROM wm), a.Ads_clicks, 0)) clk1,
    SUM(IF(a.date = (SELECT d FROM wm), a.Ads_cost, 0)) sp1,
    SUM(IF(a.date = (SELECT d FROM wm), a.Ads_sales - COALESCE(pct.tier_cost, a.TOTAL_COST_PER_UNIT)*a.Ads_units, 0)) gp1,
    -- panel windows (Ori 2026-08-01: 'last 7 days' + 'prev 21 days, day 8 till 28')
    SUM(IF(a.date > DATE_SUB((SELECT d FROM wm), INTERVAL 7 DAY), a.Ads_clicks, 0)) clk7,
    SUM(IF(a.date > DATE_SUB((SELECT d FROM wm), INTERVAL 7 DAY), a.Ads_cost, 0)) sp7,
    SUM(IF(a.date > DATE_SUB((SELECT d FROM wm), INTERVAL 7 DAY), a.Ads_sales - COALESCE(pct.tier_cost, a.TOTAL_COST_PER_UNIT)*a.Ads_units, 0)) gp7,
    SUM(IF(a.date <= DATE_SUB((SELECT d FROM wm), INTERVAL 7 DAY), a.Ads_clicks, 0)) clk8_28,
    SUM(IF(a.date <= DATE_SUB((SELECT d FROM wm), INTERVAL 7 DAY), a.Ads_cost, 0)) sp8_28,
    SUM(IF(a.date <= DATE_SUB((SELECT d FROM wm), INTERVAL 7 DAY), a.Ads_sales - COALESCE(pct.tier_cost, a.TOTAL_COST_PER_UNIT)*a.Ads_units, 0)) gp8_28
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN camps c ON c.campaign_id = CAST(a.campaign_id AS STRING)
  CROSS JOIN cap k
  LEFT JOIN `onyga-482313.OI.T_PRICE_COST_TIER` pct
    ON a.Ads_units > 0 AND pct.unit_price = ROUND(SAFE_DIVIDE(a.Ads_sales, a.Ads_units), 2)
  WHERE a.date > DATE_SUB((SELECT d FROM wm), INTERVAL 28 DAY)
  GROUP BY 1, 2
),
-- full target list (idle keywords included — the candidate pool), ids + current bid
td AS (
  -- CONFIG TRUTH (Ori 2026-08-01): every ENABLED SP target from DIM_KEYWORD current rows —
  -- keywords, product targets AND auto clauses, including dormant ones with no recent delivery.
  -- Sourcing from V_TARGET_DAILY (delivery days only) silently dropped 14 enabled keywords that
  -- had not delivered recently — exactly the candidate/queue pool the engines exist to manage.
  -- One row per (campaign, target text): highest-bid copy wins (text is the FACT perf grain).
  SELECT campaign_id, target_text, keyword_id, ad_group_id, match_type, keyword_bid
  FROM (
    SELECT CAST(campaign_id AS STRING) campaign_id, keyword_text AS target_text,
           CAST(keyword_id AS STRING) keyword_id, CAST(ad_group_id AS STRING) ad_group_id,
           match_type, bid AS keyword_bid,
           ROW_NUMBER() OVER (PARTITION BY CAST(campaign_id AS STRING), keyword_text
                              ORDER BY bid DESC NULLS LAST, keyword_id) rn
    FROM `onyga-482313.OI.DIM_KEYWORD`
    WHERE is_current AND UPPER(state) = 'ENABLED'
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
  -- ly_cpc (the personal target anchor) still needs >= 10 LY clicks for quality; ly_ord (the
  -- seasonal-revival signal) counts from the first LY order — a 4-click 2-order LY seller revives.
  SELECT LOWER(TRIM(targeting)) AS kw,
         IF(SUM(Ads_clicks) >= 10, ROUND(SAFE_DIVIDE(SUM(Ads_cost), SUM(Ads_clicks)), 2), NULL) AS ly_cpc,
         SUM(Ads_clicks) AS ly_clk, SUM(Ads_orders) AS ly_ord
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 391 DAY)
                 AND DATE_SUB((SELECT d FROM wm), INTERVAL 364 DAY)
  GROUP BY 1 HAVING SUM(Ads_clicks) >= 10 OR SUM(Ads_orders) >= 1
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
-- 90d evidence per target (tested-loser bar + seat ranking) — corrected GP
t90 AS (
  SELECT CAST(a.campaign_id AS STRING) cid, a.targeting, SUM(a.Ads_clicks) clk90, SUM(a.Ads_orders) ord90,
    ROUND(SAFE_DIVIDE(SUM(a.Ads_sales - COALESCE(pct.tier_cost, a.TOTAL_COST_PER_UNIT)*a.Ads_units),
                      NULLIF(SUM(a.Ads_cost), 0)), 2) AS roas90
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN camps c ON c.campaign_id = CAST(a.campaign_id AS STRING)
  LEFT JOIN `onyga-482313.OI.T_PRICE_COST_TIER` pct
    ON a.Ads_units > 0 AND pct.unit_price = ROUND(SAFE_DIVIDE(a.Ads_sales, a.Ads_units), 2)
  WHERE a.date >= DATE_SUB((SELECT d FROM wm), INTERVAL 89 DAY)
  GROUP BY 1, 2
),
-- dark % on the SP anchor day (event log, same construction as the SB arm below) — the probe gate (v3)
sp_h AS (
  SELECT campaign_id cid, DATETIME(date, 'America/Los_Angeles') ts, serving_status
  FROM `onyga-482313.OI.V_SRC_AmazonAds_campaign_history`
  WHERE campaign_type = 'SP' AND DATE(date, 'America/Los_Angeles') = (SELECT d FROM wm)
    AND campaign_id IN (SELECT campaign_id FROM camps)
),
sp_ev AS (
  SELECT cid, ts, serving_status FROM sp_h
  UNION ALL SELECT DISTINCT cid, DATETIME((SELECT d FROM wm), TIME '00:00:00'), 'CAMPAIGN_STATUS_ENABLED' FROM sp_h
),
sp_sqd AS (SELECT cid, ts, serving_status, LEAD(ts) OVER (PARTITION BY cid ORDER BY ts) nxt FROM sp_ev),
sp_dark AS (
  SELECT cid, SUM(IF(serving_status = 'CAMPAIGN_OUT_OF_BUDGET',
    DATETIME_DIFF(COALESCE(nxt, DATETIME(DATE_ADD((SELECT d FROM wm), INTERVAL 1 DAY))), ts, MINUTE), 0)) / 1440.0 AS pd
  FROM sp_sqd GROUP BY 1
),
base AS (
  SELECT c.campaign_id, c.campaign_name, c.budget, c.is_defense, c.is_seasonal,
    td.target_text, td.keyword_id, td.ad_group_id, td.match_type,
    LOWER(td.target_text) IN ('close-match','loose-match','substitutes','complements') AS is_auto,
    LOWER(td.target_text) LIKE 'asin%' AS is_pt,
    COALESCE(td.keyword_bid, agb.default_bid) AS current_bid,
    COALESCE(w.clk_w, 0) clk_w, COALESCE(w.sp_w, 0) sp_w, COALESCE(w.ord_w, 0) ord_w,
    ROUND(SAFE_DIVIDE(w.gp_w, NULLIF(w.sp_w, 0)), 2) AS roas_w, COALESCE(w.clk1, 0) clk1,
    COALESCE(w.sp1, 0) sp1, COALESCE(w.gp1, 0) gp1, COALESCE(w.gp_w, 0) gp_w_raw,
    COALESCE(w.clk7, 0) clk7, ROUND(SAFE_DIVIDE(w.gp7, NULLIF(w.sp7, 0)), 2) AS roas7,
    COALESCE(w.sp7, 0) sp7, COALESCE(w.gp7, 0) gp7,
    COALESCE(w.clk8_28, 0) clk8_28, ROUND(SAFE_DIVIDE(w.gp8_28, NULLIF(w.sp8_28, 0)), 2) AS roas8_28,
    COALESCE(w.sp8_28, 0) sp8_28, COALESCE(w.gp8_28, 0) gp8_28,
    COALESCE(n90.clk90, 0) clk90, COALESCE(n90.ord90, 0) ord90, n90.roas90,
    li.inc_date, li.probe_bid,
    COALESCE(ep.ep_clk, 0) ep_clk, ROUND(SAFE_DIVIDE(ep.ep_gp, NULLIF(ep.ep_sp, 0)), 2) AS ep_roas,
    COALESCE(ep.ep_ord, 0) ep_ord,
    ROUND(COALESCE(IF(LOWER(td.target_text) IN ('close-match','loose-match','substitutes','complements')
                      OR LOWER(td.target_text) LIKE 'asin%', NULL, l.ly_cpc), bd.cpc_target), 2) AS tcpc,
    COALESCE(l.ly_clk, 0) AS ly_clk,
    -- SEASONAL REVIVAL (Ori 2026-08-01): it SOLD in this same 28-day window last year — its
    -- season is arriving; exempt from the tested-loser bar and jump the seat queue
    COALESCE(l.ly_ord, 0) >= 1
      AND NOT (LOWER(td.target_text) IN ('close-match','loose-match','substitutes','complements')
               OR LOWER(td.target_text) LIKE 'asin%') AS seasonal_now,
    COALESCE(dk.pd, 0) > 0.10 AS capped,
    ROUND(COALESCE(dk.pd, 0) * 100) AS pct_dark
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
  LEFT JOIN sp_dark dk ON dk.cid = c.campaign_id
  LEFT JOIN t90 n90 ON n90.cid = c.campaign_id AND n90.targeting = td.target_text
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
    SUM(c.sp1) OVER (PARTITION BY c.campaign_id) AS camp_sp1,
    ROUND(SAFE_DIVIDE(SUM(c.gp1) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp1) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas_1d,
    ROUND(SAFE_DIVIDE(SUM(c.gp_w_raw) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp_w) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas_w,
    SUM(c.clk7) OVER (PARTITION BY c.campaign_id) AS camp_clk7,
    ROUND(SAFE_DIVIDE(SUM(c.gp7) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp7) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas7,
    SUM(c.clk8_28) OVER (PARTITION BY c.campaign_id) AS camp_clk8_28,
    ROUND(SAFE_DIVIDE(SUM(c.gp8_28) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp8_28) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas8_28,
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
               IF(c.seasonal_now, 0, 1),
               IF(c.tcpc IS NOT NULL, 0, 1), c.ly_clk DESC, c.clk_w ASC, c.target_text) AS cand_rank,
    -- SEAT MECHANISM (Ori 2026-08-01, Portfolio absorbs the launch controller): slots = budget/$4;
    -- seats to proven keywords (roas90/class) then mid-tests then anchored candidates; tested
    -- losers never seated; beyond-seat rows queue at $0.25 until a seat frees.
    GREATEST(1, CAST(ROUND(c.budget / 4) AS INT64)) AS slots,
    ROW_NUMBER() OVER (PARTITION BY c.campaign_id ORDER BY
      IF(c.clk90 >= 15 AND c.ord90 = 0 AND NOT c.probing AND NOT c.probe_done AND NOT c.seasonal_now, 1, 0),
      IF(c.class IN ('WINNER','MARGINAL') OR COALESCE(c.roas90, 0) >= 1.0 OR c.probing OR c.probe_done, 0, 1),
      -- seasonal revival: sold in this window last year -> jumps the queue as its season arrives
      IF(c.seasonal_now, 0, 1),
      COALESCE(c.roas90, 0) DESC,
      IF(c.clk90 > 0, 0, 1),
      c.clk90 DESC,
      IF(c.tcpc IS NOT NULL, 0, 1),
      c.target_text) AS seat_rank
  FROM classed c
),
-- ═══════════ SB ARM (v2 2026-07-30) — same machinery on SB-native sources ═══════════
sb_camps AS (
  SELECT c.campaign_id, c.campaign_name, c.daily_budget AS budget,
    LOWER(c.campaign_name) LIKE '%brand defense%' AS is_defense,
    -- v9 (Ori 2026-08-02): seasonal campaigns get their own Weekly Run home — name-based like
    -- is_defense ('prime'/'season' deliberately not matched, too ambiguous)
    REGEXP_CONTAINS(LOWER(c.campaign_name), r'christmas|xmas|valentine|easter|halloween|thanksgiving|black friday|bfcm|cyber monday|back to school|mother.?s day|father.?s day|santa|advent|holiday') AS is_seasonal
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` c, cap k
  WHERE c.campaign_type = 'SB' AND c.campaign_state = 'ENABLED'
    AND c.serving_status IN ('CAMPAIGN_STATUS_ENABLED', 'CAMPAIGN_OUT_OF_BUDGET')
),
-- per-channel anchor: the SB reports' own watermark (FACT undercounts SB; reports refresh intraday,
-- so W and episode windows are bounded ABOVE at the anchor too — FACT only holds complete days)
sb_wm AS (SELECT LEAST(MAX(report_date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
          FROM `fivetran-hl.amazon_ads.sb_search_term_report`),
-- est. COGS ratio per campaign via its mapped ASIN (same method as V_SB_LAUNCH_TARGET — SB reports
-- carry no per-unit COGS, so net ROAS is estimated as sales × (1 − cost_ratio) ÷ spend)
sb_prod AS (
  SELECT CAST(f.campaign_id AS STRING) cid,
    SAFE_DIVIDE(ANY_VALUE(c.cost), NULLIF(ANY_VALUE(p.listing_price_amount), 0)) AS cost_ratio
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = f.ASIN_BY_CAMPAIGN_NAME
  LEFT JOIN (SELECT asin, TOTAL_COST_PER_UNIT cost FROM (
      SELECT asin, TOTAL_COST_PER_UNIT, ROW_NUMBER() OVER (PARTITION BY marketplace_id, asin ORDER BY start_date DESC) rn
      FROM `onyga-482313.OI.DIM_COSTS_HISTORY` WHERE marketplace_id='ATVPDKIKX0DER' AND end_date IS NULL) WHERE rn=1) c
    ON c.asin = f.ASIN_BY_CAMPAIGN_NAME
  GROUP BY 1
),
sb_ptlabel AS (   -- product-target label from the target report (the config mirror has no text)
  SELECT target_id, ANY_VALUE(targeting_text) txt
  FROM `fivetran-hl.amazon_ads.sb_target_report`
  WHERE report_date >= DATE_SUB((SELECT d FROM sb_wm), INTERVAL 30 DAY)
  GROUP BY 1
),
-- full target list from the minutes-fresh config mirrors (keywords ∪ product targets; SB has no
-- auto clauses) — idle keywords included, they are the probe candidate pool
sb_td AS (
  SELECT k.id AS keyword_id, CAST(k.campaign_id AS STRING) campaign_id, CAST(k.ad_group_id AS STRING) ad_group_id,
    k.keyword_text AS target_text, FALSE AS is_pt, k.match_type, k.bid AS keyword_bid
  FROM `fivetran-hl.amazon_ads.sb_keyword` k
  WHERE NOT k._fivetran_deleted AND k.state = 'enabled'
    AND CAST(k.campaign_id AS STRING) IN (SELECT campaign_id FROM sb_camps)
  UNION ALL
  SELECT pt.id, CAST(pt.campaign_id AS STRING), CAST(pt.ad_group_id AS STRING),
    COALESCE(l.txt, 'product target'), TRUE, 'TARGETING_EXPRESSION', pt.bid
  FROM `fivetran-hl.amazon_ads.sb_product_target` pt
  LEFT JOIN sb_ptlabel l ON l.target_id = pt.id
  WHERE NOT pt._fivetran_deleted AND pt.state = 'enabled'
    AND CAST(pt.campaign_id AS STRING) IN (SELECT campaign_id FROM sb_camps)
),
-- per-day performance: keyword arm from the search-term report (keyword_id grain) ∪ product arm
-- from the target report — NOT sb_keyword_report (dead since 2025-12-29)
sb_day AS (
  SELECT keyword_id AS target_id, report_date date, SUM(clicks) clk, SUM(cost) sp,
         SUM(attributed_sales_14_d) sales, SUM(attributed_conversions_14_d) ord
  FROM `fivetran-hl.amazon_ads.sb_search_term_report`
  GROUP BY 1, 2
  UNION ALL
  SELECT target_id, report_date, SUM(clicks), SUM(cost), SUM(attributed_sales_14_d), SUM(attributed_conversions_14_d)
  FROM `fivetran-hl.amazon_ads.sb_target_report`
  GROUP BY 1, 2
),
sb_kwW AS (
  SELECT t.keyword_id,
    SUM(IF(d.date > DATE_SUB((SELECT d FROM sb_wm), INTERVAL k.w_days DAY), d.clk, 0)) clk_w,
    SUM(IF(d.date > DATE_SUB((SELECT d FROM sb_wm), INTERVAL k.w_days DAY), d.sp, 0)) sp_w,
    SUM(IF(d.date > DATE_SUB((SELECT d FROM sb_wm), INTERVAL k.w_days DAY), d.ord, 0)) ord_w,
    SUM(IF(d.date > DATE_SUB((SELECT d FROM sb_wm), INTERVAL k.w_days DAY), d.sales * (1 - COALESCE(pr.cost_ratio, 0)), 0)) gp_w,
    SUM(IF(d.date = (SELECT d FROM sb_wm), d.clk, 0)) clk1,
    SUM(IF(d.date = (SELECT d FROM sb_wm), d.sp, 0)) sp1,
    SUM(IF(d.date = (SELECT d FROM sb_wm), d.sales * (1 - COALESCE(pr.cost_ratio, 0)), 0)) gp1,
    SUM(IF(d.date > DATE_SUB((SELECT d FROM sb_wm), INTERVAL 7 DAY), d.clk, 0)) clk7,
    SUM(IF(d.date > DATE_SUB((SELECT d FROM sb_wm), INTERVAL 7 DAY), d.sp, 0)) sp7,
    SUM(IF(d.date > DATE_SUB((SELECT d FROM sb_wm), INTERVAL 7 DAY), d.sales * (1 - COALESCE(pr.cost_ratio, 0)), 0)) gp7,
    SUM(IF(d.date <= DATE_SUB((SELECT d FROM sb_wm), INTERVAL 7 DAY), d.clk, 0)) clk8_28,
    SUM(IF(d.date <= DATE_SUB((SELECT d FROM sb_wm), INTERVAL 7 DAY), d.sp, 0)) sp8_28,
    SUM(IF(d.date <= DATE_SUB((SELECT d FROM sb_wm), INTERVAL 7 DAY), d.sales * (1 - COALESCE(pr.cost_ratio, 0)), 0)) gp8_28
  FROM sb_td t
  JOIN sb_day d ON d.target_id = t.keyword_id
  CROSS JOIN cap k
  LEFT JOIN sb_prod pr ON pr.cid = t.campaign_id
  WHERE d.date > DATE_SUB((SELECT d FROM sb_wm), INTERVAL 28 DAY)
    AND d.date <= (SELECT d FROM sb_wm)
  GROUP BY 1
),
sb_episode AS (
  SELECT t.keyword_id,
    SUM(d.clk) ep_clk, SUM(d.sp) ep_sp, SUM(d.ord) ep_ord,
    SUM(d.sales * (1 - COALESCE(pr.cost_ratio, 0))) ep_gp
  FROM sb_td t
  JOIN lastinc li ON li.keyword_id = t.keyword_id
  JOIN sb_day d ON d.target_id = t.keyword_id
  LEFT JOIN sb_prod pr ON pr.cid = t.campaign_id
  WHERE d.date > li.inc_date AND d.date <= (SELECT d FROM sb_wm)
  GROUP BY 1
),
sb_t90 AS (
  SELECT t.keyword_id, SUM(d.clk) clk90, SUM(d.ord) ord90,
    ROUND(SAFE_DIVIDE(SUM(d.sales * (1 - COALESCE(pr.cost_ratio, 0))), NULLIF(SUM(d.sp), 0)), 2) AS roas90
  FROM sb_td t
  JOIN sb_day d ON d.target_id = t.keyword_id
  LEFT JOIN sb_prod pr ON pr.cid = t.campaign_id
  WHERE d.date >= DATE_SUB((SELECT d FROM sb_wm), INTERVAL 89 DAY) AND d.date <= (SELECT d FROM sb_wm)
  GROUP BY 1
),
sb_adfmt AS (   -- ad-group → SB creative type (BRAND_VIDEO / PRODUCT_COLLECTION / …): the profile's
  -- ad_format grain. Canonical derivation lives in SP_LOAD_DIM_AD_GROUP — read the dimension.
  SELECT ad_group_id, ANY_VALUE(creative_type) creative_type
  FROM `onyga-482313.OI.DIM_AD_GROUP` WHERE is_current AND creative_type IS NOT NULL GROUP BY 1
),
sb_band AS (   -- FINE band cell: SB × ad_format × match (CONCLUSIVE); coarse ALL/ALL is the fallback
  SELECT parent_name, UPPER(ad_format) AS ad_format, UPPER(match_type) AS match_type,
         ROUND(AVG(cpc_target), 2) AS cpc_target
  FROM `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE`, season s
  WHERE enabled AND cpc_target IS NOT NULL AND confidence = 'CONCLUSIVE'
    AND campaign_type = 'SB' AND COALESCE(ad_format, 'NA') != 'ALL'
    AND season = IF(s.in_peak, 'PEAK', 'OFF')
  GROUP BY 1, 2, 3
),
-- dark % on the SB anchor day (event log, same construction as V_SB_LAUNCH_TARGET) — the probe gate
sb_h AS (
  SELECT campaign_id cid, DATETIME(date, 'America/Los_Angeles') ts, serving_status
  FROM `onyga-482313.OI.V_SRC_AmazonAds_campaign_history`
  WHERE campaign_type = 'SB' AND DATE(date, 'America/Los_Angeles') = (SELECT d FROM sb_wm)
    AND campaign_id IN (SELECT campaign_id FROM sb_camps)
),
sb_ev AS (
  SELECT cid, ts, serving_status FROM sb_h
  UNION ALL SELECT DISTINCT cid, DATETIME((SELECT d FROM sb_wm), TIME '00:00:00'), 'CAMPAIGN_STATUS_ENABLED' FROM sb_h
),
sb_sqd AS (SELECT cid, ts, serving_status, LEAD(ts) OVER (PARTITION BY cid ORDER BY ts) nxt FROM sb_ev),
sb_dark AS (
  SELECT cid, SUM(IF(serving_status = 'CAMPAIGN_OUT_OF_BUDGET',
    DATETIME_DIFF(COALESCE(nxt, DATETIME(DATE_ADD((SELECT d FROM sb_wm), INTERVAL 1 DAY))), ts, MINUTE), 0)) / 1440.0 AS pd
  FROM sb_sqd GROUP BY 1
),
sb_base AS (
  SELECT c.campaign_id, c.campaign_name, c.budget, c.is_defense, c.is_seasonal,
    t.target_text, t.keyword_id, t.ad_group_id, t.match_type,
    FALSE AS is_auto, t.is_pt,
    COALESCE(t.keyword_bid, agb.default_bid) AS current_bid,
    COALESCE(w.clk_w, 0) clk_w, COALESCE(w.sp_w, 0) sp_w, COALESCE(w.ord_w, 0) ord_w,
    ROUND(SAFE_DIVIDE(w.gp_w, NULLIF(w.sp_w, 0)), 2) AS roas_w, COALESCE(w.clk1, 0) clk1,
    COALESCE(w.sp1, 0) sp1, COALESCE(w.gp1, 0) gp1, COALESCE(w.gp_w, 0) gp_w_raw,
    COALESCE(w.clk7, 0) clk7, ROUND(SAFE_DIVIDE(w.gp7, NULLIF(w.sp7, 0)), 2) AS roas7,
    COALESCE(w.sp7, 0) sp7, COALESCE(w.gp7, 0) gp7,
    COALESCE(w.clk8_28, 0) clk8_28, ROUND(SAFE_DIVIDE(w.gp8_28, NULLIF(w.sp8_28, 0)), 2) AS roas8_28,
    COALESCE(w.sp8_28, 0) sp8_28, COALESCE(w.gp8_28, 0) gp8_28,
    COALESCE(n90.clk90, 0) clk90, COALESCE(n90.ord90, 0) ord90, n90.roas90,
    li.inc_date, li.probe_bid,
    COALESCE(ep.ep_clk, 0) ep_clk, ROUND(SAFE_DIVIDE(ep.ep_gp, NULLIF(ep.ep_sp, 0)), 2) AS ep_roas,
    COALESCE(ep.ep_ord, 0) ep_ord,
    ROUND(COALESCE(IF(t.is_pt, NULL, l.ly_cpc), fb.cpc_target, bd.cpc_target), 2) AS tcpc,
    COALESCE(l.ly_clk, 0) AS ly_clk,
    COALESCE(l.ly_ord, 0) >= 1 AND NOT t.is_pt AS seasonal_now,
    COALESCE(dk.pd, 0) > 0.10 AS capped,
    ROUND(COALESCE(dk.pd, 0) * 100) AS pct_dark
  FROM sb_camps c
  JOIN sb_td t ON t.campaign_id = c.campaign_id
  LEFT JOIN agb ON agb.ad_group_id = t.ad_group_id
  LEFT JOIN sb_kwW w ON w.keyword_id = t.keyword_id
  LEFT JOIN lastinc li ON li.keyword_id = t.keyword_id
  LEFT JOIN sb_episode ep ON ep.keyword_id = t.keyword_id
  LEFT JOIN ly l ON l.kw = LOWER(TRIM(t.target_text))
  LEFT JOIN camp_parent cp ON cp.cid = c.campaign_id
  LEFT JOIN sb_adfmt af ON af.ad_group_id = t.ad_group_id
  LEFT JOIN sb_band fb ON fb.parent_name = cp.parent_name
    AND fb.ad_format = UPPER(COALESCE(af.creative_type, 'NA'))
    AND fb.match_type = IF(t.is_pt, 'PRODUCT', UPPER(COALESCE(t.match_type, '')))
  LEFT JOIN band bd ON bd.parent_name = cp.parent_name
    AND bd.match_type = IF(t.is_pt, 'PRODUCT', UPPER(COALESCE(t.match_type, '')))
  LEFT JOIN sb_dark dk ON dk.cid = c.campaign_id
  LEFT JOIN sb_t90 n90 ON n90.keyword_id = t.keyword_id
),
sb_classed AS (
  SELECT b.*,
    CASE
      WHEN b.ord_w >= 1 AND COALESCE(b.roas_w, 0) >= 1.1 THEN 'WINNER'
      WHEN b.ord_w >= 1 AND COALESCE(b.roas_w, 0) >= 0.7 THEN 'MARGINAL'
      WHEN b.clk_w > 0 THEN 'LOSER'
      ELSE 'IDLE'
    END AS class,
    (b.inc_date IS NOT NULL
     AND b.inc_date > DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY)
     AND b.ep_clk < 20) AS probing,
    (b.inc_date IS NOT NULL
     AND b.inc_date > DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY)
     AND b.ep_clk >= 20) AS probe_done
  FROM sb_base b
),
sb_agg AS (
  SELECT c.*,
    SUM(c.sp_w) OVER (PARTITION BY c.campaign_id) AS camp_sp,
    SUM(c.sp1) OVER (PARTITION BY c.campaign_id) AS camp_sp1,
    ROUND(SAFE_DIVIDE(SUM(c.gp1) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp1) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas_1d,
    ROUND(SAFE_DIVIDE(SUM(c.gp_w_raw) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp_w) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas_w,
    SUM(c.clk7) OVER (PARTITION BY c.campaign_id) AS camp_clk7,
    ROUND(SAFE_DIVIDE(SUM(c.gp7) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp7) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas7,
    SUM(c.clk8_28) OVER (PARTITION BY c.campaign_id) AS camp_clk8_28,
    ROUND(SAFE_DIVIDE(SUM(c.gp8_28) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp8_28) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas8_28,
    SUM(IF(c.class = 'LOSER', c.sp_w, 0)) OVER (PARTITION BY c.campaign_id) AS loser_sp,
    SUM(IF(c.probing, 1, 0)) OVER (PARTITION BY c.campaign_id) AS active_probes,
    ROUND(SAFE_DIVIDE(SUM(IF(c.class IN ('WINNER','MARGINAL'), c.sp_w, 0)) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(IF(c.class IN ('WINNER','MARGINAL'), c.clk_w, 0)) OVER (PARTITION BY c.campaign_id), 0)), 2) AS win_cpc,
    SUM(IF(c.class = 'LOSER' AND NOT c.probing, c.sp_w, 0))
      OVER (PARTITION BY c.campaign_id ORDER BY IF(c.class = 'LOSER' AND NOT c.probing, COALESCE(c.roas_w, 0), 999) DESC, c.sp_w
            ROWS UNBOUNDED PRECEDING) AS loser_cum_sp,
    ROW_NUMBER() OVER (PARTITION BY c.campaign_id
      ORDER BY IF(c.class = 'IDLE' AND NOT c.probing AND NOT c.probe_done, 0, 1),
               IF(c.seasonal_now, 0, 1),
               IF(c.tcpc IS NOT NULL, 0, 1), c.ly_clk DESC, c.clk_w ASC, c.target_text) AS cand_rank,
    GREATEST(1, CAST(ROUND(c.budget / 4) AS INT64)) AS slots,
    ROW_NUMBER() OVER (PARTITION BY c.campaign_id ORDER BY
      IF(c.clk90 >= 15 AND c.ord90 = 0 AND NOT c.probing AND NOT c.probe_done AND NOT c.seasonal_now, 1, 0),
      IF(c.class IN ('WINNER','MARGINAL') OR COALESCE(c.roas90, 0) >= 1.0 OR c.probing OR c.probe_done, 0, 1),
      -- seasonal revival: sold in this window last year -> jumps the queue as its season arrives
      IF(c.seasonal_now, 0, 1),
      COALESCE(c.roas90, 0) DESC,
      IF(c.clk90 > 0, 0, 1),
      c.clk90 DESC,
      IF(c.tcpc IS NOT NULL, 0, 1),
      c.target_text) AS seat_rank
  FROM sb_classed c
)
SELECT
  a.campaign_id, a.campaign_name, 'SP' AS channel, ROUND(a.budget, 0) AS budget,
  (SELECT in_peak FROM season) AS in_peak, (SELECT w_days FROM cap) AS w_days,
  ROUND(a.camp_sp, 2) AS campaign_spend_w,
  ROUND(100 * SAFE_DIVIDE(a.loser_sp, NULLIF(a.camp_sp, 0))) AS loser_share_pct,
  a.active_probes,
  a.keyword_id, a.ad_group_id, a.target_text, a.match_type, a.is_auto, a.is_pt,
  ROUND(a.current_bid, 2) AS current_bid,
  a.clk_w AS clicks_w, ROUND(a.sp_w, 2) AS spend_w, a.ord_w AS orders_w, a.roas_w,
  a.tcpc AS target_cpc, a.class,
  a.probing, a.inc_date AS probe_started, a.ep_clk AS probe_clicks, a.ep_roas AS probe_roas,
  CAST(a.clk7 AS INT64) AS clicks_7d, a.roas7 AS roas_7d,
  CAST(a.clk8_28 AS INT64) AS clicks_8_28, a.roas8_28 AS roas_8_28,
  ROUND(a.sp1, 2) AS spend_1d, ROUND(a.camp_sp1, 2) AS camp_spend_1d,
  CAST(a.camp_clk7 AS INT64) AS camp_clicks_7d, a.camp_roas7 AS camp_roas_7d,
  CAST(a.camp_clk8_28 AS INT64) AS camp_clicks_8_28, a.camp_roas8_28 AS camp_roas_8_28,
  a.pct_dark, a.capped, a.slots, a.seat_rank, a.is_defense, a.is_seasonal, a.seasonal_now,
  -- ROLE (Ori 2026-08-02): the keyword's job in the campaign economy, one word.
  -- FUNDER pays for everything · WATCH earns but thin · PROBE mid-test · CANDIDATE next up
  -- · TRIAL gathering its 4 clicks · PARKED allowance-parked (can return) · RETIRED tested
  -- loser (permanent, seasonal revival exempts) · QUEUED beyond the seats · IDLE waiting
  CASE
    WHEN a.is_defense THEN 'DEFENSE'
    WHEN a.probing OR a.probe_done THEN 'PROBE'
    WHEN a.clk90 >= 15 AND a.ord90 = 0 AND NOT a.seasonal_now THEN 'RETIRED'
    WHEN a.seat_rank > a.slots THEN 'QUEUED'
    WHEN a.class = 'WINNER' THEN 'FUNDER'
    WHEN a.class = 'MARGINAL' THEN 'WATCH'
    WHEN a.class = 'LOSER' AND a.clk_w >= 4 AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp THEN 'PARKED'
    WHEN a.class = 'LOSER' THEN 'TRIAL'
    WHEN a.class = 'IDLE' AND NOT a.capped AND a.seat_rank <= a.slots
         AND a.active_probes < (SELECT IF(in_peak, 4, 2) FROM season)
         AND a.cand_rank <= ((SELECT IF(in_peak, 4, 2) FROM season) - a.active_probes) THEN 'CANDIDATE'
    ELSE 'IDLE'
  END AS role,

  -- HEALTHY-CAMPAIGN BUDGET RULE (Ori 2026-08-01 tuning, knob #5): the only budget move for a
  -- not-capped campaign is the loss cut — evidence window (W) AND today both under 0.6x ->
  -- -20% with the seasonal floor ($10 off / $15 peak). Raises belong to the dark ladder
  -- (a healthy campaign is not hitting its cap, a raise buys nothing).
  CASE WHEN NOT a.is_defense AND COALESCE(a.camp_roas_w, 0) < 0.6 AND COALESCE(a.camp_roas_1d, 0) < 0.6
        AND a.camp_sp > 0 AND a.budget > (SELECT IF(in_peak, 15.0, 10.0) FROM season)
       THEN ROUND(GREATEST(a.budget * 0.8, (SELECT IF(in_peak, 15.0, 10.0) FROM season)), 2) END AS suggested_budget,
  CASE WHEN NOT a.is_defense AND COALESCE(a.camp_roas_w, 0) < 0.6 AND COALESCE(a.camp_roas_1d, 0) < 0.6
        AND a.camp_sp > 0 AND a.budget > (SELECT IF(in_peak, 15.0, 10.0) FROM season)
       THEN CONCAT('W ', CAST(COALESCE(a.camp_roas_w,0) AS STRING), 'x AND today ',
                   CAST(COALESCE(a.camp_roas_1d,0) AS STRING), 'x — both losing → cut 20% (floor $',
                   CAST(CAST((SELECT IF(in_peak, 15, 10) FROM season) AS INT64) AS STRING), ')') END AS budget_reason,
  CASE
    -- probe verdicts first
    WHEN a.is_defense THEN 'DEFENSE'
    WHEN a.probe_done AND COALESCE(a.ep_roas, 0) >= 1.0 THEN 'WINNER_FOUND'
    WHEN a.probe_done THEN 'PARK'
    -- active probes: daily movement by the click methodology
    WHEN a.probing AND a.clk1 > 6 AND a.ep_ord = 0 THEN 'PROBE_ADJUST'
    WHEN a.probing THEN 'PROBE_WAIT'
    -- tested loser (>=15 clicks/90d, no sale): permanent park — its seat frees for the next test
    WHEN a.clk90 >= 15 AND a.ord90 = 0 AND NOT a.seasonal_now THEN IF(COALESCE(a.current_bid, 0) > 0.30, 'PARK', 'IDLE')
    -- SEAT MECHANISM (Ori 2026-08-01): beyond the budget/$4 seats -> queue at $0.25
    WHEN a.seat_rank > a.slots THEN IF(COALESCE(a.current_bid, 0) > 0.30, 'PARK_WAIT', 'IDLE')
    -- the 80% pool
    -- SEASON RAMP (Ori 2026-08-02): its season is arriving (seasonal_now) and the bid sits
    -- under 60% of the current LY-anchored target — glide UP toward target (+10%/day, min 5c),
    -- never above it from this rule. WINNER/MARGINAL only (orders prove the season is real);
    -- losers re-enter through the probe path at 1.5x target instead.
    WHEN a.class IN ('WINNER','MARGINAL') AND a.seasonal_now AND a.tcpc IS NOT NULL
         AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < 0.60 * a.tcpc THEN 'RAISE_TO_TARGET'
    WHEN a.class = 'WINNER' THEN 'KEEP'
    -- target < bid (Ori 2026-08-01): MARGINAL glides -5%/day toward target; LOSING goes straight
    -- TO the target bid. Winners are never pulled down.
    WHEN a.class = 'MARGINAL' AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05 THEN 'EASE_TO_TARGET'
    WHEN a.class = 'MARGINAL' THEN 'KEEP'
    -- losers beyond the 20% allowance → park (worst first; the cum-sum keeps the best within it)
    -- 4-CLICK TRIAL GATE (Ori 2026-08-02, FRESH-SP/BROAD BTS case): "1 click do not break" —
    -- a loser can only be allowance-parked or cut-to-target once it has >= 4 clicks in W (the
    -- same evidence bar as TRIM). Under that it is still in its trial: KEEP_TAIL, keep gathering.
    -- (Without the gate, a day-1 campaign's 20% allowance is cents and first clicks park instantly.)
    WHEN a.class = 'LOSER' AND a.clk_w >= 4 AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp AND COALESCE(a.current_bid, 0) > 0.30 THEN 'PARK'
    WHEN a.class = 'LOSER' AND a.clk_w >= 4 AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05 THEN 'CUT_TO_TARGET'
    WHEN a.class = 'LOSER' THEN 'KEEP_TAIL'
    -- idle pool: promote the next candidates into probes when slots are free
    WHEN a.class = 'IDLE' AND NOT a.capped AND a.seat_rank <= a.slots
         AND a.active_probes < (SELECT IF(in_peak, 4, 2) FROM season) AND a.cand_rank <= ((SELECT IF(in_peak, 4, 2) FROM season) - a.active_probes)
         THEN 'PROBE_START'
    ELSE 'IDLE'
  END AS action,
  CASE
    WHEN a.is_defense THEN NULL
    WHEN a.probe_done AND COALESCE(a.ep_roas, 0) >= 1.0 THEN NULL
    WHEN a.probe_done THEN 0.25
    WHEN a.probing AND a.clk1 > 6 AND a.ep_ord = 0 THEN ROUND(GREATEST(a.current_bid * 0.95, 0.20), 2)
    WHEN a.probing THEN NULL
    WHEN a.clk90 >= 15 AND a.ord90 = 0 AND NOT a.seasonal_now THEN IF(COALESCE(a.current_bid, 0) > 0.30, 0.25, NULL)
    WHEN a.seat_rank > a.slots THEN IF(COALESCE(a.current_bid, 0) > 0.30, 0.25, NULL)
    WHEN a.class IN ('WINNER','MARGINAL') AND a.seasonal_now AND a.tcpc IS NOT NULL
         AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < 0.60 * a.tcpc
      THEN ROUND(LEAST(GREATEST(a.current_bid * 1.10, a.current_bid + 0.05), a.tcpc), 2)
    WHEN a.class = 'WINNER' THEN NULL
    WHEN a.class = 'MARGINAL' AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05
      THEN ROUND(GREATEST(a.current_bid * 0.95, a.tcpc), 2)
    WHEN a.class = 'MARGINAL' THEN NULL
    WHEN a.class = 'LOSER' AND a.clk_w >= 4 AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp AND COALESCE(a.current_bid, 0) > 0.30 THEN 0.25
    WHEN a.class = 'LOSER' AND a.clk_w >= 4 AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05 THEN a.tcpc
    WHEN a.class = 'LOSER' THEN NULL
    WHEN a.class = 'IDLE' AND NOT a.capped AND a.seat_rank <= a.slots
         AND a.active_probes < (SELECT IF(in_peak, 4, 2) FROM season) AND a.cand_rank <= ((SELECT IF(in_peak, 4, 2) FROM season) - a.active_probes)
      -- $1 SEAT-ENTRY FLOOR (Ori 2026-08-02: "i wont move if not") — also the anchorless entry:
      -- no LY target, no band, no winner CPC -> enter at the $1 floor instead of never starting
      THEN ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 1.00), 2.00), 2)
    ELSE NULL
  END AS suggested_bid,
  CASE
    WHEN a.is_defense THEN 'brand defense — the moat is bought at whatever it costs; bids run on the coacher defense mode, never parked by ROAS'
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
    WHEN a.clk90 >= 15 AND a.ord90 = 0 AND NOT a.seasonal_now
      THEN CONCAT('tested ', CAST(a.clk90 AS STRING), ' clicks/90d with 0 orders — permanent park; its seat goes to the next candidate')
    WHEN a.seat_rank > a.slots
      THEN CONCAT('queue #', CAST(a.seat_rank - a.slots AS STRING), ' — ', CAST(a.slots AS STRING),
                  ' seats (budget ÷ $4); its test resumes when a seat frees')
    WHEN a.class IN ('WINNER','MARGINAL') AND a.seasonal_now AND a.tcpc IS NOT NULL
         AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < 0.60 * a.tcpc
      THEN CONCAT('SEASON RAMP — its season is arriving and the bid is under 60% of the current target $',
                  CAST(a.tcpc AS STRING), ': glide up +10%/day toward it (beyond target only via the coacher)')
    WHEN a.class = 'WINNER' THEN CONCAT('winner: ', CAST(COALESCE(a.roas_w,0) AS STRING), 'x over ', CAST((SELECT w_days FROM cap) AS STRING), 'd — funds the campaign')
    WHEN a.class = 'MARGINAL' AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05
      THEN CONCAT('marginal ', CAST(COALESCE(a.roas_w,0) AS STRING), 'x with bid above target — glide -5%/day toward $', CAST(a.tcpc AS STRING))
    WHEN a.class = 'MARGINAL' THEN CONCAT('marginal: ', CAST(COALESCE(a.roas_w,0) AS STRING), 'x — in the 80% pool, watch')
    WHEN a.class = 'LOSER' AND a.clk_w < 4
      THEN CONCAT('still in its 4-click trial (', CAST(CAST(a.clk_w AS INT64) AS STRING), ' clicks so far) — 1 click does not break; keep gathering')
    WHEN a.class = 'LOSER' AND a.clk_w >= 4 AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp AND COALESCE(a.current_bid, 0) > 0.30
      THEN CONCAT('loser beyond the ', CAST(CAST((SELECT IF(in_peak, 40, 20) FROM season) AS INT64) AS STRING), '% exploration budget — park $0.25 (spend goes to the winners)')
    WHEN a.class = 'LOSER' AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05
      THEN CONCAT('losing at ', CAST(COALESCE(a.roas_w,0) AS STRING), 'x with bid above target — straight to the target bid $', CAST(a.tcpc AS STRING))
    WHEN a.class = 'LOSER' THEN CONCAT('loser inside the ', CAST(CAST((SELECT IF(in_peak, 40, 20) FROM season) AS INT64) AS STRING), '% allowance — keep gathering')
    WHEN a.class = 'IDLE' AND a.capped
      THEN 'idle — campaign capped (dark > 10%): probes held, a budget artifact not a bid problem'
    WHEN a.class = 'IDLE' AND a.seat_rank <= a.slots AND a.active_probes < (SELECT IF(in_peak, 4, 2) FROM season) AND a.cand_rank <= ((SELECT IF(in_peak, 4, 2) FROM season) - a.active_probes)
      THEN CONCAT(IF(a.seasonal_now, 'SEASONAL REVIVAL (sold in this window last year) — ', ''), 'next probe candidate — lift to $',
                  CAST(ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 1.00), 2.00), 2) AS STRING),
                  ' (', CASE WHEN a.tcpc IS NOT NULL AND 1.5 * a.tcpc >= 1.00 THEN '1.5x target CPC'
                             WHEN COALESCE(a.win_cpc, 0) >= 1.00 AND a.tcpc IS NULL THEN "winners' avg CPC"
                             ELSE '$1 seat-entry floor — will not move below it' END,
                  '), verdict at 20 clicks')
    ELSE 'idle — waiting for a probe slot'
  END AS reason
FROM agg a
UNION ALL
-- ── SB block: identical action grammar, incl. the capped PROBE_START gate (both arms since v3;
--    probing a dark campaign is a budget artifact — the no-loss-cuts rule; running probes still
--    get verdicts and the −5% descent); net ROAS is the cost-ratio ESTIMATE ──
SELECT
  a.campaign_id, a.campaign_name, 'SB' AS channel, ROUND(a.budget, 0) AS budget,
  (SELECT in_peak FROM season) AS in_peak, (SELECT w_days FROM cap) AS w_days,
  ROUND(a.camp_sp, 2) AS campaign_spend_w,
  ROUND(100 * SAFE_DIVIDE(a.loser_sp, NULLIF(a.camp_sp, 0))) AS loser_share_pct,
  a.active_probes,
  a.keyword_id, a.ad_group_id, a.target_text, a.match_type, a.is_auto, a.is_pt,
  ROUND(a.current_bid, 2) AS current_bid,
  CAST(a.clk_w AS INT64) AS clicks_w, ROUND(a.sp_w, 2) AS spend_w, CAST(a.ord_w AS INT64) AS orders_w, a.roas_w,
  a.tcpc AS target_cpc, a.class,
  a.probing, a.inc_date AS probe_started, CAST(a.ep_clk AS INT64) AS probe_clicks, a.ep_roas AS probe_roas,
  CAST(a.clk7 AS INT64) AS clicks_7d, a.roas7 AS roas_7d,
  CAST(a.clk8_28 AS INT64) AS clicks_8_28, a.roas8_28 AS roas_8_28,
  ROUND(a.sp1, 2) AS spend_1d, ROUND(a.camp_sp1, 2) AS camp_spend_1d,
  CAST(a.camp_clk7 AS INT64) AS camp_clicks_7d, a.camp_roas7 AS camp_roas_7d,
  CAST(a.camp_clk8_28 AS INT64) AS camp_clicks_8_28, a.camp_roas8_28 AS camp_roas_8_28,
  a.pct_dark, a.capped, a.slots, a.seat_rank, a.is_defense, a.is_seasonal, a.seasonal_now,
  -- ROLE (Ori 2026-08-02): the keyword's job in the campaign economy, one word.
  -- FUNDER pays for everything · WATCH earns but thin · PROBE mid-test · CANDIDATE next up
  -- · TRIAL gathering its 4 clicks · PARKED allowance-parked (can return) · RETIRED tested
  -- loser (permanent, seasonal revival exempts) · QUEUED beyond the seats · IDLE waiting
  CASE
    WHEN a.is_defense THEN 'DEFENSE'
    WHEN a.probing OR a.probe_done THEN 'PROBE'
    WHEN a.clk90 >= 15 AND a.ord90 = 0 AND NOT a.seasonal_now THEN 'RETIRED'
    WHEN a.seat_rank > a.slots THEN 'QUEUED'
    WHEN a.class = 'WINNER' THEN 'FUNDER'
    WHEN a.class = 'MARGINAL' THEN 'WATCH'
    WHEN a.class = 'LOSER' AND a.clk_w >= 4 AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp THEN 'PARKED'
    WHEN a.class = 'LOSER' THEN 'TRIAL'
    WHEN a.class = 'IDLE' AND NOT a.capped AND a.seat_rank <= a.slots
         AND a.active_probes < (SELECT IF(in_peak, 4, 2) FROM season)
         AND a.cand_rank <= ((SELECT IF(in_peak, 4, 2) FROM season) - a.active_probes) THEN 'CANDIDATE'
    ELSE 'IDLE'
  END AS role,

  -- HEALTHY-CAMPAIGN BUDGET RULE (Ori 2026-08-01 tuning, knob #5): the only budget move for a
  -- not-capped campaign is the loss cut — evidence window (W) AND today both under 0.6x ->
  -- -20% with the seasonal floor ($10 off / $15 peak). Raises belong to the dark ladder
  -- (a healthy campaign is not hitting its cap, a raise buys nothing).
  CASE WHEN NOT a.is_defense AND COALESCE(a.camp_roas_w, 0) < 0.6 AND COALESCE(a.camp_roas_1d, 0) < 0.6
        AND a.camp_sp > 0 AND a.budget > (SELECT IF(in_peak, 15.0, 10.0) FROM season)
       THEN ROUND(GREATEST(a.budget * 0.8, (SELECT IF(in_peak, 15.0, 10.0) FROM season)), 2) END AS suggested_budget,
  CASE WHEN NOT a.is_defense AND COALESCE(a.camp_roas_w, 0) < 0.6 AND COALESCE(a.camp_roas_1d, 0) < 0.6
        AND a.camp_sp > 0 AND a.budget > (SELECT IF(in_peak, 15.0, 10.0) FROM season)
       THEN CONCAT('W ', CAST(COALESCE(a.camp_roas_w,0) AS STRING), 'x AND today ',
                   CAST(COALESCE(a.camp_roas_1d,0) AS STRING), 'x — both losing → cut 20% (floor $',
                   CAST(CAST((SELECT IF(in_peak, 15, 10) FROM season) AS INT64) AS STRING), ')') END AS budget_reason,
  CASE
    WHEN a.is_defense THEN 'DEFENSE'
    WHEN a.probe_done AND COALESCE(a.ep_roas, 0) >= 1.0 THEN 'WINNER_FOUND'
    WHEN a.probe_done THEN 'PARK'
    WHEN a.probing AND a.clk1 > 6 AND a.ep_ord = 0 THEN 'PROBE_ADJUST'
    WHEN a.probing THEN 'PROBE_WAIT'
    -- tested loser (>=15 clicks/90d, no sale): permanent park — its seat frees for the next test
    WHEN a.clk90 >= 15 AND a.ord90 = 0 AND NOT a.seasonal_now THEN IF(COALESCE(a.current_bid, 0) > 0.30, 'PARK', 'IDLE')
    -- SEAT MECHANISM (Ori 2026-08-01): beyond the budget/$4 seats -> queue at $0.25
    WHEN a.seat_rank > a.slots THEN IF(COALESCE(a.current_bid, 0) > 0.30, 'PARK_WAIT', 'IDLE')
    -- SEASON RAMP (Ori 2026-08-02): its season is arriving (seasonal_now) and the bid sits
    -- under 60% of the current LY-anchored target — glide UP toward target (+10%/day, min 5c),
    -- never above it from this rule. WINNER/MARGINAL only (orders prove the season is real);
    -- losers re-enter through the probe path at 1.5x target instead.
    WHEN a.class IN ('WINNER','MARGINAL') AND a.seasonal_now AND a.tcpc IS NOT NULL
         AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < 0.60 * a.tcpc THEN 'RAISE_TO_TARGET'
    WHEN a.class = 'WINNER' THEN 'KEEP'
    -- target < bid (Ori 2026-08-01): MARGINAL glides -5%/day toward target; LOSING goes straight
    -- TO the target bid. Winners are never pulled down.
    WHEN a.class = 'MARGINAL' AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05 THEN 'EASE_TO_TARGET'
    WHEN a.class = 'MARGINAL' THEN 'KEEP'
    -- 4-CLICK TRIAL GATE (Ori 2026-08-02, FRESH-SP/BROAD BTS case): "1 click do not break" —
    -- a loser can only be allowance-parked or cut-to-target once it has >= 4 clicks in W (the
    -- same evidence bar as TRIM). Under that it is still in its trial: KEEP_TAIL, keep gathering.
    -- (Without the gate, a day-1 campaign's 20% allowance is cents and first clicks park instantly.)
    WHEN a.class = 'LOSER' AND a.clk_w >= 4 AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp AND COALESCE(a.current_bid, 0) > 0.30 THEN 'PARK'
    WHEN a.class = 'LOSER' AND a.clk_w >= 4 AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05 THEN 'CUT_TO_TARGET'
    WHEN a.class = 'LOSER' THEN 'KEEP_TAIL'
    WHEN a.class = 'IDLE' AND NOT a.capped AND a.seat_rank <= a.slots
         AND a.active_probes < (SELECT IF(in_peak, 4, 2) FROM season) AND a.cand_rank <= ((SELECT IF(in_peak, 4, 2) FROM season) - a.active_probes)
         THEN 'PROBE_START'
    ELSE 'IDLE'
  END AS action,
  CASE
    WHEN a.is_defense THEN NULL
    WHEN a.probe_done AND COALESCE(a.ep_roas, 0) >= 1.0 THEN NULL
    WHEN a.probe_done THEN 0.25
    WHEN a.probing AND a.clk1 > 6 AND a.ep_ord = 0 THEN ROUND(GREATEST(a.current_bid * 0.95, 0.20), 2)
    WHEN a.probing THEN NULL
    WHEN a.clk90 >= 15 AND a.ord90 = 0 AND NOT a.seasonal_now THEN IF(COALESCE(a.current_bid, 0) > 0.30, 0.25, NULL)
    WHEN a.seat_rank > a.slots THEN IF(COALESCE(a.current_bid, 0) > 0.30, 0.25, NULL)
    WHEN a.class IN ('WINNER','MARGINAL') AND a.seasonal_now AND a.tcpc IS NOT NULL
         AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < 0.60 * a.tcpc
      THEN ROUND(LEAST(GREATEST(a.current_bid * 1.10, a.current_bid + 0.05), a.tcpc), 2)
    WHEN a.class = 'WINNER' THEN NULL
    WHEN a.class = 'MARGINAL' AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05
      THEN ROUND(GREATEST(a.current_bid * 0.95, a.tcpc), 2)
    WHEN a.class = 'MARGINAL' THEN NULL
    WHEN a.class = 'LOSER' AND a.clk_w >= 4 AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp AND COALESCE(a.current_bid, 0) > 0.30 THEN 0.25
    WHEN a.class = 'LOSER' AND a.clk_w >= 4 AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05 THEN a.tcpc
    WHEN a.class = 'LOSER' THEN NULL
    WHEN a.class = 'IDLE' AND NOT a.capped AND a.seat_rank <= a.slots
         AND a.active_probes < (SELECT IF(in_peak, 4, 2) FROM season) AND a.cand_rank <= ((SELECT IF(in_peak, 4, 2) FROM season) - a.active_probes)
      -- $1 SEAT-ENTRY FLOOR (Ori 2026-08-02: "i wont move if not") — also the anchorless entry:
      -- no LY target, no band, no winner CPC -> enter at the $1 floor instead of never starting
      THEN ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 1.00), 2.00), 2)
    ELSE NULL
  END AS suggested_bid,
  CASE
    WHEN a.is_defense THEN 'brand defense — the moat is bought at whatever it costs; bids run on the coacher defense mode, never parked by ROAS'
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
    WHEN a.clk90 >= 15 AND a.ord90 = 0 AND NOT a.seasonal_now
      THEN CONCAT('tested ', CAST(a.clk90 AS STRING), ' clicks/90d with 0 orders — permanent park; its seat goes to the next candidate')
    WHEN a.seat_rank > a.slots
      THEN CONCAT('queue #', CAST(a.seat_rank - a.slots AS STRING), ' — ', CAST(a.slots AS STRING),
                  ' seats (budget ÷ $4); its test resumes when a seat frees')
    WHEN a.class IN ('WINNER','MARGINAL') AND a.seasonal_now AND a.tcpc IS NOT NULL
         AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < 0.60 * a.tcpc
      THEN CONCAT('SEASON RAMP — its season is arriving and the bid is under 60% of the current target $',
                  CAST(a.tcpc AS STRING), ': glide up +10%/day toward it (beyond target only via the coacher)')
    WHEN a.class = 'WINNER' THEN CONCAT('winner: ', CAST(COALESCE(a.roas_w,0) AS STRING), 'x over ', CAST((SELECT w_days FROM cap) AS STRING), 'd — funds the campaign (est. net ROAS)')
    WHEN a.class = 'MARGINAL' AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05
      THEN CONCAT('marginal ', CAST(COALESCE(a.roas_w,0) AS STRING), 'x with bid above target — glide -5%/day toward $', CAST(a.tcpc AS STRING))
    WHEN a.class = 'MARGINAL' THEN CONCAT('marginal: ', CAST(COALESCE(a.roas_w,0) AS STRING), 'x — in the 80% pool, watch (est. net ROAS)')
    WHEN a.class = 'LOSER' AND a.clk_w < 4
      THEN CONCAT('still in its 4-click trial (', CAST(CAST(a.clk_w AS INT64) AS STRING), ' clicks so far) — 1 click does not break; keep gathering')
    WHEN a.class = 'LOSER' AND a.clk_w >= 4 AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp AND COALESCE(a.current_bid, 0) > 0.30
      THEN CONCAT('loser beyond the ', CAST(CAST((SELECT IF(in_peak, 40, 20) FROM season) AS INT64) AS STRING), '% exploration budget — park $0.25 (spend goes to the winners)')
    WHEN a.class = 'LOSER' AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05
      THEN CONCAT('losing at ', CAST(COALESCE(a.roas_w,0) AS STRING), 'x with bid above target — straight to the target bid $', CAST(a.tcpc AS STRING))
    WHEN a.class = 'LOSER' THEN CONCAT('loser inside the ', CAST(CAST((SELECT IF(in_peak, 40, 20) FROM season) AS INT64) AS STRING), '% allowance — keep gathering')
    WHEN a.class = 'IDLE' AND a.capped
      THEN 'idle — campaign capped (dark > 10%): probes held, a budget artifact not a bid problem'
    WHEN a.class = 'IDLE' AND a.seat_rank <= a.slots AND a.active_probes < (SELECT IF(in_peak, 4, 2) FROM season) AND a.cand_rank <= ((SELECT IF(in_peak, 4, 2) FROM season) - a.active_probes)
      THEN CONCAT(IF(a.seasonal_now, 'SEASONAL REVIVAL (sold in this window last year) — ', ''), 'next probe candidate — lift to $',
                  CAST(ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 1.00), 2.00), 2) AS STRING),
                  ' (', CASE WHEN a.tcpc IS NOT NULL AND 1.5 * a.tcpc >= 1.00 THEN '1.5x target CPC'
                             WHEN COALESCE(a.win_cpc, 0) >= 1.00 AND a.tcpc IS NULL THEN "winners' avg CPC"
                             ELSE '$1 seat-entry floor — will not move below it' END,
                  '), verdict at 20 clicks')
    ELSE 'idle — waiting for a probe slot'
  END AS reason
FROM sb_agg a;
