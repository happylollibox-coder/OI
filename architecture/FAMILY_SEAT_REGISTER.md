# FAMILY_SEAT_REGISTER — the 80/20 doctrine for working families

**Born:** 2026-08-22. **Owner request (verbatim):** "for working families (not launch in the last 3
month) make sure 80% of budget is for winning or margin keywords / the other 20% should be for
losing … number them per family so you always know what seat you are opening and what you are
probing or waiting for results." Design spec: `docs/superpowers/specs/2026-08-22-family-seat-register-design.md`
(Approach A, approved). Plan: `docs/superpowers/plans/2026-08-22-family-seat-register.md`.

**Status:** Task 1 (the ledger) SHIPPED 2026-08-22; repaired the same day (rulings R-a / R-b
encoded, ledger memory added, plain-sentence reasons). Tasks 2–5 (register view, leak generator
arm, morning surface, health checks) pending — this file grows with each.

## The doctrine in one paragraph

For the WORKING families — the HARVEST book in `V_BOOK_ASSIGNMENT`; the launches (INVEST) are
outside the doctrine entirely — 80% of spend should sit on keywords that are winning, at their bar,
or waiting for a verdict with volume. The other 20% is a dollar-sized allowance of NUMBERED SEATS,
each holding one keyword the family is knowingly paying for while it is repaired, on probation,
failed, probed, stalled in a probe, or settling. Closed-but-spending and untracked spend also count
on the 20% side: a family cannot pass by hiding spend in the cracks. The register prescribes keyword
moves executed by MANUAL bulksheet; campaign budgets are shown, never moved. No engine reads the
register.

## Rulings (from the spec, binding)

| question | ruling |
|---|---|
| Working families | HARVEST book. Launch families appear only as a labelled reference block, never judged on profit. |
| 80% side | winning + marginal (at bar) + waiting for results. |
| 20% side | losing + everything not earning or being tested: closed-but-spending, untracked. |
| The lever | keyword moves by manual bulksheet. Budgets shown, never moved. |
| A seat | a dollar-sized slot in the 20% allowance, occupied by one keyword; numbers are stable per keyword, not per rank. |
| Occupants | REPRICE (repair), FLOOR_PROBATION (probation), LOSER (failed), TRIAL keywords in a probe position (probe / stalled probe — see the two probe rulings below), REVIVED_SETTLING / PENDING_SETTLE (settling — reported on the 80% side, seated on the 20% ledger). |
| Brand defense | never seated, never given a profit-based move (house rule: defense is never judged on profit). A seated keyword that becomes defense is closed `DEFENSE_EXEMPT`. The register (Task 2) shows defense keywords with a label, outside the seat count. |
| **R-a — a probe** (2026-08-22) | A TRIAL keyword on the engine's own probe list `T_LIFT_PROBES` (a bid raised within the engine's probe window with fewer than the verdict's clicks since; the set `V_OOB_KEYWORD` calls `is_lift_probe`) is a seat **whether or not it spent this week** — it costs $0 today and still answers "what am I probing". A TRIAL keyword at the **park bid** — the ladder's `at_floor` (the live bid observed at the channel floor `FN_BID_FLOOR` publishes, never a literal) — that the engine does NOT list is a seat **only with spend** in the basis window: a floor-priced keyword buying nothing is idle, not a probe. |
| **R-b — a stalled probe** (2026-08-22) | A TRIAL keyword parked at an activation entry bid — still holding the raised bid of its latest applied `INCREASE_BID` in `V_PPC_CHANGE_LOG_APPLIED` — past the engine's probe window (`k_probe_window_days`) with fewer than the verdict's clicks (`k_verdict_clicks`) since, no longer engine-listed and not at the floor, is a **STALLED PROBE**: a seat on the 20% side with a standing proposal (re-price to the seat price, or park), NOT "waiting for results" on the 80% side. A test that cannot produce a verdict at its pace is not a test. The set is read from the data on every run (the change log × the snapshot), never from a list. |
| Waiting | A TRIAL keyword in none of the three probe positions (engine-listed; at the floor with spend; stalled) is WAITING on the 80% side and is never seated. |

## Objects

| object | role | status |
|---|---|---|
| `DE_FAMILY_SEAT_LEDGER` | The only state the register keeps: one row per occupancy (family, campaign_id, keyword_id, opened_on) with `seat_no`, `closed_on`, `closed_reason`, `closed_reason_text`, `occupant_kind_at_open`, `last_observed_kind`, `last_observed_state`. | shipped |
| `SP_MAINTAIN_FAMILY_SEATS` | Orchestrator Task 20.8b, right after `SP_SNAPSHOT_KEYWORD_STATE`. Closes, reopens, admits, observes. Idempotent on the same snapshot. | shipped |
| `V_FAMILY_SEAT_REGISTER` | FAMILY / SEAT / LEAK / GAP / REFERENCE rows — the object Ori reads. | Task 2 |
| leak arm of `tools/build_reprice_bulksheet.py` | pause rows + ad-group-grain negates for closed-but-spending keywords. | Task 3 |
| `V_DAILY_BRIEF` SEATS section, `SeatRegister` cube | the morning surface. | Task 4 |
| `V_ENGINE_HEALTH` checks | reconciliation, idempotence, every occupant numbered. | Task 5 |

