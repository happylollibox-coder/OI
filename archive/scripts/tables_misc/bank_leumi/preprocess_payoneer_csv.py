#!/usr/bin/env python3
"""
Payoneer CSV Preprocessor
Converts Payoneer CSV date format to BigQuery-compatible format
"""

import csv
import sys
from datetime import datetime

def preprocess_payoneer_csv(input_file, output_file):
    """
    Preprocess Payoneer CSV to convert date format and clean data
    """

    with open(input_file, 'r', encoding='utf-8') as infile, \
         open(output_file, 'w', newline='', encoding='utf-8') as outfile:

        reader = csv.DictReader(infile)
        fieldnames = ['transaction_date', 'description', 'amount', 'currency', 'status', 'running_balance', 'transaction_id']
        writer = csv.DictWriter(outfile, fieldnames=fieldnames)
        writer.writeheader()

        for row in reader:
            # Convert date format from "DD MMM, YYYY" to "YYYY-MM-DD"
            # Handle BOM character in header
            date_key = next((k for k in row.keys() if 'Date' in k), None)
            if not date_key:
                print(f"Warning: Could not find Date column in row: {list(row.keys())}")
                continue

            date_str = row[date_key].strip('"')
            try:
                # Parse date like "30 Dec, 2025" to "2025-12-30"
                parsed_date = datetime.strptime(date_str, '%d %b, %Y')
                transaction_date = parsed_date.strftime('%Y-%m-%d')
            except ValueError:
                print(f"Warning: Could not parse date: {date_str}")
                transaction_date = date_str  # Keep original if parsing fails

            # Clean amount by removing quotes and commas
            amount_str = row['Amount'].strip('"').replace(',', '')
            try:
                amount = float(amount_str)
            except ValueError:
                print(f"Warning: Could not parse amount: {amount_str}")
                amount = 0.0

            # Clean other fields
            description = row['Description'].strip('"')
            currency = row['Currency'].strip('"')
            status = row['Status'].strip('"')

            # Handle Running Balance column
            running_balance_key = next((k for k in row.keys() if 'Running Balance' in k or 'Balance' in k), None)
            running_balance_str = row[running_balance_key].strip('"').replace(',', '') if running_balance_key else ''
            try:
                running_balance = float(running_balance_str) if running_balance_str else None
            except ValueError:
                print(f"Warning: Could not parse running balance: {running_balance_str}")
                running_balance = None

            # Handle Transaction ID column with potential trailing spaces
            transaction_id_key = next((k for k in row.keys() if 'Transaction ID' in k), None)
            transaction_id = row[transaction_id_key].strip() if transaction_id_key else ''

            # Write cleaned row
            writer.writerow({
                'transaction_date': transaction_date,
                'description': description,
                'amount': amount,
                'currency': currency,
                'status': status,
                'running_balance': running_balance if running_balance is not None else '',
                'transaction_id': transaction_id
            })

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python preprocess_payoneer_csv.py <input_csv> <output_csv>")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]

    try:
        preprocess_payoneer_csv(input_file, output_file)
        print(f"Successfully preprocessed {input_file} to {output_file}")
    except Exception as e:
        print(f"Error processing file: {e}")
        sys.exit(1)
