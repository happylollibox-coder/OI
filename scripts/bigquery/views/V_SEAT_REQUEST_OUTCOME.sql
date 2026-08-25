CREATE OR REPLACE VIEW `onyga-482313.OI.V_SEAT_REQUEST_OUTCOME`
OPTIONS (description = "§6.0's closing half — the Brain grades the other two layers against its OWN record. Plan step 6. Ori 2026-08-25: 'report if the catalog and pacing performed like expected... by doing so we can examine what need to get better.' One row per PROMISE — (plan, campaign, keyword, clicks_due_date) — not per nightly ask, because the plan re-asks every night and the promise is the thing that gets kept or broken. Three grades, each on a different layer and each REFUSING to answer early: PACING is graded on whether the CLICKS ARRIVED, not on whether the bid moved (a bid that moved perfectly and bought 3 of 40 clicks has failed); the CATALOG is graded on whether the return it claimed held, and stays PENDING_SETTLE until the settle window has passed because judging an unsettled window marks the Catalog down for sales that simply have not landed yet; the CAMPAIGN is graded on days at or over budget during the promise, target zero, because out-of-budget time is the one mechanism that makes a correct seat and a correct bid deliver nothing — and a non-zero reading is a BRAIN fault under §3.0 step 3, not a Pacing one. Reads FACT_SEAT_REQUEST, FACT_AMAZON_ADS and the campaign budget history (forward-filled, because that source records changes and not days). NOTHING HERE DECIDES ANYTHING and it can move no bid, budget or pause. Acceptance: scripts/bigquery/tests/SEAT_REQUEST_OUTCOME_acceptance.sql. Spec: architecture/THREE_LAYERS.md §6.0, §3.0.")
AS
WITH
-- THE PROMISE, not the nightly ask. The plan re-asks every night until the verdict date; what was
-- promised is one thing per (subject, due date), and it is the LAST ask that stands — an earlier,
-- different number was amended, not broken. times_asked and ask_changed are published because an
-- ask that keeps moving is itself a finding (§6.0), and a view that collapsed silently would hide it.
promise AS (
  SELECT
    plan, is_live_plan, family, campaign_id, campaign_name, keyword_id, ad_group_id,
    target_text, match_type, channel, clicks_due_date,
    MIN(requested_on)                                   AS first_asked_on,
    MAX(requested_on)                                   AS last_asked_on,
    COUNT(*)                                            AS times_asked,
    COUNT(DISTINCT clicks_requested) > 1                AS ask_changed,
    ARRAY_AGG(clicks_requested   ORDER BY requested_on DESC LIMIT 1)[SAFE_OFFSET(0)] AS clicks_requested,
    ARRAY_AGG(expected_cpc       ORDER BY requested_on DESC LIMIT 1)[SAFE_OFFSET(0)] AS expected_cpc,
    ARRAY_AGG(implied_daily_spend ORDER BY requested_on DESC LIMIT 1)[SAFE_OFFSET(0)] AS implied_daily_spend,
    ARRAY_AGG(request_basis      ORDER BY requested_on DESC LIMIT 1)[SAFE_OFFSET(0)] AS request_basis,
    ARRAY_AGG(seat_no            ORDER BY requested_on DESC LIMIT 1)[SAFE_OFFSET(0)] AS seat_no,
    ARRAY_AGG(holdout            ORDER BY requested_on DESC LIMIT 1)[SAFE_OFFSET(0)] AS holdout,
    -- THE CATALOG'S CLAIM, taken from the ask that stands. This is what the Catalog is graded on.
    ARRAY_AGG(ret_corrected      ORDER BY requested_on DESC LIMIT 1)[SAFE_OFFSET(0)] AS claimed_return,
    ARRAY_AGG(family_bar         ORDER BY requested_on DESC LIMIT 1)[SAFE_OFFSET(0)] AS family_bar,
    ARRAY_AGG(ladder_state       ORDER BY requested_on DESC LIMIT 1)[SAFE_OFFSET(0)] AS ladder_state,
    ARRAY_AGG(verdict            ORDER BY requested_on DESC LIMIT 1)[SAFE_OFFSET(0)] AS verdict,
    ARRAY_AGG(current_bid        ORDER BY requested_on DESC LIMIT 1)[SAFE_OFFSET(0)] AS bid_at_request,
    ARRAY_AGG(planned_bid        ORDER BY requested_on DESC LIMIT 1)[SAFE_OFFSET(0)] AS bid_planned,
    ARRAY_AGG(campaign_current_budget ORDER BY requested_on DESC LIMIT 1)[SAFE_OFFSET(0)] AS budget_at_request
  FROM `onyga-482313.OI.FACT_SEAT_REQUEST`
  GROUP BY plan, is_live_plan, family, campaign_id, campaign_name, keyword_id, ad_group_id,
           target_text, match_type, channel, clicks_due_date
),
wm AS (SELECT MAX(date) AS watermark FROM `onyga-482313.OI.FACT_AMAZON_ADS`),

