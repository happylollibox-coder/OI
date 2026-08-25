# The Three Layers — the doctrine every ads decision starts from

**Status:** agreed with Ori 2026-08-24. **This is the top document.** Any change to how a bid, a
budget, a pause or a probe is decided starts here and derives downward. If a design cannot be
expressed in these three layers and their contracts, the design is wrong, not the doctrine.

Supersedes the "one engine" wording of P-11 in
`docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md`. Downstream documents
(`FAMILY_SEAT_REGISTER.md`, `KEYWORD_STATE.md`, `ENGINE_PREFLIGHT.md`, `OOB_BUDGET_PHASE.md`) describe
*mechanisms*; this one describes *who is allowed to decide what*, and it wins on conflict.

---

## Changelog

Every entry records **what was decided and why**, not merely what was edited. A doctrine change is a
ruling: it names who made it and what evidence moved it, so a later reader can tell a considered
position from an accident. Newest last.

| when | commit | what changed, and what moved it |
|---|---|---|
| 2026-08-24 16:00 | `d87cbe6` | **The doctrine created.** Three layers named and bounded (Catalog / Brain / Pacing), the Catalog's four-field contract, the Brain→Pacing intents, seasonality assigned to the Catalog, the irreversibility rule, and the scorecards. Written after tracing two live failures end to end: a keyword whose correct price had been known for twenty days and never executed, and a seasonal keyword with a strong last holiday season paused as dead in August. Supersedes the "one engine" wording of P-11 — the boundary is not one engine, it is who decides worth, who decides funding, and who decides today's bid. |
| 2026-08-24 16:04 | `695030a` | **§9 — the UI must explain top-down.** Ori: every action shown to a person is presented Catalog → Brain → Pacing, in that order, because that is the order the decision was made in. Every number names the layer that produced it, so a reader who disagrees knows whether the argument is with a valuation, an allocation or an execution — the ambiguity that let a mechanics rule quietly make an economics decision. Disagreements between layers are surfaced, never hidden. |
| 2026-08-24 16:11 | `3b6c0c3` | **§2.1 subject types, §2.2 the grain ladder.** Ori observed that an auto-targeting group is not a real keyword. `substitutes` and its siblings are containers whose contents Amazon changes, so the subject is family × product × mode and cross-family comparison of "the same one" is meaningless — though the mode-level question is legitimate at the campaign-type grain. A real keyword shares its demand signal across families but never its worth; a product target does compare, being the same competitor. Also records that the family bar is a Catalog answer rather than a shared constant, and that bare target text is never a valid subject. |
| 2026-08-24 16:37 | `a92960b` | **§3.2 `LEAN_IN`, §3.3 open questions.** Ori: the Brain must always ask what it could do better, *including on the earning side* — "leave it alone" guards against churn but is not a licence to stop thinking. Adds the sixth intent and names the two populations the Brain must examine besides the losing side: turns (record says losing, window says earning — protected today, never funded, though the evidence is already bought) and constrained winners. Also: the 10 % holdout is not only the engine-vs-nothing baseline, it is the only place the Brain can honestly answer its own method questions. |
| 2026-08-24 17:09 | `11a562c` | **§2.3 evidence on probation, §2.4 `rank()`, §6 rewritten.** Ori: the Catalog must see SQP but distrust it until it earns trust — recorded with four nameable grounds rather than a disposition, and a hard limit that demand data alone may never move a verdict to `WORTH`. The Catalog must also answer *what is worth having* in a family, not only what a named subject is worth; refined from Ori's "best CVR" to expected profit contribution at the ceiling, because ranking on conversion rate alone fills an allowance with keywords too small to matter. §6 rewritten so all three layers recompute daily and are graded on their own question — including Pacing, whose scorecard nobody builds and which is the only way to test house constants like the entry anchor. §6.2 adds the attribution discipline the principle requires: only one layer may run a live method experiment in a family at a time, or the measurement is destroyed. |
| 2026-08-24 18:30 | `1ca33b0` | **§2.5 quantity, §2.6 what is advertised, §6.3 demonstrate don't assert, §10 the baseline.** A simulated keyword-year against the doctrine, measured across the account, then put through two adversarial verifiers. The arithmetic passed; **three of the four largest claims did not** — each had measured a population correctly and then asserted a loss without testing the innocent explanation. That failure produced the three new rules. §2.5: worth is a curve over volume, not a scalar price — the post-season month that looked like mispricing was the account buying more clicks at the right price into weaker conversion. §2.6 (Ori's correction of my "substitution" framing): the Catalog must know **what is advertised** — format, placement, creative, match width — because most of the "destroyed" seasonal sales were the same demand arriving through a wider match. §6.3 makes the discipline standing. §10 records the survivors, the disproved claims, and three violations in §8 the research corrected — including that the coverage gap is entirely deliberate and that the move cap is not enforced in *either* direction. |
| 2026-08-24 19:05 | `5f999c3` | **Baseline queries committed, five gaps closed.** §10.5 promised re-runnable queries that lived only in ephemeral scratch — all 76 are now committed at `docs/superpowers/specs/2026-08-24-three-layers-baseline.md`, which is what makes a recheck a re-run rather than a fresh argument. §3 gains the **park re-test obligation**: §8 and §10 both named a park as an absorbing state and no rule said so. §3 also gains `CARRY`, the vehicle intent §2.6 made possible but the contract could not express. §1.2 finally defines **the bar**. §9's UI table was missing `LEAN_IN`. §6.4 records the open rulings — including that the confidence scale is undefined, which leaves §5's irreversibility rule unenforceable as written. |
| 2026-08-24 19:20 | `d2af2ab` | **§1.4 — each layer is independently usable.** Ori: any module in the system, or he himself, must be able to use a layer for its own needs. The three layers are services, not stages of a nightly job: a stable contract, no ordering dependency, durable queryable state of their own, asking changes nothing, and answers are attributable. This is what the narrow interface was always for, and it reinforces §1.1 — a verdict shaped like a command is meaningless to a caller that is not the Brain. Notes honestly that all three are pipeline stages today and the Catalog keeps one snapshot, so independence is required and not yet held. |
| 2026-08-24 19:40 | `2b3cb8d` | **§2.7 confidence, §2.8 market volume.** Ori chose option C for the confidence scale: **separation × stability** — how sure we are which side of the bar a subject sits, discounted by whether the thing measured stayed the same thing, since BROAD terms turn over ~64 % a month against an EXACT control at 19 %. `NO_EVIDENCE` is a fourth state distinct from `LOW`, because §10 found zeros sitting on 0.2 expected clicks and a scale that reads those as "low confidence it is good" licenses kills on noise. §2.8 answers Ori's question about a keyword's volume on Amazon: `expected_clicks` meant *our* history, which cannot value an unbought subject nor say whether an owned one is capturing its opportunity. The market figures are already in the warehouse and read by nothing — a query the market buys 71 times a week where we hold 0.02 % of impressions, whose keyword we had paused. Two new violations recorded. |
| 2026-08-24 20:10 | `17d73ad` | **§4.1 — a campaign is a seasonal subject, and pause is its only park.** Ori: seasonal campaigns must be enabled and paused at the right time, and that is the Brain asking and the Catalog answering. The Catalog therefore answers for a campaign subject, not only keywords. The asymmetry that makes it urgent: a keyword can park at its floor, a campaign is on or off — so a campaign pause is the one irreversible action permitted on `NOT_WORTH_NOW`, and only on condition it **carries its reopen date**, recorded where a layer will act on it rather than remembered by a person. Adds `OPEN · by date D` and `CLOSE · reopen D`, and makes lead time part of the answer, since a campaign enabled on day one of its season has not been running when the season starts. Measured: ten paused campaigns hold $127,352 of last-season sales at 1.49 GP-ROAS, five stopped on one day in mid-July, and none has a reopen date. Also records the rename hazard that nearly inverted the finding — join campaign history on the id, never the name. |
| 2026-08-24 20:35 | `a8b3373` | **§2.9 negatives belong to the Catalog and expire; the account total is deliberately homeless.** Ori: negatives are managed by the Catalog — the Brain asks *how do I improve this*, and one answer is to negate a term. Adds `improve()` as a third question beside `ask()` and `rank()`. Critically, **the answer expires**: asked again a month later the Catalog may say *remove the negate*, for the same term, either because the data now says so or because a peak makes a high-volume term worth unblocking simply to buy data. So a negative is a standing answer with an expiry, never a settled fact. Records the asymmetry that a negative is created by a bulksheet but removed only by hand, and that the account's registry — not Amazon — is the record of what is blocked. Ori also confirmed the account's total budget is deliberately outside the doctrine: the Brain allocates within a pot, and the total emerges from the parts. |
| 2026-08-24 20:50 | `4e12846` | **§2.9 corrected — a negative CAN be removed by bulksheet.** Ori challenged the claim that removal needs a console edit, and he was right. Checked: `negative_id` is populated on every live negative in the registry, one removal has already been executed, and Amazon accepts an `Entity: Negative Keyword` row with `Operation: Update` and `State: archived`. The real gap is narrower and ours — every book this account builds emits `Operation: Create` for negatives and nothing else, so the Catalog's expiry answer has no book to travel in (new violation 25). The surviving constraint is coverage, not capability: the registry rather than Amazon is the record of what is blocked, so a negative created outside our books is invisible to the Catalog. |
| 2026-08-24 21:40 | `ca01597` | **Violation 6 CLOSED — the Catalog keeps a memory.** Ori chose this as the first violation to close, on one decisive ground: every other one costs the same to fix next week, while this one got permanently more expensive every night — `FACT_KEYWORD_STATE` is `CREATE OR REPLACE`d on each pass and holds a single day, so each pass destroyed a day of verdicts that could never be recovered. Built additively, with nothing that can reach Amazon reading any new object: `FACT_KEYWORD_STATE_HISTORY` (append-only, partitioned by `snapshot_date`, the WHOLE ladder row — because §6 asks *was the valuation right?* and a verdict without the record, the bar, the band, the price and the appointment behind it can be counted but not graded), `SP_APPEND_KEYWORD_STATE_HISTORY` at orchestrator Task 20.8a (append-then-prune, so the failure mode leaves a duplicate rather than a lost day; the prune's scoping was repaired in v27.144 — see the 2026-08-25 `8dcd3f8` row below — so that a strand is healed by any later call and a pass that did not build the snapshot cannot restamp it; no hard-coded column list, so §2.7, §2.8 and §4's future columns are kept the night they appear), and `V_CATALOG_DWELL`, which answers §10.4 while REFUSING to answer more than the evidence allows — dwell is a bound with a stated basis, and a run reaching the start of the history reads `AT_LEAST` with a deliberately NULL maximum. Two findings the memory produced on its first day, both previously unaskable: the ladder's own `state_since` column disagrees with the observed state start for the overwhelming majority of subjects (it is the park date / `floor_since` / last bid change, not a state clock), and subjects that VANISH from the snapshot — doctrine Appendix B's failure — are now visible as rows rather than absences. Seeded from BigQuery's own seven-day table history: real replaced versions at their true dates, two schema eras loaded with the columns each actually had, nothing invented, and no other surviving copy existed anywhere in the account. What is closed is the RETENTION; §6's Catalog scorecard is still to be built, and the Brain and Pacing still keep no answers of their own. |
| 2026-08-25 | `99129ac` | **The unowned-spend gap becomes a daily number — measurement only, nothing wired.** §10.1's largest surviving finding was spend on subjects with no Catalog row at all, discovered by a research pass and countable nowhere afterwards. `V_UNOWNED_SPEND` / `V_UNOWNED_SPEND_SUMMARY` stand it up as durable, queryable, read-only state, which is what §1.4 requires of a layer's answers: one row per spending subject with no `FACT_KEYWORD_STATE` row, at TARGET grain rather than the baseline's `(campaign, keyword)` pairs — under the `-1` sentinel a pair bundles many product targets into one row, so the baseline's largest row was not a subject — with the reason classified into four classes and six reasons, a live 7-day figure beside the 28-day one so a tail from a paused campaign cannot be read as money burning today, and the family bar it *would* be judged against where one exists. It issues **no verdict**: no family means no bar means nothing to compare, and unmeasured never reads as bad — no bar distance is published for a subject too thin to read. It refuses the baseline's substitute reference bar, which the baseline itself had marked MEDIUM for the right reason. Eleven acceptance assertions (A11 added by the repair row below), written failing-first against a deliberately broken deployment and returning measured violation counts on five of them before the real view shipped; A9 proves against `INFORMATION_SCHEMA` that the objects are views, contain no DML, and are read by nothing. **§8 violations 4 and 21 are deliberately NOT struck through:** the measurement half of 4 is closed and its SQP half is untouched, and 21 gains nothing at all. Wiring these subjects into the universe would move money and is Ori's decision, not a consequence of having measured it. SOP: `architecture/UNOWNED_SPEND.md`. |
| 2026-08-25 | `a8e08d5` | **Repair — a summary column counted a family population through a judgeability label, and the label's precedence ate it.** `V_UNOWNED_SPEND_SUMMARY.subjects_with_no_family` / `no_family_spend_per_day_28d` were defined as `COUNTIF(judgeability = 'NO_BAR_NO_FAMILY')` and the matching SUM. `judgeability` applies **reading precedence first**, so every subject with no family that took fewer than `min_clicks_for_a_reading` clicks was labelled `TOO_THIN_TO_READ` and silently dropped out of a column whose name promised a family census — worst on `CAMPAIGN_OUTSIDE_UNIVERSE`, where every subject has no family and the published count was a fraction of it. Nothing moved money (the view is read-only and read by nothing), but it is the **attribution** figure — how much of this spend can be assigned to a product line at all — in the view built to be read daily without re-derivation, and the mislabel had already produced a wrong statement in a written report. The columns now count `family IS NULL`, a `subjects_with_no_bar` / `no_bar_spend_per_day_28d` pair (`family_bar IS NULL`) is published beside them, and the three populations nest. A11 re-derives all six figures from `V_UNOWNED_SPEND` per class and for the total and checks the nesting; run failing-first against the deployed summary it returned violations = 4. The generalisable lesson, now in the SOP: **a column counted through a label inherits that label's precedence, not its own name's meaning.** |
| 2026-08-25 | `8dcd3f8` | **Repair — the Catalog memory's two self-healing promises were both conditional, and one failed permanently.** `SP_APPEND_KEYWORD_STATE_HISTORY` pruned with `WHERE snapshot_date IN (SELECT DISTINCT snapshot_date FROM FACT_KEYWORD_STATE)` — scoped to whichever date the live snapshot happened to carry. `snapshot_date` is `CURRENT_DATE('America/Los_Angeles')`, so a strand left when the INSERT succeeded and the prune failed on the LAST pass of an LA day could never be reached again: every later pass carried a different date and the duplicate was permanent, with no in-procedure remedy — not even the manual `CALL` the SOP offers as the universal fix. The same scoping made the second promise conditional in the other direction: Task 20.8 sits in its own `BEGIN ... EXCEPTION` block, so a pass where the snapshot BUILD failed still reached the append with the previous day's table standing, and re-copying it stamped an older partition with tonight's `captured_at` and a `source_detail` naming a read time at which the Catalog said nothing — identical rows, falsified provenance, in the one object whose whole purpose is to be trusted about what was said when. The prune is now stated as the invariant it always meant — a `snapshot_date` holds exactly one `captured_at`, newest wins — keyed on the history's OWN duplicate stamps rather than on the live snapshot's dates, and it runs before the append as well as after, so a strand on ANY date is healed by ANY later call. A new GUARD 3 refuses a snapshot older than the current LA date whose day the history already holds; a stale snapshot carrying a date the history does NOT hold is still appended, because that is memory gained rather than provenance rewritten. Both defects were measured on TEMP replicas before the fix and re-measured to zero after, and the acceptance suite gains `C12` (one `captured_at` per `snapshot_date`) and `C13` (provenance monotone in `snapshot_date`), each given a negative control on a poisoned copy of the live history to prove it has teeth. Nothing about what the ladder records changed; this is the memory's own integrity, not its content. |
| 2026-08-25 | `82db0e3` | **Repair — the memory's no-restamp guard was blind inside the day it ran in, and its own table still published the mechanism the previous repair removed.** Two defects in the object whose whole purpose is to be trusted about what was said when. (1) `GUARD 3` refused a stale snapshot only when its date was older than `CURRENT_DATE('America/Los_Angeles')`. But `snapshot_date` IS that LA date and several passes run each night, so *sharing one LA date is the normal case*: a pass whose Task 20.8 failed at 03:00 carried the same date as the pass that had already appended, the guard waved it through, and the partition was restamped — `captured_at` and `source_detail` moved to a read time at which the Catalog said nothing new. Measured against live state before the fix: the guard refused nothing, one partition was restamped, and `C05`, `C12` and `C13` all read 0 — silent, which is worse than loud. The guard now tests the BUILD rather than the calendar, comparing the snapshot table's own last-modified clock against the stamp the history holds for that date; a build that has not moved has nothing to add, while a genuine rebuild still writes the day's final word, and a date the history does not hold is still appended because that is memory gained. Every row now records `snapshot_built_at`, so which build a partition came from is part of the memory rather than an assumption about it. (2) The DEPLOYED table description still asserted the v27.143 mechanism — *"replaces exactly the snapshot's own date partition ... no earlier partition is ever touched"* — after v27.144 had made both halves false, and it contradicted the registry entry for the same table, which had been corrected. A person hunting for rows missing from an old partition would have read it, ruled the writer out and looked elsewhere. The cause is worth remembering: the table's DDL is `CREATE TABLE IF NOT EXISTS`, so editing the file cannot update a live description — it takes an explicit `ALTER`, shipped here as `scripts/bigquery/migrations/2026-08-25_keyword_state_history_build_clock.sql`, and the file now says so. `C14` was drafted with a third assertion and it was CUT after measurement: it read 1 violation on an honest history and 0 on a genuine restamp. A same-day restamp cannot be detected from committed rows at all — it is a write-time property or none — so `C14` asserts only what is provable: no partition records a build later than its own write, and the guard is still deployed and still reading the build clock. All 14 checks pass, both halves with negative controls. Nothing about what the ladder records changed. |
| 2026-08-25 | `9638be7` | **The recovered memory gets a second copy, because the fuse turned out to be seven dates and the first one was hours away.** The backfill migration's own header said its time-travel timestamps expire "around 2026-08-31". That is the LAST expiry, not the first. BigQuery's window is 168 hours and each source timestamp leaves it on its own day, so `2026-08-17` — read from the `2026-08-18 06:00Z` version — became **permanently unrecoverable at 2026-08-25 06:00Z**, about seven hours after the discrepancy was noticed, with one further day joining it every 24h until 2026-08-31. Nobody had misread anything; the header stated the true end of the range and everyone, including the writer of the closing report, carried that date forward as though it were the deadline for all seven. From each of those moments `FACT_KEYWORD_STATE_HISTORY` is the ONLY copy of that day, and **its own time travel is not a second copy** — it expires on the same rolling window, so it protects only against a loss noticed inside a week. `FACT_KEYWORD_STATE_HISTORY_SEED_20260824` is therefore an immutable BigQuery SNAPSHOT of all eight partitions, taken at 23:15Z: delta-stored so it costs almost nothing, it survives deletion of the base table, and a `DELETE` against it fails with *snapshots are immutable* — verified as a negative control rather than assumed. Verified at creation against the live history: 8 dates / 6,814 rows, every date's row count AND `captured_at` identical, 69 columns both sides with zero type mismatches. Nothing reads it and nothing should; it is insurance, not a source, and it can move no bid, budget or pause. **The doctrine point this makes is §5's, one level up from bids:** violation 6 was chosen first on the ground that its cost was *permanent and compounding*, and a recovery performed once under that reasoning was then left as a single copy standing on a clock nobody had read to the day. An irreversible asset deserves the same treatment as an irreversible action — the migration header and the gap-closure plan's "live and empty" row are both corrected, since a stale note about an unrepeatable recovery is itself a hazard. |
| 2026-08-25 | `afef20e` | **Two rulings by Ori, and the park re-test gets an answer with teeth.** (1) **The park re-test cadence is SETTLED** (§3, §6.4): *per family, once off-season and once at the December peak, gated on the subject's volume being worth it.* Three things follow that were not obvious from the sentence — the cadence is a FAMILY property and there is no account-wide interval, because families do not share a season; the volume gate is the **Catalog's** answer via §2.8 market volume, not the Brain's guess, so a re-test below the gate is SKIPPED and the skip is recorded with its reason; and two occasions is a **ceiling, not a floor**, which is the doctrine deliberately accepting permanent parks — but only ones it can name the reason for. The December occasion is there because peak is when a high-volume term is worth unblocking simply to buy data, the same argument §2.9 already makes for negatives, and it is the cheapest evidence of the year per click. Still open: how many clicks a re-test buys and at what price (§6.1). (2) **Phase 2 approved** — the unowned subjects will be wired into the Catalog's universe; `V_UNOWNED_SPEND` stops being a report and becomes a work list, and the $64.38/day under the `-1` sentinel gets a structural fix (key SB product targets on campaign plus target text) before any pricing decision about them is expressible. Also recorded: the appointment machinery is **already there and already ignored** — all 544 parked subjects carry a `next_check_date`, 63 have passed, the oldest by 281 days. Violation 14 is therefore not "a park carries no re-test obligation" but the narrower and more fixable "the obligation is recorded and never read as a trigger". |

