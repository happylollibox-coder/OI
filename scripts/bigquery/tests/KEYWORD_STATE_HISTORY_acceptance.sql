-- =============================================================================================
-- FACT_KEYWORD_STATE_HISTORY + SP_APPEND_KEYWORD_STATE_HISTORY + V_CATALOG_DWELL
-- acceptance — v27.143 (2026-08-24). EVERY ROW MUST READ PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Spec: architecture/THREE_LAYERS.md §1.4, §6, §6.2, §8 (violation 6), §10.4.
-- SOP:  architecture/KEYWORD_STATE.md §"The history".
--
-- WHAT IS BEING ASSERTED, AND WHY EACH ONE EXISTS.
--   C01 the history is a partitioned, clustered table and not a heap. If snapshot_date stops
--       being the partitioning column, the write step's "replace exactly this date" stops being
--       a partition operation and starts being a full-table DELETE — a different and much more
--       dangerous thing.
--   C02 the history's row count for a date EQUALS the snapshot's for that date. The whole promise
--       of the object is that nothing is lost on the way in.
--   C03 APPEND-ONLY, IDEMPOTENT: one row per (snapshot_date, campaign_id, keyword_id). Two passes
--       on the same snapshot_date must leave exactly one copy. The orchestrator calls
--       SP_REFRESH_CUBE_TABLES which calls SP_MAINTAIN_FAMILY_SEATS a second time each pass, so a
--       procedure being called twice in one night is house-normal, not hypothetical.
--   C04 PARTITION INTEGRITY: no NULL and no future snapshot_date, every row carries captured_at
--       and a source from the closed set, and the number of NON-EMPTY physical partitions equals
--       the number of distinct snapshot dates, with the __NULL__ / __UNPARTITIONED__ pseudo-
--       partitions holding no rows at all (a row landing there landed nowhere and would be
--       invisible to every date-bounded read). BigQuery keeps an empty __NULL__ entry on a
--       partitioned table as a matter of course, so it is its ROW COUNT that is asserted, not its
--       absence — the first version of this check counted the entry itself and read 1 violation
--       against a table that was in fact clean.
--   C05 NO ROW IS EVER MUTATED. Every partition older than the newest was written STRICTLY BEFORE
--       the newest one was: an earlier day rewritten by a later pass breaks this immediately.
--       This is the check that would have caught the defect the whole object exists to fix, had
--       the object existed — a pass that quietly replaces yesterday is a pass that destroys it.
--   C06 the dwell view covers every subject the live snapshot holds. A subject the Catalog speaks
--       about today and the dwell view cannot find is a hole in the memory.
--   C07 HONEST DEGRADATION — the check this suite exists for. A row whose run reaches back to its
--       own first observation is CENSORED: it must read AT_LEAST, must publish NULL for
--       days_in_state_max, and must NOT name a state it changed from. A row that claims EXACT or
--       BETWEEN must name one. And no row may claim a dwell longer than the history is old.
--   C08 the bounds are arithmetic, not decoration: days_in_state >= 1 (it counts inclusively —
--       a state first seen today has stood for one day), and days_in_state_max, where it exists,
--       is >= days_in_state. days_in_state is ALWAYS the floor, so a consumer reading it alone is
--       told less than the truth and never more.
--   C09 the dwell view invents no subject: every row it publishes exists in the history.
--   C10 SCHEMA TOLERANCE (§2.7 confidence, §2.8 market volume, §4 seasonality are coming): every
--       column the snapshot publishes exists in the history with the same type. This check goes
--       red the first night a new Catalog column is NOT carried, which is the alarm that matters —
--       a column missed for a month is a month of that column that can never be recovered.
--   C11 CONTENT FIDELITY, not merely row count: for the live snapshot's date, the verdict and the
--       evidence behind it are identical in both places. Comparison is on straight copies, never
--       on re-derived arithmetic, so exact equality is the correct test here.
--       NOTE: if SP_SNAPSHOT_KEYWORD_STATE is ever run WITHOUT the append step that follows it,
--       C02 and C11 go red until the next pass. That is not a false alarm — it is the history
--       being stale — and the fix is to CALL `onyga-482313.OI.SP_APPEND_KEYWORD_STATE_HISTORY`().
-- =============================================================================================
WITH
live AS (
  SELECT MAX(snapshot_date) AS d FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
),
hist_bounds AS (
  SELECT MAX(snapshot_date) AS newest, COUNT(DISTINCT snapshot_date) AS n_dates
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
),
c01 AS (
  SELECT 'C01 history is partitioned by snapshot_date and clustered' AS check_name,
         (SELECT COUNT(*) FROM `onyga-482313.OI.INFORMATION_SCHEMA.TABLES`
           WHERE table_name = 'FACT_KEYWORD_STATE_HISTORY' AND table_type = 'BASE TABLE') - 1
       + (SELECT 1 - COUNTIF(is_partitioning_column = 'YES' AND column_name = 'snapshot_date')
          FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
           WHERE table_name = 'FACT_KEYWORD_STATE_HISTORY')
       + (SELECT IF(COUNTIF(clustering_ordinal_position IS NOT NULL) >= 1, 0, 1)
          FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
           WHERE table_name = 'FACT_KEYWORD_STATE_HISTORY') AS violations
),
c02 AS (
  SELECT 'C02 history row count for the live date equals the snapshot' AS check_name,
         ABS(
           (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
         - (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
             WHERE snapshot_date = (SELECT d FROM live))
         ) AS violations
),
c03 AS (
  SELECT 'C03 append-only: one row per (date, campaign, keyword)' AS check_name,
         (SELECT COALESCE(SUM(n - 1), 0) FROM (
            SELECT COUNT(*) AS n
            FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
            GROUP BY snapshot_date, campaign_id, keyword_id
            HAVING COUNT(*) > 1)) AS violations
),
c04 AS (
  SELECT 'C04 partition integrity: dates, provenance, one partition per date' AS check_name,
         (SELECT COUNTIF(snapshot_date IS NULL
                      OR snapshot_date > CURRENT_DATE('America/Los_Angeles')
                      OR captured_at IS NULL
                      OR source NOT IN ('ORCHESTRATOR', 'BACKFILL_TIME_TRAVEL'))
          FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`)
       + ABS((SELECT COUNT(*) FROM `onyga-482313.OI.INFORMATION_SCHEMA.PARTITIONS`
               WHERE table_name = 'FACT_KEYWORD_STATE_HISTORY' AND total_rows > 0
                 AND partition_id NOT IN ('__NULL__', '__UNPARTITIONED__'))
             - (SELECT n_dates FROM hist_bounds))
       + (SELECT COALESCE(SUM(total_rows), 0) FROM `onyga-482313.OI.INFORMATION_SCHEMA.PARTITIONS`
           WHERE table_name = 'FACT_KEYWORD_STATE_HISTORY'
             AND partition_id IN ('__NULL__', '__UNPARTITIONED__')) AS violations
),
c05 AS (
  SELECT 'C05 no row is ever mutated: older partitions predate the newest' AS check_name,
         (SELECT COUNT(*) FROM (
            SELECT snapshot_date
            FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
            WHERE snapshot_date < (SELECT newest FROM hist_bounds)
            GROUP BY snapshot_date
            HAVING MAX(captured_at) >= (
              SELECT MIN(captured_at) FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
               WHERE snapshot_date = (SELECT newest FROM hist_bounds)))) AS violations
),
c06 AS (
  SELECT 'C06 dwell view covers every subject in the live snapshot' AS check_name,
         (SELECT COUNT(*)
          FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
          LEFT JOIN `onyga-482313.OI.V_CATALOG_DWELL` d
            ON d.campaign_id = s.campaign_id AND d.keyword_id = s.keyword_id
          WHERE d.keyword_id IS NULL) AS violations
),
c07 AS (
  SELECT 'C07 dwell degrades honestly on short history' AS check_name,
         (SELECT COUNTIF(
            -- censored rows must say AT_LEAST, refuse a maximum, and name no prior state
            (state_run_start = first_observed_on
             AND (dwell_basis != 'AT_LEAST' OR days_in_state_max IS NOT NULL
                  OR changed_from IS NOT NULL OR NOT dwell_is_censored))
            -- a claimed change must name what it changed from and when
            OR (dwell_basis IN ('EXACT', 'BETWEEN')
                AND (changed_from IS NULL OR changed_on_or_before IS NULL))
            -- and no dwell may outrun the history itself
            OR days_in_state > DATE_DIFF(history_to, history_from, DAY) + 1)
          FROM `onyga-482313.OI.V_CATALOG_DWELL`) AS violations
),
c08 AS (
  SELECT 'C08 dwell bounds are ordered and non-negative' AS check_name,
         (SELECT COUNTIF(days_in_state < 1
                      OR (days_in_state_max IS NOT NULL AND days_in_state_max < days_in_state)
                      OR observed_days_in_state < 1
                      OR dwell_gap_days < 0
                      OR state_changes_28d < 0 OR state_changes_90d < 0)
          FROM `onyga-482313.OI.V_CATALOG_DWELL`) AS violations
),
c09 AS (
  SELECT 'C09 dwell view invents no subject' AS check_name,
         (SELECT COUNT(*)
          FROM `onyga-482313.OI.V_CATALOG_DWELL` d
          LEFT JOIN (SELECT DISTINCT campaign_id, keyword_id
                     FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`) h
            ON h.campaign_id = d.campaign_id AND h.keyword_id = d.keyword_id
          WHERE h.keyword_id IS NULL) AS violations
),
c10 AS (
  SELECT 'C10 every snapshot column exists in the history, same type' AS check_name,
         (SELECT COUNT(*)
          FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS` s
          LEFT JOIN `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS` h
            ON h.table_name = 'FACT_KEYWORD_STATE_HISTORY'
           AND h.column_name = s.column_name
           AND h.data_type = s.data_type
          WHERE s.table_name = 'FACT_KEYWORD_STATE'
            AND h.column_name IS NULL) AS violations
),
c11 AS (
  SELECT 'C11 content fidelity for the live date, not just row count' AS check_name,
         (SELECT COUNTIF(
             s.campaign_id IS NULL OR h.campaign_id IS NULL
             OR s.state IS DISTINCT FROM h.state
             OR s.owner_engine IS DISTINCT FROM h.owner_engine
             OR s.state_reason IS DISTINCT FROM h.state_reason
             OR s.next_check_date IS DISTINCT FROM h.next_check_date
             OR s.settled_roas90 IS DISTINCT FROM h.settled_roas90
             OR s.settled_clk90 IS DISTINCT FROM h.settled_clk90
             OR s.family_bar IS DISTINCT FROM h.family_bar
             OR s.affordable_cpc IS DISTINCT FROM h.affordable_cpc
             OR s.affordable_bid IS DISTINCT FROM h.affordable_bid
             OR s.bid_floor IS DISTINCT FROM h.bid_floor
             OR s.current_bid IS DISTINCT FROM h.current_bid
             OR s.prior_state IS DISTINCT FROM h.prior_state)
          FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
          FULL OUTER JOIN (
            SELECT * FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
             WHERE snapshot_date = (SELECT d FROM live)) h
            ON h.campaign_id = s.campaign_id AND h.keyword_id = s.keyword_id) AS violations
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM (SELECT * FROM c01 UNION ALL SELECT * FROM c02 UNION ALL SELECT * FROM c03
      UNION ALL SELECT * FROM c04 UNION ALL SELECT * FROM c05 UNION ALL SELECT * FROM c06
      UNION ALL SELECT * FROM c07 UNION ALL SELECT * FROM c08 UNION ALL SELECT * FROM c09
      UNION ALL SELECT * FROM c10 UNION ALL SELECT * FROM c11)
ORDER BY check_name;
