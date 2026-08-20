-- =============================================
-- V_INVEST_STATUS — the Invest book: budget consumed, trajectory, exemption state (2026-08-19).
-- Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md §5.
--
-- THE QUESTION CHANGES WITH AGE (Ori 2026-08-19: "the question of launch products is are they
-- improving — not are they profitable — in the first 3 months").
--
--   RAMP  (months 0-3): judged on TRAJECTORY ONLY. Nothing is required to be positive; everything is
--                       required to be IMPROVING — organic units rising, total net ROAS rising, loss
--                       shrinking. The decision rule is "no improvement across two consecutive
--                       months", NEVER "still unprofitable". A profitable-at-month-2 test would kill
--                       every launch that was working.
--   PROOF (months 3+):  level starts to matter — closing on the declared take-over target by the
--                       end date, with the ceiling and clock enforcing themselves.
--
-- WHY ABSOLUTE ORGANIC UNITS, NOT SHARE: share is a trap — it rises when ads units collapse, which
-- looks like success and is not. Bunny and LolliBall already sit at ~31% organic, comparable to
-- Lollibox's 29.7%, so by share alone they would read "finished" while still losing $2,892/month.
--
-- A USEFUL CONSEQUENCE: trajectory is robust to a level bias. A constant COGS misallocation cancels
-- out of a month-over-month trend, which is why LolliBall's implausible 0.87 halo (spec §9.1) does
-- not block the ramp test — though it must be fixed before LolliBall reaches PROOF.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_INVEST_STATUS` AS
WITH b AS (
  SELECT * FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` WHERE book = 'INVEST'
),
-- the three most recent COMPLETE calendar months, per family, from the measurement spine
m AS (
  SELECT family, period_label, period_start, net_profit, total_net_roas, organic_units
  FROM `onyga-482313.OI.V_FAMILY_PNL`
  WHERE REGEXP_CONTAINS(period_label, r'^\d{4}-\d{2}$')
    AND period_end < DATE_TRUNC(CURRENT_DATE('America/Los_Angeles'), MONTH)
),
ranked AS (
  SELECT m.*, ROW_NUMBER() OVER (PARTITION BY family ORDER BY period_start DESC) AS rn
  FROM m JOIN b USING (family)
),
trend AS (
  SELECT family,
    MAX(IF(rn=1, organic_units, NULL))  AS org_m0, MAX(IF(rn=2, organic_units, NULL))  AS org_m1, MAX(IF(rn=3, organic_units, NULL))  AS org_m2,
    MAX(IF(rn=1, total_net_roas, NULL)) AS tnr_m0, MAX(IF(rn=2, total_net_roas, NULL)) AS tnr_m1, MAX(IF(rn=3, total_net_roas, NULL)) AS tnr_m2,
    MAX(IF(rn=1, net_profit, NULL))     AS np_m0,  MAX(IF(rn=2, net_profit, NULL))     AS np_m1,  MAX(IF(rn=3, net_profit, NULL))     AS np_m2
  FROM ranked WHERE rn <= 3 GROUP BY family
),
-- ---------------------------------------------------------------------------------------------
-- TWO MEASURES, TWO WINDOWS, ONE OWNER EACH (defect fix 2026-08-20).
--
-- The previous cut computed BOTH the month-to-date money and the month-to-date spend rate here,
-- off one CTE bounded only from below (date >= start of CURRENT_DATE's month). That produced a
-- SECOND month-to-date net profit for the same family and the same month, differing from the one
-- V_FAMILY_PNL already published: LolliBall read -$53.22 here against a settled -$15.28, Bunny
-- -$257.57 against -$203.78. Worse, it subtracted ad spend loaded through the newest ads day from
-- sales complete only to the orders watermark two days earlier -- a blended figure assembled from
-- two different windows, which the house window convention forbids outright.
--
--   MONEY  -> V_FAMILY_PNL is now the SOLE owner. Its 'MTD' row is bounded at the ORDERS watermark,
--             which is complete by construction (the sessions gate drops mid-sync partial days), so
--             sales, COGS and ad spend inside it all end on the same complete day. Nothing about the
--             month-to-date money is recomputed in this file. One concept, one number, one place.
--
--   RATE   -> stays here, because it is a different measure with a different job: a spend rate has
--             to be CURRENT to bind on anything, so it may not wait for the orders watermark. It is
--             ads-only, so it takes the ADS watermark and ends at wm - 1: FACT_AMAZON_ADS is only
--             88-90% loaded at age 1 and restates for about three days, and a half-loaded day
--             divided as a whole day drags the rate DOWN, which is the direction that quietly grants
--             a launch the protection it has not earned.
--
-- This is not a second watermark for one number. It is one watermark each for two numbers that must
-- not share a window -- and both windows are published on the row (rate_window_start/_end/_days and
-- _basis, mtd_money_start/_end) so no reader has to guess which days a column covers.
--
-- THE DENOMINATOR IS ELAPSED DAYS, NOT DAYS THAT HAVE ROWS. COUNT(DISTINCT date) counts only days
-- with activity, so a genuine zero-spend day vanished from the divisor and inflated the rate.
--
-- WHY THE LOSS CEILING IS PUBLISHED BUT NOT ENFORCING: measured 2026-08-20 both families ran 1.6x
-- and 1.9x over their sanctioned SPEND while their month-to-date LOSS was $204 and $15 against
-- ceilings of $913 and $1,674. A loss ceiling on a product that nearly covers its costs never fires.
-- Enforcing on it would have been enforcement in name only; the spend rate is what binds.
--
-- ---------------------------------------------------------------------------------------------
-- A RATE NEEDS ENOUGH DAYS TO BE A RATE (defect fix 2026-08-20, second round).
--
-- Ori: "when you do not have full window data, do not show calculate." The round-1 cut bounded the
-- window at the ads watermark and anchored its lower edge on the WATERMARK's month rather than
-- today's, which fixed 1 and 2 September. It NARROWED the month-start cliff; it did not close it,
-- and on one day a month it was measurably worse than the code it replaced. Walking the calendar
-- under the observed lag (FACT_AMAZON_ADS MAX(date) = today - 1, so the last complete ads day is
-- today - 2):
--
--     1st  -> the whole of the previous month.        31 days.  safe
--     2nd  -> the whole of the previous month.        31 days.  safe
--     3rd  -> the 1st, alone.                          1 day.   the old code held 2
--     4th  -> the 1st to the 2nd.                      2 days.
--      ...
--     12th -> the 1st to the 10th.                    10 days.
--
-- A one-day sample is not a rate. Daily spend is nothing like smooth: over the 90 days to 19 August
-- 2026 Bunny ran from $0.00 to $127.82 a day around a mean of $54.75, and LolliBall from $0.00 to
-- $156.91 around $55.69. One quiet day on a family running half again over its sanction reads as
-- compliant, and the gate certifies it.
--
-- THE MINIMUM IS MEASURED, NOT ROUND. A rate over n days is the mean of n daily spends, so its
-- standard error is sigma / sqrt(n). For the gate to SEE a family running 1.6x its sanctioned rate,
-- the margin it has to clear -- 0.6 x the sanctioned rate -- must be at least two standard errors
-- wide, which puts the chance of a false pass near 1 in 40. That is n >= (2 x sigma / (0.6 x S))^2:
--
--     Bunny      sigma $28.91, S $30 -> margin $18 -> n >= (57.82 / 18)^2  = 10.32 -> 11 days
--     LolliBall  sigma $51.55, S $55 -> margin $33 -> n >= (103.10 / 33)^2 =  9.76 -> 10 days
--
-- sigma is the sample standard deviation of DAILY family spend over the 90 days to 19 August 2026,
-- zero-filled so a day with no rows counts as $0 rather than dropping out. The binding family sets
-- the rule: MINIMUM_RATE_WINDOW_DAYS = 11.
--
-- Checked against the data as well as against the normal curve. Rescale each family's last 31 days
-- (a single steady regime, no launch ramp inside it) so its TRUE rate is exactly 1.6x its sanction,
-- then read every rolling window: Bunny's longest falsely-compliant window is 7 days (4.0% of 7-day
-- windows, and none at 8 or more); LolliBall has none at any length. 11 days clears both.
--
-- AND THE RESIDUAL IS STATED, NOT HIDDEN. Run the same rescale across 1 July to 18 August 2026 --
-- a span containing a real level shift, Bunny near $85 a day in July and near $45 in August -- and
-- one 11-day window in 39 still reads compliant, at $29.64 against a $30 sanction. That is the rule
-- meeting its own specification rather than missing it: two standard errors was chosen as about one
-- false pass in forty, and one in thirty-nine is what forty looks like when you count it. A shorter
-- window is worse by exactly the arithmetic above -- at one day it is six in forty-nine, at three
-- days five in forty-seven. Raising the floor further would only widen the stretch of the month that
-- reads last month's rate; it would not make a short window measurable.
--
-- WHERE THE 11-DAY FLOOR ACTUALLY BINDS: on ONE day of the month, the 13th, where the running month
-- has exactly 11 loaded days. Days 3 to 12 fall back to a whole calendar month, 28 days or more,
-- where the arithmetic above has an enormous margin; from the 14th on, the window only gets longer.
--
-- BELOW THE MINIMUM THE RUNNING MONTH PRODUCES NO RATE AT ALL. It falls back to the LAST COMPLETE
-- CALENDAR MONTH -- 28 days or more, and fully loaded, because its final day is older than the ads
-- watermark by at least a day. THE ROW SAYS WHICH IT IS LOOKING AT: rate_window_basis names the span
-- in words and, on the fallback, names it as the last complete month and says why; and
-- rate_window_is_last_complete_month carries the same fact as a boolean for anything that has to
-- branch on it. The gate can no longer certify compliance off a sample too small to judge, and no
-- reader is left to assume the window is the month they happen to be standing in.
--
-- ---------------------------------------------------------------------------------------------
-- THE WINDOW ENDS ON THE SOURCE THAT IS ACTUALLY SUMMED (defect fix 2026-08-20, second round).
--
-- The numerator sums ad_cost from V_UNIFIED_DAILY; the window used to end on FACT_AMAZON_ADS. They
-- agree today, and have agreed on all 710 loaded ads days, but they are not the same set:
-- V_UNIFIED_DAILY's ads leg keeps only rows whose advertised ASIN resolves through
-- COALESCE(most_advertised_asin_impressions, advertised_asins, ASIN_BY_CAMPAIGN_NAME), so a day can
-- land in FACT and reach nothing here. The window would then end on a day the numerator cannot see
-- while the denominator still counted it -- diluting the rate DOWN, the same direction as every
-- other defect on this measure. The end is now the newest day whose spend can actually REACH
-- V_UNIFIED_DAILY, computed with that view's own attribution test.
--
-- AND IT IS CAPPED THE WAY ITS SIBLINGS ARE. V_KEYWORD_CONTEXT_LEDGER:27, V_KEYWORD_CONTEXT_GATE:78
-- and V_SEASON_CONTEXT:37 all read LEAST(MAX(date), FN_ADS_ANCHOR_CAP()); this view read MAX(date)
-- bare. There are no future-dated ads rows today, and a single one would push the window END past
-- the days that exist -- lengthening the denominator over days with no spend in them, which dilutes
-- the rate down yet again. Same guard, same reason, same house pattern.
-- ---------------------------------------------------------------------------------------------
ads_src AS (
  -- ONE pass over FACT_AMAZON_ADS answering the only question the rate needs: what is the newest day
  -- whose ad spend can reach the numerator this view sums? Capped at FN_ADS_ANCHOR_CAP() so a
  -- future-dated row can never move it forward.
  SELECT LEAST(
           MAX(IF(Ads_cost > 0
                  AND COALESCE(most_advertised_asin_impressions, advertised_asins,
                               ASIN_BY_CAMPAIGN_NAME) IS NOT NULL,
                  date, NULL)),
           `onyga-482313.OI.FN_ADS_ANCHOR_CAP`())                                    AS reachable_end
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),
rate_edge AS (
  -- The last COMPLETE day. Day-1 ads are 88-90% loaded (fact_oi_fresh_ads_data_reading_rules), so
  -- the newest loaded day never enters a rate.
  SELECT DATE_SUB(reachable_end, INTERVAL 1 DAY) AS d FROM ads_src
),
rate_cand AS (
  SELECT
    11                                                                  AS min_days,
    DATE_TRUNC(d, MONTH)                                                AS mtd_start,
    d                                                                   AS mtd_end,
    DATE_DIFF(d, DATE_TRUNC(d, MONTH), DAY) + 1                         AS mtd_days,
    DATE_TRUNC(DATE_SUB(DATE_TRUNC(d, MONTH), INTERVAL 1 DAY), MONTH)   AS prev_start,
    DATE_SUB(DATE_TRUNC(d, MONTH), INTERVAL 1 DAY)                      AS prev_end
  FROM rate_edge
),
rate_win AS (
  SELECT
    min_days                                                            AS win_min_days,
    is_fallback,
    win_start,
    win_end,
    DATE_DIFF(win_end, win_start, DAY) + 1                              AS win_days,
    -- THE SPAN IN WORDS, for the column a person reads. It names real dates every day of the year,
    -- so it cannot drift out of agreement with the numbers beside it the way a hand-built
    -- "month to date, from <the 1st of today's month>" string does the moment the two months differ.
    CONCAT(
      IF(DATE_TRUNC(win_start, MONTH) = DATE_TRUNC(win_end, MONTH),
         FORMAT_DATE('%-d', win_start), FORMAT_DATE('%-d %B', win_start)),
      ' to ', FORMAT_DATE('%-d %B %Y', win_end), ', ',
      CAST(DATE_DIFF(win_end, win_start, DAY) + 1 AS STRING), ' days',
      IF(is_fallback,
         CONCAT(' — the last complete month, because this month does not yet have enough ',
                'measured days to give a rate.'),
         ''))                                                           AS win_basis,
    -- The same window compressed to a clause that drops into the middle of a sentence: "spending
    -- $48.35 a day over the 18 days to 18 August 2026". True on every day of the month, including
    -- the ones where the window is not the month the reader is standing in.
    CONCAT('over the ', CAST(DATE_DIFF(win_end, win_start, DAY) + 1 AS STRING),
           ' days to ', FORMAT_DATE('%-d %B %Y', win_end))              AS win_phrase
  FROM (
    SELECT
      min_days,
      mtd_days < min_days                                               AS is_fallback,
      IF(mtd_days < min_days, prev_start, mtd_start)                    AS win_start,
      IF(mtd_days < min_days, prev_end,   mtd_end)                      AS win_end
    FROM rate_cand
  )
),
spend AS (
  -- rate_win is one row, so the CROSS JOIN is a constant, not a fan-out. It is joined rather than
  -- read through scalar subqueries so the window is derived ONCE per reference instead of once per
  -- column that quotes it.
  SELECT u.family,
    ROUND(SUM(u.ad_cost), 2)                                            AS rate_window_spend,
    ROUND(SAFE_DIVIDE(SUM(u.ad_cost), MAX(w.win_days)), 2)              AS spend_per_day
  FROM `onyga-482313.OI.V_UNIFIED_DAILY` u
  CROSS JOIN rate_win w
  WHERE u.date BETWEEN w.win_start AND w.win_end
  GROUP BY 1
),
-- THE MONEY, READ NOT RECOMPUTED. One row per family for the running month, bounded at the orders
-- watermark by the view that owns it.
money AS (
  SELECT family, net_profit AS mtd_net_profit, period_start AS mtd_money_start, period_end AS mtd_money_end
  FROM `onyga-482313.OI.V_FAMILY_PNL`
  WHERE period_label = 'MTD'
)
SELECT
  b.family,
  b.launch_age_months,
  IF(b.launch_age_months <= 3, 'RAMP', 'PROOF')                                       AS phase,
  -- THE BINDING SANCTION.
  -- NULL, NEVER ZERO, WHEN THE SPEND IS UNKNOWN (defect fix 2026-08-20). COALESCE(rate, 0) made
  -- "we have no data for this family" read as "it spent nothing", which is the single most
  -- flattering reading available and the one that hands out launch protection for free.
  b.daily_investment,
  -- NOT mtd_spend / mtd_spend_per_day any more. On the days when the running month is too short to
  -- rate, the window is the last COMPLETE month and "month to date" is simply not what these two
  -- cover. A name that is only right most of the month is the defect class this round exists to
  -- close, so the names now say what they are: the spend inside the published rate window, and that
  -- spend per day of it.
  sp.rate_window_spend,
  sp.spend_per_day,
  ROUND(SAFE_DIVIDE(sp.spend_per_day, NULLIF(b.daily_investment, 0)), 2)               AS spend_rate_ratio,
  -- TRUE means measured over. FALSE means measured under. NULL means NOT MEASURED -- which is not a
  -- pass, and protection_qualified below refuses to treat it as one.
  (sp.spend_per_day > b.daily_investment)                                              AS spend_breached,
  -- WHICH DAYS THE RATE COVERS, as dates, as a count, in words, and as the one boolean a consumer
  -- might have to branch on. Published so a reader can SEE the window rather than assume it is the
  -- month they are standing in.
  w.win_start                                                                          AS rate_window_start,
  w.win_end                                                                            AS rate_window_end,
  w.win_days                                                                           AS rate_window_days,
  w.win_basis                                                                          AS rate_window_basis,
  w.win_phrase                                                                         AS rate_window_phrase,
  w.is_fallback                                                                        AS rate_window_is_last_complete_month,
  w.win_min_days                                                                       AS rate_window_minimum_days,
  -- the catastrophe backstop, published but NOT enforcing. Money and its window both come straight
  -- from V_FAMILY_PNL; nothing here recomputes either.
  b.monthly_loss_ceiling,
  mo.mtd_net_profit,
  mo.mtd_money_start,
  mo.mtd_money_end,
  ROUND(100 * SAFE_DIVIDE(-mo.mtd_net_profit, NULLIF(b.monthly_loss_ceiling, 0)), 1)   AS ceiling_used_pct,
  (-mo.mtd_net_profit >= b.monthly_loss_ceiling)                                       AS ceiling_breached,
  b.stop_date,
  DATE_DIFF(b.stop_date, CURRENT_DATE('America/Los_Angeles'), DAY)                     AS days_left,
  -- ---------------------------------------------------------------------------------------------
  -- WHETHER THE LAUNCH QUALIFIES FOR PROTECTION, AND WHAT THAT IS NOT (2026-08-20).
  -- IT WAS CALLED exemption_live UNTIL THE SECOND ROUND, AND THE NAME WAS THE PROBLEM. "Live" reads
  -- as "in force", which is the one thing it does not mean: this column says whether a launch has
  -- EARNED protection under the rules Ori set, never whether any machine is applying it. The brief
  -- downstream had already renamed its own copy to protection_qualified for exactly that reason,
  -- which left the ambiguous name alive one join upstream, where a new consumer would meet it first.
  -- Both names are now the same name.
  --
  -- This column is a STATEMENT, not yet a control. It says whether a launch is inside its window and
  -- inside the rate Ori sanctioned. NOTHING READS IT TO STOP ANYTHING: V_LAUNCH_EXEMPTION still
  -- hardcodes TRUE AS exempt_active, so every launch keeps its protection whatever this says. Wiring
  -- this to the engine is Task 8b, and Task 8b is not built. Until it is, the only thing standing
  -- between an over-sanction launch and the money is a person reading this row.
  --
  -- IT FAILS CLOSED. Protection is granted only on POSITIVE evidence of adherence: a sanctioned rate
  -- on file, a measured spend at or under it, a ceiling on file, and a measured loss under it. Any
  -- one of those missing and the answer is FALSE -- no protection -- rather than the old behaviour,
  -- where a missing spend was read as zero spend and the launch kept its protection. A sanction gate that
  -- cannot see the spend must not certify it: silence is not compliance.
  -- ---------------------------------------------------------------------------------------------
  -- The outer COALESCE closes the last hole: a family with no stop date on file would otherwise
  -- leave the whole chain NULL, and NULL is not FALSE to a consumer that only tests for FALSE.
  COALESCE(
    CURRENT_DATE('America/Los_Angeles') <= b.stop_date
    AND b.stop_date            IS NOT NULL
    AND b.daily_investment     IS NOT NULL AND sp.spend_per_day  IS NOT NULL
    AND b.monthly_loss_ceiling IS NOT NULL AND mo.mtd_net_profit IS NOT NULL
    AND sp.spend_per_day      <= b.daily_investment
    AND -mo.mtd_net_profit     < b.monthly_loss_ceiling, FALSE)                        AS protection_qualified,
  t.org_m2, t.org_m1, t.org_m0,
  t.tnr_m2, t.tnr_m1, t.tnr_m0,
  t.np_m2,  t.np_m1,  t.np_m0,
  -- the three RAMP trends; NULL-safe so a young family with two months of data still reports
  (t.org_m0 > t.org_m1)                                                               AS organic_units_rising,
  (t.tnr_m0 > t.tnr_m1)                                                               AS net_roas_rising,
  (t.np_m0  > t.np_m1)                                                                AS loss_shrinking,
  b.takeover_target_organic_units,
  CASE
    WHEN b.launch_age_months <= 3 THEN
      CASE
        WHEN t.org_m1 IS NULL THEN 'too early to judge — needs two complete months'
        WHEN t.org_m0 > t.org_m1 AND t.np_m0 > t.np_m1
          THEN CONCAT('improving — organic units ', CAST(t.org_m1 AS STRING), ' to ', CAST(t.org_m0 AS STRING), ', loss shrinking')
        WHEN t.org_m2 IS NOT NULL AND t.org_m0 <= t.org_m1 AND t.org_m1 <= t.org_m2
          THEN 'no improvement two months running — the investment is not working'
        ELSE CONCAT('mixed — organic units ', CAST(t.org_m1 AS STRING), ' to ', CAST(t.org_m0 AS STRING), ', watch next month')
      END
    ELSE
      CASE
        WHEN b.takeover_target_organic_units IS NULL
          THEN CONCAT('take-over target not set — ', CAST(t.org_m0 AS STRING),
                      ' organic units last complete month, but nothing to judge it against')
        WHEN t.org_m0 >= b.takeover_target_organic_units
          THEN CONCAT('took over — ', CAST(t.org_m0 AS STRING), ' organic units against a target of ', CAST(b.takeover_target_organic_units AS STRING))
        ELSE CONCAT('short of target — ', CAST(t.org_m0 AS STRING), ' of ', CAST(b.takeover_target_organic_units AS STRING), ' organic units, ',
                    CAST(DATE_DIFF(b.stop_date, CURRENT_DATE('America/Los_Angeles'), DAY) AS STRING), ' days left')
      END
  END                                                                                 AS verdict
FROM b
CROSS JOIN rate_win w
LEFT JOIN trend t  ON t.family  = b.family
LEFT JOIN spend sp ON sp.family = b.family
LEFT JOIN money mo ON mo.family = b.family;
