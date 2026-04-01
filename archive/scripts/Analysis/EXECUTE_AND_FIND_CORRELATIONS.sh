#!/bin/bash

# Execute Correlation Analysis and Find Strong Correlations
# This script runs all correlation queries and finds the strongest results

PROJECT_ID="onyga-482313"
DATASET="OI"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$RESULTS_DIR"

echo "=========================================="
echo "AGGRESSIVE CORRELATION HUNT"
echo "Project: $PROJECT_ID"
echo "Timestamp: $TIMESTAMP"
echo "=========================================="
echo ""

# Set project
gcloud config set project $PROJECT_ID 2>/dev/null

# Strategy 1: Lower Thresholds
echo "Running Strategy 1: Lower Thresholds..."
bq query --use_legacy_sql=false \
  --project_id=$PROJECT_ID \
  --format=csv \
  "$(sed -n '17,35p' "$SCRIPT_DIR/AGGRESSIVE_CORRELATION_HUNT.sql")" \
  > "$RESULTS_DIR/strategy1_${TIMESTAMP}.csv" 2>&1

if [ $? -eq 0 ]; then
  echo "✅ Strategy 1 completed"
  echo "   Checking for strong correlations..."
  STRONG_COUNT=$(grep -c "0\.5\|0\.6\|0\.7\|0\.8\|0\.9\|1\.0" "$RESULTS_DIR/strategy1_${TIMESTAMP}.csv" 2>/dev/null || echo "0")
  echo "   Found correlations: $STRONG_COUNT"
else
  echo "❌ Strategy 1 failed"
fi
echo ""

# Strategy 2: ASIN-Level
echo "Running Strategy 2: ASIN-Level Aggregation..."
bq query --use_legacy_sql=false \
  --project_id=$PROJECT_ID \
  --format=csv \
  "$(sed -n '37,65p' "$SCRIPT_DIR/AGGRESSIVE_CORRELATION_HUNT.sql")" \
  > "$RESULTS_DIR/strategy2_${TIMESTAMP}.csv" 2>&1

if [ $? -eq 0 ]; then
  echo "✅ Strategy 2 completed"
  STRONG_COUNT=$(grep -c "0\.5\|0\.6\|0\.7\|0\.8\|0\.9\|1\.0" "$RESULTS_DIR/strategy2_${TIMESTAMP}.csv" 2>/dev/null || echo "0")
  echo "   Found correlations: $STRONG_COUNT"
else
  echo "❌ Strategy 2 failed"
fi
echo ""

# Strategy 3: High-Volume Terms
echo "Running Strategy 3: High-Volume Terms..."
bq query --use_legacy_sql=false \
  --project_id=$PROJECT_ID \
  --format=csv \
  "$(sed -n '67,95p' "$SCRIPT_DIR/AGGRESSIVE_CORRELATION_HUNT.sql")" \
  > "$RESULTS_DIR/strategy3_${TIMESTAMP}.csv" 2>&1

if [ $? -eq 0 ]; then
  echo "✅ Strategy 3 completed"
  STRONG_COUNT=$(grep -c "0\.5\|0\.6\|0\.7\|0\.8\|0\.9\|1\.0" "$RESULTS_DIR/strategy3_${TIMESTAMP}.csv" 2>/dev/null || echo "0")
  echo "   Found correlations: $STRONG_COUNT"
else
  echo "❌ Strategy 3 failed"
fi
echo ""

# Strategy 4: Recent Data
echo "Running Strategy 4: Recent Data (8 weeks)..."
bq query --use_legacy_sql=false \
  --project_id=$PROJECT_ID \
  --format=csv \
  "$(sed -n '97,125p' "$SCRIPT_DIR/AGGRESSIVE_CORRELATION_HUNT.sql")" \
  > "$RESULTS_DIR/strategy4_${TIMESTAMP}.csv" 2>&1

if [ $? -eq 0 ]; then
  echo "✅ Strategy 4 completed"
  STRONG_COUNT=$(grep -c "0\.5\|0\.6\|0\.7\|0\.8\|0\.9\|1\.0" "$RESULTS_DIR/strategy4_${TIMESTAMP}.csv" 2>/dev/null || echo "0")
  echo "   Found correlations: $STRONG_COUNT"
else
  echo "❌ Strategy 4 failed"
fi
echo ""

# Strategy 5: Top Strongest Correlations
echo "Running Strategy 5: Top 100 Strongest Correlations..."
bq query --use_legacy_sql=false \
  --project_id=$PROJECT_ID \
  --format=csv \
  --max_rows=1000 \
  "$(sed -n '127,180p' "$SCRIPT_DIR/AGGRESSIVE_CORRELATION_HUNT.sql")" \
  > "$RESULTS_DIR/strategy5_top_correlations_${TIMESTAMP}.csv" 2>&1

if [ $? -eq 0 ]; then
  echo "✅ Strategy 5 completed"
  echo "   Results saved: $RESULTS_DIR/strategy5_top_correlations_${TIMESTAMP}.csv"
  echo ""
  echo "   Top correlations found:"
  head -20 "$RESULTS_DIR/strategy5_top_correlations_${TIMESTAMP}.csv" | grep -E "0\.[5-9]|1\.0" || echo "   Review CSV file for details"
else
  echo "❌ Strategy 5 failed"
fi
echo ""

echo "=========================================="
echo "Analysis Complete!"
echo "Results saved in: $RESULTS_DIR"
echo ""
echo "Review strategy5_top_correlations_${TIMESTAMP}.csv for strongest correlations"
echo "=========================================="
