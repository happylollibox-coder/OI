# LEARNING — the plan's prediction ledger, its grader and its report card — SOP

**Spec:** `docs/superpowers/specs/2026-10-01-learning-contract-design.md` (§4–§8, §10–§12; piece-2
rulings D1–D6 and the evidence behind them in §14)
**Plan:** `docs/superpowers/plans/2026-10-03-learning-piece2-ledger-grader.md` (Tasks 1..8)
**Doctrine:** `architecture/THREE_LAYERS.md` §6 (every layer gets better on its own; the Brain keeps
the ledger)
**Status:** Task 1 (2026-10-03) wrote this SOP before any code. Task 2 (2026-10-03) seeded the
LEARNING settings (§3; §10 "Task 2"). Task 3 (2026-10-03) deployed the freeze and `builder_version`
(§1 "The freeze"; §10 "Task 3"), and its follow-up 2 the judgement each night was built on, which C13
reads (§1 "The freeze"; §10 "Task 3 follow-up 2"). Task 4 (2026-10-03) deployed the ledger,
`V_PREDICTION_LEDGER` v27.172, with the campaign-budget clause in its recommended form (§3; §10
"Task 4"). Task 5 (2026-10-03) deployed the grader `SP_GRADE_PREDICTIONS` v27.173, its grades
`FACT_PREDICTION_GRADE` and its report card `T_PREDICTION_SCORECARD`, and ran it once: the six
August nights are graded (§4, §5; §10 "Task 5"). Task 6 (2026-10-04) put the grader on the
schedule (orchestrator Refresh Task 20.8f, v27.176), the three health checks on the board
(`V_ENGINE_HEALTH` c35–c37) and the two RED-able ones on the brief's SYSTEM line (§6; §10 "Task
6"). Nothing else below is deployed yet: the rest of the contract suite is Task 7. Each task appends
its own entry to §10 "Deploy and verify" and corrects any sentence here that its build proves wrong.

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
| `horizon_to` | `horizon_from + window_days − 1` (`window_days` is carried too) |
| `family`, `campaign_id`, `keyword_id`, `channel`, `calendar_state`, `is_live_plan`, `holdout`, `family_bar` | as stored |
| `min_orders` | the `DE_PLAN_CONFIG` row for the night's `calendar_state` in force at `built_at`, read from the config history |
| `current_bid`, `planned_bid`, `campaign_current_budget`, `campaign_planned_budget` | as stored |
| `move` | `ACT` rows only: the plan's move; NULL on `DO_NOTHING` |
| `alloc_spend` | `planned_spend_per_day × window_days` — the seat's spend, the plan's ALLOCATION (what `FN_PLAN_SCORECARD` grades). Not a forecast |
| `act_is_noop` | TRUE when the move has no bid component, no state component and no budget component (§4 step 4 defines the three) |
| `pred_side` | `IF(side = 'GOOD', 1, 0)`, the same on both scenarios |
| `basis_clicks`, `basis_spend` | `w_clk`, `w_sp`: the window the prediction stood on; `settle_factor_eff` beside them |
| `pred_clicks`, `pred_spend`, `pred_orders`, `pred_gp`, `pred_net` | the five predicted numbers over the horizon (§2, §3) |
| `rule_version` | the `history_id` of the `DE_PLAN_CONFIG` row for the row's `calendar_state` in force at `built_at`, `‖ ':' ‖ builder_version` (`'pre-v27.170'` where the row has none). In force: each config row's latest history event at `built_at` is active and not `REMOVED`, and of those rows for the state the latest; an event counts from its `snapshot_at`, a `SEEDED` one from its `source_updated_at` (the history began 2026-10-02; the seed rows took force on their `updated_at`, 2026-08-23) |
| `response_model_version` | `'RUN_RATE'` on `DO_NOTHING`; on `ACT`, `'RM1:'` + the history ids, comma-separated in key order, of the four settings that price it (`BID_TO_CPC_RATIO_FALLBACK`, `CLICK_BID_ELASTICITY`, `CPC_BID_EXPONENT`, `OWN_CVR_MIN_CLICKS`), as §3 picks them |
| `act_bid_ratio`, `act_budget_factor`, `act_basis` | `ACT` rows only (NULL on `DO_NOTHING`): r, the campaign-budget factor (§3), and how the row was priced — `ANCHORED`, `PAUSE`, `ZERO_BASIS`, `SEAT_PROBE_OWN`, `SEAT_PROBE_POOLED` |

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
- **The night keeps the judgement it was built on (v27.171, Task 3 follow-up 2).** Acceptance C13
  asserts that the live plan reproduces the judgement row for row. Until v27.170 it compared the
  latest night with the *live* `V_PLAN_WINDOW_JUDGMENT`, which held while later passes rewrote the
  night on the view's current window. Under the freeze it cannot: the night is built on the Los
  Angeles day before its `as_of` and stays, while the view's fence moves at Los Angeles midnight, so
  C13 against the view could pass only between a night's write and that midnight, and every harness
  that requires a clean LIVE run would fail the rest of the day. **Choice: option (a).** The builder
  writes `T_PLAN_BUILD_JUDGMENT` (`scripts/bigquery/tables/T_PLAN_BUILD_JUDGMENT.sql`) right after
  the plan partition — one row per row of its one read of the view, stamped with the night's `as_of`
  and `built_at`, with the columns C13 compares (`side_b`, `verdict`, `is_candidate`, `window_from`,
  `window_to`, `calendar_state`) — past both freeze readings and R11's guard, so a frozen, refused or
  failed pass writes neither table, and a rewrite before midnight replaces both. C13 reads that record
  for the latest night's `as_of` and `built_at`: the row-for-row difference, plus 1 when the night's
  judgement is not on record (a night written before v27.171, or a record of another write), plus 1
  when the live plan is empty. It no longer reads the view, so the hour it runs does not matter.
  Option (b) — run C13 only when the view's window and calendar state equal the night's, and report
  "not comparable" otherwise — was not taken: under the freeze the two are equal only between the
  05:00 UTC pass's write and Los Angeles midnight (07:00 UTC under daylight time), so C13 would test
  something for at most two hours a day, and an equal window still reads data restated after the
  build (measured in §10 "Task 3 follow-up 2"). T1's click goal is the only
  term that still reads the live view (`click_goal_day`, a constant the view declares).
- **Checked by** `FACT_PLAN_NEXT_WEEK_acceptance.sql` F1 (no night written since the deploy was
  rewritten after Los Angeles midnight of its `as_of`; whether a write was the night's first is read
  from its own `DELETE` in `INFORMATION_SCHEMA.JOBS_BY_PROJECT` — a first write removes nothing) and
  F2 (every row written since the deploy carries a `builder_version`, the deployed builder's on rows
  written since its deploy), each with an emptiness term, and C13 (above); controls in
  `scripts/bigquery/tests/check_plan_clock_controls.py`. A LIVE run of the suite or of its three
  harnesses (`check_plan_clock_controls.py`, `check_plan_seat_controls.py`,
  `check_plan_money_controls.py`) reads every check 0 at any hour once a night has been written by
  v27.171; before that it reads C13 1, F1 1 and F2 1 (not on record / emptiness). The harnesses take
  `--build-judge-table` to read a copy of the record a simulated pass wrote.

**Why a ledger row never changes after its night is final.** The view reads only stored columns of
a night that is no longer rewritten, the settings history (append-only, `FACT_THRESHOLD_HISTORY`:
a new event is stamped with the pass that saw it, after every night already final, so it never
reaches one — §3) and the keyword-state history (`FACT_KEYWORD_STATE_HISTORY`, the latest
`snapshot_date` *before* the Los Angeles date of `built_at` — §3: a `snapshot_date` is re-captured,
and its earlier copy pruned, by every pass on that Los Angeles date, so only an earlier date is
final when the night is written). It reads no catalog table (D3, D6) and no `FACT_AMAZON_ADS`. The DO_NOTHING orders and
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
fewer clicks, each at a higher or lower price), a campaign whose budget the plan cuts is capped at
its new budget (§3), and a paused keyword does nothing. Where the plan moves
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

**The campaign budget — ruled 2026-10-03: the recommended form** (spec §6, §14.1, §14 E8). The
clause was raised by the Task-1 review after D1–D6 and held open for Ori; the request that runs
piece 2 is Ori's "all recommended", and Task 4 read it as covering this clause too and built the
recommended form (the first form is a one-line change in the view's `camp` CTE if Ori rules
otherwise). A budget is set per campaign, so it acts on the sum of the campaign's keywords: where
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
words name, which is why it was Ori's to rule.

The argument against a cap (spec §14 E5: `DO_NOTHING` already runs above the current budget in some
campaigns, and a cap would cut those whether or not the plan moved them) applies only to a cap on
campaigns the plan does not cut. Neither form runs there, and on a cut campaign that overdelivers
the recommended form keeps the proportional cut.

**As built** (`V_PREDICTION_LEDGER`, CTE `camp`): per (`as_of`, `plan`, `campaign_id`), where
`MAX(campaign_planned_budget) < MAX(campaign_current_budget)`,

```
factor = COALESCE(LEAST(1, SAFE_DIVIDE(GREATEST(planned × H, SAFE_DIVIDE(Σ w_sp × planned, current)),
                                      Σ ACT spend before the clause)), 1)
```

and 1 on every other campaign; the factor multiplies all four of an `ACT` row's clicks, spend,
orders and gross profit (net = gross profit − spend), the seat-priced probes included. It is 1 where
the campaign's `ACT` spend is 0 (nothing to cut). §10 "Task 4" records what it removes on the
stored nights, against spec §14 E8.

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

**Which snapshot, and the pool (fixed by Task 4).** One snapshot per night: the latest
`snapshot_date` of `FACT_KEYWORD_STATE_HISTORY` *before* the Los Angeles date of `built_at`, among
copies captured at or before `built_at`. Not the latest copy captured before `built_at`, which the
brief named: a `snapshot_date` is the Los Angeles date of the pass that captures it, every later
pass on that date re-captures it and prunes the earlier copy, so a night written at 16:34 UTC on
2026-10-03 would read the 10-03 copy until the 05:00 UTC pass of 10-04 replaced it, and then fall
back to 10-02 — a stored night's prediction changing after the fact (§10 "Task 4" measures the
two copies on that night). An earlier date is final when the night is written. The cost is up to a day of freshness
in a 90-day settled rate. The **own** rate is the keyword's row in that snapshot when its
`settled_clk90 ≥ OWN_CVR_MIN_CLICKS`; the **pool** is Σ `settled_ord90` ÷ Σ `settled_clk90` (CVR) and
Σ `settled_gp90` ÷ Σ `settled_ord90` (GP per order) over the night's plan keywords of the same
family and channel in that snapshot (the plan's own universe, not every keyword the catalog holds).
Gross profit is 0 where the CVR is 0. A night with no such snapshot (the 08-23 night: the history's
first copy was captured after it was written) has no own or pooled rate, and a zero-click
`OPEN_PROBE` on it would read NULL (acceptance L1); §10 "Task 4" lists the stored zero-click probes.

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
| `MATCH_WINDOW_DAYS` | — | 3 | grader | days from the start of `horizon_from` (and the hours from `built_at` before it) in which a change can count as the plan's (§4; until v27.174, Los Angeles dates `as_of … as_of + 3`, and the setting's stored description still says so) |
| `MATCH_BID_TOL` | — | 0.005 | ledger, grader | a bid matches the plan within this; a plan row has a bid component when its bid moves by at least this (`act_is_noop`) |
| `MATCH_BUDGET_TOL` | — | 0.01 | ledger, grader | a budget matches the plan within this; a budget component when the campaign budget moves by at least this (`act_is_noop`) |
| `MIN_INVEST_SIDE_ACCURACY` | — | 0.80 | grader | the side accuracy a click bucket must clear to set the line (D4) |
| `MIN_INVEST_MIN_ROWS` | — | 20 | grader | rows a bucket needs behind it before it can set the line (D4) |
| `MIN_GRADED_WINDOWS` | — | 3 | health | windows per side of the regression comparison |
| `REGRESSION_MAX` | — | 0.10 | health | how much worse is RED |

Which value priced a row is on the row: `response_model_version` names the history ids in force.
**How the ledger reads them (Task 4).** From `FACT_THRESHOLD_HISTORY` (the LEARNING scope), never
from `DE_COACH_THRESHOLDS` directly, which holds only today's value: per night and key, the latest
event with `snapshot_at ≤ built_at`. All twelve nights stored on 2026-10-03 were built before the
settings existed (first recorded 2026-10-03 17:05:15 UTC), so none has a value in force; **a night
built before a key's first event takes that first event** — the seed. The history is append-only and
each new event is stamped with the pass that saw it, so a later event is never in force at a stored
night's `built_at`, and a key's first event never changes: the value that priced a night never
changes (proved on copies in §10 "Task 4"). The limit: a
setting changed by hand and a builder CALLed by hand before the next pass's snapshot is recorded
under the previous value (the orchestrator snapshots at Refresh Task 10.1, before the plan step).

**What the plan row supplies.** `w_clk`, `w_sp`, `w_ord`, `w_gp_corrected`, `settle_factor_eff`,
`window_days`, `move`, `current_bid`, `planned_bid`, `bid_park`, `bid_floor`, `seat_cost_per_day`,
`campaign_current_budget`, `campaign_planned_budget`, `built_at`.

---

## 4. How a grade is decided — `SP_GRADE_PREDICTIONS` → `FACT_PREDICTION_GRADE`

