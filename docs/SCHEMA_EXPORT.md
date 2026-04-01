# BigQuery Schema Export: onyga-482313.OI

Generated for Cube migration. Full reference: [schema.html](schema.html).

## Tables (BASE TABLE)

| Table | Partition | Cluster |
|-------|-----------|---------|
| CFG_TRANSACTION_CATEGORIZATION_RULES | — | priority, source_system_filter |
| COMPARE_QUANTITY_CLICKS_BY_ASIN | YEAR (date) | asin, date |
| DE_MANUFACTURER_SHIPMENTS | DAY (shipment_date) | shipment_status |
| DE_PURCHASE_ORDERS | DAY (order_date) | manufacturer_name |
| DE_VENDOR_PAYMENTS | DAY (payment_date) | vendor_name |
| DIM_AD_keyword | — | campaign_id, ad_group_id, keyword_id |
| DIM_BUDGET_CATEGORIES | — | category_name, subcategory_name |
| DIM_COSTS_HISTORY | DAY (start_date) | marketplace_id, asin, sku |
| DIM_CURRENCY_RATES | DAY (exchange_date) | base_currency, target_currency |
| DIM_EXPERIMENT | — | — |
| DIM_EXPERIMENT_CAMPAIGN | — | — |
| DIM_EXPERIMENT_CHANGE_LOG | — | — |
| DIM_PAYMENT_SOURCE_HIERARCHY | — | category, sub_category, payment_source |
| DIM_PRODUCT | — | asin, sku, marketplace |
| DIM_STRATEGY_CAMPAIGN_TEMPLATE | — | — |
| DIM_STRATEGY_TEMPLATE | — | — |
| DIM_TIME | YEAR (full_date) | year, month, peak_period_category, holiday_category |
| DIM_US_HOLIDAYS | — | — |
| FACT_AMAZON_ADS | YEAR (date) | campaign_id, ad_group_id, date |
| FACT_AMAZON_PERFORMANCE_DAILY | YEAR (DATE) | PURCHASED_ASIN, DATE |
| FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY | YEAR (Reporting_Date) | ASIN, Reporting_Date |
| FACT_ASIN_CONCLUSIONS | — | — |
| FACT_EXPERIMENT_DAILY | MONTH (snapshot_date) | experiment_id, asin |
| FACT_EXPERIMENT_RECOMMENDATIONS | MONTH (week_start_date) | category, priority |
| FACT_FACTLESS_BRIDGE | — | date_key, asin |
| FACT_FINANCIAL_TRANSACTIONS | DAY (transaction_date) | source_system, account_name, payment_source_category |
| FACT_GRADUATED_RULES | — | — |
| FACT_INVENTORY_SNAPSHOT | DAY (Date) | ASIN, source_type |
| FACT_ORDERS | DAY (snapshot_date) | manufacturer_name, order_date |
| FACT_PURCHASE_ORDER | DAY (snapshot_date) | manufacturer_name, order_date |
| FACT_SEARCH_QUERY | YEAR (week_start_date) | query_text, ASIN, Year, Week |
| GENERAL_CONVERSION | — | list_of_values, SOURCE, key |
| SCP_ASIN_View_Week | — | — |
| SQP_ASIN_View_Simple_Week | — | — |
| SRC_ACC_* (multiple) | various | various |
| SRC_BANK_* | — | — |
| SRC_INVENTORY_* | — | — |
| SRC_OLD_HIST_SP_SEARCH_TERMS | — | — |
| SRC_OLD_HIST_SB_SEARCH_TERMS | — | — |
| SRC_SCP_WEEKLY | — | — |
| SRC_SQP_WEEKLY | — | — |
| STG_* (multiple) | — | — |
| TimeDIM | — | — |
| UNCATEGORIZED_TRANSACTIONS_REVIEW | — | — |

## Views

