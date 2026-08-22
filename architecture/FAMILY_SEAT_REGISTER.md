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
| Occupants | REPRICE (repair), FLOOR_PROBATION (probation), LOSER (failed), engine-listed probes in TRIAL with spend (probe), REVIVED_SETTLING / PENDING_SETTLE (settling — reported on the 80% side, seated on the 20% ledger). |

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
| `TRIAL` AND the engine lists the keyword as a probe (`V_KEYWORD_LIFT` probing / PROBE_START — the set `V_OOB_KEYWORD` reads as `is_lift_probe`) AND it spent in the basis window | probe |

The basis window is the `k_basis_days` (declared 7) complete days ending at the ads watermark − 1,
where the watermark is `LEAST(MAX(date), FN_ADS_ANCHOR_CAP())` over `FACT_AMAZON_ADS` — the same
anchor the ladder uses. A probe that stops spending leaves the occupant set; the other kinds are
seated on their verdict alone, spend or no spend (a repair with no spend this week is still in
repair — its seat simply costs nothing today).

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

| reason | when |
|---|---|
| `LEFT_FAMILY` | the keyword is still tracked but under another family, or its family left the HARVEST book |
| `KILLED` | the ladder reads `DEAD`; or a seat that held a FAILED keyword finds it gone from the snapshot (the book paused it) |
| `PAUSED` | the ladder reads `PARKED`; or the keyword is gone from the snapshot |
| `TO_GOOD_SIDE` | still tracked in the family — winning, at its bar, or waiting with volume (the 80% side) |

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
a family; numbers ≥ 1; no launch-family row; closed rows carry one of the four reasons; open probe
seats hold TRIAL keywords; the occupancy key is unique; no keyword holds two open rows. The
synthetic test (run by hand at ship, never scheduled): insert two synthetic REPRICE rows into the
snapshot → they take the two lowest free numbers; remove the first → its row closes `PAUSED` (gone
from the snapshot); insert a third → it takes the number the first freed; remove everything → all
three closed; delete the synthetic ledger rows.

## What the register never does

No engine reads it. No budget is moved. No seat count is chosen — counts fall out of dollars and
the engine's seat cost. No change to the verdict ladder, the bar or the floors. Holdout campaigns
(`DE_HOLDOUT_ASSIGNMENT`, arm HOLDOUT, from `eligible_from`) may hold seats and are marked in the
register, but are excluded from every sheet the register prescribes.

## Standing Rule 0

Mechanism in prose, queries for numbers. The only constants declared here are `k_basis_days` = 7
(the spend basis) and, from the spec, `allowance_share` = 0.20 (Task 2). Today's seat counts and
costs come from the ledger and the register, never from this file.
