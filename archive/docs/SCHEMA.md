# Database Schema Documentation

## Overview

This document describes the schema for the OI (Operations Intelligence) dataset in BigQuery project `onyga-482313`. The dataset provides unified views for Amazon Ads and Seller data integration.

## Dataset Information

- **Project**: `onyga-482313`
- **Dataset**: `OI`
- **Location**: US
- **Last Modified**: 25 Dec 15:18:23

## Interface Views

### 1. V_SRC_AmazonAds_campaign_history

**Purpose**: Campaign performance history with temporal versioning for tracking campaign changes over time.

**Source Tables**:
- `fivetran-hl.amazon_ads.campaign_history` (Sponsored Products)
- `fivetran-hl.amazon_ads.sb_campaign_history` (Sponsored Brands)

**Key Fields**:
- `campaign_id` (STRING): Unique campaign identifier
- `last_update_date` (TIMESTAMP): When campaign was last modified
- `serving_status` (STRING): Current serving status
- `campaign_name` (STRING): Human-readable campaign name
- `budget` (FLOAT): Campaign budget
- `portfolio_id` (STRING): Portfolio grouping
- `OI_start_date` (TIMESTAMP): Start of validity period
- `OI_end_date` (TIMESTAMP): End of validity period

**Business Logic**:
- Uses window functions to create temporal validity ranges
- UNIONs data from SP and SB campaigns
- Handles historical changes with start/end date ranges

### 2. V_SRC_AmazonAds_keyword

**Purpose**: Unified keyword targeting data across sponsored products and brands.

**Source Tables**:
- `fivetran-hl.amazon_ads.keyword_history` (SP keywords)
- `fivetran-hl.amazon_ads.sb_keyword` (SB keywords)

**Key Fields**:
- `keyword_id` (STRING): Unique keyword identifier
- `ad_group_id` (STRING): Parent ad group
- `campaign_id` (STRING): Parent campaign
- `keyword_text` (STRING): The actual keyword
- `match_type` (STRING): Broad, phrase, or exact match
- `state` (STRING): Keyword status (enabled/disabled)
- `bid` (FLOAT): Keyword bid amount

### 3. V_SRC_AmazonAds_negative_keyword

**Purpose**: Negative keyword management to prevent unwanted impressions.

**Source Tables**:
- `fivetran-hl.amazon_ads.negative_keyword_history` (SP negative keywords)
- `fivetran-hl.amazon_ads.sb_negative_keyword` (SB negative keywords)

**Key Fields**:
- `negative_id` (STRING): Unique negative keyword identifier
- `campaign_id` (STRING): Associated campaign
- `ad_group_id` (STRING): Associated ad group
- `keyword_text` (STRING): Negative keyword text
- `match_type` (STRING): Match type for negative targeting
- `state` (STRING): Status (enabled/disabled)

**Filters Applied**:
- SP: `serving_status='TARGETING_CLAUSE_STATUS_LIVE' AND state='ENABLED'`
- SB: `state='enabled' AND _fivetran_deleted=false`

### 4. V_SRC_AmazonAds_purchased_product

**Purpose**: Product purchase attribution tracking across different campaign types.

**Source Tables**:
- `fivetran-hl.amazon_ads.purchased_product_targeting_report` (Targeting campaigns)
- `fivetran-hl.amazon_ads.purchased_product_keyword_report` (Keyword campaigns)
- `fivetran-hl.amazon_ads.sb_purchased_product` (Sponsored Brands)

**Key Fields**:
- `campaign_id` (STRING): Campaign identifier
- `ad_group_id` (STRING): Ad group identifier
- `keyword_id` (STRING): Keyword identifier (null for auto campaigns)
- `date` (DATE): Report date
- `purchased_asin` (STRING): Purchased product ASIN
- `orders` (INTEGER): Number of orders
- `units` (INTEGER): Units sold
- `sales` (FLOAT): Sales amount

### 5. V_SRC_AmazonAds_SearchTerms

**Purpose**: Search term performance analysis with campaign and keyword context. (Most complex view)

**Source Tables**:
- `fivetran-hl.amazon_ads.search_term_ad_keyword_report` (SP keyword reports)
- `fivetran-hl.amazon_ads.search_term_targeting_report` (SP targeting reports)
- `fivetran-hl.amazon_ads.sb_search_term_report` (SB search terms)
- `fivetran-hl.amazon_ads.sb_target_report` (SB targeting)

**Key Fields**:
- `date` (DATE): Report date
- `campaign_id` (STRING): Campaign identifier
- `ad_group_id` (STRING): Ad group identifier
- `keyword_id` (STRING): Keyword identifier
- `search_term` (STRING): Actual search term used
- `campaign_name` (STRING): Joined campaign name
- `clicks` (INTEGER): Clicks received
- `impressions` (INTEGER): Impressions served
- `cost` (FLOAT): Advertising cost
- `orders` (INTEGER): Attributed orders
- `sales` (FLOAT): Attributed sales
- `source_table` (STRING): Data source identifier

