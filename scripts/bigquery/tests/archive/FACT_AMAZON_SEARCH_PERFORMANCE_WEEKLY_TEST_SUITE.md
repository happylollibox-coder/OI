# Test Suite: FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY & V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY

## Overview

Comprehensive test suite for data integrity and referential integrity of:
- `FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` (Fact Table)
- `V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` (View)
- `FACT_FACTLESS_BRIDGE` (Bridge Table)

## Test Scenarios

### 1. Source to Target Data Integrity ✅
**File**: `test_fact_amazon_search_performance_001_source_to_target.sql`

**Tests**:
- ✅ Row count match (STG = FACT)
- ✅ No missing rows
- ✅ No duplicate rows
- ✅ Data value accuracy
- ✅ Key calculation accuracy (ad_key, factless_key)

**Purpose**: Verify all data from `STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY` is correctly loaded into `FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` with no data loss or duplication.

---

### 2. ad_key Referential Integrity ✅
**File**: `test_fact_amazon_search_performance_002_ad_key_referential_integrity.sql`

**Tests**:
- ✅ All ad_keys from view exist in fact table
- ⚠️ Date alignment check (week_end_date vs Reporting_Date)
- ⚠️ NULL search query handling
- 🔍 Key format analysis
- 🔍 Detailed missing key analysis

**Purpose**: Verify that every `ad_key` in `V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` exists in `FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`.

**Known Issues to Watch**:
- View uses `week_end_date`, fact uses `Reporting_Date` - may not align
- View doesn't use COALESCE('NULL'), fact does - key format may differ

---

### 3. factless_key Referential Integrity ✅
**File**: `test_fact_amazon_search_performance_003_factless_key_referential_integrity.sql`

**Tests**:
- ✅ All factless_keys from fact exist in bridge
- ⚠️ Key format compatibility
- ✅ Bridge table population check
- ⚠️ NULL ASIN handling (fact uses 'NULL', bridge uses 'UNKNOWN')
- ⚠️ Date key conversion check
- 🔍 Alternative key format matching

**Purpose**: Verify that every `factless_key` in `FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` exists in `FACT_FACTLESS_BRIDGE`.

**Known Issues to Watch**:
- Fact uses `COALESCE(ASIN, 'NULL')`, bridge uses `COALESCE(asin, 'UNKNOWN')` - NULL ASINs may not match
- Date format: Fact uses DATE → STRING, bridge uses INT64 → STRING

---

## How to Run Tests

### Run Individual Test

```bash
# Test 1: Source to Target Data Integrity
bq query --use_legacy_sql=false --project_id=onyga-482313 \
  < scripts/bigquery/tests/unit/test_fact_amazon_search_performance_001_source_to_target.sql

# Test 2: ad_key Referential Integrity
bq query --use_legacy_sql=false --project_id=onyga-482313 \
  < scripts/bigquery/tests/unit/test_fact_amazon_search_performance_002_ad_key_referential_integrity.sql

# Test 3: factless_key Referential Integrity
bq query --use_legacy_sql=false --project_id=onyga-482313 \
  < scripts/bigquery/tests/unit/test_fact_amazon_search_performance_003_factless_key_referential_integrity.sql
```

### Run All Tests

```bash
# Run all three tests sequentially
for test in scripts/bigquery/tests/unit/test_fact_amazon_search_performance_*.sql; do
  echo "Running $test..."
  bq query --use_legacy_sql=false --project_id=onyga-482313 < "$test"
  echo ""
done
```

### Run Tests in BigQuery Console

1. Open BigQuery Console
2. Navigate to project: `onyga-482313`
3. Open each test file
4. Run query
5. Review results

---

## Expected Results

### Test 1: Source to Target ✅
- **Row Count Match**: `stg_row_count = fact_row_count`
- **Missing Rows**: `0`
- **Duplicate Rows**: `0`
- **Mismatched Values**: `0`
- **Incorrect Keys**: `0`

### Test 2: ad_key Referential Integrity ✅
- **Missing ad_keys**: `0` (all view ad_keys exist in fact)
- **Date Mismatches**: May have some (expected if week_end_date ≠ Reporting_Date)
- **NULL Handling Issues**: May have some (expected if NULL handling differs)

### Test 3: factless_key Referential Integrity ✅
- **Missing factless_keys**: `0` (all fact factless_keys exist in bridge)
- **Format Mismatches**: May have some (expected if formats differ)
- **NULL ASIN Issues**: May have some (expected if NULL handling differs)

