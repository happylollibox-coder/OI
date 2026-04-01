#!/usr/bin/env python3
"""
Run merge feasibility check queries in BigQuery
Extracts and runs each query from check_merge_feasibility.sql
"""
import sys
import os
from google.cloud import bigquery

def extract_queries(sql_content):
    """Extract individual queries from SQL content"""
    import re
    
    # Split by query separators (lines with -- =====)
    parts = re.split(r'-- =+.*?=+\n', sql_content)
    queries = []
    
    for part in parts[1:]:  # Skip first part (header)
        lines = [l for l in part.split('\n') if l.strip() and not l.strip().startswith('--')]
        if lines:
            query = '\n'.join(lines).strip()
            if query and (query.startswith('WITH') or query.startswith('SELECT')):
                queries.append(query)
    
    return queries

def run_query(client, query, description):
    """Run a BigQuery query and print results"""
    print(f"\n{'='*80}")
    print(f"{description}")
    print(f"{'='*80}\n")
    
    try:
        query_job = client.query(query)
        results = query_job.result()
        
        # Convert to list to avoid iterator issues
        rows = list(results)
        
        if rows:
            # Get column names from first row
            columns = list(rows[0].keys())
            
            # Print header
            print(" | ".join(columns))
            print("-" * 80)
            
            # Print rows
            for row in rows:
                values = [str(row[col]) if row[col] is not None else 'NULL' for col in columns]
                print(" | ".join(values))
            
            print(f"\nTotal rows: {len(rows)}\n")
        else:
            print("No results returned.\n")
        
        return rows
    except Exception as e:
        print(f"❌ Error running query: {e}\n")
        import traceback
        traceback.print_exc()
        return None

def main():
    # Get script directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    sql_file = os.path.join(script_dir, "check_merge_feasibility.sql")
    
    # Read the SQL file
    try:
        with open(sql_file, 'r') as f:
            content = f.read()
    except FileNotFoundError:
        print(f"❌ Error: Could not find {sql_file}")
        sys.exit(1)
    
    # Extract queries
    queries = extract_queries(content)
    
    if not queries:
        print("❌ No queries found in SQL file")
        sys.exit(1)
    
    print(f"Found {len(queries)} queries to run\n")
    
    # Initialize BigQuery client
    try:
        client = bigquery.Client()
    except Exception as e:
        print(f"❌ Error initializing BigQuery client: {e}")
        print("Make sure you have:")
        print("1. Installed google-cloud-bigquery: pip install google-cloud-bigquery")
        print("2. Authenticated: gcloud auth application-default login")
        sys.exit(1)
    
    # Descriptions for each query
    descriptions = [
        "1. MERGE FEASIBILITY SUMMARY",
        "2. COLUMN COMPARISON (Detailed)",
        "3. DATA OVERLAP ANALYSIS",
        "4. SAMPLE DATA - SCP Table",
        "5. SAMPLE DATA - OpenBridge Table"
    ]
    
    # Run each query
    for i, query in enumerate(queries):
        desc = descriptions[i] if i < len(descriptions) else f"Query {i+1}"
        run_query(client, query, desc)
    
    print(f"\n{'='*80}")
    print("✅ All queries completed!")
    print(f"{'='*80}\n")

if __name__ == "__main__":
    main()
