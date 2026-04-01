# Dashboard Queries for Gap Analysis

This document lists all SQL queries needed per table per page for the OI dashboard. Use it to:
1. **Generate equivalent queries** in Amazon Ads / BigQuery for validation
2. **Compare dashboard output** vs Amazon (source of truth) for gap analysis
3. **Track changes** — when modifying dashboard logic, update this file and re-run gap analysis

**Data flow**: BigQuery (onyga-482313.OI) → `refresh_data.py` → `dashboard/data/*.json` → React dashboard

**Refresh command**: `cd dashboard && python3 refresh_data.py`

---

## Amazon vs Dashboard Metric Mapping

| Amazon (Ads Console) | Dashboard Label | Notes |
|---------------------|-----------------|-------|
| Total cost | Ads Spend | Same metric |
| Purchases | Ads Orders | Same metric |
| Sales | Ads Sales | Same metric |
| Clicks | Ads Clicks | Same metric |
| Impressions | Ads Impr | Same metric |
| CPC | Ads CPC | Same metric |
| ROAS | Ads ROAS | Amazon: Sales/Cost; Dashboard: (Sales - Cost)/Cost = Net ROAS |
| CTR | Ads CTR% | Same concept |

**Important**: Amazon uses **Portfolio** (BOX, ME, FRESH, BRAND, BOTTLE). Dashboard `ads_7d` gets `portfolio_name` from `V_SRC_AmazonAds_portfolio` via campaign_history. Date ranges may differ: dashboard uses rolling windows; Amazon uses explicit date picker.

---

## Page 1: Ads Performance (`ads`)

### Table: Hierarchy (Portfolio → Campaign → Search term)

| Field | Source | JSON | Query |
|-------|--------|------|-------|
| Hierarchy table | ads_7d | `ads_7d.json` | `QUERIES["ads_7d.json"]` in refresh_data.py |

**Measures**: Ads Spend, Ads Sales, Ads Orders, Ads Clicks, Ads Conv%, Ads CPC, Ads ROAS, Ads Terms

**Frontend logic**:
- Filters by `week_start` based on `periodMode` (day/week/month) and `specificPeriod`
- Aggregates by hierarchy level: portfolio → campaign → search_term (also family, product, day, week, month)
- Portfolio = `portfolio_name` from ads_7d
- Product labels from `product_short_name` (DIM_PRODUCT via row_asin)
- Best terms: min spend filter (default $3)
- Drainer terms: min spend filter (default $5)

**SQL query location**: `dashboard/refresh_data.py` lines 531–605

**Date range**: `a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 91 DAY)` (rolling 91 days)

**Amazon comparison**:
- Amazon: Portfolio view, date range Feb 22–28 2026, columns Impressions, Clicks, CTR, Total cost, CPC, Purchases, Sales, ROAS
- Dashboard: Same metrics but aggregated from FACT_AMAZON_ADS via campaign→portfolio join. **Gap risk**: portfolio_name temporal join (OI_start_date, OI_end_date), row_asin attribution (most_advertised_asin vs advertised_asins), date range alignment

---

### Table: Best Search Terms (HierarchicalTermsTable)

| Field | Source | JSON | Query |
|-------|--------|------|-------|
| Terms | ads_7d (row_type='search_term') | ads_7d.json | Same as above |
| SQP context | sqp_weekly | sqp_weekly.json | QUERIES["sqp_weekly.json"] |
| Product mapping | keyword_product_map | keyword_product_map.json | QUERIES["keyword_product_map.json"] |

---

### Table: Drainer Terms (TermsTable)

Same data source as Best Search Terms; different filter (drainer = low ROAS).

---

## Page 2: Home (`home`)

### Table: Family PnL (by product_type)

| Field | Source | JSON | Query |
|-------|--------|------|-------|
| Summary KPIs | summary | summary.json | QUERIES["summary.json"] |
| Monthly trends | monthly_trends | monthly_trends.json | QUERIES["monthly_trends.json"] |

**Measures**: Sales, COGS, Ads Spend, Net Profit, Ads ROAS, SQP Orders, SQP Clicks, Organic %

**SQL**: summary.json (lines 56–174), monthly_trends.json (lines 358–406)

**Date range**:
- summary: `biz_start` = MAX(date) - 6 days from V_SRC_sales_and_traffic
- monthly_trends: `DATE_SUB(CURRENT_DATE(), INTERVAL 1095 DAY)` (3 years)

---

### Chart: Trend (Sales, Ads Spend, Net Profit, Ads ROAS, Organic %)

| Field | Source | JSON | Query |
|-------|--------|------|-------|
| Weekly | weekly_trends | weekly_trends.json | QUERIES["weekly_trends.json"] |
| Monthly | monthly_trends | monthly_trends.json | QUERIES["monthly_trends.json"] |

