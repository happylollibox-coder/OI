-- =============================================================================================
-- FACT_SEAT_REQUEST acceptance — the Brain's ledger. v27.147 (2026-08-25). Plan step 5, §6.0.
-- Every check returns a VIOLATION COUNT; every row must read PASS.
-- Run: bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
--
-- v27.159 (2026-10-02, piece-1 plan Task 5, spec P-26): R04 accepts the two bases written from
-- v27.159 (HORIZON_WINDOW_RATE, HORIZON_PROBE_GOAL) and R11 divides each row by the horizon its basis
-- was written with — window_days for WINDOW_CLICKS / PROBE_GOAL, the settle horizon for the new two:
-- SP 7 days, SB 14 (the judge's settle_days: IF(channel = 'SB', 14, 7)), since a seat's due date
-- is the night it took the seat plus settle_days and an incumbent repeats that question (P-16).
-- R12 read 1 before this change (V_SEAT_REQUEST_OUTCOME reads the table); not touched here.
-- RUN 2026-10-02 (Los Angeles): R01..R11 0, R12 1. NEGATIVE CONTROLS on doctored copies of the ledger
-- (this file's own text with FACT_SEAT_REQUEST swapped for the copy; the doctored row is the latest
-- WINDOW_CLICKS row, SP, w_clk 4 in 3 days): LIVE R04 0 R11 0; that row restated under
-- HORIZON_WINDOW_RATE with coherent arithmetic (9 clicks, CPC = implied x 7 / 9): R04 0, R11 0; its
-- implied spend doubled: R11 1; the coherent row labelled WINDOW_CLICKS: R11 1; basis 'BOGUS': R04 1.
--
-- v27.160 follow-up (2026-10-03, piece-1 plan Task 6 review, spec P-24): R09 reads "future" on the
-- New York date, the clock requested_on is keyed on (SP_APPEND_SEAT_REQUEST copies the plan's as_of).
-- NEGATIVE CONTROLS, run 2026-10-03 03:32 UTC: this file's own text, comment lines stripped, with
-- FACT_SEAT_REQUEST swapped for a copy (OI._tmp_t6f_seat_*) and the one CURRENT_DATE token pinned to
-- DATE(TIMESTAMP '2026-10-03 05:40:00+00', tz) = 01:40 New York 10-03 = 22:40 Los Angeles 10-02, inside
-- the 01:35 New York pass; "old" is the 7af4857 text (Los Angeles clock) run the same way. Every copy is
-- the live ledger plus the change named. Jobs t6f_seat_run0..8_033202, 76.4 slot-seconds in all
-- including the four copies; nothing here reads FACT_AMAZON_ADS.
--   LIVE, real clock (20:32 Los Angeles, both dates 10-02): new R01..R11 0, R12 1; old the same.
--   LIVE, pinned: new and old R01..R11 0, R12 1.
--   NC_NY_PASS  the 10-02 partition (118 rows) copied as requested_on 10-03, captured 05:35:46 UTC 10-03,
--               due dates +1 day — what the 01:35 New York pass writes: new R09 0; old R09 118, the
--               false fail by construction this change removes. Other checks as LIVE.
--   NC_FUTURE   the same 118 rows as requested_on 10-04, one day past the New York date: new R09 118.
--   NC_NULL     one 10-02 row copied with a NULL requested_on: new R09 1 (and R06 1, its lone plan arm).
--   NC_EMPTY    no rows: R09 reads 0 on an empty ledger; R02 is its emptiness term and reads 118 (the
--               plan's seats on its latest partition with none in the ledger).
--
-- piece-1 follow-up F6 (2026-10-03): R02 compares the (plan, campaign_id, keyword_id) keys of the plan's
-- latest seats with the ledger's partition for that as_of, both ways, instead of subtracting row counts.
-- NEGATIVE CONTROLS, run 2026-10-03 10:29 UTC: this file's own text, comment lines stripped, with
-- FACT_SEAT_REQUEST and FACT_PLAN_NEXT_WEEK swapped for copies taken at 10:28 UTC (job
-- f6_setup_1791023296: OI._tmp_f6_plan, _tmp_f6_plan_empty, _tmp_f6_led_*); "old" is the 90c1ed3 text
-- run the same way. Jobs f6_*_102917, 134.0 slot-seconds (plus 15.6 for the copies); nothing here reads
-- FACT_AMAZON_ADS. The plan's latest partition is 2026-10-03, 126 seats, built_at 08:58:26 UTC; the
-- ledger's 2026-10-03 partition holds 125 rows appended from the 08:12:08 UTC build.
--   LIVE          real tables and their copies alike: new R02 9 (5 plan seats missing from the ledger,
--                 4 ledger rows the 08:58 build no longer seats); old R02 1. A true staleness alarm
--                 (NOTE ON R02 below).
--   NC_SYNC       the 10-03 partition rewritten from the plan copy as SP_APPEND_SEAT_REQUEST writes it:
--                 new 0, old 0.
--   NC_SWAP       NC_SYNC with one 10-03 row's keyword_id replaced, row counts equal: new 2, old 0.
--   NC_EXTRA      NC_SYNC plus one 10-03 row on a keyword the plan does not seat: new 1, old -1.
--   NC_MISSING    NC_SYNC minus one 10-03 row: new 1, old 1.
--   NC_ARM        NC_SYNC with one plan-A row relabelled B, on a keyword plan B does not seat: new 2, old 0.
--   NC_EMPTY      an empty ledger: new 126, old 126 (emptiness term).
--   NC_PLAN_EMPTY an empty plan table, ledger as NC_SYNC: new 1 (emptiness term), old 0.
--   Every other check read the same on every copy under both texts: R01, R03..R11 0, R12 1.
--
-- NOTE ON R02: the ledger is expected to go RED if the plan is rebuilt without the append. That is
-- a true staleness alarm, not a false one, and the fix is CALL SP_APPEND_SEAT_REQUEST(), which is
-- safe at any time.
-- =============================================================================================
WITH led AS (SELECT * FROM `onyga-482313.OI.FACT_SEAT_REQUEST`),
plan_day AS (SELECT MAX(as_of) AS d FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`),
plan_seats AS (
  SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of = (SELECT d FROM plan_day) AND seat_no IS NOT NULL AND clicks_requested IS NOT NULL),

-- R01 ONE captured_at per requested_on. A second stamp is a strand from a crash between the
--     insert and the prune, and it must be repairable by any later call.
r01 AS (SELECT COUNTIF(stamps > 1) AS v
        FROM (SELECT requested_on, COUNT(DISTINCT captured_at) AS stamps FROM led GROUP BY 1)),

-- R02 the ledger's partition for the plan's latest as_of holds EXACTLY the plan's seated keys
--     (plan, campaign_id, keyword_id), compared both ways: plan seats missing from the ledger plus
--     ledger rows the plan no longer seats. The value is a sum of two counts and is never negative.
--     Until piece-1 follow-up F6 (2026-10-03) it subtracted the two row counts, so equal counts over
--     different keywords read 0 and a ledger holding more rows than the plan read negative (the Task 10
--     proof read -1). Multiplicity is R03's (one row per key); NULL keys compare equal under EXCEPT
--     DISTINCT (measured: NULL EXCEPT DISTINCT NULL is 0 rows). Emptiness terms: an empty ledger reads
--     the plan's seat count (NC_EMPTY); no plan partition at all reads 1 (NC_PLAN_EMPTY), where the
--     counts form read 0. Controls in the F6 block of the header.
r02 AS (SELECT
          (SELECT COUNT(*) FROM (
             SELECT plan, campaign_id, keyword_id FROM plan_seats
             EXCEPT DISTINCT
             SELECT plan, campaign_id, keyword_id FROM led WHERE requested_on = (SELECT d FROM plan_day)))
        + (SELECT COUNT(*) FROM (
             SELECT plan, campaign_id, keyword_id FROM led WHERE requested_on = (SELECT d FROM plan_day)
             EXCEPT DISTINCT
             SELECT plan, campaign_id, keyword_id FROM plan_seats))
        + IF((SELECT d FROM plan_day) IS NULL, 1, 0) AS v),

-- R03 APPEND-ONLY GRAIN: one row per (requested_on, plan, campaign, keyword).
r03 AS (SELECT COUNTIF(n > 1) AS v
        FROM (SELECT requested_on, plan, campaign_id, keyword_id, COUNT(*) AS n
              FROM led GROUP BY 1,2,3,4)),

-- R04 NO PROMISE WITHOUT A QUESTION. Every row carries a seat, a positive click count, a basis
--     and a due date — the ledger exists to be graded and an ungradeable row is dead weight.
r04 AS (SELECT COUNTIF(seat_no IS NULL OR clicks_requested IS NULL OR clicks_requested <= 0
                       OR clicks_due_date IS NULL OR request_basis IS NULL
                       OR request_basis NOT IN ('WINDOW_CLICKS','PROBE_GOAL',
                                                'HORIZON_WINDOW_RATE','HORIZON_PROBE_GOAL')) AS v FROM led),

-- R05 NO ROW IS EVER MUTATED: an earlier partition can never be rewritten by a later pass, so its
--     captured_at must not be newer than the newest partition's.
r05 AS (SELECT COUNTIF(c > newest) AS v FROM (
          SELECT MAX(captured_at) AS c,
                 (SELECT MAX(captured_at) FROM led
                  WHERE requested_on = (SELECT MAX(requested_on) FROM led)) AS newest
          FROM led WHERE requested_on < (SELECT MAX(requested_on) FROM led)
          GROUP BY requested_on)),

-- R06 BOTH PLAN ARMS are recorded. Grading only the live one makes the shadow plan's
--     counterfactual unmeasurable, which is the whole reason it is run (P-9).
r06 AS (SELECT COUNTIF(plans < 2) AS v
        FROM (SELECT requested_on, COUNT(DISTINCT plan) AS plans FROM led GROUP BY 1)),

-- R07 A REQUEST IS NEVER BORN OVERDUE. A due date on or before the day it was written could not
--     be delivered and would grade as a Pacing failure that never had a chance.
r07 AS (SELECT COUNTIF(clicks_due_date <= requested_on) AS v FROM led),

-- R08 PROVENANCE on every row, from a closed set.
r08 AS (SELECT COUNTIF(captured_at IS NULL OR source IS NULL
                       OR source NOT IN ('ORCHESTRATOR','MANUAL')
                       OR source_detail IS NULL OR source_detail = '') AS v FROM led),

-- R09 PARTITION INTEGRITY: no NULL and no future requested_on. "Future" is read on the clock
--     requested_on is keyed on: SP_APPEND_SEAT_REQUEST copies FACT_PLAN_NEXT_WEEK.as_of, which is the
--     New York date since v27.160 (P-24). The 01:35 New York pass runs at about 22:35 Los Angeles and
--     writes the next day's requested_on, so the Los Angeles form counted that night's whole partition
--     from about 22:35 to 24:00 Los Angeles every day (control NC_NY_PASS in the header).
r09 AS (SELECT COUNTIF(requested_on IS NULL
                       OR requested_on > CURRENT_DATE('America/New_York')) AS v FROM led),

-- R10 THE CLAIM TRAVELS WITH THE PROMISE. §6.0 grades the Catalog on whether its recommendation
--     performed as claimed, and a promise stripped of the claim behind it can be counted but not
--     graded. Every row must carry the bar it was measured against.
r10 AS (SELECT COUNTIF(family_bar IS NULL) AS v FROM led),

-- R11 THE ARITHMETIC SURVIVES THE COPY: implied_daily_spend still equals clicks x cpc / days.
r11 AS (SELECT COUNTIF(ABS(implied_daily_spend
                           - SAFE_DIVIDE(clicks_requested * expected_cpc,
                                         IF(request_basis IN ('WINDOW_CLICKS', 'PROBE_GOAL'), window_days,
                                            IF(channel = 'SB', 14, 7)))) > 0.01) AS v
        FROM led WHERE expected_cpc IS NOT NULL),

-- R12 READ-ONLY BY CONSTRUCTION: nothing in the warehouse reads this table yet, and the day it
--     does is a decision, not an accident.
r12 AS (SELECT COUNT(*) AS v FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS`
        WHERE view_definition LIKE '%FACT_SEAT_REQUEST%')

SELECT * FROM (
  SELECT 1 AS n, 'R01 one captured_at per requested_on'                     AS check_name, v FROM r01 UNION ALL
  SELECT 2,  'R02 the ledger holds the plan seat keys, both ways',              v FROM r02 UNION ALL
  SELECT 3,  'R03 one row per (day, plan, campaign, keyword)',                  v FROM r03 UNION ALL
  SELECT 4,  'R04 no promise without a question',                               v FROM r04 UNION ALL
  SELECT 5,  'R05 no row is ever mutated',                                      v FROM r05 UNION ALL
  SELECT 6,  'R06 both plan arms are recorded',                                 v FROM r06 UNION ALL
  SELECT 7,  'R07 no request is born overdue',                                  v FROM r07 UNION ALL
  SELECT 8,  'R08 provenance on every row',                                     v FROM r08 UNION ALL
  SELECT 9,  'R09 partition integrity',                                         v FROM r09 UNION ALL
  SELECT 10, 'R10 the Catalog claim travels with the promise',                  v FROM r10 UNION ALL
  SELECT 11, 'R11 the arithmetic survives the copy',                            v FROM r11 UNION ALL
  SELECT 12, 'R12 nothing reads it yet',                                        v FROM r12
)
ORDER BY n;
