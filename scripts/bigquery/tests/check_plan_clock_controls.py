#!/usr/bin/env python3
"""Run FACT_PLAN_NEXT_WEEK_acceptance.sql and V_ENGINE_HEALTH's plan_window_complete_days (c23) on the
live plan and on doctored copies of it — the negative controls of piece-1 plan Task 6 (v27.160).

WHY THIS EXISTS
    The house rule is that every acceptance check has a negative control run on a temp copy, and
    that an empty input fails rather than passes. Task 6 (Ori's ruling R11 of 2026-10-02 = spec P-24,
    and audit fix #25) keyed a night on the New York date, restated C01 (the age-2 fence is two days
    before the LOS ANGELES date of the build, not before as_of) and V_ENGINE_HEALTH's c23 with it, and
    added K1 (as_of is the New York date of the build), K2 (one calendar state per partition, and the
    latest partition carries its own date's state) and K3 (no shadow row names a side its side column
    does not hold; no priced row says it carries no price). The table cannot be doctored, so this
    script runs each file's OWN text with names swapped:
        `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`      -> a copy of EVERY partition (K1, K2 read the
                                                      history), doctored per copy
        `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`   -> one snapshot of the judgement, read ONCE
    and, for the board, the `pl` / `plb` / `c23` CTEs cut out of scripts/bigquery/views/V_ENGINE_HEALTH.sql
    (comment lines stripped) with the plan table swapped the same way; before submitting, the script
    checks that the DEPLOYED view's definition carries that text. Each copy is materialized, then each
    check runs on it. Nothing here restates a check. Doctored rows are chosen deterministically
    (lowest rn) in the latest partition.

THE COPIES (check: expected value on that copy; H23M = plan_window_complete_days' measured value,
H23S = 1 when its status is RED)
    LIVE                          every check 0, H23M 0, H23S 0.
    NC_EMPTY                      no rows: K1 1, K2 1, K3 1 (emptiness terms), H23S 1.
    NC_C01_WINDOW_SHIFTED         one live row's window moved a day earlier (window_from and
                                  window_to, so its length holds): C01 1, H23M 1, H23S 1.
    NC_K1_NOT_NY_DATE             every row of the latest partition stamped as built at 22:40 Los
                                  Angeles on its as_of — the New York date is the next day, which is
                                  how a Los Angeles-keyed 22:35 pass wrote: K1 1.
    NC_K2_TWO_STATES              one row of the latest partition given another calendar state:
                                  K2 2 (two states in one partition; not its date's state).
    NC_K2_REWRITTEN_WHOLE         every row of the latest partition given another state — the
                                  2026-09-30 defect, a partition rewritten whole under another night's
                                  state: K2 1 (one state per partition cannot see it; the date term does).
    NC_K3_RULE_B_WORDS_ON_GOOD    a plan-A GOOD row whose live row is NOT_GOOD and competes for a seat,
                                  given v27.159's sentence (the P-9 prefix + the live row's sentence):
                                  K3 2 (plan A's side unnamed; the not-good side's words).
    NC_K3_RULE_B_WORDS_ON_NOT_GOOD  a priced plan-A NOT_GOOD row whose live row is GOOD, given
                                  v27.159's sentence: K3 3 (side unnamed; the good side's words; a
                                  priced row saying it carries no planned price).
    NC_K3_PRICED_SAYS_NONE        a priced plan-A row on the live plan's side with "this row carries
                                  no planned price" appended: K3 1.
    NC_K3_FOREIGN_WORDS_SAME_SIDE a plan-A GOOD row on the live plan's side with "It competes for a
                                  seat at $1.00." appended: K3 1.
    NC_K3_NO_SHADOW               every plan-A row removed: K3 1 (emptiness), C02 >= 1.
    A copy's other checks are printed and not asserted. NOT EXERCISED: a copy whose doctored row does
    not exist on the partition (its pick column is NULL) tests nothing; it is reported and the script
    exits 1.

EXIT CODES
    0  LIVE read 0 on every check, every copy was exercised, and every copy read its expected value
    1  a copy did not, or was not exercised, or the deployed V_ENGINE_HEALTH does not carry this file's
       c23 text, or the acceptance still carries the K1 cutover placeholder
    2  the check could not run

USAGE (one BigQuery script job of 41 statements, submitted asynchronously and polled: 2,642.4
slot-seconds and about 2 minutes on 2026-10-03 02:51 UTC, job bqjob_r28d04f5d6d9da7e1_000001a0ffabd93a_1,
exit 0 on the live table; 2,407.5 slot-seconds and exit 0 on a simulated 22:40 Los Angeles pass,
--plan-table OI._tmp_t6_sim_plan --judge-table OI._tmp_t6_sim_judge, job
bqjob_r3b355b0a9c44aefd_000001a0ffb852de_1)
    python3 scripts/bigquery/tests/check_plan_clock_controls.py [--judge-table PROJECT.DATASET.TABLE]
    python3 scripts/bigquery/tests/check_plan_clock_controls.py --submit [--judge-table ...]
    python3 scripts/bigquery/tests/check_plan_clock_controls.py --collect JOB
    --judge-table reads a snapshot of the judgement instead of the deployed view; use one taken from
    the same data the latest partition was built on, or C13 reads the difference on LIVE.
    --plan-table reads a copy of the plan table instead of FACT_PLAN_NEXT_WEEK (a simulated pass
    written to a copy, with --judge-table the judgement that pass read).
"""
import json
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
ACC_PLAN = os.path.join(ROOT, "scripts", "bigquery", "tests", "FACT_PLAN_NEXT_WEEK_acceptance.sql")
HEALTH = os.path.join(ROOT, "scripts", "bigquery", "views", "V_ENGINE_HEALTH.sql")
VIEW = "`onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`"
PLAN = "`onyga-482313.OI.FACT_PLAN_NEXT_WEEK`"
BQ = ["bq", "--project_id=onyga-482313"]