### How to add an entry

Amend this table in the same commit as the change. Record the ruling and the evidence that moved it —
a measurement, a failure, or an explicit decision by Ori — never just the diff. If a later ruling
overturns an earlier one, leave the old row standing and add a new one saying what replaced it and why:
the history of a position is part of the position.

---

## 1. The three layers

| | **Catalog** | **Brain** | **Pacing** |
|---|---|---|---|
| also called | the ladder, the judge, the memory | the repricer, the treasurer | the engines, the operator, the hands |
| purpose | establish **what is true** about economics | decide **where the money goes** | make it **happen in Amazon's auction** |
| the question it answers | *"What is this worth, under these conditions, for this window?"* | *"Should we pay for this, and how much?"* | *"What bid today achieves what we were asked for?"* |
| time constant | evidence-paced; seasonal; settled data only | one allocation window (3 days in peak, 7 off-peak) | daily, small steps |
| may decide | nothing — it is queried, never obeyed | funding, ceilings, pauses, budgets | today's bid, the path to a target |
| may **never** | allocate, bid, or act | set a daily bid; judge on its own window alone | decide whether a keyword deserves money |
| its characteristic failure | knows the truth, has no hands — a correct answer can sit unexecuted for weeks | allocates on a short window and goes blind on quiet keywords | optimises click flow with no concept of worth |

