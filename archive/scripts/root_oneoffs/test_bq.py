from google.cloud import bigquery
client = bigquery.Client(project='onyga-482313')
query = """
SELECT *
FROM `onyga-482313.OI.V_ADS_COACH`
WHERE action IS NOT NULL AND action != 'KEEP'
LIMIT 1
"""
try:
    for row in client.query(query).result():
        filtered_row = {k: v for k, v in dict(row).items() if v is not None}
        print({k: filtered_row[k] for k in ('campaign_name', 'search_term', 'ads_spend_8w', 'ads_orders_8w', 'action') if k in filtered_row})
except Exception as e:
    print(f"Error: {e}")
