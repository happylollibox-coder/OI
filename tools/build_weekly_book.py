#!/usr/bin/env python3
"""THE WEEKLY BOOK — one book, every action, each row explained top-down.

SOP: architecture/WEEKLY_BOOK.md. Doctrine: architecture/THREE_LAYERS.md (§1.1, §9).

WHAT THIS IS. An ASSEMBLER, not a decision-maker. It changes none of the nine existing builders and
decides nothing of its own: it runs the sources with --no-log, reads the workbooks and audit CSVs they
already write, merges them into one workbook, resolves conflicts under a declared precedence, and
writes ONE change-log batch. Every number in it was decided by a source tonight.

WHY IT EXISTS. Nine books meant no single thing to review, no conflict detection at all (nothing
stopped the reprice book raising a bid on a keyword the seat book was parking — it had never been
checked), and a flat explanation that never said WHICH LAYER decided what.

THE JOIN. Every source audit CSV starts with the same two columns, `sheet` and `excel_row`, which is
exactly the coordinate of the row it produced in its own workbook. That is what lets this file pair a
row's evidence with its Amazon cells without importing a line of any source's decision logic.

PRECEDENCE (SOP §3): CATALOG > BRAIN > PACING, loser DROPPED not blended, and never silent — every
drop lands on the Conflicts sheet with both actions and both explanations.

IT DOES NOT UPLOAD. Ori uploads, always.
"""

import argparse
import csv
import json
import os
import subprocess
import sys
from collections import defaultdict
from datetime import date, datetime, timezone

import openpyxl

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_stop_nonconverting_bulksheet import (  # noqa: E402
    SP_HEADERS, SB_HEADERS, SP_SHEET, SB_SHEET)
from build_reprice_bulksheet import q, num  # noqa: E402

PROJECT = "onyga-482313"
HOUSE_PYTHON = "/usr/bin/python3"
LIVE_CHANGE_LOG = "FACT_PPC_CHANGE_LOG"
CHANGE_LOG = f"{PROJECT}.OI.{LIVE_CHANGE_LOG}"
PLAN = f"{PROJECT}.OI.FACT_PLAN_NEXT_WEEK"

CATALOG, BRAIN, PACING = 'CATALOG', 'BRAIN', 'PACING'
TIER_RANK = {CATALOG: 0, BRAIN: 1, PACING: 2}   # lower wins

# THE TIER OF A ROW IS THE TIER THAT DECIDED IT, NOT THE ONE THAT EXECUTES IT (SOP §2). A keyword
# pause at the end of probation is executed by Pacing but DECIDED by the ladder's LOSER verdict, so
# it is a CATALOG row: the question it answers is "is this worth having", which is the Catalog's.
# Reading it as Pacing would put a worth verdict in the layer that is forbidden to make one (§1.1).
REPRICE_TIER = {
    'BID_UP': PACING, 'BID_DOWN': PACING,
    'PAUSE': CATALOG,
}
# An action's kind is what it DOES, independent of which module built it — which is what lets one
# explanation branch serve every source and stops the tiers parroting each other.
BID_MOVE, KEYWORD_PAUSE, NEGATE, PARK, SEAT_MOVE, BUDGET = (
    'BID_MOVE', 'KEYWORD_PAUSE', 'NEGATE', 'PARK', 'SEAT_MOVE', 'BUDGET')

# Most of what the seat book emits is a CATALOG verdict, not a Brain one: dead, parked and negated
# all answer "is this worth having", which is the Catalog's question. The Brain's own rows are the
# ones that move MONEY between subjects — budgets and seat reassignment.
KIND_TIER = {
    BID_MOVE: PACING, KEYWORD_PAUSE: CATALOG, NEGATE: CATALOG, PARK: CATALOG,
    SEAT_MOVE: BRAIN, BUDGET: BRAIN,
}


def bq(sql, fmt='json'):
    out = subprocess.run(
        ['bq', 'query', f'--project_id={PROJECT}', '--use_legacy_sql=false', '--nouse_cache',
         f'--format={fmt}', sql],
        capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"query failed:\n{out.stderr}")
    return json.loads(out.stdout) if fmt == 'json' and out.stdout.strip() else []


# ---------------------------------------------------------------------------------------------
# 1. Run the sources. --no-log ALWAYS: this file writes the one batch, so a source that logged its
#    own would double-count the same change under two batch ids and make the log unreadable.
# ---------------------------------------------------------------------------------------------

def run_source(name, script, extra_args, stage_dir):
    out_path = os.path.join(stage_dir, f"{name}.xlsx")
    cmd = [HOUSE_PYTHON, script, '--no-log', '-o', out_path] + list(extra_args)
    print(f"  running {name} ...", flush=True)
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        return {'name': name, 'ok': False, 'error': (res.stderr or res.stdout)[-1500:],
                'out': out_path, 'audit': None}
    audit = out_path.rsplit('.', 1)[0] + '_audit.csv'
    return {'name': name, 'ok': True, 'error': None, 'out': out_path,
            'audit': audit if os.path.exists(audit) else None}


