# Fix: app.py is Empty

## Problem Confirmed
`app.py` is missing or empty in Cloud Shell. This is why the deployment fails.

## Solution: Download app.py from Cloud Storage

I've uploaded `app.py` to Cloud Storage. Download it in Cloud Shell:

### Step 1: Download app.py

```bash
cd ~/data-entry-app

# Download the script
gsutil cp gs://onyga-482313-temp-uploads/download_app_py.sh .
chmod +x download_app_py.sh
./download_app_py.sh
```

Or download directly:

```bash
cd ~/data-entry-app
gsutil cp gs://onyga-482313-temp-uploads/app.py app.py

# Verify it downloaded
ls -lh app.py
head -10 app.py
```

### Step 2: Verify app.py has Content

```bash
# Check file size (should be > 0 bytes)
ls -lh app.py

# Check it defines 'app'
grep "app = Flask" app.py || grep "^app = " app.py

# Check first few lines
head -30 app.py
```

### Step 3: Deploy

Once app.py is downloaded and verified:

```bash
./verify_and_deploy.sh
```

---

## Alternative: Upload app.py Manually

If the Cloud Storage download doesn't work, upload app.py manually:

### Option A: Use Cloud Shell Editor

1. In Cloud Shell, click **"Open Editor"** (pencil icon)
2. Navigate to `data-entry-app` folder
3. Create new file `app.py`
4. Copy the entire content of app.py from your local machine
5. Paste into Cloud Shell Editor
6. Save

### Option B: Use Cloud Shell Upload

1. In Cloud Shell, click **"☰"** menu → **"Upload file"**
2. Select `app.py` from your local machine
3. Wait for upload

### Option C: Use Git (if you have a repo)

```bash
cd ~/data-entry-app
git clone <your-repo-url> temp-repo
cp temp-repo/data-entry-app/app.py .
rm -rf temp-repo
```

---

## After app.py is Fixed

Once app.py is downloaded/uploaded and has content:

```bash
cd ~/data-entry-app

# Verify it exists and has content
ls -lh app.py
head -30 app.py

# Deploy
./verify_and_deploy.sh
```

---

## Quick One-Liner

```bash
cd ~/data-entry-app && \
gsutil cp gs://onyga-482313-temp-uploads/app.py app.py && \
ls -lh app.py && \
./verify_and_deploy.sh
```

This will download app.py and immediately deploy!
