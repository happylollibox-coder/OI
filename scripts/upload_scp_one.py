#!/usr/bin/env python3
"""Preprocess SCP CSV for BigQuery: skip metadata row, sanitize headers to match SRC_SCP_WEEKLY."""
import sys
import re
import csv

def sanitize(name):
    name = name.strip('"')
    name = re.sub(r'[:\-()%]', '_', name)
    name = name.replace(' ', '_')
    name = re.sub(r'_+', '_', name).strip('_')
    return name or 'col'

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    input_path, output_path = sys.argv[1], sys.argv[2]
    with open(input_path, 'r', encoding='utf-8-sig') as f:
        lines = f.readlines()
    if len(lines) < 2:
        sys.exit(1)
    # Skip first row (metadata), use second as header
    reader = csv.reader(lines[1:])
    header = next(reader)
    headers = [sanitize(h) for h in header]
    with open(output_path, 'w', newline='', encoding='utf-8') as out:
        w = csv.writer(out)
        w.writerow(headers)
        for row in reader:
            w.writerow(row)
    sys.exit(0)

if __name__ == '__main__':
    main()
