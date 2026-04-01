#!/usr/bin/env python3
"""
Revised SQP Insights Analysis - Understanding ASIN vs Market Metrics
Uses only Python standard library - no dependencies required

KEY UNDERSTANDING:
- Columns with "ASIN" in name = YOUR PRODUCT (SKU B09XQ56RK5) metrics
- Columns without "ASIN" = AMAZON-WIDE market metrics for that search term
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

def insight_1_market_share_leaders(data):
    """Queries where you have highest market share"""
    print("\n" + "="*80)
    print("INSIGHT 1: MARKET SHARE LEADERS (Your Product's Best Performers)")
    print("="*80)
    
    query_stats = defaultdict(lambda: {
        'market_purchases': 0, 'your_purchases': 0, 'your_share_pct': 0.0,
        'market_clicks': 0, 'your_clicks': 0, 'click_share_pct': 0.0,
        'market_impressions': 0, 'your_impressions': 0, 'impression_share_pct': 0.0
    })
    
    for row in data:
        query = row.get('Search_Query', '')
        query_stats[query]['market_purchases'] += safe_int(row.get('Purchases_Total_Count', 0))
        query_stats[query]['your_purchases'] += safe_int(row.get('Purchases_ASIN_Count', 0))
        query_stats[query]['market_clicks'] += safe_int(row.get('Clicks_Total_Count', 0))
        query_stats[query]['your_clicks'] += safe_int(row.get('Clicks_ASIN_Count', 0))
        query_stats[query]['market_impressions'] += safe_int(row.get('Impressions_Total_Count', 0))
        query_stats[query]['your_impressions'] += safe_int(row.get('Impressions_ASIN_Count', 0))
    
    # Calculate shares
    results = []
    for query, stats in query_stats.items():
        if stats['market_purchases'] > 0:
            purchase_share = (stats['your_purchases'] / stats['market_purchases'] * 100) if stats['market_purchases'] > 0 else 0
        else:
            purchase_share = 0
            
        click_share = (stats['your_clicks'] / stats['market_clicks'] * 100) if stats['market_clicks'] > 0 else 0
        impression_share = (stats['your_impressions'] / stats['market_impressions'] * 100) if stats['market_impressions'] > 0 else 0
        
        if stats['your_purchases'] > 0:  # Only queries where you have purchases
            results.append({
                'query': query,
                'market_purchases': stats['market_purchases'],
                'your_purchases': stats['your_purchases'],
                'purchase_share_pct': purchase_share,
                'click_share_pct': click_share,
                'impression_share_pct': impression_share
            })
    
    results.sort(key=lambda x: x['purchase_share_pct'], reverse=True)
    
    print(f"\nTotal queries where you have purchases: {len(results)}")
    print("\nTop 20 Queries by Market Share (Purchase Share %):")
    print("-" * 80)
    
    for i, q in enumerate(results[:20], 1):
        query_short = q['query'][:58] + '..' if len(q['query']) > 60 else q['query']
        print(f"\n{i:2d}. {query_short}")
        print(f"    Your Purchases: {q['your_purchases']:,} | Market Total: {q['market_purchases']:,}")
        print(f"    Purchase Share: {q['purchase_share_pct']:.2f}% | "
              f"Click Share: {q['click_share_pct']:.2f}% | "
              f"Impression Share: {q['impression_share_pct']:.2f}%")
    
    return results[:20]

def insight_2_high_opportunity_low_share(data):
    """Large markets where you have low market share"""
    print("\n" + "="*80)
    print("INSIGHT 2: HIGH OPPORTUNITY, LOW MARKET SHARE")
    print("="*80)
    
    query_stats = defaultdict(lambda: {
        'market_purchases': 0, 'your_purchases': 0,
        'market_clicks': 0, 'your_clicks': 0,
        'market_impressions': 0, 'your_impressions': 0
    })
    
    for row in data:
        query = row.get('Search_Query', '')
        query_stats[query]['market_purchases'] += safe_int(row.get('Purchases_Total_Count', 0))
        query_stats[query]['your_purchases'] += safe_int(row.get('Purchases_ASIN_Count', 0))
        query_stats[query]['market_clicks'] += safe_int(row.get('Clicks_Total_Count', 0))
        query_stats[query]['your_clicks'] += safe_int(row.get('Clicks_ASIN_Count', 0))
        query_stats[query]['market_impressions'] += safe_int(row.get('Impressions_Total_Count', 0))
        query_stats[query]['your_impressions'] += safe_int(row.get('Impressions_ASIN_Count', 0))
    
    opportunities = []
    for query, stats in query_stats.items():
        if stats['market_purchases'] >= 100:  # Large market
            purchase_share = (stats['your_purchases'] / stats['market_purchases'] * 100) if stats['market_purchases'] > 0 else 0
            
            if purchase_share < 1.0:  # Low share
                opportunities.append({
                    'query': query,
                    'market_purchases': stats['market_purchases'],
                    'your_purchases': stats['your_purchases'],
                    'purchase_share_pct': purchase_share,
                    'market_clicks': stats['market_clicks'],
                    'your_clicks': stats['your_clicks'],
                    'opportunity_size': stats['market_purchases'] - stats['your_purchases']
                })
    
    opportunities.sort(key=lambda x: x['market_purchases'], reverse=True)
    
    print(f"\nFound {len(opportunities)} queries with large markets (>100 purchases) but low share (<1%)")
    print("\nTop 20 Opportunities (Sorted by Market Size):")
    print("-" * 80)
    
    for i, q in enumerate(opportunities[:20], 1):
        query_short = q['query'][:56] + '..' if len(q['query']) > 58 else q['query']
        print(f"\n{i:2d}. {query_short}")
        print(f"    Market Size: {q['market_purchases']:,} purchases | Your Share: {q['purchase_share_pct']:.2f}%")
        print(f"    Your Purchases: {q['your_purchases']:,} | "
              f"Opportunity: {q['opportunity_size']:,} additional purchases")
        print(f"    Market Clicks: {q['market_clicks']:,} | Your Clicks: {q['your_clicks']:,}")
    
    return opportunities[:20]

def insight_3_conversion_benchmarking(data):
    """Your conversion rate vs market conversion rate"""
    print("\n" + "="*80)
    print("INSIGHT 3: CONVERSION RATE BENCHMARKING (Your Product vs Market)")
    print("="*80)
    
    query_stats = defaultdict(lambda: {
        'market_clicks': 0, 'market_purchases': 0,
        'your_clicks': 0, 'your_purchases': 0
    })
    
    for row in data:
        query = row.get('Search_Query', '')
        query_stats[query]['market_clicks'] += safe_int(row.get('Clicks_Total_Count', 0))
        query_stats[query]['market_purchases'] += safe_int(row.get('Purchases_Total_Count', 0))
        query_stats[query]['your_clicks'] += safe_int(row.get('Clicks_ASIN_Count', 0))
        query_stats[query]['your_purchases'] += safe_int(row.get('Purchases_ASIN_Count', 0))
    
    conversion_comparison = []
    for query, stats in query_stats.items():
        if stats['your_clicks'] > 0 and stats['market_clicks'] > 0:
            market_conv = (stats['market_purchases'] / stats['market_clicks'] * 100) if stats['market_clicks'] > 0 else 0
            your_conv = (stats['your_purchases'] / stats['your_clicks'] * 100) if stats['your_clicks'] > 0 else 0
            delta = your_conv - market_conv
            
            if stats['your_clicks'] >= 10:  # Minimum clicks threshold
                conversion_comparison.append({
                    'query': query,
                    'market_conversion': market_conv,
                    'your_conversion': your_conv,
                    'conversion_delta': delta,
                    'your_clicks': stats['your_clicks'],
                    'your_purchases': stats['your_purchases']
                })
    
    # Sort by absolute delta (biggest differences first)
    conversion_comparison.sort(key=lambda x: abs(x['conversion_delta']), reverse=True)
    
    print(f"\nQueries with ≥10 clicks: {len(conversion_comparison)}")
    print("\nTop 20 Queries: Your Conversion vs Market Conversion")
    print("-" * 80)
    
    outperforming = [q for q in conversion_comparison if q['conversion_delta'] > 0]
    underperforming = [q for q in conversion_comparison if q['conversion_delta'] < 0]
    
    print(f"\n📈 Outperforming Market ({len(outperforming)} queries):")
    for i, q in enumerate(outperforming[:10], 1):
        query_short = q['query'][:55] + '..' if len(q['query']) > 57 else q['query']
        print(f"  {i:2d}. {query_short}")
        print(f"      Your Conversion: {q['your_conversion']:.2f}% | "
              f"Market: {q['market_conversion']:.2f}% | "
              f"Delta: +{q['conversion_delta']:.2f}%")
    
    print(f"\n📉 Underperforming Market ({len(underperforming)} queries):")
    for i, q in enumerate(underperforming[:10], 1):
        query_short = q['query'][:55] + '..' if len(q['query']) > 57 else q['query']
        print(f"  {i:2d}. {query_short}")
        print(f"      Your Conversion: {q['your_conversion']:.2f}% | "
              f"Market: {q['market_conversion']:.2f}% | "
              f"Delta: {q['conversion_delta']:.2f}%")
    
    return conversion_comparison

def insight_4_price_competitiveness(data):
    """Your price vs market median price"""
    print("\n" + "="*80)
    print("INSIGHT 4: PRICE COMPETITIVENESS ANALYSIS")
    print("="*80)
    
    query_stats = defaultdict(lambda: {
        'market_price': [], 'your_price': [],
        'your_clicks': 0, 'your_share_pct': 0.0
    })
    
    for row in data:
        query = row.get('Search_Query', '')
        market_price = safe_float(row.get('Clicks_Price_ Median', 0))
        your_price = safe_float(row.get('Clicks_ASIN_Price_ Median', 0))
        your_clicks = safe_int(row.get('Clicks_ASIN_Count', 0))
        share_pct = safe_float(row.get('Clicks_ASIN_Share_%', 0))
        
        if market_price > 0 and your_price > 0:
            query_stats[query]['market_price'].append(market_price)
            query_stats[query]['your_price'].append(your_price)
            query_stats[query]['your_clicks'] += your_clicks
            query_stats[query]['your_share_pct'] = max(query_stats[query]['your_share_pct'], share_pct)
    
    price_analysis = []
    for query, stats in query_stats.items():
        if stats['market_price'] and stats['your_price']:
            market_median = sum(stats['market_price']) / len(stats['market_price'])
            your_median = sum(stats['your_price']) / len(stats['your_price'])
            price_diff = your_median - market_median
            price_diff_pct = (price_diff / market_median * 100) if market_median > 0 else 0
            
            if stats['your_clicks'] >= 5:  # Minimum threshold
                price_analysis.append({
                    'query': query,
                    'market_median_price': market_median,
                    'your_price': your_median,
                    'price_difference': price_diff,
                    'price_difference_pct': price_diff_pct,
                    'your_clicks': stats['your_clicks'],
                    'your_share_pct': stats['your_share_pct']
                })
    
    price_analysis.sort(key=lambda x: abs(x['price_difference']), reverse=True)
    
    print(f"\nQueries with price data: {len(price_analysis)}")
    print("\nPrice Competitiveness Analysis:")
    print("-" * 80)
    
    expensive = [q for q in price_analysis if q['price_difference'] > 5]
    competitive = [q for q in price_analysis if abs(q['price_difference']) <= 5]
    cheap = [q for q in price_analysis if q['price_difference'] < -5]
    
    print(f"\n💵 Your Price Higher by >$5 ({len(expensive)} queries):")
    for i, q in enumerate(expensive[:10], 1):
        query_short = q['query'][:50] + '..' if len(q['query']) > 52 else q['query']
        print(f"  {i:2d}. {query_short}")
        print(f"      Your Price: ${q['your_price']:.2f} | Market: ${q['market_median_price']:.2f} | "
              f"Diff: +${q['price_difference']:.2f} ({q['price_difference_pct']:.1f}%)")
        print(f"      Your Click Share: {q['your_share_pct']:.2f}%")
    
    print(f"\n⚖️  Price Competitive (within $5) ({len(competitive)} queries):")
    print("   (These may be your best opportunities)")
    for i, q in enumerate(competitive[:10], 1):
        query_short = q['query'][:50] + '..' if len(q['query']) > 52 else q['query']
        print(f"  {i:2d}. {query_short}")
        print(f"      Your Price: ${q['your_price']:.2f} | Market: ${q['market_median_price']:.2f} | "
              f"Your Click Share: {q['your_share_pct']:.2f}%")
    
    return price_analysis

def insight_5_summary_metrics(data):
    """Summary metrics: your product vs market"""
    print("\n" + "="*80)
    print("INSIGHT 5: SUMMARY - YOUR PRODUCT vs MARKET")
    print("="*80)
    
    total_market_impressions = 0
    total_your_impressions = 0
    total_market_clicks = 0
    total_your_clicks = 0
    total_market_purchases = 0
    total_your_purchases = 0
    
    for row in data:
        total_market_impressions += safe_int(row.get('Impressions_Total_Count', 0))
        total_your_impressions += safe_int(row.get('Impressions_ASIN_Count', 0))
        total_market_clicks += safe_int(row.get('Clicks_Total_Count', 0))
        total_your_clicks += safe_int(row.get('Clicks_ASIN_Count', 0))
        total_market_purchases += safe_int(row.get('Purchases_Total_Count', 0))
        total_your_purchases += safe_int(row.get('Purchases_ASIN_Count', 0))
    
    impression_share = (total_your_impressions / total_market_impressions * 100) if total_market_impressions > 0 else 0
    click_share = (total_your_clicks / total_market_clicks * 100) if total_market_clicks > 0 else 0
    purchase_share = (total_your_purchases / total_market_purchases * 100) if total_market_purchases > 0 else 0
    
    market_ctr = (total_market_clicks / total_market_impressions * 100) if total_market_impressions > 0 else 0
    your_ctr = (total_your_clicks / total_your_impressions * 100) if total_your_impressions > 0 else 0
    
    market_conversion = (total_market_purchases / total_market_clicks * 100) if total_market_clicks > 0 else 0
    your_conversion = (total_your_purchases / total_your_clicks * 100) if total_your_clicks > 0 else 0
    
    print("\nOverall Market Share:")
    print("-" * 80)
    print(f"Impression Share: {impression_share:.4f}% ({total_your_impressions:,} / {total_market_impressions:,})")
    print(f"Click Share:      {click_share:.4f}% ({total_your_clicks:,} / {total_market_clicks:,})")
    print(f"Purchase Share:   {purchase_share:.4f}% ({total_your_purchases:,} / {total_market_purchases:,})")
    
    print("\nPerformance Metrics:")
    print("-" * 80)
    print(f"Market CTR:       {market_ctr:.2f}%")
    print(f"Your CTR:         {your_ctr:.2f}%")
    print(f"CTR Delta:        {your_ctr - market_ctr:.2f}%")
    
    print(f"\nMarket Conversion: {market_conversion:.2f}%")
    print(f"Your Conversion:   {your_conversion:.2f}%")
    print(f"Conversion Delta:  {your_conversion - market_conversion:.2f}%")
    
    return {
        'impression_share': impression_share,
        'click_share': click_share,
        'purchase_share': purchase_share,
        'your_ctr': your_ctr,
        'market_ctr': market_ctr,
        'your_conversion': your_conversion,
        'market_conversion': market_conversion
    }

def main():
    """Main execution"""
    print("="*80)
    print("REVISED SQP INSIGHTS ANALYSIS")
    print("Understanding: ASIN columns = YOUR PRODUCT | Others = MARKET-WIDE")
    print("="*80)
    
    data = load_data()
    
    # Generate insights
    summary = insight_5_summary_metrics(data)
    market_leaders = insight_1_market_share_leaders(data)
    opportunities = insight_2_high_opportunity_low_share(data)
    conversion_bench = insight_3_conversion_benchmarking(data)
    price_comp = insight_4_price_competitiveness(data)
    
    print("\n" + "="*80)
    print("ANALYSIS COMPLETE")
    print("="*80)
    print("\n💡 Key Takeaways:")
    print(f"   • Overall Purchase Share: {summary['purchase_share']:.4f}% of market")
    print(f"   • Your Conversion Rate: {summary['your_conversion']:.2f}% (Market: {summary['market_conversion']:.2f}%)")
    print(f"   • {len(market_leaders)} queries where you're winning market share")
    print(f"   • {len(opportunities)} high-opportunity queries with low share")
    print("\n" + "="*80)

if __name__ == '__main__':
    main()
