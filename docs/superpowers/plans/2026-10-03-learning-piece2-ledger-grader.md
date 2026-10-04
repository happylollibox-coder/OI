# Learning contract, piece 2 — the plan's prediction ledger and its grader

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every night, for every keyword the money plan judges, write down two forecasts — *if you do
nothing* and *if you upload the plan* — and 14 days later grade both against what happened, keeping a
report card per family that says how accurate the plan is, how much it is worth, and how many clicks a
keyword needs before its grade means anything.

**Architecture:** A view (`V_PREDICTION_LEDGER`) maps the plan's stored rows into one prediction shape,
two scenarios per row, with no new writing. A nightly procedure (`SP_GRADE_PREDICTIONS`) appends a grade
per prediction to `FACT_PREDICTION_GRADE` once its horizon is 14 days settled, and rebuilds the report
card `T_PREDICTION_SCORECARD`. The builder stops rewriting a night once that night has begun, so a
forecast is always final before the days it forecasts. Health checks put a stale or worsening report card
on the daily brief.

**Tech stack:** BigQuery Standard SQL (view, procedures, tables), `bq` CLI, Python 3.9 control harnesses,
Markdown SOPs. Project `onyga-482313`, dataset `OI`.

**Sources:** the learning contract `docs/superpowers/specs/2026-10-01-learning-contract-design.md` (§4–§8,
§10–§12); the piece-2 design brief (read-only survey of 2026-10-03, saved at
`/private/tmp/claude-504/-Users-ori-Develop/d749fa60-a974-4ae1-8172-1b7a6ff8637b/scratchpad/piece2_brief.md`,
with its query files beside it — read it before any task: it carries the measured constants, the worked
examples, and file:line references for every join this plan reuses); the doctrine
`architecture/THREE_LAYERS.md`.

---

## Ori's rulings for piece 2 (2026-10-03, "all recommended")

| # | question | ruling |
|---|---|---|
| D1 | grade the six August plan nights? | **Yes.** They are graded on the first run, tagged as made under the pre-P-14c rules by `rule_version` and `builder_version`. The spec's "first grades 2026-10-12" is corrected: the first post-outage grade is the 09-30 night, on 10-17 or 10-18. |
| D2 | a forecast must be final before its horizon starts | **(c)** The ledger starts a prediction's horizon on the first full Los Angeles day after `built_at`, and the builder refuses to *rewrite* a night after Los Angeles midnight of its `as_of` (a first write stays allowed at any time). A `builder_version` column records the code that wrote each row. |
| D3 | how to forecast "if you upload the plan" | **(b) anchored:** ACT = DO_NOTHING scaled by the bid change (`r^ε` for clicks, orders and gross profit; `r^(ε+γ)` for spend), a campaign budget cut applied proportionally, PAUSE = 0, and a catalog-free own-rate fallback only for probes with no window clicks. ε = γ = 1.0 seeded; the bid-to-CPC fallback is the measured 0.974, not the spec's unsourced 1.17. The seat's spend is kept as its own column, `alloc_spend`. |
| D4 | the minimum-investment bar | **Keep 0.80**, add a zero-click bucket (always INCONCLUSIVE, counted as "predicted but dark"), and require at least 20 rows before a bucket can set the line. |
| D5 | the piece-0 plan scorecard | **Leave `FN_PLAN_SCORECARD` as it is**, add a parity check against the new grade table, and re-point it in piece 6. A "window" for the report card is the Sunday-start week of `as_of`. |
| D6 | snapshot the catalog's past bids | **Skip** (only needed under D3 (a) or (c)). |

Also recorded 2026-10-03: a seated keyword that later becomes a probe keeps the question it was seated
with (builder v27.168, confirmed by Ori); Ori made no change on Amazon after 2026-09-27.

## House rules binding on every task

