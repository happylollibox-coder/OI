# Wizard-Sourced Monthly Plan + Approved-Plan-vs-Reality

**Date:** 2026-05-23
**Components:** `dashboard-react/src/components/StepAdsPath.tsx`, `PlanWizard.tsx`, `dashboard-react/src/pages/PlanPage.tsx`
**Status:** Design approved, pending implementation plan
**Builds on:** `2026-05-20-ads-path-profit-max-design.md` (the profit-max engine is unchanged)

## Problem

The Planning Wizard's Ads Path (Step 3) chooses a per-month ad-spend schedule and is the source of truth for everything downstream — the order and the coach. But the wizard only persists two disconnected things:

1. A per-product **order gap** written into `orderOverrides` (so the wizard's number collapses in the Plan-page PR table, which treats `orderOverrides[p]` as a yearly *planned total*, not a gap).
2. `adsTargets` → `DE_PLAN_ADS_TARGETS` (the coach's spend schedule), computed in a *second* place that can drift from the units the order uses.

Meanwhile the plan's frozen per-month demand snapshot (`snapshot_units_json`) is built from `runSim`, **not** from the wizard's ad-spend decision — so the plan-vs-reality comparison never reflects what the user actually chose in the Ads Path.

The user's intent: **the wizard should save actual + forecast per month → a yearly planned amount → and we always follow the approved plan vs reality (reality updated daily from actuals).**

## Decisions (from brainstorming)

- **Wizard is source of truth, per family.** A family run through the wizard contributes its per-product per-month numbers; families never opened keep their `runSim` baseline.
- **Deliverable:** data wiring **plus** a new always-on "Approved Plan vs Reality" panel (not just feeding the existing Compare toggle).
- **Persistence:** reuse the existing `snapshot_units_json` (Approach A) — no backend schema change.
- **Panel grain:** units **per product**; spend **per family** (see Model). Units/Spend toggle.
- **Order:** `orderOverrides[product]` becomes the **yearly planned total** (actual + forecast), not a gap. The wizard Order step's friendly-100 / manufacturer-`target` controls drop from the **binding** path — single source of truth. The binding order is the PR table's carton-rounded `planned − sold − stock`.

## Model

The Ads Path's selected spend point (`selectedK` → per-month spend `S[mo]`) is the single origin:

```
Ads Path selected spend  S[mo]
   │
   ├─ unitsAtSpend(S[mo]) → family units/month
   │     └─ split by per-product demand share (splitPct) → per-product per-month FORECAST
   │           └─ snapshot_units_json → yearly planned total → ORDER
   │
   └─ adsTargets/month (daily_spend, cpc, predicted_units, predicted_net_profit,
        predicted_roas, max_cpc) → DE_PLAN_ADS_TARGETS → the COACH
```

**Consistency guarantee:** a single per-month `{spend, units}` helper feeds *both* the snapshot forecast and `adsTargets.predicted_units`. Today `trajectoryMonths` and the `adsTargets` loop compute units separately and can disagree; they will be unified so the order, the units panel, and the coach all reflect the identical selected point.

### Per-product per-month series (the saved plan), built in `buildPayloadRows`

For each product, over the horizon (Jan'26 → Feb'27 per `getMonthsList`):

- **Elapsed months** (Jan → last complete month): **actual** units from `actuals2026Full` (daily-updated reality at save time).
- **Current month:** actual MTD + wizard forecast for the remainder (reuse the wizard's existing actual/forecast split).
- **Remaining months:** wizard **forecast** from the new `plannedMonthly` state.
- **Families not run through the wizard:** unchanged `runSim` snapshot.

Merged into `snapshotMap` → persisted as `snapshot_units_json` (already frozen at approval).

### Order derivation

`orderOverrides[product] = Σ months snapshot[product]` = yearly planned amount (actual + forecast).
PR table "Gap from Plan" = `planned − sold − stock` = `Σ remaining-forecast − stock`, carton-rounded by the existing `getPlanned`. Wizard, PR table, and saved plan now agree on one number. The backend `/fulfillment` `plan_qty` (which reads `order_overrides_json` raw) becomes the yearly planned total; fulfillment % is a known follow-up nuance, not in this round's scope (user orders against the PR table's Gap from Plan).

### Why spend is family-grain, not per-product

Per the 2026-05-20 spec: per-variation ad spend/ROAS is an attribution artifact (the hero variation's spend halos the listing). Ad decisions and ad-spend tracking stay at **family** grain where attribution washes out; **units** stay per-product where the order needs them.

## Approved-Plan-vs-Reality panel

New always-on panel on the Plan page, visible when `isApproved`. Units/Spend toggle:

- **Units (per product):** rows = variations, columns = months. Plan units (frozen `snapshot_units_json`) vs actual units (`actuals2026Full`). Elapsed months show actual-vs-plan with variance shading; future months show plan only until reality arrives.
- **Spend (per family):** rows = families, columns = months. Planned ad spend (Σ `adsTargets` daily_spend per family-month) vs actual ad spend (`actuals2026Full` adCost).

Reads existing in-memory data — no new fetch. The same planned-vs-actual spend computation is reusable on the coach page (thin fast-follow, not expanded scope here).

## Folded-in fixes (code this work touches)

- `trajectoryMonths` and the `adsTargets` loop currently iterate a hardcoded `for i < 12`; the horizon is ~10 months (→ Feb'27). Iterate the actual horizon so the per-month series and the **coach targets** stop emitting 2 phantom months (Mar/Apr'27).
- The current-month trajectory row ("✓ actual") will show real MTD actual + forecast remainder, consistent with the snapshot.

## Scope

**Changes:** wizard emits per-product per-month forecast → `plannedMonthly`; `buildPayloadRows` composes actual+forecast snapshot for wizard families; `orderOverrides[product]` = Σ snapshot; unify the `{spend,units}` helper; new panel; horizon-loop fix.

**Keeps unchanged:** the 2025-anchored profit-max engine (`profitMaxPlan`, `unitsAtSpend`, `profitMaxSpend`, season elasticities, `SEASON_MAX_CPC`); Step 2 brand/non-brand split; `runSim` as the baseline for un-opened families; the existing Compare toggle and `computeCompareStats` (now fed wizard-sourced snapshots).

**Out of scope:** coach `max_cpc` persistence to `DE_PLAN_ADS_TARGETS` (B1/B2); live per-family CPC ceilings (C); panel metrics beyond units + spend (profit/ROAS); reworking backend `/fulfillment` `plan_qty` semantics; per-week granularity.

## Open questions / risks

- **Friendly rounding dropped from binding path:** the wizard Order step becomes a preview mirroring `forecast − stock` (carton). If the user later wants a manufacturer round-number to persist, that needs a separate explicit order-quantity field (not folded into the yearly planned total).
- **Snapshot "actual" months vs frozen demand:** switching elapsed months to raw `actuals2026Full` units (vs the prior demand-projection) means past months in the plan equal reality by construction — intended for units tracking.
- **Family/product grain mix in the panel:** units (product) and spend (family) live in one toggle; care needed so totals reconcile per family.
