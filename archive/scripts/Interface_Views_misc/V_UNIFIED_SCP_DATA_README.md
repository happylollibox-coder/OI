# V_UNIFIED_SCP_DATA View

## Overview

This view combines data from two sources into a unified schema:
- **SCP Source**: `onyga-482313.OI.SCP_ASIN_View_Week`
- **OpenBridge Source**: `openbridge-482712.DB.sp_ba_search_catalog_by_week_v1`

## Purpose

Provides a single unified view of ASIN performance data from both sources, with:
- Common schema across both sources
- Year/Week dimensions extracted from OpenBridge dates
- Column mapping to match SCP naming conventions
- Source identification for traceability

## Schema

### Key Dimensions
- `source_system`: 'SCP' or 'OpenBridge' - identifies data source
- `Year`: INTEGER - Year (extracted from ob_date for OpenBridge)
- `Week`: INTEGER - Week number (extracted from ob_date for OpenBridge)
- `ASIN`: STRING - Amazon Standard Identification Number
- `start_date`: DATE - Week start date (calculated for OpenBridge)
- `end_date`: DATE - Week end date (calculated for OpenBridge)
- `reporting_date`: DATE - Date of the report

### Product Information
- `ASIN_Title`: STRING - Product title (SCP only)
- `Category`: STRING - Product category (SCP only)

### Performance Metrics

#### Impressions
- `Impressions_Impressions`: Total impressions
- `Impressions_Rating_Median`: Median rating (SCP only)
- `Impressions_Price_Median`: Median price at impression
- `Impressions_Same_Day_Shipping_Speed`: Same-day shipping impressions
- `Impressions_1D_Shipping_Speed`: One-day shipping impressions
- `Impressions_2D_Shipping_Speed`: Two-day shipping impressions

#### Clicks
- `Clicks_Clicks`: Total clicks
- `Clicks_Click_Rate_CTR`: Click-through rate
- `Clicks_Price_Median`: Median price at click
- `Clicks_Same_Day_Shipping_Speed`: Same-day shipping clicks
- `Clicks_1D_Shipping_Speed`: One-day shipping clicks
- `Clicks_2D_Shipping_Speed`: Two-day shipping clicks

#### Cart Adds
- `Cart_Adds_Cart_Adds`: Total cart adds
- `Cart_Adds_Price_Median`: Median price at cart add
- `Cart_Adds_Same_Day_Shipping_Speed`: Same-day shipping cart adds
- `Cart_Adds_1D_Shipping_Speed`: One-day shipping cart adds
- `Cart_Adds_2D_Shipping_Speed`: Two-day shipping cart adds

#### Purchases
- `Purchases_Purchases`: Total purchases
- `Purchases_Search_Traffic_Sales`: Search traffic sales amount
- `Purchases_Conversion_Rate_Percent`: Conversion rate percentage
- `Purchases_Rating_Median`: Median rating (SCP only)
- `Purchases_Price_Median`: Median price at purchase
- `Purchases_Same_Day_Shipping_Speed`: Same-day shipping purchases
- `Purchases_1D_Shipping_Speed`: One-day shipping purchases
- `Purchases_2D_Shipping_Speed`: Two-day shipping purchases

### Metadata Fields
- `start_date_raw`: Original start_date string (SCP only)
- `end_date_raw`: Original end_date string (SCP only)
- `reporting_date_raw`: Original reporting_date string (SCP only)
- `ob_file_name`: OpenBridge file name (OpenBridge only)
- `ob_marketplace_id`: Marketplace ID (OpenBridge only)
- `ob_seller_id`: Seller ID (OpenBridge only)
- `ob_transaction_id`: Transaction ID (OpenBridge only)
- `ob_modified_date`: Modified date (OpenBridge only)
- `ob_processed_at`: Processing timestamp (OpenBridge only)

## Column Mapping

### SCP → Unified
- Direct mapping (same column names)
- Date parsing: `PARSE_DATE('%d/%m/%Y', Start_date)` → `start_date`

