-- =============================================================================================
-- FN_PLAN_SCORECARD(grade_date DATE) — v27.154 (2026-10-01; follow-up the same day: the hint's
-- per-group minimum, and the rule read from each plan row — see THE RULE and THE HINT below): the
-- T+14 grade of the next-week money plan (plan Task 5, first half; spec §5, P-9, P-13, P-14b/c).
-- V_PLAN_SCORECARD is this function at CURRENT_DATE('America/Los_Angeles'); the acceptance calls
-- it with the clock moved forward so
-- the guard's arithmetic is exercised on real decisions before the first one settles. There is no
-- second implementation to drift (the FN_TARGET_BID_SHADOW / V_TARGET_BID_SHADOW pattern).
--
-- It reads only what the plan WROTE (FACT_PLAN_NEXT_WEEK), the order floor that was in force
-- (DE_PLAN_CONFIG) and the outcome (FACT_AMAZON_ADS, as read today, restricted to dates before
-- grade_date). Never V_PLAN_WINDOW_JUDGMENT, which re-anchors the moment the ads watermark moves,
-- and never a ceiling view.
--
-- FIVE ROW TYPES (one column set; a column a row type does not use is NULL on it):
--   GRADE           plan x family x calendar_state, pooled over the graded nights.
--   RECOMMENDATION  family x calendar_state: the declared rule below — WAIT / KEEP_<live> /
--                   SWITCH_TO_<shadow> — and a sentence.
--   FAMILY_WEEK     family x graded night: plan A and plan B side by side for that week.
--   GUARD           week x outcome class (all four classes for every week that has a graded
--                   decision, zeros included): the grade of the P-14b hold and the P-14c release.
--   RULE_HINT       exactly one row: what the GUARD grades say about the strong_day_mult in force,
--                   or WAIT and why. Carries rule_value / rule_min_orders (the rule in force),
--                   held_rows / held_rows_wrong and band_rows / band_released_wrong (the two groups
--                   it compares, under that rule), min_group_rows and other_rule_rows.
--
-- HOW A PLAN IS GRADED (P-9). One plan night per Sunday-start week (the house week) is graded: the
-- latest night in the week that is at least SETTLE_DAYS_MAX complete days old (the approved Task 5
-- rule). While later nights of the same week are still younger than that, the graded night of the
-- week moves forward one night at a time until the week's last night qualifies (run 2026-10-01 at
-- three clocks: the week of 2026-09-27 grades on 09-28 at 10-12, 09-29 at 10-13, 10-01 at 10-15).
-- The 14 days run from the plan NIGHT, so with a 7-day window the last outcome day is 8 days old at
-- the earliest grade: past SP's 7-day attribution, inside SB's 14, so the newest graded week can
-- still move as SB orders land. For every keyword in that night's plan:
--   allocation  = planned_spend_per_day x window_days
--   outcome     = GROSS_PROFIT - Ads_cost over the window_days days starting on the plan night
--   return      = outcome / Ads_cost over those days, 0 where the keyword spent nothing
--   score       = SUM(allocation x return) / SUM(allocation)          (net per allocated dollar)
-- Each allocated dollar is credited with what one ad dollar on that keyword actually netted in the
-- days that followed, so the plan that puts more of its dollars on keywords that went on to make
-- money scores higher. Allocation on keywords that spent nothing afterwards earns 0 and is
-- published as allocated_unrealized_dollars. Assumption, stated: a dollar placed on a keyword
-- earns what that keyword's dollars actually earned — the plan's own price change is not modelled
-- (the learning contract's response model, piece 2, is where that belongs), and neither plan has
-- been uploaded, so this grades where each plan WOULD have put the money.
--
-- DEPARTURE FROM THE TASK 5 DRAFT, AND WHY. The draft scored SUM(outcome) / SUM(allocation). Plans
-- A and B are written on the SAME keywords every night (measured 2026-10-01 on all ten partitions
-- 2026-08-23 .. 10-01: zero keywords in one plan and not the other; the SOP prints the query), so
-- the draft's numerator was identical for both plans and the comparison reduced to which plan
-- allocated fewer dollars: the larger plan won whenever the family lost money and lost whenever it
-- made money, whatever it did with the dollars. realized_net (SUM(outcome) over the live plan's
-- keywords, the same for A and B by construction) is still published on GRADE and FAMILY_WEEK rows.
--
-- THE DECISION RULE IS DECLARED, NOT INFERRED (P-9), in the k CTE:
--   MIN_WINDOWS 3     three graded weeks is the fewest that can show a direction rather than a week.
--   MARGIN      0.10  the shadow plan must beat the live plan by at least 10% of the live plan's
--                     MAGNITUDE. The draft wrote shadow >= live x 1.10, which is right only while
--                     live is positive: with live -0.50 it reads -0.54 >= -0.55 and switches to a
--                     worse plan (the comparison was run as a SELECT on 2026-10-01: TRUE).
-- The live plan is read from the graded rows' is_live_plan (the latest graded night's), not assumed
-- to be B. Ori flips DE_PLAN_CONFIG.live_plan; the code never switches itself.
--
-- HOW THE GUARD IS GRADED (P-14b, P-14c). A decision is a LIVE-plan row written under the
-- last-day test (last_day_strong IS NOT NULL — from the 2026-09-28 partition on) that the judge
-- either HELD (verdict = 'HELD_UNSETTLED') or LET THROUGH (guard_released_by IS NOT NULL:
-- LAST_DAY_NOT_STRONG or HOLD_EXPIRED). The grade READS those two published columns; it never
-- re-derives the guard (the builder's re-derivation vetoed every partition 2026-08-29 .. 09-28).
-- A decision is graded once grade_date has reached its own settle_due_on (window_to + 7 for SP,
-- + 14 for SB). Its SETTLED verdict re-reads THE SAME WINDOW (window_from .. window_to) from
-- FACT_AMAZON_ADS: good = Ads_orders >= the min_orders DE_PLAN_CONFIG had in force for the row's
-- calendar_state when the row was built (the latest config row with updated_at <= built_at; the
-- SOP's retire-then-insert recipe keeps superseded rows and sets only is_active on them, so their
-- updated_at still dates them) AND GROSS_PROFIT per ad dollar >= the row's family_bar. Classes:
--   HELD_RIGHT      held, and settled good          HELD_WRONG      held, settled not good
--   RELEASED_RIGHT  let through, settled not good   RELEASED_WRONG  let through, settled good
-- Each night's decision is graded on its own window, so a keyword held three nights running is
-- three graded decisions; `keywords` counts the distinct ones beside them.
--
-- THE RULE EACH DECISION WAS MADE UNDER (v27.154 follow-up). This file keeps NO copy of the
-- judge's P-14c settings. Every plan row carries the strong_day_mult and strong_day_min_orders it
-- was judged under (V_PLAN_WINDOW_JUDGMENT publishes them, SP_BUILD_NEXT_WEEK_PLAN copies them;
-- migration 2026-10-01_plan_strong_day_rule_columns.sql). Rows written before those columns existed
-- (as_of <= LEGACY_THROUGH) hold NULL and are read as LEGACY_STRONG_DAY_MULT / _MIN_ORDERS: frozen
-- history, the values the judge's k CTE carried from v27.147 (commit 41d2318; `git log -S` on either
-- k line lists that commit alone, and the deployed view read 1.5 / 1 on 2026-10-01). They never move
-- when the judge's rule moves. A row after LEGACY_THROUGH with no stored rule has no rule at all
-- here; acceptance C10 goes red on it.
--
-- THE HINT (RULE_HINT) is about THE RULE IN FORCE: the multiplier and order minimum on the live
-- plan's latest P-14c night on or before grade_date (published as rule_value / rule_min_orders). It
-- reads only graded decisions made under that rule; the others stay in the GUARD rows and are
-- counted as other_rule_rows. Below MIN_GUARD_ROWS graded decisions it says WAIT and why — with
-- nothing old enough to grade, it counts the decisions written and names the date the first one
-- settles. From there it compares two groups, both under the rule in force: HELD (held_rows), and
-- THE BAND — released by LAST_DAY_NOT_STRONG with a last day between BAND_LOW_X_BAR and the row's
-- own multiplier times the bar, the keywords a lower threshold would have held (band_rows). WHILE
-- EITHER GROUP HAS FEWER THAN MIN_GROUP_ROWS graded rows it says WAIT and names the group that is
-- too small and its count. Otherwise: RELEASED_WRONG above DOMINATE_SHARE of the band =>
-- LOWER_STRONG_DAY_MULT; HELD_WRONG above DOMINATE_SHARE of the held => RAISE_STRONG_DAY_MULT; both
-- => NO_CLEAN_SIGNAL; neither => KEEP_STRONG_DAY_MULT, each sentence leading with the size of the
-- group it argued from. Nothing here changes the threshold.
--   MIN_GUARD_ROWS   20   the fewest graded decisions in all the hint will read (the Task C ruling).
--   MIN_GROUP_ROWS   10   the fewest graded rows in EACH group before LOWER / RAISE / KEEP /
--                         NO_CLEAN_SIGNAL. Ori rules on the number. Why 10: a group whose true
--                         wrong-rate is 30% reads "more than half wrong" by chance less than one
--                         time in twenty only from 10 rows up (binomial, computed 2026-10-01: 4.7% at
--                         10, 9.9% at 9, 5.8% at 8). The total alone was not enough: on the history
--                         108 of the first 117 decisions are releases, 9 holds and 4 band rows, and at
--                         the 2026-10-03 clock 20 graded decisions held 0 holds and 1 band row.
--   DOMINATE_SHARE   0.5  "dominates" = more than half of the rows compared.
--   BAND_LOW_X_BAR   1.0  the band's floor: a last day at the bar or better.
--   SETTLE_DAYS_MAX  14   a plan night is graded once it is this many complete days old.
--   LEGACY_*              see above: history, not a setting.
-- Declared constants (Standing Rule 0 exempt). The learning contract (2026-10-01 design §4, §8)
-- moves settings of this kind to DE_COACH_THRESHOLDS under strategy_id 'LEARNING' when its proposer
-- is built; until then they are declared here, once.
--
-- COST, measured 2026-10-01 at deploy (uncached): V_PLAN_SCORECARD 354 slot-s, 70.8 MB, 4.6 s; at
-- today + 30, 391 slot-s. After the follow-up, inside the acceptance run of 2026-10-01 (uncached):
-- the view 265.5 slot-s, today + 30 490.7, 2026-10-03 402.5. The follow-up adds no FACT_AMAZON_ADS
-- read (rule_rows reads FACT_PLAN_NEXT_WEEK only). The FACT_AMAZON_ADS joins are clustered and
-- touch a handful of plan nights; the slot time is spread over the union's many small stages, not
-- the scan. Far under the 5,000 slot-s line at which this would be materialised by an orchestrator
-- step, so nothing is.
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md §5, P-9, P-13, P-14.
-- Learning contract: docs/superpowers/specs/2026-10-01-learning-contract-design.md (piece 0, Task C).
-- SOP: architecture/NEXT_WEEK_MONEY.md §6 "Grading".
-- Acceptance: scripts/bigquery/tests/PLAN_SCORECARD_acceptance.sql, and
-- scripts/bigquery/tests/check_plan_scorecard_hint_branches.py (this body on doctored plan tables).
-- =============================================================================================
CREATE OR REPLACE TABLE FUNCTION `onyga-482313.OI.FN_PLAN_SCORECARD`(grade_date DATE)
OPTIONS (description = "v27.154 follow-up (2026-10-01): RULE_HINT judges the rule in force (the strong_day_mult / strong_day_min_orders stored on the live plan's latest P-14c night) from the graded decisions made under it, and says WAIT, naming the group and its count, until BOTH groups it compares (held; let through with a last day between 1.0x and the row's own multiplier) have at least 10 graded rows; each decision is graded against the multiplier stored on its row (frozen 1.5 / 1 for rows written before the columns existed), never a copy kept here. v27.154 (2026-10-01): the T+14 grade of the next-week money plan as of grade_date (plan Task 5; spec §5, P-9, P-14b/c). GRADE per plan x family x calendar_state and FAMILY_WEEK per family x graded night: one plan night per Sunday-start week, at least 14 days old; allocation = planned_spend_per_day x window_days; net per allocated dollar = SUM(allocation x the keyword's realized net per ad dollar over the window_days days starting on the plan night) / SUM(allocation) — not the draft's SUM(net)/SUM(allocation), which is identical for A and B on the same keywords and so only compared allocation sizes. RECOMMENDATION per family x calendar_state: WAIT below 3 graded weeks, SWITCH_TO_<shadow> when the shadow beats the live plan by 10% of the live plan's magnitude, else KEEP_<live>; Ori flips DE_PLAN_CONFIG.live_plan. GUARD per week x outcome class grades every live-plan decision written under P-14c (HELD_UNSETTLED, or guard_released_by set) once its settle_due_on has passed, re-reading the same window: settled good = min_orders in force at built_at and gross profit per ad dollar >= family_bar; classes HELD_RIGHT/HELD_WRONG/RELEASED_RIGHT/RELEASED_WRONG with settled spend, net and last-day return quantiles. RULE_HINT: WAIT below 20 graded decisions in all or 10 in either group (saying why), else LOWER / RAISE / KEEP_STRONG_DAY_MULT or NO_CLEAN_SIGNAL. Reads what the plan wrote, never re-derives the guard. SOP: architecture/NEXT_WEEK_MONEY.md §6.")
AS
WITH k AS (
  SELECT 3    AS min_windows,
         0.10 AS margin,
         14   AS settle_days_max,
         20   AS min_guard_rows,
         10   AS min_group_rows,          -- per group the hint compares; Ori rules on the number
         0.5  AS dominate_share,
         1.0  AS band_low_x_bar,
         -- HISTORY, not a setting: the rule on rows written before the columns existed
         1.5  AS legacy_strong_day_mult,
         1    AS legacy_strong_day_min_orders,
         DATE '2026-10-01' AS legacy_through
),
-- ---------------------------------------------------------------------------------------------
-- THE PLAN GRADE: one night per Sunday-start week, old enough to have settled
-- ---------------------------------------------------------------------------------------------
nights AS (
  SELECT p.as_of, MAX(p.window_days) AS window_days, MAX(p.calendar_state) AS calendar_state
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p
  CROSS JOIN k
  WHERE DATE_DIFF(grade_date, p.as_of, DAY) >= k.settle_days_max
  GROUP BY p.as_of
  QUALIFY ROW_NUMBER() OVER (PARTITION BY DATE_TRUNC(p.as_of, WEEK(SUNDAY)) ORDER BY p.as_of DESC) = 1
),
rows_graded AS (
  SELECT p.as_of, p.plan, p.is_live_plan, p.family, n.calendar_state, n.window_days,
         p.campaign_id, p.keyword_id,
         p.planned_spend_per_day * n.window_days AS alloc
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p
  JOIN nights n USING (as_of)
),
after_ask AS (
  SELECT DISTINCT as_of, campaign_id, keyword_id,
         DATE_ADD(as_of, INTERVAL window_days - 1 DAY) AS d_to
  FROM rows_graded
),
after_rec AS (
  SELECT a.as_of, a.campaign_id, a.keyword_id,
         SUM(f.GROSS_PROFIT) AS gp,
         SUM(f.Ads_cost)     AS sp
  FROM after_ask a
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` f
    ON f.campaign_id = a.campaign_id
   AND f.keyword_id  = a.keyword_id
   AND f.date BETWEEN a.as_of AND a.d_to
   AND f.date < grade_date
  GROUP BY 1, 2, 3
),
joined AS (
  SELECT r.*,
         COALESCE(a.sp, 0)                     AS sp_after,
         COALESCE(a.gp, 0) - COALESCE(a.sp, 0) AS net_after,
         -- the keyword's realized net per ad dollar in the days that followed; 0 where it spent nothing
         IF(COALESCE(a.sp, 0) > 0, (COALESCE(a.gp, 0) - a.sp) / a.sp, 0) AS ret_after
  FROM rows_graded r
  LEFT JOIN after_rec a USING (as_of, campaign_id, keyword_id)
),
grades AS (
  SELECT plan, family, calendar_state,
         COUNT(DISTINCT as_of)           AS graded_windows,
         SUM(alloc)                      AS alloc,
         SUM(net_after)                  AS realized_net,   -- the same for A and B: same keywords
         SUM(alloc * ret_after)          AS nar,
         SUM(IF(sp_after = 0, alloc, 0)) AS alloc_unrealized
  FROM joined
  GROUP BY 1, 2, 3
),
-- the live plan of the latest graded night, per family x state (never assumed to be B)
live AS (
  SELECT family, calendar_state,
         ARRAY_AGG(plan ORDER BY as_of DESC, plan LIMIT 1)[OFFSET(0)] AS live_plan
  FROM rows_graded
  WHERE is_live_plan
  GROUP BY 1, 2
),
paired AS (
  SELECT g.family, g.calendar_state,
         MAX(g.graded_windows)                                   AS graded_windows,
         MAX(IF(g.plan = 'A', g.alloc, NULL))                    AS alloc_a,
         MAX(IF(g.plan = 'A', g.nar, NULL))                      AS nar_a,
         ROUND(SAFE_DIVIDE(MAX(IF(g.plan = 'A', g.nar, NULL)),
                           NULLIF(MAX(IF(g.plan = 'A', g.alloc, NULL)), 0)), 4) AS npd_a,
         MAX(IF(g.plan = 'B', g.alloc, NULL))                    AS alloc_b,
         MAX(IF(g.plan = 'B', g.nar, NULL))                      AS nar_b,
         ROUND(SAFE_DIVIDE(MAX(IF(g.plan = 'B', g.nar, NULL)),
                           NULLIF(MAX(IF(g.plan = 'B', g.alloc, NULL)), 0)), 4) AS npd_b,
         MAX(l.live_plan)                                        AS live_plan
  FROM grades g
  LEFT JOIN live l USING (family, calendar_state)
  GROUP BY 1, 2
),
decided AS (
  SELECT p.*,
         IF(p.live_plan = 'A', 'B', 'A')         AS shadow_plan,
         IF(p.live_plan = 'A', p.npd_a, p.npd_b) AS npd_live,
         IF(p.live_plan = 'A', p.npd_b, p.npd_a) AS npd_shadow,
         CASE
           WHEN p.graded_windows < k.min_windows THEN 'WAIT'
           WHEN p.live_plan IS NULL THEN 'WAIT'
           WHEN IF(p.live_plan = 'A', p.npd_a, p.npd_b) IS NULL
             OR IF(p.live_plan = 'A', p.npd_b, p.npd_a) IS NULL THEN 'WAIT'
           WHEN IF(p.live_plan = 'A', p.npd_b, p.npd_a) > IF(p.live_plan = 'A', p.npd_a, p.npd_b)
            AND IF(p.live_plan = 'A', p.npd_b, p.npd_a) - IF(p.live_plan = 'A', p.npd_a, p.npd_b)
                >= k.margin * ABS(IF(p.live_plan = 'A', p.npd_a, p.npd_b))
             THEN CONCAT('SWITCH_TO_', IF(p.live_plan = 'A', 'B', 'A'))
           ELSE CONCAT('KEEP_', p.live_plan)
         END AS recommendation,
         k.min_windows, k.margin
  FROM paired p
  CROSS JOIN k
),
family_week AS (
  SELECT family, as_of AS graded_night, DATE_TRUNC(as_of, WEEK(SUNDAY)) AS week_start,
         MAX(calendar_state)                        AS calendar_state,
         MAX(window_days)                           AS window_days,
         SUM(IF(plan = 'A', alloc, 0))              AS alloc_a,
         SUM(IF(plan = 'A', alloc * ret_after, 0))  AS nar_a,
         SUM(IF(plan = 'B', alloc, 0))              AS alloc_b,
         SUM(IF(plan = 'B', alloc * ret_after, 0))  AS nar_b,
         SUM(IF(is_live_plan, net_after, 0))        AS realized_net,
         MAX(IF(is_live_plan, plan, NULL))          AS live_plan
  FROM joined
  GROUP BY 1, 2, 3
),
-- ---------------------------------------------------------------------------------------------
-- THE GUARD GRADE: every hold and every release the live plan wrote under P-14c
-- ---------------------------------------------------------------------------------------------
-- the P-14c rule each live row was judged under: stored on the row, or the frozen legacy values for
-- a row written before the columns existed; NULL for a later row the builder wrote without it
rule_rows AS (
  SELECT p.as_of,
         COALESCE(p.strong_day_mult,
                  IF(p.as_of <= k.legacy_through, k.legacy_strong_day_mult, NULL))       AS eff_mult,
         COALESCE(p.strong_day_min_orders,
                  IF(p.as_of <= k.legacy_through, k.legacy_strong_day_min_orders, NULL)) AS eff_min
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p
  CROSS JOIN k
  WHERE p.is_live_plan
    AND p.last_day_strong IS NOT NULL               -- written under the last-day test (P-14c)
    AND p.as_of <= grade_date
),
-- THE RULE IN FORCE: the one the latest such night was judged under. Always one row (NULLs when the
-- plan has written nothing under P-14c), so the hint row can never vanish.
rule_now AS (
  SELECT MAX(r.as_of)                              AS rule_as_of,
         MAX(IF(r.as_of = m.d, r.eff_mult, NULL))  AS rule_mult,
         MAX(IF(r.as_of = m.d, r.eff_min, NULL))   AS rule_min
  FROM rule_rows r
  CROSS JOIN (SELECT MAX(as_of) AS d FROM rule_rows) m
),
guard_written AS (
  SELECT p.as_of, p.family, p.calendar_state, p.campaign_id, p.keyword_id,
         p.window_from, p.window_to, p.settle_due_on, p.family_bar,
         p.last_day_ret, p.guard_released_by, p.built_at,
         -- the same expressions as rule_rows: the rule this decision was made under
         COALESCE(p.strong_day_mult,
                  IF(p.as_of <= k.legacy_through, k.legacy_strong_day_mult, NULL))       AS eff_mult,
         COALESCE(p.strong_day_min_orders,
                  IF(p.as_of <= k.legacy_through, k.legacy_strong_day_min_orders, NULL)) AS eff_min,
         IF(p.verdict = 'HELD_UNSETTLED', 'HELD', 'RELEASED') AS decision
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p
  CROSS JOIN k
  WHERE p.is_live_plan
    AND p.last_day_strong IS NOT NULL               -- written under the last-day test (P-14c)
    AND (p.verdict = 'HELD_UNSETTLED' OR p.guard_released_by IS NOT NULL)
    AND p.as_of <= grade_date
),
guard_due AS (
  SELECT * FROM guard_written WHERE settle_due_on <= grade_date
),
cfg_active AS (
  SELECT calendar_state, min_orders
  FROM `onyga-482313.OI.DE_PLAN_CONFIG`
  WHERE is_active
  QUALIFY ROW_NUMBER() OVER (PARTITION BY calendar_state ORDER BY updated_at DESC) = 1
),
-- the order floor in force when the row was built; the active row only if none is older than it
guard_cfg AS (
  SELECT g.*, COALESCE(c.min_orders, a.min_orders) AS min_orders
  FROM guard_due g
  LEFT JOIN `onyga-482313.OI.DE_PLAN_CONFIG` c
    ON c.calendar_state = g.calendar_state AND c.updated_at <= g.built_at
  LEFT JOIN cfg_active a
    ON a.calendar_state = g.calendar_state
  QUALIFY ROW_NUMBER() OVER (PARTITION BY g.as_of, g.campaign_id, g.keyword_id
                             ORDER BY c.updated_at DESC) = 1
),
guard_ask AS (
  SELECT DISTINCT campaign_id, keyword_id, window_from, window_to FROM guard_due
),
guard_rec AS (
  SELECT a.campaign_id, a.keyword_id, a.window_from, a.window_to,
         SUM(f.Ads_cost)     AS sp,
         SUM(f.Ads_orders)   AS ord,
         SUM(f.GROSS_PROFIT) AS gp
  FROM guard_ask a
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` f
    ON f.campaign_id = a.campaign_id
   AND f.keyword_id  = a.keyword_id
   AND f.date BETWEEN a.window_from AND a.window_to
   AND f.date < grade_date
  GROUP BY 1, 2, 3, 4
),
guard_cls AS (
  SELECT c.*,
         CASE WHEN c.decision = 'HELD' AND c.settled_good THEN 'HELD_RIGHT'
              WHEN c.decision = 'HELD'                    THEN 'HELD_WRONG'
              WHEN NOT c.settled_good                     THEN 'RELEASED_RIGHT'
              ELSE                                             'RELEASED_WRONG' END AS outcome_class
  FROM (
    SELECT g.*,
           COALESCE(r.sp, 0)  AS s_sp,
           COALESCE(r.ord, 0) AS s_ord,
           COALESCE(r.gp, 0)  AS s_gp,
           COALESCE(COALESCE(r.ord, 0) >= g.min_orders
                    AND COALESCE(SAFE_DIVIDE(r.gp, NULLIF(r.sp, 0)), -1) >= g.family_bar, FALSE) AS settled_good,
           SAFE_DIVIDE(g.last_day_ret, NULLIF(g.family_bar, 0)) AS last_day_x_bar,
           DATE_TRUNC(g.as_of, WEEK(SUNDAY))                    AS week_start
    FROM guard_cfg g
    LEFT JOIN guard_rec r USING (campaign_id, keyword_id, window_from, window_to)
  ) c
),
guard_q AS (
  SELECT g.*,
         PERCENTILE_CONT(g.last_day_ret, 0.25)   OVER w AS r25,
         PERCENTILE_CONT(g.last_day_ret, 0.50)   OVER w AS r50,
         PERCENTILE_CONT(g.last_day_ret, 0.75)   OVER w AS r75,
         PERCENTILE_CONT(g.last_day_x_bar, 0.25) OVER w AS x25,
         PERCENTILE_CONT(g.last_day_x_bar, 0.50) OVER w AS x50,
         PERCENTILE_CONT(g.last_day_x_bar, 0.75) OVER w AS x75
  FROM guard_cls g
  WINDOW w AS (PARTITION BY g.week_start, g.outcome_class)
),
-- the week's decisions are counted BEFORE they are classed, so the four classes can be held to it
guard_weeks AS (
  SELECT week_start,
         COUNT(*)                                  AS graded_rows,
         COUNTIF(outcome_class = 'HELD_RIGHT')     AS held_right,
         COUNTIF(outcome_class = 'HELD_WRONG')     AS held_wrong,
         COUNTIF(outcome_class = 'RELEASED_RIGHT') AS released_right,
         COUNTIF(outcome_class = 'RELEASED_WRONG') AS released_wrong,
         STRING_AGG(DISTINCT calendar_state, ',' ORDER BY calendar_state) AS states,
         MAX(settle_due_on)                        AS last_settle_due_on
  FROM guard_cls
  GROUP BY 1
),
guard_out AS (
  SELECT w.week_start, cl AS outcome_class, w.graded_rows, w.held_right, w.held_wrong,
         w.released_right, w.released_wrong, w.states, w.last_settle_due_on,
         COUNT(q.keyword_id)                                      AS class_rows,
         COUNT(DISTINCT CONCAT(q.campaign_id, '|', q.keyword_id)) AS keywords,
         COALESCE(SUM(q.s_sp), 0)                                 AS settled_spend,
         COALESCE(SUM(q.s_gp - q.s_sp), 0)                        AS settled_net,
         MAX(q.r25) AS r25, MAX(q.r50) AS r50, MAX(q.r75) AS r75,
         MAX(q.x25) AS x25, MAX(q.x50) AS x50, MAX(q.x75) AS x75
  FROM guard_weeks w
  CROSS JOIN UNNEST(['HELD_RIGHT', 'HELD_WRONG', 'RELEASED_RIGHT', 'RELEASED_WRONG']) AS cl
  LEFT JOIN guard_q q
    ON q.week_start = w.week_start AND q.outcome_class = cl
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
-- the hint's inputs. The totals (graded .. rw) are every graded decision, so they equal the GUARD
-- weeks' totals; the two groups it compares are read under the rule in force only (u), and a band
-- row's top is ITS OWN multiplier, never a constant of this file.
hint_in AS (
  SELECT COUNT(g.keyword_id)                                         AS graded,
         COUNT(DISTINCT CONCAT(g.campaign_id, '|', g.keyword_id))    AS kws,
         COUNT(DISTINCT g.week_start)                                AS weeks,
         COUNTIF(g.outcome_class = 'HELD_RIGHT')                     AS hr,
         COUNTIF(g.outcome_class = 'HELD_WRONG')                     AS hw,
         COUNTIF(g.outcome_class = 'RELEASED_RIGHT')                 AS rr,
         COUNTIF(g.outcome_class = 'RELEASED_WRONG')                 AS rw,
         COUNTIF(NOT g.u)                                            AS other_rule_n,
         COUNTIF(g.u AND g.decision = 'HELD')                        AS held_n,
         COUNTIF(g.u AND g.outcome_class = 'HELD_WRONG')             AS held_wrong_n,
         COALESCE(SUM(IF(g.u AND g.outcome_class = 'HELD_WRONG', g.s_sp, 0)), 0) AS hw_sp,
         COUNTIF(g.u AND g.in_band)                                  AS band_n,
         COUNTIF(g.u AND g.in_band AND g.outcome_class = 'RELEASED_WRONG') AS band_wrong,
         COALESCE(SUM(IF(g.u AND g.in_band AND g.outcome_class = 'RELEASED_WRONG', g.s_sp, 0)), 0) AS band_wrong_sp
  FROM (
    SELECT c.*,
           COALESCE(c.eff_mult = r.rule_mult AND c.eff_min = r.rule_min, FALSE) AS u,
           COALESCE(c.guard_released_by = 'LAST_DAY_NOT_STRONG'
                    AND c.last_day_x_bar >= k.band_low_x_bar
                    AND c.last_day_x_bar <  c.eff_mult, FALSE)               AS in_band
    FROM guard_cls c
    CROSS JOIN rule_now r
    CROSS JOIN k
  ) g
),
pending AS (
  SELECT COUNT(*)                                                 AS written,
         COUNTIF(decision = 'HELD')                               AS held_w,
         COUNTIF(decision = 'RELEASED')                           AS released_w,
         MIN(as_of)                                               AS first_written,
         MIN(IF(settle_due_on > grade_date, settle_due_on, NULL)) AS next_due
  FROM guard_written
),
hint AS (
  SELECT h.*, p.*, r.*, k.min_guard_rows, k.min_group_rows, k.dominate_share, k.band_low_x_bar,
         CASE
           WHEN h.graded < k.min_guard_rows                                  THEN 'WAIT'
           WHEN r.rule_mult IS NULL OR r.rule_min IS NULL                    THEN 'WAIT'
           WHEN h.held_n < k.min_group_rows OR h.band_n < k.min_group_rows   THEN 'WAIT'
           WHEN h.band_wrong > k.dominate_share * h.band_n
            AND h.held_wrong_n > k.dominate_share * h.held_n                 THEN 'NO_CLEAN_SIGNAL'
           WHEN h.band_wrong > k.dominate_share * h.band_n                   THEN 'LOWER_STRONG_DAY_MULT'
           WHEN h.held_wrong_n > k.dominate_share * h.held_n                 THEN 'RAISE_STRONG_DAY_MULT'
           ELSE                                                                   'KEEP_STRONG_DAY_MULT'
         END AS hint_rec,
         -- appended to every sentence that reads a population: the totals, and what was left out
         FORMAT(' %d graded guard decision(s) in all, over %d week(s).%s', h.graded, h.weeks,
                IF(h.other_rule_n > 0,
                   FORMAT(' %d of them were made under a different or unrecorded rule and are left out of this hint; they are in the GUARD rows.', h.other_rule_n),
                   '')) AS tail
  FROM hint_in h CROSS JOIN pending p CROSS JOIN rule_now r CROSS JOIN k
)
-- ---------------------------------------------------------------------------------------------
SELECT 'GRADE' AS row_type, g.plan, g.family, g.calendar_state,
       CAST(NULL AS DATE) AS week_start, CAST(NULL AS DATE) AS graded_night, l.live_plan,
       g.graded_windows,
       ROUND(g.alloc, 2)                                         AS allocated_dollars,
       ROUND(g.realized_net, 2)                                  AS realized_net,
       ROUND(g.nar, 2)                                           AS net_at_realized_returns,
       ROUND(SAFE_DIVIDE(g.nar, NULLIF(g.alloc, 0)), 4)          AS net_per_allocated_dollar,
       ROUND(g.alloc_unrealized, 2)                              AS allocated_unrealized_dollars,
       CAST(NULL AS FLOAT64) AS allocated_a, CAST(NULL AS FLOAT64) AS net_at_realized_a,
       CAST(NULL AS FLOAT64) AS npd_a,
       CAST(NULL AS FLOAT64) AS allocated_b, CAST(NULL AS FLOAT64) AS net_at_realized_b,
       CAST(NULL AS FLOAT64) AS npd_b,
       CAST(NULL AS STRING) AS outcome_class, CAST(NULL AS INT64) AS class_rows,
       CAST(NULL AS INT64) AS graded_rows, CAST(NULL AS INT64) AS keywords,
       CAST(NULL AS INT64) AS held_right, CAST(NULL AS INT64) AS held_wrong,
       CAST(NULL AS INT64) AS released_right, CAST(NULL AS INT64) AS released_wrong,
       CAST(NULL AS FLOAT64) AS settled_spend, CAST(NULL AS FLOAT64) AS settled_net,
       CAST(NULL AS FLOAT64) AS last_day_ret_p25, CAST(NULL AS FLOAT64) AS last_day_ret_p50,
       CAST(NULL AS FLOAT64) AS last_day_ret_p75,
       CAST(NULL AS FLOAT64) AS last_day_x_bar_p25, CAST(NULL AS FLOAT64) AS last_day_x_bar_p50,
       CAST(NULL AS FLOAT64) AS last_day_x_bar_p75,
       CAST(NULL AS DATE) AS last_settle_due_on,
       CAST(NULL AS INT64) AS band_rows, CAST(NULL AS INT64) AS band_released_wrong,
       CAST(NULL AS FLOAT64) AS rule_value,
       CAST(NULL AS INT64) AS rule_min_orders,
       CAST(NULL AS INT64) AS held_rows, CAST(NULL AS INT64) AS held_rows_wrong,
       CAST(NULL AS INT64) AS min_group_rows, CAST(NULL AS INT64) AS other_rule_rows,
       CAST(NULL AS STRING) AS recommendation,
       FORMAT('Plan %s%s in %s, %s: $%.2f allocated over %d graded week(s). At what each keyword\'s ad dollars actually netted in the days that followed, those dollars netted $%.2f, %.4f per allocated dollar; $%.2f of the allocation sat on keywords that then spent nothing and earned 0. The keywords themselves netted $%.2f.',
              g.plan, IF(g.plan = l.live_plan, ' (live)', ' (shadow)'), g.family, g.calendar_state,
              g.alloc, g.graded_windows, g.nar, COALESCE(SAFE_DIVIDE(g.nar, NULLIF(g.alloc, 0)), 0),
              g.alloc_unrealized, g.realized_net) AS sentence
FROM grades g
LEFT JOIN live l USING (family, calendar_state)

UNION ALL
SELECT 'RECOMMENDATION', CAST(NULL AS STRING), d.family, d.calendar_state,
       CAST(NULL AS DATE), CAST(NULL AS DATE), d.live_plan,
       d.graded_windows,
       CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
       ROUND(COALESCE(d.npd_a, 0) - COALESCE(d.npd_b, 0), 4),
       CAST(NULL AS FLOAT64),
       ROUND(d.alloc_a, 2), ROUND(d.nar_a, 2), d.npd_a,
       ROUND(d.alloc_b, 2), ROUND(d.nar_b, 2), d.npd_b,
       CAST(NULL AS STRING), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
       CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
       CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
       CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
       CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
       CAST(NULL AS DATE), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS FLOAT64),
       CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
       d.recommendation,
       CASE
         WHEN d.recommendation = 'WAIT' THEN FORMAT(
           'Not enough evidence yet for %s in %s: %d graded week(s) of the %d this rule needs. So far each dollar the live plan %s allocated netted %s and each dollar the shadow plan %s allocated netted %s. Nothing changes; plan %s stays live.',
           d.family, d.calendar_state, d.graded_windows, d.min_windows,
           COALESCE(d.live_plan, '(none recorded)'),
           COALESCE(FORMAT('%.4f', d.npd_live), 'nothing (it allocated no dollars)'),
           d.shadow_plan, COALESCE(FORMAT('%.4f', d.npd_shadow), 'nothing (it allocated no dollars)'),
           COALESCE(d.live_plan, '(none recorded)'))
         WHEN STARTS_WITH(d.recommendation, 'SWITCH_TO_') THEN FORMAT(
           'Over %d graded weeks the shadow plan %s put its dollars where more net profit turned up in %s, %s: each allocated dollar netted %.4f against %.4f for the live plan %s, more than the %d%% margin this rule asks for. Consider switching by setting live_plan to %s for %s in DE_PLAN_CONFIG. The code never switches itself.',
           d.graded_windows, d.shadow_plan, d.family, d.calendar_state, d.npd_shadow, d.npd_live,
           d.live_plan, CAST(ROUND(100 * d.margin) AS INT64), d.shadow_plan, d.calendar_state)
         ELSE FORMAT(
           'Over %d graded weeks the live plan %s holds in %s, %s: each allocated dollar netted %.4f against %.4f for the shadow plan %s, which is not ahead by the %d%% margin this rule asks for. Keep plan %s.',
           d.graded_windows, d.live_plan, d.family, d.calendar_state, d.npd_live, d.npd_shadow,
           d.shadow_plan, CAST(ROUND(100 * d.margin) AS INT64), d.live_plan)
       END
