/**
 * Cloud Function to process files uploaded to GCS hot folder
 * Triggers on file creation/update in the hot folder
 * Routes to different processors based on file type/name
 */

const { Storage } = require('@google-cloud/storage');
const { BigQuery } = require('@google-cloud/bigquery');

const storage = new Storage();
const bigquery = new BigQuery({ projectId: 'onyga-482313' });

/**
 * Sanitize column names for BigQuery compatibility
 * Replaces special characters that aren't supported by BigQuery's default character map
 */
function sanitizeColumnName(name) {
  return name
    .replace(/\//g, '_')           // Replace forward slashes
    .replace(/[^a-zA-Z0-9_]/g, '_') // Replace other special chars with underscore
    .replace(/^_+|_+$/g, '')       // Remove leading/trailing underscores
    .replace(/_+/g, '_');           // Collapse multiple underscores
}

// Configuration
const CONFIG = {
  projectId: 'onyga-482313',
  datasetId: 'OI',
  bucketName: 'onyga-482313-hot-folder', // Will be created by setup script
  hotFolderPrefix: 'incoming/', // Files uploaded here trigger processing
  archiveFolderPrefix: 'archive/', // Processed files moved here
  errorFolderPrefix: 'errors/', // Failed files moved here
  // Folder structure for different file types
  fileTypeFolders: {
    'csv': 'incoming/csv/',
    'excel': 'incoming/excel/',
    'xlsx': 'incoming/excel/',
    'xls': 'incoming/excel/',
    'json': 'incoming/json/',
    'txt': 'incoming/text/',
    'default': 'incoming/other/' // For unmatched file types
  },
  // File type handlers - add your file types here
  fileHandlers: {
    '.csv': 'processCSV',
    '.xlsx': 'processExcel',
    '.xls': 'processExcel',
    '.json': 'processJSON',
    '.txt': 'processText',
    // Add more file types as needed
  },
  // File-to-table mapping: determines which BigQuery table to load each file into
  // Matches are checked in order - first match wins
  // Priority: folder path > filename pattern > default
  tableMapping: [
    // CSV folder mappings
    {
      folderPath: 'incoming/csv/payoneer/', // Files in this folder
      filenameContains: null,
      filenameStartsWith: null,
      filenameEndsWith: null,
      exactMatch: null,
      tableId: 'SRC_BANK_PAYONEER_HAPPY_LOLLI',
      datasetId: 'OI',
      loadMode: 'WRITE_APPEND',
      skipLeadingRows: 1,
      autodetect: false,
      schema: [
        { name: 'transaction_date', type: 'DATE' },
        { name: 'description', type: 'STRING' },
        { name: 'amount', type: 'FLOAT64' },
        { name: 'currency', type: 'STRING' },
        { name: 'status', type: 'STRING' },
        { name: 'running_balance', type: 'FLOAT64' },
        { name: 'transaction_id', type: 'STRING' }
      ],
      writeDisposition: 'WRITE_APPEND'
    },
    {
      folderPath: 'incoming/csv/leumi/',
      filenameContains: null,
      filenameStartsWith: null,
      filenameEndsWith: null,
      exactMatch: null,
      tableId: 'SRC_BANK_LEUMI_ILS',
      datasetId: 'OI',
      loadMode: 'WRITE_APPEND',
      skipLeadingRows: 1,
      autodetect: true,
      schema: null
    },
    {
      folderPath: 'incoming/csv/currency/',
      filenameContains: null,
      filenameStartsWith: null,
      filenameEndsWith: null,
      exactMatch: null,
      tableId: 'SRC_CURRENCY_RATES',
      datasetId: 'OI',
      loadMode: 'WRITE_TRUNCATE',
      skipLeadingRows: 0,
      autodetect: true,
      schema: null
    },
    // Amazon Inventory folder mappings
    {
      folderPath: 'incoming/csv/Inventory_Ledger_Summary/',
      filenameContains: null,      // Not used - folder path determines routing
      filenameStartsWith: null,    // Not used
      filenameEndsWith: null,      // Not used
      exactMatch: null,            // Not used
      tableId: 'SRC_INVENTORY_FBA',
      datasetId: 'OI',
      loadMode: 'WRITE_TRUNCATE',
      skipLeadingRows: 1,
      autodetect: true,
      schema: null,
      writeDisposition: 'WRITE_TRUNCATE'
    },
    {
      folderPath: 'incoming/csv/AWD_Inventory_Ledger_Summary/',
      filenameContains: null,      // Not used - folder path determines routing
      filenameStartsWith: null,    // Not used
      filenameEndsWith: null,      // Not used
      exactMatch: null,            // Not used
      tableId: 'SRC_INVENTORY_AWD',
      datasetId: 'OI',
      loadMode: 'WRITE_TRUNCATE',
      skipLeadingRows: 1,
      autodetect: true,
      schema: null,
      writeDisposition: 'WRITE_TRUNCATE'
    },
    // Excel folder mappings
    {
      folderPath: 'incoming/excel/reports/',
      filenameContains: null,
      filenameStartsWith: null,
      filenameEndsWith: null,
      exactMatch: null,
      tableId: 'SRC_EXCEL_REPORTS',
      datasetId: 'OI',
      loadMode: 'WRITE_APPEND',
      skipLeadingRows: 1,
      autodetect: true,
      schema: null
    },
    // JSON folder mappings
    {
      folderPath: 'incoming/json/api/',
      filenameContains: null,
      filenameStartsWith: null,
      filenameEndsWith: null,
      exactMatch: null,
      tableId: 'SRC_API_DATA',
      datasetId: 'OI',
      loadMode: 'WRITE_APPEND',
      skipLeadingRows: 0,
      autodetect: true,
      schema: null
    },
    // Fallback: Match by folder type (csv, excel, json, etc.)
    {
      folderPath: 'incoming/csv/', // Any CSV file in csv folder
      filenameContains: null,
      filenameStartsWith: null,
      filenameEndsWith: null,
      exactMatch: null,
      tableId: 'SRC_CSV_DEFAULT',
      datasetId: 'OI',
      loadMode: 'WRITE_APPEND',
      skipLeadingRows: 1,
      autodetect: true,
      schema: null
    },
    {
      folderPath: 'incoming/excel/',
      filenameContains: null,
      filenameStartsWith: null,
      filenameEndsWith: null,
      exactMatch: null,
      tableId: 'SRC_EXCEL_DEFAULT',
      datasetId: 'OI',
      loadMode: 'WRITE_APPEND',
      skipLeadingRows: 1,
      autodetect: true,
      schema: null
    },
    {
      folderPath: 'incoming/json/',
      filenameContains: null,
      filenameStartsWith: null,
      filenameEndsWith: null,
      exactMatch: null,
      tableId: 'SRC_JSON_DEFAULT',
      datasetId: 'OI',
      loadMode: 'WRITE_APPEND',
      skipLeadingRows: 0,
      autodetect: true,
      schema: null
    },
    // Default fallback - if no pattern matches
    {
      folderPath: null,
      filenameContains: null,
      filenameStartsWith: null,
      filenameEndsWith: null,
      exactMatch: null,
      tableId: 'HOT_FOLDER_DEFAULT',
      datasetId: 'OI',
      loadMode: 'WRITE_APPEND',
      skipLeadingRows: 1,
      autodetect: true,
      schema: null
    }
  ]
};

/**
 * Load file to BigQuery table with retry logic and error handling
 */
async function loadToBigQuery(file, bucket, tableConfig) {
  const datasetId = tableConfig.datasetId || CONFIG.datasetId;
  const tableId = tableConfig.tableId;
  
  console.log(`Loading file ${file.name} to BigQuery table: ${datasetId}.${tableId}`);
  
  // Verify file exists before attempting load
  try {
    const [fileExists] = await bucket.file(file.name).exists();
    if (!fileExists) {
      throw new Error(`File ${file.name} does not exist in bucket ${file.bucket}`);
    }
    console.log(`Verified file exists: ${file.name}`);
    
    // Small delay to ensure file is fully available for BigQuery
    // This helps avoid race conditions with GCS eventual consistency
    await new Promise(resolve => setTimeout(resolve, 1000));
  } catch (error) {
    console.error(`Error checking file existence: ${error.message}`);
    throw error;
  }
  
  // Get the Storage File object (required by BigQuery Node.js client for GCS files)
  const gcsFile = bucket.file(file.name);
  const gcsUri = `gs://${file.bucket}/${file.name}`;
  console.log(`GCS URI: ${gcsUri}`);
  
  // Get file extension first (needed for options configuration)
  const fileExt = getFileExtension(file.name);
  
  // Prepare load job options
  const options = {
    sourceFormat: 'CSV', // Will be adjusted based on file type
    writeDisposition: tableConfig.writeDisposition || tableConfig.loadMode,
    skipLeadingRows: tableConfig.skipLeadingRows || 0,
    // Additional options
    allowJaggedRows: true,
    allowQuotedNewlines: true,
    ignoreUnknownValues: true
  };
  
  // Handle schema and autodetect - if schema is provided, disable autodetect
  if (tableConfig.schema && Array.isArray(tableConfig.schema) && tableConfig.schema.length > 0) {
    options.autodetect = false;
    // Convert schema array to BigQuery format
    options.schema = {
      fields: tableConfig.schema.map(field => ({
        name: field.name,
        type: field.type
      }))
    };
    console.log(`Using provided schema with ${options.schema.fields.length} fields`);
  } else {
    options.autodetect = tableConfig.autodetect !== false;
    console.log(`Using autodetect: ${options.autodetect}`);
  }
  
  // Adjust source format based on file extension and set character map V2 for CSV files
  if (fileExt === '.json') {
    options.sourceFormat = 'NEWLINE_DELIMITED_JSON';
  } else if (fileExt === '.csv') {
    options.sourceFormat = 'CSV';
    // Set character map V2 for CSV files to handle special characters in column names (like forward slashes)
    options.columnNameCharacterMap = 'V2'; // Replaces unsupported characters with underscores
  } else if (fileExt === '.xlsx' || fileExt === '.xls') {
    // Excel files need to be converted to CSV first
    throw new Error('Excel files must be converted to CSV before loading to BigQuery');
  }
  
  // Get dataset and table references
  const dataset = bigquery.dataset(datasetId);
  const table = dataset.table(tableId);
  
  // Check if table exists
  const [tableExists] = await table.exists();
  if (!tableExists) {
    console.log(`Table ${datasetId}.${tableId} does not exist, will be created on first load`);
  } else {
    console.log(`Table ${datasetId}.${tableId} exists`);
  }
  
  // Retry logic for BigQuery load
  const maxRetries = 3;
  let lastError;
  
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      console.log(`Starting BigQuery load job (attempt ${attempt}/${maxRetries}) from ${gcsUri}...`);
      console.log(`Load options:`, JSON.stringify(options, null, 2));
      
      // Load data from GCS - BigQuery Node.js client requires a Storage File object, not a URI string
      const [job] = await table.load(gcsFile, options);
      
      console.log(`Load job ${job.id} started`);
      
      // Extract job ID (job.id might be full reference like "project:location.jobId" or just "jobId")
      const jobIdParts = job.id.split('.');
      const jobId = jobIdParts.length > 1 ? jobIdParts[jobIdParts.length - 1] : job.id;
      
      // Wait for job to complete - poll job status using job reference
      let jobComplete = false;
      let jobResult;
      let pollAttempts = 0;
      const maxPollAttempts = 120; // 2 minutes max (1 second intervals)
      
      while (!jobComplete && pollAttempts < maxPollAttempts) {
        await new Promise(resolve => setTimeout(resolve, 1000)); // Wait 1 second
        
        // Get job status - use the job object's getMetadata method if available, otherwise poll
        try {
          // Try using the job object directly
          if (typeof job.getMetadata === 'function') {
            [jobResult] = await job.getMetadata();
          } else {
            // Fallback: get job by ID from BigQuery client
            const jobRef = bigquery.job(jobId);
            [jobResult] = await jobRef.getMetadata();
          }
        } catch (error) {
          console.error(`Error getting job metadata: ${error.message}`);
          throw error;
        }
        
        if (jobResult.status && jobResult.status.state === 'DONE') {
          jobComplete = true;
        } else {
          pollAttempts++;
          const state = jobResult.status?.state || 'UNKNOWN';
          console.log(`Job ${jobId} status: ${state} (poll ${pollAttempts}/${maxPollAttempts})`);
        }
      }
      
      if (!jobComplete) {
        throw new Error(`BigQuery load job ${jobId} did not complete within timeout`);
      }
      
      console.log(`Job status: ${jobResult.status.state}`);
      
      // Check for job errors
      if (jobResult.status.errors && jobResult.status.errors.length > 0) {
        const errorMessages = jobResult.status.errors.map(e => e.message).join('; ');
        throw new Error(`BigQuery load job failed: ${errorMessages}`);
      }
      
      const rowsLoaded = jobResult.statistics?.load?.outputRows || 0;
      
      console.log(`✅ Successfully loaded ${rowsLoaded} rows to ${datasetId}.${tableId}`);
      
      return {
        success: true,
        jobId: job.id,
        rowsLoaded: parseInt(rowsLoaded),
        table: `${datasetId}.${tableId}`
      };
      
    } catch (error) {
      lastError = error;
      console.error(`BigQuery load attempt ${attempt} failed:`, error.message);
      console.error(`Error details:`, JSON.stringify(error, null, 2));
      
      // Check if error is retryable (5xx errors, rate limits, etc.)
      const isRetryable = error.code === 503 || 
                         error.code === 500 || 
                         error.code === 429 ||
                         (error.message && error.message.includes('rate limit')) ||
                         (error.message && error.message.includes('backend error'));
      
      if (!isRetryable || attempt === maxRetries) {
        // Not retryable or max retries reached
        throw new Error(`BigQuery load failed after ${attempt} attempt(s): ${error.message}`);
      }
      
      // Wait before retry with exponential backoff
      const waitTime = Math.pow(2, attempt - 1) * 1000; // 1s, 2s, 4s
      console.log(`Retrying in ${waitTime}ms...`);
      await new Promise(resolve => setTimeout(resolve, waitTime));
    }
  }
  
  // Should never reach here, but just in case
  throw lastError || new Error('BigQuery load failed for unknown reason');
}

