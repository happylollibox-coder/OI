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
from collections import Counter
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
# The plan's settings live in DE_PLAN_CONFIG by ruling P-13, and as of v27.131 THIS GENERATOR
# READS THAT TABLE (read_plan_config() below, called once at the top of a build). The values
# below are the DECLARED FALLBACK, used only when the table cannot be read — and when they are
# used the README says so on the page, because a book must never quote a setting it did not read.
#   PLAN_WINDOW_DAYS   P-13: OFF-PEAK 7 complete days · BOOST 3 · PEAK 3.
#   RULE_B_MIN_ORDERS  P-3: one order at 3x is mostly luck; two is the cheapest guard.
#   GRACE_LADDER_STATES P-5: the ladder's settled-winner states. Grace buys ONE window, and only
#                      for a QUIET window (under the order floor) — a window with 2+ orders is
#                      evidence, and rule B stands over it. v27.137: the limit is now READ, not
#                      assumed away — SP_BUILD_NEXT_WEEK_PLAN writes FACT_PLAN_NEXT_WEEK nightly
#                      and the `plan_grace` CTE below reads the live plan's own history with the
#                      same expression V_PLAN_WINDOW_JUDGMENT uses, so a keyword whose grace is
#                      already spent is refused here exactly as it is refused there. One keyword,
#                      one judge.
PLAN_WINDOW_DAYS = {'OFF_PEAK': 7, 'BOOST': 3, 'PEAK': 3}
RULE_B_MIN_ORDERS = 2
GRACE_LADDER_STATES = ('WINNER', 'PACED_WINNER')
RULE_B_GOOD = 'RULE_B_GOOD'          # the disposition a dropped row carries
PLAN_CONFIG_SOURCE = 'fallback'      # set by read_plan_config(); 'DE_PLAN_CONFIG' or 'fallback'