-- WHAT ACTUALLY ARRIVED, over the promise's own span: from the first day it was asked for to the
-- day it was due. Keyed on campaign_id AND targeting because FACT_AMAZON_ADS carries no keyword id
-- — and on campaign_id rather than campaign_name, because 53 ids in this account carry more than
-- one name (violation 23) and a name join would silently mix two campaigns' delivery.
delivered AS (
  SELECT
    p.plan, p.campaign_id, p.keyword_id, p.clicks_due_date,
    SUM(a.Ads_clicks)      AS clicks_delivered,
    SUM(a.Ads_cost)        AS spend_actual,
    SUM(a.Ads_orders)      AS orders_actual,
    SUM(a.Ads_sales)       AS sales_actual,
    SUM(a.GROSS_PROFIT)    AS gp_actual,
    COUNT(DISTINCT a.date) AS days_with_spend
  FROM promise p
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` a
    ON CAST(a.campaign_id AS STRING) = p.campaign_id
   AND LOWER(TRIM(a.targeting)) = LOWER(TRIM(p.target_text))
   AND a.date BETWEEN p.first_asked_on AND p.clicks_due_date
  GROUP BY 1,2,3,4
),

-- THE CAMPAIGN'S BUDGET, FORWARD-FILLED. campaign_history records CHANGES, not days, so a campaign
-- with no row on a date still had a budget — the last one it was given. Reading the raw table per
-- day would score a campaign as budgetless on every quiet day it spent money.
-- The fill is a WINDOW FUNCTION over a spine of every day the campaign spent, unioned with the days
-- its budget changed. The first shape used a correlated subquery in a join predicate ("the last
-- change on or before this day") and BigQuery refuses that outright — which is the better outcome,
-- because the window form is also the one that reads correctly on a campaign whose budget never
-- changed inside the window.
span AS (SELECT MIN(first_asked_on) AS from_d, MAX(clicks_due_date) AS to_d FROM promise),
campaign_spend AS (
  SELECT CAST(a.campaign_id AS STRING) AS campaign_id, a.date AS d, SUM(a.Ads_cost) AS spend
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a CROSS JOIN span sp
  WHERE a.date BETWEEN sp.from_d AND sp.to_d AND a.campaign_id IS NOT NULL
  GROUP BY 1,2
),
budget_spine AS (
  SELECT campaign_id, d, MAX(daily_budget) AS daily_budget FROM (
    SELECT CAST(h.campaign_id AS STRING) AS campaign_id, DATE(h.date) AS d, h.daily_budget
    FROM `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` h CROSS JOIN span sp
    WHERE h.daily_budget IS NOT NULL AND DATE(h.date) <= sp.to_d
    UNION ALL
    SELECT campaign_id, d, CAST(NULL AS FLOAT64) FROM campaign_spend
  ) GROUP BY 1,2
),
budget_ff AS (
  SELECT campaign_id, d,
         LAST_VALUE(daily_budget IGNORE NULLS) OVER (
           PARTITION BY campaign_id ORDER BY d
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS daily_budget
  FROM budget_spine
),
oob AS (
  SELECT
    p.plan, p.campaign_id, p.keyword_id, p.clicks_due_date,
    COUNT(*)                                    AS days_measured,
    -- "SPEND >= BUDGET" IS THE SIGNAL, not a dark-hours clock. The clock misses SB overdelivery,
    -- where a campaign spends PAST its ceiling instead of stopping; both shapes mean the money ran
    -- out before the day did.
    COUNTIF(cs.spend >= b.daily_budget - 0.005) AS days_at_or_over_budget
  FROM promise p
  JOIN campaign_spend cs
    ON cs.campaign_id = p.campaign_id
   AND cs.d BETWEEN p.first_asked_on AND p.clicks_due_date
  JOIN budget_ff b ON b.campaign_id = cs.campaign_id AND b.d = cs.d
  WHERE b.daily_budget IS NOT NULL
  GROUP BY 1,2,3,4
),

graded AS (
  SELECT
    p.*,
    w.watermark,
    COALESCE(d.clicks_delivered, 0) AS clicks_delivered,
    d.spend_actual, d.orders_actual, d.sales_actual, d.gp_actual, d.days_with_spend,
    o.days_measured, COALESCE(o.days_at_or_over_budget, 0) AS days_at_or_over_budget,
    SAFE_DIVIDE(d.spend_actual, NULLIF(d.clicks_delivered, 0))         AS cpc_actual,
    SAFE_DIVIDE(d.gp_actual, NULLIF(d.spend_actual, 0))                AS return_actual,
    SAFE_DIVIDE(COALESCE(d.clicks_delivered, 0), NULLIF(p.clicks_requested, 0)) AS delivery_ratio,
    -- SETTLE DISCIPLINE. SP sales accrue for 7 days, SB for 14. A window judged before it has
    -- settled marks the Catalog down for sales that have not landed yet, which is the opposite of
    -- a fair grade.
    IF(UPPER(p.channel) = 'SB', 14, 7)                                  AS settle_days,
    DATE_ADD(p.clicks_due_date, INTERVAL IF(UPPER(p.channel) = 'SB', 14, 7) DAY) AS settles_on
  FROM promise p
  CROSS JOIN wm w
  LEFT JOIN delivered d USING (plan, campaign_id, keyword_id, clicks_due_date)
  LEFT JOIN oob       o USING (plan, campaign_id, keyword_id, clicks_due_date)
)
SELECT
  plan, is_live_plan, family, campaign_id, campaign_name, keyword_id, target_text, match_type,
  channel, seat_no, holdout,
  first_asked_on, last_asked_on, clicks_due_date, times_asked, ask_changed, request_basis,
  clicks_requested, ROUND(expected_cpc, 4) AS expected_cpc,
  ROUND(implied_daily_spend, 4) AS implied_daily_spend,
  clicks_delivered, ROUND(cpc_actual, 4) AS cpc_actual,
  ROUND(spend_actual, 2) AS spend_actual, orders_actual,
  ROUND(delivery_ratio, 4) AS delivery_ratio,
  ROUND(claimed_return, 4) AS claimed_return, ROUND(return_actual, 4) AS return_actual,
  ROUND(family_bar, 4) AS family_bar, ladder_state, verdict,
  bid_at_request, bid_planned, budget_at_request,
  days_measured, days_at_or_over_budget,
  ROUND(SAFE_DIVIDE(days_at_or_over_budget, NULLIF(days_measured, 0)), 4) AS pct_days_capped,
  settles_on, watermark,

  -- ---- PACING: DID THE CLICKS ARRIVE? Not "did the bid move" (§6.0). --------------------------
  CASE
    WHEN clicks_due_date > watermark               THEN 'PENDING'
    WHEN clicks_requested IS NULL                  THEN 'NO_REQUEST'
    WHEN delivery_ratio >= 0.90                    THEN 'DELIVERED'
    WHEN delivery_ratio >= 0.50                    THEN 'SHORT'
    ELSE                                                'MISSED'
  END AS pacing_grade,

  -- ---- CATALOG: DID THE CLAIM HOLD? Refuses to answer until the window has settled. -----------
  CASE
    WHEN clicks_due_date > watermark               THEN 'PENDING'
    WHEN settles_on > watermark                    THEN 'PENDING_SETTLE'
    WHEN claimed_return IS NULL                    THEN 'NO_CLAIM'
    WHEN COALESCE(clicks_delivered, 0) = 0         THEN 'UNTESTED'
    WHEN return_actual >= family_bar               THEN 'HELD'
    WHEN return_actual >= family_bar * 0.75        THEN 'SHORT_OF_CLAIM'
    ELSE                                                'BROKE'
  END AS catalog_grade,

  -- ---- CAMPAIGN: was the answer buyable at all? Target zero (§3.0 step 3, violation 29). ------
  CASE
    WHEN clicks_due_date > watermark               THEN 'PENDING'
    WHEN days_measured IS NULL                     THEN 'NO_BUDGET_HISTORY'
    WHEN days_at_or_over_budget = 0                THEN 'CARRIED'
    WHEN SAFE_DIVIDE(days_at_or_over_budget, days_measured) <= 0.25 THEN 'TIGHT'
    ELSE                                                'STARVED'
  END AS campaign_grade,

  -- A plain sentence, in the shape §9 requires: what was asked, what arrived, and who owns the gap.
  CASE WHEN clicks_due_date > watermark THEN FORMAT(
    'PENDING — the Brain asked for %d clicks on %t by %t and the window is still open (ads data reaches %t). %d clicks so far.',
    clicks_requested, first_asked_on, clicks_due_date, watermark, COALESCE(clicks_delivered, 0))
  ELSE FORMAT(
    'Asked for %d clicks by %t; %d arrived (%.0f%%) at $%.2f against $%.2f expected. Campaign was at or over budget on %d of %d days. The Catalog claimed %.2f against a %.2f bar and the window returned %.2f.',
    clicks_requested, clicks_due_date, COALESCE(clicks_delivered, 0),
    100 * COALESCE(delivery_ratio, 0), COALESCE(cpc_actual, 0), COALESCE(expected_cpc, 0),
    COALESCE(days_at_or_over_budget, 0), COALESCE(days_measured, 0),
    COALESCE(claimed_return, 0), COALESCE(family_bar, 0), COALESCE(return_actual, 0))
  END AS sentence
FROM graded;
