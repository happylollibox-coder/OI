#!/usr/bin/env python3
"""Run FACT_PLAN_NEXT_WEEK_acceptance.sql, PLAN_SEAT_REQUEST_acceptance.sql and V_ENGINE_HEALTH's
plan_one_move_per_notgood on the live plan and on doctored copies of it — the negative controls of
piece-1 plan Task 5 (v27.159).

WHY THIS EXISTS
    The house rule is that every acceptance check has a negative control run on a temp copy, and
    that an empty input fails rather than passes. Task 5 (Ori's rulings R2 / R6 / R12 / R13 / R15 of
    2026-10-02 = spec P-16 / P-20 / P-25 / P-26 / P-28, audit fix #19) restated C06, C12, C14, C17,
    C19 and C23 and added T1..T5 to the plan's acceptance, restated S03 / S06 / S07 / S11 of the
    seat-request acceptance, and added two terms to V_ENGINE_HEALTH's plan_one_move_per_notgood (a
    candidate's NONE on anything but an unseated probe; an OPEN_PROBE on anything but a seated probe).
    The table cannot be doctored, so this script runs each file's OWN text with names swapped:
        `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`      -> a copy of EVERY partition (T2 reads the history),
                                                      doctored per copy
        `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`   -> one snapshot of the judgement, read ONCE
    and, for the board, the `pl` / `plb` / `c25` CTEs cut out of scripts/bigquery/views/V_ENGINE_HEALTH.sql
    (comment lines stripped) with the plan table swapped the same way; before submitting, the script
    checks that the DEPLOYED view's definition (INFORMATION_SCHEMA.VIEWS) carries that text, so the
    control is run on what the board runs. Each copy is materialized as a temp table, then each check
    runs on it as ONE statement. Nothing here restates a check: a change to an acceptance file or to
    the view's c25 is what gets tested. Doctored rows are chosen deterministically (lowest rn) in the
    latest partition (`b0`, the live plan) and the one before it (`prev0`).

THE COPIES (check: expected value on that copy; HM = plan_one_move_per_notgood's measured value,
HS = 1 when its status is RED)
    LIVE                          every check 0, HM 0, HS 0.
    NC_EMPTY                      no rows: C23 T1 T2 T3 T4 T5 1 (emptiness terms), S04 1 (its
                                  emptiness term, v27.164), HS 1 (the board reads an empty live plan
                                  RED).
    HC_T1_INCUMBENT               a continuing live seat made an incumbent with a coherent contract
                                  (the previous partition's row carries tonight's contract, seated
                                  the night before with a verdict date a settle horizon later;
                                  tonight tagged INCUMBENT with that date, and costed at its price on
                                  tonight's window, v27.164): T1 0, C23 0, T3 0, S04 0.
    NC_T1_PRICE_MOVED             that incumbent's price +$0.10 tonight: T1 1.
    NC_T1_QUESTION_MOVED          that incumbent's clicks_requested +1 tonight: T1 1.
    NC_T1_COST_KEPT_FROM_CONTRACT (v27.164, follow-up F2) that incumbent carrying its contract's cost,
                                  v27.160's rule: the contract and tonight's row both at tonight's
                                  window cost + $0.50: T1 1.
    (v27.168, follow-up G1: an incumbent's cost branch follows the KEPT question's basis, the
    previous partition's request_basis, not tonight's is_probe. These four restate v27.164's
    HC_T1_PROBE_INCUMBENT / NC_T1_PROBE_COSTED_BY_WINDOW, which held the is_probe rule.)
    HC_T1_TURNED_PROBE_KEEPS_WINDOW_COST  that incumbent (an ordinary seat) made a probe tonight and
                                  costed at its kept price on tonight's window: T1 0.
    NC_T1_TURNED_PROBE_COSTED_BY_GOAL  the same, costed click_goal_day x its kept price (v27.164's
                                  rule; the live 2026-10-03 defect): T1 1.
    HC_T1_PROBE_BASIS_INCUMBENT   that incumbent's question asked as a probe's (request_basis
                                  'HORIZON_PROBE_GOAL' on both nights; not a probe tonight), costed
                                  click_goal_day x its kept price: T1 0.
    NC_T1_BASIS_FLIPPED           the same basis flip, costed at its price on the window: T1 1.
    NC_T1_TENURE_WITHOUT_CONTRACT a NEW seat tagged INCUMBENT with no contract behind it: T1 >= 1 (the
                                  tenure term and the sentence term each count it).
    NC_C23_SEAT_DROPPED           the plan's control: the previous partition holds a seat dated
                                  tomorrow, priced $0.00 (so tonight's window costs it nothing;
                                  v27.164 — it was "costing $0.01 a day" while T1 read the contract's
                                  cost), for a keyword tonight's walk queues: C23 1, T1 1.
    HC_T1_EVICTION_JUSTIFIED      that seat's contract priced $1,000,000 and asking a probe's
                                  question (v27.168: its click goal at that price is above any
                                  allowance whatever the row spent), and tonight says
                                  LEFT_ALLOWANCE_SHRANK and TENURE ENDS EARLY: C23 0, T1 0.
    NC_T1_SHRANK_SILENT           the same without "TENURE ENDS EARLY" in the sentence: C23 0, T1 1
                                  (the sentence term alone).
    NC_T1_EVICTION_UNJUSTIFIED    the justified copy with the contract priced $0.00: C23 0, T1 1.
    (v27.167, follow-up F8: incumbents leave latest-seated first until the rest fit.) The queued row
    the eviction copies doctor is ranked after every INCUMBENT of its plan x family (families with
    kept incumbents first), so its contract, dated the night before, is the latest seated in the
    walk's order (seat date, then tonight's rank), and SHRANK_SAID's sentence carries R2's words.
    HC_T1_LATER_LEAVES_BEHIND_EARLIER  two such queued rows of one family, contracts dated the night
                                  before: the earlier priced $1,000,000 (does not fit), the later
                                  $0.00 (fits on its own); both LEFT_ALLOWANCE_SHRANK: C23 0, T1 0.
    NC_T1_EARLIER_LEFT_LATER_KEPT the justified eviction with its contract dated a day before the
                                  earliest kept incumbent of its family (seated before every kept
                                  one, as the fit test let happen): C23 0, T1 1 (the order term).
    NC_T1_SHRANK_OLD_WORDS        the justified eviction saying v27.164's fit-test sentence instead
                                  of R2's words: C23 0, T1 1 (the sentence term).
    NC_S04_NEW_SEAT_COST_OFF      (v27.164) a NEW seat's cost + $0.50 off its implied spend: S04 1,
                                  T3 1 (both now compare the two on seats taken tonight only).
    NC_C23_RENUMBERED             a continuing occupant (same number both nights; the register holds
                                  that number for no other keyword) given number 900: C23 1, T2 1.
    NC_T2_RETURN_RENUMBERED       a seated keyword absent the night before whose most recent seat
                                  number is honoured tonight, given number 901: T2 1.
    HC_C17_PLAN_A                 a plan-A seat given a number the register holds open for another
                                  keyword: C17 0 (the register is the live plan's).
    NC_C17_PLAN_B                 the same on the live plan: C17 >= 1 (2 when the keyword has its own
                                  register row).
    NC_T3_CLICKS_DOUBLED          the plan's control: one seat's clicks_requested doubled: T3 1, S03 1.
    NC_T4_PROBE_PARKED            an unseated, unserved probe given PARK at $0.20 and the v27.158
                                  sentence ("keeps buying clicks"): T4 1, C14 1.
    NC_T4_NONE_SILENT             an unseated probe's sentence without "PROBE NOT OPENED TONIGHT;
                                  NOTHING UPLOADED": T4 1.
    NC_T4_NONE_PRICED             an unseated probe's NONE carrying a $0.20 bid: T4 1.
    NC_T4_OPEN_PROBE_SILENT       a seated probe's sentence without "OPEN PROBE at $": T4 1.
    NC_C14_PROBE_REPRICED         a seated probe's move REPRICE: C14 1.
    NC_C12_OPEN_PROBE_ABOVE_CEILING  a seated probe's planned bid $0.10 above GREATEST(current bid,
                                  $2.00): C12 1.
    NC_S07_PROBE_GOAL_NOT_MULTIPLE  a seated probe (HORIZON_PROBE_GOAL) asking one click more than a
                                  whole number of days, its CPC restated so clicks x CPC / horizon is
                                  still its implied spend: S07 1, T3 1 (the MOD term alone), S03 0.
    NC_C06_NONE_ON_SEAT           a seated non-probe's move NONE: C06 >= 1, C19 1 (NONE is a queue
                                  move), HM 1 (the board's NONE term).
    NC_H_OPEN_PROBE_ON_SEAT       a seated non-probe's move OPEN_PROBE: C14 1, HM 1 (the board's
                                  OPEN_PROBE term).
    NC_C14_PROBE_FLAG_NULL        a seated candidate's is_probe NULL: C14 1.
    NC_S11_BOGUS_BASIS            a seat's request_basis 'BOGUS': S11 1, T3 1.
    NC_T5_RANK_SWAPPED            the ranks 1 and 2 of one family swapped: T5 2.
    NC_S06_HORIZON                one NEW ordinary seat asking for w_clk (v27.158's question) under
                                  the HORIZON_WINDOW_RATE basis: S06 1, T3 1.
    A copy's other checks are printed and not asserted: doctoring one row can trip another check.
    NOT EXERCISED: a copy whose doctored row does not exist on the partition (its pick column is
    NULL — no seated probe tonight, no returning seat, no register number outside tonight's seats ...)
    tests nothing. It is reported as NOT EXERCISED and the script exits 1: a control that did not
    run is not a pass.

EXIT CODES
    0  LIVE read 0 on every check, every copy was exercised, and every copy read its expected value
    1  a copy did not, or a copy was not exercised, or the deployed V_ENGINE_HEALTH does not carry
       the c25 text this script runs (each is printed)
    2  the check could not run (bq failed, or a file did not parse)

USAGE (one BigQuery script job: 121 statements, 8 min 34 s and 5,789.9 slot-seconds on 2026-10-03,
job bqjob_r4ed37cefafebd407_000001a0ff7ee55d_1; with the five v27.164 copies, 32 copies, 8,715.2
slot-seconds on 2026-10-03 09:00–09:09 UTC, job bqjob_r78febaf76288764f_000001a100fdebd9_1; with the
three v27.167 copies, 35 copies, 10,719.1 slot-seconds on 2026-10-03 11:13–11:22 UTC, job
bqjob_r7aa7d0f7442a1a18_000001a10177bacd_1; with the four v27.168 copies (two of them restating
v27.164's probe pair), 37 copies, 13,018.2 slot-seconds on 2026-10-03 13:06–13:17 UTC, job
bqjob_r600d3131e7ab6071_000001a101dfb192_1, judgement snapshot OI._tmp_g1_judge2, doctored incumbent
plan B LolliME 123153583900193; all exit 0. The four v27.168 copies under the v27.167 acceptance form
read T1 1, 0, 1, 0 beyond that form's live reading of 1 (job bqjob_r69ce5b20553e581e_000001a101dfd8d0_1,
2,217.9 slot-seconds). It is submitted asynchronously and polled.)
    python3 scripts/bigquery/tests/check_plan_seat_controls.py [--judge-table PROJECT.DATASET.TABLE]
        submit, poll with `bq wait JOB 60` (printing the state each minute), collect.
    python3 scripts/bigquery/tests/check_plan_seat_controls.py --submit [--judge-table ...]
        submit only; prints JOB=<id>.
    python3 scripts/bigquery/tests/check_plan_seat_controls.py --collect JOB
        poll until DONE, then read the job's last statement (`SELECT * FROM res`) with `bq head -j`.
    --judge-table reads a snapshot of the judgement instead of the deployed view. Since v27.171 the
    plan acceptance reads it only for T1's click goal (a constant the view declares) and this
    script's PROBE_COST; C13 reads the judgement each night was BUILT ON, which
    SP_BUILD_NEXT_WEEK_PLAN v27.171 saves with the night:
        `onyga-482313.OI.T_PLAN_BUILD_JUDGMENT`    -> bjsnap (with --build-judge-table PROJECT.DATASET.TABLE,
                                                      a copy of it), read ONCE
    LIVE (every check 0) holds on the real table at any hour once a night has been written by v27.171.
    Until then LIVE reads C13 1 (the latest night's judgement is not on record), F1 1 and F2 1
    (emptiness) and the script exits 1 whatever the copies read. Before v27.171, C13 read the live
    view, whose fence moves at Los Angeles midnight while a frozen night (v27.170) stays: from the
    first frozen night on, LIVE would have read C13 non-zero outside the hours between a night's write
    and Los Angeles midnight. Run on the real table 2026-10-03 18:47-18:59 UTC after the v27.171
    deploy (job bqjob_r28ce46c4ceeae428_000001a10317178d_1, 8,986.4 slot-seconds): exit 1 by LIVE
    alone — 52 readings, non-zero exactly C13 1, F1 1, F2 1 (the 10-03 night was written by v27.169)
    — and every copy read its expected value (64 assertions, none NOT EXERCISED).
"""
import json
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
ACC_PLAN = os.path.join(ROOT, "scripts", "bigquery", "tests", "FACT_PLAN_NEXT_WEEK_acceptance.sql")
ACC_REQ = os.path.join(ROOT, "scripts", "bigquery", "tests", "PLAN_SEAT_REQUEST_acceptance.sql")
HEALTH = os.path.join(ROOT, "scripts", "bigquery", "views", "V_ENGINE_HEALTH.sql")
VIEW = "`onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`"
PLAN = "`onyga-482313.OI.FACT_PLAN_NEXT_WEEK`"
# v27.171 (learning piece 2 Task 3 follow-up 2): C13 reads the judgement each night was built on
BUILD_J = "`onyga-482313.OI.T_PLAN_BUILD_JUDGMENT`"
BQ = ["bq", "--project_id=onyga-482313"]


