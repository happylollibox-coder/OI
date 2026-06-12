-- =============================================
-- V_PPC_ACTION_OUTCOMES — Outcome scoring for applied PPC changes
-- =============================================
-- One row per change_id from FACT_PPC_CHANGE_LOG (last 180 days).
-- Compares a 14-day pre window vs a 14-day post window of
-- spend / orders / net ROAS from FACT_AMAZON_ADS at the scope that
-- matches the action (term / target / campaign), and emits a verdict:
--   IMPROVED / WORSE / NO_DATA / TOO_EARLY
--
-- Windows (LA-local dates; change day itself excluded):
--   change_date  = DATE(applied_at, 'America/Los_Angeles')
--   pre          = [change_date-14, change_date-1]
--   post         = [change_date+1, LEAST(change_date+14, data_cutoff)]
--   data_cutoff  = CURRENT_DATE(LA) - 2  (ads attribution lag)
--
-- Net ROAS mirrors V_ADS_COACH_DATA (direct ad-attributed, no halo):
--   margin_per_unit = listing_price - latest TOTAL_COST_PER_UNIT
--   net_roas        = margin_per_unit * units / spend
-- Do NOT swap in Cube's UnifiedPerformance Net ROAS here — verdicts
-- must use the same metric that fired the coach threshold.
--
-- Verdict rules: see architecture/PPC_CLOSE_THE_LOOP.md (SOP).
-- Note: NEGATE/PAUSE verdicts judge the decision premise (pre-window
-- profitability) since the negated entity has no post data by design.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PPC_ACTION_OUTCOMES` AS
WITH

-- Unit economics per ASIN (same as V_ADS_COACH_DATA.asin_economics)
asin_economics AS (
  SELECT
    p.asin,
    COALESCE(ch.TOTAL_COST_PER_UNIT, 0) AS total_cost_per_unit,
    p.listing_price_amount - COALESCE(ch.TOTAL_COST_PER_UNIT, 0) AS margin_per_unit
  FROM `onyga-482313.OI.DIM_PRODUCT` p
  LEFT JOIN (
    SELECT asin, TOTAL_COST_PER_UNIT,
      ROW_NUMBER() OVER (PARTITION BY asin ORDER BY end_date DESC NULLS FIRST) AS rn
    FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  ) ch ON ch.asin = p.asin AND ch.rn = 1
),

changes AS (
  SELECT
    c.change_id,
    c.batch_id,
    c.applied_at,
    DATE(c.applied_at, 'America/Los_Angeles') AS change_date,
    c.action,
    c.search_term,
    c.targeting,
    c.keyword_id,
    c.match_type,
    c.campaign_id,
    c.campaign_name,
    c.campaign_type,
    c.ad_group_id,
    c.product,
    c.old_bid, c.new_bid, c.old_budget, c.new_budget,
    c.target_spend_8w, c.target_orders_8w, c.target_net_roas_8w,
    c.coach_mode,
    c.source,
    c.expected_impact_weekly,
    c.expected_impact_kind,
    CASE
      WHEN c.action LIKE 'NEGATE%' OR c.action IN ('STOP_TERM', 'STOP', 'SWITCH_HERO') THEN 'NEGATE'
      WHEN c.action = 'STOP_TARGET' THEN 'PAUSE_TARGET'
      WHEN c.action = 'REDUCE_BID' THEN 'BID_DOWN'
      WHEN c.action IN ('INCREASE_BID', 'BOOST', 'SCALE_UP') THEN 'BID_UP'
      WHEN c.action LIKE 'PROMOTE%' OR c.action IN ('START_TERM', 'START') THEN 'PROMOTE'
      WHEN c.action LIKE '%BUDGET%' THEN
        CASE WHEN c.action LIKE '%INCREASE%' THEN 'BUDGET_UP' ELSE 'BUDGET_DOWN' END
      ELSE 'OTHER'
    END AS action_group
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` c
  WHERE DATE(c.applied_at, 'America/Los_Angeles')
        >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 180 DAY)
),