### 1.1 The Catalog is a catalog

The Catalog is a **reference of prices and profitability** — per family, per product, per campaign
type, per placement, per season, per any criterion that changes what something is worth. The Brain
uses it the way a buyer uses a catalog: it comes with a budget and a window, asks what things are
worth *for that window*, and decides what to buy.

A catalog does not issue commands. It has no opinion about money. This is why the Catalog may not
emit verdicts shaped like instructions (`DEAD`, `WINNER`, `REPRICE`) — a verdict shaped like a
command turns into an Amazon action without anyone having decided. It emits worth, ceiling,
confidence and volume; the Brain decides.

### 1.2 The Brain is the buyer

**The bar** is the family's break-even: how many gross-profit dollars an ad dollar must return for a
subject to be worth its money. It sits below 1.0 because advertising also drives organic sales — the
organic halo — so a subject can clear its bar while returning less than a dollar on ads alone. It is a
property of a family, not of a keyword, and (§2.2) it is a Catalog answer rather than a shared constant.

**The account's total budget is not the Brain's** (Ori, 2026-08-24 — deliberate). The Brain allocates
*within* a family's pot and the pot is defined by what that family's good keywords spent, so the account
total emerges from the parts rather than being handed down. How big the account should be is a decision
outside this doctrine.

The Brain holds the pot (the 80/20 allowance per family) and spends it. It asks the Catalog per
keyword, compares **within the family** — because the pot, the bar and the halo are all family-scoped
— and stops when marginal return reaches the bar or the money runs out.

It is the only layer permitted to take an irreversible action (§5).

### 1.3 Pacing is the operator

Pacing knows Amazon: auction dynamics, click flow, placement multipliers, floors, minimums, how a bid
becomes a CPC. It receives an intent and a constraint from the Brain and finds the price that
delivers it. It is accountable for results: if the Brain buys an answer, Pacing must push until the
answer arrives — and if it cannot buy clicks at any permitted price, **that is itself the answer**,
reported back.

### 1.4 Each layer is independently usable

The three layers are **not a pipeline with one consumer**. Each is a service that Ori, a dashboard page,
a bulksheet generator, a notebook, or a module that does not exist yet may call for its own purpose,
without running the others.

That is what the narrow interface (§2) is *for*. It is not tidiness — it is the condition that lets a
layer be improved on its own (§6) and reused by something its author never anticipated. Concretely it
requires:

- **A stable, documented contract.** A caller uses `ask()` / `rank()` and the intents without knowing any
  internals, and an internal change that does not alter the contract may not break a caller.
- **No ordering dependency.** The Catalog must answer whether or not the Brain has run tonight; Pacing
  must be usable against a hand-written intent. A layer that only works as stage *n* of a nightly job is
  not a layer, it is a step.
- **Durable, queryable state of its own.** A caller must be able to read a layer's answers directly and
  historically. A layer whose output exists only as a side effect of a pipeline run cannot be consulted,
  audited or graded (§6).
- **Asking changes nothing.** A query to any layer is read-only. Nothing is spent, moved or recorded
  because someone asked a question.
- **Answers are attributable.** A caller can tell which layer answered and on what date — the same
  requirement §9 places on the UI, applied to every consumer.

**This is also why the Catalog may not emit commands (§1.1).** A verdict shaped like an instruction is
meaningless to a consumer that is not the Brain: a dashboard asking "what is this worth in November"
cannot act on `DEAD`. Worth, ceiling, confidence and volume mean the same thing to every caller.

**Where the build stands:** all three layers are still pipeline stages, so the ordering-dependency
requirement is not met. The *durable state* requirement is now met for the Catalog alone:
`FACT_KEYWORD_STATE_HISTORY` (2026-08-24, violation 6 CLOSED) is queryable directly and historically
by any caller, and `V_CATALOG_DWELL` reads only that history, so it answers whether or not tonight's
pass has run. The Brain and Pacing still keep no answers of their own. Independence remains a
property the doctrine requires and the system only partly has.

---

## 2. The Catalog contract

The interface is deliberately narrow. All pricing complexity lives behind it, so the Catalog can be
improved without any other layer changing.

```
catalog.ask(subject, window_from, window_to)
```

Returns exactly:

| field | values | what the Brain does with it |
|---|---|---|
| `verdict` | `WORTH` · `NOT_WORTH` · `NOT_WORTH_NOW` · `UNKNOWN` | fund · stop · park · buy an answer |
| `ceiling_cpc` | the **marginal** value of the next click, at the bar, for that window | the hard cap handed to Pacing |
| `confidence` | how sure the verdict is — **separation × stability**, see §2.7 | act on it, or buy more evidence |
| `expected_clicks` | clicks the subject typically takes in such a window | **sizes the seat** — what an answer costs |

**Hidden inside, and never exposed:** seasonal resolution · the family bar and the organic halo ·
placement multipliers · settle curves and attribution lag · noise bands and volume floors · the
mix-drift / never-seen-term guard · product margin and landed COGS · campaign-type halo weights ·
channel floors · bid→CPC translation and elasticity.

**Marginal, not average.** `ceiling_cpc` is the worth of the *next* click, not the average click. As a
bid rises it wins auctions it previously lost — later placements, weaker intent — so the marginal
click is normally worth less than the average. Pricing to the average systematically overpays at the
margin. The Catalog owns the response curve; the Brain owns the comparison across keywords under a
budget. (Elasticity is realistically estimated per segment — family x match type x placement — and
applied per keyword; do not promise per-keyword precision the data cannot support.)

### 2.1 Subject types — not everything the ladder holds is a keyword

`ask()` takes a **subject type** alongside the subject, because the three types the account actually
contains behave differently and may not be compared the same way. Measured 2026-08-24, the split by
settled spend is roughly half real keywords, a quarter auto-targeting modes, and the remainder product
targets — re-derive with a GROUP BY on the target text pattern over `FACT_KEYWORD_STATE`.

| type | the subject is | cross-family comparison | why |
|---|---|---|---|
| **real keyword** | the phrase, scoped to its family | share the **demand** signal; never the **worth** | the phrase carries intent that genuinely travels; the bar, product margin and halo do not |
| **auto-targeting mode** (`substitutes`, `complements`, `close-match`, `loose-match`) | **family x product x mode** | **never as "the same subject"** | it is a container, not a phrase: `substitutes` for one product targets entirely different competitors than for another |
| **campaign** | the campaign itself — is it worth running in this window at all (§4.1) | not compared across families; a campaign belongs to one | seasonal campaigns are opened and closed on the Catalog's answer, and a campaign has no park (§4.1) |
| **product target** (`asin=`, `category=`) | the competitor target, scoped to its family | **legitimate** — same competitor, different product of ours advertised against it | "does this competitor's traffic convert for us" is one coherent question |

**An auto-targeting mode is a basket whose contents Amazon changes.** Its history is therefore a weaker
predictor than a keyword's history of the same length, and `confidence` must say so rather than letting
a 90-day auto record be trusted like a 90-day keyword record. The account has already seen this: the
mix-drift guard found one auto mode reading far below its bar raw and far above it once never-seen
zero-order terms were stripped — the same subject, a many-fold swing, from composition alone.

**The mode-level question is legitimate at its own grain.** *"What is `substitutes` worth?"* is
meaningless across families; *"does substitutes-targeting work for us as an instrument, and for which
families?"* is a real allocation question at grain 3 (§2.2), and one nothing currently asks despite the
money involved.

### 2.2 The grain ladder — the Brain asks top-down

The subject is the grain of the decision, and the Brain works downward in the same order as the doctrine:

