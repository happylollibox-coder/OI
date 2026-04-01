"""
Excel Data Loader for OI Data Entry Forms
Loads historic data from Excel files into BigQuery tables

Usage:
    python load_excel_data.py --file data.xlsx --type orders
    python load_excel_data.py --file data.xlsx --type shipments --sheet "Sheet1"
    python load_excel_data.py --file data.xlsx --type payments
"""

import argparse
import pandas as pd
from google.cloud import bigquery
from datetime import datetime
import uuid
import os
import sys
from typing import List, Dict, Any

# Load environment variables
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

from config import PROJECT_ID, DATASET_ID, ORDERS_TABLE, SHIPMENTS_TABLE, PAYMENTS_TABLE, PRODUCTS_TABLE

client = bigquery.Client(project=PROJECT_ID)


def generate_id(prefix):
    """Generate a unique ID for records"""
    return f"{prefix}_{uuid.uuid4().hex[:12]}"


def get_product_info(product_id=None, product_asin=None, product_sku=None):
    """Get product information from DIM_PRODUCT"""
    if not product_id and not product_asin and not product_sku:
        return None, None, None
    
    conditions = []
    params = []
    
    if product_id:
        conditions.append("product_id = @product_id")
        params.append(bigquery.ScalarQueryParameter("product_id", "INT64", int(product_id)))
    if product_asin:
        conditions.append("asin = @asin")
        params.append(bigquery.ScalarQueryParameter("asin", "STRING", str(product_asin)))
    if product_sku:
        conditions.append("sku = @sku")
        params.append(bigquery.ScalarQueryParameter("sku", "STRING", str(product_sku)))
    
    query = f"""
    SELECT product_id, asin, product_name, display_name, sku
    FROM `{PRODUCTS_TABLE}`
    WHERE {' OR '.join(conditions)} AND is_active = TRUE
    LIMIT 1
    """
    job_config = bigquery.QueryJobConfig(query_parameters=params)
    result = list(client.query(query, job_config=job_config).result())
    
    if result:
        return result[0].product_id, result[0].asin, result[0].sku or result[0].display_name or result[0].product_name
    return None, None, None


def load_orders_from_excel(file_path: str, sheet_name: str = None) -> List[Dict[str, Any]]:
    """
    Load purchase orders from Excel file
    
    Expected columns:
    - purchase_order_id (optional, will generate if missing)
    - order_date (required, DATE format)
    - manufacturer_name (required)
    - product_id (optional, can use product_asin or product_sku instead)
    - product_asin (optional)
    - product_sku (optional)
    - quantity (required)
    - total_amount (required) - will calculate unit_price
    - currency (optional, defaults to USD)
    - payment_status (optional, defaults to PENDING)
    - notes (optional)
    """
    print(f"Reading Excel file: {file_path}")
    if sheet_name:
        df = pd.read_excel(file_path, sheet_name=sheet_name)
    else:
        df = pd.read_excel(file_path)
    
    print(f"Found {len(df)} rows")
    
    orders = []
    errors = []
    
    for idx, row in df.iterrows():
        try:
            # Generate ID if not provided
            po_id = str(row.get('purchase_order_id', '')).strip() if pd.notna(row.get('purchase_order_id')) else generate_id('PO')
            
            # Required fields
            order_date = pd.to_datetime(row['order_date']).date() if pd.notna(row.get('order_date')) else None
            if not order_date:
                errors.append(f"Row {idx + 2}: Missing order_date")
                continue
            
            manufacturer_name = str(row.get('manufacturer_name', '')).strip() if pd.notna(row.get('manufacturer_name')) else None
            if not manufacturer_name:
                errors.append(f"Row {idx + 2}: Missing manufacturer_name")
                continue
            
            quantity = float(row.get('quantity', 0)) if pd.notna(row.get('quantity')) else 0
            if quantity <= 0:
                errors.append(f"Row {idx + 2}: Invalid quantity")
                continue
            
            total_amount = float(row.get('total_amount', 0)) if pd.notna(row.get('total_amount')) else 0
            if total_amount <= 0:
                errors.append(f"Row {idx + 2}: Invalid total_amount")
                continue
            
            # Calculate unit_price
            unit_price = total_amount / quantity if quantity > 0 else 0
            
            # Get product info
            product_id = int(row['product_id']) if pd.notna(row.get('product_id')) else None
            product_asin = str(row.get('product_asin', '')).strip() if pd.notna(row.get('product_asin')) else None
            product_sku = str(row.get('product_sku', '')).strip() if pd.notna(row.get('product_sku')) else None
            
            resolved_product_id, resolved_asin, product_name = get_product_info(product_id, product_asin, product_sku)
            
            order = {
                'purchase_order_id': po_id,
                'order_date': order_date.isoformat(),
                'manufacturer_name': manufacturer_name,
                'product_id': resolved_product_id,
                'product_asin': resolved_asin,
                'product_name': product_name,
                'quantity': int(quantity),
                'unit_price': unit_price,
                'total_amount': total_amount,
                'currency': str(row.get('currency', 'USD')).strip() if pd.notna(row.get('currency')) else 'USD',
                'payment_status': str(row.get('payment_status', 'PENDING')).strip() if pd.notna(row.get('payment_status')) else 'PENDING',
                'notes': str(row.get('notes', '')).strip() if pd.notna(row.get('notes')) else None,
            }
            
            orders.append(order)
            
        except Exception as e:
            errors.append(f"Row {idx + 2}: {str(e)}")
    
    if errors:
        print("\nErrors found:")
        for error in errors:
            print(f"  - {error}")
    
    return orders


