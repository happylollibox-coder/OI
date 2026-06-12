from google.cloud import bigquery
client = bigquery.Client(project='onyga-482313')

with open('scripts/bigquery/views/V_PRODUCT_FAMILY_MAP.sql', 'r') as f:
    sql = f.read()

client.query(sql).result()

query = """
SELECT family, COUNT(*) as cnt 
FROM `onyga-482313.OI.V_PRODUCT_FAMILY_MAP`
GROUP BY 1
"""
for row in client.query(query).result():
    print(row)
