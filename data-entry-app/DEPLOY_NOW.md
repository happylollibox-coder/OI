# Deploy to Google Cloud Run - Step by Step

Follow these steps to deploy your app to Cloud Run:

## Step 1: Open Terminal

Open Terminal on your Mac and navigate to the project:
```bash
cd "/Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI/data-entry-app"
```

## Step 2: Verify Authentication

```bash
gcloud auth login
gcloud config set project onyga-482313
```

## Step 3: Build and Deploy

Run this command (it will take 5-10 minutes):

```bash
gcloud builds submit --tag gcr.io/onyga-482313/oi-data-entry-app
```

Then deploy:

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

## Step 4: Get Your URL

After deployment completes, you'll see output like:
```
Service [oi-data-entry-app] revision [oi-data-entry-app-00001-abc] has been deployed and is serving 100 percent of traffic.
Service URL: https://oi-data-entry-app-xxxxx-uc.a.run.app
```

**That URL will work 24/7, even when your computer is off!**

## Alternative: Use the Deployment Script

You can also run:
```bash
chmod +x deploy_cloud_run.sh
./deploy_cloud_run.sh
```

## Troubleshooting

**If build fails:**
- Check your internet connection
- Make sure you're authenticated: `gcloud auth login`
- Verify project: `gcloud config get-value project`

**If deployment fails:**
- Check Cloud Run API is enabled
- Verify billing is enabled for your project
- Check logs: `gcloud run services logs read oi-data-entry-app --region us-central1`

## After Deployment

1. **Test the URL** - Open it in your browser
2. **Share with team** - Anyone can access it from anywhere
3. **Bookmark it** - Save the URL for easy access

## Updating the App

When you make changes, redeploy:
```bash
gcloud builds submit --tag gcr.io/onyga-482313/oi-data-entry-app
gcloud run deploy oi-data-entry-app --image gcr.io/onyga-482313/oi-data-entry-app --region us-central1
```
