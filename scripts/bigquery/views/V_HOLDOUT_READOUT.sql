-- =============================================
-- V_HOLDOUT_READOUT — the answer. Spec: architecture/HOLDOUT.md.
--
-- THE QUESTION, in Ori's words: "the main goal of ads is to make more total dollars that we would
-- do without the changes." This view is the only object in the stack that tries to answer it with
-- a control group that actually exists.
--
-- ── WHICH TRIAL (holdout restart, 2026-10-05; plan docs/superpowers/plans/2026-10-03-holdout-restart.md
-- Task 6) ──────────────────────────────────────────────────────────────────────────────────────
-- The view serves THE LIVE TRIAL: CTE k reads its row of V_HOLDOUT_TRIAL (registry DE_HOLDOUT_TRIAL,
-- newest assigned_on on a tie), the row V_ENGINE_HEALTH holdout_unit_changed and SP_ASSIGN_HOLDOUT
-- read. Nothing else in the body names a trial. From 2026-10-05 that is trial 2:
--   trial_id HOLDOUT-2026Q4-CAMPAIGN-T2, seed OI-HOLDOUT-v2|5, 59 campaigns, 12 HOLDOUT clusters;
--   gate (the export block) from 2026-10-05; window 2026-10-06 .. 2027-01-26; interim safety look
--   2026-12-15 (a one-time hand query, HOLDOUT.md §8); FIRST READOUT 2027-02-09, never pulled forward.
--   t_mult 3.27 is carried from trial 1's design; it was not re-derived for 12 clusters.
--   Ex-ante MDE $2,089 per 14 days: trial 1's $2,261 rescaled by N*sqrt(1/h + 1/t) on trial 1's
--   noise floor. A larger multiplier for 12 clusters would raise it, so read it as a floor.
--   The pre-period: -$1,868.51 per 14 days is HALF THE DRAW'S 28-DAY NET (-$3,737.02 / 2, read
--   2026-10-03), the convention trial 1 used (net_28d_at_assign / 2 below); it is not a measured
--   14-day net. FACT_AMAZON_ADS summed over the 59 campaigns for 2026-09-19 .. 10-02 read -$2,052.52
--   (read 2026-10-04; FACT restates as days settle: the same 28 days read -$4,145.07 that day). Either
--   way the MDE is about 1.0-1.1x the whole quantity being measured, so the warning below applies to
--   trial 2 unchanged.
-- Trial 1 (HOLDOUT-2026Q4-CAMPAIGN) is ARCHIVED from 2026-10-05, contaminated (DE_HOLDOUT_TRIAL's
-- ARCHIVED row, HOLDOUT.md §6). Its 69 rows stay in DE_HOLDOUT_ASSIGNMENT unchanged and this view no
-- longer computes it. Every number in the sections below is TRIAL 1's, as designed and measured
-- before the restart; they are kept as the record.
-- MEASURED 2026-10-04 ~05:50 UTC (LA 2026-10-03) on TMP_HT2_ copies (this body, comment lines
-- stripped, names sed-pointed at copies; all dropped afterwards): over the deploy's registry rows and
-- the founding cohort, 1 row, NOT_YET, "not enough data yet — first readout 2027-02-09", no CENSORED
-- or PRE_WINDOW_CHANGE row; over an empty registry, 0 rows; over a registry holding trial 1's OPENED
-- row only, the same 69 rows as the deployed view (1 NOT_YET, 61 CENSORED, 7 PRE_WINDOW_CHANGE; 0 rows
-- differ either way, compared as whole rows). Unit branches (CENSORED + PRE_WINDOW_CHANGE) read once:
-- deployed 102.0 slot-s, this body on the copies 251.3 slot-s; V_HOLDOUT_TRIAL is planned again at
-- every reference of k.
--
-- ── TRIAL 1 (archived): READ THIS BEFORE READING ANY NUMBER BELOW ───────────────────────────────
-- THIS IS A HARM DETECTOR, NOT A VALUE CERTIFIER. The design's minimum detectable effect at the
-- chosen cell (20% share, 16 weeks, 14 holdout clusters) is $2,261 per 14 days. The eligible
-- population's ENTIRE 14-day net profit is about -$1,288. The MDE is 1.76x the whole quantity
-- being measured. Concretely:
--   · an engine adding 7% of ad spend (~$900 per 14 days) is COMPLETELY INVISIBLE here — detecting
--     it at this share would take 106 weeks;
--   · detecting $1,300 needs 50 weeks; detecting $1,800 needs 26 weeks;
--   · the precision ceiling is scale-invariant, so a bigger or smaller slice does not rescue it
--     (drop the top-1 campaign: MDE is 18% of covered spend; top-3: 18%; top-5: 19%; whole
--     population: 17%). The skew is not the binding constraint — the noise-to-signal ratio of
--     14-day net profit at this account's size is.
-- Therefore a result of "no detectable difference" is NOT a verdict that the engine is worthless.
-- It is a verdict that THE INSTRUMENT CANNOT SEE IT, and the verdict sentence this view emits says
-- exactly that. The one hypothesis this trial CAN settle inside a quarter is "the engine is doing
-- large harm" — which is live and plausible: the account's 14-day net has moved from +$3,439 to
-- -$2,470 over four months while the engine ran, and Ori's own scorecard measured account raises
-- at -$752 against cuts at +$3,051.
--
-- ── WHY THE VIEW PRINTS NOTHING UNTIL THE FIRST READOUT (trial 2: 2027-02-09; trial 1 was 2027-01-05)
-- Before k.first_readout this view returns exactly ONE estimate row, state NOT_YET, every
-- numeric column NULL (v27.162: beside it, one CENSORED row per censored unit and one
-- PRE_WINDOW_CHANGE row per HOLDOUT unit changed before its window, which carry dates and a reason
-- and no number — see "CONTAMINATION AND CENSORING" below). That is deliberate and it
-- is not paternalism:
--   · Ads spend settles ~D+3 and sales accrue to D+7/D+14 (fact_oi_ads_restatement_settle). The
--     TREATED arm has more recent changes than the holdout arm by construction, so reading early
--     systematically UNDERSTATES the treated arm's sales. The readout date already contains the
--     14-day settle. Do not pull it forward.
--   · A daily-readable estimate on an underpowered trial WILL be read early and over-interpreted.
--     The first plausible-looking number becomes the answer. The interim SAFETY look (trial 2:
--     2026-12-15; trial 1 was 2026-11-10, 8 weeks observed, able to detect harm above $3,133 per 14
--     days only) is a CIRCUIT BREAKER, not a verdict, and it is a deliberate one-time hand query
--     documented in HOLDOUT.md — not something this standing view leaks every morning.
--
-- ── WHAT IS BEING COMPARED ───────────────────────────────────────────────────────────────────
-- Unit: the CAMPAIGN (see V_HOLDOUT_ELIGIBLE for why not the keyword — holding out a keyword
-- inside a capped campaign re-routes its budget to its TREATED neighbours, which is a SUTVA
-- violation that flatters the treated arm).
-- Outcome: DOLLARS = SUM(GROSS_PROFIT) - SUM(Ads_cost) from FACT_AMAZON_ADS, one paired source for
-- both channels, normalised to a 14-day rate. GROSS_PROFIT is READ, never recomputed (THE GP RULE).
-- Baseline: net_28d_at_assign, frozen in DE_HOLDOUT_ASSIGNMENT on the assignment date — so the
-- change-score estimate below is computed against a pre-period that existed BEFORE the coin flip
-- and cannot have been contaminated by it.
-- Split: by the engine's INTENDED action class, taken from FACT_ENGINE_PROPOSALS. This is the
-- point of the whole architecture — SP_ENGINE_PREFLIGHT blocks the EXPORT for a holdout campaign
-- but the proposal is still RECORDED with its intended action, so the readout can compare
-- "the engine wanted to cut AND we cut" against "the engine wanted to cut AND the coin said don't".
-- Without that record the holdout arm would be a black box.
--
-- ── TWO ESTIMATES, AND WHY BOTH ──────────────────────────────────────────────────────────────
-- diff_raw      = mean 14-day dollars per TREATED campaign minus the same for HOLDOUT. Unbiased
--                 under randomization, and it makes no assumption at all.
-- diff_adjusted = the same difference computed on CHANGE SCORES (window 14-day rate minus the
--                 frozen pre-period 14-day rate). Also unbiased under randomization, and it strips
--                 the realized pre-period level gap. That gap is real and must be looked at: on the
--                 assignment date the holdout arm ran at -$0.053 of net per ad dollar and the
--                 treated arm at -$0.110 — chance, but a chance worth ~$146 per 14 days, i.e. ~6%
--                 of the MDE. If the two estimates disagree materially, the pre-period row below is
--                 where to look first.
-- Both are scaled to the account by multiplying the per-campaign difference by the number of
-- eligible units, because the question is about TOTAL dollars, not per-campaign dollars.
--
-- BAND: t_mult x SE(difference of means), with SE from the campaign-level spread inside each arm —
-- the campaign IS the cluster, so a plain two-sample SE at this grain already IS the cluster-robust
-- one. t_mult = 3.27 is the design's small-sample cluster multiplier for 14 clusters; a naive
-- t(0.975, 13) would be 2.16, so the published band is deliberately the conservative one. The
-- design's EX-ANTE MDE ($2,261 per 14 days) is published alongside it: if the realized band comes
-- back much wider, that is the peak-season variance the design warned about (expect 20-40% worse
-- than the table, since the window spans BFCM and the whole gift season).
--
-- INFERENCE CAVEAT, pre-registered: with 14 holdout clusters the right p-value is a PERMUTATION
-- p-value against the exact assignment distribution, permuted INSIDE the rerandomization acceptance
-- region (see DE_HOLDOUT_ASSIGNMENT), not a t-test. The band here is an orientation device. Also
-- pre-registered: a leave-one-out sensitivity check, because the largest eligible campaign is 11.2%
-- of the money on its own and one campaign's bad quarter moves the estimate materially.
--
-- SUBGROUP CAVEAT: the ALL row is the trial. The per-action-class rows are EXPLORATORY — the trial
-- is powered for the total and for nothing else, and every split multiplies the MDE. Read them as
-- directions to investigate, never as findings.
--
-- ── CONTAMINATION AND CENSORING (v27.162, 2026-10-03; piece-1 plan Task 8, ruling R9 = spec P-23) ─
-- HOLDOUT.md §6 #2: one instruction reaching a HOLDOUT campaign, from the engine or from a person,
-- contaminates that unit permanently. Ori ruled on 2026-10-02 (R9, option (a)) that a contaminated
-- unit AND its stratum-mates, in BOTH arms, are censored from the day of the contamination, so the
-- comparison inside the stratum stays fair (never pull only the holdout campaign).
--   contaminated_on  per HOLDOUT unit: the Los Angeles day of the first change on it inside
--                    [eligible_from, trial_end] that the change log records as applied
--                    (V_PPC_CHANGE_LOG_APPLIED) or the observed-change ledger records as seen on
--                    Amazon (FACT_PPC_CHANGE_LOG source OBSERVED: the DIM SCD2 trail, hand changes in
--                    the console included). A logged change and its observed landing are both read;
--                    the first of the two days counts. Day = DATE(applied_at, Los Angeles), the day
--                    every reader of the log uses. LIMIT: an SB keyword's observed instant is the
--                    Fivetran sync that first saw it, up to a day after the real change
--                    (V_AMAZON_OBSERVED_CHANGES header), so an SB keyword contamination can be dated
--                    one day late. PENDING_UPLOAD rows are not changes (a pending row that lands is
--                    observed); a book row naming a HOLDOUT campaign is seat_holdout_row_on_sheet's.
--   censored_from    per unit, both arms: the earliest contaminated_on of any HOLDOUT unit in the
--                    unit's stratum. From that day on the unit's dollars and proposals leave the
--                    estimate; it is rated on its own days before it (a unit with none drops out).
-- The view publishes one CENSORED row per censored unit — dates and the reason, never a dollar — so
-- the CENSORED rows exist before 2027-01-05 and leak nothing of the estimate. V_ENGINE_HEALTH
-- holdout_unit_changed READS them and turns RED when a change on a HOLDOUT unit has no censoring
-- here (HOLDOUT_INTEGRITY_acceptance.sql proves both on doctored copies).
-- MEASURED BEFORE DEPLOY (2026-10-03 ~08:00 UTC, this body run as a query, CENSORED rows listed):
-- R9 named two units, Ori's pauses of 2026-09-27 (BOX-SP/PHRASE (teen-girl-birthday-gift, White)
-- 75834491759416 and BOX-VIDEO/COMPETE (Copycat, Blue) 76054744633802, confirmed by Ori 2026-10-02).
-- INSIDE THE WINDOW the ledger holds changes on 8 of the 14 HOLDOUT units (25 rows, every one an
-- OBSERVED row with no log row behind it, first days 2026-09-10 .. 2026-09-27), so the rule censors
-- 6 of the 7 strata that hold a HOLDOUT unit: 61 of 69 units (13 of 14 HOLDOUT, 48 of 55 TREATED).
-- Untouched: stratum SB|CAP|LNC (1 HOLDOUT, 5 TREATED) and SB|CAP|GRD (no HOLDOUT, 2 TREATED). A
-- censored unit keeps 9 observed days (censored from 09-10: 09-01..09-09) to 26 (from 09-27). Ori
-- confirmed the two pauses; the other six units' changes are unconfirmed (HOLDOUT.md §6,
-- "Contamination"). No dollar was read: the estimate path was run only for unit counts and days.
-- That is NOT every change since the arms were frozen — see the next section.
--
-- ── CHANGES BEFORE THE WINDOW (v27.162 follow-up, 2026-10-03, review of commit a2e7e1e) ────────
-- The arms were frozen on 2026-08-19 (DE_HOLDOUT_ASSIGNMENT.assigned_at); the window, and R9's
-- censoring, start on eligible_from (2026-09-01); SP_ENGINE_PREFLIGHT's HOLDOUT arm also bites from
-- eligible_from only. Changes between the two are NOT censored. The plan's rule reads "after
-- eligible_from" and HOLDOUT.md §6 #2 says one upload contaminates a unit permanently; which governs
-- a change before the window start is a ruling for Ori, so this view does not decide it: it publishes
-- one PRE_WINDOW_CHANGE row per HOLDOUT unit changed from its assignment day (Los Angeles) to the day
-- before its eligible_from, with the changes day by day (logged and observed rows counted apart), the
-- days the estimate scores it as untouched, and no number; the ALL row's sentence (from 2027-01-05)
-- says how many there are. V_ENGINE_HEALTH holdout_unit_changed is AMBER while any stands and RED when
-- the ledger holds one this view does not publish.
-- MEASURED (2026-10-03, this body run as a query with state = 'PRE_WINDOW_CHANGE'; the acceptance's
-- `pre` statement lists the rows): 25 ledger rows on 7 HOLDOUT units before the window start —
--   FRESH-SP/PT (Competitors, Blue, A1) 135553284530895 and PILOT-WHITE-PHRASE-birthday-gifts
--     39989090923480, SP|UNC|LNC: CAMPAIGN_PAUSE on 2026-08-21, each 1 logged row (stop-20260821-*)
--     and 1 observed row confirming it. Neither has a change inside the window, so neither is a
--     contaminated unit under R9 today; their stratum is censored from 09-11, for another unit.
--   the 2026-08-23 reprice book (reprice_book_20260823_1527, logged and observed): BOTTLE-SP/AUTO
--     279837860088128 (SP|UNC|LNC, 2 REDUCE_BID), FRESH-VIDEO/ BROAD 446868628489343 (SB|UNC|GRD,
--     3 INCREASE_BID) and BOX-SP/PHRASE (teen-girl-birthday-gift, White) 75834491759416 (SP|UNC|LNC,
--     1 INCREASE_BID);
--   unlogged observed changes: BOX-SP/BROAD (Hunter, Gift for Girl) 200171414843593 (SP|CAP|GRD,
--     1 REDUCE_BID 08-25) and BOX-SP/AUTO (White) 488973733209950 (SP|UNC|GRD, 5 bid changes 08-26,
--     2 bid changes and 1 budget change 08-31).
-- Since the assignment, then, 10 of the 14 HOLDOUT units changed (7 before the window, 8 inside it,
-- 5 both). Had the rule counted from the assignment day instead (censored_from = GREATEST(first
-- change since assignment, eligible_from), measured by the same query on the strata): SP|UNC|LNC,
-- SP|UNC|GRD, SP|CAP|GRD and SB|UNC|GRD would be censored from 09-01 and drop out — 43 units, 9
-- HOLDOUT and 34 TREATED — leaving 26 units (5 HOLDOUT, 21 TREATED): SP|CAP|LNC censored from 09-11,
-- SB|UNC|LNC from 09-27, SB|CAP|LNC and SB|CAP|GRD untouched. That is Ori's call, not this view's.
-- COST (2026-10-03, each read twice): the CENSORED rows alone 6.5 / 20.2 slot-s (no FACT_AMAZON_ADS: the
-- estimate branch is gated off before 2027-01-05, and filtering state = 'CENSORED' prunes it after —
-- dry run with the gate date set to 2027-02-01: 403,245 bytes filtered, 47,636,110 unfiltered). The
-- estimate path, gate date set to 2027-02-01, counts only: v27.83 16.0 / 56.3 slot-s, this body
-- 252.0 / 153.8 slot-s, 27,053,628 bytes (FACT_AMAZON_ADS read once, joined to the 69-row cut).
-- Reproduce: HOLDOUT_INTEGRITY_acceptance.sql, temp tables `led` and `ro`.
-- COST of the follow-up (2026-10-03, deployed view): state = 'PRE_WINDOW_CHANGE' read twice 50.1 /
-- 25.6 slot-s, 318,457 bytes; dry runs with the gate date set to 2027-02-01: PRE_WINDOW_CHANGE
-- 318,457 bytes, CENSORED 403,245, unfiltered 47,687,197 — both unit branches prune FACT_AMAZON_ADS.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_HOLDOUT_READOUT` AS
WITH
-- ── THE LIVE TRIAL (holdout restart, 2026-10-05): its row of V_HOLDOUT_TRIAL, newest assigned_on on a
-- tie — the row V_ENGINE_HEALTH holdout_unit_changed and SP_ASSIGN_HOLDOUT read. win_start / win_end
-- = DE_HOLDOUT_ASSIGNMENT.eligible_from / trial_end of its rows; first_readout = win_end + the 14-day
-- settle, NEVER pulled forward; t_mult and mde_ex_ante_14d are the design's (header, "WHICH TRIAL").
-- No live trial: k is empty, and so is every row below (no NOT_YET row).
k AS (
  SELECT trial_id, win_start, win_end, first_readout, t_mult, mde_ex_ante_14d
  FROM `onyga-482313.OI.V_HOLDOUT_TRIAL`
  WHERE is_live
  QUALIFY ROW_NUMBER() OVER (ORDER BY assigned_on DESC, trial_id DESC) = 1
),
anchor AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
           FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
-- the frozen arms. Nothing here recomputes an arm; it only reads one.
asg AS (
  SELECT a.unit_id, a.unit_name, a.arm, a.stratum, a.channel, a.family,
         a.net_28d_at_assign, a.eligible_from, a.trial_end, a.assigned_at
  FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT` a, k
  WHERE a.trial_id = k.trial_id AND a.unit_type = 'CAMPAIGN'
),
-- the two sources of a change that reached Amazon: a change-log row that was applied, or a change
-- the observed-change ledger saw on Amazon (header, "CONTAMINATION AND CENSORING")
chg AS (
  SELECT campaign_id, applied_at, change_id, action, 'LOGGED, applied' AS landed_evidence
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
  UNION ALL
  SELECT campaign_id, applied_at, change_id, action,
         IF(STARTS_WITH(COALESCE(upload_note, ''), 'CONFIRMS '),
            'OBSERVED on Amazon, confirming a logged row', 'OBSERVED on Amazon, not logged')
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE source = 'OBSERVED'
),
-- R9: every change that reached Amazon on a HOLDOUT unit inside its trial window
touch AS (
  SELECT a.unit_id, a.stratum, DATE(l.applied_at, 'America/Los_Angeles') AS change_day,
         l.change_id, l.action, l.landed_evidence
  FROM asg a
  JOIN chg l ON l.campaign_id = a.unit_id
  WHERE a.arm = 'HOLDOUT'
    AND DATE(l.applied_at, 'America/Los_Angeles') BETWEEN a.eligible_from AND a.trial_end
),
-- v27.162 follow-up: every change that reached Amazon on a HOLDOUT unit from its assignment day to
-- the day before its window start. R9 does not censor these (it reads the window only); they are
-- published as PRE_WINDOW_CHANGE rows, a ruling for Ori (header, "CHANGES BEFORE THE WINDOW").
pre_touch AS (
  SELECT a.unit_id, l.applied_at, DATE(l.applied_at, 'America/Los_Angeles') AS change_day,
         l.change_id, l.action, STARTS_WITH(l.landed_evidence, 'LOGGED') AS is_logged
  FROM asg a
  JOIN chg l ON l.campaign_id = a.unit_id
  WHERE a.arm = 'HOLDOUT'
    AND DATE(l.applied_at, 'America/Los_Angeles') >= DATE(a.assigned_at, 'America/Los_Angeles')
    AND DATE(l.applied_at, 'America/Los_Angeles') < a.eligible_from
),
-- per HOLDOUT unit changed before its window: its first day and what changed, day by day
pre AS (
  SELECT unit_id, MIN(change_day) AS pre_window_change_on, SUM(n_logged + n_observed) AS n_rows,
         STRING_AGG(FORMAT('%t %s (%d logged, %d observed)', change_day, action, n_logged, n_observed),
                    '; ' ORDER BY change_day, first_at, action) AS changes
  FROM (SELECT unit_id, change_day, action, MIN(applied_at) AS first_at,
               COUNTIF(is_logged) AS n_logged, COUNTIF(NOT is_logged) AS n_observed
        FROM pre_touch GROUP BY 1, 2, 3)
  GROUP BY 1
),
-- per contaminated HOLDOUT unit: its first day, and the first change on it
contam AS (
  SELECT unit_id, stratum, MIN(change_day) AS contaminated_on, COUNT(*) AS n_changes,
         ARRAY_AGG(CONCAT(action, ', ', landed_evidence) ORDER BY change_day, change_id LIMIT 1)[OFFSET(0)] AS first_change
  FROM touch GROUP BY 1, 2
),
-- per stratum: censored from the earliest contamination of any HOLDOUT unit in it, and that unit
strat AS (
  SELECT c.stratum, MIN(c.contaminated_on) AS censored_from,
         ARRAY_AGG(FORMAT('%s (%s) changed on Amazon on %t: %s', a.unit_name, c.unit_id,
                          c.contaminated_on, c.first_change)
                   ORDER BY c.contaminated_on, c.unit_id LIMIT 1)[OFFSET(0)] AS censored_by
  FROM contam c JOIN asg a USING (unit_id)
  GROUP BY 1
),
-- per unit, both arms: the censoring the estimate applies and the CENSORED rows publish
ucens AS (
  SELECT a.unit_id, a.unit_name, a.arm, a.stratum,
         c.contaminated_on, c.n_changes, c.first_change, s.censored_from, s.censored_by
  FROM asg a
  LEFT JOIN contam c USING (unit_id)
  LEFT JOIN strat s ON s.stratum = a.stratum
),
-- observed days so far inside the window: the normaliser. LEAST(win_end, anchor) means a partial
-- window is rated, never silently summed as if it were complete.
win AS (
  SELECT k.win_start AS s,
         LEAST(k.win_end, anchor.d) AS e,
         DATE_DIFF(LEAST(k.win_end, anchor.d), k.win_start, DAY) + 1 AS n_days
  FROM k, anchor
),
-- outcome at the randomization unit's grain. One paired source: cost and GROSS_PROFIT off the same
-- FACT rows, so the subtraction can never straddle two differently-complete feeds.
-- v27.162 (R9): a censored unit's days from censored_from on are left out.
out AS (
  SELECT CAST(f.campaign_id AS STRING) AS unit_id,
         SUM(f.GROSS_PROFIT) - SUM(f.Ads_cost) AS dollars_window
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  CROSS JOIN win
  LEFT JOIN ucens u ON u.unit_id = CAST(f.campaign_id AS STRING)
  WHERE f.date BETWEEN win.s AND win.e
    AND (u.censored_from IS NULL OR f.date < u.censored_from)
  GROUP BY 1
),
-- THE COUNTERFACTUAL RECORD. FACT_ENGINE_PROPOSALS keeps the engine's intended action for HOLDOUT
-- campaigns too — SP_ENGINE_PREFLIGHT blocks their EXPORT, never their judgement. Without this the
-- holdout arm would be "campaigns nothing happened to" instead of "campaigns the engine wanted to
-- move and was forbidden from moving", and the split below would be impossible.
-- v27.98: the same doctrine now covers the LAST-DAY VETO. Until today a vetoed proposal was
-- ERASED rather than labelled — the veto rewrites the action to HOLD and NULLs the bid, which
-- broke the snapshot's filters — so the engine's intent on those keywords was invisible here too.
-- Held rows are recorded now, with the intended action in held_action and the intended value in
-- held_bid (never in suggested_bid, which would be an instruction). READING held_bid IS NOT
-- OPTIONAL: a held row has suggested_bid NULL, so without it every held RAISE would fall to the
-- ELSE branch and be counted as a BID_DOWN — the trial would split on the opposite of what the
-- engine wanted. This is also what makes the veto measurable inside a trial that is already
-- running: a holdout campaign whose engine wanted to raise and was vetoed is still, correctly, a
-- BID_UP unit.
prop AS (
  SELECT CAST(p.campaign_id AS STRING) AS unit_id,
    CASE
      WHEN p.grain = 'NEGATE' THEN 'NEGATE'
      WHEN p.grain = 'BUDGET' THEN IF(COALESCE(p.suggested_budget,0) > COALESCE(p.current_budget,0),
                                      'BUDGET_UP', 'BUDGET_DOWN')
      ELSE IF(COALESCE(p.held_bid, p.suggested_bid, 0) > COALESCE(p.current_bid,0),
              'BID_UP', 'BID_DOWN')
    END AS action_class,
    COUNT(*) AS n_prop
  FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS` p
  CROSS JOIN win
  LEFT JOIN ucens u ON u.unit_id = CAST(p.campaign_id AS STRING)
  WHERE p.snapshot_date BETWEEN win.s AND win.e
    AND (u.censored_from IS NULL OR p.snapshot_date < u.censored_from)   -- R9, as in `out`
  GROUP BY 1, 2
),
-- one class per unit: what the engine MOST wanted to do to this campaign over the window. A
-- campaign with no proposal at all is its own class — the engine had no opinion, so neither arm
-- was doing anything, and those units carry information about the noise floor and nothing else.
intent AS (
  SELECT unit_id, action_class
  FROM prop
  QUALIFY ROW_NUMBER() OVER (PARTITION BY unit_id ORDER BY n_prop DESC, action_class) = 1
),
-- v27.162 (R9): each unit is rated on its own observed days — the window, cut the day before its
-- censored_from — and a unit censored from the window's first day has none and drops out.
unit_days AS (
  SELECT a.*, o.dollars_window, i.action_class AS intent_class,
         DATE_DIFF(LEAST(w.e, COALESCE(DATE_SUB(u.censored_from, INTERVAL 1 DAY), w.e)), w.s, DAY) + 1 AS n_obs_days
  FROM asg a
  LEFT JOIN out o ON o.unit_id = a.unit_id
  LEFT JOIN intent i ON i.unit_id = a.unit_id
  LEFT JOIN ucens u ON u.unit_id = a.unit_id
  CROSS JOIN win w
),
unit AS (
  SELECT unit_id, arm, stratum, channel, family,
         COALESCE(intent_class, 'NO_PROPOSAL') AS action_class,
         COALESCE(dollars_window, 0) * 14.0 / n_obs_days   AS d14,
         net_28d_at_assign / 2.0                          AS pre14,
         COALESCE(dollars_window, 0) * 14.0 / n_obs_days
           - net_28d_at_assign / 2.0                      AS chg14
  FROM unit_days
  WHERE n_obs_days >= 1
),
-- how many units the censoring touches, and how many HOLDOUT units changed before the window, for
-- the ALL row's sentence
ncens AS (
  SELECT COUNTIF(censored_from IS NOT NULL) AS n_cens, COUNT(*) AS n_all,
         (SELECT COUNT(*) FROM pre) AS n_pre
  FROM ucens
),
-- per (class, arm) moments. The ALL row is the trial; the class rows are exploratory.
cell AS (
  SELECT 'ALL' AS action_class, arm, COUNT(*) n, AVG(d14) m, VAR_SAMP(d14) v,
         AVG(pre14) mpre, AVG(chg14) mchg, VAR_SAMP(chg14) vchg, SUM(d14) tot
  FROM unit GROUP BY 1, 2
  UNION ALL
  SELECT action_class, arm, COUNT(*), AVG(d14), VAR_SAMP(d14),
         AVG(pre14), AVG(chg14), VAR_SAMP(chg14), SUM(d14)
  FROM unit GROUP BY 1, 2
),
wide AS (
  SELECT c.action_class,
    MAX(IF(arm = 'HOLDOUT', n, NULL))    AS holdout_n,
    MAX(IF(arm = 'TREATED', n, NULL))    AS treated_n,
    MAX(IF(arm = 'HOLDOUT', tot, NULL))  AS holdout_dollars_14d,
    MAX(IF(arm = 'TREATED', tot, NULL))  AS treated_dollars_14d,
    MAX(IF(arm = 'HOLDOUT', m, NULL))    AS h_mean,
    MAX(IF(arm = 'TREATED', m, NULL))    AS t_mean,
    MAX(IF(arm = 'HOLDOUT', v, NULL))    AS h_var,
    MAX(IF(arm = 'TREATED', v, NULL))    AS t_var,
    MAX(IF(arm = 'HOLDOUT', mpre, NULL)) AS h_pre,
    MAX(IF(arm = 'TREATED', mpre, NULL)) AS t_pre,
    MAX(IF(arm = 'HOLDOUT', mchg, NULL)) AS h_chg,
    MAX(IF(arm = 'TREATED', mchg, NULL)) AS t_chg,
    MAX(IF(arm = 'HOLDOUT', vchg, NULL)) AS h_vchg,
    MAX(IF(arm = 'TREATED', vchg, NULL)) AS t_vchg
  FROM cell c GROUP BY 1
),
est AS (
  SELECT w.*,
    (w.holdout_n + w.treated_n) AS n_units,
    (w.t_mean - w.h_mean) * (w.holdout_n + w.treated_n) AS diff_raw_14d,
    (w.t_chg  - w.h_chg)  * (w.holdout_n + w.treated_n) AS diff_adjusted_14d,
    k.t_mult * SQRT(SAFE_DIVIDE(w.t_var, w.treated_n) + SAFE_DIVIDE(w.h_var, w.holdout_n))
             * (w.holdout_n + w.treated_n) AS band_95_14d,
    k.mde_ex_ante_14d, k.first_readout, k.win_start, k.win_end
  FROM wide w, k
)
-- ── GATE. Before first_readout: ONE row, no estimate, in as many words. ──────────────────────
SELECT
  0 AS row_rank,
  'NOT_YET' AS state,
  'ALL' AS action_class,
  CAST(NULL AS INT64)   AS holdout_n,
  CAST(NULL AS INT64)   AS treated_n,
  CAST(NULL AS FLOAT64) AS holdout_dollars_14d,
  CAST(NULL AS FLOAT64) AS treated_dollars_14d,
  CAST(NULL AS FLOAT64) AS holdout_pre_dollars_14d,
  CAST(NULL AS FLOAT64) AS treated_pre_dollars_14d,
  CAST(NULL AS FLOAT64) AS diff_raw_14d,
  CAST(NULL AS FLOAT64) AS diff_adjusted_14d,
  CAST(NULL AS FLOAT64) AS band_95_14d,
  CAST(NULL AS FLOAT64) AS mde_ex_ante_14d,
  FORMAT('not enough data yet — first readout %s', CAST(k.first_readout AS STRING)) AS verdict,
  -- v27.162: the unit columns, filled on CENSORED rows only
  CAST(NULL AS STRING)  AS unit_id,
  CAST(NULL AS STRING)  AS unit_name,
  CAST(NULL AS STRING)  AS arm,
  CAST(NULL AS STRING)  AS stratum,
  CAST(NULL AS DATE)    AS contaminated_on,
  CAST(NULL AS DATE)    AS censored_from,
  -- v27.162 follow-up: filled on PRE_WINDOW_CHANGE rows only
  CAST(NULL AS DATE)    AS pre_window_change_on
FROM k
WHERE CURRENT_DATE('America/Los_Angeles') < k.first_readout

UNION ALL

SELECT
  IF(e.action_class = 'ALL', 1, 2) AS row_rank,
  'READY' AS state,
  e.action_class,
  e.holdout_n, e.treated_n,
  ROUND(e.holdout_dollars_14d, 2), ROUND(e.treated_dollars_14d, 2),
  ROUND(e.h_pre * e.holdout_n, 2), ROUND(e.t_pre * e.treated_n, 2),
  ROUND(e.diff_raw_14d, 2), ROUND(e.diff_adjusted_14d, 2),
  ROUND(e.band_95_14d, 2), e.mde_ex_ante_14d,
  -- THE PLAIN SENTENCE. It always names the band before the estimate, because on this trial the
  -- band is the finding. v27.162: the ALL row also says how many units R9's censoring cut.
  CONCAT(CASE
    WHEN e.action_class <> 'ALL' THEN
      FORMAT('exploratory split, not a finding — the trial is powered for the total only. %s: engine arm %s vs holdout arm %s per 14 days across %d and %d campaigns.',
             e.action_class,
             FORMAT('$%.0f', e.treated_dollars_14d), FORMAT('$%.0f', e.holdout_dollars_14d),
             e.treated_n, e.holdout_n)
    WHEN ABS(e.diff_raw_14d) <= e.band_95_14d THEN
      FORMAT('NO DETECTABLE DIFFERENCE. Over %s to %s the %d campaigns the engine managed produced %s per 14 days more net profit than the %d randomly-matched campaigns it was forbidden to touch, with a 95%% interval of plus or minus %s. That interval contains zero, so we can rule out the engine adding or destroying more than about %s per 14 days — and NOTHING SMALLER. This is not a verdict that the engine is worthless; it is a verdict that the instrument cannot see an effect this size. A real effect of a thousand dollars either way would be indistinguishable from zero here.',
             CAST(e.win_start AS STRING), CAST(e.win_end AS STRING),
             e.treated_n, FORMAT('$%.0f', e.diff_raw_14d), e.holdout_n,
             FORMAT('$%.0f', e.band_95_14d), FORMAT('$%.0f', e.band_95_14d))
    WHEN e.diff_raw_14d < 0 THEN
      FORMAT('HARM DETECTED. Over %s to %s the %d campaigns the engine managed produced %s per 14 days LESS net profit than the %d randomly-matched campaigns it was forbidden to touch (95%% interval plus or minus %s, change-score estimate %s). This clears the band, which is what this trial was built to catch. Confirm with the permutation p-value inside the rerandomization acceptance region and the leave-one-out check before acting — one campaign is 11.2%% of the money.',
             CAST(e.win_start AS STRING), CAST(e.win_end AS STRING),
             e.treated_n, FORMAT('$%.0f', ABS(e.diff_raw_14d)), e.holdout_n,
             FORMAT('$%.0f', e.band_95_14d), FORMAT('$%.0f', e.diff_adjusted_14d))
    ELSE
      FORMAT('GAIN DETECTED. Over %s to %s the %d campaigns the engine managed produced %s per 14 days MORE net profit than the %d randomly-matched campaigns it was forbidden to touch (95%% interval plus or minus %s, change-score estimate %s). Before believing it, rule out cross-campaign leakage: dollars the engine frees in one treated campaign can be re-spent on another treated campaign through the BASE/GROWTH portfolio pot, which flatters this arm, and organic halo runs between variations of one family. The family strata balance the arms on that; they do not make the arms independent, and its size is unmeasured.',
             CAST(e.win_start AS STRING), CAST(e.win_end AS STRING),
             e.treated_n, FORMAT('$%.0f', e.diff_raw_14d), e.holdout_n,
             FORMAT('$%.0f', e.band_95_14d), FORMAT('$%.0f', e.diff_adjusted_14d))
  END,
  IF(e.action_class = 'ALL' AND nc.n_cens > 0,
     FORMAT(' CENSORED (R9, HOLDOUT.md §6): %d of %d campaigns, both arms, each rated only on its days before the first change on a HOLDOUT campaign of its stratum; the CENSORED rows of this view name them.',
            nc.n_cens, nc.n_all),
     ''),
  IF(e.action_class = 'ALL' AND nc.n_pre > 0,
     FORMAT(' NOT CENSORED, A RULING FOR ORI: %d HOLDOUT campaign(s) changed on Amazon between their assignment and the window start; R9 censors changes inside the window only, so this estimate scores them, and their stratum-mates, as untouched from the window start; the PRE_WINDOW_CHANGE rows of this view name them.',
            nc.n_pre),
     '')) AS verdict,
  CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(NULL AS STRING),
  CAST(NULL AS DATE), CAST(NULL AS DATE), CAST(NULL AS DATE)
FROM est e
CROSS JOIN ncens nc
WHERE CURRENT_DATE('America/Los_Angeles') >= e.first_readout

UNION ALL

-- ── v27.162 (R9): one CENSORED row per censored unit, both arms. Dates and the reason, never a
-- dollar, so these rows stand before 2027-01-05 too. V_ENGINE_HEALTH holdout_unit_changed reads them.
SELECT
  3 AS row_rank,
  'CENSORED' AS state,
  CAST(NULL AS STRING) AS action_class,
  CAST(NULL AS INT64), CAST(NULL AS INT64),
  CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
  CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
  CONCAT(FORMAT('CENSORED from %t, %s arm, stratum %s: ', u.censored_from, u.arm, u.stratum),
         IF(u.contaminated_on IS NOT NULL,
            FORMAT('this HOLDOUT campaign changed on Amazon on %t (%d change(s) inside the trial window, the first %s); ',
                   u.contaminated_on, u.n_changes, u.first_change),
            ''),
         'the stratum is censored from the first change on any of its HOLDOUT campaigns — ', u.censored_by,
         '. Both arms of the stratum leave the estimate from that day (R9, Ori 2026-10-02; HOLDOUT.md §6).') AS verdict,
  u.unit_id, u.unit_name, u.arm, u.stratum, u.contaminated_on, u.censored_from,
  CAST(NULL AS DATE) AS pre_window_change_on
FROM ucens u
WHERE u.censored_from IS NOT NULL

UNION ALL

-- ── v27.162 follow-up: one PRE_WINDOW_CHANGE row per HOLDOUT unit changed between its assignment and
-- its window start. Dates and the changes, never a dollar, so these rows stand before 2027-01-05 too.
-- R9 does not censor these changes; whether they contaminate the unit is a ruling for Ori (header,
-- "CHANGES BEFORE THE WINDOW"). V_ENGINE_HEALTH holdout_unit_changed reads these rows and is AMBER
-- while any stands.
SELECT
  4 AS row_rank,
  'PRE_WINDOW_CHANGE' AS state,
  CAST(NULL AS STRING) AS action_class,
  CAST(NULL AS INT64), CAST(NULL AS INT64),
  CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
  CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
  CONCAT(FORMAT('NOT CENSORED, A RULING FOR ORI: this HOLDOUT campaign (stratum %s) changed on Amazon between its assignment on %t and its window start on %t, %d ledger row(s): %s. ',
                u.stratum, DATE(a.assigned_at, 'America/Los_Angeles'), a.eligible_from, p.n_rows, p.changes),
         CASE WHEN u.censored_from IS NULL
                THEN FORMAT('R9 censors changes inside the window only, so the estimate scores this campaign and its stratum-mates as untouched from %t to the end of the window',
                            a.eligible_from)
              WHEN u.censored_from > a.eligible_from
                THEN FORMAT('R9 censors changes inside the window only, so the estimate scores this campaign and its stratum-mates as untouched from %t to %t (the stratum is censored from %t)',
                            a.eligible_from, DATE_SUB(u.censored_from, INTERVAL 1 DAY), u.censored_from)
              ELSE FORMAT('R9 already censors the stratum from %t, the window start, for a change inside the window', u.censored_from)
         END,
         '. HOLDOUT.md §6 #2: one upload contaminates a unit permanently; whether a change before the window start does is a ruling for Ori (HOLDOUT.md §6 "Contamination"). Censoring the stratum from the window start would drop it from the estimate.') AS verdict,
  u.unit_id, u.unit_name, u.arm, u.stratum, u.contaminated_on, u.censored_from,
  p.pre_window_change_on
FROM pre p
JOIN ucens u USING (unit_id)
JOIN asg a USING (unit_id)
;
