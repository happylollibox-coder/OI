# Deploying to Google Cloud Run

This guide will help you deploy your Flask application to Google Cloud Run so it's accessible 24/7, even when your computer is off.

## Prerequisites

1. **Google Cloud Account**: You already have one (using BigQuery)
2. **gcloud CLI**: Install from https://cloud.google.com/sdk/docs/install
3. **Billing Enabled**: Cloud Run requires billing (but has a generous free tier)

## Quick Deploy

### Option 1: Using the Deployment Script (Easiest)

```bash
cd data-entry-app
chmod +x deploy_cloud_run.sh
./deploy_cloud_run.sh
```

This will:
- Build a Docker image
- Deploy to Cloud Run
- Give you a public URL

### Option 2: Manual Deployment

```bash
# 1. Set your project
gcloud config set project onyga-482313

# 2. Enable APIs
gcloud services enable cloudbuild.googleapis.com
gcloud services enable run.googleapis.com

# 3. Build and deploy
gcloud builds submit --tag gcr.io/onyga-482313/oi-data-entry-app
gcloud run deploy oi-data-entry-app \
    --image gcr.io/onyga-482313/oi-data-entry-app \
    --platform managed \
    --region us-central1 \
    --allow-unauthenticated \
    --set-env-vars "GCP_PROJECT_ID=onyga-482313,BIGQUERY_DATASET=OI"
```

## After Deployment

You'll get a URL like:
```
https://oi-data-entry-app-xxxxx-uc.a.run.app
```

**This URL will work 24/7, even when your computer is off!**

## Environment Variables

The app uses these environment variables (set automatically):
- `GCP_PROJECT_ID`: Your GCP project ID
- `BIGQUERY_DATASET`: Your dataset name (OI)

For production, you may want to set:
- `SECRET_KEY`: A secure random key for Flask sessions

## Cost

**Free Tier**: 
- 2 million requests/month free
- 360,000 GB-seconds of memory free
- 180,000 vCPU-seconds free

**After Free Tier**:
- ~$0.40 per million requests
- ~$0.0000025 per GB-second
- ~$0.0000100 per vCPU-second

For a small company, this is likely **free or under $5/month**.

## Security Considerations

1. **Authentication**: Consider adding login/password protection
2. **HTTPS**: Automatically provided by Cloud Run
3. **Environment Variables**: Sensitive data should be in Secret Manager

## Updating the App

To update after making changes:

```bash
./deploy_cloud_run.sh
```

Or manually:
```bash
gcloud builds submit --tag gcr.io/onyga-482313/oi-data-entry-app
gcloud run deploy oi-data-entry-app --image gcr.io/onyga-482313/oi-data-entry-app --region us-central1
```

## Alternative: Google App Engine

If you prefer App Engine (simpler but less flexible):

1. Create `app.yaml`:
```yaml
runtime: python311
instance_class: F1
automatic_scaling:
  min_instances: 0
  max_instances: 10
env_variables:
  GCP_PROJECT_ID: onyga-482313
  BIGQUERY_DATASET: OI
```

2. Deploy:
```bash
gcloud app deploy
```

## Troubleshooting

**Build fails:**
- Check Dockerfile syntax
- Ensure requirements.txt is correct
- Check gcloud authentication: `gcloud auth login`

**App doesn't start:**
- Check logs: `gcloud run services logs read oi-data-entry-app --region us-central1`
- Verify environment variables are set correctly
- Check BigQuery permissions

**Can't access BigQuery:**
- Ensure Cloud Run service account has BigQuery permissions
- Grant roles: `roles/bigquery.dataEditor` and `roles/bigquery.jobUser`
