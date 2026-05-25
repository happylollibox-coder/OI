# Plan Page — Forecast / Tracking Toggle (family-level target vs actual)

**Date:** 2026-05-25
**Component:** `dashboard-react/src/pages/PlanPage.tsx` (family overview table in `Section`)
**Status:** Design — pending review
**Builds on:** the wizard-sourced-forecast rewire (`2026-05-24-wizard-sourced-forecast-design.md`) and the Approved-Plan-vs-Reality panel.

## Problem

The family overview table is a **forecast / P&L summary** ($/day, Stock, Ad Spend, ROAS, YTD NP, EOY NP, OOS, PR Qty, Landed $). It answers *"what's the plan and what will it earn?"* — not *"am I executing to my plan?"* The user wants a family-level **target-vs-actual** view: ad spend, units sold, unit stock, CPC.

## Goal

Add a **Forecast / Tracking toggle** above the family overview. Forecast = the current columns (unchanged). Tracking = per-family target-vs-actual for **ad spend, units sold, stock, CPC**, with **both** plan-to-date and full-horizon targets.

## The key semantic issue (must resolve in review)

The wizard plan is **forward-looking**: the saved snapshot units and coach `daily_spend`/`cpc` targets cover the **horizon only — current month → Feb'27**. There are **no plan values for already-elapsed months (Jan–Apr'26)**. Actuals, conversely, are **Jan → now**. So:

- The plan and the actuals **only overlap in the current (partial) month**.
- A naive "plan-to-date vs actual-to-date" over Jan→now is apples-to-oranges: the plan didn't exist for Jan–Apr.

So "target vs actual" at a family level resolves cleanly into **three honest quantities**, which is how this view is defined:

1. **This month (pace):** plan for the current month **prorated to today** vs actual MTD. Answers *"am I on pace this month?"* — the only true overlap.
2. **Horizon target (full):** the plan total over current→Feb'27 — the forward commitment / goal.
3. **Actual YTD:** Jan→now actuals — where the family stands today.

The user's "plan-to-date + full-year" maps to (1) **pace this month** + (2) **horizon target**; (3) actual-YTD is the reference.

## Layout (Tracking tab)

Per family row:

| Family | Ad Spend (MTD act / MTD plan) | Ad Spend horizon target | Units (MTD act / MTD plan) | Units horizon target | Stock | CPC (act / target) |
|---|---|---|---|---|---|---|

- **Ad Spend — pace:** `actual MTD` vs `plan MTD` (Δ% badge: under/over). **horizon target:** Σ coach targets current→Feb'27.
- **Units — pace:** `actual MTD` vs `plan MTD`. **horizon target:** Σ snapshot units current→Feb'27.
- **Stock:** current inventory (actual only).
- **CPC:** `actual` (YTD or trailing) vs `target` (weighted coach `cpc_target`). Single comparison (CPC isn't cumulative).

Unplanned families (no saved targets) show actual columns only, with "—" for plan/target and the existing "est · not planned" badge.

## Data sources

- **Ad spend actual (MTD):** `actuals2026Full` `adCost` for the current month, summed over the family's products.
- **Ad spend plan (MTD):** Σ coach `daily_spend_target` × elapsed-days-of-current-month (prorated) for the family; **horizon target** = Σ `daily_spend_target × days` over all plan months.
- **Units actual (MTD):** `actuals2026Full` `units`, current month, family sum. **plan (MTD):** current-month snapshot units × (elapsedDays / daysInMonth). **horizon target** = Σ snapshot units current→Feb'27.
- **Stock:** `f.inventory`.
- **CPC actual:** from `channelEfficiency` (`AdsChannelEfficiency` — already loaded; carries spend + clicks per family) → `Σ spend / Σ clicks`. (If trailing-window CPC is preferred, use the channel-summary window already computed for the Ads Path.) **CPC target:** spend-weighted avg of the family's saved `cpc_target`.

No new BigQuery objects; `AdsChannelEfficiency` and the coach targets are already fetched. (Targets are fetched per-family by the rewire's `plannedSpend`; reuse it — extend it to also keep `cpc_target` if needed.)

## Toggle mechanism

A `viewMode: 'forecast' | 'tracking'` state on the overview `Section`. Two pill buttons above the table (mirroring the existing Compare/tab styling). The `<thead>` and each family `<tr>` render the column set for the active mode; the expanded-row detail is shared/unchanged. Keep the row count aligned per mode.

## Scope

**Changes:** the toggle + the Tracking column set (header + per-family cells + totals) in `Section`; reuse `plannedSpend`, `activeSnapshot`/`plannedUnits`, `actuals2026Full`, `channelEfficiency`.

**Keeps unchanged:** the Forecast columns (current view); the expanded-row detail; the wizard; the Approved-Plan-vs-Reality panel (the per-month drill-down — Tracking tab is the family summary).

**Out of scope:** per-month tracking in this table (that's the panel); reconstructing a Jan–Apr plan the wizard never produced; per-variation CPC (family-grain only, per the attribution rule).

## Open questions / risks

- **Window mismatch (above)** — confirm the "pace this month + horizon target + actual YTD" framing is what you want, vs a different cut.
- **CPC actual window:** YTD vs trailing-N-months — which is more useful for the at-a-glance row?
- **Column density:** ~10 columns; if too wide, collapse Ad Spend/Units "pace" into a single "act vs plan (Δ%)" cell with the horizon target as a tooltip.
