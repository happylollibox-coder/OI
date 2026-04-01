# Archive Policy: Before Dropping Tables

## Rule

**Before dropping a table, create an archive table with the `ARCHIVE_` prefix.**

## Pattern

### When dropping a table (DROP TABLE)

```sql
-- Step 1: Create archive table with current data
CREATE OR REPLACE TABLE `onyga-482313.OI.ARCHIVE_<TABLE_NAME>` AS
SELECT * FROM `onyga-482313.OI.<TABLE_NAME>`;

-- Step 2: Drop the original table
DROP TABLE `onyga-482313.OI.<TABLE_NAME>`;
```

### When truncating (TRUNCATE + full refresh)

If the procedure does TRUNCATE + INSERT (full refresh), archive before truncating:

```sql
-- Step 1: Create archive table with current data (only if table has rows)
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.ARCHIVE_<TABLE_NAME>` 
PARTITION BY <same as source>
AS SELECT * FROM `onyga-482313.OI.<TABLE_NAME>`;

-- Step 2: TRUNCATE the original table
TRUNCATE TABLE `onyga-482313.OI.<TABLE_NAME>`;

-- Step 3: INSERT new data...
```

**Note:** For high-frequency TRUNCATE+INSERT procedures (e.g. daily full refresh), archive only when **intentionally replacing or retiring** the table, not on every scheduled run. Use archival for migrations or one-time schema changes.

## Naming

- Archive table: `ARCHIVE_<original_table_name>`
- Example: `FACT_AMAZON_ADS` → `ARCHIVE_FACT_AMAZON_ADS`
- Example: `TimeDIM` → `ARCHIVE_TimeDIM`

## When to Archive

- **DROP TABLE**: Always archive first.
- **Migration / rename**: Archive source table before dropping.
- **Schema change requiring table recreation**: Archive before DROP/CREATE.
- **Regular TRUNCATE+INSERT in stored procedures**: Typically do NOT archive on each run (would duplicate data every run). Archive only for migrations or manual recovery points.
