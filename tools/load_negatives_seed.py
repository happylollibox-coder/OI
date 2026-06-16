#!/usr/bin/env python3
"""
Seed DE_NEGATIVE_KEYWORDS + DE_NEGATIVE_TARGETS from an Amazon Ads bulksheet download.

One-time (re-runnable) seed of the warehouse-owned negative registries that replace the
frozen Fivetran source. After seeding, SP_SYNC_NEGATIVES keeps them current from
FACT_PPC_CHANGE_LOG.

Usage:
    python3 load_negatives_seed.py <bulksheet.xlsx> [--dry-run]

WRITE_TRUNCATE with an EXPLICIT schema (never autodetect — numeric ids would become INT64).
A re-run fully replaces the SEED snapshot; negatives we later add via the DO page
(source='COACH'/'MANUAL') are layered on by SP_SYNC_NEGATIVES, not here.
"""
import argparse
import hashlib
import os
import sys
from datetime import datetime, timezone

import pandas as pd
from google.cloud import bigquery

PROJECT = "onyga-482313"
DATASET = "OI"
KW_TABLE_REF = f"{PROJECT}.{DATASET}.DE_NEGATIVE_KEYWORDS"
TGT_TABLE_REF = f"{PROJECT}.{DATASET}.DE_NEGATIVE_TARGETS"

# Bulksheet Entity → (level, has_ad_group)
NEG_ENTITIES = {
    "Negative Keyword": ("AD_GROUP", True),
    "Campaign Negative Keyword": ("CAMPAIGN", False),
}
NEG_TARGET_ENTITIES = {
    "Negative Product Targeting": ("AD_GROUP", True),
    "Campaign Negative Product Targeting": ("CAMPAIGN", False),
}
SHEETS = ["Sponsored Products Campaigns", "Sponsored Brands Campaigns", "SB Multi Ad Group Campaigns"]


# Explicit schemas — never autodetect (numeric-looking ids would become INT64).
def _sf(n, t):
    return bigquery.SchemaField(n, t)


def _schema(extra_text_col):
    return [
        _sf("negative_id", "STRING"), _sf("campaign_id", "STRING"), _sf("campaign_name", "STRING"),
        _sf("ad_group_id", "STRING"), _sf("ad_group_name", "STRING"), _sf(extra_text_col, "STRING"),
    ] + ([_sf("match_type", "STRING")] if extra_text_col == "keyword_text" else []) + [
        _sf("level", "STRING"), _sf("state", "STRING"), _sf("source", "STRING"),
        _sf("added_at", "TIMESTAMP"), _sf("removed_at", "TIMESTAMP"), _sf("change_id", "STRING"),
        _sf("source_file", "STRING"), _sf("updated_at", "TIMESTAMP"),
    ]


KW_SCHEMA = _schema("keyword_text")
TGT_SCHEMA = _schema("targeting_expression")


def col(r, *names, default=""):
    for n in names:
        if n in r and pd.notna(r[n]) and str(r[n]).strip() != "":
            return str(r[n]).strip()
    return default


def norm_match(mt: str) -> str:
    m = mt.replace(" ", "").replace("_", "").upper()
    if "EXACT" in m:
        return "NEGATIVE_EXACT"
    if "PHRASE" in m:
        return "NEGATIVE_PHRASE"
    return mt.upper() or "NEGATIVE_EXACT"


def norm_state(s: str) -> str:
    return "ENABLED" if (s or "").strip().lower() in ("", "enabled") else s.strip().upper()


def mint_id(campaign_id, ad_group_id, text, match_type) -> str:
    h = hashlib.sha1(f"{campaign_id}|{ad_group_id}|{text}|{match_type}".encode()).hexdigest()[:12]
    return f"neg_{h}"


