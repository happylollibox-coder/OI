-- =============================================================================================
-- V_SEAT_REQUEST_OUTCOME acceptance — the delivery grade. v27.148 (2026-08-25). Plan step 6, §6.0.
-- Every check returns a VIOLATION COUNT; every row must read PASS.
--
-- READ THIS BEFORE TRUSTING A GREEN RUN. Until 2026-09-01 every promise is still open, so the
-- GRADING ARMS ARE UNEXERCISED BY LIVE DATA and O01/O02 pass because the view correctly refuses to
-- answer. Abstention is not correctness. O07 therefore exercises the delivery JOIN over a span that
-- has already happened, and O08 exercises the budget forward-fill, so the two pieces of machinery
-- the grades depend on are proven now rather than assumed until September.
-- =============================================================================================
WITH v AS (SELECT * FROM `onyga-482313.OI.V_SEAT_REQUEST_OUTCOME`),
wm AS (SELECT MAX(date) AS watermark FROM `onyga-482313.OI.FACT_AMAZON_ADS`),

-- O01 NO GRADE BEFORE THE WINDOW CLOSES. A grader that answers early is worse than no grader: it
--     marks Pacing down for clicks that still have days to arrive.
o01 AS (SELECT COUNTIF(clicks_due_date > (SELECT watermark FROM wm)
                       AND (pacing_grade != 'PENDING' OR catalog_grade != 'PENDING'
                            OR campaign_grade != 'PENDING')) AS v FROM v),

-- O02 THE CATALOG IS NEVER GRADED ON AN UNSETTLED WINDOW. SP accrues 7 days, SB 14; judging early
--     marks the Catalog down for sales that have not landed.
o02 AS (SELECT COUNTIF(settles_on > (SELECT watermark FROM wm)
                       AND catalog_grade NOT IN ('PENDING','PENDING_SETTLE')) AS v FROM v),

-- O03 ONE ROW PER PROMISE, not per nightly ask. The plan re-asks every night; the promise is the
--     thing kept or broken.
o03 AS (SELECT COUNTIF(n > 1) AS v FROM (
          SELECT plan, campaign_id, keyword_id, clicks_due_date, COUNT(*) AS n FROM v
          GROUP BY 1,2,3,4)),

-- O04 THE VIEW INVENTS NO PROMISE: every row traces to the ledger.
o04 AS (SELECT (SELECT COUNT(DISTINCT FORMAT('%s|%s|%s|%t', plan, campaign_id, keyword_id, clicks_due_date))
                FROM `onyga-482313.OI.FACT_SEAT_REQUEST`)
             - (SELECT COUNT(*) FROM v) AS v),

-- O05 THE ARITHMETIC: delivery_ratio is clicks_delivered / clicks_requested, to four places.
o05 AS (SELECT COUNTIF(ABS(delivery_ratio - SAFE_DIVIDE(clicks_delivered, clicks_requested)) > 0.0005) AS v
        FROM v WHERE clicks_requested > 0),

-- O06 READ-ONLY, and read by nothing. The day something reads it is a decision, not an accident.
o06 AS (SELECT (SELECT COUNT(*) FROM `onyga-482313.OI.INFORMATION_SCHEMA.TABLES`
                WHERE table_name = 'V_SEAT_REQUEST_OUTCOME' AND table_type != 'VIEW')
             + (SELECT COUNT(*) FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS`
                WHERE table_name != 'V_SEAT_REQUEST_OUTCOME'
                  AND view_definition LIKE '%V_SEAT_REQUEST_OUTCOME%') AS v),

-- O07 THE DELIVERY JOIN ACTUALLY FINDS CLICKS. The grades are unexercised until September, so the
--     machinery underneath them is proven here instead: over a span that HAS happened, the same
--     (campaign_id, targeting) join the view uses must return clicks for the ledger's own subjects.
--     A zero here would mean every future grade reads MISSED for a join fault, not a Pacing one.
o07 AS (SELECT IF(SUM(clk) > 0, 0, 1) AS v FROM (
          SELECT SUM(a.Ads_clicks) AS clk
          FROM (SELECT DISTINCT campaign_id, target_text FROM `onyga-482313.OI.FACT_SEAT_REQUEST`) r
          JOIN `onyga-482313.OI.FACT_AMAZON_ADS` a
            ON CAST(a.campaign_id AS STRING) = r.campaign_id
           AND LOWER(TRIM(a.targeting)) = LOWER(TRIM(r.target_text))
          WHERE a.date BETWEEN DATE_SUB((SELECT watermark FROM wm), INTERVAL 14 DAY)
                           AND (SELECT watermark FROM wm))),

-- O08 THE BUDGET FORWARD-FILL COVERS THE SPENDING DAYS. campaign_history records CHANGES, not days;
--     if the fill were wrong, days_measured would be far below the days the campaign actually spent
--     and every campaign_grade would read CARRIED for lack of evidence rather than for merit.
o08 AS (SELECT COUNTIF(days_measured IS NULL OR days_measured = 0) AS v
        FROM v WHERE first_asked_on <= (SELECT watermark FROM wm)),

-- O09 UNMEASURED NEVER READS AS BAD: a promise with no delivery data yet must not read MISSED.
o09 AS (SELECT COUNTIF(clicks_delivered = 0 AND pacing_grade = 'MISSED'
                       AND clicks_due_date > (SELECT watermark FROM wm)) AS v FROM v),

-- O10 EVERY ROW CARRIES A SENTENCE. §9: an action a person cannot read is not explained.
o10 AS (SELECT COUNTIF(sentence IS NULL OR sentence = '') AS v FROM v)

SELECT * FROM (
  SELECT 1 AS n, 'O01 no grade before the window closes'                AS check_name, v FROM o01 UNION ALL
  SELECT 2,  'O02 the Catalog is never graded on an unsettled window',      v FROM o02 UNION ALL
  SELECT 3,  'O03 one row per promise, not per nightly ask',                v FROM o03 UNION ALL
  SELECT 4,  'O04 the view invents no promise',                             v FROM o04 UNION ALL
  SELECT 5,  'O05 delivery_ratio arithmetic',                               v FROM o05 UNION ALL
  SELECT 6,  'O06 read-only, and read by nothing',                          v FROM o06 UNION ALL
  SELECT 7,  'O07 the delivery join actually finds clicks',                 v FROM o07 UNION ALL
  SELECT 8,  'O08 the budget forward-fill covers the spending days',        v FROM o08 UNION ALL
  SELECT 9,  'O09 unmeasured never reads as bad',                           v FROM o09 UNION ALL
  SELECT 10, 'O10 every row carries a sentence',                            v FROM o10
)
ORDER BY n;