| grain | the question | what the answer decides |
|---|---|---|
| **family** | what does this family need to break even after halo, and what is a marginal click worth to it? | the bar and the stopping rule for everything below |
| **product** | which of this family's products is worth advertising in this window? | where the pot points |
| **campaign / targeting type** | what is a conquest click worth versus brand defense, or auto-substitutes versus exact? | which instruments the money flows through |
| **keyword / target** (scoped) | what is this worth, in this family, for this window? | fund, repair, park or stop |

Two consequences: **the family bar is a Catalog answer, not a shared constant** — it is what the Catalog
returns when asked about a family, and it is seasonal like everything else; and a subject must always be
scoped enough to be unambiguous. A keyword id is safe (Amazon scopes it to an ad group, hence to one
campaign and family); bare target text is not — several phrases in this account exist in three or more
families at once, and a query keyed on text alone silently blends their economics into one wrong answer.

### 2.3 External evidence enters on probation

The Catalog values a subject on what the account already spent. That is a severe limit: it can only
describe what was captured, never what was available. **Demand data — Search Query Performance above
all — belongs in the Catalog**, because "how big is this query and what share do we hold" is a
statement about worth, not about allocation or execution.

**It enters distrusted, and earns trust by prediction.** A new evidence source arrives weighted near
zero, makes forecasts alongside the existing estimator, is scored against outcomes like any other
Catalog prediction (§6), and its weight rises or falls with its measured accuracy. Trust is a
measurement, never an assumption.

For SQP specifically the suspicion has four nameable grounds, and each is a thing to measure rather
than a reason to avoid it:

1. **The join is not one-to-one.** SQP is reported per search query; the Catalog's subjects are
   keywords, auto-targeting modes and product targets. One broad keyword matches many queries and one
   query is matched by many keywords, so any query→subject attribution is itself an estimate.
2. **It is market-level, not ours.** Its impressions, clicks and purchases are the whole query's, across
   all sellers. Our share is a separate and smaller number, and confusing the two overstates worth.
3. **It is weekly, not daily**, so it cannot answer a 3-day window directly.
4. **Coverage is partial** in this account, and known to be so — a source that describes part of the
   traffic must not be read as describing all of it.

Until it has earned trust, SQP may inform `expected_clicks` and may propose candidates (§2.4), but it
may not by itself move a `verdict` from `UNKNOWN` to `WORTH`. Spending money still requires evidence
the account itself produced.

### 2.4 The Catalog answers "what is worth having", not only "what is this worth"

The Brain must be able to come to the Catalog with a family and a window and ask for the **ranked
opportunities**, not merely to price subjects it already knows about. This is what makes the Brain
proactive rather than reactive — otherwise it can only judge keywords that already exist and already
spend, and the account can never grow except by accident.

```
catalog.rank(family, window_from, window_to)  ->  ordered candidates
```

Each candidate carries the ordinary four fields (§2), plus whether it is **live** (already running) or
**new** (proposed from demand data and research, never yet bought).

**The ranking is expected profit contribution at the ceiling — not CVR.** Conversion rate is an input,
not the ordering: a high-CVR subject with almost no volume is worth less than a moderate-CVR subject
with real volume, and ranking on CVR alone quietly fills an allowance with keywords too small to matter.
The order is (expected conversions x margin) − (expected clicks x ceiling CPC), over the requested
window, with the whole thing discounted by confidence so an `UNKNOWN` candidate cannot outrank a proven
one on optimism alone.

**The Brain then does what it always does:** take the ranked list, fund down it until the family's
allowance is spent, and queue the rest. A new candidate is funded as a question (`TEST`, §3) with a
budget and a deadline like any other; a live one is funded as `EARN`, `LEAN_IN` or `REPAIR` according to
its verdict. Research-sourced keywords enter here — they are Catalog candidates, not a separate
decision-making system.

### 2.5 Worth is a curve over quantity, not a single price

`ceiling_cpc` answers *what may we pay for a click*. It does not answer **how many clicks to buy**, and
a doctrine that prices without quantifying cannot tell overpaying apart from over-buying — two failures
that need opposite responses.

The baseline research (§10) found this the hard way. Across one post-season month, spend rose sharply
while the cost per click barely moved: the account bought far **more** clicks, correctly priced, into a
market whose conversion rate had fallen. Every price was defensible; the quantity was the question, and
no layer had language for it.

So the Catalog's answer is a **response curve**, not a scalar: for a subject and a window, what volume
is available at what price, and what does the marginal click return at each point. `ceiling_cpc` is then
simply the point on that curve where marginal return meets the bar — a derived reading, not the primitive.

This is the same curve §2 already requires for marginal-versus-average pricing, used for a second
purpose, so it is one piece of work and not two. It gives the Brain the question it currently cannot ask:
**at what volume does the next click stop clearing the bar?** — which is the allocation question, stated
properly.

### 2.6 The Catalog must know what is advertised

Worth is not a property of a search phrase alone. The same demand can be bought through different
**vehicles**, and Amazon prices each one differently:

- **format** — Sponsored Products, Sponsored Brands, Sponsored Brands with video
- **placement** — top of search, rest of search, product pages, each with its own multiplier
- **creative** — which specific video or image is running, since one performs materially better than
  another and the account has both
- **match width** — the same query can be caught by an exact keyword, a phrase, a broad, or an auto mode

A Catalog that knows only "this phrase is worth X" cannot answer *which vehicle should carry it*, and
that is a real allocation question the Brain has no way to pose today.

**This also explains an apparent loss that was not one.** The research measured a large sum of last-season
sales sitting behind paused keywords and called it money at stake. Challenged, the overwhelming majority
of those queries turned out to be **bought elsewhere in the account already** — the same demand arriving
through a wider match. Nothing was lost; the traffic changed vehicle. A per-subject valuation cannot see
this, and will keep reporting recaptured demand as destroyed value until the Catalog carries the vehicle
dimension.

Two consequences follow. **A pause is cheaper than §5 assumes when the demand is recaptured, and exactly
as expensive as §5 assumes when it is not** — and only a vehicle-aware Catalog can tell which case is in
front of you. And **the Brain should be allocating across vehicles, not only across phrases**: the
question "should this family's money go to SB video or to SP" is a grain-3 question (§2.2) that nothing
currently asks.

### 2.7 Confidence — separation discounted by stability

§5 forbids an irreversible action below HIGH confidence, so confidence must be a computed thing, not an
impression. It has two factors, and both are necessary.

**Separation — how sure are we which side of the bar this is on?** Not "how much data is there", which
asks the wrong question: a subject far below its bar needs little evidence to be certain, one sitting on
the bar needs a great deal. The ladder already computes the noise band, so:

```
separation = |return − bar| / se        where se = return / sqrt(orders)
```

**Stability — did the thing being measured stay the same thing?** A record is only as trustworthy as the
constancy of what produced it. Measured (§10.1): terms behind a BROAD subject turn over at about 64 % a
month and auto modes at 57–68 %, against an EXACT control at 19 %. Two subjects with identical click
counts are therefore not equally knowable, and separation alone would call them equal. Stability is the
share of a record that came from composition still present.

**Confidence is the product**, published as a continuous score and read through three bands:

| band | meaning | what it licenses |
|---|---|---|
| `HIGH` | well separated from the bar on a stable record | everything, including an irreversible action (§5) |
| `MEDIUM` | separated but on a drifting record, or near the bar on a stable one | reversible moves; repair, park, lean in |
| `LOW` | not separated | no move justified by worth alone |
| `NO_EVIDENCE` | **distinct from LOW** — the record cannot speak at all | buy an answer (§3 `TEST`) or park. **Never** a kill |

**`NO_EVIDENCE` is a separate state on purpose.** §10 found subjects whose zero orders sat on a median of
0.2 *expected* clicks — a zero that means nothing. A scale that collapses "no information" into "low
confidence it is good" will license kills on noise, which is exactly the failure §5 exists to prevent.

The two factors also give §2.3 somewhere to live: an evidence source on probation enters with a low
stability weight and earns a higher one by predicting well.

### 2.8 Volume is a market fact, not only our history

`expected_clicks` (§2) means **our** volume — what this subject has taken for us. That is the wrong
number for two of the questions the doctrine asks. It cannot value a subject the account has never
bought, and it cannot say whether a subject we already own is capturing its opportunity or a sliver of it.

So the Catalog carries **market volume** beside our own:

| | source | what it answers |
|---|---|---|
| **our volume** | our ads history | what this subject takes for us today |
| **market volume** | the search-query report — the query's total impressions, clicks and purchases | how much this demand is worth **on Amazon**, whether or not we are in it |
| **our share** | the two together | the **headroom**: how much of it we are not capturing |

This is the missing input, and it is already in the warehouse and used by nothing. The search-query data
carries market totals alongside our own figures, our impression share, the query's volume, and the median
price of the item clicked — which is a positioning signal rather than a cost one, and worth keeping
distinct from CPC.

**What headroom makes possible.** It is the input `rank()` (§2.4) needs to propose a subject never bought
— the research found no usable candidates precisely because nothing looked here. It is the ceiling on
§2.5's volume curve: available clicks are a market quantity, not an extrapolation of ours. And it turns a
dormant subject's silence into a measurable question — a query the market buys weekly, on which we hold a
fraction of a percent of impressions, is not evidence that the subject is dead.

**On probation like any external evidence (§2.3).** The query-to-subject join is not one-to-one, the
totals are market-wide rather than ours, the data is weekly, and coverage is partial. Market volume may
size an opportunity and inform a curve; it may not by itself move a verdict to `WORTH`.

### 2.9 Negatives are a Catalog answer, and they expire

Blocking a search term is a statement about **worth** — this traffic is not worth buying — so it belongs
to the Catalog, not to whichever engine happened to notice it.

This gives the Brain a third question, beside "what is this worth" (§2) and "what is worth having" (§2.4):

```
catalog.improve(subject, window_from, window_to)  ->  ordered suggestions
```

*"How do I make this better?"* One available answer is **negate this search term**. Others are the
ordinary moves — reprice, park, change what carries it (§2.6) — ranked the same way as anything else, by
what they are worth.

**And the answer expires.** When the Brain asks again a month later, the Catalog may answer **remove the
negate** — for the very same term — on either of two grounds:

