# Unowned spend — the money the three layers cannot see

**Status:** measurement shipped 2026-08-25. **The fix is not shipped and has not been decided.**
Read `THREE_LAYERS.md` first — this document derives from it and never overrides it.

| object | what it is |
|---|---|
| `V_UNOWNED_SPEND` | one row per spending **subject** — `(campaign_id, keyword_id, targeting)` — with no row in `FACT_KEYWORD_STATE` |
| `V_UNOWNED_SPEND_SUMMARY` | the account-level number, one row per reason class plus a grand total under `reason_class = '__ALL__'` |
| `scripts/bigquery/tests/V_UNOWNED_SPEND_acceptance.sql` | the ten assertions that keep both honest |

---

## 1. What this is for

`FACT_KEYWORD_STATE` is where the Catalog's universe is materialised. A subject with no row there
is invisible to **all three layers at once**: the Catalog never valued it, the Brain never funded
it, Pacing never priced it, and no park, no ceiling, no bid change and no stop can ever reach it.
It spends anyway.

Nothing in the warehouse reconciled the ads feed's spenders against that universe, so this
population could only be found by someone going looking — which is how the §10 baseline found it,
once. These two views make it a number a person watches every morning instead of a discovery
somebody makes every quarter.

**This is the measurement half and only the measurement half.** Read §5 before doing anything else
with it.

## 2. The four reasons a subject can be invisible

Precedence is top-down: a row takes the **first** arm that matches, which makes the classification a
partition rather than a set of tags. The order is by **what binds** — a target inside a paused
campaign cannot be made visible by fixing the target, so the campaign-level reason wins.

### 1. `SENTINEL` — the id is not an id

SB product targets arrive in `FACT_AMAZON_ADS` under `keyword_id = '-1'`. That is a sentinel, not an
Amazon target id: every product target in the campaign shares it, so no `(campaign, keyword)` key
exists for any of them and none can ever join `DIM_KEYWORD`. This is the one class where the subject
is not merely missing from the universe — it is **unrepresentable** in the key the universe is built
on. It is also the class that spends the most today, and the one where the 7-day figure is closest
to the 28-day figure, meaning the money is leaving now rather than decaying.

*To close it:* SB product targets must be keyed on campaign plus target text, or resolved to their
real target ids, **before** `V_KEYWORD_GUARD` builds the universe.

### 2. `CAMPAIGN_OUTSIDE_UNIVERSE` — the campaign is outside

Two reasons live here. `CAMPAIGN_ABSENT_FROM_DIM`: the campaign has no row in
`V_DIM_CAMPAIGN_CURRENT` at all. `CAMPAIGN_NOT_ENABLED`: it has one and the state is not `ENABLED`.
The universe is built from enabled campaigns only, so every target underneath falls out with it.

Most of this class is **a tail, not a leak** — spend booked before the campaign was paused, still
sitting inside a 28-day average and decaying to nothing on its own. That is exactly why every row
and every summary line carries the 7-day figure beside the 28-day one. A row in this class that is
*still* spending is the interesting case: the dimension and the ads feed disagree, and the feed is
what to check.

### 3. `SUBJECT_OUTSIDE_UNIVERSE` — the target is outside

`SUBJECT_ABSENT_FROM_DIM_KEYWORD`: no `DIM_KEYWORD` row exists, current or historical.
`SUBJECT_NOT_ENABLED`: a row exists but there is no `is_current` row in state `ENABLED`. Again a mix
of tails and live spenders, and again the 7-day column is what separates them. A subject that reads
paused in the dimension while still spending today means either the dimension is stale or the target
was re-enabled outside our books.

### 4. `DROPPED_DOWNSTREAM` — it passes every gate and is still not there

`IN_UNIVERSE_NO_STATE_ROW`: an enabled target in an enabled campaign, spending, and the state build
produced no row for it. This is a **defect in `SP_SNAPSHOT_KEYWORD_STATE` or its inputs**, not a
wiring gap, and it should be treated differently from the other three: nothing needs deciding,
something needs fixing. The arm exists whether or not it is populated today — an empty bucket that
starts filling is a signal, and deleting it would destroy that signal.

**The gates in classes 2 and 3 are not invented here.** They are `V_KEYWORD_GUARD`'s own `kw` CTE,
which is what defines the universe `FACT_KEYWORD_STATE` is built from. If that CTE changes,
`V_UNOWNED_SPEND` must change with it or it will start giving the wrong reason — a confident wrong
reason, which is worse than none.

## 3. How to read it without misreading it

**Read the two windows together.** `spend_per_day_28d` is the headline and matches the shape of the
baseline figure it descends from. `spend_per_day_7d` is the live half. They diverge a great deal
between classes, and the divergence is the most informative thing in the view. A total quoted with
only one of them is a number that will be argued about — correctly.

**Read the share, not only the dollars.** `share_of_account_pct_28d` / `_7d` survive the account
changing size, and per `THREE_LAYERS.md` §10.5 the share is what a re-measurement compares.

