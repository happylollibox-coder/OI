# Deployment Guide - Making the App Available from Different Computers

## Current Setup

The application is configured to listen on `0.0.0.0`, which means it can accept connections from other computers on your network. However, by default it runs on `localhost:5000` which is only accessible from the same machine.

## Option 1: Local Network Access (Quick & Simple)

### For Development/Testing

1. **Find your computer's IP address:**
   ```bash
   # On macOS/Linux
   ifconfig | grep "inet " | grep -v 127.0.0.1
   
   # On Windows
   ipconfig
   ```
   Look for something like `192.168.1.100` or `10.0.0.50`

2. **Run the application:**
   ```bash
   cd data-entry-app
   source venv/bin/activate
   python app.py
   ```

3. **Access from other computers:**
   - From other computers on the same network, open: `http://YOUR_IP_ADDRESS:5000`
   - Example: `http://192.168.1.100:5000`

4. **Firewall Configuration:**
   - macOS: System Preferences → Security & Privacy → Firewall → Allow incoming connections
   - Windows: Windows Defender Firewall → Allow an app → Python
   - Linux: `sudo ufw allow 5000/tcp`

**Limitations:**
- Only works on the same local network
- Computer must be running
- Not secure for production (no HTTPS, no authentication)

## Option 2: Google Cloud Run (Recommended for Production)

Deploy to Google Cloud Run for a fully managed, scalable solution accessible from anywhere.

### Prerequisites

```bash
# Install Google Cloud SDK if not already installed
# https://cloud.google.com/sdk/docs/install

# Authenticate
gcloud auth login
gcloud config set project onyga-482313
```

### Deployment Steps

1. **Create a Dockerfile:**
   ```dockerfile
   FROM python:3.9-slim

   WORKDIR /app

   COPY requirements.txt .
   RUN pip install --no-cache-dir -r requirements.txt

   COPY . .

   ENV PORT=8080
   CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 app:app
   ```

2. **Create app.yaml for App Engine (Alternative):**
   ```yaml
   runtime: python39

   env_variables:
     GCP_PROJECT_ID: "onyga-482313"
     BIGQUERY_DATASET: "OI"
     SECRET_KEY: "your-secret-key-here"
   ```

3. **Deploy to Cloud Run:**
   ```bash
   # Build and deploy
   gcloud run deploy data-entry-forms \
     --source . \
     --platform managed \
     --region us-central1 \
     --allow-unauthenticated \
     --set-env-vars GCP_PROJECT_ID=onyga-482313,BIGQUERY_DATASET=OI
   ```

4. **Access your app:**
   - Cloud Run will provide a URL like: `https://data-entry-forms-xxxxx.run.app`
   - This URL is accessible from anywhere with internet access

**Benefits:**
- ✅ Accessible from anywhere
- ✅ HTTPS automatically enabled
- ✅ Auto-scaling
- ✅ Managed by Google
- ✅ Pay only for what you use

## Option 3: Google App Engine

### Deploy to App Engine

1. **Create `app.yaml`:**
   ```yaml
   runtime: python39

   instance_class: F1

   env_variables:
     GCP_PROJECT_ID: "onyga-482313"
     BIGQUERY_DATASET: "OI"
     SECRET_KEY: "your-secret-key-here"
   ```

2. **Deploy:**
   ```bash
   gcloud app deploy
   ```

3. **Access:**
   - Your app will be at: `https://onyga-482313.appspot.com`
   - Or custom domain if configured

## Option 4: Compute Engine VM

For more control, deploy to a VM.

1. **Create a VM:**
   ```bash
   gcloud compute instances create data-entry-app \
     --zone=us-central1-a \
     --machine-type=e2-small \
     --image-family=ubuntu-2004-lts \
     --image-project=ubuntu-os-cloud
   ```

2. **SSH into VM and set up:**
   ```bash
   gcloud compute ssh data-entry-app --zone=us-central1-a
   
   # Install dependencies
   sudo apt-get update
   sudo apt-get install -y python3 python3-pip nginx
   
   # Clone your code and set up
   # ... (follow local setup instructions)
   ```

3. **Set up Nginx reverse proxy:**
   ```nginx
   server {
       listen 80;
       server_name your-domain.com;

       location / {
           proxy_pass http://127.0.0.1:5000;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
       }
   }
   ```

## Option 5: Use a Service like Heroku, Railway, or Render

These platforms make deployment very simple:

### Railway Example

1. Sign up at railway.app
2. Connect your GitHub repo
3. Railway auto-detects Flask and deploys
4. Get a public URL automatically

### Render Example

1. Sign up at render.com
2. Create a new Web Service
3. Connect your repo
4. Set build command: `pip install -r requirements.txt`
5. Set start command: `gunicorn app:app`
6. Deploy

## Security Considerations

### For Production:

1. **Add Authentication:**
   - Implement user login
   - Use Google OAuth or similar
   - Add role-based access control

2. **Use HTTPS:**
   - Cloud Run/App Engine provide this automatically
   - For local/VM: Use Let's Encrypt with Nginx

3. **Set Strong Secret Key:**
   ```python
   import secrets
   print(secrets.token_hex(32))
   ```

4. **Environment Variables:**
   - Never commit secrets to git
   - Use Cloud Run/App Engine environment variables
   - Or use Google Secret Manager

5. **Rate Limiting:**
   - Add Flask-Limiter for API protection
   - Prevent abuse

## Quick Start: Local Network Access

If you just want to test from other computers on your network:

```bash
# 1. Find your IP
ifconfig | grep "inet " | grep -v 127.0.0.1

# 2. Run the app (already configured for 0.0.0.0)
cd data-entry-app
source venv/bin/activate
python app.py

# 3. Access from other computers:
# http://YOUR_IP:5000
```

## Recommended Approach

**For Development/Testing:**
- Use Option 1 (Local Network Access)

**For Production:**
- Use Option 2 (Google Cloud Run) - Best balance of simplicity and features
- Or Option 3 (App Engine) - If you prefer App Engine

## Next Steps

1. Choose your deployment option
2. Follow the specific instructions above
3. Test access from different computers
4. Add authentication for production use
5. Set up monitoring and logging

## Troubleshooting

### Can't access from other computers:
- Check firewall settings
- Verify IP address is correct
- Ensure app is running on `0.0.0.0` not `127.0.0.1`
- Check router/network settings

### Cloud Run deployment fails:
- Verify GCP authentication
- Check BigQuery permissions
- Review Cloud Run logs: `gcloud run services logs read data-entry-forms`

### Permission errors:
- Ensure service account has BigQuery permissions
- Check IAM roles in GCP console
