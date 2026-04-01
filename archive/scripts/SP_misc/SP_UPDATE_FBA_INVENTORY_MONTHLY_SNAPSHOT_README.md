# SP_UPDATE_FBA_INVENTORY_MONTHLY_SNAPSHOT

## Overview

This stored procedure creates and maintains monthly snapshots of FBA inventory summary data. Only the current month's snapshot is updated; previous months remain frozen.

## Purpose

- **Source**: `fivetran-hl.amazon_selling_partner.fba_inventory_summary`
- **Target**: `onyga-482313.OI.STG_FBA_INVENTORY_MONTHLY_SNAPSHOT`
- **Filter**: `granularity_id = 'ATVPDKIKX0DER'`
- **Join**: Left join to `DIM_PRODUCT` on ASIN

## Key Features

### 1. Month-Based Snapshot Logic
- **Current Month**: Updated every time the procedure runs
- **Previous Months**: Frozen (no updates after month changes)
- **New Month**: Automatically inserted when month changes

### 2. Product Dimension Join
- Left joins to `DIM_PRODUCT` on ASIN
- Includes `product_id` for dimensional analysis
- Handles products not yet in dimension table (product_id = NULL)

### 3. Filtering
- Only processes records where `granularity_id = 'ATVPDKIKX0DER'`
- Filters out NULL ASINs

## Table Structure

### Primary Key
- `snapshot_month` (STRING): YYYY-MM format
- `asin` (STRING): Product ASIN
- `fnsku` (STRING): Fulfillment Network SKU

### Month Identifiers
- `snapshot_month`: YYYY-MM format (e.g., '2025-01')
- `snapshot_year`: Year as INT64
- `snapshot_month_num`: Month number (1-12)

### Inventory Fields
The table includes common FBA inventory fields. **Note**: You may need to adjust field names based on the actual `fba_inventory_summary` schema:
- Quantity fields (available, reserved, unfulfillable, total)
- Inbound quantities (working, shipped, receiving)
- Reserved quantities (FC transfers, processing, customer orders)
- Unfulfillable breakdowns (customer damage, warehouse damage, defective, expired, etc.)

## Usage

### Manual Execution
```sql
CALL `onyga-482313.OI.SP_UPDATE_FBA_INVENTORY_MONTHLY_SNAPSHOT`();
```

### Via Orchestrator
The procedure is automatically called by `SP_ORCHESTRATE_DAILY_REFRESH` as Task 4.

## How It Works

1. **Get Current Month**: Extracts current year and month
2. **Source Query**: 
   - Filters `fba_inventory_summary` by `granularity_id = 'ATVPDKIKX0DER'`
   - Left joins to `DIM_PRODUCT` on ASIN
   - Adds month identifiers
3. **MERGE Operation**:
   - **WHEN MATCHED**: Only updates if `snapshot_month` matches current month
   - **WHEN NOT MATCHED**: Inserts new records (new month or new products)

## Important Notes

### Schema Adjustment Required
The stored procedure uses common FBA inventory field names. **You must verify and adjust** the field names in the procedure to match your actual `fba_inventory_summary` table schema.

To check the actual schema:
```sql
SELECT column_name, data_type
FROM `fivetran-hl.amazon_selling_partner.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'fba_inventory_summary'
ORDER BY ordinal_position;
```

### Month Transition Behavior
- When running on the last day of a month: Updates that month's snapshot
- When running on the first day of a new month: Creates new month's snapshot
- Previous months remain unchanged (frozen)

## Example Output

```
SP_UPDATE_FBA_INVENTORY_MONTHLY_SNAPSHOT completed:
  Snapshot Month: 2025-01
  Total rows affected: 1250
  Duration: 8 seconds
  Completed at: 2025-01-15 10:30:45
```

## Monitoring

### Check Current Month Snapshot
```sql
SELECT 
  snapshot_month,
  COUNT(*) as product_count,
  SUM(quantity_total) as total_quantity,
  MIN(snapshot_date) as first_snapshot,
  MAX(snapshot_date) as last_snapshot
FROM `onyga-482313.OI.STG_FBA_INVENTORY_MONTHLY_SNAPSHOT`
WHERE snapshot_month = FORMAT_DATE('%Y-%m', CURRENT_DATE())
GROUP BY snapshot_month;
```

### Check All Months
```sql
SELECT 
  snapshot_month,
  COUNT(*) as product_count,
  COUNT(DISTINCT asin) as unique_asins,
  SUM(quantity_total) as total_quantity,
  MAX(updated_at) as last_updated
FROM `onyga-482313.OI.STG_FBA_INVENTORY_MONTHLY_SNAPSHOT`
GROUP BY snapshot_month
ORDER BY snapshot_month DESC;
```

### Verify Month Freezing
```sql
-- Check that previous months haven't been updated recently
SELECT 
  snapshot_month,
  MAX(updated_at) as last_updated,
  CASE 
    WHEN snapshot_month < FORMAT_DATE('%Y-%m', CURRENT_DATE()) 
    THEN 'FROZEN' 
    ELSE 'ACTIVE' 
  END as status
FROM `onyga-482313.OI.STG_FBA_INVENTORY_MONTHLY_SNAPSHOT`
GROUP BY snapshot_month
ORDER BY snapshot_month DESC;
```

## Deployment

### 1. Create the Snapshot Table
```bash
bq query --use_legacy_sql=false < scripts/Tables/inventory/STG_FBA_INVENTORY_MONTHLY_SNAPSHOT.sql
```

### 2. Verify Source Schema
```sql
-- Check actual field names in source table
SELECT column_name, data_type
FROM `fivetran-hl.amazon_selling_partner.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'fba_inventory_summary'
ORDER BY ordinal_position;
```

### 3. Adjust Field Names (if needed)
Update the stored procedure to match actual field names from step 2.

### 4. Create the Stored Procedure
```bash
bq query --use_legacy_sql=false < scripts/SP/SP_UPDATE_FBA_INVENTORY_MONTHLY_SNAPSHOT.sql
```

### 5. Verify in Orchestrator
The procedure is already added to `SP_ORCHESTRATE_DAILY_REFRESH` as Task 4.

## Related Files

- `scripts/Tables/inventory/STG_FBA_INVENTORY_MONTHLY_SNAPSHOT.sql` - Table definition
- `scripts/SP/SP_UPDATE_FBA_INVENTORY_MONTHLY_SNAPSHOT.sql` - Stored procedure
- `scripts/SP/SP_ORCHESTRATE_DAILY_REFRESH.sql` - Orchestrator (includes this SP)