def extract(path: str) -> list[dict]:
    now = datetime.now(timezone.utc).isoformat()
    src = os.path.basename(path)
    rows, seen = [], set()
    xl = pd.ExcelFile(path)
    for sheet in [s for s in SHEETS if s in xl.sheet_names]:
        df = pd.read_excel(path, sheet_name=sheet, dtype=str).fillna("")
        if "Entity" not in df.columns:
            continue
        df["Entity"] = df["Entity"].str.strip()
        for entity, (level, has_ag) in NEG_ENTITIES.items():
            for _, r in df[df["Entity"] == entity].iterrows():
                campaign_id = col(r, "Campaign ID", "Campaign Id")
                ad_group_id = col(r, "Ad Group ID", "Ad Group Id") if has_ag else ""
                text = col(r, "Keyword Text")
                if not campaign_id or not text:
                    continue
                match_type = norm_match(col(r, "Match Type", default="NEGATIVE_EXACT"))
                neg_id = col(r, "Keyword ID", "Keyword Id") or mint_id(campaign_id, ad_group_id, text, match_type)
                key = (campaign_id, ad_group_id, text.lower(), match_type)
                if key in seen:
                    continue
                seen.add(key)
                rows.append({
                    "negative_id": neg_id,
                    "campaign_id": campaign_id,
                    "campaign_name": col(r, "Campaign Name", "Campaign Name (Informational only)"),
                    "ad_group_id": ad_group_id or None,
                    "ad_group_name": col(r, "Ad Group Name", "Ad Group Name (Informational only)") or None,
                    "keyword_text": text,
                    "match_type": match_type,
                    "level": level,
                    "state": norm_state(col(r, "State")),
                    "source": "SEED",
                    "added_at": now,
                    "removed_at": None,
                    "change_id": None,
                    "source_file": src,
                    "updated_at": now,
                })
    return rows


def extract_targets(path: str) -> list[dict]:
    now = datetime.now(timezone.utc).isoformat()
    src = os.path.basename(path)
    rows, seen = [], set()
    xl = pd.ExcelFile(path)
    for sheet in [s for s in SHEETS if s in xl.sheet_names]:
        df = pd.read_excel(path, sheet_name=sheet, dtype=str).fillna("")
        if "Entity" not in df.columns:
            continue
        df["Entity"] = df["Entity"].str.strip()
        for entity, (level, has_ag) in NEG_TARGET_ENTITIES.items():
            for _, r in df[df["Entity"] == entity].iterrows():
                campaign_id = col(r, "Campaign ID", "Campaign Id")
                ad_group_id = col(r, "Ad Group ID", "Ad Group Id") if has_ag else ""
                expr = col(r, "Product Targeting Expression",
                           "Resolved Product Targeting Expression (Informational only)")
                if not campaign_id or not expr:
                    continue
                key = (campaign_id, ad_group_id, expr.lower())
                if key in seen:
                    continue
                seen.add(key)
                neg_id = col(r, "Product Targeting ID", "Product Targeting Id") or \
                    "negt_" + hashlib.sha1(f"{campaign_id}|{ad_group_id}|{expr}".encode()).hexdigest()[:12]
                rows.append({
                    "negative_id": neg_id,
                    "campaign_id": campaign_id,
                    "campaign_name": col(r, "Campaign Name", "Campaign Name (Informational only)"),
                    "ad_group_id": ad_group_id or None,
                    "ad_group_name": col(r, "Ad Group Name", "Ad Group Name (Informational only)") or None,
                    "targeting_expression": expr,
                    "level": level,
                    "state": norm_state(col(r, "State")),
                    "source": "SEED",
                    "added_at": now,
                    "removed_at": None,
                    "change_id": None,
                    "source_file": src,
                    "updated_at": now,
                })
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input_file")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    kw_rows = extract(args.input_file)
    tgt_rows = extract_targets(args.input_file)
    print(f"Parsed {len(kw_rows)} negative keywords + {len(tgt_rows)} negative product targets.")
    if kw_rows:
        kdf = pd.DataFrame(kw_rows)
        print(f"  keywords: {kdf['level'].value_counts().to_dict()} {kdf['match_type'].value_counts().to_dict()}")
    if tgt_rows:
        tdf = pd.DataFrame(tgt_rows)
        print(f"  targets:  {tdf['level'].value_counts().to_dict()}")
        print(tdf[["campaign_name", "targeting_expression", "level", "state"]].head(5).to_string(index=False))
    if not kw_rows and not tgt_rows:
        print("No negative rows found in the bulksheet. Nothing to load.")
        sys.exit(1)

    if args.dry_run:
        print("\n[dry-run] not loaded.")
        return

    client = bigquery.Client(project=PROJECT)

    def load(rows, ref, schema):
        if not rows:
            print(f"  (no rows for {ref})")
            return
        job = client.load_table_from_json(
            rows, ref,
            job_config=bigquery.LoadJobConfig(write_disposition="WRITE_TRUNCATE", schema=schema))
        job.result()
        if job.errors:
            print("LOAD ERRORS:", job.errors)
            sys.exit(1)
        print(f"  Seeded {len(rows)} → {ref} (WRITE_TRUNCATE, explicit schema).")

    load(kw_rows, KW_TABLE_REF, KW_SCHEMA)
    load(tgt_rows, TGT_TABLE_REF, TGT_SCHEMA)


if __name__ == "__main__":
    main()
