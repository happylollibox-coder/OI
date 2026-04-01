#!/usr/bin/env python3
"""
Preprocess SQP CSV files for BigQuery upload
- Extracts ASIN from metadata row (row 1)
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

def extract_asin_from_metadata(metadata_line):
    """Extract ASIN from metadata row like: ASIN or Product=["B0CR6N3WRC"],..."""
    # Pattern: ASIN or Product=["ASIN_VALUE"]
    match = re.search(r'ASIN or Product=\["([^"]+)"\]', metadata_line)
    if match:
        return match.group(1)
    # Fallback: try to find any pattern with brackets
    match = re.search(r'\["([A-Z0-9]{10})"\]', metadata_line)
    if match:
        return match.group(1)
    return None

def preprocess_sqp_csv(input_file, output_file):
    """Preprocess SQP CSV file"""
    with open(input_file, 'r', encoding='utf-8') as infile, \
         open(output_file, 'w', newline='', encoding='utf-8') as outfile:
        
        reader = csv.reader(infile)
        writer = csv.writer(outfile)
        
        # Read and extract ASIN from first row (metadata)
        metadata_row = next(reader, None)
        if not metadata_row:
            print(f"Error: No metadata row found in {input_file}")
            return False
        
        asin = extract_asin_from_metadata(metadata_row[0] if metadata_row else '')
        if not asin:
            print(f"Warning: Could not extract ASIN from metadata in {input_file}")
            print(f"Metadata row: {metadata_row[0] if metadata_row else 'N/A'}")
            # Try to extract from filename
            import os
            filename = os.path.basename(input_file)
            # Look for ASIN pattern in filename
            asin_match = re.search(r'([A-Z0-9]{10})', filename)
            if asin_match:
                asin = asin_match.group(1)
                print(f"Extracted ASIN from filename: {asin}")
            else:
                print(f"Error: Could not extract ASIN from filename either")
                return False
        
        # Read header row
        header_row = next(reader, None)
        if not header_row:
            print(f"Error: No header row found in {input_file}")
            return False
        
        # Sanitize column names
        sanitized_headers = [sanitize_column_name(col) for col in header_row]
        
        # Add ASIN column to headers
        sanitized_headers.append('ASIN')
        
        # Write sanitized headers
        writer.writerow(sanitized_headers)
        
        # Write all data rows with ASIN appended
        row_count = 0
        for row in reader:
            # Append ASIN to each row
            row.append(asin)
            writer.writerow(row)
            row_count += 1
        
        print(f"Processed {row_count} data rows from {input_file} (ASIN: {asin})")
        print(f"Output written to {output_file}")
        return True

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python preprocess_sqp_csv.py <input_csv> <output_csv>")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
    try:
        success = preprocess_sqp_csv(input_file, output_file)
        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"Error processing file: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
