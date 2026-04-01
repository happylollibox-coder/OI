# Expected Results Specification - FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY & V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY

**Objects Under Test**:
- `FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` (Fact Table)
- `V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` (View)
- `FACT_FACTLESS_BRIDGE` (Bridge Table)

---

## Test Scenario 1: Source to Target Data Integrity

### Purpose
Verify that all data from `STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY` is correctly loaded into `FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` with no missing rows and no duplicates.

### Source Table
- **Table**: `onyga-482313.OI.STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
- **Primary Key**: `(Reporting_Date, ASIN, Search_Query)`
- **Load Method**: TRUNCATE + INSERT (full refresh)

### Target Table
- **Table**: `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
- **Primary Key**: `(Reporting_Date, ASIN, Search_Query)`
- **Additional Fields**: `ad_key`, `factless_key`

### Expected Behavior

#### 1.1 Row Count Match
- **Expected**: `COUNT(*) FROM FACT` = `COUNT(*) FROM STG`
- **Validation**: Row counts must match exactly
- **Failure Condition**: If counts don't match, data is missing or duplicated

#### 1.2 No Missing Rows
- **Expected**: Every row in STG exists in FACT
- **Validation**: LEFT JOIN STG to FACT - no NULLs in FACT columns
- **Query**:
```sql
SELECT COUNT(*) as missing_rows
FROM STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY stg
LEFT JOIN FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY fact
  ON stg.Reporting_Date = fact.Reporting_Date
  AND stg.ASIN = fact.ASIN
  AND COALESCE(stg.Search_Query, '') = COALESCE(fact.Search_Query, '')
WHERE fact.Reporting_Date IS NULL
```
- **Expected Result**: 0 missing rows

#### 1.3 No Duplicate Rows
- **Expected**: No duplicate primary keys in FACT
- **Validation**: COUNT(*) = COUNT(DISTINCT Reporting_Date, ASIN, Search_Query)
- **Query**:
```sql
SELECT 
  Reporting_Date,
  ASIN,
  Search_Query,
  COUNT(*) as duplicate_count
FROM FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY
GROUP BY Reporting_Date, ASIN, Search_Query
HAVING COUNT(*) > 1
```
- **Expected Result**: 0 duplicate rows

#### 1.4 Data Value Accuracy
- **Expected**: All non-key columns match between STG and FACT
- **Validation**: Compare all columns except ad_key and factless_key
- **Query**: Compare each column value
- **Expected Result**: All values match exactly

#### 1.5 Key Calculation Accuracy
- **Expected**: ad_key and factless_key calculated correctly
- **ad_key Format**: `YYYYMMDD-ASIN-Search_Query`
  - Example: `20240115-B001TEST01-test query`
  - NULL handling: `COALESCE(ASIN, 'NULL')` and `COALESCE(Search_Query, 'NULL')`
- **factless_key Format**: `YYYYMMDD-ASIN`
  - Example: `20240115-B001TEST01`
  - NULL handling: `COALESCE(ASIN, 'NULL')`
- **Validation**: Compare calculated keys with expected format

### Validation Criteria
✅ **PASS**: Row counts match, no missing rows, no duplicates, all values match, keys calculated correctly  
❌ **FAIL**: Any missing rows, duplicates, mismatched values, or incorrect key calculations

---

## Test Scenario 2: Referential Integrity - ad_key

### Purpose
Verify that every `ad_key` in `V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` exists in `FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`.

### View
- **View**: `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY`
- **ad_key Format**: `YYYYMMDD-asin-search_term` (using `week_end_date`)
- **Source**: Aggregated from `FACT_AMAZON_ADS` by week

### Fact Table
- **Table**: `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
- **ad_key Format**: `YYYYMMDD-ASIN-Search_Query` (using `Reporting_Date`)
- **Source**: Loaded from `STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY`

### Expected Behavior

#### 2.1 All ad_keys Exist
- **Expected**: Every ad_key in view exists in fact table
- **Validation**: LEFT JOIN view to fact - no NULLs in fact columns
- **Query**:
```sql
SELECT COUNT(*) as missing_ad_keys
FROM V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY view
LEFT JOIN FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY fact
  ON view.ad_key = fact.ad_key
WHERE fact.ad_key IS NULL
```
- **Expected Result**: 0 missing ad_keys

#### 2.2 Key Format Compatibility
- **Note**: View uses `week_end_date` (DATE) → `YYYYMMDD`
- **Note**: Fact uses `Reporting_Date` (DATE) → `YYYYMMDD`
- **Potential Issue**: If `week_end_date` ≠ `Reporting_Date`, keys won't match
- **Validation**: Check if date alignment is correct
- **Query**: Compare date ranges and alignment

### Edge Cases

#### 2.3 NULL Search Query Handling
- **View**: Uses `search_term` directly (no COALESCE to 'NULL')
- **Fact**: Uses `COALESCE(Search_Query, 'NULL')` in key
- **Issue**: If view has NULL search_term, key format might differ
- **Validation**: Check NULL handling consistency

#### 2.4 Case Sensitivity
- **View**: Uses `asin` and `search_term` (lowercase column names)
- **Fact**: Uses `ASIN` and `Search_Query` (uppercase column names)
- **Validation**: Ensure key values are case-insensitive or normalized

### Validation Criteria
✅ **PASS**: All ad_keys from view exist in fact table  
❌ **FAIL**: Any ad_keys in view don't exist in fact table

---

## Test Scenario 3: Referential Integrity - factless_key

### Purpose
Verify that every `factless_key` in `FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` exists in `FACT_FACTLESS_BRIDGE`.

### Fact Table
- **Table**: `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
- **factless_key Format**: `YYYYMMDD-ASIN` (using `Reporting_Date`)
- **Calculation**: `CONCAT(FORMAT_DATE('%Y%m%d', Reporting_Date), '-', COALESCE(ASIN, 'NULL'))`

