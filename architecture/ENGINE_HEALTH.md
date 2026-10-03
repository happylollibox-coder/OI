# ENGINE_HEALTH — the standing self-check

**Born:** 2026-08-16 (engine-finalization Task 3.3). `V_ENGINE_HEALTH`: one row per check —
GREEN / AMBER / RED / INFO, the measurement AND its threshold printed together. Reads small
tables only, except the single scorecard arm. A quiet board is the goal state.

Checks: contradiction_rate (EXCLUDE share; amber>5 red>15) · ownership_overlaps (red>0) ·
state_duplicate / missing_appointment (the V_KEYWORD_STATE invariants; red>0) ·
overdue_appointments (amber>50) · scorecard_reversed_share (trailing 42d judged; amber>35) ·
manual_better_unresolved (the MANUAL_DIVERGENCE closing rule) · snapshot_freshness (red>2d) ·
noop_leakage (amber>10) · view_body_headroom (v27.101; amber>70% red>85% of the view ceiling) ·
plan_price_ambiguity (v27.102; red>0) · loser_kill_clause / state_floor_resolution (v27.104;
red>0).

**The family seat register's checks (v27.127, 2026-08-23; `seat_*`, spec
`FAMILY_SEAT_REGISTER.md` "Health").** They read the register's once-per-pass IMAGE
(`T_FAMILY_SEAT_REGISTER` — the table the brief, the Weekly Run and the cube read), the seat
ledger, the keyword-state snapshot, the change log, the holdout table and `LOG_PIPELINE_RUNS`;
never the live register view and never a ceiling view. seat_reconciliation_gap (categories = the
family's spend on every horizon, seats + leaks + gaps = the bad side today, within $0.01 — the
acceptance suite's own tolerance; red>0) · seat_ledger_idempotence (the invariants a second
admission or a re-insert on one snapshot would break; the proof proper is two runs, one
fingerprint — red>0) · seat_every_occupant_numbered (red for an unnumbered or twice-held number
on the image; amber when the image and the ledger disagree, which is the transient between
orchestrator step 20.8b and cube step 0c of one pass) · seat_no_launch_seat (red>0) ·
seat_holdout_row_on_sheet (a seat book row naming a HOLDOUT-arm campaign built on or after its
`eligible_from`, at any upload status; red>0) · seat_raise_at_or_below_live_bid (ruling R-f;
red>0) · seat_past_due_in_future_tense (ruling R-i; red>0) · seat_overdue_vs_snapshot (INFO —
reports the appointments the ladder owes, measured on the snapshot's own date; the cause is the
park-era `settle_due`, diagnosed and not applied, a ruling for Ori) · seat_step_days_since_pass
(days since `SP_MAINTAIN_FAMILY_SEATS` last logged OK inside a pass, New York clock — the
orchestrator's clock; `started_at` is UTC and is converted; amber>1, red>2, red when never
logged). Every one was proven to fire on doctored `TMP_` copies before deploy and read
GREEN / INFO on the live objects after it; the numbers are the board's, never this file's.