def stripped(path):
    return "\n".join(l for l in open(path).read().split("\n") if not re.match(r"^\s*--", l))


def acceptance_query(path, needs_view):
    q = stripped(path).strip().rstrip(";")
    if PLAN not in q or (needs_view and (VIEW not in q or BUILD_J not in q)):
        raise ValueError(f"{os.path.basename(path)} no longer reads the plan table (and the view and the "
                         "saved judgement) by name")
    return q.replace(VIEW, "jsnap").replace(PLAN, "__HH__").replace(BUILD_J, "bjsnap")


def health_ctes():
    """the view's own `pl`, `plb` and `c25` CTEs (comment lines stripped), and the text to look for
    in the deployed definition"""
    text = stripped(HEALTH)
    m_pl = re.search(r"^pl AS \(.*?^plb AS \(SELECT \* FROM pl WHERE is_live_plan\),", text, re.S | re.M)
    m_c25 = re.search(r"^c25 AS \(.*?(?=^c26 AS \()", text, re.S | re.M)
    if not m_pl or not m_c25 or "'plan_one_move_per_notgood'" not in m_c25.group(0) or PLAN not in m_pl.group(0):
        raise ValueError("V_ENGINE_HEALTH.sql: the pl / plb / c25 (plan_one_move_per_notgood) CTEs were not found")
    pl = m_pl.group(0).rstrip().rstrip(",")
    c25 = m_c25.group(0).rstrip().rstrip(",")
    return pl, c25


