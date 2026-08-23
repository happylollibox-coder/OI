#!/usr/bin/env python3
"""THE REPRICE BOOK — the manual bulksheet that executes the bar/SE keyword states.

v27.105 (2026-08-22, after the adversarial verification returned DO_NOT_UPLOAD on the v27.104
book): the book is now gated on the SIGN of the keyword's record against its family bar, not on
the state label; every move is capped per upload; the placement translation prices each keyword
on its OWN realised cpc/bid ratio where one exists; a floor-probation row is emitted even when an
engine also speaks for the key (CHECK FIRST, naming the competing instruction, one price chosen by
Ori); and the batch written to the change log is asserted to be exactly the rows on the sheet.

    F1  SIGN, NOT LABEL.  AT_BAR is two-sided. Above the bar the record is a paying keyword — a
        winner is never pulled down (NO_CUT_ABOVE_BAR); a raise is booked only if the standing
        price implies one. Below the bar a keyword is never raised (NO_RAISE_BELOW_BAR) — A4's
        failure mode is a placement translation that says a below-bar bid is "cheap". AT_BAR's
        standing price may only move a bid TOWARD the bar. The v27.104 book cut five above-bar
        keywords and raised six below-bar ones because it keyed the rule on state == 'REPRICE'.
    F2  MOVE-SIZE CAP, derived (see the constants): three engine steps per upload, symmetric.
        Every row whose uncapped move exceeds the cap is CHECK FIRST.
    F2b TOO THIN (v27.107). A bid move resting on <= 2 settled orders is NOT EXECUTABLE: with one
        order the noise band equals the reading itself (se == roas), so the keyword is AT_BAR by
        construction and the SIDE of the bar is noise. Such a row is disposition TOO_THIN — off the
        sheet, shown in the audit and README with its reason. A file handed over is the file
        uploaded; "delete these lines" is not an instruction a generator may leave to its reader.
        Exception: a FLOOR_PROBATION row is a floor landing, not an evidence-based move — kept.
    F3  PLACEMENT.  A keyword with >= 10 settled clicks since its last bid change prices through
        its OWN realised cpc/bid ratio in V_BID_CPC_TRANSFER's ratio form (k_seg and M cancel
        within a keyword): new_bid = bid x (affordable_cpc / realised_cpc)^(1/gamma). Otherwise
        the documented campaign inverse bid = (cpc / (k_pure x M))^(1/gamma). Rows whose own
        ratio sits more than one held-out RMSE (0.2805 in log space — the view's own figure) from
        the campaign model are flagged PLACEMENT_DIVERGES in the audit and README.
    F4  PROVENANCE.  One batch per build, time-stamped, logged ONLY for rows on a sheet, with a
        non-NULL new_bid on every bid row and an upload_note; the row count written is read back
        and asserted equal to the sheet. Earlier never-uploaded batches are never deleted — they
        are labelled SUPERSEDED_NEVER_UPLOADED by --supersede BATCH_ID (deliberate, never silent).
    F5  PROBATION.  The state machine's clock starts only when a floor bid has LANDED (v27.105
        SP). A FLOOR_PROBATION row is therefore always emitted — even over an engine's GO on the
        same key — as CHECK FIRST naming the competing instruction, so Ori picks one price.
    F6  README lists every executable row in a HOLDOUT-arm campaign with its 2026-09-01 deadline,
        and names the campaigns whose latest history row carries a NULL portfolio.
    F7  RULE B (--rule-b, OFF by default — nothing changes unless it is asked for). The plan
        judges a keyword on the WINDOW, not on the ladder's 90-day record: good = 2+ orders in
        the window AND window gross profit per ad dollar at or above the family bar; one order
        (whatever the return) is not good; spend with no order is not good; 2+ orders under the
        bar is losing. THE GOOD SIDE IS NEVER CUT AND IS NOT RE-PRICED (P-4), so a good keyword's
        row is dropped in BOTH directions — a cut and a raise alike. A keyword the ladder calls
        WINNER / PACED_WINNER whose window is quiet keeps the good side for one window (P-5
        grace). Every dropped row is named with its window numbers in the audit CSV and the
        README: rule B removes rows, it never adds one and never changes a price.
        Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md (P-1..P-13).
    F8  THE README IS EXECUTABLE, AND A HALF-BUILT BOOK IS NEVER PUBLISHED. Every instruction
        the README gives carries the command that performs it — where the sheet is uploaded,
        --mark-uploaded after Ori uploads, --supersede on the next build if he does not, the
        FAILED_UPLOAD label for a deleted line, and the restore sheet by NAME with the command
        that builds it. The book, the audit and the README are written as `.partial` drafts and
        renamed onto their final names only AFTER the change-log insert, so a build that dies
        early leaves no book naming a batch that has no rows behind it.

WHY THIS EXISTS
    v27.103 gave every keyword a verdict against its FAMILY's bar (AT_BAR / REPRICE / LOSER —
    see architecture/KEYWORD_STATE.md). NO ENGINE acts on those states, by ruling: the one
    executor is this file's output, which Ori reads row by row and uploads BY HAND to
    Amazon Ads > Bulk operations. This script prepares; it never touches Amazon.

WHAT IT EMITS
    - Bid updates for AT_BAR / REPRICE rows whose capped price differs from the current bid by
      more than one 5% ease step (the engine's smallest standing move), in the direction the
      record's side of the bar allows.
    - To-the-floor moves for FLOOR_PROBATION rows (down-moves capped per upload like any other
      cut, except that a floor within one more engine step beyond the cap is landed on — a
      residual under the smallest standing move is not a move, and a bid one cent over the
      floor never starts the clock; an up-move to a platform minimum is not capped — a bid
      under the minimum is invalid).
    - Pause rows for LOSERs (ruling 4: failed AT the floor after probation) — ALWAYS CHECK FIRST.
    - An audit CSV with every candidate row and its disposition, a plain-English README
      (TRIGGER - EVIDENCE => MOVE, no codes), and a restore sheet via
      build_restore_reprice_bulksheet.py, so reversibility is a property, not a claim.

INTERLOCKS
    - SEASON (A5): every bid-down and pause row is checked against the season ledger's
      BLOCK_CUT (V_KEYWORD_CONTEXT_GATE). A blocked row appears in the book WITH its reason
      and is NOT emitted as an executable row — nothing executes-by-hand into a live peak.
    - HOLDOUT: campaigns in DE_HOLDOUT_ASSIGNMENT arm=HOLDOUT are excluded from their
      eligible_from date — a hand upload into the holdout invalidates the trial. Asserted on
      every run; rows allowed today in a holdout campaign are LISTED with the deadline.
    - BRAND DEFENSE: never judged on profit, so never in this book with a profit-based row.
    - PORTFOLIO: echoed on every row. A blank Portfolio ID DETACHES a campaign on Campaign
      rows; on keyword rows Amazon ignores the column, so the echo is a uniform convention,
      not a lever — and the README names campaigns whose latest history row is NULL.

USAGE
    /usr/bin/python3 tools/build_reprice_bulksheet.py [-o PATH] [--no-log] [--rule-b]
                                                     [--supersede BATCH_ID ...]

    Re-derives everything from BigQuery on every run; there is no embedded row list. The batch
    is logged to FACT_PPC_CHANGE_LOG (source MANUAL, coach_mode MANUAL_BULKSHEET) so the
    scorecard grades it — if the book is NOT uploaded, mark the batch FAILED_UPLOAD (uploaded
    but never landed) or SUPERSEDED_NEVER_UPLOADED (never uploaded) — never delete the rows.
"""

import argparse
import csv
import json
import math
import os
import subprocess
import sys
from datetime import date, datetime, timedelta, timezone

import openpyxl

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_stop_nonconverting_bulksheet import (  # noqa: E402
    SP_HEADERS, SB_HEADERS, SP_SHEET, SB_SHEET)

PROJECT = "onyga-482313"

# THE CHANGE LOG, and the one rule every statement against it obeys (2026-08-23 cleanup): a label
# is written on PENDING_UPLOAD rows only, and a row is never deleted. NULL upload_status is the
# APPLIED state — V_PPC_CHANGE_LOG_APPLIED selects it and --mark-uploaded writes it — so the old
# `IS NULL OR PENDING_UPLOAD` clause could silently un-apply a batch Ori really uploaded. The live
# proof runs against a TMP_ copy named with --change-log-table; any override must be a TMP_/TEMP_
# copy. Shared shape with tools/build_seat_moves_bulksheet.py (tools/tests/test_change_log_discipline.py).
LIVE_CHANGE_LOG = "FACT_PPC_CHANGE_LOG"
CHANGE_LOG = f"{PROJECT}.OI.{LIVE_CHANGE_LOG}"


def set_change_log_table(table):
    global CHANGE_LOG
    assert table == LIVE_CHANGE_LOG or table.startswith(('TMP_', 'TEMP_')), \
        f"{table}: a change-log override must be a TMP_/TEMP_ copy — never another live table"
    CHANGE_LOG = f"{PROJECT}.OI.{table}"
    return CHANGE_LOG

# Declared constants, each derived from a house instrument (Standing Rule 0 exempt):
#   MATERIAL_STEP   one daily ease step, the engine's smallest standing move (dark ease -5%/day;
#                   the same 5% the state ladder uses for "materially above affordable").
#   BLIND_STEPS     how many daily steps an engine takes before the FIRST settled reading of its
#                   own move can exist: spend settles by age 2-3 on both channels
#                   (V_ADS_SETTLE_CURVE: spend_pct_of_final_median 100.0/100.1 at age 2/3 for SP,
#                   100.1/100.2 for SB) and the guard's SP settle discipline is 3 days
#                   (V_KEYWORD_GUARD sp_settle_days). So an engine moves blind for 3 steps, then
#                   every further step is informed. A hand upload gets NO further steps before
#                   its next re-read, so its one move is capped at the engine's blind run:
#   CAP_UP          (1 + 0.05)^3 - 1 = +15.76%      CAP_DOWN  1 - (1 - 0.05)^3 = -14.26%
#                   (three compounding steps in each direction — symmetric in step count).
#   VOL_FLOOR       10 settled clicks: the guard's own floor (V_KEYWORD_GUARD min_settled_clk);
#                   the evidence a keyword's own cpc/bid ratio needs before it is used.
#   THIN_ORDERS     2: at <= 2 settled orders the SE band equals the reading itself (se =
#                   roas / sqrt(orders)) — a bid move on such a record is TOO_THIN, not executable
#                   (F2b); only a floor landing (FLOOR_PROBATION) is exempt.
#   RMSE_LOG        0.2805: V_BID_CPC_TRANSFER's leave-one-campaign-out held-out RMSE of
#                   log(cpc) — the tolerance beyond which a keyword's own ratio is said to
#                   DIVERGE from the campaign model.
#   GAMMA_DEFAULT   0.778: the view's gamma, used only if a row arrives without one.
#   RAISE_CEILING   $2.00 — the house's standing bid ceiling (GUARDIAN threshold redesign);
#                   applies to bid RAISES only, a bid-down needs no ceiling.
#   (the floor)     NOT a constant here — each row's bid_floor comes from the state table,
#                   which reads the ONE definition (FN_BID_FLOOR via V_BID_FLOOR). v27.104.
MATERIAL_STEP = 0.05
BLIND_STEPS = 3
CAP_UP = (1 + MATERIAL_STEP) ** BLIND_STEPS - 1        # 0.157625
CAP_DOWN = 1 - (1 - MATERIAL_STEP) ** BLIND_STEPS      # 0.142625
VOL_FLOOR = 10
THIN_ORDERS = 2
RMSE_LOG = 0.2805
GAMMA_DEFAULT = 0.778
RAISE_CEILING = 2.00

