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
  SELECT CAST(a.campaign_id AS STRING) cid, a.targeting, SUM(a.Ads_clicks) clk90
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN oob o ON o.campaign_id = CAST(a.campaign_id AS STRING)
  WHERE a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 89 DAY) AND (SELECT d FROM wm)
  GROUP BY 1, 2
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
-- ── target CPC (Ori 2026-07-30: "show also target cpc, based on time last year if data exists") ──
-- Precedence: (1) the SAME 28 days one year back (364-day offset keeps Sun–Sat weekday alignment),
-- per keyword TEXT account-wide, needs >= 10 LY clicks to count; (2) else the coacher band
-- cpc_target (DE_PRODUCT_STRATEGY_PROFILE, product × season × match, coarse ALL/ALL cells averaged
-- across intents, CONCLUSIVE + enabled only); (3) else NULL. Auto clauses + product targets skip LY
-- (the clause text is not product-specific across campaigns) — band or nothing.
ly AS (
  SELECT LOWER(TRIM(targeting)) AS kw, SUM(Ads_cost) sp, SUM(Ads_clicks) clk
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 391 DAY)
                 AND DATE_SUB((SELECT d FROM wm), INTERVAL 364 DAY)
  GROUP BY 1 HAVING SUM(Ads_clicks) >= 10
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
  SELECT target_id, SUM(clk) clk90 FROM (
    SELECT keyword_id AS target_id, SUM(clicks) clk FROM `fivetran-hl.amazon_ads.sb_search_term_report`
    WHERE report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 89 DAY) AND (SELECT d FROM wm_sb) GROUP BY 1
    UNION ALL
    SELECT target_id, SUM(clicks) FROM `fivetran-hl.amazon_ads.sb_target_report`
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
  SELECT o.campaign_id, o.campaign_name, o.pct_dark, o.budget, o.c_roas1, o.c_roas_prev2,
    t.targeting AS target_text, td.keyword_id, td.ad_group_id, td.match_type,
    LOWER(t.targeting) IN ('close-match','loose-match','substitutes','complements') AS is_auto,
    LOWER(t.targeting) LIKE 'asin%' AS is_pt,
    FALSE AS is_sb,
    COALESCE(td.keyword_bid, agb.default_bid) AS current_bid,
    t.clk1, t.sp1, t.units1, t.roas1, t.clk2, t.sp2, t.units2, t.roas_prev2,
    (COALESCE(t.roas1, 0) >= 1.0 OR COALESCE(t.roas_prev2, 0) >= 1.0) AS converting,
    COALESCE(t90.clk90, 0) AS clk90,
    lc.days_since AS days_since_change
  FROM tsig t
  JOIN oob o ON o.campaign_id = t.cid
  LEFT JOIN t90 ON t90.cid = t.cid AND t90.targeting = t.targeting
  LEFT JOIN td ON td.campaign_id = t.cid AND td.target_text = t.targeting
  LEFT JOIN agb ON agb.ad_group_id = td.ad_group_id
  LEFT JOIN lc ON lc.keyword_id = td.keyword_id
  UNION ALL
  SELECT o.campaign_id, o.campaign_name, o.pct_dark, o.budget, o.c_roas1, o.c_roas_prev2,
    t.target_text, t.target_id AS keyword_id, t.ad_group_id, t.match_type,
    FALSE AS is_auto, t.is_pt, TRUE AS is_sb,
    t.bid AS current_bid,
    s.clk1, ROUND(s.sp1,2), s.units1, ROUND(s.roas1,2), s.clk2, ROUND(s.sp2,2), s.units2, ROUND(s.roas_prev2,2),
    (COALESCE(s.roas1, 0) >= 1.0 OR COALESCE(s.roas_prev2, 0) >= 1.0) AS converting,
    COALESCE(s90.clk90, 0),
    lc.days_since
  FROM sb_tgt t
  JOIN oob_sb o ON o.campaign_id = t.cid
  JOIN sb_tsig s ON s.target_id = t.target_id
  LEFT JOIN sb_t90 s90 ON s90.target_id = t.target_id
  LEFT JOIN lc ON lc.keyword_id = t.target_id
),
-- affordable CPC per campaign (Ori 2026-07-30: "TRIM floor should not stop at $1.00") —
-- budget ÷ (targets × 4-click goal), floored at bid_min. Self-scaling: a $10/17-target campaign
-- trims toward $0.20; a $70/10-target campaign has aff ≈ $1.75 and its bids are left alone.
baseN AS (
  SELECT b.*, ROUND(GREATEST(SAFE_DIVIDE(b.budget, COUNT(*) OVER (PARTITION BY b.campaign_id) * 4), 0.20), 2) AS aff_cpc
  FROM base b
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
  ROUND(COALESCE(IF(b.is_auto OR b.is_pt, NULL, SAFE_DIVIDE(ly.sp, ly.clk)), bd.cpc_target), 2) AS target_cpc,
  CASE WHEN NOT (b.is_auto OR b.is_pt) AND ly.kw IS NOT NULL THEN 'LY'
       WHEN bd.cpc_target IS NOT NULL THEN 'BAND' END AS target_cpc_source,
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
    -- budget-constrained probing (Ori 2026-07-30): every campaign in this phase is CAPPED, so
    -- under-clicking is a budget artifact — never probe up. Park the tested, trim the eaters.
    WHEN b.clk90 >= x.tested_clk AND b.current_bid > x.bid_park + 0.05
      THEN x.bid_park
    WHEN b.current_bid > COALESCE(b.aff_cpc, x.big_bid) + 0.05 AND (b.clk1 + b.clk2) > 0
      THEN ROUND(GREATEST(b.current_bid * x.bid_big_trim, COALESCE(b.aff_cpc, x.bid_min)), 2)
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
    WHEN b.clk90 >= x.tested_clk AND b.current_bid > x.bid_park + 0.05 THEN 'PARK'
    WHEN b.current_bid > COALESCE(b.aff_cpc, x.big_bid) + 0.05 AND (b.clk1 + b.clk2) > 0 THEN 'TRIM_BID'
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
    WHEN b.clk90 >= x.tested_clk AND b.current_bid > x.bid_park + 0.05
      THEN CONCAT('tested ', CAST(b.clk90 AS STRING), ' clicks/90d, no sale — park at $0.25 so the untested keywords get their probe')
    WHEN b.current_bid > COALESCE(b.aff_cpc, x.big_bid) + 0.05 AND (b.clk1 + b.clk2) > 0
      THEN CONCAT('bid eats the capped budget — trim 15%/day toward the affordable CPC $',
                  CAST(b.aff_cpc AS STRING), ' (= budget ÷ targets × 4-click goal)')
    WHEN b.clk1 >= x.click_cap_day THEN '6+ clicks yesterday, not converting — slow −5%: cheaper clicks stretch the budget across the day'
    ELSE 'under-clicked because the BUDGET dies, not the bid — held; parking/trimming the eaters frees its probe'
  END AS bid_reason
FROM baseN b CROSS JOIN k x
LEFT JOIN ly ON ly.kw = LOWER(TRIM(b.target_text))
LEFT JOIN camp_parent cp ON cp.cid = b.campaign_id
-- PT/auto match normalization (backtest 2026-07-30): V_TARGET_DAILY says TARGETING_EXPRESSION for
-- asin targets but the band table says PRODUCT — without this map every PT target got NULL target_cpc
LEFT JOIN band bd ON bd.parent_name = cp.parent_name
  AND bd.match_type = CASE WHEN b.is_pt THEN 'PRODUCT' WHEN b.is_auto THEN 'AUTO'
                           WHEN UPPER(COALESCE(b.match_type,'')) IN ('TARGETING_EXPRESSION','ASIN','ASIN EXPANDED') THEN 'PRODUCT'
                           ELSE UPPER(COALESCE(b.match_type, '')) END
WHERE b.clk1 > 0 OR b.clk2 > 0;
