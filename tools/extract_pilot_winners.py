"""
Extract Pilot Winners Search Terms Report (May 10 – yesterday).
Aggregates by (campaign_name, customer_search_term) from FACT_AMAZON_ADS.
Outputs: pilot_winners_search_terms_may10_to_today.csv
"""
import os, csv, warnings
warnings.filterwarnings('ignore')
from google.cloud import bigquery

client = bigquery.Client(project="onyga-482313")

QUERY = """
WITH ad_group_names AS (
  SELECT
    ad_group_id,
    ANY_VALUE(ad_group_name) as ad_group_name
  FROM `onyga-482313.OI.V_SRC_AmazonAds_ad_group_history`
  GROUP BY ad_group_id
)
SELECT
  fa.campaign_name,
  COALESCE(ag.ad_group_name, fa.ad_group_id) AS ad_group_name,
  fa.targeting AS targeting_keyword,
  fa.targeting_type AS targeting_match_type,
  fa.search_term AS customer_search_term,
  SUM(fa.Ads_impressions) AS impressions,
  SUM(fa.Ads_clicks) AS clicks,
  ROUND(SUM(fa.Ads_cost), 2) AS spend,
  ROUND(SUM(fa.Ads_sales), 2) AS sales,
  SUM(fa.Ads_orders) AS orders,
  SUM(fa.Ads_units) AS units,
  -- Derived metrics
  ROUND(SAFE_DIVIDE(SUM(fa.Ads_clicks), SUM(fa.Ads_impressions)) * 100, 2) AS click_through_rate,
  ROUND(SAFE_DIVIDE(SUM(fa.Ads_orders), SUM(fa.Ads_clicks)) * 100, 2) AS conversion_rate,
  ROUND(SAFE_DIVIDE(SUM(fa.Ads_cost), SUM(fa.Ads_clicks)), 2) AS cost_per_click,
  ROUND(SAFE_DIVIDE(SUM(fa.Ads_sales), SUM(fa.Ads_cost)), 2) AS roas
FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
LEFT JOIN ad_group_names ag ON fa.ad_group_id = ag.ad_group_id
WHERE fa.date >= '2026-05-10'
  AND fa.date < CURRENT_DATE()
  AND fa.campaign_name IN (
    'PILOT-WHITE-BROAD-birthday-gifts-for-g',
    'PILOT-MINT-BROAD-journaling-kit-for-g',
    'PILOT-MINT-BROAD-cute-notebooks-for-g'
  )
  AND fa.search_term IS NOT NULL
  AND fa.search_term != ''
GROUP BY
  fa.campaign_name,
  COALESCE(ag.ad_group_name, fa.ad_group_id),
  fa.targeting,
  fa.targeting_type,
  fa.search_term
ORDER BY
  fa.campaign_name ASC,
  orders DESC,
  sales DESC
"""

print("Querying BigQuery for PILOT winners search terms (May 10 – yesterday)...")
rows = list(client.query(QUERY).result())
print(f"  → {len(rows)} rows returned")

# Write CSV
output_path = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "pilot_winners_search_terms_may10_to_today.csv"
)

columns = [
    "campaign_name", "ad_group_name", "targeting_keyword", "targeting_match_type",
    "customer_search_term", "impressions", "clicks", "spend", "sales",
    "orders", "units", "click_through_rate", "conversion_rate",
    "cost_per_click", "roas"
]

with open(output_path, 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=columns)
    writer.writeheader()
    for row in rows:
        writer.writerow({col: row[col] for col in columns})

print(f"✅ Saved to {output_path}")
