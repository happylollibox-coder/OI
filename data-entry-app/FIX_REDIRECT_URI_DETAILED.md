# Fix OAuth Redirect URI Mismatch Error

## Error: `redirect_uri_mismatch`

This error means the redirect URI in Google OAuth Console doesn't match what your app is sending.

## Quick Fix

### Step 1: Get Your Exact Service URL

Run this in Cloud Shell:

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

### Step 2: Calculate Your Redirect URI

Your redirect URI should be:
```
https://<your-service-url>/auth/callback
```

For example:
```
https://oi-data-entry-app-405291422506.us-central1.run.app/auth/callback
```

### Step 3: Add Redirect URI to Google Console

1. **Go to Google Cloud Console:**
   - https://console.cloud.google.com/apis/credentials?project=onyga-482313

2. **Find your OAuth Client ID:**
   - Look for: `405291422506-9gd1k58luauqfbn6bvu79u495ji93v5h.apps.googleusercontent.com`
   - Click the **pencil icon** (Edit) next to it

3. **Add Redirect URI:**
   - Scroll down to **"Authorized redirect URIs"**
   - Click **"+ ADD URI"**
   - Paste your redirect URI: `https://<your-service-url>/auth/callback`
   - **Important:** 
     - Must start with `https://`
     - No trailing slash
     - Exact match

4. **Save:**
   - Click **"SAVE"** at the bottom

5. **Wait:**
   - Wait 1-2 minutes for changes to propagate

6. **Test:**
   - Try logging in again

## Common Mistakes

❌ **Wrong:**
- `http://oi-data-entry-app.../auth/callback` (missing 's' in https)
- `https://oi-data-entry-app.../auth/callback/` (trailing slash)
- `https://oi-data-entry-app.../callback` (missing /auth)

✅ **Correct:**
- `https://oi-data-entry-app-405291422506.us-central1.run.app/auth/callback`

## Verify Your Redirect URI

After adding it, you should see it in the list of "Authorized redirect URIs" in Google Console.

## Still Not Working?

1. **Double-check the exact URL:**
   - Get your service URL again
   - Make sure it matches exactly (copy-paste, don't type)

2. **Check for multiple redirect URIs:**
   - You can have multiple redirect URIs
   - Make sure the correct one is in the list

3. **Clear browser cache:**
   - Sometimes browsers cache OAuth errors
   - Try incognito/private window

4. **Check Cloud Run logs:**
   ```bash
   gcloud run services logs read oi-data-entry-app \
       --region=us-central1 \
       --project=onyga-482313 \
       --limit=20
   ```

## Quick Script

Run this to get your exact redirect URI:

```bash
SERVICE_URL=$(gcloud run services describe oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313 \
    --format="value(status.url)")

echo "Add this redirect URI to Google Console:"
echo "$SERVICE_URL/auth/callback"
```
