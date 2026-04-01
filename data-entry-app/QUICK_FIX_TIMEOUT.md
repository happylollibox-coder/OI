# Quick Fix for Upload Timeout

## Problem
`gcloud builds submit` times out immediately when uploading files from your local machine.

## Solution: Use Cloud Shell ⭐ (Easiest)

**Cloud Shell runs in Google's cloud** - no network timeouts!

### Steps:

1. **Open Cloud Shell**: https://console.cloud.google.com/cloudshell

2. **Upload your code**:
   - Click **"☰" menu** → **"Upload"**
   - Upload the `data-entry-app` folder
   - Or zip it first: `zip -r data-entry-app.zip data-entry-app/`

3. **Deploy**:
   ```bash
   cd data-entry-app
   chmod +x deploy_minimal.sh
   ./deploy_minimal.sh
   ```

**That's it!** Cloud Shell has direct access to Cloud Build - no timeouts.

---

## Alternative: Git-Based Deployment

If you prefer to stay local, use Git (avoids file upload):

```bash
cd data-entry-app
chmod +x deploy_via_git.sh
./deploy_via_git.sh
```

This pushes code to Cloud Source Repositories first, then builds from there.

---

## Why This Happens

Your local network/firewall is blocking or throttling the upload to Google Cloud Build. Cloud Shell bypasses this entirely.

**Recommendation**: Use Cloud Shell - it's the fastest and most reliable option.
