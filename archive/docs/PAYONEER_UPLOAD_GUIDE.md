# Payoneer CSV Upload Guide

## Overview
This guide explains how to upload Payoneer CSV files to BigQuery and process them through the existing procedures.

## Two Payoneer Accounts
1. **HAPPY_LOLLI** → `SRC_BANK_PAYONEER_HAPPY_LOLLI`
2. **ADVA_TAL** → `SRC_BANK_PAYONEER_ADVA_TAL`

---

## 🚀 Quick Method: Hot Folder (Recommended)

**The easiest way!** Just upload your CSV file to the hot folder and it will be automatically processed.

### For HAPPY_LOLLI:
```bash
# 1. Preprocess the CSV (required for date format conversion)
python3 scripts/Tables/bank_leumi/preprocess_payoneer_csv.py \
  "report_2023-2025 happy lolli payoneer.csv" \
  "payoneer_happy_lolli_clean.csv"

# 2. Upload to hot folder (automatic processing!)
gsutil cp payoneer_happy_lolli_clean.csv \
  gs://onyga-482313-hot-folder/incoming/csv/payoneer/
```

### For ADVA_TAL:
```bash
# Just upload directly (no preprocessing needed)
gsutil cp "report_2023-2025 adva.tal payoneer.csv" \
  gs://onyga-482313-hot-folder/incoming/csv/payoneer/
```

**That's it!** The Cloud Function will:
- ✅ Automatically detect the file
- ✅ Load it into the correct BigQuery table (`SRC_BANK_PAYONEER_HAPPY_LOLLI`)
- ✅ Move it to `archive/` folder when done
- ✅ Move to `errors/` folder if something goes wrong

**After upload, run the stored procedures:**
```bash
export CLOUDSDK_PYTHON=$(which python3)

# Refresh staging
bq query --project_id=onyga-482313 --use_legacy_sql=false \
  "CALL \`onyga-482313.OI.SP_STG_UNIFIED_TRANSACTION_SOURCES\`()"

# Process to fact table
bq query --project_id=onyga-482313 --use_legacy_sql=false \
  "CALL \`onyga-482313.OI.SP_FACT_FINANCIAL_TRANSACTIONS\`()"
```

**Check processing status:**
```bash
# View function logs
gcloud functions logs read process-hot-folder-file \
  --region=us-central1 \
  --project=onyga-482313 \
  --limit=20

# Check if file was archived (success) or moved to errors
gsutil ls gs://onyga-482313-hot-folder/archive/
gsutil ls gs://onyga-482313-hot-folder/errors/
```

---

## Manual Method: Step-by-Step Process

### Step 1: Prepare Your CSV File

#### For HAPPY_LOLLI Account:
1. Download your Payoneer CSV export (format: "DD MMM, YYYY" dates)
2. **Preprocess the CSV** using the Python script:
   ```bash
   cd /Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI
   python3 scripts/Tables/bank_leumi/preprocess_payoneer_csv.py \
     <input_csv_file> \
     <output_csv_file>
   ```
   Example:
   ```bash
   python3 scripts/Tables/bank_leumi/preprocess_payoneer_csv.py \
     "report_2023-2025 happy lolli payoneer.csv" \
     "payoneer_happy_lolli_clean.csv"
   ```

#### For ADVA_TAL Account:
- No preprocessing needed - use the CSV file directly

---

### Step 2: Upload CSV to Google Cloud Storage (GCS)

