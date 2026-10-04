#!/usr/bin/env bash
# =============================================================================================
# 2026-10-05 — HOLDOUT TRIAL 2: THE DEPLOY RUNBOOK (plan docs/superpowers/plans/2026-10-03-holdout-restart.md,
# Task 8 as rewritten 2026-10-04; this script is Task R). Ori's OK of 2026-10-04: "ok seed 5, deploy it".
# Rollback: 2026-10-05_holdout_t2_rollback.sh. Helpers: 2026-10-05_holdout_t2_lib.sh, _sqltool.py.
#
# RUN IT from the repo root of the MERGED checkout (holdout-t2 merged; the script cds to the git top level),
# under bash, with bq authenticated on onyga-482313. It runs for about 30 minutes; an agent should start it
# in the background and read its log (.tmp/holdout_t2_deploy_<time>/run.log).
#
#   --check          guards and drift only. Writes nothing in BigQuery. Exit 0 = the deploy could start now.
#   --deploy         preflight, drift, then steps 1-5; stops at the first violation, refusal or error.
#   --from-step N    resume at step N (with --deploy, the default, or with --rehearse). Every step is
#                    re-runnable: it skips what an earlier run already wrote and re-checks it.
#   --to-step N      stop after step N (default 5); a later run continues with --from-step N+1.
#   --rehearse       every write goes to OI.TMP_HT2_R_<name> (sed on the SQL text; CURRENT_DATE('America/
#                    Los_Angeles') pinned to 2026-10-05); reads of every other live object are kept; the date and
#                    window guards are measured and printed but not enforced. Without --from-step it first
#                    makes fresh copies (the live assignment table, and the seven replaced objects from their
#                    live DDL); with --from-step it resumes on the copies already there.
#   --rehearse-drop  drops every OI.TMP_HT2_R_* object (views with DROP VIEW, tables, procedures).
#   --post-pass      K8, K9b (after the first pass gated for trial 2), K9 (after pass 1 of 2026-10-06),
#                    K2-K4 (after the first pass that ran SP_ASSIGN_HOLDOUT) and K13. Read-only.
#   --base REF       the pre-branch version of every replaced file (default: per file, the parent of the first
#                    commit in 53326a5..holdout-t2 that touched it; = 53326a5 for all seven today). Only when the
#                    base branch edited AND deployed a replaced object after the cut, whether HEAD or holdout-t2
#                    carries that edit by a merge (FOREIGN EDITS and MERGES below).
#   --tip REF        the holdout-t2 tip that must be merged into HEAD, and whose text the deploy sends (default
#                    holdout-t2).
#   --book-branch B  the branch the books are built from (default feat/campaign-first-strategy, the
#                    /Users/ori/Develop/OI checkout). It must contain --tip (BOOK BRANCH below).
#
# ---------------------------------------------------------------------------------------------
# THE WINDOW (plan Task 8). Los Angeles date 2026-10-05 (BigQuery's CURRENT_DATE('America/Los_Angeles')),
# and the UTC time inside one of:
#   PRIMARY   from the moment pass 2 of 10-05 (starts ~07:35 UTC) has FINISHED, to 15:40 UTC;
#   FALLBACK  from the moment pass 3 of 10-05 (starts ~16:00 UTC) has FINISHED, to 04:40 UTC 10-06.
# and no pass running. Every step re-reads this before its writes and needs the time of ITSELF AND EVERY LATER
# STEP left (STEP_NEED, steps 1-5: 5, 5, 5, 10, 5 minutes; so step 1 needs 30, step 2 25, step 3 20, step 4 15,
# step 5 5), whatever --to-step says. Measured: all writes of steps 1-5 took 6.3 min in the rehearsal (step 1's
# guard 09:05:44 to step 5's writes 09:12:01). So the window cannot stop a run between step 2 and step 5 (review
# of holdout-t2, 2026-10-04: with each step's own need only, a fallback start at ~04:30 UTC 10-06 passed steps
# 1-3 and refused step 4, with no window left to resume in). A step that cannot start stops the run with the
# --from-step to resume with. Missing both windows shifts every trial-2 date and trial 1's ARCHIVED date
# together before step 1 (plan Task 0) — this script does not do that.
#
# WHAT A PASS IS, MEASURED (LOG_PIPELINE_RUNS, 2026-09-20 16:00 .. 2026-10-04 08:36 UTC, 42 passes; and the
# deployed SP_ORCHESTRATE_DAILY_REFRESH, last altered 2026-10-03 22:47 UTC):
#   - a pass is one CALL of SP_ORCHESTRATE_DAILY_REFRESH (a scheduled query at ~05:00, ~07:35 and ~16:00
#     UTC). It draws run_id = GENERATE_UUID() once and logs ONE ROW PER STEP, with that run_id, when the
#     step ENDS (OK, or FAIL from its EXCEPTION handler; a failing step does not stop the pass). No row is
#     written when a step starts, so a step in progress is invisible in the log;
#   - its first step is SP_SRC_ACC_PRODUCTS (42 of 42 passes; the row lands 11-25 s after the start);
#   - its last step is SP_SNAPSHOT_ENGINE_HEALTH in every pass since it was added (4 of 4, 2026-10-03 07:35
#     .. 2026-10-04 07:35; SP_REFRESH_CUBE_TABLES was last in the 38 before). After that row the procedure
#     only SELECTs a summary: the scheduled job ended 2 s after it (JOBS_BY_PROJECT, 5 of 5 on 10-03/04);
#   - between one step's row and the next step's start: at most 1.5 min; a single step ran up to 362 min
#     (SP_SNAPSHOT_ENGINE_PROPOSALS, 2026-09-24), so silence in the log never means a pass has ended;
#   - passes ran 41-75 min, the slowest 7 h (09-24 16:00 .. 22:59).
# So, in this script (pass_guard, sqltool guard):
#   pass N of 10-05 has STARTED   = a run_id whose first-step row started in its UTC slot (pass 2:
#                                   07:00-12:00, pass 3: 12:00-24:00 of 10-05);
#   it has FINISHED               = that run_id has logged its last step;
#   a pass is RUNNING             = a run_id of the last 36 h logged its first step and not its last
#                                   (a pass that died also reads RUNNING: confirm with JOBS_BY_PROJECT and
#                                   re-measure), OR JOBS_BY_PROJECT holds a job not DONE whose query is
#                                   CALL SP_ORCHESTRATE_DAILY_REFRESH;
#   first / last step are read from the deployed orchestrator body each time (its SET procedure_name
#   lines); if they are no longer SP_SRC_ACC_PRODUCTS / SP_SNAPSHOT_ENGINE_HEALTH the guard refuses.
# The ~25 s between a scheduled start and its first row are covered by the window bounds: no pass is
# scheduled between 07:35 and 15:40 or between 16:00 and 04:40.
#
# ---------------------------------------------------------------------------------------------
# THE ORDER (plan Task 8; review fix 3). Each step stops on any violation > 0, and every object it writes
# is re-read from INFORMATION_SCHEMA after the write and compared with the file (bodies with comments and
# whitespace removed; tables by their columns).
#   preflight  config.yaml parses; HEAD contains the holdout-t2 tip and no deployed file has an uncommitted
#              change (deploy mode); BOOK BRANCH: the book branch contains the tip and its checkout's four
#              tools are its committed text (below); FOREIGN EDITS: every file the deploy sends is the tip's text, and MERGES:
#              no merge into the tip carries a base-branch edit to one of them that is not proven deployed (below);
#              the presence-rule block of c33 = the baseline file's = K12's; the HOLDOUT_INTEGRITY paste =
#              c33's text; the 10-04 change-log rows on the 12 controls (INFO, plan Task 8 "one caution");
#              every PENDING_UPLOAD change-log row on the 12 controls, any batch prefix, any build date
#              (STOP; UPLOAD RULE below); DRIFT of all seven replaced objects (below).
#   step 1     DE_HOLDOUT_TRIAL, DE_HOLDOUT_BASELINE (tables), V_HOLDOUT_TRIAL, V_HOLDOUT_ARM, the registry
#              rows. K1, K2.
#   step 2     the founding file (59 rows), then the baseline file. K3, K4, K5, K6, K12.
#   step 3     SP_ASSIGN_HOLDOUT, THEN V_HOLDOUT_ELIGIBLE (the reverse order lets the old procedure append
#              the 5 Bunny campaigns to trial 1 for good). K2, K3, K4 again; INFO: the eligible campaigns
#              outside trial 2 (what the next pass would append as LATE ARRIVALs).
#   step 4     the register suite's pre-deploy baseline (merge-base text on the old register), then
#              SP_ENGINE_PREFLIGHT, V_PLAN_WINDOW_JUDGMENT, V_FAMILY_SEAT_REGISTER. K7 (here exactly one
#              object off its count: V_ENGINE_HEALTH 3, expected 1, until step 5), K7b (the four tools as
#              committed on the book branch, and the weekly book's MEND_SQL there: one V_HOLDOUT_ARM reference).
#   step 5     V_HOLDOUT_READOUT, V_ENGINE_HEALTH. K7 (all on count), K7b, K10, K11, K13 (the weekly book's mend
#              on the trial's controls, its gate read as of LA 10-06: 0); HOLDOUT_INTEGRITY
#              (every row PASS; ~18 min); V_FAMILY_SEAT_REGISTER_acceptance (no check that passed before
#              the deploy fails after it, and B09 / B34, the holdout checks, PASS).
# Safe stopping points: after step 1; after step 2, 3 or 4 ONLY IF a resume reaches step 5 before pass 2 of
# 2026-10-06 starts (~07:35 UTC, the first pass on LA 10-06). Between steps 2 and 3 the old readers see trial
# 2's rows but its eligible_from (10-06) has not come; between 3 and 4 the procedure and the population already
# follow trial 2. From LA 10-06 the OLD SP_ENGINE_PREFLIGHT, V_PLAN_WINDOW_JUDGMENT and V_FAMILY_SEAT_REGISTER
# hold both trials' controls (26, the rollback header's measurement), and 10 of trial 1's 14 controls are trial-2
# TREATED units: trial 2's TREATED arm would be held from its first day. Its dates cannot be shifted after step 2
# (the assignment table is append-only), and the rollback does not cure it (it restores those same old readers).
# So after a stop past step 2 (an error or a violation; the summed need keeps the window from causing one): fix
# it and resume with --from-step N inside the window. After 04:40 UTC 10-06 the guard refuses every step; the
# only resume left is GUARD_OPTS=--running-only (it refuses while a pass runs and skips the date and window
# checks) once pass 1 of 10-06 has logged its last step and before 07:35 UTC, on Ori's ruling.
# No pass may run inside a step (the window).
#
# DRIFT. Before replacing each of SP_ASSIGN_HOLDOUT, V_HOLDOUT_ELIGIBLE, SP_ENGINE_PREFLIGHT,
# V_PLAN_WINDOW_JUDGMENT, V_FAMILY_SEAT_REGISTER, V_HOLDOUT_READOUT, V_ENGINE_HEALTH the script reads its
# deployed DDL (INFORMATION_SCHEMA ddl), and compares its body with the file's pre-branch version (--base),
# comments and whitespace removed. Equal: the DDL is saved to .tmp/holdout_t2_predeploy/<name>.ddl.sql
# (never overwritten; the rollback restores from there) and the object is replaced. Equal to this deploy's
# file: already replaced by an earlier run, skipped. Anything else: STOP, printing the difference. If the
# base branch changed one of these objects after holdout-t2 was cut, deployed that change and a merge
# carries it, re-run with --base <the merged base-branch commit, or a later one>.
#
# FOREIGN EDITS (review of Task R, 2026-10-04). Drift proves only that the deployed body is the pre-branch
# file; the deploy sends HEAD's file, and HEAD is the merged checkout, where other sessions commit. A
# base-branch commit to one of these files that was never deployed would read "= <pre-branch> (not yet
# replaced)" and ship with this deploy. So preflight (git only, before any BigQuery read) requires, for the
# 7 new-object and migration files and the 7 replaced objects' files:
#   without --base   git diff --quiet <tip> HEAD -- FILE, for all 14;
#   with --base B    a replaced object's file at HEAD = the clean three-way merge (git merge-file, histogram
#                    or myers) of the tip's file and B's file over their merge base: B's text, which drift
#                    then requires deployed, plus the tip's edit and nothing else. The 7 new-object and
#                    migration files must still equal the tip's (no deployed body vouches for an edit to them).
# Otherwise it prints the foreign diff and STOPs (--deploy), REFUSEs (--check) or warns (--rehearse). The
# remedy is to take the edit out of HEAD, or to make it on holdout-t2 by its own reviewed commit, or --base when
# the base branch's edit is proven deployed. Merging the base branch into holdout-t2 is NOT a remedy: it only
# moves the edit into the tip, where MERGES (next) refuses it unless that edit is proven deployed.
#
# MERGES (review of d2c8df1, 2026-10-04). The check above compares HEAD with the tip, so it cannot see a
# base-branch edit E that holdout-t2 itself merged in (the brief's workflow when a later fix touches a file with
# newer base commits): HEAD's file = the tip's, which carries E. Drift cannot see it either: base_ref_for's
# pre-branch text is the parent of the oldest commit in 53326a5..holdout-t2 that touched the file, which predates
# E, so the deployed pre-E body reads "(not yet replaced)" and E ships unproven. So preflight (git only) lists
# the first-parent merges of the tip (git rev-list --first-parent --merges 53326a5..<tip>) and, for each merge M
# whose result differs from M^1 in one of the 14 files (git diff --quiet M^1 M -- FILES fails), refuses:
#   without --base   always (STOP / REFUSE / warn, as above), printing M's diff on those files;
#   with --base B    unless every merged-in parent (M^2, ...) is an ancestor of B (git merge-base
#                    --is-ancestor). Then the tip already holds B's ancestors' text, FOREIGN EDITS' merge base is
#                    B itself (or the tip's last merged base commit when B is later), so HEAD must be the tip's
#                    text plus B's later edits, and drift requires B's text, E included, deployed.
#   always           when M changed one of the 7 new-object or migration files: no deployed body vouches for it.
#
# BOOK BRANCH (review of 648f201, MUST_FIX 3). The books are built in /Users/ori/Develop/OI, on
# feat/campaign-first-strategy, not in the checkout this runbook runs in. A run from the holdout-t2 worktree
# passed K7b and K13 on the worktree's tools while the book checkout held 53326a5's: a hold CTE of
# MIN(eligible_from) over every trial with no end (trial 1's 14 controls held for good, 10 of them trial-2
# TREATED units) and a mend with no holdout gate (5 trims on 3 trial-2 controls, measured 10-04). Every check
# read 0 while both arms were contaminated from 10-06. So preflight and --post-pass (git only, before any
# BigQuery read) require: git merge-base --is-ancestor <tip> <book-branch>; and, in every worktree that has the
# book branch checked out, the four tools = the branch's committed text (git diff --quiet <book-branch> --).
# K7b and K13 read the four tools as committed on the book branch (git show), never this working tree.
# --deploy / --post-pass STOP, --check REFUSEs, --rehearse warns and reads the tip's committed tools.
# WHERE THE MERGE HAPPENS: in /Users/ori/Develop/OI itself, `git merge --no-ff holdout-t2` on
# feat/campaign-first-strategy, then run this runbook there. Git refuses ("local changes would be
# overwritten") when a file the merge touches is uncommitted in that checkout, as config.yaml was on 10-04:
# coordinate with that session to commit it first. Never move the branch ref from another worktree (git
# update-ref / branch -f): that checkout would keep the old tools in its working tree as uncommitted reverts
# and build books from them (the worktree check above refuses that state). Equivalent: merge in a clean scratch
# worktree on a detached HEAD, then `git merge --ff-only <that commit>` in /Users/ori/Develop/OI.
# Read 2026-10-04 ~14:30 UTC: feat/campaign-first-strategy = 31e08fd, 4 commits past 53326a5 (config.yaml and
# learning files, none of the files this deploy sends); `git merge-tree --write-tree feat/campaign-first-strategy
# holdout-t2` merges clean; the main checkout's uncommitted files (8, supply/plan pages, app.py,
# deploy_all.sh, a spec) are none of holdout-t2's, config.yaml is clean there now.
#
# UPLOAD RULE (review of 648f201, MUST_FIX 1). A book built before step 4 is never uploaded after LA
# 2026-10-04: it is discarded and rebuilt after K9 and K13 read 0. It was built by the old code, which holds
# trial 1's controls and not trial 2's, and nothing else catches it before upload (c18 counts only
# seat_moves_ / reprice_book_ rows built between gate_from and gate_to; weekly_book_ batches never; c33 fires
# only after Amazon syncs the change). So preflight lists every PENDING_UPLOAD change-log row on the 12
# controls (any batch prefix, any build date) and STOPs (--check: REFUSE; --rehearse: WARNING) until each
# batch is either marked uploaded (it went up on or before LA 10-04: the building tool's --mark-uploaded) or
# labelled SUPERSEDED_NEVER_UPLOADED (python3 tools/build_seat_moves_bulksheet.py --supersede BATCH, any
# prefix). --post-pass repeats it on every V_HOLDOUT_ARM campaign.
# THE DO PAGE (MUST_FIX 2). DoPage.exportBulksheet holds every queued item on a V_HOLDOUT_ARM campaign (cube
# HoldoutArm, fail closed). It ships with the next dashboard + cube deploy, AFTER step 1 (the view must exist;
# before it does the hold refuses every item on an existing campaign). Until it is live, nothing is queued on
# the 12 campaigns from the Do page or the Weekly Run page (V_WEEKLY_RUN_* carry no holdout logic).
#
# AFTER THE RUN (plan Task 8, Task 9). K8 and K9b pass only after the next pass (pass 3 of 10-05 in the
# primary window, pass 1 of 10-06 in the fallback); K9 only after pass 1 of 10-06 (~05:30 UTC): run
# --post-pass then (it also runs K13 on the book branch's mend and the PENDING_UPLOAD check). No upload on
# 10-05; no book built before step 4 uploaded after LA 10-04 (UPLOAD RULE); no book from
# tools/build_weekly_book.py until K9 and K13 read 0 AND the Los Angeles date is 10-06 (07:00 UTC 10-06): every
# tool's gate, the mend's included, binds trial 2's own controls from CURRENT_DATE('America/Los_Angeles') >=
# 2026-10-06, and K9 can pass at ~22:30 LA 10-05; books only from the book branch; nothing queued on the 12
# from the Do page or Weekly Run until the Do page's hold is live; no hand change to the 12 controls.
# HOLDOUT.md §9 becomes "running" on 10-06 (Task 9).
#
# ---------------------------------------------------------------------------------------------
# REHEARSED 2026-10-04 (UTC 09:03-09:39, LA date 2026-10-04), on OI.TMP_HT2_R_* copies with the dates pinned to
# 2026-10-05. Every copy was dropped afterwards (--rehearse-drop: 21 objects; INFORMATION_SCHEMA then held no
# TMP_HT2_ table or routine). Live objects were only read: the seven replaced objects and DE_HOLDOUT_ASSIGNMENT
# kept their last-modified times (all before 09:00 UTC 10-04) and the table its 69 rows.
#   --check, 09:40:59-09:41:31, on the committed tree (34325f0), exit 1, as it must on LA 2026-10-04:
#     preflight clean; drift 0 (all seven "= <pre-branch>:<file> (not yet replaced)"); change-log rows on the
#     12 controls since LA 10-04: 0; the window:
#       "REFUSE: the Los Angeles date is 2026-10-04, not 2026-10-05: the deploy runs on LA 2026-10-05 only"
#       "REFUSE: the primary window has not opened: it opens when pass 2 of 2026-10-05 (starts ~07:35 UTC) has
#        logged SP_SNAPSHOT_ENGINE_HEALTH (it has not started)"
#       "CHECK: the deploy may NOT start now (preflight refusals 0, drift 0, window refused). Nothing was written."
#   --rehearse, 09:03:33-09:30:35 (27 min, 86,119 slot-s in all), exit 0:
#     live drift: the seven deployed bodies equal their pre-branch files.
#     setup: the assignment copy (69 rows, all trial 1); the seven pre-images from the live DDL.
#     step 1: 2 tables (14 / 8 columns = the files), 2 views (bodies = the files), registry 3 rows. K1 0
#             ("2 trial(s), live: HOLDOUT-2026Q4-CAMPAIGN-T2"), K2 0 (69 rows, 7298956708089075507).
#     step 2: founding 59 rows; baseline 15 rows on 8 controls (SB_PLACEMENT, SB_SHOPPER_COHORT, SB_TARGET,
#             SP_PLACEMENT). K3 0, K4 0, K5 0 (index 5 the first pass, 12 controls, 21.0%), K6 0 (12 bind, all
#             trial 2), K12 0 (15 = 15 on 8 controls).
#     step 3: both replaced (drift: = pre-branch). K2-K4 0. The new procedure CALLed on the copies: trial 2 rows
#             59 -> 59 (129.3 slot-s, 16 s); K2-K4 0 again.
#     step 4: the register suite BEFORE (pre-branch text, old register): 39 checks; FAIL B04 39, B29 1, B32 2,
#             B38 1. The same four failed on the live register, pre-branch suite, at 08:46 UTC: not this deploy's.
#             Three replaced. K7 1 = "TMP_HT2_R_V_ENGINE_HEALTH 3 (expected 1)", the state expected before
#             step 5. K7b 0 / 0 / 0.
#     step 5: both replaced. K7 0, K10 0 (one NOT_YET row naming 2027-02-09), K11 0 (17 of 17 tokens; c33 GREEN
#             with 15 feed ages, 0.6-1.6 h). HOLDOUT_INTEGRITY: 69 rows, 0 FAIL (967 s, 51,110.6 slot-s, 12.8 GB).
#             The register suite AFTER: no regression, B09 and B34 PASS. B04 / B29 / B32 the same as before; B38
#             FAIL 1 -> PASS 0 (the register's inputs moved between the two reads, 20 min apart).
#     the costly reads: the register suite 15,544.5 (before) and 18,315.4 (after) slot-s, K7/K10/K11 741.5,
#     K3-K6/K12 213.5; every other statement under 130 slot-s.
#     The step-1 window reading of this run did not parse (bq's progress text was in the JSON file); fixed
#     during the run (stderr kept apart, the JSON read from its first '['), and steps 2-5 printed it.
#   --rehearse --from-step 1 --to-step 4, the resume on the same copies, 09:31-09:34, exit 0: tables and views
#     "left as is", the registry still 3 rows, founding and baseline not re-run, every replaced object "already =
#     file", the saved register baseline reused; K1-K7 0 (K7 0: the board copy was replaced by the first run).
#   negative controls (expected / measured), on the same copies:
#     the baseline file run again               ASSERT 'already has baseline rows' / fired, nothing written
#     the baseline file with no founding rows   ASSERT 'does not have its 12 founding controls' / fired
#     the baseline file, sources emptied of the 12 controls  ASSERT 'no present setting' / fired, 0 rows written
#     K12: baseline minus one row 1 / 1; one value altered 2 / 2; every row doubled 15 / 15 (duplicate keys);
#          the re-read emptied for the 12 controls 16 / 16 (15 + the emptiness term)
#     K7 before step 5: 1 / 1 (above); the drift check of a replaced copy: "= this deploy's file" (resume)
#     the window guard (sqltool guard on synthetic logs): LA 10-04 refused; pass 2 finished, 10:00 open
#     (primary, 340 min left); pass 2 running at 08:20 refused; 15:45 refused; pass 3 running at 16:30 refused;
#     pass 3 finished, 18:00 open (fallback); 04:39 10-06 open; 04:41 refused (both closed); 15:35 with 10 min
#     needed refused; an orchestrator job not DONE refused.
#     The live log read: the 2026-10-03 05:00 pass has no SP_SNAPSHOT_ENGINE_HEALTH row (that step was added in
#     the next pass); hence "running" needs a start less than 8 h ago.
#   Rollback: 2026-10-05_holdout_t2_rollback.sh --rehearse on these copies (its header).
#
# FOREIGN EDITS, measured 2026-10-04 10:04-10:09 UTC (the check added after the review of Task R). Scratch
# commits in a detached scratch worktree (never on a branch; the worktree removed afterwards). Where marked
# "stub bq", a bq first on PATH refused and logged every call: the check is git-only, so 0 calls = it stopped
# before BigQuery. No TMP_HT2_ object was made; the real-bq runs are --check (read-only).
#   a scratch commit on the tip, V_ENGINE_HEALTH.sql c10's RED threshold 262144 * 0.85 -> 0.80:
#     --check (real bq)     "FOREIGN EDIT ... differs between holdout-t2 and HEAD", the one-line diff printed,
#                           "REFUSE: 1 of the 14 files ...", while drift still read V_ENGINE_HEALTH "= 93ba2a9:...
#                           (not yet replaced)" (the gap the review found); "preflight refusals 1", exit 1
#     --deploy (stub bq)    STOP at the check, the diff printed, 0 bq calls, exit 1
#     --rehearse (stub bq)  the diff printed, "WARNING (rehearsal)", went on
#     the same commit with --base 53326a5 (= the merge base): STOP, merge-file of the tip over 53326a5 = the tip
#   a scratch commit on the tip touching only architecture/HOLDOUT.md: --deploy "foreign edits: none; the 14
#     files the deploy sends are holdout-t2's text" (stub bq: went on to its first call, the INFO read)
#   a simulated base-branch commit B on 53326a5 (the same 0.85 -> 0.80), then holdout-t2 merged into it (clean):
#     --deploy, no --base (stub bq)      STOP, B's line printed as the foreign diff, 0 bq calls
#     --deploy --base B (stub bq)        "foreign edits: none; the 7 new-object and migration files are
#                                        holdout-t2's text, the 7 replaced objects' files B's text plus
#                                        holdout-t2's edit", went on to the INFO read
#     --check --base B (real bq)         foreign edits none; drift "V_ENGINE_HEALTH: DRIFT against B" (B's edit
#                                        was never deployed), the other six "= B (not yet replaced)"; "drift 1"
#     + a post-merge commit, AMBER 262144 * 0.70 -> 0.65, --deploy --base B (stub bq): STOP, "not B's text plus
#                                        holdout-t2's edit", only that line in the diff, 0 bq calls
#     + a post-merge commit to the founding file (one row 'HOLDOUT' -> 'CONTROL'), --deploy --base B (stub bq):
#                                        STOP, that row printed, 0 bq calls
#     --base no-such-ref: STOP "--base no-such-ref is not a commit here", 0 bq calls
#   positive control: --check in this worktree, HEAD 4638d9a = holdout-t2 (this edit of the runbook uncommitted;
#   the runbook is not a file the deploy sends), 10:08:20-10:08:52: "foreign edits: none; the 14 files the deploy
#   sends are holdout-t2's text"; preflight refusals 0, drift 0 (all seven = pre-branch), change-log rows on the
#   12 controls 0, the window refused (LA 10-04), exit 1.
#
# MERGES, measured 2026-10-04 10:34-10:39 UTC (the check added after the review of d2c8df1). A `git clone
# --shared` of this worktree in the scratchpad, its remote removed, scratch commits detached, the clone's own
# holdout-t2 ref moved onto them where said, this runbook copied in uncommitted (the clone deleted afterwards).
# "stub bq" as above. No TMP_HT2_ object was made; the real-bq runs are --check (read-only).
#   B = a base commit on 53326a5 (V_FAMILY_SEAT_REGISTER kwfeed COALESCE(state, '') -> '?'); M = B merged into
#   the tip d2c8df1 (clean); holdout-t2 := M; HEAD = M. The case the review found:
#     d2c8df1's runbook, --deploy (stub bq)   "foreign edits: none; the 14 files the deploy sends are holdout-t2's
#                                             text", went on to its first bq call: the merged edit would ship
#     --deploy (stub bq)                      "FOREIGN MERGE: M ... no --base", B's line printed, STOP, 0 bq calls
#                                             (also with --tip HEAD on the tip left at d2c8df1)
#     --check (stub bq)                       "REFUSE: 1 merge(s) into holdout-t2 carry a base-branch edit ..."
#     --rehearse (stub bq)                    "WARNING (rehearsal): 1 merge(s) ...", went on
#     --check (real bq) 10:35:42-10:36:14     that REFUSE, while drift read V_FAMILY_SEAT_REGISTER "= 1d0fb90:...
#                                             (not yet replaced)" (blind to the merge); "preflight refusals 1,
#                                             drift 0", exit 1
#     --deploy --base 53326a5 (stub bq)       STOP, "its merged-in parent B is not an ancestor of --base 53326a5"
#     --deploy --base B (stub bq)             "merge M ... its merged-in parent(s) are in --base B"; "foreign
#                                             edits: none"; went on to its first bq call
#     --check --base B (real bq) 10:36:24-10:36:55  foreign edits none; "V_FAMILY_SEAT_REGISTER: DRIFT against B"
#                                             (B's kwfeed line was never deployed); "preflight refusals 0, drift 1",
#                                             exit 1. So the merged, undeployed edit stops either way.
#   B2 = a later base commit on B (V_ENGINE_HEALTH c10 AMBER 262144 * 0.70 -> 0.65), merged into M (clean);
#   holdout-t2 := that merge. No --base: STOP naming both merges. --base B: STOP (B2 is not an ancestor of B).
#   --base B2: both merges pass, foreign edits none, first bq call.
#   B3 = a base commit on B2 (SP_ENGINE_PREFLIGHT line 1), holdout-t2 merged into B3 (HEAD, clean): --base B3
#   passes; --base B2 STOP (FOREIGN EDIT: SP_ENGINE_PREFLIGHT at HEAD is not B2's text plus holdout-t2's edit);
#   no --base STOP (the file and both merges).
#   a base commit outside the 14 files (a new scratch file) merged into the tip: --deploy (stub bq) "foreign
#   edits: none; ... and no merge into holdout-t2 since 53326a5 changed them", first bq call.
#   a side commit S on the tip editing V_HOLDOUT_ARM.sql, merged --no-ff into the tip: --deploy STOP without
#   --base and with --base S ("it changed a new-object or migration file"), 0 bq calls; --check REFUSE.
#   the earlier controls re-run with this runbook: NC-A (SP_ASSIGN_HOLDOUT c_every 5 -> 4 committed on the tip)
#   --deploy STOP 0 calls, --check REFUSE, --rehearse WARNING, --base 53326a5 STOP; HEAD = the tip merged into B
#   (the earlier base path): no --base STOP 0 calls, --base B passes, --base 53326a5 STOP.
#   positive control: --check in this worktree, HEAD d2c8df1 = holdout-t2 (this edit uncommitted; the runbook is
#   not a file the deploy sends), 10:38:46-10:39:17: "foreign edits: none; the 14 files the deploy sends are
#   holdout-t2's text, and no merge into holdout-t2 since 53326a5 changed them"; preflight refusals 0, drift 0
#   (all seven = pre-branch), change-log rows on the 12 controls 0, the window refused (LA 10-04), exit 1.
#   Not covered: a base commit put on holdout-t2's first-parent line WITHOUT a merge (a rebase or cherry-pick)
#   reads as holdout-t2's own edit. The brief's workflow is a merge; review any such commit as this deploy's.
#
# REVIEW FIXES (MUST_FIX 1-3 of the adversarial panel, 2026-10-04), commit 648f201, measured 13:20-14:41 UTC.
#   1 the weekly book's mend: MEND_SQL joins V_HOLDOUT_ARM (K7b counts 1); K13 = 2026-10-05_holdout_t2_k13_mend.py.
#     On a scratch copy of the arm (OI.TMP_HT2_RV_HOLDOUT_ARM: the 12 controls, gate_from 2026-10-06; dropped):
#       as of LA 10-06: gated 0, ungated 5 trims on 3 controls (230219410635024, 271009556929636,
#       537046793426450), the reviewer's 5; as of LA 10-04 (gate not yet binding): gated 5, FAIL, as it must.
#       mend_rows() on the same copy: 30 executable trims account-wide, 0 on a control; 5 Refused rows on the
#       3 controls ("HOLDOUT: ... held from 2026-10-06 ... refused, not shipped"), tier BRAIN.
#   2 the window: STEP_NEED 5/5/5/10/5, a step needs the sum to step 5 (30/25/20/15/5 min). sqltool guard on
#     synthetic logs (pass 3 of 10-05 finished): 04:30 UTC 10-06 needing 30, 25, 20, 15 min: REFUSE (10 min
#     left); needing 5: OPEN; 04:05 needing 30: OPEN (35 min left); --running-only at 06:30 with no pass
#     running: "OK: no pass is running" (the late resume of Safe stopping points).
#   3 c33 kind 3 watches end_date (campaign_history SP, sb_campaign_history SB). Measured 2026-01-01 .. 10-04,
#     the same version-pair rule account-wide: SP 2 edits (2026-08, 2 campaigns; one on control 51727823265377,
#     end 2026-09-28 -> none on 08-09), SB 0. None of the 12 controls has an end date: the board GREEN below.
#   --rehearse, 14:13:26-14:39:40 (26 min), exit 0, on the committed tree 648f201: preflight clean (foreign
#     edits none; the HOLDOUT_INTEGRITY paste = V_ENGINE_HEALTH.sql's hu_gap .. c33 block); drift 0 (all seven
#     = pre-branch). The window lines: "needing 30 min for steps 1-5", 25, 20, 15, 5. step 1 K1 0, K2 0;
#     step 2 founding 59, baseline 15 rows on 8 controls, K3-K6 0, K12 0; step 3 both replaced, the CALL 59 ->
#     59, K2-K4 0; step 4 register BEFORE FAIL B04 39, B29 1, B32 2, B38 1 (as at 09:03), three replaced, K7 1
#     (the board, expected), K7b 0 on the four tools and MEND_SQL 1 reference; step 5 both replaced (the board
#     63,193 characters), K7 0, K10 0, K11 0 (17 of 17 tokens; c33 GREEN, 15 feed ages), K13 gated 0 / ungated
#     5 on 3 controls (the copies' arm and assignment), HOLDOUT_INTEGRITY 71 rows, 0 FAIL (944 s, 41,023.8
#     slot-s): H45_TEXT 21,685 characters, 38 of 38 cases, 0 live references; H4_END_DATE RED 1, H4_SB_END_DATE
#     RED 1, H4_SB_BID_OPT RED 1, H4_BASE GREEN 0. Register AFTER: no regression, B09 / B34 PASS, B38 1 -> 0.
#     All writes, step 1's guard 14:15:41 to step 5's last replace 14:21:42: 6.0 min.
#   --rehearse-drop 14:39:49-14:40:06: 12 TMP_HT2_R_ objects. The 10 TMP_HT2_RV_ objects an earlier reviewer
#     left (created 10:50-10:52 UTC) and this review's arm copy were dropped by hand; INFORMATION_SCHEMA then held
#     no TMP_HT2_ table or routine, none of DE_HOLDOUT_TRIAL / V_HOLDOUT_TRIAL / V_HOLDOUT_ARM /
#     DE_HOLDOUT_BASELINE, DE_HOLDOUT_ASSIGNMENT 69 rows, and the seven replaced objects kept their last-modified
#     times (all before 2026-10-04 08:00 UTC).
# =============================================================================================
set -euo pipefail

