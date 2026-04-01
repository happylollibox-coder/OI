# Stored Procedure: SP_DATA_ENTRY_UPDATES

## Overview

Loads data from `V_PO_SNAPSHOT` view into staging and fact tables for all snapshots (2 calendar years: month-end dates + current date), calculating new fields (LAST_PAYMENT_DATE, LAST_SHIPMENT_DATE, etc.) based on payment and shipment data as of each snapshot date.

**Note**: `DE_PURCHASE_ORDERS` is NOT modified by this procedure - it is used for data entry only.

## Calculated Fields (in STG and FACT tables)

These fields are calculated when loading data into `STG_PURCHASE_ORDER`:

### 1. LAST_PAYMENT_DATE
- **Condition**: All payments are paid (total_paid >= total_amount) as of snapshot date
- **Value**: Maximum `payment_date` from `DE_VENDOR_PAYMENTS` where `payment_date <= snapshot_date`
- **Logic**: Only set when PO is fully paid as of the snapshot date, otherwise NULL

### 2. LAST_SHIPMENT_DATE
- **Condition**: All shipments are created (total_quantity_shipped >= PO quantity) as of snapshot date
- **Value**: Maximum `shipment_date` from `DE_MANUFACTURER_SHIPMENTS` where `shipment_date <= snapshot_date`
  - **Special logic**: If shipment `is_paid=true` and `paid_date IS NULL`, use `shipment_date + 30 days`
- **Logic**: Only set when all expected quantities have been shipped as of the snapshot date, otherwise NULL

### 3. LAST_ESTIMATED_ARRIVAL_DATE
- **Condition**: Always calculated if shipments exist as of snapshot date
- **Value**: Maximum `estimated_arrival_date` from `DE_MANUFACTURER_SHIPMENTS` where `shipment_date <= snapshot_date`
- **Logic**: Set to max estimated arrival date if shipments exist as of the snapshot date, otherwise NULL

### 4. END_DATE
- **Condition**: Both LAST_PAYMENT_DATE and LAST_SHIPMENT_DATE are set (not NULL)
- **Value**: Greatest of:
  - LAST_PAYMENT_DATE
  - LAST_SHIPMENT_DATE
  - Maximum `estimated_arrival_date`
- **Logic**: Only set when both payments and shipments are complete, otherwise NULL

## Usage

```sql
-- Run the stored procedure directly
CALL `onyga-482313.OI.SP_DATA_ENTRY_UPDATES`();

-- Or run via orchestrator (recommended for scheduled runs)
CALL `onyga-482313.OI.SP_ORCHESTRATE_DAILY_REFRESH`();
```

**Note**: This procedure is included in `SP_ORCHESTRATE_DAILY_REFRESH` as Task 5.

## When to Run

- After inserting/updating payments in `DE_VENDOR_PAYMENTS`
- After inserting/updating shipments in `DE_MANUFACTURER_SHIPMENTS`
- After updating PO quantities or amounts in `DE_PURCHASE_ORDERS`
- As a scheduled job (e.g., daily) to keep fields up-to-date

## Example: Schedule Daily Execution

```sql
-- Create a scheduled query in BigQuery
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SCHEDULED_DATA_ENTRY_UPDATES`()
BEGIN
  CALL `onyga-482313.OI.SP_DATA_ENTRY_UPDATES`();
END;
```

## Data Flow

The procedure follows this flow:

1. **Truncate STG_PURCHASE_ORDER** (Step 1)
   - Clears the staging table to prepare for new data

2. **Load STG_PURCHASE_ORDER from V_PO_SNAPSHOT** (Step 2)
   - Inserts all snapshots (2 calendar years: month-end dates + current date) from `V_PO_SNAPSHOT` view
   - Calculates payment and shipment summaries as of each snapshot date (not just current date)
   - **Calculates new fields** based on payment and shipment data:
     - LAST_PAYMENT_DATE
     - LAST_SHIPMENT_DATE
     - LAST_ESTIMATED_ARRIVAL_DATE
     - END_DATE
   - Includes all calculated fields from view: payments_remaining, quantity_remaining, cogs_remaining, selling_price_remaining, etc.

3. **Delete existing rows from FACT_PURCHASE_ORDER** (Step 3)
   - Deletes all rows from `FACT_PURCHASE_ORDER` that have the same `snapshot_date` as the data in `STG_PURCHASE_ORDER`
   - Prevents duplicate snapshots for the same date
   - Ensures idempotency (can run multiple times on the same day)

4. **Insert into FACT_PURCHASE_ORDER** (Step 4)
   - Inserts all data from `STG_PURCHASE_ORDER` into `FACT_PURCHASE_ORDER`
   - Creates daily snapshots for historical tracking

**Important**: `DE_PURCHASE_ORDERS` is NOT modified by this procedure. It remains unchanged for data entry purposes.

## Tables

### STG_PURCHASE_ORDER
- **Purpose**: Staging table for all snapshot data (2 calendar years: month-end dates + current date)
- **Source**: `V_PO_SNAPSHOT` view (all snapshots: month-end dates + current date)
- **Lifecycle**: Truncated and reloaded on each SP run
- **Partitioning**: Partitioned by `snapshot_date`
- **Clustering**: Clustered by `manufacturer_name` and `order_date`

### FACT_PURCHASE_ORDER
- **Purpose**: Fact table storing historical snapshots of PO state (2 calendar years: month-end dates + current date)
- **Source**: `STG_PURCHASE_ORDER` table
- **Snapshot Date**: Uses `CURRENT_DATE()` to track when the snapshot was taken
- **Partitioning**: Partitioned by `snapshot_date` for efficient querying
- **Clustering**: Clustered by `manufacturer_name` and `order_date`

This allows you to track historical states of POs over time by querying different `snapshot_date` values.

## Notes

- The procedure uses `MERGE` statement for efficient updates
- Only updates rows where there are changes
- Updates `updated_at` timestamp automatically
- Handles POs with only payments, only shipments, or both
- Creates daily snapshots in `FACT_ORDERS` table for historical tracking