def read_plan_config():
    """P-13: the plan's settings are DATA, not literals. Reads the latest ACTIVE row per calendar
    state from DE_PLAN_CONFIG and rebinds PLAN_WINDOW_DAYS and RULE_B_MIN_ORDERS onto it, so a
    setting Ori changes without a deploy reaches the one book that currently moves money.

    If the table cannot be read, or does not carry all three states, the declared fallbacks above
    stand and PLAN_CONFIG_SOURCE stays 'fallback' — which the README then prints, naming the
    numbers as declared-in-the-generator rather than read. Never silently.
    """
    global PLAN_WINDOW_DAYS, RULE_B_MIN_ORDERS, PLAN_CONFIG_SOURCE
    sql = f"""
    SELECT calendar_state, window_days, min_orders, allowance_share, ramp_steps, live_plan
    FROM `{PROJECT}.OI.DE_PLAN_CONFIG`
    WHERE is_active
    QUALIFY ROW_NUMBER() OVER (PARTITION BY calendar_state ORDER BY updated_at DESC) = 1
    """
    out = subprocess.run(
        ['bq', 'query', '--use_legacy_sql=false', '--format=json', '--nouse_cache',
         f'--project_id={PROJECT}', sql],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        tail = out.stderr.strip().splitlines()[-1] if out.stderr.strip() else 'no detail'
        print(f"DE_PLAN_CONFIG unreadable ({tail}); the generator's declared fallback settings "
              f"stand and the README will say so.")
        return {}
    rows = json.loads(out.stdout or '[]')
    cfg = {r['calendar_state']: r for r in rows}
    if not all(st in cfg for st in ('OFF_PEAK', 'BOOST', 'PEAK')):
        print("DE_PLAN_CONFIG does not carry all three calendar states; the declared fallback "
              "settings stand and the README will say so.")
        return {}
    floors = {int(cfg[st]['min_orders']) for st in ('OFF_PEAK', 'BOOST', 'PEAK')}
    if len(floors) > 1:
        sys.exit(f"DE_PLAN_CONFIG carries different min_orders per state {sorted(floors)}; rule B "
                 f"has one order floor (P-3). Make them agree before building a book.")
    PLAN_WINDOW_DAYS = {st: int(cfg[st]['window_days']) for st in ('OFF_PEAK', 'BOOST', 'PEAK')}
    RULE_B_MIN_ORDERS = floors.pop()
    PLAN_CONFIG_SOURCE = 'DE_PLAN_CONFIG'
    return cfg


def window_bounds(watermark, window_days, today_la=None):
    """P-10 COMPLETE DAYS ONLY + THE P-14a FENCE. The window is `window_days` days ending at
    `window_to = LEAST(watermark - 1, today_la - 2)`: the filling day never enters a window, and
    neither does a day younger than two, because the anchor cap advances at 22:00 Los Angeles and
    the published settle curve puts an age-1 day's SPEND materially short of final. Before 22:00
    the two terms are equal and the fence costs nothing. Returns (window_from, window_to)."""
    wm = watermark if isinstance(watermark, date) else date.fromisoformat(str(watermark))
    window_to = wm - timedelta(days=1)
    if today_la is not None:
        t = today_la if isinstance(today_la, date) else date.fromisoformat(str(today_la))
        window_to = min(window_to, t - timedelta(days=2))
    return window_to - timedelta(days=window_days - 1), window_to


def assert_window_complete(watermark, window_from, window_to, window_days, today_la=None):
    """The guarantee spec §9 asks for, run against whatever the query actually returned."""
    lo, hi = window_bounds(watermark, window_days, today_la)
    def d(v):
        return v if isinstance(v, date) else date.fromisoformat(str(v))
    assert d(window_to) == hi, (f"the window ends {window_to}, not {hi} — a window may never "
                                f"touch the filling day {watermark}")
    assert d(window_from) == lo, (f"the window starts {window_from}, not {lo} — "
                                  f"{window_days} complete days end at {hi}")


def legacy_calendar_state(in_peak, peak_start, today):
    """THE OLD RULE, KEPT ONLY TO REPORT WHEN IT DISAGREES WITH THE PLAN'S AUTHORITY.

    Until v27.132 this book derived the calendar state itself: OFF_PEAK outside a season; inside
    one, BOOST from the SINGLE OWNING occurrence's boost_start (V_PEAK_WINDOW_RULE resolves the
    owner as the earliest boost_start) until its peak_start, PEAK from then on, compared on the
    Los Angeles date. FN_PLAN_CALENDAR_STATE — the plan's declared authority, and the key
    DE_PLAN_CONFIG is read by — uses a different precedence (a peak ANYWHERE wins) on the New
    York date. P-11 says one engine, so the function decides and this is only an alarm: swept
    across 2026 the two part on 24 days, the whole Black-Friday run-up, where this rule says
    BOOST (allowance_share 0.50) and the authority says PEAK (0.20). Re-derive the sweep rather
    than trusting the sentence; the SOP publishes the query."""
    if not in_peak:
        return 'OFF_PEAK'
    if peak_start and str(today) < str(peak_start):
        return 'BOOST'
    return 'PEAK'


def rule_b(r):
    """P-1/P-3/P-5/P-14 — judge ONE keyword on the WINDOW. Returns
    {'good': bool, 'verdict': str, 'reason': plain-English sentence, 'ret': float|None,
     'settle_arm': str, 'decided_by': str, 'settle_due_on': str|None}.

    The margin is the ladder's own: window gross profit is SUM(FACT_AMAZON_ADS.GROSS_PROFIT) over
    the window at the keyword's own grain — the same stored column V_KEYWORD_GUARD sums for
    settled_gp90 and the bar is compared against (see THE GP RULE in that view). No margin is
    invented here and nothing is hardcoded.

    P-14, BUILT AS SPECIFIED AND SAID ON EVERY ROW (Ori has not ruled; to overrule, one sentence:
    "judge the window as it reads"):
      (a) CORRECTION — the judged margin is the window's gross profit divided, per day, by the
          published completion factor for the day's channel and age (V_ADS_SETTLE_CURVE, read as
          a table by the query). Because every factor is <= 1 the correction can only ever RAISE
          the margin, so it can only ever PROMOTE. Where the curve cannot answer for a day the
          factor is 1.0 and the row says UNCORRECTED_NO_CURVE. Order COUNTS are never inflated.
      (b) ASYMMETRIC GUARD — a keyword may be promoted on fresh corrected evidence, but it is
          never demoted until its window has SETTLED (SP 7 / SB 14 complete days after
          window_to). A would-be demotion of a keyword that WAS good is held, on the good side,
          with its settle-due date on the row. "Was good" here is the bootstrap the spec
          declares: the ladder's own settled 90-day record at or above the family bar with the
          order floor met (there is no previous night's plan to read — the plan's own tables are
          Task 1, and this book is the only live judge until they exist).
      (c) Every row publishes settle_arm and decided_by, and the plain-English reason says which
          arm decided it and when the window settles.

    verdict: GOOD · GRACE · HELD_UNSETTLED · LOSING · ONE_ORDER · NO_SALE · NOT_SERVING.
    """
    ordw = int(num(r.get('w_ord'), 0) or 0)
    clkw = int(num(r.get('w_clk'), 0) or 0)
    spw = num(r.get('w_sp'), 0) or 0.0
    gpw = num(r.get('w_gp'), 0) or 0.0
    # w_gp_corr is always supplied by the query. A caller that does not supply it gets the raw
    # margin and is told so on the row rather than silently judged on a zero.
    gpc = num(r.get('w_gp_corr'), None)
    no_curve = int(num(r.get('w_days_no_curve'), 0) or 0) > 0
    if gpc is None:
        gpc, no_curve = gpw, True
    settled = b(r.get('window_settled'))
    due = r.get('settle_due_on')
    bar = num(r.get('family_bar'), 1.0)
    bar = 1.0 if bar is None else bar

    ret_raw = (gpw / spw) if spw > 0 else None
    ret = (gpc / spw) if spw > 0 else None          # P-14a: the corrected margin is the judged one
    days = r.get('window_days')
    win = (f"the {days}-day window {r.get('window_from')} to {r.get('window_to')}"
           if r.get('window_from') else "the window")

    # WHICH ARM IS SPEAKING, before any verdict. The order and the arms are the ones
    # V_PLAN_WINDOW_JUDGMENT publishes, so the book and the view never name different work on the
    # same keyword (v27.135 alignment; before it, EVERY row in this book's audit read CORRECTED —
    # including keywords that never served and keywords that sold nothing, neither of which any
    # correction touched).
    served = (spw > 0 or clkw > 0)
    if not served and gpw == 0:
        # nothing was read, so nothing was corrected and nothing is in flight
        arm = 'SETTLED'
    elif no_curve:
        arm = 'UNCORRECTED_NO_CURVE'
    elif ret is not None and ret_raw is not None and ret >= bar > ret_raw:
        arm = 'PROMOTED_ON_FRESH'
    elif settled:
        arm = 'SETTLED'
    elif gpw == 0:
        # the correction SCALES gross profit and this window has none: zero over any factor is
        # zero, so no correction was possible and the row must not claim one
        arm = 'NOT_CORRECTABLE_NO_GP'
    else:
        arm = 'CORRECTED'

    lift = (f", lifted from {ret_raw:.2f} by the settle correction"
            if (ret is not None and ret_raw is not None and ret - ret_raw > 0.005) else "")
    took = (f"{ordw} order(s) on ${spw:.2f} of ad spend in {win}"
            + (f", returning {ret:.2f} gross-profit dollars per ad dollar{lift} against its "
               f"{r.get('family') or 'family'} bar of {bar:.2f}" if ret is not None else ""))
    no_gp = (served and gpw == 0)
    if settled:
        caveat = ""
    elif no_gp:
        caveat = (f" NOT YET SETTLED: the window's orders are still arriving (SP 7 / SB 14 "
                  f"complete days), so this reading settles on {due}. NO CORRECTION WAS APPLIED "
                  f"AND NONE WAS POSSIBLE: the settle correction scales gross profit and this "
                  f"window has none, so only the order floor (P-3) or the guard (P-14b) can "
                  f"change this side (P-14a).")
    else:
        caveat = (f" NOT YET SETTLED: the window's orders are still arriving (SP 7 / SB 14 complete "
                  f"days), so this reading settles on {due}. The margin above is CORRECTED for "
                  f"settle completion from the published curve"
                  + (" — except that the curve could not answer for at least one day of this "
                     "window, so that day was left uncorrected (P-14a)." if no_curve else
                     " (P-14a); order counts are never corrected."))

    def out(good, verdict, decided_by, reason, arm_override=None):
        return {'good': good, 'verdict': verdict, 'ret': ret, 'ret_raw': ret_raw,
                'settle_arm': arm_override or arm, 'decided_by': decided_by,
                'settle_due_on': None if settled else due, 'reason': reason}

    if ordw >= RULE_B_MIN_ORDERS and ret is not None and ret >= bar:
        return out(True, 'GOOD', 'P-3',
                   f"GOOD on the window — {took}. The good side is never cut and is not "
                   f"re-priced, so this keyword is left exactly as it is (P-4)."
                   + (f" Decided by the {arm} arm." if arm != 'SETTLED' else "") + caveat)

    # P-5, WITH ITS LIMIT (v27.137). prior_grace is the LIVE PLAN's own memory, read in the SQL
    # from FACT_PLAN_NEXT_WEEK with the same expression V_PLAN_WINDOW_JUDGMENT uses — one judge,
    # one answer. A second quiet window in a row falls through to the guard and then to rule B.
    prior_grace = bool(r.get('prior_grace'))
    armed = bool(r.get('grace_limit_armed'))
    if ordw < RULE_B_MIN_ORDERS and (r.get('state') or '') in GRACE_LADDER_STATES \
            and not prior_grace:
        return out(True, 'GRACE', 'P-5',
                   f"GRACE — the ladder calls this a settled winner ({r.get('state')}) and "
                   f"its window is quiet: {took}. A proven winner keeps the good side for "
                   f"ONE quiet window (P-5), held, not cut. "
                   + (f"This is that window: the limit is ARMED — the plan's own history in "
                      f"FACT_PLAN_NEXT_WEEK is read on every build — so grace is now SPENT and "
                      f"will be refused until this keyword earns a GOOD window back."
                      if armed else
                      f"THE LIMIT IS NOT ARMED FOR THIS KEYWORD YET: it is read from the live "
                      f"plan's own history in FACT_PLAN_NEXT_WEEK and no partition earlier than "
                      f"today exists to read, so grace is granted on the ladder state alone this "
                      f"run. From the plan's next nightly build the limit bites.")
                   + f" V_PLAN_WINDOW_JUDGMENT and this book read the same memory with the same "
                     f"expression, so they cannot answer differently." + caveat)

    # P-14b: never demote a keyword that was good until its window has settled.
    sgp, ssp = num(r.get('settled_gp90'), 0) or 0.0, num(r.get('settled_sp90'), 0) or 0.0
    was_good = (int(num(r.get('settled_ord90'), 0) or 0) >= RULE_B_MIN_ORDERS
                and ssp > 0 and (sgp / ssp) >= bar)
    # THE GUARD REQUIRES SERVICE (v27.135 alignment with V_PLAN_WINDOW_JUDGMENT). P-14b exists
    # because sales are still ARRIVING; a keyword with no spend and no clicks in the window has
    # none in flight, so the guard has no basis and must not hold it. Without this clause the book
    # held such rows on the good side — where P-4 forbids re-pricing them — while its own
    # NOT SERVING text said, correctly, that nothing was arriving. Rule B only ever REMOVES a move,
    # so the clause returns those keywords to whatever the engine itself proposed for them.
    if was_good and not settled and served:
        return out(True, 'HELD_UNSETTLED', 'P-14b',
                   f"HELD, NOT DEMOTED (P-14b) — {took}, which would put it on the not-good "
                   f"side. Its window has not settled, and the ladder's own settled 90-day "
                   f"record clears the {r.get('family') or 'family'} bar of {bar:.2f} on "
                   f"{int(num(r.get('settled_ord90'), 0) or 0)} settled orders, so it keeps the "
                   f"good side until {due}. A keyword may be promoted on fresh evidence but "
                   f"never demoted on it: unmeasured never reads as bad." + caveat,
                   arm_override='HELD_UNSETTLED')

    if ordw >= RULE_B_MIN_ORDERS:
        return out(False, 'LOSING', 'P-3',
                   f"LOSING on the window — {took}, under the bar." + caveat)
    if ordw == 1:
        return out(False, 'ONE_ORDER', 'P-3',
                   f"WAITING, one order — {took}. One order is not evidence whatever the "
                   f"return, so this keyword is on the not-good side." + caveat)
    if spw > 0 or clkw > 0:
        return out(False, 'NO_SALE', 'P-3',
                   f"NO SALE — {took}. Spend with no order is on the not-good side." + caveat)
    return out(False, 'NOT_SERVING', 'P-3',
               f"NOT SERVING — no spend and no clicks in {win}. There is nothing here for the "
               f"settle curve to correct and nothing arriving later: a keyword that took no "
               f"clicks has no sales in flight"
               + ("" if settled else
                  f", so the settle question does not arise even though the window itself does "
                  f"not settle until {due} (P-14)") + ".")


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
  -- THE HOUSE WATERMARK (P-10, SOP §1): LEAST(MAX(date), FN_ADS_ANCHOR_CAP()), never a bare
  -- MAX(date). v27.132 defect, measured: at 10:15 America/Los_Angeles on 2026-08-23 the raw
  -- MAX(date) was 2026-08-23 while FN_ADS_ANCHOR_CAP() was 2026-08-22, so this book's window
  -- ended on a day ONE day old — and V_ADS_SETTLE_CURVE publishes SP spend at ~5/6 and SP sales
  -- at ~2/3 of final at age 1. It judged good vs not-good on a day a third of whose sales had
  -- not arrived, which is exactly the defect Ori raised P-14 for. Read the curve, never a
  -- literal: SELECT channel, age_days, spend_pct_of_final_median, sales_pct_of_final_median
  -- FROM `{p}.OI.V_ADS_SETTLE_CURVE` WHERE age_days <= 2 ORDER BY channel, age_days.
  -- The cap also governs live7 and the `own` settled frame below: one day older, strictly safer,
  -- and one definition of "the last complete ads day" in this file instead of two.
  SELECT LEAST(MAX(date), `{p}.OI.FN_ADS_ANCHOR_CAP`()) AS d FROM `{p}.OI.FACT_AMAZON_ADS`
),
ks AS (
  SELECT * FROM `{p}.OI.V_KEYWORD_STATE`
  WHERE state IN ('AT_BAR','REPRICE','FLOOR_PROBATION','LOSER')
),
-- P-5's ONE-WINDOW LIMIT, READ FROM THE PLAN'S OWN MEMORY (v27.137). Until SP_BUILD_NEXT_WEEK_PLAN
-- shipped there was no memory to read and this generator granted grace on the ladder state alone,
-- saying so on every row. The builder now writes FACT_PLAN_NEXT_WEEK nightly and
-- V_PLAN_WINDOW_JUDGMENT arms the limit from it — so a book that kept computing grace in Python
-- would become a SECOND JUDGE of the same ruling on the same keyword, which is the defect v27.135
-- was written to close. Same expression as the view: grace is SPENT until the keyword earns a GOOD
-- window back, i.e. its most recent GRACE is later than its most recent GOOD (or it has never had
-- one). Empty table => no rows => prior_grace FALSE everywhere, exactly as before.
plan_grace AS (
  SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
         (MAX(IF(verdict = 'GRACE', as_of, NULL)) IS NOT NULL
          AND (MAX(IF(verdict = 'GOOD', as_of, NULL)) IS NULL
               OR MAX(IF(verdict = 'GRACE', as_of, NULL))
                  > MAX(IF(verdict = 'GOOD', as_of, NULL)))) AS prior_grace
  FROM `{p}.OI.FACT_PLAN_NEXT_WEEK`
  WHERE is_live_plan AND as_of < CURRENT_DATE('America/Los_Angeles')
  GROUP BY 1, 2
),
plan_armed AS (
  SELECT COUNT(*) > 0 AS grace_limit_armed
  FROM `{p}.OI.FACT_PLAN_NEXT_WEEK`
  WHERE is_live_plan AND as_of < CURRENT_DATE('America/Los_Angeles')
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
-- LENGTHS are substituted from DE_PLAN_CONFIG, read once at the top of the build (P-13); this
-- file's own constants are only the fallback for when that table cannot be read.
cal AS (
  SELECT pw.in_peak, pw.occurrence_type, pw.occurrence_start, pw.w_days AS helper_w_days,
         (SELECT MIN(h.peak_start) FROM `{p}.OI.DIM_US_HOLIDAYS` h
          WHERE h.category IN ('gift_season','prime_event','back_to_school','seasonal')
            AND h.boost_start = pw.occurrence_start) AS peak_start
  FROM `{p}.OI.V_PEAK_WINDOW_RULE` pw
),
-- P-11, ONE ENGINE, ONE CALENDAR AUTHORITY. The state is FN_PLAN_CALENDAR_STATE on the New York
-- calendar date — the plan's declared authority, the one DE_PLAN_CONFIG is keyed by and the one
-- PLAN_CONFIG_acceptance C03 asserts. Until v27.132 this CTE derived the state itself, from
-- V_PEAK_WINDOW_RULE's SINGLE owning occurrence (earliest boost_start wins) on the Los Angeles
-- date. That is a DIFFERENT PRECEDENCE from the function's (a peak anywhere wins) and it is not
-- academic: swept across 2026 the two agree on 341 days and part on 24 — 2026-10-10..2026-11-02,
-- the whole Black-Friday run-up — where the old rule said BOOST (allowance_share 0.50) and the
-- plan's authority says PEAK (0.20). Re-derive it rather than trusting this comment; the sweep
-- is published in the SOP. The old rule is kept in Python as legacy_calendar_state() and the
-- build prints a WARNING when the two disagree, so the divergence is visible, not silent.
st AS (
  SELECT cal.*,
         `{p}.OI.FN_PLAN_CALENDAR_STATE`(CURRENT_DATE('America/New_York')) AS calendar_state
  FROM cal
),
winr AS (
  SELECT st.*, w.window_days, w.window_to,
         DATE_SUB(w.window_to, INTERVAL w.window_days - 1 DAY) AS window_from
  FROM (
    SELECT st.calendar_state,
           CASE st.calendar_state WHEN 'OFF_PEAK' THEN {w_off} WHEN 'BOOST' THEN {w_boost}
                ELSE {w_peak} END AS window_days,
           -- P-10 COMPLETE DAYS ONLY + THE P-14a FENCE. The window ends at wm - 1, and never on
           -- a day younger than two: FN_ADS_ANCHOR_CAP() advances to the current Los Angeles
           -- date at 22:00 LA, so wm - 1 alone can still be an age-1 day, where the published
           -- curve puts spend materially short of final. Before 22:00 the two terms are equal
           -- and the fence costs nothing; after it, the fence gives up one day rather than judge
           -- money on a day the warehouse has not finished writing. Spec P-14a, section 3.
           LEAST(DATE_SUB(wm.d, INTERVAL 1 DAY),
                 DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 2 DAY)) AS window_to
    FROM st CROSS JOIN wm
  ) w
  JOIN st ON st.calendar_state = w.calendar_state
),
-- the channel of each judged keyword, for the settle curve and the settle clock (SP 7 / SB 14)
ksch AS (
  SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
         ANY_VALUE(channel) channel
  FROM ks GROUP BY 1, 2
),
-- the keyword's own record in the window. GP is FACT_AMAZON_ADS.GROSS_PROFIT, the stored column
-- the ladder's own guard sums for settled_gp90 — the same margin source, not a new one.
kwin AS (
  SELECT CAST(f.campaign_id AS STRING) cid, CAST(f.keyword_id AS STRING) kid,
         SUM(f.Ads_cost) w_sp, SUM(f.Ads_clicks) w_clk, SUM(f.Ads_orders) w_ord,
         SUM(f.GROSS_PROFIT) w_gp,
         -- P-14a THE CORRECTION: each DAY's gross profit divided by the published completion
         -- factor for its channel and its age, read as a table — never a literal and never a
         -- hardcoded factor. THE SOURCE IS V_PLAN_SETTLE_COMPLETION, NOT THE RAW CURVE (v27.135):
         -- this file used to divide by V_ADS_SETTLE_CURVE.sales_pct_of_final_median directly,
         -- with none of the plan view's safety — no 1.0 cap, no 0.50 floor, no monotone-in-age
         -- smoothing and no thin-curve gate. That is latent today (no published median exceeds
         -- 100) and wrong the day the curve is rebuilt: a median above 100 would SHRINK a window's
         -- gross profit, breaking the §9 guarantee that the correction is never smaller in
         -- magnitude, in the one path that is live; and a thin low-age median would inflate it
         -- without the declared twofold ceiling. One curve source now answers for the book and
         -- the plan, so the two can never correct the same keyword differently.
         -- Where the curve cannot answer, the factor is 1.0 and w_days_no_curve counts the day,
         -- so the row can say the correction was unavailable and rest on the asymmetric guard
         -- alone. ORDER COUNTS ARE NEVER INFLATED
         -- (a count cannot be fractionally corrected), so w_ord above is the observed count and
         -- the P-3 floor is always read on it.
         SUM(f.GROSS_PROFIT / COALESCE(sc.sales_completion, 1.0)) w_gp_corr,
         COUNTIF(NOT COALESCE(sc.curve_available, FALSE)) w_days_no_curve
  FROM `{p}.OI.FACT_AMAZON_ADS` f
  CROSS JOIN winr
  JOIN ksch ON ksch.cid = CAST(f.campaign_id AS STRING)
           AND ksch.kid = CAST(f.keyword_id AS STRING)
  LEFT JOIN `{p}.OI.V_PLAN_SETTLE_COMPLETION` sc
    ON sc.channel  = ksch.channel
   AND sc.age_days = LEAST(DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), f.date, DAY), 120)
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
  -- P-14a / P-14b: the corrected window margin, whether the curve could answer, and the clock
  COALESCE(kwin.w_gp_corr, 0) AS w_gp_corr,
  COALESCE(kwin.w_days_no_curve, 0) AS w_days_no_curve,
  ks.settled_gp90, ks.settled_sp90,
  COALESCE(pg.prior_grace, FALSE) AS prior_grace,
  pa.grace_limit_armed,
  CAST(DATE_ADD(winr.window_to,
                INTERVAL IF(ks.channel = 'SB', 14, 7) DAY) AS STRING) AS settle_due_on,
  CURRENT_DATE('America/Los_Angeles')
    >= DATE_ADD(winr.window_to, INTERVAL IF(ks.channel = 'SB', 14, 7) DAY) AS window_settled,
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
LEFT JOIN plan_grace pg ON pg.cid = ks.campaign_id AND pg.kid = ks.keyword_id
CROSS JOIN wm
CROSS JOIN winr
CROSS JOIN plan_armed pa
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

    # P-13: settings first, so the window lengths substituted into the query are the ones the
    # settings table declares — not the ones this file happens to carry.
    read_plan_config()

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
    assert_window_complete(w0['watermark'], win_from, win_to, win_days, today_la)
    assert win_days == PLAN_WINDOW_DAYS[cal_state], \
        f"the query returned a {win_days}-day window for {cal_state}; P-13 declares " \
        f"{PLAN_WINDOW_DAYS[cal_state]}"
    # P-11: FN_PLAN_CALENDAR_STATE decides. The OLD in-book rule is kept only as an alarm — it
    # parts from the authority on the Black-Friday run-up, where it said BOOST (share 0.50) and
    # the authority says PEAK (0.20). Never silent.
    legacy_state = legacy_calendar_state(b(w0.get('cal_in_peak')), w0.get('cal_peak_start'),
                                         today_la)
    if legacy_state != cal_state:
        print(f"WARNING — CALENDAR DIVERGENCE: the plan's authority FN_PLAN_CALENDAR_STATE says "
              f"{cal_state} for {today_la}; the rule this book used before v27.132 says "
              f"{legacy_state}. The authority wins (P-11) and DE_PLAN_CONFIG is read on it. "
              f"This is a ruling for Ori, not a bug to patch here — see architecture/"
              f"NEXT_WEEK_MONEY.md.")
    fenced = (date.fromisoformat(str(win_to))
              != date.fromisoformat(str(w0['watermark'])) - timedelta(days=1))
    win_txt = (f"{win_days} complete days, {win_from} to {win_to} (the ads watermark is "
               f"{w0['watermark']} and never enters the window"
               + ("; the P-14a fence gave up one more day so that no judged day is younger than "
                  "two — the anchor cap has advanced past 22:00 Los Angeles" if fenced else "")
               + ")")
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
                     # P-14: rule_b_gp is the OBSERVED window gross profit; rule_b_gp_corrected
                     # is the same money divided by the published settle-completion factor per
                     # day (V_ADS_SETTLE_CURVE), which is the margin rule_b_return is computed on.
                     # settle_arm and decided_by say WHICH ARM decided the row; settle_due is the
                     # date the window settles (blank = already settled).
                     'rule_b_window', 'rule_b_orders', 'rule_b_spend', 'rule_b_gp',
                     'rule_b_gp_corrected',
                     'rule_b_return', 'rule_b_bar', 'rule_b_verdict',
                     'rule_b_settle_arm', 'rule_b_decided_by', 'rule_b_settle_due',
                     'rule_b_dropped_row', 'rule_b_reason',
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
                f"{num(r.get('w_gp_corr'), 0):.2f}",
                (f"{(bits.get('rule_b') or {}).get('ret'):.3f}"
                 if (bits.get('rule_b') or {}).get('ret') is not None else ''),
                f"{(bits['bar'] or 1.0):.4f}",
                (bits.get('rule_b') or {}).get('verdict', ''),
                (bits.get('rule_b') or {}).get('settle_arm', ''),
                (bits.get('rule_b') or {}).get('decided_by', ''),
                (bits.get('rule_b') or {}).get('settle_due_on') or '',
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
            n_held = sum(1 for _, _, _, v in rule_b_dropped if v['verdict'] == 'HELD_UNSETTLED')
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
                    f"because a peak moves too fast to be judged on a week. "
                    + (f"Those numbers, and the order floor of {RULE_B_MIN_ORDERS}, were **read "
                       f"from the plan's settings table** (DE_PLAN_CONFIG, ruling P-13) when this "
                       f"book was built — change a setting there and the next book follows it, "
                       f"with no deploy and no edit to the generator. "
                       if PLAN_CONFIG_SOURCE == 'DE_PLAN_CONFIG' else
                       f"**WARNING — the settings table could not be read for this build.** Those "
                       f"numbers, and the order floor of {RULE_B_MIN_ORDERS}, are the generator's "
                       f"**declared fallbacks**, not DE_PLAN_CONFIG (ruling P-13). If you changed "
                       f"a setting there, THIS BOOK DOES NOT REFLECT IT — rebuild once the table "
                       f"reads. ")
                    + f"The newest ads day ({w0['watermark']}) is still filling and is deliberately "
                    f"left out: only finished days are judged.\n\n")
            n_arm = Counter((v.get('settle_arm') or '') for _, _, _, v in rule_b_dropped)
            f.write(f"### The window's sales are still arriving — and this book says so on "
                    f"every row (P-14)\n\n")
            f.write(f"Sponsored Products sales keep landing for about a week after the click and "
                    f"Sponsored Brands for about two, so a keyword judged in a {win_days}-day "
                    f"window ending {win_to} has NOT yet been credited with everything it "
                    f"earned. Left alone, that overstates the **not-good** side — it parks "
                    f"keywords for the crime of being recent. Two things are done about it, and "
                    f"the audit CSV names which one decided each row "
                    f"(`rule_b_settle_arm`, `rule_b_decided_by`, `rule_b_settle_due`):\n\n"
                    f"1. **The margin is corrected.** Each day's gross profit is divided by the "
                    f"published completion factor for its channel and its age, read from "
                    f"`V_ADS_SETTLE_CURVE` as a table — never a factor typed into this file. "
                    f"Every factor is at most 1, so the correction can only ever RAISE a "
                    f"keyword's return: it can promote, never demote. **Order counts are never "
                    f"corrected** — a count cannot be fractional, so the {RULE_B_MIN_ORDERS}-"
                    f"order floor is always read on orders actually observed. Column "
                    f"`rule_b_gp_corrected` beside `rule_b_gp` shows both.\n"
                    f"2. **Nothing is demoted before it has settled.** A keyword whose settled "
                    f"90-day record clears its family bar keeps the good side until its window "
                    f"settles ({win_to} plus 7 days for Sponsored Products, 14 for Sponsored "
                    f"Brands), even when the window reads badly. Those rows say "
                    f"`HELD_UNSETTLED` and carry the date they settle. Unmeasured never reads "
                    f"as bad.\n\n")
            f.write(f"**This is UNRULED.** Ori raised the defect on 2026-08-23 and has not "
                    f"chosen between the offered fixes; the above is the build-as-specified "
                    f"answer (spec P-14). To overrule it, one sentence — *\"judge the window as "
                    f"it reads\"* — and both halves come out. Worth knowing before you rule: "
                    f"the correction is real but it moves almost nobody across a bar, because "
                    f"the overstatement lives behind the ORDER FLOOR (keywords with one order "
                    f"or none), which the ruling's own wording forbids correcting. On this "
                    f"book the arms fired: "
                    + (", ".join(f"{k or 'n/a'} {n}" for k, n in sorted(n_arm.items())) or "none")
                    + f". Re-derive it yourself rather than trusting this sentence — the "
                    f"comparison is `rule_b_gp` against `rule_b_gp_corrected` in the audit "
                    f"CSV.\n\n")
            if rule_b_dropped:
                f.write(f"**{len(rule_b_dropped)} row(s) were dropped by rule B** — {n_good} on a "
                        f"keyword the window calls good, {n_grace} held by grace (the ladder "
                        f"calls it a settled winner and its window was merely quiet; a proven "
                        f"winner keeps the good side for one quiet window, held, never cut), "
                        f"and {n_held} held because the window has not settled yet (P-14b: a "
                        f"keyword may be promoted on fresh evidence but never demoted on it). "
                        f"The limit on grace is READ, not assumed: the plan's nightly builder "
                        f"writes FACT_PLAN_NEXT_WEEK and this book reads that history with the "
                        f"same expression V_PLAN_WINDOW_JUDGMENT uses, so a second quiet window "
                        f"in a row is refused here exactly as the plan refuses it. Until a "
                        f"partition earlier than today exists there is nothing to read and each "
                        f"grace row says so on itself.\n\n")
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