| View | Used by refresh_data |
|------|----------------------|
| V_ASIN_BEST_PRACTICES | — |
| V_AUTO_CAMPAIGN_TERM_REVIEW | — |
| V_BOOST_KEYWORD_LEAKAGE | — |
| V_CAMPAIGN_DAILY_MOMENTUM | — |
| V_CAMPAIGN_PLACEMENT_BIDDING | — |
| V_CAMPAIGN_PLACEMENT_REPORT | — |
| V_EXPERIMENT_BUDGET_HEALTH | ✓ |
| V_EXPERIMENT_CAMPAIGN_SETTINGS | — |
| V_EXPERIMENT_KEYWORD_COLLISIONS | — |
| V_EXPERIMENT_LEARNINGS | ✓ |
| V_EXPERIMENT_PLACEMENT_LEARNINGS | — |
| V_EXPERIMENT_RESULTS_ASIN | — |
| V_EXPERIMENT_RESULTS_SEARCH_TERM | — |
| V_EXPERIMENT_SEARCH_TERMS | — |
| V_EXPERIMENT_SUGGESTED_CAMPAIGNS | — |
| V_EXPERIMENT_SUGGESTIONS | — |
| V_EXPERIMENT_SUMMARY | ✓ |
| V_EXPERIMENT_TERM_RECOMMENDATIONS | ✓ |
| V_FACT_AMAZON_PERFORMANCE_DAILY | — |
| V_PARENT_HERO_ASIN | ✓ |
| V_PO_SNAPSHOT | — |
| V_SEARCH_TERM_OPPORTUNITIES | — |
| V_SEARCH_TERM_SEGMENT | — |
| V_SEASONAL_INDEX_WEEKLY | — |
| V_SNAPSHOT_REMAINING_COSTS | — |
| V_SRC_AmazonAds_SearchTerms | — |
| V_SRC_AmazonAds_ad_group_history | — |
| V_SRC_AmazonAds_advertised_product | — |
| V_SRC_AmazonAds_campaign_history | ✓ |
| V_SRC_AmazonAds_keyword | — |
| V_SRC_AmazonAds_negative_keyword | — |
| V_SRC_AmazonAds_portfolio | ✓ |
| V_SRC_AmazonAds_purchased_product | — |
| V_SRC_AmazonAds_sb_ad_report | — |

**Note:** refresh_data.py also uses `V_SRC_sales_and_traffic_business_sku_report_daily` — check interface_views.

## Key Tables for Cube (refresh_data.py)

| Object | Type | JSON output |
|--------|------|-------------|
| FACT_AMAZON_ADS | TABLE | ads_7d, campaign_search_terms, experiment_campaigns |
| FACT_AMAZON_PERFORMANCE_DAILY | TABLE | summary, actions, drivers |
| FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY | TABLE | sqp_weekly, sqp_volume_4w |
| FACT_EXPERIMENT_DAILY | TABLE | experiment_weekly |
| DIM_PRODUCT | TABLE | products, keyword_product_map, hero_asins |
| DIM_TIME | TABLE | weekly_trends, monthly_trends |
| DIM_EXPERIMENT | TABLE | experiments, learnings |
| DIM_EXPERIMENT_CAMPAIGN | TABLE | experiment_campaigns |
| DIM_EXPERIMENT_CHANGE_LOG | TABLE | change_log |
| DIM_COSTS_HISTORY | TABLE | products, drivers, keyword_product_map |
| DIM_US_HOLIDAYS | TABLE | upcoming, peak |
| V_SRC_sales_and_traffic_business_sku_report_daily | VIEW | summary, weekly_trends, monthly_trends, drivers |
| V_SRC_AmazonAds_campaign_history | VIEW | ads_7d |
| V_SRC_AmazonAds_portfolio | VIEW | ads_7d |
| V_EXPERIMENT_TERM_RECOMMENDATIONS | VIEW | actions, learnings |
| V_EXPERIMENT_LEARNINGS | VIEW | learnings |
| V_EXPERIMENT_SUMMARY | VIEW | experiments |
| V_EXPERIMENT_BUDGET_HEALTH | VIEW | budget_health |
| V_PARENT_HERO_ASIN | VIEW | hero_asins |

