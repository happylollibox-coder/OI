# Planning & Forecast — End-to-End Flow (one pager)

_Last updated 2026-05-29. Grounded in `PlanPage.tsx`, `PlanWizard.tsx`, `StepAdsPath.tsx`, `planTypes.ts`, `app.py`._

```
══════════════════════════════════════════════════════════════════════════════════
 1. DATA  (BigQuery  →  Cube.js  →  PlanPage state)
──────────────────────────────────────────────────────────────────────────────────
 UnifiedPerformance        AdsChannelEfficiency     V_FORECAST_DEMAND / _ROAS   DIM_PRODUCT
  monthly  → actuals2025/26  per fam×yr×mo×channel    holiday demand + event       + inventory
  weekly   → actualsWeekly    netRoas, spend, clicks   ROAS/ad-spend                 snapshot
  units·sales·cogs·adCost     → channelEfficiency      → demandMap, forecastMap      → buildFamilyBaselines
  ·organicUnits·clicks                                                                  → families[]  (asp, cost,
                                                                                          stock, splitPct, carton)
══════════════════════════════════════════════════════════════════════════════════
 2. PLANNING WIZARD   (per family · 5 steps)            ← the human decision
──────────────────────────────────────────────────────────────────────────────────
 ① Baseline   stock + velocity (read-only)
 ② Growth     brand vs non-brand YoY  →  brandGrowth  (applied to every variation)
 ③ ADS PATH ▮ THE ENGINE ▮  2025-anchored profit-max
              units(S) = units₂₅ · (S/spend₂₅)^e      e = SEASON_E[season]
              S* = peak of net-profit curve;  user dials selectedK (× the plan)
              shows: 2025 → recommended (+Δ),  Net-ROAS ref (blended vs ad-only, LY→CY),
                     season CPC ceiling
              emits: profitMaxPlan → trajectory (units/mo)  +  adsTargets (spend/cpc/mo×channel)
 ④ Spend Plan monthly ramp preview (from trajectory)
 ⑤ Order      per-product gap = forecast − own stock, carton-rounded
              Auto  → family target split by each product's per-MONTH runSim share
              Manual→ you type each product's buy qty
══════════════════════════════════════════════════════════════════════════════════
 3. WIZARD OUTPUTS  (onSave)              ┌───────────── one selected spend point ─────────────┐
──────────────────────────────────────────│  drives BOTH inventory side AND coach side          │
 plannedMonthly                            └────────────────────────────────────────────────────┘
   per-product per-month forecast            orderOverrides[product]            adsTargets (enriched)
   = trajectory split by runSim share          Auto:  sold + forecast             per mo × channel:
   (seasonality counted ONCE)                  Manual: sold + stock + qty          daily_spend·cpc·max_cpc
        │                                            │                              predicted_units/profit/roas
        │                                            │                              + LY/CY net_roas (blended+ad-only)
        ▼                                            ▼                                      │
══════════════════════════════════════════════════════════════════════════════════════════│════
 4. PERSISTENCE                                                                              ▼
──────────────────────────────────────────────────────────────────────────────────────────────
 DE_PLAN_STRATEGY   ← buildPayloadRows:  mults/strategy/growth rows                  DE_PLAN_ADS_TARGETS
   order_overrides_json   (= orderOverrides)                                          ← POST /api/plans/
   snapshot_units_json    (per-product per-month = actual elapsed + forecast remain)    ads-targets
   (frozen → original_overrides_json at APPROVE)
══════════════════════════════════════════════════════════════════════════════════
 5. CONSUMERS
──────────────────────────────────────────────────────────────────────────────────
 (a) PLAN-PAGE FORECAST  ▮ the heart ▮
       rawProjs  = runSim(families, mults, forecastMap, demandMap, growth)      ← fallback engine
       projs     = buildEffectiveProjs(rawProjs, plannedUnits, plannedSpend, isPlanned)
                     planned family → units from snapshot · spend from coach targets · P&L rebuilt
                     unplanned       → runSim, flagged "est · not planned"
       → every number reads `projs`: NEED · Ad Spend · ROAS · YTD/EOY NP · OOS · PR Qty · Landed
                                       · monthly table · Buy Plan · Cashflow

 (b) PURCHASE ORDER         PR "Gap from Plan" = planned − sold − stock (carton-rounded)
       order_overrides_json → backend /fulfillment plan_qty → matched vs DE_PURCHASE_ORDERS

 (c) ADS COACH              reads DE_PLAN_ADS_TARGETS → executes the monthly spend/CPC schedule
                            (max_cpc cap; LY/CY blended-vs-ad-only ROAS = halo + direction signal)

 (d) PLAN-vs-REALITY  (approved only)   PlanVsRealityPanel
       period: Week / Month / Since-approval     measures: ad spend · CPC · units · net profit
       plan  = snapshot+targets prorated via monthFractions
       actual= weekly/monthly actuals            CPC actual = Σspend ÷ Σclicks (week tab)
══════════════════════════════════════════════════════════════════════════════════

 KEY INVARIANTS (what makes it consistent)
 • ONE spend decision (selectedK) feeds order + coach + forecast — no divergent engines.
 • Wizard families are wizard-sourced; only un-opened families fall back to runSim.
 • Seasonality lives in the family month total; per-product split is a dimensionless share → counted once.
 • Ad spend is FAMILY grain (per-variation ROAS is an attribution artifact / halo).
 • Order = per-PRODUCT gap (forecast − its own stock), never family-gap × demand share.
```

## Pure, unit-tested core (`planTypes.ts` — 33 tests)

| fn | does |
|---|---|
| `unitsAtSpend` / `profitMaxSpend` | the 2025-anchored profit-max math (Ads Path) |
| `splitTrajectoryToProducts` | family month total → per-product via per-month runSim share (no double-count) |
| `allocateOrder` | per-product gap → carton-rounded order |
| `buildEffectiveProjs` | substitute wizard plan into runSim projections |
| `composeMonthlyPlan` | actual(elapsed) + forecast(remaining) → snapshot |
| `monthFractions` / `sumOverPeriod` / `netProfitPlan` | period proration for tracking |
| `blendedNetRoas` | (Σsales−Σcogs)/ΣadCost |
| `latestCompleteWeekRange` | week resolver for the tracking tab |
```
```
