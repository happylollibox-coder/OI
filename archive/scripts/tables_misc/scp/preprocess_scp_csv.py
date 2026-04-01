#!/usr/bin/env python3
"""
Preprocess SCP CSV files for BigQuery upload
- Skips first row (metadata)
- Sanitizes column names (removes colons, parentheses, spaces)
- Outputs clean CSV ready for BigQuery
"""

import csv
import sys
import re

def sanitize_column_name(name):
    """Sanitize column name for BigQuery compatibility"""
    # Remove quotes
    name = name.strip('"')
    # Replace colons, parentheses, and other special chars with underscores
    name = re.sub(r'[:\-()%]', '_', name)
    # Replace spaces with underscores
    name = name.replace(' ', '_')
    # Remove multiple underscores
    name = re.sub(r'_+', '_', name)
    # Remove leading/trailing underscores
    name = name.strip('_')
    return name

def preprocess_scp_csv(input_file, output_file):
    """Preprocess SCP CSV file"""
    with open(input_file, 'r', encoding='utf-8') as infile, \
         open(output_file, 'w', newline='', encoding='utf-8') as outfile:
        
        reader = csv.reader(infile)
        writer = csv.writer(outfile)
        
        # Skip first row (metadata)
        next(reader, None)
        
        # Read header row
        header_row = next(reader, None)
        if not header_row:
            print(f"Error: No header row found in {input_file}")
            return False
        
        # Sanitize column names
        sanitized_headers = [sanitize_column_name(col) for col in header_row]
        
        # Write sanitized headers
        writer.writerow(sanitized_headers)
        
        # Write all data rows
        row_count = 0
        for row in reader:
            writer.writerow(row)
            row_count += 1
        
        print(f"Processed {row_count} data rows from {input_file}")
        print(f"Output written to {output_file}")
        return True

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python preprocess_scp_csv.py <input_csv> <output_csv>")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
    try:
        success = preprocess_scp_csv(input_file, output_file)
        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"Error processing file: {e}")
        sys.exit(1)
