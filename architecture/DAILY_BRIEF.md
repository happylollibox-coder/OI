# DAILY_BRIEF — the engine's daily self-accounting

**Born:** 2026-08-15. **Owner request (verbatim):** "i want you to be able to check the data easily
so i can ask you daily what was planned what actually happened and what are your action items. the
purpose is to make it better. meaning if after a change it became worse this is not good."

## Objects

| object | role |
|---|---|
| `FACT_ENGINE_PROPOSALS` | The engine's memory of its own **opinions** — one row per (day, engine, instruction), applied or not. Partitioned by `snapshot_date`. |
| `SP_SNAPSHOT_ENGINE_PROPOSALS` | Writes today's partition (delete-today-then-insert, idempotent). One single-view scan per INSERT — planner-ceiling doctrine. Orchestrator Task 20.6. |
| `V_DAILY_BRIEF` | The one-query answer. Seven sections, uniform row shape. |
| `V_ENGINE_HEALTH` | The engine's standing self-check. The SYSTEM section reads it LIVE (never an image) and folds its RED rows into one line. Spec: `architecture/ENGINE_HEALTH.md`. |
| `FACT_ENGINE_HEALTH_HISTORY` | The board's memory (v27.163): one row per check per orchestrator pass, written by `SP_SNAPSHOT_ENGINE_HEALTH` (Refresh Task 23). The SYSTEM section reads its statuses to tell a NEW RED from a standing one. |
| `T_FAMILY_SEAT_REGISTER` | The family seat register's once-per-pass image, built by `SP_REFRESH_CUBE_TABLES` step 0c. The SEATS section reads it — not the live view — so the brief, the Weekly Run front page and the `SeatRegister` cube all quote one image. Spec: `architecture/FAMILY_SEAT_REGISTER.md`. |
| `SP_ENGINE_PREFLIGHT` | Not a brief object, but the brief now reads its verdict. Nothing reaches PLANNED that the gate refused. Spec: `architecture/ENGINE_PREFLIGHT.md`. |

## The daily ritual

```sql
SELECT section, source, campaign_name, item, action, from_value, to_value, status, detail
FROM `onyga-482313.OI.V_DAILY_BRIEF`
ORDER BY section_rank, campaign_name;
```

- **PLANNED** — the latest snapshot, **gate-filtered**: what the engine wants done today, per
  engine, verbatim reasons, **one price per (campaign, keyword, lever)**. A `REVIEW` row is on the
  list but leads with the gate's caution, because it is exportable only after human eyes.
- **SKIPPED** — the instructions the gate refused, each with the gate's own plain sentence and the
  value it wanted. Recorded, never deleted; just not offered as a price to copy.
