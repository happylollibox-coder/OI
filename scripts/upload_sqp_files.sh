#!/bin/bash
# Upload SQP files - validates all files exist and no duplicates, then uploads

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ID="onyga-482313"
DATASET="OI"
TABLE="SRC_SQP_WEEKLY"

# Always check before entering DB: all files exist and no duplicate paths
if [ $# -eq 0 ]; then
    echo "Usage: $0 <file1.csv> [file2.csv ...]"
    exit 1
fi
if ! python3 "$SCRIPT_DIR/validate_upload_files.py" "$@"; then
    echo "Aborting upload. Fix validation errors above."
    exit 1
fi

# Schema for SQP files
SCHEMA="Search_Query:STRING,Search_Query_Score:INTEGER,Search_Query_Volume:INTEGER,Impressions_Total_Count:INTEGER,Impressions_ASIN_Count:INTEGER,Impressions_ASIN_Share:FLOAT,Clicks_Total_Count:INTEGER,Clicks_Click_Rate:FLOAT,Clicks_ASIN_Count:INTEGER,Clicks_ASIN_Share:FLOAT,Clicks_Price_Median:FLOAT,Clicks_ASIN_Price_Median:FLOAT,Clicks_Same_Day_Shipping_Speed:INTEGER,Clicks_1D_Shipping_Speed:INTEGER,Clicks_2D_Shipping_Speed:INTEGER,Cart_Adds_Total_Count:INTEGER,Cart_Adds_Cart_Add_Rate:FLOAT,Cart_Adds_ASIN_Count:INTEGER,Cart_Adds_ASIN_Share:FLOAT,Cart_Adds_Price_Median:FLOAT,Cart_Adds_ASIN_Price_Median:FLOAT,Cart_Adds_Same_Day_Shipping_Speed:INTEGER,Cart_Adds_1D_Shipping_Speed:INTEGER,Cart_Adds_2D_Shipping_Speed:INTEGER,Purchases_Total_Count:INTEGER,Purchases_Purchase_Rate:FLOAT,Purchases_ASIN_Count:INTEGER,Purchases_ASIN_Share:FLOAT,Purchases_Price_Median:FLOAT,Purchases_ASIN_Price_Median:FLOAT,Purchases_Same_Day_Shipping_Speed:INTEGER,Purchases_1D_Shipping_Speed:INTEGER,Purchases_2D_Shipping_Speed:INTEGER,Reporting_Date:DATE,ASIN:STRING"

# Process and upload files (already validated: all exist, no duplicates)
UPLOADED_COUNT=0
for input_file in "$@"; do
    basename_file=$(basename "$input_file" | sed 's/[ ()]/_/g' | sed 's/__/_/g')
    timestamp=$(date +%s)
    output_file="${TMPDIR:-/tmp}/sqp_${basename_file%.csv}_${timestamp}_clean.csv"

    echo "Processing: $input_file -> (ASIN from file)"
    if python3 "$SCRIPT_DIR/upload_sqp_one.py" "$input_file" "$output_file"; then
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
echo "Uploaded $UPLOADED_COUNT file(s) successfully"
echo "=========================================="
