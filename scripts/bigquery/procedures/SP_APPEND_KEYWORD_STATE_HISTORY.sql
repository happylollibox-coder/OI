-- =============================================================================================
-- SP_APPEND_KEYWORD_STATE_HISTORY — the Catalog's memory gets written. v27.144 (2026-08-25).
--
-- Appends today's FACT_KEYWORD_STATE into FACT_KEYWORD_STATE_HISTORY. Called by the orchestrator
-- as Task 20.8a, IMMEDIATELY after Task 20.8 builds the snapshot and BEFORE anything reads it.
-- Closes THREE_LAYERS.md §8 violation 6: without this step the snapshot is CREATE OR REPLACE'd on
-- every pass and a day of the ladder's verdicts is destroyed for good.
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
--   2. PRUNE: within any snapshot_date that now carries MORE THAN ONE captured_at, keep the
--      newest stamp and drop the rest.
-- If step 1 fails, nothing was removed and the history is untouched. If step 2 fails, the
-- partition briefly holds two copies and ANY later call repairs it. A delete-then-insert would
-- have the failure mode pointing the other way: a crash between the two statements destroys a day
-- of memory, which is precisely the defect this object exists to end. There is no window in which
-- this procedure can lose a snapshot it has already kept.
--
-- WHY THE PRUNE IS KEYED ON THE HISTORY'S OWN DUPLICATE STAMPS AND NOT ON THE SNAPSHOT'S DATES
-- (v27.144, repair). It used to read "DELETE ... WHERE snapshot_date IN (SELECT DISTINCT
-- snapshot_date FROM FACT_KEYWORD_STATE) AND captured_at < run_ts" — scoped to whichever date the
-- live snapshot happened to carry tonight. That made the advertised self-healing conditional in
-- exactly the case it was advertised for: snapshot_date is CURRENT_DATE('America/Los_Angeles'),
-- so if the INSERT succeeded and the PRUNE failed on the LAST pass of an LA day, every later pass
-- carried a DIFFERENT date and its prune could never reach the stranded one again. The duplicate
-- was permanent, C03/C08 went red for good, and not even the manual CALL the SOP offers as the
-- universal fix could clear it. The prune is now stated as what it always meant: a snapshot_date
-- may hold exactly one captured_at, and the newest one wins. It is a pure repair — on a clean
-- history no date carries two stamps and it deletes nothing — and it runs BEFORE the append as
-- well as after, so a call that adds nothing today still heals a strand left by an earlier one.
--
-- WHAT THIS PASS MAY WRITE, AND WHAT IT MAY NOT (v27.144, repair). Task 20.8 is wrapped in its own
-- BEGIN ... EXCEPTION block in the orchestrator, so a pass where the snapshot build FAILS still
-- reaches this task — with the PREVIOUS build's table still standing. Re-copying that table would
-- restamp a partition this pass did not produce: identical rows, but captured_at and source_detail
-- would then claim a read time at which the Catalog said nothing, corrupting the provenance the
-- history exists to hold. GUARD 3 refuses it. A snapshot whose date is older than the current LA
-- date AND already present in the history is a snapshot this pass did not build, and there is
-- nothing to add; the procedure returns having repaired but not written. A stale snapshot carrying
-- a date the history does NOT hold is still appended — that is memory being gained, not restamped.
-- What remains writable is the LA day the pass is itself running in, which is the day it belongs
-- to, and only there does re-copying express the intended "the day's final word" semantics.
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
--   * every statement here is guarded — if either table is absent, or the snapshot holds no rows,
--     the procedure returns having done nothing, rather than emptying a partition.
--
-- Writes: FACT_KEYWORD_STATE_HISTORY (append + prune of duplicate captured_at stamps).
-- Reads:  FACT_KEYWORD_STATE, INFORMATION_SCHEMA.COLUMNS, INFORMATION_SCHEMA.TABLES.
-- Acceptance: scripts/bigquery/tests/KEYWORD_STATE_HISTORY_acceptance.sql
-- Spec: architecture/THREE_LAYERS.md §1.4, §6, §6.2, §8 (violation 6), §10.4.
-- SOP:  architecture/KEYWORD_STATE.md §"The history".
-- =============================================================================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_APPEND_KEYWORD_STATE_HISTORY`()
OPTIONS (
  description = "Appends the live FACT_KEYWORD_STATE snapshot into the append-only FACT_KEYWORD_STATE_HISTORY (orchestrator Task 20.8a, immediately after 20.8). Closes THREE_LAYERS.md §8 violation 6 — the snapshot table is CREATE OR REPLACE'd every pass and holds one day, so before this step each pass destroyed a day of the Catalog's verdicts permanently. Idempotent and APPEND-FIRST: it INSERTs the whole snapshot stamped with this run's captured_at, then PRUNEs any snapshot_date carrying more than one captured_at down to its newest stamp, so two passes on one snapshot_date leave exactly one copy and a crash between the statements can only leave a duplicate — never a lost day. The prune is keyed on the history's own duplicate stamps, not on the dates the live snapshot happens to carry, and runs before the append as well as after, so a strand left on ANY date is repaired by ANY later call. A snapshot older than the current LA date whose day the history already holds is refused rather than restamped: a pass where Task 20.8 failed must not rewrite the provenance of a partition it did not produce. Schema-evolving: it reads the live column list from INFORMATION_SCHEMA, ADD COLUMN IF NOT EXISTS-es whatever the history lacks and inserts by column name, so the columns §2.7 (confidence), §2.8 (market volume) and §4 (seasonality) will add are carried the night they appear, with earlier partitions honestly NULL. Decides nothing and writes nothing any engine reads; it cannot move a bid, a budget or a pause. Guarded so a missing table or an empty snapshot is a no-op, and wrapped by the orchestrator's exception handler so a failure logs FAIL and the pass continues. Acceptance: scripts/bigquery/tests/KEYWORD_STATE_HISTORY_acceptance.sql. Spec: architecture/THREE_LAYERS.md §8 violation 6, §10.4. SOP: architecture/KEYWORD_STATE.md."
)
BEGIN
  DECLARE col_list  STRING;
  DECLARE add_cols  STRING;
  DECLARE run_ts    TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE src_rows  INT64 DEFAULT 0;
  DECLARE snap_date DATE;

  -- GUARD 0: both tables must exist. The history's DDL is deployed separately; until it is there
  -- this procedure has nowhere to write and must not error the pass trying.
  IF (SELECT COUNT(*) FROM `onyga-482313.OI.INFORMATION_SCHEMA.TABLES`
       WHERE table_name = 'FACT_KEYWORD_STATE_HISTORY') = 0 THEN
    RETURN;
  END IF;

  -- REPAIR FIRST, unconditionally. A snapshot_date may hold exactly one captured_at; if an earlier
  -- call's prune failed after its insert succeeded, the strand is cleared here — on ANY date, by
  -- ANY later call, including a manual one. On a clean history this deletes nothing.
  CREATE OR REPLACE TEMP TABLE _kwsh_prune_keep AS
  SELECT snapshot_date, MAX(captured_at) AS keep_ts
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
  GROUP BY snapshot_date
  HAVING COUNT(DISTINCT captured_at) > 1;

  DELETE FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY` h
  WHERE EXISTS (SELECT 1 FROM _kwsh_prune_keep k
                 WHERE k.snapshot_date = h.snapshot_date
                   AND h.captured_at < k.keep_ts);

  -- GUARD 1: the snapshot must exist. On a fresh project, or a pass where Task 20.8 failed and
  -- left no table at all, the right behaviour is to leave the history exactly as it is.
  IF (SELECT COUNT(*) FROM `onyga-482313.OI.INFORMATION_SCHEMA.TABLES`
       WHERE table_name = 'FACT_KEYWORD_STATE') = 0 THEN
    RETURN;
  END IF;

  -- GUARD 2: an empty snapshot is never a reason to empty a partition. (The statements below are
  -- already no-ops on an empty source — the INSERT inserts nothing — but the intent is stated
  -- rather than left to be inferred.)
  SET src_rows = (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`);
  IF src_rows = 0 THEN
    RETURN;
  END IF;

  -- GUARD 3: refuse a snapshot this pass did not build. Task 20.8 has its own exception handler,
  -- so a failed build leaves the PREVIOUS day's table standing and this task still runs. Copying
  -- it again would restamp a partition tonight did not produce — the rows would be identical but
  -- captured_at and source_detail would claim a read time at which the Catalog said nothing.
  -- A stale snapshot whose day the history does NOT yet hold is still appended below: that is
  -- memory gained, not provenance rewritten.
  SET snap_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`);
  IF snap_date IS NULL
     OR (snap_date < CURRENT_DATE('America/Los_Angeles')
         AND (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
               WHERE snapshot_date = snap_date) > 0) THEN
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

  -- STEP 2 — PRUNE. Same statement as the repair above, for the same reason: a snapshot_date holds
  -- one captured_at, the newest wins. Today's date now carries two stamps and loses the older one;
  -- every other date carries one and is untouched.
  CREATE OR REPLACE TEMP TABLE _kwsh_prune_keep AS
  SELECT snapshot_date, MAX(captured_at) AS keep_ts
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
  GROUP BY snapshot_date
  HAVING COUNT(DISTINCT captured_at) > 1;

  DELETE FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY` h
  WHERE EXISTS (SELECT 1 FROM _kwsh_prune_keep k
                 WHERE k.snapshot_date = h.snapshot_date
                   AND h.captured_at < k.keep_ts);
END;
