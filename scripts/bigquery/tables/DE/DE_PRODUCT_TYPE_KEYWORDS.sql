-- DE_PRODUCT_TYPE_KEYWORDS
-- Maps keywords to product types for search term classification.
-- Used by V_SQP_QUERY_WEEKLY to classify query_text into product_type.
-- Priority controls which type wins when a term matches multiple keywords (lower = wins).
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_PRODUCT_TYPE_KEYWORDS` (
  keyword STRING NOT NULL,
  product_type STRING NOT NULL,
  priority INT64 NOT NULL
);
