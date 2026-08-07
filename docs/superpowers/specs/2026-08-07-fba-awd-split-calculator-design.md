# FBA / AWD Split Calculator — Design

**Date:** 2026-08-07
**Page:** Plan (`dashboard-react/src/pages/PlanPage.tsx`)
**Status:** Design approved, pending implementation plan

> **Amendment — 2026-08-07, after the first live batch.** Everything below that
> reads "FBA holds 100 DOC" is **wrong** and was implemented as written: on a real
> 12,000-unit batch it sent 11,760 units to FBA and 240 to AWD, putting the whole
> batch in the expensive warehouse through Q4.
>
> The 100 days describe the **combined FBA + AWD position**, not the FBA leg.
> Two levels, named apart in the engine as `fbaTargetDoc` and `totalTargetDoc`:
>
> - **FBA holds 45 days LIVE** (`FBA_TARGET_DOC`). The physical floor is 30 days —
>   AWD→FBA transit (14d) + FBA inbound buffer (10d) + up to 6d of Monday-only
>   ordering cadence — below which the reserve cannot arrive in time at all. 45 is
>   that floor plus margin for hot demand, slow receiving, and one missed transfer
>   cycle at the ~21-day merge cadence.
> - **FBA + AWD hold 100 days together** (`TOTAL_TARGET_DOC`); AWD holds the 55-day
>   balance cheaply, and transfers restore FBA to 45, not to 100.
>
> Read every "100 DOC" below as `totalTargetDoc`, and every "size the FBA leg to it"
> as `fbaTargetDoc`. Known gap this exposes: when AWD is **empty** at plan time, the
> reserve is 63d at sea + 24d transfer lead = 87 days from being sellable, so a
> 45-day FBA leg leaves a hole the old 100-day leg papered over. See
> `fbaAwdSplit.test.ts` → "the reserve cannot cover a cold start".

## Problem

When a batch of a product is ready at the manufacturer, there is no tool that answers:
how many cartons go to FBA and how many go to AWD, by which shipment method, arriving when.

The operating rule is that **FBA should always hold 100 days of cover (DOC)**. Today the Plan
page's Weekly Stock Projection pools FBA and AWD into a single stock line
(`PlanPage.tsx:731-738` sums both `sourceType` values into `stockMap`), so the 100-DOC-at-FBA
question cannot be read off any existing chart.

## Scope

A read-only what-if calculator. It writes nothing — no rows in `DE_SHIPMENT_PLAN`, no bulksheet,
no automated action. The user reads the recommendation and acts manually.

Explicitly out of scope for this iteration:

- Creating suggested shipment rows from the result.
- Excel export of the split.
- Multi-product batches. One product at a time.

If "create shipments" is wanted later, that is the moment to port the split arithmetic to SQL
(see Architecture).

## Inputs and outputs

**Input:** product, cartons ready for shipment.

Cartons prefill from manufacturer-ready units ÷ `package_quantity` (the `mfrReadyMap` already
built in `ReplenishmentFlowWrapper`) and are editable.

**Output:**

- Destination split — units and cartons to FBA, units and cartons to AWD.
- Shipment type per leg, with transit days, ship date, arrival date and sellable date.
- The AWD→FBA transfer schedule that holds FBA near 100 DOC as the AWD pool drains.
- A full ledger of every input that fed the calculation.
- A weekly simulation chart of FBA and AWD stock.

## Architecture

**Hybrid.** Policy inputs come from the backend; the split arithmetic is a pure TypeScript module.

Backend-sourced (unchanged, read-only):

| Value | Source |
|---|---|
| Transit days per method | `DE_LIST_OF_VALUES`, `lov_set = 'SHIPMENT_TYPE'` |
| FBA inbound buffer days | `DE_LIST_OF_VALUES`, `lov_set = 'Q4_PEAK'`, `value_id = 'FBA_INBOUND_BUFFER_DAYS'` |
| Monthly demand forecast | `V_FORECAST_DEMAND` via `demandMap` |
| Family peak-day weighting | `seasonMap` |
| Units per carton | `DIM_PRODUCT.package_quantity` |
| FBA / AWD / MFR-ready on hand | `InventorySnapshot` cube, latest snapshot date |

