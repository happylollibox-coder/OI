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
BID_MOVE, KEYWORD_PAUSE, NEGATE, PARK, SEAT_MOVE, BUDGET, MEND_TRIM = (
    'BID_MOVE', 'KEYWORD_PAUSE', 'NEGATE', 'PARK', 'SEAT_MOVE', 'BUDGET', 'MEND_TRIM')

# Most of what the seat book emits is a CATALOG verdict, not a Brain one: dead, parked and negated
# all answer "is this worth having", which is the Catalog's question. The Brain's own rows are the
# ones that move MONEY between subjects — budgets and seat reassignment.
KIND_TIER = {
    BID_MOVE: PACING, KEYWORD_PAUSE: CATALOG, NEGATE: CATALOG, PARK: CATALOG,
    SEAT_MOVE: BRAIN, BUDGET: BRAIN, MEND_TRIM: BRAIN,
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

def run_source(name, script, extra_args, stage_dir, reuse=False):
    out_path = os.path.join(stage_dir, f"{name}.xlsx")
    audit_path = out_path.rsplit('.', 1)[0] + '_audit.csv'
    # --reuse-stage: rebuild the BOOK from source output already on disk without re-running the
    # sources. They take minutes and hit BigQuery repeatedly, so iterating on the explanation or the
    # precedence should not mean re-deciding the account. The staged files are stamped in the README
    # so a reused build can never be mistaken for a fresh one.
    if reuse and os.path.exists(out_path) and os.path.exists(audit_path):
        age = datetime.now(timezone.utc) - datetime.fromtimestamp(
            os.path.getmtime(out_path), tz=timezone.utc)
        print(f"  reusing staged {name} ({age.total_seconds()/60:.0f} min old)", flush=True)
        return {'name': name, 'ok': True, 'error': None, 'out': out_path, 'audit': audit_path,
                'reused': True, 'staged_at': datetime.fromtimestamp(
                    os.path.getmtime(out_path), tz=timezone.utc)}
    cmd = [HOUSE_PYTHON, script, '--no-log', '-o', out_path] + list(extra_args)
    print(f"  running {name} ...", flush=True)
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        return {'name': name, 'ok': False, 'error': (res.stderr or res.stdout)[-1500:],
                'out': out_path, 'audit': None, 'reused': False}
    return {'name': name, 'ok': True, 'error': None, 'out': out_path,
            'audit': audit_path if os.path.exists(audit_path) else None, 'reused': False,
            'staged_at': datetime.now(timezone.utc)}


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
    MAX(campaign_visible_spend_per_day) AS visible_spend_per_day,
    -- A BUDGET IS A CEILING, NOT A SPEND (Ori, 2026-08-25). The plan publishes its own estimate of
    -- what each keyword's spend will actually do, and summing it per campaign is the only honest
    -- answer to "which way does this book point". Measured: across the 45 campaigns with budget
    -- changes, budgets move +$119.31/day while the plan expects spend to move -$41.27/day, because
    -- utilisation is 0.798 and most ceilings are not binding.
    SUM(planned_spend_delta_per_day)    AS planned_spend_delta_per_day
  FROM latest
  WHERE campaign_id IS NOT NULL
  GROUP BY campaign_id
)
SELECT c.*, d.campaign_type, d.state AS campaign_state, d.portfolio_id,
       np.net_profit_28d, np.spend_28d, np.gp_roas_28d,
       e.echo_portfolio_id,
       -- Whether the campaign was FOUND in history at all. Without this, a bug in the echo
       -- join (there was one: the column was joined and never selected) reads as "this
       -- campaign never had a portfolio" and preflight waves the blank through. An escape
       -- hatch keyed on a NULL cannot tell absence from breakage; this one is keyed on a
       -- fact the query asserts.
       e.campaign_id IS NOT NULL AS seen_in_history
FROM per_campaign c
LEFT JOIN (SELECT CAST(campaign_id AS STRING) AS campaign_id, campaign_type, state, portfolio_id
           FROM `{PROJECT}.OI.DIM_CAMPAIGN` WHERE is_current) d USING (campaign_id)
-- THE BRAIN'S JOB IS NET PROFIT DOLLARS PER CAMPAIGN (Ori, 2026-08-25). A campaign's own 28-day
-- profitability decides whether it may be GROWN at all: GROSS_PROFIT is sales minus landed COGS with
-- ad spend NOT subtracted, so net profit is gp - spend. Measured before this gate existed: EIGHT
-- campaigns were being handed +$209.91/day of extra ceiling while losing $1,659.54 over 28 days.
LEFT JOIN (SELECT CAST(campaign_id AS STRING) AS campaign_id,
                  SUM(GROSS_PROFIT) - SUM(Ads_cost) AS net_profit_28d,
                  SUM(Ads_cost)                     AS spend_28d,
                  SAFE_DIVIDE(SUM(GROSS_PROFIT), NULLIF(SUM(Ads_cost), 0)) AS gp_roas_28d
           FROM `{PROJECT}.OI.FACT_AMAZON_ADS`
           -- THE SAME SETTLED WINDOW THE MEND USES, ending 7 days back. The first cut measured to
           -- the watermark while the mend measured to watermark-7, and a campaign can be profitable
           -- on one and losing on the other — which put both claims in ONE sentence: "made $31.45,
           -- so it may be grown" immediately followed by "a losing campaign is capped while it is
           -- fixed". Two windows is two opinions; the gate and the mend must share one.
           WHERE date BETWEEN DATE_SUB((SELECT MAX(date) FROM `{PROJECT}.OI.FACT_AMAZON_ADS`),
                                       INTERVAL 34 DAY)
                          AND DATE_SUB((SELECT MAX(date) FROM `{PROJECT}.OI.FACT_AMAZON_ADS`),
                                       INTERVAL 7 DAY)
           GROUP BY 1) np USING (campaign_id)
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
        # A blank is only safe when history was actually consulted AND it holds no portfolio.
        never_had = bool(r.get('seen_in_history')) and not echo
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
                '_spend_delta': num(r.get('planned_spend_delta_per_day')),
                '_utilisation': (num(r.get('visible_spend_per_day')) / old_b) if old_b else None,
                '_net_profit_28d': num(r.get('net_profit_28d')),
                '_spend_28d': num(r.get('spend_28d')),
                '_gp_roas_28d': num(r.get('gp_roas_28d')),
                '_never_had_portfolio': never_had,
            }})
    return out


# ---------------------------------------------------------------------------------------------
# 3. The explanation — three sentences, in decision order, never abbreviated (SOP §4).
#    Nothing here is invented: it is the evidence the sources already carry, re-routed into the
#    tier that produced it. A tier with nothing to say SAYS SO, because a missing sentence reads
#    as an oversight and an explicit refusal reads as the fact it is.
# ---------------------------------------------------------------------------------------------

_FAMILY_BAR = None


