# Family ROAS Reference — blended & ad-only Net ROAS (LY/CY) for the coach

**Date:** 2026-05-26
**Components:** `dashboard-react/src/components/StepAdsPath.tsx` + `PlanWizard.tsx`, `dashboard-react/src/pages/PlanPage.tsx`, `data-entry-app/app.py`, `scripts/bigquery/tables/DE_PLAN_ADS_TARGETS*` (+ migration), `config.yaml`. (Cube/views are read-only — sources already exist.)
**Status:** Design — pending review

## Problem / use case

> "Save Ad Net ROAS and Net ROAS in the wizard per family per month (last year, current year). This assists the coach to understand if campaigns are in the right direction, and whether advertising is better done for this family."

Two historical signals, per family, per month, for **2025 (LY)** and **2026 (CY)**:
- **Net ROAS (blended)** = `(Revenue − COGS) / Ad Spend` — pays back per ad dollar *including* the organic halo. **Family-month grain** (organic isn't channel-attributable).
- **Ad Net ROAS (ad-only)** = ad-attributed `(sales − COGS) / spend` — pays back *on its own*. **Family-month-CHANNEL grain** (BRAND / NON_BRAND).

Blended healthy + ad-only weak → ads buy organic discovery (fund at family grain). Both weak → advertising isn't working for this family. LY→CY = direction. Per-channel ad-only tells the coach *which* channel is (in)efficient.

## Data sources (no new BigQuery/Cube object)

- **Ad-only Net ROAS, per family-month-channel-year** — `AdsChannelEfficiency` (← `V_ADS_CHANNEL_EFFICIENCY`): dimensions `family`, `year` (`yr`), `month` (`mo`), `searchType` (BRAND/NON_BRAND), and a pre-computed `netRoas`. The view already classifies channel and computes net ROAS — **no client-side campaign classification, no approximation**. Also exposes `totalSpend`, `totalSales`, `totalUnits` per channel if needed. The wizard already loads this cube (`adsEfficiency`); extend the fetch to include **2025 and 2026** (confirm the current fetch isn't year-filtered to 2026 only).
- **Blended Net ROAS, per family-month-year** — `UnifiedPerformance` total `sales`, `cogs`, `adCost` (already loaded as monthly actuals for 2025 & 2026); blended = `(Σsales − Σcogs) / ΣadCost` over the family's products per month. `null` when `adCost = 0`.

## Persistence (freeze into the saved plan)

Add to **`DE_PLAN_ADS_TARGETS`** (rows are per plan × family × month × channel) four nullable FLOAT columns:

- `ly_ad_net_roas`, `cy_ad_net_roas` — **ad-only**, written **per channel** (the BRAND row gets brand's value, NON_BRAND row gets non-brand's), 2025 / 2026.
- `ly_net_roas`, `cy_net_roas` — **blended** (family-month), carried identically on both channel rows.

Backend:
- `data-entry-app/app.py`: extend `ADS_TARGETS_SCHEMA` (+4 columns) and `api_ads_targets_save` to read+insert them.
- `scripts/bigquery/tables/DE_PLAN_ADS_TARGETS.sql` + a migration in `scripts/bigquery/migrations/` (`ALTER TABLE ADD COLUMN` ×4, nullable — safe, run before the endpoint writes them).
- `config.yaml`: update the `DE_PLAN_ADS_TARGETS` entry (CLAUDE.md rule 7).
- The wizard computes the four values per family-month(-channel) and includes them in the `adsTargets` payload it already POSTs to `/api/plans/ads-targets`, freezing them at plan-save time.

## Wizard UI + compute

- **Compute** (`StepAdsPath`/`PlanWizard`): per family-month — blended LY/CY from the 2025/2026 actuals (already props); ad-only LY/CY per channel from `adsEfficiency` (both years).
- **Display** (Ads Path step): a compact per-month block showing **LY vs CY** for **blended** (family) and **ad-only** (BRAND, NON_BRAND), with the blended−ad-only gap (the halo) visible — read-only planning context.
- **Send**: include the four values in the per-channel `adsTargets` rows (ad-only per its channel; blended on both).

## Coach consumption

Out of scope to change coach logic. This spec **persists + surfaces** the values; the coach already reads `DE_PLAN_ADS_TARGETS`. Follow-up wires it to compare ad-only vs blended (halo) and LY→CY (direction) per family/channel.

## Scope

**Changes:** extend `adsEfficiency` fetch to 2025+2026; wizard computes/displays/sends the 4 ROAS; backend schema + save + DDL/migration + config.yaml.

**Keeps unchanged:** profit-max engine, order math, tracking scorecard, coach decision logic; no new Cube/view (both sources exist).

**Out of scope:** per-variation ROAS (family grain only); changing what the coach does with the values.

## Open questions / risks

- **`adsEfficiency` year coverage** — confirm the existing PlanPage fetch can return 2025 rows (the cube has a `year` dim); if it's filtered to 2026, widen it.
- **Backend migration** — `ALTER TABLE DE_PLAN_ADS_TARGETS ADD COLUMN` ×4; needs your go (touches BigQuery) and must precede the save write.
- **Blended duplicated across channel rows** — accepted (it's a family-month attribute).
- **Months with no ad spend** — ROAS `null` (LY especially for newer families).
- **Task 7 of the tracking-scorecard plan remains open** (needs an approved plan to live-verify) — unrelated, still pending.
