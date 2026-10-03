# The learning contract — every prediction saved, graded, and turned into a proposal

**Date:** 2026-10-01 · **Status:** design approved by Ori in conversation (sections 1–5), not yet implemented.
Piece-2 rulings D1–D6 recorded 2026-10-03 in §14; §5, §6, §7, §9 and §10 corrected in place where
a ruling or a measurement contradicted them, each correction marked *Corrected 2026-10-03*.
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
| `horizon_from`, `horizon_to` | the days it is about: plan from the first full Los Angeles day after the night was final, `GREATEST(as_of, DATE(built_at, 'America/Los_Angeles') + 1)`, for `window_days` days; catalog the coming Sunday–Saturday. *Corrected 2026-10-03 (§14 D2): was `as_of … as_of + window_days − 1`, a horizon that began before every stored night's last write (§14 E2).* |
| `family`, `campaign_id`, `keyword_id`, `channel`, `calendar_state` | the grain |
| `scenario` | `DO_NOTHING` or `ACT` |
| `move` | for `ACT`: the proposed bid, park/pause, budget; NULL for `DO_NOTHING` |
| `pred_spend`, `pred_clicks`, `pred_orders`, `pred_gp`, `pred_net` | the five numbers over the horizon |
| `pred_side` | plan only: 1 good / 0 not-good |
| `basis_clicks`, `basis_spend` | the evidence the prediction stood on (its window) |
| `rule_version` | the threshold-history snapshot id in force that night |
| `response_model_version` | which response model priced `ACT` |

**The plan** needs no new prediction table: a mapping view reads `FACT_PLAN_NEXT_WEEK`, whose night
is final once its first Los Angeles day has begun (§14 D2: the builder refuses to rewrite a night
after Los Angeles midnight of its `as_of`, and stamps `builder_version` on every row). `DO_NOTHING`
is the keyword's last-window run-rate per day × horizon days; the horizon is `window_days` long, so
that is the stored window itself: clicks `w_clk`, spend `w_sp`, orders `w_ord / settle_factor_eff`,
gross profit `w_gp_corrected`, net `w_gp_corrected − w_sp` — settle-corrected by the factor the
builder stored with the night, so the prediction is frozen with it and `V_PLAN_SETTLE_COMPLETION`
is not re-read. `ACT` is `DO_NOTHING` moved by the response model (§6) at `planned_bid` (or the park
price; pause is zero). The seat's own spend, `planned_spend_per_day × window_days`, is kept beside
it as `alloc_spend`, the plan's allocation, and is not a prediction. Both plans write both
scenarios for every keyword, so `PLAN_A` vs `PLAN_B` is a paired comparison on identical keys.
*Corrected 2026-10-03 (§14 D2, D3): was "no new writing", `DO_NOTHING` settle-corrected through
`V_PLAN_SETTLE_COMPLETION`, and "`ACT` is the seat" for spend — the seat puts $0 on PARK keywords
that went on spending (§14 E3), and §6 priced spend a second, different way.*

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
budget does to clicks and cost. Version 1 (`RM1`), deliberately simple and **anchored on
`DO_NOTHING`**, every constant a `LEARNING` setting:

```
r                = new_bid / current_bid      -- new_bid: planned_bid for REPRICE / OPEN_PROBE / PARK
                                              --   (PARK: ROUND(COALESCE(bid_park, bid_floor, current_bid), 2));
                                              -- current_bid for NONE / NONE_HOLDOUT / HOLD_AT_PRICE /
                                              --   HOLD_AT_PARK, so r = 1 where the plan moves no bid
ε                = CLICK_BID_ELASTICITY       -- seed 1.0; the grader's proposals move it (§8 rule 4)
γ                = CPC_BID_EXPONENT           -- seed 1.0 (CPC = bid × ratio implies 1.0);
                                              --   V_BID_CPC_TRANSFER declares 0.778 as the measured alternative
expected_clicks  = DO_NOTHING clicks           × r^ε
expected_spend   = DO_NOTHING spend            × r^(ε+γ)
expected_orders  = DO_NOTHING orders           × r^ε     -- w_ord / settle_factor_eff, as in §5
expected_gp      = DO_NOTHING gross profit     × r^ε
expected_net     = expected_gp − expected_spend
PAUSE            = all five zero
campaign budget  = RULED 2026-10-03: the recommended form below (§14.1, E8). As first written:
                   where the plan CUTS a campaign's budget, every ACT row of the campaign is scaled by
                   LEAST(1, Σ DO_NOTHING spend × planned / current ÷ Σ ACT spend) over its rows;
                   a raise has no effect in v1 (a stated limitation)
no window clicks = DO_NOTHING is zero, and so is ACT — except OPEN_PROBE, priced from the seat:
                   spend = seat_cost_per_day × horizon days, clicks = spend ÷ (planned_bid ×
                   BID_TO_CPC_RATIO_FALLBACK), orders and gross profit at the keyword's own settled
                   90-day rate (FACT_KEYWORD_STATE_HISTORY, latest snapshot at built_at) when it has
                   ≥ OWN_CVR_MIN_CLICKS settled clicks, else the family × channel pooled settled rate
```

Anchoring makes `ACT = DO_NOTHING` exactly on every row the plan does not move, so a predicted lift
can only come from a move. The seat's spend stays a separate column, `alloc_spend` (§5); it is the
allocation `FN_PLAN_SCORECARD` grades, not a forecast. The catalog's `cvr_hat` and `gp_per_order`
are not read (§14 D3, D6).

