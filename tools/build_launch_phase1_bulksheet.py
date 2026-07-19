"""
Build the Sponsored Products bulksheet for the launch phase-1 controller.

Reads V_LAUNCH_PHASE1 (the launch bid/budget controller, spec:
architecture/CAMPAIGN_LAUNCH_RAMP.md) and emits an Amazon Ads SP bulk-operation
xlsx with:
  - Campaign / Update / Daily Budget rows   (one per campaign whose suggested
    budget differs from its current budget)
  - Keyword / Update / Bid rows             (KEYWORD targets)
  - Product Targeting / Update / Bid rows    (AUTO + PRODUCT targets -- the auto
    groups close-match/loose-match/substitutes/complements are Product Targeting
    entities keyed by the target's keyword_id, NOT Keyword rows)

Only rows the controller actually decided are written: budget changes, and bid
CUT / RAISE_STRONG / RAISE_WEAK / STARVE. HOLD and NO_BID (auto groups with no
current bid to move) are skipped -- NO_BID needs a seed-bid decision first.

Headers mirror SP_HEADERS in dashboard-react/src/pages/DoPage.tsx (same file the
coacher's DoPage export uses), so this uploads through the same path.

Usage:
    /usr/bin/python3 tools/build_launch_phase1_bulksheet.py [--out PATH] [--include-cuts/--no-cuts]

Prepare-only. Review the audit CSV printed alongside, then upload to Amazon manually.
"""
import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone

import openpyxl

PROJECT = "onyga-482313"

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

BID_ACTIONS = {'CUT', 'RAISE_STRONG', 'RAISE_WEAK', 'STARVE'}


def bq(sql):
    out = subprocess.run(
        ['bq', 'query', '--use_legacy_sql=false', '--format=json', '--max_rows=100000', sql],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        sys.exit(f"BigQuery failed:\n{out.stderr}")
    return json.loads(out.stdout or '[]')


def fetch():
    return bq("""
        SELECT campaign_id, campaign_name, day_of_ramp, pct_dark,
               current_budget, suggested_budget,
               keyword_id, ad_group_id, target_text, target_type, match_type,
               clk3, tgt_roas_1d, tgt_eq3, current_bid, suggested_bid, bid_action
        FROM `onyga-482313.OI.V_LAUNCH_PHASE1`
        ORDER BY campaign_name, target_text
    """)


def blank_row():
    return {h: '' for h in SP_HEADERS}


def build(rows, include_cuts):
    sp, audit = [], []
    seen_budget = set()
    for r in rows:
        camp = r['campaign_name']
        cid = r['campaign_id']

        # one budget row per campaign whose suggestion moves the budget
        if cid not in seen_budget and r['suggested_budget'] and r['current_budget']:
            cur = round(float(r['current_budget']), 2)
            new = round(float(r['suggested_budget']), 2)
            if abs(new - cur) >= 0.01:
                seen_budget.add(cid)
                row = blank_row()
                row.update({
                    'Product': 'Sponsored Products', 'Entity': 'Campaign', 'Operation': 'Update',
                    'Campaign ID': cid, 'Campaign Name (Informational only)': camp,
                    'Daily Budget': f"{new:.2f}",
                })
                sp.append(row)
                audit.append([camp, 'BUDGET', '', f"${cur:.2f}", f"${new:.2f}",
                              f"day {r['day_of_ramp']}, dark {r['pct_dark']}%"])

        # bid rows
        act = r['bid_action']
        if act not in BID_ACTIONS:
            continue
        if act == 'CUT' and not include_cuts:
            continue
        if not r['keyword_id'] or r['suggested_bid'] is None or r['current_bid'] is None:
            continue
        cur_b = round(float(r['current_bid']), 2)
        new_b = round(float(r['suggested_bid']), 2)
        if abs(new_b - cur_b) < 0.01:
            continue

        row = blank_row()
        row.update({
            'Product': 'Sponsored Products', 'Operation': 'Update', 'State': 'ENABLED',
            'Campaign ID': cid, 'Ad Group ID': r['ad_group_id'],
            'Campaign Name (Informational only)': camp,
            'Bid': f"{new_b:.2f}",
        })
        if r['target_type'] == 'KEYWORD':
            row['Entity'] = 'Keyword'
            row['Keyword ID'] = r['keyword_id']
            row['Keyword Text'] = r['target_text']
            row['Match Type'] = (r['match_type'] or '').upper()
        else:  # AUTO or PRODUCT -> Product Targeting
            row['Entity'] = 'Product Targeting'
            row['Product Targeting ID'] = r['keyword_id']
            row['Product Targeting Expression'] = r['target_text']
        sp.append(row)
        audit.append([camp, act, r['target_text'], f"${cur_b:.2f}", f"${new_b:.2f}",
                      f"clk3={r['clk3']} 1d={r['tgt_roas_1d']} eq3={r['tgt_eq3']}"])
    return sp, audit


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default='exports/launch_phase1_bulksheet.xlsx')
    ap.add_argument('--no-cuts', dest='cuts', action='store_false',
                    help='omit CUT rows (keep only raises + budgets)')
    ap.set_defaults(cuts=True)
    args = ap.parse_args()

    rows = fetch()
    sp, audit = build(rows, args.cuts)

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = 'Sponsored Products Campaigns'
    ws.append(SP_HEADERS)
    for r in sp:
        ws.append([r.get(h, '') for h in SP_HEADERS])
    wb.save(args.out)

    audit_path = args.out.rsplit('.', 1)[0] + '_audit.csv'
    with open(audit_path, 'w') as f:
        f.write("campaign,action,target,from,to,evidence\n")
        for a in audit:
            f.write(",".join('"' + str(x).replace('"', '""') + '"' for x in a) + "\n")

    n_bud = sum(1 for a in audit if a[1] == 'BUDGET')
    n_bid = len(audit) - n_bud
    stamp = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')
    print(f"[{stamp}] wrote {len(sp)} SP rows -> {args.out}")
    print(f"  {n_bud} budget rows, {n_bid} bid rows (cuts {'IN' if args.cuts else 'OUT'})")
    print(f"  audit -> {audit_path}")
    print("  PREPARE-ONLY: review the audit, then upload to Amazon manually.")


if __name__ == '__main__':
    main()