def family_bar_facts():
    """The bar's BASIS, not just its value.

    Ori, 2026-08-25: "you used gross-profit — are we not using net ad roas". The sentence said
    "against the Lollibox bar of 0.81" and never said WHY 0.81, so a reader who knows the account's
    ads_net_roas reasonably reads it as accepting a sub-break-even return. The number was right and
    the sentence hid the only thing that made it make sense: the bar is 1/(1 + 0.5*(halo-1)), the
    family's break-even once HALF its measured organic halo is credited (V_FAMILY_BAR: adjust the
    bar, never the measurement — organic sales are real at family grain and unattributable at
    keyword grain). An explanation that omits the adjustment is not shorter, it is wrong."""
    global _FAMILY_BAR
    if _FAMILY_BAR is None:
        _FAMILY_BAR = {}
        try:
            for r in bq("SELECT DISTINCT family, keyword_bar, halo_factor, ads_net_roas "
                        "FROM `onyga-482313.OI.T_FAMILY_BAR`"):
                _FAMILY_BAR[r['family']] = r
        except SystemExit:
            _FAMILY_BAR = {}
    return _FAMILY_BAR


def bar_basis(fam):
    r = family_bar_facts().get(fam)
    if not r:
        return ""
    halo, anr = _f(r.get('halo_factor')), _f(r.get('ads_net_roas'))
    if halo is None or halo <= 1.0:
        return " Bar 1.00 — no halo credit; measured organic lift is not above 1."
    txt = f" Bar = break-even crediting half the family's {halo:.2f}x organic halo"
    txt += f" (ads-only {anr:.3f})." if anr is not None else "."
    return txt


# ---------------------------------------------------------------------------------------------
# THE MEND — a losing campaign is walked back to profit, budget AND bids together.
# ---------------------------------------------------------------------------------------------
# Ori, 2026-08-25: "if the campaign is not profitable the brain can use his budget tool to reduce
# it so it wont loose a lot of money until he fix the campaign to be profitable... but if you
# reduce unprofitable budget you should also trim bids to try to make it profitable."
#
# BOTH ARMS, BECAUSE THEY DO DIFFERENT THINGS. Cutting the budget caps the TOTAL loss and changes
# no unit economics — the campaign loses less only because it buys less. Trimming the bid attacks
# the CAUSE: a lower CPC is a higher return per ad dollar. A budget cut alone is a tourniquet; the
# pair is a tourniquet and a stitch.
#
# WHY THE LADDER CANNOT DRIVE THIS, and it is the finding that shaped the whole design. The ladder
# judges on a SETTLED 90-DAY window, and on that window the losing campaigns look healthy: across
# them the ladder calls only NINE keywords below bar, worth $4.30 of trimmable bid. Judged on their
# own RECENT settled 28 days, ONE HUNDRED AND NINETY-NINE are below their own bar, carrying
# $12,903.61 of spend. The campaigns are not full of mispriced keywords by the ladder's reckoning —
# they are full of keywords whose RECENT record has fallen away from a 90-day average that has not
# caught up. So the mend reads the recent window, and it says so on every row.
#
# IT NEVER TRIMS A KEYWORD THAT IS EARNING. A campaign can lose money with every keyword inside it
# correctly priced, and trimming a correct price to fix a campaign-level number would be the Brain
# overruling the Catalog on the Catalog's own question (§1.1). Where nothing qualifies, the mend is
# BUDGET ONLY and the book says so in words rather than leaving a reader to wonder.
MEND_STEP = 0.15                  # one window's walk, both arms. Declared, not buried (§3.3).
MEND_MIN_SPEND_28D = 50.0         # below this a campaign's loss is noise, not a pattern worth acting on

MEND_SQL = """
WITH wm AS (SELECT MAX(date) AS w FROM `{P}.OI.FACT_AMAZON_ADS`),
-- SETTLED window: ends 7 days back, because SP sales accrue for 7 days and a window ending at the
-- watermark counts all the spend against only part of the sales. Checked before relying on it: the
-- unsettled window shows 80 losing campaigns and the settled one 78, so the losses are real and not
-- a settle artifact — but the settled window is the honest one to act on.
camp AS (
  SELECT CAST(a.campaign_id AS STRING) AS campaign_id,
         ANY_VALUE(a.campaign_name) AS campaign_name,
         SUM(a.GROSS_PROFIT) - SUM(a.Ads_cost) AS net_profit_28d,
         SUM(a.Ads_cost) AS spend_28d,
         SAFE_DIVIDE(SUM(a.GROSS_PROFIT), NULLIF(SUM(a.Ads_cost), 0)) AS gp_roas_28d
  FROM `{P}.OI.FACT_AMAZON_ADS` a CROSS JOIN wm
  WHERE a.date BETWEEN DATE_SUB(wm.w, INTERVAL 34 DAY) AND DATE_SUB(wm.w, INTERVAL 7 DAY)
    AND a.campaign_id IS NOT NULL
  GROUP BY 1),
losers AS (SELECT * FROM camp WHERE net_profit_28d < 0 AND spend_28d >= {MINSPEND}),
kw AS (
  SELECT CAST(a.campaign_id AS STRING) AS campaign_id, LOWER(TRIM(a.targeting)) AS t,
         SUM(a.Ads_cost) AS kw_spend_28d,
         SAFE_DIVIDE(SUM(a.GROSS_PROFIT), NULLIF(SUM(a.Ads_cost), 0)) AS kw_roas_28d
  FROM `{P}.OI.FACT_AMAZON_ADS` a CROSS JOIN wm
  WHERE a.date BETWEEN DATE_SUB(wm.w, INTERVAL 34 DAY) AND DATE_SUB(wm.w, INTERVAL 7 DAY)
  GROUP BY 1,2)
SELECT
  l.campaign_id, l.campaign_name, l.net_profit_28d, l.spend_28d, l.gp_roas_28d,
  s.keyword_id, s.ad_group_id, s.target_text, s.match_type, s.channel, s.family,
  s.state AS ladder_state, s.current_bid, s.bid_floor, s.bid_floor_source, s.family_bar,
  s.settled_roas90, s.is_pt,
  k.kw_spend_28d, k.kw_roas_28d,
  d.campaign_type, d.state AS campaign_state, d.portfolio_id,
  e.echo_portfolio_id
FROM losers l
JOIN `{P}.OI.FACT_KEYWORD_STATE` s ON CAST(s.campaign_id AS STRING) = l.campaign_id
JOIN kw k ON k.campaign_id = l.campaign_id AND k.t = LOWER(TRIM(s.target_text))
LEFT JOIN (SELECT CAST(campaign_id AS STRING) AS cid2, campaign_type, state, portfolio_id
           FROM `{P}.OI.DIM_CAMPAIGN` WHERE is_current) d ON d.cid2 = l.campaign_id
LEFT JOIN (SELECT CAST(campaign_id AS STRING) AS cid3,
                  ARRAY_AGG(portfolio_id IGNORE NULLS ORDER BY date DESC LIMIT 1)[SAFE_OFFSET(0)]
                    AS echo_portfolio_id
           FROM `{P}.OI.V_SRC_AmazonAds_campaign_history` GROUP BY campaign_id) e
       ON e.cid3 = l.campaign_id
WHERE d.state = 'ENABLED'
  -- TWO CONDITIONS, AND THE SECOND ONE IS THE ONE THAT MATTERS.
  -- (1) The keyword's OWN recent record condemns it: below its family bar on the settled 28 days.
  -- (2) The LADDER ALSO ALREADY READS IT AS AT-OR-BELOW BAR. Without (2) the first cut of this
  --     trimmed 100 keywords across 24 campaigns, and the states it caught were wrong in four
  --     separate ways: 39 PARKED (already sitting at the Catalog's own park price — there is
  --     nothing to walk), 21 LAUNCH_CONTAINED (the launch ruling is explicit that a launch is never
  --     loss-cut — find the right bid, bleed via negate), 10 DEAD (those belong to a PAUSE, not a
  --     trim), 13 TRIAL (a probe the Brain funded with a click goal; halving its bid mid-window is
  --     the half-funded question that answers nothing) and 4 WINNER (the ladder says it earns on 90
  --     settled days, and overruling that on a 28-day dip is the Brain deciding the Catalog's own
  --     question, which §1.1 forbids).
  --     What survives is the honest set: keywords the CATALOG ITSELF already calls at or below bar.
  AND k.kw_roas_28d IS NOT NULL AND k.kw_roas_28d < s.family_bar
  AND s.state IN ('REPRICE', 'AT_BAR', 'FLOOR_PROBATION')
  AND s.current_bid > s.bid_floor + 0.005
ORDER BY l.net_profit_28d ASC, k.kw_spend_28d DESC
"""