def norm(s):
    return re.sub(r"\s+", " ", s).strip()


LIVE = "SELECT * EXCEPT (rn) FROM hbase"


def rows(cond, **repl):
    """the rows matching cond (SQL over hbase columns and the pick table), doctored"""
    sets = ", ".join(f"IF({cond}, {v}, {k}) AS {k}" for k, v in repl.items())
    return f"SELECT * EXCEPT (rn) REPLACE ({sets}) FROM hbase"


def at(col, **repl):
    return rows(f"rn = (SELECT {col} FROM pick)", **repl)


def two(col_tonight, col_prev, tonight, prev):
    """doctor one row tonight and one row in the previous partition (both by rn), in one copy"""
    return many([(col_prev, prev), (col_tonight, tonight)])


def many(pairs):
    """doctor several rows (each picked by rn from a pick column), in one copy: [(pick column,
    {column: expression}), ...]"""
    sets = []
    keys = set().union(*[set(d) for _, d in pairs])
    for k in sorted(keys):
        e = k
        for col, d in pairs:
            if k in d:
                e = f"IF(rn = (SELECT {col} FROM pick), {d[k]}, {e})"
        sets.append(f"{e} AS {k}")
    return f"SELECT * EXCEPT (rn) REPLACE ({', '.join(sets)}) FROM hbase"


# the contract a previous-partition row must carry for the doctored incumbent: tonight's own, seated
# the night before (prev as_of) with a verdict date one settle horizon after that
def contract_from_tonight(src_rn_col):
    t = f"(SELECT AS STRUCT * FROM hbase WHERE rn = (SELECT {src_rn_col} FROM pick))"
    return {
        "seat_no": f"{t}.seat_no", "planned_bid": f"{t}.planned_bid",
        "seat_cost_per_day": f"{t}.seat_cost_per_day",
        "seat_since": "(SELECT prev_as_of FROM pick)",
        "verdict_date": f"DATE_ADD((SELECT prev_as_of FROM pick), INTERVAL DATE_DIFF({t}.verdict_date, {t}.seat_since, DAY) DAY)",
        "clicks_requested": f"{t}.clicks_requested",
        "clicks_due_date": f"DATE_ADD((SELECT prev_as_of FROM pick), INTERVAL DATE_DIFF({t}.verdict_date, {t}.seat_since, DAY) DAY)",
        "expected_cpc": f"{t}.expected_cpc", "implied_daily_spend": f"{t}.implied_daily_spend",
        "request_basis": f"{t}.request_basis",
    }


# v27.164 (follow-up F2): an incumbent's cost is its kept price on TONIGHT's window, as the builder
# and T1 recount it: w_sp / window_days x price / current bid (0 with no spend or no current bid),
# and click_goal_day x price on a probe (the goal read from the judgement snapshot). The doctored
# incumbent keeps tonight's planned_bid, which contract_from_tonight writes into the previous
# partition, so its coherent cost is this recount on tonight's own price.
WINDOW_COST = ("ROUND(IF(w_sp > 0 AND COALESCE(current_bid, 0) > 0, "
               "w_sp / window_days * planned_bid / current_bid, 0), 4)")
