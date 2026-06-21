# SQP Page — Real SQP × Ads By-Search-Term Table

**Date:** 2026-06-21
**Branch:** feat/owned-negatives-coacher
**Status:** Design — pending review

## Problem

The SQP page (`FamilyPage` with `focus='sqp'`) has a "Search Terms" panel that is **not** sourced from SQP. It reads the Ads Coach term engine (`T_EXPERIMENT_TERM_RECOMMENDATIONS` via the `ExperimentTermRecommendations` cube → `data.keyword_product_map`). Consequences observed on Choice Bunny (B0GSKQ5TJ6):

- "SQP Mkt Vol" is wired to `market_weekly_orders` (market weekly **orders**, e.g. 42), not search volume.
- "Ads Imp Share" is wired to `your_orders_share_pct` (orders share) and rendered `* 100` too large (1.2% → 120%, full share → 10,000%).
- Only ad-targeted/coached terms appear, so the SQP head terms ("keychain" = 139,915 market impressions, "cute keychain" = 20,408) are absent.

This is a dedicated SQP page; the panel must show the **real** Search Query Performance funnel plus the real ads economics, per search term.

## Goal

Replace the data feeding the "Search Terms" panel with a unified **per-search-term** table that combines, for the filtered family/product and period:

- **SQP funnel:** your impressions, clicks, cart-adds, orders; market totals (`amazon_*`); ad volume (`ads_*`); true organic orders; impression share (`show_rate_pct`); estimated organic rank + zone.
- **Ads economics:** ad spend, ad sales, CPC, **net ROAS** (gross profit ÷ spend).

Rows = search **terms** (shopper queries), not ad keywords/targets.

## Locked Decisions

| Decision | Choice |
|---|---|
| Content | SQP funnel **+** full ads (spend, sales, CPC, net ROAS) |
| Row grain (family view) | One row per search query, **rolled up across the family's ASINs** |
| `amazon_*` market measures | **MAX** within `(term, week)` to dedupe identical per-week market figure |
| Multi-week "Market Volume" column | **Sum the weeks** (total market searches over the period) |
| ROAS | **Net ROAS** = `SUM(GROSS_PROFIT) / SUM(Ads_cost)` |
| Architecture | **Backend joined view** `V_SQP_ADS_BY_TERM` → `T_` → cube → frontend loader |
| Scope of UI change | Replace **only** the "Search Terms" panel data source; other panels untouched |

## Architecture

### 1. View `V_SQP_ADS_BY_TERM`

**Grain:** `(search_term, asin, week)`. Keep `asin`/`parent_name` so the page can filter by family and roll up client-side (a query such as "keychain" maps to many ASINs).

**SQP side:** `FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` — one row per `(ASIN, Search_Query, Reporting_Date)`. `Reporting_Date` is the week **end** (Sat; Sun–Sat weeks).

