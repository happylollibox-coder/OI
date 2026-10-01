# The learning contract — every prediction saved, graded, and turned into a proposal

**Date:** 2026-10-01 · **Status:** design approved by Ori in conversation (sections 1–5), not yet implemented
**Supersedes nothing.** Extends `2026-08-23-next-week-money-plan-design.md` (the plan) and
`2026-08-31-intent-cvr-index-registry-design.md` (the catalog). Builds on the four pieces in flight on
2026-10-01 (alarm, observed changes, plan scorecard, rules with history), referred to below as **piece 0**.

## 1. Why

Ori, 2026-10-01: *"The first step is to make sure the system is a learning system and it saves the
relevant data … I want you to be sure this plan guarantees that each day it works, prediction is
better. So predictions and actions will be better."*

Measured on 2026-09-30, the loop was open in two places. Decisions are saved (`FACT_PLAN_NEXT_WEEK`
nightly since 09-28, `FACT_ENGINE_PROPOSALS` and `FACT_KEYWORD_STATE_HISTORY` nightly) and outcomes
are saved (`FACT_AMAZON_ADS`, `FACT_ADS_RESTATEMENT`). But **actions** stopped being recorded on
2026-08-25 (82 hand changes seen only by Fivetran), the plan's **grade** was designed in August and
never built, and the **rule settings** that matter most (the last-day threshold) were literals in a
view with no history. Piece 0 closes those. This spec is what makes the closed loop *learn*: a
prediction ledger, a grader, a proposer, and the alarms that make getting worse impossible to miss.

The month of unwritten plans (2026-08-29 → 09-28) is the cautionary tale: `LOG_PIPELINE_RUNS` logged
every failure and no surface Ori reads said a word. Nothing here is allowed to fail that quietly.

## 2. Rulings made in this conversation (each overrulable by one line)

| # | ruling | Ori's choice |
|---|---|---|
| L-1 | **"Better" is measured two ways:** accuracy (predicted vs realised, settled) says *why* a rule is wrong; money (net profit per allocated dollar) decides *whether* to switch. Both at family × calendar-state grain. | C |
| L-2 | **The system proposes, Ori disposes.** No rule changes itself. Accepting is one row. | A |
| L-3 | The calibration refit built 09-11 (`INTENT_CVR_CALIBRATION`, 10% band, dead-band 0.25%) **stays as it is** — a level correction reviewed when it shipped, not a rule. | A |
| L-4 | **One ledger, one grader, one queue.** Every predictor maps into one shape; one grader; one proposals table. Adding an index, a rule or an engine is a row. | 1 |
| L-5 | **Every prediction is a pair of futures:** `DO_NOTHING` (keep today's bid and budget) and `ACT` (upload the predictor's move), same horizon, same five numbers. The brief says "do nothing: $X; upload the plan: $Y". | — |
| L-6 | **The grader states the minimum investment:** per predictor × family × state, the smallest click bucket at which accuracy clears a declared bar, in clicks and dollars. Below it a grade is `INCONCLUSIVE`, never `WRONG`. | — |
| L-7 | **Every proposal explains itself on facts and states the next-12-month effect:** graded facts, a 12-month replay, a 12-month projection with its assumptions and the predictor's own grade printed on it, and the way back. | — |
| L-8 | **Order of work:** audit and fix the plan's rules → ledger and grader for the plan → make the plan executable (plan Tasks 3+4) → catalog weekly forecast → backtest harness (Task 6) → proposer and panel → surfaces and SOP (Tasks 7+8). | — |

## 3. The contract — what is guaranteed and what is not

No system can guarantee that every day's prediction beats the day before: sales settle over 14 days
and one week is noise. What is guaranteed:

1. **Every prediction is written down before its outcome exists.**
2. **Every prediction is graded on settled numbers**, automatically, 14 days after its horizon ends,
   and the grade is stored beside it.
