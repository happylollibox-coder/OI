# Fix: Dockerfile is Empty

## Problem
The Dockerfile in the ZIP is 0 bytes (empty), causing build failure.

## Quick Fix: Create Dockerfile in Cloud Shell

### In Cloud Shell, run these commands:

```bash
cd ~/data-entry-app

# Create Dockerfile
cat > Dockerfile << 'EOF'
# Use Python 3.11 slim image
FROM python:3.11-slim

# Set working directory
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

# Expose port
EXPOSE 8080

# Run gunicorn
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 app:app
EOF

# Verify it was created
cat Dockerfile

# Now deploy
chmod +x deploy_minimal.sh
./deploy_minimal.sh
```

---

## Alternative: Verify All Files Are There

Before deploying, check that essential files exist:

```bash
cd ~/data-entry-app

# Check file sizes (should NOT be 0)
ls -lh Dockerfile requirements.txt app.py

# If any are 0 bytes, recreate them
```

---

## Why This Happened

OneDrive sync may not have fully downloaded files before zipping, resulting in empty files.

---

## After Fixing

Run deployment again:
```bash
./deploy_minimal.sh
```
