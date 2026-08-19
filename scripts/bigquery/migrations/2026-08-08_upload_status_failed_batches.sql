-- =============================================
-- 2026-08-08 — upload_status column + FAILED_UPLOAD marking
-- =============================================
-- Audit (session 2026-08-08, memory: bulksheet-upload-failure-aug6) compared all
-- 582 FACT_PPC_CHANGE_LOG rows applied 2026-08-04..06 (LA) against the live
-- Fivetran mirrors (keyword_history / sb_keyword / targeting_clause_history /
-- sb_product_target / campaign_history / sb_campaign_history; all syncing live).
-- THREE whole Aug-6 batches never landed (0 of 38 rows; live values still equal
-- the pre-change bids/budgets at T+2d), plus 2 NEGATE_TERM rows in the sibling
-- 06:08 batch that are unverifiable (negative mirrors frozen 2026-01-03) but
-- belong to the same failed upload session.
--
-- Marking these rows FAILED_UPLOAD removes them from every analytical consumer
-- via V_PPC_CHANGE_LOG_APPLIED (outcome scorecard, APPLIED_HOLD, cooldowns,
-- v27.14 negate retirement, SP_SYNC_NEGATIVES).
-- SOP: architecture/PPC_CLOSE_THE_LOOP.md §Upload verification.
-- Rows are NEVER deleted — the attempt is part of the audit trail.

ALTER TABLE `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  ADD COLUMN IF NOT EXISTS upload_status STRING
  OPTIONS (description = 'NULL = assumed landed in Amazon (default). FAILED_UPLOAD = verified never landed (mirror audit). Set only by audited migrations; see architecture/PPC_CLOSE_THE_LOOP.md');

-- Expect exactly 40 rows: 12 + 9 + 17 bid/budget rows + 2 negates.
UPDATE `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
SET upload_status = 'FAILED_UPLOAD'
WHERE DATE(applied_at) BETWEEN '2026-08-05' AND '2026-08-07'  -- partition pruning (UTC)
  AND batch_id IN (
    'batch_20260806_160801_c2e9ae',   -- 2 NEGATE_TERM (BOTTLE-SP/AUTO), unverifiable, same failed session
    'batch_20260806_162211_d1b142',   -- 12 rows, 06:08 LA, 0 landed
    'batch_20260806_183247_990c97',   --  9 rows, 08:32 LA, 0 landed
    'batch_20260806_184036_3853e9'    -- 17 rows, 08:40 LA, 0 landed
  );

-- The nightly SP_SYNC_NEGATIVES had already copied the 2 failed negates into the
-- DE_NEGATIVE_KEYWORDS registry (post-freeze authority), falsely claiming they were
-- live in Amazon and suppressing any re-add. Soft-removed via the designed state flip
-- (2 rows affected 2026-08-08). Future syncs read V_PPC_CHANGE_LOG_APPLIED, so they
-- cannot re-appear from the failed rows.
UPDATE `onyga-482313.OI.DE_NEGATIVE_KEYWORDS`
SET state = 'REMOVED', removed_at = CURRENT_TIMESTAMP()
WHERE campaign_id = '279837860088128'
  AND ad_group_id = '514348414742076'
  AND LOWER(keyword_text) IN ('b0c1vlxybp', 'things for girls 10-12')
  AND state = 'ENABLED';
