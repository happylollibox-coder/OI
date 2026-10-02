#!/usr/bin/env python3
"""Run V_PLAN_WINDOW_JUDGMENT_acceptance.sql on the live judgement and on doctored copies.

WHY THIS EXISTS
    The house rule is that every acceptance check has a negative control run on a temp copy.
    The judge's memory checks (G1..G4, piece-1 plan Task 2, v27.156) and the two checks Task 2
    restated (C12, C22) read the judgement view AND the live plan's history. The deployed view
    cannot be pointed at a doctored history, so this script runs the acceptance file's OWN text
    with the two names swapped for temp tables:
        `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT` -> jj  (a copy of the judgement)
        `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`    -> hh  (a copy of the live plan's history)
    Nothing here restates a check: a change to the acceptance file is what gets tested.

THE COPIES (one script, one scan of the view; each copy is one run of the acceptance)
    LIVE                     the judgement and the history as they are: every check 0.
    NC_G1_RUN_TOO_LONG       a fake keyword with GRACE on 09-01 (window 3) and GRACE on 09-04: G1 1.
    HC_G1_INSIDE             the same with the second GRACE on 09-03: G1 0.
    HC_G1_GOOD_RESET         GRACE 09-01, GOOD 09-02, GRACE 09-04 (a new run): G1 0.
    HC_G1_GAP_RESET          GRACE 09-01, GRACE 09-10 on a night that cleared the memory: G1 0.
    NC_G1_NO_RESET           the same 09-10 GRACE with no clearing recorded: G1 1.
    NC_G1_EMPTY_HISTORY      no history at all: G1 1 (the emptiness term).
    NC_G2_STRONG_DAY_OUT     one row made HELD, kept by STRONG_DAY_IN_WINDOW, the strong day one
                             day before window_from: G2 1.
    HC_G2_STRONG_DAY_IN      the same with the strong day ON window_from: G2 0, G3 0.
    NC_G2_NO_REASON          a HELD row with hold_kept_by NULL: G2 1.
    NC_G2_LAST_DAY_WEAK      a HELD row kept by LAST_DAY whose last day is not strong: G2 1.
    NC_G2_REASON_UNHELD      a row that is not HELD carrying hold_kept_by: G2 1.
    NC_G3_NO_CLOCK           the HC_G2 row with hold_since NULL: G3 1.
    NC_G4_DOCTORED_GRACE     the plan's control: a keyword with a live row on 08-27 and no GOOD or
                             GRACE since, whose ads record reads a GOOD 3-day window inside the
                             08-29..09-27 gap: its 08-27 row made GRACE and its judgement row made
                             to honour a spent grace (prior_grace TRUE): G4 1.
    HC_G4_NOT_HONOURED       the same history, the judgement row left alone: G4 0.
    NC_G4_CLEARED_HONOURED   a row the judge cleared tonight (memory_cleared_by_gap GRACE) made to
                             honour its grace anyway: G4 1 (vacuous when the judge cleared none).
    NC_C12_RUN_OVER          a GRACE row whose grace_ends_on is yesterday: C12 1.
    NC_C22_NO_END_DATE       a GRACE row whose sentence lost its "through <date>": C22 1.
    A copy's other checks are printed and not asserted: doctoring one row can trip another check.

EXIT CODES
    0  LIVE read 0 on every check and every copy read its expected value on its target check
    1  a copy did not (each mismatch is printed)
    2  the check could not run (bq failed, or the acceptance file did not parse)

USAGE
    python3 scripts/bigquery/tests/check_judge_memory_controls.py [--judge-table PROJECT.DATASET.TABLE]
    --judge-table reads a snapshot of the judgement instead of the deployed view (its extra
    columns are ignored; it must carry every column the view publishes).
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
ACC_FILE = os.path.join(ROOT, "scripts", "bigquery", "tests", "V_PLAN_WINDOW_JUDGMENT_acceptance.sql")
VIEW = "`onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`"
PLAN = "`onyga-482313.OI.FACT_PLAN_NEXT_WEEK`"


def acceptance_query():
    lines = [l for l in open(ACC_FILE).read().split("\n") if not l.startswith("--")]
    q = "\n".join(lines).strip().rstrip(";")
    if VIEW not in q or PLAN not in q:
        raise ValueError("the acceptance file no longer reads the view and the plan table by name")
    return q.replace(VIEW, "jj").replace(PLAN, "hh")


def fake(d, verdict, cleared="NULL"):
    return (f"SELECT TRUE AS is_live_plan, 'NC_G1' AS campaign_id, 'NC_G1' AS keyword_id, DATE '{d}' AS as_of, "
            f"'{verdict}' AS verdict, 3 AS window_days, DATE_SUB(DATE '{d}', INTERVAL 2 DAY) AS window_to, "
            f"CAST({cleared} AS STRING) AS memory_cleared_by_gap")


H_LIVE = "SELECT * FROM hbase"
J_LIVE = "SELECT * EXCEPT (rn) FROM jbase"


def j_held(**repl):
    """the HELD-doctored row: the lowest-numbered row that served, outside the holdout"""
    sets = ", ".join(f"IF(rn = (SELECT held_rn FROM pick), {v}, {k}) AS {k}" for k, v in repl.items())
    return f"SELECT * EXCEPT (rn) REPLACE ({sets}) FROM jbase"


HELD_BASE = {
    "verdict": "'HELD_UNSETTLED'", "side_b": "'GOOD'", "last_day_strong": "FALSE",
    "hold_kept_by": "'STRONG_DAY_IN_WINDOW'", "hold_since": "DATE_SUB(window_from, INTERVAL 1 DAY)",
    "hold_settles_on": "DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)",
}

COPIES = {
    "LIVE": (J_LIVE, H_LIVE, None),
    "NC_G1_RUN_TOO_LONG": (J_LIVE, f"{H_LIVE} UNION ALL {fake('2026-09-01','GRACE')} UNION ALL {fake('2026-09-04','GRACE')}", ("G1", 1)),
    "HC_G1_INSIDE": (J_LIVE, f"{H_LIVE} UNION ALL {fake('2026-09-01','GRACE')} UNION ALL {fake('2026-09-03','GRACE')}", ("G1", 0)),
    "HC_G1_GOOD_RESET": (J_LIVE, f"{H_LIVE} UNION ALL {fake('2026-09-01','GRACE')} UNION ALL {fake('2026-09-02','GOOD')} UNION ALL {fake('2026-09-04','GRACE')}", ("G1", 0)),
    "HC_G1_GAP_RESET": (J_LIVE, f"{H_LIVE} UNION ALL {fake('2026-09-01','GRACE')} UNION ALL {fake('2026-09-10','GRACE', chr(39)+'GRACE'+chr(39))}", ("G1", 0)),
    "NC_G1_NO_RESET": (J_LIVE, f"{H_LIVE} UNION ALL {fake('2026-09-01','GRACE')} UNION ALL {fake('2026-09-10','GRACE')}", ("G1", 1)),
    "NC_G1_EMPTY_HISTORY": (J_LIVE, f"{H_LIVE} WHERE FALSE", ("G1", 1)),
    "NC_G2_STRONG_DAY_OUT": (j_held(**HELD_BASE, hold_strong_day="DATE_SUB(window_from, INTERVAL 1 DAY)"), H_LIVE, ("G2", 1)),
    "HC_G2_STRONG_DAY_IN": (j_held(**HELD_BASE, hold_strong_day="window_from"), H_LIVE, ("G2", 0)),
    "NC_G2_NO_REASON": (j_held(**{**HELD_BASE, "hold_kept_by": "CAST(NULL AS STRING)"}, hold_strong_day="window_from"), H_LIVE, ("G2", 1)),
    "NC_G2_LAST_DAY_WEAK": (j_held(**{**HELD_BASE, "hold_kept_by": "'LAST_DAY'"}, hold_strong_day="window_from"), H_LIVE, ("G2", 1)),
    "NC_G2_REASON_UNHELD": (j_held(hold_kept_by="'LAST_DAY'", verdict="IF(verdict = 'HELD_UNSETTLED', 'LOSING', verdict)"), H_LIVE, ("G2", 1)),
    "NC_G3_NO_CLOCK": (j_held(**{**HELD_BASE, "hold_since": "CAST(NULL AS DATE)"}, hold_strong_day="window_from"), H_LIVE, ("G3", 1)),
    "NC_G4_DOCTORED_GRACE": (
        "SELECT * EXCEPT (rn) REPLACE (IF(CONCAT(campaign_id, '|', keyword_id) = (SELECT k FROM g4key), TRUE, prior_grace) AS prior_grace) FROM jbase",
        "SELECT * REPLACE (IF(CONCAT(campaign_id, '|', keyword_id) = (SELECT k FROM g4key) AND as_of = DATE '2026-08-27', 'GRACE', verdict) AS verdict) FROM hbase",
        ("G4", 1)),
    "HC_G4_NOT_HONOURED": (
        J_LIVE,
        "SELECT * REPLACE (IF(CONCAT(campaign_id, '|', keyword_id) = (SELECT k FROM g4key) AND as_of = DATE '2026-08-27', 'GRACE', verdict) AS verdict) FROM hbase",
        ("G4", 0)),
    "NC_G4_CLEARED_HONOURED": (
        "SELECT * EXCEPT (rn) REPLACE (IF(rn = (SELECT cleared_rn FROM pick), TRUE, prior_grace) AS prior_grace, "
        "IF(rn = (SELECT cleared_rn FROM pick), CAST(NULL AS STRING), memory_cleared_by_gap) AS memory_cleared_by_gap) FROM jbase",
        H_LIVE, ("G4", "1_IF_CLEARED")),
    "NC_C12_RUN_OVER": (
        "SELECT * EXCEPT (rn) REPLACE (IF(rn = (SELECT grace_rn FROM pick), DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY), grace_ends_on) AS grace_ends_on) FROM jbase",
        H_LIVE, ("C12", "1_IF_GRACE")),
    "NC_C22_NO_END_DATE": (
        "SELECT * EXCEPT (rn) REPLACE (IF(rn = (SELECT grace_rn FROM pick), REPLACE(sentence, FORMAT('through %t', grace_ends_on), 'through then'), sentence) AS sentence) FROM jbase",
        H_LIVE, ("C22", "1_IF_GRACE")),
}


def build_script(judge_source):
    acc = acceptance_query()
    parts = [
        f"CREATE TEMP TABLE jbase AS SELECT *, ROW_NUMBER() OVER (ORDER BY campaign_id, keyword_id) AS rn FROM {judge_source};",
        "CREATE TEMP TABLE hbase AS SELECT is_live_plan, CAST(campaign_id AS STRING) AS campaign_id, "
        "CAST(keyword_id AS STRING) AS keyword_id, as_of, verdict, window_days, window_to, memory_cleared_by_gap "
        f"FROM {PLAN};",
        # the rows the copies doctor, chosen deterministically
        "CREATE TEMP TABLE pick AS SELECT "
        "(SELECT MIN(rn) FROM jbase WHERE served AND NOT holdout) AS held_rn, "
        "(SELECT MIN(rn) FROM jbase WHERE verdict = 'GRACE') AS grace_rn, "
        "(SELECT MIN(rn) FROM jbase WHERE memory_cleared_by_gap IN ('GRACE', 'GRACE_AND_HOLD')) AS cleared_rn;",
        # NC_G4's keyword: a live row on 08-27, no GOOD or GRACE verdict from then on, no hold run,
        # and a 3-day window ending 08-27..09-15 (judged by PEAK nights 08-29..09-17, 3-day windows)
        # that reads GOOD on the ads record against tonight's bar; the lowest such key
        "CREATE TEMP TABLE g4key AS "
        "WITH c AS (SELECT j.campaign_id, j.keyword_id, j.family_bar FROM jbase j "
        "  WHERE j.verdict NOT IN ('GOOD', 'GRACE') AND j.hold_since IS NULL AND NOT j.prior_grace "
        "    AND j.memory_cleared_by_gap IS NULL "
        "    AND EXISTS (SELECT 1 FROM hbase h WHERE h.is_live_plan AND h.campaign_id = j.campaign_id AND h.keyword_id = j.keyword_id AND h.as_of = DATE '2026-08-27') "
        "    AND NOT EXISTS (SELECT 1 FROM hbase h WHERE h.is_live_plan AND h.campaign_id = j.campaign_id AND h.keyword_id = j.keyword_id "
        "                    AND h.as_of >= DATE '2026-08-27' AND h.verdict IN ('GOOD', 'GRACE'))), "
        "w AS (SELECT c.campaign_id, c.keyword_id, c.family_bar, d, SUM(f.Ads_orders) AS o, "
        "  SAFE_DIVIDE(SUM(f.GROSS_PROFIT), NULLIF(SUM(f.Ads_cost), 0)) AS r "
        "  FROM c CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(DATE '2026-08-27', DATE '2026-09-15')) AS d "
        "  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` f ON CAST(f.campaign_id AS STRING) = c.campaign_id "
        "   AND CAST(f.keyword_id AS STRING) = c.keyword_id AND f.date BETWEEN DATE_SUB(d, INTERVAL 2 DAY) AND d "
        "  GROUP BY 1, 2, 3, 4) "
        "SELECT MIN(CONCAT(campaign_id, '|', keyword_id)) AS k FROM w WHERE o >= 2 AND r >= family_bar;",
        "SELECT 'PICK' AS copy, (SELECT held_rn FROM pick) AS held_rn, (SELECT grace_rn FROM pick) AS grace_rn, "
        "(SELECT cleared_rn FROM pick) AS cleared_rn, (SELECT k FROM g4key) AS g4key;",
    ]
    for name, (jsql, hsql, _) in COPIES.items():
        parts.append(f"CREATE OR REPLACE TEMP TABLE jj AS {jsql};")
        parts.append(f"CREATE OR REPLACE TEMP TABLE hh AS {hsql};")
        parts.append(f"SELECT '{name}' AS copy, check_name, violations FROM (\n{acc}\n);")
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
    r = subprocess.run(["bq", "query", "--project_id=onyga-482313", "--use_legacy_sql=false", "--nouse_cache",
                        "--format=json", "--max_rows=1000", script], capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-3000:], r.stderr[-3000:])
        return 2
    if os.environ.get("JUDGE_CONTROLS_RAW"):
        open(os.environ["JUDGE_CONTROLS_RAW"], "w").write(r.stdout)
    # bq prints one JSON array per statement, keys in alphabetical order
    rows = [json.loads(m) for m in re.findall(r'\{[^{}]*"copy":[^{}]*\}', r.stdout)]
    pick = next((x for x in rows if x.get("copy") == "PICK"), {})
    print("doctored rows:", pick)
    got = {}
    for x in rows:
        if "check_name" in x:
            got[(x["copy"], x["check_name"][:3].strip())] = int(x["violations"])
    bad = []
    live = {k[1]: v for k, v in got.items() if k[0] == "LIVE"}
    print("LIVE:", len(live), "checks;", "non-zero:", {k: v for k, v in live.items() if v} or "none")
    if not live or any(live.values()):
        bad.append(("LIVE", "every check 0", live))
    for name, (_, _, target) in COPIES.items():
        if target is None:
            continue
        chk, want = target
        v = got.get((name, chk))
        if want == "1_IF_CLEARED":
            want = 1 if pick.get("cleared_rn") else 0
        if want == "1_IF_GRACE":
            want = 1 if pick.get("grace_rn") else 0
        others = {k[1]: x for k, x in got.items() if k[0] == name and k[1] != chk and x != live.get(k[1])}
        flag = "ok " if v == want else "BAD"
        print(f"{flag} {name:26} {chk} = {v} (expected {want}); other checks that moved: {others or 'none'}")
        if v != want:
            bad.append((name, chk, v, want))
    if bad:
        print("MISMATCHES:", bad)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
