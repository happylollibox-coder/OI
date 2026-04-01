# Complete Guide: Deploy via Google Cloud Shell

## What is Cloud Shell?

**Google Cloud Shell** is a free, browser-based terminal that runs in Google's cloud infrastructure. It has:
- ✅ Direct, fast access to Google Cloud services
- ✅ Pre-installed `gcloud`, `docker`, `git`, and other tools
- ✅ 5GB of persistent storage
- ✅ No upload timeout issues!

---

## Step-by-Step Instructions

### Step 1: Open Cloud Shell

1. **Go to**: https://console.cloud.google.com/
2. **Make sure you're in the correct project**: 
   - Check the project dropdown at the top (should show `onyga-482313`)
   - If not, click it and select `onyga-482313`
3. **Open Cloud Shell**:
   - Click the **"Activate Cloud Shell"** icon (looks like `>_`) in the top-right toolbar
   - Or go directly to: https://console.cloud.google.com/cloudshell
4. **Wait for Cloud Shell to load** (first time takes ~30 seconds)

You'll see a terminal window at the bottom of your browser.

---

### Step 2: Prepare Your Code for Upload

**Option A: Upload the entire folder (Easiest)**

1. **On your local machine**, navigate to:
   ```
   /Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI/
   ```

2. **Create a zip file** (optional but recommended):
   ```bash
   cd "/Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI"
   zip -r data-entry-app.zip data-entry-app/ -x "*.git*" "*venv/*" "*__pycache__/*" "*.DS_Store"
   ```

**Option B: Upload individual files** (if zip doesn't work)

Just upload the folder as-is.

---

### Step 3: Upload Files to Cloud Shell

**Method 1: Using Cloud Shell Upload Button**

1. In Cloud Shell, click the **"☰" (three horizontal lines)** menu icon in the top-right
2. Click **"Upload file"**
3. Select your `data-entry-app.zip` file (or the `data-entry-app` folder)
4. Wait for upload to complete (you'll see progress)

**Method 2: Using Drag & Drop**

1. In Cloud Shell, click the **"☰"** menu
2. Click **"Upload file"**
3. Drag and drop your `data-entry-app.zip` file into the upload area

**Method 3: Using `gcloud` command** (if you have files on your machine)

```bash
# In Cloud Shell, run:
gcloud cloud-shell scp local:~/path/to/data-entry-app.zip cloudshell:~/data-entry-app.zip
```

---

### Step 4: Extract and Navigate (if you zipped)

```bash
# In Cloud Shell terminal:
unzip data-entry-app.zip
cd data-entry-app
```

If you uploaded the folder directly, just:
```bash
cd data-entry-app
```

---

### Step 5: Verify Files Are There

```bash
# List files to make sure everything uploaded
ls -la

# You should see:
# - app.py
# - requirements.txt
# - Dockerfile
# - templates/
# - deploy_minimal.sh
# etc.
```

---

### Step 6: Make Script Executable

```bash
chmod +x deploy_minimal.sh
```

---

### Step 7: Run Deployment

```bash
./deploy_minimal.sh
```

**What happens:**
1. ✅ Builds Docker image (5-10 minutes)
   - You'll see: `🔨 Building Docker image...`
   - Progress updates will appear
2. ✅ Deploys to Cloud Run (2-3 minutes)
   - You'll see: `🚀 Deploying to Cloud Run...`
3. ✅ Shows your URL
   - You'll see: `✅ Deployment successful!`
   - URL: `https://oi-data-entry-app-xxxxx-uc.a.run.app`

---

### Step 8: Test Your App

1. Copy the URL from the deployment output
2. Open it in a new browser tab
3. Your app should load!

---

## Troubleshooting

### "Permission denied" when running script
```bash
chmod +x deploy_minimal.sh
```

### "Command not found: gcloud"
Cloud Shell should have `gcloud` pre-installed. If not:
```bash
gcloud components update
```

### "Project not found"
Set the project:
```bash
gcloud config set project onyga-482313
```

### Upload failed
- Try zipping the folder first
- Try uploading smaller batches
- Use Method 3 (gcloud scp) if available

### Build fails
Check the error message. Common issues:
- Missing `Dockerfile` → Make sure it uploaded
- Missing `requirements.txt` → Check files are there
- API not enabled → Script should enable it automatically

---

## Alternative: Create Files Directly in Cloud Shell

If upload is problematic, you can create files directly:

1. **In Cloud Shell**, click the **pencil icon** (editor) or **"Open Editor"**
2. **Create new files** or **edit existing ones**
3. **Copy/paste** content from your local files
4. **Save** (Ctrl+S or Cmd+S)
5. **Run deployment** as above

---

## What Happens After Deployment?

✅ Your app is **live 24/7**
✅ Accessible from **anywhere in the world**
✅ **No need to keep your computer on**
✅ **Automatic scaling** (handles traffic spikes)

---

## Updating Your App Later

1. **Make changes** to your local code
2. **Upload again** to Cloud Shell (or edit directly)
3. **Run** `./deploy_minimal.sh` again
4. **New version** deploys automatically!

---

## Quick Reference Commands

```bash
# Navigate to your app
cd ~/data-entry-app

# Check files
ls -la

# Deploy
./deploy_minimal.sh

# Check deployment status
gcloud run services list --project=onyga-482313

# View logs
gcloud run services logs read oi-data-entry-app --region=us-central1 --project=onyga-482313
```

---

## Need Help?

If you get stuck:
1. Check the error message carefully
2. Make sure all files uploaded correctly
3. Verify you're in the correct project (`onyga-482313`)
4. Check Cloud Shell has enough space: `df -h`

---

**That's it!** Cloud Shell makes deployment much easier than dealing with local network timeouts. 🚀