- **HAPPENED** — everything applied in the last 48h. `status='planned'` means the engine proposed
  that exact key on the day it was applied; `unplanned` means manual or engine-silent — the raw
  material of the manual-divergence doctrine ("if i change something manually … we need to fix the
  model").
- **VERDICT_NEW** — scorecard verdicts that became *readable* in the last 3 days. **The lag is the
  instrument**: a change is graded on [T+1, T+7] and read no earlier than T+14 (SB [T+1, T+14],
  read T+21). Early reads systematically under-read your own change and manufacture churn — so
  "what actually happened" arrives on a delay, by design, the morning it is finally honest.
- **SEATS** — the 80/20 doctrine read, one plain line per **working** family (v27.123,
  2026-08-23; family seat register Task 4). Not a sixth list of instructions: the other five
  sections answer *what was planned, what happened, what needs a hand*, and this one answers the
  standing question underneath them — is each working family still spending 80% of its money on
  keywords that are winning, at their bar, or waiting for a verdict? The row shape carries it
  without stretching: `campaign_name` is the family, `from_value` what the 20% side COSTS,
  `to_value` what it is ALLOWED to cost, `status` the doctrine status, `item` what that side is
  made of, `detail` the sentence.

  **It proposes nothing, and that is a rule rather than an omission.** The gap-closure arithmetic
  (ruling R-l in the seat register's SOP) is stated once in `V_FAMILY_SEAT_REGISTER` and asserted
  once there; a second place doing it is a second place for it to drift. So the line names no book,
  restates no projection, promises no recovery, and its closing clause sends the reader to that
  family's own rows. It also names no campaign and no keyword, which is why the holdout rule has
  nothing to mark on it.

  **It reads an image, and says which one.** The source is `T_FAMILY_SEAT_REGISTER`, built once per
  pass. Building a leak book or marking one uploaded moves the LIVE register — its day-one horizon
  reads the pending change log — before it moves this line, so every SEATS row prints the ads
  window it was measured on and the keyword snapshot it came from. A reader who acted since the
  last pass can see that the line has not seen it yet.

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

- **SYSTEM** — one line, always present (v27.152, 2026-10-01; section_rank 7, appended): how many
  of `V_ENGINE_HEALTH`'s checks are RED and which, with the board's own detail quoted for the two
  that mean **a night was not saved** — `plan_partition_fresh` (the last plan date and the nights
  missing) and `pipeline_step_failing` (the failing step, the first 120 characters of its latest
  error, the length of the streak) — and every other RED named by name. `campaign_name` is
  `V_ENGINE_HEALTH` (where to read on), `from_value` the RED count, `to_value` 0 (a quiet board
  is the goal state), `status` RED iff any check is RED. The action says A NIGHT WAS NOT SAVED when
  either alarm is RED, because that is the one state in which PLANNED above is quoting a plan
  older than it looks.

  **Why it is here and not only on the board.** `SP_BUILD_NEXT_WEEK_PLAN` failed every pass from
  2026-08-29 to 2026-09-28. `LOG_PIPELINE_RUNS` logged every failure, the Admin sidebar dot
  reflected it, and this query — the one Ori reads every morning — said nothing. The board already
  carried three REDs nobody acted on, so a RED there is necessary and not sufficient; this line is
  the sufficient half. It reads the board LIVE, never an image, because an image goes stale exactly
  when the pipeline that builds it stops — the failure it exists to report. The cost is one more
  read of the board inside the brief (one `V_CHANGE_SCORECARD` arm beside the brief's own two);
  measured at deploy and recorded in the task report, not pinned here.

  **One row, always.** On a healthy board it reads `SYSTEM: 0 checks RED` with the last plan date
  and the last run, so a reader can tell "quiet because healthy" from "quiet because the line
  broke"; on an empty board it says the board is empty rather than that nothing is wrong.
  Asserted, with its negative controls as standing checks, by
  `scripts/bigquery/tests/PLAN_HEALTH_acceptance.sql` (C04, C05, C07).

  **What is NEW (v27.163, 2026-10-03, money-plan piece-1 Task 9).** The v27.152 line named each RED
  with no date, so it could not say which one was new — the board carried the same three REDs on
  2026-10-01 and in its first snapshot on 2026-10-03, and a fourth would have read like them. The
  line now reads the
  board's memory, `FACT_ENGINE_HEALTH_HISTORY` (one row per check per orchestrator pass, written by
  `SP_SNAPSHOT_ENGINE_HEALTH` as the pass's last step; `ENGINE_HEALTH.md`). For each RED check,
  `red_since` is the earliest snapshot of the current unbroken RED run; a snapshot on which the
  check was GREEN, AMBER, INFO or absent breaks the run. The RED part of the line is then:

  - `NEW since <time> New York: <check>` for each RED whose run started inside the last 24 hours
    (the brief is read once a day) on a snapshot after the memory's first, or
    `NEW since the last snapshot (<time>): <check>` for a RED that was not RED on the latest
    snapshot; `nothing NEW in the last 24 hours` when there is none;
  - then `standing: <check> since <date>, …`. A run that reaches back to the memory's first
    snapshot may have begun before it and reads `since <date> or earlier` — so on the first
    morning of the memory the REDs older than it read as standing, not new.

  The three alarms — `pipeline_step_failing`, `plan_partition_fresh` and (v27.163)
  `plan_pass_failed` — are quoted with the board's detail wherever they appear; `plan_pass_failed`'s
  first clause (the latest plan run) joins the healthy line. The action says **A PLAN PASS FAILED**
  when it is RED and neither night alarm is. With an empty memory the line lists the REDs as before
  and says the memory is empty rather than calling everything new. Every line, green or red, ends
  with the memory's size and span (`the board's memory: N snapshots, <first> to <last> New York`), so
  a reader can see the snapshots stop. The board is still read once; the memory is a small table.
  Asserted by `PLAN_HEALTH_acceptance.sql` A1f, A2a–A2f and C04f (the twin's live rendering equals
  the deployed row).

  **The learning checks (v27.176, 2026-10-04, learning-contract piece 2 Task 6).** The board's two
  RED-able learning checks follow the three alarms in the line's order — `prediction_grades_fresh`
  fourth, `prediction_regression` fifth, every other check after — and their detail is quoted too, so
  a RED one says which nights went ungraded, or which weeks got worse and which rule or builder
  version changed between them, without opening the board (`LEARNING.md` §6, `ENGINE_HEALTH.md`). The
  action is unchanged: a RED learning check reads NEW or standing like any other. Asserted by
  `PLAN_HEALTH_acceptance.sql` P4a (quoted, on a board with it doctored RED) and P4b (the order).

## One keyword, one price (v27.102, 2026-08-21)

The bulksheet is built **by hand** off PLANNED. So a keyword appearing twice there at two prices
does not mean the list is untidy — it means the bid that reaches Amazon is decided by which line
the eye landed on first.

This view read the very table `SP_ENGINE_PREFLIGHT` stamps its verdict onto, and never read the
verdict column. Every collision loser the gate had already refused was printed in PLANNED beside
the instruction that beat it, at its own price, with nothing on the row to say it had lost.

The gate was never broken. It resolves every contention to one surviving instruction, and on the
day this was found the surviving set carried exactly one price per key. It resolved them onto the
table, and no reader downstream ever asked.

Three places quoted a price; all three now quote the survivor:

1. **PLANNED** lists exportable instructions only — `verdict` `GO` or `REVIEW`, or none at all.
2. **HAPPENED's** *"the engine proposed N"*. It joined the raw proposal table on
   (day, campaign, keyword) with no verdict test **and no lever test**, so a hand change on a
   contended keyword printed once per proposing engine, each line quoting a different number —
   and a campaign-grain change (`keyword_id` NULL) matched every NEGATE in the campaign, marking
   hand pauses "planned" on the strength of a search-term block and printing a blank sentence
   while it did it.
3. **ACTION_ITEM's** CONFLICT clause, which demotes a scorecard restore to `REVIEW` because "a
   live engine outranks the remedy". A refused instruction is not a live engine, and the same
   missing lever test let a search-term block demote a campaign-budget restore.

**Fail open** everywhere: `COALESCE(verdict, 'GO') != 'EXCLUDE'`. A partition written before
verdicts existed, or one the gate has not stamped yet, still reads as a plan — the brief must not
go blank because a procedure did not run.

## The SEATS section (v27.123, 2026-08-23)

Asserted by `scripts/bigquery/tests/SEAT_SURFACE_acceptance.sql` (C01–C04, C09, C10) and the file
checker `scripts/bigquery/tests/check_seat_surface_labels.py`. Two properties of that suite are
worth borrowing anywhere else in this view:

1. **A surface is never asked to confirm itself.** Every figure is re-derived from the register's
   own per-row rows and only then compared with what the line printed. The dollar comparisons carry
   a `$0.02` tolerance whose reason is stated on the check — an aggregate rendered to two decimals
   against a sum of per-row rounded costs; the count comparisons are exact, because a count has no
   rounding.
2. **An empty population is a violation of the check that reads it.** The first run of that suite,
   before the section existed, reported five green checks against nothing at all.

**Nothing may render blank.** The label CASE names every `doctrine_status` the register can emit —
`IN`, `AT_LINE`, `OUT`, `NO_SPEND`, `REFERENCE` — and its fall-through is a sentence, not a value.
Every `FORMAT` argument is `COALESCE`d, because `CONCAT` with one NULL argument returns NULL, and a
blank line is worse than a wrong one: it tells the reader nothing, including that anything is wrong.
The file checker fails the build if a status is added to the register's own CASE and not learned here.

**Standing assertion.** `V_ENGINE_HEALTH.plan_price_ambiguity` asks the question of the proposal
table (cheap, deployed, on the board). `scripts/bigquery/check_one_price_per_key.py`, wired into
`scripts/run_tests.sh`, asks it of the proposal table **and of PLANNED itself** — the second is
what would have caught this, because on the day it was found the table was clean and the list was
not. Both were proven to fire by re-deploying the pre-change view on purpose.

`section_rank` renumbered, order unchanged: PLANNED 1, SKIPPED 2, HAPPENED 3, VERDICT_NEW 4,
ACTION_ITEM 5. SEATS was APPENDED at 6 in v27.123, so all five keep their numbers and the ritual
query is byte-identical above the new section.

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
