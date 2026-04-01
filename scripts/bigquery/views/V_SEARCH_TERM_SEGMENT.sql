-- =============================================
-- OI Database Project - V_SEARCH_TERM_SEGMENT View
-- =============================================
--
-- Purpose: Classify every SQP search term on 4 independent dimensions + 1 derived:
--   1. intent_segment: WHO is the shopper looking for? (BRAND/COMPETITOR/PRODUCT/CATEGORY/GIFT/GENERIC)
--   2. occasion: WHAT is the occasion? (BIRTHDAY/CHRISTMAS/SLEEPOVER/PARTY/VALENTINES/BACK_TO_SCHOOL/EASTER/GRADUATION/NO_OCCASION)
--   3. age_group: WHO is the recipient? (AGE_5_7/AGE_8_10/AGE_11_14/TWEEN/TEEN/COLLEGE/NO_AGE)
--   4. product_match: WHICH Happy Lolli product line? (LOLLIME_JOURNAL/LOLLIBOX_GIFT/TRUTH_OR_DARE/POWER_SHOWER/MULTI_MATCH/NO_MATCH)
--   5. experiment_segment (derived): Actionable grouping for experiment targeting.
--      Combines intent_segment + occasion + age_group + product_match into non-overlapping segments:
--      BRAND, PRODUCT, ACTIVITY, BIRTHDAY_KIDS, BIRTHDAY_TEEN, BIRTHDAY_GENERAL,
--      CHRISTMAS, EASTER, VALENTINES, BACK_TO_SCHOOL, GRADUATION,
--      GIFT_KIDS, GIFT_TEEN, GIFT_GENERAL
--
-- Each dimension is independent: "journal kit for girls birthday gift" =
--   PRODUCT + BIRTHDAY + NO_AGE + LOLLIME_JOURNAL
--
-- Source: FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY (SQP), DIM_PRODUCT, DIM_BRAND_PHRASES
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_SEARCH_TERM_SEGMENT`
AS
WITH
-- Holiday week detection: which SQP reporting weeks fall inside a holiday ramp-up window?
-- Extends 7 days past holiday_date since SQP weekly data bleeds across the holiday boundary
holiday_weeks AS (
  SELECT DISTINCT sqp.Reporting_Date
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` sqp
  JOIN `onyga-482313.OI.DIM_US_HOLIDAYS` h
    ON sqp.Reporting_Date >= h.pre_season_start
    AND sqp.Reporting_Date <= DATE_ADD(h.holiday_date, INTERVAL 7 DAY)
  WHERE sqp.DATA_SOURCE = 'SQP'
    AND sqp.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
),

