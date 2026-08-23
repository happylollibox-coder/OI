#!/usr/bin/env python3
"""THE LEAK BOOK — the manual bulksheet that closes the family seat register's LEAK rows.

Task 3 of the family seat register (architecture/FAMILY_SEAT_REGISTER.md). The register's LEAK
rows are keywords the ladder has CLOSED — DEAD, or PARKED past its re-verdict appointment — that
are still taking money. This file turns each of them into one executable row, or one stated
reason why there is none, and adds the ad-group-grain negatives for the search terms bleeding
under them.

WHY A SIBLING FILE AND NOT AN ARM OF build_reprice_bulksheet.py
    The plan allowed either and asked for the argument. Three facts decided it.
    1. Different population, different question. The reprice book's population is the bar/SE
       ladder's LIVE half — AT_BAR / REPRICE / FLOOR_PROBATION / LOSER — and its whole body is
       bid arithmetic: the move cap, the placement translation, the thin-evidence gate, the
       sign-of-the-bar doctrine. A leak has no price to compute. Its keyword is already closed;
       the only question is whether the switch is still on.
    2. Different reversibility. Every row the reprice book emits is undone by one restore row.
       Half of what this book emits — the negatives — cannot be undone by a sheet at all (see
       the README section this file writes). Two files, two restore promises, each true.
    3. Different batch, different grain. A negative acts on the AD GROUP, not on the keyword the
       register listed; its evidence is summed across every product and every keyword in that
       group. Logging it in the reprice batch would put two grains under one batch id.
    What is SHARED is shared: the sheet headers, the pause rows, the SQL-literal quoting, the
    change-log batch discipline and the holdout interlock are imported from the reprice book and
    build_stop_nonconverting_bulksheet, so there is one definition of each.

WHAT IS PAUSABLE, AND THE RULE THAT DECIDES IT (re-derived 2026-08-23, correcting an earlier claim)
    An earlier report said no leak pause is executable "because the ladder requires floor
    probation first". That is a misreading of the ladder and it is retired here.
    Read SP_SNAPSHOT_KEYWORD_STATE's raw ladder in order. Probation gates exactly ONE rung:
    `WHEN probation_elapsed AND at_floor THEN 'LOSER'` — the only kill of a keyword that is
    below its bar but still ordering, and the reprice book owns that pause.
    DEAD is the ladder's FIRST rung and answers a different question: >= 15 settled clicks with
    ZERO orders, fired whatever the bid and whatever the probation clock says, with
    `next_check_date` NULL and the reason "tested loser - thesis falsified". Nothing is pending
    on a DEAD row; there is no probation for it to complete.
    PARKED is the revive cycle's holding pen. R-h seats a PARKED keyword while its appointment
    is still ahead; the register only publishes it as a LEAK once that appointment has PASSED.
    Nothing is testing it either.
    So a LEAK row is PAUSABLE when all of these hold, and each one is named on the row:
      - it is still SERVING in Amazon (the live keyword/target state reads ENABLED). A keyword
        already paused is trailing spend from before the pause: the row would change nothing.
      - its ladder state is terminal with nothing pending: DEAD, or PARKED whose
        `next_check_date` is before the snapshot day (or absent).
      - its campaign is not in the holdout arm on or after `eligible_from` (house rule 13).
      - the season ledger does not BLOCK_CUT its text (a pause is the largest cut there is).
      - it is not brand defense (never judged on profit; the register never codes one as a leak,
        and this book refuses one if it ever arrives).
    Anything else is NOT pausable and is printed with the rule that stopped it.

THE NEGATIVES, AND THE GRAIN THEY ARE JUDGED ON
    Candidates are the engine's own NEGATE_TERM proposals for the leaking keyword
    (T_WEEKLY_RUN_NEGATIVE, the materialised V_ADS_COACH negate list, already deduped against
    DE_NEGATIVE_KEYWORDS / DE_NEGATIVE_TARGETS and already fit-, season- and defense-guarded).
    This book then re-derives the evidence INDEPENDENTLY from FACT_AMAZON_ADS at
    campaign x ad group x search term — never ASIN-sliced, because that is the grain a negative
    actually switches off — and refuses any candidate whose ad group:
      - took an order on the term in the eight-week window, or
      - is net-positive on the term over that window, or
      - is net-positive on the term over its whole LIFETIME (a block is permanent), or
      - sells the term organically (the SQP guard, summed across every product the group
        advertises), or
      - has fewer clicks on it than the coach's published global click floor, or
      - has taken no click on it in the last five complete days (it is not bleeding now).
    A negative is emitted even though the keyword beside it is being paused, because the two act
    at different grains: the pause stops one target, the negative stops the term for every
    keyword and every product in the ad group. The one exception is measured, not assumed: when
    the leak's target IS the term (a product target on the very ASIN the term reports) and the
    leak keyword drew ALL of the ad group's clicks on it, the pause already removes every dollar
    the negative would, and a negative on your own deliberate target is a contradiction — that
    row is refused with its measurement on it.

WHAT IT NEVER DOES
    It never uploads. It never moves a bid. It never touches a budget. It never writes a
    synthetic row into a live table. It never counts a negative as money recovered today: R-l
    counts only pauses, and the recovered-today arithmetic lives in the register, not here.

USAGE
    /usr/bin/python3 tools/build_seat_moves_bulksheet.py [-o PATH] [--no-log]
        [--register-table TMP_...] [--negates-table TMP_...]

    Three TERMINAL actions that build nothing, log nothing and upload nothing:
        --mark-uploaded BATCH_ID   Ori has uploaded that book: its rows leave PENDING_UPLOAD.
        --supersede BATCH_ID ...   Ori will NOT upload it: label it SUPERSEDED_NEVER_UPLOADED.
                                   This is the executable half of the choice every LEAK row in
                                   the register publishes; before 2026-08-23 the label only fired
                                   at the end of a build that logged a NEW batch, so the only way
                                   to obey it was to build another book — which the same sentence
                                   forbids.
        --rewrite-readme AUDIT     rewrite a logged book's README from its own audit CSV, so a
                                   README on disk can gain a note the writer learned after it was
                                   written without building a second book of the same rows.

    The two *-table flags exist so the arm can be proven on a TMP_ copy with injected rows on a
    day the live data does not exercise a branch. Anything other than the live default must be
    named TMP_ or TEMP_, and using either flag forces --no-log: a synthetic batch never reaches
    the change log.
"""

import argparse
import csv
import json
import os
import re
import subprocess
import sys
from datetime import date, datetime, timezone

import openpyxl

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_stop_nonconverting_bulksheet import (  # noqa: E402
    SP_HEADERS, SB_HEADERS, SP_SHEET, SB_SHEET)
from build_reprice_bulksheet import (  # noqa: E402
    sp_pause_row, sb_pause_row, q, num, b)

PROJECT = "onyga-482313"

LIVE_REGISTER = "V_FAMILY_SEAT_REGISTER"
LIVE_NEGATES = "T_WEEKLY_RUN_NEGATIVE"

# THE CHANGE LOG, and the one rule every statement against it obeys (2026-08-23 cleanup):
# a label is written on PENDING_UPLOAD rows only, and a row is never deleted. NULL upload_status
# is the APPLIED state — V_PPC_CHANGE_LOG_APPLIED selects it and --mark-uploaded writes it — so a
# statement that also matched NULL could silently un-apply a batch Ori really uploaded. The live
# proof runs against a TMP_ copy named with --change-log-table; any override must be a TMP_/TEMP_
# copy, so a test can never be aimed at the production log by a typo.
LIVE_CHANGE_LOG = "FACT_PPC_CHANGE_LOG"
CHANGE_LOG = f"{PROJECT}.OI.{LIVE_CHANGE_LOG}"


def set_change_log_table(table):
    global CHANGE_LOG
    assert table == LIVE_CHANGE_LOG or table.startswith(('TMP_', 'TEMP_')), \
        f"{table}: a change-log override must be a TMP_/TEMP_ copy — never another live table"
    CHANGE_LOG = f"{PROJECT}.OI.{table}"
    return CHANGE_LOG

# dispositions
PAUSE = 'PAUSE'
NEGATE_KEYWORD = 'NEGATE_KEYWORD'
NEGATE_TARGET = 'NEGATE_TARGET'
EXECUTABLE = (PAUSE, NEGATE_KEYWORD, NEGATE_TARGET)

# An Amazon ASIN is ten characters: 'B0' plus eight alphanumerics, or a ten-digit ISBN.
ASIN_RE = re.compile(r'^(?:B0[A-Z0-9]{8}|\d{10})$', re.IGNORECASE)
TARGET_ASIN_RE = re.compile(r'(?i)^\s*asin\s*=\s*"?([A-Z0-9]{10})"?\s*$')


def is_asin_term(term):
    """True when a search term is itself an ASIN — the shape a product-target substitute offer
    reports. Such a term is blocked by a negative PRODUCT TARGET, not a negative keyword."""
    return bool(term) and bool(ASIN_RE.match(str(term).strip()))


def target_asin(expression):
    """The ASIN a product target names, or None for anything that is not an asin= expression
    (a category= target names no ASIN, and neither does a keyword)."""
    if not expression:
        return None
    m = TARGET_ASIN_RE.match(str(expression))
    return m.group(1).upper() if m else None


def _d(v):
    """A date out of a BigQuery JSON string, or None."""
    if v in (None, ''):
        return None
    if isinstance(v, date):
        return v
    return date.fromisoformat(str(v)[:10])


# ── the pause rule ────────────────────────────────────────────────────────────────────────────

