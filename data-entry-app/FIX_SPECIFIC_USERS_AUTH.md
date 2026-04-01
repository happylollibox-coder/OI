# Fix: Specific Users Authentication Not Working

## Problem
Restricted to specific users, but authentication isn't working properly.

## Step-by-Step Troubleshooting

### Step 1: Verify IAM Policy
The IAM policy should show ONLY the two users (no `allUsers`):
```bash
gcloud run services get-iam-policy oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313
```

### Step 2: Check Which Account Browser is Using

**Critical:** Your browser might be signed in with a different account than you think!

1. Go to: https://myaccount.google.com/
2. Look at the account shown at the top-right
3. It MUST be exactly:
   - `happylollibox@gmail.com` OR
   - `adva.tal2@gmail.com`
4. If it's different, that's why you see "Forbidden"

### Step 3: Sign Out Completely

1. Go to: https://accounts.google.com/logout
2. Sign out of **ALL** Google accounts
3. Close all browser windows

### Step 4: Clear Browser Data

**Chrome/Edge:**
- Press `Ctrl+Shift+Delete` (Windows) or `Cmd+Shift+Delete` (Mac)
- Select "All time"
- Check:
  - ✅ Cookies and other site data
  - ✅ Cached images and files
- Click "Clear data"

**Firefox:**
- Press `Ctrl+Shift+Delete` (Windows) or `Cmd+Shift+Delete` (Mac)
- Select "Everything"
- Check all boxes
- Click "Clear Now"

### Step 5: Use Incognito/Private Mode

1. Open a **new incognito/private window**
2. Go to: `https://oi-data-entry-app-405291422506.us-central1.run.app`
3. You should see a Google sign-in page
4. Sign in with `happylollibox@gmail.com` or `adva.tal2@gmail.com`
5. You should now see the app

### Step 6: Verify Account After Sign-In

After signing in, check:
1. Go to: https://myaccount.google.com/
2. Verify the account shown matches one of the authorized accounts
3. If it doesn't match, sign out and sign in with the correct account

---

## Common Issues

### Issue 1: Browser Using Different Account
**Symptom:** You think you're signed in with `happylollibox@gmail.com` but browser is using a different account
**Fix:** Check https://myaccount.google.com/ to see actual account

### Issue 2: Multiple Accounts Signed In
**Symptom:** Browser has multiple Google accounts, using wrong one
**Fix:** Sign out of all accounts, then sign in with only the authorized account

### Issue 3: IAM Propagation Delay
**Symptom:** Changes just made, might take 1-2 minutes
**Fix:** Wait 2 minutes and try again

### Issue 4: Browser Cache
**Symptom:** Browser cached old authentication state
**Fix:** Use incognito mode or clear all browser data

---

## Test Authentication Flow

1. **Open incognito window**
2. **Go to:** `https://oi-data-entry-app-405291422506.us-central1.run.app`
3. **Expected:** Google sign-in page appears
4. **Sign in with:** `happylollibox@gmail.com` or `adva.tal2@gmail.com`
5. **Expected:** App loads successfully
6. **If you see "Forbidden":** The account you signed in with is not authorized

---

## Verify IAM Policy is Correct

Run this to check:
```bash
gcloud run services get-iam-policy oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313
```

Should show:
```
bindings:
- members:
  - user:adva.tal2@gmail.com
  - user:happylollibox@gmail.com
  role: roles/run.invoker
```

**NO `allUsers` should be present!**

---

## If Still Not Working

1. **Double-check the exact email** you're signing in with (case-sensitive)
2. **Try a different browser** (Chrome → Firefox or vice versa)
3. **Wait 2-3 minutes** for IAM propagation
4. **Check browser console** (F12) for any error messages

The most common issue is the browser using a different Google account than expected!
