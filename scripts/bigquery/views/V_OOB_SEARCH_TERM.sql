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
CREATE OR REPLACE VIEW `onyga-482313.OI.V_OOB_SEARCH_TERM` AS
WITH wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
            FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
-- Population (Ori 2026-08-01, negates layer in Portfolio 80/20): dark campaigns (engine='OOB')
-- UNION healthy working campaigns from the lift engine (engine='LIFT') — the same two-window
-- negate doctrine applies to both; each panel filters its own engine.
oob AS (
  SELECT campaign_id, 'OOB' AS engine FROM `onyga-482313.OI.V_OOB_BUDGET_PHASE`
  WHERE channel = 'SP' AND pct_dark > 10
  UNION DISTINCT
  SELECT DISTINCT l.campaign_id, 'LIFT' FROM `onyga-482313.OI.V_KEYWORD_LIFT` l
  WHERE l.channel = 'SP' AND l.campaign_id NOT IN (
    SELECT campaign_id FROM `onyga-482313.OI.V_OOB_BUDGET_PHASE` WHERE pct_dark > 10)
),
-- SB arm (v2.1): dark SB campaigns' keyword-targeted search terms from sb_search_term_report.
-- kind='SB' behaves like MANUAL for the negate rule (SB keywords are all manual match types);
-- product-targeted SB rows live in sb_target_report where the "term" is the ASIN — excluded, like PT.
oob_sb AS (
  SELECT campaign_id, 'OOB' AS engine FROM `onyga-482313.OI.V_OOB_BUDGET_PHASE`
  WHERE channel = 'SB' AND pct_dark > 10
  UNION DISTINCT
  SELECT DISTINCT l.campaign_id, 'LIFT' FROM `onyga-482313.OI.V_KEYWORD_LIFT` l
  WHERE l.channel = 'SB' AND l.campaign_id NOT IN (
    SELECT campaign_id FROM `onyga-482313.OI.V_OOB_BUDGET_PHASE` WHERE pct_dark > 10)
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
    SUM(IF(r.report_date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 27 DAY), r.clicks, 0)) AS clicks,
    SUM(IF(r.report_date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 27 DAY), r.attributed_conversions_14_d, 0)) AS orders,
    SUM(IF(r.report_date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 27 DAY), r.cost, 0)) AS spend,
    SUM(IF(r.report_date = (SELECT d FROM wm_sb), r.cost, 0)) AS spend_1d,
    SUM(IF(r.report_date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 27 DAY), r.attributed_sales_14_d, 0)) AS sales,
    -- gross ROAS only for SB terms at the 28d slice (negate rule keys on clicks/orders);
    -- 90d gp ESTIMATED via the campaign cost ratio — feeds the term-winner net-ROAS bar (v15)
    CAST(NULL AS FLOAT64) AS gp,
    SUM(r.attributed_sales_14_d * (1 - COALESCE(pr.cost_ratio, 0))) AS gp_90d,
    SUM(r.clicks) AS clicks_90d, SUM(r.attributed_conversions_14_d) AS orders_90d, SUM(r.cost) AS spend_90d,
    STRING_AGG(DISTINCT CAST(r.ad_group_id AS STRING), ',') AS ad_group_ids
  FROM `fivetran-hl.amazon_ads.sb_search_term_report` r
  JOIN oob_sb o ON o.campaign_id = CAST(r.campaign_id AS STRING)
  LEFT JOIN prod pr ON pr.cid = CAST(r.campaign_id AS STRING)
  LEFT JOIN sb_kw k ON k.id = r.keyword_id
  WHERE r.query_term IS NOT NULL AND r.query_term != ''
    AND r.report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 89 DAY) AND (SELECT d FROM wm_sb)
  GROUP BY 1, 2, 3, 4, 5
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
      AND date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 89 DAY) AND (SELECT d FROM wm)
    UNION ALL
    SELECT LOWER(TRIM(query_term)), clicks, attributed_conversions_14_d
    FROM `fivetran-hl.amazon_ads.sb_search_term_report`
    WHERE query_term IS NOT NULL AND query_term != ''
      AND report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 89 DAY) AND (SELECT d FROM wm_sb)
  ) GROUP BY 1
),
st AS (
  SELECT CAST(a.campaign_id AS STRING) AS campaign_id,
    CAST(a.keyword_id AS STRING) AS keyword_id,
    a.targeting AS target_text, a.SEARCH_TERM AS search_term,
    CASE WHEN LOWER(a.targeting) IN ('close-match','loose-match','substitutes','complements') THEN 'AUTO'
         WHEN LOWER(a.targeting) LIKE 'asin%' THEN 'PT'
         ELSE 'MANUAL' END AS kind,
    SUM(IF(a.date >= DATE_SUB((SELECT d FROM wm), INTERVAL 27 DAY), a.Ads_clicks, 0)) AS clicks,
    SUM(IF(a.date >= DATE_SUB((SELECT d FROM wm), INTERVAL 27 DAY), a.Ads_orders, 0)) AS orders,
    SUM(IF(a.date >= DATE_SUB((SELECT d FROM wm), INTERVAL 27 DAY), a.Ads_cost, 0)) AS spend,
    SUM(IF(a.date = (SELECT d FROM wm), a.Ads_cost, 0)) AS spend_1d,
    SUM(IF(a.date >= DATE_SUB((SELECT d FROM wm), INTERVAL 27 DAY), a.Ads_sales, 0)) AS sales,
    SUM(IF(a.date >= DATE_SUB((SELECT d FROM wm), INTERVAL 27 DAY), a.GROSS_PROFIT, 0)) AS gp,
    SUM(a.GROSS_PROFIT) AS gp_90d,
    SUM(a.Ads_clicks) AS clicks_90d, SUM(a.Ads_orders) AS orders_90d, SUM(a.Ads_cost) AS spend_90d,
    -- the ad groups where this term actually ran under this keyword — SB negatives REQUIRE an
    -- Ad Group Id (Amazon rejects campaign-level SB negatives: upload report 29, 9 rows)
    STRING_AGG(DISTINCT CAST(a.ad_group_id AS STRING), ',') AS ad_group_ids
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN oob o ON o.campaign_id = CAST(a.campaign_id AS STRING)
  WHERE a.SEARCH_TERM IS NOT NULL AND a.SEARCH_TERM != ''
    AND a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 89 DAY) AND (SELECT d FROM wm)
  GROUP BY 1, 2, 3, 4, 5
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
            ELSE u.clicks >= 15 AND u.orders = 0 END) AS is_negate