PROBE_COST = "ROUND((SELECT MAX(click_goal_day) FROM jsnap) * planned_bid, 4)"
# v27.168 (follow-up G1): the branch follows the KEPT question's basis, not tonight's is_probe. The
# doctored incumbent's contract carries tonight's request_basis (contract_from_tonight), so its
# coherent cost is the goal on a 'HORIZON_PROBE_GOAL' question and the window on any other.
BASIS_COST = f"IF(request_basis = 'HORIZON_PROBE_GOAL', {PROBE_COST}, {WINDOW_COST})"
PROBE_BASIS = "'HORIZON_PROBE_GOAL'"


def incumbent_tonight(extra=None):
    d = {
        "seat_tenure": "'INCUMBENT'",
        "seat_since": "(SELECT prev_as_of FROM pick)",
        "verdict_date": "DATE_ADD((SELECT prev_as_of FROM pick), INTERVAL DATE_DIFF(verdict_date, seat_since, DAY) DAY)",
        "clicks_due_date": "DATE_ADD((SELECT prev_as_of FROM pick), INTERVAL DATE_DIFF(verdict_date, seat_since, DAY) DAY)",
        "sentence": "REPLACE(sentence, 'TENURE: seated tonight', 'TENURE: it has held this seat since')",
        "seat_cost_per_day": BASIS_COST,
    }
    d.update(extra or {})
    return d


# the v27.160 rule F2 retired: the incumbent carries the cost its contract was granted at, here
# tonight's window cost + $0.50 written both into the contract and onto tonight's row
STALE_COST = f"{WINDOW_COST} + 0.50"

DROP_PREV = {  # a seat dated tomorrow in the previous partition, for a keyword tonight queues; its
    # kept price $0.00, so tonight's window costs it nothing and nothing justifies its eviction
    "seat_no": "999", "planned_bid": "0.0", "seat_cost_per_day": "0.01",
    "seat_since": "(SELECT prev_as_of FROM pick)",
    "verdict_date": "DATE_ADD((SELECT mx FROM pick), INTERVAL 1 DAY)",
    "clicks_requested": "7", "clicks_due_date": "DATE_ADD((SELECT mx FROM pick), INTERVAL 1 DAY)",
    "expected_cpc": "0.01", "implied_daily_spend": "0.01", "request_basis": "'HORIZON_WINDOW_RATE'",
}
# v27.167 (F8): a LEFT_ALLOWANCE_SHRANK row says R2's rule in R2's words
SHRANK_SAID = {"seat_tenure": "'LEFT_ALLOWANCE_SHRANK'",
               "sentence": "CONCAT(sentence, ' TENURE ENDS EARLY: doctored, so incumbents leave latest-seated first until the rest fit (P-16).')"}
SHRANK_SILENT = {"seat_tenure": "'LEFT_ALLOWANCE_SHRANK'",
                 "sentence": "REPLACE(sentence, 'TENURE ENDS EARLY', 'tenure ends early')"}
# v27.164's words, which named the fit test
SHRANK_OLD_WORDS = {"seat_tenure": "'LEFT_ALLOWANCE_SHRANK'",
                    "sentence": "CONCAT(sentence, ' TENURE ENDS EARLY: doctored; incumbents keep their seats in the order they took them, and this one no longer fits behind those seated before it (P-16).')"}
INC = ["inc_rn", "inc_prev_rn", "prev_as_of"]
QUEUED = ["queued_rn", "queued_prev_rn", "prev_as_of", "mx"]
# v27.167 (F8): a second queued row of the same plan x family, ranked after the first; and the
# earliest seat date of that family's kept incumbents
QUEUED2 = QUEUED + ["queued2_rn", "queued2_prev_rn"]
EARLIER = QUEUED + ["queued_fam_inc_since"]
# costs more than any allowance at that price. v27.168 (G1): it asks a probe's question, so T1 costs
# it click_goal_day x $1,000,000 whatever the queued row spent (on a window question an unserved
# probe's $0.00 window would cost it nothing)
DEAR = dict(DROP_PREV, planned_bid="1000000.0", request_basis=PROBE_BASIS)
CHEAP2 = dict(DROP_PREV, seat_no="998")              # $0.00: fits any room on its own
EARLIER_DEAR = dict(DEAR, seat_since="DATE_SUB((SELECT queued_fam_inc_since FROM pick), INTERVAL 1 DAY)")
HORIZON = "DATE_DIFF(clicks_due_date, seat_since, DAY)"

