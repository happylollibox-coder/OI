"""
Truncate all orders, shipments, and payments tables, then re-import from Excel
"""

from google.cloud import bigquery
import os
import sys

# Load environment variables
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

from config import PROJECT_ID, ORDERS_TABLE, SHIPMENTS_TABLE, PAYMENTS_TABLE

client = bigquery.Client(project=PROJECT_ID)

def recreate_table(table_id, table_name, schema_sql):
    """Drop and recreate a table to clear all data (bypasses streaming buffer)"""
    print(f"\nRecreating {table_name}...")
    
    # Count rows before deletion
    try:
        count_query = f"SELECT COUNT(*) as cnt FROM `{table_id}`"
        result = list(client.query(count_query).result())
        row_count = result[0].cnt if result else 0
        print(f"  Current row count: {row_count}")
    except:
        row_count = 0
        print(f"  Table may not exist or is empty")
    
    # Drop the table
    try:
        client.delete_table(table_id, not_found_ok=True)
        print(f"  ✓ Dropped existing table")
    except Exception as e:
        print(f"  Note: {e}")
    
    # Recreate the table using the schema SQL
    try:
        job = client.query(schema_sql)
        job.result()  # Wait for completion
        print(f"  ✓ Recreated table (empty)")
    except Exception as e:
        print(f"  ✗ Error recreating table: {e}")
        raise

def main():
    print("="*60)
    print("TRUNCATE AND RE-IMPORT DATA")
    print("="*60)
    print("\nThis will:")
    print("  1. Delete ALL data from Orders, Shipments, and Payments tables")
    print("  2. Re-import everything from the Excel file")
    print("  3. Use batch loading (no streaming buffer issues)")
    
    import sys
    if sys.stdin.isatty():
        response = input("\n⚠️  WARNING: This will DELETE ALL existing data! Continue? (yes/no): ")
        if response.lower() not in ['yes', 'y']:
            print("Cancelled.")
            return
    else:
        print("\n⚠️  WARNING: Non-interactive mode - proceeding with truncation...")
    
    # Read schema SQL files
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    
    orders_sql_path = os.path.join(project_root, 'scripts/bigquery/tables/FACT/FACT_ORDERS.sql')
    shipments_sql_path = os.path.join(project_root, 'scripts/bigquery/tables/Other/FACT_SHIPMENTS.sql')
    payments_sql_path = os.path.join(project_root, 'scripts/bigquery/tables/Other/FACT_PAYMENTS.sql')
    
    with open(orders_sql_path, 'r') as f:
        orders_schema_sql = f.read()
    with open(shipments_sql_path, 'r') as f:
        shipments_schema_sql = f.read()
    with open(payments_sql_path, 'r') as f:
        payments_schema_sql = f.read()
    
    # Recreate all tables (drop and recreate to bypass streaming buffer)
    print("\n" + "="*60)
    print("STEP 1: Dropping and Recreating Tables")
    print("="*60)
    print("(This bypasses streaming buffer by recreating tables)")
    
    recreate_table(ORDERS_TABLE, "Purchase Orders", orders_schema_sql)
    recreate_table(SHIPMENTS_TABLE, "Shipments", shipments_schema_sql)
    recreate_table(PAYMENTS_TABLE, "Payments", payments_schema_sql)
    
    # Wait a moment for tables to be fully ready
    import time
    print("\nWaiting 2 seconds for tables to be fully ready...")
    time.sleep(2)
    
    print("\n" + "="*60)
    print("STEP 2: Re-importing Data")
    print("="*60)
    print("\nNow running the import script...")
    print("(This will use batch loading - no streaming buffer issues)")
    
    # Import the parse_2025_data module and run it
    import parse_2025_data
    
    # Parse and import
    orders, payments, shipments = parse_2025_data.parse_excel_file('excel_templates/2025 orders, payments , shipments.xlsx')
    
    print("\n" + "="*60)
    print("Summary:")
    print(f"  Orders: {len(orders)}")
    print(f"  Payments: {len(payments)}")
    print(f"  Shipments: {len(shipments)}")
    print("="*60)
    
    if not orders and not payments and not shipments:
        print("No data found to import.")
        return
    
    # Insert data using batch loading
    try:
        if orders:
            print("\nInserting orders...")
            table_ref = client.get_table(ORDERS_TABLE)
            inserted = parse_2025_data.insert_batch(table_ref, orders)
            print(f"✓ Inserted {inserted} orders")
        
        if payments:
            print("\nInserting payments...")
            table_ref = client.get_table(PAYMENTS_TABLE)
            inserted = parse_2025_data.insert_batch(table_ref, payments)
            print(f"✓ Inserted {inserted} payments")
        
        if shipments:
            print("\nInserting shipments...")
            table_ref = client.get_table(SHIPMENTS_TABLE)
            inserted = parse_2025_data.insert_batch(table_ref, shipments)
            print(f"✓ Inserted {inserted} shipments")
        
        print("\n" + "="*60)
        print("✅ All data re-imported successfully!")
        print("="*60)
        print("\nNote: Data was loaded using batch loading, so it should be")
        print("immediately updatable/deletable (no streaming buffer delays).")
        
    except Exception as e:
        print(f"\n❌ Error importing data: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()