- **the data now says so.** A term blocked on a thin or seasonal record is a judgement, and judgements are
  re-made when the evidence changes (§4: worth is answered for a *requested window*, and a term worthless
  in July may not be worthless in December).
- **the peak makes it worth re-learning.** A high-volume term (§2.8) blocked before a season may be worth
  unblocking simply to buy data, even without a positive record — the same logic as funding a question
  (§3 `TEST`). Volume is the reason; a term nobody searches is never worth re-testing.

So **a negative is a standing answer with an expiry, not a permanent state.** Nothing may treat "we
negated this once" as settled, and the set of live negatives is re-asked like everything else.

**Removal is executable — the gap is in our hands, not the platform.** A negative can be archived by
bulksheet like anything else: an `Entity: Negative Keyword` row with `Operation: Update` and
`State: archived`, addressed by the negative's id. The account's registry holds that id for every live
negative, and a removal has been executed before. **What does not exist is the generator arm** — every
book this account builds emits `Operation: Create` for negatives and nothing else, so the Catalog's
"remove the negate" answer currently has no book to travel in.

One real constraint remains and shapes what the Catalog can reconsider: the record of what is negated is
a **local registry**, not a read-back from Amazon, because the negative feed has been frozen since early
2026. So the Catalog can only reconsider negatives the registry knows about, and a negative created
outside our books is invisible to it. That is a coverage limit on the question, not on the answer.

---

## 3. The Brain → Pacing contract

The Brain issues an intent, a constraint, and — when it is buying an answer — a budget and a deadline.

| the Brain issues | meaning | Pacing's obligation |
|---|---|---|
| `REPAIR · ceiling C` | worth is known; do not pay above C | move to the ceiling; **never exceed it** |
| `TEST · seat $X/day · N clicks by date D` | worth is unknown and we are buying the answer | push for clicks within the budget; report back if unbuyable |
| `PARK` | not worth **now**; keep it alive | hold at the channel floor **and owe a periodic re-test** — see below |
| `STOP` | not worth in any season | execute the pause |
| `EARN` | it is working; do not disturb | small daily maintenance only |

**Two groups, and no third.** Every keyword is either **answered** (the Brain acts) or has an **open
question** (the Brain funds it and demands a verdict). *"Nothing to do"* is not a legal state — it is
how keywords sit in limbo, spending or dormant, owned by no one.

**A park is not a resting place — it carries a re-test obligation.** A parked subject takes no clicks, so
it generates no evidence, so no layer can ever discover that it recovered: the Catalog learns nothing new,
the Brain's window stays empty, and the subject can sit forever. Measured (§10.1), the overwhelming
majority of parked subjects take zero clicks in a week. A park is therefore an **absorbing state** unless
something deliberately buys fresh evidence.

So Pacing owes a park periodic clicks — enough to produce a verdict, not enough to bleed — and the Brain
funds that re-test exactly as it funds any other question, with a budget and a deadline (`TEST`). If the
re-test buys clicks and no orders, the answer is confirmed and the park continues. If it buys orders, the
Brain promotes. **The re-test cadence is a setting, not code** (§3.3), and therefore something §6.1 can
answer with evidence.

**RULED by Ori, 2026-08-25 — the cadence is per family, on two occasions, gated on volume.** A park is
re-tested **once off-season and once at the December peak**, and only **if the subject's volume is worth
it**. Three consequences follow and none of them is optional:

1. **The cadence is a family property, not an account constant.** Each family declares its own two dates
   in `DE_PLAN_CONFIG`, because families do not share a season — the off-season month for one is the
   ramp for another. There is no global re-test interval, and any code that assumes one is wrong.
2. **Volume is the gate, and it is the Catalog's answer, not the Brain's guess.** §2.8's market volume
   decides whether a re-test is worth buying: a term nobody searches is never worth re-testing (§2.4), so
   the appointment is *skipped* rather than deferred, and the skip is recorded with its reason. A skipped
   re-test is a decision, not an omission.
3. **Two occasions is a ceiling, not a floor.** A park whose volume does not clear the gate gets **zero**
   re-tests, and stays parked with the Catalog saying plainly why. This is the doctrine deliberately
   accepting that some parks are permanent — but only ones we can name the reason for.

The December peak occasion exists for a specific reason Ori named: peak is when a high-volume term is
worth unblocking **simply to buy data** (§2.9 makes the same argument for negatives). Evidence bought at
peak is the cheapest evidence of the year per click, and a subject that cannot earn at peak has been
answered about as thoroughly as this account can answer anything.

**What this does NOT settle:** how many clicks a re-test buys, and at what price. That is the seat's
funding question below, and it remains a §6.1 experiment.

**Live evidence this rule is not being honoured today.** Every one of the 544 parked subjects carries a
`next_check_date` — none is missing. **63 of those dates have passed and nothing acted on them**, the
oldest by 281 days (`V_CATALOG_DWELL`, 2026-08-25). So the appointment is *recorded and never read as a
trigger*: the machinery to schedule a re-test exists and the machinery to honour one does not. That is a
narrower and more fixable defect than "parks are absorbing", and it is what violation 14 should be read
as meaning.

**The seat must fund the answer it demands.** If the Brain wants N clicks by date D, the seat is
priced `(N x expected CPC) / days`, not by what the keyword happened to spend last window. A
half-funded question answers nothing and wastes the money; prefer fewer, fully funded questions.

### 3.1 Speed of movement — direction matters

The house's per-upload cap (three blind 5% steps: +15.76% / −14.26%) exists because *a hand upload
cannot observe*. It is a pacing constraint, not an evidence one, and it should not be symmetric.

- **Cutting to a known ceiling with HIGH confidence: go immediately.** A cut to a ceiling cannot
  overshoot — the ceiling is the target. The clicks lost above it lose money by definition.
- **Raising into unknown territory: walk it.** There is no stopping point, so overshoot is real
  waste. Keep the blind-step limit.
- Pacing keeps one veto on immediacy: if a sharp drop surrenders a placement that is expensive to
  regain, it may walk instead — within the ceiling, never above it.

### 3.2 The Brain is restless — including about what is already earning

The Brain's job is not only to stop losses. **It must always be asking what it could do better, and that
includes the earning side.** "Leave it alone" (§3, `EARN`) is a protection against churn, not a licence to
stop thinking: a keyword that is working may still be underfunded, priced below what it could afford, or
winning a placement it could win more of.

So the Brain carries a sixth intent:

| the Brain issues | meaning | Pacing's obligation |
|---|---|---|
| `LEAN_IN · ceiling C` | the evidence improved and we believe it; spend more here | raise toward the new ceiling, gradually (§3.1 — this is a raise) |

And one intent that is not about a single subject at all, which §2.6 makes possible:

| the Brain issues | meaning | Pacing's obligation |
|---|---|---|
| `CARRY · vehicle V` | this demand should be bought through this format, placement or creative rather than another | shift budget and bids toward V; do not re-open the choice daily |

A vehicle decision is slower-moving than a bid and belongs to the Brain, because it is an allocation
question — which instrument carries the family's money — not an auction question.

Two populations it must look at every window, not just the losing side:

- **Turns** — the record says losing, the window says earning. Today the Brain only *protects* these
  (`move = NONE`); protection is not investment, and a keyword that has genuinely turned is the cheapest
  growth in the account because the evidence is already bought.
- **Constrained winners** — earning, but capped: out of budget, losing impression share, or bidding below
  the ceiling the Catalog would allow. The money is available and the worth is proven; nothing currently
  asks the question.

The asymmetry with §3.1 stands: **a `LEAN_IN` is a raise into partially-unknown territory and is walked,
never taken in one step.** The evidence supports the direction, not the magnitude.

### 3.3 The Brain's open questions are settings, not code

The Brain's own uncertainties — the window length per calendar state, the allowance share, the
minimum-orders floor, the verdict click count, the ramp step — are all declared constants in
`DE_PLAN_CONFIG`. That is deliberate: a setting can be tested, and code cannot. How they are tested,
and the discipline that keeps the answers honest, is §6.1.

---

## 4. Seasonality belongs to the Catalog

Neither the Brain nor Pacing should know that Christmas exists.

The Catalog answers for a **requested window**, not for "now" — that is what lets the Brain plan
November in October. For a seasonal subject the honest answer is not one number; a trailing-window
average is the wrong estimator for a seasonal series.

Three verdicts must stay distinct, because they license different actions:

| verdict | meaning | what it permits |
|---|---|---|
| `NOT_WORTH` | no value **in any season** | a one-way action (pause, archive) |
| `NOT_WORTH_NOW` | no value **in this season**, value in another | **park at floor — never pause** |
| `UNKNOWN` | no evidence either way | buy an answer, or park. **Never** a one-way action |

Collapsing `NOT_WORTH_NOW` or `UNKNOWN` into `NOT_WORTH` is the single most expensive mistake this
doctrine exists to prevent (Appendix B).

### 4.1 A campaign is a seasonal subject too — and pause is its only park

**Seasonal campaigns must be opened and closed at the right time, and that is a Brain question the Catalog
answers.** The Brain asks; the Catalog answers for the window requested; the Brain acts with enough lead
time for the answer to be worth anything.

The Catalog therefore answers for a **campaign** as a subject, not only for keywords and targets (§2.1).
Nothing in the doctrine ever said otherwise, but nothing said so explicitly either, and the omission is
expensive: a seasonal campaign is `NOT_WORTH_NOW` in the summer and `WORTH` in November, exactly like a
seasonal keyword, and no layer currently has a verdict for it at all.

**The asymmetry that makes this urgent: a campaign has no park.** A keyword can sit at its floor —
visible, costing pennies, re-judgeable (§3, §4). A campaign is on or off. So the only available
expression of `NOT_WORTH_NOW` at this grain **is** a pause, which means the campaign pause is the one
irreversible action the doctrine must permit on something other than `NOT_WORTH`.

It is permitted only on one condition: **a seasonal close carries its reopen date.** A campaign paused
because its season ended is a scheduled close, not a kill, and the reopen must be recorded where a layer
will act on it — not remembered by a person. A close without a reopen date is the one-way door of §5
wearing different clothes.

Two campaign-grain intents follow:

