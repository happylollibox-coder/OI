# One-Time Insert: SCP to STG_SCP_WEEKLY

## Overview

This script performs a **one-time data migration** from `SCP_ASIN_View_Week` to `STG_SCP_WEEKLY`. It maps SCP's column structure to the staging table format.

## Purpose

- Migrate existing historical data from SCP table
- Map SCP column names to OpenBridge naming convention
- Parse date strings (DD/MM/YYYY) to DATE format
- Set up staging table with both SCP and OpenBridge data

## Important Notes

⚠️ **ONE-TIME SCRIPT**: This should only be run once to migrate existing data.  
✅ **After migration**: Use `SP_MERGE_SCP_WEEKLY` for ongoing updates from OpenBridge.

## Column Mapping

### Primary Keys
- `ASIN` → `ASIN` (direct)
- `Year` → `Year` (direct)
- `Week` → `Week` (direct)
- `Reporting_Date` → `ob_date` (parsed from STRING to DATE)

### Dates
- `Start_date` (STRING DD/MM/YYYY) → `week_start_date` (DATE)
- `End_Date` (STRING DD/MM/YYYY) → `week_end_date` (DATE)
- `Reporting_Date` (STRING DD/MM/YYYY) → `ob_date` (DATE)

### Performance Metrics

| SCP Column | STG Column | Notes |
|------------|------------|-------|
| `Impressions_Impressions` | `impression_data_impression_count` | Direct mapping |
| `Impressions_Price_Median` | `impression_data_impression_median_price_amount` | Direct mapping |
| `Impressions_1D_Shipping_Speed` | `impression_data_one_day_shipping_impression_count` | Direct mapping |
| `Impressions_Same_Day_Shipping_Speed` | `impression_data_same_day_shipping_impression_count` | Direct mapping |
| `Impressions_2D_Shipping_Speed` | `impression_data_two_day_shipping_impression_count` | Direct mapping |
| `Clicks_Clicks` | `click_data_click_count` | Direct mapping |
| `Clicks_Click_Rate_CTR` | `click_data_click_rate` | Direct mapping |
| `Clicks_Price_Median` | `click_data_clicked_median_price_amount` | Direct mapping |
| `Clicks_1D_Shipping_Speed` | `click_data_one_day_shipping_click_count` | Direct mapping |
| `Clicks_Same_Day_Shipping_Speed` | `click_data_same_day_shipping_click_count` | Direct mapping |
| `Clicks_2D_Shipping_Speed` | `click_data_two_day_shipping_click_count` | Direct mapping |
| `Cart_Adds_Cart_Adds` | `cart_add_data_cart_add_count` | Direct mapping |
| `Cart_Adds_Price_Median` | `cart_add_data_cart_added_median_price_amount` | Direct mapping |
| `Cart_Adds_1D_Shipping_Speed` | `cart_add_data_one_day_shipping_cart_add_count` | Direct mapping |
| `Cart_Adds_Same_Day_Shipping_Speed` | `cart_add_data_same_day_shipping_cart_add_count` | Direct mapping |
| `Cart_Adds_2D_Shipping_Speed` | `cart_add_data_two_day_shipping_cart_add_count` | Direct mapping |
| `Purchases_Purchases` | `purchase_data_purchase_count` | Direct mapping |
| `Purchases_Conversion_Rate_Percent` | `purchase_data_conversion_rate` | Direct mapping |
| `Purchases_Price_Median` | `purchase_data_purchase_median_price_amount` | Direct mapping |
| `Purchases_Search_Traffic_Sales` | `purchase_data_search_traffic_sales_amount` | Direct mapping |
| `Purchases_1D_Shipping_Speed` | `purchase_data_one_day_shipping_purchase_count` | Direct mapping |
| `Purchases_Same_Day_Shipping_Speed` | `purchase_data_same_day_shipping_purchase_count` | Direct mapping |
| `Purchases_2D_Shipping_Speed` | `purchase_data_two_day_shipping_purchase_count` | Direct mapping |

### Fields Set to NULL (Not Available in SCP)
- All `*_currency_code` fields (not in SCP schema)
- All `ob_*` metadata fields (OpenBridge-specific)

## Usage

### Step 1: Review the Script
```bash
cat scripts/SP/ONE_TIME_INSERT_SCP_TO_STG_SCP_WEEKLY.sql
```

### Step 2: Check Source Data Count
```sql
SELECT 
  COUNT(*) as total_rows,
  COUNT(DISTINCT ASIN) as unique_asins,
  MIN(Year) as min_year,
  MAX(Year) as max_year
FROM `onyga-482313.OI.SCP_ASIN_View_Week`
WHERE ASIN IS NOT NULL;
```

### Step 3: Run the Insert
```bash
bq query --use_legacy_sql=false < scripts/SP/ONE_TIME_INSERT_SCP_TO_STG_SCP_WEEKLY.sql
```

Or run in BigQuery Console:
```sql
-- Copy and paste the INSERT statement from the script
```

### Step 4: Verify Results
The script includes verification queries that will run automatically. You can also manually check:

```sql
-- Check total rows in staging
SELECT 
  COUNT(*) as total_rows,
  COUNT(DISTINCT ASIN) as unique_asins,
  COUNTIF(ob_file_name IS NULL) as scp_rows,  -- SCP rows have NULL ob_file_name
  COUNTIF(ob_file_name IS NOT NULL) as ob_rows  -- OpenBridge rows have ob_file_name
FROM `onyga-482313.OI.STG_SCP_WEEKLY`;
```

## Safety Features

1. **Duplicate Prevention**: The script includes a `NOT EXISTS` clause to prevent inserting duplicates if re-run
2. **Data Validation**: Filters out rows with NULL key fields
3. **Date Parsing**: Uses `PARSE_DATE` to safely convert STRING dates to DATE
4. **Verification Queries**: Includes automatic verification after insert

## Expected Results

After running, you should see:
- All SCP historical data in `STG_SCP_WEEKLY`
- `ob_file_name` = NULL for all SCP rows (identifies source)
- Proper date parsing (no NULL dates)
- Year/Week matching extracted dates

## Troubleshooting

### Issue: Date parsing errors
**Solution**: Check date format in SCP table. Should be DD/MM/YYYY.

### Issue: Duplicate key errors
**Solution**: The script includes duplicate prevention. If you still get errors, check for existing data:
```sql
SELECT ASIN, Year, Week, ob_date, COUNT(*) as count
FROM `onyga-482313.OI.STG_SCP_WEEKLY`
GROUP BY ASIN, Year, Week, ob_date
HAVING count > 1;
```

### Issue: Missing data
**Solution**: Check the WHERE clause filters - ensure SCP data has all required fields populated.

## After Migration

Once the one-time insert is complete:
1. ✅ SCP historical data is in staging
2. ✅ Use `SP_MERGE_SCP_WEEKLY` for ongoing OpenBridge updates
3. ✅ Both sources will coexist in `STG_SCP_WEEKLY`
4. ✅ Identify source by checking `ob_file_name` (NULL = SCP, NOT NULL = OpenBridge)

## Related Files

- `scripts/SP/ONE_TIME_INSERT_SCP_TO_STG_SCP_WEEKLY.sql` - This script
- `scripts/Tables/scp/STG_SCP_WEEKLY.sql` - Table definition
- `scripts/SP/SP_MERGE_SCP_WEEKLY.sql` - Ongoing merge procedure
