# Holdout restart — trial 2 from 2026-10-06 (Ori's ruling of 2026-10-03, option (c))

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.
> **Nothing in this plan may be deployed before Task 0 (Ori's OK on the list) is done.** Task 0 is done
> (2026-10-04, below). The deploy is **2026-10-05**, by the runbook, inside the window of Task 8.

> **Status (2026-10-04): APPROVED, deploying 2026-10-05.** On 2026-10-04, after asking "explain seed 5",
> Ori wrote: **"ok seed 5, deploy it"**. The list in §3.1 is approved unchanged. The OK came before
> 2026-10-05 22:00 Los Angeles, so **no date moves** (Task 0): `assigned_on` / `gate_from` 2026-10-05,
> `win_start` 2026-10-06, `win_end` 2027-01-26, interim look 2026-12-15, `first_readout` 2027-02-09,
> trial 1 archived from 2026-10-05. The deploy runs on 2026-10-05 by
> `scripts/bigquery/migrations/2026-10-05_holdout_t2_deploy.sh` (Task R), in the window Task 8 sets.
> Nothing that changes live behaviour is deployed on 10-04; BigQuery stays read-only apart from
> `TMP_HT2_` scratch objects.
>
> This amendment (2026-10-04) folds in the pre-deploy review of 2026-10-03. Where each of its six
> fixes lands:
> 1. the touch alarm sees more kinds of hand change, wherever a source can date one, and states what
>    no source can see: §2.7, Task 6, HOLDOUT.md §6. R9's censoring is unchanged;
> 2. feed liveness watches the campaign and ad-group paths and each Fivetran source table on its own:
>    §2.7, Task 6;
> 3. `SP_ASSIGN_HOLDOUT` deploys before `V_HOLDOUT_ELIGIBLE`: Task 4;
> 4. a late OK also moves trial 1's `ARCHIVED.effective_on`: Task 0;
> 5. measured pass times, the deploy window and the two snapshot tables: Task 8; the preflight
>    times cited in §2.3 are corrected from the log;
> 6. wording: §1, §2.9, Appendix A.
>
> Every number this amendment adds was measured on 2026-10-04 between about 01:45 and 02:55 UTC. The
> queries are in Appendix C.
>
> **Follow-up (2026-10-04, re-review of the amendment).** The kind-4 design assumed that a row in a
> current-state table is a live setting. It is not: a removed adjustment keeps its old, un-re-stamped
> row. A setting is now present only when the table's latest sync re-stamped its row (the **presence
> rule**, §2.7 kind 4), in the founding baseline (Task 3), c33's `BASELINE_DIFF` (Task 6) and K12 (§5).
> A NULL `value` on a later baseline row means absent (Task 2, Step 3b). The "8 of the 12 controls"
> figure is corrected to 7 (Appendix C11, C12).
>
> **Second follow-up (2026-10-04, re-review).** Kind 4 now names the controls it watches: the live
> trial's HOLDOUT units with `STARTS_WITH(assignment_rule, 'FOUNDING')`, whether or not they have a
> baseline row. `BASELINE_DIFF`'s today side reads only those. A `LATE ARRIVAL` control is named
> unwatched by its `assignment_rule`, never because it has no baseline row (§2.7 kind 4, Task 2 Step 3b,
> Task 6, Task 7 H4, K12). The tests were re-run with c33's text and no id literal (Appendix C12).

**Goal:** restart the randomized holdout so that a clean control group exists from 2026-10-06, keep the
contaminated first trial on record untouched, and make the health board turn RED the night a control
campaign is touched. When this plan was written the only step left was Ori's OK on the list in §3.

**Architecture:** `DE_HOLDOUT_ASSIGNMENT` already carries `trial_id`. No column is added and no row is
updated. A small append-only registry (`DE_HOLDOUT_TRIAL`) records which trial is live and when each
trial's arm binds. Two views read it: `V_HOLDOUT_TRIAL` gives one row per trial, and `V_HOLDOUT_ARM` gives
one row per control campaign whose arm binds today or later. Every reader that blocks controls today reads
`DE_HOLDOUT_ASSIGNMENT` directly and takes the union of all trials. All of them except the preflight
also have no end date. Each of those
readers switches to `V_HOLDOUT_ARM`, a one-CTE edit that keeps its column names. The readout and the
integrity check read the live trial from the registry instead of a literal. The trial-2 founding cohort is
written once from the approved literal list, never re-drawn live. (Amendment of 2026-10-04: a second
small append-only table, `DE_HOLDOUT_BASELINE`, holds each control's value at the assignment for the
settings no source can date, such as placement adjustments and SB product targets. The touch alarm
compares against it, §2.7.)

**Status (2026-10-03):** nothing is deployed and BigQuery was read-only throughout. The draw in §3 was
computed by `SELECT` only (scratch queries, reproduced in Appendix B). The FACT anchor was 2026-10-02.
Cap and launch states were read 2026-10-03 at about 16:00 UTC.

**Sources:** `architecture/HOLDOUT.md` (§4 population, §5 draw, §6 contamination, §8 readout),
`scripts/bigquery/tables/DE_HOLDOUT_ASSIGNMENT.sql`, `procedures/SP_ASSIGN_HOLDOUT.sql`,
`views/V_HOLDOUT_ELIGIBLE.sql`, `views/V_HOLDOUT_READOUT.sql`, `views/V_ENGINE_HEALTH.sql` (c18, c33),
`tests/HOLDOUT_INTEGRITY_acceptance.sql`, piece-1 plan `docs/superpowers/plans/2026-10-02-money-plan-rulings-piece1.md`
(Task 8).

---

## In plain words

- **The old trial is spoiled.** Since the arms were drawn on 08-19, changes reached 10 of its 14 control
  campaigns. Some were uploads, some were console changes, and two were Ori's pauses. The rule Ori chose
  (R9) therefore throws away 61 of its 69 campaigns. The old trial stays in the table exactly as it is,
  marked "archived, contaminated" in a new registry. Its rows are never edited.
- **A new trial starts on 10-06 with a fresh coin flip, by the same rules.** It covers 59 campaigns.
  12 of them are controls, carrying 21% of the money (about $226 a day). It runs 16 weeks to 2027-01-26,
  and the answer comes on 2027-02-09.
- **Ori's one decision was the list of 12 controls in §3.1.** He approved it on 2026-10-04: "ok seed 5,
  deploy it". Nothing is written before the deploy on 2026-10-05.
- **Three things change in the code.**
  1. A "which trial is live" registry. Every place that keeps the engine off a control reads it, so the
     old controls are released and the new ones frozen on the same day.
  2. The alarm that is supposed to turn RED when a control is touched. Today it does not: it read AMBER on
     10-03 with 8 touched controls.
  3. The new list is written once, exactly as approved.

## Ori's rulings, 2026-10-03

| # | ruling |
|---|---|
| (1) | **The holdout trial restarts** (option (c) of the piece-1 follow-up question). The window restarts on 2026-10-06 with a FRESH draw by the same method. The old trial is kept on record, archived, with its contamination stated. The plan relies on `V_ENGINE_HEALTH` `holdout_unit_changed` to turn the brief RED the same night a control campaign is touched. |
| (2) | **A seated keyword that later becomes a probe keeps the question it was seated with.** This confirms piece-1 follow-up G1, builder v27.168. It is recorded as spec P-30, beside P-16 and P-25. |
| (3) | **Ori believes he made no change on Amazon since 2026-09-27, and the observed-change feed shows none.** The evidence that the feed is alive rather than stalled is in Appendix A. |

## House rules binding on every task