| the Brain issues | meaning | Pacing's obligation |
|---|---|---|
| `OPEN · by date D` | the Catalog says this campaign is worth running in the coming window | enable it with enough lead time to re-learn before the window opens |
| `CLOSE · reopen D` | its season has ended | pause it, and carry the reopen date |

**Lead time is part of the answer, not an afterthought.** A campaign enabled on the first day of its
season has not been running when the season starts: it needs time to re-accumulate the signal Amazon
prices it on. So the Catalog's answer for a November window must be available in October, which is only
possible because it answers for a **requested** window (§4) rather than for "now".

**Measured 2026-08-24 (§10):** ten paused campaigns carry 2,826 orders and $127,352 of last-season sales
at a pooled GP-ROAS of 1.49 — well above every family bar. Five of them stopped on a single day in
mid-July, so this was a deliberate seasonal wind-down and not decay. **Nothing anywhere holds a reopen
date for any of them.**

**A measurement hazard, recorded because it nearly inverted this finding.** Campaign names change.
`DIM_CAMPAIGN` holds today's name while `FACT_AMAZON_ADS` holds the name as it was, so any campaign-level
history keyed on name silently misattributes renamed campaigns — the first pass at this measurement
showed these campaigns as near-dead, and only a join on `campaign_id` revealed December returns of
3.4x to 7.1x. **Join campaign history on the id, never on the name.**

---

## 5. Irreversibility

**Only the Brain may take an irreversible action, and only on `NOT_WORTH` with HIGH confidence.**

Pacing, the books and the generators execute; they never originate a kill. A pause removes a keyword
from `FACT_KEYWORD_STATE` entirely — after that no layer can see it, judge it or revive it. That is a
door that only closes, and a silent window is not evidence that it should.

**A silent window is never evidence of worthlessness.** A keyword that takes no clicks may be dormant,
seasonal, or simply bid too low to win an auction — three very different things that look identical
to a window-based judge.

### 6.3 A loss must be demonstrated, not asserted

The baseline research (§10) produced four confident, well-measured claims about money being wasted. All
four had sound arithmetic. Three of them were wrong, and they were wrong in the same way: **a population
was measured correctly, and then a loss was asserted without testing the obvious innocent explanation.**

So the discipline §6.1 applies to method questions applies equally to analysis:

> **Name the innocent explanation and test it before claiming money was wasted.** A finding that has not
> survived its own best counter-argument is a hypothesis, not a measurement.

The innocent explanations that actually fired, and are therefore the standing checklist:

| the claim | the innocent explanation that proved true |
|---|---|
| "we overpaid into a dead market" | the price barely moved; **volume** rose and conversion fell — a demand shift, not a pricing error (§2.5) |
| "pausing these destroyed their sales" | the demand was **recaptured** by a wider match already running (§2.6) |
| "something keeps cutting already-floored keywords" | those cuts **were** the parking actions themselves |
| "the account overspends its bar by $X" | the metric summed one-sided deviations; the account clears its bar **in aggregate** |

Two rules fall out of the last one, because they will recur:

- **A one-sided metric always finds what it looks for.** Any sum of `GREATEST(actual − target, 0)` is
  positive under ordinary dispersion even when the population is healthy. Report the net alongside it, or
  do not report it.
- **Beware selecting on the pattern noise produces.** A cohort chosen for "recent window bad, long record
  good" will be populated by regression to the mean at small samples. Test that the deterioration
  persists out of sample before calling it decline.

### 6.4 Open rulings — decisions the doctrine is waiting on

Recorded here so a deferral stays a deferral rather than quietly becoming a default. Each names what
would settle it.

| ruling | status | what would settle it |
|---|---|---|
| ~~The confidence scale~~ | **SETTLED 2026-08-24 — §2.7: separation × stability, with `NO_EVIDENCE` distinct from `LOW`.** | — |
| **Agreement-tier ranking** — when the long record and the short window disagree, should the seat queue prefer subjects both judges condemn? | **deferred by Ori, 2026-08-24** | a real case: a confirmed candidate with real money queued behind a lower-ranked disputed one that got funded. At the time of deferral every confirmed candidate in the queue carried $0 at stake, so nothing was being lost |
| ~~**The re-test cadence for a park**~~ | **SETTLED 2026-08-25 by Ori — §3: per family, once off-season and once at the December peak, gated on the subject's volume being worth it. Zero re-tests if volume does not clear the gate, recorded with its reason.** | — (how MANY clicks a re-test buys, and at what price, stays open — §6.1) |
| **The boost allowance share** — 0.50 in the run-up to a peak | **open — flagged unproven** | §6.1, or the free shadow plan |

---

## 6. Every layer must get better on its own

**All three layers are recomputed daily, and all three are obliged to ask what they could do better.**
A layer that only executes its current rules is a layer that decays: the account changes, the season
turns, Amazon's auction moves, and a fixed rule silently drifts out of correctness. Improvement is part
of the job, not a project someone schedules.

Each layer is graded on **its own question**, which is what lets it improve without waiting for the others:

| layer | its scorecard asks | how it is measured |
|---|---|---|
| **Catalog** | *was the valuation right?* | its own predictions against outcomes — "in October you said this was worth 4.6x in December; was it?" |
| **Brain** | *did the money go to the right places?* | the shadow plan at T+14 — would the other allocation rule have earned more? |
| **Pacing** | *did it deliver what it was asked for, at the price it predicted?* | clicks and CPC actually achieved against the bid it chose and the outcome the Brain paid for |

**Pacing's scorecard is the one nobody thinks to build**, and it is the only way to know whether "bid
$1.27 to buy decision data" actually buys decision data, or whether the entry anchor is simply a number
the house has never checked.

### 6.1 Answering methodology questions — the control group

Some questions cannot be answered by looking harder at existing data, because they are about the method
itself: is a 3-day window right in peak, or 7, or 1? Is the boost allowance 0.50 or 0.35? Is the
2-order floor hiding slow converters? Is the entry anchor at 1.5x target CPC the right price to buy a
verdict? **These are settings, not code** — every one is a declared constant — and settings are exactly
what a control group can test.

The 10 % holdout (`DE_HOLDOUT_ASSIGNMENT`) therefore serves two purposes: the standing engine-vs-nothing
baseline, and the instrument for questions like these. Rules:

- **Never experiment on the control arm.** It is the "do nothing" baseline; contaminating it destroys
  the only clean comparison the account has. Method questions are asked by splitting the *treated*
  population.
- **Declare the question before running it** — which setting, which slice, what outcome decides it, by
  when — so the result cannot be read after the fact to suit a preference.
- **The answer is a setting change, never a code change.** If answering it needs new code, it was not a
  question about a setting and does not belong in this mechanism.
- **Ask the free version first.** The shadow plan runs a second allocation rule every night at no cost;
  any question expressible as "would the other rule have allocated better" is answered there before
  anything is asked of real money.

### 6.2 The attribution discipline — the price of improving everywhere

Three layers improving at once destroys the measurement that justifies any of it: a Pacing change and a
Brain change in the same family in the same week make both unreadable, and the outcome is attributed to
whichever story is told most confidently afterwards.

So: **one layer experiments at a time within a family**, or the experiments run on disjoint families.
Everything else — the daily recompute, the routine self-questioning, improvements that are provably
neutral — continues everywhere. It is only *live method experiments* that must not overlap.

A corollary: **a layer cannot be graded on predictions it does not keep.** Any layer expected to
improve must retain its own answers. The Catalog did not, until 2026-08-24: `FACT_KEYWORD_STATE` was
replaced every night and held one day (violation 6, now CLOSED — `FACT_KEYWORD_STATE_HISTORY` keeps
every ladder row per day and `V_CATALOG_DWELL` reads it). The retention exists; the Catalog's
scorecard itself is still to be built, and the Brain's and Pacing's answers are still not retained.

## 7. What this doctrine forbids

- A Catalog verdict that reads as a command.
- The Brain judging a keyword on its own window alone, ignoring the Catalog.
- Pacing raising or lowering a bid on a keyword the Catalog has answered conclusively, outside the
  Brain's ceiling.
