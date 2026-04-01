# SP_MERGE_SCP_WEEKLY Stored Procedure

## Overview

This stored procedure merges weekly ASIN performance data from OpenBridge (`openbridge-482712.DB.sp_ba_search_catalog_by_week_v1`) into the staging table `STG_SCP_WEEKLY` using a simple upsert pattern.

## Purpose

- **Source**: `openbridge-482712.DB.sp_ba_search_catalog_by_week_v1`
- **Target**: `onyga-482313.OI.STG_SCP_WEEKLY`
- **Pattern**: Simple upsert - Updates existing records, inserts new ones

## Key Features

### 1. Simple Upsert
The procedure performs a straightforward MERGE:
- Updates existing records with latest data (no change detection)
- Inserts new records for new ASIN/Year/Week combinations

### 2. Time Dimension Extraction
- Extracts `Year` and `Week` from `ob_date` for compatibility with SCP structure
- Calculates `week_start_date` (Monday) and `week_end_date` (Sunday)

### 3. Audit Fields
- `created_at`: Timestamp when record was first inserted
- `updated_at`: Timestamp when record was last updated (updated on every merge)

## Table Structure

### Primary Key
- `ASIN` (STRING)
- `Year` (INT64) - Extracted from ob_date
- `Week` (INT64) - Extracted from ob_date
- `ob_date` (DATE) - Original date from source

### Metrics Included
- **Impressions**: count, median price, shipping speed breakdowns
- **Clicks**: count, click rate, median price, shipping speed breakdowns
- **Cart Adds**: count, median price, shipping speed breakdowns
- **Purchases**: count, conversion rate, median price, sales amount, shipping speed breakdowns

### Metadata
- `ob_file_name`, `ob_marketplace_id`, `ob_seller_id`, `ob_transaction_id`
- `ob_modified_date`, `ob_processed_at`

## Usage

### Manual Execution
```sql
CALL `onyga-482313.OI.SP_MERGE_SCP_WEEKLY`();
```

### Via Orchestrator
The procedure is automatically called by `SP_ORCHESTRATE_DAILY_REFRESH`:
```sql
CALL `onyga-482313.OI.SP_ORCHESTRATE_DAILY_REFRESH`();
```

## How It Works

1. **Source Query**: Extracts data from OpenBridge table with Year/Week calculated
2. **MERGE Operation**: 
   - Matches on `ASIN`, `Year`, `Week`, and `ob_date`
   - **WHEN MATCHED**: Updates all fields with latest data (no change detection)
   - **WHEN NOT MATCHED**: Inserts new record
3. **Logging**: Reports total rows affected

## Example Output

```
SP_MERGE_SCP_WEEKLY completed:
  Total rows affected: 1250
  Duration: 12 seconds
  Completed at: 2025-01-15 10:30:45
```

## Deployment

### 1. Create the Staging Table
```bash
bq query --use_legacy_sql=false < scripts/bigquery/tables/STG/STG_SCP_WEEKLY.sql
```

### 2. Create the Stored Procedure
```bash
bq query --use_legacy_sql=false < scripts/bigquery/procedures/SP_MERGE_SCP_WEEKLY.sql
```

### 3. Verify in Orchestrator
The procedure is already added to `SP_ORCHESTRATE_DAILY_REFRESH` as Task 2.

## Monitoring

### Check Recent Updates
```sql
SELECT 
  COUNT(*) as total_records,
  COUNTIF(updated_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)) as modified_last_24h,
  COUNTIF(created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)) as created_last_24h,
  MIN(ob_date) as earliest_date,
  MAX(ob_date) as latest_date
FROM `onyga-482313.OI.STG_SCP_WEEKLY`;
```

### Check Data Quality
```sql
SELECT 
  Year,
  Week,
  COUNT(DISTINCT ASIN) as unique_asins,
  SUM(impression_data_impression_count) as total_impressions,
  SUM(click_data_click_count) as total_clicks,
  SUM(purchase_data_purchase_count) as total_purchases
FROM `onyga-482313.OI.STG_SCP_WEEKLY`
GROUP BY Year, Week
ORDER BY Year DESC, Week DESC
LIMIT 10;
```

## Notes

1. **Week Calculation**: Uses ISO week standard (Monday = start of week)
2. **Simple Upsert**: Always updates matched records with latest data (no change detection)
3. **Performance**: Partitioned by Year, clustered by ASIN, Year, Week for optimal query performance
4. **Idempotency**: Safe to run multiple times - always reflects latest source data

## Related Files

- `scripts/bigquery/tables/STG/STG_SCP_WEEKLY.sql` - Table definition
- `scripts/bigquery/procedures/SP_MERGE_SCP_WEEKLY.sql` - Stored procedure
- `scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql` - Orchestrator (includes this SP)
