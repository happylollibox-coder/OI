from google.cloud import bigquery
client = bigquery.Client(project='onyga-482313')

with open('scripts/bigquery/views/V_FORECAST_DEMAND.sql', 'r') as f:
    sql = f.read()

client.query(sql).result()
print("V_FORECAST_DEMAND view successfully updated in BigQuery!")