usage() { sed -n '2,/^# ----/p' "$0" | sed 's/^# \{0,1\}//' | sed -n '1,32p'; }

MODE=""
FROM_STEP=1
TO_STEP=5
FROM_GIVEN=0
BASE_OVERRIDE=""
TIP=holdout-t2
BRANCH_BASE=53326a5
BOOK_BRANCH=feat/campaign-first-strategy
while [ $# -gt 0 ]; do
  case $1 in
    --check) MODE=check ;;
    --deploy) MODE=deploy ;;
    --rehearse) MODE=rehearse ;;
    --rehearse-drop) MODE=drop ;;
    --post-pass) MODE=postpass ;;
    --from-step) FROM_STEP=${2:?--from-step needs N}; FROM_GIVEN=1; shift ;;
    --to-step) TO_STEP=${2:?--to-step needs N}; shift ;;
    --base) BASE_OVERRIDE=${2:?--base needs a ref}; shift ;;
    --tip) TIP=${2:?--tip needs a ref}; shift ;;
    --book-branch) BOOK_BRANCH=${2:?--book-branch needs a branch}; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done
if [ -z "$MODE" ] && { [ "$FROM_STEP" != 1 ] || [ "$TO_STEP" != 5 ]; }; then MODE=deploy; fi
[ -n "$MODE" ] || { usage >&2; exit 2; }
case $FROM_STEP$TO_STEP in [1-5][1-5]) ;; *) echo "--from-step and --to-step must be 1..5" >&2; exit 2 ;; esac
[ "$FROM_STEP" -le "$TO_STEP" ] || { echo "--from-step is after --to-step" >&2; exit 2; }

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
# shellcheck source=scripts/bigquery/migrations/2026-10-05_holdout_t2_lib.sh
. scripts/bigquery/migrations/2026-10-05_holdout_t2_lib.sh

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
case $MODE in
  rehearse|drop)
    PFX=$REHEARSE_PREFIX
    XF="--prefix $REHEARSE_PREFIX --pin $REHEARSE_PIN"
    PRE=.tmp/holdout_t2_rehearse/predeploy
    WORK=.tmp/holdout_t2_rehearse/run_$STAMP
    RUN_TAG=reh ;;
  *)
    PRE=.tmp/holdout_t2_predeploy
    WORK=.tmp/holdout_t2_${MODE}_$STAMP
    RUN_TAG=$MODE ;;
