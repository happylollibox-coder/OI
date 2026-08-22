# Family Seat Register — the 80/20 doctrine for working families

**Date:** 2026-08-22 · **Owner:** Ori · **Status:** approved in conversation (Approach A)

## 1. What Ori asked for, verbatim

> "show me per family all the categories the keywords are in (winning, probe,...) / the main goal is
> for working families (not launch in the last 3 month) make sure 80% of budget is for winning or
> margin keywords / the other 20% should be for losing / the waiting for results split to categories
> as well for budget purpose / meaning waiting for results and winning or marginal should be part of
> the 80% / plan what to do"

> "regarding the losing keywords for the 20% you should number them per family so you always know
> what seat you are opening and what you are probing or waiting for results"

## 2. Rulings made during design

| question | ruling |
|---|---|
| Working families | The **HARVEST** book (`V_BOOK_ASSIGNMENT`). Launch families (INVEST: Bunny, LolliBall) are outside the doctrine entirely and appear only as a reference block. |
| What sits on the **80% side** | winning + marginal + waiting-for-results (keywords with a verdict pending). |
| What sits on the **20% side** | losing **plus everything that is not earning or being tested**: closed-but-still-spending (parked/dead keywords with spend) and untracked spend (no verdict row). A family cannot pass by hiding spend in the cracks. |
| The lever | **Keyword-level moves, executed by manual bulksheet** (Approach A). Campaign budgets are *shown* (a capped, above-bar campaign that could absorb freed spend) but never moved by this design. |
| What a **seat** is | A dollar-sized slot inside the family's 20% allowance, occupied by one keyword the family is knowingly paying for while it is **repaired, tested, or judged**. Seat numbers are stable per keyword, not per rank. |
| Seat occupants | losers in repair (`REPRICE`), losers on probation (`FLOOR_PROBATION`), failed (`LOSER`), probes (trial keywords being bought at an entry bid), verdicts pending (`REVIVED_SETTLING`, `PENDING_SETTLE`). Waiting-with-volume keywords stay on the 80% side. |

## 3. Vocabulary — plain words, mapped to the deployed ladder

The keyword verdict ladder (`SP_SNAPSHOT_KEYWORD_STATE` v27.104+, `FACT_KEYWORD_STATE`) already
judges every keyword against its **family bar** (the family's measured break-even after the organic
halo, from `T_FAMILY_BAR`). The register only *groups* those verdicts:

| category (what Ori reads) | ladder states | side |
|---|---|---|
| winning | `WINNER`, `PACED_WINNER` | 80 |
| marginal — at its bar | `AT_BAR` | 80 |
| waiting — too few clicks yet | `TRIAL` with clicks above zero but under the volume floor, **not** at an entry/park bid | 80 |
| waiting — verdict settling | `REVIVED_SETTLING`, `PENDING_SETTLE` | 80 |
| losing — in repair | `REPRICE` | 20 · seat |
| losing — on probation at its floor | `FLOOR_PROBATION` | 20 · seat |
| losing — failed at its floor | `LOSER` | 20 · seat |
| probe — being bought at an entry bid | `TRIAL` that the engine itself lists as a probe (its lift-probe set), **whether or not it spent this week** — a reserved probe seat costs $0 today and still answers "what am I probing"; plus any `TRIAL` at its channel floor / park bid **with spend** | 20 · seat |
| probe — stalled | `TRIAL` sitting at an activation entry bid past the engine's probe window (14 days) with fewer than the verdict's 20 clicks, no longer listed by the engine — a test that cannot produce a verdict at its pace is **not** "waiting for results"; it is a seat with a standing proposal: re-price to the seat price or park | 20 · seat |
| closed but still spending | `PARKED`, `DEAD` with spend in the window | 20 · leak |
| untracked | spending keyword with no `FACT_KEYWORD_STATE` row | 20 · gap |
| launch | `LAUNCH_CONTAINED` (INVEST families) | outside |

"Waiting — verdict settling" keywords are also **seat occupants** (ruling: anything not yet earning
occupies a seat) but are reported on the 80% side per Ori's explicit ruling. The register shows both
facts; the doctrine ratio uses the side column.

## 4. The register — one object, two grains

`V_FAMILY_SEAT_REGISTER` publishes, for each working family:

**FAMILY rows** — the doctrine read.
- `spend_basis_per_day`: the family's spend over the **7 complete days** ending at the ads
  watermark − 1 (the window Ori validated the design on). A 28-day figure is published beside it as
  context; the doctrine is judged on the 7-day read.
- `good_side_per_day`, `bad_side_per_day`, `good_share`, and `doctrine_status`
  (`IN` ≥ 80 %, `AT_LINE` within a declared band of the line, `OUT`).
- `allowance_per_day` = `k.allowance_share × spend_basis_per_day` with `k.allowance_share = 0.20`
  (declared constant).
- `seats_occupied_cost`, `open_capacity` = allowance − occupied cost (may be negative).
- `over_by_per_day` when OUT: the dollars the bad side exceeds the allowance by.
- Three horizons per family: **today**, **day one** (the current book's capped moves land, closed
  leaks paused), **re-judged** (repriced occupants either hold at their bar and become marginal, or
  fail and are killed). The horizons are projections and are labelled as such.
