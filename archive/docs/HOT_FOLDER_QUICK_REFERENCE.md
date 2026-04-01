# Hot Folder Quick Reference

## Folder Structure & Table Mappings

### CSV Files (`incoming/csv/`)

| Folder Path | Destination Table | Load Mode | Notes |
|------------|-------------------|-----------|-------|
| `incoming/csv/payoneer/` | `SRC_BANK_PAYONEER_HAPPY_LOLLI` | APPEND | Payoneer transaction data |
| `incoming/csv/leumi/` | `SRC_BANK_LEUMI_ILS` | APPEND | Leumi bank transactions |
| `incoming/csv/currency/` | `SRC_CURRENCY_RATES` | TRUNCATE | Currency exchange rates (overwrites) |
| `incoming/csv/Inventory_Ledger_Summary/` | `SRC_INVENTORY_FBA` | TRUNCATE | Amazon FBA inventory snapshots (any filename) |
| `incoming/csv/AWD_Inventory_Ledger_Summary/` | `SRC_INVENTORY_AWD` | TRUNCATE | Amazon AWD inventory snapshots (any filename) |
| `incoming/csv/` | `SRC_CSV_DEFAULT` | APPEND | Any other CSV files |

**Upload Examples:**
```bash
gsutil cp payoneer-data.csv gs://onyga-482313-hot-folder/incoming/csv/payoneer/
gsutil cp leumi-data.csv gs://onyga-482313-hot-folder/incoming/csv/leumi/
gsutil cp rates.csv gs://onyga-482313-hot-folder/incoming/csv/currency/
gsutil cp INVENTORY_FBA_2024_12_31.csv gs://onyga-482313-hot-folder/incoming/csv/Inventory_Ledger_Summary/
gsutil cp any-fba-file.csv gs://onyga-482313-hot-folder/incoming/csv/Inventory_Ledger_Summary/
gsutil cp INVENTORY_AWD_2025_12_31.csv gs://onyga-482313-hot-folder/incoming/csv/AWD_Inventory_Ledger_Summary/
gsutil cp any-awd-file.csv gs://onyga-482313-hot-folder/incoming/csv/AWD_Inventory_Ledger_Summary/
gsutil cp other.csv gs://onyga-482313-hot-folder/incoming/csv/
```

### Excel Files (`incoming/excel/`)

| Folder Path | Destination Table | Load Mode | Notes |
|------------|-------------------|-----------|-------|
| `incoming/excel/reports/` | `SRC_EXCEL_REPORTS` | APPEND | Report files |
| `incoming/excel/` | `SRC_EXCEL_DEFAULT` | APPEND | Any other Excel files |

**Upload Examples:**
```bash
gsutil cp monthly-report.xlsx gs://onyga-482313-hot-folder/incoming/excel/reports/
gsutil cp data.xlsx gs://onyga-482313-hot-folder/incoming/excel/
```

### JSON Files (`incoming/json/`)

| Folder Path | Destination Table | Load Mode | Notes |
|------------|-------------------|-----------|-------|
| `incoming/json/api/` | `SRC_API_DATA` | APPEND | API response data |
| `incoming/json/` | `SRC_JSON_DEFAULT` | APPEND | Any other JSON files |

**Upload Examples:**
```bash
gsutil cp api-response.json gs://onyga-482313-hot-folder/incoming/json/api/
gsutil cp data.json gs://onyga-482313-hot-folder/incoming/json/
```

### Other Files

| Folder Path | Processing | Notes |
|------------|-----------|-------|
| `incoming/text/` | Text processing only | No BigQuery load |
| `incoming/other/` | `HOT_FOLDER_DEFAULT` | Unknown file types |

## Adding a New Mapping

1. **Create the folder:**
   ```bash
   gsutil -m mkdir -p gs://onyga-482313-hot-folder/incoming/csv/my-new-type/
   ```

2. **Add mapping in `index.js`** (before default fallback):
   ```javascript
   {
     folderPath: 'incoming/csv/my-new-type/',
     tableId: 'SRC_MY_NEW_TYPE',
     datasetId: 'OI',
     loadMode: 'WRITE_APPEND',
     skipLeadingRows: 1,
     autodetect: true,
     schema: null
   }
   ```

3. **Redeploy:**
   ```bash
   ./scripts/setup_hot_folder.sh
   ```

## File Processing Flow

```
File Upload → Folder Detection → Table Mapping → BigQuery Load → Archive
     ↓              ↓                  ↓              ↓            ↓
  incoming/    csv/excel/json      Find table    Load data    archive/
```

## Common Commands

```bash
# List incoming files
gsutil ls -r gs://onyga-482313-hot-folder/incoming/

# Upload a file
gsutil cp file.csv gs://onyga-482313-hot-folder/incoming/csv/payoneer/

# View function logs
gcloud functions logs read process-hot-folder-file --region=us-central1 --limit=50

# Check archived files
gsutil ls -r gs://onyga-482313-hot-folder/archive/

# Check error files
gsutil ls -r gs://onyga-482313-hot-folder/errors/
```
