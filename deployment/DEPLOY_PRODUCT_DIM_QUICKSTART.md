# PRODUCT_DIM Quick Deployment Guide

## Option 1: Deploy via BigQuery Console (Easiest)

1. **Open BigQuery Console:**
   - Go to: https://console.cloud.google.com/bigquery?project=onyga-482313
   - Make sure project `onyga-482313` is selected

2. **Run the deployment script:**
   - Open the file: `deployment/deploy_product_dim.sql`
   - Copy the entire contents
   - Paste into BigQuery query editor
   - Click **"Run"**

3. **Verify deployment:**
   ```sql
   -- Check table exists
   SELECT table_name 
   FROM `onyga-482313.OI.INFORMATION_SCHEMA.TABLES` 
   WHERE table_name = 'DIM_PRODUCT';
   
   -- Check view exists
   SELECT table_name 
   FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS` 
   WHERE table_name = 'V_SRC_Products';
   
   -- Check stored procedures exist
   SELECT routine_name 
   FROM `onyga-482313.OI.INFORMATION_SCHEMA.ROUTINES` 
   WHERE routine_name LIKE 'SP_MERGE_PRODUCT_DIM%';
   ```

4. **Test the merge:**
   ```sql
   CALL `onyga-482313.OI.SP_MERGE_PRODUCT_DIM_SMART`();
   ```

## Option 2: Deploy via Command Line

```bash
# Make sure you're authenticated
gcloud auth login
gcloud config set project onyga-482313

# Run the deployment script
cd /Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI
./deployment/deploy_product_dim.sh
```

## Option 3: Deploy Individual Components

If you prefer to deploy step by step:

### Step 1: Create Table
```bash
bq query --use_legacy_sql=false --project_id=onyga-482313 < scripts/bigquery/tables/DIM/DIM_PRODUCT.sql
```

### Step 2: Create View
```bash
bq query --use_legacy_sql=false --project_id=onyga-482313 < scripts/bigquery/interface_views/V_SRC_Products.sql
```

### Step 3: Create Stored Procedures
```bash
bq query --use_legacy_sql=false --project_id=onyga-482313 < scripts/bigquery/procedures/SP_MERGE_PRODUCT_DIM.sql
bq query --use_legacy_sql=false --project_id=onyga-482313 < scripts/bigquery/procedures/SP_MERGE_PRODUCT_DIM_SMART.sql
```

## Important Notes

### Before Deployment

1. **Verify item_summary schema:**
   The `V_SRC_Products` view may need field name adjustments. Check the actual schema:
   ```sql
   SELECT * 
   FROM `fivetran-hl.amazon_selling_partner.item_summary` 
   LIMIT 1;
   ```
   
   Common field name variations:
   - `product_name` might be: `title`, `item_name`, `product_title`
   - `marketplace` might be: `marketplace_id`, `marketplace_code`
   - `launch_date` might be: `release_date`, `first_available_date`

2. **Update V_SRC_Products.sql if needed:**
   If field names don't match, edit `scripts/bigquery/interface_views/V_SRC_Products.sql` before deployment.

### After Deployment

1. **Run initial merge:**
   ```sql
   CALL `onyga-482313.OI.SP_MERGE_PRODUCT_DIM_SMART`();
   ```

2. **Verify data loaded:**
   ```sql
   SELECT 
     COUNT(*) as total_products,
     COUNT(DISTINCT asin) as unique_asins,
     MAX(_fivetran_synced) as last_sync
   FROM `onyga-482313.OI.DIM_PRODUCT`;
   ```

3. **Set up scheduled query:**
   - See `SETUP_PRODUCT_DIM_SCHEDULE.md` for detailed instructions
   - Or go to BigQuery → Scheduled queries → Create
   - Use: `CALL \`onyga-482313.OI.SP_MERGE_PRODUCT_DIM_SMART\`();`
   - Schedule: Every 1 hour (or match your Fivetran sync frequency)

## Troubleshooting

### Error: Table/View/Procedure already exists
- This is normal - the scripts use `CREATE OR REPLACE`
- The objects will be updated/recreated

### Error: Field not found in item_summary
- The `V_SRC_Products` view needs field name adjustments
- Check the actual schema and update the view accordingly

### Error: Permission denied
- Ensure you have BigQuery Admin or Editor role
- Check project access: `gcloud projects list`

## Next Steps

After successful deployment:
1. ✅ Verify all objects created
2. ✅ Test the merge procedure
3. ✅ Set up scheduled query (see `SETUP_PRODUCT_DIM_SCHEDULE.md`)
4. ✅ Monitor execution logs
5. ✅ Add custom fields as needed
