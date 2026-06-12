from google.cloud import bigquery
client = bigquery.Client(project='onyga-482313')

with open('scripts/bigquery/views/V_PRODUCT_SEASONALITY_INDEX.sql', 'r') as f:
    sql = f.read()

client.query(sql).result()
print("V_PRODUCT_SEASONALITY_INDEX view successfully updated in BigQuery!")
