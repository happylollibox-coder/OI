# Correlation Analysis Plan: Organic vs Paid Search Performance

## Objective
Find correlations between `FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` (organic search) and `V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` (paid ads) to identify unique search terms that can improve organic sales per ASIN.

## Data Structure Overview

### FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY (Organic Search)
**Key Fields:**
- `Reporting_Date` (DATE) - Weekly reporting date
- `ASIN` (STRING) - Product identifier
- `Search_Query` (STRING) - Organic search query (nullable)
- `Search_Query_Score` (FLOAT64) - Relevance score
- `Impressions`, `Clicks`, `Cart_Adds`, `ORDERS` - Overall metrics
- `AMAZON_IMPRESSIONS`, `AMAZON_Clicks`, `AMAZON_Cart_Adds`, `AMAZON_ORDERS` - Amazon-specific metrics
- `ad_key`: `YYYYMMDD-ASIN-Search_Query`
- `factless_key`: `YYYYMMDD-ASIN`

### V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY (Paid Ads)
**Key Fields:**
- `week_end_date` (DATE) - Week end date from TimeDIM
- `asin` (STRING) - Product identifier
- `search_term` (STRING) - Paid search term
- `campaign_id`, `campaign_name`, `campaign_type`
- `inferred_sales_module` - Sales module classification
- `impressions`, `clicks`, `orders`, `units` - Paid ad metrics
- `ad_key`: `YYYYMMDD-asin-search_term`
- `factless_key`: `YYYYMMDD-asin`

## Key Questions to Answer

### 1. **Search Term Overlap Analysis**
- Which search terms appear in BOTH organic and paid?
- Which search terms are ONLY in paid (opportunity for organic growth)?
- Which search terms are ONLY in organic (potential to reduce paid spend)?

### 2. **Performance Correlation Metrics**
- **Conversion Rate Correlation**: Do search terms with high paid conversion rates also have high organic conversion rates?
- **Volume Correlation**: Do high-impression paid terms correlate with high organic impressions?
- **Efficiency Correlation**: Which paid terms have better ROI but lower organic performance (investment opportunity)?

### 3. **ASIN-Level Analysis**
- Which ASINs have the largest gap between paid and organic performance?
- Which ASINs show strong organic growth after paid investment?
- What's the optimal paid-to-organic ratio per ASIN?

### 4. **Search Term Uniqueness & Opportunity**
- **Unique Paid Terms**: Search terms that perform well in paid but have NO organic presence
- **High-Value Terms**: Paid terms with high orders/units but low organic orders
- **Efficiency Gaps**: Terms where organic conversion rate is higher than paid (reduce paid, boost organic)

## Required Information Before Analysis

### 1. **Date Alignment**
- ✅ **RESOLVED**: Both use weekly aggregation
- **Question**: Does `Reporting_Date` in FACT align with `week_end_date` in V_AMAZON_ADS?
  - **Action**: Need to verify if both use the same week definition (Sunday-starting weeks)

### 2. **Search Term Matching**
- **Question**: Are `Search_Query` (organic) and `search_term` (paid) normalized the same way?
  - Case sensitivity?
  - Whitespace handling?
  - Special character handling?
- **Action**: Need sample data to verify matching logic

### 3. **Metric Definitions**
- **Question**: Are `ORDERS` in FACT comparable to `orders` in V_AMAZON_ADS?
  - Attribution windows (30-day vs immediate)?
  - Order definition consistency?
- **Question**: What does `Search_Query_Score` represent? (relevance, ranking, etc.)

### 4. **Business Context**
- **Question**: What's the goal timeframe for organic growth?
- **Question**: What's the acceptable paid investment threshold?
- **Question**: Are there specific ASINs or product categories to prioritize?

### 5. **Data Quality**
- **Question**: What's the date range of available data?
- **Question**: Are there any known data quality issues?
- **Question**: What percentage of records have NULL `Search_Query` in FACT?

## Proposed Analysis Approach

### Phase 1: Data Exploration & Validation
```sql
-- 1. Date range and coverage check
-- 2. Search term normalization verification
-- 3. ASIN overlap analysis
-- 4. NULL value analysis
```

### Phase 2: Correlation Analysis
```sql
-- 1. Join on: week_end_date = Reporting_Date, ASIN = asin, Search_Query = search_term
-- 2. Calculate correlation metrics:
--    - Paid impressions vs Organic impressions
--    - Paid orders vs Organic orders
--    - Paid conversion rate vs Organic conversion rate
--    - Paid efficiency (orders/cost) vs Organic efficiency
```

### Phase 3: Opportunity Identification
```sql
-- 1. Find unique paid terms (no organic match)
-- 2. Calculate opportunity score:
--    - High paid orders + Low organic orders = High opportunity
--    - High paid conversion rate + Low organic presence = Investment target
-- 3. Rank by potential ROI
```

### Phase 4: ASIN-Level Insights
```sql
-- 1. Aggregate by ASIN
-- 2. Calculate paid-to-organic ratios
-- 3. Identify ASINs with highest growth potential
-- 4. Recommend search terms per ASIN
```

## Key Metrics to Calculate

### Correlation Metrics
1. **Pearson Correlation Coefficient** between:
   - Paid impressions vs Organic impressions (by search term)
   - Paid orders vs Organic orders (by search term)
   - Paid conversion rate vs Organic conversion rate

2. **Spearman Rank Correlation** for non-linear relationships

### Opportunity Metrics
1. **Opportunity Score** = (Paid Orders × Paid Conversion Rate) / (Organic Orders + 1)
   - Higher score = Better opportunity

2. **Efficiency Gap** = Organic Conversion Rate - Paid Conversion Rate
   - Positive = Organic is more efficient (reduce paid)
   - Negative = Paid is more efficient (increase organic)

3. **Market Share Gap** = (Paid Impressions / Total Impressions) - (Organic Impressions / Total Impressions)
   - Identifies terms where paid dominates but organic could grow

### Investment Priority Score
```
Priority Score = (
  (Paid Orders × 0.4) +
  (Paid Conversion Rate × 0.3) +
  (Organic Gap × 0.2) +
  (Search Term Uniqueness × 0.1)
)
```

## Expected Deliverables

1. **Correlation Report**: Statistical correlations between paid and organic metrics
2. **Opportunity Matrix**: Search terms ranked by investment potential
3. **ASIN Recommendations**: Top 10 ASINs with highest growth potential
4. **Search Term List**: Unique paid terms to target for organic growth
5. **SQL Queries**: Reusable queries for ongoing analysis

## Next Steps

1. **Verify date alignment** between Reporting_Date and week_end_date
2. **Sample data review** to understand search term normalization
3. **Business requirements confirmation** (priorities, thresholds, timeframes)
4. **Create initial correlation query** for validation
5. **Build opportunity scoring model**
