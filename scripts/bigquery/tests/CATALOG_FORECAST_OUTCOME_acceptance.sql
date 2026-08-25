-- =============================================================================================
-- FACT_CATALOG_FORECAST / V_CATALOG_FORECAST_OUTCOME / V_CATALOG_SCORECARD acceptance.
-- v27.78 (2026-08-25). Forecast chain step 3. Every check returns a VIOLATION COUNT; PASS is 0.
--
-- READ THIS BEFORE TRUSTING A GREEN RUN. The first claim window closes 2026-09-01 and settles a
-- week later, so TODAY EVERY ROW IS PENDING and the grading arms are UNEXERCISED BY LIVE DATA.
-- O01 and O02 pass because the view correctly refuses to answer, and ABSTENTION IS NOT ACCURACY.
-- O07, O08 and O09 therefore exercise the actuals join, the coverage denominator and the
-- contribution arithmetic over a span that has ALREADY HAPPENED, so the machinery underneath the
-- grades is demonstrated now rather than assumed until September.
-- =============================================================================================
WITH k AS (SELECT DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 30 DAY) AS past_start,
                  DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 24 DAY) AS past_end),
o  AS (SELECT * FROM `onyga-482313.OI.V_CATALOG_FORECAST_OUTCOME`),
sc AS (SELECT * FROM `onyga-482313.OI.V_CATALOG_SCORECARD`),
led AS (SELECT * FROM `onyga-482313.OI.FACT_CATALOG_FORECAST`),
wm AS (SELECT MAX(date) AS watermark FROM `onyga-482313.OI.FACT_AMAZON_ADS`),

-- O01 NO SCORE BEFORE THE WINDOW CLOSES. A grader that answers early marks the Catalog down for
--     clicks that still have days to arrive.
o01 AS (SELECT COUNTIF(window_end > (SELECT watermark FROM wm) AND status <> 'PENDING') AS v FROM o),

-- O02 NO SCORE BEFORE IT SETTLES. SP accrues 7 days, SB 14. Judging early counts sales that have
--     not landed as sales that never will.
o02 AS (SELECT COUNTIF(settles_on > (SELECT watermark FROM wm) AND status = 'SCORED') AS v FROM o),

-- O03 ONE ROW PER CLAIM. A duplicated claim would be double-counted by the family roll-up, which
--     sums predicted money.
o03 AS (SELECT COUNTIF(n > 1) AS v FROM (
          SELECT forecast_on, campaign_id, keyword_id, COUNT(*) AS n FROM o GROUP BY 1,2,3)),

-- O04 THE LEDGER CARRIES ONE STAMP PER DAY. Append-then-prune must leave exactly one captured_at
--     per forecast_on; two stamps means a crash left a duplicate strand that never got repaired.
o04 AS (SELECT COUNTIF(stamps > 1) AS v FROM (
          SELECT forecast_on, COUNT(DISTINCT captured_at) AS stamps FROM led GROUP BY 1)),

-- O05 THE VIEW INVENTS NO CLAIM. Every scored row must trace to a row the Catalog actually wrote.
o05 AS (SELECT COUNT(*) AS v FROM o
        WHERE NOT EXISTS (SELECT 1 FROM led l WHERE l.forecast_on = o.forecast_on
                          AND l.campaign_id = o.campaign_id AND l.keyword_id = o.keyword_id)),

-- O06 NET PROFIT IS NEVER PUBLISHED AS A PERCENTAGE. Measured (spec 3.3): 15% on net profit needs
--     gross profit to 1.3-2.8%, so a net-profit percentage is a ratio of a rounding error. If a
--     future edit adds one, this fails and the reasoning above must be re-argued, not bypassed.
o06 AS (SELECT COUNTIF(LOWER(column_name) LIKE '%contribution%error%'
                       AND LOWER(column_name) NOT LIKE '%dollars%') AS v
        FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
        WHERE table_name IN ('V_CATALOG_FORECAST_OUTCOME','V_CATALOG_SCORECARD')),