esac
mkdir -p "$WORK" "$PRE"
LOG=$WORK/run.log
RECORD=$WORK/checks.tsv
: > "$RECORD"
log "holdout trial 2 runbook: mode $MODE, from step $FROM_STEP, HEAD $(git rev-parse --short HEAD), log $LOG"

ACC=scripts/bigquery/tests/HOLDOUT_RESTART_acceptance.sql
HI=scripts/bigquery/tests/HOLDOUT_INTEGRITY_acceptance.sql
FSR=scripts/bigquery/tests/V_FAMILY_SEAT_REGISTER_acceptance.sql
# the text this deploy sends to BigQuery: the new objects and the migrations, then the seven replaced objects
NEW_FILES="scripts/bigquery/tables/DE_HOLDOUT_TRIAL.sql scripts/bigquery/tables/DE_HOLDOUT_BASELINE.sql
scripts/bigquery/views/V_HOLDOUT_TRIAL.sql scripts/bigquery/views/V_HOLDOUT_ARM.sql
$MIG/2026-10-05_holdout_t2_registry_rows.sql $MIG/2026-10-05_holdout_t2_founding.sql $MIG/2026-10-05_holdout_t2_baseline.sql"
REPLACED_FILES=$(for n in $REPLACED; do file_of "$n"; echo; done)
FILES="$NEW_FILES
$REPLACED_FILES
$ACC $HI $FSR $TOOL $MIG/2026-10-05_holdout_t2_lib.sh
tools/build_reprice_bulksheet.py tools/build_seasonal_unpause_bulksheet.py tools/build_seat_moves_bulksheet.py"

