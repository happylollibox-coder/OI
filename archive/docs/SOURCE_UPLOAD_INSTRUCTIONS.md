# How to Upload Source Code - Step 3

## Where to Find the Source Section:

The **Source** section is typically at the **TOP** of the "Create service" page, before the Authentication section you're currently viewing.

### Steps:

1. **Scroll UP** on the page - look for a section labeled:
   - "Source" or "Source code" or "Container"
   - It might be collapsed/folded

2. **Look for these options:**
   - "Upload ZIP file" button
   - "Browse" button
   - Drag-and-drop area
   - Or a dropdown with options like "Upload ZIP", "Cloud Source Repositories", etc.

3. **Click "Upload ZIP file" or "Browse"**

4. **Select the ZIP file:**
   - Navigate to: `cloud-functions/fetch-exchange-rates/function-source.zip`
   - Or full path: `/Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI/cloud-functions/fetch-exchange-rates/function-source.zip`

5. **After upload, you should see:**
   - `index.js`
   - `package.json`
   - `package-lock.json`

## Also Check These Settings (if visible):

- **Runtime**: Should be **Node.js 20** (not 22)
- **Entry point**: Should be **`fetchExchangeRates`**
- **Region**: Should be **us-central1**

## If You Can't Find Source Section:

The page might be using a different layout. Look for:
- Tabs at the top (e.g., "Configuration", "Source", "Advanced")
- A "Source" tab or section
- Or it might be in a sidebar

## Quick Check:

The ZIP file is ready at:
```
cloud-functions/fetch-exchange-rates/function-source.zip
```

File size: ~10KB (contains index.js, package.json, package-lock.json)