def read_source(src):
    """Pair every audit row with the Amazon cells it produced, on (sheet, excel_row).

    A row with no sheet coordinate is a CANDIDATE the source considered and refused — season
    blocked, holdout, engine-instructed, rule B on the good side. Those are kept and routed to the
    Refused sheet rather than dropped, because a refusal is a decision about money and an absence
    reads as an oversight (SOP §5)."""
    if not src['audit'] or not os.path.exists(src['out']):
        return [], []
    wb = openpyxl.load_workbook(src['out'])
    cells = {}
    for sheet in wb.sheetnames:
        ws = wb[sheet]
        headers = [c.value for c in ws[1]]
        for i, row in enumerate(ws.iter_rows(min_row=2, values_only=True), start=2):
            cells[(sheet, i)] = dict(zip(headers, row))
    executable, refused = [], []
    with open(src['audit'], newline='') as f:
        for a in csv.DictReader(f):
            sheet, xr = (a.get('sheet') or '').strip(), (a.get('excel_row') or '').strip()
            key = (sheet, int(xr)) if sheet and xr.isdigit() else None
            rec = {'source': src['name'], 'audit': a, 'cells': cells.get(key) if key else None,
                   'sheet': sheet or None}
            (executable if rec['cells'] else refused).append(rec)
    return executable, refused


# ---------------------------------------------------------------------------------------------
# 2. The Brain's own rows: campaign budgets the plan wants changed. No source module emits these
#    today, which is why the Brain tier was invisible in every book the account has ever built.
# ---------------------------------------------------------------------------------------------

BUDGET_SQL = f"""
WITH latest AS (
  SELECT * FROM `{PLAN}`
  WHERE DATE(built_at) = (SELECT MAX(DATE(built_at)) FROM `{PLAN}`)
    AND plan = @PLANARM@
),
per_campaign AS (
  SELECT
    CAST(campaign_id AS STRING) AS campaign_id,
    ANY_VALUE(campaign_name)    AS campaign_name,
    ANY_VALUE(family)           AS family,
    MAX(campaign_planned_budget) AS planned_budget,
    MAX(campaign_current_budget) AS current_budget,
    MAX(campaign_budget_basis)   AS basis,
    MAX(pot_per_day)             AS pot_per_day,
    MAX(allowance_ramped_per_day) AS allowance_per_day,
    MAX(allowance_share)         AS allowance_share,
    LOGICAL_OR(IFNULL(holdout, FALSE)) AS holdout,
    MAX(campaign_visible_spend_per_day) AS visible_spend_per_day
  FROM latest
  WHERE campaign_id IS NOT NULL
  GROUP BY campaign_id
)
SELECT c.*, d.campaign_type, d.state AS campaign_state, d.portfolio_id
FROM per_campaign c
LEFT JOIN (SELECT CAST(campaign_id AS STRING) AS campaign_id, campaign_type, state, portfolio_id
           FROM `{PROJECT}.OI.DIM_CAMPAIGN` WHERE is_current) d USING (campaign_id)
-- BLANK IS NOT "UNCHANGED" ON A CAMPAIGN UPDATE ROW — it DETACHES the campaign from its portfolio.
-- DIM_CAMPAIGN.portfolio_id is NULL for a campaign that is detached RIGHT NOW, so echoing it would
-- silently make a temporary detachment permanent. The echo is the last non-null portfolio the
-- campaign has EVER carried, read from campaign history exactly as build_stop_nonconverting does.
-- Measured before this fix: 3 of 42 budget rows carried a blank and would have detached.
LEFT JOIN (SELECT CAST(campaign_id AS STRING) AS campaign_id,
                  ARRAY_AGG(portfolio_id IGNORE NULLS ORDER BY date DESC LIMIT 1)[SAFE_OFFSET(0)]
                    AS echo_portfolio_id
           FROM `{PROJECT}.OI.V_SRC_AmazonAds_campaign_history`
           GROUP BY campaign_id) e USING (campaign_id)
WHERE c.planned_budget IS NOT NULL AND c.current_budget IS NOT NULL
  AND ABS(c.planned_budget - c.current_budget) > 0.005
  AND NOT c.holdout
  AND d.state = 'ENABLED'
ORDER BY ABS(c.planned_budget - c.current_budget) DESC
"""


