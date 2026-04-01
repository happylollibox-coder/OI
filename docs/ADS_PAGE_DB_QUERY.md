# Ads Page — Database Query Chain

## 1. Cube API Request (from `useCubeData.ts` → `loadAdsFromCube`)

```json
{
  "measures": ["Ads.spend", "Ads.orders", "Ads.clicks", "Ads.impressions", "Ads.sales"],
  "dimensions": [
    "Ads.date",
    "Ads.campaignId",
    "Ads.campaignName",
    "Ads.campaignType",
    "Ads.searchTerm",
    "Product.productShortName"
  ],
  "timeDimensions": [{ "dimension": "Ads.date", "dateRange": "Last 91 days" }],
  "limit": 50000
}
```

**Endpoint:** `POST /cubejs-api/v1/load`

---

## 2. Cube Schema — Ads (`cube/schema/Ads.js`)

**Base SQL (subquery):**
```sql
SELECT * FROM `onyga-482313.OI.FACT_AMAZON_ADS`
WHERE cost > 0 OR impressions > 0
```

**Join to Product:**
```sql
LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` Product
  ON Ads.most_advertised_asin_impressions = Product.asin
```

**Column mapping:**
| Cube measure/dimension | SQL column |
|------------------------|------------|
| Ads.spend              | `cost`     |
| Ads.orders             | `orders`   |
| Ads.clicks             | `clicks`   |
| Ads.impressions        | `impressions` |
| Ads.sales              | `sales`    |
| Ads.date               | `date`     |
| Ads.campaignId         | `campaign_id` |
| Ads.campaignName       | `campaign_name` |
| Ads.campaignType       | `campaign_type` |
| Ads.searchTerm         | `search_term` |

---

## 3. Approximate SQL Cube Generates

Cube compiles the request into SQL similar to:

```sql
SELECT
  DATE_TRUNC(Ads.date, DAY) AS "Ads.date",
  Ads.campaign_id AS "Ads.campaignId",
  Ads.campaign_name AS "Ads.campaignName",
  Ads.campaign_type AS "Ads.campaignType",
  Ads.search_term AS "Ads.searchTerm",
  Product.product_short_name AS "Product.productShortName",
  SUM(Ads.cost) AS "Ads.spend",
  SUM(Ads.orders) AS "Ads.orders",
  SUM(Ads.clicks) AS "Ads.clicks",
  SUM(Ads.impressions) AS "Ads.impressions",
  SUM(Ads.sales) AS "Ads.sales"
FROM (
  SELECT * FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE cost > 0 OR impressions > 0
) AS Ads
LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` Product
  ON Ads.most_advertised_asin_impressions = Product.asin
WHERE Ads.date >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 91 DAY)
GROUP BY 1, 2, 3, 4, 5, 6
ORDER BY "Ads.spend" DESC
LIMIT 50000
```

---

## 4. Base Table — FACT_AMAZON_ADS

**Location:** `scripts/bigquery/tables/FACT/FACT_AMAZON_ADS.sql`

**Relevant columns:**
- `date`, `campaign_id`, `campaign_name`, `campaign_type`
- `ad_group_id`, `keyword_id`, `search_term`
- `impressions`, `clicks`, `orders`, `units`, `cost`, `sales`
- `most_advertised_asin_impressions` (used for Product join)

**Note:** The table DDL shows `Ads_cost`, `Ads_impressions`, etc., but `SP_FACT_AMAZON_ADS` inserts into `cost`, `impressions`, etc. If the table was migrated to `Ads_*` names, the Cube schema and SP may need to be updated.

---

## 5. Data Flow

```
STG_AMAZON_ADS (Fivetran) 
    → SP_FACT_AMAZON_ADS 
    → FACT_AMAZON_ADS 
    → Cube Ads 
    → loadAdsFromCube() 
    → ads_7d 
    → AdsPerformancePage
```

---

## 6. Raw BigQuery (for debugging)

To run a direct query against the table:

```sql
SELECT
  date,
  campaign_id,
  campaign_name,
  campaign_type,
  search_term,
  cost,
  orders,
  clicks,
  impressions,
  sales
FROM `onyga-482313.OI.FACT_AMAZON_ADS`
WHERE (cost > 0 OR impressions > 0)
  AND date >= DATE_SUB(CURRENT_DATE(), INTERVAL 91 DAY)
ORDER BY cost DESC
LIMIT 100
```

---

## 7. Possible Column Mismatch

If `FACT_AMAZON_ADS` uses `Ads_cost`, `Ads_impressions`, etc., the Cube schema must reference those names:

```javascript
// cube/schema/Ads.js - if table has Ads_* columns:
sql: `SELECT * FROM \`onyga-482313.OI.FACT_AMAZON_ADS\` WHERE Ads_cost > 0 OR Ads_impressions > 0`,
spend: { sql: `Ads_cost`, ... },
orders: { sql: `Ads_orders`, ... },
clicks: { sql: `Ads_clicks`, ... },
impressions: { sql: `Ads_impressions`, ... },
sales: { sql: `Ads_sales`, ... },
```