- **Targeted `git add` only.** Sixteen unrelated files are dirty. **Never touch, stage or revert**
  `architecture/PPC_CLOSE_THE_LOOP.md`, `cube/schema/ChangeScorecard.js`,
  `dashboard-react/src/pages/ChangeScorecardPanel.tsx`, `scripts/bigquery/tests/OBSERVED_CHANGES_acceptance.sql`,
  `scripts/bigquery/tests/check_change_scorecard_cube.py`, `scripts/bigquery/views/V_CHANGE_SCORECARD.sql`
  (another session is editing them) or the ten older dirty files. Other sessions commit to this branch:
  read `git log -6` before each task and build on HEAD. Commits use `--no-verify` and end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Long jobs:** an agent silent for three minutes is killed, and a `bq` job that runs longer looks
  identical. Submit anything that may exceed ~90 s with `--nosync` and poll with `bq wait JOB 60`, one call
  per Bash invocation. In zsh never hold a command in a variable.
- **Deploy big files with comment lines stripped:**
  `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^[[:space:]]*--' FILE)"`.
- **Never DELETE or UPDATE existing rows** of `FACT_*` or `DE_*` tables; `FACT_PREDICTION_GRADE` is
  append-only. New columns: `ADD COLUMN IF NOT EXISTS`, one per statement, at most four per table per ten
  seconds.
- **Every acceptance check has a negative control** run on a temp copy, with its measured value recorded in
  the file's comments; add an emptiness term wherever an empty input would pass.
- **Never `SELECT` from `V_INTENT_CVR_CURVE`, `_SHADOW`, `V_INTENT_BID_BASE`, `V_INTENT_INDEX_SCORECARD`**,
  and piece 2 needs no catalog table at all (D3 b, D6).
- **Do not run `SP_ORCHESTRATE_DAILY_REFRESH`.** Deploy it only in Task 6, after diffing the deployed body
  against the file (the only difference must be the new step).
- **Register every new object in `config.yaml`**; it must parse. Comments state only what was measured.
- **The guard is read, never re-derived** (`guard_released_by`, `hold_kept_by`).

## File structure

| file | task | responsibility |
|---|---|---|
| `docs/superpowers/specs/2026-10-01-learning-contract-design.md` | 1 | rulings D1–D6 and the brief's corrections |
| `architecture/LEARNING.md` (new) | 1, every task | the SOP: ledger, response model, grader, report card, checks, deploy and verify |
| `scripts/bigquery/migrations/2026-10-03_learning_settings.sql` | 2 | seed the `LEARNING` settings |
| `scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql`, `tables/FACT_PLAN_NEXT_WEEK.sql`, migration `2026-10-03_plan_builder_version.sql` | 3 | the freeze guard and `builder_version` |
| `scripts/bigquery/views/V_PREDICTION_LEDGER.sql` (new) | 4 | the plan's predictions, two scenarios |
| `scripts/bigquery/tables/FACT_PREDICTION_GRADE.sql`, `tables/T_PREDICTION_SCORECARD.sql` (new) | 5 | the grades and the report card |
| `scripts/bigquery/procedures/SP_GRADE_PREDICTIONS.sql` (new) | 5 | the grader |
| `scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql` | 6 | one new step |
| `scripts/bigquery/views/V_ENGINE_HEALTH.sql`, `V_DAILY_BRIEF.sql`, `tests/PLAN_HEALTH_acceptance.sql` | 6 | the checks and the brief |
| `scripts/bigquery/tests/PREDICTION_CONTRACT_acceptance.sql` (new) + a controls harness | 7 | the contract suite |
| `config.yaml` | every task | registrations |

---

### Task 1: Record the rulings and write the SOP

Docs only.

- [ ] **Step 1:** In the learning-contract spec, add a dated section "§14 Piece-2 rulings (2026-10-03)" with
  D1–D6 as in the table above, and correct in place, each with a one-line note: §10's "first grades on
  2026-10-12" (→ the first post-outage grade is the 09-30 night on 10-17/10-18; August grades on the first
  run); §6 (the response model is anchored on DO_NOTHING; 1.17 → 0.974 measured); §7 (a zero-click bucket;
  UNGRADABLE only for an archived keyword or campaign; the spec never defined RIGHT/WRONG for the plan —
  define it as below); §5 (horizon start); §9 (`proposals_open` moves to piece 6). Quote the brief's
  measured numbers with the query that produced each, never bare.
