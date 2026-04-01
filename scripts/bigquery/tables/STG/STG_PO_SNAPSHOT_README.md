# Purchase Order Snapshot Table

## Overview

Creates a snapshot table (`STG_PO_SNAPSHOT`) that tracks the state of each Purchase Order from start to completion.

## Table Structure

### Key Fields

- **snapshot_date**: Date of the snapshot (from DIM_TIME)
- **purchase_order_id**: PO identifier
- **start_date**: PO order_date (when PO was created)
- **end_date**: When PO is completed (all shipments paid AND all PO payments made)
- **is_active**: TRUE if snapshot_date is between start_date and end_date
- **is_completed**: TRUE if snapshot_date >= end_date

### Remaining Costs (as of snapshot_date)

- `remaining_manufactured_cost`: Remaining cost for manufacture (SYLVIA only)
- `remaining_shipments_cost`: Remaining unpaid shipment costs
- `remaining_shipments_estimated_cost`: Estimated cost for remaining shipments

### Quantities (as of snapshot_date)

- `total_quantity_shipped_as_of_snapshot`
- `remaining_quantity_to_ship_as_of_snapshot`

## End Date Logic

A PO is considered complete (end_date is set) when:
1. **All PO payments are made**: `total_paid >= total_amount`
2. **All shipments are paid**: `total_shipment_paid >= total_shipment_cost`

If either condition is not met, `end_date` is NULL (PO is still active).

## Snapshot Dates

Snapshots are created for:
- Month-end dates (using DIM_TIME)
- Current date
- PO start_date
- PO end_date (if completed)

## Usage Examples

```sql
-- Get current state of all active POs
SELECT *
FROM `onyga-482313.OI.STG_PO_SNAPSHOT`
WHERE is_active = TRUE
  AND snapshot_date = CURRENT_DATE()
ORDER BY purchase_order_id;

-- Get month-end snapshots
SELECT *
FROM `onyga-482313.OI.STG_PO_SNAPSHOT`
WHERE snapshot_date = LAST_DAY(snapshot_date, MONTH)
ORDER BY snapshot_date DESC, purchase_order_id;

-- Track a specific PO over time
SELECT 
  snapshot_date,
  total_paid_as_of_snapshot,
  amount_remaining_as_of_snapshot,
  remaining_shipments_cost_as_of_snapshot,
  is_completed
FROM `onyga-482313.OI.STG_PO_SNAPSHOT`
WHERE purchase_order_id = 'PO_20240101_ABC123_1000'
ORDER BY snapshot_date;
```

## Deployment

```bash
bq query --use_legacy_sql=false < scripts/bigquery/tables/STG/STG_PO_SNAPSHOT.sql
```