EXECUTABLE = ('BID_DOWN', 'BID_UP', 'PAUSE')

# ── RULE B (F7) ───────────────────────────────────────────────────────────────────────────────
# The plan's settings live in DE_PLAN_CONFIG by ruling P-13 — that table DOES NOT EXIST YET, so
# they are DECLARED here, once, and the README says they were declared here. When the table is
# built these three constants and RULE_B_MIN_ORDERS become a read of it, and nothing else moves.
#   PLAN_WINDOW_DAYS   P-13: OFF-PEAK 7 complete days · BOOST 3 · PEAK 3.
#   RULE_B_MIN_ORDERS  P-3: one order at 3x is mostly luck; two is the cheapest guard.
#   GRACE_LADDER_STATES P-5: the ladder's settled-winner states. Grace buys ONE window, and only
#                      for a QUIET window (under the order floor) — a window with 2+ orders is
#                      evidence, and rule B stands over it. There is no two-window memory table
#                      yet, so this generator grants grace on the LADDER STATE ALONE and says so
#                      on the row: it cannot see whether the previous window was also quiet.
PLAN_WINDOW_DAYS = {'OFF_PEAK': 7, 'BOOST': 3, 'PEAK': 3}
RULE_B_MIN_ORDERS = 2
GRACE_LADDER_STATES = ('WINNER', 'PACED_WINNER')
RULE_B_GOOD = 'RULE_B_GOOD'          # the disposition a dropped row carries


def window_bounds(watermark, window_days):
    """P-10: COMPLETE DAYS ONLY. The window is `window_days` days ending at the ads watermark
    minus one; the filling day (the watermark itself) never enters a window. Returns
    (window_from, window_to), both inclusive."""
    wm = watermark if isinstance(watermark, date) else date.fromisoformat(str(watermark))
    window_to = wm - timedelta(days=1)
    return window_to - timedelta(days=window_days - 1), window_to


def assert_window_complete(watermark, window_from, window_to, window_days):
    """The guarantee spec §9 asks for, run against whatever the query actually returned."""
    lo, hi = window_bounds(watermark, window_days)
    def d(v):
        return v if isinstance(v, date) else date.fromisoformat(str(v))
    assert d(window_to) == hi, (f"the window ends {window_to}, not {hi} — a window may never "
                                f"touch the filling day {watermark}")
    assert d(window_from) == lo, (f"the window starts {window_from}, not {lo} — "
                                  f"{window_days} complete days end at {hi}")


def calendar_state(in_peak, peak_start, today):
    """P-13, read from the house calendar (V_PEAK_WINDOW_RULE over DIM_US_HOLIDAYS): OFF_PEAK
    outside a season; inside one, BOOST from the occurrence's boost_start until its peak_start
    and PEAK from then on. A peak whose calendar row carries no peak_start is judged PEAK — both
    states declare the same window, so the split cannot change what this book reads."""
    if not in_peak:
        return 'OFF_PEAK'
    if peak_start and str(today) < str(peak_start):
        return 'BOOST'
    return 'PEAK'


def rule_b(r):
    """P-1/P-3/P-5 — judge ONE keyword on the WINDOW. Returns
    {'good': bool, 'verdict': str, 'reason': plain-English sentence, 'ret': float|None}.

    The margin is the ladder's own: window gross profit is SUM(FACT_AMAZON_ADS.GROSS_PROFIT) over
    the window at the keyword's own grain — the same stored column V_KEYWORD_GUARD sums for
    settled_gp90 and the bar is compared against (see THE GP RULE in that view). No margin is
    invented here and nothing is hardcoded.

    verdict: GOOD · GRACE · LOSING · ONE_ORDER · NO_SALE · NOT_SERVING.
    """
    ordw = int(num(r.get('w_ord'), 0) or 0)
    clkw = int(num(r.get('w_clk'), 0) or 0)
    spw = num(r.get('w_sp'), 0) or 0.0
    gpw = num(r.get('w_gp'), 0) or 0.0
    bar = num(r.get('family_bar'), 1.0)
    bar = 1.0 if bar is None else bar
    ret = (gpw / spw) if spw > 0 else None
    days = r.get('window_days')
    win = (f"the {days}-day window {r.get('window_from')} to {r.get('window_to')}"
           if r.get('window_from') else "the window")
    took = (f"{ordw} order(s) on ${spw:.2f} of ad spend in {win}"
            + (f", returning {ret:.2f} gross-profit dollars per ad dollar against its "
               f"{r.get('family') or 'family'} bar of {bar:.2f}" if ret is not None else ""))

    if ordw >= RULE_B_MIN_ORDERS and ret is not None and ret >= bar:
        return {'good': True, 'verdict': 'GOOD', 'ret': ret,
                'reason': (f"GOOD on the window — {took}. The good side is never cut and is not "
                           f"re-priced, so this keyword is left exactly as it is (P-4).")}
    if ordw < RULE_B_MIN_ORDERS and (r.get('state') or '') in GRACE_LADDER_STATES:
        return {'good': True, 'verdict': 'GRACE', 'ret': ret,
                'reason': (f"GRACE — the ladder calls this a settled winner ({r.get('state')}) and "
                           f"its window is quiet: {took}. A proven winner keeps the good side for "
                           f"ONE quiet window (P-5), held, not cut. NOTE: there is no two-window "
                           f"memory table yet, so this grace is granted on the ladder state alone "
                           f"— it cannot see whether the previous window was also quiet, and a "
                           f"second quiet window should have let rule B stand.")}
    if ordw >= RULE_B_MIN_ORDERS:
        return {'good': False, 'verdict': 'LOSING', 'ret': ret,
                'reason': f"LOSING on the window — {took}, under the bar."}
    if ordw == 1:
        return {'good': False, 'verdict': 'ONE_ORDER', 'ret': ret,
                'reason': (f"WAITING, one order — {took}. One order is not evidence whatever the "
                           f"return, so this keyword is on the not-good side.")}
    if spw > 0 or clkw > 0:
        return {'good': False, 'verdict': 'NO_SALE', 'ret': ret,
                'reason': f"NO SALE — {took}. Spend with no order is on the not-good side."}
    return {'good': False, 'verdict': 'NOT_SERVING', 'ret': ret,
            'reason': f"NOT SERVING — no spend and no clicks in {win}."}


def rule_b_gate(disp, r, bits):
    """P-4, both directions. Returns (disposition, verdict). Rule B only ever REMOVES an
    executable row — it never creates one, and it never changes a price."""
    v = rule_b(r)
    bits['rule_b'] = v
    if v['good'] and disp in EXECUTABLE:
        return RULE_B_GOOD, v
    return disp, v