# name -> (copy SQL, [(check, expected)], pick columns the copy needs: NULL = NOT EXERCISED)
COPIES = {
    "LIVE": (LIVE, None, []),
    "NC_EMPTY": (f"{LIVE} WHERE FALSE",
                 [("C23", 1), ("T1", 1), ("T2", 1), ("T3", 1), ("T4", 1), ("T5", 1), ("S04", 1), ("HS", 1)], []),
    "HC_T1_INCUMBENT": (two("inc_rn", "inc_prev_rn", incumbent_tonight(), contract_from_tonight("inc_rn")),
                        [("T1", 0), ("C23", 0), ("T3", 0), ("S04", 0)], INC),
    "NC_T1_PRICE_MOVED": (two("inc_rn", "inc_prev_rn", incumbent_tonight({"planned_bid": "planned_bid + 0.10"}),
                              contract_from_tonight("inc_rn")), [("T1", 1)], INC),
    "NC_T1_QUESTION_MOVED": (two("inc_rn", "inc_prev_rn", incumbent_tonight({"clicks_requested": "clicks_requested + 1"}),
                                 contract_from_tonight("inc_rn")), [("T1", 1)], INC),
    # v27.164 (F2): the incumbent costed by its contract, v27.160's rule
    "NC_T1_COST_KEPT_FROM_CONTRACT": (two("inc_rn", "inc_prev_rn", incumbent_tonight({"seat_cost_per_day": STALE_COST}),
                                          dict(contract_from_tonight("inc_rn"), seat_cost_per_day=STALE_COST)),
                                      [("T1", 1)], INC),
    # v27.168 (G1, restating v27.164's two probe copies): the cost follows the KEPT question's basis.
    # The incumbent (an ordinary seat, its question HORIZON_WINDOW_RATE) made a probe tonight keeps
    # its window cost; F2's click_goal_day x price on it is the defect G1 retires (plan B Fresh
    # 388620934464557 on 2026-10-03)
    "HC_T1_TURNED_PROBE_KEEPS_WINDOW_COST": (two("inc_rn", "inc_prev_rn",
                                                 incumbent_tonight({"is_probe": "TRUE", "seat_cost_per_day": WINDOW_COST}),
                                                 contract_from_tonight("inc_rn")), [("T1", 0)], INC),
    "NC_T1_TURNED_PROBE_COSTED_BY_GOAL": (two("inc_rn", "inc_prev_rn",
                                              incumbent_tonight({"is_probe": "TRUE", "seat_cost_per_day": PROBE_COST}),
                                              contract_from_tonight("inc_rn")), [("T1", 1)], INC),
    # a contract asked as a probe (HORIZON_PROBE_GOAL on both nights) costs the goal, probe tonight or
    # not; the same incumbent with its basis flipped to the probe's but costed by its window reads 1
    "HC_T1_PROBE_BASIS_INCUMBENT": (two("inc_rn", "inc_prev_rn",
                                        incumbent_tonight({"request_basis": PROBE_BASIS, "seat_cost_per_day": PROBE_COST}),
                                        dict(contract_from_tonight("inc_rn"), request_basis=PROBE_BASIS)),
                                    [("T1", 0)], INC),
    "NC_T1_BASIS_FLIPPED": (two("inc_rn", "inc_prev_rn",
                                incumbent_tonight({"request_basis": PROBE_BASIS, "seat_cost_per_day": WINDOW_COST}),
                                dict(contract_from_tonight("inc_rn"), request_basis=PROBE_BASIS)),
                            [("T1", 1)], INC),
    "NC_T1_TENURE_WITHOUT_CONTRACT": (at("new_rn", seat_tenure="'INCUMBENT'"), [("T1", "GE1")], ["new_rn"]),
    "NC_C23_SEAT_DROPPED": (two("queued_rn", "queued_prev_rn", {}, DROP_PREV), [("C23", 1), ("T1", 1)], QUEUED),
    # v27.164 (F2): the eviction test reads the contract's kept price on tonight's window, so the
    # justified copy prices the contract at $1,000,000 (any spend or probe goal costs more than any
    # allowance at it) and the unjustified one at $0.00
    "HC_T1_EVICTION_JUSTIFIED": (two("queued_rn", "queued_prev_rn", SHRANK_SAID, DEAR),
                                 [("C23", 0), ("T1", 0)], QUEUED),
    "NC_T1_SHRANK_SILENT": (two("queued_rn", "queued_prev_rn", SHRANK_SILENT, DEAR),
                            [("C23", 0), ("T1", 1)], QUEUED),
    "NC_T1_EVICTION_UNJUSTIFIED": (two("queued_rn", "queued_prev_rn", SHRANK_SAID, DROP_PREV),
                                   [("C23", 0), ("T1", 1)], QUEUED),
    # v27.167 (F8): incumbents leave latest-seated first until the rest fit. Two contracts dated the
    # night before for two queued rows ranked after every kept incumbent of their family: the
    # earlier ($1,000,000) does not fit, so the later ($0.00, which would fit on its own) leaves too
    "HC_T1_LATER_LEAVES_BEHIND_EARLIER": (many([("queued_prev_rn", DEAR), ("queued2_prev_rn", CHEAP2),
                                                ("queued_rn", SHRANK_SAID), ("queued2_rn", SHRANK_SAID)]),
                                          [("C23", 0), ("T1", 0)], QUEUED2),
    # the fit test's outcome F8 retires: an incumbent seated before every kept one of its family
    # ($1,000,000, so the v27.164 test passed it) leaves while the later ones keep their seats
    "NC_T1_EARLIER_LEFT_LATER_KEPT": (two("queued_rn", "queued_prev_rn", SHRANK_SAID, EARLIER_DEAR),
                                      [("C23", 0), ("T1", 1)], EARLIER),
    # a justified eviction whose sentence names v27.164's fit test instead of R2's rule
    "NC_T1_SHRANK_OLD_WORDS": (two("queued_rn", "queued_prev_rn", SHRANK_OLD_WORDS, DEAR),
                               [("C23", 0), ("T1", 1)], QUEUED),
    # v27.164 (F2): S04 and T3 hold implied spend = seat cost on a seat taken tonight
    "NC_S04_NEW_SEAT_COST_OFF": (at("new_rn", seat_cost_per_day="seat_cost_per_day + 0.50"),
                                 [("S04", 1), ("T3", 1)], ["new_rn"]),
    "NC_C23_RENUMBERED": (at("cont_rn", seat_no="900"), [("C23", 1), ("T2", 1)], ["cont_rn"]),
    "NC_T2_RETURN_RENUMBERED": (at("ret_rn", seat_no="901"), [("T2", 1)], ["ret_rn"]),
    "HC_C17_PLAN_A": (at("a_rn", seat_no="(SELECT reg_no FROM pick)"), [("C17", 0)], ["a_rn", "reg_no"]),
    "NC_C17_PLAN_B": (at("b_rn", seat_no="(SELECT reg_no FROM pick)"), [("C17", "GE1")], ["b_rn", "reg_no"]),
    "NC_T3_CLICKS_DOUBLED": (at("seat_rn", clicks_requested="clicks_requested * 2"), [("T3", 1), ("S03", 1)],
                             ["seat_rn"]),
    "NC_T4_PROBE_PARKED": (at("probe_none_rn", move="'PARK'", planned_bid="0.20",
                              sentence="REPLACE(sentence, 'PROBE NOT OPENED TONIGHT; NOTHING UPLOADED', 'park the bid; it keeps buying clicks at the park price')"),
                           [("T4", 1), ("C14", 1)], ["probe_none_rn"]),
    "NC_T4_NONE_SILENT": (at("probe_none_rn",
                             sentence="REPLACE(sentence, 'PROBE NOT OPENED TONIGHT; NOTHING UPLOADED', 'probe not opened tonight')"),
                          [("T4", 1)], ["probe_none_rn"]),
    "NC_T4_NONE_PRICED": (at("probe_none_rn", planned_bid="0.20"), [("T4", 1)], ["probe_none_rn"]),
    "NC_T4_OPEN_PROBE_SILENT": (at("probe_open_rn", sentence="REPLACE(sentence, 'OPEN PROBE at $', 'OPEN at $')"),
                                [("T4", 1)], ["probe_open_rn"]),
    "NC_C14_PROBE_REPRICED": (at("probe_open_rn", move="'REPRICE'"), [("C14", 1)], ["probe_open_rn"]),
    "NC_C12_OPEN_PROBE_ABOVE_CEILING": (at("probe_open_rn",
                                           planned_bid="GREATEST(COALESCE(current_bid, 0), 2.00) + 0.10"),
                                        [("C12", 1)], ["probe_open_rn"]),
    "NC_S07_PROBE_GOAL_NOT_MULTIPLE": (at("probe_open_rn", clicks_requested="clicks_requested + 1",
                                          expected_cpc=f"implied_daily_spend * {HORIZON} / (clicks_requested + 1)"),
                                       [("S07", 1), ("T3", 1), ("S03", 0)], ["probe_open_rn"]),
    "NC_C06_NONE_ON_SEAT": (at("seat_rn", move="'NONE'"), [("C06", "GE1"), ("C19", 1), ("HM", 1)], ["seat_rn"]),
    "NC_H_OPEN_PROBE_ON_SEAT": (at("seat_rn", move="'OPEN_PROBE'"), [("C14", 1), ("HM", 1)], ["seat_rn"]),
    "NC_C14_PROBE_FLAG_NULL": (at("seat_rn", is_probe="CAST(NULL AS BOOL)"), [("C14", 1)], ["seat_rn"]),
    "NC_S11_BOGUS_BASIS": (at("seat_rn", request_basis="'BOGUS'"), [("S11", 1), ("T3", 1)], ["seat_rn"]),
    "NC_T5_RANK_SWAPPED": (rows("rn IN ((SELECT r1_rn FROM pick), (SELECT r2_rn FROM pick))",
                                rank_no="IF(rank_no = 1, 2, 1)"), [("T5", 2)], ["r1_rn", "r2_rn"]),
    "NC_S06_HORIZON": (at("ord_rn", clicks_requested="CAST(w_clk AS INT64)"), [("S06", 1), ("T3", 1)], ["ord_rn"]),
}

