# CRITICAL FIX: app.py is Empty

## Problem
`app.py` is 0 bytes in the deployed image, causing `ImportError: cannot import name 'app' from 'app'`.

## Root Cause
OneDrive sync is causing `app.py` to be uploaded as 0 bytes.

## Solution: Verify and Fix in Cloud Shell

### Step 1: Download and Run Verification Script

```bash
cd ~/data-entry-app

# Download verification script
gsutil cp gs://onyga-482313-temp-uploads/verify_and_deploy.sh .
chmod +x verify_and_deploy.sh
./verify_and_deploy.sh
```

This script will:
1. ✅ Check if app.py exists and has content
2. ✅ Verify app.py defines the 'app' variable
3. ✅ Create missing files (main.py, requirements.txt, Dockerfile)
4. ✅ Build and deploy

---

## Step 2: If app.py is Empty, You Need to Recreate It

If the script says app.py is 0 bytes, you have two options:

### Option A: Download app.py from Source

If you have app.py in another location or git repo:

```bash
cd ~/data-entry-app

# Download from your source (replace URL with your actual source)
# Or copy from local machine if accessible
# Or recreate from scratch

# Then verify it has content
ls -lh app.py
head -30 app.py
```

### Option B: Create Minimal app.py (Temporary)

If you can't get the full app.py, create a minimal one to test:

```bash
cd ~/data-entry-app

cat > app.py << 'EOF'
from flask import Flask
import os

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'dev-secret-key')

@app.route('/')
def index():
    return {'status': 'error', 'message': 'Full app.py not deployed. Please ensure app.py is properly uploaded.'}, 500

# Add your routes here...
EOF

# Then deploy
./verify_and_deploy.sh
```

---

## Step 3: Ensure app.py is NOT Excluded

Check `.dockerignore` doesn't exclude app.py:

```bash
cd ~/data-entry-app

# Check .dockerignore
cat .dockerignore

# Make sure app.py is NOT listed
# If it is, remove that line
```

---

## Quick Test: Check What's Actually Deployed

```bash
# Check build logs to see if app.py was copied
gcloud builds log 2c0ce828-8343-48a1-9292-aaddd116657b --project=onyga-482313 | grep -i "app.py\|copy"

# Check file sizes in build
gcloud builds log 2c0ce828-8343-48a1-9292-aaddd116657b --project=onyga-482313 | grep -E "Step 6|COPY"
```

---

## Most Likely Solution

Run the verification script - it will tell you exactly what's wrong:

```bash
cd ~/data-entry-app
gsutil cp gs://onyga-482313-temp-uploads/verify_and_deploy.sh .
chmod +x verify_and_deploy.sh
./verify_and_deploy.sh
```

The script will check if app.py exists and has content before building. If it's empty, it will tell you and stop, so you can fix it first.