- [ ] **Step 2:** Write `architecture/LEARNING.md`: what the ledger is (one row per prediction per
  scenario), the two scenarios in words, the response model with every setting it reads, how a grade is
  decided, the report card's rows, the health checks, the deploy order, and "how to read the report card
  in one query". Every later task appends its own "deploy and verify" there.
- [ ] **Step 3:** Commit.

---

### Task 2: Seed the LEARNING settings

- [ ] **Step 1:** `scripts/bigquery/migrations/2026-10-03_learning_settings.sql` inserts into
  `DE_COACH_THRESHOLDS` under `strategy_id = 'LEARNING'`, `coach_mode = 'GUARDIAN'`, `product_family =
  NULL`, `source = 'SEED'`, `updated_by = 'learning-piece2'`, each with a description naming its source:

| key | value | source |
|---|---|---|
| `CLICK_BID_ELASTICITY` | 1.0 | spec §6 seed; the grader tunes it via proposals (piece 6) |
| `CPC_BID_EXPONENT` | 1.0 | spec's CPC = bid × ratio implies 1.0; `V_BID_CPC_TRANSFER` measures 0.778 (CI 0.638–0.872) |
| `BID_TO_CPC_RATIO_FALLBACK` | 0.974 | SUM(cost)/SUM(clicks × live bid) 2026-09-02..09-29 (brief §3) |
| `OWN_CVR_MIN_CLICKS` | 30 | brief §3: 180 of 361 keys reach it |
| `SETTLE_HORIZON_DAYS` | 14 | settle completion reaches 1.0 at age 14 |
| `MATCH_WINDOW_DAYS` / `MATCH_BID_TOL` / `MATCH_BUDGET_TOL` | 3 / 0.005 / 0.01 | spec §7 |
| `MIN_INVEST_SIDE_ACCURACY` | 0.80 | spec §7, ruling D4 |
| `MIN_INVEST_MIN_ROWS` | 20 | ruling D4 |
| `MIN_GRADED_WINDOWS` / `REGRESSION_MAX` | 3 / 0.10 | spec §9 |

  The migration is re-runnable: insert only keys that do not exist (never delete or update). Run it, and
  CALL `SP_SNAPSHOT_THRESHOLDS()` once so the history records them.
- [ ] **Step 2:** Check: every key present once under that exact scope (negative control: a doctored copy
  with one key under `coach_mode = 'BLITZ'`). Commit.

---

### Task 3: The freeze — a night is final once it has begun (D2 c)

- [ ] **Step 1:** Migration `2026-10-03_plan_builder_version.sql` adds `builder_version STRING` to
  `FACT_PLAN_NEXT_WEEK` (mirror it in the table DDL). The builder writes its own version string (the
  `vNN.NNN` of its header) on every row.
- [ ] **Step 2:** Before the DELETE of tonight's partition: if a partition for `as_of_d` already exists and
  `CURRENT_DATE('America/Los_Angeles') >= as_of_d` (Los Angeles midnight of that night has passed), do not
  rewrite it — log a clear `SELECT 'FROZEN: partition <as_of> was written at <built_at>; its first day has
  begun; not rewritten' AS log_message` and return successfully, so `LOG_PIPELINE_RUNS` records OK, the
  seat-request append that follows remains idempotent, and `plan_pass_failed` stays GREEN. A first write
  for a night with no partition is always allowed (a late plan is still a plan; the ledger shifts its
  horizon, Task 4).
- [ ] **Step 3:** Checks with negative controls: F1 every partition written after this deploy has
  `built_at` before Los Angeles midnight of its `as_of`, unless it was the night's first write (NC: a
  doctored second write after midnight); F2 every row carries `builder_version` from this deploy on (NC:
  one NULL). Prove the guard on a temp copy of the builder logic (no real rewrite): it refuses a rewrite
  dated after midnight and allows a first write. Record in the SOP that under New York keying the 05:00 UTC
  pass writes each night and the 07:35 / 16:00 UTC passes are no-ops, and what that costs in freshness
  (the 05:00 pass judges a window one day older). Deploy; commit.

---