- **Never `UPDATE`, `DELETE`, `MERGE … WHEN MATCHED` or `CREATE OR REPLACE TABLE` on
  `DE_HOLDOUT_ASSIGNMENT`, `DE_HOLDOUT_TRIAL` or `DE_HOLDOUT_BASELINE`.** All three are append-only
  (HOLDOUT.md §6 #1). `DE_HOLDOUT_BASELINE` was added by the 2026-10-04 amendment (§2.7).
- **Targeted `git add` only.** About ten unrelated files are dirty and other sessions commit here. Use
  `--no-verify`. Every commit ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **SOPs first** (`architecture/` before code, project CLAUDE.md). **Register every new object in
  `config.yaml`**, and `python3 -c "import yaml; yaml.safe_load(open('config.yaml'))"` must pass.
- **Every check returns a violation count and has a negative control** on a temp copy, and the measured
  result goes in the acceptance file's header. Add an emptiness term wherever an empty input would pass.
- **Deploy a near-limit file with comment lines stripped:**
  `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^[[:space:]]*--' FILE)"`.
  Before replacing a deployed object, diff its `INFORMATION_SCHEMA` body against the file. The only
  difference allowed is this plan's edit.
- **Do not run `SP_ORCHESTRATE_DAILY_REFRESH`.** No orchestrator step is added: `SP_ASSIGN_HOLDOUT`
  stays at Task 20.55.
- **Long `bq` jobs:** use `--nosync` and poll with `bq wait JOB 60`, one call per invocation. Record the
  slot-seconds of every read that is new on a hot path.
- **Comments make no untested claim.**

---

## 1. Who reads `DE_HOLDOUT_ASSIGNMENT`, and what a second trial's rows would do to each

Repository grep on 2026-10-03, excluding `.bak` copies: no Cube schema, dashboard file or Flask route
reads the table. `cube/schema/SeatRegister.js` reads the register's `holdout` columns, so it inherits the
register's fix. Every reader filters `unit_type = 'CAMPAIGN'` except c18 (row 4), which joins on
`unit_id` and `arm` only. That is harmless today, because every row is a `CAMPAIGN` row, and c18's
switch to `V_HOLDOUT_ARM` (which filters) closes it. Rows 15 and 16 (added 2026-10-04) are not readers
of the table. They are snapshots of two readers, and they keep the old holds until a pass rebuilds them.

| # | reader | how it reads it today | what trial-2 rows would do to it if left alone | edit |
|---|---|---|---|---|
| 1 | `SP_ASSIGN_HOLDOUT` (writer, Task 20.55) | its own trial only: anti-join on `(trial_id, unit_id)`, per-stratum count of placed units; constants are T1 literals | keeps appending new campaigns to **T1** and never assigns T2 late arrivals. (It has appended nothing since 08-19: 137 OK runs and still 69 rows, because every campaign eligible on 10-03 under T1's rules is already a T1 unit.) | reads the live trial from `V_HOLDOUT_TRIAL`; refuses to write into a trial whose founding cohort is absent (Task 4) |
| 2 | `SP_ENGINE_PREFLIGHT` `hold` | `unit_id`, `arm = 'HOLDOUT'`, `CURRENT_DATE(LA) BETWEEN eligible_from AND trial_end`, **all trials**, `GROUP BY unit` with `MAX(trial_id)` | T1's 14 controls stay EXCLUDED until 2026-12-22, including all 10 that T2 draws as TREATED. T2's controls start biting only on 10-06 (see §2.3) | reads `V_HOLDOUT_ARM` binding today (Task 5) |
| 3 | `V_HOLDOUT_READOUT` `asg` | `trial_id = k.trial_id`, a T1 literal in `k` with the T1 dates | keeps reading T1 (censored 61 of 69) | `k` reads the live trial's row from `V_HOLDOUT_TRIAL`; nothing else changes (Task 6) |
| 4 | `V_ENGINE_HEALTH` c18 `seat_holdout_row_on_sheet` | `unit_id`, `arm`, **all trials**, book rows on or after `eligible_from`, **no end**; detail prints `MIN(eligible_from)` over all HOLDOUT rows | prints "the arm starts 2026-09-01" forever. A T1-only control released to the engine and put on a seat book would read RED | joins `V_HOLDOUT_ARM` between `gate_from` and `gate_to` (Task 6) |
| 5 | `V_ENGINE_HEALTH` c33 `holdout_unit_changed` (`hu_asg`) | `trial_id = 'HOLDOUT-2026Q4-CAMPAIGN'` literal | watches T1 only | `hu_asg` reads the live trial. **Plus the touch alarm and the feed liveness term**, because as built c33 does not turn RED on a touch (§2.7) (Task 6) |
| 6 | `V_FAMILY_SEAT_REGISTER` `holdout` | `unit_id`, `arm`, `MIN(eligible_from)` over **all trials**, **no end** | T1's 14 controls stay "holdout" on the register forever (no seat moves, no book rows) | reads `V_HOLDOUT_ARM` (Task 5) |
| 7 | `V_PLAN_WINDOW_JUDGMENT` `holdout` | same as 6 | same: T1 controls get `NONE_HOLDOUT` forever. This flows into `SP_BUILD_NEXT_WEEK_PLAN`, `FACT_PLAN_NEXT_WEEK`, `tools/build_weekly_book.py`, `V_DAILY_BRIEF`, `SP_APPEND_SEAT_REQUEST` and `V_SEAT_REQUEST_OUTCOME`, all of which inherit the fix | reads `V_HOLDOUT_ARM` (Task 5) |
| 8 | `tools/build_reprice_bulksheet.py` `hold` | same as 6 (`today_la >= eligible_from`) | the book never prices a T1 control again | reads `V_HOLDOUT_ARM` (Task 5) |
| 9 | `tools/build_seasonal_unpause_bulksheet.py` `hold` | same as 6 | same | reads `V_HOLDOUT_ARM` (Task 5) |
| 10 | `tools/build_seat_moves_bulksheet.py` `hold` (two CTEs) | same as 6 | same | reads `V_HOLDOUT_ARM` (Task 5) |
| 11 | `V_HOLDOUT_ELIGIBLE` | does not read the table; holds the population's stock literal `('Bunny', 'LolliBall')` | late arrivals to T2 would be judged on T1's population | literal re-graded to `('LolliBall')` (§2.4, Task 4) |
| 12 | `tests/HOLDOUT_INTEGRITY_acceptance.sql` | `trial_id` literal; pastes c33's text verbatim; H3 gates on 2027-01-05 | stays on T1 | follows the c33 edit; H3 reads `first_readout`; new H4/H5 (Task 7) |
| 13 | `tests/V_FAMILY_SEAT_REGISTER_acceptance.sql` (line 350) | `MIN(eligible_from)` over all trials | expects T1 controls held forever | reads `V_HOLDOUT_ARM` (Task 7) |
| 14 | `tests/PLAN_OWNERSHIP_acceptance.sql` (**untracked, another session's work in progress**) | `hold_open`: HOLDOUT rows in window, all trials | T1 controls stay "open" holds | **do not edit**; tell its owner to read `V_HOLDOUT_ARM` (Task 7) |
| 15 | `T_FAMILY_SEAT_REGISTER` (snapshot of reader 6) | `CREATE OR REPLACE` from `V_FAMILY_SEAT_REGISTER` by `SP_REFRESH_CUBE_TABLES` (Refresh Task 21), once per pass. Read by `V_DAILY_BRIEF`, `V_RUN_SUMMARY`, the `seat_*` board checks, `SP_SNAPSHOT_ENGINE_HEALTH` and `cube/schema/SeatRegister.js` | from the deploy until that step next logs OK, it still marks T1's controls `holdout` and not T2's | none: the next rebuild inherits Task 5's fix. Check it after that pass (Task 8) |
| 16 | `FACT_PLAN_NEXT_WEEK` (snapshot of reader 7) | a partition per night, written by `SP_BUILD_NEXT_WEEK_PLAN` from `V_PLAN_WINDOW_JUDGMENT`. Its `holdout` column is read by `tools/build_weekly_book.py` (`AND NOT c.holdout`), `SP_APPEND_SEAT_REQUEST` (copied into `FACT_SEAT_REQUEST`) and `V_PREDICTION_LEDGER` | from the deploy until the first partition written after it, the latest partition holds T1's controls and not T2's. **A book built from it in that gap would carry T2 controls.** That first partition is `as_of` 2026-10-06, written by pass 1 of 10-06 (~05:30 UTC), in either deploy window. `as_of` is the New York date (v27.160), and pass 1 of 10-05 (01:00 New York, 22:00 LA 10-04) writes `as_of` 10-05 before the deploy. From LA midnight that night is FROZEN (v27.170): passes 2 and 3 of 10-05 log OK and write nothing, so "the step logged OK" does not mean "a partition was written" (measured 10-04: pass 2's step logged OK in 1 s at 08:09:42 UTC, and the `as_of` 10-04 partition kept `built_at` 05:30:18). **No weekly book can be built on 10-05**, none before that pass (Task 8). Corrected 2026-10-04: this row first said "until the plan step next logs OK" | none: the first partition written after the deploy (`as_of` 10-06) inherits Task 5's fix. K9 runs on it, after pass 1 of 10-06 (Task 8, Task 9) |

**Double counting.** Only the readout aggregates the arms, and it filters on one `trial_id`. Every other
reader takes a set of campaigns (`GROUP BY` campaign), so a second trial cannot double any number. The
danger is different: those readers take the **union of every trial's controls with no end date**. Left
alone, T1's 14 controls would stay frozen beside T2's 12.

---

## 2. Design

### 2.1 How a trial is identified

- **`trial_id` already exists** in `DE_HOLDOUT_ASSIGNMENT` ("A second trial gets a new id and its own
  rows", DDL comment). Trial 2 is `HOLDOUT-2026Q4-CAMPAIGN-T2`. No migration adds a column, and no T1 row
  is touched.
- **`DE_HOLDOUT_TRIAL`** is new, append-only, and holds one row per event: `OPENED` or `ARCHIVED`. A
  trial's status cannot live on `DE_HOLDOUT_ASSIGNMENT`, because marking 69 old rows would be an
  `UPDATE`. T1 gets a back-filled `OPENED` row with its own v27.83 constants, then an `ARCHIVED` row
  effective 2026-10-05.
- **`V_HOLDOUT_TRIAL`** gives one row per trial: `gate_from`, `gate_to`, `win_start`, `win_end`,
  `first_readout`, `is_live` and `status_today`.
  - `gate_to = LEAST(win_end, archived_from − 1)`.
  - Exactly one trial is live: the one not archived. The readout, c33 and `SP_ASSIGN_HOLDOUT` read that
    row and break ties on the newest `assigned_on`.
- **`V_HOLDOUT_ARM`** is the gate. It gives one row per control campaign of any trial whose arm binds
  today or later:
  - `campaign_id`, `gate_from = MIN`, `gate_to = MAX`, `trial_id`;
  - a T1 control that T2 drew as TREATED drops out on 2026-10-05;
  - a hold ends on its trial's last day, which none of readers 6–10 can do today.

  Simulated on the T1 rows plus the approved T2 literal (Appendix B, `gate_sim`):

  | day | rows | binding | of which T2 | of which T1 |
  |---|---|---|---|---|
  | 10-05 | 12 | 12 | 12 | 0 |
  | 10-06 | 12 | 12 | 12 | 0 |
  | 2027-01-26 | 12 | 12 | 12 | 0 |
  | 2027-01-27 | 0 | — | — | — |

  On 10-04, had the registry existed, the view would hold 26 rows, 14 of them binding, all T1.

### 2.2 Dates. T1's horizon rule, re-applied

T1's rule: `trial_end = eligible_from + 112` (16 weeks), `first_readout = trial_end + 14` (the settle),
and interim safety look `= eligible_from + 70` (8 weeks observed plus the settle).

| | trial 1 (archived) | trial 2 |
|---|---|---|
| assignment (`assigned_on`, LA) | 2026-08-19 | **2026-10-05** |
| gate opens (`gate_from`, export blocked from this LA day) | 2026-09-01 | **2026-10-05** |
| window start (`eligible_from`; the estimate and R9 start here) | 2026-09-01 | **2026-10-06** |
| last day enforced (`trial_end`) | 2026-12-22 | **2027-01-26** |
| interim safety look (one-time hand query, §8) | 2026-11-10 | **2026-12-15** |
| first readout (never pulled forward) | 2027-01-05 | **2027-02-09** |
| archived from | **2026-10-05** | — |

### 2.3 Why the gate opens the day before the window

`LOG_PIPELINE_RUNS` shows `SP_ENGINE_PREFLIGHT` at 05:33, 08:04 and 16:55 UTC on 10-02, and at 05:33,
08:08 and 16:31 UTC on 10-03. (Corrected 2026-10-04 from the log. The first version of this plan cited
"16:55" for 10-03 too, but it was written before that day's third pass, whose preflight ran at 16:31.)
Over the 21 passes from 09-27 to 10-03 the preflight started at 05:29–05:41, 08:03–08:20 and
16:31–16:57 UTC (Task 8). The 05:33 UTC run is 01:33 New York but **22:33 Los Angeles of the previous
day**. Every gate reader compares a Los Angeles date.

So the pass that builds the book uploaded on the morning of 10-06 judges under LA date **10-05**. If the
T2 arm only bit from its window start (10-06), that book would carry rows for T2 controls. Uploaded on
10-06, it would contaminate them on the first day of the window.

The gate therefore opens on the assignment day (`gate_from = 2026-10-05`), and the window opens on 10-06.
T1 releases its controls on the same day (`archived_from = 2026-10-05`), so exactly one trial binds on
any day.

A change that lands on a T2 control on 10-05 can only come from a book built before the insert or from a
hand change. The readout already publishes such a change as a `PRE_WINDOW_CHANGE` row, and it is **not
censored**: R9 as Ori built it reads the window only. That is pre-declared here for T2, so no ruling is
left pending. The new touch alarm (§2.7) turns RED on it anyway. The runbook (Task 8) forbids both
sources: no book is uploaded on 10-05, because none can be built after the deploy that day (the plan
partition a book reads is first rebuilt on the deployed code by pass 1 of 10-06, Task 8; corrected
2026-10-04 from "upload only a book built after the deploy, or none"). Sunday's Weekly Run upload on 10-04
comes before the assignment and is fine.

### 2.4 The eligible population, with the same exclusions re-applied on the design date

These are HOLDOUT.md §4's four rules, read on 2026-10-03:

- **ENABLED and serving**;
- **spend > 0 in the 28 days** to the FACT anchor 2026-10-02;
- **not brand defense** (`campaign_name LIKE '%brand defense%'`);
- **not a family in ACTUAL CRITICAL stock on the design date**, kept as a frozen literal.

The stock literal is the one rule whose *answer* changed:

| family | T1 (graded 2026-08-18) | 2026-10-03 (`V_LOW_STOCK_ADS`, family row) |
|---|---|---|
| LolliBall | CRITICAL, excluded | **CRITICAL** (21.6 d binding cover). Excluded |
| Bunny | CRITICAL, excluded | **OK.** 159.4 d binding cover, 6,000 units arriving 10-07. **Eligible** |
| Fresh / LolliME / Lollibox | OK, forecast THROTTLE | actual OK; forecast THROTTLE / **CRITICAL** / THROTTLE |

The exclusion exists because holding a family out costs inventory when stock runs dry (§4). Bunny no
longer has that problem, so the same rule applied on the new design date lets Bunny in.

**Population:** 59 campaigns, $30,114.34 per 28 days, five families (Bottle, Bunny, Fresh, LolliME,
Lollibox).

- Keeping T1's literal instead would give 54 campaigns and $29,416. Seed index 5 is also the first pass
  under that population, with 11 controls, but the list differs.
- Every campaign eligible on 10-03 is a T1 unit except the 5 Bunny campaigns.
- 10 of T1's 14 controls are still eligible. The other 4 are paused: the two 08-21 pauses and Ori's two
  09-27 pauses.

### 2.5 The draw: the same method, declared before it ran

These are HOLDOUT.md §5's rules, unchanged except for the seed prefix and the two criteria that scale
with the population.

```
stratum        = channel | CAP/UNC | LNC/GRD                       (frozen at the draw)
seq_in_stratum = 0-based rank in stratum by spend_28d DESC, campaign_id   (fresh for T2)
offset         = MOD(ABS(FARM_FINGERPRINT(seed || '|' || stratum)), 5)
arm            = HOLDOUT iff MOD(seq_in_stratum + offset, 5) = 0, else TREATED
seed           = 'OI-HOLDOUT-v2|' || seed_index, the FIRST seed_index = 0, 1, 2, … passing:
  A1  exactly ROUND(N / 5) controls          (T1: 14 = ROUND(69/5); T2: 12 = ROUND(59/5))
  A2  control share of eligible 28-day ad dollars in [0.18, 0.22]
  A3  every eligible family present among the controls (T1: five; T2: five)
```

- **Result.** `seed_index = 5` (`OI-HOLDOUT-v2|5`) is the first pass. Indices 0–4 fail:
  - 0 gives 14 controls;
  - 1 gives 12 controls at 16.1%;
  - 2 gives 11 controls;
  - 3 gives 11 controls at 24.4%;
  - 4 gives 14 controls covering 4 families.
- **The acceptance region,** which the permutation inference must stay inside (§8), is **18,190 of the
  390,625 offset vectors** (4.66%). By seed index, 7 of the first 200 pass: 5, 52, 88, 96, 123, 128
  and 151.
- **Why not the suggested `FARM_FINGERPRINT(unit_id || '|T2-…')` ordering.** Ruling (1) says "the same
  method". That ordering is a different method: a random order with no size blocking.

### 2.6 The list Ori approves is the list that lands

The population reads live views (`V_DIM_CAMPAIGN_CURRENT`, `V_CAMPAIGN_CAP_STATE`, `V_LAUNCH_POPULATION`)
that cannot be pinned to 10-03. A live re-draw on 10-05 could therefore differ from what Ori saw.

So the founding cohort is inserted **from the literal list in Task 3**. It is guarded by:
- its fingerprint `4171456845817687166`, taken over `unit_id|arm|stratum|seq` ordered by `unit_id`;
- an assertion that every arm follows the rule from the stored columns.

The cohort is marked `assignment_rule = 'FOUNDING (approved list): …'`.

The trial-2 version of `SP_ASSIGN_HOLDOUT` then assigns **late arrivals only**. These are campaigns
eligible after 10-03, assigned on first sight by the same seed, with `seq_in_stratum` continuing the
stratum's count. A cohort campaign that is paused before 10-05 keeps its row and arm (intention to treat).

### 2.7 Contamination and the alarm for trial 2

- **R9 stays as built** (Ori, 2026-10-02, option (a)). A change inside `[eligible_from, trial_end]` on a
  control censors its stratum, in both arms, from that day. A change between the assignment and the
  window start (10-05 only) is published as `PRE_WINDOW_CHANGE` and not censored, pre-declared above.
- **As built, c33 does not alarm on a touch.** Measured 2026-10-03: `holdout_unit_changed` read
  **AMBER, measured 0**. Its own detail said 8 of 14 controls had changed inside the window, including
  Ori's two 09-27 pauses.
  - c33 turns RED only when `V_HOLDOUT_READOUT` *fails* to censor a change.
  - The readout censors from the same ledger on the same read, so a working readout keeps c33 out of
    RED however many controls are touched.
  - Ruling (1)'s reliance needs a new term.
- **Touch alarm (new; widened 2026-10-04 by review fix 1).** c33 is RED while any *touch* on a control
  of the live trial, from its assignment day on, is 7 or fewer Los Angeles days old. After that it is
  AMBER for as long as any control was ever touched, and the detail names each one.
  - **Why 7 days:** the brief is read daily. Seven days survives a missed brief or a weekend.
  - **"The same night"** means the next orchestrator pass after Fivetran syncs the change, because
    `SP_RECORD_OBSERVED_CHANGES` and the three DIM loads run in every pass. An SP keyword or a campaign
    is dated by Amazon's own `last_updated_date`. An SB keyword is dated by the sync that first saw it,
    up to a day late (`V_AMAZON_OBSERVED_CHANGES` header).
  - **A touch is any of four kinds.** Kinds 1–3 are read for every HOLDOUT unit of the live trial.
    Kind 4 is read for its founding HOLDOUT units only (the watched set, defined under kind 4). The
    sources were chosen after measuring what each one carries (2026-10-04, Appendix C).
    1. **A ledger row**, as first designed: `hu_led` ∪ `hu_pre`. The observed-change ledger records
       keyword and product-target bid and state, campaign budget and state, and ad-group default bid
       and state, whether they come from an applied change-log row or an observed one. R9 censors one
       inside the window. One on 10-05 is a `PRE_WINDOW_CHANGE`.
    2. **A new keyword, product target or ad group on a control.** The ledger never counts an entity's
       first version: `V_AMAZON_OBSERVED_CHANGES` calls it "a creation, not a change".
       - **Source:** the first version of a `keyword_id` in `DIM_KEYWORD`, or of an `ad_group_id` in
         `DIM_AD_GROUP`, on a control, whose LA day falls on or after the control's assignment day.
       - **Dated by** that version's `effective_from`. For SP keywords and SP product targets that is
         Amazon's `last_updated_date`. Measured: the only two created since 08-20, both on 2026-08-26,
         have first versions equal to their Fivetran `creation_date` to the millisecond. For an SB
         keyword it is the sync that first saw it.
    3. **A portfolio move or a bidding-strategy change.**
       - **Source:** a `DIM_CAMPAIGN` version on a control, on or after its assignment day, whose
         `portfolio_id` or `bidding_strategy` differs from its predecessor's. `SP_LOAD_DIM_CAMPAIGN`
         versions both; the ledger reads neither. Measured since 08-20, account-wide: 1 portfolio
         change (08-21) and 1 bidding-strategy change (08-26).
       - **SB campaigns** carry no bidding strategy in `DIM_CAMPAIGN`, because the source view writes
         `''`. Their `bid_optimization` and `bid_optimization_strategy` are read the same way, from
         version pairs of `fivetran-hl.amazon_ads.sb_campaign_history`. That is a history table dated
         by `last_update_date`: 253 campaigns and 1,942 rows, with 0 such changes since 08-20.
    4. **A setting that differs from its value at the assignment:**
       - placement bid adjustments: `campaign_placement_bidding` (SP) and
         `sb_campaign_bid_adjustments_by_placement` (SB);
       - SB shopper-cohort adjustments: `sb_campaign_bid_adjustments_shopper_cohort`;
       - an SB product target's bid and state: `sb_product_target`.

       **No source can date a change to these.** None of the four tables has a history, a creation
       date or a change date. `sb_product_target` is also outside `V_SRC_AmazonAds_keyword`, so
       `DIM_KEYWORD`, the ledger and R9 never see an SB product target at all. **BOX-VIDEO/PT
       (Competitors, Purple, A1) `27660342907703`, the largest control at $49.47 a day, has no keyword
       in `DIM_KEYWORD`.** Its one target is an SB product target, so its only bid lever is invisible
       to the ledger.

       **A row in one of these tables is not necessarily a live setting** (corrected 2026-10-04 on
       re-review; the first version said each table "keeps today's value only" and that Fivetran
       "re-stamps its rows on every sync"):
       - A sync re-stamps only the rows Amazon still returns. A row Amazon stops returning keeps its
         old `_fivetran_synced` and stays in the table. The three adjustment tables have no
         `_fivetran_deleted` column, so such a row is never marked deleted either. Only
         `sb_product_target` carries the flag.
       - Measured at the 2026-10-04 02:14 UTC sync (Appendix C11): `campaign_placement_bidding`
         re-stamped 181 of its 195 rows. The other 14 rows, on 13 campaigns, were last stamped
         between 2026-03-17 and 08-14, and none of those 13 campaigns has a re-stamped row.
       - Two of the 14 rows belong to control `365568042533669` ME-COMPETE (ENABLED):
         `PLACEMENT_TOP` 30 and `PLACEMENT_PRODUCT_PAGE` 15, stamped 2026-06-23. These are almost
         certainly adjustments removed months ago.
       - The SP table holds no 0% row (0 of 195), so an SP adjustment set to 0% most likely stops
         being returned, as a removal does. The presence rule below reads either case as a
         difference: a row that stops being re-stamped turns absent, and a re-stamped 0% differs from
         the baseline value.
       - `sb_product_target` keeps 62 rows that have not been re-stamped since 2026-01-02. All 62 carry
         `_fivetran_deleted`. The SB placement and shopper-cohort tables were re-stamped whole (390 of
         390 and 36 of 36).

       **The presence rule.** A setting is present only when its row was re-stamped by its table's
       latest sync, that is `_fivetran_synced >= MAX(_fivetran_synced)` of that table minus 1 hour,
       and the row is not `_fivetran_deleted`. Every other row is absent. This one rule is used in
       three places: the founding baseline insert (Task 3), c33's `BASELINE_DIFF` (Task 6) and K12's
       re-read (§5).
       - **Why one hour (measured, Appendix C11).** Time travel was read at 30 points, 1 to 166 hours
         back. At every point and on all four tables, every row of the latest sync carried one stamp
         (spread 0.0 minutes). The nearest older stamp was at least 1,046 hours older on the SP table
         and 6,429 hours older on `sb_product_target`. The set of present settings never changed on
         the three adjustment tables. On `sb_product_target` it changed once, between 150 and 144
         hours back, which was a bid or state change.
       - If two syncs ever landed within one hour, a row the second one stopped re-stamping would
         read as present until the next sync.
       - **Measured with the rule** (02:14 UTC sync): 7 of the 12 controls carry placement rows, 5 SP
         and 2 SB. 6 of the 7 carry a non-zero adjustment. `537046793426450`'s four SB rows are all 0%,
         and that control also carries the one shopper-cohort row (0%). `27660342907703` carries the
         one SB product target. In all, **15 settings on 8 controls**. Four controls carry none,
         ME-COMPETE among them. The first version said "8 of the 12 controls carry rows": it counted
         ME-COMPETE's two stale rows, and `537046793426450`'s rows, which are all 0%.

       BigQuery time travel cannot compare a table with its own past inside one query (measured: "is
       referenced with and without 'FOR SYSTEM_TIME AS OF'"), so a stored value is the only reference.
       The design:
       - the founding script (Task 3) writes each watched control's **present** settings once, by the
         presence rule, into a new append-only table `DE_HOLDOUT_BASELINE` (Task 2);
       - c33 compares the watched controls' present settings today, by the same rule, with the latest
         baseline row per setting. A changed value, or a setting present on one side only, is an
         **undated touch**;
       - so a removal is seen. On SP, a removed adjustment's row stops being re-stamped, turns absent
         and differs from its baseline. A stale row that Fivetran drops later, for example on a
         re-sync, changes nothing, because it was already absent. Without the rule, the baseline
         would have recorded ME-COMPETE's two removed adjustments as live, a removal would have left
         no difference, and a dropped stale row would have read as an undated touch with no touch
         behind it. All three were tested on copies (Appendix C12);
       - an undated touch reads **RED while it stands**, because no date exists to age it. The detail
         says "date unknown: the source keeps no history";
       - Ori's ruling on it is recorded by appending a baseline row that carries his words. **A NULL
         `value` on a later baseline row means absent**, so a removal can be re-baselined like a
         changed value. A setting re-baselined that way reads AMBER from then on, as an aged touch
         does. If it comes back later, it differs from the NULL and reads RED again.

       **Which controls kind 4 watches (the watched set; second follow-up, 2026-10-04).** The watched
       set is the live trial's HOLDOUT units with `STARTS_WITH(assignment_rule, 'FOUNDING')`, whether or
       not they have a baseline row. c33 derives it from `hu_asg`, so it reads `DE_HOLDOUT_ASSIGNMENT`
       no second time.
       - **`BASELINE_DIFF`'s today side reads the watched set only.** A watched control with no
         baseline row is still watched: any setting present on it differs from the absent baseline and
         reads RED. Four founding controls carry no setting today: `273898143987321`,
         `271009556929636`, `51727823265377` and ME-COMPETE `365568042533669`. This is what makes an
         adjustment put back on ME-COMPETE read RED.
       - **Every other HOLDOUT unit of the live trial is unwatched on kind-4 settings.** Under T2 that
         means a `LATE ARRIVAL` from `SP_ASSIGN_HOLDOUT` (Task 4). No baseline is taken for it, its
         settings are never compared, and the detail names it as unwatched. It is named by its
         `assignment_rule`, never because it has no baseline row.
       - **Why not every HOLDOUT unit:** a late arrival has no baseline, so every setting present on it
         would be present on one side only, and it would read RED with nothing touched. SB campaigns
         usually carry 0% placement rows: 356 of the 390 SB placement rows are 0%, and 124 of the 128
         SB campaigns with placement rows carry at least one (read at the 2026-10-04 03:07 UTC sync).
         So this would happen often. Measured on copies: a late SB control with two 0% placement rows
         and one 0% shopper-cohort row read 3 differences that way (Appendix C12).
       - **Why not only the controls that have a baseline row:** the four founding controls above have
         none, so they would be silently unwatched, ME-COMPETE among them. Measured on copies: an
         adjustment put back on ME-COMPETE read 0 differences that way (Appendix C12).
       - **Kinds 1–3 are unchanged.** They watch every HOLDOUT unit of the live trial, late arrivals
         included.
       - If the watched set were ever empty while baseline rows exist (for example, an
         `assignment_rule` written without its prefix), every baseline row is present on one side only,
         so c33 reads RED. It cannot pass silently. Measured on copies: 15 differences (Appendix C12).
  - **Kinds 2–4 are seen by the alarm and not censored by R9.** R9 stays as Ori ruled it on 10-02, and
    the readout's censoring is not widened. The detail says "seen by the alarm, not censored by R9 —
    Ori to rule".
- **What no source can see.** This is stated in HOLDOUT.md §6 and in the tail of c33's detail on every
  read:
  - **Negatives added or removed by hand.** The five negative mirrors (`negative_keyword_history`,
    `campaign_negative_keyword_history`, `sb_negative_keyword`, `negative_targeting_clause_history`,
    `sb_negative_product_target`) were last written between 2025-12-29 and 2026-01-03. None had a write
    job in the 30 days to 10-04. `DE_NEGATIVE_KEYWORDS` holds only the negatives OI uploads itself.
  - **Ads and creatives.** `product_ad_history` (last written 2026-01-03), `sb_ad_history` (2025-12-29)
    and `sb_creative_history` (2025-12-28) are frozen the same way.
  - **A change undone before the next sync**, or two changes between two DIM loads, which read as one
    version carrying the later value.
  - **A kind-4 setting put back to its baseline value** before the board reads it.
  - **Not used:** `campaign_history` wrote 20 versions on 10 campaigns since 08-20 in which every
    carried attribute equals the previous version's. Amazon recorded some change the mirror does not
    carry, but its cause is unproven, so it is not a touch.

  Ori was told on 2026-10-04: "the safest rule is not to open these 12 campaigns at all."
- **Feed liveness (new; widened 2026-10-04 by review fix 2).** c33 is RED when any of the following is
  more than 36 hours old or missing. The detail prints every age and names the stale one.
  - **The last OK run in `LOG_PIPELINE_RUNS`** of `SP_RECORD_OBSERVED_CHANGES`, `SP_LOAD_DIM_KEYWORD`,
    `SP_LOAD_DIM_CAMPAIGN` and `SP_LOAD_DIM_AD_GROUP`, each on its own. Measured over 30 days: each one
    logged OK on every pass, and the largest gap between two OK runs was 13.0 hours for each (a 16:0x
    run to the next 05:0x UTC run). `SP_RECORD_OBSERVED_CHANGES` has been logging only since 2026-10-02
    05:02 UTC.
  - **`MAX(_fivetran_synced)` of each Fivetran table that feeds the ledger or the alarm**, each on its
    own and never as one MAX over a union:
    - `keyword_history` (SP keywords);
    - `sb_keyword` (SB keywords);
    - `targeting_clause_history` (SP product targets);
    - `campaign_history` (SP campaigns);
    - `sb_campaign_history` (SB campaigns);
    - `ad_group_history` (SP ad groups);
    - `sb_ad_group_history` (SB ad groups);
    - for kind 4: `campaign_placement_bidding`, `sb_campaign_bid_adjustments_by_placement`,
      `sb_campaign_bid_adjustments_shopper_cohort` and `sb_product_target`.

    The deployed `V_SRC_AmazonAds_keyword` unions the first three tables. Its MAX would stay fresh on
    `sb_keyword` alone.
  - **Why each table's MAX ticks daily (measured).** Each sync re-stamps every row Amazon still
    returns. It does not re-stamp every row in the table (corrected 2026-10-04). The 02:14 UTC sync of
    10-04 re-stamped these rows (Appendix C11):

    | table | re-stamped | rows |
    |---|---|---|
    | `keyword_history` | 19,786 | 38,697 |
    | `targeting_clause_history` | 5,836 | 11,218 |
    | `campaign_history` | 861 | 4,495 |
    | `ad_group_history` | 991 | 1,837 |
    | `sb_ad_group_history` | 273 | 333 |
    | `sb_campaign_history` | 253 | 1,942 |
    | `sb_product_target` | 88 | 150 |
    | `campaign_placement_bidding` | 181 | 195 |
    | `sb_keyword` | 8,415 | 8,415 |
    | SB placement | 390 | 390 |
    | shopper cohort | 36 | 36 |

    So a table's `MAX(_fivetran_synced)` is its last sync, not its last change, for as long as Amazon
    returns at least one of its rows. The evidence:
    - BigQuery's job history for the Fivetran project shows a write that touched rows on each of the
      eleven tables at gaps of at most 21 hours over the 30 days to 10-04 (16 hours for
      `campaign_history` and `campaign_placement_bidding`, 12 hours for `ad_group_history`);
    - time-travel reads of `MAX(_fivetran_synced)` every 12 hours over the last 7 days found it
      0.0–9.9 hours old.

    No source on the term has a normal gap anywhere near 36 hours. The reviewer's warning is true of
    the stamps that survive on *superseded* history rows: those move only on a change, and
    `keyword_history`'s surviving stamps show a 386-hour gap. So the term reads each table's MAX, never
    a gap between surviving stamps.
  - **Left out, and why:** the frozen tables listed under "What no source can see". They have not been
    written since early January and would hold c33 RED for good. Fivetran's own sync log
    (`fivetran-hl.fivetran_metadata.log`) stopped on 2025-12-29, so it cannot serve either.

  Without this term, "no change" and "feed stalled" read the same, which was the open question behind
  ruling (3).
- `V_DAILY_BRIEF`'s SYSTEM line counts RED rows, so RED on the board is RED in the brief.

### 2.8 Trial 1, archived

- Its 69 rows stay as they are. Their fingerprint on 2026-10-03 was `7298956708089075507`, over every
  column ordered by `unit_id`. Check K2 holds it.
- Its `ARCHIVED` registry row carries the contamination in words (Task 2).
- `V_HOLDOUT_READOUT` stops computing it, because the view serves the live trial.
- The record stays reproducible: run `HOLDOUT_INTEGRITY_acceptance.sql`'s `led` and `pre` statements with
  the T1 constants.
- The contamination numbers are in HOLDOUT.md §6:
  - **10 of 14 controls** changed after the assignment: 7 before the window, 8 inside it, 5 both;
  - **61 of 69 units** are censored under R9 (13 of 14 HOLDOUT, 48 of 55 TREATED);
  - **no estimate was ever read.**

### 2.9 What does not change

- The estimand and the outcome: `GROSS_PROFIT − Ads_cost` from `FACT_AMAZON_ADS`, paired on the same
  rows.
- The randomization unit (the campaign) and the strata.
- The readout's gate, estimators and verdict sentences.
- The censoring rule for a family that enters ACTUAL CRITICAL (§6).
- The rule that the preflight blocks the export, never the judgement.
- `t_mult` 3.27 is carried from T1's design. It was not re-derived for 12 clusters.
- The ex-ante MDE is T1's $2,261, rescaled by `N·√(1/h + 1/t)` to **$2,089 per 14 days**, on T1's noise
  floor. A larger multiplier for 12 clusters would raise it, so read it as a floor.
- **The MDE against the whole quantity.** −$1,868.51 is **half the draw's 28-day net**: −$3,737.02 ÷ 2,
  the convention T1 used (§3.2's net, read 2026-10-03). It is not a measured 14-day net.
  - `FACT_AMAZON_ADS` summed over the 59 campaigns for 09-19 .. 10-02 reads −$2,052.52 (read
    2026-10-04).
  - FACT restates as days settle. The same 28-day sum read on 10-04 is −$4,145.07. The draw's figures
    stay as approved.
  - Either way, the MDE is about 1.0–1.1× the whole quantity being measured. **§7's warning applies
    unchanged.**

---

## 3. The proposed draw: the list for Ori's OK

### 3.1 The 12 control (HOLDOUT) campaigns, by family

The engine must not touch these from 2026-10-05 to 2027-01-26, and **neither may a person**. Each
campaign's spend per day is its 28-day spend to 2026-10-02 divided by 28.

| family | campaign | campaign_id | stratum | seq | $/day (28d) | 28-day spend | share of eligible $ | net 28d | arm in trial 1 |
|---|---|---|---|---|---|---|---|---|---|
| Bottle | BOTTLE-VIDEO/EXACT (social-game, Truth) | `71317833591283` | SB\|UNC\|LNC | 4 | $0.67 | $18.67 | 0.06% | −$18.67 | TREATED |
| Bottle | BOTTLE-SP/PHRASE (tween-girl-birthday-gift, Truth) | `53343800376430` | SP\|UNC\|LNC | 19 | $0.02 | $0.70 | 0.00% | −$0.70 | TREATED |
| Bunny | BUNNY-SP/AUTO (Birthday) | `273898143987321` | SP\|UNC\|LNC | 4 | $5.62 | $157.34 | 0.52% | $46.01 | not in trial 1 |
| Fresh | FRESH -SP/AUTO (Purple) | `271009556929636` | SP\|UNC\|GRD | 5 | $3.69 | $103.40 | 0.34% | −$7.48 | TREATED |
| LolliME | ME-SBS/BROAD (Discovery, Journal) | `537046793426450` | SB\|CAP\|LNC | 1 | $49.32 | $1,380.97 | 4.59% | −$302.68 | TREATED |
| LolliME | ME-COMPETE (Nollh Mint) | `365568042533669` | SP\|CAP\|GRD | 2 | $44.76 | $1,253.37 | 4.16% | −$164.29 | TREATED |
| LolliME | ME-SP/AUTO (Mint) | `527422818407259` | SP\|UNC\|GRD | 0 | $34.34 | $961.64 | 3.19% | $211.29 | TREATED |
| LolliME | MINT-SP/BROAD (Back to School) | `51727823265377` | SP\|CAP\|LNC | 2 | $23.08 | $646.31 | 2.15% | $16.69 | TREATED |
| LolliME | ME-SP/EXACT (tween-girl-journal-diary, Purple) | `130115986205897` | SP\|CAP\|LNC | 7 | $12.78 | $357.73 | 1.19% | −$34.62 | TREATED |
| LolliME | ME-SP/PT (Competitors, Mint, D2) | `230219410635024` | SP\|UNC\|LNC | 9 | $1.64 | $45.83 | 0.15% | −$20.33 | TREATED |
| LolliME | ME-SP/PT (Competitors, Mint, C2) | `222497123677300` | SP\|UNC\|LNC | 14 | $0.57 | $15.86 | 0.05% | $22.39 | TREATED |
| Lollibox | BOX-VIDEO/PT (Competitors, Purple, A1) | `27660342907703` | SB\|CAP\|GRD | 2 | $49.47 | $1,385.21 | 4.60% | −$639.48 | TREATED |
| **all** | **12 campaigns** | | | | **$225.97** | **$6,327.03** | **21.01%** | **−$891.87** | |

Per family, the controls spend **$0.69 a day** in Bottle (2), **$5.62** in Bunny (1), **$3.69** in Fresh
(1), **$166.49** in LolliME (7) and **$49.47** in Lollibox (1).

### 3.2 Balance

| | HOLDOUT | TREATED |
|---|---|---|
| campaigns | **12** (20.3%) | **47** |
| ad spend, 28 d | **$6,327.03 (21.01%)** | $23,787.31 |
| ad spend per day | $225.97 | $849.55 |
| gross profit, 28 d | $5,435.16 | $20,942.16 |
| net, 28 d | −$891.87 | −$2,845.15 |
| net per ad dollar | **−0.141** | **−0.120** |
| mean / median 28-d spend per campaign | $527 / $358 | $506 / $225 |
| largest campaign (share of eligible $) | $1,385 (4.6%) | $2,376 (7.9%) |
| SB | 3 (25%) | 15 (32%) |
| capped (`is_oob_owned`) | 5 (42%) | 15 (32%) |
| launch population | 8 (67%) | 34 (72%) |
| families represented | 5 of 5 | 5 of 5 |
| controls in trial 1 | **0** | 10 |
| not in trial 1 (Bunny) | 1 | 4 |

- **The pre-trial gap** is chance and small. The controls ran $0.021 of net per ad dollar worse than the
  treated arm, about $68 per 14 days at the control arm's size, around 3% of the MDE. T1's controls ran
  $0.057 better, about $146.
- **The change-score estimate** in the readout removes the gap.

| stratum | offset | HOLDOUT / TREATED | HOLDOUT $ / TREATED $ (28 d) |
|---|---|---|---|
| SB\|CAP\|GRD | 3 | 1 / 3 | $1,385 / $4,127 |
| SB\|CAP\|LNC | 4 | 1 / 2 | $1,381 / $1,992 |
| SB\|UNC\|GRD | 1 | **0 / 4** | $0 / $5,423 |
| SB\|UNC\|LNC | 1 | 1 / 6 | $19 / $445 |
| SP\|CAP\|GRD | 3 | 1 / 2 | $1,253 / $4,242 |
| SP\|CAP\|LNC | 3 | 2 / 8 | $1,004 / $4,310 |
| SP\|UNC\|GRD | 0 | 2 / 4 | $1,065 / $1,619 |
| SP\|UNC\|LNC | 1 | 4 / 18 | $220 / $1,628 |

SB\|UNC\|GRD has four campaigns and offset 1, so its only control slot (seq 4) is empty. Every campaign
still had a one-in-five chance. T1's SB\|CAP\|GRD had no control either.

| family | controls / campaigns | control share of the family's 28-d dollars |
|---|---|---|
| Bottle | 2 / 6 | 2.7% |
| Bunny | 1 / 5 | 22.5% |
| Fresh | 1 / 9 | 1.6% |
| LolliME | 7 / 25 | 37.3% |
| Lollibox | 1 / 14 | 14.5% |

### 3.3 Two things to know before saying OK

1. **LolliME carries 74% of the control dollars** ($166.49 of $225.97 a day, 7 of 12 controls).
   - LolliME's actual stock is OK, but its forecast reads CRITICAL: forecast family cover is 20.5 days.
     Mint LolliME's forecast cover is 5.0 days against 48.2 actual, with 1,200 units arriving 10-07.
   - §6's pre-committed rule removes a family that enters ACTUAL CRITICAL from both arms. If LolliME
     does, the trial keeps **5 controls ($59.47 a day) and 29 treated**.
   - The plan keeps seed 5 anyway, for two reasons:
     - The rule was declared before the draw ran. Picking another seed because this one looks
       unlucky is picking the draw.
     - The concentration is what the method usually produces here: 4 of the 7 accepted seeds in 0–199
       put 70% or more of control dollars in LolliME.
   - The only honest alternative is a newly declared criterion applied from index 0, for example "A4:
     no family carries over half the control dollars". Its first pass is seed 52, which has a larger
     pre-trial gap (control −0.247 vs treated −0.096 net per ad dollar). It is not clearly better, and
     it is Ori's call, not this plan's.
2. **None of T1's 10 still-eligible controls was drawn as a control in T2.** All 10 are TREATED.
   - About 2 would be expected, and a simple random draw gives zero about 8% of the time.
   - These 10 campaigns have had no engine instruction since 09-01 (hand changes aside). From 10-05 the
     engine manages them again, so the treated arm opens with a catch-up burst. That burst is part of
     the treatment and the estimate stays unbiased.
   - **Pre-registered now:** the readout's sensitivity checks gain one row, "the estimate without the 10
     former T1 controls", which is exploratory like the action-class rows. It sits beside the
     leave-one-out check.

### 3.4 The full draw (59 campaigns)

| family | stratum | seq | offset | arm | campaign | campaign_id | $/day | share | arm in trial 1 |
|---|---|---|---|---|---|---|---|---|---|
| Bottle | SB\|UNC\|LNC | 0 | 1 | TREATED | BOTTLE-VIDEO/PT (Competitors, Truth Or Dare, E1) | `274922784647676` | $8.05 | 0.75% | TREATED |
| Bottle | SB\|UNC\|LNC | 3 | 1 | TREATED | BOTTLE-VIDEO/PT (Competitors, Truth Or Dare, D1) | `66467422009617` | $0.70 | 0.07% | HOLDOUT |
| Bottle | SB\|UNC\|LNC | 4 | 1 | **HOLDOUT** | BOTTLE-VIDEO/EXACT (social-game, Truth) | `71317833591283` | $0.67 | 0.06% | TREATED |
| Bottle | SP\|CAP\|LNC | 6 | 3 | TREATED | BOTTLE-SP/AUTO | `279837860088128` | $14.77 | 1.37% | HOLDOUT |
| Bottle | SP\|UNC\|LNC | 12 | 1 | TREATED | BOTTLE- COPYCAT | `3918431774030` | $1.13 | 0.10% | TREATED |
| Bottle | SP\|UNC\|LNC | 19 | 1 | **HOLDOUT** | BOTTLE-SP/PHRASE (tween-girl-birthday-gift, Truth) | `53343800376430` | $0.02 | 0.00% | TREATED |
| Bunny | SB\|UNC\|LNC | 1 | 1 | TREATED | BUNNY-VIDEO/BROAD (Hunter) | `107017178352577` | $3.70 | 0.34% | — |
| Bunny | SP\|UNC\|LNC | 2 | 1 | TREATED | BUNNY-SP/BROAD (Hunter, Gift for Girl , keychain) | `146179760782525` | $7.98 | 0.74% | — |
| Bunny | SP\|UNC\|LNC | 3 | 1 | TREATED | BUNNY-SP/AUTO (Brave) | `112036454757078` | $7.53 | 0.70% | — |
| Bunny | SP\|UNC\|LNC | 4 | 1 | **HOLDOUT** | BUNNY-SP/AUTO (Birthday) | `273898143987321` | $5.62 | 0.52% | — |
| Bunny | SP\|UNC\|LNC | 18 | 1 | TREATED | BUNNY-SP/EXACT (backpack charms for girls) | `206332152032611` | $0.09 | 0.01% | — |
| Fresh | SB\|CAP\|LNC | 0 | 4 | TREATED | FRESH - SB\BROAD (Hunter, FRESH) | `342313119548309` | $53.08 | 4.94% | TREATED |
| Fresh | SB\|UNC\|GRD | 0 | 1 | TREATED | FRESH-VIDEO/ BROAD | `446868628489343` | $84.85 | 7.89% | HOLDOUT |
| Fresh | SB\|UNC\|GRD | 1 | 1 | TREATED | FRESH SP/BROAD (Hunter ,Pink, Gift) | `292848303399755` | $53.16 | 4.94% | TREATED |
| Fresh | SP\|CAP\|LNC | 9 | 3 | TREATED | FRESH-SP/PT (Competitors, Pink, A1) | `227290137740434` | $4.55 | 0.42% | HOLDOUT |
| Fresh | SP\|UNC\|GRD | 1 | 0 | TREATED | FRESH-SP/BROAD (Back to School) | `28526809722181` | $25.52 | 2.37% | TREATED |
| Fresh | SP\|UNC\|GRD | 5 | 0 | **HOLDOUT** | FRESH -SP/AUTO (Purple) | `271009556929636` | $3.69 | 0.34% | TREATED |
| Fresh | SP\|UNC\|LNC | 1 | 1 | TREATED | FRESH -SP/AUTO (Pink) | `185651228688176` | $9.81 | 0.91% | TREATED |
| Fresh | SP\|UNC\|LNC | 7 | 1 | TREATED | FRESH-SP/AUTO (Blue) | `67504198774096` | $2.99 | 0.28% | TREATED |
| Fresh | SP\|UNC\|LNC | 15 | 1 | TREATED | FRESH-SP/EXACT (teen-girl-gift, Fresh) | `224831787476880` | $0.46 | 0.04% | TREATED |
| LolliME | SB\|CAP\|GRD | 0 | 3 | TREATED | ME-VIDEO/BROAD (Hunter) | `369056697567588` | $60.48 | 5.62% | TREATED |
| LolliME | SB\|CAP\|LNC | 1 | 4 | **HOLDOUT** | ME-SBS/BROAD (Discovery, Journal) | `537046793426450` | $49.32 | 4.59% | TREATED |
| LolliME | SB\|CAP\|LNC | 2 | 4 | TREATED | ME-VIDEO/PT (Competitors, Pink, D1) | `176884360124879` | $18.08 | 1.68% | TREATED |
| LolliME | SB\|UNC\|GRD | 2 | 1 | TREATED | BRAND-STORE/BROAD (Me,Box,Bottle) | `491652134548478` | $36.94 | 3.44% | TREATED |
| LolliME | SB\|UNC\|GRD | 3 | 1 | TREATED | ME-VIDEO/EXACT (age8-14-girl-journal-diary, Purple) | `435692261851957` | $18.72 | 1.74% | TREATED |
| LolliME | SB\|UNC\|LNC | 5 | 1 | TREATED | ME-VIDEO/PT (Competitors, Pink, E1) | `26332659728861` | $0.13 | 0.01% | TREATED |
| LolliME | SP\|CAP\|GRD | 2 | 3 | **HOLDOUT** | ME-COMPETE (Nollh Mint) | `365568042533669` | $44.76 | 4.16% | TREATED |
| LolliME | SP\|CAP\|LNC | 0 | 3 | TREATED | ME-SP/PT (Conquest, Competitors) | `531456687555062` | $47.93 | 4.46% | TREATED |
| LolliME | SP\|CAP\|LNC | 2 | 3 | **HOLDOUT** | MINT-SP/BROAD (Back to School) | `51727823265377` | $23.08 | 2.15% | TREATED |
| LolliME | SP\|CAP\|LNC | 3 | 3 | TREATED | ME-SP/BROAD (Mint, journaling kit for g) | `190387447939462` | $17.53 | 1.63% | HOLDOUT |
| LolliME | SP\|CAP\|LNC | 4 | 3 | TREATED | ME-SP/PT (Competitors, Mint, D3) | `2626284884970` | $15.76 | 1.47% | TREATED |
| LolliME | SP\|CAP\|LNC | 5 | 3 | TREATED | ME-SP/PT (Competitors, Mint, D1) | `19013742686856` | $15.06 | 1.40% | TREATED |
| LolliME | SP\|CAP\|LNC | 7 | 3 | **HOLDOUT** | ME-SP/EXACT (tween-girl-journal-diary, Purple) | `130115986205897` | $12.78 | 1.19% | TREATED |
| LolliME | SP\|CAP\|LNC | 8 | 3 | TREATED | ME-SP/AUTO (Pink) | `163079264356669` | $12.76 | 1.19% | TREATED |
| LolliME | SP\|UNC\|GRD | 0 | 0 | **HOLDOUT** | ME-SP/AUTO (Mint) | `527422818407259` | $34.34 | 3.19% | TREATED |
| LolliME | SP\|UNC\|GRD | 2 | 0 | TREATED | ME-SP/AUTO (Purple) | `158989642962021` | $16.09 | 1.50% | TREATED |
| LolliME | SP\|UNC\|GRD | 4 | 0 | TREATED | ME-SP/PT (Competitors, Mint, B2) | `104973644967484` | $5.12 | 0.48% | TREATED |
| LolliME | SP\|UNC\|LNC | 0 | 1 | TREATED | ME-SP/PHRASE (age8-14-girl-journal-diary, Mint) | `60344378778716` | $10.48 | 0.97% | TREATED |
| LolliME | SP\|UNC\|LNC | 8 | 1 | TREATED | ME-SP/PHRASE (tween-girl-birthday-gift, Purple 3) | `275295641745590` | $2.83 | 0.26% | TREATED |
| LolliME | SP\|UNC\|LNC | 9 | 1 | **HOLDOUT** | ME-SP/PT (Competitors, Mint, D2) | `230219410635024` | $1.64 | 0.15% | TREATED |
| LolliME | SP\|UNC\|LNC | 11 | 1 | TREATED | ME-SP/PT (Competitors, Mint, A1) | `43890791772293` | $1.16 | 0.11% | TREATED |
| LolliME | SP\|UNC\|LNC | 14 | 1 | **HOLDOUT** | ME-SP/PT (Competitors, Mint, C2) | `222497123677300` | $0.57 | 0.05% | TREATED |
| LolliME | SP\|UNC\|LNC | 16 | 1 | TREATED | ME-SP/EXACT (kid-girl-birthday-gift, Purple) | `32239413784257` | $0.44 | 0.04% | TREATED |
| LolliME | SP\|UNC\|LNC | 17 | 1 | TREATED | ME-SP/PT (Competitors, Mint, E1) | `272919287610543` | $0.39 | 0.04% | TREATED |
| LolliME | SP\|UNC\|LNC | 21 | 1 | TREATED | ME-SP/PHRASE (tween-girl-birthday-gift, Purple) | `130253181662559` | $0.01 | 0.00% | HOLDOUT |
| Lollibox | SB\|CAP\|GRD | 1 | 3 | TREATED | BOX- STORE/ BROAD | `424256831364046` | $54.50 | 5.07% | TREATED |
| Lollibox | SB\|CAP\|GRD | 2 | 3 | **HOLDOUT** | BOX-VIDEO/PT (Competitors, Purple, A1) | `27660342907703` | $49.47 | 4.60% | TREATED |
| Lollibox | SB\|CAP\|GRD | 3 | 3 | TREATED | BOX-SBS/BROAD (Hunter, By Age) | `501467313119574` | $32.43 | 3.01% | TREATED |
| Lollibox | SB\|UNC\|LNC | 2 | 1 | TREATED | BOX-VIDEO Competitor | `47108762429478` | $3.22 | 0.30% | HOLDOUT |
| Lollibox | SB\|UNC\|LNC | 6 | 1 | TREATED | BOX-VIDEO/ BROAD (Pink, gift) | `266634740728451` | $0.09 | 0.01% | TREATED |
| Lollibox | SP\|CAP\|GRD | 0 | 3 | TREATED | BOX-SP/BROAD (Hunter, Gift for Girl) | `200171414843593` | $78.46 | 7.30% | HOLDOUT |
| Lollibox | SP\|CAP\|GRD | 1 | 3 | TREATED | BOX-SP/AUTO (White) | `488973733209950` | $73.05 | 6.79% | HOLDOUT |
| Lollibox | SP\|CAP\|LNC | 1 | 3 | TREATED | BOX-SP/BROAD- gifts for girls 10-12 | `350259814389755` | $25.56 | 2.38% | HOLDOUT |
| Lollibox | SP\|UNC\|GRD | 3 | 0 | TREATED | BOX-SP/AUTO (Pink) | `193631713358335` | $11.10 | 1.03% | TREATED |
| Lollibox | SP\|UNC\|LNC | 5 | 1 | TREATED | BOX-SP/AUTO (Purple) | `172872442210536` | $5.39 | 0.50% | TREATED |
| Lollibox | SP\|UNC\|LNC | 6 | 1 | TREATED | BOX-SP/EXACT (teen-girl-gift, White 2) | `71460479938206` | $5.18 | 0.48% | TREATED |
| Lollibox | SP\|UNC\|LNC | 10 | 1 | TREATED | BOX -SP/AUTO (Blue) | `52908075625268` | $1.47 | 0.14% | TREATED |
| Lollibox | SP\|UNC\|LNC | 13 | 1 | TREATED | BOX-COMPETE (Copycat) | `358247566911916` | $0.80 | 0.07% | TREATED |
| Lollibox | SP\|UNC\|LNC | 20 | 1 | TREATED | BOX-SP/EXACT (tween-girl-gift, Blue) | `366680190861213` | $0.01 | 0.00% | TREATED |

---

## 4. Tasks

### Task 0: Ori's OK on the list (the gate)

- [x] Ori reads §3.1, §3.3 and the population note in §2.4, then answers **"OK"**, or names a change.
  Accepted changes are limited to the population (for example, keep Bunny out). Each one means a full
  re-draw by §2.5 from index 0 and a new fingerprint, never a hand swap of one campaign.
  **Done 2026-10-04.** After asking "explain seed 5", Ori wrote **"ok seed 5, deploy it"**. The list is
  approved unchanged.
- [x] Record his words and the date in HOLDOUT.md §9 and in the T2 `OPENED` row's `ruling` (Task 2).
  **Done 2026-10-04 (HOLDOUT.md §9).** The `ruling` the deploy writes is: `Ori 2026-10-03: restart
  from 2026-10-06 with a fresh draw by the same method. List approved by Ori on 2026-10-04: "ok seed 5,
  deploy it".` The literal is single-quoted, so his double quotes need no escape (Task 2, Step 3).
- [x] **If the OK comes after 2026-10-05 22:00 Los Angeles** (05:00 UTC on 10-06, the start of that
  night's first pass): every T2 date moves together by the number of days late. That covers
  `assigned_on`, `gate_from`, `win_start`, `win_end`, the interim look and `first_readout` (HOLDOUT.md
  §6, "move both dates together"). **Trial 1's `ARCHIVED.effective_on` moves with them**, so that it
  always equals T2's `gate_from` (review fix 4).
  - If it stayed at 10-05 while T2's gate opened later, no trial would bind on the days between.
  - T1's controls would be released early, and T2's controls would be open to books before their gate.
  - The list stays the same, and `assignment_rule` names the facts' date.
  - **Not needed:** the OK came on 2026-10-04, on time, so no date moves.

### Task 1: SOPs first

**Files:** `architecture/HOLDOUT.md`, `architecture/ENGINE_PREFLIGHT.md`, `architecture/ENGINE_HEALTH.md`,
`architecture/FAMILY_SEAT_REGISTER.md`, `architecture/NEXT_WEEK_MONEY.md` (the holdout passages),
`architecture/THREE_LAYERS.md`, `architecture/KEYWORD_STATE.md` (each names `DE_HOLDOUT_ASSIGNMENT`).

The SOPs land with the 2026-10-05 deploy, so they are written as the state from that day.

- [x] HOLDOUT.md:
  - §4: the objects table gains `DE_HOLDOUT_TRIAL`, `V_HOLDOUT_TRIAL`, `V_HOLDOUT_ARM` and (2026-10-04
    amendment) `DE_HOLDOUT_BASELINE`;
  - §5: gains the T2 seed and criteria;
  - §6: gains the alarm's blind spots, stated plainly (§2.7);
  - §8: gains the T2 dates and the former-T1-controls sensitivity row;
  - §9: reads "approved 2026-10-04, deploying 2026-10-05", with Ori's words (Task 9 turns it into
    "running");
  - the banner names the live trial.
- [x] The other SOPs (`ENGINE_PREFLIGHT.md`, `ENGINE_HEALTH.md` with c33's new terms as designed,
  `FAMILY_SEAT_REGISTER.md`, `NEXT_WEEK_MONEY.md`, `THREE_LAYERS.md`, `KEYWORD_STATE.md`): every
  "reads `DE_HOLDOUT_ASSIGNMENT`" becomes "reads `V_HOLDOUT_ARM` (the arm that binds today, any
  trial)". Dated records of past proofs keep the table they used. Nothing else changes.
- [x] Commit (targeted add). Done 2026-10-04, with this amendment.

### Task 2: The registry and its two views

**Files:** new `scripts/bigquery/tables/DE_HOLDOUT_TRIAL.sql`, new `views/V_HOLDOUT_TRIAL.sql`, new
`views/V_HOLDOUT_ARM.sql`, `config.yaml`, and new `scripts/bigquery/tables/DE_HOLDOUT_BASELINE.sql`
(added by the 2026-10-04 amendment, Step 3b).

- [ ] **Step 1: the table.**

```sql
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_HOLDOUT_TRIAL` (
  trial_id         STRING    NOT NULL,  -- = DE_HOLDOUT_ASSIGNMENT.trial_id
  event            STRING    NOT NULL,  -- 'OPENED' | 'ARCHIVED'
  effective_on     DATE      NOT NULL,  -- OPENED: gate_from, the LA day the arm starts to block exports; ARCHIVED: first LA day the trial no longer binds
  recorded_at      TIMESTAMP NOT NULL,
  seed             STRING,              -- OPENED: the seed its rows carry
  assigned_on      DATE,                -- OPENED: LA day of the founding insert
  win_start        DATE,                -- OPENED: = eligible_from of its rows (the estimate and R9 start here)
  win_end          DATE,                -- OPENED: = trial_end of its rows
  interim_look     DATE,                -- OPENED: the one-time safety look (HOLDOUT.md §8)
  first_readout    DATE,                -- OPENED: win_end + 14, never pulled forward
  t_mult           FLOAT64,             -- OPENED: the readout's band multiplier
  mde_ex_ante_14d  FLOAT64,             -- OPENED: the design's MDE per 14 days
  ruling           STRING,              -- who decided, when, in their words
  note             STRING               -- ARCHIVED: why, with the contamination numbers
)
OPTIONS (description = 'Which holdout trial is live, append-only: one row per event (OPENED / ARCHIVED). Never UPDATE or DELETE — a trial is archived by appending a row. Read by V_HOLDOUT_TRIAL. Spec: architecture/HOLDOUT.md §9; plan docs/superpowers/plans/2026-10-03-holdout-restart.md.');
```

- [ ] **Step 2: the views.**

```sql
CREATE OR REPLACE VIEW `onyga-482313.OI.V_HOLDOUT_TRIAL` AS
WITH
opened AS (
  SELECT * FROM `onyga-482313.OI.DE_HOLDOUT_TRIAL` WHERE event = 'OPENED'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY trial_id ORDER BY recorded_at DESC) = 1),
archived AS (
  SELECT trial_id, MIN(effective_on) AS archived_from,
         ARRAY_AGG(note ORDER BY recorded_at LIMIT 1)[OFFSET(0)] AS archive_note
  FROM `onyga-482313.OI.DE_HOLDOUT_TRIAL` WHERE event = 'ARCHIVED' GROUP BY 1),
today AS (SELECT CURRENT_DATE('America/Los_Angeles') AS d)
SELECT o.trial_id, o.seed, o.assigned_on, o.win_start, o.win_end, o.interim_look, o.first_readout,
       o.t_mult, o.mde_ex_ante_14d, o.ruling,
       o.effective_on AS gate_from,
       IF(a.archived_from IS NULL, o.win_end,
          LEAST(o.win_end, DATE_SUB(a.archived_from, INTERVAL 1 DAY))) AS gate_to,
       a.archived_from, a.archive_note,
       (a.archived_from IS NULL OR t.d < a.archived_from) AS is_live,
       CASE WHEN a.archived_from IS NOT NULL AND t.d >= a.archived_from THEN 'ARCHIVED'
            WHEN t.d < o.effective_on   THEN 'ASSIGNED'
            WHEN t.d <= o.win_end       THEN 'RUNNING'
            WHEN t.d < o.first_readout  THEN 'SETTLING'
            ELSE 'READ_OUT' END AS status_today
FROM opened o
LEFT JOIN archived a USING (trial_id)
CROSS JOIN today t;

CREATE OR REPLACE VIEW `onyga-482313.OI.V_HOLDOUT_ARM` AS
-- one row per HOLDOUT campaign whose arm binds today or later, any trial. The gate readers test
-- CURRENT_DATE('America/Los_Angeles') >= gate_from (and <= gate_to where they need it).
SELECT a.unit_id AS campaign_id,
       MIN(t.gate_from) AS gate_from,
       MAX(t.gate_to)   AS gate_to,
       ARRAY_AGG(a.trial_id ORDER BY t.gate_from DESC LIMIT 1)[OFFSET(0)] AS trial_id
FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT` a
JOIN `onyga-482313.OI.V_HOLDOUT_TRIAL` t USING (trial_id)
WHERE a.unit_type = 'CAMPAIGN' AND a.arm = 'HOLDOUT'
  AND CURRENT_DATE('America/Los_Angeles') <= t.gate_to
GROUP BY 1;
```

  `MIN`/`MAX` is safe because one trial's `gate_to` is the day before the next one's `gate_from`, so a
  campaign that is a control in both trials has one unbroken interval. None is today.

  **A trial with no `OPENED` row is invisible to the gate.** That is why T1's `OPENED` row is
  back-filled in the same step as its `ARCHIVED` row, and why the registry rows go in before any
  consumer switches (Task 8). An empty registry empties the gate. c33 then reads "no HOLDOUT unit" and
  goes RED (§2.7), so this failure cannot pass silently.

- [ ] **Step 3: the registry rows.** Ori's OK date and words were filled in on 2026-10-04 (Task 0).

```sql
INSERT INTO `onyga-482313.OI.DE_HOLDOUT_TRIAL`
  (trial_id, event, effective_on, recorded_at, seed, assigned_on, win_start, win_end,
   interim_look, first_readout, t_mult, mde_ex_ante_14d, ruling, note)
VALUES
  ('HOLDOUT-2026Q4-CAMPAIGN', 'OPENED', DATE '2026-09-01', CURRENT_TIMESTAMP(), 'OI-HOLDOUT-v1|14',
   DATE '2026-08-19', DATE '2026-09-01', DATE '2026-12-22', DATE '2026-11-10', DATE '2027-01-05', 3.27, 2261.0,
   'Ori 2026-08-18: "start the holdout." (v27.83)',
   'Back-filled 2026-10-05 from the SP_ASSIGN_HOLDOUT v27.83 constants; the 69 rows are unchanged.'),
  ('HOLDOUT-2026Q4-CAMPAIGN', 'ARCHIVED', DATE '2026-10-05', CURRENT_TIMESTAMP(), NULL, NULL, NULL, NULL,
   NULL, NULL, NULL, NULL,
   'Ori 2026-10-03: the holdout trial restarts (option (c)); keep the old trial on record, archived, with its contamination stated.',
   'CONTAMINATED. Since the assignment on 2026-08-19, 10 of the 14 HOLDOUT campaigns changed on Amazon: 7 between the assignment and the window start (25 ledger rows: the 08-21 pauses of 135553284530895 and 39989090923480, the 08-23 reprice book on 279837860088128, 446868628489343 and 75834491759416, unlogged changes on 200171414843593 and 488973733209950) and 8 inside the window (25 observed rows, none logged, first days 2026-09-10 .. 2026-09-27, among them the two pauses Ori made himself on 2026-09-27, 75834491759416 and 76054744633802). R9 as built censors 61 of 69 units (13 of 14 HOLDOUT, 48 of 55 TREATED). No estimate was read. Arms bound 2026-09-01 .. 2026-10-04. The 69 rows stay in DE_HOLDOUT_ASSIGNMENT unchanged (fingerprint 7298956708089075507). Record: architecture/HOLDOUT.md §6.'),
  ('HOLDOUT-2026Q4-CAMPAIGN-T2', 'OPENED', DATE '2026-10-05', CURRENT_TIMESTAMP(), 'OI-HOLDOUT-v2|5',
   DATE '2026-10-05', DATE '2026-10-06', DATE '2027-01-26', DATE '2026-12-15', DATE '2027-02-09', 3.27, 2089.0,
   'Ori 2026-10-03: restart from 2026-10-06 with a fresh draw by the same method. List approved by Ori on 2026-10-04: "ok seed 5, deploy it".',
   NULL);
```

  Inside a BigQuery string literal, a quote in Ori's words must be escaped as `\'` (or `\"`). The
  `ruling` literal is single-quoted, so the double quotes around his words need no escape.

- [ ] **Step 3b (amendment 2026-10-04, review fix 1): `DE_HOLDOUT_BASELINE`**, new file
  `scripts/bigquery/tables/DE_HOLDOUT_BASELINE.sql`. This is the stored value that kind-4 touches of §2.7
  are read against. Design, in words; the DDL is the builder's:
  - **Grain:** one row per (`trial_id`, `campaign_id`, `setting`) per recording. It is append-only, and
    c33 reads the latest row per key by `recorded_at`.
  - **Columns:**
    - `trial_id`, `campaign_id`, `setting`, `recorded_at`: NOT NULL;
    - `value`: STRING, the value as read. **NULL means absent.** Only a later re-baseline row may
      carry it, when Ori rules that a setting is gone;
    - `source`: the Fivetran table it was read from;
    - `source_synced_at`: that table's `MAX(_fivetran_synced)` at the read;
    - `ruling`: NULL on the founding rows. On a later row it carries Ori's words when he rules on an
      undated touch.
  - **`setting` keys:**
    - `SP_PLACEMENT|<placement>` = `percentage` from `campaign_placement_bidding`;
    - `SB_PLACEMENT|<placement>` = `percentage` from `sb_campaign_bid_adjustments_by_placement`;
    - `SB_SHOPPER_COHORT|<audience_id>|<shopper_cohort_type>` = `percentage` from
      `sb_campaign_bid_adjustments_shopper_cohort`;
    - `SB_TARGET|<id>|bid` and `SB_TARGET|<id>|state` from `sb_product_target`.
  - **What is present: the presence rule of §2.7 kind 4, on all four sources.** A row counts only when
    `_fivetran_synced >= MAX(_fivetran_synced)` of its own table minus 1 hour, and it is not
    `_fivetran_deleted` (only `sb_product_target` has that column). Every other row is absent. The
    founding insert (Task 3), c33's `BASELINE_DIFF` (Task 6) and K12 (§5) apply the same rule. Write it
    once, the same way, in all three.
  - **The founding rows record no absent setting.** A setting absent at the founding that is present
    later is a touch. A later row whose `value` is NULL records that the setting is absent from then
    on, and c33 compares it like any other value. An absent setting matches a NULL baseline, and a
    present one differs from it.
  - **Which controls it covers: kind 4's watched set (§2.7).** That is the trial's HOLDOUT units with
    `STARTS_WITH(assignment_rule, 'FOUNDING')`, read from `DE_HOLDOUT_ASSIGNMENT`, never from an id
    literal. A watched control is watched whether or not it has a baseline row. A founding control
    with no present setting gets no row and is still compared. A `LATE ARRIVAL` HOLDOUT unit gets no
    row and is unwatched on these settings. c33 names it by its `assignment_rule`, never because it
    has no baseline row.
  - **Who writes it:** the founding script (Task 3) writes the first rows, for the watched set only.
    Nothing else writes it except an appended re-baseline row carrying Ori's ruling, whose `value` is
    NULL when he accepts a removal.
  - **The house rules apply.** Register it in `config.yaml`. Its description says append-only, read by
    `V_ENGINE_HEALTH` c33, spec HOLDOUT.md §6.
  - **If it cannot be built and checked inside the deploy window,** deploy without it. Kind 4 then
    joins the blind spots of HOLDOUT.md §6, and c33's tail names those four sources as unwatched.
    Nothing else in the plan depends on it.
- [ ] **Step 4: checks K1, K2 and K6 (§5) with their NCs.** Register the objects in `config.yaml`
  (`depends_on`: the table, then `DE_HOLDOUT_ASSIGNMENT`). Commit.

### Task 3: The founding cohort, written once from the approved literal

**Files:** none new in the repo. The script lives in this plan and runs once. Its rows are the record.

- [ ] Run as one script, which writes 59 rows or nothing:

```sql
ASSERT (SELECT COUNT(*) FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`
        WHERE trial_id = 'HOLDOUT-2026Q4-CAMPAIGN-T2') = 0
  AS 'trial 2 already has rows: the founding insert runs once';
ASSERT (SELECT COUNTIF(is_live AND trial_id = 'HOLDOUT-2026Q4-CAMPAIGN-T2')
        FROM `onyga-482313.OI.V_HOLDOUT_TRIAL`) = 1
  AS 'trial 2 is not registered as the live trial (Task 2 first)';
CREATE TEMP TABLE v AS
SELECT * FROM UNNEST(ARRAY<STRUCT<unit_id STRING, unit_name STRING, arm STRING, stratum STRING,
  seq_in_stratum INT64, channel STRING, family STRING, is_capped BOOL, is_launch BOOL,
  spend_28d FLOAT64, gp_28d FLOAT64, net_28d FLOAT64>>[
  ('369056697567588', 'ME-VIDEO/BROAD (Hunter)', 'TREATED', 'SB|CAP|GRD', 0, 'SB', 'LolliME', TRUE, FALSE, 1693.58, 2272.3, 578.72),
  ('424256831364046', 'BOX- STORE/ BROAD', 'TREATED', 'SB|CAP|GRD', 1, 'SB', 'Lollibox', TRUE, FALSE, 1525.93, 1736.12, 210.19),
  ('27660342907703', 'BOX-VIDEO/PT (Competitors, Purple, A1)', 'HOLDOUT', 'SB|CAP|GRD', 2, 'SB', 'Lollibox', TRUE, FALSE, 1385.21, 745.73, -639.48),
  ('501467313119574', 'BOX-SBS/BROAD (Hunter, By Age)', 'TREATED', 'SB|CAP|GRD', 3, 'SB', 'Lollibox', TRUE, FALSE, 907.92, 799.09, -108.83),
  ('342313119548309', 'FRESH - SB\\BROAD (Hunter, FRESH)', 'TREATED', 'SB|CAP|LNC', 0, 'SB', 'Fresh', TRUE, TRUE, 1486.16, 1097.37, -388.79),
  ('537046793426450', 'ME-SBS/BROAD (Discovery, Journal)', 'HOLDOUT', 'SB|CAP|LNC', 1, 'SB', 'LolliME', TRUE, TRUE, 1380.97, 1078.29, -302.68),
  ('176884360124879', 'ME-VIDEO/PT (Competitors, Pink, D1)', 'TREATED', 'SB|CAP|LNC', 2, 'SB', 'LolliME', TRUE, TRUE, 506.17, 436.97, -69.2),
  ('446868628489343', 'FRESH-VIDEO/ BROAD', 'TREATED', 'SB|UNC|GRD', 0, 'SB', 'Fresh', FALSE, FALSE, 2375.81, 1455.48, -920.33),
  ('292848303399755', 'FRESH SP/BROAD (Hunter ,Pink, Gift)', 'TREATED', 'SB|UNC|GRD', 1, 'SB', 'Fresh', FALSE, FALSE, 1488.62, 833.73, -654.89),
  ('491652134548478', 'BRAND-STORE/BROAD (Me,Box,Bottle)', 'TREATED', 'SB|UNC|GRD', 2, 'SB', 'LolliME', FALSE, FALSE, 1034.45, 1076.07, 41.62),
  ('435692261851957', 'ME-VIDEO/EXACT (age8-14-girl-journal-diary, Purple)', 'TREATED', 'SB|UNC|GRD', 3, 'SB', 'LolliME', FALSE, FALSE, 524.11, 417.72, -106.39),
  ('274922784647676', 'BOTTLE-VIDEO/PT (Competitors, Truth Or Dare, E1)', 'TREATED', 'SB|UNC|LNC', 0, 'SB', 'Bottle', FALSE, TRUE, 225.31, 154.46, -70.85),
  ('107017178352577', 'BUNNY-VIDEO/BROAD (Hunter)', 'TREATED', 'SB|UNC|LNC', 1, 'SB', 'Bunny', FALSE, TRUE, 103.72, 26.16, -77.56),
  ('47108762429478', 'BOX-VIDEO Competitor', 'TREATED', 'SB|UNC|LNC', 2, 'SB', 'Lollibox', FALSE, TRUE, 90.09, 98.77, 8.68),
  ('66467422009617', 'BOTTLE-VIDEO/PT (Competitors, Truth Or Dare, D1)', 'TREATED', 'SB|UNC|LNC', 3, 'SB', 'Bottle', FALSE, TRUE, 19.7, 17.78, -1.92),
  ('71317833591283', 'BOTTLE-VIDEO/EXACT (social-game, Truth)', 'HOLDOUT', 'SB|UNC|LNC', 4, 'SB', 'Bottle', FALSE, TRUE, 18.67, 0.0, -18.67),
  ('26332659728861', 'ME-VIDEO/PT (Competitors, Pink, E1)', 'TREATED', 'SB|UNC|LNC', 5, 'SB', 'LolliME', FALSE, TRUE, 3.56, 0.0, -3.56),
  ('266634740728451', 'BOX-VIDEO/ BROAD (Pink, gift)', 'TREATED', 'SB|UNC|LNC', 6, 'SB', 'Lollibox', FALSE, TRUE, 2.53, 98.4, 95.87),
  ('200171414843593', 'BOX-SP/BROAD (Hunter, Gift for Girl)', 'TREATED', 'SP|CAP|GRD', 0, 'SP', 'Lollibox', TRUE, FALSE, 2196.89, 2087.63, -109.26),
  ('488973733209950', 'BOX-SP/AUTO (White)', 'TREATED', 'SP|CAP|GRD', 1, 'SP', 'Lollibox', TRUE, FALSE, 2045.43, 1454.26, -591.17),
  ('365568042533669', 'ME-COMPETE (Nollh Mint)', 'HOLDOUT', 'SP|CAP|GRD', 2, 'SP', 'LolliME', TRUE, FALSE, 1253.37, 1089.08, -164.29),
  ('531456687555062', 'ME-SP/PT (Conquest, Competitors)', 'TREATED', 'SP|CAP|LNC', 0, 'SP', 'LolliME', TRUE, TRUE, 1342.01, 1514.26, 172.25),
  ('350259814389755', 'BOX-SP/BROAD- gifts for girls 10-12', 'TREATED', 'SP|CAP|LNC', 1, 'SP', 'Lollibox', TRUE, TRUE, 715.65, 670.49, -45.16),
  ('51727823265377', 'MINT-SP/BROAD (Back to School)', 'HOLDOUT', 'SP|CAP|LNC', 2, 'SP', 'LolliME', TRUE, TRUE, 646.31, 663.0, 16.69),
  ('190387447939462', 'ME-SP/BROAD (Mint, journaling kit for g)', 'TREATED', 'SP|CAP|LNC', 3, 'SP', 'LolliME', TRUE, TRUE, 490.78, 541.41, 50.63),
  ('2626284884970', 'ME-SP/PT (Competitors, Mint, D3)', 'TREATED', 'SP|CAP|LNC', 4, 'SP', 'LolliME', TRUE, TRUE, 441.3, 242.25, -199.05),
  ('19013742686856', 'ME-SP/PT (Competitors, Mint, D1)', 'TREATED', 'SP|CAP|LNC', 5, 'SP', 'LolliME', TRUE, TRUE, 421.76, 471.75, 49.99),
  ('279837860088128', 'BOTTLE-SP/AUTO', 'TREATED', 'SP|CAP|LNC', 6, 'SP', 'Bottle', TRUE, TRUE, 413.65, 550.67, 137.02),
  ('130115986205897', 'ME-SP/EXACT (tween-girl-journal-diary, Purple)', 'HOLDOUT', 'SP|CAP|LNC', 7, 'SP', 'LolliME', TRUE, TRUE, 357.73, 323.11, -34.62),
  ('163079264356669', 'ME-SP/AUTO (Pink)', 'TREATED', 'SP|CAP|LNC', 8, 'SP', 'LolliME', TRUE, TRUE, 357.22, 442.83, 85.61),
  ('227290137740434', 'FRESH-SP/PT (Competitors, Pink, A1)', 'TREATED', 'SP|CAP|LNC', 9, 'SP', 'Fresh', TRUE, TRUE, 127.29, 61.83, -65.46),
  ('527422818407259', 'ME-SP/AUTO (Mint)', 'HOLDOUT', 'SP|UNC|GRD', 0, 'SP', 'LolliME', FALSE, FALSE, 961.64, 1172.93, 211.29),
  ('28526809722181', 'FRESH-SP/BROAD (Back to School)', 'TREATED', 'SP|UNC|GRD', 1, 'SP', 'Fresh', FALSE, FALSE, 714.56, 298.14, -416.42),
  ('158989642962021', 'ME-SP/AUTO (Purple)', 'TREATED', 'SP|UNC|GRD', 2, 'SP', 'LolliME', FALSE, FALSE, 450.55, 612.57, 162.02),
  ('193631713358335', 'BOX-SP/AUTO (Pink)', 'TREATED', 'SP|UNC|GRD', 3, 'SP', 'Lollibox', FALSE, FALSE, 310.8, 268.58, -42.22),
  ('104973644967484', 'ME-SP/PT (Competitors, Mint, B2)', 'TREATED', 'SP|UNC|GRD', 4, 'SP', 'LolliME', FALSE, FALSE, 143.39, 63.75, -79.64),
  ('271009556929636', 'FRESH -SP/AUTO (Purple)', 'HOLDOUT', 'SP|UNC|GRD', 5, 'SP', 'Fresh', FALSE, FALSE, 103.4, 95.92, -7.48),
  ('60344378778716', 'ME-SP/PHRASE (age8-14-girl-journal-diary, Mint)', 'TREATED', 'SP|UNC|LNC', 0, 'SP', 'LolliME', FALSE, TRUE, 293.49, 255.0, -38.49),
  ('185651228688176', 'FRESH -SP/AUTO (Pink)', 'TREATED', 'SP|UNC|LNC', 1, 'SP', 'Fresh', FALSE, TRUE, 274.67, 369.46, 94.79),
  ('146179760782525', 'BUNNY-SP/BROAD (Hunter, Gift for Girl , keychain)', 'TREATED', 'SP|UNC|LNC', 2, 'SP', 'Bunny', FALSE, TRUE, 223.57, 114.93, -108.64),
  ('112036454757078', 'BUNNY-SP/AUTO (Brave)', 'TREATED', 'SP|UNC|LNC', 3, 'SP', 'Bunny', FALSE, TRUE, 210.87, 65.4, -145.47),
  ('273898143987321', 'BUNNY-SP/AUTO (Birthday)', 'HOLDOUT', 'SP|UNC|LNC', 4, 'SP', 'Bunny', FALSE, TRUE, 157.34, 203.35, 46.01),
  ('172872442210536', 'BOX-SP/AUTO (Purple)', 'TREATED', 'SP|UNC|LNC', 5, 'SP', 'Lollibox', FALSE, TRUE, 150.89, 107.16, -43.73),
  ('71460479938206', 'BOX-SP/EXACT (teen-girl-gift, White 2)', 'TREATED', 'SP|UNC|LNC', 6, 'SP', 'Lollibox', FALSE, TRUE, 144.98, 12.75, -132.23),
  ('67504198774096', 'FRESH-SP/AUTO (Blue)', 'TREATED', 'SP|UNC|LNC', 7, 'SP', 'Fresh', FALSE, TRUE, 83.7, 20.61, -63.09),
  ('275295641745590', 'ME-SP/PHRASE (tween-girl-birthday-gift, Purple 3)', 'TREATED', 'SP|UNC|LNC', 8, 'SP', 'LolliME', FALSE, TRUE, 79.13, 51.0, -28.13),
  ('230219410635024', 'ME-SP/PT (Competitors, Mint, D2)', 'HOLDOUT', 'SP|UNC|LNC', 9, 'SP', 'LolliME', FALSE, TRUE, 45.83, 25.5, -20.33),
  ('52908075625268', 'BOX -SP/AUTO (Blue)', 'TREATED', 'SP|UNC|LNC', 10, 'SP', 'Lollibox', FALSE, TRUE, 41.28, 102.76, 61.48),
  ('43890791772293', 'ME-SP/PT (Competitors, Mint, A1)', 'TREATED', 'SP|UNC|LNC', 11, 'SP', 'LolliME', FALSE, TRUE, 32.61, 12.75, -19.86),
  ('3918431774030', 'BOTTLE- COPYCAT', 'TREATED', 'SP|UNC|LNC', 12, 'SP', 'Bottle', FALSE, TRUE, 31.59, 8.89, -22.7),
  ('358247566911916', 'BOX-COMPETE (Copycat)', 'TREATED', 'SP|UNC|LNC', 13, 'SP', 'Lollibox', FALSE, TRUE, 22.38, 20.61, -1.77),
  ('222497123677300', 'ME-SP/PT (Competitors, Mint, C2)', 'HOLDOUT', 'SP|UNC|LNC', 14, 'SP', 'LolliME', FALSE, TRUE, 15.86, 38.25, 22.39),
  ('224831787476880', 'FRESH-SP/EXACT (teen-girl-gift, Fresh)', 'TREATED', 'SP|UNC|LNC', 15, 'SP', 'Fresh', FALSE, TRUE, 12.8, 0.0, -12.8),
  ('32239413784257', 'ME-SP/EXACT (kid-girl-birthday-gift, Purple)', 'TREATED', 'SP|UNC|LNC', 16, 'SP', 'LolliME', FALSE, TRUE, 12.19, 0.0, -12.19),
  ('272919287610543', 'ME-SP/PT (Competitors, Mint, E1)', 'TREATED', 'SP|UNC|LNC', 17, 'SP', 'LolliME', FALSE, TRUE, 11.04, 0.0, -11.04),
  ('206332152032611', 'BUNNY-SP/EXACT (backpack charms for girls)', 'TREATED', 'SP|UNC|LNC', 18, 'SP', 'Bunny', FALSE, TRUE, 2.63, 0.0, -2.63),
  ('53343800376430', 'BOTTLE-SP/PHRASE (tween-girl-birthday-gift, Truth)', 'HOLDOUT', 'SP|UNC|LNC', 19, 'SP', 'Bottle', FALSE, TRUE, 0.7, 0.0, -0.7),
  ('366680190861213', 'BOX-SP/EXACT (tween-girl-gift, Blue)', 'TREATED', 'SP|UNC|LNC', 20, 'SP', 'Lollibox', FALSE, TRUE, 0.3, 0.0, -0.3),
  ('130253181662559', 'ME-SP/PHRASE (tween-girl-birthday-gift, Purple)', 'TREATED', 'SP|UNC|LNC', 21, 'SP', 'LolliME', FALSE, TRUE, 0.25, 0.0, -0.25)]);
ASSERT (SELECT COUNT(*) = 59 AND COUNTIF(arm = 'HOLDOUT') = 12
          AND FARM_FINGERPRINT(STRING_AGG(FORMAT('%s|%s|%s|%d', unit_id, arm, stratum, seq_in_stratum), ','
                                          ORDER BY unit_id)) = 4171456845817687166
        FROM v) AS 'the literal is not the approved list';
ASSERT (SELECT COUNTIF(arm != IF(MOD(seq_in_stratum + MOD(ABS(FARM_FINGERPRINT(CONCAT('OI-HOLDOUT-v2|5', '|', stratum))), 5), 5) = 0,
                                 'HOLDOUT', 'TREATED')) FROM v) = 0
  AS 'an arm does not follow the rule';
INSERT INTO `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`
  (trial_id, unit_type, unit_id, unit_name, arm, stratum, seq_in_stratum, seed,
   assigned_at, eligible_from, trial_end, channel, family, is_capped, is_launch,
   spend_28d_at_assign, gp_28d_at_assign, net_28d_at_assign, assignment_rule)
SELECT 'HOLDOUT-2026Q4-CAMPAIGN-T2', 'CAMPAIGN', unit_id, unit_name, arm, stratum, seq_in_stratum,
       'OI-HOLDOUT-v2|5', CURRENT_TIMESTAMP(), DATE '2026-10-06', DATE '2027-01-26',
       channel, family, is_capped, is_launch, spend_28d, gp_28d, net_28d,
       FORMAT('FOUNDING (approved list): systematic 1-in-5 within stratum ordered by spend_28d DESC; offset %d from seed OI-HOLDOUT-v2|5 (first seed_index passing A1-A3); facts as of FACT anchor 2026-10-02, read 2026-10-03',
              MOD(ABS(FARM_FINGERPRINT(CONCAT('OI-HOLDOUT-v2|5', '|', stratum))), 5))
FROM v;
```

  Verified read-only on 2026-10-03: the `UNNEST` literal parses, gives 59 rows and 12 controls, has
  fingerprint `4171456845817687166`, 0 arm mismatches, a share of 0.2101 and 5 of 5 families. One
  campaign name contains a backslash (`FRESH - SB\BROAD (Hunter, FRESH)`), and the literal escapes it.

- [ ] **The baseline (amendment 2026-10-04).** The same script then appends the `DE_HOLDOUT_BASELINE`
  rows (Task 2, Step 3b) for the watched set: the 12 HOLDOUT units it has just written with a
  `FOUNDING` `assignment_rule`, read back from `DE_HOLDOUT_ASSIGNMENT` rather than from an id literal.
  The same script reads them from the four sources **by the presence rule of §2.7 kind 4**. It then
  asserts that their number equals a re-read of those sources for the same 12 campaigns, by the same
  rule.
  - Measured 2026-10-04 at the 02:14 UTC sync (Appendix C11): 15 settings on 8 controls. 7 controls
    carry placement rows (6 of them non-zero), 1 carries a shopper-cohort row and 1 (`27660342907703`)
    carries an SB product target.
  - Four controls carry none. Absence is recorded as absence. ME-COMPETE `365568042533669` is one of
    the four: its two rows have not been re-stamped since 2026-06-23, so they are absent under the rule.
    Read without the rule, the same insert would write 17 rows on 9 controls, ME-COMPETE's two removed
    adjustments among them (Appendix C12).
  - If this insert fails, the founding rows stand, because they are the record. Run the baseline
    insert again on its own, before Task 4.
- [ ] Checks K2, K3, K4, K5 and K12 with their NCs.

### Task 4: The assignment procedure and the population view follow the live trial

**Files:** `procedures/SP_ASSIGN_HOLDOUT.sql`, `views/V_HOLDOUT_ELIGIBLE.sql`.

- [ ] `SP_ASSIGN_HOLDOUT`: replace the four trial constants with the live trial's row, and refuse an
  empty trial. The `INSERT … WITH assigned/used/fresh/seq` body stays byte for byte, with `c_trial_id`
  → `t.trial_id`, `c_seed` → `t.seed`, `c_eligible_from` → `t.win_start` and `c_trial_end` →
  `t.win_end`. `assignment_rule` is prefixed `'LATE ARRIVAL (first sight): '`.

```sql
  DECLARE c_unit_type STRING DEFAULT 'CAMPAIGN';
  DECLARE c_every     INT64  DEFAULT 5;
  DECLARE t STRUCT<trial_id STRING, seed STRING, win_start DATE, win_end DATE>;
  SET t = (SELECT AS STRUCT trial_id, seed, win_start, win_end
           FROM `onyga-482313.OI.V_HOLDOUT_TRIAL` WHERE is_live
           QUALIFY ROW_NUMBER() OVER (ORDER BY assigned_on DESC, trial_id DESC) = 1);
  -- A founding cohort is written once, from the list Ori approved (plan 2026-10-03, Task 3), never by
  -- this procedure. No live trial, or a live trial with no rows yet: write nothing.
  IF t.trial_id IS NULL
     OR (SELECT COUNT(*) FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT` WHERE trial_id = t.trial_id) = 0 THEN
    RETURN;
  END IF;
```

- [ ] `V_HOLDOUT_ELIGIBLE`: change `NOT IN ('Bunny', 'LolliBall')` to `NOT IN ('LolliBall')`. Add a
  comment: re-graded on T2's design date 2026-10-03, Bunny OK (159.4 days binding cover, 6,000 units
  arriving 10-07) and LolliBall CRITICAL (21.6 days). It stays a frozen literal for the reason in the
  header.
- [ ] **Deploy order (review fix 3): `SP_ASSIGN_HOLDOUT` first, then `V_HOLDOUT_ELIGIBLE`, and both
  only after Task 3.**
  - **Why:** the deployed `SP_ASSIGN_HOLDOUT` carries T1's constants and appends every eligible
    campaign it does not find among T1's rows.
  - If the new view went first, the 5 Bunny campaigns would become eligible to the old procedure. Its
    next run, from a pass or a hand `CALL`, would append them to **trial 1**. That append is permanent,
    because the table is append-only, and it would break K2 (T1's 69-row fingerprint) for good.
  - With the new procedure in place first, it reads the live trial (T2, after Task 2), finds T2's
    founding rows (after Task 3), and treats only campaigns outside the 59 as late arrivals. Under the
    old view or the new one, every campaign eligible on 10-03 is already one of the 59.
  - The new procedure needs `V_HOLDOUT_TRIAL` to exist, so it cannot go before Task 2. Before Task 3 it
    would find T2 live with no rows and write nothing (its guard).
  - No pass may run between the two deploys: Task 8's window.
- [ ] **Check after the first pass that runs it:** K2, K3 and K4 still read 0. Any new T2 row is a
  `LATE ARRIVAL` whose `seq_in_stratum` continues its stratum (K4).
- [ ] Commit.

### Task 5: The gate readers read `V_HOLDOUT_ARM`

**Files:** `procedures/SP_ENGINE_PREFLIGHT.sql`, `views/V_PLAN_WINDOW_JUDGMENT.sql`,
`views/V_FAMILY_SEAT_REGISTER.sql`, `tools/build_reprice_bulksheet.py`,
`tools/build_seasonal_unpause_bulksheet.py`, `tools/build_seat_moves_bulksheet.py`.

Each edit replaces one CTE body and keeps its column names, so nothing downstream changes.

- [ ] `SP_ENGINE_PREFLIGHT`, CTE `hold`:

```sql
  hold AS (
    SELECT campaign_id AS cid, trial_id
    FROM `onyga-482313.OI.V_HOLDOUT_ARM`
    WHERE CURRENT_DATE('America/Los_Angeles') BETWEEN gate_from AND gate_to
  ),
```

- [ ] `V_PLAN_WINDOW_JUDGMENT` `holdout` and `V_FAMILY_SEAT_REGISTER` `holdout`, which keep their own
  column names (`cid` / `campaign_id`, `eligible_from`):

```sql
holdout AS (
  SELECT campaign_id AS cid, gate_from AS eligible_from      -- V_FAMILY_SEAT_REGISTER: campaign_id AS campaign_id
  FROM `onyga-482313.OI.V_HOLDOUT_ARM`
),
```

- [ ] The three tools, all four `hold` CTEs:

```sql
hold AS (  -- the arm that binds today or later (V_HOLDOUT_ARM); eligible_from = the gate date
  SELECT campaign_id cid, gate_from eligible_from
  FROM `{p}.OI.V_HOLDOUT_ARM`
),
```

- [ ] Python tests: `python3 -m pytest tools/tests/test_seat_moves.py tools/tests/test_seasonal_unpause.py -q`.
- [ ] Checks K6, K7, K8 and K9 with their NCs. Record the slot-seconds of one read each of
  `V_PLAN_WINDOW_JUDGMENT` and `V_FAMILY_SEAT_REGISTER` before and after.
- [ ] Commit.

### Task 6: The readout and the board follow the live trial; c33 alarms on a touch

**Files:** `views/V_HOLDOUT_READOUT.sql`, `views/V_ENGINE_HEALTH.sql`.

- [ ] `V_HOLDOUT_READOUT`, CTE `k`. The rest of the body is unchanged because the column names are the
  same. The header's T1 numbers move under a "trial 1 (archived)" heading, and the T2 dates and MDE are
  added.

```sql
k AS (
  SELECT trial_id, win_start, win_end, first_readout, t_mult, mde_ex_ante_14d
  FROM `onyga-482313.OI.V_HOLDOUT_TRIAL`
  WHERE is_live
  QUALIFY ROW_NUMBER() OVER (ORDER BY assigned_on DESC, trial_id DESC) = 1
),
```

- [ ] `V_ENGINE_HEALTH` c18: `JOIN V_HOLDOUT_ARM h ON h.campaign_id = c.campaign_id`, with
  `DATE(c.applied_at, 'America/Los_Angeles') BETWEEN h.gate_from AND h.gate_to`. The detail prints
  `MIN(gate_from)` from `V_HOLDOUT_ARM`.
- [ ] `V_ENGINE_HEALTH` c33:

```sql
hu_trial AS (  -- the live trial: the row V_HOLDOUT_READOUT's k reads
  SELECT trial_id FROM `onyga-482313.OI.V_HOLDOUT_TRIAL` WHERE is_live
  QUALIFY ROW_NUMBER() OVER (ORDER BY assigned_on DESC, trial_id DESC) = 1),
hu_asg AS (  -- the trial's units, both arms; assignment_rule decides which controls kind 4 watches
  SELECT a.unit_id, a.unit_name, a.arm, a.stratum, a.eligible_from, a.trial_end, a.assigned_at,
         a.assignment_rule
  FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT` a JOIN hu_trial USING (trial_id)
  WHERE a.unit_type = 'CAMPAIGN'),
-- (hu_chg, hu_led, hu_pre, hu_cens, hu_pre_ro, hu_obs, hu_gap, hu_pre_gap unchanged)
hu_touch AS (  -- every change on a HOLDOUT unit of the live trial from its assignment day on
  SELECT unit_id, unit_name, change_day FROM hu_led
  UNION ALL SELECT unit_id, unit_name, change_day FROM hu_pre),
hu_live AS (   -- the path a console change takes to this check, each stamp's age in hours
  SELECT
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), (SELECT MAX(started_at) FROM `onyga-482313.OI.LOG_PIPELINE_RUNS`
      WHERE procedure_name = 'SP_RECORD_OBSERVED_CHANGES' AND status = 'OK'), HOUR) AS h_record,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), (SELECT MAX(started_at) FROM `onyga-482313.OI.LOG_PIPELINE_RUNS`
      WHERE procedure_name = 'SP_LOAD_DIM_KEYWORD' AND status = 'OK'), HOUR) AS h_dimk,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), (SELECT MAX(_fivetran_synced)
      FROM `onyga-482313.OI.V_SRC_AmazonAds_keyword`), HOUR) AS h_mirror),
