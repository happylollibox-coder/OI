# Two-Phase Launch Order (wizard Order step)

**Date:** 2026-06-07
**Component:** `dashboard-react/src/components/PlanWizard.tsx` (`StepOrder` + the order props it receives) · `dashboard-react/src/pages/PlanPage.tsx` (threads the per-product run-rate + launch flag, and saves only Phase 1)
**Status:** Design approved (all forks resolved), pending spec review
**Builds on:** Mechanism A (run-rate × shape forecast) and Mechanism B (server-side launch replenishment). This is the **client/wizard** side: when a user plans a just-launched family, the Order step should propose a phased launch buy, not one full-year order.

## Problem

Today the wizard's Order step (Step 5) gives every family a **single full order** (`allocateOrder` → per-product, rounded to cartons). For a **just-launched** family (e.g. Bunny — no last-year history, ~1–2 weeks of sales) that over-commits a year of inventory to an unproven SKU. A launch should be bought **in two phases**: a 90-day launch buy now, then the full rest-of-year restock a month later once the real run-rate is known.

## Decisions (locked)

1. **Applies only to just-launched families.** Everyone else keeps today's single-order step unchanged.
2. **Phase 1 — "Launch buy: 90 days"** (placed now, once the product has ≥3 selling days):
   per product = `earlyRunRate × 90` rounded up to whole cartons, minus available stock.
3. **Phase 2 — "Full restock to year-end"** (an *estimate*, placed/recalculated after ~1 month):
   per product = `rest-of-year forecast need − available stock − Phase 1 − on-order`, sized off the matured run-rate.
4. **Save behaviour:** saving the plan creates **only the Phase-1 PO**. Phase 2 is shown as a planned estimate flagged "place ~1 month · recalc on real sales" — **not** written as a PO now.
5. **Lead-time logic is informational** — Phase 1 covers ~Jun–Aug; Phase 2 ordered ~early July lands ~Sep for the Q4 ramp.

## Model

### Detection — `isLaunchFamily`
A family is just-launched when it has **no usable last-year history** but **does** have a current run-rate:
```
isLaunchFamily = (Σ familyMonthly2025[family] ≤ LAUNCH_FLOOR)   // no 2025 sales
             AND (Σ over products of runRateMap[name].unitsPerDay > 0)  // selling now
```
(Equivalent to Mechanism B's "first sale < 60 days"; `familyMonthly2025` and `runRateMap` are already in the wizard.) `LAUNCH_FLOOR` ≈ 5 units/year, mirroring `seasonalShape`'s floor.

### Phase 1 — 90-day launch buy (the saved order)
Per product `p` in `f.variations`:
```
earlyRate[p]   = runRateMap[p].unitsPerDay          // weighted run-rate = the early rate for a 1–2-week-old SKU
need90[p]      = earlyRate[p] × 90
avail[p]       = p.inventory                          // FBA + AWD + in-transit already in baseline
phase1[p]      = ceilToCarton(max(0, need90[p] − avail[p]), p.cartonQty)
```
`ceilToCarton(x, c) = c>0 ? ceil(x/c)*c : ceil(x)` (the existing carton-rounding rule; honour the `friendly` → next-100 toggle too). Phase-1 total = Σ `phase1[p]`. **This is what `allocateOrder`/the saved order becomes for a launch family** — i.e. `orderByProduct = phase1`.

### Phase 2 — rest-of-year restock (estimate, not saved)
Per product:
```
restOfYear[p]  = forecastByProduct[p]                 // per-product forward forecast (already passed to StepOrder)
onOrder[p]     = p.inventoryBySource['In Production'] + ['In Transit'] + ['MFR Ready']   // already-committed supply
phase2[p]      = ceilToCarton(max(0, restOfYear[p] − avail[p] − phase1[p] − onOrder[p]), p.cartonQty)
```
Phase-2 total = Σ `phase2[p]`. Displayed read-only with the "place ~1 month, recalc on real sales" note. Phase 2 nets out Phase 1 and stock, so the two phases never double-count.

### Wiring
- `StepOrder` gains props: `isLaunchFamily: boolean`, `runRatePerProduct: Record<string, number>` (units/day from `runRateMap`).
- PlanWizard computes `isLaunchFamily` + the per-product run-rate map and passes them; for a launch family the saved `orderByProduct` is the Phase-1 allocation (not the full gap).
- For a non-launch family `StepOrder` renders exactly as today.

## UI

For a launch family the Order step shows two stacked panels instead of the single target:
- **Phase 1 — Launch buy (90 days) · order now** — per-product table (qty, cartons, landed $), editable target like today; this is the saved order.
- **Phase 2 — Full restock to year-end · place ~1 month** (muted/estimate styling, a calendar/clock badge) — per-product estimate table, **read-only**, with the recalc note.
A one-line explainer: "New launch — buying in 2 phases: 90 days now, the rest once a month of real sales confirms the pace."

## Testing

- **Unit (`planTypes.ts`):** extract a pure `launchOrderPhases(variations, runRatePerProduct, forecastByProduct, friendly)` returning `{ phase1, phase2 }` per product. Tests: Phase 1 = `ceilCarton(rate×90 − stock)`; Phase 2 = `ceilCarton(restOfYear − stock − phase1 − onOrder)`; Phase 2 never negative; Phase 2 nets out Phase 1 (no double-count); rate 0 → Phase 1 0 (seed-PO case); carton + friendly rounding.
- **Live (Bunny):** Order step shows two phases — Phase 1 ≈ each product's ~1/day × 90 ≈ ~90/product (a carton or two), Phase 2 the rest-of-year remainder; established families (LolliME/Lollibox) still show the single order. Saving creates the Phase-1 quantities only.

## Scope

**Changes:** a pure `launchOrderPhases` builder + tests in `planTypes.ts`; `StepOrder` renders 2 phases for launch families (+ new props); PlanWizard computes `isLaunchFamily` + per-product run-rate and saves Phase 1 as the order.

**Keeps unchanged:** the order step for established families; `allocateOrder` (still used for non-launch + the per-product split shape); the Ads Path / forecast; Mechanism B (the server replenishment continues independently after Phase 1 ships).

**Out of scope:** auto-placing Phase 2 as a future-dated PO (it's an estimate); a server-side launch-order record; changing how non-launch orders work; reconciling the wizard Phase-1 PO with Mechanism B's suggestions (they target the same SKU but the dedup already deducts committed POs — verify, don't rebuild).

## Open questions / risks

- **`forecastByProduct` horizon** — confirm it's the *remaining-year* forward forecast (not full-year incl. elapsed); if it's full-year, subtract YTD so Phase 2 isn't overstated.
- **`onOrder` source** — `inventoryBySource` keys must match (`In Production` / `In Transit` / `MFR Ready`); if a key is absent it contributes 0 (safe).
- **Double-buy with Mechanism B** — after Phase 1 ships and the daily SP runs, the server may also suggest launch batches. The SP already deducts APPROVED/SCHEDULED committed qty, so the Phase-1 PO should be netted out — verify on Bunny after a save.
- **Early-rate noise** — a 1–2-week run-rate is volatile; Phase 1 is intentionally only 90 days (small) to bound the risk, and Phase 2 waits for a real month.
