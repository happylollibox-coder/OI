# FAMILY_SEAT_REGISTER — the 80/20 doctrine for working families

**Born:** 2026-08-22. **Owner request (verbatim):** "for working families (not launch in the last 3
month) make sure 80% of budget is for winning or margin keywords / the other 20% should be for
losing … number them per family so you always know what seat you are opening and what you are
probing or waiting for results." Design spec: `docs/superpowers/specs/2026-08-22-family-seat-register-design.md`
(Approach A, approved). Plan: `docs/superpowers/plans/2026-08-22-family-seat-register.md`.

**Status:** Task 1 (the ledger) SHIPPED 2026-08-22. Tasks 2–5 (register view, leak generator arm,
morning surface, health checks) pending — this file grows with each.

## The doctrine in one paragraph

For the WORKING families — the HARVEST book in `V_BOOK_ASSIGNMENT`; the launches (INVEST) are
outside the doctrine entirely — 80% of spend should sit on keywords that are winning, at their bar,
or waiting for a verdict with volume. The other 20% is a dollar-sized allowance of NUMBERED SEATS,
each holding one keyword the family is knowingly paying for while it is repaired, on probation,
failed, probed, or settling. Closed-but-spending and untracked spend also count on the 20% side: a
family cannot pass by hiding spend in the cracks. The register prescribes keyword moves executed by
MANUAL bulksheet; campaign budgets are shown, never moved. No engine reads the register.

## Rulings (from the spec, binding)

| question | ruling |
|---|---|
| Working families | HARVEST book. Launch families appear only as a labelled reference block, never judged on profit. |
| 80% side | winning + marginal (at bar) + waiting for results. |
| 20% side | losing + everything not earning or being tested: closed-but-spending, untracked. |
| The lever | keyword moves by manual bulksheet. Budgets shown, never moved. |
| A seat | a dollar-sized slot in the 20% allowance, occupied by one keyword; numbers are stable per keyword, not per rank. |
| Occupants | REPRICE (repair), FLOOR_PROBATION (probation), LOSER (failed), TRIAL keywords bought at an entry or park bid (probe — see the probe ruling below), REVIVED_SETTLING / PENDING_SETTLE (settling — reported on the 80% side, seated on the 20% ledger). |
| Brand defense | never seated, never given a profit-based move (house rule: defense is never judged on profit). A seated keyword that becomes defense is closed `DEFENSE_EXEMPT`. The register (Task 2) shows defense keywords with a label, outside the seat count. |
| A probe | a TRIAL keyword bought at an **entry bid** — on the engine's own probe list `T_LIFT_PROBES` (a bid raised within the engine's probe window with fewer than the verdict's clicks since; the set `V_OOB_KEYWORD` calls `is_lift_probe`), seated on the engine's funding decision alone, spend or no spend — or at the **park bid** — the ladder's `at_floor` (the live bid observed at the channel floor `FN_BID_FLOOR` publishes, never a literal) with spend in the basis window. A TRIAL keyword at neither bid is WAITING (80% side) and is never seated. Both tests read published engine columns; no bid threshold is restated here. |
| Open question for Ori | a TRIAL keyword whose bid was set to the activation entry more than the engine's probe window ago (the `$1.00` on-ramp, known defect) and that has not reached the verdict's clicks reads WAITING under this rule — the engine no longer calls it a probe. If Ori rules that an expired entry is still a probe, the test gains a third arm (bid unchanged since a `VOLUME_LIFT`/activation row in the change log); until then the register shows such keywords as waiting with their bid and bid age. |

## Objects

| object | role | status |
|---|---|---|
| `DE_FAMILY_SEAT_LEDGER` | The only state the register keeps: one row per occupancy (family, campaign_id, keyword_id, opened_on) with `seat_no`, `closed_on`, `closed_reason`, `occupant_kind_at_open`. | shipped |
| `SP_MAINTAIN_FAMILY_SEATS` | Orchestrator Task 20.8b, right after `SP_SNAPSHOT_KEYWORD_STATE`. Closes, reopens, admits. Idempotent on the same snapshot. | shipped |
| `V_FAMILY_SEAT_REGISTER` | FAMILY / SEAT / LEAK / GAP / REFERENCE rows — the object Ori reads. | Task 2 |
| leak arm of `tools/build_reprice_bulksheet.py` | pause rows + ad-group-grain negates for closed-but-spending keywords. | Task 3 |
| `V_DAILY_BRIEF` SEATS section, `SeatRegister` cube | the morning surface. | Task 4 |
| `V_ENGINE_HEALTH` checks | reconciliation, idempotence, every occupant numbered. | Task 5 |

## The seat lifecycle (Task 1 — what the ledger does)

**The occupant set** is read from the latest `FACT_KEYWORD_STATE` snapshot, working families only:

