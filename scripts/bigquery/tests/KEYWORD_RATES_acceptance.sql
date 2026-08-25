-- =============================================================================================
-- V_KEYWORD_RATES acceptance — the shared conversion and margin rates. v27.81 (2026-08-25).
-- Every check returns a VIOLATION COUNT; PASS is 0.
-- THIS VIEW IS NOT YET WIRED TO ANYTHING THAT SPENDS. It is the validated definition; cutting the
-- engine over to it flips 32 of 357 bar verdicts and is a separate, approved change.
-- =============================================================================================
WITH r AS (SELECT * FROM `onyga-482313.OI.V_KEYWORD_RATES`),
wm AS (SELECT MAX(date) AS watermark FROM `onyga-482313.OI.FACT_AMAZON_ADS`),

-- R01 THE NESTING IS WHAT MAKES THE WEIGHTING. Weighted clicks must sit between 1x and 4x the
--     90-day count, because the windows nest 4/3/2/1. Outside that band the sum is not the
--     step-decay it claims to be and the recency weighting is silently something else.
--     MEASURED AGAINST clicks_90, NOT clicks_90_settled. The first version of this check used the
--     settled count and failed 12 keywords that were perfectly correct: the settled window ENDS
--     seven days ago, so a keyword that only started running recently has almost no settled clicks
--     and many weighted ones -- one showed 88 against 5, a ratio of 17.6. The bound only means
--     anything against a window ending at the same watermark.
r01 AS (SELECT COUNTIF(weighted_clicks < clicks_90 OR weighted_clicks > clicks_90 * 4) AS v
        FROM r WHERE clicks_90 > 0),

-- R02 RATES ARE ARITHMETIC ON THE PUBLISHED EVIDENCE, not a separate calculation that could drift.
r02 AS (SELECT COUNTIF(
          ABS(cvr - SAFE_DIVIDE(weighted_orders, NULLIF(weighted_clicks,0))) > 0.000002
          OR ABS(gp_per_click - SAFE_DIVIDE(weighted_gross_profit, NULLIF(weighted_clicks,0))) > 0.01
        ) AS v FROM r WHERE weighted_clicks > 0),

-- R03 gp_per_click IS cvr TIMES gp_per_order. If these three ever disagree the chain's ceiling,
--     which is gp_per_click / keyword_bar, stops matching the orders and margin it was built from.
r03 AS (SELECT COUNTIF(ABS(gp_per_click - cvr * gp_per_order) > 0.02) AS v
        FROM r WHERE weighted_orders > 0),

-- R04 NO WINDOW READS THE FUTURE.
r04 AS (SELECT COUNTIF(rates_through > (SELECT watermark FROM wm)) AS v FROM r),

-- R05 ONE ROW PER KEYWORD. A duplicate would double-count a keyword in any consumer that sums.
r05 AS (SELECT COUNTIF(n > 1) AS v FROM (
          SELECT campaign_id, keyword_id, COUNT(*) AS n FROM r GROUP BY 1,2)),

-- R06 THE OLD RATES ARE STILL PUBLISHED. The whole point of carrying cvr_90_settled is that a
--     consumer can see what changed; drop it and the cut-over becomes unauditable.
r06 AS (SELECT 3 - COUNTIF(column_name IN ('cvr_90_settled','gp_per_order_90_settled',
                                           'gp_per_click_90_settled')) AS v
        FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS` WHERE table_name = 'V_KEYWORD_RATES'),

-- R07 EVERY ROW DISCLOSES ITS EVIDENCE. A rate without its order count cannot be weighed.
r07 AS (SELECT COUNTIF(rates_basis IS NULL OR rates_basis = '') AS v FROM r),

-- R08 NO NEGATIVE CONVERSION RATE. A negative CVR is impossible and would invert every price
--     built on it. A negative GROSS PROFIT PER ORDER is NOT checked here, because it is a real
--     business state -- a keyword selling below landed cost -- and the chain must be able to say
--     so rather than be prevented from representing it. The first version of this check conflated
--     the two and flagged a genuine loss-making keyword as a data error.
r08 AS (SELECT COUNTIF(cvr < 0) AS v FROM r),

-- R09 IT DECIDES NOTHING. No bid, budget, action or state column may appear here.
r09 AS (SELECT COUNTIF(LOWER(column_name) IN ('new_bid','bid','budget','action','apply','pause','state')) AS v
        FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS` WHERE table_name = 'V_KEYWORD_RATES')

SELECT * FROM (
  SELECT 1 AS n, 'R01 weighted clicks sit within the 1x-4x nesting band' AS check_name, v FROM r01 UNION ALL
  SELECT 2, 'R02 rates are arithmetic on the published evidence', v FROM r02 UNION ALL
  SELECT 3, 'R03 gp_per_click equals cvr x gp_per_order',        v FROM r03 UNION ALL
  SELECT 4, 'R04 no window reads the future',                    v FROM r04 UNION ALL
  SELECT 5, 'R05 one row per keyword',                           v FROM r05 UNION ALL
  SELECT 6, 'R06 the old rates are still published',             v FROM r06 UNION ALL
  SELECT 7, 'R07 every row discloses its evidence',              v FROM r07 UNION ALL
  SELECT 8, 'R08 no negative conversion rate',                             v FROM r08 UNION ALL
  SELECT 9, 'R09 it decides nothing',                            v FROM r09
)
ORDER BY n;
