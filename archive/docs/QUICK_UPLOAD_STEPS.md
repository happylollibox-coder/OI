# Quick Steps to Upload Source Code

## Current Status:
- ✅ Service name: `fetch-exchange-rates` (already set)
- ⚠️ Currently selected: "GitHub" (middle card)
- ❌ Need to select: "Function" (rightmost card)

## Steps:

1. **Click the "Function" card** (rightmost card with curly braces icon `{}`)
   - It says: "Use an inline editor to create a function"

2. **After clicking "Function", you'll see:**
   - Option to upload ZIP file
   - Or use inline editor
   - **Choose "Upload ZIP file"**

3. **Click "Browse" or "Choose file"**

4. **Select the ZIP file:**
   - Path: `cloud-functions/fetch-exchange-rates/function-source.zip`
   - Or navigate to: `OI/cloud-functions/fetch-exchange-rates/function-source.zip`

5. **After upload, set:**
   - **Runtime**: Node.js 20
   - **Entry point**: `fetchExchangeRates`
   - **Authentication**: "Allow public access" (you already have this ✅)

6. **Click "Create"**

## The ZIP file contains:
- `index.js` (your function code)
- `package.json` (dependencies)
- `package-lock.json` (dependency versions)
