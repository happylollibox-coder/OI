# ENGINE_PREFLIGHT — the standing contradiction gate

**Born:** 2026-08-15 (engine-finalization plan Task 1.1). **Why:** the one-off iteration-6 audit cut
upload contradiction from 29.9% to ~4%, and manual preflights have now killed two bad batches in
two attempts (iteration-6; the 27 stale restores of 2026-08-15). A check that only runs when
someone remembers to run it is not a gate. This makes it permanent, mechanical, and cheap.

## Objects

| object | role |
|---|---|
| `SP_ENGINE_PREFLIGHT` | Judges the day's proposal snapshot. Reads ONLY small tables (`FACT_ENGINE_PROPOSALS` + `FACT_KEYWORD_GUARD`) — never the ceiling views — so it runs in seconds. Writes `T_ENGINE_PREFLIGHT` and stamps `verdict`/`verdict_reason` back onto the day's `FACT_ENGINE_PROPOSALS` partition. Orchestrator Task 20.7, immediately after the proposal snapshot (20.6). |
| `T_ENGINE_PREFLIGHT` | The judged day: one row per live instruction with `own_rank`, `n_instr`, `verdict`, `verdict_reason`. |
| `V_ENGINE_PREFLIGHT` | Thin read surface for panels/cube. No logic. |
| `V_HOLDOUT_ARM` | (from 2026-10-05; v27.83 read `DE_HOLDOUT_ASSIGNMENT` directly) The randomized holdout arm that binds today, any trial: one row per control campaign with `gate_from`, `gate_to` and `trial_id`, built from `DE_HOLDOUT_ASSIGNMENT` (written by `SP_ASSIGN_HOLDOUT` at orchestrator Task 20.55, before the proposal snapshot) and the trial registry `V_HOLDOUT_TRIAL`. Read here as a third exclusion source. Spec: `architecture/HOLDOUT.md`. |

## The checks (in verdict precedence order)

1. **SINGLE OWNER** — conflict domain is (campaign, keyword, **lever**) where lever = BID or
   BUDGET (a bid and a budget on the same key are two levers, not a conflict; a REVIVE and a BID
   on the same keyword are the same lever). Engine precedence: **LOW_STOCK > LAUNCH > OOB >
   REVERDICT > LIFT**. When more than one engine instructs the same (key, lever), the highest
   engine keeps its verdict; every other row is `EXCLUDE` with the owner named.
2. **NO-OP** — |suggested − current| ≤ 0.005 → `EXCLUDE` (engines carry their own no-op guards;
   this is the belt after their suspenders).
3. **SETTLED-WINNER CUT** — a bid cut on a key whose settled record is ≥ 1.2× at ≥ 10 settled
   clicks (`FACT_KEYWORD_GUARD`) → `REVIEW`, never auto-shipped. The FIT_CPC incident is the
   type specimen: the cut may still be right, but human eyes are the price of cutting a winner.
4. **HOUSE BID CAP** — suggested bid > $2.00 → `REVIEW`.
5. Everything else → `GO`.

### 0. HOLDOUT — a third, independent exclusion source (v27.83, 2026-08-19)

Checked **before** all of the above, and it is not an engine-quality judgement at all.

`V_HOLDOUT_ARM` (the arm that binds today, any trial) says this campaign is a randomized
**measurement control**: it was drawn by coin flip to be left alone for 16 weeks so we can find out
what the engine is actually worth. Nothing may be exported to it on **any** lever — bid, budget
**and** negate — while its arm binds (`CURRENT_DATE('America/Los_Angeles') BETWEEN gate_from AND
gate_to`; trial 2: 2026-10-05 .. 2027-01-26; trial 1 bound 2026-09-01 .. 2026-10-04 and is archived).
`T_ENGINE_PREFLIGHT.holdout_trial_id` is the arm's `trial_id`. Verdict `EXCLUDE`, reason in plain
words:

> *skipped — this campaign is a measurement control: it was randomly chosen to be left alone so we
> can tell what the engine is actually worth, and no bid, budget or negative may be uploaded to it
> until the trial ends*

**THE PROPOSAL IS STILL RECORDED.** This gate has never deleted a row and does not start now. The
holdout campaign's instruction stays in `FACT_ENGINE_PROPOSALS` with its intended action and its
verbatim reason; only the verdict says `EXCLUDE`. **That record is the counterfactual** — it is what
lets `V_HOLDOUT_READOUT` compare *"the engine wanted to cut AND we cut"* against *"the engine wanted
to cut AND the coin said don't"*. Without it the holdout arm degrades from "campaigns the engine was
forbidden to move" into "campaigns nothing happened to", which is a different and much weaker
question. **Block the export, never the judgement.**

Boundaries, each deliberate:

- **All levers**, unlike the claim arm. A negative keyword is a real intervention with a real dollar
  effect; letting negates through would make the holdout arm "the engine minus its bid levers" and
  the readout would silently measure the wrong thing.
- **Time-bounded.** Empty before `gate_from` and empty again after `gate_to`, with no code change
  either time. The gate opens a day before the window (`gate_from` = the assignment day) because the
  first pass of a New York day judges under the previous Los Angeles date. Measured 2026-08-19 (trial
  1, then read from `DE_HOLDOUT_ASSIGNMENT` between `eligible_from` and `trial_end`): 0 rows affected
  that day; the same proposal set inside the window would exclude 25 rows (14 BID, 11 NEGATE) across
  the 14 holdout campaigns.
