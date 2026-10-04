#!/usr/bin/env python3
"""The ledger freeze (learning piece 2, fix L1, v27.177), proved on copies: a stored night's forecast
does not move when FACT_KEYWORD_STATE_HISTORY is re-captured, backfilled or pruned, or when
FACT_PLAN_NEXT_WEEK.builder_version is backfilled — and the v27.172 view it replaced does move.

WHAT IT RUNS (one BigQuery script, TEMP copies only; it writes one scratch table,
OI._tmp_l1c_readings, which --collect reads and drops):
  OLD    = V_PREDICTION_LEDGER v27.172, the body at commit 53326a5 (git show), which read
           FACT_KEYWORD_STATE_HISTORY at query time;
  NEW    = scripts/bigquery/views/V_PREDICTION_LEDGER.sql (v27.177), which reads the night's frozen
           inputs, FACT_PREDICTION_LEDGER_INPUTS;
  FREEZE = scripts/bigquery/procedures/SP_FREEZE_LEDGER_INPUTS.sql's body, run as a block.
  Each body is its file with comment lines stripped and only these names swapped for TEMP copies:
  FACT_PLAN_NEXT_WEEK (c_p...), FACT_KEYWORD_STATE_HISTORY (c_h..., its seven columns the two read),
  FACT_PREDICTION_LEDGER_INPUTS (f...). FACT_THRESHOLD_HISTORY is read live by both.

THE COPIES AND WHAT EACH READING MUST BE
  BASE        f0 = FREEZE on (c_p, c_h) into an empty copy.
              B_NEW_OLD   NEW(c_p, f0) vs OLD(c_p, c_h), every key and column     -> 0
              B_NEW_PRE   NEW(c_p, f0) vs the saved pre-edit output (OI._tmp_l1_ledger_pre), on its
                          nights                                                   -> 0 (skipped if gone)
              B_OLD_PRE   OLD(c_p, c_h) vs the same                                -> 0 (skipped if gone)
              B_REAL_PRE  NEW(c_p, the REAL FACT_PREDICTION_LEDGER_INPUTS) vs the same -> 0
              B_F0_REAL   f0 vs the real freeze on the real freeze's nights (all columns but
                          frozen_at / frozen_by)                                   -> 0
              B_ROWS      rows of NEW(c_p, f0)                                     -> > 0 (emptiness)
  RECAP       h1 = c_h + a re-capture of snapshot_date R (the snapshot the latest night with a
              zero-click OPEN_PROBE was priced on), stamped one hour after the history's newest
              captured_at, settled_ord90 + 1 and settled_gp90 + 10 on every row (a re-read of a
              restated record).
              R_OLD       OLD(c_p, h1) vs OLD(c_p, c_h)                            -> > 0 (old moves)
              R_INS       rows FREEZE inserts on (c_p, h1) into a copy of f0        -> 0
              R_NEW       NEW(c_p, that copy) vs NEW(c_p, f0)                       -> 0 (new does not)
  PRUNED      h2 = h1 with R's older copy pruned, as SP_APPEND_KEYWORD_STATE_HISTORY's prune does
              (keep MAX(captured_at)).
              P_OLD, P_INS, P_NEW as above                                         -> > 0, 0, 0
  BV          p3 = c_p with builder_version 'v27.169' on every row that has none (a backfill).
              V_OLD       OLD(p3, c_h) vs OLD(c_p, c_h)                            -> > 0
              V_NEW       NEW(p3, f0) vs NEW(c_p, f0)                              -> 0
  FUTURE      p5 = c_p + the latest night re-keyed as a night built later (as_of + 7 days,
              built_at = the history's newest captured_at + 30 minutes, builder_version 'v27.177'),
              frozen on (p5, c_h) into a copy f5 (U_INS0 rows, > 0); then h6 = c_h + a re-capture of
              the snapshot_date f5 froze for that night, one hour after its built_at, values moved as
              in RECAP, older copy pruned; FREEZE on (p5, h6) into f5 again.
              U_INS1      rows inserted by the second FREEZE                       -> 0
              U_NEW       NEW(p5, f5) after vs before the re-capture              -> 0
              U_OLD       OLD(p5, h6) vs OLD(p5, c_h)                              -> > 0
  FIRST       f7 = f0 + a second freeze of the latest night an hour later, settled_ord90 + 1.
              W_NEW       NEW(c_p, f7) vs NEW(c_p, f0)                             -> 0 (first freeze wins)
  NC_FROZEN   f8 = f0 with the latest night's frozen settled_ord90 + 1 on every in-snapshot row:
              the comparison sees a frozen-input change.
              N_NEW       NEW(c_p, f8) vs NEW(c_p, f0)                             -> > 0
  A diff counts keys (predictor, as_of, campaign_id, keyword_id, scenario) present on one side only
  or with any column different (FLOAT64 beyond 1e-9 relative, others IS DISTINCT FROM); beside each,
  INFO readings <name>.nights (distinct as_of among them) and <name>.act_seat_probe_rows (ACT rows
  priced from a seat, SEAT_PROBE_OWN / SEAT_PROBE_POOLED).

USAGE
  python3 scripts/bigquery/tests/check_ledger_freeze_controls.py --submit      # prints the job id
  bq wait JOB 60                                                                # one call at a time
  python3 scripts/bigquery/tests/check_ledger_freeze_controls.py --collect JOB  # asserts, exit 0/1
  LEDGER_FREEZE_SQL=/path/out.sql ... --print                                   # writes the script
SOP: architecture/LEARNING.md §10 "Fix L1".
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
VIEW = os.path.join(ROOT, "scripts", "bigquery", "views", "V_PREDICTION_LEDGER.sql")
FREEZE = os.path.join(ROOT, "scripts", "bigquery", "procedures", "SP_FREEZE_LEDGER_INPUTS.sql")
OLD_COMMIT = "53326a5"
P = "`onyga-482313.OI."
BQ = ["bq", "--project_id=onyga-482313"]
READINGS = "`onyga-482313.OI._tmp_l1c_readings`"
PRE = "onyga-482313.OI._tmp_l1_ledger_pre"

COLS = [("predictor", "S"), ("variant", "S"), ("scenario", "S"), ("as_of", "S"), ("built_at", "S"),
        ("builder_version", "S"), ("horizon_from", "S"), ("horizon_to", "S"), ("window_days", "S"),
        ("family", "S"), ("campaign_id", "S"), ("keyword_id", "S"), ("channel", "S"),
        ("calendar_state", "S"), ("is_live_plan", "S"), ("holdout", "S"), ("family_bar", "F"),
        ("min_orders", "S"), ("current_bid", "F"), ("planned_bid", "F"),
        ("campaign_current_budget", "F"), ("campaign_planned_budget", "F"), ("move", "S"),
        ("alloc_spend", "F"), ("act_is_noop", "S"), ("pred_side", "S"), ("basis_clicks", "S"),
        ("basis_spend", "F"), ("settle_factor_eff", "F"), ("pred_clicks", "F"), ("pred_spend", "F"),
        ("pred_orders", "F"), ("pred_gp", "F"), ("pred_net", "F"), ("act_bid_ratio", "F"),
        ("act_budget_factor", "F"), ("act_basis", "S"), ("rule_version", "S"),
        ("response_model_version", "S")]
KEY = ["predictor", "as_of", "campaign_id", "keyword_id", "scenario"]
FCOLS = ["as_of", "built_at", "builder_version", "rule_builder_tag", "family", "channel", "campaign_id",
         "keyword_id", "in_snapshot", "snapshot_date", "snapshot_captured_at", "settled_clk90",
         "settled_ord90", "settled_gp90"]

EXPECT = {  # reading -> 'ZERO' | 'FIRE' (>= 1) | 'ZERO_IF' (0, or NULL when the saved copy is gone)
    "B_NEW_OLD": "ZERO", "B_NEW_PRE": "ZERO_IF", "B_OLD_PRE": "ZERO_IF", "B_REAL_PRE": "ZERO_IF",
    "B_F0_REAL": "ZERO", "B_ROWS": "FIRE",
    "R_OLD": "FIRE", "R_INS": "ZERO", "R_NEW": "ZERO",
    "P_OLD": "FIRE", "P_INS": "ZERO", "P_NEW": "ZERO",
    "V_OLD": "FIRE", "V_NEW": "ZERO",
    "U_INS0": "FIRE", "U_INS1": "ZERO", "U_NEW": "ZERO", "U_OLD": "FIRE",
    "W_NEW": "ZERO", "N_NEW": "FIRE",
}


def stripped(text):
    return "\n".join(l for l in text.split("\n") if not re.match(r"^\s*--", l))


def view_body(text):
    t = stripped(text)
    i = t.index("\nAS\n")
    return t[i + 4:].strip().rstrip(";").strip()


def swap(text, m):
    for k, v in m.items():
        text = text.replace(P + k + "`", v)
    return text


def old_body():
    r = subprocess.run(["git", "-C", ROOT, "show", f"{OLD_COMMIT}:scripts/bigquery/views/V_PREDICTION_LEDGER.sql"],
                       capture_output=True, text=True, check=True)
    b = view_body(r.stdout)
    assert "FACT_KEYWORD_STATE_HISTORY" in b and "FACT_PREDICTION_LEDGER_INPUTS" not in b
    return b


def new_body():
    b = view_body(open(VIEW).read())
    assert "FACT_PREDICTION_LEDGER_INPUTS" in b and "FACT_KEYWORD_STATE_HISTORY" not in b
    return b


def freeze_body():
    t = stripped(open(FREEZE).read())
    m = re.search(r"^BEGIN$\n(.*)^END;\s*$", t, re.S | re.M)
    if not m:
        raise ValueError("SP_FREEZE_LEDGER_INPUTS.sql: no BEGIN ... END; body found")
    return m.group(1)


def old(dst, plan, hist):
    return f"CREATE TEMP TABLE {dst} AS\n" + swap(old_body(), {"FACT_PLAN_NEXT_WEEK": plan,
                                                               "FACT_KEYWORD_STATE_HISTORY": hist}) + ";\n"


def new(dst, plan, frz):
    return f"CREATE TEMP TABLE {dst} AS\n" + swap(new_body(), {"FACT_PLAN_NEXT_WEEK": plan,
                                                               "FACT_PREDICTION_LEDGER_INPUTS": frz}) + ";\n"


def freeze(frz, plan, hist, reading):
    body = swap(freeze_body(), {"FACT_PLAN_NEXT_WEEK": plan, "FACT_KEYWORD_STATE_HISTORY": hist,
                                "FACT_PREDICTION_LEDGER_INPUTS": frz})
    body = body.replace("DECLARE run_ts", "DECLARE caller STRING DEFAULT 'check_ledger_freeze_controls';\n  DECLARE run_ts", 1)
    return (f"SET n_before = (SELECT COUNT(*) FROM {frz});\nBEGIN\n{body}END;\n"
            f"INSERT INTO rd VALUES ('{reading}', (SELECT COUNT(*) FROM {frz}) - n_before);\n")


def fd(a, b):
    return f"(({a} IS NULL) != ({b} IS NULL) OR ABS({a} - {b}) > 1e-9 * GREATEST(1, ABS({a}), ABS({b})))"


def diff(reading, a, b, scope=None):
    """Keys on one side only, or with any column different. scope: a table of (as_of, built_at)."""
    on = " AND ".join(f"x.{k} = y.{k}" for k in KEY)
    preds = [f"x.{KEY[0]} IS NULL", f"y.{KEY[0]} IS NULL"]
    for c, t in COLS:
        preds.append(fd(f"x.{c}", f"y.{c}") if t == "F" else f"x.{c} IS DISTINCT FROM y.{c}")
    sx = ""
    if scope:
        sx = f" t WHERE EXISTS (SELECT 1 FROM {scope} s WHERE s.as_of = t.as_of AND s.built_at = t.built_at)"
    t = f"dk_{reading.lower()}"
    return (f"CREATE TEMP TABLE {t} AS SELECT COALESCE(x.as_of, y.as_of) AS as_of, "
            f"COALESCE(x.scenario, y.scenario) AS scenario, COALESCE(x.act_basis, y.act_basis) AS act_basis "
            f"FROM (SELECT * FROM {a}{sx}) x FULL OUTER JOIN (SELECT * FROM {b}{sx}) y ON {on} WHERE "
            + " OR ".join(preds) + ";\n"
            f"INSERT INTO rd VALUES ('{reading}', (SELECT COUNT(*) FROM {t}));\n"
            f"INSERT INTO rd VALUES ('{reading}.nights', (SELECT COUNT(DISTINCT as_of) FROM {t}));\n"
            f"INSERT INTO rd VALUES ('{reading}.act_seat_probe_rows', (SELECT COUNTIF(scenario = 'ACT' AND act_basis LIKE 'SEAT_PROBE%') FROM {t}));\n")


def script(pre_exists):
    s = []
    s.append("DECLARE n_before INT64;\nDECLARE recap_date DATE;\nDECLARE recap_at TIMESTAMP;\n"
             "DECLARE fut_built TIMESTAMP;\nDECLARE fut_date DATE;\nDECLARE latest STRUCT<as_of DATE, built_at TIMESTAMP>;\n")
    s.append("CREATE TEMP TABLE rd (reading STRING, n INT64);\n")
    s.append(f"CREATE TEMP TABLE c_p AS SELECT * FROM {P}FACT_PLAN_NEXT_WEEK`;\n")
    s.append(f"CREATE TEMP TABLE c_h AS SELECT snapshot_date, captured_at, campaign_id, keyword_id, settled_clk90, "
             f"settled_ord90, settled_gp90 FROM {P}FACT_KEYWORD_STATE_HISTORY`;\n")
    s.append(f"CREATE TEMP TABLE f_empty AS SELECT * FROM {P}FACT_PREDICTION_LEDGER_INPUTS` WHERE FALSE;\n")
    s.append(f"CREATE TEMP TABLE f_real AS SELECT * FROM {P}FACT_PREDICTION_LEDGER_INPUTS`;\n")
    # BASE
    s.append("CREATE TEMP TABLE f0 AS SELECT * FROM f_empty;\n")
    s.append(freeze("f0", "c_p", "c_h", "B_F0_INS"))
    s.append(new("new_base", "c_p", "f0"))
    s.append(old("old_base", "c_p", "c_h"))
    s.append(diff("B_NEW_OLD", "new_base", "old_base"))
    s.append("INSERT INTO rd VALUES ('B_ROWS', (SELECT COUNT(*) FROM new_base));\n")
    if pre_exists:
        s.append(f"CREATE TEMP TABLE pre AS SELECT * EXCEPT (_read_at) FROM `{PRE}`;\n")
        s.append("CREATE TEMP TABLE pre_nights AS SELECT DISTINCT as_of, built_at FROM pre;\n")
        s.append(diff("B_NEW_PRE", "new_base", "pre", "pre_nights"))
        s.append(diff("B_OLD_PRE", "old_base", "pre", "pre_nights"))
        s.append(new("new_real", "c_p", "f_real"))
        s.append(diff("B_REAL_PRE", "new_real", "pre", "pre_nights"))
    else:
        for r in ("B_NEW_PRE", "B_OLD_PRE", "B_REAL_PRE"):
            s.append(f"INSERT INTO rd VALUES ('{r}', NULL);\n")
    fc = ", ".join(FCOLS)
    s.append("INSERT INTO rd VALUES ('B_F0_REAL', (SELECT COUNT(*) FROM ("
             f"(SELECT {fc} FROM f0 t WHERE EXISTS (SELECT 1 FROM f_real s WHERE s.as_of = t.as_of AND s.built_at = t.built_at) "
             f"EXCEPT DISTINCT SELECT {fc} FROM f_real) UNION ALL "
             f"(SELECT {fc} FROM f_real EXCEPT DISTINCT SELECT {fc} FROM f0))));\n")
    # the night the re-capture targets: the latest night with a zero-click OPEN_PROBE, its frozen snapshot
    s.append("SET latest = (SELECT AS STRUCT as_of, built_at FROM c_p WHERE w_clk = 0 AND move = 'OPEN_PROBE' "
             "ORDER BY as_of DESC, built_at DESC LIMIT 1);\n")
    s.append("SET recap_date = (SELECT ANY_VALUE(snapshot_date) FROM f0 WHERE as_of = latest.as_of AND built_at = latest.built_at);\n")
    s.append("SET recap_at = (SELECT TIMESTAMP_ADD(MAX(captured_at), INTERVAL 1 HOUR) FROM c_h);\n")
    s.append("INSERT INTO rd VALUES ('X_RECAP_DATE_FOUND', IF(recap_date IS NULL, 0, 1));\n")
    # RECAP
    s.append("CREATE TEMP TABLE h1 AS SELECT * FROM c_h UNION ALL "
             "SELECT snapshot_date, recap_at, campaign_id, keyword_id, settled_clk90, settled_ord90 + 1, settled_gp90 + 10 "
             "FROM c_h WHERE snapshot_date = recap_date;\n")
    s.append(old("old_h1", "c_p", "h1"))
    s.append(diff("R_OLD", "old_h1", "old_base"))
    s.append("CREATE TEMP TABLE f1 AS SELECT * FROM f0;\n")
    s.append(freeze("f1", "c_p", "h1", "R_INS"))
    s.append(new("new_h1", "c_p", "f1"))
    s.append(diff("R_NEW", "new_h1", "new_base"))
    # PRUNED
    s.append("CREATE TEMP TABLE h2 AS SELECT * FROM h1 WHERE NOT (snapshot_date = recap_date AND captured_at < recap_at);\n")
    s.append(old("old_h2", "c_p", "h2"))
    s.append(diff("P_OLD", "old_h2", "old_base"))
    s.append("CREATE TEMP TABLE f2 AS SELECT * FROM f0;\n")
    s.append(freeze("f2", "c_p", "h2", "P_INS"))
    s.append(new("new_h2", "c_p", "f2"))
    s.append(diff("P_NEW", "new_h2", "new_base"))
    # BV
    s.append("CREATE TEMP TABLE p3 AS SELECT * REPLACE (IFNULL(builder_version, 'v27.169') AS builder_version) FROM c_p;\n")
    s.append(old("old_p3", "p3", "c_h"))
    s.append(diff("V_OLD", "old_p3", "old_base"))
    s.append(new("new_p3", "p3", "f0"))
    s.append(diff("V_NEW", "new_p3", "new_base"))
    # FUTURE
    s.append("SET fut_built = (SELECT TIMESTAMP_ADD(MAX(captured_at), INTERVAL 30 MINUTE) FROM c_h);\n")
    s.append("CREATE TEMP TABLE p5 AS SELECT * FROM c_p UNION ALL "
             "SELECT * REPLACE (DATE_ADD(as_of, INTERVAL 7 DAY) AS as_of, fut_built AS built_at, 'v27.177' AS builder_version) "
             "FROM c_p WHERE as_of = latest.as_of AND built_at = latest.built_at;\n")
    s.append("CREATE TEMP TABLE f5 AS SELECT * FROM f0;\n")
    s.append(freeze("f5", "p5", "c_h", "U_INS0"))
    s.append(new("new_f5a", "p5", "f5"))
    s.append("SET fut_date = (SELECT ANY_VALUE(snapshot_date) FROM f5 WHERE built_at = fut_built);\n")
    s.append("INSERT INTO rd VALUES ('X_FUT_DATE_FOUND', IF(fut_date IS NULL, 0, 1));\n")
    s.append("CREATE TEMP TABLE h6 AS SELECT * FROM c_h WHERE snapshot_date != fut_date UNION ALL "
             "SELECT snapshot_date, TIMESTAMP_ADD(fut_built, INTERVAL 1 HOUR), campaign_id, keyword_id, settled_clk90, "
             "settled_ord90 + 1, settled_gp90 + 10 FROM c_h WHERE snapshot_date = fut_date;\n")
    s.append(freeze("f5", "p5", "h6", "U_INS1"))
    s.append(new("new_f5b", "p5", "f5"))
    s.append(diff("U_NEW", "new_f5b", "new_f5a"))
    s.append(old("old_p5", "p5", "c_h"))
    s.append(old("old_p5h6", "p5", "h6"))
    s.append(diff("U_OLD", "old_p5h6", "old_p5"))
    # FIRST freeze wins
    s.append("CREATE TEMP TABLE f7 AS SELECT * FROM f0 UNION ALL "
             "SELECT * REPLACE (settled_ord90 + 1 AS settled_ord90, TIMESTAMP_ADD(frozen_at, INTERVAL 1 HOUR) AS frozen_at) "
             "FROM f0 WHERE as_of = latest.as_of AND built_at = latest.built_at;\n")
    s.append(new("new_f7", "c_p", "f7"))
    s.append(diff("W_NEW", "new_f7", "new_base"))
    # NC: a frozen input moved is seen
    s.append("CREATE TEMP TABLE f8 AS SELECT * REPLACE (IF(as_of = latest.as_of AND built_at = latest.built_at AND in_snapshot, "
             "settled_ord90 + 1, settled_ord90) AS settled_ord90) FROM f0;\n")
    s.append(new("new_f8", "c_p", "f8"))
    s.append(diff("N_NEW", "new_f8", "new_base"))
    s.append("INSERT INTO rd SELECT 'X_RECAP_DATE', UNIX_DATE(recap_date);\n")
    s.append("INSERT INTO rd SELECT 'X_FUT_DATE', UNIX_DATE(fut_date);\n")
    s.append(f"CREATE OR REPLACE TABLE {READINGS} OPTIONS (expiration_timestamp = "
             "TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)) AS SELECT * FROM rd;\n")
    return "".join(s)


def pre_exists():
    r = subprocess.run(BQ + ["show", "--format=json", PRE.replace("onyga-482313.", "onyga-482313:")],
                       capture_output=True, text=True)
    return r.returncode == 0


def main():
    if "--print" in sys.argv or "--submit" in sys.argv:
        sql = script(pre_exists())
        if os.environ.get("LEDGER_FREEZE_SQL"):
            open(os.environ["LEDGER_FREEZE_SQL"], "w").write(sql)
        if "--submit" in sys.argv:
            r = subprocess.run(BQ + ["query", "--nosync", "--use_legacy_sql=false", "--nouse_cache", sql],
                               capture_output=True, text=True)
            m = re.search(r"(bqjob_\w+)", r.stdout + r.stderr)
            print(m.group(1) if m else (r.stdout.strip() + r.stderr.strip())[-2000:])
            return 0 if (r.returncode == 0 and m) else 1
        return 0
    if "--collect" in sys.argv:
        job = sys.argv[sys.argv.index("--collect") + 1]
        st = subprocess.run(BQ + ["show", "--format=json", "-j", job], capture_output=True, text=True)
        js = json.loads(st.stdout)
        err = js.get("status", {}).get("errorResult")
        stats = js.get("statistics", {})
        print("job", job, "state", js.get("status", {}).get("state"), "error", err)
        print("slot-seconds", round(int(stats.get("totalSlotMs", 0)) / 1000, 1),
              "bytes processed", stats.get("totalBytesProcessed"))
        if err or js.get("status", {}).get("state") != "DONE":
            return 1
        r = subprocess.run(BQ + ["query", "--format=json", "--use_legacy_sql=false", "--nouse_cache",
                                 f"SELECT reading, n FROM {READINGS} ORDER BY reading"], capture_output=True, text=True)
        rows = {x["reading"]: (None if x["n"] is None else int(x["n"])) for x in json.loads(r.stdout)}
        ok = True
        for k in sorted(rows):
            mode = EXPECT.get(k)
            n = rows[k]
            if mode == "ZERO":
                res = "PASS" if n == 0 else "FAIL"
            elif mode == "ZERO_IF":
                res = "PASS" if n in (0, None) else "FAIL"
            elif mode == "FIRE":
                res = "PASS" if (n or 0) >= 1 else "FAIL"
            elif k in ("X_RECAP_DATE_FOUND", "X_FUT_DATE_FOUND"):
                res = "PASS" if n == 1 else "FAIL"
            else:
                res = "INFO"
            ok = ok and res != "FAIL"
            print(f"{k:22s} {str(n):>8s}  {mode or ''}  {res}")
        missing = [k for k in EXPECT if k not in rows]
        if missing:
            print("MISSING readings:", missing)
            ok = False
        subprocess.run(BQ + ["rm", "-f", "-t", READINGS.strip("`").replace("onyga-482313.", "onyga-482313:")],
                       capture_output=True, text=True)
        return 0 if ok else 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
