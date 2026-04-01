# Table Merge Feasibility Analysis

## Tables to Merge

**Source Table**: `openbridge-482712.DB.sp_ba_search_catalog_by_week_v1`  
**Target Table**: `onyga-482313.OI.SCP_ASIN_View_Week`

---

## Known Schema: SCP_ASIN_View_Week

Based on `scp_schema.json`, the SCP table has the following structure:

### Key Columns (Identifiers)
- `Year` (INTEGER)
- `Week` (INTEGER)
- `ASIN` (STRING)
- `Start_date` (STRING) - Date format: DD/MM/YYYY
- `End_Date` (STRING) - Date format: DD/MM/YYYY
- `Reporting_Date` (STRING) - Date format: DD/MM/YYYY

### Product Information
- `ASIN_Title` (STRING)
- `Category` (STRING)

### Performance Metrics
- `Impressions_Impressions` (INTEGER)
- `Impressions_Rating_Median` (FLOAT)
- `Impressions_Price_Median` (FLOAT)
- `Clicks_Clicks` (INTEGER)
- `Clicks_Click_Rate_CTR` (FLOAT)
- `Cart_Adds_Cart_Adds` (INTEGER)
- `Purchases_Purchases` (INTEGER)
- `Purchases_Search_Traffic_Sales` (FLOAT)
- Plus shipping speed breakdowns for each metric

---

## Analysis Queries

### Query 1: Get SCP Schema
**Purpose**: Confirm exact column names and data types

**Run in BigQuery**: First query in `check_table_merge.sql`

**Expected Output**: List of all columns with data types

---

### Query 2: Get OpenBridge Schema
**Purpose**: See structure of the source table

**Run in BigQuery**: Second query in `check_table_merge.sql`

**Expected Output**: List of all columns with data types

**Critical Check**: 
- Does it have `Year`, `Week`, `ASIN` columns?
- Are data types compatible?

---

### Query 3: Compare Schemas
**Purpose**: Identify common columns and type mismatches

**Run in BigQuery**: Third query in `check_table_merge.sql`

**Expected Output**: 
- Columns in both tables (BOTH)
- Columns only in SCP (SCP_ONLY)
- Columns only in OpenBridge (OPENBRIDGE_ONLY)
- Type compatibility (SAME_TYPE vs DIFFERENT_TYPE)

**What to Look For**:
- ✅ Common key columns: `Year`, `Week`, `ASIN`
- ✅ Compatible data types
- ⚠️ Columns with different types (need casting)

---

### Query 4: Identify Merge Keys
**Purpose**: Find potential join keys

**Run in BigQuery**: Fourth query in `check_table_merge.sql`

**Expected Output**: List of common key columns

**Best Case**: 
- ASIN
- Year
- Week

**These should match for a proper merge**

---

### Query 5: Sample Data Comparison
**Purpose**: Understand data format and structure

**Run in BigQuery**: Fifth query in `check_table_merge.sql`

**Expected Output**: Sample rows from both tables

**What to Check**:
- Date format consistency (DD/MM/YYYY vs YYYY-MM-DD)
- ASIN format consistency
- Data quality (nulls, empty values)

---

### Query 6: Data Volume Comparison
**Purpose**: Understand data volume and coverage

**Run in BigQuery**: Sixth query in `check_table_merge.sql`

**Expected Output**: Row counts, unique ASINs, date ranges

**What to Look For**:
- Similar row counts?
- Overlapping date ranges?
- Common ASINs?

---

### Query 7: ASIN Overlap Analysis
**Purpose**: Check if tables have overlapping products

**Run in BigQuery**: Seventh query in `check_table_merge.sql`

**Expected Output**: 
- Unique ASIN counts per table
- Overlapping ASIN count
- Overlap percentages

**What This Tells You**:
- High overlap (>80%) → Likely mergeable
- Medium overlap (40-80%) → Partial merge, some products unique
- Low overlap (<40%) → Different data sets, may need careful merging

---

### Query 8: Merge Feasibility Summary
**Purpose**: Overall assessment

**Run in BigQuery**: Eighth query in `check_table_merge.sql`

**Expected Output**: Feasibility status and common column count

---

## Merge Strategies

### Strategy 1: Full Outer Join (Keep All Data)
**When to Use**: When you want all records from both tables

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

**Pros**: Preserves all data  
**Cons**: May have many NULLs, need to handle conflicts

---

