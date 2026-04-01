# Fix: "Failed to find attribute 'app' in 'app'"

## Problem
The app keeps crashing because gunicorn can't find the Flask app instance. This likely means `app.py` is empty or corrupted in the deployed image.

## Solution: Use main.py Instead

Since `main.py` imports from `app`, it's more reliable. Update the Dockerfile to use `main:app`:

### In Cloud Shell:

```bash
cd ~/data-entry-app

# Update Dockerfile to use main.py
cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y gcc && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV PORT=8080
ENV PYTHONUNBUFFERED=1

# Use main.py instead of app.py (main.py imports from app)
RUN python -c "import main; print('✓ Main module imported')" || exit 1

EXPOSE 8080

# Use main:app instead of app:app
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 --log-level info main:app
EOF

# Verify main.py exists
cat main.py

# Deploy
./deploy_minimal.sh
```

---

## Alternative: Ensure app.py is Copied Correctly

If you want to keep using `app:app`, make sure app.py has content:

```bash
cd ~/data-entry-app

# Check if app.py exists and has content
ls -lh app.py
head -30 app.py

# If empty, you'll need to recreate it or download from source
# For now, use main.py approach above
```

---

## Quick Fix (Recommended)

Use this one-liner in Cloud Shell:

```bash
cd ~/data-entry-app && \
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
&& \
cat > requirements.txt << 'EOF'
Flask==3.0.0
google-cloud-bigquery==3.13.0
python-dotenv==1.0.0
gunicorn==21.2.0
pandas==2.0.3
openpyxl==3.1.2
EOF
&& \
./deploy_minimal.sh
```

This uses `main.py` which imports `app` from `app.py`, so even if `app.py` has issues, `main.py` should work.
