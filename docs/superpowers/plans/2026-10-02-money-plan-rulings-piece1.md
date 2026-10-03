# Money plan — the 2026-10-02 rulings and the audit fixes (learning contract, piece 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the money plan's rules right before the learning loop starts grading them: apply Ori's
fifteen rulings of 2026-10-02 (audit questions 1–9 and 11–16), the twelve code fixes the audit found
where the rulings are clear and the code disobeys them, and the three defects the piece-0 proof found.

**Architecture:** Every change lands in one of four places — the judge (`V_PLAN_WINDOW_JUDGMENT`, who is
good and why), the builder (`SP_BUILD_NEXT_WEEK_PLAN`, how much money and which seats), the keyword
snapshot (`SP_SNAPSHOT_KEYWORD_STATE`), or the health surfaces (`V_ENGINE_HEALTH`, `V_DAILY_BRIEF`,
`V_HOLDOUT_READOUT`). Tasks run in order because Tasks 2–3 and 4–6 edit the same two files. Each task
deploys, runs its own acceptance with negative controls, and commits on its own.

**Tech stack:** BigQuery Standard SQL (views, procedures, table functions), `bq` CLI, Python 3.9 test
harnesses, Markdown SOPs. Project `onyga-482313`, dataset `OI`.

**Sources:** the audit (workflow `wf_d99d0321-5a4`, 2026-10-02; ranked result saved in the session
scratchpad as `audit_ranked.json`), spec `docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md`,
SOP `architecture/NEXT_WEEK_MONEY.md`, doctrine `architecture/THREE_LAYERS.md` (the top document — it
supersedes P-11's "one engine"), learning contract `docs/superpowers/specs/2026-10-01-learning-contract-design.md`.

---

## House rules binding on every task

- **Targeted `git add` only.** Ten unrelated files are dirty (eight modified, two untracked). Never
  `git add -A` / `.` / `commit -a`. Commits use `--no-verify` and end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Deploy a file with comment lines stripped** when it is near the 32 KB query limit:
  `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^[[:space:]]*--' FILE)"`.
- **Never DELETE or UPDATE existing rows** of `FACT_PLAN_NEXT_WEEK`, `FACT_PPC_CHANGE_LOG`, `DE_*` tables.
  New columns: `ALTER TABLE … ADD COLUMN IF NOT EXISTS`, one per statement, at most four per table in
  ten seconds (BigQuery allows five metadata updates per table per ten seconds).
- **The P-14b/P-14c guard is read, never re-derived.** Any check about the guard reads
  `guard_released_by`; the builder's month of refused plans (08-29 → 09-28) came from a copy of the
  guard's preconditions read as a veto.
- **Every acceptance check has a negative control** run on a temp copy, with the measured result
  recorded in the file's comments. Add an emptiness term wherever an empty input would pass.
- **Never `SELECT` from `V_INTENT_CVR_CURVE`, `_SHADOW`, `V_INTENT_BID_BASE`, `V_INTENT_INDEX_SCORECARD`.**
  Measure and report slot-seconds of anything new that scans `FACT_AMAZON_ADS`.
- **Do not run `SP_ORCHESTRATE_DAILY_REFRESH`.** Deploy it only when a task adds a step, after diffing the
  deployed body against the file (the only difference must be the new step).
- **Register every new object in `config.yaml`**; `python3 -c "import yaml; yaml.safe_load(open('config.yaml'))"`
  must pass.
- **Comments make no untested claim.** Write what was measured, with the query or the run that measured it.
- **Out of scope for piece 1:** audit code fix #2 (a PLAN-owned exclusion in the preflight) and audit
  question #10 (SB product targets). Both assume P-11's "the plan is the sole price authority", which
  `THREE_LAYERS.md` superseded on 2026-08-24: the plan is the **Brain** and issues intents
  (`REPAIR · ceiling`, `TEST · seat · N clicks by D`, `PARK`, `STOP`, `EARN`); **Pacing** (LIFT, OOB,
  REVERDICT) finds today's bid inside them. They are redesigned as piece 3 on that contract.

## The rulings (Ori, 2026-10-02, "all recommended")

| # | question | ruling |
|---|---|---|
| R1 | the pot and the holdout | **(a)** the pot is every GOOD keyword of the family, holdout included; holdout rows still get no move |
| R2 | seat tenure | **(a)** a seat is held until its verdict date while its keyword is still a candidate; newcomers queue behind |
| R3 | grace on a nightly run | **(a)** grace lasts `window_days` nightly judgments, anchored to the night it was granted |
| R4 | how long a hold lasts | **(c)** a hold persists while the very good last day that earned it is still inside the judged window, and the clock has not expired |
| R5 | raises on not-good seats | **(a)** never price a not-good seat above its current bid while its corrected return is under the bar |
| R6 | zero-score candidates | **(b)** among candidates with no positive score, rank by money burned with no return instead of by clicks |
| R7 | allowance above today's loser spend | **(a)** cap the ramped allowance at today's not-good spend |
| R8 | P-8's queue residual | **(b)** keep the arithmetic; publish `expected_after_upload` and `share_closed` beside the allowance |
| R9 | two control campaigns paused 09-27 | **(a)** Ori paused them; censor both units and their stratum-mates from the holdout readout from 2026-09-27 |
| R11 | which clock keys a night | **(a)** `as_of` is the New York date, with a guard that refuses to rewrite a partition under a different calendar state |
| R12 | a probe's bid | **(a)** a seated probe opens at LIFT's `PROBE_START` bid (capped by the raise ceiling) and is costed there; an unseated probe gets no move |
| R13 | the seat's question horizon | **(a)** `clicks_requested` spans the settle horizon: the window's click rate × `settle_days` |
| R14 | campaign caps | **(c)** keep: cuts ramp by thirds, raises jump to need; write it into spec §4.7 |
| R15 | who numbers seats | **(a)** the register adopts the plan's number; the builder's memory reads a keyword's most recent seat in any earlier partition |
| R16 | memory across an unwritten gap | **(b)** before honouring a GRACE or hold memory older than the gap, check whether the gap's windows read GOOD; if so, clear it |
| — | min group size for the scorecard's hint | **16** (done in commit `b42a6f5`) |
| — | hand changes as evidence | **(a)**, tuner and Weekly Run panel, labelled (done in `ab2c1a3`; panel in a separate task) |

## File structure

| file | tasks | responsibility |
|---|---|---|
| `docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md` | 1 | rulings R1–R16 recorded as P-15…; §4.7 caps (R14); §3b correction |
| `docs/superpowers/specs/2026-10-01-learning-contract-design.md` | 1 | piece 3 restated on the THREE_LAYERS contract |
| `architecture/NEXT_WEEK_MONEY.md` | 1, every task | SOP: corrections, each task's deploy and verify |
| `scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql` | 2, 3, 6 | the judge |
| `scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql` | 2, 3, 7 | the judge's checks |
| `scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql` | 4, 5, 6 | the builder |
| `scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql` + a dated migration | 4, 5 | new columns |
| `scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql` | 4, 5, 6 | the plan's checks |
| `scripts/bigquery/procedures/SP_MAINTAIN_FAMILY_SEATS.sql` | 5 | the register's admission (verify R15's adoption is complete) |
| `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql` | 7 | the brand-defense flag |
| `scripts/bigquery/views/V_HOLDOUT_READOUT.sql` | 8 | censoring |
| `scripts/bigquery/views/V_ENGINE_HEALTH.sql`, `V_DAILY_BRIEF.sql` | 4, 8, 9 | checks and the SYSTEM line |
| `scripts/bigquery/tables/FACT_ENGINE_HEALTH_HISTORY.sql`, `procedures/SP_SNAPSHOT_ENGINE_HEALTH.sql` | 9 | the board's memory |
| `scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql` | 9 | one new step |
| `config.yaml` | every task | registrations and descriptions |

