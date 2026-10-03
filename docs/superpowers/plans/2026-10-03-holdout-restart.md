# Holdout restart — trial 2 from 2026-10-06 (Ori's ruling of 2026-10-03, option (c))

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.
> **Nothing in this plan may be deployed before Task 0 (Ori's OK on the list) is done.**

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
written once from the approved literal list, never re-drawn live.

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
- **Ori's one decision is the list of 12 controls in §3.1.** Nothing is written until he says OK.
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
  `DE_HOLDOUT_ASSIGNMENT` or `DE_HOLDOUT_TRIAL`.** Both are append-only (HOLDOUT.md §6 #1).
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
register's fix. Every reader filters `unit_type = 'CAMPAIGN'`.

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

The orchestrator passes on 10-02 and 10-03 ran `SP_ENGINE_PREFLIGHT` at about 05:33, 08:05 and 16:55 UTC
(`LOG_PIPELINE_RUNS`). The 05:33 UTC pass is 01:33 New York but **22:33 Los Angeles of the previous
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
sources: on 10-05, upload only a book built after the deploy, or none. Sunday's Weekly Run upload on 10-04
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
- **Touch alarm (new).** c33 is RED while any change on a control of the live trial, from its assignment
  day on, is 7 or fewer Los Angeles days old. After that it is AMBER for as long as any control was ever
  touched, and the detail names each one.
  - **Why 7 days:** the brief is read daily. Seven days survives a missed brief or a weekend.
  - **"The same night"** means the next orchestrator pass after Fivetran syncs the change, because
    `SP_RECORD_OBSERVED_CHANGES` runs in every pass. An SP keyword or a campaign is dated by Amazon's own
    `last_updated_date`. An SB keyword is dated by the sync that first saw it, up to a day late
    (`V_AMAZON_OBSERVED_CHANGES` header).
- **Feed liveness (new).** c33 is RED when any of the following is more than 36 hours old or missing:
  - the last OK run of `SP_RECORD_OBSERVED_CHANGES`;
  - the last OK run of `SP_LOAD_DIM_KEYWORD`;
  - the keyword mirror's `MAX(_fivetran_synced)`.

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
  floor. A larger multiplier for 12 clusters would raise it, so read it as a floor. The population's
  pre-period 14-day net is −$1,868.51, so the MDE is about 1.1× the whole quantity measured. **§7's
  warning applies unchanged.**

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

- [ ] Ori reads §3.1, §3.3 and the population note in §2.4, then answers **"OK"**, or names a change.
  Accepted changes are limited to the population (for example, keep Bunny out). Each one means a full
  re-draw by §2.5 from index 0 and a new fingerprint, never a hand swap of one campaign.
- [ ] Record his words and the date in HOLDOUT.md §9 and in the T2 `OPENED` row's `ruling` (Task 2).
- [ ] **If the OK comes after 2026-10-05 22:00 Los Angeles** (05:00 UTC on 10-06, before that night's
  first pass): every T2 date moves together by the number of days late. That covers `assigned_on`,
  `gate_from`, `win_start`, `win_end`, the interim look and `first_readout` (HOLDOUT.md §6, "move both
  dates together"). The list stays the same, and `assignment_rule` names the facts' date.

### Task 1: SOPs first

**Files:** `architecture/HOLDOUT.md`, `architecture/ENGINE_PREFLIGHT.md`, `architecture/ENGINE_HEALTH.md`,
`architecture/FAMILY_SEAT_REGISTER.md`, `architecture/NEXT_WEEK_MONEY.md` (the holdout passages),
`architecture/THREE_LAYERS.md`, `architecture/KEYWORD_STATE.md` (each names `DE_HOLDOUT_ASSIGNMENT`).

- [ ] HOLDOUT.md: §4 objects table gains `DE_HOLDOUT_TRIAL`, `V_HOLDOUT_TRIAL` and `V_HOLDOUT_ARM`. §5
  gains the T2 seed and criteria. §8 gains the T2 dates and the former-T1-controls sensitivity row. §9
  changes from "proposed" to "running". The banner names the live trial.
- [ ] The other SOPs: every "reads `DE_HOLDOUT_ASSIGNMENT`" becomes "reads `V_HOLDOUT_ARM` (the arm
  that binds today, any trial)". Nothing else changes.
- [ ] Commit (targeted add).

### Task 2: The registry and its two views

**Files:** new `scripts/bigquery/tables/DE_HOLDOUT_TRIAL.sql`, new `views/V_HOLDOUT_TRIAL.sql`, new
`views/V_HOLDOUT_ARM.sql`, `config.yaml`.

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

- [ ] **Step 3: the registry rows** (fill in `<OK date>` and Ori's words at deploy).

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
   'Ori 2026-10-03: restart from 2026-10-06 with a fresh draw by the same method. List approved by Ori on <OK date>: "<his words>".',
   NULL);
```

  Inside a BigQuery string literal, a quote in Ori's words must be escaped as `\'` (or `\"`).

- [ ] **Step 4: checks K1, K2 and K6 (§5) with their NCs.** Register the three objects in `config.yaml`
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

- [ ] Checks K2, K3, K4 and K5 with their NCs.

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
- [ ] Deploy only after Task 3. **Check after the first pass that runs it:** K2, K3 and K4 still read 0.
  Any new T2 row is a `LATE ARRIVAL` whose `seq_in_stratum` continues its stratum (K4).
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
hu_asg AS (  -- the trial's units, both arms
  SELECT a.unit_id, a.unit_name, a.arm, a.stratum, a.eligible_from, a.trial_end, a.assigned_at
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
  - The detail leads with `TOUCHED: <name> (<id>) on <day>` for each recent touch, then the feed's three
    ages. The "A RULING FOR ORI" clause becomes "published, not censored (pre-declared for T2, plan
    2026-10-03 §2.3)".
  - **Measured fact for the NC:** on T1's live inputs on 2026-10-03, the new term reads RED. The latest
    touch is 2026-09-27, 6 days old.
  - **Before deploying, check** whether `V_SRC_AmazonAds_keyword` covers SB keywords. If the SB mirror is
    a separate source, add its `MAX(_fivetran_synced)` as a fourth age.
- [ ] Measure the slot-seconds of the board filtered to c33, two runs. Commit.

### Task 7: Acceptance

**Files:** new `scripts/bigquery/tests/HOLDOUT_RESTART_acceptance.sql` (K1–K11, §5),
`tests/HOLDOUT_INTEGRITY_acceptance.sql`, `tests/V_FAMILY_SEAT_REGISTER_acceptance.sql`.

- [ ] `HOLDOUT_INTEGRITY_acceptance.sql`:
  - `hu_asg` and the pasted c33 text follow Task 6 verbatim;
  - H3's gate date reads `first_readout` from `V_HOLDOUT_TRIAL`;
  - **H4 (touch alarm)**, on doctored inputs: an observed change on a T2 control dated today reads RED
    with measured ≥ 1; the same change dated today − 8 reads AMBER; no change reads GREEN;
  - **H5 (feed liveness)**: a `LOG_PIPELINE_RUNS` copy with no OK `SP_RECORD_OBSERVED_CHANGES` run in
    36 hours reads RED, and the live log reads not-RED on that term.
- [ ] `V_FAMILY_SEAT_REGISTER_acceptance.sql` line 350: `holdout` reads `V_HOLDOUT_ARM`.
- [ ] `PLAN_OWNERSHIP_acceptance.sql` is untracked and belongs to another session. Do not touch it. Hand
  its owner the one-line change: `hold_open` reads `V_HOLDOUT_ARM` between `gate_from` and `gate_to`.
- [ ] Run all three files and record the results in their headers. Commit.

### Task 8: Deploy order and timing (2026-10-05)

The passes run at about 05:20, 07:55 and 16:30 UTC. `SP_ASSIGN_HOLDOUT` runs at those times, followed by
the preflight about 10 to 25 minutes later.

| step | when | what |
|---|---|---|
| 0 | before 10-05 | Task 0 (OK), Task 1 (SOPs) |
| 1 | 10-05, after the ~07:55 UTC pass has finished (check `LOG_PIPELINE_RUNS`; ~08:30 UTC) | Task 2: table, registry rows, views. K1, K2, K6 |
| 2 | right after | Task 3: the founding insert. K3, K4, K5 |
| 3 | right after | Task 4: `SP_ASSIGN_HOLDOUT`, `V_HOLDOUT_ELIGIBLE` |
| 4 | right after | Task 5: preflight, judgment, register, tools. K7 |
| 5 | right after | Task 6: readout, board. Task 7 acceptance |
| 6 | **all of 1–5 before ~16:20 UTC** (the third pass) | the 16:30 UTC pass is the first one gated for T2 |
| — | **hard deadline: before ~05:15 UTC 10-06** (22:15 LA 10-05) | that pass judges under LA 10-05 and builds the book uploaded on 10-06. If it is missed, shift every T2 date by a day (Task 0) before step 1 |

- **Uploads on 10-05:** only a book built by the 16:30 UTC pass or later, or none.
- **From 10-06:** books as usual. They no longer carry T2 controls.
- **Hand changes:** none to the 12 campaigns in §3.1, from the insert to 2027-01-26.

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

---

## 6. What could block a 2026-10-06 start

1. **Ori's OK on the list** (Task 0). That includes his reading of the population: Bunny in, because the
   stock exclusion was re-graded on the design date (§2.4).
2. **The deploy window.** Everything must be in before the first pass of 10-06, at about 05:15 UTC
   (22:15 Los Angeles on 10-05). That pass judges under LA 10-05 and builds the book uploaded on 10-06.
   If it is missed, every T2 date shifts together.
3. **The alarm Ori is relying on does not exist yet.** c33 read AMBER on 10-03 with 8 touched controls
   (§2.7). Task 6 must land with the rest, or ruling (1)'s safeguard is not there on day one.
4. **No upload on 10-05 from a book built before the deploy, and no hand change to a T2 control from the
   insert on.**

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
-- latest OBSERVED 2026-09-28 04:11 UTC; latest logged 2026-08-25 21:44 UTC; DIM_KEYWORD newest version
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
Angeles evening batch. `DIM_KEYWORD`'s newest version stays at 09-28 04:11 UTC because SCD2 writes a
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
