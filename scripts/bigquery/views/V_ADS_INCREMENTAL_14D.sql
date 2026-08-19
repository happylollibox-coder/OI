-- =============================================
-- V_ADS_INCREMENTAL_14D — "did the last fortnight of PPC work make more dollars than doing
-- nothing would have?" (Ori, 2026-08-18). v27.82.
--
-- ###########################################################################################
-- # THIS IS A DOWNGRADED ESTIMATOR. IT IS NOT A DIFFERENCE-IN-DIFFERENCES. READ THIS FIRST. #
-- ###########################################################################################
-- The design that was ASKED FOR was matched keyword-grain DiD: treated keyword pre/post minus a
-- matched untouched keyword's pre/post. That design was TESTED BEFORE BUILDING and it FAILED.
-- It is not built here, and the reasons are recorded in the view itself (column downgrade_reason)
-- so nobody can read the number without the caveat:
--
--   1. NO CONTROL POOL EXISTS. 73.5% of keywords with ads activity in 60 days were touched, and
--      they carry 85.1% of keyword-grain spend. On the exact live rolling window the clean
--      untouched arm is 29 keywords / $1,110 against a treated arm of 379 keywords / $29,326, and
--      only SEVEN untouched keywords clear a 10-click bar in both windows ($819). A 3% control
--      against a 97% treatment is not a control.
--   2. MATCHING FAILS AT 98.1%. On (family, state, volume band, launch-age band) 617 of 629
--      treated keywords get ZERO match; 92.0% of treated dollars have no counterfactual. Relaxing
--      to (family, state) still leaves 84.4% unmatched. 120 of the 161 untouched keywords are not
--      in FACT_KEYWORD_STATE at all and carry no family, so they are unmatchable on any covariate.
--   3. PARALLEL TRENDS IS FALSIFIED, NOT MERELY UNTESTED. Pre-treatment daily-delta correlation
--      between treated and matched control is -0.137 (2026-08-15 event) and -0.673 (2026-08-09) --
--      the two arms move in OPPOSITE directions BEFORE anything is done. Normalised pre-trend gap
--      is 152% and 236% of the treated cohort's own daily variation.
--   4. THE PLACEBO IS CATASTROPHIC. Replicating the engine's own selection rule (rank keywords by
--      trailing-14d dollars, act on the tails) and then doing NOTHING AT ALL fabricates +$1,505 /
--      +$1,855 / +$2,445 on the losers arm and -$1,094 / -$1,365 / -$1,829 on the winners arm,
--      across four independent no-upload dates. The account's true 14-day dollar magnitude is
--      about -$2,500, so pure mean reversion manufactures ~90% of the account's entire size.
--   5. SUTVA IS VIOLATED. 56-63% of matched controls share a campaign budget with a treated
--      keyword, so raising a treated bid mechanically starves its own "control".
--   6. THE CONTROL IS BEING DRAINED. Clean control keywords went 4,302 -> 725 clicks (-83%) across
--      one anchor: the intent-grid rebuild moved traffic, hitting the control arm and not the
--      treated one. A change-in-change against a collapsing control measures the reorg.
--
-- ###########################################################################################
-- # WHAT IS BUILT INSTEAD                                                                   #
-- ###########################################################################################
-- SEASON-ADJUSTED BEFORE/AFTER WITH AN EMPIRICAL PLACEBO BAND. Per the build rules this is
-- option (c): the naive before/after reported ALONGSIDE its own measured placebo bias as the
-- error bar, labelled an UPPER BOUND ON KNOWLEDGE, not a measurement. Option (a) (a tighter
-- matched subset that passes the placebo) was not available -- there is no subset, the control
-- pool is 7 keywords. Option (b) (synthetic control) was rejected for the same reason: a donor
-- pool of 49-161 untouched keywords whose MEMBERSHIP IS CAUSED BY THE OUTCOME (a keyword is
-- untouched precisely because it stopped being worth acting on) and whose clicks fell 83% over
-- the fit window cannot reproduce a treated trajectory honestly. Weighting a lying donor pool
-- produces a more confident lie.
--
-- THE ARITHMETIC, per treated target k, changed on day t:
--     pre_k      = SUM(GROSS_PROFIT - Ads_cost) over [t-14, t-1]
--     post_k     = SUM(GROSS_PROFIT - Ads_cost) over [t+1, t+14]
--     season_k   = season_rate(t) * pre_spend_k
--     effect_k   = (post_k - pre_k) - season_k
--     incremental_dollars = SUM(effect_k)
-- DOLLARS, never ROAS: Ori asked "how many more dollars", and a ratio cannot answer a dollars
-- question -- it hides volume. GROSS_PROFIT is the STORED FACT_AMAZON_ADS column, never
-- recomputed (v27.62 GP RULE).
--
-- season_rate(t) is the SAME-CALENDAR LAST-YEAR swing per pre-spend dollar, measured account-wide
-- on [t-378,t-365] -> [t-363,t-350] (364 days = 52 weeks, so day-of-week aligns). This is the
-- ONLY trustworthy seasonal yardstick available: over the identical day-of-year windows in 2025,
-- with zero 2026 decisions involved, account ad dollars moved -$2,328 -> +$299, a +$2,627 swing
-- (ads sales +31.6% while ad cost FELL 17%) -- pure Back-to-School calendar. WITHOUT this
-- adjustment a 14-day check reads a +/-$150 signal sitting on a +$2,000 calendar tide.
-- The "untouched cohort drift" alternative (+$1,500-2,100) was REJECTED as a season yardstick: it
-- is contaminated by the same survivorship that breaks the DiD (its GP-ROAS rose 0.49 -> 1.21
-- largely because its weak members got touched and left), so it is an upper bound on season, not
-- an estimate of it.
-- CAVEAT ON THE YARDSTICK: ads data starts 2024-09-05, so exactly ONE prior year of seasonality
-- exists and none at all for windows before 2025-09. It is one draw, not a distribution.
--
-- ###########################################################################################
-- # THE BAND IS THE OUTPUT. THE POINT ESTIMATE IS NOT.                                      #
-- ###########################################################################################
-- A "+$340" with no band is the same unfalsifiable number this is meant to replace. Two separate
-- sources of error are measured and combined:
--   se_keywords   standard error of the SUM over per-target effects = STDDEV_SAMP(effect_k) *
--                 SQRT(n). Chosen over a bootstrap because the estimator is a plain sum of
--                 per-keyword terms, so the closed form IS the bootstrap's limit, it is exact
--                 rather than resampled, and it is deterministic -- two pulls of this view on the
--                 same day are byte-identical, which a seeded bootstrap in BigQuery SQL is not.
--                 It captures SAMPLING noise only, and it is the SMALLER of the two errors.
--   placebo_sd    the REAL error bar. The identical estimator -- same targets, same eligibility
--                 rule, same season adjustment -- is re-run at 5 PLACEBO ANCHORS (the same change
--                 dates shifted back 28/35/42/49/56 days, i.e. before those targets were touched,
--                 where the true effect is EXACTLY ZERO by construction). Whatever it prints
--                 there is bias plus noise. placebo_mean is the bias; placebo_sd is the spread.
--   band_halfwidth = 1.96 * SQRT(se_keywords^2 + placebo_sd^2) + ABS(placebo_mean)
-- If band_low <= 0 <= band_high the honest verdict is INSIDE NOISE: the fortnight's work cannot
-- be distinguished from having done nothing. That is a legitimate answer and must be reported as
-- one, not smoothed into a positive-sounding number.
-- The placebo band is computed on THE SAME STRATUM as the estimate, deliberately: whole-cohort
-- placebos look deceptively tame only because the up-bias on the REDUCE arm cancels the
-- down-bias on the INCREASE arm, and that cancellation is a coincidence of each week's mix.
--
-- ###########################################################################################
-- # THE LAG IS REAL AND IS NOT A BUG                                                        #
-- ###########################################################################################
-- Ori asked for "the last 14 days". A change made yesterday CANNOT be judged: FACT is ~88-90%
-- complete at age 1, ads sales accrue to D+7 (SP) / D+14 (SB), and grading early does not add
-- noise, it adds BIAS in one direction -- it systematically under-reads your own change.
-- Therefore: cohort_end = as_of - (14 + 7) for SP and as_of - (14 + 14) for SB, and the reported
-- population is the ROLLING 14 DAYS OF DECISIONS ending there. Everything newer is counted on the
-- changes_too_recent line as TOO EARLY TO JUDGE and is NEVER silently treated as zero effect.
-- Consequence, stated up front so it is not read as breakage: this check reports on decisions
-- made 3-4 weeks ago, and on days when no upload happened 3-4 weeks ago it will legitimately have
-- nothing new to say. changes_in_cohort tells you how much evidence today's reading rests on.
--
-- BURSTINESS WARNING carried in the data: uploads land on only 25 of 60 days and three days hold
-- 44% of all changes. A rolling total therefore STEPS UP AND DOWN as bursts enter and leave the
-- window for pure calendar reasons. Read changes_in_cohort next to the dollars, always.
--
-- ###########################################################################################
-- # WHAT THIS VIEW DOES NOT AND CANNOT MEASURE -- state this to anyone who reads the number  #
-- ###########################################################################################
--  * IT IS NOT AN ACCOUNT-LEVEL COUNTERFACTUAL. A sum of per-target effects cannot see budget
--    reallocation between keywords, cannibalisation between campaigns bidding the same term, or
--    organic halo -- which is most of what "total dollars" means. With ~79% purchased-vs-
--    advertised ASIN divergence, ad-attributed GROSS_PROFIT is not the account's dollars either.
--  * SELECTION ON THE OUTCOME IS NOT REMOVED, ONLY MEASURED. The engine picks winners and losers
--    on their extreme days; mean reversion is the null. The season adjustment does not touch it.
--    The placebo band is what quantifies it -- which is why the band is usually wider than the
--    estimate, and why that is the correct result rather than a defect.
--  * NEGATE and ADD_TARGET are NOT MEASURED. A negate is scored on a term disappearing, not on a
--    dollar delta; an added target has no pre-window by construction, so post-minus-pre equals
--    post and the estimator would book 100% of new-keyword launch volume as skill -- exactly the
--    "new product masquerading as skill" Ori asked to prevent. Both are reported as coverage
--    counts only. V_CHANGE_SCORECARD grades them properly.
--  * BUDGET rows are campaign grain and are reported on their OWN NON-ADDITIVE line. They must
--    never be added to the keyword line: every keyword inside a re-budgeted campaign already
--    appears there, so summing double-counts. is_additive = FALSE says so per row.
--  * LAUNCH is stratified, never excluded (dropping it would flatter the result and stop
--    answering Ori's question), but inside launch the estimator is NOT IDENTIFIED: LolliBall
--    sales grew +56.7% and Bunny +33.3% against an account at +12.5%, so pre/post books the ramp
--    as skill. Grade launch against the planned donor ramp (V_CAMPAIGN_LAUNCH_RAMP), not here.
--  * IN-SEASON vs OUT-OF-SEASON could not be built as a stratum: DIM_US_HOLIDAYS_PRODUCT_FAMILY
--    has ZERO Back to School rows, and every measurable family rises Jul->Aug anyway, so no
--    out-of-season contrast group exists in this account.
--
-- THE ONLY THING THAT MAKES THIS QUESTION PROPERLY ANSWERABLE is a deliberate randomised hold-out:
-- a stratified 15-20% of ELIGIBLE keywords per upload that the engine proposes and does NOT
-- apply. Randomisation is what makes a control group's membership independent of the outcome, and
-- nothing in the existing data substitutes for it. It costs roughly $1.5-2k/month of foregone
-- optimisation and buys a real answer in 6-8 weeks. Until it exists, THIS VIEW IS A MONITOR.
--
-- PLANNER DISCIPLINE: FACT_AMAZON_ADS is referenced ONCE at keyword-day grain (fa_base); every
-- panel, the account daily series, campaign first-seen dates and the family map are derived from
-- it. A second, trivial 30-day MAX(date) probe establishes the watermark. NO ceiling view is
-- inlined (V_LOW_STOCK_ADS / V_KEYWORD_LIFT / V_OOB_KEYWORD / V_CHANGE_SCORECARD / V_LAUNCH_*):
-- launch age and family are re-derived from fa_base + DIM_PRODUCT + DE_CAMPAIGN_FAMILY instead.
-- DETERMINISM: plain SUMs over fixed windows, no ANY_VALUE pairs, dedup QUALIFY fully tie-broken.
-- Money is aggregated in NUMERIC, not FLOAT64. This is not decoration: the first build differed by
-- one cent between two pulls of the same second, because FLOAT64 addition is not associative and
-- BigQuery aggregates in parallel in a nondeterministic order. Same family of trap as the EXCEPT
-- DISTINCT view-parity false positives. NUMERIC addition is exact and order-independent, so two
-- pulls are now byte-identical; the cast back to FLOAT64 happens once, after every SUM is closed.
-- TIMEZONE: applied_at is UTC; every window uses DATE(applied_at,'America/Los_Angeles') to align
-- with FACT_AMAZON_ADS.date. WINDOW CONVENTION: as_of = MAX(FACT.date) - 1 (Task 4.7 -- the last
-- day is still filling and stands alone).
--
-- ###########################################################################################
-- # WHAT THE FIRST RUN FOUND, AND WHY THE VIEW GAINED TWO MORE GUARDS                       #
-- ###########################################################################################
-- Built, run, and the result changed the build. On the live fortnight of gradeable decisions
-- (2026-07-14..2026-07-27) EVERY placebo anchor came back EXACTLY ZERO: all 41 judged targets had
-- 0 clicks and $0 in their placebo pre/post windows 28-56 days earlier. The reason is not a bug --
-- THE CAMPAIGNS DID NOT EXIST YET. Campaign age at the change date across the judged set is 1 to
-- 19 days: the only decisions currently old enough to have settled are the ones made during the
-- intent-campaign-grid rebuild, on campaigns that were days old. Two consequences, both now
-- encoded rather than hidden:
--   (a) A placebo that lands before the unit existed measures nothing and returns a FALSELY TIGHT
--       band ($14 sd where the real noise floor is in the hundreds). placebo_coverage_pct now
--       measures the share of units that actually had >=10 pre-window clicks at the placebo
--       anchors; below 50% the placebo is discarded, band_basis flips to 'SAMPLING ONLY' and the
--       band is explicitly labelled a LOWER BOUND on uncertainty, never a confidence interval.
--   (b) A unit whose campaign is younger than the 14-day pre-window has a pre-window that predates
--       its own existence, so post-minus-pre is the campaign's RAMP, not the bid change. That is
--       the "new product masquerading as skill" case Ori explicitly asked to be prevented. It is
--       flagged per row (pre_window_valid) and split out as its own stratum.
-- Because the rolling-14-day cohort of decisions is so thin (burstiness: uploads land on 25 of 60
-- days), a second SCOPE is reported alongside it -- ALL_GRADEABLE_60D, every settled decision in
-- the last 60 days. ROLLING_14D is the answer to the question as asked; ALL_GRADEABLE_60D is the
-- widest defensible read and is where a placebo can actually be computed. They are separate rows,
-- never summed.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_INCREMENTAL_14D` AS
WITH
k AS (
  SELECT 14   AS horizon_days,        -- Ori's fortnight, both pre and post
         7    AS sp_settle_days,      -- SP attribution tail
         14   AS sb_settle_days,      -- SB attribution tail
         364  AS ly_offset_days,      -- 52 weeks, preserves day-of-week
         10   AS min_pre_clicks,      -- thin-evidence bar (same bar as V_CHANGE_SCORECARD)
         500  AS fact_lookback_days,  -- covers the oldest placebo anchor's last-year window
         120  AS chg_lookback_days,
         0.50 AS min_placebo_coverage,-- below this the placebo band is discarded as vacuous
         1.96 AS z
),
probe AS (
  SELECT MAX(date) AS max_date
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 30 DAY)
),
b AS (
  SELECT
    DATE_SUB(p.max_date, INTERVAL 1 DAY)                                          AS as_of,
    DATE_SUB(DATE_SUB(p.max_date, INTERVAL 1 DAY),
             INTERVAL k.horizon_days + k.sp_settle_days DAY)                      AS cohort_end,
    DATE_SUB(DATE_SUB(p.max_date, INTERVAL 1 DAY),
             INTERVAL k.horizon_days + k.sb_settle_days DAY)                      AS sb_gate_end,
    DATE_SUB(CURRENT_DATE('America/Los_Angeles'),
             INTERVAL k.fact_lookback_days DAY)                                   AS scan_start,
    k.min_placebo_coverage, k.min_pre_clicks, k.z
  FROM probe p CROSS JOIN k
),
-- ROLLING_14D answers Ori's question as asked. ALL_GRADEABLE_60D is the widest defensible read
-- and the only scope on which a placebo anchor can usually be computed. NEVER SUM THE TWO.
scopes AS (
  SELECT * FROM UNNEST([
    STRUCT('ROLLING_14D' AS scope_name, 14 AS decision_days, 1 AS scope_ord),
    STRUCT('ALL_GRADEABLE_60D',         60,                  2)
  ])
),
offsets AS (SELECT * FROM UNNEST([0, 28, 35, 42, 49, 56]) AS placebo_offset),

-- ── 1. THE ONE SCAN OF FACT_AMAZON_ADS (keyword-day grain) ──────────────────────────────────
fa_base AS (
  SELECT
    CAST(a.campaign_id AS STRING)                                         AS cid,
    NULLIF(CAST(a.keyword_id AS STRING), '')                              AS kid,
    LOWER(TRIM(a.targeting))                                              AS tgt_lc,
    COALESCE(a.most_advertised_asin_impressions, a.ASIN_BY_CAMPAIGN_NAME) AS asin,
    a.date                                                                AS dt,
    SUM(a.Ads_clicks)                     AS clk,
    SUM(CAST(a.Ads_cost     AS NUMERIC))  AS cost,   -- NUMERIC: exact, order-independent
    SUM(CAST(a.GROSS_PROFIT AS NUMERIC))  AS gp      -- (see DETERMINISM in the header)
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  WHERE a.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 500 DAY)
  GROUP BY 1, 2, 3, 4, 5
),
-- '-1'/'0' are SB video / product-targeting SENTINELS pooling many campaigns into one row; they
-- can never be a real treated target and must never be allowed to match one.
fa_kid  AS (SELECT cid, kid, dt, SUM(clk) clk, SUM(cost) cost, SUM(gp) gp
            FROM fa_base WHERE kid IS NOT NULL AND kid NOT IN ('-1','0') GROUP BY 1,2,3),
fa_tgt  AS (SELECT cid, tgt_lc, dt, SUM(clk) clk, SUM(cost) cost, SUM(gp) gp
            FROM fa_base WHERE tgt_lc IS NOT NULL GROUP BY 1,2,3),
fa_camp AS (SELECT cid, dt, SUM(clk) clk, SUM(cost) cost, SUM(gp) gp FROM fa_base GROUP BY 1,2),
acct_day AS (SELECT dt, SUM(cost) cost, SUM(gp) gp FROM fa_base GROUP BY 1),
kid_index AS (SELECT DISTINCT cid, kid FROM fa_kid),

-- launch age and family re-derived from fa_base: no ceiling view, no second FACT scan
camp_first AS (SELECT cid, MIN(dt) AS first_dt FROM fa_camp GROUP BY 1),
camp_fam AS (
  SELECT cid, parent_name FROM (
    SELECT f.cid, p.parent_name,
           ROW_NUMBER() OVER (PARTITION BY f.cid ORDER BY SUM(f.cost) DESC, p.parent_name) AS rn
    FROM fa_base f
    JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = f.asin
    CROSS JOIN b
    WHERE f.dt >= DATE_SUB(b.as_of, INTERVAL 90 DAY)
    GROUP BY f.cid, p.parent_name
  ) WHERE rn = 1
),
camp_family AS (
  SELECT c.cid, COALESCE(de.parent_name, cf.parent_name, 'Unknown') AS family
  FROM (SELECT DISTINCT cid FROM fa_camp) c
  LEFT JOIN `onyga-482313.OI.DE_CAMPAIGN_FAMILY` de ON CAST(de.campaign_id AS STRING) = c.cid
  LEFT JOIN camp_fam cf ON cf.cid = c.cid
),

-- ── 2. the change log, deduped to one row per logical change per LA day ─────────────────────
chg_raw AS (
  SELECT
    c.change_id, c.applied_at,
    DATE(c.applied_at, 'America/Los_Angeles')  AS change_date,
    c.action,
    NULLIF(CAST(c.keyword_id AS STRING), '')   AS keyword_id,
    LOWER(TRIM(NULLIF(TRIM(c.targeting), ''))) AS tgt_lc,
    CAST(c.campaign_id AS STRING)              AS cid,
    c.campaign_type
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED` c
  WHERE c.campaign_id IS NOT NULL
    AND DATE(c.applied_at, 'America/Los_Angeles')
        >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 120 DAY)
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY CAST(c.campaign_id AS STRING), c.action,
      COALESCE(NULLIF(CAST(c.keyword_id AS STRING), ''), LOWER(TRIM(COALESCE(c.targeting, ''))), ''),
      IFNULL(CAST(c.new_bid AS STRING), ''), IFNULL(CAST(c.new_budget AS STRING), ''),
      DATE(c.applied_at, 'America/Los_Angeles')
    ORDER BY c.applied_at, c.change_id
  ) = 1
),
chg AS (
  SELECT
    r.*,
    CASE
      WHEN r.action = 'REDUCE_BID'                                        THEN 'BID_DOWN'
      WHEN r.action IN ('INCREASE_BID','BOOST','SCALE_UP')                THEN 'BID_UP'
      WHEN r.action = 'STOP_TARGET'                                       THEN 'PAUSE_TARGET'
      WHEN r.action LIKE '%BUDGET%' THEN
        CASE WHEN r.action LIKE '%DECREASE%' OR r.action LIKE '%CONTAIN%' OR r.action LIKE '%DOWN%'
             THEN 'BUDGET_DOWN' ELSE 'BUDGET_UP' END
      WHEN r.action LIKE 'NEGATE%' OR r.action IN ('STOP_TERM','STOP')    THEN 'NEGATE'
      WHEN r.action IN ('REMOVE_NEGATIVE','REMOVE_CONFLICTING_NEGATIVE')  THEN 'UNNEGATE'
      WHEN r.action LIKE 'PROMOTE%' OR r.action LIKE 'ADD_%'
           OR r.action IN ('START_TERM','START')                          THEN 'ADD_TARGET'
      ELSE 'OTHER'
    END AS action_group,
    CASE
      WHEN UPPER(COALESCE(dc.campaign_type, '')) = 'SB'         THEN 'SB'
      WHEN UPPER(COALESCE(dc.campaign_type, '')) = 'SP'         THEN 'SP'
      WHEN UPPER(COALESCE(r.campaign_type, '')) LIKE '%BRAND%'  THEN 'SB'
      WHEN UPPER(COALESCE(r.campaign_type, '')) = 'SB'          THEN 'SB'
      ELSE 'SP'
    END AS channel
  FROM chg_raw r
  LEFT JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` dc
    ON CAST(dc.campaign_id AS STRING) = r.cid
),

-- ── 3. cohorts = decisions whose 14-day post window has fully SETTLED (SP T+21 / SB T+28) ────
cohort_all AS (
  SELECT c.*, s.scope_name, s.scope_ord, b.as_of, b.cohort_end, b.sb_gate_end,
         DATE_SUB(b.cohort_end, INTERVAL s.decision_days - 1 DAY) AS cohort_start
  FROM chg c CROSS JOIN b CROSS JOIN scopes s
  WHERE c.change_date BETWEEN DATE_SUB(b.cohort_end, INTERVAL s.decision_days - 1 DAY)
                         AND b.cohort_end
),
cohort AS (
  SELECT * FROM cohort_all
  WHERE (channel = 'SP') OR (channel = 'SB' AND change_date <= sb_gate_end)
),

-- ── 4. one measured UNIT per (scope, entity): earliest change in the window wins, so a keyword
--       touched twice is counted ONCE. An additive dollar total cannot double-count the same
--       dollars the way V_CHANGE_SCORECARD's flag-don't-drop policy can afford to. ────────────
unit_raw AS (
  SELECT
    c.scope_name, c.scope_ord,
    CASE WHEN c.action_group IN ('BID_DOWN','BID_UP','PAUSE_TARGET') THEN 'TARGET'
         WHEN c.action_group IN ('BUDGET_UP','BUDGET_DOWN')          THEN 'CAMPAIGN'
         ELSE 'UNMEASURABLE' END                                     AS scope_grain,
    c.cid,
    IF(ki.kid IS NOT NULL, c.keyword_id, NULL)                       AS kid_use,
    IF(ki.kid IS NULL, c.tgt_lc, NULL)                               AS tgt_use,
    c.change_date, c.action_group, c.channel, c.change_id
  FROM cohort c
  LEFT JOIN kid_index ki ON ki.cid = c.cid AND ki.kid = c.keyword_id
),
unit AS (
  SELECT
    CONCAT(scope_name, '|', scope_grain, '|', cid, '|',
           CASE scope_grain WHEN 'CAMPAIGN' THEN '' ELSE COALESCE(kid_use, tgt_use, '') END) AS entity_key,
    scope_name, scope_ord, scope_grain, cid, kid_use, tgt_use, change_date,
    action_group, channel, n_touches
  FROM (
    SELECT u.*, COUNT(*) OVER (PARTITION BY u.scope_name, u.scope_grain, u.cid,
                    CASE u.scope_grain WHEN 'CAMPAIGN' THEN '' ELSE COALESCE(u.kid_use, u.tgt_use, '') END)
                AS n_touches
    FROM unit_raw u
    WHERE u.scope_grain IN ('TARGET','CAMPAIGN')
      AND (u.scope_grain = 'CAMPAIGN' OR COALESCE(u.kid_use, u.tgt_use) IS NOT NULL)
  ) u
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY scope_name, scope_grain, cid,
      CASE scope_grain WHEN 'CAMPAIGN' THEN '' ELSE COALESCE(kid_use, tgt_use, '') END
    ORDER BY change_date, action_group, change_id
  ) = 1
),

-- ── 5. the real anchor plus 5 PLACEBO anchors: identical units, identical rules, shifted back
--       to a time when nothing had been done to them, where the true effect is EXACTLY zero ────
anchored AS (
  SELECT u.*, o.placebo_offset,
         DATE_SUB(u.change_date, INTERVAL o.placebo_offset DAY) AS t_eff,
         DATE_SUB(DATE_SUB(u.change_date, INTERVAL o.placebo_offset DAY), INTERVAL 14 DAY) AS pre_s,
         DATE_SUB(DATE_SUB(u.change_date, INTERVAL o.placebo_offset DAY), INTERVAL  1 DAY) AS pre_e,
         DATE_ADD(DATE_SUB(u.change_date, INTERVAL o.placebo_offset DAY), INTERVAL  1 DAY) AS post_s,
         DATE_ADD(DATE_SUB(u.change_date, INTERVAL o.placebo_offset DAY), INTERVAL 14 DAY) AS post_e
  FROM unit u CROSS JOIN offsets o
),

-- ── 6. the panel, at each unit's own grain ──────────────────────────────────────────────────
panel AS (
  SELECT a.entity_key, a.placebo_offset, f.dt, f.clk, f.cost, f.gp
  FROM anchored a JOIN fa_kid f ON f.cid = a.cid AND f.kid = a.kid_use
   AND f.dt BETWEEN a.pre_s AND a.post_e
  WHERE a.scope_grain = 'TARGET' AND a.kid_use IS NOT NULL
  UNION ALL
  SELECT a.entity_key, a.placebo_offset, f.dt, f.clk, f.cost, f.gp
  FROM anchored a JOIN fa_tgt f ON f.cid = a.cid AND f.tgt_lc = a.tgt_use
   AND f.dt BETWEEN a.pre_s AND a.post_e
  WHERE a.scope_grain = 'TARGET' AND a.kid_use IS NULL
  UNION ALL
  SELECT a.entity_key, a.placebo_offset, f.dt, f.clk, f.cost, f.gp
  FROM anchored a JOIN fa_camp f ON f.cid = a.cid
   AND f.dt BETWEEN a.pre_s AND a.post_e
  WHERE a.scope_grain = 'CAMPAIGN'
),

-- ── 7. the LAST-YEAR seasonal yardstick, account-wide, per anchor date ──────────────────────
season AS (
  SELECT
    t.t_eff,
    SUM(IF(ad.dt BETWEEN DATE_SUB(t.t_eff, INTERVAL 378 DAY)
                     AND DATE_SUB(t.t_eff, INTERVAL 365 DAY), ad.gp - ad.cost, 0)) AS ly_pre_dollars,
    SUM(IF(ad.dt BETWEEN DATE_SUB(t.t_eff, INTERVAL 378 DAY)
                     AND DATE_SUB(t.t_eff, INTERVAL 365 DAY), ad.cost, 0))         AS ly_pre_spend,
    SUM(IF(ad.dt BETWEEN DATE_SUB(t.t_eff, INTERVAL 363 DAY)
                     AND DATE_SUB(t.t_eff, INTERVAL 350 DAY), ad.gp - ad.cost, 0)) AS ly_post_dollars
  FROM (SELECT DISTINCT t_eff FROM anchored) t
  JOIN acct_day ad
    ON ad.dt BETWEEN DATE_SUB(t.t_eff, INTERVAL 378 DAY) AND DATE_SUB(t.t_eff, INTERVAL 350 DAY)
  GROUP BY 1
),
season_rate AS (
  SELECT t_eff,
         SAFE_DIVIDE(ly_post_dollars - ly_pre_dollars, NULLIF(ly_pre_spend, 0)) AS rate
  FROM season
),

-- ── 8. per-unit pre/post and effect ─────────────────────────────────────────────────────────
unit_agg AS (
  SELECT
    a.entity_key, a.placebo_offset, a.scope_name, a.scope_ord, a.scope_grain, a.cid,
    a.change_date, a.t_eff, a.action_group, a.channel, a.n_touches,
    SUM(IF(p.dt BETWEEN a.pre_s  AND a.pre_e,  p.gp - p.cost, 0)) AS pre_dollars,
    SUM(IF(p.dt BETWEEN a.pre_s  AND a.pre_e,  p.cost,        0)) AS pre_spend,
    SUM(IF(p.dt BETWEEN a.pre_s  AND a.pre_e,  p.clk,         0)) AS pre_clicks,
    SUM(IF(p.dt BETWEEN a.post_s AND a.post_e, p.gp - p.cost, 0)) AS post_dollars,
    SUM(IF(p.dt BETWEEN a.post_s AND a.post_e, p.cost,        0)) AS post_spend,
    SUM(IF(p.dt BETWEEN a.post_s AND a.post_e, p.clk,         0)) AS post_clicks,
    COUNT(p.dt)                                                   AS panel_rows
  FROM anchored a
  LEFT JOIN panel p ON p.entity_key = a.entity_key AND p.placebo_offset = a.placebo_offset
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11
),
-- eligibility is decided ONCE at the REAL anchor and then applied to every placebo anchor, so the
-- placebo measures the same population the estimate does. Anything else compares two cohorts.
eligible AS (
  SELECT entity_key FROM unit_agg
  WHERE placebo_offset = 0 AND pre_clicks >= (SELECT min_pre_clicks FROM b)
),
eff AS (
  SELECT
    ua.*,
    COALESCE(sr.rate, 0) * ua.pre_spend                                      AS season_expected,
    (ua.post_dollars - ua.pre_dollars) - COALESCE(sr.rate, 0) * ua.pre_spend AS effect,
    COALESCE(cf.family, 'Unknown') AS family,
    -- LAUNCH = campaign age <= 90 days at the change date (the V_LAUNCH_POPULATION definition).
    -- The FAMILY-level launch exemption (V_LAUNCH_EXEMPTION, family_age_months <= 12: LolliBall and
    -- Bunny) is deliberately NOT applied here: that view scans FACT_AMAZON_ADS itself and inlining
    -- it would break the one-scan rule. A first attempt to proxy it from this view's own scan was
    -- built, RUN, and REMOVED because it was wrong -- family first-seen is right-censored by the
    -- 500-day scan AND the family map only covers campaigns active in the last 90 days, so the
    -- reorg made every family look newly born and the stratum came back 100% LAUNCH. The launch
    -- FAMILIES are visible on the FAMILY stratum instead, where they are named.
    IF(DATE_DIFF(ua.change_date, cfi.first_dt, DAY) <= 90, 'LAUNCH', 'ESTABLISHED') AS launch_label,
    IF(ua.n_touches > 1, 'MULTI_TOUCH', 'SINGLE_TOUCH') AS touch_label,
    -- a campaign younger than the pre-window has no pre-window: post-minus-pre is its RAMP
    IF(DATE_DIFF(ua.change_date, cfi.first_dt, DAY) >= 14,
       'PRE_WINDOW_VALID', 'PRE_WINDOW_PREDATES_CAMPAIGN') AS pre_window_label
  FROM unit_agg ua
  JOIN eligible e USING (entity_key)
  LEFT JOIN season_rate sr ON sr.t_eff = ua.t_eff
  LEFT JOIN camp_family cf ON cf.cid = ua.cid
  LEFT JOIN camp_first cfi ON cfi.cid = ua.cid
),

-- ── 9. strata (long form). TARGET rows are additive with each other; CAMPAIGN budget rows are
--       NOT -- their keywords are already counted on the TARGET lines. ─────────────────────────
strat AS (
  SELECT 'ACCOUNT' AS stratum_type, 'ALL BID DECISIONS (keyword grain)' AS stratum,
         TRUE AS is_additive, e.* FROM eff e WHERE e.scope_grain = 'TARGET'
  UNION ALL SELECT 'LAUNCH',      e.launch_label,     TRUE, e.* FROM eff e WHERE e.scope_grain='TARGET'
  UNION ALL SELECT 'CHANNEL',     e.channel,          TRUE, e.* FROM eff e WHERE e.scope_grain='TARGET'
  UNION ALL SELECT 'ACTION_ARM',  e.action_group,     TRUE, e.* FROM eff e WHERE e.scope_grain='TARGET'
  UNION ALL SELECT 'TOUCH',       e.touch_label,      TRUE, e.* FROM eff e WHERE e.scope_grain='TARGET'
  UNION ALL SELECT 'PRE_WINDOW',  e.pre_window_label, TRUE, e.* FROM eff e WHERE e.scope_grain='TARGET'
  UNION ALL SELECT 'FAMILY',      e.family,           TRUE, e.* FROM eff e WHERE e.scope_grain='TARGET'
  UNION ALL SELECT 'BUDGET_CAMPAIGN_GRAIN',
                   CONCAT('BUDGET (', e.action_group, ') - NON-ADDITIVE'), FALSE, e.*
            FROM eff e WHERE e.scope_grain = 'CAMPAIGN'
),
agg AS (
  SELECT
    scope_name, scope_ord, stratum_type, stratum, is_additive, placebo_offset,
    COUNT(*)                                   AS n_units,
    COUNTIF(pre_clicks >= 10)                  AS n_units_with_pre_data,
    SUM(effect)                                AS eff_sum,
    STDDEV_SAMP(CAST(effect AS FLOAT64))       AS eff_sd,
    SUM(pre_dollars)                           AS pre_dollars,
    SUM(post_dollars)                          AS post_dollars,
    SUM(pre_spend)                             AS pre_spend,
    SUM(post_spend)                            AS post_spend,
    SUM(season_expected)                       AS season_expected,
    SUM(pre_clicks)                            AS pre_clicks,
    SUM(post_clicks)                           AS post_clicks
  FROM strat
  GROUP BY 1,2,3,4,5,6
),
pivoted AS (
  SELECT
    scope_name, scope_ord, stratum_type, stratum, is_additive,
    MAX(IF(placebo_offset = 0, n_units, NULL))                              AS n_units,
    CAST(MAX(IF(placebo_offset = 0, pre_dollars,     NULL)) AS FLOAT64)      AS pre_dollars,
    CAST(MAX(IF(placebo_offset = 0, post_dollars,    NULL)) AS FLOAT64)      AS post_dollars,
    CAST(MAX(IF(placebo_offset = 0, pre_spend,       NULL)) AS FLOAT64)      AS pre_spend,
    CAST(MAX(IF(placebo_offset = 0, post_spend,      NULL)) AS FLOAT64)      AS post_spend,
    MAX(IF(placebo_offset = 0, pre_clicks,  NULL))                           AS pre_clicks,
    MAX(IF(placebo_offset = 0, post_clicks, NULL))                           AS post_clicks,
    CAST(MAX(IF(placebo_offset = 0, season_expected, NULL)) AS FLOAT64)      AS season_expected_dollars,
    CAST(MAX(IF(placebo_offset = 0, eff_sum,         NULL)) AS FLOAT64)      AS incremental_dollars,
    MAX(IF(placebo_offset = 0, eff_sd * SQRT(n_units), NULL))                AS se_keywords,
    CAST(AVG(IF(placebo_offset > 0, eff_sum, NULL))         AS FLOAT64)      AS placebo_mean,
    CAST(STDDEV_SAMP(IF(placebo_offset > 0, eff_sum, NULL)) AS FLOAT64)      AS placebo_sd,
    CAST(MIN(IF(placebo_offset > 0, eff_sum, NULL))         AS FLOAT64)      AS placebo_min,
    CAST(MAX(IF(placebo_offset > 0, eff_sum, NULL))         AS FLOAT64)      AS placebo_max,
    COUNTIF(placebo_offset > 0)                                AS n_placebo_anchors,
    SAFE_DIVIDE(SUM(IF(placebo_offset > 0, n_units_with_pre_data, 0)),
                NULLIF(SUM(IF(placebo_offset > 0, n_units, 0)), 0)) AS placebo_coverage
  FROM agg
  GROUP BY 1,2,3,4,5
),
-- THE BAND. If the placebo anchors land before the units existed, the placebo is VACUOUS and is
-- discarded rather than allowed to certify a falsely tight interval.
banded AS (
  SELECT
    p.*,
    (p.placebo_coverage >= (SELECT min_placebo_coverage FROM b)) AS placebo_usable,
    IF(p.placebo_coverage >= (SELECT min_placebo_coverage FROM b),
       1.96 * SQRT(POW(COALESCE(p.se_keywords,0),2) + POW(COALESCE(p.placebo_sd,0),2))
         + ABS(COALESCE(p.placebo_mean,0)),
       1.96 * COALESCE(p.se_keywords,0)) AS band_halfwidth
  FROM pivoted p
),

-- ── 10. coverage: what the estimate rests on, and what it could NOT cover ───────────────────
cov_chg AS (
  SELECT ca.scope_name,
         COUNT(*)                                                                   AS changes_in_cohort,
         COUNTIF(ca.channel = 'SP' OR ca.change_date <= ca.sb_gate_end)             AS changes_settled,
         COUNTIF(ca.channel = 'SB' AND ca.change_date > ca.sb_gate_end)             AS changes_sb_unsettled,
         COUNTIF((ca.channel = 'SP' OR ca.change_date <= ca.sb_gate_end)
                 AND ca.action_group IN ('NEGATE','UNNEGATE','ADD_TARGET','OTHER')) AS changes_unmeasurable_kind
  FROM cohort_all ca GROUP BY 1
),
cov_recent AS (
  SELECT COUNT(*) AS changes_too_recent FROM chg c CROSS JOIN b bb WHERE c.change_date > bb.cohort_end
),
cov_unit AS (
  SELECT u.scope_name, COUNTIF(u.scope_grain = 'TARGET') AS targets_in_cohort
  FROM unit u GROUP BY 1
),
cov_judged AS (
  SELECT ua.scope_name,
         COUNTIF(e.entity_key IS NOT NULL)                                          AS units_judged,
         COUNTIF(ua.panel_rows = 0)                                                 AS units_unmatched_in_fact,
         COUNTIF(ua.panel_rows > 0 AND ua.pre_clicks < 10)                          AS units_thin_pre_window
  FROM unit_agg ua LEFT JOIN eligible e USING (entity_key)
  WHERE ua.placebo_offset = 0 AND ua.scope_grain = 'TARGET'
  GROUP BY 1
),
cov AS (
  SELECT s.scope_name,
         COALESCE(cc.changes_in_cohort, 0)         AS changes_in_cohort,
         COALESCE(cc.changes_settled, 0)           AS changes_settled,
         COALESCE(cc.changes_sb_unsettled, 0)      AS changes_sb_unsettled,
         cr.changes_too_recent,
         COALESCE(cc.changes_unmeasurable_kind, 0) AS changes_unmeasurable_kind,
         COALESCE(cu.targets_in_cohort, 0)         AS targets_in_cohort,
         COALESCE(cj.units_judged, 0)              AS units_judged,
         COALESCE(cj.units_unmatched_in_fact, 0)   AS units_unmatched_in_fact,
         COALESCE(cj.units_thin_pre_window, 0)     AS units_thin_pre_window
  FROM scopes s
  CROSS JOIN cov_recent cr
  LEFT JOIN cov_chg    cc ON cc.scope_name = s.scope_name
  LEFT JOIN cov_unit   cu ON cu.scope_name = s.scope_name
  LEFT JOIN cov_judged cj ON cj.scope_name = s.scope_name
)

SELECT
  bb.as_of                                                         AS as_of_date,
  p.scope_name                                                     AS scope,
  DATE_SUB(bb.cohort_end, INTERVAL IF(p.scope_name='ROLLING_14D',13,59) DAY) AS decision_window_start,
  bb.cohort_end                                                    AS decision_window_end,
  DATE_DIFF(bb.as_of, bb.cohort_end, DAY)                          AS decision_staleness_days,
  'SEASON_ADJUSTED_BEFORE_AFTER_WITH_PLACEBO_BAND'                 AS estimator,
  TRUE                                                             AS downgraded_from_did,
  CONCAT('Matched keyword-grain DiD was tested and REJECTED before build. Parallel trends is ',
         'FALSIFIED: pre-trend correlation of daily dollar deltas is -0.137 and -0.673, i.e. ',
         'treated and control move in OPPOSITE directions before treatment. A placebo replicating ',
         'the engine own selection rule with ZERO intervention fabricates +$1,505..+$2,445 on the ',
         'losers arm and -$1,094..-$1,829 on the winners arm, roughly 90% of the account entire ',
         '14-day dollar magnitude. Matching fails for 98.1% of treated keywords; the clean control ',
         'pool on the live window is 7 keywords / $819 against a treated arm of $29,326; 56-63% of ',
         'would-be controls share a campaign budget with a treated keyword (SUTVA). Synthetic ',
         'control was rejected too: donor-pool membership is CAUSED by the outcome and donor clicks ',
         'fell 83% over the fit window. THIS VIEW IS THEREFORE A MONITOR, NOT A CAUSAL ESTIMATE: ',
         'season-adjusted before/after, reported with its own measured placebo bias as the error ',
         'bar, an UPPER BOUND ON KNOWLEDGE. It cannot see budget reallocation, cannibalisation or ',
         'organic halo, and it does not remove selection on the outcome - it only measures it. The ',
         'only real fix is a randomised hold-out of 15-20% of eligible keywords per upload.')
                                                                   AS downgrade_reason,
  p.stratum_type,
  p.stratum,
  p.is_additive,
  p.n_units,
  ROUND(p.pre_dollars, 2)                                          AS pre_dollars,
  ROUND(p.post_dollars, 2)                                         AS post_dollars,
  ROUND(p.post_dollars - p.pre_dollars, 2)                         AS naive_delta_dollars,
  ROUND(p.pre_spend, 2)                                            AS pre_spend_dollars,
  ROUND(p.post_spend, 2)                                           AS post_spend_dollars,
  ROUND(p.season_expected_dollars, 2)                              AS season_expected_dollars,
  -- the seasonal adjustment can be LARGER than the naive delta; this is the rate it rests on, so
  -- the number can be audited rather than trusted. One prior year only (ads start 2024-09-05).
  ROUND(SAFE_DIVIDE(p.season_expected_dollars, NULLIF(p.pre_spend, 0)), 4) AS season_rate_implied,
  ROUND(p.incremental_dollars, 2)                                  AS incremental_dollars,
  ROUND(p.se_keywords, 2)                                          AS se_keywords,
  ROUND(p.placebo_mean, 2)                                         AS placebo_bias_dollars,
  ROUND(p.placebo_sd, 2)                                           AS placebo_sd_dollars,
  ROUND(p.placebo_min, 2)                                          AS placebo_min_dollars,
  ROUND(p.placebo_max, 2)                                          AS placebo_max_dollars,
  p.n_placebo_anchors,
  ROUND(p.placebo_coverage, 3)                                     AS placebo_coverage_pct,
  IF(p.placebo_usable, 'PLACEBO+SAMPLING',
     'SAMPLING ONLY - LOWER BOUND ON UNCERTAINTY (placebo anchors predate the units)')
                                                                   AS band_basis,
  ROUND(p.band_halfwidth, 2)                                       AS band_halfwidth_dollars,
  ROUND(p.incremental_dollars - p.band_halfwidth, 2)               AS band_low_dollars,
  ROUND(p.incremental_dollars + p.band_halfwidth, 2)               AS band_high_dollars,
  CASE
    WHEN p.n_units < 5                                       THEN 'TOO FEW UNITS TO SAY ANYTHING'
    WHEN NOT p.placebo_usable                                THEN 'NOT REPORTABLE AS A RESULT - NO VALID PLACEBO ANCHOR (band is a lower bound only)'
    WHEN p.incremental_dollars - p.band_halfwidth > 0        THEN 'ABOVE NOISE BAND (POSITIVE)'
    WHEN p.incremental_dollars + p.band_halfwidth < 0        THEN 'BELOW NOISE BAND (NEGATIVE)'
    ELSE 'INSIDE NOISE - CANNOT DISTINGUISH FROM DOING NOTHING'
  END                                                              AS verdict,
  c.changes_in_cohort,
  c.changes_settled,
  c.changes_sb_unsettled,
  c.changes_too_recent            AS changes_too_early_to_judge,
  c.changes_unmeasurable_kind     AS changes_negate_or_addtarget_not_measurable,
  c.targets_in_cohort,
  c.units_judged,
  c.units_unmatched_in_fact,
  c.units_thin_pre_window
FROM banded p
CROSS JOIN b bb
JOIN cov c ON c.scope_name = p.scope_name
ORDER BY
  p.scope_ord,
  CASE p.stratum_type WHEN 'ACCOUNT' THEN 0 WHEN 'PRE_WINDOW' THEN 1 WHEN 'LAUNCH' THEN 2
       WHEN 'CHANNEL' THEN 3 WHEN 'ACTION_ARM' THEN 4 WHEN 'TOUCH' THEN 5
       WHEN 'FAMILY' THEN 6 ELSE 7 END,
  p.stratum;
