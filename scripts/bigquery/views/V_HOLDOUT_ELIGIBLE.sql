-- =============================================
-- V_HOLDOUT_ELIGIBLE — who is allowed into the randomized holdout trial, and the frozen facts
-- the randomization blocks on. Spec: architecture/HOLDOUT.md.
--
-- GRAIN: one row per ENABLED campaign that clears every eligibility rule below. 69 rows on the
-- assignment date 2026-08-19 — the exact population the design was powered on. Trial 2 (holdout
-- restart, plan docs/superpowers/plans/2026-10-03-holdout-restart.md §2.4): 59 rows on its design
-- date 2026-10-03 (FACT anchor 2026-10-02) under the re-graded stock literal of exclusion 4.
--
-- DEPLOY ORDER (plan Task 4, review fix 3): this view's trial-2 literal deploys AFTER
-- SP_ASSIGN_HOLDOUT's live-trial body, never before. Under trial 1's procedure the literal makes the
-- 5 Bunny campaigns eligible, and its next run appends them to trial 1 for good. See the header of
-- procedures/SP_ASSIGN_HOLDOUT.sql.
--
-- WHY A TRIAL AT ALL (measured 2026-08-18, all numbers real). We tried to answer Ori's question
-- ("the main goal of ads is to make more total dollars than we would without the changes") with
-- matched difference-in-differences and PROVED it untrustworthy on this account:
--   · SELECTION PLACEBO, FATAL. Emulate the engine's selection (rank by trailing-14d dollars),
--     then do NOTHING: +$1,505..+$2,445 on the losers arm (+3.9..+7.1 sd) and -$1,094..-$1,829 on
--     the winners arm, over four independent no-upload dates. The account's true 14-day net is
--     about -$2,500..-$2,730, so the artifact is ~90% of the entire quantity being measured.
--   · NO CONTROL EXISTS. 73.5% of active keywords and 85.1% of ad dollars are touched. The clean
--     untouched pool clearing 10 clicks in both windows is SEVEN keywords / $819, against 379
--     treated keywords / $29,326. Matching fails for 98.1% of treated keywords, and 120 of 161
--     untouched keywords are not even in FACT_KEYWORD_STATE. The untouched arm is untouched
--     BECAUSE it is dying (-83% clicks over the window).
-- There is no control to find, so we CREATE one by randomization. Ori: "start the holdout."
--
-- WHY THE UNIT IS THE CAMPAIGN, not the keyword — this is the decisive constraint, and Ori's own
-- low-stock doctrine already states it: "in a CAPPED campaign the budget is spent regardless, so
-- removing a target does not return money — it RE-ROUTES it to the neighbours." Holding out
-- keyword A inside a budget-capped campaign hands A's forgone impressions and budget to its
-- TREATED neighbours in the same campaign. The arms interfere, the treated arm is flattered, and
-- the trial measures reallocation as if it were skill (a SUTVA violation). A whole-campaign arm
-- has zero within-campaign spillover by construction and CAPTURES that reallocation inside the
-- unit instead of being fooled by it. Family clustering would remove even the cross-campaign
-- leak but leaves 5 clusters / 3 degrees of freedom and an MDE of 32% of the spend under test —
-- statistically dead. See architecture/HOLDOUT.md for the full unit comparison.
--
-- ── THE FIVE EXCLUSIONS, and why each ────────────────────────────────────────────────────────
--  1. NOT ENABLED / not serving. Nothing to measure.
--  2. ZERO ad spend in the trailing 28 days (3 campaigns). Enabled but dormant: contributes a
--     budget line and no outcome. Holding one out measures nothing and adds a zero to the noise.
--  3. BRAND DEFENSE (7 campaigns, $764/28d). Doctrine already forbids the engine moving defense
--     bids (V_CAMPAIGN_CAP_STATE: "ownership never moves a defense campaign's bids"). They are
--     therefore untreated in BOTH arms — pure noise, no signal.
--  4. CRITICAL-STOCK FAMILIES, graded on each trial's design date: trial 1 (2026-08-18) Bunny and
--     LolliBall (14 campaigns, $5,496/28d); trial 2 (2026-10-03) LolliBall only. Holding these out
--     costs INVENTORY, not dollars: a holdout campaign cannot be throttled when the family runs
--     dry, so the trial would spend down stock it cannot replace. The list is a FROZEN LITERAL,
--     deliberately — see the note on the exclusion below.
--  5. Nothing else. Two exclusions were CONSIDERED AND REJECTED and the rejection matters:
--     · forecast-THROTTLE families (Fresh, LolliME, Lollibox): excluding them removes $25,192 of
--       the $32,637 spending base and leaves 6 campaigns. There is no trial left. Instead the
--       CENSORING RULE is pre-committed in HOLDOUT.md: a family entering ACTUAL CRITICAL mid-trial
--       is censored from BOTH arms from that date forward, symmetric across strata, and the
--       readout reports the truncated window. Pulling only the holdout campaign would be a
--       treatment-correlated dropout and would reintroduce the exact selection artifact the
--       design exists to eliminate.
--     · launch-phase campaigns (V_LAUNCH_POPULATION): they are 52 of the 69 and 33.1% of eligible
--       dollars. Excluding them leaves 17 clusters and kills cluster randomization outright.
--       MITIGATION instead: launch status is a randomization STRATUM and is FROZEN at the
--       assignment date, so a campaign the launch controller promotes out mid-trial stays in its
--       original stratum and its original arm (intention-to-treat).
--
-- ── THE BLOCKING FACTS (published here, frozen into DE_HOLDOUT_ASSIGNMENT at assignment) ──────
-- channel (SP vs SB — SB is 46% of account spend, a different data path and a different lag),
-- is_capped (V_CAMPAIGN_CAP_STATE.is_oob_owned; capped campaigns carry ~1.5x the residual sd,
-- $121 vs $83), is_launch (V_LAUNCH_POPULATION membership), family (V_CAMPAIGN_FAMILY_MAP —
-- controls organic halo and stock exposure), and spend_28d (size, THE dominant variance driver:
-- the top-1 campaign is 11.2% and the top-10 are 54.5% of eligible dollars). Size is blocked
-- inside each stratum by the within-stratum spend ordering the assignment SP applies — see
-- SP_ASSIGN_HOLDOUT.
--
-- PLANNER DOCTRINE: this view reads V_CAMPAIGN_CAP_STATE and V_LAUNCH_POPULATION, which are not
-- cheap. It is read by EXACTLY ONE consumer, SP_ASSIGN_HOLDOUT, once per pass. Every hot consumer —
-- the engines, the preflight gate, the readout — reads the TABLE DE_HOLDOUT_ASSIGNMENT (or
-- V_HOLDOUT_ARM over it), never this view. Same doctrine as FACT_PANEL_OWNERSHIP / FACT_KEYWORD_GUARD.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_HOLDOUT_ELIGIBLE` AS
WITH
-- the complete-days anchor, the same one every ads engine uses
wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
       FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
-- exclusion 1 + 3: enabled and serving, and not brand defense. is_defense is spelled exactly as
-- V_CAMPAIGN_CAP_STATE spells it so the two populations can never drift apart on this predicate.
camp AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id,
         campaign_name,
         campaign_type AS channel,
         daily_budget AS budget_now
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT`
  WHERE campaign_state = 'ENABLED'
    AND serving_status IN ('CAMPAIGN_STATUS_ENABLED', 'CAMPAIGN_OUT_OF_BUDGET', 'PENDING_START_DATE')
    AND NOT (LOWER(campaign_name) LIKE '%brand defense%')
),
-- SP money: spend AND gross profit, both from FACT_AMAZON_ADS.GROSS_PROFIT, the stored column —
-- THE GP RULE (V_CHANGE_SCORECARD header): read it, never recompute it.
sp28 AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id,
         SUM(Ads_cost) AS spend, SUM(GROSS_PROFIT) AS gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`, wm
  WHERE date BETWEEN DATE_SUB(wm.d, INTERVAL 27 DAY) AND wm.d
  GROUP BY 1
),
-- ONE MONEY SOURCE, BOTH CHANNELS. FACT_AMAZON_ADS carries SP and SB alike (34 SB campaigns /
-- $15,349 of 28-day cost on 2026-08-19), and cost and GROSS_PROFIT sit on the SAME rows there.
-- V_CAMPAIGN_CAP_STATE deliberately reads sb_campaign_report instead, because cap arithmetic must
-- compare spend to the budget Amazon itself enforced; a TRIAL has the opposite requirement — its
-- outcome is (GROSS_PROFIT - Ads_cost), and subtracting two differently-complete sources would put
-- a source artifact inside the very quantity being measured. So eligibility, size-blocking and
-- V_HOLDOUT_READOUT all read FACT and only FACT. Verified 2026-08-19: switching the SB spend
-- source does not move the population (69 either way) and does not move the chosen seed (14).
fam AS (SELECT CAST(campaign_id AS STRING) AS campaign_id, parent_name
        FROM `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP`),
cap AS (SELECT CAST(campaign_id AS STRING) AS campaign_id, is_oob_owned, days_capped_14d
        FROM `onyga-482313.OI.V_CAMPAIGN_CAP_STATE`),
lau AS (SELECT DISTINCT CAST(campaign_id AS STRING) AS campaign_id
        FROM `onyga-482313.OI.V_LAUNCH_POPULATION`)
SELECT
  c.campaign_id,
  c.campaign_name,
  c.channel,
  c.budget_now,
  COALESCE(f.parent_name, 'Unknown') AS family,
  ROUND(COALESCE(s.spend, 0), 2)                                AS spend_28d,
  ROUND(COALESCE(s.gp, 0), 2)                                   AS gp_28d,
  ROUND(COALESCE(s.gp, 0) - COALESCE(s.spend, 0), 2)            AS net_28d,
  COALESCE(cp.is_oob_owned, FALSE)  AS is_capped,
  COALESCE(cp.days_capped_14d, 0)   AS days_capped_14d,
  (l.campaign_id IS NOT NULL)       AS is_launch,
  -- THE STRATUM. Three categorical blocks; size is blocked INSIDE each by the spend ordering the
  -- assignment applies. Eight cells at most, which is the coarsest key that still separates the
  -- variance drivers the design named — a full five-way cross of 69 units would be almost all
  -- singletons, and a singleton stratum is not a block, it is a coin flip with extra steps.
  CONCAT(c.channel, '|',
         IF(COALESCE(cp.is_oob_owned, FALSE), 'CAP', 'UNC'), '|',
         IF(l.campaign_id IS NOT NULL, 'LNC', 'GRD')) AS stratum
FROM camp c
LEFT JOIN sp28 s  ON s.campaign_id  = c.campaign_id
LEFT JOIN fam  f  ON f.campaign_id  = c.campaign_id
LEFT JOIN cap  cp ON cp.campaign_id = c.campaign_id
LEFT JOIN lau  l  ON l.campaign_id  = c.campaign_id
WHERE
  -- exclusion 2: dormant. No spend in 28 days is no outcome to measure.
  COALESCE(s.spend, 0) > 0
  -- exclusion 4: CRITICAL-stock families, as graded on the design date. Trial 1, 2026-08-18: Bunny
  -- (21.7 days of cover) and LolliBall (33.7), so ('Bunny', 'LolliBall'). Trial 2, re-graded on its
  -- design date 2026-10-03 (V_LOW_STOCK_ADS, family row): Bunny OK (159.4 days binding cover, 6,000
  -- units arriving 10-07) and LolliBall CRITICAL (21.6 days), so ('LolliBall'). The same rule gives
  -- a new answer; it is not re-graded between design dates. THIS LIST IS A FROZEN LITERAL ON
  -- PURPOSE. Reading a live
  -- risk_state here would (a) drag V_LOW_STOCK_ADS — a view at BigQuery's planning ceiling —
  -- into this plan, which the planner doctrine forbids, and (b) let the trial's POPULATION drift
  -- with performance: a family that grades CRITICAL because it is selling well would silently
  -- leave the eligible set, which is a selection artifact of exactly the kind this whole design
  -- exists to kill. Families that grade CRITICAL *during* the trial are handled by the pre-
  -- committed censoring rule (symmetric, both arms), never by editing this list.
  AND COALESCE(f.parent_name, 'Unknown') NOT IN ('LolliBall')
;