---

### Task 1: Record the rulings and fix the documents that state the opposite of the built rule

Docs only. No BigQuery object changes.

**Files:** the two specs and the SOP in the table above.

- [ ] **Step 1: Record the rulings in the money-plan spec.** After the P-14c row of §2, add one row per
  ruling R1–R16 (skip R10), numbered P-15 onward, each with Ori's choice, one sentence of rule, and the
  audit's measured dollars from the table at the top of this plan. Add a line under §2's heading:
  "P-15…P-29 ruled 2026-10-02 from the piece-1 audit; R10 (SB product targets) is deferred to piece 3."
- [ ] **Step 2: §4.7 campaign caps (R14).** State the built rule as the ruling: a cap is
  `GREATEST(current + (need − current) / ramp_steps, need, good_side_spend, 1.00)` snapped out of the
  $20.01–$31.99 band — cuts ramp by thirds, raises land on need in one night because a cap below the
  money the plan can already see starves seats the plan just funded.
- [ ] **Step 3: correct spec §3b and the judge comments (audit fix #17).** Replace "the four held read
  1.86× to 17.5×", "a very good one (1.86× and up) earns the wait" and "41 are judged on the window" with
  what the 09-28 partition shows: all 44 released rows were judged on the window — 4 `HOLD_EXPIRED` on
  stale August clocks (last-day multiples 1.90× / 1.93× / 11.71× / 22.19× the bar; "17.5" was a raw return
  per ad dollar), 40 `LAST_DAY_NOT_STRONG`; the four rows actually held were 472871506551769,
  327098771639576, 523536098863060, 417024311542687. Re-read each multiple from `FACT_PLAN_NEXT_WEEK`
  (`last_day_ret / family_bar`) before writing it.
- [ ] **Step 4: P-9's holdout share (audit fix #26).** Replace "(10 %, from 2026-09-01)" with "(1-in-5 by
  campaign within stratum, 14 of 69 units, about 20 % of eligible 28-day spend, from 2026-09-01; see
  architecture/HOLDOUT.md)". Read the counts from `DE_HOLDOUT_ASSIGNMENT` before writing them.
