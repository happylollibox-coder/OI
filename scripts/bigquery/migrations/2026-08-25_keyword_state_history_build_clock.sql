-- =============================================================================================
-- FACT_KEYWORD_STATE_HISTORY — the build clock, and the description that told the truth about
-- an older writer. Migration, v27.145 (2026-08-25). Run ONCE, in order, top to bottom:
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
--
-- WHY A MIGRATION AND NOT A REDEPLOY OF THE TABLE FILE. scripts/bigquery/tables/FACT/
-- FACT_KEYWORD_STATE_HISTORY.sql is CREATE TABLE IF NOT EXISTS, on purpose: re-running it can
-- never drop a kept snapshot, which is the entire point of the object. The consequence is that
-- re-running it is also a NO-OP against a table that already exists — it cannot add a column and
-- it cannot update the deployed OPTIONS description. Editing that file alone would make the repo
-- look repaired while the live object kept the old text. Both changes below are therefore explicit
-- ALTERs, and both are additive: no row is read, moved, rewritten or dropped anywhere in this file.
--
-- 1. snapshot_built_at. The history says when a row was WRITTEN here (captured_at) and what the
--    Catalog computed it for (snapshot_date). It did not say WHICH BUILD of the snapshot it was
--    copied from. That third clock is what makes a restamp visible after the fact: a pass whose
--    Task 20.8 failed leaves the previous build standing, and copying it again moves captured_at
--    while the build behind it stays put. With only two clocks the two cases are identical in the
--    data. With three, the acceptance suite's C14 can see the difference. NULL on every row
--    written before this migration — honestly, because those rows did not record it.
-- 2. The description. The deployed text asserted that the writer "replaces exactly the snapshot's
--    own date partition, so a pass that runs twice leaves one copy and no earlier partition is
--    ever touched". Both halves stopped being true at v27.144: the writer INSERTs and then prunes
--    duplicate captured_at stamps, and it deliberately DOES reach an earlier partition, because
--    repairing a strand on ANY date from ANY later call is the whole of that repair. A person
--    reading the old sentence while hunting for rows missing from an old partition would rule the
--    writer out and look somewhere else.
-- =============================================================================================

ALTER TABLE `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
  ADD COLUMN IF NOT EXISTS snapshot_built_at TIMESTAMP;

ALTER TABLE `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
  SET OPTIONS (description = "The Catalog's memory (THREE_LAYERS.md §8 violation 6, closed 2026-08-24). Append-only history of FACT_KEYWORD_STATE, which is CREATE OR REPLACE'd nightly and holds exactly one snapshot — so before this table existed no caller could ask the ladder what it said on any day but today, and §6's Catalog scorecard ('was the valuation right?') was impossible to compute. One row per (snapshot_date, campaign_id, keyword_id): the WHOLE snapshot row — verdict, the settled record it was read off, the family bar, the noise band, the affordable price, the floor, the mix-drift guard's cleaned re-reading and the promised appointment — because a verdict without its evidence cannot be graded, only counted. THREE CLOCKS, and they answer different questions: snapshot_date is the day the Catalog was speaking about, captured_at is when the row was written here, and snapshot_built_at is when the BUILD it was copied from was made (NULL before v27.145, which is the honest reading — those rows did not record it). Provenance is completed by source (ORCHESTRATOR | BACKFILL_TIME_TRAVEL) and source_detail naming exactly what was read. Written by SP_APPEND_KEYWORD_STATE_HISTORY (orchestrator Task 20.8a), which INSERTs the whole snapshot stamped with the run's captured_at and then PRUNEs any snapshot_date carrying more than one captured_at down to its newest stamp — append-first, so a crash between the two statements can only leave a duplicate, never a lost day, and two passes on one snapshot_date leave exactly one copy. THE WRITER CAN AND DOES REACH AN EARLIER PARTITION, deliberately: the prune is keyed on the history's OWN duplicate stamps rather than on the date the live snapshot happens to carry, and it runs before the append as well as after, so a strand left on any date is repaired by any later call including a manual one. What it may NOT do is restamp a build the history has already recorded — a pass whose Task 20.8 failed still reaches this step with the previous build standing, and re-copying it would move captured_at while the build behind it stood still, making the provenance claim a read time at which the Catalog said nothing. The writer refuses that copy by comparing the snapshot table's own last-modified clock against the stamp the history already holds for that date, which is a test of the BUILD and not of the calendar, so it holds for repeat passes inside one LA day as well as across days. The writer reads the live column list from INFORMATION_SCHEMA and ADD COLUMN IF NOT EXISTS-es what it lacks, so the columns §2.7 (confidence), §2.8 (market volume) and §4 (seasonality) will add appear here the day they exist, with older partitions honestly NULL rather than backfilled. NO ENGINE, GENERATOR OR BOOK READS THIS TABLE — it records what was already recorded and can move no bid, budget or pause. Read by V_CATALOG_DWELL. Acceptance: scripts/bigquery/tests/KEYWORD_STATE_HISTORY_acceptance.sql. Spec: architecture/THREE_LAYERS.md §1.4/§6/§8/§10.4. SOP: architecture/KEYWORD_STATE.md.");
