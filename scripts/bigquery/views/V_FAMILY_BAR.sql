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
--     NOT A LIVE CLAMP, and that follows from the declared constants rather than from a reading:
--     with credit 0.5 and floor 0.60 the floor can bite ONLY above halo 7/3, because
--     1/(1+0.5*(h-1)) < 0.60 exactly when h > 2.3333. Whether any row is near that today is a
--     MEASUREMENT and is not written here (Standing Rule 0 — this bullet used to pin all six bars).
--     Rows that WOULD clamp exist elsewhere in V_FAMILY_PNL, on early partial sales months with
--     enormous halos, but this view reads period_label = 'M3' and nothing else, so those rows are a
--     counterfactual and not a clamp. Run the re-check, and NOTE THE TOLERANCE — 5e-5, NOT 1e-9.
--     That is not arbitrary and it is not a fudge: the SELECT below ROUNDs keyword_bar to 4
--     decimals, so a published bar sits up to 5e-5 ABOVE its own unrounded value on any row where
--     rounding went up. At 1e-9 that ordinary rounding reads as a clamp on every such row — a query
--     published here at 1e-9 once returned a non-zero count directly under a sentence saying no row
--     clamps. At 5e-5, half of the 1e-4 rounding grid, only a real clamp can trip it.
--       SELECT COUNTIF(keyword_bar > 1.0/(1.0+0.5*(halo_factor-1.0)) + 5e-5) AS rows_clamped,
--              MIN(keyword_bar) AS lowest_bar, COUNT(*) AS n
--       FROM `onyga-482313.OI.V_FAMILY_BAR`;
--     Expect rows_clamped = 0 for as long as every M3 halo stays under 7/3.
--   · where halo_factor <= 1.0 NO credit is given and the bar stays 1.0. WHICH FAMILIES SIT ON THAT
--     BRANCH IS A MEASUREMENT AND MOVES WITH THE WINDOW — read it off the view, and always name the
--     window you read it on. That distinction is not pedantry: a halo below 1.0 on the
--     BASELINE_MAY_JUL window (which this view NEVER reads) was once quoted here as if it were the
--     M3 halo, and a reviewer spot-checking it found a credited bar on a family the header called
--     uncredited and had every reason to think the guard was broken. The sub-1.0 halos are real,
--     they are a COGS-imputation artifact rather than a negative halo (spec §9.1), and they DO
--     appear on other windows of V_FAMILY_PNL — which is exactly why the branch exists and stays.
--     It is a guard against a window this view does not read, not a description of today.
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
-- of those is the COGS, NEVER the bar and never halo_credit. The calibration query is published
-- below; its counts deliberately are not.
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
-- gate anything on it: V_FAMILY_PNL restates for about D+3, rows sit within a percent of the 1.000
-- truth test, and the running-month rows are still filling. An earlier version of this paragraph
-- pinned an agree/conservative/permissive split with no query, no stated scope and no warning; a
-- reviewer re-measuring it the next day got a different conservative count and correctly filed the
-- pinned figure as false. RUN THIS. DO NOT QUOTE A COUNT YOU DID NOT JUST PRODUCE:
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
-- SCOPE IS PART OF THE ANSWER AND MUST BE STATED — run it BOTH ways (all rows, and again with
-- "WHERE is_complete_period" to drop the still-filling running-month rows) and say which one you
-- are quoting. Quoting a conservative count without naming its scope is how the last pinned figure
-- went wrong.
-- THE COUNTS ARE DELIBERATELY NOT WRITTEN DOWN HERE. They were, twice, and both times they went
-- stale faster than the document — two independent re-runs of the query above on the SAME DAY, with
-- no code change between them, returned different splits. That is the knife edge below doing
-- exactly what it says it will do. Do not gate anything on one.
-- The one structural fact worth carrying is the ALGEBRA above, not a count: a PERMISSIVE row is
-- reachable only at halo < 1. When you run the query, check that every PERMISSIVE row it returns
-- satisfies that — if one ever does not, the bridge, not the COGS, is what broke.
--
-- WHAT IS STABLE IS THE DIRECTION, NOT THE COUNT: a CONSERVATIVE break (fails bar, clears truth)
-- means the engine under-spends and is harmless; a PERMISSIVE break (clears bar, fails truth) is
-- the only kind that says the bridge is miscalibrated, and the algebra above shows it is reachable
-- only at halo < 1. So a monitor alarms on PERMISSIVE only. One that alarms on any disagreement
-- fires on a majority of harmless rows and will be ignored inside a week.
-- THE KNIFE EDGE IS STRUCTURAL, AND IT IS THE REASON THE COUNT IS NOT WRITTEN DOWN. A family whose
-- total_net_roas sits a fraction under 1.000 while its ads_net_roas sits well under its bar is one
-- restatement away from flipping the M3 window from zero CONSERVATIVE breaks to one, with nothing
-- wrong and nothing to fix — and ad spend and sales restate for about D+3, so it can happen
-- intraday. Check whether such a family exists before you wire any monitor:
--   SELECT family, total_net_roas, ads_net_roas, keyword_bar
--   FROM `onyga-482313.OI.V_FAMILY_BAR` WHERE total_net_roas < 1.0 ORDER BY total_net_roas DESC;
-- Anyone wiring a monitor must count PERMISSIVE breaks only, or a restatement halts work on a
-- non-defect.
-- AND DO NOT REACH FOR THE KNOB. The only tunable that makes a conservative break disappear is
-- raising halo_credit above 0.5, which lowers EVERY Harvest bar at once and would let the engine
-- bid up across families the truth test does not clear. A conservative break is not something to
-- tune away; it is the safety margin doing its job.
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
