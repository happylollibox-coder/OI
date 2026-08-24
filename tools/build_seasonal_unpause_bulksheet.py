#!/usr/bin/env python3
"""THE SEASONAL UNPAUSE BOOK — re-open a door a pause closed, and park what comes back.

WHAT IT IS FOR
    A pause is the one action in this account that cannot be undone by the system that took it.
    It removes the keyword from FACT_KEYWORD_STATE altogether, so afterwards no layer can see it,
    judge it or revive it (architecture/THREE_LAYERS.md §5). When a keyword is paused because a
    trailing window was quiet, and the quiet is a SEASON rather than a verdict, the pause is
    wrong twice over: it acts on `NOT_WORTH_NOW` as though it were `NOT_WORTH` (§4), and it
    destroys the evidence trail that would have corrected it.

    This book emits, for a NAMED list of keywords, ONE bulksheet row each that
      - sets the keyword state back to enabled, and
      - sets the bid to the CHANNEL PARK PRICE.

    Not to the bid it was paused from. A keyword that is `NOT_WORTH_NOW` comes back VISIBLE AND
    ALIVE, not funded: it holds at the floor for pennies a day, it reappears in the ladder and in
    every layer's view, and the Catalog can be asked what it is worth for the window that matters
    when that window is close enough to plan.

THE PARK PRICE IS READ, NEVER WRITTEN HERE
    In order:
      1. the engine's published park price for that keyword — T_OOB_SEAT_ECONOMICS.bid_park, the
         column V_OOB_KEYWORD has published since 2026-08-22 (ruling R-f);
      2. otherwise the channel+creative floor for its ad group — V_BID_FLOOR, which resolves
         DIM_AD_GROUP.creative_type once and calls FN_BID_FLOOR, the ONE definition of a floor.
    An engine park price below the ad group's floor is raised to the floor, because a bid under
    the platform minimum is rejected outright and parks nothing at all.
    A keyword whose park price cannot be read from either source is REFUSED, loudly, with its id
    on the refusal. It never falls back to a number written in this file. A generator holding a
    private copy of a floor is precisely the defect FN_BID_FLOOR was created to end: the ladder
    once borrowed the engine's flat parking price as though it were a floor and manufactured three
    phantom kills out of it (the story is in FN_BID_FLOOR.sql).

    Note that a paused keyword usually has NO row in T_OOB_SEAT_ECONOMICS — the pause is what
    removed it — so the channel floor is the ordinary path, and that is by design: the floor is a
    property of the channel and the creative, which a pause cannot take away.

THE POPULATION IS ALWAYS EXPLICIT
    Ids come from --keywords FILE and/or repeated --keyword ID, and from nowhere else. This book
    never derives a population of its own. Reversing a pause is a judgement about which silence
    is seasonal, and that judgement is made before this file runs, not inside it.
    An id that cannot be found in DIM_KEYWORD is reported as a refusal, never dropped quietly.

WHAT IT NEVER DOES
    It never uploads. It never pauses, archives or negates anything. It never raises a bid above
    the park price it read. It never writes into a live ads table. It never deletes a change-log
    row.

USAGE
    /usr/local/bin/python3 tools/build_seasonal_unpause_bulksheet.py \
        --keywords .tmp/seasonal_unpause_20260824.txt [-o PATH] [--no-log]

    Terminal actions that build nothing, log nothing and upload nothing:
        --mark-uploaded BATCH_ID   Ori has uploaded that book: its rows leave PENDING_UPLOAD.
        --supersede BATCH_ID ...   Ori will NOT upload it: label it SUPERSEDED_NEVER_UPLOADED.

    Both act on PENDING_UPLOAD rows and nothing else. NULL upload_status is the APPLIED state —
    V_PPC_CHANGE_LOG_APPLIED selects it and --mark-uploaded writes it — so a statement that also
    matched NULL could silently un-apply a batch Ori really uploaded. No path deletes a row.
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
from build_reprice_bulksheet import q, num, b  # noqa: E402

PROJECT = "onyga-482313"

# The season this book asks the record about. It is an ARGUMENT, not a fact: --season-from /
# --season-to move it, and every figure the README prints is measured on the window it names.
DEFAULT_SEASON_FROM = '2025-11-01'
DEFAULT_SEASON_TO = '2025-12-31'

LIVE_CHANGE_LOG = "FACT_PPC_CHANGE_LOG"
CHANGE_LOG = f"{PROJECT}.OI.{LIVE_CHANGE_LOG}"

BATCH_PREFIX = 'seasonal_unpause'


def set_change_log_table(table):
    global CHANGE_LOG
    assert table == LIVE_CHANGE_LOG or table.startswith(('TMP_', 'TEMP_')), \
        f"{table}: a change-log override must be a TMP_/TEMP_ copy — never another live table"
    CHANGE_LOG = f"{PROJECT}.OI.{table}"
    return CHANGE_LOG


# dispositions
UNPAUSE_PARK = 'UNPAUSE_PARK'
EXECUTABLE = (UNPAUSE_PARK,)

KEYWORD_ID_RE = re.compile(r'^\d{6,20}$')


class ParkPriceUnreadable(Exception):
    """Neither the engine's park price nor the ad group's floor could be read for this row."""


# ── the population ────────────────────────────────────────────────────────────────────────────

def parse_keyword_ids(lines):
    """Explicit ids, in the order given, deduped. A `#` line is a comment; anything after the id
    on a line is a human label and is ignored. Anything that is not an id stops the build — a
    typo must never silently shrink the population."""
    ids, seen = [], set()
    for raw in lines:
        line = str(raw).split('#')[0].strip()
        if not line:
            continue
        token = line.split()[0].strip().strip(',"\'')
        if not KEYWORD_ID_RE.match(token):
            sys.exit(f"{token!r} is not a keyword id. The population of this book is explicit: "
                     f"one numeric keyword id per line (a '#' comment and a trailing label are "
                     f"allowed). Nothing was built.")
        if token not in seen:
            seen.add(token)
            ids.append(token)
    if not ids:
        sys.exit("no keyword ids given. This book never derives its own population: pass "
                 "--keywords FILE and/or --keyword ID. Nothing was built.")
    return ids


def read_keyword_ids(files, inline):
    lines = list(inline or [])
    for path in files or []:
        with open(path, encoding='utf-8') as f:
            lines.extend(f.read().splitlines())
    return parse_keyword_ids(lines)


# ── the park price ────────────────────────────────────────────────────────────────────────────

def park_price(r):
    """(price, source) for one row, read from the warehouse. Raises ParkPriceUnreadable rather
    than guessing. See the module docstring for the order and the reasons."""
    engine = num(r.get('bid_park'), None)
    floor = num(r.get('bid_floor'), None)
    if engine is None and floor is None:
        raise ParkPriceUnreadable(
            f"keyword {r.get('keyword_id')} ({r.get('target_text')!r} in "
            f"{r.get('campaign_name')}): the engine publishes no park price for it "
            f"(T_OOB_SEAT_ECONOMICS.bid_park) and its ad group "
            f"{r.get('ad_group_id')} has no floor in V_BID_FLOOR. A park price is READ or it is "
            f"refused — this generator holds no price of its own.")
    if engine is None:
        return round(floor, 2), 'CHANNEL_FLOOR'
    if floor is not None and engine < floor:
        return round(floor, 2), 'ENGINE_BID_PARK_RAISED_TO_FLOOR'
    return round(engine, 2), 'ENGINE_BID_PARK'


def assert_park_is_not_a_restore(r, old_bid, price):
    """The row must carry the park price the warehouse published — not the bid the keyword was
    paused from. `gift for 18 year old girl` was paused from $1.00; it is NOT_WORTH_NOW, so it
    comes back visible, not funded. The single legal raise is up to the platform minimum, which
    is the floor itself."""
    park, source = park_price(r)
    assert abs(price - park) < 1e-9, (
        f"{r.get('target_text')!r} ({r.get('keyword_id')}): the sheet carries {price} but the "
        f"park price read from the warehouse is {park} ({source}). A park is the price the "
        f"warehouse published, never a bid this book chose — and never the {old_bid} it was "
        f"paused from.")
    if old_bid is not None and price > old_bid + 1e-9:
        floor = num(r.get('bid_floor'), None)
        assert floor is not None and abs(price - floor) < 1e-9, (
            f"{r.get('target_text')!r} ({r.get('keyword_id')}): parking at {price} would be a "
            f"RAISE over the {old_bid} it was paused from, and it is not the platform minimum. "
            f"A park never funds a keyword.")


# ── the rule ──────────────────────────────────────────────────────────────────────────────────

def classify(r, today):
    """One warehouse row in, one (disposition, reason) out. Every no-action branch names the rule
    that stopped it, in words a reader can act on."""
    text = f"`{r.get('target_text')}` in {r.get('campaign_name')}"
    hold = _d(r.get('holdout_eligible_from'))
    if hold and today >= hold:
        return 'HOLDOUT_EXCLUDED', (
            f"No sheet row: {text} sits in a campaign in the HOLDOUT arm since {hold}. A hand "
            f"upload into the holdout invalidates the trial — it stays paused until the trial "
            f"ends, and it must be re-listed then.")
    if b(r.get('is_brand_defense')):
        return 'DEFENSE_EXEMPT', (
            f"No sheet row: {text} is brand defense. Defense is never judged on profit and never "
            f"parked at a floor — what it should be bidding is a defense decision, not a park.")
    live = (r.get('live_state') or '').upper()
    if not live:
        return 'LIVE_STATE_UNKNOWN', (
            f"No sheet row: Amazon's own record of {text} could not be read, so whether it is "
            f"actually paused is unknown. Never write a state you cannot see the current value of.")
    if live == 'ENABLED':
        return 'ALREADY_ENABLED', (
            f"No sheet row: {text} already reads enabled in Amazon — the pause never landed, or "
            f"it has already been reversed. Its bid is a repricing question for the reprice book, "
            f"not an unpause.")
    if live not in ('PAUSED',):
        return 'NOT_REVERSIBLE_BY_SHEET', (
            f"No sheet row: {text} reads {live.lower()} in Amazon, not paused. An archived or "
            f"removed target cannot be brought back by a state row; it has to be created again, "
            f"which is a different decision and a different book.")
    try:
        price, source = park_price(r)
    except ParkPriceUnreadable as e:
        return 'PARK_PRICE_UNREADABLE', f"No sheet row: {e}"
    old = num(r.get('paused_from_bid'), None)
    old_txt = f"${old:.2f}" if old is not None else "an unrecorded bid"
    return UNPAUSE_PARK, (
        f"{text} was paused from {old_txt} on a trailing window that was silent because of the "
        f"season, not because the keyword is worthless. It sold in the reference season "
        f"({int(num(r.get('season_orders'), 0))} order(s), "
        f"${num(r.get('season_sales'), 0):.2f}), so it is NOT_WORTH_NOW rather than NOT_WORTH => "
        f"re-enable it and park it at ${price:.2f} ({source.lower().replace('_', ' ')}). It comes "
        f"back visible and alive, not funded.")


def _d(v):
    """A date out of a BigQuery JSON string, or None."""
    if v in (None, ''):
        return None
    if isinstance(v, date):
        return v
    return date.fromisoformat(str(v)[:10])


# ── sheet routing and rows ────────────────────────────────────────────────────────────────────

def is_sb(r):
    """Which sheet a row belongs on. The campaign DIMENSION is the authority (a campaign named
    '...SP/BROAD...' can be a real SB campaign — one in this account is), the ladder's channel is
    the fallback, and a disagreement between the two is raised, never resolved silently: an SP row
    in an SB campaign fails the whole upload."""
    ct = (r.get('campaign_type') or '').upper()
    ch = (r.get('channel') or '').upper()
    assert not (ct and ch and (ct == 'SB') != (ch == 'SB')), (
        f"CHANNEL DISAGREEMENT on {r.get('campaign_name')}: the campaign dimension says {ct} and "
        f"the keyword ladder says {ch} — resolve it before a sheet is written")
    return (ct or ch) == 'SB'


def sp_unpause_row(r, price):
    """One Sponsored Products line: the switch and the price together. Two lines — one enabling,
    one repricing — would leave a window in which the keyword is live at the bid it was paused
    from, which is the one bid it must never run at again."""
    row = {h: '' for h in SP_HEADERS}
    is_target = b(r.get('is_pt'))
    row.update({
        'Product': 'Sponsored Products',
        'Entity': 'Product Targeting' if is_target else 'Keyword',
        'Operation': 'Update',
        'Campaign ID': str(r['campaign_id']),
        'Ad Group ID': str(r.get('ad_group_id') or ''),
        # THE PORTFOLIO ECHO. A blank portfolio cell DETACHES a campaign from its portfolio on a
        # Campaign row — blank never means "unchanged" — so the last non-null portfolio is read
        # LIVE and echoed onto every row this book writes.
        'Portfolio ID': str(r.get('echo_portfolio_id') or ''),
        'Campaign Name (Informational only)': r.get('campaign_name') or '',
        'State': 'ENABLED',
        'Bid': f"{price:.2f}",
    })
    if is_target:
        row['Product Targeting ID'] = str(r['keyword_id'])
    else:
        row['Keyword ID'] = str(r['keyword_id'])
    return row


def sb_unpause_row(r, price):
    """One Sponsored Brands line. 'Campaign Name' on the SB sheet is a REAL column and is left
    blank on purpose — filling it would rename the campaign; the README maps every row to its
    campaign instead."""
    row = {h: '' for h in SB_HEADERS}
    row.update({
        'Product': 'Sponsored Brands',
        'Entity': 'Keyword',
        'Operation': 'Update',
        'Campaign Id': str(r['campaign_id']),
        'Ad Group Id': str(r.get('ad_group_id') or ''),
        'Portfolio Id': str(r.get('echo_portfolio_id') or ''),
        'Keyword Id': str(r['keyword_id']),
        'State': 'enabled',
        'Bid': f"{price:.2f}",
    })
    return row


def routing_note(campaign_name, sb):
    """A campaign whose NAME reads as one channel while Amazon has it as the other. The routing is
    already right — the campaign dimension is the authority — but the SB sheet carries bare ids and
    no campaign name, so an SP-named campaign under the SB heading looks like a misroute to a cold
    reader, and 'fixing' it fails the whole upload. The channel is matched as a WORD: 'SPRING' is
    not SP."""
    name = (campaign_name or '').upper()
    name_sb = bool(re.search(r'\bSB\b', name))
    name_sp = bool(re.search(r'\bSP\b', name))
    if sb and name_sp and not name_sb:
        return ("This campaign is NAMED SP but Amazon has it as a Sponsored Brands campaign, so "
                "the row belongs on the SB sheet exactly where it is. Do not move it to the "
                "Sponsored Products sheet — an SP row for an SB campaign fails the whole upload.")
    if not sb and name_sb and not name_sp:
        return ("This campaign is NAMED SB but Amazon has it as a Sponsored Products campaign, so "
                "the row belongs on the SP sheet exactly where it is. Do not move it.")
    return None


# ── SQL ───────────────────────────────────────────────────────────────────────────────────────
# Every source below is read for the NAMED ids only. Nothing here can widen the population.

SQL = """
WITH wm AS (
  SELECT LEAST(MAX(date), `{p}.OI.FN_ADS_ANCHOR_CAP`()) AS wm
  FROM `{p}.OI.FACT_AMAZON_ADS`
),
dimk AS (
  SELECT CAST(keyword_id AS STRING) keyword_id, CAST(campaign_id AS STRING) campaign_id,
         CAST(ad_group_id AS STRING) ad_group_id, keyword_text, match_type,
         UPPER(COALESCE(state, '')) dim_state, bid AS dim_bid
  FROM `{p}.OI.DIM_KEYWORD`
  WHERE is_current AND CAST(keyword_id AS STRING) IN ({ids})
  QUALIFY ROW_NUMBER() OVER (PARTITION BY keyword_id ORDER BY effective_from DESC) = 1
),
-- Amazon's own feed of the switch. Two independent readings; they must agree before a row is
-- treated as paused, and a disagreement is never read as the convenient answer.
kwsrc AS (
  SELECT CAST(keyword_id AS STRING) kid, UPPER(COALESCE(state, '')) st
  FROM `{p}.OI.V_SRC_AmazonAds_keyword`
  WHERE CAST(keyword_id AS STRING) IN ({ids})
  QUALIFY ROW_NUMBER() OVER (PARTITION BY keyword_id ORDER BY date DESC) = 1
),
camp AS (
  SELECT CAST(campaign_id AS STRING) cid, ANY_VALUE(campaign_name) campaign_name,
         ANY_VALUE(campaign_type) campaign_type
  FROM `{p}.OI.V_DIM_CAMPAIGN_CURRENT` GROUP BY 1
),
ag AS (
  SELECT CAST(ad_group_id AS STRING) agid, ANY_VALUE(creative_type) creative_type,
         ANY_VALUE(ad_group_name) ad_group_name
  FROM `{p}.OI.DIM_AD_GROUP` WHERE is_current GROUP BY 1
),
-- THE PARK PRICE, both published sources. Neither is restated anywhere in the generator.
flr AS (
  SELECT CAST(ad_group_id AS STRING) agid, bid_floor, bid_floor_source
  FROM `{p}.OI.V_BID_FLOOR`
),
oob AS (
  SELECT CAST(keyword_id AS STRING) kid, ANY_VALUE(bid_park) bid_park
  FROM `{p}.OI.T_OOB_SEAT_ECONOMICS`
  WHERE CAST(keyword_id AS STRING) IN ({ids})
  GROUP BY 1
),
-- The ladder, if it can still see the keyword at all. A paused keyword has NO row here — that is
-- the door this book re-opens — so every column is a bonus, never a requirement.
ks AS (
  SELECT CAST(keyword_id AS STRING) kid, ANY_VALUE(channel) channel,
         MAX(COALESCE(is_pt, FALSE)) is_pt, MAX(COALESCE(is_brand_defense, FALSE)) is_brand_defense
  FROM `{p}.OI.FACT_KEYWORD_STATE`
  WHERE CAST(keyword_id AS STRING) IN ({ids})
  GROUP BY 1
),
-- last NON-NULL portfolio (the echo) and the latest row's portfolio (the caveat)
restore AS (
  SELECT CAST(campaign_id AS STRING) cid,
         ARRAY_AGG(portfolio_id IGNORE NULLS ORDER BY date DESC LIMIT 1)[SAFE_OFFSET(0)] AS portfolio_id,
         ARRAY_AGG(portfolio_id ORDER BY date DESC LIMIT 1)[SAFE_OFFSET(0)] AS latest_portfolio_id
  FROM `{p}.OI.V_SRC_AmazonAds_campaign_history`
  GROUP BY 1
),
hold AS (
  SELECT CAST(unit_id AS STRING) cid, MIN(eligible_from) eligible_from
  FROM `{p}.OI.DE_HOLDOUT_ASSIGNMENT`
  WHERE arm = 'HOLDOUT' AND unit_type = 'CAMPAIGN'
  GROUP BY 1
),
-- which book actually switched it off, and from what bid: the most recent APPLIED pause row.
-- upload_status IS NULL is the APPLIED state (V_PPC_CHANGE_LOG_APPLIED selects it).
paused AS (
  SELECT CAST(keyword_id AS STRING) kid, old_bid AS paused_from_bid, batch_id AS paused_by_batch,
         CAST(DATE(applied_at) AS STRING) AS paused_on
  FROM `{p}.OI.FACT_PPC_CHANGE_LOG`
  WHERE action IN ('KEYWORD_PAUSE', 'STOP_TARGET') AND upload_status IS NULL
    AND CAST(keyword_id AS STRING) IN ({ids})
  QUALIFY ROW_NUMBER() OVER (PARTITION BY keyword_id ORDER BY applied_at DESC) = 1
),
-- the reference season's own record, re-derived here rather than quoted from anywhere
season AS (
  SELECT CAST(keyword_id AS STRING) kid,
         SUM(Ads_clicks) season_clicks, SUM(Ads_orders) season_orders,
         ROUND(SUM(Ads_sales), 2) season_sales, ROUND(SUM(Ads_cost), 2) season_cost
  FROM `{p}.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN '{season_from}' AND '{season_to}'
    AND CAST(keyword_id AS STRING) IN ({ids})
  GROUP BY 1
),
-- and this summer's, so the README can show the silence the pause was read from
recent AS (
  SELECT CAST(f.keyword_id AS STRING) kid,
         SUM(f.Ads_clicks) recent_clicks, SUM(f.Ads_orders) recent_orders,
         ROUND(SUM(f.Ads_cost), 2) recent_cost
  FROM `{p}.OI.FACT_AMAZON_ADS` f CROSS JOIN wm
  WHERE f.date BETWEEN DATE_SUB(wm.wm, INTERVAL 90 DAY) AND DATE_SUB(wm.wm, INTERVAL 1 DAY)
    AND CAST(f.keyword_id AS STRING) IN ({ids})
  GROUP BY 1
)
SELECT
  dimk.keyword_id, dimk.campaign_id, dimk.ad_group_id,
  dimk.keyword_text AS target_text, dimk.match_type, dimk.dim_state, dimk.dim_bid,
  camp.campaign_name, camp.campaign_type, ag.ad_group_name, ag.creative_type,
  ks.channel,
  COALESCE(ks.is_pt, REGEXP_CONTAINS(LOWER(dimk.keyword_text), r'^(asin|category)\\s*=')) AS is_pt,
  COALESCE(ks.is_brand_defense, FALSE) AS is_brand_defense,
  ks.kid IS NOT NULL AS ladder_can_see_it,
  -- one live reading; a disagreement must never read as PAUSED (nor as ENABLED)
  CASE WHEN kwsrc.st IS NULL AND dimk.dim_state = '' THEN ''
       WHEN COALESCE(kwsrc.st, dimk.dim_state) = COALESCE(dimk.dim_state, kwsrc.st)
         THEN COALESCE(kwsrc.st, dimk.dim_state)
       ELSE 'DISAGREEMENT'
  END AS live_state,
  kwsrc.st AS live_state_feed, NULLIF(dimk.dim_state, '') AS live_state_dim,
  flr.bid_floor, flr.bid_floor_source, oob.bid_park,
  restore.portfolio_id AS echo_portfolio_id, restore.latest_portfolio_id,
  hold.eligible_from AS holdout_eligible_from,
  paused.paused_from_bid, paused.paused_by_batch, paused.paused_on,
  COALESCE(season.season_clicks, 0) season_clicks, COALESCE(season.season_orders, 0) season_orders,
  COALESCE(season.season_sales, 0) season_sales, COALESCE(season.season_cost, 0) season_cost,
  COALESCE(recent.recent_clicks, 0) recent_clicks, COALESCE(recent.recent_orders, 0) recent_orders,
  COALESCE(recent.recent_cost, 0) recent_cost,
  '{season_from}' AS season_from, '{season_to}' AS season_to,
  CAST(wm.wm AS STRING) AS watermark,
  CAST(CURRENT_DATE('America/Los_Angeles') AS STRING) AS today_la
FROM dimk
CROSS JOIN wm
LEFT JOIN kwsrc ON kwsrc.kid = dimk.keyword_id
LEFT JOIN camp ON camp.cid = dimk.campaign_id
LEFT JOIN ag ON ag.agid = dimk.ad_group_id
LEFT JOIN flr ON flr.agid = dimk.ad_group_id
LEFT JOIN oob ON oob.kid = dimk.keyword_id
LEFT JOIN ks ON ks.kid = dimk.keyword_id
LEFT JOIN restore ON restore.cid = dimk.campaign_id
LEFT JOIN hold ON hold.cid = dimk.campaign_id
LEFT JOIN paused ON paused.kid = dimk.keyword_id
LEFT JOIN season ON season.kid = dimk.keyword_id
LEFT JOIN recent ON recent.kid = dimk.keyword_id
-- HOUSE RULE 9 — a TOTAL ordering, so two builds of one snapshot diff byte for byte. Last
-- season's orders tie freely (three of today's six sit in single digits), so the tiebreak reaches
-- the unique key (campaign_id, keyword_id).
ORDER BY season.season_orders DESC, dimk.campaign_id, dimk.keyword_id
"""


# ── the warehouse ─────────────────────────────────────────────────────────────────────────────

def bq(sql):
    out = subprocess.run(
        ['bq', 'query', f'--project_id={PROJECT}', '--use_legacy_sql=false', '--nouse_cache',
         '--format=json', '--max_rows=100000', sql],
        capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"query failed:\n{out.stderr}\n{sql[:400]}")
    return json.loads(out.stdout or '[]')


def run_update(sql, what=None):
    out = subprocess.run(['bq', 'query', '--use_legacy_sql=false', '--nouse_cache',
                          f'--project_id={PROJECT}', sql], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"{what} failed:\n{out.stderr}")


# ── the change-log discipline: PENDING_UPLOAD rows only, and never a delete ────────────────────

def prior_unmarked_sql():
    """Earlier unpause books still waiting on Ori: PENDING_UPLOAD and nothing else. A batch at
    NULL is APPLIED — Ori said so with --mark-uploaded — and is never listed as waiting."""
    return (f"SELECT batch_id, upload_status, COUNT(*) n, MIN(applied_at) first_at "
            f"FROM `{CHANGE_LOG}` WHERE batch_id LIKE '{BATCH_PREFIX}_%' "
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


def supersede_note(new_batch):
    stamp = f"{datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}"
    if new_batch:
        return f"never uploaded; superseded by {new_batch} ({stamp}) — labelled by the generator"
    return (f"never uploaded; no later book replaces it ({stamp}) — labelled by hand with "
            f"--supersede")


def supersede(batch_ids, new_batch=None):
    for bid in batch_ids:
        n_pending = int(bq(pending_count_sql(bid))[0]['n'])
        if n_pending == 0:
            sys.exit(f"--supersede {bid}: no PENDING_UPLOAD rows under that id — it is already "
                     f"applied (uploaded), already labelled, or unknown. Nothing was changed: a "
                     f"label is written on PENDING_UPLOAD rows only.")
        run_update(supersede_sql(bid, supersede_note(new_batch)), 'supersede')
        left = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` "
                  f"WHERE batch_id = {q(bid)} AND upload_status = 'SUPERSEDED_NEVER_UPLOADED'")
        print(f"  labelled batch {bid} SUPERSEDED_NEVER_UPLOADED — {int(left[0]['n'])} row(s) "
              f"({n_pending} were pending)")
        assert int(left[0]['n']) >= n_pending, \
            f"--supersede {bid}: fewer rows labelled than were pending"