- [ ] **Step 5: SOP sentences that state the opposite of the built rule (audit fix #28).** In
  `architecture/NEXT_WEEK_MONEY.md`: §3 step 3 "is never ramped upwards into a bigger loss budget" →
  the builder's own comment, then the R7 cap (Task 4 makes it true); §3 item 1 strike "No campaign is
  eligible before 2026-09-01, so this costs nothing today"; open-ruling #2 "where a family's allowance
  exceeds its whole not-good side" → "regardless of allowance headroom: the fit test has no direction
  term" (R5 closes it); the v27.134 grace wording → the R3 rule. Grep for each phrase; quote nothing that
  is no longer true.
- [ ] **Step 6: Learning contract, piece 3.** In `2026-10-01-learning-contract-design.md` §10, replace
  "plan Tasks 3 + 4: the plan owns bids in the preflight; the plan bulksheet" with "the Brain → Pacing
  handoff (`THREE_LAYERS.md` §3): the plan emits intents — REPAIR with a ceiling, TEST with a seat and a
  click target, PARK, STOP, EARN — and the preflight holds Pacing inside them (never above a REPAIR
  ceiling, never a raise on a PARK); and the plan's upload file". Add one sentence to §12: P-11's
  "one engine" was superseded by `THREE_LAYERS.md` on 2026-08-24.
- [ ] **Step 7: Commit.**

```bash
git add docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md docs/superpowers/specs/2026-10-01-learning-contract-design.md architecture/NEXT_WEEK_MONEY.md
git commit --no-verify -m "docs(plan): record Ori's 2026-10-02 rulings P-15..P-29; correct the sentences that state the opposite of the built rule"
```

---

### Task 2: The judge's memory — grace (R3), the hold (R4), the gap (R16), the clock on night one (fix #16)

**Files:** `scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql` (the `plan_hist`, `prior`, `base`,
`sided`, `judged`, `final` CTEs and the sentences), `scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql`.

- [ ] **Step 1: Measure the baseline.** Save the deployed view's output to a temp table and record, per
  family: GRACE rows, HELD rows, released rows by `guard_released_by`, and the rows whose `last_grace_on`
  is older than 2026-09-01. Record the slot-seconds of one scan.

- [ ] **Step 2: R3 — grace is one window of nightly judgments.** In `prior`, replace the "most recent
  GRACE later than the most recent GOOD" reading with an anchored one:

```sql
-- the grace run in force: its first night, and the window length in force on that night
MIN(IF(verdict = 'GRACE' AND (last_good_on IS NULL OR as_of > last_good_on), as_of, NULL)) AS grace_since,
-- window_days of that first night: carried by the plan row of the same as_of
...
-- grace is SPENT once the run has lasted the window it was granted for
(grace_since IS NOT NULL AND DATE_DIFF(today_ny, grace_since, DAY) >= grace_window_days) AS prior_grace
```

  `plan_hist` must also carry `window_days` and the last GOOD night (`last_good_on`). A grace granted
  under a 7-day window keeps 7 nights after a switch to a 3-day window (anchor it). Restate the GRACE
  sentence to print the date grace ends, and restate acceptance C12/C22 to the window reading.

- [ ] **Step 3: R4 — the hold lasts while its very good day is still in the window.** The hold run
  already anchors `hold_since` / `hold_settles_on`. Add `hold_strong_day` = the `window_to` of the
  `hold_since` night (the very good last day that started the run). The HELD branch becomes:

```sql
WHEN s.was_good AND NOT s.settled AND s.served AND NOT s.hold_expired
     AND (s.last_day_strong
          OR (s.hold_since IS NOT NULL AND s.window_from <= s.hold_strong_day))
  THEN 'HELD_UNSETTLED'
```

  `guard_released_by = 'LAST_DAY_NOT_STRONG'` only when neither condition holds. The builder's ASSERT
  that every HELD row has `last_day_strong` must become: every HELD row has `last_day_strong` OR a hold
  run whose strong day is inside today's window — publish `hold_strong_day` and `hold_kept_by`
  (`'LAST_DAY'` | `'STRONG_DAY_IN_WINDOW'`) so the builder and the acceptance read it, never re-derive it.
  Rewrite the three HELD sentences: "held since <date> because <date> was very good; that day leaves the
  judged window after <date>, and the hold lifts then or when its window settles on <date>, whichever is
  first".

- [ ] **Step 4: R16 — memory across an unwritten gap.** In `prior`, before honouring a GRACE run or a
  hold run whose last plan night is older than `today − window_days − 1`, compute from `FACT_AMAZON_ADS`
  whether any judge-window between that night's `window_to` and today's `window_from` read GOOD
  (orders ≥ `min_orders` AND gross profit / spend ≥ `family_bar`, the judge's own definition, on windows
  of the `window_days` in force). If one did, clear the memory (`prior_grace` FALSE, no hold run). One
  CTE over `FACT_AMAZON_ADS` restricted to the keywords that carry such a memory. Measure slot-seconds.

- [ ] **Step 5: fix #16 — publish the clock on the first HELD night.**

```sql
COALESCE(pr.hold_since,      IF(verdict = 'HELD_UNSETTLED', today_ny, NULL))      AS hold_since,
COALESCE(pr.hold_settles_on, IF(verdict = 'HELD_UNSETTLED', settle_due_on, NULL)) AS hold_settles_on
```

  `prior` reads only `as_of`, `verdict` and `settle_due_on` from history, so publishing these cannot
  re-anchor a run (verify on the 09-28 → 10-02 holds: night two's `hold_since` = night one's `as_of`).

- [ ] **Step 6: Acceptance.** Add, each with a negative control on a temp copy of the view's output or of
  `FACT_PLAN_NEXT_WEEK`:
  - G1 a GRACE run never lasts beyond `window_days` nightly judgments of the window in force when granted
    (NC: a doctored history with grace on day 1 and a GRACE verdict on day `window_days + 1`);
  - G2 every HELD row has `last_day_strong` or `hold_kept_by = 'STRONG_DAY_IN_WINDOW'` with
    `window_from <= hold_strong_day` (NC: one HELD row with the strong day moved before `window_from`);
  - G3 every HELD row carries `hold_since` and `hold_settles_on` (NC: nulled);
  - G4 no GRACE or hold memory survives a gap whose windows read GOOD (NC: a doctored history with a
    GRACE on 08-27 and a GOOD window inside 08-29..09-27).
- [ ] **Step 7: Deploy, run, record per family the before/after counts of GRACE, HELD and releases, and
  the dollars that moved sides. Commit.**

---

### Task 3: The judge's prices and ranks — no raise below the bar (R5), the zero-score rank (R6), the probe price (R12)

**Files:** `V_PLAN_WINDOW_JUDGMENT.sql` (the `derived` CTE near `planned_bid_raw`, `probes`, the
`final` rank columns, the seat sentences), its acceptance.

- [ ] **Step 1: R5.** After `planned_bid_raw` is computed:

```sql
-- R5 (Ori 2026-10-02): a repair on the not-good side is a step toward the bar, never away from it.
-- Gate on the corrected return against the bar, not on the verdict label: five ONE_ORDER rows on
-- 2026-10-01 sat under the bar and would survive a label gate.
IF(COALESCE(ret_corrected, 0) < family_bar,
   LEAST(planned_bid_raw, current_bid),
   planned_bid_raw) AS planned_bid_raw
```

  `seat_cost_per_day` must be recomputed from the gated price (it scales by `planned_bid_raw /
  current_bid`).

- [ ] **Step 2: R6.** Keep P-7's `rank_score` for every candidate with a positive corrected return. For
  candidates whose score is 0 (`rank_is_degenerate`), order them by money burned with no return instead
  of by clicks: publish

```sql
rank_money_burned = (w_sp / window_days) * GREATEST(0, 1 - COALESCE(ret_corrected, 0) / NULLIF(family_bar, 0))
```

  and change the view's final ORDER BY (and the builder's `ranked` CTE in Task 5) to
  `rank_score DESC, rank_money_burned DESC, w_clk DESC, campaign_id, keyword_id`. Zero-score candidates
  still rank below every positive score. Correct the SOP §2 sentence "can never win a seat, and always
  queues".

