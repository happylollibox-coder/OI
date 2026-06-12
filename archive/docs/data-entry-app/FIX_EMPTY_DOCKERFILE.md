# Fix: Empty Dockerfile Error

## Problem
```
Error response from daemon: the Dockerfile (Dockerfile) cannot be empty
```

This happens because OneDrive sync causes files to appear as 0 bytes.

## Solution: Create Files Directly in Cloud Shell

### Step 1: Create Essential Files

Run this in Cloud Shell:

```bash
cd ~/data-entry-app

# Download the file creation script
gsutil cp gs://onyga-482313-temp-uploads/create_files_in_cloudshell.sh .
chmod +x create_files_in_cloudshell.sh
./create_files_in_cloudshell.sh
```

### Step 2: Or Create Manually

```bash
cd ~/data-entry-app

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV PORT=8080
ENV PYTHONUNBUFFERED=1

RUN python -c "import app; print('✓ App imported')" || exit 1

EXPOSE 8080

CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 --log-level info app:app
EOF

# Create requirements.txt if empty
cat > requirements.txt << 'EOF'
Flask==3.0.0
google-cloud-bigquery==3.13.0
python-dotenv==1.0.0
gunicorn==21.2.0
pandas==2.0.3
openpyxl==3.1.2
EOF

# Verify files exist and have content
ls -lh Dockerfile requirements.txt
cat Dockerfile
```

### Step 3: Deploy

```bash
./deploy_minimal.sh
```

---

## Quick One-Liner Fix

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
RUN python -c "import app" || exit 1
EXPOSE 8080
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 app:app
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

---

## Verify Before Deploying

Always check file sizes before deploying:

```bash
# Should NOT be 0 bytes
ls -lh Dockerfile requirements.txt app.py

# Should show content
head -5 Dockerfile
head -3 requirements.txt
```

If any file is 0 bytes, recreate it using the commands above.
