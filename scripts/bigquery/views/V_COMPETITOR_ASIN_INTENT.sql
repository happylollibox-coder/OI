-- V_COMPETITOR_ASIN_INTENT — competitor ASIN -> intent, derived from the product NAME.
--
-- Ori 2026-07-23: competitor campaigns are split by intent (<=10 ASINs each) and the intent comes
-- from the competitor product name. This reuses DE_INTENT_THEMES — the SAME rule table that routes
-- search terms — so competitor ASINs land in the same intent vocabulary as everything else.
--
-- The product name is first run through FN_EXTRACT_SEGMENTS, which pulls age_group / occasion /
-- holiday out of free text (e.g. "DIY Journal Kit for Girls Ages 8-12 Birthday Gift" -> Tween,
-- Birthday). Those segments then feed the FULL AND-match that DE_INTENT_THEMES expects.
--
-- Matching on match_keyword_regex ALONE is wrong and was the first thing I got wrong here: every
-- rule containing \bgifts?\b matched a journal title, so it came back "Easter Gift" and "Christmas
-- Gift" simultaneously. A rule only matches when ALL of its non-null match_* conditions hold.
--
-- Ties break on specificity (most conditions satisfied, then longest regex), mirroring the routing
-- V_INTENT_KEYWORDS uses, so 'tween-birthday-gift' beats bare 'gift'.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_COMPETITOR_ASIN_INTENT` AS
WITH seg AS (
  SELECT asin, product_name,
    `onyga-482313.OI.FN_EXTRACT_SEGMENTS`(product_name) AS s
  FROM `onyga-482313.OI.DE_COMPETITOR_PRODUCT`
  WHERE product_name IS NOT NULL AND product_name != ''
),
matched AS (
  SELECT
    g.asin, g.product_name, t.intent_key, t.label AS intent_label,
    -- specificity: how many conditions the rule actually pins down
    (IF(t.match_occasion     IS NOT NULL, 1, 0)
   + IF(t.match_holiday      IS NOT NULL, 1, 0)
   + IF(t.match_product_type IS NOT NULL, 1, 0)
   + IF(t.match_age_group    IS NOT NULL, 1, 0)
   + IF(t.match_keyword_regex IS NOT NULL, 1, 0)) AS n_conditions,
    LENGTH(COALESCE(t.match_keyword_regex, '')) AS regex_len
  FROM seg g
  JOIN `onyga-482313.OI.DE_INTENT_THEMES` t
    ON (t.match_occasion     IS NULL OR t.match_occasion  = g.s.occasion)
   AND (t.match_holiday      IS NULL OR t.match_holiday   = g.s.holiday)
   AND (t.match_age_group    IS NULL OR t.match_age_group = g.s.age_group)
   -- product_type has no counterpart in a free-text title, so a rule that pins it cannot be
   -- confirmed from a name alone; require it to be absent rather than guess.
   AND t.match_product_type IS NULL
   AND (t.match_keyword_regex IS NULL
        OR REGEXP_CONTAINS(LOWER(g.product_name), t.match_keyword_regex))
   -- never match a rule that pins nothing: that would tag every product with the same intent
   AND (t.match_occasion IS NOT NULL OR t.match_holiday IS NOT NULL
        OR t.match_age_group IS NOT NULL OR t.match_keyword_regex IS NOT NULL)
)
SELECT asin, product_name, intent_key, intent_label
FROM matched
QUALIFY ROW_NUMBER() OVER (PARTITION BY asin ORDER BY n_conditions DESC, regex_len DESC, intent_key) = 1;
