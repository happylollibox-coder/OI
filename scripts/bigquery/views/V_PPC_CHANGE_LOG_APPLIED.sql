-- =============================================
-- V_PPC_CHANGE_LOG_APPLIED — change-log rows that actually landed in Amazon
-- =============================================
-- FACT_PPC_CHANGE_LOG is append-only and records what was ATTEMPTED; a row is a
-- claim, not a fact, until the live Fivetran mirrors confirm it. Rows marked
-- upload_status = 'FAILED_UPLOAD' (silent bulksheet upload failures — e.g. the
-- three 2026-08-06 batches whose 38 rows never landed) are excluded here.
--
-- EVERY analytical consumer reads THIS view: outcome scoring, cooldowns,
-- APPLIED_HOLD / probe episodes, negate retirement, negative sync, and the live
-- /api/applied-recent endpoint. Only the Flask writer and audit/debug paths read
-- the raw table. SOP: architecture/PPC_CLOSE_THE_LOOP.md §Upload verification.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED` AS
SELECT *
FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
WHERE COALESCE(upload_status, '') != 'FAILED_UPLOAD';
