-- =============================================
-- V_PPC_CHANGE_LOG_APPLIED — change-log rows that actually landed in Amazon
-- =============================================
-- FACT_PPC_CHANGE_LOG is append-only and records what was ATTEMPTED; a row is a
-- claim, not a fact, until the live Fivetran mirrors confirm it. Rows marked
-- upload_status = 'FAILED_UPLOAD' (silent bulksheet upload failures — e.g. the
-- three 2026-08-06 batches whose 38 rows never landed) are excluded here, and so
-- are rows marked 'SUPERSEDED_NEVER_UPLOADED' (2026-08-22: a manual book that was
-- exported and logged, failed verification, and was replaced before any upload —
-- the 54-row 'reprice_book_20260822' batch). Only NULL means "landed".
--
-- EVERY analytical consumer reads THIS view: outcome scoring, cooldowns,
-- APPLIED_HOLD / probe episodes, negate retirement, negative sync, the keyword
-- state machine's probation clock (SP_SNAPSHOT_KEYWORD_STATE v27.105 — the clock
-- starts only on an applied bid at the floor), and the live /api/applied-recent
-- endpoint. Only the Flask writer and audit/debug paths read the raw table.
-- SOP: architecture/PPC_CLOSE_THE_LOOP.md §Upload verification.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED` AS
SELECT *
FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
-- PENDING_UPLOAD (v27.106): a hand-built book is LOGGED at build time so its batch id is on record,
-- but nothing has reached Amazon until Ori uploads it. Until he confirms, the rows must not read
-- as applied — otherwise the keyword state machine re-reads them as changes that happened
-- (cooldowns, holds and re-judge dates all moved on a file that was still on disk). Flip the
-- status to NULL on confirmation; never delete the rows.
-- OBSERVED_ON_AMAZON (2026-10-01, SP_RECORD_OBSERVED_CHANGES): a change read off the DIM SCD2 trail
-- (source = 'OBSERVED') — hand changes made in the console, and the landing of changes OI logged.
-- They are kept OUT of this view on purpose. Every reader of this view (cooldowns, the keyword
-- state machine's probation clock, seat registers, 48-hour change detection, negative sync, the
-- outcome views; list them with SELECT table_name FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS`
-- WHERE STRPOS(view_definition, 'V_PPC_CHANGE_LOG_APPLIED') > 0, and the same on ROUTINES) keeps
-- reading exactly the rows it read before the ledger existed (OBSERVED_CHANGES_acceptance.sql C06);
-- letting hand changes in would move cooldowns and clocks, which is a decision for Ori, not a side
-- effect of recording. The grader reads them through V_PPC_CHANGE_LOG_LANDED, which unions this
-- view with the observed rows and counts a logged change and its observed landing once.
WHERE COALESCE(upload_status, '') NOT IN ('FAILED_UPLOAD', 'SUPERSEDED_NEVER_UPLOADED', 'PENDING_UPLOAD',
                                          'OBSERVED_ON_AMAZON');
