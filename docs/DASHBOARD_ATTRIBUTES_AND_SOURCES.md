# Dashboard Attributes & Data Sources

## Data Flow Overview

```
BigQuery (onyga-482313.OI)  ──►  refresh_data.py  ──►  dashboard/data/*.json  ──►  useData()  ──►  React Dashboard
         │                              │
         │                              └── negative_keywords: CSV (docs/LOLLIBOX_negative_keywords_by_campaign.csv)
         │
         └── Python: google.cloud.bigquery.Client(project="onyga-482313")
                    Runs SQL queries, writes results to JSON files
```

**Connection**: The dashboard does **not** connect to BigQuery directly. It loads static JSON files from `/data/*.json`. These JSON files are produced by running `python3 refresh_data.py`, which executes BigQuery queries and writes the results to `dashboard/data/`.

---

## Attribute Fields by Data Source

*(Attributes = dimension/identifier fields, not measures like spend, orders, etc.)*

### 1. summary.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| product_type | DIM_PRODUCT (via family_map) | Derived: Lollibox, LolliME, Fresh, Bottle from product_short_name |
| period_start | date_range (from V_SRC_sales_and_traffic_business_sku_report_daily) | Min date of period |
| period_end | date_range | Max date of period |

**BigQuery sources**: DIM_PRODUCT, DIM_COSTS_HISTORY, V_SRC_sales_and_traffic_business_sku_report_daily, FACT_AMAZON_ADS

---

### 2. actions.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| search_term | V_EXPERIMENT_TERM_RECOMMENDATIONS | |
| product_short_name | V_EXPERIMENT_TERM_RECOMMENDATIONS | |
| hero_asin | V_EXPERIMENT_TERM_RECOMMENDATIONS | |
| experiment_id | V_EXPERIMENT_TERM_RECOMMENDATIONS | |
| strategy_id | V_EXPERIMENT_TERM_RECOMMENDATIONS | |
| action | V_EXPERIMENT_TERM_RECOMMENDATIONS | STOP, REDUCE_BID, PROMOTE_TO_EXACT, START, BOOST, etc. |
| ads_signal | V_EXPERIMENT_TERM_RECOMMENDATIONS | |
| reason | V_EXPERIMENT_TERM_RECOMMENDATIONS | |

**BigQuery source**: V_EXPERIMENT_TERM_RECOMMENDATIONS

---

### 3. upcoming.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| holiday_date | DIM_US_HOLIDAYS | |
| holiday_name | DIM_US_HOLIDAYS | |
| category | DIM_US_HOLIDAYS | |
| pre_season_start | DIM_US_HOLIDAYS | |
| status | Computed | ACTIVE, UPCOMING, PASSED |

**BigQuery source**: DIM_US_HOLIDAYS

---

### 4. peak.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| holiday_name | DIM_US_HOLIDAYS | |
| holiday_date | DIM_US_HOLIDAYS | |
| peak_start | DIM_US_HOLIDAYS | = pre_season_start |
| peak_end | Computed | holiday_date - 2 days |
| readiness_start | Computed | pre_season_start - 120 days |
| pre_peak_start | Computed | pre_season_start - 28 days |
| boost_start | Computed | pre_season_start - 14 days |
| current_stage | Computed | READINESS, PRE_PEAK, PRE_PEAK_BOOST, PEAK, POST_PEAK |
| category | DIM_US_HOLIDAYS | |

**BigQuery source**: DIM_US_HOLIDAYS

---

### 5. products.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| asin | DIM_PRODUCT | |
| product_short_name | DIM_PRODUCT | |
| product_type | DIM_PRODUCT | |
| product_name | DIM_PRODUCT | (in query, mapped to price etc.) |
| color | DIM_PRODUCT | |
| parent_asin | DIM_PRODUCT | |

**BigQuery sources**: DIM_PRODUCT, DIM_COSTS_HISTORY

---

