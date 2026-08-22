#!/usr/bin/env python3
"""THE REPRICE BOOK — the manual bulksheet that executes the bar/SE keyword states.

WHY THIS EXISTS
    v27.103 gave every keyword a verdict against its FAMILY's bar (AT_BAR / REPRICE / LOSER —
    see architecture/KEYWORD_STATE.md). NO ENGINE acts on those states, by ruling: the one
    executor is this file's output, which Ori reads row by row and uploads BY HAND to
    Amazon Ads > Bulk operations. This script prepares; it never touches Amazon.

WHAT IT EMITS
    - Bid updates for REPRICE and AT_BAR rows whose placement-translated affordable bid differs
      from the current bid by more than one 5% ease step (the engine's own smallest standing
      move — the materiality floor is derived from that step, not invented).
    - Pause rows for LOSERs (ruling 4: failed AT their price) — ALWAYS marked CHECK FIRST.
    - An audit CSV with every candidate row and its disposition, a plain-English README
      (TRIGGER - EVIDENCE => MOVE, no codes), and a restore sheet via
      build_restore_reprice_bulksheet.py, so reversibility is a property, not a claim.

THE PRICE (A3 + A4)
    The verdict's own settled-90d window prices the verdict's evidence: affordable CPC =
    settled GP-per-click / family bar (the guard-cleaned reading where the mix-drift guard
    deferred). That CPC becomes a BID through the campaign's measured placement multiplier
    (V_BID_CPC_TRANSFER.m_effective — the model's trustworthy part; beta=0 on brand defense):
        new_bid = affordable_cpc / m_effective
    A naive CPC->bid mapping would RAISE bids on below-bar keywords in placement-dosed
    campaigns (Fresh is ~85% placement-dosed) — that is the failure A4 exists to prevent, and
    the book additionally refuses ANY bid raise on a below-bar (REPRICE) keyword outright.
    Live 7d CPC appears in the audit as labelled CONTEXT ONLY — never in a verdict or a price.

INTERLOCKS
    - SEASON (A5): every bid-down and pause row is checked against the season ledger's
      BLOCK_CUT (V_KEYWORD_CONTEXT_GATE). A blocked row appears in the book WITH its reason
      and is NOT emitted as an executable row — nothing executes-by-hand into a live peak.
    - HOLDOUT: campaigns in DE_HOLDOUT_ASSIGNMENT arm=HOLDOUT are excluded from their
      eligible_from date — a hand upload into the holdout invalidates the trial. Asserted on
      every run and printed.
    - BRAND DEFENSE: never judged on profit, so never in this book with a profit-based row.
    - PORTFOLIO: echoed on every row. A blank Portfolio ID DETACHES a campaign on Campaign
      rows; echoing it on keyword rows is harmless and keeps the convention uniform.

USAGE
    /usr/bin/python3 tools/build_reprice_bulksheet.py [-o PATH] [--no-log]

    Re-derives everything from BigQuery on every run; there is no embedded row list. The batch
    is logged to FACT_PPC_CHANGE_LOG (source MANUAL, coach_mode MANUAL_BULKSHEET) so the
    scorecard grades it — if the book is NOT uploaded, mark the batch FAILED_UPLOAD (the
    2026-08-06 precedent) or the outcome scoring will grade moves that never happened.
"""

import argparse
import csv
import json
import os
import subprocess
import sys
from datetime import date, datetime, timezone

import openpyxl

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_stop_nonconverting_bulksheet import (  # noqa: E402
    SP_HEADERS, SB_HEADERS, SP_SHEET, SB_SHEET)

PROJECT = "onyga-482313"

# Declared constants, each derived from a house instrument (Standing Rule 0 exempt):
#   MATERIAL_STEP   one daily ease step, the engine's smallest standing move (dark ease -5%/day;
#                   the same 5% the state ladder uses for "materially above affordable").
#   FLOOR           $0.25 — the account's operative park/floor price (V_KEYWORD_LIFT parks
#                   at $0.25; the state ladder's platform_floor).
#   RAISE_CEILING   $2.00 — the house's standing bid ceiling (GUARDIAN threshold redesign);
#                   applies to bid RAISES only, a bid-down needs no ceiling.
MATERIAL_STEP = 0.05
FLOOR = 0.25
RAISE_CEILING = 2.00

