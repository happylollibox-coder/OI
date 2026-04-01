#!/bin/bash

# =============================================
# Deploy Hot Folder Processor Cloud Function
# =============================================

set -e

PROJECT_ID="onyga-482313"
FUNCTION_NAME="process-hot-folder-file"
REGION="us-central1"
TOPIC_NAME="hot-folder-notifications"

echo "Deploying Hot Folder Processor Function..."
echo "Project: $PROJECT_ID"
echo "Function: $FUNCTION_NAME"
echo "Region: $REGION"
echo ""

# Check if gcloud is authenticated
gcloud config set project $PROJECT_ID

# Deploy function
gcloud functions deploy $FUNCTION_NAME \
  --gen2 \
  --runtime=nodejs20 \
  --region=$REGION \
  --source=. \
  --entry-point=processHotFolderFile \
  --trigger-topic=$TOPIC_NAME \
  --project=$PROJECT_ID \
  --memory=512MB \
  --timeout=540s \
  --max-instances=10 \
  --set-env-vars="PROJECT_ID=$PROJECT_ID"

echo ""
echo "✅ Function deployed successfully!"
echo ""
echo "View logs:"
echo "  gcloud functions logs read $FUNCTION_NAME --region=$REGION --project=$PROJECT_ID"
