#!/usr/bin/env python3
"""Run FACT_PLAN_NEXT_WEEK_acceptance.sql and PLAN_SEAT_REQUEST_acceptance.sql on the live plan and
on doctored copies of it — the negative controls of piece-1 plan Task 5 (v27.159).

WHY THIS EXISTS
    The house rule is that every acceptance check has a negative control run on a temp copy, and
    that an empty input fails rather than passes. Task 5 (Ori's rulings R2 / R6 / R12 / R13 / R15 of
    2026-10-02 = spec P-16 / P-20 / P-25 / P-26 / P-28, audit fix #19) restated C06, C12, C14, C17,
    C19 and C23 and added T1..T5 to the plan's acceptance, and restated S03 / S06 / S07 / S11 of the
    seat-request acceptance. The table cannot be doctored, so this script runs each file's OWN text
    with two names swapped:
        `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`      -> a copy of EVERY partition (T2 reads the history),
                                                      doctored per copy
        `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`   -> one snapshot of the judgement, read ONCE
    Each copy is materialized as a temp table, then each acceptance runs on it as ONE statement.
    Nothing here restates a check: a change to an acceptance file is what gets tested. Doctored rows are chosen deterministically (lowest rn) in the latest partition
    (`b0`, the live plan) and the one before it (`prev0`).

THE COPIES
    LIVE                          every check 0.
    NC_EMPTY                      no rows: C23 T1 T2 T3 T4 T5 read 1 (emptiness terms).
    HC_T1_INCUMBENT               a continuing live seat made an incumbent with a coherent contract
                                  (the previous partition's row carries tonight's contract, seated
                                  the night before with a verdict date settle_days later; tonight
                                  tagged INCUMBENT with that date): T1 0, C23 0, T3 0.
    NC_T1_PRICE_MOVED             that incumbent's price +$0.10 tonight: T1 1.
    NC_T1_QUESTION_MOVED          that incumbent's clicks_requested +1 tonight: T1 1.
    NC_T1_TENURE_WITHOUT_CONTRACT a NEW seat tagged INCUMBENT with no contract behind it: T1 >= 1 (the
                                  tenure term and the sentence term each count it).
    NC_C23_SEAT_DROPPED           the plan's control: the previous partition holds a seat dated
                                  tomorrow for a keyword tonight's walk queues: C23 1, T1 1.
    HC_T1_EVICTION_JUSTIFIED      that seat's contract costs $1,000 a day (above any allowance), and
                                  tonight says TENURE ENDS EARLY: C23 0, T1 0.
    NC_T1_EVICTION_UNJUSTIFIED    the same with a contract costing $0.01: T1 1.
    NC_C23_RENUMBERED             a continuing occupant (same number both nights; the register holds
                                  that number for no other keyword) given number 900: C23 1, T2 1.
    NC_T2_RETURN_RENUMBERED       a seated keyword absent the night before whose most recent seat
                                  number is honoured tonight, given number 901: T2 1 (0 when no such
                                  keyword exists — the copy is then vacuous and says so).
    HC_C17_PLAN_A                 a plan-A seat given a number the register holds open for another
                                  keyword: C17 0 (the register is the live plan's).
    NC_C17_PLAN_B                 the same on the live plan: C17 >= 1 (2 when the keyword has its own
                                  register row; 0 when the register holds no number outside tonight's
                                  seats — the copy is then vacuous and says so).
    NC_T3_CLICKS_DOUBLED          the plan's control: one seat's clicks_requested doubled: T3 1,
                                  and PLAN_SEAT_REQUEST S03 1.
    NC_T4_PROBE_PARKED            an unseated probe given PARK at $0.20 and the v27.158 sentence
                                  ("keeps buying clicks"): T4 >= 1, C14 >= 1.
    NC_T4_OPEN_PROBE_SILENT       a seated probe's sentence without "OPEN PROBE at $": T4 1 (0 when
                                  no probe is seated).
    NC_C14_PROBE_REPRICED         a seated probe's move REPRICE: C14 1 (0 when no probe is seated).
    NC_C06_NONE_ON_SEAT           a seated non-probe's move NONE: C06 >= 1.
    NC_T5_RANK_SWAPPED            the ranks 1 and 2 of one family swapped: T5 2.
    NC_S06_HORIZON                one NEW ordinary seat asking for w_clk (v27.158's question) under
                                  the HORIZON_WINDOW_RATE basis: S06 1, T3 1 (0 when its w_clk
                                  already equals its horizon ask).
    A copy's other checks are printed and not asserted: doctoring one row can trip another check.

EXIT CODES
    0  LIVE read 0 on every check and every copy read its expected value on its target checks
    1  a copy did not (each mismatch is printed)
    2  the check could not run (bq failed, or an acceptance file did not parse)

USAGE
    python3 scripts/bigquery/tests/check_plan_seat_controls.py [--judge-table PROJECT.DATASET.TABLE]
    --judge-table reads a snapshot of the judgement instead of the deployed view; use one taken
    from the same data the latest partition was built on, or C13 reads the difference on LIVE.
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
ACC_PLAN = os.path.join(ROOT, "scripts", "bigquery", "tests", "FACT_PLAN_NEXT_WEEK_acceptance.sql")
ACC_REQ = os.path.join(ROOT, "scripts", "bigquery", "tests", "PLAN_SEAT_REQUEST_acceptance.sql")
VIEW = "`onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`"
PLAN = "`onyga-482313.OI.FACT_PLAN_NEXT_WEEK`"


def acceptance_query(path, needs_view):
    lines = [l for l in open(path).read().split("\n") if not re.match(r"^\s*--", l)]
    q = "\n".join(lines).strip().rstrip(";")
    if PLAN not in q or (needs_view and VIEW not in q):
        raise ValueError(f"{os.path.basename(path)} no longer reads the plan table (and the view) by name")
    return q.replace(VIEW, "jsnap").replace(PLAN, "__HH__")


LIVE = "SELECT * EXCEPT (rn) FROM hbase"


def rows(cond, **repl):
    """the rows matching cond (SQL over hbase columns and the pick table), doctored"""
    sets = ", ".join(f"IF({cond}, {v}, {k}) AS {k}" for k, v in repl.items())
    return f"SELECT * EXCEPT (rn) REPLACE ({sets}) FROM hbase"


def at(col, **repl):
    return rows(f"rn = (SELECT {col} FROM pick)", **repl)


def two(col_tonight, col_prev, tonight, prev):
    """doctor one row tonight and one row in the previous partition (both by rn), in one copy"""
    sets = []
    keys = set(tonight) | set(prev)
    for k in sorted(keys):
        e = k
        if k in prev:
            e = f"IF(rn = (SELECT {col_prev} FROM pick), {prev[k]}, {e})"
        if k in tonight:
            e = f"IF(rn = (SELECT {col_tonight} FROM pick), {tonight[k]}, {e})"
        sets.append(f"{e} AS {k}")
    return f"SELECT * EXCEPT (rn) REPLACE ({', '.join(sets)}) FROM hbase"


# the contract a previous-partition row must carry for the doctored incumbent: tonight's own, seated
# the night before (prev as_of) with a verdict date settle_days after that
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


def incumbent_tonight(extra=None):
    d = {
        "seat_tenure": "'INCUMBENT'",
        "seat_since": "(SELECT prev_as_of FROM pick)",
        "verdict_date": "DATE_ADD((SELECT prev_as_of FROM pick), INTERVAL DATE_DIFF(verdict_date, seat_since, DAY) DAY)",
        "clicks_due_date": "DATE_ADD((SELECT prev_as_of FROM pick), INTERVAL DATE_DIFF(verdict_date, seat_since, DAY) DAY)",
        "sentence": "REPLACE(sentence, 'TENURE: seated tonight', 'TENURE: it has held this seat since')",
    }
    d.update(extra or {})
    return d


DROP_PREV = {  # a seat dated tomorrow in the previous partition, for a keyword tonight queues
    "seat_no": "999", "planned_bid": "current_bid", "seat_cost_per_day": "0.5",
    "seat_since": "(SELECT prev_as_of FROM pick)",
    "verdict_date": "DATE_ADD((SELECT mx FROM pick), INTERVAL 1 DAY)",
    "clicks_requested": "7", "clicks_due_date": "DATE_ADD((SELECT mx FROM pick), INTERVAL 1 DAY)",
    "expected_cpc": "0.5", "implied_daily_spend": "0.5", "request_basis": "'HORIZON_WINDOW_RATE'",
}

COPIES = {
    "LIVE": (LIVE, None),
    "NC_EMPTY": (f"{LIVE} WHERE FALSE",
                 [("C23", 1), ("T1", 1), ("T2", 1), ("T3", 1), ("T4", 1), ("T5", 1)]),
    "HC_T1_INCUMBENT": (two("inc_rn", "inc_prev_rn", incumbent_tonight(), contract_from_tonight("inc_rn")),
                        [("T1", 0), ("C23", 0), ("T3", 0)]),
    "NC_T1_PRICE_MOVED": (two("inc_rn", "inc_prev_rn", incumbent_tonight({"planned_bid": "planned_bid + 0.10"}),
                              contract_from_tonight("inc_rn")), ("T1", 1)),
    "NC_T1_QUESTION_MOVED": (two("inc_rn", "inc_prev_rn", incumbent_tonight({"clicks_requested": "clicks_requested + 1"}),
                                 contract_from_tonight("inc_rn")), ("T1", 1)),
    "NC_T1_TENURE_WITHOUT_CONTRACT": (at("new_rn", seat_tenure="'INCUMBENT'"), ("T1", "GE1")),
    "NC_C23_SEAT_DROPPED": (two("queued_rn", "queued_prev_rn", {}, DROP_PREV), [("C23", 1), ("T1", 1)]),
    "HC_T1_EVICTION_JUSTIFIED": (two("queued_rn", "queued_prev_rn",
                                     {"seat_tenure": "'LEFT_ALLOWANCE_SHRANK'",
                                      "sentence": "CONCAT(sentence, ' TENURE ENDS EARLY: doctored.')"},
                                     dict(DROP_PREV, seat_cost_per_day="1000.0")),
                                 [("C23", 0), ("T1", 0)]),
    "NC_T1_EVICTION_UNJUSTIFIED": (two("queued_rn", "queued_prev_rn",
                                       {"seat_tenure": "'LEFT_ALLOWANCE_SHRANK'",
                                        "sentence": "CONCAT(sentence, ' TENURE ENDS EARLY: doctored.')"},
                                       dict(DROP_PREV, seat_cost_per_day="0.01")),
                                   [("C23", 0), ("T1", 1)]),
    "NC_C23_RENUMBERED": (at("cont_rn", seat_no="900"), [("C23", 1), ("T2", 1)]),
    "NC_T2_RETURN_RENUMBERED": (at("ret_rn", seat_no="901"), ("T2", "1_IF_RETURN")),
    "HC_C17_PLAN_A": (at("a_rn", seat_no="(SELECT reg_no FROM pick)"), ("C17", 0)),
    "NC_C17_PLAN_B": (at("b_rn", seat_no="(SELECT reg_no FROM pick)"), ("C17", "GE1_IF_REG")),
    "NC_T3_CLICKS_DOUBLED": (at("new_rn", clicks_requested="clicks_requested * 2"), [("T3", 1), ("S03", 1)]),
    "NC_T4_PROBE_PARKED": (at("probe_none_rn", move="'PARK'", planned_bid="0.20",
                              sentence="REPLACE(sentence, 'PROBE NOT OPENED TONIGHT; NOTHING UPLOADED', 'park the bid; it keeps buying clicks at the park price')"),
                           [("T4", "GE1"), ("C14", "GE1")]),
    "NC_T4_OPEN_PROBE_SILENT": (at("probe_open_rn", sentence="REPLACE(sentence, 'OPEN PROBE at $', 'OPEN at $')"),
                                ("T4", "1_IF_OPEN_PROBE")),
    "NC_C14_PROBE_REPRICED": (at("probe_open_rn", move="'REPRICE'"), ("C14", "1_IF_OPEN_PROBE")),
    "NC_C06_NONE_ON_SEAT": (at("new_rn", move="'NONE'"), ("C06", "GE1")),
    "NC_T5_RANK_SWAPPED": (rows("rn IN ((SELECT r1_rn FROM pick), (SELECT r2_rn FROM pick))",
                                rank_no="IF(rank_no = 1, 2, 1)"), ("T5", 2)),
    "NC_S06_HORIZON": (at("ord_rn", clicks_requested="CAST(w_clk AS INT64)"), [("S06", "1_IF_HORIZON"), ("T3", "1_IF_HORIZON")]),
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
-- a continuing live occupant: seated both nights at the same number, not a probe, no register row
cont AS (SELECT t.rn, y.rn AS prev_rn FROM b0 t JOIN prev0 y USING (plan, family, campaign_id, keyword_id)
         LEFT JOIN led l ON l.family = t.family AND l.campaign_id = t.campaign_id AND l.keyword_id = t.keyword_id
         WHERE t.seat_no IS NOT NULL AND y.seat_no = t.seat_no AND NOT COALESCE(t.is_probe, FALSE)
           AND t.seat_tenure = 'NEW'),
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
  (SELECT MIN(rn) FROM b0 WHERE seat_tenure = 'NEW' AND NOT COALESCE(is_probe, FALSE)) AS new_rn,
  (SELECT MIN(t.rn) FROM b0 t WHERE t.is_candidate AND t.seat_no IS NULL AND COALESCE(t.ladder_state, '') != 'DEAD') AS queued_rn,
  (SELECT y.rn FROM b0 t JOIN prev0 y USING (plan, family, campaign_id, keyword_id)
   WHERE t.rn = (SELECT MIN(t2.rn) FROM b0 t2 WHERE t2.is_candidate AND t2.seat_no IS NULL AND COALESCE(t2.ladder_state, '') != 'DEAD')) AS queued_prev_rn,
  (SELECT MIN(rn) FROM contnoreg) AS cont_rn,
  (SELECT MIN(rn) FROM ret) AS ret_rn,
  (SELECT MIN(l.seat_no) FROM led l WHERE l.family = (SELECT family FROM a0 WHERE seat_no IS NOT NULL ORDER BY rn LIMIT 1)
     AND l.seat_no NOT IN (SELECT seat_no FROM a0 WHERE seat_no IS NOT NULL AND family = l.family)
     AND l.seat_no NOT IN (SELECT seat_no FROM b0 WHERE seat_no IS NOT NULL AND family = l.family)) AS reg_no,
  (SELECT rn FROM a0 WHERE seat_no IS NOT NULL ORDER BY rn LIMIT 1) AS a_rn,
  (SELECT MIN(rn) FROM b0 WHERE seat_no IS NOT NULL
     AND family = (SELECT family FROM a0 WHERE seat_no IS NOT NULL ORDER BY rn LIMIT 1)) AS b_rn,
  (SELECT MIN(rn) FROM b0 WHERE is_candidate AND move = 'NONE') AS probe_none_rn,
  (SELECT MIN(rn) FROM b0 WHERE move = 'OPEN_PROBE') AS probe_open_rn,
  (SELECT rn FROM b0 WHERE is_candidate AND rank_no = 1 AND family = (SELECT f FROM fam1)) AS r1_rn,
  (SELECT rn FROM b0 WHERE is_candidate AND rank_no = 2 AND family = (SELECT f FROM fam1)) AS r2_rn,
  (SELECT MIN(rn) FROM b0 WHERE seat_tenure = 'NEW' AND request_basis = 'HORIZON_WINDOW_RATE'
     AND clicks_requested != w_clk) AS ord_rn;
"""


