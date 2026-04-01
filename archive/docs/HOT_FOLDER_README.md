# Hot Folder Setup Guide

This guide explains how to set up and use a "hot folder" in Google Cloud Storage for automatic file processing.

## Overview

The hot folder system allows you to:
- Upload files to a GCS bucket folder
- Automatically trigger processing when files are uploaded/updated
- Route different file types to different processors
- Archive processed files automatically
- Handle errors gracefully

## Architecture

```
File Upload → GCS Bucket (incoming/) 
           → Pub/Sub Notification 
           → Cloud Function 
           → Process File 
           → Move to archive/ or errors/
```

## Setup

### 1. Run the Setup Script

```bash
chmod +x scripts/setup_hot_folder.sh
./scripts/setup_hot_folder.sh
```

This script will:
- Create a GCS bucket (`onyga-482313-hot-folder`)
- Create folder structure (incoming/, archive/, errors/)
- Set up Pub/Sub topic for notifications
- Configure bucket notifications
- Deploy the Cloud Function

### 2. Verify Setup

```bash
# Check bucket exists
gsutil ls gs://onyga-482313-hot-folder/

# Check function is deployed
gcloud functions describe process-hot-folder-file --region=us-central1 --project=onyga-482313
```

## Usage

### Folder Structure

Files are organized by type in subfolders:

```
incoming/
├── csv/
│   ├── payoneer/                    → SRC_BANK_PAYONEER_HAPPY_LOLLI
│   ├── leumi/                       → SRC_BANK_LEUMI_ILS
│   ├── currency/                     → SRC_CURRENCY_RATES
│   ├── Inventory_Ledger_Summary/     → SRC_INVENTORY_FBA (any filename)
│   ├── AWD_Inventory_Ledger_Summary/ → SRC_INVENTORY_AWD (any filename)
│   └── *                            → SRC_CSV_DEFAULT (any other CSV)
├── excel/
│   ├── reports/      → SRC_EXCEL_REPORTS
│   └── *             → SRC_EXCEL_DEFAULT (any other Excel)
├── json/
│   ├── api/          → SRC_API_DATA
│   └── *             → SRC_JSON_DEFAULT (any other JSON)
├── text/             → Processed as text
└── other/            → HOT_FOLDER_DEFAULT (unknown types)
```

### Uploading Files

Upload files to the appropriate folder based on file type and destination table:

```bash
# CSV files - Payoneer data
gsutil cp payoneer-report.csv gs://onyga-482313-hot-folder/incoming/csv/payoneer/

# CSV files - Leumi data
gsutil cp leumi-transactions.csv gs://onyga-482313-hot-folder/incoming/csv/leumi/

# CSV files - Currency rates
gsutil cp currency-rates.csv gs://onyga-482313-hot-folder/incoming/csv/currency/

# CSV files - Amazon FBA Inventory (any filename works)
gsutil cp INVENTORY_FBA_2024_12_31.csv gs://onyga-482313-hot-folder/incoming/csv/Inventory_Ledger_Summary/
gsutil cp latest-fba-snapshot.csv gs://onyga-482313-hot-folder/incoming/csv/Inventory_Ledger_Summary/

# CSV files - Amazon AWD Inventory (any filename works)
gsutil cp INVENTORY_AWD_2025_12_31.csv gs://onyga-482313-hot-folder/incoming/csv/AWD_Inventory_Ledger_Summary/
gsutil cp awd-inventory.csv gs://onyga-482313-hot-folder/incoming/csv/AWD_Inventory_Ledger_Summary/

# CSV files - Any other CSV (default table)
gsutil cp other-data.csv gs://onyga-482313-hot-folder/incoming/csv/

# Excel files - Reports
gsutil cp monthly-report.xlsx gs://onyga-482313-hot-folder/incoming/excel/reports/

# Excel files - Any other Excel (default table)
gsutil cp data.xlsx gs://onyga-482313-hot-folder/incoming/excel/

# JSON files - API data
gsutil cp api-response.json gs://onyga-482313-hot-folder/incoming/json/api/

# JSON files - Any other JSON (default table)
gsutil cp data.json gs://onyga-482313-hot-folder/incoming/json/

# Text files
gsutil cp log.txt gs://onyga-482313-hot-folder/incoming/text/

# Unknown file types
gsutil cp unknown.xyz gs://onyga-482313-hot-folder/incoming/other/

# Upload multiple files
gsutil -m cp *.csv gs://onyga-482313-hot-folder/incoming/csv/
```

### File Processing

Files are automatically processed when uploaded. The folder path determines which BigQuery table the file is loaded into:

**CSV Files:**
- `incoming/csv/payoneer/` → `SRC_BANK_PAYONEER_HAPPY_LOLLI`
- `incoming/csv/leumi/` → `SRC_BANK_LEUMI_ILS`
- `incoming/csv/currency/` → `SRC_CURRENCY_RATES`
- `incoming/csv/Inventory_Ledger_Summary/` → `SRC_INVENTORY_FBA` (any filename, TRUNCATE mode)
- `incoming/csv/AWD_Inventory_Ledger_Summary/` → `SRC_INVENTORY_AWD` (any filename, TRUNCATE mode)
- `incoming/csv/` (any other CSV) → `SRC_CSV_DEFAULT`

**Excel Files:**
- `incoming/excel/reports/` → `SRC_EXCEL_REPORTS`
- `incoming/excel/` (any other Excel) → `SRC_EXCEL_DEFAULT`

**JSON Files:**
- `incoming/json/api/` → `SRC_API_DATA`
- `incoming/json/` (any other JSON) → `SRC_JSON_DEFAULT`

**Other Files:**
- `incoming/text/` → Processed as text (no BigQuery load)
- `incoming/other/` → `HOT_FOLDER_DEFAULT`