/**
 * Move data from SRC table to SRC_ACC table with deduplication
 * Deletes rows where date field matches, then inserts new rows
 * @param {string} srcTableId - Source table ID
 * @param {string} accTableId - Accumulation table ID
 * @param {string} fileName - File name for tracking
 * @param {string} dateFieldName - Name of the date field (default: 'Date')
 */
async function moveToAccumulationTable(srcTableId, accTableId, fileName, dateFieldName = 'Date') {
  const datasetId = CONFIG.datasetId;
  const srcTable = `${datasetId}.${srcTableId}`;
  const accTable = `${datasetId}.${accTableId}`;
  
  console.log(`Moving data from ${srcTable} to ${accTable} (using date field: ${dateFieldName})`);
  
  // Step 1: Delete rows from accumulation table where date field matches source
  // This deletes all rows for the date being loaded
  const deleteQuery = `
    DELETE FROM \`${accTable}\` acc
    WHERE EXISTS (
      SELECT 1
      FROM \`${srcTable}\` src
      WHERE src.\`${dateFieldName}\` = acc.\`${dateFieldName}\`
        AND src.\`${dateFieldName}\` IS NOT NULL
    )
  `;
  
  console.log(`Executing delete query...`);
  const [deleteJob] = await bigquery.createQueryJob({
    query: deleteQuery,
    location: 'US'
  });
  
  // Wait for delete job to complete
  let deleteComplete = false;
  let deleteResult;
  let deletePollAttempts = 0;
  const maxDeletePollAttempts = 120;
  
  while (!deleteComplete && deletePollAttempts < maxDeletePollAttempts) {
    await new Promise(resolve => setTimeout(resolve, 1000));
    try {
      const jobIdParts = deleteJob.id.split('.');
      const jobId = jobIdParts.length > 1 ? jobIdParts[jobIdParts.length - 1] : deleteJob.id;
      const jobRef = bigquery.job(jobId);
      [deleteResult] = await jobRef.getMetadata();
      
      if (deleteResult.status && deleteResult.status.state === 'DONE') {
        deleteComplete = true;
      } else {
        deletePollAttempts++;
      }
    } catch (error) {
      console.error(`Error polling delete job: ${error.message}`);
      throw error;
    }
  }
  
  if (!deleteComplete) {
    throw new Error(`Delete query did not complete within timeout`);
  }
  
  if (deleteResult.status.errors && deleteResult.status.errors.length > 0) {
    throw new Error(`Delete query failed: ${deleteResult.status.errors.map(e => e.message).join('; ')}`);
  }
  
  const numDeleted = deleteResult.statistics?.query?.numDmlAffectedRows || 0;
  console.log(`Deleted ${numDeleted} rows from ${accTable}`);
  
  // Step 2: Insert all rows from source to accumulation table with metadata
  // Use string interpolation for fileName since parameterized queries can be complex
  // For AWD tables, we need to map columns differently due to schema differences
  let insertQuery;
  if (srcTableId === 'SRC_INVENTORY_AWD') {
    // AWD has different column names - map them to match accumulation table schema
    insertQuery = `
      INSERT INTO \`${accTable}\`
      SELECT 
        Date,
        FNSKU,
        ASIN,
        MSKU,
        Title,
        CAST(NULL AS STRING) AS Disposition,
        \`Starting Warehouse Balance _cartons_\` AS \`Starting Warehouse Balance\`,
        CAST(NULL AS INT64) AS \`In Transit Between Warehouses\`,
        \`Received _cartons_\` AS Receipts,
        \`Departed _cartons_\` AS \`Customer Shipments\`,
        CAST(NULL AS INT64) AS \`Customer Returns\`,
        CAST(NULL AS INT64) AS \`Vendor Returns\`,
        CAST(NULL AS INT64) AS \`Warehouse Transfer In_Out\`,
        \`Found _cartons_\` AS Found,
        \`Lost _cartons_\` AS Lost,
        CAST(NULL AS INT64) AS Damaged,
        CAST(NULL AS INT64) AS Disposed,
        \`Other _cartons_\` AS \`Other Events\`,
        \`Ending Warehouse Balance _cartons_\` AS \`Ending Warehouse Balance\`,
        \`Unknown _cartons_\` AS \`Unknown Events\`,
        \`Facility ID\` AS Location,
        CAST(NULL AS STRING) AS Store,
        CURRENT_TIMESTAMP() as insert_date,
        '${fileName.replace(/'/g, "''")}' as insert_file_name,
        \`Package Quantity\` AS \`Package Quantity\`
      FROM \`${srcTable}\`
    `;
  } else {
    // For other tables, use SELECT * (they have matching schemas)
    insertQuery = `
      INSERT INTO \`${accTable}\`
      SELECT 
        *,
        CURRENT_TIMESTAMP() as insert_date,
        '${fileName.replace(/'/g, "''")}' as insert_file_name
      FROM \`${srcTable}\`
    `;
  }
  
  console.log(`Executing insert query...`);
  const [insertJob] = await bigquery.createQueryJob({
    query: insertQuery,
    location: 'US',
    jobTimeoutMs: 300000 // 5 minutes
  });
  
  // Wait for insert job to complete
  let insertComplete = false;
  let insertResult;
  let insertPollAttempts = 0;
  const maxInsertPollAttempts = 120;
  
  while (!insertComplete && insertPollAttempts < maxInsertPollAttempts) {
    await new Promise(resolve => setTimeout(resolve, 1000));
    try {
      const jobIdParts = insertJob.id.split('.');
      const jobId = jobIdParts.length > 1 ? jobIdParts[jobIdParts.length - 1] : insertJob.id;
      const jobRef = bigquery.job(jobId);
      [insertResult] = await jobRef.getMetadata();
      
      if (insertResult.status && insertResult.status.state === 'DONE') {
        insertComplete = true;
      } else {
        insertPollAttempts++;
      }
    } catch (error) {
      console.error(`Error polling insert job: ${error.message}`);
      throw error;
    }
  }
  
  if (!insertComplete) {
    throw new Error(`Insert query did not complete within timeout`);
  }
  
  if (insertResult.status.errors && insertResult.status.errors.length > 0) {
    throw new Error(`Insert query failed: ${insertResult.status.errors.map(e => e.message).join('; ')}`);
  }
  
  const numInserted = insertResult.statistics?.query?.numDmlAffectedRows || 0;
  console.log(`Inserted ${numInserted} rows into ${accTable}`);
  
  return {
    deleted: parseInt(numDeleted),
    inserted: parseInt(numInserted)
  };
}