SQL = """
WITH wm AS (
  SELECT MAX(date) AS d FROM `{p}.OI.FACT_AMAZON_ADS`
),
ks AS (
  SELECT * FROM `{p}.OI.V_KEYWORD_STATE`
  WHERE state IN ('AT_BAR','REPRICE','FLOOR_PROBATION','LOSER')
),
-- one keyword, one price: a key with a live GO instruction today belongs to its engine —
-- except a floor-probation row, which is emitted CHECK FIRST beside the instruction (F5)
instructed AS (
  SELECT CAST(campaign_id AS STRING) cid, COALESCE(CAST(keyword_id AS STRING), '') kid,
         STRING_AGG(DISTINCT CONCAT(engine, ' ', lever, ' $', FORMAT('%.2f', current_bid),
                                    ' -> $', FORMAT('%.2f', suggested_bid))) engines
  FROM `{p}.OI.T_ENGINE_PREFLIGHT`
  WHERE verdict = 'GO'
  GROUP BY 1, 2
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
-- last NON-NULL portfolio (the echo) AND the latest row's portfolio (NULL = the D8 caveat)
restore AS (
  SELECT CAST(campaign_id AS STRING) cid,
         ARRAY_AGG(portfolio_id IGNORE NULLS ORDER BY date DESC LIMIT 1)[SAFE_OFFSET(0)] AS portfolio_id,
         ARRAY_AGG(portfolio_id ORDER BY date DESC LIMIT 1)[SAFE_OFFSET(0)] AS latest_portfolio_id
  FROM `{p}.OI.V_SRC_AmazonAds_campaign_history`
  GROUP BY 1
),
pf AS (
  SELECT portfolio_id, portfolio_name
  FROM `{p}.OI.V_SRC_AmazonAds_portfolio`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY portfolio_id ORDER BY last_updated_date DESC) = 1
),
ag AS (
  SELECT campaign_id cid, keyword_id kid,
         ad_group_id, UPPER(COALESCE(state, 'ENABLED')) ad_keyword_status
  FROM `{p}.OI.V_SRC_AmazonAds_keyword`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id, keyword_id ORDER BY date DESC) = 1
),
-- the transfer model, per campaign x target kind: M (campaign constant), k_pure, gamma
m AS (
  SELECT CAST(campaign_id AS STRING) cid, target_kind, m_effective, k_pure, gamma,
         is_brand_defense
  FROM `{p}.OI.V_BID_CPC_TRANSFER`
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
-- RULE B (F7): the calendar state, the declared window, and the keyword's record INSIDE it.
-- The state comes from the house calendar helper V_PEAK_WINDOW_RULE (one row, resolved over
-- DIM_US_HOLIDAYS: in_peak, the owning occurrence and its boost_start); peak_start comes from
-- the calendar row that owns that boost_start, so BOOST and PEAK can be told apart. The WINDOW
-- LENGTHS are the constants declared in this file (P-13: DE_PLAN_CONFIG does not exist yet).
cal AS (
  SELECT pw.in_peak, pw.occurrence_type, pw.occurrence_start, pw.w_days AS helper_w_days,
         (SELECT MIN(h.peak_start) FROM `{p}.OI.DIM_US_HOLIDAYS` h
          WHERE h.category IN ('gift_season','prime_event','back_to_school','seasonal')
            AND h.boost_start = pw.occurrence_start) AS peak_start
  FROM `{p}.OI.V_PEAK_WINDOW_RULE` pw
),
st AS (
  SELECT cal.*,
         CASE WHEN NOT COALESCE(cal.in_peak, FALSE) THEN 'OFF_PEAK'
              WHEN cal.peak_start IS NOT NULL
                   AND CURRENT_DATE('America/Los_Angeles') < cal.peak_start THEN 'BOOST'
              ELSE 'PEAK' END AS calendar_state
  FROM cal
),
winr AS (
  SELECT st.*,
         CASE st.calendar_state WHEN 'OFF_PEAK' THEN {w_off} WHEN 'BOOST' THEN {w_boost}
              ELSE {w_peak} END AS window_days,
         -- P-10: COMPLETE DAYS ONLY — the window ends at wm - 1; the filling day never enters it
         DATE_SUB(wm.d, INTERVAL (CASE st.calendar_state WHEN 'OFF_PEAK' THEN {w_off}
                                       WHEN 'BOOST' THEN {w_boost} ELSE {w_peak} END) DAY) AS window_from,
         DATE_SUB(wm.d, INTERVAL 1 DAY) AS window_to
  FROM st CROSS JOIN wm
),
-- the keyword's own record in the window. GP is FACT_AMAZON_ADS.GROSS_PROFIT, the stored column
-- the ladder's own guard sums for settled_gp90 — the same margin source, not a new one.
kwin AS (
  SELECT CAST(f.campaign_id AS STRING) cid, CAST(f.keyword_id AS STRING) kid,
         SUM(f.Ads_cost) w_sp, SUM(f.Ads_clicks) w_clk, SUM(f.Ads_orders) w_ord,
         SUM(f.GROSS_PROFIT) w_gp
  FROM `{p}.OI.FACT_AMAZON_ADS` f, winr
  WHERE f.date BETWEEN winr.window_from AND winr.window_to
    AND f.keyword_id IS NOT NULL
  GROUP BY 1, 2
),
live7 AS (
  SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
         SUM(Ads_cost) sp7, SUM(Ads_clicks) clk7
  FROM `{p}.OI.FACT_AMAZON_ADS`, wm
  WHERE date BETWEEN DATE_SUB(wm.d, INTERVAL 7 DAY) AND DATE_SUB(wm.d, INTERVAL 1 DAY)
    AND keyword_id IS NOT NULL
  GROUP BY 1, 2
),
-- F3: the keyword's OWN realised cost and clicks at its CURRENT bid — settled days strictly
-- after its last bid change, inside the guard's own settled frame
own AS (
  SELECT CAST(f.campaign_id AS STRING) cid, CAST(f.keyword_id AS STRING) kid,
         SUM(f.Ads_cost) own_cost, SUM(f.Ads_clicks) own_clk,
         MIN(f.date) own_from, MAX(f.date) own_to
  FROM `{p}.OI.FACT_AMAZON_ADS` f
  JOIN `{p}.OI.FACT_KEYWORD_GUARD` g
    ON CAST(g.campaign_id AS STRING) = CAST(f.campaign_id AS STRING)
   AND CAST(g.keyword_id AS STRING) = CAST(f.keyword_id AS STRING)
  CROSS JOIN wm
  WHERE f.date >= GREATEST(DATE_SUB(wm.d, INTERVAL IF(g.channel = 'SB', 103, 92) DAY),
                           COALESCE(DATE_ADD(g.last_bid_change_date, INTERVAL 1 DAY), DATE '1900-01-01'))
    AND f.date <= DATE_SUB(wm.d, INTERVAL COALESCE(CAST(g.settle_days_eff AS INT64), IF(g.channel = 'SB', 14, 3)) DAY)
  GROUP BY 1, 2
)
SELECT
  ks.campaign_id, ks.keyword_id, ks.target_text, ks.match_type, ks.channel,
  ks.is_auto, ks.is_pt, ks.campaign_name, ks.family, ks.current_bid, ks.state,
  ks.settled_clk90, ks.settled_ord90, ks.settled_roas90, ks.settled_cpc90,
  ks.family_bar, ks.nf_orders, ks.se_eff, ks.affordable_cpc,
  ks.guard_deferred, ks.guard_flip, ks.clean_roas90, ks.clean_cpc90, ks.clean_affordable_cpc,
  ks.state_reason,
  ks.bid_floor, ks.bid_floor_source, ks.affordable_bid, ks.clean_affordable_bid,
  ks.guard_scope, ks.at_floor, ks.floor_since, ks.probation_clock_start,
  ks.probation_clk_settled, ks.probation_elapsed, ks.probation_due_date, ks.probation_bid,
  instr.engines AS engine_instruction,
  camp.campaign_type, camp.campaign_state, camp.live_portfolio_id,
  restore.portfolio_id AS echo_portfolio_id,
  restore.latest_portfolio_id,
  pf.portfolio_name,
  ag.ad_group_id, ag.ad_keyword_status,
  m.m_effective, m.k_pure, m.gamma, COALESCE(m.is_brand_defense, FALSE) AS is_brand_defense,
  own.own_cost, own.own_clk, own.own_from, own.own_to,
  hold.eligible_from AS holdout_eligible_from,
  bc.gate_reason AS block_cut_reason,
  COALESCE(live7.sp7, 0) AS sp7, COALESCE(live7.clk7, 0) AS clk7,
  COALESCE(kwin.w_sp, 0) AS w_sp, COALESCE(kwin.w_clk, 0) AS w_clk,
  COALESCE(kwin.w_ord, 0) AS w_ord, COALESCE(kwin.w_gp, 0) AS w_gp,
  CAST(winr.window_from AS STRING) AS window_from,
  CAST(winr.window_to AS STRING) AS window_to,
  winr.window_days, winr.calendar_state, winr.in_peak AS cal_in_peak,
  CAST(winr.peak_start AS STRING) AS cal_peak_start,
  winr.occurrence_type AS cal_occurrence, winr.helper_w_days AS cal_helper_w_days,
  CAST(winr.occurrence_start AS STRING) AS cal_occurrence_start,
  CAST(wm.d AS STRING) AS watermark,
  CAST(CURRENT_DATE('America/Los_Angeles') AS STRING) AS today_la
FROM ks
LEFT JOIN camp ON camp.cid = ks.campaign_id
LEFT JOIN restore ON restore.cid = ks.campaign_id
LEFT JOIN pf ON pf.portfolio_id = restore.portfolio_id
LEFT JOIN ag ON ag.cid = ks.campaign_id AND ag.kid = ks.keyword_id
LEFT JOIN m ON m.cid = ks.campaign_id
           AND m.target_kind = CASE WHEN COALESCE(ks.is_auto, FALSE) THEN 'AUTO'
                                    WHEN COALESCE(ks.is_pt, FALSE) THEN 'PRODUCT'
                                    ELSE 'KEYWORD' END
LEFT JOIN own ON own.cid = ks.campaign_id AND own.kid = ks.keyword_id
LEFT JOIN hold ON hold.cid = ks.campaign_id
LEFT JOIN bc ON bc.keyword_text = ks.target_text AND NOT COALESCE(ks.is_auto, FALSE)
            AND NOT COALESCE(ks.is_pt, FALSE)
LEFT JOIN live7 ON live7.cid = ks.campaign_id AND live7.kid = ks.keyword_id
LEFT JOIN kwin ON kwin.cid = ks.campaign_id AND kwin.kid = ks.keyword_id
LEFT JOIN instructed instr ON instr.cid = ks.campaign_id AND instr.kid = ks.keyword_id
CROSS JOIN wm
CROSS JOIN winr
-- house rule 9: a total ordering — (campaign_id, target_text) is not a key in the state table,
-- so the tiebreak reaches the keyword key and two builds of one snapshot emit one row order
ORDER BY ks.state, ks.family, ks.campaign_name, ks.target_text, ks.campaign_id, ks.keyword_id
"""


