# Family ROAS Reference — blended & ad-only Net ROAS (LY/CY) for the coach

**Date:** 2026-05-26
**Components:** `cube/schema/UnifiedPerformance.js` (read-only — measures already exist), `dashboard-react/src/components/StepAdsPath.tsx` + `PlanWizard.tsx`, `dashboard-react/src/pages/PlanPage.tsx`, `data-entry-app/app.py`, `scripts/bigquery/tables/DE_PLAN_ADS_TARGETS*`, `config.yaml`
**Status:** Design — pending review

## Problem / use case

> "Save Ad Net ROAS and Net ROAS in the wizard per family per month (last year, current year). This assists the coach to understand if campaigns are in the right direction, and whether advertising is better done for this family."

The coach needs two historical signals per family-month, for **2025 (LY)** and **2026 (CY)**:
- **Net ROAS (blended)** = `(Revenue − COGS) / Ad Spend` — pays back per ad dollar *including* the organic halo.
- **Ad Net ROAS (ad-only)** = ad-attributed gross profit / Ad Spend — pays back *on its own*.

The **gap = the halo**. Blended healthy + ad-only weak → ads buy organic discovery (fund at family grain). Both weak → advertising isn't working for this family (pull back). **LY→CY** trend = direction. This reinforces the family-grain attribution rule already in the spec.

## Metric definitions (confirmed)

Per family, per calendar month, per year (2025, 2026):

```
blended NetROAS = (Σ sales − Σ cogs) / Σ adCost
adUnits         = Σ units − Σ organicUnits
ad-only NetROAS = blended NetROAS × (adUnits / Σ units)
```

`ad-only` scales the blended gross profit by the ad-driven unit share (uniform per-unit margin between a product's ad and organic units — reasonable; the only available alternative would need an ad-attributed-sales-$ Cube measure, which does not exist). When `adCost = 0` for a month → ROAS is `null` (not 0).

## Data (no new Cube/BigQuery object)

`UnifiedPerformance` already exposes `sales`, `cogs`, `adCost`, `units`, `organicUnits` (and a derived `netRoas`). The Plan page actuals fetch currently pulls `units/sales/cogs/adCost`; **add `organicUnits`** so ad-unit share is computable. Compute per family-month from the (already-loaded) monthly actuals for 2025 and 2026 — aggregate the family's products' sales/cogs/adCost/units/organicUnits per month, then apply the formulas.

## Persistence (freeze into the saved plan)

Add to **`DE_PLAN_ADS_TARGETS`** four nullable FLOAT columns, carried on each family-month row (duplicated across that month's channel rows — acceptable; they're a family-month attribute):

- `ly_net_roas`, `cy_net_roas` — blended, 2025 / 2026.
- `ly_ad_net_roas`, `cy_ad_net_roas` — ad-only, 2025 / 2026.

Backend changes:
- `data-entry-app/app.py`: extend `ADS_TARGETS_SCHEMA` (the four columns) and `api_ads_targets_save` to read+insert them.
- `scripts/bigquery/tables/DE_PLAN_ADS_TARGETS.sql` (+ a migration in `scripts/bigquery/migrations/` to `ALTER TABLE ADD COLUMN`).
- `config.yaml`: update the `DE_PLAN_ADS_TARGETS` object definition (CLAUDE.md rule 7).
- Snapshot at save time: the wizard computes the four values per family-month and sends them in the `adsTargets` payload; they freeze the historical ROAS as of plan creation.

## Wizard UI + compute

- **Compute** (in `StepAdsPath`/`PlanWizard`): per family-month, the four ROAS from 2025/2026 actuals (passed in as props — `actuals2025`/`actuals2026` are already available to the wizard).
- **Display** (Ads Path step): a compact per-month row/table showing **LY vs CY** for **blended** and **ad-only** Net ROAS, with the blended−ad-only gap visible (the halo). Read-only context for the planning decision.
- **Send**: include the four values per family-month in the `adsTargets` rows the wizard already emits to `/api/plans/ads-targets`.

## Coach consumption

Out of scope to *change coach logic* here. This spec only **persists + surfaces** the values. A follow-up wires the coach to read the four columns (it already reads `DE_PLAN_ADS_TARGETS`). Note the intended use: compare ad-only vs blended (halo) and LY→CY (direction) per family.

## Scope

**Changes:** add `organicUnits` to the actuals fetch; wizard computes + displays + sends the 4 ROAS; backend schema + save + DDL/migration + config.yaml.

**Keeps unchanged:** the profit-max engine, the order math, the tracking scorecard, the coach's decision logic.

**Out of scope:** an ad-attributed-sales-$ Cube measure (use the unit-share approximation); changing what the coach *does* with the values.

## Open questions / risks

- **Ad-only approximation** — uniform per-unit margin between ad and organic units. Confirm acceptable (vs adding an `adSales` Cube measure for exactness — bigger).
- **Channel-row duplication** — the family-month ROAS repeat across BRAND/NON_BRAND rows. Acceptable, or store once (needs a family-month row or a separate small table)?
- **Backend migration** — `ALTER TABLE DE_PLAN_ADS_TARGETS ADD COLUMN` ×4 (nullable, safe). Must be applied before the save endpoint writes them.
- **Task 7 of the tracking-scorecard plan is still open** (needs an approved plan to live-verify) — unrelated, but not yet closed.