def classify_leak(r, today):
    """One LEAK row in, one (disposition, reason) out. Every no-action branch names the rule
    that stopped it, in words a reader can act on. See the module docstring for the doctrine."""
    text = f"`{r['target_text']}` in {r['campaign_name']}"
    hold = _d(r.get('holdout_eligible_from'))
    if hold and today >= hold:
        return 'HOLDOUT_EXCLUDED', (
            f"No sheet row: {text} sits in a campaign in the HOLDOUT arm since {hold}. A hand "
            f"upload into the holdout invalidates the trial, so this leak keeps costing until "
            f"the trial ends.")
    if b(r.get('is_brand_defense')):
        return 'DEFENSE_EXEMPT', (
            f"No sheet row: {text} is brand defense, and defense is never judged on profit. "
            f"If its spend is wrong, the answer is a defense decision, not a pause.")
    live = (r.get('live_state') or '').upper()
    if not live:
        return 'LIVE_STATE_UNKNOWN', (
            f"No sheet row: Amazon's own record of {text} could not be read, so whether the "
            f"switch is still on is unknown. Never pause a row whose live state you cannot see.")
    if live != 'ENABLED':
        return 'ALREADY_PAUSED', (
            f"No sheet row: {text} already reads {live.lower()} in Amazon. Its spend on the "
            f"basis window is trailing spend from before it was switched off, and a pause row "
            f"would change nothing. It leaves the register on its own when the spend stops.")
    if r.get('block_cut_reason'):
        return 'SEASON_BLOCKED', (
            f"No sheet row: the season ledger blocks cuts on {text} — {r['block_cut_reason']}. "
            f"A pause is the largest cut there is, and nothing executes by hand into a live peak.")
    state = (r.get('state') or '').upper()
    snap = _d(r.get('snapshot_date'))
    nxt = _d(r.get('next_check_date'))
    if state == 'DEAD':
        return PAUSE, (
            f"{text} is DEAD on the ladder — it took its settled clicks and never ordered, so "
            f"the ladder's first rung fired and it carries no re-check date. Nothing is testing "
            f"it and nothing is pending. It is still enabled and still spending "
            f"${num(r.get('cost_per_day'), 0):.2f}/day => pause it.")
    if state == 'PARKED':
        if nxt and snap and nxt >= snap:
            return 'APPOINTMENT_PENDING', (
                f"No sheet row: {text} is parked with a re-verdict appointment on {nxt}, which "
                f"has not arrived. The revive cycle is still testing it — that is a seat, not a "
                f"leak, and the register should be showing it as one.")
        due = f"was due to be re-judged on {nxt} and that date has passed" if nxt else \
              "carries no re-verdict date at all"
        return PAUSE, (
            f"{text} is parked and {due}, so nothing is testing it. It is still enabled and "
            f"still spending ${num(r.get('cost_per_day'), 0):.2f}/day => pause it.")
    return 'NOT_A_CLOSED_STATE', (
        f"No sheet row: {text} reads {state} on the ladder, which is not a closed state. A leak "
        f"is DEAD or parked-past-appointment; this row does not belong in the LEAK set and the "
        f"register needs a look.")


# ── the negate rule ───────────────────────────────────────────────────────────────────────────

def classify_negate(c, today):
    """One negate candidate in, one (disposition, reason) out. The evidence read here is the
    BLOCK grain — everything the ad group earned from this term, summed across every product and
    every keyword — because that is exactly what a negative switches off."""
    term = c['search_term']
    where = f"in {c['campaign_name']} (ad group {c['ad_group_id']})"
    hold = _d(c.get('holdout_eligible_from'))
    if hold and today >= hold:
        return 'HOLDOUT_EXCLUDED', (
            f"No sheet row: \"{term}\" {where} sits in a campaign in the HOLDOUT arm since "
            f"{hold}, which gets no sheet row of any kind.")
    if b(c.get('is_brand_defense')):
        return 'DEFENSE_EXEMPT', (
            f"No sheet row: \"{term}\" {where} is under brand defense, which is never negated.")
    if b(c.get('already_negated')):
        return 'ALREADY_NEGATED', (
            f"No sheet row: \"{term}\" is already registered as a negative on this campaign, so "
            f"a second one would bounce as a duplicate.")
    orders = num(c.get('ng_orders_8w'), 0)
    np8 = num(c.get('ng_net_profit_8w'), 0)
    lt = num(c.get('ng_lt_net_profit'), 0)
    organic = num(c.get('ng_organic_units_8w'), 0)
    clicks = num(c.get('ng_clicks_8w'), 0)
    recent = num(c.get('ng_clicks_recent_5d'), 0)
    floor = num(c.get('min_clicks'), 0)
    if orders > 0 or np8 >= 0:
        return 'EARNS_AT_BLOCK_GRAIN', (
            f"No sheet row: across everything this ad group runs, \"{term}\" took "
            f"{int(clicks)} clicks, {int(orders)} order(s) and ${np8:.2f} net over the eight-week "
            f"window. A negative switches the term off for every product and every keyword in "
            f"the group, so it may not fall on a term the ad group earns on.")
    if lt >= 0:
        return 'PAID_ITS_KEEP_LIFETIME', (
            f"No sheet row: \"{term}\" is ${np8:.2f} down over eight weeks but ${lt:.2f} UP over "
            f"its whole lifetime {where}. A block is permanent, so a term that has paid its keep "
            f"here is a bid or a season problem, never a blacklist.")
    if organic > 0:
        return 'SELLS_ORGANICALLY', (
            f"No sheet row: \"{term}\" bought {int(organic)} organic unit(s) for the products "
            f"this ad group advertises. Blocking the ad would not stop the search selling, and "
            f"the organic guard keeps the term alive.")
    if clicks < floor:
        return 'TOO_FEW_CLICKS', (
            f"No sheet row: \"{term}\" has only {int(clicks)} clicks {where} over eight weeks, "
            f"under the coach's published click floor of {int(floor)}. There is not enough "
            f"evidence to make a permanent block.")
    if recent <= 0:
        return 'NOT_BLEEDING_NOW', (
            f"No sheet row: \"{term}\" has taken no click {where} in the last five complete "
            f"days. It is not bleeding today, so nothing needs blocking today.")
    own = num(c.get('own_kw_clicks_8w'), 0)
    self_target = (target_asin(c.get('target_text')) is not None
                   and target_asin(c.get('target_text')) == str(term).strip().upper())
    if self_target and own >= clicks:
        return 'SELF_TARGET_PAUSE_COVERS', (
            f"No sheet row: \"{term}\" is the very ASIN this product target buys, and all "
            f"{int(clicks)} of the ad group's clicks on it came from that one target — the "
            f"pause on the same sheet removes every dollar a negative would. Blocking the ASIN "
            f"an ad group deliberately targets is a contradiction, not a saving.")
    kind = NEGATE_TARGET if is_asin_term(term) else NEGATE_KEYWORD
    what = "negative product target" if kind == NEGATE_TARGET else "negative keyword"
    extra = ''
    if self_target:
        extra = (f" {int(clicks - own)} of its clicks come from other targets in the group, which "
                 f"the pause does not touch.")
    return kind, (
        f"\"{term}\" took {int(clicks)} clicks and ${abs(np8):.2f} net loss {where} over eight "
        f"weeks with {int(orders)} orders, ${abs(lt):.2f} net loss over its whole lifetime here, "
        f"no organic sales, and it is still drawing clicks ({int(recent)} in the last five "
        f"complete days) => add it as a {what} on the ad group.{extra}")


# ── sheet rows ────────────────────────────────────────────────────────────────────────────────

def sp_negative_keyword_row(c, portfolio_id):
    row = {h: '' for h in SP_HEADERS}
    row.update({
        'Product': 'Sponsored Products',
        'Entity': 'Negative Keyword',
        'Operation': 'Create',
        'Campaign ID': str(c['campaign_id']),
        'Ad Group ID': str(c['ad_group_id'] or ''),
        'Portfolio ID': str(portfolio_id or ''),
        'Campaign Name (Informational only)': c['campaign_name'],
        'Keyword Text': str(c['search_term']),
        'Match Type': 'negativeExact',
        'State': 'ENABLED',
    })
    return row


def sp_negative_target_row(c, portfolio_id):
    row = {h: '' for h in SP_HEADERS}
    row.update({
        'Product': 'Sponsored Products',
        'Entity': 'Negative Product Targeting',
        'Operation': 'Create',
        'Campaign ID': str(c['campaign_id']),
        'Ad Group ID': str(c['ad_group_id'] or ''),
        'Portfolio ID': str(portfolio_id or ''),
        'Campaign Name (Informational only)': c['campaign_name'],
        'Product Targeting Expression': f'asin="{str(c["search_term"]).strip().upper()}"',
        'State': 'ENABLED',
    })
    return row


def sb_negative_keyword_row(c, portfolio_id):
    row = {h: '' for h in SB_HEADERS}
    row.update({
        'Product': 'Sponsored Brands',
        'Entity': 'Negative Keyword',
        'Operation': 'Create',
        'Campaign Id': str(c['campaign_id']),
        'Ad Group Id': str(c['ad_group_id'] or ''),
        'Portfolio Id': str(portfolio_id or ''),
        'Keyword Text': str(c['search_term']),
        'Match Type': 'negativeExact',
        'State': 'enabled',
    })
    return row


# ── SQL ───────────────────────────────────────────────────────────────────────────────────────