def budget_rows(plan_arm):
    rows = bq(BUDGET_SQL.replace('@PLANARM@', q(plan_arm)))
    out = []
    for r in rows:
        is_sb = (r.get('campaign_type') or '').upper() == 'SB'
        # The live value if there is one, else the last one ever seen. Only genuinely blank when
        # the campaign has never belonged to a portfolio, in which case a blank detaches nothing.
        echo = r.get('portfolio_id') or r.get('echo_portfolio_id') or ''
        never_had = not (r.get('portfolio_id') or r.get('echo_portfolio_id'))
        new_b, old_b = num(r['planned_budget']), num(r['current_budget'])
        if is_sb:
            cells = {h: '' for h in SB_HEADERS}
            cells.update({
                'Product': 'Sponsored Brands', 'Entity': 'Campaign', 'Operation': 'Update',
                'Campaign Id': str(r['campaign_id']),
                # BLANK IS NOT "UNCHANGED" ON A CAMPAIGN UPDATE ROW — a blank Portfolio Id DETACHES
                # the campaign from its portfolio. The last non-null portfolio is echoed back.
                'Portfolio Id': str(echo),
                'Budget': f"{new_b:.2f}",
                # 'Campaign Name' is a REAL column on the SB sheet: filling it would RENAME the
                # campaign to whatever the warehouse held at build time. Left blank on purpose.
            })
            sheet = SB_SHEET
        else:
            cells = {h: '' for h in SP_HEADERS}
            cells.update({
                'Product': 'Sponsored Products', 'Entity': 'Campaign', 'Operation': 'Update',
                'Campaign ID': str(r['campaign_id']),
                'Portfolio ID': str(echo),
                'Daily Budget': f"{new_b:.2f}",
                'Campaign Name (Informational only)': r.get('campaign_name') or '',
            })
            sheet = SP_SHEET
        out.append({
            'source': 'plan-budgets', 'sheet': sheet, 'cells': cells,
            'audit': {
                'disposition': 'BUDGET_UP' if new_b > old_b else 'BUDGET_DOWN',
                'campaign_id': str(r['campaign_id']), 'campaign': r.get('campaign_name') or '',
                'keyword_id': '', 'target': '(whole campaign)',
                'family': r.get('family') or '', 'old_bid': '', 'new_bid': '',
                '_old_budget': old_b, '_new_budget': new_b,
                '_basis': r.get('basis') or '', '_pot': num(r.get('pot_per_day')),
                '_allowance': num(r.get('allowance_per_day')),
                '_share': num(r.get('allowance_share')),
                '_visible_spend': num(r.get('visible_spend_per_day')),
                '_never_had_portfolio': never_had,
            }})
    return out


# ---------------------------------------------------------------------------------------------
# 3. The explanation — three sentences, in decision order, never abbreviated (SOP §4).
#    Nothing here is invented: it is the evidence the sources already carry, re-routed into the
#    tier that produced it. A tier with nothing to say SAYS SO, because a missing sentence reads
#    as an oversight and an explicit refusal reads as the fact it is.
# ---------------------------------------------------------------------------------------------

