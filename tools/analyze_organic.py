import os
import warnings
warnings.filterwarnings('ignore')

from google.cloud import bigquery
import pandas as pd

client = bigquery.Client(project="onyga-482313")

query = """
SELECT 
  family,
  week_start_date,
  SUM(ad_cost) as total_ad_cost,
  SUM(clicks) as total_clicks,
  SUM(ad_orders) as total_ad_orders,
  SUM(organic_units) as total_organic_units,
  SUM(orders) as total_orders
FROM `onyga-482313.OI.V_UNIFIED_DAILY`
WHERE week_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
  AND family IS NOT NULL
GROUP BY family, week_start_date
HAVING SUM(clicks) > 0
"""

results = list(client.query(query).result())

data = []
for r in results:
    ad_cost = float(r.total_ad_cost or 0)
    clicks = getattr(r, 'total_clicks', getattr(r, 'clicks', 0)) or 0
    ad_orders = float(r.total_ad_orders or 0)
    organic_units = float(r.total_organic_units or 0)
    orders = float(r.total_orders or 0)
    
    if clicks == 0: continue
    
    cpc = ad_cost / clicks
    organic_ratio = organic_units / orders if orders > 0 else 0
    
    bucket = 'High CPC (> $0.70)' if cpc > 0.70 else 'Normal/Low CPC (<= $0.70)'
    
    data.append({
        'family': r.family,
        'week_start_date': r.week_start_date,
        'ad_cost': ad_cost,
        'clicks': clicks,
        'cpc': cpc,
        'organic_units': organic_units,
        'ad_orders': ad_orders,
        'total_orders': orders,
        'organic_ratio': organic_ratio,
        'bucket': bucket
    })

results_df = pd.DataFrame(data)

output = ""

for family in results_df['family'].unique():
    df = results_df[results_df['family'] == family]
    output += f"**Family: {family}**\n"
    
    # Aggregate by bucket
    agg = df.groupby('bucket').agg(
        weeks=('week_start_date', 'count'),
        avg_cpc=('cpc', 'mean'),
        avg_organic_units=('organic_units', 'mean'),
        avg_ad_orders=('ad_orders', 'mean'),
        avg_total_orders=('total_orders', 'mean'),
        avg_organic_ratio=('organic_ratio', 'mean')
    ).reset_index()
    
    if agg.empty: continue
    
    output += "| CPC Strategy | Weeks in Mode | Avg CPC | Avg Weekly Organic Units | Avg Weekly Ad Orders | Organic Ratio |\n"
    output += "| :--- | :--- | :--- | :--- | :--- | :--- |\n"
    for _, row in agg.iterrows():
        output += f"| {row['bucket']} | {row['weeks']} | ${row['avg_cpc']:.2f} | **{row['avg_organic_units']:.1f}** | {row['avg_ad_orders']:.1f} | {row['avg_organic_ratio']*100:.1f}% |\n"
    output += "\n"

corr = results_df['cpc'].corr(results_df['organic_units'])
corr_ratio = results_df['cpc'].corr(results_df['organic_ratio'])
output += "---\n"
output += f"**Global Correlation (CPC to Organic Units Volume):** {corr:.2f}\n"
output += f"**Global Correlation (CPC to Organic % of Total Sales):** {corr_ratio:.2f}\n"

with open('.tmp/organic_analysis.md', 'w') as f:
    f.write(output)

print("Done.")
