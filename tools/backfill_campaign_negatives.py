"""
Backfill Campaign Negative Keyword rows for campaigns that launched without them.

New campaigns have never carried the curated negative list from
DE_PRODUCT_PHRASE_NEGATIVES -- the bulksheet generator in DoPage.tsx emits
Campaign / Ad Group / Keyword / Product Ad rows but no negatives. This script
produces a one-off catch-up bulksheet for the campaigns already live.

Scope:
  - ENABLED campaigns only (paused/archived don't spend)
  - created after 2026-01-03 (the date the Amazon negative_keyword sync froze --
    past that we have no evidence either way, so we don't touch them)
  - BRAND_DEFENSE / PRODUCT_DEFENSE excluded: the _ALL list negates brand terms
    (lolli/lollibox/lollime), which is exactly what defense campaigns exist to buy
  - Sponsored Products only -- the SB negative-keyword entity format is unverified

Already-negated exclusion: the Fivetran negative_keyword sync froze 2026-01-03, so
"already negated" = frozen `V_SRC_AmazonAds_negative_keyword` UNION the warehouse-owned
`DE_NEGATIVE_KEYWORDS` registry (the authority since the freeze). Any (campaign, term)
pair already enabled as a negative there -- at either campaign or ad-group level, any
match type -- is skipped, so the sheet neither re-adds existing negatives nor misses
ones added since the freeze.

Own-keyword conflict guard: a campaign-level negative phrase that appears inside one of
the campaign's own ENABLED bidded keywords (DIM_KEYWORD, is_current) would block the
campaign's own targeting -- e.g. family phrase 'cute' vs a campaign bidding 'cute diary'.
Those rows are skipped and reported; the curated list is family-wide, the keyword set is
per-campaign, and the keyword wins.

Usage:
    /usr/bin/python3 tools/backfill_campaign_negatives.py [--out PATH]

Output: XLSX with a 'Sponsored Products Campaigns' sheet, headers matching
DoPage.tsx SP_HEADERS. Prepare-only -- review, then upload to Amazon manually.
"""
import argparse
import re
import subprocess
import json
import sys
from collections import defaultdict

import openpyxl

PROJECT = "onyga-482313"
NEG_SYNC_FROZEN_AT = "2026-01-03"

# Mirrors SP_HEADERS in dashboard-react/src/pages/DoPage.tsx
SP_HEADERS = [
    'Product', 'Entity', 'Operation',
    'Campaign ID', 'Ad Group ID', 'Portfolio ID', 'Ad ID', 'Keyword ID', 'Product Targeting ID',
    'Campaign Name', 'Ad Group Name',
    'Campaign Name (Informational only)', 'Ad Group Name (Informational only)',
    'Portfolio Name (Informational only)',
    'Start Date', 'End Date', 'Targeting Type', 'State',
    'Campaign State (Informational only)', 'Ad Group State (Informational only)',
    'Daily Budget', 'SKU', 'ASIN (Informational only)',
    'Eligibility Status (Informational only)', 'Reason for Ineligibility (Informational only)',
    'Ad Group Default Bid', 'Ad Group Default Bid (Informational only)',
    'Bid', 'Keyword Text', 'Native Language Keyword', 'Native Language Locale',
    'Match Type', 'Bidding Strategy', 'Placement', 'Percentage',
    'Product Targeting Expression', 'Resolved Product Targeting Expression (Informational only)',
]

# Campaigns the family map can't resolve (no 90d spend yet) fall back to the name
# prefix. Kept explicit rather than clever so a wrong guess is visible in review.
NAME_PREFIX_FAMILY = [
    (r'^BALL|BALLS|VIDEO-\s*(COMP/)?BALL', 'LolliBall'),
    (r'^BOTTLE', 'Bottle'),
    (r'^BOX', 'Lollibox'),
    (r'^BUNNY', 'Bunny'),
    (r'^FRESH', 'Fresh'),
    (r'^ME-|^MINT', 'LolliME'),
]