```

  The status becomes:

```sql
    CASE WHEN (SELECT COUNTIF(arm = 'HOLDOUT') FROM hu_asg) = 0 THEN 'RED'
         WHEN (SELECT n FROM hu_obs) = 0 THEN 'RED'
         WHEN (SELECT COUNT(*) FROM hu_gap) + (SELECT COUNT(*) FROM hu_pre_gap) > 0 THEN 'RED'
         WHEN (SELECT MAX(change_day) FROM hu_touch)
                >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY) THEN 'RED'
         WHEN (SELECT COALESCE(GREATEST(h_record, h_dimk, h_mirror), 999) FROM hu_live) > 36 THEN 'RED'
         WHEN (SELECT COUNT(*) FROM hu_touch) > 0 THEN 'AMBER'
         ELSE 'GREEN' END
```

  - `measured` = `hu_gap` + `hu_pre_gap` + the number of distinct controls touched in the last 7 days.
  - The detail leads with `TOUCHED: <name> (<id>) on <day>` for each recent touch, then the feed's
    ages. The "A RULING FOR ORI" clause becomes "published, not censored (pre-declared for T2, plan
    2026-10-03 §2.3)".
  - **Measured fact for the NC:** on T1's live inputs on 2026-10-03, the new term reads RED. The latest
    touch is 2026-09-27, 6 days old.
  - **Answered 2026-10-04:** the deployed `V_SRC_AmazonAds_keyword` unions `keyword_history` (SP
    keywords), `sb_keyword` (SB keywords) and `targeting_clause_history` (SP product targets). It does
    not include `sb_product_target`. The single `h_mirror` age above is replaced by the per-table ages
    below.

- [ ] **c33 widened (amendment 2026-10-04; review fixes 1 and 2; design in §2.7).** This replaces the
  `hu_touch` / `hu_live` sketch above where the two differ.
  - **`hu_touch` takes the four kinds of §2.7**, each a row of (`unit_id`, `unit_name`, `kind`,
    `change_day`, `what`). `change_day` is NULL for kind 4.
    1. `LEDGER`: `hu_led` ∪ `hu_pre`, as above.
    2. `NEW_ENTITY`: the first `DIM_KEYWORD` version of a `keyword_id`, or the first `DIM_AD_GROUP`
       version of an `ad_group_id`, on a HOLDOUT unit, with LA day ≥ the unit's assignment day.
    3. `CAMPAIGN_ATTR`: `DIM_CAMPAIGN` version pairs on a HOLDOUT unit where `portfolio_id` or
       `bidding_strategy` differs, plus `fivetran-hl.amazon_ads.sb_campaign_history` version pairs
       where `bid_optimization` or `bid_optimization_strategy` differs. Both use LA day ≥ the
       assignment day, ordered as `V_AMAZON_OBSERVED_CHANGES` orders versions.
    4. `BASELINE_DIFF`: today's **present** settings from the four current-state sources, by the
       presence rule of §2.7 kind 4, **for the watched set only**, full-outer-joined to the latest
       `DE_HOLDOUT_BASELINE` row per (`trial_id`, `campaign_id`, `setting`) for the live trial, where
       the two sides differ. `IS DISTINCT FROM` treats a setting on one side only as a difference. A
       baseline whose latest `value` is NULL means absent, so an absent setting matches it and a
       present one differs from it.
       - **The watched set** is the live trial's HOLDOUT units with
         `STARTS_WITH(assignment_rule, 'FOUNDING')`, whether or not they have a baseline row (§2.7). It
         is derived from `hu_asg`, so K7's count of one `DE_HOLDOUT_ASSIGNMENT` reference in
         `V_ENGINE_HEALTH` stands.
       - **Unwatched:** every other HOLDOUT unit of the live trial (a `LATE ARRIVAL`). It is named in
         the detail by its `assignment_rule`, never because it has no baseline row, and it is never
         compared.
       - **The text,** as tested on copies (Appendix C12). It names no campaign id:

```sql
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
```

       The baseline side is not restricted to the watched set. Only the founding script and Ori's
       re-baseline rows write the table, so every baseline row belongs to a watched control. If the
       watched set were ever empty, its baseline rows would each read as a difference, RED.
  - **`hu_live` reads fifteen ages:** the four procedures' last OK runs, and `MAX(_fivetran_synced)` of
    each of the eleven Fivetran tables listed in §2.7, each read by name. Read them from the Fivetran
    tables themselves, as the `V_SRC_` views do: no OI view tells the three keyword tables apart.
  - **Status** (first match wins):
    1. RED on: no HOLDOUT unit; an empty observed ledger; `hu_gap` / `hu_pre_gap` > 0; a dated touch
       (kinds 1–3) 7 or fewer LA days old; a standing `BASELINE_DIFF`; any age > 36 hours or missing;
    2. else AMBER on: any dated touch ever; a re-baselined setting (more than one baseline row for a
       key); `hu_pre` > 0;
    3. else GREEN.
  - **`measured`** = `hu_gap` + `hu_pre_gap` + the distinct controls with a RED-making touch.
  - **The detail:**
    - one `TOUCHED:` clause per touch: kind, unit, day (or "date unknown: the source keeps no
      history"), and what changed;
    - for kinds 2–4, "seen by the alarm, not censored by R9 — Ori to rule";
    - then every age, with any stale one named;
    - each row of `hu_k4_unwatched` (a `LATE ARRIVAL` control, by its `assignment_rule`) is named as
      unwatched on kind-4 settings. A founding control is never named unwatched, whether or not it
      has baseline rows. An unwatched control does not change the status by itself;
    - **the standing tail, on every read:** "not seen by any source: negatives (mirrors frozen since
      2026-01-03), ads and creatives (frozen since 2025-12-28 .. 2026-01-03), a change undone before
      the next sync".
  - **Cost:** the new reads are small. The largest is `DIM_KEYWORD` grouped by `keyword_id`. The
    Fivetran tables read here hold at most 38,697 rows (`keyword_history`), and the ages read one
    column. Measure the board filtered to c33 twice, before and after, as the first step says.
  - **Keep `V_ENGINE_HEALTH` under the view-body ceiling** (`view_body_headroom`). If the new text
    would push it past AMBER, move the touch inputs into a small view, `V_HOLDOUT_TOUCH`, that c33
    reads. HOLDOUT_INTEGRITY H4 then runs that view's text on copies, and K7 gives that view its own
    count of `DE_HOLDOUT_ASSIGNMENT` references.
- [ ] Measure the slot-seconds of the board filtered to c33, two runs. Commit.

### Task 7: Acceptance

**Files:** new `scripts/bigquery/tests/HOLDOUT_RESTART_acceptance.sql` (K1–K12, §5),
`tests/HOLDOUT_INTEGRITY_acceptance.sql`, `tests/V_FAMILY_SEAT_REGISTER_acceptance.sql`.

- [ ] `HOLDOUT_INTEGRITY_acceptance.sql`:
  - `hu_asg` and the pasted c33 text follow Task 6 verbatim;
  - H3's gate date reads `first_readout` from `V_HOLDOUT_TRIAL`;
  - **H4 (touch alarm)**, on doctored inputs: an observed change on a T2 control dated today reads RED
    with measured ≥ 1; the same change dated today − 8 reads AMBER; no change reads GREEN;
  - **H5 (feed liveness)**: a `LOG_PIPELINE_RUNS` copy with no OK `SP_RECORD_OBSERVED_CHANGES` run in
    36 hours reads RED, and the live log reads not-RED on that term.
  - **H4 widened (amendment 2026-10-04).** One doctored input per new kind, each on a T2 control:
    - a `DIM_KEYWORD` copy with a new `keyword_id` whose first version is today reads RED. The same
      first version dated before the assignment reads GREEN;
    - a `DIM_CAMPAIGN` copy with a portfolio change today reads RED;
    - an `sb_campaign_history` copy with a `bid_optimization` flip today reads RED;
    - a `DE_HOLDOUT_BASELINE` copy with one placement value altered reads RED while it stands. With a
      later re-baseline row carrying a `ruling`, it reads AMBER;
    - **How the kind-4 inputs run (second follow-up 2026-10-04).** Each runs c33's deployed text with
      its table names pointed at `TMP_HT2_` copies: the four sources, `DE_HOLDOUT_BASELINE`,
      `DE_HOLDOUT_ASSIGNMENT` (with T2's founding rows) and the registry with `V_HOLDOUT_TRIAL`. The
      text that is run carries **no campaign-id literal**, so the watched set comes from the
      assignment copy exactly as it will on the board. Only the doctoring statements name an id.
      Appendix C12 gives the `BASELINE_DIFF` count each input must reproduce;
    - **the watched set (second follow-up 2026-10-04):**
      - a `campaign_placement_bidding` copy with a present ME-COMPETE `365568042533669`
        `PLACEMENT_TOP` 30 row added (stamped at the table's latest sync) reads RED, with
        `BASELINE_DIFF` 1, although ME-COMPETE has no baseline row;
      - an assignment copy with one `LATE ARRIVAL` HOLDOUT row added for an SB campaign that carries
        present 0% SB placement rows reads not-RED on this term. The detail names that campaign as
        unwatched;
    - **the presence rule (follow-up 2026-10-04).** These inputs use the copies above, and
      Appendix C12 gives the `BASELINE_DIFF` counts each must reproduce:
      - a `campaign_placement_bidding` copy in which one control's row is not re-stamped (its stamp
        moved one sync back) reads RED, as a removal;
      - the same copy with a re-baseline row whose `value` is NULL reads AMBER;
      - a copy with the stale rows deleted reads not-RED on this term, because a re-sync that drops
        stale rows is not a touch;
    - every one of these RED details carries "not censored by R9".
  - **H5 widened.** For each of the four procedures, a log copy with no OK run in 36 hours reads RED.
    For each of the eleven Fivetran tables, a one-column copy holding only a `_fivetran_synced` 37
    hours old, swapped in for that table alone, reads RED and names that table. The live sources read
    not-RED.
- [ ] `V_FAMILY_SEAT_REGISTER_acceptance.sql` line 350: `holdout` reads `V_HOLDOUT_ARM`.
- [ ] `PLAN_OWNERSHIP_acceptance.sql` is untracked and belongs to another session. Do not touch it. Hand
  its owner the one-line change: `hold_open` reads `V_HOLDOUT_ARM` between `gate_from` and `gate_to`.
- [ ] Run all three files and record the results in their headers. Commit.

### Task 8: Deploy order and timing (2026-10-05). Rewritten 2026-10-04 (review fix 5)

**The runbook** is `scripts/bigquery/migrations/2026-10-05_holdout_t2_deploy.sh` (Task R). It runs steps
1–5 below in order, stops at the first failure, and records each check's result.

**Measured pass times.** These come from `LOG_PIPELINE_RUNS`: the 21 passes from 2026-09-27 05:00 to
2026-10-03 16:47 UTC, 7 in each slot (query in Appendix C). All times are UTC start times, except the
last column.

| pass | starts | `SP_RECORD_OBSERVED_CHANGES` | `SP_ASSIGN_HOLDOUT` | `SP_ENGINE_PREFLIGHT` | `SP_BUILD_NEXT_WEEK_PLAN` | `SP_REFRESH_CUBE_TABLES` | ends (last step finished) |
|---|---|---|---|---|---|---|---|
| 1 | 05:00 | 05:02 | 05:23–05:28 | 05:29–05:41 | 05:32–05:43 | 05:33–05:45 | 05:50–06:19 |
| 2 | 07:35 | 07:37–07:38 | 07:54–08:01 | 08:03–08:20 | 08:04–08:21 | 08:06–08:24 | 08:19–08:55 |
| 3 | 16:00 | 16:02–16:03 | 16:21–16:37 | 16:31–16:57 | 16:33–17:02 | 16:35–17:04 | 16:46–17:37 |

- **The same passes in other zones.** New York: 01:00, 03:35 and 12:00 (EDT). Los Angeles: pass 1 is
  22:00 of the *previous* LA day, pass 2 is 00:35 and pass 3 is 09:00.
- `SP_RECORD_OBSERVED_CHANGES` has logged only since 10-02, so its times come from 6 runs.
- The first version of this task said "about 05:20, 07:55 and 16:30". Those are `SP_ASSIGN_HOLDOUT`'s
  times, not the passes'.

**The window is Los Angeles date 2026-10-05.** No pass may start while a step is half-done. A pass that
read the new `V_HOLDOUT_ELIGIBLE` under the old `SP_ASSIGN_HOLDOUT` is exactly the irreversible case of
Task 4.

- **Primary window.**
  - Start after pass 2 of 10-05 has finished. Confirm its last step in `LOG_PIPELINE_RUNS`; the latest
    measured end is 08:55 UTC.
  - Finish before pass 3 starts at 16:00 UTC. **Stop by 15:40 UTC.** Whatever is not done by then waits
    for the fallback.
  - Pass 3 of 10-05 (09:00 LA) is then the first pass gated for T2 **for the preflight and the
    register image** (K8, K9b). It does not apply to `FACT_PLAN_NEXT_WEEK`: pass 3 finds the `as_of`
    10-05 night already written and FROZEN, and writes nothing (below). The first plan partition
    gated for T2 is `as_of` 10-06, written by pass 1 of 10-06 (K9).
- **Fallback window.**
  - Start after pass 3 of 10-05 has finished. Confirm it; the latest measured end is 17:37 UTC.
  - Finish by **04:40 UTC on 10-06**. Pass 1 of 10-06 starts at 05:00 UTC, which is 22:00 LA on 10-05.
    It judges under LA 10-05 and builds the book uploaded on 10-06, so it must run on the deployed
    code.
  - Pass 1 of 10-06 is then the first pass gated for T2, for all three snapshots (K8, K9, K9b).
- **If both windows are missed,** every T2 date shifts by a day, and so does T1's archive date
  (Task 0), before step 1.
- **Pass 2 of 10-05 runs before the deploy,** at 00:35 LA on 10-05, on the old code. Its outputs carry
  T2 controls unblocked and T1 controls still held. Hence the upload rule below.
- **Pass 1 of 10-05 writes the `as_of` 10-05 plan partition on the old code,** at 22:00 LA on 10-04,
  before either window opens. From LA midnight that night is frozen (below), and it stays the latest
  partition until pass 1 of 10-06 writes `as_of` 10-06.

| step | when | what |
|---|---|---|
| 0 | done 2026-10-04 | Task 0 (OK), Task 1 (SOPs) |
| 1 | the window opens | Task 2: the tables (`DE_HOLDOUT_TRIAL`, `DE_HOLDOUT_BASELINE`), registry rows, views. K1, K2, K6 |
| 2 | right after | Task 3: the founding insert, then the baseline. K3, K4, K5, K12 |
| 3 | right after | Task 4: `SP_ASSIGN_HOLDOUT` **first**, then `V_HOLDOUT_ELIGIBLE` (review fix 3) |
| 4 | right after | Task 5: preflight, judgment, register, tools. K7 |
| 5 | right after | Task 6: readout, board. Task 7 acceptance |
| 6 | by 15:40 UTC (primary) or 04:40 UTC 10-06 (fallback) | the runbook ends. The next pass is the first one gated for T2 for the preflight and the register image (K8, K9b). For `FACT_PLAN_NEXT_WEEK` the first is pass 1 of 10-06 in either window (K9) |

**The two snapshot tables keep T1's holds until a pass rebuilds them** (§1 rows 15 and 16).

- **`T_FAMILY_SEAT_REGISTER`** is rebuilt by `SP_REFRESH_CUBE_TABLES` in every pass (OK in all 21
  passes measured). Until it next runs, `V_DAILY_BRIEF`, `V_RUN_SUMMARY`, the `seat_*` checks and the
  cube mark T1's controls as holdout and T2's as ordinary campaigns.
  - **Check it after the first gated pass.** In the image, every T2 control has `holdout = TRUE` and no
    T1-only control does.
- **`FACT_PLAN_NEXT_WEEK`** gets a new partition only when `SP_BUILD_NEXT_WEEK_PLAN` logs OK **and
  is not FROZEN**. Corrected 2026-10-04 (review of G5): the first version said "only when it logs OK".
  - `as_of` is the New York date (v27.160). Once a partition for that `as_of` exists and LA midnight
    of the `as_of` has passed, the step does not rewrite it (FROZEN, v27.170; live v27.171, altered
    2026-10-03 18:37 UTC). It returns and logs OK.
  - Measured 10-04: pass 2's step logged OK at 08:09:42 UTC in 1 s, and the `as_of` 10-04 partition
    kept `built_at` 05:30:18 UTC (712 rows). So "the step logged OK" does not mean "a partition was
    written".
  - On 10-05, pass 1 (05:00 UTC = 01:00 New York 10-05 = 22:00 LA 10-04) writes `as_of` 10-05 on the
    old code. Passes 2 and 3 of 10-05 (00:35 and 09:00 LA) are FROZEN: they log OK and write nothing.
  - **So the first partition built after the deploy is `as_of` 10-06, written by pass 1 of 10-06
    (~05:30 UTC 10-06, which is ~22:30 LA 10-05), in either window.** Until then the latest
    partition is pre-deploy.
  - The freeze needs an existing partition. A night with none is written by the next pass that logs
    OK. The step refused (FAIL, on an ASSERT) 10 of its 21 runs from 09-27 to 10-03, six of them in a
    row (09-27 05:32 to 09-28 16:44). It logged OK on all 7 runs from 10-02 08:05 to 10-04 08:09.
    The last of these (1 s) wrote nothing.
    - If it refuses on pass 1 of 10-06, a later pass of 10-06 writes `as_of` 10-06.
    - Only if it refused on both passes 1 and 2 of 10-05 could pass 3 of 10-05 write `as_of` 10-05
      after a primary-window deploy.
  - **Run K9 after pass 1 of 10-06** (Task 9). Before then it reads ≥ 1 through its freshness term
    ("BUILT BEFORE TRIAL 2 WAS FOUNDED").
  - **No book may be built with `tools/build_weekly_book.py` until K9 passes, so no weekly book can be
    built on 10-05** (UTC and New York date; in LA, none before ~22:30 of 10-05). The tool reads the rows with the latest `DATE(built_at)` (UTC), and their
    `holdout` column. From pass 1 of 10-05 to pass 1 of 10-06, those rows are the pre-deploy `as_of`
    10-05 partition, so a book built then would carry T2 controls.
  - The three bulksheet tools of Task 5 read `V_HOLDOUT_ARM` directly, so they are right from the
    deploy on.

**Uploads and hand changes.**
- **Uploads on 10-05: none.** No weekly book can be built after the deploy on 10-05 (above: K9 cannot
  read 0 before pass 1 of 10-06). Corrected 2026-10-04: the first version said "only a book built
  after the deploy, by the first gated pass or later, or none", and on 10-05 no such book can exist.
  Sunday's Weekly Run upload on 10-04 comes before the assignment and is fine.
  - **One caution for that upload.** An SB keyword change is dated by the sync that first saw it, up to
    a day late. A 10-04 change to an SB control's keywords can therefore be dated 10-05.
    `537046793426450` carries 83 SB keywords, 12 of them enabled; `71317833591283` carries 1.
  - c33 would then read RED on day one, and the readout would publish it as a `PRE_WINDOW_CHANGE`.
  - Before step 1, list the 10-04 upload's rows on the 12 controls. If any SB keyword row is among
    them, the first RED is expected and is named in the deploy record.
- **From 10-06:** books as usual, once K9 has passed after pass 1 of 10-06. They no longer carry T2
  controls.
- **Hand changes:** none to the 12 campaigns in §3.1, from the insert to 2027-01-26. The alarm cannot
  see every kind of change (§2.7, "What no source can see").

### Task 9: Prove it on 2026-10-06

- [ ] After the first pass of 10-06:
  - K8: every T2 control proposal is EXCLUDE with `holdout_trial_id` T2, and no T1-only control is
    excluded for HOLDOUT;
  - K9: every T2 control in the plan has `holdout = TRUE`, and no T1-only control does;
  - K10: the readout serves T2;
  - c33 reads GREEN, or RED naming exactly what touched a control;
  - c18 reads GREEN.
- [ ] HOLDOUT.md §9: status "running from 2026-10-06", with the measured results. Commit.

---

## 5. Checks (`HOLDOUT_RESTART_acceptance.sql`)

Each check returns `violations`, and PASS means 0. In this table `\|` stands for a literal `|`. Each NC runs the same text on a temp copy with the one
input doctored, and must read the stated count. `T1` = `'HOLDOUT-2026Q4-CAMPAIGN'` and
`T2` = `'HOLDOUT-2026Q4-CAMPAIGN-T2'`.

| # | check (violations =) | negative control (expected) |
|---|---|---|
| K1 | one live trial and it is T2: `ABS(COUNTIF(is_live) − 1) + COUNTIF(is_live AND trial_id != T2)` over `V_HOLDOUT_TRIAL` | the view's text on a registry copy without T1's `ARCHIVED` row reads 2 (two live trials, one of them not T2). On an empty copy it reads 1 |
| K2 | T1 rows unchanged: `IF(COUNT(*) = 69 AND FARM_FINGERPRINT(STRING_AGG(FORMAT('%T', (trial_id, unit_type, unit_id, unit_name, arm, stratum, seq_in_stratum, seed, assigned_at, eligible_from, trial_end, channel, family, is_capped, is_launch, spend_28d_at_assign, gp_28d_at_assign, net_28d_at_assign, assignment_rule)), '\|' ORDER BY unit_id)) = 7298956708089075507, 0, 1)` over `trial_id = T1` | a copy with one arm flipped reads 1 |
| K3 | the founding cohort is the approved list: `IF(COUNT(*) = 59 AND COUNTIF(arm = 'HOLDOUT') = 12 AND FARM_FINGERPRINT(STRING_AGG(FORMAT('%s\|%s\|%s\|%d', unit_id, arm, stratum, seq_in_stratum), ',' ORDER BY unit_id)) = 4171456845817687166, 0, 1)` over `trial_id = T2 AND STARTS_WITH(assignment_rule, 'FOUNDING')` | a copy minus one row reads 1. A copy with two arms swapped reads 1 |
| K4 | the arms follow the rule from stored columns, and the sequences are whole: `COUNTIF(arm != IF(MOD(seq_in_stratum + MOD(ABS(FARM_FINGERPRINT(CONCAT(seed, '\|', stratum))), 5), 5) = 0, 'HOLDOUT', 'TREATED'))` + per stratum `(COUNT(*) − COUNT(DISTINCT seq_in_stratum)) + COUNTIF(seq_in_stratum >= stratum count)`, over `trial_id = T2`, with 1 added when T2 has no row | one arm flipped reads 1. One seq duplicated reads ≥ 1. An empty T2 reads 1 |
| K5 | the seed is the first pass: on the founding rows, recompute A1–A3 for `OI-HOLDOUT-v2\|0` … `\|5`. Violations = (index 5 fails) + (number of indices 0–4 that pass) | A2's band set to [0.22, 0.26] reads 1 (index 5 fails) |
| K6 | the gate is T2's arm: today's binding rows of `V_HOLDOUT_ARM` versus T2's HOLDOUT rows, the size of the symmetric difference, + 1 if T2 has no HOLDOUT row | the views' text on a registry copy without T1's `ARCHIVED` row reads **14**, because T1's controls bind beside T2's |
| K7 | no gate reader bypasses the arm. In the deployed bodies (`INFORMATION_SCHEMA.VIEWS` and `ROUTINES`), occurrences of `` `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT` `` per object must equal exactly: `V_HOLDOUT_ARM` 1, `V_HOLDOUT_READOUT` 1, `V_ENGINE_HEALTH` 1 (c33 `hu_asg`), `SP_ASSIGN_HOLDOUT` 3 (the guard, `assigned`, `INSERT INTO`); every other object 0. Plus `grep -c 'DE_HOLDOUT_ASSIGNMENT'` = 0 in the three tools' SQL strings. Violations = objects off their count | the same query on the bodies saved before the deploy reads ≥ 6 (preflight, judgment, register, `V_ENGINE_HEALTH` at 3, the readout's literal, and four CTEs in the three tools) |
| K8 | the preflight bites on T2 only (latest `T_ENGINE_PREFLIGHT`): `COUNTIF(campaign in T2 HOLDOUT AND verdict != 'EXCLUDE') + COUNTIF(campaign in T1 HOLDOUT AND NOT in T2 HOLDOUT AND is_holdout)` | the 10-03 snapshot (pre-deploy) reads > 0 on the second term whenever a T1 control had a proposal that night. If it had none, the NC is the same text with T1 and T2 swapped |
| K9 | the plan agrees (latest `FACT_PLAN_NEXT_WEEK` live partition): `COUNTIF(T2 control AND NOT holdout) + COUNTIF(T1-only control AND holdout)` | the 10-03 partition reads > 0 (T1 controls carried `holdout = TRUE`) |
| K10 | the readout serves T2: exactly one `NOT_YET` row, whose verdict names `2027-02-09`; no `CENSORED` or `PRE_WINDOW_CHANGE` row names a unit outside T2; no number on any row before `first_readout` (H3) | the readout's text with `k` pinned to T1 reads ≥ 1 (the verdict names 2027-01-05, and the CENSORED rows name T1 units) |
| K11 | the touch alarm and the feed term: HOLDOUT_INTEGRITY H4 and H5 | as stated in Task 7 |
| K12 | the baseline is whole (amendment 2026-10-04): for T2's watched set (its HOLDOUT units with `STARTS_WITH(assignment_rule, 'FOUNDING')`, §2.7 kind 4, read from `DE_HOLDOUT_ASSIGNMENT` and not from an id literal), the symmetric difference between the founding `DE_HOLDOUT_BASELINE` rows (`ruling IS NULL`) and a re-read of the four sources' **present** settings at the read, by the presence rule of §2.7 kind 4 (re-stamped by the table's latest sync, within 1 hour of its `MAX(_fivetran_synced)`, and not `_fivetran_deleted`), compared as (`campaign_id`, `setting`, `value`). Add 1 when the re-read finds no setting for any unit of the watched set, because an empty input would pass. Measured 2026-10-04 by the rule: 15 settings on 8 controls, of which 7 carry placement rows. Run it straight after Task 3; afterwards it reads as kind-4 touches | a copy minus one row reads 1. A copy with one value altered reads 2. A re-read emptied for the 12 controls reads 16. All three were measured on `TMP_HT2_` copies on 2026-10-04 (Appendix C12) |

---

## 6. What could block a 2026-10-06 start

1. **Ori's OK on the list** (Task 0). **Done 2026-10-04:** "ok seed 5, deploy it". That includes his
   reading of the population: Bunny in, because the stock exclusion was re-graded on the design date
   (§2.4).
2. **The deploy window** (Task 8). Primary: after pass 2 of 10-05 ends, stopping by 15:40 UTC. Fallback:
   after pass 3 ends, finishing by 04:40 UTC on 10-06. Pass 1 of 10-06 starts at 05:00 UTC (22:00 Los
   Angeles on 10-05, measured); it judges under LA 10-05 and builds the book uploaded on 10-06. If it
   is missed, every T2 date shifts together, and so does T1's archive date.
3. **The alarm Ori is relying on does not exist yet.** c33 read AMBER on 10-03 with 8 touched controls
   (§2.7). Task 6, widened by the 2026-10-04 amendment, must land with the rest, or ruling (1)'s
   safeguard is not there on day one. Even then it cannot see hand negatives or ads and creatives
   (§2.7).
4. **No upload on 10-05 from a book built before the deploy, no book from `tools/build_weekly_book.py`
   until K9 passes, and no hand change to a T2 control from the insert on.**

**Open, not blocking:**
- **LolliME stock** (§3.3): a censor would leave 5 controls.
- **"The engine is a moving target"** (HOLDOUT.md §6), still unruled. Pieces 2–6 of the money plan will
  change the treatment during T2, so the readout should say "the engine as it evolved".
- **The BASE/GROWTH reorg status** (HOLDOUT.md §6). Nothing in the repository records it as landed.

---

## Appendix A — ruling (3) evidence (read 2026-10-03, ~16:00 UTC)

```sql
-- the ledger and the DIM SCD2 trail
SELECT 'ledger OBSERVED' src, CAST(MAX(applied_at) AS STRING) latest,
       COUNTIF(applied_at >= TIMESTAMP '2026-09-28') n_since_0928
FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` WHERE source = 'OBSERVED'
UNION ALL SELECT 'ledger logged', CAST(MAX(applied_at) AS STRING), COUNTIF(applied_at >= TIMESTAMP '2026-09-28')
FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` WHERE source != 'OBSERVED' OR source IS NULL
UNION ALL SELECT 'DIM_KEYWORD', CAST(MAX(_fivetran_synced) AS STRING), COUNTIF(effective_from >= DATETIME '2026-09-28')
FROM `onyga-482313.OI.DIM_KEYWORD`
UNION ALL SELECT 'DIM_CAMPAIGN', CAST(MAX(_fivetran_synced) AS STRING), COUNTIF(effective_from >= DATETIME '2026-09-28')
FROM `onyga-482313.OI.DIM_CAMPAIGN`;
-- latest OBSERVED 2026-09-28 04:11 UTC; latest logged 2026-08-25 21:44 UTC (wording corrected 2026-10-04:
-- that row is batch weekly_book_20260825_214435, still PENDING_UPLOAD, never uploaded; the latest logged
-- change that was APPLIED is seasonal_unpause_20260824_1728, 2026-08-24 17:28 UTC, in
-- V_PPC_CHANGE_LOG_APPLIED); DIM_KEYWORD newest version
-- 2026-09-28 04:11 UTC; DIM_CAMPAIGN synced 2026-10-03 07:14 UTC with 122 versions since 09-28, none on
-- a tracked attribute (no ledger row after 09-28).

