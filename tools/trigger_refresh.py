import os
from google.cloud import bigquery
import time

project_id = "onyga-482313"
client = bigquery.Client(project=project_id)

print("Starting SP_REFRESH_CUBE_TABLES...")
start = time.time()
try:
    client.query("CALL `onyga-482313.OI.SP_REFRESH_CUBE_TABLES`();").result()
    end = time.time()
    print(f"Successfully refreshed cube tables in {(end-start)/60:.2f} minutes!")
except Exception as e:
    print(f"Error refreshing cube tables: {e}")
