# Strategies & Weekly Workflow — Claude's understanding, for Ori to correct

**Date:** 2026-07-16 · **corrected 2026-07-17**
**Purpose:** Ori said "I think we are not aligned." This is **my** model of his strategies and workflow,
written down so he can see where it is wrong. It is not a spec and not instructions — it is a mirror.
Anything marked ❓ is a real question, not rhetoric.

> **CORRECTION (2026-07-17).** The first version of this document asked whether "strategy auto" meant the
> Coverage AUTO role or the `LOW_COST_DISCOVERY` template, and implied `strategy_id` was Ori's real model
> that I'd walked past. **`architecture/INTENT_CAMPAIGN_MODEL.md` already answers this and I had not read
> it.** The Coverage roles ARE the target model; the `strategy_id` templates (HUNTER, EXACT_BOOST,
> LOW_COST_DISCOVERY…) are the model being migrated AWAY from — *"the new model runs beside the existing
> offense strategies; products migrate one at a time"* (§Goal & context). So "use this system gradually,
> first step strategy auto" = adopt the intent/Coverage model role by role, starting with Auto — which is
> what got built. §1 below is kept, corrected, because the four-way naming collision is still real.
>
> The real misalignment was not the taxonomy. It was that **I designed against my own reconstruction
> instead of reading the design doc that already existed.** The $10/day + $1.00 bid I "elicited" from
> Ori for the launch ramp was already decided in that doc (§Goal & context). The role-classification
> CASE I "lifted out of Flask" is written out in its §F.

---

## 1. "Strategy" means FOUR different things — still a real collision

Not the root cause (see correction above), but a genuine source of ambiguity in every conversation.

| # | What the code calls it | Values | Where it lives | Refs |
|---|---|---|---|---|
| 1 | `strategy_id` | HUNTER, EXACT_BOOST, LOW_COST_DISCOVERY, TOS_DOMINATION, SEASONAL_PUSH, NEW_LAUNCH, RETARGETING, CATEGORY_CONQUEST, COMPETITOR_CONQUEST, BRAND_DEFENSE, PRODUCT_DEFENSE | `DIM_STRATEGY_TEMPLATE`, `DIM_EXPERIMENT`, `src/strategies/*.ts` | **290** |
| 2 | `strategy_type` | SCALE / MARGIN / CUT | Weekly Run step 4 grouping | 3 |
| 3 | `strategy_role` | AUTO / EXACT / BROAD / PHRASE / COMPETITOR / SB_VIDEO | `V_CAMPAIGN_ROLE` — **I added this today** | 14 |
| 4 | PPC mode | Offense / Brand Defense / Product Defense | Weekly Run toggle | — |

**#1 is the LEGACY model being migrated away from.** 11 templates, each with a recommended campaign
type, match type, bidding strategy and TOS%. Current mapping: HUNTER 54, LOW_COST_DISCOVERY 27,
EXACT_BOOST 24, COMPETITOR_CONQUEST 13, BRAND_DEFENSE 8, PRODUCT_DEFENSE 8, CATEGORY_CONQUEST 5. Per
INTENT_CAMPAIGN_MODEL.md: *"No existing strategy is deleted in A/B"* — they run alongside while products
migrate one at a time. Brand/Product Defense survive the migration; the rest are what Auto/Exact/Broad/…
replace.

**#3 is the target model** and what today's "Budget by strategy" table groups by. Correct.

The collision that remains: `strategy_type` (SCALE/MARGIN/CUT) and `strategy_role` (AUTO/EXACT/…) sit in
the same Weekly Run screens and both read as "strategy". Step 4 groups by `strategy_type`; step 1's new
split groups by `strategy_role`. Worth renaming one day.

---

## 2. The target model (per INTENT_CAMPAIGN_MODEL.md — the authority, not my reconstruction)

**Campaign grain (governing rule, Ori 2026-07-16):**

| Role | Grain |
|---|---|
| AUTO | **per product** — the only per-product role |
| BRAND_DEFENSE | per family |
| PRODUCT_DEFENSE | store — cross-family, one catalogue-wide |
| COMPETITOR / EXACT / BROAD / PHRASE / SB_VIDEO | family × match-type × **intent theme**, ≤10 keywords |

This is why the 14 campaigns launched on 2026-07-15 are one `*-SP/AUTO` per product — exactly the rule.

**New campaigns start at $10/day and a $1.00 default bid** (§Goal & context) — already decided there.
The launch ramp built on 2026-07-16 is the *continuation* of that decision: what happens on days 1-20
after the $10/$1.00 start.

**Terminology, already settled in that doc:** bare **"intent"** = the keyword class BRAND/PRODUCT/GENERIC.
**"intent theme"** = the bucket (journal, birthday, easter). Don't mix them.

**Coverage (§F)** is the gap scanner over this model, at each role's own grain — one button per family
plus a Store button. Phase 1 (now) checks Auto per product, Brand Defense per family, Product Defense at
store, and family-level *presence* of Competitor/Exact/Broad/Phrase/SB_Video. Phase 2 expands to
per-intent checks once the intent model exists. `V_CAMPAIGN_ROLE` (built 2026-07-16) is §F's
classification rule lifted into BigQuery so Coverage and Weekly Run share it.