-- is the keyword feed alive? the mirror against DIM_KEYWORD's current version
WITH src AS (
  SELECT keyword_id, ROUND(bid, 2) bid, UPPER(state) state, _fivetran_synced
  FROM `onyga-482313.OI.V_SRC_AmazonAds_keyword`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY keyword_id ORDER BY date DESC, _fivetran_synced DESC) = 1),
dim AS (
  SELECT CAST(keyword_id AS STRING) keyword_id, ROUND(bid, 2) bid, UPPER(state) state
  FROM `onyga-482313.OI.DIM_KEYWORD` WHERE is_current)
SELECT COUNT(*) n_src, COUNTIF(d.keyword_id IS NULL) not_in_dim,
       COUNTIF(d.keyword_id IS NOT NULL AND s.bid IS DISTINCT FROM d.bid) bid_differs,
       COUNTIF(d.keyword_id IS NOT NULL AND s.state IS DISTINCT FROM d.state) state_differs,
       CAST(MAX(s._fivetran_synced) AS STRING) latest_src_sync
FROM src s LEFT JOIN dim d USING (keyword_id);
-- 34,037 keywords, 0 missing from DIM, 0 bid differs, 0 state differs, mirror synced 2026-10-03 11:09 UTC.
-- LOG_PIPELINE_RUNS since 09-27: SP_LOAD_DIM_KEYWORD 21 OK, SP_LOAD_DIM_CAMPAIGN 21 OK,
-- SP_RECORD_OBSERVED_CHANGES OK on every pass from 10-02 (05:02, 07:38, 16:03 UTC each day).
```

**Reading:** the feed is alive, and Amazon carries no keyword bid or state change after the 09-27 Los
Angeles evening batch. "Latest logged 2026-08-25" is a book that was never uploaded. The latest logged
change that reached Amazon is 2026-08-24 17:28 UTC (wording corrected 2026-10-04, review fix 6). `DIM_KEYWORD`'s newest version stays at 09-28 04:11 UTC because SCD2 writes a
version only on a change. The record and Ori agree.

## Appendix B — the draw queries (scratch, read-only)

- **Population** = `V_HOLDOUT_ELIGIBLE`'s body with the stock literal `('LolliBall')`. The seed search
  crosses that population with `GENERATE_ARRAY(0, 199)` and applies §2.5 per index.
- **Acceptance region:** per stratum and offset, compute the control count, control dollars and the
  family bitmask. Then take the 8-way cross product of the 5 offsets, which gives 390,625 vectors, and
  count those passing A1–A3. 18,190 pass.
- **`gate_sim`:** `V_HOLDOUT_TRIAL` and `V_HOLDOUT_ARM` bodies over a literal registry, run for
  10-03, 10-04, 10-05, 10-06, 2027-01-26 and 2027-01-27. The results are in §2.1.
- **The stock read:** `V_LOW_STOCK_ADS` `row_kind IN ('FAMILY', 'ASIN')`, 47 s.
- **The live board read:** `V_ENGINE_HEALTH` filtered to `holdout_unit_changed` and
  `seat_holdout_row_on_sheet`. c33 read AMBER, measured 0. c18 read GREEN, measured 0, "the arm starts
  2026-09-01".

## Appendix C — the 2026-10-04 measurements (read-only, about 01:45–02:30 UTC)

The amendment's numbers come from these queries. Re-run them rather than quoting the numbers.

```sql
-- C1 which Fivetran tables each source view reads (deployed bodies)
SELECT table_name, ARRAY_TO_STRING(REGEXP_EXTRACT_ALL(view_definition, r'amazon_ads`?\.([a-z_]+)'), ' ') srcs
FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS`
WHERE table_name IN ('V_SRC_AmazonAds_keyword', 'V_SRC_AmazonAds_campaign_history',
                     'V_SRC_AmazonAds_ad_group_history', 'V_SRC_AmazonAds_negative_keyword');
-- keyword: targeting_expression keyword_history sb_keyword targeting_clause_history (no sb_product_target)

-- C2 what each source carries: INFORMATION_SCHEMA.COLUMNS of fivetran-hl.amazon_ads (campaign_history,
-- sb_campaign_history, ad_group_history, sb_ad_group_history, keyword_history, sb_keyword,
-- targeting_clause_history, sb_product_target, campaign_placement_bidding,
-- sb_campaign_bid_adjustments_by_placement, sb_campaign_bid_adjustments_shopper_cohort, the negative
-- and ad tables) and of OI.DIM_CAMPAIGN / DIM_AD_GROUP / DIM_KEYWORD.
-- History + creation_date: keyword_history, targeting_clause_history, ad_group_history,
-- sb_ad_group_history, campaign_history (portfolio_id, bidding_strategy), sb_campaign_history
-- (portfolio_id, bid_optimization, bid_optimization_strategy). Current state only, no date:
-- sb_keyword, sb_product_target, campaign_placement_bidding, sb_campaign_bid_adjustments_by_placement,
-- sb_campaign_bid_adjustments_shopper_cohort. DIM_CAMPAIGN versions portfolio_id and bidding_strategy.

-- C3 write history per Fivetran table, 30 days: the largest gap between writes that touched rows
WITH k AS (SELECT CURRENT_TIMESTAMP() now_ts, TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY) from_ts),
j AS (SELECT destination_table.table_id t, TIMESTAMP_TRUNC(creation_time, HOUR) h
      FROM `fivetran-hl`.`region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT, k
      WHERE creation_time >= k.from_ts AND destination_table.dataset_id = 'amazon_ads'
        AND statement_type IN ('MERGE', 'UPDATE', 'INSERT', 'DELETE') AND error_result IS NULL
        AND COALESCE(dml_statistics.inserted_row_count, 0) + COALESCE(dml_statistics.updated_row_count, 0)
            + COALESCE(dml_statistics.deleted_row_count, 0) > 0
      GROUP BY 1, 2),
