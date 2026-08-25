-- =============================================================================================
-- FACT_SEAT_REQUEST acceptance — the Brain's ledger. v27.147 (2026-08-25). Plan step 5, §6.0.
-- Every check returns a VIOLATION COUNT; every row must read PASS.
-- Run: bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
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

-- R02 the ledger's latest day matches the plan's seated rows EXACTLY, count and content.
r02 AS (SELECT
          (SELECT COUNT(*) FROM plan_seats) -
          (SELECT COUNT(*) FROM led WHERE requested_on = (SELECT d FROM plan_day)) AS v),

-- R03 APPEND-ONLY GRAIN: one row per (requested_on, plan, campaign, keyword).
r03 AS (SELECT COUNTIF(n > 1) AS v
        FROM (SELECT requested_on, plan, campaign_id, keyword_id, COUNT(*) AS n
              FROM led GROUP BY 1,2,3,4)),

-- R04 NO PROMISE WITHOUT A QUESTION. Every row carries a seat, a positive click count, a basis
--     and a due date — the ledger exists to be graded and an ungradeable row is dead weight.
r04 AS (SELECT COUNTIF(seat_no IS NULL OR clicks_requested IS NULL OR clicks_requested <= 0
                       OR clicks_due_date IS NULL OR request_basis IS NULL
                       OR request_basis NOT IN ('WINDOW_CLICKS','PROBE_GOAL')) AS v FROM led),

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

-- R09 PARTITION INTEGRITY: no NULL and no future requested_on.
r09 AS (SELECT COUNTIF(requested_on IS NULL
                       OR requested_on > CURRENT_DATE('America/Los_Angeles')) AS v FROM led),

-- R10 THE CLAIM TRAVELS WITH THE PROMISE. §6.0 grades the Catalog on whether its recommendation
--     performed as claimed, and a promise stripped of the claim behind it can be counted but not
--     graded. Every row must carry the bar it was measured against.
r10 AS (SELECT COUNTIF(family_bar IS NULL) AS v FROM led),

-- R11 THE ARITHMETIC SURVIVES THE COPY: implied_daily_spend still equals clicks x cpc / days.
r11 AS (SELECT COUNTIF(ABS(implied_daily_spend
                           - SAFE_DIVIDE(clicks_requested * expected_cpc, window_days)) > 0.01) AS v
        FROM led WHERE expected_cpc IS NOT NULL),

-- R12 READ-ONLY BY CONSTRUCTION: nothing in the warehouse reads this table yet, and the day it
--     does is a decision, not an accident.
r12 AS (SELECT COUNT(*) AS v FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS`
        WHERE view_definition LIKE '%FACT_SEAT_REQUEST%')

SELECT * FROM (
  SELECT 1 AS n, 'R01 one captured_at per requested_on'                     AS check_name, v FROM r01 UNION ALL
  SELECT 2,  'R02 the ledger matches the plan seats exactly',                   v FROM r02 UNION ALL
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
