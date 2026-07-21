-- One row per (scope) the user has marked NOT expected, to suppress false "missing" coverage cells.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_COVERAGE_EXPECTATION` (
  id           STRING NOT NULL,          -- uuid
  scope_grain  STRING NOT NULL,          -- 'STRATEGY' | 'FAMILY_STRATEGY' | 'INTENT_CELL'
  parent_name  STRING,                   -- family (NULL for store-wide)
  strategy     STRING NOT NULL,          -- AUTO|INTENT|EXACT_BOOST|COMPETITOR|BRAND_DEFENSE|PRODUCT_DEFENSE
  intent_key   STRING,                   -- NULL unless scope_grain='INTENT_CELL'
  match_type   STRING,                   -- NULL unless intent-cell needs it
  is_active    BOOL NOT NULL,            -- FALSE = tombstone (un-suppress)
  reason       STRING,
  updated_by   STRING,
  updated_at   TIMESTAMP NOT NULL
);
