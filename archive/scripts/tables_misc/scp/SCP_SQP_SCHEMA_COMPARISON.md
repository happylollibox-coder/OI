# SCP vs SQP Schema Comparison

## Overview
This document compares the schemas of `STG_SCP_WEEKLY` and `STG_SQP_WEEKLY` to identify common fields and differences for combining the data.

## Common Fields (Same Name & Type)

| Field Name | Data Type | Notes |
|------------|-----------|-------|
| `ASIN` | STRING | Product identifier |
| `Year` | INT64 | Year extracted from date |
| `Week` | INT64 | Week number |
| `ob_date` | DATE | Original date from source |
| `week_start_date` | DATE | Week start (Monday) |
| `week_end_date` | DATE | Week end (Sunday) |
| `ob_file_name` | STRING | OpenBridge metadata |
| `ob_marketplace_id` | STRING | OpenBridge metadata |
| `ob_seller_id` | STRING | OpenBridge metadata |
| `ob_transaction_id` | STRING | OpenBridge metadata |
| `ob_modified_date` | DATETIME | OpenBridge metadata |
| `ob_processed_at` | STRING | OpenBridge metadata |

## Fields Only in STG_SCP_WEEKLY

| Field Name | Data Type | Purpose |
|------------|-----------|---------|
| `impression_data_impression_count` | INT64 | ASIN-level impressions |
| `impression_data_impression_median_price_amount` | FLOAT64 | Median price at impression |
| `impression_data_impression_median_price_currency_code` | STRING | Currency for impression price |
| `impression_data_one_day_shipping_impression_count` | INT64 | 1-day shipping impressions |
| `impression_data_same_day_shipping_impression_count` | INT64 | Same-day shipping impressions |
| `impression_data_two_day_shipping_impression_count` | INT64 | 2-day shipping impressions |
| `click_data_click_count` | INT64 | ASIN-level clicks |
| `click_data_click_rate` | FLOAT64 | Click-through rate |
| `click_data_clicked_median_price_amount` | FLOAT64 | Median price at click |
| `click_data_clicked_median_price_currency_code` | STRING | Currency for click price |
| `click_data_one_day_shipping_click_count` | INT64 | 1-day shipping clicks |
| `click_data_same_day_shipping_click_count` | INT64 | Same-day shipping clicks |
| `click_data_two_day_shipping_click_count` | INT64 | 2-day shipping clicks |
| `cart_add_data_cart_add_count` | INT64 | ASIN-level cart adds |
| `cart_add_data_cart_added_median_price_amount` | FLOAT64 | Median price at cart add |
| `cart_add_data_cart_added_median_price_currency_code` | STRING | Currency for cart add price |
| `cart_add_data_one_day_shipping_cart_add_count` | INT64 | 1-day shipping cart adds |
| `cart_add_data_same_day_shipping_cart_add_count` | INT64 | Same-day shipping cart adds |
| `cart_add_data_two_day_shipping_cart_add_count` | INT64 | 2-day shipping cart adds |
| `purchase_data_purchase_count` | INT64 | ASIN-level purchases |
| `purchase_data_conversion_rate` | FLOAT64 | Conversion rate |
| `purchase_data_purchase_median_price_amount` | FLOAT64 | Median purchase price |
| `purchase_data_purchase_median_price_currency_code` | STRING | Currency for purchase price |
| `purchase_data_search_traffic_sales_amount` | FLOAT64 | Total sales from search traffic |
| `purchase_data_search_traffic_sales_currency_code` | STRING | Currency for search traffic sales |
| `purchase_data_one_day_shipping_purchase_count` | INT64 | 1-day shipping purchases |
| `purchase_data_same_day_shipping_purchase_count` | INT64 | Same-day shipping purchases |
| `purchase_data_two_day_shipping_purchase_count` | INT64 | 2-day shipping purchases |
| `created_at` | TIMESTAMP | Record creation timestamp |
| `updated_at` | TIMESTAMP | Record update timestamp |

## Fields Only in STG_SQP_WEEKLY

| Field Name | Data Type | Purpose |
|------------|-----------|---------|
| `query_text` | STRING | Search query text (part of primary key) |
| `impressions` | INT64 | Query+ASIN-level impressions |
| `clicks` | INT64 | Query+ASIN-level clicks |
| `click_through_rate` | FLOAT64 | CTR for query+ASIN |
| `conversions` | INT64 | Query+ASIN-level conversions |
| `conversion_rate` | FLOAT64 | Conversion rate for query+ASIN |
| `sales_amount` | FLOAT64 | Sales amount for query+ASIN |
| `sales_currency_code` | STRING | Currency for sales |
| `TOTAL_IMPRESSIONS` | INT64 | Total impressions across all ASINs for query |
| `TOTAL_CLICKS` | INT64 | Total clicks across all ASINs for query |
| `TOTAL_CART_ADDS` | INT64 | Total cart adds across all ASINs for query |
| `TOTAL_PURCHASES` | INT64 | Total purchases across all ASINs for query |
| `query_rank` | INT64 | Query ranking position |
| `avg_position` | FLOAT64 | Average position for query |