Current LOV values: `AIR` 10d, `FAST_SEA` 27d, `SLOW_SEA` 33d, `AWD_SLOW_SEA` 63d,
`AWD_TRANSFER` 14d; FBA inbound buffer 10d. These are read at runtime, never hardcoded.

### Why not pure backend

The project rule is that decision logic lives in BigQuery/Python, not React. That rule exists so
decisions the system *acts on* are reproducible. This calculator writes nothing and drives no
automation.

Two concrete costs to putting it in SQL: a BigQuery round-trip per keystroke on an interactive
what-if input, and a second implementation of the weekly-projection and forward-DOC math that
already lives in React today (`ShipmentEngine.tsx:1443-1605`). Forking that math is the larger
risk. The mitigation adopted here is to **extract** the existing math into a shared module rather
than write a parallel copy.

## Components

| File | Responsibility | Depends on |
|---|---|---|
| `src/stockProjection.ts` | `weeklyDemand()`, `buildWeeklyProjection()`, `forwardDoc()`. Extracted verbatim from `StockProjectionChart`. | Nothing (pure) |
| `src/fbaAwdSplit.ts` | `planSplit(input): SplitPlan`. The split, method selection and transfer schedule. | `stockProjection.ts` |
| `src/hooks/useInventorySnapshot.ts` | The `InventorySnapshot` cube query, lifted out of `ReplenishmentFlowWrapper`. | Cube |
| `src/components/FbaAwdSplitPanel.tsx` | UI: product picker, cartons input, ledger, decision rows, chart. | The three above |

`StockProjectionChart` is refactored to import `stockProjection.ts` instead of inlining the math.
Its rendered output must not change — see Testing.

`useInventorySnapshot` exists so the new panel and `ReplenishmentFlowWrapper` share one cube query
instead of firing the same query twice. It returns `fbaMap` and `awdMap` unmerged; the existing
merged `stockMap` is derived from them for backward compatibility.

**Placement:** inside the `isAdmin` block, immediately above the `Plan — Ads & Inventory Simulator`
header (`PlanPage.tsx:1804`).

## Algorithm

Ship dates snap to Wednesday, matching the plan's existing `ship_wednesday` convention.

Landed lead time = transit days + FBA inbound buffer. For FBA legs that is SLOW_SEA 43d,
FAST_SEA 37d. AWD legs use AWD_SLOW_SEA 63d with no FBA buffer, since goods are not sellable at
AWD; the buffer is applied later on the AWD→FBA transfer instead.

### 1. Units

`U = cartons × package_quantity`.

### 2. Select the FBA leg method

Project FBA-only stock forward — current FBA on hand, minus demand, plus confirmed FBA-bound
arrivals — and find the first date FBA reaches zero (`fbaOosDate`).

Take `SLOW_SEA` if it lands on or before `fbaOosDate`; otherwise escalate to `FAST_SEA`.
**AIR is never selected**, automatically or by override.

If `FAST_SEA` also lands after `fbaOosDate`, still select `FAST_SEA` but surface the unavoidable
OOS days rather than presenting it as a clean result.

The user can override the method via dropdown (SLOW_SEA / FAST_SEA only); the chart and schedule
recompute.

### 3. Size the FBA drop

At arrival date `A`, holding 100 DOC means holding exactly the demand of `[A, A + 100d)`, computed
off the peak-weighted daily curve — not a flat daily rate.

```
target      = Σ demand over [A, A + 100 days)
onHandAtA   = projected FBA stock at A (after depletion and confirmed FBA arrivals)
fbaSend     = clamp(target − onHandAtA, 0, U), floored to whole cartons
```

### 4. Remainder to AWD

`awdSend = U − fbaSend`, always via `AWD_SLOW_SEA`. Whole cartons by construction.

### 5. Hold the 100 DOC line

Pool = existing AWD on hand + `awdSend`, each tranche usable from its own arrival date.

Walk forward weekly. When FBA DOC is projected to fall below 100 within the transfer lead time
(14d transfer + 10d buffer = 24d), issue an AWD→FBA transfer sized to restore 100 DOC, capped by
pool available at the order date, floored to whole cartons.

Transfers whose arrivals fall within 14 days of each other are merged, so the schedule produces
roughly monthly moves rather than weekly dribble.

