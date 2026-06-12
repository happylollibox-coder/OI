# Add Redirect URI to Google OAuth Credentials

## Step 1: Get Your Cloud Run Service URL

Run this command in Cloud Shell or locally:

```bash
gcloud run services describe oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313 \
    --format="value(status.url)"
```

This will output something like:
```
https://oi-data-entry-app-405291422506.us-central1.run.app
```

## Step 2: Add Redirect URI to OAuth Credentials

1. Go to Google Cloud Console: https://console.cloud.google.com/apis/credentials?project=onyga-482313

2. Find your OAuth 2.0 Client ID (the one with Client ID: `405291422506-9gd1k58luauqfbn6bvu79u495ji93v5h.apps.googleusercontent.com`)

3. Click on the **pencil icon** (Edit) next to the OAuth client

4. Under **"Authorized redirect URIs"**, click **"+ ADD URI"**

5. Add this URI (replace with your actual service URL):
   ```
   https://<YOUR_SERVICE_URL>/auth/callback
   ```
   
   For example, if your URL is `https://oi-data-entry-app-405291422506.us-central1.run.app`, add:
   ```
   https://oi-data-entry-app-405291422506.us-central1.run.app/auth/callback
   ```

6. Click **"SAVE"**

## Step 3: Verify

After saving, the redirect URI should appear in the list. Make sure:
- ✅ The URI matches exactly (including `https://` and `/auth/callback`)
- ✅ No trailing slashes
- ✅ The domain matches your Cloud Run service URL

## Common URLs

Based on previous deployments, your service URL might be one of:
- `https://oi-data-entry-app-405291422506.us-central1.run.app`
- `https://oi-data-entry-app-cllsaft6eq-uc.a.run.app`

**Add BOTH if you're not sure which one is active!**

## Quick Command to Get URL

```bash
# Get the service URL
SERVICE_URL=$(gcloud run services describe oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313 \
    --format="value(status.url)")

echo "Add this redirect URI:"
echo "$SERVICE_URL/auth/callback"
```

Then copy the output and add it to the OAuth credentials in the console.
