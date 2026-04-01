-- DE_BULKSHEET_UPLOADS: Logs every action uploaded to Amazon via bulksheet.
-- Used by the learning system to track what changes were executed.
-- Auto-populated from the dashboard when user clicks "Uploaded to Amazon".

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_BULKSHEET_UPLOADS` (
  upload_id STRING NOT NULL,
  batch_id STRING NOT NULL,            -- groups items from a single upload
  uploaded_at DATETIME NOT NULL,
  search_term STRING NOT NULL,
  campaign_id STRING,
  campaign_name STRING,
  action STRING NOT NULL,              -- STOP, NEGATE, REDUCE_BID, etc.
  entity STRING,                       -- Keyword / Negative Keyword
  operation STRING,                    -- Create / Update
  field_changed STRING,                -- bid / state / negative_keyword
  old_value STRING,
  new_value STRING,
  product STRING,
  source STRING DEFAULT 'dashboard'
);
