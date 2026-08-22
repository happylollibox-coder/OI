-- V_OOB_SEARCH_TERM — search-term layer of the Out-of-budget phase. Spec: architecture/OOB_BUDGET_PHASE.md §v2.
--
-- One row per (OOB campaign, target, search term), measured over TWO windows (Ori 2026-07-30:
-- "in order to negate general big words need to check 3 month data; small volume words 28 days
-- are enough"):
--   BIG general word  = >= 30 clicks over 90 complete days ACCOUNT-WIDE (all campaigns, SP+SB —
--     per-slice volume fragments a big word into "small" pieces; caught by Ori 2026-07-30 on
--     "teen girl gifts trendy stuff": 13 clicks in one keyword slice but 693 clicks / 6 orders
--     across 24 campaigns) → negate only if 0 orders over the FULL 90d ACCOUNT-WIDE.
--   SMALL word        = < 30 account-wide clicks/90d → negate at >= 10 clicks AND 0 orders over
--     28d at the (campaign, keyword) slice.
-- Plus the structural rules:
--   MANUAL keywords: term != keyword (normalized). A term that IS the keyword is what you bid on.
--   AUTO clauses: no term!=keyword test — every auto term differs by construction; the 0-order
--     gate does the work so harvesting isn't killed.
--   PT (product targets): EXCLUDED — the "term" is the targeted ASIN; negating it = pausing the
--     target, which is a bid/state decision, not a negative keyword.
-- Winners (orders in 90d) are surfaced and never negated.
-- v27.74 (Task 4.7): every trailing multi-day ads window (28d slice, 90d slice + account-wide) ends at wm-1 (complete days); spend_1d (day wm) unchanged.
-- v27.100: A BLOCK IS JUDGED AT THE GRAIN A NEGATIVE KEYWORD ACTS ON. An Amazon negative keyword is
--   attached to the AD GROUP: the moment it lands the search term is dead for every product and
--   every targeting keyword in that group. This view was deciding blocks off ONE keyword's slice of
--   a term, so a slice could put a term on the permanent block list while the rest of the ad group
--   was being paid by it. Every input the block rule reads is now summed across every keyword and
--   every product in the ad group first (bg / bg_lt below), and a block may never fall on a term the
--   ad group is net-positive on over the judging window, over 90 days, or over its whole life there,
--   nor on a term the ad group already sold in that window, nor on one the shop sells organically
--   under any product the group advertises. Same money test, same columns and the same three
--   windows as the coacher's block evidence (V_ADS_COACH_DATA 'negate_grain') — one definition of
--   "is this term losing money", never two. The roll-up is a GUARD here and not the trigger; the
--   comment on is_negate says why, and what it measured.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_OOB_SEARCH_TERM` AS
WITH wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
            FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
-- Population (Ori 2026-08-01, negates layer in Portfolio 80/20): OOB-owned campaigns
-- (engine='OOB') UNION healthy working campaigns from the lift engine (engine='LIFT') — the same
-- two-window negate doctrine applies to both; each panel filters its own engine.
-- v27.46: routing reads V_CAMPAIGN_CAP_STATE.is_oob_owned — the single membership function both
-- bid engines already use (v27.45) — replacing the old anchor-day pct_dark > 10 test, so the
-- panel a campaign's terms appear under matches bid ownership (silent caps included).
oob AS (
  SELECT campaign_id, 'OOB' AS engine FROM `onyga-482313.OI.V_CAMPAIGN_CAP_STATE`
  WHERE channel = 'SP' AND is_oob_owned
  UNION DISTINCT
  SELECT DISTINCT l.campaign_id, 'LIFT' FROM `onyga-482313.OI.V_KEYWORD_LIFT` l
  WHERE l.channel = 'SP' AND l.campaign_id NOT IN (
    SELECT campaign_id FROM `onyga-482313.OI.V_CAMPAIGN_CAP_STATE` WHERE is_oob_owned)
),
-- SB arm (v2.1): OOB-owned SB campaigns' keyword-targeted search terms from sb_search_term_report.
-- kind='SB' behaves like MANUAL for the negate rule (SB keywords are all manual match types);
-- product-targeted SB rows live in sb_target_report where the "term" is the ASIN — excluded, like PT.
oob_sb AS (
  SELECT campaign_id, 'OOB' AS engine FROM `onyga-482313.OI.V_CAMPAIGN_CAP_STATE`
  WHERE channel = 'SB' AND is_oob_owned
  UNION DISTINCT
  SELECT DISTINCT l.campaign_id, 'LIFT' FROM `onyga-482313.OI.V_KEYWORD_LIFT` l
  WHERE l.channel = 'SB' AND l.campaign_id NOT IN (
    SELECT campaign_id FROM `onyga-482313.OI.V_CAMPAIGN_CAP_STATE` WHERE is_oob_owned)
),
wm_sb AS (SELECT LEAST(MAX(report_date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
          FROM `fivetran-hl.amazon_ads.sb_campaign_report`),
-- SQP market view per query (Ori 2026-08-01 negate redesign): BIG word = the MARKET buys it —
-- > 1,000 total purchases on Amazon in the last 90 days per SQP, AND SQP has >= 90 days of
-- history on the term. A term in SQP with less history = WAIT (no negate of either kind until
-- the market data matures). Terms Amazon never shows us in SQP take the small-word bar.
sqp_mw AS (SELECT MAX(week_start_date) mw FROM `onyga-482313.OI.FACT_SEARCH_QUERY`),
sqp AS (
  SELECT LOWER(query_text) q, MIN(week_start_date) first_w
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` GROUP BY 1
),
sqp_win AS (
  SELECT s.q,
    s.first_w <= DATE_SUB((SELECT mw FROM sqp_mw), INTERVAL 84 DAY) AS has_90d,
    COALESCE(w.p90, 0) AS market_purchases_90d
  FROM sqp s
  LEFT JOIN (
    SELECT q, SUM(p) p90 FROM (
      SELECT LOWER(query_text) q, week_start_date, MAX(TOTAL_PURCHASES) p
      FROM `onyga-482313.OI.FACT_SEARCH_QUERY`
      WHERE week_start_date > (SELECT DATE_SUB(mw, INTERVAL 91 DAY) FROM sqp_mw)
      GROUP BY 1, 2
    ) GROUP BY q
  ) w ON w.q = s.q
),
-- NEVER negate inside defense campaigns (Ori doctrine: negate brand terms everywhere EXCEPT
-- defense — brand traffic is the point of the moat). Defense is its own page section.
defense AS (
  SELECT campaign_id FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT`
  WHERE LOWER(campaign_name) LIKE '%brand defense%'
),
-- RESEARCH MODE (Ori 2026-08-02): Hunter/Discovery campaigns harvest terms — a winning term
-- with no keyword of its own becomes an ADD_KEYWORD (broad) suggestion
research AS (
  SELECT CAST(campaign_id AS STRING) campaign_id FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT`
  WHERE REGEXP_CONTAINS(LOWER(campaign_name), r'hunter|discovery|research')
),
kw_texts AS (
  SELECT CAST(campaign_id AS STRING) campaign_id, LOWER(TRIM(keyword_text)) txt
  FROM `onyga-482313.OI.DIM_KEYWORD` WHERE is_current AND UPPER(state) = 'ENABLED' GROUP BY 1, 2
  UNION DISTINCT
  SELECT CAST(campaign_id AS STRING), LOWER(TRIM(keyword_text))
  FROM `fivetran-hl.amazon_ads.sb_keyword` WHERE NOT _fivetran_deleted AND state = 'enabled' GROUP BY 1, 2
),
sb_kw AS (
  SELECT id, keyword_text FROM `fivetran-hl.amazon_ads.sb_keyword` WHERE NOT _fivetran_deleted
),
-- est. COGS ratio per campaign via its mapped ASIN — for the SB term-winner net-ROAS bar (v15)
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
sb_st AS (
  SELECT CAST(r.campaign_id AS STRING) AS campaign_id,
    CAST(r.keyword_id AS STRING) AS keyword_id,
    COALESCE(k.keyword_text, CAST(r.keyword_id AS STRING)) AS target_text,
    r.query_term AS search_term, 'SB' AS kind,
    -- v27.74: complete days (Task 4.7) — 28d ends wm-1
    SUM(IF(r.report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 28 DAY) AND DATE_SUB((SELECT d FROM wm_sb), INTERVAL 1 DAY), r.clicks, 0)) AS clicks,
    SUM(IF(r.report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 28 DAY) AND DATE_SUB((SELECT d FROM wm_sb), INTERVAL 1 DAY), r.attributed_conversions_14_d, 0)) AS orders,
    SUM(IF(r.report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 28 DAY) AND DATE_SUB((SELECT d FROM wm_sb), INTERVAL 1 DAY), r.cost, 0)) AS spend,
    SUM(IF(r.report_date = (SELECT d FROM wm_sb), r.cost, 0)) AS spend_1d,
    SUM(IF(r.report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 28 DAY) AND DATE_SUB((SELECT d FROM wm_sb), INTERVAL 1 DAY), r.attributed_sales_14_d, 0)) AS sales,
    -- gross ROAS only for SB terms at the 28d slice (negate rule keys on clicks/orders);
    -- 90d gp ESTIMATED via the campaign cost ratio — feeds the term-winner net-ROAS bar (v15)
    CAST(NULL AS FLOAT64) AS gp,
    -- v27.74: complete days (Task 4.7) — 90d sums end wm-1 (WHERE spans wm-90..wm; day wm kept only for spend_1d)
    SUM(IF(r.report_date < (SELECT d FROM wm_sb), r.attributed_sales_14_d * (1 - COALESCE(pr.cost_ratio, 0)), 0)) AS gp_90d,
    SUM(IF(r.report_date < (SELECT d FROM wm_sb), r.clicks, 0)) AS clicks_90d,
    SUM(IF(r.report_date < (SELECT d FROM wm_sb), r.attributed_conversions_14_d, 0)) AS orders_90d,
    SUM(IF(r.report_date < (SELECT d FROM wm_sb), r.cost, 0)) AS spend_90d,
    -- v27.100: the ad group is now a GROUPING key, not an aggregate. A (campaign, keyword, term)
    -- slice sits in exactly one ad group, so this changes no value and no row count — it gives
    -- every row a concrete ad group to carry its block evidence, and it is what lets a term
    -- running in several ad groups be judged, and blocked, in each of them.
    CAST(r.ad_group_id AS STRING) AS ad_group_ids
  FROM `fivetran-hl.amazon_ads.sb_search_term_report` r
  JOIN oob_sb o ON o.campaign_id = CAST(r.campaign_id AS STRING)
  LEFT JOIN prod pr ON pr.cid = CAST(r.campaign_id AS STRING)
  LEFT JOIN sb_kw k ON k.id = r.keyword_id
  WHERE r.query_term IS NOT NULL AND r.query_term != ''
    -- v27.74: complete days (Task 4.7) — 90d = wm-90..wm-1; upper bound wm feeds only spend_1d
    AND r.report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 90 DAY) AND (SELECT d FROM wm_sb)
  GROUP BY 1, 2, 3, 4, 5, ad_group_ids
),
-- account-wide 90d volume + orders per TERM (all campaigns, both channels) — the "is it a big
-- general word" test and the big-word order protection both run on THIS, never on the slice.
-- campaign age (Ori 2026-07-30: a 2-week-old campaign hasn't given a big word its own trial —
-- "only after real 90 days with at least 25 clicks I will consider")
camp_age AS (
  SELECT campaign_id, MIN(first_d) AS first_d FROM (
    SELECT CAST(campaign_id AS STRING) campaign_id, MIN(date) first_d
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` GROUP BY 1
    UNION ALL
    SELECT CAST(campaign_id AS STRING), MIN(report_date)
    FROM `fivetran-hl.amazon_ads.sb_campaign_report` GROUP BY 1
  ) GROUP BY 1
),
term_all AS (
  SELECT term, SUM(clk) AS term_clicks_90d, SUM(ord) AS term_orders_90d FROM (
    SELECT LOWER(TRIM(SEARCH_TERM)) AS term, Ads_clicks AS clk, Ads_orders AS ord
    FROM `onyga-482313.OI.FACT_AMAZON_ADS`
    WHERE SEARCH_TERM IS NOT NULL AND SEARCH_TERM != ''
      -- v27.74: complete days (Task 4.7) — ends wm-1
      AND date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 90 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY)
    UNION ALL
    SELECT LOWER(TRIM(query_term)), clicks, attributed_conversions_14_d
    FROM `fivetran-hl.amazon_ads.sb_search_term_report`
    WHERE query_term IS NOT NULL AND query_term != ''
      -- v27.74: complete days (Task 4.7) — ends wm-1
      AND report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 90 DAY) AND DATE_SUB((SELECT d FROM wm_sb), INTERVAL 1 DAY)
  ) GROUP BY 1
),
st AS (
  SELECT CAST(a.campaign_id AS STRING) AS campaign_id,
    CAST(a.keyword_id AS STRING) AS keyword_id,
    a.targeting AS target_text, a.SEARCH_TERM AS search_term,
    CASE WHEN LOWER(a.targeting) IN ('close-match','loose-match','substitutes','complements') THEN 'AUTO'
         WHEN LOWER(a.targeting) LIKE 'asin%' THEN 'PT'
         ELSE 'MANUAL' END AS kind,
    -- v27.74: complete days (Task 4.7) — 28d ends wm-1
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 28 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_clicks, 0)) AS clicks,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 28 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_orders, 0)) AS orders,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 28 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_cost, 0)) AS spend,
    SUM(IF(a.date = (SELECT d FROM wm), a.Ads_cost, 0)) AS spend_1d,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 28 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_sales, 0)) AS sales,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 28 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.GROSS_PROFIT, 0)) AS gp,
    -- v27.74: complete days (Task 4.7) — 90d sums end wm-1 (WHERE spans wm-90..wm; day wm kept only for spend_1d)
    SUM(IF(a.date < (SELECT d FROM wm), a.GROSS_PROFIT, 0)) AS gp_90d,
    SUM(IF(a.date < (SELECT d FROM wm), a.Ads_clicks, 0)) AS clicks_90d,
    SUM(IF(a.date < (SELECT d FROM wm), a.Ads_orders, 0)) AS orders_90d,
    SUM(IF(a.date < (SELECT d FROM wm), a.Ads_cost, 0)) AS spend_90d,
    -- the ad groups where this term actually ran under this keyword — SB negatives REQUIRE an
    -- Ad Group Id (Amazon rejects campaign-level SB negatives: upload report 29, 9 rows)
    -- v27.100: grouping key, not an aggregate — see the sb_st note above.
    CAST(a.ad_group_id AS STRING) AS ad_group_ids
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN oob o ON o.campaign_id = CAST(a.campaign_id AS STRING)
  WHERE a.SEARCH_TERM IS NOT NULL AND a.SEARCH_TERM != ''
    -- v27.74: complete days (Task 4.7) — 90d = wm-90..wm-1; upper bound wm feeds only spend_1d
    AND a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 90 DAY) AND (SELECT d FROM wm)
  GROUP BY 1, 2, 3, 4, 5, ad_group_ids
),

-- ══════════════════════════════════════════════════════════════════════════════════════════
-- BLOCK GRAIN — WHAT A NEGATIVE KEYWORD ACTUALLY SWITCHES OFF.
--
-- Everything above this point is sliced by the keyword being bid on. A negative keyword is not.
-- It is attached to the AD GROUP, and the moment it lands the search term is dead for every
-- product and every keyword inside that group. Deciding to block a term off one keyword's slice
-- therefore throws away whatever the other slices of the same term were earning from it — and a
-- block is permanent, so there is no cheap way back.
--
-- So the evidence a block is judged on is summed across keyword and product FIRST, at
-- campaign x ad group x search term, over the same two windows the negate rule already states
-- (28 complete days, 90 complete days), and over the term's whole life in that ad group. This is
-- the same layer, the same shape and the same guards as the coacher's block evidence
-- (V_ADS_COACH_DATA 'negate_grain'); two different definitions of "is this term losing money" is
-- how this class of defect survives.
-- ══════════════════════════════════════════════════════════════════════════════════════════
-- Organic purchases per (search, product) — the "it sells anyway" guard's raw material. Summed
-- across every product the ad group advertises below, because the negative hits all of them.
sqp_asin AS (
  SELECT LOWER(query_text) AS q, ASIN AS asin, SUM(conversions) AS organic_orders
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY`
  WHERE data_source = 'SQP'
    AND week_start_date >= DATE_SUB((SELECT mw FROM sqp_mw), INTERVAL 56 DAY)
  GROUP BY 1, 2
),
-- One row per (campaign, ad group, search term, product) so the organic guard can be joined per
-- product before the ad-group roll-up. SP from FACT_AMAZON_ADS; SB from the brand search-term
-- report, whose gross profit is estimated with the campaign's own cost ratio exactly as sb_st
-- does (SB rows carry no product, so they take no organic guard — stated, not hidden).
bg_slice AS (
  SELECT
    CAST(a.campaign_id AS STRING) AS campaign_id,
    CAST(a.ad_group_id AS STRING) AS ad_group_id,
    LOWER(TRIM(a.SEARCH_TERM)) AS term,
    COALESCE(a.most_advertised_asin_impressions, a.ASIN_BY_CAMPAIGN_NAME) AS asin,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 28 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_clicks, 0)) AS clicks_28d,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 28 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_orders, 0)) AS orders_28d,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 28 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_cost, 0)) AS spend_28d,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 28 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.GROSS_PROFIT - a.Ads_cost, 0)) AS net_28d,
    SUM(IF(a.date < (SELECT d FROM wm), a.Ads_clicks, 0)) AS clicks_90d,
    SUM(IF(a.date < (SELECT d FROM wm), a.Ads_orders, 0)) AS orders_90d,
    SUM(IF(a.date < (SELECT d FROM wm), a.Ads_cost, 0)) AS spend_90d,
    SUM(IF(a.date < (SELECT d FROM wm), a.GROSS_PROFIT - a.Ads_cost, 0)) AS net_90d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  WHERE a.SEARCH_TERM IS NOT NULL AND a.SEARCH_TERM != '' AND a.ad_group_id IS NOT NULL
    AND a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 90 DAY) AND (SELECT d FROM wm)
  GROUP BY 1, 2, 3, 4
  UNION ALL
  SELECT
    CAST(r.campaign_id AS STRING), CAST(r.ad_group_id AS STRING), LOWER(TRIM(r.query_term)),
    CAST(NULL AS STRING),
    SUM(IF(r.report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 28 DAY) AND DATE_SUB((SELECT d FROM wm_sb), INTERVAL 1 DAY), r.clicks, 0)),
    SUM(IF(r.report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 28 DAY) AND DATE_SUB((SELECT d FROM wm_sb), INTERVAL 1 DAY), r.attributed_conversions_14_d, 0)),
    SUM(IF(r.report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 28 DAY) AND DATE_SUB((SELECT d FROM wm_sb), INTERVAL 1 DAY), r.cost, 0)),
    SUM(IF(r.report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 28 DAY) AND DATE_SUB((SELECT d FROM wm_sb), INTERVAL 1 DAY), r.attributed_sales_14_d * (1 - COALESCE(pr.cost_ratio, 0)) - r.cost, 0)),
    SUM(IF(r.report_date < (SELECT d FROM wm_sb), r.clicks, 0)),
    SUM(IF(r.report_date < (SELECT d FROM wm_sb), r.attributed_conversions_14_d, 0)),
    SUM(IF(r.report_date < (SELECT d FROM wm_sb), r.cost, 0)),
    SUM(IF(r.report_date < (SELECT d FROM wm_sb), r.attributed_sales_14_d * (1 - COALESCE(pr.cost_ratio, 0)) - r.cost, 0))
  FROM `fivetran-hl.amazon_ads.sb_search_term_report` r
  LEFT JOIN prod pr ON pr.cid = CAST(r.campaign_id AS STRING)
  WHERE r.query_term IS NOT NULL AND r.query_term != '' AND r.ad_group_id IS NOT NULL
    AND r.report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 90 DAY) AND (SELECT d FROM wm_sb)
  GROUP BY 1, 2, 3, 4
),
bg AS (
  SELECT
    s.campaign_id, s.ad_group_id, s.term,
    SUM(s.clicks_28d) AS bg_clicks_28d,
    SUM(s.orders_28d) AS bg_orders_28d,
    SUM(s.spend_28d)  AS bg_spend_28d,
    SUM(s.net_28d)    AS bg_net_28d,
    SUM(s.clicks_90d) AS bg_clicks_90d,
    SUM(s.orders_90d) AS bg_orders_90d,
    SUM(s.spend_90d)  AS bg_spend_90d,
    SUM(s.net_90d)    AS bg_net_90d,
    -- organic purchases on this search across EVERY product the ad group advertises. The block
    -- rule had no organic guard at all; the coacher's looked at one product only. A term the
    -- shop sells organically is not waste, whichever product it sells.
    SUM(COALESCE(sq.organic_orders, 0)) AS bg_sqp_orders
  FROM bg_slice s
  LEFT JOIN sqp_asin sq ON sq.q = s.term AND sq.asin = s.asin
  GROUP BY 1, 2, 3
),
-- The all-time record at the same grain. A block is permanent, so it may never fall on a term
-- that has PAID this ad group over its whole life here: a term that earned its keep and is
-- having a bad month is a bid or a season problem, not a term to blacklist for good.
bg_lt AS (
  SELECT campaign_id, ad_group_id, term,
         SUM(clicks) AS bg_lt_clicks, SUM(orders) AS bg_lt_orders,
         SUM(spend)  AS bg_lt_spend,  SUM(net)    AS bg_lt_net
  FROM (
    SELECT CAST(campaign_id AS STRING) AS campaign_id, CAST(ad_group_id AS STRING) AS ad_group_id,
           LOWER(TRIM(SEARCH_TERM)) AS term, Ads_clicks AS clicks, Ads_orders AS orders,
           Ads_cost AS spend, GROSS_PROFIT - Ads_cost AS net
    FROM `onyga-482313.OI.FACT_AMAZON_ADS`
    WHERE SEARCH_TERM IS NOT NULL AND SEARCH_TERM != '' AND ad_group_id IS NOT NULL
    UNION ALL
    SELECT CAST(r.campaign_id AS STRING), CAST(r.ad_group_id AS STRING), LOWER(TRIM(r.query_term)),
           r.clicks, r.attributed_conversions_14_d, r.cost,
           r.attributed_sales_14_d * (1 - COALESCE(pr.cost_ratio, 0)) - r.cost
    FROM `fivetran-hl.amazon_ads.sb_search_term_report` r
    LEFT JOIN prod pr ON pr.cid = CAST(r.campaign_id AS STRING)
    WHERE r.query_term IS NOT NULL AND r.query_term != '' AND r.ad_group_id IS NOT NULL
  )
  GROUP BY 1, 2, 3
)
SELECT u.campaign_id, COALESCE(e.engine, e2.engine) AS engine, u.keyword_id, u.target_text, u.search_term, u.kind,
  u.clicks, u.orders, ROUND(u.spend, 2) AS spend, ROUND(u.spend_1d, 2) AS spend_1d, ROUND(u.sales, 2) AS sales,
  ROUND(SAFE_DIVIDE(u.gp, NULLIF(u.spend, 0)), 2) AS net_roas,
  u.clicks_90d, u.orders_90d, ROUND(u.spend_90d, 2) AS spend_90d, u.ad_group_ids,
  COALESCE(ta.term_clicks_90d, 0) AS term_clicks_90d,
  COALESCE(ta.term_orders_90d, 0) AS term_orders_90d,
  -- BIG word (Ori 2026-08-01): the MARKET buys it — >1,000 Amazon purchases in 90d per SQP,
  -- with >= 90 days of SQP history on the term
  (sq.q IS NOT NULL AND sq.has_90d AND sq.market_purchases_90d > 1000) AS is_big,
  (sq.q IS NOT NULL AND NOT sq.has_90d) AS sqp_wait,
  COALESCE(sq.market_purchases_90d, 0) AS market_purchases_90d,
  (LOWER(TRIM(u.search_term)) = LOWER(TRIM(u.target_text))) AS term_is_keyword,
  -- v15 (Ori 2026-08-02): a winning term must EARN it — >= 1.1x net ROAS at this slice over
  -- 90d (same bar as the keyword WINNER class), not merely an order somewhere
  (COALESCE(SAFE_DIVIDE(u.gp_90d, NULLIF(u.spend_90d, 0)), 0) >= 1.1) AS is_winner,
  ROUND(SAFE_DIVIDE(u.gp_90d, NULLIF(u.spend_90d, 0)), 2) AS net_roas_90d,
  -- research mode: winner term lacking its own enabled keyword -> suggest ADD as broad
  (rsr.campaign_id IS NOT NULL
   AND COALESCE(SAFE_DIVIDE(u.gp_90d, NULLIF(u.spend_90d, 0)), 0) >= 1.1
   AND NOT (LOWER(TRIM(u.search_term)) = LOWER(TRIM(u.target_text)))
   AND kt.txt IS NULL
   AND NOT REGEXP_CONTAINS(u.search_term, r'^b0[a-z0-9]{8}$')) AS is_add_candidate,
  -- ── the block-grain evidence this row is judged on, published so a reason can quote it ──
  COALESCE(bg.bg_clicks_28d, 0) AS block_clicks_28d,
  COALESCE(bg.bg_orders_28d, 0) AS block_orders_28d,
  ROUND(COALESCE(bg.bg_spend_28d, 0), 2) AS block_spend_28d,
  ROUND(COALESCE(bg.bg_net_28d, 0), 2)   AS block_net_28d,
  COALESCE(bg.bg_clicks_90d, 0) AS block_clicks_90d,
  COALESCE(bg.bg_orders_90d, 0) AS block_orders_90d,
  ROUND(COALESCE(bg.bg_net_90d, 0), 2)   AS block_net_90d,
  COALESCE(bgl.bg_lt_clicks, 0) AS block_lifetime_clicks,
  COALESCE(bgl.bg_lt_orders, 0) AS block_lifetime_orders,
  ROUND(COALESCE(bgl.bg_lt_net, 0), 2)   AS block_lifetime_net,
  GREATEST(0, COALESCE(bg.bg_sqp_orders, 0) - COALESCE(bg.bg_orders_90d, 0)) AS block_organic_orders,
  (u.kind != 'PT'
   AND ng.cid IS NULL
   AND (u.kind = 'AUTO' OR LOWER(TRIM(u.search_term)) != LOWER(TRIM(u.target_text)))
   -- SQP-listed term without 90 days of market history: WAIT — no negate of either kind
   AND NOT (sq.q IS NOT NULL AND NOT sq.has_90d)
   AND CASE WHEN sq.q IS NOT NULL AND sq.has_90d AND sq.market_purchases_90d > 1000
            -- big word (Ori 2026-07-30): a young campaign hasn't given it its own trial — negate
            -- only after REAL 90 days (campaign >= 90d old) AND >= 25 clicks IN THIS campaign,
            -- with zero orders anywhere account-wide
            -- big word: the campaign is >= 90 days old, gave it >= 25 clicks of its OWN trial,
            -- and THIS campaign has no sales on it (Ori 2026-08-01)
            THEN u.orders_90d = 0 AND u.clicks_90d >= 25
                 AND ca.first_d <= DATE_SUB((SELECT d FROM wm), INTERVAL 89 DAY)
            -- small word (everything else): 15 clicks · 0 sales · 28 days at this slice
            ELSE u.clicks >= 15 AND u.orders = 0 END
   -- ══ v27.100: AND THEN IT HAS TO SURVIVE THE GRAIN THE NEGATIVE ACTUALLY ACTS ON ═══════
   -- Everything above is one keyword's share of the term. Everything below is the whole AD
   -- GROUP's record on it — every product, every keyword — because that is what the negative
   -- switches off. These are guards ONLY: each one can withdraw a block, none can create one.
   --
   -- THE ROLL-UP IS DELIBERATELY NOT THE TRIGGER, and this is the one place this differs from
   -- the coacher's fix, which moved trigger and guard together. Same money test, same columns,
   -- same three windows — but moving the 15-click / 25-click bar onto a sum over every keyword
   -- in the ad group does not make a block safer, it makes it EASIER: the bars were calibrated
   -- against a single keyword's trial, and an auto campaign fragments one term across four
   -- clauses in one group. Measured on this account the same day: judging the trigger at ad-group
   -- grain took these two engines from 30 blocked terms to 103. How much trial a term gets before
   -- it is blocked FOREVER is Ori's call, not a side effect of a grain repair, so the trigger
   -- stays where the rule states it and the roll-up only ever takes a block away.
   AND bg.term IS NOT NULL
   -- (1) the ad group must have no order on the term over the window this block is judged on —
   --     a zero-order rule that fires while a sibling keyword in the same group is selling the
   --     term is reading one slice and calling it the group,
   AND CASE WHEN sq.q IS NOT NULL AND sq.has_90d AND sq.market_purchases_90d > 1000
            THEN COALESCE(bg.bg_orders_90d, 0) = 0
            ELSE COALESCE(bg.bg_orders_28d, 0) = 0 END
   -- (2) it must be losing the ad group money over that window,
   AND COALESCE(bg.bg_net_28d, 0) < 0
   -- (3) over 90 days as well — a term paying the group back over the long window is having a
   --     quiet month, and that is a bid or a season question, not a blacklisting,
   AND COALESCE(bg.bg_net_90d, 0) < 0
   -- (4) and over its whole life in that ad group, because the block never comes off by itself.
   --     A term that earned its keep here has to be argued down, not dropped.
   AND COALESCE(bgl.bg_lt_net, 0) < 0
   -- (5) and the shop must not be selling it anyway: organic purchases on this search across
   --     every product the ad group advertises, net of what the ads themselves booked.
   AND GREATEST(0, COALESCE(bg.bg_sqp_orders, 0) - COALESCE(bg.bg_orders_90d, 0)) = 0
  ) AS is_negate