# ── the basis window ──────────────────────────────────────────────────────────────────────────
# ONE definition of the watermark, shared by both queries, and it is the REGISTER'S (see
# V_FAMILY_SEAT_REGISTER.sql: LEAST(MAX(date), FN_ADS_ANCHOR_CAP())). FN_ADS_ANCHOR_CAP is a
# wall-clock routine: before 22:00 Los Angeles it caps the anchor at YESTERDAY, so for 22 hours of
# every day it sits one day behind MAX(date). A book anchored on a bare MAX(date) therefore prints
# the register's cost_per_day — measured on the capped week — beside its own 7-day spend measured
# on the uncapped week, in the same row of the same query, and its README states a watermark the
# dollars did not come from. The shipped book seat_moves_20260822_0431 was built at 21:31 LA and
# is inside that gap: its 16 rows carry the week ending 2026-08-20 in cost_per_day and the week
# ending 2026-08-21 in spend_7d.
WM_CTE = """WITH wm AS (
  SELECT LEAST(MAX(date), `{p}.OI.FN_ADS_ANCHOR_CAP`()) AS wm,
         DATE_SUB(LEAST(MAX(date), `{p}.OI.FN_ADS_ANCHOR_CAP`()), INTERVAL 1 DAY) AS win_end
  FROM `{p}.OI.FACT_AMAZON_ADS`
),"""

LEAK_SQL = WM_CTE + """
lk AS (
  SELECT campaign_id, keyword_id, family, campaign_name, target_text, match_type, state,
         current_bid, bid_floor, cost_per_day, holdout, holdout_eligible_from
  FROM `{p}.OI.{register}`
  WHERE row_type = 'LEAK'
),
ks AS (
  SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
         snapshot_date, next_check_date, ad_group_id, channel, is_auto, is_pt,
         is_brand_defense, state_reason, settled_clk90, settled_ord90
  FROM `{p}.OI.FACT_KEYWORD_STATE`
),
-- Amazon's own record of whether the switch is still on. Two independent readings; a row is
-- treated as serving only when the ones that exist agree on ENABLED.
kwsrc AS (
  SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
         UPPER(COALESCE(state, '')) st
  FROM `{p}.OI.V_SRC_AmazonAds_keyword`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id, keyword_id ORDER BY date DESC) = 1
),
dimk AS (
  SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
         UPPER(COALESCE(state, '')) st
  FROM `{p}.OI.DIM_KEYWORD`
  WHERE is_current
),
-- last NON-NULL portfolio (the echo) and the latest row's portfolio (NULL = the caveat)
restore AS (
  SELECT CAST(campaign_id AS STRING) cid,
         ARRAY_AGG(portfolio_id IGNORE NULLS ORDER BY date DESC LIMIT 1)[SAFE_OFFSET(0)] AS portfolio_id,
         ARRAY_AGG(portfolio_id ORDER BY date DESC LIMIT 1)[SAFE_OFFSET(0)] AS latest_portfolio_id
  FROM `{p}.OI.V_SRC_AmazonAds_campaign_history`
  GROUP BY 1
),
camp AS (
  SELECT CAST(campaign_id AS STRING) cid, ANY_VALUE(campaign_type) campaign_type
  FROM `{p}.OI.V_DIM_CAMPAIGN_CURRENT` GROUP BY 1
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
sp7 AS (
  SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
         SUM(Ads_cost) sp7, SUM(Ads_clicks) clk7
  FROM `{p}.OI.FACT_AMAZON_ADS`, wm
  WHERE date BETWEEN DATE_SUB(wm.wm, INTERVAL 7 DAY) AND DATE_SUB(wm.wm, INTERVAL 1 DAY)
    AND keyword_id IS NOT NULL
  GROUP BY 1, 2
)
SELECT
  lk.campaign_id, lk.keyword_id, lk.family, lk.campaign_name, lk.target_text, lk.match_type,
  lk.state, lk.current_bid, lk.bid_floor, lk.cost_per_day,
  ks.snapshot_date, ks.next_check_date, ks.ad_group_id, ks.channel, camp.campaign_type,
  COALESCE(ks.is_auto, FALSE) AS is_auto, COALESCE(ks.is_pt, FALSE) AS is_pt,
  COALESCE(ks.is_brand_defense, FALSE) AS is_brand_defense,
  ks.state_reason, ks.settled_clk90, ks.settled_ord90,
  -- one live reading: they agree today, and a disagreement must never read as ENABLED
  CASE WHEN kwsrc.st IS NULL AND dimk.st IS NULL THEN ''
       WHEN COALESCE(kwsrc.st, dimk.st) = 'ENABLED' AND COALESCE(dimk.st, kwsrc.st) = 'ENABLED'
         THEN 'ENABLED'
       ELSE COALESCE(NULLIF(kwsrc.st, 'ENABLED'), NULLIF(dimk.st, 'ENABLED'), 'ENABLED')
  END AS live_state,
  kwsrc.st AS live_state_feed, dimk.st AS live_state_dim,
  restore.portfolio_id AS echo_portfolio_id, restore.latest_portfolio_id,
  hold.eligible_from AS holdout_eligible_from,
  bc.gate_reason AS block_cut_reason,
  -- rounded so the audit CSV is byte-reproducible: a distributed SUM of FLOAT64 is not
  -- associative, so the same query on the same rows returns 12.98 on one run and
  -- 12.979999999999999 on the next, and a reviewer diffing two builds of the same snapshot would
  -- see a change that is not one
  ROUND(COALESCE(sp7.sp7, 0), 4) AS sp7, COALESCE(sp7.clk7, 0) AS clk7,
  CAST(wm.wm AS STRING) AS watermark,
  CAST(CURRENT_DATE('America/Los_Angeles') AS STRING) AS today_la
FROM lk
LEFT JOIN ks ON ks.cid = lk.campaign_id AND ks.kid = lk.keyword_id
LEFT JOIN kwsrc ON kwsrc.cid = lk.campaign_id AND kwsrc.kid = lk.keyword_id
LEFT JOIN dimk ON dimk.cid = lk.campaign_id AND dimk.kid = lk.keyword_id
LEFT JOIN camp ON camp.cid = lk.campaign_id
LEFT JOIN restore ON restore.cid = lk.campaign_id
LEFT JOIN hold ON hold.cid = lk.campaign_id
LEFT JOIN bc ON bc.keyword_text = lk.target_text
            AND NOT COALESCE(ks.is_auto, FALSE) AND NOT COALESCE(ks.is_pt, FALSE)
LEFT JOIN sp7 ON sp7.cid = lk.campaign_id AND sp7.kid = lk.keyword_id
CROSS JOIN wm
-- HOUSE RULE 9 — a TOTAL ordering. cost_per_day is rounded to 4 decimals in the register, so ties
-- are ordinary (two leaks sat at exactly 0.0314 on the first live build and swapped places between
-- two runs of the same snapshot, moving four workbook lines and the README's 'row N' pointers).
-- The sibling reprice book orders totally for the same reason; a reviewer must be able to re-run
-- this generator on the same snapshot and diff the workbook byte for byte.
ORDER BY lk.cost_per_day DESC, lk.campaign_id, lk.keyword_id
"""