❓ Still open from that doc's own list: product-vs-family grain for intent keywords (its open question
#1), and whether `DE_COVERAGE_EXPECTATION` (opt a product out of a role) exists yet — the coverage
endpoint doesn't appear to read it.

---

## 3. Campaign lifecycle (as I understand it today)

```
   created  ──►  LAUNCH RAMP (days 1-20)  ──►  MATURE (day 21+)
                 $10/day, $1.00 bid              coacher decides
                 budget maxed that day?
                   ├─ target >3 clicks  → bid × 0.93
                   └─ 3d net ROAS >1.5  → budget × 1.10
                 not maxed → nothing changes (self-arresting)
```

Built and verified today (`V_CAMPAIGN_LAUNCH_RAMP`). Replaces the old `LAUNCH_*` track in `V_ADS_COACH`.

Mature campaigns are then judged by the coacher in one of three modes: **GUARDIAN** (protect profit),
**BLITZ** (peak push), **COOLDOWN** (ease back after peak).

❓ Where does a strategy template attach — at creation (it dictates the campaign's shape) or
continuously (it keeps steering bids after day 21)? Today the coacher's rules seem to run off
`coach_mode` + thresholds, and I can't see the strategy template influencing a mature campaign's bids.

---

## 4. The weekly workflow (Weekly Run page)

| Step | What it does |
|---|---|
| PPC toggle | Offense (grow) / Brand Defense (own the brand SERP) / Product Defense (cross-sell, $30 learning start) — three independent pools |
| 1 · Budget | Per family, now also per strategy. Both tables are selectors; they intersect. Default = All |
| 2 · Budget | Per campaign inside the picked slice — edit and queue |
| 3 · Plan | The week's plan cells (family × season × match × intent), each with a PURPOSE: SCALE / DEFEND / MAP / PROBE / CUT / HOLD — review & approve |
| 4 · Actions | Keyword bids + negatives, grouped SCALE/MARGIN/CUT |
| 5 · Upload | Export bulksheet → upload to Amazon **manually** (no Ads API write path) |
| 6 · Done | Acknowledge |

Key constraints I'm working under:
- **Net ROAS = GROSS_PROFIT ÷ ad spend, direct-attributed only, no halo credit.**
- **Manual bulksheet only** — the engine proposes, you upload. This is why the launch ramp is a *view*
  that replays history rather than a daily job: it's always current whenever you sit down.
- **Weeks are Sun–Sat**; ads data lags; FACT/V_ are America/Los_Angeles.
- Cooldown: a target's re-suggestions hide for 3 days after a change; one bid change per keyword per 7
  days under GUARDIAN. **The launch ramp must be exempt from both**, or the daily ladder gets swallowed.

---

## 5. Budget philosophy — mid-change, and I don't fully understand the destination

**Was:** top-down. One `total_daily_budget` ($770) split across families by profit, then across
campaigns by ROAS tier.

**Your call today:** *"the total budget is not relevant — remove it."* Confirmed as: kill the global
pool; every campaign's budget is set on its own merits; the total becomes a reported sum, not a dial.

**Done so far:** the dial UI is gone from step 1.
**Not done:** the backend still divides $770 — which is why the family table totals $770.00 while the
strategy table totals $629.90. Those two numbers disagree *on your screen right now* and that is a
known, temporary state.

`V_CAMPAIGN_DAILY_MOVE` already implements bottom-up (out-of-budget gate → ROAS decides raise/cut) and
is dormant, wired to nothing, and clamped to the family cap — the exact clamp you're removing.

❓ **The open question:** with no pool, what stops total spend from growing without limit? Today the cap
is the brake. Bottom-up, the only brake is "is this campaign profitable" — which is a real answer, but
it means spend is an outcome you observe, not a number you set. Is that what you want?

---

## 6. Where I think I've been getting it wrong

Honest list, so you can confirm or correct:

1. **I didn't read INTENT_CAMPAIGN_MODEL.md before designing against it.** This is the big one and it
   caused all of the rest. I re-derived the $10/$1.00 start by asking Ori questions he had already
   answered in writing, and "lifted the role CASE out of Flask" when §F is its source. **Fix: read
   `architecture/` first — it is layer 1 of A.N.T. and CLAUDE.md says SOPs come before code.**
2. **I assumed Auto was a gap to fill.** It isn't — 31 auto campaigns, $19.4k/90d, the second-biggest
   surface. Ori isn't building Auto from zero; he's taking over something large and live.
3. **I keep treating each request as a UI change when it's a model change.** "Remove the total budget"
   wasn't a UI edit, it was a redesign of how money is decided. I nearly implemented it as a delete.
4. **Counts disagree across steps.** Step 1/2 counts budget-eligible campaigns (59); step 4 counts every
   campaign with history including paused (118). SB/Video reads 12 in one and 25 in the other.

## 7. What would align us fastest

§5's question — what brakes total spend once the pool is gone. That decides what the budget engine
becomes; everything else follows from the model already written in INTENT_CAMPAIGN_MODEL.md.

**Reading order for anyone (including me) picking this up:**
1. `architecture/INTENT_CAMPAIGN_MODEL.md` — the target campaign model. **The authority.**
2. `architecture/CAMPAIGN_LAUNCH_RAMP.md` — days 1-20 of a new campaign, + the bottom-up budget decision.
3. This file — the map between them and the Weekly Run surface.
