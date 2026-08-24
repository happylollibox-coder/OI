# Three Layers — Gap Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the 23 live violations in `architecture/THREE_LAYERS.md` §8 so that the Catalog answers worth (not commands), the Brain funds the answers it demands, and Pacing executes inside a ceiling that binds — in dependency order, memory first, safety before throughput.

**Architecture:** Three layers already exist as separate BigQuery objects: the Catalog (`SP_SNAPSHOT_KEYWORD_STATE` → `FACT_KEYWORD_STATE`, `V_KEYWORD_GUARD`, `T_FAMILY_BAR`), the Brain (`V_PLAN_WINDOW_JUDGMENT` → `SP_BUILD_NEXT_WEEK_PLAN` → `FACT_PLAN_NEXT_WEEK`) and Pacing (`SP_SNAPSHOT_ENGINE_PROPOSALS` → `SP_ENGINE_PREFLIGHT` → `T_ENGINE_PREFLIGHT`, plus the books in `tools/`). This plan does not re-architect them. It (a) starts two unbackfillable clocks on day one, (b) makes the Brain's ceiling bind on Pacing before admitting any new spend into the system, (c) widens the Catalog's population and its calendar, (d) gives the Brain a vocabulary that has no "nothing to do" in it, and (e) only then replaces the average price with a marginal one and lets the Brain propose what it does not already own. Every layer keeps its narrow contract; improvements happen behind it.

**Tech Stack:** BigQuery Standard SQL (project `onyga-482313`, dataset `OI`, location `US`), deployed with the `bq` CLI. Python 3 at `/usr/local/bin/python3` with `pytest`, `PyYAML` and `openpyxl` for the bulksheet generators in `tools/`. Registry in `config.yaml`. Acceptance suites are standalone `.sql` files in `scripts/bigquery/tests/`, every row of which must read `PASS`.

---

## How to read and run this plan

**House deploy line — memorise it. Never `cat` a `.sql` file into `bq`:**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
```

**STEP 0 OF EVERY TASK — BACK UP EVERY FILE THE TASK LISTS UNDER `Modify:`.** This is a numbered,
non-skippable step of **every** task in this plan, whether or not that task's own step list opens
with one. Several tasks below spell the backup out; the ones that do not are not exempt — they are
abbreviated, and this rule is what they abbreviate. The house convention stamps the file with the
next unused `v27` number and the time. Derive the number, never guess it. Run this, verbatim, with
the task's own `Modify:` paths substituted into `FILES`:

```bash
cd /Users/ori/Develop/OI
NEXT=$(ls scripts/bigquery/**/*.bak.v27.*.* docs/superpowers/plans/*.bak.v27.*.* 2>/dev/null \
       | sed -E 's/.*\.bak\.v27\.([0-9]+)\..*/\1/' | sort -n | tail -1)
NEXT=$((NEXT + 1)); echo "next version: v27.$NEXT"
# FILES = every path this task lists under **Modify:** that already exists in the repo.
FILES="scripts/bigquery/views/V_BID_FLOOR.sql scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql"
for f in $FILES; do
  [ -f "$f" ] && cp "$f" "$f.bak.v27.$NEXT.$(date +%H%M)" && echo "backed up $f"
done
```

Bump `NEXT` by one for each subsequent backup in the same session. `config.yaml` and files being
CREATED are not backed up; everything else under `Modify:` is. If a task's step list has no explicit
backup step, run the block above before its first step anyway — the tasks that omit it are
`2.4`, `5.3`, `5.5`, `5.6`, `6.2`–`6.9`, `7.3`–`7.6`, `8.2`, `8.6`, `8.7`, `9.3`, `9.5`, `10.3`,
`11.4`, `13.4` and `13.5`, and every one of them re-deploys a live object.

**Running an acceptance suite.** Suites in `scripts/bigquery/tests/` are standalone. There is **no aggregator** — `RUN_ALL_TESTS.sql` and `tests_manifest.json` in that directory belong to a legacy `SP_MERGE_SQP_WEEKLY` suite about `FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` and must not be edited by this plan. Run a suite exactly the way `FACT_PLAN_NEXT_WEEK_acceptance.sql` documents in its own header:

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql)"
```

Every row must read `PASS`. Substitute the suite's own filename; every suite in that directory runs
by exactly this line, and each carries it in its own header.

**Running the Python tests:**

```bash
/usr/local/bin/python3 -m pytest tools/tests/ -q
```

**Registry.** Every BigQuery object this plan creates gets a `config.yaml` entry in the right section (`views:` / `tables:` / `stored_procedures:` / `functions:`), inserted **next to its neighbours, never appended at the end of the file**, and committed as a filtered patch of your own hunks. Verify after each edit:

```bash
/usr/local/bin/python3 - <<'PY'
import yaml, collections
d = yaml.safe_load(open('/Users/ori/Develop/OI/config.yaml'))
for sec in ('views','tables','stored_procedures','functions'):
    names = [e['name'] for e in d[sec]]
    dupes = [n for n,c in collections.Counter(names).items() if c > 1]
    print(sec, len(names), 'duplicates:', dupes)
PY
```

Expected: four lines, `duplicates: []` on each.

**House precedent for registering a table written by a procedure:** `FACT_KEYWORD_STATE` is registered under `stored_procedures:` (index 35) with `source_files: [scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql]`, and `V_KEYWORD_STATE` sits beside it at index 36. `T_FAMILY_BAR` is the counter-example, registered under `tables:` (index 132) because `SP_SNAPSHOT_FAMILY_BAR` has its own entry. Each task below says which precedent it follows.

**Files another session owns. Never stage, revert or commit these:**

- `dashboard-react/src/pages/PlanPage.tsx`
- `scripts/bigquery/procedures/SP_MERGE_PRODUCT_DIM.sql`
- `scripts/bigquery/views/V_FORECAST_DEMAND.sql`
- `docs/superpowers/specs/2026-07-19-launch-ramp-forecast-design.md`

Every `git add` in this plan names its files explicitly for exactly this reason. Never `git add -A`, never `git add .`.

**Standing Rule 0.** Mechanism in prose, queries for numbers. No pinned measurement in an SOP, a file header or a registry description. Declared constants are exempt. **This plan itself is exempt** — the dated figures below come from `docs/superpowers/specs/2026-08-24-three-layers-baseline.md` and are cited so a re-run is a re-run.

**Never upload to Amazon.** Books land `PENDING_UPLOAD` in `FACT_PPC_CHANGE_LOG` and are for Ori. `--mark-uploaded` and `--supersede` act on `PENDING_UPLOAD` rows only. No code path issues a `DELETE` against that table.

**FINAL STEP OF EVERY TASK WHOSE TITLE NAMES A VIOLATION — STRIKE IT IN §8.** A violation closed in
code and left standing in `architecture/THREE_LAYERS.md` §8 leaves the top document lying about the
system, and §8's *"How to add an entry"* is explicit: **amend the table in the same commit as the
change**. §8 already carries the house format — violations 12 and 16 are struck through with a dated
`**CORRECTED**` note. Closing one uses the same shape, with `CLOSED` in place of `CORRECTED`:

```markdown
7. ~~It ignores the Catalog, judging on its own window; a quiet window yields `NOT_SERVING` — the
   "nothing to do" state this doctrine forbids.~~ **CLOSED 2026-08-25 (Task 6.2): the verdict CASE's
   bare `ELSE 'NOT_SERVING'` now yields the Catalog's own answer in five named arms. 51.8% of the
   live plan was in that state on 2026-08-24; the acceptance suite asserts it is now zero.**
```

Add `architecture/THREE_LAYERS.md` to that task's `git add` line and name the closure in the commit
body. **A violation is struck only when the task that closes it has gone green** — never on the task
that merely prepares it, and never on a half-closure. Where a phase closes one violation across two
tasks (7 and 14 and 22 each do), the strike goes on the **second**, and the first says so.

The tasks this binds, by the violation each closes: `1.2`+`1.4` (15), `1.3` (16's live half),
`2.2`+`2.4` (4's Catalog-side population), `3.3`–`3.5` (23), `4.5`+`7.6`+`7.7` (22), `5.5`+`5.6` (2),
`6.2` (7), `6.3`+`10.6` (11), `6.4`+`6.5` (8), `6.6`+`6.9` (9), `6.7` (14), `10.8` (6's grading half
— 6's retention half was struck on 2026-08-24 by another session, so `10.8` AMENDS that entry rather
than striking it again), `0.5`+`0.6`+`10.4` (13), `7.2` (19), `7.4`+`7.5` (20), `8.2`+`8.3` (1),
`8.6` (10), `9.3` (25), `9.4`+`9.5` (24), `10.3` (3 and 17), `11.3`+`11.4` (21), `12.3`+`12.4` (5),
`13.4`+`13.5` (18). **Task 13.7 verifies at the end that none was missed** and is the only place the
list above may be treated as complete.

---

## File Structure

**One file spans every phase.** `docs/superpowers/specs/2026-08-25-gap-closure-measurements.md` is
the running record of every red measurement this plan takes, created by the first measurement task
that reaches its commit step and appended to by each one after it. It exists for the same reason
`docs/superpowers/specs/2026-08-24-three-layers-baseline.md` exists: a recheck must be a re-run and
not a fresh argument, and a fix cannot be shown to have worked against a number nobody wrote down.


### Phase 0 — memory

| file | responsibility |
|---|---|
| `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql` *(modify)* | idempotent temp tables; append today's snapshot to the history table |
| `scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql` *(create)* | full daily append of every Catalog answer, partitioned by `snapshot_date` |
| `scripts/bigquery/views/V_CATALOG_DWELL.sql` *(create)* | how long a subject has been in its state, and how overdue its appointment is |
| `scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql` *(create)* | the Catalog's first acceptance suite — grain, ladder set, floors, appointments |
| `scripts/bigquery/procedures/SP_SNAPSHOT_ENGINE_PROPOSALS.sql` *(modify)* | record what each proposed bid was expected to deliver |
| `tools/build_reprice_bulksheet.py` *(modify)* | stop throwing the book's own prediction into a `.tmp` CSV; persist it |
| `scripts/bigquery/tables/FACT_PPC_CHANGE_LOG.sql` *(modify)* | four explicit prediction columns |
| `tools/tests/test_change_log_discipline.py` *(modify)* | the new prediction columns are logged on every bid row |

### Phase 1 — precedence and a binding ceiling

| file | responsibility |
|---|---|
| `scripts/bigquery/functions/FN_MOVE_CAP.sql` *(create)* | the one move cap, asymmetric by direction and confidence, callable from SQL |
| `scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql` *(modify)* | read the Catalog price and the Brain's ceiling; EXCLUDE a proposal above it |
| `tools/build_reprice_bulksheet.py` *(modify)* | the book's priced row wins over an engine instruction, not the reverse |
| `scripts/bigquery/tests/ENGINE_PREFLIGHT_acceptance.sql` *(create)* | no GO bid exceeds its ceiling; every EXCLUDE names the layer that set it |
| `tools/tests/test_reprice_precedence.py` *(create)* | the inverted deference, unit-tested without a warehouse |

### Phase 2 — everything that spends is judged

| file | responsibility |
|---|---|
| `scripts/bigquery/views/V_KEYWORD_GUARD.sql` *(modify)* | a spend-derived arm beside the config-derived one; `universe_source`, `serving_blocked_reason` |
| `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql` *(modify)* | `subject_key`, `NO_RECORD`, `bar_missing`, campaign-scoped ad-group resolution |
| `scripts/bigquery/views/V_KEYWORD_STATE.sql` *(re-deploy)* | `SELECT *` — must be re-run in the same step as every column addition |
| `scripts/bigquery/tests/CATALOG_COVERAGE_acceptance.sql` *(create)* | every spending key is in the Catalog or named by a priced exclusion |

### Phase 3 — campaign identity

| file | responsibility |
|---|---|
| `scripts/bigquery/views/V_CAMPAIGN_IDENTITY.sql` *(create)* | every name a campaign has carried; the one place a history join goes |
| `scripts/bigquery/views/V_PEAK_STUCK_CAMPAIGNS.sql` *(modify)* | reactivation decided on an id-keyed lifetime pool |
| `scripts/bigquery/views/V_PAUSED_CAMPAIGN_HISTORY.sql` *(modify)* | season classification from the full name history, not today's name |
| `scripts/bigquery/views/V_ADS_COACH.sql` *(modify)* | publish `holiday_match_is_name_derived` so a fragile classification says so |
| `scripts/bigquery/views/V_CAMPAIGN_FAMILY_MAP.sql` *(modify)* | demote the name-prefix arm below the ASIN arm |
| `scripts/bigquery/tests/CAMPAIGN_IDENTITY_acceptance.sql` *(create)* | no campaign-history aggregation groups on `campaign_name` |

### Phase 4 — the campaign becomes a subject

| file | responsibility |
|---|---|
| `scripts/bigquery/views/V_CAMPAIGN_FAMILY_MAP.sql` *(modify)* | all campaigns, all history — the prerequisite for any seasonal answer |
| `scripts/bigquery/tables/FACT_CAMPAIGN_STATE.sql` *(create)* | the campaign-grain answer, with history from day one |
| `scripts/bigquery/procedures/SP_SNAPSHOT_CAMPAIGN_STATE.sql` *(create)* | builds it nightly, DELETE-today-then-INSERT |
| `scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql` *(modify)* | one new task slot, after 20.5g-1 and before 20.8c |
| `tools/build_campaign_reopen_bulksheet.py` *(create)* | the OPEN arm as a book: enable a campaign, carry its reopen date |
| `tools/build_restore_campaign_reopen_bulksheet.py` *(create)* | its restore generator |
| `scripts/bigquery/tests/FACT_CAMPAIGN_STATE_acceptance.sql` *(create)* | one row per campaign per day; every CLOSE carries a reopen date |

### Phase 5 — seasonality reaches the verdict

| file | responsibility |
|---|---|
| `scripts/bigquery/views/V_KEYWORD_SEASON_WINDOW.sql` *(create, then rewritten)* | instance-grain evidence reaching 364+ days back; Task 5.4 turns it into a call to the function below at the standing window |
| `scripts/bigquery/functions/FN_CATALOG_SEASON_WINDOW.sql` *(create)* | `ask(window_from, window_to)` — a table function, so asking records nothing (§1.4) and two callers may hold two windows |
| `scripts/bigquery/tables/DE/DE_CATALOG_WINDOW_REQUEST.sql` *(create)* | the **standing** window the nightly snapshot answers for — a setting (§3.3), not the parameter of a question |
| `scripts/bigquery/views/V_KEYWORD_CONTEXT_GATE_BY_SUBJECT.sql` *(create)* | the subject-grain season gate, wired into the ladder so auto modes and product targets reach a verdict |
| `scripts/bigquery/procedures/SP_SNAPSHOT_SEASON_VERDICT.sql` *(modify)* | write ids beside the text so the season memory stops blending families |
| `scripts/bigquery/views/V_KEYWORD_GUARD.sql` *(modify)* | join the season memory on ids |
| `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql` *(modify)* | the seasonal arm of the ladder; `NOT_WORTH_NOW` |
| `tools/build_reprice_bulksheet.py` *(modify)* | delete the book's `SEASON_BLOCKED` arm — the Catalog owns it now |

### Phase 6 — the Brain

| file | responsibility |
|---|---|
| `scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql` *(modify)* | no `NOT_SERVING` fall-through; seat priced on the answer; rank on shortfall |
| `scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql` *(modify)* | mirrored candidacy and ordering; park re-test; seasonal park; seat deadline |
| `scripts/bigquery/tables/DE/DE_PLAN_CONFIG.sql` *(modify)* | four new settings, two of them Ori's open rulings |
| `scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql` *(modify)* | `revisit_date`, `reopen_date`, and the columns the re-test needs |
| `scripts/bigquery/views/V_PLAN_SCORECARD.sql` *(create)* | the Brain's scorecard — named in four documents, built nowhere |
| `scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql` *(modify)* | C06, C10, C13 **and C14** widened in the same change — C14 enumerates the legal moves a second time |
| `scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql` *(modify)* | C21 re-based off the product form |
| `scripts/bigquery/tests/PLAN_CONFIG_acceptance.sql` *(modify)* | C09 covers the new settings |

### Phase 7 — confidence

| file | responsibility |
|---|---|
| `scripts/bigquery/views/V_KEYWORD_STABILITY.sql` *(create)* | the share of a record that came from composition still present |
| `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql` *(modify)* | `separation`, `stability`, `confidence`, `confidence_band` |
| `scripts/bigquery/procedures/SP_SNAPSHOT_CAMPAIGN_STATE.sql` *(modify)* | the same four columns at campaign grain |
| `scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql` *(modify)* | no irreversible action below HIGH |
| `tools/build_reprice_bulksheet.py` *(modify)* | the same gate on the book's PAUSE row |
| `tools/build_campaign_close_bulksheet.py` *(create)* | the CLOSE intent gets hands: pause it, carrying the reopen date |
| `tools/build_restore_campaign_close_bulksheet.py` *(create)* | its restore generator |

### Phase 8 — the four-field contract

| file | responsibility |
|---|---|
| `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql` *(modify)* | publish `verdict`, `ceiling_cpc`, `confidence`, `expected_clicks` |
| `tools/build_reprice_bulksheet.py` *(modify)* | consume the contract, not the ladder's command words |
| `scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql` *(modify)* | unmask the good side for raises only |
| `scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql` *(modify)* | `LEAN_IN`, and P-4 re-worded to forbid cuts rather than all prices |
| `architecture/THREE_LAYERS.md` *(modify)* | §9's row shape, and the P-4 ruling in the changelog |

### Phase 9 — negatives

| file | responsibility |
|---|---|
| `tools/build_negative_archive_bulksheet.py` *(create)* | the missing arm: `Operation: Update`, `State: archived` |
| `tools/build_restore_negative_archive_bulksheet.py` *(create)* | its restore generator |
| `scripts/bigquery/views/V_CATALOG_IMPROVE.sql` *(create)* | `improve()` — negate ranked beside reprice and park |
| `scripts/bigquery/tables/DE/DE_NEGATIVE_KEYWORDS.sql` *(modify)* | `next_review_date`, `review_reason`, `season_context` |
| `scripts/bigquery/views/V_WEEKLY_RUN_NEGATIVE.sql` *(modify)* | re-ask at expiry instead of never again |
| `scripts/bigquery/procedures/SP_SYNC_NEGATIVES.sql` *(modify)* | tighten the removal key; record `change_id` |

### Phase 10 — the response curve, and two layers graded

| file | responsibility |
|---|---|
| `scripts/bigquery/functions/FN_MATCH_WIDTH.sql` *(create)* | the curve's segment axis, in one place, callable from both the fit and the read |
| `scripts/bigquery/views/V_CLICK_RESPONSE_CURVE.sql` *(create)* | clicks and CPC as a function of bid, per segment |
| `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql` *(modify)* | `ceiling_cpc` from the curve; `ceiling_basis` flips to `MARGINAL` |
| `scripts/bigquery/views/V_PACING_SCORECARD.sql` *(create)* | predicted against delivered, per change |
| `scripts/bigquery/views/V_CATALOG_SCORECARD.sql` *(create)* | was the Catalog's own published ceiling, verdict and appointment right? |
| `scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql` *(modify)* | rank on expected profit at the marginal ceiling **measured against the bar**, discounted by confidence |

### Phase 11 — demand data on probation

| file | responsibility |
|---|---|
| `scripts/bigquery/views/V_SRC_MARKET_VOLUME.sql` *(create)* | the market's totals per (query, week), collapsed correctly |
| `scripts/bigquery/views/V_SUBJECT_MARKET_HEADROOM.sql` *(create)* | market volume, our share, headroom, and the four grounds |
| `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql` *(modify)* | carry headroom; never let it move a verdict alone |

### Phase 12 — rank()

| file | responsibility |
|---|---|
| `scripts/bigquery/views/V_HARVEST_CANDIDATE.sql` *(create)* | proven converting terms with no keyword anywhere |
| `scripts/bigquery/views/V_CATALOG_RANK.sql` *(create)* | ordered candidates, live and new, discounted by confidence |
| `scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql` *(modify)* | fund down the ranked list; a new candidate enters as `TEST` |

### Phase 13 — the vehicle

| file | responsibility |
|---|---|
| `scripts/bigquery/views/V_SUBJECT_VEHICLE.sql` *(create)* | format, placement, creative, match width on the subject |
| `scripts/bigquery/views/V_DEMAND_RECAPTURE.sql` *(create)* | was this query bought elsewhere within 28 days, and through what |
| `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql` *(modify)* | carry the vehicle and the recapture answer |
| `architecture/THREE_LAYERS.md` *(modify)* | the changelog entry, the §10.2 re-pricing, and §8's closed-violation audit (Task 13.7) |

---

## Violation-to-task map

All 23 live violations. Violations 12 and 16 are struck through in §8 as CORRECTED by the baseline and carry no task by design (see **Deliberately not built**).

| # | violation (§8) | phase | task(s) |
|---|---|---|---|
| 1 | Catalog emits commands | 8 | 8.2, 8.3, 8.4 |
| 2 | Catalog is not seasonal | 5 | 5.1 – 5.8 |
| 3 | No marginal model | 10 | 10.1, 10.2, 10.3 |
| 4a | Spending rows outside the Catalog | 2 | 2.1 – 2.4 |
| 4b | No demand data reaches the Catalog | 11 | 11.1 – 11.5 |
| 5 | No `rank(family, window)` | 12 | 12.1 – 12.4 |
| 6 | The Catalog keeps no memory | 0, 10 | 0.2, 0.3, 0.4 (the memory) · 10.8 (the grading the memory exists for) |
| 7 | Brain ignores the Catalog; `NOT_SERVING` | 6 | 6.2 |
| 8 | Seats do not fund the answers they demand | 6 | 6.4, 6.5 |
| 9 | `NOT_WORTH_NOW` does not exist | 6 | 6.6, 6.9 |
| 10 | Turns protected, never funded (`LEAN_IN`) | 8 | 8.5, 8.6 |
| 11 | Ranking uses a proxy | 6, 10 | 6.3 (interim), 10.6 (doctrinal) |
| ~~12~~ | ~~Coverage hole~~ CORRECTED | — | no task, by design |
| 13a | Pacing records no prediction | 0 | 0.5, 0.6 |
| 13b | Pacing is not graded | 10 | 10.4, 10.5 |
| 14 | A park carries no re-test obligation | 6 | 6.6, 6.7, 6.8 |
| 15 | The book defers to Pacing; precedence backwards | 1 | 1.1 – 1.5 |
| ~~16~~ | ~~The move cap is symmetric~~ CORRECTED | — | replacement finding implemented in 1.3, **not** presented as closing 16 |
| 17 | Nothing decides how many clicks to buy | 10 | 10.3 |
| 18 | The Catalog does not know what is advertised | 13 | 13.1 – 13.6 |
| 19 | Drift treated as an auto-mode problem | 7 | 7.2, 7.3 |
| 20 | `confidence` specified, computed nowhere | 7 | 7.4, 7.5 |
| 21 | Market volume used by nothing | 11 | 11.1 – 11.5 (10.8 is the instrument that can raise it off probation) |
| 22a | No campaign verdict — the OPEN half | 4 | 4.1 – 4.8 |
| 22b | No campaign verdict — the CLOSE half | 7 | 7.6 (the intent) · 7.7 (the book that executes it) |
| 23 | Campaign history keyed on name | 3 | 3.1 – 3.6 |
| 24 | `improve()` does not exist; negatives have no owner | 9 | 9.4, 9.5 |
| 25 | No generator can remove a negative | 9 | 9.2, 9.3 |

**Every task in the right-hand column ends by striking its violation in §8** — see the plan header's
`FINAL STEP OF EVERY TASK` rule, and **Task 13.7**, which audits that none was missed and records the
two corrections this plan made to §8's own wording (violations 19 and 21).

**Coverage:** 23 of 23 live violations have at least one task. Violations 4, 11, 13 and 22 each split across two phases because their halves have opposite dependencies; the split is load-bearing and is argued in each phase's opening.

---
## Phase 0 — Start both clocks

> ### ⚠️ RECONCILE BEFORE YOU BUILD — the Catalog's memory SHIPPED on 2026-08-24, from another session
>
> **Violation 6 is already struck through in §8** (commit `ca01597`, changelog row `2026-08-24 21:40`),
> and a second session shipped `V_UNOWNED_SPEND` on 2026-08-25 (`99129ac`) measuring the same
> population Task 2.1 measures. Do **not** rebuild any of it. What exists, verified in the repo and
> the warehouse on 2026-08-25:
>
> | object | where | note |
> |---|---|---|
> | `FACT_KEYWORD_STATE_HISTORY` | `scripts/bigquery/tables/FACT/FACT_KEYWORD_STATE_HISTORY.sql` | **not** the path Task 0.3 names. **Live and NOT empty** — it holds 8 partitions / 6,814 rows (2026-08-17..2026-08-24), seven of them recovered from BigQuery time travel and **not re-creatable**. An earlier version of this row said "live and empty", which was already wrong when written. A second, immutable copy exists: `FACT_KEYWORD_STATE_HISTORY_SEED_20260824`. |
> | `SP_APPEND_KEYWORD_STATE_HISTORY` | `scripts/bigquery/procedures/` | a **separate orchestrator task 20.8a**, append-then-prune — not an append arm inside `SP_SNAPSHOT_KEYWORD_STATE` as Task 0.3 describes |
> | `V_CATALOG_DWELL` | `scripts/bigquery/views/V_CATALOG_DWELL.sql` | Task 0.4's object, built |
> | `KEYWORD_STATE_HISTORY_acceptance.sql` | `scripts/bigquery/tests/` | **not** `FACT_KEYWORD_STATE_acceptance.sql`, the name Task 0.2 creates |
> | `V_UNOWNED_SPEND` / `_SUMMARY` | `scripts/bigquery/views/` | Phase 2's measurement, standing as durable state |
>
> **The shipped design is better than Task 0.3's on two counts** and should be kept: a separate
> procedure means the failure mode leaves a duplicate rather than a lost day, and it reads the live
> column list out of `INFORMATION_SCHEMA` on every run — which is exactly what this plan's Task 0.3
> Step 3 arrived at independently, and it makes the "every column added to `FACT_KEYWORD_STATE` must
> arrive on the history DDL" rule automatic rather than remembered.
>
> **So do this instead of Tasks 0.2–0.4 as written:**
>
> 1. Read the three shipped files and `architecture/KEYWORD_STATE.md` before touching anything.
> 2. **Task 0.3 becomes a verification task**, not a build: confirm the append runs, confirm 20.8a's
>    position, and confirm the schema-evolution arm actually adds a new column on the night it
>    appears. **Never add a second writer to that table.**
> 3. **Task 0.2's suite is `KEYWORD_STATE_HISTORY_acceptance.sql`, which already exists** — merge
>    Task 0.2's eleven checks into it rather than creating a second file, and keep the K-numbering
>    this plan uses (`K01`–`K10`, `K02b`) only where it does not collide with what is there.
> 4. **Every later `ALTER TABLE ... FACT_KEYWORD_STATE_HISTORY` in this plan is probably redundant**
>    — the append procedure adds columns itself. Run the append once after each column addition and
>    check the history's schema rather than issuing the `ALTER`; keep the `ALTER` only where the
>    check shows the column did not arrive. Acceptance `K02b` is the instrument either way.
> 5. **Task 2.1's red measurement should be taken against `V_UNOWNED_SPEND`**, which is already at
>    TARGET grain — finer than the baseline's `(campaign, keyword)` pairs, and the reason its largest
>    row "was not a subject". Do not build a second measurement of the same money.
>
> Everything else in Phase 0 — Task 0.1's idempotency fix and Tasks 0.5/0.6's Pacing prediction
> columns, which close violation 13's recording half — is untouched by that session and stands
> exactly as written.

**Closes:** violation 6 (the Catalog keeps no memory) and the recording half of violation 13 (Pacing records no prediction).

**Why first, and why it moves no money.** `FACT_KEYWORD_STATE` holds exactly one distinct `snapshot_date` (838 rows, 2026-08-24). §10.4's "how long has this been stuck" is unanswerable, §6's Catalog scorecard is impossible, and every later phase would ship with no way to prove it helped. The same argument applies to Pacing's predicted half: nothing records what a bid was expected to deliver, so §2.5's response curve has no input and Pacing cannot be graded at all. Both are append-only, zero-behaviour, zero-risk and **unbackfillable** — the cost of deferring is not the cost of the fix, it is the history you can never get back. Measured cost: 0.35 MB/day, ~128 MB/year, about $0.003/month of active storage. Cost is not a design input here.

This phase also builds the Catalog's first acceptance suite, because `scripts/bigquery/tests/` has nothing for `FACT_KEYWORD_STATE`, `V_KEYWORD_GUARD`, `T_FAMILY_BAR` or `V_BID_FLOOR` — TDD on any Catalog task has nothing to fail first until it exists.

**Unblocks:** every other phase's ability to be graded; §6.1's method experiments; §1.4's "durable, queryable state of its own"; and the response curve in Phase 10, which needs weeks of accumulated bid→click predictions before it can be fitted.

**Size:** S — 1–2 days. Two table adds, one append arm, one new suite. No behavioural change anywhere.

---

### Task 0.1: Make `SP_SNAPSHOT_KEYWORD_STATE` safe to call twice

**Files:**
- Modify: `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql:91,95,99`

The three branches that build `prior_snapshot` use a bare `CREATE TEMP TABLE`. The house rule after the 2026-08-24 cube outage is `CREATE OR REPLACE TEMP TABLE` for anything the orchestrator may call twice in one pass. Today the procedure fails on a second call inside one `bq` script session — which is exactly what Task 0.3 needs to verify its append arm. Zero behavioural risk, so it goes first.

- [ ] **Step 1: Reproduce the failure**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE\`();
   CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE\`();"
```

Expected: FAIL. BigQuery reports that the temporary table `prior_snapshot` already exists (the second `CALL` re-enters the `IF` and re-runs a bare `CREATE TEMP TABLE`).

- [ ] **Step 2: Back up the procedure**

```bash
cd /Users/ori/Develop/OI
NEXT=$(ls scripts/bigquery/**/*.bak.v27.*.* 2>/dev/null | sed -E 's/.*\.bak\.v27\.([0-9]+)\..*/\1/' | sort -n | tail -1)
NEXT=$((NEXT + 1))
cp scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql \
   scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql.bak.v27.$NEXT.$(date +%H%M)
```

- [ ] **Step 3: Convert all three branches**

```bash
cd /Users/ori/Develop/OI
/usr/local/bin/python3 - <<'PY'
p = 'scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql'
s = open(p).read()
assert s.count('CREATE TEMP TABLE prior_snapshot AS') == 3, s.count('CREATE TEMP TABLE prior_snapshot AS')
s = s.replace('CREATE TEMP TABLE prior_snapshot AS',
              'CREATE OR REPLACE TEMP TABLE prior_snapshot AS')
open(p, 'w').write(s)
print('converted 3')
PY
grep -c 'CREATE OR REPLACE TEMP TABLE prior_snapshot AS' scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql
```

Expected: `converted 3` then `3`.

- [ ] **Step 4: Deploy and re-run the double call**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE\`();
   CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE\`();"
```

Expected: both statements succeed, no error.

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql
git commit -m "fix(catalog): SP_SNAPSHOT_KEYWORD_STATE prior_snapshot uses CREATE OR REPLACE TEMP TABLE

A bare CREATE TEMP TABLE in all three IF branches made the procedure fail on a
second CALL in one script session. House rule after the 2026-08-24 cube outage."
```

---

### Task 0.2: The Catalog's first acceptance suite

**Files:**
- Create: `scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql`

Modelled on `FACT_PLAN_NEXT_WEEK_acceptance.sql`: one CTE per check, each returning `(check_name, violations)`, unioned, and a final `IF(violations = 0, 'PASS', 'FAIL')`.

- [ ] **Step 1: Write the suite**

```sql
-- =============================================================================================
-- FACT_KEYWORD_STATE acceptance — the Catalog's first suite. EVERY ROW MUST READ PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Doctrine: architecture/THREE_LAYERS.md §2 (the contract), §6.2 (a layer cannot be graded on
-- predictions it does not keep). Object: scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql.
--
-- K01 is the memory check and is the one that starts RED: the Catalog is rebuilt nightly with
-- CREATE OR REPLACE TABLE, so the live table can only ever hold one snapshot_date. It goes green
-- once FACT_KEYWORD_STATE_HISTORY exists and has accrued a second day.
-- =============================================================================================
WITH s AS (
  SELECT * FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
),
h AS (
  SELECT COUNT(DISTINCT snapshot_date) AS n_days
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
),
k01 AS (
  SELECT 'K01 the Catalog retains its own answers for more than one day (doctrine 6.2)' AS check_name,
         GREATEST(2 - (SELECT n_days FROM h), 0) AS violations
),
k02 AS (
  SELECT 'K02 exactly one row per (snapshot_date, campaign_id, keyword_id)',
         (SELECT COUNT(*) FROM (
            SELECT snapshot_date, campaign_id, keyword_id
            FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
            GROUP BY 1, 2, 3 HAVING COUNT(*) > 1))
),
k03 AS (
  SELECT 'K03 state is inside the enumerated ladder set',
         COUNTIF(state NOT IN ('DEAD','PENDING_SETTLE','REVIVED_SETTLING','PARKED',
                               'LAUNCH_CONTAINED','TRIAL','PACED_WINNER','WINNER','AT_BAR',
                               'LOSER','FLOOR_PROBATION','REPRICE')
                 OR state IS NULL)
  FROM s
),
k04 AS (
  SELECT 'K04 next_check_date is NULL only on DEAD (the appointment rule)',
         COUNTIF(next_check_date IS NULL AND state != 'DEAD')
  FROM s
),
k05 AS (
  SELECT 'K05 bid_floor equals FN_BID_FLOOR for the row channel and creative type',
         COUNTIF(ABS(bid_floor
                     - `onyga-482313.OI.FN_BID_FLOOR`(channel, creative_type).bid_floor) > 0.0001)
  FROM s
),
k06 AS (
  SELECT 'K06 one ad group per (campaign_id, keyword_id) — the floor cannot be borrowed',
         (SELECT COUNT(*) FROM (
            SELECT campaign_id, keyword_id
            FROM s WHERE ad_group_id IS NOT NULL
            GROUP BY 1, 2 HAVING COUNT(DISTINCT ad_group_id) > 1))
),
k07 AS (
  SELECT 'K07 family_bar is inside the published clamp [0.60, 1.00] (tolerance 5e-5, bar is ROUNDed to 4dp)',
         COUNTIF(family_bar IS NOT NULL
                 AND (family_bar < 0.60 - 0.00005 OR family_bar > 1.00 + 0.00005))
  FROM s
),
k08 AS (
  SELECT 'K08 a bid at or under its floor plus half a cent reads at_floor',
         COUNTIF(current_bid IS NOT NULL AND bid_floor IS NOT NULL
                 AND (current_bid <= bid_floor + 0.005) != COALESCE(at_floor, FALSE))
  FROM s
),
k09 AS (
  SELECT 'K09 the cleaned record can never be larger than the raw one (the guard only removes)',
         COUNTIF(clean_clk90 > settled_clk90 OR clean_ord90 > settled_ord90)
  FROM s
),
k10 AS (
  SELECT 'K10 probation columns are populated together or not at all',
         COUNTIF(probation_clock_start IS NULL AND probation_clk_settled IS NOT NULL)
       + COUNTIF(probation_clock_start IS NOT NULL AND probation_due_date IS NULL)
  FROM s
),
k02b AS (
  -- THE MEMORY IS COMPLETE, not merely present. Task 0.3's append copies BY COLUMN NAME, so a
  -- column added to FACT_KEYWORD_STATE without the matching ALTER TABLE on the history table is
  -- silently not recorded — no error, no alarm, and unbackfillable. Nine later tasks in this plan
  -- add columns (2.3, 2.4, 5.5, 7.3, 7.4, 8.2, 10.3, 11.4, 13.4); this check is what makes
  -- forgetting one loud on the same night.
  SELECT 'K02b the history table carries every column of the current table (the append is by name)',
         (SELECT COUNT(*)
          FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS` c
          WHERE c.table_name = 'FACT_KEYWORD_STATE'
            AND c.column_name NOT IN (SELECT h.column_name
                                      FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS` h
                                      WHERE h.table_name = 'FACT_KEYWORD_STATE_HISTORY'))
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM (SELECT * FROM k01 UNION ALL SELECT * FROM k02 UNION ALL SELECT * FROM k03
      UNION ALL SELECT * FROM k04 UNION ALL SELECT * FROM k05 UNION ALL SELECT * FROM k06
      UNION ALL SELECT * FROM k07 UNION ALL SELECT * FROM k08 UNION ALL SELECT * FROM k09
      UNION ALL SELECT * FROM k10 UNION ALL SELECT * FROM k02b)
ORDER BY check_name;
```

- [ ] **Step 2: Run it and watch K01 fail**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql)"
```

Expected: the whole query FAILS with `Not found: Table onyga-482313:OI.FACT_KEYWORD_STATE_HISTORY` — the measured violation is that the history table does not exist at all. This is the red state Task 0.3 turns green.

- [ ] **Step 3: Confirm the other ten checks by themselves**

Run the same file with the `h` CTE and `k01` temporarily unavailable, by measuring the memory violation directly:

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT COUNT(DISTINCT snapshot_date) AS distinct_snapshot_days
   FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`"
```

Expected: `1`. That is the measured violation count behind violation 6 — one day of memory where the doctrine needs a history.

- [ ] **Step 4: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql
git commit -m "test(catalog): first acceptance suite for FACT_KEYWORD_STATE

Eleven checks: grain, ladder set, appointment rule, floor identity, ad-group
uniqueness, bar clamp, at_floor, one-sided guard, probation coherence, K02b (the
history carries every column, because the append is by name), and K01 — the memory
check, red until FACT_KEYWORD_STATE_HISTORY exists."
```

---

### Task 0.3: `FACT_KEYWORD_STATE_HISTORY` and the append arm

**Files:**
- Create: `scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql`
- Modify: `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql` (tail, after `FROM fin3 s;`)
- Modify: `config.yaml` (`stored_procedures:` section, beside `FACT_KEYWORD_STATE`)

**Why a full daily copy, not a change-only SCD2.** 25 of the 65 columns are continuous floats that move nightly (`settled_roas90`, `se_eff`, `affordable_cpc`, `guard_ns_share`…), so a change-detector would emit nearly every row anyway; §6's question is "on date D you said X — was it right?", which needs a row per subject per date; and at 0.35 MB/day the space a narrower shape saves is a rounding error. `CREATE TABLE IF NOT EXISTS` is a silent no-op against an existing table, so every future column arrives as an explicit `ALTER TABLE ADD COLUMN IF NOT EXISTS` line.

- [ ] **Step 1: Write the DDL**

```sql
-- =============================================================================================
-- FACT_KEYWORD_STATE_HISTORY — the Catalog's memory. One row per subject per snapshot date, every
-- column of FACT_KEYWORD_STATE, appended nightly by SP_SNAPSHOT_KEYWORD_STATE after it rebuilds
-- the current table.
--
-- WHY A FULL COPY AND NOT A CHANGE-ONLY SCD2. The doctrine's Catalog scorecard asks "on date D you
-- said X — was it right?" (architecture/THREE_LAYERS.md 6). That question needs a row for the
-- subject on the date, so a change-only table would have to be interpolated by a window function
-- on every read. Most of the measurement columns are continuous and move every night, so a change
-- detector would emit nearly every row regardless. Re-derive the storage cost with the query in
-- the SOP rather than trusting a number here.
--
-- IDEMPOTENCY: the append is DELETE-today-then-INSERT, the same shape SP_SNAPSHOT_ENGINE_PROPOSALS
-- uses. The partition key is the row's OWN snapshot_date, which is Los Angeles dated, while the
-- orchestrator runs on New York — never recompute CURRENT_DATE() in the append, or a pass starting
-- after 21:00 New York splits one snapshot across two partitions.
--
-- ADDING A COLUMN: CREATE TABLE IF NOT EXISTS is a silent no-op against a table that exists, so a
-- new column must arrive as an explicit ALTER TABLE ADD COLUMN IF NOT EXISTS line below, in the
-- same commit as the column addition to FACT_KEYWORD_STATE.
-- =============================================================================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
(
  snapshot_date              DATE    NOT NULL,
  campaign_id                STRING,
  keyword_id                 STRING,
  target_text                STRING,
  match_type                 STRING,
  channel                    STRING,
  is_auto                    BOOL,
  is_pt                      BOOL,
  campaign_name              STRING,
  family                     STRING,
  current_bid                FLOAT64,
  state                      STRING,
  owner_engine               STRING,
  state_since                DATE,
  settled_clk90              INT64,
  settled_ord90              INT64,
  settled_roas90             FLOAT64,
  settled_cpc90              FLOAT64,
  settled_gp90               FLOAT64,
  settled_sp90               FLOAT64,
  season_context             BOOL,
  next_check_date            DATE,
  next_check_what            STRING,
  state_reason               STRING,
  family_bar                 FLOAT64,
  bar_exempt                 BOOL,
  nf_orders                  INT64,
  se_eff                     FLOAT64,
  gp_per_click               FLOAT64,
  affordable_cpc             FLOAT64,
  ord_bar_expected           FLOAT64,
  click_collapse             BOOL,
  guard_prior_clk            INT64,
  guard_ns_share             FLOAT64,
  guard_bar_material         FLOAT64,
  guard_deferred             BOOL,
  guard_flip                 BOOL,
  clean_clk90                INT64,
  clean_ord90                INT64,
  clean_roas90               FLOAT64,
  clean_cpc90                FLOAT64,
  clean_affordable_cpc       FLOAT64,
  ns_zero_ord_terms          INT64,
  ns_zero_ord_clicks         INT64,
  ad_group_id                STRING,
  creative_type              STRING,
  bid_floor                  FLOAT64,
  bid_floor_source           STRING,
  m_effective                FLOAT64,
  is_brand_defense           BOOL,
  affordable_bid             FLOAT64,
  clean_affordable_bid       FLOAT64,
  at_floor                   BOOL,
  guard_scope                STRING,
  raw_state                  STRING,
  clean_state                STRING,
  settle_days_eff            INT64,
  floor_since                DATE,
  probation_clock_start      DATE,
  probation_clk_settled      INT64,
  probation_elapsed          BOOL,
  probation_due_date         DATE,
  probation_bid              FLOAT64,
  nf_collapse_forecast_date  DATE,
  prior_state                STRING
)
PARTITION BY snapshot_date
CLUSTER BY campaign_id, keyword_id
;

-- SET OPTIONS, not CREATE ... OPTIONS: CREATE TABLE IF NOT EXISTS is a silent no-op against a
-- table that already exists, so the description would never converge.
ALTER TABLE `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY` SET OPTIONS(description =
  "The Catalog's memory: one row per (snapshot_date, campaign_id, keyword_id), every column of FACT_KEYWORD_STATE, appended nightly by SP_SNAPSHOT_KEYWORD_STATE immediately after the rebuild. Exists because the current table is CREATE OR REPLACE and therefore holds one day, which makes the Catalog scorecard in architecture/THREE_LAYERS.md 6 impossible and every dwell-time question unanswerable (violation 6). A FULL copy rather than a change-only SCD2: the scorecard needs a row per subject per date, and most measurement columns move nightly anyway. The append is DELETE-today-then-INSERT on the row's OWN Los Angeles dated snapshot_date — never a freshly computed CURRENT_DATE(), because the orchestrator runs on New York. Read through V_CATALOG_DWELL for state duration and overdue appointments. Adding a column here requires an explicit ALTER TABLE ADD COLUMN IF NOT EXISTS line in the DDL, in the same commit as the column addition upstream.");
```

- [ ] **Step 2: Deploy the table**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql)"
bq show --format=prettyjson onyga-482313:OI.FACT_KEYWORD_STATE_HISTORY \
  | /usr/local/bin/python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['schema']['fields']), 'columns;', d.get('timePartitioning'), d.get('clustering'))"
```

Expected: `65 columns; {'type': 'DAY', 'field': 'snapshot_date'} {'fields': ['campaign_id', 'keyword_id']}`.

- [ ] **Step 3: Back up the procedure and add the append arm**

```bash
cd /Users/ori/Develop/OI
NEXT=$(ls scripts/bigquery/**/*.bak.v27.*.* 2>/dev/null | sed -E 's/.*\.bak\.v27\.([0-9]+)\..*/\1/' | sort -n | tail -1)
NEXT=$((NEXT + 1))
cp scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql \
   scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql.bak.v27.$NEXT.$(date +%H%M)
```

Replace the final two lines of the file, which today read exactly:

```sql
  FROM fin3 s;
END;
```

with:

```sql
  FROM fin3 s;

  -- ── THE CATALOG'S MEMORY (violation 6) ──────────────────────────────────────────────────────
  -- The rebuild above is CREATE OR REPLACE, so this table holds one day. Append that day to
  -- FACT_KEYWORD_STATE_HISTORY so the Catalog can be graded on what it said (doctrine 6, 6.2) and
  -- so any "how long has this been stuck" question becomes answerable (10.4).
  --
  -- DELETE-today-then-INSERT, copied from SP_SNAPSHOT_ENGINE_PROPOSALS: a same-day re-run replaces
  -- rather than duplicates, and the orchestrator wraps every CALL in BEGIN/EXCEPTION so a re-run is
  -- normal. The date deleted and the date inserted are BOTH the value already on the row — it is
  -- Los Angeles dated (see `today` above) while the orchestrator runs on New York, so a freshly
  -- computed CURRENT_DATE() here would split one snapshot across two partitions on any pass that
  -- starts after 21:00 New York.
  DELETE FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
  WHERE snapshot_date IN (SELECT DISTINCT snapshot_date
                          FROM `onyga-482313.OI.FACT_KEYWORD_STATE`);

  -- THE APPEND IS BY COLUMN NAME, NEVER BY POSITION, AND THIS IS NOT A STYLE PREFERENCE.
  -- `INSERT INTO history SELECT * FROM current` maps columns POSITIONALLY. NINE later tasks in this
  -- plan add columns to FACT_KEYWORD_STATE (2.3, 2.4, 5.5, 7.3, 7.4, 8.2, 10.3, 11.4, 13.4), and
  -- two of them add columns in the MIDDLE of the
  -- procedure's final SELECT rather than at the end (Task 2.3 places subject_key and
  -- is_sentinel_target immediately after keyword_id; Task 8.2 places the four-field contract FIRST
  -- in the row), while every column reaching this history table arrives by ALTER TABLE ADD COLUMN,
  -- which appends at the END. After Task 2.3 a positional insert would map subject_key (STRING)
  -- onto target_text and is_sentinel_target (BOOL) onto match_type (STRING) — the nightly pass
  -- fails at the INSERT, and where the types happen to line up it does not fail, it writes the
  -- wrong data silently. So the column list is built from INFORMATION_SCHEMA at run time, by name,
  -- and a column that exists on the current table but not yet on the history table is simply not
  -- copied (the acceptance suite's K02b catches that case loudly rather than letting it rot).
  BEGIN
    DECLARE append_sql STRING;
    SET append_sql = (
      SELECT CONCAT(
        'INSERT INTO `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY` (', cols, ') ',
        'SELECT ', cols, ' FROM `onyga-482313.OI.FACT_KEYWORD_STATE`')
      FROM (
        SELECT STRING_AGG(h.column_name, ', ' ORDER BY h.ordinal_position) AS cols
        FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS` h
        WHERE h.table_name = 'FACT_KEYWORD_STATE_HISTORY'
          AND h.column_name IN (SELECT c.column_name
                                FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS` c
                                WHERE c.table_name = 'FACT_KEYWORD_STATE')
      )
    );
    EXECUTE IMMEDIATE append_sql;
  END;
END;
```

**A standing rule this creates, binding on every later task in this plan.** Every task that adds a
column to `FACT_KEYWORD_STATE` must add the **same column name** to
`scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql` as an `ALTER TABLE ... ADD COLUMN IF NOT
EXISTS` line **and deploy that DDL** in the same step. All nine tasks that add a column — 2.3, 2.4,
5.5, 7.3, 7.4, 8.2, 10.3, 11.4 and 13.4 — carry that `ALTER TABLE` block already; this is why. Position no longer matters — only
the name — so a column may be added anywhere in the procedure's final `SELECT`.

- [ ] **Step 4: Deploy, run twice, and prove idempotency**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE\`();
   CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE\`();"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT snapshot_date, COUNT(*) rows_written,
          COUNT(*) - COUNT(DISTINCT CONCAT(campaign_id,'|',keyword_id)) AS duplicate_subjects
   FROM \`onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY\`
   GROUP BY 1 ORDER BY 1"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT c.column_name AS on_current_but_not_on_history
   FROM \`onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS\` c
   WHERE c.table_name = 'FACT_KEYWORD_STATE'
     AND c.column_name NOT IN (SELECT h.column_name
                               FROM \`onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS\` h
                               WHERE h.table_name = 'FACT_KEYWORD_STATE_HISTORY')
   ORDER BY 1"
```

Expected: one row from the first query, `duplicate_subjects = 0`, and `rows_written` equal to the row count of `FACT_KEYWORD_STATE`. Two calls produce one partition, not two copies. **Zero rows from the second query** — a name listed there is a column the name-keyed append is silently dropping, and the fix is the missing `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` line in the history DDL, never a change to the append.

- [ ] **Step 5: Register in `config.yaml`**

Insert a new entry in the `stored_procedures:` list immediately after the `FACT_KEYWORD_STATE` entry (index 35) and before `V_KEYWORD_STATE` — the verified house precedent for a table written by a procedure:

```yaml
  - name: FACT_KEYWORD_STATE_HISTORY
    description: >-
      The Catalog's memory. One row per (snapshot_date, campaign_id, keyword_id) carrying every
      column of FACT_KEYWORD_STATE, appended nightly by SP_SNAPSHOT_KEYWORD_STATE immediately after
      it rebuilds the current table. Partitioned by snapshot_date, clustered by (campaign_id,
      keyword_id). Exists because the current table is CREATE OR REPLACE and holds one day, which
      makes the Catalog scorecard impossible and every dwell-time question unanswerable
      (architecture/THREE_LAYERS.md violation 6). The append is DELETE-today-then-INSERT keyed on
      the row's own Los Angeles dated snapshot_date, never a freshly computed CURRENT_DATE().
      Read through V_CATALOG_DWELL.
    source_files:
      - scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql
      - scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql
    dependencies:
      - FACT_KEYWORD_STATE
```

Then verify:

```bash
cd /Users/ori/Develop/OI
/usr/local/bin/python3 - <<'PY'
import yaml, collections
d = yaml.safe_load(open('config.yaml'))
names = [e['name'] for e in d['stored_procedures']]
print('FACT_KEYWORD_STATE_HISTORY at index', names.index('FACT_KEYWORD_STATE_HISTORY'))
print('duplicates:', [n for n,c in collections.Counter(names).items() if c > 1])
PY
```

Expected: an index of 36, `duplicates: []`.

- [ ] **Step 6: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql \
        scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql \
        config.yaml
git commit -m "feat(catalog): FACT_KEYWORD_STATE_HISTORY — the Catalog keeps its answers

Closes half of violation 6. Full daily append, partitioned on snapshot_date and
clustered on the subject, written DELETE-today-then-INSERT on the row's own LA
date. Zero behaviour change; unbackfillable, so it starts accruing now."
```

---

### Task 0.4: `V_CATALOG_DWELL` — make §10.4's question answerable

**Files:**
- Create: `scripts/bigquery/views/V_CATALOG_DWELL.sql`
- Modify: `config.yaml` (`views:` section)

- [ ] **Step 1: Write the view**

```sql
-- =============================================================================================
-- V_CATALOG_DWELL — how long a subject has been where it is, read off the Catalog's own history.
--
-- WHY IT EXISTS: architecture/THREE_LAYERS.md 10.4 records that "dwell time in any state" could not
-- be measured at all, because the state table is replaced nightly. This view is the instrument that
-- makes the question answerable, and the one every later phase reports against: it says how long a
-- verdict has stood, how often it has flipped, and how overdue its own appointment is.
--
-- GRAIN: one row per (campaign_id, keyword_id) on the latest snapshot in the history table. Read
-- the history table directly — nothing here reads FACT_KEYWORD_STATE, so the view answers whether
-- or not tonight's pass has run (doctrine 1.4, no ordering dependency).
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CATALOG_DWELL` AS
WITH latest AS (
  SELECT MAX(snapshot_date) AS d FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
),
h AS (
  SELECT campaign_id, keyword_id, snapshot_date, state, next_check_date, family, target_text,
         match_type, channel, settled_clk90, settled_ord90, settled_roas90, settled_sp90,
         current_bid, bid_floor
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
),
now_row AS (
  SELECT h.* FROM h JOIN latest ON h.snapshot_date = latest.d
),
-- the run the subject is currently in: the earliest consecutive date on which it already held
-- today's state. A gap in the history (a night the pass did not run) does not break a run — the
-- run is defined by the state, not by date adjacency, so this is the earliest date at or after the
-- last date the subject held a DIFFERENT state.
last_different AS (
  SELECT n.campaign_id, n.keyword_id, MAX(h.snapshot_date) AS d_last_other
  FROM now_row n
  JOIN h ON h.campaign_id = n.campaign_id AND h.keyword_id = n.keyword_id
        AND h.state != n.state
  GROUP BY 1, 2
),
run_start AS (
  SELECT n.campaign_id, n.keyword_id,
         MIN(h.snapshot_date) AS state_run_start
  FROM now_row n
  LEFT JOIN last_different ld ON ld.campaign_id = n.campaign_id AND ld.keyword_id = n.keyword_id
  JOIN h ON h.campaign_id = n.campaign_id AND h.keyword_id = n.keyword_id
        AND h.state = n.state
        AND h.snapshot_date > COALESCE(ld.d_last_other, DATE '1900-01-01')
  GROUP BY 1, 2
),
flips AS (
  SELECT campaign_id, keyword_id,
         COUNTIF(prev_state IS NOT NULL AND prev_state != state
                 AND snapshot_date > DATE_SUB((SELECT d FROM latest), INTERVAL 27 DAY))
           AS state_changes_28d,
         COUNTIF(prev_state IS NOT NULL AND prev_state != state
                 AND snapshot_date > DATE_SUB((SELECT d FROM latest), INTERVAL 89 DAY))
           AS state_changes_90d
  FROM (
    SELECT campaign_id, keyword_id, snapshot_date, state,
           LAG(state) OVER (PARTITION BY campaign_id, keyword_id ORDER BY snapshot_date) AS prev_state
    FROM h
  )
  GROUP BY 1, 2
)
SELECT
  n.snapshot_date              AS as_of,
  n.campaign_id,
  n.keyword_id,
  n.family,
  n.target_text,
  n.match_type,
  n.channel,
  n.state,
  r.state_run_start,
  DATE_DIFF(n.snapshot_date, r.state_run_start, DAY) + 1        AS days_in_state,
  n.next_check_date,
  -- positive = the appointment is past due. NULL where there is no appointment (DEAD only).
  IF(n.next_check_date IS NULL, NULL,
     DATE_DIFF(n.snapshot_date, n.next_check_date, DAY))        AS days_overdue,
  COALESCE(f.state_changes_28d, 0)                              AS state_changes_28d,
  COALESCE(f.state_changes_90d, 0)                              AS state_changes_90d,
  (SELECT COUNT(DISTINCT snapshot_date) FROM h hh
   WHERE hh.campaign_id = n.campaign_id AND hh.keyword_id = n.keyword_id)
                                                                AS days_of_history,
  n.settled_clk90, n.settled_ord90, n.settled_roas90, n.settled_sp90,
  n.current_bid, n.bid_floor
FROM now_row n
LEFT JOIN run_start r ON r.campaign_id = n.campaign_id AND r.keyword_id = n.keyword_id
LEFT JOIN flips     f ON f.campaign_id = n.campaign_id AND f.keyword_id = n.keyword_id;
```

- [ ] **Step 2: Deploy and sanity-check the grain**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_CATALOG_DWELL.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT COUNT(*) rows, COUNT(DISTINCT CONCAT(campaign_id,'|',keyword_id)) subjects,
          MIN(days_in_state) min_days, MAX(days_of_history) max_days
   FROM \`onyga-482313.OI.V_CATALOG_DWELL\`"
```

Expected: `rows = subjects` (one row per subject), `min_days = 1` and `max_days = 1` on the first night — the view is correct and the history is one day old. `days_in_state` grows from tomorrow.

- [ ] **Step 3: Register in `config.yaml`**

Insert in the `views:` list immediately after the `V_KEYWORD_GUARD` entry (index 205):

```yaml
  - name: V_CATALOG_DWELL
    description: >-
      How long each Catalog subject has been in its current state, how often it has flipped in 28
      and 90 days, and how overdue its own next_check_date is. Reads FACT_KEYWORD_STATE_HISTORY
      only, so it answers whether or not tonight's pass has run. Built because
      architecture/THREE_LAYERS.md 10.4 records dwell time as unmeasurable while the state table
      held one day; it is the instrument every gap-closure phase reports against.
    type: view
    source_files:
      - scripts/bigquery/views/V_CATALOG_DWELL.sql
    dependencies:
      - FACT_KEYWORD_STATE_HISTORY
```

- [ ] **Step 4: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_CATALOG_DWELL.sql config.yaml
git commit -m "feat(catalog): V_CATALOG_DWELL — days in state, flips, and overdue appointments

Makes THREE_LAYERS 10.4's unanswerable question answerable. Reads the history
table only, so it has no ordering dependency on the nightly pass."
```

---

### Task 0.5: Pacing records what it expected to deliver

**Files:**
- Modify: `scripts/bigquery/procedures/SP_SNAPSHOT_ENGINE_PROPOSALS.sql` (schema of `FACT_ENGINE_PROPOSALS` plus all nine INSERTs)

`FACT_ENGINE_PROPOSALS` carries what each engine wanted and nothing about what it expected the bid to do. `V_BID_CPC_TRANSFER` already publishes the model per (campaign, target kind): `k_effective`, `gamma`, `m_effective` and `expected_cpc_at_bid_1_00`. Record only — no verdict changes in this phase.

- [ ] **Step 1: Add the four columns**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
ALTER TABLE \`onyga-482313.OI.FACT_ENGINE_PROPOSALS\`
  ADD COLUMN IF NOT EXISTS expected_cpc         FLOAT64,
  ADD COLUMN IF NOT EXISTS expected_clicks      FLOAT64,
  ADD COLUMN IF NOT EXISTS ceiling_at_proposal  FLOAT64,
  ADD COLUMN IF NOT EXISTS prediction_source    STRING"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT column_name FROM \`onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS\`
   WHERE table_name='FACT_ENGINE_PROPOSALS'
     AND column_name IN ('expected_cpc','expected_clicks','ceiling_at_proposal','prediction_source')
   ORDER BY 1"
```

Expected: four rows.

- [ ] **Step 2: Back up the procedure**

```bash
cd /Users/ori/Develop/OI
NEXT=$(ls scripts/bigquery/**/*.bak.v27.*.* 2>/dev/null | sed -E 's/.*\.bak\.v27\.([0-9]+)\..*/\1/' | sort -n | tail -1)
NEXT=$((NEXT + 1))
cp scripts/bigquery/procedures/SP_SNAPSHOT_ENGINE_PROPOSALS.sql \
   scripts/bigquery/procedures/SP_SNAPSHOT_ENGINE_PROPOSALS.sql.bak.v27.$NEXT.$(date +%H%M)
```

- [ ] **Step 3: Declare the model once, immediately after the `DELETE`**

The procedure currently opens with:

```sql
BEGIN
  DECLARE snap DATE DEFAULT CURRENT_DATE('America/Los_Angeles');

  DELETE FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS` WHERE snapshot_date = snap;
```

Insert immediately after the `DELETE`:

```sql
  -- ── WHAT THE BID WAS EXPECTED TO DELIVER (violation 13, the recording half) ─────────────────
  -- Doctrine 6: Pacing's scorecard is "did it deliver what it was asked for, at the price it
  -- predicted?", and 10.4 records that nothing captured the prediction, so Pacing could not be
  -- graded at all and 2.5's response curve had no input. This table is where the prediction lives.
  -- TWO TEMP TABLES, joined by every INSERT below, so the nine surfaces cannot disagree about the
  -- model. CREATE OR REPLACE TEMP TABLE because the orchestrator may call this procedure twice in
  -- one pass (house rule after the 2026-08-24 cube outage).
  --
  -- THE MODEL IS V_BID_CPC_TRANSFER's OWN, unchanged and not re-derived here. Read its header
  -- before touching this: line 21 states the forward model as
  --     realised_CPC = k_seg * bid^gamma * M_campaign
  -- and line 301 publishes k_effective = k_pure * m_effective — that is, k_effective ALREADY
  -- CONTAINS the campaign's placement multiplier. So the expression is
  --     expected_cpc = k_effective * bid ^ gamma
  -- and multiplying by m_effective a second time double-counts placement. (Verified 2026-08-24:
  -- COUNTIF(ABS(k_effective - k_pure*m_effective) > 1e-4) = 0 over all 415 rows of the view.)
  --
  -- THE GRAIN IS THE VIEW'S OWN GRAIN: one row per (campaign_id, channel, target_kind) — 415 rows
  -- over 152 campaigns, verified 1:1. k_effective VARIES BY target_kind inside a campaign (SP AUTO
  -- 0.70–3.62, SP KEYWORD 0.77–3.96), so collapsing the campaign with independent MAX()es would
  -- pair a level from one target kind with a gamma from another and produce a curve that belongs to
  -- no real segment — the ANY_VALUE-pairing hazard the house has a standing rule about. The QUALIFY
  -- below takes k_eff and gamma FROM THE SAME ROW, and the row is chosen by the key, not by a max.
  CREATE OR REPLACE TEMP TABLE bid_cpc_model AS
  SELECT CAST(campaign_id AS STRING) AS cid,
         channel,
         target_kind,
         k_effective AS k_eff,
         gamma
  FROM `onyga-482313.OI.V_BID_CPC_TRANSFER`
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY CAST(campaign_id AS STRING), channel, target_kind
    ORDER BY k_effective DESC) = 1;   -- defensive only: the grain is already 1:1

  -- our own click rate per day over the last 28 complete days, per (campaign, keyword).
  -- A SEPARATE TABLE, NOT A COLUMN ON THE ONE ABOVE. Written as one table joined on cid alone, a
  -- keyword with no 28-day click rate produced a NULL kid and therefore matched NOTHING, so
  -- 'CPC_ONLY_NO_OWN_CLICK_RATE' was unreachable and every dormant or parked keyword — precisely
  -- the population 2.5's curve most needs — was mislabelled 'NO_TRANSFER_MODEL'.
  -- expected_clicks is our own recent rate at the CURRENT price, carried forward — it is
  -- deliberately NOT elasticity-adjusted, because no bid-to-click-quantity model exists anywhere
  -- yet (that is violation 17, built in Phase 10). prediction_source says so on the row.
  CREATE OR REPLACE TEMP TABLE own_click_rate AS
  WITH wm AS (
    SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
    FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  )
  SELECT CAST(a.campaign_id AS STRING) AS cid, CAST(a.keyword_id AS STRING) AS kid,
         SAFE_DIVIDE(SUM(a.Ads_clicks), 28.0) AS clicks_per_day
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a, wm
  WHERE a.date BETWEEN DATE_SUB(wm.d, INTERVAL 28 DAY) AND DATE_SUB(wm.d, INTERVAL 1 DAY)
  GROUP BY 1, 2;
```

- [ ] **Step 4: Carry the prediction on every INSERT**

Every one of the nine `INSERT INTO onyga-482313.OI.FACT_ENGINE_PROPOSALS` statements in this file must gain the four columns in its column list and the four expressions in its `SELECT`, plus one `LEFT JOIN`. The pattern is identical on all nine; apply it mechanically. For the first INSERT (LIFT bids) the column list becomes:

```sql
  INSERT INTO `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
    (snapshot_date, engine, grain, campaign_id, campaign_name, keyword_id, ad_group_id, target_text,
     match_type, channel, action, current_bid, suggested_bid, current_budget, suggested_budget, reason, reason_short, season_relax_applied,
     held_action, held_bid, hold_source, verdict, verdict_reason,
     expected_cpc, expected_clicks, ceiling_at_proposal, prediction_source)
```

and the four expressions appended to its `SELECT` list, before the `FROM`:

```sql
         -- the prediction. NULL suggested_bid (a held row) predicts nothing, and says so.
         -- k_eff already carries the campaign's placement multiplier — see the model comment above;
         -- multiplying by m_effective here would double-count it.
         IF(v.suggested_bid IS NULL, NULL,
            COALESCE(bm.k_eff, bmk.k_eff)
              * POW(v.suggested_bid, COALESCE(bm.gamma, bmk.gamma)))        AS expected_cpc,
         IF(v.suggested_bid IS NULL, NULL, cr.clicks_per_day)               AS expected_clicks,
         CAST(NULL AS FLOAT64)                                              AS ceiling_at_proposal,
         -- FOUR REACHABLE OUTCOMES, and every one of them is a real state a row can be in.
         CASE WHEN v.suggested_bid IS NULL                    THEN 'NONE_HELD_ROW'
              WHEN COALESCE(bm.k_eff, bmk.k_eff) IS NULL      THEN 'NO_TRANSFER_MODEL'
              WHEN cr.clicks_per_day IS NULL AND bm.k_eff IS NULL
                                                              THEN 'CPC_KEYWORD_FALLBACK_NO_OWN_CLICK_RATE'
              WHEN cr.clicks_per_day IS NULL                  THEN 'CPC_ONLY_NO_OWN_CLICK_RATE'
              WHEN bm.k_eff IS NULL                           THEN 'CPC_KEYWORD_FALLBACK_PLUS_OWN_28D_CLICK_RATE'
              ELSE 'V_BID_CPC_TRANSFER_CPC_PLUS_OWN_28D_CLICK_RATE' END    AS prediction_source
```

with the source view aliased as `v` and these three joins added at the end of the statement:

```sql
  -- the segment's own curve...
  LEFT JOIN bid_cpc_model bm
    ON bm.cid         = CAST(v.campaign_id AS STRING)
   AND bm.channel     = IF(UPPER(COALESCE(v.channel, 'SP')) LIKE 'SB%', 'SB', 'SP')
   AND bm.target_kind = CASE
         WHEN UPPER(COALESCE(v.match_type, '')) LIKE 'AUTO%'      THEN 'AUTO'
         WHEN UPPER(COALESCE(v.match_type, '')) LIKE 'ASIN%'
           OR UPPER(COALESCE(v.match_type, '')) LIKE 'CATEGORY%'
           OR UPPER(COALESCE(v.match_type, '')) = 'TARGETING_EXPRESSION' THEN 'PRODUCT'
         ELSE 'KEYWORD' END
  -- ...and the campaign's KEYWORD segment as the named fallback, because V_BID_CPC_TRANSFER has no
  -- SB AUTO row at all and the proposals' match_type vocabulary is messier than the view's
  -- (measured on the 2026-08-21 snapshot: 'Automatic', 'AUTOMATIC', 'broad', 'BROAD', 'ASIN',
  -- 'TARGETING_EXPRESSION' and NULL all appear). A fallback that is NAMED on the row is honest; a
  -- silent NULL prediction is not.
  LEFT JOIN bid_cpc_model bmk
    ON bmk.cid         = CAST(v.campaign_id AS STRING)
   AND bmk.channel     = IF(UPPER(COALESCE(v.channel, 'SP')) LIKE 'SB%', 'SB', 'SP')
   AND bmk.target_kind = 'KEYWORD'
  LEFT JOIN own_click_rate cr
    ON cr.cid = CAST(v.campaign_id AS STRING)
   AND cr.kid = CAST(v.keyword_id AS STRING)
```

`ceiling_at_proposal` is `NULL` in this phase on purpose: no layer publishes a ceiling until Phase 1
widens `SP_ENGINE_PREFLIGHT`, and §6.3's discipline says do not assert a number we have not computed.

**IT IS FILLED BY TASK 1.3 STEP 5, NOT BY TASK 1.2.** Task 1.2 modifies `SP_ENGINE_PREFLIGHT`, which
writes `T_ENGINE_PREFLIGHT`; this column lives on `FACT_ENGINE_PROPOSALS`, written by
`SP_SNAPSHOT_ENGINE_PROPOSALS` — a different procedure, one orchestrator task earlier. Nothing in
Phase 1 touches this procedure unless a step says so, which is why Task 1.3 Step 5 exists and why
`SP_SNAPSHOT_ENGINE_PROPOSALS.sql` appears in that task's `Modify:` list. If that step is skipped the
column stays `NULL` for ever and violation 13's recording arm is one field short of what this plan
says it delivers. **Do not leave this phase with `ceiling_at_proposal` unfilled.**

For the two NEGATE INSERTs, which carry no bid, all four expressions are the constants `NULL, NULL, NULL, 'NOT_A_PRICE_LEVER'` and no join is added.

- [ ] **Step 5: Deploy and verify the prediction lands**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_ENGINE_PROPOSALS.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_ENGINE_PROPOSALS\`();
   CALL \`onyga-482313.OI.SP_SNAPSHOT_ENGINE_PROPOSALS\`();"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT prediction_source, COUNT(*) n,
          COUNTIF(expected_cpc IS NOT NULL) with_cpc,
          COUNTIF(expected_clicks IS NOT NULL) with_clicks
   FROM \`onyga-482313.OI.FACT_ENGINE_PROPOSALS\`
   WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_ENGINE_PROPOSALS\`)
   GROUP BY 1 ORDER BY n DESC"
```

Expected: every row carries a non-null `prediction_source`; rows sourced
`V_BID_CPC_TRANSFER_CPC_PLUS_OWN_28D_CLICK_RATE` carry both an `expected_cpc` and an
`expected_clicks`; `NOT_A_PRICE_LEVER` and `NONE_HELD_ROW` rows carry neither. Two calls produce one
partition. **`CPC_ONLY_NO_OWN_CLICK_RATE` must be REACHABLE** — a parked or dormant keyword with a
priced proposal and no clicks in the last 28 days lands there, and if that bucket is empty while
`NO_TRANSFER_MODEL` is large, the click-rate join has been folded back into the CPC table and the
two must be separated again. Sanity-check the CPC prediction against the view it comes from, which
must agree to the cent:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT COUNTIF(ABS(expected_cpc - t.expected_cpc_at_bid_1_00 * POW(p.suggested_bid, t.gamma)) > 0.01)
         AS rows_that_disagree_with_the_published_model
FROM \`onyga-482313.OI.FACT_ENGINE_PROPOSALS\` p
JOIN \`onyga-482313.OI.V_BID_CPC_TRANSFER\` t
  ON CAST(t.campaign_id AS STRING) = CAST(p.campaign_id AS STRING)
 AND t.channel = IF(UPPER(COALESCE(p.channel,'SP')) LIKE 'SB%','SB','SP')
 AND t.target_kind = 'KEYWORD'
WHERE p.snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_ENGINE_PROPOSALS\`)
  AND p.prediction_source = 'CPC_KEYWORD_FALLBACK_PLUS_OWN_28D_CLICK_RATE'
  AND p.expected_cpc IS NOT NULL"
```

Expected: `0`. `expected_cpc_at_bid_1_00` is `k_effective * 1^gamma`, so this is the same expression
read from the other end — if it disagrees, `m_effective` has been reintroduced somewhere.

- [ ] **Step 6: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/procedures/SP_SNAPSHOT_ENGINE_PROPOSALS.sql
git commit -m "feat(pacing): record what each proposed bid was expected to deliver

Closes the recording half of violation 13. expected_cpc from V_BID_CPC_TRANSFER's
published model, expected_clicks from our own 28-day rate, prediction_source
naming which. ceiling_at_proposal stays NULL until Task 1.3 Step 5 fills it — that
step, and no other, is what closes it."
```

---

### Task 0.6: The book stops throwing its own prediction away

**Files:**
- Modify: `scripts/bigquery/tables/FACT_PPC_CHANGE_LOG.sql`
- Modify: `tools/build_reprice_bulksheet.py` (`log_batch`, around lines 1313–1365)
- Modify: `tools/tests/test_change_log_discipline.py`

`price()` in the reprice book already computes `own_cpc`, `own_ratio`, `model_ratio` and the transfer method, and writes them only to a `.tmp` audit CSV. The two prediction columns that already exist on the change log (`expected_impact_weekly`, `expected_impact_kind`) are populated on 35 of 2,263 rows, none since 2026-06-23, and record dollars rather than clicks or CPC — so add explicit columns rather than overloading them.

- [ ] **Step 1: Add the columns to the change log**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
ALTER TABLE \`onyga-482313.OI.FACT_PPC_CHANGE_LOG\`
  ADD COLUMN IF NOT EXISTS predicted_cpc          FLOAT64,
  ADD COLUMN IF NOT EXISTS predicted_clicks_7d    FLOAT64,
  ADD COLUMN IF NOT EXISTS prediction_source      STRING,
  ADD COLUMN IF NOT EXISTS ceiling_at_change      FLOAT64"
```

Then append the same four `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` lines to `scripts/bigquery/tables/FACT_PPC_CHANGE_LOG.sql` so the DDL and the warehouse agree, with this comment above them:

```sql
-- ── WHAT THE BOOK PREDICTED (violation 13, the recording half; 2026-08-25) ────────────────────
-- The reprice book's price() already computes the keyword's own realised cost per click, its own
-- bid-to-CPC ratio, the campaign model's ratio and which of the two it used — and wrote all of it
-- to a .tmp audit CSV that nothing reads. Doctrine 6 grades Pacing on "did it deliver what it was
-- asked for, at the price it predicted", so the prediction is logged beside the change.
-- NOT overloaded onto expected_impact_weekly / expected_impact_kind: those record DOLLARS, are
-- populated on a small minority of historical rows and have not been written since mid-2026.
ALTER TABLE `onyga-482313.OI.FACT_PPC_CHANGE_LOG` ADD COLUMN IF NOT EXISTS predicted_cpc       FLOAT64;
ALTER TABLE `onyga-482313.OI.FACT_PPC_CHANGE_LOG` ADD COLUMN IF NOT EXISTS predicted_clicks_7d FLOAT64;
ALTER TABLE `onyga-482313.OI.FACT_PPC_CHANGE_LOG` ADD COLUMN IF NOT EXISTS prediction_source   STRING;
ALTER TABLE `onyga-482313.OI.FACT_PPC_CHANGE_LOG` ADD COLUMN IF NOT EXISTS ceiling_at_change   FLOAT64;
```

- [ ] **Step 2: Write the failing test**

Append to `tools/tests/test_change_log_discipline.py`:

```python
# ── THE PREDICTION IS LOGGED (violation 13, recording half; 2026-08-25) ──────────────────────
# The reprice book computes the keyword's own realised CPC and the transfer method it used, then
# threw both into a .tmp CSV. Doctrine 6 grades Pacing on the price it predicted, so the
# prediction must be on the change-log row, not in a scratch file.

PREDICTION_COLUMNS = ('predicted_cpc', 'predicted_clicks_7d', 'prediction_source',
                      'ceiling_at_change')


def test_reprice_log_batch_names_every_prediction_column():
    src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..',
                            'build_reprice_bulksheet.py')).read()
    body = src.split('def log_batch(')[1].split('\ndef ')[0]
    for col in PREDICTION_COLUMNS:
        assert col in body, f'log_batch does not log {col}'


def test_reprice_log_batch_column_list_matches_the_struct():
    """The INSERT's column list and the STRUCT's aliases must name the same columns, or BigQuery
    silently writes the wrong value into the wrong column."""
    src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..',
                            'build_reprice_bulksheet.py')).read()
    body = src.split('def log_batch(')[1].split('\ndef ')[0]
    cols_literal = re.search(r'cols = \(([^)]*)\)', body, re.S).group(1)
    cols = [c.strip() for c in re.sub(r'["\n]', '', cols_literal).split(',') if c.strip()]
    aliases = re.findall(r'AS (\w+)', body)
    for col in cols:
        assert col in aliases, f'{col} is in the INSERT column list but no STRUCT field aliases it'
    for col in PREDICTION_COLUMNS:
        assert col in cols, f'{col} is aliased in the STRUCT but missing from the column list'
```

- [ ] **Step 3: Run it and watch it fail**

```bash
cd /Users/ori/Develop/OI
/usr/local/bin/python3 -m pytest tools/tests/test_change_log_discipline.py -q -k prediction
```

Expected: FAIL — `AssertionError: log_batch does not log predicted_cpc`.

- [ ] **Step 4: Carry the prediction through to `log_batch`**

`log_batch(rows, batch_id, readme_path)` receives `rows` as a list of `(r, disp, new_bid)` triples. The
row dict `r` does not yet carry the prediction, so the caller must attach it.

**`price()` IS NOT CHANGED AT ALL.** It already returns everything needed —
`(raw_bid, transfer_method, detail)`, where `detail['own_cpc']` is the keyword's own realised cost per
click whenever it has `VOL_FLOOR` or more settled clicks and `NULL` otherwise
(`build_reprice_bulksheet.py:789-814`). The one edit is at its **only call site**, `_classify()` at
`:942`, where the three returned values are already bound to the local names `raw`, `method` and `pd`.
**Use those names.** `detail` and `transfer_method` are `price()`'s own internal names and do not exist
in the caller's scope; writing them there raises `NameError` on the first priced row of every build.
The call site today reads:

```python
    raw, method, pd = price(r, afford, cur)
    bits['raw_bid'], bits['transfer'], bits['pd'] = raw, method, pd
```

Add two lines immediately below it:

```python
    # the book's own prediction, kept for the change log rather than only the .tmp audit CSV
    # (violation 13). `pd` is price()'s detail dict and `method` its transfer method — the names
    # this function already binds them to. own_cpc is None below VOL_FLOOR settled clicks, and the
    # book never invents one, so predicted_cpc is populated exactly on the OWN_RATIO rows.
    r['predicted_cpc'] = pd.get('own_cpc')
    r['prediction_source'] = method
```

`method` takes one of three values — `OWN_RATIO`, `CAMPAIGN_MODEL`, `CPC_OVER_M` — and only the first
carries an `own_cpc`, which is exactly what Step 6 expects to read back.

Then in `log_batch`, replace the `cols` assignment and the trailing part of each `STRUCT(` with the versions below. The `cols` line today reads:

```python
    cols = ("change_id, batch_id, applied_at, action, targeting, keyword_id, match_type, "
            "campaign_id, campaign_name, campaign_type, ad_group_id, old_bid, new_bid, source, "
            "coach_mode, upload_note, upload_status")
```

Replace with:

```python
    cols = ("change_id, batch_id, applied_at, action, targeting, keyword_id, match_type, "
            "campaign_id, campaign_name, campaign_type, ad_group_id, old_bid, new_bid, source, "
            "coach_mode, upload_note, upload_status, "
            # violation 13: what this row predicted, logged beside what it changed
            "predicted_cpc, predicted_clicks_7d, prediction_source, ceiling_at_change")
```

and inside the `for r, disp, new_bid in rows:` loop, immediately before the closing `f"{q('PENDING_UPLOAD')} AS upload_status)"` line, insert:

```python
        # THE PREDICTION (violation 13). predicted_cpc is the keyword's OWN realised cost per click
        # where it has 10 or more settled clicks, else NULL — the book never invents one. There is
        # no bid-to-click-quantity model anywhere yet (violation 17, Phase 10), so
        # predicted_clicks_7d carries our own recent rate and prediction_source says which.
        pred_cpc = num(r.get('predicted_cpc'))
        pred_clk = num(r.get('own_clk'))
        pred_clk = (pred_clk / 90.0 * 7.0) if pred_clk else None
        psrc = r.get('prediction_source') or 'NONE'
        ceiling = num(r.get('affordable_cpc'))
```

and change that closing line to:

```python
            f"{q('PENDING_UPLOAD')} AS upload_status, "
            f"{('CAST(' + repr(pred_cpc) + ' AS FLOAT64)') if pred_cpc is not None else 'NULL'} AS predicted_cpc, "
            f"{('CAST(' + repr(pred_clk) + ' AS FLOAT64)') if pred_clk is not None else 'NULL'} AS predicted_clicks_7d, "
            f"{q(psrc)} AS prediction_source, "
            f"{('CAST(' + repr(ceiling) + ' AS FLOAT64)') if ceiling is not None else 'NULL'} AS ceiling_at_change)"
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd /Users/ori/Develop/OI
/usr/local/bin/python3 -m pytest tools/tests/test_change_log_discipline.py -q
```

Expected: all tests PASS, including the existing discipline tests for all three books.

- [ ] **Step 6: Build a book against a temporary copy of the change log and read the prediction back**

**THE OVERRIDE IS A FLAG, NOT AN ENVIRONMENT VARIABLE — and getting this wrong writes synthetic rows
into the production change log, permanently.** `CHANGE_LOG` in `build_reprice_bulksheet.py` is a
module global set at `:124-125` and changed only by `set_change_log_table()` (`:128-133`), reachable
only through `--change-log-table` (`:1383`). The book never reads `os.environ`. A shell assignment
`CHANGE_LOG=...` in front of the command is therefore **silently ignored**: `log_batch` inserts into
`FACT_PPC_CHANGE_LOG`, the house rule forbids ever deleting a change-log row, and the `DROP TABLE`
below would remove an empty `TMP_` table while the real rows sat in production for ever. Pass the
**bare table name** — `set_change_log_table` asserts a `TMP_`/`TEMP_` prefix and refuses a
project-qualified string.

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CREATE OR REPLACE TABLE \`onyga-482313.OI.TMP_PPC_CHANGE_LOG_PRED\` AS
   SELECT * FROM \`onyga-482313.OI.FACT_PPC_CHANGE_LOG\` WHERE FALSE"
/usr/local/bin/python3 tools/build_reprice_bulksheet.py \
  --change-log-table TMP_PPC_CHANGE_LOG_PRED -o .tmp/reprice_pred_check.xlsx
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT prediction_source, COUNT(*) n, COUNTIF(predicted_cpc IS NOT NULL) with_cpc
   FROM \`onyga-482313.OI.TMP_PPC_CHANGE_LOG_PRED\` GROUP BY 1 ORDER BY n DESC"
# THE POLLUTION CHECK. Run it BEFORE the DROP — the DROP is what would hide the mistake.
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT COUNTIF(DATE(applied_at) = CURRENT_DATE('America/Los_Angeles')
                  AND upload_status = 'PENDING_UPLOAD') AS rows_written_to_the_LIVE_log_today
   FROM \`onyga-482313.OI.FACT_PPC_CHANGE_LOG\`"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "DROP TABLE \`onyga-482313.OI.TMP_PPC_CHANGE_LOG_PRED\`"
```

Expected: every logged row in the `TMP_` copy carries a `prediction_source`; `OWN_RATIO` rows carry a
`predicted_cpc`; and `rows_written_to_the_LIVE_log_today` is whatever it was before this step and not
one row more. **If it grew, the flag did not take and the rows cannot be removed** — the house rule
forbids a `DELETE` against that table. Stop, label the batch `SUPERSEDED_NEVER_UPLOADED` with
`--supersede`, and record it in the measurements file before continuing.

- [ ] **Step 7: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/tables/FACT_PPC_CHANGE_LOG.sql \
        tools/build_reprice_bulksheet.py \
        tools/tests/test_change_log_discipline.py
git commit -m "feat(pacing): the reprice book logs the prediction it already computed

Four explicit columns rather than overloading expected_impact_weekly, which
records dollars and has not been written since mid-2026. Closes the book half of
violation 13's recording arm."
```

---
## Phase 1 — Precedence, and a ceiling that binds

**Closes:** violation 15 (the book defers to Pacing on answered subjects — precedence backwards).

**Why second: it is pure safety, and it is the doctrine's own motivating failure.** Appendix A: a keyword whose correct price had been known for twenty days; the Brain saw a quiet window and said `NOT_SERVING`, the book stood aside as `ENGINE_INSTRUCTED` (`tools/build_reprice_bulksheet.py:881-882`), and Pacing filled the vacuum with a large raise to relieve campaign click-starvation — a mechanics rule making an economics decision. Nothing in `SP_ENGINE_PREFLIGHT`'s verdict `CASE` (lines 232–256) compares a proposal to any Catalog price; the only Catalog data it reads is `settled_roas90` and `settled_clk90` (lines 137–141). Until the ceiling binds, every later phase that admits more subjects or authorises more action makes wrong actions happen faster. Order safety before throughput.

**Unblocks:** Phase 2 (admitting 74 unjudged spending rows into a system where Pacing no longer overrides the answer); Phase 8's `LEAN_IN`, which is a raise into partly-unknown territory and must be walked through a cap that actually exists.

**A note on violation 16.** §10.3 corrected it: the cap is not symmetric-and-slow, it is **not enforced in either direction**. `FN_MOVE_CAP` below implements the mechanism violation 15's fix requires — the Brain's ceiling must bind on Pacing — and §3.1's asymmetry falls out of it. This is **not** presented as closing violation 16, which stands struck through.

**Size:** S–M — 3–5 days. One CTE widening, two verdict arms, one book inversion, one new SQL function, and the fill for the ceiling column Phase 0 created.

---

### Task 1.1: Measure the breach

**Files:**
- Create (temporary probe, not committed): none — this is a measurement step

- [ ] **Step 1: Count GO bid proposals that already exceed the price the Catalog and the Brain published**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH pf AS (
  SELECT campaign_id, keyword_id, engine, suggested_bid, current_bid
  FROM \`onyga-482313.OI.T_ENGINE_PREFLIGHT\`
  WHERE verdict = 'GO' AND lever = 'BID' AND suggested_bid IS NOT NULL
),
ks AS (
  SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
         affordable_bid, state
  FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`)
),
pl AS (
  SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid, planned_bid
  FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
  WHERE as_of = (SELECT MAX(as_of) FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`)
    AND is_live_plan AND planned_bid IS NOT NULL
)
SELECT COUNTIF(pf.suggested_bid > COALESCE(pl.planned_bid, ks.affordable_bid) + 0.005) AS above_ceiling,
       COUNT(*) AS go_bid_rows,
       ks.state, COUNT(*) AS n
FROM pf
LEFT JOIN ks ON ks.cid = CAST(pf.campaign_id AS STRING) AND ks.kid = CAST(pf.keyword_id AS STRING)
LEFT JOIN pl ON pl.cid = CAST(pf.campaign_id AS STRING) AND pl.kid = CAST(pf.keyword_id AS STRING)
GROUP BY ks.state ORDER BY n DESC"
```

Expected: a non-zero `above_ceiling`. On 2026-08-24 the GO BID rows joined to ladder states TRIAL 18, AT_BAR 9, WINNER 8, PARKED 8, REPRICE 4, PACED_WINNER 4, LAUNCH_CONTAINED 1, FLOOR_PROBATION 1. Record the number you measure — it is the violation count Task 1.5's acceptance suite drives to zero.

- [ ] **Step 2: Locate every copy of the cap, and prove none of them binds on an engine proposal**

```bash
cd /Users/ori/Develop/OI
grep -rn "0.157625\|0.142625\|BLIND_STEPS\|blind_steps\|material_step" scripts/bigquery/ \
  | grep -v "\.bak\."
grep -rn "CAP_UP\|CAP_DOWN\|cap_move\|MATERIAL_STEP\|BLIND_STEPS" tools/*.py | wc -l
grep -rn "cap_up\|cap_down\|FN_MOVE_CAP" scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql \
        scripts/bigquery/views/V_OOB_KEYWORD.sql scripts/bigquery/views/V_KEYWORD_LIFT.sql \
  | grep -v "\.bak\." | wc -l
```

**Expected, and it is NOT zero — read this carefully before writing the function.** The first
command finds the cap in exactly **one live `.sql` file**: `V_PLAN_WINDOW_JUDGMENT.sql:254-264`,
which declares `0.05 AS material_step, 3 AS blind_steps` in its `k` CTE and derives
`POW(1 + material_step, blind_steps) - 1 AS cap_up` and
`1 - POW(1 - material_step, blind_steps) AS cap_down` in its `caps` CTE. That is the same cap in
SQL, and it binds on the Brain's repaired price (P-6) — nowhere else. (Any additional hits are
`.bak` files, which the `grep -v` above already drops; if it still returns `.bak` paths, tighten the
filter rather than counting them.) The second command returns a small non-zero count: the Python
copy in `tools/build_reprice_bulksheet.py`, where `cap_move()` has exactly three callers, all inside
that one generator. **The third command returns `0`, and that is the actual defect** — no cap of any
kind is applied to an engine proposal in either direction, which is §10.3's correction of violation
16 verbatim.

So the cap lives in **two** places today, both of them narrow, and `FN_MOVE_CAP` is built in Task 1.3
to be the third and last: Task 1.3 Step 5 migrates `V_PLAN_WINDOW_JUDGMENT`'s copy onto the function
so the count goes back to two — the function and the Python generator — rather than to three.

- [ ] **Step 3: Record the measurement and commit it**

Every red measurement in this plan is a number the green run is compared against, so it is written
down rather than remembered. Append what you measured — the query, the date, and the count — to the
running record, creating the file on the first task that reaches this step:

```bash
cd /Users/ori/Develop/OI
mkdir -p docs/superpowers/specs
cat >> docs/superpowers/specs/2026-08-25-gap-closure-measurements.md <<'EOF'

## Task 1.1 — measured YYYY-MM-DD

Replace the date above with the date you ran it, and paste below: the query you ran (unchanged from
the task), and its output. Do not summarise the output — the point of this file is that a re-run is
a re-run and not a fresh argument, which is the same reason
docs/superpowers/specs/2026-08-24-three-layers-baseline.md exists.
EOF
git add docs/superpowers/specs/2026-08-25-gap-closure-measurements.md
git commit -m "measure(task 1.1): record the red measurement before the fix

The number the green run is compared against, written down rather than remembered."
```

---

### Task 1.2: The preflight reads the Catalog's price and the Brain's ceiling

**Files:**
- Modify: `scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql:137-141` (the `rec` CTE), `:222-231` (the published column list), `:232-256` (the verdict `CASE`)

- [ ] **Step 1: Back up**

```bash
cd /Users/ori/Develop/OI
NEXT=$(ls scripts/bigquery/**/*.bak.v27.*.* 2>/dev/null | sed -E 's/.*\.bak\.v27\.([0-9]+)\..*/\1/' | sort -n | tail -1)
NEXT=$((NEXT + 1))
cp scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql \
   scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql.bak.v27.$NEXT.$(date +%H%M)
```

- [ ] **Step 2: Widen the `rec` CTE**

Today it reads exactly:

```sql
  rec AS (
    SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
           settled_roas90, settled_clk90
    FROM `onyga-482313.OI.FACT_KEYWORD_GUARD`
  ),
```

Replace with:

```sql
  rec AS (
    SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
           settled_roas90, settled_clk90
    FROM `onyga-482313.OI.FACT_KEYWORD_GUARD`
  ),
  -- ── THE CATALOG'S PRICE (doctrine 7: Pacing may not move a bid on a keyword the Catalog has
  -- answered conclusively, outside the Brain's ceiling). Until 2026-08-25 this gate read exactly
  -- two Catalog columns — settled_roas90 and settled_clk90 above — so no proposal was ever
  -- compared to a price. Appendix A is what that costs: a correct price known for twenty days, the
  -- book standing aside, and Pacing filling the vacuum with a large raise for click-starvation.
  cat AS (
    SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
           affordable_bid, family_bar, bid_floor, state, next_check_date
    FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
    WHERE snapshot_date = (SELECT MAX(snapshot_date)
                           FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
  ),
  -- ── THE BRAIN'S CEILING. The live plan's planned_bid IS the ceiling for a seated keyword; the
  -- good side carries none by P-4, and a keyword the plan has never seen carries none either. Both
  -- absences fall back to the Catalog's affordable_bid below — never to "no ceiling".
  brain AS (
    SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
           planned_bid, move, seat_no
    FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
    WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`)
      AND is_live_plan
  ),
```

- [ ] **Step 3: Resolve the ceiling ONE CTE EARLIER, inside `ranked` — never in the final SELECT**

**Read this before typing.** BigQuery does not expose a `SELECT`-list alias to any other expression
in the same `SELECT` list. The verdict `CASE` in Step 4 and the `verdict_reason` `CASE` live in the
**same** final `SELECT` as the ceiling columns, so a ceiling resolved there would be unreachable from
them. Confirm it yourself in one line before you start, so the shape below is obviously necessary
rather than merely asserted:

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT 1 AS ceiling_bid, CASE WHEN ceiling_bid > 0 THEN 'x' END AS v"
```

Expected: `Error ... Unrecognized name: ceiling_bid`.

So the ceiling is resolved in the `ranked` CTE, which the final `SELECT` reads as `r`. `ranked` today
ends at `SP_ENGINE_PREFLIGHT.sql:217-221`:

```sql
      ) AS owner_engine
    FROM p
    LEFT JOIN own o  ON o.cid = CAST(p.campaign_id AS STRING)
    LEFT JOIN hold h ON h.cid = CAST(p.campaign_id AS STRING)
  )
```

**`) AS owner_engine` IS THE LAST ITEM OF `ranked`'S SELECT LIST AND CARRIES NO TRAILING COMMA.** It
is included in the block below, with the comma added, precisely so the replacement cannot leave
`) AS owner_engine` sitting directly above a new `COALESCE(...)` — which is a bare syntax error and
would fail the deploy on the first line of the phase. Replace those **five** lines with:

```sql
      ) AS owner_engine,
      -- THE CEILING, AND WHO SET IT. The Brain's price wins where it exists, because the Brain
      -- is the layer that allocates (doctrine 1.2); the Catalog's affordable bid is the
      -- fallback, because a keyword outside the plan still has a worth; and a subject with
      -- neither has no ceiling and is left alone by this arm rather than blocked on a guess.
      -- RESOLVED HERE, NOT IN THE FINAL SELECT: the verdict CASE below is in the same SELECT list
      -- as the published columns, and BigQuery cannot read a select-list alias from a sibling
      -- expression. Computing it once in this CTE is also what stops the COALESCE being written
      -- out three times and drifting.
      COALESCE(br.planned_bid, ct.affordable_bid)                          AS ceiling_bid,
      CASE WHEN br.planned_bid    IS NOT NULL THEN 'BRAIN'
           WHEN ct.affordable_bid IS NOT NULL THEN 'CATALOG'
           ELSE 'NONE' END                                                 AS ceiling_source,
      ct.state                                                             AS catalog_state,
      ct.next_check_date                                                   AS catalog_next_check,
      br.move                                                              AS brain_move
    FROM p
    LEFT JOIN own o  ON o.cid = CAST(p.campaign_id AS STRING)
    LEFT JOIN hold h ON h.cid = CAST(p.campaign_id AS STRING)
    -- both joins are 1:1 by the source's own key and cannot fan `p` out. VERIFY IT, do not assume
    -- it: on 2026-08-24 FACT_KEYWORD_STATE's latest snapshot held 838 rows over 838 distinct
    -- (campaign_id, keyword_id) pairs and the live plan partition held 365 over 365. Phase 2 Task
    -- 2.3 adds sentinel SB targets, which ARE many-per-(campaign, keyword) — that task carries the
    -- step that re-keys this join onto subject_key before it can fan anything out.
    LEFT JOIN cat   ct ON ct.cid = CAST(p.campaign_id AS STRING) AND ct.kid = CAST(p.keyword_id AS STRING)
    LEFT JOIN brain br ON br.cid = CAST(p.campaign_id AS STRING) AND br.kid = CAST(p.keyword_id AS STRING)
  )
```

Then, in the final `SELECT`, immediately after the existing `rc.settled_roas90, rc.settled_clk90,`
line, publish them off `r`:

```sql
         r.ceiling_bid, r.ceiling_source, r.catalog_state, r.catalog_next_check, r.brain_move,
```

- [ ] **Step 4: Add the verdict arm above `ELSE 'GO'`**

The verdict `CASE` today ends:

```sql
      WHEN COALESCE(r.season_relax_applied, FALSE) THEN 'REVIEW'
      ELSE 'GO' END AS verdict,
```

Replace with:

```sql
      WHEN COALESCE(r.season_relax_applied, FALSE) THEN 'REVIEW'
      -- ── 2026-08-25, VIOLATION 15: THE CEILING BINDS. Doctrine 7 forbids Pacing moving a bid on
      -- a keyword the Catalog has answered conclusively, outside the Brain's ceiling. This is
      -- EXCLUDE and not REVIEW deliberately: a REVIEW is a queue a person has to empty, and the
      -- twenty-day failure in Appendix A happened while everybody agreed on the price. A proposal
      -- above the ceiling is not a judgement call, it is a proposal to overpay.
      -- The >$2.00 arm above stays as a second, weaker net for subjects with no ceiling at all.
      WHEN r.lever = 'BID' AND r.ceiling_bid IS NOT NULL
        AND r.suggested_bid > r.ceiling_bid + 0.005 THEN 'EXCLUDE'
      -- ── AND THE PRECEDENCE ARM, WHICH IS NOT THE SAME RULE ─────────────────────────────────
      -- The arm above catches a proposal to OVERPAY. This one catches a second price for one
      -- keyword. Doctrine 7: "precedence is: the Brain's instruction wins." Where the live plan has
      -- issued a move for this subject, the Brain has already said what its price is, and an engine
      -- BID — at ANY level, including one comfortably under the ceiling — is a competing instruction
      -- for the same keyword on the same night.
      -- THIS ARM IS WHAT MAKES TASK 1.4 SAFE. Until Task 1.4 the book suppressed its own row on any
      -- GO engine instruction (ENGINE_INSTRUCTED), so only one row ever existed. Task 1.4 inverts
      -- that — correctly, because standing aside is the violation — and without this arm the two
      -- rows would BOTH become live upload rows, with nothing but a README sentence asking a person
      -- to delete one. The rule that resolves them must live in the warehouse, not in a sentence.
      -- BUDGET is untouched: a budget is a campaign-grain lever and the plan's move is keyword-grain,
      -- so they are not two prices for one thing.
      WHEN r.lever = 'BID' AND COALESCE(r.brain_move, 'NONE') NOT IN ('NONE', 'NONE_HOLDOUT')
        THEN 'EXCLUDE'
      ELSE 'GO' END AS verdict,
```

and in the `verdict_reason` `CASE`, immediately above its own final `ELSE`, add the matching sentence:

```sql
      WHEN r.lever = 'BID' AND r.ceiling_bid IS NOT NULL
        AND r.suggested_bid > r.ceiling_bid + 0.005
        THEN CONCAT('skipped — ', IF(r.ceiling_source = 'BRAIN', 'the plan', 'the keyword state'),
                    ' prices this keyword at $', CAST(ROUND(r.ceiling_bid, 2) AS STRING),
                    ' and this proposal would pay $', CAST(ROUND(r.suggested_bid, 2) AS STRING),
                    '. Worth is decided above the auction, not in it: the engine may find the path '
                    'to a price, never choose one higher than the price it was given.')
      WHEN r.lever = 'BID' AND COALESCE(r.brain_move, 'NONE') NOT IN ('NONE', 'NONE_HOLDOUT')
        THEN CONCAT('skipped — the plan has already issued ', r.brain_move, ' for this keyword '
                    'tonight, so this proposal is a second price for one keyword. Precedence is the '
                    'Brain''s instruction (doctrine 7); the engine''s row is the one that goes.')
```

- [ ] **Step 5: Deploy and confirm the columns reach the table**

The five columns are published off `r` in Step 3, which resolves them in the `ranked` CTE — so the
verdict arms in Step 4 can read them and the table receives them. Confirm both:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_ENGINE_PREFLIGHT\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT ceiling_source, verdict, COUNT(*) n
   FROM \`onyga-482313.OI.T_ENGINE_PREFLIGHT\` WHERE lever = 'BID'
   GROUP BY 1, 2 ORDER BY n DESC"
# and the precedence arm on its own: no BID proposal survives on a subject the plan moved
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT COUNTIF(verdict = 'GO' AND COALESCE(brain_move,'NONE') NOT IN ('NONE','NONE_HOLDOUT'))
            AS two_prices_for_one_keyword
   FROM \`onyga-482313.OI.T_ENGINE_PREFLIGHT\` WHERE lever = 'BID'"
```

Expected: rows with `ceiling_source` in (`BRAIN`, `CATALOG`, `NONE`) and a non-zero count of `EXCLUDE`
under `BRAIN` or `CATALOG` — the breach measured in Task 1.1, now blocked — and
`two_prices_for_one_keyword = 0`. That second number is the one Task 1.4 depends on: it is what makes
it safe for the book to stop standing aside.

- [ ] **Step 6: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql
git commit -m "feat(pacing): the Brain's ceiling binds on every engine bid proposal

Closes half of violation 15. The gate read two Catalog columns and no price; it
now resolves a ceiling (Brain's planned_bid, else the Catalog's affordable_bid),
publishes it with its source, and EXCLUDEs any BID proposal above it. A second
arm EXCLUDEs any BID on a subject the live plan has already moved — precedence
is the Brain's instruction, and that is what makes Task 1.4 safe."
```

---

### Task 1.3: `FN_MOVE_CAP` — one cap, asymmetric by direction

**Files:**
- Create: `scripts/bigquery/functions/FN_MOVE_CAP.sql`
- Modify: `scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql` (apply the cap, both directions)
- Modify: `scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql:261-266` (the `caps` CTE — migrate the second copy of the constant onto the function)
- Modify: `scripts/bigquery/procedures/SP_SNAPSHOT_ENGINE_PROPOSALS.sql` (Step 5 — fill `ceiling_at_proposal`, which Task 0.5 created and left `NULL`)
- Modify: `config.yaml` (`functions:` section, beside `FN_BID_FLOOR` at index 2)

§3.1: a cut to a known ceiling at HIGH confidence goes immediately, because a cut to a ceiling cannot overshoot; a raise into unknown territory keeps the blind-step limit. The constants live today only in `tools/build_reprice_bulksheet.py:160-170` and bind inside one generator.

- [ ] **Step 1: Write the function**

```sql
-- =============================================================================================
-- FN_MOVE_CAP — how far one upload may move a bid, in ONE place, callable from SQL.
--
-- WHY IT EXISTS. The house per-upload cap (three blind 5% steps: +15.7625% / -14.2625%) lived in
-- exactly two narrow places and bound on no engine proposal in either direction:
--   * tools/build_reprice_bulksheet.py, where cap_move() has three callers, all inside that one
--     generator; and
--   * V_PLAN_WINDOW_JUDGMENT.sql's k / caps CTEs, which declare material_step 0.05 and
--     blind_steps 3 and derive cap_up / cap_down from them — binding only on the Brain's repaired
--     price (P-6), and on nothing that Pacing emits.
-- Neither reaches SP_ENGINE_PREFLIGHT, V_OOB_KEYWORD or V_KEYWORD_LIFT, so an engine proposal was
-- bounded by nothing. architecture/THREE_LAYERS.md 10.3 corrected violation 16 to exactly this: the
-- defect is not that the cap is symmetric, it is that no cap binds at all.
-- THIS FUNCTION IS THE ONE DEFINITION IN SQL. Step 5 of this task migrates V_PLAN_WINDOW_JUDGMENT's
-- copy onto it in the same commit, so the constant does not end up living in three places.
--
-- THE ASYMMETRY IS 3.1's, AND IT IS ABOUT WHAT CAN OVERSHOOT.
--   * A CUT TO A KNOWN CEILING AT HIGH CONFIDENCE CANNOT OVERSHOOT — the ceiling is the target, and
--     every click bought above it loses money by definition. It goes in one step.
--   * A RAISE HAS NO STOPPING POINT, so overshoot is real waste. It keeps the blind-step limit,
--     whatever the confidence.
--   * A cut below HIGH confidence is still a cut into partly-unknown territory and is walked.
--
-- THE CAP IS A DISTANCE, NOT A PRICE: it returns the furthest bid this upload may set. The caller
-- still clamps to the floor and to the ceiling; this function knows nothing about either.
-- Rounding is INWARD to the cent (a capped raise floors, a capped cut ceils) so cent rounding can
-- never carry a move past the cap — the same rule cap_move() applies in the book.
--
-- confidence: 'HIGH' | 'MEDIUM' | 'LOW' | 'NO_EVIDENCE' | NULL. Anything that is not exactly 'HIGH'
-- is treated as not-HIGH, which is the safe direction.
-- =============================================================================================
CREATE OR REPLACE FUNCTION `onyga-482313.OI.FN_MOVE_CAP`(
  current_bid FLOAT64, direction STRING, confidence STRING
)
RETURNS FLOAT64
AS (
  CASE
    WHEN current_bid IS NULL OR current_bid <= 0 THEN NULL
    -- a confident cut goes straight to the target: no cap, expressed as a bound of zero
    WHEN UPPER(direction) = 'DOWN' AND UPPER(COALESCE(confidence, '')) = 'HIGH' THEN 0.0
    -- an unconfident cut walks: three blind 5% steps down = 1 - 0.95^3 = 0.142625
    WHEN UPPER(direction) = 'DOWN'
      THEN CEIL(current_bid * (1.0 - 0.142625) * 100 - 0.000000001) / 100
    -- every raise walks: three blind 5% steps up = 1.05^3 - 1 = 0.157625
    WHEN UPPER(direction) = 'UP'
      THEN FLOOR(current_bid * (1.0 + 0.157625) * 100 + 0.000000001) / 100
    ELSE NULL
  END
);
```

- [ ] **Step 2: Deploy and unit-check the four branches**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/functions/FN_MOVE_CAP.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT
  \`onyga-482313.OI.FN_MOVE_CAP\`(1.00, 'DOWN', 'HIGH')   AS cut_high,
  \`onyga-482313.OI.FN_MOVE_CAP\`(1.00, 'DOWN', 'MEDIUM') AS cut_medium,
  \`onyga-482313.OI.FN_MOVE_CAP\`(1.00, 'UP',   'HIGH')   AS raise_high,
  \`onyga-482313.OI.FN_MOVE_CAP\`(1.00, 'UP',   NULL)     AS raise_null,
  \`onyga-482313.OI.FN_MOVE_CAP\`(NULL, 'UP',   'HIGH')   AS no_current"
```

Expected exactly: `cut_high 0.0`, `cut_medium 0.86`, `raise_high 1.15`, `raise_null 1.15`, `no_current NULL`.

- [ ] **Step 3: Apply the cap inside the preflight**

In the final `SELECT` of `SP_ENGINE_PREFLIGHT`, immediately after the `brain_move` line added in Task 1.2, add:

```sql
         -- ── THE MOVE CAP, PUBLISHED SO IT BINDS ON EVERY EMITTER (2026-08-25). The cap has never
         -- existed in SQL — only inside one Python generator — so nothing bounded an engine's step.
         -- Confidence is not computed until Phase 7, so it is passed as NULL here and every move
         -- walks. That is the safe reading. Task 7.5 Step 4 is the task that replaces this literal
         -- NULL with ct.confidence_band and re-deploys this procedure; nothing else does, and
         -- leaving it at NULL forever would silently keep confident cuts walking.
         CASE WHEN r.lever = 'BID' AND r.suggested_bid IS NOT NULL AND r.current_bid IS NOT NULL
                   AND r.suggested_bid < r.current_bid
              THEN `onyga-482313.OI.FN_MOVE_CAP`(r.current_bid, 'DOWN', NULL)
              WHEN r.lever = 'BID' AND r.suggested_bid IS NOT NULL AND r.current_bid IS NOT NULL
                   AND r.suggested_bid > r.current_bid
              THEN `onyga-482313.OI.FN_MOVE_CAP`(r.current_bid, 'UP', NULL)
              ELSE NULL END                                             AS move_cap_bid,
```

and add **two** more arms to the verdict `CASE` — one per direction — immediately below the ceiling
arm added in Task 1.2. **Both directions, deliberately:** §10.3's measured finding, which is this
phase's whole motivation, is that CUTS break their cap proportionally MORE often than raises break
theirs. A one-directional cap would leave the larger half of the measured breach unlabelled.

```sql
      -- a move beyond one upload's cap is not refused, it is TRIMMED by the consumer — but a
      -- proposal that ignores the cap entirely is a defect, so it is labelled here.
      WHEN r.lever = 'BID' AND r.current_bid IS NOT NULL AND r.suggested_bid IS NOT NULL
        AND r.suggested_bid > r.current_bid
        AND r.suggested_bid > `onyga-482313.OI.FN_MOVE_CAP`(r.current_bid, 'UP', NULL) + 0.005
        THEN 'REVIEW'
      -- the CUT arm. FN_MOVE_CAP returns 0.0 for a HIGH-confidence cut (go straight to the target),
      -- so this arm can never fire once Task 7.5 passes a real confidence band — which is exactly
      -- 3.1's asymmetry expressing itself rather than a special case bolted on.
      WHEN r.lever = 'BID' AND r.current_bid IS NOT NULL AND r.suggested_bid IS NOT NULL
        AND r.suggested_bid < r.current_bid
        AND r.suggested_bid < `onyga-482313.OI.FN_MOVE_CAP`(r.current_bid, 'DOWN', NULL) - 0.005
        THEN 'REVIEW'
```

with the matching `verdict_reason` arms, placed in the same relative positions:

```sql
      WHEN r.lever = 'BID' AND r.current_bid IS NOT NULL AND r.suggested_bid IS NOT NULL
        AND r.suggested_bid > r.current_bid
        AND r.suggested_bid > `onyga-482313.OI.FN_MOVE_CAP`(r.current_bid, 'UP', NULL) + 0.005
        THEN CONCAT('needs a look — this raises $', CAST(ROUND(r.current_bid, 2) AS STRING),
                    ' to $', CAST(ROUND(r.suggested_bid, 2) AS STRING),
                    ', further than one upload may move a bid it cannot observe ($',
                    CAST(ROUND(`onyga-482313.OI.FN_MOVE_CAP`(r.current_bid, 'UP', NULL), 2) AS STRING),
                    '). Raising into unknown territory is walked, never taken in one step.')
      WHEN r.lever = 'BID' AND r.current_bid IS NOT NULL AND r.suggested_bid IS NOT NULL
        AND r.suggested_bid < r.current_bid
        AND r.suggested_bid < `onyga-482313.OI.FN_MOVE_CAP`(r.current_bid, 'DOWN', NULL) - 0.005
        THEN CONCAT('needs a look — this cuts $', CAST(ROUND(r.current_bid, 2) AS STRING),
                    ' to $', CAST(ROUND(r.suggested_bid, 2) AS STRING),
                    ', below the furthest one upload may cut a bid it is not yet sure about ($',
                    CAST(ROUND(`onyga-482313.OI.FN_MOVE_CAP`(r.current_bid, 'DOWN', NULL), 2) AS STRING),
                    '). A cut to a ceiling we are sure of goes in one step; this is not one.')
```

- [ ] **Step 4: Deploy and verify**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_ENGINE_PREFLIGHT\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT verdict, COUNT(*) n,
          COUNTIF(suggested_bid > current_bid
                  AND suggested_bid > move_cap_bid + 0.005) beyond_cap_up,
          COUNTIF(suggested_bid < current_bid
                  AND suggested_bid < move_cap_bid - 0.005) beyond_cap_down
   FROM \`onyga-482313.OI.T_ENGINE_PREFLIGHT\` WHERE lever = 'BID' GROUP BY 1 ORDER BY n DESC"
```

Expected: every row with `beyond_cap_up > 0` **or** `beyond_cap_down > 0` reads verdict `REVIEW` or
`EXCLUDE`, never `GO`. **Both columns matter**: §10.3 measured cuts breaking their cap more often
than raises, so a check that only looked upward would report green on the larger half.

- [ ] **Step 4b: Migrate `V_PLAN_WINDOW_JUDGMENT`'s copy of the cap onto the function**

Back up the view (header Step 0), then in `scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql` replace
the `caps` CTE at lines 261–266, which today reads:

```sql
caps AS (
  SELECT k.*,
         POW(1 + k.material_step, k.blind_steps) - 1 AS cap_up,
         1 - POW(1 - k.material_step, k.blind_steps) AS cap_down
  FROM k
),
```

with:

```sql
caps AS (
  -- 2026-08-25: the cap is FN_MOVE_CAP's, not this view's. material_step and blind_steps stay in k
  -- because the row sentences quote them ("three 5% steps"), but the arithmetic that binds on P-6's
  -- repaired price is now the same arithmetic that binds on every engine proposal — one definition,
  -- in one place, per 10.3's correction of violation 16. cap_up / cap_down keep their meaning
  -- (fractions, not prices) so line 532's expression and every sentence below are untouched.
  SELECT k.*,
         `onyga-482313.OI.FN_MOVE_CAP`(1.0, 'UP',   NULL) - 1.0 AS cap_up,
         1.0 - `onyga-482313.OI.FN_MOVE_CAP`(1.0, 'DOWN', NULL) AS cap_down
  FROM k
),
```

`FN_MOVE_CAP(1.0, …)` returns the cap as a fraction of a $1.00 bid because the function is a
distance, which is exactly what `cap_up` and `cap_down` already were. Verify the two agree to the
cent before and after — the function rounds inward to the cent and the old expression did not, so a
tiny difference is expected and is the function being stricter, never looser:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT POW(1.05, 3) - 1                                          AS old_cap_up,
       \`onyga-482313.OI.FN_MOVE_CAP\`(1.0, 'UP', NULL) - 1.0     AS new_cap_up,
       1 - POW(0.95, 3)                                          AS old_cap_down,
       1.0 - \`onyga-482313.OI.FN_MOVE_CAP\`(1.0, 'DOWN', NULL)   AS new_cap_down"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql)"
```

Expected, and verified on 2026-08-24 before this task was written: `old_cap_up 0.157625` becomes
`new_cap_up 0.15`, and `old_cap_down 0.142625` becomes `new_cap_down 0.14`. **Both shrink**, because
the function rounds INWARD to the cent in each direction — a capped raise floors, a capped cut ceils
— so the new caps are strictly the more conservative of the two on a $1.00 bid. Assert the
direction, not equality:

- `new_cap_up <= old_cap_up + 1e-9`
- `new_cap_down <= old_cap_down + 1e-9`

This is a real, small behaviour change to P-6's repaired price: it moves at most a cent per dollar of
bid, and it moves it toward the current price. Say so in the commit message. If an acceptance row
fails on a tolerance rather than a behaviour, widen that check's tolerance to the cent and say so in
the check's comment — never widen the cap.

- [ ] **Step 5: Fill `ceiling_at_proposal`, the column Task 0.5 created and left `NULL`**

Task 0.5 added `ceiling_at_proposal` to `FACT_ENGINE_PROPOSALS` and wrote
`CAST(NULL AS FLOAT64)` on all nine `INSERT`s, because no layer published a ceiling yet. Task 1.2
publishes one — but it publishes it on `T_ENGINE_PREFLIGHT`, written by a **different procedure one
orchestrator task later**. Nothing has written this column, and nothing will unless this step does.

In `scripts/bigquery/procedures/SP_SNAPSHOT_ENGINE_PROPOSALS.sql`, add a temp table beside the
`bid_cpc_model` and `own_click_rate` tables Task 0.5 built:

```sql
  -- ── THE CEILING IN FORCE WHEN THE PROPOSAL WAS MADE (2026-08-25, violation 13) ──────────────
  -- The SAME COALESCE SP_ENGINE_PREFLIGHT's `ranked` CTE resolves, and deliberately the same one:
  -- the scorecard's whole question is "was this proposal inside the price the house had already
  -- decided", and two different ceilings would make the answer unreadable.
  -- IT IS DELIBERATELY THE CEILING AS OF *NOW*, WHICH FOR THE PLAN MEANS YESTERDAY'S PARTITION.
  -- This procedure is orchestrator task 20.6 and SP_BUILD_NEXT_WEEK_PLAN is 20.8c, so the newest
  -- live plan at proposal time is the previous pass's. That is correct and is what the column
  -- NAME says: the ceiling in force when the engine proposed, not the one it was later judged by.
  -- The one-pass lag is a known open ruling (Task 6.11) and this column must not close it.
  CREATE OR REPLACE TEMP TABLE ceiling_now AS
  WITH cat AS (
    SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid, affordable_bid
    FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
    WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
  ),
  brain AS (
    SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid, planned_bid
    FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
    WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`) AND is_live_plan
  )
  SELECT COALESCE(cat.cid, brain.cid) AS cid, COALESCE(cat.kid, brain.kid) AS kid,
         COALESCE(brain.planned_bid, cat.affordable_bid) AS ceiling_bid,
         CASE WHEN brain.planned_bid    IS NOT NULL THEN 'BRAIN'
              WHEN cat.affordable_bid   IS NOT NULL THEN 'CATALOG'
              ELSE 'NONE' END                       AS ceiling_source
  FROM cat FULL OUTER JOIN brain ON brain.cid = cat.cid AND brain.kid = cat.kid;
```

Then, on the **seven bid-bearing `INSERT`s** (not the two `NEGATE` ones, which carry
`'NOT_A_PRICE_LEVER'` and no join), replace

```sql
         CAST(NULL AS FLOAT64)                                              AS ceiling_at_proposal,
```

with

```sql
         cl.ceiling_bid                                                     AS ceiling_at_proposal,
```

and add the join beside the ones Task 0.5 already carries:

```sql
  LEFT JOIN ceiling_now cl
    ON cl.cid = CAST(v.campaign_id AS STRING)
   AND cl.kid = CAST(v.keyword_id AS STRING)
```

**Check the grain before you deploy it — this join is on the money path of a nightly procedure:**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH cat AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid
             FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`
             WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`)),
     brn AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid
             FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
             WHERE as_of = (SELECT MAX(as_of) FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`) AND is_live_plan),
     u AS (SELECT cid, kid FROM cat UNION DISTINCT SELECT cid, kid FROM brn)
SELECT COUNT(*) rows_, COUNT(DISTINCT CONCAT(cid,'|',kid)) pairs FROM u"
```

Expected: `rows_ = pairs`. Then deploy, run, and confirm the column is no longer empty:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_ENGINE_PROPOSALS.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_ENGINE_PROPOSALS\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT lever, COUNT(*) n, COUNTIF(ceiling_at_proposal IS NOT NULL) with_a_ceiling
FROM \`onyga-482313.OI.FACT_ENGINE_PROPOSALS\`
WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_ENGINE_PROPOSALS\`)
GROUP BY 1 ORDER BY n DESC"
```

Expected: every `BID` row carries a ceiling except the handful with neither a Catalog nor a plan row;
`NEGATE` rows carry none, which is correct. Record the fraction in the measurements file — it is the
denominator `V_PACING_SCORECARD` (Task 10.4) will grade the engines against.

- [ ] **Step 5b: Register `FN_MOVE_CAP` in `config.yaml`**

Insert in the `functions:` list immediately after `FN_BID_FLOOR` (index 2):

```yaml
  - name: FN_MOVE_CAP
    description: >-
      How far one upload may move a bid, in one place and callable from SQL. Returns the furthest
      bid this upload may set — a distance, not a price; the caller still clamps to the floor and
      the ceiling. Asymmetric by direction per architecture/THREE_LAYERS.md 3.1: a cut to a known
      ceiling at HIGH confidence returns 0.0 (go immediately, a cut to a ceiling cannot overshoot),
      every raise and every unconfident cut keep the three blind 5% steps. Built because the cap
      existed only inside tools/build_reprice_bulksheet.py and therefore bound on nothing else —
      10.3's correction of violation 16. Rounds inward to the cent so cent rounding cannot carry a
      move past the cap.
    type: sql_udf
    source_files:
      - scripts/bigquery/functions/FN_MOVE_CAP.sql
```

- [ ] **Step 6: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/functions/FN_MOVE_CAP.sql \
        scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql \
        scripts/bigquery/procedures/SP_SNAPSHOT_ENGINE_PROPOSALS.sql \
        scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql config.yaml \
        architecture/THREE_LAYERS.md
git commit -m "feat(pacing): FN_MOVE_CAP publishes the move cap so it binds outside Python

Implements 3.1's asymmetry — an immediate confident cut, a walked raise — and
applies it in the preflight. Not a fix for violation 16, which is struck through:
10.3's measured defect is that no cap bound in either direction — and §8's entry
for 16 is amended to say the live half is now closed. Also fills
ceiling_at_proposal, which Task 0.5 created and no other step writes."
```

---

### Task 1.4: Invert the book's deference

**Files:**
- Modify: `tools/build_reprice_bulksheet.py:881-882` (the `ENGINE_INSTRUCTED` early return), `:1063-1065` (the story sentence), `:908-916` (the FLOOR_PROBATION warning), `:918-925` and `:1483-1500` (the landing exception — preserved unchanged)
- Create: `tools/tests/test_reprice_precedence.py`

Today the book returns `ENGINE_INSTRUCTED` on **any** GO engine BID/BUDGET instruction outside `FLOOR_PROBATION`, suppressing its own priced row with no comparison at all, and its published sentence states the precedence backwards.

- [ ] **Step 1: Write the failing test**

```python
"""PRECEDENCE (violation 15). architecture/THREE_LAYERS.md 7: "a generator or book that stands
aside for an engine on an answered keyword" is forbidden — precedence is the Brain's instruction,
then the Catalog's price, and only then the engine's.

WHAT WENT WRONG. build_reprice_bulksheet.py returned ENGINE_INSTRUCTED on any GO engine BID or
BUDGET instruction outside FLOOR_PROBATION, without comparing the two prices, and its README said
"one keyword, one price; the book yields". Appendix A is the cost: a correct price known for twenty
days, the book standing aside, and Pacing raising the bid to relieve campaign click-starvation.

These tests read the source rather than the warehouse, like their siblings in
test_change_log_discipline.py, so they run with no credentials.
"""
import os
import re
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

import build_reprice_bulksheet as reprice  # noqa: E402

SRC = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..',
                        'build_reprice_bulksheet.py')).read()


def test_the_book_no_longer_yields_unconditionally_to_an_engine():
    """The bare `if bits['engine'] and state != 'FLOOR_PROBATION': return 'ENGINE_INSTRUCTED'`
    early return is gone. A book row may only be dropped after the two prices are compared."""
    assert "return 'ENGINE_INSTRUCTED', None, None, checks, bits" not in SRC


def test_the_book_keeps_its_row_when_the_catalog_has_priced_the_subject():
    """The surviving disposition must be the engine's row being excluded, not the book's."""
    assert 'ENGINE_EXCLUDED_BOOK_WINS' in SRC


def test_the_readme_sentence_states_the_precedence_forwards():
    """Read as two fragments, not one phrase. The replacement sentence in Step 4 wraps across two
    adjacent f-string literals — `... so the engine ` / `yields: ...` — so the words are contiguous
    in the PRINTED sentence and never contiguous in the SOURCE. Asserting the joined phrase would
    make this test unpassable against the very edit it is testing."""
    assert 'the book yields' not in SRC
    assert 'so the engine ' in SRC
    assert 'yields: its row is excluded' in SRC


def test_the_floor_probation_landing_exception_survives():
    """A row whose floor lies within one more engine step beyond the cap lands AT the floor,
    uncapped, because the probation clock only starts when a bid at the floor lands."""
    assert '(1 - MATERIAL_STEP) ** (BLIND_STEPS + 1)' in SRC


def test_the_hand_resolution_warning_survives_with_the_precedence_restated():
    assert 'keep ONE' in SRC
    assert 'delete the ENGINE line' in SRC
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd /Users/ori/Develop/OI
/usr/local/bin/python3 -m pytest tools/tests/test_reprice_precedence.py -q
```

Expected: FAIL — `test_the_book_no_longer_yields_unconditionally_to_an_engine` and three others fail; the source still contains the bare early return and the backwards sentence.

- [ ] **Step 3: Replace the early return with a comparison**

`tools/build_reprice_bulksheet.py` today contains, among the exclusions:

```python
    if bits['engine'] and state != 'FLOOR_PROBATION':
        return 'ENGINE_INSTRUCTED', None, None, checks, bits
```

Replace with:

```python
    # ── PRECEDENCE, THE RIGHT WAY ROUND (2026-08-25, violation 15) ────────────────────────────
    # This used to be `return 'ENGINE_INSTRUCTED'` — the book suppressing its own priced row on any
    # GO engine instruction, with no comparison of the two prices. Doctrine 7 forbids it: worth is
    # decided above the auction, so where the Catalog has answered, the book's price wins and the
    # ENGINE row is the one that must go. The engine row is excluded in the warehouse by
    # SP_ENGINE_PREFLIGHT's ceiling arm; here the book simply stops standing aside, and says on the
    # row that a person must delete the engine line if both somehow reach a sheet.
    if bits['engine'] and state != 'FLOOR_PROBATION':
        checks.append(f"{bits['engine']} also speaks for this keyword today; the keyword state has "
                      f"answered it, so the book's price stands and the engine's row is excluded — "
                      f"if both reach a sheet, delete the ENGINE line")
        bits['engine_excluded'] = True
```

- [ ] **Step 3b: Make `ENGINE_EXCLUDED_BOOK_WINS` REACHABLE — the deleted return was its only producer**

`return 'ENGINE_INSTRUCTED', ...` at `:881-882` is the **only** site in the file that ever produced
that disposition (`grep -n ENGINE_INSTRUCTED` returns exactly three lines: the `classify` docstring at
`:837`, that return, and the story branch at `:1063`). Step 3 deletes it, so unless a new site
produces the replacement, both the constant below and the story branch in Step 4 are dead code and the
book silently loses the ability to say what happened.

Add the constant beside the other non-executable dispositions:

```python
# a disposition that produces NO bulksheet row and NO change-log row: an engine also spoke for this
# keyword, the book had no move of its own to make, and the ENGINE's row is the one excluded — by
# SP_ENGINE_PREFLIGHT's precedence arm, not by this book standing aside.
ENGINE_EXCLUDED_BOOK_WINS = 'ENGINE_EXCLUDED_BOOK_WINS'
```

and produce it in `classify()` (`:833-848`), the single wrapper every disposition already passes
through, immediately above its final `return`:

```python
    # PRECEDENCE, SAID ON THE ROW (2026-08-25, violation 15). Two cases, and they are different:
    #   * the book HAS a move — it is on the sheet, and the check line added above tells a reader
    #     that the engine's competing row was excluded. The disposition is the book's own.
    #   * the book has NO move — nothing goes on the sheet from either side tonight, and the row
    #     must still say why, or a reader sees silence where a keyword had two suitors.
    if bits.get('engine_excluded') and disp not in EXECUTABLE:
        return ENGINE_EXCLUDED_BOOK_WINS, None, None, checks, bits
```

Add a fourth assertion to the test file so this stays reachable:

```python
def test_the_engine_excluded_disposition_is_actually_produced():
    """A constant nothing returns is a comment. The old early return was the only producer of
    ENGINE_INSTRUCTED; its replacement must have a producer too."""
    assert 'return ENGINE_EXCLUDED_BOOK_WINS' in SRC
```

- [ ] **Step 4: Rewrite the story sentence**

The sentence at `tools/build_reprice_bulksheet.py:1063-1065` today reads:

```python
    elif disp == 'ENGINE_INSTRUCTED':
        move = (f"no book row — {bits['engine']} already carries a GO instruction on "
                f"this keyword today (one keyword, one price); the book yields")
```

Replace with:

```python
    elif disp == ENGINE_EXCLUDED_BOOK_WINS:
        move = (f"no book row — {bits['engine']} also carries an instruction on this keyword today "
                f"and the book had no move of its own to make. One keyword, one price, and the "
                f"price is the one the keyword state answered, so the engine "
                f"yields: its row is excluded by the preflight, which refuses any engine BID on a "
                f"keyword the plan has already moved and any bid above the ceiling. "
                f"If both somehow reach a sheet, delete the ENGINE line")
```

**The exclusion is enforced in the warehouse, not by this sentence.** Task 1.2 Step 4 ships two
`EXCLUDE` arms in `SP_ENGINE_PREFLIGHT`: one for a proposal above the ceiling, and one for **any**
engine `BID` on a subject the live plan has moved, at any level. Before Task 1.2, inverting this
book's deference would have put the book's row and the engine's row on two live sheets for one
keyword with only a README asking a person to delete one — which is why Task 1.2 comes first, and why
its Step 5 asserts `two_prices_for_one_keyword = 0` before this task begins.

- [ ] **Step 5: Restate the FLOOR_PROBATION hand-resolution warning**

At `tools/build_reprice_bulksheet.py:908-916` the warning today ends `keep ONE (delete this line to let the engine's stand)`. Replace that parenthetical with:

```python
                          f"keyword; keep ONE — delete the ENGINE line, because the floor is the "
                          f"answer the state machine reached and the engine has not seen it")
```

The landing exception at `:918-925` and its README text at `:1483-1500` are **not** changed.

- [ ] **Step 6: Run the tests**

```bash
cd /Users/ori/Develop/OI
/usr/local/bin/python3 -m pytest tools/tests/test_reprice_precedence.py tools/tests/test_change_log_discipline.py -q
```

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
cd /Users/ori/Develop/OI
git add tools/build_reprice_bulksheet.py tools/tests/test_reprice_precedence.py
git commit -m "fix(books): the book's priced row wins over an engine instruction

Closes the book half of violation 15. ENGINE_INSTRUCTED suppressed the book's own
price with no comparison, and the README stated the precedence backwards. The
FLOOR_PROBATION landing exception is preserved unchanged."
```

---

### Task 1.5: `ENGINE_PREFLIGHT_acceptance.sql`

**Files:**
- Create: `scripts/bigquery/tests/ENGINE_PREFLIGHT_acceptance.sql`

- [ ] **Step 1: Write the suite**

```sql
-- =============================================================================================
-- T_ENGINE_PREFLIGHT acceptance — the ceiling binds. EVERY ROW MUST READ PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Doctrine: architecture/THREE_LAYERS.md 7 (Pacing may not move a bid outside the Brain's ceiling),
-- 3.1 (a raise is walked). Object: scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql.
-- =============================================================================================
WITH t AS (SELECT * FROM `onyga-482313.OI.T_ENGINE_PREFLIGHT`),
e01 AS (
  SELECT 'E01 no GO bid proposal exceeds its ceiling (doctrine 7)' AS check_name,
         COUNTIF(verdict = 'GO' AND lever = 'BID'
                 AND ceiling_bid IS NOT NULL
                 AND suggested_bid > ceiling_bid + 0.005) AS violations
  FROM t
),
e02 AS (
  SELECT 'E02 every ceiling carries the layer that set it',
         COUNTIF(ceiling_bid IS NOT NULL AND ceiling_source NOT IN ('BRAIN','CATALOG'))
       + COUNTIF(ceiling_bid IS NULL AND ceiling_source != 'NONE')
  FROM t
),
e03 AS (
  SELECT 'E03 every EXCLUDE names why in words a person can act on',
         COUNTIF(verdict = 'EXCLUDE' AND (verdict_reason IS NULL OR LENGTH(verdict_reason) < 20))
  FROM t
),
e04 AS (
  SELECT 'E04 no GO bid raise exceeds one upload move cap (3.1)',
         COUNTIF(verdict = 'GO' AND lever = 'BID'
                 AND current_bid IS NOT NULL AND suggested_bid > current_bid
                 AND suggested_bid > `onyga-482313.OI.FN_MOVE_CAP`(current_bid, 'UP', NULL) + 0.005)
  FROM t
),
e04b AS (
  -- BOTH DIRECTIONS. 10.3's measured finding is that CUTS break their cap proportionally MORE often
  -- than raises break theirs, so a suite that only checked upward would report green on the larger
  -- half of the breach. FN_MOVE_CAP returns 0.0 for a HIGH-confidence cut, so once Task 7.5 passes a
  -- real confidence band this check simply stops firing on confident cuts — which is 3.1's
  -- asymmetry, not an exemption.
  SELECT 'E04b no GO bid cut exceeds one upload move cap (3.1, the direction 10.3 measured)',
         COUNTIF(verdict = 'GO' AND lever = 'BID'
                 AND current_bid IS NOT NULL AND suggested_bid < current_bid
                 AND suggested_bid < `onyga-482313.OI.FN_MOVE_CAP`(current_bid, 'DOWN', NULL) - 0.005)
  FROM t
),
e05 AS (
  SELECT 'E05 the gate judges exactly one partition, and it is the latest proposals partition',
         (SELECT ABS(1 - COUNT(DISTINCT snapshot_date)) FROM t)
       + (SELECT COUNTIF(t.snapshot_date != (SELECT MAX(snapshot_date)
                                             FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`))
          FROM t)
),
e06 AS (
  SELECT 'E06 one owner per (campaign, key, lever): every non-owner reads EXCLUDE',
         COUNTIF(n_instr > 1 AND own_rank > 1 AND verdict != 'EXCLUDE')
  FROM t
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM (SELECT * FROM e01 UNION ALL SELECT * FROM e02 UNION ALL SELECT * FROM e03
      UNION ALL SELECT * FROM e04 UNION ALL SELECT * FROM e04b
      UNION ALL SELECT * FROM e05 UNION ALL SELECT * FROM e06)
ORDER BY check_name;
```

- [ ] **Step 2: Run it**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/ENGINE_PREFLIGHT_acceptance.sql)"
```

Expected: seven rows, all `PASS`. If E01 reads `FAIL`, the ceiling arm from Task 1.2 was not deployed — re-run the deploy line for `SP_ENGINE_PREFLIGHT.sql` and `CALL` it.

- [ ] **Step 3: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/tests/ENGINE_PREFLIGHT_acceptance.sql
git commit -m "test(pacing): ENGINE_PREFLIGHT acceptance — the ceiling binds

Six checks: no GO bid above its ceiling, every ceiling names its layer, every
EXCLUDE explains itself, no GO raise beyond the move cap, one judged partition,
one owner per key."
```

---
## Phase 2 — Everything that spends is judged

**Closes:** the coverage half of violation 4 (spending rows outside the Catalog entirely).

**Why third.** The largest survivor by current spend: $132.71/day on 74 rows at 0.528 GP-ROAS against 0.906 inside the Catalog. No layer can see them, so nothing can price, repair or close them. The mechanism is that the universe is **configuration-derived, never spend-derived**: `V_KEYWORD_GUARD.sql:150-171` requires an ENABLED keyword inside an ENABLED campaign, so a row that spends but is not both cannot enter. Decomposed over the last complete week: the SB sentinel `keyword_id = '-1'` with no `DIM_KEYWORD` row is 9 keys and $70.55/day — the single biggest arm; PAUSED keyword in an ENABLED campaign 16 keys $10.46/day; ENABLED keyword in a PAUSED campaign 15 keys $5.76/day. It is money on the table today, and Phase 1 has now made it safe to admit them: they arrive into a system where Pacing no longer prices them alone.

**Honestly noted:** §8's violation 4 text describes the SQP gap; §10.3 assigns this money to violation 4 as well. This plan splits the two halves because they have opposite dependencies — the coverage half depends on nothing and ships now; the demand half depends on the response curve and ships in Phase 11. Treating them as one violation would have chained $132.71/day of live spend behind a modelling project.

**Unblocks:** any per-subject work whose population claim must be complete — Phase 5's seasonal answer, Phase 7's confidence census, Phase 10's curve fit. It also removes the 838-vs-502 trap that silently drops 40% of the table from any `GROUP BY` on `is_auto` / `is_pt`.

**Size:** M — 1–1.5 weeks. The sentinel subject key is a real design decision, not a filter change, and individuating the sentinel's RECORD means re-keying two joins inside `V_KEYWORD_GUARD` itself.

---

### Task 2.1: `CATALOG_COVERAGE_acceptance.sql` — the red test

**Files:**
- Create: `scripts/bigquery/tests/CATALOG_COVERAGE_acceptance.sql`

- [ ] **Step 1: Write the suite**

```sql
-- =============================================================================================
-- CATALOG COVERAGE acceptance — everything that spends is judged. EVERY ROW MUST READ PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Doctrine: architecture/THREE_LAYERS.md violation 4 / 10.1 "outside the Catalog entirely".
-- Objects: scripts/bigquery/views/V_KEYWORD_GUARD.sql,
--          scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql.
--
-- THE WINDOW IS COMPLETE DAYS ONLY, ending at the ads watermark minus one, per house convention —
-- the filling day never enters a window.
-- =============================================================================================
WITH wm AS (
  SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),
spend AS (
  SELECT CAST(a.campaign_id AS STRING) AS cid, CAST(a.keyword_id AS STRING) AS kid,
         SUM(a.Ads_cost) AS cost
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a, wm
  WHERE a.date BETWEEN DATE_SUB(wm.d, INTERVAL 7 DAY) AND DATE_SUB(wm.d, INTERVAL 1 DAY)
    AND a.Ads_cost > 0
  GROUP BY 1, 2
),
ks AS (
  SELECT CAST(campaign_id AS STRING) AS cid, CAST(keyword_id AS STRING) AS kid,
         universe_source, serving_blocked_reason
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
),
v01 AS (
  SELECT 'V01 every spending (campaign, keyword) in the last complete week has a Catalog row' AS check_name,
         (SELECT COUNT(*) FROM spend s
          LEFT JOIN ks ON ks.cid = s.cid AND ks.kid = s.kid
          WHERE ks.cid IS NULL) AS violations
),
v02 AS (
  SELECT 'V02 every Catalog row names how it entered the universe',
         (SELECT COUNTIF(universe_source NOT IN ('CONFIG','SPEND','BOTH')
                         OR universe_source IS NULL) FROM ks)
),
v03 AS (
  SELECT 'V03 a subject admitted on spend alone says why it cannot serve',
         (SELECT COUNTIF(universe_source = 'SPEND'
                         AND (serving_blocked_reason IS NULL OR serving_blocked_reason = ''))
          FROM ks)
),
v04 AS (
  SELECT 'V04 a newly admitted subject with no settled record never reads a terminal state',
         (SELECT COUNTIF(COALESCE(settled_clk90, 0) = 0
                         AND state IN ('DEAD','LOSER','FLOOR_PROBATION'))
          FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
          WHERE snapshot_date = (SELECT MAX(snapshot_date)
                                 FROM `onyga-482313.OI.FACT_KEYWORD_STATE`))
),
v05 AS (
  SELECT 'V05 a subject judged against a default bar of 1.0 says so on the row',
         (SELECT COUNTIF(family_bar IS NOT NULL AND ABS(family_bar - 1.0) < 0.00005
                         AND NOT COALESCE(bar_missing, FALSE)
                         AND family IS NULL)
          FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
          WHERE snapshot_date = (SELECT MAX(snapshot_date)
                                 FROM `onyga-482313.OI.FACT_KEYWORD_STATE`))
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM (SELECT * FROM v01 UNION ALL SELECT * FROM v02 UNION ALL SELECT * FROM v03
      UNION ALL SELECT * FROM v04 UNION ALL SELECT * FROM v05)
ORDER BY check_name;
```

- [ ] **Step 2: Measure the violation before the columns exist**

The suite as written references columns Tasks 2.2–2.4 add, so it cannot compile yet. Measure the headline violation directly, which is what V01 will assert:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH wm AS (SELECT LEAST(MAX(date), \`onyga-482313.OI.FN_ADS_ANCHOR_CAP\`()) d
            FROM \`onyga-482313.OI.FACT_AMAZON_ADS\`),
spend AS (
  SELECT CAST(a.campaign_id AS STRING) cid, CAST(a.keyword_id AS STRING) kid, SUM(a.Ads_cost) cost
  FROM \`onyga-482313.OI.FACT_AMAZON_ADS\` a, wm
  WHERE a.date BETWEEN DATE_SUB(wm.d, INTERVAL 7 DAY) AND DATE_SUB(wm.d, INTERVAL 1 DAY)
    AND a.Ads_cost > 0 GROUP BY 1,2),
ks AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid
       FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`
       WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`))
SELECT COUNTIF(ks.cid IS NULL) AS unseen_spending_keys,
       COUNT(*) AS all_spending_keys,
       ROUND(SUM(IF(ks.cid IS NULL, s.cost, 0)) / 7, 2) AS unseen_usd_per_day,
       ROUND(SUM(s.cost) / 7, 2) AS all_usd_per_day
FROM spend s LEFT JOIN ks ON ks.cid = s.cid AND ks.kid = s.kid"
```

Expected: a non-zero `unseen_spending_keys`. Measured 2026-08-24: 35 of 288 pairs, $85.63/day of $1,455.95/day; the doctrine's headline over its own 14-day window is 74 rows and $132.71/day. Record what you measure.

- [ ] **Step 3: Decompose it, so the fix is aimed at the real arms**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH wm AS (SELECT LEAST(MAX(date), \`onyga-482313.OI.FN_ADS_ANCHOR_CAP\`()) d
            FROM \`onyga-482313.OI.FACT_AMAZON_ADS\`),
spend AS (
  SELECT CAST(a.campaign_id AS STRING) cid, CAST(a.keyword_id AS STRING) kid, SUM(a.Ads_cost) cost
  FROM \`onyga-482313.OI.FACT_AMAZON_ADS\` a, wm
  WHERE a.date BETWEEN DATE_SUB(wm.d, INTERVAL 7 DAY) AND DATE_SUB(wm.d, INTERVAL 1 DAY)
    AND a.Ads_cost > 0 GROUP BY 1,2),
ks AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid
       FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`
       WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`)),
dk AS (SELECT CAST(keyword_id AS STRING) kid, CAST(campaign_id AS STRING) cid,
              ANY_VALUE(UPPER(state)) st FROM \`onyga-482313.OI.DIM_KEYWORD\`
       WHERE is_current GROUP BY 1,2),
dc AS (SELECT campaign_id cid, campaign_state FROM \`onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT\`)
SELECT CASE WHEN s.kid = '-1' THEN 'SB sentinel keyword_id = -1'
            WHEN dk.st IS NULL THEN 'no DIM_KEYWORD row'
            WHEN dk.st != 'ENABLED' THEN CONCAT('keyword ', dk.st)
            WHEN COALESCE(dc.campaign_state,'?') != 'ENABLED'
              THEN CONCAT('campaign ', COALESCE(dc.campaign_state,'NO ROW'))
            ELSE 'other' END AS why_excluded,
       COUNT(*) AS keys, ROUND(SUM(s.cost)/7, 2) AS usd_per_day
FROM spend s
LEFT JOIN ks ON ks.cid = s.cid AND ks.kid = s.kid
LEFT JOIN dk ON dk.cid = s.cid AND dk.kid = s.kid
LEFT JOIN dc ON dc.cid = s.cid
WHERE ks.cid IS NULL
GROUP BY 1 ORDER BY usd_per_day DESC"
```

Expected: the sentinel arm dominates. On 2026-08-24 it was 9 keys and $70.55/day of the total.

- [ ] **Step 4: Commit the suite (red)**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/tests/CATALOG_COVERAGE_acceptance.sql
git commit -m "test(catalog): coverage acceptance — every spending key must be judged

Red until V_KEYWORD_GUARD gains a spend-derived arm and the state machine
publishes universe_source, serving_blocked_reason and bar_missing."
```

---

### Task 2.2: A spend-derived arm in `V_KEYWORD_GUARD`

**Files:**
- Modify: `scripts/bigquery/views/V_KEYWORD_GUARD.sql:150-171` (the `kw` CTE)

- [ ] **Step 1: Back up**

```bash
cd /Users/ori/Develop/OI
NEXT=$(ls scripts/bigquery/**/*.bak.v27.*.* 2>/dev/null | sed -E 's/.*\.bak\.v27\.([0-9]+)\..*/\1/' | sort -n | tail -1)
NEXT=$((NEXT + 1))
cp scripts/bigquery/views/V_KEYWORD_GUARD.sql \
   scripts/bigquery/views/V_KEYWORD_GUARD.sql.bak.v27.$NEXT.$(date +%H%M)
```

- [ ] **Step 2: Replace the `kw` CTE**

The `kw` CTE today reads exactly as shown in the file at lines 150–171 (a single config-derived population). Replace the whole CTE with:

```sql
-- population, TWO ARMS (2026-08-25, violation 4 / 10.1 "outside the Catalog entirely").
--
-- ARM 1, CONFIG — unchanged: every current ENABLED target (keywords, auto clauses, product targets
-- — SP and SB config both live in DIM_KEYWORD) inside an ENABLED campaign, one row per
-- (campaign, keyword).
--
-- ARM 2, SPEND — new. A row that took settled spend in the judging window enters WHATEVER its
-- DIM_KEYWORD state or its campaign state, because doctrine 7 forbids money spending with no layer
-- able to see it. Measured before this arm existed: spending (campaign, keyword) pairs with no
-- Catalog row at all, the largest single survivor in 10.1 by current spend — chiefly SB product
-- targets arriving under the sentinel keyword_id '-1' with no DIM_KEYWORD row.
--
-- THE POPULATION IS NOW AUDITABLE RATHER THAN IMPLIED: universe_source says which arm admitted the
-- row, and serving_blocked_reason says, for a row that cannot currently serve, exactly why. A
-- consumer that wants the old behaviour filters universe_source IN ('CONFIG','BOTH').
kw AS (
  SELECT
    COALESCE(c.campaign_id, sp.campaign_id)            AS campaign_id,
    COALESCE(c.keyword_id,  sp.keyword_id)             AS keyword_id,
    COALESCE(c.keyword_text, sp.keyword_text)          AS keyword_text,
    COALESCE(c.match_type,   sp.match_type)            AS match_type,
    COALESCE(c.channel,      sp.channel)               AS channel,
    COALESCE(c.current_bid,  sp.current_bid)           AS current_bid,
    LOWER(COALESCE(c.keyword_text, sp.keyword_text))
      IN ('close-match','loose-match','substitutes','complements')          AS is_auto,
    LOWER(COALESCE(c.keyword_text, sp.keyword_text)) LIKE 'asin%'
      OR LOWER(COALESCE(c.keyword_text, sp.keyword_text)) LIKE 'category%'  AS is_pt,
    CASE WHEN c.campaign_id IS NOT NULL AND sp.campaign_id IS NOT NULL THEN 'BOTH'
         WHEN c.campaign_id IS NOT NULL                                THEN 'CONFIG'
         ELSE                                                               'SPEND' END
                                                                            AS universe_source,
    -- why a row cannot serve today. NULL means it can.
    CASE WHEN c.campaign_id IS NOT NULL                     THEN NULL
         WHEN sp.keyword_id = '-1'                          THEN 'SB sentinel target: no DIM_KEYWORD row exists for keyword_id -1'
         WHEN sp.dim_state IS NULL                          THEN 'no current DIM_KEYWORD row'
         WHEN sp.dim_state != 'ENABLED'                     THEN CONCAT('keyword is ', sp.dim_state)
         WHEN COALESCE(sp.campaign_state, '?') != 'ENABLED' THEN CONCAT('campaign is ', COALESCE(sp.campaign_state, 'absent'))
         ELSE 'admitted on spend; serving status unresolved' END            AS serving_blocked_reason
  FROM (
    -- ARM 1: config
    SELECT campaign_id, keyword_id, keyword_text, match_type, channel, current_bid
    FROM (
      SELECT CAST(k.campaign_id AS STRING) AS campaign_id, CAST(k.keyword_id AS STRING) AS keyword_id,
             k.keyword_text, k.match_type,
             IF(UPPER(COALESCE(c.campaign_type, 'SP')) = 'SB', 'SB', 'SP') AS channel,
             COALESCE(k.bid, ag.default_bid) AS current_bid,
             ROW_NUMBER() OVER (PARTITION BY CAST(k.campaign_id AS STRING), CAST(k.keyword_id AS STRING)
                                ORDER BY k.effective_from DESC, k.bid DESC NULLS LAST) AS rn
      FROM `onyga-482313.OI.DIM_KEYWORD` k
      JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` c
        ON c.campaign_id = CAST(k.campaign_id AS STRING) AND c.campaign_state = 'ENABLED'
      LEFT JOIN (SELECT ad_group_id, ANY_VALUE(default_bid) AS default_bid
                 FROM `onyga-482313.OI.DIM_AD_GROUP` WHERE is_current GROUP BY 1) ag
        ON ag.ad_group_id = CAST(k.ad_group_id AS STRING)
      WHERE k.is_current AND UPPER(k.state) = 'ENABLED'
    ) WHERE rn = 1
  ) c
  FULL OUTER JOIN (
    -- ARM 2a: spend, NON-SENTINEL. The judging frame is the guard's own 104-day bound, so a subject
    -- that spent at any point the guard can still see is admitted; the settled windows downstream
    -- decide whether there is a record worth judging.
    -- ANY_VALUE IS SAFE HERE AND ONLY HERE, and the reason is measured rather than assumed: over the
    -- same 104-day window on 2026-08-24, spending (campaign_id, keyword_id, LOWER(TRIM(targeting)))
    -- triples where keyword_id != '-1' numbered 631 over 631 distinct (campaign_id, keyword_id)
    -- pairs — exactly 1:1, so there is only ever one text to choose from. Re-run that count before
    -- trusting this comment; if it is ever not 1:1, this arm must be grained like 2b below.
    SELECT sp.campaign_id, sp.keyword_id, sp.keyword_text, sp.match_type, sp.channel,
           sp.current_bid, sp.dim_state, sp.campaign_state
    FROM (
      SELECT CAST(a.campaign_id AS STRING) AS campaign_id,
             CAST(a.keyword_id AS STRING)  AS keyword_id,
             ANY_VALUE(a.targeting)        AS keyword_text,
             ANY_VALUE(a.targeting_type)   AS match_type,
             IF(UPPER(ANY_VALUE(COALESCE(a.campaign_type, 'SP'))) LIKE 'SB%', 'SB', 'SP') AS channel,
             CAST(NULL AS FLOAT64)         AS current_bid,
             ANY_VALUE(dk.st)              AS dim_state,
             ANY_VALUE(dc.campaign_state)  AS campaign_state
      FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
      LEFT JOIN (SELECT CAST(keyword_id AS STRING) kid, CAST(campaign_id AS STRING) cid,
                        ANY_VALUE(UPPER(state)) st
                 FROM `onyga-482313.OI.DIM_KEYWORD` WHERE is_current GROUP BY 1, 2) dk
        ON dk.kid = CAST(a.keyword_id AS STRING) AND dk.cid = CAST(a.campaign_id AS STRING)
      LEFT JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` dc
        ON dc.campaign_id = CAST(a.campaign_id AS STRING)
      WHERE a.date > DATE_SUB((SELECT d FROM wm), INTERVAL 104 DAY)
        AND a.date <= DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY)
        AND a.Ads_cost > 0
        AND a.keyword_id IS NOT NULL
        AND CAST(a.keyword_id AS STRING) != '-1'
      GROUP BY 1, 2
    ) sp
  ) sp
    ON  sp.campaign_id = c.campaign_id
   AND  sp.keyword_id  = c.keyword_id
),
-- ── ARM 2b: THE SB SENTINEL TARGETS, GRAINED ON THE TEXT (2026-08-25) ────────────────────────
-- Amazon reports an SB product target with no keyword identity under keyword_id '-1', and MANY
-- DISTINCT TARGETS IN ONE CAMPAIGN SHARE IT. Measured 2026-08-24 over the same window: 50 distinct
-- (campaign_id, '-1', targeting) triples over just 11 (campaign_id, keyword_id) pairs. Grouping them
-- by (campaign_id, keyword_id) like arm 2a would pool up to a dozen unrelated product targets into
-- one row, label it with an arbitrarily chosen sibling's text, and judge them all on the pooled
-- record — which is exactly the cross-subject blending doctrine 2.2 forbids, and it would also make
-- Task 2.3's subject_key nondeterministic between nightly runs because the label came from
-- ANY_VALUE. So the text is a GROUPING COLUMN here, not an aggregate.
--
-- THEY ARE UNIONED, NOT JOINED. keyword_id '-1' has no DIM_KEYWORD row by construction, so an arm-2b
-- row can never have an arm-1 counterpart and the FULL OUTER JOIN above has nothing to match it to.
-- Unioning after the join keeps that join strictly 1:1 on (campaign_id, keyword_id).
sentinel AS (
  SELECT CAST(a.campaign_id AS STRING)      AS campaign_id,
         CAST(a.keyword_id AS STRING)       AS keyword_id,
         LOWER(TRIM(a.targeting))           AS keyword_text,
         ANY_VALUE(a.targeting_type)        AS match_type,
         IF(UPPER(ANY_VALUE(COALESCE(a.campaign_type, 'SP'))) LIKE 'SB%', 'SB', 'SP') AS channel,
         CAST(NULL AS FLOAT64)              AS current_bid,
         ANY_VALUE(dc.campaign_state)       AS campaign_state
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  LEFT JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` dc
    ON dc.campaign_id = CAST(a.campaign_id AS STRING)
  WHERE a.date > DATE_SUB((SELECT d FROM wm), INTERVAL 104 DAY)
    AND a.date <= DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY)
    AND a.Ads_cost > 0
    AND CAST(a.keyword_id AS STRING) = '-1'
    AND a.targeting IS NOT NULL AND TRIM(a.targeting) != ''
  GROUP BY 1, 2, 3
),
kw_all AS (
  SELECT * FROM kw
  UNION ALL
  SELECT campaign_id, keyword_id, keyword_text, match_type, channel, current_bid,
         FALSE                                                                  AS is_auto,
         TRUE                                                                   AS is_pt,
         'SPEND'                                                                AS universe_source,
         'SB sentinel target: no DIM_KEYWORD row exists for keyword_id -1'       AS serving_blocked_reason
  FROM sentinel
),
```

**`kw_all` replaces `kw` in every downstream reference inside this view.** Find them and repoint them
in the same edit — do not leave `kw` readable, or half the view will see the sentinels and half will
not:

```bash
cd /Users/ori/Develop/OI
grep -n "FROM kw$\|FROM kw \|JOIN kw \|JOIN kw$" scripts/bigquery/views/V_KEYWORD_GUARD.sql
```

On 2026-08-24 that returns exactly one hit: `FROM kw` at `:189`, inside the `kws` CTE. **Repoint it
with the alias preserved** — `kws` refers to its source as `kw.*`, `kw.is_auto`, `kw.match_type`,
`kw.campaign_id` and `kw.keyword_text`, and a bare `FROM kw_all` would break every one of them:

```sql
  FROM kw_all kw
```

The `kw` CTE itself keeps its name so the diff stays readable, and `wm` is declared at `:133`, above
both new CTEs, so `(SELECT d FROM wm)` resolves inside `sentinel`.

- [ ] **Step 2b: RE-KEY THE RECORD ONTO THE SUBJECT — individuating the label is not enough**

**Step 2 individuates the sentinel's LABEL. On its own it does not individuate its RECORD, and
without this step it does the exact thing the comment above says it prevents.** The guard attaches
the settled record at `V_KEYWORD_GUARD.sql:414`:

```sql
  LEFT JOIN inst i ON i.cid = kws.campaign_id AND i.kwid = kws.keyword_id
```

and `inst` is `FROM f, wm ... GROUP BY 1, 2` (`:226-235`) — campaign and `keyword_id` only. So every
one of the ~50 sentinel rows in a campaign would receive the **same pooled `-1` record**: identical
`settled_clk90`, `settled_ord90`, `settled_roas90`, `settled_sp90` and `settled_gp90`, each subject
judged on all its siblings' spend. Measured 2026-08-24 over the guard's own 104-day window: **50
distinct `(campaign_id, '-1', targeting)` triples over 11 `(campaign_id, keyword_id)` pairs across 11
campaigns, carrying $2,479.52** — so the guard's settled spend would read roughly 4.5x too high on
those rows for any aggregate, and `subject_key` (Task 2.3) would be a distinct key over identical
economics, which is worse than pooling because it looks individuated.

Three edits, and they must land in the same deploy as Step 2.

**(a)** `f` (`:193-200`) carries `scope` but no bare target text. Add one column to its select list:

```sql
         LOWER(TRIM(a.targeting))                                   AS tgt,
```

**(b)** `inst` (`:226`) gains a third grouping column — **empty for every non-sentinel subject**, so
nothing about the existing 631 rows changes, and the target text for a `-1` row:

```sql
inst AS (
  SELECT cid, kwid,
    -- 2026-08-25: the SUBJECT AXIS. '' everywhere except keyword_id '-1', where Amazon gives many
    -- distinct SB product targets one shared id and the record must not be pooled across them
    -- (doctrine 2.2). Non-sentinel rows keep a constant here, so their grain is untouched.
    IF(kwid = '-1', tgt, '') AS subj_txt,
```

with `GROUP BY 1, 2, 3` in place of `GROUP BY 1, 2` at `:234`. Apply the identical two edits to
`wkev` (`:344-351`) — it is empty for sentinels today because `wk` holds no `-1` row, but leaving it
keyed differently from `inst` is exactly how a later change re-introduces the pooling silently.

**(c)** `kws` (`:172-191`) gains the matching column, and the two joins gain the matching predicate:

```sql
         IF(kw.keyword_id = '-1', LOWER(TRIM(kw.keyword_text)), '') AS subj_txt,
```

```sql
  LEFT JOIN inst i ON i.cid = kws.campaign_id AND i.kwid = kws.keyword_id
                  AND i.subj_txt = kws.subj_txt
  LEFT JOIN wkev we ON we.cid = kws.campaign_id AND we.kwid = kws.keyword_id
                   AND we.subj_txt = kws.subj_txt
```

**The other five record joins need no change, and here is why each is already safe.** `life` and
`lys` join on `scope`, which already embeds `LOWER(a.targeting)` by construction (`:194-196`), so
they are individuated per target already. `seas` joins on `LOWER(TRIM(kws.keyword_text))`, which
Step 2 has just made the target's own text. `chg`, `bchg` and `wk` join on `keyword_id` or
`campaign_id` alone, but each holds at most one row per key, so they cannot fan out — they share a
value across siblings, and for `-1` that value is empty because no upload ever addressed keyword id
`-1`. Say so in a comment beside the joins rather than leaving a reader to re-derive it.

Prove the record is individuated, not merely the label:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_KEYWORD_GUARD.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT campaign_id,
       COUNT(*)                                    AS sentinel_rows,
       COUNT(DISTINCT ROUND(settled_sp90, 2))      AS distinct_settled_spends,
       ROUND(SUM(settled_sp90), 2)                 AS summed_settled_spend
FROM \`onyga-482313.OI.V_KEYWORD_GUARD\`
WHERE keyword_id = '-1'
GROUP BY 1 ORDER BY sentinel_rows DESC LIMIT 5"
```

Expected: on any campaign with more than one sentinel, `distinct_settled_spends > 1`. **If it reads
`1` on every campaign the record is still pooled** — the join predicate did not land — and the whole
of Phase 2's sentinel work is decorative. Stop and fix it before Task 2.3.

- [ ] **Step 3: Carry the two new columns through to the published SELECT**

`V_KEYWORD_GUARD`'s final `SELECT` already carries the `kw` columns through the `kws` CTE. Add `kws.universe_source` and `kws.serving_blocked_reason` to the published column list, immediately after `is_pt`.

- [ ] **Step 4: Deploy and check the population grew, and by what**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_KEYWORD_GUARD.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT universe_source, COALESCE(serving_blocked_reason,'(can serve)') AS blocked,
          COUNT(*) n, COUNTIF(settled_clk90 > 0) with_record
   FROM \`onyga-482313.OI.V_KEYWORD_GUARD\` GROUP BY 1,2 ORDER BY n DESC"
```

Expected: three `universe_source` values, and every `SPEND` row carrying a non-null
`serving_blocked_reason`. Then prove the sentinels arrived individuated rather than pooled:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT COUNT(*) sentinel_rows,
       COUNT(DISTINCT CONCAT(campaign_id, '|', keyword_text)) distinct_targets,
       COUNT(DISTINCT campaign_id) campaigns
FROM \`onyga-482313.OI.V_KEYWORD_GUARD\` WHERE keyword_id = '-1'"
```

Expected: `sentinel_rows = distinct_targets`, and both materially larger than `campaigns`. Measured
2026-08-24 the population was 50 distinct targets over 11 (campaign, keyword) pairs, so a result
where `sentinel_rows` is close to `campaigns` means the text grouping was dropped and the pooling is
back.

**One grain consequence, stated here because Task 2.3 depends on it.** After this change
`V_KEYWORD_GUARD` — and therefore `FACT_KEYWORD_GUARD` and `FACT_KEYWORD_STATE` — is one row per
**subject**, which is `(campaign_id, keyword_id)` everywhere except the sentinels, where it is
`(campaign_id, keyword_id, keyword_text)`. Anything joining those tables on `(campaign_id,
keyword_id)` alone can now fan out on eleven campaigns' worth of SB targets. Task 2.3 Step 3 audits
every such join and repoints the one on the money path.

- [ ] **Step 5: Refresh the guard snapshot the ladder reads**

`FACT_KEYWORD_GUARD` is a snapshot of this view, rebuilt by `SP_SNAPSHOT_KEYWORD_GUARD` (orchestrator task 20.5f). It must be refreshed **before** anything compiles against the new columns:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_GUARD\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT universe_source, COUNT(*) n FROM \`onyga-482313.OI.FACT_KEYWORD_GUARD\` GROUP BY 1 ORDER BY n DESC"
```

Expected: the same three values, same counts.

- [ ] **Step 6: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_KEYWORD_GUARD.sql
git commit -m "feat(catalog): V_KEYWORD_GUARD admits every subject that spends

The universe was configuration-derived, so a row that spent but was not both an
ENABLED keyword and an ENABLED campaign could not enter — the largest single
survivor in THREE_LAYERS 10.1 by current spend. universe_source and
serving_blocked_reason make the population auditable rather than implied."
```

---

### Task 2.3: The SB sentinel gets a subject key

**Files:**
- Modify: `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql` (final `SELECT`)
- Modify: `scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql` (re-key the `cat` join onto `subject_key`)
- Modify: `scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql`, `scripts/bigquery/views/V_KEYWORD_STATE.sql`
- Modify: `tools/build_reprice_bulksheet.py` (a sentinel is judged but never uploaded)
- Modify: `scripts/bigquery/views/V_OOB_KEYWORD.sql:1731`, `scripts/bigquery/views/V_KEYWORD_LIFT.sql:714`, `:1054`, `:3493` (the four guard joins, so a sentinel cannot fan a ceiling view out)

**The design decision, written down.** A sentinel is not a keyword. `keyword_id = '-1'` is what Amazon reports for an SB product target that has no keyword identity, and 31 distinct (campaign, targeting) pairs share it, spending $70.61/day across 10 SB campaigns — 17 targets worth $69.66/day priced by Pacing only, 14 worth $0.95/day with no layer at all. Minting a synthetic `keyword_id` would be shorter but dangerous: a synthetic id must never reach a bulksheet that addresses Amazon by id. So the Catalog carries a **separate `subject_key` column**, and `keyword_id` keeps meaning exactly what Amazon means by it.

- [ ] **Step 1: Back up**

```bash
cd /Users/ori/Develop/OI
NEXT=$(ls scripts/bigquery/**/*.bak.v27.*.* 2>/dev/null | sed -E 's/.*\.bak\.v27\.([0-9]+)\..*/\1/' | sort -n | tail -1)
NEXT=$((NEXT + 1))
cp scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql \
   scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql.bak.v27.$NEXT.$(date +%H%M)
```

- [ ] **Step 2: Publish `subject_key` in the final SELECT**

In the final `SELECT` of `SP_SNAPSHOT_KEYWORD_STATE`, immediately after the line that publishes `s.keyword_id` (or its equivalent alias), add:

```sql
    -- ── THE SUBJECT KEY (2026-08-25, violation 4) ────────────────────────────────────────────
    -- Amazon reports an SB product target with no keyword identity under the sentinel
    -- keyword_id '-1', and many distinct targets in many campaigns share it. A sentinel is not a
    -- keyword, so the Catalog carries its own key and leaves keyword_id meaning exactly what
    -- Amazon means by it. A SYNTHETIC ID IS DELIBERATELY NOT MINTED: SP_SYNC_NEGATIVES's MD5
    -- precedent shows how, and DE_NEGATIVE_KEYWORDS shows the cost — 119 rows carry an id Amazon
    -- cannot accept. A key that can never address Amazon must never look like one that can.
    -- IT IS DETERMINISTIC BECAUSE ITS INPUT IS. Task 2.2's arm 2b makes LOWER(TRIM(targeting)) a
    -- GROUPING column on the sentinel rows rather than an ANY_VALUE, so the text on the row is the
    -- row's own identity and cannot change between two runs of the same night. Built on an
    -- ANY_VALUE it would have been a key that silently re-pointed itself, which would break
    -- FACT_KEYWORD_STATE_HISTORY's identity and V_CATALOG_DWELL's whole premise.
    IF(s.keyword_id = '-1',
       CONCAT('sbtarget|', s.campaign_id, '|', LOWER(TRIM(COALESCE(s.target_text, '')))),
       CONCAT('kw|', s.campaign_id, '|', s.keyword_id))                 AS subject_key,
    (s.keyword_id = '-1')                                               AS is_sentinel_target,
```

- [ ] **Step 3: Audit every join that assumes one row per (campaign_id, keyword_id) — BEFORE deploying**

Task 2.2 made the Catalog's grain `(campaign_id, keyword_id)` **except on the sentinels**, where it
is `(campaign_id, keyword_id, target_text)`. Any consumer joining `FACT_KEYWORD_STATE`,
`V_KEYWORD_STATE` or `FACT_KEYWORD_GUARD` on the pair alone can now multiply rows. Find them all:

```bash
cd /Users/ori/Develop/OI
grep -rln "FACT_KEYWORD_STATE\b\|V_KEYWORD_STATE\b\|FACT_KEYWORD_GUARD\b" \
  scripts/bigquery/views scripts/bigquery/procedures scripts/bigquery/tests tools cube \
  | grep -v "\.bak"
```

Measured 2026-08-24 that returns 23 files. **Only two of them are on the money path and only one of
them needs a code change now:**

1. **`SP_ENGINE_PREFLIGHT.sql` — the `cat` join added in Task 1.2.** It joins on `(cid, kid)` and
   would give every sentinel proposal as many ceiling rows as its campaign has SB targets, fanning
   the whole proposal set out. Re-key it onto the subject, which the proposal side can compute
   identically because `FACT_ENGINE_PROPOSALS` carries `target_text`. Replace the `cat` CTE and its
   join with:

```sql
  cat AS (
    SELECT subject_key, affordable_bid, family_bar, bid_floor, state, next_check_date
    FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
    WHERE snapshot_date = (SELECT MAX(snapshot_date)
                           FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
  ),
```

```sql
    -- 2026-08-25: keyed on SUBJECT, not on (campaign, keyword). An SB product target with no keyword
    -- identity arrives under the sentinel keyword_id '-1' and many targets in one campaign share it,
    -- so a pair-keyed join fans this proposal set out. The expression below is the same one
    -- SP_SNAPSHOT_KEYWORD_STATE publishes as subject_key, and it must stay that way.
    LEFT JOIN cat ct
      ON ct.subject_key = IF(CAST(p.keyword_id AS STRING) = '-1',
           CONCAT('sbtarget|', CAST(p.campaign_id AS STRING), '|',
                  LOWER(TRIM(COALESCE(p.target_text, '')))),
           CONCAT('kw|', CAST(p.campaign_id AS STRING), '|', CAST(p.keyword_id AS STRING)))
```

   The `brain` join is left on `(cid, kid)`: `FACT_PLAN_NEXT_WEEK` is built from
   `V_PLAN_WINDOW_JUDGMENT`, which is HARVEST-family keyword grain and carries no sentinel row, so it
   is still 1:1. Prove it in the same step rather than asserting it.

2. **`tools/build_reprice_bulksheet.py`** reads `V_KEYWORD_STATE` row by row and never joins it, so
   it needs no key change — but a sentinel row has `keyword_id = '-1'`, which Amazon cannot accept on
   a bulksheet. Add one exclusion beside the book's other exclusions so a sentinel can never become
   an upload row, and say why:

```python
    # A sentinel SB target has no keyword id Amazon will accept ('-1' is a report artefact, not an
    # identity). The Catalog judges it — that is violation 4's whole point — but no book may address
    # it, and a synthetic id must never be minted to make one look addressable.
    if str(r.get('keyword_id')) == '-1':
        return 'SKIPPED_SENTINEL_TARGET', None, None, [], bits
```

3. **The two ceiling views join the guard on the pair, in four places, and would fan out.**
   `V_OOB_KEYWORD.sql:1731` and `V_KEYWORD_LIFT.sql:714`, `:1054`, `:3493` each carry
   `LEFT JOIN FACT_KEYWORD_GUARD ... ON g.campaign_id = ... AND g.keyword_id = ...`. After Task 2.2
   that table holds 50 rows on 11 `(campaign, keyword)` pairs, so **any** engine row for one of those
   eleven campaign/`-1` pairs would multiply into a dozen proposals.

   **Measured on 2026-08-24 the exposure is zero today, and that is exactly why this is a guard
   rather than a repair.** `FACT_ENGINE_PROPOSALS`' latest partition holds 227 rows across six
   engines and **not one** carries `keyword_id = '-1'` — both ceiling views build their populations
   from `DIM_KEYWORD`, which has no sentinel row, and read the guard only as a small-table LEFT JOIN
   on the final rowset. Re-run the count before and after Task 2.2 rather than trusting this
   sentence. What the predicate below buys is that the day an engine *does* reach a sentinel — Phase
   12's `rank()` proposes candidates, and Phase 13 reasons about SB vehicles — it fans nothing out
   and nobody has to remember why. Add to **all four** joins:

```sql
  -- 2026-08-25: the guard is (campaign, keyword) grain for every subject EXCEPT the SB sentinel,
  -- where many targets share keyword_id '-1' (Task 2.2). A pair-keyed join to a sentinel row would
  -- multiply this rowset by the campaign's target count. Missing guard rows already fail OPEN here
  -- by design, so excluding the sentinel changes no existing row's behaviour — it only refuses the
  -- fan-out. Re-keying these onto subject_key is a separate, measured change.
  AND g.keyword_id != '-1'
```

   (the alias is `g` in `V_OOB_KEYWORD` and at `V_KEYWORD_LIFT:3493`, and `gd` at `:714` and
   `:1054` — use each site's own alias).

Then verify no fan-out, before and after:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT COUNT(*) proposals,
       (SELECT COUNT(*) FROM \`onyga-482313.OI.T_ENGINE_PREFLIGHT\`) AS preflight_rows
FROM \`onyga-482313.OI.FACT_ENGINE_PROPOSALS\`
WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_ENGINE_PROPOSALS\`)
  AND hold_source IS NULL"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT COUNT(*) plan_rows,
       COUNT(DISTINCT CONCAT(campaign_id,'|',keyword_id)) pairs
FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
WHERE as_of = (SELECT MAX(as_of) FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`) AND is_live_plan"
```

Expected: `preflight_rows = proposals` (the gate neither drops nor multiplies a row), and
`plan_rows = pairs` (the Brain's side is still pair-unique, so the `brain` join is safe as written).

- [ ] **Step 4: Add `subject_key` to the history table and re-deploy `V_KEYWORD_STATE`**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
ALTER TABLE \`onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY\`
  ADD COLUMN IF NOT EXISTS subject_key        STRING,
  ADD COLUMN IF NOT EXISTS is_sentinel_target BOOL"
```

Append the same two lines to `scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql` under a comment naming the phase, then re-deploy the `SELECT *` view **in the same step** — it freezes its schema at CREATE time and `tools/build_reprice_bulksheet.py` reads the view, so a missing column fails as a Python `KeyError`, not a SQL error:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT COUNT(*) rows, COUNT(DISTINCT subject_key) subjects, COUNTIF(is_sentinel_target) sentinels
   FROM \`onyga-482313.OI.V_KEYWORD_STATE\`"
```

Expected: `rows = subjects` (the key is unique) and a non-zero `sentinels` count. **Also check the
weaker claim that `rows = subjects` cannot see**, because it passes trivially on a pooled population:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT COUNTIF(is_sentinel_target) sentinel_subjects,
       COUNT(DISTINCT IF(is_sentinel_target, campaign_id, NULL)) sentinel_campaigns,
       COUNTIF(is_sentinel_target
               AND (target_text IS NULL OR TRIM(target_text) = '')) unlabelled_sentinels
FROM \`onyga-482313.OI.V_KEYWORD_STATE\`"
```

Expected: `sentinel_subjects` materially larger than `sentinel_campaigns` (measured 2026-08-24: 31
distinct (campaign, target) pairs across 10 SB campaigns in the ENABLED set, 50 across 11 over the
guard's full 104-day window), and `unlabelled_sentinels = 0` — an unlabelled sentinel would collapse
into a shared key `sbtarget|<campaign>|` and re-pool exactly what this task exists to separate.

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql \
        scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql \
        scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql \
        scripts/bigquery/views/V_KEYWORD_STATE.sql \
        scripts/bigquery/views/V_OOB_KEYWORD.sql \
        scripts/bigquery/views/V_KEYWORD_LIFT.sql \
        tools/build_reprice_bulksheet.py
git commit -m "feat(catalog): subject_key — a sentinel SB target is not a keyword

31 distinct (campaign, targeting) pairs share keyword_id '-1'. The Catalog gets
its own key; keyword_id keeps meaning what Amazon means by it, so no synthetic id
can ever reach a bulksheet that addresses Amazon by id."
```

---

### Task 2.4: Admit them safely — `NO_RECORD`, `bar_missing`, and the ad-group fix

**Files:**
- Modify: `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql:144-146` (the `kag` CTE), `:306-310` (the bar COALESCE), `:389-435` (the `st` CTE)
- Re-deploy: `scripts/bigquery/views/V_KEYWORD_STATE.sql`

- [ ] **Step 1: Fix the ad-group resolution**

`kag` today partitions by `keyword_id` alone while every other join in the procedure is on `(campaign_id, keyword_id)`. If a `keyword_id` appears under two campaigns, one takes the other's ad group, hence `creative_type`, hence `bid_floor`. Today it reads:

```sql
  kag AS (SELECT CAST(keyword_id AS STRING) kid, CAST(ad_group_id AS STRING) ad_group_id
          FROM `onyga-482313.OI.DIM_KEYWORD`
          QUALIFY ROW_NUMBER() OVER (PARTITION BY keyword_id ORDER BY is_current DESC, effective_from DESC) = 1),
```

Replace with:

```sql
  -- 2026-08-25: PARTITION BY (campaign_id, keyword_id), not keyword_id alone. Every other join in
  -- this procedure is on the pair, so a keyword_id appearing under two campaigns used to take one
  -- campaign's ad group for both — and with it the creative type, and with that the bid floor.
  -- Acceptance K06 asserts the uniqueness this restores.
  kag AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
                 CAST(ad_group_id AS STRING) ad_group_id
          FROM `onyga-482313.OI.DIM_KEYWORD`
          QUALIFY ROW_NUMBER() OVER (PARTITION BY CAST(campaign_id AS STRING),
                                                  CAST(keyword_id AS STRING)
                                     ORDER BY is_current DESC, effective_from DESC) = 1),
```

Every join onto `kag` in the procedure must gain the campaign predicate. Find them:

```bash
cd /Users/ori/Develop/OI
grep -n "kag" scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql
```

For each `JOIN kag ON kag.kid = X.kid` (or `LEFT JOIN`), add ` AND kag.cid = X.cid`, where `X` is the alias already carrying the campaign.

- [ ] **Step 2: Publish `bar_missing`**

The `calc` CTE today reads, exactly:

```sql
      COALESCE(fb.keyword_bar, 1.0) AS family_bar,
      COALESCE(fb.bar_exempt, FALSE) AS bar_exempt,
```

Add one line directly beneath those two, inside the same `calc` CTE:

```sql
      -- 2026-08-25: a campaign with no row in T_FAMILY_BAR is judged against a bar of 1.0 with no
      -- halo credit, and nothing on the row said so. It is SAFE IN DIRECTION — 1.0 is stricter than
      -- any real family's bar, which runs 0.60 to 1.00 — but it is invisible, and most rows newly
      -- admitted on spend will have no bar until Phase 4 widens V_CAMPAIGN_FAMILY_MAP. Say it.
      (fb.keyword_bar IS NULL) AS bar_missing,
```

then carry `bar_missing` through the CTE chain (`calc` -> `st` -> `fin` -> `fin3`, each of which
selects `s.*` or `b.*` from its predecessor, so no per-CTE edit is needed) and add
`s.bar_missing,` to the procedure's final `SELECT`.

- [ ] **Step 3: Add the `NO_RECORD` arm ahead of the ladder**

In the `st` CTE, the `raw_state` `CASE` is a first-match ladder. Insert a new **first** arm, above every existing arm:

```sql
      -- ── NO_RECORD (2026-08-25, violation 4) ────────────────────────────────────────────────
      -- FIRST ARM, DELIBERATELY. Phase 2 admits subjects on spend alone, and many of them arrive
      -- with no settled record at all. Doctrine 5: a silent window is never evidence of
      -- worthlessness, and a one-way action needs HIGH confidence, which does not exist yet
      -- (violation 20, Phase 7). Admitting thin rows into a ladder that emits DEAD and LOSER would
      -- be a fix that makes a wrong action happen faster.
      -- This is the precursor of 2.7's NO_EVIDENCE, which Phase 7 completes; the two are folded
      -- together there. Until then NO_RECORD is a state, and the acceptance suite asserts that a
      -- subject with no settled clicks can never read DEAD, LOSER or FLOOR_PROBATION.
      -- THE ALIAS IS `v`, NOT `g`. The `st` CTE reads `FROM verd v` and every existing arm beside
      -- this one says `v.settled_clk90`; `g` is a different CTE eleven levels upstream and is not
      -- in scope here.
      WHEN COALESCE(v.settled_clk90, 0) = 0 THEN 'NO_RECORD'
```

**And gate the two TERMINAL arms on the same admission.** The arm above shields only subjects with
*zero* settled clicks, which is not the population Phase 2 admits. Measured 2026-08-24: 321
(campaign, keyword) pairs enter on the guard's spend arm and **75 of them carry ≥ 15 settled clicks
with 0 settled orders**, which is A7's `DEAD` condition exactly. `DEAD` is a one-way action —
`SP_BUILD_NEXT_WEEK_PLAN.sql:357` turns it straight into `'PAUSE'` — and doctrine 5 forbids a one-way
action below HIGH confidence, which does not exist until Phase 7. Without this, Phase 2 makes a
wrong action happen faster, which is the exact failure the phase order exists to prevent.

In the same `raw_state` `CASE`, add one predicate to the `DEAD` arm and one to the `LOSER` arm:

```sql
        WHEN COALESCE(v.settled_clk90, 0) >= 15 AND COALESCE(v.settled_ord90, 0) = 0
         AND COALESCE(v.reverdict, '') NOT IN ('SIBLING_REVIVE', 'REDUNDANT')
         -- 2026-08-25: a subject admitted on SPEND ALONE has no configuration row, so nothing about
         -- it has ever been judged and nothing about it can be uploaded by id. It falls through to
         -- the evidential ladder below (TRIAL / WINNER / AT_BAR / REPRICE / FLOOR_PROBATION), all of
         -- which are reversible — judgement without a kill. Task 7.5 Step 1 deletes this predicate
         -- and replaces it with the confidence band, which is the real gate doctrine 5 asks for.
         AND COALESCE(v.universe_source, 'CONFIG') != 'SPEND' THEN 'DEAD'
```

```sql
        WHEN v.probation_elapsed AND v.at_floor
         AND COALESCE(v.universe_source, 'CONFIG') != 'SPEND' THEN 'LOSER'
```

Add `'NO_RECORD'` to the enumerated ladder set in `scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql` check K03, and give it an appointment so K04 stays green.

**The three appointment expressions are VALUE-form `CASE`s, not searched ones.** All three open
`CASE s.state_c` and every existing arm is a bare literal (`WHEN 'DEAD' THEN …`), so an arm written
`WHEN s.state_c = 'NO_RECORD'` compares a `STRING` operand against a `BOOL` `WHEN`-expression and the
deploy fails. Write the bare literal. In the `next_check_date` expression add as its first arm —
note `s.today_d`, which is the alias `fin2` introduces; there is no `t` alias anywhere in this
procedure:

```sql
      WHEN 'NO_RECORD'
        THEN DATE_ADD(s.today_d, INTERVAL COALESCE(s.settle_days_eff, 7) DAY)
```

in `next_check_what`:

```sql
      WHEN 'NO_RECORD'
        THEN 'this subject spends but has no settled record yet — re-read when its first settled clicks arrive'
```

and in `state_reason`, so the row explains itself rather than falling through to a sentence written
for a different state:

```sql
      WHEN 'NO_RECORD'
        THEN CONCAT('spends but has no settled record to judge yet — admitted on spend (',
                    COALESCE(s.universe_source, 'CONFIG'), '), ',
                    CAST(COALESCE(s.settled_clk90, 0) AS STRING),
                    ' settled clicks. A silent window is never evidence of worthlessness.')
```

- [ ] **Step 4: Add the new columns to the history table and re-deploy the view**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
ALTER TABLE \`onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY\`
  ADD COLUMN IF NOT EXISTS bar_missing            BOOL,
  ADD COLUMN IF NOT EXISTS universe_source        STRING,
  ADD COLUMN IF NOT EXISTS serving_blocked_reason STRING"
```

Append the same three `ALTER TABLE` lines to
`scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql`, then carry `universe_source` and
`serving_blocked_reason` from the guard through to the final `SELECT`. **Spell the carry out — the
`DEAD` and `LOSER` predicates in Step 3 read `v.universe_source`, so it must reach `verd`, not only
the published row:**

- in the `g` CTE (`:121-129`), add `universe_source, serving_blocked_reason` to the select list;
- in the `base` CTE (`:286-303`), add `g.universe_source, g.serving_blocked_reason` beside
  `g.settle_ok, g.settle_due, …`;
- `calc`, `verd`, `st`, `fin`, `fin2` and `fin3` each select `*` from their predecessor, so nothing
  further is needed between `base` and the final `SELECT`;
- add `s.universe_source, s.serving_blocked_reason,` to the final `SELECT`'s column list.

Confirm the carry landed before deploying anything that depends on it:

```bash
cd /Users/ori/Develop/OI
grep -n "universe_source" scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql
```

Expected: at least four hits — the `g` CTE, the `base` CTE, the two ladder predicates in `st`, and
the final `SELECT`. Then:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_KEYWORD_STATE.sql)"
```

- [ ] **Step 5: Separate the ghosts from the subjects**

287 of 838 rows (34.2%) are ENABLED keywords inside PAUSED campaigns, all PARKED, all with NULL family, none ever present in `FACT_AMAZON_ADS`, costing $0.00–1.20/day between them. `serving_blocked_reason` now names them, so every population count can exclude them explicitly rather than diluting silently. Verify:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT COALESCE(serving_blocked_reason,'(can serve)') AS blocked, state, COUNT(*) n
   FROM \`onyga-482313.OI.V_KEYWORD_STATE\` GROUP BY 1,2 ORDER BY n DESC LIMIT 20"
```

Expected: the ghost population appears under a `campaign is PAUSED` reason, distinguishable from serving subjects.

- [ ] **Step 6: Run the two suites green**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/CATALOG_COVERAGE_acceptance.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql)"
```

Expected: five rows all `PASS` from the first, eleven rows all `PASS` from the second (K01 passes once the history table has two days; if it is still the first night, note it and re-run tomorrow).

- [ ] **Step 7: Verify the 27 downstream readers still compile**

Adding columns is safe for all of them; the check exists to catch an accidental rename or removal:

```bash
cd /Users/ori/Develop/OI
for v in V_RUN_SUMMARY V_PLAN_WINDOW_JUDGMENT V_HOLDOUT_ELIGIBLE V_ENGINE_HEALTH \
         V_FAMILY_SEAT_REGISTER V_LASTDAY_VETO_PREMISE V_THRESHOLD_TUNER \
         V_ADS_INCREMENTAL_14D V_RUN_UNCHANGED V_KEYWORD_STATE V_PARK_REVERDICT \
         V_DAILY_BRIEF V_OOB_KEYWORD V_KEYWORD_LIFT; do
  bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --dry_run \
    "SELECT 1 FROM \`onyga-482313.OI.$v\` LIMIT 0" >/dev/null 2>&1 \
    && echo "OK   $v" || echo "FAIL $v"
done
/usr/local/bin/python3 -m pytest tools/tests/ -q
```

Expected: `OK` on every view, all Python tests PASS.

- [ ] **Step 7b: THE STATE-LITERAL AUDIT — a new value in `state` is not a column addition**

Step 7 checks that nothing broke. This step checks the thing that does not break: **`NO_RECORD` is a
new value in the most widely-read column the Catalog publishes**, and every consumer that
enumerates `state` literals silently changes what it does the night this ships. "Adding columns is
safe" is true; adding *values* is not, and the two must not be confused.

Find every enumeration:

```bash
cd /Users/ori/Develop/OI
grep -rn "state IN ('\|state = 'PARKED'\|state = 'LOSER'\|state = 'REPRICE'\|state = 'DEAD'\|state = 'TRIAL'\|ladder_state IN (\|ladder_state = '" \
  scripts/bigquery/views scripts/bigquery/procedures scripts/bigquery/tests \
  | grep -v "\.bak" | grep -v "dim_state\|campaign_state\|entry_state"
```

Measured 2026-08-24 that reaches ten live files. Four of them decide money or a verdict and each gets
an explicit ruling **written into the file as a comment**, not left implicit:

| consumer | what it enumerates | the ruling for `NO_RECORD` |
|---|---|---|
| `SP_MAINTAIN_FAMILY_SEATS.sql:365-372` | `LOSER`/`DEAD` ⇒ seat closed, `PARKED` ⇒ `PARK_LAPSED`, `WINNER`/`PACED_WINNER`/`AT_BAR` ⇒ `TO_GOOD_SIDE` | falls to the `ELSE`. **Correct and deliberate** — a subject with no settled record has not earned a seat and has not lost one. Add `-- NO_RECORD (2026-08-25) falls through on purpose: no record is not an outcome.` |
| `V_FAMILY_SEAT_REGISTER.sql:533-539` | the register's display bucket | falls through to whatever the `ELSE` names. Add an explicit `WHEN state = 'NO_RECORD' THEN 'NO_RECORD'` arm so the register says it rather than mislabelling it |
| `V_PARK_REVERDICT.sql` | the revival population | `NO_RECORD` is not `PARKED`, so it is outside the park re-verdict by construction. **Correct** — a subject that never had a record cannot be revived. Say so in a comment |
| `V_DAILY_BRIEF.sql`, `V_ENGINE_HEALTH.sql`, `V_RUN_SUMMARY.sql`, `V_RUN_UNCHANGED.sql` | reporting buckets only | falls to `ELSE`; no money moves. Confirm each has an `ELSE` and record the count |

Then prove no subject fell into a silent hole:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT state, COUNT(*) n, ROUND(SUM(settled_sp90)/90, 2) usd_per_day
FROM \`onyga-482313.OI.V_KEYWORD_STATE\` GROUP BY 1 ORDER BY usd_per_day DESC"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT COUNT(*) register_rows,
       COUNTIF(bucket IS NULL) rows_with_no_bucket
FROM \`onyga-482313.OI.V_FAMILY_SEAT_REGISTER\`"
```

Expected: a `NO_RECORD` bucket with its own spend line, and `rows_with_no_bucket = 0`. **Record both
in the measurements file** — Task 5.5 adds a second new state (`NOT_WORTH_NOW`) to the same column
and re-runs this identical audit against the same table.

- [ ] **Step 7c: Re-run the engines and compare proposal counts**

Phase 2 widens the population the Catalog judges. The two ceiling views read the guard, and
`SP_ENGINE_PREFLIGHT` now reads the Catalog (Task 1.2). Nothing in this phase intends to change what
the engines propose — so measure it rather than assume it:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_ENGINE_PROPOSALS\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_ENGINE_PREFLIGHT\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT engine, lever, COUNT(*) n, COUNTIF(CAST(keyword_id AS STRING) = '-1') sentinel_rows
FROM \`onyga-482313.OI.FACT_ENGINE_PROPOSALS\`
WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_ENGINE_PROPOSALS\`)
GROUP BY 1,2 ORDER BY n DESC"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT (SELECT COUNT(*) FROM \`onyga-482313.OI.T_ENGINE_PREFLIGHT\`) preflight_rows,
       (SELECT COUNT(*) FROM \`onyga-482313.OI.FACT_ENGINE_PROPOSALS\`
        WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_ENGINE_PROPOSALS\`)
          AND hold_source IS NULL) proposals"
```

Expected: per-engine counts within a few rows of the 2026-08-24 baseline — LIFT 78, OOB 61, COACH 42,
LAUNCH 36, REVERDICT 6, LOW_STOCK 4, 227 in all — `sentinel_rows = 0` on every engine, and
`preflight_rows = proposals`. **A per-engine count that has multiplied is the guard fan-out**, which
Task 2.3 Step 3 item 3 exists to prevent; stop and check that the four `AND ... != '-1'` predicates
landed. A per-engine count that has *grown moderately* is the widened population reaching the
engines legitimately — record it and say which engine.

- [ ] **Step 8: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql \
        scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql \
        scripts/bigquery/views/V_KEYWORD_STATE.sql \
        scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql
git commit -m "feat(catalog): admit spending subjects safely — NO_RECORD, bar_missing, ad-group fix

Closes the coverage half of violation 4. A thin newly admitted row cannot reach a
terminal state; a row judged against a default bar of 1.0 says so; and the ad
group is resolved per (campaign, keyword) so a floor can no longer be borrowed."
```

---
## Phase 3 — Join campaign history on the id

**Closes:** violation 23 (campaign-level history keyed on name misattributes renamed campaigns).

**Why now.** Cheap, independent, and a hard prerequisite for both remaining large seasonal phases. 54 of 311 campaign_ids carry more than one name, and those ids hold $468,111 of $762,535 of lifetime spend — 61.4% of every dollar the account has ever spent sits on a campaign that has been renamed at least once; 6 names are additionally reused across ids ($68,125). `V_PEAK_STUCK_CAMPAIGNS.sql:41-50` sums `FACT_AMAZON_ADS` by `campaign_name` over all dates, and its track-record gate at lines 80–81 decides which paused campaigns to reactivate for a peak on that name-split history. §4.1 records this hazard as having nearly inverted the doctrine's own finding — the first pass showed the seasonal campaigns as near-dead, and only an id join revealed December returns of 3.4x to 7.1x. It goes now because Phase 4 is about to build a campaign verdict on exactly this history, and because the reactivation decision is live this season.

**Unblocks:** Phase 4's campaign verdict and Phase 5's seasonal evidence, both of which read campaign history. It also makes this season's reactivation list trustworthy before anyone acts on it.

**Size:** S — 2–3 days. Four view edits plus one new identity view.

---

### Task 3.1: Measure the divergence

- [ ] **Step 1: Size the rename population and the money on it**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH per_id AS (
  SELECT CAST(campaign_id AS STRING) cid, COUNT(DISTINCT campaign_name) names, SUM(Ads_cost) cost
  FROM \`onyga-482313.OI.FACT_AMAZON_ADS\` WHERE campaign_name IS NOT NULL GROUP BY 1),
per_name AS (
  SELECT campaign_name, COUNT(DISTINCT CAST(campaign_id AS STRING)) ids, SUM(Ads_cost) cost
  FROM \`onyga-482313.OI.FACT_AMAZON_ADS\` WHERE campaign_name IS NOT NULL GROUP BY 1)
SELECT (SELECT COUNT(*) FROM per_id) AS campaign_ids,
       (SELECT COUNTIF(names > 1) FROM per_id) AS ids_renamed,
       (SELECT ROUND(SUM(IF(names > 1, cost, 0)), 2) FROM per_id) AS usd_on_renamed_ids,
       (SELECT ROUND(SUM(cost), 2) FROM per_id) AS usd_lifetime,
       (SELECT COUNTIF(ids > 1) FROM per_name) AS names_reused_across_ids,
       (SELECT ROUND(SUM(IF(ids > 1, cost, 0)), 2) FROM per_name) AS usd_on_reused_names"
```

Expected: a non-zero `ids_renamed` carrying the majority of `usd_lifetime`. Measured 2026-08-24: 54 of 311 ids, $468,111.29 of $762,535.23 (61.4%); 6 reused names holding $68,125.75.

- [ ] **Step 2: Show that the reactivation gate reads the wrong pool**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH by_name AS (
  SELECT campaign_name, SUM(Ads_orders) ord, SUM(Ads_cost) cost, SUM(Ads_sales) sales
  FROM \`onyga-482313.OI.FACT_AMAZON_ADS\` WHERE campaign_name IS NOT NULL GROUP BY 1),
by_id AS (
  SELECT CAST(campaign_id AS STRING) cid, SUM(Ads_orders) ord, SUM(Ads_cost) cost,
         SUM(Ads_sales) sales
  FROM \`onyga-482313.OI.FACT_AMAZON_ADS\` GROUP BY 1),
cur AS (SELECT CAST(campaign_id AS STRING) cid, campaign_name
        FROM \`onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT\`)
SELECT COUNTIF(ABS(COALESCE(n.ord,0) - i.ord) > 0) AS campaigns_whose_lifetime_pool_differs,
       ROUND(SUM(ABS(COALESCE(n.cost,0) - i.cost)), 2) AS usd_misattributed
FROM by_id i JOIN cur ON cur.cid = i.cid
LEFT JOIN by_name n ON n.campaign_name = cur.campaign_name"
```

Expected: a non-zero count and a large `usd_misattributed`. This is what the track-record gate at `V_PEAK_STUCK_CAMPAIGNS.sql:80-81` is deciding on today.

- [ ] **Step 3: Record the measurement and commit it**

Every red measurement in this plan is a number the green run is compared against, so it is written
down rather than remembered. Append what you measured — the query, the date, and the count — to the
running record, creating the file on the first task that reaches this step:

```bash
cd /Users/ori/Develop/OI
mkdir -p docs/superpowers/specs
cat >> docs/superpowers/specs/2026-08-25-gap-closure-measurements.md <<'EOF'

## Task 3.1 — measured YYYY-MM-DD

Replace the date above with the date you ran it, and paste below: the query you ran (unchanged from
the task), and its output. Do not summarise the output — the point of this file is that a re-run is
a re-run and not a fresh argument, which is the same reason
docs/superpowers/specs/2026-08-24-three-layers-baseline.md exists.
EOF
git add docs/superpowers/specs/2026-08-25-gap-closure-measurements.md
git commit -m "measure(task 3.1): record the red measurement before the fix

The number the green run is compared against, written down rather than remembered."
```

---

### Task 3.2: `V_CAMPAIGN_IDENTITY`

**Files:**
- Create: `scripts/bigquery/views/V_CAMPAIGN_IDENTITY.sql`
- Modify: `config.yaml` (`views:` section)

- [ ] **Step 1: Write the view**

```sql
-- =============================================================================================
-- V_CAMPAIGN_IDENTITY — every name a campaign has carried, and the one it carries now.
--
-- WHY IT EXISTS. DIM_CAMPAIGN holds today's name; FACT_AMAZON_ADS holds the name as it was on the
-- day. Any campaign-level history keyed on name therefore splits a renamed campaign in two and
-- merges two campaigns that shared a name. architecture/THREE_LAYERS.md 4.1 records this hazard as
-- having nearly inverted the doctrine's own seasonal finding: the first pass showed the seasonal
-- campaigns as near-dead, and only a join on campaign_id revealed the December returns.
--
-- ONE PLACE. Every campaign-history join goes through this view so the fix does not have to be
-- re-derived per consumer, and so an audit can see in one query which campaigns are renamers.
--
-- GRAIN: one row per campaign_id. name_history is ordered oldest first.
-- SOURCE: DIM_CAMPAIGN's SCD2 (effective_from / effective_to / is_current).
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_IDENTITY` AS
WITH spans AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id,
         campaign_name,
         MIN(effective_from) AS name_from,
         MAX(COALESCE(effective_to, DATE '9999-12-31')) AS name_to,
         LOGICAL_OR(is_current) AS is_current_name
  FROM `onyga-482313.OI.DIM_CAMPAIGN`
  WHERE campaign_name IS NOT NULL
  GROUP BY 1, 2
),
cur AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id, campaign_name AS current_name,
         campaign_type, state AS campaign_state, portfolio_id, portfolio_name, daily_budget
  FROM `onyga-482313.OI.DIM_CAMPAIGN`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY CAST(campaign_id AS STRING)
                             ORDER BY is_current DESC, effective_from DESC, campaign_name) = 1
),
-- names as the ads fact recorded them, which can include a name DIM_CAMPAIGN no longer holds
fact_names AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id, campaign_name,
         MIN(date) AS first_seen, MAX(date) AS last_seen, SUM(Ads_cost) AS spend_under_name
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE campaign_name IS NOT NULL
  GROUP BY 1, 2
),
agg AS (
  SELECT campaign_id,
         ARRAY_AGG(STRUCT(campaign_name AS name, name_from, name_to, is_current_name)
                   ORDER BY name_from) AS name_history,
         COUNT(DISTINCT campaign_name) AS distinct_names
  FROM spans GROUP BY 1
),
fagg AS (
  SELECT campaign_id,
         ARRAY_AGG(STRUCT(campaign_name AS name, first_seen, last_seen, spend_under_name)
                   ORDER BY first_seen) AS fact_name_history,
         COUNT(DISTINCT campaign_name) AS distinct_fact_names,
         SUM(spend_under_name) AS lifetime_spend
  FROM fact_names GROUP BY 1
),
-- a name that more than one campaign_id has ever carried is unsafe to key on in EITHER direction
shared AS (
  SELECT campaign_name FROM fact_names GROUP BY 1
  HAVING COUNT(DISTINCT campaign_id) > 1
)
SELECT
  c.campaign_id,
  c.current_name,
  c.campaign_type,
  c.campaign_state,
  c.portfolio_id,
  c.portfolio_name,
  c.daily_budget,
  COALESCE(a.name_history, [])                                     AS name_history,
  COALESCE(f.fact_name_history, [])                                AS fact_name_history,
  GREATEST(COALESCE(a.distinct_names, 1),
           COALESCE(f.distinct_fact_names, 1)) - 1                 AS name_changed_count,
  GREATEST(COALESCE(a.distinct_names, 1),
           COALESCE(f.distinct_fact_names, 1)) > 1                 AS has_been_renamed,
  COALESCE(f.lifetime_spend, 0.0)                                  AS lifetime_spend,
  EXISTS (SELECT 1 FROM shared s WHERE s.campaign_name = c.current_name)
                                                                   AS current_name_shared_with_another_campaign
FROM cur c
LEFT JOIN agg  a ON a.campaign_id = c.campaign_id
LEFT JOIN fagg f ON f.campaign_id = c.campaign_id;
```

- [ ] **Step 2: Deploy and check the grain**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_CAMPAIGN_IDENTITY.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT COUNT(*) rows, COUNT(DISTINCT campaign_id) ids,
          COUNTIF(has_been_renamed) renamed,
          COUNTIF(current_name_shared_with_another_campaign) shared_names,
          ROUND(SUM(IF(has_been_renamed, lifetime_spend, 0)), 2) usd_on_renamed
   FROM \`onyga-482313.OI.V_CAMPAIGN_IDENTITY\`"
```

Expected: `rows = ids`, and `renamed` / `usd_on_renamed` matching Task 3.1's measurement.

- [ ] **Step 3: Register in `config.yaml`** — insert in the `views:` list beside `V_CAMPAIGN_FAMILY_MAP` (index 126):

```yaml
  - name: V_CAMPAIGN_IDENTITY
    description: >-
      One row per campaign_id carrying every name it has ever held — from DIM_CAMPAIGN's SCD2 and
      from the names FACT_AMAZON_ADS recorded on the day — its current name, how many times it has
      been renamed, its lifetime spend, and whether its current name is shared with another
      campaign. The single place any campaign-history join goes, so the rename hazard in
      architecture/THREE_LAYERS.md 4.1 does not have to be re-derived per consumer.
    type: view
    source_files:
      - scripts/bigquery/views/V_CAMPAIGN_IDENTITY.sql
    dependencies:
      - DIM_CAMPAIGN
      - FACT_AMAZON_ADS
```

- [ ] **Step 4: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_CAMPAIGN_IDENTITY.sql config.yaml
git commit -m "feat(catalog): V_CAMPAIGN_IDENTITY — every name a campaign has carried

One place for a campaign-history join to go. 61.4% of lifetime spend sits on ids
that have been renamed at least once (THREE_LAYERS 4.1)."
```

---

### Task 3.3: Re-key `V_PEAK_STUCK_CAMPAIGNS` onto the id

**Files:**
- Modify: `scripts/bigquery/views/V_PEAK_STUCK_CAMPAIGNS.sql:23-38` (`camp`), `:41-50` (`lifetime`), `:72` (the join)

- [ ] **Step 1: Back up**

```bash
cd /Users/ori/Develop/OI
NEXT=$(ls scripts/bigquery/**/*.bak.v27.*.* 2>/dev/null | sed -E 's/.*\.bak\.v27\.([0-9]+)\..*/\1/' | sort -n | tail -1)
NEXT=$((NEXT + 1))
cp scripts/bigquery/views/V_PEAK_STUCK_CAMPAIGNS.sql \
   scripts/bigquery/views/V_PEAK_STUCK_CAMPAIGNS.sql.bak.v27.$NEXT.$(date +%H%M)
```

- [ ] **Step 2: Replace the two CTEs**

`V_ADS_COACH` publishes `campaign_id` (verified), so the `camp` CTE can group on it. Replace lines 23–50 with:

```sql
-- 2026-08-25 (violation 23): GROUPED ON campaign_id, NOT campaign_name. This view decides which
-- paused campaigns are worth reactivating for a peak, and its track-record gate below reads the
-- lifetime pool. A rename splits that pool in two, so the gate was judging half a history — the
-- hazard architecture/THREE_LAYERS.md 4.1 records as having nearly inverted the doctrine's own
-- seasonal finding. The current NAME is still published, from V_CAMPAIGN_IDENTITY, because that is
-- what a person reads on the Peak page; it is no longer what anything joins on.
WITH camp AS (
  SELECT
    CAST(campaign_id AS STRING)                     AS campaign_id,
    ANY_VALUE(campaign_name)                        AS campaign_name,
    ANY_VALUE(parent_name)                          AS parent_name,
    ANY_VALUE(campaign_state)                       AS campaign_state,
    ROUND(ANY_VALUE(camp_budget_util_pct), 0)       AS budget_util_pct,
    ANY_VALUE(current_budget)                       AS budget,
    ANY_VALUE(pp_campaign_orders)                   AS recent_orders,
    ROUND(ANY_VALUE(pp_campaign_net_roas), 2)       AS net_roas,
    ROUND(ANY_VALUE(sqp_impression_share_8w), 3)    AS share_8w,
    ROUND(ANY_VALUE(sqp_ly_impression_share), 3)    AS share_ly,
    ANY_VALUE(days_since_last_budget_change)        AS days_since_budget_chg
  FROM `onyga-482313.OI.V_ADS_COACH`
  WHERE campaign_id IS NOT NULL
  GROUP BY campaign_id
),

-- Lifetime track record per campaign ID (all dates) — was it ever a success? Keyed on the id, so a
-- renamed campaign keeps one history instead of two halves.
lifetime AS (
  SELECT
    CAST(campaign_id AS STRING) AS campaign_id,
    SUM(Ads_orders) AS lt_orders,
    ROUND(SUM(Ads_cost), 0) AS lt_spend,
    ROUND(SAFE_DIVIDE(SUM(Ads_sales), NULLIF(SUM(Ads_cost), 0)), 2) AS lt_roas
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE campaign_id IS NOT NULL
  GROUP BY campaign_id
)
```

- [ ] **Step 3: Re-key the join and publish the identity**

Line 72 today reads `LEFT JOIN lifetime l ON l.campaign_name = c.campaign_name`. Replace with:

```sql
FROM camp c
LEFT JOIN lifetime l ON l.campaign_id = c.campaign_id
LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_IDENTITY` ci ON ci.campaign_id = c.campaign_id
```

and add two columns to the published `SELECT`, immediately after `c.campaign_name`:

```sql
  c.campaign_id,
  COALESCE(ci.current_name, c.campaign_name)          AS current_campaign_name,
  COALESCE(ci.name_changed_count, 0)                  AS name_changed_count,
```

- [ ] **Step 4: Deploy and prove the pools changed for the renamers**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_PEAK_STUCK_CAMPAIGNS.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH v AS (SELECT campaign_id, lt_orders, lt_roas, name_changed_count
           FROM \`onyga-482313.OI.V_PEAK_STUCK_CAMPAIGNS\`),
truth AS (SELECT CAST(campaign_id AS STRING) cid, SUM(Ads_orders) ord,
                 ROUND(SAFE_DIVIDE(SUM(Ads_sales), NULLIF(SUM(Ads_cost),0)), 2) roas
          FROM \`onyga-482313.OI.FACT_AMAZON_ADS\` GROUP BY 1)
SELECT COUNTIF(v.lt_orders != t.ord) AS pools_that_still_disagree,
       COUNTIF(v.name_changed_count > 0) AS renamed_campaigns_on_the_page
FROM v JOIN truth t ON t.cid = v.campaign_id"
```

Expected: `pools_that_still_disagree = 0`.

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_PEAK_STUCK_CAMPAIGNS.sql
git commit -m "fix(peak): reactivation is decided on an id-keyed lifetime pool

Closes the live half of violation 23. The track-record gate read a name-split
history, which is the hazard 4.1 records as nearly inverting the seasonal finding."
```

---

### Task 3.4: `V_PAUSED_CAMPAIGN_HISTORY` derives its season from the id

**Files:**
- Modify: `scripts/bigquery/views/V_PAUSED_CAMPAIGN_HISTORY.sql:16-30`

`is_seasonal` and `season_holiday` are `REGEXP_CONTAINS` over the **current** `campaign_name`, so a renamed campaign silently loses its season classification — in the one object that is otherwise correctly id-keyed (it joins history on `campaign_id` at lines 61 and 99).

- [ ] **Step 1: Back up, then replace the classification block**

```bash
cd /Users/ori/Develop/OI
NEXT=$(ls scripts/bigquery/**/*.bak.v27.*.* 2>/dev/null | sed -E 's/.*\.bak\.v27\.([0-9]+)\..*/\1/' | sort -n | tail -1)
NEXT=$((NEXT + 1))
cp scripts/bigquery/views/V_PAUSED_CAMPAIGN_HISTORY.sql \
   scripts/bigquery/views/V_PAUSED_CAMPAIGN_HISTORY.sql.bak.v27.$NEXT.$(date +%H%M)
```

Replace the `is_seasonal` / `season_holiday` expressions (lines 16–30) with a lookup over the full name history:

```sql
    -- 2026-08-25 (violation 23): the season is derived from EVERY name this campaign has carried,
    -- not from the one it carries today. A rename used to erase a campaign's season classification
    -- silently, in the one object that is otherwise correctly keyed on campaign_id.
    -- name_derived is published so a consumer knows this classification comes from text and is
    -- fragile by construction — Phase 4's FACT_CAMPAIGN_STATE replaces it with a verdict.
    EXISTS (
      SELECT 1 FROM UNNEST(ci.fact_name_history) fn
      WHERE REGEXP_CONTAINS(LOWER(fn.name),
        r'(christmas|xmas|holiday|gift|valentine|easter|halloween|bts|back.?to.?school|prime.?day|black.?friday|cyber|mother|father|graduat)')
    ) OR EXISTS (
      SELECT 1 FROM UNNEST(ci.name_history) nh
      WHERE REGEXP_CONTAINS(LOWER(nh.name),
        r'(christmas|xmas|holiday|gift|valentine|easter|halloween|bts|back.?to.?school|prime.?day|black.?friday|cyber|mother|father|graduat)')
    )                                                                     AS is_seasonal,
    (SELECT h.holiday_name
     FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
     WHERE EXISTS (SELECT 1 FROM UNNEST(ci.fact_name_history) fn
                   WHERE STRPOS(UPPER(fn.name), UPPER(h.holiday_name)) > 0)
        OR EXISTS (SELECT 1 FROM UNNEST(ci.name_history) nh
                   WHERE STRPOS(UPPER(nh.name), UPPER(h.holiday_name)) > 0)
     ORDER BY h.holiday_date DESC LIMIT 1)                                AS season_holiday,
    TRUE                                                                  AS season_is_name_derived,
```

and add the join that supplies `ci` to the same CTE:

```sql
  LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_IDENTITY` ci
    ON ci.campaign_id = CAST(c.campaign_id AS STRING)
```

- [ ] **Step 2: Deploy and confirm no renamed campaign lost its season**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_PAUSED_CAMPAIGN_HISTORY.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT COUNTIF(is_seasonal) seasonal, COUNT(*) rows,
          COUNTIF(is_seasonal AND season_holiday IS NULL) seasonal_without_a_holiday
   FROM \`onyga-482313.OI.V_PAUSED_CAMPAIGN_HISTORY\` WHERE target_text IS NULL"
```

Expected: `seasonal` is greater than or equal to the count before the change (rerun the backup file to compare if needed) — the history can only add classifications, never remove them.

- [ ] **Step 3: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_PAUSED_CAMPAIGN_HISTORY.sql
git commit -m "fix(seasonal): paused-campaign season derived from the full name history

A renamed campaign silently lost its season classification in the one object that
is otherwise correctly id-keyed. season_is_name_derived says the classification is
text-based and fragile."
```

---

### Task 3.5: Label the two remaining name-derived classifications

**Files:**
- Modify: `scripts/bigquery/views/V_ADS_COACH.sql:483` and `:2371`
- Modify: `scripts/bigquery/views/V_CAMPAIGN_FAMILY_MAP.sql:167-168` (the prefix join, demoted)

Neither of these is a history join, so neither misattributes money — but both classify a campaign from its current name, and a consumer cannot tell. Publish the fragility rather than silently fixing something that has no id-keyed equivalent.

- [ ] **Step 1: Back up both files**

```bash
cd /Users/ori/Develop/OI
NEXT=$(ls scripts/bigquery/**/*.bak.v27.*.* 2>/dev/null | sed -E 's/.*\.bak\.v27\.([0-9]+)\..*/\1/' | sort -n | tail -1)
NEXT=$((NEXT + 1))
cp scripts/bigquery/views/V_ADS_COACH.sql \
   scripts/bigquery/views/V_ADS_COACH.sql.bak.v27.$NEXT.$(date +%H%M)
cp scripts/bigquery/views/V_CAMPAIGN_FAMILY_MAP.sql \
   scripts/bigquery/views/V_CAMPAIGN_FAMILY_MAP.sql.bak.v27.$((NEXT+1)).$(date +%H%M)
```

- [ ] **Step 2: Publish the flag in `V_ADS_COACH`**

The holiday join at line 483 reads `ON STRPOS(UPPER(d.campaign_name), UPPER(h.holiday_name)) > 0`. Leave the join, and add one published column to the view's final `SELECT`:

```sql
  -- 2026-08-25 (violation 23): this campaign's holiday and launch-type classifications come from
  -- matching text in its CURRENT name (the joins at the holiday and name-token CTEs). A rename
  -- changes them, and nothing else in this view is keyed that way. Publish the fragility rather
  -- than pretend it is an id-keyed fact — Phase 4's FACT_CAMPAIGN_STATE is the id-keyed answer.
  TRUE AS campaign_classification_is_name_derived,
```

- [ ] **Step 3: Demote the prefix arm in `V_CAMPAIGN_FAMILY_MAP`**

The final `SELECT` today resolves `COALESCE(cf.parent_name, af.parent_name, pm.parent_name, 'Unknown')` and publishes `resolution_source` with three arms. The order already prefers the hand-set map, then the advertised ASIN, then the name prefix — so the demotion is already correct and no change to the COALESCE is needed. What is missing is that a consumer cannot filter on it cheaply. Add one column to the final `SELECT`:

```sql
  -- 2026-08-25 (violation 23): TRUE where the family came from an alphabetic prefix of the
  -- campaign NAME. It is the last resort and already sits below the hand-set map and the
  -- advertised-ASIN arm in the COALESCE above; this column lets a consumer refuse a name-derived
  -- family outright, which Phase 4's campaign verdict does.
  (cf.parent_name IS NULL AND af.parent_name IS NULL AND pm.parent_name IS NOT NULL)
    AS family_is_name_derived,
```

- [ ] **Step 4: Deploy both and verify**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_CAMPAIGN_FAMILY_MAP.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_ADS_COACH.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT resolution_source, family_is_name_derived, COUNT(*) n
   FROM \`onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP\` GROUP BY 1,2 ORDER BY n DESC"
```

Expected: `family_is_name_derived` is TRUE exactly where `resolution_source = 'the name it was given'`.

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_ADS_COACH.sql scripts/bigquery/views/V_CAMPAIGN_FAMILY_MAP.sql
git commit -m "feat(catalog): label the name-derived campaign classifications

Neither is a history join, so neither misattributes money — but a consumer could
not tell that a rename would change the answer. Now it can."
```

---

### Task 3.6: `CAMPAIGN_IDENTITY_acceptance.sql`

**Files:**
- Create: `scripts/bigquery/tests/CAMPAIGN_IDENTITY_acceptance.sql`

- [ ] **Step 1: Write the suite**

```sql
-- =============================================================================================
-- CAMPAIGN IDENTITY acceptance — campaign history is keyed on the id. EVERY ROW MUST READ PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Doctrine: architecture/THREE_LAYERS.md 4.1 "join campaign history on the id, never on the name".
-- =============================================================================================
WITH truth AS (
  SELECT CAST(campaign_id AS STRING) AS cid,
         SUM(Ads_orders) AS ord, SUM(Ads_cost) AS cost, SUM(Ads_sales) AS sales
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE campaign_id IS NOT NULL
  GROUP BY 1
),
i01 AS (
  SELECT 'I01 V_CAMPAIGN_IDENTITY is one row per campaign_id' AS check_name,
         (SELECT COUNT(*) FROM (SELECT campaign_id FROM `onyga-482313.OI.V_CAMPAIGN_IDENTITY`
                                GROUP BY 1 HAVING COUNT(*) > 1)) AS violations
),
i02 AS (
  SELECT 'I02 the peak page lifetime pool equals the id-keyed pool exactly (violation 23)',
         (SELECT COUNTIF(v.lt_orders != t.ord)
          FROM `onyga-482313.OI.V_PEAK_STUCK_CAMPAIGNS` v
          JOIN truth t ON t.cid = v.campaign_id)
),
i03 AS (
  SELECT 'I03 every renamed campaign carries its name history',
         (SELECT COUNTIF(has_been_renamed AND ARRAY_LENGTH(fact_name_history) < 2
                         AND ARRAY_LENGTH(name_history) < 2)
          FROM `onyga-482313.OI.V_CAMPAIGN_IDENTITY`)
),
i04 AS (
  SELECT 'I04 a text-derived classification says so on the row',
         (SELECT COUNTIF(resolution_source = 'the name it was given' AND NOT family_is_name_derived)
              + COUNTIF(resolution_source != 'the name it was given' AND family_is_name_derived)
          FROM `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP`)
),
i05 AS (
  SELECT 'I05 the paused-campaign season survives a rename',
         (SELECT COUNTIF(ci.has_been_renamed AND NOT h.is_seasonal
                         AND EXISTS (SELECT 1 FROM UNNEST(ci.fact_name_history) fn
                                     WHERE REGEXP_CONTAINS(LOWER(fn.name),
                                       r'(christmas|xmas|holiday|gift|valentine|easter|halloween|bts|back.?to.?school|prime.?day|black.?friday|cyber|mother|father|graduat)')))
          FROM `onyga-482313.OI.V_PAUSED_CAMPAIGN_HISTORY` h
          JOIN `onyga-482313.OI.V_CAMPAIGN_IDENTITY` ci
            ON ci.campaign_id = CAST(h.campaign_id AS STRING)
          WHERE h.target_text IS NULL)
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM (SELECT * FROM i01 UNION ALL SELECT * FROM i02 UNION ALL SELECT * FROM i03
      UNION ALL SELECT * FROM i04 UNION ALL SELECT * FROM i05)
ORDER BY check_name;
```

- [ ] **Step 2: Add the grep-backed half — no repo view groups campaign history on the name**

```bash
cd /Users/ori/Develop/OI
grep -rn "GROUP BY campaign_name\|GROUP BY 1" scripts/bigquery/views/*.sql \
  | grep -i "campaign_name" | grep -v "V_CAMPAIGN_IDENTITY" || echo "NONE — PASS"
grep -rn "ON .*\.campaign_name = .*\.campaign_name" scripts/bigquery/views/*.sql \
  | grep -v "V_CAMPAIGN_IDENTITY" || echo "NONE — PASS"
```

Expected: `NONE — PASS` from both, or only hits inside `V_CAMPAIGN_IDENTITY` itself, which is where names legitimately live.

- [ ] **Step 3: Run the SQL suite**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/CAMPAIGN_IDENTITY_acceptance.sql)"
```

Expected: five rows, all `PASS`.

- [ ] **Step 4: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/tests/CAMPAIGN_IDENTITY_acceptance.sql
git commit -m "test(catalog): campaign identity acceptance — history is keyed on the id"
```

---
## Phase 4 — The campaign becomes a subject, and every campaign gets a bar

**Closes:** violation 22, the OPEN half. The CLOSE arm is deliberately withheld to Phase 7.

**Why here, before the seasonal keyword work.** Two facts force it. First, **the money is dated**: ten paused campaigns carry 2,826 orders and $127,352 of last-season sales at a pooled 1.49 GP-ROAS, five of them stopped on a single day in mid-July, and an `INFORMATION_SCHEMA` scan for `%reopen%` / `%unpause%` / `%revisit%` / `%next_check%` / `%due_date%` returns exactly seven columns, all keyword-grain — nothing anywhere holds a reopen date for any of them. Second, **the family map is the hard prerequisite for everything seasonal**: `V_CAMPAIGN_FAMILY_MAP` is ENABLED-only with a 90-day learning window, so `T_FAMILY_BAR` holds exactly the 90 ENABLED campaigns and the other 1,023 have no bar at all — and measured, 100% of holiday-2024 spend and 31.8% of holiday-2025 spend belongs to campaigns with no family today. A seasonal answer with no bar to answer against is not an answer. Widening the map is one task and 100% of the missing attribution is recoverable.

**Why CLOSE is withheld.** A campaign has no park, so CLOSE is a **new irreversible action**, and §5 forbids one below HIGH confidence, which does not exist until Phase 7. Shipping OPEN alone is money-positive and reversible.

**Unblocks:** Phase 5 (a seasonal verdict needs a family bar over both holiday seasons); Phase 7's CLOSE arm; §4.1's lead-time requirement, which needs a campaign-grain answer for a requested window.

**Size:** L — 1.5–2.5 weeks. A new grain, a new FACT, a new SP, an orchestrator slot and a new book.

---

### Task 4.1: Three red measurements

- [ ] **Step 1: The bar covers only the ENABLED campaigns**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT (SELECT COUNT(DISTINCT campaign_id) FROM \`onyga-482313.OI.T_FAMILY_BAR\`) AS campaigns_with_a_bar,
       (SELECT COUNT(DISTINCT campaign_id) FROM \`onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT\`
        WHERE campaign_state = 'ENABLED') AS enabled_campaigns,
       (SELECT COUNT(DISTINCT campaign_id) FROM \`onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT\`
        WHERE campaign_state != 'ENABLED') AS non_enabled_campaigns_with_no_bar"
```

Expected: `campaigns_with_a_bar = enabled_campaigns`, and a large `non_enabled_campaigns_with_no_bar`. Measured 2026-08-24: 90, 90, 1,023.

- [ ] **Step 2: Nothing carries a campaign-grain reopen date**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT table_name, column_name FROM \`onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS\`
WHERE LOWER(column_name) LIKE '%reopen%' OR LOWER(column_name) LIKE '%unpause%'
   OR LOWER(column_name) LIKE '%revisit%' OR LOWER(column_name) LIKE '%next_check%'
   OR LOWER(column_name) LIKE '%due_date%'
ORDER BY 1, 2"
```

Expected: every row returned is keyword-grain (`FACT_KEYWORD_STATE` / `V_KEYWORD_STATE` / `V_RUN_UNCHANGED`). Measured 2026-08-24: seven columns, all keyword-grain, none campaign-grain.

- [ ] **Step 3: Both holiday seasons are unattributable to a family**

Re-run the baseline's own query rather than writing a new one — it is committed at `docs/superpowers/specs/2026-08-24-three-layers-baseline.md` under **"The family map is ENABLED-only with a 90-day learning window"**. Run both queries in that section: the first measures `pct_spend_with_no_family_today` per period, the second measures how much of it is recoverable.

Expected: holiday 2024 100.0% with no family today, holiday 2025 31.8%, and the adversarial check reporting essentially all of it recoverable by dropping the ENABLED filter and widening the window.

- [ ] **Step 4: Record the measurement and commit it**

Every red measurement in this plan is a number the green run is compared against, so it is written
down rather than remembered. Append what you measured — the query, the date, and the count — to the
running record, creating the file on the first task that reaches this step:

```bash
cd /Users/ori/Develop/OI
mkdir -p docs/superpowers/specs
cat >> docs/superpowers/specs/2026-08-25-gap-closure-measurements.md <<'EOF'

## Task 4.1 — measured YYYY-MM-DD

Replace the date above with the date you ran it, and paste below: the query you ran (unchanged from
the task), and its output. Do not summarise the output — the point of this file is that a re-run is
a re-run and not a fresh argument, which is the same reason
docs/superpowers/specs/2026-08-24-three-layers-baseline.md exists.
EOF
git add docs/superpowers/specs/2026-08-25-gap-closure-measurements.md
git commit -m "measure(task 4.1): record the red measurement before the fix

The number the green run is compared against, written down rather than remembered."
```

---

### Task 4.2: Widen `V_CAMPAIGN_FAMILY_MAP`, and rebuild the bar on it

**Files:**
- Modify: `scripts/bigquery/views/V_CAMPAIGN_FAMILY_MAP.sql:88-92` (`k`), `:99-101` (`enabled`), `:111` (the ASIN window), `:164` (the final FROM)
- Re-deploy: `scripts/bigquery/procedures/SP_SNAPSHOT_FAMILY_BAR.sql` (no code change — it is re-run against the widened map)

- [ ] **Step 1: Back up**

```bash
cd /Users/ori/Develop/OI
NEXT=$(ls scripts/bigquery/**/*.bak.v27.*.* 2>/dev/null | sed -E 's/.*\.bak\.v27\.([0-9]+)\..*/\1/' | sort -n | tail -1)
NEXT=$((NEXT + 1))
cp scripts/bigquery/views/V_CAMPAIGN_FAMILY_MAP.sql \
   scripts/bigquery/views/V_CAMPAIGN_FAMILY_MAP.sql.bak.v27.$NEXT.$(date +%H%M)
```

- [ ] **Step 2: Widen the learning window**

The `k` CTE today declares `90 AS learning_window_days`. Replace that line and its comment with:

```sql
    -- 2026-08-25 (violation 22): ALL HISTORY, not 90 days. The ads data starts 2024-09-05, so this
    -- window is what decides whether either holiday season is attributable to a family at all.
    -- Measured before this change: 100% of holiday-2024 spend and 31.8% of holiday-2025 spend
    -- belonged to campaigns with no family today, and essentially all of it was recoverable simply
    -- by widening the window and dropping the ENABLED filter below. A seasonal answer with no bar
    -- to answer against is not an answer (architecture/THREE_LAYERS.md 4.1, 2.2).
    -- The literal is the first date FACT_AMAZON_ADS holds; re-derive with
    --   SELECT MIN(date) FROM `onyga-482313.OI.FACT_AMAZON_ADS`
    DATE '2024-09-05' AS learning_window_start
```

and change the two places that consume it — the `asin_fam` CTE at line 111 and the `spent` CTE — from

```sql
    WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL (SELECT learning_window_days FROM k) DAY)
```

to

```sql
    WHERE a.date >= (SELECT learning_window_start FROM k)
```

- [ ] **Step 3: Drop the ENABLED filter**

The `enabled` CTE reads:

```sql
enabled AS (
  SELECT campaign_id, campaign_name FROM latest WHERE state = 'ENABLED'
),
```

Replace with:

```sql
-- 2026-08-25 (violation 22): EVERY campaign, not only the ENABLED ones. A paused seasonal campaign
-- had no family, therefore no row in T_FAMILY_BAR, therefore no bar the Catalog could answer
-- against — which made a campaign verdict impossible at exactly the grain 4.1 needs it.
-- campaign_state rides through so a consumer that genuinely wants only live campaigns can filter,
-- rather than having the filter hidden in the population.
enabled AS (
  SELECT campaign_id, campaign_name, state AS campaign_state FROM latest
),
```

and add `e.campaign_state` to the final `SELECT`'s column list.

- [ ] **Step 4: Deploy and measure the recovery**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_CAMPAIGN_FAMILY_MAP.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH s AS (SELECT CAST(campaign_id AS STRING) cid, DATE_TRUNC(date, MONTH) mo, SUM(Ads_cost) c
           FROM \`onyga-482313.OI.FACT_AMAZON_ADS\` WHERE date >= DATE '2024-09-05' GROUP BY 1,2)
SELECT CASE WHEN mo BETWEEN DATE '2024-10-01' AND DATE '2024-12-31' THEN 'holiday 2024'
            WHEN mo BETWEEN DATE '2025-10-01' AND DATE '2025-12-31' THEN 'holiday 2025'
            ELSE 'other' END AS period,
       ROUND(SUM(c), 0) usd,
       ROUND(100 * SUM(IF(m.campaign_id IS NULL, c, 0)) / SUM(c), 1) pct_no_family_today
FROM s LEFT JOIN \`onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP\` m ON m.campaign_id = s.cid
GROUP BY period ORDER BY period"
```

Expected: `pct_no_family_today` falls to near zero for both holiday periods (the baseline measured essentially all of it recoverable).

- [ ] **Step 4b: PROVE NO EXISTING CAMPAIGN CHANGED FAMILY — the risk this task actually carries**

Widening the window does more than admit campaigns that had no family. `asin_fam`
(`V_CAMPAIGN_FAMILY_MAP.sql:102-112`) picks a campaign's family with
`ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY SUM(a.Ads_cost) DESC, p.parent_name)` — so
re-computing that sum over two years instead of ninety days **can flip the dominant `parent_name` of
a campaign that already had one**, if its advertised-ASIN mix shifted. A changed `parent_name`
changes `T_FAMILY_BAR.keyword_bar`, which changes `affordable_cpc = gp_per_click / family_bar`, which
changes the `ceiling_bid` Task 1.2 just made binding on every engine proposal. Step 5's clamp check
cannot see it: a bar that moves from 0.84 to 0.91 is inside the clamp and inside the 5e-5 tolerance
of nothing.

**Measured 2026-08-24 the answer is zero — 130 campaigns resolve under both windows and not one
changes `parent_name`.** That is a reason to assert it, not a reason to skip it: the mix shifts every
season, and this task will be re-run against a different corpus than the one that measurement came
from. Capture the before, deploy, then compare:

```bash
cd /Users/ori/Develop/OI
# BEFORE — run this while the 90-day view is still deployed, i.e. before Step 4's deploy line
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CREATE OR REPLACE TABLE \`onyga-482313.OI.TMP_FAMILY_MAP_BEFORE\` AS
   SELECT m.campaign_id, m.parent_name, b.keyword_bar
   FROM \`onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP\` m
   LEFT JOIN (SELECT CAST(campaign_id AS STRING) cid, ANY_VALUE(keyword_bar) keyword_bar
              FROM \`onyga-482313.OI.T_FAMILY_BAR\` GROUP BY 1) b
     ON b.cid = m.campaign_id"
```

and after Step 5's `SP_SNAPSHOT_FAMILY_BAR` rebuild:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH after_ AS (
  SELECT m.campaign_id, m.parent_name, b.keyword_bar
  FROM \`onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP\` m
  LEFT JOIN (SELECT CAST(campaign_id AS STRING) cid, ANY_VALUE(keyword_bar) keyword_bar
             FROM \`onyga-482313.OI.T_FAMILY_BAR\` GROUP BY 1) b
    ON b.cid = m.campaign_id)
SELECT COUNT(*) campaigns_resolved_before_and_after,
       COUNTIF(x.parent_name != a.parent_name)                       AS family_flipped,
       COUNTIF(x.keyword_bar IS NOT NULL AND a.keyword_bar IS NOT NULL
               AND ABS(x.keyword_bar - a.keyword_bar) > 0.00005)      AS bar_moved,
       COUNTIF(x.keyword_bar IS NULL AND a.keyword_bar IS NOT NULL)   AS gained_a_bar
FROM \`onyga-482313.OI.TMP_FAMILY_MAP_BEFORE\` x
JOIN after_ a USING (campaign_id)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "DROP TABLE \`onyga-482313.OI.TMP_FAMILY_MAP_BEFORE\`"
```

Expected: `family_flipped = 0` and `bar_moved = 0`; `gained_a_bar` is the whole point of the task and
should be large. **`family_flipped > 0` is stop-the-line.** It means a campaign that is live today is
now judged against a different family's bar, and every ceiling on every keyword inside it moved with
it. Do not proceed: list the campaigns, put them to Ori by name with the two families and the two
bars, and record the outcome in the measurements file. `bar_moved > 0` with `family_flipped = 0` is
the halo re-computing over a wider corpus — smaller, but the same class; list them and say by how
much before continuing.

- [ ] **Step 5: Rebuild `T_FAMILY_BAR` against the widened map**

`SP_SNAPSHOT_FAMILY_BAR.sql:64` INNER JOINs `V_CAMPAIGN_FAMILY_MAP` deliberately, so a campaign the map cannot resolve gets no bar. With the map widened it now resolves far more campaigns. **The bar computation itself is not changed** — only the population it covers.

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_FAMILY_BAR\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT COUNT(DISTINCT campaign_id) campaigns_with_a_bar,
       COUNT(DISTINCT family) families,
       COUNTIF(bar_exempt) exempt_rows,
       COUNTIF(keyword_bar < 0.60 - 0.00005 OR keyword_bar > 1.00 + 0.00005) outside_the_clamp
FROM \`onyga-482313.OI.T_FAMILY_BAR\`"
```

Expected: `campaigns_with_a_bar` rises from 90 to roughly the full resolvable population, and `outside_the_clamp = 0`. **The tolerance is 5e-5, not 1e-9** — `keyword_bar` is `ROUND`ed to four decimals in `V_FAMILY_BAR.sql:169-177`, so a tighter assertion produces false failures.

- [ ] **Step 6: Refresh the ladder and confirm `bar_missing` collapses**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT COUNTIF(bar_missing) AS subjects_with_no_bar, COUNT(*) AS subjects
   FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`
   WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`)"
```

Expected: `subjects_with_no_bar` falls sharply from its Phase 2 level.

- [ ] **Step 6b: Dry-run every downstream reader of the widened map — this is the largest blast radius in the plan**

`V_CAMPAIGN_FAMILY_MAP` goes from 90 campaigns to roughly 1,113 in one deploy, and `T_FAMILY_BAR` is
not its only consumer — the `grep` above returned **eighteen** files on 2026-08-24. Step 5 checks the
bar's clamp; it checks nothing about the other objects that read the map, one of which (`V_PANEL_OWNERSHIP`) carries a **1:1 single-home claim that
`SP_ENGINE_PREFLIGHT.sql:141-144` relies on to guarantee its join cannot fan the proposal set out**.
Find the readers and check every one:

```bash
cd /Users/ori/Develop/OI
grep -rln "V_CAMPAIGN_FAMILY_MAP" scripts/bigquery cube tools | grep -v "\.bak"
for v in V_PANEL_OWNERSHIP V_CAMPAIGN_HALO V_BUDGET_STEP1_CAMPAIGN V_BUDGET_STEP1_FAMILY \
         V_CAMPAIGN_BUDGET_BASE V_CHANGE_SCORECARD V_HOLDOUT_ELIGIBLE V_DIM_CAMPAIGN_FAMILY \
         V_LOW_STOCK_ADS V_LAUNCH_EXEMPTION V_FAMILY_NET_PROFIT_7D V_TWO_BOOK_BRIEF \
         V_BOOK_ASSIGNMENT V_FAMILY_BAR; do
  bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --dry_run \
    "SELECT 1 FROM \`onyga-482313.OI.$v\` LIMIT 0" >/dev/null 2>&1 \
    && echo "OK   $v" || echo "FAIL $v"
done
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT COUNT(*) rows_, COUNT(DISTINCT campaign_id) campaigns,
       COUNT(*) - COUNT(DISTINCT campaign_id) AS single_home_claim_broken
FROM \`onyga-482313.OI.V_PANEL_OWNERSHIP\`"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/BUDGET_WATERFALL_INVARIANTS.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_ENGINE_PREFLIGHT\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT (SELECT COUNT(*) FROM \`onyga-482313.OI.FACT_ENGINE_PROPOSALS\`
        WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_ENGINE_PROPOSALS\`)
          AND hold_source IS NULL) AS proposals,
       (SELECT COUNT(*) FROM \`onyga-482313.OI.T_ENGINE_PREFLIGHT\`) AS preflight_rows"
```

Expected: `OK` on every view; `single_home_claim_broken = 0`; every invariant row `PASS`; and
`preflight_rows = proposals`. **`single_home_claim_broken > 0` is a stop-the-line result** — widening
the map has given a campaign two panel homes, `SP_ENGINE_PREFLIGHT`'s defensive `GROUP BY` is now
load-bearing rather than defensive, and the ownership snapshot must be fixed before anything else in
Phase 4 proceeds.

**One deliberate side effect to look at, not to fix here.** Widening the learning window to all
history re-arms the name-prefix learning corpus with archived campaigns, which cuts against Task
3.5's demotion of the prefix arm. Task 4.3's disagreement measurement is where that shows up; if the
three family definitions diverge *more* after this change than before it, that is the prefix arm
talking and Task 4.3 is the task that rules on it.

- [ ] **Step 7: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_CAMPAIGN_FAMILY_MAP.sql
git commit -m "feat(catalog): the family map covers every campaign over all ads history

Hard prerequisite for any seasonal or campaign-grain verdict. T_FAMILY_BAR held
exactly the 90 ENABLED campaigns while 100% of holiday-2024 spend and 31.8% of
holiday-2025 belonged to campaigns with no family. The bar computation is
unchanged; only the population it covers is."
```

---

### Task 4.3: Reconcile the three family definitions before publishing a campaign family

**Files:**
- Modify: `scripts/bigquery/tests/CAMPAIGN_IDENTITY_acceptance.sql` (add one check)

Three different definitions are live: `V_KEYWORD_GUARD.sql:140-148` (dominant parent by lifetime spend via `ASIN_BY_CAMPAIGN_NAME`, and its own header says explicitly this is **not** `V_DIM_CAMPAIGN_FAMILY`); `SP_SNAPSHOT_FAMILY_BAR.sql:64` (`V_CAMPAIGN_FAMILY_MAP`); and `SP_SNAPSHOT_KEYWORD_STATE.sql:306`'s `COALESCE(fb.family, po.family)` — a third precedence. A campaign verdict must say which one it means.

- [ ] **Step 1: Measure the disagreement**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH g AS (SELECT DISTINCT CAST(campaign_id AS STRING) cid, parent_name AS guard_family
           FROM \`onyga-482313.OI.V_KEYWORD_GUARD\` WHERE parent_name IS NOT NULL),
m AS (SELECT CAST(campaign_id AS STRING) cid, parent_name AS map_family
      FROM \`onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP\` WHERE parent_name != 'Unknown')
SELECT COUNTIF(g.guard_family != m.map_family) AS campaigns_where_the_two_disagree,
       COUNT(*) AS campaigns_both_resolve
FROM g JOIN m USING (cid)"
```

Record the number. It does not have to be zero — the two definitions answer different questions — but it must be **known**, and the campaign verdict must name which it uses.

- [ ] **Step 2: Add the reconciliation check**

Append a sixth CTE to `scripts/bigquery/tests/CAMPAIGN_IDENTITY_acceptance.sql` and add it to the final UNION:

```sql
,
-- I06: the campaign verdict means V_CAMPAIGN_FAMILY_MAP's family, because that is what
-- T_FAMILY_BAR is exploded from and therefore what the bar the verdict is judged against belongs
-- to. V_KEYWORD_GUARD's parent_name answers a different question (dominant advertised parent over
-- full history, for the lifetime and last-year pools) and its own header says so. This check does
-- not force them to agree — it forces the DISAGREEMENT TO BE VISIBLE, so a silent divergence
-- cannot grow. Raise the threshold deliberately, with the measurement, never by accident.
i06 AS (
  SELECT 'I06 the campaign family the verdict uses is published and its source is named',
         (SELECT COUNTIF(parent_name IS NULL OR resolution_source IS NULL)
          FROM `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP`)
)
```

- [ ] **Step 3: Run and commit**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/CAMPAIGN_IDENTITY_acceptance.sql)"
git add scripts/bigquery/tests/CAMPAIGN_IDENTITY_acceptance.sql
git commit -m "test(catalog): the campaign family the verdict uses names its source"
```

Expected: six rows, all `PASS`.

---

### Task 4.4: `FACT_CAMPAIGN_STATE`

**Files:**
- Create: `scripts/bigquery/tables/FACT_CAMPAIGN_STATE.sql`

**History from day one** — apply Phase 0's lesson rather than repeating violation 6 at a new grain.

- [ ] **Step 1: Write the DDL**

```sql
-- =============================================================================================
-- FACT_CAMPAIGN_STATE — the Catalog's answer for a CAMPAIGN subject (architecture/THREE_LAYERS.md
-- 2.1, 4.1). One row per (snapshot_date, campaign_id).
--
-- WHY A CAMPAIGN IS A SUBJECT. A seasonal campaign is NOT_WORTH_NOW in the summer and WORTH in
-- November, exactly like a seasonal keyword, and no layer had a verdict for it at all. Measured
-- 2026-08-24: ten paused campaigns carry 2,826 orders and $127,352 of last-season sales at a pooled
-- 1.49 GP-ROAS, five stopped on a single day in mid-July, and nothing anywhere holds a reopen date
-- for any of them.
--
-- THE ASYMMETRY THAT SHAPES THE TABLE: a campaign has no park. A keyword can sit at its floor,
-- visible and re-judgeable; a campaign is on or off. So the only expression of NOT_WORTH_NOW at
-- this grain is a pause — the one irreversible action the doctrine permits on something other than
-- NOT_WORTH, and only on condition it CARRIES ITS REOPEN DATE. reopen_date is that condition,
-- recorded where a layer acts on it rather than remembered by a person.
--
-- LEAD TIME IS PART OF THE ANSWER, not an afterthought: a campaign enabled on the first day of its
-- season has not been running when the season starts. lead_time_days is how long it needs to
-- re-accumulate signal, and window_from / window_to are the REQUESTED window, which is what lets a
-- November answer be computed in October.
--
-- HISTORY FROM DAY ONE: partitioned on snapshot_date and never replaced, so this grain does not
-- repeat violation 6. The procedure writes DELETE-today-then-INSERT.
--
-- ADDING A COLUMN: CREATE TABLE IF NOT EXISTS is a silent no-op against an existing table, so every
-- new column arrives as an explicit ALTER TABLE ADD COLUMN IF NOT EXISTS line at the foot of this
-- file, in the same commit as the code that writes it.
-- =============================================================================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_CAMPAIGN_STATE`
(
  snapshot_date       DATE    NOT NULL,
  campaign_id         STRING  NOT NULL,
  campaign_name       STRING,
  campaign_state      STRING,
  campaign_type       STRING,
  family              STRING,
  family_source       STRING,
  family_is_name_derived BOOL,
  book                STRING,
  campaign_bar        FLOAT64,
  bar_exempt          BOOL,
  bar_missing         BOOL,

  -- the requested window this row answers for (4: the Catalog answers for a REQUESTED window)
  window_from         DATE,
  window_to           DATE,
  window_label        STRING,

  -- id-keyed evidence. m1/m3/y1 are trailing 28 / 91 / 365 complete days; season_* is the
  -- occurrence of the same calendar window one year back, resolved from DIM_US_HOLIDAYS.
  m1_clicks           INT64,
  m1_spend            FLOAT64,
  m1_orders           INT64,
  m1_gp               FLOAT64,
  m3_clicks           INT64,
  m3_spend            FLOAT64,
  m3_orders           INT64,
  m3_gp               FLOAT64,
  y1_clicks           INT64,
  y1_spend            FLOAT64,
  y1_orders           INT64,
  y1_gp               FLOAT64,
  season_from         DATE,
  season_to           DATE,
  season_clicks       INT64,
  season_spend        FLOAT64,
  season_orders       INT64,
  season_gp           FLOAT64,
  season_gp_roas      FLOAT64,

  -- the answer
  verdict             STRING,
  verdict_reason      STRING,
  lead_time_days      INT64,
  reopen_date         DATE,
  state_reason        STRING,
  built_at            TIMESTAMP
)
PARTITION BY snapshot_date
CLUSTER BY campaign_id
;

ALTER TABLE `onyga-482313.OI.FACT_CAMPAIGN_STATE` SET OPTIONS(description =
  "The Catalog's answer for a CAMPAIGN subject: one row per (snapshot_date, campaign_id), carrying the family and its bar, id-keyed evidence over trailing 28/91/365 complete days and the same calendar window one year back, and a verdict for the REQUESTED window (window_from, window_to). Exists because architecture/THREE_LAYERS.md 4.1 makes a campaign a seasonal subject and nothing had a verdict for one. A campaign has no park, so a CLOSE is the one irreversible action permitted on NOT_WORTH_NOW, and only on condition it carries reopen_date. lead_time_days is how long the campaign needs to re-accumulate signal before its window opens, which is why a November answer must be computable in October. Partitioned on snapshot_date and never replaced, so this grain does not repeat violation 6. Written by SP_SNAPSHOT_CAMPAIGN_STATE, DELETE-today-then-INSERT.");
```

- [ ] **Step 2: Deploy and check the shape**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tables/FACT_CAMPAIGN_STATE.sql)"
bq show --format=prettyjson onyga-482313:OI.FACT_CAMPAIGN_STATE \
  | /usr/local/bin/python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['schema']['fields']),'columns;',d.get('timePartitioning'),d.get('clustering'))"
```

Expected: `47 columns; {'type': 'DAY', 'field': 'snapshot_date'} {'fields': ['campaign_id']}`.

- [ ] **Step 3: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/tables/FACT_CAMPAIGN_STATE.sql
git commit -m "feat(catalog): FACT_CAMPAIGN_STATE — a campaign is a subject with a verdict

Partitioned and never replaced, so the new grain does not repeat violation 6."
```

---

### Task 4.5: `SP_SNAPSHOT_CAMPAIGN_STATE`

**Files:**
- Create: `scripts/bigquery/procedures/SP_SNAPSHOT_CAMPAIGN_STATE.sql`
- Modify: `config.yaml` (`stored_procedures:` section)

- [ ] **Step 1: Write the procedure**

```sql
-- =============================================================================================
-- SP_SNAPSHOT_CAMPAIGN_STATE — the campaign verdict (architecture/THREE_LAYERS.md 4.1).
--
-- POSITION IN THE NIGHTLY PASS, STATED EXPLICITLY:
--   * AFTER task 20.5g-1 (SP_SNAPSHOT_FAMILY_BAR), because the campaign bar comes from T_FAMILY_BAR
--     and that snapshot must stay ahead of every reader or a verdict is judged against yesterday's
--     halo with no error and no alarm.
--   * BEFORE task 20.8c (SP_BUILD_NEXT_WEEK_PLAN), because the Brain's OPEN intent reads this row.
--   * The ORDER RELATIVE TO 20.7 (SP_ENGINE_PREFLIGHT) DOES NOT MATTER and is not changed: the
--     preflight is keyword-grain and reads nothing here. The known one-pass lag between 20.6/20.7
--     and 20.8 is left exactly as it is — closing it means moving another owner's tasks and is an
--     open ruling for Ori.
--
-- IDEMPOTENT: DELETE-today-then-INSERT, and every temp table is CREATE OR REPLACE TEMP TABLE,
-- because the orchestrator may call this twice in one pass (house rule after the 2026-08-24 cube
-- outage).
--
-- WHAT IT DOES NOT DO YET: it issues OPEN and never CLOSE. A campaign has no park, so a CLOSE is a
-- new irreversible action, and doctrine 5 forbids one below HIGH confidence — which is not computed
-- anywhere until Phase 7 of the gap-closure plan. The CLOSE arm is added there, gated.
--
-- BUT EVERY ANSWERABLE VERDICT ALREADY CARRIES ITS DATE, from tonight. NOT_WORTH_NOW without a
-- reopen date would BE the one-way door 4.1 describes even with no CLOSE intent published, because
-- nothing would ever bring the campaign back into the question. The date is the answer; the intent
-- is only what Pacing does with it.
-- =============================================================================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SNAPSHOT_CAMPAIGN_STATE`()
OPTIONS (
  description = "The Catalog's campaign-grain verdict, written to FACT_CAMPAIGN_STATE one row per (snapshot_date, campaign_id). Reads V_CAMPAIGN_IDENTITY for id-keyed history, T_FAMILY_BAR for the bar, DIM_US_HOLIDAYS for the season window and V_CAMPAIGN_FAMILY_MAP for the family. Answers for a REQUESTED window (window_from, window_to), defaulting to the next season occurrence, so a November answer is computable in October; lead_time_days is how long the campaign needs to re-accumulate signal before that window opens. Issues WORTH / NOT_WORTH_NOW / UNKNOWN, and every one of the first two carries a date: an OPEN date on WORTH, a re-ask date on NOT_WORTH_NOW, both with lead time already subtracted. It does not yet issue the CLOSE intent: a campaign has no park, so a close is a new irreversible action and doctrine 5 requires HIGH confidence, which is not computed until the confidence phase. DELETE-today-then-INSERT. Runs in SP_ORCHESTRATE_DAILY_REFRESH after task 20.5g-1 and before 20.8c. Spec: architecture/THREE_LAYERS.md 4.1."
)
BEGIN
  DECLARE snap DATE DEFAULT CURRENT_DATE('America/Los_Angeles');

  -- the ads watermark, and the complete-days fence: the filling day never enters a window
  CREATE OR REPLACE TEMP TABLE wm AS
  SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`;

  -- THE REQUESTED WINDOW. Default: the next holiday occurrence whose peak has not yet started,
  -- from boost_start to cooldown_end (or peak_start + 3 days where no cooldown is set — the same
  -- fallback FN_PLAN_CALENDAR_STATE uses). A caller who wants a different window overrides it via
  -- DE_CATALOG_WINDOW_REQUEST, added in Phase 5; until then this is the only window asked for.
  CREATE OR REPLACE TEMP TABLE req AS
  SELECT
    COALESCE(MIN(h.boost_start), DATE_ADD((SELECT d FROM wm), INTERVAL 1 DAY))  AS window_from,
    COALESCE(MIN(COALESCE(h.cooldown_end, DATE_ADD(h.peak_start, INTERVAL 3 DAY))),
             DATE_ADD((SELECT d FROM wm), INTERVAL 28 DAY))                     AS window_to,
    COALESCE(MIN(h.holiday_name), 'next 28 days')                               AS window_label
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
  WHERE h.peak_start IS NOT NULL
    AND h.peak_start > (SELECT d FROM wm)
    AND h.peak_start = (SELECT MIN(peak_start) FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
                        WHERE peak_start > (SELECT d FROM wm));

  -- id-keyed evidence, all windows in one scan
  CREATE OR REPLACE TEMP TABLE ev AS
  SELECT
    CAST(a.campaign_id AS STRING) AS cid,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 28 DAY)
                      AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_clicks, 0)) AS m1_clicks,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 28 DAY)
                      AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_cost, 0))   AS m1_spend,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 28 DAY)
                      AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_orders, 0)) AS m1_orders,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 28 DAY)
                      AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.GROSS_PROFIT, 0)) AS m1_gp,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 91 DAY)
                      AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_clicks, 0)) AS m3_clicks,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 91 DAY)
                      AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_cost, 0))   AS m3_spend,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 91 DAY)
                      AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_orders, 0)) AS m3_orders,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 91 DAY)
                      AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.GROSS_PROFIT, 0)) AS m3_gp,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 365 DAY)
                      AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_clicks, 0)) AS y1_clicks,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 365 DAY)
                      AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_cost, 0))   AS y1_spend,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 365 DAY)
                      AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_orders, 0)) AS y1_orders,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 365 DAY)
                      AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.GROSS_PROFIT, 0)) AS y1_gp,
    -- LAST YEAR'S SAME WINDOW — the evidence a seasonal verdict actually needs
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT window_from FROM req), INTERVAL 364 DAY)
                      AND DATE_SUB((SELECT window_to   FROM req), INTERVAL 364 DAY), a.Ads_clicks, 0)) AS season_clicks,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT window_from FROM req), INTERVAL 364 DAY)
                      AND DATE_SUB((SELECT window_to   FROM req), INTERVAL 364 DAY), a.Ads_cost, 0))   AS season_spend,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT window_from FROM req), INTERVAL 364 DAY)
                      AND DATE_SUB((SELECT window_to   FROM req), INTERVAL 364 DAY), a.Ads_orders, 0)) AS season_orders,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT window_from FROM req), INTERVAL 364 DAY)
                      AND DATE_SUB((SELECT window_to   FROM req), INTERVAL 364 DAY), a.GROSS_PROFIT, 0)) AS season_gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  WHERE a.campaign_id IS NOT NULL
    AND a.date <= DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY)
  GROUP BY 1;

  -- the campaign bar: one row per campaign, from the nightly T_FAMILY_BAR snapshot
  CREATE OR REPLACE TEMP TABLE bar AS
  SELECT CAST(campaign_id AS STRING) AS cid,
         ANY_VALUE(family) AS family, ANY_VALUE(book) AS book,
         ANY_VALUE(keyword_bar) AS campaign_bar, ANY_VALUE(bar_exempt) AS bar_exempt
  FROM `onyga-482313.OI.T_FAMILY_BAR`
  GROUP BY 1;

  DELETE FROM `onyga-482313.OI.FACT_CAMPAIGN_STATE` WHERE snapshot_date = snap;

  INSERT INTO `onyga-482313.OI.FACT_CAMPAIGN_STATE`
  SELECT
    snap                                                              AS snapshot_date,
    ci.campaign_id,
    ci.current_name                                                   AS campaign_name,
    ci.campaign_state,
    ci.campaign_type,
    COALESCE(bar.family, fm.parent_name)                              AS family,
    fm.resolution_source                                              AS family_source,
    COALESCE(fm.family_is_name_derived, FALSE)                        AS family_is_name_derived,
    bar.book,
    bar.campaign_bar,
    COALESCE(bar.bar_exempt, FALSE)                                   AS bar_exempt,
    (bar.campaign_bar IS NULL)                                        AS bar_missing,

    r.window_from, r.window_to, r.window_label,

    COALESCE(ev.m1_clicks, 0), COALESCE(ev.m1_spend, 0.0),
    COALESCE(ev.m1_orders, 0), COALESCE(ev.m1_gp, 0.0),
    COALESCE(ev.m3_clicks, 0), COALESCE(ev.m3_spend, 0.0),
    COALESCE(ev.m3_orders, 0), COALESCE(ev.m3_gp, 0.0),
    COALESCE(ev.y1_clicks, 0), COALESCE(ev.y1_spend, 0.0),
    COALESCE(ev.y1_orders, 0), COALESCE(ev.y1_gp, 0.0),
    DATE_SUB(r.window_from, INTERVAL 364 DAY)                         AS season_from,
    DATE_SUB(r.window_to,   INTERVAL 364 DAY)                         AS season_to,
    COALESCE(ev.season_clicks, 0), COALESCE(ev.season_spend, 0.0),
    COALESCE(ev.season_orders, 0), COALESCE(ev.season_gp, 0.0),
    SAFE_DIVIDE(ev.season_gp, NULLIF(ev.season_spend, 0))             AS season_gp_roas,

    -- ── THE VERDICT. First-match, and every arm is one of doctrine 4's three, never a command.
    CASE
      -- no evidence in the requested window's own season, and none recently: we do not know.
      WHEN COALESCE(ev.season_spend, 0) = 0 AND COALESCE(ev.m3_spend, 0) = 0 THEN 'UNKNOWN'
      -- it earned in this same window last year, above the bar it is judged against.
      WHEN COALESCE(ev.season_spend, 0) > 0
       AND SAFE_DIVIDE(ev.season_gp, ev.season_spend) >= COALESCE(bar.campaign_bar, 1.0)
        THEN 'WORTH'
      -- it earned last season and is quiet now: dormant, not dead. The distinction doctrine 4 calls
      -- the single most expensive mistake it exists to prevent.
      WHEN COALESCE(ev.season_spend, 0) > 0 AND COALESCE(ev.m1_spend, 0) = 0 THEN 'NOT_WORTH_NOW'
      -- it is spending now and returning under its bar over a full quarter.
      WHEN COALESCE(ev.m3_spend, 0) > 0
       AND SAFE_DIVIDE(ev.m3_gp, ev.m3_spend) < COALESCE(bar.campaign_bar, 1.0)
        THEN 'NOT_WORTH_NOW'
      ELSE 'UNKNOWN'
    END                                                               AS verdict,

    CASE
      WHEN COALESCE(ev.season_spend, 0) = 0 AND COALESCE(ev.m3_spend, 0) = 0
        THEN 'no spend in this window last year and none in the last quarter — nothing here says whether it is worth running'
      WHEN COALESCE(ev.season_spend, 0) > 0
       AND SAFE_DIVIDE(ev.season_gp, ev.season_spend) >= COALESCE(bar.campaign_bar, 1.0)
        THEN FORMAT('in this same window last year it returned %.2f gross-profit dollars per ad dollar on $%.0f of spend, against a bar of %.2f',
                    SAFE_DIVIDE(ev.season_gp, ev.season_spend), ev.season_spend,
                    COALESCE(bar.campaign_bar, 1.0))
      WHEN COALESCE(ev.season_spend, 0) > 0 AND COALESCE(ev.m1_spend, 0) = 0
        THEN FORMAT('it spent $%.0f in this window last year and nothing in the last 28 days — dormant, which is not the same as dead',
                    ev.season_spend)
      ELSE FORMAT('over the last quarter it returned %.2f per ad dollar on $%.0f, under its bar of %.2f',
                  COALESCE(SAFE_DIVIDE(ev.m3_gp, ev.m3_spend), 0), COALESCE(ev.m3_spend, 0),
                  COALESCE(bar.campaign_bar, 1.0))
    END                                                               AS verdict_reason,

    -- LEAD TIME. A campaign enabled on day one of its season has not been running when the season
    -- starts. 14 days is the house's settle span for SB and the longest any channel needs to
    -- re-accumulate the signal Amazon prices on; a campaign that never spent needs the same.
    14                                                                AS lead_time_days,

    -- THE DATE, and it is the whole point of the row: recorded where a layer acts on it, never
    -- remembered by a person.
    --   * On WORTH it is the OPEN date — the window's start with the lead time already subtracted.
    --   * On NOT_WORTH_NOW it is the RE-ASK date, and it is not optional. 4.1: "a campaign has no
    --     park", so the only expression of NOT_WORTH_NOW at this grain is a pause, and "a seasonal
    --     close carries its reopen date. A close without a reopen date is the one-way door of 5
    --     wearing different clothes." A NOT_WORTH_NOW row with no date IS that door: nothing would
    --     ever bring the campaign back, which is precisely the state the doctrine measured — ten
    --     paused campaigns, $127,352 of last-season sales, and not one reopen date anywhere.
    --     It is the same lead-time-adjusted open date, because the question "is it worth running"
    --     must be re-asked when the window is next in front of us, not on a rolling clock.
    -- UNKNOWN carries none: there is nothing to come back to.
    CASE
      WHEN COALESCE(ev.season_spend, 0) = 0 AND COALESCE(ev.m3_spend, 0) = 0 THEN NULL
      ELSE DATE_SUB(r.window_from, INTERVAL 14 DAY)
    END                                                               AS reopen_date,

    FORMAT('%s for %s (%t to %t). %s',
           CASE
             WHEN COALESCE(ev.season_spend, 0) = 0 AND COALESCE(ev.m3_spend, 0) = 0 THEN 'UNKNOWN'
             WHEN COALESCE(ev.season_spend, 0) > 0
              AND SAFE_DIVIDE(ev.season_gp, ev.season_spend) >= COALESCE(bar.campaign_bar, 1.0)
               THEN 'WORTH RUNNING'
             ELSE 'NOT WORTH RUNNING NOW' END,
           r.window_label, r.window_from, r.window_to,
           IF(ci.campaign_state = 'ENABLED', 'It is running today.',
              'It is paused today.'))                                 AS state_reason,
    CURRENT_TIMESTAMP()                                               AS built_at
  FROM `onyga-482313.OI.V_CAMPAIGN_IDENTITY` ci
  CROSS JOIN req r
  LEFT JOIN ev  ON ev.cid = ci.campaign_id
  LEFT JOIN bar ON bar.cid = ci.campaign_id
  LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` fm ON fm.campaign_id = ci.campaign_id;

  -- doctrine 4.1: a close carries its reopen date — and NOT_WORTH_NOW is a close at this grain,
  -- because a campaign has no park. The assertion therefore covers BOTH answerable verdicts from
  -- the day this procedure ships, not only the NOT_WORTH one Phase 7 adds. Writing it narrowly
  -- would have let every dormant seasonal campaign carry no date at all and still read green.
  ASSERT (SELECT COUNTIF(verdict IN ('WORTH', 'NOT_WORTH_NOW', 'NOT_WORTH') AND reopen_date IS NULL)
          FROM `onyga-482313.OI.FACT_CAMPAIGN_STATE` WHERE snapshot_date = snap) = 0
    AS 'every answerable campaign verdict carries its date — an open date or a re-ask date (4.1)';
END;
```

- [ ] **Step 2: Deploy, run twice, verify idempotency and the grain**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_CAMPAIGN_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_CAMPAIGN_STATE\`();
   CALL \`onyga-482313.OI.SP_SNAPSHOT_CAMPAIGN_STATE\`();"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT verdict, campaign_state, COUNT(*) n,
       COUNTIF(reopen_date IS NOT NULL) with_reopen_date,
       ROUND(SUM(season_spend), 0) usd_last_season
FROM \`onyga-482313.OI.FACT_CAMPAIGN_STATE\`
WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_CAMPAIGN_STATE\`)
GROUP BY 1,2 ORDER BY n DESC"
```

Expected: one partition, one row per campaign, **every `WORTH` and every `NOT_WORTH_NOW` row carrying
a `reopen_date`** (`UNKNOWN` carries none, correctly — there is nothing to come back to), and paused
campaigns with real last-season money appearing as `WORTH` — that is the $127,352 the doctrine
measured, now with a date on it. A `NOT_WORTH_NOW` row with a null date means the `CASE` was written
on the WORTH branch only; the `ASSERT` at the foot will have aborted the run before the row landed.

- [ ] **Step 3: Register both objects in `config.yaml`**

Insert two entries in `stored_procedures:` next to `SP_SNAPSHOT_FAMILY_BAR`:

```yaml
  - name: SP_SNAPSHOT_CAMPAIGN_STATE
    description: >-
      Writes FACT_CAMPAIGN_STATE, the Catalog's campaign-grain verdict, one row per (snapshot_date,
      campaign_id). Reads V_CAMPAIGN_IDENTITY for id-keyed history, T_FAMILY_BAR for the bar,
      V_CAMPAIGN_FAMILY_MAP for the family and DIM_US_HOLIDAYS for the requested season window.
      Issues WORTH / NOT_WORTH_NOW / UNKNOWN. Every WORTH row carries an OPEN date and every
      NOT_WORTH_NOW row a re-ask date, both with lead time already subtracted, because 4.1 makes a
      campaign pause a close and a close without a reopen date is 5's one-way door. It does not yet
      issue the CLOSE intent: a campaign has no park, so a close is a new irreversible action and
      doctrine 5 requires HIGH confidence. Runs after task 20.5g-1 and before 20.8c.
      DELETE-today-then-INSERT; every temp table is CREATE OR REPLACE TEMP TABLE.
    source_files:
      - scripts/bigquery/procedures/SP_SNAPSHOT_CAMPAIGN_STATE.sql
    dependencies:
      - V_CAMPAIGN_IDENTITY
      - T_FAMILY_BAR
      - V_CAMPAIGN_FAMILY_MAP
      - DIM_US_HOLIDAYS
      - FACT_AMAZON_ADS
  - name: FACT_CAMPAIGN_STATE
    description: >-
      The Catalog's answer for a campaign subject: family, bar, id-keyed evidence over trailing
      28/91/365 complete days and the same calendar window one year back, a verdict for the
      requested window, a lead time and a reopen date. Partitioned on snapshot_date and never
      replaced, so this grain keeps its own history from day one.
    source_files:
      - scripts/bigquery/procedures/SP_SNAPSHOT_CAMPAIGN_STATE.sql
      - scripts/bigquery/tables/FACT_CAMPAIGN_STATE.sql
    dependencies:
      - V_CAMPAIGN_IDENTITY
```

- [ ] **Step 4: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/procedures/SP_SNAPSHOT_CAMPAIGN_STATE.sql config.yaml
git commit -m "feat(catalog): SP_SNAPSHOT_CAMPAIGN_STATE — the campaign verdict, OPEN arm only

Closes the OPEN half of violation 22. WORTH carries a reopen date with lead time
already subtracted, so the reopen lives where a layer acts on it. CLOSE is
withheld until confidence exists (doctrine 5)."
```

---

### Task 4.6: The orchestrator slot

**Files:**
- Modify: `scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql` (a new task between 20.5g-1 and 20.6)

- [ ] **Step 1: Back up**

```bash
cd /Users/ori/Develop/OI
NEXT=$(ls scripts/bigquery/**/*.bak.v27.*.* 2>/dev/null | sed -E 's/.*\.bak\.v27\.([0-9]+)\..*/\1/' | sort -n | tail -1)
NEXT=$((NEXT + 1))
cp scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql \
   scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql.bak.v27.$NEXT.$(date +%H%M)
```

- [ ] **Step 2: Insert the task immediately after the `SP_SNAPSHOT_FAMILY_BAR` block ends**

Locate the end of the `SP_SNAPSHOT_FAMILY_BAR` `BEGIN ... END;` block (its `EXCEPTION WHEN ERROR THEN` handler closes with `END;`). Insert directly below it:

```sql

  -- ============================================
  -- Refresh Task 20.5g-2 (2026-08-25, three-layers gap closure Phase 4): the CAMPAIGN verdict.
  -- Writes today's partition of FACT_CAMPAIGN_STATE — one row per campaign, a family and its bar,
  -- id-keyed evidence over trailing 28/91/365 complete days and the same calendar window one year
  -- back, a verdict for the requested season window, and on WORTH an OPEN date with lead time
  -- already subtracted.
  -- ORDER, EXPLICITLY: it MUST run after 20.5g-1 (SP_SNAPSHOT_FAMILY_BAR), because the campaign bar
  -- comes from T_FAMILY_BAR and that snapshot must stay ahead of every reader or a verdict is
  -- judged against yesterday's halo with no error and no alarm. It MUST run before 20.8c
  -- (SP_BUILD_NEXT_WEEK_PLAN), which reads the OPEN intent. Its order relative to 20.6 and 20.7 is
  -- IRRELEVANT — those are keyword-grain and read nothing here — and the known one-pass lag between
  -- them and 20.8 is deliberately NOT changed by this task.
  -- Spec: architecture/THREE_LAYERS.md 4.1.
  -- ============================================
  SET procedure_name = 'SP_SNAPSHOT_CAMPAIGN_STATE';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_SNAPSHOT_CAMPAIGN_STATE`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;

```

- [ ] **Step 3: Deploy and run one full pass**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_ORCHESTRATE_DAILY_REFRESH\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT procedure_name, status, duration_seconds
FROM \`onyga-482313.OI.LOG_PIPELINE_RUNS\`
WHERE run_date = CURRENT_DATE()
  AND procedure_name IN ('SP_SNAPSHOT_FAMILY_BAR','SP_SNAPSHOT_CAMPAIGN_STATE','SP_BUILD_NEXT_WEEK_PLAN')
ORDER BY started_at"
```

Expected: three rows in that order, every `status` reading `OK`. If any reads `FAIL`, read `error_message` — a failure here is contained by the `EXCEPTION` handler and leaves the previous partition standing, but the pass must be green before Phase 5 builds on it.

- [ ] **Step 4: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql
git commit -m "feat(orchestrator): task 20.5g-2 builds the campaign verdict nightly

After 20.5g-1 so the bar is current, before 20.8c which reads the OPEN intent.
The known 20.6/20.7 lag is untouched — that is an open ruling for Ori."
```

---

### Task 4.7: `build_campaign_reopen_bulksheet.py` and its restore generator

**Files:**
- Create: `tools/build_campaign_reopen_bulksheet.py`
- Create: `tools/build_restore_campaign_reopen_bulksheet.py`
- Modify: `tools/tests/test_change_log_discipline.py` (add both to `BOOKS`)

- [ ] **Step 1: Write the failing test first**

In `tools/tests/test_change_log_discipline.py`, change the `BOOKS` list to include the new generator:

```python
import build_campaign_reopen_bulksheet as reopen  # noqa: E402

# Every book that writes a row into FACT_PPC_CHANGE_LOG obeys the same discipline, so every book is
# parametrised here. The campaign reopen book (2026-08-25, three-layers Phase 4) joined the day it
# was written: it enables a campaign the Catalog says is worth running for the coming window, and
# it labels and lists exactly like its siblings.
BOOKS = [leak, reprice, unpause, reopen]
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd /Users/ori/Develop/OI
/usr/local/bin/python3 -m pytest tools/tests/test_change_log_discipline.py -q
```

Expected: FAIL at import — `ModuleNotFoundError: No module named 'build_campaign_reopen_bulksheet'`.

- [ ] **Step 3: Write the generator**

```python
#!/usr/bin/env python3
"""CAMPAIGN REOPEN BOOK — enable the campaigns the Catalog says are worth running for the window.

architecture/THREE_LAYERS.md 4.1: a campaign is a seasonal subject, and the Brain's OPEN intent is
"the Catalog says this campaign is worth running in the coming window — enable it with enough lead
time to re-learn before the window opens". Measured 2026-08-24: ten paused campaigns carried 2,826
orders and $127,352 of last-season sales at a pooled 1.49 GP-ROAS, and NOT ONE held a reopen date.

WHAT THIS BOOK DOES. It reads FACT_CAMPAIGN_STATE for rows whose verdict is WORTH, whose campaign is
not currently ENABLED, and whose reopen_date has arrived — the date the verdict itself computed, with
the lead time already subtracted. It emits one Amazon bulksheet Campaign row per campaign setting
State to enabled, writes the same rows into FACT_PPC_CHANGE_LOG as PENDING_UPLOAD, and prints a
README naming the Catalog's evidence for every line.

NEVER UPLOADED BY THIS SCRIPT. The book is for Ori. --mark-uploaded flips a batch to applied once he
has uploaded it; --supersede labels a batch that never will be. Both act on PENDING_UPLOAD rows only,
and no code path here issues a DELETE against the change log.

THE BLANK PORTFOLIO TRAP. On a Campaign Update row a BLANK Portfolio ID is not "unchanged" — Amazon
reads it as a detach. Every row below echoes the campaign's current portfolio_id, from
V_CAMPAIGN_IDENTITY, rather than leaving the cell empty.
"""
import argparse
import json
import os
import subprocess
import sys
from datetime import date, datetime, timezone

import openpyxl

PROJECT = 'onyga-482313'

# THE CHANGE LOG, in the house shape every other book already uses. It is NOT an environment
# variable: tools/tests/test_change_log_discipline.py::test_a_change_log_override_must_be_a_tmp_copy
# calls set_change_log_table() and reads LIVE_CHANGE_LOG by name on every book in BOOKS, and an
# os.environ override carries no TMP_/TEMP_ guard at all — so the one thing that test exists to
# constrain would be unconstrained. Copy this block verbatim from
# tools/build_reprice_bulksheet.py:118-133; do not paraphrase it.
LIVE_CHANGE_LOG = "FACT_PPC_CHANGE_LOG"
CHANGE_LOG = f"{PROJECT}.OI.{LIVE_CHANGE_LOG}"


def set_change_log_table(table):
    global CHANGE_LOG
    assert table == LIVE_CHANGE_LOG or table.startswith(('TMP_', 'TEMP_')), \
        f"{table}: a change-log override must be a TMP_/TEMP_ copy — never another live table"
    CHANGE_LOG = f"{PROJECT}.OI.{table}"
    return CHANGE_LOG

# Amazon's Sponsored Products campaign-row headers, in the order the bulk template expects them.
CAMPAIGN_HEADERS = [
    'Product', 'Entity', 'Operation', 'Campaign ID', 'Campaign Name', 'Portfolio ID',
    'Start Date', 'End Date', 'Targeting Type', 'State', 'Daily Budget',
    'Bidding Strategy',
]


def q(v):
    """A SQL string literal, or NULL."""
    if v is None:
        return 'NULL'
    return "'" + str(v).replace('\\', '\\\\').replace("'", "\\'") + "'"


def bq(sql):
    out = subprocess.run(
        ['bq', 'query', '--use_legacy_sql=false', '--nouse_cache', '--format=json',
         f'--project_id={PROJECT}', sql],
        capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f'query failed:\n{out.stderr}')
    return json.loads(out.stdout or '[]')


def run_update(sql, what):
    out = subprocess.run(
        ['bq', 'query', '--use_legacy_sql=false', '--nouse_cache', f'--project_id={PROJECT}', sql],
        capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f'{what} failed:\n{out.stderr}')


def candidates_sql():
    """Campaigns the Catalog says are WORTH for the requested window, not currently enabled, whose
    reopen date has arrived."""
    return f"""
SELECT cs.campaign_id, cs.campaign_name, cs.family, cs.campaign_bar,
       cs.window_from, cs.window_to, cs.window_label,
       cs.season_spend, cs.season_gp, cs.season_orders, cs.season_gp_roas,
       cs.reopen_date, cs.lead_time_days, cs.verdict_reason,
       ci.portfolio_id, ci.daily_budget, ci.campaign_type,
       ci.name_changed_count
FROM `{PROJECT}.OI.FACT_CAMPAIGN_STATE` cs
JOIN `{PROJECT}.OI.V_CAMPAIGN_IDENTITY` ci ON ci.campaign_id = cs.campaign_id
WHERE cs.snapshot_date = (SELECT MAX(snapshot_date) FROM `{PROJECT}.OI.FACT_CAMPAIGN_STATE`)
  AND cs.verdict = 'WORTH'
  AND UPPER(COALESCE(cs.campaign_state, '')) != 'ENABLED'
  AND cs.reopen_date IS NOT NULL
  AND cs.reopen_date <= CURRENT_DATE('America/Los_Angeles')
ORDER BY cs.season_gp DESC
"""


def supersede_sql(batch_id, note):
    """A label is written on PENDING_UPLOAD rows only, and nothing is ever deleted."""
    return (f"UPDATE `{CHANGE_LOG}` SET upload_status = 'SUPERSEDED_NEVER_UPLOADED', "
            f"upload_note = {q(note)} "
            f"WHERE batch_id = {q(batch_id)} AND upload_status = 'PENDING_UPLOAD'")


def mark_uploaded_sql(batch_id):
    """PENDING_UPLOAD rows only: NULL is the APPLIED state, so a batch already applied is not
    re-labelled by this statement."""
    return (f"UPDATE `{CHANGE_LOG}` SET upload_status = NULL "
            f"WHERE batch_id = {q(batch_id)} AND upload_status = 'PENDING_UPLOAD'")


def prior_unmarked_batches_sql():
    """Earlier reopen books that are still pending — PENDING_UPLOAD rows only."""
    return (f"SELECT batch_id, COUNT(*) n, MIN(applied_at) built "
            f"FROM `{CHANGE_LOG}` "
            f"WHERE upload_status = 'PENDING_UPLOAD' AND action = 'CAMPAIGN_ENABLE' "
            f"GROUP BY batch_id ORDER BY built")


def log_batch(rows, batch_id, readme_path):
    exists = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` WHERE batch_id = {q(batch_id)}")
    assert int(exists[0]['n']) == 0, f'batch id {batch_id} already exists in the change log'
    note = (f'campaign reopen book {batch_id}, built '
            f'{datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}; '
            f'README {os.path.basename(readme_path)}; manual upload pending — if this book is not '
            f'uploaded set upload_status SUPERSEDED_NEVER_UPLOADED; if uploaded and a line was '
            f'deleted first, set that row FAILED_UPLOAD')
    structs = []
    for r in rows:
        cid = str(r['campaign_id'])
        structs.append(
            'STRUCT('
            f"{q('campreopen-' + batch_id.split('_')[-1] + '-' + cid)} AS change_id, "
            f'{q(batch_id)} AS batch_id, CURRENT_TIMESTAMP() AS applied_at, '
            f"{q('CAMPAIGN_ENABLE')} AS action, "
            f'{q(cid)} AS campaign_id, {q(r["campaign_name"])} AS campaign_name, '
            f'{q((r.get("campaign_type") or "").upper())} AS campaign_type, '
            f"{q('MANUAL')} AS source, {q('MANUAL_BULKSHEET')} AS coach_mode, "
            f'{q(note)} AS upload_note, '
            f"{q('PENDING_UPLOAD')} AS upload_status)")
    cols = ('change_id, batch_id, applied_at, action, campaign_id, campaign_name, campaign_type, '
            'source, coach_mode, upload_note, upload_status')
    sql = (f'INSERT INTO `{CHANGE_LOG}` ({cols}) '
           f"SELECT {cols} FROM UNNEST([{', '.join(structs)}])")
    run_update(sql, 'change-log insert')
    back = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` WHERE batch_id = {q(batch_id)}")
    n_logged = int(back[0]['n'])
    assert n_logged == len(rows), f'logged {n_logged} rows but the sheet holds {len(rows)}'
    return n_logged


def write_sheet(rows, out_path):
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = 'Sponsored Products Campaigns'
    ws.append(CAMPAIGN_HEADERS)
    for r in rows:
        ws.append([
            'Sponsored Products',
            'Campaign',
            'Update',
            str(r['campaign_id']),
            r['campaign_name'],
            # NEVER BLANK: a blank Portfolio ID on a Campaign Update row DETACHES the campaign.
            r.get('portfolio_id') or '',
            '', '', '',
            'enabled',
            r.get('daily_budget') or '',
            '',
        ])
    os.makedirs(os.path.dirname(out_path) or '.', exist_ok=True)
    wb.save(out_path)
    return out_path


def write_readme(rows, batch_id, out_path, readme_path):
    lines = [
        'CAMPAIGN REOPEN BOOK',
        f'batch {batch_id}   built {datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}',
        f'sheet {os.path.basename(out_path)}   {len(rows)} campaign(s)',
        '',
        'WHY THESE CAMPAIGNS, TOP DOWN (architecture/THREE_LAYERS.md 9).',
        '',
    ]
    for r in rows:
        lines += [
            f'* {r["campaign_name"]}  (id {r["campaign_id"]}, family {r.get("family") or "unknown"})',
            f'    CATALOG   worth running for {r["window_label"]} '
            f'({r["window_from"]} to {r["window_to"]}): {r["verdict_reason"]}.',
            f'    BRAIN     OPEN by {r["reopen_date"]} — {r["lead_time_days"]} days of lead time '
            f'before the window opens, so it is running when the season starts and not after it.',
            '    PACING    this sheet sets State to enabled. Its budget and bids are unchanged; '
            'the daily pass prices it from tomorrow.',
        ]
        if int(r.get('name_changed_count') or 0) > 0:
            lines.append('    NOTE      this campaign has been renamed; its history is joined on '
                         'the id, never the name (4.1).')
        lines.append('')
    lines += [
        'AFTER YOU UPLOAD:',
        f'    python3 tools/build_campaign_reopen_bulksheet.py --mark-uploaded {batch_id}',
        'IF YOU DO NOT UPLOAD:',
        f'    python3 tools/build_campaign_reopen_bulksheet.py --supersede {batch_id}',
        'TO REVERSE AN UPLOADED BOOK:',
        f'    python3 tools/build_restore_campaign_reopen_bulksheet.py {batch_id}',
        '',
        'This script never uploads anything to Amazon.',
    ]
    with open(readme_path, 'w') as fh:
        fh.write('\n'.join(lines) + '\n')
    return readme_path


def build_parser():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('-o', '--out',
                    default=f'.tmp/campaign_reopen_{date.today():%Y%m%d}.xlsx')
    ap.add_argument('--mark-uploaded', metavar='BATCH')
    ap.add_argument('--supersede', metavar='BATCH')
    return ap


def main():
    args = build_parser().parse_args()

    if args.mark_uploaded:
        pending = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` "
                     f"WHERE batch_id = {q(args.mark_uploaded)} "
                     f"AND upload_status = 'PENDING_UPLOAD'")
        if int(pending[0]['n']) == 0:
            sys.exit(f'--mark-uploaded {args.mark_uploaded}: no PENDING_UPLOAD rows under that id. '
                     f'Nothing was changed.')
        run_update(mark_uploaded_sql(args.mark_uploaded), 'mark-uploaded')
        print(f'  marked batch {args.mark_uploaded} uploaded '
              f'({int(pending[0]["n"])} row(s))')
        return

    if args.supersede:
        pending = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` "
                     f"WHERE batch_id = {q(args.supersede)} "
                     f"AND upload_status = 'PENDING_UPLOAD'")
        if int(pending[0]['n']) == 0:
            sys.exit(f'--supersede {args.supersede}: no PENDING_UPLOAD rows under that id — it is '
                     f'already applied, already labelled, or unknown. Nothing was changed.')
        note = (f'never uploaded; superseded '
                f'({datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}) — labelled by the generator')
        run_update(supersede_sql(args.supersede, note), 'supersede')
        print(f'  labelled batch {args.supersede} SUPERSEDED_NEVER_UPLOADED '
              f'({int(pending[0]["n"])} row(s))')
        return

    for b in bq(prior_unmarked_batches_sql()):
        print(f'  earlier reopen book still pending: {b["batch_id"]} '
              f'({b["n"]} row(s), built {b["built"]})')

    rows = bq(candidates_sql())
    if not rows:
        print('  no campaign is due to reopen today — nothing written')
        return

    batch_id = f'campreopen_{date.today():%Y%m%d}_{datetime.now(timezone.utc):%H%M%S}'
    out = write_sheet(rows, args.out)
    readme = write_readme(rows, batch_id, out, out.replace('.xlsx', '_README.txt'))
    n = log_batch(rows, batch_id, readme)
    print(f'  {n} campaign(s) written to {out}')
    print(f'  README {readme}')
    print(f'  batch {batch_id} logged PENDING_UPLOAD — this script uploads nothing')


if __name__ == '__main__':
    main()
```

- [ ] **Step 3b: The house change-log shape — four names, and the discipline suite reads all four**

**This is the step that makes Step 1's test pass, and it is easy to miss because the book "works"
without it.** `tools/tests/test_change_log_discipline.py:99-106` parametrises over `BOOKS` and calls
`book.set_change_log_table(...)` and `book.LIVE_CHANGE_LOG` **by name**; a book whose only override
is `CHANGE_LOG = os.environ.get('CHANGE_LOG', ...)` fails that test immediately — and, worse, would
pass every other test while carrying **no `TMP_`/`TEMP_` guard at all**, which is precisely the
thing that test exists to prevent. Every new book in this plan needs all four names:

| name | where it comes from |
|---|---|
| `LIVE_CHANGE_LOG` | `"FACT_PPC_CHANGE_LOG"`, a bare table name |
| `CHANGE_LOG` | module global, `f"{PROJECT}.OI.{LIVE_CHANGE_LOG}"` |
| `set_change_log_table(table)` | asserts `table == LIVE_CHANGE_LOG or table.startswith(('TMP_','TEMP_'))` |
| `--change-log-table` | argparse argument, `default=LIVE_CHANGE_LOG`, wired in `main()` |

The Step 3 block above already carries the first three verbatim. Add the fourth in `build_parser()`
and wire it as the **first** thing `main()` does, copying
`tools/build_reprice_bulksheet.py:1383-1393`:

```python
    ap.add_argument('--change-log-table', default=LIVE_CHANGE_LOG, metavar='TABLE',
                    help='a TMP_/TEMP_ copy of FACT_PPC_CHANGE_LOG to act on instead of the live '
                         'log. Any other name is refused.')
```

```python
    if args.change_log_table != LIVE_CHANGE_LOG:
        set_change_log_table(args.change_log_table)
```

**The same four names go into every book this plan creates** — the restore generator in Step 4, both
Phase 9 books, and Task 7.7's close book and its restore. Never a `CHANGE_LOG=` shell variable in
front of the command: it does nothing, and the rows land in the live log where the house rule
forbids removing them.

- [ ] **Step 4: Write the restore generator**

```python
#!/usr/bin/env python3
"""RESTORE FOR THE CAMPAIGN REOPEN BOOK — put back what a reopen book turned on.

Every book in this account has a restore generator, because a book that cannot be reversed is a
one-way door in a system whose whole doctrine is about not building one (architecture/THREE_LAYERS.md
5). This one reads an uploaded reopen batch out of FACT_PPC_CHANGE_LOG and emits the opposite
bulksheet: the same campaigns, State set back to paused.

IT DOES NOT DELETE THE ORIGINAL ROWS. The change log is append-only; a restore is a NEW batch that
says what it reverses. Never uploaded by this script.
"""
import argparse
import json
import os
import subprocess
import sys
from datetime import date, datetime, timezone

import openpyxl

PROJECT = 'onyga-482313'

# THE CHANGE LOG, in the house shape every other book already uses. It is NOT an environment
# variable: tools/tests/test_change_log_discipline.py::test_a_change_log_override_must_be_a_tmp_copy
# calls set_change_log_table() and reads LIVE_CHANGE_LOG by name on every book in BOOKS, and an
# os.environ override carries no TMP_/TEMP_ guard at all — so the one thing that test exists to
# constrain would be unconstrained. Copy this block verbatim from
# tools/build_reprice_bulksheet.py:118-133; do not paraphrase it.
LIVE_CHANGE_LOG = "FACT_PPC_CHANGE_LOG"
CHANGE_LOG = f"{PROJECT}.OI.{LIVE_CHANGE_LOG}"


def set_change_log_table(table):
    global CHANGE_LOG
    assert table == LIVE_CHANGE_LOG or table.startswith(('TMP_', 'TEMP_')), \
        f"{table}: a change-log override must be a TMP_/TEMP_ copy — never another live table"
    CHANGE_LOG = f"{PROJECT}.OI.{table}"
    return CHANGE_LOG

CAMPAIGN_HEADERS = [
    'Product', 'Entity', 'Operation', 'Campaign ID', 'Campaign Name', 'Portfolio ID',
    'Start Date', 'End Date', 'Targeting Type', 'State', 'Daily Budget',
    'Bidding Strategy',
]


def q(v):
    if v is None:
        return 'NULL'
    return "'" + str(v).replace('\\', '\\\\').replace("'", "\\'") + "'"


def bq(sql):
    out = subprocess.run(
        ['bq', 'query', '--use_legacy_sql=false', '--nouse_cache', '--format=json',
         f'--project_id={PROJECT}', sql],
        capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f'query failed:\n{out.stderr}')
    return json.loads(out.stdout or '[]')


def run_update(sql, what):
    out = subprocess.run(
        ['bq', 'query', '--use_legacy_sql=false', '--nouse_cache', f'--project_id={PROJECT}', sql],
        capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f'{what} failed:\n{out.stderr}')


def batch_rows_sql(batch_id):
    return (f'SELECT c.campaign_id, c.campaign_name, c.campaign_type, ci.portfolio_id, '
            f'ci.daily_budget '
            f'FROM `{CHANGE_LOG}` c '
            f'LEFT JOIN `{PROJECT}.OI.V_CAMPAIGN_IDENTITY` ci '
            f'  ON ci.campaign_id = CAST(c.campaign_id AS STRING) '
            f'WHERE c.batch_id = {q(batch_id)} AND c.action = \'CAMPAIGN_ENABLE\' '
            f'ORDER BY c.campaign_name')


def supersede_sql(batch_id, note):
    return (f"UPDATE `{CHANGE_LOG}` SET upload_status = 'SUPERSEDED_NEVER_UPLOADED', "
            f"upload_note = {q(note)} "
            f"WHERE batch_id = {q(batch_id)} AND upload_status = 'PENDING_UPLOAD'")


def mark_uploaded_sql(batch_id):
    return (f"UPDATE `{CHANGE_LOG}` SET upload_status = NULL "
            f"WHERE batch_id = {q(batch_id)} AND upload_status = 'PENDING_UPLOAD'")


def prior_unmarked_batches_sql():
    return (f"SELECT batch_id, COUNT(*) n, MIN(applied_at) built "
            f"FROM `{CHANGE_LOG}` "
            f"WHERE upload_status = 'PENDING_UPLOAD' AND action = 'CAMPAIGN_PAUSE_RESTORE' "
            f"GROUP BY batch_id ORDER BY built")


def log_batch(rows, batch_id, source_batch, readme_path):
    exists = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` WHERE batch_id = {q(batch_id)}")
    assert int(exists[0]['n']) == 0, f'batch id {batch_id} already exists in the change log'
    note = (f'restore of campaign reopen batch {source_batch}, built '
            f'{datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}; '
            f'README {os.path.basename(readme_path)}; manual upload pending')
    structs = []
    for r in rows:
        cid = str(r['campaign_id'])
        structs.append(
            'STRUCT('
            f"{q('camprestore-' + batch_id.split('_')[-1] + '-' + cid)} AS change_id, "
            f'{q(batch_id)} AS batch_id, CURRENT_TIMESTAMP() AS applied_at, '
            f"{q('CAMPAIGN_PAUSE_RESTORE')} AS action, "
            f'{q(cid)} AS campaign_id, {q(r["campaign_name"])} AS campaign_name, '
            f'{q((r.get("campaign_type") or "").upper())} AS campaign_type, '
            f"{q('MANUAL')} AS source, {q('MANUAL_BULKSHEET')} AS coach_mode, "
            f'{q(note)} AS upload_note, '
            f"{q('PENDING_UPLOAD')} AS upload_status)")
    cols = ('change_id, batch_id, applied_at, action, campaign_id, campaign_name, campaign_type, '
            'source, coach_mode, upload_note, upload_status')
    run_update(f'INSERT INTO `{CHANGE_LOG}` ({cols}) '
               f"SELECT {cols} FROM UNNEST([{', '.join(structs)}])", 'change-log insert')
    back = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` WHERE batch_id = {q(batch_id)}")
    assert int(back[0]['n']) == len(rows)
    return int(back[0]['n'])


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('batch', nargs='?', help='the campaign reopen batch id to reverse')
    ap.add_argument('-o', '--out', default=None)
    ap.add_argument('--mark-uploaded', metavar='BATCH')
    ap.add_argument('--supersede', metavar='BATCH')
    args = ap.parse_args()

    if args.mark_uploaded:
        pending = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` "
                     f"WHERE batch_id = {q(args.mark_uploaded)} "
                     f"AND upload_status = 'PENDING_UPLOAD'")
        if int(pending[0]['n']) == 0:
            sys.exit(f'--mark-uploaded {args.mark_uploaded}: no PENDING_UPLOAD rows. '
                     f'Nothing was changed.')
        run_update(mark_uploaded_sql(args.mark_uploaded), 'mark-uploaded')
        print(f'  marked batch {args.mark_uploaded} uploaded')
        return

    if args.supersede:
        pending = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` "
                     f"WHERE batch_id = {q(args.supersede)} "
                     f"AND upload_status = 'PENDING_UPLOAD'")
        if int(pending[0]['n']) == 0:
            sys.exit(f'--supersede {args.supersede}: no PENDING_UPLOAD rows under that id. '
                     f'Nothing was changed.')
        note = (f'never uploaded; superseded '
                f'({datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}) — labelled by the generator')
        run_update(supersede_sql(args.supersede, note), 'supersede')
        print(f'  labelled batch {args.supersede} SUPERSEDED_NEVER_UPLOADED')
        return

    if not args.batch:
        sys.exit('name the campaign reopen batch to reverse, or pass --mark-uploaded / --supersede')

    for b in bq(prior_unmarked_batches_sql()):
        print(f'  earlier restore book still pending: {b["batch_id"]} '
              f'({b["n"]} row(s), built {b["built"]})')

    rows = bq(batch_rows_sql(args.batch))
    if not rows:
        sys.exit(f'{args.batch}: no CAMPAIGN_ENABLE rows under that batch id')

    out = args.out or f'.tmp/campaign_reopen_restore_{date.today():%Y%m%d}.xlsx'
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = 'Sponsored Products Campaigns'
    ws.append(CAMPAIGN_HEADERS)
    for r in rows:
        ws.append(['Sponsored Products', 'Campaign', 'Update', str(r['campaign_id']),
                   r['campaign_name'],
                   # never blank: a blank Portfolio ID on an Update row detaches the campaign
                   r.get('portfolio_id') or '',
                   '', '', '', 'paused', r.get('daily_budget') or '', ''])
    os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
    wb.save(out)

    batch_id = f'camprestore_{date.today():%Y%m%d}_{datetime.now(timezone.utc):%H%M%S}'
    readme = out.replace('.xlsx', '_README.txt')
    with open(readme, 'w') as fh:
        fh.write('\n'.join([
            'RESTORE FOR THE CAMPAIGN REOPEN BOOK',
            f'batch {batch_id}   reverses {args.batch}   {len(rows)} campaign(s)',
            '',
            'Every campaign this sheet touches is set back to paused. The original change-log rows '
            'are NOT deleted — the log is append-only, and this batch records what it reverses.',
            '',
            f'After you upload:  python3 tools/build_restore_campaign_reopen_bulksheet.py '
            f'--mark-uploaded {batch_id}',
            f'If you do not:     python3 tools/build_restore_campaign_reopen_bulksheet.py '
            f'--supersede {batch_id}',
            '',
            'This script never uploads anything to Amazon.',
        ]) + '\n')
    n = log_batch(rows, batch_id, args.batch, readme)
    print(f'  {n} campaign(s) written to {out}')
    print(f'  batch {batch_id} logged PENDING_UPLOAD — this script uploads nothing')


if __name__ == '__main__':
    main()
```

- [ ] **Step 5: Run the discipline tests**

```bash
cd /Users/ori/Develop/OI
/usr/local/bin/python3 -m pytest tools/tests/test_change_log_discipline.py -q
```

Expected: all PASS, now covering four books. **If
`test_a_change_log_override_must_be_a_tmp_copy` fails, Step 3b was skipped** — the book is missing
`set_change_log_table` or `LIVE_CHANGE_LOG`, and until it has them its change-log target has no
`TMP_` guard.

- [ ] **Step 6: Build against a temporary change-log copy**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CREATE OR REPLACE TABLE \`onyga-482313.OI.TMP_PPC_CHANGE_LOG_REOPEN\` AS
   SELECT * FROM \`onyga-482313.OI.FACT_PPC_CHANGE_LOG\` WHERE FALSE"
/usr/local/bin/python3 tools/build_campaign_reopen_bulksheet.py \
  --change-log-table TMP_PPC_CHANGE_LOG_REOPEN -o .tmp/campaign_reopen_check.xlsx
cat .tmp/campaign_reopen_check_README.txt
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT action, upload_status, COUNT(*) n FROM \`onyga-482313.OI.TMP_PPC_CHANGE_LOG_REOPEN\`
   GROUP BY 1,2"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "DROP TABLE \`onyga-482313.OI.TMP_PPC_CHANGE_LOG_REOPEN\`"
```

Expected: every row `CAMPAIGN_ENABLE` / `PENDING_UPLOAD`, and a README explaining each campaign top-down — Catalog, then Brain, then Pacing.

- [ ] **Step 7: Commit**

```bash
cd /Users/ori/Develop/OI
git add tools/build_campaign_reopen_bulksheet.py \
        tools/build_restore_campaign_reopen_bulksheet.py \
        tools/tests/test_change_log_discipline.py
git commit -m "feat(books): the campaign reopen book, and its restore generator

The OPEN half of violation 22 becomes an action. Reads FACT_CAMPAIGN_STATE for
WORTH rows whose reopen date has arrived, lands PENDING_UPLOAD, never uploads.
Portfolio ID is echoed on every row — a blank one detaches the campaign."
```

---

### Task 4.8: `FACT_CAMPAIGN_STATE_acceptance.sql`

**Files:**
- Create: `scripts/bigquery/tests/FACT_CAMPAIGN_STATE_acceptance.sql`

- [ ] **Step 1: Write the suite**

```sql
-- =============================================================================================
-- FACT_CAMPAIGN_STATE acceptance — the campaign verdict. EVERY ROW MUST READ PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Doctrine: architecture/THREE_LAYERS.md 4.1. Object:
-- scripts/bigquery/procedures/SP_SNAPSHOT_CAMPAIGN_STATE.sql.
-- =============================================================================================
WITH c AS (
  SELECT * FROM `onyga-482313.OI.FACT_CAMPAIGN_STATE`
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_CAMPAIGN_STATE`)
),
c01 AS (
  SELECT 'C01 one row per campaign per snapshot' AS check_name,
         (SELECT COUNT(*) FROM (SELECT snapshot_date, campaign_id
                                FROM `onyga-482313.OI.FACT_CAMPAIGN_STATE`
                                GROUP BY 1,2 HAVING COUNT(*) > 1)) AS violations
),
c02 AS (
  SELECT 'C02 the verdict is one of the doctrine four, never a command word',
         COUNTIF(verdict NOT IN ('WORTH','NOT_WORTH','NOT_WORTH_NOW','UNKNOWN') OR verdict IS NULL)
  FROM c
),
c03 AS (
  SELECT 'C03 a campaign closed for its season carries its reopen date (4.1)',
         COUNTIF(verdict = 'NOT_WORTH' AND reopen_date IS NULL)
  FROM c
),
c04 AS (
  SELECT 'C04 every WORTH campaign carries an OPEN date with its lead time already subtracted',
         COUNTIF(verdict = 'WORTH' AND reopen_date IS NULL)
       + COUNTIF(verdict = 'WORTH' AND reopen_date IS NOT NULL
                 AND DATE_DIFF(window_from, reopen_date, DAY) != lead_time_days)
  FROM c
),
c05 AS (
  SELECT 'C05 the requested window is a real forward window',
         COUNTIF(window_from IS NULL OR window_to IS NULL OR window_to < window_from)
  FROM c
),
c06 AS (
  SELECT 'C06 season evidence is the same calendar window one year back',
         COUNTIF(season_from != DATE_SUB(window_from, INTERVAL 364 DAY)
                 OR season_to != DATE_SUB(window_to, INTERVAL 364 DAY))
  FROM c
),
c07 AS (
  SELECT 'C07 every verdict explains itself in words a person can argue with',
         COUNTIF(verdict_reason IS NULL OR LENGTH(verdict_reason) < 20)
  FROM c
),
c08 AS (
  SELECT 'C08 a campaign bar, where present, is inside the published clamp (tolerance 5e-5)',
         COUNTIF(campaign_bar IS NOT NULL
                 AND (campaign_bar < 0.60 - 0.00005 OR campaign_bar > 1.00 + 0.00005))
  FROM c
),
c09 AS (
  SELECT 'C09 evidence is keyed on the id: the y1 pool equals an id-keyed pool over the fact',
         (SELECT COUNTIF(ABS(c.y1_spend - COALESCE(t.spend, 0)) > 0.01)
          FROM c
          LEFT JOIN (
            SELECT CAST(a.campaign_id AS STRING) cid, SUM(a.Ads_cost) spend
            FROM `onyga-482313.OI.FACT_AMAZON_ADS` a,
                 (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) d
                  FROM `onyga-482313.OI.FACT_AMAZON_ADS`) w
            WHERE a.date BETWEEN DATE_SUB(w.d, INTERVAL 365 DAY)
                             AND DATE_SUB(w.d, INTERVAL 1 DAY)
            GROUP BY 1) t ON t.cid = c.campaign_id)
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM (SELECT * FROM c01 UNION ALL SELECT * FROM c02 UNION ALL SELECT * FROM c03
      UNION ALL SELECT * FROM c04 UNION ALL SELECT * FROM c05 UNION ALL SELECT * FROM c06
      UNION ALL SELECT * FROM c07 UNION ALL SELECT * FROM c08 UNION ALL SELECT * FROM c09)
ORDER BY check_name;
```

- [ ] **Step 2: Run it**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/FACT_CAMPAIGN_STATE_acceptance.sql)"
```

Expected: nine rows, all `PASS`.

- [ ] **Step 3: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/tests/FACT_CAMPAIGN_STATE_acceptance.sql
git commit -m "test(catalog): FACT_CAMPAIGN_STATE acceptance — nine checks, id-keyed evidence"
```

---
## Phase 5 — Seasonality reaches the verdict

**Closes:** violation 2 (the Catalog is not seasonal, though two full holiday seasons of ads data exist).

**Why now, and why it has a deadline no other phase has.** This is the doctrine's single most expensive mistake — collapsing `NOT_WORTH_NOW` or `UNKNOWN` into `NOT_WORTH`. Replaying 2025-11-15 with the Catalog's own estimator shape against the 40-day peak: 45 of 111 condemned keywords actually **earned**, $40,108 of sales and $7,473 of net over the peak; false-negative rate 41%; the ratio of profit destroyed to loss avoided 8.9:1. Today $206.92/day sits on 50 keywords whose holiday CVR is at least 1.5x their summer CVR — 15.6% of the whole account, mispriced on a seasonal axis. §4.1's lead time means the November answer must be readable in October, so **this phase must land before roughly mid-October, with Phase 4's campaign lead time on top of it, or it misses the season it exists for.**

Mechanically the Catalog is seasonally blind by construction: `grep -n season` over the 639-line procedure returns three lines and all three are pass-through, and the guard's `inst` CTE is hard-bounded to 104 days at `V_KEYWORD_GUARD.sql:233`, so no second holiday season is reachable from it at all.

**Unblocks:** violation 9 (`NOT_WORTH_NOW` has nothing to say until the Catalog can answer seasonally); Phase 8's `verdict` field; the negative-expiry rule in Phase 9, which needs a season to reason with.

**Size:** L — 2.5–3.5 weeks. A new instance-grain window object, a re-keyed season memory, a table function that makes `ask()` read-only, and the subject-grain season gate wired into the ladder before the book's arm can be removed.

---

### Task 5.1: Two red measurements

- [ ] **Step 1: Prove the ladder never consumes `season_context`**

```bash
cd /Users/ori/Develop/OI
grep -n "season" scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql
```

Expected: exactly three hits — the guard selection, the carry, and the publication as `season_context`. **No `CASE` arm, no filter, no verdict and no appointment reads it.** Confirm the column is populated and inert:

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT season_context, COUNT(*) n, COUNT(DISTINCT state) distinct_states
   FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`
   WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`)
   GROUP BY 1"
```

Expected: three groups (TRUE / FALSE / NULL) with the same spread of states in each — the flag changes nothing.

- [ ] **Step 2: Replay the season door and measure the false-negative rate**

Re-run the baseline's own query, committed at `docs/superpowers/specs/2026-08-24-three-layers-baseline.md` under **"THE SEASON DOOR — the window says NO on the eve of the season"**. It replays 2025-11-15 with a 90-day trailing frame against the 2025-11-16..12-25 peak.

Expected: a `trailing_says_BELOW_bar` × `season_EARNED` cell with a large keyword count and a large positive `peak_net`. Measured: 45 of 111 condemned keywords earned, $40,108 of peak sales, $7,473 of peak net — a 41% false-negative rate. **That is the number this phase must reduce**, and Task 5.8 re-runs the same replay against the new estimator.

- [ ] **Step 3: Show the season memory blends families**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH s AS (
  SELECT LOWER(TRIM(target_text)) t, family, SUM(settled_sp90) sp
  FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`)
    AND family IS NOT NULL
  GROUP BY 1,2),
multi AS (SELECT t FROM s GROUP BY t HAVING COUNT(DISTINCT family) > 1)
SELECT COUNT(DISTINCT s.t) AS texts_in_more_than_one_family,
       ROUND(SUM(IF(m.t IS NOT NULL, s.sp, 0)), 2) AS usd_settled_on_blended_texts,
       ROUND(SUM(s.sp), 2) AS usd_settled_total
FROM s LEFT JOIN multi m ON m.t = s.t"
```

Expected: a modest count of texts carrying a large share of the money. Measured 2026-08-24: 24 texts, $30,124.69 of $74,689.27 — 40.3%. `FACT_KEYWORD_SEASON_VERDICT` has no `campaign_id`, no `keyword_id`, no family and no ASIN, and `V_KEYWORD_GUARD.sql:289-299` groups it by `LOWER(TRIM(keyword_text))`, so any text-keyed seasonal answer blends 40% of the account across families. §2.2 forbids bare target text as a subject.

- [ ] **Step 4: Record the measurement and commit it**

Every red measurement in this plan is a number the green run is compared against, so it is written
down rather than remembered. Append what you measured — the query, the date, and the count — to the
running record, creating the file on the first task that reaches this step:

```bash
cd /Users/ori/Develop/OI
mkdir -p docs/superpowers/specs
cat >> docs/superpowers/specs/2026-08-25-gap-closure-measurements.md <<'EOF'

## Task 5.1 — measured YYYY-MM-DD

Replace the date above with the date you ran it, and paste below: the query you ran (unchanged from
the task), and its output. Do not summarise the output — the point of this file is that a re-run is
a re-run and not a fresh argument, which is the same reason
docs/superpowers/specs/2026-08-24-three-layers-baseline.md exists.
EOF
git add docs/superpowers/specs/2026-08-25-gap-closure-measurements.md
git commit -m "measure(task 5.1): record the red measurement before the fix

The number the green run is compared against, written down rather than remembered."
```

---

### Task 5.2: `V_KEYWORD_SEASON_WINDOW` — instance-grain evidence reaching a year back

**Files:**
- Create: `scripts/bigquery/views/V_KEYWORD_SEASON_WINDOW.sql`
- Modify: `config.yaml` (`views:` section)

**Why a new object and not a wider window.** `V_KEYWORD_GUARD.sql:233` hard-bounds the entire `inst` CTE to 104 days, so violation 2 cannot be fixed by widening a window in place. The existing long-history pools (`life` at 237–243 and `lys` at 246–256) are **scope grain** — bare text pooled account-wide, or `family|clause` for auto — and cannot be reused as-is. This is a new object at `(campaign_id, keyword_id)` grain.

- [ ] **Step 1: Write the view**

```sql
-- =============================================================================================
-- V_KEYWORD_SEASON_WINDOW — what a subject did in the SAME CALENDAR WINDOW one and two years back,
-- at (campaign_id, keyword_id) grain.
--
-- WHY A NEW OBJECT. V_KEYWORD_GUARD's instance CTE is hard-bounded to 104 days, so no second
-- holiday season is reachable from it at all, and its long-history pools are SCOPE grain — bare
-- text pooled account-wide, or family|clause for auto clauses — which architecture/THREE_LAYERS.md
-- 2.2 forbids as a subject: 24 target texts in this account appear in more than one family and
-- carry 40% of the settled money between them.
--
-- THE WINDOW IS 364 DAYS, NOT 365. A 364-day shift preserves the day of week, which matters for a
-- retail seasonal comparison — the same Saturday of the same shopping week, not the same date.
--
-- COMPLETE DAYS ONLY: every window ends at the ads watermark minus one, house convention.
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_KEYWORD_SEASON_WINDOW` AS
WITH wm AS (
  SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),
-- the window being asked about. Default: the next holiday occurrence whose peak has not started,
-- from boost_start to cooldown_end (or peak_start + 3 days where no cooldown is set — the same
-- fallback FN_PLAN_CALENDAR_STATE uses). Phase 5's DE_CATALOG_WINDOW_REQUEST overrides it.
req AS (
  SELECT
    COALESCE((SELECT MIN(h.boost_start) FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
              WHERE h.peak_start > (SELECT d FROM wm)),
             DATE_ADD((SELECT d FROM wm), INTERVAL 1 DAY))  AS window_from,
    COALESCE((SELECT MIN(COALESCE(h.cooldown_end, DATE_ADD(h.peak_start, INTERVAL 3 DAY)))
              FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
              WHERE h.peak_start > (SELECT d FROM wm)),
             DATE_ADD((SELECT d FROM wm), INTERVAL 28 DAY)) AS window_to,
    COALESCE((SELECT MIN(h.holiday_name) FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
              WHERE h.peak_start > (SELECT d FROM wm)),
             'next 28 days')                                AS window_label
),
f AS (
  SELECT CAST(a.campaign_id AS STRING) AS campaign_id,
         CAST(a.keyword_id  AS STRING) AS keyword_id,
         a.date, a.Ads_clicks, a.Ads_cost, a.Ads_orders, a.Ads_sales, a.GROSS_PROFIT
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a, wm
  WHERE a.keyword_id IS NOT NULL
    AND a.date <= DATE_SUB(wm.d, INTERVAL 1 DAY)
)
SELECT
  f.campaign_id,
  f.keyword_id,
  r.window_from,
  r.window_to,
  r.window_label,
  DATE_SUB(r.window_from, INTERVAL 364 DAY)                        AS ly_from,
  DATE_SUB(r.window_to,   INTERVAL 364 DAY)                        AS ly_to,
  DATE_SUB(r.window_from, INTERVAL 728 DAY)                        AS ly2_from,
  DATE_SUB(r.window_to,   INTERVAL 728 DAY)                        AS ly2_to,

  -- LAST YEAR, same calendar window
  SUM(IF(f.date BETWEEN DATE_SUB(r.window_from, INTERVAL 364 DAY)
                    AND DATE_SUB(r.window_to,   INTERVAL 364 DAY), f.Ads_clicks, 0))  AS ly_clicks,
  SUM(IF(f.date BETWEEN DATE_SUB(r.window_from, INTERVAL 364 DAY)
                    AND DATE_SUB(r.window_to,   INTERVAL 364 DAY), f.Ads_cost, 0))    AS ly_spend,
  SUM(IF(f.date BETWEEN DATE_SUB(r.window_from, INTERVAL 364 DAY)
                    AND DATE_SUB(r.window_to,   INTERVAL 364 DAY), f.Ads_orders, 0))  AS ly_orders,
  SUM(IF(f.date BETWEEN DATE_SUB(r.window_from, INTERVAL 364 DAY)
                    AND DATE_SUB(r.window_to,   INTERVAL 364 DAY), f.GROSS_PROFIT, 0)) AS ly_gp,

  -- TWO YEARS BACK. The ads data starts 2024-09-05, so for most windows this is empty today and
  -- becomes real next year. It is published rather than omitted so a consumer can see the absence.
  SUM(IF(f.date BETWEEN DATE_SUB(r.window_from, INTERVAL 728 DAY)
                    AND DATE_SUB(r.window_to,   INTERVAL 728 DAY), f.Ads_clicks, 0))  AS ly2_clicks,
  SUM(IF(f.date BETWEEN DATE_SUB(r.window_from, INTERVAL 728 DAY)
                    AND DATE_SUB(r.window_to,   INTERVAL 728 DAY), f.Ads_cost, 0))    AS ly2_spend,
  SUM(IF(f.date BETWEEN DATE_SUB(r.window_from, INTERVAL 728 DAY)
                    AND DATE_SUB(r.window_to,   INTERVAL 728 DAY), f.Ads_orders, 0))  AS ly2_orders,
  SUM(IF(f.date BETWEEN DATE_SUB(r.window_from, INTERVAL 728 DAY)
                    AND DATE_SUB(r.window_to,   INTERVAL 728 DAY), f.GROSS_PROFIT, 0)) AS ly2_gp,

  -- THE COMPARISON WINDOW: the equivalent span ending at the watermark, so a seasonal lift can be
  -- read as a ratio against what the subject is doing right now rather than against nothing.
  SUM(IF(f.date BETWEEN DATE_SUB((SELECT d FROM wm),
                                 INTERVAL DATE_DIFF(r.window_to, r.window_from, DAY) + 1 DAY)
                    AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), f.Ads_clicks, 0)) AS now_clicks,
  SUM(IF(f.date BETWEEN DATE_SUB((SELECT d FROM wm),
                                 INTERVAL DATE_DIFF(r.window_to, r.window_from, DAY) + 1 DAY)
                    AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), f.Ads_orders, 0)) AS now_orders,
  SUM(IF(f.date BETWEEN DATE_SUB((SELECT d FROM wm),
                                 INTERVAL DATE_DIFF(r.window_to, r.window_from, DAY) + 1 DAY)
                    AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), f.Ads_cost, 0))   AS now_spend,
  SUM(IF(f.date BETWEEN DATE_SUB((SELECT d FROM wm),
                                 INTERVAL DATE_DIFF(r.window_to, r.window_from, DAY) + 1 DAY)
                    AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), f.GROSS_PROFIT, 0)) AS now_gp
FROM f CROSS JOIN req r
GROUP BY f.campaign_id, f.keyword_id, r.window_from, r.window_to, r.window_label;
```

- [ ] **Step 2: Deploy and check it reaches the last holiday**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_KEYWORD_SEASON_WINDOW.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT ANY_VALUE(window_label) label, ANY_VALUE(window_from) w_from, ANY_VALUE(window_to) w_to,
       ANY_VALUE(ly_from) ly_from, ANY_VALUE(ly_to) ly_to,
       COUNT(*) subjects, COUNTIF(ly_clicks > 0) with_last_year_evidence,
       ROUND(SUM(ly_spend), 0) usd_last_year_in_this_window
FROM \`onyga-482313.OI.V_KEYWORD_SEASON_WINDOW\`"
```

Expected: `ly_from` / `ly_to` land inside the last holiday season, and `with_last_year_evidence` is substantial — the evidence the 104-day bound made unreachable.

- [ ] **Step 3: Register in `config.yaml`** (`views:`, beside `V_KEYWORD_GUARD`):

```yaml
  - name: V_KEYWORD_SEASON_WINDOW
    description: >-
      What each subject did in the same calendar window one and two years back, at (campaign_id,
      keyword_id) grain, plus the equivalent span ending at today's watermark for comparison. Exists
      because V_KEYWORD_GUARD's instance CTE is hard-bounded to 104 days, so no second holiday
      season is reachable from it, and its long-history pools are scope grain — bare text pooled
      account-wide — which architecture/THREE_LAYERS.md 2.2 forbids as a subject. Windows shift by
      364 days so the day of week is preserved. Complete days only.
    type: view
    source_files:
      - scripts/bigquery/views/V_KEYWORD_SEASON_WINDOW.sql
    dependencies:
      - FACT_AMAZON_ADS
      - DIM_US_HOLIDAYS
      - FN_ADS_ANCHOR_CAP
```

- [ ] **Step 4: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_KEYWORD_SEASON_WINDOW.sql config.yaml
git commit -m "feat(catalog): V_KEYWORD_SEASON_WINDOW — a year of evidence at subject grain

The guard's instance window is hard-bounded to 104 days, so the second holiday
season was unreachable. This is a new object at (campaign_id, keyword_id), not a
wider window in an old one."
```

---

### Task 5.3: Re-key the season memory off bare text

**Files:**
- Create: `scripts/bigquery/views/V_KEYWORD_CONTEXT_LEDGER_BY_SUBJECT.sql`
- Modify: `scripts/bigquery/tables/FACT_KEYWORD_SEASON_VERDICT.sql` (three new columns)
- Modify: `scripts/bigquery/procedures/SP_SNAPSHOT_SEASON_VERDICT.sql` (write the ids)
- Modify: `scripts/bigquery/views/V_KEYWORD_GUARD.sql:289-299` and `:419` (join on the ids)

`V_KEYWORD_CONTEXT_LEDGER` groups `FACT_AMAZON_ADS` by `LOWER(TRIM(targeting))` alone. The ids are right there in the fact; a subject-grain twin is the same shape with two more grouping columns. Build the twin rather than mutating the existing view, so nothing that reads the text-grain ledger moves.

- [ ] **Step 1: Write the subject-grain ledger**

```sql
-- =============================================================================================
-- V_KEYWORD_CONTEXT_LEDGER_BY_SUBJECT — the season ledger at (campaign_id, keyword_id) grain.
--
-- WHY. V_KEYWORD_CONTEXT_LEDGER is one row per (LOWER(TRIM(targeting)), occurrence) — bare target
-- text, pooled across the whole account. architecture/THREE_LAYERS.md 2.2 forbids bare text as a
-- subject, and the money says why: 24 target texts in this account appear in more than one family
-- and carry 40% of the settled 90-day spend between them, so a text-keyed seasonal verdict blends
-- two families' economics into one wrong answer.
--
-- THE TEXT-GRAIN VIEW IS NOT CHANGED. It has its own readers and its own meaning (an account-wide
-- prior over a phrase); this is a twin at the grain the verdict needs.
--
-- IT IS AN IDENTICAL TWIN, AND THAT IS A REQUIREMENT, NOT A STYLE NOTE. The guard's re-keyed `seas`
-- CTE filters on mature_at_start and drives season_win_prior, which gates BLOCK_CUT and ENTRY_BLOCK
-- today and NOT_WORTH_NOW after Task 5.5 — all live safety gates. So EVERY rule below is copied
-- from V_KEYWORD_CONTEXT_LEDGER verbatim and only the GROUP BY differs:
--   * the anchor is LEAST(MAX(date), FN_ADS_ANCHOR_CAP()) and the ledger sums SETTLED DAYS ONLY,
--     date <= anchor - 7 — NOT watermark - 1, which would let six unsettled days manufacture a
--     false loss verdict inside the very window the gate protects;
--   * mature_at_start is first_click_date <= occurrence_start - 30 DAYS — NOT
--     first_click_date < occurrence_start, which drops the 30-day margin and admits launch ramp as
--     season signal, the exact thing the maturity guard exists to exclude;
--   * occurrence_closed is V_SEASON_CONTEXT's own column, carried through, never recomputed here;
--   * settled_through is anchor - 7, the same date the sums are fenced at;
--   * gross_profit is Ads_sales - IFNULL(TOTAL_COST_PER_UNIT,0)*Ads_units — the doctrine formula
--     verbatim, deliberately NOT FACT_AMAZON_ADS.GROSS_PROFIT, which is the tier-COGS variant the
--     engines use. The ledger stays self-contained;
--   * tested is clicks >= 15, and the HAVING keeps a row only where the subject had clicks or spend
--     inside the occurrence.
-- If either view's rules move, BOTH move, in one commit. A drift here is a silent loosening of a
-- live gate that no acceptance check would catch, because both views would still be internally
-- consistent.
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_KEYWORD_CONTEXT_LEDGER_BY_SUBJECT` AS
WITH
anchor AS (
  SELECT LEAST((SELECT MAX(date) FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
               `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS a
),
fx AS (
  SELECT
    CAST(campaign_id AS STRING) AS campaign_id,
    CAST(keyword_id  AS STRING) AS keyword_id,
    LOWER(TRIM(targeting))      AS keyword_text,
    date,
    Ads_clicks,
    Ads_cost,
    Ads_sales,
    Ads_units,
    Ads_orders,
    Ads_sales - IFNULL(TOTAL_COST_PER_UNIT, 0) * Ads_units AS gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE targeting IS NOT NULL AND TRIM(targeting) != ''
    AND keyword_id IS NOT NULL
),
-- the SUBJECT's own first click. FULL history, not settled-capped — same as the text-grain view.
first_click AS (
  SELECT campaign_id, keyword_id, MIN(IF(Ads_clicks > 0, date, NULL)) AS first_click_date
  FROM fx
  GROUP BY campaign_id, keyword_id
),
led AS (
  SELECT
    f.campaign_id,
    f.keyword_id,
    ANY_VALUE(f.keyword_text)      AS keyword_text,   -- 1:1 with the pair; label only, never a key
    c.context_label,
    c.occurrence_key,
    c.occurrence_start,
    c.occurrence_end,
    c.is_peak,
    c.occurrence_closed,
    SUM(f.Ads_clicks)              AS clicks,
    ROUND(SUM(f.Ads_cost), 2)      AS spend,
    ROUND(SUM(f.Ads_sales), 2)     AS sales,
    ROUND(SUM(f.gp), 2)            AS gross_profit,
    ROUND(SUM(f.gp) - SUM(f.Ads_cost), 2) AS net,
    SUM(f.Ads_orders)              AS orders,
    SUM(f.Ads_units)               AS units,
    MIN(f.date)                    AS first_active_date,
    MAX(f.date)                    AS last_active_date,
    COUNT(DISTINCT f.date)         AS active_days
  FROM fx f
  JOIN `onyga-482313.OI.V_SEASON_CONTEXT` c ON c.date = f.date
  CROSS JOIN anchor an
  WHERE f.date <= DATE_SUB(an.a, INTERVAL 7 DAY)   -- SETTLED days only, identical to the twin
  GROUP BY 1, 2, 4, 5, 6, 7, 8, 9
  HAVING SUM(f.Ads_clicks) > 0 OR SUM(f.Ads_cost) > 0
)
SELECT
  l.*,
  fc.first_click_date,
  (fc.first_click_date IS NOT NULL
   AND fc.first_click_date <= DATE_SUB(l.occurrence_start, INTERVAL 30 DAY)) AS mature_at_start,
  l.clicks >= 15 AS tested,
  (SELECT DATE_SUB(a, INTERVAL 7 DAY) FROM anchor) AS settled_through
FROM led l
LEFT JOIN first_click fc
  ON fc.campaign_id = l.campaign_id AND fc.keyword_id = l.keyword_id;
```

- [ ] **Step 1b: Prove the twin is a twin**

Before anything reads it, check that the subject-grain view rolls up to the text-grain one on the
rules that matter. A difference here is a rule that drifted, not a grain effect:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH t AS (SELECT keyword_text, occurrence_key, SUM(clicks) c, SUM(spend) sp,
                  COUNTIF(mature_at_start) m, MAX(settled_through) st
           FROM \`onyga-482313.OI.V_KEYWORD_CONTEXT_LEDGER\` GROUP BY 1,2),
     b AS (SELECT keyword_text, occurrence_key, SUM(clicks) c, SUM(spend) sp,
                  COUNTIF(mature_at_start) m, MAX(settled_through) st
           FROM \`onyga-482313.OI.V_KEYWORD_CONTEXT_LEDGER_BY_SUBJECT\` GROUP BY 1,2)
SELECT COUNTIF(ABS(t.c - b.c) > 0)        AS click_totals_that_disagree,
       COUNTIF(ABS(t.sp - b.sp) > 0.01)   AS spend_totals_that_disagree,
       COUNTIF(t.st != b.st)              AS settled_fences_that_disagree,
       COUNTIF(t.m > 0 AND b.m = 0)       AS occurrences_that_lost_their_maturity_flag,
       COUNTIF(t.m = 0 AND b.m > 0)       AS occurrences_that_GAINED_a_maturity_flag
FROM t JOIN b USING (keyword_text, occurrence_key)"
```

Expected: `settled_fences_that_disagree = 0` and, above all,
`occurrences_that_GAINED_a_maturity_flag = 0` — a gain means the twin's maturity rule is looser than
the live one and the safety gate has been quietly widened. Click and spend totals may differ by the
rows the text-grain view keeps and this one drops (`keyword_id IS NULL`); report the difference
rather than assuming it is zero, and if it is large, find out which rows carry no keyword id before
proceeding.

- [ ] **Step 2: Add the id columns to the verdict table**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
ALTER TABLE \`onyga-482313.OI.FACT_KEYWORD_SEASON_VERDICT\`
  ADD COLUMN IF NOT EXISTS campaign_id STRING,
  ADD COLUMN IF NOT EXISTS keyword_id  STRING,
  ADD COLUMN IF NOT EXISTS family      STRING"
```

Append the same three `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` lines to `scripts/bigquery/tables/FACT_KEYWORD_SEASON_VERDICT.sql` with this comment:

```sql
-- ── THE SUBJECT, NOT THE PHRASE (2026-08-25, violation 2 / doctrine 2.2) ──────────────────────
-- This table had no campaign_id, no keyword_id, no family and no ASIN, so the account's only
-- seasonal memory was keyed on bare target text — and 24 texts in this account appear in more than
-- one family carrying 40% of the settled money between them. The ids are written at verdict time
-- from V_KEYWORD_CONTEXT_LEDGER_BY_SUBJECT; the text-keyed rows already in the table keep their
-- NULL ids and are still readable as an account-wide prior over a phrase.
ALTER TABLE `onyga-482313.OI.FACT_KEYWORD_SEASON_VERDICT` ADD COLUMN IF NOT EXISTS campaign_id STRING;
ALTER TABLE `onyga-482313.OI.FACT_KEYWORD_SEASON_VERDICT` ADD COLUMN IF NOT EXISTS keyword_id  STRING;
ALTER TABLE `onyga-482313.OI.FACT_KEYWORD_SEASON_VERDICT` ADD COLUMN IF NOT EXISTS family      STRING;
```

- [ ] **Step 3: Write the ids at verdict time**

In `SP_SNAPSHOT_SEASON_VERDICT.sql`, change the `USING` source from `V_KEYWORD_CONTEXT_LEDGER` to the subject-grain twin, add the three columns to the projection, change the MERGE key, and add the three columns to both the `UPDATE SET` and the `INSERT`. The `ON` clause today reads:

```sql
  ON t.occurrence_key = s.occurrence_key AND t.keyword_text = s.keyword_text
```

Replace with:

```sql
  -- 2026-08-25: the key is the SUBJECT, not the phrase (doctrine 2.2). COALESCE on the id columns
  -- so the historical text-keyed rows, which carry NULL ids, still match themselves and are neither
  -- duplicated nor orphaned by this change.
  ON t.occurrence_key = s.occurrence_key
 AND COALESCE(t.campaign_id, '') = COALESCE(s.campaign_id, '')
 AND COALESCE(t.keyword_id,  '') = COALESCE(s.keyword_id,  '')
 AND t.keyword_text = s.keyword_text
```

and add to the source projection, beside `keyword_text`:

```sql
      campaign_id,
      keyword_id,
      family,
```

with the source `FROM` becoming:

```sql
    FROM (
      SELECT l.*, fb.family
      FROM `onyga-482313.OI.V_KEYWORD_CONTEXT_LEDGER_BY_SUBJECT` l
      LEFT JOIN (SELECT CAST(campaign_id AS STRING) cid, ANY_VALUE(family) family
                 FROM `onyga-482313.OI.T_FAMILY_BAR` GROUP BY 1) fb
        ON fb.cid = l.campaign_id
    )
    WHERE occurrence_closed
```

- [ ] **Step 4: Re-key the guard's join**

In `V_KEYWORD_GUARD.sql`, the `seas` CTE (lines 289–299) groups the verdict table by `LOWER(TRIM(v.keyword_text))` and line 419 joins `ON s.kw = LOWER(TRIM(kws.keyword_text))`. Replace both with a subject-keyed pair, keeping the text-keyed arm as an explicit, labelled fallback:

```sql
-- 2026-08-25 (violation 2 / doctrine 2.2): the season prior is read at SUBJECT grain where the
-- verdict table now carries ids, and falls back to the text-keyed prior only where it does not —
-- with season_prior_source saying which, so a blended answer can never look like a clean one.
seas AS (
  SELECT CAST(v.campaign_id AS STRING) AS cid, CAST(v.keyword_id AS STRING) AS kid,
         COUNTIF(v.verdict = 'WIN') AS n_win
  FROM `onyga-482313.OI.FACT_KEYWORD_SEASON_VERDICT` v
  WHERE v.campaign_id IS NOT NULL AND v.keyword_id IS NOT NULL
    AND v.mature_at_start
  GROUP BY 1, 2
),
seas_text AS (
  SELECT LOWER(TRIM(v.keyword_text)) AS kw, COUNTIF(v.verdict = 'WIN') AS n_win
  FROM `onyga-482313.OI.FACT_KEYWORD_SEASON_VERDICT` v
  WHERE v.campaign_id IS NULL
    AND v.mature_at_start
  GROUP BY 1
),
```

and at the join site, replace the single text join with:

```sql
LEFT JOIN seas      s  ON s.cid = kws.campaign_id AND s.kid = kws.keyword_id
LEFT JOIN seas_text st ON st.kw = LOWER(TRIM(kws.keyword_text))
```

with the consuming expression becoming:

```sql
    COALESCE(s.n_win, st.n_win, 0) > 0                                  AS season_win_prior,
    CASE WHEN s.n_win  IS NOT NULL THEN 'SUBJECT'
         WHEN st.n_win IS NOT NULL THEN 'TEXT_POOLED_ACROSS_FAMILIES'
         ELSE 'NONE' END                                                AS season_prior_source,
```

Add `season_prior_source` to the guard's published column list.

- [ ] **Step 5: Deploy the chain in order, then verify**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_KEYWORD_CONTEXT_LEDGER_BY_SUBJECT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tables/FACT_KEYWORD_SEASON_VERDICT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_SEASON_VERDICT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_SEASON_VERDICT\`();
   CALL \`onyga-482313.OI.SP_SNAPSHOT_SEASON_VERDICT\`();"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_KEYWORD_GUARD.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_GUARD\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT season_prior_source, COUNT(*) n, COUNTIF(season_win_prior) with_a_win
   FROM \`onyga-482313.OI.FACT_KEYWORD_GUARD\` GROUP BY 1 ORDER BY n DESC"
```

Expected: a `SUBJECT` bucket that is non-empty and growing, a `TEXT_POOLED_ACROSS_FAMILIES` bucket for the historical rows, and no duplication in the verdict table from the double call.

- [ ] **Step 6: Register and commit**

Add `V_KEYWORD_CONTEXT_LEDGER_BY_SUBJECT` to `config.yaml` under `views:`, beside `V_KEYWORD_CONTEXT_GATE`, with a description saying it is the subject-grain twin of the text-grain ledger and why (doctrine §2.2, and the measured 40% of money on blended texts).

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_KEYWORD_CONTEXT_LEDGER_BY_SUBJECT.sql \
        scripts/bigquery/tables/FACT_KEYWORD_SEASON_VERDICT.sql \
        scripts/bigquery/procedures/SP_SNAPSHOT_SEASON_VERDICT.sql \
        scripts/bigquery/views/V_KEYWORD_GUARD.sql config.yaml
git commit -m "feat(catalog): the season memory is keyed on the subject, not the phrase

Doctrine 2.2 forbids bare target text as a subject, and 24 texts carrying 40% of
settled spend appear in more than one family. season_prior_source names which
prior answered, so a blended answer can never look like a clean one."
```

---

### Task 5.4: `ask(subject, window_from, window_to)` — a requested window

**Files:**
- Create: `scripts/bigquery/functions/FN_CATALOG_SEASON_WINDOW.sql` (the table function — this is `ask()`)
- Create: `scripts/bigquery/tables/DE/DE_CATALOG_WINDOW_REQUEST.sql` (the **standing** window, a setting)
- Modify: `scripts/bigquery/views/V_KEYWORD_SEASON_WINDOW.sql` (becomes a call to the function at the standing window)
- Modify: `scripts/bigquery/procedures/SP_SNAPSHOT_CAMPAIGN_STATE.sql` (resolves the standing window the same way)
- Modify: `scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql` (one new check)
- Modify: `config.yaml` (`functions:` and `tables:`)

The Catalog's judging frame is fixed relative to today's watermark — `[wm-92, wm-3]` for SP and `[wm-103, wm-14]` for SB (`SP_SNAPSHOT_KEYWORD_STATE.sql:207-225`) — with no calendar input and no requested-window parameter. §4: the Catalog answers for a **requested** window, which is what lets November be asked in October.

**`ask(subject, window_from, window_to)` IS A PARAMETER, NOT A SETTING — and building it as a setting
breaks §1.4 in as many words.** *"Asking changes nothing. A query to any layer is read-only. Nothing
is spent, moved or recorded because someone asked a question."* A single-active-row toggle that every
reader consults would mean an analyst or a dashboard asking *"what is this worth in November"*
changes the window **every subject in the account is judged against**, and any orchestrator pass
landing between the insert and the retire computes the whole ladder against the probe window. The
orchestrator runs New York and the snapshot is Los Angeles dated, so that collision is not
hypothetical. Two callers also could not hold two windows at once, which is what §1.4's "each layer
is independently usable" means concretely.

So this task builds **two things, with two different jobs**:

| object | what it is | who uses it |
|---|---|---|
| `FN_CATALOG_SEASON_WINDOW(p_from, p_to)` | a BigQuery **table function** — `ask()`. Takes the window as an argument, writes nothing, and two callers may hold different windows in the same second. | anyone: Ori, a notebook, a dashboard page, a future module |
| `DE_CATALOG_WINDOW_REQUEST` | the **standing** window the nightly snapshot answers for — a setting, per §3.3 ("the Brain's open questions are settings, not code"). Changing it is a deliberate configuration act, not a question. | `SP_SNAPSHOT_KEYWORD_STATE` and `SP_SNAPSHOT_CAMPAIGN_STATE`, once a night |

One body, two entry points: the view is defined as a call to the function at the standing window, so
the evidence definition exists exactly once and cannot drift between the asked answer and the
snapshotted one.

- [ ] **Step 0: Write the table function — this is `ask()`, and it writes nothing**

Take `V_KEYWORD_SEASON_WINDOW`'s body **exactly as Task 5.2 built it** and lift it into a table
function whose window comes in as two arguments. Nothing else changes: same evidence, same
`364 DAY` offset, same complete-days fence, same columns.

```sql
-- =============================================================================================
-- FN_CATALOG_SEASON_WINDOW — ask(window_from, window_to). The Catalog's seasonal evidence for ANY
-- window, as a parameter.
--
-- architecture/THREE_LAYERS.md 4: "The Catalog answers for a REQUESTED window, not for 'now'."
-- 1.4: "Asking changes nothing. A query to any layer is read-only. Nothing is spent, moved or
-- recorded because someone asked a question." A table function is the only shape that satisfies
-- both: the window is an argument, so a dashboard asking what November is worth changes nothing
-- for anyone else, and two callers may hold two different windows in the same second.
--
-- THE STANDING WINDOW IS A DIFFERENT THING AND LIVES IN DE_CATALOG_WINDOW_REQUEST. That table is a
-- SETTING (3.3) — the window the nightly snapshot answers for — not the parameter of a question.
-- V_KEYWORD_SEASON_WINDOW is defined as a call to THIS function at that standing window, so the
-- evidence definition exists exactly once and cannot drift between an asked answer and a
-- snapshotted one.
--
-- 364 AND NOT 365: it preserves the day of week, and weekday mix moves conversion rate more than
-- one calendar day of drift does.
-- =============================================================================================
CREATE OR REPLACE TABLE FUNCTION `onyga-482313.OI.FN_CATALOG_SEASON_WINDOW`(
  p_window_from DATE, p_window_to DATE, p_window_label STRING
) AS
WITH wm AS (
  SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
)
-- ... the entire body Task 5.2 wrote, with `req` deleted and every reference to req.window_from /
-- req.window_to / req.window_label replaced by p_window_from / p_window_to / p_window_label ...
;
```

Deploy it and prove `ask()` answers for a window nobody has configured, **without writing anything**:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/functions/FN_CATALOG_SEASON_WINDOW.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT ANY_VALUE(window_label) label, ANY_VALUE(window_from) w_from, ANY_VALUE(ly_from) ly_from,
       COUNTIF(ly_clicks > 0) subjects_with_last_year_evidence
FROM \`onyga-482313.OI.FN_CATALOG_SEASON_WINDOW\`(DATE '2026-11-16', DATE '2026-12-25',
                                                  'holiday peak 2026')"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT COUNT(*) AS rows_written_by_asking FROM \`onyga-482313.OI.DE_CATALOG_WINDOW_REQUEST\`"
```

Expected: `label = holiday peak 2026`, `w_from = 2026-11-16`, `ly_from = 2025-11-17` (364 days back,
preserving the day of week), a substantial `subjects_with_last_year_evidence` — **a November answer,
computed in August** — and `rows_written_by_asking` unchanged from before the call, because asking a
layer a question records nothing. That last line is §1.4, executable.

- [ ] **Step 1: Write the data-entry table — the STANDING window, which is a setting**

```sql
-- =============================================================================================
-- DE_CATALOG_WINDOW_REQUEST — the window the Catalog is being asked about.
--
-- architecture/THREE_LAYERS.md 4: "The Catalog answers for a REQUESTED window, not for 'now' —
-- that is what lets the Brain plan November in October." The judging frame in
-- SP_SNAPSHOT_KEYWORD_STATE is fixed relative to today's watermark with no calendar input at all,
-- so there was no way to ask.
--
-- THIS IS THE STANDING WINDOW, AND IT IS A SETTING (3.3) — NOT THE PARAMETER OF A QUESTION.
-- It is the window the NIGHTLY SNAPSHOT answers for. A caller who wants a different window calls
-- FN_CATALOG_SEASON_WINDOW(from, to, label) and changes nothing for anybody, because 1.4 says
-- "asking changes nothing". Inserting a row here is a deliberate configuration act by Ori — it
-- changes the window every subject in the account is judged against on the next pass — and it is
-- never how a question is asked. Retire-then-insert, never an edit in place, the same discipline
-- DE_PLAN_CONFIG documents and for the same reason: an edit in place leaves no record of what was
-- set when.
--
-- ONE ACTIVE ROW AT A TIME, AND THE READERS ENFORCE IT RATHER THAN HOPING. The ASSERT below runs
-- when this DDL is DEPLOYED and constrains nothing afterwards, which is exactly when a hand-written
-- INSERT would break it. Two is_active rows would make every reader's `req` return two rows and
-- fan its whole rowset out — silently doubling the grain of V_KEYWORD_SEASON_WINDOW and of
-- SP_SNAPSHOT_CAMPAIGN_STATE's req temp table, both of which flow into a verdict. So every reader
-- resolves the standing request with QUALIFY ROW_NUMBER() ... = 1 and CANNOT fan out whatever this
-- table happens to contain, and acceptance check K11 fails loudly if a second row appears.
--
-- WHEN NO ROW IS ACTIVE the readers fall back to the next holiday occurrence on the house calendar,
-- which is the behaviour they had before this table existed.
-- =============================================================================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_CATALOG_WINDOW_REQUEST`
(
  request_label  STRING  NOT NULL,
  window_from    DATE    NOT NULL,
  window_to      DATE    NOT NULL,
  is_active      BOOL    NOT NULL,
  asked_by       STRING,
  asked_why      STRING,
  updated_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  updated_by     STRING
)
;

ALTER TABLE `onyga-482313.OI.DE_CATALOG_WINDOW_REQUEST` SET OPTIONS(description =
  "The window the Catalog answers for. At most one is_active row; when none is active, readers fall back to the next holiday occurrence on DIM_US_HOLIDAYS. Exists because architecture/THREE_LAYERS.md 4 requires the Catalog to answer for a REQUESTED window — the only way a November answer is readable in October, which 4.1 makes a hard requirement because a campaign enabled on day one of its season has not been running when the season starts. Change a request by retire-then-insert, never by editing a row in place.");

-- Deploy-time check only. It cannot constrain a later INSERT — that is what the readers' QUALIFY
-- and acceptance check K11 are for. Kept because it catches the mistake at the moment the table is
-- first populated, which is the likeliest moment for it.
ASSERT (SELECT COUNTIF(is_active) FROM `onyga-482313.OI.DE_CATALOG_WINDOW_REQUEST`) <= 1
  AS 'at most one active Catalog window request';
```

- [ ] **Step 2: Resolve the standing window in both consumers — with `QUALIFY`, never a bare filter**

**`V_KEYWORD_SEASON_WINDOW` becomes a call to the function.** Its whole body now lives in
`FN_CATALOG_SEASON_WINDOW`, so the view is three lines: resolve the standing window, call the
function at it. A view may pass scalar subqueries as table-function arguments — verified against
`onyga-482313` on 2026-08-25, including subqueries over a real table and over a CTE — so this is one
definition with two entry points and not a copy.

```sql
-- V_KEYWORD_SEASON_WINDOW — the Catalog's seasonal evidence AT THE STANDING WINDOW.
-- The body is FN_CATALOG_SEASON_WINDOW's (Task 5.4 Step 0). This view exists so the nightly
-- snapshot and every existing reader keep one stable name, and so the standing window is resolved
-- in exactly one place.
-- QUALIFY, NOT `WHERE is_active` ALONE. DE_CATALOG_WINDOW_REQUEST's "at most one active row" is
-- asserted when its DDL is deployed and by nothing afterwards, and its documented workflow is a
-- hand-written INSERT. Two active rows under a bare filter would return two rows here and fan this
-- view's whole rowset out — a silent doubling of grain feeding a verdict. ROW_NUMBER makes that
-- impossible whatever the table contains; acceptance K11 makes it loud.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_KEYWORD_SEASON_WINDOW` AS
WITH wm AS (
  SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),
standing AS (
  SELECT window_from, window_to, request_label AS window_label
  FROM `onyga-482313.OI.DE_CATALOG_WINDOW_REQUEST`
  WHERE is_active
  QUALIFY ROW_NUMBER() OVER (ORDER BY updated_at DESC, request_label) = 1
),
-- the fallback is the next holiday occurrence on the house calendar — the behaviour every reader
-- had before DE_CATALOG_WINDOW_REQUEST existed, and still the answer when nothing is set
fallback AS (
  SELECT
    COALESCE((SELECT MIN(h.boost_start) FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
              WHERE h.peak_start > (SELECT d FROM wm)),
             DATE_ADD((SELECT d FROM wm), INTERVAL 1 DAY))                       AS window_from,
    COALESCE((SELECT MIN(COALESCE(h.cooldown_end, DATE_ADD(h.peak_start, INTERVAL 3 DAY)))
              FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
              WHERE h.peak_start > (SELECT d FROM wm)),
             DATE_ADD((SELECT d FROM wm), INTERVAL 28 DAY))                      AS window_to,
    COALESCE((SELECT MIN(h.holiday_name) FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
              WHERE h.peak_start > (SELECT d FROM wm)),
             'next 28 days')                                                     AS window_label
),
resolved AS (
  SELECT * FROM standing
  UNION ALL
  SELECT * FROM fallback WHERE NOT EXISTS (SELECT 1 FROM standing)
)
SELECT * FROM `onyga-482313.OI.FN_CATALOG_SEASON_WINDOW`(
  (SELECT window_from  FROM resolved),
  (SELECT window_to    FROM resolved),
  (SELECT window_label FROM resolved));
```

Apply the **same `standing` / `fallback` / `resolved` shape** to the `req` temp table in
`SP_SNAPSHOT_CAMPAIGN_STATE.sql` — `QUALIFY` included. It resolves the window itself rather than
reading the view, because it needs the dates for its own `ev` scan; what must be identical is the
resolution, not the plumbing.

- [ ] **Step 2b: Add the acceptance check that makes a second active row loud**

Append to `scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql` and add it to the UNION:

```sql
,
k12 AS (
  SELECT 'K11 at most one active Catalog window request (4, and the readers QUALIFY on it)',
         GREATEST((SELECT COUNTIF(is_active) FROM `onyga-482313.OI.DE_CATALOG_WINDOW_REQUEST`) - 1, 0)
       + (SELECT COUNTIF(window_from IS NULL OR window_to IS NULL OR window_to < window_from)
          FROM `onyga-482313.OI.DE_CATALOG_WINDOW_REQUEST` WHERE is_active)
)
```

The `QUALIFY` in the readers means a second row cannot corrupt a verdict; this check means it cannot
sit there unnoticed either, deciding which window the whole account is judged against by the accident
of a `updated_at` ordering.

- [ ] **Step 3: Deploy the chain, and verify the fallback and the fan-out guard — WITHOUT writing a row**

**No step of this task inserts into `DE_CATALOG_WINDOW_REQUEST`.** Step 0 already proved November is
answerable in August, through the function, writing nothing — that is §1.4's requirement and the
whole reason the function exists. What is left to verify here is (a) that the view is unchanged when
nothing is set, and (b) that the `QUALIFY` actually prevents a fan-out. Do the second on a `TMP_`
copy of the resolution, never on the live table.

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tables/DE/DE_CATALOG_WINDOW_REQUEST.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_KEYWORD_SEASON_WINDOW.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_CAMPAIGN_STATE.sql)"
# (a) nothing is set, so the view answers for the house calendar exactly as it did before
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT COUNT(*) rows_,
          COUNT(DISTINCT CONCAT(campaign_id,'|',keyword_id)) subjects,
          ANY_VALUE(window_label) label, ANY_VALUE(window_from) w_from
   FROM \`onyga-482313.OI.V_KEYWORD_SEASON_WINDOW\`"
# (b) the fan-out guard, proved against TWO active rows — on a TMP_ copy of the resolution only
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH two_active AS (
  SELECT 'a' AS request_label, DATE '2026-11-16' AS window_from, TIMESTAMP '2026-08-25 10:00:00' AS updated_at
  UNION ALL
  SELECT 'b', DATE '2026-12-01', TIMESTAMP '2026-08-25 11:00:00')
SELECT COUNT(*) AS rows_the_readers_would_resolve
FROM (SELECT window_from FROM two_active
      QUALIFY ROW_NUMBER() OVER (ORDER BY updated_at DESC, request_label) = 1)"
```

Expected: `rows_ = subjects` and the label naming the next holiday on the house calendar — the view's
behaviour is unchanged while nothing is set, which is what makes this a safe deploy — and
`rows_the_readers_would_resolve = 1`. **A bare `WHERE is_active` returns 2 there**; run it both ways
once so the difference is something you have seen rather than something you were told.

- [ ] **Step 4: Set the standing window — the one deliberate write, and it is Ori's**

Setting the standing window changes what every subject in the account is judged against on the next
pass. It is a configuration act, not a verification step, and this plan does not perform it. Put it
to Ori with the two dates and what changes:

> The Catalog can now be asked about any window without changing anything (`FN_CATALOG_SEASON_WINDOW`).
> Separately, the **standing** window — the one tonight's snapshot judges everything against — is
> still the house calendar's next holiday occurrence. §4.1's lead time says the November answer must
> be readable in October. Do you want the standing window set to the holiday peak now, or left on the
> calendar default until October?

If he says set it, the row is written by him or on his instruction, with his words in `asked_why`:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
UPDATE \`onyga-482313.OI.DE_CATALOG_WINDOW_REQUEST\` SET is_active = FALSE WHERE is_active;
INSERT INTO \`onyga-482313.OI.DE_CATALOG_WINDOW_REQUEST\`
  (request_label, window_from, window_to, is_active, asked_by, asked_why, updated_by)
VALUES ('holiday peak 2026', DATE '2026-11-16', DATE '2026-12-25', TRUE, 'Ori',
        '<Ori''s own words>', 'phase5')"
```

Retire-then-insert in one statement, so no window exists in which two rows are active. Record the
ruling in `docs/superpowers/specs/2026-08-25-gap-closure-measurements.md` either way — "left on the
calendar default" is an answer and must be written down.

- [ ] **Step 5: Register and commit**

Add `FN_CATALOG_SEASON_WINDOW` to `config.yaml` under `functions:` beside `FN_MOVE_CAP` (`type:
table_function`), and `DE_CATALOG_WINDOW_REQUEST` under `tables:` beside the other `DE_` entries.
Its description must say what it is — the **standing** window the nightly snapshot answers for, a
setting per §3.3 — and must point a reader who wants to ask a question at the function instead.
Never appended at the end of the file; re-run the duplicate check from the plan header.

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/functions/FN_CATALOG_SEASON_WINDOW.sql \
        scripts/bigquery/tables/DE/DE_CATALOG_WINDOW_REQUEST.sql \
        scripts/bigquery/views/V_KEYWORD_SEASON_WINDOW.sql \
        scripts/bigquery/procedures/SP_SNAPSHOT_CAMPAIGN_STATE.sql \
        scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql config.yaml
git commit -m "feat(catalog): ask() takes a requested window

Doctrine 4 requires it and 4.1 makes it urgent — a November answer must be
readable in October. ask() is a TABLE FUNCTION and not a toggle, because 1.4 says
asking changes nothing: two callers may hold two windows at once and neither
writes a row. DE_CATALOG_WINDOW_REQUEST is the separate STANDING window the
nightly snapshot answers for, resolved with QUALIFY so a second active row cannot
fan a verdict out, and asserted by acceptance K11."
```

---

### Task 5.5: The seasonal arm of the ladder, and `NOT_WORTH_NOW`

**Files:**
- Modify: `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql` (a new CTE, the `st` CTE's `raw_state` CASE, the appointment expressions, the final `SELECT`)
- Re-deploy: `scripts/bigquery/views/V_KEYWORD_STATE.sql`

- [ ] **Step 1: Join the seasonal window into the procedure — CTE, join AND carry**

Three edits, not one. A CTE that is declared and never joined is invisible to the ladder, and the
ladder runs three CTEs downstream of where the join happens.

**(a)** Add the CTE beside the existing `fb` / `nf` / `gpo` block (`:132-143`). It CROSS JOINs the
procedure's own `today` CTE (`:118`) rather than calling `CURRENT_DATE()` again, and resolves
"is the window still ahead of us" **here**, because `today_d` does not exist until the `fin2` CTE at
`:450` — five CTEs below the ladder that needs the answer:

```sql
  -- ── THE SEASONAL EVIDENCE (2026-08-25, violation 2) ────────────────────────────────────────
  -- Until now the ONLY seasonal field this procedure carried was season_win_prior, selected from
  -- the guard, carried unchanged and published as season_context — read by no CASE arm, no filter,
  -- no verdict and no appointment. `grep -n season` over this file returned three lines and all
  -- three were pass-through. Two full holiday seasons of ads data sat unread while the ladder
  -- condemned seasonal subjects on a trailing average, which doctrine 4 calls the single most
  -- expensive mistake it exists to prevent.
  sw AS (
    SELECT CAST(w.campaign_id AS STRING) AS cid, CAST(w.keyword_id AS STRING) AS kid,
           w.window_from, w.window_to, w.window_label,
           w.ly_clicks, w.ly_spend, w.ly_orders, w.ly_gp,
           SAFE_DIVIDE(w.ly_gp, NULLIF(w.ly_spend, 0))       AS ly_gp_roas,
           SAFE_DIVIDE(w.ly_orders, NULLIF(w.ly_clicks, 0))  AS ly_cvr,
           w.now_clicks, w.now_orders, w.now_spend, w.now_gp,
           SAFE_DIVIDE(w.now_orders, NULLIF(w.now_clicks, 0)) AS now_cvr,
           (w.window_from > t.d)                             AS window_is_ahead
    FROM `onyga-482313.OI.V_KEYWORD_SEASON_WINDOW` w
    CROSS JOIN today t
  ),
```

**(b)** Join it into `calc` (`:304-370`), beside the `fb` / `nf` / `gpo` joins that already sit
there, and publish its columns in `calc`'s select list so they reach `verd` and `st` — both of which
select `*` from their predecessor, so no further edit is needed between `calc` and the final
`SELECT`:

```sql
    LEFT JOIN sw ON sw.cid = b.campaign_id AND sw.kid = b.keyword_id
```

```sql
      -- carried for the ladder arm in Step 2 and the three sentences in Step 3
      sw.window_from  AS season_window_from,
      sw.window_to    AS season_window_to,
      sw.window_label AS season_window_label,
      sw.window_is_ahead AS season_window_is_ahead,
      sw.ly_clicks, sw.ly_spend, sw.ly_orders, sw.ly_gp, sw.ly_gp_roas, sw.ly_cvr,
      sw.now_clicks, sw.now_orders, sw.now_spend, sw.now_gp, sw.now_cvr,
```

**(c)** Confirm the carry before writing the ladder arm:

```bash
cd /Users/ori/Develop/OI
grep -n "season_window_is_ahead\|LEFT JOIN sw\|sw AS (" scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql
```

Expected: three hits at least — the CTE, the join in `calc`, and the carried column.

- [ ] **Step 2: Add the seasonal arm to `raw_state`**

In the `st` CTE, insert this arm immediately **after** the `NO_RECORD` arm added in Phase 2 and **before** every other arm — so a seasonal subject is never reached by `LOSER`, `DEAD` or `FLOOR_PROBATION`:

```sql
      -- ── NOT_WORTH_NOW (2026-08-25, violation 2 / doctrine 4) ────────────────────────────────
      -- A subject that EARNED in this same calendar window last year, above the bar it is judged
      -- against, and is quiet or losing now, is DORMANT — not dead. Doctrine 4: collapsing
      -- NOT_WORTH_NOW into NOT_WORTH is the single most expensive mistake this doctrine exists to
      -- prevent, and 10 measured it: replaying 2025-11-15 with this ladder's own estimator shape
      -- would have condemned 45 of 111 keywords that went on to earn in the peak — a 41%
      -- false-negative rate at an 8.9:1 ratio of profit destroyed to loss avoided.
      -- THE BAR IS THE SAME BAR. This arm does not lower it; it changes which WINDOW it is applied
      -- to, from a trailing average to the window actually being asked about.
      -- THE GATE IS EVIDENCE, NOT OPTIMISM: it needs real settled clicks in last year's window
      -- (the guard's own min_settled_clk of 10), so a single lucky order cannot rescue a subject.
      -- EVERY REFERENCE IS `v.`, THE `st` CTE'S ONLY ALIAS. `st` reads `FROM verd v`; `sw`, `fb` and
      -- `t` are none of them in scope here, which is why Step 1 carries the seasonal columns and the
      -- resolved window_is_ahead boolean all the way down through `calc`. `v.family_bar` is `calc`'s
      -- own COALESCE(fb.keyword_bar, 1.0), so the bar is read once and cannot diverge.
      WHEN COALESCE(v.ly_clicks, 0) >= 10
       AND COALESCE(v.ly_gp_roas, 0) >= COALESCE(v.family_bar, 1.0)
       AND COALESCE(v.season_window_is_ahead, FALSE)
        THEN 'NOT_WORTH_NOW'
```

- [ ] **Step 3: Give it an appointment and a sentence**

**All three are VALUE-form `CASE`s** — each opens `CASE s.state_c` and every existing arm is a bare
literal (`WHEN 'DEAD' THEN …`). An arm written `WHEN s.state_c = 'NOT_WORTH_NOW'` compares a `STRING`
operand against a `BOOL` `WHEN`-expression and the deploy fails. Write the bare literal.

In the `next_check_date` expression, add as the first arm:

```sql
      -- the appointment IS the season: re-read when the window opens, not on a rolling clock
      WHEN 'NOT_WORTH_NOW' THEN s.season_window_from
```

in `next_check_what`:

```sql
      WHEN 'NOT_WORTH_NOW'
        THEN CONCAT('dormant until ', CAST(s.season_window_from AS STRING),
                    ' — it earned in this same window last year; re-read when the window opens')
```

and in `state_reason`:

```sql
      WHEN 'NOT_WORTH_NOW'
        THEN FORMAT('NOT WORTH NOW, not dead. In %s last year (%t to %t) it took %d clicks on $%.2f and returned %.2f gross-profit dollars per ad dollar against a bar of %.2f. It is quiet today because the season is not here, and a silent window is never evidence of worthlessness.',
                    s.season_window_label, s.season_window_from, s.season_window_to,
                    s.ly_clicks, s.ly_spend, s.ly_gp_roas, COALESCE(s.family_bar, 1.0))
```

Step 1(b) already carried every column these three sentences read (`season_window_from`,
`season_window_to`, `season_window_label`, `season_window_is_ahead`, `ly_clicks`, `ly_spend`,
`ly_orders`, `ly_gp`, `ly_gp_roas`, `ly_cvr` and the four `now_*` columns) down to `fin3`. Publish
seven of them on the final `SELECT` — `season_window_from`, `season_window_to`,
`season_window_label`, `ly_clicks`, `ly_spend`, `ly_gp_roas`, `ly_cvr` — which are the seven Step 4
adds to the history table.

- [ ] **Step 4: Add the columns to the history table and re-deploy the view**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
ALTER TABLE \`onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY\`
  ADD COLUMN IF NOT EXISTS season_window_from  DATE,
  ADD COLUMN IF NOT EXISTS season_window_to    DATE,
  ADD COLUMN IF NOT EXISTS season_window_label STRING,
  ADD COLUMN IF NOT EXISTS ly_clicks           INT64,
  ADD COLUMN IF NOT EXISTS ly_spend            FLOAT64,
  ADD COLUMN IF NOT EXISTS ly_gp_roas          FLOAT64,
  ADD COLUMN IF NOT EXISTS ly_cvr              FLOAT64"
```

Append the same seven `ALTER TABLE` lines to the history DDL, then deploy the procedure, call it, and re-deploy `V_KEYWORD_STATE.sql` **in the same step**:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT state, COUNT(*) n, ROUND(SUM(settled_sp90)/90, 2) usd_per_day,
       COUNTIF(next_check_date IS NULL) without_an_appointment
FROM \`onyga-482313.OI.V_KEYWORD_STATE\` GROUP BY 1 ORDER BY n DESC"
```

Expected: a `NOT_WORTH_NOW` bucket appears, drawn from subjects that were previously reaching `LOSER`, `PARKED` or `REPRICE`; `without_an_appointment` is zero on every state except `DEAD`.

- [ ] **Step 4b: RE-RUN THE STATE-LITERAL AUDIT — this is the second new value in `state`**

`NOT_WORTH_NOW` is drawn from subjects that previously read `PARKED`, `LOSER`, `REPRICE` or
`FLOOR_PROBATION`, so every consumer that enumerates `state` literals silently changes what it does
tonight. Run **Task 2.4 Step 7b verbatim** against this second value, and give each of the four
money-or-verdict consumers its explicit ruling in the file:

| consumer | the ruling for `NOT_WORTH_NOW` |
|---|---|
| `SP_MAINTAIN_FAMILY_SEATS.sql:365-372` | it is **not** `LOSER`/`DEAD`, so no seat closes on it, and it is **not** `PARKED`, so no seat lapses. Correct: dormant is not an outcome. Add the comment |
| `V_FAMILY_SEAT_REGISTER.sql:533-539` | add `WHEN state = 'NOT_WORTH_NOW' THEN 'DORMANT'` — otherwise the register shows a seasonal subject under whatever the `ELSE` names |
| `V_PARK_REVERDICT.sql` | **this one moves money.** A subject that flips from `PARKED` to `NOT_WORTH_NOW` silently leaves the park re-verdict population, so nothing revives it. That is correct — its appointment is `season_window_from`, which is a better clock than the revival gate — but it must be written down, and the count must be measured: report how many subjects left the reverdict population on the first night |
| `V_DAILY_BRIEF`, `V_ENGINE_HEALTH`, `V_RUN_SUMMARY`, `V_RUN_UNCHANGED` | reporting only; confirm each has an `ELSE` |

`V_PLAN_WINDOW_JUDGMENT` and `SP_BUILD_NEXT_WEEK_PLAN` are **not** updated here: Task 6.2 maps
`NOT_WORTH_NOW` to `DORMANT_SEASONAL` and `PARK_SEASONAL`. Until then the Brain reads a
`NOT_WORTH_NOW` subject through its own window like any other, which is the pre-existing behaviour
and moves nothing new. Say so in the measurements file rather than leaving the gap implicit.

- [ ] **Step 5: Add `NOT_WORTH_NOW` to the acceptance suite's enumerated set**

In `scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql`, check K03, add `'NOT_WORTH_NOW'` and `'NO_RECORD'` to the `IN (...)` list, then run the suite.

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql)"
```

Expected: twelve rows, all `PASS`.

- [ ] **Step 6: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql \
        scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql \
        scripts/bigquery/views/V_KEYWORD_STATE.sql \
        scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql
git commit -m "feat(catalog): NOT_WORTH_NOW — the ladder reads the season it is being asked about

Closes violation 2. The bar is unchanged; what changes is the window it is applied
to. A subject that earned in this same window last year and is quiet now is
dormant, and its appointment is the day the window opens."
```

---

### Task 5.6: Auto modes and product targets get a seasonal memory

**Files:**
- Create: `scripts/bigquery/views/V_KEYWORD_CONTEXT_GATE_BY_SUBJECT.sql`
- Modify: `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql` (Step 3b — the CTE, the join, the second `NOT_WORTH_NOW` branch)
- Modify: `scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql` (two columns)
- Re-deploy: `scripts/bigquery/views/V_KEYWORD_STATE.sql`
- Modify: `config.yaml` (`views:` — insert immediately after the `V_KEYWORD_CONTEXT_GATE` entry, so the twin sits beside the view it twins)

`V_KEYWORD_CONTEXT_GATE` is one row per bare `keyword_text` by its own header, and explicitly excludes auto clauses, `asin%` / `category%` product targets and `'*'` at lines 102–104, 161–163 and 188–189 — so 66 auto modes and 116 product targets have no seasonal memory of any kind.

**BUILD THE TWIN; DO NOT RE-GRAIN THE LIVE VIEW.** Re-graining `V_KEYWORD_CONTEXT_GATE` onto
`(campaign_id, keyword_id)` would fan out **five live consumers that join it `ON keyword_text`**, two
of them on the money path:

| consumer | join | consequence of a re-grain |
|---|---|---|
| `V_OOB_KEYWORD.sql:1727-1728` | `cg.keyword_text = LOWER(TRIM(o.target_text))` | a ceiling view feeding engine proposals through `T_OOB_KEYWORD` — one text matching N subject rows multiplies proposal rows |
| `V_KEYWORD_LIFT.sql:3485-3486` | same shape | the other ceiling view, same multiplication |
| `V_PARK_REVERDICT.sql:489-490` | `g.keyword_text = LOWER(TRIM(COALESCE(tn.fact_tgt, p.keyword_text)))` | the revival verdict fans out |
| `FN_TARGET_BID_SHADOW.sql:378-385` | `gate` CTE groups by `LOWER(TRIM(keyword_text))` | aggregates, so it survives — but only if `keyword_text` still exists |
| `V_SEASON_NEGATE_CANDIDATES.sql:25-32` | selects `keyword_text` directly | duplicate negate candidates |
| `V_FAMILY_SEAT_REGISTER_acceptance.sql:316` | reads the view | the suite's counts move for no real reason |

Doctrine §2.2 is satisfied by the twin — the subject-grain answer exists and every subject kind is in
it — and the five text-keyed readers keep the account-wide prior over a phrase, which is a different
and still-meaningful thing. Note that `V_OOB_KEYWORD` and `V_KEYWORD_LIFT` already restrict their
gate join with `AND NOT o.is_auto AND NOT o.is_pt` for exactly the grain reason this task is fixing;
migrating them is a separate, later change that must be measured on its own, not a side effect of
this one.

- [ ] **Step 1: Measure the hole**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT is_auto, is_pt, COUNT(*) subjects, ROUND(SUM(settled_sp90)/90, 2) usd_per_day
FROM \`onyga-482313.OI.V_KEYWORD_STATE\` GROUP BY 1,2 ORDER BY usd_per_day DESC"
```

Record the auto and product-target counts and spend — that is the population with no seasonal memory today.

- [ ] **Step 2: Build the subject-grain twin, covering every subject kind**

Copy `scripts/bigquery/views/V_KEYWORD_CONTEXT_GATE.sql` to
`scripts/bigquery/views/V_KEYWORD_CONTEXT_GATE_BY_SUBJECT.sql` and make exactly four changes to the
copy. Every gate rule, threshold, tier and sentence is carried across **verbatim** — the same
requirement, and for the same reason, as Task 5.3's twin:

1. rename the created object to `V_KEYWORD_CONTEXT_GATE_BY_SUBJECT`;
2. read `V_KEYWORD_CONTEXT_LEDGER_BY_SUBJECT` wherever the original reads
   `V_KEYWORD_CONTEXT_LEDGER`, and add `campaign_id, keyword_id` to every `GROUP BY`, `PARTITION BY`
   and join key that today carries `keyword_text` alone;
3. **delete the three exclusion predicates** at lines 102–104, 161–163 and 188–189 (the auto-clause
   list, the `asin%` / `category%` patterns, and the `'*'` sentinel) — they exist only because the
   text-grain ledger pools account-wide, which the subject-grain ledger does not;
4. replace the header's grain line, which today reads `One row per keyword_text, KEYWORD GRAIN ONLY`:

```sql
-- Grain: one row per (campaign_id, keyword_id, occurrence) — EVERY subject kind.
-- WHY A TWIN AND NOT A RE-GRAIN OF V_KEYWORD_CONTEXT_GATE. That view is one row per bare
-- keyword_text and explicitly excluded auto clauses, asin%/category% product targets and the '*'
-- sentinel, so auto modes and product targets had no seasonal memory of any kind while carrying
-- real money. Doctrine 2.1 says an auto mode is a legitimate subject at family x product x mode
-- grain, and 2.2 forbids bare text as a subject at all — which this view satisfies.
-- The TEXT-GRAIN view is left exactly as it is because five live objects join it ON keyword_text
-- (V_OOB_KEYWORD:1727, V_KEYWORD_LIFT:3485, V_PARK_REVERDICT:489, FN_TARGET_BID_SHADOW:383,
-- V_SEASON_NEGATE_CANDIDATES:31), two of them ceiling views on the money path: re-graining it would
-- turn one text into N subject rows and multiply engine proposals. Those five keep the account-wide
-- prior over a phrase, which is a different and still-meaningful thing. Migrating them is a
-- separate change with its own measurement.
-- EVERY GATE RULE IS THE TEXT-GRAIN VIEW'S, VERBATIM. If one moves, both move, in one commit.
```

- [ ] **Step 3: Deploy and confirm the population, and that nothing downstream moved**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_KEYWORD_CONTEXT_GATE_BY_SUBJECT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT COUNT(*) rows_,
          COUNT(DISTINCT CONCAT(campaign_id,'|',keyword_id,'|',occurrence_key)) subjects_occurrences,
          COUNT(DISTINCT CONCAT(campaign_id,'|',keyword_id)) subjects
   FROM \`onyga-482313.OI.V_KEYWORD_CONTEXT_GATE_BY_SUBJECT\`"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT COUNT(*) AS text_grain_rows_unchanged
   FROM \`onyga-482313.OI.V_KEYWORD_CONTEXT_GATE\`"
for v in V_OOB_KEYWORD V_KEYWORD_LIFT V_PARK_REVERDICT V_SEASON_NEGATE_CANDIDATES; do
  bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --dry_run \
    "SELECT 1 FROM \`onyga-482313.OI.$v\` LIMIT 0" >/dev/null 2>&1 \
    && echo "OK   $v" || echo "FAIL $v"
done
```

Expected: `rows_ = subjects_occurrences`; a `subjects` count that now includes auto modes and product
targets (Step 1 recorded how many of each); `text_grain_rows_unchanged` identical to its value before
this task, because nothing about that view was touched; and `OK` on all four readers.

- [ ] **Step 3b: WIRE IT INTO THE LADDER — an object nothing reads is not a memory**

**Without this step Task 5.6 builds a view, registers it, and changes no verdict anywhere.** The
task's stated purpose is that auto modes and product targets *get* a seasonal memory; a memory that
reaches no answer is a table. And the timing matters: **Task 5.7, the very next task, deletes the
only live consumer of the text-grain gate this view twins** — the reprice book's
`V_KEYWORD_CONTEXT_GATE` join and its three `SEASON_BLOCKED` branches. If nothing else reads the
gate family, Phase 5 ends with the season-context ledger wired to nothing at all.

Three edits to `SP_SNAPSHOT_KEYWORD_STATE.sql`, in the same shape Task 5.5 Step 1 used for `sw`.

**(a)** A CTE beside `sw`:

```sql
  -- ── THE OCCURRENCE-GRAIN SEASON GATE (2026-08-25, violation 2) ─────────────────────────────
  -- `sw` answers "did this subject earn in this window LAST year". This answers a different and
  -- narrower question: "is this subject earning RIGHT NOW, inside a season occurrence that has not
  -- closed" — BLOCK_CUT, the gate whose calibration is recorded in
  -- architecture/SEASON_CONTEXT_LEDGER.md §6 (bar 15 settled clicks at GP-ROAS >= 1.0; measured
  -- net +$2,080 strict / +$21,386 wide, protected winners earning ~3x what wrong protections lose).
  -- It reaches the ladder through the SUBJECT-GRAIN twin, so auto modes and product targets are in
  -- it — the text-grain view excluded them outright and they had no seasonal memory of any kind.
  cg AS (
    SELECT CAST(campaign_id AS STRING) AS cid, CAST(keyword_id AS STRING) AS kid,
           gate_action, gate_reason
    FROM `onyga-482313.OI.V_KEYWORD_CONTEXT_GATE_BY_SUBJECT`
    WHERE gate_action = 'BLOCK_CUT'
    -- one row per subject even if the twin ever publishes two occurrences for one: BLOCK_CUT is a
    -- veto, and two vetoes are one veto. QUALIFY rather than ANY_VALUE so the reason belongs to the
    -- occurrence the row names.
    QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id, keyword_id
                               ORDER BY occurrence_start DESC) = 1
  ),
```

**(b)** Join it into `calc` beside `LEFT JOIN sw`, and carry two columns in `calc`'s select list:

```sql
    LEFT JOIN cg ON cg.cid = b.campaign_id AND cg.kid = b.keyword_id
```

```sql
      cg.gate_action AS season_gate_action,
      cg.gate_reason AS season_gate_reason,
```

**(c)** Widen Task 5.5's `NOT_WORTH_NOW` arm with a second, independent branch. Every reference is
`v.`, the `st` CTE's only alias, for the reason Task 5.5 spells out:

```sql
      -- TWO WAYS TO BE DORMANT RATHER THAN DEAD, and they are not the same population.
      --   (1) Task 5.5's branch: it EARNED in this window last year and the window is ahead of us.
      --   (2) This branch: it is earning INSIDE an open season occurrence right now — the ledger's
      --       BLOCK_CUT. Cutting a subject that is currently paying, because a 90-day average
      --       includes eleven months in which its season was not happening, is the same mistake in
      --       a different tense.
      -- BRANCH 2 IS WHAT THE BOOK USED TO DO, AND IT IS WHY TASK 5.7 CAN DELETE IT. The reprice
      -- book turned any cut or pause on a BLOCK_CUT subject into SEASON_BLOCKED, which produced no
      -- bulksheet row and no change-log row — a Pacing object making a Catalog ruling (doctrine 4).
      -- The ruling moves here. If this branch is not shipped BEFORE Task 5.7, those subjects fall
      -- straight through to an executable, irreversible PAUSE.
      WHEN v.season_gate_action = 'BLOCK_CUT' THEN 'NOT_WORTH_NOW'
```

and give it its own sentence in `state_reason`, so a reader can tell the two branches apart — the
existing `NOT_WORTH_NOW` arm from Task 5.5 Step 3 becomes an `IF` on `s.season_gate_action`:

```sql
      WHEN 'NOT_WORTH_NOW' THEN
        IF(s.season_gate_action = 'BLOCK_CUT',
           CONCAT('NOT WORTH NOW, not dead — it is paying inside an open season occurrence: ',
                  COALESCE(s.season_gate_reason, ''),
                  ' A trailing average that spans eleven months without this season is not '
                  'evidence about this season.'),
           FORMAT('NOT WORTH NOW, not dead. In %s last year (%t to %t) ...', ...))
```

(the second argument is Task 5.5 Step 3's sentence, unchanged). `next_check_date` needs no new arm:
`s.season_window_from` is still the right appointment for both branches — branch 2's occurrence is
open now and the next question about it is the next occurrence.

Add the two columns to the history table in the same step, because **every column added to
`FACT_KEYWORD_STATE` must arrive on the history DDL in the same edit** (see acceptance K02b):

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
ALTER TABLE \`onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY\`
  ADD COLUMN IF NOT EXISTS season_gate_action STRING,
  ADD COLUMN IF NOT EXISTS season_gate_reason STRING"
```

Then deploy, run, and confirm the memory reaches a verdict:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT is_auto, is_pt, COUNTIF(season_gate_action = 'BLOCK_CUT') blocked,
       COUNTIF(state = 'NOT_WORTH_NOW') dormant, COUNT(*) subjects
FROM \`onyga-482313.OI.V_KEYWORD_STATE\` GROUP BY 1,2 ORDER BY subjects DESC"
```

Expected: a non-zero `blocked` count on the auto and product-target rows — the population Step 1
measured as having no seasonal memory at all — and every blocked subject reading `NOT_WORTH_NOW`.
**`blocked = 0` everywhere is a legitimate outcome out of season** and must be recorded as such
rather than assumed to be a wiring failure; check it against the text-grain view's own `BLOCK_CUT`
count for the same day before concluding either way.


- [ ] **Step 4: Register and commit**

Insert the entry in `config.yaml` under `views:` **immediately after the `V_KEYWORD_CONTEXT_GATE`
entry** — never appended at the end of the file — with a description saying it is the subject-grain
twin covering every subject kind, that the text-grain view is deliberately unchanged because five
live objects join it on `keyword_text`, and that both views' gate rules must move together. Verify
with the `config.yaml` duplicate check in the plan header, then:

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_KEYWORD_CONTEXT_GATE_BY_SUBJECT.sql \
        scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql \
        scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql \
        scripts/bigquery/views/V_KEYWORD_STATE.sql config.yaml \
        architecture/THREE_LAYERS.md
git commit -m "feat(catalog): auto modes and product targets get a seasonal memory

Closes violation 2 with Task 5.5. A subject-grain twin of the season gate, WIRED
INTO THE LADDER — the text-grain view excluded auto clauses and product targets
outright, so subjects carrying real money had no seasonal record at all, and a
twin nothing read would have changed no verdict. Built as a twin, not a re-grain:
five live objects join the text-grain view ON keyword_text, two of them ceiling
views on the money path. The BLOCK_CUT ruling moves from the reprice book to the
ladder here, which is what makes Task 5.7's deletion safe."
```

---

### Task 5.7: Delete the book's seasonal arm — the Catalog owns it now

**Files:**
- Modify: `tools/build_reprice_bulksheet.py:583` (the join), `:718` (`block_cut_reason`), `:901-902`, `:933-934`, `:976-977` (the `SEASON_BLOCKED` arms)
- Modify: `tools/tests/test_reprice_precedence.py` (add the assertion)

The book joins `V_KEYWORD_CONTEXT_GATE`, exposes `gate_reason` as `block_cut_reason`, and turns any cut or pause into `SEASON_BLOCKED` — a Pacing/execution object making the §4 `NOT_WORTH_NOW` distinction the Catalog must own. Once the Catalog answers seasonally there must not be two authorities.

- [ ] **Step 0: PROVE THE VETO MOVED BEFORE YOU DELETE IT — this task removes a live pause veto**

**`SEASON_BLOCKED` is not a label today, it is a suppression.** `build_reprice_bulksheet.py:836`
lists it as *"Book-visible only"*, so at `:900-902` a `LOSER` keyword carrying a `block_cut_reason`
produces **no bulksheet row and no change-log row** — the season ledger stops the pause. Delete the
arm and that subject falls straight to `return 'PAUSE', 'PAUSE', ...` at `:903` and becomes an
executable, irreversible row. The HIGH-confidence gate on the book's `PAUSE` does not arrive until
Task 7.5, two phases away, so **nothing else is standing between those subjects and a pause tonight**
except Task 5.6 Step 3b's `BLOCK_CUT` branch.

This plan's own ordering rule is *safety before throughput — never make a wrong action happen faster
before the safety fix that governs it*. So measure the handover rather than assume it:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH blocked AS (
  SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid
  FROM \`onyga-482313.OI.V_KEYWORD_CONTEXT_GATE_BY_SUBJECT\` WHERE gate_action = 'BLOCK_CUT'),
st AS (
  SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid, state, settled_sp90
  FROM \`onyga-482313.OI.V_KEYWORD_STATE\`)
SELECT COUNT(*)                                                     AS block_cut_subjects,
       COUNTIF(st.state = 'NOT_WORTH_NOW')                          AS now_dormant,
       COUNTIF(st.state IN ('LOSER','DEAD'))                        AS would_become_a_pause,
       ROUND(SUM(IF(st.state IN ('LOSER','DEAD'), st.settled_sp90, 0)) / 90, 2) AS usd_per_day_at_risk
FROM blocked LEFT JOIN st USING (cid, kid)"
```

Expected: **`would_become_a_pause = 0`**, because Task 5.6 Step 3b's second `NOT_WORTH_NOW` branch
takes precedence over `LOSER` and `DEAD` in the ladder. Record `block_cut_subjects` and `now_dormant`
in the measurements file — that pair is the evidence the ruling moved from the book to the Catalog
rather than simply disappearing.

**`would_become_a_pause > 0` is stop-the-line.** It means the population the book was protecting is
larger than the one the ladder now protects, and deleting the arm would turn each of those subjects
into an executable pause on a keyword that is paying inside an open season. Do not proceed: name the
subjects, widen Task 5.6's branch to cover them, and re-run this query until it reads zero.

- [ ] **Step 1: Write the failing test**

Append to `tools/tests/test_reprice_precedence.py`:

```python
def test_the_book_no_longer_makes_the_seasonal_decision():
    """Doctrine 4: NOT_WORTH_NOW is a Catalog verdict. The book turning a cut into SEASON_BLOCKED
    made a second authority for the same ruling, in an execution object."""
    assert 'SEASON_BLOCKED' not in SRC
    assert 'block_cut_reason' not in SRC


def test_the_book_reads_the_catalog_seasonal_verdict_instead():
    assert "'NOT_WORTH_NOW'" in SRC
```

Run it:

```bash
cd /Users/ori/Develop/OI
/usr/local/bin/python3 -m pytest tools/tests/test_reprice_precedence.py -q -k season
```

Expected: FAIL — `SEASON_BLOCKED` is still in the source.

- [ ] **Step 2: Remove the arm and read the verdict instead**

Delete the `V_KEYWORD_CONTEXT_GATE` join at line 583 and the `gate_reason AS block_cut_reason` projection at line 718. Delete all three `SEASON_BLOCKED` branches. In their place, add one exclusion beside the others near the top of the disposition function:

```python
    # ── THE SEASON IS A CATALOG VERDICT, NOT A BOOK RULE (2026-08-25) ─────────────────────────
    # This book used to join V_KEYWORD_CONTEXT_GATE and turn any cut or pause into SEASON_BLOCKED,
    # which made an execution object the second authority on doctrine 4's NOT_WORTH_NOW distinction.
    # The ladder now answers seasonally, so the book simply reads the answer.
    if state == 'NOT_WORTH_NOW':
        return ('SEASONAL_HOLD', None, None,
                [f"the keyword state says this is dormant, not dead: {r.get('state_reason') or ''}"],
                bits)
```

and add a story sentence for it beside the others:

```python
    elif disp == 'SEASONAL_HOLD':
        move = (f"no book row — the keyword state answers NOT WORTH NOW for this window and WORTH "
                f"for its season. It is held at its current price until "
                f"{r.get('next_check_date')}, when the window opens. Dormant is not dead")
```

- [ ] **Step 3: Run the tests and commit**

```bash
cd /Users/ori/Develop/OI
/usr/local/bin/python3 -m pytest tools/tests/ -q
git add tools/build_reprice_bulksheet.py tools/tests/test_reprice_precedence.py
git commit -m "refactor(books): the seasonal decision moves from the book to the Catalog

The book made doctrine 4's NOT_WORTH_NOW call in an execution object, which is a
second authority for one ruling. It now reads the ladder's verdict."
```

Expected: all tests PASS.

---

### Task 5.8: The seasonal replay, green

**Files:**
- Modify: `scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql` (one new check)

- [ ] **Step 1: Add the replay check**

Append a CTE and add it to the final UNION:

```sql
,
-- K12 THE SEASON DOOR, REPLAYED. Doctrine 10 measured what this ladder's own estimator shape would
-- have said on the eve of last season: replaying 2025-11-15 with a fixed 90-day trailing frame
-- condemned 45 of 111 keywords that went on to EARN in the 2025-11-16..12-25 peak — a 41%
-- false-negative rate, at an 8.9:1 ratio of profit destroyed to loss avoided.
-- This check re-runs that replay with the SEASONAL arm in place: a subject with at least 10 settled
-- clicks in the same window a year earlier, returning at or above 1.0, must not be condemned by the
-- trailing frame alone. The bar of 1.0 is deliberately CONSERVATIVE — today's family bars run 0.60
-- to 1.00, so 1.0 condemns FEWER keywords than the live bar would.
k11 AS (
  SELECT 'K12 the season door: a subject that earned in this window last year is not condemned on a trailing average',
         (SELECT COUNT(*)
          FROM `onyga-482313.OI.V_KEYWORD_STATE` ks
          JOIN `onyga-482313.OI.V_KEYWORD_SEASON_WINDOW` sw
            ON sw.campaign_id = ks.campaign_id AND sw.keyword_id = ks.keyword_id
          WHERE sw.ly_clicks >= 10
            AND SAFE_DIVIDE(sw.ly_gp, NULLIF(sw.ly_spend, 0)) >= 1.0
            AND sw.window_from > CURRENT_DATE('America/Los_Angeles')
            AND ks.state IN ('DEAD', 'LOSER', 'FLOOR_PROBATION'))
)
```

- [ ] **Step 2: Run it, and re-run the historical replay for the record**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql)"
```

Expected: thirteen rows, all `PASS`. Then re-run the baseline's own season-door query from Task 5.1 Step 2 and record the new false-negative rate beside the measured 41% — that comparison is the phase's evidence, and it belongs in the doctrine's §10.2 table when Phase 13 updates the changelog.

- [ ] **Step 3: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql
git commit -m "test(catalog): K12 replays the season door against the seasonal ladder"
```

---
## Phase 6 — The Brain stops saying "nothing to do", and funds what it demands

**Closes:** violations 7, 8, 9, 11 and 14.

**Why five violations in one phase.** They share the same two objects (`V_PLAN_WINDOW_JUDGMENT.sql` and `SP_BUILD_NEXT_WEEK_PLAN.sql`), the same acceptance suites, and — in the case of 9 and 14 — the same assertion relaxations: **a park cannot carry a date today**, because `verdict_date` is written only for seats (`SP_BUILD_NEXT_WEEK_PLAN.sql:396`) and its absence off-seat is asserted twice, at `SP:648-650` and `FACT_PLAN_NEXT_WEEK_acceptance` C10.

It comes after Phases 4–5 because 9 is dependency-blocked: the Brain cannot express `NOT_WORTH_NOW` until the Catalog answers seasonally and answers for a campaign. It comes before the throughput phases because every violation here is safety-positive — it removes the forbidden limbo (189 of 365 live-plan rows, 51.8%, sit at `NOT_SERVING`/`NONE`), it funds fewer and fuller questions (40 of 53 seats underfunded; 27 seats buying under 25% of the evidence they demand — 9.1 clicks bought against 106 needed, 196 days at the granted rate against 9.9 granted, $1,418.58 of shortfall), and it stops the one-way door opening on dormancy. Violation 11 rides along because it is the same expression in the same view and 56 of 66 candidates are currently unordered.

**Unblocks:** Phase 8's `LEAN_IN` (the good side's mask and the P-4 assert are read here first); Phase 7's CLOSE arm needs the Brain's revisit/reopen column; the boost-allowance ruling needs `V_PLAN_SCORECARD`, built here.

**Size:** XL — 3–4 weeks. One DDL change, two large object rewrites, four acceptance suites, and two of Ori's open rulings carried as declared constants.

---

### Task 6.1: Five red measurements in one query

- [ ] **Step 1: Run it**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH p AS (
  SELECT * FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
  WHERE as_of = (SELECT MAX(as_of) FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`) AND is_live_plan)
SELECT
  COUNTIF(verdict = 'NOT_SERVING' AND move = 'NONE')                       AS r1_forbidden_limbo,
  COUNT(*)                                                                 AS r1_live_rows,
  COUNTIF(rank_is_degenerate)                                              AS r2_unordered_candidates,
  COUNTIF(is_candidate)                                                    AS r2_candidates,
  ROUND(CORR(seat_cost_per_day, SAFE_DIVIDE(w_sp, window_days)), 3)        AS r3_seat_is_last_window,
  ROUND(AVG(SAFE_DIVIDE(seat_cost_per_day, NULLIF(w_sp / window_days, 0))), 3) AS r3_mean_ratio,
  COUNTIF(seat_no IS NOT NULL)                                             AS r4_seats,
  ROUND(SUM(IF(seat_no IS NOT NULL, seat_cost_per_day, 0)), 2)             AS r4_seat_usd_per_day,
  COUNTIF(seat_no IS NULL AND verdict_date IS NOT NULL)                    AS r5_unseated_with_a_date
FROM p"
```

Expected, on the 2026-08-24 partition: `r1_forbidden_limbo` 189 of 365 live rows (51.8%); `r2_unordered_candidates` 56 of 66; `r3_seat_is_last_window` 0.995 with `r3_mean_ratio` 0.973; `r4_seats` 53 holding $195.07/day; `r5_unseated_with_a_date` 0 — the last is the *assertion* that makes a park unable to carry a date, not a defect count. Record what you measure.

- [ ] **Step 2: Price the limbo**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH p AS (
  SELECT * FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
  WHERE as_of = (SELECT MAX(as_of) FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`) AND is_live_plan)
SELECT ladder_state, COUNT(*) n, ROUND(SUM(w_sp / window_days), 2) usd_per_day,
       ROUND(SUM(GREATEST(w_sp / window_days
                          - SAFE_DIVIDE(w_gp_corrected / window_days, NULLIF(family_bar, 0)), 0)), 2)
         AS one_sided_excess_usd_per_day,
       ROUND(SUM(w_sp / window_days
                 - SAFE_DIVIDE(w_gp_corrected / window_days, NULLIF(family_bar, 0))), 2)
         AS net_usd_per_day
FROM p WHERE verdict = 'NOT_SERVING' AND move = 'NONE'
GROUP BY 1 ORDER BY usd_per_day DESC"
```

**Report the net beside the one-sided figure — §6.3's standing rule.** Any sum of `GREATEST(actual − target, 0)` is positive under ordinary dispersion even in a healthy population; the doctrine's "$210/day over bar" claim died on exactly this. Measured 2026-08-24: 17 HARVEST conclusive losers at $41.61/day of spend and $20.36/day of excess, plus 30 subjects with seasonal history holding $4,943 of last-season net.

- [ ] **Step 3: Record the measurement and commit it**

Every red measurement in this plan is a number the green run is compared against, so it is written
down rather than remembered. Append what you measured — the query, the date, and the count — to the
running record, creating the file on the first task that reaches this step:

```bash
cd /Users/ori/Develop/OI
mkdir -p docs/superpowers/specs
cat >> docs/superpowers/specs/2026-08-25-gap-closure-measurements.md <<'EOF'

## Task 6.1 — measured YYYY-MM-DD

Replace the date above with the date you ran it, and paste below: the query you ran (unchanged from
the task), and its output. Do not summarise the output — the point of this file is that a re-run is
a re-run and not a fresh argument, which is the same reason
docs/superpowers/specs/2026-08-24-three-layers-baseline.md exists.
EOF
git add docs/superpowers/specs/2026-08-25-gap-closure-measurements.md
git commit -m "measure(task 6.1): record the red measurement before the fix

The number the green run is compared against, written down rather than remembered."
```

---

### Task 6.2 (violation 7): an empty window yields the Catalog's answer, never limbo

**Files:**
- Modify: `scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql:454-456` (the Catalog columns read), `:550-575` (the verdict CASE), `:636-638` (`is_candidate`), `:705-707` and `:742-743` (the sentences)
- Modify: `scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql:125-127` (the mirrored candidacy), `:344-366` (the move CASE)
- Modify: `scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql` C06, C13 **and C14** (C14 enumerates the legal moves a second time, split by seat)

- [ ] **Step 1: Read the Catalog columns that are already on the joined row**

The `base` CTE selects nine measurement columns from `FACT_KEYWORD_STATE` and drops `gp_per_click` unused, while `state`, `se_eff`, `settled_roas90`, `next_check_date` and `season_context` sit unread on the same row. Replace the two lines at 454–456 with:

```sql
    ks.state AS ladder_state, ks.current_bid, ks.affordable_bid, ks.bid_floor,
    ks.gp_per_click, ks.settled_ord90, ks.settled_gp90, ks.settled_sp90,
    -- 2026-08-25 (violation 7): the Catalog's own answer, free on a row this view already joins.
    -- The Brain judged a keyword on its own window alone and fell through to NOT_SERVING on a quiet
    -- one — the "nothing to do" state doctrine 3 forbids outright, and 51.8% of the live plan.
    ks.settled_clk90, ks.settled_roas90, ks.se_eff, ks.next_check_date, ks.season_context,
    ks.affordable_cpc, ks.state_reason AS catalog_reason,
```

**`catalog_reason` and `next_check_date` are read by Step 4's sentences, which sit in the same
enclosing `SELECT` as the outer column list, so they must be republished there too.** This view's
outer `SELECT` (`:641-667`) is an explicit list, not a `SELECT *` — a column that reaches `final` and
is not named on that list does not exist to any consumer, and `SP_BUILD_NEXT_WEEK_PLAN` reads the
**view**. Add to it, in this step:

```sql
  f.catalog_reason, f.next_check_date, f.ladder_state AS catalog_state, f.season_context,
```

(`ladder_state` is already published under that name; the alias above is only if the view does not
already carry it — check before adding a duplicate column name, which fails the deploy.) Task 6.4
Step 2b adds the rest of the set and explains the trap in full.

- [ ] **Step 2: Replace the bare `ELSE 'NOT_SERVING'`**

The verdict CASE today ends with `ELSE 'NOT_SERVING'`. Replace that single line with:

```sql
      -- ── AN EMPTY WINDOW YIELDS THE CATALOG'S ANSWER (2026-08-25, violation 7) ──────────────
      -- Doctrine 3: every keyword is either ANSWERED or has an OPEN QUESTION. "Nothing to do" is
      -- not a legal state — it is how keywords sit in limbo, spending or dormant, owned by nobody.
      -- Measured before this change: 189 of 365 live-plan rows, 51.8% of the plan.
      -- ORDER MATTERS. The seasonal answer is tested first, because doctrine 4 says collapsing
      -- NOT_WORTH_NOW into a condemnation is the most expensive mistake the doctrine exists to
      -- prevent, and a dormant seasonal subject is exactly the kind of thing a quiet window hides.
      WHEN s.ladder_state = 'NOT_WORTH_NOW'                    THEN 'DORMANT_SEASONAL'
      WHEN s.ladder_state IN ('NO_RECORD', 'PENDING_SETTLE',
                              'REVIVED_SETTLING', 'TRIAL')     THEN 'NO_EVIDENCE_YET'
      WHEN s.ladder_state IN ('LOSER', 'DEAD', 'FLOOR_PROBATION',
                              'REPRICE')                       THEN 'CATALOG_SAYS_REPAIR'
      WHEN s.ladder_state IN ('WINNER', 'PACED_WINNER', 'AT_BAR') THEN 'CATALOG_SAYS_EARNING'
      -- a subject with no Catalog row at all is the one honest remaining unknown, and it is now
      -- rare by construction: Phase 2 admits everything that spends.
      ELSE 'NO_CATALOG_ROW'
```

- [ ] **Step 3: Make every one of them a candidate except the earning ones**

`is_candidate` at lines 636–638 today excludes `NOT_SERVING` unless probe-nominated. Replace with:

```sql
    -- 2026-08-25 (violation 7): candidacy no longer turns on whether the WINDOW spoke. A quiet
    -- window on a subject the Catalog has condemned is the most actionable row in the plan, not the
    -- least; the old rule made it the only row nobody owned.
    (IF(j.verdict IN ('GOOD','HELD_UNSETTLED','GRACE'), 'GOOD', 'NOT_GOOD') = 'NOT_GOOD'
     AND NOT j.holdout
     AND j.verdict != 'CATALOG_SAYS_EARNING')                                AS is_candidate
```

- [ ] **Step 4: Give each new verdict its sentence**

Replace the `NOT_SERVING` arm of the sentence CASE with five arms:

```sql
    WHEN 'DORMANT_SEASONAL' THEN FORMAT(
      'DORMANT, NOT DEAD — no spend and no clicks from %t to %t, and the keyword state says why: %s The plan parks it at its floor and revisits on %t.',
      f.window_from, f.window_to, COALESCE(f.catalog_reason, ''), f.next_check_date)
    WHEN 'NO_EVIDENCE_YET' THEN FORMAT(
      'NO EVIDENCE YET — no spend and no clicks from %t to %t, and the keyword state has not been able to judge it either: %s Buying an answer is the only thing that changes that.',
      f.window_from, f.window_to, COALESCE(f.catalog_reason, ''))
    WHEN 'CATALOG_SAYS_REPAIR' THEN FORMAT(
      'THE WINDOW WAS QUIET, THE RECORD IS NOT — no spend and no clicks from %t to %t, but the keyword state has already answered this keyword: %s A silent window is never evidence of worthlessness, and it is never a reason to leave a known answer unexecuted either.',
      f.window_from, f.window_to, COALESCE(f.catalog_reason, ''))
    WHEN 'CATALOG_SAYS_EARNING' THEN FORMAT(
      'QUIET AND EARNING — no spend and no clicks from %t to %t, and the keyword state has it above its bar on its settled record. Nothing is repaired here; it holds its price.',
      f.window_from, f.window_to)
    WHEN 'NO_CATALOG_ROW' THEN FORMAT(
      'NO ANSWER ANYWHERE — no spend and no clicks from %t to %t, and no keyword-state row either. This should be rare; if it is not, the Catalog universe has a hole and that is the thing to fix.',
      f.window_from, f.window_to)
```

and replace the seat clause for a non-candidate. **Read the block before editing it — two traps.**

The `seat_clause` `CASE` lives at `V_PLAN_WINDOW_JUDGMENT.sql:725-758`, inside
`SELECT f2.*, CASE ... END AS seat_clause FROM final f2`. `f` is the alias of the **enclosing**
derived table (`) f` at `:759`) and is **not in scope** inside it: writing `f.is_candidate` there
fails the deploy with `Unrecognized name: f`. Every reference in that block is `f2.`. And the arm
being replaced is already `WHEN NOT f2.is_candidate THEN ...`, so an `IF(is_candidate, A, B)` placed
inside it can only ever reach `B` — branch `A` would be unreachable by construction. Replace the
**sentence only**, keeping the arm's own predicate as the condition:

```sql
      -- 2026-08-25 (violation 7): the only rows that now reach this arm are the ones the Catalog
      -- has above their bar on a settled record. There is no "nobody owns this" row left.
      WHEN NOT f2.is_candidate THEN
        'It is earning on its settled record, so the plan leaves it alone and proposes no move (P-4).'
```

**And delete the arm below it.** `WHEN f2.verdict = 'NOT_SERVING' THEN ...` at `:747-752` is dead the
moment Step 2 removes that verdict from the `CASE` — it can never match, and a sentence that can
never print is a sentence nobody maintains. Its content is now carried by the five arms in Step 4.

- [ ] **Step 5: Mirror both changes in the builder**

`SP_BUILD_NEXT_WEEK_PLAN.sql:125-127` re-derives `is_candidate` itself rather than consuming the
view's column, and C13 asserts the two agree row for row.

**DO NOT PASTE STEP 3'S TEXT OVER IT. Swap the third conjunct alone.** The builder's expression is

```sql
         (IF(pl = 'B', j.side_b, j.side_a) = 'NOT_GOOD'
          AND NOT j.holdout
          AND (j.verdict != 'NOT_SERVING' OR j.is_probe))                       AS is_cand,
```

and its first conjunct is **per-plan on purpose**: the temp table is built `FROM j, UNNEST(['A','B'])
AS pl`, and plan A is the free shadow allocation that takes the ladder's side rather than rule B's
(P-9). Step 3's text hard-codes the side-B form, so a literal replacement would make plan A's
candidacy identical to the live plan's and silently destroy the counterfactual `V_PLAN_SCORECARD`
(Task 6.10) is being built to read. **C13 cannot catch it** — it joins only the live-plan rows to the
view. The correct edit is one line:

```sql
         (IF(pl = 'B', j.side_b, j.side_a) = 'NOT_GOOD'
          AND NOT j.holdout
          -- 2026-08-25 (violation 7): candidacy no longer turns on whether the WINDOW spoke. Only
          -- the earning rows are excluded. The FIRST conjunct stays per-plan: plan A is the shadow
          -- allocation and must keep taking the ladder's side, or the counterfactual is gone.
          AND j.verdict != 'CATALOG_SAYS_EARNING')                              AS is_cand,
```

Then extend the move CASE at lines 344–366 by inserting these arms immediately **above** the `WHEN r2.ladder_state = 'DEAD' THEN 'PAUSE'` arm:

```sql
      -- 2026-08-25 (violations 7 and 9): a dormant seasonal subject is PARKED with a revisit date,
      -- never paused. Doctrine 4: NOT_WORTH_NOW permits a park at the floor and forbids a pause.
      WHEN r2.verdict = 'DORMANT_SEASONAL'                              THEN 'PARK_SEASONAL'
```

- [ ] **Step 6: Widen the two acceptance checks in the same change**

**The legal moves are enumerated TWICE in that file, and widening one of them is how the suite goes
red on a change that is correct.** C06 at line 108 lists them once; **C14 at lines 178-183 lists them
again**, split by seat:

```sql
         COUNTIF(is_candidate AND seat_no IS NULL AND move NOT IN ('PARK','HOLD_AT_PARK','PAUSE'))
       + COUNTIF(is_candidate AND seat_no IS NOT NULL AND move NOT IN ('REPRICE','HOLD_AT_PRICE'))
```

`PARK_SEASONAL` is issued **unseated** and `TEST_RETEST` only when `m.seat_no IS NOT NULL`, so C14
goes red on the very first task that ships one — and the plan's own rule on a red check ("fix the
expression, never the check") would send an engineer hunting a defect that is not there. Widen both.

C06's `NOT IN (...)` list becomes:

```sql
         COUNTIF(is_candidate AND move NOT IN ('REPRICE','HOLD_AT_PRICE','PARK','HOLD_AT_PARK',
                                               'PAUSE','PARK_SEASONAL','TEST_RETEST'))
```

and C14's two clauses become:

```sql
         -- 2026-08-25: PARK_SEASONAL is a queue position with a date on it (a dormant subject holds
         -- no seat); TEST_RETEST is a SEAT, because a funded re-test buys clicks and takes allowance
         -- like any other question. The two lists are not interchangeable, which is why C14 exists
         -- beside C06 rather than duplicating it.
         COUNTIF(is_candidate AND seat_no IS NULL
                 AND move NOT IN ('PARK','HOLD_AT_PARK','PAUSE','PARK_SEASONAL'))
       + COUNTIF(is_candidate AND seat_no IS NOT NULL
                 AND move NOT IN ('REPRICE','HOLD_AT_PRICE','TEST_RETEST'))
```

C13 must keep comparing the view and the plan row for row and needs no edit.
(`TEST_RETEST` is added by Task 6.7 in this same phase; enumerating it in both places now avoids a
second edit to the same two lines.)

- [ ] **Step 7: Deploy the chain and verify the limbo is gone**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT verdict, move, COUNT(*) n, ROUND(SUM(w_sp / window_days), 2) usd_per_day
FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
WHERE as_of = (SELECT MAX(as_of) FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`) AND is_live_plan
GROUP BY 1,2 ORDER BY n DESC"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql)"
```

Expected: **no row reads `NOT_SERVING`**, every verdict is one of the five new ones or an existing one, and all 25 acceptance checks read `PASS`. If C13 goes red, the builder's mirrored `is_candidate` does not match the view's — fix the expression, never the check.

- [ ] **Step 8: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql \
        scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql \
        scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql
git commit -m "feat(brain): an empty window yields the Catalog's answer, never limbo

Closes violation 7. NOT_SERVING was the bare ELSE of the verdict CASE and 51.8% of
the live plan — the 'nothing to do' state doctrine 3 forbids. The Catalog columns
it now consults were already on the joined row and simply unselected."
```

---

### Task 6.3 (violation 11): rank on the gross-profit shortfall

**Files:**
- Modify: `scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql:625-632`
- Modify: `scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql:187-195`
- Modify: `scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql` C21

The published product form cancels spend identically on every row — the view's own header proves it at lines 195–218 — which is why 56 of 66 candidates score exactly zero and $72.90/day of subjects compete unordered. The alternative Ori already wrote into that header at lines 216–218 is the gross-profit **shortfall** per day, which does not cancel.

- [ ] **Step 0: RULE ON P-7 FIRST — the formula is named as Ori's in the code**

**Do not write Step 1 before this step returns an answer.** `V_PLAN_WINDOW_JUDGMENT.sql:214-218`
says, in the view's own header:

> *The FORMULA is Ori's ruling and is untouched here; what changed is that it is now described
> correctly. Ori rules whether to park the no-sale keywords, or to make "dollars at stake" real by
> ranking on the gross-profit SHORTFALL per day (spend/day x (bar − return)/bar), which does not
> cancel; until he does, the ordering is corrected gross profit and then falls through to clicks and
> the key.*

This is not one of §6.4's four open rulings, so it is not carried as a declared constant — but it is
the same class of decision as the P-4 collision in Task 8.5, and this plan does not settle one of
those on its own authority either. Steps 1–5 implement **one** of the two branches Ori named. Put
both in front of him with the money attached:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT rank_is_degenerate,
       COUNT(*) candidates,
       ROUND(SUM(rank_dollars_at_stake), 2) usd_per_day,
       COUNTIF(w_ord = 0)  AS no_sale_in_the_window,
       COUNTIF(w_ord >= 1) AS sold_something
FROM \`onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT\`
WHERE is_candidate GROUP BY 1"
```

Then ask him, in these words:

> Two branches, both yours, both in the view header. **(a) Park the no-sale keywords** — they leave
> the queue entirely and the product form stays. **(b) Rank on the gross-profit shortfall per day**
> — they stay in the queue and are ordered by how much money they are losing per day relative to
> the bar. Steps 1–5 below build (b). If you rule (a), stop: the change is a candidacy filter in
> the `is_candidate` expression, not a new score, C21 stays exactly as it is, and this task is
> rewritten before anything is deployed.

Record the ruling in the measurements file with the query output beside it, so the reason is
readable later. **Both factors stay published either way** — that part is not in dispute and is what
lets Ori order by either alone while the ruling is fresh.

- [ ] **Step 1: Replace the score**

Lines 625–632 today publish `rank_dollars_at_stake`, `rank_closeness` and their product. Replace the `rank_score` expression only, keeping both factors published:

```sql
    (j.w_sp / j.window_days)                                                 AS rank_dollars_at_stake,
    COALESCE(SAFE_DIVIDE(j.ret_corrected, NULLIF(j.family_bar, 0)), 0)       AS rank_closeness,
    -- ── THE GROSS-PROFIT SHORTFALL PER DAY (2026-08-25, violation 11) ───────────────────────
    -- P-7's published product is dollars-at-stake x closeness, and because return = gp / spend the
    -- spend CANCELS identically on every row (this view's own header proves it): the queue was
    -- ordered by corrected gross profit alone, and 56 of 66 candidates scored exactly zero because
    -- they had none. This is the alternative Ori wrote into that same header: spend per day times
    -- how far SHORT of the bar the return falls. It does not cancel, it is zero only at the bar,
    -- and it is larger for a subject losing more money faster — which is what a repair queue is for.
    --   shortfall/day = spend/day x (bar - return) / bar
    -- A subject ABOVE its bar scores zero or below and cannot outrank one below it.
    -- Phase 10 Task 10.6 re-bases this on expected profit contribution at the marginal ceiling,
    -- measured against the bar and discounted by confidence, which is doctrine 2.4's ordering with
    -- the one arithmetic correction Task 12.3's header derives (the cost term carries the bar, or
    -- the score is negative for every subject whose ceiling exceeds its gross profit per click —
    -- 260 of 359 on 2026-08-24). This is the buildable interim until then.
    (j.w_sp / j.window_days)
      * COALESCE(SAFE_DIVIDE(NULLIF(j.family_bar, 0) - COALESCE(j.ret_corrected, 0),
                             NULLIF(j.family_bar, 0)), 0)                    AS rank_score,
```

- [ ] **Step 2: The builder's mirrored ORDER BY needs no change**

`SP_BUILD_NEXT_WEEK_PLAN.sql:187-195` orders by `r2.rank_score DESC, r2.w_clk DESC, r2.campaign_id, r2.keyword_id` — it consumes the view's column, so the new score flows through. **Confirm it, do not assume it:**

```bash
cd /Users/ori/Develop/OI
sed -n '185,196p' scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql
```

Expected: the `WINDOW w AS (... ORDER BY r2.rank_score DESC ...)` clause, reading the column and not recomputing it. If it recomputes, replace the recomputation with the identical expression from Step 1.

- [ ] **Step 3: Re-base acceptance C21**

C21 today asserts `ABS(rank_score - rank_dollars_at_stake * rank_closeness) <= 1e-9` — it pins the product form and will go red. Replace it with:

```sql
c21 AS (
  -- 2026-08-25 (violation 11): the score is the gross-profit SHORTFALL per day, not the product of
  -- the two published factors. The product cancelled spend identically on every row (see the view
  -- header) and left 85% of candidates tied at zero. Both factors are still published so Ori can
  -- order by either alone; this check pins the score to the shortfall it now is.
  SELECT 'C21 rank_score is spend/day x how far short of the bar the return falls (P-7, restated)',
         COUNTIF(ABS(rank_score
                     - rank_dollars_at_stake
                       * COALESCE(SAFE_DIVIDE(NULLIF(family_bar, 0) - COALESCE(ret_corrected, 0),
                                              NULLIF(family_bar, 0)), 0)) > 1e-9)
  FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`
),
```

- [ ] **Step 4: Deploy and verify the queue is ordered**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT COUNTIF(is_candidate) candidates, COUNTIF(rank_is_degenerate) still_tied_at_zero
   FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
   WHERE as_of = (SELECT MAX(as_of) FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`) AND is_live_plan"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql)"
```

Expected: `still_tied_at_zero` collapses from 56 to a small number (only subjects sitting exactly at their bar, which is a real tie), and every acceptance row reads `PASS`.

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql \
        scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql
git commit -m "feat(brain): rank on the gross-profit shortfall per day

Closes violation 11's interim. The published product cancelled spend identically —
the view's own header proves it — so 56 of 66 candidates competed unordered.
Phase 10 re-bases this on expected profit at the marginal ceiling."
```

---

### Task 6.4 (violation 8): the seat is priced on the answer it buys

**Files:**
- Modify: `scripts/bigquery/tables/DE/DE_PLAN_CONFIG.sql` (two new settings, the seed, the guard, the ALTERs)
- Modify: `scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql:254-259` (`k`), `:616-624` (`seat_cost_per_day`), the `base` CTE, **and the outer `SELECT`'s explicit column list at `:641-667`** (Step 2b — the builder reads the view, not its CTEs)
- Modify: `scripts/bigquery/tests/PLAN_CONFIG_acceptance.sql` C09

`seat_cost_per_day`'s first branch is literally last window's spend rescaled by `planned_bid / current_bid`: correlation 0.995, mean ratio 0.973 across 53 seats holding $195.07/day. The verdict-click count exists only as a literal in `V_FAMILY_SEAT_REGISTER.sql:234-236` (`verdict_clicks 20`, `click_goal_day 4`, `probe_window_days 14`), with `click_goal_day` mirrored again into `V_PLAN_WINDOW_JUDGMENT.sql:257`.

- [ ] **Step 1: Add the two settings to `DE_PLAN_CONFIG`, all four places at once**

The seed guard compares every setting **by value**, so the seed STRUCT, the guard's `EXISTS` list, an `ALTER TABLE ADD COLUMN IF NOT EXISTS` line and acceptance C09 all move in one change or seed convergence breaks silently.

Add above the seed:

```sql
-- ── 2026-08-25 (violation 8): THE PRICE OF AN ANSWER, AS A SETTING ────────────────────────────
-- Doctrine 3: "if the Brain wants N clicks by date D, the seat is priced (N x expected CPC) / days,
-- not by what the keyword happened to spend last window." Measured before this change: correlation
-- between seat cost and prior-window spend 0.995, mean ratio 0.973 — the seat was not merely
-- undersized, it was an IDENTITY on last window's spend.
-- Both numbers already existed as literals inside V_FAMILY_SEAT_REGISTER, where nothing could test
-- them. Doctrine 3.3: the Brain's uncertainties are settings, not code, because a setting can be
-- tested and code cannot.
ALTER TABLE `onyga-482313.OI.DE_PLAN_CONFIG` ADD COLUMN IF NOT EXISTS clicks_to_verdict INT64;
ALTER TABLE `onyga-482313.OI.DE_PLAN_CONFIG` ADD COLUMN IF NOT EXISTS answer_days       INT64;
```

Extend each seed STRUCT with the two values and their sentence — `OFF_PEAK` gains `20 AS clicks_to_verdict, 7 AS answer_days`, `BOOST` and `PEAK` gain `20, 3`. Add both to the guard's `EXISTS` list:

```sql
                AND s.clicks_to_verdict = t.clicks_to_verdict
                AND s.answer_days       = t.answer_days
```

and to the `INSERT` column list and its `SELECT`.

- [ ] **Step 2: Read them in the view and replace the seat cost**

In the `k` CTE, delete the mirrored `click_goal_day 4` literal and add a note pointing at the config; in the `win` CTE that already reads `DE_PLAN_CONFIG`, add `clicks_to_verdict` and `answer_days` to its projection and carry both through `base`. Add `ks.settled_cpc90` and `ks.settled_clk90` to `base` as well.

- [ ] **Step 2b: REPUBLISH THEM ON THE VIEW'S OUTER SELECT — `base` is not the view's output**

**`V_PLAN_WINDOW_JUDGMENT`'s outer `SELECT` is an EXPLICIT column list** (`:641-667`), not a `SELECT
*`. A column computed in `base`, `derived` or `final` and not named there **does not exist to
`SP_BUILD_NEXT_WEEK_PLAN`**, which reads the view — `CREATE OR REPLACE TEMP TABLE j AS SELECT * FROM
V_PLAN_WINDOW_JUDGMENT` at `:111-112`. `affordable_bid` is the standing proof: it has been in `base`
at `:454` since the view was written and is invisible to the builder to this day.

Tasks 6.5 and 6.7 read `a.answer_days`, `a.affordable_bid`, `a.next_check_date`,
`a.park_retest_days` and `a.park_retest_clicks` off `assembled`, which is `r2.*`, which is `j.*`,
which is this view's published columns and nothing else. **Every one of those five must be added to
the outer `SELECT` or both tasks fail to deploy.** Add them here, in this task, so the phase does not
break three tasks later:

```sql
  -- 2026-08-25 (violation 8 and violation 14): published because SP_BUILD_NEXT_WEEK_PLAN reads this
  -- VIEW, not its CTEs. affordable_bid has sat unpublished in `base` since this view was written;
  -- next_check_date and the two park_retest_* settings arrive with Tasks 6.2 and 6.7. A column that
  -- is not on this list is not a column as far as the builder is concerned.
  f.clicks_to_verdict, f.answer_days, f.affordable_bid, f.next_check_date,
  f.park_retest_days, f.park_retest_clicks,
  f.settled_cpc90, f.settled_clk90,
```

(`park_retest_days` / `park_retest_clicks` do not exist until Task 6.7 Step 1 adds them to
`DE_PLAN_CONFIG` and to `win`; add the two names to this list **in that task**, and leave the other
six here. The comment stays as written so a reader sees the whole set in one place.)

Verify it, because a missing name produces no error until three tasks later:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT column_name FROM \`onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS\`
   WHERE table_name = 'V_PLAN_WINDOW_JUDGMENT'
     AND column_name IN ('clicks_to_verdict','answer_days','affordable_bid','next_check_date',
                         'settled_cpc90','settled_clk90')
   ORDER BY column_name"
```

Expected: six rows.

Then replace `seat_cost_per_day` at lines 616–624 with:

```sql
    -- P-6 RESTATED (2026-08-25, violation 8): a seat costs what the ANSWER costs, not what the
    -- keyword happened to spend. Doctrine 3: "(N x expected CPC) / days". P-4 still NULLs it on the
    -- good side. Expect fewer candidates to fit — measured, $98.95/day funds the whole 202-subject
    -- queue against $195.07/day of seats under the old identity. The allowance simply binds harder;
    -- the builder's walk and its allowance ASSERT need no change.
    IF(j.verdict IN ('GOOD', 'HELD_UNSETTLED', 'GRACE'), NULL,
      SAFE_DIVIDE(
        j.clicks_to_verdict
          -- expected CPC: the subject's own settled cost per click where it has one, else the price
          -- the plan is about to set, else its floor. Never a literal.
          * COALESCE(NULLIF(j.settled_cpc90, 0), j.planned_bid_raw, j.bid_floor, 0),
        NULLIF(j.answer_days, 0))) AS seat_cost_per_day,
```

- [ ] **Step 3: Extend acceptance C09**

`PLAN_CONFIG_acceptance.sql` C09 compares a `plan_seed` row's settings to the DDL. Add the two columns to whatever equality list it carries, so an in-place edit of either stays visible.

- [ ] **Step 4: Deploy in order and verify the seat is no longer an identity**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tables/DE/DE_PLAN_CONFIG.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT calendar_state, window_days, allowance_share, min_orders, clicks_to_verdict, answer_days,
          is_active, updated_by FROM \`onyga-482313.OI.DE_PLAN_CONFIG\` ORDER BY calendar_state"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT ROUND(CORR(seat_cost_per_day, SAFE_DIVIDE(w_sp, window_days)), 3) AS seat_vs_last_window,
       COUNTIF(seat_no IS NOT NULL) seats,
       ROUND(SUM(IF(seat_no IS NOT NULL, seat_cost_per_day, 0)), 2) seat_usd_per_day
FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
WHERE as_of = (SELECT MAX(as_of) FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`) AND is_live_plan"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/PLAN_CONFIG_acceptance.sql)"
```

Expected: `seat_vs_last_window` falls far below 0.995 (the identity is broken), the seat count drops because seats now cost what answers cost, and every `PLAN_CONFIG_acceptance` row reads `PASS`.

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/tables/DE/DE_PLAN_CONFIG.sql \
        scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql \
        scripts/bigquery/tests/PLAN_CONFIG_acceptance.sql
git commit -m "feat(brain): a seat costs what the answer costs

Closes half of violation 8. The seat was an identity on last window's spend
(corr 0.995, mean ratio 0.973). clicks_to_verdict and answer_days become settings
in DE_PLAN_CONFIG rather than literals inside a view, so they can be tested."
```

---

### Task 6.5 (violation 8): the seat deadline is when the funded clicks land

**Files:**
- Modify: `scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql:396`

`verdict_date` is `as_of + settle_days` (7 SP / 14 SB) — the attribution window, not the time the funded clicks take to arrive. §7 forbids a seat that demands an answer it does not fund; a seat that demands one **sooner than it buys one** is the same defect.

- [ ] **Step 1: Replace the expression**

**`a.answer_days` must already be on the view's published column list before this step will
deploy.** `assembled` is `r2.*`, which is `j.*`, which is `V_PLAN_WINDOW_JUDGMENT`'s outer `SELECT`
— an explicit list. Task 6.4 Step 2b puts it there. Confirm it before editing:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT COUNT(*) AS answer_days_is_published FROM \`onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS\`
   WHERE table_name = 'V_PLAN_WINDOW_JUDGMENT' AND column_name = 'answer_days'"
```

Expected: `1`. A `0` means Task 6.4 Step 2b was skipped and this task will fail with
`Unrecognized name: answer_days`.

Line 396 today reads:

```sql
    IF(a.seat_no IS NOT NULL, DATE_ADD(as_of_d, INTERVAL a.settle_days DAY), NULL) AS verdict_date
```

Replace with:

```sql
    -- P-12 RESTATED (2026-08-25, violation 8). The deadline was as_of + the ATTRIBUTION window,
    -- which is when sales stop arriving — not when the clicks the seat paid for arrive. A seat that
    -- demands an answer sooner than it buys one is the same defect as a seat that does not fund the
    -- answer at all (doctrine 7). The deadline is now: the days the answer takes to buy, PLUS the
    -- attribution lag on the last of those clicks.
    IF(a.seat_no IS NOT NULL,
       DATE_ADD(as_of_d, INTERVAL COALESCE(a.answer_days, 7) + a.settle_days DAY),
       NULL)                                                              AS verdict_date
```

- [ ] **Step 2: Deploy, run, and check P-12's assertion still holds**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT channel, COUNT(*) seats,
       MIN(DATE_DIFF(verdict_date, as_of, DAY)) min_days,
       MAX(DATE_DIFF(verdict_date, as_of, DAY)) max_days
FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
WHERE as_of = (SELECT MAX(as_of) FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`)
  AND is_live_plan AND seat_no IS NOT NULL
GROUP BY 1"
```

Expected: SP seats sit around 10–14 days out, SB seats around 17–21, and the builder's own `ASSERT` "every SEAT carries a verdict date in the future" passes (a failure aborts the build before the DELETE, leaving yesterday's partition standing).

- [ ] **Step 3: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql
git commit -m "fix(brain): a seat's deadline is when its funded clicks land, plus attribution

The deadline was the attribution window alone, so a seat could demand an answer
before it had bought one."
```

---

### Task 6.6 (violations 9 + 14): let a park carry a date

**Files:**
- Modify: `scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql` (three ALTER lines)
- Modify: `scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql:648-650` (the assertion)
- Modify: `scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql` C10
- Modify: `scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql:391-402` (read the new columns back)

- [ ] **Step 1: Add the columns**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
ALTER TABLE \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
  ADD COLUMN IF NOT EXISTS revisit_date        DATE,
  ADD COLUMN IF NOT EXISTS revisit_reason      STRING,
  ADD COLUMN IF NOT EXISTS retest_clicks_bought INT64"
```

Append the same three lines to `scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql` alongside the existing `ALTER TABLE ADD COLUMN IF NOT EXISTS` block (the pattern at lines 146–158), under this comment:

```sql
-- ── A PARK CARRIES A DATE (2026-08-25, violations 9 and 14) ───────────────────────────────────
-- verdict_date is written only for SEATS and its absence off-seat was asserted twice — here and in
-- FACT_PLAN_NEXT_WEEK_acceptance C10 — so a park could not carry a date at all. Doctrine 4 needs
-- one for NOT_WORTH_NOW ("park at floor with a revisit date, never pause") and doctrine 3 needs one
-- for the park re-test obligation. They are the same relaxation, so they share a change window.
-- CREATE TABLE IF NOT EXISTS above is a silent no-op against an existing table, which is why every
-- new column arrives as an explicit ALTER line.
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS revisit_date         DATE;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS revisit_reason       STRING;
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` ADD COLUMN IF NOT EXISTS retest_clicks_bought INT64;
```

- [ ] **Step 2: Relax the twin assertions**

`SP_BUILD_NEXT_WEEK_PLAN.sql:648-650` today reads:

```sql
  ASSERT (SELECT COUNTIF(seat_no IS NOT NULL AND (verdict_date IS NULL OR verdict_date <= as_of))
                + COUNTIF(seat_no IS NULL AND verdict_date IS NOT NULL) FROM final) = 0
    AS 'every SEAT carries a verdict date in the future, held or repriced (P-12)';
```

Replace with:

```sql
  -- P-12, RELAXED IN ONE DIRECTION ONLY (2026-08-25). A SEAT still must carry a verdict date in the
  -- future — that is the ruling, and it is unchanged. What is dropped is the second clause, which
  -- forbade any date on an unseated row: doctrine 4 requires a parked seasonal subject to carry a
  -- revisit date, and doctrine 3 requires a park to carry a re-test appointment. Those are
  -- revisit_date, a separate column, and verdict_date remains seat-only.
  ASSERT (SELECT COUNTIF(seat_no IS NOT NULL AND (verdict_date IS NULL OR verdict_date <= as_of))
                + COUNTIF(seat_no IS NULL AND verdict_date IS NOT NULL) FROM final) = 0
    AS 'every SEAT carries a verdict date in the future, and verdict_date stays seat-only (P-12)';
  -- and the new half: a park that carries no date is the absorbing state doctrine 3 forbids
  ASSERT (SELECT COUNTIF(move IN ('PARK', 'PARK_SEASONAL', 'HOLD_AT_PARK')
                         AND revisit_date IS NULL) FROM final) = 0
    AS 'a park carries a revisit date — it is not a resting place (doctrine 3, 4)';
```

Change acceptance C10 in the same commit to match:

```sql
c10 AS (
  -- 2026-08-25: P-12 restated. verdict_date is still seat-only and still in the future; the new
  -- half asserts that every park carries a revisit date, because a park with no appointment is the
  -- absorbing state doctrine 3 forbids and 10.1 measured (452 of 544 parked subjects dark for 28
  -- days, 417 of them holding an exit condition they structurally cannot meet).
  SELECT 'C10 verdict_date is seat-only and future; every park carries a revisit date (P-12, doctrine 3)',
         COUNTIF(seat_no IS NOT NULL AND (verdict_date IS NULL OR verdict_date <= as_of))
       + COUNTIF(seat_no IS NULL AND verdict_date IS NOT NULL)
       + COUNTIF(move IN ('PARK','PARK_SEASONAL','HOLD_AT_PARK') AND revisit_date IS NULL)
  FROM b
),
```

- [ ] **Step 3: Read the new columns back — and keep the fence**

`V_PLAN_WINDOW_JUDGMENT.sql:391-402` reads `FACT_PLAN_NEXT_WEEK` back for the P-14b guard's memory, fenced by `as_of < today`. Add `revisit_date` and `retest_clicks_bought` to that CTE's projection. **Never remove the fence** — the Brain is a cycle closed across a partition boundary, and without it the pass reads its own output. On the first night after this change both columns are NULL for every row, exactly like the `grace_limit_armed` bootstrap the view documents at lines 51–57; that is expected and self-healing.

- [ ] **Step 4: Deploy, run, verify**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`()"
```

Expected: the build succeeds. It will FAIL the new park assertion until Task 6.7 populates `revisit_date` — that failure is the red state, it aborts before the `DELETE` and leaves yesterday's partition standing, and Task 6.7 turns it green.

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql \
        scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql \
        scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql \
        scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql
git commit -m "feat(brain): a park carries a date — the shared relaxation for violations 9 and 14

verdict_date stays seat-only; revisit_date is new and required on every park. The
as_of < today fence on the plan's own memory is untouched."
```

---

### Task 6.7 (violation 14): fund the re-test

**Files:**
- Modify: `scripts/bigquery/tables/DE/DE_PLAN_CONFIG.sql` (two more settings — **Ori's open ruling**)
- Modify: `scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql` (`win`, `base` and the outer `SELECT` — the two settings must reach the builder, which reads the view)
- Modify: `scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql` (the move CASE, the seat walk, the sentence)

**The park is an absorbing state today.** 544 PARKED subjects, 452 dark for 28 days, 417 of those carrying the "record too thin to judge" appointment whose exit condition they structurally cannot meet, and `V_PARK_REVERDICT.sql:52-55` requires 10 settled clicks to REVIVE — evidence the park itself prevents. `SP_SNAPSHOT_KEYWORD_STATE.sql:500-505` re-sets the appointment to today+14 every night from an unchanged record, and its own words at 532–535 promise a re-READ, never a re-TEST.

- [ ] **Step 1: Seed the cadence as a DECLARED CONSTANT, named as Ori's**

Add to `DE_PLAN_CONFIG` in the same four-place pattern as Task 6.4:

```sql
-- ── ORI'S OPEN RULING: THE PARK RE-TEST CADENCE (doctrine 6.4) ────────────────────────────────
-- "The re-test cadence for a park — how often, and how much, to buy fresh evidence on a parked
-- subject" is recorded in architecture/THREE_LAYERS.md 6.4 as OPEN, and it is a SETTING, which is
-- exactly what 6.1 says a control group can test. THIS PLAN DOES NOT DECIDE IT.
-- The values below are a starting point, not an answer:
--   park_retest_days 28   one full attribution cycle plus a margin — long enough that a re-test is
--                         not churn, short enough that a recovered subject is found inside a season
--   park_retest_clicks 10 the guard's own min_settled_clk, and the exact number V_PARK_REVERDICT
--                         already requires to REVIVE, so a funded re-test buys precisely the
--                         evidence the revival gate demands and not a click more
-- THE EXPERIMENT THAT SETTLES IT, declared before it runs (6.1):
--   WHICH SETTING   park_retest_days, tested at 28 against 14 and 56
--   WHICH SLICE     a random half of the HARVEST families' parked subjects. NEVER the holdout arm
--                   (DE_HOLDOUT_ASSIGNMENT, arm HOLDOUT, eligible_from 2026-09-01) — contaminating
--                   the control destroys the only clean comparison the account has (6.1)
--   WHAT DECIDES IT net profit over the treated slice across two cadence cycles, against the
--                   untreated half of the same families
--   BY WHEN         two cycles at the longest arm, so 112 days from the day it starts
-- Ori changes a setting by retire-then-insert, never by editing this file.
ALTER TABLE `onyga-482313.OI.DE_PLAN_CONFIG` ADD COLUMN IF NOT EXISTS park_retest_days   INT64;
ALTER TABLE `onyga-482313.OI.DE_PLAN_CONFIG` ADD COLUMN IF NOT EXISTS park_retest_clicks INT64;
```

Extend all three seed STRUCTs with `28 AS park_retest_days, 10 AS park_retest_clicks`, add both to
the guard's `EXISTS` list and to the `INSERT`, and extend `PLAN_CONFIG_acceptance` C09.

**Then carry them all the way to the builder, which is four places and not one.** Step 3 reads
`a.park_retest_days` and `a.park_retest_clicks` off `assembled`, which is `r2.*` → `j.*` →
`V_PLAN_WINDOW_JUDGMENT`'s **explicit** outer `SELECT`. So: add both to `V_PLAN_WINDOW_JUDGMENT`'s
`win` CTE (which already reads `DE_PLAN_CONFIG`), through `base`, and onto the outer column list
beside the six names Task 6.4 Step 2b put there. Confirm before editing Step 3:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT column_name FROM \`onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS\`
   WHERE table_name = 'V_PLAN_WINDOW_JUDGMENT'
     AND column_name IN ('park_retest_days','park_retest_clicks','affordable_bid','next_check_date')
   ORDER BY column_name"
```

Expected: four rows. Anything less and Step 3 fails with `Unrecognized name`.

- [ ] **Step 2: Add the `TEST_RETEST` move**

In the builder's move CASE, insert immediately **below** the `PARK_SEASONAL` arm from Task 6.2 and **above** the `DEAD` arm:

```sql
      -- ── THE PARK RE-TEST (2026-08-25, violation 14) ────────────────────────────────────────
      -- Doctrine 3: "a park is not a resting place — it carries a re-test obligation", and Pacing
      -- owes a parked subject periodic clicks, funded by the Brain with a budget and a deadline
      -- like any other question. Measured before this: 544 parked subjects, 452 dark for 28 days,
      -- 417 of them holding an appointment whose exit condition — 10 settled clicks — the park
      -- itself prevents them from ever meeting.
      -- THIS IS A SEAT, NOT A FREE PASS: it takes family allowance and competes for it like any
      -- other candidate, and it is only issued to a subject whose last re-test is older than the
      -- cadence. A park that has just been re-tested holds at its park price.
      WHEN m.seat_no IS NOT NULL
       AND r2.ladder_state = 'PARKED'
       AND (r2.prior_revisit_date IS NULL OR r2.prior_revisit_date <= as_of_d)
                                                                        THEN 'TEST_RETEST'
```

- [ ] **Step 3: Price and date it**

In the `priced` CTE, add a branch to `planned_bid_final`:

```sql
      -- a re-test is bought at the price the Catalog says the subject can afford, capped by the
      -- Brain's own planned price — never at the park price, which is what made it dark.
      WHEN 'TEST_RETEST'   THEN ROUND(COALESCE(a.plan_bid, a.affordable_bid, a.current_bid), 2)
```

and set both dates:

```sql
    -- every park carries a revisit date; a funded re-test carries the date its clicks land
    CASE
      WHEN a.move = 'TEST_RETEST'
        THEN DATE_ADD(as_of_d, INTERVAL COALESCE(a.answer_days, 7) + a.settle_days DAY)
      WHEN a.move = 'PARK_SEASONAL'
        THEN a.next_check_date
      WHEN a.move IN ('PARK', 'HOLD_AT_PARK')
        THEN DATE_ADD(as_of_d, INTERVAL a.park_retest_days DAY)
      ELSE NULL
    END                                                                 AS revisit_date,
    CASE
      WHEN a.move = 'TEST_RETEST'
        THEN FORMAT('buying %d clicks to see whether this recovered — the park cannot produce that evidence by itself',
                    a.park_retest_clicks)
      WHEN a.move = 'PARK_SEASONAL'
        THEN 'dormant until its window opens; the keyword state re-reads it then'
      WHEN a.move IN ('PARK', 'HOLD_AT_PARK')
        THEN FORMAT('parked at its floor; due a funded re-test in %d days', a.park_retest_days)
      ELSE NULL
    END                                                                 AS revisit_reason,
    IF(a.move = 'TEST_RETEST', a.park_retest_clicks, NULL)              AS retest_clicks_bought,
```

Carry `prior_revisit_date` from the plan's own memory (the `plan_hist` CTE of Task 6.6 Step 3) into `r2`.

- [ ] **Step 4: Deploy, run, and verify the park is no longer absorbing**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tables/DE/DE_PLAN_CONFIG.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT move, COUNT(*) n, COUNTIF(revisit_date IS NULL) without_a_date,
       ROUND(SUM(COALESCE(seat_cost_per_day, 0)), 2) seat_usd_per_day
FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
WHERE as_of = (SELECT MAX(as_of) FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`) AND is_live_plan
GROUP BY 1 ORDER BY n DESC"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql)"
```

Expected: a `TEST_RETEST` bucket exists, `without_a_date = 0` on every park move, and all acceptance rows read `PASS`.

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/tables/DE/DE_PLAN_CONFIG.sql \
        scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql \
        scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql \
        scripts/bigquery/tests/PLAN_CONFIG_acceptance.sql \
        scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql \
        architecture/THREE_LAYERS.md
git commit -m "feat(brain): the park re-test is funded like any other question

Closes violation 14. The cadence and click count are ORI'S OPEN RULING (6.4),
seeded as declared constants with the 6.1 experiment written down and the holdout
arm explicitly off limits."
```

---

### Task 6.8 (violation 14): the park price source, as a declared constant

**Files:**
- Modify: `scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql` (the `bid_park` resolution)

**ORI'S OPEN RULING (§6.4).** The engine's published `bid_park` and the channel floor differ by up to 2.5x on some rows. The plan does not choose; it carries the ordered fallback already implemented in `tools/build_seasonal_unpause_bulksheet.py:22-33`, records both measured sides, and leaves the choice to Ori.

- [ ] **Step 1: Measure both sides**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT bid_park_source, COUNT(*) n, ROUND(AVG(bid_park), 3) avg_park,
       ROUND(AVG(bid_floor), 3) avg_floor,
       ROUND(MAX(SAFE_DIVIDE(bid_park, NULLIF(bid_floor, 0))), 2) max_ratio,
       COUNTIF(bid_park > bid_floor + 0.005) above_the_floor
FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
WHERE as_of = (SELECT MAX(as_of) FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`) AND is_live_plan
GROUP BY 1 ORDER BY n DESC"
```

Expected two buckets. Measured 2026-08-24: 312 rows at `SEAT_ECONOMICS` averaging $0.250 against a $0.182 floor, max ratio 2.50x, 286 of 312 above the floor; 418 rows at `BID_FLOOR_FALLBACK` priced exactly at the floor. **Record both. Do not choose.**

- [ ] **Step 2: Document the ordered fallback where the resolution happens**

Add this comment immediately above the `bid_park` / `bid_park_source` expressions in `V_PLAN_WINDOW_JUDGMENT.sql`, changing no logic:

```sql
    -- ── ORI'S OPEN RULING: THE PARK PRICE SOURCE (doctrine 6.4) ────────────────────────────────
    -- The engine's published park price (T_OOB_SEAT_ECONOMICS.bid_park) and the ad group's
    -- channel+creative floor (V_BID_FLOOR / FN_BID_FLOOR) DIFFER, materially: measured 2026-08-24,
    -- rows resolved from seat economics averaged $0.250 against a $0.182 floor, with a maximum
    -- ratio of 2.50x and the large majority sitting above the floor; rows resolved from the floor
    -- fallback price exactly at it. Which one a park SHOULD pay is 6.4's open ruling and is Ori's,
    -- not this view's.
    -- WHAT IS IMPLEMENTED IS THE ORDERED FALLBACK ALREADY IN tools/build_seasonal_unpause_bulksheet.py:
    --   1. the engine's bid_park where it exists
    --   2. otherwise the ad group's channel+creative floor
    --   3. an engine park price BELOW the floor is raised UP to the floor — never down
    --   4. a subject neither resolves for is REFUSED LOUDLY, never priced at a literal
    -- bid_park_source is published so which arm answered is always visible on the row.
```

- [ ] **Step 3: Add the refusal, which is the one behavioural half**

Add an assertion to `SP_BUILD_NEXT_WEEK_PLAN.sql`, beside the others and therefore above the `DELETE`:

```sql
  -- rule 4 of the park price fallback: refuse loudly rather than price at a literal
  ASSERT (SELECT COUNTIF(move IN ('PARK', 'PARK_SEASONAL') AND planned_bid IS NULL) FROM final) = 0
    AS 'a parked keyword resolves a park price from the engine or its floor, or the build refuses';
```

- [ ] **Step 4: Deploy, run and commit**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`()"
git add scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql \
        scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql
git commit -m "docs(brain): the park price source is Ori's open ruling, recorded not decided

Both measured sides are on the record and the ordered fallback is documented where
it resolves. The one behavioural half: a park with no resolvable price refuses."
```

---

### Task 6.9 (violation 9): the Brain does not originate a kill

**Files:**
- Modify: `scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql:684-688` (the DEAD assertion)

The only pause the Brain issues stays `ladder_state = 'DEAD'` — the Brain executes the Catalog's terminal state, it does not originate one. What changes is that a `NOT_WORTH_NOW` subject can no longer reach that arm, because Task 6.2 routes it to `PARK_SEASONAL` first.

- [ ] **Step 1: Extend the assertion to say so**

The assertion at 684–688 today reads that a closed keyword takes no seat, carries no price and its move is PAUSE. Add a second assertion beside it:

```sql
  -- 2026-08-25 (violation 9): a dormant seasonal subject is NEVER paused. Doctrine 4 calls
  -- collapsing NOT_WORTH_NOW into NOT_WORTH the single most expensive mistake it exists to prevent,
  -- and 10 priced it: replaying last season's door, 45 of 111 condemned keywords went on to earn.
  ASSERT (SELECT COUNTIF(ladder_state = 'NOT_WORTH_NOW' AND move = 'PAUSE') FROM final) = 0
    AS 'a dormant seasonal keyword is parked with a revisit date, never paused (doctrine 4)';
```

- [ ] **Step 2: Deploy, run, commit**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`()"
git add scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql
git commit -m "feat(brain): a dormant seasonal keyword is parked, never paused

Closes violation 9. The Brain still originates no kill — it executes the Catalog's
terminal state — but NOT_WORTH_NOW can no longer reach that arm."
```

---

### Task 6.10: `V_PLAN_SCORECARD` — the instrument that does not exist

**Files:**
- Create: `scripts/bigquery/views/V_PLAN_SCORECARD.sql`
- Modify: `config.yaml` (`views:`)

It is named as if it existed in `DE_PLAN_CONFIG.sql:9`, `FACT_PLAN_NEXT_WEEK.sql:12`, `architecture/NEXT_WEEK_MONEY.md` and `docs/superpowers/plans/2026-08-23-next-week-money.md`, and exists as neither a `.sql` file nor a BigQuery object. It is the named instrument for **Ori's open ruling on the 0.50 boost allowance share**.

- [ ] **Step 1: Confirm it really is absent**

```bash
cd /Users/ori/Develop/OI
ls scripts/bigquery/views/V_PLAN_SCORECARD.sql 2>&1
bq show onyga-482313:OI.V_PLAN_SCORECARD 2>&1 | head -2
grep -rln "V_PLAN_SCORECARD" scripts/ architecture/ docs/ | head
```

Expected: no such file, `Not found`, and several documents naming it.

- [ ] **Step 2: Write it**

```sql
-- =============================================================================================
-- V_PLAN_SCORECARD — the Brain's own scorecard: did the money go to the right places?
--
-- architecture/THREE_LAYERS.md 6 grades each layer on its own question, and the Brain's is "did the
-- money go to the right places?", measured by the SHADOW PLAN at T+14: would the other allocation
-- rule have earned more? SP_BUILD_NEXT_WEEK_PLAN already writes both plans every night (P-9), so
-- the counterfactual is already on disk and free — 6.1's "ask the free version first".
--
-- IT IS NAMED IN FOUR DOCUMENTS AND EXISTED IN NONE OF THEM. It is the instrument for Ori's open
-- ruling on the BOOST allowance share (6.4, flagged unproven in DE_PLAN_CONFIG's own seed text),
-- and until it existed "the scorecard answers it" was a promise with no object behind it.
--
-- THE GATE IS SETTLE-SAFE. A plan written on day T is judged on days T+1..T+7 (SP) or T+1..T+14
-- (SB), and that judgement is only READABLE at T+14 / T+21 — the same discipline
-- V_CHANGE_SCORECARD applies. A plan younger than its gate is published with graded = FALSE rather
-- than with a number nobody should read.
--
-- 6.3 IS BINDING HERE. Every "the other rule would have earned more" figure is a one-sided
-- comparison unless the net is reported beside it, so both plans' actual outcomes are published,
-- never only the difference.
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PLAN_SCORECARD` AS
WITH wm AS (
  SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),
plans AS (
  SELECT as_of, plan, is_live_plan, family, calendar_state, allowance_share, window_days,
         CAST(campaign_id AS STRING) AS campaign_id, CAST(keyword_id AS STRING) AS keyword_id,
         channel, side, verdict, move, seat_no, seat_cost_per_day, planned_spend_per_day
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
),
-- what actually happened in the window each plan was written for
outcome AS (
  SELECT p.as_of, p.plan, p.family, p.campaign_id, p.keyword_id,
         SUM(a.Ads_cost)     AS spend,
         SUM(a.Ads_clicks)   AS clicks,
         SUM(a.Ads_orders)   AS orders,
         SUM(a.GROSS_PROFIT) AS gp
  FROM plans p
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` a
    ON CAST(a.campaign_id AS STRING) = p.campaign_id
   AND CAST(a.keyword_id  AS STRING) = p.keyword_id
   AND a.date BETWEEN DATE_ADD(p.as_of, INTERVAL 1 DAY)
                  AND DATE_ADD(p.as_of, INTERVAL IF(p.channel = 'SB', 14, 7) DAY)
  GROUP BY 1, 2, 3, 4, 5
),
per_plan AS (
  SELECT
    p.as_of,
    p.plan,
    LOGICAL_OR(p.is_live_plan)                                   AS is_live_plan,
    ANY_VALUE(p.calendar_state)                                  AS calendar_state,
    MAX(p.allowance_share)                                       AS allowance_share,
    p.family,
    COUNTIF(p.seat_no IS NOT NULL)                               AS seats,
    ROUND(SUM(IF(p.seat_no IS NOT NULL, p.seat_cost_per_day, 0)), 2) AS seat_cost_per_day,
    ROUND(SUM(p.planned_spend_per_day), 2)                       AS planned_spend_per_day,
    ROUND(SUM(COALESCE(o.spend, 0)), 2)                          AS actual_spend,
    SUM(COALESCE(o.clicks, 0))                                   AS actual_clicks,
    SUM(COALESCE(o.orders, 0))                                   AS actual_orders,
    ROUND(SUM(COALESCE(o.gp, 0)), 2)                             AS actual_gp,
    ROUND(SUM(COALESCE(o.gp, 0)) - SUM(COALESCE(o.spend, 0)), 2) AS actual_net
  FROM plans p
  LEFT JOIN outcome o
    ON o.as_of = p.as_of AND o.plan = p.plan AND o.family = p.family
   AND o.campaign_id = p.campaign_id AND o.keyword_id = p.keyword_id
  GROUP BY p.as_of, p.plan, p.family
)
SELECT
  l.as_of,
  l.family,
  l.calendar_state,
  l.allowance_share,
  -- readable only once the longest settle window on the plan has closed (SB 14 + 7 of lag)
  (DATE_ADD(l.as_of, INTERVAL 21 DAY) <= (SELECT d FROM wm))     AS graded,
  DATE_ADD(l.as_of, INTERVAL 21 DAY)                             AS readable_from,

  l.plan            AS live_plan_id,
  l.seats           AS live_seats,
  l.seat_cost_per_day AS live_seat_cost_per_day,
  l.actual_spend    AS live_actual_spend,
  l.actual_orders   AS live_actual_orders,
  l.actual_gp       AS live_actual_gp,
  l.actual_net      AS live_actual_net,

  s.plan            AS shadow_plan_id,
  s.seats           AS shadow_seats,
  s.seat_cost_per_day AS shadow_seat_cost_per_day,
  s.actual_spend    AS shadow_actual_spend,
  s.actual_orders   AS shadow_actual_orders,
  s.actual_gp       AS shadow_actual_gp,
  s.actual_net      AS shadow_actual_net,

  -- 6.3: publish BOTH sides, and the net difference, never a one-sided "would have earned more"
  ROUND(l.actual_net - s.actual_net, 2)                          AS live_minus_shadow_net,
  -- the rows the two plans disagreed about at all. A day on which they agree everywhere carries no
  -- information about the allocation rule and must not be counted as evidence for it.
  (SELECT COUNT(*) FROM plans a JOIN plans b
     ON b.as_of = a.as_of AND b.family = a.family
    AND b.campaign_id = a.campaign_id AND b.keyword_id = a.keyword_id
    AND b.plan != a.plan
   WHERE a.as_of = l.as_of AND a.family = l.family AND a.plan = l.plan
     -- BOTH SIDES PARENTHESISED. BigQuery rejects `x IS NULL != y` with "Expression to the left of
     -- comparison must be parenthesized"; the IS NULL binds looser than the comparison.
     AND (a.move != b.move OR (a.seat_no IS NULL) != (b.seat_no IS NULL)))
                                                                 AS rows_the_two_plans_disagreed_on
FROM per_plan l
JOIN per_plan s ON s.as_of = l.as_of AND s.family = l.family AND s.plan != l.plan
WHERE l.is_live_plan;
```

- [ ] **Step 3: Deploy and read it**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_PLAN_SCORECARD.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT as_of, family, graded, readable_from, live_actual_net, shadow_actual_net,
          live_minus_shadow_net, rows_the_two_plans_disagreed_on
   FROM \`onyga-482313.OI.V_PLAN_SCORECARD\` ORDER BY as_of DESC, family LIMIT 20"
```

Expected: rows with `graded = FALSE` for recent partitions (the settle gate has not opened) and real numbers once a partition is 21 days old. **The BOOST allowance question cannot be answered until BOOST partitions exist and have aged past their gate** — that is honest, and it is why the ruling stays open.

- [ ] **Step 4: Register and commit**

Add `V_PLAN_SCORECARD` to `config.yaml` under `views:` beside `V_PLAN_WINDOW_JUDGMENT`, with a description saying it is the Brain's scorecard, that it grades the live plan against the free shadow plan on a settle-safe gate, that both sides are published per §6.3, and that it is the named instrument for the open ruling on the boost allowance share.

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_PLAN_SCORECARD.sql config.yaml
git commit -m "feat(brain): V_PLAN_SCORECARD — the instrument four documents already named

Grades the live plan against the free shadow plan at a settle-safe gate, publishes
both sides per 6.3, and counts the rows the two rules actually disagreed on. It is
the named instrument for Ori's open ruling on the 0.50 boost allowance share."
```

---

### Task 6.11: Do NOT close the orchestrator lag

**No files change. This task exists so the constraint is executed rather than assumed.**

- [ ] **Step 1: Confirm the lag is still there and still deliberate**

```bash
cd /Users/ori/Develop/OI
sed -n '2280,2290p' scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql
```

Expected: the comment recording that tasks 20.6 and 20.7 run earlier in the pass than 20.8/20.8c, so Pacing reads the plan one pass late, and that closing it means moving another owner's tasks — **an open ruling for Ori, not taken here**. Leave it exactly as it is.

- [ ] **Step 2: Confirm every temp table in the builder is still idempotent**

```bash
cd /Users/ori/Develop/OI
grep -c "CREATE OR REPLACE TEMP TABLE" scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql
grep -c "^\s*CREATE TEMP TABLE" scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql
```

Expected: a non-zero first count and `0` from the second. If the second is not zero, a task in this phase introduced a bare `CREATE TEMP TABLE` — fix it before moving on.

- [ ] **Step 3: Record the CONFIRMATION and commit it**

This task takes no red measurement — it confirms that two things a later phase could quietly break
are still intact. That confirmation is still written down, for the same reason every measurement in
this plan is: a recheck must be a re-run and not a fresh argument, and "we checked the lag was still
there" is worthless six weeks later if nobody recorded what "there" looked like.

```bash
cd /Users/ori/Develop/OI
mkdir -p docs/superpowers/specs
cat >> docs/superpowers/specs/2026-08-25-gap-closure-measurements.md <<'EOF'

## Task 6.11 — confirmed YYYY-MM-DD

Replace the date above with the date you ran it. Paste below, unsummarised: the output of the
`sed -n '2280,2290p'` on SP_ORCHESTRATE_DAILY_REFRESH.sql from Step 1, and the two `grep -c` counts
from Step 2. This is a CONSTRAINT CONFIRMATION, not a measurement: the orchestrator lag is an open
ruling for Ori and no phase of this plan may close it as a side effect, and every temp table in
SP_BUILD_NEXT_WEEK_PLAN must stay CREATE OR REPLACE after the 2026-08-24 cube outage.
EOF
git add docs/superpowers/specs/2026-08-25-gap-closure-measurements.md
git commit -m "chore(brain): confirm the orchestrator lag is untouched and every temp table idempotent

Not a fix and not a measurement — an executed constraint. The lag is Ori's open
ruling; closing it means moving another owner's tasks."
```

---
## Phase 7 — Confidence, and the door that only opens on it

**Closes:** violations 19, 20, and the CLOSE half of violation 22.

**Why here.** §5's irreversibility rule is unenforceable in code because confidence is specified in §2.7 and computed nowhere. That is why the CLOSE arm was withheld in Phase 4 and why the Brain's PAUSE branch is still gated only on `ladder_state = 'DEAD'`. It comes after Phase 6 rather than before because Phase 6 is entirely reversible moves and does not need it, and because building it earlier would have blocked five safety fixes behind one modelling task.

**19 and 20 are one computation.** §2.7's `stability` factor **is** the term-turnover measurement violation 19 asks for — measured at BROAD 63.7%/month and auto 57–68% against an EXACT control at 19.1% — and separation already half-exists as `se_eff`. Sized: of 359 subjects with settled clicks only 88 pass the guard's applicability test, leaving $308.13/day of $829.88/day with no drift check at all, including 125 BROAD subjects carrying $156.32/day. **§8 blames auto modes; the code is not auto-scoped** — `grep is_auto` over the procedure returns only pass-through references — and the money is in BROAD.

**Unblocks:** every one-way action in the system — the campaign CLOSE arm, the Brain's PAUSE, the books' pause rows. Phase 8's verdict field needs confidence as one of its four columns; Phase 10's rank discount needs it as a multiplier.

**Size:** L — 2–2.5 weeks. One genuinely new computation (stability), two derived columns, a gate wired into three places, the campaign CLOSE intent, and the book that executes it.

---

### Task 7.1: Two red measurements

- [ ] **Step 1: Confidence does not exist**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT column_name FROM \`onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS\`
   WHERE table_name = 'FACT_KEYWORD_STATE'
     AND LOWER(column_name) IN ('confidence','confidence_band','separation','stability')"
```

Expected: zero rows.

- [ ] **Step 2: Most of the money has no drift check at all**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT CASE WHEN is_auto THEN 'AUTO' WHEN is_pt THEN 'PT' ELSE UPPER(match_type) END AS kind,
       COUNT(*) subjects,
       COUNTIF(COALESCE(guard_prior_clk, 0) >= 10) guard_applicable,
       ROUND(AVG(guard_ns_share), 4) avg_never_seen_share,
       ROUND(SUM(settled_sp90) / 90, 2) usd_per_day,
       ROUND(SUM(IF(COALESCE(guard_prior_clk, 0) < 10, settled_sp90, 0)) / 90, 2) unprotected_usd_per_day
FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`
WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`)
  AND settled_clk90 > 0
GROUP BY 1 ORDER BY usd_per_day DESC"
```

Expected: `guard_applicable` far below `subjects` on the wide match types. Measured 2026-08-24: 88 of 359 pass; $308.13/day of $829.88/day unprotected; BROAD 163 subjects / 38 applicable / $450.59/day, of which 125 subjects and $156.32/day get no check at all.

- [ ] **Step 3: Show the code was never auto-scoped**

```bash
cd /Users/ori/Develop/OI
grep -n "is_auto" scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql
```

Expected: only pass-through column references — no `CASE`, no filter. The auto framing in §8's violation 19 is in the doctrine, not in the code, and the plan must say so rather than "de-scope" something that was never scoped.

- [ ] **Step 4: Record the measurement and commit it**

Every red measurement in this plan is a number the green run is compared against, so it is written
down rather than remembered. Append what you measured — the query, the date, and the count — to the
running record, creating the file on the first task that reaches this step:

```bash
cd /Users/ori/Develop/OI
mkdir -p docs/superpowers/specs
cat >> docs/superpowers/specs/2026-08-25-gap-closure-measurements.md <<'EOF'

## Task 7.1 — measured YYYY-MM-DD

Replace the date above with the date you ran it, and paste below: the query you ran (unchanged from
the task), and its output. Do not summarise the output — the point of this file is that a re-run is
a re-run and not a fresh argument, which is the same reason
docs/superpowers/specs/2026-08-24-three-layers-baseline.md exists.
EOF
git add docs/superpowers/specs/2026-08-25-gap-closure-measurements.md
git commit -m "measure(task 7.1): record the red measurement before the fix

The number the green run is compared against, written down rather than remembered."
```

---

### Task 7.2 (violation 19): `V_KEYWORD_STABILITY`

**Files:**
- Create: `scripts/bigquery/views/V_KEYWORD_STABILITY.sql`
- Modify: `config.yaml` (`views:`)

**Do not reuse the mix-drift guard for this.** `SP_SNAPSHOT_KEYWORD_STATE.sql:232-235` discards only terms with **zero prior-window impressions AND zero orders**, so cleaned ROAS is greater than or equal to raw ROAS by construction and `guard_flip` can only ever move a subject **up** the ladder. It is a rescue valve, not a stability measure. §2.7's stability is a new computation.

- [ ] **Step 1: Write the view**

```sql
-- =============================================================================================
-- V_KEYWORD_STABILITY — the share of a subject's record that came from composition still present.
--
-- architecture/THREE_LAYERS.md 2.7: confidence is separation x STABILITY, and stability asks "did
-- the thing being measured stay the same thing?" A record is only as trustworthy as the constancy
-- of what produced it. Measured (10.1): terms behind a BROAD subject turn over about 64% a month
-- and auto modes 57-68%, against an EXACT control at 19% — so two subjects with identical click
-- counts are NOT equally knowable, and separation alone would call them equal.
--
-- WHY NOT REUSE THE MIX-DRIFT GUARD. The guard in SP_SNAPSHOT_KEYWORD_STATE discards only terms
-- with zero prior-window impressions AND zero orders, so its cleaned ROAS is >= the raw one BY
-- CONSTRUCTION and its flip can only ever move a subject UP the ladder. It is a rescue valve, not a
-- measure of constancy, and describing it as one would be wrong in a way that licenses kills.
--
-- WHAT THIS MEASURES INSTEAD: of the CLICKS in the judging window, what share came from search
-- terms that were also present in the prior window. High share = the basket held still. It is
-- symmetric — it can fall as easily as rise — and it is defined for every subject with clicks,
-- including the ones whose prior window is too thin for the guard.
--
-- GRAIN: one row per (campaign_id, keyword_id). Complete days only.
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_KEYWORD_STABILITY` AS
WITH wm AS (
  SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),
-- the judging window and the window before it, per subject per search term
t AS (
  SELECT CAST(a.campaign_id AS STRING) AS cid,
         CAST(a.keyword_id  AS STRING) AS kid,
         a.search_term,
         SUM(IF(a.date BETWEEN DATE_SUB(w.d, INTERVAL 92 DAY)
                           AND DATE_SUB(w.d, INTERVAL 3 DAY), a.Ads_clicks, 0))      AS now_clicks,
         SUM(IF(a.date BETWEEN DATE_SUB(w.d, INTERVAL 92 DAY)
                           AND DATE_SUB(w.d, INTERVAL 3 DAY), a.Ads_cost, 0))        AS now_cost,
         SUM(IF(a.date BETWEEN DATE_SUB(w.d, INTERVAL 182 DAY)
                           AND DATE_SUB(w.d, INTERVAL 93 DAY), a.Ads_clicks, 0))     AS prior_clicks,
         SUM(IF(a.date BETWEEN DATE_SUB(w.d, INTERVAL 182 DAY)
                           AND DATE_SUB(w.d, INTERVAL 93 DAY), a.Ads_impressions, 0)) AS prior_impr
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a, wm w
  WHERE a.search_term IS NOT NULL
    AND a.keyword_id IS NOT NULL
    AND a.date BETWEEN DATE_SUB(w.d, INTERVAL 182 DAY) AND DATE_SUB(w.d, INTERVAL 3 DAY)
  GROUP BY 1, 2, 3
)
SELECT
  cid                                                              AS campaign_id,
  kid                                                              AS keyword_id,
  SUM(now_clicks)                                                  AS window_clicks,
  SUM(prior_clicks)                                                AS prior_window_clicks,
  COUNT(DISTINCT IF(now_clicks > 0, search_term, NULL))            AS terms_in_window,
  COUNT(DISTINCT IF(now_clicks > 0 AND (prior_clicks > 0 OR prior_impr > 0),
                    search_term, NULL))                            AS terms_also_present_before,
  -- STABILITY: the share of this window's CLICKS that came from terms the prior window also saw.
  -- Clicks and not term counts, because a subject can carry a long tail of one-click terms whose
  -- churn says nothing about where its money came from.
  SAFE_DIVIDE(SUM(IF(prior_clicks > 0 OR prior_impr > 0, now_clicks, 0)),
              NULLIF(SUM(now_clicks), 0))                          AS stability,
  -- and the same in dollars, published beside it because they can disagree and the disagreement is
  -- informative: a stable click base on a churning spend base is a bidding change, not a mix change.
  SAFE_DIVIDE(SUM(IF(prior_clicks > 0 OR prior_impr > 0, now_cost, 0)),
              NULLIF(SUM(now_cost), 0))                            AS stability_by_spend,
  -- WHEN THE PRIOR WINDOW IS EMPTY THERE IS NO ANSWER, and saying "0% stable" would be a lie that
  -- licenses a kill. Doctrine 2.7's NO_EVIDENCE exists for exactly this shape of nothing.
  (SUM(prior_clicks) = 0 AND SUM(prior_impr) = 0)                  AS stability_no_evidence
FROM t
GROUP BY 1, 2;
```

- [ ] **Step 2: Deploy and check it reproduces the known drift pattern**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_KEYWORD_STABILITY.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT CASE WHEN ks.is_auto THEN 'AUTO' WHEN ks.is_pt THEN 'PT'
            ELSE UPPER(ks.match_type) END AS kind,
       COUNT(*) subjects,
       ROUND(AVG(st.stability), 3) avg_stability,
       COUNTIF(st.stability_no_evidence) no_prior_window,
       ROUND(SUM(ks.settled_sp90) / 90, 2) usd_per_day
FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\` ks
JOIN \`onyga-482313.OI.V_KEYWORD_STABILITY\` st
  ON st.campaign_id = ks.campaign_id AND st.keyword_id = ks.keyword_id
WHERE ks.snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`)
  AND ks.settled_clk90 > 0
GROUP BY 1 ORDER BY usd_per_day DESC"
```

Expected: EXACT shows the highest `avg_stability`, BROAD and the auto modes materially lower — the same ordering the baseline's drifting-basket query found (EXACT 19.1% turnover, BROAD 63.7%, auto 57–68%), read as its complement. **Every subject with clicks gets a number**, including the 125 BROAD subjects the guard cannot check, and where there is genuinely no prior window `stability_no_evidence` says so rather than reading zero.

- [ ] **Step 3: Register and commit**

Add `V_KEYWORD_STABILITY` to `config.yaml` under `views:` beside `V_KEYWORD_GUARD`.

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_KEYWORD_STABILITY.sql config.yaml
git commit -m "feat(catalog): V_KEYWORD_STABILITY — did the thing measured stay the same thing

Closes violation 19. Not the mix-drift guard, which only ever removes zero-order
clicks and can therefore only rescue. Defined for every subject with clicks,
including the ones whose prior window is too thin for the guard."
```

---

### Task 7.3 (violation 20): separation, and the applicability gap

**Files:**
- Modify: `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql` (join the stability view, publish `separation`)

`se_eff` already exists (`SP:328-331`): `0.0` when `settled_ord90 >= nf_orders`, `settled_roas90 / SQRT(settled_ord90)` otherwise, `NULL` at zero orders. Separation is `|return − bar| / se`, published as its own column so a reader can see which factor is binding.

- [ ] **Step 1: Join stability and compute separation**

Add the CTE:

```sql
  -- 2026-08-25 (violations 19 and 20): stability, computed at every subject with clicks — including
  -- the ones the mix-drift guard cannot check, which carry most of the unprotected money.
  stab AS (
    SELECT campaign_id AS cid, keyword_id AS kid,
           stability, stability_by_spend, stability_no_evidence,
           terms_in_window, terms_also_present_before
    FROM `onyga-482313.OI.V_KEYWORD_STABILITY`
  ),
```

and publish, in the final `SELECT`:

```sql
    -- ── SEPARATION (doctrine 2.7) ─────────────────────────────────────────────────────────────
    -- "How sure are we which side of the bar this is on?" — NOT "how much data is there", which
    -- asks the wrong question: a subject far below its bar needs little evidence to be certain, one
    -- sitting on the bar needs a great deal. se_eff is the noise band this ladder already computes.
    -- se_eff = 0 means the record has passed its family's collapse point and the band no longer
    -- shelters it, so separation is unbounded there and is capped at a large finite number rather
    -- than divided by zero.
    CASE
      WHEN s.settled_ord90 IS NULL OR s.settled_ord90 = 0 THEN NULL
      WHEN s.se_eff IS NULL                               THEN NULL
      WHEN s.se_eff = 0.0                                 THEN 99.0
      ELSE LEAST(ABS(COALESCE(s.settled_roas90, 0) - COALESCE(s.family_bar, 1.0)) / s.se_eff, 99.0)
    END                                                                 AS separation,
    st.stability,
    st.stability_by_spend,
    -- ── THE APPLICABILITY GAP, MADE VISIBLE (violation 19) ────────────────────────────────────
    -- guard_applicable requires 10 prior-window clicks (line 377), which most BROAD subjects cannot
    -- meet — measured, 125 of them carrying $156.32/day get no drift check at all. A subject whose
    -- composition CANNOT BE CHECKED must read NO_EVIDENCE on this factor and never silently pass.
    COALESCE(st.stability_no_evidence, TRUE)                            AS stability_no_evidence,
    st.terms_in_window,
    st.terms_also_present_before,
```

with the join added at the point the final `SELECT` assembles its row. **The final `SELECT` reads
`FROM fin3 s`, and `fin3` carries `campaign_id` / `keyword_id` — there is no `s.cid` or `s.kid`
anywhere in this procedure**, so the join is:

```sql
  LEFT JOIN stab st ON st.cid = s.campaign_id AND st.kid = s.keyword_id
```

`stab` aliases `V_KEYWORD_STABILITY`'s own `campaign_id` / `keyword_id` to `cid` / `kid`, so the
predicate is id-to-id with the CTE doing the renaming, which is the shape every other join in this
procedure's final `SELECT` uses.

- [ ] **Step 2: Add the columns to history, deploy, re-deploy the view**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
ALTER TABLE \`onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY\`
  ADD COLUMN IF NOT EXISTS separation                FLOAT64,
  ADD COLUMN IF NOT EXISTS stability                 FLOAT64,
  ADD COLUMN IF NOT EXISTS stability_by_spend        FLOAT64,
  ADD COLUMN IF NOT EXISTS stability_no_evidence     BOOL,
  ADD COLUMN IF NOT EXISTS terms_in_window           INT64,
  ADD COLUMN IF NOT EXISTS terms_also_present_before INT64"
```

Append the same six lines to the history DDL, then deploy the procedure, call it, and re-deploy `V_KEYWORD_STATE.sql` in the same step.

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT COUNTIF(separation IS NOT NULL) with_separation,
          COUNTIF(stability IS NOT NULL) with_stability,
          COUNTIF(stability_no_evidence) composition_uncheckable, COUNT(*) subjects
   FROM \`onyga-482313.OI.V_KEYWORD_STATE\`"
```

Expected: every subject with orders carries a `separation`; every subject with clicks carries a `stability` or reads `stability_no_evidence`.

- [ ] **Step 3: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql \
        scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql \
        scripts/bigquery/views/V_KEYWORD_STATE.sql
git commit -m "feat(catalog): separation and stability, published as their own columns

A reader can now see which of the two factors is binding, and a subject whose
composition cannot be checked reads NO_EVIDENCE rather than silently passing."
```

---

### Task 7.4 (violation 20): `confidence`, and `NO_EVIDENCE` as a distinct state

**Files:**
- Modify: `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql` (publish `confidence` and `confidence_band`)
- Modify: `scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql` (two new checks)

- [ ] **Step 1: Publish the product and the four bands**

Add to the final `SELECT`, immediately after the `stability` columns:

```sql
    -- ── CONFIDENCE (doctrine 2.7): SEPARATION x STABILITY, continuous ─────────────────────────
    -- Both factors are necessary. Separation alone calls two subjects with identical click counts
    -- equally knowable when one of them was measured on a basket that turned over 64% in a month.
    -- Stability alone says nothing about which side of the bar a subject is on.
    -- Separation is normalised into [0,1] by a soft saturation at 3 standard errors, which is where
    -- "well separated" stops meaning anything more: at 3se the sign of (return - bar) is not the
    -- question any more.
    CASE
      WHEN s.settled_clk90 IS NULL OR s.settled_clk90 = 0 THEN NULL
      WHEN s.settled_ord90 IS NULL OR s.settled_ord90 = 0 THEN NULL
      WHEN COALESCE(st.stability_no_evidence, TRUE)       THEN NULL
      ELSE LEAST(
             CASE WHEN s.se_eff IS NULL THEN 0.0
                  WHEN s.se_eff = 0.0   THEN 1.0
                  ELSE LEAST(ABS(COALESCE(s.settled_roas90, 0) - COALESCE(s.family_bar, 1.0))
                             / s.se_eff / 3.0, 1.0) END
             * COALESCE(st.stability, 0.0), 1.0)
    END                                                                 AS confidence,

    -- ── THE FOUR BANDS. NO_EVIDENCE IS NOT A LOW SCORE, IT IS A DIFFERENT STATE ──────────────
    -- Doctrine 2.7 is explicit about why: 10 found subjects whose zero orders sat on a MEDIAN OF
    -- 0.2 EXPECTED CLICKS — a zero that means nothing. A scale that collapses "no information" into
    -- "low confidence it is good" licenses kills on noise, which is precisely the failure doctrine
    -- 5 exists to prevent. Phase 2's NO_RECORD ladder arm folds into this band.
    CASE
      WHEN s.state_c = 'NO_RECORD'                        THEN 'NO_EVIDENCE'
      WHEN s.settled_clk90 IS NULL OR s.settled_clk90 = 0 THEN 'NO_EVIDENCE'
      WHEN s.settled_ord90 IS NULL OR s.settled_ord90 = 0 THEN 'NO_EVIDENCE'
      WHEN COALESCE(st.stability_no_evidence, TRUE)       THEN 'NO_EVIDENCE'
      WHEN LEAST(CASE WHEN s.se_eff = 0.0 THEN 1.0
                      ELSE LEAST(ABS(COALESCE(s.settled_roas90, 0) - COALESCE(s.family_bar, 1.0))
                                 / NULLIF(s.se_eff, 0) / 3.0, 1.0) END
                 * COALESCE(st.stability, 0.0), 1.0) >= 0.60            THEN 'HIGH'
      WHEN LEAST(CASE WHEN s.se_eff = 0.0 THEN 1.0
                      ELSE LEAST(ABS(COALESCE(s.settled_roas90, 0) - COALESCE(s.family_bar, 1.0))
                                 / NULLIF(s.se_eff, 0) / 3.0, 1.0) END
                 * COALESCE(st.stability, 0.0), 1.0) >= 0.30            THEN 'MEDIUM'
      ELSE 'LOW'
    END                                                                 AS confidence_band,
```

**The two band thresholds (0.60 and 0.30) are declared constants of this plan, not Ori's rulings.** They are placed where a HIGH requires both factors to be strong — a subject at 2 standard errors on a fully stable record scores 0.67, and one at 3 standard errors on a 60%-stable record scores 0.60 — and they are exempt from Standing Rule 0 as declared constants. If either moves, it moves in this file with the reasoning beside it.

- [ ] **Step 2: Add the columns to history and re-deploy the chain**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
ALTER TABLE \`onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY\`
  ADD COLUMN IF NOT EXISTS confidence      FLOAT64,
  ADD COLUMN IF NOT EXISTS confidence_band STRING"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT confidence_band, COUNT(*) n, ROUND(AVG(confidence), 3) avg_conf,
       ROUND(SUM(settled_sp90)/90, 2) usd_per_day,
       COUNTIF(state IN ('LOSER','DEAD','FLOOR_PROBATION')) on_a_terminal_state
FROM \`onyga-482313.OI.V_KEYWORD_STATE\` GROUP BY 1 ORDER BY n DESC"
```

Expected: four bands, and — importantly — a non-zero `on_a_terminal_state` under `NO_EVIDENCE` or `LOW`. **That count is the reason Task 7.5 exists**: those are the rows the system would kill today on evidence it does not have.

- [ ] **Step 3: Two new acceptance checks**

Append to `scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql` and add both to the UNION:

```sql
,
k12 AS (
  SELECT 'K13 the confidence bands are exhaustive and mutually exclusive',
         COUNTIF(confidence_band IS NULL
                 OR confidence_band NOT IN ('HIGH','MEDIUM','LOW','NO_EVIDENCE'))
       + COUNTIF(confidence_band = 'NO_EVIDENCE' AND confidence IS NOT NULL)
       + COUNTIF(confidence_band != 'NO_EVIDENCE' AND confidence IS NULL)
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
),
k13 AS (
  -- doctrine 5: a one-way action requires HIGH. NO_EVIDENCE is never a kill (2.7).
  SELECT 'K14 no subject reads a terminal state without HIGH confidence (doctrine 5)',
         COUNTIF(state IN ('DEAD','LOSER') AND confidence_band != 'HIGH')
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
)
```

- [ ] **Step 4: Run the suite and watch K14 fail**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql)"
```

Expected: K13 `PASS`, **K14 `FAIL` with a non-zero count** — the ladder still reaches `DEAD` and `LOSER` without consulting confidence. Task 7.5 makes it green.

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql \
        scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql \
        scripts/bigquery/views/V_KEYWORD_STATE.sql \
        scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql
git commit -m "feat(catalog): confidence = separation x stability, with NO_EVIDENCE distinct

Closes violation 20's computation. K14 is deliberately left RED: the ladder still
reaches a terminal state without consulting it, which is the next task."
```

---

### Task 7.5: Wire the gate — no irreversible action below HIGH

**Files:**
- Modify: `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql` (the ladder's terminal arms)
- Modify: `scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql:357` and `:684-688`
- Modify: `scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql` (the `FN_MOVE_CAP` confidence argument — the only task that closes Task 1.3's hard-coded `NULL`)
- Modify: `tools/build_reprice_bulksheet.py:897-903`
- Modify: `tools/tests/test_reprice_precedence.py`

- [ ] **Step 1: Gate the ladder's own terminal arms, and retire Phase 2's placeholder gate**

In the `raw_state` CASE, the arms that emit `LOSER` and `DEAD` must not fire below HIGH. Two edits
per arm: add the confidence condition, and **delete the
`AND COALESCE(v.universe_source, 'CONFIG') != 'SPEND'` predicate Task 2.4 added**. That predicate was
a placeholder standing in for exactly this gate — it kept 75 newly admitted spending subjects out of
a one-way door while confidence did not exist. Leaving both in place would permanently exempt every
spend-admitted subject from ever being closed, which is a different bug in the opposite direction.

For `LOSER`, the arm becomes:

```sql
        -- doctrine 5: only the Brain may take an irreversible action, and only on NOT_WORTH with
        -- HIGH confidence. The ladder may still SAY a record is losing; what it may not do is reach
        -- the state that a book turns into a pause. Below HIGH the subject holds at
        -- FLOOR_PROBATION, which is reversible, visible and keeps buying the evidence the verdict
        -- would need.
        -- 2026-08-25: this REPLACES the universe_source != 'SPEND' placeholder from Task 2.4 —
        -- delete that predicate in the same edit. It was the crude version of this gate, and a
        -- spend-admitted subject with a HIGH-confidence losing record should be closable like any
        -- other.
        WHEN v.probation_elapsed AND v.at_floor
         AND v.confidence_band = 'HIGH' THEN 'LOSER'
```

and the `DEAD` arm, identically:

```sql
        WHEN COALESCE(v.settled_clk90, 0) >= 15 AND COALESCE(v.settled_ord90, 0) = 0
         AND COALESCE(v.reverdict, '') NOT IN ('SIBLING_REVIVE', 'REDUNDANT')
         AND v.confidence_band = 'HIGH' THEN 'DEAD'
```

`v.confidence_band` must therefore exist in `verd`, which is three CTEs above where Task 7.4
published it. **Compute it once, in a CTE, and read it in both places** — a second copy of the
expression in the final `SELECT` is a copy that can drift from the one the ladder used:

- add a `conf` CTE immediately after `calc`, carrying `campaign_id`, `keyword_id`, `confidence` and
  `confidence_band` computed from Task 7.4's expression over `calc`'s own columns;
- `LEFT JOIN conf cf ON cf.campaign_id = c.campaign_id AND cf.keyword_id = c.keyword_id` inside
  `verd`, publishing `cf.confidence, cf.confidence_band` there;
- in the final `SELECT`, publish `s.confidence, s.confidence_band` — the values carried up from
  `verd`, **not** a re-derivation.

Confirm there is exactly one copy of the expression, and that the placeholder is gone, before
deploying:

```bash
cd /Users/ori/Develop/OI
grep -n "confidence_band" scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql
grep -n "universe_source" scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql
```

Expected: the band's defining `CASE` appears once (inside `conf`) and every other hit is a reference;
and `universe_source` appears only in the `g` CTE, the `base` CTE and the final `SELECT` — never in a
ladder arm any more.

- [ ] **Step 2: Gate the Brain's PAUSE branch**

`SP_BUILD_NEXT_WEEK_PLAN.sql:357` reads `WHEN r2.ladder_state = 'DEAD' THEN 'PAUSE'`. Replace with:

```sql
      -- 2026-08-25 (doctrine 5): the Brain executes the Catalog's terminal state — and only when
      -- the Catalog is sure. A pause removes a keyword from FACT_KEYWORD_STATE entirely, after
      -- which no layer can see it, judge it or revive it: a door that only closes.
      WHEN r2.ladder_state = 'DEAD' AND r2.confidence_band = 'HIGH'     THEN 'PAUSE'
      -- a closed keyword the Catalog is NOT sure about holds at its park price and keeps its
      -- revisit date, so the evidence that would settle it can still arrive.
      WHEN r2.ladder_state = 'DEAD'                                     THEN 'HOLD_AT_PARK'
```

and replace the assertion at 684–688's `move != 'PAUSE'` clause with:

```sql
  ASSERT (SELECT COUNTIF(ladder_state = 'DEAD'
                         AND (seat_no IS NOT NULL OR planned_bid IS NOT NULL
                              OR (is_candidate AND move NOT IN ('PAUSE', 'HOLD_AT_PARK'))))
          FROM final) = 0
    AS 'a keyword the ladder has closed takes no seat and carries no price; it is paused only at HIGH confidence (4.5, doctrine 5)';
  ASSERT (SELECT COUNTIF(move = 'PAUSE' AND confidence_band != 'HIGH') FROM final) = 0
    AS 'no irreversible action below HIGH confidence (doctrine 5)';
```

Carry `confidence_band` from the Catalog row through `V_PLAN_WINDOW_JUDGMENT`'s `base` CTE into the plan, and add it to `FACT_PLAN_NEXT_WEEK`:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
ALTER TABLE \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
  ADD COLUMN IF NOT EXISTS confidence      FLOAT64,
  ADD COLUMN IF NOT EXISTS confidence_band STRING"
```

with the same two `ALTER TABLE` lines appended to `scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql`.

- [ ] **Step 3: Gate the book's PAUSE row**

Write the failing test first, appending to `tools/tests/test_reprice_precedence.py`:

```python
def test_the_book_refuses_a_pause_below_high_confidence():
    """Doctrine 5: only the Brain may take an irreversible action, and only on NOT_WORTH with HIGH
    confidence. The book turned state == 'LOSER' straight into a PAUSE row."""
    assert "confidence_band" in SRC
    assert "REFUSED_PAUSE_LOW_CONFIDENCE" in SRC


def test_an_irreversible_row_carries_its_justification():
    """Doctrine 9: an irreversible action carries its justification on the row — the verdict, the
    confidence, and the fact that no season contradicts it."""
    assert 'no season contradicts' in SRC
```

Run it, watch it fail, then in `tools/build_reprice_bulksheet.py` replace the `if state == 'LOSER':` block at 897–903 with:

```python
    if state == 'LOSER':
        if not (b(r['probation_elapsed']) and b(r['at_floor'])):
            return 'REFUSED_PAUSE', None, None, [], bits
        # ── DOCTRINE 5: NO ONE-WAY DOOR BELOW HIGH CONFIDENCE (2026-08-25) ────────────────────
        # A pause removes a keyword from FACT_KEYWORD_STATE entirely; after that no layer can see
        # it, judge it or revive it. The ladder now publishes confidence (separation x stability),
        # and NO_EVIDENCE is a distinct band precisely because a zero sitting on a fraction of an
        # expected click is not evidence of anything.
        if (r.get('confidence_band') or 'NO_EVIDENCE') != 'HIGH':
            return ('REFUSED_PAUSE_LOW_CONFIDENCE', None, None,
                    [f"the record reads {r.get('confidence_band') or 'NO_EVIDENCE'} confidence "
                     f"(separation {r.get('separation')}, stability {r.get('stability')}) — a pause "
                     f"is a one-way door and needs HIGH"], bits)
        checks.append(
            f"IRREVERSIBLE. Catalog verdict {state} at HIGH confidence "
            f"(separation {r.get('separation')}, stability {r.get('stability')}); "
            f"the probation record is complete and no season contradicts it "
            f"(season window {r.get('season_window_label') or 'none'})")
        return 'PAUSE', 'PAUSE', None, checks, bits
```

and add `confidence`, `confidence_band`, `separation`, `stability` and `season_window_label` to the columns the book selects from `V_KEYWORD_STATE` at line 486.

- [ ] **Step 3b: Close Task 1.3's hard-coded NULL confidence in the preflight**

`SP_ENGINE_PREFLIGHT` calls `FN_MOVE_CAP(r.current_bid, …, NULL)` in three places — `move_cap_bid`
and the two verdict arms — with a literal `NULL`, because confidence did not exist when Task 1.3 was
written. The function's whole asymmetry is inert until that literal is replaced: with `NULL` every
cut walks, including a cut to a ceiling nobody disputes, which is §3.1's rule inverted. **No other
task in this plan touches those call sites.** Back up the procedure (header Step 0), then:

- widen the `cat` CTE's select list with `confidence_band`;
- carry it into `ranked` beside `catalog_state`, as `ct.confidence_band AS catalog_confidence_band`;
- in the final `SELECT`, the three calls become
  `FN_MOVE_CAP(r.current_bid, 'DOWN', r.catalog_confidence_band)` and
  `FN_MOVE_CAP(r.current_bid, 'UP', r.catalog_confidence_band)`;
- publish `r.catalog_confidence_band` on `T_ENGINE_PREFLIGHT` so an audit can see which band produced
  the cap.

Then deploy and check the asymmetry is actually live:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_ENGINE_PREFLIGHT\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT COALESCE(catalog_confidence_band, '(none)') band,
       COUNTIF(suggested_bid < current_bid) cuts,
       COUNTIF(suggested_bid < current_bid AND move_cap_bid = 0.0) cuts_allowed_in_one_step
FROM \`onyga-482313.OI.T_ENGINE_PREFLIGHT\` WHERE lever = 'BID' GROUP BY 1 ORDER BY cuts DESC"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/ENGINE_PREFLIGHT_acceptance.sql)"
```

Expected: `cuts_allowed_in_one_step` equals `cuts` on the `HIGH` band and is `0` on every other band
— that is §3.1's asymmetry finally binding — and every acceptance row `PASS`, `E04b` included.

- [ ] **Step 4: Deploy everything and run every suite**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`()"
for s in FACT_KEYWORD_STATE_acceptance CATALOG_COVERAGE_acceptance \
         FACT_PLAN_NEXT_WEEK_acceptance V_PLAN_WINDOW_JUDGMENT_acceptance \
         ENGINE_PREFLIGHT_acceptance FACT_CAMPAIGN_STATE_acceptance \
         CAMPAIGN_IDENTITY_acceptance PLAN_CONFIG_acceptance; do
  echo "=== $s ==="
  bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
    "$(grep -v '^--' scripts/bigquery/tests/$s.sql)" | grep -c ',PASS' || echo "CHECK $s"
done
/usr/local/bin/python3 -m pytest tools/tests/ -q
```

Expected: **K14 now reads `PASS`**, every suite is green, and every Python test passes.

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql \
        scripts/bigquery/views/V_KEYWORD_STATE.sql \
        scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql \
        scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql \
        scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql \
        scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql \
        tools/build_reprice_bulksheet.py tools/tests/test_reprice_precedence.py
git commit -m "feat(all): no irreversible action below HIGH confidence

Closes violation 20. Gated in three places — the ladder's terminal arms, the
Brain's PAUSE branch, and the book's pause row — every irreversible row now
carries its justification (the verdict, the confidence, and the season), and the
preflight's move cap finally receives a real confidence band instead of NULL, so
3.1's asymmetry binds."
```

---

### Task 7.6 (violation 22, CLOSE half): the campaign door, gated

**Files:**
- Modify: `scripts/bigquery/procedures/SP_SNAPSHOT_CAMPAIGN_STATE.sql` (confidence at campaign grain, and the CLOSE arm)
- Modify: `scripts/bigquery/tables/FACT_CAMPAIGN_STATE.sql` (four ALTER lines)
- Modify: `scripts/bigquery/tests/FACT_CAMPAIGN_STATE_acceptance.sql`

§4.1 makes the campaign pause the one irreversible action allowed on something other than `NOT_WORTH`, and **only** on condition it carries its reopen date. A close without a reopen date is §5's one-way door wearing different clothes.

- [ ] **Step 1: Add the columns**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
ALTER TABLE \`onyga-482313.OI.FACT_CAMPAIGN_STATE\`
  ADD COLUMN IF NOT EXISTS separation      FLOAT64,
  ADD COLUMN IF NOT EXISTS stability       FLOAT64,
  ADD COLUMN IF NOT EXISTS confidence      FLOAT64,
  ADD COLUMN IF NOT EXISTS confidence_band STRING,
  ADD COLUMN IF NOT EXISTS intent          STRING,
  ADD COLUMN IF NOT EXISTS intent_reason   STRING"
```

Append the same six lines to the DDL. **`intent` is the column §4.1's table is written in** — it
names exactly two values, `OPEN` and `CLOSE`, plus `NONE` where the Catalog has an answer but no
action follows from it. The verdict says what is true; the intent says what the Brain asks Pacing to
do about it, and keeping them in two columns is what stops a verdict reading as a command (§1.1).

- [ ] **Step 2: Compute confidence at campaign grain**

In `SP_SNAPSHOT_CAMPAIGN_STATE.sql`, add a temp table before the INSERT:

```sql
  -- confidence at CAMPAIGN grain (doctrine 2.7). Separation is the same shape as the keyword's:
  -- how sure we are which side of the bar the campaign's own quarter sits on, in units of its noise
  -- band. Stability is the share of the campaign's window clicks that came from keywords the prior
  -- window also served — the campaign-level analogue of V_KEYWORD_STABILITY, and it matters here
  -- because a campaign whose keyword set was rebuilt is not the same campaign it was.
  CREATE OR REPLACE TEMP TABLE conf AS
  WITH k AS (
    SELECT CAST(a.campaign_id AS STRING) AS cid,
           CAST(a.keyword_id  AS STRING) AS kid,
           SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 91 DAY)
                             AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_clicks, 0)) AS now_clicks,
           SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 182 DAY)
                             AND DATE_SUB((SELECT d FROM wm), INTERVAL 92 DAY), a.Ads_clicks, 0)) AS prior_clicks
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
    WHERE a.keyword_id IS NOT NULL
    GROUP BY 1, 2
  )
  SELECT cid,
         SAFE_DIVIDE(SUM(IF(prior_clicks > 0, now_clicks, 0)), NULLIF(SUM(now_clicks), 0)) AS stability,
         (SUM(prior_clicks) = 0)                                                           AS stability_no_evidence
  FROM k GROUP BY cid;
```

and in the INSERT, publish the four columns using the same shape as the keyword grain — separation from the campaign's own quarter return against its bar over `return / SQRT(orders)`, confidence as the product with the same 3-standard-error saturation, and the same four bands with `NO_EVIDENCE` distinct.

- [ ] **Step 3: Ship the `NOT_WORTH` verdict, gated**

Add to the verdict CASE, as the **first** arm so it takes precedence over `NOT_WORTH_NOW`:

```sql
      -- ── NOT_WORTH AT CAMPAIGN GRAIN (2026-08-25) ────────────────────────────────────────────
      -- The DEEPER of the two negative answers: no value in ANY season, so both its own quarter
      -- AND the same window last year are below its bar. A campaign that earned last season is
      -- NOT_WORTH_NOW, never NOT_WORTH — that is the distinction doctrine 4 calls the single most
      -- expensive mistake it exists to prevent. HIGH confidence (doctrine 5), which did not exist
      -- until this phase, is required because this is the verdict that closes a campaign for good
      -- rather than until its window comes round.
      WHEN COALESCE(ev.m3_spend, 0) > 0
       AND SAFE_DIVIDE(ev.m3_gp, ev.m3_spend) < COALESCE(bar.campaign_bar, 1.0)
       AND COALESCE(ev.season_spend, 0) > 0
       AND SAFE_DIVIDE(ev.season_gp, ev.season_spend) < COALESCE(bar.campaign_bar, 1.0)
       AND cf.confidence_band = 'HIGH'
        THEN 'NOT_WORTH'
```

`reopen_date` needs no new arm: Task 4.5 already dates **every** answerable verdict, and a
`NOT_WORTH` campaign's re-ask date is the same lead-time-adjusted window start as any other. The
assertion at the foot of the procedure already covers `NOT_WORTH` and now does real work.

- [ ] **Step 3b: Ship the two INTENTS — `CLOSE` is `NOT_WORTH_NOW`'s intent, not `NOT_WORTH`'s**

**Read §4.1 before writing this, because the obvious arm is the wrong one.** The doctrine's table
says `CLOSE · reopen D` means **"its season has ended"** — which is `NOT_WORTH_NOW`, not `NOT_WORTH`.
And the asymmetry paragraph is explicit: *"a campaign has no park … so the only available expression
of `NOT_WORTH_NOW` at this grain **is** a pause, which means the campaign pause is the one
irreversible action the doctrine must permit on something other than `NOT_WORTH`."* Firing `CLOSE`
only on `NOT_WORTH` would leave a seasonal campaign that is simply out of season with no intent at
all — running through its whole off-season because the layer that knows it is dormant has no way to
say so. That is the narrowing this step exists to avoid; `FACT_CAMPAIGN_STATE`'s own table
description says the same thing in the DDL Task 4.4 shipped.

Add the intent expressions to the `INSERT`, beside `reopen_date`:

```sql
    -- ── THE INTENT (2026-08-25, violation 22). Doctrine 4.1's two campaign-grain intents, and
    -- nothing else. The VERDICT is what is true; the INTENT is what the Brain asks Pacing to do
    -- about it. Two columns, because a verdict that reads as an instruction is 1.1's violation.
    --   OPEN  · by date D  — WORTH, and it is not running. Enable with lead time (r.window_from
    --                        minus lead_time_days, which reopen_date already carries).
    --   CLOSE · reopen D   — its season has ended: NOT_WORTH_NOW, or the deeper NOT_WORTH. Pause
    --                        it, and carry the reopen date. HIGH CONFIDENCE ON BOTH: a pause is
    --                        this grain's one-way door (5), and it is gated whichever verdict
    --                        produced it.
    --   NONE               — WORTH and already running, or UNKNOWN. There is nothing to execute,
    --                        and saying so is not the same as having no answer.
    CASE
      WHEN vd.verdict = 'WORTH' AND ci.campaign_state != 'ENABLED'         THEN 'OPEN'
      WHEN vd.verdict IN ('NOT_WORTH_NOW', 'NOT_WORTH')
       AND ci.campaign_state = 'ENABLED'
       AND cf.confidence_band = 'HIGH'                                     THEN 'CLOSE'
      ELSE 'NONE'
    END                                                               AS intent,
    CASE
      WHEN vd.verdict = 'WORTH' AND ci.campaign_state != 'ENABLED'
        THEN FORMAT('OPEN by %t — it earned in this window last year and it is not running. %d days of lead time are already subtracted, so it can re-accumulate signal before the window opens.',
                    r_reopen, lead_time)
      WHEN vd.verdict IN ('NOT_WORTH_NOW', 'NOT_WORTH')
       AND ci.campaign_state = 'ENABLED' AND cf.confidence_band = 'HIGH'
        THEN FORMAT('CLOSE, reopen %t — %s A campaign has no park, so a pause is the only way to say NOT WORTH NOW at this grain (4.1), and it carries its reopen date because a close without one is a one-way door (5).',
                    r_reopen, vd.verdict_reason)
      WHEN vd.verdict IN ('NOT_WORTH_NOW', 'NOT_WORTH') AND ci.campaign_state = 'ENABLED'
        THEN FORMAT('NO INTENT — the answer is %s but the record reads %s confidence, and a campaign pause is irreversible at this grain. Doctrine 5: a one-way door needs HIGH.',
                    vd.verdict, COALESCE(cf.confidence_band, 'NO_EVIDENCE'))
      ELSE 'NO INTENT — nothing to execute: it is either already in the state the answer calls for, or the answer is UNKNOWN.'
    END                                                               AS intent_reason,
```

**The verdict, the reopen date and the lead time are each written three times in this `INSERT`
already** (once for the column, once for `verdict_reason`, once for `state_reason`) and the arms
above would make it five. Do not copy them a fourth and fifth time: hoist the verdict and its reason
into a `vd` CTE and the reopen date and lead time into scalars, exactly as the existing `ev` / `bar`
/ `cf` temp tables are hoisted, and read `vd.verdict`, `vd.verdict_reason`, `r_reopen` and
`lead_time` everywhere. Two copies of a first-match `CASE` in one `SELECT` is how the arms drift
apart, and this one decides whether a campaign runs.

Finally, add a third assertion at the foot of the procedure:

```sql
  -- 4.1: a CLOSE carries its reopen date, and 5: it is never issued below HIGH confidence.
  ASSERT (SELECT COUNTIF(intent = 'CLOSE'
                         AND (reopen_date IS NULL OR confidence_band != 'HIGH'))
          FROM `onyga-482313.OI.FACT_CAMPAIGN_STATE` WHERE snapshot_date = snap) = 0
    AS 'a CLOSE carries its reopen date and is issued only at HIGH confidence (4.1, 5)';
```

- [ ] **Step 4: Two more acceptance checks**

Append to `scripts/bigquery/tests/FACT_CAMPAIGN_STATE_acceptance.sql` and add both to the UNION:

```sql
,
c10 AS (
  SELECT 'C10 no campaign is closed below HIGH confidence (doctrine 5, 4.1)',
         COUNTIF(verdict = 'NOT_WORTH' AND COALESCE(confidence_band, 'NO_EVIDENCE') != 'HIGH')
  FROM c
),
c11 AS (
  SELECT 'C11 a campaign that earned in this window last year is never NOT_WORTH (doctrine 4)',
         COUNTIF(verdict = 'NOT_WORTH' AND season_spend > 0
                 AND SAFE_DIVIDE(season_gp, NULLIF(season_spend, 0))
                     >= COALESCE(campaign_bar, 1.0))
  FROM c
),
c12 AS (
  SELECT 'C12 every CLOSE carries a reopen date and HIGH confidence (4.1, doctrine 5)',
         COUNTIF(intent = 'CLOSE' AND (reopen_date IS NULL OR confidence_band != 'HIGH'))
       + COUNTIF(intent NOT IN ('OPEN', 'CLOSE', 'NONE') OR intent IS NULL)
       + COUNTIF(intent IS NOT NULL AND intent_reason IS NULL)
  FROM c
),
c13 AS (
  -- The narrowing check. 4.1: "the only available expression of NOT_WORTH_NOW at this grain IS a
  -- pause." A running campaign the Catalog has answered NOT_WORTH_NOW at HIGH confidence, carrying
  -- no CLOSE, is a campaign nobody will ever stop — the exact shape of the ten paused campaigns
  -- with no reopen date, inverted. If this goes red the intent CASE fired on NOT_WORTH only.
  SELECT 'C13 a HIGH-confidence dormant seasonal campaign that is RUNNING carries a CLOSE (4.1)',
         COUNTIF(verdict IN ('NOT_WORTH_NOW', 'NOT_WORTH') AND campaign_state = 'ENABLED'
                 AND confidence_band = 'HIGH' AND intent != 'CLOSE')
  FROM c
)
```

- [ ] **Step 5: Deploy, run, verify**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tables/FACT_CAMPAIGN_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_CAMPAIGN_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_CAMPAIGN_STATE\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/FACT_CAMPAIGN_STATE_acceptance.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT verdict, confidence_band, COUNT(*) n, COUNTIF(reopen_date IS NULL) without_a_date
   FROM \`onyga-482313.OI.FACT_CAMPAIGN_STATE\`
   WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_CAMPAIGN_STATE\`)
   GROUP BY 1,2 ORDER BY n DESC"
```

Add `intent` to the read-back query's `GROUP BY` so the two answers are visible side by side:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT verdict, campaign_state, confidence_band, intent, COUNT(*) n,
          COUNTIF(reopen_date IS NULL) without_a_date
   FROM \`onyga-482313.OI.FACT_CAMPAIGN_STATE\`
   WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_CAMPAIGN_STATE\`)
   GROUP BY 1,2,3,4 ORDER BY n DESC"
```

Expected: **thirteen** acceptance rows all `PASS`; `without_a_date = 0` on every `WORTH`,
`NOT_WORTH_NOW` and `NOT_WORTH` row; a `CLOSE` count that is non-zero only where
`campaign_state = 'ENABLED'` **and** `confidence_band = 'HIGH'`; and an `OPEN` count that appears only
on paused `WORTH` rows. If `CLOSE` is zero everywhere, check whether it is because no campaign reaches
`HIGH` — which is the honest outcome and belongs in the measurements file — or because the intent arm
was written on `NOT_WORTH` alone, which C13 will have caught.

- [ ] **Step 6: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/tables/FACT_CAMPAIGN_STATE.sql \
        scripts/bigquery/procedures/SP_SNAPSHOT_CAMPAIGN_STATE.sql \
        scripts/bigquery/tests/FACT_CAMPAIGN_STATE_acceptance.sql
git commit -m "feat(catalog): the campaign CLOSE intent, gated on HIGH confidence and a reopen date

The verdict half of violation 22's close. Withheld from Phase 4 on purpose: a
campaign has no park, so CLOSE is a new irreversible action and doctrine 5 forbids
one below HIGH. CLOSE fires on NOT_WORTH_NOW as well as NOT_WORTH, because 4.1's
'its season has ended' IS the dormant answer at this grain. Task 7.7 gives it hands."
```

---

### Task 7.7 (violation 22, the execution half): `build_campaign_close_bulksheet.py`

**Files:**
- Create: `tools/build_campaign_close_bulksheet.py`
- Create: `tools/build_restore_campaign_close_bulksheet.py`
- Modify: `tools/tests/test_change_log_discipline.py` (add both to `BOOKS`)

**§1 names the Catalog's characteristic failure exactly: *"knows the truth, has no hands — a correct
answer can sit unexecuted for weeks."*** Task 7.6 gives the account a `CLOSE` intent. Nothing
executes it. Task 4.7's reopen book, by its own docstring, reads *"rows whose verdict is `WORTH`,
whose campaign is not currently `ENABLED`, and whose `reopen_date` has arrived"* and emits
`State=enabled` rows only — so violation 22 would close on the verdict side and stay open on the
execution side, which is structurally the same defect as violation 25 (an answer with no book to
travel in) at campaign grain. §4.1 assigns Pacing an obligation on `CLOSE`: *"pause it, and carry the
reopen date."* This task is that obligation.

- [ ] **Step 1: Write the failing test first**

Extend `BOOKS` in `tools/tests/test_change_log_discipline.py`:

```python
import build_campaign_close_bulksheet as close  # noqa: E402

BOOKS = [leak, reprice, unpause, reopen, close]
```

```bash
cd /Users/ori/Develop/OI
/usr/local/bin/python3 -m pytest tools/tests/test_change_log_discipline.py -q
```

Expected: FAIL at import — `ModuleNotFoundError: No module named 'build_campaign_close_bulksheet'`.

- [ ] **Step 2: Write the generator as a mirror of the reopen book**

It is Task 4.7's book with three differences and **nothing else invented**: copy that file, then

1. select on `intent = 'CLOSE'` rather than `verdict = 'WORTH' AND campaign_state != 'ENABLED'`, and
   require `campaign_state = 'ENABLED'` (a campaign already paused needs no row) and
   `confidence_band = 'HIGH'` — **the book re-asserts the gate rather than trusting the upstream
   one**, because this is the account's one campaign-grain irreversible action and a two-sided check
   costs nothing;
2. emit `State` = `paused` instead of `enabled`, with `action = 'CAMPAIGN_CLOSE'` in the change log;
3. **write `reopen_date` into the change-log row and into every README line.** This is the whole
   reason the book exists rather than a person pausing ten campaigns by hand: §4.1 says the reopen
   *"must be recorded where a layer will act on it — not remembered by a person."* The row that
   pauses the campaign is the row that carries the date it comes back, and Task 4.7's reopen book is
   what acts on that date. Add `reopen_date DATE` to `FACT_PPC_CHANGE_LOG` in this task
   (`ALTER TABLE ... ADD COLUMN IF NOT EXISTS reopen_date DATE`, and the same line appended to the
   DDL) and include it in `log_batch`'s column list and `STRUCT`.

The **blank Portfolio ID trap** applies here exactly as it does to the reopen book: on a Campaign
Update row a blank Portfolio ID is a **detach**, not "unchanged". Echo `portfolio_id` from
`V_CAMPAIGN_IDENTITY` on every row. The README explains each campaign top-down — Catalog verdict and
its evidence, then the Brain's intent and reopen date, then the single Pacing action — per §9.

The restore generator is the mirror of `tools/build_restore_campaign_reopen_bulksheet.py`: it emits
`State=enabled` for a batch of closes, logs a **new** batch that names what it reverses, and deletes
nothing.

- [ ] **Step 3: Both new books use the house change-log shape, not an environment variable**

Task 4.7 Step 3b defines it. Repeat it here for both files: `LIVE_CHANGE_LOG`, module-global
`CHANGE_LOG`, `set_change_log_table()` with the `TMP_`/`TEMP_` assertion, and a `--change-log-table`
argument. `test_a_change_log_override_must_be_a_tmp_copy` reads all four names directly and fails
without them.

- [ ] **Step 4: Run the tests, then build against a TMP copy**

```bash
cd /Users/ori/Develop/OI
/usr/local/bin/python3 -m pytest tools/tests/test_change_log_discipline.py -q
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CREATE OR REPLACE TABLE \`onyga-482313.OI.TMP_PPC_CHANGE_LOG_CLOSE\` AS
   SELECT * FROM \`onyga-482313.OI.FACT_PPC_CHANGE_LOG\` WHERE FALSE"
/usr/local/bin/python3 tools/build_campaign_close_bulksheet.py \
  --change-log-table TMP_PPC_CHANGE_LOG_CLOSE -o .tmp/campaign_close_check.xlsx
cat .tmp/campaign_close_check_README.txt
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT action, upload_status, COUNT(*) n, COUNTIF(reopen_date IS NULL) without_a_reopen_date
   FROM \`onyga-482313.OI.TMP_PPC_CHANGE_LOG_CLOSE\` GROUP BY 1,2"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "DROP TABLE \`onyga-482313.OI.TMP_PPC_CHANGE_LOG_CLOSE\`"
```

Expected: all discipline tests PASS across **five** books; every logged row
`CAMPAIGN_CLOSE` / `PENDING_UPLOAD`; and **`without_a_reopen_date = 0`** — a close with no reopen date
is the one-way door §4.1 forbids, and the book must refuse to emit one rather than log it. **An empty
book is a legitimate outcome** and must print a sentence saying so: it means no running campaign is
`NOT_WORTH_NOW` at `HIGH` confidence today, which is information, not a failure.

- [ ] **Step 5: Commit, and strike violation 22 in §8**

```bash
cd /Users/ori/Develop/OI
git add tools/build_campaign_close_bulksheet.py \
        tools/build_restore_campaign_close_bulksheet.py \
        tools/tests/test_change_log_discipline.py \
        scripts/bigquery/tables/FACT_PPC_CHANGE_LOG.sql \
        architecture/THREE_LAYERS.md
git commit -m "feat(books): the campaign close book — a CLOSE finally has hands

Closes violation 22 end to end. Task 7.6 gave the account a CLOSE intent and
nothing executed it, which is section 1's 'knows the truth, has no hands' at
campaign grain. Every row carries its reopen date into the change log, so the
reopen book acts on it and no person has to remember."
```

---
## Phase 8 — The four-field contract, and the first lean-in

**Closes:** violations 1 and 10.

**Why the headline defect is deliberately near the end.** Publishing a `verdict` column before the seasonal answer (Phase 5) and confidence (Phase 7) existed would have been a **rename, not a fix** — and a cosmetic contract is worse than an honest command. By now three of the four fields are real: `verdict` from Phase 5's seasonal answer, `confidence` from Phase 7, `expected_clicks` from our own history. Only `ceiling_cpc` is still an average, and the honest move is to publish it **flagged as such** rather than wait for Phase 10.

**Violation 10 rides with it** because `LEAN_IN · ceiling C` cannot be issued until a ceiling is published, and because it is the plan's first genuine throughput increase — correctly placed after the ceiling binds (Phase 1), after the forbidden state is gone (Phase 6), and after confidence exists (Phase 7), since §2.7 licenses a lean-in at MEDIUM and above. The money: 57 constrained winners, $412.77/day of spend returning $565.25/day of GP, $174.73/day of headroom to `affordable_cpc`, and **100% of them at `move = NONE`**.

**Unblocks:** §9's UI shape (Catalog → Brain → Pacing, with `NOT_WORTH_NOW` reading differently from `NOT_WORTH`); Phase 10, which swaps `ceiling_basis` from `AVERAGE` to `MARGINAL` behind an unchanged contract — the whole point of a narrow interface.

**Size:** M–L — 1.5–2 weeks, of which the P-4 ruling is the long pole and is a conversation, not code.

---

### Task 8.1: The red measurement — the state IS the action

- [ ] **Step 1: Show there is no contract**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT column_name FROM \`onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS\`
   WHERE table_name = 'FACT_KEYWORD_STATE'
     AND LOWER(column_name) IN ('verdict','ceiling_cpc','expected_clicks')"
grep -n "state IN ('AT_BAR','REPRICE','FLOOR_PROBATION','LOSER')" tools/build_reprice_bulksheet.py
```

Expected: zero columns from the first (only `confidence` from Phase 7 exists), and a hit from the second — the book selects on the ladder's command words and turns `LOSER` into a `PAUSE`. **The state is the action.**

- [ ] **Step 2: Record the measurement and commit it**

Every red measurement in this plan is a number the green run is compared against, so it is written
down rather than remembered. Append what you measured — the query, the date, and the count — to the
running record, creating the file on the first task that reaches this step:

```bash
cd /Users/ori/Develop/OI
mkdir -p docs/superpowers/specs
cat >> docs/superpowers/specs/2026-08-25-gap-closure-measurements.md <<'EOF'

## Task 8.1 — measured YYYY-MM-DD

Replace the date above with the date you ran it, and paste below: the query you ran (unchanged from
the task), and its output. Do not summarise the output — the point of this file is that a re-run is
a re-run and not a fresh argument, which is the same reason
docs/superpowers/specs/2026-08-24-three-layers-baseline.md exists.
EOF
git add docs/superpowers/specs/2026-08-25-gap-closure-measurements.md
git commit -m "measure(task 8.1): record the red measurement before the fix

The number the green run is compared against, written down rather than remembered."
```

---

### Task 8.2 (violation 1): publish the four fields

**Files:**
- Modify: `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql` (final `SELECT`)
- Modify: `scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql`
- Re-deploy: `scripts/bigquery/views/V_KEYWORD_STATE.sql`

- [ ] **Step 1: Add the columns to history**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
ALTER TABLE \`onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY\`
  ADD COLUMN IF NOT EXISTS verdict                STRING,
  ADD COLUMN IF NOT EXISTS ceiling_cpc            FLOAT64,
  ADD COLUMN IF NOT EXISTS ceiling_basis          STRING,
  ADD COLUMN IF NOT EXISTS expected_clicks        FLOAT64,
  ADD COLUMN IF NOT EXISTS expected_clicks_source STRING"
```

Append the same five lines to the history DDL.

- [ ] **Step 2: Publish the contract**

Add to the final `SELECT` of `SP_SNAPSHOT_KEYWORD_STATE.sql`, placed **first** in the row so a reader meets the contract before the machinery:

```sql
    -- ═══ THE CATALOG CONTRACT (doctrine 2). FOUR FIELDS, AND NOTHING SHAPED LIKE A COMMAND. ═══
    -- Doctrine 1.1: a verdict shaped like an instruction turns into an Amazon action without anyone
    -- having decided, and it is meaningless to a caller that is not the Brain — a dashboard asking
    -- "what is this worth in November" cannot act on DEAD. The ladder's own words (WINNER, DEAD,
    -- REPRICE) stay on the row as internal machinery, and nothing new may select on them.
    --
    -- verdict: WORTH | NOT_WORTH | NOT_WORTH_NOW | UNKNOWN, and only those four.
    --   NOT_WORTH requires HIGH confidence, because it is the only one that licenses a one-way
    --   action (doctrine 4, 5). NOT_WORTH_NOW is the seasonal answer Phase 5 built. UNKNOWN covers
    --   both "no record" and "a record that cannot speak" — NO_EVIDENCE, never a low score.
    CASE
      WHEN s.state_c = 'NOT_WORTH_NOW'                                   THEN 'NOT_WORTH_NOW'
      WHEN s.state_c IN ('NO_RECORD', 'PENDING_SETTLE', 'REVIVED_SETTLING')
                                                                          THEN 'UNKNOWN'
      WHEN cf.confidence_band = 'NO_EVIDENCE'                             THEN 'UNKNOWN'
      WHEN s.state_c IN ('DEAD', 'LOSER') AND cf.confidence_band = 'HIGH' THEN 'NOT_WORTH'
      WHEN s.state_c IN ('WINNER', 'PACED_WINNER', 'AT_BAR', 'TRIAL')     THEN 'WORTH'
      WHEN COALESCE(s.settled_roas90, 0) >= COALESCE(s.family_bar, 1.0)   THEN 'WORTH'
      WHEN cf.confidence_band IN ('HIGH', 'MEDIUM')                       THEN 'NOT_WORTH_NOW'
      ELSE 'UNKNOWN'
    END                                                                 AS verdict,

    -- ceiling_cpc: what the NEXT click is worth, at the bar, for the window being asked about.
    -- IT IS AN AVERAGE TODAY AND THE ROW SAYS SO. Doctrine 2 requires the MARGINAL value and 6.3
    -- forbids asserting a number we have not computed, so ceiling_basis reads AVERAGE until the
    -- response curve exists (violation 3, Phase 10). When it does, this expression changes and NO
    -- CONSUMER MOVES — which is the entire point of a narrow interface (1.4).
    s.affordable_cpc                                                    AS ceiling_cpc,
    'AVERAGE'                                                           AS ceiling_basis,

    -- expected_clicks: clicks this subject typically takes in a window like the one asked about.
    -- OUR history, not the market's — doctrine 2.8 is explicit that this cannot value a subject the
    -- account never bought, nor say whether an owned one is capturing its opportunity. Phase 11
    -- adds market volume beside it and flips this source; it does not replace it.
    SAFE_DIVIDE(s.settled_clk90, 90.0)
      * DATE_DIFF(COALESCE(s.season_window_to, DATE_ADD(t.d, INTERVAL 7 DAY)),
                  COALESCE(s.season_window_from, t.d), DAY)             AS expected_clicks,
    'OURS'                                                              AS expected_clicks_source,
```

- [ ] **Step 3: Deploy, re-deploy the view in the same step, and read the contract**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT verdict, confidence_band, ceiling_basis, COUNT(*) n,
       ROUND(AVG(ceiling_cpc), 3) avg_ceiling, ROUND(AVG(expected_clicks), 2) avg_expected_clicks
FROM \`onyga-482313.OI.V_KEYWORD_STATE\` GROUP BY 1,2,3 ORDER BY n DESC"
```

Expected: four verdicts, `ceiling_basis` reading `AVERAGE` on every row, and **no `NOT_WORTH` row outside `HIGH` confidence**.

- [ ] **Step 4: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql \
        scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql \
        scripts/bigquery/views/V_KEYWORD_STATE.sql
git commit -m "feat(catalog): publish the four-field contract — verdict, ceiling, confidence, clicks

Closes violation 1. ceiling_basis reads AVERAGE and expected_clicks_source reads
OURS, because 6.3 forbids asserting numbers we have not computed. Phase 10 flips
the first and Phase 11 the second, behind an unchanged contract."
```

---

### Task 8.3: Demote the command words, migrate the book

**Files:**
- Modify: `tools/build_reprice_bulksheet.py:484-486` and the disposition function
- Modify: `tools/tests/test_reprice_precedence.py`

`state`, `raw_state` and `clean_state` stay on the row — 27 files read them — but nothing new may select on them, and the existing consumer migrates to `verdict` + `ceiling_cpc` + `confidence_band`.

- [ ] **Step 1: Write the failing test**

```python
def test_the_book_consumes_the_contract_not_the_ladder_words():
    """Doctrine 1.1: a verdict shaped like a command turns into an Amazon action without anyone
    having decided. The book selected WHERE state IN ('AT_BAR','REPRICE','FLOOR_PROBATION','LOSER')
    and turned LOSER into a PAUSE — the state WAS the action."""
    assert "state IN ('AT_BAR','REPRICE','FLOOR_PROBATION','LOSER')" not in SRC
    assert "verdict IN ('NOT_WORTH', 'NOT_WORTH_NOW')" in SRC
    assert 'ceiling_cpc' in SRC
```

Run it and watch it fail.

- [ ] **Step 2: Change the selection**

`tools/build_reprice_bulksheet.py` at 484–486 reads:

```python
ks AS (
  SELECT * FROM `{p}.OI.V_KEYWORD_STATE`
  WHERE state IN ('AT_BAR','REPRICE','FLOOR_PROBATION','LOSER')
),
```

Replace with:

```python
ks AS (
  -- 2026-08-25 (violation 1): the book selects on the CATALOG CONTRACT, not on the ladder's
  -- command words. Doctrine 1.1: a verdict shaped like an instruction becomes an Amazon action
  -- without anyone having decided, and it means nothing to a caller that is not the Brain.
  -- WORTH keywords are not in this book at all — they are not repaired. NOT_WORTH_NOW is here so
  -- the book can HOLD it and say why, never so it can cut it.
  SELECT * FROM `{p}.OI.V_KEYWORD_STATE`
  WHERE verdict IN ('NOT_WORTH', 'NOT_WORTH_NOW')
     OR (verdict = 'WORTH' AND ceiling_cpc IS NOT NULL
         AND current_bid > ceiling_cpc / COALESCE(m_effective, 1.0) + 0.005)
),
```

The third clause is what keeps the `AT_BAR` repricing behaviour: a keyword that is worth having but is currently priced above its ceiling still needs its price brought down.

- [ ] **Step 3: Rewrite the disposition head to read the contract**

Replace the `state ==` tests in the disposition function with `verdict ==` tests, keeping every downstream branch identical:

```python
    verdict = r.get('verdict')
    ceiling = num(r.get('ceiling_cpc'))
    band = r.get('confidence_band') or 'NO_EVIDENCE'

    # NOT_WORTH_NOW: dormant, not dead. Doctrine 4 — park at floor, never pause, never cut into a
    # season. The Catalog owns this distinction since Phase 5; the book only reads it.
    if verdict == 'NOT_WORTH_NOW':
        return ('SEASONAL_HOLD', None, None,
                [f"the keyword state says this is dormant, not dead: {r.get('state_reason') or ''}"],
                bits)

    # NOT_WORTH at HIGH confidence is the only path to a pause row (doctrine 5).
    if verdict == 'NOT_WORTH':
        if not (b(r['probation_elapsed']) and b(r['at_floor'])):
            return 'REFUSED_PAUSE', None, None, [], bits
        if band != 'HIGH':
            return ('REFUSED_PAUSE_LOW_CONFIDENCE', None, None,
                    [f"the record reads {band} confidence (separation {r.get('separation')}, "
                     f"stability {r.get('stability')}) — a pause is a one-way door and needs HIGH"],
                    bits)
        checks.append(
            f"IRREVERSIBLE. Catalog verdict NOT_WORTH at HIGH confidence "
            f"(separation {r.get('separation')}, stability {r.get('stability')}); "
            f"the probation record is complete and no season contradicts it "
            f"(season window {r.get('season_window_label') or 'none'})")
        return 'PAUSE', 'PAUSE', None, checks, bits
```

Everywhere the pricing path previously read `afford_cpc` from `affordable_cpc`, read `ceiling_cpc` instead — it is the same number today (`ceiling_basis = 'AVERAGE'`) and becomes the marginal one in Phase 10 with no further change here.

- [ ] **Step 4: Run every test and build against a TMP copy**

**`--change-log-table`, never a `CHANGE_LOG=` environment variable.** The book's change-log target is
a module global changed only by `set_change_log_table()`, which is reachable only through that flag
and which asserts a `TMP_`/`TEMP_` prefix. A shell assignment is ignored and the rows land in the
live log, where the house rule forbids removing them. Pass the **bare** table name — a
project-qualified string fails the assertion. Same rule as Task 0.6 Step 6; see the paragraph there.

```bash
cd /Users/ori/Develop/OI
/usr/local/bin/python3 -m pytest tools/tests/ -q
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CREATE OR REPLACE TABLE \`onyga-482313.OI.TMP_PPC_CHANGE_LOG_CONTRACT\` AS
   SELECT * FROM \`onyga-482313.OI.FACT_PPC_CHANGE_LOG\` WHERE FALSE"
/usr/local/bin/python3 tools/build_reprice_bulksheet.py \
  --change-log-table TMP_PPC_CHANGE_LOG_CONTRACT -o .tmp/reprice_contract_check.xlsx
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT action, COUNT(*) n FROM \`onyga-482313.OI.TMP_PPC_CHANGE_LOG_CONTRACT\` GROUP BY 1"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT COUNTIF(DATE(applied_at) = CURRENT_DATE('America/Los_Angeles')
                  AND upload_status = 'PENDING_UPLOAD') AS rows_written_to_the_LIVE_log_today
   FROM \`onyga-482313.OI.FACT_PPC_CHANGE_LOG\`"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "DROP TABLE \`onyga-482313.OI.TMP_PPC_CHANGE_LOG_CONTRACT\`"
```

Expected: all tests PASS; the book produces the same shape of output it did before — the migration is
a change of what it reads, not of what it decides; and `rows_written_to_the_LIVE_log_today` is
unchanged from before this step.

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI
git add tools/build_reprice_bulksheet.py tools/tests/test_reprice_precedence.py
git commit -m "refactor(books): the reprice book consumes the contract, not the ladder's commands

The command words stay on the row for the 27 existing readers; nothing new selects
on them, and the one book that turned a state into an action now reads a verdict."
```

---

### Task 8.4: Two worked-example acceptance tests, straight from the appendices

**Files:**
- Modify: `scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql`

- [ ] **Step 1: Add both checks**

```sql
,
-- K15 APPENDIX A. asin="B0CCCPFWZF", ME-SP/PT (Competitors, Mint, A1), LolliME. Its settled record
-- was conclusive and had been since 2026-08-04: a loss beyond the noise band, paying roughly three
-- times what its own record could support, with an executable affordable price above its floor.
-- The doctrine says the Catalog SHOULD answer NOT_WORTH, ceiling about $0.51/click, HIGH
-- confidence, about 1 click a week. The ceiling and the click rate are checked as ORDERS OF
-- MAGNITUDE, not to the cent — the record moves, and pinning a number here would break this test
-- every night for no reason and violate Standing Rule 0 into the bargain.
k14 AS (
  SELECT 'K15 Appendix A worked example: the answered keyword reads NOT_WORTH at HIGH confidence',
         (SELECT COUNTIF(NOT (verdict = 'NOT_WORTH'
                              AND confidence_band = 'HIGH'
                              AND ceiling_cpc BETWEEN 0.20 AND 1.50
                              AND expected_clicks BETWEEN 0.0 AND 20.0))
          FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
          WHERE snapshot_date = (SELECT MAX(snapshot_date)
                                 FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
            AND LOWER(TRIM(target_text)) = 'asin="b0cccpfwzf"')
),
-- K16 APPENDIX B. keyword 500617324681575, 'diary with lock for girls', ME-VIDEO/BROAD, LolliME.
-- Two strong holiday months last season and a summer with clicks and no orders at all. The doctrine
-- says: NOT_WORTH_NOW for an August window, WORTH for a November window asked in October — which is
-- only expressible because the Catalog answers for a REQUESTED window (Phase 5, doctrine 4).
-- This check reads whichever window is active: if the active request is inside the holiday peak the
-- verdict must be WORTH, and otherwise it must be NOT_WORTH_NOW. What it must NEVER be is
-- NOT_WORTH, which is what actually happened to it — paused, applied, and invisible to all three
-- layers three months before its season.
k15 AS (
  SELECT 'K16 Appendix B worked example: the seasonal keyword is never NOT_WORTH, and turns with the requested window',
         (SELECT COUNTIF(verdict = 'NOT_WORTH')
               + COUNTIF(season_window_from IS NOT NULL
                         AND season_window_from <= CURRENT_DATE('America/Los_Angeles')
                         AND season_window_to   >= CURRENT_DATE('America/Los_Angeles')
                         AND verdict != 'WORTH')
               + COUNTIF(season_window_from IS NOT NULL
                         AND season_window_from > CURRENT_DATE('America/Los_Angeles')
                         AND ly_clicks >= 10
                         AND verdict NOT IN ('NOT_WORTH_NOW', 'WORTH'))
          FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
          WHERE snapshot_date = (SELECT MAX(snapshot_date)
                                 FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
            AND keyword_id = '500617324681575')
)
```

- [ ] **Step 2: Run the suite**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql)"
```

Expected: seventeen rows, all `PASS`. **If K16 returns zero rows for the keyword id, that is itself the finding** — Appendix B records that the keyword was paused and has no row in `FACT_KEYWORD_STATE` at all. Phase 2's spend-derived arm should have re-admitted it; if it has not, the coverage fix has a hole and that is what to investigate before proceeding.

- [ ] **Step 3: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql
git commit -m "test(catalog): the doctrine's two worked examples become acceptance checks

Appendix A must read NOT_WORTH at HIGH confidence; Appendix B must never read
NOT_WORTH and must turn with the requested window."
```

---

### Task 8.5 (violation 10): RULE ON P-4 FIRST — this is a doctrine collision, not a bug

**No code in this task. It is a decision, and writing code before it is settled would be writing the decision by accident.**

§3.2's `LEAN_IN` and P-4 as coded cannot both stand. `ASSERT SP_BUILD_NEXT_WEEK_PLAN.sql:620-622` forbids **any** executable price on the good side, and the whole assert block sits **above** the `DELETE` at line 708 — so a funded turn does not produce a bad plan, it **aborts the build and silently leaves yesterday's partition live**.

- [ ] **Step 1: Put the exact collision in front of Ori, with both readings and the money**

```bash
cd /Users/ori/Develop/OI
sed -n '618,624p' scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH p AS (SELECT * FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
           WHERE as_of = (SELECT MAX(as_of) FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`)
             AND is_live_plan)
SELECT
  COUNTIF(side = 'GOOD' AND ladder_state IN ('REPRICE','LOSER','FLOOR_PROBATION','PARKED','DEAD'))
    AS good_side_rows_with_a_losing_record,
  ROUND(SUM(IF(side = 'GOOD' AND ladder_state IN ('REPRICE','LOSER','FLOOR_PROBATION','PARKED','DEAD'),
             w_sp / window_days, 0)), 2) AS usd_per_day_on_them,
  COUNTIF(side = 'GOOD' AND held_despite_evidence) AS held_despite_evidence,
  COUNTIF(side = 'GOOD' AND current_bid IS NOT NULL AND affordable_bid IS NOT NULL
          AND affordable_bid > current_bid + 0.005) AS constrained_winners,
  ROUND(SUM(IF(side = 'GOOD' AND affordable_bid > current_bid + 0.005,
             (affordable_bid - current_bid) * SAFE_DIVIDE(w_clk, window_days), 0)), 2)
    AS headroom_usd_per_day
FROM p"
```

- [ ] **Step 2: Record the ruling in the doctrine's changelog before writing a line of code**

The two readings of P-4 are:

- **"never cut"** — the good side is protected from downward moves and from nothing else. `LEAN_IN` is legal; a cut on the good side is not. Under this reading the assert is re-worded and the good side gains a raise-only price.
- **"never re-priced"** — the good side is untouched in either direction, and `LEAN_IN` cannot exist as an intent at all. Under this reading §3.2 is amended instead, and violation 10 is closed by ruling it out rather than by building it.

Add a row to the changelog table in `architecture/THREE_LAYERS.md` recording which clause survives, who ruled, and the measured evidence that moved it — per that file's own "How to add an entry": record the ruling and the evidence, never just the diff.

**Tasks 8.6 and 8.7 assume the first reading — "never cut" survives.** If Ori rules the other way, stop: close violation 10 by amending §3.2, delete Tasks 8.6 and 8.7, and note in the violation-to-task map that 10 was closed by ruling rather than by code.

- [ ] **Step 3: Commit the ruling**

```bash
cd /Users/ori/Develop/OI
git add architecture/THREE_LAYERS.md
git commit -m "docs(doctrine): rule on the P-4 / LEAN_IN collision

3.2's LEAN_IN and P-4 as coded cannot both stand — the assert forbids any
executable price on the good side and runs above the DELETE, so a funded turn
aborts the build. Records which clause survives and the evidence that moved it."
```

---

### Task 8.6 (violation 10): unmask the good side for raises only, and walk it

**Files:**
- Modify: `scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql:616-624` and `:663`
- Modify: `scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql:134-139`, `:344-366`, `:385-390`, `:620-622`
- Modify: `scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql` C08 and C14
- Modify: `scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql` C06 and C12

Four separate mechanisms block the good side today, and all four move together.

- [ ] **Step 1: Publish a raise-only price under a second column name**

In `V_PLAN_WINDOW_JUDGMENT.sql`, keep `planned_bid` NULL on the good side exactly as it is — that column is what every existing consumer treats as executable, and P-4's protection lives there. Add a **new** column beside it:

```sql
    -- ── LEAN_IN's PRICE, UNDER ITS OWN NAME (2026-08-25, violation 10) ────────────────────────
    -- Doctrine 3.2: "the Brain must always be asking what it could do better, and that includes the
    -- earning side. Leave it alone is a protection against churn, not a licence to stop thinking."
    -- Measured: 57 constrained winners spending $412.77/day, returning $565.25/day of gross profit,
    -- with $174.73/day of headroom to what their own record affords — and every one of them at
    -- move = NONE.
    -- A SECOND COLUMN, NOT A RELAXATION OF planned_bid. Every existing consumer reads planned_bid
    -- and would treat a good-side value there as a repair; this is the one-line shape
    -- SP_BUILD_NEXT_WEEK_PLAN's own header already proposed for the shadow plan.
    -- IT IS RAISE-ONLY BY CONSTRUCTION: NULL unless it is strictly above the current bid, so P-4's
    -- surviving clause ("never cut") cannot be broken through this column even by accident.
    -- IT IS WALKED, NOT TAKEN IN ONE STEP (doctrine 3.1): a lean-in is a raise into partly-unknown
    -- territory — the evidence supports the DIRECTION, not the magnitude — so it goes through
    -- FN_MOVE_CAP like every other raise.
    -- `side_b` IS CREATED IN THIS SAME SELECT LIST (line 580) and cannot be read from a sibling
    -- expression — which is exactly why the neighbouring seat_cost_per_day at line 616 spells the
    -- predicate out as j.verdict IN (...). Do the same here, or the deploy fails with
    -- "Unrecognized name: side_b".
    IF(j.verdict IN ('GOOD', 'HELD_UNSETTLED', 'GRACE')
       AND j.confidence_band IN ('HIGH', 'MEDIUM')
       AND j.affordable_bid IS NOT NULL
       AND j.current_bid IS NOT NULL
       AND j.affordable_bid > j.current_bid + 0.005,
       ROUND(LEAST(j.affordable_bid,
                   `onyga-482313.OI.FN_MOVE_CAP`(j.current_bid, 'UP', j.confidence_band)), 2),
       NULL)                                                            AS lean_in_bid,
```

Two carries, both required:

- **into `base`**: add `ks.confidence_band` beside `ks.state AS ladder_state, ks.current_bid,
  ks.affordable_bid, ks.bid_floor` at `:454`. `affordable_bid` is already there; `confidence_band`
  is the one Phase 7 added to `FACT_KEYWORD_STATE`. `judged` and `final` both select `*` from their
  predecessor, so `j.confidence_band` and `j.affordable_bid` then resolve inside `final`.
- **out of `final`**: add `f.lean_in_bid,` and `f.confidence_band,` to the view's outer `SELECT`
  (beside `f.current_bid, f.bid_floor,` at `:668`). A column computed in `final` and not republished
  there does not exist to any consumer, and `SP_BUILD_NEXT_WEEK_PLAN` reads the view, not the CTE.

- [ ] **Step 2: Let the builder issue the intent**

In the builder's `r2` CTE at 134–139, keep `plan_bid` and `plan_seat_cost` NULL on the good side and add a third:

```sql
    CASE WHEN r.side = 'GOOD' THEN r.lean_in_bid ELSE NULL END          AS plan_lean_in_bid,
```

and in the move CASE, replace the bare `WHEN r2.side = 'GOOD' THEN 'NONE'` first arm with:

```sql
      -- 2026-08-25 (violation 10): the good side is no longer uniformly 'NONE'. A winner priced
      -- below what its own record affords, at MEDIUM confidence or better, gets a walked raise.
      -- Doctrine 2.7 licenses a reversible move at MEDIUM; a lean-in is reversible by construction.
      WHEN r2.side = 'GOOD' AND r2.plan_lean_in_bid IS NOT NULL         THEN 'LEAN_IN'
      WHEN r2.side = 'GOOD'                                             THEN 'NONE'
```

In the `priced` CTE add the branch:

```sql
      WHEN 'LEAN_IN'       THEN ROUND(a.plan_lean_in_bid, 2)
```

and change `planned_spend_per_day`'s first branch at 385–390, which pins a good-side row to its own prior spend, so a lean-in says what it costs:

```sql
      -- a LEAN_IN raises the price, so it raises the spend, and the plan says so in a column rather
      -- than only in prose. Every other good-side row keeps its own prior spend as before.
      WHEN a.move = 'LEAN_IN'
        THEN COALESCE(SAFE_DIVIDE(a.w_sp, a.window_days), 0)
             * SAFE_DIVIDE(a.plan_lean_in_bid, NULLIF(a.current_bid, 0))
      WHEN a.side = 'GOOD' OR a.holdout OR NOT a.is_cand
        THEN COALESCE(SAFE_DIVIDE(a.w_sp, a.window_days), 0)
```

- [ ] **Step 3: Re-word the P-4 assertion to forbid cuts, not prices**

Replace the assertion at 620–622 with:

```sql
  -- P-4, RE-WORDED ON ORI'S RULING (2026-08-25 — see architecture/THREE_LAYERS.md changelog).
  -- The surviving clause is NEVER CUT. The good side may now carry a raise-only price under
  -- lean_in_bid, walked through FN_MOVE_CAP; what it may never carry is a price below its current
  -- bid, a seat cost, or a repair move. The old assertion forbade ALL prices, which is why 3.2's
  -- LEAN_IN and this assert could not both stand — and, because this block runs above the DELETE, a
  -- funded turn aborted the build and silently left yesterday's partition live.
  ASSERT (SELECT COUNTIF(side = 'GOOD'
                         AND (move NOT IN ('NONE', 'NONE_HOLDOUT', 'LEAN_IN')
                              OR planned_bid IS NOT NULL
                              OR seat_cost_per_day IS NOT NULL
                              -- `final` is CREATE OR REPLACE TEMP TABLE final AS SELECT * FROM
                              -- FACT_PLAN_NEXT_WEEK WHERE FALSE (:486-487), so its column is
                              -- planned_bid. planned_bid_final is an alias of the `priced` CTE and
                              -- does not exist here.
                              OR (move = 'LEAN_IN'
                                  AND COALESCE(planned_bid, 0) <= COALESCE(current_bid, 0))))
          FROM final) = 0
    AS 'the good side is never cut and takes no seat; it may carry a raise-only lean-in price (P-4, restated)';
  -- 3.1: a raise is walked. A lean-in that exceeds one upload's cap is a magnitude nobody has
  -- evidence for.
  ASSERT (SELECT COUNTIF(move = 'LEAN_IN'
                         AND planned_bid
                             > `onyga-482313.OI.FN_MOVE_CAP`(current_bid, 'UP', confidence_band) + 0.005)
          FROM final) = 0
    AS 'a lean-in is walked, never taken in one step (3.1)';
```

- [ ] **Step 4: Move the four acceptance checks in the same change**

`V_PLAN_WINDOW_JUDGMENT_acceptance` C14 asserts `side_b = 'GOOD' => planned_bid IS NULL AND seat_cost_per_day IS NULL` — that stays true and needs no change. C08 requires every not-good row to carry a planned price, a seat cost and a rank — also unchanged. In `FACT_PLAN_NEXT_WEEK_acceptance`, C06's move enumeration and C12's good-side clause must both admit `LEAN_IN` — **and so must C14**, which enumerates the legal moves a second time split by seat (Task 6.2 Step 6 explains why). A `LEAN_IN` is a seated move, so it belongs in C14's `seat_no IS NOT NULL` list beside `REPRICE` and `TEST_RETEST`; check it before running the suite rather than after it goes red:

```sql
       + COUNTIF(side = 'GOOD' AND move NOT IN ('NONE', 'NONE_HOLDOUT', 'LEAN_IN'))
```

- [ ] **Step 5: Add `lean_in_bid` to the plan table, deploy the chain, verify**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
ALTER TABLE \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
  ADD COLUMN IF NOT EXISTS lean_in_bid FLOAT64"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT move, COUNT(*) n,
       ROUND(SUM(planned_spend_per_day - COALESCE(w_sp / window_days, 0)), 2) usd_per_day_added,
       -- the PUBLISHED column is planned_bid. planned_bid_final is an internal alias inside
       -- SP_BUILD_NEXT_WEEK_PLAN's `priced` CTE (:384) and is written out as planned_bid (:517,
       -- :541, :569); it does not exist on the table.
       COUNTIF(move = 'LEAN_IN' AND COALESCE(planned_bid, 0) <= current_bid) any_cut_disguised_as_a_raise
FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
WHERE as_of = (SELECT MAX(as_of) FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`) AND is_live_plan
GROUP BY 1 ORDER BY n DESC"
for s in FACT_PLAN_NEXT_WEEK_acceptance V_PLAN_WINDOW_JUDGMENT_acceptance; do
  bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
    "$(grep -v '^--' scripts/bigquery/tests/$s.sql)"
done
```

Expected: a `LEAN_IN` bucket with a positive `usd_per_day_added`, `any_cut_disguised_as_a_raise = 0`, and every acceptance row `PASS`.

- [ ] **Step 6: Surface the two populations §3.2 names**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH p AS (SELECT * FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
           WHERE as_of = (SELECT MAX(as_of) FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`)
             AND is_live_plan)
SELECT 'good side with a losing ladder record' AS population, COUNT(*) n,
       ROUND(SUM(w_sp / window_days), 2) usd_per_day
FROM p WHERE side = 'GOOD' AND ladder_state IN ('REPRICE','LOSER','FLOOR_PROBATION','PARKED','DEAD')
UNION ALL
SELECT 'good-side protection outliving a 28-day record below the bar', COUNT(*),
       ROUND(SUM(w_sp / window_days), 2)
FROM p WHERE side = 'GOOD' AND held_despite_evidence"
```

Record both. Measured 2026-08-24: 5 rows carrying $137.88/day, all at `move = NONE`; and 21 subjects at $92.64/day whose good-side protection outlived a 28-day record at 0.518 GP-ROAS. **These are not fixed by `LEAN_IN`** — they are the opposite population — and they are surfaced here so the ruling in Task 8.5 is made with them visible rather than after the fact.

- [ ] **Step 7: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql \
        scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql \
        scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql \
        scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql \
        scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql
git commit -m "feat(brain): LEAN_IN — the Brain funds a turn instead of only protecting it

Closes violation 10 on Ori's P-4 ruling. Raise-only under its own column name,
gated at MEDIUM confidence or better, and walked through FN_MOVE_CAP because the
evidence supports the direction and not the magnitude (3.1)."
```

---

### Task 8.7: Land §9's row shape

**Files:**
- Modify: `scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql` (the `sentence` expression)
- Modify: `architecture/THREE_LAYERS.md` (§9's row shape, recorded)

§9 is binding on future implementation: every action shown to a person is explained **Catalog → Brain → Pacing, in that order**, every number names the layer that produced it, and a disagreement between layers is shown rather than hidden. **`dashboard-react/src/pages/PlanPage.tsx` belongs to another session and must not be staged, reverted or committed.** This task lands the row shape and the sentence only.

- [ ] **Step 1: Rewrite the plan's sentence in three named parts**

**Where this expression lives, and therefore what its alias is.** The `sentence` column is built at
`SP_BUILD_NEXT_WEEK_PLAN.sql:609` inside the `INSERT INTO final (…) SELECT … FROM priced p` block
(`:489-612`), so **every reference below is `p.`**, and the price column at that point is
`p.planned_bid_final` — the `priced` CTE's alias (`:384`), which the INSERT writes out into the
table's `planned_bid` column (`:517`). Do not write `f.`; there is no `f` in that block. Do not write
`p.planned_bid`; that name only exists after the row lands on the table.

Replace the `sentence` expression in the `final` CTE with:

```sql
    -- ── DOCTRINE 9: EVERY ACTION IS EXPLAINED TOP DOWN, IN THE ORDER IT WAS DECIDED ────────────
    -- Catalog (what this is worth), then Brain (what we decided), then Pacing (what happens in the
    -- account). Every number names the layer that produced it, so a reader who disagrees knows
    -- instantly whether the argument is with a valuation, an allocation or an execution — the
    -- ambiguity that let a mechanics rule quietly make an economics decision (Appendix A).
    -- A DISAGREEMENT BETWEEN LAYERS IS THE MOST INFORMATIVE THING ON THE ROW and is surfaced, never
    -- hidden behind the surviving instruction.
    CONCAT(
      FORMAT('CATALOG · %s at %s confidence. %s',
             COALESCE(p.verdict_catalog, 'UNKNOWN'),
             COALESCE(p.confidence_band, 'NO_EVIDENCE'),
             COALESCE(p.catalog_reason, 'no keyword-state row for this subject.')),
      IF(p.season_window_label IS NOT NULL,
         FORMAT(' Its season is %s (%t to %t).', p.season_window_label,
                p.season_window_from, p.season_window_to),
         ''),
      FORMAT('  BRAIN · %s. %s',
             CASE p.move
               WHEN 'REPRICE'       THEN FORMAT('REPAIR to a ceiling of $%.2f', p.planned_bid_final)
               WHEN 'HOLD_AT_PRICE' THEN 'REPAIR, already at its price'
               WHEN 'LEAN_IN'       THEN FORMAT('LEAN IN toward $%.2f', p.planned_bid_final)
               WHEN 'PARK'          THEN FORMAT('PARK at $%.2f', p.planned_bid_final)
               WHEN 'PARK_SEASONAL' THEN FORMAT('PARK until %t', p.revisit_date)
               WHEN 'HOLD_AT_PARK'  THEN 'HOLD at its park price'
               WHEN 'TEST_RETEST'   THEN FORMAT('TEST — buy %d clicks by %t',
                                                p.retest_clicks_bought, p.verdict_date)
               WHEN 'PAUSE'         THEN 'STOP'
               ELSE                      'EARN — leave it alone'
             END,
             IF(p.seat_no IS NOT NULL,
                FORMAT('It holds seat %d in %s at $%.2f a day, against a family allowance of $%.2p.',
                       p.seat_no, p.family, p.seat_cost_per_day, p.allowance_ramped_per_day),
                FORMAT('It takes no seat: %s.',
                       IF(p.is_candidate, 'the family allowance is spent on higher-ranked questions',
                          'it is earning on its settled record')))),
      FORMAT('  PACING · %s',
             CASE
               WHEN p.planned_bid_final IS NULL THEN 'nothing is uploaded for this keyword.'
               WHEN p.planned_bid_final < p.current_bid
                 THEN FORMAT('cut $%.2f to $%.2f, immediately — a cut to a known ceiling cannot overshoot. Its floor is $%.2p.',
                             p.current_bid, p.planned_bid_final, p.bid_floor)
               WHEN p.planned_bid_final > p.current_bid
                 THEN FORMAT('raise $%.2f to $%.2f, walked — one upload may move it no further than $%.2p. Its floor is $%.2p.',
                             p.current_bid, p.planned_bid_final,
                             `onyga-482313.OI.FN_MOVE_CAP`(p.current_bid, 'UP', p.confidence_band),
                             p.bid_floor)
               ELSE FORMAT('hold at $%.2f; nothing reaches Amazon.', p.current_bid)
             END),
      -- the disagreement, shown rather than hidden (doctrine 9)
      IF(p.verdict_catalog = 'NOT_WORTH' AND p.side = 'GOOD',
         '  DISAGREEMENT · the settled record says this is not worth having and the window says it is earning. The window is protected (P-4) and the record is the longer view; the next settled window decides it.',
         ''),
      IF(p.move = 'PAUSE',
         FORMAT('  IRREVERSIBLE · this is a one-way door. It is taken on verdict %s at %s confidence, with no season contradicting it.',
                p.verdict_catalog, p.confidence_band),
         '')
    )                                                                   AS sentence
```

Carry `verdict AS verdict_catalog`, `confidence_band`, `catalog_reason`, `season_window_label`, `season_window_from` and `season_window_to` from the Catalog row through `V_PLAN_WINDOW_JUDGMENT`'s `base` CTE and its outer `SELECT` into the builder's `priced` CTE, so every `p.` reference above resolves. Add the same six columns to `scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql` as `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` lines and to the INSERT's explicit column list at `:489-503` — that list is positional and a column added to the SELECT without being added to the list shifts every column after it.

- [ ] **Step 2: Record the row shape in the doctrine**

Add a short subsection under §9 of `architecture/THREE_LAYERS.md` naming the columns that carry each of the three parts — so the UI session, whenever it picks this up, implements against a written contract rather than reverse-engineering a string:

| part | columns on `FACT_PLAN_NEXT_WEEK` |
|---|---|
| **1. Catalog** | `verdict_catalog`, `confidence`, `confidence_band`, `ceiling_cpc`, `season_window_label`, `season_window_from`, `season_window_to`, `catalog_reason` |
| **2. Brain** | `move`, `planned_bid`, `lean_in_bid`, `seat_no`, `seat_cost_per_day`, `verdict_date`, `revisit_date`, `revisit_reason`, `allowance_ramped_per_day`, `rank_no` |
| **3. Pacing** | `planned_bid` (the published name of the builder's internal `planned_bid_final`), `current_bid`, `bid_floor`, `bid_park`, `bid_park_source`, and the cap from `FN_MOVE_CAP` |
| **disagreement** | `held_despite_evidence`, `good_side_no_sale`, and `verdict_catalog` against `side` |

- [ ] **Step 3: Deploy, read a sentence, and commit**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=prettyjson \
  "SELECT move, sentence FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
   WHERE as_of = (SELECT MAX(as_of) FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`) AND is_live_plan
   ORDER BY seat_no NULLS LAST LIMIT 3"
git add scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql architecture/THREE_LAYERS.md
git commit -m "feat(brain): every plan row explains itself Catalog then Brain then Pacing

Doctrine 9's row shape, landed as data and prose. The dashboard that consumes it
belongs to another session and is not touched here."
```

Expected: each sentence carries all three named parts in order, and a disagreement or an irreversible-action clause where one applies.

---
## Phase 9 — Negatives get an owner, a book and an expiry

**Closes:** violations 24 and 25.

**Why here.** Independent of most of the plan, placed here for one dependency and one money reason. **The dependency:** §2.9's expiry has two grounds — the data now says so, and the peak makes a high-volume term worth re-learning — and the first needs Phase 5's seasonal answer to mean anything. **The money is immediate and separate:** 91 search terms marked GO for negation are bleeding $73.40/day at 113.4 clicks/day for 0.29 orders/day, and the last `NEGATE_TERM` reached Amazon ten days before the baseline.

Structurally the account treats a negative as a settled fact: 9,684 ENABLED rows against exactly **one** REMOVED in the table's entire history; `V_WEEKLY_RUN_NEGATIVE.sql:36-50`'s `NOT EXISTS` exists specifically to stop the coach "suggesting negatives forever"; `DE_NEGATIVE_KEYWORDS` has no expiry, no `next_review_date` and no season column; and every book emits `Operation: Create` and nothing else.

**24 and 25 are one fix wearing two numbers** — the expiry answer has no book to travel in, and the book has nothing to carry without the answer.

**If a phase must slip, slip this one.** Nothing downstream depends on it — which is also why it is the cheapest standing bleed in the account and the only violation whose fix is a capability the platform already accepts.

**Size:** M — 1–1.5 weeks.

---

### Task 9.1: Three red measurements

- [ ] **Step 1: The bleed, and when a negate last reached Amazon**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT COUNT(*) go_negate_terms,
       ROUND(SUM(spend_28d) / 28, 2) usd_per_day,
       ROUND(SUM(clicks_28d) / 28, 1) clicks_per_day,
       ROUND(SUM(orders_28d) / 28, 2) orders_per_day
FROM \`onyga-482313.OI.T_ENGINE_PREFLIGHT\` p
JOIN (SELECT CAST(campaign_id AS STRING) cid, LOWER(TRIM(search_term)) term,
             SUM(Ads_cost) spend_28d, SUM(Ads_clicks) clicks_28d, SUM(Ads_orders) orders_28d
      FROM \`onyga-482313.OI.FACT_AMAZON_ADS\`
      WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 28 DAY)
        AND search_term IS NOT NULL GROUP BY 1,2) f
  ON f.cid = CAST(p.campaign_id AS STRING) AND f.term = LOWER(TRIM(p.target_text))
WHERE p.lever = 'NEGATE' AND p.verdict = 'GO'"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT MAX(DATE(applied_at)) last_negate_applied, COUNT(*) negate_rows_ever
   FROM \`onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED\` WHERE action LIKE 'NEGATE%'"
```

Expected: a substantial daily bleed and a `last_negate_applied` well in the past. Measured 2026-08-24: 91 terms, $73.40/day, 113.4 clicks/day, 0.29 orders/day; last negate applied ten days earlier.

- [ ] **Step 2: A negative is treated as permanent**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT state, source, COUNT(*) n,
          COUNTIF(REGEXP_CONTAINS(negative_id, r'^neg_[0-9a-f]{12}$')) synthetic_ids
   FROM \`onyga-482313.OI.DE_NEGATIVE_KEYWORDS\` GROUP BY 1,2 ORDER BY n DESC"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT column_name FROM \`onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS\`
   WHERE table_name = 'DE_NEGATIVE_KEYWORDS'
     AND (LOWER(column_name) LIKE '%expir%' OR LOWER(column_name) LIKE '%review%'
          OR LOWER(column_name) LIKE '%season%')"
```

Expected: overwhelmingly `ENABLED`, essentially no `REMOVED`, and **zero** rows from the second query. Measured 2026-08-24: 9,684 ENABLED and exactly one REMOVED ever; 9,566 rows carry a real numeric Amazon Keyword ID from the 2026-06-15 seed download, and the 119 our own uploads created carry the synthetic `neg_<md5-12>` id minted by `SP_SYNC_NEGATIVES.sql:20-56`, which Amazon cannot accept.

- [ ] **Step 3: No generator can remove one**

```bash
cd /Users/ori/Develop/OI
grep -rn "Negative Keyword" tools/*.py | head
grep -rn "archived" tools/*.py dashboard-react/src/pages/DoPage.tsx | head
```

Expected: every `tools/` hit emits `Operation: Create`; the only working reference for an archive row is `dashboard-react/src/pages/DoPage.tsx:1390-1405`, which is a UI queue rather than a book.

- [ ] **Step 4: Record the measurement and commit it**

Every red measurement in this plan is a number the green run is compared against, so it is written
down rather than remembered. Append what you measured — the query, the date, and the count — to the
running record, creating the file on the first task that reaches this step:

```bash
cd /Users/ori/Develop/OI
mkdir -p docs/superpowers/specs
cat >> docs/superpowers/specs/2026-08-25-gap-closure-measurements.md <<'EOF'

## Task 9.1 — measured YYYY-MM-DD

Replace the date above with the date you ran it, and paste below: the query you ran (unchanged from
the task), and its output. Do not summarise the output — the point of this file is that a re-run is
a re-run and not a fresh argument, which is the same reason
docs/superpowers/specs/2026-08-24-three-layers-baseline.md exists.
EOF
git add docs/superpowers/specs/2026-08-25-gap-closure-measurements.md
git commit -m "measure(task 9.1): record the red measurement before the fix

The number the green run is compared against, written down rather than remembered."
```

---

### Task 9.2 (violation 25): the archive arm

**Files:**
- Create: `tools/build_negative_archive_bulksheet.py`
- Modify: `tools/tests/test_change_log_discipline.py` (add it to `BOOKS`)

**No new headers are needed.** `SP_HEADERS` already carries `'Keyword ID'` and `SB_HEADERS` `'Keyword Id'` (`tools/build_stop_nonconverting_bulksheet.py:75-107`), both imported by `tools/build_seat_moves_bulksheet.py:112-115`. The row shape to copy is the one `DoPage.tsx:1390-1405` already builds.

- [ ] **Step 1: Write the failing test**

Add the import and extend `BOOKS` in `tools/tests/test_change_log_discipline.py`:

```python
import build_negative_archive_bulksheet as negarch  # noqa: E402

BOOKS = [leak, reprice, unpause, reopen, close, negarch]
```

Run it and watch it fail with `ModuleNotFoundError`.

- [ ] **Step 2: Write the generator**

```python
#!/usr/bin/env python3
"""NEGATIVE ARCHIVE BOOK — the arm that removes a negative, which no book in this account had.

architecture/THREE_LAYERS.md 2.9: "a negative is a standing answer with an expiry, not a permanent
state", and the 2026-08-24 20:50 correction is precise about where the gap actually is. REMOVAL IS
EXECUTABLE — Amazon accepts an Entity: Negative Keyword row with Operation: Update and
State: archived, addressed by the negative's id, and a removal has been executed before. What does
not exist is the GENERATOR ARM: every book this account builds emits Operation: Create for negatives
and nothing else, so the Catalog's "remove the negate" answer has no book to travel in (violation 25).

WHAT THIS BOOK REFUSES TO DO, LOUDLY. Of the registry's rows, the large majority carry a real numeric
Amazon Keyword ID from the 2026-06-15 bulksheet download; the ones our own uploads created carry the
synthetic `neg_<md5-12>` id minted by SP_SYNC_NEGATIVES, WHICH AMAZON CANNOT ACCEPT. A row with a
synthetic id is refused by name and reported, never silently substituted with a text match — a text
match on the wrong ad group archives the wrong negative and there is no undo for that.

THE COVERAGE LIMIT, which is real and is not fixed here: the registry rather than Amazon is the
record of what is blocked, because the negative feed has been frozen since early 2026. A negative
created outside our books is invisible to the Catalog and therefore to this book.

NEVER UPLOADED BY THIS SCRIPT. Books land PENDING_UPLOAD and are for Ori.
"""
import argparse
import json
import os
import re
import subprocess
import sys
from datetime import date, datetime, timezone

import openpyxl

PROJECT = 'onyga-482313'

# THE CHANGE LOG, in the house shape every other book already uses. It is NOT an environment
# variable: tools/tests/test_change_log_discipline.py::test_a_change_log_override_must_be_a_tmp_copy
# calls set_change_log_table() and reads LIVE_CHANGE_LOG by name on every book in BOOKS, and an
# os.environ override carries no TMP_/TEMP_ guard at all — so the one thing that test exists to
# constrain would be unconstrained. Copy this block verbatim from
# tools/build_reprice_bulksheet.py:118-133; do not paraphrase it.
LIVE_CHANGE_LOG = "FACT_PPC_CHANGE_LOG"
CHANGE_LOG = f"{PROJECT}.OI.{LIVE_CHANGE_LOG}"


def set_change_log_table(table):
    global CHANGE_LOG
    assert table == LIVE_CHANGE_LOG or table.startswith(('TMP_', 'TEMP_')), \
        f"{table}: a change-log override must be a TMP_/TEMP_ copy — never another live table"
    CHANGE_LOG = f"{PROJECT}.OI.{table}"
    return CHANGE_LOG

# Amazon's negative-keyword row headers. 'Keyword ID' is the address; without it Amazon cannot tell
# which negative to archive, which is why a synthetic id is refused rather than guessed around.
NEGATIVE_HEADERS = [
    'Product', 'Entity', 'Operation', 'Campaign ID', 'Ad Group ID', 'Keyword ID',
    'Keyword Text', 'Match Type', 'State',
]

# the shape SP_SYNC_NEGATIVES mints for a negative our own uploads created: neg_ plus 12 hex chars
SYNTHETIC_ID = re.compile(r'^neg_[0-9a-f]{12}$')


def q(v):
    if v is None:
        return 'NULL'
    return "'" + str(v).replace('\\', '\\\\').replace("'", "\\'") + "'"


def bq(sql):
    out = subprocess.run(
        ['bq', 'query', '--use_legacy_sql=false', '--nouse_cache', '--format=json',
         f'--project_id={PROJECT}', sql],
        capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f'query failed:\n{out.stderr}')
    return json.loads(out.stdout or '[]')


def run_update(sql, what):
    out = subprocess.run(
        ['bq', 'query', '--use_legacy_sql=false', '--nouse_cache', f'--project_id={PROJECT}', sql],
        capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f'{what} failed:\n{out.stderr}')


def candidates_sql():
    """Negatives the Catalog says should come off: the review date has arrived and improve() ranks a
    removal above leaving it in place."""
    return f"""
SELECT i.campaign_id, i.campaign_name, i.ad_group_id, i.negative_id, i.keyword_text,
       i.match_type, i.level, i.review_reason, i.season_context,
       i.market_volume_weekly, i.our_share_pct, i.suggestion_value_per_day
FROM `{PROJECT}.OI.V_CATALOG_IMPROVE` i
WHERE i.suggestion = 'REMOVE_NEGATE'
  AND i.next_review_date <= CURRENT_DATE('America/Los_Angeles')
ORDER BY i.suggestion_value_per_day DESC
"""


def split_addressable(rows):
    """A synthetic id cannot address Amazon. Refuse it by name; never substitute a text match."""
    ok, refused = [], []
    for r in rows:
        nid = str(r.get('negative_id') or '')
        if not nid or SYNTHETIC_ID.match(nid):
            r['refusal'] = (f'negative_id {nid or "(none)"} was minted by SP_SYNC_NEGATIVES and is '
                            f'not an Amazon Keyword ID. Amazon cannot address this negative by id, '
                            f'and a text match could archive the wrong one in the wrong ad group. '
                            f'Remove it by hand in the console, or re-seed the registry from a '
                            f'bulksheet download.')
            refused.append(r)
        else:
            ok.append(r)
    return ok, refused


def supersede_sql(batch_id, note):
    return (f"UPDATE `{CHANGE_LOG}` SET upload_status = 'SUPERSEDED_NEVER_UPLOADED', "
            f"upload_note = {q(note)} "
            f"WHERE batch_id = {q(batch_id)} AND upload_status = 'PENDING_UPLOAD'")


def mark_uploaded_sql(batch_id):
    return (f"UPDATE `{CHANGE_LOG}` SET upload_status = NULL "
            f"WHERE batch_id = {q(batch_id)} AND upload_status = 'PENDING_UPLOAD'")


def prior_unmarked_batches_sql():
    return (f"SELECT batch_id, COUNT(*) n, MIN(applied_at) built FROM `{CHANGE_LOG}` "
            f"WHERE upload_status = 'PENDING_UPLOAD' AND action = 'REMOVE_NEGATIVE' "
            f"GROUP BY batch_id ORDER BY built")


def log_batch(rows, batch_id, readme_path):
    exists = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` WHERE batch_id = {q(batch_id)}")
    assert int(exists[0]['n']) == 0, f'batch id {batch_id} already exists in the change log'
    note = (f'negative archive book {batch_id}, built '
            f'{datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}; '
            f'README {os.path.basename(readme_path)}; manual upload pending — if this book is not '
            f'uploaded set upload_status SUPERSEDED_NEVER_UPLOADED')
    structs = []
    for r in rows:
        cid = str(r['campaign_id'])
        structs.append(
            'STRUCT('
            f"{q('negarch-' + batch_id.split('_')[-1] + '-' + str(r['negative_id']))} AS change_id, "
            f'{q(batch_id)} AS batch_id, CURRENT_TIMESTAMP() AS applied_at, '
            f"{q('REMOVE_NEGATIVE')} AS action, "
            f'{q(r["keyword_text"])} AS targeting, {q(r["keyword_text"])} AS search_term, '
            f'{q(r["match_type"])} AS match_type, '
            f'{q(cid)} AS campaign_id, {q(r["campaign_name"])} AS campaign_name, '
            f'{q(r.get("ad_group_id"))} AS ad_group_id, '
            f"{q('MANUAL')} AS source, {q('MANUAL_BULKSHEET')} AS coach_mode, "
            f'{q(note)} AS upload_note, '
            f"{q('PENDING_UPLOAD')} AS upload_status)")
    cols = ('change_id, batch_id, applied_at, action, targeting, search_term, match_type, '
            'campaign_id, campaign_name, ad_group_id, source, coach_mode, upload_note, '
            'upload_status')
    run_update(f'INSERT INTO `{CHANGE_LOG}` ({cols}) '
               f"SELECT {cols} FROM UNNEST([{', '.join(structs)}])", 'change-log insert')
    back = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` WHERE batch_id = {q(batch_id)}")
    n = int(back[0]['n'])
    assert n == len(rows), f'logged {n} rows but the sheet holds {len(rows)}'
    return n


def write_sheet(rows, out_path):
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = 'Sponsored Products Campaigns'
    ws.append(NEGATIVE_HEADERS)
    for r in rows:
        ws.append([
            'Sponsored Products',
            'Negative Keyword',
            # THE ARM THAT DID NOT EXIST: Update + archived, addressed by the negative's id.
            'Update',
            str(r['campaign_id']),
            r.get('ad_group_id') or '',
            str(r['negative_id']),
            r['keyword_text'],
            r['match_type'],
            'archived',
        ])
    os.makedirs(os.path.dirname(out_path) or '.', exist_ok=True)
    wb.save(out_path)
    return out_path


def write_readme(rows, refused, batch_id, out_path, readme_path):
    lines = [
        'NEGATIVE ARCHIVE BOOK',
        f'batch {batch_id}   built {datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}',
        f'sheet {os.path.basename(out_path)}   {len(rows)} negative(s) to archive',
        '',
        'A NEGATIVE IS A STANDING ANSWER WITH AN EXPIRY, NOT A SETTLED FACT (doctrine 2.9).',
        'Every row below is a block the Catalog has re-asked and now answers differently.',
        '',
    ]
    for r in rows:
        lines += [
            f'* "{r["keyword_text"]}"  ({r["match_type"]}, {r.get("level") or "CAMPAIGN"}) '
            f'in {r["campaign_name"]}',
            f'    CATALOG   {r["review_reason"]}',
            f'    BRAIN     removing this block is worth about '
            f'${float(r.get("suggestion_value_per_day") or 0):.2f}/day.',
            '    PACING    this sheet archives the negative by its Amazon Keyword ID. Nothing '
            'else about the campaign changes.',
            '',
        ]
    if refused:
        lines += [
            'REFUSED — NOT ON THE SHEET, AND NOT SILENTLY DROPPED:',
            '',
        ]
        for r in refused:
            lines += [f'* "{r["keyword_text"]}" in {r["campaign_name"]}', f'    {r["refusal"]}', '']
    lines += [
        'A COVERAGE LIMIT WORTH KNOWING: the account registry, not Amazon, is the record of what is',
        'blocked — the negative feed has been frozen since early 2026 — so a negative created',
        'outside our books is invisible here. That limits what can be RECONSIDERED; it does not',
        'limit what can be REMOVED.',
        '',
        f'AFTER YOU UPLOAD:  python3 tools/build_negative_archive_bulksheet.py --mark-uploaded {batch_id}',
        f'IF YOU DO NOT:     python3 tools/build_negative_archive_bulksheet.py --supersede {batch_id}',
        f'TO PUT THEM BACK:  python3 tools/build_restore_negative_archive_bulksheet.py {batch_id}',
        '',
        'This script never uploads anything to Amazon.',
    ]
    with open(readme_path, 'w') as fh:
        fh.write('\n'.join(lines) + '\n')
    return readme_path


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('-o', '--out', default=f'.tmp/negative_archive_{date.today():%Y%m%d}.xlsx')
    ap.add_argument('--mark-uploaded', metavar='BATCH')
    ap.add_argument('--supersede', metavar='BATCH')
    args = ap.parse_args()

    if args.mark_uploaded:
        pending = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` "
                     f"WHERE batch_id = {q(args.mark_uploaded)} "
                     f"AND upload_status = 'PENDING_UPLOAD'")
        if int(pending[0]['n']) == 0:
            sys.exit(f'--mark-uploaded {args.mark_uploaded}: no PENDING_UPLOAD rows under that id. '
                     f'Nothing was changed.')
        run_update(mark_uploaded_sql(args.mark_uploaded), 'mark-uploaded')
        print(f'  marked batch {args.mark_uploaded} uploaded')
        return

    if args.supersede:
        pending = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` "
                     f"WHERE batch_id = {q(args.supersede)} "
                     f"AND upload_status = 'PENDING_UPLOAD'")
        if int(pending[0]['n']) == 0:
            sys.exit(f'--supersede {args.supersede}: no PENDING_UPLOAD rows under that id. '
                     f'Nothing was changed.')
        note = (f'never uploaded; superseded '
                f'({datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}) — labelled by the generator')
        run_update(supersede_sql(args.supersede, note), 'supersede')
        print(f'  labelled batch {args.supersede} SUPERSEDED_NEVER_UPLOADED')
        return

    for b in bq(prior_unmarked_batches_sql()):
        print(f'  earlier archive book still pending: {b["batch_id"]} '
              f'({b["n"]} row(s), built {b["built"]})')

    rows, refused = split_addressable(bq(candidates_sql()))
    for r in refused:
        print(f'  REFUSED "{r["keyword_text"]}" — {r["refusal"]}')
    if not rows:
        print('  no negative is due for removal today — nothing written')
        return

    batch_id = f'negarch_{date.today():%Y%m%d}_{datetime.now(timezone.utc):%H%M%S}'
    out = write_sheet(rows, args.out)
    readme = write_readme(rows, refused, batch_id, out, out.replace('.xlsx', '_README.txt'))
    n = log_batch(rows, batch_id, readme)
    print(f'  {n} negative(s) written to {out}')
    print(f'  README {readme}')
    print(f'  batch {batch_id} logged PENDING_UPLOAD — this script uploads nothing')


if __name__ == '__main__':
    main()
```

- [ ] **Step 3: Run the discipline tests**

```bash
cd /Users/ori/Develop/OI
/usr/local/bin/python3 -m pytest tools/tests/test_change_log_discipline.py -q
```

Expected: all PASS, now covering six books — `close` joined in Task 7.7. (The generator's `candidates_sql()` reads `V_CATALOG_IMPROVE`, built in Task 9.4 — the discipline tests read the source, not the warehouse, so they pass before that view exists.)

- [ ] **Step 4: Commit**

```bash
cd /Users/ori/Develop/OI
git add tools/build_negative_archive_bulksheet.py tools/tests/test_change_log_discipline.py
git commit -m "feat(books): the negative archive arm — the book that did not exist

Closes half of violation 25. Operation Update / State archived, addressed by the
Amazon Keyword ID, and a loud refusal for the synthetic ids our own uploads mint."
```

---

### Task 9.3 (violation 25): fix the removal fold-back and the stale READMEs

**Files:**
- Modify: `scripts/bigquery/procedures/SP_SYNC_NEGATIVES.sql:88-96`
- Modify: `tools/build_seat_moves_bulksheet.py:766-777`
- Modify: `tools/build_restore_seat_moves_bulksheet.py:9-17`
- Create: `tools/build_restore_negative_archive_bulksheet.py`

- [ ] **Step 1: Tighten the removal key**

`SP_SYNC_NEGATIVES.sql`'s section C sets `state = 'REMOVED'` matching on `campaign_id` plus text **only** — not `ad_group_id`, not `match_type` — and never writes `change_id`. Replace the `UPDATE` with:

```sql
  -- ── C. Removals we uploaded → flip ENABLED keyword negatives to REMOVED ──
  -- 2026-08-25 (violation 25): the key was campaign_id plus text ONLY. A campaign carrying the same
  -- text as both an exact and a phrase negative, or at both campaign and ad-group level, had ALL of
  -- them flipped by one removal — and the change_id that did it was never recorded, so a removal
  -- could not be traced back to the book that made it. The key now matches the MERGE key in section
  -- A exactly: campaign, ad group, text and match type.
  UPDATE `onyga-482313.OI.DE_NEGATIVE_KEYWORDS` T
  SET state = 'REMOVED', removed_at = now_ts, updated_at = now_ts,
      change_id = (
        SELECT MAX(c.change_id) FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED` c
        WHERE c.action IN ('REMOVE_NEGATIVE', 'REMOVE_CONFLICTING_NEGATIVE')
          AND c.campaign_id = T.campaign_id
          AND COALESCE(NULLIF(TRIM(c.ad_group_id), ''), '') = COALESCE(T.ad_group_id, '')
          AND LOWER(COALESCE(NULLIF(TRIM(c.search_term), ''), c.targeting)) = LOWER(T.keyword_text)
          AND IF(c.action LIKE '%PHRASE%', 'NEGATIVE_PHRASE', 'NEGATIVE_EXACT') = T.match_type)
  WHERE T.state = 'ENABLED' AND EXISTS (
    SELECT 1 FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED` c
    WHERE c.action IN ('REMOVE_NEGATIVE', 'REMOVE_CONFLICTING_NEGATIVE')
      AND c.campaign_id = T.campaign_id
      AND COALESCE(NULLIF(TRIM(c.ad_group_id), ''), '') = COALESCE(T.ad_group_id, '')
      AND LOWER(COALESCE(NULLIF(TRIM(c.search_term), ''), c.targeting)) = LOWER(T.keyword_text)
      AND IF(c.action LIKE '%PHRASE%', 'NEGATIVE_PHRASE', 'NEGATIVE_EXACT') = T.match_type
  );
```

- [ ] **Step 2: Correct the two stale READMEs**

`tools/build_seat_moves_bulksheet.py:766-777` asserts "A negative cannot be undone by a sheet" and "Treat every negative on this sheet as permanent". Per §2.9's 2026-08-24 20:50 correction that is **wrong on capability and right only on coverage**. Replace both sentences with:

```python
        'A NEGATIVE CAN BE UNDONE BY A SHEET, and there is now a book that does it: Amazon accepts',
        'an Entity: Negative Keyword row with Operation: Update and State: archived, addressed by',
        'the negative id — see tools/build_negative_archive_bulksheet.py. What is genuinely limited',
        'is COVERAGE, not capability: the account registry rather than Amazon is the record of what',
        'is blocked, because the negative feed has been frozen since early 2026, so a negative',
        'created outside our books cannot be reconsidered by any layer. Treat a negative on this',
        'sheet as a standing answer with an expiry (doctrine 2.9), not as a settled fact.',
```

Apply the same correction to `tools/build_restore_seat_moves_bulksheet.py:9-17` in the same commit.

- [ ] **Step 3: Write the restore generator for the archive arm**

```python
#!/usr/bin/env python3
"""RESTORE FOR THE NEGATIVE ARCHIVE BOOK — put back the blocks an archive book removed.

Every book in this account has a restore generator, because a book that cannot be reversed is a
one-way door (architecture/THREE_LAYERS.md 5). This one reads an archive batch out of
FACT_PPC_CHANGE_LOG and emits the opposite sheet: the same negatives, State set back to enabled,
addressed by the same Amazon Keyword ID.

IT DOES NOT DELETE THE ORIGINAL ROWS. The change log is append-only; a restore is a NEW batch that
records what it reverses. Never uploaded by this script.
"""
import argparse
import json
import os
import subprocess
import sys
from datetime import date, datetime, timezone

import openpyxl

PROJECT = 'onyga-482313'

# THE CHANGE LOG, in the house shape every other book already uses. It is NOT an environment
# variable: tools/tests/test_change_log_discipline.py::test_a_change_log_override_must_be_a_tmp_copy
# calls set_change_log_table() and reads LIVE_CHANGE_LOG by name on every book in BOOKS, and an
# os.environ override carries no TMP_/TEMP_ guard at all — so the one thing that test exists to
# constrain would be unconstrained. Copy this block verbatim from
# tools/build_reprice_bulksheet.py:118-133; do not paraphrase it.
LIVE_CHANGE_LOG = "FACT_PPC_CHANGE_LOG"
CHANGE_LOG = f"{PROJECT}.OI.{LIVE_CHANGE_LOG}"


def set_change_log_table(table):
    global CHANGE_LOG
    assert table == LIVE_CHANGE_LOG or table.startswith(('TMP_', 'TEMP_')), \
        f"{table}: a change-log override must be a TMP_/TEMP_ copy — never another live table"
    CHANGE_LOG = f"{PROJECT}.OI.{table}"
    return CHANGE_LOG

NEGATIVE_HEADERS = [
    'Product', 'Entity', 'Operation', 'Campaign ID', 'Ad Group ID', 'Keyword ID',
    'Keyword Text', 'Match Type', 'State',
]


def q(v):
    if v is None:
        return 'NULL'
    return "'" + str(v).replace('\\', '\\\\').replace("'", "\\'") + "'"


def bq(sql):
    out = subprocess.run(
        ['bq', 'query', '--use_legacy_sql=false', '--nouse_cache', '--format=json',
         f'--project_id={PROJECT}', sql],
        capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f'query failed:\n{out.stderr}')
    return json.loads(out.stdout or '[]')


def run_update(sql, what):
    out = subprocess.run(
        ['bq', 'query', '--use_legacy_sql=false', '--nouse_cache', f'--project_id={PROJECT}', sql],
        capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f'{what} failed:\n{out.stderr}')


def batch_rows_sql(batch_id):
    """The archived negatives, re-joined to the registry for the id the sheet must carry."""
    return (f'SELECT c.campaign_id, c.campaign_name, c.ad_group_id, c.targeting AS keyword_text, '
            f'       c.match_type, n.negative_id '
            f'FROM `{CHANGE_LOG}` c '
            f'LEFT JOIN `{PROJECT}.OI.DE_NEGATIVE_KEYWORDS` n '
            f'  ON n.campaign_id = c.campaign_id '
            f' AND COALESCE(n.ad_group_id, \'\') = COALESCE(NULLIF(TRIM(c.ad_group_id), \'\'), \'\') '
            f' AND LOWER(n.keyword_text) = LOWER(c.targeting) '
            f'WHERE c.batch_id = {q(batch_id)} AND c.action = \'REMOVE_NEGATIVE\' '
            f'ORDER BY c.campaign_name, c.targeting')


def supersede_sql(batch_id, note):
    return (f"UPDATE `{CHANGE_LOG}` SET upload_status = 'SUPERSEDED_NEVER_UPLOADED', "
            f"upload_note = {q(note)} "
            f"WHERE batch_id = {q(batch_id)} AND upload_status = 'PENDING_UPLOAD'")


def mark_uploaded_sql(batch_id):
    return (f"UPDATE `{CHANGE_LOG}` SET upload_status = NULL "
            f"WHERE batch_id = {q(batch_id)} AND upload_status = 'PENDING_UPLOAD'")


def prior_unmarked_batches_sql():
    return (f"SELECT batch_id, COUNT(*) n, MIN(applied_at) built FROM `{CHANGE_LOG}` "
            f"WHERE upload_status = 'PENDING_UPLOAD' AND action = 'RESTORE_NEGATIVE' "
            f"GROUP BY batch_id ORDER BY built")


def log_batch(rows, batch_id, source_batch, readme_path):
    exists = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` WHERE batch_id = {q(batch_id)}")
    assert int(exists[0]['n']) == 0, f'batch id {batch_id} already exists in the change log'
    note = (f'restore of negative archive batch {source_batch}, built '
            f'{datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}; '
            f'README {os.path.basename(readme_path)}; manual upload pending')
    structs = []
    for i, r in enumerate(rows):
        structs.append(
            'STRUCT('
            f"{q('negrestore-' + batch_id.split('_')[-1] + '-' + str(i))} AS change_id, "
            f'{q(batch_id)} AS batch_id, CURRENT_TIMESTAMP() AS applied_at, '
            f"{q('RESTORE_NEGATIVE')} AS action, "
            f'{q(r["keyword_text"])} AS targeting, {q(r["keyword_text"])} AS search_term, '
            f'{q(r["match_type"])} AS match_type, '
            f'{q(str(r["campaign_id"]))} AS campaign_id, {q(r["campaign_name"])} AS campaign_name, '
            f'{q(r.get("ad_group_id"))} AS ad_group_id, '
            f"{q('MANUAL')} AS source, {q('MANUAL_BULKSHEET')} AS coach_mode, "
            f'{q(note)} AS upload_note, '
            f"{q('PENDING_UPLOAD')} AS upload_status)")
    cols = ('change_id, batch_id, applied_at, action, targeting, search_term, match_type, '
            'campaign_id, campaign_name, ad_group_id, source, coach_mode, upload_note, '
            'upload_status')
    run_update(f'INSERT INTO `{CHANGE_LOG}` ({cols}) '
               f"SELECT {cols} FROM UNNEST([{', '.join(structs)}])", 'change-log insert')
    back = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` WHERE batch_id = {q(batch_id)}")
    assert int(back[0]['n']) == len(rows)
    return int(back[0]['n'])


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('batch', nargs='?', help='the negative archive batch id to reverse')
    ap.add_argument('-o', '--out', default=None)
    ap.add_argument('--mark-uploaded', metavar='BATCH')
    ap.add_argument('--supersede', metavar='BATCH')
    args = ap.parse_args()

    if args.mark_uploaded:
        pending = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` "
                     f"WHERE batch_id = {q(args.mark_uploaded)} "
                     f"AND upload_status = 'PENDING_UPLOAD'")
        if int(pending[0]['n']) == 0:
            sys.exit(f'--mark-uploaded {args.mark_uploaded}: no PENDING_UPLOAD rows. Nothing changed.')
        run_update(mark_uploaded_sql(args.mark_uploaded), 'mark-uploaded')
        print(f'  marked batch {args.mark_uploaded} uploaded')
        return

    if args.supersede:
        pending = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` "
                     f"WHERE batch_id = {q(args.supersede)} "
                     f"AND upload_status = 'PENDING_UPLOAD'")
        if int(pending[0]['n']) == 0:
            sys.exit(f'--supersede {args.supersede}: no PENDING_UPLOAD rows. Nothing changed.')
        note = (f'never uploaded; superseded '
                f'({datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}) — labelled by the generator')
        run_update(supersede_sql(args.supersede, note), 'supersede')
        print(f'  labelled batch {args.supersede} SUPERSEDED_NEVER_UPLOADED')
        return

    if not args.batch:
        sys.exit('name the negative archive batch to reverse, or pass --mark-uploaded / --supersede')

    for b in bq(prior_unmarked_batches_sql()):
        print(f'  earlier restore book still pending: {b["batch_id"]} '
              f'({b["n"]} row(s), built {b["built"]})')

    rows = bq(batch_rows_sql(args.batch))
    if not rows:
        sys.exit(f'{args.batch}: no REMOVE_NEGATIVE rows under that batch id')

    missing = [r for r in rows if not r.get('negative_id')]
    if missing:
        for r in missing:
            print(f'  REFUSED "{r["keyword_text"]}" in {r["campaign_name"]} — the registry no '
                  f'longer holds a negative id for it, and Amazon cannot be addressed without one')
        rows = [r for r in rows if r.get('negative_id')]
    if not rows:
        sys.exit('nothing addressable to restore')

    out = args.out or f'.tmp/negative_archive_restore_{date.today():%Y%m%d}.xlsx'
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = 'Sponsored Products Campaigns'
    ws.append(NEGATIVE_HEADERS)
    for r in rows:
        ws.append(['Sponsored Products', 'Negative Keyword', 'Update', str(r['campaign_id']),
                   r.get('ad_group_id') or '', str(r['negative_id']), r['keyword_text'],
                   r['match_type'], 'enabled'])
    os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
    wb.save(out)

    batch_id = f'negrestore_{date.today():%Y%m%d}_{datetime.now(timezone.utc):%H%M%S}'
    readme = out.replace('.xlsx', '_README.txt')
    with open(readme, 'w') as fh:
        fh.write('\n'.join([
            'RESTORE FOR THE NEGATIVE ARCHIVE BOOK',
            f'batch {batch_id}   reverses {args.batch}   {len(rows)} negative(s)',
            '',
            'Every negative this sheet touches is set back to enabled, addressed by the same Amazon',
            'Keyword ID the archive book used. The original change-log rows are NOT deleted — the',
            'log is append-only, and this batch records what it reverses.',
            '',
            f'After you upload:  python3 tools/build_restore_negative_archive_bulksheet.py '
            f'--mark-uploaded {batch_id}',
            f'If you do not:     python3 tools/build_restore_negative_archive_bulksheet.py '
            f'--supersede {batch_id}',
            '',
            'This script never uploads anything to Amazon.',
        ]) + '\n')
    n = log_batch(rows, batch_id, args.batch, readme)
    print(f'  {n} negative(s) written to {out}')
    print(f'  batch {batch_id} logged PENDING_UPLOAD — this script uploads nothing')


if __name__ == '__main__':
    main()
```

- [ ] **Step 4: Deploy, test, commit**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SYNC_NEGATIVES.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SYNC_NEGATIVES\`();
   CALL \`onyga-482313.OI.SP_SYNC_NEGATIVES\`();"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT state, COUNT(*) n, COUNTIF(change_id IS NOT NULL) with_a_change_id
   FROM \`onyga-482313.OI.DE_NEGATIVE_KEYWORDS\` GROUP BY 1"
/usr/local/bin/python3 -m pytest tools/tests/ -q
git add scripts/bigquery/procedures/SP_SYNC_NEGATIVES.sql \
        tools/build_seat_moves_bulksheet.py \
        tools/build_restore_seat_moves_bulksheet.py \
        tools/build_restore_negative_archive_bulksheet.py \
        tools/tests/test_change_log_discipline.py
git commit -m "fix(negatives): traceable removals, a restore generator, and two corrected READMEs

The removal fold-back matched on campaign plus text only and never recorded the
change_id. The READMEs asserted a negative cannot be undone by a sheet, which
2.9's own correction disproved on 2026-08-24."
```

Expected: every removed row now carries a `change_id`, two calls are idempotent, all Python tests PASS.

---

### Task 9.4 (violation 24): `V_CATALOG_IMPROVE` — negates get an owner

**Files:**
- Create: `scripts/bigquery/views/V_CATALOG_IMPROVE.sql`
- Modify: `scripts/bigquery/tables/DE/DE_NEGATIVE_KEYWORDS.sql` (Step 0 — the three expiry columns this view reads)
- Modify: `config.yaml` (`views:`)

§2.9 gives the Brain a third question beside `ask()` and `rank()`: `improve(subject, window_from, window_to)` → ordered suggestions, of which **negate this search term is one option beside reprice, park and change-vehicle**, ranked by what each is worth, and owned by the Catalog.

- [ ] **Step 0: Add the three expiry columns FIRST — this view reads them, and they do not exist**

**Ordering, and it is the whole reason this step is numbered 0.** Step 1's `neg` CTE selects
`next_review_date`, `review_reason` and `season_context` from `DE_NEGATIVE_KEYWORDS`. The live table
carries fifteen columns — `negative_id, campaign_id, campaign_name, ad_group_id, ad_group_name,
keyword_text, match_type, level, state, source, added_at, removed_at, change_id, source_file,
updated_at` — and **none of the three is among them**. Deploying the view first fails with
`Unrecognized name: next_review_date`, and Step 2's expectation ("a `REMOVE_NEGATE` arm that is empty
today because no registry row carries a `next_review_date` yet") is written as though the column
exists and is merely unpopulated, so the failure reads like a mistake of your own. It is not: the
`ALTER` lived in Task 9.5 and Task 9.5 runs after this one.

Run the block that Task 9.5 Step 1 used to carry — the `ALTER`, then the one-time backfill:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
ALTER TABLE \`onyga-482313.OI.DE_NEGATIVE_KEYWORDS\`
  ADD COLUMN IF NOT EXISTS next_review_date DATE,
  ADD COLUMN IF NOT EXISTS review_reason    STRING,
  ADD COLUMN IF NOT EXISTS season_context   BOOL"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
UPDATE \`onyga-482313.OI.DE_NEGATIVE_KEYWORDS\`
SET next_review_date = DATE_ADD(GREATEST(DATE(added_at),
                                         DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 90 DAY)),
                                INTERVAL 90 DAY),
    review_reason = 'seeded 2026-08-25: a negative is a standing answer with an expiry (2.9), and this one had never been re-asked',
    updated_at = CURRENT_TIMESTAMP()
WHERE UPPER(COALESCE(state, 'ENABLED')) = 'ENABLED' AND next_review_date IS NULL"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT COUNT(*) enabled_negatives,
       COUNTIF(next_review_date IS NOT NULL) with_a_review_date,
       MIN(next_review_date) first_due, MAX(next_review_date) last_due
FROM \`onyga-482313.OI.DE_NEGATIVE_KEYWORDS\`
WHERE UPPER(COALESCE(state, 'ENABLED')) = 'ENABLED'"
```

The `GREATEST` keeps a nine-thousand-row registry from all coming due on one day: a negative added
long ago is scheduled 90 days from **now**, not 90 days from a date already in the past. Append the
three `ALTER TABLE` lines to `scripts/bigquery/tables/DE/DE_NEGATIVE_KEYWORDS.sql` with a comment
naming §2.9 and violation 24, and commit that file with this task.

Expected: `with_a_review_date = enabled_negatives`, `first_due` roughly 90 days out, `last_due` no
further than 90 days past the newest `added_at`. **Step 2's `REMOVE_NEGATE` arm will therefore be
empty today for the right reason** — the dates exist and none has arrived — rather than for the wrong
one.

- [ ] **Step 1: Write the view**

```sql
-- =============================================================================================
-- V_CATALOG_IMPROVE — the Catalog's answer to "how do I make this better?" (doctrine 2.9).
--
-- WHY IT EXISTS. Blocking a search term is a statement about WORTH — this traffic is not worth
-- buying — so it belongs to the Catalog, not to whichever engine happened to notice the term.
-- Today the blocking decision is made inside V_OOB_SEARCH_TERM and V_WEEKLY_RUN_NEGATIVE, nothing
-- re-asks it, and no live negative is ever reconsidered: 9,684 ENABLED registry rows against
-- exactly one REMOVED in the table's entire history (violation 24).
--
-- AND THE ANSWER EXPIRES. 2.9: asked again a month later the Catalog may say REMOVE THE NEGATE, for
-- the very same term, on either of two grounds — the data now says so, or the peak makes a
-- high-volume term worth unblocking simply to buy data. A negative is a standing answer with an
-- expiry, never a settled fact.
--
-- ONE ROW PER (subject, suggestion). Every suggestion carries what it is worth per day, so the
-- Brain can rank a negate against a reprice against a park the same way it ranks anything else.
--
-- THE GRAIN OF A NEGATIVE IS THE AD GROUP. A negative acts on an ad group, so ASIN-sliced evidence
-- must never emit one; the ad-group list is carried as a STRING_AGG comma list, exactly the shape
-- SP_SNAPSHOT_ENGINE_PROPOSALS's two negate INSERTs already use and their consumers already split.
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CATALOG_IMPROVE` AS
WITH wm AS (
  SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),
k AS (
  -- DECLARED CONSTANTS, each with its derivation:
  --   term_meas_clk 15  the same evidence bar FACT_KEYWORD_SEASON_VERDICT uses before it will
  --                     record a verdict at all — thin evidence is never a verdict
  --   review_days 90    a negate is re-asked once a full settled window has passed under it, so the
  --                     re-ask reads a record the block itself did not write
  SELECT 15 AS term_meas_clk, 90 AS review_days
),
-- the term-level record inside each subject's own campaign, complete days only
term AS (
  SELECT CAST(a.campaign_id AS STRING) AS campaign_id,
         ANY_VALUE(a.campaign_name)    AS campaign_name,
         LOWER(TRIM(a.search_term))    AS term,
         STRING_AGG(DISTINCT CAST(a.ad_group_id AS STRING), ',')      AS ad_group_ids,
         SUM(a.Ads_clicks)             AS clicks,
         SUM(a.Ads_cost)               AS spend,
         SUM(a.Ads_orders)             AS orders,
         SUM(a.GROSS_PROFIT)           AS gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a, wm w
  WHERE a.search_term IS NOT NULL
    AND a.date BETWEEN DATE_SUB(w.d, INTERVAL 92 DAY) AND DATE_SUB(w.d, INTERVAL 3 DAY)
  GROUP BY 1, 3
),
bar AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id,
         ANY_VALUE(keyword_bar) AS campaign_bar, ANY_VALUE(family) AS family
  FROM `onyga-482313.OI.T_FAMILY_BAR` GROUP BY 1
),
neg AS (
  SELECT campaign_id, ad_group_id, negative_id, keyword_text, match_type, level, added_at,
         next_review_date, review_reason AS registry_review_reason, season_context
  FROM `onyga-482313.OI.DE_NEGATIVE_KEYWORDS`
  WHERE UPPER(COALESCE(state, 'ENABLED')) = 'ENABLED'
),
-- last year's same window for the term, so a seasonal re-ask has evidence rather than a hunch
season AS (
  SELECT LOWER(TRIM(a.search_term)) AS term,
         SUM(a.Ads_clicks) AS ly_clicks, SUM(a.Ads_orders) AS ly_orders,
         SUM(a.Ads_cost) AS ly_spend, SUM(a.GROSS_PROFIT) AS ly_gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  WHERE a.search_term IS NOT NULL
    AND a.date BETWEEN DATE_SUB((SELECT window_from FROM (
                          SELECT COALESCE(MIN(window_from),
                                          DATE_ADD((SELECT d FROM wm), INTERVAL 1 DAY)) AS window_from
                          FROM `onyga-482313.OI.DE_CATALOG_WINDOW_REQUEST` WHERE is_active)),
                        INTERVAL 364 DAY)
                  AND DATE_SUB((SELECT window_to FROM (
                          SELECT COALESCE(MIN(window_to),
                                          DATE_ADD((SELECT d FROM wm), INTERVAL 28 DAY)) AS window_to
                          FROM `onyga-482313.OI.DE_CATALOG_WINDOW_REQUEST` WHERE is_active)),
                        INTERVAL 364 DAY)
  GROUP BY 1
)
-- ── SUGGESTION 1: NEGATE a term that is buying clicks and returning nothing ────────────────────
SELECT
  t.campaign_id,
  t.campaign_name,
  b.family,
  t.ad_group_ids,
  CAST(NULL AS STRING)                                              AS negative_id,
  t.term                                                            AS keyword_text,
  'NEGATIVE_EXACT'                                                  AS match_type,
  'AD_GROUP'                                                        AS level,
  'NEGATE'                                                          AS suggestion,
  FORMAT('over the settled window it took %d clicks on $%.2f and returned %.2f gross-profit dollars per ad dollar, against a bar of %.2f',
         t.clicks, t.spend, COALESCE(SAFE_DIVIDE(t.gp, NULLIF(t.spend, 0)), 0),
         COALESCE(b.campaign_bar, 1.0))                             AS review_reason,
  -- what blocking it is worth per day: the money it is losing against its own bar
  ROUND(GREATEST(t.spend - COALESCE(t.gp, 0) / NULLIF(COALESCE(b.campaign_bar, 1.0), 0), 0) / 90, 4)
                                                                    AS suggestion_value_per_day,
  DATE_ADD((SELECT d FROM wm), INTERVAL (SELECT review_days FROM k) DAY) AS next_review_date,
  CAST(NULL AS BOOL)                                                AS season_context,
  CAST(NULL AS INT64)                                               AS market_volume_weekly,
  CAST(NULL AS FLOAT64)                                             AS our_share_pct
FROM term t
LEFT JOIN bar b ON b.campaign_id = t.campaign_id
LEFT JOIN neg n ON n.campaign_id = t.campaign_id AND LOWER(n.keyword_text) = t.term
WHERE n.campaign_id IS NULL                       -- not already blocked
  AND t.clicks >= (SELECT term_meas_clk FROM k)
  AND COALESCE(t.orders, 0) = 0
  AND t.spend > 0

UNION ALL

-- ── SUGGESTION 2: REMOVE a negate whose answer has expired (doctrine 2.9) ─────────────────────
SELECT
  n.campaign_id,
  ANY_VALUE(c.campaign_name),
  ANY_VALUE(b.family),
  n.ad_group_id                                                     AS ad_group_ids,
  ANY_VALUE(n.negative_id),
  n.keyword_text,
  ANY_VALUE(n.match_type),
  ANY_VALUE(n.level),
  'REMOVE_NEGATE'                                                   AS suggestion,
  CASE
    -- GROUND 1: the data now says so. It earned in this same window last year, above the bar.
    WHEN ANY_VALUE(s.ly_clicks) >= (SELECT term_meas_clk FROM k)
     AND COALESCE(SAFE_DIVIDE(ANY_VALUE(s.ly_gp), NULLIF(ANY_VALUE(s.ly_spend), 0)), 0)
         >= COALESCE(ANY_VALUE(b.campaign_bar), 1.0)
      THEN FORMAT('it earned in this same window last year — %d clicks, %d orders, %.2f gross-profit dollars per ad dollar — and a judgement made on a thin or out-of-season record is re-made when the evidence changes (2.9)',
                  ANY_VALUE(s.ly_clicks), ANY_VALUE(s.ly_orders),
                  COALESCE(SAFE_DIVIDE(ANY_VALUE(s.ly_gp), NULLIF(ANY_VALUE(s.ly_spend), 0)), 0))
    -- GROUND 2: the peak makes a high-volume term worth re-learning, even with no positive record.
    ELSE FORMAT('its review date has arrived and the coming window is a peak — a high-volume term blocked before a season can be worth unblocking simply to buy data (2.9). Volume is the reason: a term nobody searches is never worth re-testing.')
  END                                                               AS review_reason,
  -- what removing it is worth per day: what the term earned per day last year in this window.
  -- 6.3: this is an ESTIMATE of an upside, not a measured loss, and it is labelled as a suggestion
  -- value rather than as money currently being lost.
  ROUND(COALESCE(ANY_VALUE(s.ly_gp) - ANY_VALUE(s.ly_spend), 0)
        / NULLIF(DATE_DIFF((SELECT COALESCE(MIN(window_to), DATE_ADD((SELECT d FROM wm), INTERVAL 28 DAY))
                            FROM `onyga-482313.OI.DE_CATALOG_WINDOW_REQUEST` WHERE is_active),
                           (SELECT COALESCE(MIN(window_from), DATE_ADD((SELECT d FROM wm), INTERVAL 1 DAY))
                            FROM `onyga-482313.OI.DE_CATALOG_WINDOW_REQUEST` WHERE is_active),
                           DAY), 0), 4)                             AS suggestion_value_per_day,
  ANY_VALUE(n.next_review_date),
  ANY_VALUE(n.season_context),
  CAST(NULL AS INT64)                                               AS market_volume_weekly,
  CAST(NULL AS FLOAT64)                                             AS our_share_pct
FROM neg n
LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_IDENTITY` c ON c.campaign_id = n.campaign_id
LEFT JOIN bar b ON b.campaign_id = n.campaign_id
LEFT JOIN season s ON s.term = LOWER(TRIM(n.keyword_text))
WHERE n.next_review_date IS NOT NULL
  AND n.next_review_date <= (SELECT d FROM wm)
GROUP BY n.campaign_id, n.ad_group_id, n.keyword_text;
```

`market_volume_weekly` and `our_share_pct` are `NULL` here on purpose: no Catalog object reads market volume until Phase 11, and §6.3 forbids asserting a number that has not been computed. Task 11.5 fills both.

- [ ] **Step 2: Deploy and read both arms**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_CATALOG_IMPROVE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT suggestion, COUNT(*) n, ROUND(SUM(suggestion_value_per_day), 2) usd_per_day
   FROM \`onyga-482313.OI.V_CATALOG_IMPROVE\` GROUP BY 1 ORDER BY usd_per_day DESC"
```

Expected: a `NEGATE` arm carrying real daily money, and a `REMOVE_NEGATE` arm that is **empty today**
— Step 0 seeded a `next_review_date` on every ENABLED registry row and none of them has arrived yet
(the earliest is roughly 90 days out). Empty for that reason is correct; a deploy error naming
`next_review_date` means Step 0 was skipped.

- [ ] **Step 3: Register and commit**

Add `V_CATALOG_IMPROVE` to `config.yaml` under `views:` beside `V_KEYWORD_STATE`'s neighbours.

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_CATALOG_IMPROVE.sql \
        scripts/bigquery/tables/DE/DE_NEGATIVE_KEYWORDS.sql config.yaml
git commit -m "feat(catalog): V_CATALOG_IMPROVE — improve() gives negatives an owner

Closes half of violation 24. Blocking a term is a statement about worth, so it
belongs to the Catalog and is ranked by what it is worth, beside reprice and park.
The three expiry columns land here rather than in Task 9.5, because this view reads
them and would not deploy without them."
```

---

### Task 9.5 (violation 24): the expiry, and the end of "negated once means settled"

**Files:**
- Modify: `scripts/bigquery/tables/DE/DE_NEGATIVE_KEYWORDS.sql` (three columns and a backfill)
- Modify: `scripts/bigquery/views/V_WEEKLY_RUN_NEGATIVE.sql:36-50`
- Modify: `tools/build_seat_moves_bulksheet.py` (`classify_negate()` at 232–301)
- Modify: `scripts/bigquery/views/V_SEASON_NEGATE_CANDIDATES.sql` (wire it up)

- [ ] **Step 1: Confirm the expiry columns are already there — Task 9.4 Step 0 added them**

The three columns and their one-time backfill moved to **Task 9.4 Step 0**, because Task 9.4's
`V_CATALOG_IMPROVE` reads all three and would not deploy without them. Nothing to add here; confirm
it and move on:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT column_name FROM \`onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS\`
   WHERE table_name = 'DE_NEGATIVE_KEYWORDS'
     AND column_name IN ('next_review_date','review_reason','season_context')
   ORDER BY column_name"
```

Expected: three rows. If it returns none, Task 9.4 Step 0 was skipped — go back and run it, because
`V_CATALOG_IMPROVE` cannot have deployed either.

- [ ] **Step 2: Replace the permanent `NOT EXISTS` with "re-ask at expiry"**

In `V_WEEKLY_RUN_NEGATIVE.sql:36-50`, the `NOT EXISTS` skips a term already negated in this campaign, forever. Add one clause inside it so the exclusion **expires**:

```sql
    -- 2026-08-25 (violation 24): the duplicate-bounce protection STAYS — Amazon rejects a Create for
    -- a negative that already exists, and re-suggesting one wastes an upload. What goes is the
    -- PERMANENCE. Doctrine 2.9: "nothing may treat 'we negated this once' as settled, and the set of
    -- live negatives is re-asked like everything else." A block whose review date has arrived is no
    -- longer a reason not to look; V_CATALOG_IMPROVE decides whether it comes off.
    AND NOT EXISTS (
      SELECT 1 FROM `onyga-482313.OI.DE_NEGATIVE_KEYWORDS` nk
      WHERE nk.campaign_id = CAST(vc.campaign_id AS STRING)
        AND nk.removed_at IS NULL
        AND UPPER(COALESCE(nk.state, 'ENABLED')) NOT IN ('ARCHIVED', 'REMOVED', 'PAUSED')
        AND (nk.next_review_date IS NULL
             OR nk.next_review_date > CURRENT_DATE('America/Los_Angeles'))
        AND (
          (UPPER(COALESCE(nk.match_type, '')) LIKE '%EXACT%' AND LOWER(nk.keyword_text) = LOWER(vc.search_term))
          OR (UPPER(COALESCE(nk.match_type, '')) LIKE '%PHRASE%' AND STRPOS(LOWER(vc.search_term), LOWER(nk.keyword_text)) > 0)
        )
    )
```

- [ ] **Step 3: Give `classify_negate()` an arm that proposes a removal**

`tools/build_seat_moves_bulksheet.py:232-301` has nine arms and **every one is a reason not to create**. Add a tenth, at the top, that proposes the opposite:

```python
    # ── 2026-08-25 (violation 24): THE ARM THAT PROPOSES A REMOVAL ────────────────────────────
    # Nine arms below are reasons NOT to create a negative. None of them could ever suggest taking
    # one off, because a negative was treated as a settled fact — 9,684 ENABLED registry rows against
    # exactly one REMOVED in the table's history. Doctrine 2.9: a negative is a standing answer with
    # an expiry, and the Catalog may answer "remove the negate" for the very same term.
    # The decision is the CATALOG's (V_CATALOG_IMPROVE); this book only reports it, and the removal
    # travels in tools/build_negative_archive_bulksheet.py, which is the arm that carries it.
    if r.get('improve_suggestion') == 'REMOVE_NEGATE':
        return ('REMOVE_NEGATE',
                f"the keyword state re-asked this block and now answers differently: "
                f"{r.get('improve_reason') or ''} It is removed by "
                f"tools/build_negative_archive_bulksheet.py, not by this sheet.")
```

with `improve_suggestion` and `improve_reason` joined in from `V_CATALOG_IMPROVE` in the book's own query.

- [ ] **Step 4: Wire up `V_SEASON_NEGATE_CANDIDATES`, which is dead code today**

```bash
cd /Users/ori/Develop/OI
grep -rn "V_SEASON_NEGATE_CANDIDATES" scripts/ tools/ dashboard-react/src/ cube/ 2>/dev/null | grep -v "views/V_SEASON_NEGATE_CANDIDATES.sql"
```

Expected: **no consumer at all** — no SP, no book, no cube schema, no dashboard page. It is the account's only seasonal negate reasoning (ENTRY_BLOCK / STOP keyword texts with a mature same-family LOSS prior) and it already answers half of §2.9's first ground. Add it as a third arm of `V_CATALOG_IMPROVE`, unioned with the other two, emitting `suggestion = 'NEGATE'` with `review_reason` naming the seasonal prior and `season_context = TRUE`.

- [ ] **Step 5: DECLARED CONSTANT — rule 4's volume floor is ORI'S OPEN RULING**

§2.9: *"a term nobody searches is never worth re-testing."* The correct source for that volume is market data, which does not exist in the Catalog chain until Phase 11. Seed it against our own impressions for now, and say so:

```sql
-- ── ORI'S OPEN RULING: THE VOLUME FLOOR FOR A COVERAGE RE-TEST (doctrine 6.4, 2.9) ────────────
-- 2.9's second ground for removing a negate is that a peak makes a HIGH-VOLUME term worth
-- re-learning even without a positive record — "volume is the reason; a term nobody searches is
-- never worth re-testing." What counts as high volume is ORI'S OPEN RULING and is not decided here.
-- SEEDED AGAINST OUR OWN IMPRESSIONS, because the correct source does not exist yet: no object in
-- the Catalog/Brain/Pacing chain reads market volume until Phase 11 of the gap-closure plan, and
-- 6.3 forbids asserting a number we have not computed. Task 11.5 re-bases this on the market's
-- weekly search volume, which is the number 2.9 actually means.
--   retest_volume_floor 500  impressions in the same window last year, at term grain
-- THE EXPERIMENT THAT SETTLES IT (6.1), declared before it runs:
--   WHICH SETTING   retest_volume_floor, tested at 500 against 100 and 2000
--   WHICH SLICE     the negatives coming due inside one family per arm, on disjoint families so the
--                   arms cannot contaminate each other (6.2). NEVER the holdout arm.
--   WHAT DECIDES IT net profit on the unblocked terms over one full peak window
--   BY WHEN         the end of the first peak in which all three arms have run
500 AS retest_volume_floor,
```

Add the floor to the `k` CTE of `V_CATALOG_IMPROVE` and apply it to the `REMOVE_NEGATE` arm's ground-2 branch.

- [ ] **Step 6: Deploy the chain, verify, commit**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tables/DE/DE_NEGATIVE_KEYWORDS.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_CATALOG_IMPROVE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_WEEKLY_RUN_NEGATIVE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT suggestion, COUNT(*) n, ROUND(SUM(suggestion_value_per_day), 2) usd_per_day
   FROM \`onyga-482313.OI.V_CATALOG_IMPROVE\` GROUP BY 1 ORDER BY n DESC"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT COUNTIF(next_review_date IS NOT NULL) with_a_review_date, COUNT(*) enabled_negatives
   FROM \`onyga-482313.OI.DE_NEGATIVE_KEYWORDS\`
   WHERE UPPER(COALESCE(state,'ENABLED')) = 'ENABLED'"
/usr/local/bin/python3 -m pytest tools/tests/ -q
git add scripts/bigquery/tables/DE/DE_NEGATIVE_KEYWORDS.sql \
        scripts/bigquery/views/V_CATALOG_IMPROVE.sql \
        scripts/bigquery/views/V_WEEKLY_RUN_NEGATIVE.sql \
        scripts/bigquery/views/V_SEASON_NEGATE_CANDIDATES.sql \
        tools/build_seat_moves_bulksheet.py
git commit -m "feat(catalog): a negative expires — it is a standing answer, not a settled fact

Closes violation 24. Every live negative gets a review date, the coach's permanent
NOT EXISTS becomes 're-ask at expiry', classify_negate gains its first arm that
proposes a removal, and V_SEASON_NEGATE_CANDIDATES stops being dead code.
Rule 4's volume floor is ORI'S OPEN RULING, seeded and flagged."
```

Expected: every ENABLED negative carries a review date, both `V_CATALOG_IMPROVE` arms return rows, and all Python tests PASS.

---
## Phase 10 — The response curve, and two layers finally graded

**Closes:** violations 3 and 17 (one fix), the grading half of violation 13, **and the grading half
of violation 6** — Phase 0 gave the Catalog a memory so that §6 could be satisfied, and Task 10.8 is
the task that actually satisfies it. It sits here, not in Phase 0, because a scorecard is gated on
elapsed time exactly like the curve is: a prediction made on day D cannot be graded until day D's
window has settled.

**Why 3 and 17 are one piece of work.** §2.5 says so in as many words: the curve §2 requires for marginal-versus-average pricing, used for a second purpose, is *"one piece of work and not two"*. 3 is the marginal defect — `affordable_cpc` is `(settled_gp90 / settled_clk90) / keyword_bar` (`SP_SNAPSHOT_KEYWORD_STATE.sql:320-323`), a flat 90-day average with a cleaned twin of the same scalar shape at 341–345. 17 is the quantity defect — nothing decides how many clicks to buy. Both are the same curve read at two points.

**Why it is late.** It is the only violation whose input did not exist when the plan started. The only elasticity in the account is bid→CPC (`V_BID_CPC_TRANSFER`, gamma 0.778 with a confidence interval of [0.638, 0.872]); **nothing anywhere maps a bid or a price to a click quantity**, so violation 17 has no partial implementation to extend. §10.4 names the missing input precisely: nothing records the clicks and price a chosen bid was expected to deliver against what it delivered. Phase 0 started that recording on day one; by now it has weeks of paired predictions and outcomes, which is what makes this phase possible at all.

**The doctrine's own warning applies throughout:** every "excess" figure in §10 is computed against an **average** ceiling and misstates the true overpayment in an unknown direction until this phase re-states them.

**Unblocks:** Phase 12's `rank()` ordering; the honest re-statement of every excess figure in the baseline; and the entry-anchor question — whether bidding $1.27 to buy decision data actually buys decision data.

**Size:** L — 2–3 weeks, and the only phase whose schedule depends on **elapsed time** rather than effort. It cannot start until `FACT_ENGINE_PROPOSALS` and `FACT_KEYWORD_STATE_HISTORY` hold enough paired days to fit a curve and to grade a prediction — check before starting. Eight tasks: the segment axis (`FN_MATCH_WIDTH`), the curve, the marginal ceiling and quantity answer, the Pacing scorecard, the two house constants, the re-based rank, the re-stated excess figures, and the Catalog scorecard.

---

### Task 10.1: The red measurement, and the readiness gate

- [ ] **Step 1: Prove the ceiling is a flat average and nothing publishes clicks-at-a-price**

```bash
cd /Users/ori/Develop/OI
sed -n '318,346p' scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT ceiling_basis, COUNT(*) n FROM \`onyga-482313.OI.V_KEYWORD_STATE\` GROUP BY 1"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT column_name FROM \`onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS\`
   WHERE LOWER(column_name) LIKE '%clicks_at%' OR LOWER(column_name) LIKE '%volume_at%'"
```

Expected: `ceiling_basis` reads `AVERAGE` on every row, and the third query returns nothing.

- [ ] **Step 2: The readiness gate — do not start without the input**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT COUNT(DISTINCT snapshot_date) AS days_of_predictions,
       COUNTIF(expected_cpc IS NOT NULL) AS rows_with_a_prediction,
       MIN(snapshot_date) AS first_day
FROM \`onyga-482313.OI.FACT_ENGINE_PROPOSALS\`"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT COUNT(DISTINCT snapshot_date) AS days_of_catalog_history
   FROM \`onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY\`"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT COUNT(*) AS landed_bid_changes_with_a_prediction
FROM \`onyga-482313.OI.FACT_PPC_CHANGE_LOG\`
WHERE predicted_cpc IS NOT NULL AND upload_status IS NULL
  AND applied_at < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 14 DAY)"
```

**Do not proceed** until `days_of_predictions` is at least 28 and `landed_bid_changes_with_a_prediction` is non-trivial. A curve fitted on a fortnight of one-directional moves is a fitted artefact, and shipping it as `ceiling_basis = 'MARGINAL'` would be exactly the "assert a number we have not computed" failure §6.3 exists to stop. If the gate is not met, the honest action is to wait and to say so — the recording started in Phase 0 precisely so that waiting is finite.

- [ ] **Step 3: Record the measurement and commit it**

Every red measurement in this plan is a number the green run is compared against, so it is written
down rather than remembered. Append what you measured — the query, the date, and the count — to the
running record, creating the file on the first task that reaches this step:

```bash
cd /Users/ori/Develop/OI
mkdir -p docs/superpowers/specs
cat >> docs/superpowers/specs/2026-08-25-gap-closure-measurements.md <<'EOF'

## Task 10.1 — measured YYYY-MM-DD

Replace the date above with the date you ran it, and paste below: the query you ran (unchanged from
the task), and its output. Do not summarise the output — the point of this file is that a re-run is
a re-run and not a fresh argument, which is the same reason
docs/superpowers/specs/2026-08-24-three-layers-baseline.md exists.
EOF
git add docs/superpowers/specs/2026-08-25-gap-closure-measurements.md
git commit -m "measure(task 10.1): record the red measurement before the fix

The number the green run is compared against, written down rather than remembered."
```

---

### Task 10.2: `V_CLICK_RESPONSE_CURVE`

**Files:**
- Create: `scripts/bigquery/functions/FN_MATCH_WIDTH.sql`
- Create: `scripts/bigquery/views/V_CLICK_RESPONSE_CURVE.sql`
- Modify: `config.yaml` (`functions:` beside `FN_MOVE_CAP`; `views:` beside `V_KEYWORD_GUARD`)

**Fit per SEGMENT, not per keyword.** §2 is explicit: elasticity is realistically estimated per family × match type × placement and applied per keyword — *"do not promise per-keyword precision the data cannot support."*

- [ ] **Step 0: `FN_MATCH_WIDTH` — one definition of the segment axis, callable from both sides**

The curve is fitted over `FACT_AMAZON_ADS`, whose targeting columns are `targeting` /
`targeting_type`. It is READ in Task 10.3 over `FACT_KEYWORD_STATE`, whose columns are `target_text`
/ `match_type` and which sources them from `DIM_KEYWORD`. **The two vocabularies are not the same**,
and a comment saying "keep these identical" does not make them identical. Measured 2026-08-24 on the
838-row keyword-state snapshot against 30 days of ads: writing the fit side as
`UPPER(COALESCE(targeting_type,'UNKNOWN'))` and the read side as
`UPPER(COALESCE(match_type,'UNKNOWN'))` puts **309 of 838 subjects** into buckets the fit side never
produces — 288 rows reading `ASIN` and 21 reading `ASIN EXPANDED` where the ads side says `PT`. Every
one of them would silently fall back to `ceiling_basis = 'AVERAGE'` with no error and no alarm, so
violations 3 and 17 would read as closed while the marginal ceiling reached barely half the account.

So the axis is a function, taking the `(text, type)` pair both sides actually have:

```sql
-- =============================================================================================
-- FN_MATCH_WIDTH — the segment axis of the click response curve, in ONE place.
--
-- WHY A FUNCTION AND NOT A COPIED CASE. V_CLICK_RESPONSE_CURVE fits over FACT_AMAZON_ADS
-- (targeting, targeting_type) and SP_SNAPSHOT_KEYWORD_STATE reads the fit over FACT_KEYWORD_STATE
-- (target_text, match_type, sourced from DIM_KEYWORD). Both are (text, type) pairs and their
-- vocabularies OVERLAP WITHOUT MATCHING: the ads side carries AUTOMATIC and the four auto clauses,
-- the config side carries ASIN, 'ASIN EXPANDED', PRODUCT and TARGETING_EXPRESSION. A copied CASE
-- diverges the first time either source gains a value, and the failure is silent — the join simply
-- misses and the subject falls back to the average ceiling. Measured before this function existed:
-- 309 of 838 subjects fell into buckets the fit side never produced.
--
-- THE TEXT WINS OVER THE TYPE, because the four auto clauses and the asin/category prefixes are the
-- most reliable signals either source carries; the type is the fallback. UNKNOWN is a real answer
-- and is published as one: a segment nothing maps to simply has no subjects reading it.
-- =============================================================================================
CREATE OR REPLACE FUNCTION `onyga-482313.OI.FN_MATCH_WIDTH`(target_text STRING, target_type STRING)
RETURNS STRING
AS (
  CASE
    WHEN LOWER(COALESCE(target_text, ''))
           IN ('close-match','loose-match','substitutes','complements')      THEN 'AUTO'
    WHEN UPPER(COALESCE(target_type, '')) LIKE 'AUTO%'                       THEN 'AUTO'
    WHEN LOWER(COALESCE(target_text, '')) LIKE 'asin%'
      OR LOWER(COALESCE(target_text, '')) LIKE 'category%'                   THEN 'PT'
    WHEN UPPER(COALESCE(target_type, '')) LIKE 'ASIN%'
      OR UPPER(COALESCE(target_type, '')) LIKE 'CATEGORY%'
      OR UPPER(COALESCE(target_type, '')) IN ('PRODUCT','PT','TARGETING_EXPRESSION')
                                                                             THEN 'PT'
    WHEN UPPER(COALESCE(target_type, '')) IN ('BROAD','PHRASE','EXACT')
                                                                             THEN UPPER(target_type)
    ELSE 'UNKNOWN'
  END
);
```

Deploy it and prove the two sides now agree on a vocabulary — this is the check that makes the
`ceiling_basis` result in Task 10.3 trustworthy:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/functions/FN_MATCH_WIDTH.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH st AS (
  SELECT \`onyga-482313.OI.FN_MATCH_WIDTH\`(target_text, match_type) w, COUNT(*) n
  FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`)
  GROUP BY 1),
ad AS (
  SELECT \`onyga-482313.OI.FN_MATCH_WIDTH\`(targeting, targeting_type) w, COUNT(*) n
  FROM \`onyga-482313.OI.FACT_AMAZON_ADS\`
  WHERE date > DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 364 DAY)
  GROUP BY 1)
SELECT st.w AS state_bucket, st.n AS subjects,
       ad.n AS ads_rows_in_the_same_bucket
FROM st LEFT JOIN ad USING (w) ORDER BY subjects DESC"
```

Expected: **every** `state_bucket` has a non-null `ads_rows_in_the_same_bucket`. A NULL there is a
segment the fit will never produce, and Task 10.3's join would miss every subject in it. Register
`FN_MATCH_WIDTH` in `config.yaml` under `functions:`, immediately after `FN_MOVE_CAP`.

- [ ] **Step 1: Write the view**

```sql
-- =============================================================================================
-- V_CLICK_RESPONSE_CURVE — how many clicks a price buys, per segment (doctrine 2.5).
--
-- WHY IT EXISTS. ceiling_cpc answers WHAT WE MAY PAY for a click. It does not answer HOW MANY
-- CLICKS TO BUY, and a doctrine that prices without quantifying cannot tell overpaying apart from
-- over-buying — two failures needing opposite responses. 10.2 records the case: across one
-- post-season month, spend rose sharply while cost per click barely moved. The account bought far
-- MORE clicks, correctly priced, into a market whose conversion rate had fallen. Every price was
-- defensible; the quantity was the question, and no layer had language for it.
--
-- THE SEGMENT IS family x match width x placement, per doctrine 2's instruction not to promise
-- per-keyword precision the data cannot support. Placement is the only split FACT_AMAZON_ADS
-- actually carries (two values account-wide — see violation 18 and Phase 13); the segment is
-- honest about that rather than inventing a finer one.
--
-- THE MODEL. Two relationships, fitted separately because they are separately observable:
--   1. bid -> CPC.   NOT re-derived here. V_BID_CPC_TRANSFER already publishes it as
--                    CPC = k_effective * bid^gamma * m_effective, with gamma 0.778 and a published
--                    confidence interval, and it is the account's one established elasticity.
--   2. CPC -> CLICKS. New, and the thing violation 17 asks for. Fitted in log-log space by
--                    ordinary least squares over the segment's own history:
--                        ln(clicks_per_day) = a + b * ln(cpc)
--                    b is the click elasticity: how many percent more clicks a percent more price
--                    buys. It is expected to be POSITIVE (paying more wins more auctions) and
--                    typically well below 1 (diminishing returns), and both expectations are
--                    published as fit_warning rather than enforced, because a segment that
--                    genuinely behaves otherwise is a finding and not a bug.
--
-- 6.3 IS BINDING: n_points, r_squared and fit_warning are published on every row, so a consumer can
-- refuse a curve fitted on too little. A segment that cannot be fitted publishes NULL coefficients
-- and fit_warning = 'INSUFFICIENT_DATA' — never a default that looks like an answer.
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CLICK_RESPONSE_CURVE` AS
WITH wm AS (
  SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),
k AS (
  -- DECLARED CONSTANTS:
  --   min_points 30    an ordinary-least-squares slope on fewer than 30 (subject, week) points is
  --                    not a measurement; it is a line through noise
  --   min_clicks 5     a week with fewer than 5 clicks carries no usable price signal
  --   history_days 364 a full year, so a segment's curve is not fitted inside one season
  SELECT 30 AS min_points, 5 AS min_clicks, 364 AS history_days
),
-- the segment, resolved once
seg AS (
  SELECT
    CAST(a.campaign_id AS STRING)                                   AS campaign_id,
    CAST(a.keyword_id  AS STRING)                                   AS keyword_id,
    COALESCE(fb.family, 'Unknown')                                  AS family,
    -- THE SEGMENT AXIS IS FN_MATCH_WIDTH's, never a CASE written out here. Task 10.3 calls the
    -- same function over FACT_KEYWORD_STATE's (target_text, match_type); a copy in either place is
    -- a divergence waiting to happen, and the divergence is silent.
    `onyga-482313.OI.FN_MATCH_WIDTH`(a.targeting, a.targeting_type)              AS match_width,
    COALESCE(a.placement_type, 'UNKNOWN')                           AS placement,
    DATE_TRUNC(a.date, WEEK(SUNDAY))                                AS wk,
    SUM(a.Ads_clicks)                                               AS clicks,
    SUM(a.Ads_cost)                                                 AS cost,
    SUM(a.Ads_orders)                                               AS orders,
    SUM(a.GROSS_PROFIT)                                             AS gp,
    COUNT(DISTINCT a.date)                                          AS active_days
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a, wm w
  LEFT JOIN (SELECT CAST(campaign_id AS STRING) cid, ANY_VALUE(family) family
             FROM `onyga-482313.OI.T_FAMILY_BAR` GROUP BY 1) fb
    ON fb.cid = CAST(a.campaign_id AS STRING)
  WHERE a.keyword_id IS NOT NULL
    AND a.date BETWEEN DATE_SUB(w.d, INTERVAL (SELECT history_days FROM k) DAY)
                   AND DATE_SUB(w.d, INTERVAL 1 DAY)
  GROUP BY 1, 2, 3, 4, 5, 6
),
-- one observation per (subject, week): the price it paid and the clicks it took at that price
pts AS (
  SELECT family, match_width, placement,
         LN(SAFE_DIVIDE(cost, NULLIF(clicks, 0)))              AS x,   -- ln(cpc)
         LN(SAFE_DIVIDE(clicks, NULLIF(active_days, 0)))       AS y,   -- ln(clicks per active day)
         SAFE_DIVIDE(orders, NULLIF(clicks, 0))                AS cvr,
         SAFE_DIVIDE(gp, NULLIF(orders, 0))                    AS gp_per_order
  FROM seg
  WHERE clicks >= (SELECT min_clicks FROM k)
    AND cost > 0 AND active_days > 0
),
fit AS (
  SELECT
    family, match_width, placement,
    COUNT(*)                                                        AS n_points,
    -- ordinary least squares in closed form: b = cov(x,y) / var(x), a = mean(y) - b*mean(x)
    SAFE_DIVIDE(COVAR_SAMP(y, x), NULLIF(VAR_SAMP(x), 0))           AS b_click_elasticity,
    AVG(y) - SAFE_DIVIDE(COVAR_SAMP(y, x), NULLIF(VAR_SAMP(x), 0)) * AVG(x)
                                                                    AS a_intercept,
    -- r squared for a simple linear fit is the square of the correlation
    POW(CORR(y, x), 2)                                              AS r_squared,
    AVG(cvr)                                                        AS seg_cvr,
    AVG(gp_per_order)                                               AS seg_gp_per_order,
    EXP(AVG(x))                                                     AS seg_geomean_cpc,
    EXP(AVG(y))                                                     AS seg_geomean_clicks_per_day
  FROM pts
  WHERE x IS NOT NULL AND y IS NOT NULL
  GROUP BY 1, 2, 3
)
SELECT
  family,
  match_width,
  placement,
  n_points,
  ROUND(b_click_elasticity, 4)                                      AS click_elasticity,
  ROUND(a_intercept, 4)                                             AS intercept,
  ROUND(r_squared, 4)                                               AS r_squared,
  ROUND(seg_cvr, 5)                                                 AS segment_cvr,
  ROUND(seg_gp_per_order, 4)                                        AS segment_gp_per_order,
  ROUND(seg_geomean_cpc, 4)                                         AS segment_geomean_cpc,
  ROUND(seg_geomean_clicks_per_day, 4)                              AS segment_geomean_clicks_per_day,
  -- 6.3: say when the fit cannot be trusted, rather than publishing a number that looks like one
  CASE
    WHEN n_points < (SELECT min_points FROM k)      THEN 'INSUFFICIENT_DATA'
    WHEN b_click_elasticity IS NULL                 THEN 'NO_PRICE_VARIATION'
    WHEN b_click_elasticity <= 0                    THEN 'ELASTICITY_NOT_POSITIVE — paying more did not buy more clicks in this segment; treat the curve as unusable and say so'
    WHEN b_click_elasticity > 3.0                   THEN 'ELASTICITY_IMPLAUSIBLY_HIGH — almost certainly confounded by budget or season, not price'
    WHEN r_squared < 0.10                           THEN 'WEAK_FIT'
    ELSE NULL
  END                                                               AS fit_warning,
  (n_points >= (SELECT min_points FROM k)
   AND b_click_elasticity IS NOT NULL
   AND b_click_elasticity > 0 AND b_click_elasticity <= 3.0)        AS usable
FROM fit;
```

- [ ] **Step 2: Deploy and read the fits**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_CLICK_RESPONSE_CURVE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT usable, COALESCE(fit_warning, '(none)') warning, COUNT(*) segments,
          ROUND(AVG(click_elasticity), 3) avg_elasticity, ROUND(AVG(r_squared), 3) avg_r2
   FROM \`onyga-482313.OI.V_CLICK_RESPONSE_CURVE\` GROUP BY 1,2 ORDER BY segments DESC"
```

**Read the result honestly.** If most segments are `INSUFFICIENT_DATA` or carry a warning, that is the finding, and the correct response is to publish the curve with `usable = FALSE` and **leave `ceiling_basis` at `AVERAGE`** rather than flipping it on a fit nobody should trust. Record what you measure in the doctrine's §10 table either way.

- [ ] **Step 3: Register and commit**

Insert `V_CLICK_RESPONSE_CURVE` in `config.yaml` under `views:` **immediately after the
`V_KEYWORD_GUARD` entry** — never appended at the end of the file — describing it as the per-segment
click response curve read by `SP_SNAPSHOT_KEYWORD_STATE` for the marginal ceiling, and noting that
`n_points`, `r_squared` and `fit_warning` are published on every row so a consumer can refuse a fit
made on too little. `FN_MATCH_WIDTH` was registered under `functions:` in Step 0. Verify with the
`config.yaml` duplicate check in the plan header, then:

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/functions/FN_MATCH_WIDTH.sql \
        scripts/bigquery/views/V_CLICK_RESPONSE_CURVE.sql config.yaml
git commit -m "feat(catalog): V_CLICK_RESPONSE_CURVE — how many clicks a price buys, per segment

The input violation 17 never had. Fitted per family x match width x placement,
never per keyword, and every row carries n_points, r_squared and a fit warning so
a consumer can refuse a curve fitted on too little."
```

---

### Task 10.3 (violations 3 + 17): the marginal ceiling, and the quantity answer

**Files:**
- Modify: `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql` (`ceiling_cpc`, `ceiling_basis`, and three new columns)
- Modify: `scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql`
- Re-deploy: `scripts/bigquery/views/V_KEYWORD_STATE.sql`

- [ ] **Step 1: Join the curve and derive the marginal ceiling**

Add the CTE:

```sql
  -- 2026-08-25 (violations 3 and 17): the response curve, per segment. Doctrine 2: ceiling_cpc is
  -- the worth of the NEXT click, not the average one — as a bid rises it wins auctions it
  -- previously lost, later placements and weaker intent, so the marginal click is normally worth
  -- LESS than the average and pricing to the average systematically overpays at the margin.
  crv AS (
    SELECT family, match_width, placement, click_elasticity, segment_cvr, segment_gp_per_order,
           segment_geomean_cpc, segment_geomean_clicks_per_day, usable, fit_warning
    FROM `onyga-482313.OI.V_CLICK_RESPONSE_CURVE`
    -- placement is not carried at keyword grain anywhere in the warehouse (violation 18), so the
    -- keyword-level read pools the placements of its own segment. Phase 13 replaces this pooling
    -- with a real vehicle dimension; until then the pooling is stated rather than hidden.
    WHERE placement = 'UNKNOWN' OR placement IS NOT NULL
  ),
  crv_seg AS (
    SELECT family, match_width,
           -- click-weighted across placements, because that is the mix the subject actually bought
           SUM(click_elasticity * segment_geomean_clicks_per_day)
             / NULLIF(SUM(segment_geomean_clicks_per_day), 0)          AS click_elasticity,
           SUM(segment_cvr * segment_geomean_clicks_per_day)
             / NULLIF(SUM(segment_geomean_clicks_per_day), 0)          AS segment_cvr,
           AVG(segment_gp_per_order)                                   AS segment_gp_per_order,
           -- THE TWO ANCHOR POINTS OF THE CURVE, AND THEY MUST SURVIVE THIS GROUP BY.
           -- clicks_per_day(p) = geomean_clicks_per_day * (p / geomean_cpc)^b is evaluated at two
           -- prices in Step 2 and again in Task 11.4; without both anchors here every one of those
           -- expressions fails with "Unrecognized name". The CPC anchor is click-weighted like the
           -- elasticity, because it must describe the same mix; the clicks anchor is a SUM, because
           -- the placements' volumes ADD — the subject buys all of them.
           SUM(segment_geomean_cpc * segment_geomean_clicks_per_day)
             / NULLIF(SUM(segment_geomean_clicks_per_day), 0)          AS segment_geomean_cpc,
           SUM(segment_geomean_clicks_per_day)                         AS segment_geomean_clicks_per_day,
           LOGICAL_AND(usable)                                         AS usable,
           STRING_AGG(DISTINCT fit_warning, '; ')                      AS fit_warning
    FROM crv GROUP BY 1, 2
  ),
```

- [ ] **Step 2: Replace the ceiling expression**

The Phase 8 contract published `s.affordable_cpc AS ceiling_cpc` and `'AVERAGE' AS ceiling_basis`. Replace both with:

```sql
    -- ── THE MARGINAL CEILING (doctrine 2, 2.5) ────────────────────────────────────────────────
    -- The average click's worth is gp_per_click / bar — that is what affordable_cpc has always been.
    -- The MARGINAL click's worth is lower, and by how much is exactly the curve's job.
    --
    -- THE DERIVATION, IN FULL, BECAUSE THIS ONE EXPRESSION SETS EVERY PRICE IN THE ACCOUNT ONCE
    -- ceiling_basis FLIPS TO MARGINAL. Write n(p) for clicks bought per day at price p. The fit says
    --     n(p) = A * p^b,        b > 0, and typically b < 1 (diminishing returns)
    -- Total SPEND at price p is p * n(p) = A * p^(b+1). Total gross profit is g * n(p) = g * A * p^b,
    -- where g is gross profit per click, which the fit treats as a property of the segment and not
    -- of the price. What we want is the gross profit of the LAST click bought at price p — that is,
    -- d(total gross profit)/d(spend), the return on the marginal dollar:
    --     d(GP)/dp     = g * A * b * p^(b-1)
    --     d(spend)/dp  = A * (b+1) * p^b
    -- Dividing gives the marginal gross profit per marginal DOLLAR, and multiplying by p gives it
    -- per marginal CLICK:
    --     marginal_gp_per_click = g * b / (b + 1) * ... — and this is where the exact algebra stops
    -- being worth its precision, because b is fitted with a wide interval and g is a segment average.
    -- SO THE HOUSE TAKES THE SIMPLE, CONSERVATIVE FORM AND SAYS SO:
    --     marginal_gp_per_click = avg_gp_per_click * b,  b clamped to at most 1.0
    -- It has the two properties that matter and no false precision. (a) It is never LARGER than the
    -- average, because b <= 1 after the clamp — so the marginal ceiling can never exceed the average
    -- ceiling and this change can only ever lower a price, never raise one. (b) It shrinks as the
    -- segment's returns diminish faster: a segment where paying 10% more buys only 3% more clicks
    -- (b = 0.3) prices the next click at 30% of the average, and a segment where price barely
    -- diminishes at all (b -> 1) prices it at the average, which is where we started.
    --     ceiling_cpc = marginal_gp_per_click / bar
    -- NOTE THE DIRECTION, and do not "fix" it to 1/b: multiplying by b with b < 1 makes the marginal
    -- SMALLER than the average, which is the whole point. Dividing by b would make it larger.
    --
    -- WHERE THE CURVE IS NOT USABLE THE AVERAGE STANDS AND THE ROW SAYS SO. 6.3: an unusable fit
    -- must not be dressed up as a marginal number. ceiling_basis is the field a consumer reads to
    -- know which it got, and Phase 8 built the contract precisely so this swap changes no consumer.
    CASE
      WHEN cs.usable AND cs.click_elasticity IS NOT NULL
        THEN s.gp_per_click * LEAST(cs.click_elasticity, 1.0) / COALESCE(s.family_bar, 1.0)
      ELSE s.affordable_cpc
    END                                                                 AS ceiling_cpc,
    IF(cs.usable AND cs.click_elasticity IS NOT NULL, 'MARGINAL', 'AVERAGE')
                                                                        AS ceiling_basis,
    cs.fit_warning                                                      AS ceiling_fit_warning,

    -- ── THE QUANTITY ANSWER (violation 17) ────────────────────────────────────────────────────
    -- Doctrine 2.5: "at what volume does the next click stop clearing the bar?" — the allocation
    -- question stated properly, and the thing that separates OVERPAYING from OVER-BUYING.
    -- At the ceiling price, the segment's curve says how many clicks a day this subject would take:
    --   clicks_per_day(p) = geomean_clicks_per_day * (p / geomean_cpc)^b
    -- BOTH COLUMNS ARE EVALUATED AT THE CEILING THIS ROW ACTUALLY PUBLISHES — the marginal one where
    -- the fit is usable, the average one where it is not. Evaluating "clicks at the ceiling" at
    -- s.affordable_cpc while the row's ceiling_cpc is the smaller marginal number would publish two
    -- columns priced at two different prices without telling anyone, and would overstate the volume
    -- at the price the Brain is going to pay. The expression is written out rather than referencing
    -- the ceiling_cpc alias above, because BigQuery does not expose a select-list alias to a sibling
    -- expression in the same SELECT list.
    CASE
      WHEN cs.usable AND cs.click_elasticity IS NOT NULL
       AND cs.segment_geomean_cpc > 0
        THEN cs.segment_geomean_clicks_per_day
             * POW(GREATEST(s.gp_per_click * LEAST(cs.click_elasticity, 1.0)
                            / COALESCE(s.family_bar, 1.0), 0.01) / cs.segment_geomean_cpc,
                   cs.click_elasticity)
      ELSE NULL
    END                                                                 AS clicks_per_day_at_ceiling,
    -- and the same curve read at the BAR PRICE — the AVERAGE ceiling, gp_per_click / bar: what the
    -- subject would take if the average click were priced at exactly break-even against its family
    -- bar. That is the volume beyond which the AVERAGE click no longer clears the bar.
    -- THE TWO COLUMNS ALWAYS DIVERGE ON A USABLE FIT, and that is the point of publishing both.
    -- They differ by exactly LEAST(b, 1.0), the factor the derivation above introduces: b is below
    -- 1 wherever returns diminish at all, so the marginal ceiling is strictly below the bar price
    -- and clicks_per_day_at_ceiling is strictly below clicks_per_day_at_the_bar. The gap between
    -- them IS the over-buying this task exists to stop — the clicks the average price would have
    -- bought whose marginal return does not clear the bar. They coincide only in the degenerate
    -- case b >= 1 (no diminishing returns at all), where the clamp makes the two expressions
    -- identical, and where the fit is not usable and both read the average.
    -- If they ever read equal on a usable fit with b < 1, one of the two expressions has been
    -- edited to reference the other's price; that is the failure to look for.
    CASE
      WHEN cs.usable AND cs.click_elasticity IS NOT NULL
       AND cs.segment_geomean_cpc > 0
        THEN cs.segment_geomean_clicks_per_day
             * POW(GREATEST(s.gp_per_click / COALESCE(s.family_bar, 1.0), 0.01)
                   / cs.segment_geomean_cpc,
                   cs.click_elasticity)
      ELSE NULL
    END                                                                 AS clicks_per_day_at_the_bar,
    cs.click_elasticity                                                 AS segment_click_elasticity,
```

The join is on the family and the same match-width expression the curve itself groups by, so the
two can never disagree. Add it where the final `SELECT` assembles its row:

```sql
  LEFT JOIN crv_seg cs
    ON cs.family = s.family
   AND cs.match_width = `onyga-482313.OI.FN_MATCH_WIDTH`(s.target_text, s.match_type)
```

**The axis is the function, on both sides.** `V_CLICK_RESPONSE_CURVE`'s `seg` CTE calls
`FN_MATCH_WIDTH(a.targeting, a.targeting_type)` and this join calls it on
`(s.target_text, s.match_type)`; there is no `CASE` to keep in sync in either place, which is exactly
why Task 10.2 Step 0 built it. Do **not** replace either call with an inline `CASE` "for readability"
— a divergence here does not fail, it silently misses, and every affected subject falls back to the
average ceiling with no error and no alarm.

Verify the join actually lands before believing the `ceiling_basis` counts in Step 3:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH st AS (
  SELECT family, \`onyga-482313.OI.FN_MATCH_WIDTH\`(target_text, match_type) w, COUNT(*) n
  FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_KEYWORD_STATE\`)
    AND family IS NOT NULL
  GROUP BY 1, 2)
SELECT SUM(IF(c.family IS NULL, st.n, 0)) AS subjects_with_no_curve_segment,
       SUM(st.n)                          AS subjects_with_a_family
FROM st
LEFT JOIN (SELECT DISTINCT family, match_width FROM \`onyga-482313.OI.V_CLICK_RESPONSE_CURVE\`) c
  ON c.family = st.family AND c.match_width = st.w"
```

Expected: `subjects_with_no_curve_segment` is a small number and every row in it is explainable (a
family with too little history to fit anything). A large number here means the axis is diverging
again, and the fix is `FN_MATCH_WIDTH`, never a widening of the join.

- [ ] **Step 3: Add the columns to history, deploy, re-deploy the view, verify**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
ALTER TABLE \`onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY\`
  ADD COLUMN IF NOT EXISTS ceiling_fit_warning       STRING,
  ADD COLUMN IF NOT EXISTS clicks_per_day_at_ceiling FLOAT64,
  ADD COLUMN IF NOT EXISTS clicks_per_day_at_the_bar FLOAT64,
  ADD COLUMN IF NOT EXISTS segment_click_elasticity  FLOAT64"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT ceiling_basis, COUNT(*) n,
       ROUND(AVG(ceiling_cpc), 4) avg_ceiling,
       ROUND(AVG(affordable_cpc), 4) avg_old_average_ceiling,
       ROUND(AVG(clicks_per_day_at_the_bar), 2) avg_clicks_at_the_bar
FROM \`onyga-482313.OI.V_KEYWORD_STATE\` GROUP BY 1"
```

Expected: a `MARGINAL` bucket whose `avg_ceiling` is **below** `avg_old_average_ceiling` — the marginal click is worth less than the average, which is the whole point — and a populated `avg_clicks_at_the_bar`. **No consumer changed**: the book, the Brain and the preflight all read `ceiling_cpc` and none of them knows the basis moved. That is §1.4's narrow interface doing the job it exists for.

- [ ] **Step 4: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql \
        scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql \
        scripts/bigquery/views/V_KEYWORD_STATE.sql
git commit -m "feat(catalog): ceiling_cpc becomes marginal, and the quantity question is answerable

Closes violations 3 and 17 — one curve read at two points, exactly as 2.5 says. The
contract is unchanged, so no consumer moved. Where the fit is unusable the average
stands and ceiling_basis says so."
```

---

### Task 10.4 (violation 13, grading half): `V_PACING_SCORECARD`

**Files:**
- Create: `scripts/bigquery/views/V_PACING_SCORECARD.sql`
- Modify: `config.yaml` (`views:`)

`V_CHANGE_SCORECARD` already publishes the **observed** half per `change_id` — `win_clicks`, `win_cpc`, `prior_clicks`, `prior_cpc` — on a settle-safe gate ([T+1, T+7] readable at T+14; SB [T+1, T+14] at T+21). Its verdict grades the **money** and never whether the bid delivered the clicks or CPC it implied. That gap **is** violation 13.

- [ ] **Step 1: Write the view**

```sql
-- =============================================================================================
-- V_PACING_SCORECARD — did the bid deliver the clicks and the price it implied? (doctrine 6)
--
-- 6: "Pacing's scorecard is the one nobody thinks to build, and it is the only way to know whether
-- 'bid $1.27 to buy decision data' actually buys decision data, or whether the entry anchor is
-- simply a number the house has never checked."
--
-- THE OBSERVED HALF ALREADY EXISTED. V_CHANGE_SCORECARD publishes win_clicks, win_cpc, prior_clicks
-- and prior_cpc per change_id on a settle-safe gate. What it grades is the MONEY — did this change
-- earn — and never whether the bid delivered what it implied. That is violation 13 exactly.
--
-- THE PREDICTED HALF started being recorded on the first day of the gap-closure plan, in
-- FACT_PPC_CHANGE_LOG (predicted_cpc, predicted_clicks_7d, prediction_source, ceiling_at_change)
-- and FACT_ENGINE_PROPOSALS (expected_cpc, expected_clicks, ceiling_at_proposal). Neither can be
-- backfilled, which is why they went first.
--
-- 6.3 APPLIES TO A SCORECARD TOO: both sides are published, never only the error, and a change
-- superseded inside its own window is excluded rather than blamed for someone else's move.
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PACING_SCORECARD` AS
WITH predicted AS (
  SELECT change_id, batch_id, applied_at, action, campaign_id, keyword_id, targeting, match_type,
         campaign_type, old_bid, new_bid,
         predicted_cpc, predicted_clicks_7d, prediction_source, ceiling_at_change, source
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE predicted_cpc IS NOT NULL OR predicted_clicks_7d IS NOT NULL
),
observed AS (
  SELECT change_id, verdict, verdict_reason, graded_through, read_gate_date, win_days,
         win_clicks, win_cpc, win_spend, win_orders, win_gp, win_gp_roas,
         prior_clicks, prior_cpc, prior_available,
         superseded_in_window, n_later_changes
  FROM `onyga-482313.OI.V_CHANGE_SCORECARD`
)
SELECT
  p.change_id,
  p.batch_id,
  DATE(p.applied_at, 'America/Los_Angeles')                          AS change_date,
  p.source,
  p.action,
  p.campaign_id,
  p.keyword_id,
  p.targeting,
  p.match_type,
  p.campaign_type,
  p.old_bid,
  p.new_bid,
  p.ceiling_at_change,
  p.prediction_source,

  -- the gate: a change is readable only once its own settle window has closed
  o.read_gate_date,
  (o.read_gate_date <= CURRENT_DATE('America/Los_Angeles'))          AS readable,
  -- 6.3: a change another change stepped on inside its own window is EXCLUDED, not blamed
  COALESCE(o.superseded_in_window, FALSE)                            AS superseded_in_window,
  o.n_later_changes,

  -- ── PRICE: did the bid buy the cost per click it implied? ─────────────────────────────────
  p.predicted_cpc,
  o.win_cpc                                                          AS actual_cpc,
  ROUND(o.win_cpc - p.predicted_cpc, 4)                              AS cpc_error,
  ROUND(SAFE_DIVIDE(o.win_cpc - p.predicted_cpc, NULLIF(p.predicted_cpc, 0)), 4)
                                                                     AS cpc_error_pct,

  -- ── QUANTITY: did it buy the clicks it implied? ───────────────────────────────────────────
  p.predicted_clicks_7d,
  o.win_clicks                                                       AS actual_clicks,
  ROUND(o.win_clicks - p.predicted_clicks_7d, 2)                     AS clicks_error,
  ROUND(SAFE_DIVIDE(o.win_clicks - p.predicted_clicks_7d,
                    NULLIF(p.predicted_clicks_7d, 0)), 4)            AS clicks_error_pct,

  -- ── THE CEILING: did the price that landed respect the ceiling it was given? ──────────────
  (p.ceiling_at_change IS NOT NULL AND o.win_cpc > p.ceiling_at_change + 0.005)
                                                                     AS cpc_exceeded_its_ceiling,

  -- the money verdict, carried through unchanged so the two readings sit side by side rather than
  -- one replacing the other
  o.verdict                                                          AS money_verdict,
  o.win_spend, o.win_orders, o.win_gp, o.win_gp_roas,
  o.prior_clicks, o.prior_cpc, o.prior_available,

  -- ── THE PACING VERDICT, which is about DELIVERY and not about profit ──────────────────────
  CASE
    WHEN o.read_gate_date > CURRENT_DATE('America/Los_Angeles')      THEN 'TOO_EARLY'
    WHEN COALESCE(o.superseded_in_window, FALSE)                     THEN 'UNREADABLE_SUPERSEDED'
    WHEN p.predicted_cpc IS NULL AND p.predicted_clicks_7d IS NULL   THEN 'NO_PREDICTION_RECORDED'
    WHEN COALESCE(o.win_clicks, 0) = 0                               THEN 'UNBUYABLE — the price bought no clicks at all, and doctrine 1.3 says that is itself the answer, reported back'
    WHEN p.ceiling_at_change IS NOT NULL AND o.win_cpc > p.ceiling_at_change + 0.005
                                                                     THEN 'OVER_CEILING'
    WHEN ABS(SAFE_DIVIDE(o.win_cpc - p.predicted_cpc, NULLIF(p.predicted_cpc, 0))) <= 0.20
     AND ABS(SAFE_DIVIDE(o.win_clicks - p.predicted_clicks_7d,
                         NULLIF(p.predicted_clicks_7d, 0))) <= 0.50  THEN 'DELIVERED'
    WHEN ABS(SAFE_DIVIDE(o.win_cpc - p.predicted_cpc, NULLIF(p.predicted_cpc, 0))) > 0.20
                                                                     THEN 'PRICE_MISSED'
    ELSE 'VOLUME_MISSED'
  END                                                                AS pacing_verdict
FROM predicted p
LEFT JOIN observed o USING (change_id);
```

The tolerances (20% on price, 50% on volume) are **declared constants of this plan**: a bid→CPC model with a published gamma confidence interval of [0.638, 0.872] cannot promise better than roughly a fifth on price, and click volume is the noisier of the two by a wide margin. They are exempt from Standing Rule 0 as declared constants, and they move in this file with the reasoning beside them.

- [ ] **Step 2: Deploy and read the first grades**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_PACING_SCORECARD.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT pacing_verdict, COUNT(*) n,
          ROUND(AVG(cpc_error_pct), 3) avg_cpc_error, ROUND(AVG(clicks_error_pct), 3) avg_clicks_error
   FROM \`onyga-482313.OI.V_PACING_SCORECARD\` GROUP BY 1 ORDER BY n DESC"
```

Expected: a spread across `DELIVERED`, `PRICE_MISSED`, `VOLUME_MISSED` and `TOO_EARLY`. **A large `NO_PREDICTION_RECORDED` bucket means Phase 0's recording is not reaching every emitter** — find which and fix it before reading anything else here.

- [ ] **Step 3: Register and commit**

Insert the entry in `config.yaml` under `views:` **immediately after the `V_CHANGE_SCORECARD`
entry** — never appended at the end of the file — describing it as Pacing's scorecard, that it joins
`FACT_PPC_CHANGE_LOG`'s recorded prediction to `V_CHANGE_SCORECARD`'s observed outcome on that view's
own settle-safe gate, that both sides are published per §6.3, and that its 20%/50% tolerances are
declared constants carried in the file. Verify with the `config.yaml` duplicate check in the plan
header, then:

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_PACING_SCORECARD.sql config.yaml
git commit -m "feat(pacing): V_PACING_SCORECARD — did the bid deliver what it implied

Closes the grading half of violation 13. The observed half already existed in
V_CHANGE_SCORECARD and graded the money; the predicted half has been accruing
since day one of this plan because it cannot be backfilled."
```

---

### Task 10.5: Answer the two house constants the scorecard exists for

**Files:**
- Modify: `architecture/THREE_LAYERS.md` (§6.1 experiment declarations)

§6.1: **declare the question before running it** — which setting, which slice, what outcome decides it, by when — so the result cannot be read after the fact to suit a preference.

- [ ] **Step 1: Declare both questions in the doctrine, before reading any answer**

Add under §6.1:

> **Declared 2026-08-25, to be read no earlier than the dates below.**
>
> **Q1 — the entry anchor.** Is bidding at 1.5x target CPC the right price to buy a verdict?
> *Setting:* the entry anchor multiplier. *Slice:* new `TEST` seats in two disjoint families, one at 1.5x and one at 1.0x — disjoint because §6.2 forbids two live method experiments inside one family. Never the holdout arm. *Outcome:* the share of seats reaching their `clicks_to_verdict` by their `verdict_date`, and the net profit over those seats. *By when:* after 40 seats have closed in each arm.
>
> **Q2 — the $1.00 activation floor.** Does the $1.00 entry floor buy anything? §10 records it as a defect and the Aug-9 post-mortem names it explicitly. *Setting:* the activation floor. *Slice:* new entries in two disjoint families, one at $1.00 and one at the channel floor. *Outcome:* clicks bought per dollar, and the share of entries that produce a settled verdict at all. *By when:* after 40 entries have closed in each arm.

- [ ] **Step 2: Read the answers once, from the scorecard**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT ROUND(old_bid, 2) AS entry_bid_band, COUNT(*) n,
       COUNTIF(pacing_verdict = 'DELIVERED') delivered,
       COUNTIF(pacing_verdict LIKE 'UNBUYABLE%') bought_no_clicks,
       ROUND(AVG(actual_clicks), 2) avg_clicks, ROUND(AVG(actual_cpc), 3) avg_cpc
FROM \`onyga-482313.OI.V_PACING_SCORECARD\`
WHERE readable AND NOT superseded_in_window AND action = 'INCREASE_BID'
  AND old_bid IS NOT NULL
GROUP BY 1 ORDER BY n DESC LIMIT 20"
```

Record what you read **against the declared outcome**, never a different one. If the sample is too thin, say so and leave the question open — that is the honest reading and the reason the declaration comes first.

- [ ] **Step 3: Commit**

```bash
cd /Users/ori/Develop/OI
git add architecture/THREE_LAYERS.md
git commit -m "docs(doctrine): declare the entry-anchor and activation-floor experiments

6.1 requires the question to be declared before it is run, so the result cannot be
read after the fact to suit a preference."
```

---

### Task 10.6 (violation 11, doctrinal): re-base the rank

**Files:**
- Modify: `scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql` (the `rank_score` from Task 6.3)
- Modify: `scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql` C21

§2.4's ordering is **expected profit contribution at the ceiling, discounted by confidence** — and all three terms now exist.

**Carry the three new inputs into `base` first.** `ceiling_basis`, `clicks_per_day_at_the_bar` and
`confidence` all live on `FACT_KEYWORD_STATE` after Phases 7 and 10 and none of them is selected by
`V_PLAN_WINDOW_JUDGMENT` today. Add them beside `ks.gp_per_click` at `:455`; `judged` and `final`
select `*` from their predecessors, so `j.` then resolves. Confirm with
`grep -n "clicks_per_day_at_the_bar" scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql` before
writing Step 1.

- [ ] **Step 1: Replace the interim shortfall with the doctrinal score**

```sql
    -- ── EXPECTED PROFIT CONTRIBUTION AT THE CEILING (doctrine 2.4, 2026-08-25) ────────────────
    -- Phase 6 shipped the gross-profit SHORTFALL as an interim, because 2.4's actual ordering needs
    -- a marginal ceiling (violation 3) and a confidence score (violation 20), and neither existed.
    -- Both do now, so this is the ordering the doctrine asks for:
    --     (expected conversions x margin) - (expected clicks x ceiling CPC), over the window,
    --     the whole thing discounted by confidence.
    -- ORDER BY EXPECTED PROFIT, NEVER BY CVR: 2.4 is explicit that a high-CVR subject with almost no
    -- volume is worth less than a moderate-CVR subject with real volume, and that ranking on
    -- conversion rate alone quietly fills an allowance with keywords too small to matter.
    -- THE DISCOUNT IS WHAT STOPS AN UNKNOWN OUTRANKING A PROVEN ONE ON OPTIMISM ALONE.
    -- A subject with no usable curve falls back to Phase 6's shortfall rather than to zero, so the
    -- queue never silently loses a candidate to a missing model.
    -- THE COST TERM IS MULTIPLIED BY THE BAR, and Task 12.3's header carries the full derivation:
    -- expected conversions x margin is exactly expected clicks x gp_per_click, so writing the cost
    -- term as expected clicks x ceiling_cpc with no bar makes the whole expression
    -- clicks x gp_per_click x (1 - ceiling/gp_per_click), which is negative for any subject whose
    -- ceiling exceeds its gross profit per click — 260 of the 359 subjects carrying both on
    -- 2026-08-24, because this house's bars are deliberately below 1.0. Measured against the bar
    -- instead, and with the MARGINAL ceiling, the score is clicks x gp_per_click x (1 - b) x
    -- confidence, which is never negative and is larger the faster the segment's returns diminish.
    -- gp_per_click is read straight off the row (base carries ks.gp_per_click at :455); do NOT
    -- reconstruct it from settled_ord90 / settled_clk90, because settled_clk90 is not carried by
    -- this view at all.
    COALESCE(
      CASE WHEN j.ceiling_basis = 'MARGINAL' AND j.clicks_per_day_at_the_bar IS NOT NULL
        THEN (
          -- expected conversions x margin, over the window
          j.clicks_per_day_at_the_bar * j.window_days * COALESCE(j.gp_per_click, 0)
          -- minus what those clicks cost at the ceiling, in the currency the bar is written in
          - j.clicks_per_day_at_the_bar * j.window_days
              * COALESCE(j.family_bar, 1.0) * COALESCE(j.ceiling_cpc, 0)
        ) / NULLIF(j.window_days, 0) * COALESCE(j.confidence, 0.0)
      END,
      -- the Phase 6 interim, unchanged, for a subject whose segment has no usable curve
      (j.w_sp / j.window_days)
        * COALESCE(SAFE_DIVIDE(NULLIF(j.family_bar, 0) - COALESCE(j.ret_corrected, 0),
                               NULLIF(j.family_bar, 0)), 0)
    )                                                                    AS rank_score,
    IF(j.ceiling_basis = 'MARGINAL' AND j.clicks_per_day_at_the_bar IS NOT NULL,
       'EXPECTED_PROFIT_AT_CEILING', 'GP_SHORTFALL_INTERIM')             AS rank_basis,
```

- [ ] **Step 2: Re-base C21 again**

Replace C21's assertion with one that pins whichever basis the row declares:

```sql
c21 AS (
  -- 2026-08-25, second re-basing. Phase 6 pinned the gross-profit shortfall; the doctrinal score is
  -- expected profit at the marginal ceiling discounted by confidence (2.4), and a subject whose
  -- segment has no usable curve keeps the interim. rank_basis says which, and this check asserts
  -- that the score matches the basis the row itself declares — so neither can drift silently.
  SELECT 'C21 rank_score matches the basis the row declares (P-7, 2.4)',
         COUNTIF(rank_basis = 'GP_SHORTFALL_INTERIM'
                 AND ABS(rank_score
                         - (w_sp / window_days)
                           * COALESCE(SAFE_DIVIDE(NULLIF(family_bar, 0) - COALESCE(ret_corrected, 0),
                                                  NULLIF(family_bar, 0)), 0)) > 1e-9)
       + COUNTIF(rank_basis = 'EXPECTED_PROFIT_AT_CEILING' AND rank_score IS NULL)
       + COUNTIF(rank_basis NOT IN ('GP_SHORTFALL_INTERIM', 'EXPECTED_PROFIT_AT_CEILING'))
  FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`
),
```

- [ ] **Step 3: Deploy, run, verify**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT rank_basis, COUNT(*) n, COUNTIF(rank_is_degenerate) tied_at_zero
   FROM \`onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT\` WHERE is_candidate GROUP BY 1"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql)"
```

Expected: both bases present, and every acceptance row `PASS`.

- [ ] **Step 4: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql \
        scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql
git commit -m "feat(brain): rank on expected profit at the ceiling against the bar, discounted by confidence

2.4's actual ordering, buildable now that the marginal ceiling and confidence both
exist. A subject with no usable curve keeps Phase 6's shortfall rather than
dropping to zero."
```

---

### Task 10.7: Re-state every excess figure against the marginal ceiling

**Files:**
- Modify: `architecture/THREE_LAYERS.md` §10.1 and §10.4

§10.4 records that *"every 'excess' figure above is computed against an average ceiling and therefore misstates the true overpayment in an unknown direction."* Now it can be stated.

- [ ] **Step 1: Re-measure the three headline excess figures both ways**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH ks AS (
  SELECT * FROM \`onyga-482313.OI.V_KEYWORD_STATE\`
  WHERE settled_clk90 > 0 AND settled_sp90 > 0
)
SELECT ceiling_basis,
       COUNT(*) subjects,
       -- ONE-SIDED, as the baseline computed it: GREATEST(actual - target, 0)
       ROUND(SUM(GREATEST(settled_sp90 - settled_gp90 / NULLIF(family_bar, 0), 0)) / 90, 2)
         AS one_sided_excess_usd_per_day,
       -- THE NET, which 6.3 requires beside it, because any one-sided sum is positive under
       -- ordinary dispersion even in a healthy population — that is what killed the
       -- '\$210/day over bar' claim.
       ROUND(SUM(settled_sp90 - settled_gp90 / NULLIF(family_bar, 0)) / 90, 2)
         AS net_usd_per_day,
       -- and the same against the MARGINAL ceiling rather than the average one
       ROUND(SUM(GREATEST(settled_sp90 - ceiling_cpc * settled_clk90, 0)) / 90, 2)
         AS one_sided_excess_vs_marginal,
       ROUND(SUM(settled_sp90 - ceiling_cpc * settled_clk90) / 90, 2)
         AS net_vs_marginal
FROM ks GROUP BY 1"
```

- [ ] **Step 2: Record the re-statement in the doctrine**

Update §10.1's "umbrella" and "decided, logged, never uploaded" rows to carry **both** the one-sided figure and the net, and both the average-ceiling and marginal-ceiling readings, with the date of the re-measurement. Strike the §10.4 bullet "Marginal versus average value" and replace it with a row in §10.2 recording what the re-statement found — whichever way it fell. The doctrine's own instruction applies: *a doctrine that quietly deleted its wrong answers would teach nothing.*

- [ ] **Step 3: Commit**

```bash
cd /Users/ori/Develop/OI
git add architecture/THREE_LAYERS.md
git commit -m "docs(doctrine): re-state the excess figures against the marginal ceiling

10.4 recorded that every excess figure was computed against an average ceiling and
misstated the overpayment in an unknown direction. It no longer does, and the net
is reported beside every one-sided sum per 6.3."
```

---

### Task 10.8: `V_CATALOG_SCORECARD` — grade the layer that does the valuing

**Files:**
- Create: `scripts/bigquery/views/V_CATALOG_SCORECARD.sql`
- Modify: `config.yaml` (`views:` — insert immediately after the `V_CATALOG_DWELL` entry Task 0.4 added)

**Why this task exists at all, and why here.** Violation 6's own words are *"it keeps no memory … so
the Catalog cannot be graded on its own predictions and §6 is currently impossible to satisfy."*
Phase 0 built the memory (`FACT_KEYWORD_STATE_HISTORY`) and the dwell view, which makes grading
**possible** — and then nothing in this plan ever performed it. The Brain got `V_PLAN_SCORECARD`
(Task 6.10) and Pacing got `V_PACING_SCORECARD` (Task 10.4); the Catalog, the layer whose entire job
is valuing, got neither. That is half of violation 6 left open on its own terms, and it hard-blocks
one other thing: Task 11.3 sets `probation_weight = 0.0` and says in the code that it is raised
*"only after the Catalog scorecard has measured this source predicting better than the incumbent
estimator"* — an instrument that would otherwise not exist, leaving violation 21's demand data on a
probation it could never leave.

It sits here rather than in Phase 0 for the same reason Task 10.1 does: **it is gated on elapsed
time, not effort.** A prediction made on day D can only be graded once day D's window has settled, so
the view is buildable on day one and readable only after `FACT_KEYWORD_STATE_HISTORY` has accrued
enough partitions. Run Task 10.1's readiness gate against the history table before reading anything
here.

- [ ] **Step 1: Write the view**

```sql
-- =============================================================================================
-- V_CATALOG_SCORECARD — was the Catalog's answer right? (doctrine 6, 6.2)
--
-- 6 asks each layer a different question. The Brain's is "did the allocation earn?"
-- (V_PLAN_SCORECARD). Pacing's is "did the bid deliver what it implied?" (V_PACING_SCORECARD).
-- The CATALOG's is the one this view answers: ON DATE D YOU SAID THIS SUBJECT WAS WORTH X AND
-- AFFORDED A CPC OF Y — WAS IT?
--
-- THE PREDICTION IS THE ROW ITSELF. FACT_KEYWORD_STATE_HISTORY records, per subject per day, the
-- state, the ceiling, the confidence and the appointment. Nothing extra had to be recorded; the
-- Catalog's answer IS its prediction, which is why violation 6 was about memory and not about
-- instrumentation.
--
-- THE GRADE IS THE SUBSEQUENT SETTLED WINDOW, and the gate is the same settle-safe one every other
-- scorecard in this warehouse uses: a prediction made on D is readable at D + settle_days_eff + 7,
-- so SP rows grade at D+14 and SB rows at D+21. A row inside its gate reads TOO_EARLY, never a
-- provisional grade — 6.3 forbids a number that looks like an answer and is not one.
--
-- 6.3 IS BINDING HERE TOO: both sides are published on every row (predicted AND realised), never
-- only the error, and never only the sign of the error. A subject whose realised window carries no
-- clicks is UNREADABLE, not wrong: silence is not evidence (doctrine 5).
--
-- THREE GRADES, EACH ANSWERING A DIFFERENT QUESTION THE DOCTRINE ASKS:
--   * ceiling_grade   — did the subject's realised gross profit per click land at or above the
--                       ceiling the Catalog published? An over-published ceiling is the failure
--                       that costs money; an under-published one costs opportunity, and both are
--                       reported, signed.
--   * verdict_grade   — did a subject the Catalog called WORTH go on to clear its bar, and did one
--                       it called NOT_WORTH go on to miss it? This is the only grade that can
--                       falsify a terminal state, which is why doctrine 5 gates those on HIGH
--                       confidence and why confidence_band is carried onto every row here.
--   * appointment_grade — was next_check_date kept? An appointment nobody kept is a promise the
--                       Catalog made and broke, and V_CATALOG_DWELL already measures the overdue
--                       side; this joins it to whether keeping it would have changed anything.
--
-- WHAT IT IS FOR, CONCRETELY: (a) violation 6's grading half; (b) the named instrument for raising
-- V_SUBJECT_MARKET_HEADROOM.probation_weight off 0.0 — join this view to that one on
-- (campaign_id, keyword_id) and compare ceiling_grade where market_coverage = 'COVERED' against
-- where it is not, which is a 6.1 experiment, declared before it is run and never read after the
-- fact to suit a preference; (c) the evidence for or against every constant in the ladder,
-- re-runnable rather than argued.
--
-- IT DOES NOT CARRY market_coverage ITSELF, deliberately: that column reaches
-- FACT_KEYWORD_STATE_HISTORY in Task 11.4, one phase LATER than this view is built, and a view that
-- selected it would not deploy. The experiment joins the two views instead, which is also the
-- honest shape — the market source is on probation and does not belong inside the instrument that
-- judges it.
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CATALOG_SCORECARD` AS
WITH wm AS (
  SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),
-- every answer the Catalog has ever published, one row per subject per day
said AS (
  SELECT
    h.snapshot_date,
    h.campaign_id,
    h.keyword_id,
    h.subject_key,
    h.family,
    h.target_text,
    h.state,
    h.verdict,
    h.confidence,
    h.confidence_band,
    h.family_bar,
    h.gp_per_click                                            AS predicted_gp_per_click,
    h.ceiling_cpc,
    h.ceiling_basis,
    h.current_bid,
    h.next_check_date,
    COALESCE(h.settle_days_eff, IF(h.channel = 'SB', 14, 3))  AS settle_days_eff,
    -- the settle-safe gate: the window opens at D+1 and is readable a full settle period after it
    -- closes, which is the same shape V_CHANGE_SCORECARD uses.
    DATE_ADD(h.snapshot_date,
             INTERVAL COALESCE(h.settle_days_eff, IF(h.channel = 'SB', 14, 3)) + 7 DAY)
                                                              AS read_gate_date
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY` h
),
-- what the subject actually did in the window that followed the answer
did AS (
  SELECT
    sd.snapshot_date,
    sd.campaign_id,
    sd.keyword_id,
    SUM(a.Ads_clicks)                                         AS win_clicks,
    SUM(a.Ads_cost)                                           AS win_spend,
    SUM(a.Ads_orders)                                         AS win_orders,
    SUM(a.GROSS_PROFIT)                                       AS win_gp
  FROM (SELECT DISTINCT snapshot_date, campaign_id, keyword_id, settle_days_eff FROM said) sd
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` a
    ON CAST(a.campaign_id AS STRING) = sd.campaign_id
   AND CAST(a.keyword_id  AS STRING) = sd.keyword_id
   AND a.date >  sd.snapshot_date
   AND a.date <= DATE_ADD(sd.snapshot_date, INTERVAL sd.settle_days_eff DAY)
  GROUP BY 1, 2, 3
)
SELECT
  s.snapshot_date,
  s.campaign_id,
  s.keyword_id,
  s.subject_key,
  s.family,
  s.target_text,
  s.state,
  s.verdict,
  s.confidence,
  s.confidence_band,
  s.ceiling_basis,
  s.read_gate_date,
  (s.read_gate_date <= (SELECT d FROM wm))                    AS readable,

  -- ── BOTH SIDES, ALWAYS (6.3) ────────────────────────────────────────────────────────────────
  s.predicted_gp_per_click,
  SAFE_DIVIDE(d.win_gp, NULLIF(d.win_clicks, 0))              AS realised_gp_per_click,
  s.ceiling_cpc                                               AS predicted_ceiling_cpc,
  SAFE_DIVIDE(d.win_spend, NULLIF(d.win_clicks, 0))           AS realised_cpc,
  s.family_bar,
  SAFE_DIVIDE(d.win_gp, NULLIF(d.win_spend, 0))               AS realised_gp_roas,
  d.win_clicks, d.win_spend, d.win_orders, d.win_gp,

  -- signed, never a one-sided sum. A positive error means the Catalog published a ceiling the
  -- subject did not earn back — the direction that costs money.
  ROUND(s.ceiling_cpc - SAFE_DIVIDE(d.win_gp, NULLIF(d.win_clicks, 0)) / NULLIF(s.family_bar, 0), 4)
                                                              AS ceiling_error,

  CASE
    WHEN s.read_gate_date > (SELECT d FROM wm)                THEN 'TOO_EARLY'
    WHEN COALESCE(d.win_clicks, 0) = 0                        THEN 'UNREADABLE_NO_CLICKS'
    WHEN s.ceiling_cpc IS NULL                                THEN 'NO_CEILING_PUBLISHED'
    WHEN SAFE_DIVIDE(d.win_gp, NULLIF(d.win_clicks, 0)) / NULLIF(s.family_bar, 0)
           >= s.ceiling_cpc                                   THEN 'CEILING_EARNED_BACK'
    ELSE                                                           'CEILING_TOO_HIGH'
  END                                                         AS ceiling_grade,

  CASE
    WHEN s.read_gate_date > (SELECT d FROM wm)                THEN 'TOO_EARLY'
    WHEN COALESCE(d.win_clicks, 0) = 0                        THEN 'UNREADABLE_NO_CLICKS'
    WHEN s.verdict = 'WORTH'
     AND SAFE_DIVIDE(d.win_gp, NULLIF(d.win_spend, 0)) >= s.family_bar
                                                              THEN 'WORTH_CONFIRMED'
    WHEN s.verdict = 'WORTH'                                  THEN 'WORTH_FALSIFIED'
    WHEN s.verdict = 'NOT_WORTH'
     AND SAFE_DIVIDE(d.win_gp, NULLIF(d.win_spend, 0)) <  s.family_bar
                                                              THEN 'NOT_WORTH_CONFIRMED'
    WHEN s.verdict = 'NOT_WORTH'                              THEN 'NOT_WORTH_FALSIFIED'
    ELSE                                                           'NOT_GRADED_UNKNOWN_VERDICT'
  END                                                         AS verdict_grade,

  -- the appointment: was the date the Catalog set actually honoured by a later snapshot?
  s.next_check_date,
  EXISTS (SELECT 1 FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY` h2
          WHERE h2.campaign_id = s.campaign_id AND h2.keyword_id = s.keyword_id
            AND h2.snapshot_date = s.next_check_date)         AS appointment_snapshot_exists,
  CASE
    WHEN s.next_check_date IS NULL                            THEN 'NO_APPOINTMENT'
    WHEN s.next_check_date > (SELECT d FROM wm)               THEN 'NOT_DUE_YET'
    WHEN EXISTS (SELECT 1 FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY` h3
                 WHERE h3.campaign_id = s.campaign_id AND h3.keyword_id = s.keyword_id
                   AND h3.snapshot_date = s.next_check_date
                   AND h3.state != s.state)                   THEN 'KEPT_AND_CHANGED'
    WHEN EXISTS (SELECT 1 FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY` h4
                 WHERE h4.campaign_id = s.campaign_id AND h4.keyword_id = s.keyword_id
                   AND h4.snapshot_date = s.next_check_date)  THEN 'KEPT_AND_UNCHANGED'
    ELSE                                                           'MISSED'
  END                                                         AS appointment_grade
FROM said s
LEFT JOIN did d
  ON d.snapshot_date = s.snapshot_date
 AND d.campaign_id   = s.campaign_id
 AND d.keyword_id    = s.keyword_id;
```

- [ ] **Step 2: Deploy and read the first grades honestly**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_CATALOG_SCORECARD.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT ceiling_grade, verdict_grade, COUNT(*) n,
       ROUND(AVG(ceiling_error), 4) avg_signed_ceiling_error
FROM \`onyga-482313.OI.V_CATALOG_SCORECARD\`
GROUP BY 1, 2 ORDER BY n DESC"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT appointment_grade, COUNT(*) n
FROM \`onyga-482313.OI.V_CATALOG_SCORECARD\` GROUP BY 1 ORDER BY n DESC"
```

**Read this the way Task 10.2 says to read the curve.** If almost everything is `TOO_EARLY`, the
history has not accrued and the honest answer is to say so and come back — not to shorten the gate.
A large `MISSED` bucket is a real finding about the orchestrator, not about the ladder. Record what
you measure in the doctrine's §10 table either way; a scorecard whose first reading is "not enough
data yet" is still a scorecard, and it is the one thing violation 6 asked for.

- [ ] **Step 3: Register and commit**

Insert the entry in `config.yaml` under `views:` **immediately after the `V_CATALOG_DWELL` entry**
Task 0.4 added — never appended at the end of the file — describing it as the Catalog's scorecard,
that it grades the Catalog's own published ceiling, verdict and appointment against the settled
window that followed, that both sides are published per §6.3, and that it is the named instrument
for raising `V_SUBJECT_MARKET_HEADROOM.probation_weight` off `0.0`. Verify with the `config.yaml`
duplicate check in the plan header, then:

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_CATALOG_SCORECARD.sql config.yaml
git commit -m "feat(catalog): V_CATALOG_SCORECARD — the layer that values is finally graded

Closes the grading half of violation 6. Phase 0 made the question answerable;
nothing asked it. Grades the published ceiling, verdict and appointment against
the settled window that followed, on the same settle-safe gate every other
scorecard uses, with both sides published per 6.3. It is also the named instrument
for raising demand data off its 0.0 probation weight."
```

---
## Phase 11 — Demand data enters on probation

**Closes:** the demand half of violation 4, and violation 21.

**One gap wearing two numbers.** Violation 4's §8 text is *"no demand data (SQP) reaches it at all"*; violation 21 is *"market volume is in the warehouse and used by nothing"*. Same absence, same chain.

**Why near the end, honestly.** First, §10.3 already corrected the assumption that made it urgent: measured over twelve weeks, SQP yields roughly **one fundable new keyword per quarter** (149 non-brand queries with no keyword, 150 conversions, 175 clicks, $5,000 of sales, exactly **one** query with two or more conversions), so it is not the candidate generator §2.4 assumed. Second, its real value is as an input to the **curve** — available clicks are a market quantity, not an extrapolation of ours — and to **headroom**, and the curve did not exist until Phase 10.

**State violation 21 more precisely than the doctrine does.** The market columns **are** read today — by `V_ADS_COACH_DATA.sql:1011-1018` and `:1123-1129`, `V_RESEARCH_TERMS`, `V_RESEARCH_RANKED`, `V_SQP_QUERY_WEEKLY`, `V_OOB_SEARCH_TERM` and `tools/build_seasonal_unpause_bulksheet.py`. The defensible claim is that **no object in the Catalog/Brain/Pacing chain reads them**, so no *subject* can be valued on demand available rather than demand captured. Do not repeat "read by nothing"; it is measurably too strong.

**Unblocks:** Phase 12's `rank()` for subjects we already own (headroom, not new candidates); the correct source for Phase 9's re-test volume floor; the ceiling on Phase 10's volume curve.

**Size:** M — 1–1.5 weeks. The join already has a working reference implementation.

---

### Task 11.1: The red measurement, stated precisely

- [ ] **Step 1: Prove the ladder chain reads nothing**

```bash
cd /Users/ori/Develop/OI
for f in scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql \
         scripts/bigquery/views/V_KEYWORD_GUARD.sql \
         scripts/bigquery/views/V_FAMILY_BAR.sql \
         scripts/bigquery/procedures/SP_SNAPSHOT_FAMILY_BAR.sql \
         scripts/bigquery/views/V_BID_FLOOR.sql; do
  printf '%-70s %s\n' "$f" "$(grep -c 'FACT_SEARCH_QUERY' "$f")"
done
```

Expected: `0` on every line — that is violation 21 in its precise form.

- [ ] **Step 2: Show the counter-evidence, so the claim is not overstated**

```bash
cd /Users/ori/Develop/OI
grep -rln "TOTAL_IMPRESSIONS\|search_query_volume\|impression_share_pct" \
  scripts/bigquery/views/ tools/*.py | sort
```

Expected: several files — the coach data view, the research views, the SQP weekly view, the OOB search-term view, and the seasonal unpause book. **The data is in the warehouse and in the research and coach surfaces; it is not in the ladder.**

- [ ] **Step 3: Measure the join's coverage before building on it**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH q AS (SELECT DISTINCT LOWER(TRIM(query_text)) t FROM \`onyga-482313.OI.FACT_SEARCH_QUERY\`
           WHERE week_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)),
ks AS (SELECT LOWER(TRIM(target_text)) t, is_auto, is_pt, settled_sp90
       FROM \`onyga-482313.OI.V_KEYWORD_STATE\`)
SELECT CASE WHEN is_auto THEN 'AUTO' WHEN is_pt THEN 'PT' ELSE 'KEYWORD' END kind,
       COUNT(*) subjects,
       COUNTIF(q.t IS NOT NULL) matched,
       ROUND(100 * SUM(IF(q.t IS NOT NULL, settled_sp90, 0)) / NULLIF(SUM(settled_sp90), 0), 2)
         AS pct_of_settled_spend_matched
FROM ks LEFT JOIN q ON q.t = ks.t GROUP BY 1 ORDER BY subjects DESC"
```

Expected: real keywords match well; auto modes and product targets match **nothing**, correctly — they are not search queries. Measured 2026-08-24: 252 of 838 subjects matched, carrying 57.84% of settled 90-day spend; 232 of 320 real keywords (72.5%); 66 auto modes and 116 product targets matched zero.

- [ ] **Step 4: Record the measurement and commit it**

Every red measurement in this plan is a number the green run is compared against, so it is written
down rather than remembered. Append what you measured — the query, the date, and the count — to the
running record, creating the file on the first task that reaches this step:

```bash
cd /Users/ori/Develop/OI
mkdir -p docs/superpowers/specs
cat >> docs/superpowers/specs/2026-08-25-gap-closure-measurements.md <<'EOF'

## Task 11.1 — measured YYYY-MM-DD

Replace the date above with the date you ran it, and paste below: the query you ran (unchanged from
the task), and its output. Do not summarise the output — the point of this file is that a re-run is
a re-run and not a fresh argument, which is the same reason
docs/superpowers/specs/2026-08-24-three-layers-baseline.md exists.
EOF
git add docs/superpowers/specs/2026-08-25-gap-closure-measurements.md
git commit -m "measure(task 11.1): record the red measurement before the fix

The number the green run is compared against, written down rather than remembered."
```

---

### Task 11.2: `V_SRC_MARKET_VOLUME` — the interface, built the one correct way

**Files:**
- Create: `scripts/bigquery/views/V_SRC_MARKET_VOLUME.sql`
- Modify: `config.yaml` (`views:`)

**Reuse the working reference verbatim** rather than re-deriving it: `tools/build_seasonal_unpause_bulksheet.py:509-535` already `MAX()`es the `TOTAL_*` columns per (query, week) because they repeat identically on every ASIN row of the same query-week, `SUM()`s the lowercase columns because those are ours, and already computes `share_pct`. It even cites §2.8.

- [ ] **Step 1: Write the view**

```sql
-- =============================================================================================
-- V_SRC_MARKET_VOLUME — the market's demand per (query, week), beside our own.
--
-- architecture/THREE_LAYERS.md 2.8: expected_clicks means OUR volume — what a subject has taken for
-- us — and that is the wrong number for two of the questions the doctrine asks. It cannot value a
-- subject the account has never bought, and it cannot say whether a subject we already own is
-- capturing its opportunity or a sliver of it.
--
-- THE ONE CORRECT COLLAPSE, and it is easy to get wrong. FACT_SEARCH_QUERY is grained
-- (query_text, ASIN, Year, Week). The UPPERCASE TOTAL_* columns and search_query_volume are the
-- WHOLE MARKET'S and REPEAT IDENTICALLY on every ASIN row of the same query-week, so they must be
-- MAX()ed; the lowercase impressions / clicks / cart_adds / conversions are OURS and must be
-- SUM()ed. Summing the totals multiplies the market by the number of our ASINs that appeared.
-- This is the collapse tools/build_seasonal_unpause_bulksheet.py already implements, reused rather
-- than re-derived.
--
-- V_SRC_ PREFIX: this is an interface view over a raw source, not an analytics view. It does no
-- judging, joins to no subject and decides nothing.
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_SRC_MARKET_VOLUME` AS
SELECT
  LOWER(TRIM(query_text))                                  AS query_text,
  week_start_date,
  week_end_date,
  Year                                                     AS year,
  Week                                                     AS week,

  -- THE MARKET'S — one value per query-week, repeated on every ASIN row, so MAX
  MAX(TOTAL_IMPRESSIONS)                                   AS market_impressions,
  MAX(TOTAL_CLICKS)                                        AS market_clicks,
  MAX(TOTAL_CART_ADDS)                                     AS market_cart_adds,
  MAX(TOTAL_PURCHASES)                                     AS market_purchases,
  MAX(search_query_volume)                                 AS search_query_volume,
  MAX(total_median_click_price)                            AS market_median_click_price,

  -- OURS — one row per ASIN, so SUM
  SUM(impressions)                                         AS our_impressions,
  SUM(clicks)                                              AS our_clicks,
  SUM(cart_adds)                                           AS our_cart_adds,
  SUM(conversions)                                         AS our_conversions,
  SUM(sales_amount)                                        AS our_sales,
  COUNT(DISTINCT ASIN)                                     AS our_asins_in_this_query,

  -- OUR SHARE, and therefore the HEADROOM (2.8)
  SAFE_DIVIDE(SUM(impressions), NULLIF(MAX(TOTAL_IMPRESSIONS), 0))  AS our_impression_share,
  SAFE_DIVIDE(SUM(clicks), NULLIF(MAX(TOTAL_CLICKS), 0))           AS our_click_share,
  GREATEST(MAX(TOTAL_CLICKS) - SUM(clicks), 0)                     AS headroom_clicks,
  GREATEST(MAX(TOTAL_IMPRESSIONS) - SUM(impressions), 0)           AS headroom_impressions,

  -- 2.8: the query's median click price is a POSITIONING signal, not a cost one, and is worth
  -- keeping distinct from CPC. It says what the market is willing to pay for the ITEM behind the
  -- query, which is a statement about the shopper and not about the auction.
  MAX(asin_median_click_price)                             AS our_median_click_price
FROM `onyga-482313.OI.FACT_SEARCH_QUERY`
WHERE query_text IS NOT NULL AND TRIM(query_text) != ''
GROUP BY 1, 2, 3, 4, 5;
```

- [ ] **Step 2: Deploy and verify the collapse is right**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_SRC_MARKET_VOLUME.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT COUNT(*) query_weeks,
       COUNTIF(our_impressions > market_impressions) OURS_EXCEEDS_MARKET_MUST_BE_ZERO,
       COUNTIF(our_impression_share > 1.0) SHARE_OVER_ONE_MUST_BE_ZERO,
       ROUND(AVG(our_impression_share), 4) avg_share
FROM \`onyga-482313.OI.V_SRC_MARKET_VOLUME\`
WHERE week_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)"
```

Expected: **both `MUST_BE_ZERO` columns read 0.** If either is non-zero, the collapse is wrong — almost certainly a `SUM` where the reference uses `MAX` — and nothing downstream may be built until it is fixed.

- [ ] **Step 3: Register and commit**

Insert the entry in `config.yaml` under `views:` **beside the other `V_SRC_` interface views, in the
`V_SRC_` block** — never appended at the end of the file. If no `V_SRC_` block exists yet, place it
in alphabetical position among its neighbours and say so in the commit message. The description says
it is the one interface onto `FACT_SEARCH_QUERY`'s market columns, that the market totals are `MAX`ed
and our own figures `SUM`med because the totals repeat on every ASIN row of the same query-week, and
that nothing else in the warehouse may read those columns directly. Verify with the `config.yaml`
duplicate check in the plan header, then:

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_SRC_MARKET_VOLUME.sql config.yaml
git commit -m "feat(catalog): V_SRC_MARKET_VOLUME — the market's demand per query-week

MAX the market totals, SUM ours: the totals repeat on every ASIN row of the same
query-week. Reused from the working reference in build_seasonal_unpause_bulksheet."
```

---

### Task 11.3: `V_SUBJECT_MARKET_HEADROOM` — join to subjects, on probation

**Files:**
- Create: `scripts/bigquery/views/V_SUBJECT_MARKET_HEADROOM.sql`
- Modify: `config.yaml` (`views:`)

- [ ] **Step 1: Write the view**

```sql
-- =============================================================================================
-- V_SUBJECT_MARKET_HEADROOM — market volume, our share and the headroom, per Catalog subject.
--
-- architecture/THREE_LAYERS.md 2.8: market volume "turns a dormant subject's silence into a
-- measurable question — a query the market buys weekly, on which we hold a fraction of a percent of
-- impressions, is not evidence that the subject is dead."
--
-- THE JOIN KEY IS THE ONLY ONE AVAILABLE, and it is an estimate, not a mapping.
-- FACT_SEARCH_QUERY is grained (query_text, ASIN, Year, Week) and FACT_KEYWORD_STATE has NO ASIN
-- COLUMN AT ALL, so the only join is LOWER(TRIM(query_text)) = LOWER(TRIM(target_text)).
-- Measured 2026-08-24: 252 of 838 subjects match, carrying 57.84% of settled 90-day spend; 232 of
-- 320 real keywords (72.5%). AUTO MODES AND PRODUCT TARGETS MATCH NOTHING BY CONSTRUCTION — they
-- are not search queries — and they publish NO_MARKET_DATA, never zero. A zero would read as "the
-- market does not want this", which is a different and false statement.
--
-- ── PROBATION IS ENFORCED IN CODE, NOT IN PROSE (2.3) ────────────────────────────────────────
-- "A new evidence source arrives weighted near zero, makes forecasts alongside the existing
-- estimator, is scored against outcomes like any other Catalog prediction, and its weight rises or
-- falls with its measured accuracy. Trust is a measurement, never an assumption."
-- The HARD LIMIT, and it is the reason this view publishes no verdict of its own:
--   MARKET VOLUME MAY SIZE AN OPPORTUNITY AND INFORM THE CURVE.
--   IT MAY NEVER BY ITSELF MOVE A VERDICT FROM UNKNOWN TO WORTH.
-- Spending money still requires evidence the account itself produced. Every consumer of this view
-- inherits that limit, and the Catalog's own verdict CASE does not read a single column from here.
--
-- ── THE FOUR NAMEABLE GROUNDS, ON THE ROW RATHER THAN AS A DISPOSITION (2.3) ─────────────────
-- Each is a thing to measure rather than a reason to avoid the source, so each is published:
--   join_is_an_estimate      one broad keyword matches many queries and one query is matched by
--                            many keywords, so any query-to-subject attribution is an estimate
--   totals_are_market_wide   the impressions, clicks and purchases are the whole query's, across
--                            all sellers; our share is a separate and smaller number
--   data_is_weekly           it cannot answer a 3-day window directly
--   coverage_is_partial      known to be so, and the row says whether THIS subject is covered
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_SUBJECT_MARKET_HEADROOM` AS
WITH wm AS (
  SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),
ks AS (
  SELECT campaign_id, keyword_id, subject_key, target_text, match_type, is_auto, is_pt, family,
         settled_clk90, settled_sp90, expected_clicks
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
),
-- the market's last 13 complete weeks for each query, which is a quarter and is the shortest span
-- that is not dominated by one week's noise
mkt AS (
  SELECT query_text,
         SUM(market_impressions)               AS market_impressions_13w,
         SUM(market_clicks)                    AS market_clicks_13w,
         SUM(market_purchases)                 AS market_purchases_13w,
         AVG(search_query_volume)              AS avg_weekly_search_volume,
         SUM(our_impressions)                  AS our_impressions_13w,
         SUM(our_clicks)                       AS our_clicks_13w,
         SUM(headroom_clicks)                  AS headroom_clicks_13w,
         AVG(market_median_click_price)        AS market_median_click_price,
         COUNT(*)                              AS weeks_covered
  FROM `onyga-482313.OI.V_SRC_MARKET_VOLUME`, wm
  WHERE week_end_date <= wm.d
    AND week_start_date >= DATE_SUB(wm.d, INTERVAL 91 DAY)
  GROUP BY 1
)
SELECT
  ks.campaign_id,
  ks.keyword_id,
  ks.subject_key,
  ks.target_text,
  ks.family,

  -- coverage, said out loud rather than implied by a NULL
  CASE
    WHEN ks.is_auto THEN 'NO_MARKET_DATA — an auto-targeting mode is a container, not a search query (2.1)'
    WHEN ks.is_pt   THEN 'NO_MARKET_DATA — a product target is a competitor ASIN, not a search query (2.1)'
    WHEN m.query_text IS NULL THEN 'NO_MARKET_DATA — this phrase does not appear in the search-query report'
    ELSE 'COVERED'
  END                                                              AS market_coverage,

  m.avg_weekly_search_volume,
  m.market_impressions_13w,
  m.market_clicks_13w,
  m.market_purchases_13w,
  m.our_impressions_13w,
  m.our_clicks_13w,
  SAFE_DIVIDE(m.our_impressions_13w, NULLIF(m.market_impressions_13w, 0)) AS our_impression_share,
  SAFE_DIVIDE(m.our_clicks_13w, NULLIF(m.market_clicks_13w, 0))          AS our_click_share,
  m.headroom_clicks_13w,
  -- the ceiling on Phase 10's volume curve: available clicks are a MARKET quantity, not an
  -- extrapolation of ours (2.8)
  SAFE_DIVIDE(m.market_clicks_13w, 91.0)                           AS market_clicks_per_day,
  m.market_median_click_price,
  m.weeks_covered,

  -- ── THE FOUR GROUNDS (2.3), on the row ────────────────────────────────────────────────────
  TRUE                                                             AS join_is_an_estimate,
  TRUE                                                             AS totals_are_market_wide,
  TRUE                                                             AS data_is_weekly,
  (m.query_text IS NULL OR COALESCE(m.weeks_covered, 0) < 13)      AS coverage_is_partial,

  -- ── THE PROBATION WEIGHT (2.3), which starts near zero and is raised only by measurement ──
  -- A DECLARED CONSTANT, and deliberately not a free parameter: 0.0 means this source informs
  -- sizing and the curve and contributes NOTHING to any valuation. It is raised only after
  -- V_CATALOG_SCORECARD (built in Task 10.8, and named here so this is a reference and not a wish)
  -- has measured this source predicting better than the incumbent estimator — specifically, its
  -- ceiling_grade, joined to this view on (campaign_id, keyword_id), where market_coverage =
  -- 'COVERED' against where it is not, over enough settled windows to mean something. That is a 6.1 experiment and not an edit, and NO TASK IN THE
  -- GAP-CLOSURE PLAN RAISES THIS WEIGHT: the plan builds the instrument and leaves the raise to a
  -- declared experiment whose result Ori reads.
  0.0                                                              AS probation_weight,
  'market volume may size an opportunity and inform the response curve; it may never by itself move a verdict from UNKNOWN to WORTH (2.3)'
                                                                   AS probation_note
FROM ks
LEFT JOIN mkt m ON m.query_text = LOWER(TRIM(ks.target_text))
                AND NOT ks.is_auto AND NOT ks.is_pt;
```

- [ ] **Step 2: Deploy and read the coverage**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_SUBJECT_MARKET_HEADROOM.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT market_coverage, COUNT(*) subjects,
       ROUND(AVG(our_impression_share), 4) avg_share,
       ROUND(SUM(headroom_clicks_13w), 0) headroom_clicks
FROM \`onyga-482313.OI.V_SUBJECT_MARKET_HEADROOM\` GROUP BY 1 ORDER BY subjects DESC"
```

Expected: a `COVERED` bucket at roughly the measured match rate, and three distinct `NO_MARKET_DATA` reasons — **never a zero share standing in for an absent one**.

- [ ] **Step 3: Register and commit**

Insert the entry in `config.yaml` under `views:` **immediately after the `V_SRC_MARKET_VOLUME` entry**
added in Task 11.2 — never appended at the end of the file — describing it as market volume, our
share and the headroom per Catalog subject; that the join key is `LOWER(TRIM(query_text))` against
`LOWER(TRIM(target_text))` and is an estimate rather than a mapping; that auto modes and product
targets publish `NO_MARKET_DATA` and never zero; and that `probation_weight` is a declared constant
at `0.0` raised only by `V_CATALOG_SCORECARD` (§2.3). Verify with the `config.yaml` duplicate check
in the plan header, then:

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_SUBJECT_MARKET_HEADROOM.sql config.yaml
git commit -m "feat(catalog): market headroom per subject, on probation

Closes violations 4 (demand half) and 21. The four grounds are on the row rather
than in a disposition, the probation weight is 0.0 in code and not in prose, and
auto modes and product targets publish NO_MARKET_DATA rather than zero."
```

---

### Task 11.4: Carry headroom onto the subject, and enforce the hard limit

**Files:**
- Modify: `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql`
- Modify: `scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql` (one new check)
- Re-deploy: `scripts/bigquery/views/V_KEYWORD_STATE.sql`

- [ ] **Step 1: Join the headroom and publish it beside our own volume**

Add the CTE and the published columns:

```sql
  -- 2026-08-25 (violations 4 and 21): market volume beside our own. ON PROBATION (2.3) — it sizes
  -- an opportunity and feeds the curve, and it touches NO verdict arm above. The verdict CASE reads
  -- not one column from here, deliberately and checkably (acceptance K17).
  mh AS (
    SELECT campaign_id AS cid, keyword_id AS kid,
           market_coverage, avg_weekly_search_volume, our_impression_share, our_click_share,
           headroom_clicks_13w, market_clicks_per_day, market_median_click_price,
           coverage_is_partial, probation_weight
    FROM `onyga-482313.OI.V_SUBJECT_MARKET_HEADROOM`
  ),
```

with the join added where the final `SELECT` assembles its row, beside the `crv_seg` join Task 10.3
added. **The final `SELECT` reads `FROM fin3 s`, whose keys are `campaign_id` / `keyword_id`; the
`mh` CTE does the renaming, so the predicate is id-to-id:**

```sql
  LEFT JOIN mh ON mh.cid = s.campaign_id AND mh.kid = s.keyword_id
```

`V_SUBJECT_MARKET_HEADROOM` is one row per subject by construction, but a fan-out here multiplies the
ladder itself, so prove it rather than assume it:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT COUNT(*) rows_, COUNT(DISTINCT CONCAT(campaign_id,'|',keyword_id)) pairs
FROM \`onyga-482313.OI.V_SUBJECT_MARKET_HEADROOM\`"
```

Expected: `rows_ = pairs`.

Then, in the final `SELECT`, immediately after `expected_clicks_source`:

```sql
    -- 2.8: our volume, the market's volume, and the headroom between them. expected_clicks stays
    -- OURS — this does not replace it, it sits beside it, which is the whole of 2.8's argument.
    mh.market_coverage,
    mh.avg_weekly_search_volume                                       AS market_weekly_search_volume,
    mh.market_clicks_per_day                                          AS market_clicks_per_day,
    mh.our_impression_share                                           AS market_our_impression_share,
    mh.headroom_clicks_13w                                            AS market_headroom_clicks_13w,
    -- a positioning signal, NOT a cost one (2.8) — what the market pays for the item behind the
    -- query, which says something about the shopper and nothing about the auction
    mh.market_median_click_price,
    COALESCE(mh.probation_weight, 0.0)                                AS market_probation_weight,
```

- [ ] **Step 2: Assert the hard limit rather than trusting it**

Append to the acceptance suite and add to the UNION:

```sql
,
-- K17 THE PROBATION LIMIT, ENFORCED (2.3). "Market volume may size an opportunity and inform a
-- curve; it may not by itself move a verdict to WORTH. Spending money still requires evidence the
-- account itself produced." A subject with market data and NO settled record of its own must never
-- read WORTH — that is the failure mode the probation exists to prevent, and it is checkable.
k16 AS (
  SELECT 'K17 market volume never moves a verdict to WORTH on its own (2.3)',
         COUNTIF(verdict = 'WORTH'
                 AND COALESCE(settled_clk90, 0) = 0
                 AND market_coverage = 'COVERED')
       + COUNTIF(market_probation_weight != 0.0)
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
)
```

- [ ] **Step 3: Add the columns to history, deploy the chain, run every suite**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
ALTER TABLE \`onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY\`
  ADD COLUMN IF NOT EXISTS market_coverage              STRING,
  ADD COLUMN IF NOT EXISTS market_weekly_search_volume  FLOAT64,
  ADD COLUMN IF NOT EXISTS market_clicks_per_day        FLOAT64,
  ADD COLUMN IF NOT EXISTS market_our_impression_share  FLOAT64,
  ADD COLUMN IF NOT EXISTS market_headroom_clicks_13w   INT64,
  ADD COLUMN IF NOT EXISTS market_median_click_price    FLOAT64,
  ADD COLUMN IF NOT EXISTS market_probation_weight      FLOAT64"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql)"
```

Expected: eighteen rows, all `PASS`, K17 among them.

- [ ] **Step 4: Feed the headroom into the curve as the ceiling on available clicks**

The curve extrapolates clicks from our own history and can therefore predict more clicks than the market has. Replace **both** quantity expressions Task 10.3 added to `SP_SNAPSHOT_KEYWORD_STATE.sql` with the clamped versions below.

**Both replacements keep Task 10.3's corrected prices** — `clicks_per_day_at_ceiling` is evaluated at
the MARGINAL ceiling (the price the row publishes), not at `s.affordable_cpc`. If the expressions
below do not match what is in the procedure, Task 10.3 was applied from an older revision of this
plan; fix that first.

`clicks_per_day_at_ceiling` becomes:

```sql
    -- 2.8: available clicks are a MARKET quantity, not an extrapolation of ours. Where the market is
    -- known it is the ceiling; where it is not — auto modes, product targets, phrases the
    -- search-query report does not carry — the curve stands alone and market_coverage on the row
    -- says which, so a clamped number and an unclamped one are never confused.
    -- The 1e18 fallback is a no-op ceiling, not a magic number: it is larger than any click count
    -- this account can produce, so LEAST() simply returns the curve where no market figure exists.
    CASE
      WHEN cs.usable AND cs.click_elasticity IS NOT NULL
       AND cs.segment_geomean_cpc > 0
        THEN LEAST(
               cs.segment_geomean_clicks_per_day
                 * POW(GREATEST(s.gp_per_click * LEAST(cs.click_elasticity, 1.0)
                                / COALESCE(s.family_bar, 1.0), 0.01) / cs.segment_geomean_cpc,
                       cs.click_elasticity),
               COALESCE(mh.market_clicks_per_day, 1e18))
      ELSE NULL
    END                                                                 AS clicks_per_day_at_ceiling,
```

and `clicks_per_day_at_the_bar` becomes:

```sql
    CASE
      WHEN cs.usable AND cs.click_elasticity IS NOT NULL
       AND cs.segment_geomean_cpc > 0
        THEN LEAST(
               cs.segment_geomean_clicks_per_day
                 * POW(GREATEST(s.gp_per_click / COALESCE(s.family_bar, 1.0), 0.01)
                       / cs.segment_geomean_cpc,
                       cs.click_elasticity),
               COALESCE(mh.market_clicks_per_day, 1e18))
      ELSE NULL
    END                                                                 AS clicks_per_day_at_the_bar,
```

Then re-deploy the procedure, call it, re-deploy `V_KEYWORD_STATE.sql` in the same step, and re-run the suite:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT market_coverage, COUNT(*) n,
       COUNTIF(clicks_per_day_at_the_bar > market_clicks_per_day + 0.0001) AS above_the_market_must_be_zero
FROM \`onyga-482313.OI.V_KEYWORD_STATE\`
WHERE clicks_per_day_at_the_bar IS NOT NULL GROUP BY 1"
```

Expected: `above_the_market_must_be_zero` reads 0 on every `COVERED` row.

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql \
        scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql \
        scripts/bigquery/views/V_KEYWORD_STATE.sql \
        scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql
git commit -m "feat(catalog): headroom on the subject, and the probation limit asserted

The Catalog can now say what a subject is NOT capturing, the curve is clamped by
the market rather than extrapolating past it, and K17 checks in SQL that demand
data never moves a verdict to WORTH on its own."
```

---

### Task 11.5: Re-base Phase 9's volume floor on the correct source

**Files:**
- Modify: `scripts/bigquery/views/V_CATALOG_IMPROVE.sql` (the `retest_volume_floor` arm)

Phase 9 seeded the floor against **our own impressions** because the correct source did not exist. It does now.

- [ ] **Step 1: Re-base the constant and its note**

Replace the `retest_volume_floor` block in `V_CATALOG_IMPROVE.sql`'s `k` CTE with:

```sql
-- ── ORI'S OPEN RULING: THE VOLUME FLOOR, NOW ON THE CORRECT SOURCE (6.4, 2.9) ─────────────────
-- 2.9: "a term nobody searches is never worth re-testing." The floor was seeded against OUR OWN
-- impressions in Phase 9 because no Catalog object read market volume; V_SRC_MARKET_VOLUME now
-- exists, so the floor is re-based on what 2.9 actually means — the MARKET'S weekly search volume
-- for the query, which is a statement about demand rather than about our own past bidding.
-- STILL ORI'S RULING. The number below is a seed, not an answer, and the 6.1 experiment declared in
-- Phase 9 is unchanged except for its source: retest_market_volume_weekly tested at 200 against 50
-- and 1000, on disjoint families, never on the holdout arm.
200 AS retest_market_volume_weekly,
```

and change the `REMOVE_NEGATE` arm's ground-2 branch to read `V_SUBJECT_MARKET_HEADROOM.avg_weekly_search_volume` for the term, publishing `market_volume_weekly` and `our_share_pct` on the row — the two columns Phase 9 deliberately left `NULL`.

- [ ] **Step 2: Deploy, verify both columns are now populated, commit**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_CATALOG_IMPROVE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT suggestion, COUNT(*) n, COUNTIF(market_volume_weekly IS NOT NULL) with_market_volume
   FROM \`onyga-482313.OI.V_CATALOG_IMPROVE\` GROUP BY 1"
git add scripts/bigquery/views/V_CATALOG_IMPROVE.sql
git commit -m "feat(catalog): the negate re-test floor reads market volume, not our impressions

2.9 means the market's demand for the query, and until now the Catalog could not
see it. Still Ori's open ruling; only the source is corrected."
```

---

## Phase 12 — `rank()`, and the Brain becomes proactive

**Closes:** violation 5 (the Catalog cannot propose candidates).

**Why last but one.** §2.4's ranking is *expected profit contribution at the ceiling discounted by confidence*, and every one of those three terms was built by an earlier phase: the ceiling in Phase 10, confidence in Phase 7, the volume in Phase 11. Built earlier it would have been **CVR ranking wearing a better name**, which §2.4 explicitly forbids — a high-CVR subject with almost no volume is worth less than a moderate-CVR one with real volume, and ranking on CVR alone quietly fills an allowance with keywords too small to matter.

**Its source of new candidates is settled by measurement, not assumption.** §10.3 corrected §2.4's premise, so `rank()` v1 sources from the **harvest gap** — 130 proven converting search terms with no keyword anywhere in the account, 488 orders, $56.10/day, CVR 6.49% against an account 3.97% — and **not** from SQP, which proposes about one fundable keyword per quarter.

**Size:** M–L — 1.5–2 weeks.

---

### Task 12.1: The red measurement

- [ ] **Step 1: There is no rank surface, and the account can only grow by accident**

```bash
cd /Users/ori/Develop/OI
bq show onyga-482313:OI.V_CATALOG_RANK 2>&1 | head -2
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT COUNT(*) subjects_the_brain_can_judge
FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
WHERE as_of = (SELECT MAX(as_of) FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`) AND is_live_plan"
```

Expected: `Not found` and a count equal to the subjects that **already exist and already spend**.

- [ ] **Step 2: Size the harvest gap, which is where v1 sources from**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
WITH wm AS (SELECT LEAST(MAX(date), \`onyga-482313.OI.FN_ADS_ANCHOR_CAP\`()) d
            FROM \`onyga-482313.OI.FACT_AMAZON_ADS\`),
terms AS (
  SELECT LOWER(TRIM(a.search_term)) term,
         SUM(a.Ads_clicks) clicks, SUM(a.Ads_orders) orders,
         SUM(a.Ads_cost) spend, SUM(a.GROSS_PROFIT) gp
  FROM \`onyga-482313.OI.FACT_AMAZON_ADS\` a, wm w
  WHERE a.search_term IS NOT NULL
    AND a.date BETWEEN DATE_SUB(w.d, INTERVAL 92 DAY) AND DATE_SUB(w.d, INTERVAL 3 DAY)
  GROUP BY 1),
kw AS (SELECT DISTINCT LOWER(TRIM(keyword_text)) t FROM \`onyga-482313.OI.DIM_KEYWORD\`
       WHERE is_current)
SELECT COUNT(*) harvest_terms, SUM(t.orders) orders, ROUND(SUM(t.spend)/90, 2) usd_per_day,
       ROUND(SAFE_DIVIDE(SUM(t.orders), SUM(t.clicks)) * 100, 2) cvr_pct
FROM terms t LEFT JOIN kw ON kw.t = t.term
WHERE kw.t IS NULL AND t.orders >= 2"
```

Expected: a real population with a CVR above the account's. Measured 2026-08-24: 130 terms, 488 orders, $56.10/day, 6.49% against an account 3.97%. **§10.1 rates this finding MEDIUM and survivorship-selected** — a term that converted is over-represented among terms that were allowed to keep spending — which is why a harvest candidate enters as a question and never as a funded assumption.

- [ ] **Step 3: Record the measurement and commit it**

Every red measurement in this plan is a number the green run is compared against, so it is written
down rather than remembered. Append what you measured — the query, the date, and the count — to the
running record, creating the file on the first task that reaches this step:

```bash
cd /Users/ori/Develop/OI
mkdir -p docs/superpowers/specs
cat >> docs/superpowers/specs/2026-08-25-gap-closure-measurements.md <<'EOF'

## Task 12.1 — measured YYYY-MM-DD

Replace the date above with the date you ran it, and paste below: the query you ran (unchanged from
the task), and its output. Do not summarise the output — the point of this file is that a re-run is
a re-run and not a fresh argument, which is the same reason
docs/superpowers/specs/2026-08-24-three-layers-baseline.md exists.
EOF
git add docs/superpowers/specs/2026-08-25-gap-closure-measurements.md
git commit -m "measure(task 12.1): record the red measurement before the fix

The number the green run is compared against, written down rather than remembered."
```

---

### Task 12.2: `V_HARVEST_CANDIDATE`

**Files:**
- Create: `scripts/bigquery/views/V_HARVEST_CANDIDATE.sql`
- Modify: `config.yaml` (`views:`)

- [ ] **Step 1: Write the view**

```sql
-- =============================================================================================
-- V_HARVEST_CANDIDATE — proven converting search terms with no keyword anywhere in the account.
--
-- architecture/THREE_LAYERS.md 10.1: "search terms converting well with no keyword of their own.
-- Nothing promotes a converting term to a subject." Measured 2026-08-24: 130 terms, 488 orders,
-- $56.10/day, CVR 6.49% against an account 3.97%.
--
-- 10.3 CORRECTED WHY THIS IS THE SOURCE AND NOT SQP. 2.4 assumed demand data would let rank()
-- propose subjects the account has never bought; measured over twelve weeks it yields roughly ONE
-- fundable keyword per quarter. The mechanism in 2.4 stands, its assumed input does not, and the
-- harvest gap is the nearer path to the same goal.
--
-- THE FINDING'S OWN WEAKNESS IS PUBLISHED ON THE ROW. 10.1 rates it MEDIUM and survivorship-
-- selected: a term that converted is over-represented among terms that were allowed to keep
-- spending. So a harvest candidate enters as a QUESTION with a budget and a deadline, never as a
-- funded assumption, and evidence_grade says so to every consumer.
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_HARVEST_CANDIDATE` AS
WITH wm AS (
  SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),
k AS (
  -- DECLARED CONSTANTS:
  --   min_orders 2   one order is noise at any click count; two is the plan's own window floor
  --   min_clicks 10  the guard's min_settled_clk, so a candidate arrives with a record the ladder
  --                  would itself consider judgeable
  SELECT 2 AS min_orders, 10 AS min_clicks
),
terms AS (
  SELECT
    LOWER(TRIM(a.search_term))                              AS term,
    CAST(a.campaign_id AS STRING)                           AS campaign_id,
    ANY_VALUE(a.campaign_name)                              AS campaign_name,
    STRING_AGG(DISTINCT CAST(a.ad_group_id AS STRING), ',') AS ad_group_ids,
    SUM(a.Ads_clicks)                                       AS clicks,
    SUM(a.Ads_cost)                                         AS spend,
    SUM(a.Ads_orders)                                       AS orders,
    SUM(a.Ads_sales)                                        AS sales,
    SUM(a.GROSS_PROFIT)                                     AS gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a, wm w
  WHERE a.search_term IS NOT NULL
    AND a.date BETWEEN DATE_SUB(w.d, INTERVAL 92 DAY) AND DATE_SUB(w.d, INTERVAL 3 DAY)
  GROUP BY 1, 2
),
-- every phrase the account already targets anywhere, so a "new" candidate is genuinely new
existing AS (
  SELECT DISTINCT LOWER(TRIM(keyword_text)) AS t
  FROM `onyga-482313.OI.DIM_KEYWORD` WHERE is_current
),
-- and every phrase the account has deliberately BLOCKED. A term we negated is not a discovery.
blocked AS (
  SELECT DISTINCT LOWER(TRIM(keyword_text)) AS t
  FROM `onyga-482313.OI.DE_NEGATIVE_KEYWORDS`
  WHERE UPPER(COALESCE(state, 'ENABLED')) = 'ENABLED'
),
bar AS (
  SELECT CAST(campaign_id AS STRING) AS cid,
         ANY_VALUE(keyword_bar) AS campaign_bar, ANY_VALUE(family) AS family
  FROM `onyga-482313.OI.T_FAMILY_BAR` GROUP BY 1
)
SELECT
  t.term                                                    AS target_text,
  t.campaign_id,
  t.campaign_name,
  t.ad_group_ids,
  b.family,
  b.campaign_bar,
  t.clicks,
  t.spend,
  t.orders,
  t.gp,
  SAFE_DIVIDE(t.orders, NULLIF(t.clicks, 0))                AS cvr,
  SAFE_DIVIDE(t.gp, NULLIF(t.spend, 0))                     AS gp_roas,
  SAFE_DIVIDE(t.spend, NULLIF(t.clicks, 0))                 AS cpc,
  SAFE_DIVIDE(t.gp, NULLIF(t.orders, 0))                    AS gp_per_order,
  -- the market's view of the same phrase, where it has one (2.8, on probation)
  mh.avg_weekly_search_volume                               AS market_weekly_search_volume,
  mh.market_clicks_per_day,
  -- 10.1 rates this finding MEDIUM and survivorship-selected, and the row says so
  'MEDIUM_SURVIVORSHIP_SELECTED'                            AS evidence_grade,
  'a term that converted is over-represented among terms that were allowed to keep spending; fund this as a question with a deadline, never as a proven subject (10.1)'
                                                            AS evidence_note
FROM terms t
LEFT JOIN existing e ON e.t = t.term
LEFT JOIN blocked  x ON x.t = t.term
LEFT JOIN bar b ON b.cid = t.campaign_id
LEFT JOIN (SELECT query_text,
                  AVG(search_query_volume) AS avg_weekly_search_volume,
                  SAFE_DIVIDE(SUM(market_clicks), 91.0) AS market_clicks_per_day
           FROM `onyga-482313.OI.V_SRC_MARKET_VOLUME`
           WHERE week_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 91 DAY)
           GROUP BY 1) mh ON mh.query_text = t.term
WHERE e.t IS NULL                                     -- no keyword anywhere in the account
  AND x.t IS NULL                                     -- and not something we deliberately blocked
  AND t.orders >= (SELECT min_orders FROM k)
  AND t.clicks >= (SELECT min_clicks FROM k);
```

- [ ] **Step 2: Deploy, verify, register, commit**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_HARVEST_CANDIDATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT COUNT(*) candidates, SUM(orders) orders, ROUND(SUM(spend)/90, 2) usd_per_day,
          ROUND(AVG(cvr) * 100, 2) avg_cvr_pct, COUNTIF(family IS NULL) with_no_family
   FROM \`onyga-482313.OI.V_HARVEST_CANDIDATE\`"
git add scripts/bigquery/views/V_HARVEST_CANDIDATE.sql config.yaml
git commit -m "feat(catalog): V_HARVEST_CANDIDATE — converting terms with no keyword

rank()'s source of new candidates, chosen by measurement: 10.3 found SQP proposes
about one fundable keyword per quarter. Every row carries its own evidence grade."
```

---

### Task 12.3: `V_CATALOG_RANK`

**Files:**
- Create: `scripts/bigquery/views/V_CATALOG_RANK.sql`
- Modify: `config.yaml` (`views:`)

- [ ] **Step 1: Write the view**

```sql
-- =============================================================================================
-- V_CATALOG_RANK — catalog.rank(family, window_from, window_to) (doctrine 2.4).
--
-- "The Brain must be able to come to the Catalog with a family and a window and ask for the RANKED
-- OPPORTUNITIES, not merely to price subjects it already knows about. This is what makes the Brain
-- proactive rather than reactive — otherwise it can only judge keywords that already exist and
-- already spend, and the account can never grow except by accident."
--
-- THE ORDERING, EXACTLY AS 2.4 STATES IT AND NOT AS CVR:
--     (expected conversions x margin) - (expected clicks x ceiling CPC), over the requested window,
--     the whole thing discounted by confidence.
-- "A high-CVR subject with almost no volume is worth less than a moderate-CVR subject with real
-- volume, and ranking on CVR alone quietly fills an allowance with keywords too small to matter."
-- THE DISCOUNT IS WHAT STOPS AN UNKNOWN CANDIDATE OUTRANKING A PROVEN ONE ON OPTIMISM ALONE.
--
-- COMPARE WITHIN THE FAMILY, NEVER ACROSS IT. The pot, the bar and the halo are all family-scoped
-- and the allowance cannot cross a family line (1.2), so rank_in_family is the published order and
-- there is deliberately no account-wide rank column.
--
-- EVERY CANDIDATE CARRIES THE ORDINARY FOUR FIELDS (2), plus is_live / is_new.
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CATALOG_RANK` AS
WITH wm AS (
  SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),
req AS (
  -- the requested window if Ori has asked for one, otherwise the coming week.
  -- NOTE THE `FROM UNNEST([1])` ON THE FALLBACK ARM: BigQuery rejects a WHERE clause on a query
  -- with no FROM ("Query without FROM clause cannot have a WHERE clause"), and the fallback arm is
  -- a constant row guarded by a NOT EXISTS. Verify with
  --   bq query --dry_run "SELECT 1 WHERE NOT EXISTS (SELECT 1)"
  -- before deciding this is decoration.
  SELECT window_from, window_to, request_label AS window_label
  FROM `onyga-482313.OI.DE_CATALOG_WINDOW_REQUEST` WHERE is_active
  UNION ALL
  SELECT DATE_ADD((SELECT d FROM wm), INTERVAL 1 DAY),
         DATE_ADD((SELECT d FROM wm), INTERVAL 7 DAY),
         'the coming week'
  FROM UNNEST([1])
  WHERE NOT EXISTS (SELECT 1 FROM `onyga-482313.OI.DE_CATALOG_WINDOW_REQUEST` WHERE is_active)
),
-- ── LIVE CANDIDATES: subjects the Catalog already answers for ────────────────────────────────
live AS (
  SELECT
    ks.family,
    ks.campaign_id,
    ks.keyword_id,
    ks.subject_key,
    ks.target_text,
    ks.match_type,
    FALSE                                                        AS is_new,
    TRUE                                                         AS is_live,
    ks.verdict,
    ks.ceiling_cpc,
    ks.ceiling_basis,
    ks.confidence,
    ks.confidence_band,
    -- expected clicks OVER THE REQUESTED WINDOW, clamped by the market where it is known (2.8)
    LEAST(SAFE_DIVIDE(ks.settled_clk90, 90.0)
            * DATE_DIFF(r.window_to, r.window_from, DAY),
          COALESCE(ks.market_clicks_per_day * DATE_DIFF(r.window_to, r.window_from, DAY), 1e18))
                                                                 AS expected_clicks,
    SAFE_DIVIDE(ks.settled_ord90, NULLIF(ks.settled_clk90, 0))   AS cvr,
    SAFE_DIVIDE(ks.settled_gp90, NULLIF(ks.settled_ord90, 0))    AS gp_per_order,
    ks.family_bar,
    ks.settled_cpc90                                             AS observed_cpc,
    'LIVE'                                                       AS evidence_grade,
    ks.state_reason                                              AS evidence_note
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE` ks
  CROSS JOIN req r
  WHERE ks.snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
    AND ks.family IS NOT NULL
),
-- ── NEW CANDIDATES: the harvest gap (10.3 — not SQP) ─────────────────────────────────────────
new_c AS (
  SELECT
    hc.family,
    hc.campaign_id,
    CAST(NULL AS STRING)                                         AS keyword_id,
    CONCAT('harvest|', hc.campaign_id, '|', hc.target_text)      AS subject_key,
    hc.target_text,
    'EXACT'                                                      AS match_type,
    TRUE                                                         AS is_new,
    FALSE                                                        AS is_live,
    -- a new candidate is UNKNOWN by construction: doctrine 2.3 and 2.4 both say a proposal is a
    -- question, and only evidence the account produced can make it WORTH.
    'UNKNOWN'                                                    AS verdict,
    -- its ceiling is what its own observed record affords, at its family's bar
    SAFE_DIVIDE(SAFE_DIVIDE(hc.gp, NULLIF(hc.clicks, 0)), NULLIF(hc.campaign_bar, 0))
                                                                 AS ceiling_cpc,
    'AVERAGE_HARVEST'                                            AS ceiling_basis,
    -- NO_EVIDENCE is a distinct state (2.7): this subject has never been bought AS a keyword, and a
    -- term-level record is not the same record. Discounting to zero would drop it from the queue
    -- entirely, which is wrong; it enters at the lowest non-zero weight the doctrine licenses for a
    -- question, which is what TEST funding is for.
    0.10                                                         AS confidence,
    'NO_EVIDENCE'                                                AS confidence_band,
    LEAST(SAFE_DIVIDE(hc.clicks, 90.0) * DATE_DIFF(r.window_to, r.window_from, DAY),
          COALESCE(hc.market_clicks_per_day * DATE_DIFF(r.window_to, r.window_from, DAY), 1e18))
                                                                 AS expected_clicks,
    hc.cvr,
    hc.gp_per_order,
    hc.campaign_bar                                              AS family_bar,
    hc.cpc                                                       AS observed_cpc,
    hc.evidence_grade,
    hc.evidence_note
  FROM `onyga-482313.OI.V_HARVEST_CANDIDATE` hc
  CROSS JOIN req r
  WHERE hc.family IS NOT NULL
),
all_c AS (SELECT * FROM live UNION ALL SELECT * FROM new_c),
-- ── THE SCORE, AND WHY IT IS NOT EVALUATED AT THE CEILING ───────────────────────────────────
-- 2.4 words the ordering as "(expected conversions x margin) - (expected clicks x ceiling CPC),
-- discounted by confidence". Implemented literally that is DEGENERATE IN THIS ACCOUNT, and the
-- arithmetic says why in one line. For a live subject,
--     cvr x gp_per_order = (orders/clicks) x (gp/orders) = gp_per_click
-- and the ceiling is gp_per_click / bar by construction (SP_SNAPSHOT_KEYWORD_STATE:321-323). So
--     expected profit at the ceiling = clicks x gp_per_click x (1 - 1/bar)
-- which is ZERO at bar = 1.0 and NEGATIVE for every bar below it — because paying the ceiling means
-- landing exactly ON the bar, and this house's bars are deliberately below 1.0 (halo and lifetime
-- value are why). Measured 2026-08-24: family_bar runs 0.7384 to 1.0000, mean 0.9106, with 502 of
-- 838 subjects strictly below 1.0, and affordable_cpc exceeds gp_per_click on 260 of the 359 rows
-- carrying both. Scored both ways over those 359 subjects on the same date: the corrected form below
-- returns 166 positive / 69 zero / 26 negative, and the literal at-the-ceiling form returns exactly
-- ONE positive row out of 359. Under the literal reading the ORDER BY would rank the
-- LARGEST opportunity LAST, a 0.10-confidence candidate would outrank a proven one because
-- multiplying a negative by 0.10 moves it toward zero, and Task 12.4's `rank_value > 0` gate would
-- admit nothing at all.
--
-- THE CEILING IS A LIMIT, NOT A PLAN. What 2.4 is asking for — "expected profit contribution" — is
-- evaluated at the price the Brain would ACTUALLY PAY, and measured in the currency the bar is
-- written in:
--     planned_cpc = LEAST(the subject's own observed CPC, its ceiling)   -- never above the ceiling
--     rank_value  = expected_clicks x (gp_per_click - bar x planned_cpc) x confidence
-- This is zero exactly AT the bar, positive above it, negative below it, and it scales with volume —
-- which is the property 2.4 spends a paragraph on ("a high-CVR subject with almost no volume is
-- worth less than a moderate-CVR subject with real volume"). The doctrine's literal expression is
-- still PUBLISHED, as expected_profit_at_ceiling, so the two can be read side by side and the
-- structural sign is on the row rather than hidden. RECORD THIS in architecture/THREE_LAYERS.md 10
-- as an amendment to 2.4's wording, with the bar distribution above beside it; it is arithmetic,
-- not taste, but it changes a sentence Ori wrote and he should see it changed.
scored AS (
  SELECT
    c.*,
    COALESCE(c.cvr, 0) * COALESCE(c.gp_per_order, 0)                   AS gp_per_click,
    COALESCE(c.family_bar, 1.0)                                        AS bar,
    LEAST(COALESCE(c.observed_cpc, c.ceiling_cpc, 0),
          COALESCE(c.ceiling_cpc, c.observed_cpc, 0))                  AS planned_cpc
  FROM all_c c
),
-- the whole published row, scored but not yet ranked. THE RANKING IS A SEPARATE OUTER SELECT
-- because a window function's ORDER BY cannot read a select-list alias from its own SELECT, and
-- writing the score expression a second time inside the OVER(...) is a copy that can drift from
-- the published rank_value — which is precisely how the ordering and the gate came apart before.
ranked AS (
SELECT
  c.family,
  (SELECT window_from FROM req)                                  AS window_from,
  (SELECT window_to   FROM req)                                  AS window_to,
  (SELECT window_label FROM req)                                 AS window_label,
  c.campaign_id,
  c.keyword_id,
  c.subject_key,
  c.target_text,
  c.match_type,
  c.is_live,
  c.is_new,
  -- the ordinary four fields (2)
  c.verdict,
  c.ceiling_cpc,
  c.ceiling_basis,
  c.confidence,
  c.confidence_band,
  c.expected_clicks,
  c.cvr,
  c.gp_per_order,
  c.evidence_grade,
  c.evidence_note,
  -- ── THE SCORE (2.4), spelled out so it can be argued with. See the `scored` CTE header. ───
  c.bar                                                          AS family_bar,
  ROUND(c.planned_cpc, 4)                                        AS planned_cpc,
  ROUND(COALESCE(c.expected_clicks, 0) * c.gp_per_click, 4)      AS expected_gross_profit,
  ROUND(COALESCE(c.expected_clicks, 0) * c.planned_cpc, 4)       AS expected_cost_at_planned_price,
  ROUND(COALESCE(c.expected_clicks, 0) * COALESCE(c.ceiling_cpc, 0), 4)
                                                                 AS expected_cost_at_ceiling,
  -- 2.4's literal expression, published so the amendment above is auditable rather than asserted.
  -- It is <= 0 by construction wherever the family bar is <= 1.0, which is most of this account.
  ROUND((COALESCE(c.expected_clicks, 0) * c.gp_per_click
         - COALESCE(c.expected_clicks, 0) * COALESCE(c.ceiling_cpc, 0))
        * COALESCE(c.confidence, 0), 4)                          AS expected_profit_at_ceiling,
  -- THE ORDERING SCORE: expected profit contribution at the price we would actually pay, measured
  -- against the bar, discounted by confidence.
  ROUND(COALESCE(c.expected_clicks, 0)
        * (c.gp_per_click - c.bar * c.planned_cpc)
        * COALESCE(c.confidence, 0), 4)                          AS rank_value
FROM scored c
)
SELECT
  r.*,
  -- within the family, never across it (1.2)
  ROW_NUMBER() OVER (PARTITION BY r.family
                     ORDER BY r.rank_value DESC,
                              r.expected_clicks DESC,
                              r.subject_key)                     AS rank_in_family
FROM ranked r;
```

- [ ] **Step 2: Deploy and read the ranked list**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_CATALOG_RANK.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT family, rank_in_family, target_text, is_new, verdict, confidence_band,
       ROUND(expected_clicks, 1) exp_clicks, ROUND(rank_value, 2) rank_value
FROM \`onyga-482313.OI.V_CATALOG_RANK\`
WHERE rank_in_family <= 5 ORDER BY family, rank_in_family"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT is_new, COUNT(*) candidates, ROUND(AVG(rank_in_family), 1) avg_rank
FROM \`onyga-482313.OI.V_CATALOG_RANK\` GROUP BY 1"
```

**Sanity check the ordering, in this order, because the first check explains most failures of the
second:**

1. **`rank_value` must have both signs.** Run
   `SELECT COUNTIF(rank_value > 0) pos, COUNTIF(rank_value = 0) zero, COUNTIF(rank_value < 0) neg
   FROM V_CATALOG_RANK`. If `pos = 0`, the score is being evaluated at the ceiling rather than at
   `planned_cpc` — read the `scored` CTE header, which explains why that is zero-at-the-bar by
   construction and negative below it. Do **not** reach for the confidence discount; it is not the
   cause. `expected_profit_at_ceiling` is expected to be almost entirely `<= 0`, and that is the
   published evidence for the amendment, not a bug.
2. **Then check the discount.** A new candidate at 0.10 confidence should rarely outrank a proven
   live one, and where it does it should be because its expected profit is many times larger. If new
   candidates dominate the top of every family, the discount is not doing its job and §2.4's "cannot
   outrank a proven one on optimism alone" is being violated. Note that with a correctly-signed
   score the discount now works in the right direction — multiplying a positive by 0.10 moves it
   toward zero, which demotes it, where multiplying a negative by 0.10 promoted it.

- [ ] **Step 3: Register and commit**

Insert the entry in `config.yaml` under `views:` **immediately after the `V_HARVEST_CANDIDATE` entry**
added in Task 12.2 — never appended at the end of the file — describing it as
`catalog.rank(family, window)`, that it orders live and new candidates by expected profit
contribution at the price the Brain would actually pay, discounted by confidence, never by CVR; that
§2.4's literal at-the-ceiling expression is published beside it as `expected_profit_at_ceiling` and
is `<= 0` by construction wherever the family bar is `<= 1.0`; and that ranking is within the family
and never across it. Verify with the `config.yaml` duplicate check in the plan header, then:

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_CATALOG_RANK.sql config.yaml
git commit -m "feat(catalog): V_CATALOG_RANK — what is worth having, not only what this is worth

Closes violation 5. Ordered by expected profit contribution at the price the Brain
would actually pay, discounted by confidence, never by CVR, and compared within the
family because the pot, the bar and the halo are all family-scoped. 2.4's literal
at-the-ceiling expression is published beside it and is <= 0 by construction
wherever the family bar is <= 1.0 — which is 502 of 838 subjects."
```

---

### Task 12.4: Wire it into the Brain — fund down the list

**Files:**
- Modify: `scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql` (a new candidate source and the `TEST` move)
- Modify: `scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql` C06

- [ ] **Step 1: Admit new candidates into the seat walk**

Add a temp table before the `ranked` CTE:

```sql
  -- ── NEW CANDIDATES FROM catalog.rank() (2026-08-25, violation 5) ─────────────────────────────
  -- Doctrine 2.4: "the Brain then does what it always does — take the ranked list, fund down it
  -- until the family's allowance is spent, and queue the rest. A new candidate is funded as a
  -- question (TEST) with a budget and a deadline like any other."
  -- Phase 6 already made a seat fund the answer it demands, so a harvest candidate cannot arrive
  -- half-funded: its seat is priced (clicks_to_verdict x expected CPC) / answer_days like every
  -- other seat, and it competes for the same family allowance rather than being handed one.
  CREATE OR REPLACE TEMP TABLE new_candidates AS
  SELECT
    r.family,
    r.campaign_id,
    r.subject_key,
    r.target_text,
    r.match_type,
    r.ceiling_cpc,
    r.confidence,
    r.confidence_band,
    r.rank_value,
    r.evidence_grade,
    r.evidence_note,
    -- the seat is priced exactly as every other seat is (P-6 as restated in Phase 6)
    SAFE_DIVIDE(cfg.clicks_to_verdict * COALESCE(r.ceiling_cpc, 0),
                NULLIF(cfg.answer_days, 0))                       AS seat_cost_per_day,
    DATE_ADD(as_of_d, INTERVAL cfg.answer_days + 7 DAY)           AS verdict_date
  FROM `onyga-482313.OI.V_CATALOG_RANK` r
  CROSS JOIN (SELECT MAX(clicks_to_verdict) AS clicks_to_verdict,
                     MAX(answer_days)       AS answer_days
              FROM `onyga-482313.OI.DE_PLAN_CONFIG`
              WHERE is_active
                AND calendar_state = `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(as_of_d)) cfg
  WHERE r.is_new
    AND r.rank_value > 0
    -- a family that is not in the plan at all (launch, brand defense) is not funded from here
    AND r.family IN (SELECT DISTINCT family FROM r2 WHERE plan = 'B');
```

- [ ] **Step 2: Give them a move and a deadline**

Union them into `ranked` so they take their place in the family's ordering by `rank_value`, and add the move:

```sql
      -- a new candidate is a QUESTION: bought at the ceiling, for a fixed number of clicks, with a
      -- date by which it must have answered. It is never funded as a proven subject (10.1 rates the
      -- harvest finding MEDIUM and survivorship-selected).
      WHEN r2.is_new AND m.seat_no IS NOT NULL                          THEN 'TEST_NEW'
      WHEN r2.is_new                                                    THEN 'NONE'
```

and add `'TEST_NEW'` to acceptance C06's legal-move enumeration **and to C14's `seat_no IS NOT NULL` list** — a `TEST_NEW` takes a seat and its allowance, so it is a seated move. C14 enumerates the legal moves a second time and goes red on any move added to C06 alone (Task 6.2 Step 6).

- [ ] **Step 3: Deploy, run, verify the allowance still binds**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT family, move, COUNT(*) n, ROUND(SUM(COALESCE(seat_cost_per_day, 0)), 2) seat_usd_per_day,
       ROUND(MAX(allowance_ramped_per_day), 2) allowance
FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
WHERE as_of = (SELECT MAX(as_of) FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`) AND is_live_plan
GROUP BY 1,2 ORDER BY family, n DESC"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql)"
```

Expected: `TEST_NEW` seats appear inside families that had allowance to spare, **the builder's own allowance ASSERT still passes** (it aborts above the `DELETE` if it does not), and every acceptance row reads `PASS`.

- [ ] **Step 4: Compare within the family, and check the measured picture**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT family,
       ROUND(MAX(allowance_ramped_per_day), 2) allowance,
       ROUND(SUM(IF(seat_no IS NOT NULL, seat_cost_per_day, 0)), 2) seated,
       ROUND(SUM(IF(is_candidate AND seat_no IS NULL, seat_cost_per_day, 0)), 2) queued
FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
WHERE as_of = (SELECT MAX(as_of) FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`) AND is_live_plan
GROUP BY 1 ORDER BY allowance DESC"
```

Measured 2026-08-24 for context: three families were over allowance and one under, and LolliME could afford its entire $46.37/day queue out of allowance it was not spending, against a $98.95/day total queue. **The allowance cannot cross a family line** — a family with spare allowance funds its own questions and nobody else's.

- [ ] **Step 5: Retire any parallel keyword-proposal path**

```bash
cd /Users/ori/Develop/OI
grep -rn "ADD_KEYWORD" scripts/bigquery/views/*.sql scripts/bigquery/procedures/*.sql tools/*.py | head
```

§2.4: *"Research-sourced keywords enter here — they are Catalog candidates, not a separate decision-making system."* Any surface that proposes a keyword outside `V_CATALOG_RANK` is a second decision-maker for one question. Where one is found, re-point it at `V_CATALOG_RANK` and record the retirement in the commit message; where the grep is empty, say so.

- [ ] **Step 6: Ask §2.1's grain-3 question, which nothing asks today**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT family,
       CASE WHEN is_auto THEN LOWER(target_text) ELSE 'not an auto mode' END AS mode,
       COUNT(*) subjects, ROUND(SUM(settled_sp90)/90, 2) usd_per_day,
       ROUND(SAFE_DIVIDE(SUM(settled_gp90), NULLIF(SUM(settled_sp90), 0)), 3) gp_roas,
       ROUND(AVG(family_bar), 3) bar
FROM \`onyga-482313.OI.V_KEYWORD_STATE\`
WHERE is_auto AND family IS NOT NULL
GROUP BY 1, 2 ORDER BY usd_per_day DESC"
```

§2.1: *"does substitutes-targeting work for us as an instrument, and for which families?"* is a real allocation question at grain 3, meaningless across families as "the same subject", and **nothing asks it today despite the money involved**. Record the answer in the doctrine's §10 table; it is not an action in this plan, it is a question the grain now permits.

- [ ] **Step 7: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql \
        scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql
git commit -m "feat(brain): fund down the ranked list — the Brain becomes proactive

Closes violation 5. A new candidate is funded as TEST with a budget and a deadline,
competes for the same family allowance as everything else, and cannot cross a
family line."
```

---
## Phase 13 — The vehicle

**Closes:** violation 18 (the Catalog does not know what is advertised).

**Why last, and honestly gated on data rather than effort.** §2.6 needs format, placement, creative and match width on the subject. The fine placement split exists only at **campaign × placement × date** grain (`V_CAMPAIGN_PLACEMENT_REPORT`, unioned from the fivetran campaign and SB placement reports) — there is **no keyword-grain placement anywhere in the warehouse** — and `FACT_AMAZON_ADS.placement_type` carries only two values account-wide (`Search_Results`, `Product_Page`, 100% populated over 131,899 rows in the settled window), so it cannot even separate top of search from rest of search.

**It is nevertheless the phase that retires the most expensive analytical error the baseline found.** About **87%** of the sales behind paused keywords had their exact query bought elsewhere in the account within 28 days, through a wider match — which turned a confident "$240/day destroyed" into a non-finding. Until the Catalog carries the vehicle dimension it will keep reporting **recaptured demand as destroyed value**, and every seasonal-pause valuation — including the ones this plan acts on in Phases 4 and 5 — overstates its loss by an unknown amount.

**Size:** L — 2–3 weeks, front-loaded by a data-availability question that may change the design, and closed by the §8 audit that makes the doctrine tell the truth about itself.

---

### Task 13.1: The data question, FIRST — before any modelling

- [ ] **Step 1: Ask whether a finer placement grain exists at all**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT DISTINCT placement_type, COUNT(*) rows
   FROM \`onyga-482313.OI.FACT_AMAZON_ADS\`
   WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 92 DAY)
   GROUP BY 1 ORDER BY rows DESC"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT table_name FROM \`fivetran-hl.amazon_ads.INFORMATION_SCHEMA.TABLES\`
   WHERE LOWER(table_name) LIKE '%placement%' ORDER BY 1"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT column_name FROM \`fivetran-hl.amazon_ads.INFORMATION_SCHEMA.COLUMNS\`
   WHERE LOWER(table_name) LIKE '%placement%'
     AND (LOWER(column_name) LIKE '%keyword%' OR LOWER(column_name) LIKE '%target%'
          OR LOWER(column_name) LIKE '%ad_group%')
   ORDER BY 1"
```

**Read the answer before writing anything.** If the placement feeds carry no grain finer than campaign × placement × date, **say so and design against campaign-grain allocation honestly** — §2 is explicit: *do not promise per-keyword precision the data cannot support*. Record the answer in the doctrine's §10 table either way; a negative answer here is a finding, not a blocker.

- [ ] **Step 2: The red assertions**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT column_name FROM \`onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS\`
   WHERE table_name = 'FACT_KEYWORD_STATE'
     AND (LOWER(column_name) LIKE '%placement%' OR LOWER(column_name) LIKE '%creative%'
          OR LOWER(column_name) LIKE '%vehicle%')"
```

Expected: only `creative_type` (which is the SB creative **format**, not the specific creative), and **no placement column at all** at keyword grain. `placement_type` distinguishing top-of-search from rest-of-search: it does not — two values account-wide.

- [ ] **Step 3: Record the measurement and commit it**

Every red measurement in this plan is a number the green run is compared against, so it is written
down rather than remembered. Append what you measured — the query, the date, and the count — to the
running record, creating the file on the first task that reaches this step:

```bash
cd /Users/ori/Develop/OI
mkdir -p docs/superpowers/specs
cat >> docs/superpowers/specs/2026-08-25-gap-closure-measurements.md <<'EOF'

## Task 13.1 — measured YYYY-MM-DD

Replace the date above with the date you ran it, and paste below: the query you ran (unchanged from
the task), and its output. Do not summarise the output — the point of this file is that a re-run is
a re-run and not a fresh argument, which is the same reason
docs/superpowers/specs/2026-08-24-three-layers-baseline.md exists.
EOF
git add docs/superpowers/specs/2026-08-25-gap-closure-measurements.md
git commit -m "measure(task 13.1): record the red measurement before the fix

The number the green run is compared against, written down rather than remembered."
```

---

### Task 13.2: `V_SUBJECT_VEHICLE`

**Files:**
- Create: `scripts/bigquery/views/V_SUBJECT_VEHICLE.sql`
- Modify: `config.yaml` (`views:`)

- [ ] **Step 1: Write the view**

```sql
-- =============================================================================================
-- V_SUBJECT_VEHICLE — what actually carries a subject's demand (doctrine 2.6).
--
-- "Worth is not a property of a search phrase alone. The same demand can be bought through
-- different VEHICLES, and Amazon prices each one differently: format (SP / SB / SB video),
-- placement, creative, and match width. A Catalog that knows only 'this phrase is worth X' cannot
-- answer WHICH VEHICLE SHOULD CARRY IT."
--
-- ── WHAT THE DATA ACTUALLY SUPPORTS, STATED RATHER THAN PAPERED OVER ─────────────────────────
-- FORMAT      fully available: campaign_type on the campaign, creative_type on the ad group.
-- MATCH WIDTH fully available: targeting_type, plus the auto-clause and product-target patterns.
-- CREATIVE    available only as a TYPE for SB (PRODUCT_COLLECTION / STORE_SPOTLIGHT / video); the
--             specific creative id is not in the warehouse. 2.6 notes the account runs more than
--             one video and one performs materially better — that comparison is NOT possible here
--             and the column says so rather than implying it is.
-- PLACEMENT   NOT AVAILABLE AT SUBJECT GRAIN. FACT_AMAZON_ADS.placement_type carries two values
--             account-wide and cannot separate top of search from rest of search; the fine split
--             exists only at campaign x placement x date in V_CAMPAIGN_PLACEMENT_REPORT. The
--             campaign-grain mix is joined in and LABELLED AS CAMPAIGN-GRAIN, because a mix that
--             belongs to the campaign is not a fact about the keyword and must never be read as one.
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_SUBJECT_VEHICLE` AS
WITH wm AS (
  SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),
subj AS (
  SELECT campaign_id, keyword_id, subject_key, target_text, match_type, channel,
         is_auto, is_pt, ad_group_id, creative_type, family
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
),
-- the campaign's placement mix, which is the finest grain the warehouse holds.
-- TWO THINGS THAT MUST BE READ OFF THE SOURCE AND NOT GUESSED, both verified 2026-08-25:
--   * the date column is `report_date`, not `date`. V_CAMPAIGN_PLACEMENT_REPORT publishes
--     campaign_id, campaign_source, report_date, placement, placement_raw, bidding_strategy and
--     the metrics; `date` does not exist and `WHERE date BETWEEN ...` fails to deploy with
--     Unrecognized name: date.
--   * `placement` takes exactly FOUR values — TOP_OF_SEARCH, DETAIL_PAGE, OTHER, OFF_AMAZON.
--     There is no '%PRODUCT%' and no '%REST%'; those patterns match nothing and would publish
--     0.0 shares on every row for ever, silently, while Task 13.4 carried them onto the subject
--     and Task 13.5 reasoned about vehicle choice from them. Match the four literals exactly, and
--     keep every one of them in the numerator set so the four shares sum to 1.
--     Re-derive rather than trust this comment:
--       SELECT placement, SUM(clicks) FROM `onyga-482313.OI.V_CAMPAIGN_PLACEMENT_REPORT`
--       WHERE report_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 92 DAY) GROUP BY 1
camp_mix AS (
  SELECT CAST(campaign_id AS STRING) AS cid,
         SUM(IF(placement = 'TOP_OF_SEARCH', clicks, 0))             AS tos_clicks,
         SUM(IF(placement = 'DETAIL_PAGE',   clicks, 0))             AS detail_clicks,
         SUM(IF(placement = 'OTHER',         clicks, 0))             AS rest_clicks,
         SUM(IF(placement = 'OFF_AMAZON',    clicks, 0))             AS off_amazon_clicks,
         SUM(IF(placement NOT IN ('TOP_OF_SEARCH','DETAIL_PAGE','OTHER','OFF_AMAZON'),
                clicks, 0))                                          AS unclassified_clicks,
         SUM(clicks)                                                 AS placement_clicks,
         SAFE_DIVIDE(SUM(cost), NULLIF(SUM(clicks), 0))              AS placement_cpc
  FROM `onyga-482313.OI.V_CAMPAIGN_PLACEMENT_REPORT`, wm
  WHERE report_date BETWEEN DATE_SUB(wm.d, INTERVAL 92 DAY) AND DATE_SUB(wm.d, INTERVAL 1 DAY)
  GROUP BY 1
),
-- the subject's own two-value placement split, which is all FACT_AMAZON_ADS carries
subj_split AS (
  SELECT CAST(a.campaign_id AS STRING) AS cid, CAST(a.keyword_id AS STRING) AS kid,
         SUM(IF(a.placement_type = 'Search_Results', a.Ads_clicks, 0))  AS search_clicks,
         SUM(IF(a.placement_type = 'Product_Page',   a.Ads_clicks, 0))  AS product_page_clicks,
         SUM(a.Ads_clicks)                                              AS clicks
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a, wm w
  WHERE a.keyword_id IS NOT NULL
    AND a.date BETWEEN DATE_SUB(w.d, INTERVAL 92 DAY) AND DATE_SUB(w.d, INTERVAL 1 DAY)
  GROUP BY 1, 2
)
SELECT
  s.campaign_id,
  s.keyword_id,
  s.subject_key,
  s.target_text,
  s.family,

  -- FORMAT (2.6): what kind of ad carries this
  CASE WHEN UPPER(COALESCE(s.channel, 'SP')) != 'SB'                       THEN 'SP'
       WHEN UPPER(COALESCE(s.creative_type, '')) IN ('PRODUCT_COLLECTION',
                                                     'STORE_SPOTLIGHT')    THEN 'SB_COLLECTION'
       ELSE 'SB_VIDEO' END                                        AS vehicle_format,

  -- MATCH WIDTH (2.6): how wide the net is
  CASE WHEN s.is_auto THEN CONCAT('AUTO_', UPPER(COALESCE(s.target_text, '')))
       WHEN s.is_pt   THEN 'PRODUCT_TARGET'
       ELSE UPPER(COALESCE(s.match_type, 'UNKNOWN')) END          AS vehicle_match_width,

  -- CREATIVE (2.6): a TYPE only. The specific creative is not in the warehouse, and 2.6's
  -- observation that one video outperforms another cannot be tested from here.
  s.creative_type                                                 AS vehicle_creative_type,
  'TYPE_ONLY — the specific creative id is not in the warehouse, so one video cannot be compared to another (2.6)'
                                                                  AS vehicle_creative_note,

  -- PLACEMENT: two values at subject grain, a fuller mix only at campaign grain, both labelled
  SAFE_DIVIDE(ss.search_clicks, NULLIF(ss.clicks, 0))             AS subject_search_click_share,
  SAFE_DIVIDE(ss.product_page_clicks, NULLIF(ss.clicks, 0))       AS subject_product_page_click_share,
  -- FOUR SHARES, NAMED AFTER THE SOURCE'S OWN FOUR VALUES, and they sum to 1 by construction.
  -- `campaign_other_share` is Amazon's OTHER bucket verbatim — it is the largest of the four by
  -- clicks and inventing a friendlier name for it ("rest of search") would be a claim the data does
  -- not make. unclassified_clicks exists so a fifth value appearing upstream is visible instead of
  -- being absorbed into a denominator.
  SAFE_DIVIDE(cm.tos_clicks, NULLIF(cm.placement_clicks, 0))      AS campaign_top_of_search_share,
  SAFE_DIVIDE(cm.detail_clicks, NULLIF(cm.placement_clicks, 0))   AS campaign_detail_page_share,
  SAFE_DIVIDE(cm.rest_clicks, NULLIF(cm.placement_clicks, 0))     AS campaign_other_share,
  SAFE_DIVIDE(cm.off_amazon_clicks, NULLIF(cm.placement_clicks, 0)) AS campaign_off_amazon_share,
  SAFE_DIVIDE(cm.unclassified_clicks, NULLIF(cm.placement_clicks, 0)) AS campaign_unclassified_share,
  cm.placement_cpc                                                AS campaign_placement_cpc,
  'CAMPAIGN_GRAIN — this placement mix belongs to the campaign, not to this keyword. No keyword-grain placement exists anywhere in the warehouse (violation 18).'
                                                                  AS placement_grain_note,
  (ss.clicks IS NULL OR ss.clicks = 0)                            AS vehicle_no_evidence
FROM subj s
LEFT JOIN subj_split ss ON ss.cid = s.campaign_id AND ss.kid = s.keyword_id
LEFT JOIN camp_mix   cm ON cm.cid = s.campaign_id;
```

- [ ] **Step 2: Deploy, verify, register, commit**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_SUBJECT_VEHICLE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT vehicle_format, vehicle_match_width, COUNT(*) subjects,
          COUNTIF(vehicle_no_evidence) with_no_clicks
   FROM \`onyga-482313.OI.V_SUBJECT_VEHICLE\` GROUP BY 1,2 ORDER BY subjects DESC"
# THE PLACEMENT BUCKETS ARE THE ONE THING HERE THAT FAILS SILENTLY. A share that is structurally
# 0.0 on every row looks like "this campaign has no detail-page traffic" and is indistinguishable
# from a pattern that matches nothing — and Task 13.4 carries these onto the subject, where Task
# 13.5 reasons about vehicle choice from them.
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT COUNTIF(campaign_top_of_search_share > 0) tos,
       COUNTIF(campaign_detail_page_share  > 0) detail,
       COUNTIF(campaign_other_share        > 0) other_,
       COUNTIF(campaign_off_amazon_share   > 0) off_amazon,
       COUNTIF(COALESCE(campaign_unclassified_share, 0) > 0) unclassified_MUST_BE_ZERO,
       COUNTIF(campaign_placement_cpc IS NOT NULL
               AND ABS(COALESCE(campaign_top_of_search_share,0) + COALESCE(campaign_detail_page_share,0)
                     + COALESCE(campaign_other_share,0) + COALESCE(campaign_off_amazon_share,0)
                     + COALESCE(campaign_unclassified_share,0) - 1.0) > 0.0001) shares_that_do_not_sum_to_1
FROM \`onyga-482313.OI.V_SUBJECT_VEHICLE\`"
git add scripts/bigquery/views/V_SUBJECT_VEHICLE.sql config.yaml
git commit -m "feat(catalog): V_SUBJECT_VEHICLE — format, match width, creative type, placement

Half of violation 18. Placement is honestly labelled as campaign-grain because no
keyword-grain placement exists in the warehouse, and the creative axis is a type
only — 2.6's video-versus-video comparison cannot be made from this data. The four
placement shares are named after the source's own four values and sum to 1; the
date column is report_date, which is what the source actually publishes."
```

---

### Task 13.3: `V_DEMAND_RECAPTURE` — the test that tells a destroyed sale from a recaptured one

**Files:**
- Create: `scripts/bigquery/views/V_DEMAND_RECAPTURE.sql`
- Modify: `config.yaml` (`views:`)

- [ ] **Step 1: Write the view**

```sql
-- =============================================================================================
-- V_DEMAND_RECAPTURE — was this subject's demand bought elsewhere in the account? (doctrine 2.6)
--
-- WHY THIS IS THE MOST IMPORTANT OBJECT IN THIS PHASE. 10.2 records a confident, well-measured
-- claim that died: "~$240/day of last season's net was destroyed by pausing 79 keywords." About 87%
-- of those sales had their exact query bought ELSEWHERE in the account within 28 days, through a
-- wider match. The traffic changed vehicle. Nothing was lost.
--
-- 2.6's two consequences, and both need this test to be answerable:
--   "A pause is CHEAPER than doctrine 5 assumes when the demand is recaptured, and EXACTLY AS
--    EXPENSIVE as doctrine 5 assumes when it is not — and only a vehicle-aware Catalog can tell
--    which case is in front of you."
--
-- 6.3 MAKES THIS A STANDING CHECK, not a one-off: "name the innocent explanation and test it before
-- claiming money was wasted." For a pause valuation the innocent explanation IS recapture, and this
-- view is where it gets tested. Every pause valuation this plan reports must run through it.
--
-- GRAIN: one row per (campaign_id, keyword_id) that has stopped taking clicks. The comparison is on
-- the SEARCH TERM, because that is the demand — the keyword is only the vehicle that bought it.
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_DEMAND_RECAPTURE` AS
WITH wm AS (
  SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),
-- every subject's last click, and the terms it was buying at the end
gone AS (
  SELECT CAST(a.campaign_id AS STRING) AS cid,
         CAST(a.keyword_id  AS STRING) AS kid,
         MAX(a.date)                   AS last_click_date
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  WHERE a.keyword_id IS NOT NULL AND a.Ads_clicks > 0
  GROUP BY 1, 2
  HAVING MAX(a.date) < DATE_SUB((SELECT d FROM wm), INTERVAL 28 DAY)
),
-- the terms each stopped subject bought in its last 28 active days, and what they were worth
terms_before AS (
  SELECT g.cid, g.kid, g.last_click_date,
         LOWER(TRIM(a.search_term))    AS term,
         SUM(a.Ads_clicks)             AS clicks_before,
         SUM(a.Ads_orders)             AS orders_before,
         SUM(a.Ads_sales)              AS sales_before,
         SUM(a.GROSS_PROFIT)           AS gp_before,
         SUM(a.Ads_cost)               AS spend_before
  FROM gone g
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` a
    ON CAST(a.campaign_id AS STRING) = g.cid
   AND CAST(a.keyword_id  AS STRING) = g.kid
   AND a.date BETWEEN DATE_SUB(g.last_click_date, INTERVAL 27 DAY) AND g.last_click_date
  WHERE a.search_term IS NOT NULL AND a.Ads_clicks > 0
  GROUP BY 1, 2, 3, 4
),
-- the same term bought ANYWHERE ELSE in the account in the 28 days after that last click
after AS (
  SELECT tb.cid, tb.kid, tb.term,
         SUM(a.Ads_clicks)   AS clicks_after_elsewhere,
         SUM(a.Ads_orders)   AS orders_after_elsewhere,
         SUM(a.Ads_sales)    AS sales_after_elsewhere,
         SUM(a.GROSS_PROFIT) AS gp_after_elsewhere,
         COUNT(DISTINCT CONCAT(CAST(a.campaign_id AS STRING), '|',
                               CAST(a.keyword_id AS STRING)))              AS subjects_that_took_it,
         STRING_AGG(DISTINCT UPPER(COALESCE(a.targeting_type, 'UNKNOWN'))) AS vehicles_that_took_it
  FROM terms_before tb
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` a
    ON LOWER(TRIM(a.search_term)) = tb.term
   AND a.date BETWEEN DATE_ADD(tb.last_click_date, INTERVAL 1 DAY)
                  AND DATE_ADD(tb.last_click_date, INTERVAL 28 DAY)
  WHERE NOT (CAST(a.campaign_id AS STRING) = tb.cid AND CAST(a.keyword_id AS STRING) = tb.kid)
  GROUP BY 1, 2, 3
)
SELECT
  tb.cid                                                          AS campaign_id,
  tb.kid                                                          AS keyword_id,
  ANY_VALUE(tb.last_click_date)                                   AS last_click_date,
  COUNT(*)                                                        AS terms_it_was_buying,
  COUNTIF(af.term IS NOT NULL)                                    AS terms_bought_elsewhere_after,
  ROUND(SAFE_DIVIDE(COUNTIF(af.term IS NOT NULL), COUNT(*)), 4)   AS term_recapture_rate,
  -- the share OF THE MONEY, which is the number that matters and the one 10.2 measured at ~87%
  ROUND(SAFE_DIVIDE(SUM(IF(af.term IS NOT NULL, tb.sales_before, 0)),
                    NULLIF(SUM(tb.sales_before), 0)), 4)          AS sales_recapture_rate,
  ROUND(SUM(tb.sales_before), 2)                                  AS sales_before_it_stopped,
  ROUND(SUM(IF(af.term IS NOT NULL, tb.sales_before, 0)), 2)      AS sales_on_recaptured_terms,
  ROUND(SUM(IF(af.term IS NULL, tb.sales_before, 0)), 2)          AS sales_on_terms_nobody_took,
  ROUND(SUM(tb.gp_before) - SUM(tb.spend_before), 2)              AS net_before_it_stopped,
  -- the honest valuation of the pause: only the money on terms NOBODY ELSE TOOK is at stake
  ROUND(SUM(IF(af.term IS NULL, tb.gp_before - tb.spend_before, 0)), 2)
                                                                  AS net_genuinely_at_stake,
  STRING_AGG(DISTINCT af.vehicles_that_took_it, '; ')             AS recapture_vehicles,
  CASE
    WHEN SAFE_DIVIDE(SUM(IF(af.term IS NOT NULL, tb.sales_before, 0)),
                     NULLIF(SUM(tb.sales_before), 0)) >= 0.80
      THEN 'RECAPTURED — the demand changed vehicle; valuing this pause as a loss would repeat the error 10.2 recorded'
    WHEN SAFE_DIVIDE(SUM(IF(af.term IS NOT NULL, tb.sales_before, 0)),
                     NULLIF(SUM(tb.sales_before), 0)) >= 0.30
      THEN 'PARTLY RECAPTURED — value only the terms nobody else took'
    ELSE 'NOT RECAPTURED — this pause is exactly as expensive as doctrine 5 assumes'
  END                                                             AS recapture_verdict
FROM terms_before tb
LEFT JOIN after af ON af.cid = tb.cid AND af.kid = tb.kid AND af.term = tb.term
GROUP BY 1, 2;
```

- [ ] **Step 2: Deploy and reproduce the baseline's finding**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_DEMAND_RECAPTURE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT recapture_verdict, COUNT(*) subjects,
       ROUND(SUM(sales_before_it_stopped), 0) sales_before,
       ROUND(SUM(sales_on_recaptured_terms), 0) recaptured,
       ROUND(SUM(net_genuinely_at_stake), 0) net_genuinely_at_stake,
       ROUND(AVG(sales_recapture_rate), 3) avg_recapture_rate
FROM \`onyga-482313.OI.V_DEMAND_RECAPTURE\` GROUP BY 1 ORDER BY sales_before DESC"
```

Expected: a high average recapture rate, in the region the baseline measured (~87% of the money on the paused-keyword cohort). If it comes out far lower, **that is a finding and not a bug** — re-check the term join before concluding the account has changed.

- [ ] **Step 3: Register and commit**

Insert the entry in `config.yaml` under `views:` **immediately after the `V_SUBJECT_VEHICLE` entry**
added in Task 13.2 — never appended at the end of the file — describing it as the standing §6.3 check
for any pause valuation: it separates a sale that was DESTROYED by a pause from one that was simply
RECAPTURED by another vehicle, and publishes `sales_recapture_rate`, `net_genuinely_at_stake` and the
vehicles that did the recapturing. Verify with the `config.yaml` duplicate check in the plan header,
then:

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_DEMAND_RECAPTURE.sql config.yaml
git commit -m "feat(catalog): V_DEMAND_RECAPTURE — a destroyed sale is not a recaptured one

6.3's standing check for any pause valuation. About 87% of the sales behind paused
keywords had their query bought elsewhere within 28 days, which turned a confident
'\$240/day destroyed' into a non-finding (10.2)."
```

---

### Task 13.4: Carry the vehicle and the recapture answer on the subject

**Files:**
- Modify: `scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql`
- Modify: `scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql`
- Re-deploy: `scripts/bigquery/views/V_KEYWORD_STATE.sql`

- [ ] **Step 1: Join both and publish**

Add the CTEs:

```sql
  -- 2026-08-25 (violation 18): the vehicle dimension (2.6) and the recapture test (2.6, 6.3).
  veh AS (
    SELECT campaign_id AS cid, keyword_id AS kid,
           vehicle_format, vehicle_match_width, vehicle_creative_type,
           subject_search_click_share, campaign_top_of_search_share, placement_grain_note
    FROM `onyga-482313.OI.V_SUBJECT_VEHICLE`
  ),
  rec_cap AS (
    SELECT campaign_id AS cid, keyword_id AS kid,
           sales_recapture_rate, net_genuinely_at_stake, recapture_verdict, recapture_vehicles
    FROM `onyga-482313.OI.V_DEMAND_RECAPTURE`
  ),
```

and publish in the final `SELECT`:

```sql
    -- ── THE VEHICLE (2.6) ─────────────────────────────────────────────────────────────────────
    -- "A Catalog that knows only 'this phrase is worth X' cannot answer WHICH VEHICLE should carry
    -- it, and that is a real allocation question the Brain has no way to pose today."
    vh.vehicle_format,
    vh.vehicle_match_width,
    vh.vehicle_creative_type,
    vh.subject_search_click_share,
    vh.campaign_top_of_search_share,
    vh.placement_grain_note,

    -- ── THE RECAPTURE ANSWER (2.6, 6.3) ───────────────────────────────────────────────────────
    -- What tells a DESTROYED sale from a RECAPTURED one. Without it a per-subject valuation keeps
    -- reporting demand that simply changed vehicle as value that was destroyed — the error 10.2
    -- recorded, and the reason every pause valuation in this plan must be read through it.
    rc.sales_recapture_rate,
    rc.net_genuinely_at_stake,
    rc.recapture_verdict,
    rc.recapture_vehicles,
```

with both joins added where the final `SELECT` assembles its row. **The final `SELECT` reads
`FROM fin3 s` and `fin3` carries `campaign_id` / `keyword_id`; there is no `s.cid` or `s.kid` in this
procedure**, so the CTEs do the renaming and the predicates are:

```sql
  LEFT JOIN veh     vh ON vh.cid = s.campaign_id AND vh.kid = s.keyword_id
  LEFT JOIN rec_cap rc ON rc.cid = s.campaign_id AND rc.kid = s.keyword_id
```

Both source views are one row per `(campaign_id, keyword_id)`; confirm that before deploying rather
than after, because a fan-out here multiplies the ladder itself:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT 'V_SUBJECT_VEHICLE' v, COUNT(*) rows_,
       COUNT(DISTINCT CONCAT(campaign_id,'|',keyword_id)) pairs
FROM \`onyga-482313.OI.V_SUBJECT_VEHICLE\`
UNION ALL
SELECT 'V_DEMAND_RECAPTURE', COUNT(*),
       COUNT(DISTINCT CONCAT(campaign_id,'|',keyword_id))
FROM \`onyga-482313.OI.V_DEMAND_RECAPTURE\`"
```

Expected: `rows_ = pairs` on both.

- [ ] **Step 2: Add the columns to history, deploy, re-deploy the view, run every suite**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
ALTER TABLE \`onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY\`
  ADD COLUMN IF NOT EXISTS vehicle_format               STRING,
  ADD COLUMN IF NOT EXISTS vehicle_match_width          STRING,
  ADD COLUMN IF NOT EXISTS vehicle_creative_type        STRING,
  ADD COLUMN IF NOT EXISTS subject_search_click_share   FLOAT64,
  ADD COLUMN IF NOT EXISTS campaign_top_of_search_share FLOAT64,
  ADD COLUMN IF NOT EXISTS placement_grain_note         STRING,
  ADD COLUMN IF NOT EXISTS sales_recapture_rate         FLOAT64,
  ADD COLUMN IF NOT EXISTS net_genuinely_at_stake       FLOAT64,
  ADD COLUMN IF NOT EXISTS recapture_verdict            STRING,
  ADD COLUMN IF NOT EXISTS recapture_vehicles           STRING"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_KEYWORD_STATE.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/FACT_KEYWORD_STATE_acceptance.sql)"
/usr/local/bin/python3 -m pytest tools/tests/ -q
```

Expected: sixteen acceptance rows all `PASS`, and every Python test PASS.

- [ ] **Step 3: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/procedures/SP_SNAPSHOT_KEYWORD_STATE.sql \
        scripts/bigquery/tables/FACT_KEYWORD_STATE_HISTORY.sql \
        scripts/bigquery/views/V_KEYWORD_STATE.sql
git commit -m "feat(catalog): the vehicle dimension and the recapture answer on every subject

Closes violation 18. The Catalog can now say which vehicle carries a demand, and
can tell a destroyed sale from one that simply changed vehicle."
```

---

### Task 13.5: `CARRY · vehicle V` — the Brain's one allocation intent that is not about a phrase

**Files:**
- Modify: `scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql` (carry the vehicle columns)
- Modify: `scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql` (the `CARRY` intent)
- Modify: `scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql` C06

- [ ] **Step 1: Add the intent**

In the builder's move CASE, insert **above** the seat branches (a vehicle decision outranks a price decision because it decides which instrument the price applies to):

```sql
      -- ── CARRY · vehicle V (doctrine 3.2, 2.6) ──────────────────────────────────────────────
      -- "This demand should be bought through this format, placement or creative rather than
      -- another. Shift budget and bids toward V; DO NOT RE-OPEN THE CHOICE DAILY."
      -- A vehicle decision is slower-moving than a bid and belongs to the Brain, because it is an
      -- allocation question — which instrument carries the family's money — not an auction one.
      -- THE COOLDOWN IS THE POINT: a vehicle choice already made inside the last 28 days is held,
      -- not re-decided, which is what distinguishes CARRY from a bid move.
      WHEN r2.vehicle_target IS NOT NULL
       AND r2.vehicle_target != r2.vehicle_format
       AND (r2.prior_carry_date IS NULL
            OR r2.prior_carry_date <= DATE_SUB(as_of_d, INTERVAL 28 DAY))  THEN 'CARRY'
```

with `vehicle_target` resolved in `V_PLAN_WINDOW_JUDGMENT` as the vehicle with the best gross-profit return inside the same family and match width, over the settled window, with a materiality gate:

```sql
    -- the vehicle this family's demand should be bought through, where one is materially better.
    -- FAMILY x MATCH WIDTH grain, never per keyword — 2 forbids promising per-keyword precision the
    -- data cannot support, and a vehicle comparison at keyword grain is exactly that.
    -- MATERIALITY: a vehicle only wins if it returns at least 20% more gross profit per ad dollar
    -- than the one currently carrying the demand. A DECLARED CONSTANT: below that the difference is
    -- inside the noise of a two-value placement split and a type-only creative axis, and churning a
    -- vehicle costs the re-learning 4.1 describes for a campaign.
    vt.best_vehicle_format                                              AS vehicle_target,
    vt.best_vehicle_gp_roas,
    vt.current_vehicle_gp_roas,
```

fed by a CTE:

```sql
vehicle_choice AS (
  SELECT family, vehicle_match_width,
         ARRAY_AGG(vehicle_format ORDER BY gp_roas DESC LIMIT 1)[OFFSET(0)] AS best_vehicle_format,
         MAX(gp_roas)                                                       AS best_vehicle_gp_roas
  FROM (
    SELECT ks.family, vh.vehicle_match_width, vh.vehicle_format,
           SAFE_DIVIDE(SUM(ks.settled_gp90), NULLIF(SUM(ks.settled_sp90), 0)) AS gp_roas,
           SUM(ks.settled_clk90) AS clicks
    FROM `onyga-482313.OI.FACT_KEYWORD_STATE` ks
    JOIN `onyga-482313.OI.V_SUBJECT_VEHICLE` vh
      ON vh.campaign_id = ks.campaign_id AND vh.keyword_id = ks.keyword_id
    WHERE ks.snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
      AND ks.family IS NOT NULL
    GROUP BY 1, 2, 3
    -- a vehicle with too little traffic is not a comparison, it is an anecdote
    HAVING SUM(ks.settled_clk90) >= 100
  )
  GROUP BY 1, 2
),
```

and the materiality gate applied where `vehicle_target` is published:

```sql
    IF(vc.best_vehicle_gp_roas >= cur_v.gp_roas * 1.20, vc.best_vehicle_format, NULL)
                                                                        AS vehicle_target,
```

- [ ] **Step 2: Add `CARRY` to the enumerations and give it a sentence**

Add `'CARRY'` to acceptance C06's legal-move list, **to C14's list on whichever side it is issued** (C14 enumerates the moves a second time split by seat — see Task 6.2 Step 6; decide which side from the move's own arm before editing), and to the §9 sentence CASE from Task 8.7:

```sql
               WHEN 'CARRY'         THEN FORMAT('CARRY this demand on %s rather than %s',
                                                f.vehicle_target, f.vehicle_format)
```

- [ ] **Step 3: Deploy, run, verify the cooldown holds**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
ALTER TABLE \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
  ADD COLUMN IF NOT EXISTS vehicle_format STRING,
  ADD COLUMN IF NOT EXISTS vehicle_target STRING,
  ADD COLUMN IF NOT EXISTS carry_date     DATE"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`();
   CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`();"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT move, vehicle_format, vehicle_target, COUNT(*) n
   FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`
   WHERE as_of = (SELECT MAX(as_of) FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`)
     AND is_live_plan AND move = 'CARRY' GROUP BY 1,2,3"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql)"
```

Expected: `CARRY` rows only where a materially better vehicle exists, no row re-deciding a vehicle inside 28 days, and every acceptance row `PASS`.

- [ ] **Step 4: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql \
        scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql \
        scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql \
        scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql
git commit -m "feat(brain): CARRY - vehicle V, the allocation intent that is not about a phrase

Decided at family x match width grain with a materiality gate and a 28-day
cooldown, because a vehicle decision is slower-moving than a bid (3.2)."
```

---

### Task 13.6: Re-price the pause valuations, and close the doctrine's loop

**Files:**
- Modify: `architecture/THREE_LAYERS.md` (§10.1, §10.2 and the changelog)

- [ ] **Step 1: Re-price both figures this plan acted on**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT
  ROUND(SUM(sales_before_it_stopped), 0)   AS headline_sales,
  ROUND(SUM(sales_on_recaptured_terms), 0) AS recaptured,
  ROUND(SUM(sales_on_terms_nobody_took), 0) AS genuinely_lost_sales,
  ROUND(SUM(net_genuinely_at_stake), 0)    AS genuinely_lost_net,
  ROUND(AVG(sales_recapture_rate), 3)      AS avg_recapture_rate
FROM \`onyga-482313.OI.V_DEMAND_RECAPTURE\`"
```

Run the same test against the **ten paused campaigns** Phase 4 acted on, by joining `V_DEMAND_RECAPTURE` to the keywords inside them, and against the **seasonal-kill cohort** (79 keywords, $96,725 of Nov–Dec 2025 ads sales, $242.61 per season day) that Phase 5's argument rests on.

- [ ] **Step 2: Record the result whichever way it falls**

Update §10.1's paused-campaign and seasonal-kill rows to carry both the headline and the recapture-adjusted figure, and add a row to §10.2 — the "claimed and disproved" table — if the adjustment kills either claim. §10.2 exists precisely for this: *"knowing that the January trough was not a pricing failure is worth as much as any finding above, and a doctrine that quietly deleted its wrong answers would teach nothing."*

- [ ] **Step 3: Ask §2.6's grain-3 question, which nothing asks**

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "
SELECT ks.family, vh.vehicle_format,
       COUNT(*) subjects,
       ROUND(SUM(ks.settled_sp90)/90, 2) usd_per_day,
       ROUND(SAFE_DIVIDE(SUM(ks.settled_gp90), NULLIF(SUM(ks.settled_sp90), 0)), 3) gp_roas,
       ROUND(AVG(ks.family_bar), 3) bar
FROM \`onyga-482313.OI.V_KEYWORD_STATE\` ks
JOIN \`onyga-482313.OI.V_SUBJECT_VEHICLE\` vh
  ON vh.campaign_id = ks.campaign_id AND vh.keyword_id = ks.keyword_id
WHERE ks.family IS NOT NULL
GROUP BY 1,2 ORDER BY ks.family, usd_per_day DESC"
```

§2.6: *"should this family's money go to SB video or to SP?"* is a grain-3 question that nothing currently asks. Record the answer per family in the doctrine's §10 table.

- [ ] **Step 4: Add the changelog entry, per the doctrine's own instructions**

`architecture/THREE_LAYERS.md`'s "How to add an entry" is explicit: *amend the table in the same commit as the change; record the ruling and the evidence that moved it — a measurement, a failure, or an explicit decision by Ori — never just the diff.* Add one row recording that the vehicle dimension shipped, what the recapture test found, and which §10 figures moved as a result.

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI
git add architecture/THREE_LAYERS.md
git commit -m "docs(doctrine): re-price the pause valuations against recapture

The Catalog now knows what carries a demand, so a pause can be valued on the money
nobody else took rather than on the headline. Records the result whichever way it
fell, per 10.2's own reason for existing."
```

---

### Task 13.7: §8 tells the truth — every closed violation struck, every correction recorded

**Files:**
- Modify: `architecture/THREE_LAYERS.md` (§8, §10.3 and the changelog)

**This task exists because the failure it prevents is invisible.** Every phase closes violations in
code. If §8 is not amended in the same commits, then after all 91 tasks the **top document** — the one
the memory index tells every future session to start from — still lists 23 open violations against a
system that no longer has them, and the next reader spends a day rediscovering that. §8's own format
already shows how: violations 12 and 16 are struck through with a dated `**CORRECTED**` note.

The plan header makes striking a violation the **final step of the task that closes it**. This task
is the audit that the rule was followed, and the home for the two corrections that belong to no
single task.

- [ ] **Step 1: Audit — which violations are struck, and which are not**

```bash
cd /Users/ori/Develop/OI
sed -n '/^## 8\. Known violations/,/^## 9\./p' architecture/THREE_LAYERS.md   | grep -nE '^\s*[0-9]+\.' | sed -E 's/^([0-9]+):\s*([0-9]+)\.\s*(~~)?.*/violation   struck=/'
```

Every violation this plan closes must show `struck=~~`. Cross-check against the header's list, which
names the closing task for each. **A violation still open in §8 whose closing task is green is a
missing commit, not a missing fix** — go back to that task's commit step, add the strike and the
`git add architecture/THREE_LAYERS.md`, and amend forward with a new commit that says which.

- [ ] **Step 2: Record the two corrections this plan made to §8's own wording**

§10.3 is the file's record of *"what the research corrected in this document"* and already holds
three entries. This plan produced two more, and neither belongs to a single task's strike-through
because each corrects the **framing** of a violation rather than closing it:

1. **Violation 19's auto-mode framing is in the doctrine, not in the code.** §8 says term
   composition *"is treated as an auto-mode problem"*; Phase 7 established that no engine or view
   actually restricts drift handling to auto modes — the narrow framing is the doctrine's own, and
   BROAD carrying more money is a correction to the sentence rather than to a behaviour.
2. **Violation 21's "used by nothing" is measurably too strong.** Phase 11 established the precise
   claim: the search-query data is read, but **no layer reads the market columns** — `TOTAL_*`,
   `impression_share_pct`, `search_query_volume` — so no subject can be valued on demand available
   rather than demand captured. The violation stands; its sentence does not.

Write both as §10.3 entries in the file's existing shape: what §8 said, what was measured, what the
sentence should say instead, and the dated task that established it.

- [ ] **Step 3: One changelog row, and commit**

Per *"How to add an entry"*: record the ruling and the evidence, never just the diff. One row saying
that the gap-closure plan closed N of the 23 live violations, naming the two that remain open and
why, and pointing at
`docs/superpowers/specs/2026-08-25-gap-closure-measurements.md` for every number behind it.

```bash
cd /Users/ori/Develop/OI
git add architecture/THREE_LAYERS.md
git commit -m "docs(doctrine): section 8 tells the truth — closed violations struck, two corrections recorded

The audit that the per-task strike rule was followed, plus the two corrections to
section 8's own wording that belong to no single task: violation 19's auto-mode
framing is the doctrine's rather than the code's, and violation 21's 'used by
nothing' is too strong — the market COLUMNS are unread, not the table."
```

---

## Time estimate

**The measured pace of this project**, from the sessions behind the seat register, the money plan and the baseline: a comparable single task with adversarial verification took **1–3 hours**; a repair round after a failed verification took about **45 minutes**. "Three-lens verification" below means the three passes this project already uses on every task — re-run the assertion, attack the causal story, and check the house conventions (deploy line, backup, registry, idempotency, Standing Rule 0).

| phase | tasks | build (h) | verification (h) | repair allowance (h) | total (h) | calendar |
|---|---|---|---|---|---|---|
| 0 — start both clocks | 6 | 8 | 4 | 2.25 | **14.25** | 1–2 days |
| 1 — precedence and a binding ceiling | 5 | 12 | 6 | 1.88 | **19.88** | 3–5 days |
| 2 — everything that spends is judged | 4 | 22 | 11 | 1.5 | **34.5** | 1–1.5 weeks |
| 3 — campaign identity | 6 | 9 | 5 | 2.25 | **16.25** | 2–3 days |
| 4 — the campaign becomes a subject | 8 | 32 | 15 | 3 | **50** | 1.5–2.5 weeks |
| 5 — seasonality reaches the verdict | 8 | 47 | 23 | 3 | **73** | 2.5–3.5 weeks |
| 6 — the Brain | 11 | 54 | 27 | 4.12 | **85.12** | 3–4 weeks |
| 7 — confidence | 7 | 36 | 18 | 2.62 | **56.62** | 2–2.5 weeks |
| 8 — the four-field contract | 7 | 24 | 12 | 2.62 | **38.62** | 1.5–2 weeks |
| 9 — negatives | 5 | 20 | 10 | 1.88 | **31.88** | 1–1.5 weeks |
| 10 — the response curve, and two layers graded | 8 | 36 | 18 | 3 | **57** | 2–3 weeks* |
| 11 — demand data on probation | 5 | 16 | 8 | 1.88 | **25.88** | 1–1.5 weeks |
| 12 — rank() | 4 | 22 | 11 | 1.5 | **34.5** | 1.5–2 weeks |
| 13 — the vehicle | 7 | 31 | 15.5 | 2.62 | **49.12** | 2–3 weeks |
| **total** | **91** | **369** | **183.5** | **34.12** | **586.62** | — |

**Roughly 587 hours of engineer time.** Verification is budgeted at half of build throughout, which is what this project's own history supports for work that touches money. The repair allowance is 45 minutes per task, on the assumption that roughly half of all tasks need one round.

**\*Phase 10's calendar is gated on elapsed time, not effort.** It cannot start until Phase 0's recording has accrued enough paired predictions to fit a curve — Task 10.1's readiness gate is the check. If Phase 0 ships on day one and Phase 10 starts at week 20, the data will be there; if Phase 0 slips, Phase 10 slips by the same amount regardless of how much engineering capacity is available.

**The critical path is Phases 3 → 4 → 5**, and it has a **calendar deadline nothing else has**: §4.1's lead time means the November answer must be readable in October, with campaign re-enable time on top. Working backwards from a peak that opens in mid-November: Phase 5 must land by roughly **mid-October**, Phase 4 by **late September**, Phase 3 by **mid-September**. Phases 0, 1 and 2 sit ahead of them and total about 69 hours — under two working weeks — so the sequence fits, but the margin is thinner than it was: Phase 2's guard re-key and Phase 5's `ask()` function are both on the critical path and both grew in the last repair pass. It fits only if it starts promptly.

**If a phase must slip, slip Phase 9 (negatives) or Phase 13 (vehicle).** Nothing downstream waits on either.

---

## Open rulings — carried as declared constants, and Ori's to decide

§6.4 records four open rulings. **This plan decides none of them.** Each is seeded as a declared constant with a note naming it as Ori's and recording that it is unsettled, plus a §6.1 experiment where one applies — *declare the question before running it, so the result cannot be read after the fact to suit a preference.*

### 1. The park re-test cadence — **ORI'S, OPEN**

*How often, and how much, to buy fresh evidence on a parked subject (§3, §6.4).*

- **Where it is seeded:** `DE_PLAN_CONFIG`, Task 6.7 — `park_retest_days 28`, `park_retest_clicks 10`.
- **Why those seeds and not an answer:** 28 days is one full attribution cycle plus a margin; 10 clicks is the guard's own `min_settled_clk` and the exact number `V_PARK_REVERDICT` requires to REVIVE, so a funded re-test buys precisely the evidence the revival gate demands and not a click more.
- **The §6.1 experiment, declared:** setting `park_retest_days`, tested at 28 against 14 and 56; slice a random half of the HARVEST families' parked subjects; outcome net profit over the treated slice across two cadence cycles against the untreated half of the same families; by when, two cycles at the longest arm — 112 days from the day it starts.
- **Never the control arm.** `DE_HOLDOUT_ASSIGNMENT`, arm `HOLDOUT`, `eligible_from 2026-09-01`.

### 2. The boost allowance share, 0.50 — **ORI'S, OPEN AND FLAGGED UNPROVEN**

*§6.4 lists it as "open — flagged unproven".* `DE_PLAN_CONFIG.sql:115` already carries Ori's own words: *"Ori is not sure 0.50 is right — the scorecard and the backtest answer it per state."*

- **This plan does not change it.** It builds the named instrument instead: `V_PLAN_SCORECARD` (Task 6.10), which is named in four documents and existed as neither a file nor a BigQuery object.
- **§6.1 says ask the free version first.** The shadow plan runs a second allocation rule every night at no cost, and `V_PLAN_SCORECARD` compares them at a settle-safe gate. The question is answered there before anything is asked of real money.
- **It cannot be answered until BOOST partitions exist and have aged past the gate** — which is honest, and is why the ruling stays open rather than being quietly closed.

### 3. Rule 4's volume floor for coverage tests — **ORI'S, OPEN**

*§2.9: "a term nobody searches is never worth re-testing."*

- **Where it is seeded:** `V_CATALOG_IMPROVE`, Task 9.5 — against **our own impressions**, because the correct source did not exist yet, and §6.3 forbids asserting a number we have not computed.
- **Re-based in Task 11.5** onto `V_SRC_MARKET_VOLUME.avg_weekly_search_volume` — the market's demand for the query, which is what §2.9 actually means — seeded at `retest_market_volume_weekly 200`.
- **The §6.1 experiment, declared:** setting `retest_market_volume_weekly`, tested at 200 against 50 and 1000; slice the negatives coming due inside one family per arm, on **disjoint families** so the arms cannot contaminate each other (§6.2); outcome net profit on the unblocked terms over one full peak window; by when, the end of the first peak in which all three arms have run.

### 4. The park price source — **ORI'S, OPEN**

*The engine's published `bid_park` and the channel floor differ materially.*

- **Both measured sides are on the record** (Task 6.8): rows resolved from `T_OOB_SEAT_ECONOMICS.bid_park` averaged $0.250 against a $0.182 floor, maximum ratio 2.50x, 286 of 312 above the floor; 418 rows resolved from the floor fallback price exactly at it.
- **What is implemented is the ordered fallback already in `tools/build_seasonal_unpause_bulksheet.py:22-33`**, not a choice: (1) the engine's `bid_park` where it exists; (2) otherwise the ad group's channel + creative floor; (3) an engine park price **below** the floor is raised **up** to it, never down; (4) a subject neither resolves for is **refused loudly**, never priced at a literal. `bid_park_source` is published so which arm answered is always visible.
- **The one behavioural half this plan does ship** is rule 4: an assertion that a parked keyword with no resolvable price aborts the build rather than being priced at a guess.

### Deliberately not built

- **The agreement-tier ranking (§6.4).** Deferred by Ori pending a real case: a confirmed candidate with real money queued behind a lower-ranked disputed one that got funded. At the time of deferral every confirmed candidate in the queue carried $0 at stake. **Do not build it.** Phases 6 and 10 both touch the ranking expression and must leave the agreement question untouched.
- **Violations 12 and 16.** Struck through in §8 as CORRECTED by the baseline; no task against either. **12:** the entire Catalog-to-Brain coverage gap is deliberate (launch families plus brand defense), there is no hole, and the real uncovered money is Catalog-side in violation 4. **16:** the cap is not symmetric-and-slow, it is **not enforced in either direction**, and cuts break theirs proportionally more often than raises break theirs. §10.3's replacement finding is implemented inside Phase 1 as the mechanism violation 15's fix requires, and is **not** presented as closing violation 16.
- **The orchestrator lag.** `SP_ORCHESTRATE_DAILY_REFRESH.sql:2282-2287` records that the proposal snapshot (20.6) and preflight (20.7) run **earlier** in the pass than the keyword state machine (20.8) and the plan build (20.8c), so Pacing reads the plan one pass late. Closing it means moving another owner's tasks and is explicitly an open ruling for Ori. **No phase may close it as a side effect** (Task 6.11 checks this). Related standing constraint: `SP_SNAPSHOT_FAMILY_BAR` (task 20.5g-1) must stay **ahead** of every reader of `V_KEYWORD_LIFT`, or the engine prices yesterday's halo with no error and no alarm.
- **The account's total budget.** Deliberately outside the doctrine (§1.2, Ori 2026-08-24). The Brain allocates within a family's pot and the total emerges from the parts. No phase proposes a total.
- **SQP as a new-candidate generator.** §10.3 corrected §2.4's premise: measured over twelve weeks, SQP proposes roughly one fundable keyword per quarter. The mechanism in §2.4 stands; its assumed input does not. Phase 12 sources new candidates from the harvest gap instead, and Phase 11 builds SQP for headroom and curve ceilings rather than for discovery.
- **The verdict ladder's bar and the floors.** `T_FAMILY_BAR.keyword_bar` and `FN_BID_FLOOR` / `V_BID_FLOOR` are not changed by any phase except where a task says so explicitly: Phase 4 widens the **population** `T_FAMILY_BAR` covers without touching how the bar is computed, and Phase 2 fixes the ad-group resolution that feeds the floor without changing the floor values ($0.20 SP / $0.25 SB video / $0.10 SB collection).
- **Files owned by the concurrent session.** `dashboard-react/src/pages/PlanPage.tsx`, `scripts/bigquery/procedures/SP_MERGE_PRODUCT_DIM.sql`, `scripts/bigquery/views/V_FORECAST_DEMAND.sql`, `docs/superpowers/specs/2026-07-19-launch-ramp-forecast-design.md`. Never staged, reverted or committed. Phase 8 therefore lands §9's row shape and sentence only; the UI that consumes it is not this plan's to ship.

---

## Risk

### What could break production, and what contains it

| risk | which tasks | what contains it |
|---|---|---|
| **A nightly pass fails and the account runs on stale decisions.** | every task that deploys a procedure the orchestrator calls | Each orchestrator `CALL` is wrapped in `BEGIN ... EXCEPTION`, logs `FAIL` to `LOG_PIPELINE_RUNS`, and lets the pass continue. `SP_BUILD_NEXT_WEEK_PLAN`'s assertion block runs **above** its `DELETE`, so a failed build leaves yesterday's partition standing rather than writing a bad one. Verify after every deploy with the `LOG_PIPELINE_RUNS` query in Task 4.6. |
| **A bad price reaches Amazon.** | 1.2, 1.3, 6.4, 7.5, 8.6 | Nothing in this plan uploads. Every book lands `PENDING_UPLOAD` and Ori uploads by hand. Phase 1's ceiling arm and `FN_MOVE_CAP` are the second net, and Phase 7's HIGH-confidence gate is the third. |
| **An irreversible action on thin evidence.** | 2.4, 4.5, 5.7, 7.5, 7.6 | Phase 2 does **two** things, because the `NO_RECORD` arm alone shields only zero-click subjects and 75 of the 321 newly admitted pairs carry ≥ 15 settled clicks with no orders: the `NO_RECORD` arm, **and** a `universe_source != 'SPEND'` predicate on the `DEAD` and `LOSER` arms so a spend-admitted subject is judged but never killed. Task 7.5 Step 1 deletes that predicate and replaces it with the confidence band. Phase 5 carries its own instance of the same rule: Task 5.7 deletes the reprice book's `SEASON_BLOCKED` arm, which is a live pause **suppression** and not a label, so Task 5.6 Step 3b must move the `BLOCK_CUT` ruling into the ladder FIRST and Task 5.7 Step 0 asserts `would_become_a_pause = 0` before the deletion. Phase 4 withholds CLOSE entirely; Phase 7 gates all three emitters on HIGH confidence and asserts it in SQL (K14) and in the builder. |
| **`V_KEYWORD_STATE` goes stale and a book fails on a `KeyError`.** | 2.3, 2.4, 5.5, 7.3, 7.4, 8.2, 10.3, 11.4, 13.4 | `V_KEYWORD_STATE` is `SELECT *` and freezes its schema at CREATE time. **Every task that adds a column re-deploys it in the same step** — that instruction appears in each of those tasks, not once. |
| **A schema change breaks one of 27 readers.** | the same tasks | Adding columns is safe for all of them; **renaming or removing is not**, and no task in this plan renames or removes one. Task 2.4 Step 7 dry-runs ten views and the full Python suite after the first large addition. |
| **A procedure called twice in one pass fails on a bare temp table.** | 0.1, 4.5, 6.11 | The 2026-08-24 cube outage is the precedent. Task 0.1 converts the three known offenders, Task 4.5 uses `CREATE OR REPLACE TEMP TABLE` throughout, and Task 6.11 greps for regressions. Every new procedure is called twice in its own verification step. |
| **A partition split across two days by a timezone edge.** | 0.3, 0.5, 4.5 | `FACT`/`V_` objects are Los Angeles dated; the orchestrator runs on New York. Every append deletes and inserts on **the value already on the row**, never a freshly computed `CURRENT_DATE()`. A pass starting after 21:00 New York would otherwise split one snapshot across two partitions. |
| **A widened population silently changes the bar.** | 4.2 | Two different risks, and the clamp check only sees the first. (a) The bar **computation** is unchanged; the clamp is verified at **5e-5**, because `keyword_bar` is `ROUND`ed to four decimals and a tighter assertion produces false failures. (b) The bar's **input** can move: `asin_fam` picks a family by dominant spend, so a two-year corpus can flip an existing campaign's `parent_name` — and a bar that moves from 0.84 to 0.91 passes the clamp, passes the tolerance, and moves the ceiling on every keyword in that campaign. Task 4.2 **Step 4b** captures `parent_name` and `keyword_bar` per campaign before the deploy and asserts `family_flipped = 0` and `bar_moved = 0` after it. Measured 2026-08-24: 0 of 130. |
| **Two live method experiments in one family destroy the measurement.** | 6.7, 9.5, 10.5, 11.3 | §6.2: one layer experiments at a time within a family, or the experiments run on disjoint families. Every declared experiment in this plan names disjoint families and excludes the holdout arm explicitly. |
| **A one-sided metric manufactures a loss that is not there.** | 6.1, 10.7, 13.6 | §6.3. Every task that reports a `GREATEST(actual − target, 0)` sum reports the **net** beside it. The "$210/day over bar" claim died on exactly this. |
| **Concurrent-session files staged by accident.** | every commit step | Every `git add` names its files explicitly. Never `git add -A`, never `git add .`. |
| **A synthetic id reaches Amazon.** | 2.3, 9.2 | Phase 2 keeps `keyword_id` meaning what Amazon means and puts the Catalog's own key in `subject_key`; Phase 9's archive book refuses a `neg_<md5-12>` id by name and reports it rather than substituting a text match. |
| **A blank Portfolio ID detaches a campaign.** | 4.7 | On a Campaign Update row a blank Portfolio ID is a **detach**, not "unchanged". Both campaign books echo the campaign's current `portfolio_id` on every row. |

### Tasks that touch the nightly orchestrator

Exactly **four**, and every one is called out here so a reviewer can check them first:

1. **Task 0.1** — converts three bare `CREATE TEMP TABLE` statements in `SP_SNAPSHOT_KEYWORD_STATE` to `CREATE OR REPLACE TEMP TABLE`. Zero behavioural change; it makes an existing failure mode go away.
2. **Task 0.3** — appends an arm to the tail of `SP_SNAPSHOT_KEYWORD_STATE` (orchestrator task 20.8). Append-only, `DELETE`-today-then-`INSERT`, no verdict changes.
3. **Task 0.5** — adds four columns and one temp table to `SP_SNAPSHOT_ENGINE_PROPOSALS` (orchestrator task 20.6). Recording only.
4. **Task 4.6** — **the only task that adds a new orchestrator slot**: `SP_SNAPSHOT_CAMPAIGN_STATE` as task 20.5g-1's successor, after `SP_SNAPSHOT_FAMILY_BAR` and before `SP_BUILD_NEXT_WEEK_PLAN`. Wrapped in `BEGIN ... EXCEPTION` with a `LOG_PIPELINE_RUNS` row like every neighbour, and its position is stated in the procedure header relative to 20.5g-1, 20.7 and 20.8.

Tasks 1.2, 1.3, 2.2, 2.4, 5.5, 5.6, 6.2–6.9, 7.3–7.6, 8.2, 8.6, 9.4, 10.3, 11.4 and 13.4–13.5 modify procedures or their inputs that the orchestrator **already calls**; they change no ordering and add no slot. Task 1.3 Step 5 is the one of these that touches a **second** orchestrator procedure — `SP_SNAPSHOT_ENGINE_PROPOSALS`, task 20.6, which Task 0.5 also modifies — and it is recording-only there, exactly as Task 0.5 was. Every one of them is verified by calling the procedure twice and re-running its acceptance suite.

**After any orchestrator change, run one full pass and check the log** before moving on:

```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CALL \`onyga-482313.OI.SP_ORCHESTRATE_DAILY_REFRESH\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT procedure_name, status, duration_seconds, error_message
   FROM \`onyga-482313.OI.LOG_PIPELINE_RUNS\`
   WHERE run_date = CURRENT_DATE() AND status != 'OK' ORDER BY started_at"
```

Expected: **zero rows**.

---