**Ruled 2026-10-03 — the budget clause (§14.1, E8): the recommended form.** The clause as
first written is the proportional cut D3 names, and it cuts `ACT` on campaigns whose new budget
cannot bind: `Σ DO_NOTHING spend × planned / current` can sit below `Σ ACT spend` while the `ACT`
run rate (`Σ ACT spend ÷ H`, H = the horizon's days) is already at or below the new budget, and the
clause then removes spend the budget would not. On the stored nights that is almost all of what it
removes (E8). Anchoring was ruled in to stop exactly this kind of movement on a lever that does not
act (E3). Recommended:

```
factor = LEAST(1, GREATEST(planned × H, Σ DO_NOTHING spend × planned / current) ÷ Σ ACT spend)
```

On a campaign the plan cuts, this caps `ACT` spend at the new budget × H. Where `DO_NOTHING` already
overdelivers its current budget (`Σ DO_NOTHING spend ÷ H > current`, the overdelivery E5 measured),
the cap falls back to the proportional cut. The algebra: when `Σ DO_NOTHING ÷ H ≤ current`,
`Σ DO_NOTHING × planned / current ≤ planned × H`, so GREATEST takes `planned × H` and the factor is
`LEAST(1, planned × H ÷ Σ ACT spend)`, the plain cap at the new budget. On the stored nights GREATEST
takes the cap term on 367 of the 369 cut campaign-nights, and the factor equals the plain cap's on all
369; on the two that overdeliver, all three forms give the same factor (E8). It is therefore a cap,
not the proportional cut D3's words name, which is why it was Ori's to rule. The argument
against a cap (E5: `DO_NOTHING` already runs above the current budget in some campaigns, and a cap
would cut those whether or not the plan moved them) applies only to a cap on campaigns the plan does
not cut. This clause never runs there, and on a cut campaign that overdelivers GREATEST keeps the
proportional cut. Piece-2 Task 4 built the recommended form (`V_PREDICTION_LEDGER` v27.172), reading
Ori's "all recommended" as covering this clause; `architecture/LEARNING.md` §3 records it.

*Corrected 2026-10-03 (§14 D3): was the literal form — `expected_cpc = new_bid × bid_to_cpc_ratio`
with an account fallback of 1.17, clicks capped so spend ≤ campaign budget × horizon, orders from
the catalog's `cvr_hat`. On rows the plan does not move it disagreed with `DO_NOTHING` by as much
as $290.72 of spend on one move class in one night (§14 E3); 1.17 has no source, and the measured
account ratio is 0.974 (§14 E4); the literal cap, applied to every campaign, would cut `ACT` below
`DO_NOTHING` on campaigns whose run rate already exceeds the current budget, including campaigns
whose budget the plan does not cut (§14 E5).*

The response model is itself graded (section 7) and tuned by proposals (section 8, rule 4). Its
first weeks will show how wrong it is; that is the point of writing it down.

## 7. The grader

`SP_GRADE_PREDICTIONS`, nightly from the orchestrator after `SP_FACT_AMAZON_ADS` and the observed-
change recorder. *Corrected 2026-10-03 (Task-1 review; §14 E1): "complete days old" below is
counted against the house watermark, never the calendar alone — a row is gradable when
`DATE_ADD(horizon_to, INTERVAL SETTLE_HORIZON_DAYS DAY) <= LEAST(MAX(date), FN_ADS_ANCHOR_CAP())` over
`FACT_AMAZON_ADS`, the expression of the judge's `wm` CTE (`V_PLAN_WINDOW_JUDGMENT.sql`).
`FN_ADS_ANCHOR_CAP()` alone is calendar only and never reads `FACT_AMAZON_ADS`; keyed on it, a stalled
table would grade missing days as zero clicks (step 4: no row means zero) and freeze those grades.*
For every ledger row whose `horizon_to` is at least `SETTLE_HORIZON_DAYS` (14) complete days old and
that has no grade yet, it:

1. reads the realised spend, clicks, orders, gross profit and net for the keyword over
   `horizon_from … horizon_to` from `FACT_AMAZON_ADS` as read today;
2. decides which scenario applied from the observed-change record: `ACT` if an observed change on the
   keyword/campaign within 3 days after `as_of` matched the proposed move within tolerance (bid
   ± $0.005, budget ± $0.01, state exact), else `DO_NOTHING`; a change that matched neither is
   `OTHER_ACTION` and the row is graded on neither scenario (reported);
3. buckets the keyword-week by realised clicks: `0, 1–5, 6–10, 11–20, 21–40, 41–80, 81+`.
   *Corrected 2026-10-03 (§14 D4): the `0` bucket is new — more than half the August plan rows
   realised no click (§14 E6); a row there is always `INCONCLUSIVE` and is counted as "predicted
   but dark" when its window had clicks;*
4. appends one `FACT_PREDICTION_GRADE` row per ledger row: the realised five numbers, the applied
   scenario, absolute and signed error on net, side correctness (plan), the bucket, and
   `grade ∈ {RIGHT, WRONG, INCONCLUSIVE, UNGRADABLE}` — counted, never dropped:
   - `UNGRADABLE`: the keyword or its campaign was ARCHIVED (any letter case) in the DIM SCD within
     the horizon. A keyword with no outcome rows realised zero — `FACT_AMAZON_ADS` holds clicked
     rows only — and is graded like any other.
   - **For the plan**, the realised side is GOOD when realised orders ≥ the state's `min_orders`
     (the `DE_PLAN_CONFIG` row in force at `built_at`) and realised gross profit ÷ spend ≥ the row's
     `family_bar` — the judge's own test; a row with no spend is not GOOD. `RIGHT`: the predicted
     side (`pred_side`) came true and the realised clicks are at or above the family's
     minimum-investment line. `WRONG`: it did not, at or above the line. `INCONCLUSIVE`: bucket `0`,
     below the line, or the family × state has no line. The line in force is stored on the row
     (`min_clicks_at_grade`).
   - The scenario that did not apply is written too, `is_applied = FALSE`, and is graded on
     accuracy only; money and applied-scenario accuracy read `is_applied` rows.

   *Corrected 2026-10-03 (§14, the brief's corrections): `UNGRADABLE` was "no outcome rows exist",
   which would have labelled every zero-click row (§14 E6); and the spec never said what `RIGHT`
   and `WRONG` mean for the plan, which contract check 4 needs.* Order inside one run: errors first,
   then the curve and the line from every graded row of the family (including tonight's), then the
   labels — so the line and the labels can never disagree (contract check 4).

**Idempotent:** a prediction is graded once (`NOT EXISTS` on the grade key). Settlement moves the
outcome slightly for days after; a re-grade happens only under an explicit `regrade_from` argument, so
grades do not drift night to night.

**Published aggregates** (a view over the grade table, materialised by the same procedure into
`T_PREDICTION_SCORECARD` for the surfaces), per `predictor × variant × family × calendar_state`:

- **Accuracy** — for the scenario that applied: spend-weighted mean absolute error of net in dollars
  and as a share of realised spend; bias (predicted − realised, signed); side accuracy for the plan
  (share of spend whose predicted side came true). Three levels: the window, the trailing
  3 windows, since start. A window is the Sunday-start week of `as_of` (the house week), pooling
  every graded night in it. *Corrected 2026-10-03 (§14 D5): was "the horizon week", undefined when
  3- and 7-day horizons overlap nightly.*
- **Money** — `ACT`: realised net per predicted dollar where acted on; `DO_NOTHING`: realised net per
  dollar; **lift**: predicted `ACT − DO_NOTHING` vs realised lift, against the holdout arm
  (`DE_HOLDOUT_ASSIGNMENT`, eligible since 09-01) where the family has one, else against the
  `DO_NOTHING` prediction with that prediction's own accuracy printed beside it; `lift_control` names
  which.
- **Minimum investment** — accuracy per click bucket, the smallest bucket clearing the bar
  (`MIN_INVEST_SIDE_ACCURACY` 0.80 for the plan's side; `MIN_INVEST_VPC_ERROR` 0.25 for the catalog's
  value per click), published as `min_clicks` and `min_dollars = min_clicks × family settled CPC`. The
  whole curve is published, not only the line. For the plan the curve is cumulative (side accuracy,
  spend-weighted, over the rows at or above each bucket's floor, so the line is monotone), bucket `0`
  never sets a line, and a floor sets the line only with at least `MIN_INVEST_MIN_ROWS` (20) rows
  behind it. *Corrected 2026-10-03 (§14 D4): the row minimum is new — without it one row at 81+
  clicks would have set a line (§14 E6).*
- **Honesty rows** — ungradable count, `ACT` rows with no matching action, `OTHER_ACTION` count,
  placement changed during the horizon, predicted-but-dark (bucket `0` with window clicks), and
  a `YOUNG` row saying in words when nothing is old enough to grade. *Corrected 2026-10-03 (§14 D4
  and the brief): predicted-but-dark and placement are new.*

**Relation to the existing scorecards.** The plan scorecard (piece 0, Task C) keeps its
`GRADE` / `RECOMMENDATION` / `GUARD` rows and computes them itself, on its own clock, until piece 6
re-points `GRADE` and `RECOMMENDATION` at `FACT_PREDICTION_GRADE`; until then a parity check holds
the two to the cent on the nights both grade. `GUARD` and `RULE_HINT` grade the window the judge
looked back on, which is not a prediction, so they stay in the function. *Corrected 2026-10-03
(§14 D5): was "reads them from `FACT_PREDICTION_GRADE` instead of recomputing".* The intent index
scorecard (`V_INTENT_INDEX_SCORECARD`) stays as the *monthly* instrument for seasonal indexes: a
Christmas index changes one month's prediction, and weekly grading sees each month once a year.

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
| `prediction_grades_fresh` | any ledger row with `horizon_to` older than 14 days has no grade. *Corrected 2026-10-03 (Task-1 review): "older" on the house watermark of §7 — a row gradable there one night ago (`horizon_to` + 15 ≤ the watermark) has no current grade. A stalled `FACT_AMAZON_ADS` makes no row due, so this check stays GREEN through it; it measures the grader, not the ads feed.* |
| `prediction_regression` | per predictor: trailing-3-window accuracy or money worse than the previous 3 by > `REGRESSION_MAX` (0.10); the line names any rule applied between |
| `proposals_open` | AMBER when an `OPEN` proposal is older than 14 days; the line lists them. *Corrected 2026-10-03 (§14): built in piece 6 with `DE_RULE_PROPOSALS`, which does not exist before then (§14 E7); piece 2 builds the other three.* |
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
| 2 | ledger view for the plan, response model v1, grader, `T_PREDICTION_SCORECARD`, health checks | the six August nights grade on the grader's first run (§14 D1); the first night after the outage to grade is 09-30, at the first grader run at or after 22:00 Los Angeles on 2026-10-17 (10-18 in New York and UTC). *Corrected 2026-10-03 (§14 D1, E1): was "first grades on 2026-10-12 (the 09-28 partition + 14 days)" — that is `FN_PLAN_SCORECARD`'s clock (night + 14), not §7's (horizon end + 14 settled days).* |
| 3 | the Brain → Pacing handoff (`THREE_LAYERS.md` §3): the plan emits intents — REPAIR with a ceiling, TEST with a seat and a click target, PARK, STOP, EARN — and the preflight holds Pacing inside them (never above a REPAIR ceiling, never a raise on a PARK); and the plan's upload file | first uploaded plan, so `ACT` and lift can be graded |
| 4 | `FACT_INTENT_FORECAST` and its Sunday procedure | first catalog grades two Sundays later |
| 5 | plan Task 6, the backtest harness, serving the 12-month replay | replay rows marked `BACKTEST` |
| 6 | proposer, apply, `DE_RULE_PROPOSALS`, the Proposals panel | the loop closes |
| 7 | plan Tasks 7 + 8: surfaces and the SOP pass | — |

Each piece is its own implementation plan with its own acceptance suite.

## 11. Guarantees, asserted

A contract suite, `scripts/bigquery/tests/PREDICTION_CONTRACT_acceptance.sql`, that every current and
future predictor must pass, each check with a negative control:

1. every ledger row has both scenarios, the five numbers non-NULL, `basis_clicks ≥ 0`, a `rule_version`;
2. every ledger row with `horizon_to` ≥ 14 days old has exactly one grade (*corrected 2026-10-03:
   days counted on §7's house watermark — every gradable row*);
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
- **The plan is the Brain, not the only engine.** P-11's "one engine" was superseded by
  `THREE_LAYERS.md` on 2026-08-24: the plan issues intents and Pacing finds today's bid inside them,
  so piece 3 builds that handoff rather than a preflight in which the plan is the sole price authority.

## 13. Not in this spec

Changing any bid or budget automatically (L-2); the Coacher's and launch controller's own rules; the
Google Ads side; the intent verification queue (a human queue, not a pipeline).

## 14. Piece-2 rulings (2026-10-03)

Ori answered the six open decisions of the piece-2 design brief on 2026-10-03 with "all
recommended". The plan that builds them is
`docs/superpowers/plans/2026-10-03-learning-piece2-ledger-grader.md`; the SOP is
`architecture/LEARNING.md`. The brief itself is a read-only survey of the same day, kept outside the
repository, so this section carries what the rulings and corrections rest on: §14.2 quotes its
numbers, each beside the query that produced it (§14.3), re-run before this section was written.

### 14.1 The rulings

| # | question | ruling |
|---|---|---|
| D1 | grade the six August plan nights? | **Yes.** They are graded on the first run, tagged as made under the pre-P-14c rules by `rule_version` and `builder_version`. The first post-outage grade is the 09-30 night, on 10-17 or 10-18 (§10, corrected; E1). |
| D2 | a forecast must be final before its horizon starts | **(c)** The ledger starts a prediction's horizon on the first full Los Angeles day after `built_at`, and the builder refuses to *rewrite* a night after Los Angeles midnight of its `as_of` (a first write stays allowed at any time). A `builder_version` column records the code that wrote each row. (§5, corrected; E2.) |
| D3 | how to forecast "if you upload the plan" | **(b) anchored:** ACT = DO_NOTHING scaled by the bid change (`r^ε` for clicks, orders and gross profit; `r^(ε+γ)` for spend), a campaign budget cut applied proportionally, PAUSE = 0, and a catalog-free own-rate fallback only for probes with no window clicks. ε = γ = 1.0 seeded; the bid-to-CPC fallback is the measured 0.974, not 1.17. The seat's spend is kept as its own column, `alloc_spend`. (§5, §6, corrected; E3, E4, E5.) |
| D4 | the minimum-investment bar | **Keep 0.80**, add a zero-click bucket (always INCONCLUSIVE, counted as "predicted but dark"), and require at least 20 rows before a bucket can set the line. (§7, corrected; E6.) |
| D5 | the piece-0 plan scorecard | **Leave `FN_PLAN_SCORECARD` as it is**, add a parity check against the new grade table, and re-point it in piece 6. A "window" for the report card is the Sunday-start week of `as_of`. (§7, corrected.) |
| D6 | snapshot the catalog's past bids | **Skip.** Only the literal response model (D3 a) or the catalog-orders variant (D3 c) read `T_INTENT_BID_BASE`, which is replaced nightly and recoverable only inside BigQuery's time-travel window; under D3 (b) the ledger reads no catalog table. |

Also recorded 2026-10-03: a seated keyword that later becomes a probe keeps the question it was
seated with (builder v27.168, confirmed by Ori); Ori made no change on Amazon after 2026-09-27.

**D3's budget clause (raised 2026-10-03 by the Task-1 review) — ruled: the recommended form.** D3
ruled "a campaign budget cut applied proportionally", and §6 first wrote it as `LEAST(1, Σ DO_NOTHING
spend × planned / current ÷ Σ ACT spend)`. That form also cuts campaigns whose `ACT` run rate is
already at or below the new budget, where the budget cannot bind (E8). Recommended: `LEAST(1,
GREATEST(planned × H, Σ DO_NOTHING spend × planned / current) ÷ Σ ACT spend)`. On a campaign the
plan cuts, it caps `ACT` spend at the new budget × H; where `DO_NOTHING` already overdelivers its
current budget, the cap falls back to the proportional cut (§6). On the stored nights it is the
plain cap at the new budget on 367 of the 369 cut campaign-nights, and gives the plain cap's factor
on all 369 (E8). It is a cap, not the proportional cut D3's words name, so the choice is Ori's: the
first form (proportional, as D3 reads) or the recommended one (a cap where the plan cuts). E5's
argument against a cap holds only for a cap on campaigns the plan does not cut, where neither form
runs. The clause scales every `ACT` number of a cut campaign, so it reaches the brief's "upload the
plan $Y" line and the report card's `pred_lift`. Piece-2 Task 4 built the recommended form under
Ori's "all recommended" (`architecture/LEARNING.md` §3, §10 "Task 4").

The brief's corrections that are not a ruling, made in place above: `UNGRADABLE` means an archived
keyword or campaign, not "no outcome rows" (§7); the plan's `RIGHT` and `WRONG` are defined (§7);
`proposals_open` moves to piece 6 with the table it reads (§9; E7).

### 14.2 The evidence

Measured 2026-10-03 between 16:00 and 16:12 UTC (09:00–09:12 Los Angeles), when
`FN_ADS_ANCHOR_CAP()` read 2026-10-02; every query in §14.3 was run from this file's own text. E8, Q7
and Q1's added columns come from the Task-1 follow-up of the same day, run after 16:34 UTC, when the
house watermark also read 2026-10-02 (Q1 `house_watermark_now`). These
numbers are the record of what the rulings were made on. They gate nothing and are not today's
reading (`config.yaml`, Standing Rule 0): run the query.
`FACT_AMAZON_ADS` restates, and every orchestrator pass rewrites tonight's plan partition until the
D2 freeze is built, so the 10-03 rows in E1–E7 are that partition as built at 13:04:57 UTC (E8's,
as rebuilt at 16:34:13 UTC) and may not reproduce; the other nights will, up to restatement.

**E1 — the stored nights and when they become gradable (D1, §10). Query Q1.** Twelve nights: six in
August, 2026-08-23 … 08-28 (PEAK, `window_days` 3, 4,472 plan rows, so 8,944 ledger rows), and
09-28 … 10-03 (09-28 and 09-29 OFF_PEAK, 7 days; 09-30 … 10-03 BOOST, 3 days). One calendar state
and one `window_days` per night. Under the shifted horizon (D2) every August night ends by
2026-08-31, so all six are gradable on the first run. After the outage the earliest horizon end is
the 09-30 night's: 10-02 under the old horizon, 10-03 under the shifted one (it was written at
22:44 Los Angeles on 09-30). A row is gradable once `horizon_to` + 14 ≤ the house watermark,
`LEAST(MAX(date), FN_ADS_ANCHOR_CAP())` over `FACT_AMAZON_ADS` (§7). 10-03 + 14 = 10-17.
`FN_ADS_ANCHOR_CAP()` is calendar only — the Los Angeles date from 22:00 Los Angeles, the day before
until then — so the cap reaches 10-17 at 22:00 Los Angeles on 10-17, and the watermark reaches it
when `FACT_AMAZON_ADS` also holds 10-17. On the eight nights the builder wrote at or after 22:00 Los
Angeles (08-23 … 08-28, 09-28, 09-30), the watermark it stored equals the Los Angeles date of the write
(Q1: `built_la_hour`, `watermark_stored`, `built_la_date`), so at that hour the table has held the
current day every time. The grade therefore lands at the first grader run at or after 22:00 Los
Angeles on 10-17 at which `FACT_AMAZON_ADS` holds 10-17, and later if the table stalls. The 10-12 that
§10 had is `FN_PLAN_SCORECARD`'s clock (`settle_days_max` 14 days from the night, its `nights` CTE):
09-28 + 14. *Corrected 2026-10-03 (Task-1 review): the first version of this paragraph and of
`architecture/LEARNING.md` §4 keyed gradability on `FN_ADS_ANCHOR_CAP()` alone and called it the ads
watermark; it never reads `FACT_AMAZON_ADS`, so a stalled table would have graded its missing days as
zero clicks. The `watermark_stored`, `n_wm`, `built_la_hour` and `house_watermark_now` columns of Q1
were added with this correction (run from this file's text 2026-10-03 16:40 UTC: 8 of the 8 nights
written at or after 22:00 Los Angeles have `watermark_stored` = `built_la_date`, one stored watermark
per night; negative control, a copy with the 08-23 night's stored watermark moved back one day: 7 of
8).*

**E2 — every night was written after its first horizon day began (D2, §5). Query Q1.** On all
twelve nights `rows_built_on_or_after_la_as_of` equals `plan_rows`: every row was written on or after
the Los Angeles date `as_of`, the day the old horizon began. Each night has one `built_at`; the
August nights were written between 05:30 and 06:05 UTC on the following day (22:30–23:05 Los Angeles
on the night itself).

**E3 — what the literal model and the seat do on rows the plan does not move (D3, §5, §6). Query
Q2.** Spend over the horizon, plan B, in dollars:

| night | move | rows | DO_NOTHING | seat | literal (§6 as written) | anchored, bid term only |
|---|---|---|---|---|---|---|
| 09-28 | NONE | 201 | 3,132.01 | 3,132.01 | 3,047.11 | 3,132.01 |
| 09-28 | NONE_HOLDOUT | 54 | 1,634.38 | 1,634.38 | 1,343.66 | 1,634.38 |
| 09-28 | HOLD_AT_PRICE | 2 | 0.74 | 0.74 | 0.69 | 0.74 |
| 09-28 | HOLD_AT_PARK | 8 | 28.25 | 0.00 | 31.21 | 28.25 |
| 09-28 | PARK | 45 | 380.11 | 0.00 | 36.35 | 42.34 |
| 09-28 | REPRICE | 48 | 1,703.70 | 1,573.07 | 1,438.53 | 1,470.95 |
| 10-03 | NONE | 211 | 1,801.71 | 1,801.71 | 1,672.73 | 1,801.71 |
| 10-03 | NONE_HOLDOUT | 54 | 375.54 | 375.54 | 391.27 | 375.54 |
| 10-03 | HOLD_AT_PRICE | 43 | 350.08 | 350.08 | 326.01 | 350.08 |
| 10-03 | OPEN_PROBE | 3 | 0.00 | 15.84 | 0.00 | 0.00 |

On the moves that change no bid the literal form and doing nothing disagree, in both directions:
−$84.90 (09-28 NONE), −$290.72 (09-28 NONE_HOLDOUT), −$0.05 (09-28 HOLD_AT_PRICE), +$2.96 (09-28
HOLD_AT_PARK), −$128.98 (10-03 NONE), +$15.73 (10-03 NONE_HOLDOUT), −$24.07 (10-03 HOLD_AT_PRICE).
Graded, each gap would read as a difference between the two scenarios on a keyword the plan never
moved. The anchored form equals DO_NOTHING on every such class. On 09-28 the seat puts $0 on PARK
and HOLD_AT_PARK, whose keywords spent $380.11 and $28.25 in their window. The literal column uses
Q3's family × channel ratios, written into Q2 as constants; the anchored column is `w_sp × r²`
(ε = γ = 1), without the budget cut or the probe's seat rule, which is why OPEN_PROBE reads 0 there.

**E4 — the bid-to-CPC fallback (D3, §6). Query Q3.** Cost ÷ (clicks × the live bid that day),
2026-09-02 … 09-29: **0.974** for the account (59,524 clicks, $32,648.94), SP 1.041, SB 0.903; no
keyword-day matched twice. By cell: SP Bottle 0.902, Bunny 1.028, Fresh 1.146, LolliBall 0.909,
LolliME 1.085, Lollibox 1.020; SB Bottle 1.167 (12 clicks), Bunny 1.085 (150 clicks), Fresh 0.903,
LolliBall 0.934, LolliME 0.943, Lollibox 0.811. The 1.17 §6 cited has no source:
`git grep -n -F '1.17'` over `*.sql *.md *.py *.yaml *.js *.ts *.tsx` finds it as a bid-to-CPC ratio
only in this spec and in the piece-2 plan that cites it (the other hits are an unrelated 1.17× in
`SEASON_CONTEXT_LEDGER.md` and `V_KEYWORD_CONTEXT_GATE.sql`). γ's alternative, 0.778 (0.638–0.872),
is a constant declared in `V_BID_CPC_TRANSFER`'s `params` CTE, not re-measured here.

**E5 — DO_NOTHING already overruns the current budget (D3, §6). Query Q4.** Plan B, per campaign,
the window's spend per day against `campaign_current_budget` (one value per campaign and night on all
three nights): on 08-28, 09-28 and 10-03 the run rate is above the budget in 14 of 59, 11 of 58 and
16 of 57 campaigns, by $189.49, $161.39 and $143.14 a day in total. A cap of `ACT` spend at the budget
on campaigns the plan does not cut would cut those campaigns whether or not the plan moved them; the
budget clause, in either form §6 sets out, runs only where the plan lowers a budget (29, 34 and 27
campaigns; it raises 15, 11 and 11). *Re-framed 2026-10-03 (second Task-1 review): this argument was
first read as ruling out any cap at the budget. It does not reach a cap on campaigns the plan cuts,
which is what §6's recommended form is; across the twelve stored nights 2 of the 369 cut
campaign-nights overdeliver their current budget, and there that form keeps the proportional cut
(E8).*

**E6 — no minimum-investment line at 0.80 on the August nights (D4, §7). Queries Q5 and Q5b.** The
old horizon (`as_of` …), the realised side tested as the judge does with `min_orders` 2 (every state's
`DE_PLAN_CONFIG` value on those nights). Per plan, 2,236 rows; **1,235 realised no click**, and 92 of
those had window clicks. Spend-weighted side accuracy by bucket, plan B: 1–5 0.549, 6–10 0.325,
11–20 0.407, 21–40 0.466, 41–80 0.357, 81+ 0.317; plan A's best bucket is 0.481 (21–40).
Cumulative by family (rows at or above a floor): on floors with at least 20 rows the best is 0.658
(Bottle, plan A, ≥ 6 clicks, 25 rows); Bottle ≥ 81 clicks is one row reading 1.000 in both plans —
the line D4's 20-row minimum refuses. These are the run started 16:10 UTC. The same query started
16:02 UTC, before that pass's `SP_FACT_AMAZON_ADS` (16:08 UTC) restated `GROSS_PROFIT` on the August
days, read 0.479 for plan B at 21–40 and 0.495 for plan A's best, as the brief had; clicks and spend
did not move. That is the drift the grader's freeze (§7, "Idempotent") exists to stop. The shifted
horizon (D2) moves these numbers too; piece-2 Task 5 records the grader's own August figures beside
them.

**E7 — the proposals table does not exist (§9). Query Q6.** `DE_RULE_PROPOSALS`,
`SP_PROPOSE_RULE_CHANGES` and the four piece-2 objects (`V_PREDICTION_LEDGER`,
`FACT_PREDICTION_GRADE`, `T_PREDICTION_SCORECARD`, `SP_GRADE_PREDICTIONS`) read `false`; the two
controls in the same query, `FACT_PLAN_NEXT_WEEK` and `SP_BUILD_NEXT_WEEK_PLAN`, read `true`.
`DE_COACH_THRESHOLDS` holds no `strategy_id = 'LEARNING'` row (Q6b); piece-2 Task 2 seeds them.

**E8 — the budget clause as first written cuts where the new budget cannot bind (D3, §6; ruled
2026-10-03, §14.1). Query Q7.** Added 2026-10-03 after the Task-1 review; run at 16:35 UTC and again from this
file's text at 16:40 UTC, identical, on the 10-03 partition as rebuilt at 16:34:13 UTC (the query
prints it). Plan B, all twelve stored nights, per
campaign and night, `ACT` spend before the budget clause priced as §6 prices it (window spend × r²
with ε = γ = 1, PAUSE 0, a zero-basis OPEN_PROBE at its seat cost × H). The plan cuts the budget on
369 campaign-nights. The first form binds (factor < 1) on 286 of them; on 283 of those 286 the `ACT`
run rate before the clause is already at or below the new budget, and those 283 carry $1,833.11 of
the $1,853.69 of horizon spend the clause removes. Example: campaign 435692261851957 on 10-03, budget
$160.00 → $113.68, `DO_NOTHING` $22.00 a day, `ACT` $20.22 a day before the clause and $15.63 after
it. The recommended form binds on 3 campaign-nights and removes $6.17, and the example keeps its
$20.22. Two cut campaign-nights have a `DO_NOTHING` run rate above the current budget; on both the two
forms give the same factor (`dn_over_current_alt_ne_rm1` = 0). Negative control, in the same query: a
copy of the rows with the example's 10-03 planned budget set to $10.00, below its `ACT` run rate,
moves it out of the 283 (282) and into the recommended form's cuts (4 binding, $36.82 removed; the
example reads $10.00 a day under the recommended form and $1.37 under the first). The first §6 and
E5 set the proportional form against a cap on every campaign, never measured its own cuts, and did
not compare it with a cap on the cut campaigns alone; this is the first measurement of both.

On a cut campaign whose `DO_NOTHING` run rate is at or below its current budget, the recommended
form is the plain cap at the new budget, `LEAST(1, planned × H ÷ Σ ACT spend)` (§6). Q7's cap
columns, run from this file's text at 16:54 UTC (998,673 bytes, the 10-03 partition still as built
at 16:34:13 UTC, every `REAL` and `NC` value above unchanged): GREATEST takes the cap term on 367 of
the 369 cut campaign-nights (`alt_takes_cap_term`), the recommended factor equals the plain cap's on
all 369 (`alt_eq_cap`), and the plain cap binds on the same 3 and removes the same $6.17. On the two
overdelivering cut campaign-nights all three forms give the same factor (`alt_eq_cap` 369 with
`dn_over_current_alt_ne_rm1` 0). Control `NC2`, the example's 10-03 current budget set to $21.00
and planned to $10.00 so its `DO_NOTHING` $22.00 a day overdelivers: overdelivering cut
campaign-nights 3, cap term 366, factor equal to the cap's 368, the recommended form removes $35.39
against the plain cap's $36.82, and the example reads $10.48 a day under the recommended form (equal
to the first form's $10.48) against $10.00 under the plain cap. That is the fallback to the
proportional cut, and the cap columns move with it.