def _f(v, default=None):
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def explain(rec):
    a, src = rec['audit'], rec['source']
    subj = a.get('target') or '(unnamed)'
    fam = a.get('family') or 'unmapped'

    if src == 'plan-budgets':
        cat = (f"The Catalog is not asked about a campaign — it has no verdict for one (§4.1, "
               f"violation 22 still open), so nothing here is a statement that this campaign is "
               f"worth its budget. What the family bar governs is the keywords inside it.")
        old_b, new_b = a['_old_budget'], a['_new_budget']
        direction = 'raises' if new_b > old_b else 'lowers'
        brain = (f"The Brain {direction} {fam}'s campaign budget from ${old_b:.2f} to ${new_b:.2f} a "
                 f"day. The pot is ${a['_pot']:.2f}/day and the ramped allowance ${a['_allowance']:.2f}"
                 f"/day at a {a['_share']:.2f} share; the campaign is visibly spending "
                 f"${a['_visible_spend']:.2f}/day today. Basis: {a['_basis'] or 'not stated'}.")
        pace = (f"Pacing is not consulted on a budget — a budget is a ceiling on the day, not a "
                f"price in an auction. Bids inside this campaign are unchanged by this row.")
        return cat, brain, pace

    if src == 'reprice':
        bar, roas = _f(a.get('family_bar')), _f(a.get('roas90_used'))
        orders, side = a.get('orders90'), (a.get('bar_side') or '').lower()
        floor, floor_src = _f(a.get('bid_floor')), a.get('bid_floor_source') or 'unstated'
        cat = (f"The Catalog values '{subj}' on its settled 90-day record: "
               f"{(roas if roas is not None else 0):.2f} gross-profit dollars per ad dollar against "
               f"the {fam} bar of {(bar if bar is not None else 0):.2f}"
               + (f" — {side} the bar" if side else "")
               + f" on {orders or 0} settled orders. Its floor is "
               + (f"${floor:.2f} ({floor_src})." if floor is not None else f"unset ({floor_src})."))
        verdict = a.get('rule_b_verdict') or ''
        rb_ret, rb_bar = _f(a.get('rule_b_return')), _f(a.get('rule_b_bar'))
        if verdict:
            brain = (f"The Brain judged the window as well: {verdict}"
                     + (f", returning {rb_ret:.2f} against a {rb_bar:.2f} bar"
                        if rb_ret is not None and rb_bar is not None else "")
                     + f" over {a.get('rule_b_window') or 'the plan window'}"
                     + (f" on {a.get('rule_b_orders')} orders." if a.get('rule_b_orders') else "."))
        else:
            brain = (f"The Brain did not rule on this row — it carries no window verdict, so the "
                     f"funding question was never reached and this is a price change inside money "
                     f"the subject already has.")
        old_bid, new_bid = _f(a.get('old_bid')), _f(a.get('new_bid'))
        disp = a.get('disposition') or ''
        if disp == 'PAUSE':
            pace = (f"Pacing executes a pause: '{subj}' has finished its probation at the floor and "
                    f"stops taking clicks. This is the ladder's verdict being carried out, not a "
                    f"price Pacing chose.")
        elif old_bid is not None and new_bid is not None:
            pct = (new_bid / old_bid - 1) * 100 if old_bid else 0
            cap = a.get('cap_applied')
            pace = (f"Pacing moves the bid ${old_bid:.2f} → ${new_bid:.2f} ({pct:+.1f}%)"
                    + (f", bound by the move cap." if cap in ('1', 'True', 'true', True)
                       else ".")
                    + (f" An engine instruction was present ({a.get('engine_instruction')}) and the "
                       f"book yielded." if a.get('engine_instruction') else ""))
        else:
            pace = "Pacing records no bid change on this row."
        return cat, brain, pace

    # Everything the seat book emits. Branch on WHAT THE ROW DOES, not which module built it, so
    # each tier says something distinct and true — the earlier shape had the Brain repeat the
    # Catalog's sentence verbatim, which is exactly the "missing sentence" failure SOP §4 forbids,
    # only louder: a tier that parrots the one above it looks like agreement and is really silence.
    kind = action_kind(rec)
    reason = (a.get('reason') or '').strip()
    # The source's reason already ends in its own "=> do this" clause. That clause is the ACTION and
    # belongs to Pacing's sentence, not the Catalog's evidence — keeping it here is what made the
    # Catalog appear to be issuing a command (§1.1 forbids exactly that).
    evidence = reason.split('=>')[0].strip().rstrip('-').strip() or 'no reason recorded'
    clk, ordn = a.get('settled_clk90') or 0, a.get('settled_ord90') or 0
    per_day = _f(a.get('cost_per_day'), 0) or 0.0
    ladder = a.get('ladder_state') or ''
    nxt = a.get('next_check_date') or ''

    cat = (f"The Catalog's verdict on '{subj}': {evidence}. Its settled 90-day record is "
           f"{clk} clicks and {ordn} orders"
           + (f", and the ladder holds it as {ladder}." if ladder else "."))

    if kind == NEGATE:
        brain = (f"The Brain funds nothing here — a blocked term takes no seat, and the "
                 f"${per_day:.2f}/day it was absorbing returns to {fam}'s pot.")
        pace = (f"Pacing has no bid to set: a negative removes '{subj}' from the auction rather "
                f"than pricing it, so there is no price for Pacing to choose.")
    elif kind == KEYWORD_PAUSE:
        brain = (f"The Brain holds no seat for a subject the Catalog has called {ladder or 'dead'} — "
                 f"the ${per_day:.2f}/day it was taking returns to {fam}'s pot and funds a question "
                 f"that can still be answered."
                 + ("" if nxt else " It carries no re-check date: nothing is testing it and "
                                   "nothing is pending."))
        pace = (f"Pacing stops bidding — '{subj}' is paused Amazon-side and takes no further "
                f"clicks. This is the ladder's verdict being carried out, not a price Pacing chose.")
    elif kind == PARK:
        park_price, park_src = _f(a.get('park_price')), a.get('park_price_source') or 'unstated'
        brain = (f"The Brain gives '{subj}' no seat this window — ${per_day:.2f}/day returns to "
                 f"{fam}'s pot. A park is not a verdict of never: it owes a re-test"
                 + (f", due {nxt}." if nxt else ", and it carries no date, which is the defect "
                                                "violation 14 names."))
        pace = (f"Pacing holds it at its park price"
                + (f" of ${park_price:.2f} ({park_src})" if park_price is not None else "")
                + f" rather than bidding for it: the subject stays alive and takes no clicks until "
                  f"something deliberately buys it evidence again.")
    else:
        brain = (f"The Brain moves the seat: ${per_day:.2f}/day was going to '{subj}' and is "
                 f"reallocated inside {fam}. {evidence}.")
        pace = (f"Pacing executes the move at the price the seat carries; it chose neither the "
                f"subject nor the amount.")
    return cat, brain, pace


def action_kind(rec):
    """What the row DOES. Decided from the source's own audit fields, never guessed."""
    a, src = rec['audit'], rec['source']
    disp = (a.get('disposition') or '').upper()
    kind = (a.get('kind') or '').upper()
    if src == 'plan-budgets':
        return BUDGET
    if kind.startswith('NEG') or disp.startswith('NEG'):
        return NEGATE
    if disp in ('PARK', 'UNPARK') or (a.get('new_state') or '').upper() == 'PARKED':
        return PARK
    if disp == 'PAUSE':
        return KEYWORD_PAUSE
    if src == 'reprice' and disp in ('BID_UP', 'BID_DOWN'):
        return BID_MOVE
    return SEAT_MOVE


def tier_of(rec):
    return KIND_TIER.get(action_kind(rec), CATALOG)


def subject_key(rec):
    """What two rows must share to be in conflict. A campaign-grain row conflicts only with another
    campaign-grain row: a budget and a bid on a keyword INSIDE it are not a contradiction, they are
    the two layers doing their own jobs, which is the whole point of the doctrine."""
    a = rec['audit']
    cid = str(a.get('campaign_id') or '')
    kid = str(a.get('keyword_id') or '')
    return (cid, kid) if kid else (cid, '__CAMPAIGN__')


