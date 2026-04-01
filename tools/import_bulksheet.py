#!/usr/bin/env python3
"""
Import Amazon Ads Bulksheet v2.0 into BigQuery FACT_CAMPAIGN_CONFIG table.
Usage: python3 import_bulksheet.py <path_to_bulksheet.xlsx> [--snapshot-date YYYY-MM-DD]

If --snapshot-date is not provided, uses today's date.
"""
import argparse
import sys
import os
from datetime import date

import pandas as pd
from google.cloud import bigquery

PROJECT = "onyga-482313"
DATASET = "OI"
TABLE = "FACT_CAMPAIGN_CONFIG"
TABLE_REF = f"{PROJECT}.{DATASET}.{TABLE}"


def parse_args():
    parser = argparse.ArgumentParser(description="Import Amazon Ads Bulksheet to BigQuery")
    parser.add_argument("input_file", help="Path to bulksheet .xlsx file")
    parser.add_argument("--snapshot-date", default=None, help="Snapshot date (YYYY-MM-DD). Default: today")
    parser.add_argument("--dry-run", action="store_true", help="Parse and show stats but don't upload")
    return parser.parse_args()


def read_bulksheet(input_file: str) -> pd.DataFrame:
    """Read Sponsored Products sheet from bulksheet."""
    print(f"Reading {os.path.basename(input_file)}...")
    df = pd.read_excel(input_file, sheet_name='Sponsored Products Campaigns', dtype=str)
    df['Entity'] = df['Entity'].fillna('').str.strip()
    print(f"  SP Total rows: {len(df)}")
    print(f"  SP Entity breakdown: {df['Entity'].value_counts().to_dict()}")
    return df


def read_sb_sheet(input_file: str) -> pd.DataFrame | None:
    """Read SB Multi Ad Group Campaigns sheet from bulksheet (if present)."""
    try:
        df = pd.read_excel(input_file, sheet_name='SB Multi Ad Group Campaigns', dtype=str)
        df['Entity'] = df['Entity'].fillna('').str.strip()
        print(f"  SB Total rows: {len(df)}")
        print(f"  SB Entity breakdown: {df['Entity'].value_counts().to_dict()}")
        return df
    except ValueError:
        print("  SB sheet 'SB Multi Ad Group Campaigns' not found — skipping.")
        return None


def build_campaign_rows(df: pd.DataFrame, snap_date: str, source_file: str) -> list[dict]:
    """Extract Campaign entity rows."""
    camps = df[df['Entity'] == 'Campaign'].copy()
    rows = []
    for _, r in camps.iterrows():
        rows.append({
            'snapshot_date': snap_date,
            'source_file': source_file,
            'entity_type': 'CAMPAIGN',
            'campaign_id': r.get('Campaign ID', ''),
            'campaign_name': r.get('Campaign Name', ''),
            'campaign_state': r.get('State', ''),
            'daily_budget': safe_float(r.get('Daily Budget')),
            'bidding_strategy': r.get('Bidding Strategy', ''),
            'targeting_type': r.get('Targeting Type', ''),
            'start_date': r.get('Start Date', ''),
        })
    return rows


def build_ad_group_rows(df: pd.DataFrame, snap_date: str, source_file: str) -> list[dict]:
    """Extract Ad Group entity rows."""
    ags = df[df['Entity'] == 'Ad Group'].copy()
    rows = []
    for _, r in ags.iterrows():
        rows.append({
            'snapshot_date': snap_date,
            'source_file': source_file,
            'entity_type': 'AD_GROUP',
            'campaign_id': r.get('Campaign ID', ''),
            'ad_group_id': r.get('Ad Group ID', ''),
            'ad_group_name': r.get('Ad Group Name', ''),
            'ad_group_state': r.get('State', ''),
            'ad_group_default_bid': safe_float(r.get('Ad Group Default Bid')),
        })
    return rows


def build_keyword_rows(df: pd.DataFrame, snap_date: str, source_file: str) -> list[dict]:
    """Extract Keyword entity rows."""
    kws = df[df['Entity'] == 'Keyword'].copy()
    rows = []
    for _, r in kws.iterrows():
        rows.append({
            'snapshot_date': snap_date,
            'source_file': source_file,
            'entity_type': 'KEYWORD',
            'campaign_id': r.get('Campaign ID', ''),
            'ad_group_id': r.get('Ad Group ID', ''),
            'keyword_id': r.get('Keyword ID', ''),
            'keyword_text': r.get('Keyword Text', ''),
            'match_type': r.get('Match Type', ''),
            'bid': safe_float(r.get('Bid')),
            'keyword_state': r.get('State', ''),
        })
    return rows


