-- =============================================
-- SP_DERIVE_PRODUCT_SEGMENTS
-- =============================================
--
-- Purpose: Auto-derives product segmentation from ad purchase data.
--          Looks at which search terms each product sells on,
--          applies regex segmentation, and aggregates into
--          comma-separated values per parent_name.
--
-- Parameters:
--   p_parent_name: NULL = derive for all products, or specific parent
--
-- Logic:
--   1. Join FACT_AMAZON_ADS (purchases > 0) with FN_EXTRACT_SEGMENTS
--      (single-source taxonomy) + DE_PRODUCT_TYPE_KEYWORDS (canonical
--      product_type vocabulary — same values the term tagging uses,
--      so seg_product_type matching in V_RESEARCH_RANKED works)
--   2. Count purchases per segment value per parent
--   3. Keep values with >= 5% of total purchases for that parent
--   4. UPDATE DIM_PRODUCT only where seg_* IS NULL (preserve manual overrides)
--
-- Dependencies:
--   FACT_AMAZON_ADS, DIM_PRODUCT, FN_EXTRACT_SEGMENTS, DE_PRODUCT_TYPE_KEYWORDS
-- SOP: architecture/RESEARCH_PAGE.md
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313`.OI.SP_DERIVE_PRODUCT_SEGMENTS(
  p_parent_name STRING
)
BEGIN

  -- ═══ 1. Tag each ad purchase row with segments ═══
  -- Taxonomy via FN_EXTRACT_SEGMENTS; product_type via DE_PRODUCT_TYPE_KEYWORDS
  -- (canonical vocabulary, matching the term-side tagging in V_SQP_QUERY_WEEKLY)
  CREATE TEMP TABLE _tagged AS
  SELECT
    p.parent_name,
    a.search_term,
    a.Ads_orders,
    `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(a.search_term).gender    AS gender,
    `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(a.search_term).age_group AS age_group,
    `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(a.search_term).occasion  AS occasion,
    ptl.product_type
  FROM `onyga-482313`.OI.FACT_AMAZON_ADS a
  JOIN `onyga-482313`.OI.DIM_PRODUCT p
    ON COALESCE(a.most_advertised_asin_impressions, a.ASIN_BY_CAMPAIGN_NAME) = p.asin
  LEFT JOIN (
    SELECT
      t.search_term,
      ARRAY_AGG(ptk.product_type ORDER BY ptk.priority ASC, LENGTH(ptk.keyword) DESC LIMIT 1)[OFFSET(0)] AS product_type
    FROM (
      SELECT DISTINCT search_term
      FROM `onyga-482313`.OI.FACT_AMAZON_ADS
      WHERE Ads_orders > 0
    ) t
    CROSS JOIN `onyga-482313.OI.DE_PRODUCT_TYPE_KEYWORDS` ptk
    WHERE REGEXP_CONTAINS(LOWER(t.search_term), CONCAT(r'(?:^|\W)', ptk.keyword, r'(?:\W|$)'))
    GROUP BY t.search_term
  ) ptl ON ptl.search_term = a.search_term
  WHERE a.Ads_orders > 0
    AND p.parent_name IS NOT NULL
    AND p.is_active = true
    AND (p_parent_name IS NULL OR p.parent_name = p_parent_name);

  -- ═══ 2. Aggregate: total purchases per parent ═══
  CREATE TEMP TABLE _parent_totals AS
  SELECT parent_name, SUM(Ads_orders) AS total_orders
  FROM _tagged
  GROUP BY parent_name;

  -- ═══ 3. Derive segments with ≥ 5% threshold ═══
  CREATE TEMP TABLE _derived AS
  WITH
  gender_agg AS (
    SELECT t.parent_name, t.gender AS val, SUM(t.Ads_orders) AS seg_orders
    FROM _tagged t WHERE t.gender IS NOT NULL
    GROUP BY t.parent_name, t.gender
  ),
  age_agg AS (
    SELECT t.parent_name, t.age_group AS val, SUM(t.Ads_orders) AS seg_orders
    FROM _tagged t WHERE t.age_group IS NOT NULL
    GROUP BY t.parent_name, t.age_group
  ),
  occasion_agg AS (
    SELECT t.parent_name, t.occasion AS val, SUM(t.Ads_orders) AS seg_orders
    FROM _tagged t WHERE t.occasion IS NOT NULL
    GROUP BY t.parent_name, t.occasion
  ),
  ptype_agg AS (
    SELECT t.parent_name, t.product_type AS val, SUM(t.Ads_orders) AS seg_orders
    FROM _tagged t WHERE t.product_type IS NOT NULL
    GROUP BY t.parent_name, t.product_type
  ),
  -- Filter to >= 5% threshold and aggregate to comma-separated
  gender_csv AS (
    SELECT g.parent_name,
      STRING_AGG(g.val ORDER BY g.seg_orders DESC) AS seg_gender
    FROM gender_agg g
    JOIN _parent_totals pt ON pt.parent_name = g.parent_name
    WHERE SAFE_DIVIDE(g.seg_orders, pt.total_orders) >= 0.05
    GROUP BY g.parent_name
  ),
  age_csv AS (
    SELECT a.parent_name,
      STRING_AGG(a.val ORDER BY a.seg_orders DESC) AS seg_age_group
    FROM age_agg a
    JOIN _parent_totals pt ON pt.parent_name = a.parent_name
    WHERE SAFE_DIVIDE(a.seg_orders, pt.total_orders) >= 0.05
    GROUP BY a.parent_name
  ),
  occasion_csv AS (
    SELECT o.parent_name,
      STRING_AGG(o.val ORDER BY o.seg_orders DESC) AS seg_occasion
    FROM occasion_agg o
    JOIN _parent_totals pt ON pt.parent_name = o.parent_name
    WHERE SAFE_DIVIDE(o.seg_orders, pt.total_orders) >= 0.05
    GROUP BY o.parent_name
  ),
  ptype_csv AS (
    SELECT p.parent_name,
      STRING_AGG(p.val ORDER BY p.seg_orders DESC) AS seg_product_type
    FROM ptype_agg p
    JOIN _parent_totals pt ON pt.parent_name = p.parent_name
    WHERE SAFE_DIVIDE(p.seg_orders, pt.total_orders) >= 0.05
    GROUP BY p.parent_name
  )
  SELECT
    pt.parent_name,
    g.seg_gender,
    a.seg_age_group,
    o.seg_occasion,
    p.seg_product_type
  FROM _parent_totals pt
  LEFT JOIN gender_csv g ON g.parent_name = pt.parent_name
  LEFT JOIN age_csv a ON a.parent_name = pt.parent_name
  LEFT JOIN occasion_csv o ON o.parent_name = pt.parent_name
  LEFT JOIN ptype_csv p ON p.parent_name = pt.parent_name;

  -- ═══ 4. UPDATE DIM_PRODUCT — only where seg_* IS NULL (preserve manual) ═══
  UPDATE `onyga-482313`.OI.DIM_PRODUCT dp
  SET
    dp.seg_gender      = COALESCE(dp.seg_gender, d.seg_gender),
    dp.seg_age_group   = COALESCE(dp.seg_age_group, d.seg_age_group),
    dp.seg_occasion    = COALESCE(dp.seg_occasion, d.seg_occasion),
    dp.seg_product_type = COALESCE(dp.seg_product_type, d.seg_product_type)
  FROM _derived d
  WHERE dp.parent_name = d.parent_name
    AND dp.is_active = true;

  -- ═══ 5. Cleanup ═══
  DROP TABLE IF EXISTS _tagged;
  DROP TABLE IF EXISTS _parent_totals;
  DROP TABLE IF EXISTS _derived;

END;