DEFENSE_RE = re.compile(r'defense|/DEFENSE', re.IGNORECASE)

MATCH_TYPE_MAP = {
    'Negative Phrase': 'NEGATIVE_PHRASE',
    'Negative Exact': 'NEGATIVE_EXACT',
}


def bq(sql):
    out = subprocess.run(
        ['bq', 'query', '--use_legacy_sql=false', '--format=json', '--max_rows=100000', sql],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        sys.exit(f"BigQuery failed:\n{out.stderr}")
    return json.loads(out.stdout or '[]')


def infer_family(name):
    for pattern, fam in NAME_PREFIX_FAMILY:
        if re.search(pattern, name, re.IGNORECASE):
            return fam
    return None


def fetch_campaigns():
    rows = bq(f"""
        WITH enabled AS (
          SELECT campaign_id, campaign_name, campaign_type, CAST(creation_date AS DATE) AS created
          FROM `{PROJECT}.OI.DIM_CAMPAIGN`
          QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY last_updated_date DESC) = 1
             AND state = 'ENABLED'
        )
        SELECT e.campaign_id, e.campaign_name, e.campaign_type, e.created, m.parent_name
        FROM enabled e
        LEFT JOIN `{PROJECT}.OI.V_CAMPAIGN_FAMILY_MAP` m ON m.campaign_id = e.campaign_id
        WHERE e.created > '{NEG_SYNC_FROZEN_AT}'
        ORDER BY e.created DESC, e.campaign_name
    """)
    return rows


def fetch_negatives():
    # V_PRODUCT_PHRASE_NEGATIVES carries origin_level in its SELECT DISTINCT, so a phrase
    # curated at both _ALL and family level comes back twice (e.g. LolliME/lollipop,
    # Lollibox/stitch). Amazon rejects duplicate negatives within a campaign, so collapse
    # to one row per (family, phrase, match_type) here. Belongs in the view -- see
    # V_PRODUCT_PHRASE_NEGATIVES.sql:108.
    rows = bq(f"""
        SELECT effective_parent_name, phrase, match_type
        FROM `{PROJECT}.OI.V_PRODUCT_PHRASE_NEGATIVES`
        GROUP BY 1, 2, 3
        ORDER BY 1, 2
    """)
    by_family = defaultdict(list)
    for r in rows:
        by_family[r['effective_parent_name']].append((r['phrase'], r['match_type']))
    return by_family


def fetch_existing_negatives():
    # "Already negated" = frozen Fivetran snapshot UNION the warehouse-owned registry
    # (DE_NEGATIVE_KEYWORDS is the authority for negatives added after 2026-01-03).
    # Grain: (campaign_id, lowered term), any level / any match type — if the term is
    # already negated anywhere in the campaign we don't re-add it; Amazon rejects true
    # duplicates and a phrase-vs-exact upgrade is out of scope for a backfill.
    # Fivetran carries mixed-case states ('ENABLED'/'enabled'); DE uses 'ENABLED'.
    rows = bq(f"""
        SELECT DISTINCT campaign_id, LOWER(TRIM(keyword_text)) AS kw
        FROM (
          SELECT campaign_id, keyword_text, state
          FROM `{PROJECT}.OI.V_SRC_AmazonAds_negative_keyword`
          UNION ALL
          SELECT campaign_id, keyword_text, state
          FROM `{PROJECT}.OI.DE_NEGATIVE_KEYWORDS`
        )
        WHERE UPPER(state) = 'ENABLED' AND keyword_text IS NOT NULL
    """)
    existing = defaultdict(set)
    for r in rows:
        existing[r['campaign_id']].add(r['kw'])
    return existing


def fetch_bidded_keywords():
    # The campaign's own ENABLED positive keywords -- a negative phrase contained in one
    # of these would block the campaign's own targeting. DIM_KEYWORD is the consolidated
    # (still-syncing) keyword source; is_current gives latest state.
    rows = bq(f"""
        SELECT DISTINCT campaign_id, LOWER(TRIM(keyword_text)) AS kw
        FROM `{PROJECT}.OI.DIM_KEYWORD`
        WHERE is_current AND UPPER(state) = 'ENABLED'
          AND UPPER(COALESCE(match_type, '')) NOT LIKE '%NEGATIVE%'
          AND keyword_text IS NOT NULL
    """)
    bidded = defaultdict(set)
    for r in rows:
        bidded[r['campaign_id']].add(r['kw'])
    return bidded


def conflicts_with_bidded(phrase, match_type, bidded_kws):
    # Amazon negative phrase blocks any search term containing the phrase as a
    # contiguous word sequence; negative exact blocks only the exact term.
    if match_type == 'Negative Exact':
        return phrase in bidded_kws
    pat = re.compile(r'(^|\s)' + re.escape(phrase) + r'(\s|$)')
    return any(pat.search(kw) for kw in bidded_kws)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default='.tmp/backfill_campaign_negatives.xlsx')
    args = ap.parse_args()

    campaigns = fetch_campaigns()
    negatives = fetch_negatives()
    existing = fetch_existing_negatives()
    bidded = fetch_bidded_keywords()

    rows, included, skipped, conflicts = [], [], [], []
    total_already = 0

    for c in campaigns:
        name, cid = c['campaign_name'], c['campaign_id']

        if c['campaign_type'] != 'SP':
            skipped.append((name, f"{c['campaign_type']} — SB negative format unverified"))
            continue
        if DEFENSE_RE.search(name):
            skipped.append((name, 'defense campaign — brand terms must stay biddable'))
            continue

        fam = c.get('parent_name')
        source = 'family map'
        if not fam or fam == 'Unknown':
            fam = infer_family(name)
            source = 'name prefix'
        if not fam or fam not in negatives:
            skipped.append((name, f'no family resolved (map={c.get("parent_name")})'))
            continue

        already = existing.get(cid, set())
        campaign_kws = bidded.get(cid, set())
        emitted = set()  # defensive (campaign, term) dedupe within the sheet
        n_new, n_already = 0, 0
        for phrase, match_type in negatives[fam]:
            key = phrase.strip().lower()
            if key in already:
                n_already += 1
                continue
            if key in emitted:
                continue
            if conflicts_with_bidded(key, match_type, campaign_kws):
                conflicts.append((name, key, sorted(campaign_kws)[:3]))
                continue
            emitted.add(key)
            rows.append({
                'Product': 'Sponsored Products',
                'Entity': 'Campaign Negative Keyword',
                'Operation': 'Create',
                'Campaign ID': cid,
                'Campaign Name (Informational only)': name,
                'Keyword Text': phrase,
                'Match Type': MATCH_TYPE_MAP[match_type],
                'State': 'ENABLED',
            })
            n_new += 1
        total_already += n_already
        if n_new == 0:
            skipped.append((name, f'all {n_already} family negatives already present'))
            continue
        included.append((name, fam, source, n_new, n_already))

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = 'Sponsored Products Campaigns'
    ws.append(SP_HEADERS)
    for r in rows:
        ws.append([r.get(h, '') for h in SP_HEADERS])
    wb.save(args.out)

    print(f"\n{'CAMPAIGN':<52} {'FAMILY':<10} {'VIA':<12} {'NEW':>4} {'HAVE':>5}")
    for name, fam, source, n_new, n_already in included:
        print(f"{name[:50]:<52} {fam:<10} {source:<12} {n_new:>4} {n_already:>5}")
    print(f"\nSkipped ({len(skipped)}):")
    for name, why in skipped:
        print(f"  {name[:50]:<52} {why}")
    if conflicts:
        print(f"\nOwn-keyword conflicts dropped ({len(conflicts)}):")
        for name, phrase, _ in conflicts:
            print(f"  {name[:50]:<52} '{phrase}' appears in a bidded keyword")
    print(f"\n{len(rows)} negative rows across {len(included)} campaigns "
          f"({total_already} already negated, {len(conflicts)} own-keyword conflicts) → {args.out}")


if __name__ == '__main__':
    main()
