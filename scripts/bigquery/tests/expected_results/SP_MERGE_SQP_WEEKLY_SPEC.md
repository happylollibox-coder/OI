# Expected Results Specification - SP_MERGE_SQP_WEEKLY

**Stored Procedure**: `onyga-482313.OI.SP_MERGE_SQP_WEEKLY`

**Purpose**: Merge weekly search query performance data from OpenBridge into `STG_SQP_WEEKLY`. Only updates when data changes, inserts new records.

**Source Table**: `openbridge-482712.DB.sp_ba_search_query_by_week_v1`  
**Target Table**: `onyga-482313.OI.STG_SQP_WEEKLY`

**Match Key**: `query_text`, `ASIN`, `Year`, `Week`

---

## Test Case 1: New Record Insert

### Input
```sql
query_text = 'test query one'
ASIN = 'B001TEST01'
ob_date = DATE('2024-01-15')  -- Week 3 of 2024
impressions = 100
clicks = 10
```

### Expected Behavior
- **Action**: INSERT new row
- **Row Count**: Staging table row count should increase by 1
- **Values**: All source values should be copied to staging table

### Expected Output
```sql
SELECT * FROM TEST_STG_SQP_WEEKLY 
WHERE query_text = 'test query one' AND ASIN = 'B001TEST01';

-- Expected:
query_text = 'test query one'
ASIN = 'B001TEST01'
Year = 2024
Week = 3
ob_date = DATE('2024-01-15')
week_start_date = DATE('2024-01-15')  -- Monday
week_end_date = DATE('2024-01-21')    -- Sunday
impressions = 100
clicks = 10
click_through_rate = 10.0
conversions = 2
conversion_rate = 20.0
sales_amount = 50.00
sales_currency_code = 'USD'
query_rank = 1
avg_position = 2.5
ob_file_name = 'test_file_001.csv'
ob_marketplace_id = 'US'
ob_seller_id = 'TEST_SELLER_001'
ob_transaction_id = 'TXN001'
ob_modified_date = DATETIME('2024-01-15 10:00:00')
ob_processed_at = '2024-01-16 10:05:00'
```

### Validation
- ✅ Row exists in staging table
- ✅ All values match source exactly
- ✅ Row count increased by 1

---

## Test Case 2: Update When Data Changed

### Input
```sql
-- Source has CHANGED values:
query_text = 'test query two'  -- MATCH existing
ASIN = 'B002TEST02'             -- MATCH existing
Year = 2024, Week = 2           -- MATCH existing
impressions = 150  -- CHANGED from 100
clicks = 15        -- CHANGED from 10
conversions = 3    -- CHANGED from 2
sales_amount = 75.00  -- CHANGED from 50.00
ob_modified_date = DATETIME('2024-01-16 10:00:00')  -- CHANGED (newer)
```

### Pre-Condition (Existing in Staging)
```sql
query_text = 'test query two'
ASIN = 'B002TEST02'
Year = 2024, Week = 2
impressions = 100  -- OLD value
clicks = 10        -- OLD value
conversions = 2    -- OLD value
sales_amount = 50.00  -- OLD value
ob_modified_date = DATETIME('2024-01-15 10:00:00')  -- OLD value
```

### Expected Behavior
- **Action**: UPDATE existing row (data changed detected)
- **Row Count**: Should remain same (no new rows)
- **Values**: Staging table should have NEW values from source

### Expected Output
```sql
SELECT * FROM TEST_STG_SQP_WEEKLY 
WHERE query_text = 'test query two' AND ASIN = 'B002TEST02';

-- Expected (UPDATED values):
impressions = 150        -- UPDATED (was 100)
clicks = 15              -- UPDATED (was 10)
conversions = 3          -- UPDATED (was 2)
sales_amount = 75.00     -- UPDATED (was 50.00)
ob_modified_date = DATETIME('2024-01-16 10:00:00')  -- UPDATED (was 2024-01-15)
-- All other fields updated to source values
```

### Validation
- ✅ Row exists (not duplicated)
- ✅ Values updated to NEW values from source
- ✅ Row count unchanged
- ✅ `@@row_count` should return 1 (1 row updated)

---

## Test Case 3: No Update When Data Unchanged

### Input
```sql
-- Source has IDENTICAL values:
query_text = 'test query three'  -- MATCH existing
ASIN = 'B003TEST03'               -- MATCH existing
Year = 2024, Week = 4             -- MATCH existing
impressions = 200  -- SAME as existing
clicks = 20        -- SAME as existing
-- All values IDENTICAL to existing row
```

### Pre-Condition (Existing in Staging)
```sql
query_text = 'test query three'
ASIN = 'B003TEST03'
Year = 2024, Week = 4
impressions = 200  -- SAME value
clicks = 20        -- SAME value
-- All values match source exactly
```

### Expected Behavior
- **Action**: NO UPDATE (no change detected)
- **Row Count**: Should remain same
- **Values**: Staging table should have SAME values (no change)
- **Performance**: Should not waste time updating identical data