FROM decided d

UNION ALL
SELECT 'FAMILY_WEEK', CAST(NULL AS STRING), w.family, w.calendar_state,
       w.week_start, w.graded_night, w.live_plan,
       CAST(NULL AS INT64),
       CAST(NULL AS FLOAT64), ROUND(w.realized_net, 2), CAST(NULL AS FLOAT64),
       ROUND(COALESCE(SAFE_DIVIDE(w.nar_a, NULLIF(w.alloc_a, 0)), 0)
             - COALESCE(SAFE_DIVIDE(w.nar_b, NULLIF(w.alloc_b, 0)), 0), 4),
       CAST(NULL AS FLOAT64),
       ROUND(w.alloc_a, 2), ROUND(w.nar_a, 2), ROUND(SAFE_DIVIDE(w.nar_a, NULLIF(w.alloc_a, 0)), 4),
       ROUND(w.alloc_b, 2), ROUND(w.nar_b, 2), ROUND(SAFE_DIVIDE(w.nar_b, NULLIF(w.alloc_b, 0)), 4),
       CAST(NULL AS STRING), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
       CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
       CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
       CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
       CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
       CAST(NULL AS DATE), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS FLOAT64),
       CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
       CAST(NULL AS STRING),
       FORMAT('%s, week of %t, plan night %t (%s, %d-day window): plan A allocated $%.2f and those dollars netted $%.2f (%s per dollar); plan B allocated $%.2f and netted $%.2f (%s per dollar). The live plan was %s. The keywords themselves netted $%.2f in the %d days from the plan night.',
              w.family, w.week_start, w.graded_night, w.calendar_state, w.window_days,
              w.alloc_a, w.nar_a, COALESCE(FORMAT('%.4f', SAFE_DIVIDE(w.nar_a, NULLIF(w.alloc_a, 0))), 'nothing'),
              w.alloc_b, w.nar_b, COALESCE(FORMAT('%.4f', SAFE_DIVIDE(w.nar_b, NULLIF(w.alloc_b, 0))), 'nothing'),
              COALESCE(w.live_plan, 'not recorded'), w.realized_net, w.window_days)