3. **A rule changes only by an accepted proposal** whose evidence is the graded record, and a change
   that makes the next three graded windows worse raises a `REVERT` proposal by itself.
4. **Getting worse is impossible to miss:** grades that stop arriving, or three graded windows worse
   than the three before, are RED on the daily brief with the rule that moved named.

Under this contract predictions cannot get quietly worse, and they get better whenever the evidence
allows and Ori accepts.

## 4. Architecture

```
PREDICT ──► LEDGER ──► GRADE ──► PROPOSE ──► (Ori accepts) ──► APPLY, with history
                         │
                         └──► ALARMS on V_ENGINE_HEALTH and V_DAILY_BRIEF
```

| part | object | writes | runs |
|---|---|---|---|
| predictors | `FACT_PLAN_NEXT_WEEK` (exists), `FACT_INTENT_FORECAST` (new) | their own tables | plan nightly (exists); catalog weekly, Sunday, after the catalog refresh |
| ledger | `V_PREDICTION_LEDGER` | nothing (a union view) | — |
| grader | `SP_GRADE_PREDICTIONS` → `FACT_PREDICTION_GRADE` | grades, min-investment curve, honesty rows | nightly, after `SP_FACT_AMAZON_ADS` and the observed-change recorder |
| proposer | `SP_PROPOSE_RULE_CHANGES` → `DE_RULE_PROPOSALS` | proposals with the evidence block | nightly, after the grader |
| apply | `SP_APPLY_ACCEPTED_PROPOSALS` | the rule tables, via their existing recipes, `change_reason = proposal_id` | nightly, before the predictors read their settings |
| alarms | `V_ENGINE_HEALTH` checks, `V_DAILY_BRIEF` lines | — | on read |

All settings this spec declares live in `DE_COACH_THRESHOLDS` under `strategy_id = 'LEARNING'`,
`coach_mode = 'GUARDIAN'`, `product_family = NULL`, seeded by a dated migration, snapshotted by the
threshold history (piece 0, Task D). Never a literal in a view.

## 5. The ledger — one shape for every prediction

`V_PREDICTION_LEDGER`, one row per prediction per scenario:

| column | meaning |
|---|---|
| `predictor` | `PLAN_A`, `PLAN_B`, `CATALOG`; later any engine |
| `variant` | plan: the letter; catalog: the index set — `NONE`, one index name, `ALL`, or a sorted CSV |
| `as_of` | the night the prediction was made |
| `horizon_from`, `horizon_to` | the days it is about: plan `as_of` … `as_of + window_days − 1`; catalog the coming Sunday–Saturday |
| `family`, `campaign_id`, `keyword_id`, `channel`, `calendar_state` | the grain |
| `scenario` | `DO_NOTHING` or `ACT` |
| `move` | for `ACT`: the proposed bid, park/pause, budget; NULL for `DO_NOTHING` |
| `pred_spend`, `pred_clicks`, `pred_orders`, `pred_gp`, `pred_net` | the five numbers over the horizon |
| `pred_side` | plan only: 1 good / 0 not-good |
| `basis_clicks`, `basis_spend` | the evidence the prediction stood on (its window) |
| `rule_version` | the threshold-history snapshot id in force that night |
| `response_model_version` | which response model priced `ACT` |

**The plan** needs no new writing: a mapping view reads `FACT_PLAN_NEXT_WEEK`. `DO_NOTHING` is the
keyword's last-window run-rate per day × horizon days, settle-corrected through
`V_PLAN_SETTLE_COMPLETION`. `ACT` is the seat: `planned_spend_per_day × window_days` for spend, and
the response model for clicks, orders, gross profit and net at `planned_bid` (or the park / pause
price). Both plans write both scenarios for every keyword, so `PLAN_A` vs `PLAN_B` is a paired
comparison on identical keys.

