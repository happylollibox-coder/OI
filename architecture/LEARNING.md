# LEARNING — the plan's prediction ledger, its grader and its report card — SOP

**Spec:** `docs/superpowers/specs/2026-10-01-learning-contract-design.md` (§4–§8, §10–§12; piece-2
rulings D1–D6 and the evidence behind them in §14)
**Plan:** `docs/superpowers/plans/2026-10-03-learning-piece2-ledger-grader.md` (Tasks 1..8)
**Doctrine:** `architecture/THREE_LAYERS.md` §6 (every layer gets better on its own; the Brain keeps
the ledger)
**Status:** Task 1 (2026-10-03) wrote this SOP before any code. Task 2 (2026-10-03) seeded the
LEARNING settings (§3; §10 "Task 2"). Task 3 (2026-10-03) deployed the freeze and `builder_version`
(§1 "The freeze"; §10 "Task 3"). Nothing else below is deployed yet: the ledger is Task 4, the
grader and the report card Task 5, the schedule and the health checks Task 6, the contract suite
Task 7. Each task appends its own entry to §10 "Deploy and verify" and corrects any
sentence here that its build proves wrong.

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

**The freeze — a night is final once it has begun (D2 (c); `SP_BUILD_NEXT_WEEK_PLAN` v27.170,
deployed by Task 3).**

- **The rule.** Before it touches tonight's partition (`as_of_d`, the New York date), the builder
  reads whether a partition for that night exists and what the Los Angeles date is. A written night
  whose Los Angeles midnight has passed (`CURRENT_DATE('America/Los_Angeles') >= as_of_d`) is not
  rewritten: the builder selects `FROZEN: partition <as_of> was written at <built_at>; its first day
  has begun; not rewritten (…)` as `log_message` and returns normally, so `LOG_PIPELINE_RUNS`
  records OK and `plan_pass_failed` stays GREEN, and `SP_APPEND_SEAT_REQUEST`, the next step,
  re-reads the same partition. A night with no partition is written whenever the builder runs — a
  late first write — and the ledger starts its horizon later instead (above).
- **Read twice.** At entry, so a frozen pass reads one partition and never the judgement view; and
  again just before the `DELETE`, so a build that started before Los Angeles midnight and reaches the
  write after it does not rewrite (`built_at` is stamped before that second reading, so a rewrite it
  lets through was stamped before midnight). Both readings come before R11's calendar-state guard: a
  frozen night returns OK whatever state it was written under.
- **`builder_version`** is written on every row: the `vNN.NNN` of the builder's header and
  description (`builder_version_d` in the body; the three are bumped together). NULL on rows written
  before v27.170 (migration `scripts/bigquery/migrations/2026-10-03_plan_builder_version.sql`).
- **Which pass writes a night.** The orchestrator's three scheduled queries start at 05:00, 07:35
  and 16:00 UTC (BigQuery scheduled-query times, UTC all year). A night is keyed on the New York
  date, so a pass can rewrite it only between New York midnight and Los Angeles midnight of that
  date — 04:00–07:00 UTC under daylight time, 05:00–08:00 UTC under standard time — and writes it
  for the first time whenever, on that date, it finds no partition. The 05:00 UTC pass's plan step
  runs inside that span (the Los Angeles evening before `as_of`), so it is each night's first write;
  the 07:35 and 16:00 UTC passes' plan step runs after Los Angeles midnight, finds the night written
  and is a no-op. Two edges: under standard time the 07:35 UTC pass would
  still rewrite if its plan step reached the builder before 08:00 UTC, which the rule allows (before
  midnight); and if the 05:00 UTC pass's build fails, the 07:35 UTC pass writes the night as its first
  write, after Los Angeles midnight, and that night's horizon starts a day later.
- **What it costs in freshness.** The judge fences the window at two days before the Los Angeles
  date of the build (`window_to = LEAST(watermark − 1, today_la − 2)`). The 05:00 UTC pass builds
  on the Los Angeles day before `as_of`, so the window it judges ends three days before `as_of`; the
  later passes, a Los Angeles day on, would have judged a window ending two days before. A night now
  stands on the older window — one day less evidence — and the later passes' restatement of the
  window's days is not taken in. The measured windows of one night are in §10 "Task 3".