/**
 * Process CSV files
 */
async function processCSV(file, bucket, tableConfig) {
  console.log(`Processing CSV file: ${file.name}`);
  
  // Find table mapping for this file
  if (!tableConfig) {
    tableConfig = findTableMapping(file.name);
  }
  
  // Load to BigQuery
  const loadResult = await loadToBigQuery(file, bucket, tableConfig);
  
  // Move data to accumulation table if applicable
  const accumulationMappings = {
    'SRC_INVENTORY_FBA': { accTable: 'SRC_ACC_INVENTORY_FBA', dateField: 'Date' },
    'SRC_INVENTORY_AWD': { accTable: 'SRC_ACC_INVENTORY_AWD', dateField: 'Date' },
    'SRC_BANK_LEUMI_FOREIGN': { accTable: 'SRC_ACC_BANK_LEUMI_FOREIGN', dateField: 'transaction_date' },
    'SRC_BANK_LEUMI_ILS': { accTable: 'SRC_ACC_BANK_LEUMI_ILS', dateField: 'transaction_date' },
    'SRC_BANK_PAYONEER_HAPPY_LOLLI': { accTable: 'SRC_ACC_BANK_PAYONEER_HAPPY_LOLLI', dateField: 'transaction_date' }
  };
  
  if (accumulationMappings[tableConfig.tableId]) {
    const mapping = accumulationMappings[tableConfig.tableId];
    console.log(`Moving data to accumulation table ${mapping.accTable}...`);
    try {
      const accResult = await moveToAccumulationTable(tableConfig.tableId, mapping.accTable, file.name, mapping.dateField);
      console.log(`✅ Accumulation complete: deleted ${accResult.deleted} rows, inserted ${accResult.inserted} rows`);
    } catch (error) {
      console.error(`❌ Error moving to accumulation table: ${error.message}`);
      throw error;
    }
  }
  
  return {
    success: true,
    message: `Processed CSV file and loaded to ${loadResult.table}`,
    rowsProcessed: loadResult.rowsLoaded,
    table: loadResult.table,
    jobId: loadResult.jobId
  };
}