p AS (SELECT t, h FROM j UNION ALL SELECT DISTINCT t, from_ts FROM j, k UNION ALL SELECT DISTINCT t, now_ts FROM j, k)
SELECT t, ROUND(MAX(gap) / 60, 1) AS max_gap_h
FROM (SELECT t, TIMESTAMP_DIFF(LEAD(h) OVER (PARTITION BY t ORDER BY h), h, MINUTE) gap FROM p)
GROUP BY 1 ORDER BY 1;
-- ≤ 21 h on all eleven tables of §2.7; the negative, product-ad, SB-ad and SB-creative tables: no write.

-- C4 the table's MAX(_fivetran_synced) through time (time travel, one point per query; repeat for
-- 6, 18, ... 162 hours back). A table cannot be read with and without FOR SYSTEM_TIME AS OF in one query.
SELECT TIMESTAMP_DIFF(TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 18 HOUR), MAX(_fivetran_synced), MINUTE) / 60
FROM `fivetran-hl.amazon_ads.keyword_history` FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 18 HOUR);
-- 0.0–9.9 h at every point, on keyword_history, targeting_clause_history, ad_group_history, sb_product_target

-- C5 the 12 controls across the sources: DIM_KEYWORD current rows, sb_product_target rows, placement
-- rows (SP and SB), DIM_CAMPAIGN portfolio / bidding_strategy, sb_campaign_history bid_optimization.
-- 27660342907703: no DIM_KEYWORD row, 1 enabled sb_product_target. (Corrected 2026-10-04: the first
-- version said "8 controls carry placement rows". It counted rows not re-stamped by the latest sync. By
-- the presence rule (C11): 7 controls carry placement rows, 6 of them non-zero.)

