# Issue Analysis: Sales Discrepancy Jan 29, 2026

## Problem
- **Expected Total Sales**: $3,069 USD
- **Actual in FACT_AMAZON_PERFORMANCE_DAILY**: $3,614.6
- **Difference**: $545.6 (17.8% over)

## Root Cause Analysis

### Potential Issue #1: UNPIVOT + GROUP BY Logic

In `SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY`, the UNPIVOT creates multiple rows for the same ASIN:
- One row when ASIN is in `most_advertised_asin_impressions`
- One row when ASIN is in `most_advertised_asin_clicks`  
- One row when ASIN is in `most_advertised_asin_purchased`

Then it groups by:
```sql
GROUP BY 
  date, campaign_id, campaign_name, campaign_type, inferred_sales_module,
  ad_group_id, keyword_id, ad_keyword_status, targeting, search_term,
  placement_type, advertised_asins, advertised_asins_count, asin,
  _fivetran_synced, source_table
```

And uses `MAX()` for measures:
```sql
MAX(impressions) AS impressions,
MAX(clicks) AS clicks,
MAX(orders) AS orders,
MAX(units) AS units,
MAX(cost) AS cost,
MAX(sales) AS sales
```

**The Problem**: If the same ASIN appears in multiple source rows in `STG_AMAZON_ADS` with the same grouping key but different sales values, `MAX()` will take the maximum, not the sum. However, this should only happen if there are duplicate rows in STG_AMAZON_ADS.

### Potential Issue #2: Duplicate Records in STG_AMAZON_ADS

If `STG_AMAZON_ADS` has duplicate rows (same primary key: campaign_id, ad_group_id, keyword_id, date, search_term), then:
- Each duplicate gets UNPIVOTed separately
- They might group together if all grouping fields match
- `MAX()` would take the max sales value instead of summing

### Potential Issue #3: Organic Delta Calculation

The organic delta is calculated as:
```sql
GREATEST(0, perf.SALES_AMOUNT - COALESCE(ads.ads_sales, 0)) AS delta_amount
```

Where `ads.ads_sales` is aggregated as:
```sql
SUM(sales) AS ads_sales
```

If `ads.ads_sales` is under-counted (due to MAX() issue), then `organic_delta_sales` would be over-counted.

### Potential Issue #4: Currency Mismatch

If source data has multiple currencies and they're not being converted properly, this could cause discrepancies.

## Most Likely Issue

**Issue #1 or #2**: The UNPIVOT + GROUP BY with MAX() is likely the culprit. If the same ASIN appears in multiple rows in STG_AMAZON_ADS (possibly due to data quality issues or multiple source tables being UNIONed), and they have the same grouping key, MAX() will take the maximum value instead of summing them.

## Diagnostic Queries to Run

Run these queries in BigQuery to identify the exact issue:

### Query 1: Check for duplicates in STG_AMAZON_ADS
```sql
SELECT 
  date,
  campaign_id,
  ad_group_id,
  keyword_id,
  search_term,
  most_advertised_asin_purchased,
  COUNT(*) AS duplicate_count,
  SUM(sales) AS total_sales,
  MAX(sales) AS max_sales,
  SUM(sales) - MAX(sales) AS difference
FROM `onyga-482313.OI.STG_AMAZON_ADS`
WHERE date = '2026-01-29'
  AND most_advertised_asin_purchased IS NOT NULL
GROUP BY 
  date, campaign_id, ad_group_id, keyword_id, search_term, most_advertised_asin_purchased
HAVING COUNT(*) > 1
ORDER BY difference DESC;
```

### Query 2: Check UNPIVOT result before grouping
```sql
SELECT 
  date,
  campaign_id,
  ad_group_id,
  keyword_id,
  search_term,
  asin,
  measure_type,
  sales,
  COUNT(*) AS row_count
FROM (
  SELECT 
    date,
    campaign_id,
    ad_group_id,
    keyword_id,
    search_term,
    most_advertised_asin_purchased AS asin,
    'purchased' AS measure_type,
    sales
  FROM `onyga-482313.OI.STG_AMAZON_ADS`
  WHERE date = '2026-01-29'
    AND most_advertised_asin_purchased IS NOT NULL
)
GROUP BY date, campaign_id, ad_group_id, keyword_id, search_term, asin, measure_type, sales
HAVING COUNT(*) > 1;
```

### Query 3: Compare SUM vs MAX after grouping
```sql
WITH unpivoted AS (
  SELECT 
    date,
    campaign_id,
    ad_group_id,
    keyword_id,
    search_term,
    asin,
    sales
  FROM `onyga-482313.OI.STG_AMAZON_ADS`
  UNPIVOT (asin FOR measure_type IN (
    most_advertised_asin_purchased AS 'purchased'
  ))
  WHERE date = '2026-01-29'
    AND asin IS NOT NULL
    AND measure_type = 'purchased'
)
SELECT 
  date,
  campaign_id,
  ad_group_id,
  keyword_id,
  search_term,
  asin,
  COUNT(*) AS source_rows,
  SUM(sales) AS sum_sales,
  MAX(sales) AS max_sales,
  SUM(sales) - MAX(sales) AS difference
FROM unpivoted
GROUP BY date, campaign_id, ad_group_id, keyword_id, search_term, asin
HAVING COUNT(*) > 1
ORDER BY difference DESC;
```

## Recommended Fix

If the issue is MAX() vs SUM(), change the stored procedure to use SUM() instead of MAX() for sales:

```sql
-- Change from:
MAX(sales) AS sales,

-- To:
SUM(COALESCE(sales, 0)) AS sales,
```

However, this needs to be done carefully because:
- For impressions/clicks rows, sales is NULL (which is correct)
- For purchased rows, sales has a value
- We want to sum sales across multiple purchased rows for the same ASIN
- But we don't want to sum NULLs from impressions/clicks rows

The correct fix would be:
```sql
SUM(CASE WHEN measure_type = 'purchased' THEN sales ELSE 0 END) AS sales,
```

Or keep MAX() but ensure there are no duplicates in STG_AMAZON_ADS.

## Next Steps

1. Run the diagnostic queries above
2. Identify if duplicates exist in STG_AMAZON_ADS
3. If duplicates exist, fix the source data or change MAX() to SUM()
4. Re-run SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY
5. Verify the total matches $3,069