### File Organization

After processing:
- ✅ **Successful files** → Moved to `archive/YYYY-MM-DD/filename`
- ❌ **Failed files** → Moved to `errors/YYYY-MM-DD/filename`

## Customization

### Adding New File Types

1. **Add folder to setup script** (`scripts/setup_hot_folder.sh`):
   ```bash
   gsutil -m mkdir -p gs://$BUCKET_NAME/incoming/pdf/
   ```

2. **Add handler to CONFIG** (`cloud-functions/hot-folder-processor/index.js`):
   ```javascript
   fileHandlers: {
     '.csv': 'processCSV',
     '.pdf': 'processPDF',  // New type
   },
   fileTypeFolders: {
     'pdf': 'incoming/pdf/',
   }
   ```

3. **Add table mapping**:
   ```javascript
   {
     folderPath: 'incoming/pdf/',
     tableId: 'SRC_PDF_DATA',
     datasetId: 'OI',
     loadMode: 'WRITE_APPEND',
     // ... other config
   }
   ```

4. **Implement the handler function**:
   ```javascript
   async function processPDF(file, bucket, tableConfig) {
     // Your PDF processing logic
     const loadResult = await loadToBigQuery(file, bucket, tableConfig);
     return { success: true, message: 'PDF processed' };
   }
   ```

5. **Add case in switch statement**

6. **Redeploy**: `./scripts/setup_hot_folder.sh`

### Adding New Table Mappings

To route files to a new table, add a mapping entry:

```javascript
{
  folderPath: 'incoming/csv/sales/',  // Folder path
  tableId: 'SRC_SALES_DATA',          // Destination table
  datasetId: 'OI',                     // Dataset (optional)
  loadMode: 'WRITE_APPEND',            // WRITE_APPEND, WRITE_TRUNCATE
  skipLeadingRows: 1,                  // Skip header row
  autodetect: true,                    // Auto-detect schema
  schema: null                         // Or provide schema array
}
```

Then create the folder:
```bash
gsutil -m mkdir -p gs://onyga-482313-hot-folder/incoming/csv/sales/
```

### Custom Processing Logic

Edit the handler functions in `cloud-functions/hot-folder-processor/index.js`:

- `processCSV()` - Add CSV parsing and BigQuery loading
- `processExcel()` - Add Excel parsing (install `xlsx` library)
- `processJSON()` - Add JSON validation and processing
- `processText()` - Add text parsing logic

### Example: Load CSV to BigQuery

```javascript
async function processCSV(file, bucket) {
  const [fileBuffer] = await bucket.file(file.name).download();
  
  // Load to BigQuery
  const datasetId = 'OI';
  const tableId = 'hot_folder_data';
  
  await bigquery
    .dataset(datasetId)
    .table(tableId)
    .load(fileBuffer, {
      sourceFormat: 'CSV',
      skipLeadingRows: 1,
      autodetect: true
    });
  
  return { success: true, message: 'Loaded to BigQuery' };
}
```

## Monitoring

### View Function Logs

```bash
gcloud functions logs read process-hot-folder-file \
  --region=us-central1 \
  --project=onyga-482313 \
  --limit=50
```

### Check Bucket Contents

```bash
# List incoming files
gsutil ls gs://onyga-482313-hot-folder/incoming/

# List archived files
gsutil ls -r gs://onyga-482313-hot-folder/archive/

# List error files
gsutil ls -r gs://onyga-482313-hot-folder/errors/
```

### Monitor Pub/Sub

```bash
# View topic details
gcloud pubsub topics describe hot-folder-notifications --project=onyga-482313

# View subscriptions
gcloud pubsub subscriptions list --project=onyga-482313
```

## Best Practices

1. **File Naming**: Use consistent naming conventions for easier tracking
   - `data_YYYYMMDD.csv`
   - `report_YYYYMMDD.xlsx`

2. **File Size**: Large files (>100MB) may need special handling
   - Consider chunking or streaming for very large files

3. **Idempotency**: Make processing idempotent (safe to re-run)
   - Check if data already exists before inserting
   - Use file checksums or timestamps

4. **Error Handling**: Always check error folder for failed files
   - Review error logs
   - Fix and re-upload if needed

5. **Cleanup**: Periodically clean old archived files
   ```bash
   # Delete files older than 90 days
   gsutil -m rm -r gs://onyga-482313-hot-folder/archive/2024-*
   ```

## Troubleshooting

### Function Not Triggering

1. Check Pub/Sub topic has notifications:
   ```bash
   gcloud pubsub topics describe hot-folder-notifications
   ```

2. Verify bucket notifications:
   ```bash
   gsutil notification list gs://onyga-482313-hot-folder
   ```

3. Check function is active:
   ```bash
   gcloud functions describe process-hot-folder-file --region=us-central1
   ```

### Processing Errors

1. Check function logs for error details
2. Verify file format matches expected handler
3. Check BigQuery permissions if loading data
4. Review file in errors/ folder

### File Not Moving

1. Check function completed successfully
2. Verify bucket permissions
3. Check function logs for move errors

## Cost Considerations

- **Storage**: ~$0.020 per GB/month
- **Function Invocations**: First 2 million free, then $0.40 per million
- **Pub/Sub**: First 10GB free, then $0.40 per GB

For typical usage (<1000 files/month), costs are minimal.

## Security

- Files are stored in GCS with project-level access control
- Function runs with default service account permissions
- Consider adding IAM roles for specific users/folders
- Use signed URLs for external access if needed

## Next Steps

1. Customize file handlers for your specific use cases
2. Add BigQuery loading logic
3. Set up monitoring/alerts for failures
4. Create scheduled cleanup jobs
5. Add file validation before processing