def mend_budgets(budget_recs, losing, step=MEND_STEP):
    """ARM 1 of the mend: a losing campaign's budget WALKS DOWN, whatever the ramp said.

    Ori: "the brain can use his budget tool to reduce it so it wont loose a lot of money until he
    fix the campaign to be profitable." The ramp has no opinion about profit — measured, its budget
    moves correlate NEGATIVELY with net profit (-0.396 on dollars), so a losing campaign is as
    likely to be handed more as less. This overrides the ramp's number for losing campaigns only.

    THE MEND IS A FLOOR ON THE CUT, NOT A CEILING. Where the ramp already cuts deeper than a step,
    the deeper cut stands — the mend exists to stop a loser being GROWN or left flat, not to protect
    it from a cut the allowance already justified."""
    out = []
    for r in budget_recs:
        if action_kind(r) != BUDGET:
            out.append(r)
            continue
        a = r['audit']
        cid = str(a.get('campaign_id') or '')
        info = losing.get(cid)
        if not info:
            out.append(r)
            continue
        old_b = a.get('_old_budget') or 0
        ramp_b = a.get('_new_budget') or 0
        walked = round(old_b * (1 - step), 2)
        new_b = min(ramp_b, walked)            # whichever is lower: the mend never softens a cut
        if abs(new_b - ramp_b) < 0.005:
            out.append(r)                      # the ramp already cut at least this far
            continue
        a = dict(a, _new_budget=new_b, _mended=True, _ramp_budget=ramp_b,
                 disposition='BUDGET_DOWN' if new_b < old_b else 'BUDGET_UP')
        cells = dict(r['cells'])
        cells['Budget' if r['sheet'] == SB_SHEET else 'Daily Budget'] = f"{new_b:.2f}"
        out.append({**r, 'audit': a, 'cells': cells})
    return out


def mend_rows(step=MEND_STEP, min_spend=MEND_MIN_SPEND_28D, skip_keys=frozenset()):
    """Budget cuts and bid trims for campaigns losing money. Returns a list of book records.

    skip_keys: (campaign_id, keyword_id) pairs another source already prices. The reprice book is
    already acting on those, and a second opinion on one keyword in one night is two prices, not a
    stronger one."""
    rows = bq(MEND_SQL.replace('{P}', PROJECT).replace('{MINSPEND}', repr(float(min_spend))))
    out, by_campaign = [], defaultdict(list)
    for r in rows:
        by_campaign[r['campaign_id']].append(r)

    for cid, ks in by_campaign.items():
        head = ks[0]
        is_sb = (head.get('campaign_type') or '').upper() == 'SB'
        echo = head.get('portfolio_id') or head.get('echo_portfolio_id') or ''
        never_had = not (head.get('portfolio_id') or head.get('echo_portfolio_id'))

        # ARM 1 (the budget) is applied to the plan's own budget row by mend_budgets() below, so a
        # campaign never carries two competing budget rows in one book.
        # ARM 2: attack the cause — each condemned keyword walks down the same step.
        spend_day = num(head.get('spend_28d')) / 28.0
        for k in ks:
            if (cid, str(k['keyword_id'])) in skip_keys:
                continue
            ob = num(k.get('current_bid'))
            floor = num(k.get('bid_floor'))
            if ob is None or floor is None:
                continue
            nb = round(max(ob * (1 - step), floor), 2)
            if nb >= ob - 0.005:          # already at or below its floor — nothing to walk
                continue
            if is_sb:
                cells = {h: '' for h in SB_HEADERS}
                cells.update({'Product': 'Sponsored Brands',
                              'Entity': 'Product Targeting' if k.get('is_pt') else 'Keyword',
                              'Operation': 'Update', 'Campaign Id': cid,
                              'Ad Group Id': str(k.get('ad_group_id') or ''),
                              'Keyword Id': str(k['keyword_id']), 'Bid': f"{nb:.2f}"})
                sheet = SB_SHEET
            else:
                cells = {h: '' for h in SP_HEADERS}
                cells.update({'Product': 'Sponsored Products',
                              'Entity': 'Product Targeting' if k.get('is_pt') else 'Keyword',
                              'Operation': 'Update', 'Campaign ID': cid,
                              'Ad Group ID': str(k.get('ad_group_id') or ''),
                              ('Product Targeting ID' if k.get('is_pt') else 'Keyword ID'):
                                  str(k['keyword_id']),
                              'Bid': f"{nb:.2f}"})
                sheet = SP_SHEET
            out.append({
                'source': 'mend', 'sheet': sheet, 'cells': cells,
                'audit': {
                    'disposition': 'MEND_BID_DOWN', 'campaign_id': cid,
                    'campaign': head.get('campaign_name') or '', 'keyword_id': str(k['keyword_id']),
                    'ad_group_id': str(k.get('ad_group_id') or ''),
                    'target': k.get('target_text') or '', 'match': k.get('match_type') or '',
                    'channel': k.get('channel') or '', 'family': k.get('family') or '',
                    'old_bid': repr(ob), 'new_bid': repr(nb),
                    'ladder_state': k.get('ladder_state'),
                    'bid_floor': k.get('bid_floor'), 'bid_floor_source': k.get('bid_floor_source'),
                    'family_bar': k.get('family_bar'),
                    '_kw_roas_28d': num(k.get('kw_roas_28d')),
                    '_kw_spend_28d': num(k.get('kw_spend_28d')),
                    '_camp_net_profit': num(head.get('net_profit_28d')),
                    '_camp_spend': num(head.get('spend_28d')),
                    '_camp_roas': num(head.get('gp_roas_28d')),
                    '_camp_spend_day': spend_day,
                    '_step': step,
                    '_never_had_portfolio': never_had,
                }})
    return out