def resolve(records):
    """Higher tier wins; loser dropped, never blended, never silent (SOP §3)."""
    by_subject = defaultdict(list)
    for r in records:
        by_subject[subject_key(r)].append(r)
    kept, conflicts = [], []
    for key, group in by_subject.items():
        if len(group) == 1:
            kept.append(group[0])
            continue
        group.sort(key=lambda r: TIER_RANK[tier_of(r)])
        winner, losers = group[0], group[1:]
        # Two rows from the SAME tier are not a precedence question — the doctrine has nothing to
        # say about it and guessing would be inventing a decision. Keep both and flag it loudly.
        same_tier = [l for l in losers if TIER_RANK[tier_of(l)] == TIER_RANK[tier_of(winner)]]
        kept.append(winner)
        for l in losers:
            conflicts.append({'winner': winner, 'loser': l, 'key': key,
                              'same_tier': l in same_tier})
            if l in same_tier:
                kept.append(l)
    return kept, conflicts


# ---------------------------------------------------------------------------------------------
# 4. The workbook. Only the two Amazon sheets are uploaded; the other three exist to be read.
# ---------------------------------------------------------------------------------------------

EXPLAINED_HEADERS = ['Row', 'Sheet', 'Tier', 'Source', 'Action', 'Family', 'Campaign',
                     'Campaign ID', 'Subject', 'Keyword ID', 'From', 'To',
                     'CATALOG says', 'BRAIN says', 'PACING says']
CONFLICT_HEADERS = ['Subject', 'Campaign', 'Kept tier', 'Kept action', 'Kept source',
                    'Dropped tier', 'Dropped action', 'Dropped source', 'Same tier?',
                    'Why the kept row wins', 'What the dropped row would have done']
REFUSED_HEADERS = ['Source', 'Tier', 'Disposition', 'Family', 'Campaign', 'Subject',
                   'Keyword ID', 'Why it was NOT executed']


def from_to(rec):
    a = rec['audit']
    if rec['source'] == 'plan-budgets':
        return f"${a['_old_budget']:.2f}/day", f"${a['_new_budget']:.2f}/day"
    ob, nb = _f(a.get('old_bid')), _f(a.get('new_bid'))
    disp = (a.get('disposition') or '').upper()
    if disp == 'PAUSE' or (a.get('kind') or '').upper().startswith('NEG'):
        return (f"${ob:.2f}" if ob is not None else ''), 'stopped'
    return (f"${ob:.2f}" if ob is not None else ''), (f"${nb:.2f}" if nb is not None else '')


# ---------------------------------------------------------------------------------------------
# PREFLIGHT — the checks that stop a known hazard shipping again. Each one exists because the
# account has actually been bitten by it, and each REFUSES rather than warns: a warning printed
# above a hundred lines of output is a warning nobody reads at 2am.
# ---------------------------------------------------------------------------------------------

def preflight(kept):
    problems = []
    for rec in kept:
        cells, a = rec['cells'], rec['audit']
        is_sb = rec['sheet'] == SB_SHEET
        who = f"{a.get('campaign') or a.get('campaign_id')} / {a.get('target') or '(campaign)'}"

        for col in ('Product', 'Entity', 'Operation'):
            if not str(cells.get(col) or '').strip():
                problems.append(f"{who}: empty '{col}' — Amazon rejects the line")

        # BLANK PORTFOLIO ON A CAMPAIGN UPDATE ROW DETACHES THE CAMPAIGN. Allowed only when the
        # campaign has never belonged to a portfolio, where a blank detaches nothing.
        if str(cells.get('Entity') or '') == 'Campaign':
            pcol = 'Portfolio Id' if is_sb else 'Portfolio ID'
            if not str(cells.get(pcol) or '').strip() and not a.get('_never_had_portfolio'):
                problems.append(f"{who}: blank {pcol} on a Campaign row would DETACH it from its "
                                f"portfolio")

        # 'Campaign Name' is a REAL column on the SB sheet: filling it RENAMES the campaign to
        # whatever the warehouse held at build time. It must always be blank.
        if is_sb and str(cells.get('Campaign Name') or '').strip():
            problems.append(f"{who}: SB 'Campaign Name' is filled — that RENAMES the campaign")

        # A bid row with no bid is a silent no-op that still consumes a change-log row.
        if str(cells.get('Entity') or '') in ('Keyword', 'Product Targeting'):
            if action_kind(rec) == BID_MOVE and not str(cells.get('Bid') or '').strip():
                problems.append(f"{who}: bid move with an empty Bid cell")

    if problems:
        sys.exit("PREFLIGHT REFUSED — the book was NOT written:\n  - " + "\n  - ".join(problems))
    return True


