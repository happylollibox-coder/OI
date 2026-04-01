# Setup Google OAuth for Flask App

## What Was Added

1. ✅ **authlib library** - Added to requirements.txt
2. ✅ **OAuth configuration** - Google OAuth setup in app.py
3. ✅ **Login/Logout routes** - `/login`, `/auth/google`, `/auth/callback`, `/logout`
4. ✅ **Authentication decorator** - `@login_required` protects all routes
5. ✅ **Templates** - Login page and access denied page
6. ✅ **Navbar updates** - Shows user name and logout button

## Required: Google OAuth Credentials

You need to create Google OAuth credentials:

### Step 1: Create OAuth Credentials

1. Go to: https://console.cloud.google.com/apis/credentials
2. Select project: `onyga-482313`
3. Click **"+ CREATE CREDENTIALS"** → **"OAuth client ID"**
4. If prompted, configure OAuth consent screen:
   - User Type: **External** (for personal Gmail accounts)
   - App name: **OI Data Entry App**
   - User support email: **happylollibox@gmail.com**
   - Developer contact: **happylollibox@gmail.com**
   - Click **Save and Continue**
   - Scopes: Click **Save and Continue**
   - Test users: Add `happylollibox@gmail.com` and `adva.tal2@gmail.com`
   - Click **Save and Continue**
5. Create OAuth Client ID:
   - Application type: **Web application**
   - Name: **OI Data Entry App**
   - Authorized redirect URIs:
     - `https://oi-data-entry-app-405291422506.us-central1.run.app/auth/callback`
     - `https://oi-data-entry-app-cllsaft6eq-uc.a.run.app/auth/callback`
   - Click **Create**
6. Copy the **Client ID** and **Client Secret**

### Step 2: Set Environment Variables

In Cloud Run, set these environment variables:

```bash
gcloud run services update oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313 \
    --set-env-vars "GOOGLE_CLIENT_ID=YOUR_CLIENT_ID,GOOGLE_CLIENT_SECRET=YOUR_CLIENT_SECRET,GCP_PROJECT_ID=onyga-482313,BIGQUERY_DATASET=OI"
```

Replace `YOUR_CLIENT_ID` and `YOUR_CLIENT_SECRET` with the values from Step 1.

### Step 3: Redeploy

After setting environment variables, redeploy:

```bash
cd ~/data-entry-app
./deploy_minimal.sh
```

---

## How It Works

1. **User visits app** → Redirected to `/login`
2. **Clicks "Sign in with Google"** → Redirected to Google sign-in
3. **Signs in with Google** → Redirected back to `/auth/callback`
4. **App checks email** → If in `ALLOWED_USERS`, grants access
5. **If not authorized** → Shows "Access Denied" page
6. **If authorized** → Session created, user can access app

---

## Allowed Users

Currently configured in `app.py`:
- `happylollibox@gmail.com`
- `adva.tal2@gmail.com`

To add more users, edit `ALLOWED_USERS` list in `app.py` or move to environment variable.

---

## Test Locally

For local testing, add to `.env` file:
```
GOOGLE_CLIENT_ID=your_client_id
GOOGLE_CLIENT_SECRET=your_client_secret
```

And add `http://localhost:5000/auth/callback` to authorized redirect URIs.

---

## Next Steps

1. Create OAuth credentials (Step 1 above)
2. Set environment variables in Cloud Run (Step 2)
3. Redeploy the app (Step 3)
4. Test login flow

The app is now ready for OAuth - just needs the credentials configured!
