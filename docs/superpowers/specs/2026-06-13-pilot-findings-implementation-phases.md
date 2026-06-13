# Pilot Findings — 3-Phase Implementation, Sequenced by Trust Stage

**Date:** 2026-06-13
**Source research:** `docs/research/2026-06-03-pilot-experiment-findings.md` (24-day pilot; provisional)
**Anchoring principle:** we are mid-Stage-1 of the business-unit coacher ([[project-business-unit-coacher]]) — the coacher just started surfacing actions; the receipt-loop scorecard hasn't graded anything yet; **Ori does not yet trust automated actions.** Each phase below is ordered by *how much trust it requires before it can run*, not by how clever it is. Robust principles that **reduce ways the coacher loses trust** come first; powerful machinery that **spends money on unproven theses** comes last.

Cross-cutting rule (carries through all phases, per Ori 2026-06-13, [[feedback-coacher-no-auto-fill]]): the coacher only emits values it deliberately decided. Every threshold here is owner-tunable in `CoachThresholds`; every operator input in §11 stays operator-set.

---

## Phase 1 — Safety & Honesty (protect the trust you're building now)

**Pilot sections:** §4 (attribution asymmetry), §8a/§8b/§8c (negative safety), §3 (settled-window for *cuts* only).

**What it does:** hardens the actions the coacher **already surfaces today** — no new campaigns, no new spend, no fragile constants. It removes the specific ways an automated cut goes wrong.
- **§4 asymmetry** — forbid any cut/negate/reduce on data younger than the 2-day lag; allow scale on raw recent data (raw = worst case). Generalizes the "recovering this week → don't cut" rule already in the gate. *Direction only — not the 1.16/1.08 uplift constants (those wait for §12 validation).*
- **§8b negative audit** — a one-shot + recurring check: any search term a family **negates** that the **per-family hero** says it *converts* on → surface a "remove conflicting negative" card. (Half-built already: per-family hero exists; auditing existing negatives is new.)
- **§8a inherited-negative filter** — when the launch flow seeds negatives, drop any whose text is a substring of the new keyword.
- **§8c relevance + sufficient-clicks before negate** — raise the negate click floor to where 0 orders is *signal not noise* (≥~20), and require the term not be a known converter.

**Why it fits the current confidence stage:** at Stage 1 the fastest way to **lose** trust is one visibly-wrong cut — negating a winner, cutting on unsettled data, killing a term that was about to recover. Phase 1 is pure downside protection: it makes every card you already review daily *safer and more honest*, with zero new risk surface. It's the cheapest possible trust deposit. **It can ship now** — it depends only on data already loaded.

**Dependencies:** none new. Mostly gate-logic (`clearCase`) + one new audit view/card.

---

## Phase 2 — Discovery & Launch Engine (earn the right to *create*)

**Pilot sections:** §5 (CVR-primary + SQP seed + volume gates), §6 (Broad+Phrase dual launch, match-scope bid caps), §7 (product- vs audience-descriptive ranking), §9 (checkpoint engine), §3 (full trailing-7-settled grading).

**What it does:** turns the coacher from a *trimmer* into a *launcher*. This is the Stage-3 launch-ramp + NEW-sourcing slice on the existing roadmap, upgraded with the pilot's evaluation rules:
- §5 — `V_RESEARCH_RANKED` already scores CVR/SQP; tighten the launch gate to CVR-after-≥20-clicks, seed new keywords from SQP CVR, keep the ≥10-click/≥2-order scale gate.
- §6 — launch each NEW candidate in **both Broad and Phrase**; match-scope-aware bid caps (+5% Broad/Auto, +20% Phrase/Exact).
- §7 — rank product-descriptive candidates above audience-descriptive in NEW sourcing.
- §9 — the checkpoint engine: trailing-7-settled ROAS, Day-7 max action = bid-down (never close), never close on <3-day data, scale only on volume.