def write_book(path, kept, conflicts, refused):
    wb = openpyxl.Workbook()
    wb.remove(wb.active)
    ws_sp, ws_sb = wb.create_sheet(SP_SHEET), wb.create_sheet(SB_SHEET)
    ws_sp.append(SP_HEADERS)
    ws_sb.append(SB_HEADERS)
    line_of = {}
    # Deterministic order: tier first (Catalog, then Brain, then Pacing — the order the decision
    # was made in, which is the order §9 requires a reader to see it in), then campaign, then
    # subject. A stable order is what makes two builds of the same night diffable.
    kept = sorted(kept, key=lambda r: (TIER_RANK[tier_of(r)],
                                       str(r['audit'].get('campaign') or ''),
                                       str(r['audit'].get('target') or '')))
    for rec in kept:
        is_sb = rec['sheet'] == SB_SHEET
        ws, headers = (ws_sb, SB_HEADERS) if is_sb else (ws_sp, SP_HEADERS)
        ws.append([rec['cells'].get(h, '') for h in headers])
        line_of[id(rec)] = (SB_SHEET if is_sb else SP_SHEET, ws.max_row)

    ws_x = wb.create_sheet('Explained')
    ws_x.append(EXPLAINED_HEADERS)
    for rec in kept:
        a = rec['audit']
        sheet, rown = line_of[id(rec)]
        cat, brain, pace = explain(rec)
        frm, to = from_to(rec)
        ws_x.append([rown, 'SP' if sheet == SP_SHEET else 'SB', tier_of(rec), rec['source'],
                     a.get('disposition') or a.get('kind') or '', a.get('family') or '',
                     a.get('campaign') or '', a.get('campaign_id') or '',
                     a.get('target') or '', a.get('keyword_id') or '',
                     frm, to, cat, brain, pace])

    ws_c = wb.create_sheet('Conflicts')
    ws_c.append(CONFLICT_HEADERS)
    for c in conflicts:
        w, l = c['winner'], c['loser']
        wt, lt = tier_of(w), tier_of(l)
        why = (f"SAME TIER ({wt}) — the doctrine does not rank two rows from one tier, so BOTH were "
               f"kept and this needs a human ruling."
               if c['same_tier'] else
               f"{wt} outranks {lt}: a tier that says what a subject is worth has answered a "
               f"question the tier below never asked (SOP §3).")
        _, _, l_pace = explain(l)
        ws_c.append([l['audit'].get('target') or '', l['audit'].get('campaign') or '',
                     wt, w['audit'].get('disposition') or w['audit'].get('kind') or '', w['source'],
                     lt, l['audit'].get('disposition') or l['audit'].get('kind') or '', l['source'],
                     'YES' if c['same_tier'] else 'no', why, l_pace])

    ws_r = wb.create_sheet('Refused')
    ws_r.append(REFUSED_HEADERS)
    for rec in refused:
        a = rec['audit']
        ws_r.append([rec['source'], tier_of(rec), a.get('disposition') or '',
                     a.get('family') or '', a.get('campaign') or '', a.get('target') or '',
                     a.get('keyword_id') or '',
                     a.get('story') or a.get('reason') or a.get('engine_reason') or
                     'no reason recorded by the source'])

    for ws in (ws_x, ws_c, ws_r):
        for col, width in zip('ABCDEFGHIJKLMNO', (6, 6, 9, 14, 14, 11, 34, 18, 30, 18, 12, 12,
                                                  90, 90, 90)):
            ws.column_dimensions[col].width = width
        ws.freeze_panes = 'A2'
    wb.save(path)
    return line_of


# ---------------------------------------------------------------------------------------------
# 5. The change log. ONE batch for the whole book. PENDING_UPLOAD at build time and flipped by
#    --mark-uploaded, exactly as every other book: nothing has reached Amazon until Ori uploads.
#    A row is NEVER deleted, only labelled.
# ---------------------------------------------------------------------------------------------

ACTION_OF = {
    'BID_UP': 'INCREASE_BID', 'BID_DOWN': 'REDUCE_BID', 'PAUSE': 'KEYWORD_PAUSE',
    'BUDGET_UP': 'INCREASE_BUDGET', 'BUDGET_DOWN': 'REDUCE_BUDGET',
}


def log_action(rec):
    a, src = rec['audit'], rec['source']
    disp = (a.get('disposition') or '').upper()
    if disp in ACTION_OF:
        return ACTION_OF[disp]
    if (a.get('kind') or '').upper().startswith('NEG'):
        return 'NEGATE'
    return disp or 'SEAT_MOVE'