FROM family_week w

UNION ALL
SELECT 'GUARD', CAST(NULL AS STRING), CAST(NULL AS STRING), o.states,
       o.week_start, CAST(NULL AS DATE), CAST(NULL AS STRING),
       CAST(NULL AS INT64),
       CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
       CAST(NULL AS FLOAT64),
       CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
       CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
       o.outcome_class, o.class_rows, o.graded_rows, o.keywords,
       o.held_right, o.held_wrong, o.released_right, o.released_wrong,
       ROUND(o.settled_spend, 2), ROUND(o.settled_net, 2),
       ROUND(o.r25, 4), ROUND(o.r50, 4), ROUND(o.r75, 4),
       ROUND(o.x25, 4), ROUND(o.x50, 4), ROUND(o.x75, 4),
       o.last_settle_due_on, CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS FLOAT64),
       CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
       CAST(NULL AS STRING),
       FORMAT('Week of %t: %d of the %d graded guard decision(s) (%d keyword(s)) were %s. Their settled windows spent $%.2f and netted $%.2f.',
              o.week_start, o.class_rows, o.graded_rows, o.keywords,
              CASE o.outcome_class
                WHEN 'HELD_RIGHT'     THEN 'held on the good side by a very good last day, and the window was good once it settled'
                WHEN 'HELD_WRONG'     THEN 'held on the good side by a very good last day, but the window was NOT good once it settled: money the guard protected that it should not have'
                WHEN 'RELEASED_RIGHT' THEN 'let through to the not-good side (last day not very good, or the hold ran out), and the window was indeed not good once it settled'
                ELSE                       'let through to the not-good side, but the window turned out GOOD once it settled: keywords the guard should have held'
              END,
              o.settled_spend, o.settled_net)