FROM (SELECT * FROM st UNION ALL SELECT * FROM sb_st) u
LEFT JOIN oob e ON e.campaign_id = u.campaign_id
LEFT JOIN oob_sb e2 ON e2.campaign_id = u.campaign_id
LEFT JOIN term_all ta ON ta.term = LOWER(TRIM(u.search_term))
LEFT JOIN sqp_win sq ON sq.q = LOWER(TRIM(u.search_term))
LEFT JOIN camp_age ca ON ca.campaign_id = u.campaign_id
-- block-grain evidence: one row per campaign x ad group x search term, and u is now one row per
-- (campaign, keyword, ad group, term), so this is many-to-one and cannot fan a row out
LEFT JOIN bg ON bg.campaign_id = u.campaign_id AND bg.ad_group_id = u.ad_group_ids
             AND bg.term = LOWER(TRIM(u.search_term))
LEFT JOIN bg_lt bgl ON bgl.campaign_id = u.campaign_id AND bgl.ad_group_id = u.ad_group_ids
             AND bgl.term = LOWER(TRIM(u.search_term))
LEFT JOIN research rsr ON rsr.campaign_id = CAST(u.campaign_id AS STRING)
LEFT JOIN kw_texts kt ON kt.campaign_id = CAST(u.campaign_id AS STRING) AND kt.txt = LOWER(TRIM(u.search_term))
-- already negated via OI (upload report 31: "NegativeKeyword already exists") — the Fivetran
-- negatives sync is frozen, so the CHANGE LOG is how we see our own applied negates; a logged
-- NEGATE_TERM permanently retires the suggestion (negatives are forever).
LEFT JOIN (SELECT DISTINCT CAST(campaign_id AS STRING) cid, LOWER(TRIM(search_term)) term
           FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED` WHERE action = 'NEGATE_TERM') ng
  ON ng.cid = CAST(u.campaign_id AS STRING) AND ng.term = LOWER(TRIM(u.search_term))
WHERE u.clicks_90d > 0
  AND u.campaign_id NOT IN (SELECT campaign_id FROM defense);
