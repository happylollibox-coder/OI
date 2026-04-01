#!/bin/bash
# Deploy and Verify Fix for Sales Discrepancy
# This script deploys the updated stored procedure, runs it, and verifies results

set -e

PROJECT_ID="onyga-482313"
DATASET="OI"
SP_FILE="../SP/SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY.sql"
VERIFY_FILE="DEPLOY_AND_VERIFY_FIX.sql"

echo "=========================================="
echo "Deploying Updated Stored Procedure"
echo "=========================================="

# Deploy the stored procedure
echo "Deploying SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY..."
bq query --use_legacy_sql=false --project_id=$PROJECT_ID < "$SP_FILE"

if [ $? -eq 0 ]; then
    echo "✅ Stored procedure deployed successfully"
else
    echo "❌ Failed to deploy stored procedure"
    exit 1
fi

echo ""
echo "=========================================="
echo "Running Stored Procedure"
echo "=========================================="

# Run the stored procedure
echo "Running SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY..."
bq query --use_legacy_sql=false --project_id=$PROJECT_ID \
    "CALL \`$PROJECT_ID.$DATASET.SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY\`();"

if [ $? -eq 0 ]; then
    echo "✅ Stored procedure executed successfully"
else
    echo "❌ Failed to execute stored procedure"
    exit 1
fi

echo ""
echo "=========================================="
echo "Verifying Results for Jan 29, 2026"
echo "=========================================="

# Run verification queries
bq query --use_legacy_sql=false --project_id=$PROJECT_ID < "$VERIFY_FILE"

echo ""
echo "=========================================="
echo "Done!"
echo "=========================================="
