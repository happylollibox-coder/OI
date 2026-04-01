# Dashboard Data Sources

When `VITE_CUBE_API_URL` is set, the dashboard uses Cube for most data and JSON only for fields Cube does not provide.

## Cube (BigQuery via Cube.js)

| Field | Cube schema |
|-------|-------------|
| summary | Summary |
| actions | Actions |
| upcoming | Upcoming |
| peak | Peak |
| products | Product |
| hero_asins | ParentHeroAsin |
| keyword_product_map | (from Product) |
| weekly_trends | WeeklyTrends |
| monthly_trends | MonthlyTrends |
| weekly_trends_by_asin | WeeklyTrendsByAsin |
| monthly_trends_by_asin | MonthlyTrendsByAsin |
| learnings | ExperimentLearnings |
| experiments | Experiment |
| budget_health | ExperimentBudgetHealth |
| drivers | Drivers |
| change_log | ChangeLog |
| experiment_weekly | ExperimentDaily |
| sqp_weekly | Sqp |
| sqp_volume_4w | Sqp |
| experiment_campaigns | ExperimentCampaign |
| campaign_search_terms | CampaignSearchTerm (via Ads) |
| ads_7d | Ads |
| experiment_templates | ExperimentTemplates |

## JSON (dashboard/data/)

| Field | Source |
|-------|--------|
| negative_keywords | CSV (LOLLIBOX_negative_keywords_by_campaign.csv) |
| _meta | refresh_data.py metadata |

Cube-backed JSON files are archived in `archive/dashboard-data/`; the dashboard does not use them.