def _f(v, default=None):
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def explain(rec):
    """Three sentences, one per tier, AS SHORT AS THEY CAN BE AND STILL BE TRUE (Ori, 2026-08-25).

    NAME THE METRIC THE WAY THE ACCOUNT NAMES IT. This first said "gross-profit dollars per ad
    dollar", which is the same quantity the account calls NET ROAS — `GROSS_PROFIT / Ads_cost`, and
    `GROSS_PROFIT` is `Ads_sales - cost_per_unit x units` with ad spend NOT subtracted
    (V_ADS_COST_CORRECTED), so margin per ad dollar exactly. A second name for one number reads as a
    second metric, and it cost a round trip asking whether we were using net ad ROAS at all."""
    a, src = rec['audit'], rec['source']
    subj = a.get('target') or '(unnamed)'
    fam = a.get('family') or 'unmapped'
    kind = action_kind(rec)

    if kind == BUDGET:
        old_b, new_b = a['_old_budget'], a['_new_budget']
        return (
            "No verdict — the Catalog does not value campaigns (violation 22).",
            f"{'Raises' if new_b > old_b else 'Lowers'} {fam}'s budget "
            f"${old_b:.2f} → ${new_b:.2f}/day, but a budget is a CEILING: the campaign spends "
            f"${a['_visible_spend']:.2f}/day today ("
            + (f"{a['_utilisation'] * 100:.0f}% of it" if a['_utilisation'] is not None else "n/a")
            + f") and the plan expects its spend to move {a['_spend_delta']:+.2f}/day. "
            + (f"The campaign has made ${a['_net_profit_28d']:,.2f} net profit over 28 SETTLED days "
               f"(GP-ROAS {a['_gp_roas_28d']:.2f}), so it may be grown."
               if (a.get('_net_profit_28d') or 0) > 0 else
               (f"The campaign has LOST ${abs(a['_net_profit_28d']):,.2f} over 28 SETTLED days "
                f"(GP-ROAS {a['_gp_roas_28d']:.2f}) — it is being mended, not grown."
                if a.get('_net_profit_28d') is not None else
                "No 28-day profit reading, so the profit gate abstained."))
            + (f" MENDED — the ramp wanted ${a['_ramp_budget']:.2f}/day and the Brain walked the "
               f"budget down {(1 - new_b / old_b) * 100:.0f}% instead, because a losing campaign is "
               f"capped while it is fixed. The bids of its below-bar keywords walk down with it."
               if a.get('_mended') else "")
            + f" Pot ${a['_pot']:.2f}/day, ramped allowance ${a['_allowance']:.2f}/day at "
            f"{a['_share']:.2f} share. Basis: {a['_basis'] or 'not stated'}.",
            "Not consulted — a budget is a daily ceiling, not a price. Bids unchanged.")

    if kind == MEND_TRIM:
        npf = a.get('_camp_net_profit') or 0
        cat = (f"'{subj}' returned {(a.get('_kw_roas_28d') or 0):.2f} on its own last settled 28 days "
               f"(${(a.get('_kw_spend_28d') or 0):.2f} spent) against {fam}'s "
               f"{(_f(a.get('family_bar')) or 0):.2f} bar. The ladder still reads it "
               f"{a.get('ladder_state')} on 90 settled days — this is the RECENT window disagreeing "
               f"with the average, which is why the campaign loses while the ladder looks calm.")
        brain = (f"The campaign lost ${abs(npf):,.2f} over 28 settled days on "
                 f"${(a.get('_camp_spend') or 0):,.2f} (GP-ROAS {(a.get('_camp_roas') or 0):.2f}), so "
                 f"the Brain is MENDING it: the budget walks down "
                 f"{(a.get('_step') or 0) * 100:.0f}% and every keyword whose own recent record is "
                 f"below bar walks down with it. Cutting the budget alone would cap the loss without "
                 f"fixing it.")
        ob, nb = _f(a.get('old_bid')), _f(a.get('new_bid'))
        pace = (f"${ob:.2f} → ${nb:.2f} ({(nb / ob - 1) * 100 if ob else 0:+.1f}%), floored at "
                f"${_f(a.get('bid_floor')) or 0:.2f} ({a.get('bid_floor_source') or 'unstated'}). "
                f"Pacing chose neither the subject nor the step.")
        return cat, brain, pace

    if kind == BID_MOVE:
        bar, roas = _f(a.get('family_bar')), _f(a.get('roas90_used'))
        side = (a.get('bar_side') or '').lower()
        floor, floor_src = _f(a.get('bid_floor')), a.get('bid_floor_source') or 'unstated'
        n90 = a.get('orders90') or 0
        cat = (f"'{subj}': {(roas or 0):.2f} net ROAS on settled 90d "
               f"({n90} order{'' if str(n90) == '1' else 's'}), "
               f"{side or 'vs'} {fam}'s {(bar or 0):.2f} bar."
               + bar_basis(fam)
               + (f" Floor ${floor:.2f} ({floor_src})." if floor is not None
                  else f" Floor unset ({floor_src})."))
        verdict = a.get('rule_b_verdict') or ''
        rb_ret, rb_bar = _f(a.get('rule_b_return')), _f(a.get('rule_b_bar'))
        if verdict:
            n_ord = a.get('rule_b_orders')
            brain = (f"Reviewed, no veto: {verdict}"
                     + (f", {rb_ret:.2f} vs {rb_bar:.2f}"
                        if rb_ret is not None and rb_bar is not None else "")
                     + f" over {a.get('rule_b_window') or 'the plan window'}"
                     + (f", {n_ord} order{'' if str(n_ord) == '1' else 's'}." if n_ord else ".")
                     + " Did not fund it — a bid consults no seat, allowance or pot (violation 26).")
        else:
            brain = ("Nothing — no window verdict, so not even the veto ran. A bid consults no "
                     "seat, allowance or pot (violation 26).")
        ob, nb = _f(a.get('old_bid')), _f(a.get('new_bid'))
        pct = (nb / ob - 1) * 100 if ob and nb else 0
        pace = (f"${ob:.2f} → ${nb:.2f} ({pct:+.1f}%)"
                + (", at the move cap." if a.get('cap_applied') in ('1', 'True', 'true', True)
                   else ".")
                + (f" Engine instruction {a.get('engine_instruction')} present; the book yielded."
                   if a.get('engine_instruction') else ""))
        return cat, brain, pace

    # Catalog-decided actions on an owned subject: pause, negate, park, seat move.
    clk, ordn = a.get('settled_clk90') or 0, a.get('settled_ord90') or 0
    per_day = _f(a.get('cost_per_day'), 0) or 0.0
    ladder = a.get('ladder_state') or 'no ladder state'
    nxt = a.get('next_check_date') or ''
    # The source's own reason is a paragraph and already contains these facts. Restating it whole
    # made the Catalog sentence four lines that said one line's worth.
    cat = (f"'{subj}': {ladder} — {clk} clicks, {ordn} orders, ${per_day:.2f}/day"
           + ("." if nxt else ", no re-check date."))

    if kind == NEGATE:
        return (cat,
                f"Funds nothing — a blocked term takes no seat; ${per_day:.2f}/day returns to "
                f"{fam}'s pot.",
                "No bid to set — a negative removes it from the auction rather than pricing it.")
    if kind == KEYWORD_PAUSE:
        return (cat,
                f"No seat for a {ladder} subject; ${per_day:.2f}/day returns to {fam}'s pot.",
                "Paused Amazon-side — the ladder's verdict carried out, not a price Pacing chose.")
    if kind == PARK:
        pp, ps = _f(a.get('park_price')), a.get('park_price_source') or 'unstated'
        return (cat,
                f"No seat this window; ${per_day:.2f}/day returns to {fam}'s pot. A park owes a "
                + (f"re-test, due {nxt}." if nxt else "re-test and carries no date (violation 14)."),
                "Held at its park price"
                + (f" ${pp:.2f} ({ps})" if pp is not None else "")
                + " — alive, taking no clicks until something buys it evidence.")
    return (cat,
            f"Moves the seat — ${per_day:.2f}/day reallocated inside {fam}.",
            "Executes at the price the seat carries; chose neither subject nor amount.")


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
    if disp == 'MEND_BID_DOWN':
        # THE BRAIN DECIDED THIS ONE, not Pacing. Pacing prices a keyword on the keyword's own
        # question; this trim exists because the CAMPAIGN is losing money and the Brain chose to
        # mend it. Filing it under Pacing would hide the only reason it is in the book.
        return MEND_TRIM
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


