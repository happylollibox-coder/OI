-- V_BUDGET_STEP1_CAMPAIGN — one row per ENABLED campaign for the Weekly Run per-family Step-1 Budget table.
-- The waterfall's per-campaign allocation (base_daily) + last-7-full-days performance, tiered by net ROAS
-- (WINNING >= boost, MARGIN >= margin, LOSING below) so the UI can group winning/margin/losing and order
-- each by spend desc. Ori reviews/edits each campaign's budget and queues it to the bulksheet.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_BUDGET_STEP1_CAMPAIGN` AS
WITH cfg AS (
  SELECT MAX(IF(config_key='margin_roas_threshold', config_value, NULL)) AS margin,
         MAX(IF(config_key='boost_roas_threshold',  config_value, NULL)) AS boost
  FROM `onyga-482313.OI.DE_BUDGET_CONFIG`),
wm AS (SELECT MAX(date) AS d FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` WHERE Performance_TYPE='Organic'),
perf AS (   -- per campaign over the 7 full days
  SELECT a.campaign_id,
    SUM(a.Ads_cost) AS spend7, SUM(a.Ads_clicks) AS clicks7,
    SUM(a.GROSS_PROFIT - a.Ads_cost) AS net7,
    SAFE_DIVIDE(SUM(a.GROSS_PROFIT), NULLIF(SUM(a.Ads_cost), 0)) AS net_roas
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a CROSS JOIN wm w
  WHERE a.date BETWEEN DATE_SUB(w.d, INTERVAL 6 DAY) AND w.d
  GROUP BY a.campaign_id
),
ramp AS (
  -- V_CAMPAIGN_LAUNCH_RAMP is (campaign x target) grain — roll to campaign grain FIRST or the join
  -- below fans each ramping campaign out into one row per target. The budget/day fields are campaign
  -- level and identical across a campaign's rows, so ANY_VALUE is exact, not a guess.
  SELECT campaign_id,
    ANY_VALUE(target_budget) AS target_budget,
    ANY_VALUE(day_of_ramp)   AS day_of_ramp,
    ANY_VALUE(ramp_days)     AS ramp_days
  FROM `onyga-482313.OI.V_CAMPAIGN_LAUNCH_RAMP`
  GROUP BY campaign_id
),
cur AS (   -- current Amazon name + type + daily budget + creation date (latest snapshot)
  SELECT campaign_id, campaign_name, campaign_type, daily_budget, DATE(creation_date) AS created
  FROM `onyga-482313.OI.DIM_CAMPAIGN`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY last_updated_date DESC) = 1
)
SELECT
  m.campaign_id, m.parent_name,
  COALESCE(cur.campaign_name, m.campaign_id) AS campaign_name,
  COALESCE(cur.campaign_type, 'SP')          AS campaign_type,
  -- NEW wins over the ROAS tiers: a campaign inside its launch-ramp grace has not earned a verdict yet.
  -- Judging it on 7d ROAS would tier a 2-day-old campaign as LOSING and cut it to the floor while the
  -- ramp is still finding its bid. Grace = launch_ramp_days (20), shared with V_CAMPAIGN_LAUNCH_RAMP.
  CASE WHEN r.campaign_id IS NOT NULL                THEN 'NEW'
       WHEN p.net_roas >= (SELECT boost FROM cfg)    THEN 'WINNING'
       WHEN p.net_roas >= (SELECT margin FROM cfg)   THEN 'MARGIN'
       ELSE 'LOSING' END AS tier,
  ROUND(p.net_roas, 2)              AS net_roas,
  ROUND(COALESCE(p.net7, 0) / 7, 2) AS net_profit_day,
  ROUND(COALESCE(p.spend7, 0) / 7, 2) AS spend_day,
  ROUND(SAFE_DIVIDE(p.spend7, p.clicks7), 2) AS last_cpc,
  ROUND(cur.daily_budget, 2)        AS current_budget,
  -- A ramping campaign's budget comes from the RAMP, not the waterfall — the ramp owns it for its first
  -- 20 days (Ori 2026-07-16), so the two can't fight over it.
  ROUND(COALESCE(r.target_budget, b.base_daily), 2) AS new_budget,
  r.day_of_ramp                     AS ramp_day,     -- NULL once mature; "day N of 20" in step 2
  r.ramp_days                       AS ramp_days,
  DATE_DIFF(CURRENT_DATE('America/New_York'), cur.created, DAY) AS age_days,
  -- Age buckets for the "Budget by age" section. >= boundaries so nothing falls between buckets.
  -- NEW (<=20d) is phase-1 controlled (V_LAUNCH_PHASE1); the rest are the normal waterfall/coacher.
  CASE
    WHEN cur.created IS NULL THEN 'UNKNOWN'
    WHEN DATE_DIFF(CURRENT_DATE('America/New_York'), cur.created, DAY) <= 20  THEN 'NEW'
    WHEN DATE_DIFF(CURRENT_DATE('America/New_York'), cur.created, DAY) <= 90  THEN '1-3MO'
    WHEN DATE_DIFF(CURRENT_DATE('America/New_York'), cur.created, DAY) <= 270 THEN '4-9MO'
    ELSE '10MO+' END               AS age_bucket,
  COALESCE(b.is_floor, FALSE)       AS is_floor,
  COALESCE(b.is_defense, FALSE)     AS is_defense,   -- back-compat: brand-defense pool
  COALESCE(b.role, 'OFFENSE')       AS role,         -- OFFENSE / BRAND_DEFENSE / PRODUCT_DEFENSE (PPC toggle)
  -- The Coverage role (AUTO / EXACT / BROAD / PHRASE / COMPETITOR / SB_VIDEO / *_DEFENSE) — the grain the
  -- step-1 strategy split groups by. Distinct from `role` above, which is only the 3-way PPC pool.
  COALESCE(cr.role, 'OTHER')        AS strategy_role,
  -- Strategy grain for the "Budget by strategy" split (cross-pool): AUTO / EXACT_BOOST / INTENT /
  -- COMPETITOR / BRAND_DEFENSE / PRODUCT_DEFENSE. Distinct from strategy_role (match-type coverage).
  COALESCE(cr.strategy_category, 'OTHER') AS strategy_category,
  COALESCE(h.est_halo_day, 0)       AS est_halo,     -- v2 role-weighted organic halo forecast (per day)
  ROUND(COALESCE(p.net7, 0) / 7 + COALESCE(h.est_halo_day, 0), 2) AS net_incl_halo   -- ad net profit + est halo
FROM `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` m
LEFT JOIN perf p           ON p.campaign_id = m.campaign_id
LEFT JOIN cur              ON cur.campaign_id = m.campaign_id
LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_BUDGET_BASE` b ON b.campaign_id = m.campaign_id
LEFT JOIN ramp r ON r.campaign_id = m.campaign_id
LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_ROLE` cr ON cr.campaign_id = m.campaign_id
LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_HALO` h ON h.campaign_id = m.campaign_id;
