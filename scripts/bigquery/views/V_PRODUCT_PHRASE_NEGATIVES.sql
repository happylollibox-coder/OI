-- =============================================
-- OI Database Project - V_PRODUCT_PHRASE_NEGATIVES
-- =============================================
--
-- Purpose: Query view over DE_PRODUCT_PHRASE_NEGATIVES with resolution logic.
--          Returns the effective negative phrases for a given product.
--
-- Resolution:
--   1. '_ALL' rows always included (apply to every family)
--   2. Family-level rows (product_short_name IS NULL) included
--   3. If a product-level INACTIVE override exists, family phrase is excluded
--
-- Usage (in bulksheet generation):
--   SELECT phrase, match_type
--   FROM V_PRODUCT_PHRASE_NEGATIVES
--   WHERE effective_parent_name = 'Lollibox'  -- or parameterize
--
-- Defense exclusion is NOT enforced here — it's enforced at
-- bulksheet generation time by the skill/script.
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_PRODUCT_PHRASE_NEGATIVES`
AS
WITH

-- All active phrases (family-level + _ALL)
family_phrases AS (
  SELECT
    parent_name,
    product_short_name,
    phrase,
    match_type,
    source,
    status,
    created_at
  FROM `onyga-482313.OI.DE_PRODUCT_PHRASE_NEGATIVES`
  WHERE status = 'ACTIVE'
),

-- Product-level overrides (INACTIVE = exclusion for a specific product)
product_overrides AS (
  SELECT
    parent_name,
    product_short_name,
    phrase,
    status
  FROM `onyga-482313.OI.DE_PRODUCT_PHRASE_NEGATIVES`
  WHERE product_short_name IS NOT NULL
    AND status = 'INACTIVE'
),

-- Expand _ALL phrases to each known family
known_families AS (
  SELECT DISTINCT family AS parent_name
  FROM `onyga-482313.OI.V_PRODUCT_FAMILY_MAP`
),

all_expanded AS (
  SELECT
    kf.parent_name AS effective_parent_name,
    fp.phrase,
    fp.match_type,
    fp.source,
    '_ALL' AS origin_level
  FROM family_phrases fp
  CROSS JOIN known_families kf
  WHERE fp.parent_name = '_ALL'
    AND fp.product_short_name IS NULL
),

-- Family-level phrases
family_level AS (
  SELECT
    fp.parent_name AS effective_parent_name,
    fp.phrase,
    fp.match_type,
    fp.source,
    'FAMILY' AS origin_level
  FROM family_phrases fp
  WHERE fp.parent_name != '_ALL'
    AND fp.product_short_name IS NULL
),

-- Product-level active additions
product_level AS (
  SELECT
    fp.parent_name AS effective_parent_name,
    fp.phrase,
    fp.match_type,
    fp.source,
    'PRODUCT' AS origin_level
  FROM family_phrases fp
  WHERE fp.product_short_name IS NOT NULL
),

-- Union all levels
combined AS (
  SELECT * FROM all_expanded
  UNION ALL
  SELECT * FROM family_level
  UNION ALL
  SELECT * FROM product_level
)

SELECT DISTINCT
  c.effective_parent_name,
  c.phrase,
  c.match_type,
  c.source,
  c.origin_level
FROM combined c
ORDER BY
  c.effective_parent_name,
  c.match_type,
  c.phrase;
