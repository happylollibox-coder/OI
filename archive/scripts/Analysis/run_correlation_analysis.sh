#!/bin/bash

# Correlation Analysis Runner
# Runs correlation queries and saves results for analysis

PROJECT_ID="onyga-482313"
DATASET="OI"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$RESULTS_DIR"

echo "=========================================="
echo "Running Correlation Analysis"
echo "Project: $PROJECT_ID"
echo "Dataset: $DATASET"
echo "Timestamp: $TIMESTAMP"
echo "=========================================="
echo ""

# Extract and run each query from the SQL file
SQL_FILE="$SCRIPT_DIR/CORRELATION_ANALYSIS_FOCUSED.sql"

# Query 1: Search Term Level Correlation
echo "Running Query 1: Search Term Level Correlation..."
bq query --use_legacy_sql=false \
  --project_id=$PROJECT_ID \
  --format=csv \
  --max_rows=10000 \
  "$(sed -n '19,138p' "$SQL_FILE")" > "$RESULTS_DIR/query1_search_term_correlation_${TIMESTAMP}.csv" 2>&1

if [ $? -eq 0 ]; then
  echo "✅ Query 1 completed"
  echo "   Results: $RESULTS_DIR/query1_search_term_correlation_${TIMESTAMP}.csv"
else
  echo "❌ Query 1 failed - check results file for errors"
fi
echo ""

# Query 2: Statistical Correlation Coefficients
echo "Running Query 2: Statistical Correlation Coefficients..."
bq query --use_legacy_sql=false \
  --project_id=$PROJECT_ID \
  --format=csv \
  "$(sed -n '144,207p' "$SQL_FILE")" > "$RESULTS_DIR/query2_statistical_correlation_${TIMESTAMP}.csv" 2>&1

if [ $? -eq 0 ]; then
  echo "✅ Query 2 completed"
  echo "   Results: $RESULTS_DIR/query2_statistical_correlation_${TIMESTAMP}.csv"
else
  echo "❌ Query 2 failed - check results file for errors"
fi
echo ""

# Query 3: ASIN-Level Correlation Summary
echo "Running Query 3: ASIN-Level Correlation Summary..."
bq query --use_legacy_sql=false \
  --project_id=$PROJECT_ID \
  --format=csv \
  --max_rows=1000 \
  "$(sed -n '213,292p' "$SQL_FILE")" > "$RESULTS_DIR/query3_asin_summary_${TIMESTAMP}.csv" 2>&1

if [ $? -eq 0 ]; then
  echo "✅ Query 3 completed"
  echo "   Results: $RESULTS_DIR/query3_asin_summary_${TIMESTAMP}.csv"
else
  echo "❌ Query 3 failed - check results file for errors"
fi
echo ""

# Query 4: Top 100 Investment Opportunities
echo "Running Query 4: Top 100 Investment Opportunities..."
bq query --use_legacy_sql=false \
  --project_id=$PROJECT_ID \
  --format=csv \
  --max_rows=1000 \
  "$(sed -n '298,346p' "$SQL_FILE")" > "$RESULTS_DIR/query4_top_opportunities_${TIMESTAMP}.csv" 2>&1

if [ $? -eq 0 ]; then
  echo "✅ Query 4 completed"
  echo "   Results: $RESULTS_DIR/query4_top_opportunities_${TIMESTAMP}.csv"
else
  echo "❌ Query 4 failed - check results file for errors"
fi
echo ""

echo "=========================================="
echo "Analysis Complete!"
echo "Results saved in: $RESULTS_DIR"
echo "=========================================="
