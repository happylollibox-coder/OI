# Merge Feasibility Check Guide

## Quick Check Script

**File**: `check_merge_feasibility.sql`

This script checks if `openbridge-482712.DB.sp_ba_search_catalog_by_week_v1` can be merged with `OI.SCP_ASIN_View_Week`.

## How to Use

1. Open BigQuery Console
2. Run the queries in `check_merge_feasibility.sql` sequentially
3. Review the results below

## Interpreting Results

### 1. Merge Feasibility Summary

The first query provides an overall assessment:

- **✅ HIGHLY MERGEABLE**: Tables have 3+ common keys (Year, Week, ASIN) and 5+ common columns
  - **Action**: Proceed with JOIN merge strategy
  
- **⚠️ MERGEABLE WITH MAPPING**: Tables have 2+ common keys and 3+ common columns
  - **Action**: Use JOIN with column mapping/transformation
  
- **⚠️ PARTIALLY MERGEABLE**: Tables have 1+ common key
  - **Action**: Use UNION with careful column mapping
  
- **❌ NOT DIRECTLY MERGEABLE**: No common keys found
  - **Action**: Need schema transformation before merging

### 2. Column Comparison

The second query shows:
- **✅ BOTH**: Column exists in both tables
- **📊 SCP_ONLY**: Column only in SCP table
- **📊 OPENBRIDGE_ONLY**: Column only in OpenBridge table
- **✅ SAME**: Data types match
- **⚠️ DIFFERENT**: Data types differ (needs casting)

**What to look for**:
- Key columns (Year, Week, ASIN) should be in BOTH
- Performance metrics should have compatible types
- Note any SCP_ONLY or OPENBRIDGE_ONLY columns you need

### 3. Data Overlap Analysis

The third query shows:
- **overlapping_records**: Records with same ASIN + Year + Week in both tables
- **overlapping_asins**: Unique ASINs that appear in both tables
- **overlap_pct**: Percentage of overlap

**Interpretation**:
- **>80% overlap**: Tables likely contain same/similar data → Use JOIN
- **40-80% overlap**: Partial overlap → Use FULL OUTER JOIN or UNION
- **<40% overlap**: Different datasets → Use UNION ALL to combine

### 4. Sample Data

The last queries show actual data samples to verify:
- Date formats match
- ASIN formats are consistent
- Data quality (no unexpected nulls)

## Known SCP Schema

Based on `scp_schema.json`, SCP_ASIN_View_Week has:
- **Keys**: Year (INTEGER), Week (INTEGER), ASIN (STRING)
- **Dates**: Start_date, End_Date, Reporting_Date (all STRING in DD/MM/YYYY format)
- **Metrics**: Impressions, Clicks, Cart_Adds, Purchases (with various breakdowns)

## Recommended Merge Strategies

### Strategy 1: JOIN (if high overlap)
```sql
SELECT 
  COALESCE(scp.ASIN, ob.ASIN) as ASIN,
  COALESCE(scp.Year, ob.Year) as Year,
  COALESCE(scp.Week, ob.Week) as Week,
  scp.*,
  ob.*
FROM `onyga-482313.OI.SCP_ASIN_View_Week` scp
FULL OUTER JOIN `openbridge-482712.DB.sp_ba_search_catalog_by_week_v1` ob
  ON scp.ASIN = ob.ASIN
  AND scp.Year = ob.Year
  AND scp.Week = ob.Week
```

### Strategy 2: UNION (if different structures)
```sql
SELECT 
  Year, Week, ASIN,
  -- Map common columns
  ...
FROM `onyga-482313.OI.SCP_ASIN_View_Week`
UNION ALL
SELECT 
  Year, Week, ASIN,
  -- Map matching columns
  ...
FROM `openbridge-482712.DB.sp_ba_search_catalog_by_week_v1`
```

## Next Steps

1. **Run the script** and review results
2. **Check column compatibility** - note any type mismatches
3. **Review data overlap** - understand how much data overlaps
4. **Choose merge strategy** based on feasibility status
5. **Test on small subset** before full merge
6. **Create merge script** based on chosen strategy

## Related Files

- `check_table_merge.sql` - Comprehensive analysis (8 detailed queries)
- `TABLE_MERGE_ANALYSIS.md` - Detailed merge strategies and considerations
- `scp_schema.json` - Known SCP table schema
