# ASIN Tables Exploration Guide

## Overview

This document provides information about the two ASIN performance tables in the OI BigQuery dataset:

1. **SQP_ASIN_View_Simple_Week** - Search Query Performance (SKU-level, query-level weekly data)
2. **SCP_ASIN_View_Week** - Search Catalog Performance (ASIN-level weekly aggregated data)

## Table 1: SQP_ASIN_View_Simple_Week

### Purpose
Weekly ASIN performance data at the **Search Query** level, showing how specific products (SKUs) perform for individual search queries.

### Key Characteristics
- **Granularity**: SKU + Search Query + Week
- **Data Level**: Detailed query-level performance metrics
- **Focus**: Search query performance analysis

### Key Columns (based on CSV sample)
- **Identifiers**: 
  - `SKU` - Product SKU identifier
  - `Search_Query` - The actual search query term
  - `Year`, `Week` - Time dimensions
  - `Week_Start_date`, `Week_End_date` - Week boundaries
  - `Reporting_Date` - Data reporting timestamp

- **Performance Metrics**:
  - **Impressions**: `Impressions_Total_Count`, `Impressions_ASIN_Count`, `Impressions_ASIN_Share_%`
  - **Clicks**: `Clicks_Total_Count`, `Clicks_Click_Rate_%`, `Clicks_ASIN_Count`, `Clicks_ASIN_Share_%`, `Clicks_Price_Median`
  - **Cart Adds**: `Cart_Adds_Total_Count`, `Cart_Adds_Cart_Add_Rate_%`, `Cart_Adds_ASIN_Count`, `Cart_Adds_ASIN_Share_%`
  - **Purchases**: `Purchases_Total_Count`, `Purchases_Purchase_Rate_%`, `Purchases_ASIN_Count`, `Purchases_ASIN_Share_%`
  - **Search Query Metadata**: `Search_Query_Score`, `Search_Query_Volume`

- **Shipping Speed Breakdowns**: For each metric (Clicks, Cart Adds, Purchases), there are separate counts for:
  - Same Day Shipping
  - 1 Day Shipping
  - 2 Day Shipping

### Use Cases
- Identify which search queries drive purchases for specific SKUs
- Analyze search query performance and conversion rates
- Optimize search query targeting and SEO
- Understand search query volume vs. performance

## Table 2: SCP_ASIN_View_Week

### Purpose
Weekly ASIN performance data aggregated at the **ASIN level**, providing overall product performance metrics without query-level detail.

### Key Characteristics
- **Granularity**: ASIN + Week
- **Data Level**: Aggregated ASIN-level metrics
- **Focus**: Overall product performance analysis

### Key Columns (based on schema.json)
- **Identifiers**:
  - `ASIN` - Amazon Standard Identification Number
  - `ASIN_Title` - Product title
  - `Category` - Product category
  - `Year`, `Week` - Time dimensions
  - `Start_date`, `End_Date` - Week boundaries
  - `Reporting_Date` - Data reporting timestamp

- **Performance Metrics**:
  - **Impressions**: `Impressions_Impressions`, `Impressions_Rating_Median`, `Impressions_Price_Median`
  - **Clicks**: `Clicks_Clicks`, `Clicks_Click_Rate_CTR`, `Clicks_Price_Median`
  - **Cart Adds**: `Cart_Adds_Cart_Adds`, `Cart_Adds_Price_Median`
  - **Purchases**: `Purchases_Purchases`, `Purchases_Search_Traffic_Sales`, `Purchases_Conversion_Rate_Percent`, `Purchases_Rating_Median`, `Purchases_Price_Median`

- **Shipping Speed Breakdowns**: For each metric (Impressions, Clicks, Cart Adds, Purchases):
  - Same Day Shipping Speed
  - 1D Shipping Speed
  - 2D Shipping Speed

### Use Cases
- Overall ASIN performance tracking
- Product-level performance analysis
- Category-level performance comparison
- High-level product portfolio analysis

## Key Differences

| Aspect | SQP_ASIN_View_Simple_Week | SCP_ASIN_View_Week |
|--------|--------------------------|-------------------|
| **Granularity** | SKU + Search Query + Week | ASIN + Week |
| **Query Detail** | ✅ Individual search queries | ❌ Aggregated |
| **Product ID** | SKU | ASIN |
| **Use Case** | Query-level optimization | Product-level analysis |
| **Data Volume** | Higher (more granular) | Lower (aggregated) |

## Exploration Queries

Run the SQL script `explore_asin_tables.sql` to:

1. **View Table Schemas** - Understand the exact column structure
2. **Get Data Volumes** - Row counts, unique values, date ranges
3. **Sample Data** - See actual data rows
4. **Summary Statistics** - Weekly aggregates, top performers
5. **Data Quality Checks** - Missing values, data completeness
6. **Table Comparison** - Compare date ranges and coverage

## Running the Exploration Script

```sql
-- Run individual queries from explore_asin_tables.sql in BigQuery console
-- Project: onyga-482313
-- Dataset: OI
```

## Notes

- Both tables use date formats like `'27/12/2025'` (DD/MM/YYYY), so parsing is required: `PARSE_DATE('%d/%m/%Y', Reporting_Date)`
- SQP table focuses on search query performance for SKUs
- SCP table provides aggregated ASIN-level metrics
- Both tables include shipping speed breakdowns for performance analysis
