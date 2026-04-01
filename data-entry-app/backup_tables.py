"""
Script to backup BigQuery tables before migration
Creates backup tables with timestamp suffix
"""

from google.cloud import bigquery
import os
from datetime import datetime
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

from config import PROJECT_ID, DATASET_ID, ORDERS_TABLE, SHIPMENTS_TABLE, PAYMENTS_TABLE, BASE_ORDERS, BASE_SHIPMENTS, BASE_PAYMENTS

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
    
    print("=" * 60)
    print("Backing up BigQuery tables...")
    print("=" * 60)
    print(f"Timestamp: {timestamp}")
    print(f"Project: {PROJECT_ID}")
    print(f"Dataset: {DATASET_ID}\n")
    
    for table_name, full_table_name in tables_to_backup:
        backup_table_name = f'{table_name}_backup_{timestamp}'
        backup_table_full = f'{PROJECT_ID}.{DATASET_ID}.{backup_table_name}'
        
        try:
            print(f"Backing up {table_name}...")
            
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
            
            print(f"  ✓ Created {backup_table_name} ({row_count:,} rows)")
            
        except Exception as e:
            print(f"  ✗ ERROR backing up {table_name}: {e}")
            import traceback
            traceback.print_exc()
    
    print("\n" + "=" * 60)
    print("Backup Summary:")
    print("=" * 60)
    for backup in backup_tables_created:
        print(f"  {backup['original']} -> {backup['backup']} ({backup['rows']:,} rows)")
    
    print(f"\nBackup timestamp: {timestamp}")
    print("Backup completed successfully!")
    
    return timestamp, backup_tables_created


if __name__ == '__main__':
    backup_tables()
