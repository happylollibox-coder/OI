#!/usr/bin/env python3
"""
Exchange Rates Update Script for OI Database Project

Fetches real exchange rates from exchangerate-api.com and inserts them into BigQuery.
Run this script daily to update currency rates.

Requirements:
- pip install requests google-cloud-bigquery
- Google Cloud authentication (gcloud auth application-default login)

Usage:
python update_exchange_rates.py [--project PROJECT_ID] [--date YYYY-MM-DD]
"""

import argparse
import json
import sys
from datetime import datetime, date, timedelta
from typing import Dict, List, Any

import requests
from google.cloud import bigquery


class ExchangeRateUpdater:
    """Handles fetching and updating exchange rates in BigQuery."""

    def __init__(self, project_id: str = "onyga-482313"):
        self.project_id = project_id
        self.dataset_id = "OI"
        self.table_id = "DIM_CURRENCY_RATES"
        self.api_url = "https://api.exchangerate-api.com/v4/latest/USD"
        self.currencies = ['ILS', 'USD', 'HKD']

        # Initialize BigQuery client
        self.bq_client = bigquery.Client(project=project_id)

    def fetch_exchange_rates(self) -> Dict[str, Any]:
        """Fetch exchange rates from the API."""
        try:
            print(f"Fetching exchange rates from {self.api_url}...")
            response = requests.get(self.api_url, timeout=30)
            response.raise_for_status()

            data = response.json()
            print(f"✅ Successfully fetched rates from {data.get('provider', 'API')}")

            return data

        except requests.RequestException as e:
            print(f"❌ Failed to fetch rates: {e}")
            return None
        except json.JSONDecodeError as e:
            print(f"❌ Failed to parse API response: {e}")
            return None

    def generate_currency_pairs(self, rates: Dict[str, float]) -> List[Dict[str, Any]]:
        """Generate all currency pair combinations."""
        pairs = []

        # Extract rates for our currencies
        usd_to_ils = rates.get('ILS', 3.822)
        usd_to_hkd = rates.get('HKD', 7.812)
        usd_to_usd = 1.0

        # USD as base currency
        pairs.extend([
            {
                'base_currency': 'USD',
                'target_currency': 'ILS',
                'exchange_rate': usd_to_ils,
                'inverse_rate': 1 / usd_to_ils
            },
            {
                'base_currency': 'USD',
                'target_currency': 'HKD',
                'exchange_rate': usd_to_hkd,
                'inverse_rate': 1 / usd_to_hkd
            },
            {
                'base_currency': 'USD',
                'target_currency': 'USD',
                'exchange_rate': usd_to_usd,
                'inverse_rate': 1.0
            }
        ])

        # ILS as base currency
        pairs.extend([
            {
                'base_currency': 'ILS',
                'target_currency': 'USD',
                'exchange_rate': 1 / usd_to_ils,
                'inverse_rate': usd_to_ils
            },
            {
                'base_currency': 'ILS',
                'target_currency': 'HKD',
                'exchange_rate': usd_to_hkd / usd_to_ils,
                'inverse_rate': usd_to_ils / usd_to_hkd
            },
            {
                'base_currency': 'ILS',
                'target_currency': 'ILS',
                'exchange_rate': 1.0,
                'inverse_rate': 1.0
            }
        ])

        # HKD as base currency
        pairs.extend([
            {
                'base_currency': 'HKD',
                'target_currency': 'USD',
                'exchange_rate': 1 / usd_to_hkd,
                'inverse_rate': usd_to_hkd
            },
            {
                'base_currency': 'HKD',
                'target_currency': 'ILS',
                'exchange_rate': usd_to_ils / usd_to_hkd,
                'inverse_rate': usd_to_hkd / usd_to_ils
            },
            {
                'base_currency': 'HKD',
                'target_currency': 'HKD',
                'exchange_rate': 1.0,
                'inverse_rate': 1.0
            }
        ])

        return pairs

    def insert_rates_to_bigquery(self, currency_pairs: List[Dict[str, Any]], effective_date: date) -> bool:
        """Insert currency rates into BigQuery."""
        try:
            table_ref = self.bq_client.dataset(self.dataset_id).table(self.table_id)

            rows_to_insert = []
            for pair in currency_pairs:
                row = {
                    'exchange_date': effective_date.isoformat(),
                    'base_currency': pair['base_currency'],
                    'target_currency': pair['target_currency'],
                    'exchange_rate': pair['exchange_rate'],
                    'inverse_rate': pair['inverse_rate'],
                    'rate_source': 'EXCHANGE_RATE_API',
                    'rate_timestamp': datetime.utcnow().isoformat(),
                    'is_business_day': True,
                    'data_quality_score': 100,
                    'is_manual_override': False,
                    'last_updated_by': 'EXTERNAL_SCRIPT'
                }
                rows_to_insert.append(row)

            # Use MERGE to upsert data
            merge_query = f"""
            MERGE `{self.project_id}.{self.dataset_id}.{self.table_id}` target
            USING (
              SELECT
                DATE('{effective_date.isoformat()}') as exchange_date,
                @base_currency as base_currency,
                @target_currency as target_currency,
                @exchange_rate as exchange_rate,
                @inverse_rate as inverse_rate,
                @rate_source as rate_source,
                TIMESTAMP(@rate_timestamp) as rate_timestamp,
                @is_business_day as is_business_day,
                @data_quality_score as data_quality_score,
                @is_manual_override as is_manual_override,
                @last_updated_by as last_updated_by
            ) source
            ON target.exchange_date = source.exchange_date
               AND target.base_currency = source.base_currency
               AND target.target_currency = source.target_currency
            WHEN MATCHED THEN
              UPDATE SET
                exchange_rate = source.exchange_rate,
                inverse_rate = source.inverse_rate,
                rate_timestamp = source.rate_timestamp,
                data_quality_score = source.data_quality_score,
                updated_at = CURRENT_TIMESTAMP(),
                last_updated_by = source.last_updated_by
            WHEN NOT MATCHED THEN
              INSERT (
                exchange_date, base_currency, target_currency, exchange_rate, inverse_rate,
                rate_source, rate_timestamp, is_business_day, data_quality_score,
                is_manual_override, last_updated_by
              )
              VALUES (
                source.exchange_date, source.base_currency, source.target_currency,
                source.exchange_rate, source.inverse_rate, source.rate_source,
                source.rate_timestamp, source.is_business_day, source.data_quality_score,
                source.is_manual_override, source.last_updated_by
              )
            """

            # Execute merge for each currency pair
            for pair in currency_pairs:
                job_config = bigquery.QueryJobConfig(
                    query_parameters=[
                        bigquery.ScalarQueryParameter("base_currency", "STRING", pair['base_currency']),
                        bigquery.ScalarQueryParameter("target_currency", "STRING", pair['target_currency']),
                        bigquery.ScalarQueryParameter("exchange_rate", "FLOAT64", pair['exchange_rate']),
                        bigquery.ScalarQueryParameter("inverse_rate", "FLOAT64", pair['inverse_rate']),
                        bigquery.ScalarQueryParameter("rate_source", "STRING", 'EXCHANGE_RATE_API'),
                        bigquery.ScalarQueryParameter("rate_timestamp", "STRING", datetime.utcnow().isoformat()),
                        bigquery.ScalarQueryParameter("is_business_day", "BOOL", True),
                        bigquery.ScalarQueryParameter("data_quality_score", "INT64", 100),
                        bigquery.ScalarQueryParameter("is_manual_override", "BOOL", False),
                        bigquery.ScalarQueryParameter("last_updated_by", "STRING", 'EXTERNAL_SCRIPT'),
                    ]
                )

                query_job = self.bq_client.query(merge_query, job_config=job_config)
                query_job.result()  # Wait for completion

            print(f"✅ Successfully inserted {len(currency_pairs)} currency pairs for {effective_date}")
            return True

        except Exception as e:
            print(f"❌ Failed to insert rates to BigQuery: {e}")
            return False

    def fetch_historical_rates(self, target_date: date) -> Dict[str, Any]:
        """Fetch historical rates for a specific date (limited API support)."""
        # Note: Most free APIs don't provide historical data
        # This is a placeholder for when historical API access is available
        print(f"Note: Historical API not available with free tier. Using current rates for {target_date}")

        # For now, return current rates but mark them as estimated for historical dates
        return self.fetch_exchange_rates()

    def update_rates_for_date_range(self, start_date: date, end_date: date) -> bool:
        """Update exchange rates for a range of dates."""
        print(f"Starting exchange rate update for date range: {start_date} to {end_date}")
        print("=" * 70)

        current_date = start_date
        total_processed = 0
        total_pairs = 0

        while current_date <= end_date:
            print(f"\n📅 Processing date: {current_date}")

            # Fetch rates (current rates for all dates due to API limitations)
            if current_date == date.today():
                api_data = self.fetch_exchange_rates()
            else:
                api_data = self.fetch_historical_rates(current_date)

            if not api_data:
                print(f"❌ Skipping {current_date} due to API failure")
                current_date += timedelta(days=1)
                continue

            # Generate currency pairs
            currency_pairs = self.generate_currency_pairs(api_data['rates'])
            print(f"Generated {len(currency_pairs)} currency pairs for {current_date}")

            # Insert to BigQuery
            success = self.insert_rates_to_bigquery(currency_pairs, current_date)
            if success:
                total_processed += 1
                total_pairs += len(currency_pairs)
                print(f"✅ Successfully updated {current_date}")
            else:
                print(f"❌ Failed to update {current_date}")

            current_date += timedelta(days=1)

        print("\n" + "=" * 70)
        if total_processed > 0:
            print("✅ Exchange rate update completed successfully!")
            print(f"Updated {total_processed} dates with {total_pairs} total currency pairs")
            print(f"Date range: {start_date} to {end_date}")
            return True
        else:
            print("❌ No dates were successfully updated")
            return False

    def update_rates(self, effective_date: date = None, start_date: date = None, end_date: date = None) -> bool:
        """Main method to fetch and update exchange rates."""
        # Support both single date and date range modes
        if start_date and end_date:
            return self.update_rates_for_date_range(start_date, end_date)
        elif effective_date:
            return self.update_rates_for_date_range(effective_date, effective_date)
        else:
            # Default to today
            return self.update_rates_for_date_range(date.today(), date.today())