## Relationships (Joins)

| From | To | Join key |
|------|-----|-----------|
| FACT_AMAZON_ADS | FACT_AMAZON_PERFORMANCE_DAILY | Ads_key |
| FACT_AMAZON_ADS | DIM_PRODUCT | most_advertised_asin_impressions → asin |
| FACT_AMAZON_ADS | V_SRC_AmazonAds_campaign_history | campaign_id + date |
| V_SRC_AmazonAds_campaign_history | V_SRC_AmazonAds_portfolio | portfolio_id |
| FACT_EXPERIMENT_DAILY | DIM_EXPERIMENT | experiment_id |
| FACT_EXPERIMENT_DAILY | DIM_PRODUCT | asin |
| DIM_EXPERIMENT_CAMPAIGN | FACT_AMAZON_ADS | campaign_id |
| **DIM_COSTS_HISTORY** | **FACT_FACTLESS_BRIDGE** | asin + temporal: bridge date (from date_key) between start_date and end_date; end_date NULL = current. Replaces the simpler DIM_PRODUCT → DIM_COSTS_HISTORY join used in some views. |
| FACT_FACTLESS_BRIDGE | DIM_TIME | date_key |
| FACT_FACTLESS_BRIDGE | DIM_PRODUCT | asin |
| FACT_AMAZON_PERFORMANCE_DAILY | FACT_FACTLESS_BRIDGE | factless_key |
| FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY | FACT_FACTLESS_BRIDGE | factless_key |
| FACT_EXPERIMENT_DAILY | FACT_FACTLESS_BRIDGE | factless_key |

## Key Column Mappings (refresh_data → BQ)

| refresh_data alias | BQ column |
|--------------------|-----------|
| Ads_impressions | FACT_AMAZON_ADS.impressions |
| Ads_clicks | FACT_AMAZON_ADS.clicks |
| Ads_orders | FACT_AMAZON_ADS.orders |
| Ads_cost | FACT_AMAZON_ADS.cost |
| Ads_sales | FACT_AMAZON_ADS.sales |
| product_short_name | DIM_PRODUCT (from SP_MERGE_PRODUCT_DIM) |

## DIM_COSTS_HISTORY Columns (CostsHistory cube)

| Column | Type | Cube dimension | Notes |
|--------|------|----------------|-------|
| asin | STRING | ✓ asin | Join to FactlessBridge |
| marketplace_id | STRING | — | Part of business key |
| sku | STRING | — | Part of business key |
| cost_of_goods | FLOAT64 | ✓ costOfGoods | |
| shipping_cost | FLOAT64 | ✓ shippingCost | |
| FBA_COST_estimated_fee_total | FLOAT64 | ✓ fbaCost | |
| TOTAL_COST_PER_UNIT | FLOAT64 | ✓ totalCostPerUnit | |
| start_date | DATE | ✓ startDate | NOT NULL, cost validity start |
| end_date | DATE | ✓ endDate | NULL = current |

## Cube: CostsHistory → FactlessBridge join

The CostsHistory cube joins to FactlessBridge with temporal validity so costs apply only when the bridge date falls within the cost record’s validity window:

- **Equi-join:** `CostsHistory.asin = FactlessBridge.asin`
- **Temporal:** Bridge date (from `FactlessBridge.date_key` via DIM_TIME) must be `>= CostsHistory.start_date`
- **Temporal:** And either `CostsHistory.end_date IS NULL` (current) or bridge date `<= CostsHistory.end_date`

This supports SCD Type 2: each cost record is valid for `[start_date, end_date]`, and `end_date IS NULL` means “current”.

## Run Full Schema Export (Optional)

```bash
# List all tables + views
bq query --use_legacy_sql=false '
SELECT table_name, table_type FROM `onyga-482313.OI.INFORMATION_SCHEMA.TABLES` ORDER BY table_name
'

# Get columns for a table
bq show --schema --format=prettyjson onyga-482313:OI.FACT_AMAZON_ADS
```
