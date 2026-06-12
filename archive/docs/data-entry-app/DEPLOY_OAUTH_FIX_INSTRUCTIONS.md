# Deploy OAuth Fix - Instructions

## What Was Fixed

The OAuth callback was updated to properly fetch user information from Google's userinfo endpoint instead of trying to get it directly from the token response.

**Change**: Replaced `token.get('userinfo')` with `google.get('https://www.googleapis.com/oauth2/v2/userinfo', token=token)`

## Quick Deploy (Cloud Shell)

### Option 1: Use the Deployment Script

1. Open Google Cloud Shell: https://shell.cloud.google.com/?project=onyga-482313

2. Copy and paste this entire script:

```bash
PROJECT_ID="onyga-482313"
SERVICE_NAME="oi-data-entry-app"
REGION="us-central1"
BUCKET="onyga-482313-temp-uploads"

echo "Downloading and deploying OAuth fix..."
mkdir -p ~/data-entry-app
cd ~/data-entry-app
gsutil cp gs://$BUCKET/data-entry-app.zip .
unzip -o data-entry-app.zip
chmod +x deploy_minimal.sh
./deploy_minimal.sh

echo ""
echo "✅ Deployment complete!"
gcloud run services describe $SERVICE_NAME \
    --region=$REGION \
    --project=$PROJECT_ID \
    --format="value(status.url)"
```

3. Press Enter and wait 5-10 minutes for deployment

### Option 2: Manual Steps

```bash
# 1. Download code
mkdir -p ~/data-entry-app
cd ~/data-entry-app
gsutil cp gs://onyga-482313-temp-uploads/data-entry-app.zip .

# 2. Extract
unzip -o data-entry-app.zip

# 3. Deploy
chmod +x deploy_minimal.sh
./deploy_minimal.sh
```

## Verify the Fix

After deployment, test the login:

1. Go to your service URL: `https://<your-service-url>/login`
2. Click "Sign in with Google"
3. Sign in with an authorized account (happylollibox@gmail.com or adva.tal2@gmail.com)
4. Should redirect successfully to the home page

## If OAuth Still Doesn't Work

### Check 1: Redirect URI
Ensure the redirect URI in Google Console matches:
```
https://<your-service-url>/auth/callback
```

Get your service URL:
```bash
gcloud run services describe oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313 \
    --format="value(status.url)"
```

### Check 2: OAuth Consent Screen
1. Go to: https://console.cloud.google.com/apis/credentials/consent?project=onyga-482313
2. Verify test users include:
   - happylollibox@gmail.com
   - adva.tal2@gmail.com

### Check 3: Environment Variables
```bash
gcloud run services describe oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313 \
    --format="value(spec.template.spec.containers[0].env)" | grep GOOGLE
```

Should show:
- `GOOGLE_CLIENT_ID=405291422506-9gd1k58luauqfbn6bvu79u495ji93v5h.apps.googleusercontent.com`
- `GOOGLE_CLIENT_SECRET=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`

### Check 4: View Logs
```bash
gcloud run services logs read oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313 \
    --limit=50
```

## What's Included in This Deployment

- ✅ OAuth callback fix (proper userinfo fetching)
- ✅ Removed columns: PO ID, Manufacturer, ASIN from home page
- ✅ Auto-calculate estimated_arrival_date based on shipment_type
- ✅ All previous features

## Status

✅ **Code uploaded to Cloud Storage**: `gs://onyga-482313-temp-uploads/data-entry-app.zip`
✅ **Ready to deploy**: Run the commands above in Cloud Shell
