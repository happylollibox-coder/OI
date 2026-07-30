# Out-of-budget phase — Weekly Run

**Date:** 2026-07-30 · **Owner:** Ori · **Status:** v1 shipped (view + cube + Weekly Run section)

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
| prev-2d net ROAS < 0.9× | CUT | `GREATEST(budget × 0.6, $10 floor)` — a capping loser is not funded |
| otherwise (mid 0.9–1.5×) | HOLD | — (budget stays; bids do the work) |

`budget ÷ %active` is the projection of what a full serving day would cost — the raise that makes
the campaign *stop* being dark, which is the phase's goal state: **dark 0%, utilization ~85–100%**.

Advisory v1: the section shows the numbers + suggestions; applying still happens through the
existing launch cards / bulksheet flow. `days_since_budget_change` (from `FACT_PPC_CHANGE_LOG`)
is displayed so re-suggestions after a fresh change are visibly "just changed".

## Known caveats

- SB campaigns overdeliver up to **2× daily budget** while "out of budget" (Amazon SB rule) —
  utilization > 100% on SB rows is real spend, not a bug.
- For LAUNCH campaigns the suggestion matches `V_LAUNCH_PHASE1`'s dark-gated branch by
  construction (same constants); the not-dark branches (starve / promotion) live only in the
  launch controller — this phase only covers campaigns that actually went dark.
- Anchor day per channel: SP anchors on FACT's watermark, SB on `sb_campaign_report`'s — each
  channel is judged on its own last complete day, mirroring the two launch engines.
