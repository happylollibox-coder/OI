# Fix: ImportError: cannot import name 'app' from 'app'

## Problem
The `app.py` file is empty or corrupted in the deployed image, so `main.py` can't import the Flask app.

## Solution: Create app.py directly in Cloud Shell

### In Cloud Shell, run:

```bash
cd ~/data-entry-app

# First, check if app.py exists and has content
ls -lh app.py
head -30 app.py

# If app.py is empty or missing, you need to recreate it
# Since app.py is large, we'll need to ensure it's properly uploaded
```

---

## Better Solution: Use a wrapper that creates app if missing

Create a new `wsgi.py` file that handles this:

```bash
cd ~/data-entry-app

# Create wsgi.py as entry point
cat > wsgi.py << 'EOF'
"""
WSGI entry point for Cloud Run
"""
import os
import sys

# Try to import app from app.py
try:
    from app import app
except ImportError:
    # If app.py is missing, create a minimal Flask app
    from flask import Flask
    app = Flask(__name__)
    app.secret_key = os.environ.get('SECRET_KEY', 'dev-secret-key')
    
    @app.route('/')
    def health():
        return {'status': 'error', 'message': 'app.py not found. Please ensure app.py is properly deployed.'}, 500

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)
EOF

# Update Dockerfile to use wsgi.py
cat > Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
RUN apt-get update && apt-get install -y gcc && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
ENV PORT=8080 PYTHONUNBUFFERED=1
EXPOSE 8080
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 --log-level info wsgi:app
EOF

# Deploy
gcloud builds submit --tag us-central1-docker.pkg.dev/onyga-482313/oi-data-entry-app/oi-data-entry-app --project=onyga-482313
gcloud run deploy oi-data-entry-app --image us-central1-docker.pkg.dev/onyga-482313/oi-data-entry-app/oi-data-entry-app --platform managed --region us-central1 --allow-unauthenticated --set-env-vars "GCP_PROJECT_ID=onyga-482313,BIGQUERY_DATASET=OI" --memory 512Mi --cpu 1 --timeout 300 --max-instances 10 --project=onyga-482313
```

---

## Best Solution: Ensure app.py is properly included

The real issue is that `app.py` isn't being copied correctly. Let's verify it's in the build:

```bash
cd ~/data-entry-app

# Check file size (should NOT be 0)
ls -lh app.py

# If it's 0 bytes, you need to get the actual app.py content
# Check if it exists locally and copy it properly

# Create a .dockerignore that doesn't exclude app.py
cat > .dockerignore << 'EOF'
.git
.gitignore
__pycache__
*.pyc
*.pyo
*.pyd
venv
.venv
env
.env
.idea
.vscode
*.log
.DS_Store
*.xlsx
*.xls
*.md
!README.md
migrate_po_ids.py
backup_tables.py
fix_remaining_po_ids.py
parse_2025_data.py
truncate_and_reimport.py
load_excel_data.py
create_excel_templates.py
check_streaming_buffer.py
excel_templates
# DO NOT exclude app.py!
EOF

# Rebuild ensuring app.py is included
gcloud builds submit --tag us-central1-docker.pkg.dev/onyga-482313/oi-data-entry-app/oi-data-entry-app --project=onyga-482313
```

---

## Quick Diagnostic

Run this to see what's actually in the container:

```bash
# Check what files are in the latest image
gcloud builds log 2c0ce828-8343-48a1-9292-aaddd116657b --project=onyga-482313 | grep -E "app.py|COPY app"
```

The issue is that `app.py` is either:
1. Not being copied to the Docker image
2. Being copied as 0 bytes
3. Being excluded by .dockerignore
