# Deployment Scripts

This directory contains scripts for deploying the OI database project to BigQuery.

## Scripts Overview

### `deploy.sh`
Deploys all interface views to BigQuery project `onyga-482313.OI`.

### `deploy_product_dim.sh`
Deploys DIM_PRODUCT table, V_SRC_Products view, and SP_MERGE_PRODUCT_DIM procedures.

### `deploy_currency.sh`
Deploys currency infrastructure: DIM_CURRENCY_RATES, SP_UPDATE_CURRENCY_RATES, V_SRC_CURRENCY_CONVERSION.

**Usage:**
```bash
chmod +x deploy.sh
./deploy.sh
```

**What it does:**
- Sets the correct BigQuery project
- Deploys views in dependency order
- Provides status updates for each deployment
- Validates successful deployment

### `validate.sh`
Validates that all views are properly deployed and accessible.

**Usage:**
```bash
chmod +x validate.sh
./validate.sh
```

**Checks:**
- Dataset existence
- All expected views are present
- Views are queryable
- Sample query execution

### `rollback.sh`
Drops all deployed views (use with caution).

**Usage:**
```bash
chmod +x rollback.sh
./rollback.sh
# Type 'yes' when prompted
```

**Safety features:**
- Requires explicit confirmation
- Drops views in reverse dependency order
- Uses `DROP VIEW IF EXISTS` to avoid errors

### Orchestrator (SP_ORCHESTRATE_DAILY_REFRESH)

**Usage:**
```bash
bq query --use_legacy_sql=false --project_id=onyga-482313 \
  "CALL \`onyga-482313.OI.SP_ORCHESTRATE_DAILY_REFRESH\`();"
```

**Note:** When running the orchestrator via automated tools or CI, use a **10-minute (600 second) timeout** to allow the full run to complete (18+ procedures).

## Prerequisites

1. **GCP Authentication:**
   ```bash
   gcloud auth login
   gcloud config set project onyga-482313
   ```

2. **BigQuery Permissions:**
   - BigQuery Admin or Editor role
   - Access to project `onyga-482313`

3. **Fivetran Data Access:**
   - Views depend on `fivetran-hl` project data
   - Ensure Fivetran pipelines are active

## Deployment Order

Views are deployed in this order to respect dependencies:

1. `V_SRC_AmazonAds_campaign_history` (base dependency)
2. `V_SRC_AmazonAds_keyword` (base dependency)
3. `V_SRC_AmazonAds_negative_keyword`
4. `V_SRC_AmazonAds_purchased_product`
5. `V_SRC_AmazonAds_SearchTerms` (depends on campaign_history and keyword)
6. `V_SRC_Seller_repeat_purchase`
7. `NewView1`

## Troubleshooting

### Common Issues

1. **Permission Denied:**
   ```
   ERROR: Access Denied
   ```
   - Check your GCP permissions
   - Verify project access

2. **Dataset Not Found:**
   ```
   ERROR: Dataset not found
   ```
   - Ensure dataset `OI` exists in project `onyga-482313`
   - Check project spelling

3. **Source Table Missing:**
   ```
   ERROR: Table not found: fivetran-hl.amazon_ads...
   ```
   - Verify Fivetran pipelines are running
   - Check data source connectivity

### Logs and Debugging

- Scripts provide detailed output for each step
- Use `bq ls --project_id=onyga-482313 OI` to check current state
- Run validation script to diagnose issues

## Archive Policy

**Before dropping a table, create an archive table with the `ARCHIVE_` prefix.**

See [ARCHIVE_POLICY.md](ARCHIVE_POLICY.md) for the full pattern and examples.

## Best Practices

1. **Test in Development First:**
   - Use BigQuery sandbox for testing
   - Validate scripts before production deployment

2. **Backup Existing Views:**
   - Note existing view definitions before deployment
   - Use rollback script if needed

3. **Monitor After Deployment:**
   - Check view accessibility
   - Monitor query performance
   - Validate data freshness