- Any layer treating a silent window as proof of worthlessness.
- A one-way action from any layer except the Brain, on any verdict except `NOT_WORTH`.
- A seat that demands an answer it does not fund.
- A generator or book that stands aside for an engine on an answered keyword (precedence is: the
  Brain's instruction wins).
- Pricing to an average CPC where a marginal one is the correct number.
- Pricing a subject without regard to how much volume is being bought at that price (§2.5).
- Valuing a subject as if no other vehicle in the account could serve the same demand (§2.6).
- Asserting a loss without naming and testing the innocent explanation (§6.3).

---

## 8. Known violations in the system as built (2026-08-24)

Recorded honestly so the gap is visible; each is a defect against this doctrine, not a design choice.

**Catalog**
1. It emits commands — `WINNER` / `DEAD` / `REPRICE` flow into books as actions.
2. It is not seasonal, though two full holiday seasons of ads data exist.
3. It has no marginal model: the affordable price is an average, and no response curve or elasticity
   exists anywhere.
4. It sees only what the account already spent — **no demand data (SQP) reaches it at all**, so it can
   describe what was captured but never what was available. And it does not even see all of *that*:
   §10.1's "outside the Catalog entirely" is spend the Catalog's own universe never met.
   **MEASURED, NOT FIXED (2026-08-25).** The second half of that sentence is now countable daily
   rather than rediscoverable by a research pass: `V_UNOWNED_SPEND` lists every spending subject with
   no row in `FACT_KEYWORD_STATE`, at target grain, with the reason it is invisible classified into
   four classes and six named reasons, a live 7-day figure beside the 28-day one so a tail cannot be
   read as a leak, and the family bar it *would* be judged against where a family exists.
   `V_UNOWNED_SPEND_SUMMARY` carries the account total and its share. Both are reporting only — they
   read, write nothing, are read by no engine or book, and are not in the orchestrator, so asking
   changes nothing (§1.4). **The violation is not closed.** Nothing is wired into the universe, no
   subject gained a verdict, a seat, a ceiling or a stop, and doing so would move money — it is Ori's
   decision with this evidence in front of him, not a consequence of having measured it. The first
   half of the violation, SQP demand data reaching the Catalog, is untouched.
   SOP: `architecture/UNOWNED_SPEND.md`.
5. It cannot propose candidates: there is no `rank(family, window)`, so the Brain can only judge
   keywords that already exist and already spend.
6. ~~**It keeps no memory** — the state table is replaced nightly and holds one day, so the Catalog
   cannot be graded on its own predictions and §6 is currently impossible to satisfy.~~
   **CLOSED 2026-08-24 (commit `ca01597`).** `FACT_KEYWORD_STATE_HISTORY` is an append-only,
   snapshot_date-partitioned copy of the WHOLE ladder row, written by
   `SP_APPEND_KEYWORD_STATE_HISTORY` as orchestrator Task 20.8a immediately after the snapshot is
   built. The whole row, not a `(date, subject, state)` triple, because §6 asks *was the valuation
   right?* and a verdict stripped of the record it was read off, the bar, the noise band, the
   affordable price and the promised appointment can be counted but never graded. The write is
   append-first and idempotent — it inserts, then prunes any `snapshot_date` carrying more than one
   `captured_at` down to its newest stamp — so two passes leave one copy and a crash between the two
   statements leaves a duplicate rather than a lost day, repairable by any later call on any date.
   A pass may NOT restamp a build the history already holds: Task 20.8 has its own exception
   handler, so a failed build leaves the previous build's table standing, and copying it again would
   move that partition's `captured_at` while the build behind it stood still. That copy is refused,
   and the test is on the BUILD rather than the calendar — the writer compares the snapshot table's
   own last-modified clock against the stamp the history carries for that date, and records it as
   `snapshot_built_at` (repaired twice: v27.144 scoped the prune to whichever date the live snapshot
   happened to carry, which made both self-healing properties conditional; v27.145 replaced a
   date-only guard that was blind inside a single LA day — which is where most passes run, since
   several share one LA date every night). It carries no
   hard-coded column list, so §2.7's `confidence`, §2.8's market volume and §4's seasonality will be
   kept the night they exist, with earlier partitions honestly NULL. `V_CATALOG_DWELL` answers §10.4's
   question over it, publishing dwell as a BOUND with a stated basis (`EXACT` / `BETWEEN` /
   `AT_LEAST`) rather than a number a short history cannot support. Seeded from BigQuery's own
   seven-day table history — real snapshots at their true dates, nothing invented; the account had no
   other surviving copy. **What is closed is the RETENTION, not the scorecard**: the Catalog now keeps
   its predictions, so §6 can be satisfied. Building the scorecard that grades them is still open.

**Brain**
7. It ignores the Catalog, judging on its own window; a quiet window yields `NOT_SERVING` — the
   "nothing to do" state this doctrine forbids.
8. Seats do not fund the answers they demand.
9. `NOT_WORTH_NOW` does not exist, so dormant seasonal subjects are paused as dead.
10. It protects turns but never funds them: `LEAN_IN` is doctrine, not code.
11. Ranking uses a proxy (dollars at stake x closeness) because no marginal value exists.
12. ~~It covers part of the account and the uncovered remainder is a hole.~~ **CORRECTED 2026-08-24
    (§10.3): the entire Catalog-to-Brain gap is deliberate — launch families plus brand defense. There
    is no hole here.** The real uncovered money is Catalog-side, in violation 4.

**Pacing**
13. It has no scorecard: nothing measures whether the bid it chose delivered the clicks and CPC it
    implied, so house constants like the entry anchor have never been checked.
14. **A park carries no re-test obligation.** Measured today, the overwhelming majority of parked
    subjects took zero clicks in a week — a park is safe from cost and safe from discovery at once, so
    a recovery there can never be found by anyone.

**Quantity and vehicle** (found by the §10 baseline)

17. Nothing anywhere decides **how many** clicks to buy — worth is a scalar price, not a curve over
    volume (§2.5).
18. The Catalog does not know **what is advertised** — format, placement, creative or match width — so it
    cannot say which vehicle should carry a demand, nor tell a destroyed sale from a recaptured one (§2.6).
19. Term composition is treated as an auto-mode problem; measured, **BROAD drifts nearly as hard and
    carries far more money** (§10.1).
20. `confidence` is specified (§2.7) but not computed anywhere, so §5's irreversibility rule is
    unenforceable in code.
22. **The Catalog has no verdict for a campaign** (§4.1), so nothing can say whether a seasonal campaign
    should be running. Ten paused campaigns carry $127,352 of last-season sales at 1.49 GP-ROAS and
    **not one holds a reopen date**.
23. Campaign-level history keyed on **name** misattributes renamed campaigns; only `campaign_id` is
    stable (§4.1).
24. **`improve()` does not exist and negatives have no owner in code** (§2.9). Blocking decisions are made
    by whichever engine notices a term, nothing re-asks them, and no live negative is ever reconsidered —
    so "we negated this once" is treated as settled, which the doctrine forbids.
25. **No generator can remove a negative** (§2.9). Every book emits `Operation: Create` for negatives and
    nothing else, though the platform accepts an archive row and the registry holds the id for every live
    negative. The Catalog's expiry answer has nowhere to go until that arm exists.

21. **Market volume is in the warehouse and used by nothing** (§2.8). The search-query data carries the
    query's total impressions, clicks and purchases beside our own and our impression share; no layer
    reads it, so no subject can be valued on the demand available rather than the demand we captured.
    **STILL UNMEASURED (2026-08-25).** The work that closed the measurement half of violation 4 did
    nothing for this one — `V_UNOWNED_SPEND` reads no market volume at all. Recorded here so the two
    are never confused: "money we spend that no layer sees" and "demand we could buy that no layer
    sees" are different holes, and one of them being counted says nothing about the other.

**Boundaries**
15. The book defers to Pacing on answered subjects (`ENGINE_INSTRUCTED`) — precedence backwards.
16. ~~The move cap is symmetric, so a confident cut is slowed as much as a speculative raise.~~
    **CORRECTED 2026-08-24 (§10.3): the cap is not enforced in either direction — both sides break it,
    and cuts break theirs proportionally more often than raises break theirs.** Asymmetry (§3.1) is
    still the right design; the prior defect is that no cap binds at all.

### 8.1 The Research module already does part of the Catalog's job — outside the layers

**Raised by Ori, 2026-08-25: "in research page we built already a research module — are the modules the
same? can the catalog do today what the research is doing?"** Checked, and the answer changes how four
violations should be read.

`FACT_RESEARCH_RANKED` / `V_RESEARCH_RANKED` already computes, for 363,055 terms:

| what it computes | the violation that says nothing does this |
|---|---|
| `weekly_market_impressions` / `_clicks` / `_purchases` | **21** — "market volume is in the warehouse and **used by nothing**" |
| `cvr_christmas`, `cvr_easter`, `cvr_valentines`, `cvr_mothers_day`, `cvr_back_to_school`, `cvr_graduation`, `is_holiday_active` | **2** — "it is **not seasonal**, though two full holiday seasons of ads data exist" |
| `rank`, `overall_fit`, `purchase_rank`, and `FACT_RESEARCH_RECOMMENDATIONS` (623 live ADD candidates by match type) | **5** — "it **cannot propose candidates**: there is no `rank(family, window)`" |
| `est_cps_curve` — clicks-per-sale as a **curve**, not a point | **17** — "worth is a **scalar price, not a curve** over volume" |

Each of those violations is literally true — *no **layer** reads it* — and materially misleading, because
the capability exists in this account and has for months. **The violations were written from inside the
doctrine and the doctrine did not know about Research.** That is the failure §6.3 warns about arriving
from the other direction: not asserting a loss without testing the innocent explanation, but asserting an
absence without checking the whole account.

**They are not the same module, and the difference is the dangerous part.**

- **Different population.** The Catalog values 649 subjects the account **owns**. Research ranks 363,055
  terms it **could** own. But they are not disjoint: **291 of the 649 — 45% — are ranked by both.**
- **Different question, and this is the real divergence.** The Catalog asks *does this earn at least the
  family bar?* — a profit question, bar-relative, in gross-profit dollars per ad dollar. Research asks
  *how well does this term fit, and how efficiently does it convert?* — a 0–100 fit score against a
  market CPS curve. **`V_RESEARCH_RANKED` does not reference the family bar anywhere** (checked).

So on 291 terms this account holds two independent valuations, computed from different inputs against
different standards, with **no rule saying which wins**. Nothing has gone wrong yet only because nothing
consumes both. The moment `rank()` is wired, it would.

**The ruling this needs is not "rebuild it in the Catalog".** Rebuilding would discard working market and
seasonal machinery and produce a *third* answer. The Catalog should **own the contract and adopt Research
as its `rank()` and market-volume arm**: Research keeps computing demand, fit and the CPS curve; the
Catalog converts them into `verdict` / `ceiling_cpc` / `confidence` **against the family bar**, so exactly
one definition of worth leaves the layer. Research stops being a page and becomes a source.

**What must be true before that wiring, and is not true today:** one term must not be able to receive two
verdicts. Whatever the Catalog publishes for a subject it owns must be the same answer Research's rank
implies for that same term, or the disagreement must be surfaced rather than resolved silently (§9).

---

## 9. How the UI must present a decision (binding on future implementation)

**Every action shown to a person is explained top-down, through the three layers, in order.** Never a
bare instruction, never a single number, never one layer's reasoning standing alone. A reader must be
able to see *what is true*, *what we decided to do about it*, and *how it will be executed* — and to
tell which layer to argue with.

The order is fixed, because it is the order in which the decision was actually made:

| shown | from | answers |
|---|---|---|
| **1. Catalog** — what this is worth | the Catalog's answer for the window in question, with its confidence and the season if it matters | *why do we believe this?* |
| **2. Brain** — what we decided | the intent (`EARN` / `LEAN_IN` / `REPAIR` / `TEST` / `PARK` / `STOP`), the ceiling or the seat and its budget, and why this and not something else in the family | *why are we spending — or not spending — here?* |
| **3. Pacing** — what happens in the account | today's bid, the path (immediately or walked), the floor or cap that binds it, and what reaches Amazon | *what will actually change?* |

Rules for the surface:

- **Attribution is always visible.** A number on screen names the layer that produced it. A reader who
  disagrees must be able to tell instantly whether the argument is with a valuation, an allocation, or
  an execution.
- **A disagreement between layers is shown, never hidden.** When Pacing wanted something the ceiling
  forbade, or the Catalog's answer changed the Brain's mind, that is the most informative thing on the
  row — surface it rather than showing only the surviving instruction.
- **`NOT_WORTH_NOW` and `UNKNOWN` must read differently from `NOT_WORTH`** in words a person can act
  on ("dormant until November" is not "dead"). The three must never render alike.
- **An irreversible action carries its justification on the row** — the verdict, the confidence, and
  the fact that no season contradicts it (§5).
- The same three-part shape applies wherever a decision appears: the Weekly Run list, a keyword drill-
  down, the morning brief, and the README of any book that is uploaded.

---

## 10. Baseline — where the money actually is (measured 2026-08-24)

This section is the doctrine's **first assumption**: a dated measurement of how much of the account each
failure mode touches, taken so that it can be **re-measured later and compared**. It is the declared
exception to Standing Rule 0 — figures are pinned here on purpose, and every one carries its query in the
research record so a re-run is a re-run and not a fresh argument.

**Read the units before the numbers.** Four incompatible things are easy to rank as if they were one:
current spend on a population, current spend *above* what the record supports, last season's net divided
by the season's days, and a counterfactual efficiency delta. They are not commensurable. Every figure
below states which it is.

**Account context.** Roughly $1,320/day of spend is attributable to a subject; the full run rate is
around $1,375/day. Pooled gross-profit-per-ad-dollar across the account is **above** the reference bar —
so the account is not in aggregate losing money, and no finding below should be read as if it were.

### 10.1 What survived both verifiers

| finding | what it is | size | unit | confidence |
|---|---|---|---|---|
| **Outside the Catalog entirely** | Spending rows with no Catalog row at all — chiefly SB product targets arriving under a sentinel `keyword_id = '-1'`, unowned since June. No layer can see them; nothing reconciles ads spenders against the keyword universe. | **$132.71/day** at 0.528 GP-ROAS, against 0.906 inside the Catalog. 74 rows | current spend | HIGH |
| **The slow converter** | Rule B needs two orders inside the window. For subjects converting below about 5 %, that takes ~69 days on average — so the window re-condemns them forever. For subjects the window *can* see it works well (3.9 days). | **216 subjects, $273.53/day** | current spend | HIGH |
| **The seat is last window's spend** | Not merely undersized — an identity. Correlation between seat cost and prior-window spend is **0.995**, mean ratio 0.973. The seat has no relationship to the price of the answer it demands. | 40 of 53 live seats underfunded, holding $29.73/day | current spend | HIGH |
| **The drifting basket** | Measured against an EXACT control at 19.1 % month-over-month term turnover: BROAD drifts at **63.7 %**, auto modes 57–68 %. §2.1 blamed auto modes; the money is in BROAD. | BROAD alone carries **$468.73/day** | current spend | HIGH |
| **The umbrella** | Subjects the Catalog's own test calls conclusively below bar, still spending. Median 19 days in that state. | 84 subjects, **$137.96/day above** what the record supports | excess over bar | HIGH |
| **Decided, logged, never uploaded** | Correct decisions that never reached Amazon. Restricted to keywords also conclusively below bar today: 11 subjects. | **$28.40/day** excess; oldest unexecuted decision 17 days | excess over bar | HIGH |
| **The park trap** | Parked subjects take no clicks, so they generate no evidence, so no layer can ever discover a recovery. A park is an absorbing state. | 31 dark-parked subjects earned **$202.86/day** of net in last year's season | last season's net ÷ season days | HIGH |
| **The harvest gap** | Search terms converting well with no keyword of their own. Nothing promotes a converting term to a subject. | 130 terms, 488 orders, **$56.10/day**, CVR 6.49 % against an account 3.97 % | current spend | MEDIUM — survivorship-selected |

### 10.2 Claimed and disproved — the record of §6.3

Kept deliberately. Knowing that the January trough was **not** a pricing failure is worth as much as any
finding above, and a doctrine that quietly deleted its wrong answers would teach nothing.

| claimed | what killed it |
|---|---|
| A post-season month cost ~$300/day because a trailing window held holiday prices | Cost per click moved only ~8 %. Clicks rose ~28 % and conversion fell ~18 %: the account bought **more** clicks at the right price. The trough was still profitable. **A demand shift, not mispricing** — and the reason §2.5 exists. |
| ~$240/day of last season's net was destroyed by pausing 79 keywords | About **87 %** of those sales had their exact query bought elsewhere in the account within 28 days, through a wider match. The traffic changed vehicle. **The reason §2.6 exists.** |
| Something keeps cutting keywords already at the floor | Those cuts **were** the parking actions — average bid before them $0.69, after $0.29. Misread, not malfunctioning. |
| The account overspends its bar by ~$210/day | The metric summed one-sided deviations. Pooled, the account is **above** its bar. The figure is a dispersion artefact, not a loss. |
| The kill gate is jammed by a circular dependency | The fields cited are NULL **by definition** outside probation. The count carried no information. |
| The pre-season signal is 8.9x wrong | Base rate omitted. The trailing signal separates a 41 % hit rate from 78 % — informative, not blind. |

### 10.3 What the research corrected in this document

Three of §8's violations were wrong, and are corrected in place:

1. **Coverage (was violation 12).** The claim was that the Brain covers only part of the account and the
   remainder is a hole. Measured, the entire gap is **deliberate**: launch families plus brand defense.
   There is no hole. What is *not* covered — and is a real defect — is §10.1's "outside the Catalog".
2. **The move cap (was violation 16).** The claim was that the cap is symmetric and so slows a confident
   cut as much as a speculative raise. Measured, **both** sides break their nominal caps, and cuts break
   theirs proportionally *more often* than raises break theirs. The defect is that the cap is not
   enforced, which is a different and larger problem than asymmetry.
3. **Demand data as a candidate generator (§2.4).** The section assumed search-query data would let
   `rank()` propose subjects the account has never bought. Measured, it yields **no usable candidates**
   today. §2.4's mechanism stands; its assumed input does not exist yet, and the harvest gap in §10.1 is
   the nearer path to the same goal.

### 10.4 What could not be measured, and why it matters

- ~~**Dwell time in any state.** The Catalog holds one snapshot and is replaced nightly, so no "how long
  has this been stuck" question is answerable anywhere. This is violation 6 obstructing the measurement
  of every other violation, and it is the single highest-value thing to fix first.~~
  **MEASURABLE FROM 2026-08-24 (commit `ca01597`)** — `V_CATALOG_DWELL` over
  `FACT_KEYWORD_STATE_HISTORY`. Read the answer with the caveat it carries: dwell is published as a
  BOUND with a basis, and a subject whose run reaches the start of the history reads `AT_LEAST` with a
  NULL maximum, because the true start is genuinely unknown. Every re-measurement of §10 from here on
  should state `history_days` beside any dwell figure, since a censored population shrinks as the
  history lengthens and a dwell distribution taken today is not comparable to one taken in a month.
- **Bid-to-click response.** Nothing records the clicks and price a chosen bid was expected to deliver
  against what it delivered, so §2.5's curve cannot yet be estimated and Pacing cannot be graded at all.
- **Seasonal versus dead.** Two holiday seasons sit in the ads data and the Catalog does not read them, so
  a dormant subject and a dead one remain indistinguishable — the failure §4 exists to prevent.
- **Marginal versus average value.** Every "excess" figure above is computed against an average ceiling and
  therefore misstates the true overpayment in an unknown direction.

### 10.5 How to re-run this

Every query behind §10 is committed at `docs/superpowers/specs/2026-08-24-three-layers-baseline.md`
— 76 of them, grouped by probe, with the measurement window hard-coded so a re-run is a re-run.
Move the dates and keep everything else. When re-measuring: keep the unit labels,
re-derive the account context first (a finding's share of the account matters more than its absolute
size), and apply §6.3 — for each finding that has grown, name the innocent explanation and test it before
concluding the system got worse.

## Appendix A — worked example: an answered keyword

`asin="B0CCCPFWZF"`, ME-SP/PT (Competitors, Mint, A1), LolliME. Measured 2026-08-24; re-derive with
the query in the Catalog section of `KEYWORD_STATE.md`.

Its settled record was conclusive and had been since 2026-08-04: a loss beyond the noise band, paying
roughly three times what its own record could support, with an executable affordable price above its
floor.

- **Catalog** should answer: `NOT_WORTH`, ceiling ~$0.51/click, HIGH confidence, ~1 click/week.
- **Brain** should issue: `REPAIR · ceiling $0.51` — an answered keyword, no question bought.
- **Pacing** should translate ceiling to bid through the placement multiplier and, because confidence
  is HIGH and the move is downward, go there **immediately**.

**What actually happened:** the Brain saw a quiet three-day window and said `NOT_SERVING`. The book
stood aside as `ENGINE_INSTRUCTED`. Pacing filled the vacuum with a large raise to relieve
*campaign* click-starvation — a mechanics rule making an economics decision. Twenty days, no
correction.

## Appendix B — worked example: a seasonal keyword

`diary with lock for girls`, ME-VIDEO/BROAD, LolliME, keyword 500617324681575. Measured 2026-08-24.

Its record: two strong holiday months last season, and a summer with clicks and no orders at all.

- **Catalog** should answer, for an August window: `NOT_WORTH_NOW` — with the seasonal evidence
  attached. For a November–December window, asked in October: `WORTH`, with a ceiling and an expected
  click volume large enough to size a seat.
- **Brain** should therefore **park at floor with a revisit date**, not pause.
- **Pacing** holds at the floor for pennies a day; the keyword stays visible to every layer.

**What actually happened:** the Catalog said `DEAD` on trailing evidence. The Brain read it as a leak.
It was paused, applied, and is now `paused` in `DIM_KEYWORD` with no row in `FACT_KEYWORD_STATE` —
invisible to all three layers, with no mechanism to return, three months before its season.

A scan of keywords with strong last-season sales and no orders this summer showed this is systemic,
not isolated. The query is in `FAMILY_SEAT_REGISTER.md`; run it before any seasonal pause.
