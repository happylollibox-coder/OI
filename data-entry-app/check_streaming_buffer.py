"""
Check if there are rows in BigQuery streaming buffer
Note: BigQuery doesn't provide a direct way to check or clear the streaming buffer,
but we can check recent inserts and estimate if they might still be in the buffer.
"""

from google.cloud import bigquery
import os
from datetime import datetime, timedelta

# Load environment variables
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

from config import PROJECT_ID, ORDERS_TABLE, SHIPMENTS_TABLE, PAYMENTS_TABLE

client = bigquery.Client(project=PROJECT_ID)

def check_recent_inserts(table_name, table_id):
    """Check for recent inserts that might still be in streaming buffer"""
    print(f"\n{table_name}:")
    print("-" * 60)
    
    # Check for rows created in the last 15 minutes
    query = f"""
    SELECT 
        COUNT(*) as recent_count,
        MIN(created_at) as oldest_recent,
        MAX(created_at) as newest_recent
    FROM `{table_id}`
    WHERE created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 15 MINUTE)
    """
    
    try:
        result = list(client.query(query).result())
        if result and result[0].recent_count > 0:
            print(f"  ⚠️  Found {result[0].recent_count} rows created in the last 15 minutes")
            print(f"     Oldest: {result[0].oldest_recent}")
            print(f"     Newest: {result[0].newest_recent}")
            print(f"     These may still be in the streaming buffer")
            print(f"     Wait 5-10 minutes for the buffer to clear automatically")
        else:
            print(f"  ✓ No recent inserts (last 15 minutes)")
            print(f"     Streaming buffer should be clear")
    except Exception as e:
        print(f"  Error checking table: {e}")

def main():
    print("="*60)
    print("Checking BigQuery Streaming Buffer Status")
    print("="*60)
    print("\nNote: BigQuery's streaming buffer cannot be manually cleared.")
    print("It automatically clears within 5-10 minutes after streaming inserts.")
    print("\nSince we switched to batch loading, NEW inserts should NOT go to")
    print("the streaming buffer and can be updated/deleted immediately.")
    print("\nChecking for recent inserts that might still be in buffer...")
    
    check_recent_inserts("Purchase Orders", ORDERS_TABLE)
    check_recent_inserts("Shipments", SHIPMENTS_TABLE)
    check_recent_inserts("Payments", PAYMENTS_TABLE)
    
    print("\n" + "="*60)
    print("Recommendations:")
    print("="*60)
    print("1. If you see recent inserts (< 15 minutes old):")
    print("   - Wait 5-10 minutes for the buffer to clear automatically")
    print("   - Or try updating/deleting again after waiting")
    print("\n2. For future inserts:")
    print("   - The script now uses batch loading (load_table_from_json)")
    print("   - New data should be immediately updatable/deletable")
    print("\n3. If you need to update old data:")
    print("   - Wait 10-15 minutes after the last streaming insert")
    print("   - Or use the web UI to check if updates work")

if __name__ == '__main__':
    main()