### 6. hero_asins.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| asin | V_PARENT_HERO_ASIN | |
| search_term | V_PARENT_HERO_ASIN | |
| parent_name | V_PARENT_HERO_ASIN | |
| product_short_name | V_PARENT_HERO_ASIN, DIM_PRODUCT | |
| product_type | DIM_PRODUCT | |
| hero_rank | V_PARENT_HERO_ASIN | |

**BigQuery sources**: V_PARENT_HERO_ASIN, DIM_PRODUCT

---

### 7. keyword_product_map.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| search_term | V_EXPERIMENT_TERM_RECOMMENDATIONS | |
| experiment_id | V_EXPERIMENT_TERM_RECOMMENDATIONS | |
| product_short_name | V_EXPERIMENT_TERM_RECOMMENDATIONS | |
| hero_asin | V_EXPERIMENT_TERM_RECOMMENDATIONS | |
| is_hero_match | V_EXPERIMENT_TERM_RECOMMENDATIONS | |
| action | V_EXPERIMENT_TERM_RECOMMENDATIONS | |
| reason | V_EXPERIMENT_TERM_RECOMMENDATIONS | |

**BigQuery source**: V_EXPERIMENT_TERM_RECOMMENDATIONS

---

### 8. weekly_trends.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| product_type | DIM_PRODUCT (family_map) | Lollibox, LolliME, Fresh, Bottle |
| week_start | DIM_TIME.week_start_date | |

**BigQuery sources**: DIM_PRODUCT, DIM_COSTS_HISTORY, DIM_TIME, V_SRC_sales_and_traffic_business_sku_report_daily, FACT_AMAZON_ADS

---

### 9. monthly_trends.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| product_type | DIM_PRODUCT (family_map) | |
| month_start | DATE_TRUNC(date, MONTH) | |

**BigQuery sources**: Same as weekly_trends

---

### 10. weekly_trends_by_asin.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| product_type | DIM_PRODUCT (family_map) | |
| asin | V_SRC_sales_and_traffic_business_sku_report_daily.child_asin, FACT_AMAZON_ADS.most_advertised_asin_impressions | |
| product_short_name | DIM_PRODUCT | |
| week_start | DIM_TIME.week_start_date | |

**BigQuery sources**: Same as weekly_trends + ASIN granularity

---

### 11. monthly_trends_by_asin.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| product_type | DIM_PRODUCT (family_map) | |
| asin | Same as weekly_trends_by_asin | |
| product_short_name | DIM_PRODUCT | |
| month_start | DATE_TRUNC(date, MONTH) | |

---

### 12. learnings.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| learning_dimension | V_EXPERIMENT_LEARNINGS | Primary dimension (varies by row) |

**BigQuery source**: V_EXPERIMENT_LEARNINGS

---

### 13. experiments.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| experiment_id | V_EXPERIMENT_SUMMARY | |
| experiment_name | V_EXPERIMENT_SUMMARY | |
| strategy_id | V_EXPERIMENT_SUMMARY | |
| description | V_EXPERIMENT_SUMMARY | |
| status | V_EXPERIMENT_SUMMARY | |
| start_date | V_EXPERIMENT_SUMMARY | |
| end_date | V_EXPERIMENT_SUMMARY | |

**BigQuery source**: V_EXPERIMENT_SUMMARY

---

### 14. budget_health.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| experiment_id | V_EXPERIMENT_BUDGET_HEALTH | |

**BigQuery source**: V_EXPERIMENT_BUDGET_HEALTH

---

### 15. drivers.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| search_term | V_EXPERIMENT_TERM_RECOMMENDATIONS | |
| product_short_name | V_EXPERIMENT_TERM_RECOMMENDATIONS | |
| product_type | DIM_PRODUCT (derived from product_short_name) | Lollibox, LolliME, etc. |
| experiment_id | V_EXPERIMENT_TERM_RECOMMENDATIONS | |
| action | V_EXPERIMENT_TERM_RECOMMENDATIONS | |

**BigQuery sources**: V_EXPERIMENT_TERM_RECOMMENDATIONS, DIM_PRODUCT

---