def load_shipments_from_excel(file_path: str, sheet_name: str = None) -> List[Dict[str, Any]]:
    """
    Load shipments from Excel file
    
    Expected columns:
    - shipment_id (optional, will generate if missing)
    - purchase_order_id (required)
    - shipment_date (required, DATE format)
    - estimated_arrival_date (optional)
    - tracking_number (optional)
    - shipment_type (optional: SLOW_SEA, FAST_SEA, AIR)
    - quantity_shipped (required)
    - kg_price (optional)
    - cost_shipped (required)
    - is_paid (optional, boolean or Yes/No)
    - paid_date (optional)
    - shipment_status (optional, defaults to PENDING)
    - notes (optional)
    """
    print(f"Reading Excel file: {file_path}")
    if sheet_name:
        df = pd.read_excel(file_path, sheet_name=sheet_name)
    else:
        df = pd.read_excel(file_path)
    
    print(f"Found {len(df)} rows")
    
    shipments = []
    errors = []
    
    for idx, row in df.iterrows():
        try:
            # Generate ID if not provided
            shipment_id = str(row.get('shipment_id', '')).strip() if pd.notna(row.get('shipment_id')) else generate_id('SHP')
            
            # Required fields
            purchase_order_id = str(row.get('purchase_order_id', '')).strip() if pd.notna(row.get('purchase_order_id')) else None
            if not purchase_order_id:
                errors.append(f"Row {idx + 2}: Missing purchase_order_id")
                continue
            
            shipment_date = pd.to_datetime(row['shipment_date']).date() if pd.notna(row.get('shipment_date')) else None
            if not shipment_date:
                errors.append(f"Row {idx + 2}: Missing shipment_date")
                continue
            
            quantity_shipped = int(row.get('quantity_shipped', 0)) if pd.notna(row.get('quantity_shipped')) else 0
            if quantity_shipped <= 0:
                errors.append(f"Row {idx + 2}: Invalid quantity_shipped")
                continue
            
            cost_shipped = float(row.get('cost_shipped', 0)) if pd.notna(row.get('cost_shipped')) else 0
            if cost_shipped <= 0:
                errors.append(f"Row {idx + 2}: Invalid cost_shipped")
                continue
            
            # Calculate unit_cost
            unit_cost = cost_shipped / quantity_shipped if quantity_shipped > 0 else None
            
            # Handle is_paid
            is_paid_value = row.get('is_paid')
            if pd.isna(is_paid_value):
                is_paid = False
            elif isinstance(is_paid_value, bool):
                is_paid = is_paid_value
            elif isinstance(is_paid_value, str):
                is_paid = is_paid_value.lower() in ['true', 'yes', '1', 'y']
            else:
                is_paid = bool(is_paid_value)
            
            paid_date = None
            if is_paid and pd.notna(row.get('paid_date')):
                paid_date = pd.to_datetime(row['paid_date']).date()
            
            shipment = {
                'shipment_id': shipment_id,
                'purchase_order_id': purchase_order_id,
                'shipment_date': shipment_date.isoformat(),
                'quantity_shipped': quantity_shipped,
                'cost_shipped': cost_shipped,
                'is_paid': is_paid,
                'shipment_status': str(row.get('shipment_status', 'PENDING')).strip() if pd.notna(row.get('shipment_status')) else 'PENDING',
            }
            
            # Optional fields
            if pd.notna(row.get('estimated_arrival_date')):
                shipment['estimated_arrival_date'] = pd.to_datetime(row['estimated_arrival_date']).date().isoformat()
            if pd.notna(row.get('tracking_number')):
                shipment['tracking_number'] = str(row['tracking_number']).strip()
            if pd.notna(row.get('shipment_type')):
                shipment['shipment_type'] = str(row['shipment_type']).strip()
            if pd.notna(row.get('kg_price')):
                shipment['kg_price'] = float(row['kg_price'])
            if unit_cost is not None:
                shipment['unit_cost'] = unit_cost
            if paid_date:
                shipment['paid_date'] = paid_date.isoformat()
            if pd.notna(row.get('notes')):
                shipment['notes'] = str(row['notes']).strip()
            
            shipments.append(shipment)
            
        except Exception as e:
            errors.append(f"Row {idx + 2}: {str(e)}")
    
    if errors:
        print("\nErrors found:")
        for error in errors:
            print(f"  - {error}")
    
    return shipments