/**
 * Process Excel files
 */
async function processExcel(file, bucket, tableConfig) {
  console.log(`Processing Excel file: ${file.name}`);
  
  // Find table mapping for this file
  if (!tableConfig) {
    tableConfig = findTableMapping(file.name);
  }
  
  // Note: Excel files need to be converted to CSV before loading to BigQuery
  // For now, we'll log an error - you can add xlsx library to convert
  const fileMetadata = await bucket.file(file.name).getMetadata();
  
  // TODO: Add xlsx library to convert Excel to CSV, then load to BigQuery
  // For now, return error suggesting conversion to CSV first
  
  return {
    success: false,
    message: `Excel file detected: ${file.name}. Please convert to CSV first or add xlsx library for automatic conversion.`,
    size: fileMetadata[0].size,
    note: 'Excel processing requires conversion to CSV - add xlsx library to implement',
    tableConfig: tableConfig
  };
}

/**
 * Process JSON files
 */
async function processJSON(file, bucket, tableConfig) {
  console.log(`Processing JSON file: ${file.name}`);
  
  // Find table mapping for this file
  if (!tableConfig) {
    tableConfig = findTableMapping(file.name);
  }
  
  // Load to BigQuery (supports NEWLINE_DELIMITED_JSON format)
  const loadResult = await loadToBigQuery(file, bucket, tableConfig);
  
  return {
    success: true,
    message: `Processed JSON file and loaded to ${loadResult.table}`,
    rowsProcessed: loadResult.rowsLoaded,
    table: loadResult.table,
    jobId: loadResult.jobId
  };
}

