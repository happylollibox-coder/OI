from google.cloud import bigquery
client = bigquery.Client(project="onyga-482313")
query = "SELECT * FROM `onyga-482313.OI.V_UNIFIED_DAILY` LIMIT 1"
for r in client.query(query).result():
    print(dict(r))
