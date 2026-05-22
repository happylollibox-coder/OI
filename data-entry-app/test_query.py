from google.cloud import bigquery
import os
from dotenv import load_dotenv

load_dotenv()
client = bigquery.Client()
project = os.environ.get('GCP_PROJECT_ID', 'onyga-482313')
dataset = os.environ.get('BIGQUERY_DATASET', 'OI')

ORDERS_TABLE = f"{project}.{dataset}.DE_PURCHASE_ORDERS"
SHIPMENT_LINES_TABLE = f"{project}.{dataset}.DE_SHIPMENT_LINES"
PRODUCTS_TABLE = f"{project}.{dataset}.DIM_PRODUCT"

query = f"""
WITH shipped AS (
  SELECT purchase_order_id,
         COALESCE(product_id, 0) AS product_id,
         SUM(COALESCE(quantity_shipped, 0)) as total_shipped
  FROM `{SHIPMENT_LINES_TABLE}`
  GROUP BY purchase_order_id, COALESCE(product_id, 0)
)
SELECT po.purchase_order_id, po.product_id, po.product_name, COALESCE(dp.asin, po.product_asin) as product_asin,
       po.quantity as order_quantity,
       COALESCE(sh.total_shipped, 0) as total_shipped,
       (po.quantity - COALESCE(sh.total_shipped, 0)) as remaining_quantity
FROM `{ORDERS_TABLE}` po
LEFT JOIN shipped sh ON po.purchase_order_id = sh.purchase_order_id
                     AND COALESCE(po.product_id, 0) = sh.product_id
LEFT JOIN `{PRODUCTS_TABLE}` dp ON po.product_id = dp.product_id
WHERE po.payment_status != 'CANCELLED'
  AND (po.quantity - COALESCE(sh.total_shipped, 0)) > 0
  AND po.product_asin = 'B0F9X95K5H'
ORDER BY po.order_date DESC
"""
result = client.query(query).result()
for row in result:
    print(dict(row))