**Joins Applied**:
- Campaign history view for campaign names
- Keyword view for keyword text and status

**Filters Applied**:
- `date >= '2025-10-28'`
- `cost <> 0` (for SB target reports)

### 6. V_SRC_Seller_repeat_purchase

**Purpose**: Repeat purchase behavior analysis for seller performance.

**Source Table**:
- `fivetran-hl.amazon_selling_partner.repeat_purchase_report_monthly`

**Key Fields**: All fields from source table
- Filtered to exclude null orders: `WHERE orders IS NOT NULL`

### 7. NewView1

**Purpose**: Test view for development and testing.

**Content**: `SELECT 2 as A`

### 8. V_SRC_Products

**Purpose**: Standardized product data from Fivetran item_summary table for product dimension population.

**Source Table**:
- `fivetran-hl.amazon_selling_partner.item_summary` (CATALOG module)

**Key Fields**:
- `asin` (STRING): Amazon Standard Identification Number (optional)
- `sku` (STRING): Merchant SKU
- `marketplace` (STRING): Marketplace identifier
- `product_name` (STRING): Product name/title
- `brand` (STRING): Product brand
- `manufacturer` (STRING): Manufacturer name
- `product_type` (STRING): Product type/category
- `launch_date` (DATE): Product launch date
- `_fivetran_synced` (TIMESTAMP): Data freshness tracking

**Filters Applied**:
- `_fivetran_deleted = false` (active products only)

## Tables

### SQP_ASIN_View_Simple_Week

**Purpose**: Weekly ASIN performance data.

**Note**: This appears to be a data table rather than a view. Schema details would need to be queried from BigQuery INFORMATION_SCHEMA.

### DIM_PRODUCT

**Purpose**: Product dimension table for active products with ASIN as optional identifier.

**Source**: Populated from `V_SRC_Products` via `SP_MERGE_PRODUCT_DIM` stored procedure.

**Key Fields**:
- `product_id` (INT64): Auto-generated unique identifier (primary key)
- `asin` (STRING, nullable): Amazon Standard Identification Number (optional for new products)
- `sku` (STRING, nullable): Merchant SKU
- `marketplace` (STRING, nullable): Marketplace identifier
- `product_name` (STRING, nullable): Product name
- `brand` (STRING, nullable): Product brand
- `manufacturer` (STRING, nullable): Manufacturer name
- `product_type` (STRING, nullable): Product type/category
- `launch_date` (DATE, nullable): Product launch date
- `is_active` (BOOLEAN): Product status (derived from `_fivetran_deleted = false`)
- `_fivetran_synced` (TIMESTAMP): Data freshness tracking
- `cost_of_goods` (FLOAT64, nullable): Cost of goods
- `shipping_cost` (FLOAT64, nullable): Shipping cost
- `fba_cost` (FLOAT64, nullable): Fulfillment by Amazon cost
- `manufacture_day` (INT64, nullable): Manufacturing day
- `shipment_days` (INT64, nullable): Shipment days
- `created_at` (TIMESTAMP): Record creation timestamp
- `updated_at` (TIMESTAMP): Record last update timestamp

**Business Logic**:
- Products identified by ASIN when available, or by SKU + marketplace for new products
- Upsert-only: Products are merged from Fivetran, never deleted
- Auto-generated `product_id` ensures uniqueness even when ASIN is null
- Cost and logistics fields (`cost_of_goods`, `shipping_cost`, `fba_cost`, `manufacture_day`, `shipment_days`) are preserved during MERGE updates and populated separately

**Population**:
- Populated via `SP_MERGE_PRODUCT_DIM` stored procedure
- Source: `V_SRC_Products` view (from `fivetran-hl.amazon_selling_partner.item_summary`)
- Only active products (`_fivetran_deleted = false`) are included
- **Automated Updates**: Use `SP_MERGE_PRODUCT_DIM_SMART` with a scheduled query to run when source table changes
- See `SETUP_PRODUCT_DIM_SCHEDULE.md` for scheduling instructions

## Data Relationships

```
Campaigns (V_SRC_AmazonAds_campaign_history)
├── Ad Groups (contained within campaign data)
│   ├── Keywords (V_SRC_AmazonAds_keyword)
│   │   ├── Search Terms (V_SRC_AmazonAds_SearchTerms)
│   │   └── Purchased Products (V_SRC_AmazonAds_purchased_product)
│   │       └── Products (DIM_PRODUCT) [via ASIN]
│   └── Negative Keywords (V_SRC_AmazonAds_negative_keyword)
├── Seller Data (V_SRC_Seller_repeat_purchase)
└── Products (DIM_PRODUCT)
    └── Source: V_SRC_Products (from fivetran-hl.amazon_selling_partner.item_summary)
```

## Data Freshness

All views include `_fivetran_synced` timestamps to track data freshness. Source data is automatically updated by Fivetran pipelines.

## Schema Version

- **Version**: 1.0
- **Last Updated**: 2025-01-01
- **BigQuery Project**: onyga-482313
- **Dataset**: OI
