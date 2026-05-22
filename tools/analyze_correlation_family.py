import os
import warnings
warnings.filterwarnings('ignore')

from google.cloud import bigquery
from collections import defaultdict
import pandas as pd

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
    MAX(parent_name) as family,
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
    COALESCE(pm.family, 'UNKNOWN') as family,
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
  GROUP BY dp.phase, family, ad.search_term
  HAVING SUM(ad.Ads_clicks) >= 10
)
SELECT * FROM joined_data
"""

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
    
    data.append({
        'phase': r.phase,
        'family': r.family,
        'search_term': r.search_term,
        'spend': s,
        'clicks': c,
        'orders': o,
        'net_roas': net_roas,
        'net_profit': np,
        'cpc': cpc
    })

df = pd.DataFrame(data)

# Because returning the entire markdown in chat is huge, I will build a concise summary string
output = ""

# Look at top 2 defining families (e.g., BOX, FRESH, or overall highest profit)
top_families = df.groupby('family')['net_profit'].sum().sort_values(ascending=False).head(3).index.tolist()

for fam in top_families:
    fam_df = df[df['family'] == fam]
    output += f"====================================\n"
    output += f"📦 FAMILY: {fam}\n"
    output += f"====================================\n\n"
    
    for phase in ['OFF_SEASON', 'PEAK']:
        phase_df = fam_df[fam_df['phase'] == phase]
        if phase_df.empty: continue
        
        corr_cpc_roas = phase_df['cpc'].corr(phase_df['net_roas'])
        corr_cpc_profit = phase_df['cpc'].corr(phase_df['net_profit'])
        
        output += f"--- {phase} (ROAS vs CPC Corr: {corr_cpc_roas:.2f} | Profit vs CPC Corr: {corr_cpc_profit:.2f}) ---\n"
        
        top = phase_df.sort_values('net_profit', ascending=False).head(5)
        for _, r in top.iterrows():
            output += f"  > {r['search_term'][:25].ljust(25)} | NetPrf: ${r['net_profit']:,.0f} | CPC: ${r['cpc']:.2f} | ROAS: {r['net_roas']:.1f}x | Orders: {r['orders']:.0f}\n"
        output += "\n"

with open('.tmp/family_summary.txt', 'w') as f:
    f.write(output)
print("Done.")