-- FACT rows joined to each change at the action's scope, bucketed pre/post.
-- Static 200-day bound keeps partition pruning effective.
scoped AS (
  SELECT
    ch.change_id,
    CASE
      WHEN fa.date <  ch.change_date THEN 'PRE'
      WHEN fa.date >  ch.change_date
       AND fa.date <= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 2 DAY) THEN 'POST'
    END AS bucket,
    fa.Ads_cost AS spend,
    fa.Ads_orders AS orders,
    fa.Ads_units AS units,
    fa.Ads_sales AS sales,
    -- Coach margin semantics with the coach's own fallback
    COALESCE(
      ae.margin_per_unit,
      SAFE_DIVIDE(fa.Ads_sales, NULLIF(fa.Ads_orders, 0)) - COALESCE(ae.total_cost_per_unit, 0)
    ) * fa.Ads_units AS net_profit_contrib
  FROM changes ch
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
    ON fa.date BETWEEN DATE_SUB(ch.change_date, INTERVAL 14 DAY)
                   AND DATE_ADD(ch.change_date, INTERVAL 14 DAY)
   AND (
     -- Term scope within campaign: negates / stop-term
     (ch.action_group IN ('NEGATE')
        AND fa.campaign_id = ch.campaign_id
        AND LOWER(fa.search_term) = LOWER(COALESCE(ch.search_term, ch.targeting)))
     -- Target (keyword) scope within campaign: bid changes / pause target.
     -- Prefer the exact Amazon keyword_id; fall back to targeting text.
     OR (ch.action_group IN ('PAUSE_TARGET', 'BID_DOWN', 'BID_UP')
        AND fa.campaign_id = ch.campaign_id
        AND CASE
              WHEN ch.keyword_id IS NOT NULL AND ch.keyword_id != ''
                THEN fa.keyword_id = ch.keyword_id
              ELSE LOWER(fa.targeting) = LOWER(COALESCE(ch.targeting, ch.search_term))
            END)
     -- Term scope across ALL campaigns: promotes create new campaigns
     OR (ch.action_group = 'PROMOTE'
        AND LOWER(fa.search_term) = LOWER(ch.search_term))
     -- Campaign scope: budget changes and everything else
     OR (ch.action_group IN ('BUDGET_UP', 'BUDGET_DOWN', 'OTHER')
        AND fa.campaign_id = ch.campaign_id)
   )
  LEFT JOIN asin_economics ae
    ON ae.asin = COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME)
  WHERE fa.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 200 DAY)
),

windows AS (
  SELECT
    change_id,
    -- Pre window (always 14 days)
    SUM(IF(bucket = 'PRE', spend, 0))  AS pre_spend,
    SUM(IF(bucket = 'PRE', orders, 0)) AS pre_orders,
    SUM(IF(bucket = 'PRE', units, 0))  AS pre_units,
    SUM(IF(bucket = 'PRE', sales, 0))  AS pre_sales,
    SUM(IF(bucket = 'PRE', net_profit_contrib, 0)) AS pre_margin,
    COUNTIF(bucket = 'PRE')  AS pre_rows,
    -- Post window (may be partial — normalize via post_days_elapsed)
    SUM(IF(bucket = 'POST', spend, 0))  AS post_spend,
    SUM(IF(bucket = 'POST', orders, 0)) AS post_orders,
    SUM(IF(bucket = 'POST', units, 0))  AS post_units,
    SUM(IF(bucket = 'POST', sales, 0))  AS post_sales,
    SUM(IF(bucket = 'POST', net_profit_contrib, 0)) AS post_margin,
    COUNTIF(bucket = 'POST') AS post_rows
  FROM scoped
  WHERE bucket IS NOT NULL
  GROUP BY change_id
),

scored AS (
  SELECT
    ch.*,
    GREATEST(DATE_DIFF(
      LEAST(DATE_ADD(ch.change_date, INTERVAL 14 DAY),
            DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 2 DAY)),
      ch.change_date, DAY), 0) AS post_days_elapsed,
    COALESCE(w.pre_spend, 0)  AS pre_spend,
    COALESCE(w.pre_orders, 0) AS pre_orders,
    COALESCE(w.pre_units, 0)  AS pre_units,
    COALESCE(w.pre_sales, 0)  AS pre_sales,
    COALESCE(w.pre_rows, 0)   AS pre_rows,
    COALESCE(w.post_spend, 0)  AS post_spend,
    COALESCE(w.post_orders, 0) AS post_orders,
    COALESCE(w.post_units, 0)  AS post_units,
    COALESCE(w.post_sales, 0)  AS post_sales,
    COALESCE(w.post_rows, 0)   AS post_rows,
    ROUND(SAFE_DIVIDE(w.pre_margin,  NULLIF(w.pre_spend, 0)), 2)  AS pre_net_roas,
    ROUND(SAFE_DIVIDE(w.post_margin, NULLIF(w.post_spend, 0)), 2) AS post_net_roas,
    ROUND(COALESCE(w.pre_margin, 0)  - COALESCE(w.pre_spend, 0), 2)  AS pre_net_profit,
    ROUND(COALESCE(w.post_margin, 0) - COALESCE(w.post_spend, 0), 2) AS post_net_profit,
    ROUND(COALESCE(w.pre_spend, 0) / 14, 2)  AS pre_spend_per_day,
    ROUND(COALESCE(w.pre_orders, 0) / 14, 2) AS pre_orders_per_day
  FROM changes ch
  LEFT JOIN windows w USING (change_id)
)

