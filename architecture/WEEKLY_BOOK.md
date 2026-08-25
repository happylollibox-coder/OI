# THE WEEKLY BOOK — one book, every action, each row explained top-down

**Status:** design agreed with Ori 2026-08-25. Derives from `architecture/THREE_LAYERS.md`, which wins
on conflict. Ori's words: *"you can create bulksheet that support the 3 tiers and can explain each action."*

## 1. What this is, and what it replaces

Today the account produces **nine separate bulksheets** from nine commands
(`build_reprice_bulksheet.py`, `build_seat_moves_bulksheet.py`, `build_seasonal_unpause_bulksheet.py`,
and six smaller ones). Each is correct on its own and each writes its own README, its own change-log
batch and its own file. Three consequences, all of them Ori's to live with:

- **No single thing to review.** Deciding what happens to one keyword means reading three READMEs and
  knowing which book won.
- **No conflict detection.** Nothing stops the reprice book raising a bid on a keyword the seat book is
  parking, because neither knows the other ran. It has never been checked.
- **The explanation is flat.** `story()` in the reprice builder writes an excellent plain sentence in the
  shape *TRIGGER — EVIDENCE => MOVE*, but it does not say **which layer decided what**, which is exactly
  what §9 requires and what makes a disagreement arguable.

The weekly book is an **assembler**. It changes none of the nine builders: it imports their row builders
and their evidence, merges the result into one workbook, resolves conflicts under a declared precedence,
and writes one change-log batch. Every existing command keeps working exactly as it does today.

## 2. The three tiers, and which actions belong to each

An action's tier is decided by **which question it answers**, never by which table it touches.

| tier | the question it answers | actions it emits | source module |
|---|---|---|---|
| **CATALOG** | *is this worth having at all?* | negate a term, un-negate a term, park a subject at its floor, un-park it, enable/pause a seasonal subject | `build_seat_moves_bulksheet` (negatives), `build_seasonal_unpause_bulksheet` (enable + park) |
| **BRAIN** | *what does it get funded to do?* | campaign budget up/down, seat moves between subjects, fund a `TEST` | `FACT_PLAN_NEXT_WEEK` (budgets), `build_seat_moves_bulksheet` (seats) |
| **PACING** | *what is today's bid?* | raise bid, lower bid, hold at floor | `build_reprice_bulksheet` |

A row carries **exactly one tier**. If it seems to belong to two, it has been described wrong — go back
to the question it answers.

**Corrected during the build (2026-08-25).** This table first put *"pause a keyword Amazon-side"* under
PACING, and that was wrong. A keyword pause at the end of probation is *executed* by Pacing but
**decided** by the ladder's `DEAD`/`LOSER` verdict — the question it answers is *is this worth having*,
which is the Catalog's. Filing it under Pacing would have put a worth verdict in the one layer §1.1
forbids to make one. **The tier is the tier that DECIDED, never the one that executes**, and the code
now derives it from what the row does (`action_kind`) rather than from which module built it — which is
also what stopped two tiers printing the same sentence.

## 3. Precedence — what happens when two tiers touch one subject

**The higher tier wins, and the lower tier's row is dropped rather than blended.** Catalog > Brain > Pacing.

The reasoning is §1.1's, not convenience. A tier that says *this is not worth having* has answered a
question the tier below it never asked: pricing a blocked term is meaningless, and funding a parked one
is worse than doing nothing. So:

- **Catalog beats Brain.** A term being negated is not given a seat this week.
- **Catalog beats Pacing.** A subject being parked or negated is not repriced.
- **Brain beats Pacing.** A subject the Brain is defunding is not given a new bid; a subject it is
  funding gets its bid from Pacing, which is agreement, not conflict.

**A dropped row is never silent.** Every conflict is written to the `Conflicts` sheet with both actions,
both tiers and both explanations, so the drop is reviewable. A conflict that appears every week is a
design fault, not a rounding error — the whole point of surfacing it is to make that visible.

**What precedence does NOT do:** it does not decide whether the higher tier was *right*. That is §6's
scorecard question, and this book only reports.

## 4. The explanation — three sentences, in decision order

Every executable row carries three sentences, always in this order and never abbreviated:

1. **CATALOG —** what the subject is worth and on what evidence: the settled record, the family bar,
   which side of the bar and by how much, the floor and its source, and any season or guard note.
2. **BRAIN —** what was decided about money: funded or not, from which pot, at what allowance, which
   seat, or the reason it was held (rule B on the good side, holdout arm, no seat available).
3. **PACING —** what will actually happen on Amazon: the old bid, the new bid, the cap that bound it,
   the floor that stopped it, and whether an engine instruction yielded to the book or the reverse.

The content is **not invented for this book** — it is the same evidence `story()` and `readme_row()`
already carry, re-routed into the tier that produced it. Where a tier genuinely has nothing to say about
a row, it says so in one clause rather than being omitted; a missing sentence reads as an oversight and
an explicit *"the Catalog has no verdict for this subject"* reads as the fact it is.

## 5. The workbook