- **Checked by** `FACT_PLAN_NEXT_WEEK_acceptance.sql` F1 (no night written since the deploy was
  rewritten after Los Angeles midnight of its `as_of`; whether a write was the night's first is read
  from its own `DELETE` in `INFORMATION_SCHEMA.JOBS_BY_PROJECT` — a first write removes nothing) and
  F2 (every row written since the deploy carries a `builder_version`, the deployed builder's on rows
  written since its deploy), each with an emptiness term; controls in
  `scripts/bigquery/tests/check_plan_clock_controls.py`.

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
fewer clicks, each at a higher or lower price), a campaign whose budget the plan cuts is trimmed
(how, exactly, is open for Ori: §3), and a paused keyword does nothing. Where the plan moves
nothing, `ACT` is `DO_NOTHING` to the cent — the response model is anchored on it, so a predicted
lift can only come from a move (§3).

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

**The campaign budget — open for Ori, to rule before Task 4** (spec §6, §14.1, §14 E8). A budget
is set per campaign, so it acts on the sum of the campaign's keywords: where
`campaign_planned_budget < campaign_current_budget`, every `ACT` row of the campaign is multiplied by
one factor over the campaign's rows of that night and plan (net follows as gross profit − spend). A
raise has no effect in v1. H is the horizon's days (`window_days`). Two forms of the factor:

```
as first written  LEAST(1, Σ DO_NOTHING spend × planned / current ÷ Σ ACT spend)
recommended       LEAST(1, GREATEST(planned × H, Σ DO_NOTHING spend × planned / current) ÷ Σ ACT spend)
```

The first form is the proportional cut D3 names. It also cuts a campaign whose `ACT` run rate
(Σ ACT spend ÷ H) is already at or below the new budget, where the budget cannot bind — a predicted
difference between the scenarios on a lever that does not act, the movement anchoring exists to
prevent; spec §14 E8 measures how much of what it removes falls there (query Q7).

