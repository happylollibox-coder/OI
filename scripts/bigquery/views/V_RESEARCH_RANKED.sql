-- =============================================
-- V_RESEARCH_RANKED
-- =============================================
--
-- Purpose: Pre-computes all ranking/FIT scores for every
--          (parent_name × query_text) combination.
--          Single source of truth for Research page scoring
--          (Invariants #8/#9 — frontend formats, never computes).
--
-- Output Columns (scoring):
--   seg_fit          0-100 segment matching score
--   gender_score/age_score/occasion_score/pt_score
--                    per-field seg-fit breakdown (-1 = mismatch pre-cap,
--                    NULL = family not segmented, 0 = term value unknown)
--   est_cps          Market-model clicks/sale: family curve (_ALL season) at the
--                    term's price bucket × the term's market-intent factor.
--                    Independent of our ads — the Est. CPS column shows this.
--   est_cps_curve    raw curve value (pre-adjustment), for tooltips
--   intent_factor    term market CPS ÷ bucket-median market CPS, clamped [0.5, 2]
--   effective_cps    Real ads CPS (1/CVR) when available, else est_cps
--   cps_source       'ads_30d' | 'ads_12m' | 'curve' | NULL
--   cps_fit          0-100 CPS efficiency score
--   price_bucket     matched conversion-curve bucket (A. Cheaper … E. Way above)
--   overall_fit      real-CPS bracket if >3 orders, else seg_fit minus a
--                    price-bucket penalty (C −10, D −20, E −30), floored at 0
--   purchase_rank    0-100 weekly purchases bucket score
--   rank             Final rank = avg(overall_fit, purchase_rank), holiday override
--   ads_purch        Ad units (30d if >3, else 12m)
--   ads_cps          1/CVR (30d if >3 units, else 12m)
--   family_purchases/family_clicks/family_impressions
--                    this family's SQP performance for the term (104w)
--
-- Dependencies:
--   FN_EXTRACT_SEGMENTS, V_SQP_QUERY_WEEKLY, FACT_AMAZON_ADS, FACT_SEARCH_QUERY,
--   FACT_RESEARCH_TERMS (must be refreshed BEFORE this view is materialized —
--   SP_REFRESH_RESEARCH_RANKED does so),
--   DIM_PRODUCT, DIM_COSTS_HISTORY, V_DIM_LISTING_CURRENT, V_CONVERSION_CURVE,
--   DE_SEARCH_TERM_SEGMENTS (manual overrides), DE_PRODUCT_TYPE_KEYWORDS
--
-- Grain: parent_name × query_text (one row per family per search term)
--
-- Materialized into FACT_RESEARCH_RANKED by SP_REFRESH_RESEARCH_RANKED.
-- Invariant #7: Uses ASIN_BY_CAMPAIGN_NAME (ID-based join)
-- SOP: architecture/RESEARCH_PAGE.md
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313`.OI.V_RESEARCH_RANKED AS

WITH

-- ═══ 1. Active families with merged segments ═══
family_segments AS (
  SELECT
    dp.parent_name,
    STRING_AGG(DISTINCT seg_val, ',' ORDER BY seg_val) AS seg_gender,
    STRING_AGG(DISTINCT age_val, ',' ORDER BY age_val) AS seg_age_group,
    STRING_AGG(DISTINCT occ_val, ',' ORDER BY occ_val) AS seg_occasion,
    STRING_AGG(DISTINCT pt_val, ',' ORDER BY pt_val)  AS seg_product_type,
    AVG(lc.price) AS product_price,
    ROUND(AVG(lc.price - COALESCE(ch.TOTAL_COST_PER_UNIT, 0)), 2) AS gross_profit_per_unit
  FROM `onyga-482313`.OI.DIM_PRODUCT dp
  LEFT JOIN (
    SELECT asin1, price
    FROM `onyga-482313`.OI.V_DIM_LISTING_CURRENT
    QUALIFY ROW_NUMBER() OVER (PARTITION BY asin1 ORDER BY price DESC) = 1
  ) lc ON lc.asin1 = dp.asin
  LEFT JOIN (
    SELECT asin, TOTAL_COST_PER_UNIT
    FROM `onyga-482313`.OI.DIM_COSTS_HISTORY
    WHERE end_date IS NULL OR end_date >= CURRENT_DATE()
    QUALIFY ROW_NUMBER() OVER (PARTITION BY asin ORDER BY start_date DESC) = 1
  ) ch ON ch.asin = dp.asin
  -- Unnest comma-separated segment values into individual rows
  LEFT JOIN UNNEST(SPLIT(COALESCE(dp.seg_gender, ''), ',')) AS seg_val ON TRIM(seg_val) != ''
  LEFT JOIN UNNEST(SPLIT(COALESCE(dp.seg_age_group, ''), ',')) AS age_val ON TRIM(age_val) != ''
  LEFT JOIN UNNEST(SPLIT(COALESCE(dp.seg_occasion, ''), ',')) AS occ_val ON TRIM(occ_val) != ''
  LEFT JOIN UNNEST(SPLIT(COALESCE(dp.seg_product_type, ''), ',')) AS pt_val ON TRIM(pt_val) != ''
  WHERE dp.is_active = true
    AND dp.parent_name IS NOT NULL
    AND dp.parent_name != 'UNKNOWN'
  GROUP BY dp.parent_name
),

-- ═══ 2. Search terms: last week's data + aggregated segments ═══
-- Get the most recent week per query for weekly metrics
last_week_per_query AS (
  SELECT
    query_text,
    week_start_date AS last_week,
    search_query_volume AS weekly_market_impressions,
    TOTAL_CLICKS AS weekly_market_clicks,
    TOTAL_PURCHASES AS weekly_market_purchases,
    TOTAL_MEDIAN_CLICK_PRICE AS median_click_price
  FROM `onyga-482313`.OI.V_SQP_QUERY_WEEKLY
  WHERE query_text != 'OTHER'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY query_text ORDER BY week_start_date DESC) = 1
),

-- Distinct search terms with segments from SQP
-- (segments already include manual overrides via V_SQP_QUERY_WEEKLY)
search_terms_sqp AS (
  SELECT
    lw.query_text,
    ANY_VALUE(v.gender) AS gender,
    ANY_VALUE(v.age_group) AS age_group,
    ANY_VALUE(v.occasion) AS occasion,
    ANY_VALUE(v.holiday) AS holiday,
    ANY_VALUE(v.product_type) AS product_type,
    ANY_VALUE(v.brand) AS brand,
    ANY_VALUE(v.cost_tier) AS cost_tier,
    MAX(lw.weekly_market_impressions) AS weekly_market_impressions,
    MAX(lw.weekly_market_clicks) AS weekly_market_clicks,
    MAX(lw.weekly_market_purchases) AS weekly_market_purchases,
    MAX(lw.median_click_price) AS median_click_price
  FROM last_week_per_query lw
  JOIN `onyga-482313`.OI.V_SQP_QUERY_WEEKLY v ON v.query_text = lw.query_text
  GROUP BY lw.query_text
),

-- Ads-only search terms (not in SQP)
search_terms_ads AS (
  SELECT DISTINCT LOWER(a.search_term) AS query_text
  FROM `onyga-482313`.OI.FACT_AMAZON_ADS a
  WHERE a.Ads_clicks > 0
    AND LOWER(a.search_term) NOT IN (SELECT LOWER(query_text) FROM search_terms_sqp)
),

-- Manual overrides (Research page editor) — latest row per term wins
ads_term_overrides AS (
  SELECT query_text, gender, age_group, occasion, cost_tier, product_type, brand
  FROM `onyga-482313`.OI.DE_SEARCH_TERM_SEGMENTS
  QUALIFY ROW_NUMBER() OVER (PARTITION BY LOWER(query_text) ORDER BY updated_at DESC) = 1
),

-- Product type for ads-only terms from the canonical keyword vocabulary
ads_term_product_type AS (
  SELECT
    ats.query_text,
    ARRAY_AGG(ptk.product_type ORDER BY ptk.priority ASC, LENGTH(ptk.keyword) DESC LIMIT 1)[OFFSET(0)] AS product_type
  FROM search_terms_ads ats
  CROSS JOIN `onyga-482313.OI.DE_PRODUCT_TYPE_KEYWORDS` ptk
  WHERE REGEXP_CONTAINS(LOWER(ats.query_text), CONCAT(r'(?:^|\W)', ptk.keyword, r'(?:\W|$)'))
  GROUP BY ats.query_text
),

-- Unified search terms: SQP terms + ads-only terms
-- Ads-only segments via FN_EXTRACT_SEGMENTS (same enums as everywhere else)
search_terms AS (
  SELECT * FROM search_terms_sqp
  UNION ALL
  SELECT
    ats.query_text,
    COALESCE(o.gender,    `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(ats.query_text).gender)    AS gender,
    COALESCE(o.age_group, `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(ats.query_text).age_group) AS age_group,
    COALESCE(o.occasion,  `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(ats.query_text).occasion)  AS occasion,
    `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(ats.query_text).holiday                          AS holiday,
    COALESCE(o.product_type, atpt.product_type) AS product_type,
    o.brand                                     AS brand,
    o.cost_tier                                 AS cost_tier,
    CAST(NULL AS INT64)   AS weekly_market_impressions,
    CAST(NULL AS INT64)   AS weekly_market_clicks,
    CAST(NULL AS INT64)   AS weekly_market_purchases,
    CAST(NULL AS FLOAT64) AS median_click_price
  FROM search_terms_ads ats
  LEFT JOIN ads_term_overrides o ON LOWER(o.query_text) = ats.query_text
  LEFT JOIN ads_term_product_type atpt ON atpt.query_text = ats.query_text
),

-- ═══ 3. Family-level SQP performance per term (104w) ═══
family_sqp AS (
  SELECT
    dp.parent_name,
    LOWER(sq.query_text) AS query_text,
    SUM(sq.conversions) AS family_purchases,
    SUM(sq.clicks)      AS family_clicks,
    SUM(sq.impressions) AS family_impressions
  FROM `onyga-482313`.OI.FACT_SEARCH_QUERY sq
  JOIN `onyga-482313`.OI.DIM_PRODUCT dp ON sq.ASIN = dp.asin
  WHERE sq.week_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 104 WEEK)
  GROUP BY dp.parent_name, query_text
),

-- ═══ 4. Ads metrics per search term × family ═══
ads_metrics AS (
  SELECT
    p.parent_name,
    a.search_term,
    -- CPC
    SAFE_DIVIDE(
      SUM(CASE WHEN a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH) THEN a.Ads_cost END),
      NULLIF(SUM(CASE WHEN a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH) THEN a.Ads_clicks END), 0)
    ) AS cpc_12m,
    SAFE_DIVIDE(
      SUM(CASE WHEN a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY) THEN a.Ads_cost END),
      NULLIF(SUM(CASE WHEN a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY) THEN a.Ads_clicks END), 0)
    ) AS cpc_30d,
    -- CVR
    SAFE_DIVIDE(
      SUM(CASE WHEN a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY) THEN a.Ads_units END),
      NULLIF(SUM(CASE WHEN a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY) THEN a.Ads_clicks END), 0)
    ) AS units_cvr_30d,
    SAFE_DIVIDE(
      SUM(CASE WHEN a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH) THEN a.Ads_units END),
      NULLIF(SUM(CASE WHEN a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH) THEN a.Ads_clicks END), 0)
    ) AS units_cvr_12m,
    -- Units
    SUM(CASE WHEN a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY) THEN a.Ads_units END) AS ads_units_30d,
    SUM(CASE WHEN a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH) THEN a.Ads_units END) AS ads_units_12m,
    SUM(a.Ads_orders) AS ads_family_orders,
    -- ROAS
    SAFE_DIVIDE(
      SUM(CASE WHEN a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY) THEN a.Ads_sales END),
      NULLIF(SUM(CASE WHEN a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY) THEN a.Ads_cost END), 0)
    ) AS roas_30d,
    -- Seasonal CVR (18-month lookback per holiday month window)
    SAFE_DIVIDE(SUM(CASE WHEN EXTRACT(MONTH FROM a.date) IN (10,11,12) AND a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH) THEN a.Ads_units END), NULLIF(SUM(CASE WHEN EXTRACT(MONTH FROM a.date) IN (10,11,12) AND a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH) THEN a.Ads_clicks END), 0)) AS cvr_christmas,
    SAFE_DIVIDE(SUM(CASE WHEN EXTRACT(MONTH FROM a.date) IN (2,3,4) AND a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH) THEN a.Ads_units END), NULLIF(SUM(CASE WHEN EXTRACT(MONTH FROM a.date) IN (2,3,4) AND a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH) THEN a.Ads_clicks END), 0)) AS cvr_easter,
    SAFE_DIVIDE(SUM(CASE WHEN EXTRACT(MONTH FROM a.date) IN (1,2) AND a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH) THEN a.Ads_units END), NULLIF(SUM(CASE WHEN EXTRACT(MONTH FROM a.date) IN (1,2) AND a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH) THEN a.Ads_clicks END), 0)) AS cvr_valentines,
    SAFE_DIVIDE(SUM(CASE WHEN EXTRACT(MONTH FROM a.date) IN (4,5,6) AND a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH) THEN a.Ads_units END), NULLIF(SUM(CASE WHEN EXTRACT(MONTH FROM a.date) IN (4,5,6) AND a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH) THEN a.Ads_clicks END), 0)) AS cvr_graduation,
    SAFE_DIVIDE(SUM(CASE WHEN EXTRACT(MONTH FROM a.date) IN (7,8,9) AND a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH) THEN a.Ads_units END), NULLIF(SUM(CASE WHEN EXTRACT(MONTH FROM a.date) IN (7,8,9) AND a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH) THEN a.Ads_clicks END), 0)) AS cvr_back_to_school,
    SAFE_DIVIDE(SUM(CASE WHEN EXTRACT(MONTH FROM a.date) IN (3,4,5) AND a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH) THEN a.Ads_units END), NULLIF(SUM(CASE WHEN EXTRACT(MONTH FROM a.date) IN (3,4,5) AND a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH) THEN a.Ads_clicks END), 0)) AS cvr_mothers_day
  FROM `onyga-482313`.OI.FACT_AMAZON_ADS a
  JOIN `onyga-482313`.OI.DIM_PRODUCT p
    ON a.ASIN_BY_CAMPAIGN_NAME = p.asin
  WHERE a.Ads_clicks > 0
    AND p.is_active = true
    AND p.parent_name IS NOT NULL
  GROUP BY p.parent_name, a.search_term
),

-- ═══ 5. Est. CPS v2 (market model) ═══
-- Cost note: built from FACT_RESEARCH_TERMS (term grain, refreshed FIRST by
-- SP_REFRESH_RESEARCH_RANKED) instead of re-scanning V_SQP_QUERY_WEEKLY, and
-- the curve is joined as a tiny (family × bucket) lookup instead of a range
-- join over the family × term cross join — the v1 shape of this pipeline
-- blew BigQuery's per-statement CPU guardrail during materialization.
-- Bucket thresholds mirror V_CONVERSION_CURVE (keep in sync).
term_stats AS (
  SELECT
    query_text,
    median_click_price,
    SAFE_DIVIDE(market_clicks, NULLIF(market_purchases, 0)) AS market_cps
  FROM `onyga-482313`.OI.FACT_RESEARCH_TERMS
  WHERE median_click_price > 0
),

fam_term_bucket AS (
  SELECT
    fs.parent_name,
    ts.query_text,
    ts.market_cps,
    SAFE_DIVIDE(fs.product_price, ts.median_click_price) AS price_ratio,
    CASE
      WHEN SAFE_DIVIDE(fs.product_price, ts.median_click_price) < 0.8 THEN 'A. Cheaper'
      WHEN SAFE_DIVIDE(fs.product_price, ts.median_click_price) < 1.2 THEN 'B. Sweet spot'
      WHEN SAFE_DIVIDE(fs.product_price, ts.median_click_price) < 1.8 THEN 'C. Pricier'
      WHEN SAFE_DIVIDE(fs.product_price, ts.median_click_price) < 2.5 THEN 'D. Much pricier'
      ELSE 'E. Way above'
    END AS price_bucket
  FROM family_segments fs
  CROSS JOIN term_stats ts
  WHERE fs.product_price > 0
),

-- Typical market CPS per family × bucket (median across that bucket's terms)
bucket_median AS (
  SELECT
    parent_name,
    price_bucket,
    APPROX_QUANTILES(market_cps, 100)[OFFSET(50)] AS median_market_cps
  FROM fam_term_bucket
  WHERE market_cps > 0
  GROUP BY parent_name, price_bucket
),

curve_lookup AS (
  SELECT parent_name, price_bucket, clicks_per_sale
  FROM `onyga-482313`.OI.V_CONVERSION_CURVE
  WHERE holiday_name = '_ALL'
),

-- Est. CPS v2: family curve anchored, adjusted by the term's own market
-- conversion intent relative to the typical term in the same bucket
-- (clamped 0.5×–2×). Fixes the "same number on every row in a bucket" problem.
est_v2 AS (
  SELECT
    ftb.parent_name,
    ftb.query_text,
    ftb.price_bucket,
    cl.clicks_per_sale AS est_cps_curve,
    CASE
      WHEN cl.clicks_per_sale IS NOT NULL AND ftb.market_cps > 0 AND bm.median_market_cps > 0
        THEN ROUND(LEAST(GREATEST(ftb.market_cps / bm.median_market_cps, 0.5), 2.0), 2)
      ELSE NULL
    END AS intent_factor,
    CASE
      WHEN cl.clicks_per_sale IS NULL THEN NULL
      ELSE ROUND(cl.clicks_per_sale * COALESCE(
        CASE WHEN ftb.market_cps > 0 AND bm.median_market_cps > 0
             THEN LEAST(GREATEST(ftb.market_cps / bm.median_market_cps, 0.5), 2.0)
        END, 1), 1)
    END AS est_cps
  FROM fam_term_bucket ftb
  LEFT JOIN curve_lookup cl
    ON cl.parent_name = ftb.parent_name AND cl.price_bucket = ftb.price_bucket
  LEFT JOIN bucket_median bm
    ON bm.parent_name = ftb.parent_name AND bm.price_bucket = ftb.price_bucket
),

-- ═══ 6. Segment fit calculation ═══
-- For each family × search term: weighted segment match score
seg_fit_calc AS (
  SELECT
    fs.parent_name,
    st.query_text,

    -- Gender: match=30, mismatch=-1, unknown=0, family not set=NULL
    CASE
      WHEN fs.seg_gender IS NULL OR fs.seg_gender = '' THEN NULL
      WHEN st.gender IS NULL THEN 0
      WHEN STRPOS(CONCAT(',', fs.seg_gender, ','), CONCAT(',', st.gender, ',')) > 0 THEN 30
      ELSE -1  -- value exists but doesn't match family
    END AS gender_score,

    -- Age: match=30, adjacent(Kid↔Tween)=24, 8-14 overlaps Kid/Tween/Teen=24, mismatch=-1, unknown=0
    CASE
      WHEN fs.seg_age_group IS NULL OR fs.seg_age_group = '' THEN NULL
      WHEN st.age_group IS NULL THEN 0
      WHEN STRPOS(CONCAT(',', fs.seg_age_group, ','), CONCAT(',', st.age_group, ',')) > 0 THEN 30
      -- Kid ↔ Tween adjacency at 80%
      WHEN st.age_group = '5-9 (Kid)' AND STRPOS(CONCAT(',', fs.seg_age_group, ','), ',10-12 (Tween),') > 0 THEN 24
      WHEN st.age_group = '10-12 (Tween)' AND STRPOS(CONCAT(',', fs.seg_age_group, ','), ',5-9 (Kid),') > 0 THEN 24
      -- 8-14 overlaps Kid, Tween, and lower Teen → adjacent to all three
      WHEN st.age_group = '8-14' AND (
        STRPOS(CONCAT(',', fs.seg_age_group, ','), ',5-9 (Kid),') > 0
        OR STRPOS(CONCAT(',', fs.seg_age_group, ','), ',10-12 (Tween),') > 0
        OR STRPOS(CONCAT(',', fs.seg_age_group, ','), ',13-17 (Teen),') > 0
      ) THEN 24
      -- Family has 8-14 and term has Kid/Tween/Teen → adjacent
      WHEN STRPOS(CONCAT(',', fs.seg_age_group, ','), ',8-14,') > 0 AND st.age_group IN ('5-9 (Kid)', '10-12 (Tween)', '13-17 (Teen)') THEN 24
      ELSE -1
    END AS age_score,

    -- Occasion: match=10, mismatch=-1, unknown=0
    CASE
      WHEN fs.seg_occasion IS NULL OR fs.seg_occasion = '' THEN NULL
      WHEN st.occasion IS NULL THEN 0
      WHEN STRPOS(CONCAT(',', fs.seg_occasion, ','), CONCAT(',', st.occasion, ',')) > 0 THEN 10
      ELSE -1
    END AS occasion_score,

    -- Product type: match=30, mismatch=-1, unknown=0
    CASE
      WHEN fs.seg_product_type IS NULL OR fs.seg_product_type = '' THEN NULL
      WHEN st.product_type IS NULL OR st.product_type = 'General' THEN 0
      WHEN STRPOS(CONCAT(',', fs.seg_product_type, ','), CONCAT(',', st.product_type, ',')) > 0 THEN 30
      ELSE -1
    END AS pt_score

  FROM family_segments fs
  CROSS JOIN search_terms st
),

-- Combine per-field scores into final seg_fit (field scores passed through
-- as explanation columns for the UI tooltip)
seg_fit_final AS (
  SELECT
    parent_name,
    query_text,
    gender_score, age_score, occasion_score, pt_score,
    CASE
      -- Any mismatch → cap at 10
      WHEN gender_score = -1 OR age_score = -1 OR occasion_score = -1 OR pt_score = -1 THEN 10
      -- Sum the points (NULL dimensions contribute 0)
      ELSE COALESCE(gender_score, 0) + COALESCE(age_score, 0) + COALESCE(occasion_score, 0) + COALESCE(pt_score, 0)
    END AS seg_fit
  FROM seg_fit_calc
),

-- ═══ 7. Holiday active check ═══
holiday_active AS (
  SELECT
    holiday_name,
    CASE
      WHEN holiday_name = 'Christmas' AND EXTRACT(MONTH FROM CURRENT_DATE()) IN (10,11,12) THEN TRUE
      WHEN holiday_name = 'Easter' AND EXTRACT(MONTH FROM CURRENT_DATE()) IN (2,3,4) THEN TRUE
      WHEN holiday_name = 'Valentines' AND EXTRACT(MONTH FROM CURRENT_DATE()) IN (1,2) THEN TRUE
      WHEN holiday_name = 'Halloween' AND EXTRACT(MONTH FROM CURRENT_DATE()) IN (9,10) THEN TRUE
      WHEN holiday_name = 'Mothers Day' AND EXTRACT(MONTH FROM CURRENT_DATE()) IN (3,4,5) THEN TRUE
      WHEN holiday_name = 'Fathers Day' AND EXTRACT(MONTH FROM CURRENT_DATE()) IN (5,6) THEN TRUE
      WHEN holiday_name = 'New Years' AND EXTRACT(MONTH FROM CURRENT_DATE()) IN (11,12,1) THEN TRUE
      ELSE FALSE
    END AS is_active
  FROM UNNEST(['Christmas', 'Easter', 'Valentines', 'Halloween', 'Mothers Day', 'Fathers Day', 'New Years']) AS holiday_name
),

-- ═══ 8. Scored rows (pre-bracket) ═══
scored AS (
  SELECT
    fs.parent_name,
    fs.gross_profit_per_unit,
    st.query_text,
    st.gender,
    st.age_group,
    st.occasion,
    st.holiday,
    st.product_type,
    st.brand,
    st.cost_tier,
    st.weekly_market_impressions,
    st.weekly_market_clicks,
    st.weekly_market_purchases,
    st.median_click_price,

    -- Ads metrics
    am.cpc_12m,
    am.cpc_30d,
    am.units_cvr_30d,
    am.units_cvr_12m,
    COALESCE(am.ads_units_30d, 0) AS ads_units_30d,
    COALESCE(am.ads_units_12m, 0) AS ads_units_12m,
    COALESCE(am.ads_family_orders, 0) AS ads_family_orders,
    am.roas_30d,
    am.cvr_christmas,
    am.cvr_easter,
    am.cvr_valentines,
    am.cvr_graduation,
    am.cvr_back_to_school,
    am.cvr_mothers_day,

    -- Family SQP performance
    COALESCE(fq.family_purchases, 0)   AS family_purchases,
    COALESCE(fq.family_clicks, 0)      AS family_clicks,
    COALESCE(fq.family_impressions, 0) AS family_impressions,

    -- Seg fit + per-field breakdown
    sf.seg_fit,
    sf.gender_score,
    sf.age_score,
    sf.occasion_score,
    sf.pt_score,

    -- Est. CPS v2 (market-intent-adjusted curve) + components for tooltips
    ec.est_cps,
    ec.est_cps_curve,
    ec.intent_factor,
    ec.price_bucket,

    -- Ads Purch: 30d if >3, else 12m
    CASE
      WHEN COALESCE(am.ads_units_30d, 0) > 3 THEN am.ads_units_30d
      WHEN COALESCE(am.ads_units_12m, 0) > 0 THEN am.ads_units_12m
      ELSE NULL
    END AS ads_purch,

    -- Ads CPS = 1/CVR: 30d if >3 units, else 12m
    CASE
      WHEN COALESCE(am.ads_units_30d, 0) > 3 AND am.units_cvr_30d > 0 THEN ROUND(1.0 / am.units_cvr_30d, 1)
      WHEN am.units_cvr_12m > 0 THEN ROUND(1.0 / am.units_cvr_12m, 1)
      ELSE NULL
    END AS ads_cps,

    -- CPS for scoring — SAME trust rule as ads_cps so the two always agree:
    -- 30d CVR if >3 units sold in 30d, else 12m CVR if > 0, else curve.
    -- (A zero 30d CVR — recent clicks, no recent sales — must fall through
    -- to 12m, not mask it.)
    CASE
      WHEN COALESCE(am.ads_units_30d, 0) > 3 AND am.units_cvr_30d > 0 THEN 1.0 / am.units_cvr_30d
      WHEN am.units_cvr_12m > 0 THEN 1.0 / am.units_cvr_12m
      ELSE ec.est_cps
    END AS effective_cps,
    CASE
      WHEN COALESCE(am.ads_units_30d, 0) > 3 AND am.units_cvr_30d > 0 THEN 'ads_30d'
      WHEN am.units_cvr_12m > 0 THEN 'ads_12m'
      WHEN ec.est_cps IS NOT NULL THEN 'curve'
      ELSE NULL
    END AS cps_source,
    COALESCE(am.ads_family_orders, 0) > 3
      AND ((COALESCE(am.ads_units_30d, 0) > 3 AND am.units_cvr_30d > 0) OR am.units_cvr_12m > 0)
      AS has_reliable_ads_cvr,

    -- Purchase Rank (weekly purchases buckets)
    CASE
      WHEN st.weekly_market_purchases IS NULL THEN NULL
      WHEN st.weekly_market_purchases <= 0    THEN 0
      WHEN st.weekly_market_purchases >= 1000 THEN 100
      WHEN st.weekly_market_purchases >= 500  THEN 90
      WHEN st.weekly_market_purchases >= 200  THEN 80
      WHEN st.weekly_market_purchases >= 100  THEN 70
      WHEN st.weekly_market_purchases >= 50   THEN 55
      WHEN st.weekly_market_purchases >= 20   THEN 40
      WHEN st.weekly_market_purchases >= 5    THEN 25
      ELSE 10
    END AS purchase_rank,

    -- Holiday active flag
    COALESCE(ha.is_active, TRUE) AS is_holiday_active

  FROM family_segments fs
  CROSS JOIN search_terms st
  LEFT JOIN seg_fit_final sf
    ON sf.parent_name = fs.parent_name AND sf.query_text = st.query_text
  LEFT JOIN ads_metrics am
    ON am.parent_name = fs.parent_name AND LOWER(am.search_term) = LOWER(st.query_text)
  LEFT JOIN est_v2 ec
    ON ec.parent_name = fs.parent_name AND ec.query_text = st.query_text
  LEFT JOIN family_sqp fq
    ON fq.parent_name = fs.parent_name AND fq.query_text = LOWER(st.query_text)
  LEFT JOIN holiday_active ha
    ON ha.holiday_name = st.holiday
)

-- ═══ Final output: bracket scores once, then rank ═══
SELECT
  * EXCEPT(has_reliable_ads_cvr),
  -- Final Rank = avg(overall_fit, purchase_rank) with holiday override
  CASE
    WHEN holiday IS NOT NULL AND NOT is_holiday_active THEN 0
    ELSE ROUND(
      (COALESCE(overall_fit, 0) + COALESCE(purchase_rank, 0))
      / NULLIF(IF(overall_fit IS NOT NULL, 1, 0) + IF(purchase_rank IS NOT NULL, 1, 0), 0)
    )
  END AS rank
FROM (
  SELECT
    *,
    -- CPS Fit score (0-100 brackets over effective CPS)
    CASE
      WHEN effective_cps IS NULL THEN NULL
      WHEN effective_cps <= 5  THEN 100
      WHEN effective_cps <= 8  THEN 85
      WHEN effective_cps <= 12 THEN 70
      WHEN effective_cps <= 20 THEN 55
      WHEN effective_cps <= 35 THEN 35
      WHEN effective_cps <= 50 THEN 20
      ELSE 10
    END AS cps_fit,
    -- Overall Fit: >3 orders → real-CPS bracket only.
    -- Else: SEG FIT is the base; the price bucket can only REDUCE it
    -- (Sweet spot/Cheaper −0, Pricier −10, Much pricier −20, Way above −30).
    CASE
      WHEN has_reliable_ads_cvr THEN
        CASE
          WHEN effective_cps <= 5  THEN 100
          WHEN effective_cps <= 8  THEN 85
          WHEN effective_cps <= 12 THEN 70
          WHEN effective_cps <= 20 THEN 55
          WHEN effective_cps <= 35 THEN 35
          WHEN effective_cps <= 50 THEN 20
          ELSE 10
        END
      WHEN seg_fit IS NULL THEN NULL
      ELSE GREATEST(
        seg_fit - CASE price_bucket
          WHEN 'C. Pricier'      THEN 10
          WHEN 'D. Much pricier' THEN 20
          WHEN 'E. Way above'    THEN 30
          ELSE 0
        END, 0)
    END AS overall_fit
  FROM scored
)
