# Update Estimated Arrival Dates for All Shipments

This script updates all existing shipments' `estimated_arrival_date` based on the new logic:
- **SLOW_SEA**: shipment_date + 33 days
- **FAST_SEA**: shipment_date + 27 days
- **AIR**: shipment_date + 10 days

## Option 1: Run SQL Script (Recommended - Fastest)

1. Open BigQuery Console: https://console.cloud.google.com/bigquery?project=onyga-482313

2. Run the SQL script: `update_estimated_arrival_dates_sql.sql`

   Or copy/paste this SQL:
   ```sql
   UPDATE `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS`
   SET estimated_arrival_date = 
     CASE 
       WHEN shipment_type = 'SLOW_SEA' THEN DATE_ADD(shipment_date, INTERVAL 33 DAY)
       WHEN shipment_type = 'FAST_SEA' THEN DATE_ADD(shipment_date, INTERVAL 27 DAY)
       WHEN shipment_type = 'AIR' THEN DATE_ADD(shipment_date, INTERVAL 10 DAY)
       ELSE estimated_arrival_date
     END
   WHERE shipment_date IS NOT NULL 
     AND shipment_type IS NOT NULL
     AND shipment_type IN ('SLOW_SEA', 'FAST_SEA', 'AIR');
   ```

3. Check results:
   ```sql
   SELECT 
     shipment_id,
     shipment_date,
     shipment_type,
     estimated_arrival_date,
     DATE_DIFF(estimated_arrival_date, shipment_date, DAY) as days_difference
   FROM `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS`
   WHERE shipment_date IS NOT NULL 
     AND shipment_type IS NOT NULL
     AND shipment_type IN ('SLOW_SEA', 'FAST_SEA', 'AIR')
   ORDER BY shipment_date DESC
   LIMIT 20;
   ```

## Option 2: Run Python Script

1. Make sure you have the required packages:
   ```bash
   pip install google-cloud-bigquery python-dotenv
   ```

2. Set environment variables (or use .env file):
   ```bash
   export GCP_PROJECT_ID=onyga-482313
   export BIGQUERY_DATASET=OI
   ```

3. Run the script:
   ```bash
   python update_estimated_arrival_dates.py
   ```

4. Confirm when prompted: type `yes` to proceed

## What It Does

- Finds all shipments that have both `shipment_date` and `shipment_type`
- Calculates `estimated_arrival_date` based on the shipment type
- Updates the shipments in BigQuery
- Shows a summary of updated/skipped/error counts

## Safety

- Only updates shipments that have both `shipment_date` and `shipment_type`
- Only processes shipments with types: SLOW_SEA, FAST_SEA, AIR
- The SQL version uses a single UPDATE statement (atomic operation)
- The Python version processes one by one with error handling

## Recommendation

**Use Option 1 (SQL)** - It's faster, atomic, and easier to run directly in BigQuery console.
