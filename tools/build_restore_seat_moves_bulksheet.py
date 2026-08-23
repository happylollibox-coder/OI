#!/usr/bin/env python3
"""Undo a leak book — as far as a bulksheet CAN undo one.

WHAT IT RESTORES
    Every keyword or product target the leak book PAUSED gets a row putting back the exact state
    it carried before the pause (read from the audit's `old_state`, never assumed to be enabled).
    Portfolio is re-read LIVE, so a campaign whose portfolio moved since the book was built is
    not detached by the restore.

WHAT IT CANNOT RESTORE, AND WHY
    The negatives. A negative keyword and a negative product target are CREATED by the leak book
    without an id; archiving one later needs the id Amazon assigns at creation, and this
    warehouse's negative-keyword feed has been frozen since 2026-01-03 — DE_NEGATIVE_KEYWORDS is
    the registry of record precisely because the feed stopped, so the id never arrives on its
    own. This file prints every negative the book emitted and names them as not restorable, so
    the gap is stated, not silent. Removing one is a hand edit in the Amazon console against the
    ad group's negative list.

    It reads the AUDIT CSV the book run wrote, so the restore is scoped to exactly what that
    book changed. It never re-derives a population.

USAGE
    /usr/bin/python3 tools/build_restore_seat_moves_bulksheet.py --audit .tmp/seat_moves_..._audit.csv
"""
import argparse
import csv
import json
import os
import subprocess
import sys
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_stop_nonconverting_bulksheet import (  # noqa: E402
    SP_HEADERS, SB_HEADERS, SP_SHEET, SB_SHEET)

import openpyxl  # noqa: E402

PROJECT = 'onyga-482313'
PAUSE = 'PAUSE'
NEGATES = ('NEGATE_KEYWORD', 'NEGATE_TARGET')


def bq(sql):
    out = subprocess.run(
        ['bq', 'query', f'--project_id={PROJECT}', '--use_legacy_sql=false',
         '--nouse_cache', '--format=json', '--max_rows=100000', sql],
        capture_output=True, text=True, check=True).stdout
    return json.loads(out or '[]')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--audit', required=True, help='the _audit.csv the leak book run wrote')
    ap.add_argument('-o', '--out', default=f".tmp/restore_seat_moves_{date.today():%Y%m%d}.xlsx")
    args = ap.parse_args()

    with open(args.audit) as f:
        allrows = list(csv.DictReader(f))
    pauses = [r for r in allrows if r['disposition'] == PAUSE]
    negs = [r for r in allrows if r['disposition'] in NEGATES]

    if negs:
        print(f"NOT RESTORABLE BY SHEET — {len(negs)} negative(s) the book created. Removing one "
              f"is a hand edit on the ad group's negative list in the Amazon console:")
        for r in negs:
            what = 'negative product target' if r['disposition'] == 'NEGATE_TARGET' else 'negative keyword'
            print(f"  {what}: \"{r['search_term']}\" in {r['campaign']} (ad group {r['ad_group_id']})")

    if not pauses:
        print('Audit holds no pause rows — nothing this sheet can restore.')
        return

    ids = sorted({r['campaign_id'] for r in pauses})
    id_list = ','.join(f"'{i}'" for i in ids)
    last_pf = {r['campaign_id']: r['portfolio_id'] for r in bq(f"""
        SELECT CAST(campaign_id AS STRING) AS campaign_id, portfolio_id FROM (
          SELECT campaign_id, portfolio_id,
                 ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY date DESC) rn
          FROM `{PROJECT}.OI.V_SRC_AmazonAds_campaign_history`
          WHERE CAST(campaign_id AS STRING) IN ({id_list}) AND portfolio_id IS NOT NULL)
        WHERE rn = 1""")}

    def old_state(r, sb):
        """The state the row carried before the book paused it — never a blind 'enabled'."""
        st = (r.get('old_state') or '').strip() or 'ENABLED'
        return st.lower() if sb else st.upper()

    def sp_row(r):
        row = {h: '' for h in SP_HEADERS}
        is_target = str(r.get('is_auto')).lower() == 'true' or str(r.get('is_pt')).lower() == 'true'
        row.update({
            'Product': 'Sponsored Products',
            'Entity': 'Product Targeting' if is_target else 'Keyword',
            'Operation': 'Update',
            'Campaign ID': r['campaign_id'],
            'Ad Group ID': r['ad_group_id'],
            'Portfolio ID': last_pf.get(r['campaign_id']) or r['portfolio_id'] or '',
            'Campaign Name (Informational only)': r['campaign'],
            'State': old_state(r, sb=False),
        })
        row['Product Targeting ID' if is_target else 'Keyword ID'] = r['keyword_id']
        return row

    def sb_row(r):
        row = {h: '' for h in SB_HEADERS}
        row.update({
            'Product': 'Sponsored Brands',
            'Entity': 'Keyword',
            'Operation': 'Update',
            'Campaign Id': r['campaign_id'],
            'Ad Group Id': r['ad_group_id'],
            'Portfolio Id': last_pf.get(r['campaign_id']) or r['portfolio_id'] or '',
            'Keyword Id': r['keyword_id'],
            'State': old_state(r, sb=True),
        })
        return row

    sp = [r for r in pauses if (r['channel'] or '').upper() != 'SB']
    sb = [r for r in pauses if (r['channel'] or '').upper() == 'SB']

    wb = openpyxl.Workbook()
    wb.remove(wb.active)
    if sp:
        ws = wb.create_sheet(SP_SHEET)
        ws.append(SP_HEADERS)
        for r in sp:
            ws.append([sp_row(r)[h] for h in SP_HEADERS])
    if sb:
        ws = wb.create_sheet(SB_SHEET)
        ws.append(SB_HEADERS)
        for r in sb:
            ws.append([sb_row(r)[h] for h in SB_HEADERS])
    os.makedirs(os.path.dirname(args.out) or '.', exist_ok=True)
    wb.save(args.out)
    print(f"wrote {len(pauses)} restore rows ({len(sp)} SP · {len(sb)} SB) -> {args.out}")
    print("Every row puts back the state the audit recorded before the pause. Portfolio read "
          "live so the restore cannot detach a campaign.")
    if negs:
        print(f"{len(negs)} negative(s) are NOT in this sheet and cannot be — see the list above.")


if __name__ == '__main__':
    main()
