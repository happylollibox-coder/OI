"""
Script to migrate existing PO IDs to new format: PO_YYYYMMDD_SKU_QUANTITY
This script updates:
1. DE_PURCHASE_ORDERS table
2. DE_MANUFACTURER_SHIPMENTS table (purchase_order_id foreign key)
3. DE_VENDOR_PAYMENTS table (purchase_order_id foreign key)
"""

from google.cloud import bigquery
import os
import sys
from datetime import datetime
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

from config import (PROJECT_ID, DATASET_ID, ORDERS_TABLE, SHIPMENTS_TABLE, PAYMENTS_TABLE,
                    PRODUCTS_TABLE, BASE_ORDERS, BASE_SHIPMENTS, BASE_PAYMENTS)

client = bigquery.Client(project=PROJECT_ID)


def backup_tables():
    """Backup all tables before migration"""
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    
    tables_to_backup = [
        (BASE_ORDERS, ORDERS_TABLE),
        (BASE_SHIPMENTS, SHIPMENTS_TABLE),
        (BASE_PAYMENTS, PAYMENTS_TABLE),
    ]
    
    backup_tables_created = []
    
    print("\n" + "=" * 60)
    print("Backing up BigQuery tables...")
    print("=" * 60)
    print(f"Timestamp: {timestamp}\n")
    
    for table_name, full_table_name in tables_to_backup:
        backup_table_name = f'{table_name}_backup_{timestamp}'
        backup_table_full = f'{PROJECT_ID}.{DATASET_ID}.{backup_table_name}'
        
        try:
            print(f"Backing up {table_name}...", end=' ', flush=True)
            
            # Create backup table by copying
            copy_job = client.copy_table(
                full_table_name,
                backup_table_full
            )
            copy_job.result()
            
            # Get row count
            count_query = f"SELECT COUNT(*) as cnt FROM `{backup_table_full}`"
            count_result = list(client.query(count_query).result())
            row_count = count_result[0].cnt if count_result else 0
            
            backup_tables_created.append({
                'original': table_name,
                'backup': backup_table_name,
                'rows': row_count
            })
            
            print(f"✓ ({row_count:,} rows)")
            
        except Exception as e:
            print(f"✗ ERROR: {e}")
            import traceback
            traceback.print_exc()
            return None
    
    print("\nBackup Summary:")
    for backup in backup_tables_created:
        print(f"  {backup['original']} -> {backup['backup']} ({backup['rows']:,} rows)")
    
    print(f"\nBackup timestamp: {timestamp}")
    return timestamp, backup_tables_created


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


