# OI Data Entry Forms

A web-based data entry application for entering purchase orders, manufacturer shipments, and vendor payments into BigQuery.

## Overview

This Flask web application provides user-friendly forms for manually entering:
- **Purchase Orders**: Orders from manufacturers/vendors with product details, pricing, and terms
- **Manufacturer Shipments**: Incoming shipments from manufacturers to your inventory/warehouse
- **Vendor Payments**: Payments made to vendors/manufacturers with invoice matching and reconciliation

All data is stored directly in BigQuery tables in the `onyga-482313.OI` dataset.

## Features

- ✅ Modern, responsive web interface
- ✅ Three separate forms for Purchase Orders, Shipments, and Payments
- ✅ Direct BigQuery integration
- ✅ Automatic ID generation
- ✅ Multi-currency support (USD, ILS, HKD, EUR, GBP)
- ✅ Data validation and error handling
- ✅ Success/error message notifications
- ✅ Links between purchase orders, shipments, and payments
- ✅ Payment terms and due date tracking
- ✅ Receiving and inspection tracking
- ✅ Invoice matching and reconciliation

## Prerequisites

1. **Python 3.9+** installed
2. **Google Cloud SDK** installed and configured
3. **BigQuery tables created** (see Setup section)
4. **GCP authentication** configured (Application Default Credentials)

## Setup

### 1. Create BigQuery Tables

First, create the required BigQuery tables:

```bash
# Navigate to the project root
cd /path/to/OI

# Run the setup script
./data-entry-app/setup_tables.sh
```

Or manually:

```bash
# Create purchase orders table
bq query --use_legacy_sql=false < scripts/bigquery/tables/FACT/FACT_ORDERS.sql

# Create manufacturer shipments table
bq query --use_legacy_sql=false < scripts/bigquery/tables/Other/FACT_SHIPMENTS.sql

# Create vendor payments table
bq query --use_legacy_sql=false < scripts/bigquery/tables/Other/FACT_PAYMENTS.sql
```

### 2. Install Dependencies

```bash
cd data-entry-app

# Create virtual environment (if not already created)
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate  # On macOS/Linux
# or
venv\Scripts\activate  # On Windows

# Install dependencies
pip install -r requirements.txt
```

### 3. Configure Authentication

Set up Google Cloud authentication:

```bash
# Authenticate with GCP
gcloud auth login

# Set application default credentials
gcloud auth application-default login

# Set the project
gcloud config set project onyga-482313
```

### 4. Configure Environment Variables (Optional)

Create a `.env` file in the `data-entry-app` directory:

```bash
GCP_PROJECT_ID=onyga-482313
BIGQUERY_DATASET=OI
SECRET_KEY=your-secret-key-here
PORT=5000
USER=your-username
```

Or set environment variables directly:

```bash
export GCP_PROJECT_ID=onyga-482313
export BIGQUERY_DATASET=OI
export SECRET_KEY=your-secret-key-here
export PORT=5000
export USER=your-username
```

### 5. Run the Application

```bash
# Make sure you're in the data-entry-app directory
cd data-entry-app

# Activate virtual environment
source venv/bin/activate

# Run the application
python app.py
```

The application will be available at `http://localhost:5000`

## Usage

### Entering a Purchase Order

1. Navigate to the home page
2. Click "New Purchase Order" or go to `/orders/new`
3. Fill in the required fields (marked with *)
   - Order date
   - Manufacturer name
   - Product name
   - Quantity and unit price