def refuse_second_pending_book(prior, replaces):
    """A build may not log a second PENDING unpause book beside one already waiting. Two books
    would hand Ori two sheets for one keyword, and if he uploaded both the second would overwrite
    the first's price with whatever the later build read. The build proceeds only when it names
    every pending book it replaces (--replaces), and it may not name a book that is not pending —
    nothing is labelled blind, and nothing is ever deleted."""
    pending = {p['batch_id'] for p in prior if p.get('upload_status') == 'PENDING_UPLOAD'}
    named = set(replaces or [])
    unnamed = sorted(pending - named)
    not_pending = sorted(named - pending)
    if unnamed:
        sys.exit(f"an unpause book is already PENDING_UPLOAD: {', '.join(unnamed)}. Either upload "
                 f"it (then --mark-uploaded), label it (--supersede), or rebuild with "
                 f"--replaces {' '.join(unnamed)} so ONE book carries every keyword and the old "
                 f"one is labelled as replaced by it. Nothing was logged.")
    if not_pending:
        sys.exit(f"--replaces {', '.join(not_pending)}: no PENDING_UPLOAD rows under that id "
                 f"(already applied, already labelled, or unknown) — nothing is labelled blind. "
                 f"Nothing was logged.")


def log_batch(rows, batch_id, readme_path):
    """Log EXACTLY the executable rows, one batch, unique id, an upload note; read the count back
    and assert it equals the sheet. old_bid is the bid the keyword was paused from; new_bid is the
    park price the sheet carries."""
    exists = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` WHERE batch_id = {q(batch_id)}")
    assert int(exists[0]['n']) == 0, f"batch id {batch_id} already exists in the change log"
    note = (f"seasonal unpause book {batch_id}, built "
            f"{datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}; README "
            f"{os.path.basename(readme_path)}; manual upload pending — if this book is not "
            f"uploaded set upload_status SUPERSEDED_NEVER_UPLOADED; if uploaded and a line was "
            f"deleted first, set that row FAILED_UPLOAD. Each row re-enables one keyword and "
            f"parks it at the channel park price: visible and alive, not funded.")
    structs = []
    for r, price, _source in rows:
        cid, kid = str(r['campaign_id']), str(r['keyword_id'])
        old = num(r.get('paused_from_bid'), None)
        if old is None:
            old = num(r.get('dim_bid'), None)
        structs.append(
            "STRUCT("
            f"{q('seasonpark-' + '-'.join(batch_id.split('_')[2:]) + '-' + cid + '-' + kid)} AS change_id, "
            f"{q(batch_id)} AS batch_id, CURRENT_TIMESTAMP() AS applied_at, "
            f"{q('KEYWORD_UNPAUSE_PARK')} AS action, {q(r.get('target_text'))} AS targeting, "
            f"{q(kid)} AS keyword_id, {q(r.get('match_type') or '')} AS match_type, "
            f"{q(cid)} AS campaign_id, {q(r.get('campaign_name'))} AS campaign_name, "
            f"{q((r.get('campaign_type') or r.get('channel') or '').upper())} AS campaign_type, "
            f"{q(r.get('ad_group_id'))} AS ad_group_id, "
            f"{('CAST(' + repr(old) + ' AS FLOAT64)') if old is not None else 'NULL'} AS old_bid, "
            f"CAST({price!r} AS FLOAT64) AS new_bid, "
            f"{q('MANUAL')} AS source, {q('MANUAL_BULKSHEET')} AS coach_mode, "
            f"{q(note)} AS upload_note, {q('PENDING_UPLOAD')} AS upload_status)")
    cols = ("change_id, batch_id, applied_at, action, targeting, keyword_id, match_type, "
            "campaign_id, campaign_name, campaign_type, ad_group_id, old_bid, new_bid, source, "
            "coach_mode, upload_note, upload_status")
    run_update(f"INSERT INTO `{CHANGE_LOG}` ({cols}) "
               f"SELECT {cols} FROM UNNEST([{', '.join(structs)}])", 'change-log insert')
    back = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` WHERE batch_id = {q(batch_id)}")
    n_logged = int(back[0]['n'])
    assert n_logged == len(rows), f"logged {n_logged} rows but the sheet holds {len(rows)}"
    return n_logged


