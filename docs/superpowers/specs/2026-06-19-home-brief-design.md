# Home Page Brief — Design Spec

**Date:** 2026-06-19
**Status:** Approved (design), implementing FE v1
**Owner:** Ori

## Goal

Add a high-level, plain-language **Brief** to the dashboard Home page that answers
"what should I notice this morning?" in as few words as possible, with the option to
drill into detail. Organized **per family (parent)** and **per product when relevant**.

## Shape (approved via brainstorm mockups)

- **Family is the main toggle** — a prominent segmented control at the top of the page:
  `All · <Family> · <Family> · …`. Each tab shows a health dot (red/amber/green/grey).
- **Date window lives inside** the selected family's card, as a secondary toggle:
  `Today · Ads` | `Yesterday` | `7 days` | `30 days`. The comparison label updates per mode.
- Each family view = **split layout**:
  - **Left — "What moved"**: one short plain-language read + a KPI delta strip
    (Sales / Net Profit / Net ROAS / Organic) + per-product breakdown listing only
    products that actually moved.
  - **Right — "Needs attention"**: OOS risk, pending coach actions, watch items.
- **"All" tab** = business overview: one-sentence headline + cross-cutting attention list.
- **plain ⇄ numbers** link per family = the "see detailed explanation" control
  (plain default; numbers reveals exact values/deltas).
- **Steady families** (no material change) stay in the toggle, greyed, sorted after movers.
  Within a family, products with no material change are not listed.

Placement: top of `HomePage`, above the existing `periodIncomplete` notice / headline /
`DashboardSummary` hero. It is a **separate control** from the page's existing
weeks/month/quarter/year `periodMode` — the Brief has its own day-window toggle and does
not touch `useFilters`.

## Data sources (all already in `DashboardData`)

| Need | Source | Grain |
|------|--------|-------|
| Family P&L (sales, ad_cost, cogs, net_profit, orders, units, clicks, sessions) | `daily_trends` (`product_type` = OI family) | daily, family |
| Per-product ads movement (spend, ads sales, ads orders, ROAS) | `ads_7d` (`Ads.date` daily, `parent_name`, `product_short_name`) — NOT `ads_7d_summary`, which is weekly-only | daily, product |
| Watermarks | `_meta.data_freshness.ads_max_date`, `performance_max_date` | day |
| OOS risk | `supply_chain` (days_of_coverage, velocity, next shipment), `asin_oos_days` | per ASIN |
| Pending coach actions | `actions` | per action |
| Family map (asin → parent_name) | `products` | — |
| Peak detection | `peak[0]` (pre_peak_start, peak_end) | — |

## Date windows & comparison baselines

`perf_max` = `performance_max_date` (last full/orders date, ~1-day lag).
`ads_max` = `ads_max_date`. `today` = system date.

1. **Today · Ads** — current = ads metrics for `today` (spend, ads sales, ads orders, ROAS).
   Baseline = trailing-7-day **per-day average** of the same ads metrics (`today-7 … today-1`).
   *Ads-only: no net profit / blended metrics (orders not in yet).*
2. **Yesterday** — current = `perf_max` day (full P&L from `daily_trends`, per-product ads
   from `ads_7d_summary`). Baseline = trailing-7-day per-day average (`perf_max-7 … perf_max-1`).
3. **7 days** — current = sum `perf_max-6 … perf_max`. Baseline = prior 7 days
   `perf_max-13 … perf_max-7` (sum vs sum). **Peak override** below.
4. **30 days** — current = sum `perf_max-29 … perf_max`. Baseline = prior 30 days. Peak override.

**Peak override (7d/30d):** if the current window overlaps the peak window
`[pre_peak_start, peak_end]`, compare to **last-year same relative dates** (window shifted
−364 days). Best-effort: only applied if LY daily rows exist for the family; otherwise fall
back to the prior-window baseline and set an `approx` note on the card.

## v1 approximations (phased — backend hardens later)

- **"Today > 20 hours updated"**: no hourly signal in the FE payload. v1 proxy = enable the
  `Today · Ads` tab only when `ads_max_date === today`; otherwise the tab is disabled with a
  tooltip ("today's ads data not in yet"). Backend phase will supply a true hours-updated flag.
- **Per-product net profit**: `daily_trends` is family-grain only. Per-product breakdown in v1
  shows **ads-derived movement** (spend / ads sales / ads orders / ROAS), labelled as such.
  Full per-product P&L is a backend-phase addition (per-ASIN daily view).