def stripped(path):
    return "\n".join(l for l in open(path).read().split("\n") if not re.match(r"^\s*--", l))


def acceptance_query():
    q = stripped(ACC_PLAN).strip().rstrip(";")
    if PLAN not in q or VIEW not in q:
        raise ValueError("the acceptance no longer reads the plan table and the view by name")
    if "__K1_CUTOVER__" in q:
        raise ValueError("the acceptance still carries the K1 cutover placeholder")
    return q.replace(VIEW, "jsnap").replace(PLAN, "__HH__")


def health_ctes():
    text = stripped(HEALTH)
    m_pl = re.search(r"^pl AS \(.*?^plb AS \(SELECT \* FROM pl WHERE is_live_plan\),", text, re.S | re.M)
    m_c23 = re.search(r"^c23 AS \(.*?(?=^pot_rec AS \()", text, re.S | re.M)
    if not m_pl or not m_c23 or "'plan_window_complete_days'" not in m_c23.group(0) or PLAN not in m_pl.group(0):
        raise ValueError("V_ENGINE_HEALTH.sql: the pl / plb / c23 (plan_window_complete_days) CTEs were not found")
    return m_pl.group(0).rstrip().rstrip(","), m_c23.group(0).rstrip().rstrip(",")


def norm(s):
    return re.sub(r"\s+", " ", s).strip()


LIVE = "SELECT * EXCEPT (rn) FROM hbase"


def rows(cond, **repl):
    sets = ", ".join(f"IF({cond}, {v}, {k}) AS {k}" for k, v in repl.items())
    return f"SELECT * EXCEPT (rn) REPLACE ({sets}) FROM hbase"


def at(col, **repl):
    return rows(f"rn = (SELECT {col} FROM pick)", **repl)


LATEST = "as_of = (SELECT mx FROM pick)"
OTHER_STATE = "IF(calendar_state = 'OFF_PEAK', 'PEAK', 'OFF_PEAK')"
V159 = "'SHADOW PLAN A, recorded for grading and never uploaded (P-9). '"