def build_negative_keyword_rows(df: pd.DataFrame, snap_date: str, source_file: str) -> list[dict]:
    """Extract Negative Keyword entity rows."""
    negs = df[df['Entity'] == 'Negative Keyword'].copy()
    rows = []
    for _, r in negs.iterrows():
        rows.append({
            'snapshot_date': snap_date,
            'source_file': source_file,
            'entity_type': 'NEGATIVE_KEYWORD',
            'campaign_id': r.get('Campaign ID', ''),
            'ad_group_id': r.get('Ad Group ID', ''),
            'keyword_text': r.get('Keyword Text', ''),
            'match_type': r.get('Match Type', ''),
            'keyword_state': r.get('State', ''),
        })
    return rows


def build_product_targeting_rows(df: pd.DataFrame, snap_date: str, source_file: str) -> list[dict]:
    """Extract Product Targeting entity rows."""
    pts = df[df['Entity'] == 'Product Targeting'].copy()
    rows = []
    for _, r in pts.iterrows():
        pt_id_col = 'Product Targeting ID' if 'Product Targeting ID' in df.columns else None
        pt_expr_col = 'Product Targeting Expression' if 'Product Targeting Expression' in df.columns else None
        rows.append({
            'snapshot_date': snap_date,
            'source_file': source_file,
            'entity_type': 'PRODUCT_TARGETING',
            'campaign_id': r.get('Campaign ID', ''),
            'ad_group_id': r.get('Ad Group ID', ''),
            'product_targeting_id': r.get('Product Targeting ID', '') if pt_id_col else '',
            'product_targeting_expression': r.get('Product Targeting Expression', '') if pt_expr_col else '',
            'pt_bid': safe_float(r.get('Bid')),
            'pt_state': r.get('State', ''),
        })
    return rows


def build_product_ad_rows(df: pd.DataFrame, snap_date: str, source_file: str) -> list[dict]:
    """Extract Product Ad entity rows."""
    ads = df[df['Entity'] == 'Product Ad'].copy()
    rows = []
    for _, r in ads.iterrows():
        rows.append({
            'snapshot_date': snap_date,
            'source_file': source_file,
            'entity_type': 'PRODUCT_AD',
            'campaign_id': r.get('Campaign ID', ''),
            'ad_group_id': r.get('Ad Group ID', ''),
            'ad_id': r.get('Ad ID', '') if 'Ad ID' in df.columns else '',
            'sku': r.get('SKU', '') if 'SKU' in df.columns else '',
            'asin': r.get('ASIN', '') if 'ASIN' in df.columns else '',
            'ad_state': r.get('State', ''),
        })
    return rows


def safe_float(val) -> float | None:
    """Safely convert a value to float, returning None if not possible."""
    if val is None or (isinstance(val, str) and val.strip() in ('', 'nan', 'NaN')):
        return None
    try:
        return float(val)
    except (ValueError, TypeError):
        return None


def build_bidding_adjustment_rows(df: pd.DataFrame, snap_date: str, source_file: str) -> list[dict]:
    """Extract Bidding Adjustment entity rows (placement bid multipliers)."""
    bas = df[df['Entity'] == 'Bidding Adjustment'].copy()
    rows = []
    for _, r in bas.iterrows():
        rows.append({
            'snapshot_date': snap_date,
            'source_file': source_file,
            'entity_type': 'BIDDING_ADJUSTMENT',
            'campaign_id': r.get('Campaign ID', ''),
            'bidding_strategy': r.get('Bidding Strategy', ''),
            'placement': r.get('Placement', ''),
            'placement_percentage': safe_float(r.get('Percentage')),
        })
    return rows


def build_negative_product_targeting_rows(df: pd.DataFrame, snap_date: str, source_file: str) -> list[dict]:
    """Extract Negative Product Targeting entity rows (blocked ASINs)."""
    npts = df[df['Entity'] == 'Negative Product Targeting'].copy()
    rows = []
    for _, r in npts.iterrows():
        rows.append({
            'snapshot_date': snap_date,
            'source_file': source_file,
            'entity_type': 'NEGATIVE_PRODUCT_TARGETING',
            'campaign_id': r.get('Campaign ID', ''),
            'ad_group_id': r.get('Ad Group ID', ''),
            'product_targeting_id': r.get('Product Targeting ID', ''),
            'product_targeting_expression': r.get('Product Targeting Expression', ''),
            'pt_state': r.get('State', ''),
        })
    return rows


