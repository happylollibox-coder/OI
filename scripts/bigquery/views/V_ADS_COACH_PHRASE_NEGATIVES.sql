-- =============================================
-- OI Database Project - V_ADS_COACH_PHRASE_NEGATIVES View
-- =============================================
--
-- Purpose: N-gram analysis of unprofitable search terms.
--          Identifies common 1-gram, 2-gram and 3-gram phrases shared across
--          multiple loss-making terms. Surfaces NEGATE_PHRASE recommendations.
--
-- Grain: phrase × campaign_id
--
-- Logic:
--   1. Pull all search terms from V_ADS_COACH_DATA with enough clicks
--   2. Generate 2-grams and 3-grams from each search term
--   3. Aggregate per phrase × campaign: total spend, orders, clicks, term count
--   4. Filter: phrase has 0 orders (8w), >= $15 spend, >= 3 terms sharing it
--   5. Safety: exclude phrases that also appear in converting terms (8w)
--   6. Safety: check 1-year history — ALL terms containing the phrase across 52w
--   7. Action Tiering:
--      - NEGATE_PHRASE: ROAS < 1.0 (unprofitable)
--      - SEASONAL_PHRASE: ROAS >= 1.0 but >70% of orders in top 3 months
--      - (Filtered out if profitable year-round)
--
-- Dependencies: V_ADS_COACH_DATA, FACT_AMAZON_ADS
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_COACH_PHRASE_NEGATIVES`
AS
WITH

-- ─── Source: all active search terms with their metrics ───
source_terms AS (
  SELECT
    campaign_id,
    ad_group_id,
    campaign_name,
    campaign_type,
    portfolio_name,
    asin,
    product_short_name,
    experiment_id,
    strategy_id,
    search_term,
    targeting,
    ads_spend_8w,
    ads_orders_8w,
    ads_clicks_8w,
    ads_impressions_8w
  FROM `onyga-482313.OI.V_ADS_COACH_DATA`
  WHERE recommendation_type = 'ACTIVE_TERM'
    AND search_term IS NOT NULL
    AND search_term != ''
),

-- ─── Brand terms to exclude (never negate brand phrases) ───
brand_words AS (
  SELECT phrase AS word 
  FROM `onyga-482313.OI.DIM_BRAND_PHRASES` 
  WHERE phrase_type = 'BRAND'
),

-- ─── Generate n-grams from each search term ───
term_words AS (
  SELECT
    st.*,
    SPLIT(search_term, ' ') AS words,
    ARRAY_LENGTH(SPLIT(search_term, ' ')) AS word_count
  FROM source_terms st
),

bigrams AS (
  SELECT
    tw.campaign_id,
    tw.ad_group_id,
    tw.campaign_name,
    tw.campaign_type,
    tw.portfolio_name,
    tw.strategy_id,
    tw.asin,
    tw.search_term,
    tw.targeting,
    tw.ads_spend_8w,
    tw.ads_orders_8w,
    tw.ads_clicks_8w,
    CONCAT(tw.words[SAFE_OFFSET(pos)], ' ', tw.words[SAFE_OFFSET(pos + 1)]) AS phrase,
    2 AS ngram_size
  FROM term_words tw,
    UNNEST(GENERATE_ARRAY(0, tw.word_count - 2)) AS pos
  WHERE tw.word_count >= 2
),

trigrams AS (
  SELECT
    tw.campaign_id,
    tw.ad_group_id,
    tw.campaign_name,
    tw.campaign_type,
    tw.portfolio_name,
    tw.strategy_id,
    tw.asin,
    tw.search_term,
    tw.targeting,
    tw.ads_spend_8w,
    tw.ads_orders_8w,
    tw.ads_clicks_8w,
    CONCAT(tw.words[SAFE_OFFSET(pos)], ' ', tw.words[SAFE_OFFSET(pos + 1)], ' ', tw.words[SAFE_OFFSET(pos + 2)]) AS phrase,
    3 AS ngram_size
  FROM term_words tw,
    UNNEST(GENERATE_ARRAY(0, tw.word_count - 3)) AS pos
  WHERE tw.word_count >= 3
),

-- ─── Stopwords: connecting/common words to exclude from 1-grams ───
stopwords AS (
  SELECT word FROM UNNEST([
    'for', 'the', 'and', 'with', 'to', 'a', 'an', 'in', 'of', 'on', 'my',
    'is', 'it', 'at', 'or', 'by', 'be', 'as', 'do', 'no', 'so', 'up',
    'de', 'la', 'el', 'en', 'con', 'para', 'los', 'las', 'del', 'un', 'una',
    'que', 'por', 'su', 'al', 'se', 'es', 'le', 'lo', 'ya', 'me', 'ni',
    'from', 'that', 'this', 'these', 'those', 'not', 'but', 'all',
    'her', 'his', 'she', 'him', 'who', 'its', 'has', 'had', 'was', 'are',
    'like', 'very', 'just', 'more', 'most', 'also', 'than', 'then',
    'each', 'every', 'some', 'any', 'few', 'many', 'much', 'own',
    'will', 'can', 'may', 'would', 'could', 'should',
    'about', 'into', 'over', 'after', 'under', 'between', 'through',
    'what', 'when', 'where', 'which', 'how', 'other', 'only',
    'new', 'good', 'best', 'top'
  ]) AS word
),

unigrams AS (
  SELECT
    tw.campaign_id,
    tw.ad_group_id,
    tw.campaign_name,
    tw.campaign_type,
    tw.portfolio_name,
    tw.strategy_id,
    tw.asin,
    tw.search_term,
    tw.targeting,
    tw.ads_spend_8w,
    tw.ads_orders_8w,
    tw.ads_clicks_8w,
    tw.words[SAFE_OFFSET(pos)] AS phrase,
    1 AS ngram_size
  FROM term_words tw,
    UNNEST(GENERATE_ARRAY(0, tw.word_count - 1)) AS pos
  WHERE tw.word_count >= 1
    AND LENGTH(tw.words[SAFE_OFFSET(pos)]) > 2  -- skip single/two-char words
    AND tw.words[SAFE_OFFSET(pos)] NOT IN (SELECT word FROM stopwords)
),

all_ngrams AS (
  SELECT * FROM unigrams
  UNION ALL
  SELECT * FROM bigrams
  UNION ALL
  SELECT * FROM trigrams
),

filtered_ngrams AS (
  SELECT ng.*
  FROM all_ngrams ng
  WHERE NOT EXISTS (
    SELECT 1 FROM brand_words bw
    WHERE LOWER(ng.phrase) LIKE CONCAT('%', bw.word, '%')
  )
  AND ng.phrase IS NOT NULL
  AND ng.phrase NOT LIKE '% %  %'
),

-- ─── Aggregate per phrase × campaign ───
phrase_campaign AS (
  SELECT
    phrase,
    ngram_size,
    campaign_id,
    ad_group_id,
    campaign_name,
    campaign_type,
    portfolio_name,
    ANY_VALUE(strategy_id) AS strategy_id,
    COUNT(DISTINCT search_term) AS phrase_term_count,
    SUM(ads_spend_8w) AS phrase_spend_8w,
    SUM(ads_orders_8w) AS phrase_orders_8w,
    SUM(ads_clicks_8w) AS phrase_clicks_8w,
    ARRAY_AGG(
      STRUCT(search_term, ads_spend_8w, ads_orders_8w, ads_clicks_8w)
      ORDER BY ads_spend_8w DESC
      LIMIT 5
    ) AS sample_terms
  FROM filtered_ngrams
  GROUP BY 1, 2, 3, 4, 5, 6, 7
  HAVING phrase_term_count >= 3
     AND phrase_spend_8w >= 15
     AND phrase_clicks_8w >= 20
),

-- ─── Safety check 1: converting phrases (8w) ───
converting_phrases AS (
  SELECT DISTINCT phrase, campaign_id
  FROM filtered_ngrams
  WHERE ads_orders_8w > 0
),

-- ─── 1-Year history: Pre-aggregate monthly term data ───
term_monthly_1y AS (
  SELECT
    campaign_id,
    LOWER(search_term) AS search_term,
    FORMAT_DATE('%Y-%m', date) AS month,
    SUM(Ads_orders) AS orders,
    SUM(Ads_cost) AS spend,
    SUM(Ads_sales) AS sales
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
    AND search_term IS NOT NULL
  GROUP BY 1, 2, 3
),

-- ─── Extract unique historical terms and split them ───
-- This prevents the explosive CROSS JOIN of LIKE '%phrase%'
hist_term_words AS (
  SELECT DISTINCT
    CAST(campaign_id AS STRING) AS campaign_id,
    search_term,
    SPLIT(search_term, ' ') AS words
  FROM term_monthly_1y
),

-- ─── Generate up to 3-grams for ALL historical terms ───
hist_term_ngrams AS (
  SELECT campaign_id, search_term, words[SAFE_OFFSET(pos)] AS phrase
  FROM hist_term_words, UNNEST(GENERATE_ARRAY(0, ARRAY_LENGTH(words) - 1)) AS pos
  UNION ALL
  SELECT campaign_id, search_term, CONCAT(words[SAFE_OFFSET(pos)], ' ', words[SAFE_OFFSET(pos+1)]) AS phrase
  FROM hist_term_words, UNNEST(GENERATE_ARRAY(0, ARRAY_LENGTH(words) - 2)) AS pos
  UNION ALL
  SELECT campaign_id, search_term, CONCAT(words[SAFE_OFFSET(pos)], ' ', words[SAFE_OFFSET(pos+1)], ' ', words[SAFE_OFFSET(pos+2)]) AS phrase
  FROM hist_term_words, UNNEST(GENERATE_ARRAY(0, ARRAY_LENGTH(words) - 3)) AS pos
),

-- ─── Evaluate TRUE phrase history (all terms containing the phrase EXACTLY) ───
phrase_monthly_history AS (
  SELECT
    fn.phrase,
    fn.campaign_id,
    tm.month,
    SUM(tm.orders) AS month_orders,
    SUM(tm.spend) AS month_spend,
    SUM(tm.sales) AS month_sales,
    COUNT(DISTINCT tm.search_term) AS monthly_terms
  FROM (SELECT DISTINCT phrase, CAST(campaign_id AS STRING) AS campaign_id FROM phrase_campaign) fn
  JOIN hist_term_ngrams hng
    ON hng.campaign_id = fn.campaign_id
    AND hng.phrase = fn.phrase
  JOIN term_monthly_1y tm
    ON CAST(tm.campaign_id AS STRING) = hng.campaign_id
    AND tm.search_term = hng.search_term
  GROUP BY 1, 2, 3
),

phrase_1y_history AS (
  SELECT
    phrase,
    campaign_id,
    SUM(month_orders) AS phrase_orders_1y,
    SUM(month_spend) AS phrase_spend_1y,
    SUM(month_sales) AS phrase_sales_1y,
    SAFE_DIVIDE(SUM(month_sales), NULLIF(SUM(month_spend), 0)) AS phrase_roas_1y,
    SUM(monthly_terms) AS total_monthly_terms_1y, -- proxy for scope
    ARRAY_AGG(
      STRUCT(month, month_orders AS orders)
      ORDER BY month_orders DESC
      LIMIT 3
    ) AS top_months
  FROM phrase_monthly_history
  GROUP BY 1, 2
),

-- ─── Final Classification ───
phrase_recommendations AS (
  SELECT
    pc.phrase,
    pc.ngram_size,
    pc.campaign_id,
    pc.ad_group_id,
    pc.campaign_name,
    pc.campaign_type,
    pc.portfolio_name,
    pc.strategy_id,
    pc.phrase_term_count,
    ROUND(pc.phrase_spend_8w, 2) AS phrase_spend_8w,
    pc.phrase_orders_8w,
    pc.phrase_clicks_8w,
    pc.sample_terms,

    -- 1-year history
    COALESCE(h1y.phrase_orders_1y, 0) AS phrase_orders_1y,
    ROUND(COALESCE(h1y.phrase_spend_1y, 0), 2) AS phrase_spend_1y,
    ROUND(COALESCE(h1y.phrase_sales_1y, 0), 2) AS phrase_sales_1y,
    ROUND(COALESCE(h1y.phrase_roas_1y, 0), 2) AS phrase_roas_1y,
    
    -- Seasonality math
    SAFE_DIVIDE(
      (SELECT SUM(t.orders) FROM UNNEST(h1y.top_months) t),
      NULLIF(h1y.phrase_orders_1y, 0)
    ) AS top3_months_pct,
    
    (SELECT STRING_AGG(CONCAT(t.month, ':', CAST(t.orders AS STRING)), ' | ') FROM UNNEST(h1y.top_months) t) AS peak_months,

    -- Safety check
    cp.phrase IS NOT NULL AS has_converting_terms_8w,

    -- Action
    CASE
      -- Safe NEGATE: Unprofitable over 1 year (ROAS < 1.0) and 0 recent orders
      WHEN cp.phrase IS NULL AND pc.phrase_orders_8w = 0
        AND COALESCE(h1y.phrase_roas_1y, 0) < 1.0
        THEN 'NEGATE_PHRASE'
        
      -- Caution SEASONAL: Profitable (ROAS >= 1.0) but highly seasonal (>70% orders in 3 months)
      WHEN cp.phrase IS NULL AND pc.phrase_orders_8w = 0
        AND COALESCE(h1y.phrase_roas_1y, 0) >= 1.0
        AND SAFE_DIVIDE((SELECT SUM(t.orders) FROM UNNEST(h1y.top_months) t), NULLIF(h1y.phrase_orders_1y, 0)) > 0.70
        THEN 'PROMOTE_TO_PEAK_PHRASE'
        
      WHEN cp.phrase IS NOT NULL
        THEN 'MONITOR_PHRASE'
        
      ELSE 'PROFITABLE_ALL_YEAR'
    END AS action,

    -- Theme detection
    CASE
      WHEN REGEXP_CONTAINS(LOWER(pc.phrase), r'birthday|bday|b-day') THEN 'Birthday'
      WHEN REGEXP_CONTAINS(LOWER(pc.phrase), r'easter|bunny') THEN 'Easter'
      WHEN REGEXP_CONTAINS(LOWER(pc.phrase), r'christmas|xmas') THEN 'Christmas'
      WHEN REGEXP_CONTAINS(LOWER(pc.phrase), r'valentine|vday') THEN 'Valentines'
      WHEN REGEXP_CONTAINS(LOWER(pc.phrase), r'halloween|trick or treat') THEN 'Halloween'
      WHEN REGEXP_CONTAINS(LOWER(pc.phrase), r'summer|pool|beach') THEN 'Summer'
      WHEN REGEXP_CONTAINS(LOWER(pc.phrase), r'mother|mom') THEN 'Mothers Day'
      WHEN REGEXP_CONTAINS(LOWER(pc.phrase), r'father|dad') THEN 'Fathers Day'
      ELSE 'General Peak'
    END AS seasonal_theme,

    -- Priority
    ROUND(pc.phrase_spend_8w * pc.phrase_term_count, 0) AS priority_score,

    -- Reason text
    CASE
      WHEN cp.phrase IS NULL AND pc.phrase_orders_8w = 0 AND COALESCE(h1y.phrase_roas_1y, 0) < 1.0
        THEN CONCAT('Phrase "', pc.phrase, '" is unprofitable (1y ROAS ', CAST(ROUND(COALESCE(h1y.phrase_roas_1y,0),2) AS STRING), '). 0 orders last 8w. Safe to negate.')
      WHEN cp.phrase IS NULL AND pc.phrase_orders_8w = 0 AND COALESCE(h1y.phrase_roas_1y, 0) >= 1.0
        AND SAFE_DIVIDE((SELECT SUM(t.orders) FROM UNNEST(h1y.top_months) t), NULLIF(h1y.phrase_orders_1y, 0)) > 0.70
        THEN CONCAT('⚠️ Phrase "', pc.phrase, '" is seasonal (ROAS ', CAST(ROUND(COALESCE(h1y.phrase_roas_1y,0),2) AS STRING), '). Peaks: ',
             COALESCE((SELECT STRING_AGG(CONCAT(t.month, ':', CAST(t.orders AS STRING)), ', ') FROM UNNEST(h1y.top_months) t), ''), '. Negate off-season.')
      WHEN cp.phrase IS NOT NULL THEN 'Has converting terms (8w) — do NOT negate.'
      ELSE 'Profitable year-round. Do NOT negate.'
    END AS reason

  FROM phrase_campaign pc
  LEFT JOIN converting_phrases cp
    ON pc.phrase = cp.phrase AND pc.campaign_id = cp.campaign_id
  LEFT JOIN phrase_1y_history h1y
    ON pc.phrase = h1y.phrase AND pc.campaign_id = h1y.campaign_id
)

SELECT *
FROM phrase_recommendations
WHERE action IN ('NEGATE_PHRASE', 'PROMOTE_TO_PEAK_PHRASE')
ORDER BY
  CASE action WHEN 'NEGATE_PHRASE' THEN 0 ELSE 1 END,
  priority_score DESC;
