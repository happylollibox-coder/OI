# Cube Fields → Page / Label Mapping

This document maps each Cube measure and dimension to the page(s) and UI label(s) where it is displayed. Use it to verify no duplicate measures exist and to trace data lineage.

---

## Ads Cube

| Cube Field | Data Key | Page | Label |
|------------|----------|------|-------|
| **Ads.spend** | `ads_7d[].spend` | Home | Ads Spend (KPI, Trend, Per Product Family) |
| **Ads.spend** | `ads_7d[].spend` | Ads Performance | Ads Spend (totals, table) |
| **Ads.spend** | `campaign_search_terms[].spend` | (internal aggregation) | — |
| **Ads.orders** | `ads_7d[].orders` | Home | Ads Orders |
| **Ads.orders** | `ads_7d[].orders` | Ads Performance | Ads Orders |
| **Ads.orders** | `campaign_search_terms[].orders` | (internal) | — |
| **Ads.clicks** | `ads_7d[].clicks` | Home | Clicks |
| **Ads.clicks** | `ads_7d[].clicks` | Ads Performance | Clicks |
| **Ads.clicks** | `campaign_search_terms[].clicks` | (internal) | — |
| **Ads.impressions** | `ads_7d[].impressions` | Home | (not shown as column) |
| **Ads.impressions** | `ads_7d[].impressions` | Ads Performance | Impressions |
| **Ads.impressions** | `campaign_search_terms[].impressions` | (internal) | — |
| **Ads.sales** | `ads_7d[].sales` | Ads Performance | Ads Sales |
| **Ads.cogs** | `ads_7d[].cogs` | Ads Performance | COGS |
| **Ads.grossProfit** | `ads_7d[].grossProfit` | Ads Performance | Gross Profit |
| **Ads.date** | `ads_7d[].date` | (filtering/aggregation) | — |
| **Ads.campaignId** | `ads_7d[].campaign_id` | Ads Performance | Campaign ID |
| **Ads.campaignName** | `ads_7d[].campaign_name` | Ads Performance | Campaign Name |
| **Ads.campaignType** | `ads_7d[].campaign_type` | Ads Performance | Campaign Type |
| **Ads.searchTerm** | `ads_7d[].search_term` | Ads Performance | Search Term |
| **Product.productShortName** | `ads_7d[].product_short_name` | Ads Performance | Product |

---

## Summary Cube

| Cube Field | Data Key | Page | Label |
|------------|----------|------|-------|
| **Summary.sales7d** | `summary[].sales_7d` | Home | SALES (KPI) |
| **Summary.adCost7d** | `summary[].ad_cost_7d` | Home | (not used for KPI; ads_7d used instead) |
| **Summary.cogs7d** | `summary[].cogs_7d` | Home | COGS (KPI sub, Per Product Family) |
| **Summary.netProfit7d** | `summary[].net_profit_7d` | Home | (computed: sl - cg - co) |
| **Summary.orders7d** | `summary[].orders_7d` | Home | Total Orders |
| **Summary.organicOrders7d** | `summary[].organic_orders_7d` | Home | Organic Orders |
| **Summary.adOrders7d** | `summary[].ad_orders_7d` | Home | Ads Orders |
| **Summary.clicks7d** | `summary[].clicks_7d` | Home | Clicks (KPI sub) |
| **Summary.sessions7d** | `summary[].sessions_7d` | Home | Sessions (KPI sub) |
| **Summary.netRoas** | `summary[].net_roas` | Home | NET ROAS (KPI) |
| **Summary.organicPct** | `summary[].organic_pct` | Home | ORGANIC % (KPI) |
| **Summary.salesPrev7d** | `summary[].sales_prev_7d` | Home | Sales vs Prev |
| **Summary.adCostPrev7d** | `summary[].ad_cost_prev_7d` | Home | (delta calc) |
| **Summary.cogsPrev7d** | `summary[].cogs_prev_7d` | Home | (delta calc) |
| **Summary.netProfitPrev7d** | `summary[].net_profit_prev_7d` | Home | (delta calc) |
| **Summary.ordersPrev7d** | `summary[].orders_prev_7d` | Home | (delta calc) |
| **Summary.organicOrdersPrev7d** | `summary[].organic_orders_prev_7d` | Home | (delta calc) |
| **Summary.netRoasPrev** | `summary[].net_roas_prev` | Home | (delta calc) |
| **Summary.organicPctPrev** | `summary[].organic_pct_prev` | Home | (delta calc) |
| **Summary.salesChangePct** | `summary[].sales_change_pct` | Home | Sales vs Prev |
| **Summary.costChangePct** | `summary[].cost_change_pct` | Home | (delta calc) |
| **Summary.periodStart** | `summary[].period_start` | Home | (date range) |
| **Summary.periodEnd** | `summary[].period_end` | Home | (date range) |
| **Summary.productType** | `summary[].product_type` | Home | Family |

