# BigQuery Table Definitions

CREATE TABLE scripts synced with BigQuery objects, organized by prefix.

## Structure

| Folder | Table prefix | Contents |
|--------|--------------|----------|
| **DIM/** | DIM_ | Dimension tables |
| **SRC/** | SRC_ | Source tables (bank, SQP, SCP) |
| **SRC_ACC/** | SRC_ACC_ | Account-specific source tables |
| **STG/** | STG_ | Staging tables |
| **FACT/** | FACT_ | Fact tables |
| **Other/** | — | CFG_, GENERAL_CONVERSION, DE_*, COMPARE_*, UNCATEGORIZED_ |

## Non-CREATE-TABLE files

ALTER scripts, migrations, SPs, preprocess scripts, and one-time scripts are in `archive/scripts/tables_misc/`.
