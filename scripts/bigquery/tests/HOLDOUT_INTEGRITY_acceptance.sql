-- =============================================================================================
-- HOLDOUT_INTEGRITY acceptance — v27.162 (2026-10-03), piece-1 plan Task 8: ruling R9 (spec P-23)
-- and audit fix #27; extended by the v27.162 follow-up (changes between the assignment and the window
-- start); and by the holdout restart (plan docs/superpowers/plans/2026-10-03-holdout-restart.md Task 7,
-- deploy 2026-10-05): the live trial, the touch alarm (H4) and feed liveness (H5). EVERY ROW MUST READ PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --nosync \
--     "$(grep -v '^[[:space:]]*--' FILE)"          then poll with bq wait JOB 60, one call per poll
--   It runs about 18 minutes (rehearsal: 1,054 s, 65,385 slot-s). Stripped it is about 71 KB.
--   The result is the last statement: bq ls -j --parent_job_id=JOB, then bq head -j the last child.
-- Objects: scripts/bigquery/views/V_HOLDOUT_READOUT.sql (the CENSORED and PRE_WINDOW_CHANGE rows),
--          scripts/bigquery/views/V_ENGINE_HEALTH.sql (c33 holdout_unit_changed), views/V_HOLDOUT_TRIAL.sql.
-- SOP: architecture/HOLDOUT.md §6 "Contamination"; architecture/ENGINE_HEALTH.md.
--
-- WHEN IT CAN PASS. Only after deploy step 5 of plan Task 8 (2026-10-05): the file reads V_HOLDOUT_TRIAL
-- (step 1), trial 2's rows (step 2), the readout and the board as Task 6 left them (step 5; the board
-- needs DE_HOLDOUT_BASELINE). Before the deploy it stops at its first statement: V_HOLDOUT_TRIAL is not
-- found. It reads no snapshot table, so it does not wait for the ~16:00 UTC pass. H5_LIVE reads the live
-- board's feed ages: it FAILS while any of the 15 stamps is more than 36 h old or missing, which is the
-- alarm working, not the suite.
--
-- THE RULE UNDER TEST (R9, Ori 2026-10-02, option (a); HOLDOUT.md §6 #2). A HOLDOUT campaign that
-- changed inside its trial window [eligible_from, trial_end] — a change-log row that was applied
-- (V_PPC_CHANGE_LOG_APPLIED) or a change the observed-change ledger saw on Amazon (FACT_PPC_CHANGE_LOG
-- source OBSERVED) — is contaminated from the Los Angeles day of its first such change; it AND its
-- stratum-mates in both arms are censored from the earliest such day in the stratum.
-- CHANGES BEFORE THE WINDOW (the follow-up). A change from the assignment day (Los Angeles) to the day
-- before eligible_from is NOT censored (pre-declared for trial 2, plan §2.3); the readout publishes one
-- PRE_WINDOW_CHANGE row per such HOLDOUT unit, dated by its first such change.
-- THE TRIAL. Every input is the LIVE trial's: hu_trial and asg0 below are c33's hu_trial and hu_asg
-- (V_ENGINE_HEALTH.sql, holdout restart Task 6) verbatim, read once into temp tables; H3 reads the live
-- trial's first_readout from V_HOLDOUT_TRIAL (trial 2: 2027-02-09).
--   H1  the readout's CENSORED rows are exactly the censoring: every unit the rule censors carries one
--       CENSORED row with that censored_from (and its own contaminated_on when it is a contaminated
--       HOLDOUT unit), and no other unit carries one; and its PRE_WINDOW_CHANGE rows are exactly the
--       HOLDOUT units changed before their window, each with pre_window_change_on = its first such
--       day. The expectation is re-derived HERE from the ledger (statements led and pre). Emptiness
--       terms: no HOLDOUT unit, no observed-change row at all, or no estimate row (NOT_YET / READY) in
--       the readout reads as a violation, so an empty input can never pass.
--   H2  R9 on the board. c33's own text (hu_gap .. c33, pasted below VERBATIM from V_ENGINE_HEALTH.sql)
--       runs on each doctored copy of R9's inputs. Since the restart, measured = R9's gaps + the
--       controls with a RED touch, and the status also turns RED or AMBER on a touch or a stale feed
--       (H4, H5), which a copy of R9's inputs neither sets nor controls. So H2 reads R9's PART of the
--       row from the row's own clauses: one "its stratum changed on <day>, the readout censors it" per
--       hu_gap row and one "before its window start, the readout publishes it" per hu_pre_gap row.
--       H2a: the deployed row exists and its R9 part is 0. H2b: the pasted text on the live inputs
--       equals the deployed row on measured, status, threshold and detail, with every decimal number
--       masked (the feed ages move between the two reads).
--   H3  the readout's gate holds: before the live trial's first_readout exactly one estimate row
--       (NOT_YET), no READY row, and no number on any row — the CENSORED and PRE_WINDOW_CHANGE rows carry
--       dates and a reason only; + 1 when no live trial (no first_readout) is read.
--   H4  the touch alarm, and H5 feed liveness, on the DEPLOYED c33 text: hu_trial .. c33 is read from
--       INFORMATION_SCHEMA.VIEWS (V_ENGINE_HEALTH) and run once per case (EXECUTE IMMEDIATE) with every
--       source replaced by a temp copy: V_HOLDOUT_TRIAL, DE_HOLDOUT_ASSIGNMENT, V_PPC_CHANGE_LOG_APPLIED,
--       FACT_PPC_CHANGE_LOG, V_HOLDOUT_READOUT, DIM_KEYWORD, DIM_AD_GROUP, DIM_CAMPAIGN,
--       sb_campaign_history, the four kind-4 tables, DE_HOLDOUT_BASELINE, LOG_PIPELINE_RUNS, and the
--       eleven MAX(_fivetran_synced) feed-age reads (those are replaced first: five of the tables are
--       also read whole). The text that runs names no campaign id; only the doctoring statements pick
--       one, derived from the copies. H45_TEXT checks the text was found and that no live source is
--       left in any case's text.
--       THE BASE COPY (H4_BASE) is clean by construction, whatever the live state: the ledger, DIM and
--       sb_campaign_history copies hold only what is older than the trial's assignment day (LA), the
--       readout copy is empty, the baseline copy equals today's present settings of the watched set
--       (the presence rule, as the founding insert writes it), and every feed stamp is 1 hour old.
--       Each case changes one input of the base copy:
--         H4_BASE                  nothing                                          GREEN, 0
--         H4_LEDGER_TODAY          an observed change on the first HOLDOUT unit now; the readout
--                                  copy censors its stratum from today (inside the window) or
--                                  publishes it (before the window start)           RED, 1
--         H4_LEDGER_7D / _8D       the same change, c33's CURRENT_DATE('America/Los_Angeles') (its
--                                  only one: the aging) replaced by the fixed day 7 / 8 days after it
--                                                                                   RED, 1 / AMBER, 0
--         H4_NEW_KEYWORD           a keyword created on a founding control now      RED, 1
--         H4_NEW_KEYWORD_BEFORE    the same, created the day before the assignment  GREEN, 0
--         H4_NEW_AD_GROUP          an ad group created on a founding control now    RED, 1
--         H4_PORTFOLIO             a DIM_CAMPAIGN version now with portfolio_id changed (SP control) RED, 1
--         H4_BIDDING_STRATEGY      the same with bidding_strategy changed           RED, 1
--         H4_SB_BID_OPT            an sb_campaign_history version now with bid_optimization flipped
--                                  (SB control)                                     RED, 1
--         H4_END_DATE              a campaign_history version now on a founding SP control, end date set 16 days out
--                                  (added 2026-10-04, review of holdout-t2: an end date stops a control serving)  RED, 1
--         H4_SB_END_DATE           the same on the SB control, in sb_campaign_history                              RED, 1
--         H4_BASELINE_ALTERED      one baseline value altered                       RED, 1 ("date unknown")
--         H4_BASELINE_REBASED      the same plus a later baseline row carrying a ruling       AMBER, 0
--         H4_WATCHED_NO_BASELINE   a present PLACEMENT_TOP 30 row put on a founding SP control with
--                                  no baseline row (the ME-COMPETE case of plan §2.7) RED, 1
--         H4_LATE_ARRIVAL          a LATE ARRIVAL HOLDOUT row for an SB campaign outside the trial
--                                  with present placement rows: never compared, named unwatched GREEN, 0
--         H4_REMOVAL               one present SP row of a founding control not re-stamped (stamp
--                                  12 h back): 100 -> absent                        RED, 1
--         H4_REMOVAL_REBASED       the same plus a later baseline row with value NULL and a ruling AMBER, 0
--         H4_STALE_DROPPED         the SP rows not re-stamped by the latest sync dropped (a re-sync)
--                                                                                   GREEN, 0
--         H4_SB_TARGET_DELETED     a founding control's present SB product target flagged
--                                  _fivetran_deleted (bid and state)                RED, 1
--         H4_NO_WATCHED_SET        every FOUNDING assignment_rule re-prefixed LATE ARRIVAL: every
--                                  baseline row on one side only                    RED, controls with
--                                  baseline rows; every control named unwatched
--         H5_PROC_<4 procedures>   that procedure's last OK run 37 h old            RED, 0, FEED STALE names
--                                                                                   exactly that procedure
--         H5_PROC_MISSING          SP_RECORD_OBSERVED_CHANGES with no OK run        RED, "... missing"
--         H5_TABLE_<11 tables>     that table's MAX(_fivetran_synced) read 37 h old RED, 0, names exactly it
--         H5_TABLE_MISSING         sb_product_target's feed-age read empty          RED, "... missing"
--       Every RED of kinds 2-4 must carry "not censored by R9". A case whose pick does not exist in the
--       copies (for example no stale SP row) says "(vacuous ...)" and passes.
--       H5_LIVE: the deployed board row carries no FEED STALE clause (plan Task 7: "the live sources
--       read not-RED").
-- THE R9 COPIES (H1-H3). Each copy is a full set of the six inputs the pasted text reads as temp tables
-- (hu_asg, hu_led, hu_pre, hu_cens, hu_pre_ro, hu_obs; hu_trial is read once). Picks are deterministic
-- (first by date, then unit_id).
--   LIVE              everything as read.                            H1 0      H2 R9 part 0
--   NC_DROP_ONE       the first contaminated HOLDOUT unit's CENSORED row removed.  H1 >= 1  H2 RED, R9 1
--   NC_LATE           that row's censored_from one day later.        H1 >= 1   H2 RED, R9 1
--   NC_DROP_MATE      the first censored TREATED unit's row removed. H1 >= 1   H2 RED, R9 1
--   HC_EXTRA          a CENSORED row added for an uncensored unit (over-censoring): H1 is two-sided
--                     and fires; the board counts only what is NOT censored. H1 >= 1  H2 = LIVE, R9 0
--   NC_NEW_CHANGE     an observed change added on the HOLDOUT unit that is uncensored (else the latest
--                     censored), dated today, or the window start while today is before it (else the day
--                     before its censoring); it must fall inside the window.
--                                                                    H1 >= 1   H2 RED, R9 >= 1
--   NC_NO_HOLDOUT     the HOLDOUT rows of the assignment removed.     H1 >= 1   H2 RED (emptiness)
--   NC_NO_OBSERVED    the observed ledger empty.                     H1 >= 1   H2 RED (emptiness)
--   NC_EMPTY_RO       the readout returns no row.                    H1 >= 1   H2 RED, R9 = every censored
--                     unit + every unit changed before the window (vacuous when there is none)
--   NC_NUMBER         (H3 only) a number on a CENSORED row, or on the NOT_YET row when no row is
--                     CENSORED (trial 2's first days).                H3 >= 1
--   NC_PRE_DROP       the first PRE_WINDOW_CHANGE row removed.       H1 >= 1   H2 RED, R9 1
--   NC_PRE_LATE       that row's pre_window_change_on one day later. H1 >= 1   H2 RED, R9 1
--   HC_PRE_CLEAN      no change before the window.                   H1 0      H2 R9 0, nothing published
--   NC_PRE_NEW        a change before the window added on the first HOLDOUT unit with none, dated
--                     the day before its eligible_from.              H1 >= 1   H2 RED, R9 1
--   NC_NUMBER_PRE     (H3 only) a PRE_WINDOW_CHANGE row carrying holdout_n 1.  H3 >= 1
-- A copy whose pick does not exist says '(vacuous ...)' in its name and passes: a clean trial is a
-- legitimate state. On trial 2's first days (no change yet) LIVE, NC_NEW_CHANGE, NC_NO_HOLDOUT,
-- NC_NO_OBSERVED, NC_PRE_NEW and NC_NUMBER are exercised; the copies that drop or move an existing
-- CENSORED / PRE_WINDOW_CHANGE row are vacuous until one exists. H4_LEDGER_* exercises the ledger path
-- of the deployed text on every run.
-- TEXT IDENTITY: the hu_gap .. c33 block below must equal V_ENGINE_HEALTH.sql's byte for byte, and the
-- deployed definition must carry it (whole-line comments removed, as the deploy removes them, then
-- whitespace-normalised). Check both with:
--   python3 -c "import re,json,subprocess;b=lambda t:t[t.index('\nhu_gap AS ('):t.index('\n)\n',t.index('\nc33 AS ('))+2];s=lambda t:'\n'.join(l for l in t.split('\n') if not re.match(r'\s*--',l));v=open('scripts/bigquery/views/V_ENGINE_HEALTH.sql').read();a=open('scripts/bigquery/tests/HOLDOUT_INTEGRITY_acceptance.sql').read();d=json.loads(subprocess.check_output(['bq','query','--project_id=onyga-482313','--use_legacy_sql=false','--format=json',\"SELECT view_definition FROM \`onyga-482313.OI.INFORMATION_SCHEMA.VIEWS\` WHERE table_name='V_ENGINE_HEALTH'\"]))[0]['view_definition'];n=lambda t:re.sub(r'\s+',' ',t);print('file==acceptance',b(v)==b(a),'deployed carries it',n(s(b(v))) in n(d))"
--
-- REHEARSAL 2026-10-04 on TMP_HT2_ copies (all dropped afterwards), about 06:53-07:41 UTC (LA date
-- 2026-10-03, then 2026-10-04 after 07:00 UTC). This file with comment lines stripped and five names
-- pointed at copies: V_HOLDOUT_TRIAL, DE_HOLDOUT_ASSIGNMENT, V_HOLDOUT_READOUT, DE_HOLDOUT_BASELINE and
-- V_ENGINE_HEALTH (backticked, and the INFORMATION_SCHEMA filter 'V_ENGINE_HEALTH'). The copies: the
-- registry from its DDL and the rows file (3 rows); DE_HOLDOUT_ASSIGNMENT by COPY (69 trial-1 rows) +
-- the founding file (59 trial-2 rows, 12 HOLDOUT, assigned 2026-10-04 06:42 UTC = LA 2026-10-03); a
-- baseline of 15 rows on 8 controls by the presence rule; V_HOLDOUT_TRIAL, V_HOLDOUT_READOUT and
-- V_ENGINE_HEALTH from this branch over the copies, not pinned (both trials live on LA 10-03 / 10-04;
-- hu_trial's tie-break picks trial 2). Every other source live and read-only.
--   run 3 (job g5_hi_tmp3_1791098427, the text of this file): 69 rows, every one PASS. 235 statements,
--   1,054 s, 65,385.4 slot-s, 360.2 MB. The H2 loop: 13 runs of the pasted text, 84.7-147.8 slot-s
--   each; H4/H5: 36 runs of the deployed text, 1,300.9-1,924.9 slot-s each (about 200 query stages
--   each), 58,643.0 in all. Readings:
--     H1 LIVE 0 (0 units censored, 0 changed before the window: trial 2 is clean) · NC_NEW_CHANGE 11
--        (the change dated 2026-10-06, the window start, on ME-SP/EXACT (tween-girl-journal-diary,
--        Purple) 130115986205897; 11 units of SP|CAP|LNC) · NC_NO_HOLDOUT 1 · NC_NO_OBSERVED 1 ·
--        NC_EMPTY_RO 1 (no estimate row) · NC_PRE_NEW 1 (2026-10-05 on 130115986205897) · HC_EXTRA 1 ·
--        HC_PRE_CLEAN 0 · NC_DROP_ONE, NC_LATE, NC_DROP_MATE, NC_PRE_DROP, NC_PRE_LATE vacuous.
--     H2 (status, measured, R9 part): LIVE GREEN 0 0 · HC_EXTRA GREEN 0 0 · NC_NEW_CHANGE RED 11 10
--        (10 NOT CENSORED clauses + 1 RED touch) · NC_PRE_NEW RED 2 1 · NC_NO_HOLDOUT RED 8 0 (every
--        baseline row on one side only, as H4_NO_WATCHED_SET) · NC_NO_OBSERVED RED 0 0 · the vacuous
--        copies GREEN 0 0. H2a the copied board's row: GREEN 0, R9 part 0. H2b equal.
--     H3 LIVE 0 (first_readout 2027-02-09; 0 CENSORED, 0 PRE_WINDOW_CHANGE, 1 estimate row) ·
--        NC_NUMBER 1 (on the NOT_YET row) · NC_NUMBER_PRE vacuous.
--     H45_TEXT: 20,624 characters found, 36 of 36 cases run, 0 live references.
--     H4 (status, measured), picks from the copies: the first HOLDOUT unit and the first founding SP
--        control 130115986205897; the SB control 27660342907703 (target 35049499251022); the founding
--        SP control with no baseline row 271009556929636; the late arrival 111024628782640
--        STORE-SPOTLIGHT (tween-girl-gift); 14 stale SP rows:
--        BASE GREEN 0 · LEDGER_TODAY RED 1 (2026-10-04, before the window: published, the readout copy
--        publishing it) · LEDGER_7D RED 1 · LEDGER_8D AMBER 0 · NEW_KEYWORD RED 1 · NEW_KEYWORD_BEFORE
--        GREEN 0 · NEW_AD_GROUP RED 1 · PORTFOLIO RED 1 · BIDDING_STRATEGY RED 1 (LEGACY_FOR_SALES ->
--        AUTO_FOR_SALES) · SB_BID_OPT RED 1 (true -> false) · BASELINE_ALTERED RED 1 · BASELINE_REBASED
--        AMBER 0 · WATCHED_NO_BASELINE RED 1 (absent -> 30) · LATE_ARRIVAL GREEN 0 (named unwatched) ·
--        REMOVAL RED 1 (100 -> absent) · REMOVAL_REBASED AMBER 0 · STALE_DROPPED GREEN 0 ·
--        SB_TARGET_DELETED RED 1 (bid and state, 2 rows) · NO_WATCHED_SET RED 8 (12 named unwatched).
--     H5: each of the 4 procedures 37.1 h: RED 0, naming only it; SP_RECORD_OBSERVED_CHANGES missing:
--        RED 0; each of the 11 tables 37.1-37.2 h: RED 0, naming only it; sb_product_target empty: RED 0
--        "missing". H5_LIVE: no FEED STALE clause.
--   runs 1 and 2 (jobs g5_hi_tmp1_1791096225, g5_hi_tmp2_1791097231): run 1 stopped at the result
--   ("Name threshold not found": twin_r9 lacked the column; added), after every case had read as
--   expected; run 2: 69 rows PASS, 66,245.6 slot-s. Run 3 differs from run 2 in two things: every
--   injected change is stamped by one clock and the aging cases replace CURRENT_DATE with a fixed day
--   (a run that crosses LA midnight, as run 3 did, stays consistent), and NC_NEW_CHANGE is dated the
--   window start while today is before it (it was vacuous until the window opened).
--   Text identity: file==acceptance True; the copied board carries the block (whole-line comments
--   removed, its five names mapped) True. The one-liner of 2026-10-03, which did not remove comment
--   lines, reads False on this block: c33's text now holds whole-line comments.
--   Before the deploy, this file on the live names stops at its first statement: "Not found: Table
--   onyga-482313:OI.V_HOLDOUT_TRIAL" (2026-10-04 ~07:40 UTC).
-- BASELINE 2026-10-04, the suite as it stood before this edit (commit 1dbdd58's file, trial 1 by its
-- literal), unchanged, on the live inputs: job g5_hi_baseline_1791095268, 109 statements, 240.0 s,
-- 282.2 slot-s, 14.8 MB, 31 rows, every one PASS, the readings of 2026-10-03's run below: H1 LIVE 0
-- (61 units censored, 7 HOLDOUT units changed before the window) · NC_DROP_ONE 2 · NC_LATE 1 ·
-- NC_DROP_MATE 1 · HC_EXTRA 1 · NC_NEW_CHANGE 7 · NC_NO_HOLDOUT 69 · NC_NO_OBSERVED 72 · NC_EMPTY_RO 77 ·
-- NC_PRE_DROP 1 · NC_PRE_LATE 1 · NC_PRE_NEW 1 · HC_PRE_CLEAN 0; H2 LIVE AMBER 0 · NC_DROP_ONE /
-- NC_LATE / NC_DROP_MATE / NC_PRE_DROP / NC_PRE_LATE / NC_PRE_NEW RED 1 · NC_NEW_CHANGE RED 6 ·
-- NC_EMPTY_RO RED 68 · NC_NO_HOLDOUT / NC_NO_OBSERVED RED 0 · HC_EXTRA AMBER 0 · HC_PRE_CLEAN GREEN 0;
-- H2a AMBER 0; H2b equal; H3 LIVE 0 (61 CENSORED, 7 PRE_WINDOW_CHANGE, 1 estimate row), NC_NUMBER 1,
-- NC_NUMBER_PRE 1.
-- EARLIER RUNS (v27.162, trial 1). 2026-10-03 after the follow-up's deploy: job
-- bqjob_r1be9f278e3781e6f_000001a1004aff73_1, 109 statements, 806 s, 266.2 slot-s, 31 rows PASS, the
-- readings above. Before the follow-up: job bqjob_r5628fe341cbbaa3e_000001a1002f5b71_1, 22 rows PASS,
-- H2 LIVE GREEN 0 (the window-only check, blind to the 25 ledger rows on 7 HOLDOUT units between
-- 2026-08-19 and 2026-08-31); the first run (bqjob_r740ea0939f232cc6_000001a100292209_1) showed the
-- board printing "censors it from NULL", fixed since (both texts test IS NULL).
-- =============================================================================================

DECLARE veh STRING;
DECLARE c33_text STRING;
DECLARE q STRING;
DECLARE p_trial INT64;
DECLARE p_c33 INT64;
DECLARE p_end INT64;

-- ---- the live trial and its inputs, each read once (hu_trial / asg0 = c33's hu_trial / hu_asg) ----
CREATE TEMP TABLE hu_trial AS
  SELECT trial_id FROM `onyga-482313.OI.V_HOLDOUT_TRIAL` WHERE is_live
  QUALIFY ROW_NUMBER() OVER (ORDER BY assigned_on DESC, trial_id DESC) = 1;
CREATE TEMP TABLE trial_row AS
  SELECT t.* FROM `onyga-482313.OI.V_HOLDOUT_TRIAL` t JOIN hu_trial USING (trial_id);
CREATE TEMP TABLE asg0 AS
  SELECT a.unit_id, a.unit_name, a.arm, a.stratum, a.eligible_from, a.trial_end, a.assigned_at,
         a.assignment_rule
  FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT` a JOIN hu_trial USING (trial_id)
  WHERE a.unit_type = 'CAMPAIGN';
-- every change on a HOLDOUT unit inside its window, from the two sources the rule names (statement led)
CREATE TEMP TABLE led AS
  SELECT h.unit_id, h.unit_name, h.stratum, DATE(l.applied_at, 'America/Los_Angeles') AS change_day,
         l.change_id, l.source, l.action
  FROM asg0 h
  JOIN (SELECT campaign_id, applied_at, change_id, source, action FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
        UNION ALL
        SELECT campaign_id, applied_at, change_id, source, action FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
        WHERE source = 'OBSERVED') l
    ON l.campaign_id = h.unit_id
  WHERE h.arm = 'HOLDOUT'
    AND DATE(l.applied_at, 'America/Los_Angeles') BETWEEN h.eligible_from AND h.trial_end;
-- every change on a HOLDOUT unit from its assignment day to the day before its window start, from the
-- same two sources (statement pre; the v27.162 follow-up)
CREATE TEMP TABLE pre AS
  SELECT h.unit_id, h.unit_name, h.stratum, DATE(l.applied_at, 'America/Los_Angeles') AS change_day,
         l.applied_at, l.change_id, l.source, l.action
  FROM asg0 h
  JOIN (SELECT campaign_id, applied_at, change_id, source, action FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
        UNION ALL
        SELECT campaign_id, applied_at, change_id, source, action FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
        WHERE source = 'OBSERVED') l
    ON l.campaign_id = h.unit_id
  WHERE h.arm = 'HOLDOUT'
    AND DATE(l.applied_at, 'America/Los_Angeles') >= DATE(h.assigned_at, 'America/Los_Angeles')
    AND DATE(l.applied_at, 'America/Los_Angeles') < h.eligible_from;
CREATE TEMP TABLE obs0 AS
  SELECT COUNT(*) AS n FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` WHERE source = 'OBSERVED';
-- the deployed readout, every row (before first_readout the estimate is gated: no FACT_AMAZON_ADS read)
CREATE TEMP TABLE ro AS
  SELECT state, unit_id, arm, stratum, contaminated_on, censored_from, pre_window_change_on,
         (holdout_n IS NOT NULL OR treated_n IS NOT NULL OR holdout_dollars_14d IS NOT NULL
          OR treated_dollars_14d IS NOT NULL OR holdout_pre_dollars_14d IS NOT NULL
          OR treated_pre_dollars_14d IS NOT NULL OR diff_raw_14d IS NOT NULL
          OR diff_adjusted_14d IS NOT NULL OR band_95_14d IS NOT NULL OR mde_ex_ante_14d IS NOT NULL) AS has_number
  FROM `onyga-482313.OI.V_HOLDOUT_READOUT`;
-- the deployed board's row (filtering on check_name prunes every other check: measured 2026-10-03)
CREATE TEMP TABLE board AS
  SELECT check_name, measured, threshold, status, detail
  FROM `onyga-482313.OI.V_ENGINE_HEALTH` WHERE check_name = 'holdout_unit_changed';

-- ---- the picks ----
CREATE TEMP TABLE pick AS
SELECT
  (SELECT AS STRUCT unit_id, censored_from FROM ro
   WHERE state = 'CENSORED' AND contaminated_on IS NOT NULL
   ORDER BY contaminated_on, unit_id LIMIT 1) AS contam_row,
  (SELECT AS STRUCT unit_id, censored_from FROM ro
   WHERE state = 'CENSORED' AND arm = 'TREATED'
   ORDER BY censored_from, unit_id LIMIT 1) AS mate_row,
  (SELECT AS STRUCT a.unit_id, a.arm, a.stratum FROM asg0 a
   WHERE a.unit_id NOT IN (SELECT unit_id FROM ro WHERE state = 'CENSORED' AND unit_id IS NOT NULL)
   ORDER BY a.unit_id LIMIT 1) AS free_unit,
  (SELECT AS STRUCT a.unit_id, a.unit_name, a.stratum, a.eligible_from,
          COALESCE(DATE_SUB(c.censored_from, INTERVAL 1 DAY),  -- the window start while today is before it
                   GREATEST(a.eligible_from, LEAST(CURRENT_DATE('America/Los_Angeles'), a.trial_end))) AS day
   FROM asg0 a
   LEFT JOIN (SELECT unit_id, censored_from FROM ro WHERE state = 'CENSORED') c USING (unit_id)
   WHERE a.arm = 'HOLDOUT'
   ORDER BY c.censored_from IS NOT NULL, c.censored_from DESC, a.unit_id LIMIT 1) AS new_change,
  (SELECT AS STRUCT unit_id, pre_window_change_on FROM ro
   WHERE state = 'PRE_WINDOW_CHANGE'
   ORDER BY pre_window_change_on, unit_id LIMIT 1) AS pre_row,
  (SELECT AS STRUCT a.unit_id, a.unit_name, a.stratum, DATE(a.assigned_at, 'America/Los_Angeles') AS asg_day,
          DATE_SUB(a.eligible_from, INTERVAL 1 DAY) AS day
   FROM asg0 a
   WHERE a.arm = 'HOLDOUT' AND a.unit_id NOT IN (SELECT unit_id FROM pre)
   ORDER BY a.unit_id LIMIT 1) AS pre_new;

-- ---- the copies of the inputs ----
CREATE TEMP TABLE copies AS
SELECT copy FROM UNNEST(['LIVE', 'NC_DROP_ONE', 'NC_LATE', 'NC_DROP_MATE', 'HC_EXTRA', 'NC_NEW_CHANGE',
                         'NC_NO_HOLDOUT', 'NC_NO_OBSERVED', 'NC_EMPTY_RO', 'NC_NUMBER',
                         'NC_PRE_DROP', 'NC_PRE_LATE', 'HC_PRE_CLEAN', 'NC_PRE_NEW', 'NC_NUMBER_PRE']) AS copy;

CREATE TEMP TABLE cp_asg AS
SELECT c.copy, a.* FROM copies c CROSS JOIN asg0 a
WHERE NOT (c.copy = 'NC_NO_HOLDOUT' AND a.arm = 'HOLDOUT');

CREATE TEMP TABLE cp_led AS
SELECT c.copy, l.unit_id, l.unit_name, l.stratum, l.change_day, l.source
FROM copies c CROSS JOIN led l
WHERE NOT (c.copy = 'NC_NO_HOLDOUT')
  AND NOT (c.copy = 'NC_NO_OBSERVED' AND l.source = 'OBSERVED')
UNION ALL
SELECT 'NC_NEW_CHANGE', p.new_change.unit_id, p.new_change.unit_name, p.new_change.stratum,
       p.new_change.day, 'OBSERVED'
FROM pick p
WHERE p.new_change.day >= p.new_change.eligible_from;

CREATE TEMP TABLE cp_pre AS
SELECT c.copy, r.unit_id, r.unit_name, r.stratum, r.change_day, r.source
FROM copies c CROSS JOIN pre r
WHERE NOT (c.copy = 'NC_NO_HOLDOUT')
  AND NOT (c.copy = 'NC_NO_OBSERVED' AND r.source = 'OBSERVED')
  AND NOT (c.copy = 'HC_PRE_CLEAN')
UNION ALL
SELECT 'NC_PRE_NEW', p.pre_new.unit_id, p.pre_new.unit_name, p.pre_new.stratum, p.pre_new.day, 'OBSERVED'
FROM pick p
WHERE p.pre_new.day >= p.pre_new.asg_day;

CREATE TEMP TABLE cp_obs AS
SELECT c.copy, IF(c.copy = 'NC_NO_OBSERVED', 0, o.n) AS n FROM copies c CROSS JOIN obs0 o;

CREATE TEMP TABLE cp_ro AS
SELECT c.copy, r.state, r.unit_id, r.arm, r.contaminated_on,
       IF(c.copy = 'NC_LATE' AND r.state = 'CENSORED' AND r.unit_id = p.contam_row.unit_id,
          DATE_ADD(r.censored_from, INTERVAL 1 DAY), r.censored_from) AS censored_from,
       IF(c.copy = 'NC_PRE_LATE' AND r.state = 'PRE_WINDOW_CHANGE' AND r.unit_id = p.pre_row.unit_id,
          DATE_ADD(r.pre_window_change_on, INTERVAL 1 DAY), r.pre_window_change_on) AS pre_window_change_on,
       IF((c.copy = 'NC_NUMBER'  -- a CENSORED row; the NOT_YET row when no row is CENSORED
           AND ((r.state = 'CENSORED' AND r.unit_id = (SELECT MIN(unit_id) FROM ro WHERE state = 'CENSORED'))
                OR (r.state = 'NOT_YET' AND (SELECT COUNTIF(state = 'CENSORED') FROM ro) = 0)))
          OR (c.copy = 'NC_NUMBER_PRE' AND r.state = 'PRE_WINDOW_CHANGE' AND r.unit_id = p.pre_row.unit_id),
          TRUE, r.has_number) AS has_number
FROM copies c CROSS JOIN ro r CROSS JOIN pick p
WHERE c.copy != 'NC_EMPTY_RO'
  AND NOT (c.copy = 'NC_DROP_ONE'  AND r.state = 'CENSORED' AND r.unit_id = p.contam_row.unit_id)
  AND NOT (c.copy = 'NC_DROP_MATE' AND r.state = 'CENSORED' AND r.unit_id = p.mate_row.unit_id)
  AND NOT (c.copy = 'NC_PRE_DROP'  AND r.state = 'PRE_WINDOW_CHANGE' AND r.unit_id = p.pre_row.unit_id)
  AND NOT (c.copy = 'HC_PRE_CLEAN' AND r.state = 'PRE_WINDOW_CHANGE')
UNION ALL
SELECT 'HC_EXTRA', 'CENSORED', p.free_unit.unit_id, p.free_unit.arm, CAST(NULL AS DATE),
       CURRENT_DATE('America/Los_Angeles'), CAST(NULL AS DATE), FALSE
FROM pick p WHERE p.free_unit.unit_id IS NOT NULL;

-- ---- H1: per copy, the CENSORED rows against the rule re-derived from that copy's ledger ----
CREATE TEMP TABLE h1 AS
WITH
exp AS (
  SELECT a.copy, a.unit_id, c.contaminated_on, s.censored_from, q.pre_window_change_on
  FROM cp_asg a
  LEFT JOIN (SELECT copy, unit_id, MIN(change_day) AS contaminated_on FROM cp_led GROUP BY 1, 2) c
         ON c.copy = a.copy AND c.unit_id = a.unit_id
  LEFT JOIN (SELECT copy, stratum, MIN(change_day) AS censored_from FROM cp_led GROUP BY 1, 2) s
         ON s.copy = a.copy AND s.stratum = a.stratum
  LEFT JOIN (SELECT copy, unit_id, MIN(change_day) AS pre_window_change_on FROM cp_pre GROUP BY 1, 2) q
         ON q.copy = a.copy AND q.unit_id = a.unit_id
),
act AS (  -- the readout's unit rows: CENSORED and PRE_WINDOW_CHANGE, one key per (copy, state, unit)
  SELECT copy, state, unit_id, COUNT(*) AS n_rows, MIN(censored_from) AS censored_from,
         MIN(contaminated_on) AS contaminated_on, MIN(pre_window_change_on) AS pre_window_change_on
  FROM cp_ro WHERE state IN ('CENSORED', 'PRE_WINDOW_CHANGE') GROUP BY 1, 2, 3
),
per_unit AS (  -- every trial unit of the copy against its CENSORED row and its PRE_WINDOW_CHANGE row (absent = NULL)
  SELECT e.copy,
         COUNTIF(e.censored_from IS DISTINCT FROM x.censored_from) AS v_censored_from,
         COUNTIF(e.contaminated_on IS DISTINCT FROM x.contaminated_on) AS v_contaminated_on,
         COUNTIF(e.pre_window_change_on IS DISTINCT FROM xp.pre_window_change_on) AS v_pre_window,
         COUNTIF(e.censored_from IS NOT NULL) AS n_expected_censored,
         COUNTIF(e.pre_window_change_on IS NOT NULL) AS n_expected_pre
  FROM exp e
  LEFT JOIN act x  ON x.copy = e.copy  AND x.unit_id = e.unit_id  AND x.state = 'CENSORED'
  LEFT JOIN act xp ON xp.copy = e.copy AND xp.unit_id = e.unit_id AND xp.state = 'PRE_WINDOW_CHANGE'
  GROUP BY 1
),
per_row AS (  -- CENSORED / PRE_WINDOW_CHANGE rows: duplicated, or naming no trial unit of the copy
  SELECT x.copy, COUNTIF(x.n_rows > 1) AS v_duplicate, COUNTIF(a.unit_id IS NULL) AS v_alien
  FROM act x LEFT JOIN (SELECT DISTINCT copy, unit_id FROM cp_asg) a ON a.copy = x.copy AND a.unit_id = x.unit_id
  GROUP BY 1
),
empt AS (  -- the emptiness terms
  SELECT c.copy,
         IF(COALESCE(ah.n_holdout, 0) = 0, 1, 0) + IF(COALESCE(o.n, 0) = 0, 1, 0)
           + IF(COALESCE(re.n_est, 0) = 0, 1, 0) AS v_empty
  FROM copies c
  LEFT JOIN (SELECT copy, COUNTIF(arm = 'HOLDOUT') AS n_holdout FROM cp_asg GROUP BY 1) ah ON ah.copy = c.copy
  LEFT JOIN cp_obs o ON o.copy = c.copy
  LEFT JOIN (SELECT copy, COUNTIF(state IN ('NOT_YET', 'READY')) AS n_est FROM cp_ro GROUP BY 1) re ON re.copy = c.copy
)
SELECT c.copy,
       COALESCE(u.v_censored_from, 0) AS v_censored_from,
       COALESCE(u.v_contaminated_on, 0) AS v_contaminated_on,
       COALESCE(u.v_pre_window, 0) AS v_pre_window,
       COALESCE(r.v_duplicate, 0) AS v_duplicate,
       COALESCE(r.v_alien, 0) AS v_alien,
       e.v_empty,
       COALESCE(u.n_expected_censored, 0) AS n_expected_censored,
       COALESCE(u.n_expected_pre, 0) AS n_expected_pre
FROM copies c
LEFT JOIN per_unit u ON u.copy = c.copy
LEFT JOIN per_row r ON r.copy = c.copy
LEFT JOIN empt e ON e.copy = c.copy;

-- ---- H2: the board's own text, run on each copy (hu_trial is the temp table above) ----
CREATE TEMP TABLE twin (copy STRING, check_name STRING, measured FLOAT64, threshold STRING, status STRING, detail STRING);
FOR cp IN (SELECT copy FROM copies WHERE copy NOT IN ('NC_NUMBER', 'NC_NUMBER_PRE') ORDER BY copy) DO
  CREATE OR REPLACE TEMP TABLE hu_asg AS
    SELECT unit_id, unit_name, arm, stratum, eligible_from, trial_end, assigned_at, assignment_rule
    FROM cp_asg WHERE copy = cp.copy;
  CREATE OR REPLACE TEMP TABLE hu_led AS
    SELECT unit_id, unit_name, stratum, change_day FROM cp_led WHERE copy = cp.copy;
  CREATE OR REPLACE TEMP TABLE hu_pre AS
    SELECT unit_id, unit_name, stratum, change_day FROM cp_pre WHERE copy = cp.copy;
  CREATE OR REPLACE TEMP TABLE hu_cens AS
    SELECT unit_id, censored_from FROM cp_ro WHERE copy = cp.copy AND state = 'CENSORED';
  CREATE OR REPLACE TEMP TABLE hu_pre_ro AS
    SELECT unit_id, pre_window_change_on FROM cp_ro WHERE copy = cp.copy AND state = 'PRE_WINDOW_CHANGE';
  CREATE OR REPLACE TEMP TABLE hu_obs AS
    SELECT n FROM cp_obs WHERE copy = cp.copy;
  INSERT INTO twin (copy, check_name, measured, threshold, status, detail)
  WITH
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
  SELECT cp.copy, * FROM c33;
END FOR;
-- R9's part of measured, read from the detail's own clauses (one per hu_gap row, one per hu_pre_gap row)
CREATE TEMP TABLE twin_r9 AS
SELECT copy, check_name, status, measured, threshold, detail,
       ARRAY_LENGTH(REGEXP_EXTRACT_ALL(detail, r'its stratum changed on \d{4}-\d{2}-\d{2}, the readout censors it '))
       + ARRAY_LENGTH(REGEXP_EXTRACT_ALL(detail, r'before its window start, the readout publishes it ')) AS r9
FROM twin;

-- ---- H3: the gate, per copy (first_readout of the live trial, V_HOLDOUT_TRIAL) ----
CREATE TEMP TABLE h3 AS
SELECT c.copy,
  IF(CURRENT_DATE('America/Los_Angeles') < (SELECT MAX(first_readout) FROM trial_row),
     IF(COALESCE(g.n_not_yet, 0) = 1, 0, 1) + COALESCE(g.n_ready, 0), 0)
  + IF((SELECT COUNT(*) FROM trial_row) = 1 AND (SELECT MAX(first_readout) FROM trial_row) IS NOT NULL, 0, 1)
  + COALESCE(g.n_number, 0) + COALESCE(g.n_bad_censored, 0) + COALESCE(g.n_bad_pre, 0)
  + COALESCE(g.n_bad_state, 0) AS v_gate
FROM copies c
LEFT JOIN (
  SELECT copy,
         COUNTIF(state = 'NOT_YET') AS n_not_yet,
         COUNTIF(state = 'READY') AS n_ready,
         COUNTIF(has_number AND state IN ('NOT_YET', 'CENSORED', 'PRE_WINDOW_CHANGE')) AS n_number,
         COUNTIF(state = 'CENSORED' AND (unit_id IS NULL OR censored_from IS NULL)) AS n_bad_censored,
         COUNTIF(state = 'PRE_WINDOW_CHANGE' AND (unit_id IS NULL OR pre_window_change_on IS NULL)) AS n_bad_pre,
         COUNTIF(state NOT IN ('NOT_YET', 'READY', 'CENSORED', 'PRE_WINDOW_CHANGE')) AS n_bad_state
  FROM cp_ro GROUP BY 1) g ON g.copy = c.copy;

-- =============================================================================================
-- ---- H4 / H5: the DEPLOYED c33 text (hu_trial .. c33, read from INFORMATION_SCHEMA.VIEWS) run on
-- copies, every source pointed at a temp copy; one doctored input per case (the header lists them).
-- =============================================================================================
SET veh = (SELECT view_definition FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS` WHERE table_name = 'V_ENGINE_HEALTH');
SET p_trial = STRPOS(veh, '\nhu_trial AS (');
SET p_c33 = STRPOS(veh, '\nc33 AS (');
SET p_end = IF(p_c33 = 0, 0, p_c33 + STRPOS(SUBSTR(veh, p_c33), '\n)\n'));
SET c33_text = IF(p_trial = 0 OR p_c33 = 0 OR p_end <= p_c33, NULL, SUBSTR(veh, p_trial + 1, p_end - p_trial));

CREATE TEMP FUNCTION ht_replace_all(s STRING, reps ARRAY<STRUCT<src STRING, dst STRING>>)
RETURNS STRING LANGUAGE js AS r"""
  let t = s;
  for (const r of reps) { t = t.split(r.src).join(r.dst); }
  return t;
""";

-- the anchors: the trial's assignment day (LA), every base copy holding only what is older than it;
-- one clock (now_ts) for every injected change, so a run that crosses LA midnight stays consistent
CREATE TEMP TABLE k45 AS
SELECT (SELECT MIN(DATE(assigned_at, 'America/Los_Angeles')) FROM asg0) AS asg_day,
       DATE(n.now_ts, 'America/Los_Angeles') AS today, n.now_ts,
       (SELECT trial_id FROM hu_trial) AS trial_id
FROM (SELECT CURRENT_TIMESTAMP() AS now_ts) n;

-- ---- the base copies (case H4_BASE): no touch of any kind, every feed stamp 1 hour old ----
CREATE TEMP TABLE d_trial AS SELECT * FROM `onyga-482313.OI.V_HOLDOUT_TRIAL`;
CREATE TEMP TABLE d_asg AS SELECT * FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`;
CREATE TEMP TABLE d_applied AS
  SELECT campaign_id, applied_at FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`, k45
  WHERE DATE(applied_at, 'America/Los_Angeles') < k45.asg_day;
CREATE TEMP TABLE d_fact AS
  SELECT campaign_id, applied_at, source FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`, k45
  WHERE DATE(applied_at, 'America/Los_Angeles') < k45.asg_day;
CREATE TEMP TABLE d_ro (state STRING, unit_id STRING, censored_from DATE, pre_window_change_on DATE);
CREATE TEMP TABLE d_dimk AS
  SELECT keyword_id, campaign_id, keyword_text, match_type, effective_from, _fivetran_synced
  FROM `onyga-482313.OI.DIM_KEYWORD`, k45
  WHERE DATE(TIMESTAMP(effective_from, 'UTC'), 'America/Los_Angeles') < k45.asg_day;
CREATE TEMP TABLE d_dimag AS
  SELECT ad_group_id, campaign_id, ad_group_name, effective_from, _fivetran_synced
  FROM `onyga-482313.OI.DIM_AD_GROUP`, k45
  WHERE DATE(TIMESTAMP(effective_from, 'UTC'), 'America/Los_Angeles') < k45.asg_day;
CREATE TEMP TABLE d_dimc AS
  SELECT campaign_id, effective_from, portfolio_id, bidding_strategy, _fivetran_synced
  FROM `onyga-482313.OI.DIM_CAMPAIGN`, k45
  WHERE DATE(TIMESTAMP(effective_from, 'UTC'), 'America/Los_Angeles') < k45.asg_day;
CREATE TEMP TABLE d_sbch AS
  SELECT id, last_update_date, bid_optimization, bid_optimization_strategy, end_date, _fivetran_synced
  FROM `fivetran-hl.amazon_ads.sb_campaign_history`, k45
  WHERE DATE(last_update_date, 'America/Los_Angeles') < k45.asg_day;
CREATE TEMP TABLE d_ch AS
  SELECT id, last_updated_date, end_date, _fivetran_synced
  FROM `fivetran-hl.amazon_ads.campaign_history`, k45
  WHERE DATE(last_updated_date, 'America/Los_Angeles') < k45.asg_day;
CREATE TEMP TABLE d_sp AS
  SELECT campaign_id, placement, percentage, _fivetran_synced FROM `fivetran-hl.amazon_ads.campaign_placement_bidding`;
CREATE TEMP TABLE d_sbp AS
  SELECT campaign_id, placement, percentage, _fivetran_synced FROM `fivetran-hl.amazon_ads.sb_campaign_bid_adjustments_by_placement`;
CREATE TEMP TABLE d_sbc AS
  SELECT campaign_id, audience_id, shopper_cohort_type, percentage, _fivetran_synced
  FROM `fivetran-hl.amazon_ads.sb_campaign_bid_adjustments_shopper_cohort`;
CREATE TEMP TABLE d_sbt AS
  SELECT id, campaign_id, state, bid, _fivetran_deleted, _fivetran_synced FROM `fivetran-hl.amazon_ads.sb_product_target`;
-- the baseline equals today's present settings of the watched set (the presence rule, as the founding insert)
CREATE TEMP TABLE d_base AS
WITH w AS (SELECT unit_id FROM asg0 WHERE arm = 'HOLDOUT' AND STARTS_WITH(assignment_rule, 'FOUNDING')),
sp  AS (SELECT *, MAX(_fivetran_synced) OVER () AS mx FROM d_sp),
sbp AS (SELECT *, MAX(_fivetran_synced) OVER () AS mx FROM d_sbp),
sbc AS (SELECT *, MAX(_fivetran_synced) OVER () AS mx FROM d_sbc),
sbt AS (SELECT *, MAX(_fivetran_synced) OVER () AS mx FROM d_sbt),
p AS (
  SELECT campaign_id, CONCAT('SP_PLACEMENT|', placement) AS setting, CAST(percentage AS STRING) AS value,
         'campaign_placement_bidding' AS source, mx
  FROM sp WHERE _fivetran_synced >= TIMESTAMP_SUB(mx, INTERVAL 1 HOUR)
  UNION ALL SELECT campaign_id, CONCAT('SB_PLACEMENT|', placement), CAST(percentage AS STRING),
         'sb_campaign_bid_adjustments_by_placement', mx
  FROM sbp WHERE _fivetran_synced >= TIMESTAMP_SUB(mx, INTERVAL 1 HOUR)
  UNION ALL SELECT campaign_id, CONCAT('SB_SHOPPER_COHORT|', audience_id, '|', shopper_cohort_type),
         CAST(percentage AS STRING), 'sb_campaign_bid_adjustments_shopper_cohort', mx
  FROM sbc WHERE _fivetran_synced >= TIMESTAMP_SUB(mx, INTERVAL 1 HOUR)
  UNION ALL SELECT campaign_id, CONCAT('SB_TARGET|', id, '|', kv.k), kv.v, 'sb_product_target', mx
  FROM sbt, UNNEST([STRUCT('bid' AS k, CAST(bid AS STRING) AS v), STRUCT('state', state)]) kv
  WHERE _fivetran_synced >= TIMESTAMP_SUB(mx, INTERVAL 1 HOUR) AND NOT COALESCE(_fivetran_deleted, FALSE))
SELECT k45.trial_id, p.campaign_id, p.setting, TIMESTAMP_SUB(k45.now_ts, INTERVAL 1 MINUTE) AS recorded_at,
       p.value, p.source, p.mx AS source_synced_at, CAST(NULL AS STRING) AS ruling
FROM p, k45 WHERE p.campaign_id IN (SELECT unit_id FROM w);
CREATE TEMP TABLE d_log AS
  SELECT procedure_name, 'OK' AS status, TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR) AS started_at
  FROM UNNEST(['SP_RECORD_OBSERVED_CHANGES', 'SP_LOAD_DIM_KEYWORD', 'SP_LOAD_DIM_CAMPAIGN', 'SP_LOAD_DIM_AD_GROUP']) AS procedure_name;
CREATE TEMP TABLE d_fresh AS SELECT TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR) AS _fivetran_synced;
CREATE TEMP TABLE d_stale AS SELECT TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 37 HOUR) AS _fivetran_synced;
CREATE TEMP TABLE d_empty (_fivetran_synced TIMESTAMP);

-- ---- the picks for H4 (derived from the copies; no campaign id is written in this file) ----
CREATE TEMP TABLE pick45 AS
WITH w AS (SELECT unit_id, unit_name, stratum FROM asg0 WHERE arm = 'HOLDOUT' AND STARTS_WITH(assignment_rule, 'FOUNDING')),
sp_x  AS (SELECT *, _fivetran_synced >= TIMESTAMP_SUB(MAX(_fivetran_synced) OVER (), INTERVAL 1 HOUR) AS present FROM d_sp),
sbp_x AS (SELECT *, _fivetran_synced >= TIMESTAMP_SUB(MAX(_fivetran_synced) OVER (), INTERVAL 1 HOUR) AS present FROM d_sbp),
sbt_x AS (SELECT *, _fivetran_synced >= TIMESTAMP_SUB(MAX(_fivetran_synced) OVER (), INTERVAL 1 HOUR)
                    AND NOT COALESCE(_fivetran_deleted, FALSE) AS present FROM d_sbt)
SELECT
  (SELECT AS STRUCT unit_id, unit_name, stratum, eligible_from, trial_end, DATE(assigned_at, 'America/Los_Angeles') AS asg_day
   FROM asg0 WHERE arm = 'HOLDOUT' ORDER BY unit_id LIMIT 1) AS led,
  (SELECT AS STRUCT unit_id, unit_name FROM w ORDER BY unit_id LIMIT 1) AS kw,
  (SELECT AS STRUCT w.unit_id, w.unit_name FROM w JOIN (SELECT DISTINCT campaign_id FROM d_dimc) c ON c.campaign_id = w.unit_id
   WHERE STARTS_WITH(w.stratum, 'SP|') ORDER BY w.unit_id LIMIT 1) AS sp_camp,
  (SELECT AS STRUCT w.unit_id, w.unit_name FROM w JOIN (SELECT DISTINCT id FROM d_sbch) s ON s.id = w.unit_id
   WHERE STARTS_WITH(w.stratum, 'SB|') ORDER BY w.unit_id LIMIT 1) AS sb_camp,
  (SELECT AS STRUCT w.unit_id, w.unit_name FROM w JOIN (SELECT DISTINCT id FROM d_ch) c ON c.id = w.unit_id
   WHERE STARTS_WITH(w.stratum, 'SP|') ORDER BY w.unit_id LIMIT 1) AS sp_ch,
  (SELECT AS STRUCT campaign_id, setting, value FROM d_base ORDER BY campaign_id, setting LIMIT 1) AS base_row,
  (SELECT AS STRUCT w.unit_id, w.unit_name FROM w
   WHERE STARTS_WITH(w.stratum, 'SP|') AND w.unit_id NOT IN (SELECT campaign_id FROM d_base)
   ORDER BY w.unit_id LIMIT 1) AS no_base,
  (SELECT AS STRUCT campaign_id, placement, percentage FROM sp_x
   WHERE present AND campaign_id IN (SELECT unit_id FROM w) ORDER BY campaign_id, placement LIMIT 1) AS removal,
  (SELECT AS STRUCT campaign_id, id FROM sbt_x
   WHERE present AND campaign_id IN (SELECT unit_id FROM w) ORDER BY campaign_id, id LIMIT 1) AS sbt,
  (SELECT AS STRUCT campaign_id FROM sbp_x
   WHERE present AND campaign_id NOT IN (SELECT unit_id FROM asg0)
   GROUP BY campaign_id ORDER BY LOGICAL_AND(percentage = 0) DESC, campaign_id LIMIT 1) AS late,
  (SELECT COUNTIF(NOT present) FROM sp_x) AS n_stale_sp,
  (SELECT COUNT(DISTINCT campaign_id) FROM d_base) AS n_base_controls,
  (SELECT COUNT(*) FROM asg0 WHERE arm = 'HOLDOUT') AS n_hold;

-- ---- the doctored copies (case_name keys the rows a case reads) ----
-- LEDGER: an observed change on a control now; the readout copy censors (in the window) or publishes it
CREATE TEMP TABLE d_fact_add AS
  SELECT p.led.unit_id AS campaign_id, k45.now_ts AS applied_at, 'OBSERVED' AS source FROM pick45 p, k45;
CREATE TEMP TABLE d_ro_led AS
  SELECT 'CENSORED' AS state, a.unit_id, k45.today AS censored_from, CAST(NULL AS DATE) AS pre_window_change_on
  FROM pick45 p, k45, asg0 a
  WHERE a.stratum = p.led.stratum AND k45.today BETWEEN p.led.eligible_from AND p.led.trial_end
  UNION ALL
  SELECT 'PRE_WINDOW_CHANGE', p.led.unit_id, CAST(NULL AS DATE), k45.today
  FROM pick45 p, k45
  WHERE k45.today >= p.led.asg_day AND k45.today < p.led.eligible_from;
-- NEW_ENTITY: a keyword / an ad group created on a control now, or the day before the assignment
CREATE TEMP TABLE d_dimk_add AS
  SELECT c.case_name, 'ht2-acceptance-new-keyword' AS keyword_id, p.kw.unit_id AS campaign_id,
         'ht2 acceptance probe' AS keyword_text, 'EXACT' AS match_type, c.eff AS effective_from, k45.now_ts AS _fivetran_synced
  FROM pick45 p, k45,
       UNNEST([STRUCT('H4_NEW_KEYWORD' AS case_name, DATETIME(k45.now_ts, 'UTC') AS eff),
               STRUCT('H4_NEW_KEYWORD_BEFORE', DATETIME(TIMESTAMP(DATETIME(DATE_SUB(k45.asg_day, INTERVAL 1 DAY), TIME '12:00:00'), 'America/Los_Angeles'), 'UTC'))]) c;
CREATE TEMP TABLE d_dimag_add AS
  SELECT 'ht2-acceptance-new-ad-group' AS ad_group_id, p.kw.unit_id AS campaign_id, 'ht2 acceptance probe' AS ad_group_name,
         DATETIME(k45.now_ts, 'UTC') AS effective_from, k45.now_ts AS _fivetran_synced
  FROM pick45 p, k45;
-- CAMPAIGN_ATTR: a new DIM_CAMPAIGN version now with the portfolio, or the bidding strategy, changed;
-- a new sb_campaign_history version now with bid_optimization flipped
CREATE TEMP TABLE d_dimc_add AS
  SELECT c.case_name, d.campaign_id, DATETIME(k45.now_ts, 'UTC') AS effective_from,
         IF(c.case_name = 'H4_PORTFOLIO', CONCAT(IFNULL(d.portfolio_id, 'none'), '-moved'), d.portfolio_id) AS portfolio_id,
         IF(c.case_name = 'H4_BIDDING_STRATEGY',
            IF(d.bidding_strategy = 'AUTO_FOR_SALES', 'LEGACY_FOR_SALES', 'AUTO_FOR_SALES'), d.bidding_strategy) AS bidding_strategy,
         k45.now_ts AS _fivetran_synced
  FROM (SELECT * FROM d_dimc WHERE campaign_id = (SELECT sp_camp.unit_id FROM pick45)
        QUALIFY ROW_NUMBER() OVER (ORDER BY effective_from DESC, _fivetran_synced DESC) = 1) d, k45,
       UNNEST([STRUCT('H4_PORTFOLIO' AS case_name), STRUCT('H4_BIDDING_STRATEGY')]) c;
-- (and, H4_SB_END_DATE, a new sb_campaign_history version now with an end date 16 days out)
CREATE TEMP TABLE d_sbch_add AS
  SELECT c.case_name, s.id, (SELECT now_ts FROM k45) AS last_update_date,
         IF(c.case_name = 'H4_SB_BID_OPT', NOT COALESCE(s.bid_optimization, FALSE), s.bid_optimization) AS bid_optimization,
         s.bid_optimization_strategy,
         IF(c.case_name = 'H4_SB_END_DATE', DATE_ADD((SELECT today FROM k45), INTERVAL 16 DAY), s.end_date) AS end_date,
         (SELECT now_ts FROM k45) AS _fivetran_synced
  FROM (SELECT * FROM d_sbch WHERE id = (SELECT sb_camp.unit_id FROM pick45)
        QUALIFY ROW_NUMBER() OVER (ORDER BY last_update_date DESC, _fivetran_synced DESC) = 1) s,
       UNNEST([STRUCT('H4_SB_BID_OPT' AS case_name), STRUCT('H4_SB_END_DATE')]) c;
-- END DATE (SP): a new campaign_history version now on a founding SP control, its end date set 16 days out
CREATE TEMP TABLE d_ch_add AS
  SELECT id, (SELECT now_ts FROM k45) AS last_updated_date, DATE_ADD((SELECT today FROM k45), INTERVAL 16 DAY) AS end_date,
         (SELECT now_ts FROM k45) AS _fivetran_synced
  FROM d_ch WHERE id = (SELECT sp_ch.unit_id FROM pick45)
  QUALIFY ROW_NUMBER() OVER (ORDER BY last_updated_date DESC, _fivetran_synced DESC) = 1;
-- BASELINE_DIFF on the baseline side: one value altered; then re-baselined by a ruling; a removal re-baselined NULL
CREATE TEMP TABLE d_base_doc AS
  SELECT c.case_name, b.* REPLACE (
           IF(c.case_name IN ('H4_BASELINE_ALTERED', 'H4_BASELINE_REBASED')
              AND b.campaign_id = p.base_row.campaign_id AND b.setting = p.base_row.setting,
              CONCAT(IFNULL(b.value, ''), '-altered'), b.value) AS value)
  FROM d_base b, pick45 p,
       UNNEST([STRUCT('H4_BASELINE_ALTERED' AS case_name), STRUCT('H4_BASELINE_REBASED'), STRUCT('H4_REMOVAL_REBASED')]) c
  UNION ALL
  SELECT 'H4_BASELINE_REBASED', k45.trial_id, p.base_row.campaign_id, p.base_row.setting, k45.now_ts,
         p.base_row.value, 'acceptance re-baseline', CAST(NULL AS TIMESTAMP), 'acceptance probe: a ruling re-baselines the value'
  FROM pick45 p, k45 WHERE p.base_row.campaign_id IS NOT NULL
  UNION ALL
  SELECT 'H4_REMOVAL_REBASED', k45.trial_id, p.removal.campaign_id, CONCAT('SP_PLACEMENT|', p.removal.placement), k45.now_ts,
         CAST(NULL AS STRING), 'acceptance re-baseline', CAST(NULL AS TIMESTAMP), 'acceptance probe: a ruling accepts the removal'
  FROM pick45 p, k45 WHERE p.removal.campaign_id IS NOT NULL;
-- BASELINE_DIFF on the source side (campaign_placement_bidding): a setting put on a watched control with no
-- baseline row; a removal (its row no longer re-stamped); the stale rows dropped by a re-sync
CREATE TEMP TABLE d_sp_doc AS
  SELECT c.case_name, s.* REPLACE (
           IF(c.case_name IN ('H4_REMOVAL', 'H4_REMOVAL_REBASED')
              AND s.campaign_id = p.removal.campaign_id AND s.placement = p.removal.placement,
              TIMESTAMP_SUB(s._fivetran_synced, INTERVAL 12 HOUR), s._fivetran_synced) AS _fivetran_synced)
  FROM d_sp s, pick45 p, UNNEST([STRUCT('H4_WATCHED_NO_BASELINE' AS case_name), STRUCT('H4_REMOVAL'),
                                  STRUCT('H4_REMOVAL_REBASED'), STRUCT('H4_STALE_DROPPED')]) c
  WHERE NOT (c.case_name = 'H4_STALE_DROPPED'
             AND s._fivetran_synced < TIMESTAMP_SUB((SELECT MAX(_fivetran_synced) FROM d_sp), INTERVAL 1 HOUR))
  UNION ALL
  SELECT 'H4_WATCHED_NO_BASELINE', p.no_base.unit_id, 'PLACEMENT_TOP', 30, (SELECT MAX(_fivetran_synced) FROM d_sp)
  FROM pick45 p WHERE p.no_base.unit_id IS NOT NULL;
CREATE TEMP TABLE d_sbt_doc AS
  SELECT 'H4_SB_TARGET_DELETED' AS case_name, t.* REPLACE (
           IF(t.campaign_id = p.sbt.campaign_id AND t.id = p.sbt.id, TRUE, t._fivetran_deleted) AS _fivetran_deleted)
  FROM d_sbt t, pick45 p;
-- the watched set: a LATE ARRIVAL control added (an SB campaign outside the trial with present placement
-- rows); every FOUNDING rule re-prefixed, so the watched set is empty
CREATE TEMP TABLE d_asg_doc AS
  SELECT 'H4_LATE_ARRIVAL' AS case_name, a.* FROM d_asg a
  UNION ALL
  SELECT 'H4_LATE_ARRIVAL', a.* REPLACE (
           p.late.campaign_id AS unit_id,
           IFNULL((SELECT MAX(campaign_name) FROM `onyga-482313.OI.DIM_CAMPAIGN` WHERE campaign_id = p.late.campaign_id AND is_current),
                  'late arrival') AS unit_name,
           'LATE ARRIVAL (first sight): acceptance probe' AS assignment_rule,
           (SELECT now_ts FROM k45) AS assigned_at)
  FROM (SELECT * FROM d_asg WHERE trial_id = (SELECT trial_id FROM k45) AND unit_type = 'CAMPAIGN' AND arm = 'HOLDOUT'
          AND STARTS_WITH(assignment_rule, 'FOUNDING')
        QUALIFY ROW_NUMBER() OVER (ORDER BY unit_id) = 1) a, pick45 p
  WHERE p.late.campaign_id IS NOT NULL
  UNION ALL
  SELECT 'H4_NO_WATCHED_SET', a.* REPLACE (
           IF(a.trial_id = (SELECT trial_id FROM k45), REGEXP_REPLACE(a.assignment_rule, r'^FOUNDING', 'LATE ARRIVAL'),
              a.assignment_rule) AS assignment_rule)
  FROM d_asg a;
-- FEED: one procedure's last OK run 37 hours old, or missing
CREATE TEMP TABLE d_log_doc AS
  SELECT CONCAT('H5_PROC_', p) AS case_name, l.procedure_name, l.status,
         IF(l.procedure_name = p, TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 37 HOUR), l.started_at) AS started_at
  FROM d_log l, UNNEST(['SP_RECORD_OBSERVED_CHANGES', 'SP_LOAD_DIM_KEYWORD', 'SP_LOAD_DIM_CAMPAIGN', 'SP_LOAD_DIM_AD_GROUP']) AS p
  UNION ALL
  SELECT 'H5_PROC_MISSING', procedure_name, status, started_at FROM d_log WHERE procedure_name != 'SP_RECORD_OBSERVED_CHANGES';

-- ---- the cases: what each reads instead of the base copy, and what it must read ----
CREATE TEMP TABLE ft45 AS
SELECT t, o FROM UNNEST(['keyword_history', 'sb_keyword', 'targeting_clause_history', 'campaign_history',
                         'sb_campaign_history', 'ad_group_history', 'sb_ad_group_history',
                         'campaign_placement_bidding', 'sb_campaign_bid_adjustments_by_placement',
                         'sb_campaign_bid_adjustments_shopper_cohort', 'sb_product_target']) AS t WITH OFFSET o;
CREATE TEMP TABLE repl45 AS
-- base ('*'): the 11 feed-age reads first (the six shared tables are also read whole, below), then every name
SELECT '*' AS case_name, CONCAT('MAX(_fivetran_synced) FROM `fivetran-hl.amazon_ads.', t, '`') AS src,
       'MAX(_fivetran_synced) FROM d_fresh' AS dst, 10 + o AS ord
FROM ft45
UNION ALL
SELECT '*', src, dst, ord FROM UNNEST([
  STRUCT('`onyga-482313.OI.V_HOLDOUT_TRIAL`' AS src, 'd_trial' AS dst, 30 AS ord),
  ('`onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`', 'd_asg', 31),
  ('`onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`', 'd_applied', 32),
  ('`onyga-482313.OI.FACT_PPC_CHANGE_LOG`', 'd_fact', 33),
  ('`onyga-482313.OI.V_HOLDOUT_READOUT`', 'd_ro', 34),
  ('`onyga-482313.OI.DIM_KEYWORD`', 'd_dimk', 35),
  ('`onyga-482313.OI.DIM_AD_GROUP`', 'd_dimag', 36),
  ('`onyga-482313.OI.DIM_CAMPAIGN`', 'd_dimc', 37),
  ('`fivetran-hl.amazon_ads.sb_campaign_history`', 'd_sbch', 38),
  ('`fivetran-hl.amazon_ads.campaign_placement_bidding`', 'd_sp', 39),
  ('`fivetran-hl.amazon_ads.sb_campaign_bid_adjustments_by_placement`', 'd_sbp', 40),
  ('`fivetran-hl.amazon_ads.sb_campaign_bid_adjustments_shopper_cohort`', 'd_sbc', 41),
  ('`fivetran-hl.amazon_ads.sb_product_target`', 'd_sbt', 42),
  ('`onyga-482313.OI.DE_HOLDOUT_BASELINE`', 'd_base', 43),
  ('`onyga-482313.OI.LOG_PIPELINE_RUNS`', 'd_log', 44),
  ('`fivetran-hl.amazon_ads.campaign_history`', 'd_ch', 45)])
UNION ALL
SELECT case_name, src, dst, ord FROM UNNEST([
  STRUCT('H4_LEDGER_TODAY' AS case_name, '`onyga-482313.OI.FACT_PPC_CHANGE_LOG`' AS src,
         '(SELECT * FROM d_fact UNION ALL SELECT * FROM d_fact_add)' AS dst, 33 AS ord),
  ('H4_LEDGER_TODAY', '`onyga-482313.OI.V_HOLDOUT_READOUT`', 'd_ro_led', 34),
  ('H4_LEDGER_7D', '`onyga-482313.OI.FACT_PPC_CHANGE_LOG`', '(SELECT * FROM d_fact UNION ALL SELECT * FROM d_fact_add)', 33),
  ('H4_LEDGER_7D', '`onyga-482313.OI.V_HOLDOUT_READOUT`', 'd_ro_led', 34),
  ('H4_LEDGER_8D', '`onyga-482313.OI.FACT_PPC_CHANGE_LOG`', '(SELECT * FROM d_fact UNION ALL SELECT * FROM d_fact_add)', 33),
  ('H4_LEDGER_8D', '`onyga-482313.OI.V_HOLDOUT_READOUT`', 'd_ro_led', 34),
  ('H4_NEW_KEYWORD', '`onyga-482313.OI.DIM_KEYWORD`',
   "(SELECT * FROM d_dimk UNION ALL SELECT * EXCEPT (case_name) FROM d_dimk_add WHERE case_name = 'H4_NEW_KEYWORD')", 35),
  ('H4_NEW_KEYWORD_BEFORE', '`onyga-482313.OI.DIM_KEYWORD`',
   "(SELECT * FROM d_dimk UNION ALL SELECT * EXCEPT (case_name) FROM d_dimk_add WHERE case_name = 'H4_NEW_KEYWORD_BEFORE')", 35),
  ('H4_NEW_AD_GROUP', '`onyga-482313.OI.DIM_AD_GROUP`', '(SELECT * FROM d_dimag UNION ALL SELECT * FROM d_dimag_add)', 36),
  ('H4_PORTFOLIO', '`onyga-482313.OI.DIM_CAMPAIGN`',
   "(SELECT * FROM d_dimc UNION ALL SELECT * EXCEPT (case_name) FROM d_dimc_add WHERE case_name = 'H4_PORTFOLIO')", 37),
  ('H4_BIDDING_STRATEGY', '`onyga-482313.OI.DIM_CAMPAIGN`',
   "(SELECT * FROM d_dimc UNION ALL SELECT * EXCEPT (case_name) FROM d_dimc_add WHERE case_name = 'H4_BIDDING_STRATEGY')", 37),
  ('H4_SB_BID_OPT', '`fivetran-hl.amazon_ads.sb_campaign_history`',
   "(SELECT * FROM d_sbch UNION ALL SELECT * EXCEPT (case_name) FROM d_sbch_add WHERE case_name = 'H4_SB_BID_OPT')", 38),
  ('H4_SB_END_DATE', '`fivetran-hl.amazon_ads.sb_campaign_history`',
   "(SELECT * FROM d_sbch UNION ALL SELECT * EXCEPT (case_name) FROM d_sbch_add WHERE case_name = 'H4_SB_END_DATE')", 38),
  ('H4_END_DATE', '`fivetran-hl.amazon_ads.campaign_history`', '(SELECT * FROM d_ch UNION ALL SELECT * FROM d_ch_add)', 45),
  ('H4_BASELINE_ALTERED', '`onyga-482313.OI.DE_HOLDOUT_BASELINE`',
   "(SELECT * EXCEPT (case_name) FROM d_base_doc WHERE case_name = 'H4_BASELINE_ALTERED')", 43),
  ('H4_BASELINE_REBASED', '`onyga-482313.OI.DE_HOLDOUT_BASELINE`',
   "(SELECT * EXCEPT (case_name) FROM d_base_doc WHERE case_name = 'H4_BASELINE_REBASED')", 43),
  ('H4_WATCHED_NO_BASELINE', '`fivetran-hl.amazon_ads.campaign_placement_bidding`',
   "(SELECT * EXCEPT (case_name) FROM d_sp_doc WHERE case_name = 'H4_WATCHED_NO_BASELINE')", 39),
  ('H4_REMOVAL', '`fivetran-hl.amazon_ads.campaign_placement_bidding`',
   "(SELECT * EXCEPT (case_name) FROM d_sp_doc WHERE case_name = 'H4_REMOVAL')", 39),
  ('H4_REMOVAL_REBASED', '`fivetran-hl.amazon_ads.campaign_placement_bidding`',
   "(SELECT * EXCEPT (case_name) FROM d_sp_doc WHERE case_name = 'H4_REMOVAL_REBASED')", 39),
  ('H4_REMOVAL_REBASED', '`onyga-482313.OI.DE_HOLDOUT_BASELINE`',
   "(SELECT * EXCEPT (case_name) FROM d_base_doc WHERE case_name = 'H4_REMOVAL_REBASED')", 43),
  ('H4_STALE_DROPPED', '`fivetran-hl.amazon_ads.campaign_placement_bidding`',
   "(SELECT * EXCEPT (case_name) FROM d_sp_doc WHERE case_name = 'H4_STALE_DROPPED')", 39),
  ('H4_SB_TARGET_DELETED', '`fivetran-hl.amazon_ads.sb_product_target`',
   "(SELECT * EXCEPT (case_name) FROM d_sbt_doc WHERE case_name = 'H4_SB_TARGET_DELETED')", 42),
  ('H4_LATE_ARRIVAL', '`onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`',
   "(SELECT * EXCEPT (case_name) FROM d_asg_doc WHERE case_name = 'H4_LATE_ARRIVAL')", 31),
  ('H4_NO_WATCHED_SET', '`onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`',
   "(SELECT * EXCEPT (case_name) FROM d_asg_doc WHERE case_name = 'H4_NO_WATCHED_SET')", 31),
  ('H5_PROC_MISSING', '`onyga-482313.OI.LOG_PIPELINE_RUNS`',
   "(SELECT * EXCEPT (case_name) FROM d_log_doc WHERE case_name = 'H5_PROC_MISSING')", 44),
  ('H5_TABLE_MISSING', 'MAX(_fivetran_synced) FROM `fivetran-hl.amazon_ads.sb_product_target`',
   'MAX(_fivetran_synced) FROM d_empty', 20)])
UNION ALL
-- the aging cases read c33's only CURRENT_DATE('America/Los_Angeles') as a fixed day 7 / 8 days after the change
SELECT c.case_name, "CURRENT_DATE('America/Los_Angeles')", FORMAT("DATE '%t'", DATE_ADD(k45.today, INTERVAL c.d DAY)), 1
FROM k45, UNNEST([STRUCT('H4_LEDGER_7D' AS case_name, 7 AS d), STRUCT('H4_LEDGER_8D', 8)]) c
UNION ALL
SELECT CONCAT('H5_PROC_', p), '`onyga-482313.OI.LOG_PIPELINE_RUNS`',
       CONCAT("(SELECT * EXCEPT (case_name) FROM d_log_doc WHERE case_name = 'H5_PROC_", p, "')"), 44
FROM UNNEST(['SP_RECORD_OBSERVED_CHANGES', 'SP_LOAD_DIM_KEYWORD', 'SP_LOAD_DIM_CAMPAIGN', 'SP_LOAD_DIM_AD_GROUP']) AS p
UNION ALL
SELECT CONCAT('H5_TABLE_', t), CONCAT('MAX(_fivetran_synced) FROM `fivetran-hl.amazon_ads.', t, '`'),
       'MAX(_fivetran_synced) FROM d_stale', 10 + o
FROM ft45;

-- what each case must read (status, measured, the clauses its detail must carry; vacuous when its pick is missing)
CREATE TEMP TABLE exp45 AS
WITH p AS (SELECT * FROM pick45), k AS (SELECT * FROM k45),
led_in AS (  -- the injected ledger change is a touch only from the control's assignment day to its trial_end
  SELECT k.today >= p.led.asg_day AND k.today <= p.led.trial_end AS ok FROM p, k)
SELECT 'H4_BASE' AS case_name, 'GREEN' AS exp_status, 0 AS exp_measured, ARRAY<STRING>[] AS must, ['TOUCHED:', 'FEED STALE'] AS must_not, FALSE AS vacuous,
       'no touch of any kind, every feed stamp 1 hour old' AS what
UNION ALL SELECT 'H4_LEDGER_TODAY', 'RED', 1, [FORMAT('(%s) LEDGER on %t', p.led.unit_id, k.today)], ARRAY<STRING>[], NOT l.ok,
       FORMAT('an observed change on %s now, the readout copy censoring / publishing it', p.led.unit_id) FROM p, k, led_in l
UNION ALL SELECT 'H4_LEDGER_7D', 'RED', 1, [FORMAT('TOUCHED: %s (%s) LEDGER on %t', p.led.unit_name, p.led.unit_id, k.today)], ARRAY<STRING>[], NOT l.ok,
       'the same change read 7 LA days later' FROM p, k, led_in l
UNION ALL SELECT 'H4_LEDGER_8D', 'AMBER', 0, [FORMAT('touched more than 7 LA days ago (AMBER): %s (%s) LEDGER on %t', p.led.unit_name, p.led.unit_id, k.today)],
       ['TOUCHED:'], NOT l.ok, 'the same change read 8 LA days later' FROM p, k, led_in l
UNION ALL SELECT 'H4_NEW_KEYWORD', 'RED', 1,
       [FORMAT('(%s) NEW_ENTITY on %t: keyword or target ht2-acceptance-new-keyword created', p.kw.unit_id, k.today), 'not censored by R9'],
       ARRAY<STRING>[], p.kw.unit_id IS NULL, 'a keyword created on a founding control now' FROM p, k
UNION ALL SELECT 'H4_NEW_KEYWORD_BEFORE', 'GREEN', 0, ARRAY<STRING>[], ['TOUCHED:'], p.kw.unit_id IS NULL,
       'the same keyword created the day before the assignment' FROM p
UNION ALL SELECT 'H4_NEW_AD_GROUP', 'RED', 1,
       [FORMAT('(%s) NEW_ENTITY on %t: ad group ht2-acceptance-new-ad-group created', p.kw.unit_id, k.today), 'not censored by R9'],
       ARRAY<STRING>[], p.kw.unit_id IS NULL, 'an ad group created on a founding control now' FROM p, k
UNION ALL SELECT 'H4_PORTFOLIO', 'RED', 1,
       [FORMAT('(%s) CAMPAIGN_ATTR on %t: portfolio ', p.sp_camp.unit_id, k.today), 'not censored by R9'],
       ARRAY<STRING>[], p.sp_camp.unit_id IS NULL, 'a portfolio move on an SP control now' FROM p, k
UNION ALL SELECT 'H4_BIDDING_STRATEGY', 'RED', 1,
       [FORMAT('(%s) CAMPAIGN_ATTR on %t: bidding strategy ', p.sp_camp.unit_id, k.today), 'not censored by R9'],
       ARRAY<STRING>[], p.sp_camp.unit_id IS NULL, 'a bidding-strategy change on an SP control now' FROM p, k
UNION ALL SELECT 'H4_SB_BID_OPT', 'RED', 1,
       [FORMAT('(%s) CAMPAIGN_ATTR on %t: SB bid optimization ', p.sb_camp.unit_id, k.today), 'not censored by R9'],
       ARRAY<STRING>[], p.sb_camp.unit_id IS NULL, 'bid_optimization flipped on an SB control now' FROM p, k
UNION ALL SELECT 'H4_END_DATE', 'RED', 1,
       [FORMAT('(%s) CAMPAIGN_ATTR on %t: end date ', p.sp_ch.unit_id, k.today), FORMAT(' -> %t', DATE_ADD(k.today, INTERVAL 16 DAY)),
        'not censored by R9'],
       ARRAY<STRING>[], p.sp_ch.unit_id IS NULL, 'an end date set by hand on an SP control now, 16 days out (campaign_history)' FROM p, k
UNION ALL SELECT 'H4_SB_END_DATE', 'RED', 1,
       [FORMAT('(%s) CAMPAIGN_ATTR on %t: SB end date ', p.sb_camp.unit_id, k.today), FORMAT(' -> %t', DATE_ADD(k.today, INTERVAL 16 DAY)),
        'not censored by R9'],
       ARRAY<STRING>[], p.sb_camp.unit_id IS NULL, 'an end date set by hand on an SB control now, 16 days out (sb_campaign_history)' FROM p, k
UNION ALL SELECT 'H4_BASELINE_ALTERED', 'RED', 1,
       [FORMAT('(%s) BASELINE_DIFF date unknown: the source keeps no history: %s ', p.base_row.campaign_id, p.base_row.setting), 'not censored by R9'],
       ARRAY<STRING>[], p.base_row.campaign_id IS NULL, 'a baseline value altered (the setting differs from its value at the assignment)' FROM p
UNION ALL SELECT 'H4_BASELINE_REBASED', 'AMBER', 0,
       [FORMAT('re-baselined by Ori (AMBER): %s %s (2 rows)', p.base_row.campaign_id, p.base_row.setting)], ['TOUCHED:'],
       p.base_row.campaign_id IS NULL, 'the same, plus a later baseline row carrying a ruling' FROM p
UNION ALL SELECT 'H4_WATCHED_NO_BASELINE', 'RED', 1,
       [FORMAT('(%s) BASELINE_DIFF date unknown: the source keeps no history: SP_PLACEMENT|PLACEMENT_TOP absent -> 30', p.no_base.unit_id), 'not censored by R9'],
       ARRAY<STRING>[], p.no_base.unit_id IS NULL, 'a present PLACEMENT_TOP 30 row put on a founding SP control that has no baseline row' FROM p
UNION ALL SELECT 'H4_LATE_ARRIVAL', 'GREEN', 0,
       [FORMAT('(%s): LATE ARRIVAL (first sight)', p.late.campaign_id), 'unwatched on kind-4 settings'], ['TOUCHED:'],
       p.late.campaign_id IS NULL, 'a LATE ARRIVAL HOLDOUT row added for an SB campaign outside the trial that carries present placement rows' FROM p
UNION ALL SELECT 'H4_REMOVAL', 'RED', 1,
       [FORMAT('(%s) BASELINE_DIFF date unknown: the source keeps no history: SP_PLACEMENT|%s %d -> absent', p.removal.campaign_id, p.removal.placement, p.removal.percentage), 'not censored by R9'],
       ARRAY<STRING>[], p.removal.campaign_id IS NULL, 'a removal: one present SP row of a founding control not re-stamped (its stamp 12 h back)' FROM p
UNION ALL SELECT 'H4_REMOVAL_REBASED', 'AMBER', 0,
       [FORMAT('re-baselined by Ori (AMBER): %s SP_PLACEMENT|%s (2 rows)', p.removal.campaign_id, p.removal.placement)], ['TOUCHED:'],
       p.removal.campaign_id IS NULL, 'the same removal, plus a later baseline row with value NULL and a ruling' FROM p
UNION ALL SELECT 'H4_STALE_DROPPED', 'GREEN', 0, ARRAY<STRING>[], ['TOUCHED:'], p.n_stale_sp = 0,
       FORMAT('the %d SP rows not re-stamped by the latest sync dropped (a re-sync)', p.n_stale_sp) FROM p
UNION ALL SELECT 'H4_SB_TARGET_DELETED', 'RED', 1,
       [FORMAT('(%s) BASELINE_DIFF date unknown: the source keeps no history: SB_TARGET|%s|bid ', p.sbt.campaign_id, p.sbt.id),
        FORMAT('SB_TARGET|%s|state ', p.sbt.id), '(2 rows)', 'not censored by R9'],
       ARRAY<STRING>[], p.sbt.campaign_id IS NULL, 'a present SB product target of a founding control flagged _fivetran_deleted' FROM p
UNION ALL SELECT 'H4_NO_WATCHED_SET', 'RED', p.n_base_controls, ['unwatched on kind-4 settings'], ARRAY<STRING>[], p.n_base_controls = 0,
       FORMAT('every FOUNDING assignment_rule re-prefixed LATE ARRIVAL: every baseline row on one side only (%d controls), all %d controls named unwatched',
              p.n_base_controls, p.n_hold) FROM p
UNION ALL SELECT CONCAT('H5_PROC_', pr), 'RED', 0, ['FEED STALE (> 36 h or missing): '], ARRAY<STRING>[], FALSE,
       CONCAT('the last OK run of ', pr, ' 37 hours old')
FROM UNNEST(['SP_RECORD_OBSERVED_CHANGES', 'SP_LOAD_DIM_KEYWORD', 'SP_LOAD_DIM_CAMPAIGN', 'SP_LOAD_DIM_AD_GROUP']) AS pr
UNION ALL SELECT 'H5_PROC_MISSING', 'RED', 0, ['FEED STALE (> 36 h or missing): SP_RECORD_OBSERVED_CHANGES missing · '], ARRAY<STRING>[], FALSE,
       'no OK run of SP_RECORD_OBSERVED_CHANGES at all'
UNION ALL SELECT CONCAT('H5_TABLE_', t), 'RED', 0, ['FEED STALE (> 36 h or missing): '], ARRAY<STRING>[], FALSE,
       CONCAT('MAX(_fivetran_synced) of ', t, ' 37 hours old') FROM ft45
UNION ALL SELECT 'H5_TABLE_MISSING', 'RED', 0, ['FEED STALE (> 36 h or missing): sb_product_target missing · '], ARRAY<STRING>[], FALSE,
       'sb_product_target read empty';

-- ---- run every case: the deployed text, every source a copy ----
CREATE TEMP TABLE h45 (case_name STRING, check_name STRING, measured FLOAT64, threshold STRING, status STRING, detail STRING,
                       n_live_refs INT64);
FOR c IN (SELECT case_name FROM exp45 ORDER BY case_name) DO
  IF c33_text IS NOT NULL THEN
    SET q = (SELECT ht_replace_all(c33_text, ARRAY_AGG(STRUCT(src, dst) ORDER BY ord, src))
             FROM (SELECT src, ARRAY_AGG(dst ORDER BY IF(case_name = '*', 1, 0) LIMIT 1)[OFFSET(0)] AS dst, MIN(ord) AS ord
                   FROM repl45 WHERE case_name IN ('*', c.case_name) GROUP BY src));
    EXECUTE IMMEDIATE CONCAT('INSERT INTO h45 (case_name, check_name, measured, threshold, status, detail, n_live_refs) WITH ',
                             q, ' SELECT @case_name, *, @n_live FROM c33')
      USING c.case_name AS case_name,
            ARRAY_LENGTH(REGEXP_EXTRACT_ALL(q, r'`(?:onyga-482313|fivetran-hl)[.`]')) AS n_live;
  END IF;
END FOR;

-- ---- the result ----
WITH
p AS (SELECT * FROM pick),
x AS (
  SELECT
    p.contam_row.unit_id IS NOT NULL AS has_contam,
    p.mate_row.unit_id IS NOT NULL AS has_mate,
    p.free_unit.unit_id IS NOT NULL AS has_free,
    p.new_change.day >= p.new_change.eligible_from AS has_new,
    p.pre_row.unit_id IS NOT NULL AS has_pre_row,
    (SELECT COUNT(*) FROM pre) > 0 AS has_pre_led,
    COALESCE(p.pre_new.day >= p.pre_new.asg_day, FALSE) AS has_pre_new,
    (SELECT n_expected_censored + n_expected_pre FROM h1 WHERE copy = 'NC_EMPTY_RO') > 0 AS has_ro_rows
  FROM p
),
h AS (
  SELECT copy, v_censored_from + v_contaminated_on + v_pre_window + v_duplicate + v_alien + v_empty AS v,
         FORMAT('censored_from %d, contaminated_on %d, pre_window_change_on %d, duplicate %d, alien %d, emptiness %d · %d unit(s) the rule censors, %d HOLDOUT unit(s) changed before the window, on this copy',
                v_censored_from, v_contaminated_on, v_pre_window, v_duplicate, v_alien, v_empty,
                n_expected_censored, n_expected_pre) AS d
  FROM h1
),
t AS (SELECT * FROM twin_r9),
tl AS (SELECT * FROM twin_r9 WHERE copy = 'LIVE'),
-- per copy: the vacuity suffix (a copy whose pick does not exist says so and passes)
vac AS (
  SELECT c.copy,
         CASE c.copy WHEN 'NC_DROP_ONE' THEN IF(x.has_contam, '', ' (vacuous: no contaminated unit)')
                     WHEN 'NC_LATE' THEN IF(x.has_contam, '', ' (vacuous: no contaminated unit)')
                     WHEN 'NC_DROP_MATE' THEN IF(x.has_mate, '', ' (vacuous: no censored TREATED unit)')
                     WHEN 'HC_EXTRA' THEN IF(x.has_free, '', ' (vacuous: every trial unit is censored)')
                     WHEN 'NC_NEW_CHANGE' THEN IF(x.has_new, '', ' (vacuous: no day inside a HOLDOUT window before its censoring)')
                     WHEN 'NC_PRE_DROP' THEN IF(x.has_pre_row, '', ' (vacuous: no PRE_WINDOW_CHANGE row)')
                     WHEN 'NC_PRE_LATE' THEN IF(x.has_pre_row, '', ' (vacuous: no PRE_WINDOW_CHANGE row)')
                     WHEN 'NC_NUMBER_PRE' THEN IF(x.has_pre_row, '', ' (vacuous: no PRE_WINDOW_CHANGE row)')
                     WHEN 'NC_PRE_NEW' THEN IF(x.has_pre_new, '', ' (vacuous: no HOLDOUT unit unchanged before its window with a day between its assignment and its window start)')
                     WHEN 'HC_PRE_CLEAN' THEN IF(x.has_pre_led, '', ' (vacuous: no change before the window, the copy equals LIVE)')
                     WHEN 'NC_EMPTY_RO' THEN IF(x.has_ro_rows, '', ' (vacuous: the rule censors and publishes nothing, so an empty readout misses nothing)')
                     ELSE '' END AS suffix,
         CASE c.copy WHEN 'NC_DROP_ONE' THEN NOT x.has_contam
                     WHEN 'NC_LATE' THEN NOT x.has_contam
                     WHEN 'NC_DROP_MATE' THEN NOT x.has_mate
                     WHEN 'HC_EXTRA' THEN NOT x.has_free
                     WHEN 'NC_NEW_CHANGE' THEN NOT x.has_new
                     WHEN 'NC_PRE_DROP' THEN NOT x.has_pre_row
                     WHEN 'NC_PRE_LATE' THEN NOT x.has_pre_row
                     WHEN 'NC_NUMBER_PRE' THEN NOT x.has_pre_row
                     WHEN 'NC_PRE_NEW' THEN NOT x.has_pre_new
                     WHEN 'HC_PRE_CLEAN' THEN NOT x.has_pre_led
                     WHEN 'NC_EMPTY_RO' THEN NOT x.has_ro_rows
                     ELSE FALSE END AS is_vacuous
  FROM copies c CROSS JOIN x
),
-- H4 / H5: each case against its expectation; the stale clause of an H5 case must name exactly its source
hx AS (
  SELECT e.case_name, e.exp_status, e.exp_measured, e.vacuous, e.what, r.status, r.measured, r.detail, r.n_live_refs,
         REGEXP_EXTRACT(r.detail, r'FEED STALE \(> 36 h or missing\): (.*?) · ') AS stale_clause,
         (SELECT COUNTIF(STRPOS(IFNULL(r.detail, ''), m) = 0) FROM UNNEST(e.must) m) AS n_must_missing,
         (SELECT COUNTIF(STRPOS(IFNULL(r.detail, ''), m) > 0) FROM UNNEST(e.must_not) m) AS n_must_not_present,
         ARRAY_LENGTH(REGEXP_EXTRACT_ALL(IFNULL(r.detail, ''), r'\): LATE ARRIVAL')) AS n_unwatched_named,
         (SELECT n_hold FROM pick45) AS n_hold
  FROM exp45 e LEFT JOIN h45 r USING (case_name)
),
hx_ok AS (
  SELECT *,
         CASE
           WHEN vacuous THEN TRUE
           WHEN status IS NULL THEN FALSE
           ELSE status = exp_status AND measured = exp_measured AND n_must_missing = 0 AND n_must_not_present = 0
                AND n_live_refs = 0
                AND CASE
                      WHEN case_name = 'H4_NO_WATCHED_SET' THEN n_unwatched_named = n_hold
                      WHEN STARTS_WITH(case_name, 'H5_PROC_') AND case_name != 'H5_PROC_MISSING'
                        THEN REGEXP_CONTAINS(IFNULL(stale_clause, ''), CONCAT(r'^', SUBSTR(case_name, 9), r' \d+\.\d h$'))
                      WHEN STARTS_WITH(case_name, 'H5_TABLE_') AND case_name != 'H5_TABLE_MISSING'
                        THEN REGEXP_CONTAINS(IFNULL(stale_clause, ''), CONCAT(r'^', SUBSTR(case_name, 10), r' \d+\.\d h$'))
                      WHEN case_name IN ('H5_PROC_MISSING', 'H5_TABLE_MISSING')
                        THEN stale_clause IN ('SP_RECORD_OBSERVED_CHANGES missing', 'sb_product_target missing')
                      ELSE TRUE END
         END AS ok
  FROM hx
),
res AS (
  -- H1
  SELECT 'H1_LIVE every censoring the rule makes is a CENSORED row, every HOLDOUT unit changed before its window is a PRE_WINDOW_CHANGE row, and nothing else is' AS check_name,
         'violations 0' AS expected, CAST(h.v AS STRING) AS measured, h.v = 0 AS ok, h.d AS detail
  FROM h WHERE copy = 'LIVE'
  UNION ALL
  SELECT FORMAT('H1_%s %s%s', h.copy, IF(h.copy = 'HC_PRE_CLEAN', 'holds', 'fires'), v.suffix),
         IF(h.copy = 'HC_PRE_CLEAN', 'violations 0', 'violations >= 1'), CAST(h.v AS STRING),
         IF(h.copy = 'HC_PRE_CLEAN', h.v = 0, h.v >= 1) OR (v.is_vacuous AND h.copy != 'NC_EMPTY_RO'),
         h.d
  FROM h JOIN vac v USING (copy) WHERE h.copy NOT IN ('LIVE', 'NC_NUMBER', 'NC_NUMBER_PRE')
  UNION ALL
  -- H2 (R9's part of the board: the NOT CENSORED / NOT PUBLISHED clauses; the touch alarm is H4)
  SELECT 'H2a the deployed board row holdout_unit_changed: one row, and R9 holds on it (no NOT CENSORED / NOT PUBLISHED clause)',
         'one row, R9 part 0',
         COALESCE((SELECT FORMAT('%d row(s), %s, measured %g, R9 part %d', COUNT(*), MAX(status), MAX(measured),
                                 MAX(ARRAY_LENGTH(REGEXP_EXTRACT_ALL(detail, r'its stratum changed on \d{4}-\d{2}-\d{2}, the readout censors it '))
                                     + ARRAY_LENGTH(REGEXP_EXTRACT_ALL(detail, r'before its window start, the readout publishes it '))))
                   FROM board), 'none'),
         (SELECT COUNT(*) = 1
                 AND LOGICAL_AND(ARRAY_LENGTH(REGEXP_EXTRACT_ALL(detail, r'its stratum changed on \d{4}-\d{2}-\d{2}, the readout censors it '))
                                 + ARRAY_LENGTH(REGEXP_EXTRACT_ALL(detail, r'before its window start, the readout publishes it ')) = 0)
          FROM board),
         COALESCE((SELECT MAX(detail) FROM board), 'no row')
  UNION ALL
  SELECT 'H2b the pasted hu_gap .. c33 text on the live inputs equals the deployed row (measured, status, threshold, detail with the feed ages masked)',
         'equal',
         IF(COUNT(*) = 1 AND LOGICAL_AND(b.measured = t.measured AND b.status = t.status AND b.threshold = t.threshold
                                          AND REGEXP_REPLACE(b.detail, r'\d+\.\d+', '#') = REGEXP_REPLACE(t.detail, r'\d+\.\d+', '#')),
            'equal', 'different'),
         COUNT(*) = 1 AND LOGICAL_AND(b.measured = t.measured AND b.status = t.status AND b.threshold = t.threshold
                                      AND REGEXP_REPLACE(b.detail, r'\d+\.\d+', '#') = REGEXP_REPLACE(t.detail, r'\d+\.\d+', '#')),
         ANY_VALUE(t.detail)
  FROM board b JOIN t ON t.copy = 'LIVE'
  UNION ALL
  SELECT FORMAT('H2_%s %s%s', t.copy,
                CASE t.copy WHEN 'HC_EXTRA' THEN 'holds (the board counts what is NOT censored; equals LIVE)'
                            WHEN 'HC_PRE_CLEAN' THEN 'holds (no change before the window, nothing published)'
                            WHEN 'LIVE' THEN 'holds' ELSE 'fires' END,
                v.suffix),
         CASE t.copy WHEN 'LIVE' THEN 'R9 part 0'
                     WHEN 'HC_EXTRA' THEN 'R9 part 0, status and measured = LIVE'
                     WHEN 'HC_PRE_CLEAN' THEN 'R9 part 0, no published-not-censored clause'
                     WHEN 'NC_NEW_CHANGE' THEN 'RED, R9 part >= 1'
                     WHEN 'NC_EMPTY_RO' THEN 'RED, R9 part = the units the rule censors + the HOLDOUT units changed before the window'
                     WHEN 'NC_NO_HOLDOUT' THEN 'RED (no HOLDOUT unit)'
                     WHEN 'NC_NO_OBSERVED' THEN 'RED (observed ledger empty)'
                     ELSE 'RED, R9 part 1' END,
         FORMAT('%s, measured %g, R9 part %d', t.status, t.measured, t.r9),
         CASE t.copy WHEN 'LIVE' THEN t.r9 = 0
                     WHEN 'HC_EXTRA' THEN (t.r9 = 0 AND t.status = tl.status AND t.measured = tl.measured) OR v.is_vacuous
                     WHEN 'HC_PRE_CLEAN' THEN (t.r9 = 0 AND STRPOS(t.detail, 'published, not censored') = 0) OR v.is_vacuous
                     WHEN 'NC_NEW_CHANGE' THEN (t.status = 'RED' AND t.r9 >= 1) OR v.is_vacuous
                     WHEN 'NC_EMPTY_RO' THEN (t.status = 'RED'
                                              AND t.r9 = (SELECT n_expected_censored + n_expected_pre FROM h1 WHERE copy = 'NC_EMPTY_RO'))
                                             OR (v.is_vacuous AND t.r9 = 0)
                     WHEN 'NC_NO_HOLDOUT' THEN t.status = 'RED' AND STARTS_WITH(t.detail, 'no HOLDOUT unit read')
                     WHEN 'NC_NO_OBSERVED' THEN t.status = 'RED' AND STARTS_WITH(t.detail, 'the observed-change ledger is empty')
                     ELSE (t.status = 'RED' AND t.r9 = 1) OR v.is_vacuous END,
         t.detail
  FROM t JOIN vac v USING (copy) CROSS JOIN tl
  UNION ALL
  -- H3
  SELECT FORMAT('H3_LIVE the gate holds: one NOT_YET row before the live trial\'s first_readout (%s), no READY row, no number on any row',
                IFNULL((SELECT CAST(MAX(first_readout) AS STRING) FROM trial_row), 'none: no live trial')),
         'violations 0', CAST(v_gate AS STRING), v_gate = 0,
         FORMAT('%d CENSORED row(s), %d PRE_WINDOW_CHANGE row(s), %d estimate row(s)',
                (SELECT COUNTIF(state = 'CENSORED') FROM ro), (SELECT COUNTIF(state = 'PRE_WINDOW_CHANGE') FROM ro),
                (SELECT COUNTIF(state NOT IN ('CENSORED', 'PRE_WINDOW_CHANGE')) FROM ro))
  FROM h3 WHERE copy = 'LIVE'
  UNION ALL
  SELECT 'H3_NC_NUMBER fires (a number on a CENSORED row, or on the NOT_YET row when no row is CENSORED)', 'violations >= 1',
         CAST(v_gate AS STRING), v_gate >= 1,
         IF((SELECT COUNTIF(state = 'CENSORED') FROM ro) > 0, 'holdout_n set on one CENSORED row', 'holdout_n set on the NOT_YET row')
  FROM h3 WHERE copy = 'NC_NUMBER'
  UNION ALL
  SELECT CONCAT('H3_NC_NUMBER_PRE fires (a PRE_WINDOW_CHANGE row carrying a number)', v.suffix), 'violations >= 1',
         CAST(h3.v_gate AS STRING), h3.v_gate >= 1 OR v.is_vacuous, 'holdout_n set on one PRE_WINDOW_CHANGE row'
  FROM h3 JOIN vac v USING (copy) WHERE h3.copy = 'NC_NUMBER_PRE'
  UNION ALL
  -- H4 / H5
  SELECT 'H45_TEXT the deployed c33 text was found (hu_trial .. c33) and every case ran it with no live source left in it',
         'found, every case run, 0 live references',
         FORMAT('%s, %d of %d cases run, %d live reference(s)', IF(c33_text IS NULL, 'NOT FOUND', FORMAT('%d characters', LENGTH(c33_text))),
                (SELECT COUNT(*) FROM h45), (SELECT COUNT(*) FROM exp45), (SELECT IFNULL(SUM(n_live_refs), 0) FROM h45)),
         c33_text IS NOT NULL AND (SELECT COUNT(*) FROM h45) = (SELECT COUNT(*) FROM exp45)
           AND (SELECT IFNULL(SUM(n_live_refs), 0) FROM h45) = 0,
         'V_ENGINE_HEALTH view_definition from INFORMATION_SCHEMA.VIEWS; sources replaced: the registry view, the assignment, both change-log sources, the readout, DIM_KEYWORD, DIM_AD_GROUP, DIM_CAMPAIGN, sb_campaign_history, the four kind-4 tables, DE_HOLDOUT_BASELINE, LOG_PIPELINE_RUNS and the eleven feed-age reads'
  UNION ALL
  SELECT FORMAT('%s %s%s', case_name, what, IF(vacuous, ' (vacuous: no such control or row in the copies)', '')),
         FORMAT('%s, %d', exp_status, exp_measured),
         FORMAT('%s, %s%s', IFNULL(status, 'not run'), IFNULL(CAST(measured AS STRING), '-'),
                IF(STARTS_WITH(case_name, 'H5_'), CONCAT(' · stale: ', IFNULL(stale_clause, 'none')), '')),
         ok, IFNULL(detail, 'no row')
  FROM hx_ok
  UNION ALL
  SELECT 'H5_LIVE the deployed board row reads no feed stamp older than 36 h or missing',
         'no FEED STALE clause',
         COALESCE((SELECT IFNULL(REGEXP_EXTRACT(MAX(detail), r'FEED STALE \(> 36 h or missing\): (.*?) · '), 'none') FROM board), 'no row'),
         (SELECT COUNT(*) = 1 AND LOGICAL_AND(STRPOS(detail, 'FEED STALE') = 0) FROM board),
         COALESCE((SELECT REGEXP_EXTRACT(MAX(detail), r'feed ages \(h\): (.*?) · not seen by any source') FROM board), 'no row')
)
SELECT check_name, expected, measured, IF(ok, 'PASS', 'FAIL') AS result, detail
FROM res
ORDER BY check_name;