def load_payments_from_excel(file_path: str, sheet_name: str = None) -> List[Dict[str, Any]]:
    """
    Load payments from Excel file
    
    Expected columns:
    - payment_id (optional, will generate if missing)
    - purchase_order_id (required)
    - payment_date (required, DATE format)
    - payment_amount (required)
    - bank_fee (optional)
    - currency (optional, defaults to USD)
    - payment_method (optional)
    - vendor_name (required, can be comma-separated: SYLVIA,ANNA)
    - notes (optional)
    """
    print(f"Reading Excel file: {file_path}")
    if sheet_name:
        df = pd.read_excel(file_path, sheet_name=sheet_name)
    else:
        df = pd.read_excel(file_path)
    
    print(f"Found {len(df)} rows")
    
    payments = []
    errors = []
    
    for idx, row in df.iterrows():
        try:
            # Generate ID if not provided
            payment_id = str(row.get('payment_id', '')).strip() if pd.notna(row.get('payment_id')) else generate_id('PAY')
            
            # Required fields
            purchase_order_id = str(row.get('purchase_order_id', '')).strip() if pd.notna(row.get('purchase_order_id')) else None
            if not purchase_order_id:
                errors.append(f"Row {idx + 2}: Missing purchase_order_id")
                continue
            
            payment_date = pd.to_datetime(row['payment_date']).date() if pd.notna(row.get('payment_date')) else None
            if not payment_date:
                errors.append(f"Row {idx + 2}: Missing payment_date")
                continue
            
            payment_amount = float(row.get('payment_amount', 0)) if pd.notna(row.get('payment_amount')) else 0
            if payment_amount <= 0:
                errors.append(f"Row {idx + 2}: Invalid payment_amount")
                continue
            
            vendor_name = str(row.get('vendor_name', '')).strip() if pd.notna(row.get('vendor_name')) else None
            if not vendor_name:
                errors.append(f"Row {idx + 2}: Missing vendor_name")
                continue
            
            payment = {
                'payment_id': payment_id,
                'purchase_order_id': purchase_order_id,
                'payment_date': payment_date.isoformat(),
                'payment_amount': payment_amount,
                'vendor_name': vendor_name,
                'currency': str(row.get('currency', 'USD')).strip() if pd.notna(row.get('currency')) else 'USD',
            }
            
            # Optional fields
            if pd.notna(row.get('bank_fee')):
                payment['bank_fee'] = float(row['bank_fee'])
            if pd.notna(row.get('payment_method')):
                payment['payment_method'] = str(row['payment_method']).strip()
            if pd.notna(row.get('notes')):
                payment['notes'] = str(row['notes']).strip()
            
            payments.append(payment)
            
        except Exception as e:
            errors.append(f"Row {idx + 2}: {str(e)}")
    
    if errors:
        print("\nErrors found:")
        for error in errors:
            print(f"  - {error}")
    
    return payments


