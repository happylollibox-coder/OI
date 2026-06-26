-- V_KEYWORD_INTENT_CLASS — classify each ad keyword per parent as BRAND / PRODUCT / GENERIC.
-- BRAND: contains a DIM_BRAND_PHRASES BRAND phrase.
-- PRODUCT: not brand AND (is an anchor OR matches DE_PRODUCT_CATEGORY_TERMS category_regex for the family).
-- GENERIC: everything else.  DE_KEYWORD_INTENT_OVERRIDE wins.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_KEYWORD_INTENT_CLASS` AS
WITH camp_parent AS (
  SELECT campaign_id, parent_name FROM (
    SELECT a.campaign_id, p.parent_name,
      ROW_NUMBER() OVER (PARTITION BY a.campaign_id ORDER BY SUM(a.Ads_cost) DESC) rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
    JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
    WHERE a.date >= DATE('2025-09-23') GROUP BY a.campaign_id, p.parent_name
  ) WHERE rn = 1
),
kw AS (
  SELECT DISTINCT cp.parent_name, LOWER(a.targeting) AS keyword_text
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN camp_parent cp ON cp.campaign_id = a.campaign_id
  WHERE a.targeting IS NOT NULL AND a.targeting != ''
),
brand AS (
  SELECT k.parent_name, k.keyword_text, TRUE AS is_brand
  FROM kw k
  WHERE EXISTS (SELECT 1 FROM `onyga-482313.OI.DIM_BRAND_PHRASES` b
                WHERE b.phrase_type = 'BRAND' AND STRPOS(k.keyword_text, LOWER(b.phrase)) > 0)
),
anchor AS (
  SELECT DISTINCT parent_name, LOWER(keyword_text) AS keyword_text
  FROM `onyga-482313.OI.DE_PRODUCT_MAIN_KEYWORDS` WHERE is_anchor
),
cat AS (
  SELECT parent_name, category_regex FROM `onyga-482313.OI.DE_PRODUCT_CATEGORY_TERMS`
)
SELECT kw.parent_name, kw.keyword_text,
  COALESCE(ov.intent_class,
    CASE WHEN b.is_brand THEN 'BRAND'
         WHEN an.keyword_text IS NOT NULL
              OR (c.category_regex IS NOT NULL AND REGEXP_CONTAINS(kw.keyword_text, c.category_regex)) THEN 'PRODUCT'
         ELSE 'GENERIC' END) AS intent_class
FROM kw
LEFT JOIN brand  b  ON b.parent_name=kw.parent_name AND b.keyword_text=kw.keyword_text
LEFT JOIN anchor an ON an.parent_name=kw.parent_name AND an.keyword_text=kw.keyword_text
LEFT JOIN cat    c  ON c.parent_name=kw.parent_name
LEFT JOIN `onyga-482313.OI.DE_KEYWORD_INTENT_OVERRIDE` ov
  ON ov.parent_name=kw.parent_name AND LOWER(ov.keyword_text)=kw.keyword_text;
