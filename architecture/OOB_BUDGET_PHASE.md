# Out-of-budget phase — Weekly Run

**Date:** 2026-07-30 · **Owner:** Ori · **Status:** v2 — campaign → keyword → search-term hierarchy + apply-all (v1: campaign-level advisory)

## Goal (Ori, verbatim intent)

> "Main goal is that campaigns won't be out of budget but use almost all their budget.
> If campaign is out of budget and performs good — raise budget."

A **technical phase**, deliberately straightforward: one screen listing every enabled campaign
(SP **and** SB, launch **and** working) that Amazon reported `CAMPAIGN_OUT_OF_BUDGET` on the
anchor day, with the dark %, utilization, performance and ONE budget suggestion each.

## Where

Weekly Run page, its own collapsible section directly **below the Coach-logic flowchart** and above
the launch cards. Component: `dashboard-react/src/pages/OobBudgetPhase.tsx` · cube `OobBudget`
(live read) · view `scripts/bigquery/views/V_OOB_BUDGET_PHASE.sql`.

## Rules (same definitions as the launch controller's budget ladder — applied uniformly)

Signals: `pct_dark` = share of the anchor day Amazon reported out-of-budget (from the unified
`V_SRC_AmazonAds_campaign_history` event log — see CAMPAIGN_LAUNCH_RAMP.md §"Status source");
net ROAS = corrected gross profit ÷ spend, 1.0 = breakeven (SP from FACT + price-tier COGS; SB
estimated via the campaign's mapped ASIN cost ratio, same as `V_SB_LAUNCH_CAMPAIGN`).

| condition (first match wins) | action | suggested budget |
|---|---|---|
| dark ≤ 10% | WATCH | — (touched the cap but barely; no move) |
| prev-2d net ROAS ≥ 1.5× | RAISE_STRONG | `LEAST(budget ÷ %active, budget × 3)` — fund full-day demand |
| last-day net ROAS ≥ 1.2× | RAISE_WEAK | `LEAST(budget ÷ %active, budget × 2)` |
| prev-2d net ROAS < 0.9× | CUT | `GREATEST(budget × 0.9, $10 floor)` — **−10% per day** toward the floor (Ori 2026-07-30: "lower budget slowly until minimum"; was one −40% jump). Repeated daily while it stays dark and losing; a recovery any day stops the slide. |
| otherwise (mid 0.9–1.5×) | HOLD | — (budget stays; bids do the work) |

`budget ÷ %active` is the projection of what a full serving day would cost — the raise that makes
the campaign *stop* being dark, which is the phase's goal state: **dark 0%, utilization ~85–100%**.

## v2 — keyword and search-term layers (Ori 2026-07-30)

Hierarchy on the panel: **campaign → keywords → search terms**, with one **apply-all** button that
queues every suggestion (budget updates + bid updates + term negations) into the DO queue /
bulksheet flow. Mechanism note (validated in data 2026-07-30): bid cuts do NOT reduce spend — the
budget caps spend either way; they lower CPC so the same budget serves more of the day. 69% of
dark-campaign spend sat on 6+-click keywords, so the −5% lever touches most of the money.

**Keyword layer** (`V_OOB_KEYWORD` — SP keywords/auto/PT **and SB keywords/product targets**;
v2.1, Ori: "i cant see sb keywords as a hierarchy". SB signals from the SB reports with the
est.-net-ROAS cost-ratio method; SB bids from the live sb_keyword / sb_product_target config
mirrors. **Target CPC column** (Ori: "based on time last year if data exists"): precedence =
(1) same 28 days one year back (364-day offset keeps weekday alignment; needs ≥10 LY clicks),
(2) else the coacher band `cpc_target` (product × season × match, conclusive ALL/ALL cells
averaged), (3) else — . Auto clauses/PT skip LY — the clause text is not product-specific.):
same constants as the launch controller, applied to every OOB campaign regardless of engine —
- CONVERTING (net ROAS ≥ 1.0 on last day OR prior-2d) is **exempt from the click band** (Ori
  decision): it follows the ROAS ladder — hold-while-capping unless the campaign itself is strong;
  both windows > 1.5× → +30%; last day > 1.2× → +15%; cap $2.00. The budget raise is the right
  lever for a converting keyword in a dark campaign, not a bid cut.
- NOT converting → click band on the last complete day's clicks: **< 4 clicks → +5%** (cap $1.50)
  · 4–5 → hold · **≥ 6 clicks → −5%** (floor $0.20).
- 1-day cooldown: a keyword changed < 1 day ago (FACT_PPC_CHANGE_LOG) shows HOLD "changed today".

**Search-term layer** (`V_OOB_SEARCH_TERM`, SP + SB, TWO windows — Ori 2026-07-30: "to negate
general big words need to check 3 month data; small volume words 28 days are enough"):
- **big general word** (≥ 30 clicks over 90 complete days **ACCOUNT-WIDE**, all campaigns SP+SB —
  per-slice volume fragments a big word into "small" pieces; caught by Ori on "teen girl gifts
  trendy stuff": 13 clicks in one slice, 1,326 clicks / 11 orders account-wide) → negate only on
  **0 orders anywhere in the full 90d**, and only in slices with ≥ 3 clicks/90d here;
- **small word** → negate at **≥ 10 clicks · 0 orders over 28d**;
plus the structural rules: the term is not the keyword itself (`term ≠ keyword`, normalized —
applies to MANUAL and SB keywords), AUTO targets skip the term≠keyword test (every auto term
differs by construction; the 0-order gate protects harvesting), PT targets excluded entirely
(the "term" is the targeted ASIN). Winners (orders in 90d) are shown, never negated.

`days_since_budget_change` (from `FACT_PPC_CHANGE_LOG`) is displayed so re-suggestions after a
fresh change are visibly "just changed".

## Known caveats

- SB campaigns overdeliver up to **2× daily budget** while "out of budget" (Amazon SB rule) —
  utilization > 100% on SB rows is real spend, not a bug.
- For LAUNCH campaigns the suggestion matches `V_LAUNCH_PHASE1`'s dark-gated branch by
  construction (same constants); the not-dark branches (starve / promotion) live only in the
  launch controller — this phase only covers campaigns that actually went dark.
- Anchor day per channel: SP anchors on FACT's watermark, SB on `sb_campaign_report`'s — each
  channel is judged on its own last complete day, mirroring the two launch engines.