/**
 * Process text files
 */
async function processText(file, bucket) {
  console.log(`Processing text file: ${file.name}`);
  
  const [fileBuffer] = await bucket.file(file.name).download();
  const textContent = fileBuffer.toString('utf-8');
  
  return {
    success: true,
    message: `Processed text file with ${textContent.length} characters`,
    length: textContent.length
  };
}

/**
 * Get file extension
 */
function getFileExtension(filename) {
  const lastDot = filename.lastIndexOf('.');
  return lastDot !== -1 ? filename.substring(lastDot).toLowerCase() : '';
}

/**
 * Get file handler function name based on extension
 */
function getFileHandler(extension) {
  return CONFIG.fileHandlers[extension] || null;
}

/**
 * Find table mapping for a file based on folder path and filename patterns
 * Returns the first matching configuration
 * Priority: folder path > filename pattern > default
 */
function findTableMapping(filename) {
  const fileNameOnly = filename.split('/').pop(); // Get just the filename without path
  
  for (const mapping of CONFIG.tableMapping) {
    let matches = true;
    
    // Priority 1: Check folder path (most specific)
    if (mapping.folderPath) {
      if (!filename.startsWith(mapping.folderPath)) {
        matches = false;
      } else {
        // Folder matches, check filename patterns if specified
        if (mapping.exactMatch && fileNameOnly !== mapping.exactMatch) {
          matches = false;
        }
        if (matches && mapping.filenameStartsWith && !fileNameOnly.startsWith(mapping.filenameStartsWith)) {
          matches = false;
        }
        if (matches && mapping.filenameEndsWith && !fileNameOnly.endsWith(mapping.filenameEndsWith)) {
          matches = false;
        }
        if (matches && mapping.filenameContains) {
          const lowerFilename = fileNameOnly.toLowerCase();
          const lowerContains = mapping.filenameContains.toLowerCase();
          if (!lowerFilename.includes(lowerContains)) {
            matches = false;
          }
        }
      }
    } else {
      // No folder path specified, check filename patterns only
      if (mapping.exactMatch && filename !== mapping.exactMatch) {
        matches = false;
      }
      if (matches && mapping.filenameStartsWith && !filename.startsWith(mapping.filenameStartsWith)) {
        matches = false;
      }
      if (matches && mapping.filenameEndsWith && !filename.endsWith(mapping.filenameEndsWith)) {
        matches = false;
      }
      if (matches && mapping.filenameContains) {
        const lowerFilename = filename.toLowerCase();
        const lowerContains = mapping.filenameContains.toLowerCase();
        if (!lowerFilename.includes(lowerContains)) {
          matches = false;
        }
      }
    }
    
    // If all specified patterns match (or no patterns specified for default), return this mapping
    if (matches && (
      mapping.folderPath ||
      mapping.filenameContains || 
      mapping.filenameStartsWith || 
      mapping.filenameEndsWith || 
      mapping.exactMatch ||
      (!mapping.folderPath && !mapping.filenameContains && !mapping.filenameStartsWith && !mapping.filenameEndsWith && !mapping.exactMatch) // Default fallback
    )) {
      console.log(`Matched file ${filename} to table ${mapping.tableId} using:`, {
        folderPath: mapping.folderPath,
        contains: mapping.filenameContains,
        startsWith: mapping.filenameStartsWith,
        endsWith: mapping.filenameEndsWith,
        exact: mapping.exactMatch
      });
      return mapping;
    }
  }
  
  // Should never reach here if default mapping exists, but just in case
  throw new Error(`No table mapping found for file: ${filename}`);
}

