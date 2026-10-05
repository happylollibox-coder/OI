-- =============================================
-- V_ENGINE_HEALTH — the engine's standing self-check, one row per check (2026-08-16, Task 3.3).
-- Spec: architecture/ENGINE_HEALTH.md.
--
-- (Ori 2026-08-15: the engine "should always check himself.") Every check reads SMALL tables
-- except the scorecard (ceiling view), which appears exactly once — the shared `sc` CTE below,
-- read by BOTH #6 and #7. Statuses are the VIEW's — GREEN / AMBER / RED / INFO — with the
-- threshold printed beside the measurement so a reader never has to guess what "bad" means.
-- A quiet board is the goal state, not a malfunction.
-- v27.104 (2026-08-22): c12 loser_kill_clause + c13 state_floor_resolution (KEYWORD_STATE.md).
-- v27.127 (2026-08-23): c14–c22, the family seat register's checks (FAMILY_SEAT_REGISTER.md,
-- "Health"). They read the register's once-per-pass IMAGE (T_FAMILY_SEAT_REGISTER, the table the
-- morning surfaces read), the seat ledger, the keyword-state snapshot, the change log, the holdout
-- table and LOG_PIPELINE_RUNS — never the live register view (tens of seconds) and never a
-- ceiling view. Two are REPORTS (INFO) by design: the overdue-appointment counter, whose cause is
-- upstream of the register (the park-era settle_due, diagnosed, not applied), and the days-since
-- counter, which is a clock on the orchestrator (New York), not a verdict on the ledger.
-- v27.152 (2026-10-01): c23–c32, the next-week money plan's checks (plan Task 5, NEXT_WEEK_MONEY.md
-- §6) and two ALARMS for a night that was not saved. WHY NOW: SP_BUILD_NEXT_WEEK_PLAN failed every
-- pass from 2026-08-29 to 2026-09-28; LOG_PIPELINE_RUNS logged every failure and no surface told
-- Ori. The plan checks read the plan's latest partition, the proposal snapshot and the gate table —
-- small — never the judgement view and never a ceiling view. Three depart from the Task 5 draft
-- because the draft's forms read RED on a healthy partition (measured 2026-10-01 before deploy:
-- draft window test 0 but fails after 22:00 Los Angeles by the acceptance's own finding, draft pot
-- test 7, draft move test 152; the acceptance suite's v27.147 forms 0, 0, 0), so each takes the
-- form FACT_PLAN_NEXT_WEEK_acceptance.sql already holds: C01 (the age-2 fence), C03 (holdout spend
-- is outside the pot — the builder's unruled reading then; Ori ruled the opposite on 2026-10-02,
-- P-15, and v27.158 restates both) and C06 (one move per CANDIDATE). c28 is restated for P-14c: the guard is a
-- clock and a last-day test, not a veto — a demotion under its preconditions is legitimate iff the
-- judge published guard_released_by, and this check READS that column and never re-derives the
-- guard (the builder vetoed every partition for a month by re-deriving it). c26 is a REPORT until
-- plan Task 3 ships, because no engine PLAN writes proposals today and the check would otherwise
-- assert ownership the plan does not yet hold. The two alarms: plan_partition_fresh (a night the
-- plan step reached and did not save, or any night older than yesterday) and pipeline_step_failing
-- (ANY procedure whose three most recent runs all logged FAIL — the generic form of the outage,
-- which it would have named on day 1). V_DAILY_BRIEF reads this view's RED rows into one SYSTEM
-- line (section_rank 7), so the alarm reaches the one query Ori reads every morning.
-- v27.156 (2026-10-02, piece-1 plan Task 2, P-18): c28's hold half reads hold_kept_by. A hold now
-- also lasts while the very good day that started it is still inside the window, so a HELD row
-- is RED only when it has neither a very good last day nor hold_kept_by = STRONG_DAY_IN_WINDOW
-- with window_from <= hold_strong_day; the detail counts the holds kept by that day. Only the
-- guard and c28 CTEs changed.
-- v27.158 (2026-10-02, piece-1 plan Task 4, P-15, audit fix #24): plan_pot_reconciliation reads
-- the pot as Ori ruled it — every GOOD keyword's window spend, holdout included. The v27.152 form
-- (and the paragraph above calling the all-GOOD sum the draft's error) enforced the builder's
-- unruled reading (a) under a "(P-2)" label. The detail now prints each family's not-good side,
-- the expected spend after the upload and the share of the gap it closes (P-22). Only the pot_rec
-- and c24 CTEs changed.
-- v27.159 (2026-10-02, piece-1 plan Task 5, P-25, audit fix #19): plan_one_move_per_notgood reads the
-- two probe moves — a seated probe is OPEN_PROBE, an unseated probe NONE (nothing uploaded) — and
-- counts a candidate's NONE on anything but an unseated probe, or an OPEN_PROBE on anything but a
-- seated one (reads FACT_PLAN_NEXT_WEEK.is_probe, migration 2026-10-02_plan_seat_tenure_columns.sql).
-- Only that CTE changed.
-- Negative controls, 2026-10-03 02:01–02:10 UTC (job bqjob_r4ed37cefafebd407_000001a0ff7ee55d_1), by
-- scripts/bigquery/tests/check_plan_seat_controls.py. It ran this file's own pl, plb and c25 text,
-- with comment lines stripped, on doctored copies of FACT_PLAN_NEXT_WEEK, after finding that text in
-- the deployed definition (INFORMATION_SCHEMA.VIEWS). Results: LIVE measured 0, GREEN. A seated
-- non-probe's move NONE: measured 1, RED (the NONE term). A seated non-probe's move OPEN_PROBE:
-- measured 1, RED (the OPEN_PROBE term). An empty plan: measured 0, RED.
-- v27.162 (2026-10-03, piece-1 plan Task 8, ruling R9 = spec P-23, audit fix #27): c33
-- holdout_unit_changed. RED when a HOLDOUT campaign changed inside its trial window — a change-log row
-- that was applied (V_PPC_CHANGE_LOG_APPLIED) or a change the observed-change ledger saw on Amazon
-- (FACT_PPC_CHANGE_LOG source OBSERVED, hand changes in the console included) — and V_HOLDOUT_READOUT
-- does not censor that campaign and its stratum-mates, both arms, from that day on. It READS the
-- readout's CENSORED rows and never re-derives the censoring. Before it, seat_holdout_row_on_sheet
-- (c18) joined only the seat books' log rows to the holdout, so the two console pauses of 2026-09-27
-- were on no surface. Red as well when no HOLDOUT unit or no observed-change row is read (an empty
-- ledger would hide every console change). Sources: DE_HOLDOUT_ASSIGNMENT, FACT_PPC_CHANGE_LOG,
-- V_PPC_CHANGE_LOG_APPLIED and the readout's CENSORED branch, which reads no FACT_AMAZON_ADS (measured
-- in the readout's header). Negative controls: HOLDOUT_INTEGRITY_acceptance.sql (H2) runs this file's
-- hu_gap and c33 text verbatim on doctored copies; the results are in that file's header.
-- v27.162 follow-up (2026-10-03, review of commit a2e7e1e): the v27.162 c33 read changes from
-- eligible_from (2026-09-01) only, but the arms were frozen on 2026-08-19 (assigned_at). Listing the
-- same two sources on HOLDOUT units from 2026-08-19 (HOLDOUT_INTEGRITY_acceptance.sql, statement
-- `pre`) found 25 rows on 7 HOLDOUT units before the window start, none censored: the 08-21 pauses
-- of FRESH-SP/PT (Competitors, Blue, A1) 135553284530895 and PILOT-WHITE-PHRASE-birthday-gifts
-- 39989090923480, the 08-23 reprice book on 279837860088128, 446868628489343 and 75834491759416,
-- and unlogged observed changes on 200171414843593 (08-25) and 488973733209950 (08-26, 08-31). R9
-- reads the window only; whether such a change contaminates is a ruling for Ori. So c33 now also
-- reads the readout's PRE_WINDOW_CHANGE rows: RED when a HOLDOUT unit changed between its assignment
-- day and its window start and the readout does not publish it from that day, AMBER while any such
-- change stands (the ruling is pending), and the detail names them. Measured after the deploy
-- (2026-10-03): the board filtered to this check read AMBER, measured 0, at 99.5 / 143.6 slot-s
-- (two runs; 10,641,938 bytes, no FACT_AMAZON_ADS: the readout is read twice, CENSORED and
-- PRE_WINDOW_CHANGE branches only); the full board 33 checks, 3 RED (contradiction_rate,
-- seat_every_occupant_numbered, seat_past_due_in_future_tense), 4402.4 slot-s. V_DAILY_BRIEF's
-- SYSTEM line counts RED rows only, so this AMBER is on the board, not in the brief.
-- Controls: HOLDOUT_INTEGRITY_acceptance.sql (31 rows PASS, its header).
-- v27.163 (2026-10-03, piece-1 plan Task 9, Step 1): c34 plan_pass_failed. RED when the latest run of
-- SP_BUILD_NEXT_WEEK_PLAN in LOG_PIPELINE_RUNS (last 30 days) logged FAIL, or any run in the last 24
-- hours did; RED as well when the step logged no run in the last 24 hours (an empty log would read
-- GREEN). The detail leads with the failure's New York time and the first 160 characters of its
-- error. WHY: the piece-0 proof found 3 of 9 passes refused 2026-09-29 -> 10-01 (the seat-number
-- continuity ASSERT). Read 2026-10-03: LOG_PIPELINE_RUNS holds at most two FAILs of the plan step in a
-- row from 09-29 on, and FACT_PLAN_NEXT_WEEK a partition for every night 09-28 -> 10-03, so neither
-- plan_partition_fresh (a night with no partition) nor pipeline_step_failing (three FAILs in a row)
-- could name a single refused pass.
-- Reads LOG_PIPELINE_RUNS only (no FACT_AMAZON_ADS). V_DAILY_BRIEF quotes its detail on the SYSTEM
-- line beside the two alarms. Negative controls: PLAN_HEALTH_acceptance.sql A1 (results in its
-- header). Only the ppr, ppf and c34 CTEs and the final UNION changed.
-- v27.176 (2026-10-04, learning-contract piece 2, Task 6; architecture/LEARNING.md §6, spec §9): c35-c37,
-- the learning contract's checks. prediction_grades_fresh: RED when a ledger row of V_PREDICTION_LEDGER
-- has no grade in FACT_PREDICTION_GRADE one night after the house watermark LEAST(MAX(FACT_AMAZON_ADS
-- .date), FN_ADS_ANCHOR_CAP()) made it gradable (horizon_to + SETTLE_HORIZON_DAYS + 1 <= watermark),
-- and RED on an empty population; the detail prints the watermark beside both its terms.
-- prediction_regression: per predictor, the report card's trailing MIN_GRADED_WINDOWS WINDOW rows
-- against the MIN_GRADED_WINDOWS before them, pooled, on mae_net_share (applied scenario) and
-- counterfactual_net_per_alloc; RED when either is worse by more than REGRESSION_MAX of the earlier
-- value (the setting is a ratio), INFO YOUNG until a predictor has twice MIN_GRADED_WINDOWS windows,
-- RED on an empty card; the detail names the rule and builder versions that changed between the spans.
-- response_model_unverified: INFO until a current ACT grade applied on a row with a move, then GREEN.
-- Measured before deploy (the three checks' text run as a query, 2026-10-03 22:41 UTC, job
-- t6_proto_1791067312): 116.5 slot-s, 15,229,779 bytes processed; prediction_grades_fresh GREEN 0 of
-- 8,944 rows past due, prediction_regression INFO (YOUNG, 1 of 6 windows per plan),
-- response_model_unverified INFO 0. Only the lrn_* and c35-c37 CTEs and the final UNION changed.
-- Holdout restart (deploy 2026-10-05; plan docs/superpowers/plans/2026-10-03-holdout-restart.md §1 rows
-- 4-5, §2.7, Task 6; pre-deploy review fixes 1-2; no v27.N assigned). Only c18, the c33 CTEs (hu_trial
-- .. hu_r9) and c33 changed.
--   c18 seat_holdout_row_on_sheet joins V_HOLDOUT_ARM (the arm that binds today or later, any trial; it
--   filters unit_type = 'CAMPAIGN') and counts a seat-book row built between the campaign's gate_from and
--   gate_to; the detail prints MIN(gate_from) of the arm. It no longer reads DE_HOLDOUT_ASSIGNMENT.
--   c33 holdout_unit_changed reads THE LIVE TRIAL (hu_trial: the is_live row of V_HOLDOUT_TRIAL, newest
--   assigned_on on a tie, the row V_HOLDOUT_READOUT's k reads), not a literal. R9's terms (hu_gap,
--   hu_pre_gap) are unchanged. Two terms are added.
--   TOUCH ALARM: RED while a touch on a HOLDOUT unit of the live trial, dated from its assignment day (LA)
--   to its trial_end, is 7 or fewer LA days old, or while a BASELINE_DIFF stands; AMBER for any older
--   touch and for a re-baselined setting (more than one DE_HOLDOUT_BASELINE row for a key). Kinds:
--   LEDGER (hu_led + hu_pre, as before); NEW_ENTITY (the first DIM_KEYWORD version of a keyword_id or
--   the first DIM_AD_GROUP version of an ad_group_id, dated by the LA day of TIMESTAMP(effective_from,
--   'UTC') as V_AMAZON_OBSERVED_CHANGES dates a version); CAMPAIGN_ATTR (DIM_CAMPAIGN version pairs whose
--   portfolio_id or bidding_strategy differ; sb_campaign_history version pairs whose bid_optimization or
--   bid_optimization_strategy differ, because DIM_CAMPAIGN carries '' for an SB bidding strategy);
--   BASELINE_DIFF (undated: placement and shopper-cohort adjustments and SB product targets present by
--   the presence rule, for the FOUNDING controls only, against the latest DE_HOLDOUT_BASELINE row).
--   Kinds 2-4 are labelled "seen by the alarm, not censored by R9 — Ori to rule"; R9 is unchanged.
--   Kinds 2-3 end at trial_end, as kind 1 (hu_led) does.
--   FEED LIVENESS: RED when any of 15 stamps is more than 36 h old or missing, each read on its own: the
--   last OK run in LOG_PIPELINE_RUNS of SP_RECORD_OBSERVED_CHANGES, SP_LOAD_DIM_KEYWORD,
--   SP_LOAD_DIM_CAMPAIGN and SP_LOAD_DIM_AD_GROUP; MAX(_fivetran_synced) of keyword_history,
--   sb_keyword, targeting_clause_history, campaign_history, sb_campaign_history, ad_group_history,
--   sb_ad_group_history, campaign_placement_bidding, sb_campaign_bid_adjustments_by_placement,
--   sb_campaign_bid_adjustments_shopper_cohort, sb_product_target. The detail prints every age.
--   WHY 36 h (measured 2026-10-04 ~04:55-05:05 UTC): over 30 days each of the four procedures logged
--   90 OK runs with at most 13.0 h between two (SP_RECORD_OBSERVED_CHANGES: 6 since 2026-10-02 05:02,
--   13.0 h); the Fivetran project's job history shows a write touching rows on every one of the eleven
--   tables with at most 12.0 h (ad_group_history), 16.0 h (campaign_history, campaign_placement_bidding)
--   or 21.0 h (the other eight) between two; time travel at 14 points 6..162 h back read each table's
--   MAX(_fivetran_synced) 0.0-12.2 h old. The negative mirrors (negative_keyword_history,
--   campaign_negative_keyword_history, sb_negative_keyword, negative_targeting_clause_history,
--   sb_negative_product_target; last written 2025-12-29 .. 2026-01-03) and the ad and creative mirrors
--   (product_ad_history, sb_ad_history, sb_creative_history; 2025-12-28 .. 2026-01-03) had no write in
--   the 30 days, so they are left out, and the detail's tail names them as what no source can see.
--   V_SRC_AmazonAds_keyword DOES cover SB keywords: it unions keyword_history, sb_keyword (dated by
--   _fivetran_synced) and targeting_clause_history, and all 8,415 sb_keyword ids are in DIM_KEYWORD
--   (read 2026-10-04). It does not carry sb_product_target, hence kind 4.
--   PLANNING: the first draft (one scalar subquery per term and per detail clause) failed "Not enough
--   resources for query planning - too many subqueries" on the board filtered to c33. Every CTE
--   reference is planned again, so the touch, liveness, R9 and kind-4 inputs are each read once into a
--   one-row aggregate (hu_touch_sum, hu_live, hu_r9, hu_k4_sum).
--   MEASURED 2026-10-04 05:00-06:05 UTC (LA 2026-10-03) on TMP_HT2_ copies, all dropped afterwards:
--   this file with comment lines stripped (76,164 bytes), names sed-pointed at a registry copy (Task 2's
--   rows), an assignment copy (69 trial-1 rows + Task 3's founding file: 59 trial-2 rows, 12 HOLDOUT),
--   a baseline copy (15 rows on 8 controls by the presence rule) and copies of V_HOLDOUT_TRIAL,
--   V_HOLDOUT_ARM and V_HOLDOUT_READOUT from this branch.
--     trial 2, no touch, live sources: GREEN, measured 0; every age 0.1-0.9 h.
--     the full board on the copy against the live board, read together after pass 1 of 10-04: 37
--     checks each; all 36 others equal in status and measured; c33 live AMBER 0 (trial 1), copy GREEN 0.
--     doctored, the date pinned to 2026-10-20 (registry, arm, readout and c33), every input a copy:
--       observed ledger row on control 130115986205897 dated 10-20: RED, measured 1 (the readout copy
--       censors its stratum, 10 of 59); dated 10-13 (7 days): RED 1; dated 10-12 (8 days): AMBER 0;
--       dated 10-05 (before the window): AMBER 0, "published, not censored (pre-declared for T2)".
--       NEW_ENTITY keyword created 10-20: RED 1, labelled; the same keyword dated 09-30 (before the
--       assignment): GREEN 0. NEW_ENTITY ad group 10-20: RED 1. CAMPAIGN_ATTR portfolio change 10-20:
--       RED 1; bidding strategy LEGACY_FOR_SALES -> AUTO_FOR_SALES: RED 1; SB bid_optimization false ->
--       true on 537046793426450: RED 1. Each RED names the touch, kind, day and "seen by the alarm,
--       not censored by R9 — Ori to rule".
--       BASELINE_DIFF: a baseline value altered (53343800376430 TOP 25 -> 30): RED 1, "date unknown";
--       plus a later re-baseline row carrying a ruling: AMBER 0. ME-COMPETE 365568042533669 TOP 30
--       re-stamped at the table's latest sync (no baseline row): RED 1 (absent -> 30). A removal
--       (130115986205897 TOP stamp 12 h back): RED 1 (100 -> absent); plus a NULL re-baseline row:
--       AMBER 0. The 14 stale SP rows dropped: GREEN 0. 27660342907703's SB target flagged deleted:
--       RED 1 (bid and state). A LATE ARRIVAL control (SB 111024628782640, present 0% placement and
--       cohort rows): GREEN 0, named unwatched. An empty watched set (every rule re-prefixed): RED 8,
--       15 differences, all 12 named unwatched. Undoctored again: GREEN 0.
--       FEED: a log copy without the OK runs of the last 36 h of each procedure in turn: RED, naming
--       that procedure only (37.5 h); each of the eleven table copies shifted so its MAX is 37 h old:
--       RED, naming that table only; a procedure with no row: RED, "missing"; an emptied table: RED,
--       "missing".
--     trial 1's live inputs (a registry copy holding trial 1's OPENED row only): RED, measured 4 —
--     200171414843593, 446868628489343, 75834491759416 and 76054744633802 touched on 2026-09-27, 6 LA
--     days before 10-03; R9's terms 0 (the readout copy censors 61 of 69, as live). The date pinned to
--     10-04 (7 days): RED 4; pinned to 10-05 (8 days): AMBER 0. No NEW_ENTITY or CAMPAIGN_ATTR touch
--     on a trial-1 control since 2026-08-19.
--     c18 on the pinned copy: GREEN 0, "the arm starts 2026-10-05"; three book rows added (a trial-2
--     control inside its gate, a trial-1-only control on 10-20, a trial-2 control on 10-03): RED 1.
--   COST, the board filtered to c33, two runs each, 2026-10-04 ~05:48 UTC: deployed text (trial 1)
--   106.0 / 112.9 slot-s, 10,641,938 bytes (jobs g4_SLOT_LIVE_1_1791092909_20323,
--   g4_SLOT_LIVE_2_1791092960_20323); this text on the copies (trial 2) 352.5 / 351.8 slot-s,
--   17,197,490 bytes, 13-16 s (g4_SLOT_TMP_1_1791092935_20323, g4_SLOT_TMP_2_1791092994_20323). Most
--   of the increase is the registry: V_HOLDOUT_TRIAL is planned again at each reference of hu_trial and
--   of the readout's k, and one c33 read read the registry copy 48 times (307 stages). Full board, one
--   run each, read together: live 33,009.5 slot-s, 50.8 s; copy 11,489.7 slot-s, 28.9 s.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_ENGINE_HEALTH` AS
WITH pf AS (SELECT * FROM `onyga-482313.OI.T_ENGINE_PREFLIGHT`),
ks AS (SELECT * FROM `onyga-482313.OI.FACT_KEYWORD_STATE`),
-- ONE shared scorecard scan (review 2026-08-16, planner safety): c6 and c7 both read THIS CTE.
-- Before this, c7 read V_MANUAL_DIVERGENCE, which embeds its own full V_CHANGE_SCORECARD scan —
-- two copies of the ceiling view inlined into one statement.
-- 2026-10-01: the scorecard now also grades changes observed on Amazon (source = 'OBSERVED', hand
-- changes from the DIM SCD2 trail). They are left out here so c6 and c7 measure what they always
-- measured; counting graded hand changes on the board is Ori's call (PPC_CLOSE_THE_LOOP.md).
sc AS (
  SELECT source, verdict, change_date, change_id, campaign_id, keyword_id, action_group,
         SAFE_CAST(new_value AS FLOAT64) AS new_val
  FROM `onyga-482313.OI.V_CHANGE_SCORECARD`
  WHERE source != 'OBSERVED'
),

c1 AS (  -- contradiction rate: EXCLUDE share of the day's instructions
  SELECT 'contradiction_rate' AS check_name,
    ROUND(SAFE_DIVIDE(COUNTIF(verdict = 'EXCLUDE'), COUNT(*)) * 100, 1) AS measured,
    'EXCLUDE % of instructions · amber > 5, red > 15 (iteration-6 found 29.9 unGated)' AS threshold,
    CASE WHEN SAFE_DIVIDE(COUNTIF(verdict = 'EXCLUDE'), COUNT(*)) > 0.15 THEN 'RED'
         WHEN SAFE_DIVIDE(COUNTIF(verdict = 'EXCLUDE'), COUNT(*)) > 0.05 THEN 'AMBER'
         ELSE 'GREEN' END AS status,
    CONCAT(CAST(COUNTIF(verdict = 'EXCLUDE') AS STRING), ' of ', CAST(COUNT(*) AS STRING),
           ' instructions excluded by ownership — high is not broken (the gate is WORKING) but says the engines overlap a lot') AS detail
  FROM pf
),
c2 AS (  -- single voice: no key+lever with two live instructions
  -- v27.72: the key mirrors SP_ENGINE_PREFLIGHT's key_id — NEGATE rows key on the TERM (they
  -- have no keyword_id; without the term, every negate in a campaign is one false "overlap")
  SELECT 'ownership_overlaps',
    CAST(COUNT(*) AS FLOAT64),
    'keys with >1 non-EXCLUDE instruction · red > 0',
    IF(COUNT(*) > 0, 'RED', 'GREEN'),
    'one key, one lever, one voice — the preflight assertion, standing'
  FROM (SELECT campaign_id,
               IF(grain = 'NEGATE', CONCAT('term|', LOWER(TRIM(COALESCE(target_text, '')))),
                  COALESCE(keyword_id, '')) k,
               lever
        FROM pf GROUP BY 1, 2, 3 HAVING COUNTIF(verdict != 'EXCLUDE') > 1)
),
c3 AS (  -- state invariant 1
  SELECT 'state_duplicate', CAST(COUNT(*) AS FLOAT64),
    'keywords in two states · red > 0', IF(COUNT(*) > 0, 'RED', 'GREEN'),
    'V_KEYWORD_STATE invariant 1'
  FROM (SELECT campaign_id, keyword_id FROM ks GROUP BY 1, 2 HAVING COUNT(*) > 1)
),
c4 AS (  -- state invariant 2
  SELECT 'missing_appointment',
    CAST(COUNTIF(next_check_date IS NULL AND state != 'DEAD') AS FLOAT64),
    'non-DEAD keywords with no next appointment · red > 0',
    IF(COUNTIF(next_check_date IS NULL AND state != 'DEAD') > 0, 'RED', 'GREEN'),
    'V_KEYWORD_STATE invariant 2 — every keyword has a date something re-judges it'
  FROM ks
),
c5 AS (  -- overdue appointments (found on the state machine's first day)
  SELECT 'overdue_appointments',
    CAST(COUNTIF(next_check_date < CURRENT_DATE('America/Los_Angeles') AND state != 'DEAD') AS FLOAT64),
    'appointments in the past · amber > 50 (judgments due that nothing has re-run)',
    CASE WHEN COUNTIF(next_check_date < CURRENT_DATE('America/Los_Angeles') AND state != 'DEAD') > 50
         THEN 'AMBER' ELSE 'GREEN' END,
    CONCAT('oldest: ', CAST(MIN(IF(next_check_date < CURRENT_DATE('America/Los_Angeles'), next_check_date, NULL)) AS STRING))
  FROM ks
),
c6 AS (  -- outcome mix, trailing settled window (reads the shared sc scan — the ceiling view's one appearance)
  SELECT 'scorecard_reversed_share',
    ROUND(SAFE_DIVIDE(COUNTIF(verdict = 'REVERSED'), NULLIF(COUNTIF(verdict != 'INSUFFICIENT'), 0)) * 100, 1),
    'REVERSED % of judged, changes from the last 42d · amber > 35 (measured era baseline 46)',
    CASE WHEN SAFE_DIVIDE(COUNTIF(verdict = 'REVERSED'), NULLIF(COUNTIF(verdict != 'INSUFFICIENT'), 0)) > 0.35
         THEN 'AMBER' ELSE 'GREEN' END,
    CONCAT(CAST(COUNTIF(verdict != 'INSUFFICIENT') AS STRING), ' judged · ',
           CAST(COUNTIF(verdict = 'INSUFFICIENT') AS STRING), ' too thin to judge')
  FROM sc
  WHERE change_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 42 DAY)
),
c7 AS (  -- the human-vs-model ledger: MANUAL_BETTER rows demand a model fix
  -- PLANNER SAFETY (review 2026-08-16): this DUPLICATES V_MANUAL_DIVERGENCE's kind logic BY
  -- DESIGN instead of reading that view — the view embeds its own full V_CHANGE_SCORECARD scan,
  -- and stacking it beside c6 put two copies of the ceiling view in one statement. Kind here =
  -- OVERRODE: a same-day non-EXCLUDE proposal exists on the key+lever (owning engine first, the
  -- view's priority order) and the hand's value diverges > 5% from it (a proposal carrying no
  -- value diverges by definition — the view's ELSE). MANUAL_BETTER = OVERRODE + CONFIRMED.
  -- Both definitions are owned by architecture/MANUAL_DIVERGENCE.md — change them together.
  SELECT 'manual_better_unresolved',
    CAST(COUNT(DISTINCT s.change_id) AS FLOAT64),
    'OVERRODE changes where the hand beat the model · INFO until resolution tracking exists',
    IF(COUNT(DISTINCT s.change_id) > 0, 'AMBER', 'GREEN'),
    'doctrine: each one ends as a threshold change or a documented disagreement (MANUAL_DIVERGENCE.md)'
  FROM sc s
  JOIN (
    -- v27.72: NEGATE rows key on the term and are OVERRODE-exempt (a negate has no value to
    -- diverge from) — the lever filter below keeps this check to the value levers.
    SELECT snapshot_date, campaign_id, COALESCE(keyword_id, '') AS kid,
           CASE grain WHEN 'BUDGET' THEN 'BUDGET' WHEN 'NEGATE' THEN 'NEGATE' ELSE 'BID' END AS lever,
           suggested_bid, suggested_budget
    FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
    WHERE COALESCE(verdict, '') != 'EXCLUDE' AND grain != 'NEGATE'
    QUALIFY ROW_NUMBER() OVER (
      PARTITION BY snapshot_date, campaign_id, COALESCE(keyword_id, ''),
                   CASE grain WHEN 'BUDGET' THEN 'BUDGET' WHEN 'NEGATE' THEN 'NEGATE' ELSE 'BID' END
      ORDER BY CASE engine WHEN 'LOW_STOCK' THEN 1 WHEN 'LAUNCH' THEN 2 WHEN 'OOB' THEN 3
                           WHEN 'REVERDICT' THEN 4 WHEN 'LIFT' THEN 5 WHEN 'COACH' THEN 6 ELSE 9 END) = 1
  ) p ON p.snapshot_date = s.change_date
     AND p.campaign_id = s.campaign_id
     AND p.kid = COALESCE(s.keyword_id, '')
     AND p.lever = IF(s.action_group IN ('BUDGET_UP', 'BUDGET_DOWN'), 'BUDGET', 'BID')
  WHERE s.source = 'MANUAL' AND s.verdict = 'CONFIRMED'
    AND (COALESCE(p.suggested_bid, p.suggested_budget) IS NULL
         OR ABS(COALESCE(s.new_val, 0) - COALESCE(p.suggested_bid, p.suggested_budget))
            > 0.05 * COALESCE(p.suggested_bid, p.suggested_budget))
),
c8 AS (  -- snapshot freshness: the memory must not silently stop
  SELECT 'snapshot_freshness',
    CAST(DATE_DIFF(CURRENT_DATE('America/Los_Angeles'),
                   (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`), DAY) AS FLOAT64),
    'days since the last proposal snapshot · red > 2',
    IF(DATE_DIFF(CURRENT_DATE('America/Los_Angeles'),
                 (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`), DAY) > 2, 'RED', 'GREEN'),
    'FACT_ENGINE_PROPOSALS — without the memory, nothing learns'
),
c9 AS (  -- no-op leakage: engines carry their own guards; the gate counts what still leaks
  SELECT 'noop_leakage',
    CAST(COUNTIF(verdict_reason LIKE 'no-op%') AS FLOAT64),
    'instructions that were no-ops at the gate · amber > 10 (ladder thrash)',
    IF(COUNTIF(verdict_reason LIKE 'no-op%') > 10, 'AMBER', 'GREEN'),
    'v27.29/v27.46 no-op guards should catch these upstream; the gate is the belt'
  FROM pf
),
c10 AS (  -- v27.101: view-body headroom — no view may creep up on BigQuery's hard ceiling unseen
  -- V_KEYWORD_LIFT reached the ceiling with a fraction of a percent to spare and nothing measured
  -- it, so the discovery came from a change that would not fit. Past the ceiling a view can no
  -- longer be edited at all, only migrated, and the migration lands under whatever deadline
  -- happens to expose it. This check fires while the fix is still an edit.
  --   Declared constants: ceiling 262,144 characters (BigQuery's maximum view query length),
  --   amber at 70% of it, red at 85%.
  -- The number is CHARACTERS, matching LENGTH() and BigQuery's own limit — not bytes, which
  -- overstate any view whose commentary carries non-ASCII text.
  -- Pre-deploy twin (measures the repo files, before BigQuery ever sees them):
  --   python3 scripts/bigquery/check_view_body_size.py
  SELECT 'view_body_headroom',
    ROUND(MAX(LENGTH(view_definition)) / 262144 * 100, 2),
    'largest view body as % of the 262,144-character ceiling · amber > 70, red > 85',
    CASE WHEN MAX(LENGTH(view_definition)) > 262144 * 0.85 THEN 'RED'
         WHEN MAX(LENGTH(view_definition)) > 262144 * 0.70 THEN 'AMBER'
         ELSE 'GREEN' END,
    CONCAT('largest is ',
           ARRAY_AGG(table_name ORDER BY LENGTH(view_definition) DESC LIMIT 1)[OFFSET(0)],
           ' — comment markers in column 0 cost nothing (the deploy strips them), indented ones ',
           'are shipped to BigQuery and charged against the ceiling')
  FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS`
),
c11 AS (  -- v27.102: one keyword, one price, on the day's EXPORTABLE plan
  -- WHY THIS IS NOT c2. c2 reads T_ENGINE_PREFLIGHT and counts non-EXCLUDE ROWS — it asks whether
  -- the gate resolved the contention. This reads FACT_ENGINE_PROPOSALS, the table every consumer
  -- downstream actually reads, and counts distinct exportable PRICES. The difference is the whole
  -- point: the gate can resolve a contention perfectly and the verdict can still fail to reach the
  -- reader — because the stamp-back join missed the row, because a row was skipped by the gate and
  -- left unjudged in the table, or because a consumer never asked for the verdict at all. That
  -- last one is what happened: the morning brief printed three prices for one keyword out of a
  -- table the gate had already resolved, and c2 was GREEN the whole time.
  -- A hand-built bulksheet is copied off that list, so two prices on one keyword is not an
  -- untidiness — it is the account's bid being decided by which line the eye landed on.
  -- COUNT(DISTINCT) ignores NULL, so negates (no value) can never trip this.
  SELECT 'plan_price_ambiguity',
    CAST(COUNT(*) AS FLOAT64),
    'keys whose exportable plan carries >1 distinct price today · red > 0',
    IF(COUNT(*) > 0, 'RED', 'GREEN'),
    'one keyword, one lever, one price — measured on the proposal table the consumers read, not on the gate table, so a verdict that never reached a reader is visible here'
  FROM (
    SELECT campaign_id,
           IF(grain = 'NEGATE', CONCAT('term|', LOWER(TRIM(COALESCE(target_text, '')))),
              COALESCE(keyword_id, '')) AS k,
           CASE grain WHEN 'BUDGET' THEN 'BUDGET' WHEN 'NEGATE' THEN 'NEGATE' ELSE 'BID' END AS lever
    FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
    WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`)
      -- the exportable set, defined exactly as V_DAILY_BRIEF defines it: a held row is not an
      -- instruction, and an unstamped row fails open into the plan
      AND hold_source IS NULL
      AND COALESCE(verdict, 'GO') != 'EXCLUDE'
    GROUP BY 1, 2, 3
    HAVING COUNT(DISTINCT COALESCE(suggested_bid, suggested_budget)) > 1
  )
),
c12 AS (  -- v27.104: THE KILL CLAUSE — a LOSER is only ever a keyword that failed AT its floor
  -- (ruling 4 + Ori's floor ruling, 2026-08-22). The SP asserts it by construction; this is the
  -- belt: a LOSER whose probation has not elapsed, or whose bid is not at its own channel floor,
  -- or which clears its family bar, is a phantom kill and must never reach the reprice book.
  SELECT 'loser_kill_clause',
    CAST(COUNTIF(state = 'LOSER'
                 AND NOT (COALESCE(probation_elapsed, FALSE) AND COALESCE(at_floor, FALSE)
                          AND COALESCE(settled_roas90, 0) < family_bar)) AS FLOAT64),
    'LOSERs not (probation elapsed AND bid at its floor AND below bar) · red > 0',
    IF(COUNTIF(state = 'LOSER'
               AND NOT (COALESCE(probation_elapsed, FALSE) AND COALESCE(at_floor, FALSE)
                        AND COALESCE(settled_roas90, 0) < family_bar)) > 0, 'RED', 'GREEN'),
    CONCAT(CAST(COUNTIF(state = 'LOSER') AS STRING), ' LOSERs · ',
           CAST(COUNTIF(state = 'FLOOR_PROBATION') AS STRING), ' on floor probation · ',
           'KEYWORD_STATE.md "The floors" — a keyword is only ever killed at its floor, after its probation')
  FROM ks
),
c13 AS (  -- v27.104: every judged row carries a resolved floor from the ONE definition
  -- (FN_BID_FLOOR via V_BID_FLOOR). A NULL floor means a private constant crept back in, or the
  -- DIM_KEYWORD -> ad group resolution broke; *_NO_ADGROUP sources are the fallback, counted here
  -- as detail so a silent drift to the conservative $0.25 is visible.
  SELECT 'state_floor_resolution',
    CAST(COUNTIF(bid_floor IS NULL AND state IN ('AT_BAR', 'REPRICE', 'FLOOR_PROBATION', 'LOSER')) AS FLOAT64),
    'priced states (AT_BAR/REPRICE/FLOOR_PROBATION/LOSER) with no floor · red > 0',
    IF(COUNTIF(bid_floor IS NULL AND state IN ('AT_BAR', 'REPRICE', 'FLOOR_PROBATION', 'LOSER')) > 0, 'RED', 'GREEN'),
    CONCAT(CAST(COUNTIF(bid_floor_source LIKE '%_NO_ADGROUP') AS STRING),
           ' rows resolved on channel alone (ad group unresolved) · sources: ',
           COALESCE((SELECT STRING_AGG(CONCAT(src, ' ', CAST(n AS STRING)), ', ' ORDER BY n DESC)
                     FROM (SELECT bid_floor_source src, COUNT(*) n FROM ks GROUP BY 1)), 'none'))
  FROM ks
),
-- ───────────────────────────────────────────────────────────────────────────────────────────
-- c14–c22: the family seat register (v27.127, FAMILY_SEAT_REGISTER.md "Health"). Sources are the
-- pass IMAGE and small tables only. `sr` is T_FAMILY_SEAT_REGISTER — what the brief, the Weekly
-- Run and the cube read — so a check here judges the same image a reader saw, not a live view that
-- may already have moved on (the live view re-anchors the moment the ads watermark advances; the
-- ledger moves only when SP_MAINTAIN_FAMILY_SEATS runs — see "When B04 is valid" in the SOP).
-- Tolerances: $0.01 on a reconciliation, the acceptance suite's own (B01/B02) — an aggregate
-- rendered to the cent against a sum of per-row costs each rounded on its own row (ruling R-m:
-- one cent of aggregate-vs-components drift is a display fact). bid_tol 0.005 mirrors the view's.
-- ───────────────────────────────────────────────────────────────────────────────────────────
sr AS (SELECT * FROM `onyga-482313.OI.T_FAMILY_SEAT_REGISTER`),
sl AS (SELECT * FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`),
sl_open AS (SELECT * FROM sl WHERE closed_on IS NULL),
c14 AS (  -- the register reconciles: categories = the family's spend; seats + leaks + gaps = the bad side
  SELECT 'seat_reconciliation_gap',
    CAST(COUNT(*) AS FLOAT64),
    'FAMILY rows (any horizon) whose CATEGORY rows miss the spend, or whose SEAT(20%)+LEAK+GAP miss the bad side today, by more than $0.01 · red > 0',
    IF(COUNT(*) > 0, 'RED', 'GREEN'),
    CONCAT('largest gap found $', FORMAT('%.4f', COALESCE(MAX(gap), 0)), '/day on the pass image (T_FAMILY_SEAT_REGISTER, as of ',
           COALESCE((SELECT CAST(MAX(as_of) AS STRING) FROM sr), 'no image'), ') — the acceptance suite (B01/B02) holds the live view to the same cent')
  FROM (
    SELECT f.family, f.horizon,
           GREATEST(ABS(COALESCE(c.s, 0) - f.spend_horizon_per_day),
                    IF(f.horizon = 'today', ABS(COALESCE(b.s, 0) - f.bad_side_per_day), 0)) AS gap
    FROM sr f
    LEFT JOIN (SELECT family, horizon, SUM(cost_per_day) AS s FROM sr WHERE row_type = 'CATEGORY' GROUP BY 1, 2) c
           ON c.family = f.family AND c.horizon = f.horizon
    LEFT JOIN (SELECT family, SUM(cost_per_day) AS s FROM sr
               WHERE (row_type = 'SEAT' AND side = '20') OR row_type IN ('LEAK', 'GAP') GROUP BY 1) b
           ON b.family = f.family AND f.horizon = 'today'
    WHERE f.row_type = 'FAMILY'
  )
  WHERE gap > 0.01
),
c15 AS (  -- the ledger's invariants — the ones a second, non-idempotent admission or a re-insert on one snapshot would break
  -- Idempotence PROPER is proven by two runs with one fingerprint (the query in the SOP, "Idempotence");
  -- a view cannot run the procedure twice, so this is the necessary condition, standing every day.
  SELECT 'seat_ledger_idempotence',
    CAST((SELECT COUNT(*) FROM (SELECT family, campaign_id, keyword_id, opened_on FROM sl GROUP BY 1, 2, 3, 4 HAVING COUNT(*) > 1))
       + (SELECT COUNT(*) FROM (SELECT family, campaign_id, keyword_id FROM sl_open GROUP BY 1, 2, 3 HAVING COUNT(*) > 1))
       + (SELECT COUNT(*) FROM (SELECT family, seat_no FROM sl_open GROUP BY 1, 2 HAVING COUNT(*) > 1))
       + (SELECT COUNTIF(seat_no < 1 OR closed_on < opened_on OR opened_on > (SELECT MAX(snapshot_date) FROM ks)) FROM sl) AS FLOAT64),
    'duplicate occupancy keys + keys with two open rows + two keywords on one open number + malformed rows · red > 0',
    IF((SELECT COUNT(*) FROM (SELECT family, campaign_id, keyword_id, opened_on FROM sl GROUP BY 1, 2, 3, 4 HAVING COUNT(*) > 1))
       + (SELECT COUNT(*) FROM (SELECT family, campaign_id, keyword_id FROM sl_open GROUP BY 1, 2, 3 HAVING COUNT(*) > 1))
       + (SELECT COUNT(*) FROM (SELECT family, seat_no FROM sl_open GROUP BY 1, 2 HAVING COUNT(*) > 1))
       + (SELECT COUNTIF(seat_no < 1 OR closed_on < opened_on OR opened_on > (SELECT MAX(snapshot_date) FROM ks)) FROM sl) > 0, 'RED', 'GREEN'),
    CONCAT((SELECT CAST(COUNT(*) AS STRING) FROM sl_open), ' open seats · ', (SELECT CAST(COUNT(*) AS STRING) FROM sl), ' occupancies · ',
           'a second run on the same snapshot must close, reopen and admit nothing — the proof is two runs, one fingerprint (SOP)')
),
c16 AS (  -- every occupant on the image carries its number, once; numbers agree with the ledger
  -- RED only for what the image itself gets wrong (an unnumbered seat, a number held twice).
  -- Image-vs-ledger disagreement is AMBER: between orchestrator step 20.8b (the ledger) and
  -- SP_REFRESH_CUBE_TABLES step 0c (the image) of one pass the two are legitimately apart.
  SELECT 'seat_every_occupant_numbered',
    CAST((SELECT COUNTIF(seat_no IS NULL) FROM sr WHERE row_type = 'SEAT')
       + (SELECT COUNT(*) FROM (SELECT family, seat_no FROM sr WHERE row_type = 'SEAT' AND seat_no IS NOT NULL GROUP BY 1, 2 HAVING COUNT(*) > 1)) AS FLOAT64),
    'SEAT rows on the image with no seat number, or a number held by two seats of one family · red > 0; ledger disagreements amber > 0 (transient inside a pass)',
    CASE WHEN (SELECT COUNTIF(seat_no IS NULL) FROM sr WHERE row_type = 'SEAT')
            + (SELECT COUNT(*) FROM (SELECT family, seat_no FROM sr WHERE row_type = 'SEAT' AND seat_no IS NOT NULL GROUP BY 1, 2 HAVING COUNT(*) > 1)) > 0 THEN 'RED'
         WHEN (SELECT COUNT(*) FROM sr s LEFT JOIN sl_open l ON l.family = s.family AND l.campaign_id = s.campaign_id AND l.keyword_id = s.keyword_id
               WHERE s.row_type = 'SEAT' AND (l.seat_no IS NULL OR l.seat_no != s.seat_no))
            + (SELECT COUNT(*) FROM sl_open l LEFT JOIN sr s ON s.row_type = 'SEAT' AND s.family = l.family AND s.campaign_id = l.campaign_id AND s.keyword_id = l.keyword_id
               WHERE s.keyword_id IS NULL) > 0 THEN 'AMBER'
         ELSE 'GREEN' END,
    CONCAT((SELECT CAST(COUNT(*) AS STRING) FROM sr WHERE row_type = 'SEAT'), ' seats on the image · ',
           CAST((SELECT COUNT(*) FROM sr s LEFT JOIN sl_open l ON l.family = s.family AND l.campaign_id = s.campaign_id AND l.keyword_id = s.keyword_id
                 WHERE s.row_type = 'SEAT' AND (l.seat_no IS NULL OR l.seat_no != s.seat_no)) AS STRING), ' image seats the ledger numbers differently or not at all · ',
           CAST((SELECT COUNT(*) FROM sl_open l LEFT JOIN sr s ON s.row_type = 'SEAT' AND s.family = l.family AND s.campaign_id = l.campaign_id AND s.keyword_id = l.keyword_id
                 WHERE s.keyword_id IS NULL) AS STRING), ' open ledger rows with no seat on the image (compare the last SP_MAINTAIN_FAMILY_SEATS in LOG_PIPELINE_RUNS against the image as_of before calling it a defect)')
),
c17 AS (  -- a launch family is never seated, never judged (house rule 12; V_BOOK_ASSIGNMENT decides the book)
  SELECT 'seat_no_launch_seat',
    CAST((SELECT COUNT(*) FROM sl l LEFT JOIN `onyga-482313.OI.V_BOOK_ASSIGNMENT` b USING (family) WHERE COALESCE(b.book, '') != 'HARVEST')
       + (SELECT COUNT(*) FROM sr s JOIN `onyga-482313.OI.V_BOOK_ASSIGNMENT` b USING (family)
          WHERE b.book != 'HARVEST' AND s.row_type IN ('FAMILY', 'SEAT', 'OPEN_SEAT', 'LEAK', 'GAP', 'ABSORB')) AS FLOAT64),
    'ledger rows (open or closed) outside the HARVEST book + image rows judging a non-HARVEST family · red > 0',
    IF((SELECT COUNT(*) FROM sl l LEFT JOIN `onyga-482313.OI.V_BOOK_ASSIGNMENT` b USING (family) WHERE COALESCE(b.book, '') != 'HARVEST')
       + (SELECT COUNT(*) FROM sr s JOIN `onyga-482313.OI.V_BOOK_ASSIGNMENT` b USING (family)
          WHERE b.book != 'HARVEST' AND s.row_type IN ('FAMILY', 'SEAT', 'OPEN_SEAT', 'LEAK', 'GAP', 'ABSORB')) > 0, 'RED', 'GREEN'),
    'launch (INVEST) families appear on the register as REFERENCE rows only — never a FAMILY read, never a seat, never a move'
),
c18 AS (  -- house rule 13: a holdout campaign is on no sheet while its arm binds (V_HOLDOUT_ARM, from 2026-10-05)
  -- Reads the register's two books in the change log by batch prefix (seat_moves_ / reprice_book_)
  -- at EVERY upload status — a superseded book was still a sheet built with a holdout row on it.
  -- The arm is V_HOLDOUT_ARM (one row per HOLDOUT campaign whose arm binds today or later, any trial;
  -- it filters unit_type = 'CAMPAIGN'): a book row counts when it was built between the campaign's
  -- gate_from and gate_to (holdout restart plan 2026-10-03, Task 6).
  SELECT 'seat_holdout_row_on_sheet',
    CAST(COUNT(*) AS FLOAT64),
    'change-log rows of the seat books (seat_moves_* / reprice_book_*) naming a HOLDOUT-arm campaign, built while its arm binds (V_HOLDOUT_ARM, gate_from .. gate_to) · red > 0',
    IF(COUNT(*) > 0, 'RED', 'GREEN'),
    CONCAT(CAST(COUNTIF(c.upload_status = 'PENDING_UPLOAD') AS STRING), ' pending · ',
           CAST(COUNTIF(c.upload_status IS NULL) AS STRING), ' applied · ',
           CAST(COUNTIF(c.upload_status NOT IN ('PENDING_UPLOAD') AND c.upload_status IS NOT NULL) AS STRING), ' labelled · ',
           'the arm starts ', COALESCE((SELECT CAST(MIN(gate_from) AS STRING) FROM `onyga-482313.OI.V_HOLDOUT_ARM`), 'never'),
           ' — before it a holdout campaign may sit on a book; from it no generator may write one')
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` c
  JOIN `onyga-482313.OI.V_HOLDOUT_ARM` h
    ON h.campaign_id = c.campaign_id
  WHERE (c.batch_id LIKE 'seat_moves_%' OR c.batch_id LIKE 'reprice_book_%')
    AND DATE(c.applied_at, 'America/Los_Angeles') BETWEEN h.gate_from AND h.gate_to
),
c19 AS (  -- ruling R-f: a "raise" is only ever to a price ABOVE the live bid
  SELECT 'seat_raise_at_or_below_live_bid',
    CAST(COUNTIF(move LIKE 'raise to the seat price $%' AND seat_price <= current_bid + 0.005) AS FLOAT64),
    'stalled-probe seats proposing a raise to a seat price at or below the live bid · red > 0',
    IF(COUNTIF(move LIKE 'raise to the seat price $%' AND seat_price <= current_bid + 0.005) > 0, 'RED', 'GREEN'),
    CONCAT(CAST(COUNTIF(move LIKE 'raise to the seat price $%') AS STRING), ' raise proposals · ',
           CAST(COUNTIF(move LIKE 'park it%') AS STRING), ' park proposals · ',
           CAST(COUNTIF(seat_price IS NULL) AS STRING), ' outside the seat model (by hand or park) — the move branches on the sign of seat price − live bid')
  FROM sr WHERE row_type = 'SEAT' AND occupant_kind = 'stalled probe'
),
c20 AS (  -- ruling R-i: a due date already past is never printed as a future event
  SELECT 'seat_past_due_in_future_tense',
    CAST(COUNTIF(due_on < as_of AND NOT (sentence LIKE '%overdue%' AND move LIKE '%overdue%')) AS FLOAT64),
    'seats whose due date is before the image date but whose sentence or move does not say overdue · red > 0',
    IF(COUNTIF(due_on < as_of AND NOT (sentence LIKE '%overdue%' AND move LIKE '%overdue%')) > 0, 'RED', 'GREEN'),
    CONCAT(CAST(COUNTIF(due_on < as_of) AS STRING), ' seats past their due date on the image, all named overdue when this is green · ',
           'the cause is upstream of the register (see seat_overdue_vs_snapshot)')
  FROM sr WHERE row_type = 'SEAT'
),
c21 AS (  -- REPORTS only: appointments the ladder owes, measured on the SNAPSHOT's own date
  -- Not a verdict: the cause is the snapshot procedure stamping a park-era settle_due on revived
  -- and parked rows (diagnosed 2026-08-23, fix proposed and NOT applied — the ladder is outside
  -- the seat register's scope). overdue_appointments (c5) measures the same rows against today's
  -- wall clock; this one against the snapshot date the register judged them on, so it is a pure
  -- function of the snapshot and moves only when the ladder does.
  SELECT 'seat_overdue_vs_snapshot',
    CAST(COUNTIF(next_check_date < snapshot_date AND state != 'DEAD') AS FLOAT64),
    'keywords whose next_check_date is before the snapshot date they were judged on · INFO (reports, never red)',
    'INFO',
    CONCAT('by state: ',
           COALESCE((SELECT STRING_AGG(CONCAT(state, ' ', CAST(n AS STRING)), ', ' ORDER BY n DESC, state)
                     FROM (SELECT state, COUNT(*) n FROM ks WHERE next_check_date < snapshot_date AND state != 'DEAD' GROUP BY 1)), 'none'),
           ' · the register names each seated one overdue (R-i); the ladder fix is open for Ori (FAMILY_SEAT_REGISTER.md "Open rulings")')
  FROM ks
),
c22 AS (  -- REPORTS: days since the seat step last ran inside an orchestrator pass (New York clock)
  -- LOG_PIPELINE_RUNS is written by the orchestrator only — a hand CALL leaves no row — so a row
  -- here IS a pass. started_at is a UTC timestamp; run_date is the UTC date; the orchestrator is
  -- scheduled on New York time, so the day is read as DATE(started_at, 'America/New_York').
  SELECT 'seat_step_days_since_pass',
    CAST(DATE_DIFF(CURRENT_DATE('America/New_York'), MAX(DATE(started_at, 'America/New_York')), DAY) AS FLOAT64),
    'days since SP_MAINTAIN_FAMILY_SEATS last logged OK in a pass, New York clock · amber > 1, red > 2 (the pass is nightly); red when never logged',
    CASE WHEN MAX(started_at) IS NULL THEN 'RED'
         WHEN DATE_DIFF(CURRENT_DATE('America/New_York'), MAX(DATE(started_at, 'America/New_York')), DAY) > 2 THEN 'RED'
         WHEN DATE_DIFF(CURRENT_DATE('America/New_York'), MAX(DATE(started_at, 'America/New_York')), DAY) > 1 THEN 'AMBER'
         ELSE 'GREEN' END,
    CONCAT('last OK pass ', COALESCE(FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', MAX(started_at), 'America/New_York'), 'never'), ' New York · ',
           CAST(COUNT(*) AS STRING), ' OK passes logged · image as of ',
           COALESCE((SELECT CAST(MAX(as_of) AS STRING) FROM sr), 'no image'),
           ' (snapshot ', COALESCE((SELECT CAST(MAX(snapshot_date) AS STRING) FROM ks), 'none'), ')')
  FROM `onyga-482313.OI.LOG_PIPELINE_RUNS`
  WHERE procedure_name = 'SP_MAINTAIN_FAMILY_SEATS' AND status = 'OK'
),
-- ───────────────────────────────────────────────────────────────────────────────────────────
-- c23–c32: the next-week money plan (v27.152, NEXT_WEEK_MONEY.md §6 "Health") and the two
-- alarms for a night that was not saved. Sources: FACT_PLAN_NEXT_WEEK's latest partition (`pl`,
-- live rows `plb`), FACT_ENGINE_PROPOSALS' latest partition (`fep`), T_ENGINE_PREFLIGHT (`pf`,
-- above) and LOG_PIPELINE_RUNS. Tolerance $0.01 on a reconciliation, the acceptance suite's own.
-- EMPTINESS IS RED, NOT GREEN: a check that counts violations over an empty partition finds none,
-- and an empty partition is the very failure these checks exist to catch, so every partition
-- check says RED when it read no rows (the threshold column says so on each).
-- ───────────────────────────────────────────────────────────────────────────────────────────
pl AS (
  SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`)
),
plb AS (SELECT * FROM pl WHERE is_live_plan),
fep AS (
  SELECT * FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`)
),
c23 AS (  -- the window is complete days only, fenced to age 2, and exactly window_days long
  -- The Task 5 draft asserted window_to = watermark - 1, which is P-10 without the P-14a fence and
  -- fails by construction after 22:00 Los Angeles, when FN_ADS_ANCHOR_CAP() advances and the
  -- fence gives up a day (FACT_PLAN_NEXT_WEEK_acceptance.sql C01). The fence is the convention.
  -- v27.160 (2026-10-02, P-24, piece-1 plan Task 6): the fence is two days before the LOS ANGELES
  -- date of the build, as the judge applies it, not before as_of — as_of is the New York date
  -- from v27.160, and on the ~22:35 Los Angeles pass (already the next New York date) as_of - 2 is
  -- a day past the fence while the watermark has advanced to the Los Angeles date, so the v27.152
  -- form reads every row of that partition RED (722 of 722 on a simulated 22:40 Los Angeles pass of
  -- 2026-10-02; this form 0 — NEXT_WEEK_MONEY.md §3, "Which clock keys a night"). The acceptance's
  -- C01 carries the same restatement; check_plan_clock_controls.py controls this check's text.
  SELECT 'plan_window_complete_days' AS check_name,
    CAST(COUNTIF(window_to != LEAST(DATE_SUB(watermark, INTERVAL 1 DAY),
                                    DATE_SUB(DATE(built_at, 'America/Los_Angeles'), INTERVAL 2 DAY))
                 OR DATE_DIFF(window_to, window_from, DAY) + 1 != window_days) AS FLOAT64),
    'rows whose window touches the filling day, breaks the age-2 fence (two days before the Los Angeles date of the build), or is not window_days long · red > 0 (P-10, P-14a, P-24); red when the partition is empty',
    CASE WHEN COUNT(*) = 0 THEN 'RED'
         WHEN COUNTIF(window_to != LEAST(DATE_SUB(watermark, INTERVAL 1 DAY),
                                         DATE_SUB(DATE(built_at, 'America/Los_Angeles'), INTERVAL 2 DAY))
                      OR DATE_DIFF(window_to, window_from, DAY) + 1 != window_days) > 0 THEN 'RED'
         ELSE 'GREEN' END,
    CONCAT('plan of ', COALESCE((SELECT CAST(MAX(as_of) AS STRING) FROM pl), 'none'),
           ' · window ', COALESCE((SELECT CAST(MAX(window_days) AS STRING) FROM pl), '-'),
           ' complete days ending ', COALESCE((SELECT CAST(MAX(window_to) AS STRING) FROM pl), '-'),
           ' · state ', COALESCE((SELECT MAX(calendar_state) FROM pl), '-'),
           ' · ', CAST(COUNT(*) AS STRING), ' rows, both plans')
  FROM pl
),
pot_rec AS (  -- the pot and the allowance per (plan, family), the acceptance's C03/C04 form
  -- P-15 (Ori 2026-10-02, v27.158): the pot is every GOOD keyword's window spend, holdout included
  -- (P-2's own words). The v27.152 form excluded holdout rows under a "(P-2)" label (audit fix #24).
  SELECT plan, family, MAX(pot_per_day) AS pot, MAX(allowance_target_per_day) AS alw,
         MAX(allowance_share) AS share, MAX(allowance_ramped_per_day) AS ramped,
         MAX(notgood_today_per_day) AS ng, MAX(expected_after_upload_per_day) AS exp_after,
         MAX(share_closed) AS closed,
         SAFE_DIVIDE(SUM(IF(side = 'GOOD', w_sp, 0)), MAX(window_days)) AS good
  FROM pl GROUP BY 1, 2
),
c24 AS (  -- the pot and the allowance reconcile to the cent
  SELECT 'plan_pot_reconciliation',
    CAST(COUNTIF(ABS(pot - good) > 0.01 OR ABS(alw - share * pot) > 0.01) AS FLOAT64),
    'plan x family rows whose pot (every GOOD keyword, holdout included) or allowance (share x pot) is off by more than a cent · red > 0 (P-15, P-2); red when the partition is empty',
    CASE WHEN COUNT(*) = 0 THEN 'RED'
         WHEN COUNTIF(ABS(pot - good) > 0.01 OR ABS(alw - share * pot) > 0.01) > 0 THEN 'RED'
         ELSE 'GREEN' END,
    -- the per-family line is built one level down: an aggregate may not enclose another
    CONCAT('per family, live plan: ',
           COALESCE((SELECT STRING_AGG(line, ', ' ORDER BY line) FROM (
                       SELECT FORMAT('%s pot $%.2f/d allowance $%.2f/d not-good $%.2f/d expected after upload $%.2f/d %s',
                                     COALESCE(p.family, '(no family)'),
                                     COALESCE(p.pot, 0), COALESCE(p.ramped, 0), COALESCE(p.ng, 0),
                                     COALESCE(p.exp_after, 0),
                                     IF(p.closed IS NULL, '(no gap to close)',
                                        FORMAT('(%.0f%% of the gap closes)', 100 * p.closed))) AS line
                       FROM pot_rec p JOIN (SELECT DISTINCT plan FROM plb) l USING (plan))), 'none'))
  FROM pot_rec
),
c25 AS (  -- one move per CANDIDATE, none on the good side, none where there is nothing to repair
  -- The draft demanded one of four moves on EVERY not-good row and read 152 violations on a
  -- healthy partition: a keyword with no spend, no clicks and no probe nomination has nothing to
  -- repair and carries NONE by spec §9 (v27.135). This is the acceptance's C06 (v27.147).
  SELECT 'plan_one_move_per_notgood',
    CAST(COUNTIF(side = 'GOOD' AND move != 'NONE')
       + COUNTIF(is_candidate AND move NOT IN ('REPRICE', 'HOLD_AT_PRICE', 'OPEN_PROBE', 'PARK', 'HOLD_AT_PARK', 'PAUSE', 'NONE'))
       + COUNTIF(is_candidate AND move = 'NONE' AND NOT (COALESCE(is_probe, FALSE) AND seat_no IS NULL))
       + COUNTIF(move = 'OPEN_PROBE' AND NOT (is_candidate AND COALESCE(is_probe, FALSE) AND seat_no IS NOT NULL))
       + COUNTIF(NOT is_candidate AND COALESCE(holdout, FALSE) AND side = 'NOT_GOOD' AND move != 'NONE_HOLDOUT')
       + COUNTIF(NOT is_candidate AND NOT COALESCE(holdout, FALSE) AND side = 'NOT_GOOD' AND move != 'NONE')
       + COUNTIF(move IS NULL) AS FLOAT64),
    'live-plan rows: good side carrying a move, candidates carrying none of the seven (an unseated probe NONE, a seated probe OPEN_PROBE, P-25), non-candidates carrying one, rows with no move · red > 0 (P-4, §9); red when the live plan is empty',
    CASE WHEN COUNT(*) = 0 THEN 'RED'
         WHEN COUNTIF(side = 'GOOD' AND move != 'NONE')
            + COUNTIF(is_candidate AND move NOT IN ('REPRICE', 'HOLD_AT_PRICE', 'OPEN_PROBE', 'PARK', 'HOLD_AT_PARK', 'PAUSE', 'NONE'))
       + COUNTIF(is_candidate AND move = 'NONE' AND NOT (COALESCE(is_probe, FALSE) AND seat_no IS NULL))
       + COUNTIF(move = 'OPEN_PROBE' AND NOT (is_candidate AND COALESCE(is_probe, FALSE) AND seat_no IS NOT NULL))
            + COUNTIF(NOT is_candidate AND COALESCE(holdout, FALSE) AND side = 'NOT_GOOD' AND move != 'NONE_HOLDOUT')
            + COUNTIF(NOT is_candidate AND NOT COALESCE(holdout, FALSE) AND side = 'NOT_GOOD' AND move != 'NONE')
            + COUNTIF(move IS NULL) > 0 THEN 'RED'
         ELSE 'GREEN' END,
    CONCAT('moves on the live plan: ',
           COALESCE((SELECT STRING_AGG(CONCAT(move, ' ', CAST(n AS STRING)), ', ' ORDER BY n DESC, move)
                     FROM (SELECT COALESCE(move, '(null)') AS move, COUNT(*) n FROM plb GROUP BY 1)), 'none'),
           ' · ', CAST(COUNTIF(is_candidate) AS STRING), ' candidates')
  FROM plb
),
c26 AS (  -- REPORTS until plan Task 3 ships: foreign GO rows on money levers inside live-plan campaigns
  -- The draft asserted P-11 (nothing but PLAN and LOW_STOCK moves money in a plan family) with
  -- red > 0. Measured 2026-10-01: no engine PLAN has written a proposal and no row carries
  -- hold_source = 'PLAN' — plan Task 3 (ownership and the preflight) is not built, so the plan
  -- owns nothing at the gate and a RED here would be a verdict on work that does not exist. It
  -- counts the rows a RED would count, as a number, and says so; when Task 3 ships, the status
  -- becomes IF(count > 0, 'RED', 'GREEN') and this comment is retired.
  SELECT 'plan_ownership_no_foreign_go',
    CAST((SELECT COUNTIF(engine NOT IN ('PLAN', 'LOW_STOCK') AND lever IN ('BID', 'BUDGET') AND verdict = 'GO'
                         AND campaign_id IN (SELECT DISTINCT campaign_id FROM plb)) FROM pf) AS FLOAT64),
    'GO rows on a money lever from an engine other than PLAN or LOW_STOCK, inside a live-plan campaign · INFO (reports) until plan Task 3 ships, then red > 0 (P-11)',
    'INFO',
    CONCAT('plan Task 3 is NOT built — no engine PLAN writes proposals and no proposal carries hold_source PLAN, so the plan holds no ownership at the gate yet · foreign GO rows on money levers inside live-plan campaigns, by engine: ',
           COALESCE((SELECT STRING_AGG(CONCAT(engine, ' ', CAST(n AS STRING)), ', ' ORDER BY n DESC, engine)
                     FROM (SELECT engine, COUNT(*) n FROM pf
                           WHERE engine NOT IN ('PLAN', 'LOW_STOCK') AND lever IN ('BID', 'BUDGET') AND verdict = 'GO'
                             AND campaign_id IN (SELECT DISTINCT campaign_id FROM plb)
                           GROUP BY 1)), 'none'),
           ' · held by the plan today: ', CAST((SELECT COUNTIF(hold_source = 'PLAN') FROM fep) AS STRING), ' proposal(s)',
           ' · live-plan campaigns: ', CAST((SELECT COUNT(DISTINCT campaign_id) FROM plb) AS STRING))
),
c27 AS (  -- both plans are written every night
  SELECT 'plan_both_plans_written',
    CAST((SELECT COUNT(DISTINCT plan) FROM pl) AS FLOAT64),
    'distinct plans in the latest partition · must be 2 (A shadow + B live); red otherwise, red when the partition is empty (P-9)',
    IF((SELECT COUNT(DISTINCT plan) FROM pl) = 2, 'GREEN', 'RED'),
    CONCAT('live plan is ', COALESCE((SELECT MAX(plan) FROM plb), 'none'),
           ' · rows A/B: ', CAST((SELECT COUNTIF(plan = 'A') FROM pl) AS STRING), '/',
           CAST((SELECT COUNTIF(plan = 'B') FROM pl) AS STRING),
           ' · partition ', COALESCE((SELECT CAST(MAX(as_of) AS STRING) FROM pl), 'none'))
),
guard AS (  -- the P-14b/P-14c ledger on the live plan, counted once for c28
  -- under_guard = the guard's PRECONDITIONS (demoted, was good, served, unsettled). A row under
  -- them is legitimate iff the judge published why it released it: guard_released_by is READ,
  -- never re-derived (the builder re-derived it and vetoed every partition 2026-08-29..09-28).
  SELECT COUNT(*) AS n_rows,
         COUNTIF(under_guard) AS n_under,
         COUNTIF(under_guard AND guard_released_by = 'LAST_DAY_NOT_STRONG') AS n_lds,
         COUNTIF(under_guard AND guard_released_by = 'HOLD_EXPIRED') AS n_exp,
         COUNTIF(under_guard AND COALESCE(guard_released_by, '') NOT IN ('HOLD_EXPIRED', 'LAST_DAY_NOT_STRONG')) AS n_no_release,
         COUNTIF(under_guard AND guard_released_by IS NULL) AS n_null_release,
         COUNTIF(verdict = 'HELD_UNSETTLED') AS n_held,
         -- P-18 (v27.156): a hold is earned by a very good last day OR kept while the very good
         -- day that started it is still inside the window; hold_kept_by is READ, never re-derived
         COUNTIF(verdict = 'HELD_UNSETTLED'
                 AND NOT (COALESCE(last_day_strong, FALSE)
                          OR (COALESCE(hold_kept_by, '') = 'STRONG_DAY_IN_WINDOW'
                              AND COALESCE(window_from <= hold_strong_day, FALSE)))) AS n_held_weak,
         COUNTIF(verdict = 'HELD_UNSETTLED' AND hold_kept_by = 'STRONG_DAY_IN_WINDOW') AS n_held_kept_sd,
         SAFE_DIVIDE(SUM(IF(verdict = 'HELD_UNSETTLED', w_sp, 0)), MAX(window_days)) AS held_per_day
  FROM (SELECT *, (side = 'NOT_GOOD' AND COALESCE(was_good, FALSE) AND COALESCE(served, FALSE)
                   AND NOT COALESCE(settled, FALSE)) AS under_guard
        FROM plb)
),
c28 AS (  -- P-14b is a clock and P-14c a last-day test, not a veto: every release is PUBLISHED, every hold is EARNED
  SELECT 'plan_settle_guard_holds',
    CAST(n_no_release + n_held_weak AS FLOAT64),
    'live-plan rows demoted under the guard preconditions (not-good, was good, served, unsettled) with no release the judge published (HOLD_EXPIRED | LAST_DAY_NOT_STRONG), plus HELD_UNSETTLED rows held by neither a very good last day nor (hold_kept_by STRONG_DAY_IN_WINDOW) the very good day that started the hold still inside the window · red > 0 (P-14b, P-14c, P-18); red when the live plan is empty',
    CASE WHEN n_rows = 0 THEN 'RED' WHEN n_no_release + n_held_weak > 0 THEN 'RED' ELSE 'GREEN' END,
    CONCAT('under the guard preconditions: ', CAST(n_under AS STRING),
           ' — released by LAST_DAY_NOT_STRONG ', CAST(n_lds AS STRING),
           ', HOLD_EXPIRED ', CAST(n_exp AS STRING),
           ', no release published ', CAST(n_null_release AS STRING),
           ', unknown reason ', CAST(n_no_release - n_null_release AS STRING),
           ' · held (HELD_UNSETTLED): ', CAST(n_held AS STRING),
           ', of which kept by the very good day still in the window ', CAST(n_held_kept_sd AS STRING),
           ', held by neither ', CAST(n_held_weak AS STRING),
           ' · the hold is $', FORMAT('%.2f', COALESCE(held_per_day, 0)),
           '/day of window spend the not-good side does not see yet')
  FROM guard
),
c29 AS (  -- REPORTS: how much of the correction the curve could actually answer for
  SELECT 'plan_settle_curve_coverage',
    CAST(SAFE_DIVIDE(COUNTIF(COALESCE(settle_curve_available, FALSE)), NULLIF(COUNT(*), 0)) AS FLOAT64),
    'share of live-plan rows whose settle curve could answer · INFO (reports); 0 means the plan rests on the guard alone (P-14a)',
    'INFO',
    CONCAT(CAST(COUNTIF(NOT COALESCE(settle_curve_available, FALSE)) AS STRING),
           ' row(s) uncorrected because the curve could not answer · smallest factor applied ',
           FORMAT('%.3f', COALESCE(MIN(settle_factor_min), 1.0)),
           ' · arms: ',
           COALESCE((SELECT STRING_AGG(CONCAT(settle_arm, ' ', CAST(n AS STRING)), ', ' ORDER BY n DESC, settle_arm)
                     FROM (SELECT COALESCE(settle_arm, '(null)') AS settle_arm, COUNT(*) n FROM plb GROUP BY 1)), 'none'))
  FROM plb
),
c30 AS (  -- REPORTS: how far the live plan sits behind the proposal snapshot
  SELECT 'plan_proposal_lag_days',
    CAST(DATE_DIFF((SELECT MAX(snapshot_date) FROM fep),
                   COALESCE((SELECT MAX(as_of) FROM plb), DATE '1900-01-01'), DAY) AS FLOAT64),
    'days between the latest proposal snapshot and the latest live plan · INFO (reports); amber > 2; red when no live plan exists',
    CASE WHEN (SELECT MAX(as_of) FROM plb) IS NULL THEN 'RED'
         WHEN DATE_DIFF((SELECT MAX(snapshot_date) FROM fep), (SELECT MAX(as_of) FROM plb), DAY) > 2 THEN 'AMBER'
         ELSE 'INFO' END,
    CONCAT('proposals of ', COALESCE((SELECT CAST(MAX(snapshot_date) AS STRING) FROM fep), 'none'),
           ' · live plan of ', COALESCE((SELECT CAST(MAX(as_of) AS STRING) FROM plb), 'none'),
           ' · the proposal snapshot (Task 20.6) runs before the plan (20.8c) inside one pass, so the proposals read the plan an earlier pass wrote — one pass of lag is by design (open ruling for Ori)')
),
plan_clock AS (  -- the day the plan step was last REACHED (OK or FAIL) and the latest plan saved
  -- The orchestrator passes three times a day (about 01:35, 04:10 and 12:40 New York). Until
  -- v27.159 the plan step wrote as_of = CURRENT_DATE('America/Los_Angeles'), so a plan for Los
  -- Angeles day D first existed after the 04:10 New York pass; from v27.160 (P-24) it writes the New
  -- York date, so the 01:35 pass already writes New York day D. A New York as_of is never earlier
  -- than the Los Angeles day of the same build, so every pass that saved its partition meets the
  -- Los Angeles due date below, and a pass that reached the step on Los Angeles day L while no
  -- partition dated L or later exists still reads RED (this clock is unchanged by v27.160).
  -- "MAX(as_of) < today" alone would be RED every
  -- day between midnight and the first pass for no reason. The due date is the LATER of two days: the
  -- Los Angeles day of the last LOG_PIPELINE_RUNS row the plan step itself logged (a pass that
  -- reached the step and did not save a partition for its own day is the outage — OK or FAIL,
  -- because an OK that saved nothing is the same failure), and yesterday (so a dead orchestrator
  -- is RED the next morning). A hand CALL leaves no row and does not move the clock.
  SELECT GREATEST(COALESCE((SELECT MAX(DATE(started_at, 'America/Los_Angeles'))
                            FROM `onyga-482313.OI.LOG_PIPELINE_RUNS`
                            WHERE procedure_name = 'SP_BUILD_NEXT_WEEK_PLAN'
                              AND run_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)), DATE '1900-01-01'),
                  DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY)) AS due,
         (SELECT MAX(started_at) FROM `onyga-482313.OI.LOG_PIPELINE_RUNS`
          WHERE procedure_name = 'SP_BUILD_NEXT_WEEK_PLAN'
            AND run_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)) AS last_reached_at,
         (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`) AS last_plan
),
c31 AS (  -- ALARM: a night the plan was not saved
  SELECT 'plan_partition_fresh',
    CAST(IF(last_plan IS NULL, NULL, GREATEST(DATE_DIFF(due, last_plan, DAY), 0)) AS FLOAT64),
    'nights with no plan partition, up to the later of yesterday and the Los Angeles day the plan step last ran (OK or FAIL) · red > 0; red when no plan was ever saved',
    CASE WHEN last_plan IS NULL THEN 'RED' WHEN last_plan < due THEN 'RED' ELSE 'GREEN' END,
    CONCAT('last plan ', COALESCE(CAST(last_plan AS STRING), 'never'), ', ',
           IF(last_plan IS NULL, 'every night',
              CONCAT(CAST(GREATEST(DATE_DIFF(due, last_plan, DAY), 0) AS STRING), ' night(s)')),
           ' missing · a plan is due for every night up to ', CAST(due AS STRING),
           ' · the plan step last ran ',
           COALESCE(FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', last_reached_at, 'America/Los_Angeles'), 'never in 7 days'),
           ' Los Angeles · the step is SP_BUILD_NEXT_WEEK_PLAN (Refresh Task 20.8c); its error, if it failed, is on pipeline_step_failing and in LOG_PIPELINE_RUNS; nothing re-runs it by itself')
  FROM plan_clock
),
pr AS (  -- every procedure's runs in the last 30 days, newest first
  -- Declared constants: 30 days is the memory (older failures belong to a step nothing runs
  -- any more, which the freshness checks own); 3 runs is the streak (the pass runs three times a
  -- day, so a step broken for one night fails three runs and is named the next morning).
  SELECT procedure_name, status, error_message, started_at,
         ROW_NUMBER() OVER (PARTITION BY procedure_name ORDER BY started_at DESC) AS rn
  FROM `onyga-482313.OI.LOG_PIPELINE_RUNS`
  WHERE run_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
),
pipe_fail AS (  -- procedures whose three most recent runs all logged FAIL, with the streak behind them
  SELECT f.procedure_name, f.last_error, f.last_started,
         s.n_streak, s.streak_since
  FROM (SELECT procedure_name,
               ARRAY_AGG(IF(rn = 1, SUBSTR(COALESCE(error_message, '(no message)'), 1, 120), NULL) IGNORE NULLS)[SAFE_OFFSET(0)] AS last_error,
               MAX(IF(rn = 1, started_at, NULL)) AS last_started
        FROM pr WHERE rn <= 3
        GROUP BY 1
        HAVING COUNT(*) = 3 AND COUNTIF(status = 'FAIL') = 3) f
  JOIN (SELECT p.procedure_name,
               COUNTIF(p.rn < COALESCE(o.first_ok_rn, 2147483647)) AS n_streak,
               MIN(IF(p.rn < COALESCE(o.first_ok_rn, 2147483647), p.started_at, NULL)) AS streak_since
        FROM pr p
        LEFT JOIN (SELECT procedure_name, MIN(IF(status != 'FAIL', rn, NULL)) AS first_ok_rn
                   FROM pr GROUP BY 1) o USING (procedure_name)
        GROUP BY 1) s USING (procedure_name)
),
c32 AS (  -- ALARM, GENERIC: a step that fails three runs running is a step nobody is running by hand
  -- This is the check that would have named SP_BUILD_NEXT_WEEK_PLAN on 2026-08-29, the first
  -- night of its month-long outage. It names ANY procedure, so the next outage needs no new check.
  SELECT 'pipeline_step_failing',
    CAST((SELECT COUNT(*) FROM pipe_fail) AS FLOAT64),
    'procedures whose three most recent runs (last 30 days, by started_at) all logged FAIL · red > 0',
    IF((SELECT COUNT(*) FROM pipe_fail) > 0, 'RED', 'GREEN'),
    COALESCE((SELECT STRING_AGG(CONCAT(procedure_name, ': ', last_error,
                                       ' [', CAST(n_streak AS STRING), ' run(s) failing in a row since ',
                                       FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', streak_since, 'America/New_York'), ' New York]'),
                                '; ' ORDER BY last_started DESC) FROM pipe_fail),
             CONCAT('no step has failed its last three runs · ',
                    CAST((SELECT COUNT(DISTINCT procedure_name) FROM pr) AS STRING), ' procedures logged in the last 30 days · ',
                    CAST((SELECT COUNTIF(status = 'FAIL') FROM pr) AS STRING), ' FAIL row(s) among ',
                    CAST((SELECT COUNT(*) FROM pr) AS STRING), ' runs · last run ',
                    COALESCE((SELECT FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', MAX(started_at), 'America/New_York') FROM pr), 'never'),
                    ' New York'))
),
-- ───────────────────────────────────────────────────────────────────────────────────────────
-- c34: plan_pass_failed (v27.163, piece-1 plan Task 9, Step 1; header). ppr and ppf read only
-- LOG_PIPELINE_RUNS; PLAN_HEALTH_acceptance.sql (A1) carries their twin. THE TWO MUST CHANGE TOGETHER.
-- Placed before c33 on purpose: HOLDOUT_INTEGRITY_acceptance.sql's text-identity command reads c33 up
-- to the first line ')' after it, which must stay the end of the CTE list.
-- Declared constants: 24 hours (passes start about 01:00, 03:35 and 12:00 New York — LOG_PIPELINE_RUNS
-- 10-01..10-03 — so a day holds three and the longest gap between two is about 13 hours) and the
-- 30-day log window of pr.
-- ───────────────────────────────────────────────────────────────────────────────────────────
ppr AS (  -- the plan step's runs in the last 30 days, newest first
  SELECT status, error_message, started_at,
         ROW_NUMBER() OVER (ORDER BY started_at DESC) AS rn
  FROM `onyga-482313.OI.LOG_PIPELINE_RUNS`
  WHERE procedure_name = 'SP_BUILD_NEXT_WEEK_PLAN'
    AND run_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
),
ppf AS (  -- the runs the check judges: the latest one, and every one in the last 24 hours
  SELECT COUNTIF(status = 'FAIL' AND (rn = 1 OR started_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR))) AS n_fail,
         COUNTIF(started_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)) AS n_24h,
         COUNTIF(status = 'FAIL' AND started_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)) AS n_fail_24h,
         MAX(IF(rn = 1, status, NULL)) AS latest_status,
         MAX(IF(rn = 1, started_at, NULL)) AS latest_at,
         -- the newest judged failure, with its message
         ARRAY_AGG(IF(status = 'FAIL' AND (rn = 1 OR started_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)),
                      STRUCT(started_at AS fail_at, error_message AS fail_msg), NULL)
                   IGNORE NULLS ORDER BY started_at DESC LIMIT 1)[SAFE_OFFSET(0)] AS fail,
         MAX(IF(status = 'FAIL', started_at, NULL)) AS last_fail_30d
  FROM ppr
),
c34 AS (  -- ALARM: a pass of the plan step failed — the latest run, or any run in the last 24 hours
  -- plan_partition_fresh needs a whole night missing and pipeline_step_failing three failed runs in a
  -- row; 3 of 9 passes refused 2026-09-29 -> 10-01, never more than two in a row, and another pass
  -- saved each night (header). This check is RED on the first read of the board after a refused pass.
  SELECT 'plan_pass_failed',
    CAST(n_fail AS FLOAT64),
    'SP_BUILD_NEXT_WEEK_PLAN runs that logged FAIL — its latest run (last 30 days) and every run in the last 24 hours · red > 0; red when the step logged no run in the last 24 hours (a pass reaches it three times a day)',
    CASE WHEN n_24h = 0 THEN 'RED' WHEN n_fail > 0 THEN 'RED' ELSE 'GREEN' END,
    CONCAT(
      IF(fail.fail_at IS NOT NULL,
         CONCAT('FAIL ', FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', fail.fail_at, 'America/New_York'), ' New York: ',
                SUBSTR(COALESCE(fail.fail_msg, '(no message)'), 1, 160), ' · '),
         ''),
      IF(n_24h = 0,
         'no plan run logged in the last 24 hours · ',
         ''),
      'latest plan run ', COALESCE(latest_status, 'none'), ' ',
      COALESCE(CONCAT(FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', latest_at, 'America/New_York'), ' New York'), 'in 30 days'),
      ' · ', CAST(n_fail_24h AS STRING), ' of ', CAST(n_24h AS STRING), ' plan run(s) in the last 24 hours failed',
      ' · last failure ', COALESCE(CONCAT(FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', last_fail_30d, 'America/New_York'), ' New York'), 'none in 30 days'),
      ' · the step is SP_BUILD_NEXT_WEEK_PLAN (Refresh Task 20.8c); nothing re-runs a failed pass by itself')
  FROM ppf
),
-- ───────────────────────────────────────────────────────────────────────────────────────────
-- c35–c37: the learning contract (v27.176, piece-2 Task 6; header; architecture/LEARNING.md §6). The
-- plan's predictions (V_PREDICTION_LEDGER) are graded nightly by SP_GRADE_PREDICTIONS (Refresh Task
-- 20.8f) into FACT_PREDICTION_GRADE and summed into the report card T_PREDICTION_SCORECARD.
-- lrn_set / lrn_wm / lrn_led / lrn_grd / lrn_act / lrn_card / lrn_card_meta are the seven inputs;
-- lrn_due through c37 read nothing else, so PLAN_HEALTH_acceptance.sql (P1-P3) runs the lrn_due ..
-- c37 text verbatim on doctored copies of them. THE TWO MUST CHANGE TOGETHER. No whole-line comment
-- inside that text: the deploy strips those, and the text-identity command compares the file's
-- block with the deployed body. Placed before c33, which must stay last (HOLDOUT_INTEGRITY).
-- Settings: DE_COACH_THRESHOLDS, strategy_id LEARNING, coach_mode GUARDIAN, product_family NULL,
-- today's values (the rows the grader reads); never literals here.
-- ───────────────────────────────────────────────────────────────────────────────────────────
lrn_set AS (  -- the three LEARNING settings these checks read, today's values (one row even when none is present)
  SELECT CAST(MAX(IF(threshold_key = 'SETTLE_HORIZON_DAYS', threshold_value, NULL)) AS INT64) AS settle_days,
         CAST(MAX(IF(threshold_key = 'MIN_GRADED_WINDOWS', threshold_value, NULL)) AS INT64) AS min_windows,
         MAX(IF(threshold_key = 'REGRESSION_MAX', threshold_value, NULL)) AS regression_max
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  WHERE strategy_id = 'LEARNING' AND coach_mode = 'GUARDIAN' AND product_family IS NULL
    AND threshold_key IN ('SETTLE_HORIZON_DAYS', 'MIN_GRADED_WINDOWS', 'REGRESSION_MAX')
),
lrn_wm AS (  -- the house watermark, the grader's own expression, with its two terms for the detail line
  SELECT MAX(date) AS ads_max, `onyga-482313.OI.FN_ADS_ANCHOR_CAP`() AS anchor_cap,
         LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS wm
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),
lrn_led AS (  -- every prediction of the ledger: its grade key and its horizon end
  SELECT predictor, variant, as_of, campaign_id, keyword_id, scenario, horizon_to
  FROM `onyga-482313.OI.V_PREDICTION_LEDGER`
),
lrn_grd AS (  -- every prediction that holds a grade (any regrade_seq); the contract suite's fixtures excluded
  SELECT DISTINCT predictor, variant, as_of, campaign_id, keyword_id, scenario
  FROM `onyga-482313.OI.FACT_PREDICTION_GRADE`
  WHERE predictor <> 'FIXTURE'
),
lrn_act AS (  -- the current grade (highest regrade_seq) of every ACT prediction, fixtures excluded
  SELECT is_applied, act_is_noop, applied_scenario, grade
  FROM `onyga-482313.OI.FACT_PREDICTION_GRADE`
  WHERE predictor <> 'FIXTURE' AND scenario = 'ACT'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY predictor, variant, as_of, campaign_id, keyword_id, scenario
                             ORDER BY regrade_seq DESC) = 1
),
lrn_card AS (  -- the report card's WINDOW rows of each predictor's rollup: the applied scenario's accuracy, and the money
  SELECT predictor, row_type, window_from, mae_net_usd, real_spend, counterfactual_net_per_alloc, alloc_spend,
         rule_versions, builder_versions
  FROM `onyga-482313.OI.T_PREDICTION_SCORECARD`
  WHERE level = 'WINDOW' AND family = 'ALL' AND calendar_state = 'ALL' AND predictor <> 'FIXTURE'
    AND ((row_type = 'ACCURACY' AND scenario = 'APPLIED') OR row_type = 'MONEY')
),
lrn_card_meta AS (  -- the card's size and when the grader last rebuilt it; an empty card is a grader that has not run
  SELECT COUNT(*) AS n_rows, MAX(scored_at) AS scored_at
  FROM `onyga-482313.OI.T_PREDICTION_SCORECARD`
  WHERE predictor <> 'FIXTURE'
),
lrn_due AS (  -- each ledger row: past due (one night after the house watermark made it gradable) or not, graded or not
  SELECT l.predictor, l.as_of,
         DATE_ADD(l.horizon_to, INTERVAL (s.settle_days + 1) DAY) AS due_on,
         COALESCE(DATE_ADD(l.horizon_to, INTERVAL (s.settle_days + 1) DAY) <= w.wm, FALSE) AS is_due,
         g.predictor IS NOT NULL AS graded
  FROM lrn_led l
  CROSS JOIN lrn_set s
  CROSS JOIN lrn_wm w
  LEFT JOIN lrn_grd g
    ON g.predictor = l.predictor AND g.variant = l.variant AND g.as_of = l.as_of
   AND g.campaign_id = l.campaign_id AND g.keyword_id = l.keyword_id AND g.scenario = l.scenario
),
c35 AS (  -- the grader keeps up: no ledger row stays ungraded a night after the house watermark made it gradable
  SELECT 'prediction_grades_fresh' AS check_name,
    CAST(COUNTIF(is_due AND NOT graded) AS FLOAT64),
    'ledger rows (V_PREDICTION_LEDGER, both scenarios) with no grade in FACT_PREDICTION_GRADE one night after they became gradable: horizon_to + SETTLE_HORIZON_DAYS + 1 on or before the house watermark LEAST(MAX(FACT_AMAZON_ADS.date), FN_ADS_ANCHOR_CAP()) · red > 0; red when no ledger row is that old (an empty population), or the setting or the watermark is missing',
    CASE WHEN (SELECT settle_days FROM lrn_set) IS NULL OR (SELECT wm FROM lrn_wm) IS NULL THEN 'RED'
         WHEN COUNTIF(is_due) = 0 THEN 'RED'
         WHEN COUNTIF(is_due AND NOT graded) > 0 THEN 'RED'
         ELSE 'GREEN' END,
    CONCAT(
      IF((SELECT settle_days FROM lrn_set) IS NULL,
         'SETTLE_HORIZON_DAYS is not in DE_COACH_THRESHOLDS (LEARNING, GUARDIAN, family NULL), so no row can fall due · ', ''),
      IF((SELECT wm FROM lrn_wm) IS NULL, 'the house watermark is NULL (FACT_AMAZON_ADS holds no row) · ', ''),
      CAST(COUNTIF(is_due AND NOT graded) AS STRING), ' of ', CAST(COUNTIF(is_due) AS STRING),
      ' ledger rows past due have no grade',
      IF(COUNTIF(is_due AND NOT graded) > 0,
         CONCAT(' (nights ', CAST(MIN(IF(is_due AND NOT graded, as_of, NULL)) AS STRING), ' to ',
                CAST(MAX(IF(is_due AND NOT graded, as_of, NULL)) AS STRING), ')'),
         ''),
      ' · watermark ', COALESCE(CAST((SELECT wm FROM lrn_wm) AS STRING), 'NULL'),
      ' = LEAST(FACT_AMAZON_ADS newest day ', COALESCE(CAST((SELECT ads_max FROM lrn_wm) AS STRING), 'none'),
      ', FN_ADS_ANCHOR_CAP() ', COALESCE(CAST((SELECT anchor_cap FROM lrn_wm) AS STRING), 'NULL'), ')',
      ' · a row is gradable at horizon end + ', COALESCE(CAST((SELECT settle_days FROM lrn_set) AS STRING), '(no setting)'),
      ' days, past due one night later · ', CAST(COUNTIF(NOT is_due) AS STRING), ' ledger rows not yet past due',
      COALESCE(CONCAT(', the next when the watermark reaches ', CAST(MIN(IF(NOT is_due, due_on, NULL)) AS STRING)), ''),
      ' · the grader is SP_GRADE_PREDICTIONS (Refresh Task 20.8f); nothing re-runs it by itself')
  FROM lrn_due
),
lrn_win AS (  -- one row per predictor and graded window (the Sunday-start week of as_of: the card's WINDOW level), newest first
  SELECT predictor, window_from,
         SUM(IF(row_type = 'ACCURACY', mae_net_usd, NULL)) AS mae_usd,
         SUM(IF(row_type = 'ACCURACY', real_spend, NULL)) AS real_spend,
         SUM(IF(row_type = 'MONEY', counterfactual_net_per_alloc * alloc_spend, NULL)) AS cf_net,
         SUM(IF(row_type = 'MONEY', alloc_spend, NULL)) AS alloc,
         STRING_AGG(IF(row_type = 'MONEY', rule_versions, NULL), ',') AS rvs,
         STRING_AGG(IF(row_type = 'MONEY', builder_versions, NULL), ',') AS bvs,
         ROW_NUMBER() OVER (PARTITION BY predictor ORDER BY window_from DESC) AS wr
  FROM lrn_card
  GROUP BY predictor, window_from
),
lrn_span AS (  -- per predictor: the trailing MIN_GRADED_WINDOWS windows (t) and the MIN_GRADED_WINDOWS before them (p), each pooled
  SELECT w.predictor, COUNT(*) AS n_windows,
         STRING_AGG(CAST(w.window_from AS STRING), ' ' ORDER BY w.window_from) AS all_weeks,
         STRING_AGG(IF(w.wr <= s.min_windows, CAST(w.window_from AS STRING), NULL), ' ' ORDER BY w.window_from) AS t_weeks,
         STRING_AGG(IF(w.wr > s.min_windows AND w.wr <= 2 * s.min_windows, CAST(w.window_from AS STRING), NULL), ' '
                    ORDER BY w.window_from) AS p_weeks,
         SAFE_DIVIDE(SUM(IF(w.wr <= s.min_windows, w.mae_usd, NULL)),
                     SUM(IF(w.wr <= s.min_windows, w.real_spend, NULL))) AS mae_t,
         SAFE_DIVIDE(SUM(IF(w.wr > s.min_windows AND w.wr <= 2 * s.min_windows, w.mae_usd, NULL)),
                     SUM(IF(w.wr > s.min_windows AND w.wr <= 2 * s.min_windows, w.real_spend, NULL))) AS mae_p,
         SAFE_DIVIDE(SUM(IF(w.wr <= s.min_windows, w.cf_net, NULL)),
                     SUM(IF(w.wr <= s.min_windows, w.alloc, NULL))) AS cf_t,
         SAFE_DIVIDE(SUM(IF(w.wr > s.min_windows AND w.wr <= 2 * s.min_windows, w.cf_net, NULL)),
                     SUM(IF(w.wr > s.min_windows AND w.wr <= 2 * s.min_windows, w.alloc, NULL))) AS cf_p
  FROM lrn_win w
  CROSS JOIN lrn_set s
  GROUP BY w.predictor
),
lrn_chg AS (  -- per predictor, every rule or builder version behind one span and not the other: what changed between them
  SELECT predictor, STRING_AGG(CONCAT(kind, IF(in_t, ' new ', ' gone '), v), ', ' ORDER BY kind, in_t, v) AS changed
  FROM (SELECT w.predictor, x.kind, v,
               LOGICAL_OR(w.wr <= s.min_windows) AS in_t,
               LOGICAL_OR(w.wr > s.min_windows) AS in_p
        FROM lrn_win w
        CROSS JOIN lrn_set s
        CROSS JOIN UNNEST([STRUCT('rule_version' AS kind, w.rvs AS vs), STRUCT('builder_version' AS kind, w.bvs AS vs)]) AS x
        CROSS JOIN UNNEST(SPLIT(x.vs, ',')) AS v
        WHERE w.wr <= 2 * s.min_windows
        GROUP BY w.predictor, x.kind, v)
  WHERE in_t != in_p
  GROUP BY predictor
),
lrn_reg AS (  -- per predictor: judged once it has twice MIN_GRADED_WINDOWS windows; worse = by more than REGRESSION_MAX of the earlier value
  SELECT p.predictor, p.n_windows, p.all_weeks, p.t_weeks, p.p_weeks, p.mae_t, p.mae_p, p.cf_t, p.cf_p, c.changed,
         p.n_windows >= 2 * s.min_windows AS judged,
         COALESCE(p.mae_t - p.mae_p > s.regression_max * ABS(p.mae_p), FALSE) AS mae_worse,
         COALESCE(p.cf_p - p.cf_t > s.regression_max * ABS(p.cf_p), FALSE) AS cf_worse,
         s.min_windows
  FROM lrn_span p
  CROSS JOIN lrn_set s
  LEFT JOIN lrn_chg c ON c.predictor = p.predictor
),
lrn_reg_line AS (  -- one sentence per predictor, built one level below the check's aggregate
  SELECT predictor, judged, mae_worse, cf_worse,
         IF(COALESCE(judged, FALSE),
            CONCAT(predictor, ': mae_net_share ', COALESCE(FORMAT('%.4f', mae_t), 'none'), ' over ', COALESCE(t_weeks, '-'),
                   ' against ', COALESCE(FORMAT('%.4f', mae_p), 'none'), ' over ', COALESCE(p_weeks, '-'),
                   ', counterfactual_net_per_alloc ', COALESCE(FORMAT('%.4f', cf_t), 'none'),
                   ' against ', COALESCE(FORMAT('%.4f', cf_p), 'none'),
                   CASE WHEN mae_worse AND cf_worse THEN ' — WORSE on accuracy and on money'
                        WHEN mae_worse THEN ' — WORSE on accuracy'
                        WHEN cf_worse THEN ' — WORSE on money'
                        ELSE ' — not worse by more than the margin' END,
                   IF(changed IS NULL, ' · no rule or builder version changed between them',
                      CONCAT(' · changed between them: ', changed))),
            CONCAT(predictor, ': YOUNG, ', CAST(n_windows AS STRING), ' of ', COALESCE(CAST(2 * min_windows AS STRING), '?'),
                   ' windows graded (', COALESCE(all_weeks, '-'), ')')) AS line
  FROM lrn_reg
),
c36 AS (  -- the predictions do not get quietly worse: trailing windows against the ones before them, per predictor
  SELECT 'prediction_regression',
    CAST(COUNTIF(COALESCE(judged, FALSE) AND (mae_worse OR cf_worse)) AS FLOAT64),
    'predictors whose trailing MIN_GRADED_WINDOWS graded windows (the Sunday-start weeks of as_of: the report card\'s WINDOW rows, family ALL) are worse than the MIN_GRADED_WINDOWS before them by more than REGRESSION_MAX of the earlier value, on mae_net_share of the applied scenario (higher is worse) or counterfactual_net_per_alloc (lower is worse) · red > 0; INFO (YOUNG) while no predictor has twice MIN_GRADED_WINDOWS graded windows; red when the report card is empty or a setting is missing',
    CASE WHEN (SELECT min_windows FROM lrn_set) IS NULL OR (SELECT regression_max FROM lrn_set) IS NULL THEN 'RED'
         WHEN (SELECT n_rows FROM lrn_card_meta) = 0 THEN 'RED'
         WHEN COUNTIF(COALESCE(judged, FALSE) AND (mae_worse OR cf_worse)) > 0 THEN 'RED'
         WHEN COUNTIF(COALESCE(judged, FALSE)) = 0 THEN 'INFO'
         ELSE 'GREEN' END,
    CONCAT(
      IF((SELECT min_windows FROM lrn_set) IS NULL OR (SELECT regression_max FROM lrn_set) IS NULL,
         'MIN_GRADED_WINDOWS or REGRESSION_MAX is not in DE_COACH_THRESHOLDS (LEARNING, GUARDIAN, family NULL) · ', ''),
      IF((SELECT n_rows FROM lrn_card_meta) = 0,
         'the report card T_PREDICTION_SCORECARD is empty: SP_GRADE_PREDICTIONS has not rebuilt it · ', ''),
      IF(COUNTIF(COALESCE(judged, FALSE)) = 0, 'YOUNG — ', ''),
      COALESCE(STRING_AGG(line, '; ' ORDER BY predictor), 'no graded window on the card'),
      ' · the trailing ', COALESCE(CAST((SELECT min_windows FROM lrn_set) AS STRING), '(no setting)'),
      ' windows against the ', COALESCE(CAST((SELECT min_windows FROM lrn_set) AS STRING), '(no setting)'),
      ' before them; RED when worse by more than ', COALESCE(CAST((SELECT regression_max FROM lrn_set) AS STRING), '(no setting)'),
      ' of the earlier value · the card was scored ',
      COALESCE(FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', (SELECT scored_at FROM lrn_card_meta), 'America/New_York'), 'never'),
      ' New York')
  FROM lrn_reg_line
),
c37 AS (  -- REPORTS: the response model is tested only where an uploaded plan matched a move
  SELECT 'response_model_unverified',
    CAST(COUNTIF(is_applied AND NOT COALESCE(act_is_noop, FALSE) AND grade != 'UNGRADABLE') AS FLOAT64),
    'current ACT-scenario grades that applied (an uploaded plan matched every component) on a plan row with a bid, state or budget component: the grades that test the response model RM1 · INFO (reports) until one exists, then GREEN; never red',
    IF(COUNTIF(is_applied AND NOT COALESCE(act_is_noop, FALSE) AND grade != 'UNGRADABLE') > 0, 'GREEN', 'INFO'),
    CONCAT(CAST(COUNTIF(is_applied AND NOT COALESCE(act_is_noop, FALSE) AND grade != 'UNGRADABLE') AS STRING),
           ' ACT grades applied with a move · ', CAST(COUNTIF(is_applied AND COALESCE(act_is_noop, FALSE)) AS STRING),
           ' applied on rows the plan moved nothing · ',
           CAST(COUNTIF(NOT COALESCE(act_is_noop, FALSE) AND applied_scenario = 'DO_NOTHING') AS STRING),
           ' with a move whose row applied as DO_NOTHING (no uploaded plan matched) · ',
           CAST(COUNTIF(applied_scenario = 'OTHER_ACTION') AS STRING), ' OTHER_ACTION · ',
           CAST(COUNT(*) AS STRING), ' current ACT grades · RM1 is graded only where an uploaded plan matched (piece 3); until then ACT and lift are ungraded (architecture/LEARNING.md §9)')
  FROM lrn_act
),
-- ───────────────────────────────────────────────────────────────────────────────────────────
-- c33: the holdout's integrity (v27.162, piece-1 plan Task 8, R9 = P-23, audit fix #27; header).
-- Holdout restart (2026-10-05; plan docs/superpowers/plans/2026-10-03-holdout-restart.md §2.7, Task 6):
-- it reads THE LIVE TRIAL (hu_trial) and adds the touch alarm (hu_new, hu_attr, hu_k4_*, hu_touch,
-- hu_red) and feed liveness (hu_live). hu_asg / hu_led / hu_pre / hu_cens / hu_pre_ro / hu_obs feed R9's
-- terms (hu_gap, hu_pre_gap), unchanged; HOLDOUT_INTEGRITY_acceptance.sql runs this text verbatim on
-- doctored copies. THE TWO MUST CHANGE TOGETHER.
-- ───────────────────────────────────────────────────────────────────────────────────────────
hu_trial AS (  -- the live trial: the row V_HOLDOUT_READOUT's k reads
  SELECT trial_id FROM `onyga-482313.OI.V_HOLDOUT_TRIAL` WHERE is_live
  QUALIFY ROW_NUMBER() OVER (ORDER BY assigned_on DESC, trial_id DESC) = 1
),
hu_asg AS (  -- the trial's units, both arms; assignment_rule decides which controls kind 4 watches
  SELECT a.unit_id, a.unit_name, a.arm, a.stratum, a.eligible_from, a.trial_end, a.assigned_at,
         a.assignment_rule
  FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT` a JOIN hu_trial USING (trial_id)
  WHERE a.unit_type = 'CAMPAIGN'
),
hu_chg AS (  -- a change that reached Amazon: a change-log row that was applied, or a change observed on Amazon
  SELECT campaign_id, applied_at FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
  UNION ALL
  SELECT campaign_id, applied_at FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` WHERE source = 'OBSERVED'
),
hu_led AS (  -- every change on a HOLDOUT unit inside its trial window
  SELECT h.unit_id, h.unit_name, h.stratum, DATE(l.applied_at, 'America/Los_Angeles') AS change_day
  FROM hu_asg h
  JOIN hu_chg l ON l.campaign_id = h.unit_id
  WHERE h.arm = 'HOLDOUT'
    AND DATE(l.applied_at, 'America/Los_Angeles') BETWEEN h.eligible_from AND h.trial_end
),
hu_pre AS (  -- every change on a HOLDOUT unit from its assignment day to the day before its window start
  SELECT h.unit_id, h.unit_name, h.stratum, DATE(l.applied_at, 'America/Los_Angeles') AS change_day
  FROM hu_asg h
  JOIN hu_chg l ON l.campaign_id = h.unit_id
  WHERE h.arm = 'HOLDOUT'
    AND DATE(l.applied_at, 'America/Los_Angeles') >= DATE(h.assigned_at, 'America/Los_Angeles')
    AND DATE(l.applied_at, 'America/Los_Angeles') < h.eligible_from
),
hu_cens AS (  -- what the readout censors: READ from its CENSORED rows, never re-derived here
  SELECT unit_id, censored_from FROM `onyga-482313.OI.V_HOLDOUT_READOUT` WHERE state = 'CENSORED'
),
hu_pre_ro AS (  -- what the readout publishes as changed before the window: READ from its PRE_WINDOW_CHANGE rows
  SELECT unit_id, pre_window_change_on FROM `onyga-482313.OI.V_HOLDOUT_READOUT` WHERE state = 'PRE_WINDOW_CHANGE'
),
hu_obs AS (  -- the observed-change ledger's size: with no row at all, a console change is invisible
  SELECT COUNT(*) AS n FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` WHERE source = 'OBSERVED'
),
hu_gap AS (  -- trial units, either arm, that the readout does not censor from a change in their stratum on
  SELECT m.unit_id, m.unit_name, m.arm, m.stratum,
         MIN(t.change_day) AS first_change_day, MIN(c.censored_from) AS censored_from
  FROM hu_led t
  JOIN hu_asg m ON m.stratum = t.stratum
  LEFT JOIN hu_cens c ON c.unit_id = m.unit_id
  WHERE c.censored_from IS NULL OR c.censored_from > t.change_day
  GROUP BY 1, 2, 3, 4
),
hu_pre_gap AS (  -- HOLDOUT units changed before their window that the readout does not publish from that day on
  SELECT p.unit_id, p.unit_name, p.stratum,
         MIN(p.change_day) AS first_change_day, MIN(r.pre_window_change_on) AS published_on
  FROM hu_pre p
  LEFT JOIN hu_pre_ro r ON r.unit_id = p.unit_id
  GROUP BY 1, 2, 3
  HAVING MIN(r.pre_window_change_on) IS NULL OR MIN(r.pre_window_change_on) > MIN(p.change_day)
),
-- ── the touch alarm (plan §2.7, review fix 1). A touch on a HOLDOUT unit of the live trial counts from
-- its assignment day (LA) to its trial_end. Kinds 2-4 are seen by the alarm and NOT censored by R9.
hu_hold AS (  -- the live trial's HOLDOUT units and the LA days on which a touch counts
  SELECT unit_id, unit_name, DATE(assigned_at, 'America/Los_Angeles') AS from_day, trial_end
  FROM hu_asg WHERE arm = 'HOLDOUT'
),
hu_new AS (  -- kind 2: a keyword / product target (first DIM_KEYWORD version) or ad group (first DIM_AD_GROUP
  -- version) created on a control; the ledger never counts a first version. Dated like V_AMAZON_OBSERVED_CHANGES:
  -- the LA day of TIMESTAMP(effective_from, 'UTC') (Amazon's last_updated_date; an SB keyword's first sync)
  SELECT h.unit_id, h.unit_name, 'NEW_ENTITY' AS kind, f.change_day, f.what
  FROM hu_hold h
  JOIN (
    SELECT campaign_id, DATE(TIMESTAMP(effective_from, 'UTC'), 'America/Los_Angeles') AS change_day,
           FORMAT('keyword or target %s created (%s %s)', keyword_id, match_type, keyword_text) AS what
    FROM `onyga-482313.OI.DIM_KEYWORD`
    QUALIFY ROW_NUMBER() OVER (PARTITION BY keyword_id ORDER BY effective_from, _fivetran_synced) = 1
    UNION ALL
    SELECT campaign_id, DATE(TIMESTAMP(effective_from, 'UTC'), 'America/Los_Angeles'),
           FORMAT('ad group %s created (%s)', ad_group_id, ad_group_name)
    FROM `onyga-482313.OI.DIM_AD_GROUP`
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ad_group_id ORDER BY effective_from, _fivetran_synced) = 1
  ) f ON f.campaign_id = h.unit_id
  WHERE f.change_day BETWEEN h.from_day AND h.trial_end
),
hu_attr AS (  -- kind 3: a portfolio or bidding-strategy change (DIM_CAMPAIGN version pairs, SP and SB), an SB
  -- bid-optimization change (sb_campaign_history version pairs; DIM_CAMPAIGN carries '' for SB), and a campaign end
  -- date set, moved or cleared (campaign_history version pairs for SP, sb_campaign_history for SB; an end date stops
  -- a control serving, and the ledger records only budget and state), versions ordered as V_AMAZON_OBSERVED_CHANGES
  -- orders them. Not watched, on purpose: start_date (Amazon rewrote it on 16 SP and several SB campaigns in May
  -- 2026, 05-12 -> 05-09, with no human touch) and SB rule_based_budget_applicable_rule_id (it flips monthly by itself)
  SELECT h.unit_id, h.unit_name, 'CAMPAIGN_ATTR' AS kind, v.change_day, v.what
  FROM hu_hold h
  JOIN (
    SELECT campaign_id, DATE(TIMESTAMP(effective_from, 'UTC'), 'America/Los_Angeles') AS change_day,
           TRIM(CONCAT(
             IF(portfolio_id IS DISTINCT FROM prev_pf,
                FORMAT('portfolio %s -> %s ', COALESCE(prev_pf, 'none'), COALESCE(portfolio_id, 'none')), ''),
             IF(bidding_strategy IS DISTINCT FROM prev_bs,
                FORMAT('bidding strategy %s -> %s', COALESCE(prev_bs, 'none'), COALESCE(bidding_strategy, 'none')), ''))) AS what
    FROM (SELECT campaign_id, effective_from, portfolio_id, bidding_strategy,
                 LAG(portfolio_id) OVER w AS prev_pf, LAG(bidding_strategy) OVER w AS prev_bs,
                 LAG(effective_from) OVER w AS prev_from
          FROM `onyga-482313.OI.DIM_CAMPAIGN`
          WINDOW w AS (PARTITION BY campaign_id ORDER BY effective_from, _fivetran_synced))
    WHERE prev_from IS NOT NULL
      AND (portfolio_id IS DISTINCT FROM prev_pf OR bidding_strategy IS DISTINCT FROM prev_bs)
    UNION ALL
    SELECT CAST(id AS STRING), DATE(last_updated_date, 'America/Los_Angeles'),
           FORMAT('end date %s -> %s', IFNULL(CAST(prev_end AS STRING), 'none'), IFNULL(CAST(end_date AS STRING), 'none'))
    FROM (SELECT id, last_updated_date, end_date, LAG(end_date) OVER w AS prev_end,
                 LAG(last_updated_date) OVER w AS prev_at
          FROM `fivetran-hl.amazon_ads.campaign_history`
          WINDOW w AS (PARTITION BY id ORDER BY last_updated_date, _fivetran_synced))
    WHERE prev_at IS NOT NULL AND end_date IS DISTINCT FROM prev_end
    UNION ALL
    SELECT id, DATE(last_update_date, 'America/Los_Angeles'),
           TRIM(CONCAT(
             IF(bid_optimization IS DISTINCT FROM prev_bo OR bid_optimization_strategy IS DISTINCT FROM prev_bos,
                FORMAT('SB bid optimization %t / %s -> %t / %s ', prev_bo, COALESCE(prev_bos, 'none'),
                       bid_optimization, COALESCE(bid_optimization_strategy, 'none')), ''),
             IF(end_date IS DISTINCT FROM prev_end,
                FORMAT('SB end date %s -> %s', IFNULL(CAST(prev_end AS STRING), 'none'),
                       IFNULL(CAST(end_date AS STRING), 'none')), '')))
    FROM (SELECT id, last_update_date, bid_optimization, bid_optimization_strategy, end_date,
                 LAG(bid_optimization) OVER w AS prev_bo, LAG(bid_optimization_strategy) OVER w AS prev_bos,
                 LAG(end_date) OVER w AS prev_end, LAG(last_update_date) OVER w AS prev_at
          FROM `fivetran-hl.amazon_ads.sb_campaign_history`
          WINDOW w AS (PARTITION BY id ORDER BY last_update_date, _fivetran_synced))
    WHERE prev_at IS NOT NULL
      AND (bid_optimization IS DISTINCT FROM prev_bo OR bid_optimization_strategy IS DISTINCT FROM prev_bos
           OR end_date IS DISTINCT FROM prev_end)
  ) v ON v.campaign_id = h.unit_id
  WHERE v.change_day BETWEEN h.from_day AND h.trial_end
),
hu_k4_watch AS (  -- kind 4 watches the founding controls, whether or not they have a baseline row
  SELECT unit_id FROM hu_asg WHERE arm = 'HOLDOUT' AND STARTS_WITH(assignment_rule, 'FOUNDING')),
hu_k4_unwatched AS (  -- every other control (LATE ARRIVAL): named in the detail, never compared
  SELECT unit_id, unit_name, assignment_rule FROM hu_asg
  WHERE arm = 'HOLDOUT' AND unit_id NOT IN (SELECT unit_id FROM hu_k4_watch)),
hu_k4_sp  AS (SELECT *, MAX(_fivetran_synced) OVER () AS mx FROM `fivetran-hl.amazon_ads.campaign_placement_bidding`),
hu_k4_sbp AS (SELECT *, MAX(_fivetran_synced) OVER () AS mx FROM `fivetran-hl.amazon_ads.sb_campaign_bid_adjustments_by_placement`),
hu_k4_sbc AS (SELECT *, MAX(_fivetran_synced) OVER () AS mx FROM `fivetran-hl.amazon_ads.sb_campaign_bid_adjustments_shopper_cohort`),
hu_k4_sbt AS (SELECT *, MAX(_fivetran_synced) OVER () AS mx FROM `fivetran-hl.amazon_ads.sb_product_target`),
hu_k4_present AS (  -- the presence rule: re-stamped by its table's latest sync, and not deleted
  SELECT campaign_id, CONCAT('SP_PLACEMENT|', placement) AS setting, CAST(percentage AS STRING) AS value
  FROM hu_k4_sp WHERE _fivetran_synced >= TIMESTAMP_SUB(mx, INTERVAL 1 HOUR)
  UNION ALL SELECT campaign_id, CONCAT('SB_PLACEMENT|', placement), CAST(percentage AS STRING)
  FROM hu_k4_sbp WHERE _fivetran_synced >= TIMESTAMP_SUB(mx, INTERVAL 1 HOUR)
  UNION ALL SELECT campaign_id, CONCAT('SB_SHOPPER_COHORT|', audience_id, '|', shopper_cohort_type),
         CAST(percentage AS STRING)
  FROM hu_k4_sbc WHERE _fivetran_synced >= TIMESTAMP_SUB(mx, INTERVAL 1 HOUR)
  UNION ALL SELECT campaign_id, CONCAT('SB_TARGET|', id, '|', kv.k), kv.v
  FROM hu_k4_sbt, UNNEST([STRUCT('bid' AS k, CAST(bid AS STRING) AS v), STRUCT('state', state)]) kv
  WHERE _fivetran_synced >= TIMESTAMP_SUB(mx, INTERVAL 1 HOUR) AND NOT COALESCE(_fivetran_deleted, FALSE)),
hu_k4_now AS (  -- today's side of BASELINE_DIFF: the watched controls only
  SELECT * FROM hu_k4_present WHERE campaign_id IN (SELECT unit_id FROM hu_k4_watch)),
hu_k4_base AS (  -- the latest baseline row per setting, live trial; a NULL value means absent
  SELECT b.campaign_id, b.setting, b.value
  FROM `onyga-482313.OI.DE_HOLDOUT_BASELINE` b JOIN hu_trial USING (trial_id)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY b.campaign_id, b.setting ORDER BY b.recorded_at DESC) = 1),
hu_k4_diff AS (  -- BASELINE_DIFF: a changed value, or a setting on one side only
  SELECT campaign_id, setting, b.value AS base_value, n.value AS now_value
  FROM hu_k4_base b FULL OUTER JOIN hu_k4_now n USING (campaign_id, setting)
  WHERE b.value IS DISTINCT FROM n.value),
hu_k4_rebased AS (  -- settings Ori re-baselined (more than one baseline row for the key): AMBER from then on
  SELECT b.campaign_id, b.setting, COUNT(*) AS n_rows
  FROM `onyga-482313.OI.DE_HOLDOUT_BASELINE` b JOIN hu_trial USING (trial_id)
  GROUP BY 1, 2 HAVING COUNT(*) > 1),
hu_touch AS (  -- every touch: kinds 1-3 dated, kind 4 undated (change_day NULL: the source keeps no history)
  SELECT unit_id, unit_name, 'LEDGER' AS kind, change_day,
         'a change-log row applied, or a change observed on Amazon' AS what FROM hu_led
  UNION ALL SELECT unit_id, unit_name, 'LEDGER', change_day,
         'a change-log row applied, or a change observed on Amazon, before the window start' FROM hu_pre
  UNION ALL SELECT unit_id, unit_name, kind, change_day, what FROM hu_new
  UNION ALL SELECT unit_id, unit_name, kind, change_day, what FROM hu_attr
  UNION ALL SELECT d.campaign_id, COALESCE(h.unit_name, '?'), 'BASELINE_DIFF', CAST(NULL AS DATE),
         FORMAT('%s %s -> %s', d.setting, COALESCE(d.base_value, 'absent'), COALESCE(d.now_value, 'absent'))
  FROM hu_k4_diff d LEFT JOIN hu_asg h ON h.unit_id = d.campaign_id
),
hu_touch_line AS (  -- one clause per (unit, kind, day); RED = a dated touch 7 or fewer LA days old, or an undated one
  SELECT unit_id, unit_name, kind, change_day, COUNT(*) AS n,
         STRING_AGG(DISTINCT what, '; ' ORDER BY what LIMIT 4) AS what,
         (change_day IS NULL
          OR change_day >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)) AS is_red
  FROM hu_touch GROUP BY 1, 2, 3, 4
),
hu_touch_sum AS (  -- the touches in one row (each input is read once: the planner inlines every CTE reference)
  SELECT COUNTIF(is_red) AS n_red, COUNT(DISTINCT IF(is_red, unit_id, NULL)) AS n_red_units,
         COUNTIF(NOT is_red) AS n_old,
         STRING_AGG(IF(is_red, FORMAT('%s (%s) %s %s: %s%s%s', unit_name, unit_id, kind,
                                      IF(change_day IS NULL, 'date unknown: the source keeps no history',
                                         FORMAT('on %t', change_day)),
                                      what, IF(n > 1, FORMAT(' (%d rows)', n), ''),
                                      IF(kind = 'LEDGER', '', ' — seen by the alarm, not censored by R9 — Ori to rule')),
                        NULL),
                    '; ' ORDER BY is_red DESC, IFNULL(change_day, DATE '9999-12-31') DESC, unit_id, kind) AS red_txt,
         STRING_AGG(IF(NOT is_red, FORMAT('%s (%s) %s on %t: %s%s%s', unit_name, unit_id, kind, change_day, what,
                                          IF(n > 1, FORMAT(' (%d rows)', n), ''),
                                          IF(kind = 'LEDGER', '', ' — seen by the alarm, not censored by R9 — Ori to rule')),
                       NULL),
                    '; ' ORDER BY is_red, change_day DESC, unit_id, kind LIMIT 12) AS old_txt
  FROM hu_touch_line
),
hu_k4_sum AS (  -- re-baselined settings and unwatched controls, one row
  SELECT rb.n_rebased, rb.rebased_txt, uw.unwatched_txt
  FROM (SELECT COUNT(*) AS n_rebased,
               STRING_AGG(FORMAT('%s %s (%d rows)', campaign_id, setting, n_rows), ', ' ORDER BY campaign_id, setting) AS rebased_txt
        FROM hu_k4_rebased) rb,
       (SELECT STRING_AGG(FORMAT('%s (%s): %s', unit_name, unit_id, SPLIT(assignment_rule, ':')[SAFE_OFFSET(0)]), ', ' ORDER BY unit_id) AS unwatched_txt
        FROM hu_k4_unwatched) uw
),
-- ── feed liveness (plan §2.7, review fix 2): minutes since each path's last stamp, each read on its own;
-- NULL = missing. 30-day measurements behind the 36-hour bar are in the header.
hu_live AS (
  SELECT COUNTIF(age_min IS NULL OR age_min > 36 * 60) AS n_stale,
         STRING_AGG(IF(age_min IS NULL OR age_min > 36 * 60,
                       IF(age_min IS NULL, CONCAT(src, ' missing'), FORMAT('%s %.1f h', src, age_min / 60)), NULL),
                    ', ' ORDER BY ord) AS stale_txt,
         STRING_AGG(IF(age_min IS NULL, CONCAT(src, ' missing'), FORMAT('%s %.1f', src, age_min / 60)), ', ' ORDER BY ord) AS ages_txt
  FROM (
    SELECT n.src, n.ord, TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), s.ts, MINUTE) AS age_min
    FROM UNNEST(ARRAY<STRUCT<src STRING, ord INT64>>[
      ('SP_RECORD_OBSERVED_CHANGES', 0),
      ('SP_LOAD_DIM_KEYWORD', 1),
      ('SP_LOAD_DIM_CAMPAIGN', 2),
      ('SP_LOAD_DIM_AD_GROUP', 3),
      ('keyword_history', 4),
      ('sb_keyword', 5),
      ('targeting_clause_history', 6),
      ('campaign_history', 7),
      ('sb_campaign_history', 8),
      ('ad_group_history', 9),
      ('sb_ad_group_history', 10),
      ('campaign_placement_bidding', 11),
      ('sb_campaign_bid_adjustments_by_placement', 12),
      ('sb_campaign_bid_adjustments_shopper_cohort', 13),
      ('sb_product_target', 14)]) n
    LEFT JOIN (
      SELECT procedure_name AS src, MAX(started_at) AS ts FROM `onyga-482313.OI.LOG_PIPELINE_RUNS`
      WHERE status = 'OK' AND procedure_name IN ('SP_RECORD_OBSERVED_CHANGES', 'SP_LOAD_DIM_KEYWORD', 'SP_LOAD_DIM_CAMPAIGN', 'SP_LOAD_DIM_AD_GROUP')
      GROUP BY 1
      UNION ALL SELECT 'keyword_history', MAX(_fivetran_synced) FROM `fivetran-hl.amazon_ads.keyword_history`
      UNION ALL SELECT 'sb_keyword', MAX(_fivetran_synced) FROM `fivetran-hl.amazon_ads.sb_keyword`
      UNION ALL SELECT 'targeting_clause_history', MAX(_fivetran_synced) FROM `fivetran-hl.amazon_ads.targeting_clause_history`
      UNION ALL SELECT 'campaign_history', MAX(_fivetran_synced) FROM `fivetran-hl.amazon_ads.campaign_history`
      UNION ALL SELECT 'sb_campaign_history', MAX(_fivetran_synced) FROM `fivetran-hl.amazon_ads.sb_campaign_history`
      UNION ALL SELECT 'ad_group_history', MAX(_fivetran_synced) FROM `fivetran-hl.amazon_ads.ad_group_history`
      UNION ALL SELECT 'sb_ad_group_history', MAX(_fivetran_synced) FROM `fivetran-hl.amazon_ads.sb_ad_group_history`
      UNION ALL SELECT 'campaign_placement_bidding', MAX(_fivetran_synced) FROM `fivetran-hl.amazon_ads.campaign_placement_bidding`
      UNION ALL SELECT 'sb_campaign_bid_adjustments_by_placement', MAX(_fivetran_synced) FROM `fivetran-hl.amazon_ads.sb_campaign_bid_adjustments_by_placement`
      UNION ALL SELECT 'sb_campaign_bid_adjustments_shopper_cohort', MAX(_fivetran_synced) FROM `fivetran-hl.amazon_ads.sb_campaign_bid_adjustments_shopper_cohort`
      UNION ALL SELECT 'sb_product_target', MAX(_fivetran_synced) FROM `fivetran-hl.amazon_ads.sb_product_target`
    ) s USING (src))
),
-- ── R9's terms in one row
hu_r9 AS (
  SELECT u.n_hold, u.n_units, o.n AS n_obs, g.n_gap, g.gap_txt, pg.n_pre_gap, pg.pre_gap_txt,
         STRUCT(pr.n AS n, pr.txt AS txt) AS pre, STRUCT(ld.n AS n, ld.txt AS txt) AS led, cs.n_cens
  FROM (SELECT COUNTIF(arm = 'HOLDOUT') AS n_hold, COUNT(*) AS n_units FROM hu_asg) u,
       hu_obs o,
       (SELECT COUNT(*) AS n_gap,
               STRING_AGG(FORMAT('%s (%s, %s, %s): its stratum changed on %t, the readout censors it %s',
                                 unit_name, unit_id, arm, stratum, first_change_day,
                                 IF(censored_from IS NULL, 'never', FORMAT('from %t', censored_from))),
                          '; ' ORDER BY first_change_day, unit_id) AS gap_txt
        FROM hu_gap) g,
       (SELECT COUNT(*) AS n_pre_gap,
               STRING_AGG(FORMAT('%s (%s, %s): changed on %t before its window start, the readout publishes it %s',
                                 unit_name, unit_id, stratum, first_change_day,
                                 IF(published_on IS NULL, 'never', FORMAT('from %t', published_on))),
                          '; ' ORDER BY first_change_day, unit_id) AS pre_gap_txt
        FROM hu_pre_gap) pg,
       (SELECT COUNT(*) AS n, STRING_AGG(FORMAT('%s %t', unit_name, d), ', ' ORDER BY d, unit_id) AS txt
        FROM (SELECT unit_id, unit_name, MIN(change_day) AS d FROM hu_pre GROUP BY 1, 2)) pr,
       (SELECT COUNT(*) AS n, STRING_AGG(FORMAT('%s %t', unit_name, d), ', ' ORDER BY d, unit_id) AS txt
        FROM (SELECT unit_id, unit_name, MIN(change_day) AS d FROM hu_led GROUP BY 1, 2)) ld,
       (SELECT COUNT(DISTINCT unit_id) AS n_cens FROM hu_cens) cs
),
c33 AS (  -- R9 / fix #27 + the holdout restart's touch alarm and feed liveness (plan 2026-10-03 §2.7, Task 6)
  SELECT 'holdout_unit_changed',
    CAST(r.n_gap + r.n_pre_gap + t.n_red_units AS FLOAT64),
    'live trial (V_HOLDOUT_TRIAL): trial campaigns sharing a stratum with a HOLDOUT campaign changed inside its window that V_HOLDOUT_READOUT does not censor from that day on (R9, P-23, audit fix #27), + HOLDOUT campaigns changed between their assignment and window start that the readout does not publish (PRE_WINDOW_CHANGE), + HOLDOUT campaigns with a RED touch · red > 0; red on a TOUCH from the assignment day 7 or fewer LA days old (a ledger row; a keyword, target or ad group created; a portfolio, bidding-strategy or SB bid-optimization change) or a standing BASELINE_DIFF (a placement / shopper-cohort adjustment or SB product target that differs from DE_HOLDOUT_BASELINE); red when no HOLDOUT unit or no observed-change row is read, or any feed stamp (4 procedures, 11 Fivetran tables) is > 36 h old or missing; amber on any older touch or a re-baselined setting',
    CASE WHEN r.n_hold = 0 THEN 'RED'
         WHEN r.n_obs = 0 THEN 'RED'
         WHEN r.n_gap + r.n_pre_gap > 0 THEN 'RED'
         WHEN t.n_red > 0 THEN 'RED'
         WHEN l.n_stale > 0 THEN 'RED'
         WHEN t.n_old + k.n_rebased > 0 THEN 'AMBER'
         ELSE 'GREEN' END,
    CONCAT(
      CASE WHEN r.n_hold = 0 THEN 'no HOLDOUT unit read for the live trial (V_HOLDOUT_TRIAL, DE_HOLDOUT_ASSIGNMENT) · '
           WHEN r.n_obs = 0 THEN 'the observed-change ledger is empty, so a console change on a HOLDOUT campaign would be invisible · '
           ELSE '' END,
      IF(t.n_red > 0, CONCAT('TOUCHED: ', t.red_txt, ' · '), ''),
      IF(l.n_stale > 0, CONCAT('FEED STALE (> 36 h or missing): ', l.stale_txt, ' · '), ''),
      IF(t.n_old > 0, CONCAT('touched more than 7 LA days ago (AMBER): ', t.old_txt,
                             IF(t.n_old > 12, FORMAT('; and %d more', t.n_old - 12), ''), ' · '), ''),
      IF(k.n_rebased > 0, CONCAT('re-baselined by Ori (AMBER): ', k.rebased_txt, ' · '), ''),
      IF(r.n_gap > 0, CONCAT('NOT CENSORED: ', r.gap_txt, ' · '), ''),
      IF(r.n_pre_gap > 0, CONCAT('NOT PUBLISHED: ', r.pre_gap_txt, ' · '), ''),
      IF(r.pre.n > 0,
         CONCAT('published, not censored (pre-declared for T2, plan 2026-10-03 §2.3): ', CAST(r.pre.n AS STRING), ' of ',
                CAST(r.n_hold AS STRING),
                ' HOLDOUT campaign(s) changed between their assignment and their window start, which R9 does not censor (first day): ',
                r.pre.txt, ' · '),
         ''),
      CAST(r.led.n AS STRING), ' of ', CAST(r.n_hold AS STRING),
      ' HOLDOUT campaign(s) changed inside the trial window',
      IF(r.led.n > 0, CONCAT(' (first day): ', r.led.txt), ''),
      ' · the readout censors ', CAST(r.n_cens AS STRING), ' of ', CAST(r.n_units AS STRING),
      ' trial campaigns, both arms, each from the first change in its stratum (R9, HOLDOUT.md §6) · ',
      IF(k.unwatched_txt IS NOT NULL,
         CONCAT('unwatched on kind-4 settings (no baseline is taken for a late arrival): ', k.unwatched_txt, ' · '), ''),
      'feed ages (h): ', COALESCE(l.ages_txt, 'none read'),
      ' · not seen by any source: negatives added or removed by hand (the five negative mirrors last written 2025-12-29 .. 2026-01-03), ads and creatives (mirrors last written 2025-12-28 .. 2026-01-03), a change undone before the next sync or two changes between two DIM loads (read as one), a kind-4 setting put back to its baseline value before the board reads it')
  FROM hu_r9 r, hu_touch_sum t, hu_k4_sum k, hu_live l
)
SELECT * FROM c1 UNION ALL SELECT * FROM c2 UNION ALL SELECT * FROM c3
UNION ALL SELECT * FROM c4 UNION ALL SELECT * FROM c5 UNION ALL SELECT * FROM c6
UNION ALL SELECT * FROM c7 UNION ALL SELECT * FROM c8 UNION ALL SELECT * FROM c9
UNION ALL SELECT * FROM c10 UNION ALL SELECT * FROM c11 UNION ALL SELECT * FROM c12
UNION ALL SELECT * FROM c13 UNION ALL SELECT * FROM c14 UNION ALL SELECT * FROM c15
UNION ALL SELECT * FROM c16 UNION ALL SELECT * FROM c17 UNION ALL SELECT * FROM c18
UNION ALL SELECT * FROM c19 UNION ALL SELECT * FROM c20 UNION ALL SELECT * FROM c21
UNION ALL SELECT * FROM c22 UNION ALL SELECT * FROM c23 UNION ALL SELECT * FROM c24
UNION ALL SELECT * FROM c25 UNION ALL SELECT * FROM c26 UNION ALL SELECT * FROM c27
UNION ALL SELECT * FROM c28 UNION ALL SELECT * FROM c29 UNION ALL SELECT * FROM c30
UNION ALL SELECT * FROM c31 UNION ALL SELECT * FROM c32
UNION ALL SELECT * FROM c33 UNION ALL SELECT * FROM c34
UNION ALL SELECT * FROM c35 UNION ALL SELECT * FROM c36 UNION ALL SELECT * FROM c37;
