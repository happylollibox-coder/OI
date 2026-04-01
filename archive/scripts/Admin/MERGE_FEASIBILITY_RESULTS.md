# Merge Feasibility Results

**Date**: January 2025  
**Source Table**: `openbridge-482712.DB.sp_ba_search_catalog_by_week_v1`  
**Target Table**: `onyga-482313.OI.SCP_ASIN_View_Week`

## Executive Summary

**Status**: ⚠️ **PARTIALLY MERGEABLE**

The tables can be merged, but require significant column mapping and transformation. They have different schemas with only **ASIN** as a common key. The OpenBridge table does **NOT** have `Year` and `Week` columns, which are critical for the SCP table structure.

## Key Findings

### 1. Common Keys
- ✅ **ASIN**: Exists in both tables with same data type (STRING)
- ❌ **Year**: Only in SCP table (SCP_ONLY)
- ❌ **Week**: Only in SCP table (SCP_ONLY)

### 2. Common Columns
Only **3 columns** are common to both tables:
- `ASIN` (STRING) - ✅ Same type
- `Start_date` - ⚠️ Different types: SCP uses STRING, OpenBridge uses DATE
- `End_Date` - ⚠️ Different types: SCP uses STRING, OpenBridge uses DATE

### 3. Column Distribution
- **SCP-only columns**: 30 columns (including Year, Week, and all performance metrics)
- **OpenBridge-only columns**: 35 columns (different naming convention, e.g., `click_data_click_count` vs `Clicks_Clicks`)
- **Common columns**: 3 columns

### 4. Schema Differences

#### SCP Table Structure
- Uses `Year` and `Week` as key dimensions
- Column naming: `Clicks_Clicks`, `Purchases_Purchases`, etc.
- Date fields stored as STRING (DD/MM/YYYY format)
- Has detailed shipping speed breakdowns

#### OpenBridge Table Structure
- **No Year/Week columns** - uses `ob_date` (DATE type)
- Column naming: `click_data_click_count`, `purchase_data_purchase_count`, etc.
- Date fields stored as DATE type
- Has similar metrics but different structure

## Merge Challenges

### Challenge 1: Missing Time Dimensions
The OpenBridge table doesn't have `Year` and `Week` columns. To merge:
- Need to extract Year/Week from `ob_date` field
- Or aggregate OpenBridge data to weekly level first

### Challenge 2: Different Column Names
Performance metrics have different naming:
- SCP: `Clicks_Clicks`, `Purchases_Purchases`
- OpenBridge: `click_data_click_count`, `purchase_data_purchase_count`

### Challenge 3: Data Type Mismatches
- Dates: STRING vs DATE (need conversion)
- Some metrics may have different precision

## Recommended Merge Strategy

### Option 1: UNION with Column Mapping (Recommended)
Create a unified view that maps columns from both tables:

```sql
CREATE OR REPLACE VIEW `onyga-482313.OI.V_UNIFIED_SCP_DATA` AS
-- SCP data
SELECT 
  'SCP' as source,
  Year,
  Week,
  ASIN,
  PARSE_DATE('%d/%m/%Y', Start_date) as start_date,
  PARSE_DATE('%d/%m/%Y', End_Date) as end_date,
  -- Map SCP columns
  Clicks_Clicks as clicks,
  Purchases_Purchases as purchases,
  ...
FROM `onyga-482313.OI.SCP_ASIN_View_Week`

UNION ALL

-- OpenBridge data (with Year/Week extraction)
SELECT 
  'OpenBridge' as source,
  EXTRACT(YEAR FROM ob_date) as Year,
  EXTRACT(WEEK FROM ob_date) as Week,
  ASIN,
  ob_date as start_date,  -- or calculate week start
  DATE_ADD(ob_date, INTERVAL 6 DAY) as end_date,  -- or calculate week end
  -- Map OpenBridge columns
  click_data_click_count as clicks,
  purchase_data_purchase_count as purchases,
  ...
FROM `openbridge-482712.DB.sp_ba_search_catalog_by_week_v1`
```

### Option 2: JOIN on ASIN + Date Range
If you want to combine data for the same ASINs:

```sql
SELECT 
  scp.ASIN,
  scp.Year,
  scp.Week,
  scp.*,
  ob.*
FROM `onyga-482313.OI.SCP_ASIN_View_Week` scp
LEFT JOIN `openbridge-482712.DB.sp_ba_search_catalog_by_week_v1` ob
  ON scp.ASIN = ob.ASIN
  AND PARSE_DATE('%d/%m/%Y', scp.Start_date) <= ob.ob_date
  AND PARSE_DATE('%d/%m/%Y', scp.End_Date) >= ob.ob_date
```

**Note**: This will only match records where dates overlap, may miss many records.

### Option 3: Transform OpenBridge First
1. Create a weekly aggregated version of OpenBridge table
2. Extract Year/Week from dates
3. Then merge with SCP table using Year, Week, ASIN

## Next Steps

1. **Decide on merge approach**: UNION vs JOIN vs Transform-then-merge
2. **Create column mapping**: Map all 30+ SCP columns to OpenBridge equivalents
3. **Handle date conversion**: Convert STRING dates to DATE or vice versa
4. **Extract time dimensions**: Add Year/Week to OpenBridge data if needed
5. **Test on sample data**: Run merge on small date range first
6. **Validate results**: Check row counts, data quality, metrics alignment

## Column Mapping Reference

### Performance Metrics
| SCP Column | OpenBridge Column | Notes |
|------------|-------------------|-------|
| `Clicks_Clicks` | `click_data_click_count` | Same metric |
| `Purchases_Purchases` | `purchase_data_purchase_count` | Same metric |
| `Impressions_Impressions` | `impression_data_impression_count` | Same metric |
| `Cart_Adds_Cart_Adds` | `cart_add_data_cart_add_count` | Same metric |
| `Purchases_Search_Traffic_Sales` | `purchase_data_search_traffic_sales_amount` | Check currency |

### Date Fields
| SCP Column | OpenBridge Column | Conversion Needed |
|------------|-------------------|-------------------|
| `Start_date` (STRING) | `ob_date` (DATE) | Parse SCP or format OpenBridge |
| `End_Date` (STRING) | N/A | Calculate from ob_date + 6 days |
| `Reporting_Date` (STRING) | `ob_date` (DATE) | Parse/format |

## Conclusion

The tables **can be merged**, but require:
- ✅ Column mapping (30+ columns)
- ✅ Date type conversion
- ✅ Time dimension extraction (Year/Week from dates)
- ✅ Data validation

**Recommendation**: Use **UNION strategy** with comprehensive column mapping to preserve all data from both sources.