/**
 * Move file to archive folder and delete from source
 * The move() operation copies to destination and deletes from source
 */
async function moveToArchive(bucket, fileName, success = true) {
  const sourcePath = fileName;
  const destinationPath = success 
    ? `${CONFIG.archiveFolderPrefix}${new Date().toISOString().split('T')[0]}/${fileName.replace(CONFIG.hotFolderPrefix, '')}`
    : `${CONFIG.errorFolderPrefix}${new Date().toISOString().split('T')[0]}/${fileName.replace(CONFIG.hotFolderPrefix, '')}`;
  
  try {
    // Move operation: copies to destination and deletes from source
    await bucket.file(sourcePath).move(destinationPath);
    console.log(`Moved file from ${sourcePath} to ${destinationPath}`);
    
    // Verify source file is deleted (move should have done this, but verify)
    const [sourceExists] = await bucket.file(sourcePath).exists();
    if (sourceExists) {
      console.warn(`Warning: Source file ${sourcePath} still exists after move, deleting explicitly...`);
      await bucket.file(sourcePath).delete();
      console.log(`Explicitly deleted source file: ${sourcePath}`);
    } else {
      console.log(`✅ Verified: Source file ${sourcePath} successfully deleted from hot folder`);
    }
    
    return destinationPath;
  } catch (error) {
    console.error(`Error moving file: ${error.message}`);
    throw error;
  }
}

