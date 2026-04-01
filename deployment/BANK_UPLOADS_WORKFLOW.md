# Bank Data Upload Workflow

## Overview

The bank data upload system has been redesigned to prevent duplicates using a **SRC → SRC_ACC → VIEW** architecture.

## Architecture

```
New Bank Files
     ↓
SRC_BANK_* (temporary staging)
     ↓
SP_PROCESS_BANK_UPLOADS (MERGE + TRUNCATE)
     ↓
SRC_ACC_BANK_* (accumulated, deduplicated)
     ↓
V_SRC_BANK_* (views)
     ↓
V_UNIFIED_TRANSACTION_SOURCES
     ↓
STG_UNIFIED_TRANSACTION_SOURCES
     ↓
FACT_FINANCIAL_TRANSACTIONS
```

## Tables

### Staging Tables (Temporary)
- **SRC_BANK_LEUMI_FOREIGN** - Truncated after each processing
- **SRC_BANK_LEUMI_ILS** - Truncated after each processing  
- **SRC_BANK_PAYONEER_HAPPY_LOLLI** - Truncated after each processing

### Accumulated Tables (Historical)
- **SRC_ACC_BANK_LEUMI_FOREIGN** - All historical data (deduplicated)
- **SRC_ACC_BANK_LEUMI_ILS** - All historical data (deduplicated)
- **SRC_ACC_BANK_PAYONEER_HAPPY_LOLLI** - All historical data (deduplicated)

### Views
- **V_SRC_BANK_LEUMI_FOREIGN** → reads from `SRC_ACC_BANK_LEUMI_FOREIGN`
- **V_SRC_BANK_LEUMI_ILS** → reads from `SRC_ACC_BANK_LEUMI_ILS`

## Workflow

### 1. Upload New Bank Data

Load new bank transaction files into the **SRC_BANK_*** tables using your preferred method (bq load, manual insert, etc.).

Example:
```bash
bq load --source_format=CSV \
  onyga-482313:OI.SRC_BANK_LEUMI_FOREIGN \
  gs://your-bucket/leumi_foreign_2026_02.csv \
  branch:INTEGER,account:STRING,currency:STRING,transaction_date:DATE,...
```

### 2. Process Uploads

Run the processing procedure:
```sql
CALL `onyga-482313.OI.SP_PROCESS_BANK_UPLOADS`();
```

This procedure:
- Uses **MERGE** to insert only new transactions into SRC_ACC tables
- Prevents duplicates using natural keys:
  - **LEUMI_FOREIGN/ILS**: `account + transaction_date + reference_number + debit_amount + credit_amount + transaction_description`
  - **PAYONEER**: `transaction_id` (or date + description + amount + currency)
- **TRUNCATES** SRC tables after successful processing
- Returns summary of rows merged

### 3. Refresh Downstream Tables

After processing, refresh the staging and fact tables:
```sql
CALL `onyga-482313.OI.SP_STG_UNIFIED_TRANSACTION_SOURCES`();
CALL `onyga-482313.OI.SP_FACT_FINANCIAL_TRANSACTIONS`();
```

## Duplicate Prevention

### How It Works

1. **MERGE logic** checks if a transaction already exists in SRC_ACC before inserting
2. **Natural keys** uniquely identify each transaction
3. **DISTINCT** in the MERGE source removes duplicates within the upload file itself

### Example

If you accidentally upload the same file twice:
- First run: All transactions inserted into SRC_ACC
- Second run: **0 rows merged** (all duplicates prevented)
- SRC table still truncated after each run

## Monitoring

Check merge results:
```sql
-- View the procedure output to see how many rows were merged
CALL `onyga-482313.OI.SP_PROCESS_BANK_UPLOADS`();
```

Verify no duplicates in SRC_ACC:
```sql
-- Check LEUMI_FOREIGN for duplicates
SELECT account, transaction_date, reference_number, 
       debit_amount, credit_amount, transaction_description, 
       COUNT(*) as cnt
FROM `onyga-482313.OI.SRC_ACC_BANK_LEUMI_FOREIGN`
GROUP BY 1,2,3,4,5,6
HAVING COUNT(*) > 1;
```

## Migration Completed

**Date:** 2026-02-12

**Changes:**
1. ✅ Created `SP_PROCESS_BANK_UPLOADS` procedure
2. ✅ Updated `V_SRC_BANK_LEUMI_FOREIGN` to read from SRC_ACC
3. ✅ Updated `V_SRC_BANK_LEUMI_ILS` to read from SRC_ACC
4. ✅ Migrated existing data from SRC to SRC_ACC (136 + 1,205 + 471 = 1,812 rows)
5. ✅ Tested end-to-end workflow

**Result:**
- No duplicates in SRC_ACC tables
- FACT_FINANCIAL_TRANSACTIONS has 1,939 clean rows
