#!/usr/bin/env python3
"""
Test Runner for FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY Tests
Runs all three test suites and reports results
"""

import os
import sys
from pathlib import Path

# Add project root to path if needed
project_root = Path(__file__).parent.parent.parent.parent
sys.path.insert(0, str(project_root))

try:
    from google.cloud import bigquery
    from google.cloud.exceptions import GoogleCloudError
except ImportError:
    print("ERROR: google-cloud-bigquery not installed.")
    print("Install with: pip install google-cloud-bigquery")
    sys.exit(1)

PROJECT_ID = "onyga-482313"
DATASET = "OI"

# Objects required by each test (table or view names). If any are missing, the test is skipped.
TEST_REQUIREMENTS = {
    "test_fact_amazon_search_performance_001_source_to_target.sql": [],
    "test_fact_amazon_search_performance_002_ad_key_referential_integrity.sql": [
        "V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY",
    ],
    "test_fact_amazon_search_performance_003_factless_key_referential_integrity.sql": [
        "FACT_FACTLESS_BRIDGE",
    ],
}


def object_exists(client, project_id, dataset, object_name):
    """Check if a table or view exists in BigQuery."""
    try:
        query = f"""
        SELECT 1
        FROM `{project_id}.{dataset}.INFORMATION_SCHEMA.TABLES`
        WHERE table_name = '{object_name}'
        LIMIT 1
        """
        job = client.query(query, project=project_id)
        return len(list(job.result())) > 0
    except Exception:
        return False


def run_test(client, test_file_path, test_name, required_objects=None):
    """Run a single test SQL file and return results.
    Returns (success, error_msg). success=True for pass or skip; error_msg can be 'SKIP: ...'.
    """
    print(f"\n{'='*80}")
    print(f"Running: {test_name}")
    print(f"File: {test_file_path}")
    print(f"{'='*80}\n")

    # Skip if required objects are missing
    if required_objects:
        missing = [obj for obj in required_objects if not object_exists(client, PROJECT_ID, DATASET, obj)]
        if missing:
            skip_msg = (
                f"SKIP: Required object(s) not deployed: {', '.join(missing)}. "
                "Run deployment/run_migration_and_orchestrator.sh (or deploy views) to create them."
            )
            print(f"⏭️  {skip_msg}\n")
            return True, skip_msg

    try:
        # Read SQL file
        with open(test_file_path, 'r') as f:
            sql = f.read()
        
        # Execute query
        query_job = client.query(sql, project=PROJECT_ID)
        results = query_job.result()
        
        # Print results
        print("Results:")
        print("-" * 80)
        for row in results:
            # Print each field
            for key, value in row.items():
                if value is not None:
                    print(f"{key}: {value}")
            print("-" * 80)
        
        print(f"\n✅ Test completed: {test_name}\n")
        return True, None
        
    except GoogleCloudError as e:
        print(f"\n❌ Error running test: {test_name}")
        print(f"Error: {e}\n")
        return False, str(e)
    except Exception as e:
        print(f"\n❌ Unexpected error: {test_name}")
        print(f"Error: {e}\n")
        return False, str(e)

def main():
    """Main test runner"""
    print("="*80)
    print("FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY Test Suite")
    print("="*80)
    
    # Initialize BigQuery client
    try:
        client = bigquery.Client(project=PROJECT_ID)
        print(f"✅ Connected to BigQuery project: {PROJECT_ID}\n")
    except Exception as e:
        print(f"❌ Failed to connect to BigQuery: {e}")
        sys.exit(1)
    
    # Test files to run
    test_dir = Path(__file__).parent / "unit"
    tests = [
        ("test_fact_amazon_search_performance_001_source_to_target.sql", 
         "Test 1: Source to Target Data Integrity"),
        ("test_fact_amazon_search_performance_002_ad_key_referential_integrity.sql",
         "Test 2: ad_key Referential Integrity"),
        ("test_fact_amazon_search_performance_003_factless_key_referential_integrity.sql",
         "Test 3: factless_key Referential Integrity"),
    ]
    
    results = []
    
    # Run each test
    for test_file, test_name in tests:
        test_path = test_dir / test_file
        if not test_path.exists():
            print(f"⚠️  Test file not found: {test_path}")
            results.append((test_name, False, f"File not found: {test_path}"))
            continue

        required = TEST_REQUIREMENTS.get(test_file, [])
        success, error = run_test(client, test_path, test_name, required_objects=required)
        results.append((test_name, success, error))
    
    # Summary
    print("\n" + "="*80)
    print("TEST SUMMARY")
    print("="*80)
    
    passed = sum(1 for _, success, _ in results if success)
    total = len(results)
    
    for test_name, success, error in results:
        if success and error and str(error).startswith("SKIP"):
            status = "⏭️  SKIP"
        elif success:
            status = "✅ PASS"
        else:
            status = "❌ FAIL"
        print(f"{status}: {test_name}")
        if error and not str(error).startswith("SKIP"):
            print(f"   Error: {error}")
    
    print(f"\nTotal: {passed}/{total} tests passed")
    print("="*80)
    
    # Exit with error code if any test failed
    if passed < total:
        sys.exit(1)

if __name__ == "__main__":
    main()