DEFAULT_BUDGET_MAX_MOVE = 0.25

# AN UNPROFITABLE CAMPAIGN MAY NOT BE GROWN — it may only be MENDED (Ori, 2026-08-25):
# "if this campaign is not profitable it needs to do it slowly until it is profitable first (this is
#  his job — make sure campaigns are the most net profit dollars they can and also keep improving)".
# Slowly, not never: a losing campaign can still take a small step, because holding it perfectly
# still is its own way of never finding out. Cuts are never restricted — mending is always allowed.
# A declared constant, not a buried number (§3.3: the Brain's settings are testable, code is not).
DEFAULT_UNPROFITABLE_MAX_RAISE = 0.05


def cap_budget_moves(records, max_move,
                     unprofitable_max_raise=DEFAULT_UNPROFITABLE_MAX_RAISE):
    """STEP 3 — ship the small budget movers, HOLD the big ones for an explicit decision.

    Campaign budgets are a brand-new action type for a book: no generator in this account has ever
    emitted one. The 44 rows the plan proposes net to a mild +$78.41/day (+5.3%), and that netting
    hides that SEVEN campaigns move more than 50%, the largest +127% ($70.00 -> $159.03/day). A
    first upload of a new action type should not contain a 127% move riding along with a reprice.

    HELD, NEVER DROPPED. A budget change that vanishes without a word is indistinguishable from one
    the plan never proposed, and the whole argument for the Refused sheet is that money deliberately
    NOT moved is a decision that has to be visible. Each held row carries its actual percentage, so
    it can be judged rather than merely noticed.

    The cap is SYMMETRIC: a 40% cut is exactly as unreviewed as a 40% raise. Returns (kept, refused);
    it touches only budget rows and passes everything else through untouched.

    TWO GATES, IN ORDER, BECAUSE THEY ASK DIFFERENT QUESTIONS. The PROFIT gate runs first and asks
    "should this campaign be grown at all" — a raise on a campaign losing money buys more of the
    loss. The SIZE cap runs second and asks "is this move too big to ship unreviewed". A losing
    campaign fails the first no matter how modest the move; a profitable one can still fail the
    second. Cuts pass the profit gate always: mending is never held."""
    kept, refused = [], []
    for r in records:
        if action_kind(r) != BUDGET:
            kept.append(r)
            continue
        a = r['audit']
        old_b, new_b = a.get('_old_budget'), a.get('_new_budget')
        # A move from nothing has no percentage. Refuse rather than let it through unmeasured — the
        # one shape where "it is not over the cap" would be true only because the cap cannot see it.
        if not old_b or old_b <= 0:
            a = dict(a, reason=(f"no prior budget to measure the move against "
                                f"(${old_b or 0:.2f} → ${new_b or 0:.2f}/day), so the cap cannot "
                                f"judge it — decide this one explicitly"))
            refused.append({**r, 'audit': a, 'cells': None, 'sheet': None})
            continue
        pct = new_b / old_b - 1
        # THE PROFIT GATE, applied BEFORE the size cap because it is a different question. The cap
        # asks "is this move too big to ship unreviewed"; the gate asks "should this campaign be
        # GROWN AT ALL". A raise on a campaign losing money buys more of the loss, and the Brain's
        # job is net profit dollars per campaign — so a losing campaign is mended first and grown
        # after. Measured before this existed: 8 campaigns were being handed +$209.91/day of extra
        # ceiling while losing $1,659.54 over 28 days, against 3 profitable ones getting +$115.10.
        npf = a.get('_net_profit_28d')
        if pct > 0 and npf is not None and npf <= 0 and pct > unprofitable_max_raise + 1e-9:
            a = dict(a, reason=(
                f"budget RAISE {pct * 100:+.0f}% (${old_b:.2f} → ${new_b:.2f}/day) on a campaign that "
                f"LOST ${abs(npf):,.2f} over the last 28 days on ${a.get('_spend_28d') or 0:,.2f} of "
                f"spend (GP-ROAS {a.get('_gp_roas_28d') or 0:.2f}). An unprofitable campaign is mended "
                f"before it is grown — raises are held above "
                f"{unprofitable_max_raise * 100:.0f}% until it earns. Cuts are never held."))
            refused.append({**r, 'audit': a, 'cells': None, 'sheet': None})
            continue
        if abs(pct) > max_move + 1e-9:
            a = dict(a, reason=(f"budget move {pct * 100:+.0f}% (${old_b:.2f} → ${new_b:.2f}/day) is "
                                f"beyond the ±{max_move * 100:.0f}% cap for this book — held, not "
                                f"dropped. Decide it explicitly, then raise --budget-max-move or "
                                f"change it by hand."))
            refused.append({**r, 'audit': a, 'cells': None, 'sheet': None})
        else:
            kept.append(r)
    return kept, refused


def budget_carry_check(records):
    """VIOLATION 28 — can the campaign carry what is being asked of it?

    A campaign budget row and a bid row inside that campaign are NOT a precedence conflict: the two
    tiers are doing their own jobs, and `test_campaign_and_keyword_rows_are_not_a_conflict` pins
    that. But a budget being CUT while bids inside it are RAISED is a request the campaign may not
    be able to carry, and the book showed the two rows twenty-five lines apart with nothing relating
    them. Measured 2026-08-25: BOX-SP/EXACT (teen-girl-gift, White 2) cut 32% ($20.48 -> $13.94/day)
    while `teen girl gifts` rose $0.72 -> $0.83 inside it.

    IT WARNS, IT DOES NOT REFUSE. The pair can be deliberate — trimming a campaign's ceiling while
    concentrating it on its better keywords is a legitimate rebalance — and refusing would make that
    undeliverable. What is not acceptable is it being invisible.

    Only a CUT with RAISES inside is flagged. A cut with cuts inside is coherent; a raise with
    raises inside is the two layers agreeing, which is the doctrine working rather than failing."""
    budgets, raises = {}, defaultdict(list)
    for r in records:
        a = r['audit']
        cid = str(a.get('campaign_id') or '')
        if not cid:
            continue
        if action_kind(r) == BUDGET:
            budgets[cid] = r
        elif action_kind(r) == BID_MOVE:
            ob, nb = _f(a.get('old_bid')), _f(a.get('new_bid'))
            if ob is not None and nb is not None and nb > ob:
                raises[cid].append(r)

    notes = []
    for cid, brec in budgets.items():
        a = brec['audit']
        old_b, new_b = a['_old_budget'], a['_new_budget']
        if new_b >= old_b or not raises.get(cid):
            continue
        ups = raises[cid]
        # What the raised bids would cost a day if every raised keyword took the clicks it took
        # last window at its NEW price. Deliberately a floor, not a forecast: it counts only the
        # keywords being raised, so the true demand on the budget is at least this.
        implied = sum((_f(u['audit'].get('new_bid')) or 0) for u in ups)
        notes.append({
            'campaign_id': cid,
            'campaign': a.get('campaign') or '',
            'old_budget': old_b, 'new_budget': new_b,
            'pct': (new_b / old_b - 1) * 100 if old_b else 0,
            'raises': len(ups),
            'subjects': ', '.join(str(u['audit'].get('target') or '?') for u in ups[:6]),
            'sum_new_bids': implied,
            'note': (f"budget CUT {abs((new_b / old_b - 1) * 100) if old_b else 0:.0f}% "
                     f"(${old_b:.2f} → ${new_b:.2f}/day) while {len(ups)} bid(s) inside it are "
                     f"RAISED. The Brain is taking money out of the campaign the raises need. "
                     f"Neither row is wrong alone — decide whether the pair is what you meant."),
        })
    return sorted(notes, key=lambda n: n['pct'])


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