FROM (SELECT * FROM st UNION ALL SELECT * FROM sb_st) u
LEFT JOIN oob e ON e.campaign_id = u.campaign_id
LEFT JOIN oob_sb e2 ON e2.campaign_id = u.campaign_id
LEFT JOIN term_all ta ON ta.term = LOWER(TRIM(u.search_term))
LEFT JOIN sqp_win sq ON sq.q = LOWER(TRIM(u.search_term))
LEFT JOIN camp_age ca ON ca.campaign_id = u.campaign_id
LEFT JOIN research rsr ON rsr.campaign_id = CAST(u.campaign_id AS STRING)
LEFT JOIN kw_texts kt ON kt.campaign_id = CAST(u.campaign_id AS STRING) AND kt.txt = LOWER(TRIM(u.search_term))
-- already negated via OI (upload report 31: "NegativeKeyword already exists") — the Fivetran
-- negatives sync is frozen, so the CHANGE LOG is how we see our own applied negates; a logged
-- NEGATE_TERM permanently retires the suggestion (negatives are forever).
LEFT JOIN (SELECT DISTINCT CAST(campaign_id AS STRING) cid, LOWER(TRIM(search_term)) term
           FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` WHERE action = 'NEGATE_TERM') ng
  ON ng.cid = CAST(u.campaign_id AS STRING) AND ng.term = LOWER(TRIM(u.search_term))
WHERE u.clicks_90d > 0
  AND u.campaign_id NOT IN (SELECT campaign_id FROM defense);
