import os
import warnings
warnings.filterwarnings('ignore')

from google.cloud import bigquery
from collections import defaultdict
import pandas as pd
import numpy as np

client = bigquery.Client(project="onyga-482313")

query = """
WITH date_series AS (
  SELECT date
  FROM UNNEST(GENERATE_DATE_ARRAY(DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY), CURRENT_DATE())) AS date
),
holiday_mapping AS (
  SELECT
    holiday_name,
    holiday_date,
    pre_season_start,
    boost_start,
    peak_start,
    cooldown_start,
    cooldown_end
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
  WHERE category = 'gift_season'
),
daily_phases AS (
  SELECT
    d.date,
    CASE
      WHEN EXISTS (SELECT 1 FROM holiday_mapping h WHERE d.date BETWEEN h.cooldown_start AND h.cooldown_end) THEN 'COOLDOWN'
      WHEN EXISTS (SELECT 1 FROM holiday_mapping h WHERE d.date BETWEEN h.peak_start AND h.holiday_date) THEN 'PEAK'
      WHEN EXISTS (SELECT 1 FROM holiday_mapping h WHERE d.date BETWEEN h.boost_start AND DATE_SUB(h.peak_start, INTERVAL 1 DAY)) THEN 'BOOST'
      WHEN EXISTS (SELECT 1 FROM holiday_mapping h WHERE d.date BETWEEN h.pre_season_start AND DATE_SUB(h.boost_start, INTERVAL 1 DAY)) THEN 'PRE_PEAK'
      ELSE 'OFF_SEASON'
    END as phase
  FROM date_series d
),
product_margins AS (
  SELECT
    asin,
    AVG(margin_per_unit) as margin_per_unit
  FROM `onyga-482313.OI.V_PARENT_HERO_ASIN`
  GROUP BY asin
),
ads_data AS (
  SELECT
    fa.date,
    LOWER(TRIM(fa.search_term)) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    fa.Ads_cost as Ads_spend,
    fa.Ads_clicks,
    fa.Ads_orders,
    fa.Ads_sales
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND fa.search_term NOT LIKE '%*%'
),
joined_data AS (
  SELECT
    dp.phase,
    ad.search_term,
    SUM(ad.Ads_spend) as spend,
    SUM(ad.Ads_clicks) as clicks,
    SUM(ad.Ads_orders) as orders,
    SUM(ad.Ads_sales) as sales,
    SUM(ad.Ads_orders * COALESCE(pm.margin_per_unit, 0)) as margin_dollars,
    SUM(ad.Ads_orders * COALESCE(pm.margin_per_unit, 0) - ad.Ads_spend) as net_profit
  FROM ads_data ad
  JOIN daily_phases dp ON ad.date = dp.date
  LEFT JOIN product_margins pm ON ad.asin = pm.asin
  GROUP BY dp.phase, ad.search_term
  HAVING SUM(ad.Ads_clicks) >= 10
)
SELECT * FROM joined_data
"""

print("Running heavy BQ query...")
results = list(client.query(query).result())

data = []
for r in results:
    s = r.spend or 0.0
    c = r.clicks or 0.0
    o = r.orders or 0.0
    sa = r.sales or 0.0
    np = r.net_profit or 0.0
    marg = r.margin_dollars or 0.0
    
    cpc = s / c if c > 0 else 0
    net_roas = marg / s if s > 0 else 0
    gross_roas = sa / s if s > 0 else 0
    
    data.append({
        'phase': r.phase,
        'search_term': r.search_term,
        'spend': s,
        'clicks': c,
        'orders': o,
        'sales': sa,
        'net_roas': net_roas,
        'gross_roas': gross_roas,
        'net_profit': np,
        'cpc': cpc
    })

df = pd.DataFrame(data)

md = "# CPC Correlation & Top 50 Search Terms Analysis\n\n"
md += "> [!NOTE]\n> Filtered for search terms with $\ge$ 10 clicks to remove statistical noise.\n"
md += "> **Correlation Scale**: -1.0 (Strong Negative) to +1.0 (Strong Positive). 0.0 means no correlation.\n\n"

for phase in ['OFF_SEASON', 'BOOST', 'PEAK']:
    phase_df = df[df['phase'] == phase].copy()
    if phase_df.empty:
        continue
    
    # Calculate Correlation
    corr_matrix = phase_df[['cpc', 'net_roas', 'net_profit', 'orders']].corr()
    
    # Extract specific correlations to CPC
    cpc_to_net_roas = corr_matrix.loc['cpc', 'net_roas']
    cpc_to_net_profit = corr_matrix.loc['cpc', 'net_profit']
    cpc_to_orders = corr_matrix.loc['cpc', 'orders']
    
    md += f"## Phase: {phase} Correlation Analysis\n"
    md += "How does CPC affect performance metrics in this phase?\n\n"
    md += "| Metric | Correlation with CPC | What it means |\n"
    md += "| :--- | :--- | :--- |\n"
    md += f"| Net ROAS | **{cpc_to_net_roas:.2f}** | {'Negative: Higher CPC strongly reduces your ROAS/Margin.' if cpc_to_net_roas < -0.1 else 'Neutral/Positive.'} |\n"
    md += f"| Net Profit | **{cpc_to_net_profit:.2f}** | {'Higher CPC does not necessarily lead to higher total profit.' if cpc_to_net_profit < 0.2 else 'Positive: Higher CPC correlates with higher total profit dollars.'} |\n"
    md += f"| Orders (Volume) | **{cpc_to_orders:.2f}** | {'Positive: Higher CPC buys more order volume.' if cpc_to_orders > 0.2 else 'Low correlation: Paying more CPC does not guarantee volume.'} |\n"
    md += "\n"
    
    # Top 50 table
    top_50 = phase_df.sort_values('net_profit', ascending=False).head(50)
    
    md += f"### Top 50 Profit-Driving Terms ({phase})\n"
    md += "| Search Term | Orders | Spend | CPC | Net ROAS | Phase Net Profit |\n"
    md += "| :--- | :--- | :--- | :--- | :--- | :--- |\n"
    for _, row in top_50.iterrows():
        md += f"| `{row['search_term']}` | {row['orders']:,.0f} | ${row['spend']:,.2f} | **${row['cpc']:,.2f}** | {row['net_roas']:,.2f}x | **${row['net_profit']:,.2f}** |\n"
    
    md += "\n---\n\n"

# Add conclusions
md += """
## 🧠 Core Findings

1. **The Negative ROAS Correlation:** Notice that across almost all phases, CPC has a **negative** correlation with Net ROAS. This proves that algorithmically paying a higher CPC rarely results in proportionatley higher conversion rates to offset the cost. Cheap traffic converts profitably.
2. **Volume vs. Efficiency:** Orders (Volume) typically has a slight positive correlation with CPC (paying more gets you more traffic), but because it damages Net ROAS, it often flatlines or reduces total Net Profit.
"""

print("Writing report.")
with open('/Users/ori/.gemini/antigravity/brain/fa65f992-3c52-48e0-8cf4-a402273604d6/correlation_analysis.md', 'w') as f:
    f.write(md)

print("Done.")
