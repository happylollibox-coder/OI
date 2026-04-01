# Data Source for Family Table (Sales, COGS, Orders, Organic %)

## Data Source (Updated)

**Sales, COGS, Orders, Organic %** are now sourced from **FACT_AMAZON_PERFORMANCE_DAILY** (Weekly Performance Fact), aggregated by week/month and family.

---

## Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  SALES, COGS, ORDERS, ORGANIC % (biz side)                                       │
├─────────────────────────────────────────────────────────────────────────────────┤
│  FACT_AMAZON_PERFORMANCE_DAILY (Performance Fact)                                │
│       │  (DATE, PURCHASED_ASIN, PURCHASED_AMOUNT_USD, PURCHASED_ORDERS,          │
│       │   PURCHASED_UNITS, TOTAL_COST_PER_UNIT, ASIN_SESSIONS, Performance_TYPE)  │
│       │  Sources: FACT_AMAZON_ADS (ads) + STG_AMAZON_PERFORMANCE (organic)       │
│       │                                                                           │
│       + DIM_PRODUCT (family_map: PURCHASED_ASIN → Lollibox/LolliME/Fresh/Bottle)  │
│       + DIM_TIME (full_date, week_start_date for weekly aggregation)              │
│       │                                                                           │
│       ▼ Cube WeeklyTrends / MonthlyTrends                                         │
│  biz CTE: JOIN on p.PURCHASED_ASIN = fm.asin AND p.DATE = dt.full_date           │
│  Organic % = organic_orders / total_orders (from Performance_TYPE = 'Organic')   │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│  ADS SPEND, CLICKS (ads side)                                                    │
├─────────────────────────────────────────────────────────────────────────────────┤
│  Amazon Ads API                                                                   │
│       │                                                                           │
│       ▼ ETL                                                                       │
│  OI.STG_AMAZON_ADS → OI.FACT_AMAZON_ADS                                          │
│       │  (date, cost, clicks, orders, most_advertised_asin_impressions)           │
│       │                                                                           │
│       + DIM_PRODUCT (family_map)                                                  │
│       + DIM_TIME                                                                  │
│       │                                                                           │
│       ▼ Cube WeeklyTrends / MonthlyTrends                                         │
│  ads CTE: JOIN on a.most_advertised_asin_impressions = fm.asin                    │
└─────────────────────────────────────────────────────────────────────────────────┘

Cube: FULL OUTER JOIN biz + ads on (product_type, week_start)
      → Rows with ads but no biz = Ads Spend/Clicks present, Sales/Orders/COGS = 0
```

---

## BigQuery Tables / Views

| Field | Source Table | Source Column / Logic |
|-------|--------------|----------------------|
| **Sales** | `FACT_AMAZON_PERFORMANCE_DAILY` | `SUM(PURCHASED_AMOUNT_USD)` |
| **COGS** | `FACT_AMAZON_PERFORMANCE_DAILY` | `SUM(PURCHASED_UNITS * TOTAL_COST_PER_UNIT)` |
| **Orders** | `FACT_AMAZON_PERFORMANCE_DAILY` | `SUM(PURCHASED_ORDERS)` |
| **Organic %** | `FACT_AMAZON_PERFORMANCE_DAILY` | `SUM(CASE WHEN Performance_TYPE='Organic' THEN PURCHASED_ORDERS ELSE 0 END) / SUM(PURCHASED_ORDERS) * 100` |
| **Ads Spend** | `FACT_AMAZON_ADS` | `cost` |
| **Clicks** | `FACT_AMAZON_ADS` | `clicks` |

---

## Root Cause Checklist

If Sales, COGS, Orders, Organic % are empty:

1. **FACT_AMAZON_PERFORMANCE_DAILY**
   - Ensure `SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY` runs in the orchestration (depends on STG_AMAZON_PERFORMANCE, STG_AmazonAds_purchased_product).
   - Check the table has recent rows for the last 84 days.

2. **ASIN mapping**
   - `PURCHASED_ASIN` must exist in `DIM_PRODUCT.asin` (family_map).
   - Run:
     ```sql
     SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` p
     WHERE NOT EXISTS (SELECT 1 FROM `onyga-482313.OI.DIM_PRODUCT` d WHERE d.asin = p.PURCHASED_ASIN);
     ```

3. **DIM_TIME**
   - `p.DATE` must match `DIM_TIME.full_date` for weekly aggregation.
   - Ensure `SP_POPULATE_DIM_TIME` has been run.

---

## Quick Diagnostic Query

Run in BigQuery to see if the biz side has data:

```sql
-- Check if FACT_AMAZON_PERFORMANCE_DAILY has sales data for last 84 days
SELECT 
  COUNT(*) as row_count,
  MIN(DATE) as min_date,
  MAX(DATE) as max_date,
  SUM(PURCHASED_AMOUNT_USD) as total_sales,
  SUM(PURCHASED_ORDERS) as total_orders
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
WHERE DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 84 DAY);

-- Check how many rows match DIM_PRODUCT (family_map)
WITH family_map AS (
  SELECT asin FROM `onyga-482313.OI.DIM_PRODUCT` 
  WHERE asin IS NOT NULL AND asin != 'UNKNOWN'
)
SELECT COUNT(*) as matching_rows
FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` p
JOIN family_map fm ON p.PURCHASED_ASIN = fm.asin
WHERE p.DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 84 DAY);
```

If `row_count` or `matching_rows` is 0, the biz pipeline is the problem.
