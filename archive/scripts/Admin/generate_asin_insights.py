#!/usr/bin/env python3
"""
ASIN Tables Insights Generator
Analyzes SQP_ASIN_View_Simple_Week CSV data to generate actionable insights
"""

import pandas as pd
import numpy as np
from datetime import datetime
import json

# Path to the CSV file
CSV_PATH = '../../Data/amazon data/Reports/SQP_ASIN_View_Simple_Week.csv'

def load_data():
    """Load and prepare the data"""
    print("Loading data from CSV...")
    df = pd.read_csv(CSV_PATH)
    
    # Parse dates
    df['Week_Start_date_parsed'] = pd.to_datetime(df['Week_Start_date'], format='%d/%m/%Y', errors='coerce')
    df['Week_End_date_parsed'] = pd.to_datetime(df['Week_End_date'], format='%d/%m/%Y', errors='coerce')
    df['Reporting_Date_parsed'] = pd.to_datetime(df['Reporting_Date'], format='%d/%m/%Y', errors='coerce')
    
    return df

def insight_1_top_performing_queries(df):
    """Top performing search queries by purchases"""
    print("\n" + "="*80)
    print("INSIGHT 1: TOP PERFORMING SEARCH QUERIES")
    print("="*80)
    
    query_perf = df.groupby('Search_Query').agg({
        'Impressions_Total_Count': 'sum',
        'Clicks_Total_Count': 'sum',
        'Cart_Adds_Total_Count': 'sum',
        'Purchases_Total_Count': 'sum',
        'Search_Query_Score': 'mean',
        'Search_Query_Volume': 'max',
        'SKU': 'nunique'
    }).reset_index()
    
    query_perf['CTR_pct'] = (query_perf['Clicks_Total_Count'] / query_perf['Impressions_Total_Count'] * 100).round(2)
    query_perf['Conversion_Rate_pct'] = (query_perf['Purchases_Total_Count'] / query_perf['Clicks_Total_Count'] * 100).round(2)
    query_perf['Cart_Add_Rate_pct'] = (query_perf['Cart_Adds_Total_Count'] / query_perf['Clicks_Total_Count'] * 100).round(2)
    
    top_queries = query_perf[query_perf['Purchases_Total_Count'] >= 10].nlargest(20, 'Purchases_Total_Count')
    
    print(f"\nTotal unique queries: {len(query_perf)}")
    print(f"Queries with 10+ purchases: {len(query_perf[query_perf['Purchases_Total_Count'] >= 10])}")
    print("\nTop 20 Queries by Purchases:")
    print("-" * 80)
    
    for idx, row in top_queries.iterrows():
        print(f"\n{row['Search_Query'][:60]:60s}")
        print(f"  Purchases: {int(row['Purchases_Total_Count']):,} | "
              f"Conversion: {row['Conversion_Rate_pct']:.2f}% | "
              f"CTR: {row['CTR_pct']:.2f}%")
        print(f"  Impressions: {int(row['Impressions_Total_Count']):,} | "
              f"Clicks: {int(row['Clicks_Total_Count']):,} | "
              f"Score: {row['Search_Query_Score']:.1f}")
    
    return top_queries

def insight_2_underperforming_queries(df):
    """High volume queries with low conversion"""
    print("\n" + "="*80)
    print("INSIGHT 2: UNDERPERFORMING QUERIES (Optimization Opportunities)")
    print("="*80)
    
    query_perf = df.groupby('Search_Query').agg({
        'Impressions_Total_Count': 'sum',
        'Clicks_Total_Count': 'sum',
        'Purchases_Total_Count': 'sum'
    }).reset_index()
    
    query_perf['CTR_pct'] = (query_perf['Clicks_Total_Count'] / query_perf['Impressions_Total_Count'] * 100).round(2)
    query_perf['Conversion_Rate_pct'] = (query_perf['Purchases_Total_Count'] / query_perf['Clicks_Total_Count'] * 100).round(2)
    
    underperforming = query_perf[
        (query_perf['Impressions_Total_Count'] >= 1000) &
        ((query_perf['Conversion_Rate_pct'] < 2.0) | (query_perf['CTR_pct'] < 3.0)) &
        (query_perf['Purchases_Total_Count'] < 5)
    ].nlargest(20, 'Impressions_Total_Count')
    
    print(f"\nFound {len(underperforming)} underperforming queries")
    print("\nTop 20 by Impressions (Low Conversion):")
    print("-" * 80)
    
    for idx, row in underperforming.iterrows():
        issue = "LOW_CONVERSION" if row['Conversion_Rate_pct'] < 2.0 else "LOW_CTR"
        print(f"\n{row['Search_Query'][:60]:60s}")
        print(f"  Impressions: {int(row['Impressions_Total_Count']):,} | "
              f"CTR: {row['CTR_pct']:.2f}% | "
              f"Conversion: {row['Conversion_Rate_pct']:.2f}% | "
              f"Issue: {issue}")
        print(f"  Purchases: {int(row['Purchases_Total_Count'])} (Opportunity for improvement)")
    
    return underperforming

