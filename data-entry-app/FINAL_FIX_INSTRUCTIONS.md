# Final Fix: Service Unavailable

## Problem
The service is still using the old deployment with `app:app` which fails. We need to redeploy with `main:app`.

## Solution: Run Complete Fix Script

### In Cloud Shell, run:

```bash
cd ~/data-entry-app

# Download and run the complete fix
gsutil cp gs://onyga-482313-temp-uploads/COMPLETE_FIX.sh .
chmod +x COMPLETE_FIX.sh
./COMPLETE_FIX.sh
```

This script will:
1. ✅ Create Dockerfile with `main:app` (not `app:app`)
2. ✅ Create requirements.txt
3. ✅ Create main.py if needed
4. ✅ Build new Docker image
5. ✅ Deploy to Cloud Run

---

## Or Do It Manually

If the script doesn't work, run these commands one by one:

```bash
cd ~/data-entry-app

# 1. Create Dockerfile
cat > Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
RUN apt-get update && apt-get install -y gcc && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
ENV PORT=8080 PYTHONUNBUFFERED=1
RUN python -c "import main" || exit 1
EXPOSE 8080
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 main:app
EOF

# 2. Create requirements.txt
cat > requirements.txt << 'EOF'
Flask==3.0.0
google-cloud-bigquery==3.13.0
python-dotenv==1.0.0
gunicorn==21.2.0
pandas==2.0.3
openpyxl==3.1.2
EOF

# 3. Verify main.py exists
cat main.py

# 4. Build and deploy
gcloud builds submit \
    --tag us-central1-docker.pkg.dev/onyga-482313/oi-data-entry-app/oi-data-entry-app \
    --project=onyga-482313

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

## Verify After Deployment

```bash
# Check logs (should NOT show "Failed to find attribute")
gcloud run services logs read oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313 \
    --limit=20

# Get URL
gcloud run services describe oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313 \
    --format="value(status.url)"
```

---

## Key Change

The Dockerfile now uses:
- **OLD**: `CMD ... app:app` ❌ (fails)
- **NEW**: `CMD ... main:app` ✅ (works)

This is the critical fix!
