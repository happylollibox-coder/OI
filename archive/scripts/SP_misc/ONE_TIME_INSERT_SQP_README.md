# One-Time Insert: SQP to STG_SQP_WEEKLY

## Overview

This script performs a **one-time data migration** from `SQP_ASIN_View_Simple_Week` to `STG_SQP_WEEKLY`. It maps SQP's column structure to the staging table format.

## Purpose

- Migrate existing historical data from SQP table
- Prepare staging table for ongoing updates from OpenBridge
- Map SQP metrics to STG_SQP_WEEKLY structure

## Important Notes

⚠️ **This is a ONE-TIME script. Run only once to migrate existing data.**  
✅ **After migration**: Use `SP_MERGE_SQP_WEEKLY` for ongoing updates from OpenBridge.

## Column Mapping

### Primary Key Dimensions
| SQP Column | STG_SQP_WEEKLY Column | Notes |
|------------|----------------------|-------|
| `Search_Query` | `query_text` | Direct mapping |
| `ASIN` | `ASIN` | Direct mapping |
| `Year` | `Year` | Direct mapping |
| `Week` | `Week` | Direct mapping |
| `Week_Start_date` | `ob_date`, `week_start_date` | Parsed from '%d/%m/%Y' format |
| `Week_End_date` | `week_end_date` | Parsed from '%d/%m/%Y' format |

### Performance Metrics
| SQP Column | STG_SQP_WEEKLY Column | Notes |
|------------|----------------------|-------|
| `Impressions_ASIN_Count` | `impressions` | Your product's impressions |
| `Clicks_ASIN_Count` | `clicks` | Your product's clicks |
| Calculated | `click_through_rate` | (Clicks / Impressions) * 100 |
| `Purchases_ASIN_Count` | `conversions` | Your product's purchases |
| Calculated | `conversion_rate` | (Purchases / Clicks) * 100 |
| N/A | `sales_amount` | NULL (not available in SQP) |
| N/A | `sales_currency_code` | NULL (not available in SQP) |
| N/A | `query_rank` | NULL (not available in SQP) |
| N/A | `avg_position` | NULL (not available in SQP) |

### Metadata
All OpenBridge metadata fields are set to NULL for SQP data:
- `ob_file_name` → NULL
- `ob_marketplace_id` → NULL
- `ob_seller_id` → NULL
- `ob_transaction_id` → NULL
- `ob_modified_date` → NULL
- `ob_processed_at` → NULL

## Usage

### 1. Review the Script

```bash
cat scripts/SP/ONE_TIME_INSERT_SQP_TO_STG_SQP_WEEKLY.sql
```

### 2. Run the Insert

```bash
bq query --use_legacy_sql=false < scripts/SP/ONE_TIME_INSERT_SQP_TO_STG_SQP_WEEKLY.sql
```

Or run directly in BigQuery Console.

### 3. Verify the Results

The script includes verification queries that will show:
- Total rows inserted
- Unique queries, ASINs, years
- Date range covered
- Data quality checks
- Sample of inserted data
- Comparison of source vs target counts

## Expected Results

After running:
- ✅ All SQP historical data in `STG_SQP_WEEKLY`
- ✅ Proper date parsing from SQP format
- ✅ Calculated metrics (CTR, conversion rate)
- ✅ Ready for ongoing OpenBridge updates

## Next Steps

1. ✅ SQP historical data is in staging
2. ✅ Use `SP_MERGE_SQP_WEEKLY` for ongoing OpenBridge updates
3. ✅ Both sources will coexist in `STG_SQP_WEEKLY` (distinguished by ob_file_name IS NULL for SQP data)

## Related Files

- `scripts/SP/ONE_TIME_INSERT_SQP_TO_STG_SQP_WEEKLY.sql` - This script
- `scripts/Tables/scp/STG_SQP_WEEKLY.sql` - Table definition
- `scripts/SP/SP_MERGE_SQP_WEEKLY.sql` - Ongoing merge procedure

## Notes

- The script uses **ASIN-specific metrics** (your product's performance) as the primary metrics
- Market-wide metrics (Total_Count columns) are not migrated to keep the staging table focused
- Date parsing assumes '%d/%m/%Y' format for Week_Start_date and Week_End_date
- The script excludes records that already exist (safe to re-run)
