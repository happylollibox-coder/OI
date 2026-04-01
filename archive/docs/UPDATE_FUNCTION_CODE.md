# Update Cloud Function Code - Step by Step

## Current Issues to Fix:
1. ❌ Base Image: Node.js 22 → Should be **Node.js 20**
2. ❌ Entry Point: `helloHttp` → Should be **`fetchExchangeRates`**
3. ❌ Code: Default "Hello World" → Should be your exchange rate function

## Steps:

### Step 1: Change Base Image
- Look for "Base image: Node.js 22 (Ubuntu 22)"
- Click the dropdown or "Edit" button
- Select **"Node.js 20"** (or "Node.js 20 (Ubuntu 22)")

### Step 2: Change Entry Point
- Find "Function entry point" field (currently shows `helloHttp`)
- Change it to: **`fetchExchangeRates`**

### Step 3: Replace index.js Code
1. Click on `index.js` in the file explorer (left side)
2. **Select ALL** the existing code (Ctrl+A or Cmd+A)
3. **Delete it**
4. **Paste** the code from the next section

### Step 4: Update package.json
1. Click on `package.json` in the file explorer
2. **Select ALL** the existing code
3. **Delete it**
4. **Paste** the code from the next section

### Step 5: Save and Deploy
- Click the blue **"Save and redeploy"** button
- Wait for deployment to complete
