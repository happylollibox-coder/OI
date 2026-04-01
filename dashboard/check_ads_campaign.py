#!/usr/bin/env python3
"""Check FACT_AMAZON_ADS for campaign BOX-SP/BROAD (Hunter, Gift for Girl) - Feb 22-28."""

from google.cloud import bigquery

PROJECT = "onyga-482313"

# Uses same column names as refresh_data.py (clicks, orders, cost)
# Check all BOX-SP/BROAD campaigns and also search for "Hunter" anywhere
QUERY = """
SELECT
  CAST(DATE_TRUNC(date, WEEK(SUNDAY)) AS STRING) as week_start,
  campaign_id,
  campaign_name,
  SUM(clicks) as total_clicks,
  SUM(orders) as total_orders,
  SUM(cost) as total_cost
FROM `onyga-482313.OI.FACT_AMAZON_ADS`
WHERE campaign_name LIKE '%BOX-SP/BROAD%'
AND date >= '2026-02-22'
AND date <= '2026-02-28'
GROUP BY 1, 2, 3
ORDER BY total_clicks DESC
"""

QUERY2_DISTINCT = """
SELECT DISTINCT campaign_id, campaign_name
FROM `onyga-482313.OI.FACT_AMAZON_ADS`
WHERE campaign_name LIKE '%BOX-SP/BROAD%'
AND date >= '2026-02-01'
ORDER BY campaign_name
"""

def main():
    client = bigquery.Client(project=PROJECT)
    print("=== Distinct BOX-SP/BROAD campaigns in DB (Feb 2026+) ===")
    for r in client.query(QUERY2_DISTINCT).result():
        print(f"  {r.campaign_id}: {r.campaign_name}")
    print()
    print("=== Totals for Feb 22-28 ===")
    try:
        rows = list(client.query(QUERY).result())
        if not rows:
            print("No rows found. Trying broader search (all campaigns with 'BOX' in name)...")
            QUERY2 = """
            SELECT
              CAST(DATE_TRUNC(date, WEEK(SUNDAY)) AS STRING) as week_start,
              campaign_id,
              campaign_name,
              SUM(clicks) as total_clicks,
              SUM(orders) as total_orders
            FROM `onyga-482313.OI.FACT_AMAZON_ADS`
            WHERE campaign_name LIKE '%BOX%'
            AND date >= '2026-02-22' AND date <= '2026-02-28'
            GROUP BY 1, 2, 3
            ORDER BY total_clicks DESC
            LIMIT 20
            """
            rows = list(client.query(QUERY2).result())
        for r in rows:
            print(f"  {r.campaign_name}")
            print(f"    week_start: {r.week_start}, clicks: {r.total_clicks}, orders: {r.total_orders}, cost: ${r.total_cost:.2f}")
            print()
        if rows:
            total_c = sum(r.total_clicks for r in rows)
            total_o = sum(r.total_orders for r in rows)
            print(f"--- All BOX-SP/BROAD campaigns combined: {total_c} clicks, {total_o} orders ---")
    except Exception as e:
        print(f"Error: {e}")
        raise

if __name__ == "__main__":
    main()