def build_script(judge_source):
    acc_plan = acceptance_query(ACC_PLAN, True)
    acc_req = acceptance_query(ACC_REQ, False)
    parts = [
        f"CREATE TEMP TABLE jsnap AS SELECT * FROM {judge_source};",
        "CREATE TEMP TABLE hbase AS SELECT *, ROW_NUMBER() OVER (ORDER BY as_of, plan, campaign_id, keyword_id) AS rn "
        f"FROM {PLAN};",
        PICK,
        "SELECT 'PICK' AS copy, * FROM pick;",
    ]
    for i, (name, (hsql, _)) in enumerate(COPIES.items()):
        # each copy is MATERIALIZED first: the acceptance reads the plan table at several places, and
        # an inline doctored subquery at each of them exceeded BigQuery's planning limit (first run,
        # 2026-10-02: "query is too complex")
        parts.append(f"CREATE TEMP TABLE hh{i} AS {hsql};")
        for tag, acc in (("P", acc_plan), ("R", acc_req)):
            q = acc.replace("__HH__", f"hh{i}")
            if tag == "P":
                parts.append(f"SELECT '{name}' AS copy, check_name, violations FROM (\n{q}\n);")
            else:
                parts.append(f"SELECT '{name}' AS copy, check_name, v AS violations FROM (\n{q}\n);")
    return "\n".join(parts)