The walk stops when the pool is exhausted or the internal horizon ends.

**Known knob:** step 5 tops back up to exactly 100 DOC each time. The alternative is a band — let
DOC drift to ~75 before refilling — giving fewer, larger transfers. Starting with the straight 100
target as specified; the merge rule already prevents dribble.

## Definitions

**Confirmed shipment** — `status ∈ {transit, approved, scheduled}` (`ShipmentEngine.tsx:1486`).

Excluded from the projection:

- `suggested` — proposed by `SP_GENERATE_SHIPMENT_PLAN`, not approved. This is the `+Suggested`
  series on the existing chart.
- `po_needed`, `po` — PO completion means goods are at the manufacturer, not in a warehouse.

**Destination** — not a stored field. Derived from `route` containing `AWD`, the same way the
Excel export does it (`ShipmentEngine.tsx:2106`).

## Calculation ledger

A collapsible block listing every value that fed the result, each tagged with its source. This is a
requirement, not a nicety: a changed answer must be explainable by a changed input.

- **Product and conversion** — `package_quantity`, cartons entered, resulting units.
- **On hand** — FBA units and AWD units separately, plus the snapshot date.
- **Inbound shipments counted** — one row each: ship date, arrival date, qty, destination, status,
  transit type. Listed individually, never summed, because specific deliveries on specific dates
  drive the projection.
- **Inbound shipments excluded** — the same table, greyed, each with its reason (*suggested, not
  approved* / *PO, still at manufacturer*), so an omission is visible and arguable.
- **Demand** — monthly forecast units across the horizon, the growth override applied, and the
  family peak-day weighting per month.
- **Constants** — every transit and buffer value with its `DE_LIST_OF_VALUES` origin.

## Decision rows

Two rows for the batch — destination, units, cartons, shipment type, ship date, transit days,
arrival date, sellable date, resulting FBA DOC at arrival. Then one row per AWD→FBA transfer —
order date, arrival date, qty, DOC before and after.

Every row carries a one-line reason, for example:

- `SLOW_SEA lands Sep 19, FBA OOS Oct 19 — no escalation needed`
- `1,296 units = demand Sep 19–Dec 28 (100 DOC) minus 340 projected on hand`

## Chart

Same visual language as the existing Weekly Stock Projection — weekly buckets, toggleable legend —
tracking two pools instead of one:

- FBA sellable stock
- AWD reserve stock
- 100 DOC reference line
- Arrival markers for both new legs and each transfer
- OOS flag if one survives the plan

**Display window:** `today − 4 days` through `max(Dec 31 of current year, today + 100 days)`.
The later end wins; from roughly late September onward that is the 100-day arm.

**Bucket alignment:** the first bucket is the Monday on or before `today − 4 days`, keeping the
existing weekly convention.

**Internal horizon exceeds the display window.** Forward DOC at the last displayed week requires
100 days of demand beyond it, and transfers may be scheduled past year-end. The engine computes on
the longer horizon and the chart displays only the window. Without this, DOC would decay toward the
right edge as a pure artifact of running out of forecast.

## Edge cases

Each produces an explicit message, never a silent zero.

| Case | Behaviour |
|---|---|
| FBA already at or above 100 DOC | `fbaSend = 0`, entire batch to AWD, stated as such |
| Batch too small to reach 100 DOC | Everything to FBA, `awdSend = 0`, report units and days short |
| No demand forecast for the product | Refuse to compute, state the missing input |
| FAST_SEA still lands after OOS | Select FAST_SEA, report unavoidable OOS days |
| AWD pool not drained by horizon end | Report the leftover units |

## Testing

`fbaAwdSplit.test.ts` (vitest, matching the existing `pages/*.test.ts` pattern) — one case per edge
case above, plus the normal split, plus method escalation at the SLOW_SEA/FAST_SEA boundary, plus
transfer merging within the 14-day window.

`stockProjection.test.ts` — a **characterization test** asserting the extracted module reproduces
the current `StockProjectionChart` output for a fixed input, written and passing *before* any other
change. The extraction must not alter what the existing chart renders.

## Open questions

None blocking. Two assumptions to correct if wrong:

1. The panel is admin-only, matching the shipment engine around it.
2. The panel is weekly, not daily.
