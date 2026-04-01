#!/usr/bin/env python3
"""
Correlation Analysis Executor
Finds strong correlations between paid and organic search performance
"""

import sys
import os
from pathlib import Path

# Try to import BigQuery client
try:
    from google.cloud import bigquery
    BQ_AVAILABLE = True
except ImportError:
    BQ_AVAILABLE = False
    print("Warning: google-cloud-bigquery not installed. Install with: pip install google-cloud-bigquery")

def execute_query(query_file, project_id='onyga-482313'):
    """Execute a BigQuery SQL file and return results"""
    if not BQ_AVAILABLE:
        print(f"ERROR: Cannot execute {query_file} - BigQuery client not available")
        print("Please install: pip install google-cloud-bigquery")
        return None
    
    try:
        client = bigquery.Client(project=project_id)
        
        # Read query file
        with open(query_file, 'r') as f:
            query = f.read()
        
        print(f"Executing query from {query_file}...")
        query_job = client.query(query)
        results = query_job.result()
        
        return results
    except Exception as e:
        print(f"Error executing query: {e}")
        return None

def analyze_correlations(results):
    """Analyze correlation results and find strong correlations"""
    if not results:
        return
    
    strong_correlations = []
    moderate_correlations = []
    
    print("\n" + "="*80)
    print("CORRELATION ANALYSIS RESULTS")
    print("="*80 + "\n")
    
    for row in results:
        # Try to get correlation_orders field
        correlation = None
        if hasattr(row, 'correlation_orders'):
            correlation = row.correlation_orders
        elif 'correlation_orders' in row:
            correlation = row['correlation_orders']
        
        if correlation is None:
            continue
        
        abs_corr = abs(correlation)
        
        if abs_corr >= 0.5:
            strong_correlations.append(row)
        elif abs_corr >= 0.3:
            moderate_correlations.append(row)
    
    # Report findings
    print(f"📊 STRONG CORRELATIONS (≥0.5): {len(strong_correlations)}")
    print(f"💡 MODERATE CORRELATIONS (≥0.3): {len(moderate_correlations)}\n")
    
    if strong_correlations:
        print("🔥 TOP STRONG CORRELATIONS:")
        print("-" * 80)
        for i, row in enumerate(strong_correlations[:20], 1):
            asin = getattr(row, 'asin', row.get('asin', 'N/A'))
            search_term = getattr(row, 'search_term', row.get('search_term', 'N/A'))
            corr = getattr(row, 'correlation_orders', row.get('correlation_orders', 0))
            paid_orders = getattr(row, 'total_paid_orders', row.get('total_paid_orders', 0))
            organic_orders = getattr(row, 'total_organic_orders', row.get('total_organic_orders', 0))
            
            print(f"{i}. ASIN: {asin}")
            print(f"   Search Term: {search_term}")
            print(f"   Correlation: {corr:.4f}")
            print(f"   Paid Orders: {paid_orders}, Organic Orders: {organic_orders}")
            print(f"   Gap: {paid_orders - organic_orders}")
            print()
    
    if not strong_correlations and moderate_correlations:
        print("💡 MODERATE CORRELATIONS (Top 10):")
        print("-" * 80)
        for i, row in enumerate(moderate_correlations[:10], 1):
            asin = getattr(row, 'asin', row.get('asin', 'N/A'))
            search_term = getattr(row, 'search_term', row.get('search_term', 'N/A'))
            corr = getattr(row, 'correlation_orders', row.get('correlation_orders', 0))
            paid_orders = getattr(row, 'total_paid_orders', row.get('total_paid_orders', 0))
            organic_orders = getattr(row, 'total_organic_orders', row.get('total_organic_orders', 0))
            
            print(f"{i}. ASIN: {asin}, Term: {search_term}")
            print(f"   Correlation: {corr:.4f}, Paid: {paid_orders}, Organic: {organic_orders}")
            print()
    
    if not strong_correlations and not moderate_correlations:
        print("⚠️  No strong correlations found (≥0.3)")
        print("   This may indicate:")
        print("   - Insufficient data overlap")
        print("   - Different time periods")
        print("   - Need to adjust analysis parameters")
    
    return strong_correlations, moderate_correlations

def main():
    script_dir = Path(__file__).parent
    query_file = script_dir / "COMPREHENSIVE_CORRELATION_FINDER.sql"
    
    if not query_file.exists():
        print(f"ERROR: Query file not found: {query_file}")
        sys.exit(1)
    
    print("="*80)
    print("CORRELATION ANALYSIS - Finding Strong Correlations")
    print("="*80)
    print()
    
    # Execute query
    results = execute_query(query_file)
    
    if results:
        # Analyze results
        strong, moderate = analyze_correlations(results)
        
        print("="*80)
        if strong:
            print(f"✅ SUCCESS: Found {len(strong)} strong correlations (≥0.5)")
            print("   Review the results above for actionable insights")
        elif moderate:
            print(f"💡 Found {len(moderate)} moderate correlations (≥0.3)")
            print("   Consider these for monitoring and optimization")
        else:
            print("⚠️  No strong correlations found")
            print("   Try running AGGRESSIVE_CORRELATION_HUNT.sql for alternative strategies")
        print("="*80)
    else:
        print("\n❌ Failed to execute query")
        print("   Try running the SQL file directly in BigQuery console:")
        print(f"   {query_file}")

if __name__ == "__main__":
    main()
