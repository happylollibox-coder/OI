# Excel Templates for Historic Data Loading

This directory contains Excel template files for loading historic data into BigQuery.

## Available Templates

### With Sample Data (for reference)

1. **`template_purchase_orders.xlsx`**
   - Contains sample purchase order data
   - Shows the expected format and column structure
   - Use as a reference or replace data with your own

2. **`template_shipments.xlsx`**
   - Contains sample shipment data
   - Shows how to link shipments to purchase orders
   - Includes examples of all optional fields

3. **`template_payments.xlsx`**
   - Contains sample payment data
   - Shows how to link payments to purchase orders
   - Includes examples of vendor names and payment methods

4. **`template_all_data.xlsx`**
   - Contains all three types of data in separate sheets
   - Convenient for organizing all historic data in one file
   - Use `--sheet` parameter when loading specific sheets

### Empty Templates (for fresh data entry)

1. **`template_purchase_orders_empty.xlsx`**
   - Empty template with only column headers
   - Perfect for entering new data from scratch

2. **`template_shipments_empty.xlsx`**
   - Empty template with only column headers
   - Ready for your shipment data

3. **`template_payments_empty.xlsx`**
   - Empty template with only column headers
   - Ready for your payment data

## How to Use

1. **Open the template** in Excel (or your preferred spreadsheet application)

2. **Review the sample data** to understand the format (if using templates with samples)

3. **Replace sample data** with your historic data, or use empty templates

4. **Save your file** with a descriptive name (e.g., `historic_orders_2024.xlsx`)

5. **Load into BigQuery** using the load script:
   ```bash
   # Validate first (recommended)
   python load_excel_data.py --file historic_orders_2024.xlsx --type orders --dry-run
   
   # Then load
   python load_excel_data.py --file historic_orders_2024.xlsx --type orders
   ```

## Column Notes

### Purchase Orders
- **Required:** `order_date`, `manufacturer_name`, `quantity`, `total_amount`
- **Product Lookup:** Provide ONE of: `product_id`, `product_asin`, or `product_sku`
- **Auto-generated:** `purchase_order_id` (if left empty)

### Shipments
- **Required:** `purchase_order_id`, `shipment_date`, `quantity_shipped`, `cost_shipped`
- **Auto-calculated:** `unit_cost` = `cost_shipped / quantity_shipped`
- **Auto-generated:** `shipment_id` (if left empty)
- **Boolean:** `is_paid` can be "Yes"/"No", "True"/"False", or 1/0

### Payments
- **Required:** `purchase_order_id`, `payment_date`, `payment_amount`, `vendor_name`
- **Vendor Names:** Can be single ("SYLVIA") or comma-separated ("SYLVIA,ANNA")
- **Auto-generated:** `payment_id` (if left empty)

## Tips

- Keep the column headers exactly as shown (case-sensitive)
- Dates can be in Excel date format or YYYY-MM-DD text format
- Empty cells are OK for optional fields
- Make sure `purchase_order_id` values match exactly when linking shipments/payments to orders
- Test with a small batch first before loading large datasets

## Need Help?

See `EXCEL_LOAD_GUIDE.md` in the parent directory for detailed documentation.
