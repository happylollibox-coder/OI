-- =============================================================================================
-- T_INTENT_IDX_HISTORY — monthly snapshots of every index in DE_INTENT_INDEX_REGISTRY, long format.
--
-- WHY IT EXISTS. Two defects in the scorecard, one table.
--   1. V_INTENT_INDEX_SCORECARD used to hardcode the two index names (season_month, season_phase)
--      and their join columns. A third index meant editing SQL, which is exactly what the registry
--      was built to avoid. This table carries every index in ONE shape -- the four possible join
--      keys as columns, unused ones NULL -- so the scorecard can iterate index_name from the data.
--   2. The index views were read AS DEPLOYED at scoring time: fitted on all of history, including
--      the target months they were scored against. Every index verdict was optimistic by an
--      unmeasured amount (limitation L1 in the old scorecard header). Keeping the index as it stood
--      in each month lets the scorecard score target month M with the newest snapshot taken
--      BEFORE M, and flag the rows where no such snapshot exists yet.
--
-- GRAIN. One row per snapshot_month x index_name x (the index's own join keys). SP_SCORE_INTENT_INDEXES
-- writes it: for every registry row, active or not, it DELETEs that index's rows for the current
-- UTC month and re-INSERTs them from source_object, so a rerun inside a month overwrites rather
-- than duplicates, and the last run of a month is the month's snapshot. Acceptance R19 is what
-- catches a duplicate (two overlapping runs can produce one); R17 catches a missing snapshot.
--
-- JOIN-KEY COLUMNS ARE A NULL-WILDCARD CONTRACT. The scorecard joins an observation to a history
-- row with (h.key IS NULL OR h.key = o.key) on each of product_short_name / intent_key /
-- intent_type, and h.month_of_year = the target's calendar month. A NULL key therefore means
-- "this index does not discriminate on that key", not "unknown". Two consequences the procedure
-- enforces at write time and acceptance R18 enforces at read time:
--   * a declared key is never NULL in a written row (a NULL there would silently match every
--     observation for that index); the INSERT raises instead.
--   * at least one of the three wildcard keys is declared, so no row can be NULL on all three.
-- month_of_year is NOT a wildcard: the scorecard is a monthly walk-forward and an index without
-- a month key would score as absent (1.000) everywhere, which is a vacuous NEUTRAL. The procedure
-- refuses to snapshot such an index.
--
-- ACCUMULATES. This is a record of what each index said in each month, so it is CREATE TABLE IF
-- NOT EXISTS and is never CREATE OR REPLACEd -- replacing it erases the walk-forward evidence and
-- puts every scorecard row back on leakage_flag = TRUE.
--
-- Partition by snapshot_month (always the first of a month), cluster by index_name: the procedure
-- deletes and the scorecard reads by exactly that pair.
--
-- Written by:  SP_SCORE_INTENT_INDEXES
-- Read by:     V_INTENT_INDEX_SCORECARD (via T_INTENT_INDEX_SCORECARD), acceptance R17-R20
-- Acceptance:  scripts/bigquery/tests/INTENT_INDEX_acceptance.sql
-- Spec:        docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md
-- Created:     2026-09-11
-- =============================================================================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.T_INTENT_IDX_HISTORY` (
  snapshot_month     DATE      NOT NULL,  -- DATE_TRUNC(CURRENT_DATE(), MONTH) in UTC at write time
  snapshot_at        TIMESTAMP NOT NULL,  -- when this index's rows were written for that month
  index_name         STRING    NOT NULL,  -- DE_INTENT_INDEX_REGISTRY.index_name
  product_short_name STRING,              -- NULL = index does not key on it (wildcard)
  intent_key         STRING,              -- NULL = wildcard
  intent_type        STRING,              -- NULL = wildcard
  month_of_year      INT64     NOT NULL,  -- 1..12; every index must key on it
  index_value        FLOAT64   NOT NULL,  -- as published by source_object, > 0 by contract
  support_clicks     INT64     NOT NULL   -- as published by source_object
)
PARTITION BY snapshot_month
CLUSTER BY index_name
OPTIONS (description = "Monthly snapshots of every index in DE_INTENT_INDEX_REGISTRY in one long shape: the four possible join keys as columns, unused ones NULL, plus index_value and support_clicks as the source view published them. Written by SP_SCORE_INTENT_INDEXES (DELETE + INSERT per index per UTC month, so the last run in a month is that month's snapshot) for every registry row, active or not. Read by V_INTENT_INDEX_SCORECARD, which scores target month M with the newest snapshot taken strictly BEFORE M and flags leakage_flag = TRUE where none exists yet -- that flag is the honest replacement for the old header's limitation L1, where the index views were read as deployed and every index verdict carried unmeasured look-ahead. NULL on a key column is a wildcard by contract (the scorecard joins with key IS NULL OR key = obs.key), so a declared key is never written NULL and at least one non-month key is always declared; the procedure raises otherwise and acceptance R18 checks the table. ACCUMULATES: CREATE TABLE IF NOT EXISTS, never replaced -- replacing it erases the walk-forward evidence. Acceptance R17-R20.");
