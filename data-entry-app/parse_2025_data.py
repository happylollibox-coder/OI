"""
Parse the 2025 orders, payments, shipments Excel file
and load into BigQuery tables
"""
import pandas as pd
from google.cloud import bigquery
from datetime import datetime
import uuid
import os
import sys
from typing import List, Dict, Any, Optional

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


def get_all_products():
    """Get all active products from DIM_PRODUCT"""
    query = f"""
    SELECT product_id, asin, product_name, display_name, sku
    FROM `{PRODUCTS_TABLE}`
    WHERE is_active = TRUE
    ORDER BY product_name, sku
    """
    result = list(client.query(query).result())
    return [dict(row) for row in result]


def get_product_info(product_search_name: str):
    """Get product information from DIM_PRODUCT by search name"""
    query = f"""
    SELECT product_id, asin, product_name, display_name, sku
    FROM `{PRODUCTS_TABLE}`
    WHERE (UPPER(product_name) LIKE @name OR UPPER(display_name) LIKE @name OR UPPER(sku) LIKE @name)
      AND is_active = TRUE
    LIMIT 1
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[bigquery.ScalarQueryParameter("name", "STRING", f"%{product_search_name.upper()}%")]
    )
    result = list(client.query(query, job_config=job_config).result())
    
    if result:
        return result[0].product_id, result[0].asin, result[0].sku or result[0].display_name or result[0].product_name
    return None, None, product_search_name


def parse_excel_file(file_path: str):
    """Parse the Excel file and extract orders, payments, and shipments"""
    
    print(f"Reading Excel file: {file_path}")
    df = pd.read_excel(file_path, sheet_name=0, header=None)
    
    orders = []
    payments = []
    shipments = []
    
    # Find product name from Excel (first occurrence)
    excel_product_name = None
    for idx in range(min(20, len(df))):
        row = df.iloc[idx]
        for col_idx in range(len(row)):
            val = str(row.iloc[col_idx]) if pd.notna(row.iloc[col_idx]) else ""
            if "LOLLIME" in val.upper() or "DIARY" in val.upper():
                excel_product_name = val.strip()
                break
        if excel_product_name:
            break
    
    if not excel_product_name:
        excel_product_name = "DIARY- LOLLIME"
    
    print(f"\nFound product name in Excel: '{excel_product_name}'")
    
    # Ask user which product to map to
    print("\nAvailable products in DIM_PRODUCT:")
    all_products = get_all_products()
    for i, prod in enumerate(all_products, 1):
        display = prod.get('sku') or prod.get('display_name') or prod.get('product_name', 'Unknown')
        print(f"  {i}. {display} (ID: {prod.get('product_id')}, ASIN: {prod.get('asin', 'N/A')})")
    
    import sys
    if sys.stdin.isatty():
        while True:
            choice = input(f"\nWhich product should '{excel_product_name}' map to? (enter number or product name/sku): ").strip()
            
            # Try to find by number
            try:
                choice_num = int(choice)
                if 1 <= choice_num <= len(all_products):
                    selected_product = all_products[choice_num - 1]
                    product_id = selected_product.get('product_id')
                    product_asin = selected_product.get('asin')
                    product_name_final = selected_product.get('sku') or selected_product.get('display_name') or selected_product.get('product_name')
                    break
            except ValueError:
                pass
            
            # Try to find by name/sku
            selected_product = None
            for prod in all_products:
                prod_name = (prod.get('product_name') or '').upper()
                prod_sku = (prod.get('sku') or '').upper()
                prod_display = (prod.get('display_name') or '').upper()
                choice_upper = choice.upper()
                if choice_upper in prod_name or choice_upper in prod_sku or choice_upper in prod_display:
                    selected_product = prod
                    break
            
            if selected_product:
                product_id = selected_product.get('product_id')
                product_asin = selected_product.get('asin')
                product_name_final = selected_product.get('sku') or selected_product.get('display_name') or selected_product.get('product_name')
                break
            else:
                print(f"Product '{choice}' not found. Please try again.")
    else:
        # Non-interactive mode - use default
        print("Non-interactive mode - using 'lollime mint' as default")
        product_id, product_asin, product_name_final = get_product_info("lollime mint")
    
    print(f"\nUsing product: {product_name_final} (ID: {product_id}, ASIN: {product_asin})")
    
    # Find ALL header rows (each represents a potential order)
    header_rows = []
    for idx in range(len(df)):
        row = df.iloc[idx]
        row_str = " ".join([str(x) for x in row if pd.notna(x)])
        if "תאריך הזמנה" in row_str and "כמות" in row_str:
            header_rows.append(idx)
    
    print(f"Found {len(header_rows)} header rows (potential orders)")
    
    if not header_rows:
        print("Error: Could not find any header rows")
        return [], [], []
    
    # Process each header row as a separate order
    for header_idx, header_row_idx in enumerate(header_rows):
        # Order data is in the row immediately after the header
        order_row_idx = header_row_idx + 1
        
        if order_row_idx >= len(df):
            continue
        
        order_row = df.iloc[order_row_idx]
        
        try:
            # Extract order date (column 1)
            order_date_val = None
            if pd.notna(order_row.iloc[1]):
                order_date_val = pd.to_datetime(order_row.iloc[1]).date()
            
            # Extract quantity (column 2)
            quantity = None
            if pd.notna(order_row.iloc[2]):
                quantity = int(float(str(order_row.iloc[2])))
            
            # Extract total amount (column 4)
            total_amount = None
            if pd.notna(order_row.iloc[4]):
                total_amount = float(str(order_row.iloc[4]))
            
            # Extract unit price (column 6)
            unit_price = None
            if pd.notna(order_row.iloc[6]):
                unit_price = float(str(order_row.iloc[6]))
            
            # Only create order if we have required fields
            if order_date_val and quantity and total_amount:
                po_id = generate_id('PO')
                
                # Build order with all required fields
                order = {
                    'purchase_order_id': str(po_id),
                    'order_date': str(order_date_val),
                    'manufacturer_name': str('SYLVIA'),  # Required field - always include
                    'quantity': int(quantity),
                    'unit_price': float(unit_price or (total_amount / quantity if quantity > 0 else 0)),
                    'total_amount': float(total_amount),
                    'currency': str('USD'),
                    'payment_status': str('PENDING'),
                }
                
                # Add optional product fields only if they have values
                if product_id:
                    order['product_id'] = int(product_id)
                if product_asin:
                    order['product_asin'] = str(product_asin)
                if product_name_final:
                    order['product_name'] = str(product_name_final)
                order['notes'] = str(f'Imported from Excel - Order {header_idx + 1}')
                
                orders.append(order)
                print(f"Order {header_idx + 1}: PO {po_id} - Date: {order_date_val}, Qty: {quantity}, Amount: {total_amount}")
                
                # Find payments/shipments for this order section
                # Look for payment/shipment section starting from header_row_idx
                payment_shipment_start_idx = None
                search_end = header_rows[header_idx + 1] if header_idx + 1 < len(header_rows) else min(header_row_idx + 50, len(df))
                
                for idx in range(header_row_idx, search_end):
                    row = df.iloc[idx]
                    row_str = " ".join([str(x) for x in row if pd.notna(x)])
                    if "תשלומים" in row_str or "משלוחים" in row_str:
                        payment_shipment_start_idx = idx
                        break
                
                if payment_shipment_start_idx:
                    # Headers are usually one row after section header
                    data_start_idx = payment_shipment_start_idx + 2
                    section_end = header_rows[header_idx + 1] if header_idx + 1 < len(header_rows) else min(data_start_idx + 50, len(df))
                    
                    for idx in range(data_start_idx, section_end):
                        row = df.iloc[idx]
                        
                        # Stop if we hit next order section
                        if idx in header_rows:
                            break
                        
                        # Parse payment data (columns 1-4)
                        try:
                            payment_date_val = None
                            if pd.notna(row.iloc[1]):
                                payment_date_val = pd.to_datetime(row.iloc[1]).date()
                            
                            payment_amount_val = None
                            if pd.notna(row.iloc[2]):
                                payment_amount_val = float(str(row.iloc[2]))
                            
                            bank_fee_val = None
                            if pd.notna(row.iloc[3]):
                                try:
                                    bank_fee_val = float(str(row.iloc[3]))
                                except:
                                    pass
                            
                            notes_val = None
                            if pd.notna(row.iloc[4]):
                                notes_val = str(row.iloc[4]).strip()
                                if notes_val in ['סכום כולל', 'תשלום 2', 'תשלום 3', 'תשלום סופי', 'חוב פתוח', 'הערות:']:
                                    notes_val = None
                            
                            if payment_date_val and payment_amount_val:
                                payment = {
                                    'payment_id': generate_id('PAY'),
                                    'purchase_order_id': po_id,
                                    'payment_date': payment_date_val.isoformat(),
                                    'payment_amount': payment_amount_val,
                                    'vendor_name': 'SYLVIA',
                                    'currency': 'USD',
                                }
                                
                                if bank_fee_val:
                                    payment['bank_fee'] = bank_fee_val
                                if notes_val:
                                    payment['notes'] = notes_val
                                
                                payments.append(payment)
                                print(f"  Payment: {payment_date_val} - {payment_amount_val}")
                        except Exception as e:
                            # Skip payment parsing errors
                            pass
                        
                        # Parse shipment data (columns 6-10)
                        try:
                            tracking = None
                            if pd.notna(row.iloc[6]) and len(str(row.iloc[6]).strip()) > 0:
                                tracking = str(row.iloc[6]).strip()
                                if '202' in tracking or len(tracking) < 2:
                                    tracking = None
                            
                            shipment_date_val = None
                            if pd.notna(row.iloc[7]):
                                try:
                                    shipment_date_val = pd.to_datetime(row.iloc[7]).date()
                                except:
                                    pass
                            
                            quantity_shipped_val = None
                            if pd.notna(row.iloc[8]):
                                try:
                                    quantity_shipped_val = int(float(str(row.iloc[8])))
                                except:
                                    pass
                            
                            kg_price_val = None
                            if pd.notna(row.iloc[9]):
                                try:
                                    kg_price_val = float(str(row.iloc[9]))
                                except:
                                    pass
                            
                            cost_shipped_val = None
                            if pd.notna(row.iloc[10]):
                                try:
                                    cost_shipped_val = float(str(row.iloc[10]))
                                except:
                                    pass
                            
                            # Check if shipment is paid (column 11 - שולם)
                            is_paid = False
                            paid_date_val = None
                            if len(row) > 11 and pd.notna(row.iloc[11]):
                                # Column 11 has a value, so shipment is paid
                                is_paid = True
                                # Get paid date from column 12 (תאריך תשלום)
                                if len(row) > 12 and pd.notna(row.iloc[12]):
                                    try:
                                        paid_date_val = pd.to_datetime(row.iloc[12]).date()
                                    except:
                                        pass
                            
                            if shipment_date_val and quantity_shipped_val:
                                if not cost_shipped_val and kg_price_val:
                                    cost_shipped_val = kg_price_val * quantity_shipped_val
                                
                                if cost_shipped_val:
                                    shipment = {
                                        'shipment_id': generate_id('SHP'),
                                        'purchase_order_id': po_id,
                                        'shipment_date': shipment_date_val.isoformat(),
                                        'quantity_shipped': quantity_shipped_val,
                                        'cost_shipped': cost_shipped_val,
                                        'is_paid': is_paid,
                                        'shipment_status': 'PENDING',
                                    }
                                    
                                    if tracking:
                                        shipment['tracking_number'] = tracking
                                    if kg_price_val:
                                        shipment['kg_price'] = kg_price_val
                                    if quantity_shipped_val > 0:
                                        shipment['unit_cost'] = cost_shipped_val / quantity_shipped_val
                                    if paid_date_val:
                                        shipment['paid_date'] = paid_date_val.isoformat()
                                    
                                    shipments.append(shipment)
                                    paid_info = ""
                                    if is_paid:
                                        paid_info = f" [PAID"
                                        if paid_date_val:
                                            paid_info += f" on {paid_date_val}]"
                                        else:
                                            paid_info += "]"
                                    print(f"  Shipment: {shipment_date_val} - Qty: {quantity_shipped_val}, Cost: {cost_shipped_val}{paid_info}")
                        except Exception as e:
                            # Skip shipment parsing errors
                            pass
            else:
                print(f"  Skipping order at row {order_row_idx} - missing required fields")
        except Exception as e:
            print(f"Error parsing order at row {order_row_idx}: {e}")
            import traceback
            traceback.print_exc()
    
    return orders, payments, shipments


def insert_batch(table_ref, rows: List[Dict[str, Any]], batch_size: int = 1000):
    """Insert rows in batches using batch loading (avoids streaming buffer)"""
    if not rows:
        return 0
    
    total_rows = len(rows)
    inserted = 0
    
    for i in range(0, total_rows, batch_size):
        batch = rows[i:i + batch_size]
        print(f"Inserting batch {i // batch_size + 1} ({len(batch)} rows)...")
        
        # Use batch loading to avoid streaming buffer issues
        # This makes data immediately updatable/deletable
        # Get table schema to ensure proper field types
        table = client.get_table(table_ref)
        job_config = bigquery.LoadJobConfig(
            write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
            source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
            autodetect=False,  # Use table's existing schema
            schema=table.schema  # Explicitly use table schema
        )
        
        try:
            job = client.load_table_from_json(batch, table_ref, job_config=job_config)
            job.result()  # Wait for the job to complete
            
            if job.errors:
                print(f"Errors in batch {i // batch_size + 1}: {job.errors}")
                # Fallback to streaming insert if batch load fails
                print("Trying streaming insert as fallback...")
                errors = client.insert_rows_json(table_ref, batch)
                if errors:
                    print(f"Streaming insert also failed: {errors}")
                    continue
                else:
                    inserted += len(batch)
                    print(f"Successfully inserted {len(batch)} rows using streaming (Total: {inserted}/{total_rows})")
            else:
                inserted += len(batch)
                print(f"Successfully inserted {len(batch)} rows using batch load (Total: {inserted}/{total_rows})")
        except Exception as e:
            print(f"Batch load failed: {e}")
            # Fallback to streaming insert
            print("Trying streaming insert as fallback...")
            errors = client.insert_rows_json(table_ref, batch)
            if errors:
                print(f"Streaming insert also failed: {errors}")
                continue
            else:
                inserted += len(batch)
                print(f"Successfully inserted {len(batch)} rows using streaming (Total: {inserted}/{total_rows})")
    
    return inserted


def main():
    file_path = 'excel_templates/2025 orders, payments , shipments.xlsx'
    
    if not os.path.exists(file_path):
        print(f"Error: File not found: {file_path}")
        sys.exit(1)
    
    print("="*60)
    print("Parsing Excel file and extracting data...")
    print("="*60)
    
    # Parse the file
    orders, payments, shipments = parse_excel_file(file_path)
    
    print("\n" + "="*60)
    print("Summary:")
    print(f"  Orders: {len(orders)}")
    print(f"  Payments: {len(payments)}")
    print(f"  Shipments: {len(shipments)}")
    print("="*60)
    
    if not orders and not payments and not shipments:
        print("No data found to insert.")
        return
    
    # Show sample data
    if orders:
        print("\nSample Order:")
        import json
        print(json.dumps(orders[0], indent=2, default=str))
    
    # Confirm before inserting (skip if running non-interactively)
    import sys
    if sys.stdin.isatty():
        response = input(f"\nInsert data into BigQuery? (yes/no): ")
        if response.lower() not in ['yes', 'y']:
            print("Cancelled.")
            return
    else:
        print("\nAuto-inserting data (non-interactive mode)...")
    
    # Insert data
    try:
        if orders:
            print("\nInserting orders...")
            table_ref = client.get_table(ORDERS_TABLE)
            inserted = insert_batch(table_ref, orders)
            print(f"✓ Inserted {inserted} orders")
        
        if payments:
            print("\nInserting payments...")
            table_ref = client.get_table(PAYMENTS_TABLE)
            inserted = insert_batch(table_ref, payments)
            print(f"✓ Inserted {inserted} payments")
        
        if shipments:
            print("\nInserting shipments...")
            table_ref = client.get_table(SHIPMENTS_TABLE)
            inserted = insert_batch(table_ref, shipments)
            print(f"✓ Inserted {inserted} shipments")
        
        print("\n" + "="*60)
        print("All data inserted successfully!")
        print("="*60)
        
    except Exception as e:
        print(f"\nError inserting data: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