The recommended form is a cap. On a campaign the plan cuts, `ACT` spend is capped at the new
budget × H. Where `DO_NOTHING` already overdelivers its current budget (Σ DO_NOTHING spend ÷ H >
current), the cap falls back to the proportional cut. The algebra: when Σ DO_NOTHING ÷ H ≤ current,
Σ DO_NOTHING × planned / current ≤ planned × H, so GREATEST takes planned × H and the factor is
`LEAST(1, planned × H ÷ Σ ACT spend)`, the plain cap at the new budget. On the stored nights GREATEST
takes the cap term on 367 of the 369 cut campaign-nights and the factor equals the plain cap's on all
369 (spec §14 E8, Q7's `alt_takes_cap_term` and `alt_eq_cap`). It is not the proportional cut D3's
words name, which is why Ori rules it.

The argument against a cap (spec §14 E5: `DO_NOTHING` already runs above the current budget in some
campaigns, and a cap would cut those whether or not the plan moved them) applies only to a cap on
campaigns the plan does not cut. Neither form runs there, and on a cut campaign that overdelivers
the recommended form keeps the proportional cut. Task 4 builds the form Ori rules and records it here.

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
(Task 2) and recorded by `FACT_THRESHOLD_HISTORY`; `scripts/bigquery/tests/LEARNING_SETTINGS_acceptance.sql`
checks the scope, the history and the seed values. Never a literal in a view. The seeds are declared
constants (Ori's rulings of 2026-10-03); where one came from a measurement, the spec's §14 or §10
"Task 2" below names the query, and each row's `description` names its source.

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
   DAY) <= watermark` and it has no current grade, where `watermark = LEAST(MAX(date),
   FN_ADS_ANCHOR_CAP())` over `FACT_AMAZON_ADS` — the house watermark, the judge's own expression
   (`V_PLAN_WINDOW_JUDGMENT.sql`: the header's "THE WINDOW" and the `wm` CTE). The grader stores the
   value it used on each grade row (`watermark`). `FN_ADS_ANCHOR_CAP()` alone is calendar only — the
   Los Angeles date from 22:00 Los Angeles, the day before until then — and never reads
   `FACT_AMAZON_ADS`; the `MAX(date)` term is what keeps a row ungraded while the table's newest day
   is short of `horizon_to + SETTLE_HORIZON_DAYS`, so step 2's "no row means zero" is never read on a
   day the table has not reached. The watermark is one date for the whole table: a day missing below
   it, or one channel's feed stopping while the other's advances, is not caught by this test (§9).
   *Corrected 2026-10-03 (Task-1 review): the first version used `FN_ADS_ANCHOR_CAP()` alone and
   called it the ads watermark; a stalled `FACT_AMAZON_ADS` would have graded its missing days as zero
   clicks, frozen until a `regrade_from`.*
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

- **`prediction_grades_fresh`** — RED when a ledger row has no current grade although
  `DATE_ADD(horizon_to, INTERVAL SETTLE_HORIZON_DAYS + 1 DAY) <= watermark`, the house watermark of
  §4 step 1 (one night's grace). Reads the ledger, `FACT_AMAZON_ADS`'s newest `date` and
  `FACT_PREDICTION_GRADE`, never the report card. An empty population is RED, not vacuously green.
  It measures the grader against the data that exists: while `FACT_AMAZON_ADS` stops advancing no
  row falls due, and the check stays GREEN. Its detail line prints the watermark beside
  `FN_ADS_ANCHOR_CAP()` so a lag is visible; `V_ENGINE_HEALTH` has no check on the ads table's
  newest date (read 2026-10-03), and `pipeline_step_failing` names a step that fails, not one that
  loads nothing new. *Corrected 2026-10-03 (Task-1 review): was the calendar clock of §4 step 1's
  first version.*
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
   missing keys; never deletes or updates; its last statement is `CALL SP_SNAPSHOT_THRESHOLDS()`, so
   the history holds them), then `scripts/bigquery/tests/LEARNING_SETTINGS_acceptance.sql`.
2. **The freeze** (Task 3): `scripts/bigquery/migrations/2026-10-03_plan_builder_version.sql` (the
   column), then `SP_BUILD_NEXT_WEEK_PLAN.sql` (the guard and `builder_version`), then
   `FACT_PLAN_NEXT_WEEK_acceptance.sql` (F1 and F2 read their emptiness terms until the first night
   written after the deploy) and `check_plan_clock_controls.py` on a simulated pass.
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
- **A budget raise has no effect in RM1**, and how a budget cut acts is open for Ori (§3); the
  response model is a first guess, written down so it can be wrong in a measurable way.
- **The grading clock is one date for the whole ads table** (§4 step 1). It waits for
  `FACT_AMAZON_ADS`'s newest day, not for every day or every channel: a day missing below the newest,
  or one channel stalled while the other loads, grades as zero clicks.
- **"Do nothing" rests on the change record.** A keyword is DO_NOTHING-applied when no change was
  seen on it or its campaign. A stalled change feed would look the same as a quiet week.
- **A night stands on its first pass's window** (§1, "The freeze"): one day older than a later pass
  of the same night would have judged, and blind to that pass's restatement of the window's days.
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
# .tmp/learning_q1..q8.sql: Q1, Q2, Q3, Q4, Q5, Q5b (the final SELECT; prefix it with Q5's CTEs), Q6 + Q6b, Q7
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(cat .tmp/learning_q1.sql)"
```

### Task 1 follow-up — the review's two corrections (2026-10-03)

Docs only; nothing deployed, `config.yaml` untouched. The Task-1 review found two errors, corrected
in the spec, this SOP and the plan:

1. **The grading clock.** §4 step 1 keyed gradability on `FN_ADS_ANCHOR_CAP()` alone and said that
   was the ads watermark. It is calendar only (`scripts/bigquery/functions/FN_ADS_ANCHOR_CAP.sql`),
   so a stalled `FACT_AMAZON_ADS` would have graded missing days as zero clicks and frozen them. Now
   the house watermark `LEAST(MAX(date), FN_ADS_ANCHOR_CAP())` everywhere: §4 step 1, §6
   `prediction_grades_fresh`, spec §7, §9, §11 check 2, §14.2 E1, and plan Task 5 Step 2. Q1 gained
   `built_la_hour`, `watermark_stored`, `n_wm` and `house_watermark_now`; re-run from the spec's text
   (2026-10-03 16:40 UTC) it shows, on each of the eight nights written at or after 22:00 Los
   Angeles, one stored watermark equal to the Los Angeles date of the write — the evidence that E1's
   10-17 holds when the table keeps loading the current day. Negative control (a copy of the plan
   rows with the 08-23 night's stored watermark moved back one day): 7 of 8.
2. **The budget clause.** RM1's `LEAST(1, Σ DO_NOTHING × planned / current ÷ Σ ACT)` cuts campaigns
   whose new budget cannot bind. Measured by the new Q7 (spec §14 E8) and marked open for Ori in
   spec §6, §14.1, this SOP's §3 and plan Task 4 Step 3, with the recommended
   `GREATEST(planned × H, …)` form beside it. Task 4 starts only after Ori rules. Q7 carries its
   negative control in the query (an `NC` copy of the rows with one campaign's 10-03 planned budget
   set to $10.00, below its `ACT` run rate): it moved that campaign out of the "binds although the
   budget cannot" count and into the recommended form's cuts, as E8 records.

Spec §14.3 was extracted with the snippet above after the edits: eight blocks (`learning_q8.sql` is
Q7); Q2 … Q6b are byte-identical to the review's extraction. Run from that text at 16:40 UTC: Q1 as
above; Q7 reproduced E8 to the cent on both copies; Q6 still lists the six piece-2 and piece-6
objects as absent beside its two `true` controls, and Q6b 0 LEARNING rows.

### Task 1 follow-up 2 — the recommended budget clause named for what it is (2026-10-03)

Docs only; nothing deployed, `config.yaml` untouched. The second Task-1 review found that §3, spec
§6, spec §14.1 and plan Task 4 Step 3 described the recommended budget clause as the proportional
cut and said a plain cap at the budget was "used by neither". On a campaign the plan cuts and whose
`DO_NOTHING` run rate is at or below its current budget, GREATEST takes planned × H and the
recommended factor is exactly the plain cap at the new budget. §3, spec §6 and §14.1 and plan Task 4
Step 3 now say so; spec §6's correction note and E5 now limit the argument against a cap to
campaigns the plan does not cut, where neither form runs; E8 records the measurement. The clause
stays open for Ori.

Q7 gained `f_cap`, `alt_takes_cap_term`, `alt_eq_cap`, `cap_binds`, `cap_removed`, `ex_cap_per_day`
and a third copy, `NC2` (the example's 10-03 current budget $21.00 and planned $10.00, so its
`DO_NOTHING` $22.00 a day overdelivers). Spec §14.3 extracted with the snippet above: eight blocks;
Q1 … Q6b byte-identical to the previous extraction, Q7 differs by those additions only. Run from that
text at 16:54 UTC (998,673 bytes; the 10-03 partition as built at 16:34:13 UTC): every `REAL` and `NC`
value E8 already quoted is unchanged; `REAL` cap term 367 of 369, factor equal to the cap's 369, cap
binds 3 and removes $6.17, the same as the recommended form; `NC` 367, 369, 4, $36.82; `NC2` 366, 368,
the recommended form $35.39 against the cap's $36.82, the example $10.48 a day against $10.00.

### Task 2 — the LEARNING settings seeded (2026-10-03)

**Deployed.** `scripts/bigquery/migrations/2026-10-03_learning_settings.sql`, run 2026-10-03 at
17:05 UTC with its comment lines stripped (`--nosync`, polled). Its INSERT wrote 12 rows to
`DE_COACH_THRESHOLDS` — `strategy_id = 'LEARNING'`, `coach_mode = 'GUARDIAN'`, `product_family`
NULL, `source = 'SEED'`, `updated_by = 'learning-piece2'`, `updated_at` 2026-10-03 17:05:12 UTC,
the values of §3's table — and its closing `CALL SP_SNAPSHOT_THRESHOLDS()` appended 12 `ADDED`
events to `FACT_THRESHOLD_HISTORY` at `snapshot_at` 2026-10-03 17:05:15 UTC and nothing else: no
other rule row differed from its last event (the history held only the 2026-10-02 10:55:45 UTC seed). Run a second time at 17:05:48 UTC:
both statements 0 rows. The settings exist from 17:05:15 UTC on 2026-10-03; the twelve stored
nights were all built before it (the latest, 10-03, at 16:34:13 UTC), which is §3's open question
for Task 4. `config.yaml`: the `DE_COACH_THRESHOLDS` entry names the LEARNING scope and its readers,
lists the migration in `source_files`, and says the DDL file's re-seed (`DELETE WHERE TRUE`) does not
carry these rows. The DDL file itself is unchanged, as it was for the INTENT migrations.

**Checked.** `scripts/bigquery/tests/LEARNING_SETTINGS_acceptance.sql` (new): S1 every key once
under exactly that scope and no LEARNING row elsewhere; S2 each key's latest history event exists,
is not REMOVED and carries the live value; S3 a row still as the migration wrote it holds its seed
value and a description naming its source. Before the migration (17:04 UTC) the three LIVE rows read
12 violations each (FAIL): none passes on an empty seed. After it (17:06 UTC) all 14 rows PASS: S1,
S2, S3 LIVE 0; the controls, each on a doctored TEMP copy, fired with NC_EMPTY 12 / 12 / 12,
NC_S1_BLITZ (the plan's control: `MIN_INVEST_MIN_ROWS` under `coach_mode = 'BLITZ'`) 2,
NC_S1_FAMILY 2, NC_S1_DUP 1, NC_S2_UNSNAPPED 1, NC_S2_REMOVED 1, NC_S2_STALE 1, NC_S3_VALUE 1,
NC_S3_NODESC 1. 19.8 slot-seconds, 0.18 MB. `THRESHOLD_HISTORY_acceptance.sql` run as written
after the seed (17:06–17:08 UTC): 17 rows PASS, C01 over 194 coach rows and 3 plan rows, C06 and C07 over
the new rows; 446.3 slot-seconds, 104 s; its `TMP_THIST_*` tables dropped.

**Two seeds re-measured at deploy** (the other ten are the spec's or the rulings' constants, and
`BID_TO_CPC_RATIO_FALLBACK` is spec §14 E4's Q3):

- `SETTLE_HORIZON_DAYS` 14 — the first age at which `V_PLAN_SETTLE_COMPLETION.sales_completion`
  reads 1.0 on both channels. Read 17:00 UTC: SP first complete at 14 (13 reads 0.99), SB at 11.

  ```sql
  SELECT channel,
         MIN(IF(sales_completion >= 1.0, age_days, NULL)) AS first_age_complete,
         MAX(IF(sales_completion <  1.0, age_days, NULL)) AS last_age_incomplete,
         ROUND(MAX(IF(age_days = 13, sales_completion, NULL)), 4) AS c13,
         ROUND(MAX(IF(age_days = 14, sales_completion, NULL)), 4) AS c14
  FROM `onyga-482313.OI.V_PLAN_SETTLE_COMPLETION`
  GROUP BY channel ORDER BY channel;
  ```

- `OWN_CVR_MIN_CLICKS` 30 — per stored night, the plan's keywords whose latest
  `FACT_KEYWORD_STATE_HISTORY` snapshot captured at or before `built_at` has `settled_clk90 >= 30`.
  Read 17:00 UTC (19.2 slot-seconds): 180 of 361 on each night 09-28 … 10-02 (the brief's figure),
  180 of 356 on 10-03, 182–183 of 373–376 on 08-24 … 08-28, and **0 of 365 on 08-23 — no snapshot
  existed**: the history's first `captured_at` is 2026-08-24 21:22:53 UTC, after the 08-23 night's
  `built_at` (2026-08-24 05:34:19 UTC); its `snapshot_date`s reach back to 08-17 because they were
  backfilled. For Task 4: on the 08-23 night no keyword has an own rate "at `built_at`".

  ```sql
  WITH nights AS (
    SELECT as_of, MIN(built_at) AS built_at
    FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE plan = 'B' GROUP BY as_of
  ),
  keys AS (
    SELECT DISTINCT p.as_of, n.built_at, p.campaign_id, p.keyword_id
    FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p JOIN nights n USING (as_of)
    WHERE p.plan = 'B'
  ),
  snap AS (
    SELECT k.as_of, k.campaign_id, k.keyword_id,
           ARRAY_AGG(h.settled_clk90 ORDER BY h.captured_at DESC LIMIT 1)[SAFE_OFFSET(0)] AS clk90
    FROM keys k
    LEFT JOIN `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY` h
      ON h.campaign_id = k.campaign_id AND h.keyword_id = k.keyword_id AND h.captured_at <= k.built_at
    GROUP BY 1, 2, 3
  )
  SELECT as_of, COUNT(*) AS keys, COUNTIF(clk90 >= 30) AS keys_ge_30,
         COUNTIF(clk90 IS NULL) AS keys_no_snapshot
  FROM snap GROUP BY as_of ORDER BY as_of;
  ```

### Task 3 — the freeze and `builder_version` (2026-10-03)

**Deployed.** `scripts/bigquery/migrations/2026-10-03_plan_builder_version.sql` at 17:34:46 UTC (job
`t3_migration_1791048884`): `FACT_PLAN_NEXT_WEEK.builder_version STRING`, ordinal 109 of 109; run
again at 17:35:00 UTC, a no-op (`t3_migration_rerun_1791048898`). Mirrored in
`scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql`. `SP_BUILD_NEXT_WEEK_PLAN` v27.170 at 17:41:54 UTC
(`INFORMATION_SCHEMA.ROUTINES.last_altered`; job `t3_deploy_builder_1791049311`), with its comment
lines stripped. Before it, the deployed v27.169 body equalled HEAD's file (comment lines stripped,
whitespace normalized); after it, the deployed body equals this file the same way. `config.yaml`:
`FACT_PLAN_NEXT_WEEK` (description, the migration in `source_files`) and `SP_BUILD_NEXT_WEEK_PLAN`
(description). `architecture/NEXT_WEEK_MONEY.md` §3: two sentences that said every pass rewrites the
night now point here. No real build ran: the 10-03 night is frozen from the deploy on (its Los
Angeles midnight passed at 07:00 UTC), and the first night v27.170 writes is 10-04, at the 05:00 UTC
pass of 2026-10-04. Piece-2 Task 8 runs the real builder after that midnight and shows `FROZEN`.

**What the freeze stops, measured before it** (every write of the plan table since nights were keyed
on the New York date, read 17:54 UTC): the 10-03 night was written 9 times — 1 first write (the
05:00 UTC pass, 05:36 UTC) and 8 rewrites, all after Los Angeles midnight of 10-03 (2 by the
orchestrator's 07:35 and 16:00 UTC passes, 6 by hand CALLs); the 10-02 night's stored write was a
hand rewrite at 02:50 UTC on 10-03.

```sql
SELECT DATE(creation_time, 'America/New_York') AS night,
       COUNTIF(statement_type = 'DELETE') AS writes,
       COUNTIF(statement_type = 'DELETE' AND dml_statistics.deleted_row_count = 0) AS first_writes,
       COUNTIF(statement_type = 'DELETE' AND dml_statistics.deleted_row_count > 0
               AND creation_time >= TIMESTAMP(DATE(creation_time, 'America/New_York'), 'America/Los_Angeles'))
         AS rewrites_after_la_midnight,
       COUNTIF(statement_type = 'DELETE' AND STARTS_WITH(parent_job_id, 'scheduled_query_')) AS by_the_orchestrator
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP '2026-10-03 02:45:20+00'
  AND state = 'DONE' AND error_result IS NULL AND statement_type IN ('INSERT', 'DELETE')
  AND destination_table.dataset_id = 'OI' AND destination_table.table_id = 'FACT_PLAN_NEXT_WEEK'
GROUP BY night ORDER BY night;
```

F1's own text, its cutover set to 2026-10-02 00:00 UTC, read the table as it stood at 17:34 UTC: 2
(the 10-02 and 10-03 nights, each stored by a rewrite after Los Angeles midnight of its `as_of`; job
`bqjob_r26caffed21880c52_000001a102d4cb72_1`, 44.8 slot-seconds).

**Which pass writes, and the freshness it costs** (§1, "The freeze"). The schedules (`bq ls
--transfer_config --transfer_location=us`): `daily_run_sp_orchestrate_morning` every day 05:00,
`daily_run_sp_orchestrate` 07:35, `daily_run_sp_orchestrate_evening` 16:00, UTC. The plan step's
runs in `LOG_PIPELINE_RUNS` 2026-09-29 … 10-03 started 05:34–05:43, 08:05–08:21 and 16:33–17:02 UTC
(22:34–22:43, 01:05–01:21 and 09:33–10:02 Los Angeles). One night's windows, read by BigQuery time
travel on the 10-03 night: the 05:36:35 UTC write (22:36 Los Angeles on 10-02) judged 09-28 … 09-30
(`as_of` − 3); the 08:12:08 and 16:34:13 UTC rewrites judged 09-29 … 10-01 (`as_of` − 2). Under the
freeze the first stands.

```sql
-- run once per read time: 2026-10-03 05:40:00, 08:20:00, 17:20:00 UTC
SELECT as_of, MAX(built_at) AS built_at, MIN(window_from) AS window_from, MAX(window_to) AS window_to,
       DATE_DIFF(as_of, MAX(window_to), DAY) AS as_of_minus_window_to
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` FOR SYSTEM_TIME AS OF TIMESTAMP '2026-10-03 05:40:00+00'
WHERE as_of = '2026-10-03' GROUP BY as_of;
```

(Time travel reaches back 7 days; after 2026-10-10 the plan step's times are still readable from
`LOG_PIPELINE_RUNS` and the windows only from a night written before and after a later pass.)

**The guard, proved on a copy of the builder** (no real rewrite). One judgement snapshot,
`OI._tmp_t3_judge` (17:34 UTC, job `t3_judge_snap_1791048876`, 366.6 slot-seconds). The procedure
copy `OI._tmp_t3_build(la1, la2)` is this file with its comment lines stripped and four swaps: the
plan table → `OI._tmp_t3_plan` (a `COPY` of `FACT_PLAN_NEXT_WEEK` after the migration), the view →
the snapshot, and the two Los Angeles readings → `COALESCE(la1 | la2, CURRENT_DATE('America/Los_Angeles'))`
(NULL = the clock). The scratch tables expire 2026-10-10; the three procedure copies were
dropped after the run.

| case | call | what happened | job, slot-seconds |
|---|---|---|---|
| first write after Los Angeles midnight | 10-03 night removed from the copy; `(NULL, NULL)` at 10:44 Los Angeles 10-03 | written: 712 rows, `builder_version = 'v27.170'` on all, `built_at` 17:44:03 UTC; its `DELETE` removed 0, its `INSERT` wrote 712 | `t3_caseB2_1791049335`, 657.0 |
| rewrite after Los Angeles midnight | `(NULL, NULL)` again | `FROZEN: partition 2026-10-03 was written at 2026-10-03 17:44:03 UTC; its first day has begun; not rewritten (…)` at entry; no `DELETE` or `INSERT`; 1.6 s | `t3_caseC2_1791049500`, 0.12 |
| rewrite before Los Angeles midnight | copy `OI._tmp_t3_plan2`; `(10-02, 10-02)` | rewritten: its `DELETE` removed 712, `built_at` 17:44:03 → 17:46:40 UTC | `t3_caseD_1791049524`, 501.3 |
| a build that crosses Los Angeles midnight | `(10-02, 10-03)` | built (`INSERT INTO final`), then `FROZEN … 17:46:40 UTC …` at the second reading; no `DELETE` or `INSERT` on the copy; the night still 17:46:40 | `t3_caseE_1791049666`, 705.0 |

The same two first cases ran before the deploy too (`t3_caseB_1791048940`, 831.1; `t3_caseC_1791049200`,
0.17), with the same outcome. **No verdict, seat or move changes:** HEAD's v27.169 body, swapped the
same way into `OI._tmp_t3_build169` / `OI._tmp_t3_plan169` (`t3_v169_dry_1791049178`, 490.3), and
the v27.170 body (`t3_caseB_1791048940`) wrote equal 10-03 nights on the snapshot: 712 rows, the
same keys, all 107 columns other than `built_at` and `builder_version` equal value for value.

**Checked.** `FACT_PLAN_NEXT_WEEK_acceptance.sql` gained F1 and F2 (cutover 2026-10-03 17:41:54+00,
the deploy). On the live table at 17:51 UTC: 37 rows PASS, F1 1 and F2 1 from their emptiness terms
alone — no night written since the deploy (`t3_acc_live_1791049874`, 734.4 slot-seconds, 330,785,449
bytes). They read 0 only after the 10-04 night is written; Task 8 re-runs the suite.
`check_plan_clock_controls.py` gained the write record (`--jobs-table-id`) and six copies; run on the
simulated pass above (`--plan-table onyga-482313.OI._tmp_t3_plan --jobs-table-id _tmp_t3_plan
--judge-table onyga-482313.OI._tmp_t3_judge`), exit 0, all 17 copies exercised (job
`bqjob_r7d71ccc3fee762d1_000001a102e149e3_1`, 5,558.7 slot-seconds, 678,044,832 bytes):

- LIVE — the late first write (17:44:03 UTC, after Los Angeles midnight, its `DELETE` removing 0):
  41 readings 0 (the file's 39, and V_ENGINE_HEALTH c23's two).
- NC_EMPTY: F1 1, F2 1.
- NC_F1_SECOND_WRITE_AFTER_MIDNIGHT (the plan's control — the write's `DELETE` recorded as removing
  the night's 712 rows): F1 1. NC_F1_WRITE_NOT_ON_RECORD (its `INSERT` removed): F1 1.
- HC_F1_REWRITE_BEFORE_MIDNIGHT (that rewrite re-keyed to 10-04 and stamped 22:35 Los Angeles on
  10-03, its two jobs moved with it): F1 0, F2 0. NC_F1_REWRITE_AT_MIDNIGHT (stamped 00:00 Los
  Angeles on 10-04): F1 1.
- NC_F2_NULL (the plan's control, one row NULL): F2 2 — no version, and not the deployed one.
  NC_F2_STALE_VERSION (one row `'v27.169'`): F2 1.
- Unasserted, printed: NC_K1_NOT_NY_DATE and NC_K3_NO_SHADOW also read F1 1 (a night restamped
  22:40 Los Angeles has no `INSERT` in the hour after it; a night without its shadow rows no longer
  has the row count its `INSERT` wrote).

The first collect expected NC_F2_NULL to read 1; it read 2, because a NULL fails both of F2's terms.
The expectation was corrected in the script and the same job re-collected (exit 0).

**Follow-up, same day.** `INFORMATION_SCHEMA.JOBS` keeps 180 days of jobs, so from about 2027-04-01
F1 would have read the first nights' writes as "not on record" for ever. F1 now reads the nights
written in the last 170 days (its emptiness term too). Re-run after the change: the live table at
17:57 UTC 37 PASS, F1 1 and F2 1 by emptiness (`t3_acc_live2_1791050257`, 682.4 slot-seconds); the
controls with the same arguments exit 0, every reading above unchanged
(`bqjob_r60aad232f3626a83_000001a102ea38f4_1`, 6,722.0 slot-seconds, 678,044,832 bytes).