## The seat lifecycle (Task 1 — what the ledger does)

**The occupant set** is read from `FACT_KEYWORD_STATE` — which holds exactly ONE snapshot, see
"Memory" below — working families only:

| ladder state | occupant kind |
|---|---|
| `REPRICE` | repair |
| `FLOOR_PROBATION` | probation |
| `LOSER` | failed |
| `REVIVED_SETTLING`, `PENDING_SETTLE` | settling |
| `TRIAL` AND (on the engine's probe list `T_LIFT_PROBES`, spend or not — OR `at_floor` with spend in the basis window) | probe (R-a) |
| `TRIAL` AND not engine-listed AND not `at_floor` AND the latest applied bid change is an `INCREASE_BID` whose `new_bid` is still the current bid, dated on or before today − `k_probe_window_days`, with fewer than `k_verdict_clicks` clicks since | stalled probe (R-b) |
| any state AND `is_brand_defense` | never an occupant |

The basis window is the `k_basis_days` (declared 7) complete days ending at the ads watermark − 1,
where the watermark is `LEAST(MAX(date), FN_ADS_ANCHOR_CAP())` over `FACT_AMAZON_ADS` — the same
anchor the ladder uses. `k_probe_window_days` (declared 14) and `k_verdict_clicks` (declared 20)
mirror the engine's own probing test in `V_KEYWORD_LIFT` (raised within 14 days, under 20 episode
clicks) — a stalled probe is that test expired; if the engine changes them, change them here.
Every kind except the floor-priced probe is seated on its verdict alone, spend or no spend (a
repair with no spend this week is still in repair — its seat simply costs nothing today; an
engine-listed probe with no clicks yet is still being funded; a stalled probe with no clicks is
exactly the problem). Only a TRIAL keyword at the park bid needs spend to be seated. Spend
therefore never flips a seat day to day: a probe seat closes when the engine drops the keyword
from its list or its bid leaves the floor, not when a quiet week passes.

**Probe-list freshness.** `T_LIFT_PROBES` is rebuilt by `SP_REFRESH_CUBE_TABLES` (Task 21), which
runs AFTER this procedure (20.8b) in the same orchestrator pass, so the list read is the previous
pass's. Deliberate: inlining `V_KEYWORD_LIFT` here cost tens of seconds and risks BigQuery's
planning limit, the engine's probe window is two weeks, and the register never reads a ceiling
view.

**Admission.** An occupant with no open row gets the LOWEST seat number not held by an open row of
its family. Several admissions in one run are ordered totally (kind: repair, probation, failed,
settling, probe, stalled probe; then spend DESC, campaign_id, keyword_id) and take the free numbers
in ascending order, so a run is deterministic and reproducible.

**Stability.** A continuing occupant's number is never touched. It is kept for as long as the
keyword stays seated, whatever its kind becomes (repair → probation → failed is the ladder doing
its job, not a new seat). `occupant_kind_at_open` records what the seat held on admission;
`last_observed_kind` is what it held on the latest run; the CURRENT kind is the ladder's, read
live by the register.

**Memory.** `FACT_KEYWORD_STATE` is `CREATE OR REPLACE`'d by `SP_SNAPSHOT_KEYWORD_STATE` on every
run and holds exactly one snapshot, so "what did this keyword read yesterday" cannot be asked of
it. The ledger is the only memory: on every run each OPEN row is stamped with
`last_observed_kind` / `last_observed_state` from today's occupant set (re-stamping the same
snapshot writes the same values). When a keyword vanishes from the snapshot, KILLED vs PAUSED is
decided from `last_observed_state`; a row opened before the memory columns existed (NULL) falls
back to the kind it opened with.

**Closure.** An open row whose keyword is no longer an occupant is closed on the snapshot date with
one reason code and the same reason as one plain sentence (`closed_reason_text`), first match
wins. The sentences below are the ones written to the ledger, asserted by the acceptance test, and
to be shown wherever a person reads the code:

| code | the sentence a person reads |
|---|---|
| `KILLED` | The keyword is gone from the snapshot after its last verdict was failed or dead, or the ladder now reads dead: the book paused a failed keyword. The seat is free. |
| `PAUSED` | The keyword is gone from the snapshot, or the ladder now reads parked, without a failed verdict first. The seat is free. |
| `LEFT_FAMILY` | The keyword is still tracked but now belongs to another family, or its family left the working (HARVEST) book. The seat is free. |
| `DEFENSE_EXEMPT` | The keyword is now brand defense. Defense is never judged on profit, so it is never seated. The seat is free. |
| `TO_GOOD_SIDE` | The keyword is now winning or at its bar: it moved to the 80% side. The seat is free. |
| `TO_WAITING` | The keyword is still a trial but is no longer bought at an entry or park bid and is not a stalled probe: it is back to waiting for clicks on the 80% side, no verdict yet. The seat is free. |