### Task 4: `V_PREDICTION_LEDGER` — the plan's two forecasts per keyword

- [ ] **Step 1:** One row per (`as_of`, `plan`, `campaign_id`, `keyword_id`) × `scenario` IN
  (`DO_NOTHING`, `ACT`), from `FACT_PLAN_NEXT_WEEK`, all partitions including August (D1). Columns as in
  the brief §2 table: `predictor` = `'PLAN_' || plan`, `variant` = `plan`, `as_of`, `built_at`,
  `builder_version`, `horizon_from = GREATEST(as_of, DATE(built_at, 'America/Los_Angeles') + 1)`,
  `horizon_to = horizon_from + window_days - 1`, `family`, `campaign_id`, `keyword_id`, `channel`,
  `calendar_state`, `is_live_plan`, `holdout`, `family_bar`, `min_orders` (the state's row of the config
  history in force at `built_at`), `current_bid`, `planned_bid`, `campaign_current_budget`,
  `campaign_planned_budget`, `move` (ACT only), `alloc_spend = planned_spend_per_day * window_days`,
  `act_is_noop`, `pred_side`, `basis_clicks = w_clk`, `basis_spend = w_sp`, the five predicted numbers,
  `rule_version`, `response_model_version`.
- [ ] **Step 2: DO_NOTHING** — `pred_clicks = w_clk`, `pred_spend = w_sp`, `pred_orders = w_ord /
  settle_factor_eff`, `pred_gp = w_gp_corrected`, `pred_net = w_gp_corrected - w_sp`.
- [ ] **Step 3: ACT (anchored)** — exactly the brief's formulas:

```sql
-- r = the bid change the plan asks for; 1 where it asks for none
r = SAFE_DIVIDE(new_bid, current_bid)   -- new_bid: planned_bid for REPRICE / OPEN_PROBE / PARK
                                        -- (PARK: ROUND(COALESCE(bid_park, bid_floor, current_bid), 2)),
                                        -- current_bid for NONE / NONE_HOLDOUT / HOLD_AT_PRICE / HOLD_AT_PARK
pred_clicks = w_clk                           * POW(r, eps)
pred_spend  = w_sp                            * POW(r, eps + gamma)
pred_orders = (w_ord / settle_factor_eff)     * POW(r, eps)
pred_gp     = w_gp_corrected                  * POW(r, eps)
pred_net    = pred_gp - pred_spend
-- PAUSE: all five 0
```

  Then the campaign budget: where `campaign_planned_budget < campaign_current_budget`, scale every ACT row
  of the campaign by `LEAST(1, SUM(DO_NOTHING spend) * planned / current / SUM(ACT spend))` over the
  campaign's rows; a raise has no effect in v1 (stated as a limitation). **Open 2026-10-03 (Task-1
  review; spec §6, §14.1, §14 E8): Ori rules this clause before this task starts.** The form above
  also cuts campaigns whose ACT run rate is already at or below the new budget; the recommended form
  is `LEAST(1, GREATEST(planned * H, SUM(DO_NOTHING spend) * planned / current) / SUM(ACT spend))`,
  H = `window_days`. The recommended form is a cap: on a campaign the plan cuts, ACT spend is capped at
  the new budget × H, and where DO_NOTHING already overdelivers its current budget
  (`SUM(DO_NOTHING spend) / H > current`) the cap falls back to the proportional cut. On the stored
  nights it is the plain cap on 367 of the 369 cut campaign-nights and gives the plain cap's factor on
  all 369 (spec §14 E8, Q7). The form above is the proportional cut D3 names; the recommended one is
  not, so Ori chooses. Build the ruled form and record it in `architecture/LEARNING.md` §3.
  Zero-basis OPEN_PROBE rows use the brief's seat rule (spend = `seat_cost_per_day × H`, clicks at
  `planned_bid × BID_TO_CPC_RATIO_FALLBACK`, CVR and GP/order from the keyword's own settled 90-day
  record in `FACT_KEYWORD_STATE_HISTORY` at `built_at` when `settled_clk90 >= OWN_CVR_MIN_CLICKS`, else
  the family × channel pooled settled rate).
  Every other zero-basis ACT row predicts 0. Settings are read from `DE_COACH_THRESHOLDS`
  (`strategy_id = 'LEARNING'`), never as literals.
  *Corrected 2026-10-04 (fix L1, found by the Task-8 proof): the view read the snapshot at query time
  and its `ks` CTE kept the newest copy of the date with no `captured_at <= built_at` filter, while
  `SP_APPEND_KEYWORD_STATE_HISTORY` keeps only the newest copy of a date, so a re-capture or backfill
  of an older `snapshot_date` would have moved a stored night. The snapshot is now read once, by
  `SP_FREEZE_LEDGER_INPUTS`, which `SP_BUILD_NEXT_WEEK_PLAN` v27.177 CALLs right after it writes the
  night, into the append-only `FACT_PREDICTION_LEDGER_INPUTS`; `V_PREDICTION_LEDGER` v27.177 prices
  from each night's first freeze and never reads the history (`architecture/LEARNING.md` §3, §10
  "Fix L1").*