| sheet | contents |
|---|---|
| `Sponsored Products Campaigns` | Amazon's SP bulksheet rows, headers exactly as `SP_HEADERS` |
| `SB Multi Ad Group Campaigns` | Amazon's SB rows, headers exactly as `SB_HEADERS` |
| `Explained` | one row per executable action: tier, campaign, subject, action, old → new, and the three sentences in three columns |
| `Conflicts` | every row dropped by precedence, with the winner, the loser and both explanations |
| `Refused` | rows a source built and then refused to execute (season-blocked, holdout, engine-instructed), with the reason — money NOT moved, kept visible so a refusal is a decision and not an absence |

Only the two Amazon sheets are uploaded. The other three exist to be read.

## 6. The change log

**One batch id for the whole book**, prefix `weekly`. Every row logged `PENDING_UPLOAD` at build time and
flipped by `--mark-uploaded`, exactly as the existing books do — nothing about that discipline changes,
including that a row is **never deleted**, only labelled. The `action` vocabulary gains the campaign-grain
and Catalog-grain verbs the single-purpose books already use, so no new action string is invented here.

Because one book now carries rows from several sources, the log's `source` column records the **source
module** and a new note records the **tier**, so a later reader can ask "what did the Brain do in August"
without re-deriving it from the action verb.

## 6.2 The budget move cap — and the trap inside it (plan step 3)

Campaign budgets are a **new action type for a book**: no generator in this account has ever emitted
one. `--budget-max-move` (default **0.25**) holds any move beyond ±25% on the `Refused` sheet, carrying
its actual percentage so it can be judged rather than merely noticed. **Held, never dropped** — a budget
change that vanishes without a word is indistinguishable from one the plan never proposed. The cap is
**symmetric**: a 40% cut is exactly as unreviewed as a 40% raise. A move from a zero budget is refused
rather than let through, because no percentage exists to measure it against.

**THE CAP CAN REVERSE THE BOOK'S DIRECTION, and that is not a smaller version of the plan.** Measured on
the first live run: the plan's 44 rows move budgets **+$135.62/day**, but the 21 that survive a ±25% cap
move them **−$85.77/day**. The moves beyond the cap are overwhelmingly *raises* (23 held, +$221.39/day),
so holding them leaves their opposites standing alone and a book meant to be *conservative* becomes a
book that **cuts spend**.

The README and stdout both say so explicitly whenever the two directions disagree in sign. A reader must
not discover this after uploading — being cautious about *size* while silently inverting *direction* is
a worse failure than shipping the big movers would have been.

## 6.1 Budget carry — a warning, not a refusal (violation 28)

A campaign budget row and a bid row inside that campaign are **not** a precedence conflict — §3 pins
that, and a test asserts it. But a budget being **cut** while bids inside it are **raised** is a request
the campaign may not be able to carry, and before this check the two rows sat twenty-five lines apart in
the same book with nothing relating them.

`budget_carry_check()` flags exactly that shape: a `BUDGET_DOWN` row with one or more executable
`BID_UP` rows in the same campaign. Not a cut with cuts inside (coherent), not a raise with raises inside
(the two layers agreeing, which is the doctrine working). Warnings land on the `Conflicts` sheet below
the precedence conflicts, in the README, and on stdout.

**It warns and never refuses**, and never drops a row. Trimming a campaign's ceiling while concentrating
it on its better keywords is a legitimate rebalance; refusing would make that undeliverable. What is not
acceptable is it being invisible.

**Measured on the first live run: ten campaigns, twelve raised bids** — the largest a 29% cut
(`$160.00 → $113.51/day`) with two raises inside it. The single pair found by hand beforehand was not
among them, and that is the check behaving correctly rather than missing: `BOX-SP/EXACT` is still a cut
(`$20.48 → $14.68`), but rule B has since vetoed the raise inside it, so there is no executable raise to
carry. A cut with no raise inside is not a carry problem.

## 7. Preflight — refusals, not warnings

Before a single cell is written the assembled rows are checked, and any violation **refuses the whole
build**. Not a warning: a warning printed above a hundred lines of output at 2am is a warning nobody
reads. Each check exists because this account has actually been bitten by it.

| check | why |
|---|---|
| `Product` / `Entity` / `Operation` present on every row | Amazon rejects the line, and a rejected line inside an accepted book is the hardest failure to notice |
| **no blank portfolio on a `Campaign` row** unless the campaign never had one | **blank is not "unchanged" — it DETACHES.** Caught 3 of the first 42 budget rows carrying a blank, because `DIM_CAMPAIGN.portfolio_id` is NULL for a campaign detached *right now*, so echoing it makes a temporary detachment permanent. The echo is the last non-null portfolio the campaign has ever carried, read from campaign history |
| SB `Campaign Name` always blank | it is a **real** column on the SB sheet — filling it renames the campaign to whatever the warehouse held at build time |
| a bid move carries a non-empty `Bid` | a bid row with no bid is a silent no-op that still consumes a change-log row, so the log claims a change that never happened |

## 8. What v1 does not do

Stated so nobody reads more into it than is there:

- It does **not** decide anything. Every decision in it was already made by a source module tonight.
- It does **not** implement §5's confidence gate, because `confidence` is still not computed (violation 20).
- It does **not** re-open campaigns. Campaign state is Ori's by hand this season — see
  `.tmp/REOPEN_CAMPAIGNS_20260825.md` and §4.1.
- It does **not** upload. Ori uploads, always.