# ── the README ────────────────────────────────────────────────────────────────────────────────

def write_readme(readme_path, out_name, batch_id, today_la, watermark, no_log, rows, season):
    """Plain words a reader who has never met this system can act on. `rows` is a list of dicts,
    one per keyword the book looked at, so the writer never reaches back into the warehouse."""
    doing = [x for x in rows if x['disp'] == UNPAUSE_PARK]
    skipped = [x for x in rows if x['disp'] != UNPAUSE_PARK]
    stamp = f"{datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}"
    daily = sum(x['price'] for x in doing)
    with open(readme_path, 'w') as f:
        f.write("# Bringing six seasonal keywords back — what each row does and why\n\n")
        f.write(f"Built {stamp} from `{out_name}` (ads watermark {watermark}, warehouse day "
                f"{today_la}). Change-log batch: **`{batch_id}`**"
                f"{' (NOT logged — --no-log)' if no_log else ''}.\n\n")
        f.write("## What a seasonal park is\n\n")
        f.write("A keyword can be quiet for two completely different reasons, and they look "
                "identical in a spreadsheet: it is **worthless**, or it is **out of season**. "
                "Yesterday's leak book read the second as the first. It paused keywords whose "
                "last few weeks were silent — and for the ones below, the silence is August.\n\n")
        f.write("A pause is not a small mistake here. Pausing a keyword removes it from the "
                "warehouse table every part of this system reads, so afterwards nothing can see "
                "it, nothing re-judges it, and nothing brings it back. It is a door that only "
                "closes. Three months before Christmas, that door was closed on keywords that "
                "sold through last Christmas.\n\n")
        f.write("So each row in this sheet does two things at once:\n\n"
                "1. **switches the keyword back on**, so it exists again and every part of the "
                "system can see and judge it; and\n"
                "2. **sets its bid to the park price** — the lowest bid its channel and creative "
                "allow — so being switched on costs pennies a day.\n\n")
        f.write("**They are being made visible and alive, not funded.** A park is not a vote of "
                "confidence and not a budget. It says: *worth nothing THIS month, worth something "
                "in another one, and we refuse to lose the evidence in between.* When November is "
                "close enough to plan, these keywords get asked the real question — what is a "
                "click worth in a November window — and whatever answer comes back is what they "
                "get funded with. Nothing on this sheet pre-judges that.\n\n")
        f.write(f"**Not one of them returns to the bid it was paused from.** The park price is "
                f"read from the warehouse per row (the engine's published park price where it has "
                f"one, otherwise the floor for that ad group's channel and creative), never "
                f"chosen here. Total cost of the whole sheet if every keyword took a click a day: "
                f"about ${daily:.2f}/day.\n\n")
        f.write(f"## The record each one is coming back on\n\n")
        recent_end = watermark
        try:
            from datetime import timedelta
            recent_end = (date.fromisoformat(str(watermark)[:10]) - timedelta(days=1)).isoformat()
        except (ValueError, TypeError):
            pass
        f.write(f"Last season below is **{season['from']} to {season['to']}**, re-derived from "
                f"`FACT_AMAZON_ADS` when this file was built. *This summer* is the 90 complete "
                f"days ending {recent_end} — the silence the pause was read from. (The ads "
                f"watermark is {watermark}, the last complete ads day; every window ends the day "
                f"before it.)\n\n")
        f.write("| sheet row | keyword | campaign | last season | this summer | paused from | "
                "park price |\n")
        f.write("|---|---|---|---|---|---|---|\n")
        for i, x in enumerate(doing, 1):
            f.write(f"| {x['sheet_line']} | `{x['target_text']}` | {x['campaign_name']} | "
                    f"{x['season_orders']} orders · ${x['season_sales']:,.0f} sales · "
                    f"{x['season_clicks']} clicks | {x['recent_orders']} orders · "
                    f"{x['recent_clicks']} clicks · ${x['recent_cost']:,.2f} spent | "
                    f"${x['old_bid']:.2f} | **${x['price']:.2f}** ({x['price_source']}) |\n")
        cut = [x for x in doing if x['price'] < x['old_bid'] - 1e-9]
        same = [x for x in doing if abs(x['price'] - x['old_bid']) <= 1e-9]
        f.write(f"\nRead the last two columns together. Not one keyword comes back on a HIGHER "
                f"bid than the one it was paused from: {len(cut)} come back cheaper")
        if same:
            f.write(f" and {len(same)} come back at the same price, because that price already "
                    f"was the floor for their ad group")
        f.write(". ")
        worst = max(doing, key=lambda x: x['old_bid'] - x['price']) if doing else None
        if worst and worst['old_bid'] > worst['price'] + 1e-9:
            f.write(f"`{worst['target_text']}` is the one to look at: it was running at "
                    f"${worst['old_bid']:.2f} and comes back at ${worst['price']:.2f}. "
                    f"Re-enabling it without repricing it would have put it straight back on the "
                    f"bid that made it a leak in the first place.")
        f.write("\n\n")
        f.write("## Row by row\n\n")
        for x in doing:
            f.write(f"### {x['sheet']} — row {x['sheet_line']}: `{x['target_text']}` "
                    f"({x['campaign_name']})\n\n")
            f.write(f"- {x['reason']}\n")
            f.write(f"- The park price ${x['price']:.2f} comes from **{x['price_source']}** "
                    f"({x['price_provenance']}). It is read for this ad group's channel and "
                    f"creative; no price is written into the generator.\n")
            f.write(f"- Paused on {x['paused_on'] or 'an unrecorded date'} by batch "
                    f"`{x['paused_by_batch'] or 'unknown'}`, from ${x['old_bid']:.2f}.\n")
            note = routing_note(x['campaign_name'], x['is_sb'])
            if note:
                f.write(f"- **Sheet check.** {note}\n")
            f.write("- Delete this line and the keyword simply stays paused and invisible; then "
                    "label its change-log row FAILED_UPLOAD.\n\n")
        if skipped:
            f.write(f"## Keywords with no row today ({len(skipped)}) — and the rule that stopped "
                    f"each\n\n")
            for x in skipped:
                f.write(f"- **{x['disp']}** — {x['reason']}\n")
            f.write("\n")
        f.write("## How to upload it\n\n")
        f.write("1. Open `" + out_name + "` and read the row-by-row section above beside it. "
                "Delete any line you disagree with — a deleted line changes nothing in Amazon.\n"
                "2. Go to **Amazon Ads → Sponsored ads → Bulk operations**.\n"
                "3. Under *Upload a bulk file*, choose the file and upload it. Do not edit the "
                "header row, do not move a row between sheets, and do not fill the blank "
                "columns — a blank cell means *leave unchanged*, and the two columns that are "
                "filled (State and Bid) are the only two this book changes.\n"
                "4. Wait for the upload to finish and open the result file Amazon gives back. "
                "Every row should read *Success*. A row that errors changed nothing.\n"
                "5. Check one keyword in the console: it should read **enabled**, at the park "
                "price shown above.\n"
                "6. Tell the warehouse it happened:\n\n")
        f.write(f"```\n/usr/local/bin/python3 tools/build_seasonal_unpause_bulksheet.py "
                f"--mark-uploaded {batch_id}\n```\n\n")
        f.write(f"That flips this batch's rows out of PENDING_UPLOAD, so the change log stops "
                f"showing it as waiting on you and the scorecard starts grading it.\n\n")
        f.write(f"**If you decide NOT to upload it**, say so instead — never leave it waiting:\n\n"
                f"```\n/usr/local/bin/python3 tools/build_seasonal_unpause_bulksheet.py "
                f"--supersede {batch_id}\n```\n\n"
                f"That labels the batch `SUPERSEDED_NEVER_UPLOADED`. A change-log row is never "
                f"deleted, and a label is only ever written on rows still marked PENDING_UPLOAD "
                f"— a batch you have already marked uploaded is never touched.\n\n")
        f.write("## What happens next\n\n")
        f.write("Once these are enabled they reappear in the keyword ladder within a day, which "
                "means the register, the weekly run and every book can see them again. They will "
                "sit at their park price doing almost nothing until someone asks the seasonal "
                "question. **Put a note in the calendar for early October**: that is when a "
                "November window is close enough to price, and each of these should be asked what "
                "a click is worth in that window and funded — or not — on the answer. Until then "
                "the correct state for all six is exactly what this sheet gives them: on, "
                "visible, and cheap.\n\n")
        f.write("One more thing to watch: if a later leak book runs before that review and reads "
                "the same trailing silence, it will propose pausing them again. That is the "
                "underlying defect — the ladder has no seasonal verdict yet "
                "(`architecture/THREE_LAYERS.md` §8, item 8) — and until it does, a pause "
                "proposal on any keyword in the table above should be refused by hand.\n")
    return readme_path


