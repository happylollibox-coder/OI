-- =============================================================================================
-- PLAN_SEAT_REQUEST acceptance — the seat names its question. v27.146 (2026-08-25). Plan step 4.
-- Violation 27, §3.0 step 2. Every check returns a VIOLATION COUNT; every row must read PASS.
-- Run: bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
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
--     implied_daily_spend = clicks_requested x expected_cpc / window_days, to the cent.
s03 AS (SELECT COUNTIF(ABS(implied_daily_spend
                           - SAFE_DIVIDE(clicks_requested * expected_cpc, window_days)) > 0.01) AS v
        FROM seated WHERE expected_cpc IS NOT NULL),

-- S04 the seat's own dollars and the request's dollars are the same money. If these ever diverge
--     the request is describing a seat the Brain did not actually fund.
s04 AS (SELECT COUNTIF(ABS(implied_daily_spend - seat_cost_per_day) > 0.01) AS v
        FROM seated WHERE seat_cost_per_day IS NOT NULL),

-- S05 NO REQUEST WITHOUT A SEAT. A row that took no seat asked no question, and publishing a click
--     target on it would invent an intention the Brain never had.
s05 AS (SELECT COUNTIF(clicks_requested IS NOT NULL OR clicks_due_date IS NOT NULL) AS v
        FROM latest WHERE seat_no IS NULL),

-- S06 an ORDINARY seat asks for exactly last window's clicks — the price ratio cancels, so this is
--     arithmetic and not an estimate. A mismatch means someone introduced a forecast.
s06 AS (SELECT COUNTIF(clicks_requested != w_clk) AS v
        FROM seated WHERE request_basis = 'WINDOW_CLICKS'),

-- S07 a PROBE asks for a whole number of days at the register's declared goal.
s07 AS (SELECT COUNTIF(MOD(clicks_requested, window_days) != 0) AS v
        FROM seated WHERE request_basis = 'PROBE_GOAL'),

-- S08 the due date is never in the past at build time — a request that was already overdue when it
--     was written cannot be delivered and would grade as a Pacing failure that never had a chance.
s08 AS (SELECT COUNTIF(clicks_due_date < as_of) AS v FROM seated),

-- S09 expected_cpc is a price, not a bid, and never absurd. Above $10 on this account means the
--     arithmetic inverted somewhere (dividing by clicks that are actually spend, say).
s09 AS (SELECT COUNTIF(expected_cpc <= 0 OR expected_cpc > 10.0) AS v
        FROM seated WHERE expected_cpc IS NOT NULL),

-- S10b every request states how it was derived; an unexplained number is not checkable.
s10b AS (SELECT COUNTIF(request_basis IS NULL
                        OR request_basis NOT IN ('WINDOW_CLICKS','PROBE_GOAL')) AS v FROM seated),

-- S10 both plans are written, and both carry requests — the shadow plan is graded too (P-9).
s10 AS (SELECT COUNTIF(n = 0) AS v
        FROM (SELECT plan, COUNTIF(clicks_requested IS NOT NULL) AS n FROM latest GROUP BY plan))

SELECT * FROM (
  SELECT 1 AS n, 'S01 every seat names a click count'                              AS check_name, v FROM s01 UNION ALL
  SELECT 2, 'S02 every seat names a date, and it is the window it funds',              v FROM s02 UNION ALL
  SELECT 3, 'S03 implied spend re-derives from the row itself',                        v FROM s03 UNION ALL
  SELECT 4, 'S04 the request and the seat are the same money',                         v FROM s04 UNION ALL
  SELECT 5, 'S05 no request without a seat',                                           v FROM s05 UNION ALL
  SELECT 6, 'S06 an ordinary seat asks for exactly last window clicks',                v FROM s06 UNION ALL
  SELECT 7, 'S07 a probe asks for whole days at the declared goal',                    v FROM s07 UNION ALL
  SELECT 8, 'S08 no request is overdue on the day it is written',                      v FROM s08 UNION ALL
  SELECT 9, 'S09 expected_cpc is a plausible price',                                   v FROM s09 UNION ALL
  SELECT 10, 'S10 both plans carry requests',                                          v FROM s10 UNION ALL
  SELECT 11, 'S11 every request states how it was derived',                            v FROM s10b
)
ORDER BY n;