---

## WeeklyTrends Cube

| Cube Field | Data Key | Page | Label |
|------------|----------|------|-------|
| **WeeklyTrends.sales** | `weekly_trends[].sales` | Home | Sales (Trend chart) |
| **WeeklyTrends.adCost** | `weekly_trends[].ad_cost` | Home | (replaced by ads_7d for Trend) |
| **WeeklyTrends.cogs** | `weekly_trends[].cogs` | Home | COGS (Trend chart) |
| **WeeklyTrends.netProfit** | `weekly_trends[].net_profit` | Home | Net Profit (Trend chart) |
| **WeeklyTrends.orders** | `weekly_trends[].orders` | Home | Orders (Trend chart) |
| **WeeklyTrends.clicks** | `weekly_trends[].clicks` | Home | Clicks (Trend chart) |
| **WeeklyTrends.sessions** | `weekly_trends[].sessions` | Home | Sessions (Trend chart) |
| **WeeklyTrends.netRoas** | `weekly_trends[].net_roas` | Home | Ads ROAS (Trend chart) |
| **WeeklyTrends.organicPct** | `weekly_trends[].organic_pct` | Home | Organic % (Trend chart) |
| **WeeklyTrends.productType** | `weekly_trends[].product_type` | Home | Family |
| **WeeklyTrends.weekStart** | `weekly_trends[].week_start` | Home | (x-axis) |

---

## MonthlyTrends Cube

| Cube Field | Data Key | Page | Label |
|------------|----------|------|-------|
| **MonthlyTrends.sales** | `monthly_trends[].sales` | Home | Sales (Trend chart) |
| **MonthlyTrends.adCost** | `monthly_trends[].ad_cost` | Home | (replaced by ads_7d for Trend) |
| **MonthlyTrends.cogs** | `monthly_trends[].cogs` | Home | COGS (Trend chart) |
| **MonthlyTrends.netProfit** | `monthly_trends[].net_profit` | Home | Net Profit (Trend chart) |
| **MonthlyTrends.orders** | `monthly_trends[].orders` | Home | Orders (Trend chart) |
| **MonthlyTrends.clicks** | `monthly_trends[].clicks` | Home | Clicks (Trend chart) |
| **MonthlyTrends.sessions** | `monthly_trends[].sessions` | Home | Sessions (Trend chart) |
| **MonthlyTrends.netRoas** | `monthly_trends[].net_roas` | Home | Ads ROAS (Trend chart) |
| **MonthlyTrends.organicPct** | `monthly_trends[].organic_pct` | Home | Organic % (Trend chart) |
| **MonthlyTrends.productType** | `monthly_trends[].product_type` | Home | Family |
| **MonthlyTrends.monthStart** | `monthly_trends[].month_start` | Home | (x-axis) |

---

## WeeklyTrendsByAsin Cube

