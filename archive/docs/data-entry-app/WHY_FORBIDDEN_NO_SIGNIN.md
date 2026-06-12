# Why "Forbidden" Instead of Sign-In Prompt

## Problem
When you restrict Cloud Run to specific users, it shows "Forbidden" instead of prompting you to sign in.

## Root Cause
**Cloud Run with IAM-only authentication doesn't show a sign-in prompt.** It just returns 403 Forbidden for unauthenticated requests.

## Solution Options

### Option 1: Use Identity-Aware Proxy (IAP) - Recommended for Sign-In Prompt

IAP will show a Google sign-in page when users access the app.

**Setup Steps:**

1. **Enable IAP API:**
```bash
gcloud services enable iap.googleapis.com --project=onyga-482313
```

2. **Enable IAP for Cloud Run:**
   - Go to: https://console.cloud.google.com/security/iap
   - Find your Cloud Run service
   - Enable IAP
   - Grant IAP service account the `roles/run.invoker` role

3. **Set IAP access:**
```bash
# Grant users access via IAP
gcloud iap web add-iam-policy-binding \
    --resource-type=backend-services \
    --service=oi-data-entry-app \
    --member="user:happylollibox@gmail.com" \
    --role="roles/iap.httpsResourceAccessor" \
    --project=onyga-482313
```

**Note:** IAP setup for Cloud Run can be complex and may require Load Balancer configuration.

---

### Option 2: Keep It Public (Simplest)

Since IAM-only doesn't show sign-in prompts, the simplest solution is to keep it public:

```bash
gcloud run services add-iam-policy-binding oi-data-entry-app \
    --region=us-central1 \
    --member="allUsers" \
    --role="roles/run.invoker" \
    --project=onyga-482313
```

**Pros:** Works immediately, no setup needed
**Cons:** Anyone can access (less secure)

---

### Option 3: Add App-Level Authentication

Add authentication inside your Flask app:
- Users sign in via Google OAuth
- App checks if email is in allowed list
- Shows sign-in page if not authenticated

This requires code changes to your Flask app.

---

## Recommendation

For now, **Option 2 (keep it public)** is the simplest. If you need authentication with sign-in prompts, we can set up IAP, but it's more complex.

Would you like to:
1. Keep it public (works now)
2. Set up IAP (more secure, shows sign-in prompt)
3. Add authentication in the Flask app (requires code changes)