**The catalog** gets `FACT_INTENT_FORECAST`, written every Sunday by `SP_SNAPSHOT_INTENT_FORECAST`
right after the catalog refresh in the orchestrator: for every keyword that served in the week just
ended, one row per index variant (2^N variants; N = 2 today → `NONE`, `season_month`, `season_phase`,
`ALL`), `DO_NOTHING` at the current bid and `ACT` at the catalog's `target_bid`. Value per click comes
from a materialised curve per variant — the money gate's `T_TMP_GATE_*` method, one `CREATE OR REPLACE
TABLE` per variant (~27k slot-seconds each, its own statement, weekly). Variants beyond 5 indexes fall
back to `NONE`, each-alone and `ALL` only; the grader's add-one-in / leave-one-out reading covers the
rest. The first write also stores the catalog's own cells for the keyword (`cvr_hat`, `gp_per_order`,
`confidence`) so a prediction can be explained a year later without re-running the view.

**Not in the ledger:** anything a human did. Actions live in the change log (piece 0, Task B records
them from Fivetran as `source = 'OBSERVED'`). The grader joins the two to decide which scenario
applied.

## 6. The two scenarios and the response model

`DO_NOTHING` is a run-rate projection and needs no model. `ACT` needs one: what a different bid or
budget does to clicks and cost. Version 1, deliberately simple, every constant a `LEARNING` setting:

```
expected_cpc     = new_bid × bid_to_cpc_ratio            -- ratio measured per family × channel over the
                                                         -- trailing 28 settled days from FACT_AMAZON_ADS
                                                         -- and FACT_KEYWORD_STATE_HISTORY; fallback the
                                                         -- account's click-weighted 1.17 (measured 08-11)
expected_clicks  = last_window_clicks_per_day × horizon_days
                   × POW(new_bid / current_bid, CLICK_BID_ELASTICITY)   -- seed 1.0; the grader moves it
                   capped so expected_spend ≤ campaign budget × horizon_days
expected_spend   = expected_clicks × expected_cpc
expected_orders  = expected_clicks × cvr_hat               -- the served catalog cell for the keyword's
                                                         -- product × intent × month; fallback the
                                                         -- keyword's own settled 90-day CVR
