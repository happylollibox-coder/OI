#!/bin/bash

# =============================================
# Setup Hot Folder in Google Cloud Storage
# =============================================
#
# Purpose: Create GCS bucket and configure hot folder processing
# Project: onyga-482313
#
# =============================================

set -e  # Exit on any error

PROJECT_ID="onyga-482313"
BUCKET_NAME="onyga-482313-hot-folder"
REGION="us-central1"
FUNCTION_NAME="process-hot-folder-file"
FUNCTION_REGION="us-central1"
TOPIC_NAME="hot-folder-notifications"

echo "==========================================="
echo "Setting up Hot Folder in GCS"
echo "==========================================="
echo "Project: $PROJECT_ID"
echo "Bucket: $BUCKET_NAME"
echo "Region: $REGION"
echo ""

# Check if gcloud is authenticated
echo "Checking GCP authentication..."
gcloud config set project $PROJECT_ID

# Enable required APIs
echo ""
echo "Enabling required APIs..."
gcloud services enable storage-component.googleapis.com --project=$PROJECT_ID
gcloud services enable cloudfunctions.googleapis.com --project=$PROJECT_ID
gcloud services enable cloudbuild.googleapis.com --project=$PROJECT_ID
gcloud services enable pubsub.googleapis.com --project=$PROJECT_ID

# Create GCS bucket if it doesn't exist
echo ""
echo "Creating GCS bucket..."
if gsutil ls -b gs://$BUCKET_NAME 2>/dev/null; then
    echo "Bucket $BUCKET_NAME already exists"
else
    gsutil mb -p $PROJECT_ID -c STANDARD -l $REGION gs://$BUCKET_NAME
    echo "✅ Bucket created: gs://$BUCKET_NAME"
fi

# Create folder structure
# Note: GCS doesn't have true folders, so we create placeholder files to establish folder structure
echo ""
echo "Creating folder structure..."
echo "Creating folder placeholders..."

# Create placeholder files to establish folder structure
echo "Folder placeholder" | gsutil cp - gs://$BUCKET_NAME/incoming/.keep
echo "Folder placeholder" | gsutil cp - gs://$BUCKET_NAME/archive/.keep
echo "Folder placeholder" | gsutil cp - gs://$BUCKET_NAME/errors/.keep

echo "Folder placeholder" | gsutil cp - gs://$BUCKET_NAME/incoming/csv/.keep
echo "Folder placeholder" | gsutil cp - gs://$BUCKET_NAME/incoming/csv/payoneer/.keep
echo "Folder placeholder" | gsutil cp - gs://$BUCKET_NAME/incoming/csv/leumi/.keep
echo "Folder placeholder" | gsutil cp - gs://$BUCKET_NAME/incoming/csv/currency/.keep
echo "Folder placeholder" | gsutil cp - gs://$BUCKET_NAME/incoming/csv/Inventory_Ledger_Summary/.keep
echo "Folder placeholder" | gsutil cp - gs://$BUCKET_NAME/incoming/csv/AWD_Inventory_Ledger_Summary/.keep
echo "Folder placeholder" | gsutil cp - gs://$BUCKET_NAME/incoming/excel/.keep
echo "Folder placeholder" | gsutil cp - gs://$BUCKET_NAME/incoming/excel/reports/.keep
echo "Folder placeholder" | gsutil cp - gs://$BUCKET_NAME/incoming/json/.keep
echo "Folder placeholder" | gsutil cp - gs://$BUCKET_NAME/incoming/json/api/.keep
echo "Folder placeholder" | gsutil cp - gs://$BUCKET_NAME/incoming/text/.keep
echo "Folder placeholder" | gsutil cp - gs://$BUCKET_NAME/incoming/other/.keep

echo "✅ Folder structure created:"
echo "   - incoming/csv/ (with subfolders: payoneer/, leumi/, currency/, Inventory_Ledger_Summary/, AWD_Inventory_Ledger_Summary/)"
echo "   - incoming/excel/ (with subfolder: reports/)"
echo "   - incoming/json/ (with subfolder: api/)"
echo "   - incoming/text/"
echo "   - incoming/other/"
echo "   - archive/"
echo "   - errors/"

# Create Pub/Sub topic for notifications
echo ""
echo "Creating Pub/Sub topic..."
if gcloud pubsub topics describe $TOPIC_NAME --project=$PROJECT_ID 2>/dev/null; then
    echo "Topic $TOPIC_NAME already exists"
else
    gcloud pubsub topics create $TOPIC_NAME --project=$PROJECT_ID
    echo "✅ Topic created: $TOPIC_NAME"
fi

# Configure bucket notifications
echo ""
echo "Configuring bucket notifications..."
gsutil notification create -t $TOPIC_NAME -f json gs://$BUCKET_NAME
echo "✅ Bucket notifications configured"

# Deploy Cloud Function
echo ""
echo "Deploying Cloud Function..."
cd cloud-functions/hot-folder-processor

gcloud functions deploy $FUNCTION_NAME \
  --gen2 \
  --runtime=nodejs20 \
  --region=$FUNCTION_REGION \
  --source=. \
  --entry-point=processHotFolderFile \
  --trigger-topic=$TOPIC_NAME \
  --project=$PROJECT_ID \
  --memory=512MB \
  --timeout=540s \
  --max-instances=10 \
  --set-env-vars="PROJECT_ID=$PROJECT_ID"

cd ../..

echo ""
echo "==========================================="
echo "✅ Hot Folder setup completed!"
echo "==========================================="
echo ""
echo "Usage:"
echo "  Upload files to the appropriate folder based on file type:"
echo ""
echo "  CSV files:"
echo "    gsutil cp payoneer-data.csv gs://$BUCKET_NAME/incoming/csv/payoneer/"
echo "    gsutil cp leumi-data.csv gs://$BUCKET_NAME/incoming/csv/leumi/"
echo "    gsutil cp currency-rates.csv gs://$BUCKET_NAME/incoming/csv/currency/"
echo "    gsutil cp inventory-snapshot.csv gs://$BUCKET_NAME/incoming/csv/Inventory_Ledger_Summary/"
echo "    gsutil cp awd-inventory.csv gs://$BUCKET_NAME/incoming/csv/AWD_Inventory_Ledger_Summary/"
echo "    gsutil cp any-csv.csv gs://$BUCKET_NAME/incoming/csv/"
echo ""
echo "  Excel files:"
echo "    gsutil cp report.xlsx gs://$BUCKET_NAME/incoming/excel/reports/"
echo "    gsutil cp any-excel.xlsx gs://$BUCKET_NAME/incoming/excel/"
echo ""
echo "  JSON files:"
echo "    gsutil cp api-data.json gs://$BUCKET_NAME/incoming/json/api/"
echo "    gsutil cp any-json.json gs://$BUCKET_NAME/incoming/json/"
echo ""
echo "  Other files:"
echo "    gsutil cp file.txt gs://$BUCKET_NAME/incoming/text/"
echo "    gsutil cp unknown-file.xyz gs://$BUCKET_NAME/incoming/other/"
echo ""
echo "File Processing:"
echo "  - Files are automatically processed when uploaded"
echo "  - Processed files moved to: gs://$BUCKET_NAME/archive/"
echo "  - Failed files moved to: gs://$BUCKET_NAME/errors/"
echo ""
echo "View function logs:"
echo "  gcloud functions logs read $FUNCTION_NAME --region=$FUNCTION_REGION --project=$PROJECT_ID"
echo ""
