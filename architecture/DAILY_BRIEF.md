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