- A plain sentence: what the family's seats hold, what is open, what closes the gap.

**SEAT rows** — one per occupant, numbered.
- `seat_no`: **stable per keyword** — assigned on first appearance and carried forward in
  `DE_FAMILY_SEAT_LEDGER` (a small table the register maintains: `family, campaign_id, keyword_id,
  seat_no, opened_on, closed_on, closed_reason`). Freed numbers are reused by the next admission so
  the register reads "seat 4 (open)".
- `occupant_kind` (repair / probation / failed / probe / settling), the keyword, campaign, current
  bid, the move on the current book if any, `cost_per_day`, `due_on` (the ladder's
  `next_check_date`), and a plain sentence.
- Open seats are listed with the **next candidate from the probe queue** (`V_OOB_KEYWORD` queue
  rank) that the open capacity can afford.

**LEAK and GAP rows** — closed-but-spending and untracked keywords, one per keyword, each with the
one move that resolves it (pause / negate the term / map the family) so nothing on the 20% side is
unexplained.

**REFERENCE rows** — the two launch families, same categories, no doctrine read, labelled.

## 5. Seat economics

- A seat's cost is **what the occupant actually spends per day** (7-day basis). Repairs are big
  seats, probes are small ones; the allowance is denominated in dollars so the two are honest.
- A probe's admission cost is the engine's own seat economics: `seat_cpc × daily click goal` from
  `V_OOB_KEYWORD` (budget ÷ slots ÷ 4-click goal — read the view, never restate the number), over the
  days a 20-click verdict takes at the keyword's click pace.
- Admission rule: a probe enters only when `open_capacity ≥ its admission cost`. The register
  **proposes** admissions (the queue already exists in the engine); it never bids.
- A seat **closes** when its occupant becomes winning/marginal (moves to the 80% side), is killed
  (`LOSER` after probation), or is paused. The ledger records `closed_reason`.

## 6. What the register makes Ori do — the daily moves

The register prescribes; Ori executes by bulksheet (the house pattern: generator → audit CSV →
README → restore sheet → batch logged `PENDING_UPLOAD` → `--mark-uploaded`).

1. **Repairs** — already produced by `tools/build_reprice_bulksheet.py`; the register links each
   seat to its row and its per-upload step (three engine steps: +15.76 % / −14.26 %).
2. **Leaks** — closed-but-spending keywords: a pause row, or a search-term negate where the leak is
   a term under a parked keyword. New generator arm, same conventions, **acting-grain rule applies**
   (a negate is judged at the ad group).
3. **Gaps** — untracked keywords: no bulksheet row; a mapping prompt (the family-name fallback now
   resolves campaigns, but keywords in newly mapped campaigns get a verdict only on the next state
   run — the register says "verdict arrives tomorrow" rather than prescribing).
4. **Admissions** — open capacity and the next probe candidate, as a proposal.
5. **Absorption (advisory only)** — a capped, above-bar campaign in the family that could take freed
   spend. Shown with its cap days; never moved.

## 7. Non-goals

- No engine reads the register. No budget is moved. No seat count is chosen — all counts fall out of
  dollars and the engine's seat cost.
- No change to the verdict ladder, the bar, or the floors.
- The holdout arm (from 2026-09-01) is respected by every generator: holdout campaigns appear in the
  register with a `HOLDOUT — do not touch` marker and are excluded from every sheet.

## 8. Guarantees and how they are asserted

- **Reconciliation:** FAMILY-row categories sum to the family's spend basis to the cent; SEAT + LEAK +
  GAP costs sum to `bad_side_per_day`. Asserted at deploy and in `V_ENGINE_HEALTH`.
- **Exactly one side per keyword**, exactly one seat number per occupant, no launch family in a
  FAMILY row, no brand-defense keyword with a profit-based move.
- **Seat stability:** a keyword that stays an occupant keeps its number across days (ledger test).
- **Determinism:** two uncached pulls, sorted, identical.
- **Planner:** the register reads `FACT_KEYWORD_STATE`, `T_FAMILY_BAR`, `FACT_AMAZON_ADS`; it does
  not inline any ceiling view. Dry-run before/after.
- **Standing Rule 0:** no measured figure in any header or registry entry; the projection horizons
  carry their as-of date on the row.

## 9. Acceptance (what Ori sees)

A morning read per working family, in plain words, e.g. the shape (figures illustrative, measured
2026-08-22):

```
LOLLIBOX — 56 % good · OUT by $53/day
  allowance $86/day · seats cost $139 · open −$53
  seat 1  tween girl gifts        repair   $81/day  $0.70→$0.61 on the book  re-judge Sep 5
  seat 2  girls gifts age 8-10    repair   $53/day  $0.52→$0.45 on the book  re-judge Sep 5
  leak    3 parked keywords still spending $9/day → pause rows on the book
  gap     3 video targets with no verdict  $40/day → verdict arrives on the next state run
  could absorb freed spend: BOX-SP/BROAD (Hunter) — above bar, capped 6 of 7 days
  re-judged horizon: ~90 % if the repairs hold at their bar
```

Lollibox passes the doctrine only at the re-judged horizon; that is the design working, not a gap.