-- C6 untracked campaign attributes and new entities since the ledger began (2026-08-20)
-- DIM_CAMPAIGN version pairs: portfolio_id differs 1 (08-21), bidding_strategy differs 1 (08-26);
-- sb_campaign_history pairs: bid_optimization(_strategy) differs 0; DIM_KEYWORD first versions 2,
-- DIM_AD_GROUP first versions 1 (both = Fivetran creation_date); campaign_history versions with every
-- carried attribute equal to the predecessor's: 20 on 10 campaigns (cause unproven).

-- C7 pass times, 7 days (Task 8)
WITH r AS (SELECT procedure_name p, started_at s, finished_at f,
             CASE WHEN EXTRACT(HOUR FROM started_at) < 7 THEN 1 WHEN EXTRACT(HOUR FROM started_at) < 12 THEN 2 ELSE 3 END slot
           FROM `onyga-482313.OI.LOG_PIPELINE_RUNS`
           WHERE started_at >= TIMESTAMP '2026-09-27' AND started_at < TIMESTAMP '2026-10-04'),
pe AS (SELECT slot, DATE(s) d, MIN(s) ps, MAX(f) pf FROM r GROUP BY 1, 2)
SELECT slot, 'pass start' w, MIN(TIME(ps)) earliest, MAX(TIME(ps)) latest FROM pe GROUP BY 1
UNION ALL SELECT slot, 'pass end', MIN(TIME(pf)), MAX(TIME(pf)) FROM pe GROUP BY 1
UNION ALL SELECT slot, p, MIN(TIME(s)), MAX(TIME(s)) FROM r
WHERE p IN ('SP_RECORD_OBSERVED_CHANGES', 'SP_ASSIGN_HOLDOUT', 'SP_ENGINE_PREFLIGHT',
            'SP_BUILD_NEXT_WEEK_PLAN', 'SP_REFRESH_CUBE_TABLES')