**`days_in_current_run` is days of SPENDING, not days unowned.** It cannot be days unowned: the
Catalog is replaced nightly and keeps one snapshot (violation 6), so nothing in this warehouse knows
what `FACT_KEYWORD_STATE` held last month. A long run means the money is old. It does not mean the
hole is that old, and the view must never be quoted as if it did.

**Nothing here is a verdict, and that is deliberate.** Where the campaign maps to a family, the row
prints `family_bar` beside `gp_roas_28d` and one `gp_roas_minus_bar_28d` distance, and stops. Where
it does not, those columns are `NULL` and `judgeability` says why. `verdict_withheld_because` is
never blank on any row. The reason is doctrine, not modesty: §1.1 — a catalog does not issue
commands, and this is not even a catalog, it is a census of subjects the Catalog has never met.

**Unmeasured never reads as bad.** `reading` is `NO_EVIDENCE` at zero clicks and `THIN` below the
declared `min_clicks_for_a_reading`, which is derived as roughly the clicks that produce one expected
order at this account's own conversion rate. Below that a zero return is the ordinary outcome of a
perfectly good subject. No bar distance is published for such a row at all — the acceptance suite
asserts it (A7). A large `unjudgeable_spend_per_day_28d` is a fact **about the hole**, not about the
subjects inside it.

## 4. Provenance, and where it improves on the baseline

The population test — left-join the window's spending `(campaign_id, keyword_id)` pairs to
`FACT_KEYWORD_STATE`, keep the misses — is reproduced exactly from the `OUTSIDE THE CATALOG ENTIRELY`
probe in `docs/superpowers/specs/2026-08-24-three-layers-baseline.md`. Assertion A10 re-runs that
probe inside the suite and requires the pair count and the spend to match, so the lineage is checked
rather than claimed. Four things are different, each on purpose:

1. **Target grain.** The baseline counts `(campaign, keyword)` pairs, which under the sentinel
   collapses every product target in an SB campaign into one row — the largest baseline row is a
   bundle. Here a product target is its own subject (§2.1). The pair count is still recoverable and
   still reconciles; regrouping moves no dollars.
2. **Two windows.** The baseline quotes 28 days only, which cannot tell a live leak from a tail.
3. **A classified reason.** The baseline says how much; without a why it cannot be acted on.
4. **No substitute bar.** The baseline scored the population against 0.8431 — the median of the six
   live family bars — and marked exactly that figure MEDIUM, for exactly the right reason: these
   subjects do not own that bar. This view refuses the substitute and leaves the column `NULL`.

## 5. Closing the gap is Ori's decision, and it has NOT been made

Everything above is **reporting**. Both views read; they write nothing, they are read by no engine,
no book and no generator, and neither is in the orchestrator. Asking changes nothing (§1.4), and
assertion A9 proves it against `INFORMATION_SCHEMA` on every run.

Wiring these subjects **into** the universe would change what the account does — it would give them
verdicts, seats, ceilings, parks and stops, and money would move as a result. That is a decision for
Ori with this evidence in front of him, not a consequence of having measured it. Until he makes it:

- do **not** add these subjects to `FACT_KEYWORD_STATE`, `FACT_PLAN_NEXT_WEEK` or any book;
- do **not** change `V_KEYWORD_GUARD`, `SP_SNAPSHOT_KEYWORD_STATE` or the Catalog's universe;
- do **not** add either view to the orchestrator. A view is inert; keeping it inert is the point.

The four classes do not all pose the same question, and the decision is probably not one decision:
`SENTINEL` needs a key that does not exist yet, `CAMPAIGN_OUTSIDE_UNIVERSE` is mostly a tail that
needs nothing, `SUBJECT_OUTSIDE_UNIVERSE` is a disagreement between a dimension and a feed, and
`DROPPED_DOWNSTREAM` is a bug. Read the summary by class before treating the total as one problem.

## 6. Re-running it

House rule — never `cat` a `.sql` into `bq`:

```
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "$(grep -v '^--' scripts/bigquery/tests/V_UNOWNED_SPEND_acceptance.sql)"
```

Every row must read `pass = TRUE`; `violations` is a count, so a failure says how big it is. The
suite was written failing-first against a deliberately broken deployment and returned measured
violations on A1, A2, A3, A4 and A10 before the real view was deployed.

The daily number, and the only figure that should ever be quoted (Standing Rule 0 — no measurement
is pinned in this document):

```
SELECT * FROM `onyga-482313.OI.V_UNOWNED_SPEND_SUMMARY` ORDER BY reason_class;
SELECT sentence FROM `onyga-482313.OI.V_UNOWNED_SPEND` ORDER BY spend_per_day_28d DESC LIMIT 10;
```

## 7. What this still cannot say

- **How long any of it has been unowned.** Violation 6 blocks it, as it blocks the measurement of
  almost everything else. `days_in_current_run` is the honest substitute and is not the same thing.
- **Whether any of it should be running.** No family, no bar, no verdict — and even where a bar
  exists, a bar comparison is not a verdict, it is a distance.
- **What it would earn if a layer did see it.** That is a counterfactual, and §6.3 forbids asserting
  one without testing the innocent explanation.
