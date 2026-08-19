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
-- MONTH-TO-DATE SPEND RATE — the binding constraint (Ori 2026-08-19: "spend rate binds").
-- daily_investment is the number Ori actually sanctioned ($30/day Bunny, $55/day LolliBall). The
-- net-profit ceiling is computed too, but only as a catastrophe backstop: measured 2026-08-19 both
-- families ran 1.5-1.8x over sanctioned SPEND while their month-to-date LOSS was just $259 and $74
-- against ceilings of $913 and $1,674 — a loss ceiling on a product that nearly covers its costs
-- never fires. Enforcing on it would have been enforcement in name only.
mtd AS (
  SELECT u.family,
    ROUND(SUM(u.sales - u.cogs) - SUM(u.ad_cost), 2)                       AS mtd_net_profit,
    ROUND(SUM(u.ad_cost), 2)                                               AS mtd_spend,
    COUNT(DISTINCT u.date)                                                 AS mtd_days,
    ROUND(SAFE_DIVIDE(SUM(u.ad_cost), NULLIF(COUNT(DISTINCT u.date), 0)), 2) AS mtd_spend_per_day
  FROM `onyga-482313.OI.V_UNIFIED_DAILY` u
  WHERE u.date >= DATE_TRUNC(CURRENT_DATE('America/Los_Angeles'), MONTH)
  GROUP BY 1
)
SELECT
  b.family,
  b.launch_age_months,
  IF(b.launch_age_months <= 3, 'RAMP', 'PROOF')                                       AS phase,
  -- THE BINDING SANCTION
  b.daily_investment,
  COALESCE(mtd.mtd_spend_per_day, 0)                                                  AS mtd_spend_per_day,
  ROUND(SAFE_DIVIDE(COALESCE(mtd.mtd_spend_per_day, 0), NULLIF(b.daily_investment, 0)), 2) AS spend_rate_ratio,
  (COALESCE(mtd.mtd_spend_per_day, 0) > b.daily_investment)                           AS spend_breached,
  -- the catastrophe backstop, published but NOT enforcing
  b.monthly_loss_ceiling,
  COALESCE(mtd.mtd_net_profit, 0)                                                     AS mtd_net_profit,
  ROUND(100 * SAFE_DIVIDE(-COALESCE(mtd.mtd_net_profit, 0), NULLIF(b.monthly_loss_ceiling, 0)), 1) AS ceiling_used_pct,
  (-COALESCE(mtd.mtd_net_profit, 0) >= b.monthly_loss_ceiling)                        AS ceiling_breached,
  b.stop_date,
  DATE_DIFF(b.stop_date, CURRENT_DATE('America/Los_Angeles'), DAY)                    AS days_left,
  -- THE EXEMPTION: live only while inside the window AND under the SANCTIONED SPEND RATE.
  -- The engine stops, not the human. Spend rate binds; the loss ceiling is a backstop behind it.
  (CURRENT_DATE('America/Los_Angeles') <= b.stop_date
   AND COALESCE(mtd.mtd_spend_per_day, 0) <= b.daily_investment
   AND -COALESCE(mtd.mtd_net_profit, 0) < b.monthly_loss_ceiling)                     AS exemption_live,
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
LEFT JOIN trend t ON t.family = b.family
LEFT JOIN mtd    ON mtd.family = b.family;
