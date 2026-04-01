# Data Entry Forms - Quick Start Guide

## Overview

I've created a complete data entry solution for **purchasing operations**:
- **Purchase Orders** from manufacturers
- **Manufacturer Shipments** to your inventory/warehouse
- **Vendor Payments** to manufacturers/suppliers

All data is stored directly in BigQuery tables in the `onyga-482313.OI` dataset.

## What Was Created

### BigQuery Tables
- `DE_PURCHASE_ORDERS` - Purchase orders from manufacturers/vendors
- `DE_MANUFACTURER_SHIPMENTS` - Incoming shipments from manufacturers to inventory
- `DE_VENDOR_PAYMENTS` - Payments made to vendors/manufacturers

Location: `scripts/Tables/orders/`

### Web Application
- Modern, responsive web interface
- Three separate forms for data entry
- Direct BigQuery integration
- Automatic ID generation

Location: `data-entry-app/`

## Quick Setup

### Step 1: Create BigQuery Tables

```bash
cd /path/to/OI
./data-entry-app/setup_tables.sh
```

Or manually:

```bash
bq query --use_legacy_sql=false < scripts/Tables/orders/FACT_ORDERS.sql
bq query --use_legacy_sql=false < scripts/Tables/orders/FACT_SHIPMENTS.sql
bq query --use_legacy_sql=false < scripts/Tables/orders/FACT_PAYMENTS.sql
```

### Step 2: Install Dependencies

```bash
cd data-entry-app
python3 -m venv venv
source venv/bin/activate  # On macOS/Linux
pip install -r requirements.txt
```

### Step 3: Authenticate with Google Cloud

```bash
gcloud auth application-default login
gcloud config set project onyga-482313
```

### Step 4: Run the Application

```bash
cd data-entry-app
source venv/bin/activate
python app.py
```

Then open your browser to: `http://localhost:5000`

## Usage Flow

1. **Create a Purchase Order** → Get a Purchase Order ID
2. **Create a Manufacturer Shipment** → Link it to the Purchase Order ID
3. **Create a Vendor Payment** → Link it to the Purchase Order ID

## Features

✅ **Purchase Orders Form**
- Manufacturer/vendor information
- Product details (SKU, name, category, manufacturer SKU)
- Pricing (quantity, unit price, total)
- Payment terms (Net 30, Net 60, Due on Receipt, etc.)
- Delivery terms (FOB Origin, FOB Destination, CIF, etc.)
- Order status tracking
- Expected delivery dates
- Destination warehouse information
- Multi-currency support

✅ **Manufacturer Shipments Form**
- Links to purchase orders via Purchase Order ID
- Origin (manufacturer) and destination (your warehouse) addresses
- Tracking information (carrier, tracking number)
- Package details (weight, dimensions, number of boxes)
- Shipping costs (shipping, insurance, handling, customs duty)
- Receiving and inspection information
- Quantity tracking (shipped, received, damaged, missing)
- Quality status and inspection notes
- Inventory location after put-away

✅ **Vendor Payments Form**
- Links to purchase orders via Purchase Order ID
- Payment methods (Wire Transfer, ACH, Check, etc.)
- Payment terms and due date tracking
- Bank account information (from/to)
- Invoice matching
- Payment fees (bank fees, currency conversion)
- Partial payment support
- Overdue payment tracking
- Reconciliation support
- Refund and credit memo tracking

## Best Practices

1. **Always create purchase orders first** - Shipments and payments need a Purchase Order ID
2. **Use consistent Purchase Order IDs** - Copy the PO ID from the success message
3. **Fill required fields** - Fields marked with * are required
4. **Review before submitting** - Data goes directly to BigQuery
5. **Track shipment status** - Update status as shipments move through your receiving process
6. **Reconcile payments** - Mark payments as reconciled when matched with bank statements

## Data Structure

All tables are:
- **Partitioned by date** for efficient querying
- **Clustered** for better performance
- **Include audit fields** (created_by, updated_by, timestamps)
- **Support multi-currency** with conversion fields

## Table Details

### DE_PURCHASE_ORDERS
- Stores purchase orders from manufacturers
- Primary key: `purchase_order_id`
- Tracks manufacturer information, product details, payment terms, delivery terms
- Partitioned by `order_date`
- Clustered by `manufacturer_name`, `order_status`, `order_year`, `order_month`

### DE_MANUFACTURER_SHIPMENTS
- Stores incoming shipments from manufacturers
- Primary key: `shipment_id`
- Links to purchase orders via `purchase_order_id`
- Tracks full shipment lifecycle: pending → in transit → received → inspected → put away
- Includes receiving, inspection, and quality control information
- Partitioned by `shipment_date`
- Clustered by `destination_warehouse`, `shipment_status`, `shipment_year`, `shipment_month`

### DE_VENDOR_PAYMENTS
- Stores payments to vendors/manufacturers
- Primary key: `payment_id`
- Links to purchase orders via `purchase_order_id`
- Tracks payment terms, due dates, and overdue status
- Includes invoice matching and reconciliation
- Supports partial payments
- Partitioned by `payment_date`
- Clustered by `vendor_name`, `payment_status`, `payment_year`, `payment_month`

## Next Steps

1. Review the detailed README: `data-entry-app/README.md`
2. Customize forms if needed (templates in `data-entry-app/templates/`)
3. Add authentication for production use
4. Consider deploying to a web server for team access
5. Set up reporting queries in BigQuery to analyze your purchasing data

## Support

For detailed documentation, see:
- `data-entry-app/README.md` - Complete setup and usage guide
- Table schemas in `scripts/Tables/orders/` - SQL files with full schema details

## Why This Solution?

✅ **Integrated with your existing BigQuery setup**
✅ **No external dependencies** - Uses your current GCP project
✅ **Scalable** - BigQuery handles large volumes efficiently
✅ **User-friendly** - Modern web interface, no SQL knowledge needed
✅ **Flexible** - Easy to customize and extend
✅ **Maintainable** - Clean code structure, well-documented
✅ **Complete purchasing workflow** - Orders → Shipments → Payments