# base_ref_for FILE: the commit holding FILE's pre-branch version. The per-file default predates any base-branch
# edit that a merge brought into $TIP, so it is right only while no such merge changed the 14 files: preflight
# (foreign_merges) refuses one unless --base is given, and with --base this returns --base for every file.
base_ref_for() {
  local first
  if [ -n "$BASE_OVERRIDE" ]; then printf '%s' "$BASE_OVERRIDE"; return; fi
  first=$(git rev-list --reverse "$BRANCH_BASE..$TIP" -- "$1" | sed -n 1p)
  if [ -z "$first" ]; then printf '%s' "$BRANCH_BASE"; else git rev-parse --short "$first^"; fi
}

# ---------------------------------------------------------------------------------------------
# preflight
# ---------------------------------------------------------------------------------------------
preflight() {
  local f bad=0
  log "PREFLIGHT"
  for f in bq git python3; do command -v "$f" > /dev/null || die "$f not found"; done
  for f in $FILES; do [ -f "$f" ] || { log "  missing $f"; bad=1; }; done
  [ "$bad" = 0 ] || die "files missing: is this the merged checkout?"
  python3 -c "import yaml; yaml.safe_load(open('config.yaml'))" || die "config.yaml does not parse"
  log "  config.yaml parses"
  git rev-parse -q --verify "$TIP^{commit}" > /dev/null || die "--tip $TIP is not a commit here"
  git merge-base --is-ancestor "$TIP" HEAD || die "HEAD does not contain $TIP: merge holdout-t2 first"
  log "  HEAD contains $TIP ($(git rev-parse --short "$TIP"))"
  book_branch
  # shellcheck disable=SC2086
  if ! git diff --quiet HEAD -- $FILES || [ -n "$(git ls-files --others --exclude-standard -- $FILES)" ]; then
    if [ "$MODE" = deploy ] || [ "$MODE" = check ]; then
      # shellcheck disable=SC2086
      git status --short -- $FILES | sed 's/^/    /' | tee -a "$LOG" >&2
      if [ "$MODE" = deploy ]; then die "a file of the deploy is uncommitted or differs from HEAD: deploy committed text only"; fi
      log "  REFUSE: a file of the deploy is uncommitted or differs from HEAD: deploy committed text only"
      CHECK_REFUSALS=$((CHECK_REFUSALS + 1))
    else
      log "  WARNING (rehearsal): files differ from HEAD:"
      # shellcheck disable=SC2086
      git status --short -- $FILES | sed 's/^/    /' | tee -a "$LOG" >&2
    fi
  fi
  foreign_all
  # the presence rule is one text in three places (plan §2.7 kind 4)
  tool block scripts/bigquery/views/V_ENGINE_HEALTH.sql 'hu_k4_sp  AS' hu_k4_present > "$WORK/pres_board.txt"
  tool block "$MIG/2026-10-05_holdout_t2_baseline.sql" 'hu_k4_sp  AS' hu_k4_present > "$WORK/pres_baseline.txt"
  tool block "$ACC" 'hu_k4_sp  AS' hu_k4_present > "$WORK/pres_k12.txt"
  cmp -s "$WORK/pres_board.txt" "$WORK/pres_baseline.txt" && cmp -s "$WORK/pres_board.txt" "$WORK/pres_k12.txt" \
    || die "the presence-rule block differs between V_ENGINE_HEALTH.sql, the baseline file and K12"
  log "  presence rule: one text in V_ENGINE_HEALTH c33, the baseline file and K12"
  python3 - <<'PY' || die "HOLDOUT_INTEGRITY's pasted c33 block is not V_ENGINE_HEALTH.sql's"
import sys
b = lambda t: t[t.index('\nhu_gap AS ('):t.index('\n)\n', t.index('\nc33 AS (')) + 2]
v = open('scripts/bigquery/views/V_ENGINE_HEALTH.sql').read()
a = open('scripts/bigquery/tests/HOLDOUT_INTEGRITY_acceptance.sql').read()
sys.exit(0 if b(v) == b(a) else 1)
PY
  log "  HOLDOUT_INTEGRITY's hu_gap .. c33 block = V_ENGINE_HEALTH.sql's"
  upload_rows_info
}

# FOREIGN EDITS (house rule: "Before replacing a deployed object, diff its INFORMATION_SCHEMA body against the
# file. The only difference allowed is this plan's edit."). The run sends HEAD's text, and HEAD is the merged
# checkout, where other sessions commit; drift proves only deployed = the pre-branch file. So, read-only, in git:
#   without --base: every file the deploy sends (NEW_FILES, REPLACED_FILES) is the $TIP text: git diff --quiet
#                   $TIP HEAD -- FILE;
#   with --base B:  a replaced object's file at HEAD = git merge-file of $TIP's file and B's over their merge
#                   base, i.e. B's text (drift then proves B deployed) plus the tip's edit and nothing else; a
#                   new object or migration file is still the $TIP text (no deployed body vouches for an edit).
# Any other difference is printed: STOP (--deploy), REFUSE (--check), WARNING (--rehearse).
FOREIGN_MB=""
foreign_one() {   # FILE new|replaced -> 0 when HEAD's text is the reviewed text
  local f=$1 kind=$2 w=$WORK/foreign alg
  if [ -z "$BASE_OVERRIDE" ] || [ "$kind" = new ]; then
    git diff --quiet --no-ext-diff "$TIP" HEAD -- "$f" && return 0
    log "  FOREIGN EDIT: $f differs between $TIP and HEAD (git diff $TIP HEAD -- $f):"
    git diff --no-ext-diff "$TIP" HEAD -- "$f" | sed 's/^/    /' | tee -a "$LOG" >&2 || true
    return 1
  fi
  if ! { git show "$TIP:$f" > "$w.tip" && git show "$FOREIGN_MB:$f" > "$w.mb" \
         && git show "$BASE_OVERRIDE:$f" > "$w.base" && git show "HEAD:$f" > "$w.head"; }; then
    log "  FOREIGN EDIT: $f cannot be read at $TIP, $FOREIGN_MB (their merge base), $BASE_OVERRIDE and HEAD"
    return 1
  fi
  # a clean merge by either algorithm: git merge's ort strategy merges with histogram (git help
  # merge-strategies), git merge-file defaults to myers
  for alg in histogram myers; do
    git merge-file -p --diff-algorithm="$alg" "$w.tip" "$w.mb" "$w.base" > "$w.merged" 2> /dev/null || true   # rc = conflicts
    cmp -s "$w.merged" "$w.head" && return 0
  done
  log "  FOREIGN EDIT: $f at HEAD is not $BASE_OVERRIDE's text plus $TIP's edit (diff: that merge -> HEAD):"
  diff -u --label "git merge-file $TIP $FOREIGN_MB $BASE_OVERRIDE -- $f" --label "HEAD:$f" "$w.merged" "$w.head" \
    | sed 's/^/    /' | tee -a "$LOG" >&2 || true
  return 1
}

