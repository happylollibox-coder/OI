# Approved-Plan Tracking Scorecard — plan vs actual by period

**Date:** 2026-05-25
**Component:** `dashboard-react/src/pages/PlanPage.tsx` (the `PlanVsRealityPanel`)
**Status:** Design — pending review
**Builds on:** the wizard-sourced-forecast rewire + the existing Approved-Plan-vs-Reality panel.

## Problem / use case

> "Let's say I approved a plan. After a week I want to see, per each measure I approved in the wizard, the **forecast vs the actual** done that week — ad spend, CPC, sold units, net profit."

So the need is an **approved-plan adherence scorecard**: for a chosen recent **period**, per family, show **plan vs actual** for the four wizard measures. Because any period after approval sits **inside** the plan horizon, plan and actual both exist for it — no Jan–Apr window mismatch.

The family **overview** table stays **Forecast-only** (the planning view). Tracking lives in the **panel** (already approved-gated, already a plan-vs-actual surface). Planning = overview; tracking = panel.

## Measures (the four approved in the wizard)

Per family, per period:

| Measure | Plan (forecast) | Actual |
|---|---|---|
| **Ad spend** | Σ coach `daily_spend_target` over the period | Σ `adCost` |
| **CPC** | spend-weighted `cpc_target` | Σ adCost ÷ Σ clicks |
| **Sold units** | Σ snapshot units over the period | Σ `units` |
| **Net profit** | plan units × margin − plan spend | revenue − cogs − adCost |

`margin = asp − costPerUnit` (family-weighted). Each cell shows **plan vs actual** with a Δ (and Δ%) and under/over coloring. Ad spend is family-grain (per the attribution rule); CPC family-grain.

## Period tabs

A period selector (tabs) on the panel:

1. **By week** — default to the latest **complete** week; prev/next to step back through weeks since approval. Plan is **prorated** month→week (`monthPlan × daysOfWeekInMonth / daysInMonth`); approximate at week grain (assumes even within-month distribution). Needs **weekly actuals** (see Data).
2. **By month** — pick a month (default current); plan = that month's stored plan (exact, no proration); actual = monthly actuals (already loaded).
3. **Since approval** — cumulative from the approval date → now: Σ plan vs Σ actual over whole + partial elapsed months since approved.

## Layout

Panel header: the existing title + a **period tab strip** (Week ‹ ›/ Month / Since approval). Below, a **per-family table**:

| Family | Ad Spend (plan → actual, Δ%) | CPC (plan → actual) | Units (plan → actual, Δ%) | Net Profit (plan → actual, Δ%) |

Plus a TOTAL row. The existing per-product per-month **units/spend grid** becomes a secondary "By month detail" (kept, or folded under the Month tab) so we don't lose the monthly breakdown.

## Data

- **Plan (frozen at approval):** snapshot units (`snapshot_units_json` / `original_overrides_json` sibling) + coach targets (`DE_PLAN_ADS_TARGETS`, incl. `cpc_target`). Use the **approved/frozen** values, not live wizard edits.
- **Monthly actuals:** `actuals2026Full` (units/sales/cogs/adCost) — already loaded. **No clicks** → CPC actual not available monthly without adding a clicks measure.
- **Weekly actuals (NEW):** a Cube query by ISO week × family with `units, sales, cogs, adCost, clicks`. Required for the Week tab and for CPC actual. (The dashboard already queries weekly elsewhere — same `UnifiedPerformance` cube, week granularity + a `clicks` measure.)
- **Approval date — DECIDED: use `updated_at`.** No `approved_at` exists on `DE_PLAN_STRATEGY` and we will **not** add one (no backend change). The "Since approval" tab uses the plan's `updated_at` (bumped at approval) as the window start. Caveat: editing an approved plan re-bumps `updated_at`, shifting the start — accepted for v1.

## Scope

**Changes:** restructure `PlanVsRealityPanel` into the period-tabbed scorecard (4 measures × plan/actual per family); add a weekly-actuals fetch (+ clicks); wire CPC + net-profit plan/actual; keep the monthly units/spend grid as detail.

**Keeps unchanged:** the family **overview** (Forecast-only — no Tracking toggle after all); the wizard; the forecast rewire; the order math.

**Out of scope:** per-variation CPC/ad spend (family-grain only); reconstructing pre-approval history; changing the coach.

## Resolved decisions

- **Placement:** tracking lives in the **panel** (approved-gated). The family **overview stays Forecast-only** (planning view) — no Tracking toggle on the overview.
- **Weekly proration:** month→week even split is **accepted as a pace check** (all four measures), despite ignoring intra-month seasonality.
- **Approval date:** use **`updated_at`** for the "Since approval" window (no backend change; accepts the edit-re-bump caveat).
- **CPC actual:** **Σ spend ÷ Σ clicks** over the selected period.

## Remaining risk

- Weekly proration understates/overstates peak-adjacent weeks (accepted). The TOTAL/Month/Since-approval tabs are unaffected by intra-month split.