/**
 * Main Cloud Function entry point
 * Triggered by Cloud Storage events via Pub/Sub (Eventarc)
 * Eventarc wraps Pub/Sub messages in CloudEvents format
 */
exports.processHotFolderFile = async (cloudEvent) => {
  console.log('Received CloudEvent:', JSON.stringify(cloudEvent, null, 2));
  
  // Eventarc sends CloudEvents with data containing the Pub/Sub message
  let messageData;
  try {
    // CloudEvents format: cloudEvent.data contains the Pub/Sub message
    // The Pub/Sub message data is base64 encoded JSON
    if (cloudEvent.data && cloudEvent.data.message && cloudEvent.data.message.data) {
      // Standard Pub/Sub message wrapped in CloudEvent
      const messageString = Buffer.from(cloudEvent.data.message.data, 'base64').toString();
      messageData = JSON.parse(messageString);
    } else if (cloudEvent.data && cloudEvent.data.bucket) {
      // Direct GCS notification data (some formats)
      messageData = cloudEvent.data;
    } else {
      // Try parsing cloudEvent.data directly
      messageData = typeof cloudEvent.data === 'string' 
        ? JSON.parse(Buffer.from(cloudEvent.data, 'base64').toString())
        : cloudEvent.data;
    }
  } catch (error) {
    console.error('Error parsing CloudEvent data:', error);
    console.error('CloudEvent structure:', JSON.stringify(cloudEvent, null, 2));
    throw error;
  }
  
  // Extract file information from GCS notification
  const file = {
    bucket: messageData.bucket,
    name: messageData.name,
    contentType: messageData.contentType,
    size: messageData.size,
    timeCreated: messageData.timeCreated,
    updated: messageData.updated
  };
  
  const eventType = messageData.eventType || cloudEvent.attributes?.eventType || 'OBJECT_FINALIZE';
  
  console.log(`Received event for file: ${file.name}`);
  console.log(`Event type: ${eventType}`);
  console.log(`Bucket: ${file.bucket}`);
  
  // Only process finalize events (file uploads/updates) - skip DELETE events early
  if (eventType !== 'OBJECT_FINALIZE') {
    console.log(`Event type ${eventType} is not OBJECT_FINALIZE, skipping`);
    return { success: false, message: `Event type ${eventType} not processed` };
  }
  
  // Only process files in the hot folder
  if (!file.name.startsWith(CONFIG.hotFolderPrefix)) {
    console.log(`File ${file.name} is not in hot folder, skipping`);
    return { success: false, message: 'File not in hot folder' };
  }
  
  console.log(`Processing file: ${file.name}`);
  
  const bucket = storage.bucket(file.bucket);
  const fileExtension = getFileExtension(file.name);
  const handlerName = getFileHandler(fileExtension);
  
  if (!handlerName) {
    console.warn(`No handler found for file type: ${fileExtension}`);
    // Move to errors folder
    await moveToArchive(bucket, file.name, false);
    return {
      success: false,
      error: `No handler configured for file type: ${fileExtension}`
    };
  }
  
  try {
    // Find table mapping for this file
    const tableConfig = findTableMapping(file.name);
    console.log(`Table mapping found: ${tableConfig.datasetId || CONFIG.datasetId}.${tableConfig.tableId}`);
    
    // Process the file
    let result;
    switch (handlerName) {
      case 'processCSV':
        result = await processCSV(file, bucket, tableConfig);
        break;
      case 'processExcel':
        result = await processExcel(file, bucket, tableConfig);
        break;
      case 'processJSON':
        result = await processJSON(file, bucket, tableConfig);
        break;
      case 'processText':
        result = await processText(file, bucket);
        break;
      default:
        throw new Error(`Handler ${handlerName} not implemented`);
    }
    
    // Move file to archive on success
    if (result.success) {
      await moveToArchive(bucket, file.name, true);
    } else {
      await moveToArchive(bucket, file.name, false);
    }
    
    console.log(`✅ Successfully processed: ${file.name}`);
    return result;
    
  } catch (error) {
    console.error(`❌ Error processing file ${file.name}:`, error);
    
    // Move to errors folder
    try {
      await moveToArchive(bucket, file.name, false);
    } catch (moveError) {
      console.error(`Failed to move file to errors folder: ${moveError.message}`);
    }
    
    // Re-throw to mark function as failed
    throw error;
  }
};
