-- =============================================
-- V_FAMILY_BAR — the engine bridge: measured halo -> per-family keyword bar (2026-08-19).
-- Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md §4.
--
-- ADJUST THE BAR, NEVER THE MEASUREMENT. Organic sales are measurable at family grain and NOT
-- attributable to a keyword. So the engine keeps measuring ads-attributed GP-ROAS at keyword grain —
-- the only honest measure available there — and what changes is the BAR it is judged against, set
-- once per family from that family's MEASURED halo. Mathematically this is the same as inflating
-- every keyword's ROAS, but it keeps the measured number true, puts the adjustment in exactly one
-- auditable place per family, and never invents a per-keyword organic figure that does not exist.
--
--   keyword_bar = 1 / (1 + credit * (halo_factor - 1)),  credit = 0.5
--
-- WHY 0.5: crediting ALL organic to ads is wrong (brand search and repeat buyers would happen
-- anyway); crediting NONE is the pre-2026-08-19 behaviour and is why the engine undervalued
-- rank-building. Half is the conservative middle. It is a declared tunable in the k CTE, not a
-- buried constant.
--
-- SAFETY PROPERTIES, each asserted in the acceptance test:
--   · the credit can only LOWER a bar, never raise one above 1.0 — it can never justify a cut
--   · the bar is FLOORED at 0.60 — no halo excuses a catastrophic keyword. THE FLOOR IS A GUARD,
--     NOT A LIVE CLAMP, AND SAYING OTHERWISE WAS A DEFECT (corrected 2026-08-20): on the window
--     this view actually reads, NO ROW CLAMPS. Re-measured 2026-08-20 the six M3 bars are 0.7769,
--     0.8012, 0.8293, 0.8780, 0.9302, 0.9362 — the lowest sits 0.18 above the floor, and the raw
--     unclamped bar equals the published bar on all six. The floor bites only above halo 7/3
--     (1/(1+0.5*(h-1)) < 0.60  <=>  h > 2.3333), and no family's M3 halo is near that. Rows that
--     WOULD clamp do exist elsewhere in V_FAMILY_PNL — 5 of its 84 (family, period) rows on
--     2026-08-20, up to halo 30.18 on Bunny's first partial sales month — but this view reads
--     period_label = 'M3' and nothing else, so those rows are a counterfactual, not a clamp.
--     Re-run before quoting either number:
--       SELECT COUNTIF(keyword_bar > 1.0/(1.0+0.5*(halo_factor-1.0)) + 1e-9) AS rows_clamped,
--              MIN(keyword_bar) AS lowest_bar
--       FROM `onyga-482313.OI.V_FAMILY_BAR`;
--   · where halo_factor <= 1.0 NO credit is given and the bar stays 1.0. NO FAMILY IS ON THAT
--     BRANCH TODAY (measured 2026-08-20 on the window this view actually reads): the lowest M3 halo
--     is Fresh at 1.14, and every one of the six families is credited. An earlier version of this
--     bullet cited "LolliBall reads 0.87 today" — 0.87 is LolliBall's BASELINE_MAY_JUL halo, a
--     window this view NEVER reads, and on M3 LolliBall reads 1.15 and is credited like the rest.
--     A reviewer spot-checking the bullet found a credited bar on a family the header called
--     below 1.0 and had every reason to think the guard was broken. The sub-1.0 halos are real, they
--     are a COGS-imputation artifact rather than a negative halo (spec §9.1), and they DO appear on
--     other windows of V_FAMILY_PNL — which is exactly why the branch exists and stays. It is a
--     guard against a window this view does not read today, not a description of today.
--   · INVEST families are exempt entirely; they are governed by budget + trajectory, not by a bar
--
-- WINDOW AND CADENCE (corrected 2026-08-19 — the header used to say MONTHLY and the deployment is
-- DAILY; the deployment is right and the comment was wrong). The halo is read from V_FAMILY_PNL's
-- settled 90-day M3 window and SP_SNAPSHOT_FAMILY_BAR materialises this view DAILY inside the
-- orchestrator. That is safe, and the original "monthly" instinct was over-cautious: the fear was
-- bids chasing organic noise, but a 90-day settled window moves by roughly one day in ninety per
-- rebuild, so a daily refresh moves a bar by roughly a ninetieth of a day's data. That bounds the
-- ORDINARY case and it is not an absolute (qualified 2026-08-20): a restatement or a COGS change
-- that rewrites 90 days at once moves the halo, and therefore the bar, as far as it likes. What is
-- guaranteed is only the direction — the credit can never raise a bar above 1.0. Daily also removes
-- a second scheduler and keeps the bars in the same transaction-of-thought as the engines that will
-- read them. Read
-- computed_on if you need to know how fresh a bar actually is.
--
-- CALIBRATION IS A STANDING TEST, NOT A ONE-OFF, AND IT RUNS IN ONE DIRECTION ONLY: a family that
-- CLEARS its keyword bar must also clear total net ROAS 1.0. THE REVERSE IS NOT REQUIRED — a family
-- can fail its bar while clearing 1.0, and that is the bar being STRICTER than the truth, which is
-- the direction we want. It is not a defect and must never be alarmed on. Only a PERMISSIVE break
-- (clears the bar, fails 1.0) says the bridge is miscalibrated, and the algebra below shows it is
-- reachable only where halo < 1 — today, the COGS tier imputation on new products. The fix for one
-- of those is the COGS, NEVER the bar and never halo_credit. See the measured counts below.
-- =============================================
-- ── WHAT THE BAR TEST ACTUALLY IS, ALGEBRAICALLY (proved in review, 2026-08-19) ─────────────
-- V_FAMILY_PNL defines halo_factor = (sales-cogs)/ads_gross_profit, which over a shared ad_cost
-- denominator is exactly total_net_roas / ads_net_roas. Substitute that into the bar test:
--     ads >= 1 / (1 + 0.5*(total/ads - 1))
--  => ads + 0.5*(total - ads) >= 1
--  => (ads + total) / 2 >= 1
-- SO THE BAR TEST IS THE ARITHMETIC MEAN of the two ROAS measures against 1.0. The 0.5 credit
-- literally means "judge the family on the midpoint between what ads earned and what everything
-- earned". That is a feature, and it makes the safety direction PROVABLE rather than hopeful:
--   · when the halo is REAL (>1, i.e. total > ads) the mean sits BELOW total, so the bar is
--     STRICTER than the truth test. It can never be more permissive. This is the conservative
--     direction we want, guaranteed by algebra rather than by luck.
--   · a PERMISSIVE disagreement (clears the bar, fails total >= 1.0) is therefore only reachable
--     when halo < 1 — total profit BELOW ads-attributed profit, which is not physically sensible
--     and today means the COGS tier imputation on new products. The fix for that is the COGS, never
--     the bar.
-- CONSEQUENCE FOR THE STANDING CALIBRATION CHECK: agreement between the bar and total_net_roas is
-- a DATA COINCIDENCE on any given window, not an identity.
--
-- THE SPLIT BELOW IS A READING, NOT A CONSTANT. Do not treat it as a pinned expectation and do not
-- gate anything on it: V_FAMILY_PNL restates for about D+3, several rows sit within a percent of
-- the 1.000 truth test, and the running-month rows are still filling. An earlier version of this
-- paragraph pinned "73 agree, 10 disagree — 8 CONSERVATIVE and 2 PERMISSIVE" with no query, no
-- stated scope and no warning; a reviewer re-measuring it the next day got a different conservative
-- count and correctly filed the pinned figure as false. RE-RUN THIS BEFORE QUOTING ANY OF IT:
--
--   WITH k AS (SELECT 0.5 AS halo_credit, 0.60 AS bar_floor, 1.0 AS bar_ceiling),
--   b AS (
--     SELECT p.family, p.period_label, p.is_complete_period, p.ads_net_roas, p.total_net_roas,
--       CASE WHEN p.halo_factor IS NULL OR p.halo_factor <= 1.0 THEN k.bar_ceiling
--            ELSE GREATEST(k.bar_floor, LEAST(k.bar_ceiling,
--                 1.0 / (1.0 + k.halo_credit * (p.halo_factor - 1.0)))) END AS keyword_bar
--     FROM `onyga-482313.OI.V_FAMILY_PNL` p CROSS JOIN k)
--   SELECT COUNT(*) rows_scanned,
--     COUNTIF(ads_net_roas IS NULL OR total_net_roas IS NULL) unjudgeable,
--     COUNTIF(ads_net_roas IS NOT NULL AND total_net_roas IS NOT NULL
--             AND (ads_net_roas >= keyword_bar) = (total_net_roas >= 1.0)) agree,
--     COUNTIF(ads_net_roas IS NOT NULL AND total_net_roas IS NOT NULL
--             AND ads_net_roas <  keyword_bar AND total_net_roas >= 1.0) conservative,
--     COUNTIF(ads_net_roas IS NOT NULL AND total_net_roas IS NOT NULL
--             AND ads_net_roas >= keyword_bar AND total_net_roas <  1.0) permissive
--   FROM b;                       -- add "WHERE is_complete_period" for the complete-periods scope
--
-- SCOPE IS PART OF THE ANSWER AND MUST BE STATED. Run 2026-08-20, both scopes, same query:
--   · ALL 84 (family, period) rows, INCLUDING the six still-filling MTD rows:
--       84 scanned, 1 unjudgeable (LolliBall 2026-05, both ROAS NULL), 73 agree,
--       8 CONSERVATIVE, 2 PERMISSIVE. One of the eight — Fresh MTD — IS a still-filling row.
--   · COMPLETE PERIODS ONLY (WHERE is_complete_period, the six MTD rows dropped):
--       78 scanned, 1 unjudgeable, 68 agree, 7 CONSERVATIVE, 2 PERMISSIVE.
-- Quoting a conservative count without saying which scope produced it is how the last pinned
-- figure went wrong. The two PERMISSIVE rows are Fresh 2025-08 and Fresh 2025-10, both halo < 1,
-- and they are the same two under either scope.
--
-- WHAT IS STABLE IS THE DIRECTION, NOT THE COUNT: a CONSERVATIVE break (fails bar, clears truth)
-- means the engine under-spends and is harmless; a PERMISSIVE break (clears bar, fails truth) is
-- the only kind that says the bridge is miscalibrated, and the algebra above shows it is reachable
-- only at halo < 1. So a monitor alarms on PERMISSIVE only. One that alarms on any disagreement
-- fires on a majority of harmless rows and will be ignored inside a week.
-- KNIFE EDGE, AND IT IS LOADED RIGHT NOW: Bottle's M3 total_net_roas is 0.998 (re-measured
-- 2026-08-20) — 0.2% under the truth test, while its ads_net_roas 0.63 is well under its bar 0.78.
-- Ad spend and sales restate for about D+3. A routine restatement lifting Bottle past 1.000 turns
-- today's clean 0 breaks on the M3 window into 1 CONSERVATIVE break, with nothing wrong and nothing
-- to fix. Anyone wiring a monitor must count PERMISSIVE breaks only, or a restatement will halt
-- work on a non-defect.
-- AND DO NOT REACH FOR THE KNOB. The only tunable that makes a conservative break disappear is
-- raising halo_credit above 0.5, which lowers EVERY Harvest bar at once and would let the engine
-- bid up across four families that the truth test does not clear. A conservative break is not
-- something to tune away; it is the safety margin doing its job.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_FAMILY_BAR`
OPTIONS (
  description = "THE ENGINE BRIDGE (two-book P&L, 2026-08-19; description added 2026-08-20 — this view carried none, so the reasoning was invisible to anyone reading the warehouse). One row per family: that family's MEASURED organic halo turned into the bar the keyword engine judges ads-attributed GP-ROAS against. ADJUST THE BAR, NEVER THE MEASUREMENT — organic sales are measurable at family grain and are not attributable to a keyword, so the engine keeps measuring the only honest keyword-grain number and what moves is the bar. keyword_bar = 1 / (1 + credit * (halo_factor - 1)), credit = 0.5, a declared tunable in the k CTE. Algebraically the test is the ARITHMETIC MEAN of ads_net_roas and total_net_roas against 1.0, which is what makes the safety direction provable: where the halo is real (>1) the bar is STRICTER than a plain total-net-ROAS 1.0 test, never more permissive. Guards: the credit can only lower a bar, never raise one above 1.0, so it can never justify a cut; the bar is floored at 0.60; halo <= 1.0 gets no credit at all; INVEST families carry bar_exempt = TRUE and are judged on budget and trajectory instead. CALIBRATION IS ONE-DIRECTIONAL: clearing the bar must imply clearing total net ROAS 1.0; the reverse does NOT hold and a family failing its bar while clearing 1.0 is the conservative direction working, not a defect. Alarm only on PERMISSIVE breaks (clears bar, fails 1.0), which are reachable only where halo < 1 — the COGS tier imputation on new products — and the fix for one of those is the COGS, never the bar and never halo_credit. WINDOW AND CADENCE: reads V_FAMILY_PNL period_label = 'M3', the settled 90 complete days; SP_SNAPSHOT_FAMILY_BAR materialises it into T_FAMILY_BAR DAILY inside the orchestrator (task 20.5g-1). Daily is safe because a settled 90-day window moves about one day in ninety per rebuild, so the bar cannot chase noise. computed_on tells you how fresh a row is. NOTHING READS T_FAMILY_BAR YET — the bid engines are built to be able to join it (Task 8), and that wiring is not done. DO NOT PIN FIGURES HERE: bars move with the halo. Pull the view. Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md §4."
)
AS
WITH k AS (
  SELECT
    0.5  AS halo_credit,   -- fraction of the measured halo we credit to ads (Ori tunable)
    0.60 AS bar_floor,     -- no halo excuses a keyword below this
    1.0  AS bar_ceiling    -- the credit may only ever lower a bar
),
p AS (
  SELECT family, total_net_roas, ads_net_roas, halo_factor, net_profit, organic_pct
  FROM `onyga-482313.OI.V_FAMILY_PNL`
  WHERE period_label = 'M3'          -- settled 90 complete days
)
SELECT
  p.family,
  b.book,
  p.halo_factor,
  p.total_net_roas,
  p.ads_net_roas,
  p.net_profit,
  p.organic_pct,
  -- the bar itself: no credit when the measured factor is <= 1.0, floored, never above 1.0
  ROUND(
    GREATEST(
      LEAST(
        IF(COALESCE(p.halo_factor, 0) > 1.0,
           SAFE_DIVIDE(1.0, 1.0 + k.halo_credit * (p.halo_factor - 1.0)),
           k.bar_ceiling),
        k.bar_ceiling),
      k.bar_floor)
  , 4)                                                                        AS keyword_bar,
  k.halo_credit,
  (b.book = 'INVEST')                                                         AS bar_exempt,
  CURRENT_DATE('America/Los_Angeles')                                         AS computed_on
FROM p
CROSS JOIN k
LEFT JOIN `onyga-482313.OI.V_BOOK_ASSIGNMENT` b ON b.family = p.family;