# name -> (copy SQL, [(check, expected)], pick columns the copy needs: NULL = NOT EXERCISED)
COPIES = {
    "LIVE": (LIVE, None, []),
    "NC_EMPTY": (f"{LIVE} WHERE FALSE", [("K1", 1), ("K2", 1), ("K3", 1), ("H23S", 1)], []),
    "NC_C01_WINDOW_SHIFTED": (at("live_rn", window_from="DATE_SUB(window_from, INTERVAL 1 DAY)",
                                 window_to="DATE_SUB(window_to, INTERVAL 1 DAY)"),
                              [("C01", 1), ("H23M", 1), ("H23S", 1)], ["live_rn"]),
    "NC_K1_NOT_NY_DATE": (rows(LATEST, built_at="TIMESTAMP(DATETIME(as_of, TIME '22:40:00'), 'America/Los_Angeles')"),
                          [("K1", 1)], ["mx"]),
    "NC_K2_TWO_STATES": (at("live_rn", calendar_state=OTHER_STATE), [("K2", 2)], ["live_rn"]),
    "NC_K2_REWRITTEN_WHOLE": (rows(LATEST, calendar_state=OTHER_STATE), [("K2", 1)], ["mx"]),
    "NC_K3_RULE_B_WORDS_ON_GOOD": (at("a_good_rn", sentence=f"CONCAT({V159}, (SELECT sentence FROM hbase WHERE rn = (SELECT a_good_live_rn FROM pick)))"),
                                   [("K3", 2)], ["a_good_rn", "a_good_live_rn"]),
    "NC_K3_RULE_B_WORDS_ON_NOT_GOOD": (at("a_ng_rn", sentence=f"CONCAT({V159}, (SELECT sentence FROM hbase WHERE rn = (SELECT a_ng_live_rn FROM pick)))"),
                                       [("K3", 3)], ["a_ng_rn", "a_ng_live_rn"]),
    "NC_K3_PRICED_SAYS_NONE": (at("a_same_priced_rn", sentence="CONCAT(sentence, ' No move: this row carries no planned price.')"),
                               [("K3", 1)], ["a_same_priced_rn"]),
    "NC_K3_FOREIGN_WORDS_SAME_SIDE": (at("a_same_good_rn", sentence="CONCAT(sentence, ' It competes for a seat at $1.00.')"),
                                      [("K3", 1)], ["a_same_good_rn"]),
    "NC_K3_NO_SHADOW": (f"{LIVE} WHERE is_live_plan OR as_of != (SELECT mx FROM pick)",
                        [("K3", 1), ("C02", "GE1")], ["mx"]),
}

PICK = """CREATE TEMP TABLE pick AS
WITH t AS (SELECT * FROM hbase WHERE as_of = (SELECT MAX(as_of) FROM hbase)),
pair AS (SELECT a.rn, l.rn AS live_rn, a.side, l.side AS live_side, a.planned_bid, l.sentence AS live_sentence
         FROM t a JOIN t l ON l.campaign_id = a.campaign_id AND l.keyword_id = a.keyword_id
         WHERE NOT a.is_live_plan AND l.is_live_plan)
SELECT
  (SELECT MAX(as_of) FROM hbase) AS mx,
  (SELECT MIN(rn) FROM t WHERE is_live_plan) AS live_rn,
  (SELECT MIN(rn) FROM pair WHERE side = 'GOOD' AND live_side = 'NOT_GOOD'
     AND live_sentence LIKE '%competes for a seat%') AS a_good_rn,
  (SELECT live_rn FROM pair WHERE rn = (SELECT MIN(rn) FROM pair WHERE side = 'GOOD' AND live_side = 'NOT_GOOD'
     AND live_sentence LIKE '%competes for a seat%')) AS a_good_live_rn,
  (SELECT MIN(rn) FROM pair WHERE side = 'NOT_GOOD' AND live_side = 'GOOD' AND planned_bid IS NOT NULL) AS a_ng_rn,
  (SELECT live_rn FROM pair WHERE rn = (SELECT MIN(rn) FROM pair WHERE side = 'NOT_GOOD' AND live_side = 'GOOD'
     AND planned_bid IS NOT NULL)) AS a_ng_live_rn,
  (SELECT MIN(rn) FROM pair WHERE side = 'NOT_GOOD' AND live_side = 'NOT_GOOD' AND planned_bid IS NOT NULL) AS a_same_priced_rn,
  (SELECT MIN(rn) FROM pair WHERE side = 'GOOD' AND live_side = 'GOOD') AS a_same_good_rn;
"""


def raw(s):
    if '"""' in s or s.endswith('"'):
        raise ValueError("a check text cannot be held in a raw triple-quoted string")
    return 'r"""' + s + '"""'


