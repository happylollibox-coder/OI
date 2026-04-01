# Test Results for SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY

## Test Execution Summary
- **Test Date**: 2026-02-01
- **Procedure**: SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY
- **Execution Time**: 17 seconds
- **Status**: ✅ PASSED

## Test Results

### Test 1: Procedure Execution
✅ **PASSED**
- Procedure executed successfully
- Ads records inserted: 290,723
- Sales delta records inserted: 3,102
- Clicks delta records inserted: 3,218
- Total records: 297,043

### Test 2: Record Counts by Performance Type
✅ **PASSED**
- **Ads Records**: 290,723 records across 96 unique dates (2025-10-28 to 2026-01-31)
- **Organic Records**: 6,320 records across 399 unique dates (2024-12-24 to 2026-01-29)
- **Total**: 297,043 records across 404 unique dates

### Test 3: Data Quality Status Distribution
✅ **PASSED**
- **OK Status**: 284,282 records (Ads records with no issues)
- **Empty Status**: 6,182 records (Organic records with no warnings)
- **Missing Organic Data**: 6,453 records (dates with IS_LOADED=FALSE or missing dates)
- **Ads Greater Than Total**: 6,441 records (dates where ads measures exceed total performance)
- **Negative Deltas**: 126 records (properly flagged and set to 0)

### Test 4: Ads Records Validation
✅ **PASSED**
- All 290,723 Ads records have:
  - Performance_TYPE = 'Ads' ✓
  - data_SOURCE = 'STG_AMAZON_ADS' ✓
  - campaign_id IS NOT NULL ✓
  - ad_group_id IS NOT NULL ✓
  - keyword_id IS NOT NULL ✓
  - cost > 0 (where applicable) ✓
  - CLICKS_DAILY_UNIQUE IS NULL ✓

### Test 5: Organic Records Validation
✅ **PASSED**
- All 6,320 Organic records have:
  - Performance_TYPE = 'Organic' ✓
  - data_SOURCE = 'STG_AMAZON_PERFORMANCE' ✓
  - campaign_id IS NULL ✓
  - ad_group_id IS NULL ✓
  - keyword_id IS NULL ✓
  - cost = 0 ✓
  - ASIN populated (most_advertised_asin_purchased OR most_advertised_asin_clicks) ✓

### Test 6: Negative Delta Check
✅ **PASSED**
- **No negative values found** in any organic records:
  - negative_orders: 0
  - negative_units: 0
  - negative_sales: 0
  - negative_clicks: 0
  - negative_clicks_daily_unique: 0
- All negative deltas were properly set to 0 using GREATEST(0, ...)

### Test 7: Sample Sales Delta Records
✅ **PASSED**
- Sample records show correct delta calculations
- Example: B0C1VLXYBP on 2026-01-29
  - orders: 9
  - units: 9
  - sales: 535.14
  - cost: 0
  - DATA_QUALITY_STATUS: (empty = no issues)

### Test 8: Sample Clicks Delta Records
✅ **PASSED**
- Sample records show correct delta calculations
- Example: B0C1VLXYBP on 2026-01-29
  - clicks: 633
  - CLICKS_DAILY_UNIQUE: 385
  - cost: 0
  - DATA_QUALITY_STATUS: (empty = no issues)

### Test 9: Missing Organic Data Handling
✅ **PASSED**
- Dates with missing organic data are properly flagged
- All records for those dates have DATA_QUALITY_STATUS containing "Missing Organic data"
- Example dates flagged:
  - 2026-01-31: 844 records
  - 2026-01-30: 1,125 records
  - 2026-01-28: 1,486 records

### Test 10: Ads Greater Than Total Warnings
✅ **PASSED**
- Dates where aggregated ads measures exceed total performance measures are properly flagged
- Warnings include specific measure names:
  - "Ads SALES_QUANTITY in ads greater than total"
  - "Ads SALES_AMOUNT in ads greater than total"
  - "Ads SALES_ORDERS in ads greater than total"
  - "Ads CLICKS in ads greater than total"
  - "Ads CLICKS_DAILY_UNIQUE in ads greater than total"

## Key Validations

### ✅ Data Integrity
- All records have valid Performance_TYPE ('Ads' or 'Organic')
- All records have valid data_SOURCE
- No NULL values in required fields (except where intentionally NULL for organic records)
- No negative values in measure fields

### ✅ Business Logic
- Ads records maintain all original fields from STG_AMAZON_ADS
- Organic records have NULL for campaign/ad_group/keyword fields
- Organic records have cost = 0
- Delta calculations correctly subtract ads from performance
- Negative deltas are set to 0 and flagged in DATA_QUALITY_STATUS

### ✅ Data Quality
- Missing organic data is properly detected and flagged
- Ads measures greater than total are properly detected and flagged
- Negative deltas are properly detected and flagged
- Multiple warnings are properly concatenated

## Test Conclusion

**All tests PASSED** ✅

The SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY procedure is working correctly:
- Successfully loads Ads records from STG_AMAZON_ADS
- Successfully calculates and loads organic delta records
- Properly handles negative deltas (sets to 0)
- Properly flags data quality issues
- Maintains data integrity across all record types
