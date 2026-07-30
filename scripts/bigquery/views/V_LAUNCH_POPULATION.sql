-- V_LAUNCH_POPULATION — THE single definition of "which campaigns the launch controller governs".
--
-- Ori 2026-07-24: the population is no longer AGE ("first 20 days") but BUDGET — a campaign is in the
-- launch / low-budget regime while its daily budget is at or below the low-budget cap:
--     PEAK (inside any gift-season boost→cooldown window)  → $30/day
--     OFF-SEASON                                            → $20/day
-- Rationale: age is an arbitrary clock; budget is a statement of how much you are willing to risk while
-- the campaign is still unproven. It also self-promotes — the launch controller RAISES budget on good
-- performance (see V_LAUNCH_PHASE1 budget ladder), and once the budget clears the cap the campaign
-- graduates to the working-campaign methodology (the coacher, V_ADS_COACH) on its own.
--
-- WHY THIS VIEW EXISTS: "new" was previously defined in three independent places (V_LAUNCH_PHASE1.camp,
-- V_ADS_COACH.is_new_campaign, V_WEEKLY_RUN_CAMPAIGN.age_bucket). They agreed only because all three used
-- the same age rule. Under a budget rule they would drift apart, and the dashboard would show a campaign
-- in BOTH the launch cards and the mature table (or neither). Every consumer must read THIS view.
--
-- HYSTERESIS (deliberate, prevents thrashing): membership requires the budget to have been at/below the cap
-- for the last 3 complete days (`budget_max_3d <= cap`), so
--   • PROMOTION is immediate — one day above the cap graduates the campaign to the working methodology;
--   • DEMOTION is slow — a working campaign whose budget dips under the cap for a day does NOT get yanked
--     back into launch mode. It must stay low for 3 consecutive days.
-- Without this a campaign could oscillate across the boundary every few days, flipping between two engines
-- with different cadences (launch = daily, working = weekly/3-day).
--
-- Grain: one row per ENABLED campaign currently governed by the launch controller.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_LAUNCH_POPULATION` AS
WITH
-- Anchor on the last COMPLETE ads day (same anchor the launch controller uses).
wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
       FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
-- Peak = today falls inside any gift-season window (boost → cooldown), matching how peak is defined
-- across the coacher. Prime-event windows count too: they behave like a gift season for budget.
season AS (
  SELECT COUNTIF(CURRENT_DATE('America/New_York') BETWEEN boost_start AND cooldown_end) > 0 AS in_peak
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
  WHERE category IN ('gift_season', 'prime_event')
),
-- Season-scaled budget-tier caps (Ori 2026-07-24): low = launch controller; medium/high classify the
-- graduated campaigns. Peak lifts every band. medium_budget_cap is exposed so V_WEEKLY_RUN_CAMPAIGN can
-- split MEDIUM vs HIGH from one source instead of re-deriving the season.
cap AS (
  SELECT in_peak,
    IF(in_peak, 30.0,  20.0) AS low_budget_cap,
    IF(in_peak, 100.0, 50.0) AS medium_budget_cap
  FROM season
),
-- Latest state AND serving_status per campaign. serving_status is Amazon's own verdict on whether the
-- campaign is actually eligible to serve — it catches ENDED / PENDING campaigns whose last STATE row still
-- says ENABLED because the change-log is event-based and the archive/end event never synced (Ori confirmed
-- the 4 BOX campaigns are archived, yet state=ENABLED / serving_status=ENDED). Keep only campaigns that can
-- serve now or are scheduled to; ENDED / PAUSED / ARCHIVED drop out even when state=ENABLED.
camp AS (
  SELECT campaign_id, created, campaign_name, state, serving_status FROM (
    SELECT CAST(campaign_id AS STRING) AS campaign_id, MIN(DATE(creation_date)) AS created,
      ARRAY_AGG(state ORDER BY date DESC LIMIT 1)[OFFSET(0)] AS state,
      ARRAY_AGG(campaign_name ORDER BY date DESC LIMIT 1)[OFFSET(0)] AS campaign_name,
      ARRAY_AGG(serving_status ORDER BY date DESC LIMIT 1)[OFFSET(0)] AS serving_status
    FROM `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` GROUP BY 1
  )
  WHERE state = 'ENABLED'
    -- CAMPAIGN_STATUS_ENABLED = serving · CAMPAIGN_OUT_OF_BUDGET = serving but capping (the real dark case)
    -- · PENDING_START_DATE = scheduled, will start soon (a new low-budget campaign, keep it). ENDED and
    -- the paused/archived statuses are excluded.
    AND serving_status IN ('CAMPAIGN_STATUS_ENABLED', 'CAMPAIGN_OUT_OF_BUDGET', 'PENDING_START_DATE')
),
-- Budget today + the 3-day max that drives the hysteresis.
bud AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id,
    MAX(IF(date = (SELECT d FROM wm), campaign_budget, NULL)) AS budget_today,
    MAX(campaign_budget) AS budget_max_3d
  FROM `onyga-482313.OI.V_TARGET_DAILY`
  WHERE date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 2 DAY) AND (SELECT d FROM wm)
  GROUP BY 1
)
SELECT
  c.campaign_id,
  c.campaign_name,
  c.created,
  DATE_DIFF((SELECT d FROM wm), c.created, DAY) AS age_days,
  b.budget_today,
  b.budget_max_3d,
  k.low_budget_cap,
  k.medium_budget_cap,
  k.in_peak,
  c.serving_status,
  -- Why this campaign is in the launch population — surfaced so the card can explain itself.
  IF(b.campaign_id IS NULL, 'no delivery yet (brand new)', 'budget at/below the low-budget cap') AS launch_reason
FROM camp c
CROSS JOIN cap k
LEFT JOIN bud b ON b.campaign_id = c.campaign_id
WHERE
  -- Normal case: budget has been at/below the cap for the last 3 complete days.
  -- `b.campaign_id IS NOT NULL` is load-bearing: without it a campaign with NO budget rows at all
  -- (long dormant, never delivered) would COALESCE to 0 and be swept in as "low budget" — that alone
  -- inflated the population from ~26 to 72. No data is NOT evidence of a low budget.
  (b.campaign_id IS NOT NULL AND b.budget_max_3d <= k.low_budget_cap)
  -- Brand-new campaign with no V_TARGET_DAILY rows yet (created today, nothing delivered): keep it in the
  -- launch population so it is coached from day 1 instead of falling into a gap between the two engines.
  OR (b.campaign_id IS NULL AND DATE_DIFF((SELECT d FROM wm), c.created, DAY) < 20)
;
