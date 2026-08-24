# KEYWORD_STATE — the roadmap of each keyword

**Born:** 2026-08-16 (engine-finalization plan Task 2.1). **Owner request:** "the roadmap of each
keyword" — every keyword in exactly ONE state, with exactly ONE owner, and always ONE NEXT
APPOINTMENT (a date on which something will re-judge it).

**v27.104 (2026-08-22): THE FLOOR RULING — SHIPPED.** Ori, verbatim: "floor question bid-up-to-floor
if after a few days still loosing kill it" and "i think it is not 0.25 (we already checked it)". One
floor per channel and creative (`FN_BID_FLOOR` via `V_BID_FLOOR`), affordability in BID space,
`FLOOR_PROBATION`, the kill only at the floor after an elapsed probation, and the guard extended to
AT_BAR's standing price. Gate: `SIM_2026-08-22_ladder_floor_probation.sql` (TMP_SIM_LADDER_FLOOR) —
the SP reproduced it **855/855 exact, 0 differing** on the consistent 2026-08-22 snapshot chain.

**v27.103 (2026-08-22): THE BAR/SE LADDER.** Four Ori rulings plus the clean-then-judge guard,
gated on the A1 clean-rerun simulation (`scripts/bigquery/simulations/SIM_2026-08-22_ladder_clean_rerun.sql`,
result table TMP_SIM_LADDER_CLEAN — SP output verified 854/855 exact key-level agreement; the one
difference is the PACED_WINNER overlay reading today's live pace instruction, by design).

## Objects

| object | role |
|---|---|
| `SP_SNAPSHOT_KEYWORD_STATE` | Assembles reverdict/ownership/pacing verdicts from the other snapshots AND owns the bar/SE judgment (the one place the account says what a keyword's record is worth against its family's bar). Orchestrator Task 20.8, after the preflight (20.7) and after `SP_SNAPSHOT_FAMILY_BAR`. Reads FACT_AMAZON_ADS at term grain for the guard (~40s). |
| `FACT_KEYWORD_STATE` | One row per (campaign, keyword): state, owner, next appointment, settled record, bar machinery (family_bar, se_eff, N_f, affordable_cpc, click sufficiency), guard columns (ns_share, cleaned record, negate-valve population), season context, view-authored reason. |
| `V_KEYWORD_STATE` | Thin read surface. No logic. `SELECT *` freezes schema — redeploy it with every FACT column change. |
| `FN_BID_FLOOR` / `V_BID_FLOOR` | The ONE floor definition (channel × creative) and its per-ad-group resolution; the SP reaches it through `DIM_KEYWORD.ad_group_id` (unresolved ad group → `FN_BID_FLOOR(channel, NULL)`, source suffixed `_NO_ADGROUP`). |
| `V_BID_CPC_TRANSFER` | `m_effective` (MAX over target kinds per campaign) — the A4 placement translation from affordable CPC to affordable BID, done once in the SP (`affordable_bid`, `clean_affordable_bid`). |
| `FACT_KEYWORD_STATE_HISTORY` | THE MEMORY (v27.143). Append-only, partitioned by `snapshot_date`, clustered on `keyword_id` first. One row per (snapshot_date, campaign, keyword) holding the WHOLE snapshot row. No engine, generator or book reads it. |
| `SP_APPEND_KEYWORD_STATE_HISTORY` | The write step. Orchestrator Task 20.8a, immediately after 20.8. Append-first, idempotent, schema-evolving. Cannot break the pass. |
| `V_CATALOG_DWELL` | How long a subject has been in its state, what it changed from, how overdue its appointment is — with an explicit basis, never a bare number. Reads the history only. |
| `tools/build_reprice_bulksheet.py` | THE ONLY EXECUTOR. NO ENGINE reads the state table — the new states move bids exclusively through the manual reprice book Ori uploads by hand. |

## THE HISTORY — the Catalog's memory (v27.143, 2026-08-24)

**What was wrong.** `SP_SNAPSHOT_KEYWORD_STATE` builds `FACT_KEYWORD_STATE` with `CREATE OR REPLACE
TABLE`. The table therefore holds exactly one snapshot, and every orchestrator pass — several a day
— destroyed the previous one permanently. `THREE_LAYERS.md` records this as violation 6, and §10.4
names its consequence as the single highest-value thing in the account to fix first: with one
snapshot, **no "how long has this been stuck" question is answerable anywhere**, which obstructs
the measurement of every other violation. §6.2 states the second consequence: *a layer cannot be
graded on predictions it does not keep*, so the Catalog's own scorecard — "was the valuation
right?" — was not merely unbuilt, it was impossible.

**What was built.** Three objects, all ADDITIVE. Nothing in the ladder's verdicts, the bar, the
floors or the book changed; the history records what was already being recorded and nothing reads
it that can act.

### What the history keeps, and why the whole row

The whole snapshot row, plus provenance. The temptation is a narrow `(date, subject, state)` table,
which is much smaller and answers dwell. It cannot answer the question §6 actually poses. A
prediction is not the label — it is the verdict **together with the evidence and the arithmetic
that justified it**: the settled record it was read off, the family bar it was judged against, the
noise band that decided whether the gap was real, the affordable price and the floor that made the
move executable or not, the guard's cleaned re-reading, and the appointment the ladder promised. "In
August you said this keyword's price was X — was it?" needs X, not `REPRICE`. The storage argument
runs the other way from intuition: this table is small, and a column not kept is a column that can
**never** be recovered, because the source is destroyed nightly.

Three provenance columns say where each row came from, so a recovered row is never mistaken for a
live-appended one: `captured_at` (when the row was written here — *not* when the Catalog computed
it, which is `snapshot_date`), `source` (`ORCHESTRATOR` | `BACKFILL_TIME_TRAVEL`), and
`source_detail` naming exactly what was read.

### Schema evolution — §2.7, §2.8 and §4 are columns that do not exist yet

`confidence` (§2.7), market volume (§2.8) and seasonality (§4) will all add columns to the ladder.
The append step contains **no hard-coded column list**. Every run it reads the live column set of
`FACT_KEYWORD_STATE` from `INFORMATION_SCHEMA`, issues `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`
for anything the history lacks, and inserts **by column name**. So:

- a column the Catalog gains tonight is in the history tonight, with no edit to any file;
- partitions written before that night keep NULL for it — the honest reading, since the Catalog did
  not say it then, and a backfilled value would be a fabrication;
- a column REMOVED upstream is never dropped here; it keeps what it held and goes NULL going
  forward. Append-only means the record of a retired field outlives the field.

The seeded partitions already prove this: the earliest ones come from a 22-column era of the
procedure and sit in the same table as the current wide rows, neither distorting the other. Confirm
the eras with a `COUNTIF(family_bar IS NOT NULL)` grouped by `snapshot_date`.

One name collision is deliberately left LOUD rather than silent: if the ladder ever publishes a
column called `captured_at`, `source` or `source_detail`, the generated INSERT names it twice and
the step errors. The orchestrator logs FAIL, the pass continues, and a person renames the column.
Silently dropping it would put a hole in the memory no later run could fill.

### Idempotency — and why the order is append-then-prune

Assume any procedure may be called twice a night; the orchestrator already calls
`SP_MAINTAIN_FAMILY_SEATS` a second time each pass through `SP_REFRESH_CUBE_TABLES`. The step
therefore:

1. **INSERTs** the whole snapshot, stamped with this run's `captured_at`;
2. **PRUNEs**: within any `snapshot_date` now carrying more than one `captured_at`, keeps the newest
   stamp and drops the rest.

Two passes on one `snapshot_date` leave exactly one copy. The order is not arbitrary. A
delete-then-insert has its failure pointing the wrong way — a crash between the statements destroys
a day of memory, which is the exact defect this object exists to end. Append-first can only ever
leave a duplicate.

**That duplicate is repaired by any later call, on any date** (v27.144). The prune used to be keyed
on whichever `snapshot_date` the live snapshot happened to carry, which made the self-healing
conditional in exactly the case it was claimed for: `snapshot_date` is
`CURRENT_DATE('America/Los_Angeles')`, so a strand left when the INSERT succeeded and the prune
failed on the *last* pass of an LA day could never be reached again — every later pass carried a
different date. It is now stated as the invariant it always meant: **a `snapshot_date` holds exactly
one `captured_at`, and the newest wins.** The prune runs before the append as well as after, so a
call that adds nothing today still heals a strand left by an earlier one. `C12` is the alarm.

**A pass may not restamp a build the history already holds** (v27.145). Task 20.8 sits in its own
`BEGIN ... EXCEPTION` block, so a pass where the snapshot build FAILS still reaches 20.8a — with the
previous build's table standing. Re-copying it would move that partition's `captured_at` and give it
a `source_detail` naming a read time at which the Catalog said nothing new: the rows identical, the
provenance a lie. GUARD 3 refuses it.

**The guard tests the build, not the calendar.** Its first shape asked only whether the snapshot's
date was older than the current LA date. That left it blind for the whole of the day it was running
in — and `snapshot_date` is `CURRENT_DATE('America/Los_Angeles')` while passes run several times a
night, so *several passes sharing one LA date is the normal case*, not an edge one. A pass whose
Task 20.8 failed in the small hours carried the same date as the pass that had already appended, and
the partition was restamped anyway, with no check able to see it. What the guard reads now is
`snapshot_built_at` — the snapshot table's own last-modified clock. If it has not moved past the
stamp the history already carries for that date, the table standing *is* the build already recorded
and there is nothing to add; a genuine rebuild always moves it, so the last pass of an LA day still
writes that day's final word. The LA-date clause is kept beside the build test for a different case:
a snapshot rebuilt by hand under an old date is a new build, but it must not overwrite what was said
back then. A snapshot carrying a date the history does *not* hold is appended whatever its clocks
say, because that is memory gained rather than provenance rewritten.

**Every row now records which build it came from.** `snapshot_built_at` sits beside `snapshot_date`
(the day being spoken about) and `captured_at` (when the row was written here). It is NULL on every
row written before v27.145 — those rows did not record it, and a backfilled value would be exactly
the fabrication this object refuses.

**What the alarms can and cannot see, stated plainly.** `C13` catches a restamp that crosses days.
A restamp *inside* one LA day cannot be detected from the committed rows at all: it moves
`captured_at` while `snapshot_built_at` stands still, which is indistinguishable from an honest write
whose build simply happened earlier the same day. That is a write-time property or nothing, so `C14`
asserts the two things that are provable — no partition records a build later than its own write, and
the guard is still deployed and still reading the build clock. Delete the guard and `C14` goes red.

### It cannot break the pass

Two independent guarantees. The procedure is guarded internally — a missing or empty snapshot
returns having done nothing, never emptying a partition — and the orchestrator wraps the CALL in the
house `BEGIN ... EXCEPTION WHEN ERROR` block, which logs FAIL to `LOG_PIPELINE_RUNS` and carries
straight on to Task 20.8b. Every step below 20.8a sees exactly what it would have seen without it.

### What it makes answerable

Read it through **`V_CATALOG_DWELL`**, one row per subject:

- **How long has this been in this state, and what did it change from.** Measured from OBSERVATION.
- **Was the appointment kept?** `days_overdue` against the ladder's own `next_check_date`.
- **How unstable is this subject?** `state_changes_28d` / `state_changes_90d`, over *observed* days.
- **What vanished?** A subject that leaves the snapshot keeps its row (`is_current = FALSE`,
  `absent_since`, `absent_days`) with the last verdict ever given it. This is doctrine Appendix B's
  failure — a keyword paused into invisibility — and a one-snapshot table cannot even report it.
- **Was the valuation right?** The history carries `affordable_cpc`, `affordable_bid`, `family_bar`
  and the settled record per day, which is the raw material of §6's Catalog scorecard. The scorecard
  itself is NOT built; the evidence for it now accrues, which it previously did not.

### Honest degradation — the rule the view is built around

On the day the history starts, every subject has been in its state for "at least one day" and
nothing can be said about how much longer. A view that printed a number there would manufacture the
very memory violation 6 is about. So `days_in_state` is **always the floor** — the number that is
certainly true — and `dwell_basis` says how it was arrived at:

| `dwell_basis` | meaning | `days_in_state_max` |
|---|---|---|
| `EXACT` | the change was observed: the previous snapshot for this subject is the day before the run started, and it read a different state | equals `days_in_state` |
| `BETWEEN` | the change fell inside an observation gap — it happened after the previous observation and by the run start | a real, larger bound |
| `AT_LEAST` | the run reaches back to the subject's FIRST row in the history. The true start is UNKNOWN and may be far earlier | **NULL, deliberately** — so an arithmetic consumer cannot average a censored value into a fake mean |

A consumer reading `days_in_state` alone is therefore told *less* than the truth and never more.
`dwell_gap_days` counts days inside the run for which the history HAS a snapshot but this subject has
no row — a run with holes is a weaker claim than one without, and it is said out loud rather than
hidden. `state_changes_28d` / `_90d` are counts over windows the history may not yet span; read them
against `history_days`, which every row carries.

### `state_since` is NOT when the state began — and the view says so

`FACT_KEYWORD_STATE.state_since` has a misleading name. Read the procedure: it is the park date for
a park, `floor_since` on probation, and otherwise the last bid change or the last applied change-log
row. It is a proxy for "when did something last happen to this keyword", it is NULL for a large
share of the account, and it is derived from the change log rather than from the ladder's own
verdicts — so it can move while the state stands still, and stand still while the state moves. The
v1 honesty note "`state_since` is best-effort" understated it.

`V_CATALOG_DWELL` therefore measures dwell from observation and publishes the declared column beside
it as `state_since_declared`, with `declared_agrees`. Measure the disagreement rather than trusting
a figure written here:

```sql
SELECT COUNTIF(NOT COALESCE(declared_agrees, FALSE)) AS disagree,
       COUNTIF(state_since_declared IS NULL)        AS declared_null,
       COUNT(*)                                     AS subjects
FROM `onyga-482313.OI.V_CATALOG_DWELL`;
```

### Where the history came from, and why it starts where it does

No copy of an earlier snapshot existed anywhere in the warehouse — no `TMP_`, no `T_`, no cube
materialisation, no export. What did exist is **BigQuery's own seven-day table history**: the
versions `CREATE OR REPLACE` replaced are still readable through `FOR SYSTEM_TIME AS OF`, and they
carry their TRUE `snapshot_date`. `scripts/bigquery/migrations/2026-08-24_keyword_state_history_backfill.sql`
recovered every day that window held, taking for each date the LAST version that carried it — the
same rule the live append follows, since the last pass of a day is that day's final word. Nothing
was interpolated, synthesised or dated by inference, and `source_detail` on every recovered row
names the exact time-travel timestamp it came from.

**That file has a fuse and is committed as an audit record, not a repeatable step.** Its timestamps
leave the seven-day window about a week after it ran, and it then becomes unrunnable. Everything
later comes from the nightly append. The history is only ever this thin once — check where it
actually begins:

```sql
SELECT MIN(snapshot_date) AS history_from, MAX(snapshot_date) AS history_to,
       COUNT(DISTINCT snapshot_date) AS days, COUNT(*) AS rows,
       COUNTIF(source = 'BACKFILL_TIME_TRAVEL') AS recovered_rows
FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`;
```

### Operating it

- **Acceptance:** `scripts/bigquery/tests/KEYWORD_STATE_HISTORY_acceptance.sql` — eleven checks, every
  row must read PASS. It asserts partitioning, row-count parity with the snapshot, one row per
  (date, subject), partition integrity, that no earlier partition is ever rewritten, dwell coverage,
  honest degradation, bound arithmetic, that the view invents no subject, that every ladder column
  reaches the history, and content fidelity for the live date.
- **If `SP_SNAPSHOT_KEYWORD_STATE` is ever run WITHOUT the append**, checks C02 and C11 go red until
  the next pass. That is not a false alarm — it is the history being stale. The fix is safe to run
  at any time:

  ```sql
  CALL `onyga-482313.OI.SP_APPEND_KEYWORD_STATE_HISTORY`();
  ```

- **Adding a ladder column needs no change here.** Deploy it upstream; the next pass carries it.
  C10 is the alarm if it somehow does not.

## The states (first match wins — the derivation order IS the doctrine)

| state | predicate | next appointment |
|---|---|---|
| `DEAD` | settled_clk90 ≥ 15 AND settled_ord90 = 0 — **re-derived from current data every run (A7), never passed through** | none (the one exempt state) |
| `PENDING_SETTLE` | reverdict = PENDING_SETTLE | reverdict settle_due |
| `REVIVED_SETTLING` | revive_settling | its settle_due |
| `PARKED` | reverdict ∈ (REVIVE, SIBLING_REVIVE, CONFIRM_PARK, REDUNDANT, INSUFFICIENT) | REVIVE → today; CONFIRM_PARK/REDUNDANT → +14d; INSUFFICIENT → its settle_due |
| `LAUNCH_CONTAINED` | bar_exempt family AND flat-era loser record (roas < 0.6 at ≥ 10 clk) — **a launch is never judged on profit, including in its label (A8)** | +7d |
| `PACED_WINNER` | clears the bar beyond noise + a GO bid-lowering instruction live today | tomorrow |
| `WINNER` | settled_roas90 − family_bar > se_eff at ≥ 10 settled clicks | last change + 14d else +7d rolling |
| `AT_BAR` | \|settled_roas90 − family_bar\| ≤ se_eff AND the click record does not rule the bar out — whatever the bid — **winner demotion (ruling 2) lands here: labels only, no bid moves on a relabel**; standing price = `GREATEST(affordable_bid, bid_floor)` | the EARLIER of `nf_collapse_forecast_date` (from its own 90d order pace) and the 7d re-read, never before tomorrow (A9) |
| `REPRICE` | below bar beyond noise AND an affordable **bid** (`affordable_bid` = affordable CPC / m_effective) exists at/above the keyword's own floor AND the bid is above the floor — move to it, re-judge after settle | last applied + 14d when still ahead (the scorecard's settled read); else +7d |
| `FLOOR_PROBATION` | below bar beyond noise AND (bid at/below its floor, ±½¢, OR no affordable bid at/above it) — the move is TO THE FLOOR from either side; `floor_since` is written (seeded on entry, carried forward from the table's own prior row) | `probation_due_date` = probation clock start + `settle_days_eff` (SP 3 / SB 14) + CEIL(10 / own 90d click pace), never before tomorrow; no pace → settle + 7 |
| `LOSER` | ONLY: `probation_elapsed` (≥ 10 settled clicks dated on/after the probation clock start = later of `floor_since` and the last bid change) AND `at_floor` AND still below bar beyond noise. **An above-bar keyword is never a kill, whatever its bid.** | +7d |
| `TRIAL` | everything else (clk < 10, or 0 orders under 15 clicks) | guard settle_due else +7d |

### The bar and its noise band (rulings 1 + 2)

- **bar_f** = `T_FAMILY_BAR.keyword_bar` (halo-adjusted breakeven, per family; COALESCE 1.0 when a
  campaign is unmapped — judged flat, as before).
- **se** = settled_roas90 / SQRT(settled_ord90) — order-space standard error of the record.
- **N_f** = CEIL((bar_f/(1−bar_f))²), computed from T_FAMILY_BAR **at run time, never hardcoded**
  (ruling 1). At ≥ N_f orders `se_eff` = 0: the band collapses and the verdict is wherever the
  number sits. Take today's values from the table, not this file:
  `SELECT DISTINCT family, keyword_bar, CAST(CEIL(POW(keyword_bar/(1-keyword_bar),2)) AS INT64) nf
   FROM T_FAMILY_BAR WHERE NOT bar_exempt AND keyword_bar < 1.0;`
- **A2 click-space sufficiency:** at the family's measured GP-per-order gpo_f, a keyword running AT
  the bar on its settled spend would have produced ord_bar = spend × bar / gpo_f orders. If
  observed orders fall short beyond SQRT(ord_bar), the click record itself rules the bar out and
  the order-SE band may NOT hide the row (`click_collapse` — the 489-click/4-order bleeder can
  never re-enter a band).
- **A3 one window:** verdict and price both read the settled-90 window (settled_cpc90 /
  affordable_cpc = gp_per_click / bar_f, or their cleaned equivalents). Live 7d CPC appears only
  in the reprice book, labelled as context.

### THE KILL CLAUSE (ruling 4 + the floor ruling — v27.104)

The v27.103 assertion ("every LOSER has failed AT its price" — settled CPC at/below affordable, or
no affordable price above a flat $0.25, or bid at/below $0.25) is **REPEALED**: two of its three
arms were phantom kills against a parking price. The standing assertion is now: **every LOSER is a
keyword that failed AT ITS OWN FLOOR, after its probation** — `probation_elapsed AND at_floor AND
below bar`. `V_ENGINE_HEALTH.loser_kill_clause` reads it (red > 0); self-check, must return 0:

```sql
SELECT COUNT(*) FROM `onyga-482313.OI.V_KEYWORD_STATE`
WHERE state = 'LOSER'
  AND NOT (probation_elapsed AND at_floor AND COALESCE(settled_roas90, 0) < family_bar);
```

Companion (`state_floor_resolution`, red > 0): no priced state (AT_BAR / REPRICE / FLOOR_PROBATION /
LOSER) may carry a NULL `bid_floor`; rows resolved on channel alone (`*_NO_ADGROUP`) are counted in
the detail so a silent drift to the conservative $0.25 is visible.

### The floors (v27.104, 2026-08-22 — Ori: "i think it is not 0.25 (we already checked it)")

A floor is a property of the CHANNEL and the CREATIVE, never a flat number. The ONE definition is
`FN_BID_FLOOR(channel, creative_type)`; `V_BID_FLOOR` resolves it per current ad group
(`DIM_AD_GROUP.creative_type`, `is_current`), and a keyword reaches its floor through
`DIM_KEYWORD.ad_group_id`. `V_LAUNCH_BID_LADDER` calls the same function (byte-identical output).

| row | floor | source |
|---|---|---|
| SP (anything not SB) | **$0.20** | house floor — Amazon's SP minimum is $0.02, but a bid that low buys no placement worth having |
| SB, `PRODUCT_COLLECTION` / `STORE_SPOTLIGHT` | **$0.10** | Amazon `minBid` |
| SB, video (`BRAND_VIDEO` / `VIDEO`) or NULL creative | **$0.25** | Amazon `minBid` ($0.15 / $0.20 rejected in r32 / r33); NULL resolves conservatively |

`V_OOB_KEYWORD`'s `0.25` is **`bid_park`** — a PARKING price, not a floor. v27.103's state ladder
borrowed it as a flat `platform_floor` and manufactured three phantom kills: `close-match`
BOX-SP/AUTO (Purple) at $0.24 and `complements` BOX -SP/AUTO (Blue) at $0.21 — both ABOVE the real
$0.20 SP floor and both at/above their family bar — and `tween girl gifts` (BOX-SBS/BROAD, an SB
collection keyword) whose floor is $0.10 and whose affordable $0.49 CPC ($0.46 bid) is perfectly
executable. Executability is tested in BID space: affordable bid = affordable CPC / the campaign's
measured placement multiplier (`V_BID_CPC_TRANSFER.m_effective`, A4).

### FLOOR_PROBATION — the floor ruling (Ori 2026-08-22, verbatim: "bid-up-to-floor if after a few days still loosing kill it")

**Status: SHIPPED (Step 2, v27.104) — `SP_SNAPSHOT_KEYWORD_STATE` runs this ladder; production
`FACT_KEYWORD_STATE` reproduced the simulation 855/855, 0 differing.** Simulation of record: `scripts/bigquery/simulations/SIM_2026-08-22_ladder_floor_probation.sql`
(TMP_SIM_LADDER_FLOOR, 7-day expiry), on the 2026-08-22 07:41–08:09 UTC snapshot chain.

| state | predicate |
|---|---|
| `REPRICE` | below bar beyond noise AND an affordable BID exists at/above the channel floor AND the bid is above the floor — move to it, re-judge after settle. The v27.103 "failed AT its price" CPC-materiality kill arm is REPEALED: a keyword is only ever killed at its floor (the book still applies the 5% materiality step to whether a row is emitted). |
| `FLOOR_PROBATION` | below bar beyond noise AND (the bid sits at/below its channel floor OR no affordable bid exists at/above it) — the move is TO THE FLOOR, from either side, and the keyword is re-judged after a few settled days AT the floor. |
| `LOSER` | ONLY a keyword whose FLOOR_PROBATION has ELAPSED and still reads below bar beyond noise. An above-bar keyword is NEVER a kill, whatever its bid (the v27.103 A2b "unexecutable AT_BAR → LOSER" arm is REPEALED). |

**"A few days" is derived, never a round number.** Probation ELAPSES on evidence: ≥ `vol_floor` (10)
settled clicks dated on/after `floor_since` (the date the state machine put the keyword at its
floor — carried forward by the SP from its own prior row; seeded by the first v27.104 run). The
appointment is the earliest date that evidence can exist: `floor_since + settle_days_eff`
(`FACT_KEYWORD_GUARD`'s own discipline, SP 3 / SB 14) `+ CEIL(10 / the keyword's 90d click pace)`.
Today's two probation rows forecast 6 and 7 days. No snapshot has ever recorded a FLOOR_PROBATION,
so `floor_since` is NULL everywhere and **the sim asserts ZERO LOSERs today**.

The guard defers every deterioration verdict (REPRICE / FLOOR_PROBATION / LOSER) and re-reads it
cleaned, as before — **and, since v27.104, AT_BAR's standing price** (see the guard section: `guard_scope`).

#### Probation memory (how `floor_since` is honest)

The SP reads its own prior `FACT_KEYWORD_STATE` row into a temp table before the rebuild (the column
is absent before the first v27.104 run and the table absent on a fresh project; both cases are
handled, never a first-run failure). `floor_since` = `COALESCE(prior floor_since, today)` while the
state is FLOOR_PROBATION or LOSER; any other state clears it.

**The probation CLOCK starts only when a floor bid has LANDED (v27.105).** It starts once the live
bid is OBSERVED at the floor (`at_floor` — a change-log row is a claim until the mirror confirms it;
a book logged at build time and never uploaded must never start a clock), and
`probation_clock_start` is the day the floor bid was APPLIED: the earliest `V_PPC_CHANGE_LOG_APPLIED`
row on that keyword with `new_bid ≤ bid_floor + bid_tol`, dated after the last applied row ABOVE the
floor and on/after `floor_since` (so the 1–2 day mirror lag delays the start without shifting the
date); failing a log row, `last_bid_change_date` dates it. Until the bid is at the floor the clock,
`probation_clk_settled` and `probation_due_date` are NULL, `state_reason` says
"WAITING FOR THE FLOOR BID TO LAND", and `next_check_date` is the 7d re-read (invariant 2). v27.104
started the clock at the later of `floor_since` and the last bid change, which stamped a running
clock on keywords whose floor bid had never been uploaded (the two BOTTLE-SP/AUTO clauses at $0.22 /
$0.24 over a $0.20 floor) — a fiction the book then yielded to LIFT. A book row that is never
uploaded never starts the clock; a raise off the floor ends `at_floor` and the kill arm with it.
`probation_clk_settled` = clicks dated on/after the clock start and on/before wm − settle_days_eff.
The SP reading its own previous output is not an engine reading the table: no engine reads it.

Published columns (v27.104, beside the v27.103 set): `ad_group_id`, `creative_type`, `bid_floor`,
`bid_floor_source`, `m_effective`, `is_brand_defense`, `affordable_bid`, `clean_affordable_bid`,
`at_floor`, `guard_scope`, `raw_state`, `clean_state`, `settle_days_eff`, `floor_since`,
`probation_clock_start`, `probation_clk_settled`, `probation_elapsed`, `probation_due_date`,
`probation_bid`, `nf_collapse_forecast_date`, `prior_state`. `state_reason` is one plain sentence per
state on the numbers the verdict used (guard-cleaned where the guard fired).

#### v27.104 transition matrix (live v27.103 state → floor-corrected state, 855 tracked keys)

| v27.103 \ v27.104 | AT_BAR | FLOOR_PROBATION | REPRICE | WINNER | (unchanged) |
|---|---|---|---|---|---|
| LOSER (5) | 2 | 2 | 1 | — | — |
| WINNER (76) | 1 | — | — | 75 | — |
| AT_BAR (50) / REPRICE (11) / PACED_WINNER (7) / TRIAL (70) / LAUNCH_CONTAINED (28) / DEAD (33) / PARKED (546) / PENDING (3) / REVIVED (26) | — | — | — | — | 826 |

Assertions (all on TMP_SIM_LADDER_FLOOR): 0 LOSERs; the two Bottle auto clauses (`loose-match`
$0.22, `substitutes` $0.24, affordable bids $0.03 / $0.14 under the $0.20 floor) land
FLOOR_PROBATION → bid to $0.20; `close-match` (Purple) and `complements` (Blue) land AT_BAR;
`tween girl gifts` lands REPRICE ($0.70 → $0.46 affordable bid, floor $0.10); the guard re-derives
its bar at 12.0% and the two drift flips reproduce (`substitutes` BOX-SP/AUTO White 0.58x → WINNER,
`shower gift set` FRESH-VIDEO 0.72x → WINNER); sums hold (884 rows = 884 keys = 855 tracked + 29
untracked spenders). **The third v27.103 "flip" — `complements` BOX-SP/AUTO (Purple), 0.57x shown
/ 1.90x on its own terms — no longer reaches the guard:** its raw verdict was only a deterioration
(LOSER) because of the phantom $0.25 floor; at the real $0.20 floor it reads AT_BAR within noise
(se 0.29) and the guard, which fires only on deterioration verdicts, leaves it there. Its AT_BAR
standing price ($0.17 affordable bid, under the floor) would book a cut to $0.20 on a mix the guard
already knows is drifted — **closed in Step 2: the guard covers every verdict that can move a bid
DOWN, AT_BAR's standing price included** (`guard_scope = 'AT_BAR_PRICE'`: the label stays AT_BAR,
`guard_deferred` is TRUE and the book prices the cleaned record — $0.56 bid on 1.90x own-terms for
this row). Live at ship: 2 AT_BAR_PRICE deferrals, 2 DETERIORATION flips (both → WINNER).

### CLEAN-THEN-JUDGE (the mix-drift guard)

Before any verdict that can move a bid DOWN stands — a deterioration verdict (REPRICE /
FLOOR_PROBATION / LOSER), or AT_BAR whose standing price would cut the bid by more than the book's
5% step — the SP measures the share of the
judging window's clicks on search terms **never seen** for that keyword in the prior comparison
window (the preceding 90d), **on measurable terms only** (≥ 5 judging clicks — the one-off
long-tail churns ~100% in every window pair and is background in both windows). The materiality
bar is **derived at run time** as the account click-weighted never-seen share on the same
measurable-term basis over keys with a measurable prior record (≥ 10 prior clicks) — a keyword
defers only when its own mix drifted beyond the account's measured background. A deferred keyword
is RE-READ excluding its zero-order never-seen terms and only the cleaned reading may downgrade
(`guard_deferred`, `guard_scope` ∈ {DETERIORATION, AT_BAR_PRICE}, `guard_flip`, `clean_*` columns).
DETERIORATION re-labels from the clean ladder; AT_BAR_PRICE keeps the label (the band is terminal)
and defers only the price the book may act on. The excluded population (`ns_zero_ord_terms`,
`ns_zero_ord_clicks`) is the **negate valve's** — it routes through the coach pipeline (negatives
act at AD GROUP grain — see fact_oi_negate_grain_mismatch), never as a raw list. Guard applies
only where a prior record exists; a keyword absent from the prior window has no comparison and its
record IS its record.