| Cube Field | Data Key | Page | Label |
|------------|----------|------|-------|
| **WeeklyTrendsByAsin.sales** | `weekly_trends_by_asin[].sales` | Family | (drill-down) |
| **WeeklyTrendsByAsin.adCost** | `weekly_trends_by_asin[].ad_cost` | Family | (drill-down) |
| **WeeklyTrendsByAsin.cogs** | `weekly_trends_by_asin[].cogs` | Family | (drill-down) |
| **WeeklyTrendsByAsin.netProfit** | `weekly_trends_by_asin[].net_profit` | Family | (drill-down) |
| **WeeklyTrendsByAsin.orders** | `weekly_trends_by_asin[].orders` | Family | (drill-down) |
| **WeeklyTrendsByAsin.clicks** | `weekly_trends_by_asin[].clicks` | Family | (drill-down) |
| **WeeklyTrendsByAsin.sessions** | `weekly_trends_by_asin[].sessions` | Family | (drill-down) |
| **WeeklyTrendsByAsin.netRoas** | `weekly_trends_by_asin[].net_roas` | Family | (drill-down) |
| **WeeklyTrendsByAsin.organicPct** | `weekly_trends_by_asin[].organic_pct` | Family | (drill-down) |
| **WeeklyTrendsByAsin.productType** | `weekly_trends_by_asin[].product_type` | Family | Family |
| **WeeklyTrendsByAsin.asin** | `weekly_trends_by_asin[].asin` | Family | ASIN |
| **WeeklyTrendsByAsin.productShortName** | `weekly_trends_by_asin[].product_short_name` | Family | Product |
| **WeeklyTrendsByAsin.weekStart** | `weekly_trends_by_asin[].week_start` | Family | (x-axis) |

---

## MonthlyTrendsByAsin Cube

| Cube Field | Data Key | Page | Label |
|------------|----------|------|-------|
| **MonthlyTrendsByAsin.sales** | `monthly_trends_by_asin[].sales` | Family | (drill-down) |
| **MonthlyTrendsByAsin.adCost** | `monthly_trends_by_asin[].ad_cost` | Family | (drill-down) |
| **MonthlyTrendsByAsin.cogs** | `monthly_trends_by_asin[].cogs` | Family | (drill-down) |
| **MonthlyTrendsByAsin.netProfit** | `monthly_trends_by_asin[].net_profit` | Family | (drill-down) |
| **MonthlyTrendsByAsin.orders** | `monthly_trends_by_asin[].orders` | Family | (drill-down) |
| **MonthlyTrendsByAsin.clicks** | `monthly_trends_by_asin[].clicks` | Family | (drill-down) |
| **MonthlyTrendsByAsin.sessions** | `monthly_trends_by_asin[].sessions` | Family | (drill-down) |
| **MonthlyTrendsByAsin.netRoas** | `monthly_trends_by_asin[].net_roas` | Family | (drill-down) |
| **MonthlyTrendsByAsin.organicPct** | `monthly_trends_by_asin[].organic_pct` | Family | (drill-down) |
| **MonthlyTrendsByAsin.productType** | `monthly_trends_by_asin[].product_type` | Family | Family |
| **MonthlyTrendsByAsin.asin** | `monthly_trends_by_asin[].asin` | Family | ASIN |
| **MonthlyTrendsByAsin.productShortName** | `monthly_trends_by_asin[].product_short_name` | Family | Product |
| **MonthlyTrendsByAsin.monthStart** | `monthly_trends_by_asin[].month_start` | Family | (x-axis) |

---

## ExperimentTermRecommendations Cube