## Key Differences

### 1. Primary Key Structure
- **STG_SCP_WEEKLY**: `(ASIN, Year, Week, ob_date)` - ASIN-level aggregation
- **STG_SQP_WEEKLY**: `(query_text, ASIN, Year, Week)` - Query+ASIN-level aggregation

### 2. Granularity
- **STG_SCP_WEEKLY**: ASIN-level metrics (no query detail)
- **STG_SQP_WEEKLY**: Query+ASIN-level metrics (includes query text)

### 3. Field Naming Convention
- **STG_SCP_WEEKLY**: Uses `impression_data_*`, `click_data_*`, `cart_add_data_*`, `purchase_data_*` prefixes
- **STG_SQP_WEEKLY**: Uses simpler names: `impressions`, `clicks`, `conversions`, `sales_amount`

### 4. Shipping Speed Breakdown
- **STG_SCP_WEEKLY**: Has detailed shipping speed breakdowns (1-day, same-day, 2-day) for impressions, clicks, cart adds, and purchases
- **STG_SQP_WEEKLY**: No shipping speed breakdowns

### 5. Price Information
- **STG_SCP_WEEKLY**: Has median price fields at each stage (impression, click, cart add, purchase)
- **STG_SQP_WEEKLY**: Only has `sales_amount` and `sales_currency_code`

### 6. Total Metrics
- **STG_SCP_WEEKLY**: No total metrics (only ASIN-level)
- **STG_SQP_WEEKLY**: Has `TOTAL_IMPRESSIONS`, `TOTAL_CLICKS`, `TOTAL_CART_ADDS`, `TOTAL_PURCHASES` (aggregated across all ASINs for a query)

### 7. Query-Specific Fields
- **STG_SCP_WEEKLY**: No query-specific fields
- **STG_SQP_WEEKLY**: Has `query_text`, `query_rank`, `avg_position`

### 8. Audit Fields
- **STG_SCP_WEEKLY**: Has `created_at` and `updated_at`
- **STG_SQP_WEEKLY**: No audit fields

## Compatibility Analysis

### ✅ Compatible Fields (Can be directly joined/combined)
- `ASIN`, `Year`, `Week`, `ob_date`, `week_start_date`, `week_end_date`
- All OpenBridge metadata fields (`ob_*`)

### ⚠️ Similar Fields (Different names, similar purpose)
- `impression_data_impression_count` (SCP) vs `impressions` (SQP)
- `click_data_click_count` (SCP) vs `clicks` (SQP)
- `purchase_data_purchase_count` (SCP) vs `conversions` (SQP)
- `purchase_data_search_traffic_sales_amount` (SCP) vs `sales_amount` (SQP)

### ❌ Unique Fields (Only in one table)
- SCP: All shipping speed breakdowns, median price fields, audit fields
- SQP: Query text, total metrics, query rank, avg position

## Recommendations for Combining

### Option 1: UNION ALL (Different granularities)
**Not recommended** - Different primary keys and granularities make UNION ALL problematic.

### Option 2: JOIN on ASIN + Year + Week
**Recommended** - Join SCP and SQP on `ASIN`, `Year`, `Week` to combine:
- SCP provides ASIN-level aggregated metrics
- SQP provides query-level detail for the same ASIN

### Option 3: Create Unified View
**Recommended** - Create a view that:
- Uses SCP as base (ASIN-level)
- LEFT JOINs SQP to add query-level detail
- Maps similar fields with consistent naming

### Option 4: Create New Combined Table
**Consider** - Create `FACT_SEARCH_PERFORMANCE_WEEKLY` that:
- Combines both granularities
- Uses consistent field naming
- Includes all fields from both tables

## Field Mapping for Combination

| SCP Field | SQP Equivalent | Notes |
|-----------|----------------|-------|
| `impression_data_impression_count` | `impressions` | Similar but SQP is query-specific |
| `click_data_click_count` | `clicks` | Similar but SQP is query-specific |
| `click_data_click_rate` | `click_through_rate` | Same concept, different names |
| `purchase_data_purchase_count` | `conversions` | Same concept, different names |
| `purchase_data_conversion_rate` | `conversion_rate` | Same concept |
| `purchase_data_search_traffic_sales_amount` | `sales_amount` | Similar but SQP is query-specific |

## Next Steps

1. **Decide on combination approach**: JOIN, UNION, or new table
2. **Standardize field names**: Choose naming convention for combined structure
3. **Handle NULLs**: SCP won't have query_text, SQP won't have shipping breakdowns
4. **Create mapping logic**: How to aggregate SQP query-level data to ASIN-level if needed