**Date range**: weekly 84 days, monthly 1095 days

---

### Chart: Variation PnL (by ASIN)

| Field | Source | JSON | Query |
|-------|--------|------|-------|
| Weekly by ASIN | weekly_trends_by_asin | weekly_trends_by_asin.json | QUERIES["weekly_trends_by_asin.json"] |
| Monthly by ASIN | monthly_trends_by_asin | monthly_trends_by_asin.json | QUERIES["monthly_trends_by_asin.json"] |

---

### Table: Actions (recent)

| Field | Source | JSON | Query |
|-------|--------|------|-------|
| Actions | actions | actions.json | QUERIES["actions.json"] |

**Source**: V_EXPERIMENT_TERM_RECOMMENDATIONS (no date filter in query)

---

## Page 3: Actions (`actions`)

### Table: Action recommendations

| Field | Source | JSON | Query |
|-------|--------|------|-------|
| Rows | actions | actions.json | QUERIES["actions.json"] |

**Measures**: Ads Spend, Ads Orders, Ads Conv%, Ads CPC, Ads ROAS, SQP Mkt Vol

**SQL**: refresh_data.py lines 176–206

---

## Page 4: Family / SQP (`family`, `sqp`)

### KPIs (summary)

| Field | Source | JSON | Query |
|-------|--------|------|-------|
| Summary | summary | summary.json | QUERIES["summary.json"] |
| Monthly trends | monthly_trends | monthly_trends.json | QUERIES["monthly_trends.json"] |

---

### Table: Collections (with variations)

| Field | Source | JSON | Query |
|-------|--------|------|-------|
| Collection stats | Computed from monthly_trends, sqp_weekly | monthly_trends.json, sqp_weekly.json | monthly_trends, sqp_weekly |
| Variation rows | sqp_weekly aggregated by asin | sqp_weekly.json | QUERIES["sqp_weekly.json"] |

---

### Table: Keyword summary (Mkt Vol, Spend 60d, Ads Orders, Ads ROAS)

| Field | Source | JSON | Query |
|-------|--------|------|-------|
| keyword_product_map | keyword_product_map | keyword_product_map.json | QUERIES["keyword_product_map.json"] |

**SQL**: lines 288–308. Source: V_EXPERIMENT_TERM_RECOMMENDATIONS (60d window in view)

---

### Table: SQP keyword terms (SQP Orders, SQP Clicks, Ads Clicks, Ads Orders)

| Field | Source | JSON | Query |
|-------|--------|------|-------|
| sqp_weekly | sqp_weekly | sqp_weekly.json | QUERIES["sqp_weekly.json"] |

**SQL**: lines 468–516. Source: FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY

---

### Table: DriverTable (top performers)

| Field | Source | JSON | Query |
|-------|--------|------|-------|
| drivers | drivers | drivers.json | QUERIES["drivers.json"] |

**SQL**: lines 438–465. Source: V_EXPERIMENT_TERM_RECOMMENDATIONS

---

### Table: DrainTable (low ROAS)

Same as DriverTable; filtered by net_roas < 1.

---

### Chart: SQP trend (Orders, Show Rate, etc.)

| Field | Source | JSON | Query |
|-------|--------|------|-------|
| sqp_weekly | sqp_weekly | sqp_weekly.json | QUERIES["sqp_weekly.json"] |

---

## Page 5: Experiment (`experiment`)

### KPIs & Chart

| Field | Source | JSON | Query |
|-------|--------|------|-------|
| experiments | experiments | experiments.json | QUERIES["experiments.json"] |
| experiment_weekly | experiment_weekly | experiment_weekly.json | QUERIES["experiment_weekly.json"] |
| keyword_product_map | keyword_product_map | keyword_product_map.json | QUERIES["keyword_product_map.json"] |

**SQL**: experiments (424–428), experiment_weekly (467–506), keyword_product_map (288–308)

---

### Table: Keyword performance

| Field | Source | JSON | Query |
|-------|--------|------|-------|
| keyword_product_map (filtered by experiment_id) | keyword_product_map | keyword_product_map.json | Same |

---

### Table: Campaigns

| Field | Source | JSON | Query |
|-------|--------|------|-------|
| experiment_campaigns | experiment_campaigns | experiment_campaigns.json | QUERIES["experiment_campaigns.json"] |

**SQL**: lines 518–555. Source: DIM_EXPERIMENT_CAMPAIGN, FACT_AMAZON_ADS (90 days)

---

## Page 6: Keywords (`kwds`)

### Table: Keyword list

| Field | Source | JSON | Query |
|-------|--------|------|-------|
| keyword_product_map | keyword_product_map | keyword_product_map.json | QUERIES["keyword_product_map.json"] |