**Owner:** unchanged — `FACT_PANEL_OWNERSHIP.owner` with the REVERDICT-above-LIFT keyword overlay.

## The two invariants (standing self-checks; V_ENGINE_HEALTH reads them)

1. **One state:** `SELECT campaign_id, keyword_id … HAVING COUNT(*) > 1` returns 0 rows.
2. **No keyword without a next appointment:** `COUNTIF(next_check_date IS NULL AND state != 'DEAD') = 0`.
3. **The kill clause (v27.104):** `loser_kill_clause = 0` — see THE KILL CLAUSE above.
4. **Every priced row has its floor (v27.104):** `state_floor_resolution = 0`.

## THE REPRICE BOOK — the manual executor

`tools/build_reprice_bulksheet.py` (conventions of `build_stop_nonconverting_bulksheet.py`):

- **The SIDE of the bar decides the only direction allowed (v27.105, F1).** AT_BAR is two-sided.
  `sign(roas_used − family_bar)` (guard-cleaned where the guard fired) gates every AT_BAR / REPRICE
  row: ABOVE the bar a keyword is never cut (`NO_CUT_ABOVE_BAR`) — a raise is booked only if its
  own record prices one; BELOW the bar a keyword is never raised (`NO_RAISE_BELOW_BAR`). The
  v27.104 book keyed the no-raise rule on `state == 'REPRICE'` and cut five above-bar keywords /
  raised six below-bar ones — the DO_NOT_UPLOAD verdict of 2026-08-22.
