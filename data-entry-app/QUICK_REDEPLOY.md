# Quick Redeploy Instructions

## In Cloud Shell, run:

```bash
cd ~/data-entry-app

# Make sure you have the latest code
gsutil cp gs://onyga-482313-temp-uploads/data-entry-app.zip .
unzip -o data-entry-app.zip

# Verify Dockerfile has the fix
grep "import app" Dockerfile

# Deploy
./deploy_minimal.sh
```

---

## Or deploy directly:

```bash
cd ~/data-entry-app

# Build
gcloud builds submit \
    --tag us-central1-docker.pkg.dev/onyga-482313/oi-data-entry-app/oi-data-entry-app \
    --project=onyga-482313

# Deploy
gcloud run deploy oi-data-entry-app \
    --image us-central1-docker.pkg.dev/onyga-482313/oi-data-entry-app/oi-data-entry-app \
    --platform managed \
    --region us-central1 \
    --allow-unauthenticated \
    --set-env-vars "GCP_PROJECT_ID=onyga-482313,BIGQUERY_DATASET=OI" \
    --memory 512Mi \
    --cpu 1 \
    --timeout 300 \
    --max-instances 10 \
    --project=onyga-482313
```

---

## Check deployment status:

```bash
gcloud run services describe oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313 \
    --format="value(status.url)"
```

---

## View logs:

```bash
gcloud run services logs read oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313 \
    --limit=50
```