PICK = """CREATE TEMP TABLE pick AS
WITH b0 AS (SELECT * FROM hbase WHERE as_of = (SELECT MAX(as_of) FROM hbase) AND is_live_plan),
a0 AS (SELECT * FROM hbase WHERE as_of = (SELECT MAX(as_of) FROM hbase) AND NOT is_live_plan),
prev0 AS (SELECT * FROM hbase WHERE as_of = (SELECT MAX(as_of) FROM hbase WHERE as_of < (SELECT MAX(as_of) FROM hbase))),
led AS (SELECT family, CAST(campaign_id AS STRING) campaign_id, CAST(keyword_id AS STRING) keyword_id, MIN(seat_no) seat_no
        FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` WHERE closed_on IS NULL GROUP BY 1, 2, 3),
cl AS (SELECT plan, family, campaign_id, keyword_id, seat_no AS claim_no, as_of AS claim_as_of
       FROM hbase WHERE as_of < (SELECT MAX(as_of) FROM hbase) AND seat_no IS NOT NULL
       QUALIFY ROW_NUMBER() OVER (PARTITION BY plan, family, campaign_id, keyword_id ORDER BY as_of DESC) = 1),
-- a continuing live occupant: seated both nights at the same number, not a probe (NEW until the
-- builder writes contracts, INCUMBENT after)
cont AS (SELECT t.rn, y.rn AS prev_rn FROM b0 t JOIN prev0 y USING (plan, family, campaign_id, keyword_id)
         WHERE t.seat_no IS NOT NULL AND y.seat_no = t.seat_no AND NOT COALESCE(t.is_probe, FALSE)
           AND t.seat_tenure IN ('NEW', 'INCUMBENT')),
-- a live candidate tonight's walk queued (not an incumbent that left), present the night before.
-- v27.167 (F8): ranked after every INCUMBENT of its plan x family, so a contract doctored onto it
-- dated the night before (the latest an incumbent can be seated) is the latest seated of them in
-- the walk's order (seat date, then tonight's rank); families with kept incumbents first
incfam AS (SELECT plan, family, MAX(rank_no) AS max_inc_rank, MIN(seat_since) AS min_inc_since
           FROM b0 WHERE seat_tenure = 'INCUMBENT' GROUP BY 1, 2),
queued AS (SELECT t.rn, y.rn AS prev_rn, t.plan, t.family, t.rank_no, m.min_inc_since,
                  ROW_NUMBER() OVER (ORDER BY m.max_inc_rank IS NULL, t.rn) AS qix
           FROM b0 t JOIN prev0 y USING (plan, family, campaign_id, keyword_id)
           LEFT JOIN incfam m USING (plan, family)
           WHERE t.is_candidate AND t.seat_no IS NULL AND COALESCE(t.ladder_state, '') != 'DEAD'
             AND COALESCE(t.seat_tenure, '') != 'LEFT_ALLOWANCE_SHRANK'
             AND t.rank_no > COALESCE(m.max_inc_rank, 0)),
-- a continuing occupant (either plan) whose number the register holds for no OTHER keyword
contnoreg AS (SELECT t.rn FROM hbase t JOIN prev0 y USING (plan, family, campaign_id, keyword_id)
              WHERE t.as_of = (SELECT MAX(as_of) FROM hbase) AND t.seat_no IS NOT NULL AND y.seat_no = t.seat_no
                AND NOT EXISTS (SELECT 1 FROM led l WHERE l.family = t.family AND l.seat_no = t.seat_no
                                                      AND l.keyword_id != t.keyword_id)),
-- a returning seat: seated tonight, not the night before, its most recent claim honoured tonight
ret AS (SELECT t.rn FROM hbase t
        JOIN cl c ON c.plan = t.plan AND c.family = t.family AND c.campaign_id = t.campaign_id AND c.keyword_id = t.keyword_id
        LEFT JOIN prev0 y ON y.plan = t.plan AND y.campaign_id = t.campaign_id AND y.keyword_id = t.keyword_id
        LEFT JOIN led l ON l.family = t.family AND l.campaign_id = t.campaign_id AND l.keyword_id = t.keyword_id
        WHERE t.as_of = (SELECT MAX(as_of) FROM hbase) AND t.seat_no IS NOT NULL AND y.seat_no IS NULL
          AND c.claim_no = t.seat_no AND (NOT t.is_live_plan OR l.keyword_id IS NULL)),
fam1 AS (SELECT MIN(family) f FROM b0 WHERE is_candidate AND rank_no = 2)
SELECT
  (SELECT MAX(as_of) FROM hbase) AS mx,
  (SELECT MAX(as_of) FROM hbase WHERE as_of < (SELECT MAX(as_of) FROM hbase)) AS prev_as_of,
  (SELECT MIN(rn) FROM cont) AS inc_rn,
  (SELECT prev_rn FROM cont WHERE rn = (SELECT MIN(rn) FROM cont)) AS inc_prev_rn,
  (SELECT MIN(rn) FROM b0 WHERE seat_no IS NOT NULL AND NOT COALESCE(is_probe, FALSE)) AS seat_rn,
  (SELECT MIN(rn) FROM b0 WHERE seat_tenure = 'NEW' AND NOT COALESCE(is_probe, FALSE)) AS new_rn,
  (SELECT rn FROM queued WHERE qix = 1) AS queued_rn,
  (SELECT prev_rn FROM queued WHERE qix = 1) AS queued_prev_rn,
  (SELECT min_inc_since FROM queued WHERE qix = 1) AS queued_fam_inc_since,
  (SELECT q2.rn FROM queued q2 JOIN queued q1 ON q1.qix = 1 AND q2.plan = q1.plan AND q2.family = q1.family
   WHERE q2.rank_no > q1.rank_no ORDER BY q2.rank_no LIMIT 1) AS queued2_rn,
  (SELECT q2.prev_rn FROM queued q2 JOIN queued q1 ON q1.qix = 1 AND q2.plan = q1.plan AND q2.family = q1.family
   WHERE q2.rank_no > q1.rank_no ORDER BY q2.rank_no LIMIT 1) AS queued2_prev_rn,
  (SELECT MIN(rn) FROM contnoreg) AS cont_rn,
  (SELECT MIN(rn) FROM ret) AS ret_rn,
  (SELECT MIN(l.seat_no) FROM led l WHERE l.family = (SELECT family FROM a0 WHERE seat_no IS NOT NULL ORDER BY rn LIMIT 1)
     AND l.seat_no NOT IN (SELECT seat_no FROM a0 WHERE seat_no IS NOT NULL AND family = l.family)
     AND l.seat_no NOT IN (SELECT seat_no FROM b0 WHERE seat_no IS NOT NULL AND family = l.family)) AS reg_no,
  (SELECT rn FROM a0 WHERE seat_no IS NOT NULL ORDER BY rn LIMIT 1) AS a_rn,
  (SELECT MIN(rn) FROM b0 WHERE seat_no IS NOT NULL
     AND family = (SELECT family FROM a0 WHERE seat_no IS NOT NULL ORDER BY rn LIMIT 1)) AS b_rn,
  (SELECT MIN(rn) FROM b0 WHERE is_candidate AND move = 'NONE' AND NOT COALESCE(served, FALSE)) AS probe_none_rn,
  (SELECT MIN(rn) FROM b0 WHERE move = 'OPEN_PROBE') AS probe_open_rn,
  (SELECT rn FROM b0 WHERE is_candidate AND rank_no = 1 AND family = (SELECT f FROM fam1)) AS r1_rn,
  (SELECT rn FROM b0 WHERE is_candidate AND rank_no = 2 AND family = (SELECT f FROM fam1)) AS r2_rn,
  (SELECT MIN(rn) FROM b0 WHERE seat_tenure = 'NEW' AND request_basis = 'HORIZON_WINDOW_RATE'
     AND clicks_requested != w_clk) AS ord_rn;
"""