### 16. change_log.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| change_id | DIM_EXPERIMENT_CHANGE_LOG | |
| experiment_id | DIM_EXPERIMENT_CHANGE_LOG | |
| change_date | DIM_EXPERIMENT_CHANGE_LOG | |
| change_type | DIM_EXPERIMENT_CHANGE_LOG | |
| campaign_id | DIM_EXPERIMENT_CHANGE_LOG | |
| field_changed | DIM_EXPERIMENT_CHANGE_LOG | |
| old_value | DIM_EXPERIMENT_CHANGE_LOG | |
| new_value | DIM_EXPERIMENT_CHANGE_LOG | |
| reason | DIM_EXPERIMENT_CHANGE_LOG | |
| source | DIM_EXPERIMENT_CHANGE_LOG | |
| created_at | DIM_EXPERIMENT_CHANGE_LOG | |

**BigQuery source**: DIM_EXPERIMENT_CHANGE_LOG

---

### 17. negative_keywords.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| campaign_name | CSV | **NOT BigQuery** – from docs/LOLLIBOX_negative_keywords_by_campaign.csv |
| negative_keyword | CSV | |

**Source**: Local CSV file (not BigQuery)

---

### 18. experiment_weekly.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| experiment_id | FACT_EXPERIMENT_DAILY, DIM_EXPERIMENT | |
| experiment_name | DIM_EXPERIMENT | |
| strategy_id | DIM_EXPERIMENT | |
| week_start | DATE_TRUNC(snapshot_date, WEEK) | |

**BigQuery sources**: FACT_EXPERIMENT_DAILY, DIM_EXPERIMENT

---

### 19. sqp_weekly.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| product_type | DIM_PRODUCT (family_map) | |
| asin | FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY.ASIN | |
| product_short_name | DIM_PRODUCT | |
| week_start | Reporting_Date - 6 days | |
| search_term | FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY.Search_Query | |
| organic_rank_zone | FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY | |

**BigQuery sources**: DIM_PRODUCT, FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY

---

### 20. experiment_campaigns.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| experiment_id | DIM_EXPERIMENT_CAMPAIGN | |
| campaign_id | DIM_EXPERIMENT_CAMPAIGN, FACT_AMAZON_ADS | |
| campaign_name | FACT_AMAZON_ADS | |
| campaign_type | FACT_AMAZON_ADS | |
| first_date | FACT_AMAZON_ADS (MIN date) | |
| last_date | FACT_AMAZON_ADS (MAX date) | |

**BigQuery sources**: DIM_EXPERIMENT_CAMPAIGN, FACT_AMAZON_ADS

---

### 21. campaign_search_terms.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| campaign_id | FACT_AMAZON_ADS | |
| search_term | FACT_AMAZON_ADS | |

**BigQuery source**: FACT_AMAZON_ADS

---

### 22. ads_7d.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| row_type | Computed | 'campaign' or 'search_term' |
| week_start | DATE_TRUNC(date, WEEK) | |
| campaign_id | FACT_AMAZON_ADS | |
| campaign_name | FACT_AMAZON_ADS | |
| campaign_type | FACT_AMAZON_ADS | |
| portfolio_name | V_SRC_AmazonAds_portfolio (via campaign_history) | |
| product_short_name | DIM_PRODUCT (via top_asin) | From most_advertised_asin |
| search_term | FACT_AMAZON_ADS | (search_term rows only) |

**BigQuery sources**: FACT_AMAZON_ADS, V_SRC_AmazonAds_campaign_history, V_SRC_AmazonAds_portfolio, DIM_PRODUCT

---

### 23. experiment_templates.json
| Attribute | DB Source | Notes |
|-----------|-----------|-------|
| strategy_id | DIM_EXPERIMENT | |
| experiment_id | DIM_EXPERIMENT | |
| experiment_name | DIM_EXPERIMENT | |
| description | DIM_EXPERIMENT | |
| status | DIM_EXPERIMENT | |
| start_date | DIM_EXPERIMENT | |
| end_date | DIM_EXPERIMENT | |
| lifecycle_stage | DIM_EXPERIMENT | |
| graduation_confidence | DIM_EXPERIMENT | |
| season_context | DIM_EXPERIMENT | |