# ── CLI ───────────────────────────────────────────────────────────────────────────────────────

def build_parser():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--keywords', action='append', default=[], metavar='FILE',
                    help='file of keyword ids, one per line (# comments and trailing labels are '
                         'allowed). Repeatable.')
    ap.add_argument('--keyword', action='append', default=[], metavar='KEYWORD_ID',
                    help='one keyword id. Repeatable. This book NEVER derives a population.')
    ap.add_argument('-o', '--out', default=None,
                    help="default .tmp/seasonal_unpause_<the warehouse's own day>.xlsx")
    ap.add_argument('--no-log', action='store_true')
    ap.add_argument('--season-from', default=DEFAULT_SEASON_FROM, metavar='YYYY-MM-DD',
                    help='first day of the reference season the README reports (default '
                         f'{DEFAULT_SEASON_FROM}).')
    ap.add_argument('--season-to', default=DEFAULT_SEASON_TO, metavar='YYYY-MM-DD',
                    help=f'last day of the reference season (default {DEFAULT_SEASON_TO}).')
    ap.add_argument('--supersede', nargs='+', default=[], metavar='BATCH_ID',
                    help='label these never-uploaded batches SUPERSEDED_NEVER_UPLOADED and stop.')
    ap.add_argument('--mark-uploaded', metavar='BATCH_ID',
                    help='Ori has uploaded this batch: flip its rows from PENDING_UPLOAD to '
                         'applied (NULL). Builds nothing.')
    ap.add_argument('--replaces', nargs='+', default=[], metavar='BATCH_ID',
                    help='build ONE book carrying every keyword and label these PENDING unpause '
                         'books SUPERSEDED_NEVER_UPLOADED as replaced by it. A build that finds a '
                         'pending unpause book it does not name stops: two pending books hand Ori '
                         'two sheets for one keyword.')
    ap.add_argument('--change-log-table', default=LIVE_CHANGE_LOG, metavar='TABLE',
                    help='a TMP_/TEMP_ copy of FACT_PPC_CHANGE_LOG to act on instead of the live '
                         'log. Any other name is refused.')
    return ap


