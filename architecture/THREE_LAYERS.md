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

### 2.1 Subject types — not everything the ladder holds is a keyword

`ask()` takes a **subject type** alongside the subject, because the three types the account actually
contains behave differently and may not be compared the same way. Measured 2026-08-24, the split by
settled spend is roughly half real keywords, a quarter auto-targeting modes, and the remainder product
targets — re-derive with a GROUP BY on the target text pattern over `FACT_KEYWORD_STATE`.

| type | the subject is | cross-family comparison | why |
|---|---|---|---|
| **real keyword** | the phrase, scoped to its family | share the **demand** signal; never the **worth** | the phrase carries intent that genuinely travels; the bar, product margin and halo do not |
| **auto-targeting mode** (`substitutes`, `complements`, `close-match`, `loose-match`) | **family x product x mode** | **never as "the same subject"** | it is a container, not a phrase: `substitutes` for one product targets entirely different competitors than for another |
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

### 3.2 The Brain is restless — including about what is already earning

The Brain's job is not only to stop losses. **It must always be asking what it could do better, and that
includes the earning side.** "Leave it alone" (§3, `EARN`) is a protection against churn, not a licence to
stop thinking: a keyword that is working may still be underfunded, priced below what it could afford, or
winning a placement it could win more of.

So the Brain carries a sixth intent:

| the Brain issues | meaning | Pacing's obligation |
|---|---|---|
| `LEAN_IN · ceiling C` | the evidence improved and we believe it; spend more here | raise toward the new ceiling, gradually (§3.1 — this is a raise) |

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

A corollary the account does not currently satisfy: **a layer cannot be graded on predictions it does
not keep.** `FACT_KEYWORD_STATE` is replaced every night and holds one day, so the Catalog has no record
of what it said last month and cannot be scored on it. Any layer expected to improve must retain its own
answers.

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

**Catalog**
1. It emits commands — `WINNER` / `DEAD` / `REPRICE` flow into books as actions.
2. It is not seasonal, though two full holiday seasons of ads data exist.
3. It has no marginal model: the affordable price is an average, and no response curve or elasticity
   exists anywhere.
4. It sees only what the account already spent — **no demand data (SQP) reaches it at all**, so it can
   describe what was captured but never what was available.
5. It cannot propose candidates: there is no `rank(family, window)`, so the Brain can only judge
   keywords that already exist and already spend.
6. **It keeps no memory** — the state table is replaced nightly and holds one day, so the Catalog cannot
   be graded on its own predictions and §6 is currently impossible to satisfy.

**Brain**
7. It ignores the Catalog, judging on its own window; a quiet window yields `NOT_SERVING` — the
   "nothing to do" state this doctrine forbids.
8. Seats do not fund the answers they demand.
9. `NOT_WORTH_NOW` does not exist, so dormant seasonal subjects are paused as dead.
10. It protects turns but never funds them: `LEAN_IN` is doctrine, not code.
11. Ranking uses a proxy (dollars at stake x closeness) because no marginal value exists.
12. It covers part of the account — a few hundred of the Catalog's subjects — and the uncovered
    remainder is where the "nothing to do" hole lives.

**Pacing**
13. It has no scorecard: nothing measures whether the bid it chose delivered the clicks and CPC it
    implied, so house constants like the entry anchor have never been checked.
14. **A park carries no re-test obligation.** Measured today, the overwhelming majority of parked
    subjects took zero clicks in a week — a park is safe from cost and safe from discovery at once, so
    a recovery there can never be found by anyone.

**Boundaries**
15. The book defers to Pacing on answered subjects (`ENGINE_INSTRUCTED`) — precedence backwards.
16. The move cap is symmetric, so a confident cut is slowed as much as a speculative raise.

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
