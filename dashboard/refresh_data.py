#!/usr/bin/env python3
"""Refresh dashboard data from BigQuery and local CSV sources."""

import argparse
import csv
import json
import sys
from datetime import date, datetime
from pathlib import Path

from google.cloud import bigquery

PROJECT = "onyga-482313"
DATASET = "OI"
DATA_DIR = Path(__file__).parent / "data"  # negative_keywords, _meta (dashboard uses these)
ARCHIVE_DIR = Path(__file__).parent.parent / "archive" / "dashboard-data"  # Cube-backed JSON (archived)
CSV_PATH = (
    Path(__file__).parent.parent
    / "docs"
    / "LOLLIBOX_negative_keywords_by_campaign.csv"
)


def _json_serial(obj):
    if isinstance(obj, (date, datetime)):
        return obj.isoformat()
    raise TypeError(f"Type {type(obj)} not serializable")


def run_query_to_json(client: bigquery.Client, sql: str, output_path: Path) -> int:
    """Execute *sql*, write result rows as JSON to *output_path*, return row count."""
    rows = list(client.query(sql).result())
    data = [dict(row) for row in rows]
    with open(output_path, "w") as f:
        json.dump(data, f, default=_json_serial, indent=2)
    print(f"  ✓ {output_path.name}: {len(data)} rows")
    return len(data)