**Measures**: Ads Spend, Ads Orders, Ads Conv%, Ads ROAS, SQP Mkt Vol

---

## Page 7: Strategies (`strategies`)

### Tables & Charts

| Field | Source | JSON | Query |
|-------|--------|------|-------|
| experiment_templates | experiment_templates | experiment_templates.json | QUERIES["experiment_templates.json"] |
| experiment_weekly | experiment_weekly | experiment_weekly.json | QUERIES["experiment_weekly.json"] |
| experiment_campaigns | experiment_campaigns | experiment_campaigns.json | QUERIES["experiment_campaigns.json"] |
| campaign_search_terms | campaign_search_terms | campaign_search_terms.json | QUERIES["campaign_search_terms.json"] |
| keyword_product_map | keyword_product_map | keyword_product_map.json | QUERIES["keyword_product_map.json"] |

**SQL**: experiment_templates (607–649), campaign_search_terms (557–574)

---

## Page 8: Peak (`peak`)

### Tables

| Field | Source | JSON | Query |
|-------|--------|------|-------|
| peak | peak | peak.json | QUERIES["peak.json"] |
| summary | summary | summary.json | QUERIES["summary.json"] |
| experiments | experiments | experiments.json | QUERIES["experiments.json"] |
| experiment_campaigns | experiment_campaigns | experiment_campaigns.json | QUERIES["experiment_campaigns.json"] |
| campaign_search_terms | campaign_search_terms | campaign_search_terms.json | QUERIES["campaign_search_terms.json"] |
| keyword_product_map | keyword_product_map | keyword_product_map.json | QUERIES["keyword_product_map.json"] |
| drivers | drivers | drivers.json | QUERIES["drivers.json"] |
| sqp_weekly | sqp_weekly | sqp_weekly.json | QUERIES["sqp_weekly.json"] |

---

## Page 9: Learn (`learn`)

| Field | Source | JSON | Query |
|-------|--------|------|-------|
| learnings | learnings | learnings.json | QUERIES["learnings.json"] |

**SQL**: lines 418–422. Source: V_EXPERIMENT_LEARNINGS

---

## Page 10: Health (`health`)

| Field | Source | JSON | Query |
|-------|--------|------|-------|
| summary | summary | summary.json | QUERIES["summary.json"] |

---

## Query Index (refresh_data.py)

| JSON file | Query lines | Primary source |
|-----------|-------------|---------------|
| summary.json | 56–174 | V_SRC_sales_and_traffic, FACT_AMAZON_ADS, DIM_COSTS_HISTORY |
| actions.json | 176–206 | V_EXPERIMENT_TERM_RECOMMENDATIONS |
| upcoming.json | 208–225 | DIM_US_HOLIDAYS |
| peak.json | 227–261 | DIM_US_HOLIDAYS |
| products.json | 263–283 | DIM_PRODUCT, DIM_COSTS_HISTORY |
| hero_asins.json | 285–286 | V_PARENT_HERO_ASIN |
| keyword_product_map.json | 288–308 | V_EXPERIMENT_TERM_RECOMMENDATIONS |
| weekly_trends.json | 310–356 | V_SRC_sales_and_traffic, FACT_AMAZON_ADS |
| monthly_trends.json | 358–406 | Same |
| weekly_trends_by_asin.json | 408–416 | Same + ASIN |
| monthly_trends_by_asin.json | 418–466 | Same + ASIN |
| learnings.json | 468–472 | V_EXPERIMENT_LEARNINGS |
| experiments.json | 424–428 | V_EXPERIMENT_SUMMARY |
| budget_health.json | 430–434 | V_EXPERIMENT_BUDGET_HEALTH |
| drivers.json | 438–465 | V_EXPERIMENT_TERM_RECOMMENDATIONS |
| experiment_weekly.json | 467–506 | FACT_EXPERIMENT_DAILY |
| sqp_weekly.json | 468–516 | FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY |
| experiment_campaigns.json | 518–555 | DIM_EXPERIMENT_CAMPAIGN, FACT_AMAZON_ADS |
| campaign_search_terms.json | 557–574 | FACT_AMAZON_ADS |
| ads_7d.json | 531–605 | FACT_AMAZON_ADS, DIM_PRODUCT, campaign_history, portfolio |
| experiment_templates.json | 607–649 | DIM_EXPERIMENT, FACT_AMAZON_ADS |
| change_log.json | 651–659 | DIM_EXPERIMENT_CHANGE_LOG |
| negative_keywords.json | CSV | docs/LOLLIBOX_negative_keywords_by_campaign.csv |

---

## Gap Analysis Checklist

When comparing dashboard vs Amazon:

1. **Date range**: Align exactly. Dashboard summary uses `MAX(date)-6` to `MAX(date)` from V_SRC. Amazon uses explicit range (e.g. Feb 22–28 2026).
2. **Portfolio mapping**: Dashboard portfolio_name from campaign_history → V_SRC_AmazonAds_portfolio. Ensure campaign–portfolio assignment matches Amazon.
3. **Attribution**: Dashboard uses `most_advertised_asin_impressions` / `most_advertised_asin_clicks` / `most_advertised_asin_purchased` / first advertised_asins. Amazon may use different attribution.
4. **ROAS formula**: Dashboard = (Sales - Cost) / Cost. Amazon = Sales / Cost. Compare accordingly.
5. **Row filtering**: ads_7d excludes rows with cost=0 AND clicks=0 AND orders=0. Terms need `HAVING SUM(cost) >= 1`.
6. **Product join**: ads_7d INNER JOINs DIM_PRODUCT on row_asin. Rows with unknown ASINs are dropped.

---

## Validation Queries for SQL Agent

The SQL agent should create BigQuery/Amazon validation queries that mirror the dashboard. Key templates:

### 1. Portfolio-level (match Amazon Ads Console view)

**Purpose**: Validate Ads Performance hierarchy table at Portfolio level for a given date range.

**Expected output columns**: portfolio_name, spend, sales, orders, clicks, impressions, conv_rate, cpc, roas

**Logic**: Same as ads_7d.json but:
- Filter: `date BETWEEN @start_date AND @end_date` (use explicit dates, e.g. 2026-02-22 to 2026-02-28)
- Group by: portfolio_name only (aggregate all campaigns in portfolio)
- Join path: FACT_AMAZON_ADS → campaign_history → V_SRC_AmazonAds_portfolio
- Attribution: use same row_asin logic as ads_7d (COALESCE most_advertised_asin_impressions, etc.)
- Join DIM_PRODUCT on row_asin (INNER) to match dashboard

**Source query**: Extract and adapt from `dashboard/refresh_data.py` QUERIES["ads_7d.json"] (lines 531–605).

---

### 2. Summary 7d (match Home/Family KPIs)

**Purpose**: Validate summary.json for latest 7-day period.

**Expected output columns**: product_type, sales_7d, ad_cost_7d, orders_7d, ad_orders_7d, clicks_7d, net_roas, organic_pct

**Logic**: Use date_range from `MAX(date)` in V_SRC_sales_and_traffic_business_sku_report_daily; biz_start = MAX(date) - 6 days.

**Source query**: `dashboard/refresh_data.py` QUERIES["summary.json"] (lines 56–174).

---

### 3. Actions table

**Purpose**: Validate actions.json.

**Source**: V_EXPERIMENT_TERM_RECOMMENDATIONS. No date filter in current query.

**Source query**: `dashboard/refresh_data.py` QUERIES["actions.json"] (lines 176–206).

---

### 4. Keyword product map

**Purpose**: Validate keyword_product_map.json (Keywords page, Family keyword table).

**Source**: V_EXPERIMENT_TERM_RECOMMENDATIONS. 60d window in view.

**Source query**: `dashboard/refresh_data.py` QUERIES["keyword_product_map.json"] (lines 288–308).

---

### Extracting full SQL

Run `cd dashboard && python3 refresh_data.py --dry-run` to print all queries to stdout. Or read `dashboard/refresh_data.py` and copy from the `QUERIES` dict.

---

## Validation Queries (Created)

Validation SQL files live in `scripts/bigquery/queries/validation/`:

| File | Dashboard source | Purpose |
|------|------------------|---------|
| `VALIDATE_ADS_PORTFOLIO_LEVEL.sql` | ads_7d.json | Portfolio-level spend/sales/orders (match Amazon Ads Console) |
| `VALIDATE_SUMMARY_7D.sql` | summary.json | Home/Family KPIs (7-day period) |
| `VALIDATE_ACTIONS.sql` | actions.json | Action recommendations |
| `VALIDATE_KEYWORD_PRODUCT_MAP.sql` | keyword_product_map.json | Keywords page, Family keyword table |
| `VALIDATE_SQP_WEEKLY.sql` | sqp_weekly.json | Family SQP keyword terms |
| `VALIDATE_EXPERIMENT_CAMPAIGNS.sql` | experiment_campaigns.json | Experiment page campaigns |
| `VALIDATE_DRIVERS.sql` | drivers.json | Family DriverTable (top performers) |

**Run**: `bq query --use_legacy_sql=false < scripts/bigquery/queries/validation/VALIDATE_ADS_PORTFOLIO_LEVEL.sql`

---

## Next Steps

1. **Gap analysis**: Run validation queries, compare to dashboard JSON output and Amazon Ads Console, document differences.
2. **Rule**: When changing dashboard queries or logic, update this file, update validation queries, and re-run gap analysis.