NEGATE_SQL = WM_CTE + """
-- the coach's published GLOBAL click floor, read (never restated). The strictest of the global
-- rows is used: this is a SECOND floor over the per-strategy one the engine already applied.
clkfloor AS (
  SELECT MAX(threshold_value) AS min_clicks
  FROM `{p}.OI.DE_COACH_THRESHOLDS`
  WHERE threshold_key = 'INSUFFICIENT_DATA_CLICKS' AND strategy_id = 'GLOBAL'
),
lk AS (
  SELECT campaign_id, keyword_id, family, campaign_name, target_text, state,
         holdout_eligible_from
  FROM `{p}.OI.{register}`
  WHERE row_type = 'LEAK'
),
cand AS (
  SELECT CAST(n.campaign_id AS STRING) campaign_id, CAST(n.keyword_id AS STRING) keyword_id,
         CAST(n.ad_group_id AS STRING) ad_group_id,
         LOWER(n.search_term) AS search_term,
         ANY_VALUE(n.campaign_name) campaign_name, ANY_VALUE(n.reason) engine_reason
  FROM `{p}.OI.{negates}` n
  JOIN lk ON lk.campaign_id = CAST(n.campaign_id AS STRING)
         AND lk.keyword_id = CAST(n.keyword_id AS STRING)
  WHERE n.search_term IS NOT NULL AND n.ad_group_id IS NOT NULL
  GROUP BY 1, 2, 3, 4
),
-- ── THE GRAIN A NEGATIVE ACTUALLY ACTS ON, re-derived here from the fact table.
-- Summed across every product and every keyword in the ad group. Nothing below is ASIN-sliced.
blk AS (
  SELECT CAST(f.campaign_id AS STRING) campaign_id, CAST(f.ad_group_id AS STRING) ad_group_id,
         LOWER(f.search_term) search_term,
         SUM(f.Ads_clicks) ng_clicks_8w,
         SUM(f.Ads_orders) ng_orders_8w,
         SUM(f.Ads_cost)   ng_spend_8w,
         SUM(f.GROSS_PROFIT) - SUM(f.Ads_cost) AS ng_net_profit_8w,
         SUM(IF(f.date >= DATE_SUB(wm.win_end, INTERVAL 4 DAY), f.Ads_clicks, 0)) ng_clicks_recent_5d
  FROM `{p}.OI.FACT_AMAZON_ADS` f CROSS JOIN wm
  WHERE f.date BETWEEN DATE_SUB(wm.win_end, INTERVAL 55 DAY) AND wm.win_end
    AND f.search_term IS NOT NULL AND f.search_term != '' AND f.ad_group_id IS NOT NULL
  GROUP BY 1, 2, 3
),
blk_lt AS (
  SELECT CAST(f.campaign_id AS STRING) campaign_id, CAST(f.ad_group_id AS STRING) ad_group_id,
         LOWER(f.search_term) search_term,
         SUM(f.Ads_clicks) ng_lt_clicks, SUM(f.Ads_orders) ng_lt_orders,
         SUM(f.GROSS_PROFIT) - SUM(f.Ads_cost) AS ng_lt_net_profit
  FROM `{p}.OI.FACT_AMAZON_ADS` f
  WHERE f.search_term IS NOT NULL AND f.search_term != '' AND f.ad_group_id IS NOT NULL
  GROUP BY 1, 2, 3
),
-- the leak keyword's OWN share of the block-grain clicks: how much of it the pause already takes
own AS (
  SELECT CAST(f.campaign_id AS STRING) campaign_id, CAST(f.ad_group_id AS STRING) ad_group_id,
         CAST(f.keyword_id AS STRING) keyword_id, LOWER(f.search_term) search_term,
         SUM(f.Ads_clicks) own_kw_clicks_8w
  FROM `{p}.OI.FACT_AMAZON_ADS` f CROSS JOIN wm
  WHERE f.date BETWEEN DATE_SUB(wm.win_end, INTERVAL 55 DAY) AND wm.win_end
    AND f.search_term IS NOT NULL AND f.ad_group_id IS NOT NULL
  GROUP BY 1, 2, 3, 4
),
-- the organic guard, group-wide: organic purchases on the search across EVERY product the group
-- advertises, minus what the ads themselves booked
slice_asin AS (
  SELECT DISTINCT CAST(f.campaign_id AS STRING) campaign_id,
         CAST(f.ad_group_id AS STRING) ad_group_id, LOWER(f.search_term) search_term,
         COALESCE(f.most_advertised_asin_impressions, f.ASIN_BY_CAMPAIGN_NAME) asin
  FROM `{p}.OI.FACT_AMAZON_ADS` f CROSS JOIN wm
  WHERE f.date BETWEEN DATE_SUB(wm.win_end, INTERVAL 55 DAY) AND wm.win_end
    AND f.search_term IS NOT NULL AND f.ad_group_id IS NOT NULL
),
sqp AS (
  SELECT LOWER(query_text) search_term, ASIN asin, SUM(conversions) sqp_orders_8w
  FROM `{p}.OI.FACT_SEARCH_QUERY`
  WHERE data_source = 'SQP'
    AND week_end_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 56 DAY)
  GROUP BY 1, 2
),
organic AS (
  SELECT s.campaign_id, s.ad_group_id, s.search_term,
         SUM(COALESCE(q.sqp_orders_8w, 0)) sqp_orders_8w
  FROM slice_asin s LEFT JOIN sqp q ON q.search_term = s.search_term AND q.asin = s.asin
  GROUP BY 1, 2, 3
),
already_kw AS (
  SELECT DISTINCT CAST(nk.campaign_id AS STRING) campaign_id, LOWER(c.search_term) search_term
  FROM cand c
  JOIN `{p}.OI.DE_NEGATIVE_KEYWORDS` nk ON nk.campaign_id = c.campaign_id
  WHERE nk.removed_at IS NULL
    AND UPPER(COALESCE(nk.state, 'ENABLED')) NOT IN ('ARCHIVED', 'REMOVED', 'PAUSED')
    AND ((UPPER(COALESCE(nk.match_type, '')) LIKE '%EXACT%'
          AND LOWER(nk.keyword_text) = LOWER(c.search_term))
      OR (UPPER(COALESCE(nk.match_type, '')) LIKE '%PHRASE%'
          AND STRPOS(LOWER(c.search_term), LOWER(nk.keyword_text)) > 0))
),
already_tg AS (
  SELECT DISTINCT CAST(nt.campaign_id AS STRING) campaign_id, LOWER(c.search_term) search_term
  FROM cand c
  JOIN `{p}.OI.DE_NEGATIVE_TARGETS` nt ON nt.campaign_id = c.campaign_id
  WHERE nt.removed_at IS NULL
    AND UPPER(COALESCE(nt.state, 'ENABLED')) NOT IN ('ARCHIVED', 'REMOVED', 'PAUSED')
    AND UPPER(REGEXP_EXTRACT(nt.targeting_expression, r'(?i)asin="?([A-Za-z0-9]+)"?'))
        = UPPER(c.search_term)
),
restore AS (
  SELECT CAST(campaign_id AS STRING) cid,
         ARRAY_AGG(portfolio_id IGNORE NULLS ORDER BY date DESC LIMIT 1)[SAFE_OFFSET(0)] AS portfolio_id
  FROM `{p}.OI.V_SRC_AmazonAds_campaign_history`
  GROUP BY 1
),
hold AS (
  SELECT CAST(unit_id AS STRING) cid, MIN(eligible_from) eligible_from
  FROM `{p}.OI.DE_HOLDOUT_ASSIGNMENT`
  WHERE arm = 'HOLDOUT' AND unit_type = 'CAMPAIGN' GROUP BY 1
),
ks AS (
  SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
         channel, COALESCE(is_pt, FALSE) is_pt, COALESCE(is_brand_defense, FALSE) is_brand_defense
  FROM `{p}.OI.FACT_KEYWORD_STATE`
),
camp AS (
  SELECT CAST(campaign_id AS STRING) cid, ANY_VALUE(campaign_type) campaign_type
  FROM `{p}.OI.V_DIM_CAMPAIGN_CURRENT` GROUP BY 1
)
SELECT
  c.campaign_id, c.keyword_id, c.ad_group_id, c.search_term, c.campaign_name, c.engine_reason,
  lk.family, lk.target_text, lk.state AS leak_state,
  ks.channel, camp.campaign_type, ks.is_pt AS leak_is_pt, ks.is_brand_defense,
  COALESCE(blk.ng_clicks_8w, 0) ng_clicks_8w,
  COALESCE(blk.ng_orders_8w, 0) ng_orders_8w,
  ROUND(COALESCE(blk.ng_spend_8w, 0), 2) ng_spend_8w,
  ROUND(COALESCE(blk.ng_net_profit_8w, 0), 2) ng_net_profit_8w,
  COALESCE(blk.ng_clicks_recent_5d, 0) ng_clicks_recent_5d,
  COALESCE(blk_lt.ng_lt_clicks, 0) ng_lt_clicks,
  COALESCE(blk_lt.ng_lt_orders, 0) ng_lt_orders,
  ROUND(COALESCE(blk_lt.ng_lt_net_profit, 0), 2) ng_lt_net_profit,
  GREATEST(0, COALESCE(o.sqp_orders_8w, 0) - COALESCE(blk.ng_orders_8w, 0)) ng_organic_units_8w,
  COALESCE(own.own_kw_clicks_8w, 0) own_kw_clicks_8w,
  (already_kw.campaign_id IS NOT NULL OR already_tg.campaign_id IS NOT NULL) already_negated,
  restore.portfolio_id AS echo_portfolio_id,
  hold.eligible_from AS holdout_eligible_from,
  clkfloor.min_clicks,
  CAST(wm.wm AS STRING) AS watermark
FROM cand c
CROSS JOIN wm CROSS JOIN clkfloor
JOIN lk ON lk.campaign_id = c.campaign_id AND lk.keyword_id = c.keyword_id
LEFT JOIN ks ON ks.cid = c.campaign_id AND ks.kid = c.keyword_id
LEFT JOIN camp ON camp.cid = c.campaign_id
LEFT JOIN blk ON blk.campaign_id = c.campaign_id AND blk.ad_group_id = c.ad_group_id
             AND blk.search_term = c.search_term
LEFT JOIN blk_lt ON blk_lt.campaign_id = c.campaign_id AND blk_lt.ad_group_id = c.ad_group_id
                AND blk_lt.search_term = c.search_term
LEFT JOIN own ON own.campaign_id = c.campaign_id AND own.ad_group_id = c.ad_group_id
             AND own.keyword_id = c.keyword_id AND own.search_term = c.search_term
LEFT JOIN organic o ON o.campaign_id = c.campaign_id AND o.ad_group_id = c.ad_group_id
                   AND o.search_term = c.search_term
LEFT JOIN already_kw ON already_kw.campaign_id = c.campaign_id
                    AND already_kw.search_term = c.search_term
LEFT JOIN already_tg ON already_tg.campaign_id = c.campaign_id
                    AND already_tg.search_term = c.search_term
LEFT JOIN restore ON restore.cid = c.campaign_id
LEFT JOIN hold ON hold.cid = c.campaign_id
-- a total ordering here too (house rule 9): ng_spend_8w is rounded to cents and ties freely
ORDER BY blk.ng_spend_8w DESC, c.campaign_id, c.ad_group_id, c.search_term, c.keyword_id
"""



def routing_note(campaign_name, is_sb):
    """The README's sheet check: a campaign whose NAME reads as one channel while Amazon has it as
    the other.

    The routing itself is already right — the campaign DIMENSION is the authority and the ladder's
    channel is the fallback, with a disagreement raised rather than resolved. But this README is
    the only human-readable cross-reference a reader gets: Amazon's SB Multi Ad Group schema has no
    campaign-name column, so every SB line in the workbook is bare ids (Campaign Id / Ad Group Id /
    Keyword Id / State). Read cold, an SP-named campaign under the SB heading looks like a misroute,
    and "fixing" it puts an SP row in an SB campaign, which fails the whole upload. So the
    disagreement is stated on the row instead of being left for the reader to find.

    The channel is matched as a WORD, never a substring — 'SPRING' is not SP.
    """
    name = (campaign_name or '').upper()
    name_sb = bool(re.search(r'\bSB\b', name))
    name_sp = bool(re.search(r'\bSP\b', name))
    if is_sb and name_sp and not name_sb:
        return ("This campaign is NAMED SP but Amazon has it as a Sponsored Brands campaign (the "
                "campaign dimension and the keyword ladder agree), so the row belongs on the SB "
                "sheet exactly where it is. Do not move it to the Sponsored Products sheet — an SP "
                "row for an SB campaign fails the whole upload.")
    if not is_sb and name_sb and not name_sp:
        return ("This campaign is NAMED SB but Amazon has it as a Sponsored Products campaign, so "
                "the row belongs on the SP sheet exactly where it is. Do not move it.")
    return None



