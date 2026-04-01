# Test Setup Guide - SP_MERGE_SQP_WEEKLY

## Quick Start

### Step 1: Create Test Dataset

```bash
bq mk --dataset --location=US onyga-482313:OI_TEST
```

Or using SQL:
```sql
CREATE SCHEMA IF NOT EXISTS `onyga-482313.OI_TEST`;
```

### Step 2: Create Test Tables

Run the table creation queries from `framework/test_helpers.sql`:
- `OI_TEST.TEST_SOURCE` (mimics source table)
- `OI_TEST.TEST_STG_SQP_WEEKLY` (mimics staging table)

### Step 3: Run First Test

```bash
cd scripts/bigquery/tests
bq query --use_legacy_sql=false --project_id=onyga-482313 < unit/test_sp_merge_sqp_weekly_001_new_insert.sql
```

## What Was Created

### 1. Test Fixtures (`fixtures/`)
- **`test_source_data.sql`**: Known input data for 5 test cases
  - Test Case 1: New record insert
  - Test Case 2: Update when data changed
  - Test Case 3: No update when data unchanged
  - Test Case 4: Edge case - NULL values
  - Test Case 5: Edge case - Zero values

- **`test_data_setup.sql`**: Pre-populate staging table for update tests

### 2. Expected Results Specification (`expected_results/`)
- **`SP_MERGE_SQP_WEEKLY_SPEC.md`**: Complete specification of:
  - Input data for each test case
  - Expected behavior (INSERT/UPDATE/NO UPDATE)
  - Expected output values
  - Validation criteria
  - Business rules

### 3. Test Framework (`framework/`)
- **`test_helpers.sql`**: Common utilities:
  - Test table creation
  - Helper queries for row counts
  - Helper queries for retrieving actual values

- **`assertions.sql`**: Pass/fail check functions:
  - Row count assertions
  - Value comparison assertions
  - Update/no-update assertions

### 4. Unit Tests (`unit/`)
- **`test_sp_merge_sqp_weekly_001_new_insert.sql`**: First automated test
  - Tests new record insert behavior
  - Compares actual vs expected results
  - Reports PASS/FAIL with actual values

## Test Cases

| Test Case | Purpose | Expected Action |
|-----------|---------|-----------------|
| 001 | New Record Insert | INSERT new row |
| 002 | Update When Changed | UPDATE existing row (data changed) |
| 003 | No Update When Unchanged | NO UPDATE (all values identical) |
| 004 | Edge Case - NULLs | INSERT with NULL values preserved |
| 005 | Edge Case - Zeros | INSERT with zero values preserved |

## Next Steps

1. **Run Test 001**: Verify new record insert works
   ```bash
   bq query --use_legacy_sql=false --project_id=onyga-482313 < unit/test_sp_merge_sqp_weekly_001_new_insert.sql
   ```

2. **Create Test 002**: Test update when data changed
   - Use `test_data_setup.sql` to pre-populate staging table
   - Run merge procedure
   - Verify values updated to new values

3. **Create Test 003**: Test no update when unchanged
   - Pre-populate staging table with same values as source
   - Run merge procedure
   - Verify values NOT updated (critical test!)

4. **Fix Test Framework Issues**:
   - DECLARE statements in test scripts may need to be moved to stored procedure format
   - Consider creating TEST_SP_MERGE_SQP_WEEKLY that uses test tables

## Known Issues

1. **Test Script Format**: Current test uses inline MERGE (not stored procedure)
   - **Fix**: Create `TEST_SP_MERGE_SQP_WEEKLY` that uses `OI_TEST` tables
   - Or: Convert test to stored procedure format

2. **DECLARE Statements**: BigQuery requires DECLARE at start of stored procedure
   - **Fix**: Move DECLARE statements to beginning of test script
   - Or: Use CTEs instead of DECLARE

## Test Philosophy

- **Test actual results, not theory**: Compare actual output byte-for-byte with expected
- **Simplify through testing**: Identify unused columns and unnecessary code
- **Automate everything**: Pass/fail based on actual vs expected values
- **Edge cases matter**: Test NULLs, zeros, duplicates, boundary dates

## Validation Criteria

Each test validates:
1. **Row Count**: Correct number of rows affected
2. **Row Existence**: Row exists (or doesn't exist) as expected
3. **Value Accuracy**: All values match expected exactly
4. **Behavior Correctness**: INSERT/UPDATE/NO UPDATE happens as expected

## Files Created

```
scripts/bigquery/tests/
├── README.md                                    # Test framework overview
├── SETUP_GUIDE.md                               # This file
├── fixtures/
│   ├── test_source_data.sql                     # Test input data
│   └── test_data_setup.sql                      # Pre-population data
├── expected_results/
│   └── SP_MERGE_SQP_WEEKLY_SPEC.md             # Expected results spec
├── framework/
│   ├── test_helpers.sql                         # Common utilities
│   └── assertions.sql                           # Pass/fail checks
└── unit/
    └── test_sp_merge_sqp_weekly_001_new_insert.sql  # First test
```

## Success Criteria

✅ **Test 001 PASSES**: New row inserted with exact source values  
✅ **Test 002 PASSES**: Existing row updated with new values  
✅ **Test 003 PASSES**: Existing row NOT updated (critical!)  
✅ **Test 004 PASSES**: NULL values preserved correctly  
✅ **Test 005 PASSES**: Zero values preserved correctly  

Once all tests pass, you have proof that `SP_MERGE_SQP_WEEKLY` works correctly!