**The next-week money plan's checks and the two alarms (v27.152, 2026-10-01; `plan_*` and
`pipeline_step_failing`, spec `NEXT_WEEK_MONEY.md` §6).** Why now: `SP_BUILD_NEXT_WEEK_PLAN`
failed every pass from 2026-08-29 to 2026-09-28, `LOG_PIPELINE_RUNS` logged every failure, and no
surface Ori reads said a word — while this board already carried three REDs nobody acted on, so a
RED here is necessary and not sufficient. The sufficient half is `V_DAILY_BRIEF`'s SYSTEM line
(section_rank 7), which reads this view LIVE and folds its RED rows into one sentence; see
`DAILY_BRIEF.md`. The checks read the plan's latest partition, the proposal snapshot and the gate
table — small — never the judgement view and never a ceiling view, and every partition check reads
RED on an EMPTY partition rather than vacuously green. plan_window_complete_days (the age-2
fence, the acceptance's C01 form — the Task 5 draft's `watermark − 1` fails after 22:00 Los Angeles;
red>0) · plan_pot_reconciliation (holdout spend outside the pot, the C03 form; red>0) ·
plan_one_move_per_notgood (one move per CANDIDATE, the C06 form — the draft read 152 violations on
a healthy partition; red>0) · plan_ownership_no_foreign_go (INFO: plan Task 3 is not built, no
engine PLAN writes proposals, so it REPORTS the foreign GO rows on money levers inside live-plan
campaigns as a number; red>0 once Task 3 ships) · plan_both_plans_written (red unless exactly A
and B) · plan_settle_guard_holds (P-14b as a clock, P-14c as a last-day test, NOT a veto: red for a
demotion under the guard's preconditions whose `guard_released_by` the judge did not publish as
HOLD_EXPIRED or LAST_DAY_NOT_STRONG, and for a HELD_UNSETTLED row whose last day was not very
good; the check READS the column and never re-derives the guard — the builder re-derived it and
vetoed every partition for a month) · plan_settle_curve_coverage (INFO) · plan_proposal_lag_days
(INFO; amber>2) · **plan_partition_fresh** (ALARM; red when the latest plan is older than the later
of yesterday and the Los Angeles day the plan step last ran, OK or FAIL — "older than today" alone
would be red every day between midnight and the 04:10 New York pass, which is the first that can
write today's partition; the detail says the last plan date and the nights missing) ·
**pipeline_step_failing** (ALARM, GENERIC; red when ANY procedure's three most recent runs in the
last 30 days all logged FAIL; the detail names each one with the first 120 characters of its latest
error and the length of the streak — the check that would have named the plan builder on day 1,
and that needs no new check for the next outage). Acceptance, with the negative controls as standing
checks: `scripts/bigquery/tests/PLAN_HEALTH_acceptance.sql`.

**The holdout's integrity (v27.162, 2026-10-03; ruling R9 = spec P-23, audit fix #27; spec
`HOLDOUT.md` §6 "Contamination").** holdout_unit_changed: RED when a HOLDOUT campaign changed inside
its trial window — a change-log row applied, or a change the observed-change ledger saw on Amazon
(hand changes in the console included) — and `V_HOLDOUT_READOUT` does not censor it and its
stratum-mates, both arms, from that day; RED as well when no HOLDOUT unit or no observed-change row
is read. It READS the readout's `CENSORED` rows and never re-derives the censoring; the detail lists
the HOLDOUT campaigns that changed (first day) and how many trial campaigns the readout censors, or,
when RED, names each campaign not censored. seat_holdout_row_on_sheet joins only the seat books' log
rows, which is why the two console pauses of 2026-09-27 were on no surface. Sources: the assignment
table, the change log and the readout's `CENSORED` branch — no `FACT_AMAZON_ADS` (filtering the board
on this check alone: 63.6 slot-s, measured 2026-10-03). Acceptance with negative controls on doctored
copies, running the board's own text: `scripts/bigquery/tests/HOLDOUT_INTEGRITY_acceptance.sql`.
**Follow-up (2026-10-03, review of commit a2e7e1e):** the v27.162 check read changes from
`eligible_from` (2026-09-01) only, but the arms were frozen on 2026-08-19, and 7 HOLDOUT units changed
in between (25 ledger rows: two 08-21 campaign pauses, the 08-23 reprice book on three units, and
unlogged observed changes on two) — none censored, none on any surface. R9 reads the window only;
whether such a change contaminates is a ruling for Ori (`HOLDOUT.md` §6 "Contamination", both answers
measured there). The check now also reads the readout's `PRE_WINDOW_CHANGE` rows: RED when a HOLDOUT
unit changed between its assignment day and its window start and the readout does not publish it
from that day, AMBER while any such change stands, and the detail names them. Measured after the
deploy: AMBER, measured 0; the board filtered to this check 99.5 / 143.6 slot-s (two runs, no
`FACT_AMAZON_ADS`). `V_DAILY_BRIEF`'s SYSTEM line counts RED rows only, so this AMBER shows on the
board and not in the brief. Acceptance: 31 rows PASS (`HOLDOUT_INTEGRITY_acceptance.sql` header).

