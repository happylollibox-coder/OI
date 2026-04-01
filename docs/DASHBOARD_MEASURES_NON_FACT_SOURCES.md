# Dashboard Measures: Non-FACT Table Sources

Dashboard measures that are **NOT** taken from tables starting with `FACT_`.

---

## Summary

| Dashboard Data | Cube Schema | DB Source (non-FACT) | Measures Affected |
|----------------|-------------|---------------------|-------------------|
| **summary** | Summary | FACT_AMAZON_PERFORMANCE_DAILY, FACT_AMAZON_ADS, DIM_PRODUCT | ✅ Now uses FACT (updated) |
| **actions** | ExperimentTermRecommendations | V_EXPERIMENT_TERM_RECOMMENDATIONS | All (search_term, spend, orders, action, etc.) |
| **change_log** | ChangeLog | DIM_EXPERIMENT_CHANGE_LOG | All |
| **upcoming** | Holidays | DIM_US_HOLIDAYS | All |
| **peak** | Holidays | DIM_US_HOLIDAYS | All |
| **products** | Product, CostsHistory | DIM_PRODUCT, DIM_COSTS_HISTORY | asin, product_short_name, product_type, cogs, shipping, fba |
| **hero_asins** | ParentHeroAsin | V_PARENT_HERO_ASIN | All |
| **keyword_product_map** | ExperimentTermRecommendations | V_EXPERIMENT_TERM_RECOMMENDATIONS | All |
| **learnings** | ExperimentLearnings | V_EXPERIMENT_LEARNINGS | All |
| **experiments** | Experiment | DIM_EXPERIMENT | All |
| **budget_health** | ExperimentBudgetHealth | V_EXPERIMENT_BUDGET_HEALTH | All |
| **drivers** | ExperimentTermRecommendations | V_EXPERIMENT_TERM_RECOMMENDATIONS | All |
| **experiment_campaigns** | ExperimentCampaign | DIM_EXPERIMENT_CAMPAIGN | All |
| **experiment_templates** | ExperimentTemplates | DIM_EXPERIMENT, DIM_EXPERIMENT_CAMPAIGN, V_EXPERIMENT_SUMMARY | All |

---

## Data Sources That ARE FACT (OK)

| Dashboard Data | DB Source |
|---------------|-----------|
| summary | FACT_AMAZON_PERFORMANCE_DAILY, FACT_AMAZON_ADS |
| ads_7d | FACT_AMAZON_ADS |
| sqp_weekly | FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY |
| weekly_trends | FACT_AMAZON_PERFORMANCE_DAILY, FACT_AMAZON_ADS |
| monthly_trends | FACT_AMAZON_PERFORMANCE_DAILY, FACT_AMAZON_ADS |
| weekly_trends_by_asin | FACT_AMAZON_PERFORMANCE_DAILY, FACT_AMAZON_ADS |
| monthly_trends_by_asin | FACT_AMAZON_PERFORMANCE_DAILY, FACT_AMAZON_ADS |
| data_freshness | FACT_AMAZON_ADS, FACT_AMAZON_PERFORMANCE_DAILY |
| experiment_weekly | FACT_EXPERIMENT_DAILY |
| sqp_volume_4w | FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY |
| campaign_search_terms | FACT_AMAZON_ADS |

---

## Priority: Measures That Should Use FACT

### 1. **Summary** (sales_7d, cogs_7d, orders_7d, organic_pct, etc.) ✅ DONE

**Now:** FACT_AMAZON_PERFORMANCE_DAILY + FACT_AMAZON_ADS (same as WeeklyTrends)

### 2. **Actions, Drivers, Keyword Product Map**

**Current:** V_EXPERIMENT_TERM_RECOMMENDATIONS  
**Possible FACT:** FACT_EXPERIMENT_RECOMMENDATIONS (if it exists and has the same grain)

Check if FACT_EXPERIMENT_RECOMMENDATIONS can replace V_EXPERIMENT_TERM_RECOMMENDATIONS.

### 3. **Change Log**

**Current:** DIM_EXPERIMENT_CHANGE_LOG  
**Note:** Change logs are typically dimension/audit data. DIM_ may be correct unless there is a FACT_EXPERIMENT_CHANGE_LOG.

### 4. **Upcoming, Peak**

**Current:** DIM_US_HOLIDAYS  
**Note:** Holiday/calendar data is dimension data. DIM_ is appropriate.

### 5. **Products**

**Current:** DIM_PRODUCT, DIM_COSTS_HISTORY  
**Note:** Product master and cost history are dimension/SCD data. DIM_ is appropriate unless costs are in a fact.

### 6. **Hero Asins**

**Current:** V_PARENT_HERO_ASIN  
**Note:** View; check if it is built from FACT tables.

### 7. **Learnings**

**Current:** V_EXPERIMENT_LEARNINGS  
**Note:** View; check if it aggregates from FACT_EXPERIMENT_DAILY or similar.

### 8. **Experiments**

**Current:** DIM_EXPERIMENT  
**Note:** Experiment metadata is dimension data. DIM_ is appropriate.

### 9. **Budget Health**

**Current:** V_EXPERIMENT_BUDGET_HEALTH  
**Note:** View; check if it uses FACT tables.

### 10. **Experiment Campaigns**

**Current:** DIM_EXPERIMENT_CAMPAIGN  
**Note:** Campaign metadata. DIM_ may be correct.

### 11. **Experiment Templates**

**Current:** DIM_EXPERIMENT, DIM_EXPERIMENT_CAMPAIGN, V_EXPERIMENT_SUMMARY  
**Note:** Mix of DIM and V_; V_EXPERIMENT_SUMMARY may aggregate from FACT.

---

## Recommendation

**High priority:** Update **Summary** to use FACT_AMAZON_PERFORMANCE_DAILY (same pattern as WeeklyTrends/MonthlyTrends).

**Medium priority:** Audit V_EXPERIMENT_TERM_RECOMMENDATIONS vs FACT_EXPERIMENT_RECOMMENDATIONS for actions/drivers/keyword_product_map.

**Low priority:** DIM_ and V_ for metadata (holidays, experiments, products, change log) may be acceptable if they are reference/lookup data rather than transactional measures.
