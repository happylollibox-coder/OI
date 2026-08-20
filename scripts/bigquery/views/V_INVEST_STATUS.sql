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
-- not share a window -- and both windows are published on the row (rate_window_start/_end,
-- mtd_money_start/_end) so no reader has to guess which days a column covers.
--
-- THE LOWER BOUND ANCHORS ON THE WATERMARK'S MONTH, NOT TODAY'S. On 1-3 September, CURRENT_DATE's
-- month has already turned over while the ads watermark is still in August; anchoring on today would
-- return a near-empty window and read the whole month's spend as a rounding error.
--
-- THE DENOMINATOR IS ELAPSED DAYS, NOT DAYS THAT HAVE ROWS. COUNT(DISTINCT date) counts only days
-- with activity, so a genuine zero-spend day vanished from the divisor and inflated the rate.
--
-- WHY THE LOSS CEILING IS PUBLISHED BUT NOT ENFORCING: measured 2026-08-20 both families ran 1.6x
-- and 1.9x over their sanctioned SPEND while their month-to-date LOSS was $204 and $15 against
-- ceilings of $913 and $1,674. A loss ceiling on a product that nearly covers its costs never fires.
-- Enforcing on it would have been enforcement in name only; the spend rate is what binds.
-- ---------------------------------------------------------------------------------------------
ads_wm AS (
  -- The last COMPLETE ads day. Day-1 ads are 88-90% loaded (fact_oi_fresh_ads_data_reading_rules),
  -- so the newest loaded day never enters a rate.
  SELECT DATE_SUB(MAX(date), INTERVAL 1 DAY) AS d FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),
rate_win AS (
  SELECT
    DATE_TRUNC((SELECT d FROM ads_wm), MONTH)                                            AS win_start,
    (SELECT d FROM ads_wm)                                                               AS win_end,
    DATE_DIFF((SELECT d FROM ads_wm), DATE_TRUNC((SELECT d FROM ads_wm), MONTH), DAY) + 1 AS win_days
),
spend AS (
  SELECT u.family,
    ROUND(SUM(u.ad_cost), 2)                                                             AS mtd_spend,
    ROUND(SAFE_DIVIDE(SUM(u.ad_cost), (SELECT win_days FROM rate_win)), 2)               AS mtd_spend_per_day
  FROM `onyga-482313.OI.V_UNIFIED_DAILY` u
  WHERE u.date BETWEEN (SELECT win_start FROM rate_win) AND (SELECT win_end FROM rate_win)
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
  sp.mtd_spend,
  sp.mtd_spend_per_day,
  ROUND(SAFE_DIVIDE(sp.mtd_spend_per_day, NULLIF(b.daily_investment, 0)), 2)           AS spend_rate_ratio,
  -- TRUE means measured over. FALSE means measured under. NULL means NOT MEASURED -- which is not a
  -- pass, and exemption_live below refuses to treat it as one.
  (sp.mtd_spend_per_day > b.daily_investment)                                          AS spend_breached,
  -- WHICH DAYS THE RATE COVERS. Published so a reader can see the window rather than assume it.
  (SELECT win_start FROM rate_win)                                                     AS rate_window_start,
  (SELECT win_end   FROM rate_win)                                                     AS rate_window_end,
  (SELECT win_days  FROM rate_win)                                                     AS rate_window_days,
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
  -- THE EXEMPTION, AND WHAT IT IS NOT (2026-08-20).
  -- This column is a STATEMENT, not yet a control. It says whether a launch is inside its window and
  -- inside the rate Ori sanctioned. NOTHING READS IT TO STOP ANYTHING: V_LAUNCH_EXEMPTION still
  -- hardcodes TRUE AS exempt_active, so every launch keeps its protection whatever this says. Wiring
  -- this to the engine is Task 8b, and Task 8b is not built. Until it is, the only thing standing
  -- between an over-sanction launch and the money is a person reading this row.
  --
  -- IT FAILS CLOSED. Protection is granted only on POSITIVE evidence of adherence: a sanctioned rate
  -- on file, a measured spend at or under it, a ceiling on file, and a measured loss under it. Any
  -- one of those missing and the answer is FALSE -- no protection -- rather than the old behaviour,
  -- where a missing spend was read as zero spend and the exemption stayed live. A sanction gate that
  -- cannot see the spend must not certify it: silence is not compliance.
  -- ---------------------------------------------------------------------------------------------
  -- The outer COALESCE closes the last hole: a family with no stop date on file would otherwise
  -- leave the whole chain NULL, and NULL is not FALSE to a consumer that only tests for FALSE.
  COALESCE(
    CURRENT_DATE('America/Los_Angeles') <= b.stop_date
    AND b.stop_date            IS NOT NULL
    AND b.daily_investment     IS NOT NULL AND sp.mtd_spend_per_day IS NOT NULL
    AND b.monthly_loss_ceiling IS NOT NULL AND mo.mtd_net_profit    IS NOT NULL
    AND sp.mtd_spend_per_day  <= b.daily_investment
    AND -mo.mtd_net_profit     < b.monthly_loss_ceiling, FALSE)                        AS exemption_live,
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
LEFT JOIN trend t  ON t.family  = b.family
LEFT JOIN spend sp ON sp.family = b.family
LEFT JOIN money mo ON mo.family = b.family;
