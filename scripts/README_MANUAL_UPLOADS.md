# Manual SCP/SQP uploads to BigQuery

## Rule: validate before entering DB

**Always check before loading into the database that:**
1. **All files exist** (paths are valid, files are readable, non-empty).
2. **There are no duplicate files** (no duplicate path in the list).

The upload scripts enforce this by running `validate_upload_files.py` first. If validation fails, no files are loaded.

## Usage

- **SQP (Search Query Performance, ASIN View):**  
  `./scripts/upload_sqp_files.sh file1.csv file2.csv ...`

- **SCP (Search Catalog Performance):**  
  `./scripts/upload_scp_files.sh file1.csv file2.csv ...`

Validation runs automatically; fix any reported errors (missing files, duplicate paths) before re-running.

## Standalone validation

To only validate a list of files (e.g. before a custom load):

```bash
python3 scripts/validate_upload_files.py /path/to/a.csv /path/to/b.csv
```

Exit code 0 = OK; 1 = validation failed.
