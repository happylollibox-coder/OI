-- =============================================================================================
-- PLAN_SEAT_REQUEST acceptance — the seat names its question. v27.146 (2026-08-25). Plan step 4.
-- Violation 27, §3.0 step 2. Every check returns a VIOLATION COUNT; every row must read PASS.
-- Run: bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
--
-- v27.159 (2026-10-02, piece-1 plan Task 5, Ori's ruling R13 = spec P-26): THE QUESTION SPANS THE
-- SETTLE HORIZON. S03, S06, S07 and S11 are restated: the horizon of a seat's question is
-- DATE_DIFF(clicks_due_date, seat_since) — the settle horizon, since a seat's verdict date is the
-- night it took the seat plus settle_days — not window_days; an ordinary NEW seat asks
-- ROUND(w_clk x horizon / window_days) (basis HORIZON_WINDOW_RATE), a probe a whole number of days at
-- its goal (HORIZON_PROBE_GOAL); an incumbent repeats the question it was given (P-16), checked by
-- FACT_PLAN_NEXT_WEEK_acceptance.sql T1. Bases written before v27.159 (WINDOW_CLICKS, PROBE_GOAL)
-- keep their own arithmetic, for a latest partition written before it.
-- RUN 2026-10-02 (Los Angeles) on the v27.159 partition: 11 rows, every one 0. NEGATIVE CONTROLS, by
-- scripts/bigquery/tests/check_plan_seat_controls.py on doctored copies of the plan table (2026-10-03
-- 02:01–02:10 UTC, job bqjob_r4ed37cefafebd407_000001a0ff7ee55d_1, exit 0, every copy exercised):
-- LIVE 0 on all 11; one seat's clicks doubled: S03 1 (and S06 1); one new ordinary seat asking w_clk
-- under HORIZON_WINDOW_RATE: S06 1 (and S03 1); the seated probe (HORIZON_PROBE_GOAL) asking one click
-- more than a whole number of days, its CPC restated so clicks x CPC / horizon still equals its
-- implied spend: S07 1, S03 0; one seat's request_basis 'BOGUS': S11 1. Results also in
-- FACT_PLAN_NEXT_WEEK_acceptance.sql.
-- =============================================================================================
WITH latest AS (
  SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`)
),
seated AS (SELECT * FROM latest WHERE seat_no IS NOT NULL),

-- S01 every seat names a click count. A seat that says only "$0.93/day" is not a question.
s01 AS (SELECT COUNTIF(clicks_requested IS NULL OR clicks_requested <= 0) AS v FROM seated),

-- S02 every seat names a date, and it is the date the seat already promises to be judged on
--     (P-12's verdict_date). NOT window_to: that closes the window that was JUDGED, which is in
--     the past — it is the evidence, not the horizon. The first cut used it and S08 caught all 94.
s02 AS (SELECT COUNTIF(clicks_due_date IS NULL OR clicks_due_date != verdict_date) AS v FROM seated),

-- S03 the arithmetic re-derives from the row itself, without re-reading the view.
--     implied_daily_spend = clicks_requested x expected_cpc / the question's horizon, to the cent:
--     DATE_DIFF(clicks_due_date, seat_since) since v27.159 (P-26), window_days before it.
s03 AS (SELECT COUNTIF(ABS(implied_daily_spend
                           - SAFE_DIVIDE(clicks_requested * expected_cpc,
                                         IF(request_basis IN ('WINDOW_CLICKS', 'PROBE_GOAL'), window_days,
                                            DATE_DIFF(clicks_due_date, seat_since, DAY)))) > 0.01
                       OR (request_basis NOT IN ('WINDOW_CLICKS', 'PROBE_GOAL') AND seat_since IS NULL)) AS v
        FROM seated WHERE expected_cpc IS NOT NULL),

-- S04 the seat's own dollars and the request's dollars are the same money. If these ever diverge
--     the request is describing a seat the Brain did not actually fund.
s04 AS (SELECT COUNTIF(ABS(implied_daily_spend - seat_cost_per_day) > 0.01) AS v
        FROM seated WHERE seat_cost_per_day IS NOT NULL),

-- S05 NO REQUEST WITHOUT A SEAT. A row that took no seat asked no question, and publishing a click
--     target on it would invent an intention the Brain never had.
s05 AS (SELECT COUNTIF(clicks_requested IS NOT NULL OR clicks_due_date IS NOT NULL) AS v
        FROM latest WHERE seat_no IS NULL),

-- S06 an ORDINARY seat asks for the window's click rate over its horizon — the price ratio cancels,
--     so this is arithmetic and not an estimate. A mismatch means someone introduced a forecast.
--     v27.159 (P-26): ROUND(w_clk x horizon / window_days) on a seat taken tonight (an incumbent's
--     window is the one it was seated on); exactly w_clk on a pre-v27.159 WINDOW_CLICKS row.
s06 AS (SELECT COUNTIF((request_basis = 'WINDOW_CLICKS' AND clicks_requested != w_clk)
                       OR (request_basis = 'HORIZON_WINDOW_RATE' AND seat_since = as_of
                           AND clicks_requested != CAST(ROUND(w_clk * DATE_DIFF(clicks_due_date, seat_since, DAY)
                                                              / window_days) AS INT64))) AS v
        FROM seated),

-- S07 a PROBE asks for a whole number of days at the register's declared goal (over its horizon
--     since v27.159, over window_days before it).
s07 AS (SELECT COUNTIF((request_basis = 'PROBE_GOAL' AND MOD(clicks_requested, window_days) != 0)
                       OR (request_basis = 'HORIZON_PROBE_GOAL'
                           AND MOD(clicks_requested, DATE_DIFF(clicks_due_date, seat_since, DAY)) != 0)) AS v
        FROM seated),

-- S08 the due date is never in the past at build time — a request that was already overdue when it
--     was written cannot be delivered and would grade as a Pacing failure that never had a chance.
s08 AS (SELECT COUNTIF(clicks_due_date < as_of) AS v FROM seated),

-- S09 expected_cpc is a price, not a bid, and never absurd. Above $10 on this account means the
--     arithmetic inverted somewhere (dividing by clicks that are actually spend, say).
s09 AS (SELECT COUNTIF(expected_cpc <= 0 OR expected_cpc > 10.0) AS v
        FROM seated WHERE expected_cpc IS NOT NULL),

-- S10b every request states how it was derived; an unexplained number is not checkable.
s10b AS (SELECT COUNTIF(request_basis IS NULL
                        OR request_basis NOT IN ('WINDOW_CLICKS','PROBE_GOAL',
                                                 'HORIZON_WINDOW_RATE','HORIZON_PROBE_GOAL')) AS v FROM seated),

-- S10 both plans are written, and both carry requests — the shadow plan is graded too (P-9).
s10 AS (SELECT COUNTIF(n = 0) AS v
        FROM (SELECT plan, COUNTIF(clicks_requested IS NOT NULL) AS n FROM latest GROUP BY plan))

SELECT * FROM (
  SELECT 1 AS n, 'S01 every seat names a click count'                              AS check_name, v FROM s01 UNION ALL
  SELECT 2, 'S02 every seat names a date, and it is the window it funds',              v FROM s02 UNION ALL
  SELECT 3, 'S03 implied spend re-derives from the row itself',                        v FROM s03 UNION ALL
  SELECT 4, 'S04 the request and the seat are the same money',                         v FROM s04 UNION ALL
  SELECT 5, 'S05 no request without a seat',                                           v FROM s05 UNION ALL
  SELECT 6, 'S06 an ordinary seat asks for the window click rate over its horizon',   v FROM s06 UNION ALL
  SELECT 7, 'S07 a probe asks for whole days at the declared goal',                    v FROM s07 UNION ALL
  SELECT 8, 'S08 no request is overdue on the day it is written',                      v FROM s08 UNION ALL
  SELECT 9, 'S09 expected_cpc is a plausible price',                                   v FROM s09 UNION ALL
  SELECT 10, 'S10 both plans carry requests',                                          v FROM s10 UNION ALL
  SELECT 11, 'S11 every request states how it was derived',                            v FROM s10b
)
ORDER BY n;
