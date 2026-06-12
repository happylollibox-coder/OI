from google.cloud import bigquery

client = bigquery.Client(project='onyga-482313')

# We'll just read the SP definition, add a debug statement right before tmp_type4, and run it.
with open('scripts/bigquery/procedures/SP_GENERATE_SHIPMENT_PLAN.sql', 'r') as f:
    sql = f.read()

# Insert the debug statement right before tmp_type4
target = "CREATE TEMP TABLE tmp_type4 AS"
debug_sql = """
  CREATE OR REPLACE TABLE `onyga-482313.OI.DEBUG_BUDGET_REAL` AS 
  SELECT p.product, budget.remaining_budget, p.q4_demand, p.committed_q4, p.forecasted_sep1_pipeline, p.total_shipment_budget 
  FROM tmp_products p JOIN tmp_budget_pool budget ON p.product = budget.product 
  WHERE p.product = 'Fresh in Blue';
"""

patched_sql = sql.replace(target, debug_sql + "\n" + target)

# Update the procedure in BigQuery
job = client.query(patched_sql)
job.result()
print("Procedure patched successfully.")