expected_gp      = expected_orders × gp_per_order          -- the catalog's gp_source ladder
expected_net     = expected_gp − expected_spend
PARK / PAUSE     = clicks at the park price through the same formula / zero
```

The response model is itself graded (section 7) and tuned by proposals (section 8, rule 4). Its
first weeks will show how wrong it is; that is the point of writing it down.

## 7. The grader

`SP_GRADE_PREDICTIONS`, nightly from the orchestrator after `SP_FACT_AMAZON_ADS` and the observed-
change recorder. For every ledger row whose `horizon_to` is at least `SETTLE_HORIZON_DAYS` (14) complete
days old and that has no grade yet, it:

1. reads the realised spend, clicks, orders, gross profit and net for the keyword over
   `horizon_from … horizon_to` from `FACT_AMAZON_ADS` as read today;
2. decides which scenario applied from the observed-change record: `ACT` if an observed change on the
   keyword/campaign within 3 days after `as_of` matched the proposed move within tolerance (bid
   ± $0.005, budget ± $0.01, state exact), else `DO_NOTHING`; a change that matched neither is
   `OTHER_ACTION` and the row is graded on neither scenario (reported);
3. buckets the keyword-week by realised clicks: `1–5, 6–10, 11–20, 21–40, 41–80, 81+`;
4. appends one `FACT_PREDICTION_GRADE` row per ledger row: the realised five numbers, the applied
   scenario, absolute and signed error on net, side correctness (plan), the bucket, and
   `grade ∈ {RIGHT, WRONG, INCONCLUSIVE, UNGRADABLE}` where `INCONCLUSIVE` means the bucket sits below
   the family's minimum-investment line and `UNGRADABLE` means no outcome rows exist (keyword gone,
   campaign deleted) — counted, never dropped. Order inside one run: errors first, then the curve and
   the line from every graded row of the family (including tonight's), then the labels — so the line
   and the labels can never disagree (contract check 4).

**Idempotent:** a prediction is graded once (`NOT EXISTS` on the grade key). Settlement moves the
outcome slightly for days after; a re-grade happens only under an explicit `regrade_from` argument, so
grades do not drift night to night.

**Published aggregates** (a view over the grade table, materialised by the same procedure into
`T_PREDICTION_SCORECARD` for the surfaces), per `predictor × variant × family × calendar_state`:

- **Accuracy** — for the scenario that applied: spend-weighted mean absolute error of net in dollars
  and as a share of realised spend; bias (predicted − realised, signed); side accuracy for the plan
  (share of spend whose predicted side came true). Three levels: the horizon week, the trailing
  3 windows, since start.
- **Money** — `ACT`: realised net per predicted dollar where acted on; `DO_NOTHING`: realised net per
  dollar; **lift**: predicted `ACT − DO_NOTHING` vs realised lift, against the holdout arm
  (`DE_HOLDOUT_ASSIGNMENT`, eligible since 09-01) where the family has one, else against the
  `DO_NOTHING` prediction with that prediction's own accuracy printed beside it; `lift_control` names
  which.
- **Minimum investment** — accuracy per click bucket, the smallest bucket clearing the bar
  (`MIN_INVEST_SIDE_ACCURACY` 0.80 for the plan's side; `MIN_INVEST_VPC_ERROR` 0.25 for the catalog's
  value per click), published as `min_clicks` and `min_dollars = min_clicks × family settled CPC`. The
  whole curve is published, not only the line.
- **Honesty rows** — ungradable count, `ACT` rows with no matching action, `OTHER_ACTION` count, and
  a `YOUNG` row saying in words when nothing is old enough to grade.

**Relation to the existing scorecards.** The plan scorecard (piece 0, Task C) keeps its
`GRADE` / `RECOMMENDATION` / `GUARD` rows and reads them from `FACT_PREDICTION_GRADE` instead of
recomputing. The intent index scorecard (`V_INTENT_INDEX_SCORECARD`) stays as the *monthly* instrument
for seasonal indexes: a Christmas index changes one month's prediction, and weekly grading sees each
month once a year.

## 8. Proposals — the system suggests, Ori decides

**`DE_RULE_PROPOSALS`**: `proposal_id`, `created_at`, `rule_table`, `rule_key`, `scope`,
`current_value`, `proposed_value`, `decision_rule`, `evidence_facts`, `evidence_replay_12m`,
`evidence_projection_12m`, `evidence_risk`, `evidence_kind ∈ {GRADED, BACKTEST}`,
`projection_status ∈ {VERIFIED, UNVERIFIED}`, `status ∈ {OPEN, ACCEPTED, REJECTED, EXPIRED, REVERTED}`,
`decided_at`, `decided_by`, `note`, `applied_at`, `history_row_id`.

**Decision rules** (`SP_PROPOSE_RULE_CHANGES`, nightly; thresholds in `LEARNING` settings):

1. **Live plan** — in a calendar state, `PLAN_A` beats `PLAN_B` by ≥ `PLAN_SWITCH_MARGIN` (0.10) on net
   per allocated dollar over ≥ `MIN_GRADED_WINDOWS` (3) → propose `DE_PLAN_CONFIG.live_plan = 'A'` for
   that state (and the reverse once A is live).
2. **Last-day threshold** — among the plan's held-wrong and released-wrong keywords over ≥ 3 windows,
   if ≥ `STEP_BAND_SHARE` (0.60) of the wrong dollars sit between `strong_day_mult` and one step
   (`STRONG_DAY_STEP`, 0.2) below or above it → propose that step for that state.
3. **Index activation** — a catalog variant beats `NONE` on both accuracy and money over ≥ 3 graded
   weeks → propose `DE_INTENT_INDEX_REGISTRY.is_active = TRUE`; an active index losing to its
   leave-one-out variant the same way → propose `FALSE`.
4. **Response model** — `ACT` bias beyond `RESPONSE_BIAS_MAX` (0.10) in the same direction over 3
   windows → propose the `CLICK_BID_ELASTICITY` or `bid_to_cpc_ratio` value that would have removed it
   (solved on the graded rows).
5. **Seat size** — a family's `min_clicks` above the seat register's `click_goal_day × window_days`
   → propose the larger click goal, with its cost in dollars.

A proposal is not raised while one for the same `rule_key × scope` is `OPEN`, or was `REJECTED` within
`PROPOSAL_COOLDOWN_DAYS` (28). An `OPEN` proposal unanswered for 28 days becomes `EXPIRED` and may be
raised again with fresh evidence.

**The evidence block**, four parts, in words with the numbers:

1. **Facts** — windows graded, keywords and dollars, accuracy and money under the current rule vs. the
   proposed rule scored on the *same graded weeks*, the minimum-investment line, the lift control.
   Saved predictions and settled outcomes only.
2. **Last 12 months, replay** — month by month: calendar state, net under the current rule, net under
   the proposed rule, the difference. Until the ledger is a year old this replays the judge and the
   catalog over history through the backtest harness (plan Task 6) and is marked `BACKTEST`; once
   graded rows cover the month it is marked `GRADED`.
3. **Next 12 months, projection** — month by month, using the house calendar for the coming year's
   states and last year's months scaled to today's run-rate: expected net under each rule, the
   difference, the total; with the assumption in words and the predictor's trailing-3-window accuracy
   printed. `UNVERIFIED` while the predictor has no graded window.
4. **Risk and the way back** — the dollars in the band if the grade is wrong, and the revert rule.

**Accepting is one row.** Ori sets `status = 'ACCEPTED'` from the Admin page or one `bq` statement.
`SP_APPLY_ACCEPTED_PROPOSALS` (nightly, before the predictors read their settings) applies it through
the rule table's own recipe — retire-then-insert in `DE_PLAN_CONFIG` with `change_reason =
proposal_id`; `UPDATE … updated_by = 'proposal:<id>'` on `DE_INTENT_INDEX_REGISTRY` and
`DE_COACH_THRESHOLDS` — and stamps `applied_at` and the threshold-history row id. Nothing else writes
those settings on Ori's behalf (L-2; the calibration refit is the one declared exception, L-3).

**Revert rule.** For an `APPLIED` proposal, if the three graded windows after `applied_at` score worse
than the three before on the metric that justified it, the proposer raises a `REVERT` proposal carrying
the same block with the measured regression; accepting it restores the previous value and marks the
original `REVERTED`.

**On the brief**, one line per `OPEN` proposal:
`PROPOSAL 12 · OFF_PEAK last-day threshold 1.5× → 1.3× · 14 released-wrong vs 2 held-wrong over 4
windows · +$210/week graded, +$9,800 next 12 months (projection, predictor 78% accurate) · accept: mark
proposal 12.`

## 9. Alarms and surfaces

`V_ENGINE_HEALTH` checks (each carried onto `V_DAILY_BRIEF` by piece 0's system line):

| check | RED when |
|---|---|
| `prediction_grades_fresh` | any ledger row with `horizon_to` older than 14 days has no grade |
| `prediction_regression` | per predictor: trailing-3-window accuracy or money worse than the previous 3 by > `REGRESSION_MAX` (0.10); the line names any rule applied between |
| `proposals_open` | AMBER when an `OPEN` proposal is older than 14 days; the line lists them |
| `response_model_unverified` | INFO until the first `ACT` grade exists |

**Surfaces** (backend first, per the house rule; panels read `T_` tables): the Admin page gets a
*Proposals* panel (accept / reject with a note, the evidence block expanded) and a *Learning* panel:
per predictor the accuracy and money trend, the minimum-investment curve, and next week's
do-nothing vs act totals per family.

## 10. Order of work

| # | piece | gate to the next |
|---|---|---|
| 0 | alarm, observed changes, plan scorecard, rules with history (in flight) | all its acceptance suites green |
| 1 | audit the 09-28 → today plans; fix what it finds and the two known gaps: proven winners whose quiet window sold nothing lose the seat the night after grace under P-14c; a family whose only good keywords sit in a holdout campaign gets a pot of zero (Bottle) | rules amended and re-ruled by Ori |
| 2 | ledger view for the plan, response model v1, grader, `T_PREDICTION_SCORECARD`, health checks | first grades on 2026-10-12 (the 09-28 partition + 14 days) |
| 3 | plan Tasks 3 + 4: the plan owns bids in the preflight; the plan bulksheet | first uploaded plan, so `ACT` and lift can be graded |
| 4 | `FACT_INTENT_FORECAST` and its Sunday procedure | first catalog grades two Sundays later |
| 5 | plan Task 6, the backtest harness, serving the 12-month replay | replay rows marked `BACKTEST` |
| 6 | proposer, apply, `DE_RULE_PROPOSALS`, the Proposals panel | the loop closes |
| 7 | plan Tasks 7 + 8: surfaces and the SOP pass | — |

Each piece is its own implementation plan with its own acceptance suite.

## 11. Guarantees, asserted

A contract suite, `scripts/bigquery/tests/PREDICTION_CONTRACT_acceptance.sql`, that every current and
future predictor must pass, each check with a negative control:

1. every ledger row has both scenarios, the five numbers non-NULL, `basis_clicks ≥ 0`, a `rule_version`;
2. every ledger row with `horizon_to` ≥ 14 days old has exactly one grade;
3. the grader re-run inserts zero rows; a `regrade_from` run re-grades exactly the named band;
4. `RIGHT + WRONG + INCONCLUSIVE + UNGRADABLE` = graded rows, and no `INCONCLUSIVE` row sits above the
   family's `min_clicks`;
5. three fixtures — a fabricated prediction that must grade `RIGHT`, one `WRONG`, one `INCONCLUSIVE` —
   read as expected (the fixtures are written under `predictor = 'FIXTURE'` and excluded from every
   aggregate);
6. every `ACCEPTED` proposal has `applied_at` and a threshold-history row within one night; every
   `APPLIED` value equals the rule table's current value;
7. no `OPEN` proposal duplicates another on `rule_key × scope`;
8. the health checks exist and `prediction_grades_fresh` is GREEN on a healthy pass.

Plus, per piece, the house acceptance style: numbered checks returning a violation count, 0 = PASS,
a capitalised comment on what breaks in production, and negative controls recorded with results.

## 12. Limitations, stated

- **Not day-over-day.** The promise is "never quietly worse, better whenever the evidence allows";
  one week's grade is noise and is never read alone (three windows minimum, everywhere).
- **`ACT` is graded only where someone acted.** Until the plan bulksheet exists (piece 3) and is
  uploaded, every `ACT` row reads "no matching action" and lift is ungraded. The ledger says so.
- **Seasonal indexes learn slowly here.** Weekly grading sees each calendar month once a year; the
  monthly index scorecard remains the instrument for them.
- **The 12-month replay is a backtest for the first year** and is labelled as one; the projection
  assumes next year's months resemble last year's at today's run-rate and prints the predictor's grade
  beside itself.
- **The response model v1 is a first guess** (`CLICK_BID_ELASTICITY` seeded at 1.0). It is written
  down so it can be wrong in a measurable way.
- **Outcomes restate.** Grades are frozen at first grading; a `regrade_from` run is the only way they
  move, and it is logged.

## 13. Not in this spec

Changing any bid or budget automatically (L-2); the Coacher's and launch controller's own rules; the
Google Ads side; the intent verification queue (a human queue, not a pipeline).
