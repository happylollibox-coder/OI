# Wizard-Sourced Forecast — `effectiveProjs` + Remove Manual Levers

**Date:** 2026-05-24
**Component:** `dashboard-react/src/pages/PlanPage.tsx` (+ a new pure helper, likely in `planTypes.ts`)
**Status:** Design approved, pending implementation plan
**Builds on:** `2026-05-23-wizard-monthly-plan-vs-reality-design.md` (the wizard already saves a per-product per-month plan + coach spend targets)

## Problem

"**The wizard is the only way to manipulate the forecast.**" Today the Plan page contradicts that:

- The displayed forecast (`NEED`, `Ad Spend`, `ROAS`, `YTD/EOY NP`, `OOS`, `PR Qty`, the monthly table, Buy Plan, Cashflow) all come from `projs = runSim(...)`, which is driven by **manual levers on the Plan page** — the per-family **Strategy** preset, the per-month **multiplier** inputs, and the per-product **growth %** inputs.
- Meanwhile the **wizard** produces the real plan (per-product per-month units in `snapshot_units_json`, spend in `DE_PLAN_ADS_TARGETS`) — but that only flows to the order and the plan-vs-reality panel, **not** to the Plan page's headline forecast.
- Result: the wizard says one thing (e.g. Lollibox 14,306 units) and the Plan page shows another (12,898 from runSim). Two sources, no single truth.

## Goal

Make the Plan page's forecast **read from the wizard's saved plan**, and **remove the manual forecast levers**, so the wizard is the single source of forecast manipulation. `runSim` survives only as a **fallback estimate** for families not yet planned in the wizard.

## Decisions (from brainstorming)

- **Architecture:** a derived `effectiveProjs` (Approach A) — one builder substitutes wizard data into a `MonthProj[]`; the whole page swaps `projs → effectiveProjs` in one place.
- **Ad spend source:** the saved coach targets (`DE_PLAN_ADS_TARGETS` via `/api/plans/ads-targets/<family>`).
- **Growth editors:** removed (read-only) — the wizard's Growth step is the only growth lever.
- **Unplanned families:** show the `runSim` estimate, visually **flagged "not planned"**.

## Model

### The builder — `buildEffectiveProjs`

A pure function (testable, in `planTypes.ts`):

```
buildEffectiveProjs(
  projs: MonthProj[],                                   // runSim output (fallback)
  plannedUnits: Record<product, Record<monthKey, units>>, // wizard snapshot units
  plannedSpend: Record<family, Record<monthKey, number>>, // Σ saved daily_spend × days
  families: FamilyBaseline[],                            // for ASP / cost per product
  isPlanned: (family: string) => boolean,
): MonthProj[]
```

For each `MonthProj p` and each family:

- **If `isPlanned(family)`** — rebuild `p.families[fam]`:
  - per product `v`: `units = plannedUnits[v.name][p.key] ?? <runSim demand for that month>` (per-month fallback so a missing month doesn't zero out); `revenue = units × v.price`; `cogs = units × v.cogs`.
  - family `adSpend = plannedSpend[fam][p.key] ?? 0`.
  - per-product `adSpend` = family adSpend × (units / family units) — **display-only allocation**, not a real per-variation signal (per the 2026-05-20 attribution rule).
  - `netProfit = Σrevenue − Σcogs − adSpend`; `demand = Σunits`; `invEnd`/`isOos` recomputed from inventory − cumulative units; family `netRoas = (Σrev − Σcogs) / adSpend`.
- **Else** — pass the `runSim` `p.families[fam]` through unchanged.

Recompute `p` totals (`totalDemand`, `totalRevenue`, …) from the merged families. Output is the same `MonthProj[]` shape.

### Inputs

- **`plannedUnits`** — the wizard's composed snapshot: in-session `plannedMonthlyOverrides` composed with actuals (via the existing `composeMonthlyPlan`) takes precedence over the loaded `activeSnapshot`. (Reuses logic already in `buildPayloadRows`.)
- **`plannedSpend`** — fetch `/api/plans/ads-targets/<family>` for every family on load → `Σ(daily_spend_target × daysInMonth)` per family-month, keyed by `monthKey`. Same fetch the spend panel uses, hoisted to page scope. Async → guarded (see below).
- **`isPlanned(family)`** — true when the family has snapshot units for its products (i.e. appears in `plannedUnits`).

### Consumption swap

Replace `projs` with `effectiveProjs` at the Plan-page **display/forecast** consumers: the `items`/NEED computation, the family-row sim aggregates, the totals row, the monthly comparison table, the Buy Plan Summary, and `CashflowSection`. `runSim`/`projs` are still computed — they are the *input* (fallback) to the builder, not consumed directly for display.

`buildPayloadRows` (plan **save**) is unchanged — it already composes the snapshot from `plannedMonthlyOverrides` + actuals, so the saved artifact stays wizard-sourced and consistent with the display.

## Remove the manual levers

- **Strategy selector** — delete entirely (the dropdown relocated to the expanded row in the prior commit), plus `onStrategy` + its parent handler + the `strategy`/`showStrategyMenu` plumbing that only served it.
- **Per-month multiplier inputs** — remove the expanded-row editor.
- **Growth % inputs** (Growth & Velocity card) — make read-only (keep the YoY/velocity display).
- `strategies` / `mults` / `growthOverrides` **state remains** (loaded from the plan, still drives the `runSim` fallback for unplanned families) — just no longer user-editable on the Plan page.

## Unplanned-family flag

A family not in `plannedUnits` renders its `runSim` numbers with a small **"estimate · not planned"** badge next to its name, so estimated rows are visually distinct from wizard-planned ones.

## Loading guard

The targets fetch is async. Until `plannedSpend` has loaded for the planned families, the P&L (Ad Spend / ROAS / NP) would be understated. Show a subtle loading state (or fall back to runSim P&L) for planned families until their targets resolve, so no wrong number is shown as final.

## Testing

Unit tests for `buildEffectiveProjs`:
- planned family → units from snapshot, family adSpend from targets, revenue/cogs/netProfit/roas reconstructed correctly.
- unplanned family → runSim entry passes through byte-for-byte.
- a planned family with a missing month → that month falls back to runSim demand (no zero hole).
- per-product adSpend allocation sums to the family adSpend.

## Scope

**Changes:** the `buildEffectiveProjs` builder; page-level `plannedSpend` fetch; swap `projs→effectiveProjs` at display consumers; remove Strategy/mult/growth editors; "not planned" flag.

**Keeps unchanged:** the wizard itself; the coach; `runSim` (now the fallback); `buildPayloadRows`/save; the order math; the plan-vs-reality panel.

**Out of scope:** treating per-product ad spend as a real signal (it's a display allocation); changing the coach's spend logic; a bulk ads-targets endpoint (per-family fetch is fine for v1).

## Open questions / risks

- **Every number on the page now flows through the builder** — so the builder's tests are the safety net (live verification is being deferred this round). High blast radius.
- **Saved vs unsaved:** the page reflects the *saved* plan, not unsaved wizard edits. Acceptable ("save to apply").
- **Async targets:** the loading guard must prevent showing a half-loaded (spend-less) P&L as final.
- **`isPlanned` granularity:** a family partially planned (some products in snapshot, some not) — treat the family as planned and per-product-fallback the missing ones to runSim demand.