- **Organic %** (family): `daily_trends` has no organic field. Approximated as
  `(orders − ads_orders) / orders` using `ads_7d_summary` ads orders. Matches the platform's
  "organic units = total − ads-attributed units" definition.
- **Peak baseline**: best-effort as above; exact peak-baseline view is backend-phase.

## Signal rules (what the brief flags)

Per family per window, compute deltas vs baseline for: sales, net_profit, net_roas
(`(sales−cogs)/ad_cost`), organic_pct (approx), tacos (`ad_cost/sales`), np_per_unit.

**Material-change thresholds** (config constant `BRIEF_THRESHOLDS`, tunable):
- $/additive metrics: `|Δ%| ≥ 7%`
- Net ROAS: `|Δ| ≥ 0.2x` or `|Δ%| ≥ 7%`
- Organic %: `|Δ| ≥ 2pt`

A family is **steady** (greyed, no detail) if no tracked metric moved. A product is listed
only if a tracked ads metric moved.

**Flagged signals** (chosen in brainstorm):
- Net profit / margin shift (NP or NP/unit moved)
- Ad efficiency shift (Net ROAS / TACoS)
- Organic share shift
- OOS risk: product with `days_of_coverage ≤ 7` and no shipment arriving sooner; show
  "out in ~N days". Already stocking out if `asin_oos_days.oos_days_7d > 0`.
- Pending coach actions: `actions` filtered to the family (count + short label).

**Health dot** per family: red if any OOS risk; amber if margin/efficiency softening or
coach actions pending; green if net positive movement; grey if steady.

## Components (isolation)

- `src/homeBrief.ts` — **pure logic**: window resolution, baseline selection (incl. peak),
  per-family/per-product aggregation, delta + signal computation, narrative builders.
  No React. Inputs: slices of `DashboardData`. Output: a `BriefModel` (overview + per-family
  view objects). Unit-tested.
- `src/homeBrief.test.ts` — unit tests for window resolution, delta classification, signal
  detection, peak detection, organic approximation.
- `src/components/HomeBrief.tsx` — the wizard UI (family main toggle, inner date toggle,
  split read/attention, plain⇄numbers). Consumes `BriefModel`. No business logic.
- `HomePage.tsx` — mount `<HomeBrief data={data} onNav={onNav} />` at the top of the page.

## Backend phase (2026-06-19)

**#1 Per-ASIN daily P&L — DONE & verified.** No new BigQuery object needed: `UnifiedPerformance`
is already backed by `V_UNIFIED_DAILY` at `asin × date` with `netProfit` / `organic_units`.
Added a `daily_trends_by_asin` Cube loader (`loadDailyTrendsByAsinFromCube`, last 120d), wired it
through `datasetTypes` / `DATASET_LOADERS` / `CubeDataProvider` / `pageDatasets.home`, and switched
the brief to it as the single daily source (family rolled up from it). Per-product now shows **true
P&L** (sales + net profit); **organic %** is now real (`organic_units / units`), not the
`(orders − ad_orders)` proxy. Also wired `asin_oos_days` + `daily_trends_by_asin` into `home`'s
dataset set — fixes a latent gap where the brief only painted because idle-prefetch had warmed those.

**#2 Hours-freshness gate — DECIDED: keep the proxy.** `V_DATA_FRESHNESS` is date-grain only;
Ori chose to keep `ads_max_date === today` (no hour check). No code change. A true hours/sync
signal can be added later if the early-morning partial-day view becomes a problem.

**#3 Peak baseline — DONE: peak-anchor-relative.** `resolveWindow` now takes `lyShiftDays`;
`peakShiftDays(holidays, pk)` computes the gap between this year's and last year's peak anchor
(`peak_start`, fallback `holiday_date`) from `data.holidays`, sanity-clamped to ~1 year (330–400d),
falling back to 364 if unresolved. The by-asin fetch was widened to **400 days** so last year's peak
window is available during peak season. Only triggers when the window overlaps `[pre_peak_start, peak_end]`
(i.e. Q4), so it's inert off-season. Verified via unit tests (peak not active in June).

Trade-off noted: the 400-day per-ASIN daily fetch is heavier than the 30-day window strictly needs;
acceptable for the small catalog. A seasonal range or daily-by-asin pre-agg could optimize it later.

## Out of scope

- Mutating the existing page `periodMode` / filters.
- Export of the brief.