def main():
    judge_source = VIEW
    if "--judge-table" in sys.argv:
        judge_source = "`" + sys.argv[sys.argv.index("--judge-table") + 1] + "`"
    try:
        script = build_script(judge_source)
    except Exception as e:  # noqa: BLE001
        print("could not build the script:", e)
        return 2
    if os.environ.get("PLAN_SEAT_CONTROLS_SQL"):
        open(os.environ["PLAN_SEAT_CONTROLS_SQL"], "w").write(script)
    r = subprocess.run(["bq", "query", "--project_id=onyga-482313", "--use_legacy_sql=false", "--nouse_cache",
                        "--format=json", "--max_rows=1000", script], capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-3000:], r.stderr[-3000:])
        return 2
    if os.environ.get("PLAN_SEAT_CONTROLS_RAW"):
        open(os.environ["PLAN_SEAT_CONTROLS_RAW"], "w").write(r.stdout)
    # bq prints one JSON array per statement: parse the row objects, not the whole output
    objs = [json.loads(m) for m in re.findall(r'\{[^{}]*"copy":[^{}]*\}', r.stdout)]
    pick = next((x for x in objs if x.get("copy") == "PICK"), {})
    if not pick:
        print("the PICK row did not parse")
        return 2
    print("doctored rows:", pick)
    got = {}
    for x in objs:
        if "check_name" in x:
            got[(x["copy"], x["check_name"][:3].strip())] = int(x["violations"])
    bad = []
    live = {k[1]: v for k, v in got.items() if k[0] == "LIVE"}
    print("LIVE:", len(live), "checks;", "non-zero:", {k: v for k, v in live.items() if v} or "none")
    if not live or any(live.values()):
        bad.append(("LIVE", "every check 0", live))
    for name, (_, targets) in COPIES.items():
        if targets is None:
            continue
        if isinstance(targets, tuple):
            targets = [targets]
        for chk, want in targets:
            v = got.get((name, chk))
            if want == "1_IF_RETURN":
                want = 1 if pick.get("ret_rn") else 0
            if want == "1_IF_OPEN_PROBE":
                want = 1 if pick.get("probe_open_rn") else 0
            if want == "1_IF_HORIZON":
                want = 1 if pick.get("ord_rn") else 0
            if want == "GE1_IF_REG":
                want = "GE1" if pick.get("reg_no") else 0
            ok = (v is not None and v >= 1) if want == "GE1" else (v == want)
            others = {k[1]: x for k, x in got.items()
                      if k[0] == name and k[1] not in [t[0] for t in targets] and x != live.get(k[1])}
            flag = "ok " if ok else "BAD"
            print(f"{flag} {name:30} {chk} = {v} (expected {want}); other checks that moved: {others or 'none'}")
            if not ok:
                bad.append((name, chk, v, want))
    if bad:
        print("MISMATCHES:", bad)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