# MERGES (review of d2c8df1): a base-branch edit merged INTO $TIP passes foreign_one (HEAD's file = the tip's,
# which carries it) and drift (base_ref_for's pre-branch text predates it). So every first-parent merge M in
# $BRANCH_BASE..$TIP whose result differs from M^1 in one of the 14 files is refused, unless --base B is given
# and every merged-in parent (M^2, ...) is an ancestor of B: then foreign_one's merge base is B (or the last
# merged base commit, when B is later), and drift requires B's text, which carries the merged edit, deployed.
# A merge that changed a new-object or migration file is refused even with --base (no deployed body vouches).
FOREIGN_MERGES=0
foreign_merges() {
  local m p parents subj nchg bad merges
  FOREIGN_MERGES=0
  git merge-base --is-ancestor "$BRANCH_BASE" "$TIP" || die "$TIP does not contain the branch point $BRANCH_BASE"
  merges=$(git rev-list --first-parent --merges "$BRANCH_BASE..$TIP") || die "git rev-list --first-parent --merges $BRANCH_BASE..$TIP failed"
  for m in $merges; do
    # shellcheck disable=SC2086
    git diff --quiet --no-ext-diff "$m^1" "$m" -- $NEW_FILES $REPLACED_FILES && continue
    parents=$(git rev-list --parents -n 1 "$m" | cut -d' ' -f3-)
    subj=$(git log -1 --format=%s "$m")
    # shellcheck disable=SC2086
    nchg=$(git diff --name-only --no-ext-diff "$m^1" "$m" -- $NEW_FILES $REPLACED_FILES | wc -l | tr -d ' ')
    bad=""
    # shellcheck disable=SC2086
    if ! git diff --quiet --no-ext-diff "$m^1" "$m" -- $NEW_FILES; then
      bad="it changed a new-object or migration file, which no deployed body vouches for (refused even with --base)"
    elif [ -z "$BASE_OVERRIDE" ]; then
      bad="no --base: nothing proves the merged-in edit deployed"
    else
      for p in $parents; do
        git merge-base --is-ancestor "$p" "$BASE_OVERRIDE" \
          || bad="${bad:+$bad; }its merged-in parent $(git rev-parse --short "$p") is not an ancestor of --base $BASE_OVERRIDE"
      done
    fi
    if [ -z "$bad" ]; then
      log "  merge $(git rev-parse --short "$m") ($subj) changed $nchg of the 14 files; its merged-in parent(s) are in --base $BASE_OVERRIDE, whose text drift must find deployed"
      continue
    fi
    FOREIGN_MERGES=$((FOREIGN_MERGES + 1))
    log "  FOREIGN MERGE: $(git rev-parse --short "$m") ($subj), merged-in parent(s) $(for p in $parents; do git rev-parse --short "$p"; done | tr '\n' ' ')brought $nchg of the 14 files' edits into $TIP: $bad. Its diff on them (git diff $(git rev-parse --short "$m")^1 $(git rev-parse --short "$m") -- FILES):"
    # shellcheck disable=SC2086
    git diff --no-ext-diff "$m^1" "$m" -- $NEW_FILES $REPLACED_FILES > "$WORK/foreign_merge_$(git rev-parse --short "$m").diff" || true
    sed -n '1,200p' "$WORK/foreign_merge_$(git rev-parse --short "$m").diff" | sed 's/^/    /' | tee -a "$LOG" >&2 || true
    [ "$(wc -l < "$WORK/foreign_merge_$(git rev-parse --short "$m").diff")" -le 200 ] \
      || log "    (first 200 lines; the whole diff is $WORK/foreign_merge_$(git rev-parse --short "$m").diff)"
  done
}

foreign_all() {
  local f nf=0 nfiles nnew
  if [ -n "$BASE_OVERRIDE" ]; then
    git rev-parse -q --verify "$BASE_OVERRIDE^{commit}" > /dev/null || die "--base $BASE_OVERRIDE is not a commit here"
    FOREIGN_MB=$(git merge-base "$TIP" "$BASE_OVERRIDE") || die "$TIP and --base $BASE_OVERRIDE have no merge base"
    FOREIGN_MB=$(git rev-parse --short "$FOREIGN_MB")
  fi
  for f in $NEW_FILES; do foreign_one "$f" new || nf=$((nf + 1)); done
  for f in $REPLACED_FILES; do foreign_one "$f" replaced || nf=$((nf + 1)); done
  foreign_merges
  # shellcheck disable=SC2086
  nfiles=$(printf '%s\n' $NEW_FILES $REPLACED_FILES | wc -l | tr -d ' ')
  # shellcheck disable=SC2086
  nnew=$(printf '%s\n' $NEW_FILES | wc -l | tr -d ' ')
  if [ "$nf" = 0 ] && [ "$FOREIGN_MERGES" = 0 ]; then
    if [ -z "$BASE_OVERRIDE" ]; then
      log "  foreign edits: none; the $nfiles files the deploy sends are $TIP's text, and no merge into $TIP since $BRANCH_BASE changed them"
    else
      log "  foreign edits: none; the $nnew new-object and migration files are $TIP's text, the $((nfiles - nnew)) replaced objects' files $BASE_OVERRIDE's text plus $TIP's edit, and every merge into $TIP that changed them merged an ancestor of $BASE_OVERRIDE (drift must find $BASE_OVERRIDE's text deployed)"
    fi
    return
  fi
  case $MODE in
    deploy)
      [ "$nf" = 0 ] || log "  $nf of the $nfiles files the deploy sends carry an edit $TIP did not make (above). Take the edit out of HEAD, or make it on $TIP by its own reviewed commit; merging the base branch into $TIP is NOT a remedy (MERGES refuses a merged-in edit unless proven deployed)"
      [ "$FOREIGN_MERGES" = 0 ] || log "  $FOREIGN_MERGES merge(s) into $TIP carry a base-branch edit to the files the deploy sends that is not proven deployed (above). Merging the base branch is not a remedy for an undeployed edit: deploy from a tip without that merge"
      die "foreign edits: $nf file(s), $FOREIGN_MERGES merge(s) (above): deploy reviewed text only. If the base branch made AND deployed the edit, re-run with --base <a base-branch commit containing it and every merged-in parent>: drift then requires that commit's text deployed" ;;
    check)
      if [ "$nf" -gt 0 ]; then
        log "  REFUSE: $nf of the $nfiles files the deploy sends carry an edit $TIP did not make (above)"
        CHECK_REFUSALS=$((CHECK_REFUSALS + 1))
      fi
      if [ "$FOREIGN_MERGES" -gt 0 ]; then
        log "  REFUSE: $FOREIGN_MERGES merge(s) into $TIP carry a base-branch edit to the files the deploy sends that is not proven deployed (above)"
        CHECK_REFUSALS=$((CHECK_REFUSALS + 1))
      fi ;;
    *) [ "$nf" = 0 ] || log "  WARNING (rehearsal): $nf of the $nfiles files differ from $TIP (above)"
       [ "$FOREIGN_MERGES" = 0 ] || log "  WARNING (rehearsal): $FOREIGN_MERGES merge(s) into $TIP carry a base-branch edit not proven deployed (above)" ;;
  esac
}

# BOOK BRANCH (review of 648f201, MUST_FIX 3). Books are built from the checkout of $BOOK_BRANCH
# (/Users/ori/Develop/OI, default feat/campaign-first-strategy), not from the checkout this runbook runs in.
# A run from the holdout-t2 worktree used to pass K7b and K13 on the worktree's own tools while the book
# checkout still held 53326a5's: a hold on every trial's controls with no end (trial 1's 14, 10 of them
# trial-2 TREATED units) and a mend with no holdout gate. So (git only, before any BigQuery read):
#   - $BOOK_BRANCH must contain the $TIP tip (git merge-base --is-ancestor $TIP $BOOK_BRANCH);
#   - every worktree that has $BOOK_BRANCH checked out builds from its working tree: the four tools there
#     must equal $BOOK_BRANCH's committed text;
#   - K7b and K13 read the four tools as committed on $BOOK_BRANCH (git show), never this working tree.
# --deploy and --post-pass STOP, --check REFUSEs; --rehearse warns and reads $TIP's committed tools instead.
BOOK_TOOL_FILES="tools/build_reprice_bulksheet.py tools/build_seasonal_unpause_bulksheet.py tools/build_seat_moves_bulksheet.py tools/build_weekly_book.py"
BOOK_TOOLS=""   # $WORK/book_tools: the four tools as committed on TOOLS_REF
TOOLS_REF=""
book_branch() {
  local bad="" wt f
  git rev-parse -q --verify "$BOOK_BRANCH^{commit}" > /dev/null || die "--book-branch $BOOK_BRANCH is not a commit here"
  if ! git merge-base --is-ancestor "$TIP" "$BOOK_BRANCH"; then
    bad="$BOOK_BRANCH ($(git rev-parse --short "$BOOK_BRANCH")), the branch the books are built from, does not contain the $TIP tip ($(git rev-parse --short "$TIP")): its tools hold trial 1's controls with no end and its mend has no holdout gate. Merge $TIP into $BOOK_BRANCH first (header, BOOK BRANCH)"
  else
    while IFS= read -r wt; do
      [ -n "$wt" ] || continue
      # shellcheck disable=SC2086
      if ! git -C "$wt" diff --quiet --no-ext-diff "$BOOK_BRANCH" -- $BOOK_TOOL_FILES; then
        bad="${bad:+$bad; }the checkout $wt (on $BOOK_BRANCH) builds books from a working tree whose tools differ from $BOOK_BRANCH's committed text: $(git -C "$wt" diff --name-only --no-ext-diff "$BOOK_BRANCH" -- $BOOK_TOOL_FILES | tr '\n' ' ')"
      fi
    done <<< "$(git worktree list --porcelain | awk -v b="branch refs/heads/$BOOK_BRANCH" '/^worktree /{w=substr($0, 10)} $0 == b {print w}')"
  fi
  if [ -z "$bad" ]; then
    TOOLS_REF=$BOOK_BRANCH
    log "  book branch: $BOOK_BRANCH ($(git rev-parse --short "$BOOK_BRANCH")) contains $TIP, and its checkout's tools are its committed text; K7b and K13 read $BOOK_BRANCH's tools"
  else
    case $MODE in
      deploy|postpass) die "$bad" ;;
      check) log "  REFUSE: $bad"; CHECK_REFUSALS=$((CHECK_REFUSALS + 1)); TOOLS_REF=$BOOK_BRANCH ;;
      *) log "  WARNING (rehearsal): $bad. K7b and K13 read $TIP's committed tools instead"; TOOLS_REF=$TIP ;;
    esac
  fi
  BOOK_TOOLS=$WORK/book_tools
  mkdir -p "$BOOK_TOOLS/tools"
  for f in $BOOK_TOOL_FILES; do git show "$TOOLS_REF:$f" > "$BOOK_TOOLS/$f" || die "git show $TOOLS_REF:$f failed"; done
}

# the change-log rows on trial 2's 12 controls since LA 2026-10-04 (plan Task 8, "one caution"): INFO;
# and every PENDING_UPLOAD row on them, whatever its batch prefix and build date: STOP (plan Task 8, "a book
# built before step 4 is never uploaded after LA 10-04"; review of 648f201, MUST_FIX 1)
t2_control_ids() {
  python3 - "$MIG/2026-10-05_holdout_t2_founding.sql" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
ids = re.findall(r"\('(\d+)', '(?:[^'\\]|\\.)*', 'HOLDOUT', ", s)
assert len(ids) == 12, len(ids)
print(','.join("'%s'" % i for i in ids))
PY
}

