# FACT_INVENTORY_SNAPSHOT Table

## Overview
Fact table that combines inventory snapshot data from `V_UNIFIED_INVENTORY_SNAPSHOT` with purchase order financial data from `FACT_PURCHASE_ORDER`.

## Purpose
Provides a unified view of inventory quantities with associated COGS and selling price amounts from purchase orders.

## Schema

### Fields from V_UNIFIED_INVENTORY_SNAPSHOT
- `Date` (DATE): Snapshot date
- `ASIN` (STRING): Product ASIN
- `quantity_balance` (INT64): Ending warehouse balance
- `source_type` (STRING): Source of inventory data ('FBA' or 'AWD')

### Additional Fields
- `COGS_AMOUNT` (FLOAT64): Total COGS from purchase orders
  - Calculated as: `SUM(cogs_remaining_at_manufacturer + cogs_remaining_at_shipment)` per Date/ASIN
- `SELL_AMOUNT` (FLOAT64): Total selling price from purchase orders
  - Calculated as: `SUM(selling_price_remaining_at_manufacturer + selling_price_remaining_at_shipment)` per Date/ASIN
- `loaded_at` (TIMESTAMP): When the row was loaded

## Data Population

### Stored Procedure: `SP_LOAD_FACT_INVENTORY_SNAPSHOT`

**Purpose**: Populate `FACT_INVENTORY_SNAPSHOT` from `V_UNIFIED_INVENTORY_SNAPSHOT` and `FACT_PURCHASE_ORDER`.

**Business Logic**:
1. Starts with all rows from `V_UNIFIED_INVENTORY_SNAPSHOT`
2. Left joins to `FACT_PURCHASE_ORDER` on:
   - `Date = snapshot_date`
   - `ASIN = product_asin`
3. Aggregates purchase order data per Date/ASIN:
   - `COGS_AMOUNT` = sum of `(cogs_remaining_at_manufacturer + cogs_remaining_at_shipment)`
   - `SELL_AMOUNT` = sum of `(selling_price_remaining_at_manufacturer + selling_price_remaining_at_shipment)`
4. Only includes purchase order snapshots that exist in `V_UNIFIED_INVENTORY_SNAPSHOT` (matching Date and ASIN)

**Usage**:
```sql
CALL `onyga-482313.OI.SP_LOAD_FACT_INVENTORY_SNAPSHOT`();
```

## Field Mapping

The following mapping explains how purchase order fields are aggregated:

- `quantity_remaining_at_manufacturer + quantity_remaining_at_shipment` → represents `quantity_balance` (conceptually, though `quantity_balance` comes from the view)
- `cogs_remaining_at_manufacturer + cogs_remaining_at_shipment` → `COGS_AMOUNT`
- `selling_price_remaining_at_manufacturer + selling_price_remaining_at_shipment` → `SELL_AMOUNT`

## Notes

- The table is partitioned by `Date` and clustered by `ASIN` and `source_type` for optimal query performance
- The stored procedure deletes existing rows for dates that will be reloaded to ensure idempotency
- If there are no matching Date/ASIN combinations between the view and `FACT_PURCHASE_ORDER`, `COGS_AMOUNT` and `SELL_AMOUNT` will be 0
- This is expected when inventory snapshots and purchase order snapshots are on different dates

## Dependencies

- `V_UNIFIED_INVENTORY_SNAPSHOT` (view)
- `FACT_PURCHASE_ORDER` (table)