def raw(s):
    if '"""' in s or s.endswith('"'):
        raise ValueError("a check text cannot be held in a raw triple-quoted string")
    return 'r"""' + s + '"""'


def build_script(judge_source, build_judge_source=BUILD_J):
    acc_plan = acceptance_query(ACC_PLAN, True)
    acc_req = acceptance_query(ACC_REQ, False)
    pl, c25 = health_ctes()
    # V_ENGINE_HEALTH c25 as the view has it; its five columns are unnamed, so a typed empty branch
    # names them
    acc_health = (f"WITH {pl.replace(PLAN, '__HH__')},\n{c25},\n"
                  "b AS (SELECT '' AS n, 0.0 AS measured, '' AS threshold, '' AS status, '' AS detail\n"
                  "      FROM UNNEST([1]) WHERE FALSE UNION ALL SELECT * FROM c25)\n"
                  "SELECT 'HM plan_one_move_per_notgood measured (V_ENGINE_HEALTH c25)' AS check_name,\n"
                  "       CAST(measured AS INT64) AS violations, status AS detail FROM b\n"
                  "UNION ALL\n"
                  "SELECT 'HS plan_one_move_per_notgood status is RED (V_ENGINE_HEALTH c25)',\n"
                  "       IF(status = 'RED', 1, 0), detail FROM b")
    # each check text is held ONCE and run per copy by EXECUTE IMMEDIATE with the copy's name swapped
    # in: inlined per copy, the 28 copies made a 1,023,272-byte script (measured 2026-10-03), at
    # BigQuery's 1 MB limit on a query's text and over what `getconf ARG_MAX` (1,048,576 bytes on
    # this Mac, environment included) leaves for one argument
    parts = [
        f"DECLARE acc_plan STRING DEFAULT {raw(acc_plan)};",
        f"DECLARE acc_req STRING DEFAULT {raw(acc_req)};",
        f"DECLARE acc_health STRING DEFAULT {raw(acc_health)};",
        f"CREATE TEMP TABLE jsnap AS SELECT * FROM {judge_source};",
        f"CREATE TEMP TABLE bjsnap AS SELECT * FROM {build_judge_source};",
        "CREATE TEMP TABLE hbase AS SELECT *, ROW_NUMBER() OVER (ORDER BY as_of, plan, campaign_id, keyword_id) AS rn "
        f"FROM {PLAN};",
        PICK,
        # every result lands here and the script's LAST statement reads it, so the job's own result
        # (bq head -j) is the whole run
        "CREATE TEMP TABLE res (copy STRING, check_name STRING, violations INT64, detail STRING);",
        "INSERT INTO res SELECT 'PICK', 'PICK', 0, TO_JSON_STRING(p) FROM pick p;",
    ]
    for i, (name, (hsql, _, _)) in enumerate(COPIES.items()):
        # each copy is MATERIALIZED first: the acceptance reads the plan table at several places, and
        # an inline doctored subquery at each of them exceeded BigQuery's planning limit (first run,
        # 2026-10-02: "query is too complex")
        hh = f"hh{i}"
        parts.append(f"CREATE TEMP TABLE {hh} AS {hsql};")
        for var, col in (("acc_plan", "violations"), ("acc_req", "v")):
            parts.append("EXECUTE IMMEDIATE FORMAT(\"INSERT INTO res SELECT '%s', check_name, " + col
                         + f", NULL FROM (%s)\", '{name}', REPLACE({var}, '__HH__', '{hh}'));")
        parts.append("EXECUTE IMMEDIATE FORMAT(\"INSERT INTO res SELECT '%s', check_name, violations, detail "
                     f"FROM (%s)\", '{name}', REPLACE(acc_health, '__HH__', '{hh}'));")
    parts.append("SELECT copy, check_name, violations, detail FROM res ORDER BY copy, check_name;")
    return "\n".join(parts)