| Cube Field | Data Key | Page | Label |
|------------|----------|------|-------|
| **ExperimentTermRecommendations.adsSpend** | `actions[].spend` | Actions | Ads Spend |
| **ExperimentTermRecommendations.adsSpend** | `drivers[].spend` | Family (Drivers) | Ads Spend |
| **ExperimentTermRecommendations.adsSpend** | `keyword_product_map[].spend_60d` | Keywords | Ads Spend |
| **ExperimentTermRecommendations.adsOrders** | `actions[].orders` | Actions | Ads Orders |
| **ExperimentTermRecommendations.adsOrders** | `drivers[].orders` | Family | Ads Orders |
| **ExperimentTermRecommendations.adsOrders** | `keyword_product_map[].orders_60d` | Keywords | Ads Orders |
| **ExperimentTermRecommendations.adsClicks** | `actions[].clicks` | Actions | (Ads Clicks) |
| **ExperimentTermRecommendations.adsClicks** | `drivers[].clicks` | Family | Ads Clicks |
| **ExperimentTermRecommendations.adsClicks** | `keyword_product_map[].clicks_60d` | Keywords | Ads Clicks |
| **ExperimentTermRecommendations.adsImpressions** | `keyword_product_map[].impressions_60d` | Keywords | Ads Impr |
| **ExperimentTermRecommendations.cpc** | `actions[].cpc` | Actions | Ads CPC |
| **ExperimentTermRecommendations.cpc** | `drivers[].cpc` | Family | Ads CPC |
| **ExperimentTermRecommendations.cpc** | `keyword_product_map[].cpc_60d` | Keywords | Ads CPC |
| **ExperimentTermRecommendations.adsCvrPct** | `actions[].conv_rate` | Actions | Ads Conv% |
| **ExperimentTermRecommendations.adsCvrPct** | `drivers[].conv_rate` | Family | Ads Conv% |
| **ExperimentTermRecommendations.adsCvrPct** | `keyword_product_map[].conv_rate_60d` | Keywords | Ads Conv% |
| **ExperimentTermRecommendations.adsNetRoas** | `actions[].net_roas` | Actions | Ads ROAS |
| **ExperimentTermRecommendations.adsNetRoas** | `drivers[].net_roas` | Family | Ads ROAS |
| **ExperimentTermRecommendations.adsNetRoas** | `keyword_product_map[].net_roas_60d` | Keywords | Ads ROAS |
| **ExperimentTermRecommendations.yourOrdersSharePct** | `actions[].impression_share` | Actions | Ads Imp Share |
| **ExperimentTermRecommendations.yourOrdersSharePct** | `drivers[].impression_share` | Family | Imp Share |
| **ExperimentTermRecommendations.yourOrdersSharePct** | `keyword_product_map[].impression_share` | Keywords | Ads Imp Share |
| **ExperimentTermRecommendations.marketWeeklyOrders** | `actions[].market_volume` | Actions | SQP Mkt Vol |
| **ExperimentTermRecommendations.marketWeeklyOrders** | `keyword_product_map[].market_volume` | Keywords | SQP Mkt Vol |
| **ExperimentTermRecommendations.marginPerUnit** | `actions[].margin_per_unit` | Actions | Margin/Unit |
| **ExperimentTermRecommendations.marginPerUnit** | `drivers[].margin_per_unit` | Family | — |
| **ExperimentTermRecommendations.searchTerm** | `actions[].search_term` | Actions | Keyword |
| **ExperimentTermRecommendations.searchTerm** | `drivers[].search_term` | Family | Keyword |
| **ExperimentTermRecommendations.searchTerm** | `keyword_product_map[].search_term` | Keywords | Keyword |
| **ExperimentTermRecommendations.productShortName** | `actions[].product_short_name` | Actions | Product |
| **ExperimentTermRecommendations.productShortName** | `drivers[].product_short_name` | Family | Product |
| **ExperimentTermRecommendations.productShortName** | `keyword_product_map[].product_short_name` | Keywords | Product |
| **ExperimentTermRecommendations.action** | `actions[].action` | Actions | Action |
| **ExperimentTermRecommendations.action** | `drivers[].action` | Family | Action |
| **ExperimentTermRecommendations.action** | `keyword_product_map[].action` | Keywords | Action |
| **ExperimentTermRecommendations.experimentId** | `actions[].experiment_id` | Actions | Experiment |
| **ExperimentTermRecommendations.experimentId** | `drivers[].experiment_id` | Family | Experiment |
| **ExperimentTermRecommendations.experimentId** | `keyword_product_map[].experiment_id` | Keywords | Experiment |
| **ExperimentTermRecommendations.heroAsin** | `actions[].hero_asin` | Actions | — |
| **ExperimentTermRecommendations.heroAsin** | `keyword_product_map[].hero_asin` | Keywords | Hero |
| **ExperimentTermRecommendations.isHeroMatch** | `keyword_product_map[].is_hero_match` | Keywords | Match? |
| **ExperimentTermRecommendations.reason** | `actions[].reason` | Actions | — |
| **ExperimentTermRecommendations.reason** | `keyword_product_map[].reason` | Keywords | — |

---

## Sqp Cube