- [ ] **Step 4: versions** — `rule_version` = the `history_id` of the `DE_PLAN_CONFIG` row for the row's
  `calendar_state` in force at `built_at` (brief §2 "rule_version"), `|| ':' || builder_version`
  (`'pre-v27.170'` where NULL); `response_model_version` = `'RUN_RATE'` for DO_NOTHING and `'RM1:'` + the
  history ids of the LEARNING settings in force for ACT. *Corrected 2026-10-04 (fix L1): the
  `builder_version` part is the night's frozen `rule_builder_tag` in `FACT_PREDICTION_LEDGER_INPUTS`,
  not the plan row's column, so a backfill of the pre-v27.170 NULLs cannot rename a stored night's rule
  (acceptance L5c counts such a backfill).*
- [ ] **Step 5: Checks** (in `PREDICTION_CONTRACT_acceptance.sql`, started here): L1 two scenarios per plan
  row, five numbers non-NULL, `basis_clicks >= 0`, a `rule_version` (NC per term); L2 **anchoring**: on
  every row with `act_is_noop` and no budget cut, ACT equals DO_NOTHING to the cent (NC: one row's r
  doctored to 0.9); L3 the brief's two worked examples reproduce (305171316086021 on 10-03, 439648864838275);
  L4 the view is deterministic (two reads, keyed FULL OUTER JOIN with tolerance, per house memory on float
  parity). Measure the view's cost. Deploy; commit.

---

### Task 5: `SP_GRADE_PREDICTIONS`, `FACT_PREDICTION_GRADE`, `T_PREDICTION_SCORECARD`

- [ ] **Step 1: tables.** `FACT_PREDICTION_GRADE` per the brief §4 "Proposed table" (partition by `as_of`,
  cluster by `predictor, family`; append-only; `regrade_seq`; frozen copies of the five predicted numbers
  and `built_at`). `T_PREDICTION_SCORECARD` per the brief §6.