# ── the README ────────────────────────────────────────────────────────────────────────────────
# The README is the only human-readable cross-reference a reader gets for this workbook: Amazon's
# SB Multi Ad Group schema has no campaign-name column, so every SB line is bare ids. It is written
# from a list of plain dicts — one per visible row — so the SAME writer can be re-run over an audit
# CSV of a book already logged (--rewrite-readme), which is how a README on disk gains a note the
# writer learned after it was written. Building another book to regenerate it is exactly what the
# register's LEAK rows forbid.

def basis_window(watermark):
    """The seven COMPLETE days the register prices on, from its anchor. The anchor is the last
    complete ads day; the window ENDS THE DAY BEFORE it (V_FAMILY_SEAT_REGISTER's win CTE:
    basis_from = wm - 7, basis_to = wm - 1). Stating only the anchor is how a book came to claim
    watermark 2026-08-22 while every dollar in it was measured on 2026-08-14..2026-08-20."""
    from datetime import timedelta
    wm = date.fromisoformat(str(watermark)[:10])
    return ((wm - timedelta(days=7)).isoformat(), (wm - timedelta(days=1)).isoformat())


def readme_row(r, disp, reason, kind, line_of, key_of, is_sb):
    sheet, line = line_of.get(key_of(r, disp), ('', ''))
    return {
        'kind': kind, 'disp': disp, 'reason': reason, 'sheet': sheet, 'line': line,
        'is_sb': bool(is_sb(r)),
        'campaign_name': r.get('campaign_name'),
        'target_text': r.get('target_text'), 'search_term': r.get('search_term'),
        'cost_per_day': num(r.get('cost_per_day'), 0) if kind == 'LEAK' else 0.0,
    }


def write_readme(readme_path, out_name, batch_id, watermark, today_la, no_log, rows,
                 had_negate_candidates, built_at=None, prior_watermark=None):
    leak_rows = [x for x in rows if x['kind'] == 'LEAK']
    neg_rows = [x for x in rows if x['kind'] == 'NEGATE']
    pauses = [x for x in rows if x['disp'] == PAUSE]
    negates = [x for x in rows if x['disp'] in (NEGATE_KEYWORD, NEGATE_TARGET)]
    executable = pauses + negates
    paused_spend = sum(x['cost_per_day'] for x in pauses)
    stamp = f"{datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}"
    # a rewrite may correct the week a README STATES, and must say when it does: the dollars in
    # the audit never move, only the sentence that names the window they came from
    corrected = ''
    if prior_watermark and str(prior_watermark).strip() != str(watermark).strip():
        corrected = (f" This file previously stated {prior_watermark} as the watermark; that was "
                     f"the raw MAX(date) of the ads table rather than the register's anchor, and "
                     f"it named a week the dollars did not come from. Not one figure changed.")
    with open(readme_path, 'w') as f:
        f.write("# The leak book — what each row does and why\n\n")
        if built_at:
            f.write(f"Built {built_at} from `{out_name}` (ads watermark {watermark}, register of "
                    f"{today_la}); this file REWRITTEN {stamp} from the book's own audit CSV — "
                    f"the rows and the batch are unchanged, only the wording of this file. "
                    f"Change-log batch: **`{batch_id}`**.\n\n")
        else:
            f.write(f"Built {stamp} from `{out_name}` "
                    f"(ads watermark {watermark}, register of {today_la}). Change-log batch: "
                    f"**`{batch_id}`**{' (NOT logged — --no-log)' if no_log else ''}.\n\n")
        f.write("**What a leak is.** The family seat register calls a keyword a LEAK when the "
                "ladder has CLOSED it — it is DEAD (it took its settled clicks and never "
                "ordered) or it is parked past the date the revive cycle was due to re-judge it "
                "— and it is still taking money. Nothing is testing a leak and nothing is "
                "pending on one. This book switches them off.\n\n")
        f.write("**Why these pauses are executable.** The ladder's only probation-gated kill is "
                "LOSER: a keyword below its bar that is still ordering may only be paused after "
                "it has sat at its floor and failed there, and the reprice book owns that row. "
                "DEAD is a different rung and a different question — zero orders on settled "
                "clicks, fired whatever the bid, with no re-check date. A parked keyword past "
                "its appointment has had its test and it lapsed. Neither waits on probation.\n\n")
        try:
            b_from, b_to = basis_window(watermark)
            window = f"the seven complete days {b_from} to {b_to}"
        except (ValueError, TypeError):
            window = "the seven complete days ending the day before the watermark above"
        f.write(f"**The week these dollars are measured on: {window}.** The watermark above is "
                f"the register's ANCHOR — the last complete ads day (the current Los Angeles day "
                f"only counts once it is past 22:00 there) — and the basis window ends the day "
                f"BEFORE it. Every figure in this file is measured on that week — the book's OWN "
                f"window, fixed the moment it was built. The register is not frozen: it re-anchors "
                f"every day (LEAST(MAX(date), FN_ADS_ANCHOR_CAP())), so from the next complete ads "
                f"day its cost_per_day is a different week from this file's, and a dollar here "
                f"that no longer matches the register is the window moving, not an error. Compare "
                f"a row against the register of {today_la} only; the audit CSV carries the window "
                f"on every row.{corrected}\n\n")
        n_noact = len(leak_rows) - len(pauses)
        f.write(f"**{len(pauses)} pause row(s)** covering ${paused_spend:.2f}/day of spend on the "
                f"7-day basis window, and **{len(negates)} negative(s)**. "
                + (f"{n_noact} leak row(s) get no pause; the rule that stopped each is listed "
                   f"below.\n\n" if n_noact else
                   "Every leak row on the register today has a pause row on this sheet.\n\n"))
        f.write("**Why a negative sits beside a pause.** They act at different grains. The pause "
                "switches off one target. A negative switches the search term off for EVERY "
                "keyword and EVERY product in the ad group, which is also why its evidence is "
                "summed at the ad group and never sliced by ASIN: blocking a term off one "
                "product's slice throws away whatever the other slices earn from it. A negative "
                "is refused here whenever the ad group took an order on the term, is net "
                "positive on it over the window or over its whole lifetime, sells it "
                "organically, has too few clicks on it, or has stopped drawing clicks.\n\n")
        f.write("**A negative cannot be undone by a sheet.** The restore sheet next to this file "
                "re-enables every keyword this book pauses, and that is all it can do. A "
                "negative keyword or negative product target is CREATED by this sheet without an "
                "id; removing it later needs the id Amazon assigns on creation, and this "
                "warehouse's negative-keyword feed has been frozen since 2026-01-03 "
                "(`DE_NEGATIVE_KEYWORDS` is the registry of record precisely because the feed "
                "stopped). So the id never comes back on its own. Treat every negative on this "
                "sheet as permanent: if you are not sure, delete the line.\n\n")
        f.write("**This book never counts a negative as money recovered today.** The register's "
                "gap-closure arithmetic (ruling R-l) counts pauses only, because only a pause "
                "provably takes a keyword's spend to zero on upload. The dollars beside each "
                "negative are what the ad group has already lost on the term, not a saving.\n\n")
        f.write("**Holdout.** Campaigns in the HOLDOUT arm get no row of any kind from their "
                "eligible_from date. Every executable row is asserted against the arm before the "
                "sheet is written.\n\n")
        f.write(f"**Provenance.** The batch `{batch_id}` in FACT_PPC_CHANGE_LOG holds exactly the "
                f"{len(executable)} rows on this sheet (read back and asserted). If you do NOT "
                f"upload this book, label the batch `SUPERSEDED_NEVER_UPLOADED` by running this "
                f"file with `--supersede {batch_id}` — it labels and stops, building nothing, and "
                f"a log row is never deleted. If you delete a line before uploading, label that "
                f"row `FAILED_UPLOAD`. When you have uploaded it, run this file with "
                f"`--mark-uploaded {batch_id}`. **One leak book at a time.** If the register "
                f"shows a leak this book does not carry (it says the book is STALE and every leak "
                f"row reads 'rebuild the leak book'), do not upload this file: run this generator "
                f"with `--replaces {batch_id}` — it logs ONE new book carrying every leak and "
                f"labels this batch as replaced by it. A label is only ever written on "
                f"PENDING_UPLOAD rows; a batch you have marked uploaded is never touched.\n\n")
        f.write("---\n\n## Pauses — row by row\n\n")
        for x in leak_rows:
            if x['disp'] != PAUSE:
                continue
            f.write(f"### {x['sheet']} — row {x['line']}: `{x['target_text']}` "
                    f"({x['campaign_name']})\n\n")
            f.write(f"- {x['reason']}\n")
            note = routing_note(x['campaign_name'], x['is_sb'])
            if note:
                f.write(f"- **Sheet check.** {note}\n")
            f.write("- Delete this line and it keeps running exactly as it is; then label its "
                    "change-log row FAILED_UPLOAD.\n\n")
        no_action = [x for x in leak_rows if x['disp'] != PAUSE]
        if no_action:
            f.write(f"---\n\n## Leaks with no row today ({len(no_action)}) — and the rule that "
                    f"stopped each\n\n")
            for x in no_action:
                f.write(f"- **{x['disp']}** — {x['reason']}\n")
            f.write("\n")
        if negates:
            f.write("---\n\n## Negatives — row by row (permanent; delete any you are unsure of)\n\n")
            for x in neg_rows:
                if x['disp'] not in EXECUTABLE:
                    continue
                f.write(f"### {x['sheet']} — row {x['line']}: `{x['search_term']}` "
                        f"({x['campaign_name']})\n\n")
                f.write(f"- {x['reason']}\n")
                note = routing_note(x['campaign_name'], x['is_sb'])
                if note:
                    f.write(f"- **Sheet check.** {note}\n")
                f.write("\n")
        neg_no = [x for x in neg_rows if x['disp'] not in EXECUTABLE]
        if neg_no:
            f.write(f"---\n\n## Negate candidates refused ({len(neg_no)}) — and why\n\n")
            for x in neg_no:
                f.write(f"- **{x['disp']}** — {x['reason']}\n")
            f.write("\n")
        if not had_negate_candidates:
            f.write("---\n\n## Negatives\n\nNo search term under any leaking keyword is on the "
                    "engine's negate list today, so this book carries no negative.\n\n")
    return readme_path


