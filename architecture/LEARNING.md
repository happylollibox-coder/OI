# LEARNING — the plan's prediction ledger, its grader and its report card — SOP

**Spec:** `docs/superpowers/specs/2026-10-01-learning-contract-design.md` (§4–§8, §10–§12; piece-2
rulings D1–D6 and the evidence behind them in §14)
**Plan:** `docs/superpowers/plans/2026-10-03-learning-piece2-ledger-grader.md` (Tasks 1..8)
**Doctrine:** `architecture/THREE_LAYERS.md` §6 (every layer gets better on its own; the Brain keeps
the ledger)
**Status:** Task 1 (2026-10-03) wrote this SOP before any code. Nothing below is deployed yet: the
settings are Task 2, the freeze Task 3, the ledger Task 4, the grader and the report card Task 5, the
schedule and the health checks Task 6, the contract suite Task 7. Each task appends its own entry
to §10 "Deploy and verify" and corrects any sentence here that its build proves wrong.

> Every night, for every keyword the money plan judges, two forecasts are written down — *if you do
> nothing* and *if you upload the plan* — and once the days they forecast have settled, both are
> graded against what happened. A report card per family says how accurate the plan is, what it is
> worth, and how many clicks a keyword needs before its grade means anything.

This SOP states mechanisms and settings. Outside the dated records of §10 it quotes no measurement
(`config.yaml`, Standing Rule 0): where a number is needed, the query is printed (here or in the
spec's §14.3) and the reader runs it.

---

## 1. The ledger — one row per prediction per scenario

| object | file | what it is |
|---|---|---|
| `V_PREDICTION_LEDGER` | `scripts/bigquery/views/V_PREDICTION_LEDGER.sql` (Task 4) | the plan's stored rows mapped into the learning contract's prediction shape, two scenarios each |
| `FACT_PLAN_NEXT_WEEK` | `scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql` | the source: one row per (`as_of`, `plan`, `campaign_id`, `keyword_id`), written by `SP_BUILD_NEXT_WEEK_PLAN` |

**What a prediction is.** One row of `FACT_PLAN_NEXT_WEEK`: on night `as_of`, plan `A` or `B` judged
a keyword and wrote a side (GOOD / NOT_GOOD), a move and, for a seat, a price. Every stored night is
in the ledger, the six August nights included (ruling D1); they are tagged by `rule_version` and
`builder_version` as made under the rules of their time.

**What a ledger row is.** That prediction × `scenario` IN (`DO_NOTHING`, `ACT`). Key: (`as_of`,
`predictor`, `campaign_id`, `keyword_id`, `scenario`). Both plans write the same keywords every
night, so `PLAN_A` against `PLAN_B` is a paired comparison (the query that checks it is in
`NEXT_WEEK_MONEY.md` §6, "Grading").

| column | value |
|---|---|
| `predictor`, `variant` | `'PLAN_' ‖ plan`, `plan` |
| `as_of`, `built_at`, `builder_version` | as the builder stored them (`builder_version` from Task 3 on; NULL before) |
| `horizon_from` | `GREATEST(as_of, DATE(built_at, 'America/Los_Angeles') + 1)` — the first full Los Angeles day after the night was final (D2) |
| `horizon_to` | `horizon_from + window_days − 1` |
| `family`, `campaign_id`, `keyword_id`, `channel`, `calendar_state`, `is_live_plan`, `holdout`, `family_bar` | as stored |
| `min_orders` | the `DE_PLAN_CONFIG` row for the night's `calendar_state` in force at `built_at`, read from the config history |
| `current_bid`, `planned_bid`, `campaign_current_budget`, `campaign_planned_budget` | as stored |
| `move` | `ACT` rows only: the plan's move; NULL on `DO_NOTHING` |
| `alloc_spend` | `planned_spend_per_day × window_days` — the seat's spend, the plan's ALLOCATION (what `FN_PLAN_SCORECARD` grades). Not a forecast |
| `act_is_noop` | TRUE when the move has no bid component, no state component and no budget component (§4 step 4 defines the three) |
| `pred_side` | `IF(side = 'GOOD', 1, 0)`, the same on both scenarios |
| `basis_clicks`, `basis_spend` | `w_clk`, `w_sp`: the window the prediction stood on |
| `pred_clicks`, `pred_spend`, `pred_orders`, `pred_gp`, `pred_net` | the five predicted numbers over the horizon (§2, §3) |
| `rule_version` | the `history_id` of the `DE_PLAN_CONFIG` row for the row's `calendar_state` in force at `built_at`, `‖ ':' ‖ builder_version` (`'pre-v27.170'` where the row has none) |
| `response_model_version` | `'RUN_RATE'` on `DO_NOTHING`; `'RM1:'` + the history ids of the LEARNING settings in force on `ACT` |

**Why the horizon starts the day after the write (D2).** A forecast must exist before any day it
forecasts. Every night stored before piece 2 was written after Los Angeles midnight of its own
`as_of` (spec §14 E2), so a horizon starting on `as_of` began before its forecast was final. The
ledger therefore starts each horizon on the first full Los Angeles day after `built_at`, and the
builder (Task 3) refuses to rewrite a night once Los Angeles midnight of its `as_of` has passed. A
first write is always allowed: a late plan is still a plan, and its horizon simply starts later.

**Why a ledger row never changes after its night is final.** The view reads only stored columns of
a night that is no longer rewritten, the settings history (append-only, `FACT_THRESHOLD_HISTORY`)
and the keyword-state history (append-only, `FACT_KEYWORD_STATE_HISTORY`, the snapshot latest at
`built_at`). It reads no catalog table (D3, D6) and no `FACT_AMAZON_ADS`. The DO_NOTHING orders and
gross profit are settle-corrected by the factor the builder stored with the night
(`settle_factor_eff`, `w_gp_corrected`), not by re-reading `V_PLAN_SETTLE_COMPLETION`. The grader
still copies the five predicted numbers and `built_at` into each grade row, and the contract suite
(Task 7) fails if a graded ledger row ever reads differently from its copy.

**The side is read, never re-derived.** `pred_side` is the stored `side`, which the judge decided
with the P-14b guard and the P-14c last-day test (`guard_released_by`, `hold_kept_by` on the row).
Nothing in piece 2 recomputes a side or a guard.

---

## 2. The two scenarios, in words

**`DO_NOTHING` — leave tonight's bids and budgets as they are.** The keyword does over its horizon
what it did over the window the plan judged. The horizon is `window_days` long, the same length as
that window, so the forecast is the window itself:

| number | DO_NOTHING |
|---|---|
| clicks | `w_clk` |
| spend | `w_sp` |
| orders | `w_ord / settle_factor_eff` (keeps gross profit per order unchanged; there is no orders-completion curve) |
| gross profit | `w_gp_corrected` |
| net | `w_gp_corrected − w_sp` |

Spend and clicks get no settle correction: no day younger than two enters the window
(`V_PLAN_WINDOW_JUDGMENT`, "THE WINDOW": `window_to = LEAST(watermark − 1,
CURRENT_DATE('America/Los_Angeles') − 2)`), the fence the judge set because an age-1 day's spend is
short of final.

**`ACT` — upload the plan's move.** The same keyword at the price and budget the plan asks for:
clicks, orders and gross profit move with the bid change, spend moves further than clicks (more or
fewer clicks, each at a higher or lower price), a campaign whose budget the plan cuts is trimmed in
proportion, and a paused keyword does nothing. Where the plan moves nothing, `ACT` is `DO_NOTHING`
to the cent — the response model is anchored on it, so a predicted lift can only come from a move
(§3).

---

## 3. The response model, RM1, and every setting it reads

```
r = new_bid / current_bid
      new_bid = planned_bid                                          for REPRICE, OPEN_PROBE
              = ROUND(COALESCE(bid_park, bid_floor, current_bid), 2) for PARK
              = current_bid                                          for NONE, NONE_HOLDOUT,
                                                                         HOLD_AT_PRICE, HOLD_AT_PARK
pred_clicks = w_clk                        × r^ε
pred_spend  = w_sp                         × r^(ε+γ)
pred_orders = (w_ord / settle_factor_eff)  × r^ε
pred_gp     = w_gp_corrected               × r^ε
pred_net    = pred_gp − pred_spend
PAUSE       → all five 0
```

**The campaign budget.** A budget is set per campaign, so it acts on the sum of the campaign's
keywords. Where `campaign_planned_budget < campaign_current_budget`, every `ACT` row of the campaign
is multiplied by `LEAST(1, Σ DO_NOTHING spend × planned / current ÷ Σ ACT spend)` over the
campaign's rows of that night and plan (net follows as gross profit − spend). A raise has no effect
in v1. A cap at the budget itself is not used: `DO_NOTHING` already runs above the current budget
in some campaigns (spec §14 E5), and a cap would cut those whether or not the plan moved them.

**A keyword with no window clicks** (`w_clk = 0`) has `DO_NOTHING` all zero, and `ACT` all zero —
except `OPEN_PROBE`, which the plan seats to buy clicks it has never had. It is priced from the seat:

```
pred_spend  = seat_cost_per_day × window_days
pred_clicks = pred_spend / (planned_bid × BID_TO_CPC_RATIO_FALLBACK)
pred_orders = pred_clicks × CVR
pred_gp     = pred_orders × GP per order
  CVR, GP per order = the keyword's own settled 90-day record (settled_ord90 / settled_clk90,
                      settled_gp90 / settled_ord90) in FACT_KEYWORD_STATE_HISTORY, the latest
                      snapshot with captured_at <= built_at, when settled_clk90 >= OWN_CVR_MIN_CLICKS;
                      otherwise the family × channel pooled settled rate
```

(How the pooled rate is pooled — which snapshot, which keywords — is Task 4's to fix and record here.)

**The settings.** All in `DE_COACH_THRESHOLDS` under `strategy_id = 'LEARNING'`, `coach_mode =
'GUARDIAN'`, `product_family = NULL`, seeded by `scripts/bigquery/migrations/2026-10-03_learning_settings.sql`
(Task 2) and recorded by `FACT_THRESHOLD_HISTORY`. Never a literal in a view. The seeds are declared
constants (Ori's rulings of 2026-10-03); where one came from a measurement, the spec names the query.

| key | symbol | seed | read by | what it does |
|---|---|---|---|---|
| `CLICK_BID_ELASTICITY` | ε | 1.0 | ledger | how clicks, orders and gross profit follow the bid |
| `CPC_BID_EXPONENT` | γ | 1.0 | ledger | how the price per click follows the bid (1.0 = CPC proportional to bid; `V_BID_CPC_TRANSFER` declares 0.778 as the measured alternative) |
| `BID_TO_CPC_RATIO_FALLBACK` | — | 0.974 | ledger | CPC ÷ bid for a zero-basis probe (measured: spec §14 E4) |
| `OWN_CVR_MIN_CLICKS` | — | 30 | ledger | settled clicks a probe needs before its own rate is used |
| `SETTLE_HORIZON_DAYS` | — | 14 | grader, health | settled days after `horizon_to` before a row is graded |
| `MATCH_WINDOW_DAYS` | — | 3 | grader | days after `as_of` in which a change can count as the plan's |
| `MATCH_BID_TOL` | — | 0.005 | grader | a bid matches the plan within this |
| `MATCH_BUDGET_TOL` | — | 0.01 | grader | a budget matches the plan within this |
| `MIN_INVEST_SIDE_ACCURACY` | — | 0.80 | grader | the side accuracy a click bucket must clear to set the line (D4) |
| `MIN_INVEST_MIN_ROWS` | — | 20 | grader | rows a bucket needs behind it before it can set the line (D4) |
| `MIN_GRADED_WINDOWS` | — | 3 | health | windows per side of the regression comparison |
| `REGRESSION_MAX` | — | 0.10 | health | how much worse is RED |

Which value priced a row is on the row: `response_model_version` names the history ids in force.
**Open for Task 4:** all twelve nights stored on 2026-10-03 were built before the LEARNING settings
existed, so none has a setting "in force at `built_at`". The ledger must still price them, from a
value that can never change afterwards; Task 4 decides how and records it here.

**What the plan row supplies.** `w_clk`, `w_sp`, `w_ord`, `w_gp_corrected`, `settle_factor_eff`,
`window_days`, `move`, `current_bid`, `planned_bid`, `bid_park`, `bid_floor`, `seat_cost_per_day`,
`campaign_current_budget`, `campaign_planned_budget`, `built_at`.

---

## 4. How a grade is decided — `SP_GRADE_PREDICTIONS` → `FACT_PREDICTION_GRADE`

| object | file | what it is |
|---|---|---|
| `SP_GRADE_PREDICTIONS` | `scripts/bigquery/procedures/SP_GRADE_PREDICTIONS.sql` (Task 5) | the grader; nightly, orchestrator "Task 20.8f", between `SP_APPEND_CATALOG_FORECAST` and `SP_REFRESH_CUBE_TABLES` (Task 6) |
| `FACT_PREDICTION_GRADE` | `scripts/bigquery/tables/FACT_PREDICTION_GRADE.sql` (Task 5) | one row per graded ledger row; partitioned by `as_of`, clustered by `predictor, family`; **append-only** — never updated, never deleted from |

1. **Gradable.** A ledger row is gradable when `DATE_ADD(horizon_to, INTERVAL SETTLE_HORIZON_DAYS
   DAY) <= FN_ADS_ANCHOR_CAP()` and it has no current grade. The clock is the ads watermark, not the
   calendar, so grading pauses by itself if `FACT_AMAZON_ADS` stops advancing.
   (`FN_ADS_ANCHOR_CAP()` is the Los Angeles date from 22:00 Los Angeles, the day before until then.)
2. **What happened.** `FACT_AMAZON_ADS` on `campaign_id + keyword_id`, `date BETWEEN horizon_from AND
   horizon_to`, summing `Ads_clicks`, `Ads_cost`, `Ads_orders`, `GROSS_PROFIT`; net = gross profit −
   cost. The same join as `FN_PLAN_SCORECARD`. **No row means zero**: `FACT_AMAZON_ADS` holds clicked
   rows only, so a keyword that went dark realised zero and is graded like any other.
3. **`UNGRADABLE`** only when the keyword or its campaign is ARCHIVED (any letter case — the SCD
   holds both) in `DIM_KEYWORD` / `DIM_CAMPAIGN` at any point of the horizon (SCD2
   `effective_from` / `effective_to`). Counted, never dropped.
4. **Which scenario applied**, from `V_PPC_CHANGE_LOG_LANDED` (every `landed_evidence` except
   `LOGGED_ONLY`), changes applied on Los Angeles dates `as_of … as_of + MATCH_WINDOW_DAYS`:
   - the plan's **expected components**: a bid component when |`planned_bid` − `current_bid`| ≥
     `MATCH_BID_TOL`; a state component for PAUSE; a budget component when |planned − current
     budget| ≥ `MATCH_BUDGET_TOL`. `act_is_noop` = none of the three;
   - a component **matches** a change on the same keyword (bid within `MATCH_BID_TOL` of
     `planned_bid`; PAUSE ← `KEYWORD_PAUSE` / `STOP_TARGET`) or the same campaign (a `*BUDGET*`
     action within `MATCH_BUDGET_TOL` of `campaign_planned_budget`) — the recorder's own rules
     (`SP_RECORD_OBSERVED_CHANGES`);
   - **`ACT`** when every expected component matched and nothing else changed on the keyword or its
     campaign; **`DO_NOTHING`** when nothing changed on the keyword and no state or budget changed on
     its campaign; **`OTHER_ACTION`** otherwise, a partial match included;
   - `placement_changed` when `FACT_KEYWORD_STATE_HISTORY.m_effective` moved between `as_of` and
     `horizon_to` (placement changes are not in the change log).

   An SB change is observed at the Fivetran sync, up to a day late; the 3-day window covers it.
5. **The realised side.** GOOD when realised orders ≥ `min_orders` AND realised gross profit ÷ spend
   ≥ `family_bar` — the judge's own test (`V_PLAN_WINDOW_JUDGMENT`, `sided` CTE). A row with no spend
   has no return and is not GOOD, as in the judge (`COALESCE(ret, −1) >= family_bar`).
6. **The click bucket**, by realised clicks: `0, 1–5, 6–10, 11–20, 21–40, 41–80, 81+`.
7. **Inside one run, in this order** — so the line and the labels can never disagree:
   1. **errors**: `err_net = pred_net − real_net`, `abs_err_net`, side correctness;
   2. **the curve and the line**, per predictor × family × calendar_state, over every graded row
      including tonight's: for each bucket floor (1, 6, 11, 21, 41, 81), the side accuracy weighted
      by realised spend over the rows at or above that floor (cumulative, so the line is monotone).
      The line is the smallest floor whose cumulative accuracy ≥ `MIN_INVEST_SIDE_ACCURACY` with ≥
      `MIN_INVEST_MIN_ROWS` rows behind it; NULL when no floor qualifies. Bucket `0` never sets it.
      Both scenario rows of a plan row carry the same side and the same realised numbers, so the
      curve counts each plan row once — rows and dollars are plan rows, as in the spec's §14 E6
      queries;
   3. **the labels**: `UNGRADABLE` (step 3); else `INCONCLUSIVE` in bucket `0`, below the line, or
      when there is no line; else `RIGHT` when the predicted side came true, `WRONG` when it did not.
      The line in force is stored on the row as `min_clicks_at_grade`.
8. **Both scenarios are written.** One grade row per ledger row; `is_applied` marks the scenario
   that applied (neither, on `OTHER_ACTION`). The scenario that did not apply is graded on accuracy
   only: its errors are kept, and money and applied-scenario accuracy read `is_applied` rows. The
   label grades the side call, which both rows share, so it is the same on both.
9. **Frozen.** Each grade row carries copies of the five predicted numbers and `built_at`. A
   prediction is graded once (`NOT EXISTS` on the grade key); a second run inserts nothing.
   Outcomes keep restating for days, so a grade moves only under an explicit `regrade_from DATE`,
   which re-grades exactly that band, appending rows with `regrade_seq + 1` and a `regrade_reason`.
   The current grade of a prediction is its highest `regrade_seq`.

**The grade row** (columns): key `predictor, variant, as_of, campaign_id, keyword_id, scenario,
regrade_seq`; `horizon_from`, `horizon_to`, `built_at`, `rule_version`, `response_model_version`;
the five predicted numbers and `pred_side`; `applied_scenario`, `is_applied`, `act_is_noop`,
`matched_change_ids` and `other_change_ids` (arrays); the five realised numbers, `real_side`,
`side_correct`; `err_net`, `abs_err_net`, `click_bucket`, `min_clicks_at_grade`; `grade`,
`ungradable_reason`, `placement_changed`; `graded_at`, `watermark`, `grader_version`,
`regrade_reason`.

**Fixtures.** The contract suite (Task 7) writes three fabricated predictions under `predictor =
'FIXTURE'` that must read `RIGHT`, `WRONG` and `INCONCLUSIVE`; every aggregate excludes them.

**The piece-0 scorecard keeps its own clock (D5).** `FN_PLAN_SCORECARD` / `V_PLAN_SCORECARD` are
unchanged in piece 2: they grade one night per Sunday week once the night is 14 days old, over
`as_of … as_of + window_days − 1`. A parity check (Task 7) holds its GRADE allocation and realised
net equal, within a cent, to the grade table's computed the same way on the nights both grade.
Piece 6 re-points GRADE and RECOMMENDATION at the grade table; GUARD and RULE_HINT grade the window
the judge looked back on, which is not a prediction, and stay in the function.

---

## 5. The report card — `T_PREDICTION_SCORECARD`

Rebuilt (`CREATE OR REPLACE`) at the end of every grader run, from `FACT_PREDICTION_GRADE` (current
grades, fixtures excluded) and, for NEXT_WEEK, the ledger. File:
`scripts/bigquery/tables/T_PREDICTION_SCORECARD.sql` (Task 5).

**Grain:** `predictor × variant × family × calendar_state × level × row_type`.
**Levels:** `WINDOW` — the Sunday-start week of `as_of` (the house week, `WEEK(SUNDAY)`), pooling
every graded night in it (D5); `TRAILING_3` — the three most recent graded windows; `SINCE_START`.

| row_type | what it says |
|---|---|
| `ACCURACY` | for the scenario that applied: `mae_net_usd` = Σ\|err_net\|; `mae_net_share` = Σ\|err_net\| ÷ Σ realised spend; `bias_share` = Σ(pred_net − real_net) ÷ Σ realised spend; `side_accuracy`, spend-weighted |
| `MONEY` | `dn_net_per_dollar` over DO_NOTHING-applied rows; `act_net_per_pred_dollar` over ACT-applied rows; `counterfactual_net_per_alloc` = Σ alloc_spend × (real_net ÷ real_spend) ÷ Σ alloc_spend — `FN_PLAN_SCORECARD`'s GRADE metric, the only money metric that tells plan A from plan B until a plan is uploaded; `pred_lift` = Σ(ACT net − DO_NOTHING net); `realised_lift`; `lift_control` = `'DO_NOTHING_PREDICTION'` |
| `CURVE` / `LINE` | per bucket: rows, spend, cumulative side accuracy; the line as `min_clicks`, and `min_dollars` = `min_clicks` × (Σ real_spend ÷ Σ real_clicks) of the family's graded rows. The whole curve, not only the line |
| `HONESTY` | `UNGRADABLE`; `ACT_NO_MATCHING_ACTION` (a non-no-op ACT whose row applied as DO_NOTHING); `OTHER_ACTION`; `PLACEMENT_CHANGED`; `PREDICTED_BUT_ZERO_CLICKS` (bucket `0` with window clicks — "predicted but dark", D4) |
| `YOUNG` | a sentence saying, in words, when nothing is old enough to grade and when the next row becomes gradable |
| `NEXT_WEEK` | per family, tonight's live plan: Σ DO_NOTHING net and Σ ACT net, for the brief's line "do nothing $X; upload the plan $Y" |

---

## 6. The health checks

In `V_ENGINE_HEALTH` (Task 6), inserted before c33, which stays last
(`HOLDOUT_INTEGRITY_acceptance.sql` slices the file there); see `architecture/ENGINE_HEALTH.md`.

- **`prediction_grades_fresh`** — RED when a gradable ledger row has no current grade one night past
  due (the grader's own watermark clock plus one night's grace). Reads the ledger and
  `FACT_PREDICTION_GRADE`, never the report card. An empty population is RED, not vacuously green.
- **`prediction_regression`** — per predictor: the trailing `MIN_GRADED_WINDOWS` windows against the
  `MIN_GRADED_WINDOWS` before them on `mae_net_share` or `counterfactual_net_per_alloc`; RED when
  worse by more than `REGRESSION_MAX`. INFO "YOUNG" until twice `MIN_GRADED_WINDOWS` windows are
  graded. The detail names any `rule_version` or `builder_version` change between the two spans —
  the rule that moved.
- **`response_model_unverified`** — INFO until an `ACT`-applied grade with `act_is_noop = FALSE`
  exists; that needs an uploaded plan (piece 3).
- `proposals_open` is piece 6's, with `DE_RULE_PROPOSALS`.

`V_DAILY_BRIEF`'s SYSTEM line counts RED rows; the two RED-able checks go on its priority list, and
the copies of that list in `scripts/bigquery/tests/PLAN_HEALTH_acceptance.sql` are updated in the
same step.

---

## 7. Deploy order

Each step needs the one before it. Big files go up with their comment lines stripped:
`bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^[[:space:]]*--' FILE)"`.
Anything that may run past ~90 s is submitted `--nosync` and polled with `bq wait JOB 60`.

1. **Settings** (Task 2): `scripts/bigquery/migrations/2026-10-03_learning_settings.sql` (inserts only
   missing keys; never deletes or updates), then `CALL SP_SNAPSHOT_THRESHOLDS()` once so the history
   holds them.
2. **The freeze** (Task 3): `scripts/bigquery/migrations/2026-10-03_plan_builder_version.sql` (the
   column), then `SP_BUILD_NEXT_WEEK_PLAN.sql` (the guard and `builder_version`).
3. **The ledger** (Task 4): `scripts/bigquery/views/V_PREDICTION_LEDGER.sql`.
4. **The grader** (Task 5): `tables/FACT_PREDICTION_GRADE.sql`, `tables/T_PREDICTION_SCORECARD.sql`,
   then `procedures/SP_GRADE_PREDICTIONS.sql`, then its first CALL (the August nights grade).
5. **The schedule and the board** (Task 6): the orchestrator's new step — after diffing the deployed
   body against the file, where the new step must be the only difference; the orchestrator is never
   run by hand — then `V_ENGINE_HEALTH.sql`, `V_DAILY_BRIEF.sql`.
6. **The contract** (Task 7): `scripts/bigquery/tests/PREDICTION_CONTRACT_acceptance.sql`, the parity
   check, and the controls harness (`--submit` / `--collect`).

Every new object is registered in `config.yaml` by the task that creates it.

---

## 8. How to read the report card in one query

```sql
SELECT *
FROM `onyga-482313.OI.T_PREDICTION_SCORECARD`
ORDER BY family, calendar_state, predictor, variant, level, row_type;
```

Read `YOUNG` first: it says whether anything is old enough to have a grade. Then, per family,
`LINE` (is there a minimum investment, and how many clicks and dollars), `ACCURACY` at `TRAILING_3`
(how far off the forecasts run), `MONEY` (`counterfactual_net_per_alloc`, plan A against plan B) and
`NEXT_WEEK` (tonight's "do nothing / upload the plan"). Task 5 runs this query on the deployed table
and confirms the column names in §5.

---

## 9. Limits, stated

- **`ACT` is graded only where someone acted.** Until a plan is uploaded (piece 3) no `ACT` scenario
  applies; every non-no-op `ACT` row is an `ACT_NO_MATCHING_ACTION` honesty count, lift is ungraded,
  and `lift_control` is the DO_NOTHING prediction.
- **A budget raise has no effect in RM1**, and a budget cut is proportional across the campaign's
  keywords; the response model is a first guess, written down so it can be wrong in a measurable way.
- **"Do nothing" rests on the change record.** A keyword is DO_NOTHING-applied when no change was
  seen on it or its campaign. A stalled change feed would look the same as a quiet week.
- **Not day-over-day.** One window is noise; the regression check compares spans of
  `MIN_GRADED_WINDOWS` windows.
- **No minimum-investment line may exist for a long time.** At the 0.80 bar every plan row can read
  `INCONCLUSIVE`; the curve is published regardless (D4).

---

## 10. Deploy and verify

One entry per task, appended by the task, newest last.

### Task 1 — the rulings recorded and this SOP written (2026-10-03)

Docs only; nothing deployed, nothing registered in `config.yaml` (no BigQuery object is created).
The learning-contract spec gained §14 (rulings D1–D6, the evidence E1–E7 and the queries Q1–Q6 behind
every number it quotes) and was corrected in place in §5, §6, §7, §9 and §10, each correction marked
*Corrected 2026-10-03*. Every query in spec §14.3 was run from the spec's own text before commit
(2026-10-03, 16:09–16:12 UTC) and its output read against the sentence that quotes it. Controls:
Q6 lists two objects that exist beside the six that do not, and they read `true`; Q1's E2 column,
run on a copy of the plan rows with one row's `built_at` moved to 23:00 Los Angeles the day before
its `as_of`, counted 729 of 730 rows on 2026-08-23 — one violation, the doctored row. During the
run the 16:00 UTC pass's `SP_FACT_AMAZON_ADS` (16:08 UTC) restated August `GROSS_PROFIT`, and Q5
moved between two runs eight minutes apart; spec §14.2 E6 quotes the later run and states the
earlier. Re-run them the same way:

```bash
cd /Users/ori/Develop/OI && mkdir -p .tmp
python3 - <<'EOF'
import re
s = open('docs/superpowers/specs/2026-10-01-learning-contract-design.md', encoding='utf-8').read()
sec = s[s.index('### 14.3 The queries'):s.index('### 14.4')]
for i, b in enumerate(re.findall(r'`{3}sql\n(.*?)`{3}', sec, re.S), 1):
    open(f'.tmp/learning_q{i}.sql', 'w').write(b)
EOF
# .tmp/learning_q1..q7.sql: Q1, Q2, Q3, Q4, Q5, Q5b (the final SELECT; prefix it with Q5's CTEs), Q6 + Q6b
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(cat .tmp/learning_q1.sql)"
```
