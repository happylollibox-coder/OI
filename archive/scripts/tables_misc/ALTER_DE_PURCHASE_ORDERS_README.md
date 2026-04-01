# DE_PURCHASE_ORDERS Table

## Overview

`DE_PURCHASE_ORDERS` is the data entry table for Purchase Orders. It contains only the core PO fields and is **not** modified by any stored procedures.

## Important Notes

- **DO NOT add calculated/accumulated fields to this table**
- Fields like `LAST_PAYMENT_DATE`, `LAST_SHIPMENT_DATE`, `LAST_ESTIMATED_ARRIVAL_DATE`, and `END_DATE` are **NOT** stored in this table
- These calculated fields are stored in:
  - `STG_PURCHASE_ORDER` (staging table)
  - `FACT_PURCHASE_ORDER` (fact table)
- Calculated fields are populated by `SP_DATA_ENTRY_UPDATES` stored procedure

## Current Schema

The table contains only data entry fields:
- `purchase_order_id`
- `order_date`
- `manufacturer_name`
- `product_id`
- `product_asin`
- `product_name`
- `quantity`
- `unit_price`
- `total_amount`
- `currency`
- `payment_status`
- `notes`
- `created_at`

## Related Tables

- **STG_PURCHASE_ORDER**: Staging table with calculated fields (populated from `V_PO_SNAPSHOT`)
- **FACT_PURCHASE_ORDER**: Fact table with historical snapshots (populated from `STG_PURCHASE_ORDER`)
