#!/bin/bash
# Upload SCP files - validates all files exist and no duplicates, then uploads to SRC_SCP_WEEKLY

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ID="onyga-482313"
DATASET="OI"
TABLE="SRC_SCP_WEEKLY"

# Always check before entering DB: all files exist and no duplicate paths
if [ $# -eq 0 ]; then
    echo "Usage: $0 <file1.csv> [file2.csv ...]"
    exit 1
fi
if ! python3 "$SCRIPT_DIR/validate_upload_files.py" "$@"; then
    echo "Aborting upload. Fix validation errors above."
    exit 1
fi

# Schema for SCP (must match SRC_SCP_WEEKLY table and preprocessed CSV headers; Amazon exports use Purchases_Conversion_Rate)
SCHEMA="ASIN_Title:STRING,ASIN:STRING,Category:STRING,Impressions_Impressions:INTEGER,Impressions_Rating_Median:FLOAT,Impressions_Price_Median:FLOAT,Impressions_Same_Day_Shipping_Speed:INTEGER,Impressions_1D_Shipping_Speed:INTEGER,Impressions_2D_Shipping_Speed:INTEGER,Clicks_Clicks:INTEGER,Clicks_Click_Rate_CTR:FLOAT,Clicks_Price_Median:FLOAT,Clicks_Same_Day_Shipping_Speed:INTEGER,Clicks_1D_Shipping_Speed:INTEGER,Clicks_2D_Shipping_Speed:INTEGER,Cart_Adds_Cart_Adds:INTEGER,Cart_Adds_Price_Median:FLOAT,Cart_Adds_Same_Day_Shipping_Speed:INTEGER,Cart_Adds_1D_Shipping_Speed:INTEGER,Cart_Adds_2D_Shipping_Speed:INTEGER,Purchases_Purchases:INTEGER,Purchases_Search_Traffic_Sales:FLOAT,Purchases_Conversion_Rate:FLOAT,Purchases_Rating_Median:FLOAT,Purchases_Price_Median:FLOAT,Purchases_Same_Day_Shipping_Speed:INTEGER,Purchases_1D_Shipping_Speed:INTEGER,Purchases_2D_Shipping_Speed:INTEGER,Reporting_Date:DATE"

UPLOADED_COUNT=0
for input_file in "$@"; do
    basename_file=$(basename "$input_file" | sed 's/[ ()]/_/g' | sed 's/__/_/g')
    timestamp=$(date +%s)
    output_file="${TMPDIR:-/tmp}/scp_${basename_file%.csv}_${timestamp}_clean.csv"

    echo "Processing: $input_file"
    if python3 "$SCRIPT_DIR/upload_scp_one.py" "$input_file" "$output_file"; then
        if [ -f "$output_file" ] && [ -s "$output_file" ]; then
            echo "Uploading: $output_file"
            if command -v bq >/dev/null 2>&1; then
                bq_out=$(bq load --source_format=CSV --skip_leading_rows=1 --project_id=$PROJECT_ID --replace=false ${PROJECT_ID}:${DATASET}.${TABLE} "$output_file" "$SCHEMA" 2>&1)
                load_rc=$?
            else
                bq_out=$(python3 "$SCRIPT_DIR/bq_load_csv.py" "$PROJECT_ID" "${DATASET}.${TABLE}" "$output_file" "$SCHEMA" 2>&1)
                load_rc=$?
            fi
            if [ $load_rc -eq 0 ]; then
                echo "✓ Successfully uploaded: $input_file"
                UPLOADED_COUNT=$((UPLOADED_COUNT + 1))
            else
                echo "✗ Failed to upload: $input_file"
                echo "$bq_out"
            fi
            rm -f "$output_file"
        else
            echo "✗ Preprocess produced no output: $input_file"
        fi
    else
        echo "✗ Failed to preprocess: $input_file"
    fi
done

echo "=========================================="
echo "Uploaded $UPLOADED_COUNT SCP file(s) successfully"
echo "=========================================="
