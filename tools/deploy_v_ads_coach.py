import os
from google.cloud import bigquery

project_id = "onyga-482313"
client = bigquery.Client(project=project_id)

with open("/Users/ori/Develop/OI/scripts/bigquery/views/V_ADS_COACH_DATA.sql", "r") as f:
    sql_data = f.read()

print("Deploying V_ADS_COACH_DATA...")
client.query(sql_data).result()
print("Successfully deployed V_ADS_COACH_DATA!")

with open("/Users/ori/Develop/OI/scripts/bigquery/views/V_ADS_COACH.sql", "r") as f:
    sql_coach = f.read()

print("Deploying V_ADS_COACH...")
client.query(sql_coach).result()
print("Successfully deployed V_ADS_COACH!")

with open("/Users/ori/Develop/OI/scripts/bigquery/views/V_ADS_COACH_ACTIONS.sql", "r") as f:
    sql_actions = f.read()

print("Deploying V_ADS_COACH_ACTIONS...")
client.query(sql_actions).result()
print("Successfully deployed V_ADS_COACH_ACTIONS!")
