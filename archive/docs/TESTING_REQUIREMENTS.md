# Professional Testing Requirements - What's Missing

**Role**: Professional tester focused on simplification, removal of unnecessary code/columns, and verification through actual test results (not theory).

## Executive Summary

Currently, the codebase has **manual verification scripts** and **ad-hoc test queries**, but lacks:
1. **Automated test framework** with pass/fail criteria
2. **Test data fixtures** with known inputs/outputs
3. **Expected results specifications** (what "correct" looks like)
4. **Data validation rules** document
5. **Column usage analysis** (to identify unused columns)
6. **Regression test suite**
7. **Performance benchmarks**
8. **Simplification opportunities** analysis

---

## 1. Missing: Test Data Fixtures

### Current State
- ✅ Some test queries exist (`test_unified_scp_view.sql`, `test_currency.sql`)
- ❌ **NO** standard test data fixtures with known values
- ❌ **NO** sample datasets for edge cases (NULLs, duplicates, invalid dates, etc.)

### What's Needed
```
scripts/Tests/TestData/
├── fixtures/
│   ├── test_sqp_weekly_source_data.csv     # Known input data
│   ├── test_scd_weekly_source_data.csv     # Known input data
│   ├── test_product_dim_source_data.csv    # Known input data
│   └── expected_results/
│       ├── test_sqp_merge_expected.csv     # Expected output after merge
│       ├── test_scd_merge_expected.csv     # Expected output after merge
│       └── test_product_dim_expected.csv   # Expected output
```

**Required**: 
- 10-20 rows per fixture with known values
- Edge cases: NULLs, empty strings, dates at boundaries, negative numbers
- Known "correct" output for each test case

---

## 2. Missing: Expected Results Specifications

### Current State
- ❌ **NO** document defining what "correct" means
- ❌ **NO** business rules for data validation
- ❌ Verification scripts check structure, not correctness

### What's Needed

**File**: `scripts/Tests/EXPECTED_RESULTS_SPEC.md`

For each stored procedure and view, document:
- **Input**: What data goes in
- **Output**: What data should come out (exact values)
- **Rules**: Business logic (e.g., "only update if values changed", "always insert if not exists")
- **Edge Cases**: What should happen with NULLs, duplicates, invalid data

**Example**:
```markdown
## SP_MERGE_SQP_WEEKLY

### Test Case 1: New Record Insert
- Input: query_text="test", ASIN="B123", Year=2024, Week=1, impressions=100
- Expected: New row inserted in STG_SQP_WEEKLY
- Validation: Row count increases by 1

### Test Case 2: Update Only If Changed
- Input: Same query_text/ASIN/Year/Week, but impressions changed from 100 to 200
- Expected: Row updated
- Validation: impressions = 200, updated_at timestamp changed

### Test Case 3: No Update If Unchanged
- Input: Same query_text/ASIN/Year/Week, same impressions value
- Expected: No update
- Validation: updated_at timestamp NOT changed, @@row_count = 0
```

---

## 3. Missing: Column Usage Analysis

### Current State
- ❌ **NO** analysis of which columns are actually used
- ❌ Stored procedures have many columns - are all necessary?
- ❌ Views may have redundant calculations

### What's Needed

**File**: `scripts/Tests/COLUMN_USAGE_ANALYSIS.md`

For each table/view/stored procedure:
1. **List all columns**
2. **Track usage**: Is this column queried by downstream views/reports?
3. **Flag unused**: Mark columns never used
4. **Recommendation**: Remove or keep

**Example Analysis Required**:
- `SP_MERGE_SCD_WEEKLY`: 30+ columns - are all shipping speed variants used?
- `V_UNIFIED_SCP_DATA`: Multiple NULL-mapped fields - can they be simplified?
- `SP_MERGE_SQP_WEEKLY`: 15+ metadata fields (ob_file_name, ob_marketplace_id, etc.) - all needed?

**Tool Needed**: SQL queries to check:
```sql
-- Which columns in STG_SCD_WEEKLY are never queried?
SELECT column_name
FROM INFORMATION_SCHEMA.COLUMNS
WHERE table_name = 'STG_SCD_WEEKLY'
  AND column_name NOT IN (
    SELECT DISTINCT column_name
    FROM INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
    WHERE table_name LIKE '%VIEW%'
  );
```

---

## 4. Missing: Automated Test Framework

### Current State
- ✅ `validate.sh` checks if views exist (structure check)
- ❌ **NO** automated tests for correctness
- ❌ **NO** automated tests for data quality
- ❌ **NO** regression tests

### What's Needed

**Structure**:
```
scripts/Tests/
├── framework/
│   ├── test_runner.sh           # Runs all tests
│   ├── test_helpers.sql         # Common test utilities
│   └── assertions.sql           # Pass/fail check functions
├── unit/
│   ├── test_sp_merge_sqp_weekly.sql
│   ├── test_sp_merge_scd_weekly.sql
│   ├── test_sp_merge_product_dim.sql
│   └── test_v_unified_scp_data.sql
├── integration/
│   ├── test_full_merge_pipeline.sql
│   └── test_view_data_quality.sql
└── regression/
    └── test_known_good_outputs.sql
```