PRIOR_HEADER_RE = re.compile(
    r'Built (?P<built>[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} UTC).*?'
    r'ads watermark (?P<wm>[^,]+), register of (?P<day>[^)]+)' + re.escape(')') +
    r'.*?batch: ' + re.escape('**`') + r'(?P<batch>[^`]+)' + re.escape('`**'), re.S)


def prior_readme_facts(readme_path):
    """The build facts of the README being replaced: when it was built, the window it was measured
    on, and its batch. A rewrite may never invent any of them — for a book built before the audit
    CSV carried the window, the README it is replacing is the record."""
    if not os.path.exists(readme_path):
        return {}
    m = PRIOR_HEADER_RE.search(open(readme_path).read()[:4000])
    return m.groupdict() if m else {}


def rewrite_readme_from_audit(audit_path, batch_id=None, watermark=None, today_la=None):
    """Rewrite the README beside an audit CSV, from the audit itself. No workbook, no change log,
    no batch — the audit is the record of what the book already contains, and the README is the
    only artefact that has to change when the writer learns something new."""
    rows, audit_wm, audit_day = [], [], []
    with open(audit_path, newline='') as f:
        for a in csv.DictReader(f):
            audit_wm.append((a.get('watermark') or '').strip())
            audit_day.append((a.get('register_day') or '').strip())
            rows.append({
                'kind': a['kind'], 'disp': a['disposition'], 'reason': a['reason'],
                'sheet': a['sheet'], 'line': a['excel_row'],
                # the sheet a row was WRITTEN on is the authority here: it is what the reader is
                # holding, and it is what the routing note has to explain
                'is_sb': a['sheet'] == SB_SHEET,
                'campaign_name': a['campaign'],
                'target_text': a['target'], 'search_term': a['search_term'],
                'cost_per_day': num(a.get('cost_per_day'), 0) if a['kind'] == 'LEAK' else 0.0,
            })
    stem = audit_path[:-len('_audit.csv')] if audit_path.endswith('_audit.csv') else \
        audit_path.rsplit('.', 1)[0]
    readme_path = stem + '_README.md'
    prior = prior_readme_facts(readme_path)
    wm = watermark or next((a for a in audit_wm if a), None) or prior.get('wm')
    day = today_la or next((a for a in audit_day if a), None) or prior.get('day')
    bid = batch_id or prior.get('batch') or os.path.basename(stem)
    assert wm and day, (
        f"{readme_path}: neither the audit CSV nor the README being replaced states the window "
        f"these dollars were measured on. Pass --watermark / --register-day rather than let this "
        f"file state a week it cannot prove.")
    return write_readme(readme_path, os.path.basename(stem) + '.xlsx', bid, wm, day, False, rows,
                        any(x['kind'] == 'NEGATE' for x in rows),
                        built_at=prior.get('built'), prior_watermark=prior.get('wm'))


def bq(sql):
    out = subprocess.run(
        ['bq', 'query', f'--project_id={PROJECT}', '--use_legacy_sql=false', '--nouse_cache',
         '--format=json', '--max_rows=100000', sql],
        capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"query failed:\n{out.stderr}\n{sql[:400]}")
    return json.loads(out.stdout or '[]')


def prior_unmarked_sql():
    """Earlier leak books still waiting on Ori: PENDING_UPLOAD and nothing else. A batch at NULL
    is APPLIED (Ori said so with --mark-uploaded) and is never listed as waiting — listing it was
    how the listing ate its own tail and invited a --supersede on an uploaded book."""
    return (f"SELECT batch_id, upload_status, COUNT(*) n, MIN(applied_at) first_at "
            f"FROM `{CHANGE_LOG}` WHERE batch_id LIKE 'seat_moves_%' "
            f"AND upload_status = 'PENDING_UPLOAD' "
            f"GROUP BY 1, 2 ORDER BY 4")


def prior_unmarked_batches():
    return bq(prior_unmarked_sql())


def pending_count_sql(bid):
    return (f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` "
            f"WHERE batch_id = {q(bid)} AND upload_status = 'PENDING_UPLOAD'")


def supersede_sql(bid, note):
    """Label ONE never-uploaded batch. PENDING_UPLOAD only: an applied batch (NULL) is untouched,
    a FAILED_UPLOAD row is untouched, an already-labelled row is untouched."""
    return (f"UPDATE `{CHANGE_LOG}` SET upload_status = 'SUPERSEDED_NEVER_UPLOADED', "
            f"upload_note = {q(note)} WHERE batch_id = {q(bid)} "
            f"AND upload_status = 'PENDING_UPLOAD'")


def mark_uploaded_sql(bid, note):
    return (f"UPDATE `{CHANGE_LOG}` SET upload_status = NULL, "
            f"upload_note = CONCAT(COALESCE(upload_note, ''), {q(note)}) "
            f"WHERE batch_id = {q(bid)} AND upload_status = 'PENDING_UPLOAD'")


def refuse_second_pending_book(prior, replaces):
    """A build may not log a second PENDING leak book beside one already waiting: the register
    credits a keyword's pause per pending row, so two books would hand Ori two sheets for one
    pause and the projections a double credit. The build proceeds only when it names every
    pending book it replaces (--replaces), and it may not name a book that is not pending —
    nothing is labelled blind."""
    pending = {p['batch_id'] for p in prior if p.get('upload_status') == 'PENDING_UPLOAD'}
    named = set(replaces or [])
    unnamed = sorted(pending - named)
    not_pending = sorted(named - pending)
    if unnamed:
        sys.exit(f"a leak book is already PENDING_UPLOAD: {', '.join(unnamed)}. Either upload it "
                 f"(then --mark-uploaded), label it (--supersede), or rebuild with "
                 f"--replaces {' '.join(unnamed)} so ONE book carries every leak and the old one "
                 f"is labelled as replaced by it. Nothing was built or logged.")
    if not_pending:
        sys.exit(f"--replaces {', '.join(not_pending)}: no PENDING_UPLOAD rows under that id "
                 f"(already applied, already labelled, or unknown) — nothing is labelled blind. "
                 f"Nothing was built or logged.")


def run_update(sql, what):
    out = subprocess.run(['bq', 'query', '--use_legacy_sql=false', '--nouse_cache',
                          f'--project_id={PROJECT}', sql], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"{what} failed:\n{out.stderr}")


def supersede_note(new_batch):
    """The upload_note a SUPERSEDED_NEVER_UPLOADED label carries. Two cases, two true sentences:
    a book replaced by a later one names its replacement; a book simply abandoned says so, because
    'superseded by None' would be a lie and a reader would go looking for a batch that never
    existed."""
    stamp = f"{datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}"
    if new_batch:
        return (f"never uploaded; superseded by {new_batch} ({stamp}) — labelled by the generator")
    return (f"never uploaded; no later book replaces it ({stamp}) — labelled by hand with "
            f"--supersede")


def supersede(batch_ids, new_batch=None):
    """Label never-uploaded batches. Callable WITHOUT a replacement: every LEAK row in the register
    offers Ori 'upload that book, or label it never-uploaded', and until 2026-08-23 the label had
    exactly one mechanism — the tail of a build that logged a NEW batch — so obeying the second
    half of the instruction meant building another book, which the same sentence forbids."""
    for bid in batch_ids:
        # PENDING_UPLOAD only, counted BEFORE the UPDATE: an applied batch (NULL) has zero pending
        # rows and stops here with a sentence — it is never re-labelled, because NULL means Amazon
        # has it (V_PPC_CHANGE_LOG_APPLIED). A row is never deleted.
        n_pending = int(bq(pending_count_sql(bid))[0]['n'])
        if n_pending == 0:
            sys.exit(f"--supersede {bid}: no PENDING_UPLOAD rows under that id — it is already "
                     f"applied (uploaded), already labelled, or unknown. Nothing was changed: a "
                     f"label is written on PENDING_UPLOAD rows only.")
        note = supersede_note(new_batch)
        run_update(supersede_sql(bid, note), 'supersede')
        left = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` "
                  f"WHERE batch_id = {q(bid)} AND upload_status = 'SUPERSEDED_NEVER_UPLOADED'")
        print(f"  labelled batch {bid} SUPERSEDED_NEVER_UPLOADED — {int(left[0]['n'])} row(s) "
              f"({n_pending} were pending)")
        assert int(left[0]['n']) >= n_pending, f"--supersede {bid}: fewer rows labelled than were pending"


