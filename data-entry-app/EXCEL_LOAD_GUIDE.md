# Excel Data Loading Guide

This guide explains how to load historic data from Excel files into BigQuery.

## Prerequisites

1. Install required Python packages:
```bash
cd data-entry-app
source ../.venv/bin/activate  # or your virtual environment
pip install -r requirements.txt
```

2. Ensure you have BigQuery authentication set up (same as the Flask app)

## Excel File Format

### Purchase Orders (orders)

Required columns:
- `order_date` - Date (YYYY-MM-DD format or Excel date)
- `manufacturer_name` - Text (e.g., "SYLVIA")
- `quantity` - Number
- `total_amount` - Number (total amount, unit_price will be calculated)

Optional columns:
- `purchase_order_id` - Text (if not provided, will be auto-generated)
- `product_id` - Number (must match DIM_PRODUCT.product_id)
- `product_asin` - Text (can use instead of product_id)
- `product_sku` - Text (can use instead of product_id)
- `currency` - Text (defaults to "USD")
- `payment_status` - Text (defaults to "PENDING")
- `notes` - Text

**Note:** For product lookup, provide ONE of: `product_id`, `product_asin`, or `product_sku`

### Shipments (shipments)

Required columns:
- `purchase_order_id` - Text (must match existing PO)
- `shipment_date` - Date
- `quantity_shipped` - Number
- `cost_shipped` - Number

Optional columns:
- `shipment_id` - Text (if not provided, will be auto-generated)
- `estimated_arrival_date` - Date
- `tracking_number` - Text
- `shipment_type` - Text ("SLOW_SEA", "FAST_SEA", or "AIR")
- `kg_price` - Number
- `is_paid` - Boolean or Text ("Yes"/"No", "True"/"False")
- `paid_date` - Date
- `shipment_status` - Text (defaults to "PENDING")
- `notes` - Text

**Note:** `unit_cost` will be automatically calculated as `cost_shipped / quantity_shipped`

### Payments (payments)

Required columns:
- `purchase_order_id` - Text (must match existing PO)
- `payment_date` - Date
- `payment_amount` - Number
- `vendor_name` - Text (e.g., "SYLVIA" or "SYLVIA,ANNA" for multiple)

Optional columns:
- `payment_id` - Text (if not provided, will be auto-generated)
- `bank_fee` - Number
- `currency` - Text (defaults to "USD")
- `payment_method` - Text
- `notes` - Text

## Usage

### Basic Usage

```bash
# Load purchase orders
python load_excel_data.py --file orders.xlsx --type orders

# Load shipments
python load_excel_data.py --file shipments.xlsx --type shipments

# Load payments
python load_excel_data.py --file payments.xlsx --type payments
```

### Advanced Usage

```bash
# Specify sheet name
python load_excel_data.py --file data.xlsx --type orders --sheet "Purchase Orders"

# Dry run (validate without inserting)
python load_excel_data.py --file orders.xlsx --type orders --dry-run
```

### Examples

1. **Load orders from first sheet:**
```bash
python load_excel_data.py --file historic_orders.xlsx --type orders
```

2. **Load shipments from specific sheet:**
```bash
python load_excel_data.py --file historic_data.xlsx --type shipments --sheet "Shipments"
```

3. **Validate data before loading:**
```bash
python load_excel_data.py --file payments.xlsx --type payments --dry-run
```

## Excel File Tips

1. **Date Format:** Use Excel date format or YYYY-MM-DD text format
2. **Headers:** First row should contain column names (exactly as listed above)
3. **Empty Cells:** Optional fields can be left empty
4. **Multiple Sheets:** Use `--sheet` parameter to specify which sheet to load
5. **Product Lookup:** The script will automatically look up products from DIM_PRODUCT table

## Error Handling

The script will:
- Validate all required fields
- Check data types
- Look up products automatically
- Report errors row-by-row
- Continue processing even if some rows have errors

## Batch Loading

The script uses BigQuery batch loading (not streaming inserts), which means:
- ✅ Data is immediately available for updates/deletes
- ✅ No streaming buffer delays
- ✅ More reliable for large datasets

## Example Excel Structure

### Purchase Orders Example:

| order_date | manufacturer_name | product_sku | quantity | total_amount | currency | notes |
|------------|-------------------|-------------|----------|--------------|----------|-------|
| 2024-01-15 | SYLVIA | Mint LolliME | 100 | 5000.00 | USD | First order |
| 2024-01-20 | SYLVIA | Mint LolliME | 200 | 10000.00 | USD | |

### Shipments Example:

| purchase_order_id | shipment_date | quantity_shipped | cost_shipped | shipment_type | is_paid | paid_date |
|-------------------|---------------|-------------------|--------------|---------------|---------|-----------|
| PO_abc123 | 2024-01-20 | 100 | 2000.00 | FAST_SEA | Yes | 2024-01-25 |
| PO_abc123 | 2024-02-01 | 100 | 2000.00 | SLOW_SEA | No | |

### Payments Example:

| purchase_order_id | payment_date | payment_amount | vendor_name | payment_method | bank_fee |
|-------------------|--------------|----------------|-------------|----------------|----------|
| PO_abc123 | 2024-01-25 | 5000.00 | SYLVIA | Bank Leumi Business | 10.00 |
| PO_abc123 | 2024-02-10 | 5000.00 | SYLVIA | Account Payoneer | |

## Troubleshooting

**Error: "Missing order_date"**
- Make sure the column is named exactly `order_date`
- Check that dates are in valid format

**Error: "Invalid quantity"**
- Ensure quantity is a positive number
- Check for empty cells in required fields

**Error: "Product not found"**
- Verify product exists in DIM_PRODUCT table
- Check that product_id/asin/sku matches exactly
- Ensure product is active (is_active = TRUE)

**Error: "Missing purchase_order_id"**
- For shipments/payments, PO must exist first
- Load orders before loading shipments/payments

## Best Practices

1. **Start with a dry run** to validate your data format
2. **Load orders first**, then shipments, then payments
3. **Use consistent PO IDs** across files if linking shipments/payments
4. **Keep backups** of your Excel files
5. **Test with small files first** before loading large datasets
