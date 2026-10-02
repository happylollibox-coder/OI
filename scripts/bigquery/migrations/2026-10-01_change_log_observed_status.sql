-- 2026-10-01 — learning-system Task B: FACT_PPC_CHANGE_LOG carries observed changes. WHY. The
-- log's last applied row is 2026-08-24; every change since was made by hand in the console and
-- only the DIM SCD2 trail saw it. SP_RECORD_OBSERVED_CHANGES now writes those changes into the log
-- as rows of their own (source 'OBSERVED', upload_status 'OBSERVED_ON_AMAZON'). No column is
-- added and no existing row is touched; this migration only rewrites two DESCRIPTIONS so the
-- table's own schema names every status in use — the upload_status description still named two
-- of the five (PENDING_UPLOAD arrived in v27.106 without it).
-- Metadata only, idempotent, one ALTER per statement.
ALTER TABLE `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  ALTER COLUMN upload_status SET OPTIONS (description = 'NULL = landed in Amazon (default for DO-page rows and confirmed books). FAILED_UPLOAD = uploaded, verified never landed (audited migrations). SUPERSEDED_NEVER_UPLOADED = logged, never uploaded, replaced by a later batch. PENDING_UPLOAD = a hand-built book logged at build time, not yet confirmed uploaded (tools/build_*_bulksheet.py / build_weekly_book.py; --mark-uploaded flips it to NULL). OBSERVED_ON_AMAZON = a change read off the DIM SCD2 trail by SP_RECORD_OBSERVED_CHANGES (source OBSERVED). V_PPC_CHANGE_LOG_APPLIED excludes the last four; V_PPC_CHANGE_LOG_LANDED adds the observed rows for the grader. See architecture/PPC_CLOSE_THE_LOOP.md');
ALTER TABLE `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  SET OPTIONS (description = 'Append-only action record: every PPC change OI put through (DO page source COACH/MANUAL, hand-built books BRAIN:*/CATALOG:*/PACING:*) and, from 2026-08-20, every change the DIM SCD2 trail shows on Amazon (source OBSERVED, written nightly by SP_RECORD_OBSERVED_CHANGES). Readers: V_PPC_CHANGE_LOG_APPLIED (engines), V_PPC_CHANGE_LOG_LANDED (the grader). See architecture/PPC_CLOSE_THE_LOOP.md');
