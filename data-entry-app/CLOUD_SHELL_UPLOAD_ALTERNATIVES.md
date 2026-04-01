# Cloud Shell Upload Alternatives

## Problem: Folder Upload Not Working

If clicking "select folder" does nothing, try these alternatives:

---

## Method 1: Upload ZIP File (Recommended)

### Step 1: Create ZIP on Your Mac

Open Terminal on your Mac and run:

```bash
cd "/Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI"
zip -r data-entry-app.zip data-entry-app/ -x "*venv/*" "*__pycache__/*" "*.git*" "*.DS_Store" "*.xlsx"
```

This creates `data-entry-app.zip` in the `OI` folder.

### Step 2: Upload ZIP to Cloud Shell

1. In Cloud Shell, click **"☰"** menu → **"Upload file"**
2. Click **"Select a file from your device"**
3. Choose `data-entry-app.zip` (single file upload works better!)
4. Wait for upload

### Step 3: Extract in Cloud Shell

```bash
unzip data-entry-app.zip
cd data-entry-app
```

---

## Method 2: Use Cloud Shell Editor (Create Files Manually)

If upload still fails, create files directly:

### Step 1: Open Editor

In Cloud Shell, click **"Open Editor"** button (pencil icon) or press `Ctrl+E` (Windows) / `Cmd+E` (Mac)

### Step 2: Create Folder Structure

1. Right-click in file explorer → **"New Folder"** → Name it `data-entry-app`
2. Create subfolders: `templates`, `excel_templates`

### Step 3: Copy Files One by One

For each file, you'll need to:
1. Open the file on your Mac
2. Copy all content
3. In Cloud Shell Editor, create new file with same name
4. Paste content
5. Save

**Essential files to copy:**
- `app.py`
- `requirements.txt`
- `Dockerfile`
- `.dockerignore`
- `.gcloudignore`
- `deploy_minimal.sh`
- All files in `templates/` folder

**You can skip:**
- `venv/` folder
- `__pycache__/`
- `.md` files (except README.md)
- Excel files
- Migration scripts

---

## Method 3: Use Git (If You Have a Repo)

### Step 1: Initialize Git Locally (if not done)

```bash
cd "/Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI/data-entry-app"
git init
git add .
git commit -m "Initial commit"
```

### Step 2: Push to GitHub/GitLab

```bash
# Create repo on GitHub first, then:
git remote add origin <your-repo-url>
git push -u origin main
```

### Step 3: Clone in Cloud Shell

```bash
# In Cloud Shell:
git clone <your-repo-url>
cd data-entry-app
```

---

## Method 4: Use gcloud Storage (Advanced)

### Step 1: Upload to Cloud Storage

```bash
# On your Mac:
cd "/Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI"
zip -r data-entry-app.zip data-entry-app/

# Upload to Cloud Storage
gsutil cp data-entry-app.zip gs://onyga-482313-temp/data-entry-app.zip
```

### Step 2: Download in Cloud Shell

```bash
# In Cloud Shell:
gsutil cp gs://onyga-482313-temp/data-entry-app.zip .
unzip data-entry-app.zip
cd data-entry-app
```

---

## Method 5: Copy-Paste via Terminal (Small Files)

For small files, you can use `cat`:

### In Cloud Shell:

```bash
mkdir -p data-entry-app
cd data-entry-app

# Create a file
cat > app.py << 'ENDOFFILE'
[paste your app.py content here]
ENDOFFILE
```

Then paste the file content between `ENDOFFILE` markers.

**Note:** This is tedious for many files, but works for critical ones.

---

## Recommended Approach

**Best option:** Method 1 (ZIP file upload)
- Most reliable
- Single file upload works better than folders
- Fastest method

**If ZIP fails:** Method 3 (Git)
- Most reliable long-term
- Easy to update later
- Professional approach

**Quick test:** Method 2 (Editor)
- Good for testing
- Can create files manually
- No upload needed

---

## Quick Test: Minimal Deployment

If you just want to test deployment, create these **minimum files** in Cloud Shell Editor:

1. **Dockerfile**
2. **requirements.txt**
3. **app.py** (simplified version)
4. **deploy_minimal.sh**

Then run deployment. You can add more files later.

---

## Need Help?

Tell me which method you're trying and what error you see!
