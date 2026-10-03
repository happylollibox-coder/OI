#!/usr/bin/env python3
"""The Weekly Run scorecard panel reads EVERY row of the scorecard, hand changes included.

WHY THIS EXISTS
    Since 2026-10-01 (learning-system Task B) V_CHANGE_SCORECARD also grades
    source = 'OBSERVED': changes the DIM SCD2 trail shows on Amazon that OI never
    logged, which are mostly Ori's own edits in the console. The morning brief and
    the board read the scorecard without them; the tuner reads them since Ori's
    ruling of 2026-10-02. scripts/bigquery/tests/OBSERVED_CHANGES_acceptance.sql
    (C09) checks those three, because they are views.

    The fourth reader is Cube ChangeScorecard (cube/schema/ChangeScorecard.js),
    which feeds the Weekly Run panel "How did last week's changes do?"
    (dashboard-react/src/pages/ChangeScorecardPanel.tsx). It is a JavaScript
    file, so no query can read what it returns. From 2026-10-01 to 2026-10-03 it
    held hand changes out (WHERE source != 'OBSERVED') and this check asserted
    that. Ori's ruling of 2026-10-02 puts them in the panel, labelled as his (the
    OBSERVED chip), so since 2026-10-03 it asserts the opposite: the cube drops
    no row of the view, of any source.

HOW IT READS THE CUBE
    By EVALUATING it, as scripts/bigquery/tests/check_seat_surface_labels.py
    does: the file is run in node with `cube` stubbed, so the SQL checked here is
    exactly the SQL Cube would send. That SQL runs in BigQuery next to a BARE
    copy: the same SQL cut off right after the view's name, so the cube's own
    select list over the whole view, with any filter the cube carries removed.
    Both run in ONE statement, so both see the same CURRENT_DATE.

CHECKS (violation counts, 0 = PASS)
    K01   |OBSERVED rows in the bare copy - OBSERVED rows the cube returns|:
          every graded hand change reaches the panel
    K01n  NEGATIVE CONTROL: the bare copy returns >= 1 OBSERVED row (else K01
          passes over an input that has none, which proves nothing)
    K02   |rows in the bare copy - rows the cube returns|: the cube drops
          nothing, of any source
    K02n  NEGATIVE CONTROL: the bare copy returns >= 1 row that is not OBSERVED
          (else K02 cannot see a filter that hides logged changes)

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
    2026-10-01 entries ran the checks as they then stood, which ASSERTED the filter
    (K01 = OBSERVED rows the cube returns; K02 = cube rows vs non-OBSERVED rows).
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
    2026-10-03 08:53-08:55 LA (15:53-15:55 UTC), the filter lifted (Ori's ruling of 2026-10-02),
      checks inverted as above. On the cube file as committed: K01 0 / K01n 0 / K02 0 / K02n 0,
      exit 0. Cube 1,973 rows, 145 OBSERVED; bare view 1,973 rows, 145 OBSERVED, 1,828 not.
      2,905 slot-seconds, 13 s.
    Whole-file negative controls, same session, doctored temp copies in the session scratchpad
    run through CHANGE_SCORECARD_CUBE_FILE; each exited 1, K01n and K02n 0 in each:
      the 2026-10-01 filter put back, WHERE source != 'OBSERVED' ... K01 145, K02 145
      a filter that drops the coach, WHERE source != 'COACH' ..... K01 0, K02 1678
      3,368 and 2,110 slot-seconds.
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
    bare = sql[:sql.index(VIEW) + len(VIEW)]

    q = """
WITH
cube_rows AS (
%s
),
bare_view AS (
%s
),
a AS (SELECT COUNT(*) AS n, COUNTIF(source = 'OBSERVED') AS obs FROM cube_rows),
b AS (SELECT COUNT(*) AS n, COUNTIF(source = 'OBSERVED') AS obs,
             COUNTIF(source != 'OBSERVED') AS logged
      FROM bare_view)
SELECT a.n AS cube_n, a.obs AS cube_obs, b.n AS bare_n, b.obs AS bare_obs,
       b.logged AS bare_logged
FROM a CROSS JOIN b
""" % (sql, bare)

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
        # A HAND CHANGE IS MISSING FROM THE WEEKLY RUN PANEL: Ori ruled on 2026-10-02 that his
        # console edits are evidence, shown labelled as his; a source filter in the cube hides
        # their settled results, REVERSED restores included.
        ("K01 the cube returns every OBSERVED row of the view",
         abs(m["bare_obs"] - m["cube_obs"])),
        # K01 CANNOT FIRE: the view holds no graded hand change today, so a cube that filters
        # them out would pass K01 too.
        ("K01n NEGATIVE CONTROL K01 FIRES: the bare view returns >= 1 OBSERVED row",
         0 if m["bare_obs"] >= 1 else 1),
        # THE CUBE HIDES ROWS: changes (the coach's, the books', Ori's) vanish from the panel and
        # their settled results are never read.
        ("K02 the cube returns every row of the view",
         abs(m["bare_n"] - m["cube_n"])),
        # K02 CANNOT FIRE ON LOGGED ROWS: every graded row today is OBSERVED, so a filter that
        # drops the logged changes would pass K02 too.
        ("K02n NEGATIVE CONTROL K02 FIRES: the bare view returns >= 1 row that is not OBSERVED",
         0 if m["bare_logged"] >= 1 else 1),
    ]
    width = max(len(c[0]) for c in checks)
    failed = 0
    for name, v in checks:
        print("%s  %5d  %s" % (name.ljust(width), v, "PASS" if v == 0 else "FAIL"))
        failed += 1 if v else 0
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
