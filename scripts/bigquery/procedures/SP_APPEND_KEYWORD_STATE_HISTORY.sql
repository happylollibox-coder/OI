-- =============================================================================================
-- SP_APPEND_KEYWORD_STATE_HISTORY — the Catalog's memory gets written. v27.143 (2026-08-24).
--
-- Appends today's FACT_KEYWORD_STATE into FACT_KEYWORD_STATE_HISTORY. Called by the orchestrator
-- as Task 20.8a, IMMEDIATELY after Task 20.8 builds the snapshot and BEFORE anything reads it.
-- Closes THREE_LAYERS.md §8 violation 6: without this step the snapshot is CREATE OR REPLACE'd on
-- every pass and a day of the Catalog's verdicts is destroyed for good.
--
-- IT DECIDES NOTHING. It copies a table that was already written into a table nothing acts on.
-- No engine, generator, book or bulksheet reads the history. This procedure cannot move a bid, a
-- budget or a pause, and it cannot change what any other step sees: FACT_KEYWORD_STATE is read,
-- never written, here.
--
-- IDEMPOTENT, AND APPEND-FIRST BY CONSTRUCTION. Two passes on the same snapshot_date must leave
-- exactly one copy — and the house assumes any procedure may be called twice a night (the
-- orchestrator already calls SP_MAINTAIN_FAMILY_SEATS twice per pass through
-- SP_REFRESH_CUBE_TABLES). The order here is deliberately INSERT-THEN-PRUNE rather than
-- DELETE-THEN-INSERT:
--   1. INSERT every row of the snapshot, stamped with this run's captured_at.
--   2. DELETE, from the snapshot's OWN dates only, every row stamped EARLIER than this run.
-- If step 1 fails, nothing was removed and the history is untouched. If step 2 fails, the
-- partition briefly holds two copies and the NEXT run prunes both older stamps — self-healing.
-- A delete-then-insert would have the failure mode pointing the other way: a crash between the
-- two statements destroys a day of memory, which is precisely the defect this object exists to
-- end. There is no window in which this procedure can lose a snapshot it has already kept.
-- Note also what the DELETE cannot reach: it is keyed on the snapshot's own snapshot_date values,
-- so no earlier partition is in scope at all. Yesterday cannot be touched by tonight's pass.
--
-- SCHEMA EVOLUTION IS AUTOMATIC (§2.7 confidence, §2.8 market volume, §4 seasonality are columns
-- the Catalog will grow). Nothing here is a hard-coded column list. Every run:
--   * reads the LIVE column list of FACT_KEYWORD_STATE from INFORMATION_SCHEMA;
--   * ALTER TABLE ... ADD COLUMN IF NOT EXISTS for anything the history does not yet hold;
--   * inserts by explicit column NAME, so column ORDER on either side is irrelevant.
-- A column added to the Catalog therefore appears in the history the same night, with no edit to
-- this file. Partitions written before that night keep NULL for it — the honest reading, since the
-- Catalog did not say it then. A column REMOVED from the Catalog is never dropped here; it keeps
-- what it held and goes NULL going forward.
-- ONE NAME COLLISION IS POSSIBLE AND IS LEFT LOUD ON PURPOSE: if the Catalog ever publishes a
-- column called captured_at, source or source_detail, the generated INSERT names it twice and
-- this procedure ERRORS. That is the intended behaviour — the orchestrator's handler logs FAIL,
-- the pass continues untouched, and a person renames the column. Silently dropping it would put a
-- hole in the memory that no later run could fill.
--
-- IT CANNOT BREAK THE PASS. Two independent guarantees:
--   * the orchestrator wraps the CALL in the house BEGIN ... EXCEPTION WHEN ERROR pattern, which
--     logs FAIL to LOG_PIPELINE_RUNS and carries on to the next task;
--   * every statement here is guarded — if FACT_KEYWORD_STATE does not exist, or holds no rows,
--     the procedure returns having done nothing, rather than emptying a partition.
--
-- Writes: FACT_KEYWORD_STATE_HISTORY (append + prune of its own date only).
-- Reads:  FACT_KEYWORD_STATE, INFORMATION_SCHEMA.COLUMNS.
-- Acceptance: scripts/bigquery/tests/KEYWORD_STATE_HISTORY_acceptance.sql
-- Spec: architecture/THREE_LAYERS.md §1.4, §6, §6.2, §8 (violation 6), §10.4.
-- SOP:  architecture/KEYWORD_STATE.md §"The history".
-- =============================================================================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_APPEND_KEYWORD_STATE_HISTORY`()
OPTIONS (
  description = "Appends the live FACT_KEYWORD_STATE snapshot into the append-only FACT_KEYWORD_STATE_HISTORY (orchestrator Task 20.8a, immediately after 20.8). Closes THREE_LAYERS.md §8 violation 6 — the snapshot table is CREATE OR REPLACE'd every pass and holds one day, so before this step each pass destroyed a day of the Catalog's verdicts permanently. Idempotent and APPEND-FIRST: it INSERTs the whole snapshot stamped with this run's captured_at, then DELETEs rows stamped earlier FROM THE SNAPSHOT'S OWN DATES ONLY, so two passes on one snapshot_date leave exactly one copy, no earlier partition is ever in scope, and a crash between the statements can only leave a duplicate the next run prunes — never a lost day. Schema-evolving: it reads the live column list from INFORMATION_SCHEMA, ADD COLUMN IF NOT EXISTS-es whatever the history lacks and inserts by column name, so the columns §2.7 (confidence), §2.8 (market volume) and §4 (seasonality) will add are carried the night they appear, with earlier partitions honestly NULL. Decides nothing and writes nothing any engine reads; it cannot move a bid, a budget or a pause. Guarded so a missing or empty snapshot is a no-op, and wrapped by the orchestrator's exception handler so a failure logs FAIL and the pass continues. Acceptance: scripts/bigquery/tests/KEYWORD_STATE_HISTORY_acceptance.sql. Spec: architecture/THREE_LAYERS.md §8 violation 6, §10.4. SOP: architecture/KEYWORD_STATE.md."
)
BEGIN
  DECLARE col_list  STRING;
  DECLARE add_cols  STRING;
  DECLARE run_ts    TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE src_rows  INT64 DEFAULT 0;

  -- GUARD 1: the snapshot must exist. On a fresh project, or a pass where Task 20.8 failed, the
  -- right behaviour is to leave the history exactly as it is.
  IF (SELECT COUNT(*) FROM `onyga-482313.OI.INFORMATION_SCHEMA.TABLES`
       WHERE table_name = 'FACT_KEYWORD_STATE') = 0 THEN
    RETURN;
  END IF;

  -- GUARD 2: an empty snapshot is never a reason to empty a partition. (The statements below are
  -- already no-ops on an empty source — the INSERT inserts nothing and the DELETE's IN-list is
  -- empty — but the intent is stated rather than left to be inferred.)
  SET src_rows = (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`);
  IF src_rows = 0 THEN
    RETURN;
  END IF;

  -- The live column list, read fresh every run. This is what makes the history tolerate the
  -- columns the Catalog has not grown yet.
  SET col_list = (
    SELECT STRING_AGG(CONCAT('`', column_name, '`'), ', ' ORDER BY ordinal_position)
    FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'FACT_KEYWORD_STATE');

  IF col_list IS NULL THEN
    RETURN;
  END IF;

  -- Widen the history to whatever the Catalog has grown. ADD COLUMN IF NOT EXISTS is a no-op for
  -- everything already present, so this is safe to run on every pass.
  SET add_cols = (
    SELECT STRING_AGG(CONCAT('ADD COLUMN IF NOT EXISTS `', s.column_name, '` ', s.data_type),
                      ', ' ORDER BY s.ordinal_position)
    FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS` s
    LEFT JOIN `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS` h
      ON h.table_name = 'FACT_KEYWORD_STATE_HISTORY'
     AND h.column_name = s.column_name
    WHERE s.table_name = 'FACT_KEYWORD_STATE'
      AND h.column_name IS NULL);

  IF add_cols IS NOT NULL THEN
    EXECUTE IMMEDIATE FORMAT(
      "ALTER TABLE `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY` %s", add_cols);
  END IF;

  -- STEP 1 — APPEND. Nothing is removed before this has succeeded.
  EXECUTE IMMEDIATE FORMAT("""
    INSERT INTO `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
      (captured_at, source, source_detail, %s)
    SELECT @ts, 'ORCHESTRATOR', @detail, %s
    FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
  """, col_list, col_list)
  USING run_ts AS ts,
        CONCAT('SP_APPEND_KEYWORD_STATE_HISTORY read FACT_KEYWORD_STATE at ',
               FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%SZ', run_ts, 'UTC'),
               ' (', CAST(src_rows AS STRING), ' rows)') AS detail;

  -- STEP 2 — PRUNE, and only within the dates this run just wrote. An earlier partition is not in
  -- scope, so no pass can ever rewrite a day it did not produce.
  DELETE FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
  WHERE snapshot_date IN (SELECT DISTINCT snapshot_date FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
    AND captured_at < run_ts;
END;