def build_campaign_negative_keyword_rows(df: pd.DataFrame, snap_date: str, source_file: str) -> list[dict]:
    """Extract Campaign Negative Keyword entity rows (campaign-level negatives)."""
    cnks = df[df['Entity'] == 'Campaign Negative Keyword'].copy()
    rows = []
    for _, r in cnks.iterrows():
        rows.append({
            'snapshot_date': snap_date,
            'source_file': source_file,
            'entity_type': 'CAMPAIGN_NEGATIVE_KEYWORD',
            'campaign_id': r.get('Campaign ID', ''),
            'keyword_id': r.get('Keyword ID', ''),
            'keyword_text': r.get('Keyword Text', ''),
            'match_type': r.get('Match Type', ''),
            'keyword_state': r.get('State', ''),
        })
    return rows


# ═══ SB (Sponsored Brands) entity builders ═══

def build_sb_campaign_rows(df: pd.DataFrame, snap_date: str, source_file: str) -> list[dict]:
    """Extract SB Campaign entity rows."""
    camps = df[df['Entity'] == 'Campaign'].copy()
    rows = []
    for _, r in camps.iterrows():
        rows.append({
            'snapshot_date': snap_date,
            'source_file': source_file,
            'entity_type': 'SB_CAMPAIGN',
            'campaign_id': r.get('Campaign ID', ''),
            'campaign_name': r.get('Campaign Name', ''),
            'campaign_state': r.get('State', ''),
            'daily_budget': safe_float(r.get('Budget')),
            'bidding_strategy': r.get('Bid Optimization', ''),
        })
    return rows


def build_sb_ad_group_rows(df: pd.DataFrame, snap_date: str, source_file: str) -> list[dict]:
    """Extract SB Ad Group entity rows."""
    ags = df[df['Entity'] == 'Ad Group'].copy()
    rows = []
    for _, r in ags.iterrows():
        rows.append({
            'snapshot_date': snap_date,
            'source_file': source_file,
            'entity_type': 'SB_AD_GROUP',
            'campaign_id': r.get('Campaign ID', ''),
            'ad_group_id': r.get('Ad Group ID', ''),
            'ad_group_name': r.get('Ad Group Name', ''),
            'ad_group_state': r.get('State', ''),
        })
    return rows


def build_sb_keyword_rows(df: pd.DataFrame, snap_date: str, source_file: str) -> list[dict]:
    """Extract SB Keyword entity rows (these have the bid we need)."""
    kws = df[df['Entity'] == 'Keyword'].copy()
    rows = []
    for _, r in kws.iterrows():
        rows.append({
            'snapshot_date': snap_date,
            'source_file': source_file,
            'entity_type': 'SB_KEYWORD',
            'campaign_id': r.get('Campaign ID', ''),
            'ad_group_id': r.get('Ad Group ID', ''),
            'keyword_id': r.get('Keyword ID', ''),
            'keyword_text': r.get('Keyword Text', ''),
            'match_type': r.get('Match Type', ''),
            'bid': safe_float(r.get('Bid')),
            'keyword_state': r.get('State', ''),
        })
    return rows


def build_sb_negative_keyword_rows(df: pd.DataFrame, snap_date: str, source_file: str) -> list[dict]:
    """Extract SB Negative Keyword entity rows."""
    negs = df[df['Entity'] == 'Negative Keyword'].copy()
    rows = []
    for _, r in negs.iterrows():
        rows.append({
            'snapshot_date': snap_date,
            'source_file': source_file,
            'entity_type': 'SB_NEGATIVE_KEYWORD',
            'campaign_id': r.get('Campaign ID', ''),
            'ad_group_id': r.get('Ad Group ID', ''),
            'keyword_text': r.get('Keyword Text', ''),
            'match_type': r.get('Match Type', ''),
            'keyword_state': r.get('State', ''),
        })
    return rows


