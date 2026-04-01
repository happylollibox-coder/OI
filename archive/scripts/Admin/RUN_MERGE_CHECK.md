# How to Run Merge Feasibility Check

Due to environment restrictions, please run the queries manually in BigQuery Console.

## Option 1: BigQuery Console (Recommended)

1. Open [BigQuery Console](https://console.cloud.google.com/bigquery)
2. Select your project: `onyga-482313`
3. Open the file: `scripts/Admin/check_merge_feasibility.sql`
4. Copy and paste each query section into the BigQuery editor
5. Run each query sequentially

## Option 2: Using bq Command Line

If you have `bq` CLI properly configured:

```bash
cd /Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI
bq query --use_legacy_sql=false < scripts/Admin/check_merge_feasibility.sql
```

## Option 3: Extract Individual Queries

The SQL file contains 4 main queries. You can run them individually:

### Query 1: Merge Feasibility Summary
Lines 13-96 in `check_merge_feasibility.sql`

### Query 2: Column Comparison  
Lines 101-134 in `check_merge_feasibility.sql`

### Query 3: Data Overlap Analysis
Lines 139-182 in `check_merge_feasibility.sql`

### Query 4: Sample Data (2 queries)
Lines 188-203 and 206-216 in `check_merge_feasibility.sql`

## What to Look For

After running the queries, check:

1. **Feasibility Status**: Should show ✅ HIGHLY MERGEABLE, ⚠️ MERGEABLE WITH MAPPING, etc.
2. **Common Keys**: Should show `has_year_key`, `has_week_key`, `has_asin_key` = 1 if keys exist
3. **Column Overlap**: Check how many columns are in BOTH tables vs unique to each
4. **Data Overlap**: Check `overlapping_records` and `overlap_pct` to see how much data overlaps

## Next Steps

Once you have the results:
- If **HIGHLY MERGEABLE**: Proceed with JOIN merge strategy
- If **MERGEABLE WITH MAPPING**: Create column mapping and use JOIN
- If **PARTIALLY MERGEABLE**: Consider UNION strategy
- If **NOT MERGEABLE**: Review schema differences and plan transformation

See `MERGE_FEASIBILITY_GUIDE.md` for detailed interpretation guide.