SQL = """
WITH wm AS (
  SELECT MAX(date) AS d FROM `{p}.OI.FACT_AMAZON_ADS`
),
ks AS (
  SELECT * FROM `{p}.OI.V_KEYWORD_STATE` WHERE state IN ('AT_BAR','REPRICE','LOSER')
),
camp AS (
  SELECT CAST(campaign_id AS STRING) cid,
         ANY_VALUE(campaign_name) live_campaign_name,
         ANY_VALUE(campaign_type) campaign_type,
         ANY_VALUE(campaign_state) campaign_state,
         ANY_VALUE(portfolio_id) live_portfolio_id
  FROM `{p}.OI.V_DIM_CAMPAIGN_CURRENT`
  GROUP BY 1
),
-- last NON-NULL portfolio: a blank Portfolio ID means "no portfolio" on a Campaign Update row
-- and DETACHES the campaign, so every row echoes one.
restore AS (
  SELECT CAST(campaign_id AS STRING) cid,
         ARRAY_AGG(portfolio_id IGNORE NULLS ORDER BY date DESC LIMIT 1)[SAFE_OFFSET(0)] AS portfolio_id
  FROM `{p}.OI.V_SRC_AmazonAds_campaign_history`
  GROUP BY 1
),
pf AS (
  SELECT portfolio_id, portfolio_name
  FROM `{p}.OI.V_SRC_AmazonAds_portfolio`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY portfolio_id ORDER BY last_updated_date DESC) = 1
),
ag AS (
  -- V_SRC_AmazonAds_keyword unifies SP keywords, SB keywords AND targeting clauses, each with
  -- its ad_group_id — the one source that covers every entity this book can address.
  SELECT campaign_id cid, keyword_id kid,
         ad_group_id, UPPER(COALESCE(state, 'ENABLED')) ad_keyword_status
  FROM `{p}.OI.V_SRC_AmazonAds_keyword`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id, keyword_id ORDER BY date DESC) = 1
),
m AS (
  SELECT CAST(campaign_id AS STRING) cid,
         MAX(m_effective) m_effective,          -- campaign-level constant; MAX over target kinds
         LOGICAL_OR(is_brand_defense) is_brand_defense
  FROM `{p}.OI.V_BID_CPC_TRANSFER`
  GROUP BY 1
),
hold AS (
  SELECT CAST(unit_id AS STRING) cid, MIN(eligible_from) eligible_from
  FROM `{p}.OI.DE_HOLDOUT_ASSIGNMENT`
  WHERE arm = 'HOLDOUT' AND unit_type = 'CAMPAIGN'
  GROUP BY 1
),
bc AS (
  SELECT keyword_text, ANY_VALUE(gate_reason) gate_reason
  FROM `{p}.OI.V_KEYWORD_CONTEXT_GATE`
  WHERE gate_action = 'BLOCK_CUT'
  GROUP BY 1
),
live7 AS (
  SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
         SUM(Ads_cost) sp7, SUM(Ads_clicks) clk7
  FROM `{p}.OI.FACT_AMAZON_ADS`, wm
  WHERE date BETWEEN DATE_SUB(wm.d, INTERVAL 7 DAY) AND DATE_SUB(wm.d, INTERVAL 1 DAY)
    AND keyword_id IS NOT NULL
  GROUP BY 1, 2
)
SELECT
  ks.campaign_id, ks.keyword_id, ks.target_text, ks.match_type, ks.channel,
  ks.is_auto, ks.is_pt, ks.campaign_name, ks.family, ks.current_bid, ks.state,
  ks.settled_clk90, ks.settled_ord90, ks.settled_roas90, ks.settled_cpc90,
  ks.family_bar, ks.nf_orders, ks.se_eff, ks.affordable_cpc,
  ks.guard_deferred, ks.guard_flip, ks.clean_roas90, ks.clean_cpc90, ks.clean_affordable_cpc,
  ks.state_reason,
  camp.campaign_type, camp.campaign_state, camp.live_portfolio_id,
  restore.portfolio_id AS echo_portfolio_id,
  pf.portfolio_name,
  ag.ad_group_id, ag.ad_keyword_status,
  m.m_effective, COALESCE(m.is_brand_defense, FALSE) AS is_brand_defense,
  hold.eligible_from AS holdout_eligible_from,
  bc.gate_reason AS block_cut_reason,
  COALESCE(live7.sp7, 0) AS sp7, COALESCE(live7.clk7, 0) AS clk7,
  CAST(wm.d AS STRING) AS watermark,
  CAST(CURRENT_DATE('America/Los_Angeles') AS STRING) AS today_la
FROM ks
LEFT JOIN camp ON camp.cid = ks.campaign_id
LEFT JOIN restore ON restore.cid = ks.campaign_id
LEFT JOIN pf ON pf.portfolio_id = restore.portfolio_id
LEFT JOIN ag ON ag.cid = ks.campaign_id AND ag.kid = ks.keyword_id
LEFT JOIN m ON m.cid = ks.campaign_id
LEFT JOIN hold ON hold.cid = ks.campaign_id
LEFT JOIN bc ON bc.keyword_text = ks.target_text AND NOT COALESCE(ks.is_auto, FALSE)
            AND NOT COALESCE(ks.is_pt, FALSE)
LEFT JOIN live7 ON live7.cid = ks.campaign_id AND live7.kid = ks.keyword_id
CROSS JOIN wm
ORDER BY ks.state, ks.family, ks.campaign_name, ks.target_text
"""