- [ ] **Step 3: R12 (the judge's half).** Read LIFT's latest `PROBE_START` bid per keyword:

```sql
probe_bid AS (
  SELECT CAST(keyword_id AS STRING) AS kid, ANY_VALUE(suggested_bid) AS probe_start_bid
  FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
  WHERE engine = 'LIFT' AND action = 'PROBE_START'
    AND snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`)
  GROUP BY 1
  HAVING COUNT(DISTINCT suggested_bid) = 1   -- one price per keyword, or no probe price at all
)
```

  For `is_probe` candidates with a `probe_start_bid`, `planned_bid_raw = LEAST(probe_start_bid,
  GREATEST(raise_ceiling, current_bid))` and the seat cost = `click_goal_day × probe_start_bid` (the seat
  funds the answer it demands, THREE_LAYERS §3). Probes without a LIFT price keep today's formula and say
  so in the sentence. R5 does not apply to a probe (it has no window to be under the bar on).

- [ ] **Step 4: Acceptance.** P1 no not-good row with `ret_corrected < family_bar` has `planned_bid >
  current_bid` (NC: one row's price raised); P2 every degenerate candidate's order follows
  `rank_money_burned` (NC: two rows swapped); P3 every probe with a LIFT price is priced at it, capped
  (NC: one probe at the old formula).
- [ ] **Step 5: Deploy, run, record per family: raises removed (count, $/day), seat costs before/after,
  probes repriced. Commit.**

---

### Task 4: The builder's money — the pot (R1), the allowance cap (R7), the residual (R8), holdout caps (fix #11), cap labels (fix #12), the ramp step (fix #15), the pot check (fix #24)

**Files:** `SP_BUILD_NEXT_WEEK_PLAN.sql` (`fam`, `fam2`, `budgets`, the sentences, the ASSERTs),
`FACT_PLAN_NEXT_WEEK.sql` + migration `2026-10-02_plan_money_columns.sql`, the plan acceptance,
`V_ENGINE_HEALTH.sql` (`plan_pot_reconciliation`).

- [ ] **Step 1: R1.** In `fam`, the pot counts every GOOD keyword, holdout included; the not-good base
  keeps excluding holdout; every move still excludes holdout:

```sql
COALESCE(SAFE_DIVIDE(SUM(IF(side = 'GOOD', w_sp, 0)), MAX(window_days)), 0)                 AS pot_per_day,
COALESCE(SAFE_DIVIDE(SUM(IF(side = 'NOT_GOOD' AND NOT holdout, w_sp, 0)), MAX(window_days)), 0) AS notgood_today_per_day
```

  Restate acceptance C03 ("pot = every GOOD keyword's window spend per day, holdout included (P-15)"),
  C15 (pot + not-good = the window spend excluding not-good holdout rows) and V_ENGINE_HEALTH
  `plan_pot_reconciliation` to the same identity; drop the "(P-2)" labels that claimed the old reading.

- [ ] **Step 2: R7.** In `fam2`:

```sql
LEAST(notgood_today_per_day,
      GREATEST(allowance_target_per_day,
               notgood_today_per_day - (notgood_today_per_day - allowance_target_per_day) / ramp_steps))
  AS allowance_ramped_per_day