def parse_csv_to_json(csv_path: Path, output_path: Path) -> int:
    """Read a CSV file and write its contents as JSON."""
    with open(csv_path, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        data = list(reader)
    with open(output_path, "w") as f:
        json.dump(data, f, indent=2)
    print(f"  ✓ {output_path.name}: {len(data)} rows (from CSV)")
    return len(data)


# ---------------------------------------------------------------------------
# SQL queries keyed by output filename
# ---------------------------------------------------------------------------

QUERIES: dict[str, str] = {}

QUERIES["summary.json"] = """\
WITH family_map AS (
  SELECT asin,
    CASE
      WHEN product_short_name LIKE '%Lollibox%' OR product_short_name LIKE '%Lolli Box%' THEN 'Lollibox'
      WHEN product_short_name LIKE '%LolliME%' OR product_short_name LIKE '%Lolli ME%' THEN 'LolliME'
      WHEN product_short_name LIKE '%Fresh%' THEN 'Fresh'
      WHEN product_short_name LIKE '%Truth%' OR product_short_name LIKE '%Bottle%' THEN 'Bottle'
      ELSE product_short_name
    END as family
  FROM `onyga-482313.OI.DIM_PRODUCT`
  WHERE asin IS NOT NULL AND asin != 'UNKNOWN'
),
latest_costs AS (
  SELECT asin, TOTAL_COST_PER_UNIT, cost_of_goods, shipping_cost, FBA_COST_estimated_fee_total
  FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  WHERE end_date IS NULL
    OR end_date = (SELECT MAX(end_date) FROM `onyga-482313.OI.DIM_COSTS_HISTORY` c2 WHERE c2.asin = `onyga-482313.OI.DIM_COSTS_HISTORY`.asin)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY asin ORDER BY start_date DESC) = 1
),
date_range AS (
  SELECT
    MAX(date) as latest_biz_date,
    DATE_SUB(MAX(date), INTERVAL 6 DAY) as biz_start,
    DATE_SUB(MAX(date), INTERVAL 13 DAY) as prev_start,
    DATE_SUB(MAX(date), INTERVAL 7 DAY) as prev_end
  FROM `onyga-482313.OI.V_SRC_sales_and_traffic_business_sku_report_daily`
),
biz AS (
  SELECT fm.family, b.date,
    SUM(b.SALES_ORDERS) as orders,
    SUM(b.SALES_QUANTITY) as units,
    SUM(b.SALES_AMOUNT) as sales,
    SUM(b.asin_sessions) as sessions,
    SUM(b.SALES_QUANTITY * COALESCE(lc.TOTAL_COST_PER_UNIT, 0)) as cogs
  FROM `onyga-482313.OI.V_SRC_sales_and_traffic_business_sku_report_daily` b
  JOIN family_map fm ON b.child_asin = fm.asin
  LEFT JOIN latest_costs lc ON b.child_asin = lc.asin
  CROSS JOIN date_range dr
  WHERE b.date >= dr.prev_start
  GROUP BY 1, 2
),
ads AS (
  SELECT fm.family, a.date,
    SUM(a.cost) as ad_cost,
    SUM(a.clicks) as clicks,
    SUM(a.impressions) as impressions,
    SUM(a.orders) as ad_orders
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN family_map fm ON a.most_advertised_asin_impressions = fm.asin
  CROSS JOIN date_range dr
  WHERE a.date >= dr.prev_start AND a.date <= dr.latest_biz_date
  GROUP BY 1, 2
),
combined AS (
  SELECT
    COALESCE(b.family, a.family) as product_type,
    COALESCE(b.date, a.date) as date,
    COALESCE(b.sales, 0) as sales,
    COALESCE(b.orders, 0) as total_orders,
    COALESCE(b.units, 0) as units,
    COALESCE(b.sessions, 0) as sessions,
    COALESCE(b.cogs, 0) as cogs,
    COALESCE(a.ad_cost, 0) as ad_cost,
    COALESCE(a.clicks, 0) as clicks,
    COALESCE(a.ad_orders, 0) as ad_orders,
    GREATEST(COALESCE(b.orders, 0) - COALESCE(a.ad_orders, 0), 0) as organic_orders
  FROM biz b
  FULL OUTER JOIN ads a ON b.family = a.family AND b.date = a.date
),
this_week AS (
  SELECT product_type,
    SUM(sales) as sales_7d, SUM(ad_cost) as ad_cost_7d,
    SUM(cogs) as cogs_7d,
    SUM(total_orders) as orders_7d, SUM(organic_orders) as organic_orders_7d,
    SUM(clicks) as clicks_7d, SUM(ad_orders) as ad_orders_7d,
    SUM(sessions) as sessions_7d,
    MIN(date) as period_start, MAX(date) as period_end
  FROM combined, date_range dr
  WHERE date >= dr.biz_start
  GROUP BY 1
),
last_week AS (
  SELECT product_type,
    SUM(sales) as sales_prev, SUM(ad_cost) as ad_cost_prev,
    SUM(cogs) as cogs_prev,
    SUM(total_orders) as orders_prev,
    SUM(organic_orders) as organic_orders_prev
  FROM combined, date_range dr
  WHERE date >= dr.prev_start AND date < dr.biz_start
  GROUP BY 1
)
SELECT
  t.product_type,
  ROUND(t.sales_7d, 2) as sales_7d,
  ROUND(t.ad_cost_7d, 2) as ad_cost_7d,
  ROUND(t.cogs_7d, 2) as cogs_7d,
  ROUND(t.sales_7d - t.ad_cost_7d - t.cogs_7d, 2) as net_profit_7d,
  t.orders_7d,
  t.organic_orders_7d,
  t.ad_orders_7d,
  t.clicks_7d,
  t.sessions_7d,
  ROUND(SAFE_DIVIDE(t.sales_7d - t.cogs_7d, NULLIF(t.ad_cost_7d, 0)), 2) as net_roas,
  ROUND(SAFE_DIVIDE(t.organic_orders_7d * 100.0, NULLIF(t.orders_7d, 0)), 1) as organic_pct,
  ROUND(l.sales_prev, 2) as sales_prev_7d,
  ROUND(l.ad_cost_prev, 2) as ad_cost_prev_7d,
  ROUND(l.cogs_prev, 2) as cogs_prev_7d,
  ROUND(l.sales_prev - l.ad_cost_prev - l.cogs_prev, 2) as net_profit_prev_7d,
  l.orders_prev as orders_prev_7d,
  l.organic_orders_prev as organic_orders_prev_7d,
  ROUND(SAFE_DIVIDE(l.sales_prev - l.cogs_prev, NULLIF(l.ad_cost_prev, 0)), 2) as net_roas_prev,
  ROUND(SAFE_DIVIDE(l.organic_orders_prev * 100.0, NULLIF(l.orders_prev, 0)), 1) as organic_pct_prev,
  ROUND(SAFE_DIVIDE((t.sales_7d - l.sales_prev) * 100.0, NULLIF(l.sales_prev, 0)), 1) as sales_change_pct,
  ROUND(SAFE_DIVIDE((t.ad_cost_7d - l.ad_cost_prev) * 100.0, NULLIF(l.ad_cost_prev, 0)), 1) as cost_change_pct,
  CAST(t.period_start AS STRING) as period_start,
  CAST(t.period_end AS STRING) as period_end
FROM this_week t
LEFT JOIN last_week l USING (product_type)
ORDER BY t.sales_7d DESC
"""

QUERIES["actions.json"] = """\
SELECT
  action, ads_signal, reason,
  search_term, experiment_id,
  product_short_name, hero_asin, is_hero_match,
  ROUND(ads_spend, 2) as spend,
  ads_orders as orders,
  ads_clicks as clicks,
  ROUND(SAFE_DIVIDE(ads_spend, NULLIF(ads_clicks, 0)), 2) as cpc,
  ROUND(ads_cvr_pct, 2) as conv_rate,
  ROUND(ads_net_roas, 2) as net_roas,
  ROUND(margin_per_unit, 2) as margin_per_unit,
  ROUND(market_weekly_orders, 0) as market_volume,
  ROUND(your_orders_share_pct, 1) as impression_share,
  priority_score,
  strategy_id
FROM `onyga-482313.OI.V_EXPERIMENT_TERM_RECOMMENDATIONS`
WHERE action NOT IN ('KEEP', 'MONITOR')
ORDER BY
  CASE action
    WHEN 'STOP' THEN 1
    WHEN 'REDUCE_BID' THEN 2
    WHEN 'PROMOTE_TO_EXACT' THEN 3
    WHEN 'START' THEN 4
    WHEN 'BOOST' THEN 5
    ELSE 6
  END,
  ads_spend DESC
"""

QUERIES["upcoming.json"] = """\
SELECT
  holiday_date,
  holiday_name,
  category,
  ramp_up_days,
  pre_season_start,
  DATE_DIFF(holiday_date, CURRENT_DATE(), DAY) as days_until_holiday,
  DATE_DIFF(pre_season_start, CURRENT_DATE(), DAY) as days_until_pre_season,
  CASE
    WHEN CURRENT_DATE() BETWEEN pre_season_start AND holiday_date THEN 'ACTIVE'
    WHEN CURRENT_DATE() < pre_season_start THEN 'UPCOMING'
    ELSE 'PASSED'
  END as status
FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
WHERE holiday_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
  AND holiday_date <= DATE_ADD(CURRENT_DATE(), INTERVAL 120 DAY)
ORDER BY holiday_date
"""

QUERIES["peak.json"] = """\
WITH next_peak AS (
  SELECT *,
    DATE_SUB(pre_season_start, INTERVAL 120 DAY) as readiness_start,
    DATE_SUB(pre_season_start, INTERVAL 28 DAY) as pre_peak_start,
    DATE_SUB(pre_season_start, INTERVAL 14 DAY) as boost_start,
    pre_season_start as peak_start,
    DATE_SUB(holiday_date, INTERVAL 2 DAY) as peak_end,
    CASE
      WHEN CURRENT_DATE() < DATE_SUB(pre_season_start, INTERVAL 28 DAY) THEN 'READINESS'
      WHEN CURRENT_DATE() < DATE_SUB(pre_season_start, INTERVAL 14 DAY) THEN 'PRE_PEAK'
      WHEN CURRENT_DATE() < pre_season_start THEN 'PRE_PEAK_BOOST'
      WHEN CURRENT_DATE() <= DATE_SUB(holiday_date, INTERVAL 2 DAY) THEN 'PEAK'
      ELSE 'POST_PEAK'
    END as current_stage
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
  WHERE holiday_date > CURRENT_DATE()
    AND category = 'gift_season'
  ORDER BY holiday_date
  LIMIT 1
)
SELECT
  np.holiday_name,
  np.holiday_date,
  np.pre_season_start,
  np.readiness_start,
  np.pre_peak_start,
  np.boost_start,
  np.peak_start,
  np.peak_end,
  np.current_stage,
  np.category,
  DATE_DIFF(np.peak_start, CURRENT_DATE(), DAY) as days_until_peak_start,
  DATE_DIFF(np.peak_end, CURRENT_DATE(), DAY) as days_until_peak_end
FROM next_peak np
"""

QUERIES["products.json"] = """\
WITH latest_costs AS (
  SELECT asin, cost_of_goods, shipping_cost, FBA_COST_estimated_fee_total, TOTAL_COST_PER_UNIT
  FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  WHERE end_date IS NULL
    OR end_date = (SELECT MAX(end_date) FROM `onyga-482313.OI.DIM_COSTS_HISTORY` c2 WHERE c2.asin = `onyga-482313.OI.DIM_COSTS_HISTORY`.asin)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY asin ORDER BY start_date DESC) = 1
)
SELECT
  p.asin, p.product_name, p.product_short_name, p.product_type,
  ROUND(p.listing_price_amount, 2) as price,
  ROUND(c.cost_of_goods, 2) as cogs,
  ROUND(c.shipping_cost, 2) as shipping,
  ROUND(c.FBA_COST_estimated_fee_total, 2) as fba_cost,
  ROUND(c.TOTAL_COST_PER_UNIT, 2) as total_cost_per_unit,
  p.color, p.parent_asin
FROM `onyga-482313.OI.DIM_PRODUCT` p
LEFT JOIN latest_costs c ON p.asin = c.asin
WHERE p.asin IS NOT NULL AND p.asin != 'UNKNOWN'
ORDER BY p.product_type, p.asin
"""

QUERIES["hero_asins.json"] = """\
SELECT
  h.*,
  p.product_type
FROM `onyga-482313.OI.V_PARENT_HERO_ASIN` h
LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON h.asin = p.asin
ORDER BY h.parent_name, h.hero_rank
LIMIT 500
"""

QUERIES["keyword_product_map.json"] = """\
SELECT
  r.search_term,
  r.experiment_id,
  r.product_short_name,
  r.hero_asin,
  r.is_hero_match,
  r.action,
  r.reason,
  ROUND(r.ads_spend, 2) as spend_60d,
  r.ads_orders as orders_60d,
  r.ads_clicks as clicks_60d,
  r.ads_impressions as impressions_60d,
  ROUND(SAFE_DIVIDE(r.ads_spend, NULLIF(r.ads_clicks, 0)), 2) as cpc_60d,
  ROUND(r.ads_cvr_pct, 2) as conv_rate_60d,
  ROUND(r.ads_net_roas, 2) as net_roas_60d,
  ROUND(r.market_weekly_orders, 0) as market_volume,
  ROUND(r.your_orders_share_pct, 1) as impression_share
FROM `onyga-482313.OI.V_EXPERIMENT_TERM_RECOMMENDATIONS` r
ORDER BY r.ads_spend DESC
LIMIT 2000
"""

QUERIES["weekly_trends.json"] = """\
WITH family_map AS (
  SELECT asin,
    CASE
      WHEN product_short_name LIKE '%Lollibox%' THEN 'Lollibox'
      WHEN product_short_name LIKE '%LolliME%' THEN 'LolliME'
      WHEN product_short_name LIKE '%Fresh%' THEN 'Fresh'
      WHEN product_short_name LIKE '%Truth%' OR product_short_name LIKE '%Bottle%' THEN 'Bottle'
      ELSE product_short_name
    END as family
  FROM `onyga-482313.OI.DIM_PRODUCT` WHERE asin IS NOT NULL AND asin != 'UNKNOWN'
),
latest_costs AS (
  SELECT asin, TOTAL_COST_PER_UNIT
  FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  WHERE end_date IS NULL
    OR end_date = (SELECT MAX(end_date) FROM `onyga-482313.OI.DIM_COSTS_HISTORY` c2 WHERE c2.asin = `onyga-482313.OI.DIM_COSTS_HISTORY`.asin)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY asin ORDER BY start_date DESC) = 1
),
biz AS (
  SELECT fm.family as product_type,
    dt.week_start_date as week_start,
    SUM(b.SALES_AMOUNT) as sales,
    SUM(b.SALES_ORDERS) as orders,
    SUM(b.asin_sessions) as sessions,
    SUM(b.SALES_QUANTITY * COALESCE(lc.TOTAL_COST_PER_UNIT, 0)) as cogs
  FROM `onyga-482313.OI.V_SRC_sales_and_traffic_business_sku_report_daily` b
  JOIN family_map fm ON b.child_asin = fm.asin
  JOIN `onyga-482313.OI.DIM_TIME` dt ON b.date = dt.full_date
  LEFT JOIN latest_costs lc ON b.child_asin = lc.asin
  WHERE b.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 84 DAY)
  GROUP BY 1, 2
),
ads AS (
  SELECT fm.family as product_type,
    dt.week_start_date as week_start,
    SUM(a.cost) as ad_cost,
    SUM(a.clicks) as clicks,
    SUM(a.orders) as ad_orders
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN family_map fm ON a.most_advertised_asin_impressions = fm.asin
  JOIN `onyga-482313.OI.DIM_TIME` dt ON a.date = dt.full_date
  WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 84 DAY)
  GROUP BY 1, 2
)
SELECT
  COALESCE(b.product_type, a.product_type) as product_type,
  COALESCE(b.week_start, a.week_start) as week_start,
  ROUND(COALESCE(b.sales, 0), 2) as sales,
  ROUND(COALESCE(a.ad_cost, 0), 2) as ad_cost,
  ROUND(COALESCE(b.cogs, 0), 2) as cogs,
  ROUND(COALESCE(b.sales, 0) - COALESCE(a.ad_cost, 0) - COALESCE(b.cogs, 0), 2) as net_profit,
  COALESCE(b.orders, 0) as orders,
  COALESCE(a.clicks, 0) as clicks,
  COALESCE(b.sessions, 0) as sessions,
  ROUND(SAFE_DIVIDE(COALESCE(b.sales, 0) - COALESCE(b.cogs, 0), NULLIF(COALESCE(a.ad_cost, 0), 0)), 2) as net_roas,
  ROUND(SAFE_DIVIDE(GREATEST(COALESCE(b.orders, 0) - COALESCE(a.ad_orders, 0), 0) * 100.0, NULLIF(COALESCE(b.orders, 0), 0)), 1) as organic_pct
FROM biz b
FULL OUTER JOIN ads a ON b.product_type = a.product_type AND b.week_start = a.week_start
ORDER BY 1, 2
"""

QUERIES["monthly_trends.json"] = """\
WITH family_map AS (
  SELECT asin,
    CASE
      WHEN product_short_name LIKE '%Lollibox%' THEN 'Lollibox'
      WHEN product_short_name LIKE '%LolliME%' THEN 'LolliME'
      WHEN product_short_name LIKE '%Fresh%' THEN 'Fresh'
      WHEN product_short_name LIKE '%Truth%' OR product_short_name LIKE '%Bottle%' THEN 'Bottle'
      ELSE product_short_name
    END as family
  FROM `onyga-482313.OI.DIM_PRODUCT` WHERE asin IS NOT NULL AND asin != 'UNKNOWN'
),
latest_costs AS (
  SELECT asin, TOTAL_COST_PER_UNIT
  FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  WHERE end_date IS NULL
    OR end_date = (SELECT MAX(end_date) FROM `onyga-482313.OI.DIM_COSTS_HISTORY` c2 WHERE c2.asin = `onyga-482313.OI.DIM_COSTS_HISTORY`.asin)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY asin ORDER BY start_date DESC) = 1
),
biz AS (
  SELECT fm.family as product_type,
    DATE_TRUNC(b.date, MONTH) as month_start,
    SUM(b.SALES_AMOUNT) as sales,
    SUM(b.SALES_ORDERS) as orders,
    SUM(b.asin_sessions) as sessions,
    SUM(b.SALES_QUANTITY * COALESCE(lc.TOTAL_COST_PER_UNIT, 0)) as cogs
  FROM `onyga-482313.OI.V_SRC_sales_and_traffic_business_sku_report_daily` b
  JOIN family_map fm ON b.child_asin = fm.asin
  LEFT JOIN latest_costs lc ON b.child_asin = lc.asin
  WHERE b.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 1095 DAY)
  GROUP BY 1, 2
),
ads AS (
  SELECT fm.family as product_type,
    DATE_TRUNC(a.date, MONTH) as month_start,
    SUM(a.cost) as ad_cost,
    SUM(a.clicks) as clicks,
    SUM(a.orders) as ad_orders
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN family_map fm ON a.most_advertised_asin_impressions = fm.asin
  WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 1095 DAY)
  GROUP BY 1, 2
)
SELECT
  COALESCE(b.product_type, a.product_type) as product_type,
  COALESCE(b.month_start, a.month_start) as month_start,
  ROUND(COALESCE(b.sales, 0), 2) as sales,
  ROUND(COALESCE(a.ad_cost, 0), 2) as ad_cost,
  ROUND(COALESCE(b.cogs, 0), 2) as cogs,
  ROUND(COALESCE(b.sales, 0) - COALESCE(a.ad_cost, 0) - COALESCE(b.cogs, 0), 2) as net_profit,
  COALESCE(b.orders, 0) as orders,
  COALESCE(a.clicks, 0) as clicks,
  COALESCE(b.sessions, 0) as sessions,
  ROUND(SAFE_DIVIDE(COALESCE(b.sales, 0) - COALESCE(b.cogs, 0), NULLIF(COALESCE(a.ad_cost, 0), 0)), 2) as net_roas,
  ROUND(SAFE_DIVIDE(GREATEST(COALESCE(b.orders, 0) - COALESCE(a.ad_orders, 0), 0) * 100.0, NULLIF(COALESCE(b.orders, 0), 0)), 1) as organic_pct
FROM biz b
FULL OUTER JOIN ads a ON b.product_type = a.product_type AND b.month_start = a.month_start
ORDER BY 1, 2
"""

QUERIES["weekly_trends_by_asin.json"] = """\
WITH family_map AS (
  SELECT asin,
    CASE
      WHEN product_short_name LIKE '%Lollibox%' THEN 'Lollibox'
      WHEN product_short_name LIKE '%LolliME%' THEN 'LolliME'
      WHEN product_short_name LIKE '%Fresh%' THEN 'Fresh'
      WHEN product_short_name LIKE '%Truth%' OR product_short_name LIKE '%Bottle%' THEN 'Bottle'
      ELSE product_short_name
    END as family,
    product_short_name
  FROM `onyga-482313.OI.DIM_PRODUCT` WHERE asin IS NOT NULL AND asin != 'UNKNOWN'
),
latest_costs AS (
  SELECT asin, TOTAL_COST_PER_UNIT
  FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  WHERE end_date IS NULL
    OR end_date = (SELECT MAX(end_date) FROM `onyga-482313.OI.DIM_COSTS_HISTORY` c2 WHERE c2.asin = `onyga-482313.OI.DIM_COSTS_HISTORY`.asin)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY asin ORDER BY start_date DESC) = 1
),
biz AS (
  SELECT fm.family as product_type,
    b.child_asin as asin,
    fm.product_short_name,
    dt.week_start_date as week_start,
    SUM(b.SALES_AMOUNT) as sales,
    SUM(b.SALES_ORDERS) as orders,
    SUM(b.asin_sessions) as sessions,
    SUM(b.SALES_QUANTITY * COALESCE(lc.TOTAL_COST_PER_UNIT, 0)) as cogs
  FROM `onyga-482313.OI.V_SRC_sales_and_traffic_business_sku_report_daily` b
  JOIN family_map fm ON b.child_asin = fm.asin
  JOIN `onyga-482313.OI.DIM_TIME` dt ON b.date = dt.full_date
  LEFT JOIN latest_costs lc ON b.child_asin = lc.asin
  WHERE b.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 84 DAY)
  GROUP BY 1, 2, 3, 4
),
ads AS (
  SELECT fm.family as product_type,
    a.most_advertised_asin_impressions as asin,
    fm.product_short_name,
    dt.week_start_date as week_start,
    SUM(a.cost) as ad_cost,
    SUM(a.clicks) as clicks,
    SUM(a.orders) as ad_orders
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN family_map fm ON a.most_advertised_asin_impressions = fm.asin
  JOIN `onyga-482313.OI.DIM_TIME` dt ON a.date = dt.full_date
  WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 84 DAY)
  GROUP BY 1, 2, 3, 4
)
SELECT
  COALESCE(b.product_type, a.product_type) as product_type,
  COALESCE(b.asin, a.asin) as asin,
  COALESCE(b.product_short_name, a.product_short_name) as product_short_name,
  COALESCE(b.week_start, a.week_start) as week_start,
  ROUND(COALESCE(b.sales, 0), 2) as sales,
  ROUND(COALESCE(a.ad_cost, 0), 2) as ad_cost,
  ROUND(COALESCE(b.cogs, 0), 2) as cogs,
  ROUND(COALESCE(b.sales, 0) - COALESCE(a.ad_cost, 0) - COALESCE(b.cogs, 0), 2) as net_profit,
  COALESCE(b.orders, 0) as orders,
  COALESCE(a.clicks, 0) as clicks,
  COALESCE(b.sessions, 0) as sessions,
  ROUND(SAFE_DIVIDE(COALESCE(b.sales, 0) - COALESCE(b.cogs, 0), NULLIF(COALESCE(a.ad_cost, 0), 0)), 2) as net_roas,
  ROUND(SAFE_DIVIDE(GREATEST(COALESCE(b.orders, 0) - COALESCE(a.ad_orders, 0), 0) * 100.0, NULLIF(COALESCE(b.orders, 0), 0)), 1) as organic_pct
FROM biz b
FULL OUTER JOIN ads a ON b.product_type = a.product_type AND b.asin = a.asin AND b.week_start = a.week_start
ORDER BY 1, 2, 4
"""

QUERIES["monthly_trends_by_asin.json"] = """\
WITH family_map AS (
  SELECT asin,
    CASE
      WHEN product_short_name LIKE '%Lollibox%' THEN 'Lollibox'
      WHEN product_short_name LIKE '%LolliME%' THEN 'LolliME'
      WHEN product_short_name LIKE '%Fresh%' THEN 'Fresh'
      WHEN product_short_name LIKE '%Truth%' OR product_short_name LIKE '%Bottle%' THEN 'Bottle'
      ELSE product_short_name
    END as family,
    product_short_name
  FROM `onyga-482313.OI.DIM_PRODUCT` WHERE asin IS NOT NULL AND asin != 'UNKNOWN'
),
latest_costs AS (
  SELECT asin, TOTAL_COST_PER_UNIT
  FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  WHERE end_date IS NULL
    OR end_date = (SELECT MAX(end_date) FROM `onyga-482313.OI.DIM_COSTS_HISTORY` c2 WHERE c2.asin = `onyga-482313.OI.DIM_COSTS_HISTORY`.asin)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY asin ORDER BY start_date DESC) = 1
),
biz AS (
  SELECT fm.family as product_type,
    b.child_asin as asin,
    fm.product_short_name,
    DATE_TRUNC(b.date, MONTH) as month_start,
    SUM(b.SALES_AMOUNT) as sales,
    SUM(b.SALES_ORDERS) as orders,
    SUM(b.asin_sessions) as sessions,
    SUM(b.SALES_QUANTITY * COALESCE(lc.TOTAL_COST_PER_UNIT, 0)) as cogs
  FROM `onyga-482313.OI.V_SRC_sales_and_traffic_business_sku_report_daily` b
  JOIN family_map fm ON b.child_asin = fm.asin
  LEFT JOIN latest_costs lc ON b.child_asin = lc.asin
  WHERE b.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 1095 DAY)
  GROUP BY 1, 2, 3, 4
),
ads AS (
  SELECT fm.family as product_type,
    a.most_advertised_asin_impressions as asin,
    fm.product_short_name,
    DATE_TRUNC(a.date, MONTH) as month_start,
    SUM(a.cost) as ad_cost,
    SUM(a.clicks) as clicks,
    SUM(a.orders) as ad_orders
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN family_map fm ON a.most_advertised_asin_impressions = fm.asin
  WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 1095 DAY)
  GROUP BY 1, 2, 3, 4
)
SELECT
  COALESCE(b.product_type, a.product_type) as product_type,
  COALESCE(b.asin, a.asin) as asin,
  COALESCE(b.product_short_name, a.product_short_name) as product_short_name,
  COALESCE(b.month_start, a.month_start) as month_start,
  ROUND(COALESCE(b.sales, 0), 2) as sales,
  ROUND(COALESCE(a.ad_cost, 0), 2) as ad_cost,
  ROUND(COALESCE(b.cogs, 0), 2) as cogs,
  ROUND(COALESCE(b.sales, 0) - COALESCE(a.ad_cost, 0) - COALESCE(b.cogs, 0), 2) as net_profit,
  COALESCE(b.orders, 0) as orders,
  COALESCE(a.clicks, 0) as clicks,
  COALESCE(b.sessions, 0) as sessions,
  ROUND(SAFE_DIVIDE(COALESCE(b.sales, 0) - COALESCE(b.cogs, 0), NULLIF(COALESCE(a.ad_cost, 0), 0)), 2) as net_roas,
  ROUND(SAFE_DIVIDE(GREATEST(COALESCE(b.orders, 0) - COALESCE(a.ad_orders, 0), 0) * 100.0, NULLIF(COALESCE(b.orders, 0), 0)), 1) as organic_pct
FROM biz b
FULL OUTER JOIN ads a ON b.product_type = a.product_type AND b.asin = a.asin AND b.month_start = a.month_start
ORDER BY 1, 2, 4
"""

QUERIES["learnings.json"] = """\
SELECT *
FROM `onyga-482313.OI.V_EXPERIMENT_LEARNINGS`
ORDER BY learning_dimension, experiment_count DESC
"""

QUERIES["experiments.json"] = """\
SELECT *
FROM `onyga-482313.OI.V_EXPERIMENT_SUMMARY`
ORDER BY status DESC, experiment_name
"""

QUERIES["budget_health.json"] = """\
SELECT *
FROM `onyga-482313.OI.V_EXPERIMENT_BUDGET_HEALTH`
ORDER BY experiment_id
"""

QUERIES["drivers.json"] = """\
SELECT
  r.search_term,
  r.product_short_name,
  r.experiment_id,
  r.action,
  ROUND(r.ads_spend, 2) as spend,
  r.ads_orders as orders,
  r.ads_clicks as clicks,
  ROUND(SAFE_DIVIDE(r.ads_spend, NULLIF(r.ads_clicks, 0)), 2) as cpc,
  ROUND(r.ads_cvr_pct, 2) as conv_rate,
  ROUND(r.margin_per_unit, 2) as margin_per_unit,
  ROUND(r.your_orders_share_pct, 1) as impression_share,
  ROUND(r.ads_net_roas, 2) as net_roas,
  CASE
    WHEN p.product_short_name LIKE '%Lollibox%' THEN 'Lollibox'
    WHEN p.product_short_name LIKE '%LolliME%' THEN 'LolliME'
    WHEN p.product_short_name LIKE '%Fresh%' THEN 'Fresh'
    WHEN p.product_short_name LIKE '%Truth%' OR p.product_short_name LIKE '%Bottle%' THEN 'Bottle'
    ELSE p.product_short_name
  END as product_type
FROM `onyga-482313.OI.V_EXPERIMENT_TERM_RECOMMENDATIONS` r
LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON r.hero_asin = p.asin
ORDER BY r.ads_spend DESC
LIMIT 2000
"""

QUERIES["experiment_weekly.json"] = """\
WITH exp_daily AS (
  SELECT
    fed.experiment_id,
    de.experiment_name,
    de.strategy_id,
    DATE_TRUNC(fed.snapshot_date, WEEK(SUNDAY)) as week_start,
    SUM(fed.performance_total_orders) as total_orders,
    SUM(fed.performance_organic_orders) as organic_orders,
    SUM(fed.ads_all_orders) as ads_orders,
    SUM(fed.ads_all_cost) as ads_spend,
    SUM(fed.performance_sessions) as sessions,
    SUM(fed.performance_total_sales) as sales
  FROM `onyga-482313.OI.FACT_EXPERIMENT_DAILY` fed
  JOIN `onyga-482313.OI.DIM_EXPERIMENT` de ON fed.experiment_id = de.experiment_id
  WHERE fed.snapshot_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 84 DAY)
  GROUP BY 1, 2, 3, 4
)
SELECT
  experiment_id,
  experiment_name,
  strategy_id,
  week_start,
  ROUND(sales, 2) as sales,
  ROUND(ads_spend, 2) as ads_spend,
  total_orders,
  ads_orders,
  organic_orders,
  sessions,
  ROUND(SAFE_DIVIDE(ads_orders * 100.0, NULLIF(sessions, 0)), 2) as conv_rate,
  ROUND(SAFE_DIVIDE(sales - ads_spend, NULLIF(ads_spend, 0)), 2) as net_roas,
  ROUND(SAFE_DIVIDE(organic_orders * 100.0, NULLIF(total_orders, 0)), 1) as organic_pct
FROM exp_daily
WHERE total_orders > 0 OR ads_spend > 0
ORDER BY experiment_id, week_start
"""

QUERIES["sqp_weekly.json"] = """\
WITH family_map AS (
  SELECT asin,
    CASE
      WHEN product_short_name LIKE '%Lollibox%' THEN 'Lollibox'
      WHEN product_short_name LIKE '%LolliME%' THEN 'LolliME'
      WHEN product_short_name LIKE '%Fresh%' THEN 'Fresh'
      WHEN product_short_name LIKE '%Truth%' OR product_short_name LIKE '%Bottle%' THEN 'Bottle'
      ELSE product_short_name
    END as family,
    product_short_name
  FROM `onyga-482313.OI.DIM_PRODUCT` WHERE asin IS NOT NULL AND asin != 'UNKNOWN'
),
agg AS (
  SELECT
    fm.family as product_type,
    s.ASIN as asin,
    fm.product_short_name,
    DATE_SUB(s.Reporting_Date, INTERVAL 6 DAY) as week_start,
    s.Search_Query as search_term,
    COALESCE(s.Impressions, 0) as impressions,
    COALESCE(s.Clicks, 0) as clicks,
    COALESCE(s.Cart_Adds, 0) as cart_adds,
    COALESCE(s.ORDERS, 0) as orders,
    COALESCE(s.AMAZON_IMPRESSIONS, 0) as amazon_impressions,
    COALESCE(s.AMAZON_Clicks, 0) as amazon_clicks,
    COALESCE(s.AMAZON_ORDERS, 0) as amazon_orders,
    COALESCE(s.ADS_Impressions, 0) as ads_impressions,
    COALESCE(s.ADS_Clicks, 0) as ads_clicks,
    COALESCE(s.ADS_Orders, 0) as ads_orders,
    ROUND(COALESCE(s.show_rate_pct, 0), 1) as show_rate_pct,
    GREATEST(1, ROUND(48 * (1 - LEAST(COALESCE(s.show_rate_pct, 0), 100) / 100), 0)) as estimated_organic_rank,
    COALESCE(s.organic_rank_zone, 'unknown') as organic_rank_zone,
    ROUND(COALESCE(s.Search_Query_Score, 0), 0) as search_query_score
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` s
  JOIN family_map fm ON s.ASIN = fm.asin
  WHERE s.Reporting_Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 395 DAY)
    AND s.Impressions IS NOT NULL AND s.Impressions > 0
),
ranked AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY asin, week_start ORDER BY orders DESC, impressions DESC) as rn
  FROM agg
)
SELECT product_type, asin, product_short_name, week_start, search_term,
  impressions, clicks, cart_adds, orders,
  amazon_impressions, amazon_clicks, amazon_orders,
  ads_impressions, ads_clicks, ads_orders,
  show_rate_pct, estimated_organic_rank, organic_rank_zone, search_query_score
FROM ranked
WHERE rn <= 100
ORDER BY week_start DESC, orders DESC
"""

QUERIES["experiment_campaigns.json"] = """\
WITH mapped AS (
  SELECT experiment_id, campaign_id,
    top_of_search_pct, product_page_pct, rest_of_search_pct, notes
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN`
),
campaign_perf AS (
  SELECT campaign_id, campaign_name, campaign_type,
    ROUND(SUM(cost), 2) as spend,
    SUM(orders) as orders,
    SUM(clicks) as clicks,
    SUM(impressions) as impressions,
    CAST(MIN(date) AS STRING) as first_date,
    CAST(MAX(date) AS STRING) as last_date
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
  GROUP BY campaign_id, campaign_name, campaign_type
  HAVING SUM(cost) > 0
)
SELECT
  m.experiment_id,
  cp.campaign_id,
  cp.campaign_name,
  cp.campaign_type,
  m.top_of_search_pct,
  m.product_page_pct,
  m.rest_of_search_pct,
  m.notes,
  cp.spend,
  cp.orders,
  cp.clicks,
  cp.impressions,
  cp.first_date,
  cp.last_date
FROM campaign_perf cp
LEFT JOIN mapped m ON cp.campaign_id = m.campaign_id
ORDER BY cp.spend DESC
"""

QUERIES["campaign_search_terms.json"] = """\
SELECT
  CAST(a.campaign_id AS STRING) as campaign_id,
  a.search_term,
  ROUND(SUM(a.cost), 2) as spend,
  SUM(a.orders) as orders,
  SUM(a.clicks) as clicks,
  SUM(a.impressions) as impressions,
  ROUND(SAFE_DIVIDE(SUM(a.orders) * 100.0, NULLIF(SUM(a.clicks), 0)), 2) as conv_rate,
  ROUND(SAFE_DIVIDE(SUM(a.cost), NULLIF(SUM(a.clicks), 0)), 2) as cpc
FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
WHERE a.search_term IS NOT NULL AND a.search_term != ''
  AND a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
GROUP BY a.campaign_id, a.search_term
HAVING SUM(a.cost) > 0
ORDER BY spend DESC
LIMIT 10000
"""

QUERIES["ads_7d.json"] = """\
WITH latest_costs AS (
  SELECT asin, TOTAL_COST_PER_UNIT
  FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  WHERE end_date IS NULL
    OR end_date = (SELECT MAX(end_date) FROM `onyga-482313.OI.DIM_COSTS_HISTORY` c2 WHERE c2.asin = `onyga-482313.OI.DIM_COSTS_HISTORY`.asin)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY asin ORDER BY start_date DESC) = 1
),
row_asin AS (
  SELECT
    a.*,
    COALESCE(
      a.most_advertised_asin_impressions,
      a.most_advertised_asin_clicks,
      a.most_advertised_asin_purchased,
      TRIM(SPLIT(COALESCE(a.advertised_asins, ''), ',')[SAFE_OFFSET(0)])
    ) AS row_asin
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 91 DAY)
    AND (a.cost > 0 OR a.clicks > 0 OR a.orders > 0)
),
camp AS (
  SELECT
    CAST(DATE_TRUNC(a.date, WEEK(SUNDAY)) AS STRING) as week_start,
    a.campaign_id,
    a.campaign_name,
    a.campaign_type,
    ANY_VALUE(pf.portfolio_name) as portfolio_name,
    p.product_short_name,
    ROUND(SUM(a.cost), 2) as spend,
    SUM(a.orders) as orders,
    SUM(a.clicks) as clicks,
    SUM(a.impressions) as impressions,
    ROUND(SUM(a.sales), 2) as sales,
    ROUND(SUM(COALESCE(a.GROSS_PROFIT, 0)), 2) as gross_profit,
    ROUND(SUM(a.orders * COALESCE(lc.TOTAL_COST_PER_UNIT, 0)), 2) as cogs,
    ROUND(SAFE_DIVIDE(SUM(a.cost), NULLIF(SUM(a.clicks), 0)), 2) as cpc,
    ROUND(SAFE_DIVIDE(SUM(a.orders) * 100.0, NULLIF(SUM(a.clicks), 0)), 2) as conv_rate,
    ROUND(SAFE_DIVIDE(SUM(a.sales), NULLIF(SUM(a.cost), 0)), 2) as gross_roas,
    ROUND(SAFE_DIVIDE(SUM(a.sales) - SUM(a.orders * COALESCE(lc.TOTAL_COST_PER_UNIT, 0)), NULLIF(SUM(a.cost), 0)), 2) as roas,
    COUNT(DISTINCT a.search_term) as search_terms_count
  FROM row_asin a
  LEFT JOIN latest_costs lc ON a.row_asin = lc.asin
  JOIN `onyga-482313.OI.DIM_PRODUCT` p
    ON p.asin = a.row_asin AND p.asin IS NOT NULL AND p.asin != 'UNKNOWN'
  LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` ch
    ON a.campaign_id = ch.campaign_id
    AND TIMESTAMP(a.date) BETWEEN ch.OI_start_date AND ch.OI_end_date
  LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_portfolio` pf
    ON ch.portfolio_id = pf.portfolio_id
    AND TIMESTAMP(a.date) BETWEEN pf.OI_start_date AND pf.OI_end_date
  GROUP BY 1, 2, 3, 4, 6
),
terms AS (
  SELECT
    CAST(DATE_TRUNC(a.date, WEEK(SUNDAY)) AS STRING) as week_start,
    a.campaign_id,
    a.campaign_name,
    a.search_term,
    ANY_VALUE(pf.portfolio_name) as portfolio_name,
    p.product_short_name,
    ROUND(SUM(a.cost), 2) as spend,
    SUM(a.orders) as orders,
    SUM(a.clicks) as clicks,
    SUM(a.impressions) as impressions,
    ROUND(SUM(a.sales), 2) as sales,
    ROUND(SUM(a.orders * COALESCE(lc.TOTAL_COST_PER_UNIT, 0)), 2) as cogs,
    ROUND(SAFE_DIVIDE(SUM(a.cost), NULLIF(SUM(a.clicks), 0)), 2) as cpc,
    ROUND(SAFE_DIVIDE(SUM(a.orders) * 100.0, NULLIF(SUM(a.clicks), 0)), 2) as conv_rate,
    ROUND(SAFE_DIVIDE(SUM(a.sales), NULLIF(SUM(a.cost), 0)), 2) as gross_roas,
    ROUND(SAFE_DIVIDE(SUM(a.sales) - SUM(a.orders * COALESCE(lc.TOTAL_COST_PER_UNIT, 0)), NULLIF(SUM(a.cost), 0)), 2) as roas
  FROM row_asin a
  LEFT JOIN latest_costs lc ON a.row_asin = lc.asin
  JOIN `onyga-482313.OI.DIM_PRODUCT` p
    ON p.asin = a.row_asin AND p.asin IS NOT NULL AND p.asin != 'UNKNOWN'
  LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` ch
    ON a.campaign_id = ch.campaign_id
    AND TIMESTAMP(a.date) BETWEEN ch.OI_start_date AND ch.OI_end_date
  LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_portfolio` pf
    ON ch.portfolio_id = pf.portfolio_id
    AND TIMESTAMP(a.date) BETWEEN pf.OI_start_date AND pf.OI_end_date
  WHERE a.search_term IS NOT NULL AND a.search_term != ''
  GROUP BY 1, 2, 3, 4, 6
  HAVING SUM(a.cost) >= 1
)
SELECT 'campaign' as row_type,
  c.week_start,
  c.campaign_id, c.campaign_name, c.campaign_type,
  c.portfolio_name,
  c.product_short_name,
  NULL as search_term,
  c.spend, c.orders, c.clicks, c.impressions, c.sales, c.cogs, c.gross_profit,
  c.cpc, c.conv_rate, c.gross_roas, c.roas, c.search_terms_count
FROM camp c
UNION ALL
SELECT 'search_term' as row_type,
  t.week_start,
  t.campaign_id, t.campaign_name, NULL as campaign_type,
  t.portfolio_name,
  t.product_short_name,
  t.search_term,
  t.spend, t.orders, t.clicks, t.impressions, t.sales, t.cogs, NULL as gross_profit,
  t.cpc, t.conv_rate, t.gross_roas, t.roas, NULL as search_terms_count
FROM terms t
ORDER BY week_start DESC, row_type, spend DESC
"""

QUERIES["experiment_templates.json"] = """\
WITH exp_data AS (
  SELECT
    e.strategy_id,
    e.experiment_id,
    e.experiment_name,
    e.description,
    e.status,
    CAST(e.start_date AS STRING) as start_date,
    CAST(e.end_date AS STRING) as end_date,
    e.baseline_days,
    e.outcome_score,
    e.outcome_tags,
    e.outcome_notes,
    e.lifecycle_stage,
    e.graduation_confidence,
    e.season_context,
    DATE_DIFF(COALESCE(e.end_date, CURRENT_DATE()), e.start_date, DAY) as days_running
  FROM `onyga-482313.OI.DIM_EXPERIMENT` e
),
exp_perf AS (
  SELECT
    ec.experiment_id,
    ROUND(SUM(a.cost), 2) as total_spend,
    SUM(a.orders) as total_orders,
    SUM(a.clicks) as total_clicks,
    SUM(a.impressions) as total_impressions,
    ROUND(SUM(a.sales), 2) as total_sales,
    ROUND(SAFE_DIVIDE(SUM(a.sales) - SUM(a.cost), NULLIF(SUM(a.cost), 0)), 2) as net_roas,
    ROUND(SAFE_DIVIDE(SUM(a.orders) * 100.0, NULLIF(SUM(a.clicks), 0)), 2) as conv_rate,
    ROUND(SAFE_DIVIDE(SUM(a.cost), NULLIF(SUM(a.clicks), 0)), 2) as cpc,
    COUNT(DISTINCT a.search_term) as unique_search_terms
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` a ON ec.campaign_id = a.campaign_id
  WHERE a.cost > 0
  GROUP BY ec.experiment_id
)
SELECT
  d.strategy_id, d.experiment_id, d.experiment_name, d.description,
  d.status, d.start_date, d.end_date, d.baseline_days,
  d.outcome_score, d.outcome_tags, d.outcome_notes,
  d.lifecycle_stage, d.graduation_confidence, d.season_context,
  d.days_running,
  p.total_spend, p.total_orders, p.total_clicks, p.total_impressions,
  p.total_sales, p.net_roas, p.conv_rate, p.cpc, p.unique_search_terms
FROM exp_data d
LEFT JOIN exp_perf p ON d.experiment_id = p.experiment_id
ORDER BY d.strategy_id, d.start_date DESC
"""

QUERIES["change_log.json"] = """\
SELECT
  change_id, experiment_id, change_date, change_type,
  campaign_id, field_changed, old_value, new_value,
  reason, source, created_at
FROM `onyga-482313.OI.DIM_EXPERIMENT_CHANGE_LOG`
ORDER BY change_date DESC, created_at DESC
LIMIT 200
"""


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Refresh dashboard JSON data from BigQuery")
    parser.add_argument("--dry-run", action="store_true", help="Print SQL queries without executing")
    args = parser.parse_args()

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)

    if args.dry_run:
        for name, sql in QUERIES.items():
            print(f"\n{'='*60}")
            print(f"-- {name}")
            print(f"{'='*60}")
            print(sql)
        print(f"\n-- negative_keywords.json: parsed from CSV at {CSV_PATH}")
        return

    client = bigquery.Client(project=PROJECT)
    queries_run = 0
    queries_failed = 0
    file_stats = {}

    print("Refreshing dashboard data…\n")

    for name, sql in QUERIES.items():
        output_path = ARCHIVE_DIR / name
        try:
            row_count = run_query_to_json(client, sql, output_path)
            queries_run += 1
            file_stats[name] = {"status": "ok", "rows": row_count}
        except Exception as exc:
            queries_failed += 1
            print(f"  ✗ {name}: {exc}")
            file_stats[name] = {"status": "error", "error": str(exc)}

    # negative keywords from CSV
    try:
        row_count = parse_csv_to_json(CSV_PATH, DATA_DIR / "negative_keywords.json")
        queries_run += 1
        file_stats["negative_keywords.json"] = {"status": "ok", "rows": row_count, "source": "CSV"}
    except Exception as exc:
        queries_failed += 1
        print(f"  ✗ negative_keywords.json: {exc}")
        file_stats["negative_keywords.json"] = {"status": "error", "error": str(exc)}

    # SQP volume by term (last 4 weeks) - lightweight file for Ads page (archived)
    try:
        sqp_path = ARCHIVE_DIR / "sqp_weekly.json"
        if sqp_path.exists():
            sqp = json.loads(sqp_path.read_text())
            weeks = sorted({r.get("week_start", "") for r in sqp if r.get("week_start")})[-4:]
            by_term = {}
            for r in sqp:
                w = r.get("week_start", "")
                if w not in weeks:
                    continue
                term = (r.get("search_term") or "").lower().strip()
                if not term:
                    continue
                by_term[term] = by_term.get(term, 0) + (r.get("amazon_impressions") or 0)
            with open(ARCHIVE_DIR / "sqp_volume_4w.json", "w") as f:
                json.dump(by_term, f)
            print(f"  ✓ sqp_volume_4w.json: {len(by_term)} terms")
            file_stats["sqp_volume_4w.json"] = {"status": "ok", "rows": len(by_term)}
        else:
            file_stats["sqp_volume_4w.json"] = {"status": "skipped", "reason": "sqp_weekly.json not found"}
    except Exception as exc:
        print(f"  ✗ sqp_volume_4w.json: {exc}")
        file_stats["sqp_volume_4w.json"] = {"status": "error", "error": str(exc)}

    # Compute date ranges from the actual data
    date_ranges = {}
    try:
        summary = json.loads((ARCHIVE_DIR / "summary.json").read_text())
        if summary:
            ps = summary[0].get("period_start", "")
            pe = summary[0].get("period_end", "")
            if ps and pe:
                date_ranges["summary_7d"] = {"start": ps, "end": pe}
    except Exception:
        pass

    # Data freshness: ads from FACT_AMAZON_ADS, perf from FACT_AMAZON_PERFORMANCE_DAILY
    data_freshness = {}
    try:
        freshness_sql = """\
WITH ads_max AS (
  SELECT MAX(`DATE`) AS ads_max_date FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),
perf_max AS (
  SELECT MAX(CASE WHEN DATA_SOURCE='STG_AMAZON_PERFORMANCE' THEN `DATE` END) AS performance_max_date
  FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
)
SELECT a.ads_max_date, p.performance_max_date FROM ads_max a CROSS JOIN perf_max p
"""
        rows = list(client.query(freshness_sql).result())
        if rows:
            r = dict(rows[0])
            data_freshness["ads_max_date"] = r.get("ads_max_date")
            data_freshness["performance_max_date"] = r.get("performance_max_date")
            # Serialise date objects to strings
            for k, v in data_freshness.items():
                if isinstance(v, (date, datetime)):
                    data_freshness[k] = v.isoformat()
        print(f"  ✓ data_freshness: ads={data_freshness.get('ads_max_date')}, perf={data_freshness.get('performance_max_date')}")
    except Exception as exc:
        print(f"  ✗ data_freshness query failed: {exc}")

    # metadata
    meta = {
        "refreshed_at": datetime.now(tz=None).isoformat(),
        "queries_run": queries_run,
        "queries_failed": queries_failed,
        "date_ranges": date_ranges,
        "data_freshness": data_freshness,
        "files": file_stats,
    }
    with open(DATA_DIR / "_meta.json", "w") as f:
        json.dump(meta, f, indent=2)

    print(f"\nDone — {queries_run} succeeded, {queries_failed} failed.")
    print(f"Archive (Cube-backed): {ARCHIVE_DIR.resolve()}")
    print(f"Data (negative_keywords, _meta): {DATA_DIR.resolve()}")


if __name__ == "__main__":
    main()
