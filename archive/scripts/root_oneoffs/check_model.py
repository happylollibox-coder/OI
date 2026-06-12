from google.cloud import bigquery
client = bigquery.Client(project='onyga-482313')
query = "SELECT * FROM `onyga-482313.OI.DE_NEW_PRODUCT_MODEL`"
print(list(client.query(query).result()))
