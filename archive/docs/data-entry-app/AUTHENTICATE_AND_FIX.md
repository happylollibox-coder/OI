# Fix Authentication and Complete Deployment

## Problem
Cloud Shell needs to authenticate with gcloud.

## Solution: Authenticate and Deploy

### Step 1: Authenticate

In Cloud Shell, run:

```bash
# Authenticate (will open browser)
gcloud auth login

# Set project
gcloud config set project onyga-482313

# Verify
gcloud auth list
```

### Step 2: Run Complete Fix Script

```bash
cd ~/data-entry-app

# Download and run the complete fix script
gsutil cp gs://onyga-482313-temp-uploads/FIX_AUTH_AND_DEPLOY.sh .
chmod +x FIX_AUTH_AND_DEPLOY.sh
./FIX_AUTH_AND_DEPLOY.sh
```

This script will:
1. ✅ Authenticate you
2. ✅ Download templates
3. ✅ Grant BigQuery permissions
4. ✅ Verify all files
5. ✅ Build and deploy

---

## Or Do It Manually

### 1. Authenticate

```bash
gcloud auth login
gcloud config set project onyga-482313
```

### 2. Grant BigQuery Permissions

```bash
PROJECT_NUMBER=$(gcloud projects describe onyga-482313 --format="value(projectNumber)")
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

gcloud projects add-iam-policy-binding onyga-482313 \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/bigquery.dataViewer"

gcloud projects add-iam-policy-binding onyga-482313 \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/bigquery.jobUser"

gcloud projects add-iam-policy-binding onyga-482313 \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/bigquery.dataEditor"
```

### 3. Download Templates

```bash
cd ~/data-entry-app
gsutil -m cp -r gs://onyga-482313-temp-uploads/templates/*.html templates/
ls -lh templates/
```

### 4. Deploy

```bash
./verify_and_deploy.sh
```

---

## Quick One-Liner

```bash
gcloud auth login && \
gcloud config set project onyga-482313 && \
cd ~/data-entry-app && \
gsutil cp gs://onyga-482313-temp-uploads/FIX_AUTH_AND_DEPLOY.sh . && \
chmod +x FIX_AUTH_AND_DEPLOY.sh && \
./FIX_AUTH_AND_DEPLOY.sh
```

---

## After Authentication

Once authenticated, the script will:
- Download templates (fix empty page)
- Grant BigQuery permissions (fix data access)
- Rebuild and redeploy

Then your app should work! 🎉