- **Fails open.** `LEFT JOIN` + `IS NOT NULL`: a missing table, an empty trial or an unassigned
  campaign never silences legitimate work. An empty trial registry empties `V_HOLDOUT_ARM`, and
  `V_ENGINE_HEALTH` `holdout_unit_changed` then reads RED ("no HOLDOUT unit"), so that failure is not
  silent.
- **Ordered first.** When a holdout row is also a collision loser both reasons are true, but only
  this one explains why the campaign will not move for four months.
- **`TREATED` campaigns get no special handling of any kind.** Treatment *is* the status quo.
- It reuses the existing `EXCLUDE` verdict on purpose, so `DoPage.exportBulksheet`'s refusal
  enforces it with **no dashboard change**.
- `T_ENGINE_PREFLIGHT` publishes `is_holdout` / `holdout_trial_id` so an audit can tell a HOLDOUT
  exclusion from a CLAIM or COLLISION one without re-deriving either.

Full design, the honest limits and what invalidates the trial: **`architecture/HOLDOUT.md`**.

## The contract with the generator

`DoPage.exportBulksheet` (the only bulksheet path) must, at export time, fetch the latest
preflight and **refuse to write any queue item whose (campaign, keyword, lever) is `EXCLUDE`**,
showing the user exactly what was refused and why. `REVIEW` rows export only after an explicit
per-item confirmation. The generator refusing EXCLUDE rows is the entire point of the object —
a verdict nobody enforces is a comment.

## The other half of the contract: the verdict has to REACH a reader (v27.102, 2026-08-21)

A verdict nobody enforces is a comment — and so is a verdict nobody *reads*. `V_DAILY_BRIEF`'s
PLANNED section, the list Ori builds the hand bulksheet from, read `FACT_ENGINE_PROPOSALS` and
never read the `verdict` column this procedure stamps onto it. Every collision loser appeared on
the morning list beside the instruction that beat it, at its own price. On one BALL auto target
three engines each offered a different bid and nothing on any row said which had won.

`ownership_overlaps` was GREEN throughout, correctly: it measures `T_ENGINE_PREFLIGHT`, where the
contention *was* resolved. **The gate table being right is not the same as the reader being right.**
So the standing assertion added with the fix measures both — `plan_price_ambiguity` on the proposal
table (V_ENGINE_HEALTH, deployed) and the same question asked of PLANNED itself
(`scripts/bigquery/check_one_price_per_key.py`, in `scripts/run_tests.sh`).

Anything new that reads `FACT_ENGINE_PROPOSALS` and shows a value to a human owes the same filter:
`hold_source IS NULL AND COALESCE(verdict, 'GO') != 'EXCLUDE'`, failing open on an unstamped row.

## Honest limits

- The gate judges what the snapshot saw. An instruction born after the day's snapshot (a manual
  queue add, a same-day view fix) carries no verdict — the generator treats no-verdict as GO and
  the next snapshot judges it. The 15-min-TTL panels and the daily snapshot can therefore
  disagree for part of a day; the upload-time fetch of the LATEST preflight bounds the exposure.
- NEGATE instructions ARE snapshotted and judged since v27.72 (2026-08-17, Ori: "close the
  negate gap"). Their conflict key is `(campaign_id, term|<lowercased term>, NEGATE)` — negates
  have no keyword_id, so the term text itself is the key; the verdict stamp-back join carries
  `target_text` for the same reason. Sources: V_OOB_SEARCH_TERM `is_negate` (engines OOB/LIFT)
  and V_WEEKLY_RUN_NEGATIVE (engine COACH, lowest precedence). A duplicate negate across engines
  is the SAME action, not a contradiction — the gate keeps the owner's row and EXCLUDEs the rest
  ("one negative per term per day"). A term that converted in past gift peaks arrives with
  `season_relax_applied=TRUE` and is judged REVIEW, never a silent GO — first live day it caught
  the coach proposing to block "journal for girls" (47 peak orders). The generator judges NEGATE
  items by the same key, with no value clause (a negate has no value).
- The ADD_KEYWORD lever (research-mode "+broad" offers) is now the one unsnapshotted lever.
- Verdicts also land on `FACT_ENGINE_PROPOSALS.verdict`, so the proposal history doubles as the
  contradiction-rate time series (`V_ENGINE_HEALTH` check #1 reads it).
- **Veto holds are skipped by the gate (v27.98, 2026-08-21).** Rows carrying `hold_source` — the
  last-day veto's held proposals, now RECORDED in `FACT_ENGINE_PROPOSALS` instead of erased — do
  not enter `T_ENGINE_PREFLIGHT`. They are not instructions to judge: they carry no value, so every
  value test here would read them as no-ops and overwrite the veto's own sentence, and — the real
  hazard — they would join the single-owner contention as live instructions, where a held OOB row
  could outrank a real LIFT one and leave the keyword untouched by an engine that was ready to act.
  Skipping them is also what keeps a held row out of the cube, the decisions feed and
  `DoPage.exportBulksheet`: it can be read in the history and reach Amazon by no path at all. Their
  `verdict` (`EXCLUDE`) and `verdict_reason` (the veto's own sentence) are written by
  `SP_SNAPSHOT_ENGINE_PROPOSALS`; the stamp-back UPDATE excludes them explicitly, so a future
  join-key change cannot quietly overwrite the sentence. The contradiction rate is therefore
  unaffected by labelling — a held row is not two engines disagreeing. Spec:
  `architecture/DAILY_BRIEF.md` §"The last-day veto is recorded, not erased".