recent_sqp AS (
  -- Last 12 months of SQP data per search term per ASIN
  -- Recency weighting: last 1 month = 3x, 1-3 months = 2x, 3-12 months = 1x
  -- Split into non-holiday (weighted) and holiday metrics
  SELECT
    LOWER(sqp.Search_Query) as search_term,
    sqp.ASIN as asin,
    COUNT(DISTINCT sqp.Reporting_Date) as weeks_seen,

    -- Non-holiday RAW counts (for proven thresholds -- unweighted)
    COUNTIF(COALESCE(sqp.ORDERS, 0) > 0 AND hw.Reporting_Date IS NULL) as weeks_with_your_orders,
    SUM(CASE WHEN hw.Reporting_Date IS NULL THEN COALESCE(sqp.ORDERS, 0) END) as your_orders,
    SUM(CASE WHEN hw.Reporting_Date IS NULL THEN COALESCE(sqp.Clicks, 0) END) as your_clicks,
    SUM(CASE WHEN hw.Reporting_Date IS NULL THEN COALESCE(sqp.ADS_Orders, 0) END) as ads_orders,
    SUM(CASE WHEN hw.Reporting_Date IS NULL THEN COALESCE(sqp.ADS_Clicks, 0) END) as ads_clicks,
    COUNTIF(hw.Reporting_Date IS NULL) as non_holiday_weeks,

    -- Non-holiday WEIGHTED sums (for rates, magnitudes, shares -- recency-weighted)
    SUM(CASE WHEN hw.Reporting_Date IS NULL THEN COALESCE(sqp.AMAZON_ORDERS, 0) * (CASE WHEN sqp.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY) THEN 3.0 WHEN sqp.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 84 DAY) THEN 2.0 ELSE 1.0 END) END) as w_amazon_orders,
    SUM(CASE WHEN hw.Reporting_Date IS NULL THEN COALESCE(sqp.AMAZON_Clicks, 0) * (CASE WHEN sqp.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY) THEN 3.0 WHEN sqp.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 84 DAY) THEN 2.0 ELSE 1.0 END) END) as w_amazon_clicks,
    SUM(CASE WHEN hw.Reporting_Date IS NULL THEN COALESCE(sqp.AMAZON_IMPRESSIONS, 0) * (CASE WHEN sqp.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY) THEN 3.0 WHEN sqp.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 84 DAY) THEN 2.0 ELSE 1.0 END) END) as w_amazon_impressions,
    SUM(CASE WHEN hw.Reporting_Date IS NULL THEN COALESCE(sqp.ORDERS, 0) * (CASE WHEN sqp.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY) THEN 3.0 WHEN sqp.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 84 DAY) THEN 2.0 ELSE 1.0 END) END) as w_your_orders,
    SUM(CASE WHEN hw.Reporting_Date IS NULL THEN COALESCE(sqp.Impressions, 0) * (CASE WHEN sqp.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY) THEN 3.0 WHEN sqp.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 84 DAY) THEN 2.0 ELSE 1.0 END) END) as w_your_impressions,
    SUM(CASE WHEN hw.Reporting_Date IS NULL THEN COALESCE(sqp.Clicks, 0) * (CASE WHEN sqp.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY) THEN 3.0 WHEN sqp.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 84 DAY) THEN 2.0 ELSE 1.0 END) END) as w_your_clicks,
    SUM(CASE WHEN hw.Reporting_Date IS NULL THEN COALESCE(sqp.ADS_Orders, 0) * (CASE WHEN sqp.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY) THEN 3.0 WHEN sqp.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 84 DAY) THEN 2.0 ELSE 1.0 END) END) as w_ads_orders,
    SUM(CASE WHEN hw.Reporting_Date IS NULL THEN COALESCE(sqp.ADS_Clicks, 0) * (CASE WHEN sqp.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY) THEN 3.0 WHEN sqp.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 84 DAY) THEN 2.0 ELSE 1.0 END) END) as w_ads_clicks,
    -- Sum of weights for non-holiday weeks 
    SUM(CASE WHEN hw.Reporting_Date IS NULL THEN (CASE WHEN sqp.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY) THEN 3.0 WHEN sqp.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 84 DAY) THEN 2.0 ELSE 1.0 END) END) as w_non_holiday_total,

    -- Holiday RAW counts (seasonal experiment decisions -- unweighted)
    COUNTIF(COALESCE(sqp.ORDERS, 0) > 0 AND hw.Reporting_Date IS NOT NULL) as holiday_weeks_with_your_orders,
    SUM(CASE WHEN hw.Reporting_Date IS NOT NULL THEN COALESCE(sqp.AMAZON_ORDERS, 0) END) as holiday_amazon_orders,
    SUM(CASE WHEN hw.Reporting_Date IS NOT NULL THEN COALESCE(sqp.AMAZON_Clicks, 0) END) as holiday_amazon_clicks,
    SUM(CASE WHEN hw.Reporting_Date IS NOT NULL THEN COALESCE(sqp.ORDERS, 0) END) as holiday_your_orders,
    SUM(CASE WHEN hw.Reporting_Date IS NOT NULL THEN COALESCE(sqp.Clicks, 0) END) as holiday_your_clicks,
    SUM(CASE WHEN hw.Reporting_Date IS NOT NULL THEN COALESCE(sqp.ADS_Orders, 0) END) as holiday_ads_orders,
    SUM(CASE WHEN hw.Reporting_Date IS NOT NULL THEN COALESCE(sqp.ADS_Clicks, 0) END) as holiday_ads_clicks,
    COUNTIF(hw.Reporting_Date IS NOT NULL) as holiday_weeks

  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` sqp
  LEFT JOIN holiday_weeks hw ON sqp.Reporting_Date = hw.Reporting_Date
  WHERE sqp.DATA_SOURCE = 'SQP'
    AND sqp.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
  GROUP BY 1, 2
),

term_base AS (
  SELECT
    r.search_term,
    r.asin,
    r.weeks_seen,

    -- Non-holiday proven metrics
    r.weeks_with_your_orders,
    r.your_orders as your_total_orders,
    r.your_clicks as your_total_clicks,
    r.ads_orders as ads_total_orders,
    r.ads_clicks as ads_total_clicks,
    r.non_holiday_weeks,

    -- Holiday proven metrics
    r.holiday_weeks_with_your_orders,
    r.holiday_your_orders as holiday_your_total_orders,
    r.holiday_your_clicks as holiday_your_total_clicks,
    r.holiday_ads_orders as holiday_ads_total_orders,
    r.holiday_ads_clicks as holiday_ads_total_clicks,
    r.holiday_weeks,

    -- Non-holiday WEIGHTED metrics
    ROUND(SAFE_DIVIDE(r.w_amazon_orders, NULLIF(r.w_non_holiday_total, 0)), 1) as amazon_avg_weekly_orders,
    ROUND(SAFE_DIVIDE(r.w_amazon_orders, NULLIF(r.w_amazon_clicks, 0)) * 100, 2) as amazon_conversion_rate_pct,
    ROUND(SAFE_DIVIDE(r.w_amazon_clicks, NULLIF(r.w_amazon_impressions, 0)) * 100, 2) as amazon_ctr_pct,
    ROUND(SAFE_DIVIDE(r.w_your_impressions, NULLIF(r.w_amazon_impressions, 0)) * 100, 2) as your_impressions_share_pct,
    ROUND(SAFE_DIVIDE(r.w_your_orders, NULLIF(r.w_amazon_orders, 0)) * 100, 2) as your_orders_share_pct,
    ROUND(SAFE_DIVIDE(r.w_your_clicks, NULLIF(r.w_amazon_clicks, 0)) * 100, 2) as your_clicks_share_pct,
    r.w_your_orders,
    r.w_your_clicks,
    r.w_ads_orders,
    r.w_ads_clicks,

    -- Holiday market magnitude
    ROUND(SAFE_DIVIDE(r.holiday_amazon_orders, NULLIF(r.holiday_weeks, 0)), 1) as holiday_amazon_avg_weekly_orders,
    ROUND(SAFE_DIVIDE(r.holiday_amazon_orders, NULLIF(r.holiday_amazon_clicks, 0)) * 100, 2) as holiday_amazon_conversion_rate_pct

  FROM recent_sqp r
),

matched_brand_phrases AS (
  SELECT 
    t.*,
    bp.phrase_type AS matched_intent,
    bp.requested_product,
    bp.tag,
    bp.occasion as matched_occasion
  FROM term_base t
  LEFT JOIN `onyga-482313.OI.DIM_BRAND_PHRASES` bp
    ON STRPOS(LOWER(t.search_term), LOWER(bp.phrase)) > 0
  QUALIFY ROW_NUMBER() OVER (PARTITION BY t.search_term, t.asin ORDER BY bp.word_count DESC, LENGTH(bp.phrase) DESC) = 1
),

-- =============================================
-- DIMENSION 1: intent_segment (priority order)
-- =============================================
segmented AS (
  SELECT
    m.*,

    -- INTENT SEGMENT (first match wins)
    CASE
      -- EXACT MATCH FROM DIM_BRAND_PHRASES (BRAND or PRODUCT)
      WHEN m.matched_intent IS NOT NULL THEN m.matched_intent
      
      -- ASIN LOOKUP
      WHEN REGEXP_CONTAINS(m.search_term, r'^b0f9|^b09x|^b0c1|^b0cr|^b0dj|^b0d7|^b0f4')
        THEN 'BRAND'

      -- COMPETITOR: known competing brands
      WHEN REGEXP_CONTAINS(m.search_term, r'claires|clairs|claire\'s|american girl|barbie|cinnamoroll|rainbow high|sanrio|squishmallow|hello kitty|my melody|kuromi|pusheen|disney princess|bratz|polly pocket|crayola|lisa frank')
        THEN 'COMPETITOR'

      -- PRODUCT: exact product type Happy Lolli sells
      WHEN REGEXP_CONTAINS(m.search_term, r'journal kit|diary kit|journaling kit|journaling set|diary set|diy journal|notebook set|gift set for girl|gift box for girl|gift basket for girl|truth or dare|shower set|bath set|bath accessories for girl|spa set for girl')
        THEN 'PRODUCT'

      -- CATEGORY: browsing the product category
      WHEN REGEXP_CONTAINS(m.search_term, r'journal|diary|notebook|stationery|planner|writing set|pen set|art kit|craft kit|scrapbook|washi|marker set|coloring set')
        THEN 'CATEGORY'

      -- GIFT: gift shopping (not product-specific)
      WHEN REGEXP_CONTAINS(m.search_term, r'gift|present|for girls|year old girl|yr old girl|tween|teen girl|for kids|for daughter|for niece|for granddaughter')
        THEN 'GIFT'

      -- GENERIC: everything else
      ELSE 'GENERIC'
    END as intent_segment,

    -- Which intent rule matched (for debugging)
    CASE
      WHEN m.matched_intent = 'BRAND' THEN 'brand_phrase_match'
      WHEN m.matched_intent = 'PRODUCT' THEN 'brand_product_phrase_match'
      WHEN REGEXP_CONTAINS(m.search_term, r'^b0f9|^b09x|^b0c1|^b0cr|^b0dj|^b0d7|^b0f4') THEN 'asin_match'
      WHEN REGEXP_CONTAINS(m.search_term, r'claires|clairs|claire\'s|american girl|barbie|cinnamoroll|rainbow high|sanrio|squishmallow|hello kitty|my melody|kuromi|pusheen|disney princess|bratz|polly pocket|crayola|lisa frank') THEN 'competitor_brand'
      WHEN REGEXP_CONTAINS(m.search_term, r'journal kit|diary kit|journaling kit|journaling set|diary set|diy journal|notebook set') THEN 'product_journal_kit'
      WHEN REGEXP_CONTAINS(m.search_term, r'gift set for girl|gift box for girl|gift basket for girl') THEN 'product_gift_set'
      WHEN REGEXP_CONTAINS(m.search_term, r'truth or dare') THEN 'product_game'
      WHEN REGEXP_CONTAINS(m.search_term, r'shower set|bath set|bath accessories for girl|spa set for girl') THEN 'product_bath'
      WHEN REGEXP_CONTAINS(m.search_term, r'journal|diary|notebook|stationery|planner|writing set|pen set|art kit|craft kit|scrapbook|washi|marker set|coloring set') THEN 'category_match'
      WHEN REGEXP_CONTAINS(m.search_term, r'gift|present') THEN 'gift_keyword'
      WHEN REGEXP_CONTAINS(m.search_term, r'for girls|year old girl|yr old girl|tween|teen girl|for kids|for daughter|for niece|for granddaughter') THEN 'gift_audience'
      ELSE 'no_match'
    END as intent_rule,

    -- =============================================
    -- DIMENSION 2: occasion
    -- =============================================
    CASE
      WHEN m.matched_occasion IS NOT NULL THEN m.matched_occasion
      WHEN REGEXP_CONTAINS(m.search_term, r'birthday') THEN 'BIRTHDAY'
      WHEN REGEXP_CONTAINS(m.search_term, r'christmas|xmas|holiday gift|stocking stuffer|advent') THEN 'CHRISTMAS'
      WHEN REGEXP_CONTAINS(m.search_term, r'sleepover|slumber party|pajama party|bff night|pj party') THEN 'SLEEPOVER'
      WHEN REGEXP_CONTAINS(m.search_term, r'valentine|galentine') THEN 'VALENTINES'
      WHEN REGEXP_CONTAINS(m.search_term, r'easter') THEN 'EASTER'
      WHEN REGEXP_CONTAINS(m.search_term, r'back to school|school supplies') THEN 'BACK_TO_SCHOOL'
      WHEN REGEXP_CONTAINS(m.search_term, r'graduation|grad gift') THEN 'GRADUATION'
      WHEN REGEXP_CONTAINS(m.search_term, r'party') THEN 'PARTY'
      ELSE 'NO_OCCASION'
    END as occasion,

    -- =============================================
    -- DIMENSION 3: age_group
    -- =============================================
    CASE
      WHEN REGEXP_CONTAINS(m.search_term, r'college') THEN 'COLLEGE'
      WHEN REGEXP_CONTAINS(m.search_term, r'\b(5|6|7)\s*(year|yr)') THEN 'AGE_5_7'
      WHEN REGEXP_CONTAINS(m.search_term, r'\b(8|9|10)\s*(year|yr)|ages?\s*8|ages?\s*9|ages?\s*10|8[\s-]*1[0-2]|9[\s-]*1[0-2]') THEN 'AGE_8_10'
      WHEN REGEXP_CONTAINS(m.search_term, r'\b(11|12|13|14)\s*(year|yr)|ages?\s*1[1-4]|1[1-4][\s-]*1[4-8]') THEN 'AGE_11_14'
      WHEN REGEXP_CONTAINS(m.search_term, r'tween') THEN 'TWEEN'
      WHEN REGEXP_CONTAINS(m.search_term, r'\bteen\b|\b(15|16|17|18)\s*(year|yr)') THEN 'TEEN'
      ELSE 'NO_AGE'
    END as age_group,

    -- =============================================
    -- DIMENSION 4: product_match (which Happy Lolli product line)
    -- =============================================
    CASE
      -- Explicit exact matching from DIM logic wins primary resolution
      WHEN LOWER(m.requested_product) LIKE '%lollibox%' THEN 'LOLLIBOX_GIFT'
      WHEN LOWER(m.requested_product) LIKE '%lollime%' THEN 'LOLLIME_JOURNAL'
      WHEN LOWER(m.requested_product) LIKE '%truth or dare%' THEN 'TRUTH_OR_DARE'
      WHEN LOWER(m.requested_product) = 'fresh' THEN 'POWER_SHOWER'
      
      -- Count how many product lines match via regex
      WHEN (
        CASE WHEN REGEXP_CONTAINS(m.search_term, r'journal kit|diary kit|diy journal|journaling kit|journaling set|diary set|scrapbook kit|lockable diary|fuzzy diary|notebook set') THEN 1 ELSE 0 END
        + CASE WHEN REGEXP_CONTAINS(m.search_term, r'gift set|gift box|gift basket|wrapped gift|surprise box|unboxing|lollibox') THEN 1 ELSE 0 END
        + CASE WHEN REGEXP_CONTAINS(m.search_term, r'truth or dare|party game|sleepover game|screen.?free game') THEN 1 ELSE 0 END
        + CASE WHEN REGEXP_CONTAINS(m.search_term, r'shower set|bath set|bath accessories|spa set|body towel|hair towel|shower gift') THEN 1 ELSE 0 END
      ) > 1 THEN 'MULTI_MATCH'
      -- Single product match
      WHEN REGEXP_CONTAINS(m.search_term, r'journal kit|diary kit|diy journal|journaling kit|journaling set|diary set|scrapbook kit|lockable diary|fuzzy diary|notebook set') THEN 'LOLLIME_JOURNAL'
      WHEN REGEXP_CONTAINS(m.search_term, r'gift set|gift box|gift basket|wrapped gift|surprise box|unboxing|lollibox') THEN 'LOLLIBOX_GIFT'
      WHEN REGEXP_CONTAINS(m.search_term, r'truth or dare|party game|sleepover game|screen.?free game') THEN 'TRUTH_OR_DARE'
      WHEN REGEXP_CONTAINS(m.search_term, r'shower set|bath set|bath accessories|spa set|body towel|hair towel|shower gift') THEN 'POWER_SHOWER'
      ELSE 'NO_MATCH'
    END as product_match

  FROM matched_brand_phrases m
)

SELECT
  -- Keys
  CONCAT(s.search_term, '|', s.asin) as row_key,
  CONCAT(s.search_term, '|', s.asin) as search_term_key,
  CONCAT(s.asin, '|',
    -- experiment_segment inline (priority order, first match wins)
    CASE
      WHEN s.intent_segment = 'BRAND' THEN 'BRAND'
      WHEN s.intent_segment = 'PRODUCT' THEN 'PRODUCT'
      WHEN s.product_match NOT IN ('NO_MATCH', 'MULTI_MATCH') THEN 'PRODUCT'
      WHEN s.occasion IN ('SLEEPOVER', 'PARTY') THEN 'ACTIVITY'
      WHEN s.occasion = 'BIRTHDAY' AND s.age_group IN ('AGE_8_10', 'AGE_11_14') THEN 'BIRTHDAY_KIDS'
      WHEN s.occasion = 'BIRTHDAY' AND s.age_group IN ('TEEN', 'TWEEN') THEN 'BIRTHDAY_TEEN'
      WHEN s.occasion = 'BIRTHDAY' THEN 'BIRTHDAY_GENERAL'
      WHEN s.occasion IN ('CHRISTMAS', 'EASTER', 'VALENTINES', 'BACK_TO_SCHOOL', 'GRADUATION') THEN s.occasion
      WHEN s.age_group IN ('AGE_5_7', 'AGE_8_10', 'AGE_11_14') THEN 'GIFT_KIDS'
      WHEN s.age_group IN ('TEEN', 'TWEEN') THEN 'GIFT_TEEN'
      ELSE 'GIFT_GENERAL'
    END
  ) as asin_segment_key,

  s.search_term,
  s.asin,
  -- 4 Independent dimensions
  s.intent_segment,
  s.occasion,
  s.age_group,
  s.product_match,
  -- 5th derived dimension: experiment_segment (actionable grouping for experiment targeting)
  CASE
    WHEN s.intent_segment = 'BRAND' THEN 'BRAND'
    WHEN s.intent_segment = 'PRODUCT' THEN 'PRODUCT'
    WHEN s.product_match NOT IN ('NO_MATCH', 'MULTI_MATCH') THEN 'PRODUCT'
    WHEN s.occasion IN ('SLEEPOVER', 'PARTY') THEN 'ACTIVITY'
    WHEN s.occasion = 'BIRTHDAY' AND s.age_group IN ('AGE_8_10', 'AGE_11_14') THEN 'BIRTHDAY_KIDS'
    WHEN s.occasion = 'BIRTHDAY' AND s.age_group IN ('TEEN', 'TWEEN') THEN 'BIRTHDAY_TEEN'
    WHEN s.occasion = 'BIRTHDAY' THEN 'BIRTHDAY_GENERAL'
    WHEN s.occasion IN ('CHRISTMAS', 'EASTER', 'VALENTINES', 'BACK_TO_SCHOOL', 'GRADUATION') THEN s.occasion
    WHEN s.age_group IN ('AGE_5_7', 'AGE_8_10', 'AGE_11_14') THEN 'GIFT_KIDS'
    WHEN s.age_group IN ('TEEN', 'TWEEN') THEN 'GIFT_TEEN'
    ELSE 'GIFT_GENERAL'
  END as experiment_segment,
  -- Detailed tags propagated downstream
  s.requested_product,
  s.tag,
  -- Debug
  s.intent_rule,
  -- Non-holiday metrics (use these for regular experiment decisions)
  s.weeks_seen,
  s.non_holiday_weeks,
  s.weeks_with_your_orders,
  s.your_total_orders,
  s.your_total_clicks,
  s.ads_total_orders,
  s.ads_total_clicks,
  s.amazon_avg_weekly_orders,
  s.amazon_conversion_rate_pct,
  s.amazon_ctr_pct,
  s.your_impressions_share_pct,
  s.your_orders_share_pct,
  s.your_clicks_share_pct,
  -- Conversion rates (recency-weighted: 1mo=3x, 1-3mo=2x, 3-12mo=1x)
  ROUND(SAFE_DIVIDE(s.w_your_orders, NULLIF(s.w_your_clicks, 0)) * 100, 2) as your_conversion_rate_pct,
  ROUND(SAFE_DIVIDE(s.w_ads_orders, NULLIF(s.w_ads_clicks, 0)) * 100, 2) as ads_conversion_rate_pct,

  -- Holiday metrics (use these for seasonal/pre-holiday experiment decisions)
  s.holiday_weeks,
  s.holiday_weeks_with_your_orders,
  s.holiday_your_total_orders,
  s.holiday_your_total_clicks,
  s.holiday_ads_total_orders,
  s.holiday_ads_total_clicks,
  s.holiday_amazon_avg_weekly_orders,
  s.holiday_amazon_conversion_rate_pct,
  ROUND(SAFE_DIVIDE(s.holiday_your_total_orders, NULLIF(s.holiday_your_total_clicks, 0)) * 100, 2) as holiday_your_conversion_rate_pct,
  ROUND(SAFE_DIVIDE(s.holiday_ads_total_orders, NULLIF(s.holiday_ads_total_clicks, 0)) * 100, 2) as holiday_ads_conversion_rate_pct,
  -- Season awareness: is this term's occasion currently relevant?
  CASE
    WHEN s.occasion IN ('CHRISTMAS', 'VALENTINES', 'BACK_TO_SCHOOL', 'EASTER')
      THEN EXISTS (
        SELECT 1 FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
        WHERE CURRENT_DATE() BETWEEN h.pre_season_start AND h.holiday_date
          AND (
            (s.occasion = 'CHRISTMAS' AND h.holiday_name IN ('Christmas', 'Black Friday', 'Cyber Monday'))
            OR (s.occasion = 'VALENTINES' AND h.holiday_name = 'Valentines Day')
            OR (s.occasion = 'BACK_TO_SCHOOL' AND h.holiday_name = 'Back to School')
            OR (s.occasion = 'EASTER' AND h.holiday_name = 'Easter')
          )
      )
    ELSE TRUE  -- BIRTHDAY, SLEEPOVER, PARTY, GRADUATION, NO_OCCASION = always in season
  END as is_occasion_in_season,
  -- Product context (from DIM_PRODUCT)
  p.product_short_name,
  p.product_type,

  -- Best ASIN selection: for each search term, which ASIN should own it?
  -- Score = proven_orders * conversion_advantage (your rate / amazon rate)
  -- If your conversion > amazon conversion, organic winning chance is higher
  ROW_NUMBER() OVER (
    PARTITION BY s.search_term
    ORDER BY
      -- Composite: proven volume * conversion advantage vs market
      (COALESCE(s.your_total_orders, 0) + COALESCE(s.ads_total_orders, 0))
      * COALESCE(
          SAFE_DIVIDE(
            GREATEST(
              COALESCE(SAFE_DIVIDE(s.w_your_orders, NULLIF(s.w_your_clicks, 0)), 0),
              COALESCE(SAFE_DIVIDE(s.w_ads_orders, NULLIF(s.w_ads_clicks, 0)), 0)
            ),
            NULLIF(s.amazon_conversion_rate_pct / 100.0, 0)
          ),
          0
        )
      DESC,
      -- Tiebreaker: organic visibility
      COALESCE(s.your_impressions_share_pct, 0) DESC
  ) as asin_rank_for_term,
  ROW_NUMBER() OVER (
    PARTITION BY s.search_term
    ORDER BY
      (COALESCE(s.your_total_orders, 0) + COALESCE(s.ads_total_orders, 0))
      * COALESCE(
          SAFE_DIVIDE(
            GREATEST(
              COALESCE(SAFE_DIVIDE(s.w_your_orders, NULLIF(s.w_your_clicks, 0)), 0),
              COALESCE(SAFE_DIVIDE(s.w_ads_orders, NULLIF(s.w_ads_clicks, 0)), 0)
            ),
            NULLIF(s.amazon_conversion_rate_pct / 100.0, 0)
          ),
          0
        )
      DESC,
      COALESCE(s.your_impressions_share_pct, 0) DESC
  ) = 1 as is_best_asin_for_term

FROM segmented s
LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON s.asin = p.asin;
