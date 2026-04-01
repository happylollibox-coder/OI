# Cloud Function Deployment Guide - GCP Console

## Current Settings to Change:

### 1. **Runtime** ⚠️
- **Current**: Node.js 22
- **Change to**: **Node.js 20** (required - our code specifies Node 20)

### 2. **Authentication** ⚠️ CRITICAL
- **Current**: "Require authentication" with IAM selected
- **Change to**: **"Allow public access"** 
  - This is REQUIRED for BigQuery remote functions to call it
  - BigQuery cannot authenticate with IAM-protected functions

### 3. **Source Code Upload**
You need to upload the function source code:
- Go to the "Source" section
- Select "Upload ZIP" or "Upload from repository"
- Upload the `cloud-functions/fetch-exchange-rates/` directory contents:
  - `index.js`
  - `package.json`
  - (Optional: `package-lock.json` if you have it)

### 4. **Entry Point**
- **Entry point**: `fetchExchangeRates` (must match the export name in index.js)

### 5. **Other Settings**
- **Memory**: 256 MB (default is fine)
- **Timeout**: 60 seconds (default is fine)
- **Region**: us-central1 ✅ (correct)

## Step-by-Step:

1. **Change Runtime**: Click the Runtime dropdown → Select "Node.js 20"

2. **Change Authentication**: 
   - Click the radio button for **"Allow public access"**
   - This will show: "No authentication checks will be performed."

3. **Upload Source**:
   - Scroll to "Source" section
   - Choose "Upload ZIP" or browse for files
   - Select all files from `cloud-functions/fetch-exchange-rates/`

4. **Set Entry Point**:
   - In the "Entry point" field, enter: `fetchExchangeRates`

5. **Click "Deploy"**

## After Deployment:

Test the function:
```bash
curl -s 'https://fetch-exchange-rates-405291422506.us-central1.run.app' | jq '.success'
```

Then deploy the BigQuery remote function:
```bash
bq query --use_legacy_sql=false --project_id=onyga-482313 < scripts/Functions/FN_FETCH_EXCHANGE_RATES.sql
```
