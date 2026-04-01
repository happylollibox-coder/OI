# Cloud Run Access Control Options

## Overview
You can control who can access your Cloud Run service using IAM (Identity and Access Management).

## Option 1: Public Access (Current)
**What it means:** Anyone on the internet can access your app
**How to set:**
```bash
gcloud run services add-iam-policy-binding oi-data-entry-app \
    --region=us-central1 \
    --member="allUsers" \
    --role="roles/run.invoker" \
    --project=onyga-482313
```
**Use case:** Public websites, APIs, or when you want open access

---

## Option 2: Specific Users
**What it means:** Only listed Google accounts can access
**How to set:**
```bash
# Remove public access
gcloud run services remove-iam-policy-binding oi-data-entry-app \
    --region=us-central1 \
    --member="allUsers" \
    --role="roles/run.invoker" \
    --project=onyga-482313

# Add specific users
gcloud run services add-iam-policy-binding oi-data-entry-app \
    --region=us-central1 \
    --member="user:email@gmail.com" \
    --role="roles/run.invoker" \
    --project=onyga-482313
```
**Use case:** Internal tools, restricted access, specific team members

**Current authorized users:**
- `happylollibox@gmail.com`
- `adva.tal2@gmail.com`

---

## Option 3: Service Accounts
**What it means:** Only specific service accounts (not human users) can access
**How to set:**
```bash
gcloud run services add-iam-policy-binding oi-data-entry-app \
    --region=us-central1 \
    --member="serviceAccount:service-account@project.iam.gserviceaccount.com" \
    --role="roles/run.invoker" \
    --project=onyga-482313
```
**Use case:** Service-to-service communication, automated access

---

## Option 4: Google Groups
**What it means:** All members of a Google Group can access
**How to set:**
```bash
gcloud run services add-iam-policy-binding oi-data-entry-app \
    --region=us-central1 \
    --member="group:group-name@yourdomain.com" \
    --role="roles/run.invoker" \
    --project=onyga-482313
```
**Use case:** Team access, department-wide access

---

## Option 5: Domain-Wide Access
**What it means:** Anyone with an email from your organization's domain
**How to set:**
```bash
gcloud run services add-iam-policy-binding oi-data-entry-app \
    --region=us-central1 \
    --member="domain:yourdomain.com" \
    --role="roles/run.invoker" \
    --project=onyga-482313
```
**Use case:** Company-wide access, organization-wide tools

---

## Option 6: Combination (Multiple Methods)
**What it means:** Mix and match - e.g., specific users + a Google Group
**Example:**
```bash
# Add specific users
gcloud run services add-iam-policy-binding oi-data-entry-app \
    --region=us-central1 \
    --member="user:admin@company.com" \
    --role="roles/run.invoker" \
    --project=onyga-482313

# Add a group
gcloud run services add-iam-policy-binding oi-data-entry-app \
    --region=us-central1 \
    --member="group:team@company.com" \
    --role="roles/run.invoker" \
    --project=onyga-482313
```

---

## How Authentication Works

### For Public Access:
- No sign-in required
- Anyone can access immediately

### For Restricted Access:
- Users must sign in with Google
- Only authorized accounts can access
- Others see "Access Denied" (403 Forbidden)

---

## View Current Access

```bash
gcloud run services get-iam-policy oi-data-entry-app \
    --region=us-central1 \
    --project=onyga-482313
```

---

## Remove Access

```bash
# Remove a specific user
gcloud run services remove-iam-policy-binding oi-data-entry-app \
    --region=us-central1 \
    --member="user:email@gmail.com" \
    --role="roles/run.invoker" \
    --project=onyga-482313

# Remove public access
gcloud run services remove-iam-policy-binding oi-data-entry-app \
    --region=us-central1 \
    --member="allUsers" \
    --role="roles/run.invoker" \
    --project=onyga-482313
```

---

## Recommendations

**For Business/Internal Tools:**
- Use **Option 2** (Specific Users) or **Option 4** (Google Groups)
- Most secure for sensitive data

**For Public APIs/Websites:**
- Use **Option 1** (Public Access)
- Simplest for public-facing services

**For Company-Wide Tools:**
- Use **Option 5** (Domain-Wide Access)
- Easy to manage for entire organization

---

## Current Status

Your service currently has:
- ✅ Public access (`allUsers`)
- ✅ Two specific users (`happylollibox@gmail.com`, `adva.tal2@gmail.com`)

You can remove `allUsers` to restrict it to just those two users.
