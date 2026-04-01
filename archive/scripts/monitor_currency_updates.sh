#!/bin/bash

# Monitor Currency Rate Updates
# Check if daily updates are running correctly

PROJECT_ID="onyga-482313"
DATASET="OI"
TABLE="DIM_CURRENCY_RATES"

echo "💱 Monitoring Currency Rate Updates"
echo "==================================="

# Check recent rates
echo "📅 Recent currency rate updates:"
bq query --use_legacy_sql=false --project_id="$PROJECT_ID" "
SELECT
  DATE(rate_timestamp) as update_date,
  COUNT(*) as rates_updated,
  MAX(rate_timestamp) as latest_update,
  STRING_AGG(DISTINCT rate_source LIMIT 3) as sources
FROM \`$PROJECT_ID.$DATASET.$TABLE\`
WHERE DATE(rate_timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY DATE(rate_timestamp)
ORDER BY update_date DESC
LIMIT 7"

echo ""
echo "📊 Current rate summary:"
bq query --use_legacy_sql=false --project_id="$PROJECT_ID" "
SELECT
  base_currency,
  target_currency,
  ROUND(exchange_rate, 4) as current_rate,
  FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', rate_timestamp) as last_updated,
  data_quality_score
FROM \`$PROJECT_ID.$DATASET.$TABLE\`
WHERE exchange_date = CURRENT_DATE()
  AND base_currency = 'USD'
ORDER BY base_currency, target_currency"

echo ""
echo "📈 Historical coverage:"
bq query --use_legacy_sql=false --project_id="$PROJECT_ID" "
SELECT
  EXTRACT(YEAR FROM exchange_date) as year,
  COUNT(DISTINCT exchange_date) as days_with_rates,
  ROUND(AVG(data_quality_score), 1) as avg_quality
FROM \`$PROJECT_ID.$DATASET.$TABLE\`
WHERE exchange_date >= '2023-01-01'
GROUP BY year
ORDER BY year"

echo ""
echo "🔍 Data quality check:"
bq query --use_legacy_sql=false --project_id="$PROJECT_ID" "
SELECT
  rate_source,
  COUNT(*) as record_count,
  ROUND(AVG(data_quality_score), 1) as avg_quality,
  MIN(DATE(rate_timestamp)) as earliest_update,
  MAX(DATE(rate_timestamp)) as latest_update
FROM \`$PROJECT_ID.$DATASET.$TABLE\`
GROUP BY rate_source
ORDER BY record_count DESC"

# Check if cron job is running (if on macOS/Linux)
echo ""
echo "⏰ Local cron job status:"
if command -v crontab >/dev/null 2>&1; then
    if crontab -l | grep -q "update_exchange_rates"; then
        echo "✅ Cron job found:"
        crontab -l | grep "update_exchange_rates"
    else
        echo "❌ No currency update cron job found"
        echo "   Run: ./setup_daily_updates.sh"
    fi
else
    echo "❌ crontab not available (Windows or restricted environment)"
fi

# Check log file if it exists
LOG_FILE="/Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI/logs/currency_updates.log"
echo ""
echo "📋 Recent log entries:"
if [ -f "$LOG_FILE" ]; then
    echo "Last 5 log entries:"
    tail -5 "$LOG_FILE" | while read line; do
        echo "   $line"
    done
else
    echo "❌ No log file found at $LOG_FILE"
fi

echo ""
echo "🎯 Recommendations:"
echo "   - Ensure daily updates are running (check timestamps above)"
echo "   - Verify data quality scores are acceptable (>80 for live data)"
echo "   - Monitor for any FAILED updates in logs"
echo "   - Consider upgrading to Cloud Functions for more reliable updates"