GROUP BY 1, 2 ORDER BY 1, 3;

-- C8 the four procedures' largest gap between OK runs, 30 days (feed liveness): 13.0 h each
WITH r AS (SELECT procedure_name p, started_at s FROM `onyga-482313.OI.LOG_PIPELINE_RUNS`
           WHERE status = 'OK' AND started_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
             AND procedure_name IN ('SP_RECORD_OBSERVED_CHANGES', 'SP_LOAD_DIM_KEYWORD',
                                    'SP_LOAD_DIM_CAMPAIGN', 'SP_LOAD_DIM_AD_GROUP'))
SELECT p, COUNT(*) ok_runs, ROUND(MAX(gap) / 60, 1) max_gap_h
FROM (SELECT p, TIMESTAMP_DIFF(s, LAG(s) OVER (PARTITION BY p ORDER BY s), MINUTE) gap FROM r) GROUP BY 1;

-- C9 the latest logged and the latest applied change (Appendix A wording)
SELECT batch_id, upload_status, MAX(applied_at) FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
WHERE source IS DISTINCT FROM 'OBSERVED' AND applied_at >= '2026-08-20' GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 1;
SELECT batch_id, MAX(applied_at) FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
WHERE source IS DISTINCT FROM 'OBSERVED' AND applied_at >= '2026-08-20' GROUP BY 1 ORDER BY 2 DESC LIMIT 1;

-- C10 the 59 campaigns' net from FACT (§2.9): 09-19..10-02 −2,052.52; 09-05..10-02 −4,145.07 (read 10-04)
SELECT ROUND(SUM(IF(date >= '2026-09-19', GROSS_PROFIT - Ads_cost, 0)), 2) net_14d,
       ROUND(SUM(GROSS_PROFIT - Ads_cost), 2) net_28d
FROM `onyga-482313.OI.FACT_AMAZON_ADS`
WHERE date BETWEEN '2026-09-05' AND '2026-10-02' AND campaign_id IN (/* the 59 ids of §3.4 */);
```

### C11 and C12: the presence rule (follow-up 2026-10-04, about 02:30–02:55 UTC)

C11 measures which rows the latest sync re-stamped. C12 tests the rule on `TMP_HT2_` copies.

```sql
-- C11a per kind-4 table: rows, rows the latest sync re-stamped (within 1 h of the table's MAX), deleted
-- rows, stale rows that are not deleted, and stale campaigns with no re-stamped row
WITH s AS (
  SELECT 'SP_PLACEMENT' t, campaign_id cid, _fivetran_synced ts, FALSE del FROM `fivetran-hl.amazon_ads.campaign_placement_bidding`
  UNION ALL SELECT 'SB_PLACEMENT', campaign_id, _fivetran_synced, FALSE FROM `fivetran-hl.amazon_ads.sb_campaign_bid_adjustments_by_placement`
  UNION ALL SELECT 'SB_COHORT', campaign_id, _fivetran_synced, FALSE FROM `fivetran-hl.amazon_ads.sb_campaign_bid_adjustments_shopper_cohort`
  UNION ALL SELECT 'SB_TARGET', campaign_id, _fivetran_synced, COALESCE(_fivetran_deleted, FALSE) FROM `fivetran-hl.amazon_ads.sb_product_target`),
x AS (SELECT s.*, ts >= TIMESTAMP_SUB(MAX(ts) OVER (PARTITION BY t), INTERVAL 1 HOUR) fresh FROM s)
SELECT t, COUNT(*) n, COUNTIF(fresh AND NOT del) present, COUNTIF(del) deleted, COUNTIF(NOT fresh AND NOT del) stale,
       MIN(IF(NOT fresh AND NOT del, ts, NULL)) stale_min, MAX(IF(NOT fresh, ts, NULL)) stale_max,
       COUNT(DISTINCT IF(NOT fresh AND NOT del AND cid NOT IN (SELECT cid FROM x x2 WHERE x2.t = x.t AND x2.fresh), cid, NULL)) stale_cids_no_fresh_row
FROM x GROUP BY 1 ORDER BY 1;
-- 02:14 UTC sync (re-run 02:55 as written here, same result):
--   SP_PLACEMENT 195 rows, 181 present, 0 deleted, 14 stale (2026-03-17 .. 08-14) on 13 campaigns, none of
--   them with a fresh row (DIM_CAMPAIGN: 4 PAUSED, 9 ENABLED, ME-COMPETE among the 9);
--   SB_PLACEMENT 390 / 390 present; SB_COHORT 36 / 36 present;
--   SB_TARGET 150 rows, 88 present, 62 deleted (all last stamped by 2026-01-02), 0 stale and not deleted.
-- The SP table holds 0 rows at 0%; the SB placement table holds 356 rows at 0%. Of the eleven tables of §2.7,
-- only sb_product_target and sb_keyword have a _fivetran_deleted column. Rows re-stamped by the same sync on
-- all eleven tables: the table in §2.7 "Why each table's MAX ticks daily".

-- C11b the 12 controls by the rule (the same CTEs, joined to the 12 ids of §3.1, values listed)
-- present: SP 130115986205897 TOP 100; 222497123677300 PRODUCT_PAGE 200; 230219410635024 PRODUCT_PAGE 200;
-- 527422818407259 SITE_AMAZON_BUSINESS 50; 53343800376430 TOP 25. SB 71317833591283 DETAIL_PAGE / HOME / OTHER 500;
-- 537046793426450 DETAIL_PAGE / HOME / OTHER / TOP_OF_SEARCH 0, and its shopper cohort 0. 27660342907703: SB
-- target bid 0.6, enabled. 15 settings on 8 controls; 7 controls with placement rows, 6 of them non-zero.
-- absent (stale): 365568042533669 ME-COMPETE PLACEMENT_TOP 30 and PLACEMENT_PRODUCT_PAGE 15, stamped 2026-06-23.
-- no setting at all: 273898143987321, 271009556929636, 365568042533669, 51727823265377.

-- C11c is one hour wide enough? The same per-table read through time travel, one query per point,
-- every table at the same AS OF expression, 30 points from 1 to 166 hours back in steps of 6 hours:
--   FROM `fivetran-hl.amazon_ads.campaign_placement_bidding`
--     FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 6 HOUR)  (likewise for the other three)
-- reading the spread of the latest sync's stamps, the gap to the next older stamp, and
-- FARM_FINGERPRINT(STRING_AGG(present key and value ORDER BY key)).
-- Every point, every table: spread 0.0 min. Nearest older stamp ≥ 1,046 h (SP), ≥ 6,429 h (SB targets).
-- Present counts constant: SP 181, SB placement 390, cohort 36, SB targets 88. The fingerprint was constant on the
-- three adjustment tables. On sb_product_target it changed once, between 150 h and 144 h back. Latest sync age at
-- the 30 points: 0.0 to 15.6 h.
```

**C12, the rule tested on copies.** Scratch objects were created on 2026-10-04 and all dropped
afterwards: `OI.TMP_HT2_SP_PLACEMENT`, `_SB_PLACEMENT`, `_SB_COHORT` and `_SB_TARGET` (copies of the
four sources), `TMP_HT2_BASELINE` (founding rows by the rule) and `TMP_HT2_BASELINE_OLD` (founding
rows read without the rule).

The test query is the c33 `BASELINE_DIFF` sketch of Task 6: the latest baseline row per key,
full-outer-joined to the present settings of the 12 controls, counting `IS DISTINCT FROM`. It also
computes K12 as in §5 and the count of re-baselined keys (AMBER). In this first run (about 02:38–02:43
UTC) the 12 controls were an id literal in the test text. That does not test how c33 will choose them,
so the cases were run again below with the watched set.

| case (doctored input) | rule | `BASELINE_DIFF` | K12 | re-baselined |
|---|---|---|---|---|
| founding insert | with the rule | 15 rows on 8 controls, 0 for ME-COMPETE | | |
| founding insert | without the rule | 17 rows on 9 controls, 2 for ME-COMPETE | | |
| no doctoring | with / without | 0 / 0 | 0 / 0 | 0 |
| a removal on SP: `130115986205897` TOP's stamp moved 6 h back, so it is not re-stamped | with | **1** (100 → absent) | 1 | 0 |
| the same | without | **0**: missed | 0 | |
| the same, plus a re-baseline row with `value` NULL and a `ruling` | with | 0 | 1 | **1** (AMBER) |
| then the row is re-stamped again (the setting comes back) | with | 1 (absent → 100) | 0 | 1 |
| Fivetran drops the 14 stale SP rows (a re-sync) | with | **0** | 0 | 0 |
| the same | without | **2**: ME-COMPETE's removed rows read as an undated touch | 2 | |
| a value altered: `130115986205897` TOP 100 → 120 | with | 1 | 2 | 0 |
| a setting appears: a re-stamped ME-COMPETE TOP 30 row is added | with | 1 (absent → 30) | 1 | 0 |
| the same | without | **0**: missed, because it matches the stale row | 0 | |
| the SB target on `27660342907703` flagged `_fivetran_deleted` | with | 2 (its bid and its state) | 2 | 0 |
| K12 NC: a baseline copy without one row (`53343800376430` TOP) | with | 1 | **1** | |
| K12 NC: a baseline copy with that value altered (25 → 30) | with | 1 | **2** | |
| K12 emptiness: the four copies with the 12 controls' rows deleted | with | 15 | **16** (15 + 1) | |

After the last case, `INFORMATION_SCHEMA.TABLES` and `ROUTINES` listed no `TMP_HT2_%` object.

**C12, re-run with the watched set (second follow-up, 2026-10-04, about 03:01–03:10 UTC).** This run
used the plan's own text and no id literal:
- **The registry.** `TMP_HT2_TRIAL` was built from Task 2's Step 1 DDL and Step 3 rows. `TMP_HT2_V_TRIAL`
  was built from Step 2's `V_HOLDOUT_TRIAL` body. Read on 10-04, both trials are live, because T1's
  archive starts 10-05, and `hu_trial`'s tie-break picks T2.
- **The assignment.** `TMP_HT2_ASSIGNMENT` copied `DE_HOLDOUT_ASSIGNMENT` (T1's 69 rows). Task 3's
  founding script then ran on it unchanged apart from the names. Every ASSERT passed and it wrote 59
  rows, 12 of them HOLDOUT, all `FOUNDING (approved list)`.
- **The sources.** Copies of the four sources were taken at the 02:14 UTC sync: `TMP_HT2_SP`, `_SBP`,
  `_SBC` and `_TG`. `TMP_HT2_BASELINE` was empty.
- **The baseline insert** read the watched set from the assignment copy through the Task 6 text. It wrote
  15 rows on 8 controls: none for ME-COMPETE, and 7 controls with placement rows.
- **The test text** was Task 6's `hu_trial`, `hu_asg` and `hu_k4_*` CTEs, verbatim, with the table names
  pointed at the copies. A harness `SELECT` added K12 (§5, over the watched set) and the re-baselined
  count. For comparison it also computed the same diff two other ways: with the today side over every
  HOLDOUT unit (reading a), and over only the controls that have a baseline row (reading b).
- **The doctoring** followed the first run, except that the removal moved the stamp 12 hours back. Each
  case was undone before the next. The SB placement table re-synced at 03:07 UTC, before the last two
  cases. Its copy and the cohort copy were then re-taken, and the undoctored case read 0 again.

| case (doctored input) | `BASELINE_DIFF`, watched set | c33 kind-4 term | K12 | re-baselined | reading (a): every HOLDOUT unit | reading (b): baseline rows only |
|---|---|---|---|---|---|---|
| no doctoring | 0 | not-RED | 0 | 0 | 0 | 0 |
| **NC 1:** a present ME-COMPETE `PLACEMENT_TOP` 30 row added, stamped at the table's latest sync | **1** (absent → 30) | **RED** | 1 | 0 | 1 | **0**: missed |
| **NC 2:** a `LATE ARRIVAL` HOLDOUT row added for SB `111024628782640` STORE-SPOTLIGHT (tween-girl-gift). It is outside the 59 and carries two present 0% SB placement rows and one 0% shopper-cohort row | **0** | **not-RED**; the detail lists it as unwatched (`STORE-SPOTLIGHT (tween-girl-gift) (111024628782640): LATE ARRIVAL`) | 0 | 0 | **3**: RED with nothing touched | 0 |
| a removal on SP: `130115986205897` TOP's stamp moved 12 h back | 1 (100 → absent) | RED | 1 | 0 | 1 | 1 |
| the same, plus a re-baseline row with `value` NULL and a `ruling` | 0 | not-RED | 1 | 1 | 0 | 0 |
| then the row is re-stamped again (the setting comes back) | 1 (absent → 100) | RED | 0 | 1 | 1 | 1 |
| the 14 stale SP rows deleted (a re-sync) | 0 | not-RED | 0 | 0 | 0 | 0 |
| a value altered: `130115986205897` TOP 100 → 120 | 1 | RED | 2 | 0 | 1 | 1 |
| the SB target on `27660342907703` flagged `_fivetran_deleted` | 2 | RED | 2 | 0 | 2 | 2 |
| K12 NC: a baseline copy without one row (`53343800376430` TOP) | 1 | RED | **1** | 0 | 1 | **0**: that control has no other row |
| K12 NC: a baseline copy with that value altered (25 → 30) | 1 | RED | **2** | 0 | 1 | 1 |
| K12 emptiness: the four copies with the trial's HOLDOUT units' rows deleted (selected through the assignment copy, no literal) | 15 | RED | **16** (15 + 1) | 0 | 15 | 15 |
| an empty watched set: the 12 founding rows' `assignment_rule` re-prefixed `LATE ARRIVAL` | 15 (every baseline row, one side only) | RED; all 12 listed as unwatched | 16 | 0 | 0 | 0 |

- **Reading (a)** turns a late SB control RED on 0% rows, with nothing touched.
- **Reading (b)** misses an adjustment put back on ME-COMPETE. It also misses a lost baseline row
  whenever that was the control's only one.
- **The watched set** reads every case as designed.

All `TMP_HT2_` objects of this run were dropped. Afterwards `INFORMATION_SCHEMA.TABLES` and `ROUTINES`
listed 0 `TMP_HT2_%` objects.
