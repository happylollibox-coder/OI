"""
Script to update estimated_arrival_date for all existing shipments
based on shipment_type and shipment_date using the new logic:
- SLOW_SEA: shipment_date + 33 days
- FAST_SEA: shipment_date + 27 days
- AIR: shipment_date + 10 days
"""

from google.cloud import bigquery
from datetime import datetime, timedelta
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

from config import PROJECT_ID, SHIPMENTS_TABLE

client = bigquery.Client(project=PROJECT_ID)

def calculate_estimated_arrival_date(shipment_date, shipment_type):
    """Calculate estimated_arrival_date based on shipment_type"""
    if not shipment_date or not shipment_type:
        return None
    
    shipment_type_upper = shipment_type.upper()
    
    # Calculate days based on shipment type
    if shipment_type_upper == 'SLOW_SEA':
        days_to_add = 33
    elif shipment_type_upper == 'FAST_SEA':
        days_to_add = 27
    elif shipment_type_upper == 'AIR':
        days_to_add = 10
    else:
        return None  # Unknown shipment type
    
    # Parse shipment_date if it's a string
    if isinstance(shipment_date, str):
        shipment_date_obj = datetime.strptime(shipment_date, '%Y-%m-%d').date()
    elif isinstance(shipment_date, datetime):
        shipment_date_obj = shipment_date.date()
    elif hasattr(shipment_date, 'date'):
        shipment_date_obj = shipment_date.date()
    else:
        shipment_date_obj = shipment_date
    
    # Calculate estimated arrival date
    estimated_arrival_date = shipment_date_obj + timedelta(days=days_to_add)
    return estimated_arrival_date.isoformat()

def update_all_estimated_arrival_dates():
    """Update estimated_arrival_date for all shipments that have shipment_date and shipment_type"""
    
    print(f"Fetching shipments from {SHIPMENTS_TABLE}...")
    
    # Query all shipments that have both shipment_date and shipment_type
    query = f"""
    SELECT 
        shipment_id,
        shipment_date,
        shipment_type,
        estimated_arrival_date as current_estimated_arrival_date
    FROM `{SHIPMENTS_TABLE}`
    WHERE shipment_date IS NOT NULL 
      AND shipment_type IS NOT NULL
      AND shipment_type IN ('SLOW_SEA', 'FAST_SEA', 'AIR')
    ORDER BY shipment_date DESC
    """
    
    results = client.query(query).result()
    shipments = list(results)
    
    print(f"Found {len(shipments)} shipments to process...")
    
    updated_count = 0
    skipped_count = 0
    error_count = 0
    
    for shipment in shipments:
        shipment_id = shipment.shipment_id
        shipment_date = shipment.shipment_date
        shipment_type = shipment.shipment_type
        current_estimated = shipment.current_estimated_arrival_date
        
        # Calculate new estimated_arrival_date
        new_estimated_arrival_date = calculate_estimated_arrival_date(shipment_date, shipment_type)
        
        if not new_estimated_arrival_date:
            print(f"⚠️  Skipping {shipment_id}: Could not calculate estimated_arrival_date")
            skipped_count += 1
            continue
        
        # Check if update is needed
        if current_estimated:
            current_estimated_str = current_estimated.isoformat() if hasattr(current_estimated, 'isoformat') else str(current_estimated)
            if current_estimated_str == new_estimated_arrival_date:
                print(f"✓ {shipment_id}: Already correct ({new_estimated_arrival_date})")
                skipped_count += 1
                continue
        
        # Update the shipment
        try:
            update_query = f"""
            UPDATE `{SHIPMENTS_TABLE}`
            SET estimated_arrival_date = @estimated_arrival_date
            WHERE shipment_id = @shipment_id
            """
            
            job_config = bigquery.QueryJobConfig(
                query_parameters=[
                    bigquery.ScalarQueryParameter("estimated_arrival_date", "DATE", new_estimated_arrival_date),
                    bigquery.ScalarQueryParameter("shipment_id", "STRING", shipment_id)
                ]
            )
            
            client.query(update_query, job_config=job_config).result()
            
            old_value = current_estimated.isoformat() if current_estimated and hasattr(current_estimated, 'isoformat') else str(current_estimated) if current_estimated else "NULL"
            print(f"✅ Updated {shipment_id}: {old_value} → {new_estimated_arrival_date} ({shipment_type})")
            updated_count += 1
            
        except Exception as e:
            print(f"❌ Error updating {shipment_id}: {str(e)}")
            error_count += 1
    
    print("\n" + "="*60)
    print("Update Summary:")
    print("="*60)
    print(f"✅ Updated: {updated_count}")
    print(f"⏭️  Skipped: {skipped_count}")
    print(f"❌ Errors: {error_count}")
    print(f"📊 Total processed: {len(shipments)}")
    print("="*60)

if __name__ == "__main__":
    print("="*60)
    print("Updating Estimated Arrival Dates for All Shipments")
    print("="*60)
    print(f"Project: {PROJECT_ID}")
    print(f"Dataset: {DATASET}")
    print(f"Table: {SHIPMENTS_TABLE}")
    print("="*60)
    print()
    
    # Confirm before proceeding
    response = input("This will update all shipments. Continue? (yes/no): ")
    if response.lower() != 'yes':
        print("Cancelled.")
        exit(0)
    
    print()
    update_all_estimated_arrival_dates()
    print("\n✅ Done!")
