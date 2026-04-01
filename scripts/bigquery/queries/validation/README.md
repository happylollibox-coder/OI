# Dashboard Validation Queries

BigQuery validation queries for gap analysis between the OI dashboard and Amazon Ads Console / source data.

**Reference**: [docs/DASHBOARD_QUERIES_FOR_GAP_ANALYSIS.md](../../../docs/DASHBOARD_QUERIES_FOR_GAP_ANALYSIS.md)

## Queries

| Query | Dashboard source | Purpose |
|-------|------------------|---------|
| `VALIDATE_ADS_PORTFOLIO_LEVEL.sql` | ads_7d.json | Portfolio-level spend/sales/orders for Amazon comparison |
| `VALIDATE_SUMMARY_7D.sql` | summary.json | Home/Family KPIs (7-day period) |
| `VALIDATE_ACTIONS.sql` | actions.json | Action recommendations table |
| `VALIDATE_KEYWORD_PRODUCT_MAP.sql` | keyword_product_map.json | Keywords page, Family keyword table |
| `VALIDATE_SQP_WEEKLY.sql` | sqp_weekly.json | Family SQP keyword terms |
| `VALIDATE_EXPERIMENT_CAMPAIGNS.sql` | experiment_campaigns.json | Experiment page campaigns |
| `VALIDATE_DRIVERS.sql` | drivers.json | Family DriverTable (top performers) |

## Usage

1. **Run a query** (replace date literals if needed):
   ```bash
   bq query --use_legacy_sql=false < scripts/bigquery/queries/validation/VALIDATE_ADS_PORTFOLIO_LEVEL.sql
   ```

2. **Compare to dashboard**:
   - Run `cd dashboard && python3 refresh_data.py` to refresh JSON
   - Compare query output to `dashboard/data/*.json`

3. **Compare to Amazon Ads Console**:
   - Use same date range in Amazon (e.g. Feb 22–28 2026)
   - Portfolio view: Impressions, Clicks, CTR, Total cost, CPC, Purchases, Sales, ROAS

## Gap Analysis Checklist

- [ ] **Date range**: Align exactly (dashboard uses `MAX(date)-6` for summary; use explicit dates for validation)
- [ ] **Portfolio mapping**: campaign_history → V_SRC_AmazonAds_portfolio temporal join
- [ ] **Attribution**: row_asin = COALESCE(most_advertised_asin_impressions, most_advertised_asin_clicks, most_advertised_asin_purchased, first advertised_asins)
- [ ] **ROAS**: Dashboard = (Sales - Cost)/Cost (Net ROAS); Amazon = Sales/Cost
- [ ] **Row filtering**: Exclude cost=0 AND clicks=0 AND orders=0; terms need HAVING SUM(cost) >= 1
