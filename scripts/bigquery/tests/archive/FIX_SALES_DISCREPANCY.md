# Fix: Sales Discrepancy in FACT_AMAZON_PERFORMANCE_DAILY

## Issue
- **Date**: Jan 29, 2026
- **Expected**: $3,069 USD
- **Actual**: $3,614.6 USD
- **Difference**: $545.6 (17.8% over)

## Root Cause

The issue was in `SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY` at line 83. The stored procedure uses `MAX(sales)` when grouping UNPIVOTed rows:

```sql
MAX(sales) AS sales,
```

**Problem**: When the same ASIN appears in multiple rows in `STG_AMAZON_ADS` with the same grouping key (date, campaign_id, ad_group_id, keyword_id, search_term, asin), `MAX()` takes the maximum sales value instead of summing them. This can cause:
1. Under-counting of Ads sales if there are multiple rows with different sales values
2. Over-counting of organic sales (because organic = total - ads, and if ads is under-counted, organic is over-counted)

## Fix Applied

Changed line 83-85 in `SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY.sql`:

**Before:**
```sql
MAX(sales) AS sales,
```

**After:**
```sql
-- Use SUM for sales to handle cases where same ASIN appears in multiple rows
-- Only sum sales from 'purchased' measure_type (others are NULL)
SUM(COALESCE(sales, 0)) AS sales,
```

## Why This Works

1. The UNPIVOT creates rows where:
   - `measure_type = 'impressions'`: sales = NULL
   - `measure_type = 'clicks'`: sales = NULL
   - `measure_type = 'purchased'`: sales = actual value

2. When grouping, `SUM(COALESCE(sales, 0))`:
   - Converts NULL to 0 for impressions/clicks rows
   - Sums actual sales values from purchased rows
   - Handles multiple purchased rows correctly

3. This ensures all sales from purchased rows are included, not just the maximum.

## Testing

After applying the fix:

1. **Re-run the stored procedure:**
   ```sql
   CALL `onyga-482313.OI.SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY`();
   ```

2. **Verify the total for Jan 29, 2026:**
   ```sql
   SELECT 
     SUM(sales) AS total_sales,
     SUM(CASE WHEN Performance_TYPE = 'Ads' THEN sales ELSE 0 END) AS ads_sales,
     SUM(CASE WHEN Performance_TYPE = 'Organic' THEN sales ELSE 0 END) AS organic_sales
   FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
   WHERE date = '2026-01-29';
   ```

3. **Expected result**: Total should be closer to $3,069 (may not be exact due to organic delta calculation, but should be much closer).

## Additional Checks

If the total is still not $3,069 after the fix, check:

1. **Source data total:**
   ```sql
   SELECT SUM(SALES_AMOUNT) 
   FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE`
   WHERE date = '2026-01-29' AND IS_LOADED = TRUE;
   ```
   This should match $3,069 if that's the source of truth.

2. **Ads sales total:**
   ```sql
   SELECT SUM(sales)
   FROM `onyga-482313.OI.STG_AMAZON_ADS`
   WHERE date = '2026-01-29' AND most_advertised_asin_purchased IS NOT NULL;
   ```

3. **Organic delta calculation:**
   - Organic = STG_AMAZON_PERFORMANCE - STG_AMAZON_ADS
   - If ads sales are now correct, organic should also be correct

## Notes

- The fix uses `SUM(COALESCE(sales, 0))` which is safe because:
  - NULL values (from impressions/clicks rows) become 0
  - Actual sales values are summed
  - Multiple rows with the same grouping key are handled correctly

- Other measures (impressions, clicks, orders, units, cost) still use `MAX()` which is appropriate because:
  - They should have the same value across rows with the same grouping key
  - If they differ, MAX() takes the maximum (which is reasonable for these metrics)

## Files Modified

- `scripts/bigquery/procedures/SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY.sql` (line 83-85)