def insight_3_shipping_impact(df):
    """Shipping speed impact on conversion"""
    print("\n" + "="*80)
    print("INSIGHT 3: SHIPPING SPEED IMPACT ON CONVERSION")
    print("="*80)
    
    shipping_data = []
    
    for speed in ['Same_Day', '1D', '2D']:
        clicks_col = f'Clicks_{speed}_Shipping_Speed'
        purchases_col = f'Purchases_{speed}_Shipping_Speed'
        
        total_clicks = df[clicks_col].sum()
        total_purchases = df[purchases_col].sum()
        conversion = (total_purchases / total_clicks * 100) if total_clicks > 0 else 0
        
        shipping_data.append({
            'Shipping_Speed': speed.replace('_', ' '),
            'Clicks': int(total_clicks),
            'Purchases': int(total_purchases),
            'Conversion_Rate_pct': round(conversion, 2)
        })
    
    shipping_df = pd.DataFrame(shipping_data)
    
    print("\nConversion Rates by Shipping Speed:")
    print("-" * 80)
    for _, row in shipping_df.iterrows():
        print(f"{row['Shipping_Speed']:15s} | "
              f"Clicks: {row['Clicks']:>8,} | "
              f"Purchases: {row['Purchases']:>6,} | "
              f"Conversion: {row['Conversion_Rate_pct']:>6.2f}%")
    
    best_speed = shipping_df.loc[shipping_df['Conversion_Rate_pct'].idxmax()]
    print(f"\n📊 Best performing: {best_speed['Shipping_Speed']} shipping "
          f"({best_speed['Conversion_Rate_pct']:.2f}% conversion)")
    
    return shipping_df

def insight_4_price_sensitivity(df):
    """Price sensitivity analysis"""
    print("\n" + "="*80)
    print("INSIGHT 4: PRICE SENSITIVITY ANALYSIS")
    print("="*80)
    
    # Filter valid price data
    price_df = df[df['Clicks_Price_ Median'].notna() & (df['Clicks_Price_ Median'] > 0)].copy()
    
    def price_range(price):
        if price < 15:
            return '< $15'
        elif price < 25:
            return '$15-$25'
        elif price < 35:
            return '$25-$35'
        elif price < 50:
            return '$35-$50'
        else:
            return '> $50'
    
    price_df['Price_Range'] = price_df['Clicks_Price_ Median'].apply(price_range)
    
    price_perf = price_df.groupby('Price_Range').agg({
        'Clicks_Total_Count': 'sum',
        'Cart_Adds_Total_Count': 'sum',
        'Purchases_Total_Count': 'sum',
        'Clicks_Price_ Median': 'mean'
    }).reset_index()
    
    price_perf['Conversion_Rate_pct'] = (price_perf['Purchases_Total_Count'] / price_perf['Clicks_Total_Count'] * 100).round(2)
    price_perf['Cart_Add_Rate_pct'] = (price_perf['Cart_Adds_Total_Count'] / price_perf['Clicks_Total_Count'] * 100).round(2)
    price_perf['Avg_Price'] = price_perf['Clicks_Price_ Median'].round(2)
    
    print("\nPerformance by Price Range:")
    print("-" * 80)
    for _, row in price_perf.iterrows():
        print(f"\n{row['Price_Range']:10s} (Avg: ${row['Avg_Price']:.2f})")
        print(f"  Clicks: {int(row['Clicks_Total_Count']):>8,} | "
              f"Purchases: {int(row['Purchases_Total_Count']):>6,}")
        print(f"  Conversion: {row['Conversion_Rate_pct']:>6.2f}% | "
              f"Cart Add Rate: {row['Cart_Add_Rate_pct']:>6.2f}%")
    
    best_price = price_perf.loc[price_perf['Conversion_Rate_pct'].idxmax()]
    print(f"\n📊 Sweet spot: {best_price['Price_Range']} range "
          f"({best_price['Conversion_Rate_pct']:.2f}% conversion)")
    
    return price_perf

