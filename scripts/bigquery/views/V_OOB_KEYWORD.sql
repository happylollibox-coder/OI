-- V_OOB_KEYWORD — keyword layer of the Out-of-budget phase (Weekly Run). Spec: architecture/OOB_BUDGET_PHASE.md §v2.
--
-- One row per (OOB campaign, target) — SP keywords/auto clauses/product targets AND SB keywords/
-- product targets (v2.1, Ori 2026-07-30: "i cant see sb keywords as a hierarchy") — with a bid
-- suggestion built from the SAME constants as the launch controller, applied to every out-of-budget
-- campaign regardless of engine (launch or working). SP signals from FACT + price-tier COGS; SB from
-- the SB reports with the est. net ROAS via the campaign's mapped-ASIN cost ratio (same method as
-- V_SB_LAUNCH_TARGET — sb config mirrors sb_keyword/sb_product_target are minutes-fresh KEEP_RAW).
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
         4 AS click_goal_day, 6 AS click_cap_day,
         -- budget-constrained probing (Ori 2026-07-30): tested keywords park, big bids trim
         15 AS tested_clk, 0.25 AS bid_park, 1.00 AS big_bid, 0.85 AS bid_big_trim
),
wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
       FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
-- the phase's campaign population + campaign-level ROAS signals (for the hold-while-capping test)
oob AS (
  SELECT campaign_id, campaign_name, pct_dark, current_budget AS budget, roas_1d AS c_roas1, roas_prev2 AS c_roas_prev2
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
-- tested clicks per target over 90d — the "has it had its test" evidence for the park rule
t90 AS (
  SELECT CAST(a.campaign_id AS STRING) cid, a.targeting, SUM(a.Ads_clicks) clk90, SUM(a.Ads_orders) ord90,
    ROUND(SAFE_DIVIDE(SUM(a.Ads_sales - COALESCE(pct.tier_cost, a.TOTAL_COST_PER_UNIT) * a.Ads_units),
                      NULLIF(SUM(a.Ads_cost), 0)), 2) AS roas90
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN oob o ON o.campaign_id = CAST(a.campaign_id AS STRING)
  LEFT JOIN `onyga-482313.OI.T_PRICE_COST_TIER` pct
    ON a.Ads_units > 0 AND pct.unit_price = ROUND(SAFE_DIVIDE(a.Ads_sales, a.Ads_units), 2)
  WHERE a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 89 DAY) AND (SELECT d FROM wm)
  GROUP BY 1, 2
),
-- current bid + ids: latest V_TARGET_DAILY row per (campaign, target); ad-group default as fallback
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
-- ── target CPC (Ori 2026-07-30: "show also target cpc, based on time last year if data exists") ──
-- Precedence: (1) the SAME 28 days one year back (364-day offset keeps Sun–Sat weekday alignment),
-- per keyword TEXT account-wide, needs >= 10 LY clicks to count; (2) else the coacher band
-- cpc_target (DE_PRODUCT_STRATEGY_PROFILE, product × season × match, coarse ALL/ALL cells averaged
-- across intents, CONCLUSIVE + enabled only); (3) else NULL. Auto clauses + product targets skip LY
-- (the clause text is not product-specific across campaigns) — band or nothing.
ly AS (
  -- ly_cpc: >= 10 clicks in the LY same-28d window. seasonal = CONCENTRATION (Ori 2026-08-02):
  -- >= 2 window orders AND >= 25% of the LY YEAR's orders in the window (uniform ~8%).
  SELECT LOWER(TRIM(targeting)) AS kw,
         IF(SUM(IF(date >= DATE_SUB((SELECT d FROM wm), INTERVAL 391 DAY), Ads_clicks, 0)) >= 10,
            ROUND(SAFE_DIVIDE(SUM(IF(date >= DATE_SUB((SELECT d FROM wm), INTERVAL 391 DAY), Ads_cost, 0)),
                              SUM(IF(date >= DATE_SUB((SELECT d FROM wm), INTERVAL 391 DAY), Ads_clicks, 0))), 2), NULL) AS ly_cpc,
         SUM(IF(date >= DATE_SUB((SELECT d FROM wm), INTERVAL 391 DAY), Ads_orders, 0)) AS ly_ord,
         SUM(Ads_orders) AS ly_year_ord,
         -- launch-artifact guard: concentration only means SEASON if the keyword existed at
         -- least a month before the window (else all history sits inside it by construction)
         MIN(IF(Ads_clicks > 0, date, NULL)) AS ly_first
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 728 DAY)
                 AND DATE_SUB((SELECT d FROM wm), INTERVAL 364 DAY)
  GROUP BY 1 HAVING SUM(IF(date >= DATE_SUB((SELECT d FROM wm), INTERVAL 391 DAY), Ads_clicks, 0)) >= 10
             OR SUM(IF(date >= DATE_SUB((SELECT d FROM wm), INTERVAL 391 DAY), Ads_orders, 0)) >= 1
),
season AS (
  SELECT COUNTIF(CURRENT_DATE('America/New_York') BETWEEN boost_start AND cooldown_end) > 0 AS in_peak
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS` WHERE category IN ('gift_season', 'prime_event')
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
-- Portfolio 80/20 probe protection (same rule as the coacher suppression, ADS_COACH_DECISION_MATRIX
-- §Safety Guards): keywords mid-probe-episode (or imminent PROBE_START) are owned by the lift
-- engine — the seat model must not park/trim/brake them mid-test; verdict comes at 20 clicks.
lift_probes AS (
  SELECT DISTINCT keyword_id FROM `onyga-482313.OI.V_KEYWORD_LIFT`
  WHERE probing OR action = 'PROBE_START'
),
-- 1-day cooldown: did we already upload a change for this keyword?
lc AS (
  SELECT keyword_id, DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), MAX(DATE(applied_at)), DAY) AS days_since
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE keyword_id IS NOT NULL GROUP BY 1
),
-- ── SB arm (v2.1): dark SB campaigns' keywords + product targets, from the SB reports ──
oob_sb AS (
  SELECT campaign_id, campaign_name, pct_dark, current_budget AS budget, roas_1d AS c_roas1, roas_prev2 AS c_roas_prev2
  FROM `onyga-482313.OI.V_OOB_BUDGET_PHASE`
  WHERE channel = 'SB' AND pct_dark > 10
),
wm_sb AS (SELECT LEAST(MAX(report_date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
          FROM `fivetran-hl.amazon_ads.sb_campaign_report`),
-- est. COGS ratio per SB campaign via its mapped ASIN (same method as the SB launch views)
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
sb_ptlabel AS (
  SELECT target_id, ANY_VALUE(targeting_text) txt
  FROM `fivetran-hl.amazon_ads.sb_target_report`
  WHERE report_date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 30 DAY)
  GROUP BY 1
),
sb_tgt AS (
  SELECT k.id AS target_id, CAST(k.campaign_id AS STRING) cid, CAST(k.ad_group_id AS STRING) ad_group_id,
    k.keyword_text AS target_text, FALSE AS is_pt, k.match_type, k.bid
  FROM `fivetran-hl.amazon_ads.sb_keyword` k
  WHERE NOT k._fivetran_deleted AND k.state='enabled'
    AND CAST(k.campaign_id AS STRING) IN (SELECT campaign_id FROM oob_sb)
  UNION ALL
  SELECT pt.id, CAST(pt.campaign_id AS STRING), CAST(pt.ad_group_id AS STRING),
    COALESCE(l.txt, 'product target'), TRUE, 'TARGETING_EXPRESSION', pt.bid
  FROM `fivetran-hl.amazon_ads.sb_product_target` pt
  LEFT JOIN sb_ptlabel l ON l.target_id = pt.id
  WHERE NOT pt._fivetran_deleted AND pt.state='enabled'
    AND CAST(pt.campaign_id AS STRING) IN (SELECT campaign_id FROM oob_sb)
),
sb_tgtday AS (
  SELECT keyword_id AS target_id, report_date date, SUM(clicks) clk, SUM(cost) cost,
         SUM(attributed_sales_14_d) sales, SUM(attributed_conversions_14_d) orders
  FROM `fivetran-hl.amazon_ads.sb_search_term_report`
  WHERE report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 2 DAY) AND (SELECT d FROM wm_sb)
  GROUP BY 1, 2
  UNION ALL
  SELECT target_id, report_date, SUM(clicks), SUM(cost), SUM(attributed_sales_14_d), SUM(attributed_conversions_14_d)
  FROM `fivetran-hl.amazon_ads.sb_target_report`
  WHERE report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 2 DAY) AND (SELECT d FROM wm_sb)
  GROUP BY 1, 2
),
sb_t90 AS (
  SELECT target_id, SUM(clk) clk90, SUM(conv) ord90, SUM(sp) sp90, SUM(sales) sales90 FROM (
    SELECT keyword_id AS target_id, SUM(clicks) clk, SUM(attributed_conversions_14_d) conv,
           SUM(cost) sp, SUM(attributed_sales_14_d) sales FROM `fivetran-hl.amazon_ads.sb_search_term_report`
    WHERE report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 89 DAY) AND (SELECT d FROM wm_sb) GROUP BY 1
    UNION ALL
    SELECT target_id, SUM(clicks), SUM(attributed_conversions_14_d), SUM(cost), SUM(attributed_sales_14_d)
    FROM `fivetran-hl.amazon_ads.sb_target_report`
    WHERE report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 89 DAY) AND (SELECT d FROM wm_sb) GROUP BY 1
  ) GROUP BY 1
),
sb_tsig AS (
  SELECT t.target_id,
    SUM(IF(d.date=(SELECT d FROM wm_sb), d.clk,0)) clk1,
    SUM(IF(d.date=(SELECT d FROM wm_sb), d.cost,0)) sp1,
    SUM(IF(d.date=(SELECT d FROM wm_sb), d.orders,0)) units1,
    MAX(IF(d.date=(SELECT d FROM wm_sb), SAFE_DIVIDE(d.sales*(1-COALESCE(pr.cost_ratio,0)), NULLIF(d.cost,0)), NULL)) AS roas1,
    SUM(IF(d.date<(SELECT d FROM wm_sb), d.clk,0)) clk2,
    SUM(IF(d.date<(SELECT d FROM wm_sb), d.cost,0)) sp2,
    SUM(IF(d.date<(SELECT d FROM wm_sb), d.orders,0)) units2,
    SAFE_DIVIDE(SUM(IF(d.date<(SELECT d FROM wm_sb), d.sales*(1-COALESCE(pr.cost_ratio,0)), 0)),
                NULLIF(SUM(IF(d.date<(SELECT d FROM wm_sb), d.cost,0)),0)) AS roas_prev2
  FROM sb_tgt t
  LEFT JOIN sb_tgtday d ON d.target_id = t.target_id
  LEFT JOIN prod pr ON pr.cid = t.cid
  GROUP BY 1
),
base AS (
  -- SEAT MODEL (Ori 2026-08-01): drive from the FULL current target list (td), not just targets
  -- that clicked recently — the queue includes zero-click keywords sitting at full bids, which
  -- were previously invisible to this view ("lottery tickets" stealing the odd click).
  SELECT o.campaign_id, o.campaign_name, o.pct_dark, o.budget, o.c_roas1, o.c_roas_prev2,
    td.target_text, td.keyword_id, td.ad_group_id, td.match_type,
    LOWER(td.target_text) IN ('close-match','loose-match','substitutes','complements') AS is_auto,
    LOWER(td.target_text) LIKE 'asin%' AS is_pt,
    FALSE AS is_sb,
    COALESCE(td.keyword_bid, agb.default_bid) AS current_bid,
    COALESCE(t.clk1, 0) clk1, COALESCE(t.sp1, 0) sp1, COALESCE(t.units1, 0) units1, t.roas1,
    COALESCE(t.clk2, 0) clk2, COALESCE(t.sp2, 0) sp2, COALESCE(t.units2, 0) units2, t.roas_prev2,
    (COALESCE(t.roas1, 0) >= 1.0 OR COALESCE(t.roas_prev2, 0) >= 1.0) AS converting,
    COALESCE(t90.clk90, 0) AS clk90, COALESCE(t90.ord90, 0) AS ord90,
    -- recent corrected net ROAS over the full 90d — the seat-priority ranking metric
    t90.roas90,
    lc.days_since AS days_since_change
  FROM td
  JOIN oob o ON o.campaign_id = td.campaign_id
  LEFT JOIN tsig t ON t.cid = td.campaign_id AND t.targeting = td.target_text
  LEFT JOIN t90 ON t90.cid = td.campaign_id AND t90.targeting = td.target_text
  LEFT JOIN agb ON agb.ad_group_id = td.ad_group_id
  LEFT JOIN lc ON lc.keyword_id = td.keyword_id
  UNION ALL
  SELECT o.campaign_id, o.campaign_name, o.pct_dark, o.budget, o.c_roas1, o.c_roas_prev2,
    t.target_text, t.target_id AS keyword_id, t.ad_group_id, t.match_type,
    FALSE AS is_auto, t.is_pt, TRUE AS is_sb,
    t.bid AS current_bid,
    s.clk1, ROUND(s.sp1,2), s.units1, ROUND(s.roas1,2), s.clk2, ROUND(s.sp2,2), s.units2, ROUND(s.roas_prev2,2),
    (COALESCE(s.roas1, 0) >= 1.0 OR COALESCE(s.roas_prev2, 0) >= 1.0) AS converting,
    COALESCE(s90.clk90, 0), COALESCE(s90.ord90, 0),
    ROUND(SAFE_DIVIDE(s90.sales90 * (1 - COALESCE(pr.cost_ratio, 0)), NULLIF(s90.sp90, 0)), 2) AS roas90,
    lc.days_since
  FROM sb_tgt t
  JOIN oob_sb o ON o.campaign_id = t.cid
  JOIN sb_tsig s ON s.target_id = t.target_id
  LEFT JOIN sb_t90 s90 ON s90.target_id = t.target_id
  LEFT JOIN prod pr ON pr.cid = t.cid
  LEFT JOIN lc ON lc.keyword_id = t.target_id
),
-- affordable CPC per campaign (Ori 2026-07-30: "TRIM floor should not stop at $1.00") —
-- budget ÷ (targets × 4-click goal), floored at bid_min. Self-scaling: a $10/17-target campaign
-- trims toward $0.20; a $70/10-target campaign has aff ≈ $1.75 and its bids are left alone.
baseN AS (
  SELECT b.*,
    ROUND(GREATEST(SAFE_DIVIDE(b.budget, COUNT(*) OVER (PARTITION BY b.campaign_id) * 4), 0.20), 2) AS aff_cpc,
    -- concentration (Ori 2026-07-30): share of window spend on CONVERTING keywords — when >= 80%
    -- the campaign is already winner-concentrated and converters glide -5% instead of -15% FIT
    SAFE_DIVIDE(SUM(IF(b.converting, b.sp1 + b.sp2, 0)) OVER (PARTITION BY b.campaign_id),
                NULLIF(SUM(b.sp1 + b.sp2) OVER (PARTITION BY b.campaign_id), 0)) AS conv_share
  FROM base b
),
-- target CPC resolved BEFORE the bid CASE so converting keywords can be fitted to it (Ori 2026-07-30)
withT AS (
  SELECT b.*,
    ROUND(COALESCE(IF(b.is_auto OR b.is_pt, NULL, ly.ly_cpc), bd.cpc_target), 2) AS tcpc,
    CASE WHEN NOT (b.is_auto OR b.is_pt) AND ly.ly_cpc IS NOT NULL THEN 'LY'
         WHEN bd.cpc_target IS NOT NULL THEN 'BAND' END AS tcpc_src,
    -- SEASONAL REVIVAL (Ori 2026-08-01): sold in this same 28d window LAST YEAR -> its season is
    -- arriving; it is never permanent-parked and jumps the candidate queue for a seat
    COALESCE(ly.ly_ord, 0) >= 2 AND SAFE_DIVIDE(ly.ly_ord, NULLIF(ly.ly_year_ord, 0)) >= 0.25 AND ly.ly_first <= DATE_SUB((SELECT d FROM wm), INTERVAL 421 DAY) AND NOT (b.is_auto OR b.is_pt) AS seasonal_now
  FROM baseN b
  LEFT JOIN ly ON ly.kw = LOWER(TRIM(b.target_text))
  LEFT JOIN camp_parent cp ON cp.cid = b.campaign_id
  LEFT JOIN band bd ON bd.parent_name = cp.parent_name
    AND bd.match_type = CASE WHEN b.is_pt THEN 'PRODUCT' WHEN b.is_auto THEN 'AUTO'
                             WHEN UPPER(COALESCE(b.match_type,'')) IN ('TARGETING_EXPRESSION','ASIN','ASIN EXPANDED') THEN 'PRODUCT'
                             ELSE UPPER(COALESCE(b.match_type, '')) END
),
-- ── SEAT MODEL (Ori 2026-08-01, "lets do it") ──────────────────────────────────────────────
-- slots = max(1, round(budget/4)) — $4/day buys one keyword its 4-click trial ($10 → 3 seats).
-- Seat ranking: converters by recent (90d corrected) net ROAS — winner is always main — then
-- mid-tests by clicks-so-far (finish what you started), then untested candidates (target-CPC
-- anchored first). Tested losers (>=15 clk/90d, 0 orders) are never seated. Beyond-seat rows
-- queue at $0.25 (the test pauses, not dies). When a seat frees, the next candidate ACTIVATEs
-- at min(1.5 x target CPC, $1.50) (fallback: per-seat affordable), paced at
-- max(1, floor(0.20 x budget / 4)) activations/day — 80% of any raise keeps feeding winners.
seats AS (
  SELECT b.*,
    -- COST-AWARE SEATS (Ori 2026-08-02): the $4 seat assumes $1 clicks — a WINNER's bid premium
    -- above $1 (x 4 clicks) comes off the budget before dividing. ME-SP/PT B2: $10 budget with a
    -- $1.56 winner -> (10 - 2.24)/4 = 2 seats, not 3. Sales raise the budget, seats come back.
    GREATEST(1, CAST(ROUND(GREATEST(0, b.budget - SUM(IF(b.converting, GREATEST(0, 4 * (COALESCE(b.current_bid, 0) - 1)), 0)) OVER (PARTITION BY b.campaign_id)) / 4) AS INT64)) AS slots,
    ROUND(GREATEST(SAFE_DIVIDE(b.budget, GREATEST(1, CAST(ROUND(GREATEST(0, b.budget - SUM(IF(b.converting, GREATEST(0, 4 * (COALESCE(b.current_bid, 0) - 1)), 0)) OVER (PARTITION BY b.campaign_id)) / 4) AS INT64)) * 4), 0.20), 2) AS seat_cpc,
    (b.clk90 >= 15 AND b.ord90 = 0 AND NOT b.seasonal_now) AS tested_loser,
    ROW_NUMBER() OVER (PARTITION BY b.campaign_id ORDER BY
      IF(b.clk90 >= 15 AND b.ord90 = 0 AND NOT b.seasonal_now, 1, 0),
      IF(b.converting OR COALESCE(b.roas90, 0) >= 1.0, 0, 1),
      IF(b.seasonal_now, 0, 1),
      COALESCE(b.roas90, 0) DESC,
      IF(b.clk90 > 0, 0, 1),
      b.clk90 DESC,
      IF(b.tcpc IS NOT NULL, 0, 1),
      b.target_text) AS seat_rank
  FROM withT b
),
seats2 AS (
  SELECT s.*,
    s.keyword_id IS NOT NULL AND s.keyword_id IN (SELECT keyword_id FROM lift_probes) AS is_lift_probe,
    ROW_NUMBER() OVER (PARTITION BY s.campaign_id
      ORDER BY IF(s.seat_rank <= s.slots AND COALESCE(s.current_bid, 0) <= 0.30 AND NOT s.tested_loser, 0, 1),
               s.seat_rank) AS act_rank
  FROM seats s
)
SELECT
  b.campaign_id, b.campaign_name, b.pct_dark,
  b.keyword_id, b.ad_group_id, b.target_text, b.match_type, b.is_auto, b.is_pt, b.is_sb,
  ROUND(b.current_bid, 2) AS current_bid,
  b.clk1 AS clicks_1d, ROUND(b.sp1, 2) AS spend_1d, ROUND(SAFE_DIVIDE(b.sp1, NULLIF(b.clk1,0)), 2) AS cpc_1d,
  b.units1 AS units_1d, b.roas1 AS roas_1d,
  b.clk2 AS clicks_prev2, ROUND(b.sp2, 2) AS spend_prev2, ROUND(SAFE_DIVIDE(b.sp2, NULLIF(b.clk2,0)), 2) AS cpc_prev2,
  b.units2 AS units_prev2, b.roas_prev2,
  b.converting, b.days_since_change,
  b.tcpc AS target_cpc,
  b.tcpc_src AS target_cpc_source,
  b.slots, b.seat_rank, b.seat_cpc, b.seasonal_now,
  -- ROLE (Ori 2026-08-02): the keyword's job in the campaign economy (see V_KEYWORD_LIFT)
  CASE
    WHEN b.is_lift_probe AND b.seat_rank <= b.slots THEN 'PROBE'
    -- AUTO DOCTRINE (Ori 2026-08-02): 4 fixed clauses — never retired/queued; trim + negate
    WHEN b.is_auto THEN CASE
      WHEN b.converting THEN 'WINNER'
      WHEN COALESCE(b.roas90, 0) >= 1.0 THEN 'WATCH'
      ELSE 'TRIAL' END
    WHEN b.tested_loser AND NOT b.is_lift_probe THEN 'RETIRED'
    WHEN b.seat_rank > b.slots THEN 'QUEUED'
    WHEN COALESCE(b.current_bid, 0) > 0 AND b.current_bid <= 0.30 THEN 'CANDIDATE'
    -- OOB has WINNERS not funders (Ori 2026-08-02): net ROAS >= 1.0 over the LAST 3 DAYS,
    -- always seated first; 90d-proven but cold in the last 3 -> WATCH (holds its seat)
    WHEN b.converting THEN 'WINNER'
    WHEN COALESCE(b.roas90, 0) >= 1.0 THEN 'WATCH'
    ELSE 'TRIAL'
  END AS role,
  CASE
    WHEN b.current_bid IS NULL THEN NULL
    WHEN COALESCE(b.days_since_change, 99) < 1 THEN NULL
    -- DARK, NO RAISE COMING (Ori 2026-08-04, VIDEO- BALL 72% dark): the converting/probe holds
    -- assume "the budget raise is the lever" — but when yesterday's blended ROAS is under the
    -- ladder's 1.2x raise gate the budget is cutting/floored and the BIDS own the dark. Brake
    -- every keyword that clicked unprofitably yesterday; only 90d-proven seats and keywords
    -- that PAID yesterday keep their bid (winners never pulled down).
    WHEN b.pct_dark > 10 AND COALESCE(b.c_roas1, 0) < 1.2 AND COALESCE(b.roas90, 0) < 1.0
         AND b.clk1 >= 1 AND COALESCE(b.roas1, 0) < 1.0 AND b.current_bid > x.bid_min + 0.05
      THEN ROUND(GREATEST(b.current_bid * LEAST(x.bid_slow, 1 - 0.30 * b.pct_dark / 100), x.bid_min), 2)
    -- mid-probe keyword: the Portfolio 80/20 engine owns it — no seat-model action mid-test
    -- v14 (Ori 2026-08-02 "should those be parked?"): a probe only keeps its bid while it HOLDS
    -- A SEAT — beyond the seats it queues at $0.25 like any mid-test (test pauses, not dies).
    -- A mid-probe keyword never permanent-parks (its 20-click verdict outranks the 15-click bar).
    WHEN b.is_lift_probe AND b.seat_rank <= b.slots THEN NULL
    -- tested loser: permanent park (had its 15-click trial, no sale)
    WHEN b.tested_loser AND NOT b.is_lift_probe AND NOT b.is_auto AND b.current_bid > x.bid_park + 0.05 THEN x.bid_park
    WHEN b.tested_loser AND NOT b.is_lift_probe AND NOT b.is_auto THEN NULL
    -- beyond the seats: queue at $0.25 — the test pauses, not dies (seat model, Ori 2026-08-01)
    WHEN b.seat_rank > b.slots AND NOT b.is_auto THEN IF(b.current_bid > 0.30, x.bid_park, NULL)
    -- seated after being parked: ACTIVATE at the probe entry bid, paced by the 20% rule
    WHEN b.current_bid <= 0.30
      THEN IF(b.act_rank <= GREATEST(1, CAST(FLOOR(0.20 * b.budget / 4) AS INT64)),
              -- $1 SEAT-ENTRY FLOOR (Ori 2026-08-02: "i wont move if not")
              ROUND(LEAST(GREATEST(COALESCE(1.5 * b.tcpc, b.seat_cpc), 1.00), x.bid_max), 2), NULL)
    -- CONVERTING while CAPPED (Ori 2026-07-30): never raise the bid — the budget raise buys the
    -- volume, CHEAPER clicks buy more of it. Enough clicks + bid above what clicks actually cost →
    -- FIT the bid down to the realized 3d CPC (you keep winning the same auctions, priced honestly).
    WHEN b.converting THEN CASE
      -- campaign already winner-concentrated (>=80% of spend on converters): purpose is MORE
      -- clicks — glide the 6+-clickers down gently -5%/day (floor: real CPC)
      WHEN COALESCE(b.conv_share, 0) >= 0.80 THEN
        IF(b.clk1 > 6 AND b.current_bid > COALESCE(SAFE_DIVIDE(b.sp1 + b.sp2, NULLIF(b.clk1 + b.clk2, 0)), b.current_bid) + 0.05,
           ROUND(GREATEST(b.current_bid * 0.95, SAFE_DIVIDE(b.sp1 + b.sp2, NULLIF(b.clk1 + b.clk2, 0))), 2), NULL)
      -- mixed campaign: fit the converter to its real CPC -15%/day while the ladder cleans the leak
      WHEN b.clk1 >= x.click_goal_day
        AND SAFE_DIVIDE(b.sp1 + b.sp2, NULLIF(b.clk1 + b.clk2, 0)) IS NOT NULL
        AND b.current_bid > SAFE_DIVIDE(b.sp1 + b.sp2, NULLIF(b.clk1 + b.clk2, 0)) + 0.05
        THEN ROUND(GREATEST(b.current_bid * x.bid_big_trim, SAFE_DIVIDE(b.sp1 + b.sp2, NULLIF(b.clk1 + b.clk2, 0))), 2)
      ELSE NULL END
    -- seated PROVEN keyword (90d corrected net ROAS >= 1.0): holds its seat untouched — the
    -- budget raise is the lever for winners, never the brake (approved example: seat 2 at 1.03x)
    WHEN COALESCE(b.roas90, 0) >= 1.0 THEN NULL
    -- seated mid-test: trial economics against the PER-SEAT affordable (budget / slots / 4 clicks).
    -- TRIM needs REAL evidence (Ori 2026-08-01) — 4+ clicks yesterday; step max(15%, 30% x dark).
    WHEN b.current_bid > b.seat_cpc + 0.05 AND b.clk1 >= x.click_goal_day
      THEN ROUND(GREATEST(b.current_bid * LEAST(x.bid_big_trim, 1 - 0.30 * b.pct_dark / 100), b.seat_cpc), 2)
    -- DARK_BRAKE (Ori 2026-08-01, replaces flat SLOW -5%): the bid lever against darkness is
    -- CAMPAIGN-WIDE and proportional — every clicked keyword steps down max(5%, 30% x dark) per
    -- day, re-firing daily while the campaign stays capped, floor $0.20. No single keyword is
    -- "the eater"; the campaign bleeds from many bids collectively.
    -- only keywords that clicked YESTERDAY (Ori 2026-08-01: never brake a keyword that did not
    -- click — its bid did not eat the budget; it just loses its chance to ever test)
    WHEN b.clk1 >= 1 AND b.current_bid > x.bid_min + 0.05
      THEN ROUND(GREATEST(b.current_bid * LEAST(x.bid_slow, 1 - 0.30 * b.pct_dark / 100), x.bid_min), 2)
    ELSE NULL
  END AS suggested_bid,
  CASE
    WHEN b.current_bid IS NULL THEN 'NO_BID'
    WHEN COALESCE(b.days_since_change, 99) < 1 THEN 'HOLD'
    WHEN b.pct_dark > 10 AND COALESCE(b.c_roas1, 0) < 1.2 AND COALESCE(b.roas90, 0) < 1.0
         AND b.clk1 >= 1 AND COALESCE(b.roas1, 0) < 1.0 AND b.current_bid > x.bid_min + 0.05 THEN 'DARK_BRAKE'
    WHEN b.is_lift_probe AND b.seat_rank <= b.slots THEN 'HOLD'
    WHEN b.tested_loser AND NOT b.is_lift_probe AND NOT b.is_auto THEN IF(b.current_bid > x.bid_park + 0.05, 'PARK', 'HOLD')
    WHEN b.seat_rank > b.slots AND NOT b.is_auto THEN IF(b.current_bid > 0.30, 'PARK_WAIT', 'HOLD')
    WHEN b.current_bid <= 0.30
      THEN IF(b.act_rank <= GREATEST(1, CAST(FLOOR(0.20 * b.budget / 4) AS INT64)), 'ACTIVATE', 'HOLD')
    WHEN b.converting THEN CASE
      WHEN COALESCE(b.conv_share, 0) >= 0.80 THEN
        IF(b.clk1 > 6 AND b.current_bid > COALESCE(SAFE_DIVIDE(b.sp1 + b.sp2, NULLIF(b.clk1 + b.clk2, 0)), b.current_bid) + 0.05, 'EASE', 'HOLD')
      WHEN b.clk1 >= x.click_goal_day
        AND b.current_bid > COALESCE(SAFE_DIVIDE(b.sp1 + b.sp2, NULLIF(b.clk1 + b.clk2, 0)), b.current_bid) + 0.05 THEN 'FIT_CPC'
      ELSE 'HOLD' END
    WHEN COALESCE(b.roas90, 0) >= 1.0 THEN 'HOLD'
    WHEN b.current_bid > b.seat_cpc + 0.05 AND b.clk1 >= x.click_goal_day THEN 'TRIM_BID'
    WHEN b.clk1 >= 1 AND b.current_bid > x.bid_min + 0.05 THEN 'DARK_BRAKE'
    ELSE 'HOLD'
  END AS bid_action,
  CASE
    WHEN b.current_bid IS NULL THEN 'no bid on record'
    WHEN COALESCE(b.days_since_change, 99) < 1 THEN 'changed today — one suggestion per day'
    WHEN b.pct_dark > 10 AND COALESCE(b.c_roas1, 0) < 1.2 AND COALESCE(b.roas90, 0) < 1.0
         AND b.clk1 >= 1 AND COALESCE(b.roas1, 0) < 1.0 AND b.current_bid > x.bid_min + 0.05
      THEN CONCAT('campaign ', CAST(CAST(b.pct_dark AS INT64) AS STRING), '% dark and no budget raise coming (yesterday blended ',
                  FORMAT('%.2f', COALESCE(b.c_roas1, 0)), 'x, under the 1.2x raise gate) — bids own the dark: brake ',
                  CAST(CAST(ROUND(100 * (1 - LEAST(x.bid_slow, 1 - 0.30 * b.pct_dark / 100))) AS INT64) AS STRING),
                  '%/day toward $0.20; this bid spent ', CAST(b.clk1 AS STRING), ' clicks at ',
                  FORMAT('%.2f', COALESCE(b.roas1, 0)), 'x yesterday')
    WHEN b.is_lift_probe AND b.seat_rank <= b.slots THEN 'probe in flight — holds a seat until its 20-click verdict (the Portfolio 80/20 engine owns the bid)'
    WHEN b.tested_loser AND NOT b.is_lift_probe AND NOT b.is_auto
      THEN CONCAT('tested ', CAST(b.clk90 AS STRING), ' clicks/90d with 0 orders — permanent park; its seat goes to the next candidate')
    WHEN b.seat_rank > b.slots AND NOT b.is_auto THEN
      IF(b.converting OR COALESCE(b.roas90, 0) >= 1.0,
         CONCAT('proven (', CAST(COALESCE(b.roas90, 0) AS STRING), 'x 90d) but the budget funds only ',
                CAST(b.slots AS STRING), ' seats — queue #', CAST(b.seat_rank - b.slots AS STRING)),
         CONCAT(IF(b.is_lift_probe, 'probe pauses — beyond the seats while the campaign caps; ', ''),
                'queue #', CAST(b.seat_rank - b.slots AS STRING), ' of the waiting line — ',
                CAST(b.slots AS STRING), ' seats (budget ÷ $4); its test resumes when a seat frees'))
    WHEN b.current_bid <= 0.30 THEN
      IF(b.act_rank <= GREATEST(1, CAST(FLOOR(0.20 * b.budget / 4) AS INT64)),
         CONCAT(IF(b.seasonal_now, 'SEASONAL REVIVAL (sold in this window last year) — ', ''),
                'seat freed — ACTIVATE at ', IF(b.tcpc IS NOT NULL AND 1.5 * b.tcpc >= 1.00, '1.5x target CPC', 'the $1 seat-entry floor'),
                ' to resume its test (', CAST(b.clk90 AS STRING), '/', CAST(x.tested_clk AS STRING), ' clicks so far)'),
         'seat ready — activates on a coming day (20% pace: 80% of the budget keeps feeding the winners)')
    WHEN b.converting THEN CASE
      WHEN COALESCE(b.conv_share, 0) >= 0.80 THEN
        IF(b.clk1 > 6 AND b.current_bid > COALESCE(SAFE_DIVIDE(b.sp1 + b.sp2, NULLIF(b.clk1 + b.clk2, 0)), b.current_bid) + 0.05,
           CONCAT('winners take ', CAST(ROUND(100*b.conv_share) AS STRING),
                  '% of spend — ease -5%/day toward real CPC $', CAST(ROUND(SAFE_DIVIDE(b.sp1 + b.sp2, NULLIF(b.clk1 + b.clk2, 0)), 2) AS STRING),
                  ' to buy MORE clicks from the same budget'),
           'converting in a winner-concentrated campaign — hold (budget raise is the lever)')
      WHEN b.clk1 >= x.click_goal_day
        AND b.current_bid > COALESCE(SAFE_DIVIDE(b.sp1 + b.sp2, NULLIF(b.clk1 + b.clk2, 0)), b.current_bid) + 0.05
        THEN CONCAT('selling while capping — fit bid down to the real CPC $',
                    CAST(ROUND(SAFE_DIVIDE(b.sp1 + b.sp2, NULLIF(b.clk1 + b.clk2, 0)), 2) AS STRING),
                    ': budget raise buys volume, cheaper clicks buy more of it (never raise while dark)')
      ELSE 'converting — hold; the budget raise is the lever while capping' END
    WHEN COALESCE(b.roas90, 0) >= 1.0
      THEN CONCAT('proven ', CAST(b.roas90 AS STRING), 'x over 90d — holds its seat; the budget raise is the lever, not the brake')
    WHEN b.current_bid > b.seat_cpc + 0.05 AND b.clk1 >= x.click_goal_day
      THEN CONCAT('bid eats the capped budget (', CAST(b.clk1 AS STRING), ' clicks yesterday) — trim ',
                  CAST(CAST(ROUND(100 * (1 - LEAST(x.bid_big_trim, 1 - 0.30 * b.pct_dark / 100))) AS INT64) AS STRING),
                  '%/day toward the seat CPC $', CAST(b.seat_cpc AS STRING), ' (= budget ÷ seats ÷ 4-click goal)')
    WHEN b.clk1 >= 1 AND b.current_bid > x.bid_min + 0.05
      THEN CONCAT('campaign ', CAST(CAST(b.pct_dark AS INT64) AS STRING), '% dark — brake all bids ',
                  CAST(CAST(ROUND(100 * (1 - LEAST(x.bid_slow, 1 - 0.30 * b.pct_dark / 100))) AS INT64) AS STRING),
                  '%/day (max of 5%, 30%×dark) until the budget survives the day · floor $0.20')
    ELSE 'no clicks yesterday (its bid did not eat the budget) or already at the $0.20 floor — hold'
  END AS bid_reason
FROM seats2 b CROSS JOIN k x;