| Cube Field | Data Key | Page | Label |
|------------|----------|------|-------|
| **Sqp.impressions** | `sqp[].impressions` | Family | Impr |
| **Sqp.clicks** | `sqp[].clicks` | Family | SQP Clicks |
| **Sqp.orders** | `sqp[].orders` | Family | SQP Orders |
| **Sqp.cartAdds** | `sqp[].cart_adds` | Family | — |
| **Sqp.amazonImpressions** | `sqp[].amazon_impressions` | Family | — |
| **Sqp.amazonClicks** | `sqp[].amazon_clicks` | Family | — |
| **Sqp.amazonOrders** | `sqp[].amazon_orders` | Family | — |
| **Sqp.adsImpressions** | `sqp[].ads_impressions` | Family | — |
| **Sqp.adsClicks** | `sqp[].ads_clicks` | Family | — |
| **Sqp.adsOrders** | `sqp[].ads_orders` | Family | — |
| **Sqp.amazonImpressions** | `sqp_volume_4w` | Family | SQP Mkt Vol |
| **Sqp.searchQuery** | `sqp[].search_term` | Family | Keyword |
| **Sqp.reportingDate** | `sqp[].reporting_date` | Family | — |
| **Sqp.asin** | `sqp[].asin` | Family | ASIN |
| **Sqp.showRatePct** | `sqp[].show_rate_pct` | Family | Best Share |
| **Sqp.estimatedOrganicRank** | `sqp[].estimated_organic_rank` | Family | Best Page |
| **Sqp.organicRankZone** | `sqp[].organic_rank_zone` | Family | — |
| **Sqp.searchQueryScore** | `sqp[].search_query_score` | Family | — |
| **Product.productShortName** | `sqp[].product_short_name` | Family | Product |
| **Product.productType** | `sqp[].product_type` | Family | Family |

---

## ParentHeroAsin Cube

| Cube Field | Data Key | Page | Label |
|------------|----------|------|-------|
| **ParentHeroAsin.adsSpend** | `hero_asins[].ads_spend` | Family | Ads Spend |
| **ParentHeroAsin.adsOrders** | `hero_asins[].ads_orders` | Family | Ads Orders |
| **ParentHeroAsin.adsClicks** | `hero_asins[].ads_clicks` | Family | Ads Clicks |
| **ParentHeroAsin.adsNetRoas** | `hero_asins[].ads_net_roas` | Family | Ads ROAS |
| **ParentHeroAsin.sqpImpressions** | `hero_asins[].sqp_impressions` | Family | SQP Impr |
| **ParentHeroAsin.sqpClicks** | `hero_asins[].sqp_clicks` | Family | SQP Clicks |
| **ParentHeroAsin.sqpConversions** | `hero_asins[].sqp_conversions` | Family | SQP Conv |
| **ParentHeroAsin.sqpCtrPct** | `hero_asins[].sqp_ctr_pct` | Family | SQP CTR |
| **ParentHeroAsin.sqpCvrPct** | `hero_asins[].sqp_cvr_pct` | Family | SQP CVR |
| **ParentHeroAsin.marginPerUnit** | `hero_asins[].margin_per_unit` | Family | — |
| **ParentHeroAsin.asin** | `hero_asins[].asin` | Family | ASIN |
| **ParentHeroAsin.searchTerm** | `hero_asins[].search_term` | Family | Keyword |
| **ParentHeroAsin.productShortName** | `hero_asins[].product_short_name` | Family | Product |

---

## ExperimentTemplates Cube