def log_batch(rows, batch_id, readme_path):
    """Log EXACTLY the executable rows, one batch, unique id, an upload note; read the count back
    and assert it equals the sheet. A pause carries the old bid it had when it was switched off;
    a negative carries no bid at all — it is not a bid change, and NULL is the honest value."""
    exists = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` "
                f"WHERE batch_id = {q(batch_id)}")
    assert int(exists[0]['n']) == 0, f"batch id {batch_id} already exists in the change log"
    note = (f"leak book {batch_id}, built {datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}; "
            f"README {os.path.basename(readme_path)}; manual upload pending — if this book is not "
            f"uploaded set upload_status SUPERSEDED_NEVER_UPLOADED; if uploaded and a line was "
            f"deleted first, set that row FAILED_UPLOAD. A NEGATE row cannot be undone by sheet.")
    structs = []
    for r, disp, _ in rows:
        action = {PAUSE: 'KEYWORD_PAUSE', NEGATE_KEYWORD: 'NEGATE_TERM',
                  NEGATE_TARGET: 'NEGATE_TARGET'}[disp]
        cid = str(r['campaign_id'])
        kid = str(r['keyword_id'])
        targeting = r['target_text'] if disp == PAUSE else r['search_term']
        old_bid = num(r.get('current_bid')) if disp == PAUSE else None
        key = kid if disp == PAUSE else f"{kid}-{re.sub(r'[^a-z0-9]+', '-', str(targeting).lower())[:60]}"
        structs.append(
            "STRUCT("
            f"{q('seatmove-' + '-'.join(batch_id.split('_')[2:]) + '-' + cid + '-' + key)} AS change_id, "
            f"{q(batch_id)} AS batch_id, CURRENT_TIMESTAMP() AS applied_at, "
            f"{q(action)} AS action, {q(targeting)} AS targeting, "
            f"{q(kid)} AS keyword_id, {q(r.get('match_type') or '')} AS match_type, "
            f"{q(cid)} AS campaign_id, {q(r['campaign_name'])} AS campaign_name, "
            f"{q((r.get('campaign_type') or r.get('channel') or '').upper())} AS campaign_type, "
            f"{q(r.get('ad_group_id'))} AS ad_group_id, "
            f"{('CAST(' + repr(old_bid) + ' AS FLOAT64)') if old_bid is not None else 'NULL'} AS old_bid, "
            f"NULL AS new_bid, "
            f"{q('MANUAL')} AS source, {q('MANUAL_BULKSHEET')} AS coach_mode, "
            f"{q(note)} AS upload_note, {q('PENDING_UPLOAD')} AS upload_status)")
    cols = ("change_id, batch_id, applied_at, action, targeting, keyword_id, match_type, "
            "campaign_id, campaign_name, campaign_type, ad_group_id, old_bid, new_bid, source, "
            "coach_mode, upload_note, upload_status")
    run_update(f"INSERT INTO `{CHANGE_LOG}` ({cols}) "
               f"SELECT {cols} FROM UNNEST([{', '.join(structs)}])", 'change-log insert')
    back = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` "
              f"WHERE batch_id = {q(batch_id)}")
    n_logged = int(back[0]['n'])
    assert n_logged == len(rows), f"logged {n_logged} rows but the sheet holds {len(rows)}"
    return n_logged


def build_parser():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('-o', '--out', default=None,
                    help="default .tmp/seat_moves_<the warehouse's own day>.xlsx")
    ap.add_argument('--no-log', action='store_true')
    ap.add_argument('--supersede', nargs='+', default=[], metavar='BATCH_ID',
                    help='label these never-uploaded batches SUPERSEDED_NEVER_UPLOADED and stop. '
                         'Builds nothing, logs nothing — this is the executable half of the '
                         'choice the register publishes on every LEAK row.')
    ap.add_argument('--mark-uploaded', metavar='BATCH_ID',
                    help='Ori has uploaded this batch: flip its rows from PENDING_UPLOAD to '
                         'applied (NULL). Builds nothing.')
    ap.add_argument('--replaces', nargs='+', default=[], metavar='BATCH_ID',
                    help='build ONE book that carries every leak and label these PENDING leak '
                         'books SUPERSEDED_NEVER_UPLOADED as replaced by it (the label names the '
                         'new batch). A build that finds a pending leak book it does not name '
                         'stops: two pending books would credit one pause twice.')
    ap.add_argument('--change-log-table', default=LIVE_CHANGE_LOG, metavar='TABLE',
                    help='a TMP_/TEMP_ copy of FACT_PPC_CHANGE_LOG to act on instead of the live '
                         'log — the instrument that proves --supersede / --mark-uploaded leave an '
                         'applied batch alone. Any other name is refused.')
    ap.add_argument('--register-table', default=LIVE_REGISTER,
                    help='TMP_ copy of V_FAMILY_SEAT_REGISTER (proving a branch the day does not '
                         'exercise). Forces --no-log.')
    ap.add_argument('--negates-table', default=LIVE_NEGATES,
                    help='TMP_ copy of T_WEEKLY_RUN_NEGATIVE. Forces --no-log.')
    ap.add_argument('--as-of', metavar='YYYY-MM-DD',
                    help='evaluate the doctrine as if today were this date — the only way to '
                         'exercise a rule that arms in the future (the holdout arm). Allowed '
                         'ONLY together with a TMP_ source, so a live book can never be built '
                         'for a day that is not today.')
    ap.add_argument('--rewrite-readme', metavar='AUDIT_CSV',
                    help='rewrite the README beside this audit CSV with the current writer, from '
                         'the audit itself. Builds nothing, logs nothing, touches no workbook — '
                         'the way a README already on disk gains a note the writer learned after '
                         'it was written, without building a second book of the same rows.')
    ap.add_argument('--batch', metavar='BATCH_ID',
                    help='--rewrite-readme: the batch id to state. Defaults to the one the README '
                         'being replaced already states.')
    ap.add_argument('--watermark', metavar='YYYY-MM-DD',
                    help='--rewrite-readme: the ads watermark to state. Defaults to the audit '
                         'CSV, then to the README being replaced; a rewrite never invents one.')
    ap.add_argument('--register-day', metavar='YYYY-MM-DD',
                    help='--rewrite-readme: the register day to state. Same fallbacks.')
    return ap