- Emits keyword/target **bid updates** for AT_BAR / REPRICE rows whose capped price differs from
  the current bid by more than one 5% ease step (the engine's own smallest standing move) and
  never below the row's own `bid_floor`; **to-the-floor moves** for FLOOR_PROBATION rows (a row
  already at its floor is shown as PROBATION_RUNNING); and **pause rows** ONLY for LOSERs whose
  `probation_elapsed AND at_floor` — any other LOSER is shown as REFUSED_PAUSE (always CHECK
  FIRST on a pause). No flat floor constant exists in the book (v27.104).
- **One upload is one move — the cap (v27.105, F2), derived:** the engines step 5%/day and are
  blind to their own move for the days spend takes to settle — `V_ADS_SETTLE_CURVE` has spend at
  its final value by age 2–3 on both channels and the guard's SP settle discipline is 3 days. A
  hand upload gets no further steps before its next re-read, so it is capped at the engine's
  blind run: up ≤ (1.05)³ − 1 = +15.76%, down ≤ 1 − (0.95)³ = −14.26%. Rows with ≤ 2 settled orders
  or an uncapped move beyond the cap are CHECK FIRST. A to-the-floor move lands on the floor when
  the floor lies within one more engine step beyond the cap (a residual under the smallest
  standing move is not a move; a bid one cent over the floor never starts the clock); an up-move
  to a platform minimum is never capped.