**Why it fits the current confidence stage:** creating campaigns spends real money on *unproven* terms — strictly higher-stakes than trimming. The coacher must **not** be granted launch authority until the receipt-loop scorecard has shown its cut/keep judgment is reliable (the Stage-2 success test). Phase 2 is where the coacher proves it can *find and grow winners*, but every rule here is conservative-by-design (dual-match fair tests, never-close-early, scale-only-on-volume) — it expands authority **only in the direction the receipts have already validated.** Gate it behind: scorecard hit-rate holding ≥ your bar.

**Dependencies:** Phase 1 (safe negatives feed the launch seeding); the Stage-3 engine work (territory, CoachThresholds-in-engine); operator inputs §11.3/§11.4 (p1 handling, family→portfolio map).

---

## Phase 3 — Strategic Seasonal Layer (highest stakes, most validation)

**Pilot sections:** §1 (family-relative ROAS), §2 (PROFIT vs CPC_BANK objectives), §12 (the 2-year validation that underpins both), §11.1/§11.2 (peak date, floor bid).

**What it does:** the powerful, money-on-a-thesis layer.
- §1 — family-relative grading **as a prioritization lens with an absolute profit floor underneath** (the critical refinement: beating a barely-profitable family ≠ being profitable; net ROAS ≥ breakeven still gates KEEP/CUT). Requires reconciling the pilot's gross-looking ROAS table into the coacher's **no-halo net ROAS** world ([[fact-oi-net-roas-no-halo]]).
- §2 — the PROFIT / CPC_BANK objective tag: deliberately keep some unprofitable-today campaigns alive to bank cheap CPC for peak. Operator-tagged per campaign, never a default.

**Why it fits the current confidence stage:** this is the only authority that lets the coacher **keep money-losing campaigns alive on purpose** — the single most dangerous power to automate, and the one that most needs a long track record before you'd grant it. It also leans hardest on *constants* (family ROAS table, uplift factors, CVR floor) that come from **one 24-day off-season run** — your own §12 says validate against 2 years first. So it lands last: after the coacher has months of graded receipts (trust earned) **and** the constants have survived historical validation (numbers earned). This is the "fully-trusted, runs the seasonal playbook" stage — analogous to Stage-4 end-state in the spec.

**Dependencies:** Phases 1–2; the §12 2-year validation study; gross-vs-net ROAS reconciliation; operator inputs §11.1/§11.2; family→portfolio mapping.

---

## Section → Phase map

| § | Finding | Phase | One-line why |
|---|---|---|---|
| 4 | Attribution asymmetry (cut-safety + uplift direction) | **1** | Stops wrong cuts on unsettled data — pure trust protection |
| 8a | Filter inherited negatives | **1** | Prevents self-zeroing a new keyword |
| 8b | Audit existing negatives vs own winners | **1** | Stops a product blocking its own converters |
| 8c | Relevance + click-floor before negate | **1** | Don't negate on statistical noise |
| 3 | Settled window (for cuts) | **1** → full in **2** | Don't punish recovered ramp-up |
| 5 | CVR-primary, SQP seed, volume gates | **2** | Right signal for launching/scaling |
| 6 | Broad+Phrase dual launch, scope-aware caps | **2** | Fair test per match type |
| 7 | Product- vs audience-descriptive ranking | **2** | Launch terms that actually convert |
| 9 | Checkpoint / pilot evaluation engine | **2** | Conservative graduate/close logic |
| 1 | Family-relative ROAS (+ absolute floor) | **3** | Powerful lens; needs net-ROAS + validation |
| 2 | PROFIT / CPC_BANK objectives | **3** | Keeps losers alive — max-trust authority |
| 12 | 2-year validation | **3** (gate) | Constants must be earned, not 24-day |

## Trust-stage alignment (one sentence)
**Phase 1 hardens what you review today → Phase 2 earns the right to create once the scorecard proves the judgment → Phase 3 grants the seasonal "keep-losers-alive" authority only after months of receipts and a 2-year validation.** Each phase requires more accumulated trust than the last, and grants exactly the next increment of authority.

## Status vs. what's already built
See the implemented/not table in the chat review (2026-06-13): ~3 ideas live (per-family judgment, volume gates, halo-risk parking), ~4 partial cousins, ~6 net-new. Phase 1's negative-audit and Phase 2's launch engine are the largest net-new builds; Phase 3 is mostly new + a validation study.
