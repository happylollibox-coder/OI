# Deployment Instructions

## Current Status

The service `oi-data-entry-app` is **not yet deployed**. The URL you tried doesn't exist because the deployment hasn't completed.

## Why Deployment Failed

Network timeout issues prevented the automated deployment from completing. The build process times out when uploading files.

## Solution: Deploy Manually

**Please run these commands in your Terminal** (not in Cursor):

### Step 1: Open Terminal
```bash
cd "/Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI/data-entry-app"
```

### Step 2: Build the Docker Image
```bash
gcloud builds submit --tag gcr.io/onyga-482313/oi-data-entry-app
```
⏱️ This takes 5-10 minutes

### Step 3: Deploy to Cloud Run
```bash
gcloud run deploy oi-data-entry-app \
    --image gcr.io/onyga-482313/oi-data-entry-app \
    --platform managed \
    --region us-central1 \
    --allow-unauthenticated \
    --set-env-vars "GCP_PROJECT_ID=onyga-482313,BIGQUERY_DATASET=OI" \
    --memory 512Mi \
    --cpu 1 \
    --timeout 300 \
    --max-instances 10
```
⏱️ This takes 2-3 minutes

### Step 4: Get Your URL
After deployment, you'll see:
```
Service URL: https://oi-data-entry-app-xxxxx-uc.a.run.app
```

## Alternative: Use Google Cloud Shell

If Terminal also has issues:

1. Go to: https://console.cloud.google.com/cloudshell
2. Upload the `data-entry-app` folder
3. Run the commands above in Cloud Shell (better network)

## Check Current Status

To see if service exists:
```bash
gcloud run services list --project=onyga-482313 --region=us-central1
```

To check build status:
```bash
gcloud builds list --project=onyga-482313 --limit=5
```

## All Files Are Ready ✅

- Dockerfile ✅
- requirements.txt ✅
- .gcloudignore ✅
- APIs enabled ✅

You just need to run the build and deploy commands!
