# Purchase Order Snapshot View

## Overview

Creates a snapshot view (`V_PO_SNAPSHOT`) that tracks Purchase Order state at specific points in time over the last 2 calendar years.

## Snapshot Dates

Snapshots are taken at:
- **Month-end dates**: Last day of each month
- **Current date**: Today's date

## Time Range

- **Last 2 calendar years**: From 2 years ago to today
- Uses `DIM_TIME` table to generate snapshot dates

## PO Inclusion Logic

A PO is included in a snapshot if:
- `snapshot_date >= order_date` (PO has started)
- `snapshot_date <= END_DATE` OR `END_DATE IS NULL` (PO is still active or completed)

## Fields

### Snapshot Metadata
- `snapshot_date`: Date of the snapshot
- `year`, `month`, `quarter`: Time dimensions
- `is_current_date`: TRUE if snapshot is today
- `is_month_end`: TRUE if snapshot is month-end

### All PO Fields
All columns from `DE_PURCHASE_ORDERS`:
- `purchase_order_id`
- `order_date`
- `manufacturer_name`
- `product_name`
- `product_asin`
- `quantity`
- `unit_price`
- `total_amount`
- `currency`
- `payment_status`
- `notes`
- `created_at`
- `LAST_PAYMENT_DATE`
- `LAST_SHIPMENT_DATE`
- `LAST_ESTIMATED_ARRIVAL_DATE`
- `END_DATE`

### Calculated Fields (as of snapshot_date)

1. **payments_remaining**
   - Formula: `total_amount - SUM(payments made up to snapshot_date)`
   - Shows how much is still owed as of the snapshot date

2. **quantity_remaining**
   - Formula: `quantity - SUM(quantities shipped up to snapshot_date)`
   - Shows how many units are still to be shipped as of the snapshot date

3. **cogs_remaining**
   - Formula: `quantity_remaining * cost_of_goods` (from DIM_PRODUCT)
   - Shows the remaining Cost of Goods Sold value for unshiped units

4. **selling_price_remaining**
   - Formula: `quantity_remaining * listing_price_amount` (from DIM_PRODUCT)
   - Shows the remaining selling price value for unshiped units

3. **is_fully_paid_as_of_snapshot** (convenience field)
   - TRUE if `payments_remaining <= 0`

4. **is_fully_shipped_as_of_snapshot** (convenience field)
   - TRUE if `quantity_remaining <= 0`

5. **is_complete_as_of_snapshot** (convenience field)
   - TRUE if both payments and shipments are complete

## Usage Examples

```sql
-- Get current state of all active POs
SELECT *
FROM `onyga-482313.OI.V_PO_SNAPSHOT`
WHERE is_current_date = TRUE
ORDER BY purchase_order_id;

-- Get month-end snapshots for a specific PO
SELECT 
  snapshot_date,
  payments_remaining,
  quantity_remaining,
  is_fully_paid_as_of_snapshot,
  is_fully_shipped_as_of_snapshot
FROM `onyga-482313.OI.V_PO_SNAPSHOT`
WHERE purchase_order_id = 'PO_20250510_Purple_Box_1_2704'
ORDER BY snapshot_date DESC;

-- Get all POs with remaining payments at last month-end
SELECT 
  purchase_order_id,
  manufacturer_name,
  product_name,
  total_amount,
  payments_remaining,
  quantity_remaining,
  cogs_remaining,
  selling_price_remaining
FROM `onyga-482313.OI.V_PO_SNAPSHOT`
WHERE is_month_end = TRUE
  AND snapshot_date = (
    SELECT MAX(snapshot_date) 
    FROM `onyga-482313.OI.V_PO_SNAPSHOT` 
    WHERE is_month_end = TRUE
  )
  AND payments_remaining > 0
ORDER BY payments_remaining DESC;

-- Get total COGS and selling price remaining across all POs
SELECT 
  snapshot_date,
  SUM(quantity_remaining) AS total_quantity_remaining,
  SUM(cogs_remaining) AS total_cogs_remaining,
  SUM(selling_price_remaining) AS total_selling_price_remaining
FROM `onyga-482313.OI.V_PO_SNAPSHOT`
WHERE is_current_date = TRUE
GROUP BY snapshot_date;

-- Track payment progress over time for a PO
SELECT 
  snapshot_date,
  total_amount,
  payments_remaining,
  total_amount - payments_remaining AS total_paid_as_of_snapshot
FROM `onyga-482313.OI.V_PO_SNAPSHOT`
WHERE purchase_order_id = 'PO_20250510_Purple_Box_1_2704'
ORDER BY snapshot_date;
```

## Deployment

```bash
bq query --use_legacy_sql=false < scripts/bigquery/views/V_PO_SNAPSHOT.sql
```

## Notes

- The view is calculated on-the-fly, so it always reflects current data
- Snapshot dates are generated from `DIM_TIME` table
- POs are filtered by `order_date` (start) and `END_DATE` (end) from `DE_PURCHASE_ORDERS`
- Payments and shipments are filtered by their respective dates (`payment_date` and `shipment_date`)
