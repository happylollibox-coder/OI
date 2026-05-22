import os
import warnings
warnings.filterwarnings('ignore')

from google.cloud import bigquery
from collections import defaultdict

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
    SUM(ad.Ads_orders * COALESCE(pm.margin_per_unit, 0) - ad.Ads_spend) as net_profit
  FROM ads_data ad
  JOIN daily_phases dp ON ad.date = dp.date
  LEFT JOIN product_margins pm ON ad.asin = pm.asin
  GROUP BY dp.phase, ad.search_term
)
SELECT * FROM joined_data
"""

print("Running heavy BQ query...")
results = list(client.query(query).result())

# Manual aggregation
overall_agg = defaultdict(lambda: {'spend': 0.0, 'clicks': 0.0, 'orders': 0.0, 'sales': 0.0, 'net_profit': 0.0})
phase_agg = defaultdict(list)

for r in results:
    phase = r.phase
    st = r.search_term
    s = r.spend or 0.0
    c = r.clicks or 0.0
    o = r.orders or 0.0
    sa = r.sales or 0.0
    np = r.net_profit or 0.0
    
    overall_agg[st]['spend'] += s
    overall_agg[st]['clicks'] += c
    overall_agg[st]['orders'] += o
    overall_agg[st]['sales'] += sa
    overall_agg[st]['net_profit'] += np
    
    phase_agg[phase].append({
        'search_term': st,
        'spend': s,
        'clicks': c,
        'orders': o,
        'sales': sa,
        'net_profit': np
    })

# compute overall
overall_list = []
for st, v in overall_agg.items():
    cpc = v['spend'] / v['clicks'] if v['clicks'] > 0 else 0
    grow_roas = v['sales'] / v['spend'] if v['spend'] > 0 else 0
    overall_list.append({
        'search_term': st, 'spend': v['spend'], 'orders': v['orders'],
        'cpc': cpc, 'gross_roas': grow_roas, 'net_profit': v['net_profit']
    })

overall_list.sort(key=lambda x: x['net_profit'], reverse=True)

md = "# 12-Month Search Term Profitability Analysis\n\n"
md += "> [!NOTE]\n> Analyzes actual Search Terms (what the customer typed in), aggregating performance across all match types and Auto campaigns.\n\n"

md += "## Overall Best Profit Search Terms (All Year)\n"
md += "| Search Term | Orders | Spend | Blended CPC | Gross ROAS | Net Profit |\n"
md += "| :--- | :--- | :--- | :--- | :--- | :--- |\n"
for row in overall_list[:20]:
    md += f"| `{row['search_term']}` | {row['orders']:,.0f} | ${row['spend']:,.2f} | **${row['cpc']:,.2f}** | {row['gross_roas']:,.2f}x | **${row['net_profit']:,.2f}** |\n"
md += "\n"

for phase in ['OFF_SEASON', 'BOOST', 'PEAK', 'COOLDOWN']:
    rows = phase_agg.get(phase, [])
    if not rows:
        continue
    
    for r in rows:
        r['cpc'] = r['spend'] / r['clicks'] if r['clicks'] > 0 else 0
        r['gross_roas'] = r['sales'] / r['spend'] if r['spend'] > 0 else 0
        
    rows.sort(key=lambda x: x['net_profit'], reverse=True)
    
    md += f"## Phase: {phase}\n"
    md += "| Search Term | Orders | Spend | Blended CPC | Gross ROAS | Phase Net Profit |\n"
    md += "| :--- | :--- | :--- | :--- | :--- | :--- |\n"
    for row in rows[:15]:
        md += f"| `{row['search_term']}` | {row['orders']:,.0f} | ${row['spend']:,.2f} | **${row['cpc']:,.2f}** | {row['gross_roas']:,.2f}x | **${row['net_profit']:,.2f}** |\n"
    md += "\n"

with open('/Users/ori/.gemini/antigravity/brain/fa65f992-3c52-48e0-8cf4-a402273604d6/search_term_analysis.md', 'w') as f:
    f.write(md)

print("Done.")
