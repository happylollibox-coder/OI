# Troubleshoot: "Error: Forbidden"

## Problem
You're seeing "Error: Forbidden" when trying to access the app.

## Solutions

### Solution 1: Check Which Account You're Signed In With

1. In your browser, go to: https://myaccount.google.com/
2. Check which Google account is currently signed in
3. It must be either:
   - `happylollibox@gmail.com`
   - `adva.tal2@gmail.com`
4. If it's a different account, sign out and sign in with one of the authorized accounts

### Solution 2: Use Incognito/Private Mode

1. Open a **new incognito/private window**
2. Go to: `https://oi-data-entry-app-405291422506.us-central1.run.app`
3. When prompted, sign in with `happylollibox@gmail.com` or `adva.tal2@gmail.com`
4. You should now be able to access the app

### Solution 3: Sign Out and Sign Back In

1. Go to: https://accounts.google.com/logout
2. Sign out of **all** Google accounts
3. Clear browser cache (Ctrl+Shift+Delete / Cmd+Shift+Delete)
4. Go to the app URL
5. Sign in with an authorized account when prompted

### Solution 4: Check IAM Policy

The IAM policy should show:
- `user:happylollibox@gmail.com`
- `user:adva.tal2@gmail.com`

If it doesn't, we need to re-add them.

### Solution 5: Wait for IAM Propagation

IAM changes can take 1-2 minutes to propagate. Wait a moment and try again.

---

## Quick Test

1. Open incognito window
2. Go to: `https://oi-data-entry-app-405291422506.us-central1.run.app`
3. Sign in with `happylollibox@gmail.com` when prompted
4. You should see the app

---

## If Still Not Working

We can temporarily make it public again to test, or verify the IAM policy is correct.
