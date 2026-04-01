# OI Database Project

A comprehensive BigQuery database project for Amazon Ads and Seller data integration and analysis.

## Project Overview

This project manages the OI (Operations Intelligence) database in Google BigQuery project `onyga-482313`. It provides unified views and interfaces for Amazon advertising and selling partner data, integrating multiple data sources through Fivetran.

## Architecture

### BigQuery Project Structure
- **Project ID**: `onyga-482313`
- **Dataset**: `OI`
- **Data Sources**: `fivetran-hl` (Fivetran-managed data)

### Data Flow
```
Amazon Ads/Selling Partner APIs → Fivetran → BigQuery (fivetran-hl) → OI Views → Analytics
```

## Database Objects

### Interface Views (Main Scripts)
All views are located in `scripts/bigquery/interface_views/` and deployed to `onyga-482313.OI`:

1. **V_SRC_AmazonAds_campaign_history** - Campaign performance history with temporal versioning
2. **V_SRC_AmazonAds_keyword** - Keyword targeting data consolidation
3. **V_SRC_AmazonAds_negative_keyword** - Negative keyword management
4. **V_SRC_AmazonAds_purchased_product** - Product purchase attribution reports
5. **V_SRC_AmazonAds_SearchTerms** - Search term performance analysis (most complex)
6. **V_SRC_Seller_repeat_purchase** - Repeat purchase behavior analysis
7. **NewView1** - Test view

### Tables
- **SQP_ASIN_View_Simple_Week** - ASIN performance data

## Directory Structure

```
├── README.md                    # Project documentation
├── scripts/
│   ├── bigquery/               # All BigQuery objects (synced with BQ)
│   │   ├── procedures/        # Stored procedures
│   │   ├── tables/            # Table definitions (DIM, FACT, STG, SRC)
│   │   ├── views/             # Views
│   │   ├── functions/          # BigQuery functions
│   │   ├── interface_views/   # Interface views (Fivetran sources)
│   │   ├── runner/             # Scripts that run procedures
│   │   └── tests/             # Object-specific tests
├── Data/
│   └── amazon data/
│       ├── Manual/             # Manual data files
│       ├── Reports/            # Generated reports
│       └── src/                # Source data
└── deployment/                 # Deployment scripts
```

## Key Features

### Data Integration
- **Multi-source consolidation**: Combines data from sponsored products, brands, and display campaigns
- **Temporal versioning**: Campaign history with start/end date ranges
- **Unified schema**: Consistent field naming across different data sources

### Business Logic
- **Search term analysis**: Links search terms to keywords and campaigns
- **Purchase attribution**: Tracks product purchases back to advertising campaigns
- **Performance metrics**: Unified cost, clicks, impressions, and conversion data

## Usage

### Prerequisites
- Google Cloud Platform access
- BigQuery permissions for project `onyga-482313`
- Fivetran data pipeline access

### Deployment
```bash
# Authenticate with GCP
gcloud auth login
gcloud config set project onyga-482313

# Deploy views
bq query --use_legacy_sql=false < scripts/bigquery/interface_views/V_SRC_AmazonAds_campaign_history.sql
```

### Query Examples
```sql
-- Get campaign performance
SELECT * FROM `onyga-482313.OI.V_SRC_AmazonAds_campaign_history`
WHERE OI_start_date >= '2024-01-01';

-- Analyze search term effectiveness
SELECT campaign_name, search_term, SUM(cost) total_cost, SUM(sales) total_sales
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
WHERE date >= '2024-01-01'
GROUP BY campaign_name, search_term
ORDER BY total_sales DESC;
```

## Data Sources

### Primary Sources (fivetran-hl project)
- **amazon_ads**: Sponsored products, brands, and display campaign data
- **amazon_selling_partner**: Seller performance and sales data

### View Dependencies
Most interface views depend on source tables in the `fivetran-hl` project and perform complex transformations including:
- UNION operations across multiple tables
- Date range calculations
- Data type casting and standardization
- Filtering and aggregation

## Maintenance

### Update Process
1. Fivetran automatically updates source tables
2. Views automatically reflect new data (no manual refresh needed)
3. Monitor data freshness using `_fivetran_synced` timestamps

### Monitoring Queries
```sql
-- Check data freshness
SELECT table_name, MAX(_fivetran_synced) last_sync
FROM `onyga-482313.OI.INFORMATION_SCHEMA.TABLES`
GROUP BY table_name;
```

## Development

### Adding New Views
1. Create SQL file in `scripts/bigquery/interface_views/`
2. Test locally using BigQuery sandbox
3. Deploy to production dataset
4. Update this README

### Best Practices
- Use standard SQL (not legacy)
- Include proper error handling
- Document complex business logic
- Test with sample data before deployment

## Contact

For questions about this database project, refer to the Admin.sql file for detailed queries and examples.