def insight_5_query_score_correlation(df):
    """Search query score vs performance"""
    print("\n" + "="*80)
    print("INSIGHT 5: SEARCH QUERY SCORE VS PERFORMANCE")
    print("="*80)
    
    score_df = df[df['Search_Query_Score'].notna()].copy()
    
    def score_category(score):
        if score >= 90:
            return 'Excellent (90+)'
        elif score >= 70:
            return 'Good (70-89)'
        elif score >= 50:
            return 'Fair (50-69)'
        elif score >= 30:
            return 'Poor (30-49)'
        else:
            return 'Very Poor (<30)'
    
    score_df['Score_Category'] = score_df['Search_Query_Score'].apply(score_category)
    
    score_perf = score_df.groupby('Score_Category').agg({
        'Search_Query': 'count',
        'Purchases_Total_Count': 'sum',
        'Clicks_Total_Count': 'sum',
        'Search_Query_Score': 'mean'
    }).reset_index()
    
    score_perf['Conversion_Rate_pct'] = (score_perf['Purchases_Total_Count'] / score_perf['Clicks_Total_Count'] * 100).round(2)
    score_perf['Avg_Score'] = score_perf['Search_Query_Score'].round(1)
    
    print("\nPerformance by Query Score Category:")
    print("-" * 80)
    for _, row in score_perf.iterrows():
        print(f"\n{row['Score_Category']:20s} (Avg Score: {row['Avg_Score']:.1f})")
        print(f"  Queries: {int(row['Search_Query']):>6,} | "
              f"Purchases: {int(row['Purchases_Total_Count']):>6,}")
        print(f"  Conversion: {row['Conversion_Rate_pct']:>6.2f}%")
    
    return score_perf

def insight_6_weekly_trends(df):
    """Weekly performance trends"""
    print("\n" + "="*80)
    print("INSIGHT 6: WEEKLY PERFORMANCE TRENDS")
    print("="*80)
    
    weekly = df.groupby(['Year', 'Week', 'Week_Start_date_parsed']).agg({
        'SKU': 'nunique',
        'Search_Query': 'nunique',
        'Impressions_Total_Count': 'sum',
        'Clicks_Total_Count': 'sum',
        'Purchases_Total_Count': 'sum'
    }).reset_index()
    
    weekly['CTR_pct'] = (weekly['Clicks_Total_Count'] / weekly['Impressions_Total_Count'] * 100).round(2)
    weekly['Conversion_Rate_pct'] = (weekly['Purchases_Total_Count'] / weekly['Clicks_Total_Count'] * 100).round(2)
    weekly = weekly.sort_values('Week_Start_date_parsed', ascending=False).head(12)
    
    print("\nLast 12 Weeks Performance:")
    print("-" * 80)
    for _, row in weekly.iterrows():
        date_str = row['Week_Start_date_parsed'].strftime('%Y-%m-%d') if pd.notna(row['Week_Start_date_parsed']) else 'N/A'
        print(f"\nWeek {row['Week']} ({date_str})")
        print(f"  Active SKUs: {int(row['SKU']):>3} | "
              f"Queries: {int(row['Search_Query']):>4}")
        print(f"  Purchases: {int(row['Purchases_Total_Count']):>6,} | "
              f"Conversion: {row['Conversion_Rate_pct']:>6.2f}% | "
              f"CTR: {row['CTR_pct']:>5.2f}%")
    
    return weekly

