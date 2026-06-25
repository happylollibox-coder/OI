-- DE_PRODUCT_MAIN_KEYWORDS — per-product anchor keywords (derived top terms; editable)
-- Append/update only — NEVER CREATE OR REPLACE (preserves source='MANUAL' rows).
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_PRODUCT_MAIN_KEYWORDS` (
  parent_name    STRING NOT NULL,
  keyword_text   STRING NOT NULL,
  keyword_id     STRING,
  match_type     STRING NOT NULL,          -- BROAD/EXACT/PHRASE/AUTO/PRODUCT
  rank           INT64,                     -- 1 = top anchor within (parent, match_type)
  net_profit_90d FLOAT64,
  is_anchor      BOOL DEFAULT TRUE,
  source         STRING NOT NULL,           -- DERIVED / MANUAL
  updated_at     TIMESTAMP,
  updated_by     STRING
)
OPTIONS (description = 'Per-product anchor keywords for the coacher strategy profile. Derived by tools/strategy_profile; MANUAL rows preserved. See docs/superpowers/specs/2026-06-25-per-product-strategy-profile-design.md');
