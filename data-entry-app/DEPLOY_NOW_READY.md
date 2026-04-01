# ✅ Setup Complete! Ready to Deploy

## What I Just Did

✅ **APIs Enabled**: Artifact Registry, Cloud Build, Cloud Run  
✅ **Repository Created**: Artifact Registry repository `oi-data-entry-app`  
✅ **Permissions Granted**: Cloud Build can now push images  

## Now Deploy from Cloud Shell

The setup is complete! Now you just need to deploy from Cloud Shell (where uploads work):

### Step 1: Download Updated Code

In Cloud Shell:

```bash
# Download the updated ZIP with fixed deploy script
gsutil cp gs://onyga-482313-temp-uploads/data-entry-app.zip .
unzip -o data-entry-app.zip
cd data-entry-app
```

### Step 2: Verify Dockerfile Exists

```bash
# Check Dockerfile (should NOT be empty)
ls -lh Dockerfile
cat Dockerfile
```

If Dockerfile is empty, create it:

```bash
cat > Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
RUN apt-get update && apt-get install -y gcc && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
ENV PORT=8080
ENV PYTHONUNBUFFERED=1
EXPOSE 8080
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 app:app
EOF
```

### Step 3: Deploy

```bash
chmod +x deploy_minimal.sh
./deploy_minimal.sh
```

This will:
1. Build Docker image → Push to Artifact Registry ✅
2. Deploy to Cloud Run ✅
3. Give you the URL ✅

---

## What Changed

The `deploy_minimal.sh` script now uses **Artifact Registry** instead of Container Registry:
- Old: `gcr.io/onyga-482313/oi-data-entry-app`
- New: `us-central1-docker.pkg.dev/onyga-482313/oi-data-entry-app/oi-data-entry-app`

This avoids all the permission issues!

---

## Expected Output

After running `./deploy_minimal.sh`, you'll see:

```
✅ Build successful!
🚀 Step 2: Deploying to Cloud Run...
✅ Deployment successful!
🌐 Your service is live at:
   https://oi-data-entry-app-xxxxx-uc.a.run.app
```

---

## If You Get Errors

**Dockerfile empty?** → Create it using the command above  
**Requirements.txt empty?** → Create it:
```bash
cat > requirements.txt << 'EOF'
Flask==3.0.0
google-cloud-bigquery==3.13.0
python-dotenv==1.0.0
gunicorn==21.2.0
pandas==2.0.3
openpyxl==3.1.2
EOF
```

**Permission errors?** → Already fixed! Setup is complete.

---

**Everything is ready - just deploy from Cloud Shell!** 🚀
