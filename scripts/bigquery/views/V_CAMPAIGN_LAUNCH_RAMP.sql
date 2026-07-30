-- V_CAMPAIGN_LAUNCH_RAMP — the launch protocol for a campaign's first `launch_ramp_days` (20) days.
-- Spec: architecture/CAMPAIGN_LAUNCH_RAMP.md. Replaces the LAUNCH_* branch of V_ADS_COACH.
--
-- THE RULE. A new campaign starts at $10.00/day and a $1.00 bid on every target. For each day `d` in
-- the window, ONLY IF AMAZON REPORTED THE CAMPAIGN OUT OF BUDGET that day:
--   * every target with clicks(d) > launch_click_trigger  → bid × (1 - launch_bid_cut_pct)
--   * if trailing-3d net ROAS ending d > launch_raise_roas → budget × (1 + launch_budget_raise_pct)
-- Day 21 the campaign leaves the ramp and the normal coacher takes over.
--
-- OUT OF BUDGET IS AMAZON'S VERDICT, NOT OURS (fixed 2026-07-17). This gated on spend(d) >= budget(d),
-- which was wrong three ways, all of them under-firing the ladder:
--   1. The last few percent of a budget are unspendable — Amazon stops serving when the remainder will
--      not cover another click, so a $10 campaign at ~$0.90 CPC goes out of budget at ~$9.40. On
--      2026-07-16 every campaign between 91% and 100% was out of budget per Amazon and "not maxed"
--      here: 8 of 14 out-of-budget days missed, a 57% false-negative rate.
--   2. campaign_budget is RESTATED, not historical — targeting_report carries the CURRENT budget on
--      every past row. ME-SP/AUTO (Pink) ran $10 on 07-15 and spent $10.55 (maxed), but the report
--      stamps 07-15 with the $26 it was raised to on 07-16 → $10.55 >= $26 is false. Since this view
--      REPLAYS history, one budget change silently rewrote the whole 20-day past.
--   3. Daily spend is not capped at daily budget — Amazon borrows against underspent days and reaches
--      ~2x budget, so `>=` is crossed trivially on catch-up days and missed on tight ones.
-- campaign_history.serving_status carries Amazon's own CAMPAIGN_OUT_OF_BUDGET, recorded at the time.
-- It needs no budget number, so it dissolves 2 and 3 along with 1. Spec: architecture doc, section
-- "Out of budget is Amazon's verdict, not ours".
--
-- WHY THIS IS A VIEW AND NOT A SCHEDULED JOB. Every condition reads OBSERVED history — that day's
-- spend, that day's clicks, that day's ROAS. Nothing is counterfactual, so the ladder can be replayed
-- from history on every read and is always current. The engine computes daily; Ori uploads when he
-- sits down and the bulksheet carries wherever the ladder has reached.
--
-- WHY THERE IS NO BID FLOOR. The ladder only steps down on a day the campaign spent its ENTIRE budget.
-- If bids fall far enough to starve delivery, the campaign stops filling its budget, the condition
-- stops firing, and the ladder arrests itself. A floor would be redundant.
--
-- V_TARGET_DAILY.campaign_budget is NOT the budget on day d (see bug 2 above). It no longer gates the
-- ladder; it survives only as the fallback for the ~7% of campaign-days Amazon gave us no status row
-- for, and to report current_budget.
--
-- GRAIN: one row per (campaign, target). A ramping campaign with no target rows yet (launched, no
-- spend) still emits ONE row with keyword_id = NULL so its budget recommendation is never lost.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_LAUNCH_RAMP` AS
WITH cfg AS (
  SELECT
    MAX(IF(config_key='launch_ramp_days',        config_value, NULL)) AS ramp_days,
    MAX(IF(config_key='launch_start_bid',        config_value, NULL)) AS start_bid,
    MAX(IF(config_key='campaign_launch_floor_daily', config_value, NULL)) AS start_budget,
    MAX(IF(config_key='launch_bid_cut_pct',      config_value, NULL)) AS bid_cut,
    MAX(IF(config_key='launch_click_trigger',    config_value, NULL)) AS click_trigger,
    MAX(IF(config_key='launch_budget_raise_pct', config_value, NULL)) AS bud_raise,
    MAX(IF(config_key='launch_raise_roas',       config_value, NULL)) AS raise_roas,
    MAX(IF(config_key='launch_raise_roas_days',  config_value, NULL)) AS roas_days
  FROM `onyga-482313.OI.DE_BUDGET_CONFIG`
),
-- Ads watermark: today's rows are still landing, so an incomplete day must not read as "not maxed".
wm AS (SELECT MAX(date) AS d FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
camp AS (
  SELECT campaign_id, created, campaign_name FROM (
    SELECT CAST(campaign_id AS STRING) AS campaign_id,
      MIN(DATE(creation_date)) AS created,
      ARRAY_AGG(state ORDER BY date DESC LIMIT 1)[OFFSET(0)] AS state,
      ARRAY_AGG(campaign_name ORDER BY date DESC LIMIT 1)[OFFSET(0)] AS campaign_name
    FROM `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` GROUP BY 1
  )
  WHERE state = 'ENABLED'
    AND DATE_DIFF((SELECT d FROM wm), created, DAY) < (SELECT CAST(ramp_days AS INT64) FROM cfg)
),
-- Day grain: spend + gross profit, bounded to the ramp window.
day_perf AS (
  SELECT c.campaign_id, a.date,
    SUM(a.Ads_cost)     AS spend,
    SUM(a.GROSS_PROFIT) AS gp
  FROM camp c
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` a ON CAST(a.campaign_id AS STRING) = c.campaign_id
  WHERE a.date >= c.created
    AND a.date <= (SELECT d FROM wm)
    AND DATE_DIFF(a.date, c.created, DAY) < (SELECT CAST(ramp_days AS INT64) FROM cfg)
  GROUP BY 1, 2
),
day_budget AS (   -- restated (see bug 2) — fallback gate + current_budget reporting only
  SELECT campaign_id, date, MAX(campaign_budget) AS budget
  FROM `onyga-482313.OI.V_TARGET_DAILY`
  GROUP BY 1, 2
),
-- Amazon's own out-of-budget verdict, per LA day. last_updated_date is Fivetran UTC: converting is
-- load-bearing, not cosmetic. Proud's first out-of-budget reads UTC 07-16 04:34 but is really LA
-- 07-15 21:34 — a different rung of the ladder. Fivetran writes on change, so a day may hold several
-- rows (ENABLED at the midnight reset, OUT_OF_BUDGET when the cap lands); ANY of them being
-- OUT_OF_BUDGET makes the day count.
-- Events via the unified V_SRC interface (SP∪SB), not raw fivetran (2026-07-30 rule: prefer the
-- consolidated layer; see architecture/CAMPAIGN_LAUNCH_RAMP.md §"Status source").
day_oob AS (
  SELECT campaign_id,
    DATE(date, 'America/Los_Angeles') AS date,
    LOGICAL_OR(serving_status = 'CAMPAIGN_OUT_OF_BUDGET') AS amazon_oob
  FROM `onyga-482313.OI.V_SRC_AmazonAds_campaign_history`
  GROUP BY 1, 2
),
day AS (
  SELECT p.campaign_id, p.date, p.spend, p.gp, b.budget,
    -- Amazon's verdict where we have one (93% of campaign-days); the old proxy only where the day has
    -- no status row at all. COALESCE, not OR: a row that says "serving" is an answer, not a gap.
    COALESCE(o.amazon_oob, b.budget IS NOT NULL AND p.spend >= b.budget) AS maxed,
    CAST(cfg.roas_days AS INT64) AS roas_days   -- carried as a column: BigQuery rejects a scalar
  FROM day_perf p                               -- subquery inside the join predicate below
  CROSS JOIN cfg
  LEFT JOIN day_budget b ON b.campaign_id = p.campaign_id AND b.date = p.date
  LEFT JOIN day_oob    o ON o.campaign_id = p.campaign_id AND o.date = p.date
),
-- Trailing net ROAS ending each day. Self-join rather than a window frame so the window length stays
-- config-driven (RANGE ... PRECEDING will not accept a non-literal).
day_roas AS (
  SELECT d.campaign_id, d.date, d.maxed, d.budget, d.spend,
    SAFE_DIVIDE(SUM(x.gp), NULLIF(SUM(x.spend), 0)) AS roas_trail
  FROM day d
  JOIN day x ON x.campaign_id = d.campaign_id
    AND x.date BETWEEN DATE_SUB(d.date, INTERVAL d.roas_days - 1 DAY) AND d.date
  GROUP BY d.campaign_id, d.date, d.maxed, d.budget, d.spend
),
budget_ladder AS (
  SELECT campaign_id,
    COUNTIF(maxed AND roas_trail > (SELECT raise_roas FROM cfg)) AS n_raise_days,
    COUNTIF(maxed) AS n_maxed_days,
    COUNT(*)       AS n_days_live
  FROM day_roas GROUP BY 1
),
bid_ladder AS (
  SELECT t.campaign_id, t.keyword_id,
    ANY_VALUE(t.ad_group_id)  AS ad_group_id,
    ANY_VALUE(t.target_text)  AS target_text,
    ANY_VALUE(t.target_type)  AS target_type,
    ANY_VALUE(t.match_type)   AS match_type,
    COUNTIF(d.maxed AND t.clicks > (SELECT click_trigger FROM cfg)) AS n_cut_days,
    ARRAY_AGG(t.keyword_bid IGNORE NULLS ORDER BY t.date DESC LIMIT 1)[SAFE_OFFSET(0)] AS current_bid
  FROM `onyga-482313.OI.V_TARGET_DAILY` t
  JOIN day_roas d ON d.campaign_id = t.campaign_id AND d.date = t.date
  GROUP BY 1, 2
)
SELECT
  c.campaign_id,
  c.campaign_name,
  c.created                        AS campaign_created,
  DATE_DIFF((SELECT d FROM wm), c.created, DAY) + 1 AS day_of_ramp,
  (SELECT CAST(ramp_days AS INT64) FROM cfg)        AS ramp_days,
  COALESCE(bl.n_days_live, 0)      AS n_days_live,
  COALESCE(bl.n_maxed_days, 0)     AS n_maxed_days,
  -- budget ladder (campaign grain, repeated on every target row)
  COALESCE(bl.n_raise_days, 0)     AS n_raise_days,
  ROUND((SELECT start_budget FROM cfg)
        * POW(1 + (SELECT bud_raise FROM cfg), COALESCE(bl.n_raise_days, 0)), 2) AS target_budget,
  (SELECT MAX(budget) FROM day_budget b WHERE b.campaign_id = c.campaign_id)     AS current_budget,
  -- bid ladder (target grain)
  t.keyword_id,
  t.ad_group_id,
  t.target_text,
  t.target_type,
  t.match_type,
  COALESCE(t.n_cut_days, 0)        AS n_cut_days,
  t.current_bid,
  -- THE LADDER MAY ONLY EVER CUT (fixed 2026-07-17). start_bid is a PRESCRIPTION for a campaign you
  -- launch at $1.00, but it was being applied as a retroactive ASSUMPTION about campaigns that started
  -- wherever Ori put them — real bids average $0.75. Uncapped, 52 of the 55 targets with a known bid
  -- would have been RAISED, +33% on average (worst: bunny plush $0.36 → $1.00), on campaigns that had
  -- burned $607 at 0.25-0.45x net ROAS. Capping at current_bid inverts nothing and cuts nothing extra.
  -- NULL current_bid = an auto group inheriting the ad-group default: fall back to start_bid, which is
  -- the one case the original formula had right.
  -- Known consequence: a target already below the ladder never moves. Correct for a "start at $1.00 and
  -- walk down" ramp; anchoring on each target's first observed bid instead is Ori's call, not taken here.
  IF(t.keyword_id IS NULL, NULL,
     ROUND(LEAST(
       (SELECT start_bid FROM cfg) * POW(1 - (SELECT bid_cut FROM cfg), COALESCE(t.n_cut_days, 0)),
       COALESCE(t.current_bid, (SELECT start_bid FROM cfg))
     ), 2))  AS target_bid
FROM camp c
LEFT JOIN budget_ladder bl ON bl.campaign_id = c.campaign_id
LEFT JOIN bid_ladder    t  ON t.campaign_id  = c.campaign_id;