**BigQuery sources**: DIM_EXPERIMENT, DIM_EXPERIMENT_CAMPAIGN, FACT_AMAZON_ADS

---

## Identical Attributes from Different Sources

| Attribute | Source A | Source B | Same? | Notes |
|-----------|----------|----------|-------|-------|
| **product_short_name** | DIM_PRODUCT | V_EXPERIMENT_TERM_RECOMMENDATIONS | Yes | V_EXPERIMENT_TERM_RECOMMENDATIONS joins to DIM_PRODUCT; can differ if view uses hero product |
| **product_type** | DIM_PRODUCT | Derived (family_map) | Yes | family_map derives Lollibox/LolliME/Fresh/Bottle from DIM_PRODUCT.product_short_name |
| **search_term** | FACT_AMAZON_ADS | V_EXPERIMENT_TERM_RECOMMENDATIONS | Same concept | Different tables; Ads vs experiment recommendations |
| **search_term** | FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY (Search_Query) | FACT_AMAZON_ADS | Same concept | SQP vs Ads; same search terms, different sources |
| **campaign_id** | FACT_AMAZON_ADS | DIM_EXPERIMENT_CAMPAIGN | Same | Campaign IDs from Amazon Ads |
| **campaign_name** | FACT_AMAZON_ADS | V_SRC_AmazonAds_campaign_history | Same | campaign_history has temporal versioning |
| **experiment_id** | DIM_EXPERIMENT | V_EXPERIMENT_* | Same | All from DIM_EXPERIMENT |
| **asin** | DIM_PRODUCT | FACT_AMAZON_ADS (most_advertised_asin) | Same | ASINs; ads uses advertised ASIN |
| **asin** | V_PARENT_HERO_ASIN | DIM_PRODUCT | Same | Hero ASINs are product ASINs |
| **week_start** | DIM_TIME.week_start_date | DATE_TRUNC(date, WEEK) | Same concept | Week boundaries; DIM_TIME vs computed |
| **portfolio_name** | V_SRC_AmazonAds_portfolio | — | Unique | Only in ads_7d (via campaign_history join) |

---

## BigQuery Objects Used (Summary)

| Object | Type | Used By |
|--------|------|---------|
| DIM_PRODUCT | Table | summary, products, hero_asins, trends, sqp_weekly, drivers, ads_7d |
| DIM_COSTS_HISTORY | Table | summary, products, trends |
| DIM_TIME | Table | weekly_trends, weekly_trends_by_asin |
| DIM_EXPERIMENT | Table | experiment_weekly, experiment_templates |
| DIM_EXPERIMENT_CAMPAIGN | Table | experiment_campaigns, experiment_templates |
| DIM_EXPERIMENT_CHANGE_LOG | Table | change_log |
| DIM_US_HOLIDAYS | Table | upcoming, peak |
| FACT_AMAZON_ADS | Table | summary, trends, experiment_campaigns, campaign_search_terms, ads_7d, experiment_templates |
| FACT_EXPERIMENT_DAILY | Table | experiment_weekly |
| FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY | Table | sqp_weekly |
| V_SRC_sales_and_traffic_business_sku_report_daily | View | summary, trends |
| V_EXPERIMENT_TERM_RECOMMENDATIONS | View | actions, keyword_product_map, drivers |
| V_EXPERIMENT_SUMMARY | View | experiments |
| V_EXPERIMENT_BUDGET_HEALTH | View | budget_health |
| V_EXPERIMENT_LEARNINGS | View | learnings |
| V_PARENT_HERO_ASIN | View | hero_asins |
| V_SRC_AmazonAds_campaign_history | View | ads_7d |
| V_SRC_AmazonAds_portfolio | View | ads_7d |

---

## Refresh Command

```bash
cd dashboard
python3 refresh_data.py
```

Runs all queries against `onyga-482313.OI`, writes JSON to `dashboard/data/`.
