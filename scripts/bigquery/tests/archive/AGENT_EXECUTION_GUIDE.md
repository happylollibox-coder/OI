# SQL Developer Agent Execution Guide

## Quick Start

All test SQL files are ready to be executed by your SQL developer agent. Here's what's available:

## Test Files

### Option 1: Run All Tests Together (Recommended)
**File**: `scripts/bigquery/tests/RUN_ALL_TESTS.sql`
- Consolidated test file with all critical tests
- Includes summary report at the end
- Run this single file to get complete results

### Option 2: Run Individual Test Files

1. **Test 1: Source to Target Data Integrity**
   - File: `scripts/bigquery/tests/unit/test_fact_amazon_search_performance_001_source_to_target.sql`
   - Tests: Row count match, no missing rows, no duplicates, data accuracy, key calculations

2. **Test 2: ad_key Referential Integrity**
   - File: `scripts/bigquery/tests/unit/test_fact_amazon_search_performance_002_ad_key_referential_integrity.sql`
   - Tests: All ad_keys from view exist in fact table

3. **Test 3: factless_key Referential Integrity**
   - File: `scripts/bigquery/tests/unit/test_fact_amazon_search_performance_003_factless_key_referential_integrity.sql`
   - Tests: All factless_keys from fact exist in bridge table

## What Each Test Verifies

### ✅ Test 1: Source to Target
- **Row Count**: `COUNT(STG) = COUNT(FACT)`
- **Missing Rows**: Every row in STG exists in FACT
- **Duplicates**: No duplicate primary keys in FACT
- **Data Accuracy**: All values match between STG and FACT
- **Key Calculation**: ad_key and factless_key formatted correctly

### ✅ Test 2: ad_key Referential Integrity
- **All Keys Exist**: Every ad_key in `V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` exists in `FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`

### ✅ Test 3: factless_key Referential Integrity
- **All Keys Exist**: Every factless_key in `FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` exists in `FACT_FACTLESS_BRIDGE`

## Expected Results

### PASS ✅
- Row counts match
- 0 missing rows
- 0 duplicate rows
- 0 missing ad_keys
- 0 missing factless_keys

### FAIL ❌
- Row count mismatch
- Missing rows found
- Duplicates found
- Missing ad_keys found
- Missing factless_keys found

## Interpreting Results

Each test returns:
- **test_name**: Name of the test
- **assertion_result**: PASS or FAIL with details
- **Sample rows**: Examples of issues found (for debugging)

## Execution Instructions for SQL Developer Agent

1. **Connect** to BigQuery project: `onyga-482313`
2. **Execute** `scripts/bigquery/tests/RUN_ALL_TESTS.sql`
3. **Review** results - each SELECT statement returns test results
4. **Check** the final SUMMARY report for overall status

## Files Ready for Execution

All SQL files are:
- ✅ Valid BigQuery SQL syntax
- ✅ Ready to execute
- ✅ Include error handling
- ✅ Provide detailed results
- ✅ Include sample rows for debugging

## Notes

- All tests use standard BigQuery SQL
- No external dependencies required
- Tests can be run in any order
- Each test is independent
- Results are returned as SELECT statements
