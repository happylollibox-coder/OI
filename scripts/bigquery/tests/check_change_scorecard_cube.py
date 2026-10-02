#!/usr/bin/env python3
"""The Weekly Run scorecard panel reads the scorecard WITHOUT hand changes seen only on Amazon.

WHY THIS EXISTS
    Since 2026-10-01 (learning-system Task B) V_CHANGE_SCORECARD also grades
    source = 'OBSERVED': changes the DIM SCD2 trail shows on Amazon that OI never
    logged, which are mostly Ori's own edits in the console. The morning brief,
    the board and the tuner read the scorecard without them until Ori decides
    otherwise; scripts/bigquery/tests/OBSERVED_CHANGES_acceptance.sql (C09)
    checks those three, because they are views.

    The fourth reader is Cube ChangeScorecard (cube/schema/ChangeScorecard.js),
    which feeds the Weekly Run panel "How did last week's changes do?"
    (dashboard-react/src/pages/ChangeScorecardPanel.tsx). It is a JavaScript
    file, so no query can read its filter. Without the filter the panel lists
    hand changes as REVERSED with a value to restore (60 and 52 on 2026-10-01).

HOW IT READS THE CUBE
    By EVALUATING it, as scripts/bigquery/tests/check_seat_surface_labels.py
    does: the file is run in node with `cube` stubbed, so the SQL checked here is
    exactly the SQL Cube would send. That SQL runs in BigQuery next to an
    UNFILTERED copy: the same SQL cut off right after the view's name, so the
    cube's own select list over the whole view, with whatever filter the cube
    carries removed. Both run in ONE statement, so both see the same CURRENT_DATE.

CHECKS (violation counts, 0 = PASS)
    K01   OBSERVED rows the cube's SQL returns, +1 if it returns no rows at all
    K01n  NEGATIVE CONTROL: the unfiltered copy returns >= 1 OBSERVED row (else
          K01 passes over an input that has none, which proves nothing)
    K02   |rows the cube returns - the unfiltered copy's rows with
          source != 'OBSERVED'|: the filter drops nothing but hand changes
    K02n  NEGATIVE CONTROL: a COACH-only filter would return a different count
          from the non-OBSERVED rows (else K02 cannot tell a too-broad filter)

COST
    Two reads of V_CHANGE_SCORECARD in one job; its slot-seconds are printed.

EXIT CODES
    0  every check passes
    1  a check failed
    2  the check could not run (node missing, bq failed, the view not named
       exactly once in the cube's SQL) — never a silent pass

USAGE
    python3 scripts/bigquery/tests/check_change_scorecard_cube.py
    CHANGE_SCORECARD_CUBE_FILE=/path/to/doctored_copy.js python3 ...   (negative controls only)

RUN LOG — dated; re-run rather than trusting a figure here.
    2026-10-01 17:36 and 17:41 LA (2026-10-02 00:36 / 00:41 UTC), on the fixed cube file
      (same SQL both times; the second run is on the file as committed, after comment edits):
      K01 0 / K01n 0 / K02 0 / K02n 0, exit 0, both runs. Cube 1,828 rows, 0 OBSERVED;
      unfiltered copy 1,973 rows, 145 OBSERVED, 1,828 not OBSERVED, 1,678 COACH.
      1,304 and 2,823 slot-seconds, 10 s and 19 s.
    Whole-file negative controls, 17:36-17:38 LA, each a doctored temp copy of the cube
    file in the session scratchpad (never the committed file), run through
    CHANGE_SCORECARD_CUBE_FILE; every one exited 1, K01n and K02n 0 in each:
      the file as it stood before the fix (no filter) ... K01 145, K02 145
      the filter widened to WHERE source = 'COACH' ...... K01 0, K02 150
      the filter plus AND FALSE (the panel empty) ....... K01 1 (the emptiness term), K02 1828
"""

import json
import os
import shutil
import subprocess
import sys
import time

# ---- Declared constants -----------------------------------------------------
PROJECT = "onyga-482313"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
# Overridable only to run the check against a doctored temp copy of the file (the run log's
# whole-file negative controls); the committed file is the default.
CUBE_FILE = (os.environ.get("CHANGE_SCORECARD_CUBE_FILE")
             or os.path.join(ROOT, "cube", "schema", "ChangeScorecard.js"))
VIEW = "`onyga-482313.OI.V_CHANGE_SCORECARD`"
NODE_CANDIDATES = [
    shutil.which("node"),
    "/Users/ori/.nvm/versions/node/v22.22.1/bin/node",
]


def die(msg, code=2):
    print("CANNOT RUN: %s" % msg)
    sys.exit(code)


def node_binary():
    for c in NODE_CANDIDATES:
        if c and os.path.exists(c):
            return c
    die("no node binary found (tried PATH and the nvm path in NODE_CANDIDATES)")