def main():
    ap = build_parser()
    args = ap.parse_args()
    if args.change_log_table != LIVE_CHANGE_LOG:
        print("CHANGE LOG OVERRIDE: every statement acts on "
              f"{set_change_log_table(args.change_log_table)}")

    if args.supersede:
        supersede(args.supersede)
        print(f"\nLabelled {len(args.supersede)} batch(es) SUPERSEDED_NEVER_UPLOADED. Nothing was "
              f"built and no batch was logged.")
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
        return {'marked': bid}

    ids = read_keyword_ids(args.keywords, args.keyword)
    rows = bq(SQL.format(p=PROJECT, ids=', '.join(q(i) for i in ids),
                         season_from=args.season_from, season_to=args.season_to))
    found = {str(r['keyword_id']) for r in rows}
    missing = [i for i in ids if i not in found]

    today_la = date.fromisoformat(rows[0]['today_la']) if rows else date.today()
    watermark = rows[0]['watermark'] if rows else ''
    batch_id = f"{BATCH_PREFIX}_{today_la:%Y%m%d}_{datetime.now(timezone.utc):%H%M}"
    if not args.out:
        args.out = f".tmp/{BATCH_PREFIX}_{today_la:%Y%m%d}.xlsx"
    os.makedirs(os.path.dirname(args.out) or '.', exist_ok=True)

    visible, executable = [], []
    for r in rows:
        disp, reason = classify(r, today_la)
        price, source = (None, None)
        if disp == UNPAUSE_PARK:
            price, source = park_price(r)
            executable.append((r, price, source))
        visible.append((r, disp, reason, price, source))
    for kid in missing:
        visible.append(({'keyword_id': kid, 'campaign_id': '', 'target_text': '',
                         'campaign_name': ''}, 'KEYWORD_NOT_FOUND',
                        f"No sheet row: keyword id {kid} has no current row in DIM_KEYWORD, so "
                        f"neither its campaign nor its ad group nor its channel can be read. It "
                        f"is refused rather than guessed at — check the id.", None, None))

    refused = [v for v in visible if v[1] in ('PARK_PRICE_UNREADABLE', 'KEYWORD_NOT_FOUND')]
    if refused:
        print("\n" + "!" * 92, file=sys.stderr)
        print(f"REFUSED {len(refused)} ROW(S) — read these before you upload anything:",
              file=sys.stderr)
        for r, disp, reason, _p, _s in refused:
            print(f"  [{disp}] {reason}", file=sys.stderr)
        print("!" * 92 + "\n", file=sys.stderr)

    # ── DOCTRINE ASSERTIONS — no executable row may break them ────────────────────────────────
    for r, price, source in executable:
        ef = _d(r.get('holdout_eligible_from'))
        assert not (ef and today_la >= ef), \
            f"HOLDOUT VIOLATION: {r.get('campaign_name')} is in the holdout arm and eligible"
        assert not b(r.get('is_brand_defense')), \
            f"DEFENSE VIOLATION: {r.get('target_text')} is brand defense"
        assert (r.get('live_state') or '').upper() == 'PAUSED', \
            f"STATE VIOLATION: {r.get('target_text')} does not read paused in Amazon"
        assert source in ('ENGINE_BID_PARK', 'ENGINE_BID_PARK_RAISED_TO_FLOOR', 'CHANNEL_FLOOR'), \
            f"PRICE PROVENANCE VIOLATION: {source} is not a published warehouse source"
        assert_park_is_not_a_restore(r, num(r.get('paused_from_bid'), None), price)
    seen = [str(r['keyword_id']) for r, *_ in visible]
    assert len(seen) == len(set(seen)) == len(ids), \
        "a keyword was dropped or duplicated between the id list and the classifier"

    # ── workbook ──────────────────────────────────────────────────────────────────────────────
    sp_rows = [(r, p, s) for r, p, s in executable if not is_sb(r)]
    sb_rows = [(r, p, s) for r, p, s in executable if is_sb(r)]
    wb = openpyxl.Workbook()
    wb.remove(wb.active)
    line_of = {}
    if sp_rows:
        ws = wb.create_sheet(SP_SHEET)
        ws.append(SP_HEADERS)
        for i, (r, p, _s) in enumerate(sp_rows, start=2):
            ws.append([sp_unpause_row(r, p)[h] for h in SP_HEADERS])
            line_of[str(r['keyword_id'])] = (SP_SHEET, i)
    if sb_rows:
        ws = wb.create_sheet(SB_SHEET)
        ws.append(SB_HEADERS)
        for i, (r, p, _s) in enumerate(sb_rows, start=2):
            ws.append([sb_unpause_row(r, p)[h] for h in SB_HEADERS])
            line_of[str(r['keyword_id'])] = (SB_SHEET, i)
    if executable:
        wb.save(args.out)
        assert len(line_of) == len(executable), "sheet rows != executable rows"

    # ── audit csv ─────────────────────────────────────────────────────────────────────────────
    audit_path = args.out.rsplit('.', 1)[0] + '_audit.csv'
    with open(audit_path, 'w', newline='') as f:
        wr = csv.writer(f)
        wr.writerow(['sheet', 'excel_row', 'disposition', 'campaign_id', 'campaign',
                     'campaign_type', 'ad_group_id', 'creative_type', 'keyword_id', 'target',
                     'match', 'is_pt', 'ladder_can_see_it', 'live_state', 'live_state_feed',
                     'live_state_dim', 'new_state', 'paused_from_bid', 'paused_by_batch',
                     'paused_on', 'dim_bid', 'bid_park', 'bid_floor', 'bid_floor_source',
                     'park_price', 'park_price_source', 'portfolio_id',
                     'latest_history_portfolio_id', 'holdout_eligible_from',
                     'season_from', 'season_to', 'season_clicks', 'season_orders', 'season_sales',
                     'season_cost', 'recent_clicks', 'recent_orders', 'recent_cost',
                     'reason', 'watermark', 'warehouse_day', 'batch_id'])
        for r, disp, reason, price, source in visible:
            sheet, ln = line_of.get(str(r.get('keyword_id')), ('', ''))
            wr.writerow([
                sheet, ln, disp, r.get('campaign_id'), r.get('campaign_name'),
                r.get('campaign_type'), r.get('ad_group_id'), r.get('creative_type'),
                r.get('keyword_id'), r.get('target_text'), r.get('match_type'), r.get('is_pt'),
                r.get('ladder_can_see_it'), r.get('live_state'), r.get('live_state_feed'),
                r.get('live_state_dim'), 'enabled' if disp == UNPAUSE_PARK else '',
                r.get('paused_from_bid'), r.get('paused_by_batch'), r.get('paused_on'),
                r.get('dim_bid'), r.get('bid_park'), r.get('bid_floor'), r.get('bid_floor_source'),
                price, source, r.get('echo_portfolio_id'), r.get('latest_portfolio_id'),
                r.get('holdout_eligible_from'), r.get('season_from'), r.get('season_to'),
                r.get('season_clicks'), r.get('season_orders'), r.get('season_sales'),
                r.get('season_cost'), r.get('recent_clicks'), r.get('recent_orders'),
                r.get('recent_cost'), reason, watermark, today_la, batch_id])

    # ── README ────────────────────────────────────────────────────────────────────────────────
    provenance = {
        'ENGINE_BID_PARK': 'T_OOB_SEAT_ECONOMICS.bid_park, the price the budget engine publishes',
        'ENGINE_BID_PARK_RAISED_TO_FLOOR':
            'the engine park price, raised to the ad group floor because a bid under the platform '
            'minimum is rejected outright',
        'CHANNEL_FLOOR': 'V_BID_FLOOR for this ad group, which resolves the creative type and '
                         'calls FN_BID_FLOOR — the one definition of a floor',
    }
    readme_rows = []
    for r, disp, reason, price, source in visible:
        sheet, ln = line_of.get(str(r.get('keyword_id')), ('', ''))
        old = num(r.get('paused_from_bid'), None)
        if old is None:
            old = num(r.get('dim_bid'), 0.0)
        readme_rows.append({
            'disp': disp, 'reason': reason, 'sheet': sheet, 'sheet_line': ln,
            'is_sb': bool(r.get('campaign_type') or r.get('channel')) and is_sb(r),
            'target_text': r.get('target_text'), 'campaign_name': r.get('campaign_name'),
            'season_orders': int(num(r.get('season_orders'), 0)),
            'season_sales': num(r.get('season_sales'), 0.0),
            'season_clicks': int(num(r.get('season_clicks'), 0)),
            'recent_orders': int(num(r.get('recent_orders'), 0)),
            'recent_clicks': int(num(r.get('recent_clicks'), 0)),
            'recent_cost': num(r.get('recent_cost'), 0.0),
            'old_bid': old or 0.0, 'price': price or 0.0, 'price_source': source or '',
            'price_provenance': provenance.get(source, ''),
            'paused_by_batch': r.get('paused_by_batch'), 'paused_on': r.get('paused_on'),
        })
    readme_path = args.out.rsplit('.', 1)[0] + '_README.md'
    write_readme(readme_path, os.path.basename(args.out), batch_id, today_la, watermark,
                 args.no_log, readme_rows,
                 {'from': args.season_from, 'to': args.season_to})

    # ── console ───────────────────────────────────────────────────────────────────────────────
    print(f"\n{len(ids)} keyword(s) named -> {len(executable)} unpause+park row(s)\n")
    hdr = f"{'keyword':<42} {'campaign':<34} {'live':<9} {'paused@':>8} {'park':>6}  disposition"
    print(hdr)
    print('-' * len(hdr))
    for r, disp, _reason, price, _source in visible:
        old = num(r.get('paused_from_bid'), None)
        print(f"{(r.get('target_text') or '')[:41]:<42} "
              f"{(r.get('campaign_name') or '')[:33]:<34} "
              f"{str(r.get('live_state') or '?')[:8]:<9} "
              f"{(f'{old:.2f}' if old is not None else '-'):>8} "
              f"{(f'{price:.2f}' if price is not None else '-'):>6}  {disp}")

    prior = prior_unmarked_batches()
    if prior:
        print("\nEarlier unpause batches still PENDING_UPLOAD (waiting on Ori):")
        for p in prior:
            print(f"  {p['batch_id']}  {p['n']} rows  {p['upload_status']}")
    logged = ''
    if executable and not args.no_log:
        # one pending unpause book at a time: a second is logged only as the REPLACEMENT of the
        # first, and the first is labelled AFTER the new batch is on record, so there is never a
        # moment with no pending row for a keyword this book has promised to bring back.
        refuse_second_pending_book(prior, args.replaces)
        n = log_batch(executable, batch_id, readme_path)
        logged = batch_id
        print(f"\nLogged {n} rows to {CHANGE_LOG.split('.')[-1]} as batch {logged} "
              f"(PENDING_UPLOAD).")
        if args.replaces:
            supersede(args.replaces, new_batch=batch_id)

    print(f"\n[{datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}] "
          f"wrote {len(executable)} rows -> {args.out}")
    print(f"  audit  -> {audit_path}")
    print(f"  readme -> {readme_path}")
    print("  PREPARE-ONLY: read the README, delete any line you disagree with, then upload to "
          "Amazon Ads > Bulk operations manually. Nothing here uploads.")
    return {'out': args.out, 'audit': audit_path, 'readme': readme_path,
            'rows': len(executable), 'batch': logged}


if __name__ == '__main__':
    main()
