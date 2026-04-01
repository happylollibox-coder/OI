# Fix: "You don't have access" After IAP Sign-In

## Problem
You signed in with `happylollibox@gmail.com` but IAP says "You don't have access" even though the user is in the IAP policy.

## Possible Causes

### 1. IAM Propagation Delay
IAM changes can take 2-5 minutes to propagate. **Wait 2-3 minutes** and try again.

### 2. User Not in Same Organization
IAP by default only allows users from the same Google Workspace organization. If `happylollibox@gmail.com` is a personal Gmail account (not in a Workspace org), this might be the issue.

**Solution:** Enable external identities for IAP (allows personal Gmail accounts).

### 3. IAP Service Account Missing Invoker Role
The IAP service account needs `roles/run.invoker` to invoke your service.

**Check:**
```bash
gcloud run services get-iam-policy oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313
```

Should show: `service-405291422506@gcp-sa-iap.iam.gserviceaccount.com` with `roles/run.invoker`

---

## Solutions

### Solution 1: Wait and Retry
1. Wait 2-3 minutes for IAM propagation
2. Sign out completely
3. Clear browser cache
4. Try accessing the app again
5. Sign in with `happylollibox@gmail.com`

### Solution 2: Enable External Identities (If Personal Gmail)

If `happylollibox@gmail.com` is a personal Gmail (not Workspace), you need to enable external identities:

1. Go to: https://console.cloud.google.com/security/iap
2. Find your Cloud Run service
3. Enable "External Identities" or "Identity Platform"
4. Configure to allow personal Gmail accounts

### Solution 3: Verify IAP Policy

```bash
# Check IAP policy
gcloud beta iap web get-iam-policy \
    --resource-type=cloud-run \
    --service=oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313

# Should show both users with roles/iap.httpsResourceAccessor
```

### Solution 4: Check Account Type

**Is `happylollibox@gmail.com` a:**
- Personal Gmail account? → Need external identities enabled
- Workspace account? → Should work if in same org
- Different organization? → Need to allow external identities

---

## Quick Test

1. **Wait 2-3 minutes** (IAM propagation)
2. **Sign out completely** from Google
3. **Clear browser cache**
4. **Access app:** `https://oi-data-entry-app-405291422506.us-central1.run.app`
5. **Sign in** with `happylollibox@gmail.com`
6. **Should work now**

---

## If Still Not Working

The most likely issue is that `happylollibox@gmail.com` is a personal Gmail account and IAP needs external identities enabled. This requires additional setup in the Google Cloud Console.

Try waiting 2-3 minutes first, then retry. If it still doesn't work, we may need to enable external identities.
