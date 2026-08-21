# DAILY_BRIEF — the engine's daily self-accounting

**Born:** 2026-08-15. **Owner request (verbatim):** "i want you to be able to check the data easily
so i can ask you daily what was planned what actually happened and what are your action items. the
purpose is to make it better. meaning if after a change it became worse this is not good."

## Objects

| object | role |
|---|---|
| `FACT_ENGINE_PROPOSALS` | The engine's memory of its own **opinions** — one row per (day, engine, instruction), applied or not. Partitioned by `snapshot_date`. |
| `SP_SNAPSHOT_ENGINE_PROPOSALS` | Writes today's partition (delete-today-then-insert, idempotent). One single-view scan per INSERT — planner-ceiling doctrine. Orchestrator Task 20.6. |
| `V_DAILY_BRIEF` | The one-query answer. Four sections, uniform row shape. |

## The daily ritual

```sql
SELECT section, source, campaign_name, item, action, from_value, to_value, status, detail
FROM `onyga-482313.OI.V_DAILY_BRIEF`
ORDER BY section_rank, campaign_name;
```

- **PLANNED** — the latest snapshot: what the engine wants done today, per engine, verbatim reasons.
- **HAPPENED** — everything applied in the last 48h. `status='planned'` means the engine proposed
  that exact key on the day it was applied; `unplanned` means manual or engine-silent — the raw
  material of the manual-divergence doctrine ("if i change something manually … we need to fix the
  model").
- **VERDICT_NEW** — scorecard verdicts that became *readable* in the last 3 days. **The lag is the
  instrument**: a change is graded on [T+1, T+7] and read no earlier than T+14 (SB [T+1, T+14],
  read T+21). Early reads systematically under-read your own change and manufacture churn — so
  "what actually happened" arrives on a delay, by design, the morning it is finally honest.
- **ACTION_ITEM** — `REVERSED` verdicts not yet superseded: the change made things worse on settled
  evidence. Remedy is **always restore `remedy_value`, never lower** (a false cut kills a winner
  forever; a false restore delays a day). This section is the owner's sentence — "if after a change
  it became worse this is not good" — mechanized.

  **v2 (2026-08-15, caught by the FIRST upload attempt):** a remedy is only a restore while the
  graded change is still the STANDING value. Three guards, all learned the hard way the day the
  section was born: (1) `next_change_date IS NULL` — the v1 `n_later_changes` filter counts only
  in-window changes and let through 25 keys re-decided by the Aug 4/9 iterations; (2) **live
  parity** — the config's current value must equal the graded `new_value` (a mismatch means an
  unlogged drift, its own finding); (3) **conflict flag** — a key any engine instructs in today's
  proposal snapshot demotes to `REVIEW` naming the conflict (single-home: the live engine outranks
  a scorecard remedy; low stock outranks everything).

## Honest-reading rules

1. Never judge a change before its read gate. Spend settles ~D+3; sales accrue to D+7 (SP) / D+14
   (SB). A change that looks bad at D+2 is usually an instrument artifact.
2. `HAPPENED/unplanned` is not an accusation — it is a question: *why did the human see what the
   engine didn't?* Each unplanned row should end as either a model fix or a documented
   disagreement (engine-finalization plan, Task 3.1 `V_MANUAL_DIVERGENCE`).
3. A quiet ACTION_ITEM section is the goal state, not a malfunction.
4. Cold start: snapshots begin 2026-08-15 — HAPPENED rows before the first snapshot on their
   applied day all read `unplanned`, vacuously.

## Known gaps (stated, not silent)

