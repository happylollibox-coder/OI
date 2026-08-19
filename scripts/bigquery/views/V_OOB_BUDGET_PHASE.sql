-- V_OOB_BUDGET_PHASE — the "Out of budget" technical phase on the Weekly Run page.
-- Spec: architecture/OOB_BUDGET_PHASE.md.
--
-- ############################################################################
-- # v27.62 — THE GP RULE: READ FACT_AMAZON_ADS.GROSS_PROFIT. NEVER RECOMPUTE. #
-- ############################################################################
-- (Ori 2026-08-13, found by checking the panel against Amazon.) Every gross-profit number sourced
-- from FACT in this view is now the STORED FACT_AMAZON_ADS.GROSS_PROFIT column. The old formula
--     Ads_sales - COALESCE(T_PRICE_COST_TIER.tier_cost, TOTAL_COST_PER_UNIT) * Ads_units
--   LEFT JOIN T_PRICE_COST_TIER pct ON Ads_units > 0
--     AND pct.unit_price = ROUND(SAFE_DIVIDE(Ads_sales, Ads_units), 2)
-- and its join ARE GONE. The join looked the cost tier up by an "implied unit price" of
-- Ads_sales / Ads_units — which is NOT the product's price: Ads_sales carries HALO sales of OTHER
-- products (~79% purchased-vs-advertised divergence in this account) while Ads_units does not
-- correspond to them. PROVEN on VIDEO- BALL / 2026-08-12: implied $24.39 for a $13.99 product
-- matched a ~$21.50 tier, overrode the real TOTAL_COST_PER_UNIT of $9.77, and collapsed
-- GP $229.16 -> $37.17 — a GP-ROAS of 3.69x read as 0.60x, on a campaign Amazon's own console
-- reports at $331.08 sales / $64.05 spend that day. Arithmetic: 317.09 - 9.77 x 13 = 229.16 =
-- FACT.GROSS_PROFIT exactly. WHY IT EXISTED: FACT began charging tier COGS at LOAD time on
-- 2026-08-01; these views predate that and were never updated, so they re-derived a number that
-- was already correct — and got it wrong. WHY IT HID: account-wide over 30 days the two agree to
-- ~3% (0.845 vs 0.817). The damage is PER ROW, on exactly the rows a decision is made about.
-- The SB arm is NOT affected and is deliberately untouched: it comes from the SB report stream,
-- not FACT, and derives its margin from the campaign's dominant mapped ASIN cost ratio.
-- Same fix, same day: V_LOW_STOCK_ADS (v27.61) and the other seven engine views.
--
-- GOAL (Ori 2026-07-30): campaigns should NOT be out of budget — but should use almost all of their
-- budget. One row per ENABLED campaign (SP AND SB, launch AND working) that Amazon reported
-- CAMPAIGN_OUT_OF_BUDGET at any point on its channel's anchor day, with ONE budget suggestion.
--
-- v3 TIER SPLIT (Ori 2026-07-30) -> v27.9 (Ori 2026-08-04, "this should have the short term
-- window logic not 7 days"): BOTH tiers are judged daily on last-day + prev-2d — the working
-- cadence throttle and the 7d/3d working cut window are GONE. Tiers differ only in ladder
-- multipliers (low x2/x1.5 · working x1.5/x1.25).
-- STRONG needs BOTH windows; CUT needs BOTH windows bad (symmetric evidence, no one-day verdicts).
--
-- Status events come from the UNIFIED V_SRC interface (SP∪SB) — never the raw per-channel fivetran
-- tables and never DIM_CAMPAIGN for events (SCD2 samples 3x/day; flips that revert between loads
-- vanish). See architecture/CAMPAIGN_LAUNCH_RAMP.md §"Status source".
--
-- v27.45 (2026-08-08): ONE MEMBERSHIP FUNCTION — membership no longer re-derives the v27.15
-- anchor-day test here. It reads V_CAMPAIGN_CAP_STATE.is_oob_owned (per-day dual signal over the
-- trailing 7d, hysteresis ENTER days_capped_7d >= 2 / EXIT only at 0 — calibration record in the
-- SOP §v27.45). The anchor-only test admitted anchor-day blips (BOX-STORE/BROAD Discovery, 1/7
-- capped at 22% util) while hiding 25 chronically-capped campaigns ($3,227/7d) whose anchor day
-- came in light — incl. Brand Defense (never starve defense) and ME-VIDEO/BROAD Hunter at 1.37x.
-- pct_dark / over_budget stay the MEASURED anchor-day signals (display + ladder inputs);
-- days_capped_7d + is_oob_owned are exposed as output columns for the cube and downstream engines.
-- WATCH is now gated on days_capped_7d <= 1: "barely capped, watch" is a lie about a campaign
-- capped 2+ of the last 7 days — those run the ladder on their tier evidence windows.
--
-- v27.46 (2026-08-09) guard batch A5 — BUDGET NO-OP GUARD (v27.29 pattern for the ladder): any
-- CUT/RAISE whose suggested_budget equals the current budget after floors/rounding resolves to
-- HOLD with an honest reason ("cut resolves to the floor the budget already sits at" / "no
-- change after rounding"); HOLD carries no suggested value. APPLIED_HOLD outranks it. Also
-- v27.46: the SB prod cost-ratio is now DETERMINISTIC (dominant mapped ASIN by all-history ad
-- spend supplies BOTH cost and price) — the old ANY_VALUE pair could mix cost and price from
-- different arbitrary ASINs per plan, flipping the ladder's SB GP-ROAS between pulls (found by
-- this batch's pull-twice check on V_OOB_KEYWORD's identical CTE).
--
-- v27.74 (Task 4.7): COMPLETE-DAYS WINDOWS — every trailing multi-day window (3d/7d/4-14d/8-28d/28d, both channels) now ends at wm-1; last-day reads (r1/spend_1d/anchor dark) still read wm.
--
-- GRAIN: one row per ENABLED campaign with is_oob_owned (V_CAMPAIGN_CAP_STATE).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_OOB_BUDGET_PHASE` AS
WITH applied_bud AS (
  -- APPLIED-HOLD (v27.9, same doctrine as V_KEYWORD_LIFT v27.4): a budget change applied
  -- within 48h suppresses re-suggestion while (applied TODAY — one ladder step per day — or
  -- the value has not reached the config yet). The removed working-cadence throttle was
  -- accidentally masking this; now every tier needs the honest hold.
  SELECT CAST(campaign_id AS STRING) cid,
         ARRAY_AGG(STRUCT(applied_at AS ts, new_budget) ORDER BY applied_at DESC LIMIT 1)[OFFSET(0)] last
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
  WHERE applied_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 48 HOUR)
    AND action = 'BUDGET_CHANGE' AND new_budget IS NOT NULL
  GROUP BY 1
),
cfg AS (
  SELECT MAX(IF(config_key='campaign_launch_floor_daily', config_value, NULL)) AS floor_daily
  FROM `onyga-482313.OI.DE_BUDGET_CONFIG`
),
k AS (
  SELECT 0.10 AS dark_target, 1.5 AS strong_roas, 1.2 AS weak_roas, 0.9 AS cut_roas,
         -- slow slide (Ori 2026-07-30): -10%/day toward the $10 floor
         0.90 AS bud_cut, 2.0 AS bud_cap_weak, 3.0 AS bud_cap_strong
),
-- v27.57 (2026-08-13): the launch exemption was HALF-WIRED. It gated the coach, but this view is a
-- budget authority in its own right and never referenced it — so BALL-SP/AUTO (Mint) was live as a
-- CUT $22.50 -> $18.00 on a 1.6-month-old launch family, four panels below the exemption panel that
-- claimed to be holding it, and inside "apply all". Exactly the class the exemption exists to block:
-- a campaign-level, ROAS-keyed money cut. Same shape as the v27.45 defense gate beside it.
launch_exempt AS (
  SELECT DISTINCT CAST(campaign_id AS STRING) AS cid
  FROM `onyga-482313.OI.V_LAUNCH_EXEMPTION`
  WHERE exempt_active
),
-- v27.70 (Task 2.3): in_peak AND the judged-window length now come from V_PEAK_WINDOW_RULE —
-- the same burden-of-proof source the keyword engines read (3-day default in peak; 7 only for a
-- peak that PROVED 7 better last year; off-peak in_peak=FALSE). The local season CTE (v27.49) is
-- retired: two peak definitions in one engine eventually disagree, and the rule view already
-- carries the v27.49 fix. This puts the ladder's OWN evidence windows under the rule — the last
-- construct in the engine still judging hardcoded windows during a peak.
cap AS (SELECT in_peak, IF(in_peak, 30.0, 20.0) AS low_budget_cap, w_days
        FROM `onyga-482313.OI.V_PEAK_WINDOW_RULE`),
-- v27.45: the single membership function — see the header note
cs AS (
  SELECT campaign_id, days_capped_7d, is_oob_owned
  FROM `onyga-482313.OI.V_CAMPAIGN_CAP_STATE`
  WHERE is_oob_owned
),
wm_sp AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
          FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
wm_sb AS (SELECT LEAST(MAX(report_date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
          FROM `fivetran-hl.amazon_ads.sb_campaign_report`),
-- latest identity + budget per campaign (consolidated source per prefer-DIM/FACT rule)
camp AS (
  SELECT campaign_id, campaign_name, campaign_type AS channel, campaign_state AS state,
         serving_status, daily_budget AS budget,
         LOWER(campaign_name) LIKE '%brand defense%' AS is_defense,
         -- v9 (Ori 2026-08-02): seasonal campaigns get their own Weekly Run sections
         REGEXP_CONTAINS(LOWER(campaign_name), r'christmas|xmas|valentine|easter|halloween|thanksgiving|black friday|bfcm|cyber monday|back to school|mother.?s day|father.?s day|santa|advent|holiday') AS is_seasonal,
         -- v24 (Ori 2026-08-02): auto campaigns have their own Weekly Run section (data-truth:
         -- an enabled auto clause exists in the campaign's current config)
         CAST(campaign_id AS STRING) IN (SELECT DISTINCT CAST(campaign_id AS STRING) FROM `onyga-482313.OI.DIM_KEYWORD`
                         WHERE is_current AND UPPER(state) = 'ENABLED'
                           AND LOWER(keyword_text) IN ('close-match','loose-match','substitutes','complements')) AS is_auto_campaign
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT`
),
anchor AS (
  SELECT c.campaign_id, IF(c.channel='SB', (SELECT d FROM wm_sb), (SELECT d FROM wm_sp)) AS d
  FROM camp c
),
-- %dark on the anchor day — event replay over the unified SP∪SB log
h AS (
  SELECT s.campaign_id AS cid, DATETIME(s.date,'America/Los_Angeles') AS ts, s.serving_status
  FROM `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` s
  JOIN anchor a ON a.campaign_id = s.campaign_id
  WHERE DATE(s.date,'America/Los_Angeles') = a.d
),
ev AS (
  SELECT cid, ts, serving_status FROM h
  UNION ALL
  SELECT hc.cid, DATETIME(a.d, TIME '00:00:00'), 'CAMPAIGN_STATUS_ENABLED'
  FROM (SELECT DISTINCT cid FROM h) hc JOIN anchor a ON a.campaign_id = hc.cid
),
sq AS (SELECT cid, ts, serving_status, LEAD(ts) OVER (PARTITION BY cid ORDER BY ts) AS nxt FROM ev),
dark AS (
  SELECT s.cid,
    SUM(IF(s.serving_status='CAMPAIGN_OUT_OF_BUDGET',
        DATETIME_DIFF(COALESCE(s.nxt, DATETIME(DATE_ADD(a.d, INTERVAL 1 DAY))), s.ts, MINUTE), 0)) / 1440.0 AS pd
  FROM sq s JOIN anchor a ON a.campaign_id = s.cid
  GROUP BY 1
),
-- SP performance over 28d. GP = the STORED FACT_AMAZON_ADS.GROSS_PROFIT column — see THE GP RULE
-- in the header. (The SB arm below is untouched: it comes from the SB report stream, not FACT, and
-- derives its margin from the campaign's dominant mapped ASIN — a different mechanism entirely.)
sp_day AS (
  SELECT CAST(a.campaign_id AS STRING) AS cid, a.date,
    SUM(a.GROSS_PROFIT) AS gp,
    SUM(a.Ads_cost) AS sp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  -- v27.74: complete days (Task 4.7) — base reaches wm-28 so 28d windows end wm-1; wm kept for last-day reads
  WHERE a.date BETWEEN DATE_SUB((SELECT d FROM wm_sp), INTERVAL 28 DAY) AND (SELECT d FROM wm_sp)
  GROUP BY 1, 2
),
sp_sig AS (
  SELECT cid,
    ROUND(SAFE_DIVIDE(SUM(IF(date = (SELECT d FROM wm_sp), gp, 0)),
                      NULLIF(SUM(IF(date = (SELECT d FROM wm_sp), sp, 0)), 0)), 2) AS r1,
    ROUND(SAFE_DIVIDE(SUM(IF(date < (SELECT d FROM wm_sp) AND date >= DATE_SUB((SELECT d FROM wm_sp), INTERVAL 2 DAY), gp, 0)),
                      NULLIF(SUM(IF(date < (SELECT d FROM wm_sp) AND date >= DATE_SUB((SELECT d FROM wm_sp), INTERVAL 2 DAY), sp, 0)), 0)), 2) AS rprev2,
    -- v27.74: complete days (Task 4.7) — ends wm-1
    ROUND(SAFE_DIVIDE(SUM(IF(date BETWEEN DATE_SUB((SELECT d FROM wm_sp), INTERVAL 3 DAY) AND DATE_SUB((SELECT d FROM wm_sp), INTERVAL 1 DAY), gp, 0)),
                      NULLIF(SUM(IF(date BETWEEN DATE_SUB((SELECT d FROM wm_sp), INTERVAL 3 DAY) AND DATE_SUB((SELECT d FROM wm_sp), INTERVAL 1 DAY), sp, 0)), 0)), 2) AS r3,
    -- v27.74: complete days (Task 4.7) — ends wm-1
    ROUND(SAFE_DIVIDE(SUM(IF(date BETWEEN DATE_SUB((SELECT d FROM wm_sp), INTERVAL 7 DAY) AND DATE_SUB((SELECT d FROM wm_sp), INTERVAL 1 DAY), gp, 0)),
                      NULLIF(SUM(IF(date BETWEEN DATE_SUB((SELECT d FROM wm_sp), INTERVAL 7 DAY) AND DATE_SUB((SELECT d FROM wm_sp), INTERVAL 1 DAY), sp, 0)), 0)), 2) AS r7,
    -- v27.74: complete days (Task 4.7) — 8-28d band = [wm-28, wm-8] (base reaches wm-28)
    ROUND(SAFE_DIVIDE(SUM(IF(date < DATE_SUB((SELECT d FROM wm_sp), INTERVAL 7 DAY), gp, 0)),
                      NULLIF(SUM(IF(date < DATE_SUB((SELECT d FROM wm_sp), INTERVAL 7 DAY), sp, 0)), 0)), 2) AS r8_28,
    -- v27.74: complete days (Task 4.7) — 4-14d band = [wm-14, wm-4]
    ROUND(SAFE_DIVIDE(SUM(IF(date < DATE_SUB((SELECT d FROM wm_sp), INTERVAL 3 DAY) AND date >= DATE_SUB((SELECT d FROM wm_sp), INTERVAL 14 DAY), gp, 0)),
                      NULLIF(SUM(IF(date < DATE_SUB((SELECT d FROM wm_sp), INTERVAL 3 DAY) AND date >= DATE_SUB((SELECT d FROM wm_sp), INTERVAL 14 DAY), sp, 0)), 0)), 2) AS r4_14,
    -- v27.74: complete days (Task 4.7) — ends wm-1 (excludes the filling day wm)
    ROUND(SAFE_DIVIDE(SUM(IF(date < (SELECT d FROM wm_sp), gp, 0)),
                      NULLIF(SUM(IF(date < (SELECT d FROM wm_sp), sp, 0)), 0)), 2) AS r28,
    ROUND(SUM(IF(date = (SELECT d FROM wm_sp), sp, 0)), 2) AS spend_1d
  FROM sp_day GROUP BY 1
),
-- SB performance: est net ROAS via the campaign's mapped-ASIN cost ratio.
-- v27.46 DETERMINISM FIX: dominant mapped ASIN (most all-history ad spend, tie-break ASIN)
-- supplies BOTH cost and price — the old ANY_VALUE pair was an arbitrary per-plan pick that
-- could mix cost and price from different ASINs (see V_OOB_KEYWORD's identical CTE).
prod AS (
  SELECT cid, SAFE_DIVIDE(cost, NULLIF(price, 0)) AS cost_ratio
  FROM (
    SELECT CAST(f.campaign_id AS STRING) AS cid,
      ANY_VALUE(c.cost) AS cost, ANY_VALUE(p.listing_price_amount) AS price,
      ROW_NUMBER() OVER (PARTITION BY CAST(f.campaign_id AS STRING)
                         ORDER BY SUM(f.Ads_cost) DESC,
                                  f.ASIN_BY_CAMPAIGN_NAME IS NULL, f.ASIN_BY_CAMPAIGN_NAME) AS rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
    LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = f.ASIN_BY_CAMPAIGN_NAME
    LEFT JOIN (SELECT asin, TOTAL_COST_PER_UNIT cost FROM (
        SELECT asin, TOTAL_COST_PER_UNIT, ROW_NUMBER() OVER (PARTITION BY marketplace_id, asin ORDER BY start_date DESC) rn
        FROM `onyga-482313.OI.DIM_COSTS_HISTORY` WHERE marketplace_id='ATVPDKIKX0DER' AND end_date IS NULL) WHERE rn=1) c
      ON c.asin = f.ASIN_BY_CAMPAIGN_NAME
    GROUP BY cid, f.ASIN_BY_CAMPAIGN_NAME
  ) WHERE rn = 1
),
sb_day AS (
  SELECT CAST(r.campaign_id AS STRING) AS cid, r.report_date AS date,
    SUM(r.attributed_sales_14_d * (1 - COALESCE(pr.cost_ratio, 0))) AS gp,
    SUM(r.cost) AS sp
  FROM `fivetran-hl.amazon_ads.sb_campaign_report` r
  LEFT JOIN prod pr ON pr.cid = CAST(r.campaign_id AS STRING)
  -- v27.74: complete days (Task 4.7) — base reaches wm-28 so 28d windows end wm-1; wm kept for last-day reads
  WHERE r.report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 28 DAY) AND (SELECT d FROM wm_sb)
  GROUP BY 1, 2
),
sb_sig AS (
  SELECT cid,
    ROUND(SAFE_DIVIDE(SUM(IF(date = (SELECT d FROM wm_sb), gp, 0)),
                      NULLIF(SUM(IF(date = (SELECT d FROM wm_sb), sp, 0)), 0)), 2) AS r1,
    ROUND(SAFE_DIVIDE(SUM(IF(date < (SELECT d FROM wm_sb) AND date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 2 DAY), gp, 0)),
                      NULLIF(SUM(IF(date < (SELECT d FROM wm_sb) AND date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 2 DAY), sp, 0)), 0)), 2) AS rprev2,
    -- v27.74: complete days (Task 4.7) — ends wm-1
    ROUND(SAFE_DIVIDE(SUM(IF(date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 3 DAY) AND DATE_SUB((SELECT d FROM wm_sb), INTERVAL 1 DAY), gp, 0)),
                      NULLIF(SUM(IF(date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 3 DAY) AND DATE_SUB((SELECT d FROM wm_sb), INTERVAL 1 DAY), sp, 0)), 0)), 2) AS r3,
    -- v27.74: complete days (Task 4.7) — ends wm-1
    ROUND(SAFE_DIVIDE(SUM(IF(date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 7 DAY) AND DATE_SUB((SELECT d FROM wm_sb), INTERVAL 1 DAY), gp, 0)),
                      NULLIF(SUM(IF(date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 7 DAY) AND DATE_SUB((SELECT d FROM wm_sb), INTERVAL 1 DAY), sp, 0)), 0)), 2) AS r7,
    -- v27.74: complete days (Task 4.7) — 8-28d band = [wm-28, wm-8] (base reaches wm-28)
    ROUND(SAFE_DIVIDE(SUM(IF(date < DATE_SUB((SELECT d FROM wm_sb), INTERVAL 7 DAY), gp, 0)),
                      NULLIF(SUM(IF(date < DATE_SUB((SELECT d FROM wm_sb), INTERVAL 7 DAY), sp, 0)), 0)), 2) AS r8_28,
    -- v27.74: complete days (Task 4.7) — 4-14d band = [wm-14, wm-4]
    ROUND(SAFE_DIVIDE(SUM(IF(date < DATE_SUB((SELECT d FROM wm_sb), INTERVAL 3 DAY) AND date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 14 DAY), gp, 0)),
                      NULLIF(SUM(IF(date < DATE_SUB((SELECT d FROM wm_sb), INTERVAL 3 DAY) AND date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 14 DAY), sp, 0)), 0)), 2) AS r4_14,
    -- v27.74: complete days (Task 4.7) — ends wm-1 (excludes the filling day wm)
    ROUND(SAFE_DIVIDE(SUM(IF(date < (SELECT d FROM wm_sb), gp, 0)),
                      NULLIF(SUM(IF(date < (SELECT d FROM wm_sb), sp, 0)), 0)), 2) AS r28,
    ROUND(SUM(IF(date = (SELECT d FROM wm_sb), sp, 0)), 2) AS spend_1d
  FROM sb_day GROUP BY 1
),
bc AS (
  SELECT campaign_id, DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), MAX(DATE(applied_at)), DAY) AS days_since_budget_change
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
  WHERE action = 'BUDGET_CHANGE'
  GROUP BY 1
),
base AS (
  SELECT
    c.campaign_id, c.campaign_name, c.channel, c.is_defense, c.is_seasonal, c.is_auto_campaign,
    -- v27.57: launch-family exemption, gated exactly like is_defense on every CUT branch below
    (le.cid IS NOT NULL) AS is_launch_exempt,
    IF(lp.campaign_id IS NOT NULL, 'LAUNCH', 'WORKING') AS engine,
    a.d AS anchor_date,
    ROUND(c.budget, 2) AS budget,
    COALESCE(s1.spend_1d, s2.spend_1d) AS spend_1d,
    COALESCE(d.pd, 0) AS pd,
    COALESCE(s1.r1, s2.r1) AS r1, COALESCE(s1.rprev2, s2.rprev2) AS rprev2,
    COALESCE(s1.r3, s2.r3) AS r3, COALESCE(s1.r7, s2.r7) AS r7, COALESCE(s1.r28, s2.r28) AS r28,
    COALESCE(s1.r8_28, s2.r8_28) AS r8_28, COALESCE(s1.r4_14, s2.r4_14) AS r4_14,
    bcx.days_since_budget_change AS dsb,
    kk.low_budget_cap, kk.in_peak, kk.w_days,
    -- ── v27.70 EVIDENCE LEGS (Task 2.3) — the ladder judges THESE, never raw windows ─────────
    -- Off-peak: the deliberate v27.9 shape (today + prev-2d for raises/low-cut; 7d + 8-28d for
    -- the working chronic test). IN PEAK: every leg follows V_PEAK_WINDOW_RULE.w_days — 3-day
    -- default (3d + 4-14d), or the 7d shape for a peak that proved 7. One definition, six
    -- consumers (action / suggested / reason × short / prior), so the ladders cannot drift.
    IF(kk.in_peak, IF(kk.w_days >= 7, COALESCE(s1.r7, s2.r7), COALESCE(s1.r3, s2.r3)),
       COALESCE(s1.r1, s2.r1)) AS ev_s,
    IF(kk.in_peak, IF(kk.w_days >= 7, COALESCE(s1.r8_28, s2.r8_28), COALESCE(s1.r4_14, s2.r4_14)),
       COALESCE(s1.rprev2, s2.rprev2)) AS ev_p,
    IF(kk.in_peak, IF(kk.w_days >= 7, 'last 7d', 'last 3d'), 'today') AS ev_s_label,
    IF(kk.in_peak, IF(kk.w_days >= 7, '8-28d', '4-14d'), 'prev-2d') AS ev_p_label,
    -- the working tier's CHRONIC legs (already peak-aware since v27.10; now w_days-general)
    IF(kk.in_peak, IF(kk.w_days >= 7, COALESCE(s1.r7, s2.r7), COALESCE(s1.r3, s2.r3)),
       COALESCE(s1.r7, s2.r7)) AS evc_s,
    IF(kk.in_peak, IF(kk.w_days >= 7, COALESCE(s1.r8_28, s2.r8_28), COALESCE(s1.r4_14, s2.r4_14)),
       COALESCE(s1.r8_28, s2.r8_28)) AS evc_p,
    IF(kk.in_peak, IF(kk.w_days >= 7, '7d', '3d'), '7d') AS evc_s_label,
    IF(kk.in_peak, IF(kk.w_days >= 7, '8-28d', '4-14d'), '8-28d') AS evc_p_label,
    (c.budget <= kk.low_budget_cap) AS is_low_tier,
    -- v27.15 (Ori 2026-08-05 "if spend is greater then budget you should consider it out of
    -- budget as well"): Amazon does not always emit CAMPAIGN_OUT_OF_BUDGET — SB overdelivers to
    -- 2x its daily budget without ever flipping the status, so the dark clock reads 0% on a
    -- campaign that spent 156% of budget. Spending at/over the budget IS the cap, measured a
    -- second way.
    (COALESCE(s1.spend_1d, s2.spend_1d, 0) >= c.budget) AS over_budget,
    -- v27.45: the membership function's evidence, carried to the output for the cube + engines
    csx.days_capped_7d, csx.is_oob_owned
  FROM camp c
  CROSS JOIN cap kk
  JOIN anchor a ON a.campaign_id = c.campaign_id
  -- v27.45: MEMBERSHIP = the single membership function (INNER JOIN on is_oob_owned rows).
  -- The v27.15 anchor-day WHERE test is gone — pd/over_budget stay as measured ladder inputs.
  JOIN cs csx ON csx.campaign_id = c.campaign_id
  -- LEFT (was: INNER ... AND d.pd > 0) — an over-budget campaign with a silent dark clock must
  -- still reach the ladder. Membership is enforced by the cap-state join above.
  LEFT JOIN dark d ON d.cid = c.campaign_id
  LEFT JOIN sp_sig s1 ON c.channel = 'SP' AND s1.cid = c.campaign_id
  LEFT JOIN sb_sig s2 ON c.channel = 'SB' AND s2.cid = c.campaign_id
  LEFT JOIN (SELECT DISTINCT campaign_id FROM `onyga-482313.OI.V_LAUNCH_POPULATION`) lp
    ON lp.campaign_id = c.campaign_id
  LEFT JOIN bc bcx ON bcx.campaign_id = c.campaign_id
  LEFT JOIN launch_exempt le ON le.cid = CAST(c.campaign_id AS STRING)
  WHERE c.state = 'ENABLED'
    AND c.serving_status IN ('CAMPAIGN_STATUS_ENABLED', 'CAMPAIGN_OUT_OF_BUDGET')
),
out AS (
SELECT
  b.campaign_id, b.campaign_name, b.channel, b.engine, b.anchor_date, b.is_defense, b.is_launch_exempt, b.is_seasonal, b.is_auto_campaign,
  b.budget AS current_budget, b.spend_1d,
  ROUND(SAFE_DIVIDE(b.spend_1d, b.budget), 2) AS utilization,
  ROUND(b.pd * 100) AS pct_dark,
  -- v27.15: the second out-of-budget signal. pct_dark stays the MEASURED clock (never inflated
  -- with a fabricated percentage) — this flag carries the spend-past-budget evidence.
  b.over_budget,
  -- v27.45: the membership function's evidence — exposed for the cube and the downstream engines
  -- (V_OOB_KEYWORD population + V_KEYWORD_LIFT DEFER_OOB routing read these).
  b.days_capped_7d, b.is_oob_owned,
  b.r1 AS roas_1d, b.rprev2 AS roas_prev2, b.r3 AS roas_3d, b.r7 AS roas_7d, b.r28 AS roas_28d,
  b.dsb AS days_since_budget_change,
  b.is_low_tier, b.in_peak, b.w_days,  -- v27.70: the judged window, from V_PEAK_WINDOW_RULE
  -- ═══ BUDGET LADDER v4 (Ori 2026-08-01 tuning) ═══
  -- Both tiers key raises on TODAY + PREV-2D. Low tier raises harder (x2/x1.5) than working
  -- (x1.5/x1.25). Cuts need BOTH the tier's evidence window AND today under 0.6x -> -20% with a
  -- seasonal floor ($10 off / $15 peak). Evidence window: low = prev-2d · working = 7d off / 3d peak.
  CASE
    -- v27.45: WATCH only while the cap is genuinely occasional (<= 1 capped day in 7). A campaign
    -- capped 2+ of 7 whose ANCHOR day came in light must still run the ladder on its evidence.
    WHEN b.pd <= x.dark_target AND NOT b.over_budget AND b.days_capped_7d <= 1 THEN 'WATCH'
    WHEN b.is_low_tier THEN CASE
      WHEN COALESCE(b.ev_s,0) >= x.weak_roas AND COALESCE(b.ev_p,0) >= x.strong_roas THEN 'RAISE_STRONG'
      WHEN COALESCE(b.ev_s,0) >= x.weak_roas THEN 'RAISE_WEAK'
      -- v27.45: never CUT a defense budget — the moat is bought at whatever it costs; with
      -- persistent cap-state membership a defense campaign now sits here for whole weeks, and
      -- a ROAS-keyed budget cut would starve the defense (raises and holds still apply).
      WHEN COALESCE(b.ev_s,0) < 0.6 AND COALESCE(b.ev_p,0) < 0.6 AND NOT b.is_defense AND NOT b.is_launch_exempt THEN 'CUT'
      ELSE 'HOLD' END
    -- v27.10 (Ori 2026-08-04): working tier = asymmetric windows. CHRONIC first — regular
    -- windows (7d AND 8-28d, peak 3d AND 4-14d) both under 0.6x -> CUT (a hot yesterday inside
    -- a chronic bleeder is noise; no raise). Otherwise raises fire on the SHORT windows.
    ELSE CASE
      WHEN COALESCE(b.evc_s, 0) < 0.6 AND COALESCE(b.evc_p, 0) < 0.6 AND NOT b.is_defense AND NOT b.is_launch_exempt THEN 'CUT'  -- v27.45 defense gate
      WHEN COALESCE(b.ev_s,0) >= x.weak_roas AND COALESCE(b.ev_p,0) >= x.strong_roas THEN 'RAISE_STRONG'
      WHEN COALESCE(b.ev_s,0) >= x.weak_roas THEN 'RAISE_WEAK'
      ELSE 'HOLD' END
  END AS action,
  CASE
    WHEN b.pd <= x.dark_target AND NOT b.over_budget AND b.days_capped_7d <= 1 THEN NULL  -- v27.45 WATCH gate
    WHEN b.is_low_tier THEN CASE
      WHEN COALESCE(b.ev_s,0) >= x.weak_roas AND COALESCE(b.ev_p,0) >= x.strong_roas THEN ROUND(b.budget * 2.0, 2)
      WHEN COALESCE(b.ev_s,0) >= x.weak_roas THEN ROUND(b.budget * 1.5, 2)
      WHEN COALESCE(b.ev_s,0) < 0.6 AND COALESCE(b.ev_p,0) < 0.6 AND NOT b.is_defense AND NOT b.is_launch_exempt  -- v27.45 defense gate
        THEN ROUND(GREATEST(b.budget * 0.8, IF(b.in_peak, 15.0, 10.0)), 2)
      ELSE NULL END
    ELSE CASE
      WHEN COALESCE(b.evc_s, 0) < 0.6 AND COALESCE(b.evc_p, 0) < 0.6 AND NOT b.is_defense AND NOT b.is_launch_exempt  -- v27.45 defense gate
        THEN ROUND(GREATEST(b.budget * 0.8, IF(b.in_peak, 15.0, 10.0)), 2)
      WHEN COALESCE(b.ev_s,0) >= x.weak_roas AND COALESCE(b.ev_p,0) >= x.strong_roas THEN ROUND(b.budget * 1.5, 2)
      WHEN COALESCE(b.ev_s,0) >= x.weak_roas THEN ROUND(b.budget * 1.25, 2)
      ELSE NULL END
  END AS suggested_budget,
  CASE
    WHEN b.pd <= x.dark_target AND NOT b.over_budget AND b.days_capped_7d <= 1  -- v27.45 WATCH gate
      THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% — barely capped, watch')
    WHEN b.is_low_tier THEN CASE
      WHEN COALESCE(b.ev_s,0) >= x.weak_roas AND COALESCE(b.ev_p,0) >= x.strong_roas
        THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · ', b.ev_s_label, ' ', CAST(b.ev_s AS STRING),
                    'x AND ', b.ev_p_label, ' ', CAST(b.ev_p AS STRING), 'x → strong raise ×2')
      WHEN COALESCE(b.ev_s,0) >= x.weak_roas
        THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · ', b.ev_s_label, ' ', CAST(b.ev_s AS STRING), 'x → raise ×1.5')
      WHEN COALESCE(b.ev_s,0) < 0.6 AND COALESCE(b.ev_p,0) < 0.6 AND NOT b.is_defense AND NOT b.is_launch_exempt  -- v27.45 defense gate
        THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · ', b.ev_s_label, ' AND ', b.ev_p_label,
                    ' both under 0.6x → cut 20% (floor $',
                    CAST(CAST(IF(b.in_peak,15,10) AS INT64) AS STRING), ')')
      ELSE CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · ',
                  IF(b.is_defense, 'brand defense — never cut the moat: hold budget (raise when the windows warrant)',
                     'mixed windows → hold budget, bids do the work')) END
    ELSE CASE
      WHEN COALESCE(b.evc_s, 0) < 0.6 AND COALESCE(b.evc_p, 0) < 0.6 AND NOT b.is_defense AND NOT b.is_launch_exempt  -- v27.45 defense gate
        THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · chronic — ', b.evc_s_label, ' ',
                    CAST(COALESCE(b.evc_s, 0) AS STRING), 'x AND ', b.evc_p_label, ' ',
                    CAST(COALESCE(b.evc_p, 0) AS STRING), 'x both under 0.6x → cut 20% (floor $',
                    CAST(CAST(IF(b.in_peak,15,10) AS INT64) AS STRING), '); no raise into a chronic bleeder')
      WHEN COALESCE(b.ev_s,0) >= x.weak_roas AND COALESCE(b.ev_p,0) >= x.strong_roas
        THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · ', b.ev_s_label, ' ', CAST(b.ev_s AS STRING),
                    'x AND ', b.ev_p_label, ' ', CAST(b.ev_p AS STRING), 'x → strong raise ×1.5')
      WHEN COALESCE(b.ev_s,0) >= x.weak_roas
        THEN CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · ', b.ev_s_label, ' ', CAST(b.ev_s AS STRING), 'x → raise ×1.25')
      ELSE CONCAT('Dark ', CAST(ROUND(b.pd*100) AS STRING), '% · ',
                  IF(b.is_defense, 'brand defense — never cut the moat: hold budget (raise when the windows warrant)',
                     'evidence mid → hold budget, bids do the work')) END
  END AS reason