def write_book(path, kept, conflicts, refused, no_log=False, carry=()):
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
    if no_log:
        # A person opens the workbook, not the README. The draft state has to be visible HERE.
        ws_x.append(['⛔ DRAFT — NO CHANGE-LOG BATCH WAS WRITTEN. DO NOT UPLOAD. '
                     'Re-run without --no-log to produce an uploadable book.'])
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

    # VIOLATION 28 — the budget-carry warnings share the Conflicts sheet, below the precedence
    # conflicts, because a reader who opens that sheet is already asking "what disagrees here".
    if carry:
        ws_c.append([])
        ws_c.append(['BUDGET CARRY — a campaign losing budget while bids inside it are raised. '
                     'Not a precedence conflict; both rows ship. Decide whether the pair is intended.'])
        ws_c.append(['Campaign', 'Campaign ID', 'Budget', 'Move', 'Bids raised',
                     'Sum of new bids', 'Subjects', 'What it means'])
        for n in carry:
            ws_c.append([n['campaign'], n['campaign_id'],
                         f"${n['old_budget']:.2f} → ${n['new_budget']:.2f}/day",
                         f"{n['pct']:+.0f}%", n['raises'], f"${n['sum_new_bids']:.2f}",
                         n['subjects'], n['note']])

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
        ws.freeze_panes = 'A3' if (no_log and ws is ws_x) else 'A2'
        for col, width in zip('ABCDEFGHIJKLMNO', (6, 6, 9, 14, 14, 11, 34, 18, 30, 18, 12, 12,
                                                  90, 90, 90)):
            ws.column_dimensions[col].width = width
    wb.save(path)
    return line_of


# ---------------------------------------------------------------------------------------------
# 5. The change log. ONE batch for the whole book. PENDING_UPLOAD at build time and flipped by
#    --mark-uploaded, exactly as every other book: nothing has reached Amazon until Ori uploads.
#    A row is NEVER deleted, only labelled.
# ---------------------------------------------------------------------------------------------

# THE ACCOUNT'S OWN VOCABULARY, NOT A NEW ONE. The SOP promised "no new action string is invented
# here" and the first cut broke that promise twice: it wrote INCREASE_BUDGET / REDUCE_BUDGET when
# FACT_PPC_CHANGE_LOG has carried BUDGET_CHANGE since 2026-07-18 (183 rows), and NEGATE when the log
# uses NEGATE_TERM (125 rows). A synonym in a log is worse than a typo: every existing query for
# budget history would silently miss these rows, and the miss looks like "no budget changed".
# Verified against SELECT DISTINCT action FROM FACT_PPC_CHANGE_LOG before this table was written.
ACTION_OF = {
    'BID_UP': 'INCREASE_BID',        # 616 rows in the log
    'BID_DOWN': 'REDUCE_BID',        # 1006
    'PAUSE': 'KEYWORD_PAUSE',        # 86
    'MEND_BID_DOWN': 'REDUCE_BID',   # a bid cut is a bid cut in the log; the TIER says who chose it
    'BUDGET_UP': 'BUDGET_CHANGE',    # 183 — direction lives in old_bid/new_bid, not in the verb
    'BUDGET_DOWN': 'BUDGET_CHANGE',
}


def log_action(rec):
    a, src = rec['audit'], rec['source']
    disp = (a.get('disposition') or '').upper()
    if disp in ACTION_OF:
        return ACTION_OF[disp]
    if (a.get('kind') or '').upper().startswith('NEG'):
        return 'NEGATE_TERM'   # 125 rows in the log; 'NEGATE' would be a synonym nothing queries
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

def budget_net(records):
    """(rows, old_ceiling, new_ceiling, expected_spend_delta, spend_now).

    A BUDGET IS A CEILING, NOT A SPEND. The first version of this returned only the ceiling totals
    and drove a "the cap reversed the book's direction" warning off them — which was measuring the
    wrong quantity. Measured on live data: the rows held beyond the ±25% cap raise ceilings by
    $204.06/day and are expected to move actual spend by $11.00/day, because only 10 of those 26
    campaigns are within 5% of their ceiling. A ceiling raised over a campaign that was never
    reaching it buys nothing."""
    rows = [r for r in records if action_kind(r) == BUDGET]
    o = sum((r['audit'].get('_old_budget') or 0) for r in rows)
    n = sum((r['audit'].get('_new_budget') or 0) for r in rows)
    sd = sum((r['audit'].get('_spend_delta') or 0) for r in rows)
    sn = sum((r['audit'].get('_visible_spend') or 0) for r in rows)
    return len(rows), o, n, sd, sn