```

  The allowance never raises a family's loser spend above what it spends tonight.

- [ ] **Step 3: R8.** Publish per family: `expected_after_upload_per_day` = seats' cost + queued
  candidates' spend at the park price (`w_sp / window_days × park_bid / current_bid`), and
  `share_closed = (notgood_today − expected_after_upload) / NULLIF(notgood_today − allowance_target, 0)`.
  New columns via the migration (one ALTER each). Print both in the family sentence and in SOP §3.

- [ ] **Step 4: fix #11 — holdout campaigns' caps.** In `budgets`, `LOGICAL_OR(holdout) AS is_holdout`
  per campaign; a holdout campaign's `campaign_planned_budget = current_budget`, delta 0, basis
  `NO_MOVE_HOLDOUT`, cap sentence "CAMPAIGN CAP: unchanged — this campaign is in the HOLDOUT arm from
  <eligible_from>; the plan records what it would have done and moves nothing". Extend the holdout
  ASSERT and acceptance C08 with `holdout AND ABS(campaign_planned_budget_delta_per_day) > 0.005`. For
  GOOD-side holdout rows keep `move = 'NONE'` and append the measurement-control clause to the GOOD
  sentence.

- [ ] **Step 5: fix #12 — say what bound the cap.** Basis: `NO_MOVE_*` as today; `FLOORED_AT_NEED` when
  `raw_budget = need_budget` and need differs from the ramp value in either direction; `BAND_SNAPPED_UP`
  / `BAND_SNAPPED_DOWN` when the $20.01–$31.99 snap moved it; `RAMPED` only when the planned cap equals
  `ROUND(current + (need − current) / ramp_steps, 2)`. ASSERT: `basis = 'RAMPED'` implies that equality
  within $0.01. One sentence tail per basis.

- [ ] **Step 6: fix #15 — the ramp step counts uploads.** `ramp_step` = the count of plan batches landed
  for the family since its first plan night (change-log sources `BRAIN:%`, `PACING:%`, `CATALOG:%` with
  an applied status, plus observed changes that confirm them), capped at `ramp_steps`; publish
  `plan_uploads_landed`; print "no step taken yet" when it is 0. Rewrite the comment and SOP §3 step 3
  that say the ramp "converges whether or not anyone uploads".

- [ ] **Step 7: Acceptance and deploy.** New/restated checks with negative controls: C03, C15, C08
  (holdout cap), M1 `allowance_ramped <= notgood_today` (NC: one family above), M2 basis/arithmetic
  agreement (NC: one RAMPED cap off by $1), M3 `expected_after_upload` reconciles to seats + queue at park
  (NC: one queued row dropped). Run the builder once; record per family pot, allowance, expected after
  upload, before vs after. Commit.

---

### Task 5: The builder's seats — tenure (R2), numbering (R15), probes (R12, fix #19), the question's horizon (R13)

**Files:** `SP_BUILD_NEXT_WEEK_PLAN.sql` (`ranked`, `walk`, `prior_plan`, `seated`, `assembled`,
`priced`, the seat sentences, the click-target block near `clicks_requested`),
`SP_MAINTAIN_FAMILY_SEATS.sql`, the plan acceptance.

- [ ] **Step 1: R2 — a seat is held until its verdict date.** Before the walk, take the incumbents: a
  keyword seated in the previous live partition with `verdict_date > as_of_d`, still a candidate tonight
  (`is_cand`, not GOOD, ladder not `DEAD`). Incumbents keep their seat, their seat number and their
  planned price; their cost comes off the allowance first; the walk then seats newcomers in rank order in
  what is left (the fit test unchanged). If tonight's allowance cannot carry all incumbents (it shrank),
  the incumbents with the latest seat date leave first, and the sentence says so. Extend C23 from number
  to occupancy: an incumbent before its date keeps the seat.
- [ ] **Step 2: R15 — numbering.** `prior_plan` reads each keyword's most recent seat number in ANY
  earlier live partition (not only last night's), so a one-night absence does not reissue the number.
  Read `SP_MAINTAIN_FAMILY_SEATS`: its header says a fresh admission now adopts the plan's number —
  verify on the ledger since 2026-09-28 that every admission's `seat_no` equals the plan's for that key on
  the night of admission; fix any path that still re-derives a number. Narrow C23's exception to "the
  register holds the OLD number open for a different keyword". Measure: the builder's continuity ASSERT
  failed 3 of 9 passes 09-29 → 10-01; replay those nights' inputs if possible, otherwise run the builder
  three times today and show no refusal.
- [ ] **Step 3: R12 / fix #19 — probes.** A probe that wins a seat gets move `OPEN_PROBE` (its own
  sentence: "OPEN PROBE at $X for about N clicks a day (about $Y a day), judged after <clicks_requested>
  clicks or on <verdict_date>"); an unseated probe gets move `NONE` and "probe not opened tonight;
  nothing uploaded" (no PARK on a keyword that bought no clicks). The PARK and HOLD_AT_PARK sentences
  branch on service: a keyword with no clicks and no spend reads "not serving: the park price is a floor
  it already does not reach, and it adds nothing to the family's not-good spend". Update the move list in
  the ASSERTs, C06, C14, V_ENGINE_HEALTH `plan_one_move_per_notgood`.
- [ ] **Step 4: R13 — the question spans the settle horizon.** For an ordinary seat
  `clicks_requested = CAST(ROUND(w_clk * settle_days / window_days) AS INT64)`, due on `verdict_date`;
  `expected_cpc` and `implied_daily_spend` recomputed so `clicks_requested × expected_cpc / days_to_due =
  implied_daily_spend` within a cent. Probes keep `click_goal_day × days_to_due`.
- [ ] **Step 5: Acceptance and deploy.** C23 (occupancy), T1 no seat lost before its verdict date while
  still a candidate (NC: a doctored previous partition with a seat dated tomorrow and tonight's walk
  dropping it), T2 seat numbers sticky across a one-night absence (NC), T3 the question's identity
  (NC: one seat's clicks doubled). Run the builder three times; record seats kept, newcomers queued, and
  refusals (expect 0). Commit.

---

### Task 6: Which clock keys a night (R11) and the shadow plan's sentences (fix #25)

**Files:** `SP_BUILD_NEXT_WEEK_PLAN.sql` (`as_of_d`, the DELETE, the sentence assembly),
`V_PLAN_WINDOW_JUDGMENT.sql` (`today`, `plan_hist`), the plan acceptance, `FN_PLAN_SCORECARD.sql` if it
dates nights.

- [ ] **Step 1: R11.** `as_of_d = CURRENT_DATE('America/New_York')`. The judge's `plan_hist` reads
  `as_of < today_ny`, and every "last night" comparison in the judge uses the same New York date. The
  window fence stays on Los Angeles (`window_to = LEAST(watermark − 1, today_la − 2)`): ads days are LA
  days. So within one New York date the window can move forward a day between the 01:00 and 03:40 New
  York passes; that is fresher evidence, not a different night.
- [ ] **Step 2: R11's guard.** Before the DELETE: if today's partition exists and its `calendar_state`
  differs from tonight's, refuse with a clear error ("partition <date> was written under <state>;
  tonight reads <state>; refusing to rewrite"). Under New York keying the calendar is read on the same
  date, so this never fires in normal operation; it is the net under any future clock change.
- [ ] **Step 3: fix #25.** For plan A rows whose `side_a` differs from `side_b`, build the sentence from
  plan A's side ("SHADOW PLAN A: the ladder calls this <ladder_state>, so plan A puts it on the <side_a>
  side; rule B says <verdict>") and plan A's own seat/queue clause; drop the P-4 "carries no planned
  price" clause on any shadow row that has a planned bid.
- [ ] **Step 4: Acceptance.** K1 `as_of` equals the New York date of `built_at` on every partition from
  this deploy on (NC); K2 no partition carries two calendar states (NC); K3 no shadow row's sentence
  names a side its `side` column does not hold (NC). Deploy; run; commit. Note in the SOP that partitions
  before this commit are keyed on the Los Angeles date.

---

### Task 7: Brand defense from the campaign, not from a coverage view (fix #18)

**Files:** `SP_SNAPSHOT_KEYWORD_STATE.sql` (the `is_brand_defense` derivation),
`V_PLAN_WINDOW_JUDGMENT_acceptance.sql` C02.

- [ ] **Step 1:** Derive `is_brand_defense` as `REGEXP_CONTAINS(UPPER(campaign_name), r'BRAND DEFENSE')
  OR` the campaign's experiment strategy is `BRAND_DEFENSE` (join through `DIM_EXPERIMENT_CAMPAIGN` to
  `DIM_EXPERIMENT`) `OR COALESCE(m.is_brand_defense, FALSE)`. `V_BID_CPC_TRANSFER` stays only as the last
  `OR`: it keeps only campaigns with clicks in [MAX(date) − 103, MAX(date) − 14] days, so a dormant
  defense campaign read as "not defense".
- [ ] **Step 2:** Restate C02 to test the derivation (a defense campaign by name or strategy is excluded
  from the plan's universe) instead of the column; NC: a doctored name. Deploy the procedure; run it
  once; record the rows whose flag changed. Commit.

---

### Task 8: The holdout's integrity (R9, fix #27)

**Files:** `V_HOLDOUT_READOUT.sql`, `V_ENGINE_HEALTH.sql`, `architecture/HOLDOUT.md`.

- [ ] **Step 1: R9.** In `V_HOLDOUT_READOUT`, add `contaminated_on` per unit: the first change after
  `eligible_from` that the observed-change ledger (`FACT_PPC_CHANGE_LOG`, `source = 'OBSERVED'`) or the
  change log records on a HOLDOUT unit. Censor each contaminated unit AND its stratum-mates in both arms
  from `contaminated_on` (symmetric, so the comparison stays fair). Today: BOX-SP/PHRASE
  (teen-girl-birthday-gift, White) 75834491759416 and BOX-VIDEO/COMPETE (Copycat, Blue) 76054744633802,
  from 2026-09-27, Ori's pauses. Record in HOLDOUT.md: Ori confirmed on 2026-10-02 that he paused them.
- [ ] **Step 2: fix #27.** V_ENGINE_HEALTH `holdout_unit_changed`: RED when any HOLDOUT unit has an
  observed or logged change after `eligible_from` that the readout has not censored; detail names the
  campaigns. Now that hand changes are recorded, this catches the next console change the same night.
- [ ] **Step 3: Acceptance** (in `HOLDOUT_acceptance.sql` if it exists, else a new
  `HOLDOUT_INTEGRITY_acceptance.sql`): H1 every unit with an observed change after eligibility is
  censored with its stratum-mates (NC: one censoring removed); H2 the check is GREEN after censoring (NC).
  Deploy; commit.

---

### Task 9: Alarms that tell a new problem from an old one

**Files:** `V_ENGINE_HEALTH.sql`, `V_DAILY_BRIEF.sql`, new `tables/FACT_ENGINE_HEALTH_HISTORY.sql`,
new `procedures/SP_SNAPSHOT_ENGINE_HEALTH.sql`, `SP_ORCHESTRATE_DAILY_REFRESH.sql`,
`PLAN_HEALTH_acceptance.sql`.

- [ ] **Step 1: `plan_pass_failed`.** RED when the latest run of `SP_BUILD_NEXT_WEEK_PLAN` in
  `LOG_PIPELINE_RUNS` failed, or any run in the last 24 hours failed; detail = when, and the first 160
  characters of the error. The piece-0 proof found 3 of 9 passes refused 09-29 → 10-01 while both alarms
  read GREEN (one needs three failures in a row, the other a whole missing night).
- [ ] **Step 2: the board's memory.** `FACT_ENGINE_HEALTH_HISTORY` (snapshot_at, check_name, status,
  measured, detail), written by `SP_SNAPSHOT_ENGINE_HEALTH` once per orchestrator pass at the end (one
  read of the board per pass). New orchestrator step mirroring the existing step pattern byte for byte.
- [ ] **Step 3: the SYSTEM line says what is new.** For each RED check, `red_since` = the earliest
  snapshot of the current unbroken RED run. The SYSTEM line lists NEW REDs first ("NEW since <time>:
  …") and standing ones after ("standing: contradiction_rate since <date>, …"). When the history is
  empty it says so rather than calling everything new.
- [ ] **Step 4: Acceptance** in `PLAN_HEALTH_acceptance.sql`: A1 `plan_pass_failed` fires on a doctored
  log with one failed latest run (NC: and not on a log whose latest run succeeded after an earlier
  failure older than 24 hours); A2 `red_since` is the start of the unbroken run (NC: a doctored history
  with a GREEN gap); A3 the snapshot writes one row per check per pass and nothing twice. Deploy the
  table, procedure, views and the orchestrator (diff first). Commit.

---

### Task 10: Prove it

- [ ] Run every touched acceptance suite and paste each check with its result: FACT_PLAN_NEXT_WEEK,
  V_PLAN_WINDOW_JUDGMENT, PLAN_SCORECARD, PLAN_HEALTH, PLAN_CONFIG, THRESHOLD_HISTORY, OBSERVED_CHANGES,
  the holdout suite, and `check_plan_scorecard_hint_branches.py`.
- [ ] Run `SP_BUILD_NEXT_WEEK_PLAN` three times in a row; every run writes, none refuses.
- [ ] Per family, today's live partition against the last partition written before Task 2: pot,
  allowance target and ramped, expected after upload, seats (kept / new / lost), GRACE / HELD / released,
  raises and cuts in $/day, probes opened. State what moved because of the rulings and what moved because
  the data moved a day.
- [ ] Attack: list anything in the rulings table not implemented, any check that can pass vacuously, any
  sentence that names a rule the row does not follow.

## Self-review against the rulings

R1 → Task 4.1 · R2 → 5.1 · R3 → 2.2 · R4 → 2.3 · R5 → 3.1 · R6 → 3.2 (+5 for the builder's ranked CTE) ·
R7 → 4.2 · R8 → 4.3 · R9 → 8.1 · R11 → 6.1–6.2 · R12 → 3.3 + 5.3 · R13 → 5.4 · R14 → 1.2 · R15 → 5.2 ·
R16 → 2.4. Fixes: #11 → 4.4 · #12 → 4.5 · #15 → 4.6 · #16 → 2.5 · #17 → 1.3 · #18 → 7 · #19 → 5.3 ·
#24 → 4.1 · #25 → 6.3 · #26 → 1.4 · #27 → 8.2 · #28 → 1.5. Piece-0 proof: alarm → 9.1, RED-since → 9.2–9.3,
same-day overwrite → R11 (Task 6). Out of scope, stated: audit fix #2 and question #10 (piece 3, on the
THREE_LAYERS contract).

Steps give the rule, the SQL for each rule's core expression, the checks and their negative controls;
the integration into each 700–900-line file is left to the implementer, who must read the file first,
because pasting whole files into this plan would go stale on the first edit.

---

## Follow-up fixes (2026-10-03), from the Task 10 proof

The proof (workflow `wf_3f633eab-f92`) found every ruling built except the items below. None needs a
ruling; each restores what the plan or the ruling already says. Same house rules. One commit per fix,
each with its own check and negative control.

- [ ] **F1 PLAN_SCORECARD C08a.** The control only fired while zero guard decisions were gradable; on
  2026-10-03 20 of 136 became gradable and C08a now FAILs. Rebuild it on a moved-clock copy (grade date
  pinned before the first decision's settle date) so it fires whatever today's date is.
- [ ] **F2 incumbent seat cost.** Under P-16 an incumbent keeps its seat and its planned price, not last
  window's cost. Recompute an incumbent's seat cost tonight as `(w_sp / window_days) × planned_bid /
  current_bid` on tonight's window (probes: `click_goal_day × probe price`), so the direction clause
  ("A RAISE / a cut / no change") and `expected_after_upload` / `share_closed` read tonight's money.
  Measured on 2026-10-03: 30 incumbent rows said "A RAISE" while their price was held or cut ($15.24/day).
- [ ] **F3 GRACE sentence.** State the anchored rule: "grace lasts N nightly judgments (the window length
  in force when it was granted, <date>) through <date>" — not "ONE quiet window (P-5)" while granting 7
  nights on a 3-day window.
- [ ] **F4 the scorecard's clock.** `FN_PLAN_SCORECARD` / `V_PLAN_SCORECARD` date nights on the New York
  date that keys `as_of` since Task 6; fix the view description that still says "below 10".
- [ ] **F5 spec P-7.** Restate P-7's "ties by clicks" to point at P-20 (zero-score candidates by money
  burned, then clicks).
- [ ] **F6 SEAT_REQUEST R02.** It claims the ledger matches the plan's seats "count and content" but
  subtracts counts (it read −1). Compare the key sets both ways; the value is never negative.
- [ ] **F7 judge acceptance Run line.** The header's direct Run line did not finish in 16.6 minutes
  (1.79 M slot-seconds). Point it at `check_judge_memory_controls.py` and say why.
- [ ] **F8 R2 shrink order.** When tonight's allowance cannot carry every incumbent, incumbents leave
  latest-seated first until the rest fit — no fit-test skipping, which let an earlier, costlier incumbent
  leave while a later, cheaper one stayed.
- [ ] **F9 controls vacuous today.** `NC_G4_CLEARED_HONOURED` (no memory cleared tonight) and
  `NC_M3_QUEUE_DROPPED` (the dropped queued row has $0 spend) must inject a row that exercises them.

Out of these fixes, recorded for Ori: the holdout trial's contamination (R9 as built censors 61 of 69
units) and `tools/build_reprice_bulksheet.py`, which still prices by the pre-piece-1 rules (piece 3).
