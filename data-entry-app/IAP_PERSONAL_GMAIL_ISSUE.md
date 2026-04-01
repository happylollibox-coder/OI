# Fix: Personal Gmail Accounts Can't Access IAP

## Problem
Both `happylollibox@gmail.com` and `adva.tal2@gmail.com` are getting "You don't have access" even though they're in the IAP policy.

## Root Cause
**IAP by default only allows Google Workspace accounts** (organization accounts). Personal Gmail accounts need "External Identities" to be enabled.

## Solution Options

### Option 1: Enable External Identities (Recommended)

This allows personal Gmail accounts to access IAP-protected resources.

**Via Console:**
1. Go to: https://console.cloud.google.com/security/iap
2. Find your Cloud Run service: `oi-data-entry-app`
3. Click on it
4. Enable "External Identities" or "Identity Platform"
5. Configure to allow personal Gmail accounts

**Note:** This may require additional setup and billing for Identity Platform.

### Option 2: Use IAM Instead of IAP (Simpler)

Since IAP is complex for personal Gmail accounts, we can:
1. Disable IAP
2. Use IAM-only (but this shows "Forbidden" instead of sign-in)
3. OR make it public with app-level authentication

### Option 3: Make It Public (Simplest)

For now, make it public so both users can access:

```bash
gcloud run services remove-iam-policy-binding oi-data-entry-app \
    --region=us-central1 \
    --member="allUsers" \
    --role="roles/run.invoker" \
    --project=onyga-482313
```

Wait, that removes public access. To make it public:

```bash
gcloud run services add-iam-policy-binding oi-data-entry-app \
    --region=us-central1 \
    --member="allUsers" \
    --role="roles/run.invoker" \
    --project=onyga-482313
```

### Option 4: Add App-Level Authentication

Add Google OAuth to your Flask app:
- Users sign in via Google
- App checks if email is in allowed list
- Shows sign-in page if not authenticated

This requires code changes but gives you full control.

---

## Recommendation

Since both users are personal Gmail accounts and IAP is blocking them, the **simplest solution** is:

1. **Disable IAP** (it's not working for personal Gmail)
2. **Make it public** (works immediately)
3. **OR add app-level authentication** (more secure, requires code changes)

Which would you prefer?
