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
| 2026-08-24 18:30 | `pending` | **§2.5 quantity, §2.6 what is advertised, §6.3 demonstrate don't assert, §10 the baseline.** A simulated keyword-year against the doctrine, measured across the account, then put through two adversarial verifiers. The arithmetic passed; **three of the four largest claims did not** — each had measured a population correctly and then asserted a loss without testing the innocent explanation. That failure produced the three new rules. §2.5: worth is a curve over volume, not a scalar price — the post-season month that looked like mispricing was the account buying more clicks at the right price into weaker conversion. §2.6 (Ori's correction of my "substitution" framing): the Catalog must know **what is advertised** — format, placement, creative, match width — because most of the "destroyed" seasonal sales were the same demand arriving through a wider match. §6.3 makes the discipline standing. §10 records the survivors, the disproved claims, and three violations in §8 the research corrected — including that the coverage gap is entirely deliberate and that the move cap is not enforced in *either* direction. |

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

**Boundaries**
15. The book defers to Pacing on answered subjects (`ENGINE_INSTRUCTED`) — precedence backwards.
16. ~~The move cap is symmetric, so a confident cut is slowed as much as a speculative raise.~~
    **CORRECTED 2026-08-24 (§10.3): the cap is not enforced in either direction — both sides break it,
    and cuts break theirs proportionally more often than raises break theirs.** Asymmetry (§3.1) is
    still the right design; the prior defect is that no cap binds at all.

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

- **Dwell time in any state.** The Catalog holds one snapshot and is replaced nightly, so no "how long has
  this been stuck" question is answerable anywhere. This is violation 6 obstructing the measurement of
  every other violation, and it is the single highest-value thing to fix first.
- **Bid-to-click response.** Nothing records the clicks and price a chosen bid was expected to deliver
  against what it delivered, so §2.5's curve cannot yet be estimated and Pacing cannot be graded at all.
- **Seasonal versus dead.** Two holiday seasons sit in the ads data and the Catalog does not read them, so
  a dormant subject and a dead one remain indistinguishable — the failure §4 exists to prevent.
- **Marginal versus average value.** Every "excess" figure above is computed against an average ceiling and
  therefore misstates the true overpayment in an unknown direction.

### 10.5 How to re-run this

Every figure came from a query recorded in the research output. When re-measuring: keep the unit labels,
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
