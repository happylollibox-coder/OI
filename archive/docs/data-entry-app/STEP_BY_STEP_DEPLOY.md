# Step-by-Step: Set Environment Variables & Deploy

## Overview
This guide will help you:
1. Set OAuth environment variables in Cloud Run
2. Deploy the updated code with OAuth fixes

---

## Part 1: Set Environment Variables in Cloud Run

### Option A: Using Google Cloud Shell (Recommended)

1. **Open Google Cloud Shell**
   - Go to: https://shell.cloud.google.com/?project=onyga-482313
   - Or click the Cloud Shell icon in the Google Cloud Console

2. **Run this command to set environment variables:**
   ```bash
   gcloud run services update oi-data-entry-app \
       --region=us-central1 \
       --project=onyga-482313 \
       --update-env-vars "GOOGLE_CLIENT_ID=405291422506-9gd1k58luauqfbn6bvu79u495ji93v5h.apps.googleusercontent.com,GOOGLE_CLIENT_SECRET=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"
   ```

3. **Verify the variables were set:**
   ```bash
   gcloud run services describe oi-data-entry-app \
       --region=us-central1 \
       --project=onyga-482313 \
       --format="value(spec.template.spec.containers[0].env)" | grep GOOGLE
   ```
   
   You should see:
   ```
   GOOGLE_CLIENT_ID=405291422506-9gd1k58luauqfbn6bvu79u495ji93v5h.apps.googleusercontent.com
   GOOGLE_CLIENT_SECRET=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
   ```

### Option B: Using Google Cloud Console (Web UI)

1. **Go to Cloud Run**
   - Navigate to: https://console.cloud.google.com/run?project=onyga-482313

2. **Click on your service**
   - Find and click: `oi-data-entry-app`

3. **Edit the service**
   - Click the **"EDIT & DEPLOY NEW REVISION"** button (top right)

4. **Add environment variables**
   - Scroll down to **"Variables & Secrets"** section
   - Click **"ADD VARIABLE"**
   - Add first variable:
     - **Name**: `GOOGLE_CLIENT_ID`
     - **Value**: `405291422506-9gd1k58luauqfbn6bvu79u495ji93v5h.apps.googleusercontent.com`
   - Click **"ADD VARIABLE"** again
   - Add second variable:
     - **Name**: `GOOGLE_CLIENT_SECRET`
     - **Value**: `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`

5. **Deploy**
   - Scroll to bottom
   - Click **"DEPLOY"** button
   - Wait for deployment to complete (2-3 minutes)

---

## Part 2: Deploy Updated Code

### Step 1: Open Google Cloud Shell

- Go to: https://shell.cloud.google.com/?project=onyga-482313

### Step 2: Download the Updated Code

```bash
# Create directory if it doesn't exist
mkdir -p ~/data-entry-app
cd ~/data-entry-app

# Download the latest code from Cloud Storage
gsutil cp gs://onyga-482313-temp-uploads/data-entry-app.zip .
```

**Expected output:**
```
Copying gs://onyga-482313-temp-uploads/data-entry-app.zip...
/ [1 files][ 69.0 KiB/ 69.0 KiB]
Operation completed over 1 objects/69.0 KiB.
```

### Step 3: Extract the Code

```bash
# Extract the ZIP file
unzip -o data-entry-app.zip
```

**Expected output:**
```
Archive:  data-entry-app.zip
  inflating: app.py
  inflating: requirements.txt
  inflating: Dockerfile
  ... (many files)
```

### Step 4: Make Deployment Script Executable

```bash
# Make the deployment script executable
chmod +x deploy_minimal.sh
```

### Step 5: Deploy to Cloud Run

```bash
# Run the deployment script
./deploy_minimal.sh
```

**What happens:**
- Builds a Docker image (5-10 minutes)
- Pushes image to Artifact Registry
- Deploys to Cloud Run
- Updates the service with new code

