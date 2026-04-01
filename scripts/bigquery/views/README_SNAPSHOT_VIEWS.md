# Snapshot Views: Remaining Costs & Quantities

## Overview

These views create monthly snapshots (end of month + current date) for the last 2 calendar years, showing remaining costs and quantities for manufacture, shipments, and shipment estimations.

## Views

### 1. V_SNAPSHOT_REMAINING_COSTS

**Purpose**: Detailed snapshot view with all purchase orders, shipments, and remaining amounts at each snapshot date.

**Snapshot Dates**:
- Month-end dates for the last 2 calendar years
- Current date

**Key Metrics**:
- `remaining_manufactured_cost`: Remaining cost for manufacture (SYLVIA manufacturer)
- `remaining_shipments_cost`: Remaining unpaid shipment costs
- `remaining_shipments_estimated_cost`: Estimated cost for remaining shipments without cost

**Shipment Details Included**:
- All shipment fields for start date calculation
- `start_date`: Uses `shipment_date` as the start date
- `days_until_arrival`: Calculated days until estimated arrival

**Usage Example**:
```sql
-- Get current snapshot
SELECT *
FROM `onyga-482313.OI.V_SNAPSHOT_REMAINING_COSTS`
WHERE is_current_date = TRUE
ORDER BY purchase_order_id, shipment_date DESC;

-- Get month-end snapshots
SELECT *
FROM `onyga-482313.OI.V_SNAPSHOT_REMAINING_COSTS`
WHERE is_month_end = TRUE
ORDER BY snapshot_date DESC, purchase_order_id;
```

### 2. V_SNAPSHOT_REMAINING_COSTS_SUMMARY

**Purpose**: Aggregated summary by snapshot date.

**Key Metrics**:
- Total purchase orders and shipments
- Total remaining quantities
- Total remaining costs (USD and other currencies)
- Grand total of all remaining costs

**Usage Example**:
```sql
-- Get summary for all snapshots
SELECT 
  snapshot_date,
  month_key,
  is_current_date,
  total_remaining_manufactured_cost,
  total_remaining_shipments_cost,
  total_remaining_shipments_estimated_cost,
  total_remaining_costs
FROM `onyga-482313.OI.V_SNAPSHOT_REMAINING_COSTS_SUMMARY`
ORDER BY snapshot_date DESC;

-- Compare month-over-month
SELECT 
  month_key,
  total_remaining_costs,
  LAG(total_remaining_costs) OVER (ORDER BY snapshot_date) AS previous_month_total,
  total_remaining_costs - LAG(total_remaining_costs) OVER (ORDER BY snapshot_date) AS change_from_previous
FROM `onyga-482313.OI.V_SNAPSHOT_REMAINING_COSTS_SUMMARY`
WHERE is_month_end = TRUE
ORDER BY snapshot_date DESC;
```

## Deployment

Deploy both views:

```bash
bq query --use_legacy_sql=false < scripts/bigquery/views/V_SNAPSHOT_REMAINING_COSTS.sql
bq query --use_legacy_sql=false < scripts/bigquery/views/V_SNAPSHOT_REMAINING_COSTS_SUMMARY.sql
```

## Notes

- Snapshot dates are generated using `DIM_TIME` table
- Only includes purchase orders created on or before snapshot date
- Only includes payments/shipments that occurred on or before snapshot date
- Shipment estimations use fallback logic: same PO > same product > last 12 months average
- Estimated arrival dates are calculated based on shipment type if not set:
  - SLOW_SEA: +33 days
  - FAST_SEA: +27 days
  - AIR: +10 days