def build_script(judge_source, plan_source=PLAN):
    acc_plan = acceptance_query()
    pl, c23 = health_ctes()
    acc_health = (f"WITH {pl.replace(PLAN, '__HH__')},\n{c23},\n"
                  "b AS (SELECT '' AS n, 0.0 AS measured, '' AS threshold, '' AS status, '' AS detail\n"
                  "      FROM UNNEST([1]) WHERE FALSE UNION ALL SELECT * FROM c23)\n"
                  "SELECT 'H23M plan_window_complete_days measured (V_ENGINE_HEALTH c23)' AS check_name,\n"
                  "       CAST(measured AS INT64) AS violations, status AS detail FROM b\n"
                  "UNION ALL\n"
                  "SELECT 'H23S plan_window_complete_days status is RED (V_ENGINE_HEALTH c23)',\n"
                  "       IF(status = 'RED', 1, 0), detail FROM b")
    parts = [
        f"DECLARE acc_plan STRING DEFAULT {raw(acc_plan)};",
        f"DECLARE acc_health STRING DEFAULT {raw(acc_health)};",
        f"CREATE TEMP TABLE jsnap AS SELECT * FROM {judge_source};",
        "CREATE TEMP TABLE hbase AS SELECT *, ROW_NUMBER() OVER (ORDER BY as_of, plan, campaign_id, keyword_id) AS rn "
        f"FROM {plan_source};",
        PICK,
        "CREATE TEMP TABLE res (copy STRING, check_name STRING, violations INT64, detail STRING);",
        "INSERT INTO res SELECT 'PICK', 'PICK', 0, TO_JSON_STRING(p) FROM pick p;",
    ]
    for i, (name, (hsql, _, _)) in enumerate(COPIES.items()):
        hh = f"hh{i}"
        parts.append(f"CREATE TEMP TABLE {hh} AS {hsql};")
        parts.append("EXECUTE IMMEDIATE FORMAT(\"INSERT INTO res SELECT '%s', check_name, violations, NULL "
                     f"FROM (%s)\", '{name}', REPLACE(acc_plan, '__HH__', '{hh}'));")
        parts.append("EXECUTE IMMEDIATE FORMAT(\"INSERT INTO res SELECT '%s', check_name, violations, detail "
                     f"FROM (%s)\", '{name}', REPLACE(acc_health, '__HH__', '{hh}'));")
    parts.append("SELECT copy, check_name, violations, detail FROM res ORDER BY copy, check_name;")
    return "\n".join(parts)


def run(args, timeout=None):
    return subprocess.run(BQ + args, capture_output=True, text=True, timeout=timeout)


def view_tie():
    pl, c23 = health_ctes()
    r = run(["--format=json", "query", "--use_legacy_sql=false", "--nouse_cache",
             "SELECT view_definition FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS` "
             "WHERE table_name = 'V_ENGINE_HEALTH'"])
    if r.returncode != 0:
        print(r.stdout[-2000:], r.stderr[-2000:])
        return 2
    rows_ = json.loads(r.stdout)
    deployed = norm(rows_[0]["view_definition"]) if rows_ else ""
    missing = [n for n, t in (("pl/plb", pl), ("c23", c23)) if norm(t) not in deployed]
    if missing:
        print("the deployed V_ENGINE_HEALTH does not carry this file's", missing, "text: run it on the deployed body")
        return 1
    print("the deployed V_ENGINE_HEALTH carries the file's pl / plb / c23 text")
    return 0


def submit(judge_source, plan_source=PLAN):
    try:
        script = build_script(judge_source, plan_source)
    except Exception as e:  # noqa: BLE001
        print("could not build the script:", e)
        return None, (1 if "placeholder" in str(e) else 2)
    if os.environ.get("PLAN_CLOCK_CONTROLS_SQL"):
        open(os.environ["PLAN_CLOCK_CONTROLS_SQL"], "w").write(script)
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
            key = x["check_name"].split(" ")[0]
            got[(x["copy"], key)] = int(x["violations"])
    bad = []
    live = {k[1]: v for k, v in got.items() if k[0] == "LIVE"}
    print("LIVE:", len(live), "readings;", "non-zero:", {k: v for k, v in live.items() if v} or "none")
    if not live or any(live.values()):
        bad.append(("LIVE", "every check 0", live))
    for name, (_, targets, needs) in COPIES.items():
        if targets is None:
            continue
        missing = [c for c in needs if pick.get(c) is None]
        if missing:
            print(f"NOT EXERCISED {name:32} no row to doctor on this partition ({', '.join(missing)} NULL)")
            bad.append((name, "NOT EXERCISED", missing))
            continue
        for chk, want in targets:
            v = got.get((name, chk))
            ok = (v is not None and v >= 1) if want == "GE1" else (v == want)
            others = {k[1]: x for k, x in got.items()
                      if k[0] == name and k[1] not in [t[0] for t in targets] and x != live.get(k[1])}
            flag = "ok " if ok else "BAD"
            print(f"{flag} {name:32} {chk} = {v} (expected {want}); other checks that moved: {others or 'none'}")
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
    plan_source = PLAN
    if "--plan-table" in sys.argv:
        plan_source = "`" + sys.argv[sys.argv.index("--plan-table") + 1] + "`"
    if "--collect" in sys.argv:
        return collect(sys.argv[sys.argv.index("--collect") + 1])
    job, rc = submit(judge_source, plan_source)
    if rc or "--submit" in sys.argv:
        return rc
    return collect(job)


if __name__ == "__main__":
    sys.exit(main())