def sanitize_value(val):
    """Remove control characters, null bytes, and NaN from values."""
    import math
    if val is None:
        return None
    if isinstance(val, float) and (math.isnan(val) or math.isinf(val)):
        return None
    if isinstance(val, str):
        if val.strip() in ('nan', 'NaN', 'None', ''):
            return None
        # Remove null bytes and control characters (except newlines)
        return ''.join(c for c in val if c == '\n' or c == '\r' or (ord(c) >= 32 and ord(c) != 127))
    return val


def sanitize_row(row: dict) -> dict:
    """Clean all values in a row, removing NaN/None/empty."""
    return {k: sanitize_value(v) for k, v in row.items()}


def upload_to_bigquery(rows: list[dict], snap_date: str):
    """Upload all rows to BigQuery, replacing any existing data for this snapshot_date."""
    import json
    import tempfile

    client = bigquery.Client(project=PROJECT)

    # Delete existing rows for this snapshot date (idempotent re-import)
    delete_query = f"""
    DELETE FROM `{TABLE_REF}`
    WHERE snapshot_date = '{snap_date}'
    """
    print(f"\nDeleting existing rows for {snap_date}...")
    client.query(delete_query).result()

    # Sanitize all rows and strip None values
    clean_rows = []
    for r in rows:
        clean = {}
        for k, v in sanitize_row(r).items():
            if v is not None and v != '':
                clean[k] = v
        clean_rows.append(clean)

    # Write to temp JSONL file
    tmp_file = tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False)
    for row in clean_rows:
        tmp_file.write(json.dumps(row) + '\n')
    tmp_file.close()

    print(f"  Wrote {len(clean_rows)} rows to temp JSONL file")

    # Upload from file
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
    )

    with open(tmp_file.name, 'rb') as f:
        job = client.load_table_from_file(f, TABLE_REF, job_config=job_config)
    job.result()

    os.unlink(tmp_file.name)

    if job.errors:
        print(f"ERROR: {job.errors}")
        sys.exit(1)

    print(f"✅ Successfully loaded {len(clean_rows)} rows into {TABLE_REF}")


def main():
    args = parse_args()

    if not os.path.exists(args.input_file):
        print(f"ERROR: File not found: {args.input_file}")
        sys.exit(1)

    snap_date = args.snapshot_date or date.today().isoformat()
    source_file = os.path.basename(args.input_file)

    df = read_bulksheet(args.input_file)
    sb_df = read_sb_sheet(args.input_file)

    # Build all entity rows
    all_rows = []
    # SP entities
    all_rows.extend(build_campaign_rows(df, snap_date, source_file))
    all_rows.extend(build_ad_group_rows(df, snap_date, source_file))
    all_rows.extend(build_keyword_rows(df, snap_date, source_file))
    all_rows.extend(build_negative_keyword_rows(df, snap_date, source_file))
    all_rows.extend(build_product_targeting_rows(df, snap_date, source_file))
    all_rows.extend(build_product_ad_rows(df, snap_date, source_file))
    all_rows.extend(build_bidding_adjustment_rows(df, snap_date, source_file))
    all_rows.extend(build_negative_product_targeting_rows(df, snap_date, source_file))
    all_rows.extend(build_campaign_negative_keyword_rows(df, snap_date, source_file))

    # SB entities (if sheet present)
    if sb_df is not None:
        all_rows.extend(build_sb_campaign_rows(sb_df, snap_date, source_file))
        all_rows.extend(build_sb_ad_group_rows(sb_df, snap_date, source_file))
        all_rows.extend(build_sb_keyword_rows(sb_df, snap_date, source_file))
        all_rows.extend(build_sb_negative_keyword_rows(sb_df, snap_date, source_file))

    # Stats
    entity_counts = {}
    for r in all_rows:
        et = r['entity_type']
        entity_counts[et] = entity_counts.get(et, 0) + 1

    print(f"\nParsed {len(all_rows)} total entities:")
    for et, count in sorted(entity_counts.items()):
        print(f"  {et}: {count}")

    if args.dry_run:
        print("\n[DRY RUN] No data uploaded.")
        # Show sample of each type
        for et in sorted(entity_counts.keys()):
            sample = [r for r in all_rows if r['entity_type'] == et][:2]
            print(f"\n  Sample {et}:")
            for s in sample:
                clean = {k: v for k, v in s.items() if v is not None and v != ''}
                print(f"    {clean}")
    else:
        upload_to_bigquery(all_rows, snap_date)


if __name__ == "__main__":
    main()