**Test Format**:
Each test should:
1. **Setup**: Load test fixtures
2. **Execute**: Run stored procedure/view query
3. **Assert**: Compare actual vs expected (EXACT match, not theory)
4. **Report**: Pass/Fail with actual vs expected values

**Example Test**:
```sql
-- test_sp_merge_sqp_weekly.sql
-- Test: Verify only updates when data changes

-- Setup: Insert known test data
INSERT INTO `onyga-482313.OI.TEST_STG_SQP_WEEKLY` ...
INSERT INTO `openbridge-482712.DB.TEST_SOURCE` ...

-- Execute: Run merge
CALL `onyga-482313.OI.SP_MERGE_SQP_WEEKLY`();

-- Assert: Check row count changed
DECLARE actual_count INT64;
SET actual_count = (SELECT COUNT(*) FROM `onyga-482313.OI.TEST_STG_SQP_WEEKLY`);

IF actual_count != 5 THEN
  SELECT 'FAIL' as result, 'Expected 5 rows, got ' || CAST(actual_count AS STRING) as message;
ELSE
  SELECT 'PASS' as result;
END IF;
```

---

## 5. Missing: Data Validation Rules

### Current State
- ❌ **NO** documented validation rules
- ❌ **NO** checks for invalid data (negative numbers, future dates, etc.)
- ❌ **NO** referential integrity checks

### What's Needed

**File**: `scripts/Tests/DATA_VALIDATION_RULES.md`

For each table:
1. **Required Fields**: Which columns must be NOT NULL?
2. **Value Constraints**: 
   - Year must be between 2020-2030
   - Week must be 1-53
   - Impressions, clicks, etc. must be >= 0
   - Dates must be valid, not future
3. **Business Rules**:
   - ASIN format validation
   - Currency codes must be valid ISO codes
   - Percentages must be 0-100

**Validation Queries Needed**:
```sql
-- Test: All required fields populated
SELECT 'FAIL: NULL ASIN' WHERE EXISTS (
  SELECT 1 FROM STG_SQP_WEEKLY WHERE ASIN IS NULL
);

-- Test: No negative metrics
SELECT 'FAIL: Negative impressions' WHERE EXISTS (
  SELECT 1 FROM STG_SCD_WEEKLY WHERE impression_data_impression_count < 0
);

-- Test: Valid date ranges
SELECT 'FAIL: Future dates' WHERE EXISTS (
  SELECT 1 FROM STG_SCD_WEEKLY WHERE ob_date > CURRENT_DATE()
);
```

---

## 6. Missing: Simplification Analysis

### Current State
- Complex stored procedures with repetitive column lists
- Multiple similar columns (e.g., same_day, one_day, two_day shipping variants)
- Views with many NULL-mapped fields

### What's Needed

**File**: `scripts/Tests/SIMPLIFICATION_OPPORTUNITIES.md`

**Questions to Answer**:
1. **Can column lists be simplified?**
   - Use `SELECT *` where safe?
   - Create helper views for repeated column groups?

2. **Are redundant columns needed?**
   - Do we need both `week_start_date` AND `ob_date`?
   - Do we need both raw dates (`start_date_raw`) AND parsed dates (`start_date`)?

3. **Can merge logic be simplified?**
   - `SP_MERGE_SCD_WEEKLY`: Updates all fields always - is change detection needed?
   - `SP_MERGE_SQP_WEEKLY`: Complex change detection - is it working correctly?

4. **Can views be simplified?**
   - `V_UNIFIED_SCP_DATA`: Many CAST(NULL AS ...) fields - can they be removed?
   - Can UNION ALL logic be extracted to a function?

**Action Items**:
- [ ] Audit each stored procedure: Which columns can be removed?
- [ ] Audit each view: Which transformations are unnecessary?
- [ ] Create simplified versions side-by-side with current versions
- [ ] Run tests on both versions to ensure they produce same results

---

## 7. Missing: Regression Test Suite

### Current State
- ❌ **NO** tests that verify "nothing broke"
- ❌ **NO** baseline outputs saved
- ❌ Changes to stored procedures not verified against known good outputs

### What's Needed

**File**: `scripts/Tests/REGRESSION_BASELINE.md`

**Approach**:
1. **Create baseline**: Run all procedures on known test data, save outputs
2. **Save baseline**: Commit expected outputs to git (CSV files)
3. **Regression test**: After any change, re-run and compare byte-for-byte

**Structure**:
```
scripts/Tests/baseline/
├── baseline_sp_merge_sqp_weekly.csv    # Known good output
├── baseline_sp_merge_scd_weekly.csv
├── baseline_v_unified_scp_data.csv
└── baseline_test_data.csv              # Input data used for baseline
```