| Cube Field | Data Key | Page | Label |
|------------|----------|------|-------|
| **ExperimentTemplates.totalSpend** | `experiment_templates[].total_spend` | Strategies | Ads Spend |
| **ExperimentTemplates.totalOrders** | `experiment_templates[].total_orders` | Strategies | Ads Orders |
| **ExperimentTemplates.totalClicks** | `experiment_templates[].total_clicks` | Strategies | — |
| **ExperimentTemplates.totalImpressions** | `experiment_templates[].total_impressions` | Strategies | — |
| **ExperimentTemplates.totalSales** | `experiment_templates[].total_sales` | Strategies | Sales |
| **ExperimentTemplates.netRoas** | `experiment_templates[].net_roas` | Strategies | Ads ROAS |
| **ExperimentTemplates.convRate** | `experiment_templates[].conv_rate` | Strategies | Ads Conv% |
| **ExperimentTemplates.cpc** | `experiment_templates[].cpc` | Strategies | Ads CPC |
| **ExperimentTemplates.uniqueSearchTerms** | `experiment_templates[].unique_search_terms` | Strategies | Terms |
| **ExperimentTemplates.experimentId** | `experiment_templates[].experiment_id` | Strategies | Experiment |
| **ExperimentTemplates.experimentName** | `experiment_templates[].experiment_name` | Strategies | Experiment |
| **ExperimentTemplates.strategyId** | `experiment_templates[].strategy_id` | Strategies | — |
| **ExperimentTemplates.daysRunning** | `experiment_templates[].days_running` | Strategies | Days |

---

## ExperimentDaily Cube

| Cube Field | Data Key | Page | Label |
|------------|----------|------|-------|
| **ExperimentDaily.performanceTotalSales** | `experiment_daily` (aggregated) | — | (internal) |
| **ExperimentDaily.adsAllCost** | `experiment_daily` (aggregated) | — | (internal) |
| **ExperimentDaily.performanceTotalOrders** | `experiment_daily` (aggregated) | — | (internal) |
| **ExperimentDaily.adsAllOrders** | `experiment_daily` (aggregated) | — | (internal) |
| **ExperimentDaily.performanceOrganicOrders** | `experiment_daily` (aggregated) | — | (internal) |
| **ExperimentDaily.performanceSessions** | `experiment_daily` (aggregated) | — | (internal) |

---

## Other Cubes (ChangeLog, Holidays, DataFreshness, CostsHistory, Product, Experiment, ExperimentBudgetHealth, ExperimentLearnings, ExperimentCampaign)

These cubes provide dimensions and metadata (dates, IDs, names, status, etc.) rather than displayed measures. They are used for filtering, joins, and internal logic.

---

## Duplicate Measures Summary

| Semantic Measure | Cube Source(s) | Page(s) | Notes |
|-----------------|---------------|---------|-------|
| **Ads Spend** | Ads.spend | Home, Ads Performance | Single source; used for KPI, Trend, Per Product Family, Ads table |
| **Ads Spend** | Summary.adCost7d | — | Not used for KPI; Home uses ads_7d |
| **Ads Spend** | WeeklyTrends.adCost, MonthlyTrends.adCost | — | Replaced by ads_7d for Trend chart |
| **Ads Spend** | ExperimentTermRecommendations.adsSpend | Actions, Family, Keywords | Different scope (60d, by term) |
| **Ads Spend** | ExperimentTemplates.totalSpend | Strategies | Per experiment |
| **Ads Spend** | ParentHeroAsin.adsSpend | Family (Hero table) | Per hero ASIN |
| **Sales** | Summary.sales7d | Home | KPI |
| **Sales** | WeeklyTrends.sales, MonthlyTrends.sales | Home | Trend chart |
| **Sales** | Ads.sales | Ads Performance | Ad-attributed only |
| **Net Profit** | Summary.netProfit7d | — | Computed as sl - cg - co on Home |
| **Net Profit** | WeeklyTrends.netProfit, MonthlyTrends.netProfit | Home | Trend (now uses ads_7d for ad_cost) |
| **Net ROAS** | Summary.netRoas | Home | KPI |
| **Net ROAS** | WeeklyTrends.netRoas, MonthlyTrends.netRoas | Home | Trend chart |
| **Net ROAS** | ExperimentTermRecommendations.adsNetRoas | Actions, Family, Keywords | Per term |
| **Net ROAS** | ExperimentTemplates.netRoas | Strategies | Per experiment |
| **Net ROAS** | ParentHeroAsin.adsNetRoas | Family | Per hero |

**Conclusion:** No true duplicates for the same scope. Different cubes serve different granularities (family vs term vs experiment vs ASIN). The only overlap that was intentionally consolidated: Home Ads Spend and Trend ad_cost now both use `Ads.spend` via `ads_7d`.
