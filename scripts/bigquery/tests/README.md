# Testing Framework - SP_MERGE_SQP_WEEKLY

This directory contains automated tests for `SP_MERGE_SQP_WEEKLY` stored procedure.

## Structure

```
scripts/bigquery/tests/
├── README.md                           # This file
├── fixtures/
│   ├── test_source_data.sql            # Test input data for source table
│   ├── test_expected_results.sql       # Expected output after merge
│   └── test_data_setup.sql             # SQL to create test data
├── framework/
│   ├── test_helpers.sql                # Common test utilities
│   └── assertions.sql                  # Pass/fail check functions
├── expected_results/
│   └── SP_MERGE_SQP_WEEKLY_SPEC.md    # Expected results specification
└── unit/
    ├── test_sp_merge_sqp_weekly_001_new_insert.sql
    ├── test_sp_merge_sqp_weekly_002_update_changed.sql
    ├── test_sp_merge_sqp_weekly_003_no_update_unchanged.sql
    └── test_sp_merge_sqp_weekly_004_edge_cases.sql
```

## How to Run Tests

### Prerequisites

1. Create test dataset: `onyga-482313.OI_TEST`
2. Create test tables:
   - `OI_TEST.TEST_STG_SQP_WEEKLY` (mirrors `OI.STG_SQP_WEEKLY`)
   - `OI_TEST.TEST_SOURCE` (test data simulating `openbridge-482712.DB.sp_ba_search_query_by_week_v1`)

### Run Individual Test

```bash
bq query --use_legacy_sql=false --project_id=onyga-482313 < scripts/bigquery/tests/unit/test_sp_merge_sqp_weekly_001_new_insert.sql
```

### Run All Tests

```bash
# TODO: Create test_runner.sh script
```

## Test Philosophy

- **Test actual results, not theory**: Compare actual output byte-for-byte with expected output
- **Simplify**: Identify unused columns and unnecessary code through testing
- **Automate**: Pass/fail based on actual vs expected values
- **Edge cases**: Test NULLs, duplicates, boundary dates, invalid data

## Adding New Tests

1. Add test data to `fixtures/test_source_data.sql`
2. Add expected results to `expected_results/SP_MERGE_SQP_WEEKLY_SPEC.md`
3. Create new test file in `unit/` following naming pattern
4. Test should follow pattern: Setup → Execute → Assert → Report