**Automated Check**:
```bash
# Run stored procedure
CALL SP_MERGE_SQP_WEEKLY();

# Export results
bq query --format=csv "SELECT * FROM STG_SQP_WEEKLY ORDER BY ASIN, Year, Week" > actual_output.csv

# Compare with baseline
diff baseline_sp_merge_sqp_weekly.csv actual_output.csv
```

---

## 8. Missing: Performance Benchmarks

### Current State
- ❌ **NO** performance metrics
- ❌ **NO** understanding of execution time
- ❌ **NO** cost tracking (BigQuery bytes scanned)

### What's Needed

**File**: `scripts/Tests/PERFORMANCE_BENCHMARKS.md`

**Metrics to Track**:
- Execution time for each stored procedure
- Bytes scanned by each view query
- Row counts processed
- Cost per run

**Baseline Metrics Needed**:
```sql
-- Before optimization: Track execution time
DECLARE start_time TIMESTAMP;
SET start_time = CURRENT_TIMESTAMP();
CALL SP_MERGE_SCD_WEEKLY();
SELECT TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND) as execution_seconds;
```

**Goal**: If simplification reduces columns/calculations, verify it also improves performance.

---

## 9. Missing: Test Execution Environment

### Current State
- Tests would run against production-like data
- No isolated test environment
- No way to safely test without affecting real data

### What's Needed

**Test Dataset**: `onyga-482313.OI_TEST` (separate dataset for testing)

**Test Tables**:
- `OI_TEST.TEST_STG_SQP_WEEKLY`
- `OI_TEST.TEST_STG_SCD_WEEKLY`
- `OI_TEST.TEST_DIM_PRODUCT`

**Process**:
1. All tests run in `OI_TEST` dataset
2. Use test fixtures, not production data
3. Tests can modify/drop test tables safely
4. No impact on production `OI` dataset

---

## 10. Missing: Test Documentation

### Current State
- Some test SQL files exist but no documentation
- No test coverage report
- No guide on how to run tests

### What's Needed

**File**: `scripts/Tests/README.md`

Should include:
- How to run all tests
- How to add new tests
- Test coverage (what's tested vs what's not)
- How to interpret test results
- Troubleshooting guide

---

## Priority Actions

### Immediate (Week 1)
1. ✅ Create `TESTING_REQUIREMENTS.md` (this document)
2. ⬜ Create test dataset `OI_TEST`
3. ⬜ Create test data fixtures (10-20 rows each)
4. ⬜ Write expected results spec for 1 stored procedure (start with `SP_MERGE_SQP_WEEKLY`)

### Short Term (Week 2-3)
5. ⬜ Build automated test framework (test runner + assertions)
6. ⬜ Write unit tests for all stored procedures
7. ⬜ Perform column usage analysis
8. ⬜ Create data validation rules document

### Medium Term (Month 2)
9. ⬜ Regression test suite with baselines
10. ⬜ Simplification analysis and recommendations
11. ⬜ Performance benchmarks
12. ⬜ Integration tests

---

## How to Get Started

**Step 1**: Choose one stored procedure to test end-to-end
- Recommendation: Start with `SP_MERGE_SQP_WEEKLY` (simpler than `SP_MERGE_SCD_WEEKLY`)

**Step 2**: Create test data fixtures
- 5-10 rows of input data
- Known expected output

**Step 3**: Write first automated test
- Setup → Execute → Assert → Report

**Step 4**: Run test and document results
- Does it pass? What are actual vs expected values?

**Step 5**: Use test results to identify issues
- If test fails, investigate why (don't assume theory is correct)

---

## Questions to Answer Through Testing

1. **Does `SP_MERGE_SQP_WEEKLY` actually only update when data changes?**
   - Theory says yes, but test will prove it

2. **Are all columns in stored procedures actually used?**
   - Column usage analysis will show unused columns

3. **Can we simplify column lists in merge statements?**
   - Test simplified version produces same results

4. **Do views with many NULL fields need all those fields?**
   - Test if removing NULL fields breaks anything downstream

5. **Are date calculations correct?**
   - Test edge cases (year boundaries, week 53, etc.)

---

## Summary

**What I need to do my job**:
1. ✅ Test data fixtures with known inputs/outputs
2. ✅ Expected results specifications (what "correct" means)
3. ✅ Automated test framework (not manual SQL queries)
4. ✅ Column usage analysis (identify unused columns)
5. ✅ Data validation rules (what's valid vs invalid)
6. ✅ Test execution environment (isolated `OI_TEST` dataset)
7. ✅ Regression baselines (known good outputs to compare against)

**Without these, I can only:**
- Check if views/tables exist (structure)
- Run ad-hoc queries and hope results look right
- Assume code works based on reading it (theory)

**With these, I can:**
- Prove correctness through actual test results
- Identify unnecessary code/columns through usage analysis
- Simplify with confidence (test ensures same results)
- Catch regressions automatically

---

**Next Step**: Once test fixtures and framework are in place, I can start systematically testing everything and identifying simplification opportunities.