def insert_batch(table_ref, rows: List[Dict[str, Any]], batch_size: int = 1000):
    """Insert rows in batches using batch loading"""
    total_rows = len(rows)
    inserted = 0
    
    for i in range(0, total_rows, batch_size):
        batch = rows[i:i + batch_size]
        print(f"Inserting batch {i // batch_size + 1} ({len(batch)} rows)...")
        
        job_config = bigquery.LoadJobConfig(
            write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
            source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON
        )
        
        job = client.load_table_from_json(batch, table_ref, job_config=job_config)
        job.result()  # Wait for the job to complete
        
        if job.errors:
            print(f"Errors in batch {i // batch_size + 1}: {job.errors}")
        else:
            inserted += len(batch)
            print(f"Successfully inserted {len(batch)} rows (Total: {inserted}/{total_rows})")
    
    return inserted


def main():
    parser = argparse.ArgumentParser(description='Load historic data from Excel into BigQuery')
    parser.add_argument('--file', required=True, help='Path to Excel file')
    parser.add_argument('--type', required=True, choices=['orders', 'shipments', 'payments'], 
                       help='Type of data to load')
    parser.add_argument('--sheet', help='Sheet name (if not provided, uses first sheet)')
    parser.add_argument('--dry-run', action='store_true', help='Validate data without inserting')
    
    args = parser.parse_args()
    
    if not os.path.exists(args.file):
        print(f"Error: File not found: {args.file}")
        sys.exit(1)
    
    print(f"\n{'='*60}")
    print(f"Loading {args.type.upper()} from {args.file}")
    if args.sheet:
        print(f"Sheet: {args.sheet}")
    print(f"{'='*60}\n")
    
    # Load data from Excel
    try:
        if args.type == 'orders':
            rows = load_orders_from_excel(args.file, args.sheet)
            table_ref = client.get_table(ORDERS_TABLE)
        elif args.type == 'shipments':
            rows = load_shipments_from_excel(args.file, args.sheet)
            table_ref = client.get_table(SHIPMENTS_TABLE)
        elif args.type == 'payments':
            rows = load_payments_from_excel(args.file, args.sheet)
            table_ref = client.get_table(PAYMENTS_TABLE)
    except Exception as e:
        print(f"Error reading Excel file: {e}")
        sys.exit(1)
    
    if not rows:
        print("No valid rows to insert.")
        sys.exit(1)
    
    print(f"\nValidated {len(rows)} rows")
    
    if args.dry_run:
        print("\nDRY RUN - No data will be inserted")
        print("\nSample row:")
        import json
        print(json.dumps(rows[0], indent=2, default=str))
        return
    
    # Confirm before inserting
    response = input(f"\nInsert {len(rows)} rows into BigQuery? (yes/no): ")
    if response.lower() not in ['yes', 'y']:
        print("Cancelled.")
        return
    
    # Insert data
    try:
        inserted = insert_batch(table_ref, rows)
        print(f"\n{'='*60}")
        print(f"Successfully inserted {inserted} rows!")
        print(f"{'='*60}\n")
    except Exception as e:
        print(f"\nError inserting data: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