SELECT
  s.* EXCEPT (pre_rows, post_rows),
  ROUND(SAFE_DIVIDE(s.post_spend,  NULLIF(s.post_days_elapsed, 0)), 2) AS post_spend_per_day,
  ROUND(SAFE_DIVIDE(s.post_orders, NULLIF(s.post_days_elapsed, 0)), 2) AS post_orders_per_day,
  -- "saved $Y/wk" for negate-style actions: the pre-window weekly burn rate
  ROUND(s.pre_spend / 14 * 7, 2) AS weekly_savings,
  ROUND(COALESCE(s.post_net_roas, 0) - COALESCE(s.pre_net_roas, 0), 2) AS net_roas_delta,
  CASE
    -- Not enough post-window signal yet (full confidence at 14 days)
    WHEN s.post_days_elapsed < 7 THEN 'TOO_EARLY'
    -- Nothing matched in either window / promoted keyword never went live
    WHEN s.pre_rows = 0 AND s.post_rows = 0 THEN 'NO_DATA'
    WHEN s.action_group = 'PROMOTE' AND s.post_spend = 0 THEN 'NO_DATA'

    -- Negate / pause: did we cut losing spend? (premise check — see SOP)
    WHEN s.action_group IN ('NEGATE', 'PAUSE_TARGET') THEN
      CASE WHEN s.pre_orders = 0 OR COALESCE(s.pre_net_roas, 0) < 1.0
           THEN 'IMPROVED' ELSE 'WORSE' END

    -- Bid down / budget down / other: efficiency must not degrade
    WHEN s.action_group IN ('BID_DOWN', 'BUDGET_DOWN', 'OTHER') THEN
      CASE WHEN COALESCE(s.post_net_roas, 0) >= COALESCE(s.pre_net_roas, 0)
           THEN 'IMPROVED' ELSE 'WORSE' END

    -- Bid up / budget up: more volume, efficiency may dip at most 20%
    WHEN s.action_group IN ('BID_UP', 'BUDGET_UP') THEN
      CASE WHEN SAFE_DIVIDE(s.post_orders, NULLIF(s.post_days_elapsed, 0))
                  >= s.pre_orders / 14
             AND COALESCE(s.post_net_roas, 0) >= COALESCE(s.pre_net_roas, 0) * 0.8
           THEN 'IMPROVED' ELSE 'WORSE' END

    -- Promote: must produce profitable volume
    WHEN s.action_group = 'PROMOTE' THEN
      CASE WHEN SAFE_DIVIDE(s.post_orders, NULLIF(s.post_days_elapsed, 0))
                  > s.pre_orders / 14
             AND COALESCE(s.post_net_roas, 0) >= 1.0
           THEN 'IMPROVED' ELSE 'WORSE' END

    ELSE 'NO_DATA'
  END AS verdict,

  -- ── Target-vs-actual grading ─────────────────────────────────────
  -- actual_weekly_impact:
  --   kind='save': pre-window weekly spend rate (same as weekly_savings; spend
  --     that disappears after negating / pausing is the realised saving).
  --   kind='earn': post-window weekly net-profit rate.
  --     net_profit = margin_per_unit*units − spend (captured in post_net_profit
  --     which = post_margin − post_spend).  Normalised to 7 days.
  --   NULL when target is absent.
  --
  --  Earn proxy reasoning: the view does not have a standalone weekly-revenue
  --  KPI, but it does compute post_net_profit (post_margin − post_spend) which
  --  mirrors coach net-profit semantics.  Weekly rate = post_net_profit /
  --  post_days_elapsed * 7.  This is the closest sound measure for "are we
  --  earning the expected $/wk" without inventing new data.
  CASE
    WHEN s.expected_impact_kind = 'save'
      THEN ROUND(s.pre_spend / 14 * 7, 2)
    WHEN s.expected_impact_kind = 'earn'
      -- post_net_profit = post_margin − post_spend (computed in scored CTE)
      -- Weekly rate: post_net_profit / post_days_elapsed * 7
      THEN ROUND(SAFE_DIVIDE(s.post_net_profit, NULLIF(s.post_days_elapsed, 0)) * 7, 2)
    ELSE NULL
  END AS actual_weekly_impact,

  CASE
    WHEN s.expected_impact_weekly IS NULL THEN 'NO_TARGET'
    WHEN s.post_days_elapsed < 7          THEN 'TOO_EARLY'
    WHEN s.expected_impact_kind = 'save'
      THEN IF(ROUND(s.pre_spend / 14 * 7, 2) >= s.expected_impact_weekly * 0.8,
              'TARGET_MET', 'BELOW_TARGET')
    WHEN s.expected_impact_kind = 'earn'
      -- actual weekly net-profit rate >= 80% of target
      THEN IF(
        SAFE_DIVIDE(s.post_net_profit, NULLIF(s.post_days_elapsed, 0)) * 7
              >= s.expected_impact_weekly * 0.8,
        'TARGET_MET', 'BELOW_TARGET')
    ELSE 'NO_TARGET'
  END AS target_status

FROM scored s;
