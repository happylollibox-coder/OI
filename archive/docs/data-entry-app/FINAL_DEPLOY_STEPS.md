# Final Deployment Steps

## Current Situation

The service **has not been deployed yet**, which is why the URL shows "not found". 

The automated deployment keeps timing out due to network restrictions in Cursor.

## You Need to Deploy Manually

**Please open Terminal (outside of Cursor) and run:**

```bash
cd "/Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI/data-entry-app"

# Option 1: Use the complete script
./DEPLOY_COMPLETE.sh

# OR Option 2: Run commands manually
gcloud builds submit --tag gcr.io/onyga-482313/oi-data-entry-app
gcloud run deploy oi-data-entry-app \
    --image gcr.io/onyga-482313/oi-data-entry-app \
    --platform managed \
    --region us-central1 \
    --allow-unauthenticated \
    --set-env-vars "GCP_PROJECT_ID=onyga-482313,BIGQUERY_DATASET=OI"
```

## Why This Is Needed

- ✅ All deployment files are ready
- ✅ APIs are enabled  
- ✅ Configuration is correct
- ❌ File upload times out in Cursor's sandbox

Running in Terminal directly will work because it's not restricted by Cursor's sandbox.

## After Deployment

You'll get a real URL like:
```
https://oi-data-entry-app-xxxxx-uc.a.run.app
```

**This will work 24/7!**

## Check Status

After running deployment, check if it worked:
```bash
gcloud run services list --project=onyga-482313 --region=us-central1
```

You should see `oi-data-entry-app` in the list with a URL.