- **Placement translation (v27.105, F3):** a keyword with ≥ 10 settled clicks since its last bid
  change (the guard's `vol_floor`) is priced on its OWN realised cpc/bid ratio in
  `V_BID_CPC_TRANSFER`'s ratio form — `new_bid = bid × (affordable_cpc / realised_cpc)^(1/γ)`,
  where k_seg and M cancel within a keyword; otherwise the documented campaign inverse
  `bid = (cpc / (k_pure × M))^(1/γ)`. A keyword whose own ratio sits more than one held-out RMSE
  (0.2805 in log space, the view's own figure) from `k_pure × bid^(γ−1) × M` is flagged
  PLACEMENT_DIVERGES. The SP keeps the simpler `affordable_cpc / M` for the STATE's affordability
  test (the view header says why). A naive CPC→bid mapping would RAISE bids on below-bar
  keywords in placement-dosed campaigns (Fresh ~85% placement-dosed) — hence F1's sign gate.
- **One keyword, one price:** a key carrying a live GO instruction in `T_ENGINE_PREFLIGHT` today is
  shown as ENGINE_INSTRUCTED and never executed — the engine speaks for it that day — EXCEPT a
  FLOOR_PROBATION row (v27.105, F5), which is always emitted CHECK FIRST naming the competing
  instruction, because the probation clock cannot start until a floor bid lands; Ori keeps one of
  the two prices by deleting the other line.
- **Provenance (v27.105, F4):** batch ids are time-stamped (`reprice_book_YYYYMMDD_HHMM`) and
  written into the README; the batch holds ONLY rows on a sheet, with a non-NULL `new_bid` on
  every bid row, a direction assertion, and an `upload_note`; the insert is read back and asserted
  equal to the sheet. Earlier never-uploaded batches are never deleted — `--supersede BATCH_ID`
  labels them `SUPERSEDED_NEVER_UPLOADED` (migration `2026-08-22_reprice_batch_superseded.sql`
  did this for the 54-row `reprice_book_20260822` batch); every run prints any reprice batch still
  unlabelled. `--no-log` skips the insert.
- **A5 season interlock:** every bid-down and pause row is checked against the season ledger's
  BLOCK_CUT (`V_KEYWORD_CONTEXT_GATE`, keyword grain); a blocked row appears in the book with its
  reason and is NOT emitted as an executable row.
- **HOLDOUT:** campaigns in `DE_HOLDOUT_ASSIGNMENT` arm = HOLDOUT are excluded from their
  `eligible_from` date (2026-09-01) — a hand upload into the holdout invalidates the trial. Rows
  allowed today in a holdout-arm campaign are LISTED in the README with that deadline (F6).
- Brand-defense campaigns never appear with a profit-based row.
- CHECK FIRST: rows the per-family N_f collapse newly condemns, and every LOSER pause row.
- Portfolio echoed on every row (blank DETACHES on Campaign rows; on keyword/target rows Amazon
  ignores the column — the README names campaigns whose LATEST history row is NULL, F6); SP and
  SB routed to their sheets; audit CSV + plain-English README; restore generator
  (`tools/build_restore_reprice_bulksheet.py`) rebuilds the inverse sheet from the audit CSV.
- The batch is logged to FACT_PPC_CHANGE_LOG (source MANUAL, coach_mode MANUAL_BULKSHEET) so the
  scorecard grades it; if the book is never uploaded, label the batch SUPERSEDED_NEVER_UPLOADED
  (uploaded-but-never-landed is FAILED_UPLOAD) — never delete a log row.

## v27.103 transition matrix (A1 — the clean rerun that gated this ship, 2026-08-22)

Old flat state → new bar/SE state (tracked population, 853 keys; UNTRACKED spenders excluded):

| old \ new | AT_BAR | REPRICE | LOSER | LAUNCH_CONTAINED | WINNER | TRIAL | (unchanged) |
|---|---|---|---|---|---|---|---|
| WINNER (95) | 22 | — | 2 | — | 71 | — | — |
| LOSER_BLEED (43) | — | 6 | 2 | 28 | 2 | 5 | — |
| TRIAL (102) | 27 | 5 | 1 | — | 4 | 65 | — |
| PACED_WINNER (7) | 1 | — | — | — | — | — | 6 |
| PARKED/PENDING/REVIVED/DEAD (608) | — | — | — | — | — | — | 608 |

Guard's proof (live, from the clean rerun and reproduced in production): 3 deferrals, all flips —
e.g. `shower gift set` (FRESH-VIDEO/BROAD) reads 0.72x at $0.78 shown but 3.92x at $0.83 on its
own terms; `substitutes` (BOX-SP/AUTO White) 0.58x → 3.53x. The investigation's original case
(`girls gifts age 8-10`, $0.49 shown vs $0.55 own-terms) resolved differently post-refresh: its
never-seen share fell to 1% (below the 12% background), so its REPRICE verdict stands on its own
terms — and it is N_f-condemned (62 orders ≥ N_f 20), so the book marks it CHECK FIRST.

## v1 honesty notes (still true)

- `SEASONAL_HOLD` is NOT yet a state (the gate's ENTRY_BLOCK verdict is not snapshotted).
- `state_since` is best-effort — and worse than that phrase implies. See the history section:
  it is the park date / `floor_since` / last bid change, NULL for much of the account, and it can
  move while the state stands still. `V_CATALOG_DWELL` measures dwell from observation instead and
  publishes `state_since` beside it as `state_since_declared` with `declared_agrees`.
- The 360° SIGNAL PANEL remains the task's second half.
- The negate valve for guard-excluded terms is exposed as columns (`ns_zero_ord_*`) but not yet
  wired into the coach pipeline's negate flow.
- A probation is judged on the whole settled-90 window (A3), not on the floor-period clicks alone —
  the floor-period record improves the window as it accrues; a floor-only read is a possible
  refinement, not built.
- The book logs its batch at BUILD time. A batch that is never uploaded must be labelled
  `SUPERSEDED_NEVER_UPLOADED` (the README says so) — otherwise `V_PPC_CHANGE_LOG_APPLIED` readers
  (the guard, LIFT, OOB, this SP's REPRICE appointment and, since v27.105, its probation clock)
  treat moves that never happened as applied. The v27.103 build's batch `reprice_book_20260822`
  (54 rows, never uploaded) was labelled by migration `2026-08-22_reprice_batch_superseded.sql`
  at v27.105; its removal moved ten REPRICE appointments off the phantom "applied 08-22 + 14d"
  date (2026-09-05) back to their real re-reads.
- A FLOOR_PROBATION row's down-move is capped like any cut; if the floor is more than one engine
  step beyond the cap the book steps toward it and the clock waits for a later book to land it.
- 85 overdue appointments at ship are all PARKED / REVIVED_SETTLING rows whose reverdict
  `settle_due` lies in the past — other objects' verdicts, assembled unchanged; not this ladder's.
