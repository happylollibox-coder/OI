# Setup Daily Currency Rate Updates

## ✅ System Status
- ✅ Cloud Function deployed and working
- ✅ BigQuery Remote Function deployed and working
- ✅ Stored Procedure deployed and working
- ✅ Data successfully inserted into `DIM_CURRENCY_RATES`

## Setup BigQuery Scheduled Query for Daily Updates

### Option 1: Via BigQuery Console (Recommended)

1. **Go to BigQuery Console:**
   - https://console.cloud.google.com/bigquery?project=onyga-482313

2. **Click "Scheduled queries" in the left menu**

3. **Click "Create scheduled query"**

4. **Configure the query:**
   - **Name**: `Daily Currency Rate Update`
   - **Schedule**: `Every day` at `06:00` (or your preferred time)
   - **Query:**
     ```sql
     CALL `onyga-482313.OI.SP_UPDATE_CURRENCY_RATES`(
       CURRENT_DATE(), 
       CURRENT_DATE(), 
       FALSE
     );
     ```
   - **Destination**: Leave empty (stored procedure handles the insert)
   - **Region**: `US` (multi-region)

5. **Click "Save"**

### Option 2: Via gcloud CLI

```bash
bq query \
  --use_legacy_sql=false \
  --schedule="every day 06:00" \
  --display_name="Daily Currency Rate Update" \
  --description="Updates currency exchange rates daily" \
  --location=US \
  "CALL \`onyga-482313.OI.SP_UPDATE_CURRENCY_RATES\`(CURRENT_DATE(), CURRENT_DATE(), FALSE);"
```

## Verify the Scheduled Query

1. Go to BigQuery Console → Scheduled queries
2. You should see "Daily Currency Rate Update"
3. Check the execution history to see if it runs successfully

## Manual Test

You can manually trigger the update anytime:

```sql
CALL `onyga-482313.OI.SP_UPDATE_CURRENCY_RATES`(CURRENT_DATE(), CURRENT_DATE(), FALSE);
```

## Verify Data

Check that data is being updated daily:

```sql
SELECT 
  exchange_date,
  COUNT(*) as currency_pairs,
  MAX(rate_timestamp) as last_update
FROM `onyga-482313.OI.DIM_CURRENCY_RATES`
WHERE exchange_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY exchange_date
ORDER BY exchange_date DESC;
```

## Troubleshooting

If the scheduled query fails:

1. **Check the execution logs** in BigQuery Console
2. **Verify the Cloud Function is still accessible:**
   ```bash
   curl -s 'https://fetch-exchange-rates-405291422506.us-central1.run.app' | jq '.success'
   ```
3. **Check the remote function:**
   ```sql
   SELECT JSON_VALUE(`onyga-482313.OI.FN_FETCH_EXCHANGE_RATES`(), '$.success') as success;
   ```

## Next Steps

- ✅ Daily updates are now automated
- Consider setting up alerts for failed executions
- Monitor data quality scores in the table
- Review exchange rates periodically for anomalies
