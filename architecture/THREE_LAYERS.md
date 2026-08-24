# The Three Layers — the doctrine every ads decision starts from

**Status:** agreed with Ori 2026-08-24. **This is the top document.** Any change to how a bid, a
budget, a pause or a probe is decided starts here and derives downward. If a design cannot be
expressed in these three layers and their contracts, the design is wrong, not the doctrine.

Supersedes the "one engine" wording of P-11 in
`docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md`. Downstream documents
(`FAMILY_SEAT_REGISTER.md`, `KEYWORD_STATE.md`, `ENGINE_PREFLIGHT.md`, `OOB_BUDGET_PHASE.md`) describe
*mechanisms*; this one describes *who is allowed to decide what*, and it wins on conflict.

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
| `confidence` | how much settled evidence stands behind the verdict | act on it, or buy more evidence |
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

---

## 3. The Brain → Pacing contract

The Brain issues an intent, a constraint, and — when it is buying an answer — a budget and a deadline.

| the Brain issues | meaning | Pacing's obligation |
|---|---|---|
| `REPAIR · ceiling C` | worth is known; do not pay above C | move to the ceiling; **never exceed it** |
| `TEST · seat $X/day · N clicks by date D` | worth is unknown and we are buying the answer | push for clicks within the budget; report back if unbuyable |
| `PARK` | not worth **now**; keep it alive | hold at the channel floor |
| `STOP` | not worth in any season | execute the pause |
| `EARN` | it is working; do not disturb | small daily maintenance only |

**Two groups, and no third.** Every keyword is either **answered** (the Brain acts) or has an **open
question** (the Brain funds it and demands a verdict). *"Nothing to do"* is not a legal state — it is
how keywords sit in limbo, spending or dormant, owned by no one.

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

---

## 5. Irreversibility

**Only the Brain may take an irreversible action, and only on `NOT_WORTH` with HIGH confidence.**

Pacing, the books and the generators execute; they never originate a kill. A pause removes a keyword
from `FACT_KEYWORD_STATE` entirely — after that no layer can see it, judge it or revive it. That is a
door that only closes, and a silent window is not evidence that it should.

**A silent window is never evidence of worthlessness.** A keyword that takes no clicks may be dormant,
seasonal, or simply bid too low to win an auction — three very different things that look identical
to a window-based judge.

---

## 6. How each layer improves — two scorecards, not one

The layers are graded separately, on different questions:

- **Catalog scorecard — valuation.** The Catalog makes predictions, so it is graded against outcomes
  without reference to the Brain: *"In October you said this was worth 4.6x in December. Was it?"*
  This is how the Catalog improves its estimator (trailing → seasonal → same-period-last-year →
  whatever wins) and proves the improvement, while no other layer changes by a line.
- **Brain scorecard — allocation.** Given the Catalog's answers, did the money go to the right places?
  This is the A-vs-B shadow-plan comparison at T+14.

A layer that cannot be graded on its own question cannot improve independently, which is the whole
point of the narrow interface.

---

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

---

## 8. Known violations in the system as built (2026-08-24)

Recorded honestly so the gap is visible; each is a defect against this doctrine, not a design choice.

1. **The Catalog emits commands.** `FACT_KEYWORD_STATE` publishes `WINNER` / `DEAD` / `REPRICE`, which
   flow into books as actions.
2. **The Catalog is not seasonal.** `settled_*90` is a trailing settled window with no seasonal
   resolution, though two full Decembers of ads data exist.
3. **The Catalog has no marginal model.** `affordable_cpc = gp_per_click / bar` is an average.
   No elasticity or response curve exists anywhere.
4. **The Brain ignores the Catalog.** `V_PLAN_WINDOW_JUDGMENT` judges on its own window; a quiet
   window produces `NOT_SERVING` — a "nothing to do" state this doctrine forbids.
5. **Seats do not fund their answers.** `seat_cost_per_day` is last window's spend repriced, not the
   cost of the verdict demanded.
6. **The book defers to Pacing on answered keywords** (`ENGINE_INSTRUCTED`) — precedence backwards.
7. **The move cap is symmetric**, so a confident cut is slowed as much as a speculative raise.
8. **`NOT_WORTH_NOW` does not exist**, so dormant seasonal keywords are paused as dead.
9. **Ranking uses a proxy** (`dollars_at_stake x closeness`) because no marginal value exists.

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
| **2. Brain** — what we decided | the intent (`REPAIR` / `TEST` / `PARK` / `STOP` / `EARN`), the ceiling or the seat and its budget, and why this and not something else in the family | *why are we spending — or not spending — here?* |
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