| object | file | what it is |
|---|---|---|
| `SP_GRADE_PREDICTIONS(regrade_from DATE, reason STRING)` | `scripts/bigquery/procedures/SP_GRADE_PREDICTIONS.sql` (Task 5) | the grader; nightly `CALL … (NULL, NULL)`, orchestrator "Task 20.8f", between `SP_APPEND_CATALOG_FORECAST` and `SP_REFRESH_CUBE_TABLES` (Task 6). Reads its settings from `DE_COACH_THRESHOLDS` (today's values, asserted present once each) |
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
   `LOGGED_ONLY`), **on the prediction's own clock** — `built_at` to the end of the horizon (ruled
   2026-10-04, below):
   - the changes read: the keyword's own (`keyword_id`), and its campaign's state and budget changes
     (`keyword_id` NULL, the same `campaign_id`, a `*BUDGET*` or `CAMPAIGN_*` action), **applied at
     or after `built_at`** and before the Los Angeles midnight that ends `horizon_to` (an SB
     keyword's own `SEEN_ON_AMAZON_*` changes: the midnight one day later, below). A change made
     before the plan existed is the state the plan was built on, never an action on it. Ad-group
     changes are not read (§9);
   - **the instant a change is read at is its landing on Amazon** (Task-5 review 2, 2026-10-04): a
     `SEEN_ON_AMAZON_*` row at its own `applied_at`, the observation; a `LOGGED_AND_SEEN_ON_AMAZON`
     row — a log row an observed row confirms, which the view keeps while dropping the observed twin
     — at the earliest `applied_at` in `FACT_PPC_CHANGE_LOG` of the observed rows its
     `paired_change_id` names, never at its own log stamp. A book row is stamped
     `CURRENT_TIMESTAMP()` when the book is built (`tools/build_reprice_bulksheet.py`),
     `--mark-uploaded` changes only its `upload_status`, and the recorder pairs a landing from one
     day before the stamp to three days after it (`SP_RECORD_OBSERVED_CHANGES`). Read at the stamp, a
     plan book built after `built_at` but uploaded after the match window would still match and read
     `ACT`, and a hand book built before `built_at` but uploaded after it would be dropped as baseline
     and leave the row `DO_NOTHING`. Every instant read is therefore an observation: for campaigns and
     SP keywords Amazon's own last-updated time, for SB keywords the Fivetran sync that first saw the
     change (`V_AMAZON_OBSERVED_CHANGES`). Measured 2026-10-04 on the 60 `LOGGED_AND_SEEN_ON_AMAZON`
     rows (70 observed twins, each found once in `FACT_PPC_CHANGE_LOG`): landing minus stamp
     −1 to +1,079 minutes — the SP keywords of `reprice_book_20260823_1527` +26 (15 rows), SP keyword
     pauses of `seat_moves_20260823_1045` +249 (9), SB keywords +678 to +1,079 (29 rows, 39 twins),
     campaign pauses −1 (7); none on another Los Angeles date than its stamp, and none on the other
     side of a `built_at`, match-window end or scan end of a current grade that reads it, so no
     stored grade moves (§10 "Task 5 follow-up 2");
   - the plan's **expected components**: a bid component when |`planned_bid` − `current_bid`| ≥
     `MATCH_BID_TOL`; a state component for PAUSE; a budget component when |planned − current
     budget| ≥ `MATCH_BUDGET_TOL`. `act_is_noop` = none of the three;
   - a change **matches** a component when it is applied in `[built_at`, the Los Angeles midnight
     that starts `horizon_from + MATCH_WINDOW_DAYS)` — never past the end of `horizon_to` — and is
     on the same keyword (bid within `MATCH_BID_TOL` of `planned_bid`; PAUSE ← `KEYWORD_PAUSE` /
     `STOP_TARGET`) or the same campaign (a `*BUDGET*` action within `MATCH_BUDGET_TOL` of
     `campaign_planned_budget`) — the recorder's own rules (`SP_RECORD_OBSERVED_CHANGES`). Every
     other change read is an *other* change, a matching one made after the match window included;
   - **`ACT`** when the plan row has at least one component, every one matched, and no other change
     was read; **`DO_NOTHING`** when no change was read at all — nothing on the keyword and no state
     or budget change on its campaign, from `built_at` to the end of the horizon — so a row whose
     plan asks for nothing, with nothing done after the build, is `DO_NOTHING` (its two scenarios
     are equal by anchoring, §3); **`OTHER_ACTION`** otherwise, a partial match included (a matched
     bid on a row whose budget component did not land is `OTHER_ACTION`);
   - `placement_changed`: the keyword's `FACT_KEYWORD_STATE_HISTORY.m_effective` on its latest
     snapshot on or before `as_of` differs, beyond float noise (1e-6), from the one on or before
     `horizon_to`; both readings are on the grade row (`placement_m_from`, `placement_m_to`), and the
     flag is NULL when either is missing. Placement changes are not in the change log, and
     `m_effective` moves with the click mix as well as with a setting (§9).

   **Why the clock is `built_at` … `horizon_to`** (Task-5 review, ruled 2026-10-04 "all
   recommended"; spec §7 and §14.1 record it). v27.173 read changes on the Los Angeles dates `as_of …
   as_of + MATCH_WINDOW_DAYS` (the spec's "within 3 days after `as_of`"). That window is not the
   prediction's: (a) it read changes made on `as_of` before the build — on the August nights 64 of the
   163 `OTHER_ACTION` plan rows per plan had every change applied before `built_at`, and on 60 of
   them every change's new bid or budget already equalled the row's `current_bid` /
   `campaign_current_budget`, so their horizons ran the `DO_NOTHING` baseline; (b) under New York
   keying the night is written on the Los Angeles evening before `as_of` (§1 "Which pass writes a
   night"), so a change made between the build and Los Angeles midnight carries the date `as_of − 1`
   and was never read; (c) the "nothing else changed" test covered `as_of … as_of + 3` only — four of
   a 7-day `OFF_PEAK` horizon's seven days unread, and one day past a New York-keyed 3-day horizon.
   The re-grade's numbers are in §10 "Task 5 follow-up".

   **The SB sync lag.** An SB keyword's observed instant is the Fivetran sync that first saw the
   change, up to a day after it (`V_AMAZON_OBSERVED_CHANGES`); for campaigns and SP keywords it is
   Amazon's own last-updated time. At the end of the horizon the grader therefore reads an SB
   keyword's own **`SEEN_ON_AMAZON_*`** changes — the ones OI's log does not account for as applied —
   one Los Angeles day longer, through `horizon_to + 1`: a hand change made on the last horizon day
   and seen the next day still counts, and a change made on `horizon_to + 1` itself is read too and
   makes the row `OTHER_ACTION` — the scan leaves a row out of `APPLIED` rather than call a disturbed
   horizon undisturbed. A `LOGGED_AND_SEEN_ON_AMAZON` change on an SB keyword is not read the extra
   day (Task-5 review 2): it is OI's own upload, and under nightly uploads the book uploaded on
   `horizon_to + 1` would make every row it touches `OTHER_ACTION` for a change made after the
   horizon. The cost, stated: a logged SB change uploaded on `horizon_to` and first seen after
   Los Angeles midnight is not read (of the 60 logged changes seen so far, none was seen on another
   Los Angeles date than its stamp). The match window is not lengthened: a change made inside it but
   first seen after it is an other change, and so is a logged change whose book was built inside it
   but which landed after it. At the start, a change made before `built_at` and first seen after it
   is read as made after the build — an SB keyword's sync lag, or a book built before the plan and
   uploaded after it.
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
   Outcomes keep restating for days, so a grade moves only under an explicit
   `CALL SP_GRADE_PREDICTIONS(DATE 'yyyy-mm-dd', 'reason')`: the band is every prediction of the
   nights `as_of >= regrade_from` that has a current grade and is still gradable; each gets a new
   row with `regrade_seq` one higher and `regrade_reason` = the reason (a re-grade without a reason
   is refused). The first grade is `regrade_seq` 0, and the current grade of a prediction is its
   highest `regrade_seq`. Rows not yet graded are graded as on any night, `regrade_seq` 0.

**The grade row** (columns, `scripts/bigquery/tables/FACT_PREDICTION_GRADE.sql`): key `predictor,
variant, as_of, campaign_id, keyword_id, scenario, regrade_seq`; the ledger's copy — `family`,
`channel`, `calendar_state`, `window_days`, `is_live_plan`, `holdout`, `family_bar`, `min_orders`,
`move`, `current_bid`, `planned_bid`, `campaign_current_budget`, `campaign_planned_budget`,
`horizon_from`, `horizon_to`, `built_at`, `builder_version`, `rule_version`,
`response_model_version`, `basis_clicks`, `basis_spend`, `alloc_spend`, `act_is_noop`, the five
predicted numbers and `pred_side`; `applied_scenario`, `is_applied`, `matched_change_ids` and
`other_change_ids` (arrays of `V_PPC_CHANGE_LOG_LANDED.change_id`), `placement_changed`,
`placement_m_from`, `placement_m_to`; the five realised numbers, `real_side`, `side_correct`;
`err_net`, `abs_err_net`, `click_bucket`, `min_clicks_at_grade`; `grade`, `ungradable_reason`
(`KEYWORD_ARCHIVED` | `CAMPAIGN_ARCHIVED`); `graded_at`, `watermark`, `grader_version`,
`regrade_reason`. Checked by `scripts/bigquery/tests/PREDICTION_GRADE_acceptance.sql` (V1–V8, a
negative control per check; §10 "Task 5").

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
grades, fixtures excluded) and, for YOUNG and NEXT_WEEK, the ledger. File:
`scripts/bigquery/tables/T_PREDICTION_SCORECARD.sql` (Task 5), which creates it empty so its readers
compile before the first run; the procedure then replaces it with the same columns. An `UNGRADABLE`
row enters HONESTY only.

**Grain:** `predictor × variant × family × calendar_state × level × row_type`, plus `scenario` on
ACCURACY rows, `bucket` on CURVE rows and the week (`window_from`) on WINDOW rows. `family` and
`calendar_state` = `'ALL'` is the predictor's rollup (ACCURACY, MONEY, HONESTY, YOUNG, NEXT_WEEK);
CURVE and LINE are per family × calendar_state only, the grain the line is set on.
**Levels:** `WINDOW` — the Sunday-start week of `as_of` (the house week, `WEEK(SUNDAY)`), pooling
every graded night in it (D5); `TRAILING_3` — the group's three most recent graded windows;
`SINCE_START`; and `TONIGHT` for NEXT_WEEK. Every row carries `window_from` / `window_to`,
`n_windows`, `n_nights`, the run's `watermark`, `grader_version` and `scored_at`. The columns, in
order, are `scripts/bigquery/tables/T_PREDICTION_SCORECARD.sql`'s; the procedure builds the same
list (§10 "Task 5" compares them).

| row_type | what it says |
|---|---|
| `ACCURACY` | `scenario` `APPLIED` (the rows of the scenario that applied — the headline, and what `prediction_regression` reads), `DO_NOTHING` or `ACT` (every graded row of that scenario, applied or not: accuracy only): `n_rows`, `keywords`, the predicted and realised sums of the five numbers, `mae_net_usd` = Σ\|err_net\|; `mae_net_share` = Σ\|err_net\| ÷ Σ realised spend; `bias_share` = Σ(pred_net − real_net) ÷ Σ realised spend; `side_accuracy`, spend-weighted; `rule_versions`, `builder_versions` (the distinct values behind the row) |
| `MONEY` | per plan row: `dn_net_per_dollar` over DO_NOTHING-applied rows; `act_net_per_pred_dollar` (realised net ÷ predicted spend) over ACT-applied rows; `counterfactual_net_per_alloc` = Σ alloc_spend × (real_net ÷ real_spend, 0 where nothing was spent) ÷ Σ alloc_spend — `FN_PLAN_SCORECARD`'s GRADE metric, the only money metric that tells plan A from plan B until a plan is uploaded — with `alloc_spend` and `alloc_unrealized`; `pred_lift` = Σ(ACT pred_net − DO_NOTHING pred_net) and `realised_lift` = Σ(real_net − DO_NOTHING pred_net) over ACT-applied plan rows (`lift_rows`; NULL when none), `pred_lift_all` over every graded plan row; `lift_control` = `'DO_NOTHING_PREDICTION'` with that control's own accuracy beside it (`control_mae_net_share`, `control_bias_share`); `detail` says when lift is ungraded |
| `CURVE` / `LINE` | CURVE per bucket (`bucket`, `bucket_floor`): `bucket_rows`, `bucket_spend`, `bucket_accuracy`, and over the rows at or above the floor `cum_rows`, `cum_spend`, `cum_accuracy` (NULL on bucket `0`). LINE: the line as `min_clicks`, `settled_cpc` = Σ real_spend ÷ Σ real_clicks of the family's graded rows, `min_dollars` = `min_clicks` × `settled_cpc`, the two bars used (`bar_side_accuracy`, `bar_min_rows`) and a sentence naming the line or, with none, the best floor. The whole curve, not only the line; at `SINCE_START` the LINE is the line the labels were given |
| `HONESTY` | per plan row: `n_rows`, `n_right`, `n_wrong`, `n_inconclusive`, `n_ungradable`; `n_act_no_matching_action` (a non-no-op ACT whose row applied as DO_NOTHING); `n_other_action`; `n_placement_changed`; `n_predicted_but_zero_clicks` (bucket `0` with window clicks — "predicted but dark", D4) |
| `YOUNG` | per predictor × variant × family (`calendar_state` `'ALL'`): `ledger_rows`, `graded_rows`, `waiting_rows`, `next_due_watermark` (the house watermark at which the next waiting row becomes gradable) and a sentence saying, in words, whether anything is old enough to grade and when the next row will be |
| `NEXT_WEEK` | per family, tonight's live plan (`level` `TONIGHT`, the latest night of the ledger): `dn_pred_net`, `act_pred_net`, `dn_pred_spend`, `act_pred_spend` and the sentence "do nothing $X; upload the plan $Y" |

---

## 6. The health checks

In `V_ENGINE_HEALTH` v27.176 (Task 6) as c35–c37, inserted before c33, which stays last
(`HOLDOUT_INTEGRITY_acceptance.sql` slices the file there); see `architecture/ENGINE_HEALTH.md`.
Seven input CTEs read the tables — `lrn_set` (the three settings below), `lrn_wm` (the house
watermark and its two terms), `lrn_led` (the ledger's grade keys and `horizon_to`), `lrn_grd` (the
keys that hold a grade), `lrn_act` (the current `ACT` grades), `lrn_card` and `lrn_card_meta` (the
report card) — and the CTEs from `lrn_due` to `c37` read nothing else, so
`scripts/bigquery/tests/PLAN_HEALTH_acceptance.sql` (P1–P3) runs that text verbatim on doctored
copies of the seven inputs. THE TWO MUST CHANGE TOGETHER. The settings are read from
`DE_COACH_THRESHOLDS` (the LEARNING scope, today's values: the rows the grader reads), never as
literals. The contract suite's fixtures (`predictor = 'FIXTURE'`) are left out of every input.

- **`prediction_grades_fresh`** — RED when a ledger row has no grade although
  `DATE_ADD(horizon_to, INTERVAL SETTLE_HORIZON_DAYS + 1 DAY) <= watermark`, the house watermark of
  §4 step 1 (one night's grace after the grader could have graded it). A prediction with any grade
  row has a current grade (its highest `regrade_seq`). Reads the ledger, `FACT_AMAZON_ADS`'s newest
  `date` and `FACT_PREDICTION_GRADE`, never the report card. An empty population — no ledger row
  that old — is RED, not vacuously green, and so is a missing `SETTLE_HORIZON_DAYS` or a NULL
  watermark. It measures the grader against the data that exists: while `FACT_AMAZON_ADS` stops
  advancing no row falls due, and the check stays GREEN. Its detail line prints the watermark beside
  `FACT_AMAZON_ADS`'s newest day and `FN_ADS_ANCHOR_CAP()` so a lag is visible, and the day the next
  row falls past due; `V_ENGINE_HEALTH` has no check on the ads table's newest date (read
  2026-10-03), and `pipeline_step_failing` names a step that fails, not one that loads nothing new.
  *Corrected 2026-10-03 (Task-1 review): was the calendar clock of §4 step 1's first version.*
- **`prediction_regression`** — per predictor, from the report card's `WINDOW` rows of the
  predictor's rollup (`family` and `calendar_state` `'ALL'`; `ACCURACY` with `scenario` `APPLIED`, and
  `MONEY`). The graded windows are ranked newest first; the trailing `MIN_GRADED_WINDOWS` (t) and the
  `MIN_GRADED_WINDOWS` before them (p) are each pooled — `mae_net_share` = Σ `mae_net_usd` ÷ Σ
  `real_spend`, `counterfactual_net_per_alloc` = Σ (value × `alloc_spend`) ÷ Σ `alloc_spend`. "Worse
  by more than `REGRESSION_MAX`" is read as the setting's description says, a ratio of the earlier
  value (the margin form `FN_PLAN_SCORECARD`'s RECOMMENDATION uses): `mae_t − mae_p >
  REGRESSION_MAX × |mae_p|` (more error is worse) or `cf_p − cf_t > REGRESSION_MAX × |cf_p|` (less
  net per allocated dollar is worse). RED when any predictor is worse on either; INFO "YOUNG" while
  no predictor has twice `MIN_GRADED_WINDOWS` graded windows; GREEN otherwise; RED as well when the
  card holds no row at all (the grader has not rebuilt it) or a setting is missing. A window is a
  graded Sunday-start week of `as_of`; the most recent graded weeks are compared, so a week with no
  graded night (the September outage) is skipped, not counted. The detail gives, per predictor, the
  two spans' weeks and values and names every `rule_version` and `builder_version` (from the `MONEY`
  rows' `rule_versions` / `builder_versions`) that is in one span and not the other — the rule that
  moved.
- **`response_model_unverified`** — measured = current `ACT` grades that applied (`is_applied`) on a
  plan row with a component (`act_is_noop = FALSE`) and are not `UNGRADABLE`. INFO while there is
  none, GREEN once one exists, never RED; that needs an uploaded plan (piece 3). The detail counts
  the `ACT` grades applied on rows the plan moved nothing, the moves whose row applied as
  `DO_NOTHING` (the HONESTY row's `n_act_no_matching_action`) and the `OTHER_ACTION` rows.
- `proposals_open` is piece 6's, with `DE_RULE_PROPOSALS`.

`V_DAILY_BRIEF`'s SYSTEM line counts RED rows. The two RED-able checks join its priority list after
the three alarms — `pipeline_step_failing` 1, `plan_partition_fresh` 2, `plan_pass_failed` 3,
`prediction_grades_fresh` 4, `prediction_regression` 5, every other check 6 — and the board's detail
of each of the five is quoted when it is RED (the other REDs are named by name). The action is
unchanged: A NIGHT WAS NOT SAVED for the first two, A PLAN PASS FAILED for the third; a RED learning
check reads NEW or standing like any other. The copy of that list in
`scripts/bigquery/tests/PLAN_HEALTH_acceptance.sql` (`sys_twin`) changed in the same step.

---

## 7. Deploy order

Each step needs the one before it. Big files go up with their comment lines stripped:
`bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^[[:space:]]*--' FILE)"`.
Anything that may run past ~90 s is submitted `--nosync` and polled with `bq wait JOB 60`.

1. **Settings** (Task 2): `scripts/bigquery/migrations/2026-10-03_learning_settings.sql` (inserts only
   missing keys; never deletes or updates; its last statement is `CALL SP_SNAPSHOT_THRESHOLDS()`, so
   the history holds them), then `scripts/bigquery/tests/LEARNING_SETTINGS_acceptance.sql`.
2. **The freeze** (Task 3): `scripts/bigquery/migrations/2026-10-03_plan_builder_version.sql` (the
   column) and `scripts/bigquery/tables/T_PLAN_BUILD_JUDGMENT.sql` (the judgement each night was built
   on, v27.171), then `SP_BUILD_NEXT_WEEK_PLAN.sql` (the guard, `builder_version` and the saved
   judgement), then `FACT_PLAN_NEXT_WEEK_acceptance.sql` (C13 reads "not on record" and F1 and F2
   their emptiness terms until the first night written after the deploy) and
   `check_plan_clock_controls.py` on a simulated pass.
3. **The ledger** (Task 4): `scripts/bigquery/views/V_PREDICTION_LEDGER.sql`, then
   `scripts/bigquery/tests/PREDICTION_CONTRACT_acceptance.sql` (L1–L4; `--nosync`, polled).
4. **The grader** (Task 5): `tables/FACT_PREDICTION_GRADE.sql`, `tables/T_PREDICTION_SCORECARD.sql`,
   then `procedures/SP_GRADE_PREDICTIONS.sql`, then its first `CALL … (NULL, NULL)` (`--nosync`,
   polled; the August nights grade), then `scripts/bigquery/tests/PREDICTION_GRADE_acceptance.sql`
   (`--nosync`, polled).
5. **The schedule and the board** (Task 6): the orchestrator's new step — after diffing the deployed
   body against the file, where the new step must be the only difference; the orchestrator is never
   run by hand — then `V_ENGINE_HEALTH.sql`, `V_DAILY_BRIEF.sql`, then
   `scripts/bigquery/tests/PLAN_HEALTH_acceptance.sql` (`--nosync`, polled; it reads the whole brief).
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
`NEXT_WEEK` (tonight's "do nothing / upload the plan"). Task 5 ran this query on the deployed table
and confirmed the column names in §5 (§10 "Task 5").

---

## 9. Limits, stated

- **`ACT` is graded only where someone acted.** Until a plan is uploaded (piece 3) no `ACT` scenario
  applies; every non-no-op `ACT` row is an `ACT_NO_MATCHING_ACTION` honesty count, lift is ungraded,
  and `lift_control` is the DO_NOTHING prediction.
- **A budget raise has no effect in RM1**, and a cut caps `ACT` spend at the new budget (§3); the
  response model is a first guess, written down so it can be wrong in a measurable way.
- **A probe opened at its own current price.** A zero-click `OPEN_PROBE` is priced from its seat
  even when its planned bid equals its current bid. In a campaign whose budget also stays put that
  row is `act_is_noop` and its `ACT` differs from `DO_NOTHING`, so acceptance L2 would fire on it —
  the anchoring rule and the seat rule disagree there, and the check says so rather than hiding it.
  §10 "Task 4" says whether a stored night holds one.
- **The grading clock is one date for the whole ads table** (§4 step 1). It waits for
  `FACT_AMAZON_ADS`'s newest day, not for every day or every channel: a day missing below the newest,
  or one channel stalled while the other loads, grades as zero clicks.
- **"Do nothing" rests on the change record.** A keyword is DO_NOTHING-applied when no change was
  seen on it or its campaign. A stalled change feed would look the same as a quiet week.
- **Ad-group changes are not read** when deciding which scenario applied (step 4): an ad group
  paused or its default bid moved leaves the keyword's row `DO_NOTHING`.
- **`placement_changed` is a reading of a multiplier, not a record of a setting.** `m_effective`
  is `V_BID_CPC_TRANSFER`'s click-weighted placement multiplier over a rolling window, captured
  with the adjustments current at each snapshot (that view's KNOWN DEFECT 1: no adjustment history
  exists). It moves with the click mix whether or not a setting changed, so the flag can read TRUE
  where no setting moved; the two readings are on the row so a ruling on how large a move counts
  can be applied without a re-grade. §10 "Task 5" measures how often it reads TRUE.
- **Gross profit restates after grading** (`FACT_AMAZON_ADS` re-prices COGS): the grade keeps the
  numbers it was graded on, and `PREDICTION_GRADE_acceptance.sql` V2g reports how many rows have
  drifted since.
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

### Task 3 follow-up 2 — C13 reads the judgement the night was built on (2026-10-03)

**The defect (review of 5528c1e / 9b9b8f1).** C13 compared the latest night with the *live*
`V_PLAN_WINDOW_JUDGMENT`. Under the freeze a night is written by the 05:00 UTC pass on a window ending
`as_of` − 3 and stays, while the view's fence moves to `as_of` − 2 at Los Angeles midnight (07:00 UTC
under daylight time). Measured on the 10-03 night: the 05:36:35 UTC write and the 16:34:13 UTC write
differ on 47 of 356 live rows in side, verdict or is_candidate (side 11, verdict 45, candidacy 16;
the same 356 keys; BigQuery time travel, job `c13fix_tt47b_1791052048`; the query below gives 47 too,
job `c13fix_tt47c_1791053485`), and C13's v27.170 text
against the view at 18:32 UTC reads 47 on the 05:36:35 write and 0 on the 16:34:13 write (job
`c13fix_snap_1791052309`, 927.7 slot-seconds). So from the first frozen night C13 could pass only
between a night's write and Los Angeles midnight, and the three harnesses that require a clean LIVE
run would exit 1 the rest of the day.

```sql
-- the two writes of the 10-03 night, live rows (time travel reaches back 7 days)
CREATE TEMP TABLE a AS SELECT campaign_id, keyword_id, side, verdict, is_candidate
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` FOR SYSTEM_TIME AS OF TIMESTAMP '2026-10-03 05:40:00+00'
  WHERE as_of = '2026-10-03' AND is_live_plan;
CREATE TEMP TABLE z AS SELECT campaign_id, keyword_id, side, verdict, is_candidate
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` FOR SYSTEM_TIME AS OF TIMESTAMP '2026-10-03 17:20:00+00'
  WHERE as_of = '2026-10-03' AND is_live_plan;
SELECT (SELECT COUNT(*) FROM a) AS rows_0536, (SELECT COUNT(*) FROM z) AS rows_1634,
       (SELECT COUNTIF(a.campaign_id IS NULL OR z.campaign_id IS NULL)
          FROM a FULL OUTER JOIN z USING (campaign_id, keyword_id)) AS keys_differ,
       (SELECT COUNTIF(a.side IS DISTINCT FROM z.side OR a.verdict IS DISTINCT FROM z.verdict
                       OR a.is_candidate IS DISTINCT FROM z.is_candidate)
          FROM a JOIN z USING (campaign_id, keyword_id)) AS rows_differ;
```

**The fix: option (a)** (§1 "The freeze" gives the choice and why (b) was not taken).
`scripts/bigquery/tables/T_PLAN_BUILD_JUDGMENT.sql` created 18:31:02 UTC (job `c13fix_ddl_1791052260`).
`SP_BUILD_NEXT_WEEK_PLAN` v27.171 deployed 18:37:21 UTC (`INFORMATION_SCHEMA.ROUTINES.last_altered`;
job `c13fix_deploy_builder_1791052638`), comment lines stripped: the deployed `routine_definition`
equals the file's `BEGIN … END` (63,105 characters) and its description equals the file's (10,864
characters, opening `v27.171`). After writing the plan partition it writes `T_PLAN_BUILD_JUDGMENT`'s
partition for the same `as_of` from its own `j`, stamped with the night's `built_at`; `builder_version_d`
is `v27.171`. C13 reads that record (the night's `as_of` and `built_at`) and also compares the window
and the calendar state. `config.yaml`: `T_PLAN_BUILD_JUDGMENT` (tables), `SP_BUILD_NEXT_WEEK_PLAN`
(description, the table in its dependencies). The three harnesses swap the record like the plan table
(`--build-judge-table` reads a copy). No real build ran: the 10-03 night stays as written at 16:34:13
UTC by v27.169, with no record.

**Proved on copies of the builder** (no real write). Judgement snapshot `OI._tmp_c13_judge` (18:32 UTC,
window 09-29 … 10-01) and `OI._tmp_c13_judge_old` — the deployed view's text with its Los Angeles
date set to 2026-10-02, the date the 05:00 UTC pass reads (window 09-28 … 09-30; it differs from the
stored 05:36:35 write on 3 of 356 live rows, data restated since) — both in job
`c13fix_snap_1791052309`. Plan copies of `FACT_PLAN_NEXT_WEEK` with the 10-03 night removed; record
copies created `LIKE T_PLAN_BUILD_JUDGMENT`; procedure copies are the file (or HEAD's v27.170 file)
with comment lines stripped and only the procedure, plan table, view and record names swapped. Scratch
tables expire 2026-10-10.

| case | what happened | job, slot-seconds |
|---|---|---|
| v27.171 copy, first write (snapshot) | plan copy: `DELETE` 0, `INSERT` 712, `builder_version` v27.171; record: `DELETE` 0, `INSERT` 356 (356 keys, `as_of` 10-03, `built_at` equal to the night's to the microsecond); the record equals the snapshot's 356 rows on all 8 saved columns both ways | `c13fix_call171_1791052411`, 599.7 |
| v27.170 copy, same snapshot | 712 rows; all columns but `built_at` and `builder_version` equal v27.171's night, 0 differences either way | `c13fix_call170_1791052411`, 445.6; compared in `c13fix_eq_1791052592` |
| v27.171 copy, called again | `FROZEN: partition 2026-10-03 was written at 2026-10-03 18:34:43 UTC; …` at entry; 2 child jobs, no DML; the record unchanged | `c13fix_frozen_1791052603`, 0.09 |
| v27.171 copy on `_tmp_c13_judge_old` (the 05:00 UTC pass's window) | night written on 09-28 … 09-30, record of the same | `c13fix_call171old_1791052411`, 381.9 |
| this file's C13 on that night | **0** (the record) | `c13fix_drift_new_1791052680`, 2,697.2 |
| v27.170's C13 on that night, live view | **44** | `c13fix_drift_old_1791052680`, 2,196.0 |

(Both runs on the 09-28 … 09-30 night also read C01 712 and F1 1: simulation artefacts — its
`built_at` is 11:34 Los Angeles on 10-03, a window fenced for 10-02, and the copy's write is not in
`FACT_PLAN_NEXT_WEEK`'s job record.)

**Checked.** On the live table at 18:40 UTC: 36 rows PASS; C13 1 (no record for the 10-03 night), F1
1 and F2 1 (emptiness) — job `c13fix_acc_live_1791052823`, 2,895.9 slot-seconds, 241,172,480 bytes.
`check_plan_clock_controls.py` on a simulated pass written after the v27.171 deploy (the copy's 10-03
night removed and rewritten at 18:38:55 UTC by the v27.171 copy, job `c13fix_call171b_1791052664`,
585.9 slot-seconds; `--plan-table onyga-482313.OI._tmp_c13_plan --jobs-table-id _tmp_c13_plan
--judge-table onyga-482313.OI._tmp_c13_judge --build-judge-table onyga-482313.OI._tmp_c13_bj`): exit
0, all 25 copies exercised (job `bqjob_r2bf99b8d41e5b9f7_000001a10310eb8f_1`, 10,134.5 slot-seconds,
3,853,516,800 bytes). LIVE 41 readings 0. NC_EMPTY C13 2. NC_C13_VERDICT_MOVED, NC_C13_NOT_SAVED,
NC_C13_OTHER_WRITE (the record stamped one second later), NC_C13_ROW_NOT_SAVED, NC_C13_SIDE_DIFFERS,
NC_C13_CANDIDACY_DIFFERS, NC_C13_WINDOW_DIFFERS, NC_C13_STATE_DIFFERS: C13 1 each, no other check
moved. Every v27.170 copy read as before; C13 also reads 1 on the copies that re-key or restamp the
night or move its window or state, and 356 on NC_K2_REWRITTEN_WHOLE (unasserted).
`check_plan_seat_controls.py` and `check_plan_money_controls.py` (no simulated-pass option; real
table, defaults) after the deploy: each exits 1 by LIVE alone — non-zero exactly C13 1, F1 1, F2 1,
the 10-03 night having been written by v27.169 — and every copy reads its expected value (seat: 52
LIVE readings, 64 assertions, job `bqjob_r28ce46c4ceeae428_000001a10317178d_1`, 8,986.4
slot-seconds; money: 39 LIVE readings, 28 assertions, job `bqjob_r114f15b1e643729a_000001a103173577_1`,
949,116.0 slot-seconds, 2,296,381,440 bytes — the money script's 10-03 11:52 UTC run cost 120,513.8
slot-seconds; the increase was not attributed).

**Not yet measured: C13 on a real night.** The first night v27.171 writes is 10-04, at the 05:00 UTC
pass of 2026-10-04. Re-run the suite after it, at any hour, and the three harnesses with their
defaults: C13, F1 and F2 should read 0 and every LIVE reading 0. The query for C13's record of a
night:

```sql
SELECT as_of, built_at, builder_version, COUNT(*) AS saved_rows,
       MIN(window_from) AS window_from, MAX(window_to) AS window_to
FROM `onyga-482313.OI.T_PLAN_BUILD_JUDGMENT`
GROUP BY 1, 2, 3 ORDER BY as_of DESC;
```

### Task 4 — the ledger, `V_PREDICTION_LEDGER` v27.172 (2026-10-03)

**Deployed.** `scripts/bigquery/views/V_PREDICTION_LEDGER.sql` at 19:49:05 UTC (job
`t4_deploy_view_1791056943`), comment lines stripped: 39 columns. It reads `FACT_PLAN_NEXT_WEEK`,
`FACT_THRESHOLD_HISTORY` and `FACT_KEYWORD_STATE_HISTORY` only. `config.yaml`: `V_PREDICTION_LEDGER`
(views), and the `DE_COACH_THRESHOLDS` entry now says the ledger reads `MATCH_BID_TOL` and
`MATCH_BUDGET_TOL` (for `act_is_noop`). The campaign-budget clause is the recommended form (§3), on
Ori's "all recommended".

**What it reads now.** 17,588 rows: the twelve stored nights' 8,794 plan rows, each twice. Per
night one `rule_version` — PEAK `962467a7…` on 08-23 … 08-28, OFF_PEAK `e8feebb8…` on 09-28 and
09-29, BOOST `005e56fd…` on 09-30 … 10-03, all `:pre-v27.170` (no night has been written by
v27.170 or later yet) — `min_orders` 2 on every row, and one `response_model_version` on every `ACT`
row, the four seed events (`RM1:a97e300d…,3da72b3b…,a1eed604…,eb5b095b…`), because every night was
built before them (job `t4_ver_1791057085`). Six zero-click `OPEN_PROBE` plan rows — one keyword in both plans on 10-02, the same
keyword in plan A on 10-03, and three in plan B on 10-03 — all priced from the pool (`SEAT_PROBE_POOLED`; none of them
has 30 settled clicks of its own); the 10-03 plan-B probes' seat spend sums to $15.84, the brief's
figure. One of them (388620934464557) opens at its own current price, $0.25 → $0.25 — §9's case —
but in a campaign the plan cuts ($75.00 → $72.28), so it has a budget component, is not
`act_is_noop`, and its seat costs $0; no stored night holds an `act_is_noop` probe (L2 reads 0).

**Cost.** `SELECT *` over the view: 4,349,693 bytes processed (31,457,280 billed, the minimum),
106.5 slot-seconds, 3.2 s (job `t4_cost_1791056953`). Most of it is the per-stage overhead of a
plan with ~70 stages over small inputs, not data.

**Reproductions** (each a run of the deployed view or of its own body):

- *The worked examples.* The view's body run on the 10-03 night as written at 13:04:57 UTC (BigQuery
  time travel to 13:10 UTC, `builder_version` supplied as NULL since the column did not exist yet;
  job `t4_tt_ex_1791057063`, 172.7 slot-seconds) gives the brief's numbers exactly: 305171316086021
  `DO_NOTHING` 84 clicks / $75.71 / 4.4554 orders / $56.8067 GP / −$18.9033 net, `ACT` 79.52 /
  $67.8496 / 4.2178 / $53.777 / −$14.0726, seat $72.0843; 439648864838275 `ACT` 19.565 clicks /
  $4.6295, seat $0. The night stored now is the 16:34:13 UTC rewrite, whose `w_gp_corrected` is
  55.1582 for the first keyword (`FACT_AMAZON_ADS` restated `GROSS_PROFIT` at 16:08 UTC in
  between, spec §14.2 E6), so the live view reads `DO_NOTHING` $55.16 / −$20.55 and `ACT` $52.22 /
  −$15.63 there, seat $71.40, with clicks, spend and orders unchanged. Acceptance L3 holds the live
  values; the two nights are frozen.
- *Spec §14 E3*, 09-28 plan B, `ACT` spend by move (job `t4_e3_1791057079`): NONE 3,132.01,
  NONE_HOLDOUT 1,634.38, HOLD_AT_PRICE 0.74, HOLD_AT_PARK 28.25, PARK 42.34, REPRICE 1,470.95 —
  equal to E3's anchored column on every move (no budget factor binds on that night); PAUSE 0
  against $1.86 of window spend.
- *Spec §14 E8, the budget clause* (job `t4_meas_1791057281`): plan B 369 cut campaign-nights, the
  factor binds on 3 and removes $6.17 of horizon spend — E8's recommended-form figures; plan A 369
  cut, 0 bind.

**Checked.** `scripts/bigquery/tests/PREDICTION_CONTRACT_acceptance.sql` (new; Task 7 completes it),
run 19:49:47 UTC as written (`--nosync`, polled; job `t4_acc_1791056985`, 235.9 slot-seconds,
108,751,862 bytes, 22 s): 22 rows, every one PASS. LIVE L1a, L1b, L1c, L1d, L2, L3, L4 0. L2's
population is 1,142 `ACT` rows (`act_is_noop`, campaign budget not cut), 96 of them with window
clicks (job `t4_meas_1791057281`). Controls, each FIRED: NC_EMPTY L1a 8,794, L1b 1, L1c 1, L1d 1, L2 1,
L3 16, L4 1; NC_L1_ONE_SCENARIO L1a 1; NC_L1_NULL_NUMBER L1b 1; NC_L1_NEG_BASIS L1c 1; NC_L1_NO_RULE L1d
1; NC_L2_R_09 (the plan's control: one no-op row with window clicks priced at r = 0.9) L2 1;
NC_L3_SPEND_R1 (example 1's `ACT` spend at r¹) L3 1; NC_L3_SEAT (example 2's `ACT` spend at the seat's
$0) L3 1; NC_L4_DRIFT (the second read: one `pred_net` + 0.01 and one row missing) L4 2.

**Proved on copies: a stored night never moves** (job `t4_immut_1791057132`, 221.1 slot-seconds;
TEMP copies only). The view's body over three TEMP tables: the plan table plus a future night (the
10-03 night re-keyed 10-05, `built_at` 2026-10-05 05:36 UTC); the threshold history plus a
`CHANGED` event moving `CLICK_BID_ELASTICITY` to 1.1 at 2026-10-04 05:10 UTC; the keyword-state
history with the 10-03 snapshot re-captured at 2026-10-04 05:30 UTC (what the 05:00 UTC pass of 10-04
does). Against the deployed view: 0 of the 17,588 stored rows differ in any predicted number,
`response_model_version`, `rule_version` or `act_basis`; the future night's 330 anchored `ACT` rows
are priced at ε = 1.1 (0 not), under a version no stored row carries. Negative control, the same
event dated 2026-10-03 16:00 UTC (before the 10-03 night's write, and before the first recorded
event, so the earliest event of the key and the one every stored night takes): 8,794 stored rows
differ. A pass cannot stamp an event earlier than one already recorded, so the control's case cannot
arise from the snapshot; it shows the comparison sees a repricing.

**The snapshot rule, measured** (job `t4_snapcmp_1791057175`): the 10-03 night's Fresh plan keywords
pooled from the 10-02 copy (captured 2026-10-03 05:34:01 UTC) and from the 10-03 copy (16:31:47 UTC):
CVR equal (SB 0.023764, SP 0.03613), GP per order SB 18.9507 / 18.9106 and SP 19.7348 / 19.6967. Under
the brief's "latest copy captured by `built_at`" the night would read the 10-03 copy until the 05:00
UTC pass of 10-04 re-captured it, then the 10-02 copy; under the rule built it reads 10-02 throughout.

```sql
-- the ledger by night and scenario
SELECT as_of, scenario, COUNT(*) AS n, ANY_VALUE(rule_version) AS rule_version,
       COUNT(DISTINCT response_model_version) AS n_rm, ROUND(SUM(pred_spend), 2) AS pred_spend,
       ROUND(SUM(pred_net), 2) AS pred_net, ROUND(SUM(alloc_spend), 2) AS alloc_spend,
       COUNTIF(act_budget_factor < 1) AS budget_binds, MIN(horizon_from) AS horizon_from,
       MAX(horizon_to) AS horizon_to
FROM `onyga-482313.OI.V_PREDICTION_LEDGER`
GROUP BY as_of, scenario ORDER BY as_of, scenario;
```

### Task 5 — the grader, its grades and its report card (2026-10-03)

**Deployed** (comment lines stripped): `scripts/bigquery/tables/FACT_PREDICTION_GRADE.sql` at
20:41:45 UTC (job `t5_deploy_grade_1791060103`; 60 columns, partitioned by `as_of`, clustered by
`predictor, family`; its description re-set from the file at 20:55:37 UTC after one wording fix, job `bqjob_r3f484614c664b2cb_000001a1038d0a49_1`, no
row touched), `scripts/bigquery/tables/T_PREDICTION_SCORECARD.sql` at 20:41:47 UTC
(`t5_deploy_sc_1791060103`; 74 columns), `scripts/bigquery/procedures/SP_GRADE_PREDICTIONS.sql`
v27.173 at 20:41:50 UTC (`t5_deploy_sp_1791060103`; `INFORMATION_SCHEMA.ROUTINES` created and
last_altered 20:41:50): the deployed `routine_definition` equals the file's `BEGIN … END`, 42,360
characters. `config.yaml`: `FACT_PREDICTION_GRADE` and `T_PREDICTION_SCORECARD` (tables),
`SP_GRADE_PREDICTIONS` (stored procedures, `schedule: "daily"`). Not on the schedule yet: Task 6
adds the orchestrator step.

**The first run** — `CALL SP_GRADE_PREDICTIONS(NULL, NULL)`, job `t5_call1_1791060200`, 20:42:19 to
20:43:23 UTC, 170.5 slot-seconds, 116,692,386 bytes processed (660,602,880 billed: the run is ~40
small statements). Log: watermark 2026-10-02 (`FN_ADS_ANCHOR_CAP` 2026-10-02), SETTLE_HORIZON_DAYS
14; 8,944 ledger rows due — the six August nights, 4,472 plan rows, both scenarios — 8,944 inserted,
all `regrade_seq` 0; labels RIGHT 0, WRONG 0, INCONCLUSIVE 8,944, UNGRADABLE 0; per plan, 2,073
plan rows applied as DO_NOTHING (219 of them `act_is_noop`), 163 OTHER_ACTION, 0 ACT. Nothing after
August: the report card's YOUNG row reads "2236 of 4397 predictions graded; 2161 wait, the next
gradable when the ads watermark reaches 2026-10-17" for each plan (the 09-30 night, horizon end
10-03, spec E1). `T_PREDICTION_SCORECARD`: 357 rows — ACCURACY 90, CURVE 168, HONESTY 30, LINE 24,
MONEY 30, NEXT_WEEK 5, YOUNG 10; §8's query runs on it and §5's column names are its own.
**The second run** (`t5_call2_1791060224`, 20:43:46 UTC, 157.4 slot-seconds): 0 due, 0 inserted;
the table still holds 8,944 rows from one `graded_at`.

**Checked.** `scripts/bigquery/tests/PREDICTION_GRADE_acceptance.sql` (new), run as written
20:51:49 UTC (`t5_acc_1791060707`, 139.8 slot-seconds, 159,024,712 bytes): 27 rows, every asserted
row PASS; LIVE V1–V8 0, V2g (gross profit restated since grading) REPORT 0; every control FIRED —
NC_EMPTY V1 8,944 and V2–V8 1 each, NC_V1_MISSING 1, NC_V2_REAL 1, NC_V3_FROZEN 1, NC_V4_LABEL 1,
NC_V5_SIDE 1, NC_V6_APPLIED 1, NC_V7_FALSE_UNGRADABLE 1, NC_V7_MISSED_ARCHIVE 24, NC_V8_CURVE 1,
NC_V8_ACC 1 (the file's RUN LOG). The card's columns against the DDL file's (S, below): the real
card 0; controls NC_S_TYPE 1, NC_S_DROPPED 1, NC_EMPTY 75.

**Proved on copies of the grader** (no real write beyond the two runs above). A copy is the file
with its comment lines stripped and only the procedure, `FACT_PREDICTION_GRADE` and
`T_PREDICTION_SCORECARD` names swapped (and, for the lowered bar, `DE_COACH_THRESHOLDS`). Scratch
tables `OI._tmp_t5_grade`, `_tmp_t5_grade_nc`, `_tmp_t5_grade_rg`, `_tmp_t5_grade_pc`,
`_tmp_t5_sc`, `_tmp_t5_sc_nc`, `_tmp_t5_sc_rg`, `_tmp_t5_sc_pc`, `_tmp_t5_thr`, `_tmp_t5_sc_ddl`
expire 2026-10-10 (the other `_tmp_t5_*` tables in `OI` are another session's); the procedure copies
were dropped after the runs.

| case | what happened | job, slot-seconds |
|---|---|---|
| first run on an empty copy | 8,944 inserted, the same counts as the real run | `t5_copy_run2_1791059529`, 152.5 |
| second run on it | 0 due, 0 inserted | `t5_copyA_1791059825`, 188.6 |
| **NC, idempotence**: a copy with one grade row deleted | the next run inserted exactly that row (1), equal to the deleted one in every column but `graded_at` | `t5_ncB_1791059825`, 160.9 |
| **re-grade** `(DATE '2026-08-26', 'Task 5 re-grade test on a copy')` | 4,476 rows appended — every current grade of the nights 08-26 … 08-28 — `regrade_seq` 1, the reason on each; band check R 0: every key of the band has one row at 0 and one at 1, none outside the band has one at 1, the reason on every 1 and on no 0. Controls: NC_R_OUTSIDE (a seq-1 row on 08-25) 1, NC_R_LOST (one seq-1 row removed) 1, NC_R_NOREASON 1, NC_EMPTY 1. A `(NULL, NULL)` run after it: 0 inserted | `t5_rgC_1791059825`, 166.6; `t5_rgF_1791059990`, 176.8 |
| re-grade without a reason `(DATE '2026-08-26', NULL)` | refused by the first ASSERT, nothing written | `t5_copyE_1791059825`, 0.0 |
| **the label path**, `MIN_INVEST_SIDE_ACCURACY` 0.30 on a settings copy | a line on 7 of 8 plan × family groups (each at 1 click; PLAN_A Fresh none); 1,428 RIGHT, 2,078 WRONG, 5,438 INCONCLUSIVE; no INCONCLUSIVE row at or above its line with a click. V1–V7 0, every control firing (`t5_verify_pc_1791059990`, 111.0). P: the line stored on every row = the card's SINCE_START LINE = an independent recompute, 0; controls NC_P_CARD 1, NC_P_ROW 1, NC_EMPTY 2 | `t5_pcD_1791059825`, 159.3 |

**The August numbers beside the brief's preview** (plan Task 5 Step 8; job
`t5_compare_1791060224`, the query below). Three readings of spec §14.3 Q5's test: OLD is Q5 as
written run now (horizon `as_of …`), SHIFT the same on the ledger's horizon (`as_of + 1 …`, D2 —
every August night was written after Los Angeles midnight of its `as_of`), GRADER the grade
table's current DO_NOTHING rows. **GRADER equals SHIFT on every bucket and every total**, and OLD
equals spec §14.2 E6's 16:10 UTC run on every bucket, so the differences from the brief are the
horizon shift and the gross-profit restatement E6 records — nothing else.

Spend-weighted side accuracy by realised-click bucket, plan B (brief / E6 at 16:10 UTC / OLD now /
GRADER):

| bucket | 1–5 | 6–10 | 11–20 | 21–40 | 41–80 | 81+ |
|---|---|---|---|---|---|---|
| brief | 0.549 | 0.325 | 0.407 | 0.479 | 0.357 | 0.317 |
| E6, OLD now | 0.549 | 0.325 | 0.407 | 0.466 | 0.357 | 0.317 |
| GRADER (rows) | 0.532 (319) | 0.288 (145) | 0.407 (191) | 0.447 (144) | 0.380 (104) | 0.259 (91) |

Plan A's best bucket: brief 0.495, E6 0.481 (21–40), GRADER 0.499 (21–40). Bucket 0: 1,242 rows per
plan (OLD 1,235), 92 of them with window clicks (OLD 92) — `n_predicted_but_zero_clicks`.
**The absent line:** no family has one in either plan. The best floor with at least 20 rows
(the card's LINE sentences): PLAN_A Bottle 0.741 at 6+ clicks (26 rows), Fresh 0.276 at 11+, LolliME
0.345 at 11+, Lollibox 0.378 at 41+; PLAN_B Bottle 0.690 at 1+ (50 rows), Fresh 0.310 at 1+, LolliME
0.301 at 1+, Lollibox 0.409 at 41+ (E6 on the old horizon: 0.658, Bottle plan A, 6+, 25 rows).
**DO_NOTHING totals**, plan B, keys with a realised FACT row (the brief's `dn_totals.sql`):

| | keys | clicks pred / real | spend pred / real | orders pred (corrected) / real | gross profit pred / real | net pred / real |
|---|---|---|---|---|---|---|
| brief | — | 31,641 / 29,694 | 20,118 / 19,144 | 1,150 / 1,002 | 17,434 / 14,727 | −2,684 / −4,417 |
| OLD now | 1,001 | 31,641 / 29,694 | 20,118.23 / 19,144.00 | 1,150.3 / 1,002 | 17,434.27 / 14,501.83 | −2,683.96 / −4,642.17 |
| GRADER | 994 | 31,248 / 29,490 | 19,956.90 / 19,063.22 | 1,148.8 / 963 | 17,410.81 / 14,137.39 | −2,546.09 / −4,925.83 |

The brief's realised gross profit and net are the pre-16:08 UTC reading (E6). Over every plan row
(the card's ACCURACY DO_NOTHING, ALL) the DO_NOTHING forecast's `mae_net_share` is 0.916 and its
`bias_share` 0.106 in both plans; `counterfactual_net_per_alloc` (MONEY, ALL) PLAN_A −0.187, PLAN_B
−0.168.
**Which scenario applied.** The brief expected 1 ACT (a plan-B PARK), 91–92 rows with another change
on the keyword and 98 with a campaign-level change. Measured: 92 (A) / 91 (B) and 98, and 0 ACT —
the PARK row (2026-08-25, keyword 445052966395752, bid 0.41 → 0.20) matched its bid change but its
campaign's budget component (62.50 → 60.04) did not land, so under the plan's rule (every component
matched) it is OTHER_ACTION, with the matched change in `matched_change_ids`. *Re-graded 2026-10-04
(Task 5 follow-up, below): on the ruled clock (`built_at` … `horizon_to`) 64 of the 163
OTHER_ACTION rows per plan are DO_NOTHING; this row stays OTHER_ACTION.*

**`placement_changed`, measured** (per plan, over the 2,236 August plan rows): 126 have no reading,
2,048 moved beyond 1e-6, 311 by more than 1%, 17 by more than 5%. §9 says why the flag reads so
high; whether a move of some size should count is open (a LEARNING setting would need a ruling).

**Tonight's NEXT_WEEK** (the 10-03 night, plan B live): ALL "do nothing $191.01; upload the plan
$346.77" over 10-04 … 10-06; Bottle −$41.27 / −$40.03, Fresh −$125.16 / $1.34, LolliME $153.33 /
$181.82, Lollibox $204.11 / $203.64.

```sql
-- Step 8: OLD (Q5 as written), SHIFT (Q5 on as_of + 1 ..) and GRADER, per plan and bucket; then the
-- DO_NOTHING totals of plan B over keys with a realised FACT row (submit --nosync, poll)
CREATE TEMP TABLE p AS
SELECT as_of, plan, family, channel, campaign_id, keyword_id, window_days, side, family_bar,
       w_clk, w_ord, w_sp, w_gp_corrected, settle_factor_eff
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of BETWEEN '2026-08-23' AND '2026-08-28';
CREATE TEMP TABLE k AS
WITH r AS (
  SELECT p.as_of, p.plan, p.keyword_id, shift,
         SUM(f.Ads_clicks) clk, SUM(f.Ads_cost) sp, SUM(f.Ads_orders) ord, SUM(f.GROSS_PROFIT) gp, COUNT(*) n_fact
  FROM p CROSS JOIN UNNEST([0, 1]) AS shift
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` f
    ON f.campaign_id = p.campaign_id AND f.keyword_id = p.keyword_id
   AND f.date BETWEEN DATE_ADD(p.as_of, INTERVAL shift DAY) AND DATE_ADD(p.as_of, INTERVAL p.window_days - 1 + shift DAY)
  GROUP BY 1, 2, 3, 4
)
SELECT IF(sh = 0, 'OLD', 'SHIFT') AS form, p.*, COALESCE(r.clk, 0) clk, COALESCE(r.sp, 0) sp,
       COALESCE(r.ord, 0) ord, COALESCE(r.gp, 0) gp, (r.n_fact IS NOT NULL) AS has_row
FROM p CROSS JOIN UNNEST([0, 1]) AS sh
LEFT JOIN r ON r.as_of = p.as_of AND r.plan = p.plan AND r.keyword_id = p.keyword_id AND r.shift = sh;
CREATE TEMP TABLE kk AS
SELECT form, plan, family, clk, sp, w_clk,
       (side = 'GOOD') = (ord >= 2 AND SAFE_DIVIDE(gp, NULLIF(sp, 0)) >= family_bar) AS correct,
       CASE WHEN clk = 0 THEN '0' WHEN clk <= 5 THEN '1-5' WHEN clk <= 10 THEN '6-10' WHEN clk <= 20 THEN '11-20'
            WHEN clk <= 40 THEN '21-40' WHEN clk <= 80 THEN '41-80' ELSE '81+' END AS bkt
FROM k
UNION ALL
SELECT 'GRADER', REGEXP_EXTRACT(predictor, r'PLAN_(.)'), family, real_clicks, real_spend, basis_clicks, side_correct, click_bucket
FROM `onyga-482313.OI.FACT_PREDICTION_GRADE`
WHERE scenario = 'DO_NOTHING' AND as_of BETWEEN '2026-08-23' AND '2026-08-28'
QUALIFY ROW_NUMBER() OVER (PARTITION BY predictor, as_of, campaign_id, keyword_id ORDER BY regrade_seq DESC) = 1;
SELECT plan, bkt, form, COUNT(*) n, COUNTIF(w_clk > 0) had_window_clicks, ROUND(SUM(sp), 2) real_sp,
       ROUND(SAFE_DIVIDE(SUM(IF(correct, sp, 0)), SUM(sp)), 3) side_acc_spend
FROM kk GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;
SELECT form, COUNT(*) keys, ROUND(SUM(w_clk)) pred_clk, SUM(clk) real_clk, ROUND(SUM(w_sp), 2) pred_sp, ROUND(SUM(sp), 2) real_sp,
       ROUND(SUM(w_ord / settle_factor_eff), 1) pred_ord_corr, SUM(ord) real_ord,
       ROUND(SUM(w_gp_corrected), 2) pred_gp, ROUND(SUM(gp), 2) real_gp,
       ROUND(SUM(w_gp_corrected - w_sp), 2) pred_net, ROUND(SUM(gp - sp), 2) real_net
FROM k WHERE plan = 'B' AND has_row GROUP BY 1
UNION ALL
SELECT 'GRADER', COUNT(*), ROUND(SUM(g.pred_clicks)), SUM(g.real_clicks), ROUND(SUM(g.pred_spend), 2), ROUND(SUM(g.real_spend), 2),
       ROUND(SUM(g.pred_orders), 1), SUM(g.real_orders), ROUND(SUM(g.pred_gp), 2), ROUND(SUM(g.real_gp), 2),
       ROUND(SUM(g.pred_net), 2), ROUND(SUM(g.real_net), 2)
FROM `onyga-482313.OI.FACT_PREDICTION_GRADE` g
JOIN k ON k.form = 'SHIFT' AND k.plan = 'B' AND k.has_row AND k.as_of = g.as_of AND k.keyword_id = g.keyword_id
WHERE g.predictor = 'PLAN_B' AND g.scenario = 'DO_NOTHING'
ORDER BY 1;
```

```sql
-- S: the card the procedure builds has its DDL file's columns, names, types and order. Create the DDL
-- file's table under another name (e.g. OI._tmp_t5_sc_ddl), then compare; NC_S_TYPE / NC_S_DROPPED
-- doctor the DDL side
CREATE TEMP TABLE b AS SELECT column_name, data_type, ordinal_position
  FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS` WHERE table_name = 'T_PREDICTION_SCORECARD';
CREATE TEMP TABLE d AS SELECT column_name, data_type, ordinal_position
  FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS` WHERE table_name = '_tmp_t5_sc_ddl';
CREATE TEMP TABLE dc AS
SELECT 'LIVE' AS copy, * FROM d
UNION ALL SELECT 'NC_S_TYPE', * REPLACE (IF(column_name = 'min_clicks', 'FLOAT64', data_type) AS data_type) FROM d
UNION ALL SELECT 'NC_S_DROPPED', * FROM d WHERE column_name <> 'detail';
WITH copies AS (SELECT x AS copy FROM UNNEST(['LIVE', 'NC_S_TYPE', 'NC_S_DROPPED', 'NC_EMPTY']) x),
j AS (
  SELECT x.copy, COUNTIF(dd.column_name IS NULL OR bb.column_name IS NULL
                         OR dd.data_type <> bb.data_type OR dd.ordinal_position <> bb.ordinal_position) AS n,
         COUNT(dd.column_name) AS n_ddl
  FROM copies x CROSS JOIN b bb
  FULL OUTER JOIN dc dd ON dd.copy = x.copy AND dd.column_name = bb.column_name
  GROUP BY x.copy
)
SELECT x.copy, COALESCE(j.n, 0) + IF(COALESCE(j.n_ddl, 0) = 0, 1, 0) AS violations
FROM copies x LEFT JOIN j ON j.copy = x.copy ORDER BY x.copy;
```

```sql
-- placement_changed, measured
SELECT predictor, COUNT(*) AS plan_rows, COUNTIF(placement_changed IS NULL) AS no_reading,
       COUNTIF(placement_changed) AS moved,
       COUNTIF(ABS(SAFE_DIVIDE(placement_m_to, placement_m_from) - 1) > 0.01) AS moved_gt_1pct,
       COUNTIF(ABS(SAFE_DIVIDE(placement_m_to, placement_m_from) - 1) > 0.05) AS moved_gt_5pct
FROM `onyga-482313.OI.FACT_PREDICTION_GRADE`
WHERE scenario = 'DO_NOTHING'
GROUP BY predictor ORDER BY predictor;
```

### Task 5 follow-up — the applied scenario on the prediction's own clock (2026-10-04)

**The finding** (Task-5 review): `_chg` / `hits` read changes on the Los Angeles dates `as_of … as_of +
MATCH_WINDOW_DAYS`, not on the prediction's clock `built_at … horizon_to` (§4 step 4 says why each
of the three errors follows). **Ruled 2026-10-04, "all recommended":** a change can match a component
when it is applied at or after `built_at` and before the Los Angeles midnight that starts
`horizon_from + MATCH_WINDOW_DAYS`; the "any other change" scan reads from `built_at` to the end of
`horizon_to`; the SB sync lag is handled as §4 states (an SB keyword's own changes one day longer).
The grader adds one bound the ruling did not name: the match window never runs past the end of
`horizon_to` (no stored night has `window_days` below `MATCH_WINDOW_DAYS`: 3 and 7 are the only
values, so it changes nothing today).

**Measured on the frozen v27.173 grades before the fix** (query 1 below, run before the re-grade;
the reviewer's numbers reproduced): 163 `OTHER_ACTION` plan rows per plan; 64 with every change
applied before `built_at`; 60 of those with every change's new bid or budget equal to the row's
`current_bid` / `campaign_current_budget`. Bid hits before the build 59, 57 of them already the
current bid; budget hits 40, all 40 already the current budget (each plan). The other four rows per
plan: two on the 08-25 night whose campaign or keyword was paused before the build
(`CAMPAIGN_PAUSE` 05:17:10 and `KEYWORD_PAUSE` 05:18:20 UTC on 08-26; built 05:58:01 UTC), and two on
the 08-26 night whose bid went 0.90 → 0.30 / 0.34 at 12:10 UTC and back to 0.90 at 16:01 UTC on 08-26
(built 05:44:35 UTC on 08-27). Under the ruling all 64 are `DO_NOTHING`: nothing was done after the
build. Error (b) — a change between the build and Los Angeles midnight of a New York-keyed night —
cannot be seen in the data (Ori made no change after 2026-09-27: the plan's rulings, "Also
recorded"); it is shown on a fixture below.

**Deployed** `scripts/bigquery/procedures/SP_GRADE_PREDICTIONS.sql` v27.174 (comment lines
stripped) at 21:29:52 UTC 2026-10-03 (job `t5f_deploy_sp_1791062988`): `INFORMATION_SCHEMA.ROUTINES`
`routine_definition` equals the file's `BEGIN … END`, 42,973 characters; the routine's description
(1,916 characters) and arguments (`regrade_from DATE`, `reason STRING`) equal the file's. Changed:
`_prow` carries `built_at` and `channel`; `_chg` reads `applied_at` from the earliest `built_at` to the
Los Angeles midnight that ends the latest `horizon_to + 1`; `_app` reads the windows above; a due row
with no `built_at` is refused (ASSERT); `grader_version` v27.174. `config.yaml`'s description of the
procedure says the same.

**Proved on copies of the grader** (the file with its comment lines stripped and only the procedure,
`FACT_PREDICTION_GRADE`, `T_PREDICTION_SCORECARD`, `V_PREDICTION_LEDGER` and `V_PPC_CHANGE_LOG_LANDED`
names swapped). Inputs (query 2, job `t5fx_fixtures_1791062610`, 119.6 slot-seconds): `OI._tmp_t5fx_chg`
= the view's 2,016 rows + six injected keyword changes; `OI._tmp_t5fx_led` = the ledger's 17,588 rows
with three plan keys doctored (12 rows). v27.174 and v27.173 (commit d49e7a5) each graded the copy
from empty (`t5fx_runnew_1791062660`, 96.3 slot-seconds; `t5fx_runold_1791062660`, 95.2): 8,944 rows
each. Per plan row, both plans alike (query 3):

| fixture | night, horizon | change injected | v27.174 | v27.173 |
|---|---|---|---|---|
| F1 pre-build, in the baseline | 08-23, 08-24 … 08-26 (SP, built 05:34:19 UTC 08-24) | bid 0.25 = current, 04:34:19 UTC | DO_NOTHING | OTHER_ACTION |
| F2 day 5 of 7 | 08-28, stretched to 08-29 … 09-04 (SP) | bid 0.62, noon LA 09-02 | OTHER_ACTION | DO_NOTHING |
| F3 build evening, New York keying | 08-24 moved to built 05:30 UTC 08-24 (LA 08-23 22:30), 08-24 … 08-26 (SP, plan 0.25 → 0.21, no budget component) | bid 0.21, 05:45 UTC 08-24 | ACT | DO_NOTHING |
| F3, the night before | 08-23, built 05:34:19 UTC 08-24 | the same change, after that build | ACT | ACT |
| F4 matching bid on day 5 | 08-28, stretched to 08-29 … 09-04 (SP, plan B bid 1.16) | bid 1.16, noon LA 09-02 | OTHER_ACTION | DO_NOTHING |
| F5 SB, the day after the horizon | 08-28, 08-29 … 08-31 (SB) | bid 0.31, 10:00 LA 09-01 | OTHER_ACTION | DO_NOTHING |
| F5 SP, the day after the horizon | 08-28, 08-29 … 08-31 (SP) | bid 1.07, 10:00 LA 09-01 | DO_NOTHING | DO_NOTHING |

Every other plan row of the copy (2,200 per plan) against the live v27.173 grade: 2,037 DO_NOTHING
both, 64 OTHER_ACTION → DO_NOTHING, 99 OTHER_ACTION both, nothing else. The acceptance suite with V9
on each copy (names swapped the same way): v27.174's grades every asserted row PASS
(`t5fx_acc_new_1791062874`, 85.0 slot-seconds); v27.173's V9 LIVE FAIL 388 (`t5fx_acc_old_1791062874`,
107.8): the 368 rows the live re-grade moved (below) and the 20 rows of the five fixtures the two
rules label differently. Scratch tables `OI._tmp_t5fx_chg`, `_tmp_t5fx_led`, `_tmp_t5fx_grade_new`,
`_tmp_t5fx_grade_old`, `_tmp_t5fx_sc_new`, `_tmp_t5fx_sc_old` expire 2026-10-11; the two procedure
copies were dropped.

**The re-grade** — `CALL SP_GRADE_PREDICTIONS(DATE '2026-08-23', 'v27.174 Task 5 follow-up: …')`,
job `t5f_regrade_1791063086`, 21:31:28 to 21:32:36 UTC, 165.6 slot-seconds, 129,017,601 bytes
(673,185,792 billed): 8,944 due, 8,944 appended at `regrade_seq` 1 with the reason, `grader_version`
v27.174; labels INCONCLUSIVE 8,944; applied ACT 0, DO_NOTHING 4,274, OTHER_ACTION 198. Seq 0 against
seq 1 (query 4), per plan: 2,073 DO_NOTHING both; **64 OTHER_ACTION → DO_NOTHING**; 99 OTHER_ACTION
both, 28 of them with 31 change ids dropped from their lists, every one applied before `built_at`, none
added; realised numbers, gross profit, `placement_changed` and labels unchanged on every row. A
`(NULL, NULL)` run after it (`t5f_call_null_1791063180`, 186.5 slot-seconds): 0 due, 0 inserted. The
table holds 17,888 rows, two `graded_at`.

**Before and after** (the report card, `family` ALL, SINCE_START; query 5), per plan:

| | before (v27.173) | after (v27.174) |
|---|---|---|
| APPLIED rows (DO_NOTHING-applied; ACT 0) | 2,073 | 2,137 |
| OTHER_ACTION rows (HONESTY `n_other_action`) | 163 | 99 |
| ACT with no matching action (HONESTY) | 1,854 | 1,916 |
| ACCURACY APPLIED realised spend | 14,471.52 | 15,514.60 |
| ACCURACY APPLIED `mae_net_share` / `bias_share` | 0.9325 / 0.1685 | 0.9430 / 0.1305 |
| ACCURACY APPLIED `side_accuracy`, A / B | 0.3554 / 0.3559 | 0.3557 / 0.3612 |
| MONEY `dn_net_per_dollar` | −0.2537 | −0.2468 |
| MONEY `counterfactual_net_per_alloc`, A / B | −0.1874 / −0.1678 | −0.1874 / −0.1678 (every plan row; unchanged) |

ACCURACY DO_NOTHING and ACT (every plan row, applied or not), YOUNG and NEXT_WEEK are unchanged.

**Checked.** `scripts/bigquery/tests/PREDICTION_GRADE_acceptance.sql` gains V9 — the applied scenario
and both id lists recomputed from `V_PPC_CHANGE_LOG_LANDED` on the ruled clock — with PC_V9_PREBUILD /
NC_V9_PREBUILD (a change to the bid the row already had, one hour before `built_at`: the row stays
`DO_NOTHING`; labelled `OTHER_ACTION` for it, V9 fires) and PC_V9_DAY5 / NC_V9_DAY5 (a change on day 5
of the row's horizon stretched to 7 days: the row is `OTHER_ACTION`; left `DO_NOTHING`, V9 fires).
Run as written before the re-grade (`t5f_acc_pre_1791063005`, 195.3 slot-seconds): V1–V8 and their
controls as in "Task 5"; V9 LIVE FAIL 368 = 92 plan rows per plan × 2 plans × 2 scenarios (the 64
relabelled and the 28 whose id lists moved). After it (`t5f_acc_post_1791063180`, 201.8
slot-seconds, 192,112,052 bytes): 33 rows, every asserted row PASS — LIVE V1–V9 0, V2g REPORT 0;
NC_EMPTY V1 8,944 and V2–V9 1 each; the V1–V8 controls as before; NC_V9_PREBUILD 4, NC_V9_DAY5 4;
PC_V9_PREBUILD 0, PC_V9_DAY5 0 (the file's RUN LOG names the picks).

**Not changed.** The `MATCH_WINDOW_DAYS` row of `DE_COACH_THRESHOLDS` still describes the v27.173
window ("Los Angeles dates as_of .. as_of + this"); correcting it is an UPDATE of a `DE_` row, which
the house rules leave to Ori. Its value, 3, is read as before.

```sql
-- 1. the v27.173 OTHER_ACTION rows whose every change was applied before built_at, and whether each
--    such change's new value already equals the row's current bid / budget (run before the re-grade)
CREATE TEMP TABLE r AS
SELECT g.predictor, g.as_of, g.campaign_id, g.keyword_id, g.built_at, g.current_bid, g.campaign_current_budget,
       g.planned_bid, g.campaign_planned_budget, g.move, g.channel, id, x.action, x.applied_at, x.new_bid, x.new_budget, x.landed_evidence,
       x.keyword_id AS x_kw
FROM `onyga-482313.OI.FACT_PREDICTION_GRADE` g,
     UNNEST(ARRAY_CONCAT(g.matched_change_ids, g.other_change_ids)) id
JOIN `onyga-482313.OI.V_PPC_CHANGE_LOG_LANDED` x ON x.change_id = id
WHERE g.scenario = 'DO_NOTHING' AND g.applied_scenario = 'OTHER_ACTION' AND g.regrade_seq = 0;
SELECT predictor,
       COUNT(DISTINCT FORMAT('%t|%s', as_of, keyword_id)) rows_other,
       COUNT(DISTINCT IF(all_pre, FORMAT('%t|%s', as_of, keyword_id), NULL)) rows_all_pre,
       COUNT(DISTINCT IF(all_pre AND all_base, FORMAT('%t|%s', as_of, keyword_id), NULL)) rows_all_pre_in_base,
       COUNTIF(pre AND x_kw IS NOT NULL AND new_bid IS NOT NULL) pre_bid_hits,
       COUNTIF(pre AND x_kw IS NOT NULL AND new_bid IS NOT NULL AND ABS(new_bid - current_bid) <= 0.005 + 1e-9) pre_bid_in_base,
       COUNTIF(pre AND x_kw IS NULL AND new_budget IS NOT NULL) pre_budget_hits,
       COUNTIF(pre AND x_kw IS NULL AND new_budget IS NOT NULL AND ABS(new_budget - campaign_current_budget) <= 0.01 + 1e-9) pre_budget_in_base
FROM (
  SELECT r.*, applied_at < built_at AS pre,
         LOGICAL_AND(applied_at < built_at) OVER k AS all_pre,
         LOGICAL_AND(COALESCE(IF(x_kw IS NOT NULL, ABS(new_bid - current_bid) <= 0.005 + 1e-9,
                                 ABS(new_budget - campaign_current_budget) <= 0.01 + 1e-9), FALSE)) OVER k AS all_base
  FROM r WINDOW k AS (PARTITION BY predictor, as_of, keyword_id)
)
GROUP BY predictor ORDER BY predictor;
```

```sql
-- 2. the fixture inputs
CREATE OR REPLACE TABLE `onyga-482313.OI._tmp_t5fx_chg`
OPTIONS (expiration_timestamp = TIMESTAMP '2026-10-11 00:00:00 UTC') AS
WITH tpl AS (
  SELECT * FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_LANDED`
  WHERE landed_evidence = 'SEEN_ON_AMAZON_NOT_LOGGED' AND keyword_id IS NOT NULL AND new_bid IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (ORDER BY change_id) = 1
),
inj AS (
  SELECT * FROM UNNEST([
    -- F1: night 08-23 (built 2026-08-24 05:34:19 UTC), SP keyword, a change one hour before the build to the bid it already had
    STRUCT('fx|F1_PREBUILD_IN_BASELINE' AS change_id, '108301382467865' AS keyword_id, '531456687555062' AS campaign_id,
           0.25 AS new_bid, TIMESTAMP '2026-08-24 04:34:19 UTC' AS applied_at),
    -- F2: night 08-28 stretched to 7 days (08-29 .. 09-04), SP keyword, a non-matching change at noon LA on day 5 (09-02)
    ('fx|F2_DAY5_OF_7', '11084263298679', '531456687555062', 0.62, TIMESTAMP('2026-09-02 12:00:00', 'America/Los_Angeles')),
    -- F3: night 08-24 moved to a build at 2026-08-24 05:30 UTC (LA 08-23 22:30), horizon 08-24 .. 08-26; the plan's bid (0.21) 15 minutes after
    ('fx|F3_BUILD_EVENING_MATCH', '66007207046728', '222497123677300', 0.21, TIMESTAMP '2026-08-24 05:45:00 UTC'),
    -- F4: night 08-28 stretched to 7 days, SP keyword whose plan B bid is 1.16; that bid set at noon LA on day 5 (09-02)
    ('fx|F4_DAY5_MATCHING_BID', '112492877088507', '43890791772293', 1.16, TIMESTAMP('2026-09-02 12:00:00', 'America/Los_Angeles')),
    -- F5_SB / F5_SP: night 08-28 (horizon 08-29 .. 08-31), a change seen at 10:00 LA on horizon_to + 1 (09-01)
    ('fx|F5_SB_DAY_AFTER', '145785644018633', '446868628489343', 0.31, TIMESTAMP('2026-09-01 10:00:00', 'America/Los_Angeles')),
    ('fx|F5_SP_DAY_AFTER', '117765426526312', '2626284884970', 1.07, TIMESTAMP('2026-09-01 10:00:00', 'America/Los_Angeles'))
  ])
)
SELECT * FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_LANDED`
UNION ALL
SELECT t.* REPLACE (i.change_id AS change_id, i.keyword_id AS keyword_id, i.campaign_id AS campaign_id,
                    i.new_bid AS new_bid, i.applied_at AS applied_at, 'DECREASE_BID' AS action,
                    CAST(NULL AS FLOAT64) AS new_budget, CAST(NULL AS FLOAT64) AS old_budget,
                    'Task 5 follow-up fixture' AS upload_note, CAST(NULL AS STRING) AS paired_change_id)
FROM tpl t CROSS JOIN inj i;

CREATE OR REPLACE TABLE `onyga-482313.OI._tmp_t5fx_led`
OPTIONS (expiration_timestamp = TIMESTAMP '2026-10-11 00:00:00 UTC') AS
SELECT l.* REPLACE (
  CASE WHEN l.as_of = '2026-08-28' AND l.keyword_id IN ('11084263298679', '112492877088507') THEN DATE_ADD(l.horizon_from, INTERVAL 6 DAY)
       WHEN l.as_of = '2026-08-24' AND l.keyword_id = '66007207046728' THEN DATE '2026-08-26'
       ELSE l.horizon_to END AS horizon_to,
  CASE WHEN l.as_of = '2026-08-24' AND l.keyword_id = '66007207046728' THEN DATE '2026-08-24' ELSE l.horizon_from END AS horizon_from,
  CASE WHEN l.as_of = '2026-08-24' AND l.keyword_id = '66007207046728' THEN TIMESTAMP '2026-08-24 05:30:00 UTC' ELSE l.built_at END AS built_at,
  CASE WHEN l.as_of = '2026-08-28' AND l.keyword_id IN ('11084263298679', '112492877088507') THEN 7 ELSE l.window_days END AS window_days)
FROM `onyga-482313.OI.V_PREDICTION_LEDGER` l;

SELECT 'chg' AS t, COUNT(*) AS n, COUNTIF(STARTS_WITH(change_id, 'fx|')) AS fx FROM `onyga-482313.OI._tmp_t5fx_chg`
UNION ALL
SELECT 'led', COUNT(*), COUNTIF((as_of = '2026-08-28' AND keyword_id IN ('11084263298679', '112492877088507'))
                                OR (as_of = '2026-08-24' AND keyword_id = '66007207046728')) FROM `onyga-482313.OI._tmp_t5fx_led`;
```

```sql
-- 3. v27.174 against v27.173 on the copy: the fixture keys, then every other plan row against the live seq 0
CREATE TEMP TABLE n AS SELECT * FROM `onyga-482313.OI._tmp_t5fx_grade_new` WHERE scenario = 'DO_NOTHING';
CREATE TEMP TABLE o AS SELECT * FROM `onyga-482313.OI._tmp_t5fx_grade_old` WHERE scenario = 'DO_NOTHING';
CREATE TEMP TABLE fx AS SELECT * FROM UNNEST(['108301382467865', '11084263298679', '66007207046728', '112492877088507', '145785644018633', '117765426526312']) AS keyword_id;
SELECT 'FIXTURE' AS part, n.keyword_id, n.as_of, n.predictor, n.channel, n.horizon_from, n.horizon_to, n.applied_scenario AS v174, o.applied_scenario AS v173,
       ARRAY_TO_STRING(n.matched_change_ids, ',') AS m174, ARRAY_TO_STRING(n.other_change_ids, ',') AS o174,
       ARRAY_TO_STRING(o.other_change_ids, ',') AS o173, CAST(NULL AS INT64) AS n_rows
FROM n JOIN o USING (predictor, variant, as_of, campaign_id, keyword_id)
WHERE n.keyword_id IN (SELECT keyword_id FROM fx)
  AND (n.applied_scenario <> o.applied_scenario OR ARRAY_LENGTH(n.matched_change_ids) + ARRAY_LENGTH(n.other_change_ids) + ARRAY_LENGTH(o.other_change_ids) + ARRAY_LENGTH(o.matched_change_ids) > 0)
UNION ALL
SELECT 'REAL', NULL, NULL, n.predictor, NULL, NULL, NULL, n.applied_scenario, l.applied_scenario, NULL, NULL, NULL, COUNT(*)
FROM n JOIN `onyga-482313.OI.FACT_PREDICTION_GRADE` l
  ON l.scenario = 'DO_NOTHING' AND l.regrade_seq = 0 AND l.predictor = n.predictor AND l.variant = n.variant AND l.as_of = n.as_of
 AND l.campaign_id = n.campaign_id AND l.keyword_id = n.keyword_id
WHERE n.keyword_id NOT IN (SELECT keyword_id FROM fx)
GROUP BY n.predictor, n.applied_scenario, l.applied_scenario
ORDER BY part, keyword_id, as_of, predictor, v174, v173;
```

```sql
-- 4. seq 0 (v27.173) against seq 1 (v27.174), per predictor
SELECT a.predictor, a.applied_scenario AS seq0, b.applied_scenario AS seq1,
       COUNTIF(a.scenario = 'DO_NOTHING') AS plan_rows,
       COUNTIF(a.scenario = 'DO_NOTHING' AND (ARRAY_TO_STRING(a.matched_change_ids, ',') <> ARRAY_TO_STRING(b.matched_change_ids, ',')
                                          OR ARRAY_TO_STRING(a.other_change_ids, ',') <> ARRAY_TO_STRING(b.other_change_ids, ','))) AS ids_moved,
       COUNTIF(a.is_applied) AS applied0, COUNTIF(b.is_applied) AS applied1,
       COUNTIF(a.scenario = 'DO_NOTHING' AND (a.real_clicks <> b.real_clicks OR ABS(a.real_spend - b.real_spend) > 0.005)) AS real_moved,
       COUNTIF(a.scenario = 'DO_NOTHING' AND ABS(a.real_gp - b.real_gp) > 0.005) AS gp_moved,
       COUNTIF(a.grade <> b.grade) AS grade_moved,
       COUNTIF(a.scenario = 'DO_NOTHING' AND a.placement_changed IS DISTINCT FROM b.placement_changed) AS plc_moved
FROM `onyga-482313.OI.FACT_PREDICTION_GRADE` a
JOIN `onyga-482313.OI.FACT_PREDICTION_GRADE` b
  ON b.regrade_seq = 1 AND a.predictor = b.predictor AND a.variant = b.variant AND a.as_of = b.as_of
 AND a.campaign_id = b.campaign_id AND a.keyword_id = b.keyword_id AND a.scenario = b.scenario
WHERE a.regrade_seq = 0
GROUP BY 1, 2, 3 ORDER BY 1, 2, 3
```

```sql
-- 5. the report card rows that read the applied scenario
SELECT row_type, predictor, scenario, n_rows, ROUND(real_spend, 2) AS real_spend, ROUND(mae_net_share, 4) AS mae_net_share,
       ROUND(bias_share, 4) AS bias_share, ROUND(side_accuracy, 4) AS side_accuracy,
       ROUND(counterfactual_net_per_alloc, 4) AS cf_net_per_alloc, ROUND(dn_net_per_dollar, 4) AS dn_net_per_dollar,
       n_other_action, n_act_no_matching_action, lift_rows
FROM `onyga-482313.OI.T_PREDICTION_SCORECARD`
WHERE family = 'ALL' AND level = 'SINCE_START' AND row_type IN ('ACCURACY', 'MONEY', 'HONESTY')
ORDER BY row_type, predictor, scenario
```

### Task 5 follow-up 2 — a logged change is read at its landing, not its log stamp (2026-10-04)

**The finding** (Task-5 review 2): `_chg` read every landed change at its own `applied_at`. For a
`LOGGED_AND_SEEN_ON_AMAZON` row that is the log stamp — `V_PPC_CHANGE_LOG_LANDED` keeps the log row
and drops the observed twin — and a book row is stamped when the book is built, not when it is
uploaded (§4 step 4, "the instant a change is read at"). Two consequences: a plan book built after
`built_at` but uploaded after the match window would still match and read `ACT`; a hand book built
before `built_at` but uploaded after it would be dropped as baseline and leave the row `DO_NOTHING`.
The extra SB day also read `LOGGED_AND_SEEN_ON_AMAZON` SB rows, so under nightly uploads the book
uploaded on `horizon_to + 1` would make the rows it touches `OTHER_ACTION`. The comment that
"campaigns and SP keywords carry Amazon's own last-updated time" was false for this class.

**Fixed** (`SP_GRADE_PREDICTIONS` v27.175): `_chg0` reads every landed change at its landing — a
`LOGGED_AND_SEEN_ON_AMAZON` row at `MIN(FACT_PPC_CHANGE_LOG.applied_at)` over
`SPLIT(paired_change_id, ',')`, any other row at its own `applied_at` — and an ASSERT refuses a run
in which a landed change has no instant; `seen_only` marks the `SEEN_ON_AMAZON_*` rows, and only
those get the extra SB day (`hits`: `applied_at < IF(seen_only, kw_scan_end, scan_end)`). The
procedure's step-4 comment and description, §4, the spec (§7 step 2, §14.1), the plan (Task 5
Step 4) and `config.yaml` (description; `FACT_PPC_CHANGE_LOG` added to the dependencies) say the
same.

**Measured before the fix** (queries 1–2 below): 60 `LOGGED_AND_SEEN_ON_AMAZON` rows, 70 observed
twins, each found once; landing minus stamp −1 to +1,079 minutes (by batch: campaign pauses of
`stop_nonconverting_20260821` −1, 7 rows; SP keyword pauses of `seat_moves_20260823_1045` +249, 9;
its SB keyword pauses +1,078 / +1,079, 8; SP keywords of `reprice_book_20260823_1527` +26, 15; its
SB keywords +797, 10; SB unpauses of `seasonal_unpause_20260824_1728` +678, 11 rows with 21 twins);
none on another Los Angeles date than its stamp. Against the current grades, 420 (grade row, change)
pairs read the same keyword or campaign; for 0 of them do the stamp and the landing fall on two sides
of `built_at`, the match-window end, the scan end or the SB scan end. So no stored grade moves and
the August band is not re-graded.

**Deployed** `scripts/bigquery/procedures/SP_GRADE_PREDICTIONS.sql` v27.175 (comment lines stripped)
at 22:21:31 UTC 2026-10-03 (job `t5r2_deploy_sp_1791066089`; before it the deployed body equalled
HEAD 5e0b061's, 42,973 characters): `INFORMATION_SCHEMA.ROUTINES.routine_definition` equals the file's
`BEGIN … END`, 44,081 characters, SHA-256 prefix `5b0f34ecf655`; the DDL carries the file's
description (2,050 characters) and the arguments `(regrade_from DATE, reason STRING)`. A `(NULL,
NULL)` call after it (`t5r2_call_null_1791066114`, 230.7 slot-seconds): 0 due, 0 inserted, the card
rebuilt at 357 rows; `FACT_PREDICTION_GRADE` still 17,888 rows (seq 0 v27.173 8,944; seq 1 v27.174
8,944).

**Proved on copies of the grader** (the stripped file and, for v27.174, HEAD 5e0b061's, with the
procedure, `FACT_PREDICTION_GRADE`, `T_PREDICTION_SCORECARD`, `V_PREDICTION_LEDGER`,
`V_PPC_CHANGE_LOG_LANDED` and — v27.175 only, v27.174 does not read it — `FACT_PPC_CHANGE_LOG`
names swapped). Inputs (query 3, `t5r2_fixtures_1791065621`, 170.6 slot-seconds): `OI._tmp_t5g_log`
= the change log's 2,700 rows + 5 injected twins; `OI._tmp_t5g_chg` = the view's 2,016 rows + 6
injected rows; `OI._tmp_t5g_led` = the ledger's 17,588 rows with two plan keys doctored (8 rows).
Each copy graded from empty (`t5r2_runnew_1791065675`, 118.4 slot-seconds: applied ACT 0,
DO_NOTHING 4,268, OTHER_ACTION 204; `t5r2_runold_1791065675`, 93.6: ACT 4, DO_NOTHING 4,264,
OTHER_ACTION 204), 8,944 rows each. Per plan row, both plans alike (query 4, `t5r2_compare_1791065813`):

| fixture | night, keyword | injected | v27.175 | v27.174 |
|---|---|---|---|---|
| G1 book built before the plan, landed after | 08-23 (built 05:34:19 UTC 08-24), SP 11084263298679 | bid 0.62, stamped 03:34:19, landed 06:34:19 UTC 08-24 | OTHER_ACTION | DO_NOTHING |
| G5 stamped after the build, landed before it | 08-23, SP 112492877088507 | bid 1.37, stamped 06:04:19, landed 05:04:19 UTC 08-24 | DO_NOTHING | OTHER_ACTION |
| G2 plan book stamped in the match window, landed after it | 08-28 (built 05:30:11 UTC 08-29), SP 108301382467865, stretched to 08-29 … 09-04, plan bid 0.62 as its one component | bid 0.62, stamped 10:00 LA 08-31, landed noon LA 09-02 | OTHER_ACTION | ACT |
| G2B the same, landed after the horizon | 08-28, SP 11084263298679 (08-29 … 08-31), plan bid 0.62 as its one component | bid 0.62, stamped 10:00 LA 08-31, landed 10:00 LA 09-01 | DO_NOTHING | ACT |
| G3 logged SB change on `horizon_to + 1` | 08-28, SB 164293084382000 | bid 1.32, stamped 08:00, landed 20:00 LA 09-01 | DO_NOTHING | OTHER_ACTION |
| G4 SB hand change on `horizon_to + 1` | 08-28, SB 145785644018633 | bid 0.62, seen 10:00 LA 09-01 | OTHER_ACTION | OTHER_ACTION |

Every other plan row of each copy (2,230 per plan: 2,131 `DO_NOTHING`, 99 `OTHER_ACTION`) equals the
live current grade on the applied scenario, both id lists, the label and `is_applied`, under v27.175
and under v27.174 alike: 0 moved. The acceptance suite as written, names swapped the same way, on
v27.175's grades: every asserted row PASS (`t5r2_acc_fx_new_1791066382`, 151.8 slot-seconds); on
v27.174's: V9 LIVE FAIL 20 = the five fixtures the two rules label differently × 2 plans × 2
scenarios, every V9 PC copy 20 (LIVE's, nothing added), every NC fired
(`t5r2_acc_fx_old_1791066382`, 139.8 slot-seconds). Scratch tables `OI._tmp_t5g_log`, `_tmp_t5g_chg`, `_tmp_t5g_led`,
`_tmp_t5g_grade_new`, `_tmp_t5g_grade_old`, `_tmp_t5g_sc_new`, `_tmp_t5g_sc_old` expire 2026-10-11;
the two procedure copies were dropped.

**Checked.** `scripts/bigquery/tests/PREDICTION_GRADE_acceptance.sql`'s V9 reads each change at its
landing (`chg`: the twin's earliest `applied_at` for a `LOGGED_AND_SEEN_ON_AMAZON` row) and gives the
extra SB day to `SEEN_ON_AMAZON_*` rows only. A control injects a logged change as a log row and its
twin, and V9 resolves it like a live row. Four new pairs (the file's header names the picks' rules):
PC_V9_BOOK_PRE / NC_V9_BOOK_PRE (a book stamped two hours before `built_at`, landed one hour after:
`OTHER_ACTION`; left `DO_NOTHING`, V9 fires), PC_V9_BOOK_LATE / NC_V9_BOOK_LATE (the DAY5 pick
stretched to 7 days with one bid component; a book to that bid stamped noon day 2, landed noon day 5:
`OTHER_ACTION`; labelled `ACT`, V9 fires), PC_V9_SB_LOGGED / NC_V9_SB_LOGGED (a logged SB change
stamped 08:00 and landed 20:00 Los Angeles on `horizon_to + 1`: stays `DO_NOTHING`; labelled
`OTHER_ACTION`, V9 fires) and PC_V9_SB_SEEN / NC_V9_SB_SEEN (an SB hand change seen 10:00 on
`horizon_to + 1`: `OTHER_ACTION`; left `DO_NOTHING`, V9 fires). Live, as written, after the deploy
(`t5r2_acc_live_1791066278`, 247.1 slot-seconds, 224,174,176 bytes): 42 rows, every asserted row
PASS — LIVE V1–V9 0, V2g REPORT 0; NC_EMPTY V1 8,944 and V2–V9 1 each; NC_V7_MISSED_ARCHIVE 24;
every other V1–V8 control 1; every V9 NC 4, every V9 PC 0. Picks (`t5r2_picks2_1791066278`):
PREBUILD and BOOKPRE 08-23 SP 108301382467865 (built 05:34:19 UTC 08-24); DAY5 08-25 SP
236377827196202 (built 05:58:01 UTC 08-26, day 5 = 08-30); SBNEXT 08-28 SB 145785644018633
(`horizon_to + 1` = 09-01). **Do the new pairs tell the rules apart?** The same file with V9's
instant put back to the row's own `applied_at` and the extra SB day given to every SB change (the
v27.174 reading; `t5r2_acc_mut3_1791066278`): V9 LIVE 0 (no live pair straddles), PC_V9_BOOK_PRE 4
and NC_V9_BOOK_PRE 0, PC_V9_BOOK_LATE 8, PC_V9_SB_LOGGED 4 and NC_V9_SB_LOGGED 0 — five FAILs —
while PREBUILD, DAY5 and SB_SEEN still PASS. NC_V9_BOOK_LATE reads 4 there, not 0: the day-2 stamp
lies in the 08-24 night's span (built 06:04:16 UTC 08-25, horizon 08-25 … 08-27), so that night's 4
rows read it under the stamp; the pick's own rows agree with the v27.174 reading, and PC_V9_BOOK_LATE
fails. The DAY5 pick cannot also keep its day-2 stamp out of other nights: with that condition no
plan key qualified (`t5r2_picks_1791066215`).

**Limit, stated.** A logged SB change uploaded on `horizon_to` and first seen after Los Angeles
midnight is no longer read (§4 "The SB sync lag"); of the 60 logged changes seen so far, none was
seen on another Los Angeles date than its stamp.

```sql
-- 1. the LOGGED_AND_SEEN_ON_AMAZON rows by batch: stamp, landing (earliest twin), minutes between
WITH lv AS (
  SELECT change_id, action, keyword_id, campaign_type, batch_id, applied_at AS logged_at, paired_change_id, source
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_LANDED` WHERE landed_evidence = 'LOGGED_AND_SEEN_ON_AMAZON'
),
p AS (
  SELECT lv.change_id, ANY_VALUE(lv.action) action, ANY_VALUE(lv.campaign_type) ct, ANY_VALUE(lv.batch_id) batch,
         ANY_VALUE(lv.keyword_id IS NOT NULL) is_kw, ANY_VALUE(lv.logged_at) logged_at, MIN(f.applied_at) obs_at, COUNT(*) npid,
         COUNT(f.change_id) n_found
  FROM lv, UNNEST(SPLIT(lv.paired_change_id, ',')) pid
  LEFT JOIN `onyga-482313.OI.FACT_PPC_CHANGE_LOG` f ON f.change_id = pid
  GROUP BY lv.change_id
)
SELECT batch, ct, is_kw, action, COUNT(*) n, SUM(npid) twins, SUM(n_found) found,
       MIN(TIMESTAMP_DIFF(obs_at, logged_at, MINUTE)) dmin, MAX(TIMESTAMP_DIFF(obs_at, logged_at, MINUTE)) dmax,
       COUNTIF(DATE(obs_at, 'America/Los_Angeles') <> DATE(logged_at, 'America/Los_Angeles')) la_date_differs
FROM p GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, 4
```

```sql
-- 2. the (current grade row, logged change) pairs whose stamp and landing fall on two sides of a boundary
WITH lv AS (
  SELECT v.change_id, v.keyword_id, v.campaign_id, v.applied_at AS logged_at,
         (SELECT MIN(f.applied_at) FROM UNNEST(SPLIT(v.paired_change_id, ',')) pid
          JOIN `onyga-482313.OI.FACT_PPC_CHANGE_LOG` f ON f.change_id = pid) AS seen_at
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_LANDED` v
  WHERE v.landed_evidence = 'LOGGED_AND_SEEN_ON_AMAZON'
),
cur AS (
  SELECT * FROM `onyga-482313.OI.FACT_PREDICTION_GRADE` WHERE scenario = 'DO_NOTHING'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY predictor, variant, as_of, campaign_id, keyword_id, scenario ORDER BY regrade_seq DESC) = 1
),
b AS (
  SELECT c.channel, x.logged_at, x.seen_at, c.built_at,
         LEAST(TIMESTAMP(DATE_ADD(c.horizon_from, INTERVAL 3 DAY), 'America/Los_Angeles'),
               TIMESTAMP(DATE_ADD(c.horizon_to, INTERVAL 1 DAY), 'America/Los_Angeles')) AS match_end,
         TIMESTAMP(DATE_ADD(c.horizon_to, INTERVAL 1 DAY), 'America/Los_Angeles') AS scan_end,
         TIMESTAMP(DATE_ADD(c.horizon_to, INTERVAL 2 DAY), 'America/Los_Angeles') AS scan_end_p1
  FROM cur c JOIN lv x ON x.keyword_id = c.keyword_id OR (x.keyword_id IS NULL AND x.campaign_id = c.campaign_id)
)
SELECT COUNT(*) AS pairs,
       COUNTIF((logged_at < built_at) <> (seen_at < built_at)) AS straddle_built,
       COUNTIF((logged_at < match_end) <> (seen_at < match_end)) AS straddle_match_end,
       COUNTIF((logged_at < scan_end) <> (seen_at < scan_end)) AS straddle_scan_end,
       COUNTIF(channel = 'SB' AND (logged_at < scan_end_p1) <> (seen_at < scan_end_p1)) AS straddle_sb_scan_end
FROM b
```

```sql
-- 3. the fixture inputs: the change log, the landed view and the ledger, copied, with six changes injected
-- G1 BOOK_PRE      night 08-23 (built 2026-08-24 05:34:19 UTC), SP 11084263298679: a book row stamped 2 h before the build, landed 1 h after it
-- G5 LANDED_BEFORE night 08-23, SP 112492877088507: a book row stamped 30 min after the build, landed 30 min before it
-- G2 BOOK_LATE     night 08-28 (built 2026-08-29 05:30:11 UTC), SP 108301382467865, stretched to 7 days (08-29 .. 09-04) and given one
--                  bid component (planned 0.62, the planned budget = the current one): a book row to 0.62 stamped 10:00 LA 08-31
--                  (inside the match window), landed noon LA 09-02 (after it, inside the horizon)
-- G2B BOOK_AFTER   night 08-28, SP 11084263298679, the same bid component on its 3-day horizon (08-29 .. 08-31): a book row to 0.62
--                  stamped 10:00 LA 08-31, landed 10:00 LA 09-01 (after the horizon)
-- G3 SB_LOGGED     night 08-28, SB 164293084382000: a book row stamped 08:00 LA 09-01 (horizon_to + 1), landed 20:00 LA 09-01
-- G4 SB_SEEN       night 08-28, SB 145785644018633: a hand change seen 10:00 LA 09-01 (horizon_to + 1)
CREATE TEMP TABLE inj AS
SELECT * FROM UNNEST([
  STRUCT('G1' AS g, '11084263298679' AS keyword_id, '531456687555062' AS campaign_id, 0.62 AS new_bid,
         TIMESTAMP '2026-08-24 03:34:19 UTC' AS logged_at, TIMESTAMP '2026-08-24 06:34:19 UTC' AS seen_at),
  ('G5', '112492877088507', '43890791772293', 1.37, TIMESTAMP '2026-08-24 06:04:19 UTC', TIMESTAMP '2026-08-24 05:04:19 UTC'),
  ('G2', '108301382467865', '531456687555062', 0.62, TIMESTAMP('2026-08-31 10:00:00', 'America/Los_Angeles'), TIMESTAMP('2026-09-02 12:00:00', 'America/Los_Angeles')),
  ('G2B', '11084263298679', '531456687555062', 0.62, TIMESTAMP('2026-08-31 10:00:00', 'America/Los_Angeles'), TIMESTAMP('2026-09-01 10:00:00', 'America/Los_Angeles')),
  ('G3', '164293084382000', '435692261851957', 1.32, TIMESTAMP('2026-09-01 08:00:00', 'America/Los_Angeles'), TIMESTAMP('2026-09-01 20:00:00', 'America/Los_Angeles')),
  ('G4', '145785644018633', '446868628489343', 0.62, TIMESTAMP('2026-09-01 10:00:00', 'America/Los_Angeles'), CAST(NULL AS TIMESTAMP))
]);

CREATE OR REPLACE TABLE `onyga-482313.OI._tmp_t5g_log`
OPTIONS (expiration_timestamp = TIMESTAMP '2026-10-11 00:00:00 UTC') AS
WITH tpl AS (
  SELECT * FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE source = 'OBSERVED' AND upload_status = 'OBSERVED_ON_AMAZON' AND keyword_id IS NOT NULL AND new_bid IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (ORDER BY change_id) = 1
)
SELECT * FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
UNION ALL
SELECT t.* REPLACE ('fx2|' || i.g || '|seen' AS change_id, i.keyword_id AS keyword_id, i.campaign_id AS campaign_id,
                    i.new_bid AS new_bid, i.seen_at AS applied_at, 'REDUCE_BID' AS action,
                    CAST(NULL AS FLOAT64) AS new_budget, CAST(NULL AS FLOAT64) AS old_budget,
                    'CONFIRMS fx2|' || i.g || '|log Task 5 follow-up 2 fixture' AS upload_note)
FROM tpl t CROSS JOIN inj i
WHERE i.seen_at IS NOT NULL;

CREATE OR REPLACE TABLE `onyga-482313.OI._tmp_t5g_chg`
OPTIONS (expiration_timestamp = TIMESTAMP '2026-10-11 00:00:00 UTC') AS
WITH tpl AS (
  SELECT * FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_LANDED`
  WHERE landed_evidence = 'SEEN_ON_AMAZON_NOT_LOGGED' AND keyword_id IS NOT NULL AND new_bid IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (ORDER BY change_id) = 1
)
SELECT * FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_LANDED`
UNION ALL
SELECT t.* REPLACE (IF(i.seen_at IS NULL, 'fx2|' || i.g || '|seen', 'fx2|' || i.g || '|log') AS change_id,
                    i.keyword_id AS keyword_id, i.campaign_id AS campaign_id, i.new_bid AS new_bid,
                    i.logged_at AS applied_at, 'REDUCE_BID' AS action,
                    CAST(NULL AS FLOAT64) AS new_budget, CAST(NULL AS FLOAT64) AS old_budget,
                    IF(i.seen_at IS NULL, 'OBSERVED', 'MANUAL') AS source,
                    IF(i.seen_at IS NULL, 'OBSERVED_ON_AMAZON', CAST(NULL AS STRING)) AS upload_status,
                    'Task 5 follow-up 2 fixture' AS upload_note,
                    IF(i.seen_at IS NULL, 'SEEN_ON_AMAZON_NOT_LOGGED', 'LOGGED_AND_SEEN_ON_AMAZON') AS landed_evidence,
                    IF(i.seen_at IS NULL, CAST(NULL AS STRING), 'fx2|' || i.g || '|seen') AS paired_change_id)
FROM tpl t CROSS JOIN inj i;

CREATE OR REPLACE TABLE `onyga-482313.OI._tmp_t5g_led`
OPTIONS (expiration_timestamp = TIMESTAMP '2026-10-11 00:00:00 UTC') AS
SELECT l.* REPLACE (
  IF(l.as_of = '2026-08-28' AND l.keyword_id = '108301382467865', DATE_ADD(l.horizon_from, INTERVAL 6 DAY), l.horizon_to) AS horizon_to,
  IF(l.as_of = '2026-08-28' AND l.keyword_id = '108301382467865', 7, l.window_days) AS window_days,
  IF(l.as_of = '2026-08-28' AND l.keyword_id IN ('108301382467865', '11084263298679'), 0.62, l.planned_bid) AS planned_bid,
  IF(l.as_of = '2026-08-28' AND l.keyword_id IN ('108301382467865', '11084263298679'), l.campaign_current_budget,
     l.campaign_planned_budget) AS campaign_planned_budget)
FROM `onyga-482313.OI.V_PREDICTION_LEDGER` l;

CREATE OR REPLACE TABLE `onyga-482313.OI._tmp_t5g_grade_new`
LIKE `onyga-482313.OI.FACT_PREDICTION_GRADE`
OPTIONS (expiration_timestamp = TIMESTAMP '2026-10-11 00:00:00 UTC');

CREATE OR REPLACE TABLE `onyga-482313.OI._tmp_t5g_grade_old`
LIKE `onyga-482313.OI.FACT_PREDICTION_GRADE`
OPTIONS (expiration_timestamp = TIMESTAMP '2026-10-11 00:00:00 UTC');

SELECT 'log' AS t, COUNT(*) AS n, COUNTIF(STARTS_WITH(change_id, 'fx2|')) AS fx FROM `onyga-482313.OI._tmp_t5g_log`
UNION ALL
SELECT 'chg', COUNT(*), COUNTIF(STARTS_WITH(change_id, 'fx2|')) FROM `onyga-482313.OI._tmp_t5g_chg`
UNION ALL
SELECT 'led', COUNT(*), COUNTIF(as_of = '2026-08-28' AND keyword_id IN ('108301382467865', '11084263298679')) FROM `onyga-482313.OI._tmp_t5g_led`
UNION ALL
SELECT 'grade_new', COUNT(*), 0 FROM `onyga-482313.OI._tmp_t5g_grade_new`
UNION ALL
SELECT 'grade_old', COUNT(*), 0 FROM `onyga-482313.OI._tmp_t5g_grade_old`;
```

```sql
-- 3. v27.175 against v27.174 on the copy, per plan row (the DO_NOTHING scenario row): the six fixture keys, then every other
--    plan row of each copy against the live current grade (applied scenario, both id lists, label)
CREATE TEMP TABLE fx AS
SELECT * FROM UNNEST([
  STRUCT('G1' AS g, DATE '2026-08-23' AS as_of, '11084263298679' AS keyword_id), ('G5', DATE '2026-08-23', '112492877088507'),
  ('G2', DATE '2026-08-28', '108301382467865'), ('G2B', DATE '2026-08-28', '11084263298679'),
  ('G3', DATE '2026-08-28', '164293084382000'), ('G4', DATE '2026-08-28', '145785644018633')]);
CREATE TEMP TABLE n AS SELECT * FROM `onyga-482313.OI._tmp_t5g_grade_new` WHERE scenario = 'DO_NOTHING';
CREATE TEMP TABLE o AS SELECT * FROM `onyga-482313.OI._tmp_t5g_grade_old` WHERE scenario = 'DO_NOTHING';
CREATE TEMP TABLE live AS
SELECT * FROM `onyga-482313.OI.FACT_PREDICTION_GRADE` WHERE scenario = 'DO_NOTHING'
QUALIFY ROW_NUMBER() OVER (PARTITION BY predictor, variant, as_of, campaign_id, keyword_id ORDER BY regrade_seq DESC) = 1;
SELECT 'FIXTURE' AS part, fx.g, n.as_of, n.keyword_id, n.predictor, n.channel, n.horizon_to,
       n.applied_scenario AS v175, o.applied_scenario AS v174,
       ARRAY_TO_STRING(n.matched_change_ids, ',') AS m175, ARRAY_TO_STRING(n.other_change_ids, ',') AS o175,
       ARRAY_TO_STRING(o.matched_change_ids, ',') AS m174, ARRAY_TO_STRING(o.other_change_ids, ',') AS o174,
       CAST(NULL AS INT64) AS n_rows, CAST(NULL AS INT64) AS ids_or_label_moved
FROM n JOIN o USING (predictor, variant, as_of, campaign_id, keyword_id)
JOIN fx ON fx.as_of = n.as_of AND fx.keyword_id = n.keyword_id
UNION ALL
SELECT 'REST_' || cp, NULL, NULL, NULL, x.predictor, NULL, NULL, x.applied_scenario, l.applied_scenario,
       NULL, NULL, NULL, NULL, COUNT(*),
       COUNTIF(ARRAY_TO_STRING(x.matched_change_ids, ',') <> ARRAY_TO_STRING(l.matched_change_ids, ',')
               OR ARRAY_TO_STRING(x.other_change_ids, ',') <> ARRAY_TO_STRING(l.other_change_ids, ',')
               OR x.grade <> l.grade OR x.is_applied <> l.is_applied)
FROM (SELECT 'v175_vs_live' AS cp, * FROM n UNION ALL SELECT 'v174_vs_live', * FROM o) x
JOIN live l USING (predictor, variant, as_of, campaign_id, keyword_id)
WHERE NOT EXISTS (SELECT 1 FROM fx WHERE fx.as_of = x.as_of AND fx.keyword_id = x.keyword_id)
GROUP BY cp, x.predictor, x.applied_scenario, l.applied_scenario
ORDER BY part, g, predictor, v175, v174;
```

### Task 6 — on the schedule, on the board, on the brief (2026-10-04)

**The orchestrator.** Before the change the deployed `SP_ORCHESTRATE_DAILY_REFRESH` (last altered
2026-10-03 06:30:45 UTC) equalled HEAD's file with its comment lines stripped, byte for byte (109,098
characters, SHA-256 prefix `4e81dc09a4e6`). The new step, Refresh Task 20.8f
`SP_GRADE_PREDICTIONS(NULL, NULL)`, sits between `SP_APPEND_CATALOG_FORECAST` (20.8e) and
`SP_REFRESH_CUBE_TABLES` (21) and is Task 20.8e's block byte for byte except the procedure name and
the CALL's arguments (string comparison); the new file's body differs from the deployed body by that
block (25 lines, two of them blank) and nothing else. **Proved before the deploy on copies of the
block** — two procedures with the block as written and `LOG_PIPELINE_RUNS` swapped for
`OI._tmp_t6_log` (created `LIKE` it, expires 2026-10-11), both dropped after the runs:

| case | what happened | job, slot-seconds |
|---|---|---|
| the block as deployed, the real grader | the grader's log: `0 ledger rows due, 0 inserted … T_PREDICTION_SCORECARD 357 rows; 80 seconds` (watermark 2026-10-02); the step logged OK, 82 s; the summary counted 1 OK; `FACT_PREDICTION_GRADE` still 17,888 rows from two `graded_at`; the card rebuilt (357 rows, `scored_at` 22:44:34 UTC) | `t6_step_ok_1791067472`, 263.4 (46 child jobs) |
| the CALL given `(DATE '2026-08-26', NULL)` — a re-grade without a reason, which the grader's first ASSERT refuses before any write | the step logged FAIL with the grader's message (`SP_GRADE_PREDICTIONS: a re-grade (regrade_from set) needs a reason; …`), 1 s; the summary counted 1 FAIL; the grade table unchanged (17,888 rows, highest `regrade_seq` 1) | `t6_step_fail_1791067615`, 22:46:58 UTC |

**Deployed** 22:47:27 UTC 2026-10-03 (job `t6_deploy_orch_1791067644`), comment lines stripped:
`INFORMATION_SCHEMA.ROUTINES.routine_definition` equals the file's `BEGIN … END` (110,511 characters,
SHA-256 prefix `33c0066b8120`), the description unchanged. The orchestrator was not run. The first
pass to run the step is the 05:00 UTC pass of 2026-10-04; it grades nothing until the 09-30 night
falls due (watermark 2026-10-17) and rebuilds the card every pass.

**The board.** `V_ENGINE_HEALTH` v27.176 deployed 22:47:49 UTC (job `t6_deploy_health_1791067666`);
before it the deployed definition equalled HEAD's file, after it this file (62,184 characters, 23.72%
of the 262,144-character ceiling). The three checks' text run as a query before the deploy (job
`t6_proto_1791067312`): 116.5 slot-seconds, 15,229,779 bytes processed — of which the ledger's key
columns alone cost 73.2 slot-seconds (job `t6_ledkeys_1791067079`; the whole ledger, 106.5, §10
"Task 4"). The full board after the deploy (job `t6_board_full_1791067685`, 22:48 UTC): 37 checks, 3
RED — `contradiction_rate`, `seat_every_occupant_numbered`, `seat_past_due_in_future_tense`, the
same three as before — 13,519.0 slot-seconds, 191,527,985 bytes. HEAD's body run as a query right
after it (job `t6_board_old_1791067743`): 26,210.3 slot-seconds, 186,983,538 bytes; the board's cost
moves between runs with its other arms, and the three checks' share is the 116.5 above. The board
filtered to the three checks costs 79.0 slot-seconds (25,715,539 bytes; the first statement of job
`t6_ponly2_1791068157`). Their first readings:

- `prediction_grades_fresh` GREEN, 0 — `0 of 8944 ledger rows past due have no grade · watermark
  2026-10-02 = LEAST(FACT_AMAZON_ADS newest day 2026-10-03, FN_ADS_ANCHOR_CAP() 2026-10-02) · …
  8644 ledger rows not yet past due, the next when the watermark reaches 2026-10-18`: the six August
  nights, both plans, both scenarios, all graded; the 09-30 night (horizon 10-01 … 10-03) becomes
  gradable on watermark 10-17 and past due on 10-18.
- `prediction_regression` INFO, 0 — `YOUNG — PLAN_A: YOUNG, 1 of 6 windows graded (2026-08-23);
  PLAN_B: …`: one graded week (the Sunday week of 08-23); twice `MIN_GRADED_WINDOWS` is six.
- `response_model_unverified` INFO, 0 — `0 ACT grades applied with a move · 0 applied on rows the
  plan moved nothing · 3832 with a move whose row applied as DO_NOTHING (no uploaded plan matched) ·
  198 OTHER_ACTION · 4472 current ACT grades`.

**The brief.** `V_DAILY_BRIEF` v27.176 deployed 22:51:01 UTC (job `t6_deploy_brief_1791067858`); its
deployed definition equals this file (23,495 characters). Only `health` changed (§6: `pri` 4 and 5,
the detail quoted for `pri <= 5`). No learning check is RED on the live board; C04 (the line
counts and names every RED check of the board) and C04f (the twin's rendering equals the deployed
row) pass on it (below). Run 23:05 UTC, before any pass had run the step, the two queries at the end
of this entry returned no row.

**Checked.** `scripts/bigquery/tests/PLAN_HEALTH_acceptance.sql` v27.176, run as written after both
deploys (job `t6_ph_full_1791068301`, 22:58–23:04 UTC, `--nosync`, 73 statements, 323 s): 49 rows,
every one PASS — the 42 earlier rows and P0–P5. 68,535.0 slot-seconds (the brief read 54,735.8, the
board read 13,165.9, the other 71 statements 633.3), 1,079,137,462 bytes. P1–P3 run the board's own
`lrn_due` … `c37` text on doctored copies of its seven inputs (text identity, the command in the
file's header: `file==acceptance True`, `deployed carries it True`; `HOLDOUT_INTEGRITY_acceptance.sql`'s
own command still reads True and True). The controls, each read (job `t6_ponly2_1791068157`, the P
section alone, 445.4 slot-seconds; the full run passed on the same picks):

- `prediction_grades_fresh` — NC_P1_UNGRADED (the plan's control: the first past-due ledger row's
  grade removed, the 08-23 night) RED 1; NC_P1_PAST_GRACE (an ungraded row one night past the grace)
  RED 1; HC_P1_GRACE (an ungraded row in the grace night, gradable tonight) GREEN 0; NC_P1_EMPTY (no
  ledger row), NC_P1_NO_SETTING, NC_P1_NO_WATERMARK RED 0.
- `prediction_regression` — on synthetic cards, six weeks a plan: HC_P2_FLAT GREEN 0;
  NC_P2_MAE_WORSE (the plan's control: PLAN_B's trailing three weeks 20% worse on `mae_net_share`,
  with a builder change between the spans) RED 1, naming `builder_version gone pre-v27.170,
  builder_version new v27.171, rule_version gone R0:pre-v27.170, rule_version new R0:v27.171`;
  HC_P2_MAE_WITHIN (8% worse) GREEN 0; NC_P2_CF_WORSE (`counterfactual_net_per_alloc` −0.2 against
  −0.1) RED 1; NC_P2_YOUNG (five weeks) INFO 0; NC_P2_EMPTY (no card) RED 0; NC_P2_NO_SETTING RED 0.
- `response_model_unverified` — NC_P3_ACT_APPLIED (the plan's control: one current ACT grade with a
  move set applied) GREEN 1; HC_P3_NOOP_APPLIED (one with no move) INFO 0; HC_P3_UNGRADABLE (the move
  applied on an UNGRADABLE row) INFO 0.
- No check a copy did not doctor moved on any copy. P5: the deployed rows equal the twin's LIVE copy
  on measured, threshold, status and detail.
- P4a (`prediction_grades_fresh` doctored RED on an otherwise green board): RED, `a NEW check is
  RED`, its detail quoted. P4b (`plan_pass_failed`, both learning checks and `plan_both_plans_written`
  RED): the list in that order, the first three quoted, the action A PLAN PASS FAILED. The v27.163
  list on the same two boards (job `t6_pri_mut_1791068659`) reads `prediction_grades_fresh` bare and
  `plan_pass_failed (…); plan_both_plans_written; prediction_grades_fresh; prediction_regression`, so
  both checks fail on it.

`config.yaml`: `V_ENGINE_HEALTH` (description, and its six new dependencies), `V_DAILY_BRIEF`,
`SP_ORCHESTRATE_DAILY_REFRESH` and `SP_GRADE_PREDICTIONS` (descriptions); it parses. SOPs:
`architecture/ENGINE_HEALTH.md` (the three checks), `architecture/DAILY_BRIEF.md` (their place on the
line), this file §6 and §7.

**Not yet measured: the first scheduled run.** Read after the 05:00 UTC pass of 2026-10-04:

```sql
-- the step's runs, and the board's three rows as the pass's snapshot stored them
SELECT procedure_name, status, error_message, started_at, duration_seconds
FROM `onyga-482313.OI.LOG_PIPELINE_RUNS`
WHERE procedure_name = 'SP_GRADE_PREDICTIONS' ORDER BY started_at DESC LIMIT 6;

SELECT snapshot_at, check_name, status, measured, detail
FROM `onyga-482313.OI.FACT_ENGINE_HEALTH_HISTORY`
WHERE check_name IN ('prediction_grades_fresh', 'prediction_regression', 'response_model_unverified')
ORDER BY snapshot_at DESC, check_name LIMIT 9;
```
