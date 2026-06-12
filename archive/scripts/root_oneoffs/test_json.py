from google.cloud import bigquery
import json
client = bigquery.Client(project='onyga-482313')
query = """
SELECT CASE WHEN 1=1 THEN 1 ELSE 0 END AS my_val
"""
result = list(client.query(query).result())
print(result[0]['my_val'])
print(type(result[0]['my_val']))
print(json.dumps([dict(r) for r in result]))
