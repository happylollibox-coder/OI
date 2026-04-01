"""
Script to fix remaining PO IDs that didn't get migrated
"""

from google.cloud import bigquery
import os
from datetime import datetime
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

from config import PROJECT_ID, DATASET_ID, ORDERS_TABLE, SHIPMENTS_TABLE, PAYMENTS_TABLE, PRODUCTS_TABLE

client = bigquery.Client(project=PROJECT_ID)


def generate_new_po_id(order_date, sku, quantity):
    """Generate new PO ID from date, SKU, and quantity"""
    # Format date as YYYYMMDD
    date_str = '00000000'
    if order_date:
        try:
            # Handle date objects
            if hasattr(order_date, 'strftime'):
                date_str = order_date.strftime('%Y%m%d')
            # Handle string dates
            elif isinstance(order_date, str):
                if len(order_date.replace('-', '')) == 8:
                    date_str = order_date.replace('-', '')
                else:
                    from datetime import datetime
                    dt = datetime.strptime(order_date, '%Y-%m-%d')
                    date_str = dt.strftime('%Y%m%d')
        except Exception as e:
            print(f"    Warning: Could not parse date {order_date}: {e}")
            date_str = '00000000'
    
    # Sanitize SKU
    sku_str = (sku or 'NOSKU').replace(' ', '_').replace('-', '_')[:20]
    qty_str = str(int(quantity))
    
    return f"PO_{date_str}_{sku_str}_{qty_str}"


def migrate_specific_pos(po_ids):
    """Migrate specific PO IDs"""
    print("=" * 60)
    print("Fixing Remaining PO IDs")
    print("=" * 60)
    
    for po_id in po_ids:
        print(f"\nProcessing {po_id}...")
        
        # Get PO details
        po_query = f"""
        SELECT 
          po.*,
          COALESCE(p.sku, 'NOSKU') as sku
        FROM `{ORDERS_TABLE}` po
        LEFT JOIN `{PRODUCTS_TABLE}` p ON po.product_id = p.product_id
        WHERE po.purchase_order_id = @po_id
        """
        job_config = bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("po_id", "STRING", po_id)]
        )
        po_results = list(client.query(po_query, job_config=job_config).result())
        
        if not po_results:
            print(f"  ✗ PO {po_id} not found")
            continue
        
        po = po_results[0]
        old_id = po.purchase_order_id
        new_id = generate_new_po_id(po.order_date, po.sku, po.quantity)
        
        # Check if new ID already exists
        check_query = f"""
        SELECT COUNT(*) as cnt
        FROM `{ORDERS_TABLE}`
        WHERE purchase_order_id = @new_id
        """
        check_config = bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("new_id", "STRING", new_id)]
        )
        check_result = list(client.query(check_query, job_config=check_config).result())
        
        if check_result[0].cnt > 0:
            # Add suffix
            suffix = 1
            while True:
                test_id = f"{new_id}_{suffix}"
                check_config = bigquery.QueryJobConfig(
                    query_parameters=[bigquery.ScalarQueryParameter("new_id", "STRING", test_id)]
                )
                check_result = list(client.query(check_query, job_config=check_config).result())
                if check_result[0].cnt == 0:
                    new_id = test_id
                    break
                suffix += 1
        
        print(f"  Old ID: {old_id}")
        print(f"  New ID: {new_id}")
        
        if old_id == new_id:
            print(f"  ✓ Already in correct format")
            continue
        
        try:
            # Update shipments
            print(f"  Updating shipments...", end=' ', flush=True)
            update_shipments = f"""
            UPDATE `{SHIPMENTS_TABLE}`
            SET purchase_order_id = @new_id
            WHERE purchase_order_id = @old_id
            """
            update_config = bigquery.QueryJobConfig(
                query_parameters=[
                    bigquery.ScalarQueryParameter("new_id", "STRING", new_id),
                    bigquery.ScalarQueryParameter("old_id", "STRING", old_id)
                ]
            )
            job = client.query(update_shipments, job_config=update_config)
            job.result()
            print("✓")
            
            # Update payments
            print(f"  Updating payments...", end=' ', flush=True)
            update_payments = f"""
            UPDATE `{PAYMENTS_TABLE}`
            SET purchase_order_id = @new_id
            WHERE purchase_order_id = @old_id
            """
            job = client.query(update_payments, job_config=update_config)
            job.result()
            print("✓")
            
            # Get full PO record
            print(f"  Creating new PO record...", end=' ', flush=True)
            get_query = f"""
            SELECT * FROM `{ORDERS_TABLE}`
            WHERE purchase_order_id = @old_id
            """
            get_config = bigquery.QueryJobConfig(
                query_parameters=[bigquery.ScalarQueryParameter("old_id", "STRING", old_id)]
            )
            old_record = list(client.query(get_query, job_config=get_config).result())
            
            if old_record:
                old_dict = dict(old_record[0])
                old_dict['purchase_order_id'] = new_id
                
                # Convert to JSON-serializable format
                new_row = {}
                for key, value in old_dict.items():
                    if value is not None:
                        # Convert date/datetime objects to strings
                        if hasattr(value, 'strftime'):
                            new_row[key] = value.strftime('%Y-%m-%d')
                        else:
                            new_row[key] = value
                
                # Insert new record
                table_ref = client.get_table(ORDERS_TABLE)
                job_config = bigquery.LoadJobConfig(
                    write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
                    source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
                    autodetect=False,
                    schema=table_ref.schema
                )
                job = client.load_table_from_json([new_row], table_ref, job_config=job_config)
                job.result()
                
                # Delete old record
                delete_query = f"""
                DELETE FROM `{ORDERS_TABLE}`
                WHERE purchase_order_id = @old_id
                """
                delete_config = bigquery.QueryJobConfig(
                    query_parameters=[bigquery.ScalarQueryParameter("old_id", "STRING", old_id)]
                )
                delete_job = client.query(delete_query, job_config=delete_config)
                delete_job.result()
                print("✓")
                
                print(f"  ✓ Successfully migrated {old_id} -> {new_id}")
            else:
                print("✗ Could not find PO record")
                
        except Exception as e:
            print(f"✗ ERROR: {e}")
            import traceback
            traceback.print_exc()


if __name__ == '__main__':
    # PO IDs that need to be fixed
    po_ids_to_fix = [
        'PO_52ae3974e0ff',
        'PO_c5a9df5b4099'
    ]
    
    migrate_specific_pos(po_ids_to_fix)
    print("\n" + "=" * 60)
    print("Migration complete!")
