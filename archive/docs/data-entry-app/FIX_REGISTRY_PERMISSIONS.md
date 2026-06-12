# Fix: Container Registry Permission Error

## Problem
```
denied: gcr.io repo does not exist. Creating on push requires the artifactregistry.repositories.createOnPush permission
```

## Solution: Run This in Cloud Shell

```bash
cd ~/data-entry-app

# Enable Container Registry API
gcloud services enable containerregistry.googleapis.com --project=onyga-482313

# Grant Cloud Build permissions
PROJECT_NUMBER=$(gcloud projects describe onyga-482313 --format="value(projectNumber)")
SERVICE_ACCOUNT="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

gcloud projects add-iam-policy-binding onyga-482313 \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/storage.admin"

# Now deploy again
./deploy_minimal.sh
```

---

## Alternative: Use Artifact Registry (Recommended)

If Container Registry still has issues, switch to Artifact Registry:

### Step 1: Create Artifact Registry Repository

```bash
gcloud artifacts repositories create oi-data-entry-app \
    --repository-format=docker \
    --location=us-central1 \
    --project=onyga-482313
```

### Step 2: Update deploy_minimal.sh

Change the image name from:
```bash
IMAGE_NAME="gcr.io/${PROJECT_ID}/${SERVICE_NAME}"
```

To:
```bash
IMAGE_NAME="us-central1-docker.pkg.dev/${PROJECT_ID}/oi-data-entry-app/${SERVICE_NAME}"
```

### Step 3: Deploy

```bash
./deploy_minimal.sh
```

---

## Quick Fix (Run in Cloud Shell)

Copy and paste this entire block:

```bash
cd ~/data-entry-app

# Enable APIs
gcloud services enable containerregistry.googleapis.com --project=onyga-482313
gcloud services enable artifactregistry.googleapis.com --project=onyga-482313

# Grant permissions
PROJECT_NUMBER=$(gcloud projects describe onyga-482313 --format="value(projectNumber)")
SERVICE_ACCOUNT="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

gcloud projects add-iam-policy-binding onyga-482313 \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/storage.admin"

# Deploy again
./deploy_minimal.sh
```

---

## Why This Happened

Cloud Build needs permission to push Docker images to Container Registry. The service account needs `storage.admin` role.