def bq(sql):
    out = subprocess.run(
        ['bq', 'query', '--use_legacy_sql=false', '--format=json', '--max_rows=100000',
         '--nouse_cache', f'--project_id={PROJECT}', sql],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        sys.exit(f"BigQuery failed:\n{out.stderr}")
    return json.loads(out.stdout or '[]')


def num(v, default=None):
    return default if v in (None, '') else float(v)


def b(v):
    return v is True or v == 'true'


def classify(r):
    """One row -> (disposition, action, new_bid, check_first, story_bits).

    Dispositions: BID_DOWN / BID_UP / PAUSE (executable) · SEASON_BLOCKED / HOLDOUT_EXCLUDED /
    NOT_ENABLED / BRAND_DEFENSE_EXCLUDED / NO_MOVE / NO_RAISE_BELOW_BAR (book-visible, not
    executable).
    """
    state = r['state']
    cur = num(r['current_bid'])
    guard = b(r['guard_deferred'])
    afford = num(r['clean_affordable_cpc'] if guard else r['affordable_cpc'])
    cpc = num(r['clean_cpc90'] if guard else r['settled_cpc90'])
    roas = num(r['clean_roas90'] if guard else r['settled_roas90'])
    m_eff = num(r['m_effective'], 1.0) or 1.0
    bits = {
        'afford': afford, 'cpc_settled': cpc, 'roas_used': roas, 'm_eff': m_eff,
        'guard': guard,
    }

    # exclusions first — a row the book must not execute
    if b(r['is_brand_defense']):
        return 'BRAND_DEFENSE_EXCLUDED', None, None, False, bits
    if r['holdout_eligible_from'] and r['today_la'] >= r['holdout_eligible_from']:
        return 'HOLDOUT_EXCLUDED', None, None, False, bits
    if (r.get('campaign_state') or 'ENABLED').upper() != 'ENABLED' or \
       (r.get('ad_keyword_status') or 'ENABLED').upper() not in ('ENABLED',):
        return 'NOT_ENABLED', None, None, False, bits

    nf = num(r['nf_orders'])
    ord90 = num(r['settled_ord90'], 0)
    nf_condemned = nf is not None and ord90 >= nf
    bits['nf_condemned'] = nf_condemned

    if state == 'LOSER':
        # ruling 4: failed AT its price — the move is a pause, never a reprice
        if r['block_cut_reason']:
            return 'SEASON_BLOCKED', 'PAUSE', None, True, bits
        return 'PAUSE', 'PAUSE', None, True, bits

    # AT_BAR / REPRICE: price the verdict's own evidence (A3), translate through the
    # campaign's placement multiplier (A4)
    if afford is None or cur is None:
        return 'NO_MOVE', None, None, False, bits
    raw = afford / m_eff
    new_bid = round(max(raw, FLOOR), 2)
    bits['raw_bid'] = raw

    if new_bid > cur:  # a raise
        if state == 'REPRICE':
            # A4's failure mode: never raise a below-bar keyword because the placement
            # translation says its bid is cheap — its RECORD is below bar.
            return 'NO_RAISE_BELOW_BAR', None, None, False, bits
        new_bid = min(new_bid, RAISE_CEILING)
        if new_bid <= cur or (new_bid - cur) <= max(MATERIAL_STEP * cur, 0.01):
            return 'NO_MOVE', None, None, False, bits
        return 'BID_UP', 'BID', new_bid, nf_condemned, bits

    # a cut (or equal)
    if (cur - new_bid) <= max(MATERIAL_STEP * cur, 0.01):
        return 'NO_MOVE', None, None, False, bits
    if r['block_cut_reason']:
        return 'SEASON_BLOCKED', 'BID', new_bid, nf_condemned, bits
    return 'BID_DOWN', 'BID', new_bid, nf_condemned, bits


def story(r, disp, new_bid, bits):
    """Plain sentence: TRIGGER - EVIDENCE => MOVE. No codes."""
    cur = num(r['current_bid'])
    tgt = r['target_text']
    fam = r['family'] or 'unmapped'
    bar = num(r['family_bar'], 1.0)
    roas = bits['roas_used']
    guard_note = (" (judged on its own terms — the mix-drift guard excluded never-seen "
                  "zero-order search terms)" if bits['guard'] else "")
    ev = (f"its settled 90-day record returns {roas:.2f} gross-profit dollars per ad dollar "
          f"against the {fam} bar of {bar:.2f}{guard_note}")
    if disp == 'PAUSE' or (disp == 'SEASON_BLOCKED' and r['state'] == 'LOSER'):
        # ruling 4 has three kill paths — say which one fired
        if cur is not None and cur < FLOOR:
            path = (f"its bid (${cur:.2f}) already sits below the ${FLOOR:.2f} executable "
                    f"floor — there is no price left to move to, and the record does not "
                    f"clear the bar beyond its own noise")
        elif bits['afford'] is not None and bits['afford'] <= FLOOR:
            path = (f"no price above the ${FLOOR:.2f} floor is affordable at this record")
        else:
            path = (f"its settled CPC already sits at/below its affordable price — it failed "
                    f"AT its price")
        move = f"pause '{tgt}' — {path}"
    elif disp in ('BID_DOWN', 'BID_UP') or (disp == 'SEASON_BLOCKED'):
        direction = 'down' if (new_bid or 0) < (cur or 0) else 'up'
        move = (f"move the bid {direction} from ${cur:.2f} to ${new_bid:.2f} — the record "
                f"affords ${bits['afford']:.2f} per click at the bar, which is a "
                f"${new_bid:.2f} bid through this campaign's measured placement multiplier "
                f"of {bits['m_eff']:.2f}")
    else:
        move = "no executable move"
    trigger = {
        'AT_BAR': "the keyword sits at its family bar within noise",
        'REPRICE': "the keyword sits below its family bar beyond noise but an affordable "
                   "price exists",
        'LOSER': "the keyword sits below its family bar beyond noise at its price",
    }[r['state']]
    s = f"{trigger} - {ev} => {move}."
    if bits.get('nf_condemned'):
        s += (f" CHECK FIRST: at {int(num(r['settled_ord90'],0))} orders this keyword is past "
              f"its family's collapse point of {int(num(r['nf_orders'],0))} orders — the noise "
              f"band no longer shelters it; this verdict is new under the per-family rule, so "
              f"eyeball it before uploading.")
    if disp == 'SEASON_BLOCKED':
        s += (f" BLOCKED BY THE SEASON LEDGER — {r['block_cut_reason']} — this row is shown, "
              f"not executed; do not hand-carry it into a live peak.")
    return s


def sp_bid_row(r, new_bid):
    row = {h: '' for h in SP_HEADERS}
    is_target = b(r['is_auto']) or b(r['is_pt'])
    row.update({
        'Product': 'Sponsored Products',
        'Entity': 'Product Targeting' if is_target else 'Keyword',
        'Operation': 'Update',
        'Campaign ID': str(r['campaign_id']),
        'Ad Group ID': str(r['ad_group_id'] or ''),
        'Portfolio ID': str(r['echo_portfolio_id'] or ''),
        'Campaign Name (Informational only)': r['campaign_name'],
        'Bid': f"{new_bid:.2f}",
    })
    if is_target:
        row['Product Targeting ID'] = str(r['keyword_id'])
    else:
        row['Keyword ID'] = str(r['keyword_id'])
    return row


def sp_pause_row(r):
    row = {h: '' for h in SP_HEADERS}
    is_target = b(r['is_auto']) or b(r['is_pt'])
    row.update({
        'Product': 'Sponsored Products',
        'Entity': 'Product Targeting' if is_target else 'Keyword',
        'Operation': 'Update',
        'Campaign ID': str(r['campaign_id']),
        'Ad Group ID': str(r['ad_group_id'] or ''),
        'Portfolio ID': str(r['echo_portfolio_id'] or ''),
        'Campaign Name (Informational only)': r['campaign_name'],
        'State': 'PAUSED',
    })
    if is_target:
        row['Product Targeting ID'] = str(r['keyword_id'])
    else:
        row['Keyword ID'] = str(r['keyword_id'])
    return row


def sb_bid_row(r, new_bid):
    row = {h: '' for h in SB_HEADERS}
    row.update({
        'Product': 'Sponsored Brands',
        'Entity': 'Keyword',
        'Operation': 'Update',
        'Campaign Id': str(r['campaign_id']),
        'Ad Group Id': str(r['ad_group_id'] or ''),
        'Portfolio Id': str(r['echo_portfolio_id'] or ''),
        'Keyword Id': str(r['keyword_id']),
        'Bid': f"{new_bid:.2f}",
        # 'Campaign Name' on the SB sheet is a REAL column — left blank on purpose (the
        # README maps every row to its campaign); filling it would rename the campaign.
    })
    return row


def sb_pause_row(r):
    row = {h: '' for h in SB_HEADERS}
    row.update({
        'Product': 'Sponsored Brands',
        'Entity': 'Keyword',
        'Operation': 'Update',
        'Campaign Id': str(r['campaign_id']),
        'Ad Group Id': str(r['ad_group_id'] or ''),
        'Portfolio Id': str(r['echo_portfolio_id'] or ''),
        'Keyword Id': str(r['keyword_id']),
        'State': 'paused',
    })
    return row


def log_batch(rows, batch_id):
    """Log the executable rows to FACT_PPC_CHANGE_LOG the way the stop sheet's batch was
    logged (source MANUAL, coach_mode MANUAL_BULKSHEET), so the scorecard grades them."""
    structs = []
    for r, disp, new_bid in rows:
        action = ('KEYWORD_PAUSE' if disp == 'PAUSE'
                  else 'REDUCE_BID' if disp == 'BID_DOWN' else 'INCREASE_BID')
        old_bid = num(r['current_bid'])
        cid = str(r['campaign_id'])
        kid = str(r['keyword_id'])

        def q(s):
            return "'" + str(s).replace('\\', '\\\\').replace("'", "\\'") + "'" if s not in (None, '') else 'NULL'

        structs.append(
            "STRUCT("
            f"{q('reprice-' + batch_id.split('_')[-1] + '-' + cid + '-' + kid)} AS change_id, "
            f"{q(batch_id)} AS batch_id, CURRENT_TIMESTAMP() AS applied_at, "
            f"{q(action)} AS action, {q(r['target_text'])} AS targeting, "
            f"{q(kid)} AS keyword_id, {q(r['match_type'])} AS match_type, "
            f"{q(cid)} AS campaign_id, {q(r['campaign_name'])} AS campaign_name, "
            f"{q((r.get('campaign_type') or r.get('channel') or '').upper())} AS campaign_type, "
            f"{q(r['ad_group_id'])} AS ad_group_id, "
            f"{('CAST(' + repr(old_bid) + ' AS FLOAT64)') if old_bid is not None else 'NULL'} AS old_bid, "
            f"{('CAST(' + repr(new_bid) + ' AS FLOAT64)') if new_bid is not None else 'NULL'} AS new_bid, "
            f"{q('MANUAL')} AS source, {q('MANUAL_BULKSHEET')} AS coach_mode)"
        )
    sql = (
        f"INSERT INTO `{PROJECT}.OI.FACT_PPC_CHANGE_LOG` "
        f"(change_id, batch_id, applied_at, action, targeting, keyword_id, match_type, "
        f"campaign_id, campaign_name, campaign_type, ad_group_id, old_bid, new_bid, source, coach_mode) "
        f"SELECT change_id, batch_id, applied_at, action, targeting, keyword_id, match_type, "
        f"campaign_id, campaign_name, campaign_type, ad_group_id, old_bid, new_bid, source, coach_mode "
        f"FROM UNNEST([{', '.join(structs)}])"
    )
    out = subprocess.run(
        ['bq', 'query', '--use_legacy_sql=false', '--nouse_cache', f'--project_id={PROJECT}', sql],
        capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"change-log insert failed:\n{out.stderr}")
    return batch_id


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('-o', '--out', default=f".tmp/reprice_book_{date.today():%Y%m%d}.xlsx")
    ap.add_argument('--no-log', action='store_true',
                    help='skip the FACT_PPC_CHANGE_LOG batch insert')
    args = ap.parse_args()
    os.makedirs(os.path.dirname(args.out) or '.', exist_ok=True)

    rows = bq(SQL.format(p=PROJECT))
    if not rows:
        print("No AT_BAR / REPRICE / LOSER keywords — the book is empty today.")
        return

    today_la = rows[0]['today_la']
    batch_id = f"reprice_book_{today_la.replace('-', '')}"

    executable = []   # (row, disposition, new_bid)
    visible = []      # every candidate with disposition + story
    holdout_hits = []
    for r in rows:
        disp, action, new_bid, check_first, bits = classify(r)
        st = story(r, disp, new_bid, bits)
        visible.append((r, disp, new_bid, check_first, bits, st))
        if disp in ('BID_DOWN', 'BID_UP', 'PAUSE'):
            executable.append((r, disp, new_bid))
        if disp == 'HOLDOUT_EXCLUDED':
            holdout_hits.append(r)

    # HOLDOUT ASSERTION — a hand upload into the holdout invalidates the trial.
    armed = sorted({r['holdout_eligible_from'] for r in rows if r['holdout_eligible_from']})
    for r, disp, new_bid in executable:
        assert not (r['holdout_eligible_from'] and today_la >= r['holdout_eligible_from']), \
            f"HOLDOUT VIOLATION: {r['campaign_name']} is in the holdout arm and eligible"
    print(f"HOLDOUT check: {len(holdout_hits)} row(s) excluded today; "
          f"exclusion armed from {armed[0] if armed else 'n/a'} "
          f"(today {today_la}).")

    sp_rows = [(r, d, nb) for r, d, nb in executable if (r.get('campaign_type') or r['channel']).upper() != 'SB']
    sb_rows = [(r, d, nb) for r, d, nb in executable if (r.get('campaign_type') or r['channel']).upper() == 'SB']

    # ---- workbook -------------------------------------------------------------------
    wb = openpyxl.Workbook()
    wb.remove(wb.active)
    line_of = {}
    if sp_rows:
        ws = wb.create_sheet(SP_SHEET)
        ws.append(SP_HEADERS)
        for i, (r, d, nb) in enumerate(sp_rows, start=2):
            ws.append([(sp_pause_row(r) if d == 'PAUSE' else sp_bid_row(r, nb))[h] for h in SP_HEADERS])
            line_of[(r['campaign_id'], r['keyword_id'])] = (SP_SHEET, i)
    if sb_rows:
        ws = wb.create_sheet(SB_SHEET)
        ws.append(SB_HEADERS)
        for i, (r, d, nb) in enumerate(sb_rows, start=2):
            ws.append([(sb_pause_row(r) if d == 'PAUSE' else sb_bid_row(r, nb))[h] for h in SB_HEADERS])
            line_of[(r['campaign_id'], r['keyword_id'])] = (SB_SHEET, i)
    wb.save(args.out)

    # ---- audit csv (every candidate row, executable or not) -------------------------
    audit_path = args.out.rsplit('.', 1)[0] + '_audit.csv'
    with open(audit_path, 'w', newline='') as f:
        wr = csv.writer(f)
        wr.writerow(['sheet', 'excel_row', 'disposition', 'check_first', 'state', 'family',
                     'campaign_id', 'campaign', 'ad_group_id', 'keyword_id', 'target', 'match',
                     'channel', 'is_auto', 'is_pt', 'portfolio_id', 'portfolio',
                     'family_bar', 'roas90_used', 'orders90', 'nf_orders', 'se_eff',
                     'settled_cpc_used', 'affordable_cpc', 'm_effective',
                     'old_bid', 'new_bid', 'guard_deferred',
                     'live_7d_spend_CONTEXT_ONLY', 'live_7d_cpc_CONTEXT_ONLY',
                     'story'])
        for r, disp, new_bid, check_first, bits, st in visible:
            sheet, ln = line_of.get((r['campaign_id'], r['keyword_id']), ('', ''))
            clk7 = num(r['clk7'], 0)
            wr.writerow([
                sheet, ln, disp, 'CHECK FIRST' if (check_first and disp in ('BID_DOWN', 'BID_UP', 'PAUSE')) else '',
                r['state'], r['family'], r['campaign_id'], r['campaign_name'],
                r['ad_group_id'], r['keyword_id'], r['target_text'], r['match_type'],
                r['channel'], r['is_auto'], r['is_pt'],
                r['echo_portfolio_id'], r.get('portfolio_name') or '',
                f"{num(r['family_bar'], 1.0):.4f}",
                f"{(bits['roas_used'] or 0):.3f}", int(num(r['settled_ord90'], 0)),
                r['nf_orders'] or '', f"{num(r['se_eff'], 0):.3f}" if r['se_eff'] not in (None, '') else '',
                f"{(bits['cpc_settled'] or 0):.2f}",
                f"{(bits['afford'] or 0):.2f}" if bits['afford'] is not None else '',
                f"{bits['m_eff']:.3f}",
                f"{num(r['current_bid'], 0):.2f}", f"{new_bid:.2f}" if new_bid else '',
                'yes' if bits['guard'] else '',
                f"{num(r['sp7'], 0):.2f}",
                f"{(num(r['sp7'], 0) / clk7):.2f}" if clk7 else '',
                st])

    # ---- plain-English readme -------------------------------------------------------
    n_down = sum(1 for _, d, _ in executable if d == 'BID_DOWN')
    n_up = sum(1 for _, d, _ in executable if d == 'BID_UP')
    n_pause = sum(1 for _, d, _ in executable if d == 'PAUSE')
    bid_down_total = sum(num(r['current_bid'], 0) - nb for r, d, nb in executable if d == 'BID_DOWN')
    bid_up_total = sum(nb - num(r['current_bid'], 0) for r, d, nb in executable if d == 'BID_UP')
    down_spend7 = sum(num(r['sp7'], 0) for r, d, _ in executable if d in ('BID_DOWN', 'PAUSE'))
    up_spend7 = sum(num(r['sp7'], 0) for r, d, _ in executable if d == 'BID_UP')
    blocked = [(r, st) for r, disp, nb, cf, bits, st in visible if disp == 'SEASON_BLOCKED']
    check_rows = [(r, disp, nb, st) for r, disp, nb, cf, bits, st in visible
                  if cf and disp in ('BID_DOWN', 'BID_UP', 'PAUSE')]

    readme_path = args.out.rsplit('.', 1)[0] + '_README.md'
    with open(readme_path, 'w') as f:
        f.write("# The reprice book — what each row does and why\n\n")
        f.write(f"Built {datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC} from `{args.out}` "
                f"(ads watermark {rows[0]['watermark']}, states of {today_la}).\n\n")
        f.write("Every price here is the keyword's own settled 90-day evidence divided by its "
                "family's bar, then translated to a bid through the campaign's measured "
                "placement multiplier. The 7-day figures in the audit are context only — no "
                "verdict and no price reads them.\n\n")
        f.write(f"**{len(executable)} executable rows**: {n_down} bid-downs, {n_up} bid-ups, "
                f"{n_pause} pauses. Bid-space totals: −${bid_down_total:.2f} across the downs, "
                f"+${bid_up_total:.2f} across the ups (these are bid deltas, not spend "
                f"forecasts — a per-day dollar effect from a bid move would be invented "
                f"precision). The rows being cut or paused spent ${down_spend7:.2f} in the "
                f"last 7 days; the rows being raised spent ${up_spend7:.2f}.\n\n")
        f.write("Every row echoes its campaign's portfolio (a blank portfolio cell detaches a "
                "campaign; uniform echo keeps the convention safe). Pauses are reversible with "
                "one enabled row; the restore sheet next to this file carries every old value "
                "back.\n\n")
        f.write(f"The batch is logged as `{batch_id}` in the change log so the scorecard "
                f"grades it. **If you do not upload this book, mark the batch FAILED_UPLOAD** — "
                f"otherwise the outcome scoring will grade moves that never happened. If you "
                f"delete individual lines before uploading, mark those rows FAILED_UPLOAD "
                f"too.\n\n")
        if armed:
            f.write(f"Holdout interlock: campaigns in the HOLDOUT arm are excluded from this "
                    f"book from {armed[0]}; today that excluded {len(holdout_hits)} row(s). A "
                    f"hand upload into the holdout invalidates the trial.\n\n")
        if check_rows:
            f.write("---\n\n## CHECK FIRST — eyeball these before uploading\n\n")
            for r, disp, nb, st in check_rows:
                sheet, ln = line_of.get((r['campaign_id'], r['keyword_id']), ('not in sheet', ''))
                f.write(f"- **{sheet} row {ln}** — `{r['target_text']}` in {r['campaign_name']}: {st}\n")
            f.write("\n")
        if blocked:
            f.write("---\n\n## Blocked by the season ledger — shown, not executed\n\n")
            for r, st in blocked:
                f.write(f"- `{r['target_text']}` in {r['campaign_name']}: {st}\n")
            f.write("\n")
        f.write("---\n\n## Row by row\n\n")
        for r, disp, nb, cf, bits, st in visible:
            if disp not in ('BID_DOWN', 'BID_UP', 'PAUSE'):
                continue
            sheet, ln = line_of[(r['campaign_id'], r['keyword_id'])]
            f.write(f"### {sheet} — row {ln}: `{r['target_text']}` ({r['campaign_name']})\n\n")
            f.write(f"- {st}\n")
            f.write(f"- Delete this line and `{r['target_text']}` keeps its current bid/state; "
                    f"nothing else in the sheet changes — then mark its change-log row "
                    f"FAILED_UPLOAD.\n\n")
        others = [(r, disp, st) for r, disp, nb, cf, bits, st in visible
                  if disp not in ('BID_DOWN', 'BID_UP', 'PAUSE', 'SEASON_BLOCKED')]
        if others:
            f.write("---\n\n## Candidates with no executable row (audit visibility)\n\n")
            for r, disp, st in others:
                f.write(f"- `{r['target_text']}` ({r['campaign_name']}) — {disp}: {st}\n")

    # ---- review table ---------------------------------------------------------------
    print(f"\n{len(rows)} candidate rows -> {len(executable)} executable "
          f"({n_down} down · {n_up} up · {n_pause} pause) · "
          f"{len(blocked)} season-blocked · {len(rows) - len(executable) - len(blocked)} other\n")
    hdr = f"{'target':<34} {'campaign':<38} {'st':<7} {'old':>5} {'new':>5}  disposition"
    print(hdr)
    print('-' * len(hdr))
    for r, disp, nb, cf, bits, st in visible:
        mark = ' *CHECK FIRST*' if (cf and disp in ('BID_DOWN', 'BID_UP', 'PAUSE')) else ''
        print(f"{(r['target_text'] or '')[:33]:<34} {(r['campaign_name'] or '')[:37]:<38} "
              f"{r['state'][:7]:<7} {num(r['current_bid'], 0):>5.2f} "
              f"{(f'{nb:.2f}' if nb else ('PAUSE' if disp == 'PAUSE' else '-')):>5}  {disp}{mark}")

    # ---- change log -----------------------------------------------------------------
    logged = ''
    if executable and not args.no_log:
        logged = log_batch(executable, batch_id)
        print(f"\nLogged {len(executable)} rows to FACT_PPC_CHANGE_LOG as batch {logged} "
              f"(mark FAILED_UPLOAD if the book is not uploaded).")

    stamp = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')
    print(f"\n[{stamp}] wrote {len(executable)} rows -> {args.out}")
    print(f"  audit  -> {audit_path}")
    print(f"  readme -> {readme_path}")
    print(f"  bid-space: -${bid_down_total:.2f} (downs) · +${bid_up_total:.2f} (ups); "
          f"7d spend on cut/paused rows ${down_spend7:.2f}")
    print("  PREPARE-ONLY: read the README, delete any line you disagree with, then upload "
          "to Amazon Ads > Bulk operations manually. Build the restore sheet with "
          "tools/build_restore_reprice_bulksheet.py --audit " + audit_path)
    return {
        'out': args.out, 'audit': audit_path, 'readme': readme_path,
        'rows': len(executable), 'batch': logged,
    }


if __name__ == '__main__':
    main()