| ladder state | occupant kind |
|---|---|
| `REPRICE` | repair |
| `FLOOR_PROBATION` | probation |
| `LOSER` | failed |
| `REVIVED_SETTLING`, `PENDING_SETTLE` | settling |
| `TRIAL` AND (on the engine's probe list `T_LIFT_PROBES`, OR `at_floor` with spend in the basis window) | probe |
| any state AND `is_brand_defense` | never an occupant |

The basis window is the `k_basis_days` (declared 7) complete days ending at the ads watermark − 1,
where the watermark is `LEAST(MAX(date), FN_ADS_ANCHOR_CAP())` over `FACT_AMAZON_ADS` — the same
anchor the ladder uses. Every kind except the floor-priced probe is seated on its verdict alone,
spend or no spend (a repair with no spend this week is still in repair — its seat simply costs
nothing today; an engine-listed probe with no clicks yet is still being funded). Only a TRIAL
keyword at the park bid needs spend to be seated — a floor-priced keyword buying nothing is idle,
not a probe. Spend therefore never flips a seat day to day: a probe seat closes when the engine
drops the keyword from its list or its bid leaves the floor, not when a quiet week passes.

**Probe-list freshness.** `T_LIFT_PROBES` is rebuilt by `SP_REFRESH_CUBE_TABLES` (Task 21), which
runs AFTER this procedure (20.8b) in the same orchestrator pass, so the list read is the previous
pass's. Deliberate: inlining `V_KEYWORD_LIFT` here cost tens of seconds and risks BigQuery's
planning limit, the engine's probe window is two weeks, and the register never reads a ceiling
view.

**Admission.** An occupant with no open row gets the LOWEST seat number not held by an open row of
its family. Several admissions in one run are ordered totally (kind: repair, probation, failed,
settling, probe; then spend DESC, campaign_id, keyword_id) and take the free numbers in ascending
order, so a run is deterministic and reproducible.

**Stability.** A continuing occupant is never touched. Its number is kept for as long as it stays
seated, whatever its kind becomes (repair → probation → failed is the ladder doing its job, not a
new seat). `occupant_kind_at_open` records what the seat held on admission; the CURRENT kind is the
ladder's, read live by the register.

**Closure.** An open row whose keyword is no longer an occupant is closed on the snapshot date with
one reason, first match wins:

| reason | plain reading |
|---|---|
| `KILLED` | the keyword is gone from the snapshot and its last verdict (the previous snapshot; before a second snapshot exists, the kind the seat opened with) was LOSER or DEAD — the book paused a failed keyword; or the ladder now reads `DEAD` |
| `PAUSED` | the keyword is gone from the snapshot with any other last verdict; or the ladder reads `PARKED` |
| `LEFT_FAMILY` | still tracked but under another family, or its family left the HARVEST book |
| `DEFENSE_EXEMPT` | the keyword is now brand defense — never judged on profit, never seated |
| `TO_GOOD_SIDE` | now winning or at its bar (`WINNER`, `PACED_WINNER`, `AT_BAR`) |
| `TO_WAITING` | still `TRIAL` but no longer bought at an entry or park bid — back to waiting for clicks on the 80% side, no verdict yet |

A closed number is free for the next admission. A keyword that returns later opens a NEW occupancy
and may receive a different number — stability is for the duration of a stay, not forever.

**Same-day flip.** A row closed on this snapshot date whose key is an occupant again is reopened
rather than re-inserted, so it keeps its number and the occupancy key stays unique.

**Idempotence.** Every write is keyed on the snapshot date and on set differences: a second run on
the same snapshot closes, reopens and admits nothing. Evidence is two runs with an identical
table fingerprint:

```sql
SELECT COUNT(*) n, FARM_FINGERPRINT(STRING_AGG(TO_JSON_STRING(t), '|' ORDER BY family, campaign_id, keyword_id, opened_on))
FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` t;
```

**Acceptance** (`scripts/bigquery/tests/DE_FAMILY_SEAT_LEDGER_acceptance.sql`, every row PASS):
one open row per ladder occupant; no open row without an occupant; one keyword per open number in
a family; numbers ≥ 1; no launch-family row; closed rows carry one of the six reasons; open probe
seats hold TRIAL keywords; the occupancy key is unique; no keyword holds two open rows; no
brand-defense keyword holds an open seat; every open probe seat is at an entry or park bid. The
synthetic test (run by hand at ship, never scheduled): insert two synthetic REPRICE rows into the
snapshot → they take the two lowest free numbers; remove the first → its row closes `PAUSED` (gone
from the snapshot); insert a third → it takes the number the first freed; remove everything → all
three closed; delete the synthetic ledger rows. Repair pass (2026-08-22): a synthetic brand-defense
REPRICE row was seated by the previous procedure (A10 FAIL), closed `DEFENSE_EXEMPT` by this one; a
hand-inserted probe seat on a TRIAL keyword at neither bid (A11 FAIL) closed `TO_WAITING`; a
synthetic keyword added to `T_LIFT_PROBES` with no spend was seated and, once removed from the
list, closed `TO_WAITING`; two runs after cleanup gave one fingerprint.

## What the register never does

No engine reads it. No budget is moved. No seat count is chosen — counts fall out of dollars and
the engine's seat cost. No change to the verdict ladder, the bar or the floors. Holdout campaigns
(`DE_HOLDOUT_ASSIGNMENT`, arm HOLDOUT, from `eligible_from`) may hold seats and are marked in the
register, but are excluded from every sheet the register prescribes.

## Standing Rule 0

Mechanism in prose, queries for numbers. The only constants declared here are `k_basis_days` = 7
(the spend basis) and, from the spec, `allowance_share` = 0.20 (Task 2). Today's seat counts and
costs come from the ledger and the register, never from this file.