def run(args, timeout=None):
    return subprocess.run(BQ + args, capture_output=True, text=True, timeout=timeout)


def view_tie():
    """0 when the deployed V_ENGINE_HEALTH carries this file's pl / plb / c25 text, else 1"""
    pl, c25 = health_ctes()
    r = run(["--format=json", "query", "--use_legacy_sql=false", "--nouse_cache",
             "SELECT view_definition FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS` "
             "WHERE table_name = 'V_ENGINE_HEALTH'"])
    if r.returncode != 0:
        print(r.stdout[-2000:], r.stderr[-2000:])
        return 2
    rows_ = json.loads(r.stdout)
    deployed = norm(rows_[0]["view_definition"]) if rows_ else ""
    missing = [n for n, t in (("pl/plb", pl), ("c25", c25)) if norm(t) not in deployed]
    if missing:
        print("the deployed V_ENGINE_HEALTH does not carry this file's", missing, "text: run it on the deployed body")
        return 1
    print("the deployed V_ENGINE_HEALTH carries the file's pl / plb / c25 text")
    return 0


def submit(judge_source, build_judge_source=BUILD_J):
    try:
        script = build_script(judge_source, build_judge_source)
    except Exception as e:  # noqa: BLE001
        print("could not build the script:", e)
        return None, 2
    if os.environ.get("PLAN_SEAT_CONTROLS_SQL"):
        open(os.environ["PLAN_SEAT_CONTROLS_SQL"], "w").write(script)
    tie = view_tie()
    if tie:
        return None, tie
    r = run(["query", "--nosync", "--format=none", "--use_legacy_sql=false", "--nouse_cache", script])
    m = re.search(r"bqjob_[A-Za-z0-9_]+", r.stdout + r.stderr)
    if r.returncode != 0 or not m:
        print(r.stdout[-3000:], r.stderr[-3000:])
        return None, 2
    print("JOB=" + m.group(0), flush=True)
    return m.group(0), 0


def collect(job):
    while True:
        r = run(["--format=json", "show", "-j", job])
        if r.returncode != 0:
            print(r.stdout[-2000:], r.stderr[-2000:])
            return 2
        info = json.loads(r.stdout)
        state = info.get("status", {}).get("state")
        print(time.strftime("%H:%M:%S"), job, state, flush=True)
        if state == "DONE":
            break
        run(["wait", job, "60"])
    err = info.get("status", {}).get("errorResult")
    if err:
        print("the job failed:", err)
        return 2
    slot_s = int(info.get("statistics", {}).get("totalSlotMs", 0)) / 1000.0
    r = run(["--format=json", "head", "-j", "-n", "10000", job])
    if r.returncode != 0:
        print(r.stdout[-2000:], r.stderr[-2000:])
        return 2
    objs = json.loads(r.stdout)
    print(f"job {job}: {slot_s:,.1f} slot-seconds, {len(objs)} result rows")
    pick = next((json.loads(x["detail"]) for x in objs if x.get("copy") == "PICK"), {})
    if not pick:
        print("the PICK row did not parse")
        return 2
    print("doctored rows:", pick)
    got = {}
    for x in objs:
        if x.get("copy") != "PICK":
            got[(x["copy"], x["check_name"][:3].strip())] = int(x["violations"])
    bad = []
    live = {k[1]: v for k, v in got.items() if k[0] == "LIVE"}
    print("LIVE:", len(live), "checks;", "non-zero:", {k: v for k, v in live.items() if v} or "none")
    if not live or any(live.values()):
        bad.append(("LIVE", "every check 0", live))
    for name, (_, targets, needs) in COPIES.items():
        if targets is None:
            continue
        missing = [c for c in needs if pick.get(c) is None]
        if missing:
            print(f"NOT EXERCISED {name:30} no row to doctor on this partition ({', '.join(missing)} NULL)")
            bad.append((name, "NOT EXERCISED", missing))
            continue
        for chk, want in targets:
            v = got.get((name, chk))
            ok = (v is not None and v >= 1) if want == "GE1" else (v == want)
            others = {k[1]: x for k, x in got.items()
                      if k[0] == name and k[1] not in [t[0] for t in targets] and x != live.get(k[1])}
            flag = "ok " if ok else "BAD"
            print(f"{flag} {name:30} {chk} = {v} (expected {want}); other checks that moved: {others or 'none'}")
            if not ok:
                bad.append((name, chk, v, want))
    if bad:
        print("MISMATCHES / NOT EXERCISED:", bad)
        return 1
    return 0


def main():
    judge_source = VIEW
    if "--judge-table" in sys.argv:
        judge_source = "`" + sys.argv[sys.argv.index("--judge-table") + 1] + "`"
    build_judge_source = BUILD_J
    if "--build-judge-table" in sys.argv:
        build_judge_source = "`" + sys.argv[sys.argv.index("--build-judge-table") + 1] + "`"
    if "--collect" in sys.argv:
        return collect(sys.argv[sys.argv.index("--collect") + 1])
    job, rc = submit(judge_source, build_judge_source)
    if rc or "--submit" in sys.argv:
        return rc
    return collect(job)


if __name__ == "__main__":
    sys.exit(main())