def insight_7_cart_abandonment(df):
    """Cart abandonment analysis"""
    print("\n" + "="*80)
    print("INSIGHT 7: CART ABANDONMENT ANALYSIS")
    print("="*80)
    
    total_cart_adds = df['Cart_Adds_Total_Count'].sum()
    total_purchases = df['Purchases_Total_Count'].sum()
    abandoned = total_cart_adds - total_purchases
    
    cart_to_purchase_rate = (total_purchases / total_cart_adds * 100) if total_cart_adds > 0 else 0
    abandonment_rate = (abandoned / total_cart_adds * 100) if total_cart_adds > 0 else 0
    
    avg_cart_price = df[df['Cart_Adds_Price_ Median'].notna()]['Cart_Adds_Price_ Median'].mean()
    avg_purchase_price = df[df['Purchases_Price_ Median'].notna()]['Purchases_Price_ Median'].mean()
    
    print(f"\nCart Performance Summary:")
    print("-" * 80)
    print(f"Total Cart Adds:      {total_cart_adds:>12,}")
    print(f"Total Purchases:      {total_purchases:>12,}")
    print(f"Abandoned Carts:      {abandoned:>12,}")
    print(f"\nCart to Purchase Rate: {cart_to_purchase_rate:>10.2f}%")
    print(f"Abandonment Rate:      {abandonment_rate:>10.2f}%")
    print(f"\nAverage Cart Price:    ${avg_cart_price:>10.2f}")
    print(f"Average Purchase Price: ${avg_purchase_price:>10.2f}")
    
    if abandonment_rate > 70:
        print(f"\n⚠️  HIGH ABANDONMENT RATE: {abandonment_rate:.1f}% of carts are abandoned")
        print("   Consider: Retargeting campaigns, price optimization, checkout flow review")
    
    return {
        'total_cart_adds': int(total_cart_adds),
        'total_purchases': int(total_purchases),
        'abandoned': int(abandoned),
        'abandonment_rate_pct': round(abandonment_rate, 2)
    }

def insight_8_data_summary(df):
    """Overall data summary"""
    print("\n" + "="*80)
    print("INSIGHT 8: DATA SUMMARY")
    print("="*80)
    
    total_rows = len(df)
    unique_skus = df['SKU'].nunique()
    unique_queries = df['Search_Query'].nunique()
    date_range_start = df['Week_Start_date_parsed'].min()
    date_range_end = df['Week_End_date_parsed'].max()
    
    total_impressions = df['Impressions_Total_Count'].sum()
    total_clicks = df['Clicks_Total_Count'].sum()
    total_purchases = df['Purchases_Total_Count'].sum()
    
    overall_ctr = (total_clicks / total_impressions * 100) if total_impressions > 0 else 0
    overall_conversion = (total_purchases / total_clicks * 100) if total_clicks > 0 else 0
    
    print(f"\nDataset Overview:")
    print("-" * 80)
    print(f"Total Rows:           {total_rows:>12,}")
    print(f"Unique SKUs:          {unique_skus:>12,}")
    print(f"Unique Search Queries: {unique_queries:>12,}")
    print(f"Date Range:           {date_range_start.date()} to {date_range_end.date()}")
    
    print(f"\nPerformance Metrics:")
    print("-" * 80)
    print(f"Total Impressions:    {total_impressions:>12,}")
    print(f"Total Clicks:         {total_clicks:>12,}")
    print(f"Total Purchases:      {total_purchases:>12,}")
    print(f"\nOverall CTR:          {overall_ctr:>12.2f}%")
    print(f"Overall Conversion:   {overall_conversion:>12.2f}%")
    
    return {
        'total_rows': total_rows,
        'unique_skus': unique_skus,
        'unique_queries': unique_queries,
        'total_purchases': int(total_purchases)
    }

def main():
    """Main execution"""
    print("="*80)
    print("ASIN DATA INSIGHTS ANALYSIS")
    print("="*80)
    
    df = load_data()
    print(f"✓ Loaded {len(df):,} rows")
    
    # Generate all insights
    summary = insight_8_data_summary(df)
    top_queries = insight_1_top_performing_queries(df)
    underperforming = insight_2_underperforming_queries(df)
    shipping = insight_3_shipping_impact(df)
    price = insight_4_price_sensitivity(df)
    score = insight_5_query_score_correlation(df)
    weekly = insight_6_weekly_trends(df)
    cart = insight_7_cart_abandonment(df)
    
    print("\n" + "="*80)
    print("ANALYSIS COMPLETE")
    print("="*80)
    print("\n💡 Key Takeaways:")
    print(f"   • {summary['unique_queries']:,} unique search queries analyzed")
    print(f"   • {summary['total_purchases']:,} total purchases tracked")
    print(f"   • Best shipping speed: {shipping.loc[shipping['Conversion_Rate_pct'].idxmax(), 'Shipping_Speed']}")
    print(f"   • Cart abandonment rate: {cart['abandonment_rate_pct']:.1f}%")
    print(f"   • Top query conversion: {top_queries.iloc[0]['Conversion_Rate_pct']:.2f}%")
    print("\n" + "="*80)

if __name__ == '__main__':
    main()