def cube_sql():
    """Load ChangeScorecard.js the way Cube would, and hand back its sql."""
    stub = (
        "let captured = null;"
        "global.cube = (name, def) => { captured = { name, def }; };"
        "require(%s);"
        "process.stdout.write(JSON.stringify({ name: captured.name, sql: String(captured.def.sql) }));"
    ) % json.dumps(CUBE_FILE)
    r = subprocess.run([node_binary(), "-e", stub], capture_output=True, text=True)
    if r.returncode != 0:
        die("node could not load %s:\n%s" % (CUBE_FILE, r.stderr.strip()))
    d = json.loads(r.stdout)
    if d["name"] != "ChangeScorecard":
        die("%s defines cube %r, expected ChangeScorecard" % (CUBE_FILE, d["name"]))
    return d["sql"].strip()


def main():
    sql = cube_sql()
    if sql.count(VIEW) != 1:
        die("the cube's SQL names %s %d times, expected once — repoint this check rather "
            "than delete it; it reads:\n%s" % (VIEW, sql.count(VIEW), sql))
    unfiltered = sql[:sql.index(VIEW) + len(VIEW)]

    q = """
WITH
cube_rows AS (
%s
),
unfiltered AS (
%s
),
a AS (SELECT COUNT(*) AS n, COUNTIF(source = 'OBSERVED') AS obs FROM cube_rows),
b AS (SELECT COUNT(*) AS n, COUNTIF(source = 'OBSERVED') AS obs,
             COUNTIF(source != 'OBSERVED') AS kept, COUNTIF(source = 'COACH') AS coach_only
      FROM unfiltered)
SELECT a.n AS cube_n, a.obs AS cube_obs, b.n AS unfiltered_n, b.obs AS unfiltered_obs,
       b.kept AS unfiltered_kept, b.coach_only AS unfiltered_coach_only
FROM a CROSS JOIN b
""" % (sql, unfiltered)

    job_id = "check_change_scorecard_cube_%d" % int(time.time() * 1000)
    r = subprocess.run(
        ["bq", "query", "--project_id=%s" % PROJECT, "--location=US", "--job_id=%s" % job_id,
         "--use_legacy_sql=false", "--nouse_cache", "--format=json", q],
        capture_output=True, text=True)
    if r.returncode != 0:
        die("bq failed:\n%s\n%s" % (r.stdout.strip(), r.stderr.strip()))
    rows = json.loads(r.stdout)
    if len(rows) != 1:
        die("expected one result row, got %d" % len(rows))
    m = {k: int(v) for k, v in rows[0].items()}
    print("cube file: %s" % CUBE_FILE)
    print("measured: %s" % json.dumps(m, sort_keys=True))
    s = subprocess.run(
        ["bq", "show", "--project_id=%s" % PROJECT, "--location=US", "--format=json", "-j", job_id],
        capture_output=True, text=True)
    try:
        st = json.loads(s.stdout)["statistics"]
        print("job %s: %.0f slot-seconds, %.0f s elapsed"
              % (job_id, int(st["totalSlotMs"]) / 1000.0,
                 (int(st["endTime"]) - int(st["startTime"])) / 1000.0))
    except (ValueError, KeyError):
        print("job %s: slot-seconds not readable (bq show said: %s)"
              % (job_id, s.stderr.strip() or s.stdout.strip()))

    checks = [
        # THE WEEKLY RUN PANEL SHOWS HAND CHANGES: Ori's own console edits are listed as
        # REVERSED with a value to restore before he has ruled on them; or the panel is empty
        # and this check proves nothing.
        ("K01 the cube's SQL returns no OBSERVED row, and returns rows",
         m["cube_obs"] + (1 if m["cube_n"] == 0 else 0)),
        # K01 CANNOT FIRE: the view holds no graded hand change today, so a cube without its
        # filter would pass K01 too.
        ("K01n NEGATIVE CONTROL K01 FIRES: the unfiltered copy returns >= 1 OBSERVED row",
         0 if m["unfiltered_obs"] >= 1 else 1),
        # THE FILTER HIDES MORE THAN HAND CHANGES: logged changes (the coach's or Ori's) vanish
        # from the panel and their settled results are never read.
        ("K02 the cube returns every non-OBSERVED row of the view",
         abs(m["cube_n"] - m["unfiltered_kept"])),
        # K02 CANNOT FIRE: no row today is outside COACH and OBSERVED, so a filter keeping the
        # coach's rows only would pass K02 too.
        ("K02n NEGATIVE CONTROL K02 FIRES: a COACH-only filter would return a different count",
         0 if m["unfiltered_coach_only"] != m["unfiltered_kept"] else 1),
    ]
    width = max(len(c[0]) for c in checks)
    failed = 0
    for name, v in checks:
        print("%s  %5d  %s" % (name.ljust(width), v, "PASS" if v == 0 else "FAIL"))
        failed += 1 if v else 0
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
