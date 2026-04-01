# Archive

Non-active and one-off assets moved here to keep the project root and `scripts/` focused on current schema, pipelines, and tests.

## Structure

- **data/** – Sample/upload CSVs and schema JSON (SQP, SCP, Leumi, reports). Not part of the live pipeline.
- **docs/** – One-off and superseded guides (correlation, currency, upload, deployment, pilot/campaign docs).
- **scripts/** – One-off SQL/shell and former script folders:
  - **Admin/** – Ad-hoc analysis, ASIN insights, merge feasibility, correlation investigations.
  - **Analysis/** – Correlation and pilot-finding SQL and scripts.
  - **Verification/** – One-off verification queries and reports.
  - Root-level one-off scripts: `test_currency.sql`, `TEST_REMOTE_FUNCTION.sql`, `update_rates_manual.sql`, setup/monitor shell scripts.
  - **Interface_Views_misc/** – Files that were in Interface Views but are not interface views: `check_sales_module_distribution.sql`, `Script-8.sql`, `test_new_fields.sql`, `test_unified_scp_view.sql`.
  - **SP_misc/** – Files that were in SP but don't start with `SP_`: one-time copy/dedupe/verify scripts, READMEs.

## What stays active

- **Root:** `README.md`, `Makefile`, `.funcignore`, `.venv/`, `deployment/`, `data-entry-app/`, `cloud-functions/`, `POWER BI/`, `Amazon Business/`.
- **scripts/** – `Tables/`, `SP/`, `Stored Procedures/`, `Interface Views/`, `Tests/`, `Views/`, `Functions/`, `Data/`, `Queries/`, and utility scripts like `load_historical_rates.py`, `update_exchange_rates.py`.

To restore something from archive, move it back to the path it had before (e.g. `archive/scripts/Admin` → `scripts/Admin`).