Occupant kinds, for the same reason: repair = "losing, being re-priced toward its bar";
probation = "losing, held at its floor to be seen serving"; failed = "lost at its floor";
probe = "a trial being bought at an entry or park bid"; stalled probe = "a trial parked at an
entry bid past the probe window without enough clicks for a verdict — re-price to the seat price
or park"; settling = "a verdict is pending until its clicks settle".

A closed number is free for the next admission. A keyword that returns later opens a NEW occupancy
and may receive a different number — stability is for the duration of a stay, not forever.

**Same-day flip.** A row closed on this snapshot date whose key is an occupant again is reopened
rather than re-inserted, so it keeps its number and the occupancy key stays unique.

**Idempotence.** Every write is keyed on the snapshot date and on set differences: a second run on
the same snapshot closes, reopens and admits nothing and re-stamps identical memory. Evidence is
two runs with an identical table fingerprint:

```sql
SELECT COUNT(*) n, FARM_FINGERPRINT(STRING_AGG(TO_JSON_STRING(t), '|' ORDER BY family, campaign_id, keyword_id, opened_on))
FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` t;
```

**Acceptance** (`scripts/bigquery/tests/DE_FAMILY_SEAT_LEDGER_acceptance.sql`, every row PASS, 15
checks): one open row per ladder occupant; no open row without an occupant; one keyword per open
number in a family; numbers ≥ 1; no launch-family row; closed rows carry one of the six reasons;
open probe / stalled-probe seats hold TRIAL keywords; the occupancy key is unique; no keyword
holds two open rows; no brand-defense keyword holds an open seat; R-a both ways (every open TRIAL
seat is engine-listed, or at the floor WITH spend, or stalled — and every engine-listed TRIAL,
spend or not, and every at-floor TRIAL with spend, holds one open row); R-b (every stalled probe
holds one open row observed as 'stalled probe'); every open row remembers its last observed kind
and state and the state matches the ladder today; every closed row carries the sentence mapped to
its code. TDD record 2026-08-22: with the memory columns added but the old procedure live, A13
(stalled probes unseated) and A14 (no memory) FAILED; after the new procedure, 15/15 PASS.

**Synthetic tests** are run by hand on `TMP_` copies, never on the live snapshot or ledger (house
rule: no synthetic rows in a production table consumers read). Ship record: a `TMP_` copy of the
procedure pointed at `TMP_` copies of the snapshot and the ledger; three seated keywords deleted
from the snapshot copy — one with memory `LOSER` closed `KILLED`, one with memory `REPRICE` closed
`PAUSED`, one with no memory and opened as failed closed `KILLED` — each with its sentence; the
`TMP_` objects dropped afterwards. Earlier records (first ship): two synthetic REPRICE rows took
the two lowest free numbers; the first removed closed `PAUSED`; a third took the freed number;
a synthetic brand-defense REPRICE row closed `DEFENSE_EXEMPT`; a probe seat at neither bid closed
`TO_WAITING`; a keyword added to the probe list with no spend was seated and, once removed,
closed `TO_WAITING`.

**Seat census** — how many seats each family holds, by kind, and what they cost per day on the
basis window — is a measurement; read it from the ledger, never from this file:

```sql
WITH wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) d FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
sp AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid, SUM(Ads_cost) sp7
       FROM `onyga-482313.OI.FACT_AMAZON_ADS` f CROSS JOIN wm
       WHERE f.date BETWEEN DATE_SUB(wm.d, INTERVAL 7 DAY) AND DATE_SUB(wm.d, INTERVAL 1 DAY) GROUP BY 1, 2)
SELECT l.family, l.last_observed_kind, COUNT(*) seats, ROUND(SUM(COALESCE(sp.sp7, 0)) / 7, 2) cost_per_day
FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` l
LEFT JOIN sp ON sp.cid = l.campaign_id AND sp.kid = l.keyword_id
WHERE l.closed_on IS NULL GROUP BY 1, 2 ORDER BY 1, 2;
```

## What the register never does

No engine reads it. No budget is moved. No seat count is chosen — counts fall out of dollars and
the engine's seat cost. No change to the verdict ladder, the bar or the floors. Holdout campaigns
(`DE_HOLDOUT_ASSIGNMENT`, arm HOLDOUT, from `eligible_from`) may hold seats and are marked in the
register, but are excluded from every sheet the register prescribes.

## Standing Rule 0

Mechanism in prose, queries for numbers. The only constants declared here are `k_basis_days` = 7
(the spend basis), `k_probe_window_days` = 14 and `k_verdict_clicks` = 20 (the engine's probing
test, mirrored for the stalled-probe position) and, from the spec, `allowance_share` = 0.20
(Task 2). Today's seat counts and costs come from the ledger and the register, never from this
file.