def log_batch(kept, batch_id, book_name, change_log):
    exists = bq(f"SELECT COUNT(*) n FROM `{change_log}` WHERE batch_id = {q(batch_id)}")
    assert int(exists[0]['n']) == 0, f"batch id {batch_id} already exists in the change log"
    note = (f"weekly book {batch_id}, built {datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC} from "
            f"{book_name}; ONE batch carrying every tier. Manual upload pending — if this book is "
            f"not uploaded set upload_status SUPERSEDED_NEVER_UPLOADED; if uploaded and a line was "
            f"deleted first, set that row FAILED_UPLOAD")
    structs, seen = [], set()
    for i, rec in enumerate(kept):
        a = rec['audit']
        cid, kid = str(a.get('campaign_id') or ''), str(a.get('keyword_id') or '')
        tier = tier_of(rec)
        change_id = f"weekly-{batch_id.split('_')[-1]}-{tier[:3]}-{cid}-{kid or 'CMP'}-{i}"
        assert change_id not in seen, f"duplicate change_id {change_id}"
        seen.add(change_id)
        ob, nb = _f(a.get('old_bid')), _f(a.get('new_bid'))
        if rec['source'] == 'plan-budgets':
            ob, nb = a['_old_budget'], a['_new_budget']
        structs.append(
            "STRUCT("
            f"{q(change_id)} AS change_id, {q(batch_id)} AS batch_id, "
            f"CURRENT_TIMESTAMP() AS applied_at, {q(log_action(rec))} AS action, "
            f"{q(a.get('target') or '')} AS targeting, {q(kid)} AS keyword_id, "
            f"{q(a.get('match') or '')} AS match_type, {q(cid)} AS campaign_id, "
            f"{q(a.get('campaign') or '')} AS campaign_name, "
            f"{q((a.get('channel') or a.get('campaign_type') or '').upper())} AS campaign_type, "
            f"{q(a.get('ad_group_id') or '')} AS ad_group_id, "
            f"{('CAST(' + repr(float(ob)) + ' AS FLOAT64)') if ob is not None else 'NULL'} AS old_bid, "
            f"{('CAST(' + repr(float(nb)) + ' AS FLOAT64)') if nb is not None else 'NULL'} AS new_bid, "
            # `source` carries the TIER and the module, so a later reader can ask "what did the
            # Brain do in August" without re-deriving it from the action verb (SOP §6).
            f"{q(tier + ':' + rec['source'])} AS source, "
            f"{q('MANUAL_BULKSHEET')} AS coach_mode, {q(note)} AS upload_note, "
            f"{q('PENDING_UPLOAD')} AS upload_status)")
    cols = ("change_id, batch_id, applied_at, action, targeting, keyword_id, match_type, "
            "campaign_id, campaign_name, campaign_type, ad_group_id, old_bid, new_bid, source, "
            "coach_mode, upload_note, upload_status")
    sql = (f"INSERT INTO `{change_log}` ({cols}) "
           f"SELECT {cols} FROM UNNEST([{', '.join(structs)}])")
    out = subprocess.run(
        ['bq', 'query', '--use_legacy_sql=false', '--nouse_cache', f'--project_id={PROJECT}', sql],
        capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"change-log insert failed:\n{out.stderr}")
    back = bq(f"SELECT COUNT(*) n FROM `{change_log}` WHERE batch_id = {q(batch_id)}")
    n = int(back[0]['n'])
    assert n == len(kept), f"logged {n} rows but the book holds {len(kept)}"
    return n


# ---------------------------------------------------------------------------------------------
# 6. The README — the thing Ori actually reads before uploading.
# ---------------------------------------------------------------------------------------------

def write_readme(path, book_name, batch_id, kept, conflicts, refused, sources, no_log):
    by_tier = defaultdict(list)
    for r in kept:
        by_tier[tier_of(r)].append(r)
    L = [f"# Weekly book — {batch_id}", "",
         f"Built {datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}. Workbook: `{book_name}`.",
         "SOP: `architecture/WEEKLY_BOOK.md`. Doctrine: `architecture/THREE_LAYERS.md`.", "",
         "**Nothing here has reached Amazon.** Upload the two Amazon sheets by hand, then run",
         f"`--mark-uploaded {batch_id}`. If you do not upload it, mark it",
         "`SUPERSEDED_NEVER_UPLOADED` — never delete a change-log row.", "",
         "## What is in it", "",
         "| tier | rows | what this tier decided |", "|---|---|---|"]
    for tier, what in ((CATALOG, "whether the subject is worth having at all"),
                       (BRAIN, "what it gets funded to do"),
                       (PACING, "what today's bid is")):
        L.append(f"| **{tier}** | {len(by_tier[tier])} | {what} |")
    L += [f"| | **{len(kept)}** | **executable rows** |", "",
          "Read the `Explained` sheet top to bottom: it is ordered Catalog → Brain → Pacing, which is",
          "the order the decision was made in. Every row carries three sentences and names the layer",
          "that produced each one, so if you disagree you know which layer to argue with.", ""]
    if conflicts:
        same = [c for c in conflicts if c['same_tier']]
        L += ["## Conflicts", "",
              f"{len(conflicts)} subject(s) were touched by more than one tier. Precedence is",
              "Catalog > Brain > Pacing and the loser's row was **dropped, not blended** — see the",
              "`Conflicts` sheet for both actions and both explanations.", ""]
        if same:
            L += [f"⚠️ **{len(same)} of them are SAME-TIER collisions**, where the doctrine has no",
                  "ranking and guessing would be inventing a decision. **Both rows were kept and",
                  "both are in the book.** Read those before uploading.", ""]
    else:
        L += ["## Conflicts", "",
              "None. No subject was touched by more than one tier this build.", ""]
    L += ["## Refused — money deliberately NOT moved", "",
          f"{len(refused)} candidate row(s) were built by a source and then refused: season-blocked,",
          "holdout arm, engine-instructed, or judged on the good side of the window. They are on the",
          "`Refused` sheet with the reason. A refusal is a decision about money; it is shown rather",
          "than omitted so it can be argued with.", "",
          "## Sources", "", "| source | status |", "|---|---|"]
    for s in sources:
        L.append(f"| `{s['name']}` | {'ok' if s['ok'] else '**FAILED — ' + (s['error'] or '')[:200] + '**'} |")
    L += ["", "## What this book does not do", "",
          "- It **decides nothing**. Every row was decided by a source module tonight; this file",
          "  merges, ranks and explains.",
          "- It does **not** implement §5's confidence gate — `confidence` is still not computed",
          "  (violation 20 open).",
          "- It does **not** re-open campaigns. Campaign state is yours by hand this season (§4.1).",
          "- It does **not** upload. You upload, always.", ""]
    if no_log:
        L += ["> **--no-log was used: no change-log batch was written.** This book is a draft and",
              "> must not be uploaded — an uploaded book with no logged batch is a change nothing",
              "> can attribute or restore.", ""]
    open(path, 'w').write("\n".join(L))


