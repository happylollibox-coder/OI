# STG_SQP_WEEKLY vs STG_SCP_WEEKLY Comparison

## Overview

Both tables store weekly performance data but at different granularities:
- **STG_SQP_WEEKLY**: Query+ASIN level (Search Query Performance)
- **STG_SCP_WEEKLY**: ASIN level only (Search Catalog Performance)

## Key Differences Summary

| Aspect | STG_SQP_WEEKLY | STG_SCP_WEEKLY |
|--------|----------------|----------------|
| **Granularity** | Query + ASIN | ASIN only |
| **Primary Key** | `(query_text, ASIN, Year, Week)` | `(ASIN, Year, Week)` |
| **Data Source** | Search Query Performance (query-level detail) | Search Catalog Performance (ASIN-level aggregate) |
| **Query Detail** | ✅ Has query text | ❌ No query text |
| **Total Metrics** | ✅ Has TOTAL_* fields | ❌ No TOTAL_* fields |
| **Query Ranking** | ✅ Has query_rank, avg_position | ❌ No ranking fields |
| **Change Detection** | ✅ Only updates if data changed | ❌ Always updates matched records |

## Field-by-Field Comparison

### Common Fields (Same Name & Type)

| Field Name | Data Type | Purpose |
|------------|-----------|---------|
| `ASIN` | STRING | Product identifier |
| `Year` | INT64 | Year extracted from date |
| `Week` | INT64 | Week number |
| `ob_date` | DATE | Original date from source |
| `week_start_date` | DATE | Week start (Monday) |
| `week_end_date` | DATE | Week end (Sunday) |
| `impressions` | INT64 | Number of impressions |
| `clicks` | INT64 | Number of clicks |
| `click_through_rate` | FLOAT64 | CTR percentage |
| `cart_adds` | INT64 | Number of cart adds |
| `conversions` | INT64 | Number of conversions/purchases |
| `conversion_rate` | FLOAT64 | Conversion rate percentage |
| `sales_amount` | FLOAT64 | Total sales amount |
| `sales_currency_code` | STRING | Currency code for sales |
| `ob_file_name` | STRING | OpenBridge metadata |
| `ob_marketplace_id` | STRING | OpenBridge metadata |
| `ob_seller_id` | STRING | OpenBridge metadata |
| `ob_transaction_id` | STRING | OpenBridge metadata |
| `ob_modified_date` | DATETIME | OpenBridge metadata |
| `ob_processed_at` | STRING | OpenBridge metadata |

### Fields Only in STG_SQP_WEEKLY

| Field Name | Data Type | Purpose |
|------------|-----------|---------|
| `query_text` | STRING | Search query text (part of PK) |
| `TOTAL_IMPRESSIONS` | INT64 | Total impressions across all ASINs for the query |
| `TOTAL_CLICKS` | INT64 | Total clicks across all ASINs for the query |
| `TOTAL_CART_ADDS` | INT64 | Total cart adds across all ASINs for the query |
| `TOTAL_PURCHASES` | INT64 | Total purchases across all ASINs for the query |
| `query_rank` | INT64 | Query ranking position |
| `avg_position` | FLOAT64 | Average position for the query |

### Fields Only in STG_SCP_WEEKLY