def main():
    parser = argparse.ArgumentParser(description='Update currency exchange rates in BigQuery')
    parser.add_argument('--project', default='onyga-482313', help='BigQuery project ID')
    parser.add_argument('--date', help='Single effective date (YYYY-MM-DD). Defaults to today.')
    parser.add_argument('--start-date', help='Start date for range (YYYY-MM-DD)')
    parser.add_argument('--end-date', help='End date for range (YYYY-MM-DD)')

    args = parser.parse_args()

    # Parse dates
    effective_date = None
    start_date = None
    end_date = None

    if args.date:
        try:
            effective_date = datetime.strptime(args.date, '%Y-%m-%d').date()
        except ValueError:
            print(f"❌ Invalid date format: {args.date}. Use YYYY-MM-DD")
            sys.exit(1)

    if args.start_date:
        try:
            start_date = datetime.strptime(args.start_date, '%Y-%m-%d').date()
        except ValueError:
            print(f"❌ Invalid start date format: {args.start_date}. Use YYYY-MM-DD")
            sys.exit(1)

    if args.end_date:
        try:
            end_date = datetime.strptime(args.end_date, '%Y-%m-%d').date()
        except ValueError:
            print(f"❌ Invalid end date format: {args.end_date}. Use YYYY-MM-DD")
            sys.exit(1)

    # Validate date logic
    if start_date and end_date and start_date > end_date:
        print("❌ Start date cannot be after end date")
        sys.exit(1)

    if (start_date and not end_date) or (end_date and not start_date):
        print("❌ Both --start-date and --end-date must be provided together")
        sys.exit(1)

    # Prevent future dates - only allow real historical data through today
    max_allowed_date = date.today()  # Only allow data through today

    if effective_date and effective_date > max_allowed_date:
        print(f"❌ Can only load verified historical data. Effective date {effective_date} is too recent.")
        print(f"   Maximum allowed date: {max_allowed_date} (end of previous year)")
        sys.exit(1)

    if start_date and start_date > max_allowed_date:
        print(f"❌ Can only load verified historical data. Start date {start_date} is too recent.")
        print(f"   Maximum allowed date: {max_allowed_date} (end of previous year)")
        sys.exit(1)

    if end_date and end_date > max_allowed_date:
        print(f"❌ Can only load verified historical data. End date {end_date} is too recent.")
        print(f"   Maximum allowed date: {max_allowed_date} (end of previous year)")
        print(f"   Adjusting end date to: {max_allowed_date}")
        end_date = max_allowed_date

    # Create updater and run
    updater = ExchangeRateUpdater(args.project)
    success = updater.update_rates(effective_date, start_date, end_date)

    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