**Ads side:** `FACT_AMAZON_ADS` pre-aggregated to `(asin, search_term, week_end)`. This is the **single authority for all paid metrics** (the SQP fact's own `ADS_*` columns are NOT carried, to avoid two lineages of the same concept):
```
SUM(Ads_cost)     AS ad_spend
SUM(Ads_sales)    AS ad_sales
SUM(Ads_units)    AS ad_units
SUM(GROSS_PROFIT) AS ad_gross_profit   -- Sales − COGS, already in the table
SUM(Ads_clicks)   AS ad_clicks
SUM(Ads_orders)   AS ad_orders
SUM(Ads_impressions) AS ad_impressions
week_end = DATE_ADD(DATE_TRUNC(date, WEEK(SUNDAY)), INTERVAL 6 DAY)  -- align to SQP Reporting_Date
```

**Join:** `FULL OUTER JOIN` on `asin` + `LOWER(TRIM(Search_Query)) = LOWER(TRIM(search_term))` + week. FULL OUTER so terms with **ads-but-no-SQP** (long-tail paid) and **SQP-but-no-ads** (pure organic) both appear. `COALESCE` the keys (asin, search_term, week) and resolve `parent_name`/`product_short_name` via `DIM_PRODUCT`. On SQP-only rows the `ad_*` fields are 0; on ads-only rows the `amazon_*`/`show_rate_pct`/`estimated_organic_rank`/`organic_rank_zone` are NULL.

**Columns:** `reporting_date`, `week_start`, `asin`, `parent_name`, `product_short_name`, `search_term`, SQP-your-funnel (`impressions`, `clicks`, `cart_adds`, `orders`, `organic_orders`), market (`amazon_impressions`, `amazon_clicks`, `amazon_cart_adds`, `amazon_orders`), paid (`ad_impressions`, `ad_clicks`, `ad_orders`, `ad_units`, `ad_spend`, `ad_sales`, `ad_gross_profit`), SQP-derived (`show_rate_pct`, `estimated_organic_rank`, `organic_rank_zone`, `search_query_score`).

Register in `config.yaml`. SQL file: `scripts/bigquery/views/V_SQP_ADS_BY_TERM.sql`.

### 2. Materialize + cube

- `SP_REFRESH_CUBE_TABLES`: add `CREATE OR REPLACE TABLE T_SQP_ADS_BY_TERM AS SELECT * FROM V_SQP_ADS_BY_TERM;` (Cube reads `T_*`, not `V_*`).
- New cube `cube/schema/SqpAdsByTerm.js` over `T_SQP_ADS_BY_TERM`. Dimensions: `searchTerm`, `asin`, `parentName` (join `Product`), `productShortName`, `reportingDate` (time), `organicRankZone`, `estimatedOrganicRank`, `showRatePct`. Measures: sums of the funnel/ads/$ columns + `count`. The MAX-amazon rule is applied in the frontend rollup, so the cube exposes raw weekly rows.

### 3. Frontend (`dashboard-react`)

- New loader `loadSqpAdsByTermFromCube()` → `data.sqp_ads_by_term` (`SqpAdsByTermRow[]` in `types.ts`); register in the dataset registry and add to the SQP/family page's required dataset set (per-page on-demand loading). Window: `Last 104 weeks` (parity with `sqp_weekly`), filter by `parentName`.
- New `useMemo sqpTermTable`: filter rows by family (`parent_name`) / selected product / period weeks, then roll up per `LOWER(TRIM(search_term))`:
  1. **within (term, week):** `amazon_*` = MAX across ASINs; your/ads/$ = SUM.
  2. **across weeks:** SUM everything (incl. per-week amazon → period market volume).
  3. **derived** (from totals, never summed; every ratio guards divide-by-zero → `null`/`'--'`): `ctr = clicks/impr`, `cvr = orders/clicks`, `impr_share = your_impr/amazon_impr`, `cpc = ad_spend/ad_clicks`, `acos = ad_spend/ad_sales`, `net_roas = ad_gross_profit/ad_spend`, `est_rank` / `zone` = value from the **most recent week present** in the selected window.
- Replace the "Search Terms" panel (`FAMILY_KW_COLUMNS` / `kwGrouped` source) with `sqpTermTable`. Keep `kwGrouped` for other panels (Organic Keywords etc.). Preserve column selector, sort, search box, and row-expand (expansion = per-ASIN breakdown of the rolled-up term).

**Default columns:** `Keyword · Mkt Vol · Impr · Impr Share% · Clicks · CTR% · Cart Adds · Orders · CVR% · Organic Ord · Ad Spend · Ad Sales · CPC · Net ROAS · Est Rank · Zone`. Remaining (`Ad Clicks`, `Ad Orders`, `Ad Units`, `Search Query Score`, `Amazon Clicks/Orders`) available via the column selector.

## Data Flow

```
FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY ─┐
                                       ├─ V_SQP_ADS_BY_TERM ─ SP_REFRESH_CUBE_TABLES ─ T_SQP_ADS_BY_TERM
FACT_AMAZON_ADS (→ week, term) ────────┘                                                      │
                                                                              SqpAdsByTerm cube
                                                                                              │
                                                          loadSqpAdsByTermFromCube → data.sqp_ads_by_term
                                                                                              │
                                                          FamilyPage sqpTermTable rollup → "Search Terms" panel
```

## Edge Cases / Risks

- **Term matching:** SQP `Search_Query` vs ads `search_term` matched on `LOWER(TRIM())`. Residual mismatches surface as separate rows (acceptable; FULL OUTER preserves both).
- **Week alignment:** verify SQP weeks are Sun–Sat against `WEEK(SUNDAY)+6`; spot-check one ASIN/week before trusting the join.
- **Performance:** `(term, asin, week)` over 104 weeks is high-cardinality. Scope the loader by `parentName`; if payload is large, narrow the window or add a pre-aggregation later.
- **Timezone:** `FACT_AMAZON_ADS.date` is America/Los_Angeles; SQP `Reporting_Date` is a week label. Align on calendar week; document the assumption.
- **Freshness:** panel reflects the last `SP_REFRESH_CUBE_TABLES` run + 30-min cube cache, not the live view. SQP uploads are manual/weekly.
- **Cube cache bust (local):** touch `cube/schema/SqpAdsByTerm.js`.

## Out of Scope

- Fixing the existing coach panel's `* 100` bug (it's being replaced here).
- Backfilling SQP uploads.
- Halo/organic attribution beyond `ORGANIC_ORDERS` already in the SQP fact.

## Verification

- BQ: `V_SQP_ADS_BY_TERM` returns Choice Bunny rows with `amazon_impressions("keychain") ≈ 139,915`; ads-only and SQP-only terms both present.
- Cube: `/meta` lists `SqpAdsByTerm`; a `/load` returns rows for `parentName='Bunny'`.
- Dashboard: SQP page "Search Terms" panel shows real head terms with sane Impr Share (≤100%) and net ROAS; verified in browser via preview tools.
- Tests: unit test the `sqpTermTable` rollup (MAX-amazon within week, SUM across weeks, derived metrics) with a small fixture.

## Deployment

cube-api (new cube) + oi-dashboard (frontend) + BQ (view + SP) + `SP_REFRESH_CUBE_TABLES` run. Dashboard TS commits use `--no-verify` (pre-existing lint debt).