def migrate_po_ids(dry_run=False, skip_backup=False):
    """Migrate all PO IDs to new format"""
    if dry_run:
        print("DRY RUN MODE - No changes will be made")
    
    # Backup tables first (unless dry run or skip_backup is True)
    if not dry_run and not skip_backup:
        backup_result = backup_tables()
        if backup_result is None:
            print("\nERROR: Backup failed. Aborting migration.")
            return
        print("\n" + "=" * 60)
    
    print("Starting PO ID migration...")
    
    # Step 1: Get all POs with their product SKU
    print("\nStep 1: Fetching all purchase orders...")
    po_query = f"""
    SELECT 
      po.purchase_order_id as old_po_id,
      po.order_date,
      po.quantity,
      COALESCE(p.sku, 'NOSKU') as sku
    FROM `{ORDERS_TABLE}` po
    LEFT JOIN `{PRODUCTS_TABLE}` p ON po.product_id = p.product_id
    ORDER BY po.order_date, po.purchase_order_id
    """
    
    po_results = list(client.query(po_query).result())
    print(f"Found {len(po_results)} purchase orders to migrate")
    
    # Step 2: Generate new PO IDs and check for conflicts
    print("\nStep 2: Generating new PO IDs...")
    migrations = []
    seen_new_ids = {}
    
    for po in po_results:
        old_id = po.old_po_id
        new_id = generate_new_po_id(po.order_date, po.sku, po.quantity)
        
        # Handle conflicts by adding suffix
        if new_id in seen_new_ids:
            suffix = seen_new_ids[new_id] + 1
            seen_new_ids[new_id] = suffix
            new_id = f"{new_id}_{suffix}"
        else:
            seen_new_ids[new_id] = 0
        
        migrations.append({
            'old_id': old_id,
            'new_id': new_id,
            'order_date': po.order_date,
            'sku': po.sku,
            'quantity': po.quantity
        })
        
        if old_id != new_id:
            print(f"  {old_id} -> {new_id}")
    
    # Step 3: Update shipments table (update foreign keys first)
    print("\nStep 3: Updating shipments table...")
    shipment_count = 0
    for migration in migrations:
        if migration['old_id'] != migration['new_id']:
            if dry_run:
                print(f"  [DRY RUN] Would update shipments: {migration['old_id']} -> {migration['new_id']}")
                shipment_count += 1
            else:
                try:
                    update_query = f"""
                    UPDATE `{SHIPMENTS_TABLE}`
                    SET purchase_order_id = @new_id
                    WHERE purchase_order_id = @old_id
                    """
                    job_config = bigquery.QueryJobConfig(
                        query_parameters=[
                            bigquery.ScalarQueryParameter("new_id", "STRING", migration['new_id']),
                            bigquery.ScalarQueryParameter("old_id", "STRING", migration['old_id'])
                        ]
                    )
                    job = client.query(update_query, job_config=job_config)
                    job.result()
                    shipment_count += 1
                    print(f"  Updated shipments: {migration['old_id']} -> {migration['new_id']}")
                except Exception as e:
                    print(f"  ERROR updating shipments for {migration['old_id']}: {e}")
    
    print(f"  {'Would update' if dry_run else 'Updated'} {shipment_count} shipment records")
    
    # Step 4: Update payments table (update foreign keys)
    print("\nStep 4: Updating payments table...")
    payment_count = 0
    for migration in migrations:
        if migration['old_id'] != migration['new_id']:
            if dry_run:
                print(f"  [DRY RUN] Would update payments: {migration['old_id']} -> {migration['new_id']}")
                payment_count += 1
            else:
                try:
                    update_query = f"""
                    UPDATE `{PAYMENTS_TABLE}`
                    SET purchase_order_id = @new_id
                    WHERE purchase_order_id = @old_id
                    """
                    job_config = bigquery.QueryJobConfig(
                        query_parameters=[
                            bigquery.ScalarQueryParameter("new_id", "STRING", migration['new_id']),
                            bigquery.ScalarQueryParameter("old_id", "STRING", migration['old_id'])
                        ]
                    )
                    job = client.query(update_query, job_config=job_config)
                    job.result()
                    payment_count += 1
                    print(f"  Updated payments: {migration['old_id']} -> {migration['new_id']}")
                except Exception as e:
                    print(f"  ERROR updating payments for {migration['old_id']}: {e}")
    
    print(f"  {'Would update' if dry_run else 'Updated'} {payment_count} payment records")
    
    # Step 5: Update orders table (insert new, delete old)
    print("\nStep 5: Updating purchase orders table...")
    order_count = 0
    for migration in migrations:
        if migration['old_id'] != migration['new_id']:
            if dry_run:
                print(f"  [DRY RUN] Would update PO: {migration['old_id']} -> {migration['new_id']}")
                order_count += 1
            else:
                try:
                    # Get the full record
                    get_query = f"""
                    SELECT * FROM `{ORDERS_TABLE}`
                    WHERE purchase_order_id = @old_id
                    """
                    get_config = bigquery.QueryJobConfig(
                        query_parameters=[bigquery.ScalarQueryParameter("old_id", "STRING", migration['old_id'])]
                    )
                    old_record = list(client.query(get_query, job_config=get_config).result())
                    
                    if old_record:
                        # Insert new record with new ID
                        old_dict = dict(old_record[0])
                        old_dict['purchase_order_id'] = migration['new_id']
                        
                        # Remove None values and convert to proper types
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
                            query_parameters=[bigquery.ScalarQueryParameter("old_id", "STRING", migration['old_id'])]
                        )
                        delete_job = client.query(delete_query, job_config=delete_config)
                        delete_job.result()
                        
                        order_count += 1
                        print(f"  Updated PO: {migration['old_id']} -> {migration['new_id']}")
                except Exception as e:
                    print(f"  ERROR updating PO {migration['old_id']}: {e}")
                    import traceback
                    traceback.print_exc()
    
    print(f"  {'Would update' if dry_run else 'Updated'} {order_count} purchase order records")
    
    print("\nMigration complete!")
    print(f"Total POs processed: {len(migrations)}")
    print(f"POs updated: {len([m for m in migrations if m['old_id'] != m['new_id']])}")


if __name__ == '__main__':
    print("=" * 60)
    print("PO ID Migration Script")
    print("=" * 60)
    print(f"Project: {PROJECT_ID}")
    print(f"Dataset: {DATASET_ID}")
    print("\nThis will update all PO IDs to format: PO_YYYYMMDD_SKU_QUANTITY")
    print("And update all related shipments and payments.")
    
    # Check for command line arguments
    if len(sys.argv) > 1:
        mode = sys.argv[1].lower()
        if mode == 'dry-run' or mode == 'dryrun':
            print("\nRunning in DRY RUN mode...")
            migrate_po_ids(dry_run=True)
        elif mode == 'execute' or mode == 'run':
            print("\nExecuting migration with backup...")
            migrate_po_ids(dry_run=False, skip_backup=False)
        elif mode == 'execute-no-backup':
            print("\nWARNING: Executing migration WITHOUT backup...")
            migrate_po_ids(dry_run=False, skip_backup=True)
        else:
            print(f"\nUnknown mode: {mode}")
            print("Usage: python3 migrate_po_ids.py [dry-run|execute|execute-no-backup]")
            sys.exit(1)
    else:
        # Interactive mode
        print("\nOptions:")
        print("  1. Dry run (preview changes without making them)")
        print("  2. Execute migration with backup (recommended)")
        print("  3. Execute migration without backup (not recommended)")
        print("  4. Cancel")
        
        try:
            response = input("\nEnter your choice (1/2/3/4): ").strip()
            
            if response == '1':
                migrate_po_ids(dry_run=True)
            elif response == '2':
                confirm = input("\nThis will backup tables and migrate PO IDs. Type 'yes' to confirm: ")
                if confirm.lower() == 'yes':
                    migrate_po_ids(dry_run=False, skip_backup=False)
                else:
                    print("Migration cancelled.")
            elif response == '3':
                confirm = input("\nWARNING: No backup will be created. Type 'yes' to proceed anyway: ")
                if confirm.lower() == 'yes':
                    migrate_po_ids(dry_run=False, skip_backup=True)
                else:
                    print("Migration cancelled.")
            else:
                print("Migration cancelled.")
        except (EOFError, KeyboardInterrupt):
            print("\nMigration cancelled.")
            sys.exit(1)
