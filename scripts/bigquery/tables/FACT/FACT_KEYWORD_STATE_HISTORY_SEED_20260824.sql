-- =============================================================================================
-- FACT_KEYWORD_STATE_HISTORY_SEED_20260824 — the second copy, taken before the fuse burned.
-- v27.146 (2026-08-24 23:15 UTC). RUN ONCE. It is an audit record, not a repeatable step.
--
-- WHY THIS EXISTS. The eight partitions 2026-08-17..2026-08-24 in FACT_KEYWORD_STATE_HISTORY were
-- not written by a nightly pass. Seven of them were RECOVERED from BigQuery's own seven-day table
-- history by scripts/bigquery/migrations/2026-08-24_keyword_state_history_backfill.sql, because
-- FACT_KEYWORD_STATE is CREATE OR REPLACE'd on every pass and no other copy of an earlier snapshot
-- exists anywhere in the warehouse. That recovery cannot be performed twice.
--
-- THE FUSE IS NOT ONE DATE — IT IS SEVEN, AND THE FIRST ONE IS TODAY. The backfill migration's
-- header says the timestamps stop being readable "around 2026-08-31". That is the LAST expiry, not
-- the first. The window is 168 hours (dataset maxTimeTravelHours = 168, checked), and each source
-- timestamp leaves it on its own day:
--
--     snapshot_date  read from            unrecoverable after
--     2026-08-17     2026-08-18 06:00Z    2026-08-25 06:00Z   <- FIRST, hours after this file
--     2026-08-18     2026-08-19 06:00Z    2026-08-26 06:00Z
--     2026-08-19     2026-08-20 06:00Z    2026-08-27 06:00Z
--     2026-08-20     2026-08-21 06:00Z    2026-08-28 06:00Z
--     2026-08-21     2026-08-22 06:00Z    2026-08-29 06:00Z
--     2026-08-22     2026-08-23 06:00Z    2026-08-30 06:00Z
--     2026-08-23     2026-08-24 06:00Z    2026-08-31 06:00Z
--
-- So from 06:00Z on 2026-08-25 the history table is the ONLY copy of 2026-08-17, and one further
-- day joins it every 24 hours. A dropped table, a bad migration or a mistaken partition delete
-- after that moment is not a setback — it is the permanent loss of the thing violation 6 was
-- closed to stop. The history's own seven-day time travel is not a second copy of the SEED: it
-- expires on the same rolling window, so it protects only against a loss noticed within a week.
--
-- WHY A SNAPSHOT AND NOT A COPY. CREATE SNAPSHOT TABLE is immutable by construction — a DELETE
-- against it fails with "snapshots are immutable" (verified as a negative control, not assumed) —
-- it is delta-stored so it costs almost nothing while the base table is unchanged, and it SURVIVES
-- deletion of the base table, which a view or a scheduled copy would not.
--
-- WHAT IT IS NOT. Nothing reads it. It is not a source, not a fallback path, and no procedure,
-- view, engine, generator, book or bulksheet references it. It can move no bid, budget or pause.
-- It is insurance on an irreplaceable asset and should be left alone until the recovered partitions
-- stop being of interest, at which point it can simply be dropped.
--
-- VERIFIED AT CREATION: 8 snapshot_dates / 6,814 rows, each date's row count AND captured_at
-- identical to the live history; 69 columns on both sides with zero type mismatches;
-- INFORMATION_SCHEMA.TABLES.table_type = 'SNAPSHOT'; a DELETE against it errors.
-- =============================================================================================

CREATE SNAPSHOT TABLE `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY_SEED_20260824`
CLONE `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
OPTIONS(
  description="IMMUTABLE SEED COPY of FACT_KEYWORD_STATE_HISTORY taken 2026-08-24 23:15 UTC, before the time-travel fuse burned. The eight partitions 2026-08-17..2026-08-24 were recovered from BigQuery time travel by scripts/bigquery/migrations/2026-08-24_keyword_state_history_backfill.sql and CANNOT be recovered a second time: the oldest source version (2026-08-18 06:00 UTC) leaves the 168-hour window at 2026-08-25 06:00 UTC, and one more day expires every 24h until 2026-08-31 06:00 UTC. From those moments the history table is the ONLY copy, so this snapshot is the second one. Read-only by construction; survives deletion of the base table. Nothing reads it — it is insurance, not a source. Delete only when the recovered partitions are no longer of interest."
);
