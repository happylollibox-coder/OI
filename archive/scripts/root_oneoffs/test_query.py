from google.cloud import bigquery
client = bigquery.Client(project='onyga-482313')
query = """
WITH product_history AS (
  SELECT
    product_short_name AS product,
    MIN(date) AS first_seen,
    DATE_DIFF(CURRENT_DATE(), MIN(date), DAY) AS history_days
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  GROUP BY 1
),
available_rates AS (
  SELECT product, COALESCE(SUM(forecast_units) / 30, 0) as daily_rate
  FROM `onyga-482313.OI.FACT_FORECAST_DEMAND`
  WHERE forecast_year = EXTRACT(YEAR FROM CURRENT_DATE()) 
    AND forecast_month = EXTRACT(MONTH FROM CURRENT_DATE())
  GROUP BY product
)
SELECT 
    p.product_type as family,
    p.product_short_name as product,
    COALESCE(r.daily_rate, 0) as daily_rate,
    CASE 
        WHEN ph.product IS NULL THEN 1
        ELSE 0 
    END as is_new_product,
    CASE 
        WHEN ph.product IS NULL THEN 1
        WHEN COALESCE(ph.history_days, 0) < 60 THEN 1
        ELSE 0 
    END as is_draft
FROM `onyga-482313.OI.DIM_PRODUCT` p
LEFT JOIN product_history ph ON p.product_short_name = ph.product
LEFT JOIN available_rates r ON p.product_short_name = r.product
WHERE p.asin IS NOT NULL AND p.asin != 'UNKNOWN'
  AND p.is_active = true
ORDER BY family, product
"""
results = list(client.query(query).result())
for r in results:
    if r['is_new_product']:
        print(dict(r))

