-- V_LAUNCH_OPTIMIZER: launch-phase tracking per new family × week (monthly-cockpit module).
--
-- WHY: launches have DIFFERENT GOALS than regular campaigns (Ori 2026-07-26). A launch is
-- judged on rank/velocity/organic compounding per phase — not on ads ROAS. This view is the
-- single source for "what phase am I in, am I on track, what budget, what bid" — the
-- cockpit displays it, the coacher reacts to it (phase-gated LAUNCH_TAPER).
--
-- PHASES (standard seller playbook, ratified 2026-07-26):
--   SETUP  wk 0-1   goal: reviews + CVR validation; modest discovery spend
--   RANK   wk 2-7   goal: velocity/badges/organic share; loss = launch investment
--                   (honeymoon window; NO loss-driven cuts — 2026-07-21 doctrine)
--   EXIT   wk 8-11  goal: taper bids to value, raise price/margin; keep what holds rank
--   POST   wk 12+   launch over: either graduated to the grid or stalled out
--
-- VERDICTS (complete weeks only): ON_TRACK units growing or organic share rising ·
-- BEHIND neither growing · STALLED (RANK+ only) units <= 90% of prior-3wk avg AND organic
-- flat — the "honeymoon expired, rank didn't stick" signature (Bunny, 2026-07).
--
-- value_per_click = trailing-28d family CVR × GP/order; taper_bid = 70% of it (floor 0.15).
-- weekly_budget_rec: SETUP ~ $70/wk · RANK ON_TRACK keep / BEHIND ×0.8 · STALLED ×0.3
-- (badge-defense floor) · EXIT ×0.7 per week. margin_flag warns when GP/order < $6 — at
-- that margin no bid can work; the fix is price/bundle, not ads (LolliBall $3.31).
--
-- Created 2026-07-26. Registered in config.yaml. See architecture/INTENT_CAMPAIGN_GRID.md.

CREATE OR REPLACE VIEW `onyga-482313.OI.V_LAUNCH_OPTIMIZER` AS
WITH fam AS (
  SELECT family, MIN(date) first_sale
  FROM `onyga-482313.OI.V_UNIFIED_DAILY`
  WHERE units > 0
  GROUP BY family
  HAVING MIN(date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
),
wk AS (
  SELECT u.family, f.first_sale, u.week_start_date wk,
    DATE_DIFF(u.week_start_date, DATE_TRUNC(f.first_sale, WEEK(SUNDAY)), WEEK) week_num,
    SUM(u.units) units,
    SUM(u.organic_units) organic_units,
    SUM(u.ad_cost) ad_cost,
    SUM(u.sales - u.cogs - u.ad_cost) np,
    SUM(u.ad_orders) ad_orders,
    SUM(u.clicks) clicks
  FROM `onyga-482313.OI.V_UNIFIED_DAILY` u
  JOIN fam f USING (family)
  WHERE u.date >= f.first_sale
  GROUP BY 1, 2, 3, 4
),
trail AS (
  SELECT u.family,
    SAFE_DIVIDE(SUM(u.ad_orders), NULLIF(SUM(u.clicks), 0)) cvr28,
    SAFE_DIVIDE(SUM(u.sales - u.cogs), NULLIF(SUM(u.orders), 0)) gp_per_order
  FROM `onyga-482313.OI.V_UNIFIED_DAILY` u
  JOIN fam USING (family)
  WHERE u.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
  GROUP BY 1
),
enriched AS (
  SELECT w.*,
    SAFE_DIVIDE(w.organic_units, NULLIF(w.units, 0)) org_share,
    AVG(w.units) OVER (PARTITION BY w.family ORDER BY w.wk
                       ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING) prior3_units,
    AVG(w.organic_units) OVER (PARTITION BY w.family ORDER BY w.wk
              ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING) prior3_org_units,
    AVG(w.ad_cost) OVER (PARTITION BY w.family ORDER BY w.wk
                         ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING) prev_ad_cost,
    w.wk < DATE_TRUNC(CURRENT_DATE("America/Los_Angeles"), WEEK(SUNDAY)) is_complete
  FROM wk w
)
SELECT
  e.family, e.first_sale, e.wk week_start, e.week_num,
  CASE WHEN e.week_num < 2 THEN 'SETUP'
       WHEN e.week_num < 8 THEN 'RANK'
       WHEN e.week_num < 12 THEN 'EXIT'
       ELSE 'POST' END phase,
  e.units, e.organic_units, ROUND(e.org_share, 3) org_share,
  ROUND(e.ad_cost, 0) ad_cost, ROUND(e.np, 0) np,
  ROUND(SAFE_DIVIDE(e.ad_orders, NULLIF(e.clicks, 0)), 4) ad_cvr,
  CASE
    WHEN NOT e.is_complete THEN NULL  -- partial week: no verdict
    WHEN e.week_num < 2 THEN 'SETUP'
    WHEN e.prior3_units IS NULL THEN 'ON_TRACK'
    WHEN e.units <= e.prior3_units * 0.9
         AND e.organic_units <= IFNULL(e.prior3_org_units, 0)
      THEN 'STALLED'  -- absolute organic units: share rises when ad units collapse
    WHEN e.units > e.prior3_units * 1.05
         OR e.organic_units > IFNULL(e.prior3_org_units, 0) * 1.1
      THEN 'ON_TRACK'
    ELSE 'BEHIND'
  END verdict,
  ROUND(t.cvr28 * t.gp_per_order, 2) value_per_click,
  GREATEST(0.15, ROUND(0.7 * t.cvr28 * t.gp_per_order, 2)) taper_bid,
  ROUND(t.gp_per_order, 2) gp_per_order,
  t.gp_per_order < 6 margin_flag,
  ROUND(CASE
    WHEN e.week_num < 2 THEN 70
    WHEN e.week_num >= 8 THEN IFNULL(e.prev_ad_cost, e.ad_cost) * 0.7
    WHEN e.units <= IFNULL(e.prior3_units, e.units) * 0.9
         AND e.organic_units <= IFNULL(e.prior3_org_units, 0)
      THEN IFNULL(e.prev_ad_cost, e.ad_cost) * 0.3
    WHEN e.units > IFNULL(e.prior3_units, 0) * 1.05
         OR e.organic_units > IFNULL(e.prior3_org_units, 0) * 1.1
      THEN IFNULL(e.prev_ad_cost, e.ad_cost)
    ELSE IFNULL(e.prev_ad_cost, e.ad_cost) * 0.8
  END, 0) weekly_budget_rec,
  CASE
    WHEN e.week_num < 2 THEN
      'SETUP: Vine/reviews first, coupon on, discovery autos at modest bids. Do not scale spend before ~20 reviews.'
    WHEN e.week_num < 8 AND (e.units > IFNULL(e.prior3_units, 0) * 1.05
         OR e.organic_units > IFNULL(e.prior3_org_units, 0) * 1.1) THEN
      'RANK on track: hold spend, chase badges (50+ per variant), no loss cuts - loss is the launch investment.'
    WHEN e.week_num < 8 THEN
      'RANK behind: concentrate budget on top variants and niche terms; check reviews/price before adding spend.'
    WHEN e.week_num < 12 THEN
      'EXIT: taper bids to taper_bid, raise price/bundle for margin, keep only keywords holding rank or paying.'
    ELSE
      'POST: launch window over - graduate winners to the grid, badge-defense floor on the rest.'
  END recommendation,
  e.is_complete
FROM enriched e
LEFT JOIN trail t USING (family);