**Expected output:**
```
🚀 Starting minimal deployment...
Project: onyga-482313
Service: oi-data-entry-app

📦 Step 0: Ensuring Artifact Registry repository exists...
📦 Step 1: Building Docker image...
This may take 5-10 minutes...
...
✅ Build successful!

🚀 Step 2: Deploying to Cloud Run...
This may take 2-3 minutes...
...
✅ Deployment successful!

🌐 Your service is live at:
   https://oi-data-entry-app-xxxxx-uc.a.run.app
```

### Step 6: Verify Deployment

```bash
# Get your service URL
gcloud run services describe oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313 \
    --format="value(status.url)"
```

**Copy the URL and test:**
1. Open the URL in your browser
2. You should see the login page
3. Click "Sign in with Google"
4. OAuth should work now!

---

## Complete One-Line Deployment (After Setting Env Vars)

If you've already set the environment variables, you can deploy in one go:

```bash
cd ~ && mkdir -p ~/data-entry-app && cd ~/data-entry-app && \
gsutil cp gs://onyga-482313-temp-uploads/data-entry-app.zip . && \
unzip -o data-entry-app.zip && \
chmod +x deploy_minimal.sh && \
./deploy_minimal.sh
```

---

## Troubleshooting

### Issue: "Environment variable not found"

**Solution:** Make sure you set the variables in Part 1 before deploying.

**Verify:**
```bash
gcloud run services describe oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313 \
    --format="value(spec.template.spec.containers[0].env)" | grep GOOGLE
```

### Issue: "Build failed"

**Solution:** Check the error message. Common issues:
- Network timeout: Try again
- Dockerfile error: Check logs
- Permission issues: Make sure you're authenticated

**Check logs:**
```bash
gcloud builds list --limit=1 --project=onyga-482313
```

### Issue: "Deployment failed"

**Solution:** 
1. Check Cloud Run logs:
   ```bash
   gcloud run services logs read oi-data-entry-app \
       --region=us-central1 \
       --project=onyga-482313 \
       --limit=50
   ```

2. Verify service exists:
   ```bash
   gcloud run services list --project=onyga-482313
   ```

### Issue: "OAuth still not working"

**Check these:**
1. Environment variables are set (see Part 1)
2. Redirect URI in Google Console matches your service URL
3. OAuth consent screen has test users added

**Get service URL:**
```bash
SERVICE_URL=$(gcloud run services describe oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313 \
    --format="value(status.url)")

echo "Redirect URI should be: $SERVICE_URL/auth/callback"
```

---

## Summary Checklist

- [ ] Set `GOOGLE_CLIENT_ID` environment variable in Cloud Run
- [ ] Set `GOOGLE_CLIENT_SECRET` environment variable in Cloud Run
- [ ] Verified environment variables are set
- [ ] Downloaded updated code from Cloud Storage
- [ ] Extracted the ZIP file
- [ ] Made deployment script executable
- [ ] Ran deployment script
- [ ] Deployment completed successfully
- [ ] Tested OAuth login

---

## Quick Reference Commands

```bash
# Set environment variables
gcloud run services update oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313 \
    --update-env-vars "GOOGLE_CLIENT_ID=405291422506-9gd1k58luauqfbn6bvu79u495ji93v5h.apps.googleusercontent.com,GOOGLE_CLIENT_SECRET=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"

# Verify environment variables
gcloud run services describe oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313 \
    --format="value(spec.template.spec.containers[0].env)" | grep GOOGLE

# Deploy code
cd ~/data-entry-app && \
gsutil cp gs://onyga-482313-temp-uploads/data-entry-app.zip . && \
unzip -o data-entry-app.zip && \
chmod +x deploy_minimal.sh && \
./deploy_minimal.sh

# Get service URL
gcloud run services describe oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313 \
    --format="value(status.url)"
```

---

## Need Help?

If you encounter any issues:
1. Check the error message carefully
2. Review Cloud Run logs
3. Verify environment variables are set
4. Check redirect URI in Google Console matches your service URL
