-- =============================================
-- V_PPC_CHANGE_LOG_LANDED — every change that reached Amazon, logged or not, each counted once
-- (2026-10-01, learning-system Task B). The grader's source: V_CHANGE_SCORECARD reads this view.
-- SOP: architecture/PPC_CLOSE_THE_LOOP.md §Observed changes.
--
-- TWO RECORDS OF ONE WORLD. V_PPC_CHANGE_LOG_APPLIED is what OI's own tooling put through and
-- confirmed (the DO page, the confirmed books). The rows SP_RECORD_OBSERVED_CHANGES writes into
-- FACT_PPC_CHANGE_LOG (source 'OBSERVED', upload_status 'OBSERVED_ON_AMAZON') are what the DIM SCD2
-- trail shows actually changed on Amazon from 2026-08-20 — hand changes made in the console AND the
-- landing of changes OI logged. A logged change that landed therefore appears twice; the procedure
-- writes the observed copy anyway (the log row may never be updated, house rule) but names the row
-- it confirms in upload_note: 'CONFIRMS <change_id> ...'. This view reads that name back and keeps
-- ONE row per change:
--   LOGGED_AND_SEEN_ON_AMAZON      an applied log row an observed row confirms. Kept; its observed
--                                  twin is dropped (paired_change_id names it).
--   LOGGED_ONLY                    an applied log row nothing observed confirms: every row before
--                                  2026-08-20 (the ledger starts there), negates, added targets and
--                                  other actions the SCD trail cannot see, and logged changes whose
--                                  landing did not match within the window.
--   SEEN_ON_AMAZON_NOT_LOGGED      an observed change no live log row accounts for — a hand change.
--   SEEN_ON_AMAZON_LOG_NOT_APPLIED an observed change confirming a log row that is NOT in APPLIED
--                                  (a book still PENDING_UPLOAD, or one later labelled dead). The
--                                  observation is then the only landed record, so it is kept.
-- WHICH log row an observation confirms is decided by the procedure at insert time; WHICH CLASS a
-- row falls in is decided here at query time from the log row's current status (in APPLIED or
-- not), so nothing has to be rewritten when a pending book is confirmed with --mark-uploaded later.
-- KNOWN LIMIT: a log row written AFTER its landing was recorded (the DO page's offline queue
-- flushing days late) is not paired — the procedure never revisits a row it wrote — and both rows
-- stay in this view.
--
-- COLUMNS: every FACT_PPC_CHANGE_LOG column in table order, then landed_evidence (above) and
-- paired_change_id (an observed row: the log row it confirms; a log row: the observed row or rows
-- confirming it, comma-joined, at most one per attribute). The two SELECTs read the same table
-- through SELECT *, so a column added to FACT_PPC_CHANGE_LOG arrives on both sides in order.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PPC_CHANGE_LOG_LANDED` AS
WITH
obs AS (
  SELECT f.*, REGEXP_EXTRACT(f.upload_note, r'^CONFIRMS (\S+)') AS confirms_id
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` f
  WHERE f.source = 'OBSERVED' AND f.upload_status = 'OBSERVED_ON_AMAZON'
),
confirmations AS (
  SELECT confirms_id, STRING_AGG(change_id, ',' ORDER BY change_id) AS observed_ids
  FROM obs WHERE confirms_id IS NOT NULL
  GROUP BY 1
)
SELECT a.*,
       IF(c.confirms_id IS NOT NULL, 'LOGGED_AND_SEEN_ON_AMAZON', 'LOGGED_ONLY') AS landed_evidence,
       c.observed_ids                                                          AS paired_change_id
FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED` a
LEFT JOIN confirmations c ON c.confirms_id = a.change_id
UNION ALL
SELECT o.* EXCEPT (confirms_id),
       IF(o.confirms_id IS NULL, 'SEEN_ON_AMAZON_NOT_LOGGED', 'SEEN_ON_AMAZON_LOG_NOT_APPLIED') AS landed_evidence,
       o.confirms_id                                                           AS paired_change_id
FROM obs o
WHERE o.confirms_id IS NULL
   OR NOT EXISTS (SELECT 1 FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED` a WHERE a.change_id = o.confirms_id);