-- O07 THE ACTUALS JOIN ACTUALLY FINDS CLICKS. Exercised on a span that has already happened, using
--     the SAME join shape the view uses -- campaign_id plus lowercased targeting. If the join were
--     broken every claim would score as a total miss and the Catalog would look far worse than it
--     is, which is a failure that hides as a result.
o07 AS (
  SELECT IF(SUM(a.Ads_clicks) > 0, 0, 1) AS v
  FROM `onyga-482313.OI.FACT_CATALOG_FORECAST` c, k
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` a
    ON CAST(a.campaign_id AS STRING) = c.campaign_id
   AND LOWER(TRIM(a.targeting)) = LOWER(TRIM(c.target_text))
   AND a.date BETWEEN k.past_start AND k.past_end),

-- O08 THE COVERAGE DENOMINATOR IS BIGGER THAN THE NUMERATOR. Claimed spend is a subset of family
--     spend by construction; if coverage could exceed 1 the join is fanning out and every summed
--     money column in the scorecard is inflated.
o08 AS (SELECT COUNTIF(claim_coverage > 1.0001) AS v FROM sc WHERE claim_coverage IS NOT NULL),

-- O09 THE ACTUAL CONTRIBUTION USES THE CLAIM'S OWN CREDITING RULE. Scoring a half-credit claim
--     against a full-credit actual would measure a change of accounting, not a forecast error.
--     Exercised arithmetically on a past span so it is proven before any row scores.
o09 AS (
  SELECT COUNTIF(ABS((gp / NULLIF(bar,0) - cost) - expected) > 0.01) AS v
  FROM (SELECT 100.0 AS gp, 0.8069 AS bar, 40.0 AS cost,
               100.0/0.8069 - 40.0 AS expected)),

-- O10 A FAMILY IS GRADED ONLY WHEN ALL ITS CLAIMS HAVE SETTLED. Otherwise a family passes on a
--     window that is only partly in, and the slow SB half is never counted.
o10 AS (SELECT COUNTIF(grade NOT IN ('PENDING')
                       AND (subjects_pending > 0 OR subjects_pending_settle > 0)) AS v FROM sc),

-- O11 EVERY LINK IS STORED SEPARATELY. The chain exists so a wrong total names its own fault; a
--     ledger that kept only the contribution could say the money was wrong and nothing more.
o11 AS (SELECT 6 - COUNTIF(column_name IN ('predicted_clicks','predicted_orders','predicted_cost',
                                           'predicted_gross_profit','predicted_ads_net_roas',
                                           'predicted_contribution')) AS v
        FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
        WHERE table_name = 'FACT_CATALOG_FORECAST'),

-- O12 A CLAIM NEVER LOSES ITS BASIS. A stored forecast whose provenance was dropped cannot be
--     weighed later, and weighing it later is the entire purpose of storing it.
o12 AS (SELECT COUNTIF(rate_basis IS NULL OR clicks_basis IS NULL OR elasticity_basis IS NULL) AS v
        FROM led),

-- O13 NOTHING HERE DECIDES ANYTHING. No bid, budget or pause column may appear.
o13 AS (SELECT COUNTIF(LOWER(column_name) IN ('new_bid','bid','budget','action','apply','pause')) AS v
        FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
        WHERE table_name IN ('FACT_CATALOG_FORECAST','V_CATALOG_FORECAST_OUTCOME','V_CATALOG_SCORECARD'))

SELECT * FROM (
  SELECT 1  AS n, 'O01 no score before the window closes' AS check_name, v FROM o01 UNION ALL
  SELECT 2,  'O02 no score before it settles',                  v FROM o02 UNION ALL
  SELECT 3,  'O03 one row per claim',                           v FROM o03 UNION ALL
  SELECT 4,  'O04 the ledger carries one stamp per day',        v FROM o04 UNION ALL
  SELECT 5,  'O05 the view invents no claim',                   v FROM o05 UNION ALL
  SELECT 6,  'O06 net profit is never a percentage',            v FROM o06 UNION ALL
  SELECT 7,  'O07 the actuals join actually finds clicks',      v FROM o07 UNION ALL
  SELECT 8,  'O08 coverage never exceeds one',                  v FROM o08 UNION ALL
  SELECT 9,  'O09 actual contribution uses the claim rule',     v FROM o09 UNION ALL
  SELECT 10, 'O10 a family is graded only when fully settled',  v FROM o10 UNION ALL
  SELECT 11, 'O11 every link is stored separately',             v FROM o11 UNION ALL
  SELECT 12, 'O12 a claim never loses its basis',               v FROM o12 UNION ALL
  SELECT 13, 'O13 nothing here decides anything',               v FROM o13
)
ORDER BY n;
