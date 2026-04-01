# Manual Deployment Instructions

Since the automated deployment may have issues, follow these steps manually in BigQuery Console:

## Step 1: Deploy the Updated Stored Procedure

1. Open BigQuery Console: https://console.cloud.google.com/bigquery?project=onyga-482313
2. Open the file: `scripts/bigquery/procedures/SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY.sql`
3. Copy the entire contents
4. Paste into BigQuery Console
5. Click "Run"

**Verify the fix is present**: Look for line 85 which should show:
```sql
SUM(COALESCE(sales, 0)) AS sales,
```
Instead of:
```sql
MAX(sales) AS sales,
```

## Step 2: Run the Stored Procedure

In BigQuery Console, run:
```sql
CALL `onyga-482313.OI.SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY`();
```

This will:
- Truncate FACT_AMAZON_PERFORMANCE_DAILY
- Reload all data with the corrected logic

## Step 3: Verify the Results

Run this verification query:
```sql
SELECT 
  'Verification - Jan 29, 2026' AS check_type,
  DATE('2026-01-29') AS date,
  SUM(sales) AS total_sales,
  SUM(CASE WHEN Performance_TYPE = 'Ads' THEN sales ELSE 0 END) AS ads_sales,
  SUM(CASE WHEN Performance_TYPE = 'Organic' THEN sales ELSE 0 END) AS organic_sales,
  3069.0 AS expected_sales,
  SUM(sales) - 3069.0 AS difference,
  ROUND((SUM(sales) - 3069.0) / 3069.0 * 100, 2) AS difference_pct,
  COUNT(*) AS record_count,
  COUNT(DISTINCT most_advertised_asin) AS distinct_asins
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE date = '2026-01-29';
```

## Expected Results

After the fix:
- **total_sales** should be closer to **3069.0**
- **difference** should be much smaller (ideally < $50)
- **difference_pct** should be < 2%

## If Results Are Still Off

If the total is still not $3,069, run these diagnostic queries:

### Check Source Data
```sql
SELECT 
  SUM(SALES_AMOUNT) AS source_total
FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE`
WHERE date = '2026-01-29' AND IS_LOADED = TRUE;
```

This should match $3,069 if that's the source of truth.

### Check Ads Sales
```sql
SELECT 
  SUM(sales) AS ads_total
FROM `onyga-482313.OI.STG_AMAZON_ADS`
WHERE date = '2026-01-29' 
  AND most_advertised_asin_purchased IS NOT NULL;
```

### Check for Duplicates
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
  MAX(sales) AS max_sales
FROM `onyga-482313.OI.STG_AMAZON_ADS`
WHERE date = '2026-01-29'
  AND most_advertised_asin_purchased IS NOT NULL
GROUP BY 
  date, campaign_id, ad_group_id, keyword_id, search_term, most_advertised_asin_purchased
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;
```

If this returns rows, there are duplicates in STG_AMAZON_ADS that need to be addressed.

## Files Modified

- ✅ `scripts/bigquery/procedures/SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY.sql` (line 83-85)
  - Changed from `MAX(sales)` to `SUM(COALESCE(sales, 0))`

## Next Steps After Verification

1. If the fix works, the total should be correct
2. If still off, check the diagnostic queries above
3. Consider running the full trace query: `TRACE_SALES_FROM_SOURCE_2026_01_29.sql`
