# Quick Deploy Instructions

## All files are ready! 🎉

Due to network restrictions in Cursor, please run the deployment manually in your Terminal.

## One-Command Deployment

Simply run this in Terminal:

```bash
cd "/Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI/data-entry-app" && ./DEPLOY_COMPLETE.sh
```

Or copy-paste these commands:

```bash
cd "/Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI/data-entry-app"

gcloud builds submit --tag gcr.io/onyga-482313/oi-data-entry-app

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

## What Happens

1. **Build** (5-10 min): Uploads your code and builds a Docker container
2. **Deploy** (2-3 min): Deploys to Cloud Run
3. **Get URL**: You'll receive a public URL that works 24/7

## Expected Output

After deployment, you'll see:
```
Service [oi-data-entry-app] revision [...] has been deployed
Service URL: https://oi-data-entry-app-xxxxx-uc.a.run.app
```

**That URL will work forever, even when your computer is off!**

## Troubleshooting

**If build times out:**
- Check your internet connection
- Try again (sometimes network hiccups occur)
- Use Cloud Shell: https://console.cloud.google.com/cloudshell

**If deployment fails:**
- Make sure billing is enabled
- Check: `gcloud auth list` (you should be logged in)
- Verify project: `gcloud config get-value project`

## Files Ready ✅

- ✅ Dockerfile
- ✅ requirements.txt  
- ✅ cloudbuild.yaml
- ✅ .gcloudignore
- ✅ DEPLOY_COMPLETE.sh (automated script)

Everything is configured and ready to deploy!