### OpenBridge → Unified
- `ob_date` → Extract Year/Week, calculate start_date/end_date
- `click_data_click_count` → `Clicks_Clicks`
- `purchase_data_purchase_count` → `Purchases_Purchases`
- `impression_data_impression_count` → `Impressions_Impressions`
- `cart_add_data_cart_add_count` → `Cart_Adds_Cart_Adds`
- Similar mappings for all performance metrics

## Usage Examples

### Example 1: Compare data volumes by source
```sql
SELECT 
  source_system,
  COUNT(*) as row_count,
  COUNT(DISTINCT ASIN) as unique_asins,
  MIN(reporting_date) as earliest_date,
  MAX(reporting_date) as latest_date
FROM `onyga-482313.OI.V_UNIFIED_SCP_DATA`
GROUP BY source_system;
```

### Example 2: Get combined performance metrics
```sql
SELECT 
  Year,
  Week,
  ASIN,
  SUM(Impressions_Impressions) as total_impressions,
  SUM(Clicks_Clicks) as total_clicks,
  SUM(Purchases_Purchases) as total_purchases,
  ROUND(SAFE_DIVIDE(SUM(Clicks_Clicks), SUM(Impressions_Impressions)) * 100, 2) as ctr_pct,
  ROUND(SAFE_DIVIDE(SUM(Purchases_Purchases), SUM(Clicks_Clicks)) * 100, 2) as conversion_pct
FROM `onyga-482313.OI.V_UNIFIED_SCP_DATA`
WHERE ASIN IS NOT NULL
GROUP BY Year, Week, ASIN
ORDER BY Year DESC, Week DESC, total_purchases DESC;
```

### Example 3: Find ASINs in both sources
```sql
SELECT 
  ASIN,
  COUNT(DISTINCT source_system) as source_count,
  SUM(CASE WHEN source_system = 'SCP' THEN Purchases_Purchases ELSE 0 END) as scp_purchases,
  SUM(CASE WHEN source_system = 'OpenBridge' THEN Purchases_Purchases ELSE 0 END) as ob_purchases
FROM `onyga-482313.OI.V_UNIFIED_SCP_DATA`
WHERE ASIN IS NOT NULL
GROUP BY ASIN
HAVING source_count = 2
ORDER BY (scp_purchases + ob_purchases) DESC;
```

### Example 4: Weekly aggregated performance
```sql
SELECT 
  Year,
  Week,
  start_date,
  COUNT(DISTINCT ASIN) as asin_count,
  SUM(Impressions_Impressions) as total_impressions,
  SUM(Clicks_Clicks) as total_clicks,
  SUM(Purchases_Purchases) as total_purchases,
  SUM(Purchases_Search_Traffic_Sales) as total_sales
FROM `onyga-482313.OI.V_UNIFIED_SCP_DATA`
GROUP BY Year, Week, start_date
ORDER BY Year DESC, Week DESC;
```

## Notes

1. **Week Calculation**: OpenBridge weeks are calculated using `DATE_TRUNC(ob_date, WEEK(MONDAY))` - weeks start on Monday
2. **Missing Data**: Some fields are NULL for one source (e.g., ASIN_Title only in SCP)
3. **Date Formats**: SCP dates are parsed from DD/MM/YYYY strings, OpenBridge uses DATE type
4. **Currency**: Price amounts may have different currency codes (check `ob_*_currency_code` fields if needed)
5. **Data Quality**: Always filter `WHERE ASIN IS NOT NULL` when analyzing by ASIN

## Deployment

To create/update the view:
```bash
bq query --use_legacy_sql=false < scripts/Interface\ Views/V_UNIFIED_SCP_DATA.sql
```

Or run the SQL directly in BigQuery Console.

## Related Files

- `V_UNIFIED_SCP_DATA.sql` - View definition
- `MERGE_FEASIBILITY_RESULTS.md` - Analysis that led to this view
- `check_merge_feasibility.sql` - Queries used for analysis