---

## Interpreting Results

### PASS ✅
- All assertions return `PASS`
- Counts are `0` for missing/duplicate rows
- All keys exist in target tables

### FAIL ❌
- Any assertion returns `FAIL`
- Missing rows or keys found
- Duplicates detected
- **Action**: Review sample rows provided in test output to identify root cause

### WARNING ⚠️
- Date alignment issues
- NULL handling inconsistencies
- Format mismatches
- **Action**: Review warnings - may be expected behavior or need investigation

---

## Key Format Details

### FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY

**ad_key Format**:
```
YYYYMMDD-ASIN-Search_Query
```
- Example: `20240115-B001TEST01-test query`
- NULL handling: `COALESCE(ASIN, 'NULL')` and `COALESCE(Search_Query, 'NULL')`
- Date: `FORMAT_DATE('%Y%m%d', Reporting_Date)`

**factless_key Format**:
```
YYYYMMDD-ASIN
```
- Example: `20240115-B001TEST01`
- NULL handling: `COALESCE(ASIN, 'NULL')`
- Date: `FORMAT_DATE('%Y%m%d', Reporting_Date)`

### V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY

**ad_key Format**:
```
YYYYMMDD-asin-search_term
```
- Example: `20240115-B001TEST01-test query`
- NULL handling: Uses `asin` and `search_term` directly (no COALESCE to 'NULL')
- Date: `FORMAT_DATE('%Y%m%d', week_end_date)`

**factless_key Format**:
```
YYYYMMDD-asin
```
- Example: `20240115-B001TEST01`
- NULL handling: Uses `asin` directly (no COALESCE)
- Date: `FORMAT_DATE('%Y%m%d', week_end_date)`

### FACT_FACTLESS_BRIDGE

**factless_key Format**:
```
date_key-asin
```
- Example: `20240115-B001TEST01`
- NULL handling: `COALESCE(asin, 'UNKNOWN')`
- Date: `CAST(date_key AS STRING)` where `date_key` is INT64 (YYYYMMDD format)

---

## Known Issues & Potential Problems

### 1. Date Alignment
- **Issue**: View uses `week_end_date`, fact uses `Reporting_Date`
- **Impact**: Keys may not match if dates don't align
- **Test**: Test 2.2 checks for date mismatches

### 2. NULL Handling Inconsistency
- **Issue**: View doesn't use COALESCE('NULL'), fact does
- **Impact**: NULL values may create different key formats
- **Test**: Test 2.3 checks for NULL handling issues

### 3. NULL ASIN Handling
- **Issue**: Fact uses 'NULL', bridge uses 'UNKNOWN'
- **Impact**: NULL ASINs won't match between fact and bridge
- **Test**: Test 3.4 checks for NULL ASIN issues

### 4. Bridge Table Population
- **Issue**: `SP_POPULATE_FACTLESS_BRIDGE` must include `FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
- **Impact**: factless_keys won't exist in bridge if not included
- **Test**: Test 3.3 checks bridge population

---

## Files Created

```
scripts/bigquery/tests/
├── expected_results/
│   └── FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY_SPEC.md  # Expected results specification
├── unit/
│   ├── test_fact_amazon_search_performance_001_source_to_target.sql
│   ├── test_fact_amazon_search_performance_002_ad_key_referential_integrity.sql
│   └── test_fact_amazon_search_performance_003_factless_key_referential_integrity.sql
└── FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY_TEST_SUITE.md  # This file
```

---

## Next Steps

1. **Run Tests**: Execute all three test files
2. **Review Results**: Check for FAIL or WARNING assertions
3. **Investigate Issues**: Use sample rows provided in test output
4. **Fix Issues**: Address any data integrity or referential integrity problems
5. **Re-run Tests**: Verify fixes resolved issues
6. **Document Findings**: Update this document with any discovered issues

---

## Success Criteria

✅ **All Tests Pass**: No missing rows, no duplicates, all keys exist  
✅ **Data Integrity**: Source to target data matches exactly  
✅ **Referential Integrity**: All foreign keys exist in target tables  
✅ **Key Formats**: All keys calculated correctly  

---

## Questions?

If tests fail or show warnings:
1. Review the sample rows provided in test output
2. Check key format calculations
3. Verify stored procedures include all necessary tables
4. Check NULL handling consistency
5. Verify date alignment between view and fact