def write_readme(path, book_name, batch_id, kept, conflicts, refused, sources, no_log,
                 carry=(), budget_cap=None):
    by_tier = defaultdict(list)
    for r in kept:
        by_tier[tier_of(r)].append(r)
    L = [f"# Weekly book — {batch_id}", "",
         f"Built {datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}. Workbook: `{book_name}`.",
         "SOP: `architecture/WEEKLY_BOOK.md`. Doctrine: `architecture/THREE_LAYERS.md`.", ""]
    # THE UPLOAD INSTRUCTION AND THE DRAFT WARNING MUST NEVER BOTH BE TRUE. The first shape put
    # "upload it, then --mark-uploaded" at the top and the --no-log warning at the BOTTOM, so a
    # draft with no batch to mark still opened by telling the reader to upload it. The two are now
    # mutually exclusive and the draft case wins the top of the page.
    if no_log:
        L += ["> ## ⛔ DRAFT — DO NOT UPLOAD THIS BOOK", ">",
              "> `--no-log` was used, so **no change-log batch was written** and the batch id above",
              "> exists nowhere but this file. An uploaded book with no logged batch is a change",
              "> nothing can attribute, measure or restore.", ">",
              "> To produce an uploadable book, run the same command without `--no-log`.", ""]
    else:
        L += ["**Nothing here has reached Amazon.** Upload the two Amazon sheets by hand, then run",
              f"`--mark-uploaded {batch_id}`. If you do not upload it, mark it",
              "`SUPERSEDED_NEVER_UPLOADED` — never delete a change-log row.", ""]
    L += ["## What is in it", "",
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
    # THE CAP CAN INVERT THE BOOK'S DIRECTION, and a reader must not discover that after uploading.
    # Measured 2026-08-25: the full 44 rows net +$78.41/day, but the capped 21 net -$85.77/day —
    # because the big movers are nearly all RAISES, so holding them leaves the cuts standing alone.
    # A book that quietly reverses what the plan intended is a hazard, not a conservative choice.
    n_k, o_k, w_k, sd_k, sn_k = budget_net(kept)
    n_h, o_h, w_h, sd_h, sn_h = budget_net(refused)
    if n_k or n_h:
        util_k = (sn_k / o_k) if o_k else None
        util_h = (sn_h / o_h) if o_h else None
        L += ["## Campaign budgets — the ceiling, and what it actually buys", "",
              "**A budget is a ceiling, not a spend.** The two columns move independently, and only",
              "the second one is money. Where a campaign is not reaching its ceiling, raising it buys",
              "nothing — so read the right-hand column first.", "",
              "| | rows | ceiling moves | spending now | **expected spend change** |",
              "|---|---|---|---|---|",
              f"| **ships in this book** | {n_k} | {w_k - o_k:+,.2f}/day | ${sn_k:,.2f}/day"
              + (f" ({util_k * 100:.0f}% of ceiling)" if util_k is not None else "")
              + f" | **{sd_k:+,.2f}/day** |"]
        if n_h:
            L.append(f"| held beyond the cap | {n_h} | {w_h - o_h:+,.2f}/day | ${sn_h:,.2f}/day"
                     + (f" ({util_h * 100:.0f}% of ceiling)" if util_h is not None else "")
                     + f" | {sd_h:+,.2f}/day |")
            L.append(f"| **the plan as a whole** | {n_k + n_h} | "
                     f"{(w_k + w_h) - (o_k + o_h):+,.2f}/day | ${sn_k + sn_h:,.2f}/day | "
                     f"**{sd_k + sd_h:+,.2f}/day** |")
        L.append("")
        if n_h and abs(w_h - o_h) > 1 and abs(sd_h) < abs(w_h - o_h) * 0.25:
            L += [f"> **The {n_h} held rows move ceilings by {w_h - o_h:+,.2f}/day and are expected "
                  f"to move spend by only {sd_h:+,.2f}/day.** Most of those campaigns are not "
                  "reaching the ceiling they already have, so raising it changes little. Holding "
                  "them is a smaller decision than the ceiling figures suggest.", ""]
        # THE WARNING IS ON SPEND, NOT ON THE CEILING. The first version compared ceiling totals and
        # announced a reversal that did not exist in money: the plan's ceilings move +$135.62/day
        # while its own spend estimate moves -$41.27/day, so a ceiling-based test fires on a
        # disagreement between a ceiling and a ceiling and calls it a change of direction.
        if n_h and sd_k * (sd_k + sd_h) < 0:
            L += ["> ⚠️ **THE CAP HAS REVERSED THE DIRECTION OF THIS BOOK — in spend, not just in "
                  f"ceilings.** The plan as a whole expects spend to move **{sd_k + sd_h:+,.2f}/day**, "
                  f"but what ships here moves it **{sd_k:+,.2f}/day**. Uploading this is not a "
                  "smaller version of the plan; it is a different decision. Read the held rows on "
                  "`Refused` first.", ""]
    if carry:
        L += ["## Budget carry — read this before uploading", "",
              f"**{len(carry)} campaign(s) are losing budget while bids inside them are raised.**",
              "That is not a precedence conflict — the Brain sets ceilings and Pacing sets prices, and",
              "both rows ship. But the Brain is taking money out of the campaign the raises need, and",
              "nothing in this system checks whether the smaller budget can still carry them",
              "(violation 28). Decide whether each pair is what you meant.", "",
              "| campaign | budget | move | bids raised | subjects |", "|---|---|---|---|---|"]
        for n in carry:
            L.append(f"| {n['campaign']} | ${n['old_budget']:.2f} → ${n['new_budget']:.2f}/day | "
                     f"{n['pct']:+.0f}% | {n['raises']} | {n['subjects']} |")
        L.append("")
    L += ["## Refused — money deliberately NOT moved", "",
          f"{len(refused)} candidate row(s) were built by a source and then refused: season-blocked,",
          "holdout arm, engine-instructed, or judged on the good side of the window. They are on the",
          "`Refused` sheet with the reason. A refusal is a decision about money; it is shown rather",
          "than omitted so it can be argued with.", "",
          "## Sources", "", "| source | status |", "|---|---|"]
    for s in sources:
        if not s['ok']:
            status = '**FAILED — ' + (s['error'] or '')[:200] + '**'
        elif s.get('reused'):
            age = (datetime.now(timezone.utc) - s['staged_at']).total_seconds() / 60
            status = (f"**REUSED from disk, staged {age:.0f} min ago** — these decisions are that "
                      f"old, not tonight's")
        else:
            status = 'ok — run fresh for this book'
        L.append(f"| `{s['name']}` | {status} |")
    L += ["", "## What this book does not do", "",
          "- It **decides nothing**. Every row was decided by a source module tonight; this file",
          "  merges, ranks and explains.",
          "- It does **not** implement §5's confidence gate — `confidence` is still not computed",
          "  (violation 20 open).",
          "- It does **not** re-open campaigns. Campaign state is yours by hand this season (§4.1).",
          "- It does **not** upload. You upload, always.", ""]
    open(path, 'w').write("\n".join(L))


# ---------------------------------------------------------------------------------------------
# THE OUTPUT LOCK. Two builds writing one path do not fail — they CLOBBER, and the failure is worse
# than a crash: the slower run's README can land beside the faster run's workbook, so the file
# describing the rows and the file holding them come from different builds. That happened during
# this tool's own development and read as a bug in the README writer for twenty minutes. A book
# whose README describes other rows is worse than no book.
# ---------------------------------------------------------------------------------------------

def acquire_output_lock(out_path):
    lock_path = out_path + '.lock'
    if os.path.exists(lock_path):
        try:
            holder = open(lock_path).read().strip()
        except OSError:
            holder = 'unknown'
        pid = holder.split()[0] if holder else ''
        alive = False
        if pid.isdigit():
            try:
                os.kill(int(pid), 0)
                alive = True
            except OSError:
                alive = False
        if alive:
            sys.exit(f"refusing to build: another build is writing {out_path}\n"
                     f"  holder: {holder}\n"
                     f"  wait for it, or use -o to write somewhere else.")
        print(f"  clearing a stale lock from a dead build ({holder})")
        os.unlink(lock_path)
    with open(lock_path, 'w') as f:
        f.write(f"{os.getpid()} started {datetime.now(timezone.utc):%Y-%m-%d %H:%M:%S UTC}")
    return lock_path


def build_parser():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('-o', '--out', default=f".tmp/weekly_book_{date.today():%Y%m%d}.xlsx")
    ap.add_argument('--plan', default='B', choices=['A', 'B'],
                    help="which plan arm's campaign budgets to carry (default B)")
    ap.add_argument('--no-log', action='store_true',
                    help="skip the change-log batch insert. The book is then a DRAFT and must not "
                         "be uploaded.")
    ap.add_argument('--reuse-stage', action='store_true',
                    help="rebuild the book from source output already staged on disk instead of "
                         "re-running the sources (they take minutes and re-query BigQuery). The "
                         "README stamps how old each staged source is.")
    ap.add_argument('--budget-max-move', type=float, default=DEFAULT_BUDGET_MAX_MOVE,
                    metavar='PCT',
                    help="hold any campaign budget move beyond this fraction (default 0.25 = "
                         "±25%%). Held rows go to the Refused sheet with their actual percentage — "
                         "never dropped. Symmetric: a cut is as unreviewed as a raise. Pass a large "
                         "number to ship every move.")
    ap.add_argument('--mend-step', type=float, default=MEND_STEP, metavar='PCT',
                    help="one window's walk for a losing campaign, applied to BOTH its budget and "
                         "the bids of keywords whose own recent record is below their bar "
                         "(default 0.15 = -15%%).")
    ap.add_argument('--no-mend', action='store_true',
                    help="skip the mend entirely: no budget walk-down and no bid trims on losing "
                         "campaigns.")
    ap.add_argument('--unprofitable-max-raise', type=float,
                    default=DEFAULT_UNPROFITABLE_MAX_RAISE, metavar='PCT',
                    help="the most a campaign LOSING money over 28 days may have its budget raised "
                         "(default 0.05 = +5%%). An unprofitable campaign is mended before it is "
                         "grown. Cuts are never held by this gate.")
    ap.add_argument('--no-budgets', action='store_true',
                    help="omit the Brain's campaign-budget rows (bids and Catalog actions only)")
    ap.add_argument('--change-log-table', default=None,
                    help="a TMP_/TEMP_ copy of FACT_PPC_CHANGE_LOG to act on instead of the live "
                         "table. Refused unless the name starts TMP_ or TEMP_.")
    return ap


def _main(args):
    change_log = CHANGE_LOG
    if args.change_log_table:
        base = args.change_log_table.rsplit('.', 1)[-1]
        if not base.upper().startswith(('TMP_', 'TEMP_')):
            sys.exit(f"refusing --change-log-table {args.change_log_table}: must be a TMP_/TEMP_ copy")
        change_log = args.change_log_table if '.' in args.change_log_table \
            else f"{PROJECT}.OI.{args.change_log_table}"

    os.makedirs(os.path.dirname(args.out) or '.', exist_ok=True)
    lock_path = acquire_output_lock(args.out)
    _main._lock_path = lock_path
    stage = os.path.join(os.path.dirname(args.out) or '.', '_weekly_stage')
    os.makedirs(stage, exist_ok=True)

    print("Assembling the weekly book. Sources run with --no-log; this file writes the one batch.")
    sources = [
        run_source('reprice', 'tools/build_reprice_bulksheet.py', ['--rule-b'], stage,
                   args.reuse_stage),
        run_source('seats', 'tools/build_seat_moves_bulksheet.py', [], stage, args.reuse_stage),
    ]
    mend = []
    records, refused = [], []
    for s in sources:
        if not s['ok']:
            print(f"  !! {s['name']} FAILED — its rows are absent from this book:\n{s['error']}")
            continue
        ex, rf = read_source(s)
        records += ex
        refused += rf
        print(f"  {s['name']}: {len(ex)} executable, {len(rf)} refused")

    # THE MEND, ARM 2 — bid trims on keywords whose OWN recent record condemns them, inside
    # campaigns that are losing money. Built before the budgets so arm 1 knows which campaigns are
    # losing, and skipping any keyword the reprice book already prices: two opinions on one keyword
    # in one night is two prices, not a stronger one.
    if not args.no_mend:
        already = {(str(r['audit'].get('campaign_id')), str(r['audit'].get('keyword_id')))
                   for r in records}
        mend = mend_rows(args.mend_step, skip_keys=already)
        records += mend
        sources.append({'name': 'mend (losing campaigns)', 'ok': True, 'error': None})
        camps = len({r['audit']['campaign_id'] for r in mend})
        print(f"  mend: {len(mend)} bid trims across {camps} losing campaign(s)")

    if not args.no_budgets:
        b = budget_rows(args.plan)
        # THE MEND, ARM 1 — before the cap, because a mended budget is a CUT and the cap must judge
        # the number that will actually ship rather than the ramp's discarded one.
        losing = {str(x['audit']['campaign_id']): x['audit'] for x in mend
                  if (x['audit'].get('_camp_net_profit') or 0) < 0}
        b = mend_budgets(b, losing, args.mend_step)
        b, over_cap = cap_budget_moves(b, args.budget_max_move, args.unprofitable_max_raise)
        records += b
        refused += over_cap
        sources.append({'name': f'plan-budgets ({args.plan})', 'ok': True, 'error': None})
        print(f"  plan-budgets: {len(b)} campaign budget rows"
              + (f", {len(over_cap)} HELD beyond the ±{args.budget_max_move * 100:.0f}% cap"
                 if over_cap else ""))
        for r in sorted(over_cap,
                        key=lambda x: -abs((x['audit'].get('_new_budget') or 0)
                                           / (x['audit'].get('_old_budget') or 1) - 1))[:8]:
            a = r['audit']
            ob, nb = a.get('_old_budget') or 0, a.get('_new_budget') or 0
            pct = (nb / ob - 1) * 100 if ob else float('nan')
            print(f"       HELD {pct:+7.0f}%  ${ob:8.2f} → ${nb:8.2f}  {a.get('campaign')}")

    if not records:
        sys.exit("no executable rows from any source — nothing to build")

    kept, conflicts = resolve(records)
    preflight(kept)
    carry = budget_carry_check(kept)
    print(f"\n  {len(kept)} rows kept, {len(conflicts)} conflict(s), {len(refused)} refused")

    batch_id = f"weekly_book_{datetime.now(timezone.utc):%Y%m%d_%H%M%S}"
    os.makedirs(os.path.dirname(args.out) or '.', exist_ok=True)
    write_book(args.out, kept, conflicts, refused, args.no_log, carry)
    readme_path = args.out.rsplit('.', 1)[0] + '_README.md'
    write_readme(readme_path, os.path.basename(args.out), batch_id, kept, conflicts, refused,
                 sources, args.no_log, carry, args.budget_max_move)

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
    nk, ok_, wk, sdk, snk = budget_net(kept)
    nh, oh, wh, sdh, snh = budget_net(refused)
    if nk or nh:
        print(f"  budgets: {nk} ship (ceiling {wk - ok_:+.2f}/day, SPEND {sdk:+.2f}/day), "
              f"{nh} held (ceiling {wh - oh:+.2f}/day, SPEND {sdh:+.2f}/day)")
        if nh and sdk * (sdk + sdh) < 0:
            print(f"  ⚠️  THE CAP REVERSED THE BOOK'S DIRECTION IN SPEND: the plan moves "
                  f"{sdk + sdh:+.2f}/day, what ships moves {sdk:+.2f}/day.")
    if carry:
        print(f"  ⚠️  {len(carry)} BUDGET CARRY warning(s) — a campaign is losing budget while bids "
              f"inside it are raised. See Conflicts.")
        for n in carry[:5]:
            print(f"       {n['pct']:+.0f}%  ${n['old_budget']:.2f} → ${n['new_budget']:.2f}/day  "
                  f"{n['raises']} raise(s)  {n['campaign']}")
    if any(c['same_tier'] for c in conflicts):
        print("  ⚠️  SAME-TIER collisions are in the book and need a human ruling — see Conflicts.")
    return {'out': args.out, 'readme': readme_path, 'batch': batch_id, 'kept': len(kept)}


def main():
    args = build_parser().parse_args()
    try:
        return _main(args)
    finally:
        # The lock is released even on sys.exit — including a preflight refusal, which is the case
        # most likely to be re-run immediately.
        lp = getattr(_main, '_lock_path', None)
        if lp and os.path.exists(lp):
            try:
                if open(lp).read().split()[0] == str(os.getpid()):
                    os.unlink(lp)
            except (OSError, IndexError):
                pass


if __name__ == '__main__':
    main()
