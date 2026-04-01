# Final Fix Explanation

## Issue
- Expected: $3,069 USD for Jan 29, 2026
- Actual: $3,614.6 USD
- Difference: $545.6 (17.8% over)

## Root Cause

The issue was in the UNPIVOT + GROUP BY logic in `SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY`. The original code used `MAX(sales)` which would under-count when the same ASIN appeared in multiple rows with different sales values.

## Fix Applied

I've restructured the query to:
1. **UNPIVOT** the three ASIN columns (impressions, clicks, purchased)
2. **GROUP BY** in the inner query to combine measures correctly:
   - Use `MAX()` for impressions/clicks (they should be the same across rows)
   - Use `SUM()` for purchased measures (orders, units, cost, sales) to handle duplicates
3. **SELECT** from the grouped result in the outer query

## Key Changes

**Before:**
- UNPIVOT created rows
- Outer query grouped with `MAX(sales)`

**After:**
- UNPIVOT creates rows
- Inner query groups with `SUM(CASE WHEN measure_type = 'purchased' THEN sales ELSE 0 END)`
- Outer query just selects

## Why This Should Work

1. **Handles duplicates**: If the same ASIN appears in multiple source rows with the same grouping key, sales are summed correctly
2. **Handles multiple columns**: If ASIN appears in impressions/clicks/purchased columns, measures are combined correctly
3. **Preserves uniqueness**: If ASIN appears in different search terms/campaigns, they remain separate rows (correct)

## Testing

After deploying, verify:

```sql
SELECT 
  SUM(sales) AS total_sales,
  SUM(CASE WHEN Performance_TYPE = 'Ads' THEN sales ELSE 0 END) AS ads_sales,
  SUM(CASE WHEN Performance_TYPE = 'Organic' THEN sales ELSE 0 END) AS organic_sales,
  3069.0 AS expected,
  SUM(sales) - 3069.0 AS difference
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE date = '2026-01-29';
```

## If Still Not Correct

If the total is still not $3,069, check:

1. **Source data total:**
   ```sql
   SELECT SUM(SALES_AMOUNT) 
   FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE`
   WHERE date = '2026-01-29' AND IS_LOADED = TRUE;
   ```
   This should match $3,069 if that's the source of truth.

2. **Check for true duplicates in STG_AMAZON_ADS:**
   ```sql
   SELECT 
     date, campaign_id, ad_group_id, keyword_id, search_term,
     most_advertised_asin_purchased,
     COUNT(*) AS cnt,
     SUM(sales) AS total_sales
   FROM `onyga-482313.OI.STG_AMAZON_ADS`
   WHERE date = '2026-01-29'
     AND most_advertised_asin_purchased IS NOT NULL
   GROUP BY date, campaign_id, ad_group_id, keyword_id, search_term, most_advertised_asin_purchased
   HAVING COUNT(*) > 1;
   ```
   
   If this returns rows, those are true duplicates that need to be investigated at the source.

3. **Check organic delta calculation:**
   - Organic = STG_AMAZON_PERFORMANCE - STG_AMAZON_ADS (aggregated by ASIN)
   - If ads sales are correct, organic should also be correct

## Files Modified

- ✅ `scripts/bigquery/procedures/SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY.sql`
  - Restructured UNPIVOT logic
  - Changed to SUM for purchased measures in inner query
  - Removed redundant grouping in outer query
