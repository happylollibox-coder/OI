#!/bin/bash

# Deploy Cloud Function for fetching real-time exchange rates
# Project: onyga-482313
# Region: us-central1

set -e

PROJECT_ID="onyga-482313"
REGION="us-central1"
FUNCTION_NAME="fetch-exchange-rates"

echo "🚀 Deploying Cloud Function: $FUNCTION_NAME"
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo "==========================================="

# Check if Cloud Functions API is enabled
echo "Checking Cloud Functions API..."
if ! gcloud services list --project="$PROJECT_ID" | grep -q "cloudfunctions.googleapis.com"; then
    echo "Enabling Cloud Functions API..."
    gcloud services enable cloudfunctions.googleapis.com --project="$PROJECT_ID"
fi

# Deploy the function
gcloud functions deploy $FUNCTION_NAME \
  --runtime nodejs20 \
  --trigger-http \
  --allow-unauthenticated \
  --project $PROJECT_ID \
  --region $REGION \
  --source . \
  --entry-point fetchExchangeRates \
  --memory 256MB \
  --timeout 60s \
  --max-instances 10

if [ $? -eq 0 ]; then
    echo "✅ Cloud Function deployed successfully!"
    echo ""
    echo "🌐 Function URL:"
    echo "https://$REGION-$PROJECT_ID.cloudfunctions.net/$FUNCTION_NAME"
    echo ""
    echo "🧪 Test the function:"
    echo "curl https://$REGION-$PROJECT_ID.cloudfunctions.net/$FUNCTION_NAME"
    echo ""
    echo "📊 Expected response contains:"
    echo "   - success: true"
    echo "   - rates: array of 9 currency pairs"
    echo "   - real-time exchange rates from API"
else
    echo "❌ Cloud Function deployment failed!"
    exit 1
fi

echo "==========================================="