- [ ] **Step 2: gradability** — a ledger row is gradable when `DATE_ADD(horizon_to, INTERVAL
  SETTLE_HORIZON_DAYS DAY) <= LEAST(MAX(date), FN_ADS_ANCHOR_CAP())` over `FACT_AMAZON_ADS` (the house
  watermark, `V_PLAN_WINDOW_JUDGMENT`'s `wm` CTE; store it on the grade row as `watermark`) and it has no
  current grade. *Corrected 2026-10-03 (Task-1 review): was `<= FN_ADS_ANCHOR_CAP()`, which is calendar
  only and never reads `FACT_AMAZON_ADS`, so a stalled table would grade missing days as zero.*
- [ ] **Step 3: realised numbers** — `FACT_AMAZON_ADS` on `campaign_id + keyword_id`, `date BETWEEN
  horizon_from AND horizon_to`; a missing row means 0 (FACT holds clicked rows only). `UNGRADABLE` only
  when the keyword or its campaign is ARCHIVED (case-insensitive) in the SCD within the horizon.
- [ ] **Step 4: which scenario applied** — the brief §4 Step 2 rules over `V_PPC_CHANGE_LOG_LANDED`
  (expected components; ACT only when every component matched and nothing else changed; DO_NOTHING when the
  keyword and its campaign were untouched; else OTHER_ACTION). `placement_changed` from
  `FACT_KEYWORD_STATE_HISTORY.m_effective`. *Corrected 2026-10-04 (Task-5 review, ruled "all
  recommended"): the brief's window, Los Angeles dates `as_of … as_of + MATCH_WINDOW_DAYS`, is
  replaced by the prediction's clock — only changes applied at or after `built_at`; a match before the
  Los Angeles midnight that starts `horizon_from + MATCH_WINDOW_DAYS`; the other-change scan to the end
  of `horizon_to` (an SB keyword's own changes one day longer). `SP_GRADE_PREDICTIONS` v27.174; the
  August band re-graded (spec §7, §14.1; `architecture/LEARNING.md` §4, §10 "Task 5 follow-up").*
  *Corrected 2026-10-04 (Task-5 review 2): a change is read at its landing on Amazon — a
  `LOGGED_AND_SEEN_ON_AMAZON` row at the earliest `applied_at` of the observed rows its
  `paired_change_id` names, never its log stamp — and the extra SB day covers only `SEEN_ON_AMAZON_*`
  changes. `SP_GRADE_PREDICTIONS` v27.175; no stored grade moved, so no re-grade
  (`architecture/LEARNING.md` §4, §10 "Task 5 follow-up 2").*
- [ ] **Step 5: the grade** — realised side = GOOD when `orders >= min_orders AND GP / spend >=
  family_bar` (the judge's own test). Buckets `0, 1–5, 6–10, 11–20, 21–40, 41–80, 81+` by realised clicks.
  Inside one run, in this order: errors; then per predictor × family × calendar_state the cumulative,
  spend-weighted side-accuracy curve over every graded row including tonight's, and the line = the smallest
  bucket floor whose cumulative accuracy ≥ `MIN_INVEST_SIDE_ACCURACY` with ≥ `MIN_INVEST_MIN_ROWS` rows
  (NULL when none); then labels: `UNGRADABLE`, else `INCONCLUSIVE` in bucket 0 or below the line (or when
  there is no line), else `RIGHT` / `WRONG` by side correctness. Store `min_clicks_at_grade` on each row.
  The scenario that did not apply is graded on accuracy only, with `is_applied = FALSE`.
- [ ] **Step 6: the report card** — rebuild `T_PREDICTION_SCORECARD` at the end of the procedure (brief §6
  row types: ACCURACY, MONEY with `counterfactual_net_per_alloc` and `lift_control =
  'DO_NOTHING_PREDICTION'`, CURVE / LINE with `min_clicks` and `min_dollars`, HONESTY, YOUNG, NEXT_WEEK);
  levels WINDOW (Sunday-start week of `as_of`), TRAILING_3, SINCE_START.
- [ ] **Step 7: idempotence and re-grade** — a second run inserts 0 rows; `regrade_from DATE` re-grades
  exactly the named band with `regrade_seq + 1` and a `regrade_reason`.
- [ ] **Step 8:** Run it. Expect the six August nights graded on this first run and nothing after them yet.
  Record the report card's August numbers beside the brief's preview (side accuracy by bucket, the absent
  line, DO_NOTHING totals) and explain any difference. Deploy; commit.

---

### Task 6: On the schedule, on the board, on the brief

- [ ] **Step 1:** Orchestrator: a new step "Task 20.8f SP_GRADE_PREDICTIONS" between
  `SP_APPEND_CATALOG_FORECAST` and `SP_REFRESH_CUBE_TABLES` (brief §8), the standard step block byte for
  byte. Diff the deployed body first; deploy; do not run the orchestrator.
- [ ] **Step 2:** `V_ENGINE_HEALTH` checks (brief §9; insert before c33, which must stay last):
  `prediction_grades_fresh` (RED when a gradable ledger row has no current grade one night past due —
  gradable on the house watermark of Task 5 Step 2, `horizon_to + SETTLE_HORIZON_DAYS + 1 <= watermark`;
  empty population RED; the detail prints the watermark beside `FN_ADS_ANCHOR_CAP()`),
  `prediction_regression` (per predictor, trailing 3 vs prior 3 windows on `mae_net_share` or
  `counterfactual_net_per_alloc`, RED when worse by more than `REGRESSION_MAX`; INFO "YOUNG" until 6
  windows exist; names any `rule_version` / `builder_version` change between), and
  `response_model_unverified` (INFO until an applied, non-no-op ACT grade exists). Add the two RED-able
  checks to `V_DAILY_BRIEF`'s priority list and update the copies in `PLAN_HEALTH_acceptance.sql` in the
  same step.
- [ ] **Step 3:** Checks with negative controls in `PLAN_HEALTH_acceptance.sql`: each new check fires on a
  doctored copy (a gradable row with no grade; a worse trailing window; an applied ACT row). Deploy;
  commit.

---

### Task 7: The contract suite and the parity check

- [ ] **Step 1:** Complete `PREDICTION_CONTRACT_acceptance.sql` with the spec §11 checks 1–5 and 8 (6–7
  arrive with piece 6): both scenarios on every row; exactly one current grade per gradable row; a second
  grader run inserts 0 and a `regrade_from` run re-grades exactly the named band; the labels partition the
  graded rows and no INCONCLUSIVE row sits above its `min_clicks_at_grade`; three FIXTURE predictions
  (written under `predictor = 'FIXTURE'`, excluded from every aggregate) read RIGHT, WRONG and
  INCONCLUSIVE; the health checks exist and `prediction_grades_fresh` is GREEN after a run. A frozen
  prediction never changes after grading (NC: a doctored ledger row).
- [ ] **Step 2:** D5 parity: for the nights both grade, `FN_PLAN_SCORECARD`'s GRADE allocation and
  realised net equal the grade table's computed the FN way, within a cent (NC: one row doctored). State in
  the SOP that FN keeps its own clock until piece 6.
- [ ] **Step 3:** A controls harness in the house pattern (`--submit` / `--collect`, one statement per
  copy). Run it; commit.

---

### Task 8: Prove it

- [ ] Run every touched suite (async, polled): PREDICTION_CONTRACT, PLAN_HEALTH, FACT_PLAN_NEXT_WEEK,
  PLAN_SCORECARD, PLAN_CONFIG, THRESHOLD_HISTORY and the controls harnesses; paste each check.
- [ ] Run `SP_GRADE_PREDICTIONS` twice: the second inserts 0. Run `SP_BUILD_NEXT_WEEK_PLAN` once after Los
  Angeles midnight of today's `as_of` and show it logs FROZEN, writes nothing, and the seat-request append
  after it changes nothing.
- [ ] The report card in plain numbers per family: August side accuracy per bucket, the minimum-investment
  line (or why there is none), DO_NOTHING forecast vs realised, and tonight's NEXT_WEEK "do nothing $X /
  upload the plan $Y".
- [ ] Attack: any check that can pass vacuously, any number in a comment that was not measured, any
  ledger value that could change after grading.
  *Fix L1 (2026-10-04, from this proof): a re-capture or backfill of an older keyword-state
  `snapshot_date`, or a backfill of `builder_version`, would have moved stored nights' `ACT` or
  `rule_version`. Fixed by freezing each night's inputs at the build (`FACT_PREDICTION_LEDGER_INPUTS`,
  `SP_FREEZE_LEDGER_INPUTS`, builder and ledger v27.177); acceptance L5 and
  `scripts/bigquery/tests/check_ledger_freeze_controls.py` check it (`architecture/LEARNING.md` §10
  "Fix L1").*

## Self-review

D1 → Tasks 4 (all partitions) and 5.8 · D2 → Tasks 3 and 4.1 (`horizon_from`) · D3 → Task 4.3 and Task 2
(settings) · D4 → Tasks 2 and 5.5 · D5 → Task 7.2 · D6 → not built. Spec §11 checks 1–5, 8 → Task 7; 6–7 →
piece 6. `proposals_open` → piece 6. Steps give the rule and its SQL core; integration into the existing
1,600-line builder and 900-line health view is left to the implementer, who must read the file first.
