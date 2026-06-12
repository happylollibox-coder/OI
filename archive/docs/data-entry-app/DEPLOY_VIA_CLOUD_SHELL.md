# Deploy via Google Cloud Shell (Recommended)

## Why Cloud Shell?

Your local network is timing out when uploading files. **Cloud Shell runs in Google's infrastructure** and has direct, fast access to Cloud Build - no upload timeouts!

## Steps

### 1. Open Cloud Shell
Go to: **https://console.cloud.google.com/cloudshell**

### 2. Upload Your Project

**Option A: Upload via Web UI**
- In Cloud Shell, click the **"☰" menu** (top right)
- Click **"Upload"**
- Select your entire `data-entry-app` folder
- Wait for upload to complete

**Option B: Use Git (if you have a repo)**
```bash
git clone <your-repo-url>
cd data-entry-app
```

**Option C: Create files directly**
- Copy/paste files one by one using Cloud Shell editor

### 3. Deploy from Cloud Shell

```bash
cd data-entry-app

# Make script executable
chmod +x deploy_minimal.sh

# Run deployment
./deploy_minimal.sh
```

### 4. Get Your URL

After deployment completes, you'll see:
```
✅ Deployment successful!
🌐 Your service is live at:
   https://oi-data-entry-app-xxxxx-uc.a.run.app
```

## Why This Works

- ✅ Cloud Shell has **direct network path** to Cloud Build
- ✅ No local firewall/proxy issues
- ✅ Uploads are **much faster**
- ✅ No timeout errors

---

## Alternative: Use Cloud Source Repositories

If Cloud Shell doesn't work, we can set up Git-based deployment:

1. Push code to Cloud Source Repositories
2. Build directly from repository (no file upload needed)

Let me know if you want to set this up!