def bq(sql, fmt='json'):
    out = subprocess.run(
        ['bq', 'query', '--use_legacy_sql=false', f'--format={fmt}', '--max_rows=100000',
         '--nouse_cache', f'--project_id={PROJECT}', sql],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        sys.exit(f"BigQuery failed:\n{out.stderr}")
    return json.loads(out.stdout or '[]') if fmt == 'json' else out.stdout


def num(v, default=None):
    return default if v in (None, '') else float(v)


def b(v):
    return v is True or v == 'true'


def price(r, afford_cpc, cur):
    """F3: the affordable CPC -> a BID, through the keyword's own realised ratio where it has
    one, else the campaign model. Returns (raw_bid, transfer_method, detail dict)."""
    gamma = num(r.get('gamma'), GAMMA_DEFAULT) or GAMMA_DEFAULT
    m_eff = num(r.get('m_effective'))
    k_pure = num(r.get('k_pure'))
    own_clk = num(r.get('own_clk'), 0)
    own_cost = num(r.get('own_cost'), 0)
    d = {'gamma': gamma, 'm_eff': m_eff, 'k_pure': k_pure, 'own_clk': int(own_clk),
         'own_cpc': None, 'own_ratio': None, 'model_ratio': None, 'diverges': False}
    if cur and m_eff and k_pure:
        d['model_ratio'] = k_pure * (cur ** (gamma - 1)) * m_eff
    if cur and own_clk >= VOL_FLOOR and own_cost > 0:
        d['own_cpc'] = own_cost / own_clk
        d['own_ratio'] = d['own_cpc'] / cur
        if d['model_ratio']:
            d['diverges'] = abs(math.log(d['own_ratio'] / d['model_ratio'])) > RMSE_LOG
        # ratio form of the documented model: k_seg and M cancel within the keyword
        raw = cur * (afford_cpc / d['own_cpc']) ** (1.0 / gamma)
        return raw, 'OWN_RATIO', d
    if m_eff and k_pure:
        # the documented campaign inverse
        raw = (afford_cpc / (k_pure * m_eff)) ** (1.0 / gamma)
        return raw, 'CAMPAIGN_MODEL', d
    # no model row at all: the SP's own simplification (cpc / M), M defaulting to 1
    return afford_cpc / (m_eff or 1.0), 'CPC_OVER_M', d


def cap_move(cur, raw):
    """F2: clamp raw to [cur x (1 - CAP_DOWN), cur x (1 + CAP_UP)]. Returns (bid, capped).
    A capped value is rounded INWARD to the cent (raises floor, cuts ceil) so cent rounding
    can never carry a move past the cap."""
    lo, hi = cur * (1 - CAP_DOWN), cur * (1 + CAP_UP)
    if raw > hi:
        return math.floor(hi * 100 + 1e-9) / 100, True
    if raw < lo:
        return math.ceil(lo * 100 - 1e-9) / 100, True
    return raw, False


TOO_THIN_REASON = ("one or two orders cannot tell which side of its bar this keyword is on "
                   "— no bid change")


def classify(r):
    """One row -> (disposition, action, new_bid, check_reasons, story_bits).

    Executable: BID_DOWN / BID_UP / PAUSE. Book-visible only: TOO_THIN / SEASON_BLOCKED /
    HOLDOUT_EXCLUDED / ENGINE_INSTRUCTED / NOT_ENABLED / BRAND_DEFENSE_EXCLUDED / NO_MOVE /
    NO_CUT_ABOVE_BAR / NO_RAISE_BELOW_BAR / PROBATION_RUNNING / REFUSED_PAUSE.

    F2b is the last gate: a row that would have executed on <= THIN_ORDERS settled orders is
    TOO_THIN unless it is a FLOOR_PROBATION landing. The priced bid is kept in story_bits so the
    audit still shows what the record would have said.
    """
    disp, action, new_bid, checks, bits = _classify(r)
    if disp in EXECUTABLE and r['state'] != 'FLOOR_PROBATION' \
       and num(r['settled_ord90'], 0) <= THIN_ORDERS:
        bits['thin_bid'] = new_bid
        return 'TOO_THIN', None, None, [], bits
    return disp, action, new_bid, checks, bits


def _classify(r):
    state = r['state']
    cur = num(r['current_bid'])
    guard = b(r['guard_deferred'])
    floor = num(r['bid_floor'])
    afford = num(r['clean_affordable_cpc'] if guard else r['affordable_cpc'])
    cpc = num(r['clean_cpc90'] if guard else r['settled_cpc90'])
    roas = num(r['clean_roas90'] if guard else r['settled_roas90'])
    bar = num(r['family_bar'])
    ord90 = num(r['settled_ord90'], 0)
    nf = num(r['nf_orders'])
    checks = []
    bits = {
        'afford': afford, 'cpc_settled': cpc, 'roas_used': roas, 'bar': bar, 'guard': guard,
        'floor': floor, 'floor_source': r.get('bid_floor_source') or '',
        'side': None, 'raw_bid': None, 'capped': False, 'transfer': None, 'pd': {},
        'sp_afford_bid': num(r['clean_affordable_bid'] if guard else r['affordable_bid']),
        'engine': r.get('engine_instruction') or '',
    }
    if roas is not None and bar is not None:
        bits['side'] = 'ABOVE' if roas > bar else 'BELOW' if roas < bar else 'AT'
    if floor is None:
        return 'NO_MOVE', None, None, checks, bits   # broken floor join, not a row to price

    # exclusions first — a row the book must not execute
    if b(r['is_brand_defense']):
        return 'BRAND_DEFENSE_EXCLUDED', None, None, checks, bits
    if r['holdout_eligible_from'] and r['today_la'] >= r['holdout_eligible_from']:
        return 'HOLDOUT_EXCLUDED', None, None, checks, bits
    if bits['engine'] and state != 'FLOOR_PROBATION':
        return 'ENGINE_INSTRUCTED', None, None, checks, bits
    if (r.get('campaign_state') or 'ENABLED').upper() != 'ENABLED' or \
       (r.get('ad_keyword_status') or 'ENABLED').upper() not in ('ENABLED',):
        return 'NOT_ENABLED', None, None, checks, bits

    nf_condemned = nf is not None and ord90 >= nf
    bits['nf_condemned'] = nf_condemned
    if nf_condemned:
        checks.append(f"at {int(ord90)} orders this keyword is past its family's collapse point "
                      f"of {int(nf)} orders — the noise band no longer shelters it; this verdict "
                      f"is new under the per-family rule")
    if ord90 <= THIN_ORDERS and state == 'FLOOR_PROBATION':
        checks.append(f"only {int(ord90)} settled order(s) — the record is noise, but a floor "
                      f"landing is not an evidence-based move")

    if state == 'LOSER':
        if not (b(r['probation_elapsed']) and b(r['at_floor'])):
            return 'REFUSED_PAUSE', None, None, [], bits
        checks.append("a pause is the one irreversible-feeling move; confirm the probation record")
        if r['block_cut_reason']:
            return 'SEASON_BLOCKED', 'PAUSE', None, checks, bits
        return 'PAUSE', 'PAUSE', None, checks, bits

    if cur is None:
        return 'NO_MOVE', None, None, checks, bits

    if state == 'FLOOR_PROBATION':
        # the move is TO THE FLOOR. Down: capped like any cut (the clock starts only when the
        # floor actually lands — the state says so). Up to a platform minimum: never capped.
        if cur <= floor + 0.005:
            return 'PROBATION_RUNNING', None, None, [], bits
        if bits['engine']:
            checks.append(f"an engine also speaks for this key today — {bits['engine']} — the "
                          f"book's floor row and the engine's row are two prices for one "
                          f"keyword; keep ONE (delete this line to let the engine's stand)")
        if floor < cur:
            # LANDING RULE: if the floor lies within one more engine step beyond the cap
            # (i.e. inside (1 - 0.05)^(BLIND_STEPS + 1) of the bid), land AT the floor — a
            # residual smaller than the engine's smallest standing move is not a separate
            # move, and a bid one cent over the floor never starts the probation clock.
            if floor >= cur * (1 - MATERIAL_STEP) ** (BLIND_STEPS + 1):
                new_bid, capped = floor, False
            else:
                new_bid, capped = cap_move(cur, floor)
            new_bid = round(max(new_bid, floor), 2)
            bits['capped'] = capped
            bits['raw_bid'] = floor
            if capped:
                checks.append(f"the floor ${floor:.2f} is more than one upload's cap below "
                              f"${cur:.2f}; this row steps to ${new_bid:.2f} and the probation "
                              f"clock starts only when a bid AT the floor lands")
            if r['block_cut_reason']:
                return 'SEASON_BLOCKED', 'BID', new_bid, checks, bits
            return 'BID_DOWN', 'BID', new_bid, checks, bits
        bits['raw_bid'] = floor
        return 'BID_UP', 'BID', round(floor, 2), checks, bits

    # AT_BAR / REPRICE — F1: the SIDE of the bar decides the only direction allowed
    if afford is None or bits['side'] is None:
        return 'NO_MOVE', None, None, checks, bits
    raw, method, pd = price(r, afford, cur)
    bits['raw_bid'], bits['transfer'], bits['pd'] = raw, method, pd
    if pd.get('diverges'):
        checks.append(f"PLACEMENT_DIVERGES: its own realised cpc/bid ratio {pd['own_ratio']:.2f} "
                      f"sits beyond one model RMSE from the campaign model's {pd['model_ratio']:.2f}"
                      f" — priced on its own ratio, but eyeball the level")
    if bits['side'] == 'AT':
        return 'NO_MOVE', None, None, checks, bits

    if bits['side'] == 'ABOVE':
        # a winner is never pulled down
        if raw <= cur:
            return 'NO_CUT_ABOVE_BAR', None, None, [], bits
        new_bid, capped = cap_move(cur, raw)
        new_bid = round(min(new_bid, RAISE_CEILING), 2)
        bits['capped'] = capped
        if capped:
            checks.append(f"the record's own price ${raw:.2f} is more than +{CAP_UP*100:.1f}% "
                          f"above ${cur:.2f}; capped to ${new_bid:.2f} — one upload is one move")
        if (new_bid - cur) <= max(MATERIAL_STEP * cur, 0.01):
            return 'NO_MOVE', None, None, checks, bits
        return 'BID_UP', 'BID', new_bid, checks, bits

    # BELOW the bar: a below-bar keyword is never raised
    if raw >= cur:
        return 'NO_RAISE_BELOW_BAR', None, None, [], bits
    new_bid, capped = cap_move(cur, raw)
    new_bid = round(max(new_bid, floor), 2)
    bits['capped'] = capped
    if capped:
        checks.append(f"the record's own price ${raw:.2f} is more than {CAP_DOWN*100:.1f}% "
                      f"below ${cur:.2f}; capped to ${new_bid:.2f} — one upload is one move")
    if (cur - new_bid) <= max(MATERIAL_STEP * cur, 0.01):
        return 'NO_MOVE', None, None, checks, bits
    if r['block_cut_reason']:
        return 'SEASON_BLOCKED', 'BID', new_bid, checks, bits
    return 'BID_DOWN', 'BID', new_bid, checks, bits


def story(r, disp, new_bid, bits, checks):
    """Plain sentence: TRIGGER - EVIDENCE => MOVE. No codes."""
    cur = num(r['current_bid'])
    tgt = r['target_text']
    fam = r['family'] or 'unmapped'
    bar = bits['bar'] if bits['bar'] is not None else 1.0
    roas = bits['roas_used']
    floor = bits['floor']
    side_txt = {'ABOVE': 'above', 'BELOW': 'below', 'AT': 'exactly at'}.get(bits['side'], '')
    guard_note = (" (judged on its own terms — the mix-drift guard excluded never-seen "
                  "zero-order search terms)" if bits['guard'] else "")
    ev = (f"its settled 90-day record returns {(roas or 0):.2f} gross-profit dollars per ad dollar "
          f"against the {fam} bar of {bar:.2f} — {side_txt} the bar on "
          f"{int(num(r['settled_ord90'], 0))} settled orders{guard_note}")
    floor_txt = (f"${floor:.2f} floor" if floor is not None else "floor") + \
                (f" ({bits['floor_source']})" if bits.get('floor_source') else "")
    state = r['state']
    pd = bits.get('pd') or {}

    def transfer_txt():
        if bits.get('transfer') == 'OWN_RATIO':
            return (f"through its OWN realised cost per click of ${pd['own_cpc']:.2f} at the "
                    f"${cur:.2f} bid over {pd['own_clk']} settled clicks since its last bid change "
                    f"(the model's ratio form, gamma {pd['gamma']:.3f})")
        if bits.get('transfer') == 'CAMPAIGN_MODEL':
            return (f"through the campaign model (fewer than {VOL_FLOOR} settled clicks at this "
                    f"bid: k {pd['k_pure']:.3f} x placement multiplier {pd['m_eff']:.2f}, "
                    f"gamma {pd['gamma']:.3f})")
        return "through the campaign's placement multiplier alone (no model row)"

    if disp in ('PAUSE', 'REFUSED_PAUSE') or (disp == 'SEASON_BLOCKED' and state == 'LOSER'):
        if disp == 'REFUSED_PAUSE':
            move = (f"the book REFUSES to pause '{tgt}' — the state says LOSER but its probation "
                    f"at the {floor_txt} has not elapsed or its bid is not at the floor; a kill "
                    f"is only ever a keyword that failed AT its floor")
        else:
            move = (f"pause '{tgt}' — it has been on probation at its {floor_txt} since "
                    f"{r['floor_since']} with {int(num(r['probation_clk_settled'], 0))} settled "
                    f"clicks at the floor, and the record still does not clear the bar; there is "
                    f"no cheaper price left to try")
    elif state == 'FLOOR_PROBATION' and disp in ('BID_DOWN', 'BID_UP', 'SEASON_BLOCKED', 'PROBATION_RUNNING'):
        if disp == 'PROBATION_RUNNING':
            move = (f"no move — the bid already sits at its {floor_txt}; "
                    + (f"probation runs since {r['probation_clock_start']} "
                       f"({int(num(r['probation_clk_settled'], 0))} of {VOL_FLOOR} settled clicks at "
                       f"the floor so far), re-judged on {r['probation_due_date']} at the earliest"
                       if r.get('probation_clock_start') else
                       "the state machine will start its clock on the next snapshot"))
        else:
            direction = 'down' if (new_bid or 0) < (cur or 0) else 'up'
            why = (f"its record affords only a ${bits['sp_afford_bid']:.2f} bid, under the floor"
                   if bits['sp_afford_bid'] is not None and bits['sp_afford_bid'] < (floor or 0)
                   else "no affordable price exists above the floor")
            landing = ("this lands AT the floor, so the probation clock starts the day Amazon "
                       "applies it" if abs((new_bid or 0) - (floor or 0)) < 0.005 else
                       "this steps toward the floor; the clock starts only when a bid AT the "
                       "floor lands")
            move = (f"move the bid {direction} from ${cur:.2f} to ${new_bid:.2f} toward its "
                    f"{floor_txt} because {why}; {landing}; the state machine re-judges it once "
                    f"{VOL_FLOOR} settled clicks exist at the floor, and only THEN can it become a kill")
    elif disp in ('BID_DOWN', 'BID_UP') or disp == 'SEASON_BLOCKED':
        direction = 'down' if (new_bid or 0) < (cur or 0) else 'up'
        cap_txt = (f" (the record's own price is ${bits['raw_bid']:.2f}; one upload moves at most "
                   f"{CAP_UP*100:.1f}% up or {CAP_DOWN*100:.1f}% down — three engine steps)"
                   if bits.get('capped') else "")
        move = (f"move the bid {direction} from ${cur:.2f} to ${new_bid:.2f}{cap_txt} — the record "
                f"affords ${(bits['afford'] or 0):.2f} per click at the bar, translated to a bid "
                f"{transfer_txt()}, never below its {floor_txt}")
    elif disp == 'TOO_THIN':
        tb = bits.get('thin_bid')
        move = (f"no bid change — {TOO_THIN_REASON}"
                + (f" (the record would have priced ${cur:.2f} -> ${tb:.2f}; it is not on the sheet)"
                   if tb is not None and cur is not None else ""))
    elif disp == 'NO_CUT_ABOVE_BAR':
        move = (f"no cut — the record is ABOVE its bar, a paying keyword is never pulled down "
                f"(the standing price ${(bits['raw_bid'] or 0):.2f} would have cut ${cur:.2f}; "
                f"its settled cost per click ${(bits['cpc_settled'] or 0):.2f} is already at or "
                f"under the ${(bits['afford'] or 0):.2f} the bar affords)")
    elif disp == 'NO_RAISE_BELOW_BAR':
        move = (f"no raise — the record is BELOW its bar, a below-bar keyword is never raised "
                f"(the placement translation would have raised ${cur:.2f} to "
                f"${(bits['raw_bid'] or 0):.2f}; its record does not earn that)")
    elif disp == 'ENGINE_INSTRUCTED':
        move = (f"no book row — {bits['engine']} already carries a GO instruction on "
                f"this keyword today (one keyword, one price); the book yields")
    elif disp == RULE_B_GOOD:
        v = bits.get('rule_b') or {}
        held = bits.get('rule_b_held') or 'a move'
        move = (f"no book row — rule B judges this keyword on the window and it is on the GOOD "
                f"side: {v.get('reason', '')} The book had priced {held}; that row is dropped, "
                f"not re-priced, and '{tgt}' keeps its ${(cur or 0):.2f} bid")
    elif disp == 'HOLDOUT_EXCLUDED':
        move = (f"no book row — its campaign is in the HOLDOUT arm and the exclusion is in force "
                f"since {r['holdout_eligible_from']}")
    else:
        move = "no executable move"
    trigger = {
        'AT_BAR': "the keyword sits at its family bar within noise",
        'REPRICE': "the keyword sits below its family bar beyond noise but an affordable "
                   "bid exists above its floor",
        'FLOOR_PROBATION': "the keyword sits below its family bar beyond noise and no "
                           "affordable bid exists above its floor (or it is already there)",
        'LOSER': "the keyword sits below its family bar beyond noise after its probation at "
                 "the floor",
    }[state]
    s = f"{trigger} - {ev} => {move}."
    if checks and disp in EXECUTABLE:
        s += " CHECK FIRST: " + "; ".join(checks) + "."
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


def q(s):
    return "'" + str(s).replace('\\', '\\\\').replace("'", "\\'") + "'" if s not in (None, '') else 'NULL'


def prior_unmarked_sql():
    """Earlier reprice books still waiting on Ori: PENDING_UPLOAD and nothing else. A batch at
    NULL is APPLIED — the scorecard grades it and the state machine reads it — and is never
    listed as waiting: listing it was how the listing ate its own tail and invited a --supersede
    on a book Ori had uploaded."""
    return (f"SELECT batch_id, upload_status, COUNT(*) n, MIN(applied_at) first_at "
            f"FROM `{CHANGE_LOG}` "
            f"WHERE batch_id LIKE 'reprice_book_%' "
            f"AND upload_status = 'PENDING_UPLOAD' "
            f"GROUP BY 1, 2 ORDER BY 4")


def prior_unmarked_batches():
    return bq(prior_unmarked_sql())


# ---- F8: the README is executable, and a half-built book is never published --------------
DRAFT_SUFFIX = '.partial'
HOUSE_PYTHON = '/usr/local/bin/python3'


def draft_path(final_path):
    """Every output is written under this name first and renamed onto its final name only
    after the change log holds the batch (see publish_drafts)."""
    return final_path + DRAFT_SUFFIX


def publish_drafts(final_paths):
    """Rename every draft onto its final name, or nothing at all.

    WHY: a build that wrote the book, the audit and the README and then died before the
    change-log insert used to leave a complete-looking trio at the DEFAULT output path naming
    a batch id with no rows behind it. Uploading that sheet would be invisible to the
    scorecard and to the guard. Publishing after the log makes 'a book exists on disk' mean
    'its batch exists in the log'."""
    for p in final_paths:
        assert os.path.exists(draft_path(p)), f"draft missing, nothing published: {draft_path(p)}"
    for p in final_paths:
        os.replace(draft_path(p), p)


def restore_path_for(out_path):
    """The name build_restore_reprice_bulksheet.py will write, so the README can NAME the file
    instead of saying 'next to this one'. That script's default is
    .tmp/restore_reprice_<today>.xlsx — derived here from the book's own date so the two agree."""
    base = os.path.basename(out_path).rsplit('.', 1)[0]
    digits = ''.join(c for c in base if c.isdigit())[:8]
    if len(digits) != 8:                      # an ad-hoc book name carries no date: use today's
        digits = f"{date.today():%Y%m%d}"
    return os.path.join(os.path.dirname(out_path) or '.', f"restore_reprice_{digits}.xlsx")


def lifecycle_section(batch_id, out_path, audit_path, restore_path, no_log=False):
    """The README section that lets a reader who has ONLY this file run the whole lifecycle.

    The book told Ori to label the batch and never showed him a command; every instruction now
    carries the invocation that performs it. Nothing here uploads: the sheet goes to Amazon by
    hand, and --mark-uploaded is the confirmation that he did it."""
    s = ["## What to do with this file\n\n"]
    s.append(
        f"**1. Read it, then upload it by hand.** Open `{os.path.basename(out_path)}` in Amazon "
        f"Ads > Sponsored ads > **Bulk operations** > *Upload file*. No script in this repo ever "
        f"uploads to Amazon — this one only prepares the sheet. Delete any line you disagree "
        f"with before uploading; the row-by-row notes below say exactly what deleting each line "
        f"costs.\n\n")
    if no_log:
        s.append(
            f"**2. This build did NOT log a batch — the batch was not logged** (`--no-log`), so "
            f"`{batch_id}` is a name on "
            f"this page and nothing else — there are no change-log rows behind it. Do not upload "
            f"this sheet as a real move: rebuild without `--no-log` so the batch exists and the "
            f"scorecard can grade it.\n\n")
        return ''.join(s)
    s.append(
        f"**2. If you uploaded it, say so** — that is what flips the batch from pending to "
        f"applied, so the scorecard grades these moves and the state machine sees them:\n\n"
        f"```\n{HOUSE_PYTHON} tools/build_reprice_bulksheet.py --mark-uploaded {batch_id}\n```\n\n")
    s.append(
        f"**3. If you did NOT upload it**, the batch must be labelled `SUPERSEDED_NEVER_UPLOADED` "
        f"(never deleted) or the guard will treat these bids as live. The label is written by the "
        f"next book, which supersedes this one as it logs its own:\n\n"
        f"```\n{HOUSE_PYTHON} tools/build_reprice_bulksheet.py --rule-b --supersede {batch_id}\n"
        f"```\n\nThat flag acts on `PENDING_UPLOAD` rows only — an already-uploaded batch stops "
        f"the build with a sentence rather than being re-labelled.\n\n")
    s.append(
        f"**4. If you deleted a line before uploading**, label that one row `FAILED_UPLOAD` in "
        f"`FACT_PPC_CHANGE_LOG` by hand (batch `{batch_id}`, matched on its target and campaign). "
        f"A change-log row is labelled, never deleted.\n\n")
    s.append(
        f"**5. To put every bid back**, build the undo sheet from this book's own audit — it "
        f"restores exactly what this book changed, nothing re-derived:\n\n"
        f"```\n{HOUSE_PYTHON} tools/build_restore_reprice_bulksheet.py --audit {audit_path}\n"
        f"```\n\nIt writes `{os.path.basename(restore_path)}`, which is uploaded the same way.\n\n")
    return ''.join(s)


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


def run_update(sql, what):
    out = subprocess.run(['bq', 'query', '--use_legacy_sql=false', '--nouse_cache',
                          f'--project_id={PROJECT}', sql], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"{what} failed:\n{out.stderr}")


def supersede(batch_ids, new_batch):
    for bid in batch_ids:
        # PENDING_UPLOAD only, counted BEFORE the UPDATE: an applied batch (NULL) has zero
        # pending rows and stops the build here with a sentence — it is never re-labelled,
        # because NULL means Amazon has it. A row is never deleted.
        n_pending = int(bq(pending_count_sql(bid))[0]['n'])
        if n_pending == 0:
            sys.exit(f"--supersede {bid}: no PENDING_UPLOAD rows under that id — it is already "
                     f"applied (uploaded), already labelled, or unknown. Nothing was changed and "
                     f"no batch was logged: a label is written on PENDING_UPLOAD rows only.")
        note = (f"never uploaded; superseded by {new_batch} "
                f"({datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}) — labelled by the generator")
        run_update(supersede_sql(bid, note), 'supersede')
        left = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` WHERE batch_id = {q(bid)} "
                  f"AND upload_status = 'SUPERSEDED_NEVER_UPLOADED'")
        print(f"  labelled batch {bid} SUPERSEDED_NEVER_UPLOADED — {int(left[0]['n'])} row(s) "
              f"now carry the label ({n_pending} were pending)")
        assert int(left[0]['n']) >= n_pending, f"--supersede {bid}: fewer rows labelled than were pending"


def log_batch(rows, batch_id, readme_path):
    """F4: log EXACTLY the executable rows, one batch, unique id, non-NULL new_bid on every bid
    row, an upload_note; read the count back and assert it equals the sheet."""
    exists = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` WHERE batch_id = {q(batch_id)}")
    assert int(exists[0]['n']) == 0, f"batch id {batch_id} already exists in the change log"
    note = (f"reprice book {batch_id}, built {datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}; "
            f"README {os.path.basename(readme_path)}; manual upload pending — if this book is not "
            f"uploaded set upload_status SUPERSEDED_NEVER_UPLOADED; if uploaded and a line was "
            f"deleted first, set that row FAILED_UPLOAD")
    structs = []
    for r, disp, new_bid in rows:
        action = ('KEYWORD_PAUSE' if disp == 'PAUSE'
                  else 'REDUCE_BID' if disp == 'BID_DOWN' else 'INCREASE_BID')
        old_bid = num(r['current_bid'])
        if disp != 'PAUSE':
            assert new_bid is not None and old_bid is not None, f"NULL bid on {r['target_text']}"
            assert (new_bid < old_bid) == (disp == 'BID_DOWN'), f"direction mismatch on {r['target_text']}"
        cid, kid = str(r['campaign_id']), str(r['keyword_id'])
        structs.append(
            "STRUCT("
            f"{q('reprice-' + '-'.join(batch_id.split('_')[2:]) + '-' + cid + '-' + kid)} AS change_id, "
            f"{q(batch_id)} AS batch_id, CURRENT_TIMESTAMP() AS applied_at, "
            f"{q(action)} AS action, {q(r['target_text'])} AS targeting, "
            f"{q(kid)} AS keyword_id, {q(r['match_type'])} AS match_type, "
            f"{q(cid)} AS campaign_id, {q(r['campaign_name'])} AS campaign_name, "
            f"{q((r.get('campaign_type') or r.get('channel') or '').upper())} AS campaign_type, "
            f"{q(r['ad_group_id'])} AS ad_group_id, "
            f"{('CAST(' + repr(old_bid) + ' AS FLOAT64)') if old_bid is not None else 'NULL'} AS old_bid, "
            f"{('CAST(' + repr(new_bid) + ' AS FLOAT64)') if new_bid is not None else 'NULL'} AS new_bid, "
            f"{q('MANUAL')} AS source, {q('MANUAL_BULKSHEET')} AS coach_mode, {q(note)} AS upload_note, "
            # v27.106: a book is logged at BUILD time so its batch id is on record, but nothing has
            # reached Amazon until Ori uploads it. PENDING_UPLOAD keeps the rows out of
            # V_PPC_CHANGE_LOG_APPLIED, so the keyword state machine does not re-read a file that is
            # still on disk as changes that happened (it did, once: cooldowns and re-judge dates
            # moved on an un-uploaded book). --mark-uploaded BATCH flips the status to NULL.
            f"{q('PENDING_UPLOAD')} AS upload_status)"
        )
    cols = ("change_id, batch_id, applied_at, action, targeting, keyword_id, match_type, "
            "campaign_id, campaign_name, campaign_type, ad_group_id, old_bid, new_bid, source, "
            "coach_mode, upload_note, upload_status")
    sql = (f"INSERT INTO `{CHANGE_LOG}` ({cols}) "
           f"SELECT {cols} FROM UNNEST([{', '.join(structs)}])")
    out = subprocess.run(
        ['bq', 'query', '--use_legacy_sql=false', '--nouse_cache', f'--project_id={PROJECT}', sql],
        capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"change-log insert failed:\n{out.stderr}")
    back = bq(f"SELECT COUNT(*) n, COUNTIF(action <> 'KEYWORD_PAUSE' AND new_bid IS NULL) null_bids "
              f"FROM `{CHANGE_LOG}` WHERE batch_id = {q(batch_id)}")
    n_logged, null_bids = int(back[0]['n']), int(back[0]['null_bids'])
    assert n_logged == len(rows), f"logged {n_logged} rows but the sheet holds {len(rows)}"
    assert null_bids == 0, f"{null_bids} bid rows logged with NULL new_bid"
    return n_logged


def build_parser():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('-o', '--out', default=f".tmp/reprice_book_{date.today():%Y%m%d}.xlsx")
    ap.add_argument('--rule-b', action='store_true',
                    help='F7: judge every keyword on the WINDOW and drop every row on a keyword '
                         'the window calls GOOD — a cut and a raise alike (P-4). OFF by default: '
                         'without it this book is exactly the book it was before rule B existed.')
    ap.add_argument('--no-log', action='store_true',
                    help='skip the FACT_PPC_CHANGE_LOG batch insert')
    ap.add_argument('--supersede', nargs='*', default=[],
                    help='earlier never-uploaded batch ids to label SUPERSEDED_NEVER_UPLOADED')
    ap.add_argument('--mark-uploaded', metavar='BATCH_ID',
                    help='Ori has uploaded this batch: flip its rows from PENDING_UPLOAD to applied '
                         '(NULL) so the scorecard grades them and the state machine sees them. '
                         'Builds nothing.')
    ap.add_argument('--change-log-table', default=LIVE_CHANGE_LOG, metavar='TABLE',
                    help='a TMP_/TEMP_ copy of FACT_PPC_CHANGE_LOG to act on instead of the live '
                         'log — the instrument that proves --supersede / --mark-uploaded leave an '
                         'applied batch alone. Any other name is refused.')
    return ap


def main():
    args = build_parser().parse_args()
    if args.change_log_table != LIVE_CHANGE_LOG:
        print(f"CHANGE LOG OVERRIDE: every statement acts on {set_change_log_table(args.change_log_table)}")

    if args.mark_uploaded:
        # v27.106: the only way a book becomes "applied" is Ori saying so. Flipping the status is
        # the upload confirmation; rows deleted from the sheet before upload should be set
        # FAILED_UPLOAD by hand afterwards, per the README.
        bid = args.mark_uploaded
        n = int(bq(pending_count_sql(bid))[0]['n'])
        if n == 0:
            sys.exit(f"{bid}: no PENDING_UPLOAD rows — nothing to mark (already applied, superseded, or unknown id)")
        note = f" | marked uploaded by Ori {datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}"
        run_update(mark_uploaded_sql(bid, note), 'mark-uploaded')
        print(f"{bid}: {n} row(s) now applied. The next SP_SNAPSHOT_KEYWORD_STATE run will read them.")
        return

    os.makedirs(os.path.dirname(args.out) or '.', exist_ok=True)

    rows = bq(SQL.format(p=PROJECT, w_off=PLAN_WINDOW_DAYS['OFF_PEAK'],
                         w_boost=PLAN_WINDOW_DAYS['BOOST'], w_peak=PLAN_WINDOW_DAYS['PEAK']))
    if not rows:
        print("No AT_BAR / REPRICE / FLOOR_PROBATION / LOSER keywords — the book is empty today.")
        return

    today_la = rows[0]['today_la']
    # time-stamped: a re-derived book never collides with an earlier build's batch
    batch_id = f"reprice_book_{today_la.replace('-', '')}_{datetime.now(timezone.utc):%H%M}"

    # RULE B (F7): the window every keyword is judged on, proved complete before it is used
    w0 = rows[0]
    cal_state = w0.get('calendar_state') or 'OFF_PEAK'
    win_days = int(num(w0.get('window_days'), PLAN_WINDOW_DAYS[cal_state]))
    win_from, win_to = w0.get('window_from'), w0.get('window_to')
    assert_window_complete(w0['watermark'], win_from, win_to, win_days)
    assert win_days == PLAN_WINDOW_DAYS[cal_state], \
        f"the query returned a {win_days}-day window for {cal_state}; P-13 declares " \
        f"{PLAN_WINDOW_DAYS[cal_state]}"
    assert cal_state == calendar_state(b(w0.get('cal_in_peak')), w0.get('cal_peak_start'),
                                       today_la), "the query's calendar state and this file's disagree"
    win_txt = (f"{win_days} complete days, {win_from} to {win_to} (the ads watermark is "
               f"{w0['watermark']} and never enters the window)")
    if args.rule_b:
        print(f"RULE B: calendar {cal_state}"
              + (f" — {w0.get('cal_occurrence')} occurrence" if b(w0.get('cal_in_peak')) else "")
              + f"; window = {win_txt}.")

    executable = []   # (row, disposition, new_bid)
    visible = []      # every candidate with disposition + story
    holdout_hits = []
    rule_b_dropped = []   # (row, the disposition rule B removed, its bid, the verdict)
    for r in rows:
        disp, action, new_bid, checks, bits = classify(r)
        if args.rule_b:
            gated, v = rule_b_gate(disp, r, bits)
            if gated != disp:
                bits['rule_b_held'] = (
                    'a pause' if disp == 'PAUSE' else
                    f"a bid {'cut' if disp == 'BID_DOWN' else 'raise'} "
                    f"${num(r['current_bid'], 0):.2f} -> ${new_bid:.2f}")
                rule_b_dropped.append((r, disp, new_bid, v))
                disp, new_bid, checks = gated, None, []
        st = story(r, disp, new_bid, bits, checks)
        visible.append((r, disp, new_bid, checks, bits, st))
        if disp in EXECUTABLE:
            executable.append((r, disp, new_bid))
        if disp == 'HOLDOUT_EXCLUDED':
            holdout_hits.append(r)
    if args.rule_b:
        # P-4 in one assertion: no executable row survives on a keyword the window calls good.
        for r, disp, nb in executable:
            v = next(x[4] for x in visible if x[0] is r)['rule_b']
            assert not v['good'], f"RULE B VIOLATION: {r['target_text']} is on the good side"

    # DOCTRINE ASSERTIONS — no executable row may break them
    for r, disp, new_bid in executable:
        assert not (r['holdout_eligible_from'] and today_la >= r['holdout_eligible_from']), \
            f"HOLDOUT VIOLATION: {r['campaign_name']} is in the holdout arm and eligible"
        cur = num(r['current_bid'])
        bits = next(v[4] for v in visible if v[0] is r)
        if r['state'] in ('AT_BAR', 'REPRICE'):
            assert not (bits['side'] == 'ABOVE' and disp == 'BID_DOWN'), f"above-bar cut on {r['target_text']}"
            assert not (bits['side'] == 'BELOW' and disp == 'BID_UP'), f"below-bar raise on {r['target_text']}"
        if disp == 'BID_UP' and r['state'] != 'FLOOR_PROBATION':
            assert new_bid <= round(cur * (1 + CAP_UP), 2) + 0.005, f"cap breach up on {r['target_text']}"
        if disp == 'BID_DOWN':
            lands_on_floor = (r['state'] == 'FLOOR_PROBATION'
                              and abs(new_bid - num(r['bid_floor'])) < 0.005
                              and num(r['bid_floor']) >= cur * (1 - MATERIAL_STEP) ** (BLIND_STEPS + 1))
            assert lands_on_floor or new_bid >= round(cur * (1 - CAP_DOWN), 2) - 0.005, \
                f"cap breach down on {r['target_text']}"
            assert new_bid >= num(r['bid_floor']) - 0.005, f"below floor on {r['target_text']}"
    armed = sorted({r['holdout_eligible_from'] for r in rows if r['holdout_eligible_from']})
    holdout_allowed = [(r, d, nb) for r, d, nb in executable if r['holdout_eligible_from']]
    print(f"HOLDOUT check: {len(holdout_hits)} row(s) excluded today; {len(holdout_allowed)} "
          f"executable row(s) sit in holdout-arm campaigns whose exclusion arms "
          f"{armed[0] if armed else 'n/a'} (today {today_la}).")

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
    wb.save(draft_path(args.out))
    assert len(line_of) == len(executable), "sheet rows != executable rows"

    # ---- audit csv (every candidate row, executable or not) -------------------------
    audit_path = args.out.rsplit('.', 1)[0] + '_audit.csv'
    with open(draft_path(audit_path), 'w', newline='') as f:
        wr = csv.writer(f)
        wr.writerow(['sheet', 'excel_row', 'disposition', 'check_first', 'state', 'bar_side',
                     'family', 'campaign_id', 'campaign', 'ad_group_id', 'keyword_id', 'target',
                     'match', 'channel', 'is_auto', 'is_pt', 'portfolio_id', 'portfolio',
                     'latest_history_portfolio_id',
                     'family_bar', 'roas90_used', 'orders90', 'nf_orders', 'se_eff',
                     'settled_cpc_used', 'affordable_cpc',
                     'transfer_method', 'own_clicks_at_bid', 'own_cpc_at_bid', 'own_ratio',
                     'model_ratio', 'placement_flag', 'm_effective', 'k_pure', 'gamma',
                     'sp_affordable_bid', 'raw_bid', 'cap_applied', 'bid_floor', 'bid_floor_source',
                     'probation_since', 'probation_clock_start', 'probation_clicks_settled',
                     'probation_due', 'engine_instruction', 'holdout_eligible_from',
                     'old_bid', 'new_bid', 'move_pct', 'guard_deferred',
                     'live_7d_spend_CONTEXT_ONLY', 'live_7d_cpc_CONTEXT_ONLY',
                     # RULE B (F7) — the window every keyword was judged on, and the verdict.
                     # rule_b_dropped_row names the row this filter REMOVED: never silent.
                     'rule_b_window', 'rule_b_orders', 'rule_b_spend', 'rule_b_gp',
                     'rule_b_return', 'rule_b_bar', 'rule_b_verdict', 'rule_b_dropped_row',
                     'rule_b_reason',
                     'check_reasons', 'story'])
        dropped_by_key = {(x[0]['campaign_id'], x[0]['keyword_id']): (x[1], x[2])
                          for x in rule_b_dropped}
        for r, disp, new_bid, checks, bits, st in visible:
            sheet, ln = line_of.get((r['campaign_id'], r['keyword_id']), ('', ''))
            disp_before, nb_before = dropped_by_key.get((r['campaign_id'], r['keyword_id']),
                                                        ('', None))
            clk7 = num(r['clk7'], 0)
            cur = num(r['current_bid'], 0)
            pd = bits.get('pd') or {}
            wr.writerow([
                sheet, ln, disp, 'CHECK FIRST' if (checks and disp in EXECUTABLE) else '',
                r['state'], bits.get('side') or '', r['family'], r['campaign_id'], r['campaign_name'],
                r['ad_group_id'], r['keyword_id'], r['target_text'], r['match_type'],
                r['channel'], r['is_auto'], r['is_pt'],
                r['echo_portfolio_id'], r.get('portfolio_name') or '',
                r.get('latest_portfolio_id') or '',
                f"{(bits['bar'] or 1.0):.4f}",
                f"{(bits['roas_used'] or 0):.3f}", int(num(r['settled_ord90'], 0)),
                r['nf_orders'] or '', f"{num(r['se_eff'], 0):.3f}" if r['se_eff'] not in (None, '') else '',
                f"{(bits['cpc_settled'] or 0):.2f}",
                f"{(bits['afford'] or 0):.2f}" if bits['afford'] is not None else '',
                bits.get('transfer') or '', pd.get('own_clk', ''),
                f"{pd['own_cpc']:.3f}" if pd.get('own_cpc') else '',
                f"{pd['own_ratio']:.3f}" if pd.get('own_ratio') else '',
                f"{pd['model_ratio']:.3f}" if pd.get('model_ratio') else '',
                'PLACEMENT_DIVERGES' if pd.get('diverges') else '',
                f"{num(r['m_effective'], 0):.3f}" if r.get('m_effective') else '',
                f"{num(r['k_pure'], 0):.4f}" if r.get('k_pure') else '',
                f"{num(r['gamma'], 0):.3f}" if r.get('gamma') else '',
                f"{bits['sp_afford_bid']:.3f}" if bits.get('sp_afford_bid') is not None else '',
                f"{bits['raw_bid']:.3f}" if bits.get('raw_bid') is not None else '',
                'yes' if bits.get('capped') else '',
                f"{bits['floor']:.2f}" if bits.get('floor') is not None else '',
                bits.get('floor_source') or '',
                r.get('floor_since') or '', r.get('probation_clock_start') or '',
                r.get('probation_clk_settled') if r.get('probation_clk_settled') not in (None, '') else '',
                r.get('probation_due_date') or '', bits.get('engine') or '',
                r.get('holdout_eligible_from') or '',
                f"{cur:.2f}", f"{new_bid:.2f}" if new_bid else '',
                f"{100 * (new_bid / cur - 1):+.1f}%" if (new_bid and cur) else '',
                'yes' if bits['guard'] else '',
                f"{num(r['sp7'], 0):.2f}",
                f"{(num(r['sp7'], 0) / clk7):.2f}" if clk7 else '',
                f"{r.get('window_from')} to {r.get('window_to')} ({r.get('window_days')}d "
                f"{r.get('calendar_state')})",
                int(num(r.get('w_ord'), 0)), f"{num(r.get('w_sp'), 0):.2f}",
                f"{num(r.get('w_gp'), 0):.2f}",
                (f"{(bits.get('rule_b') or {}).get('ret'):.3f}"
                 if (bits.get('rule_b') or {}).get('ret') is not None else ''),
                f"{(bits['bar'] or 1.0):.4f}",
                (bits.get('rule_b') or {}).get('verdict', ''),
                (f"{disp_before} ${num(r['current_bid'], 0):.2f} -> "
                 f"{('PAUSE' if disp_before == 'PAUSE' else '$%.2f' % nb_before)}"
                 if disp == RULE_B_GOOD else ''),
                (bits.get('rule_b') or {}).get('reason', ''),
                ' | '.join(checks), st])

    # ---- plain-English readme -------------------------------------------------------
    n_down = sum(1 for _, d, _ in executable if d == 'BID_DOWN')
    n_up = sum(1 for _, d, _ in executable if d == 'BID_UP')
    n_pause = sum(1 for _, d, _ in executable if d == 'PAUSE')
    bid_down_total = sum(num(r['current_bid'], 0) - nb for r, d, nb in executable if d == 'BID_DOWN')
    bid_up_total = sum(nb - num(r['current_bid'], 0) for r, d, nb in executable if d == 'BID_UP')
    down_spend7 = sum(num(r['sp7'], 0) for r, d, _ in executable if d in ('BID_DOWN', 'PAUSE'))
    up_spend7 = sum(num(r['sp7'], 0) for r, d, _ in executable if d == 'BID_UP')
    blocked = [(r, st) for r, disp, nb, cf, bits, st in visible if disp == 'SEASON_BLOCKED']
    thin = [(r, st) for r, disp, nb, cf, bits, st in visible if disp == 'TOO_THIN']
    check_rows = [(r, disp, nb, st) for r, disp, nb, cf, bits, st in visible
                  if cf and disp in EXECUTABLE]
    n_capped = sum(1 for r, disp, nb, cf, bits, st in visible if disp in EXECUTABLE and bits.get('capped'))
    n_no_cut = sum(1 for v in visible if v[1] == 'NO_CUT_ABOVE_BAR')
    n_no_raise = sum(1 for v in visible if v[1] == 'NO_RAISE_BELOW_BAR')
    null_pf = sorted({(r['campaign_name'], r['echo_portfolio_id']) for r, d, nb in executable
                      if not r.get('latest_portfolio_id')})
    readme_path = args.out.rsplit('.', 1)[0] + '_README.md'
    restore_path = restore_path_for(args.out)
    with open(draft_path(readme_path), 'w') as f:
        f.write("# The reprice book — what each row does and why\n\n")
        f.write(f"Built {datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC} from `{args.out}` "
                f"(ads watermark {rows[0]['watermark']}, states of {today_la}). "
                f"Change-log batch: **`{batch_id}`**"
                f"{' (NOT logged — --no-log)' if args.no_log else ''}.\n\n")
        # F8: every instruction this file gives carries the command that performs it.
        f.write(lifecycle_section(batch_id, args.out, audit_path, restore_path,
                                  no_log=args.no_log))
        if args.rule_b:
            n_good = sum(1 for _, _, _, v in rule_b_dropped if v['verdict'] == 'GOOD')
            n_grace = sum(1 for _, _, _, v in rule_b_dropped if v['verdict'] == 'GRACE')
            f.write("## Rule B — the good side is left alone\n\n")
            f.write(f"This book was built with **rule B on**. Rule B judges every keyword on the "
                    f"**window** — the last stretch of finished days — instead of on its 90-day "
                    f"record, and it asks one question: *did this keyword actually work in the "
                    f"window?* A keyword **worked** if it took **{RULE_B_MIN_ORDERS} or more "
                    f"orders** in the window **and** the gross profit those sales left, divided "
                    f"by what the keyword spent, is **at or above its family's bar**. One order "
                    f"is not enough however good the return looks — one sale is mostly luck. "
                    f"Spending with no sale is not working. Two or more orders below the bar is "
                    f"losing.\n\n")
            f.write(f"**A keyword that worked is not touched by this book — neither cut nor "
                    f"raised.** It is earning as it is, and the house rule is that holding pays "
                    f"and churn loses. So every row this book had priced on a working keyword is "
                    f"**dropped**, in both directions, and listed below with its numbers.\n\n")
            f.write(f"**The window was {win_txt}.** The calendar says **{cal_state}**"
                    + ((f" — we are inside the {w0.get('cal_occurrence')} season, which the house "
                        f"calendar (DIM_US_HOLIDAYS, read through V_PEAK_WINDOW_RULE) opens on "
                        f"{w0.get('cal_occurrence_start') or w0.get('cal_peak_start') or 'its recorded start'}"
                        + (f" and turns to peak on {w0['cal_peak_start']}"
                           if w0.get('cal_peak_start') else ""))
                       if b(w0.get('cal_in_peak')) else "")
                    + f". Off-peak the window is {PLAN_WINDOW_DAYS['OFF_PEAK']} days; in the "
                    f"run-up to a peak and inside one it is {PLAN_WINDOW_DAYS['PEAK']} days, "
                    f"because a peak moves too fast to be judged on a week. Those two numbers "
                    f"are **declared in the generator, not read from a settings table** — the "
                    f"plan's settings table (DE_PLAN_CONFIG, ruling P-13) does not exist yet. "
                    f"When it is built, this book reads it instead and nothing else changes. "
                    f"The newest ads day ({w0['watermark']}) is still filling and is deliberately "
                    f"left out: only finished days are judged.\n\n")
            f.write(f"**Attribution caveat — read this before trusting a 'not good' verdict.** "
                    f"The window's sales are still settling. Sponsored Products sales keep "
                    f"arriving for about a week after the click and Sponsored Brands for about "
                    f"two, so a keyword judged in a {win_days}-day window that ends "
                    f"{win_to} has NOT yet been credited with everything it earned. That makes "
                    f"rule B conservative in one direction only: the good side is understated "
                    f"(a keyword called quiet today may be good once its sales land), while a "
                    f"keyword called good has already proved it. This is the known cost of "
                    f"judging on the window; the plan's shadow arm and the T+14 scorecard exist "
                    f"to measure it.\n\n")
            if rule_b_dropped:
                f.write(f"**{len(rule_b_dropped)} row(s) were dropped by rule B** — {n_good} on a "
                        f"keyword the window calls good, {n_grace} held by grace (the ladder "
                        f"calls it a settled winner and its window was merely quiet; a proven "
                        f"winner keeps the good side for one quiet window, held, never cut). "
                        f"Note the limit on grace: there is no two-window memory table yet, so "
                        f"grace here is granted on the ladder's state alone — this book cannot "
                        f"see whether the previous window was also quiet.\n\n")
                if n_grace == 0:
                    f.write(f"(Grace could not fire today by construction: this book only ever "
                            f"prices keywords the ladder has put in AT_BAR, REPRICE, "
                            f"FLOOR_PROBATION or LOSER, so a settled {' / '.join(GRACE_LADDER_STATES)} "
                            f"never reaches it. The rule is implemented and tested for the day the "
                            f"plan's own generator — which does see every keyword — reads it.)\n\n")
                for r, d0, nb0, v in rule_b_dropped:
                    was = ('PAUSE' if d0 == 'PAUSE'
                           else f"{'cut' if d0 == 'BID_DOWN' else 'raise'} "
                                f"${num(r['current_bid'], 0):.2f} -> ${nb0:.2f}")
                    f.write(f"- `{r['target_text']}` in {r['campaign_name']} "
                            f"({r['family'] or 'unmapped'}) — the book had priced a **{was}**; "
                            f"dropped. {v['reason']}\n")
                f.write("\n")
            else:
                f.write("**No row was dropped by rule B today** — every row this book priced "
                        "sits on a keyword the window does not call good.\n\n")
            # WHAT RULE B DID NOT DO. The filter only REMOVES rows on the good side; it does not
            # re-price the not-good side (that is the plan's seat queue, not this book). So a row
            # can survive on a keyword whose WINDOW lost while its 90-day record is above the bar
            # — the ladder and rule B disagreeing out loud. Those rows are named, never buried.
            kept_v = [(r, d, nb, (bits.get('rule_b') or {}))
                      for r, d, nb, cf, bits, st in visible if d in EXECUTABLE]
            disagree = [(r, d, nb, v) for r, d, nb, v in kept_v
                        if v.get('verdict') == 'LOSING' and d == 'BID_UP']
            counts = {}
            for _, _, _, v in kept_v:
                counts[v.get('verdict', '?')] = counts.get(v.get('verdict', '?'), 0) + 1
            f.write("**What rule B did NOT do.** It only takes rows away. It never re-prices a "
                    "keyword and never adds a row, so every row still on the sheet was priced by "
                    "the book's own 90-day doctrine and only survived because the window does "
                    "not call that keyword good. The rows that survived stand on windows that "
                    "say: "
                    + ", ".join(f"{n} {k.lower().replace('_', ' ')}" for k, n in sorted(counts.items()))
                    + ".\n\n")
            if disagree:
                f.write(f"**The ladder and rule B disagree out loud on "
                        f"{len(disagree)} row(s).** Each is a RAISE, because the keyword's settled "
                        f"90-day record sits above its family bar — while the window just past "
                        f"says it lost money. The book raises it (the 90-day record is the "
                        f"deeper evidence and rule B's job here is only to protect the good "
                        f"side), but you are the last gate: delete the line if the window is the "
                        f"story you believe.\n\n")
                for r, d, nb, v in disagree:
                    sheet, ln = line_of[(r['campaign_id'], r['keyword_id'])]
                    f.write(f"- **{sheet} row {ln}** — `{r['target_text']}` in "
                            f"{r['campaign_name']}: raise ${num(r['current_bid'], 0):.2f} -> "
                            f"${nb:.2f}. {v['reason']}\n")
                f.write("\n")
            f.write("---\n\n")
        f.write("**The doctrine every row obeys.** A keyword is judged on which SIDE of its family "
                "bar its settled 90-day record sits, not on its state label. Above the bar it is a "
                "paying keyword and is never pulled down — the only move allowed is a raise, and only "
                "if its own record prices one. Below the bar it is never raised — the only move "
                "allowed is a cut toward what its record affords, never below its channel floor. "
                "A launch family and brand defense never get a profit row. A holdout campaign is "
                "untouchable from 2026-09-01.\n\n")
        f.write(f"**One upload is one move.** The engines step 5% a day and are blind to their own "
                f"move for the {BLIND_STEPS} days spend takes to settle (V_ADS_SETTLE_CURVE: spend is "
                f"at its final value by age 2-3 on both channels; the guard's SP settle discipline is "
                f"3 days). A hand upload gets no further steps before its next re-read, so it is "
                f"capped at the engine's blind run: (1.05)^{BLIND_STEPS} - 1 = +{CAP_UP*100:.2f}% up, "
                f"1 - (0.95)^{BLIND_STEPS} = -{CAP_DOWN*100:.2f}% down. {n_capped} row(s) were capped; "
                f"the record's own price is printed beside each so the next book can step again.\n\n")
        f.write(f"**Too thin to price.** A bid move resting on {THIN_ORDERS} or fewer settled orders "
                f"is not on this sheet: {TOO_THIN_REASON}. With one order the noise band equals "
                f"the reading itself, so the keyword sits at its bar by construction and the side "
                f"of the bar is noise. {len(thin)} such row(s) are listed below, shown not "
                f"executed. A floor landing (probation) is not an evidence-based move and is "
                f"exempt.\n\n")
        f.write("**Prices.** The record's affordable cost per click (settled gross profit per click "
                f"divided by the family bar) becomes a bid through the keyword's OWN realised cost "
                f"per click at its current bid where it has {VOL_FLOOR}+ settled clicks since its "
                "last bid change — V_BID_CPC_TRANSFER's model in ratio form, where the campaign "
                "placement multiplier and the segment constant cancel; otherwise through the "
                "campaign model (k x M, gamma). Rows whose own ratio sits more than one model RMSE "
                "from the campaign model are flagged PLACEMENT_DIVERGES. The 7-day figures in the "
                "audit are context only — no verdict and no price reads them.\n\n")
        f.write(f"**{len(executable)} executable rows**: {n_down} bid-downs, {n_up} bid-ups, "
                f"{n_pause} pauses"
                + (f" — after rule B dropped {len(rule_b_dropped)} row(s) on good keywords"
                   if args.rule_b else "")
                + f". Held back by doctrine: {n_no_cut} above-bar row(s) whose standing "
                f"price would have cut them (NO_CUT_ABOVE_BAR), {n_no_raise} below-bar row(s) whose "
                f"placement translation would have raised them (NO_RAISE_BELOW_BAR). Bid-space "
                f"totals: −${bid_down_total:.2f} across the downs, +${bid_up_total:.2f} across the "
                f"ups (bid deltas, not spend forecasts). The rows being cut or paused spent "
                f"${down_spend7:.2f} in the last 7 days; the rows being raised spent ${up_spend7:.2f}.\n\n")
        n_prob = sum(1 for r, d, _ in executable if r['state'] == 'FLOOR_PROBATION')
        f.write(f"Floors are per channel and creative (SP $0.20 house; SB collection $0.10 and "
                f"SB video $0.25, Amazon's minimums) — never a flat number. {n_prob} row(s) move a "
                f"keyword toward its floor (probation). The state machine's probation clock starts "
                f"only on the day a bid AT the floor actually lands (it reads the applied change "
                f"log); until then the state says 'waiting for the floor bid'. It re-judges once "
                f"{VOL_FLOOR} settled clicks exist at the floor, and only a keyword that still fails "
                f"AFTER that probation can ever become a pause. "
                f"{'No keyword has completed a probation yet, so there are no pauses today.' if n_pause == 0 else ''}\n\n")
        f.write("Every row echoes its campaign's last non-null portfolio. On a Campaign row a blank "
                "portfolio cell DETACHES the campaign; on the keyword/target rows this book emits, "
                "Amazon ignores the column — the echo is a uniform convention, not a lever. ")
        if null_pf:
            f.write("Portfolio caveat: the LATEST campaign-history row carries a NULL portfolio for "
                    + "; ".join(f"**{n}** (echoing older {p})" for n, p in null_pf)
                    + " — Amazon currently reports these campaigns without a portfolio; the echoed "
                    "id is the last one seen and is not what these keyword rows change.\n\n")
        else:
            f.write("\n\n")
        f.write("Pauses are reversible with one enabled row; the restore sheet next to this file "
                "carries every old value back.\n\n")
        f.write(f"**Provenance.** The batch `{batch_id}` in FACT_PPC_CHANGE_LOG holds exactly the "
                f"{len(executable)} rows on this sheet (asserted after the insert), each with its "
                f"old and new bid and an upload note. **If you do not upload this book, label the "
                f"batch `SUPERSEDED_NEVER_UPLOADED`** (never delete a log row); if you delete a line "
                f"before uploading, label that row `FAILED_UPLOAD`. Otherwise the scorecard grades "
                f"moves that never happened and the guard treats them as applied. "
                f"**The commands for all of that are in 'What to do with this file' at the top of "
                f"this page.**\n\n")
        if holdout_allowed or armed:
            f.write(f"**Holdout interlock.** Campaigns in the HOLDOUT arm are excluded from this "
                    f"book from **{armed[0] if armed else 'n/a'}**; today that excluded "
                    f"{len(holdout_hits)} row(s). {len(holdout_allowed)} executable row(s) sit in "
                    f"holdout-arm campaigns and are allowed today by the letter — upload this book "
                    f"BEFORE that date or delete these lines; a hand upload into the holdout after "
                    f"it invalidates the trial:\n\n")
            for r, d, nb in holdout_allowed:
                sheet, ln = line_of[(r['campaign_id'], r['keyword_id'])]
                f.write(f"- {sheet} row {ln} — `{r['target_text']}` in {r['campaign_name']} "
                        f"({d} ${num(r['current_bid'],0):.2f} -> "
                        f"{('$%.2f' % nb) if nb else 'PAUSE'}), excluded from {r['holdout_eligible_from']}\n")
            f.write("\n")
        if check_rows:
            f.write("---\n\n## CHECK FIRST — eyeball these before uploading\n\n")
            for r, disp, nb, st in check_rows:
                sheet, ln = line_of.get((r['campaign_id'], r['keyword_id']), ('not in sheet', ''))
                f.write(f"- **{sheet} row {ln}** — `{r['target_text']}` in {r['campaign_name']}: {st}\n")
            f.write("\n")
        if thin:
            f.write(f"---\n\n## Too thin to price — shown, not executed ({len(thin)})\n\n")
            for r, st in thin:
                f.write(f"- `{r['target_text']}` in {r['campaign_name']} "
                        f"({int(num(r['settled_ord90'], 0))} settled order(s)): {st}\n")
            f.write("\n")
        if blocked:
            f.write("---\n\n## Blocked by the season ledger — shown, not executed\n\n")
            for r, st in blocked:
                f.write(f"- `{r['target_text']}` in {r['campaign_name']}: {st}\n")
            f.write("\n")
        f.write("---\n\n## Row by row\n\n")
        for r, disp, nb, cf, bits, st in visible:
            if disp not in EXECUTABLE:
                continue
            sheet, ln = line_of[(r['campaign_id'], r['keyword_id'])]
            f.write(f"### {sheet} — row {ln}: `{r['target_text']}` ({r['campaign_name']})\n\n")
            f.write(f"- {st}\n")
            f.write(f"- Delete this line and `{r['target_text']}` keeps its current bid/state; "
                    f"nothing else in the sheet changes — then label its change-log row "
                    f"FAILED_UPLOAD.\n\n")
        others = [(r, disp, st) for r, disp, nb, cf, bits, st in visible
                  if disp not in EXECUTABLE + ('SEASON_BLOCKED', 'TOO_THIN', RULE_B_GOOD)]
        if others:
            f.write("---\n\n## Candidates with no executable row (audit visibility)\n\n")
            for r, disp, st in others:
                f.write(f"- `{r['target_text']}` ({r['campaign_name']}) — {disp}: {st}\n")

    # ---- review table ---------------------------------------------------------------
    print(f"\n{len(rows)} candidate rows -> {len(executable)} executable "
          f"({n_down} down · {n_up} up · {n_pause} pause) · "
          + (f"{len(rule_b_dropped)} dropped by rule B · " if args.rule_b else "")
          + f"{len(blocked)} season-blocked · {len(thin)} too thin · "
          f"{len(rows) - len(executable) - len(blocked) - len(thin) - len(rule_b_dropped)} other\n")
    hdr = f"{'target':<30} {'campaign':<34} {'st':<8} {'side':<5} {'ord':>3} {'old':>5} {'new':>5} {'raw':>5}  disposition"
    print(hdr)
    print('-' * len(hdr))
    for r, disp, nb, cf, bits, st in visible:
        mark = ' *CHECK FIRST*' if (cf and disp in EXECUTABLE) else ''
        raw = bits.get('raw_bid')
        print(f"{(r['target_text'] or '')[:29]:<30} {(r['campaign_name'] or '')[:33]:<34} "
              f"{r['state'][:8]:<8} {(bits.get('side') or '')[:5]:<5} {int(num(r['settled_ord90'],0)):>3} "
              f"{num(r['current_bid'], 0):>5.2f} "
              f"{(f'{nb:.2f}' if nb else ('PAUSE' if disp == 'PAUSE' else '-')):>5} "
              f"{(f'{raw:.2f}' if raw is not None else '-'):>5}  {disp}{mark}")

    # ---- change log -----------------------------------------------------------------
    prior = prior_unmarked_batches()
    if prior:
        print("\nEarlier reprice batches still PENDING_UPLOAD (waiting on Ori; an applied batch is never listed here):")
        for p in prior:
            print(f"  {p['batch_id']}  {p['n']} rows  {p['upload_status']}  first {p['first_at']}")
    logged = ''
    if executable and not args.no_log:
        if args.supersede:
            supersede(args.supersede, batch_id)
        n_logged = log_batch(executable, batch_id, readme_path)
        logged = batch_id
        print(f"\nLogged {n_logged} rows to {CHANGE_LOG.split('.')[-1]} as batch {logged} — read back and "
              f"asserted equal to the {len(executable)} sheet rows "
              f"(label SUPERSEDED_NEVER_UPLOADED if the book is not uploaded).")

    # F8: publish only now. Until this line the three outputs carry a .partial suffix, so a
    # build that died before the log leaves no book at the output path naming a batch that
    # does not exist. A book on disk means its batch is in the change log.
    publish_drafts([args.out, audit_path, readme_path])

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