def main():
    ap = build_parser()
    args = ap.parse_args()
    if args.change_log_table != LIVE_CHANGE_LOG:
        print(f"CHANGE LOG OVERRIDE: every statement acts on {set_change_log_table(args.change_log_table)}")

    if args.rewrite_readme:
        out = rewrite_readme_from_audit(args.rewrite_readme, batch_id=args.batch,
                                        watermark=args.watermark, today_la=args.register_day)
        print(f"\nRewrote {out} from {args.rewrite_readme}. No workbook, no batch, no upload.")
        return {'readme': out}

    # --supersede is TERMINAL: it labels and returns, building nothing. This is the executable
    # half of the choice every LEAK row publishes ('upload that book, or label it never-uploaded').
    if args.supersede:
        supersede(args.supersede)
        print(f"\nLabelled {len(args.supersede)} batch(es) SUPERSEDED_NEVER_UPLOADED. "
              f"Nothing was built and no batch was logged. The register's LEAK rows will send you "
              f"to the next leak book on the next read.")
        return {'superseded': list(args.supersede)}

    if args.mark_uploaded:
        bid = args.mark_uploaded
        n = int(bq(pending_count_sql(bid))[0]['n'])
        if n == 0:
            sys.exit(f"{bid}: no PENDING_UPLOAD rows — nothing to mark (already applied, "
                     f"labelled, or unknown id)")
        note = f" | marked uploaded by Ori {datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}"
        run_update(mark_uploaded_sql(bid, note), 'mark-uploaded')
        print(f"{bid}: {n} row(s) now applied.")
        return

    synthetic = (args.register_table != LIVE_REGISTER or args.negates_table != LIVE_NEGATES)
    for t in (args.register_table, args.negates_table):
        if t not in (LIVE_REGISTER, LIVE_NEGATES):
            assert t.startswith(('TMP_', 'TEMP_')), \
                f"{t}: an override source must be a TMP_/TEMP_ copy — never a live table"
    if synthetic:
        args.no_log = True
        print(f"SYNTHETIC SOURCES: register={args.register_table} negates={args.negates_table} "
              f"— --no-log forced; nothing is written to the change log.")
    assert not args.as_of or synthetic, \
        "--as-of is a test instrument: it is allowed only with a TMP_ source"

    leaks = bq(LEAK_SQL.format(p=PROJECT, register=args.register_table))
    negs = bq(NEGATE_SQL.format(p=PROJECT, register=args.register_table,
                                negates=args.negates_table))
    if not leaks:
        print("The register publishes no LEAK rows today — the leak book is empty.")
        return
    today_la = date.fromisoformat(args.as_of or leaks[0]['today_la'])
    watermark = leaks[0]['watermark']
    if args.as_of:
        print(f"AS-OF {today_la} (the warehouse's own day is {leaks[0]['today_la']}) — a rule "
              f"that arms in the future is being exercised.")
    batch_id = f"seat_moves_{today_la:%Y%m%d}_{datetime.now(timezone.utc):%H%M}"
    # every date this book carries is on the WAREHOUSE's clock, the file name included: the
    # machine running it can already be on tomorrow while Los Angeles is not.
    if not args.out:
        args.out = f".tmp/seat_moves_{today_la:%Y%m%d}.xlsx"
    os.makedirs(os.path.dirname(args.out) or '.', exist_ok=True)

    visible = []      # (row, disposition, reason, kind)
    executable = []   # (row, disposition, kind)
    for r in leaks:
        disp, reason = classify_leak(r, today_la)
        visible.append((r, disp, reason, 'LEAK'))
        if disp in EXECUTABLE:
            executable.append((r, disp, 'LEAK'))
    for c in negs:
        disp, reason = classify_negate(c, today_la)
        visible.append((c, disp, reason, 'NEGATE'))
        if disp in EXECUTABLE:
            executable.append((c, disp, 'NEGATE'))

    # ── DOCTRINE ASSERTIONS — no executable row may break them ────────────────────────────────
    for r, disp, kind in executable:
        ef = _d(r.get('holdout_eligible_from'))
        assert not (ef and today_la >= ef), \
            f"HOLDOUT VIOLATION: {r['campaign_name']} is in the holdout arm and eligible"
        assert not b(r.get('is_brand_defense')), \
            f"DEFENSE VIOLATION: {r.get('target_text')} is brand defense"
        if kind == 'NEGATE':
            assert num(r['ng_net_profit_8w'], 0) < 0 and num(r['ng_lt_net_profit'], 0) < 0 \
                and num(r['ng_orders_8w'], 0) == 0 and num(r['ng_organic_units_8w'], 0) == 0, \
                f"BLOCK-GRAIN VIOLATION: negate on a term the ad group earns on: {r['search_term']}"
    # every LEAK row maps to exactly one sheet row or exactly one stated no-action reason
    leak_seen = [(r['campaign_id'], r['keyword_id']) for r, d, _, k in visible if k == 'LEAK']
    assert len(leak_seen) == len(set(leak_seen)) == len(leaks), \
        "a LEAK row was dropped or duplicated by the classifier"

    pauses = [(r, d, k) for r, d, k in executable if d == PAUSE]
    negates = [(r, d, k) for r, d, k in executable if d in (NEGATE_KEYWORD, NEGATE_TARGET)]

    # ── workbook ─────────────────────────────────────────────────────────────────────────────
    def is_sb(r):
        """Which sheet a row belongs on. The campaign DIMENSION is the authority (a campaign
        named '...SP/BROAD...' can be a real SB campaign — one in this account is), the ladder's
        channel is the fallback, and a disagreement between the two is raised, never resolved
        silently: putting an SP row on the SB sheet fails the whole upload."""
        ct = (r.get('campaign_type') or '').upper()
        ch = (r.get('channel') or '').upper()
        assert not (ct and ch and (ct == 'SB') != (ch == 'SB')), (
            f"CHANNEL DISAGREEMENT on {r.get('campaign_name')}: the campaign dimension says "
            f"{ct} and the keyword ladder says {ch} — resolve it before a sheet is written")
        return (ct or ch) == 'SB'

    sp_rows = [(r, d, k) for r, d, k in executable if not is_sb(r)]
    sb_rows = [(r, d, k) for r, d, k in executable if is_sb(r)]
    wb = openpyxl.Workbook()
    wb.remove(wb.active)
    line_of = {}

    def key_of(r, d):
        return (r['campaign_id'], r['keyword_id'], d, r.get('search_term') or '')

    def build(r, d, sb):
        pf = r.get('echo_portfolio_id')
        if d == PAUSE:
            return sb_pause_row(r) if sb else sp_pause_row(r)
        if d == NEGATE_TARGET:
            assert not sb, "a negative product target is a Sponsored Products entity only"
            return sp_negative_target_row(r, pf)
        return sb_negative_keyword_row(r, pf) if sb else sp_negative_keyword_row(r, pf)

    if sp_rows:
        ws = wb.create_sheet(SP_SHEET)
        ws.append(SP_HEADERS)
        for i, (r, d, k) in enumerate(sp_rows, start=2):
            ws.append([build(r, d, False)[h] for h in SP_HEADERS])
            line_of[key_of(r, d)] = (SP_SHEET, i)
    if sb_rows:
        ws = wb.create_sheet(SB_SHEET)
        ws.append(SB_HEADERS)
        for i, (r, d, k) in enumerate(sb_rows, start=2):
            ws.append([build(r, d, True)[h] for h in SB_HEADERS])
            line_of[key_of(r, d)] = (SB_SHEET, i)
    if executable:
        wb.save(args.out)
        assert len(line_of) == len(executable), "sheet rows != executable rows"

    # ── audit csv ────────────────────────────────────────────────────────────────────────────
    audit_path = args.out.rsplit('.', 1)[0] + '_audit.csv'
    with open(audit_path, 'w', newline='') as f:
        wr = csv.writer(f)
        wr.writerow(['sheet', 'excel_row', 'kind', 'disposition', 'family', 'campaign_id',
                     'campaign', 'ad_group_id', 'keyword_id', 'target', 'search_term',
                     'match', 'channel', 'is_auto', 'is_pt', 'ladder_state', 'live_state',
                     'old_state', 'old_bid', 'portfolio_id', 'latest_history_portfolio_id',
                     'next_check_date', 'settled_clk90', 'settled_ord90',
                     'cost_per_day', 'spend_7d',
                     'ng_clicks_8w', 'ng_orders_8w', 'ng_spend_8w', 'ng_net_profit_8w',
                     'ng_clicks_recent_5d', 'ng_lt_clicks', 'ng_lt_orders', 'ng_lt_net_profit',
                     'ng_organic_units_8w', 'own_kw_clicks_8w', 'block_min_clicks',
                     'holdout_eligible_from', 'season_block', 'engine_reason', 'reason',
                     # the window and the day, on every row, so a README rewritten later from
                     # this file states the same week the dollars came from instead of guessing
                     'watermark', 'register_day'])
        for r, disp, reason, kind in visible:
            sheet, ln = line_of.get(key_of(r, disp), ('', ''))
            wr.writerow([
                sheet, ln, kind, disp, r.get('family'), r.get('campaign_id'),
                r.get('campaign_name'), r.get('ad_group_id'), r.get('keyword_id'),
                r.get('target_text'), r.get('search_term'), r.get('match_type'),
                r.get('campaign_type') or r.get('channel'), r.get('is_auto'),
                r.get('is_pt') or r.get('leak_is_pt'),
                r.get('state') or r.get('leak_state'), r.get('live_state'),
                r.get('live_state') if disp == PAUSE else '',
                r.get('current_bid'), r.get('echo_portfolio_id'), r.get('latest_portfolio_id'),
                r.get('next_check_date'), r.get('settled_clk90'), r.get('settled_ord90'),
                r.get('cost_per_day'), r.get('sp7'),
                r.get('ng_clicks_8w'), r.get('ng_orders_8w'), r.get('ng_spend_8w'),
                r.get('ng_net_profit_8w'), r.get('ng_clicks_recent_5d'), r.get('ng_lt_clicks'),
                r.get('ng_lt_orders'), r.get('ng_lt_net_profit'), r.get('ng_organic_units_8w'),
                r.get('own_kw_clicks_8w'), r.get('min_clicks'),
                r.get('holdout_eligible_from'), r.get('block_cut_reason'),
                r.get('engine_reason'), reason, watermark, today_la])

    # ── README ───────────────────────────────────────────────────────────────────────────────
    readme_path = args.out.rsplit('.', 1)[0] + '_README.md'
    write_readme(readme_path, os.path.basename(args.out), batch_id, watermark, today_la,
                 args.no_log, [readme_row(r, disp, reason, kind, line_of, key_of, is_sb)
                               for r, disp, reason, kind in visible],
                 bool(negs))

    # ── console ──────────────────────────────────────────────────────────────────────────────
    print(f"\n{len(leaks)} LEAK row(s) + {len(negs)} negate candidate(s) -> "
          f"{len(executable)} executable ({len(pauses)} pause · {len(negates)} negative)\n")
    hdr = (f"{'kind':<7} {'target / term':<42} {'campaign':<34} {'st':<7} "
           f"{'$/day':>7}  disposition")
    print(hdr)
    print('-' * len(hdr))
    for r, disp, reason, kind in visible:
        label = (r.get('target_text') if kind == 'LEAK' else r.get('search_term')) or ''
        cpd = num(r.get('cost_per_day'), 0) if kind == 'LEAK' else num(r.get('ng_spend_8w'), 0)
        print(f"{kind:<7} {label[:41]:<42} {(r.get('campaign_name') or '')[:33]:<34} "
              f"{str(r.get('state') or r.get('leak_state') or '')[:6]:<7} {cpd:>7.2f}  {disp}")

    prior = prior_unmarked_batches()
    if prior:
        print("\nEarlier leak batches still PENDING_UPLOAD (waiting on Ori):")
        for p in prior:
            print(f"  {p['batch_id']}  {p['n']} rows  {p['upload_status']}")
    logged = ''
    if executable and not args.no_log:
        # one pending leak book at a time: a second one is logged only as the REPLACEMENT of the
        # first, and the first is labelled AFTER the new batch is on record so the register never
        # meets a moment with no pending pause row for a leak it had already credited.
        refuse_second_pending_book(prior, args.replaces)
        n = log_batch(executable, batch_id, readme_path)
        logged = batch_id
        print(f"\nLogged {n} rows to {CHANGE_LOG.split('.')[-1]} as batch {logged} (PENDING_UPLOAD).")
        if args.replaces:
            supersede(args.replaces, new_batch=batch_id)

    print(f"\n[{datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}] "
          f"wrote {len(executable)} rows -> {args.out}")
    print(f"  audit  -> {audit_path}")
    print(f"  readme -> {readme_path}")
    print("  PREPARE-ONLY: read the README, delete any line you disagree with, then upload to "
          "Amazon Ads > Bulk operations manually. Build the restore sheet with "
          "tools/build_restore_seat_moves_bulksheet.py --audit " + audit_path)
    return {'out': args.out, 'audit': audit_path, 'readme': readme_path,
            'rows': len(executable), 'batch': logged}


if __name__ == '__main__':
    main()