# pending_sql CAMPAIGN_SET_SQL: PENDING_UPLOAD change-log rows on a set of campaigns, any batch, any date
pending_sql() {
  cat <<SQL
SELECT 'pending_upload_on_controls' AS check_name, IFNULL(SUM(n), 0) AS violations,
       IFNULL(STRING_AGG(FORMAT('%s: %d row(s) on %s, logged %s', batch_id, n, cids, built), ' · '
                         ORDER BY built LIMIT 40), 'none') AS detail
FROM (
  SELECT batch_id, COUNT(*) AS n, STRING_AGG(DISTINCT campaign_id ORDER BY campaign_id) AS cids,
         FORMAT_TIMESTAMP('%F %T', MIN(applied_at)) AS built
  FROM \`$PROJECT.$DS.FACT_PPC_CHANGE_LOG\`
  WHERE upload_status = 'PENDING_UPLOAD' AND campaign_id IN ($1)
  GROUP BY batch_id)
SQL
}

PENDING_REMEDY="each batch named was either uploaded on or before LA 2026-10-04 (then mark it uploaded: the tool that built it, --mark-uploaded BATCH) or must never be uploaded (label it: python3 tools/build_seat_moves_bulksheet.py --supersede BATCH; it acts on any batch prefix). A book built before step 4 is never uploaded after LA 10-04: rebuild it after K9 and K13 read 0 (plan Task 8)"

# pending_on_controls deploy|postpass: before step 1 the 12 controls of the founding file; after the deploy every
# campaign V_HOLDOUT_ARM lists (from the assignment to gate_to), whatever the row's build date
pending_on_controls() {
  local set n
  if [ "$1" = postpass ]; then set="SELECT campaign_id FROM \`$PROJECT.$DS.V_HOLDOUT_ARM\`"
  else set=$(t2_control_ids) || die "could not read the 12 controls from the founding file"; fi
  pending_sql "$set" > "$WORK/pending_$1.sql"
  q "pending_$1" "$WORK/pending_$1.sql"
  tool rows < "$WORK/pending_$1.out" | python3 -c '
import sys, json
for l in sys.stdin:
    r = json.loads(l)
    print("%s\t%s" % (r["violations"], r["detail"]))' > "$WORK/pending_$1.tsv"
  n=$(cut -f1 "$WORK/pending_$1.tsv" | head -1)
  [ -n "$n" ] || die "the PENDING_UPLOAD read returned no row"
  log "  $([ "$n" = 0 ] && echo 'ok  ' || echo FAIL) PENDING_UPLOAD change-log rows on the $([ "$1" = postpass ] && echo "V_HOLDOUT_ARM campaigns" || echo "12 controls"), any batch, any build date: $n · $(cut -f2- "$WORK/pending_$1.tsv" | head -1)"
  record "${STEP:-preflight}" "pending_upload_on_controls ($1)" "$n" "$(cut -f2- "$WORK/pending_$1.tsv" | head -1)"
  [ "$n" = 0 ] && return 0
  case $MODE in
    deploy|postpass) die "$n PENDING_UPLOAD row(s) on a control (above): $PENDING_REMEDY" ;;
    check) log "  REFUSE: $n PENDING_UPLOAD row(s) on a control (above): $PENDING_REMEDY"; CHECK_REFUSALS=$((CHECK_REFUSALS + 1)) ;;
    *) log "  WARNING (rehearsal): $n PENDING_UPLOAD row(s) on a control (above); --deploy would STOP here" ;;
  esac
}

upload_rows_info() {
  local ids
  ids=$(t2_control_ids) || die "could not read the 12 controls from the founding file"
  cat > "$WORK/upload_info.sql" <<SQL
SELECT 'upload_rows_on_t2_controls' AS check_name, COUNT(*) AS violations,
       IFNULL(STRING_AGG(FORMAT('%s %s %s %s %s (%s)', FORMAT_TIMESTAMP('%F %T', applied_at), campaign_id,
                                IFNULL(campaign_type, '?'), IFNULL(action, '?'), IFNULL(source, 'LOGGED'),
                                IFNULL(upload_status, '-')), ' · ' ORDER BY applied_at LIMIT 40), 'none') AS detail
FROM \`$PROJECT.$DS.FACT_PPC_CHANGE_LOG\`
WHERE applied_at >= TIMESTAMP('2026-10-04', 'America/Los_Angeles') AND campaign_id IN ($ids)
SQL
  q upload_info "$WORK/upload_info.sql"
  tool rows < "$WORK/upload_info.out" | python3 -c '
import sys, json
for l in sys.stdin:
    r = json.loads(l)
    print("  INFO change-log rows on the 12 controls since LA 2026-10-04: %s · %s" % (r["violations"], r["detail"]))
    print("       (an SB keyword row among them makes c33 RED on day one: expected, name it in the deploy record)")' | tee -a "$LOG"
  pending_on_controls deploy
}

# ---------------------------------------------------------------------------------------------
# drift: every replaced object against its pre-branch file (read-only)
# ---------------------------------------------------------------------------------------------
DRIFT_STATE=""
drift_one() {   # NAME -> sets DRIFT_STATE to BASE | NEW | DRIFT | MISSING
  local n=$1 f t ref
  f=$(file_of "$n"); t=$(obj "$n"); ref=$(base_ref_for "$f")
  git show "$ref:$f" > "$WORK/$n.base.raw.sql" || die "git show $ref:$f failed"
  xf "$WORK/$n.base.raw.sql" "$WORK/$n.base.sql"
  xf "$f" "$WORK/$n.new.sql" --expect "$n"
  if ! ddl_of "$t" "$WORK/$n.deployed.sql"; then DRIFT_STATE=MISSING; return; fi
  if tool same "$WORK/$n.deployed.sql" "$WORK/$n.base.sql" > "$WORK/$n.drift.txt"; then DRIFT_STATE=BASE
  elif tool same "$WORK/$n.deployed.sql" "$WORK/$n.new.sql" > /dev/null; then DRIFT_STATE=NEW
  else DRIFT_STATE=DRIFT; fi
}

drift_all() {
  local n ref ndrift=0
  log "DRIFT: each deployed body against its pre-branch file (comments and whitespace removed)"
  for n in $REPLACED; do
    drift_one "$n"
    ref=$(base_ref_for "$(file_of "$n")")
    case $DRIFT_STATE in
      BASE) log "  $(obj "$n"): = $ref:$(file_of "$n") (not yet replaced)" ;;
      NEW) log "  $(obj "$n"): = this deploy's file (already replaced by an earlier run)" ;;
      MISSING) log "  $(obj "$n"): NOT DEPLOYED"; ndrift=$((ndrift + 1)) ;;
      DRIFT) log "  $(obj "$n"): DRIFT against $ref:$(file_of "$n"):"
             sed 's/^/    /' "$WORK/$n.drift.txt" | tee -a "$LOG"
             ndrift=$((ndrift + 1)) ;;
    esac
    record drift "$n" "$DRIFT_STATE" "$ref"
  done
  DRIFT_COUNT=$ndrift
}

# ---------------------------------------------------------------------------------------------
# writers
# ---------------------------------------------------------------------------------------------
deploy_table() {   # NAME FILE
  local n=$1 f=$2 t
  t=$(obj "$n")
  xf "$f" "$WORK/$n.sql" --expect "$n" --script
  tool columns "$WORK/$n.sql" > "$WORK/$n.cols.want"
  if ddl_of "$t" "$WORK/$n.deployed.sql"; then
    columns_of "$t" "$WORK/$n.cols.have"
    diff "$WORK/$n.cols.want" "$WORK/$n.cols.have" > /dev/null \
      || { diff "$WORK/$n.cols.want" "$WORK/$n.cols.have" | sed 's/^/    /' | tee -a "$LOG"; die "$t exists with other columns than $f"; }
    log "  $t: exists with the file's $(wc -l < "$WORK/$n.cols.want" | tr -d ' ') columns (an earlier run): left as is"
    return
  fi
  q "create_$n" "$WORK/$n.sql"
  columns_of "$t" "$WORK/$n.cols.have"
  diff "$WORK/$n.cols.want" "$WORK/$n.cols.have" > /dev/null || die "$t: columns after CREATE differ from $f"
  log "  $t: created; re-read columns = the file's ($(wc -l < "$WORK/$n.cols.want" | tr -d ' '))"
  record "step$STEP" "$n" created "columns = file"
}

deploy_new_view() {   # NAME FILE (a view this deploy creates)
  local n=$1 f=$2 t
  t=$(obj "$n")
  xf "$f" "$WORK/$n.new.sql" --expect "$n"
  if ddl_of "$t" "$WORK/$n.deployed.sql"; then
    if tool same "$WORK/$n.deployed.sql" "$WORK/$n.new.sql" > /dev/null; then
      log "  $t: already deployed with the file's body (an earlier run): left as is"
      return
    fi
    tool same "$WORK/$n.deployed.sql" "$WORK/$n.new.sql" --label-a deployed --label-b "$f" | sed 's/^/    /' | tee -a "$LOG" || true
    die "$t exists with another body"
  fi
  q "create_$n" "$WORK/$n.new.sql"
  ddl_of "$t" "$WORK/$n.after.sql" || die "$t not found after CREATE"
  tool same "$WORK/$n.after.sql" "$WORK/$n.new.sql" > "$WORK/$n.after.txt" || { cat "$WORK/$n.after.txt"; die "$t: deployed body != $f"; }
  log "  $t: created; re-read body = file ($(cat "$WORK/$n.after.txt"))"
  record "step$STEP" "$n" created "body = file"
}

replace_object() {   # NAME: drift check, save, replace, re-read
  local n=$1 f t ref saved
  f=$(file_of "$n"); t=$(obj "$n"); ref=$(base_ref_for "$f")
  drift_one "$n"
  saved=$PRE/$n.ddl.sql
  case $DRIFT_STATE in
    MISSING) die "$t is not deployed: the deploy replaces an existing object" ;;
    NEW) log "  $t: already = $f (an earlier run)$([ -f "$saved" ] && echo "; pre-deploy DDL saved at $saved" || echo "; WARNING: no saved pre-deploy DDL at $saved")"
         record "step$STEP" "$n" "already deployed" "-"
         return ;;
    DRIFT) sed 's/^/    /' "$WORK/$n.drift.txt" | tee -a "$LOG"
           die "DRIFT: $t's deployed body is not $ref:$f (see above)" ;;
  esac
  if [ -f "$saved" ]; then
    tool same "$saved" "$WORK/$n.deployed.sql" > /dev/null || die "$saved exists and is not the deployed body: refusing to overwrite a saved pre-deploy DDL"
  else
    cp "$WORK/$n.deployed.sql" "$saved"
  fi
  log "  $t: deployed body = $ref:$f; DDL saved to $saved"
  q "replace_$n" "$WORK/$n.new.sql"
  ddl_of "$t" "$WORK/$n.after.sql" || die "$t not found after CREATE OR REPLACE"
  tool same "$WORK/$n.after.sql" "$WORK/$n.new.sql" > "$WORK/$n.after.txt" || { cat "$WORK/$n.after.txt"; die "$t: deployed body != $f after the deploy"; }
  log "  $t: replaced; re-read body = file ($(cat "$WORK/$n.after.txt"))"
  record "step$STEP" "$n" replaced "body = file; pre-deploy DDL $saved"
}

run_script() {   # TAG FILE
  xf "$2" "$WORK/$1.sql" --script
  q "$1" "$WORK/$1.sql"
}

# scalar TAG SQL: one-row query, prints the first column
scalar() {
  printf '%s\n' "$2" > "$WORK/$1.sql"
  q "$1" "$WORK/$1.sql"
  python3 -c '
import sys, json
d = json.load(open(sys.argv[1]))
while isinstance(d, list) and d and isinstance(d[0], list): d = d[-1]
print(list(d[0].values())[0] if d else "")' "$WORK/$1.out"
}

# ---------------------------------------------------------------------------------------------
# checks
# ---------------------------------------------------------------------------------------------
# kchecks TAG ALLOW_VEH IDS...: HOLDOUT_RESTART_acceptance.sql statements by id; each must read 0.
# ALLOW_VEH=1: K7 may read exactly 1, the one object off its count being V_ENGINE_HEALTH 3 (expected 1).
kchecks() {
  local tag=$1 allow=$2 extra="--script" id
  shift 2
  tool select "$ACC" "$@" > "$WORK/$tag.raw.sql"
  if [ -n "$PFX" ]; then
    extra="$extra --quoted"
    for id in "$@"; do if [ "$id" = K7 ]; then extra="$extra --k7 $PFX"; fi; done
  fi
  # shellcheck disable=SC2086
  xf "$WORK/$tag.raw.sql" "$WORK/$tag.sql" $extra
  q "$tag" "$WORK/$tag.sql"
  tool rows < "$WORK/$tag.out" > "$WORK/$tag.rows" || die "$tag: no check row in the output"
  python3 - "$WORK/$tag.rows" "$RECORD" "$tag" "$allow" "$PFX" "$@" <<'PY' | tee -a "$LOG"
import sys, json, datetime
rows_f, rec, tag, allow, pfx = sys.argv[1:6]
want = sys.argv[6:]
rows = [json.loads(l) for l in open(rows_f)]
bad = 0
seen = set()
with open(rec, 'a') as out:
    for r in rows:
        cid = r['check_name'].split('_')[0]
        seen.add(cid)
        v = int(r['violations'])
        ok = v == 0
        note = ''
        if not ok and cid == 'K7' and allow == '1' and v == 1 and r['detail'] == '%sV_ENGINE_HEALTH 3 (expected 1)' % pfx:
            ok, note = True, ' (expected before step 5: the board still holds trial 1\'s three references)'
        bad += 0 if ok else 1
        print('  %s %s = %d%s | %s' % ('ok  ' if ok else 'FAIL', r['check_name'], v, note, r['detail'][:600]))
        out.write('%s\t%s\t%s\t%d\t%s\n' % (datetime.datetime.now(datetime.timezone.utc).strftime('%F %T'), tag, r['check_name'], v, r['detail']))
missing = [w for w in want if w not in seen]
if missing:
    print('  FAIL no row for ' + ', '.join(missing))
    bad += 1
sys.exit(1 if bad else 0)
PY
}

k7b() {
  local f n bad=0
  [ -n "$BOOK_TOOLS" ] || die "K7b: the book branch's tools were not read (book_branch did not run)"
  for f in $BOOK_TOOL_FILES; do
    n=$(grep -c 'DE_HOLDOUT_ASSIGNMENT' "$BOOK_TOOLS/$f" || true)
    log "  $([ "$n" = 0 ] && echo 'ok  ' || echo FAIL) K7b $TOOLS_REF:$f: $n reference(s) to DE_HOLDOUT_ASSIGNMENT"
    record "step$STEP" "K7b $TOOLS_REF:$f" "$n" "grep -c DE_HOLDOUT_ASSIGNMENT"
    [ "$n" = 0 ] || bad=1
  done
  # the weekly book's mend (arm 2) carries its own holdout gate: exactly one V_HOLDOUT_ARM reference in MEND_SQL
  n=$(python3 -c 'import ast, sys
t = ast.parse(open(sys.argv[1]).read())
print(sum(x.value.value.count("V_HOLDOUT_ARM") for x in t.body if isinstance(x, ast.Assign)
          and isinstance(x.targets[0], ast.Name) and x.targets[0].id == "MEND_SQL"))' "$BOOK_TOOLS/tools/build_weekly_book.py")
  log "  $([ "$n" = 1 ] && echo 'ok  ' || echo FAIL) K7b $TOOLS_REF:tools/build_weekly_book.py MEND_SQL: $n V_HOLDOUT_ARM reference(s) (expected 1, the mend's holdout gate)"
  record "step$STEP" "K7b $TOOLS_REF:tools/build_weekly_book.py MEND_SQL" "$([ "$n" = 1 ] && echo 0 || echo 1)" "V_HOLDOUT_ARM references in MEND_SQL: $n (expected 1)"
  [ "$n" = 1 ] || bad=1
  [ "$bad" = 0 ] || die "K7b: a bulksheet tool still reads DE_HOLDOUT_ASSIGNMENT, or the weekly book's mend lost its holdout gate"
}

# K13 (plan §5): the weekly book's mend never prices a control. MEND_SQL read from the tool's source, run on the
# trial's HOLDOUT units with its gate read as of LA 10-06 (or today, when later): gated 0; the ungated text is
# the negative control (5 on 3 controls, measured 2026-10-04).
k13() {
  local asof rc=0
  asof=$(TZ=America/Los_Angeles date +%F)
  if [[ "$asof" < 2026-10-06 ]]; then asof=2026-10-06; fi
  [ -n "$BOOK_TOOLS" ] || die "K13: the book branch's tools were not read (book_branch did not run)"
  log "  K13 the weekly book's mend on the trial's controls, the gate read as of LA $asof, MEND_SQL from $TOOLS_REF:tools/build_weekly_book.py"
  python3 "$MIG/2026-10-05_holdout_t2_k13_mend.py" --tool "$BOOK_TOOLS/tools/build_weekly_book.py" --as-of "$asof" ${PFX:+--prefix "$PFX"} > "$WORK/k13.out" 2>&1 || rc=$?
  sed 's/^/    /' "$WORK/k13.out" | tee -a "$LOG"
  record "step$STEP" "K13 the mend on the controls (LA $asof)" "$rc" "$(grep -E '^K13 (gated|ungated)' "$WORK/k13.out" | tr '\n' ' ')"
  [ "$rc" = 0 ]
}

holdout_integrity() {
  xf "$HI" "$WORK/hi.sql" --script $([ -n "$PFX" ] && echo --quoted)
  log "  HOLDOUT_INTEGRITY_acceptance.sql ($(wc -c < "$WORK/hi.sql" | tr -d ' ') bytes; ~18 min)"
  qlong hi "$WORK/hi.sql"
  last_rows "$LONG_JOB" "$WORK/hi.result.json"
  tool rows < "$WORK/hi.result.json" > "$WORK/hi.rows" || die "HOLDOUT_INTEGRITY returned no row"
  python3 - "$WORK/hi.rows" "$RECORD" <<'PY' | tee -a "$LOG"
import sys, json, datetime
rows = [json.loads(l) for l in open(sys.argv[1])]
bad = [r for r in rows if r.get('result') != 'PASS']
with open(sys.argv[2], 'a') as out:
    for r in rows:
        out.write('%s\tHOLDOUT_INTEGRITY\t%s\t%s\t%s | %s\n' % (datetime.datetime.now(datetime.timezone.utc).strftime('%F %T'),
                  r['check_name'][:200], r.get('result'), r.get('measured'), r.get('expected')))
        print('  %s %s | measured %s | expected %s' % ('ok  ' if r.get('result') == 'PASS' else 'FAIL',
              r['check_name'][:150], str(r.get('measured'))[:200], str(r.get('expected'))[:80]))
print('  HOLDOUT_INTEGRITY: %d rows, %d FAIL' % (len(rows), len(bad)))
sys.exit(1 if bad or not rows else 0)
PY
}

# register suite: BEFORE (merge-base text, old register; saved) and AFTER (this deploy's text)
fsr_run() {   # TAG FILE OUTROWS
  xf "$2" "$WORK/$1.sql" --script
  qlong "$1" "$WORK/$1.sql"
  last_rows "$LONG_JOB" "$WORK/$1.result.json"
  tool rows < "$WORK/$1.result.json" > "$3" || die "$1 returned no row"
}

fsr_before() {
  local before=$PRE/V_FAMILY_SEAT_REGISTER_acceptance.before.rows ref
  if [ -f "$before" ]; then log "  register suite baseline: saved at $before (an earlier run)"; return; fi
  drift_one V_FAMILY_SEAT_REGISTER
  if [ "$DRIFT_STATE" != BASE ]; then
    log "  register suite baseline: SKIPPED, the register is no longer the pre-branch body ($DRIFT_STATE); step 5 then requires B09 and B34 only"
    return
  fi
  ref=$(base_ref_for "$FSR")
  git show "$ref:$FSR" > "$WORK/fsr_base.raw.sql"
  log "  register suite baseline: $ref:$FSR on the deployed (old) register"
  fsr_run fsr_before "$WORK/fsr_base.raw.sql" "$before"
  python3 -c '
import sys, json
rows = [json.loads(l) for l in open(sys.argv[1])]
print("  register suite BEFORE: %d checks, FAIL: %s" % (len(rows), ", ".join("%s %s" % (r["check_name"].split()[0], r["violations"]) for r in rows if r["result"] != "PASS") or "none"))' "$before" | tee -a "$LOG"
}

fsr_after() {
  local before=$PRE/V_FAMILY_SEAT_REGISTER_acceptance.before.rows
  log "  V_FAMILY_SEAT_REGISTER_acceptance.sql (this deploy's text) on the new register"
  fsr_run fsr_after "$FSR" "$WORK/fsr_after.rows"
  python3 - "$WORK/fsr_after.rows" "$before" "$RECORD" <<'PY' | tee -a "$LOG"
import sys, json, os, datetime
after = {r['check_name'].split()[0]: r for r in map(json.loads, open(sys.argv[1]))}
before = {r['check_name'].split()[0]: r for r in map(json.loads, open(sys.argv[2]))} if os.path.exists(sys.argv[2]) else None
bad = []
with open(sys.argv[3], 'a') as out:
    for k in sorted(after):
        a = after[k]
        b = before.get(k) if before is not None else None
        regress = before is not None and b is not None and b['result'] == 'PASS' and a['result'] != 'PASS'
        must = k in ('B09', 'B34') and a['result'] != 'PASS'
        new = before is not None and b is None and a['result'] != 'PASS'
        flag = 'FAIL' if (regress or must or new) else ('ok  ' if a['result'] == 'PASS' else 'was ')
        if flag == 'FAIL':
            bad.append(k)
        print('  %s %s after %s %s%s' % (flag, k, a['result'], a['violations'],
              '' if b is None else ' (before %s %s)' % (b['result'], b['violations'])))
        out.write('%s\tFSR\t%s\t%s\t%s\n' % (datetime.datetime.now(datetime.timezone.utc).strftime('%F %T'), k, a['violations'],
                  'before ' + (b['violations'] if b else 'n/a')))
print('  register suite: %d checks; regressions or holdout-check failures: %s%s' % (
      len(after), ', '.join(bad) or 'none', '' if before is not None else ' (no baseline: only B09 / B34 judged)'))
sys.exit(1 if bad else 0)
PY
}

# ---------------------------------------------------------------------------------------------
# the window
# ---------------------------------------------------------------------------------------------
STEP=0
STEP_NEED=(0 5 5 5 10 5)   # minutes per step (index = step); a step needs the sum over itself and every later step
step_guard() {   # STEP
  local s need=0
  STEP=$1
  for ((s = $1; s <= 5; s++)); do need=$((need + STEP_NEED[s])); done
  log "STEP $1 — the window, needing $need min for steps $1-5 ($([ "$MODE" = rehearse ] && echo 'measured, not enforced: rehearsal' || echo enforced))"
  if pass_guard "$need"; then return 0; fi
  if [ "$MODE" = rehearse ]; then log "  (rehearsal: the refusal above is not enforced)"; return 0; fi
  if [ "$1" -ge 3 ]; then
    die "the window does not allow step $1 now. Nothing of step $1 was written. Trial 2's founding rows are in: steps $1-5 must be deployed before pass 2 of 2026-10-06 (~07:35 UTC) or trial 2 is contaminated (header: Safe stopping points). Resume with: $0 --deploy --from-step $1"
  fi
  die "the window does not allow step $1 now. Nothing of step $1 was written. Resume with: $0 --deploy --from-step $1"
}

# ---------------------------------------------------------------------------------------------
# steps
# ---------------------------------------------------------------------------------------------
step1() {
  local v
  step_guard 1
  deploy_table DE_HOLDOUT_TRIAL scripts/bigquery/tables/DE_HOLDOUT_TRIAL.sql
  deploy_table DE_HOLDOUT_BASELINE scripts/bigquery/tables/DE_HOLDOUT_BASELINE.sql
  deploy_new_view V_HOLDOUT_TRIAL scripts/bigquery/views/V_HOLDOUT_TRIAL.sql
  deploy_new_view V_HOLDOUT_ARM scripts/bigquery/views/V_HOLDOUT_ARM.sql
  run_script registry_rows "$MIG/2026-10-05_holdout_t2_registry_rows.sql"
  v=$(scalar reg_rows "SELECT FORMAT('%d rows: %s', COUNT(*), STRING_AGG(FORMAT('%s %s %t', trial_id, event, effective_on), ', ' ORDER BY trial_id, event)) FROM \`$PROJECT.$DS.$(obj DE_HOLDOUT_TRIAL)\`")
  log "  registry rows: $v"
  kchecks k_step1 0 K1 K2 || die "step 1 checks"
}

step2() {
  local n
  step_guard 2
  n=$(scalar t2_rows "SELECT COUNT(*) FROM \`$PROJECT.$DS.$(obj DE_HOLDOUT_ASSIGNMENT)\` WHERE trial_id = '$T2'")
  if [ "$n" = 0 ]; then
    run_script founding "$MIG/2026-10-05_holdout_t2_founding.sql"
    log "  founding: written"
  else
    log "  founding: trial 2 already has $n rows (an earlier run): not re-run (K3 checks them)"
  fi
  n=$(scalar t2_base "SELECT COUNT(*) FROM \`$PROJECT.$DS.$(obj DE_HOLDOUT_BASELINE)\` WHERE trial_id = '$T2'")
  if [ "$n" = 0 ]; then
    run_script baseline "$MIG/2026-10-05_holdout_t2_baseline.sql"
    tool rows < "$WORK/baseline.out" | python3 -c '
import sys, json
for l in sys.stdin:
    r = json.loads(l); print("  baseline: %s (inserted minus read: %s)" % (r["detail"], r["violations"]))' | tee -a "$LOG"
  else
    log "  baseline: trial 2 already has $n baseline rows (an earlier run): not re-run (K12 checks them)"
  fi
  kchecks k_step2 0 K3 K4 K5 K6 K12 || die "step 2 checks"
}

step3() {
  local before after
  step_guard 3
  replace_object SP_ASSIGN_HOLDOUT
  replace_object V_HOLDOUT_ELIGIBLE
  kchecks k_step3 0 K2 K3 K4 || die "step 3 checks"
  if [ "$MODE" = rehearse ]; then
    # the new procedure, run on the copies: it must find trial 2 live with its rows and append LATE
    # ARRIVALs only (none expected while every eligible campaign is one of the 59)
    tool writes "$WORK/SP_ASSIGN_HOLDOUT.new.sql" | grep -v "$PFX" | grep -v '^CREATE OR REPLACE PROCEDURE' \
      && die "the rehearsal procedure writes a live object" || true
    before=$(scalar t2_before "SELECT COUNT(*) FROM \`$PROJECT.$DS.$(obj DE_HOLDOUT_ASSIGNMENT)\` WHERE trial_id = '$T2'")
    printf 'CALL `%s.%s.%s`();\n' "$PROJECT" "$DS" "$(obj SP_ASSIGN_HOLDOUT)" > "$WORK/call_assign.sql"
    qlong call_assign "$WORK/call_assign.sql"
    after=$(scalar t2_after "SELECT COUNT(*) FROM \`$PROJECT.$DS.$(obj DE_HOLDOUT_ASSIGNMENT)\` WHERE trial_id = '$T2'")
    log "  rehearsal CALL of $(obj SP_ASSIGN_HOLDOUT): trial 2 rows $before -> $after"
    record step3 "CALL SP_ASSIGN_HOLDOUT (rehearsal)" "$((after - before))" "rows appended to trial 2"
    kchecks k_step3_call 0 K2 K3 K4 || die "checks after the rehearsal CALL"
  else
    before=$(scalar late "SELECT FORMAT('%d: %s', COUNT(*), IFNULL(STRING_AGG(FORMAT('%s %s', campaign_id, campaign_name), ', ' LIMIT 20), 'none')) FROM \`$PROJECT.$DS.V_HOLDOUT_ELIGIBLE\` WHERE campaign_id NOT IN (SELECT unit_id FROM \`$PROJECT.$DS.DE_HOLDOUT_ASSIGNMENT\` WHERE trial_id = '$T2')")
    log "  INFO eligible campaigns outside trial 2 (the next pass appends them as LATE ARRIVALs): $before"
    record step3 "late arrivals (INFO)" "${before%%:*}" "$before"
  fi
}

step4() {
  step_guard 4
  fsr_before
  replace_object SP_ENGINE_PREFLIGHT
  replace_object V_PLAN_WINDOW_JUDGMENT
  replace_object V_FAMILY_SEAT_REGISTER
  kchecks k_step4 1 K7 || die "step 4 checks"
  k7b
}

step5() {
  step_guard 5
  replace_object V_HOLDOUT_READOUT
  replace_object V_ENGINE_HEALTH
  kchecks k_step5 0 K7 K10 K11 || die "step 5 checks"
  k7b
  k13 || die "K13: the weekly book's mend prices a control (or could not run)"
  holdout_integrity || die "HOLDOUT_INTEGRITY: a row is not PASS"
  fsr_after || die "V_FAMILY_SEAT_REGISTER_acceptance: a regression or a holdout check failed"
}

# ---------------------------------------------------------------------------------------------
# rehearsal setup and teardown
# ---------------------------------------------------------------------------------------------
tmp_objects() {   # lists 'kind name' of every OI object starting with PREFIX
  bq query --project_id="$PROJECT" --use_legacy_sql=false --nouse_cache --format=json --max_rows=1000 \
    "SELECT table_type AS kind, table_name AS name FROM \`$PROJECT.$DS.INFORMATION_SCHEMA.TABLES\` WHERE STARTS_WITH(table_name, '$1')
     UNION ALL SELECT routine_type, routine_name FROM \`$PROJECT.$DS.INFORMATION_SCHEMA.ROUTINES\` WHERE STARTS_WITH(routine_name, '$1')" \
    | python3 -c 'import sys, json; [print(r["kind"].replace(" ", "_"), r["name"]) for r in json.load(sys.stdin)]'
}

rehearse_setup() {
  local n
  log "REHEARSAL SETUP: copies under $REHEARSE_PREFIX, dates pinned to $REHEARSE_PIN"
  [ -z "$(tmp_objects "$REHEARSE_PREFIX")" ] || die "$REHEARSE_PREFIX objects exist: run $0 --rehearse-drop first"
  rm -f "$PRE"/*.ddl.sql "$PRE"/*.rows
  bq --project_id="$PROJECT" cp -n "$PROJECT:$DS.DE_HOLDOUT_ASSIGNMENT" "$PROJECT:$DS.$(obj DE_HOLDOUT_ASSIGNMENT)" > /dev/null \
    || die "could not copy DE_HOLDOUT_ASSIGNMENT"
  n=$(scalar asg_copy "SELECT FORMAT('%d rows, %d trial 1', COUNT(*), COUNTIF(trial_id = 'HOLDOUT-2026Q4-CAMPAIGN')) FROM \`$PROJECT.$DS.$(obj DE_HOLDOUT_ASSIGNMENT)\`")
  log "  $(obj DE_HOLDOUT_ASSIGNMENT) = COPY of DE_HOLDOUT_ASSIGNMENT ($n)"
  # the pre-images: each replaced object's LIVE ddl, renamed and pinned (the state the deploy starts from)
  for n in V_HOLDOUT_ELIGIBLE SP_ASSIGN_HOLDOUT SP_ENGINE_PREFLIGHT V_PLAN_WINDOW_JUDGMENT V_FAMILY_SEAT_REGISTER V_HOLDOUT_READOUT V_ENGINE_HEALTH; do
    ddl_of "$n" "$WORK/$n.live.sql" || die "$n is not deployed"
    xf "$WORK/$n.live.sql" "$WORK/$n.pre.sql" --create-or-replace --expect "$n"
    q "pre_$n" "$WORK/$n.pre.sql"
    log "  $(obj "$n") = the live $n, renamed and pinned"
  done
}

rehearse_drop() {
  local kind name n=0
  log "DROP every $REHEARSE_PREFIX object"
  tmp_objects "$REHEARSE_PREFIX" > "$WORK/drop.list"
  while read -r kind name; do
    [ -n "$name" ] || continue
    case $name in "$REHEARSE_PREFIX"*) ;; *) die "refusing to drop $name" ;; esac
    case $kind in
      VIEW) printf 'DROP VIEW `%s.%s.%s`;\n' "$PROJECT" "$DS" "$name" ;;
      PROCEDURE) printf 'DROP PROCEDURE `%s.%s.%s`;\n' "$PROJECT" "$DS" "$name" ;;
      BASE_TABLE) printf 'DROP TABLE `%s.%s.%s`;\n' "$PROJECT" "$DS" "$name" ;;
      *) die "unknown kind $kind for $name" ;;
    esac
    n=$((n + 1))
  done < "$WORK/drop.list" > "$WORK/drop.sql"
  if [ "$n" -gt 0 ]; then q drop "$WORK/drop.sql"; fi
  log "  dropped $n object(s); left with prefix TMP_HT2_: $(tmp_objects TMP_HT2_ | wc -l | tr -d ' ')"
  tmp_objects TMP_HT2_ | sed 's/^/    /' | tee -a "$LOG"
}

# ---------------------------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------------------------
DRIFT_COUNT=0
CHECK_REFUSALS=0
case $MODE in
  drop)
    rehearse_drop ;;
  postpass)
    log "POST-PASS CHECKS (read-only)"
    git rev-parse -q --verify "$TIP^{commit}" > /dev/null || die "--tip $TIP is not a commit here"
    book_branch
    pending_on_controls postpass
    kchecks k_postpass 0 K2 K3 K4 K8 K9 K9b || die "post-pass checks: K8 / K9b pass after the first pass gated for trial 2, K9 after pass 1 of 2026-10-06 (its detail says which snapshot is stale)"
    k13 || die "K13: the weekly book's mend prices a control: build every book with --no-mend until it reads 0"
    log "post-pass checks: every one reads 0" ;;
  check)
    preflight
    PFX="" XF=""
    drift_all
    STEP=check
    log "WINDOW"
    rc=0; pass_guard 5 || rc=$?
    if [ "$DRIFT_COUNT" -gt 0 ] || [ "$rc" != 0 ] || [ "$CHECK_REFUSALS" -gt 0 ]; then
      log "CHECK: the deploy may NOT start now (preflight refusals $CHECK_REFUSALS, drift $DRIFT_COUNT, window $([ "$rc" = 0 ] && echo open || echo refused)). Nothing was written."
      exit 1
    fi
    log "CHECK: the deploy may start now. Nothing was written." ;;
  deploy|rehearse)
    preflight
    if [ "$MODE" = rehearse ]; then
      # the live objects against their pre-branch files: what tomorrow's drift check will read
      PFX="" XF=""
      drift_all
      PFX=$REHEARSE_PREFIX XF="--prefix $REHEARSE_PREFIX --pin $REHEARSE_PIN"
      [ "$DRIFT_COUNT" = 0 ] || die "the LIVE objects drifted from their pre-branch files: tomorrow's deploy would stop"
    fi
    # a rehearsal without --from-step starts from fresh copies; with it, it resumes on the copies there
    if [ "$MODE" = rehearse ] && [ "$FROM_GIVEN" = 0 ]; then rehearse_setup; fi
    drift_all
    [ "$DRIFT_COUNT" = 0 ] || die "drift: nothing written"
    s=$FROM_STEP
    while [ "$s" -le "$TO_STEP" ]; do "step$s"; s=$((s + 1)); done
    log "DONE: steps $FROM_STEP-$TO_STEP deployed$([ "$MODE" = rehearse ] && echo ' (rehearsal, objects '"$REHEARSE_PREFIX"'*)') and checked. Record: $RECORD"
    log "NEXT: K8 and K9b after the next pass, K9 after pass 1 of 2026-10-06: $0 --post-pass. No upload on 10-05;"
    log "      no book built before step 4 uploaded after LA 10-04 (discard, rebuild after K9 and K13);"
    log "      no book from tools/build_weekly_book.py until K9 and K13 read 0 and the LA date is 2026-10-06;"
    log "      books only from $BOOK_BRANCH; deploy the dashboard + cube (the Do page's HoldoutArm hold) now that"
    log "      V_HOLDOUT_ARM exists, and until then queue nothing on the 12 from the Do page or Weekly Run;"
    log "      no hand change to the 12 controls." ;;
esac
