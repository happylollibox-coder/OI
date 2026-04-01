# Setup PRODUCT_DIM Scheduled Updates

This guide explains how to schedule `SP_MERGE_PRODUCT_DIM` to run automatically when the source table (`item_summary`) changes.

## Overview

Since BigQuery doesn't have native "on table change" triggers, we use a **smart scheduled query** approach:
- A scheduled query runs periodically (e.g., every hour)
- A smart wrapper procedure checks if the source table has changed
- Only runs the MERGE if new/updated records are detected

## Components

1. **`SP_MERGE_PRODUCT_DIM`** - The main merge procedure (upsert-only)
2. **`SP_MERGE_PRODUCT_DIM_SMART`** - Smart wrapper that checks for changes before running merge
3. **Scheduled Query** - Runs the smart procedure on a schedule

## Setup Steps

### Option 1: Via BigQuery Console (Recommended)

1. **Go to BigQuery Console:**
   - https://console.cloud.google.com/bigquery?project=onyga-482313

2. **Click "Scheduled queries" in the left menu**

3. **Click "Create scheduled query"**

4. **Configure the query:**
   - **Name**: `PRODUCT_DIM Auto Update`
   - **Schedule**: 
     - `Every 1 hour` (for frequent Fivetran syncs)
     - `Every 6 hours` (for regular syncs)
     - `Every day at 06:00` (for daily syncs)
   - **Query:**
     ```sql
     CALL `onyga-482313.OI.SP_MERGE_PRODUCT_DIM_SMART`();
     ```
   - **Destination**: Leave empty (stored procedure handles the insert)
   - **Region**: `US` (multi-region)
   - **Timezone**: `America/New_York` (or your preferred timezone)

5. **Click "Save"**

### Option 2: Via gcloud CLI

```bash
bq query \
  --use_legacy_sql=false \
  --schedule="every 1 hours" \
  --display_name="PRODUCT_DIM Auto Update" \
  --description="Automatically updates PRODUCT_DIM when item_summary table changes" \
  --location=US \
  "CALL \`onyga-482313.OI.SP_MERGE_PRODUCT_DIM_SMART\`();"
```

### Option 3: Via bq command with schedule

```bash
bq mk \
  --transfer_config \
  --display_name="PRODUCT_DIM Auto Update" \
  --schedule="every 1 hours" \
  --data_source_type=scheduled_query \
  --target_dataset=OI \
  --params='{"query":"CALL `onyga-482313.OI.SP_MERGE_PRODUCT_DIM_SMART`();"}'
```

## How It Works

1. **Scheduled query runs** (e.g., every hour)
2. **Smart procedure checks**:
   - Gets latest `_fivetran_synced` from `fivetran-hl.amazon_selling_partner.item_summary`
   - Gets latest `_fivetran_synced` from `onyga-482313.OI.DIM_PRODUCT`
   - Compares timestamps
3. **If source is newer**: Runs `SP_MERGE_PRODUCT_DIM` to update dimension table
4. **If no changes**: Skips merge (saves compute costs)

## Verify the Scheduled Query

1. Go to BigQuery Console → Scheduled queries
2. You should see "PRODUCT_DIM Auto Update"
3. Check the execution history to see:
   - When it ran
   - Whether changes were detected
   - Execution duration

## Manual Test

You can manually test the smart procedure:

```sql
-- Test the smart wrapper
CALL `onyga-482313.OI.SP_MERGE_PRODUCT_DIM_SMART`();

-- Or test the direct merge (always runs)
CALL `onyga-482313.OI.SP_MERGE_PRODUCT_DIM`();
```

## Monitor Changes

Check when the source table was last updated:

```sql
-- Check source table last sync
SELECT 
  MAX(_fivetran_synced) as last_source_sync,
  COUNT(*) as active_products
FROM `fivetran-hl.amazon_selling_partner.item_summary`
WHERE _fivetran_deleted = false;

-- Check dimension table last sync
SELECT 
  MAX(_fivetran_synced) as last_dim_sync,
  COUNT(*) as total_products,
  COUNT(DISTINCT asin) as unique_asins
FROM `onyga-482313.OI.DIM_PRODUCT`;

-- Compare sync times
SELECT 
  (SELECT MAX(_fivetran_synced) FROM `fivetran-hl.amazon_selling_partner.item_summary` WHERE _fivetran_deleted = false) as source_last_sync,
  (SELECT MAX(_fivetran_synced) FROM `onyga-482313.OI.DIM_PRODUCT`) as dim_last_sync,
  TIMESTAMP_DIFF(
    (SELECT MAX(_fivetran_synced) FROM `fivetran-hl.amazon_selling_partner.item_summary` WHERE _fivetran_deleted = false),
    (SELECT MAX(_fivetran_synced) FROM `onyga-482313.OI.DIM_PRODUCT`),
    MINUTE
  ) as minutes_behind;
```

## Schedule Recommendations

Choose based on your Fivetran sync frequency:

| Fivetran Sync Frequency | Recommended Schedule | Notes |
|------------------------|---------------------|-------|
| Every 15-30 minutes | Every 1 hour | Near real-time updates |
| Every 1-2 hours | Every 1 hour | Real-time updates |
| Every 6 hours | Every 6 hours | Regular updates |
| Daily | Every day at 06:00 | Daily updates |
| Weekly | Every day at 06:00 | Daily check (won't run if no changes) |

## Troubleshooting

### Scheduled query not running

1. **Check execution logs** in BigQuery Console → Scheduled queries → Execution history
2. **Verify permissions**: Service account needs BigQuery Job User role
3. **Check schedule**: Ensure timezone is correct

### No changes detected (but source has new data)

1. **Check _fivetran_synced timestamps**:
   ```sql
   SELECT MAX(_fivetran_synced) FROM `fivetran-hl.amazon_selling_partner.item_summary` WHERE _fivetran_deleted = false;
   ```
2. **Verify Fivetran is syncing**: Check Fivetran dashboard
3. **Check timezone**: Ensure scheduled query timezone matches your expectations

### MERGE running too frequently

- Increase schedule interval (e.g., from 1 hour to 6 hours)
- The smart wrapper will still skip if no changes, but reduces unnecessary checks

## Cost Optimization

The smart wrapper saves costs by:
- **Skipping MERGE** when no changes detected
- **Only checking timestamps** (cheap operation) before running expensive MERGE
- **Reducing unnecessary writes** to the dimension table

## Next Steps

- ✅ Scheduled query is now set up
- Consider setting up alerts for failed executions
- Monitor execution logs to verify it's working correctly
- Adjust schedule frequency based on your Fivetran sync pattern
