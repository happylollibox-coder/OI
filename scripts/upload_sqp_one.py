#!/usr/bin/env python3
"""Strip BOM, extract ASIN from metadata, sanitize headers, add ASIN column. Output CSV ready for bq load to SRC_SQP_WEEKLY."""
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
    if not lines:
        sys.exit(1)
    first = lines[0].strip()
    match = re.search(r'ASIN or Product=\["([^"]+)"\]', first)
    if not match:
        match = re.search(r'\["([A-Z0-9]{10})"\]', first)
    asin = match.group(1) if match else None
    if not asin:
        sys.exit(1)
    if len(lines) < 2:
        sys.exit(1)
    reader = csv.reader(lines[1:])
    header = next(reader)
    headers = [sanitize(h) for h in header] + ['ASIN']
    with open(output_path, 'w', newline='', encoding='utf-8') as out:
        w = csv.writer(out)
        w.writerow(headers)
        for row in reader:
            w.writerow(row + [asin])
    sys.exit(0)

if __name__ == '__main__':
    main()