def build_parser():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('-o', '--out', default=f".tmp/weekly_book_{date.today():%Y%m%d}.xlsx")
    ap.add_argument('--plan', default='B', choices=['A', 'B'],
                    help="which plan arm's campaign budgets to carry (default B)")
    ap.add_argument('--no-log', action='store_true',
                    help="skip the change-log batch insert. The book is then a DRAFT and must not "
                         "be uploaded.")
    ap.add_argument('--no-budgets', action='store_true',
                    help="omit the Brain's campaign-budget rows (bids and Catalog actions only)")
    ap.add_argument('--change-log-table', default=None,
                    help="a TMP_/TEMP_ copy of FACT_PPC_CHANGE_LOG to act on instead of the live "
                         "table. Refused unless the name starts TMP_ or TEMP_.")
    return ap


def main():
    args = build_parser().parse_args()
    change_log = CHANGE_LOG
    if args.change_log_table:
        base = args.change_log_table.rsplit('.', 1)[-1]
        if not base.upper().startswith(('TMP_', 'TEMP_')):
            sys.exit(f"refusing --change-log-table {args.change_log_table}: must be a TMP_/TEMP_ copy")
        change_log = args.change_log_table if '.' in args.change_log_table \
            else f"{PROJECT}.OI.{args.change_log_table}"

    stage = os.path.join(os.path.dirname(args.out) or '.', '_weekly_stage')
    os.makedirs(stage, exist_ok=True)

    print("Assembling the weekly book. Sources run with --no-log; this file writes the one batch.")
    sources = [
        run_source('reprice', 'tools/build_reprice_bulksheet.py', ['--rule-b'], stage),
        run_source('seats', 'tools/build_seat_moves_bulksheet.py', [], stage),
    ]
    records, refused = [], []
    for s in sources:
        if not s['ok']:
            print(f"  !! {s['name']} FAILED — its rows are absent from this book:\n{s['error']}")
            continue
        ex, rf = read_source(s)
        records += ex
        refused += rf
        print(f"  {s['name']}: {len(ex)} executable, {len(rf)} refused")

    if not args.no_budgets:
        b = budget_rows(args.plan)
        records += b
        sources.append({'name': f'plan-budgets ({args.plan})', 'ok': True, 'error': None})
        print(f"  plan-budgets: {len(b)} campaign budget rows")

    if not records:
        sys.exit("no executable rows from any source — nothing to build")

    kept, conflicts = resolve(records)
    preflight(kept)
    print(f"\n  {len(kept)} rows kept, {len(conflicts)} conflict(s), {len(refused)} refused")

    batch_id = f"weekly_book_{datetime.now(timezone.utc):%Y%m%d_%H%M%S}"
    os.makedirs(os.path.dirname(args.out) or '.', exist_ok=True)
    write_book(args.out, kept, conflicts, refused)
    readme_path = args.out.rsplit('.', 1)[0] + '_README.md'
    write_readme(readme_path, os.path.basename(args.out), batch_id, kept, conflicts, refused,
                 sources, args.no_log)

    if args.no_log:
        print("  --no-log: NO change-log batch written. This book is a DRAFT; do not upload it.")
    else:
        n = log_batch(kept, batch_id, os.path.basename(args.out), change_log)
        print(f"  logged {n} rows as batch {batch_id} (PENDING_UPLOAD)")

    by_tier = defaultdict(int)
    for r in kept:
        by_tier[tier_of(r)] += 1
    print(f"\n  book   -> {args.out}")
    print(f"  readme -> {readme_path}")
    print(f"  tiers  -> CATALOG {by_tier[CATALOG]}, BRAIN {by_tier[BRAIN]}, "
          f"PACING {by_tier[PACING]}")
    if any(c['same_tier'] for c in conflicts):
        print("  ⚠️  SAME-TIER collisions are in the book and need a human ruling — see Conflicts.")
    return {'out': args.out, 'readme': readme_path, 'batch': batch_id, 'kept': len(kept)}


if __name__ == '__main__':
    main()