#### Option A: Using Google Cloud Console
1. Go to [Google Cloud Console](https://console.cloud.google.com/storage)
2. Navigate to bucket: `gs://happy-lolli-bucket-1/New/`
3. Click "Upload Files"
4. Select your CSV file

#### Option B: Using `gsutil` command line
```bash
# For HAPPY_LOLLI (preprocessed file)
gsutil cp payoneer_happy_lolli_clean.csv \
  gs://happy-lolli-bucket-1/staging/payoneer_happy_lolli_clean.csv

# For ADVA_TAL (original file)
gsutil cp "report_2023-2025 adva.tal payoneer.csv" \
  gs://happy-lolli-bucket-1/New/report_2023-2025\ adva.tal\ payoneer.csv
```

---

### Step 3: Load CSV into BigQuery Source Tables

#### For HAPPY_LOLLI:
```bash
export CLOUDSDK_PYTHON=$(which python3)

bq load \
  --source_format=CSV \
  --skip_leading_rows=1 \
  --project_id=onyga-482313 \
  --replace \
  onyga-482313:OI.SRC_BANK_PAYONEER_HAPPY_LOLLI \
  gs://happy-lolli-bucket-1/staging/payoneer_happy_lolli_clean.csv \
  transaction_date:DATE,description:STRING,amount:FLOAT64,currency:STRING,status:STRING,transaction_id:STRING
```

#### For ADVA_TAL:
```bash
export CLOUDSDK_PYTHON=$(which python3)

bq load \
  --source_format=CSV \
  --skip_leading_rows=1 \
  --project_id=onyga-482313 \
  --allow_quoted_newlines \
  --replace \
  onyga-482313:OI.SRC_BANK_PAYONEER_ADVA_TAL \
  "gs://happy-lolli-bucket-1/New/report_2023-2025 adva.tal payoneer.csv" \
  transaction_date:DATE,description:STRING,amount:FLOAT64,currency:STRING,status:STRING,transaction_id:STRING
```

**Note:** The `--replace` flag will replace all existing data in the table. Remove it if you want to append.

---

### Step 4: Run Stored Procedures

After loading the CSV, run the stored procedures to process the data:

#### Step 4.1: Refresh Staging Table
```bash
export CLOUDSDK_PYTHON=$(which python3)

bq query --project_id=onyga-482313 --use_legacy_sql=false \
  "CALL \`onyga-482313.OI.SP_STG_UNIFIED_TRANSACTION_SOURCES\`()"
```

This procedure:
- Reads from source tables (including Payoneer)
- Populates `STG_UNIFIED_TRANSACTION_SOURCES`
- Preserves any `manual_effect_date` values you've set

#### Step 4.2: Process to Fact Table
```bash
export CLOUDSDK_PYTHON=$(which python3)

bq query --project_id=onyga-482313 --use_legacy_sql=false \
  "CALL \`onyga-482313.OI.SP_FACT_FINANCIAL_TRANSACTIONS\`()"
```

This procedure:
- Processes staging data into `FACT_FINANCIAL_TRANSACTIONS`
- Applies currency conversions
- Calculates `effect_date` (from `manual_effect_date` or `effect_days_to_reduce`)
- Updates `GENERAL_CONVERSION` and `DIM_PAYMENT_SOURCE_HIERARCHY`

---

### Step 5: Verify the Data

```bash
export CLOUDSDK_PYTHON=$(which python3)

# Check row counts
bq query --project_id=onyga-482313 --use_legacy_sql=false "
  SELECT 
    'SRC_BANK_PAYONEER_HAPPY_LOLLI' as table_name,
    COUNT(*) as row_count
  FROM \`onyga-482313.OI.SRC_BANK_PAYONEER_HAPPY_LOLLI\`
  UNION ALL
  SELECT 
    'SRC_BANK_PAYONEER_ADVA_TAL' as table_name,
    COUNT(*) as row_count
  FROM \`onyga-482313.OI.SRC_BANK_PAYONEER_ADVA_TAL\`
  UNION ALL
  SELECT 
    'STG_UNIFIED_TRANSACTION_SOURCES' as table_name,
    COUNT(*) as row_count
  FROM \`onyga-482313.OI.STG_UNIFIED_TRANSACTION_SOURCES\`
  WHERE source_system LIKE '%PAYONEER%'
  UNION ALL
  SELECT 
    'FACT_FINANCIAL_TRANSACTIONS' as table_name,
    COUNT(*) as row_count
  FROM \`onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS\`
  WHERE source_system LIKE '%PAYONEER%'
"

# Check sample Payoneer transactions
bq query --project_id=onyga-482313 --use_legacy_sql=false "
  SELECT 
    transaction_date,
    effect_date,
    amount,
    currency,
    payment_source,
    transaction_description,
    source_system,
    account_name
  FROM \`onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS\`
  WHERE source_system LIKE '%PAYONEER%'
  ORDER BY transaction_date DESC
  LIMIT 10
"
```

---

## Quick Reference: All Commands in One Place

```bash
# Set environment variable (if not already in ~/.zshrc)
export CLOUDSDK_PYTHON=$(which python3)

# 1. Preprocess (HAPPY_LOLLI only)
python3 scripts/Tables/bank_leumi/preprocess_payoneer_csv.py \
  "input.csv" "output.csv"

# 2. Upload to GCS (choose one)
gsutil cp output.csv gs://happy-lolli-bucket-1/staging/payoneer_happy_lolli_clean.csv
# OR
gsutil cp "adva.tal.csv" "gs://happy-lolli-bucket-1/New/report_2023-2025 adva.tal payoneer.csv"

# 3. Load to BigQuery (choose one)
bq load --source_format=CSV --skip_leading_rows=1 --project_id=onyga-482313 --replace \
  onyga-482313:OI.SRC_BANK_PAYONEER_HAPPY_LOLLI \
  gs://happy-lolli-bucket-1/staging/payoneer_happy_lolli_clean.csv \
  transaction_date:DATE,description:STRING,amount:FLOAT64,currency:STRING,status:STRING,transaction_id:STRING

# OR
bq load --source_format=CSV --skip_leading_rows=1 --project_id=onyga-482313 --allow_quoted_newlines --replace \
  onyga-482313:OI.SRC_BANK_PAYONEER_ADVA_TAL \
  "gs://happy-lolli-bucket-1/New/report_2023-2025 adva.tal payoneer.csv" \
  transaction_date:DATE,description:STRING,amount:FLOAT64,currency:STRING,status:STRING,transaction_id:STRING

# 4. Run stored procedures
bq query --project_id=onyga-482313 --use_legacy_sql=false \
  "CALL \`onyga-482313.OI.SP_STG_UNIFIED_TRANSACTION_SOURCES\`()"

bq query --project_id=onyga-482313 --use_legacy_sql=false \
  "CALL \`onyga-482313.OI.SP_FACT_FINANCIAL_TRANSACTIONS\`()"
```

---

## Troubleshooting

### Issue: Date format errors
- **Solution**: Make sure HAPPY_LOLLI files are preprocessed. ADVA_TAL files should work directly.

### Issue: Permission denied
- **Solution**: Check GCP authentication: `gcloud auth login`

### Issue: Table not found
- **Solution**: Create the table first:
  ```bash
  bq query --project_id=onyga-482313 --use_legacy_sql=false < scripts/Tables/bank_leumi/SRC_BANK_PAYONEER_HAPPY_LOLLI.sql
  bq query --project_id=onyga-482313 --use_legacy_sql=false < scripts/Tables/bank_leumi/SRC_BANK_PAYONEER_ADVA_TAL.sql
  ```

### Issue: bq command not found
- **Solution**: Install Google Cloud SDK or use `gcloud` commands

---

## Data Flow Summary

```
Payoneer CSV
    ↓
[Preprocess for HAPPY_LOLLI only]
    ↓
Upload to GCS
    ↓
Load to SRC_BANK_PAYONEER_* tables
    ↓
SP_STG_UNIFIED_TRANSACTION_SOURCES()
    ↓
STG_UNIFIED_TRANSACTION_SOURCES
    ↓
SP_FACT_FINANCIAL_TRANSACTIONS()
    ↓
FACT_FINANCIAL_TRANSACTIONS (final table)
```

---

## Notes

- **HAPPY_LOLLI** requires preprocessing because dates are in "DD MMM, YYYY" format
- **ADVA_TAL** can be loaded directly (BigQuery auto-detects the date format)
- Use `--replace` to overwrite existing data, or remove it to append
- The stored procedures handle all transformations, currency conversions, and categorization automatically