None - all fields in SCP are also in SQP (but SCP doesn't have query-level fields).

## Data Granularity

### STG_SQP_WEEKLY
- **One row per**: Query + ASIN + Year + Week
- **Example**: 
  - Query: "wireless headphones"
  - ASIN: B0123456789
  - Year: 2025, Week: 3
  - Shows: How this specific ASIN performed for this specific query

### STG_SCP_WEEKLY
- **One row per**: ASIN + Year + Week
- **Example**:
  - ASIN: B0123456789
  - Year: 2025, Week: 3
  - Shows: How this ASIN performed across ALL queries (aggregated)

## Use Cases

### When to Use STG_SQP_WEEKLY
- ✅ Analyze which search queries drive traffic to specific ASINs
- ✅ Identify top-performing queries for a product
- ✅ Understand query-level competition (TOTAL_* fields)
- ✅ Track query ranking and position
- ✅ Query-level optimization and keyword analysis

### When to Use STG_SCP_WEEKLY
- ✅ Analyze overall ASIN performance (aggregated across all queries)
- ✅ Product-level performance metrics
- ✅ Compare ASINs without query detail
- ✅ Simpler, aggregated view of product performance

## Data Relationship

### How They Relate
- **STG_SQP_WEEKLY** = Detailed, query-level breakdown
- **STG_SCP_WEEKLY** = Aggregated summary (sum of all queries)

### Mathematical Relationship
For a given ASIN + Year + Week:
```
STG_SCP_WEEKLY.impressions ≈ SUM(STG_SQP_WEEKLY.impressions) 
  WHERE ASIN = X AND Year = Y AND Week = Z
```

**Note**: The relationship is approximate because:
- SCP may include non-search traffic
- Different data sources may have timing differences
- SQP only includes search query traffic

## Merge Behavior

### STG_SQP_WEEKLY
- **Change Detection**: ✅ Yes
- **Update Logic**: Only updates if any metric value changed
- **Efficiency**: More efficient (skips unnecessary updates)

### STG_SCP_WEEKLY
- **Change Detection**: ❌ No
- **Update Logic**: Always updates matched records
- **Efficiency**: Simpler logic, always overwrites

## Source Tables

### STG_SQP_WEEKLY Sources
1. **OpenBridge**: `openbridge-482712.DB.sp_ba_search_query_by_week_v1`
   - Fields: `cart_add_data_asin_cart_add_count`, `cart_add_data_total_cart_add_count`, etc.
2. **Historical SQP**: `onyga-482313.OI.SQP_ASIN_View_Simple_Week`
   - Fields: `Cart_Adds_ASIN_Count`, `Cart_Adds_Total_Count`, etc.

### STG_SCP_WEEKLY Sources
1. **OpenBridge**: `openbridge-482712.DB.sp_ba_search_catalog_by_week_v1`
   - Fields: `impression_data_impression_count`, `click_data_click_count`, etc.
2. **Historical SCP**: `onyga-482313.OI.SCP_ASIN_View_Week`
   - Fields: `Impressions_Impressions`, `Clicks_Clicks`, etc.

## Combining the Data

### Join Strategy
Join on `(ASIN, Year, Week)` to combine:
- SCP provides overall ASIN performance
- SQP provides query-level detail for the same ASIN

### Example Query
```sql
SELECT 
  scp.ASIN,
  scp.Year,
  scp.Week,
  scp.impressions as scp_impressions,
  scp.clicks as scp_clicks,
  sqp.query_text,
  sqp.impressions as sqp_impressions,
  sqp.clicks as sqp_clicks,
  sqp.TOTAL_IMPRESSIONS,
  sqp.TOTAL_CLICKS
FROM `onyga-482313.OI.STG_SCP_WEEKLY` scp
LEFT JOIN `onyga-482313.OI.STG_SQP_WEEKLY` sqp
  ON scp.ASIN = sqp.ASIN
  AND scp.Year = sqp.Year
  AND scp.Week = sqp.Week
WHERE scp.ASIN = 'B0123456789'
  AND scp.Year = 2025
  AND scp.Week = 3;
```

## Summary

| Feature | STG_SQP_WEEKLY | STG_SCP_WEEKLY |
|---------|----------------|----------------|
| **Granularity** | Query + ASIN | ASIN only |
| **Primary Key** | `(query_text, ASIN, Year, Week)` | `(ASIN, Year, Week)` |
| **Query Detail** | ✅ Yes | ❌ No |
| **Total Metrics** | ✅ Yes (4 fields) | ❌ No |
| **Query Ranking** | ✅ Yes | ❌ No |
| **Common Fields** | 19 fields | 19 fields |
| **Unique Fields** | 6 fields | 0 fields |
| **Total Fields** | 25 fields | 19 fields |
| **Change Detection** | ✅ Yes | ❌ No |
| **Best For** | Query-level analysis | ASIN-level analysis |