### Strategy 2: Left Join (SCP as Primary)
**When to Use**: When SCP is your primary table and OpenBridge is supplementary

```sql
SELECT 
    scp.*,
    ob.column1,
    ob.column2  -- Add columns from OpenBridge you want
FROM `onyga-482313.OI.SCP_ASIN_View_Week` scp
LEFT JOIN `openbridge-482712.DB.sp_ba_search_catalog_by_week_v1` ob
    ON scp.ASIN = ob.ASIN
    AND scp.Year = ob.Year
    AND scp.Week = ob.Week
```

**Pros**: Maintains SCP structure, adds OpenBridge data  
**Cons**: Loses OpenBridge-only records

---

### Strategy 3: UNION (Combine Both)
**When to Use**: When tables have similar structure and you want all records

```sql
SELECT 
    Year, Week, ASIN, ... -- Common columns
FROM `onyga-482313.OI.SCP_ASIN_View_Week`
UNION ALL
SELECT 
    Year, Week, ASIN, ... -- Matching columns with casting
FROM `openbridge-482712.DB.sp_ba_search_catalog_by_week_v1`
```

**Pros**: Combines all records  
**Cons**: Need identical structure, may have duplicates

---

### Strategy 4: Create Unified View
**When to Use**: When you want to merge but keep sources separate

```sql
CREATE OR REPLACE VIEW `onyga-482313.OI.V_UNIFIED_SCP_DATA` AS
SELECT 
    'SCP' as source,
    Year, Week, ASIN,
    -- SCP columns
FROM `onyga-482313.OI.SCP_ASIN_View_Week`
UNION ALL
SELECT 
    'OpenBridge' as source,
    Year, Week, ASIN,
    -- OpenBridge columns (casted to match)
FROM `openbridge-482712.DB.sp_ba_search_catalog_by_week_v1`
```

**Pros**: Keeps source identification, flexible querying  
**Cons**: Need to handle schema differences in queries

---

## Potential Issues to Check

### 1. Date Format Mismatch
**Issue**: SCP uses `STRING` with DD/MM/YYYY, OpenBridge might use different format

**Solution**: Use `PARSE_DATE` or `CAST` to normalize

```sql
PARSE_DATE('%d/%m/%Y', Start_date)  -- SCP format
CAST(Start_date AS DATE)             -- If OpenBridge uses DATE
```

---

### 2. Column Name Differences
**Issue**: Same data, different column names

**Example**:
- SCP: `Purchases_Purchases`
- OpenBridge: `Purchases` or `Total_Purchases`

**Solution**: Use aliases or column mapping

```sql
SELECT 
    scp.Purchases_Purchases as purchases,
    ob.Purchases as purchases_ob
```

---

### 3. Data Type Differences
**Issue**: Same column, different types (e.g., INTEGER vs FLOAT)

**Solution**: Cast to common type

```sql
CAST(scp.column AS FLOAT64) as column_float
```

---

### 4. Missing Keys
**Issue**: No common ASIN or date keys

**Solution**: Check if other columns can serve as keys, or merge at aggregate level

---

## Next Steps

### Step 1: Run Analysis Queries
Execute all 8 queries in `check_table_merge.sql` in BigQuery

### Step 2: Review Results
- Check schema comparison (Query 3)
- Review merge keys (Query 4)
- Check ASIN overlap (Query 7)

### Step 3: Decide Merge Strategy
Based on results:
- High overlap + common keys → Use JOIN strategy
- Similar structure → Use UNION strategy
- Different purposes → Use VIEW strategy

### Step 4: Create Merge Script
Write SQL script based on chosen strategy

### Step 5: Test Merge
Run on small date range first, validate results

### Step 6: Full Implementation
Execute full merge and validate

---

## Files Reference

- `check_table_merge.sql` - **Run this** - All analysis queries
- `scp_schema.json` - Known SCP schema structure
- `TABLE_MERGE_ANALYSIS.md` - This document

---

## Quick Decision Tree

```
Do both tables have Year, Week, ASIN columns?
├─ YES → Is ASIN overlap > 50%?
│   ├─ YES → MERGEABLE (Use JOIN)
│   └─ NO → PARTIAL MERGE (Use LEFT JOIN or UNION)
└─ NO → Are there other common keys?
    ├─ YES → MERGEABLE (Use alternative keys)
    └─ NO → NOT DIRECTLY MERGEABLE (Need transformation)
```

---

*Created: January 2025*  
*Run `check_table_merge.sql` in BigQuery to get actual results*
