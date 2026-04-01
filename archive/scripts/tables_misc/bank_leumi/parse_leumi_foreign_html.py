#!/usr/bin/env python3
"""
Bank Leumi Foreign Currency HTML to CSV Parser
Converts Bank Leumi's foreign currency HTML transaction export to CSV format for BigQuery import
Uses regex-based parsing for reliability.
"""

import re
import csv
import sys

def parse_leumi_foreign_html_to_csv(html_file_path, output_csv_path):
    """
    Parse Bank Leumi Foreign Currency HTML export and convert to CSV

    Args:
        html_file_path: Path to the HTML file
        output_csv_path: Path for the output CSV file
    """

    # Read the HTML file
    with open(html_file_path, 'r', encoding='utf-8') as f:
        html_content = f.read()

    # Find all transaction rows - they have the pattern: <tr style='font-size: 13pt;  border-bottom-width: thin;  '>
    # Followed by <td> elements containing the data
    transaction_pattern = r"<tr style='font-size: 13pt;\s+border-bottom-width: thin;[^>]*>(.*?)</tr>"
    # Updated cell pattern to handle content on new lines after opening tag
    cell_pattern = r'<td[^>]*>\s*([^<]*?)\s*</td>'

    transactions = []

    # Find all transaction rows
    row_matches = re.findall(transaction_pattern, html_content, re.DOTALL | re.IGNORECASE)

    print(f"Found {len(row_matches)} potential transaction rows")

    for row_html in row_matches:
        # Extract all td elements from this row
        cells = re.findall(cell_pattern, row_html, re.IGNORECASE)

        if len(cells) >= 9:  # Foreign currency has at least 9 columns (some may have empty notes)
            try:
                transaction = {
                    'branch': cells[0].strip(),
                    'account': cells[1].strip(),
                    'currency': cells[2].strip(),
                    'transaction_date': convert_date_format(cells[3].strip()),
                    'transaction_description': cells[4].strip(),
                    'reference_number': cells[5].strip(),
                    'debit_amount': clean_numeric(cells[6].strip()),
                    'credit_amount': clean_numeric(cells[7].strip()),
                    'balance_foreign': clean_numeric(cells[8].strip()),
                    'extended_description': cells[9].strip() if len(cells) > 9 else '',
                    'notes': cells[10].strip() if len(cells) > 10 else ''
                }
                # Only add if we have a valid date
                if transaction['transaction_date']:
                    transactions.append(transaction)
            except Exception as e:
                print(f"Warning: Skipping row due to parsing error: {e}")
                print(f"Row cells: {cells[:5]}")
                continue

    # Write to CSV
    fieldnames = ['branch', 'account', 'currency', 'transaction_date', 'transaction_description',
                  'reference_number', 'debit_amount', 'credit_amount', 'balance_foreign',
                  'extended_description', 'notes']

    with open(output_csv_path, 'w', newline='', encoding='utf-8') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(transactions)

    print(f"Parsed {len(transactions)} transactions and saved to {output_csv_path}")
    return transactions

def convert_date_format(date_str):
    """Convert DD/MM/YYYY to YYYY-MM-DD format"""
    if not date_str or date_str.strip() == '':
        return ''

    try:
        day, month, year = date_str.split('/')
        return f"{year}-{month.zfill(2)}-{day.zfill(2)}"
    except:
        return date_str  # Return original if parsing fails

def clean_numeric(value):
    """Clean numeric values by removing commas and handling empty strings"""
    if not value or value.strip() == '':
        return ''
    return value.replace(',', '').strip()

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python parse_leumi_foreign_html.py <input_html_file> <output_csv_file>")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]

    try:
        transactions = parse_leumi_foreign_html_to_csv(input_file, output_file)
        print(f"Successfully processed {len(transactions)} transactions")
    except Exception as e:
        print(f"Error processing file: {e}")
        sys.exit(1)
