# Cloud Shell Quick Start (5 Minutes)

## Fastest Way to Deploy

### 1. Open Cloud Shell
👉 https://console.cloud.google.com/cloudshell

### 2. Upload Your Code
- Click **"☰"** menu → **"Upload file"**
- Upload `data-entry-app` folder (or zip it first)

### 3. Extract (if zipped)
```bash
unzip data-entry-app.zip
cd data-entry-app
```

### 4. Deploy
```bash
chmod +x deploy_minimal.sh
./deploy_minimal.sh
```

### 5. Wait & Get URL
⏱️ Takes 7-13 minutes total
✅ You'll get a URL like: `https://oi-data-entry-app-xxxxx-uc.a.run.app`

---

## That's It!

Your app is now live 24/7! 🎉

---

## If Upload Fails

**Option 1: Zip first**
```bash
# On your Mac:
cd "/Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI"
zip -r data-entry-app.zip data-entry-app/ -x "*venv/*" "*__pycache__/*"
```

**Option 2: Use Cloud Shell Editor**
- Click **"Open Editor"** in Cloud Shell
- Create files manually
- Copy/paste content from your local files

**Option 3: Use Git** (if you have a repo)
```bash
# In Cloud Shell:
git clone <your-repo-url>
cd data-entry-app
./deploy_minimal.sh
```