FROM base b
CROSS JOIN k x
CROSS JOIN cfg cf
)
SELECT o.* EXCEPT (bud_noop) REPLACE (
  -- v27.46 A5: the no-op guard sits BELOW the applied-hold (a just-applied change is the more
  -- specific truth) and converts empty-promise CUT/RAISE rows to an honest HOLD.
  CASE WHEN hold THEN 'APPLIED_HOLD' WHEN bud_noop THEN 'HOLD' ELSE o.action END AS action,
  IF(hold OR bud_noop, NULL, o.suggested_budget) AS suggested_budget,
  CASE
    WHEN hold THEN CONCAT('budget applied $', FORMAT('%.2f', ab.last.new_budget), ' at ',
       FORMAT_TIMESTAMP('%b %d %H:%M', ab.last.ts, 'America/Los_Angeles'),
       ' — waiting for Amazon sync')
    -- v27.46 A5: honest no-op reasons — a CUT landing exactly on the seasonal floor it already
    -- sits at, or any suggestion that rounds to the current budget, promises nothing.
    WHEN bud_noop THEN IF(o.action = 'CUT',
       CONCAT('cut resolves to the $', CAST(CAST(IF(o.in_peak, 15, 10) AS INT64) AS STRING),
              ' floor the budget already sits at — hold (no empty promises)'),
       'suggested budget equals the current budget after rounding — hold (no empty promises)')
    -- v27.15: when the campaign is here on the SPEND signal rather than the dark clock, the
    -- ladder's "Dark 0% ..." opener is a lie about why it qualified. Restate the opener.
    -- v27.45: same honesty for the chronic case — a campaign here on 7d cap evidence whose
    -- anchor day came in light must not open with "Dark 0%".
    WHEN o.over_budget AND o.pct_dark <= 10 THEN
      REGEXP_REPLACE(o.reason, r'^Dark \d+%',
        CONCAT('Spent ', CAST(CAST(ROUND(o.utilization*100) AS INT64) AS STRING),
               '% of budget (dark clock silent)'))
    WHEN NOT o.over_budget AND o.pct_dark <= 10 AND o.days_capped_7d >= 2 THEN
      REGEXP_REPLACE(o.reason, r'^Dark \d+%',
        CONCAT('Capped ', CAST(o.days_capped_7d AS STRING),
               ' of last 7 days (anchor day light)'))
    ELSE o.reason
  END AS reason
)
FROM (
  SELECT o0.*,
    ab0.last IS NOT NULL AND o0.suggested_budget IS NOT NULL AND
      (DATE(ab0.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
       OR ABS(COALESCE(ab0.last.new_budget, -1) - o0.current_budget) > 0.51) AS hold,
    -- v27.46 A5: any promised move that lands on the budget the campaign already has.
    -- v27.49 EXTENDED (Ori 2026-08-12): also catch DIRECTION VIOLATIONS. Surfaced the moment the
    -- season gate started reading peak correctly: in peak the launch floor rises, so the CUT
    -- ladder's max(current x 0.90, floor) can land ABOVE current — 8 campaigns were emitting
    -- "CUT $10.00 -> $15.00", a raise wearing a cut's label. A cut that cannot go down is a HOLD.
    o0.action IN ('CUT', 'RAISE_STRONG', 'RAISE_WEAK') AND o0.suggested_budget IS NOT NULL
      AND (ABS(o0.suggested_budget - o0.current_budget) < 0.005
           OR (o0.action = 'CUT' AND o0.suggested_budget > o0.current_budget)
           OR (o0.action IN ('RAISE_STRONG','RAISE_WEAK')
               AND o0.suggested_budget < o0.current_budget)) AS bud_noop
  FROM out o0
  LEFT JOIN applied_bud ab0 ON ab0.cid = CAST(o0.campaign_id AS STRING)
) o
LEFT JOIN applied_bud ab ON ab.cid = CAST(o.campaign_id AS STRING);
