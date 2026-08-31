-- 2026-08-31 — Task 1 of the intent CVR index registry: the registry table plus the threshold
-- rows the rebuilt curve reads. Nothing consumes these yet; the shadow curve arrives in a later
-- task. Spec: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md
--
-- Index registry for the intent CVR curve. Automation proposes, a human promotes:
-- SP_SCORE_INTENT_INDEXES never writes is_active. Same contract as DE_SEARCH_TERM_INTENT.
-- Re-runnable: CREATE IF NOT EXISTS + DELETE/INSERT + idempotent UPDATE.
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

DELETE FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
WHERE strategy_id = 'INTENT'
  AND threshold_key IN ('INTENT_CVR_CALIBRATION','INTENT_IDX_MIN_SUPPORT','INTENT_IDX_MIN_SCORED_CLICKS');

-- Column list matches the sibling seed migration 2026-07-24_intent_cvr_curve_thresholds.sql so
-- these rows carry a description like every other threshold. Only threshold_key, strategy_id and
-- threshold_value are REQUIRED on the table; the rest are documentation and provenance.
INSERT INTO `onyga-482313.OI.DE_COACH_THRESHOLDS`
  (threshold_key, strategy_id, threshold_value, description, peak_multiplier,
   boost_peak_multiplier, source, updated_at, updated_by, coach_mode)
VALUES
  ('INTENT_CVR_CALIBRATION', 'INTENT', 1.151,
   'Level correction applied to the whole intent CVR curve: cvr_hat = this x base_cvr x PRODUCT(active indexes). Measured against realised CVR — the catalog under-priced a click by 1.69x and this carries the part of that gap no index explains. Re-derive it whenever an index is promoted, otherwise it silently absorbs the new index.',
   1.0, 1.0, 'SEED', CURRENT_DATETIME(), 'claude-intent-registry', 'GUARDIAN'),

  ('INTENT_IDX_MIN_SUPPORT', 'INTENT', 100.0,
   'Minimum support clicks in an index cell before that cell may move away from 1.000. Below this the cell is pinned to neutral rather than shouted at by a handful of clicks.',
   1.0, 1.0, 'SEED', CURRENT_DATETIME(), 'claude-intent-registry', 'GUARDIAN'),

  ('INTENT_IDX_MIN_SCORED_CLICKS', 'INTENT', 500.0,
   'Minimum clicks in a walk-forward scorecard month before that month casts a verdict on an index. Thin months are reported but not counted, so an index cannot be promoted on noise.',
   1.0, 1.0, 'SEED', CURRENT_DATETIME(), 'claude-intent-registry', 'GUARDIAN');

-- Base prior 200 -> 400. The curve trusts thin product x intent cells too much at 200, which is
-- one of the three diagnosed causes of the 1.69x under-pricing. Description moves with the value
-- so the halfway-point example it gives stays true.
UPDATE `onyga-482313.OI.DE_COACH_THRESHOLDS`
SET threshold_value = 400.0,
    description = "Beta-binomial prior strength k for base CVR. A product x intent cell with 400 clicks sits halfway between its own rate and its family's. Raise to trust thin cells less.",
    updated_at = CURRENT_DATETIME(),
    updated_by = 'claude-intent-registry'
WHERE strategy_id = 'INTENT' AND threshold_key = 'INTENT_CVR_BASE_PRIOR_CLICKS';

-- INTENT_CVR_SEASON_PRIOR_CLICKS is deliberately left at its current 500 here; it is re-derived
-- from measured pooled cell sizes in Task 2.
