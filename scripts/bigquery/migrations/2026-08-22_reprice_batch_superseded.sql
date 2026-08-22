-- =============================================
-- 2026-08-22 — upload_note column + SUPERSEDED_NEVER_UPLOADED marking (reprice book provenance)
-- =============================================
-- tools/build_reprice_bulksheet.py logged batch 'reprice_book_20260822' (54 rows, 07:56 UTC) from an
-- EARLY build of the reprice book. That book was never uploaded: an adversarial verification
-- returned DO_NOT_UPLOAD (five above-bar keywords were being cut, six below-bar keywords raised,
-- no move-size cap, five KEYWORD_PAUSE rows with NULL new_bid that the corrected book does not
-- emit, one row in the opposite direction). Left with upload_status NULL the scorecard would grade
-- 54 phantom changes and the guard / cooldowns would see bids that never landed.
--
-- NEVER DELETE A LOG ROW — LABEL IT. A third upload_status value is introduced:
--   NULL                      = assumed landed in Amazon (default)
--   FAILED_UPLOAD             = exported and uploaded, verified never landed (2026-08-08 precedent)
--   SUPERSEDED_NEVER_UPLOADED = exported and logged, never uploaded, replaced by a later batch
-- and a free-text upload_note so the row says WHY. V_PPC_CHANGE_LOG_APPLIED excludes both
-- non-NULL statuses from every analytical consumer (redeployed with this migration).
--
-- Run once (idempotent: the UPDATE touches only rows still NULL).
ALTER TABLE `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  ADD COLUMN IF NOT EXISTS upload_note STRING
  OPTIONS (description = 'Free text beside upload_status: why a row is FAILED_UPLOAD / SUPERSEDED_NEVER_UPLOADED, or the build note the generator wrote. Set by audited migrations and by the bulksheet generators at log time.');

UPDATE `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
SET upload_status = 'SUPERSEDED_NEVER_UPLOADED',
    upload_note = 'reprice book build of 2026-08-22 07:56 UTC failed adversarial verification (DO_NOT_UPLOAD: above-bar cuts, below-bar raises, no move cap) and was never uploaded; superseded by the corrected build — see .tmp/reprice_book_20260822_README.md for the batch that replaced it'
WHERE batch_id = 'reprice_book_20260822'
  AND upload_status IS NULL;
