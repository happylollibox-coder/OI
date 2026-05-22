import os
import warnings
warnings.filterwarnings('ignore')

from google.cloud import bigquery
import pandas as pd

client = bigquery.Client(project="onyga-482313")

query = """
WITH my_asins AS (
  SELECT DISTINCT LOWER(asin) as asin
  FROM `onyga-482313.OI.DIM_PRODUCT`
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
    fa.campaign_name,
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
filtered_ads_data AS (
  SELECT ad.*
  FROM ads_data ad
  LEFT JOIN my_asins ma ON ad.search_term = ma.asin OR ad.search_term = CONCAT('asin="', ma.asin, '"')
  WHERE ma.asin IS NULL -- Not one of my ASINs
    AND ad.search_term NOT LIKE '%happy%loli%'
    AND ad.search_term NOT LIKE '%happy%lolli%'
    AND ad.search_term NOT LIKE '%lolli%'
    AND ad.search_term NOT LIKE '%happylolli%'
),
top_terms AS (
  SELECT search_term, SUM(Ads_orders * COALESCE(pm.margin_per_unit, 0) - Ads_spend) as net_profit
  FROM filtered_ads_data ad
  LEFT JOIN product_margins pm ON ad.asin = pm.asin
  GROUP BY search_term
  ORDER BY net_profit DESC
  LIMIT 5
),
campaign_breakdown AS (
  SELECT
    ad.search_term,
    ad.campaign_name,
    SUM(ad.Ads_spend) as spend,
    SUM(ad.Ads_clicks) as clicks,
    SUM(ad.Ads_orders) as orders,
    SUM(ad.Ads_orders * COALESCE(pm.margin_per_unit, 0)) as margin_dollars,
    SUM(ad.Ads_orders * COALESCE(pm.margin_per_unit, 0) - ad.Ads_spend) as net_profit
  FROM filtered_ads_data ad
  JOIN top_terms t ON ad.search_term = t.search_term
  LEFT JOIN product_margins pm ON ad.asin = pm.asin
  GROUP BY ad.search_term, ad.campaign_name
  HAVING SUM(ad.Ads_clicks) >= 5
)
SELECT * FROM campaign_breakdown
ORDER BY search_term, net_profit DESC
"""

results = list(client.query(query).result())

output = "### Performance of Top 5 Terms Split by Campaign\n\n"

current_term = None
for r in results:
    s = r.spend or 0.0
    c = r.clicks or 0.0
    o = r.orders or 0.0
    np = r.net_profit or 0.0
    marg = r.margin_dollars or 0.0
    
    cpc = s / c if c > 0 else 0
    net_roas = marg / s if s > 0 else 0
    
    if r.search_term != current_term:
        if current_term is not None:
            output += "\n"
        current_term = r.search_term
        output += f"**Search Term:** `{current_term}`\n"
        output += "| Campaign Name | Orders | Net Profit | CPC | Net ROAS |\n"
        output += "| :--- | :--- | :--- | :--- | :--- |\n"
        
    term_length = 35
    camp = str(r.campaign_name)
    if len(camp) > term_length:
        camp = camp[:term_length] + "..."
        
    output += f"| {camp} | {o:.0f} | **${np:,.0f}** | ${cpc:.2f} | {net_roas:.1f}x |\n"

with open('.tmp/campaign_vs_term.txt', 'w') as f:
    f.write(output)

print("Done")