### Expected Output
```sql
SELECT * FROM TEST_STG_SQP_WEEKLY 
WHERE query_text = 'test query three' AND ASIN = 'B003TEST03';

-- Expected (UNCHANGED values):
impressions = 200  -- UNCHANGED
clicks = 20        -- UNCHANGED
-- All values remain SAME as before merge
```

### Validation
- ✅ Row exists (not duplicated)
- ✅ Values remain UNCHANGED
- ✅ Row count unchanged
- ✅ `@@row_count` should return 0 (no rows updated)

**Critical Test**: This verifies the "only update when data changes" logic works correctly.

---

## Test Case 4: Edge Case - NULL Values

### Input
```sql
query_text = 'test query nulls'
ASIN = 'B004TEST04'
ob_date = DATE('2024-02-05')  -- Week 6 of 2024
impressions = 50
clicks = 5
click_through_rate = NULL
conversions = NULL
sales_amount = NULL
-- Many NULL values
```

### Expected Behavior
- **Action**: INSERT new row (new query_text/ASIN/Year/Week combination)
- **Row Count**: Should increase by 1
- **NULL Handling**: NULL values should be preserved (not converted to defaults)

### Expected Output
```sql
SELECT * FROM TEST_STG_SQP_WEEKLY 
WHERE query_text = 'test query nulls' AND ASIN = 'B004TEST04';

-- Expected:
impressions = 50
clicks = 5
click_through_rate = NULL  -- Preserved NULL
conversions = NULL         -- Preserved NULL
sales_amount = NULL        -- Preserved NULL
```

### Validation
- ✅ Row inserted with NULL values preserved
- ✅ COALESCE logic doesn't break with NULLs

---

## Test Case 5: Edge Case - Zero Values

### Input
```sql
query_text = 'test query zeros'
ASIN = 'B005TEST05'
impressions = 0
clicks = 0
conversions = 0
sales_amount = 0.00
```

### Expected Behavior
- **Action**: INSERT new row
- **Zero Handling**: Zero values should be preserved (not treated as NULL)

### Expected Output
```sql
-- Expected:
impressions = 0  -- Zero, not NULL
clicks = 0       -- Zero, not NULL
conversions = 0  -- Zero, not NULL
sales_amount = 0.00  -- Zero, not NULL
```

### Validation
- ✅ Zero values preserved (not converted to NULL)
- ✅ Change detection logic handles zeros correctly (0 != NULL)

---

## Business Rules Validation

### Rule 1: Match Key Logic
- **Match on**: `query_text`, `ASIN`, `Year`, `Week` (all must match)
- **Test**: Same query_text but different ASIN should INSERT (not UPDATE)

### Rule 2: Change Detection Logic
- **Update when**: ANY metric value changes (impressions, clicks, conversions, etc.)
- **Don't update when**: ALL values identical
- **NULL Handling**: NULL != 0, NULL != '', NULL != NULL (use IS NULL for comparison)

### Rule 3: Date Calculations
- **Week Start**: Monday of the week containing `ob_date`
- **Week End**: Sunday of the week containing `ob_date`
- **Year/Week**: Extracted from `ob_date` using EXTRACT()

### Rule 4: Filter Logic
- **Source Filter**: `WHERE ASIN IS NOT NULL AND query_text IS NOT NULL`
- **Test**: Records with NULL ASIN or NULL query_text should NOT be processed

---

## Summary of Test Cases

| Test Case | Action | Row Count Change | Key Validation |
|-----------|--------|------------------|----------------|
| 1. New Record | INSERT | +1 | All values copied |
| 2. Changed Data | UPDATE | 0 | Values updated to new |
| 3. Unchanged Data | NO UPDATE | 0 | Values unchanged |
| 4. NULL Values | INSERT | +1 | NULLs preserved |
| 5. Zero Values | INSERT | +1 | Zeros preserved |

---

## Critical Validations

1. **Change Detection Works**: Test Case 2 updates, Test Case 3 doesn't update
2. **NULL Handling**: NULL values preserved correctly
3. **Zero vs NULL**: Zero values distinguished from NULL
4. **Match Key Logic**: Only exact matches update, new combinations insert
5. **Date Calculations**: Week boundaries calculated correctly (Monday to Sunday)
6. **Row Count Accuracy**: `@@row_count` reflects actual changes

---

## What "Correct" Looks Like

**PASS**: 
- Test Case 1: New row inserted with exact source values
- Test Case 2: Existing row updated with new values, old values replaced
- Test Case 3: Existing row NOT updated, values remain unchanged
- Test Case 4: New row inserted with NULL values preserved
- Test Case 5: New row inserted with zero values preserved

**FAIL**:
- Test Case 3 updates when it shouldn't (change detection broken)
- NULL values converted to defaults
- Zero values treated as NULL
- Match key logic fails (wrong row updated)
- Date calculations incorrect

---

## Next Steps

After defining expected results, create automated tests that:
1. Setup test data (source + staging pre-population)
2. Execute stored procedure
3. Query actual results
4. Compare actual vs expected (byte-for-byte)
5. Report PASS/FAIL with actual values
