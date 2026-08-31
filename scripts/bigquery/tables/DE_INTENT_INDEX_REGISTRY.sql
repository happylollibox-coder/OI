-- DE_INTENT_INDEX_REGISTRY: which multiplicative indexes the intent CVR curve is allowed to apply.
--
-- WHY A TABLE AND NOT A LIST IN THE VIEW
-- The curve stops being `base_cvr x hardcoded season_index` and becomes
-- `calibration x base_cvr x PRODUCT(active indexes)`. If the set of active indexes lived in the
-- view's SQL, turning one off would be a deploy, and the record of what was live on any given day
-- would be a git archaeology exercise. One row per index makes the active set data, so the
-- scorecard can score it and a human can flip it.
--
-- THE CONTRACT — AUTOMATION PROPOSES, A HUMAN PROMOTES
--   SP_SCORE_INTENT_INDEXES scores every index, active or not, every month, and writes its
--   verdict to V_INTENT_INDEX_SCORECARD. It NEVER writes is_active.
--   is_active belongs to a human, exactly as verified_* does in DE_SEARCH_TERM_INTENT. The reason
--   is not ceremony: the Coacher has twice made unreviewed bid changes that lost money (the
--   08-02 auto-target blowout, -$753, and the $1.00 activation floor), and an index that silently
--   promotes itself moves every bid in the catalog at once.
--
-- COLUMNS
--   index_name    the key. Must be unique — a duplicate would apply the same multiplier twice
--                 and square it. Enforced by acceptance R01, not by the schema.
--   source_object the view publishing (join_keys, index_value, support_clicks) for this index.
--   join_keys     the grain, comma-separated, e.g. 'intent_type,month_of_year'. Declared here so
--                 the curve joins on what the index actually promises rather than on assumption.
--   is_active     whether the curve multiplies by it. Human-owned. See the contract above.
--
-- Every index must be normalised to a clicks-weighted mean of 1.000 before it may go active,
-- otherwise it shifts the whole catalog's level and INTENT_CVR_CALIBRATION quietly absorbs the
-- shift, hiding the change from the scorecard. Acceptance R03 is what checks that.
--
-- Thresholds this registry works with live in DE_COACH_THRESHOLDS under strategy_id = 'INTENT',
-- seeded by scripts/bigquery/migrations/2026-08-31_intent_index_registry.sql.
--
-- Acceptance: scripts/bigquery/tests/INTENT_INDEX_acceptance.sql
-- Spec: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md
-- Created: 2026-08-31

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_INTENT_INDEX_REGISTRY` (
  index_name    STRING  NOT NULL,
  description   STRING,
  source_object STRING  NOT NULL,
  join_keys     STRING  NOT NULL,
  is_active     BOOL    NOT NULL,
  added_at      TIMESTAMP,
  added_by      STRING,
  notes         STRING
);
