# Fix: "Failed to find attribute 'app' in 'app'"

## Problem
Gunicorn can't find the Flask app instance. This usually means:
1. Import error in app.py preventing it from loading
2. Missing dependencies
3. Environment variables not set

## Solution: Update Dockerfile with Better Error Handling

### In Cloud Shell, update the Dockerfile:

```bash
cd ~/data-entry-app

cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Set environment variables
ENV PORT=8080
ENV PYTHONUNBUFFERED=1

# Verify app.py can be imported
RUN python -c "import app; print('App imported successfully'); print(dir(app))" || echo "Import check failed"

# Expose port
EXPOSE 8080

# Run gunicorn with better error messages
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 --log-level debug app:app
EOF

# Rebuild and redeploy
./deploy_minimal.sh
```

---

## Alternative: Check What's Actually Deployed

```bash
# Check if app.py exists in container
gcloud run services describe oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313 \
    --format="value(spec.template.spec.containers[0].image)"

# Check logs for import errors
gcloud run services logs read oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313 \
    --limit=100 | grep -i "error\|import\|traceback"
```

---

## Quick Fix: Try Using main.py Instead

If app.py has import issues, try using main.py:

```bash
cd ~/data-entry-app

# Update Dockerfile CMD to use main.py
sed -i 's/app:app/main:app/g' Dockerfile

# Or manually edit Dockerfile, change last line to:
# CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 main:app

# Redeploy
./deploy_minimal.sh
```

---

## Most Likely Issue: Missing Environment Variables

The app might be failing because BigQuery credentials aren't set. Check if you need to set:

```bash
gcloud run services update oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313 \
    --set-env-vars "GCP_PROJECT_ID=onyga-482313,BIGQUERY_DATASET=OI,GOOGLE_APPLICATION_CREDENTIALS=/tmp/credentials.json"
```

But actually, Cloud Run should use the default service account automatically.

---

## Debug: Test Import Locally First

Before deploying, test in Cloud Shell:

```bash
cd ~/data-entry-app

# Try importing app
python3 -c "import app; print('Success'); print(app.app)"

# If that fails, check what's wrong
python3 -c "import app" 2>&1
```

This will show you the actual import error.
