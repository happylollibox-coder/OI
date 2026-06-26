-- DE_PRODUCT_CATEGORY_TERMS — per-family lowercase regex of product-category terms (PRODUCT intent). Editable.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_PRODUCT_CATEGORY_TERMS` (
  parent_name    STRING NOT NULL,
  category_regex STRING NOT NULL,
  updated_at     TIMESTAMP,
  updated_by     STRING
)
OPTIONS (description = 'Per-family product-category term regex; a non-brand keyword matching it is PRODUCT intent (else GENERIC).');
