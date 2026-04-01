# Dashboard Validation Gap Analysis Report

**Run date**: 2026-02-09  
**Dashboard refresh**: `cd dashboard && python3 refresh_data.py`  
**Data freshness**: ads=2026-03-06, perf=2026-03-05

---

## Summary

| Validation Query | Dashboard JSON | Result |
|-----------------|----------------|--------|
| VALIDATE_ADS_PORTFOLIO_LEVEL | ads_7d.json (aggregated by portfolio) | **MATCH** |
| VALIDATE_SUMMARY_7D | summary.json | **MATCH** |
| VALIDATE_ACTIONS | actions.json | **MATCH** |
| VALIDATE_KEYWORD_PRODUCT_MAP | keyword_product_map.json | **MATCH** |
| VALIDATE_DRIVERS | drivers.json | **MATCH** |
| VALIDATE_EXPERIMENT_CAMPAIGNS | experiment_campaigns.json | **MATCH** |
| VALIDATE_SQP_WEEKLY | sqp_weekly.json | N/A (week-specific; run with desired week) |

---

## 1. Portfolio-Level (ads_7d)

**Validation**: `VALIDATE_ADS_PORTFOLIO_LEVEL.sql` (dates 2026-02-22 to 2026-02-28)  
**Dashboard**: `ads_7d.json` aggregated by `portfolio_name` for `week_start=2026-02-22`

| portfolio_name | Validation spend | Dashboard (agg) spend | Match |
|----------------|------------------|------------------------|-------|
| BOX | 1744.18 | 1744.18 | ✓ |
| ME | 1526.31 | 1526.31 | ✓ |
| FRESH | 970.63 | 970.63 | ✓ |
| BRAND | 436.33 | 436.33 | ✓ |
| BOTTLE | 321.47 | 321.47 | ✓ |

**Result**: MATCH. Portfolio totals align when comparing validation date range (Feb 22–28) to ads_7d week 2026-02-22.

---

## 2. Summary 7d

**Validation**: `VALIDATE_SUMMARY_7D.sql`  
**Dashboard**: `summary.json`

**Period**: 2026-02-27 to 2026-03-05 (biz_start = MAX(date) - 6 from V_SRC)

| product_type | sales_7d | ad_cost_7d | orders_7d | ad_orders_7d | net_roas | organic_pct |
|--------------|----------|------------|-----------|--------------|----------|-------------|
| LolliME | 9600.09 | 1421.04 | 286 | 168 | 1.57 | 42.3 |
| Lollibox | 7504.48 | 2145.23 | 137 | 97 | 0.55 | 29.2 |
| Fresh | 5232.4 | 1034.13 | 102 | 89 | 1.1 | 15.7 |
| Bottle | 926.9 | 239.6 | 31 | 15 | 0.81 | 51.6 |

**Result**: MATCH. All metrics identical between validation and dashboard.

---

## 3. Actions

**Validation**: `VALIDATE_ACTIONS.sql`  
**Dashboard**: `actions.json`

- **Rows**: 297 (both)
- **First 5 rows** (search_term, spend): Identical
  - 12 year old girl gifts: 31.62
  - gifts for 10 year old girl: 31.06
  - 11 year old girl gifts: 28.45
  - birthday gifts for girls: 28.22
  - stuff for girls 10-12: 26.7

**Result**: MATCH.

---

## 4. Keyword Product Map

**Validation**: `VALIDATE_KEYWORD_PRODUCT_MAP.sql`  
**Dashboard**: `keyword_product_map.json`

- **Rows**: 2000 (both)
- **First row**: `gifts for teenage girls` (top by spend)
- **Source**: V_EXPERIMENT_TERM_RECOMMENDATIONS, ORDER BY ads_spend DESC

**Result**: MATCH.

---

## 5. Drivers

**Validation**: `VALIDATE_DRIVERS.sql`  
**Dashboard**: `drivers.json`

- **Rows**: 2000 (both)
- **First row**: `gifts for teenage girls`, spend 96.2
- **Source**: V_EXPERIMENT_TERM_RECOMMENDATIONS, ORDER BY ads_spend DESC

**Result**: MATCH.

---

## 6. Experiment Campaigns

**Validation**: `VALIDATE_EXPERIMENT_CAMPAIGNS.sql`  
**Dashboard**: `experiment_campaigns.json`

- **Rows**: 97 (both)
- **First row**: BOX- STORE/ BROAD, spend 14552.6
- **Source**: DIM_EXPERIMENT_CAMPAIGN + FACT_AMAZON_ADS (90 days)

**Result**: MATCH.

---

## 7. SQP Weekly

**Validation**: `VALIDATE_SQP_WEEKLY.sql` (week_start = 2026-02-23)  
**Dashboard**: `sqp_weekly.json`

Run with desired `week_start` in the query. Filter `sqp_weekly.json` by `week_start` for comparison. Not run in this report.

---

## Notes

- **Portfolio**: Validation uses `date BETWEEN 2026-02-22 AND 2026-02-28`. ads_7d uses `week_start` (Sunday = 2026-02-22). Week 2026-02-22 = Feb 22–28, so overlap is exact.
- **Summary**: Uses dynamic date range from `MAX(date)` in V_SRC_sales_and_traffic_business_sku_report_daily.
- **Actions**: Filters `action NOT IN ('KEEP', 'MONITOR')`.
- **Drivers**: No action filter; includes all terms ordered by spend.
