# How to Execute FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY Tests

## Quick Start

Due to environment restrictions, you'll need to run these tests manually. Here are three ways to do it:

## Method 1: BigQuery Console (Recommended)

1. Open [BigQuery Console](https://console.cloud.google.com/bigquery?project=onyga-482313)
2. Select project: `onyga-482313`
3. Open each test file and run:
   - `scripts/bigquery/tests/unit/test_fact_amazon_search_performance_001_source_to_target.sql`
   - `scripts/bigquery/tests/unit/test_fact_amazon_search_performance_002_ad_key_referential_integrity.sql`
   - `scripts/bigquery/tests/unit/test_fact_amazon_search_performance_003_factless_key_referential_integrity.sql`

## Method 2: bq Command Line (If Available)

```bash
cd /Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI

# Test 1: Source to Target
bq query --use_legacy_sql=false --project_id=onyga-482313 \
  < scripts/bigquery/tests/unit/test_fact_amazon_search_performance_001_source_to_target.sql

# Test 2: ad_key Referential Integrity
bq query --use_legacy_sql=false --project_id=onyga-482313 \
  < scripts/bigquery/tests/unit/test_fact_amazon_search_performance_002_ad_key_referential_integrity.sql

# Test 3: factless_key Referential Integrity
bq query --use_legacy_sql=false --project_id=onyga-482313 \
  < scripts/bigquery/tests/unit/test_fact_amazon_search_performance_003_factless_key_referential_integrity.sql
```

## Method 3: Python Script (After Installing Dependencies)

```bash
# Install dependencies
pip install google-cloud-bigquery

# Run tests
python3 scripts/bigquery/tests/run_all_tests.py
```

## What Each Test Checks

### Test 1: Source to Target Data Integrity
- ✅ Row count: STG count = FACT count
- ✅ Missing rows: 0 missing
- ✅ Duplicates: 0 duplicates
- ✅ Data accuracy: All values match
- ✅ Key calculation: ad_key and factless_key formatted correctly

### Test 2: ad_key Referential Integrity
- ✅ All ad_keys from view exist in fact table
- ⚠️ Date alignment: week_end_date vs Reporting_Date
- ⚠️ NULL handling: search_term NULL handling

### Test 3: factless_key Referential Integrity
- ✅ All factless_keys from fact exist in bridge
- ⚠️ Key format: DATE vs INT64 date_key
- ⚠️ NULL ASIN: 'NULL' vs 'UNKNOWN' handling

## Expected Results

All tests should return:
- **PASS**: For critical assertions (no missing rows, no duplicates, all keys exist)
- **WARNING**: For potential issues (date alignment, NULL handling differences)

## Next Steps After Running

1. Review any FAIL assertions
2. Check sample rows provided in test output
3. Investigate root causes
4. Fix data issues
5. Re-run tests to verify fixes
