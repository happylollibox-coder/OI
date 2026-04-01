# FACT_FACTLESS_BRIDGE - Factless Fact Table Documentation

## Overview

`FACT_FACTLESS_BRIDGE` is a **factless fact table** (also called a bridge table or junction table) that links multiple fact tables together through common dimensions (Time and Product). This enables unified analysis across different business processes.

## What is a Factless Fact Table?

A factless fact table contains **only foreign keys** (no measures/facts). It's used to:
- Track relationships between facts
- Identify which facts have data for a given product/date combination
- Enable joins across multiple fact tables
- Analyze data completeness and gaps

## Current Facts Linked

1. **FACT_INVENTORY_SNAPSHOT** - Inventory levels by date/product
2. **FACT_FINANCIAL_TRANSACTIONS** - Financial transactions
3. **FACT_PURCHASE_ORDER** - Purchase orders

## Schema Structure

### Key Fields

| Field | Type | Description |
|-------|------|-------------|
| `date_key` | INT64 | Foreign key to `TimeDIM.date_key` (YYYYMMDD format) |
| `full_date` | DATE | Denormalized date for convenience |
| `product_id` | INT64 | Foreign key to `DIM_PRODUCT.product_id` |
| `asin` | STRING | Denormalized ASIN for convenience |

### Existence Flags

| Flag | Description |
|------|-------------|
| `has_inventory_snapshot` | TRUE if FACT_INVENTORY_SNAPSHOT has data for this product/date |
| `has_financial_transaction` | TRUE if FACT_FINANCIAL_TRANSACTIONS has data for this product/date |
| `has_purchase_order` | TRUE if FACT_PURCHASE_ORDER has data for this product/date |

### Record Counts

| Count | Description |
|-------|-------------|
| `inventory_snapshot_count` | Number of inventory records for this product/date |
| `financial_transaction_count` | Number of financial transactions for this product/date |
| `purchase_order_count` | Number of purchase orders for this product/date |

## Population

### Stored Procedure

Use `SP_POPULATE_FACTLESS_BRIDGE` to populate the table:

```sql
-- Populate for a date range
CALL `onyga-482313.OI.SP_POPULATE_FACTLESS_BRIDGE`('2024-01-01', '2024-12-31');

-- Populate for current month
CALL `onyga-482313.OI.SP_POPULATE_FACTLESS_BRIDGE`(
  DATE_TRUNC(CURRENT_DATE(), MONTH),
  LAST_DAY(CURRENT_DATE())
);
```

### How It Works

1. Extracts all unique (date, product) combinations from all fact tables
2. Resolves `product_id` via `DIM_PRODUCT` using ASIN
3. Sets existence flags based on which facts have data
4. Counts records per combination
5. Stores foreign key references (first value if multiple exist)

## Usage Examples

### 1. Find Products with Inventory but No Purchase Orders

```sql
SELECT 
  b.full_date,
  b.asin,
  p.product_name,
  i.quantity_balance
FROM `onyga-482313.OI.FACT_FACTLESS_BRIDGE` b
JOIN `onyga-482313.OI.DIM_PRODUCT` p ON b.product_id = p.product_id
LEFT JOIN `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT` i
  ON b.full_date = i.Date AND b.asin = i.ASIN
WHERE b.has_inventory_snapshot = TRUE
  AND b.has_purchase_order = FALSE
  AND b.full_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY);
```

### 2. Join All Facts Together

```sql
SELECT 
  b.date_key,
  t.full_date,
  p.asin,
  p.product_name,
  i.quantity_balance,
  f.amount AS financial_amount,
  po.total_amount AS po_amount
FROM `onyga-482313.OI.FACT_FACTLESS_BRIDGE` b
JOIN `onyga-482313.OI.TimeDIM` t ON b.date_key = t.date_key
JOIN `onyga-482313.OI.DIM_PRODUCT` p ON b.product_id = p.product_id
LEFT JOIN `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT` i
  ON b.full_date = i.Date AND b.asin = i.ASIN
LEFT JOIN `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS` f
  ON b.full_date = f.transaction_date
  AND JSON_EXTRACT_SCALAR(f.source_metadata, '$.asin') = b.asin
LEFT JOIN `onyga-482313.OI.FACT_PURCHASE_ORDER` po
  ON b.full_date = po.snapshot_date AND b.asin = po.product_asin
WHERE b.full_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY);
```