### Bridge Table
- **Table**: `onyga-482313.OI.FACT_FACTLESS_BRIDGE`
- **factless_key Format**: `date_key-asin` where `date_key` is INT64 (YYYYMMDD format)
- **Calculation**: `CONCAT(CAST(date_key AS STRING), '-', asin)`
- **Source**: UNION of all fact table keys

### Expected Behavior

#### 3.1 All factless_keys Exist
- **Expected**: Every factless_key in fact table exists in bridge table
- **Validation**: LEFT JOIN fact to bridge - no NULLs in bridge columns
- **Query**:
```sql
SELECT COUNT(*) as missing_factless_keys
FROM FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY fact
LEFT JOIN FACT_FACTLESS_BRIDGE bridge
  ON fact.factless_key = bridge.factless_key
WHERE bridge.factless_key IS NULL
```
- **Expected Result**: 0 missing factless_keys

#### 3.2 Key Format Compatibility
- **Fact**: Uses DATE → `FORMAT_DATE('%Y%m%d', Reporting_Date)` → STRING
- **Bridge**: Uses INT64 `date_key` → `CAST(date_key AS STRING)` → STRING
- **Both**: Format should be `YYYYMMDD-ASIN`
- **Validation**: Ensure formats match exactly

#### 3.3 Bridge Table Population
- **Expected**: `FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` is included in `SP_POPULATE_FACTLESS_BRIDGE`
- **Validation**: Check if stored procedure includes this fact table
- **Query**: Verify stored procedure includes UNION clause for this fact

### Edge Cases

#### 3.4 NULL ASIN Handling
- **Fact**: Uses `COALESCE(ASIN, 'NULL')` in factless_key
- **Bridge**: Uses `COALESCE(asin, 'UNKNOWN')` in factless_key
- **Issue**: NULL ASINs create different keys: `YYYYMMDD-NULL` vs `YYYYMMDD-UNKNOWN`
- **Validation**: Check if NULL ASIN handling is consistent

#### 3.5 Date Key Conversion
- **Fact**: `Reporting_Date` (DATE) → `FORMAT_DATE('%Y%m%d', ...)` → STRING
- **Bridge**: `date_key` (INT64) → `CAST(... AS STRING)` → STRING
- **Validation**: Ensure both produce same YYYYMMDD format

### Validation Criteria
✅ **PASS**: All factless_keys from fact table exist in bridge table  
❌ **FAIL**: Any factless_keys in fact table don't exist in bridge table

---

## Summary of Test Cases

| Test Case | Purpose | Expected Result | Critical? |
|-----------|---------|-----------------|-----------|
| 1.1 | Row count match | STG count = FACT count | ✅ Yes |
| 1.2 | No missing rows | 0 missing rows | ✅ Yes |
| 1.3 | No duplicates | 0 duplicate rows | ✅ Yes |
| 1.4 | Data accuracy | All values match | ✅ Yes |
| 1.5 | Key calculation | Keys formatted correctly | ✅ Yes |
| 2.1 | ad_key referential integrity | All view ad_keys exist in fact | ✅ Yes |
| 2.2 | Date alignment | Dates align correctly | ⚠️ Warning |
| 2.3 | NULL handling | NULL handling consistent | ⚠️ Warning |
| 3.1 | factless_key referential integrity | All fact factless_keys exist in bridge | ✅ Yes |
| 3.2 | Key format match | Formats match exactly | ✅ Yes |
| 3.3 | Bridge population | Fact included in bridge procedure | ✅ Yes |
| 3.4 | NULL ASIN handling | NULL handling consistent | ⚠️ Warning |

---

## What "Correct" Looks Like

**PASS**:
- ✅ All rows from STG loaded into FACT (no missing)
- ✅ No duplicate primary keys in FACT
- ✅ All ad_keys from view exist in fact table
- ✅ All factless_keys from fact exist in bridge table
- ✅ Key formats match exactly

**FAIL**:
- ❌ Missing rows in FACT (data loss)
- ❌ Duplicate rows in FACT (data quality issue)
- ❌ ad_keys in view don't exist in fact (referential integrity broken)
- ❌ factless_keys in fact don't exist in bridge (referential integrity broken)
- ❌ Key format mismatches (join failures)

---

## Known Issues to Watch For

1. **Date Alignment**: View uses `week_end_date`, fact uses `Reporting_Date` - may not align
2. **NULL Handling**: View doesn't use COALESCE('NULL'), fact does - key format may differ
3. **Bridge Population**: Ensure `SP_POPULATE_FACTLESS_BRIDGE` includes `FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
4. **NULL ASIN**: Fact uses 'NULL', bridge uses 'UNKNOWN' - may cause mismatches

---

## Next Steps

After defining expected results, create automated tests that:
1. Query actual row counts and compare
2. Check for missing rows using LEFT JOINs
3. Check for duplicates using GROUP BY
4. Verify referential integrity using LEFT JOINs
5. Report PASS/FAIL with actual counts and examples
