# Fix: Empty Page Issue

## Problem
App returns 200 OK but page is empty (`content-length: 0`).

## Likely Causes
1. **BigQuery query failing** - The `get_purchase_orders_with_status()` function might be failing
2. **Templates missing** - Templates folder might not be in the Docker image
3. **Exception being caught** - Errors might be silently caught

## Solution: Add Error Handling and Check Logs

### Step 1: Check if Templates are in the Image

In Cloud Shell, verify templates were copied:

```bash
cd ~/data-entry-app

# Check if templates folder exists
ls -la templates/

# If missing or empty, download from Cloud Storage
gsutil -m cp -r gs://onyga-482313-temp-uploads/templates/*.html templates/

# Verify they have content
ls -lh templates/*.html
```

### Step 2: Add Better Error Logging

The app might be catching exceptions. Let's add a test route to see if the app is working:

```bash
cd ~/data-entry-app

# Add a simple test route to app.py (temporarily)
# Edit app.py and add this before the index route:

cat >> app.py << 'EOF'

@app.route('/test')
def test():
    """Test route to verify app is working"""
    try:
        from google.cloud import bigquery
        client = bigquery.Client()
        return f"✅ App is working! BigQuery client created. Project: {client.project}"
    except Exception as e:
        return f"❌ Error: {str(e)}", 500
EOF

# Redeploy
./verify_and_deploy.sh
```

### Step 3: Check BigQuery Permissions

The app needs BigQuery access. Check if Cloud Run service account has permissions:

```bash
# Get Cloud Run service account
PROJECT_NUMBER=$(gcloud projects describe onyga-482313 --format="value(projectNumber)")
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# Grant BigQuery permissions
gcloud projects add-iam-policy-binding onyga-482313 \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/bigquery.dataViewer"

gcloud projects add-iam-policy-binding onyga-482313 \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/bigquery.jobUser"
```

### Step 4: Test the Routes

After redeploying, test:

```bash
# Test route
curl https://oi-data-entry-app-405291422506.us-central1.run.app/test

# Main route
curl -v https://oi-data-entry-app-405291422506.us-central1.run.app/
```

---

## Quick Fix: Ensure Templates are Included

Most likely, templates folder is missing. In Cloud Shell:

```bash
cd ~/data-entry-app

# Download templates
gsutil -m cp -r gs://onyga-482313-temp-uploads/templates/*.html templates/

# Verify
ls -lh templates/

# Rebuild and redeploy
./verify_and_deploy.sh
```

---

## Check Current Deployment

```bash
# Check what's actually deployed
gcloud run revisions describe oi-data-entry-app-00005-npf \
    --region=us-central1 \
    --project=onyga-482313 \
    --format="yaml(spec.containers[0].image)"

# Check logs for any errors
gcloud run services logs read oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313 \
    --limit=100 | grep -i "error\|exception\|traceback"
```

The empty page is likely because:
1. Templates folder is missing/empty
2. BigQuery query is failing
3. Exception is being silently caught

Start by ensuring templates are included in the deployment!
