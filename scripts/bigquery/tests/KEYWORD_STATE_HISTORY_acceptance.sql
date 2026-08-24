-- =============================================================================================
-- FACT_KEYWORD_STATE_HISTORY + SP_APPEND_KEYWORD_STATE_HISTORY + V_CATALOG_DWELL
-- acceptance — v27.145 (2026-08-25). EVERY ROW MUST READ PASS.
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
--   C12 ONE captured_at PER snapshot_date (added v27.144). This is the invariant the write step's
--       prune enforces, stated at the stamp level rather than the row level: if an append's INSERT
--       succeeds and its prune fails, the date carries two stamps. C03 sees the resulting duplicate
--       rows; C12 names the cause, and it is the check that proves the prune is now keyed on the
--       history's OWN duplicate stamps rather than on whichever date the live snapshot happens to
--       carry. Under the old date-scoped prune a strand left on the last pass of an LA day could
--       never be reached again by any later call — C12 would have stayed red permanently.
--   C13 PROVENANCE IS MONOTONE IN snapshot_date (added v27.144). A day's captured_at may never be
--       later than the captured_at of a day that follows it. This is what a restamp looks like from
--       the data: a pass where Task 20.8 FAILED still reaches the append with the previous build's
--       table standing, and re-copying it would stamp an older partition with tonight's time — the
--       rows identical, the provenance a lie about when the Catalog spoke. GUARD 3 in the write
--       step refuses that copy; C13 is the alarm if it ever stops doing so. Strictly stronger than
--       C05, which compares older partitions only against the newest one.
--       ONE BENIGN PATH CAN TRIP C13, AND IT IS LEFT LOUD RATHER THAN EXCUSED. If the history ever
--       MISSES a day and a later pass then runs against a stale snapshot carrying exactly that
--       missing day, GUARD 3 lets the append through — deliberately, because a day the history does
--       not hold is memory GAINED, not provenance rewritten — and the gap-filling partition lands
--       with a stamp later than the day after it. C13 goes red on an out-of-order write that lost
--       nothing. That is the right trade: the check names something a person should look at, and
--       silencing it would also silence the restamp it exists to catch. Separate the two by reading
--       the offending partition's source_detail, which names what was read and when.
--   C14 THE BUILD CLOCK (added v27.145). C13 could not see a restamp that happens INSIDE one LA
--       day, and neither could C05 — both compare captured_at across partitions, and a same-day
--       restamp moves the newest partition's stamp, which is the one partition they use as the
--       reference rather than test. That blind spot was not exotic: snapshot_date is
--       CURRENT_DATE('America/Los_Angeles') and several passes share one LA date every night, so
--       a pass whose Task 20.8 FAILED restamped the day it did not build, silently, and the first
--       shape of GUARD 3 — which asked only whether the date was older than today — waved it
--       through. Measured against live state at the time: the guard refused nothing, one partition
--       was restamped, and C05, C12 and C13 all read 0.
--       WHAT THE COMMITTED DATA CAN AND CANNOT PROVE — SAID PLAINLY, BECAUSE THE FIRST DRAFT OF
--       THIS CHECK GOT IT WRONG AND A CHECK THAT ONLY LOOKS LIKE COVERAGE IS WORSE THAN NONE.
--       The draft asserted that a partition's build must postdate the captured_at of the partition
--       before it. Measured, it was wrong twice over: it read 1 violation against an HONEST history
--       (the backfill wrote seven old partitions with a fresh capture time, so an ordinary build
--       predates the capture of the day before it — a false alarm at the backfill boundary), and
--       against a clean steady-state history carrying a genuine same-day restamp it read 0. It
--       neither held on good data nor fired on bad.
--       The reason is structural, and worth keeping written down: a restamp moves captured_at while
--       snapshot_built_at stands still, and the result is INDISTINGUISHABLE from an honest write in
--       which the build simply happened earlier in the same day. Both are legal orderings of the
--       same two clocks. No predicate over the committed rows separates them. This is a property
--       enforced at WRITE time or not at all — which is what GUARD 3 is.
--       So C14 asserts the two things that ARE provable, and claims nothing more:
--         (a) DATA. No partition records a build LATER than the moment it was written. A row
--             cannot have read a build that had not happened yet; this is a genuine invariant and
--             it is what the clock makes checkable at all.
--         (b) STRUCTURE. The deployed SP_APPEND_KEYWORD_STATE_HISTORY still reads the snapshot's
--             last_modified_time, still compares it against the stamp the history holds, and still
--             records snapshot_built_at. This is the honest way to assert a write-time guarantee
--             that leaves no footprint in the data: check that the guarantee is still installed.
--             Delete the guard and this goes red on the next run of the suite — which is precisely
--             the alarm that was missing when the same-day restamp was silent.
--       HONEST SCOPE OF (a): it is SILENT on every row written before v27.145, because those rows
--       carry NULL for snapshot_built_at — they did not record it, and inventing a value would be
--       the fabrication this whole object exists to refuse. Until the first pass appends under
--       v27.145 (a) reads 0 for want of evidence, not for want of violations; (b) has teeth today.
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
),
c12 AS (
  SELECT 'C12 one captured_at per snapshot_date: no stranded second copy' AS check_name,
         (SELECT COUNT(*) FROM (
            SELECT snapshot_date
            FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
            GROUP BY snapshot_date
            HAVING COUNT(DISTINCT captured_at) > 1)) AS violations
),
c13 AS (
  SELECT 'C13 provenance is monotone in snapshot_date: no day restamped later' AS check_name,
         (SELECT COUNTIF(ts > next_ts) FROM (
            SELECT MAX(captured_at) AS ts,
                   LEAD(MAX(captured_at)) OVER (ORDER BY snapshot_date) AS next_ts
            FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
            GROUP BY snapshot_date)) AS violations
),
c14 AS (
  -- One representative row per snapshot_date, taken from the NEWEST stamp: captured_at and
  -- snapshot_built_at must come from the SAME row, so this picks a row rather than pairing two
  -- independent aggregates (paired MAX/ANY_VALUE over one GROUP BY is not a coherent pair when a
  -- date carries a strand). Rows within one stamp are identical on both columns by construction.
  SELECT 'C14 build clock is real, and the guard that uses it is deployed' AS check_name,
         (SELECT COUNTIF(built > cap)
          FROM (
            SELECT captured_at AS cap, snapshot_built_at AS built
            FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
            QUALIFY ROW_NUMBER() OVER (PARTITION BY snapshot_date
                                       ORDER BY captured_at DESC) = 1)
          WHERE built IS NOT NULL)
       + (SELECT COUNTIF(NOT (
            REGEXP_CONTAINS(ddl, r'last_modified_time')
            AND REGEXP_CONTAINS(ddl, r'snap_built_at\s*<=\s*stored_stamp')
            AND REGEXP_CONTAINS(ddl, r'snapshot_built_at')))
          FROM `onyga-482313.OI.INFORMATION_SCHEMA.ROUTINES`
          WHERE routine_name = 'SP_APPEND_KEYWORD_STATE_HISTORY') AS violations
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM (SELECT * FROM c01 UNION ALL SELECT * FROM c02 UNION ALL SELECT * FROM c03
      UNION ALL SELECT * FROM c04 UNION ALL SELECT * FROM c05 UNION ALL SELECT * FROM c06
      UNION ALL SELECT * FROM c07 UNION ALL SELECT * FROM c08 UNION ALL SELECT * FROM c09
      UNION ALL SELECT * FROM c10 UNION ALL SELECT * FROM c11 UNION ALL SELECT * FROM c12
      UNION ALL SELECT * FROM c13 UNION ALL SELECT * FROM c14)
ORDER BY check_name;
