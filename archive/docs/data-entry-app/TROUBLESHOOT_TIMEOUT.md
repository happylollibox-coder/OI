# Troubleshooting Upload Timeout

## Problem
`gcloud builds submit` times out when uploading files:
```
ERROR: (gcloud.builds.submit) [Errno 60] Operation timed out
```

## Solutions

### Option 1: Use Cloud Shell (Recommended) ⭐

Cloud Shell has better network connectivity:

1. **Open Cloud Shell**: https://console.cloud.google.com/cloudshell
2. **Upload your project**:
   ```bash
   # In Cloud Shell, click "Upload" button
   # Upload the entire data-entry-app folder
   ```
3. **Deploy from Cloud Shell**:
   ```bash
   cd data-entry-app
   ./deploy_minimal.sh
   ```

### Option 2: Try Minimal Upload

I've fixed `.gcloudignore` to exclude unnecessary files. Try again:

```bash
cd "/Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI/data-entry-app"
./deploy_minimal.sh
```

### Option 3: Use Git Repository

If upload keeps failing, use Cloud Source Repositories:

```bash
# 1. Initialize git (if not already)
cd data-entry-app
git init
git add .
git commit -m "Initial commit"

# 2. Create Cloud Source Repository
gcloud source repos create oi-data-entry-app --project=onyga-482313

# 3. Push to Cloud Source
git remote add google https://source.developers.google.com/p/onyga-482313/r/oi-data-entry-app
git push google main

# 4. Build from repository
gcloud builds submit --config=cloudbuild.yaml \
    --source=https://source.developers.google.com/p/onyga-482313/r/oi-data-entry-app \
    --project=onyga-482313
```

### Option 4: Check Network/Firewall

If timeout persists:
- Check firewall settings
- Try different network (mobile hotspot, VPN off)
- Increase timeout: `--timeout=60m`

## What I Fixed

✅ Updated `.gcloudignore` to:
- Keep `Dockerfile` and `.dockerignore` (they were excluded!)
- Exclude all `.md` files except `README.md`
- Exclude utility scripts and templates
- Reduce upload size significantly

## Current Status

The `.gcloudignore` file has been optimized. Try `./deploy_minimal.sh` again, or use Cloud Shell for best results.