### 3. Analyze Data Completeness

```sql
SELECT 
  t.full_date,
  COUNT(*) AS total_combinations,
  SUM(CASE WHEN b.has_inventory_snapshot THEN 1 ELSE 0 END) AS with_inventory,
  SUM(CASE WHEN b.has_financial_transaction THEN 1 ELSE 0 END) AS with_financial,
  SUM(CASE WHEN b.has_purchase_order THEN 1 ELSE 0 END) AS with_po,
  SUM(CASE WHEN b.has_inventory_snapshot 
           AND b.has_financial_transaction 
           AND b.has_purchase_order THEN 1 ELSE 0 END) AS with_all_facts
FROM `onyga-482313.OI.FACT_FACTLESS_BRIDGE` b
JOIN `onyga-482313.OI.TimeDIM` t ON b.date_key = t.date_key
WHERE b.full_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY t.full_date
ORDER BY t.full_date DESC;
```

### 4. Find Products Missing Financial Data

```sql
SELECT 
  b.asin,
  p.product_name,
  COUNT(*) AS days_without_financial
FROM `onyga-482313.OI.FACT_FACTLESS_BRIDGE` b
JOIN `onyga-482313.OI.DIM_PRODUCT` p ON b.product_id = p.product_id
WHERE b.has_inventory_snapshot = TRUE
  AND b.has_financial_transaction = FALSE
  AND b.full_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY b.asin, p.product_name
ORDER BY days_without_financial DESC;
```

## Extending for New Facts

When adding a new fact table, follow this pattern:

### 1. Add Fields to FACT_FACTLESS_BRIDGE

```sql
ALTER TABLE `onyga-482313.OI.FACT_FACTLESS_BRIDGE`
ADD COLUMN has_sales_order BOOL NOT NULL DEFAULT FALSE,
ADD COLUMN sales_order_count INT64 DEFAULT 0,
ADD COLUMN sales_order_id STRING;
```

### 2. Update SP_POPULATE_FACTLESS_BRIDGE

Add a CTE for the new fact table:

```sql
sales_order_keys AS (
  SELECT DISTINCT
    CAST(FORMAT_DATE('%Y%m%d', order_date) AS INT64) AS date_key,
    order_date AS full_date,
    product_id,
    product_asin AS asin,
    TRUE AS has_sales,
    COUNT(*) AS sales_count,
    ARRAY_AGG(DISTINCT sales_order_id LIMIT 1)[OFFSET(0)] AS so_id
  FROM `onyga-482313.OI.FACT_SALES_ORDER`
  WHERE order_date BETWEEN start_date AND end_date
    AND product_asin IS NOT NULL
  GROUP BY date_key, full_date, product_id, asin
),
```

### 3. Update UNION in all_keys

```sql
UNION DISTINCT

SELECT 
  date_key,
  full_date,
  asin
FROM sales_order_keys
WHERE asin IS NOT NULL
```

### 4. Update Final SELECT

```sql
COALESCE(so.has_sales, FALSE) AS has_sales_order,
COALESCE(so.sales_count, 0) AS sales_order_count,
so.so_id AS sales_order_id,
```

And add the LEFT JOIN:

```sql
LEFT JOIN sales_order_keys so
  ON ak.date_key = so.date_key
  AND ak.asin = so.asin
```

## Best Practices

1. **Regular Population**: Run the stored procedure daily or weekly to keep data current
2. **Incremental Updates**: Use date ranges to update only recent data
3. **Performance**: The table is partitioned by year and clustered for common queries
4. **Data Quality**: Use existence flags to identify data gaps and completeness issues

## Performance Considerations

- **Partitioning**: Table is partitioned by year (`DATE_TRUNC(full_date, YEAR)`)
- **Clustering**: Clustered by `date_key`, `product_id`, `asin`, and existence flags
- **Indexing**: Primary key (not enforced) on `(date_key, product_id, asin)`

## Related Tables

- `TimeDIM` - Time dimension
- `DIM_PRODUCT` - Product dimension
- `FACT_INVENTORY_SNAPSHOT` - Inventory fact
- `FACT_FINANCIAL_TRANSACTIONS` - Financial fact
- `FACT_PURCHASE_ORDER` - Purchase order fact

## Future Enhancements

- Add more fact tables as they are created
- Add aggregation levels (week, month, quarter)
- Add data quality metrics
- Add change tracking (when facts are added/removed)
