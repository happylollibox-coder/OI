CREATE OR REPLACE VIEW `onyga-482313`.OI.V_SQP_QUERY_WEEKLY AS

/*
  V_SQP_QUERY_WEEKLY
  ------------------
  Weekly search query performance at query_text grain.

  - TOTAL_* columns = market-wide totals (deduplicated via MAX since
    they are identical across ASINs for the same query + week).
  - BRAND_* columns = our brand's aggregate across all our ASINs.
  - Segmentation columns = FN_EXTRACT_SEGMENTS (single-source taxonomy)
    + DE_PRODUCT_TYPE_KEYWORDS lookup, with manual overrides from
    DE_SEARCH_TERM_SEGMENTS winning via COALESCE (Research page editor).

  Grain: (Year, Week, week_start_date, week_end_date, query_text)
  Source: FACT_SEARCH_QUERY
  SOP: architecture/RESEARCH_PAGE.md
*/

WITH base AS (
  SELECT
    Year,
    Week,
    week_start_date,
    week_end_date,
    query_text,

    -- Market totals (same value per ASIN → deduplicate via MAX)
    MAX(TOTAL_IMPRESSIONS)  AS TOTAL_IMPRESSIONS,
    MAX(TOTAL_CLICKS)       AS TOTAL_CLICKS,
    MAX(TOTAL_CART_ADDS)    AS TOTAL_CART_ADDS,
    MAX(TOTAL_PURCHASES)    AS TOTAL_PURCHASES,
    MAX(total_median_click_price) AS TOTAL_MEDIAN_CLICK_PRICE,
    MAX(search_query_volume) AS search_query_volume,

    -- Brand totals (sum across our ASINs)
    SUM(impressions)    AS BRAND_IMPRESSIONS,
    SUM(clicks)         AS BRAND_CLICKS,
    SUM(cart_adds)      AS BRAND_CART_ADDS,
    SUM(conversions)    AS BRAND_PURCHASES,
    SUM(sales_amount)   AS BRAND_SALES,

    -- ── Segmentation: Cost Tier ──
    CASE
      WHEN MAX(total_median_click_price) < 10   THEN 'Budget (<$10)'
      WHEN MAX(total_median_click_price) < 20   THEN 'Value ($10-$20)'
      WHEN MAX(total_median_click_price) < 35   THEN 'Mid ($20-$35)'
      WHEN MAX(total_median_click_price) < 50   THEN 'Premium ($35-$50)'
      WHEN MAX(total_median_click_price) >= 50  THEN 'Luxury ($50+)'
      ELSE NULL
    END AS cost_tier,

    -- ── Segmentation: gender / age_group / occasion / holiday ──
    -- Single source of truth: FN_EXTRACT_SEGMENTS
    `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(query_text) AS seg,

    -- ── Segmentation: Brand ──
    -- Own-brand patterns sourced from V_BRAND_KEYWORD_CLASSIFICATION logic
    CASE
      WHEN LOWER(query_text) LIKE '%happy lolli%'
        OR LOWER(query_text) LIKE '%happylolli%'
        OR LOWER(query_text) LIKE '%happy lollipop%'
        OR LOWER(query_text) LIKE '%truth or dare%'
        OR LOWER(query_text) LIKE '%lollibox%'
        OR LOWER(query_text) LIKE '%lollime%'
        OR LOWER(query_text) LIKE '%lolli me%'
        OR LOWER(query_text) LIKE '%fresh in beige%'
        OR LOWER(query_text) LIKE '%fresh in pink%'
        OR EXISTS(
          SELECT 1 FROM (
            SELECT DISTINCT LOWER(product_short_name) AS pattern
            FROM `onyga-482313`.OI.DIM_PRODUCT
            WHERE product_short_name IS NOT NULL AND product_short_name != 'Unknown'
          ) bp WHERE LOWER(query_text) LIKE CONCAT('%', bp.pattern, '%')
        )
        THEN 'Happy Lolli'
      -- Competitor brands
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'(l\.o\.l|lol surprise|lol doll)') THEN 'L.O.L Surprise'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(disney|frozen|elsa|moana|ariel|rapunzel|encanto|mirabel)\b') THEN 'Disney'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'\bbarbie\b') THEN 'Barbie'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(squishmallow|squishmallows)\b') THEN 'Squishmallows'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(hello kitty|sanrio|kuromi|cinnamoroll|my melody)\b') THEN 'Sanrio'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(pokemon|pokemone?|pikachu)\b') THEN 'Pokemon'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(taylor swift|swiftie)\b') THEN 'Taylor Swift'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(minecraft)\b') THEN 'Minecraft'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(roblox)\b') THEN 'Roblox'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(unicorn|unicorns)\b') THEN 'Unicorn'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(bluey)\b') THEN 'Bluey'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(gabby.s dollhouse|gabby)\b') THEN 'Gabbys Dollhouse'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(paw patrol)\b') THEN 'Paw Patrol'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(harry potter|hogwarts)\b') THEN 'Harry Potter'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(lego)\b') THEN 'LEGO'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(hot wheels)\b') THEN 'Hot Wheels'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(bratz)\b') THEN 'Bratz'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(marvel|spider.?man|avengers|hulk)\b') THEN 'Marvel'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(star wars|darth vader|yoda|mandalorian|grogu)\b') THEN 'Star Wars'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(cocomelon)\b') THEN 'CoComelon'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(peppa pig)\b') THEN 'Peppa Pig'
      WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(labubu|pop mart|popmart)\b') THEN 'Labubu/Pop Mart'
      ELSE NULL
    END AS brand

  FROM `onyga-482313`.OI.FACT_SEARCH_QUERY

  GROUP BY
    Year,
    Week,
    week_start_date,
    week_end_date,
    query_text
),

-- ── Product Type lookup from DE_PRODUCT_TYPE_KEYWORDS ──
-- Find the best-matching keyword per query_text (lowest priority wins, longest keyword breaks ties).
product_type_lookup AS (
  SELECT
    b.query_text,
    ARRAY_AGG(ptk.product_type ORDER BY ptk.priority ASC, LENGTH(ptk.keyword) DESC LIMIT 1)[OFFSET(0)] AS product_type
  FROM base b
  CROSS JOIN `onyga-482313.OI.DE_PRODUCT_TYPE_KEYWORDS` ptk
  WHERE REGEXP_CONTAINS(LOWER(b.query_text), CONCAT(r'(?:^|\W)', ptk.keyword, r'(?:\W|$)'))
  GROUP BY b.query_text
)

SELECT
  b.* EXCEPT(seg, cost_tier, brand),
  COALESCE(o.gender,       b.seg.gender)     AS gender,
  COALESCE(o.age_group,    b.seg.age_group)  AS age_group,
  COALESCE(o.occasion,     b.seg.occasion)   AS occasion,
  b.seg.holiday                              AS holiday,
  COALESCE(o.cost_tier,    b.cost_tier)      AS cost_tier,
  COALESCE(o.brand,        b.brand)          AS brand,
  COALESCE(o.product_type, ptl.product_type) AS product_type
FROM base b
LEFT JOIN product_type_lookup ptl ON b.query_text = ptl.query_text
LEFT JOIN (
  -- Manual overrides from the Research page editor (latest row per term wins)
  SELECT query_text, gender, age_group, occasion, cost_tier, product_type, brand
  FROM `onyga-482313`.OI.DE_SEARCH_TERM_SEGMENTS
  QUALIFY ROW_NUMBER() OVER (PARTITION BY LOWER(query_text) ORDER BY updated_at DESC) = 1
) o ON LOWER(o.query_text) = LOWER(b.query_text)
