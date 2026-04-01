#!/usr/bin/env python3
"""
Query LolliME Cost Data from DIM_PRODUCT
"""
from google.cloud import bigquery
import json

PROJECT_ID = "onyga-482313"
DATASET = "OI"

def query_lollime_costs():
    """Query LolliME products for cost data"""
    client = bigquery.Client(project=PROJECT_ID)
    
    query = """
    SELECT 
      p.asin,
      p.parent_name,
      p.sku,
      p.cost_of_goods as COGS,
      p.shipping_cost,
      f.estimated_pick_pack_fee_per_unit as fba_cost,
      (p.cost_of_goods + p.shipping_cost + COALESCE(f.estimated_pick_pack_fee_per_unit, f.FBA_COST_estimated_fee_total - f.FBA_COST_estimated_referral_fee_per_unit)) as total_cost,
      p.manufacture_day,
      p.shipment_days,
      (p.manufacture_day + p.shipment_days) as total_lead_time_days,
      p.listing_price_amount as list_price,
      CASE 
        WHEN p.listing_price_amount > 0 AND (p.cost_of_goods + p.shipping_cost + COALESCE(f.estimated_pick_pack_fee_per_unit, f.FBA_COST_estimated_fee_total - f.FBA_COST_estimated_referral_fee_per_unit)) > 0 THEN 
          ROUND(((p.listing_price_amount - (p.cost_of_goods + p.shipping_cost + COALESCE(f.estimated_pick_pack_fee_per_unit, f.FBA_COST_estimated_fee_total - f.FBA_COST_estimated_referral_fee_per_unit))) / p.listing_price_amount) * 100, 2)
        ELSE NULL
      END as margin_percent
    FROM `onyga-482313.OI.DIM_PRODUCT` p
    LEFT JOIN `onyga-482313.OI.DIM_COSTS_HISTORY` f 
      ON p.marketplace = f.marketplace_id AND p.asin = f.asin AND (p.sku = f.sku OR (p.sku IS NULL AND f.sku IS NULL))
      AND f.end_date IS NULL
    WHERE p.parent_name = 'LolliME'
       OR p.asin IN ('B0F9XDSVYB', 'B0F9XFXQRW', 'B0F9X95K5H')
    ORDER BY p.sku;
    """
    
    print("Querying LolliME cost data from DIM_PRODUCT...")
    print("=" * 80)
    
    query_job = client.query(query)
    results = query_job.result()
    
    print("\nLolliME Product Cost Data:")
    print("-" * 80)
    
    rows = []
    for row in results:
        rows.append(dict(row))
        print(f"\nSKU: {row.sku}")
        print(f"  ASIN: {row.asin}")
        print(f"  COGS: ${row.COGS}")
        print(f"  Shipping: ${row.shipping_cost}")
        print(f"  FBA Fee: ${row.fba_cost}")
        print(f"  Total Cost: ${row.total_cost}")
        print(f"  List Price: ${row.list_price}")
        print(f"  Margin: {row.margin_percent}%")
        print(f"  Manufacturing Days: {row.manufacture_day}")
        print(f"  Shipment Days: {row.shipment_days}")
        print(f"  Total Lead Time: {row.total_lead_time_days} days")
    
    print("\n" + "=" * 80)
    print(f"\nTotal LolliME products found: {len(rows)}")
    
    if rows:
        avg_cogs = sum(r['COGS'] for r in rows if r['COGS']) / len(rows)
        avg_total_cost = sum(r['total_cost'] for r in rows if r['total_cost']) / len(rows)
        avg_margin = sum(r['margin_percent'] for r in rows if r['margin_percent']) / len(rows)
        
        print(f"\nAverage COGS: ${avg_cogs:.2f}")
        print(f"Average Total Cost: ${avg_total_cost:.2f}")
        print(f"Average Margin: {avg_margin:.2f}%")
    
    return rows

if __name__ == "__main__":
    try:
        query_lollime_costs()
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