4. Add manufacturer contact information
5. Set payment terms and delivery terms
6. Click "Save Purchase Order"
7. Note the Purchase Order ID that is generated (you'll need this for shipments and payments)

### Entering a Manufacturer Shipment

1. Click "New Shipment" or go to `/shipments/new`
2. Enter the Purchase Order ID from the purchase order you created
3. Fill in shipment details:
   - Shipment date
   - Tracking number and carrier
   - Origin (manufacturer) and destination (your warehouse) addresses
   - Package information
   - Quantity shipped and received
4. Update shipment status as it moves through your receiving process
5. Add receiving, inspection, and put-away information
6. Click "Save Shipment"

### Entering a Vendor Payment

1. Click "New Payment" or go to `/payments/new`
2. Enter the Purchase Order ID from the purchase order you created
3. Fill in payment details:
   - Payment date and amount
   - Payment method
   - Vendor information
   - Bank account details (from/to)
   - Invoice information
4. Set payment terms and due date
5. Mark as reconciled when matched with bank statements
6. Click "Save Payment"

## Data Flow

```
Purchase Order (created first)
  ↓
Manufacturer Shipment (linked via purchase_order_id)
  ↓
Vendor Payment (linked via purchase_order_id)
```

## Table Schemas

### DE_PURCHASE_ORDERS
- Stores purchase orders from manufacturers/vendors
- Primary key: `purchase_order_id`
- Partitioned by `order_date`
- Clustered by `manufacturer_name`, `order_status`, `order_year`, `order_month`
- Key fields: manufacturer information, product details, payment terms, delivery terms, expected delivery date

### DE_MANUFACTURER_SHIPMENTS
- Stores shipments from manufacturers to your inventory/warehouse
- Primary key: `shipment_id`
- Links to purchase orders via `purchase_order_id`
- Partitioned by `shipment_date`
- Clustered by `destination_warehouse`, `shipment_status`, `shipment_year`, `shipment_month`
- Key fields: tracking information, origin/destination addresses, receiving/inspection information, inventory location

### DE_VENDOR_PAYMENTS
- Stores payments made to vendors/manufacturers
- Primary key: `payment_id`
- Links to purchase orders via `purchase_order_id`
- Partitioned by `payment_date`
- Clustered by `vendor_name`, `payment_status`, `payment_year`, `payment_month`
- Key fields: payment method, bank accounts, invoice matching, reconciliation, payment terms, due dates

## API Endpoints

- `GET /` - Home page
- `GET /orders/new` - Purchase order form
- `POST /orders/new` - Create new purchase order
- `GET /shipments/new` - Shipment form
- `POST /shipments/new` - Create new shipment
- `GET /payments/new` - Payment form
- `POST /payments/new` - Create new payment
- `GET /api/orders` - Get recent purchase orders (JSON)

## Troubleshooting

### Authentication Errors

If you see authentication errors:

```bash
# Re-authenticate
gcloud auth application-default login

# Verify project
gcloud config get-value project
```

### Table Not Found Errors

Make sure the BigQuery tables are created:

```bash
# Check if tables exist
bq ls onyga-482313:OI

# If not, create them (see Setup section)
```

### Permission Errors

Ensure your GCP account has BigQuery Data Editor and BigQuery Job User roles:

```bash
# Check your permissions
gcloud projects get-iam-policy onyga-482313
```

## Development

### Project Structure

```
data-entry-app/
├── app.py                 # Main Flask application
├── requirements.txt       # Python dependencies
├── README.md             # This file
├── setup_tables.sh        # Script to create BigQuery tables
├── .env                  # Environment variables (not in git)
├── templates/            # HTML templates
│   ├── base.html
│   ├── index.html
│   ├── order_form.html
│   ├── shipment_form.html
│   └── payment_form.html
└── static/               # Static files (CSS, JS)
    └── css/
```

### Adding New Fields

1. Update the BigQuery table schema (SQL file)
2. Update the form template (HTML)
3. Update the insert function in `app.py`
4. Test the changes

## Security Notes

- Change the `SECRET_KEY` in production
- Implement proper authentication/authorization
- Use HTTPS in production
- Validate and sanitize all user inputs
- Consider rate limiting for API endpoints

## Production Deployment

For production deployment, consider:

1. **Web Server**: Use Gunicorn or uWSGI
2. **Reverse Proxy**: Nginx or Apache
3. **Process Manager**: systemd, supervisor, or PM2
4. **SSL/TLS**: Use Let's Encrypt for HTTPS
5. **Authentication**: Integrate with your auth system
6. **Monitoring**: Set up logging and error tracking

Example with Gunicorn:

```bash
pip install gunicorn
gunicorn -w 4 -b 0.0.0.0:5000 app:app
```

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review BigQuery table schemas
3. Check application logs
4. Verify GCP authentication and permissions

## License

Internal use only - Happy Lolli LTD