**A refused pass, and the board's memory (v27.163, 2026-10-03; money-plan piece-1 Task 9).**
*Why:* the piece-0 proof found `SP_BUILD_NEXT_WEEK_PLAN` refused 3 of 9 passes from 2026-09-29 to
2026-10-01 (the seat-number continuity ASSERT). `LOG_PIPELINE_RUNS` holds at most two of its FAILs
in a row from 09-29 on, and `FACT_PLAN_NEXT_WEEK` a partition for every night 09-28 → 10-03 (both
read 2026-10-03), so neither plan_partition_fresh nor pipeline_step_failing could name one; and the
brief named each RED with no date, while the board carried the same three REDs on 2026-10-01 and on
2026-10-03, so a new RED would have read like them.

- **plan_pass_failed** (ALARM): RED when the latest run of the plan step in `LOG_PIPELINE_RUNS`
  (last 30 days) logged FAIL, or any run in the last 24 hours did; RED as well when the step logged
  no run in the last 24 hours (an empty log is not a healthy one — the pass runs three times a day,
  starting about 01:00, 03:35 and 12:00 New York, and reaches the step every time). The detail leads with the failure's New York
  time and the first 160 characters of its error, then the latest plan run, how many of the last
  24 hours' runs failed and the last failure in 30 days. Reads `LOG_PIPELINE_RUNS` only.
- **The board's memory.** `FACT_ENGINE_HEALTH_HISTORY` holds every row of the board as it read at
  the end of each orchestrator pass: `SP_SNAPSHOT_ENGINE_HEALTH`, Refresh Task 23, the pass's last
  step (after `SP_REFRESH_CUBE_TABLES`, so it reads the tables the pass rebuilt). One read of the
  board per call, into a temp table; the snapshot is refused (the step logs FAIL) on an empty board,
  a check name twice, or a row with no name or status. Append-only; nothing decides from it. The
  board's `V_CHANGE_SCORECARD` arm scans `FACT_AMAZON_ADS`: the first call (a hand CALL at deploy,
  2026-10-03 06:29 UTC, job `bqjob_r7bb161f1c65cac22_000001a10073cf32_1`) took 4,535.4 slot-seconds
  (4,530.3 of them the board read), 186,883,740 bytes, 32 s; a second hand CALL at 06:56 UTC
  (job `bqjob_r6d08822f1efc9463_000001a1008d244b_1`) 3,197.7 slot-seconds, 30 s. Three passes a
  day call it from then on.
- **What reads it.** `V_DAILY_BRIEF`'s SYSTEM line: for each RED check, `red_since` = the earliest
  snapshot of the current unbroken RED run (a snapshot on which the check was GREEN, AMBER, INFO or
  absent breaks it). NEW REDs first, standing ones after with the date each run began; see
  `DAILY_BRIEF.md`.

Acceptance, with negative controls on doctored copies: `PLAN_HEALTH_acceptance.sql` A1 (the check),
A2 (red_since and the line), A3 (the table: nothing twice, one row per check, one snapshot per pass).

Read the memory — every status each check has held, with the first and last snapshot it held it on
(a status held in two separate runs shows once, spanning both; the brief's `red_since` is the
run-aware reading):

```sql
SELECT check_name, status, MIN(snapshot_at) AS first_seen, MAX(snapshot_at) AS last_seen, COUNT(*) AS snapshots
FROM `onyga-482313.OI.FACT_ENGINE_HEALTH_HISTORY`
GROUP BY 1, 2 ORDER BY check_name, first_seen;
```

First board 2026-08-16: RED contradiction_rate 31.8 (57/179 — the gate WORKS; the signal is that
the engines structurally overlap a third of their instructions, mostly LAUNCH proposing on
LOW_STOCK-owned keys — a future refinement is to stop GENERATING those, not just silencing them)
· AMBER overdue_appointments 78 (oldest 2025-11-16) · AMBER scorecard_reversed_share 41.1 ·
six GREEN. Surfaces on the Weekly Run summary strip when Phase 6 builds it.

Read the board:

```sql
SELECT check_name, measured, status, threshold, detail
FROM `onyga-482313.OI.V_ENGINE_HEALTH` ORDER BY status = 'GREEN', check_name;
```
