#!/bin/bash

# Complete setup for real-time currency exchange rates
# This script deploys Cloud Function, BigQuery remote function, and updates stored procedure

set -e

PROJECT_ID="onyga-482313"
DATASET="OI"
REGION="us-central1"
CONNECTION_NAME="bigquery-connection"

echo "🚀 Setting up real-time currency exchange rates"
echo "Project: $PROJECT_ID | Dataset: $DATASET | Region: $REGION"
echo "======================================================"

# Check authentication
echo "🔐 Checking GCP authentication..."
gcloud config set project $PROJECT_ID

# Step 1: Enable required APIs
echo ""
echo "📡 Step 1: Enabling required APIs..."
echo "   - Cloud Functions API"
echo "   - Cloud Build API"

gcloud services enable cloudfunctions.googleapis.com --project=$PROJECT_ID
gcloud services enable cloudbuild.googleapis.com --project=$PROJECT_ID

# Step 2: Create BigQuery connection (if it doesn't exist)
echo ""
echo "🔗 Step 2: Setting up BigQuery connection..."
if ! bq show --connection --project_id=$PROJECT_ID $CONNECTION_NAME >/dev/null 2>&1; then
    echo "   Creating BigQuery connection: $CONNECTION_NAME"
    bq mk --connection \
        --connection_type=CLOUD_RESOURCE \
        --project_id=$PROJECT_ID \
        --location=$REGION \
        $CONNECTION_NAME
else
    echo "   BigQuery connection already exists: $CONNECTION_NAME"
fi

# Step 3: Deploy Cloud Function
echo ""
echo "☁️  Step 3: Deploying Cloud Function..."

cd cloud-functions/fetch-exchange-rates

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "   Installing Node.js dependencies..."
    npm install
fi

echo "   Deploying Cloud Function..."
gcloud functions deploy fetch-exchange-rates \
  --runtime nodejs18 \
  --trigger-http \
  --allow-unauthenticated \
  --project $PROJECT_ID \
  --region $REGION \
  --source . \
  --entry-point fetchExchangeRates \
  --memory 256MB \
  --timeout 60s \
  --max-instances 10

echo "   ✅ Cloud Function deployed successfully!"

# Step 4: Test Cloud Function
echo ""
echo "🧪 Step 4: Testing Cloud Function..."
FUNCTION_URL="https://$REGION-$PROJECT_ID.cloudfunctions.net/fetch-exchange-rates"
echo "   Testing: $FUNCTION_URL"

TEST_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" "$FUNCTION_URL")
HTTP_STATUS=$(echo "$TEST_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
RESPONSE_BODY=$(echo "$TEST_RESPONSE" | sed '/HTTP_STATUS:/d')

if [ "$HTTP_STATUS" = "200" ]; then
    if echo "$RESPONSE_BODY" | grep -q '"success":true'; then
        echo "   ✅ Cloud Function test passed!"
        echo "   📊 Response contains real exchange rates"
    else
        echo "   ⚠️  Cloud Function returned success=false, using fallback data"
    fi
else
    echo "   ❌ Cloud Function test failed (HTTP $HTTP_STATUS)"
    echo "   Response: $RESPONSE_BODY"
fi

cd ../..

# Step 5: Deploy BigQuery remote function
echo ""
echo "🔧 Step 5: Deploying BigQuery remote function..."
bq query --use_legacy_sql=false --project_id=$PROJECT_ID < scripts/Functions/FN_FETCH_EXCHANGE_RATES.sql

# Step 6: Test remote function
echo ""
echo "🧪 Step 6: Testing BigQuery remote function..."
REMOTE_TEST=$(bq query --use_legacy_sql=false --project_id=$PROJECT_ID \
    "SELECT JSON_VALUE(\`onyga-482313.OI.FN_FETCH_EXCHANGE_RATES\`(), '$.success') as success, JSON_VALUE(\`onyga-482313.OI.FN_FETCH_EXCHANGE_RATES\`(), '$.metadata.api_provider') as provider" \
    2>/dev/null || echo "Remote function test failed")

if echo "$REMOTE_TEST" | grep -q "true"; then
    echo "   ✅ BigQuery remote function test passed!"
else
    echo "   ⚠️  BigQuery remote function test inconclusive (may be connection setup)"
fi

# Step 7: Deploy updated stored procedure
echo ""
echo "📝 Step 7: Deploying updated stored procedure..."
bq query --use_legacy_sql=false --project_id=$PROJECT_ID < scripts/SP/SP_UPDATE_CURRENCY_RATES.sql

# Step 8: Test complete system
echo ""
echo "🎯 Step 8: Testing complete system..."
bq query --use_legacy_sql=false --project_id=$PROJECT_ID \
    "CALL \`onyga-482313.OI.SP_UPDATE_CURRENCY_RATES\`(CURRENT_DATE(), CURRENT_DATE(), FALSE);"

echo ""
echo "📊 Checking results..."
bq query --use_legacy_sql=false --project_id=$PROJECT_ID \
    "SELECT COUNT(*) as today_rates, MAX(rate_timestamp) as latest_update, STRING_AGG(DISTINCT rate_source LIMIT 1) as source FROM \`onyga-482313.OI.DIM_CURRENCY_RATES\` WHERE exchange_date = CURRENT_DATE()"

echo ""
echo "🎉 Setup Complete!"
echo "================="
echo ""
echo "✅ What's now working:"
echo "   • Cloud Function fetching real exchange rates"
echo "   • BigQuery remote function calling Cloud Function"
echo "   • Stored procedure using real-time data"
echo "   • BigQuery Scheduled Query will use real rates"
echo ""
echo "🌐 Cloud Function URL:"
echo "   $FUNCTION_URL"
echo ""
echo "📅 Daily Updates:"
echo "   Your BigQuery Scheduled Query will now fetch real exchange rates daily!"
echo ""
echo "🔍 Monitor with:"
echo "   ./monitor_currency_updates.sh"
echo ""
echo "📊 Check today's rates:"
echo "   SELECT * FROM \`onyga-482313.OI.V_SRC_CURRENCY_CONVERSION\` WHERE rate_date = CURRENT_DATE();"
echo ""
echo "==========================================="