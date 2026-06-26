-- DE_KEYWORD_INTENT_OVERRIDE — manual corrections to a keyword's intent class (BRAND/PRODUCT/GENERIC)
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_KEYWORD_INTENT_OVERRIDE` (
  parent_name   STRING NOT NULL,
  keyword_text  STRING NOT NULL,   -- store LOWER(text)
  intent_class  STRING NOT NULL,   -- BRAND / PRODUCT / GENERIC
  updated_at    TIMESTAMP,
  updated_by    STRING
)
OPTIONS (description = 'Manual override of keyword intent class; wins over V_KEYWORD_INTENT_CLASS derivation.');