FROM guard_out o

UNION ALL
SELECT 'RULE_HINT', CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(NULL AS STRING),
       CAST(NULL AS DATE), CAST(NULL AS DATE), CAST(NULL AS STRING),
       CAST(NULL AS INT64),
       CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
       CAST(NULL AS FLOAT64),
       CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
       CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
       CAST(NULL AS STRING), CAST(NULL AS INT64), h.graded, h.kws,
       h.hr, h.hw, h.rr, h.rw,
       CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
       CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
       CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
       CAST(NULL AS DATE), h.band_n, h.band_wrong, h.rule_mult,
       h.rule_min, h.held_n, h.held_wrong_n, h.min_group_rows, h.other_rule_n,
       h.hint_rec,
       CASE
         WHEN h.graded = 0 AND h.written = 0 THEN
           'WAIT: the live plan has written no guard decision under the last-day test (P-14c) yet, so there is nothing to grade. Nothing changes.'
         WHEN h.graded = 0 THEN FORMAT(
           'WAIT: no guard decision is old enough to grade yet. Since %t the live plan has written %d guard decision(s): %d held on the good side by a very good last day, %d let through to the not-good side by the last-day test or the hold\'s clock. A decision is graded once its window has settled (7 days after the window ends for SP keywords, 14 for SB); the first one settles on %s. Nothing changes.',
           h.first_written, h.written, h.held_w, h.released_w,
           COALESCE(CAST(h.next_due AS STRING), 'a date not yet known'))
         WHEN h.graded < h.min_guard_rows THEN FORMAT(
           'WAIT: %d graded guard decision(s) of the %d this hint needs (held right %d, held wrong %d, let through right %d, let through wrong %d, over %d week(s)). %d more decision(s) are written and not yet settled. Nothing changes.',
           h.graded, h.min_guard_rows, h.hr, h.hw, h.rr, h.rw, h.weeks, h.written - h.graded)
         WHEN h.rule_mult IS NULL OR h.rule_min IS NULL THEN FORMAT(
           'WAIT: the live plan\'s latest night (%t) carries no last-day rule (strong_day_mult %s, strong_day_min_orders %s), so there is no rule in force to argue about. The builder copies both from the judge onto every row; a night written without them is a broken copy (acceptance C10).%s Nothing changes.',
           h.rule_as_of, COALESCE(FORMAT('%g', h.rule_mult), 'missing'),
           COALESCE(CAST(h.rule_min AS STRING), 'missing'), h.tail)
         WHEN h.hint_rec = 'WAIT' THEN CONCAT(
           'WAIT: ',
           CASE
             WHEN h.held_n < h.min_group_rows AND h.band_n < h.min_group_rows THEN FORMAT(
               'both groups this hint compares are too small: %d held of the %d needed, and %d let through in the band of the %d needed.',
               h.held_n, h.min_group_rows, h.band_n, h.min_group_rows)
             WHEN h.held_n < h.min_group_rows THEN FORMAT(
               'the held group is too small: %d held of the %d needed (the band has %d let through, enough).',
               h.held_n, h.min_group_rows, h.band_n)
             ELSE FORMAT(
               'the band is too small: %d let through in the band of the %d needed (the held group has %d, enough).',
               h.band_n, h.min_group_rows, h.held_n)
           END,
           FORMAT(' Both groups are read under the rule of the latest plan night (%t): a last day of at least %gx the bar with at least %d order(s) earns the hold. Of the held, %d turned out not good once settled; of the band (let through with a last day between %gx and %gx the bar, the keyword-nights a lower threshold would have held), %d turned out good.%s %d more decision(s) are written and not yet settled. Nothing changes.',
                  h.rule_as_of, h.rule_mult, h.rule_min, h.held_wrong_n, h.band_low_x_bar, h.rule_mult,
                  h.band_wrong, h.tail, h.written - h.graded))
         WHEN h.hint_rec = 'NO_CLEAN_SIGNAL' THEN FORMAT(
           'NO CLEAN SIGNAL from %d held and %d let through in the band, under the %gx rule of the latest plan night (%t): of the %d held, %d turned out not good once settled ($%.2f of settled spend protected that should not have been), AND of the %d let through with a last day between %gx and %gx the bar, %d turned out good ($%.2f of settled spend on keywords the guard should have held). Moving the %gx threshold either way fixes one side and worsens the other; read the GUARD rows week by week.%s Nothing changes until Ori rules.',
           h.held_n, h.band_n, h.rule_mult, h.rule_as_of, h.held_n, h.held_wrong_n, h.hw_sp,
           h.band_n, h.band_low_x_bar, h.rule_mult, h.band_wrong, h.band_wrong_sp, h.rule_mult, h.tail)
         WHEN h.hint_rec = 'LOWER_STRONG_DAY_MULT' THEN FORMAT(
           'THE LAST-DAY BAR LOOKS TOO HIGH from %d keyword-nights let through because their last day sold at %gx to %gx the bar, under the rule of the latest plan night (%t): %d of them turned out good once their window settled ($%.2f of settled spend on keywords the guard should have held). A lower strong_day_mult would have held them. Held under the same rule: %d, of which %d turned out not good.%s Nothing changes until Ori rules.',
           h.band_n, h.band_low_x_bar, h.rule_mult, h.rule_as_of, h.band_wrong, h.band_wrong_sp,
           h.held_n, h.held_wrong_n, h.tail)
         WHEN h.hint_rec = 'RAISE_STRONG_DAY_MULT' THEN FORMAT(
           'THE LAST-DAY BAR LOOKS TOO LOW from %d keyword-nights held on the good side by a last day of %gx the bar or better, under the rule of the latest plan night (%t): %d of them turned out not good once their window settled ($%.2f of settled spend protected that should not have been). A higher strong_day_mult would have let them through. Of the %d let through with a last day between %gx and %gx the bar, %d turned out good.%s Nothing changes until Ori rules.',
           h.held_n, h.rule_mult, h.rule_as_of, h.held_wrong_n, h.hw_sp,
           h.band_n, h.band_low_x_bar, h.rule_mult, h.band_wrong, h.tail)
         ELSE FORMAT(
           'THE LAST-DAY BAR HOLDS from %d held and %d let through in the band, under the rule of the latest plan night (%t): of the %d held, %d turned out not good; of the %d let through with a last day between %gx and %gx the bar, %d turned out good. Keep strong_day_mult at %g.%s',
           h.held_n, h.band_n, h.rule_as_of, h.held_n, h.held_wrong_n,
           h.band_n, h.band_low_x_bar, h.rule_mult, h.band_wrong, h.rule_mult, h.tail)
       END
FROM hint h
