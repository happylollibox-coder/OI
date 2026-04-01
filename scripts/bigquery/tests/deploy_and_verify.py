#!/usr/bin/env python3
"""
Deploy and Verify Fix for Sales Discrepancy
Deploys the updated SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY and verifies results
"""

import sys
import os
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    from google.cloud import bigquery
except ImportError:
    print("ERROR: google-cloud-bigquery not installed.")
    print("Install with: pip install google-cloud-bigquery")
    sys.exit(1)

PROJECT_ID = "onyga-482313"
DATASET = "OI"

def read_sql_file(file_path):
    """Read SQL file contents"""
    with open(file_path, 'r') as f:
        return f.read()

def deploy_stored_procedure(client):
    """Deploy the updated stored procedure"""
    print("=" * 60)
    print("Step 1: Deploying Updated Stored Procedure")
    print("=" * 60)
    
    sp_file = Path(__file__).parent.parent / "SP" / "SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY.sql"
    
    if not sp_file.exists():
        print(f"ERROR: File not found: {sp_file}")
        return False
    
    sql = read_sql_file(sp_file)
    
    # Verify the fix is present
    if "SUM(COALESCE(sales, 0)) AS sales" in sql:
        print("✅ Fix confirmed in SQL file (SUM instead of MAX)")
    else:
        print("⚠️  WARNING: Fix not found in SQL file!")
        return False
    
    try:
        query_job = client.query(sql)
        query_job.result()  # Wait for completion
        print("✅ Stored procedure deployed successfully")
        return True
    except Exception as e:
        print(f"❌ Failed to deploy stored procedure: {e}")
        return False

def run_stored_procedure(client):
    """Run the stored procedure"""
    print("\n" + "=" * 60)
    print("Step 2: Running Stored Procedure")
    print("=" * 60)
    
    sql = f"CALL `{PROJECT_ID}.{DATASET}.SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY`();"
    
    try:
        query_job = client.query(sql)
        results = query_job.result()
        
        # Print any output from the procedure
        for row in results:
            print(row)
        
        print("✅ Stored procedure executed successfully")
        return True
    except Exception as e:
        print(f"❌ Failed to execute stored procedure: {e}")
        return False

def verify_results(client):
    """Verify the results for Jan 29, 2026"""
    print("\n" + "=" * 60)
    print("Step 3: Verifying Results for Jan 29, 2026")
    print("=" * 60)
    
    sql = f"""
    SELECT 
      DATE('2026-01-29') AS date,
      SUM(sales) AS total_sales,
      SUM(CASE WHEN Performance_TYPE = 'Ads' THEN sales ELSE 0 END) AS ads_sales,
      SUM(CASE WHEN Performance_TYPE = 'Organic' THEN sales ELSE 0 END) AS organic_sales,
      3069.0 AS expected_sales,
      SUM(sales) - 3069.0 AS difference,
      ROUND((SUM(sales) - 3069.0) / 3069.0 * 100, 2) AS difference_pct,
      COUNT(*) AS record_count,
      COUNT(DISTINCT most_advertised_asin) AS distinct_asins
    FROM `{PROJECT_ID}.{DATASET}.FACT_AMAZON_PERFORMANCE_DAILY`
    WHERE date = '2026-01-29'
    """
    
    try:
        query_job = client.query(sql)
        results = query_job.result()
        
        print("\nResults:")
        print("-" * 60)
        for row in results:
            print(f"Date: {row.date}")
            print(f"Total Sales: ${row.total_sales:,.2f}")
            print(f"Ads Sales: ${row.ads_sales:,.2f}")
            print(f"Organic Sales: ${row.organic_sales:,.2f}")
            print(f"Expected Sales: ${row.expected_sales:,.2f}")
            print(f"Difference: ${row.difference:,.2f}")
            print(f"Difference %: {row.difference_pct}%")
            print(f"Record Count: {row.record_count}")
            print(f"Distinct ASINs: {row.distinct_asins}")
            print("-" * 60)
            
            # Evaluate results
            if abs(row.difference) < 50:
                print("✅ SUCCESS: Difference is within acceptable range (< $50)")
            elif abs(row.difference) < 200:
                print("⚠️  WARNING: Difference is moderate ($50-$200)")
            else:
                print("❌ ISSUE: Difference is still large (> $200)")
                print("   Please check the diagnostic queries.")
        
        return True
    except Exception as e:
        print(f"❌ Failed to verify results: {e}")
        return False

def compare_with_source(client):
    """Compare with source data"""
    print("\n" + "=" * 60)
    print("Step 4: Comparing with Source Data")
    print("=" * 60)
    
    sql = f"""
    SELECT 
      'STG_AMAZON_PERFORMANCE (LOADED)' AS source,
      SUM(SALES_AMOUNT) AS total_sales
    FROM `{PROJECT_ID}.{DATASET}.STG_AMAZON_PERFORMANCE`
    WHERE date = '2026-01-29' AND IS_LOADED = TRUE
    
    UNION ALL
    
    SELECT 
      'FACT_AMAZON_PERFORMANCE_DAILY',
      SUM(sales) AS total_sales
    FROM `{PROJECT_ID}.{DATASET}.FACT_AMAZON_PERFORMANCE_DAILY`
    WHERE date = '2026-01-29'
    """
    
    try:
        query_job = client.query(sql)
        results = query_job.result()
        
        print("\nSource Comparison:")
        print("-" * 60)
        for row in results:
            print(f"{row.source}: ${row.total_sales:,.2f}")
        print("-" * 60)
        
        return True
    except Exception as e:
        print(f"❌ Failed to compare with source: {e}")
        return False

def main():
    """Main execution"""
    print("Deploy and Verify Fix for Sales Discrepancy")
    print("=" * 60)
    
    # Initialize BigQuery client
    try:
        client = bigquery.Client(project=PROJECT_ID)
        print(f"✅ Connected to BigQuery project: {PROJECT_ID}\n")
    except Exception as e:
        print(f"❌ Failed to connect to BigQuery: {e}")
        print("\nMake sure you're authenticated:")
        print("  gcloud auth application-default login")
        sys.exit(1)
    
    # Execute steps
    success = True
    
    if not deploy_stored_procedure(client):
        success = False
    
    if success and not run_stored_procedure(client):
        success = False
    
    if success:
        verify_results(client)
        compare_with_source(client)
    
    print("\n" + "=" * 60)
    if success:
        print("✅ Deployment and verification completed!")
    else:
        print("❌ Deployment failed. Please check errors above.")
    print("=" * 60)
    
    return 0 if success else 1

if __name__ == "__main__":
    sys.exit(main())
