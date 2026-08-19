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
--   · the bar is FLOORED at 0.60 — no halo excuses a catastrophic keyword
--   · where halo_factor < 1.0 NO credit is given and the bar stays 1.0 (LolliBall reads 0.87 today,
--     which is a COGS-imputation artifact, not a real negative halo — see spec §9.1)
--   · INVEST families are exempt entirely; they are governed by budget + trajectory, not by a bar
--
-- WINDOW: the halo is read from V_FAMILY_PNL's settled 90-day period (M3) and this view is
-- materialised MONTHLY by SP_SNAPSHOT_FAMILY_BAR — bids must not chase organic noise day to day.
--
-- CALIBRATION IS A STANDING TEST, NOT A ONE-OFF: a family passing its keyword bar must also clear
-- total net ROAS 1.0. If that ever breaks, the bridge is miscalibrated and the credit is wrong.
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
-- a DATA COINCIDENCE on any given window, not an identity. Measured across all 84 (family, period)
-- rows of V_FAMILY_PNL: 10 disagree — 8 CONSERVATIVE (fails bar, clears truth = the engine
-- under-spends, harmless) and 2 PERMISSIVE, both on halo<1 rows. So only PERMISSIVE breaks are
-- defects. A monitor that alarms on any disagreement will cry wolf 8 times out of 10.
-- KNIFE EDGE TO KNOW ABOUT: Bottle's 90d total_net_roas is 0.998 — it fails the truth test by 0.2%,
-- so its agreement can flip on a small restatement without anything being wrong.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_FAMILY_BAR` AS
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
