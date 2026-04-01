#!/usr/bin/env python3
"""
ASIN Tables Insights Generator (Standard Library Version)
Analyzes SQP_ASIN_View_Simple_Week CSV data to generate actionable insights
Uses only Python standard library - no dependencies required
"""

import csv
from collections import defaultdict
from datetime import datetime

CSV_PATH = '../../Data/amazon data/Reports/SQP_ASIN_View_Simple_Week.csv'

def safe_int(value):
    """Safely convert to int"""
    try:
        return int(float(value)) if value else 0
    except:
        return 0

def safe_float(value):
    """Safely convert to float"""
    try:
        return float(value) if value else 0.0
    except:
        return 0.0

def load_data():
    """Load CSV data"""
    print("Loading data from CSV...")
    data = []
    with open(CSV_PATH, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data.append(row)
    print(f"✓ Loaded {len(data):,} rows")
    return data

def insight_1_top_queries(data):
    """Top performing search queries"""
    print("\n" + "="*80)
    print("INSIGHT 1: TOP PERFORMING SEARCH QUERIES")
    print("="*80)
    
    query_stats = defaultdict(lambda: {
        'impressions': 0, 'clicks': 0, 'cart_adds': 0, 'purchases': 0,
        'scores': [], 'volumes': [], 'skus': set()
    })
    
    for row in data:
        query = row.get('Search_Query', '')
        query_stats[query]['impressions'] += safe_int(row.get('Impressions_Total_Count', 0))
        query_stats[query]['clicks'] += safe_int(row.get('Clicks_Total_Count', 0))
        query_stats[query]['cart_adds'] += safe_int(row.get('Cart_Adds_Total_Count', 0))
        query_stats[query]['purchases'] += safe_int(row.get('Purchases_Total_Count', 0))
        query_stats[query]['scores'].append(safe_float(row.get('Search_Query_Score', 0)))
        query_stats[query]['volumes'].append(safe_int(row.get('Search_Query_Volume', 0)))
        query_stats[query]['skus'].add(row.get('SKU', ''))
    
    # Calculate metrics
    query_results = []
    for query, stats in query_stats.items():
        if stats['purchases'] >= 10:
            ctr = (stats['clicks'] / stats['impressions'] * 100) if stats['impressions'] > 0 else 0
            conversion = (stats['purchases'] / stats['clicks'] * 100) if stats['clicks'] > 0 else 0
            avg_score = sum(stats['scores']) / len(stats['scores']) if stats['scores'] else 0
            max_volume = max(stats['volumes']) if stats['volumes'] else 0
            
            query_results.append({
                'query': query,
                'purchases': stats['purchases'],
                'conversion': conversion,
                'ctr': ctr,
                'impressions': stats['impressions'],
                'clicks': stats['clicks'],
                'score': avg_score,
                'volume': max_volume
            })
    
    query_results.sort(key=lambda x: x['purchases'], reverse=True)
    
    print(f"\nTotal unique queries: {len(query_stats)}")
    print(f"Queries with 10+ purchases: {len(query_results)}")
    print("\nTop 20 Queries by Purchases:")
    print("-" * 80)
    
    for i, q in enumerate(query_results[:20], 1):
        query_short = q['query'][:58] + '..' if len(q['query']) > 60 else q['query']
        print(f"\n{i:2d}. {query_short}")
        print(f"    Purchases: {q['purchases']:,} | Conversion: {q['conversion']:.2f}% | CTR: {q['ctr']:.2f}%")
        print(f"    Impressions: {q['impressions']:,} | Clicks: {q['clicks']:,} | Score: {q['score']:.1f}")
    
    return query_results[:20]

def insight_2_shipping_impact(data):
    """Shipping speed impact"""
    print("\n" + "="*80)
    print("INSIGHT 2: SHIPPING SPEED IMPACT ON CONVERSION")
    print("="*80)
    
    shipping = {
        'Same Day': {'clicks': 0, 'purchases': 0},
        '1 Day': {'clicks': 0, 'purchases': 0},
        '2 Day': {'clicks': 0, 'purchases': 0}
    }
    
    for row in data:
        shipping['Same Day']['clicks'] += safe_int(row.get('Clicks_Same_Day_Shipping_Speed', 0))
        shipping['Same Day']['purchases'] += safe_int(row.get('Purchases_Same_Day_Shipping_Speed', 0))
        shipping['1 Day']['clicks'] += safe_int(row.get('Clicks_1D_Shipping_Speed', 0))
        shipping['1 Day']['purchases'] += safe_int(row.get('Purchases_1D_Shipping_Speed', 0))
        shipping['2 Day']['clicks'] += safe_int(row.get('Clicks_2D_Shipping_Speed', 0))
        shipping['2 Day']['purchases'] += safe_int(row.get('Purchases_2D_Shipping_Speed', 0))
    
    print("\nConversion Rates by Shipping Speed:")
    print("-" * 80)
    
    best_rate = 0
    best_speed = ''
    for speed, stats in shipping.items():
        conversion = (stats['purchases'] / stats['clicks'] * 100) if stats['clicks'] > 0 else 0
        if conversion > best_rate:
            best_rate = conversion
            best_speed = speed
        
        print(f"{speed:15s} | Clicks: {stats['clicks']:>8,} | "
              f"Purchases: {stats['purchases']:>6,} | Conversion: {conversion:>6.2f}%")
    
    print(f"\n📊 Best performing: {best_speed} shipping ({best_rate:.2f}% conversion)")
    
    return shipping

def insight_3_data_summary(data):
    """Data summary"""
    print("\n" + "="*80)
    print("INSIGHT 3: DATA SUMMARY")
    print("="*80)
    
    skus = set()
    queries = set()
    total_impressions = 0
    total_clicks = 0
    total_purchases = 0
    total_cart_adds = 0
    
    weeks = set()
    
    for row in data:
        skus.add(row.get('SKU', ''))
        queries.add(row.get('Search_Query', ''))
        total_impressions += safe_int(row.get('Impressions_Total_Count', 0))
        total_clicks += safe_int(row.get('Clicks_Total_Count', 0))
        total_purchases += safe_int(row.get('Purchases_Total_Count', 0))
        total_cart_adds += safe_int(row.get('Cart_Adds_Total_Count', 0))
        
        week_key = f"{row.get('Year', '')}-{row.get('Week', '')}"
        weeks.add(week_key)
    
    ctr = (total_clicks / total_impressions * 100) if total_impressions > 0 else 0
    conversion = (total_purchases / total_clicks * 100) if total_clicks > 0 else 0
    cart_rate = (total_purchases / total_cart_adds * 100) if total_cart_adds > 0 else 0
    
    print(f"\nDataset Overview:")
    print("-" * 80)
    print(f"Total Rows:           {len(data):>12,}")
    print(f"Unique SKUs:          {len(skus):>12,}")
    print(f"Unique Queries:       {len(queries):>12,}")
    print(f"Unique Weeks:         {len(weeks):>12}")
    
    print(f"\nPerformance Metrics:")
    print("-" * 80)
    print(f"Total Impressions:    {total_impressions:>12,}")
    print(f"Total Clicks:         {total_clicks:>12,}")
    print(f"Total Cart Adds:      {total_cart_adds:>12,}")
    print(f"Total Purchases:      {total_purchases:>12,}")
    
    print(f"\nOverall Rates:")
    print("-" * 80)
    print(f"CTR:                  {ctr:>12.2f}%")
    print(f"Conversion Rate:      {conversion:>12.2f}%")
    print(f"Cart to Purchase:     {cart_rate:>12.2f}%")
    
    return {
        'rows': len(data),
        'skus': len(skus),
        'queries': len(queries),
        'impressions': total_impressions,
        'clicks': total_clicks,
        'purchases': total_purchases,
        'ctr': ctr,
        'conversion': conversion
    }

def insight_4_price_analysis(data):
    """Price sensitivity analysis"""
    print("\n" + "="*80)
    print("INSIGHT 4: PRICE SENSITIVITY ANALYSIS")
    print("="*80)
    
    price_ranges = {
        '< $15': {'clicks': 0, 'purchases': 0, 'prices': []},
        '$15-$25': {'clicks': 0, 'purchases': 0, 'prices': []},
        '$25-$35': {'clicks': 0, 'purchases': 0, 'prices': []},
        '$35-$50': {'clicks': 0, 'purchases': 0, 'prices': []},
        '> $50': {'clicks': 0, 'purchases': 0, 'prices': []}
    }
    
    for row in data:
        price = safe_float(row.get('Clicks_Price_ Median', 0))
        if price > 0:
            if price < 15:
                range_key = '< $15'
            elif price < 25:
                range_key = '$15-$25'
            elif price < 35:
                range_key = '$25-$35'
            elif price < 50:
                range_key = '$35-$50'
            else:
                range_key = '> $50'
            
            price_ranges[range_key]['clicks'] += safe_int(row.get('Clicks_Total_Count', 0))
            price_ranges[range_key]['purchases'] += safe_int(row.get('Purchases_Total_Count', 0))
            price_ranges[range_key]['prices'].append(price)
    
    print("\nPerformance by Price Range:")
    print("-" * 80)
    
    best_conversion = 0
    best_range = ''
    for range_key, stats in price_ranges.items():
        if stats['clicks'] > 0:
            conversion = (stats['purchases'] / stats['clicks'] * 100)
            avg_price = sum(stats['prices']) / len(stats['prices']) if stats['prices'] else 0
            
            if conversion > best_conversion:
                best_conversion = conversion
                best_range = range_key
            
            print(f"\n{range_key:10s} (Avg: ${avg_price:.2f})")
            print(f"  Clicks: {stats['clicks']:>8,} | Purchases: {stats['purchases']:>6,}")
            print(f"  Conversion: {conversion:>6.2f}%")
    
    print(f"\n📊 Sweet spot: {best_range} range ({best_conversion:.2f}% conversion)")
    
    return price_ranges

def insight_5_underperforming_queries(data):
    """Underperforming queries"""
    print("\n" + "="*80)
    print("INSIGHT 5: UNDERPERFORMING QUERIES (Optimization Opportunities)")
    print("="*80)
    
    query_stats = defaultdict(lambda: {'impressions': 0, 'clicks': 0, 'purchases': 0})
    
    for row in data:
        query = row.get('Search_Query', '')
        query_stats[query]['impressions'] += safe_int(row.get('Impressions_Total_Count', 0))
        query_stats[query]['clicks'] += safe_int(row.get('Clicks_Total_Count', 0))
        query_stats[query]['purchases'] += safe_int(row.get('Purchases_Total_Count', 0))
    
    underperforming = []
    for query, stats in query_stats.items():
        if stats['impressions'] >= 1000:
            ctr = (stats['clicks'] / stats['impressions'] * 100) if stats['impressions'] > 0 else 0
            conversion = (stats['purchases'] / stats['clicks'] * 100) if stats['clicks'] > 0 else 0
            
            if (conversion < 2.0 or ctr < 3.0) and stats['purchases'] < 5:
                underperforming.append({
                    'query': query,
                    'impressions': stats['impressions'],
                    'ctr': ctr,
                    'conversion': conversion,
                    'purchases': stats['purchases']
                })
    
    underperforming.sort(key=lambda x: x['impressions'], reverse=True)
    
    print(f"\nFound {len(underperforming)} underperforming queries")
    print("\nTop 15 by Impressions (Low Conversion):")
    print("-" * 80)
    
    for i, q in enumerate(underperforming[:15], 1):
        issue = "LOW_CONVERSION" if q['conversion'] < 2.0 else "LOW_CTR"
        query_short = q['query'][:56] + '..' if len(q['query']) > 58 else q['query']
        print(f"\n{i:2d}. {query_short}")
        print(f"    Impressions: {q['impressions']:,} | CTR: {q['ctr']:.2f}% | "
              f"Conversion: {q['conversion']:.2f}% | Issue: {issue}")
        print(f"    Purchases: {q['purchases']} (Opportunity for improvement)")
    
    return underperforming[:15]

def main():
    """Main execution"""
    print("="*80)
    print("ASIN DATA INSIGHTS ANALYSIS (Standard Library Version)")
    print("="*80)
    
    data = load_data()
    
    # Generate insights
    summary = insight_3_data_summary(data)
    top_queries = insight_1_top_queries(data)
    shipping = insight_2_shipping_impact(data)
    price = insight_4_price_analysis(data)
    underperforming = insight_5_underperforming_queries(data)
    
    print("\n" + "="*80)
    print("ANALYSIS COMPLETE")
    print("="*80)
    print("\n💡 Key Takeaways:")
    print(f"   • {summary['queries']:,} unique search queries analyzed")
    print(f"   • {summary['purchases']:,} total purchases tracked")
    print(f"   • Overall conversion rate: {summary['conversion']:.2f}%")
    print(f"   • Overall CTR: {summary['ctr']:.2f}%")
    if top_queries:
        print(f"   • Top query: '{top_queries[0]['query'][:50]}...' with {top_queries[0]['purchases']:,} purchases")
    print(f"   • {len(underperforming)} queries need optimization")
    print("\n" + "="*80)

if __name__ == '__main__':
    main()
