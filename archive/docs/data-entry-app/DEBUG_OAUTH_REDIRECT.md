# Debug OAuth Redirect URI Mismatch

## Issue
The redirect URI is already in Google Console, but you're still getting `redirect_uri_mismatch` error.

## Possible Causes

### 1. Case Sensitivity
Google OAuth is case-sensitive. Check:
- `https://oi-data-entry-app-cllsaft6eq-uc.a.run.app/auth/callback` ✅
- `HTTPS://oi-data-entry-app-cllsaft6eq-uc.a.run.app/auth/callback` ❌

### 2. Extra Spaces or Characters
Make sure there are no:
- Leading/trailing spaces
- Hidden characters
- Line breaks

### 3. Multiple Redirect URIs
Check if you have multiple redirect URIs and one of them is wrong.

### 4. App Sending Different URI
The app might be constructing the redirect URI differently.

## Solution: Hardcode the Redirect URI

Since the redirect URI is already correct in Google Console, let's hardcode it in the app to ensure exact match.

Update the `auth_google` function in `app.py` to use the exact URL:

```python
@app.route('/auth/google')
def auth_google():
    """Initiate Google OAuth flow"""
    try:
        # Check if OAuth credentials are configured
        if not GOOGLE_CLIENT_ID or not GOOGLE_CLIENT_SECRET:
            flash('OAuth is not configured. Please set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET environment variables.', 'error')
            print(f"ERROR: OAuth credentials missing! CLIENT_ID: {'SET' if GOOGLE_CLIENT_ID else 'MISSING'}, CLIENT_SECRET: {'SET' if GOOGLE_CLIENT_SECRET else 'MISSING'}")
            return redirect(url_for('login'))
        
        # Hardcode the redirect URI to match exactly what's in Google Console
        redirect_uri = "https://oi-data-entry-app-cllsaft6eq-uc.a.run.app/auth/callback"
        
        print(f"OAuth redirect URI: {redirect_uri}")
        print(f"OAuth CLIENT_ID: {GOOGLE_CLIENT_ID[:20] if GOOGLE_CLIENT_ID else 'MISSING'}...")
        return google.authorize_redirect(redirect_uri)
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        print(f"OAuth initiation error: {error_details}")
        flash(f'OAuth initiation error: {str(e)}', 'error')
        return redirect(url_for('login'))
```

## Alternative: Check What Google Console Has

1. Go to: https://console.cloud.google.com/apis/credentials?project=onyga-482313
2. Click on your OAuth Client ID
3. Look at "Authorized redirect URIs"
4. Copy the exact URI (don't type it)
5. Compare with: `https://oi-data-entry-app-cllsaft6eq-uc.a.run.app/auth/callback`

## Verify in Google Console

Make sure the redirect URI in Google Console is EXACTLY:
```
https://oi-data-entry-app-cllsaft6eq-uc.a.run.app/auth/callback
```

No variations like:
- `https://oi-data-entry-app-cllsaft6eq-uc.a.run.app/auth/callback/` (trailing slash)
- `http://oi-data-entry-app-cllsaft6eq-uc.a.run.app/auth/callback` (http instead of https)
- Any other variations