### 14.3 The queries

Run with `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache`. Q3 and Q5 read
`FACT_AMAZON_ADS`: submit them with `--nosync` and poll with `bq wait JOB 60`. Q1 reads only its
newest `date`.

**Q1 — the stored nights (E1, E2).**

```sql
SELECT as_of, COUNT(*) AS plan_rows, COUNT(DISTINCT plan) AS plans,
       MAX(calendar_state) AS calendar_state, COUNT(DISTINCT calendar_state) AS n_states,
       MIN(window_days) AS window_days, COUNT(DISTINCT window_days) AS n_wd,
       MIN(built_at) AS built_min, MAX(built_at) AS built_max,
       DATE(MIN(built_at), 'America/Los_Angeles') AS built_la_date,
       EXTRACT(HOUR FROM DATETIME(MIN(built_at), 'America/Los_Angeles')) AS built_la_hour,
       MIN(watermark) AS watermark_stored, COUNT(DISTINCT watermark) AS n_wm,
       COUNTIF(DATE(built_at, 'America/Los_Angeles') >= as_of) AS rows_built_on_or_after_la_as_of,
       DATE_ADD(as_of, INTERVAL MIN(window_days) - 1 DAY) AS horizon_to_spec,
       DATE_ADD(GREATEST(as_of, DATE_ADD(DATE(MIN(built_at), 'America/Los_Angeles'), INTERVAL 1 DAY)),
                INTERVAL MIN(window_days) - 1 DAY) AS horizon_to_shifted,
       `onyga-482313.OI.FN_ADS_ANCHOR_CAP`() AS anchor_cap_now,
       (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`())
        FROM `onyga-482313.OI.FACT_AMAZON_ADS`) AS house_watermark_now
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
GROUP BY as_of ORDER BY as_of;
```

**Q2 — spend over the horizon by move, three forms (E3).** The brief's `act_forms.sql`.

```sql
WITH ratio AS (
  SELECT * FROM UNNEST([
    STRUCT('Bottle' AS family,'SP' AS channel,0.902 AS r), ('Fresh','SP',1.146), ('LolliME','SP',1.085), ('Lollibox','SP',1.020),
    ('Bottle','SB',1.167), ('Fresh','SB',0.903), ('LolliME','SB',0.943), ('Lollibox','SB',0.811)])
),
p AS (
  SELECT f.as_of, f.plan, f.move, f.family, f.channel, f.window_days, f.w_clk, f.w_sp, f.current_bid,
         COALESCE(f.planned_bid, f.current_bid) AS new_bid, f.planned_spend_per_day, r.r
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` f JOIN ratio r USING (family, channel)
  WHERE f.as_of IN ('2026-09-28','2026-10-03') AND f.plan = 'B'
)
SELECT as_of, move, COUNT(*) n, COUNTIF(w_clk>0) n_clk,
  ROUND(SUM(w_sp),2) dn_spend,
  ROUND(SUM(planned_spend_per_day * window_days),2) seat_spend,
  ROUND(SUM(IF(move='PAUSE',0, w_clk * POW(new_bid/current_bid,1.0) * new_bid * r)),2) v1_spec_spend,
  ROUND(SUM(IF(move='PAUSE',0, w_clk * POW(new_bid/current_bid,1.0) * new_bid * 0.974)),2) v1_spec_spend_acct,
  ROUND(SUM(IF(move='PAUSE',0, w_sp * POW(new_bid/current_bid,2.0))),2) v1_anchored_spend,
  ROUND(SUM(IF(move='PAUSE',0, w_sp * (new_bid/current_bid))),2) seat_style_linear
FROM p GROUP BY 1,2 ORDER BY 1,2;
```

**Q3 — the bid-to-CPC ratio (E4).**

```sql
WITH ks AS (
  SELECT snapshot_date, campaign_id, keyword_id, channel, family, current_bid,
         COUNT(*) OVER (PARTITION BY snapshot_date, campaign_id, keyword_id) AS n_dup
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
  WHERE snapshot_date BETWEEN '2026-09-02' AND '2026-09-29' AND current_bid > 0
),
f AS (
  SELECT date, campaign_id, keyword_id, SUM(Ads_clicks) AS clk, SUM(Ads_cost) AS cost
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN '2026-09-02' AND '2026-09-29'
  GROUP BY 1, 2, 3
)
SELECT COALESCE(ks.channel, 'ALL') AS channel, COALESCE(ks.family, 'ALL') AS family,
       COUNTIF(ks.n_dup > 1) AS dup_key_rows,
       SUM(f.clk) AS clicks, ROUND(SUM(f.cost), 2) AS cost,
       ROUND(SAFE_DIVIDE(SUM(f.cost), SUM(f.clk * ks.current_bid)), 3) AS cost_over_clicks_x_bid
FROM f JOIN ks ON ks.snapshot_date = f.date AND ks.campaign_id = f.campaign_id AND ks.keyword_id = f.keyword_id
GROUP BY ROLLUP(ks.channel, ks.family)
ORDER BY channel, family;
```

**Q4 — DO_NOTHING's run rate against the campaign budget (E5).**

```sql
WITH c AS (
  SELECT as_of, campaign_id,
         SUM(w_sp) / MAX(window_days) AS dn_spend_per_day,
         MAX(campaign_current_budget) AS cur_budget, MIN(campaign_current_budget) AS cur_budget_min,
         MAX(campaign_planned_budget) AS planned_budget
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE plan = 'B' AND as_of IN ('2026-08-28', '2026-09-28', '2026-10-03')
  GROUP BY 1, 2
)
SELECT as_of, COUNT(*) AS campaigns,
       COUNTIF(cur_budget <> cur_budget_min) AS budget_not_one_value,
       COUNTIF(dn_spend_per_day > cur_budget) AS dn_run_rate_over_current_budget,
       ROUND(SUM(IF(dn_spend_per_day > cur_budget, dn_spend_per_day - cur_budget, 0)), 2) AS over_by_per_day,
       COUNTIF(planned_budget < cur_budget) AS budget_cuts,
       COUNTIF(planned_budget > cur_budget) AS budget_raises
FROM c GROUP BY 1 ORDER BY 1;
```

**Q5 — the August side accuracy by click bucket (E6).** The brief's `aug_preview.sql`.

```sql
WITH p AS (
  SELECT as_of, plan, family, channel, campaign_id, keyword_id, window_days, side, move, family_bar,
         w_clk, w_ord, w_sp, w_gp, w_gp_corrected, settle_factor_eff
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of BETWEEN '2026-08-23' AND '2026-08-28'
),
r AS (
  SELECT p.as_of, p.plan, p.keyword_id,
    SUM(f.Ads_clicks) clk, SUM(f.Ads_cost) sp, SUM(f.Ads_orders) ord, SUM(f.GROSS_PROFIT) gp
  FROM p JOIN `onyga-482313.OI.FACT_AMAZON_ADS` f
    ON f.campaign_id = p.campaign_id AND f.keyword_id = p.keyword_id
   AND f.date BETWEEN p.as_of AND DATE_ADD(p.as_of, INTERVAL p.window_days - 1 DAY)
  GROUP BY 1,2,3
),
j AS (
  SELECT p.*, COALESCE(r.clk,0) clk, COALESCE(r.sp,0) sp, COALESCE(r.ord,0) ord, COALESCE(r.gp,0) gp
  FROM p LEFT JOIN r USING (as_of, plan, keyword_id)
),
k AS (
  SELECT *,
    CASE WHEN clk = 0 THEN '0' WHEN clk <= 5 THEN '1-5' WHEN clk <= 10 THEN '6-10' WHEN clk <= 20 THEN '11-20'
         WHEN clk <= 40 THEN '21-40' WHEN clk <= 80 THEN '41-80' ELSE '81+' END AS bkt,
    (side = 'GOOD') AS pred_good,
    (ord >= 2 AND SAFE_DIVIDE(gp, NULLIF(sp,0)) >= family_bar) AS real_good,
    (w_gp_corrected - w_sp) AS dn_net, (gp - sp) AS real_net
  FROM j
)
SELECT plan, bkt, COUNT(*) n,
  COUNTIF(w_clk > 0) pred_clk_pos,
  ROUND(SUM(sp),2) real_sp,
  ROUND(SAFE_DIVIDE(COUNTIF(pred_good = real_good), COUNT(*)),3) side_acc_n,
  ROUND(SAFE_DIVIDE(SUM(IF(pred_good = real_good, sp, 0)), SUM(sp)),3) side_acc_spend,
  ROUND(SAFE_DIVIDE(SUM(ABS(dn_net - real_net)), SUM(sp)),3) dn_mae_share,
  ROUND(SAFE_DIVIDE(SUM(dn_net - real_net), SUM(sp)),3) dn_bias_share
FROM k GROUP BY 1,2 ORDER BY 1, CASE bkt WHEN '0' THEN 0 WHEN '1-5' THEN 1 WHEN '6-10' THEN 2 WHEN '11-20' THEN 3 WHEN '21-40' THEN 4 WHEN '41-80' THEN 5 ELSE 6 END;
```

**Q5b — the cumulative curve by family (E6).** The brief's `aug_cum.sql`: Q5's four CTEs with this
final SELECT.

```sql
SELECT plan, family, bkt_floor, COUNT(*) n_ge, ROUND(SUM(sp),2) sp_ge,
  ROUND(SAFE_DIVIDE(SUM(IF(pred_good = real_good, sp, 0)), SUM(sp)),3) side_acc_spend_ge
FROM k, UNNEST([1,6,11,21,41,81]) bkt_floor WHERE clk >= bkt_floor GROUP BY 1,2,3 ORDER BY 1,2,3;
```

**Q6 — which learning objects exist (E7), with two controls that must read `true`; Q6b — the
LEARNING settings.**

```sql
SELECT n AS object_name,
       EXISTS (SELECT 1 FROM `onyga-482313.OI.INFORMATION_SCHEMA.TABLES` t WHERE t.table_name = n)
       OR EXISTS (SELECT 1 FROM `onyga-482313.OI.INFORMATION_SCHEMA.ROUTINES` r WHERE r.routine_name = n) AS exists_now
FROM UNNEST(['DE_RULE_PROPOSALS', 'SP_PROPOSE_RULE_CHANGES', 'V_PREDICTION_LEDGER', 'FACT_PREDICTION_GRADE',
             'T_PREDICTION_SCORECARD', 'SP_GRADE_PREDICTIONS',
             'FACT_PLAN_NEXT_WEEK', 'SP_BUILD_NEXT_WEEK_PLAN']) AS n;

SELECT COUNT(*) AS learning_rows
FROM `onyga-482313.OI.DE_COACH_THRESHOLDS` WHERE strategy_id = 'LEARNING';
```

**Q7 — the budget clause's cuts, first form against the recommended form and the plain cap at the
new budget (E8).** Added 2026-10-03; the cap columns (`f_cap`, `alt_takes_cap_term`, `alt_eq_cap`,
`cap_binds`, `cap_removed`, `ex_cap_per_day`) and the `NC2` copy added by the second Task-1 review.
The `NC` rows are the negative control: the same rows with one campaign's 10-03 planned budget set
to $10.00, below its `ACT` run rate. The `NC2` rows control the cap columns: the same campaign-night
with its current budget set to $21.00 and its planned budget to $10.00, so its `DO_NOTHING` run rate
($22.00 a day) is above its current budget.

```sql
WITH base AS (
  SELECT 'REAL' AS copy, as_of, campaign_id, move, window_days, w_clk, w_sp, current_bid, planned_bid,
         bid_park, bid_floor, seat_cost_per_day, campaign_current_budget, campaign_planned_budget
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE plan = 'B'
  UNION ALL  -- the negative control: the same rows, one campaign's 10-03 planned budget set to $10
  SELECT 'NC', as_of, campaign_id, move, window_days, w_clk, w_sp, current_bid, planned_bid,
         bid_park, bid_floor, seat_cost_per_day, campaign_current_budget,
         IF(as_of = '2026-10-03' AND campaign_id = '435692261851957', 10.0, campaign_planned_budget)
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE plan = 'B'
  UNION ALL  -- the cap columns' control: the same campaign-night overdelivering, current $21, planned $10
  SELECT 'NC2', as_of, campaign_id, move, window_days, w_clk, w_sp, current_bid, planned_bid,
         bid_park, bid_floor, seat_cost_per_day,
         IF(as_of = '2026-10-03' AND campaign_id = '435692261851957', 21.0, campaign_current_budget),
         IF(as_of = '2026-10-03' AND campaign_id = '435692261851957', 10.0, campaign_planned_budget)
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE plan = 'B'
),
k AS (
  SELECT *,
    CASE
      WHEN move = 'PAUSE' THEN 0
      WHEN w_clk = 0 AND move = 'OPEN_PROBE' THEN COALESCE(seat_cost_per_day, 0) * window_days
      ELSE w_sp * POW(SAFE_DIVIDE(CASE WHEN move IN ('REPRICE', 'OPEN_PROBE') THEN planned_bid
                                       WHEN move = 'PARK' THEN ROUND(COALESCE(bid_park, bid_floor, current_bid), 2)
                                       ELSE current_bid END, current_bid), 2)
    END AS act_sp
  FROM base
),
c AS (
  SELECT copy, as_of, campaign_id, MAX(window_days) AS h, MAX(campaign_current_budget) AS cur,
         MAX(campaign_planned_budget) AS planned, SUM(w_sp) AS dn, SUM(act_sp) AS act
  FROM k GROUP BY 1, 2, 3
),
f AS (
  SELECT *,
    LEAST(1, SAFE_DIVIDE(dn * planned / cur, act)) AS f_rm1,
    LEAST(1, SAFE_DIVIDE(GREATEST(planned * h, dn * planned / cur), act)) AS f_alt,
    LEAST(1, SAFE_DIVIDE(planned * h, act)) AS f_cap,
    (as_of = '2026-10-03' AND campaign_id = '435692261851957') AS ex
  FROM c WHERE planned < cur
)
SELECT copy, COUNT(DISTINCT as_of) AS nights, COUNT(*) AS cut_campaign_nights,
  COUNTIF(f_rm1 IS NULL) AS factor_null,
  COUNTIF(f_rm1 < 1) AS rm1_binds,
  COUNTIF(f_rm1 < 1 AND act / h <= planned) AS rm1_binds_act_le_new_budget,
  ROUND(SUM(IF(f_rm1 < 1, act * (1 - f_rm1), 0)), 2) AS rm1_removed,
  ROUND(SUM(IF(f_rm1 < 1 AND act / h <= planned, act * (1 - f_rm1), 0)), 2) AS rm1_removed_act_le_new_budget,
  COUNTIF(dn / h > cur) AS cut_dn_over_current_budget,
  COUNTIF(f_alt < 1) AS alt_binds,
  ROUND(SUM(IF(f_alt < 1, act * (1 - f_alt), 0)), 2) AS alt_removed,
  COUNTIF(dn / h > cur AND ABS(f_alt - f_rm1) > 1e-9) AS dn_over_current_alt_ne_rm1,
  COUNTIF(planned * h >= dn * planned / cur) AS alt_takes_cap_term,
  COUNTIF(ABS(f_alt - f_cap) <= 1e-9) AS alt_eq_cap,
  COUNTIF(f_cap < 1) AS cap_binds,
  ROUND(SUM(IF(f_cap < 1, act * (1 - f_cap), 0)), 2) AS cap_removed,
  ROUND(MAX(IF(ex, cur, NULL)), 2) AS ex_current_budget, ROUND(MAX(IF(ex, planned, NULL)), 2) AS ex_planned_budget,
  ROUND(MAX(IF(ex, dn / h, NULL)), 2) AS ex_dn_per_day, ROUND(MAX(IF(ex, act / h, NULL)), 2) AS ex_act_per_day,
  ROUND(MAX(IF(ex, act * f_rm1 / h, NULL)), 2) AS ex_rm1_per_day, ROUND(MAX(IF(ex, act * f_alt / h, NULL)), 2) AS ex_alt_per_day,
  ROUND(MAX(IF(ex, act * f_cap / h, NULL)), 2) AS ex_cap_per_day,
  ANY_VALUE(b.built_at_1003) AS built_at_1003
FROM f CROSS JOIN (SELECT MAX(built_at) AS built_at_1003 FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
                   WHERE as_of = '2026-10-03') b
GROUP BY 1 ORDER BY 1;
```

### 14.4 What else the brief found, and where it is answered

- **`rule_version`.** §5 asks for "the threshold-history snapshot id in force that night", and
  `FACT_THRESHOLD_HISTORY` has none: it keys each event by a per-row `history_id`. Piece-2 Task 4
  defines `rule_version` as the `history_id` of the `DE_PLAN_CONFIG` row for the night's
  `calendar_state` in force at `built_at`, joined with `builder_version` (`'pre-v27.170'` where the
  row carries none), because the judge and the builder changed between nights with no setting moving.
- **The night's calendar state is the stored one.** Since v27.160 the builder keys a night on its
  New York date; the ledger carries `calendar_state` as the builder wrote it and never re-derives it.
- **`ACT` and lift cannot be graded yet.** Until a plan is uploaded (piece 3) no `ACT` scenario can
  apply, so `response_model_unverified` stays INFO and the report card's `lift_control` reads
  `DO_NOTHING_PREDICTION`.
- **The observed-change feed is quiet after 2026-09-27.** That is consistent with no change having
  been made, which Ori recorded on 2026-10-03 (§14.1), but the data alone cannot tell it from a
  stalled feed; DO_NOTHING-applied labels on those nights rest on both.
