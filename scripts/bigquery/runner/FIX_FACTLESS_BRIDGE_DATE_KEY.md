# Fix: Missing date_key in FACT_FACTLESS_BRIDGE

## Issue Identified

The `FACT_FACTLESS_BRIDGE` table was missing date_key values because **FACT_AMAZON_PERFORMANCE_DAILY** was not included in the `SP_POPULATE_FACTLESS_BRIDGE` stored procedure.

## Root Cause

The stored procedure `SP_POPULATE_FACTLESS_BRIDGE` was only including 3 of 4 fact tables:
- ✅ FACT_INVENTORY_SNAPSHOT
- ✅ FACT_FINANCIAL_TRANSACTIONS  
- ✅ FACT_PURCHASE_ORDER
- ❌ **FACT_AMAZON_PERFORMANCE_DAILY** (MISSING)

This meant that all date_key values from `FACT_AMAZON_PERFORMANCE_DAILY` were not being populated in the bridge table, causing missing relationships in Power BI.

## Fix Applied

**File:** `scripts/Stored Procedures/SP_POPULATE_FACTLESS_BRIDGE.sql`

**Change:** Added `FACT_AMAZON_PERFORMANCE_DAILY` to the UNION ALL clauses:

```sql
UNION ALL

-- FACT_AMAZON_PERFORMANCE_DAILY keys
SELECT
  COALESCE(CAST(FORMAT_DATE('%Y%m%d', date) AS INT64), -1) AS date_key,
  COALESCE(most_advertised_asin, 'UNKNOWN') AS asin,
  CONCAT(CAST(COALESCE(CAST(FORMAT_DATE('%Y%m%d', date) AS INT64), -1) AS STRING), '-', COALESCE(most_advertised_asin, 'UNKNOWN')) AS factless_key
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
```

## Next Steps

1. **Deploy the updated stored procedure:**
   ```sql
   -- Run the updated SP_POPULATE_FACTLESS_BRIDGE.sql script
   ```

2. **Repopulate the bridge table:**
   ```sql
   CALL `onyga-482313.OI.SP_POPULATE_FACTLESS_BRIDGE`();
   ```

3. **Verify the fix:**
   ```sql
   -- Run the diagnostic query
   -- scripts/bigquery/tests/DIAGNOSE_FACTLESS_BRIDGE_DATE_KEY.sql
   ```

4. **Check results:**
   - All 4 fact tables should now contribute date_key values
   - No missing date_key values (except -1 placeholders for NULL dates, which is expected)
   - All date_key values should exist in DIM_TIME

## Diagnostic Queries

A comprehensive diagnostic query has been created at:
- `scripts/bigquery/tests/DIAGNOSE_FACTLESS_BRIDGE_DATE_KEY.sql`

This query checks for:
- NULL date_key values (should not exist)
- Missing date_key values (-1 placeholders)
- date_key values not in DIM_TIME
- NULL dates in source fact tables
- Overall date_key health summary

## Expected Behavior After Fix

- ✅ All date_key values from FACT_AMAZON_PERFORMANCE_DAILY will be included
- ✅ Bridge table will have complete date coverage from all fact tables
- ✅ Power BI relationships will work correctly for all fact tables
- ✅ Time-based filtering will work across all fact tables

## Notes

- The `-1` value is used as a placeholder for missing dates (this is by design)
- date_key values must exist in DIM_TIME for relationships to work in Power BI
- If you see date_key values not in DIM_TIME, you may need to populate DIM_TIME for those dates
