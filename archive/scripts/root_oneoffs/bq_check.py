from google.cloud import bigquery
import json

client = bigquery.Client(project="onyga-482313")

query = """
SELECT parent_name, product_short_name, cost_of_goods, shipping_cost
FROM `onyga-482313.OI.DIM_PRODUCT`
WHERE parent_name = 'Bunny'
LIMIT 5
"""
query_job = client.query(query)
results = [dict(row) for row in query_job]
print(json.dumps(results, indent=2))