- NEGATE proposals are snapshotted since v27.72 (2026-08-17): `grain='NEGATE'`, one row per
  (campaign, term), `target_text` holds the term, no values, `ad_group_id` carries the source
  view's comma-list verbatim (the consumer splits it — one bulksheet row per ad group, upload
  report 29). Sources: V_OOB_SEARCH_TERM `is_negate` rows under their own engine (OOB or LIFT)
  and V_WEEKLY_RUN_NEGATIVE under engine `COACH` — the coach negates read the LIVE view, because
  T_WEEKLY_RUN_NEGATIVE is built by Task 21 AFTER this snapshot (reading the T_ would snapshot
  yesterday's offers). `season_relax_applied` carries `peak_converts` so the preflight can REVIEW
  seasonal keeps. The remaining unsnapshotted lever is ADD_KEYWORD (research "+broad" offers).
- `V_DAILY_BRIEF` reads the live scorecard (ceiling view) in two lean UNION arms; if the planner
  ever objects, snapshot the scorecard the way the guard is snapshotted and repoint the arms.
- Verdict-vs-proposal attribution (did the ENGINE's own suggestions get CONFIRMED or REVERSED, as
  distinct from all changes?) needs proposal history to accumulate — meaningful from ~2026-08-29
  (first T+14 reads of snapshotted proposals).

## The last-day veto is recorded, not erased (v27.98, 2026-08-21)

Every suppression in the engine LABELS its row: ownership deferral, single-home dedup, no-ops,
holds and the randomized holdout arm all sit in `FACT_ENGINE_PROPOSALS` with `verdict = 'EXCLUDE'`
and a plain-language `verdict_reason`. `SP_ENGINE_PREFLIGHT` states the doctrine in its own header
for the holdout arm — *the proposal is still recorded; only the verdict says EXCLUDE; block the
export, never the judgement.*

The **last-day veto** (v27.75 / v27.76) was the one place that rule was broken, and not by
intention: the veto rewrites `action` to `HOLD` and NULLs `suggested_bid`, and the snapshot admits
a bid row on `action NOT IN ('HOLD', …) AND suggested_bid IS NOT NULL`. A vetoed row failed BOTH
conjuncts and vanished with its reason. The veto is also the one suppression that acts on a
proposal the engine ALREADY MADE — it is a *wait*, not a decision not to speak — so its rows are
precisely the ones worth keeping.

**How a held row is written now.** `V_OOB_KEYWORD` and `V_KEYWORD_LIFT` publish three ADDITIVE
columns inside the veto's own thin wrapper, NULL on every row it did not touch:

| column | meaning |
|---|---|
| `held_action` | the action the engine intended before the veto (`EASE`, `INCREASE_BID`, …) |
| `held_bid` | the bid it intended — **never** `suggested_bid` |
| `hold_source` | `LAST_DAY_VETO_RAISE` \| `LAST_DAY_VETO_CUT` |

`action` still reads `HOLD` and `suggested_bid` is still NULL, so every existing reader of those
columns — panels, cube, the bulksheet builders, the snapshot's own filters — behaves exactly as
before. `held_bid` is deliberately a separate column because **a value in `suggested_bid` is an
instruction**, and a held row must be unable to become one by any path.

`SP_SNAPSHOT_ENGINE_PROPOSALS` admits these rows in the SAME scan as the real bids (a separate
INSERT would re-read a planning-ceiling view for nothing) and stamps `verdict = 'EXCLUDE'` with the
veto's own sentence as `verdict_reason` — *"yday: 60c at 1.45x ⇒ cut waits a day"*.

**Why the verdict is written by the snapshot and not by the gate.** A held row is not an
instruction to judge. It carries no value, so every value test in `SP_ENGINE_PREFLIGHT` would read
it as a no-op and overwrite the veto's sentence with "no change — the suggested value equals the
current one"; and, far worse, it would enter the single-owner contention as a live instruction,
where a held OOB row could outrank a real LIFT one and leave the keyword untouched by an engine
that was ready to act. The gate therefore **skips `hold_source` rows outright**, which is also what
keeps them out of `T_ENGINE_PREFLIGHT`, the `EnginePreflight` cube, the decisions feed and
`DoPage.exportBulksheet`. A held row can be read in the history and can reach Amazon by no path.

`V_DAILY_BRIEF` skips them in PLANNED (that section is "what the engine wants DONE today") and in
the planned/unplanned join (a held row is not a plan). `V_HOLDOUT_READOUT` deliberately DOES read
them, through `COALESCE(held_bid, suggested_bid, …)` — without that, a held RAISE would fall to the
ELSE branch and be counted as a `BID_DOWN`, and the trial would split on the opposite of what the
engine wanted.

### The standing-block question, and the query that answers it

The veto is **stateless** on purpose: there is no "held since" flag, because the daily re-run IS
the day-after recheck. The failure mode that design is exposed to is a keyword whose filling day
reads poorly most days being held again, and again — a permanent block wearing a one-day costume,
which is not the single day's wait that was specified. Labelling turns that from a question needing
an experiment into a question needing a query:

    scripts/bigquery/queries/REPEAT_VETO_RUNS.sql

It groups held rows into runs of CONSECUTIVE SNAPSHOTS (not calendar days — a day the orchestrator
did not run is not a day the veto released) per (engine, campaign, keyword), and reports each run's
start, end, length and arm. Read the arm: a run on `LAST_DAY_VETO_CUT` is the veto working, since
under-attribution can only make a day look worse and a filling day already at/above the cut bar is
conservative proof. A lengthening run on `LAST_DAY_VETO_RAISE` is the alarm — that is the raise
that never comes, on a keyword busy every day, and the remedy is a release rule, not a longer wait.

**Cold start:** held rows exist only from the first snapshot after this change. The six snapshots
before it carry none, because those rows were erased rather than labelled — so the query is
answerable for runs of two only from the second snapshot onward.
