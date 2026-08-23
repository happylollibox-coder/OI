#!/usr/bin/env python3
"""The two Task-4 guarantees SQL cannot assert, because they live in FILES.

WHY THIS EXISTS
    The morning surface (family seat register Task 4) promises two things that no
    query can check, because both are properties of source files rather than of
    rows:

      1. THE CUBE SHOWS EVERY COLUMN A PERSON READS. cube/schema/SeatRegister.js
         must carry a dimension for every column of T_FAMILY_SEAT_REGISTER. A
         column added to the register and forgotten here does not fail a query —
         it simply never appears on the page, which is the quietest kind of wrong.

      2. EVERY LABEL CASE HAS LEARNED EVERY CATEGORY. The register decides a
         family's `doctrine_status` in its own CASE. The SEATS sections of
         V_DAILY_BRIEF and V_RUN_SUMMARY each map that status to plain words. If
         someone adds a status to the register, those maps fall through to their
         ELSE arm and every family carrying the new status reads "a doctrine
         status this brief has not learned" — honest, but not what the reader
         needs. This check compares the three CASEs and fails the moment they
         disagree, so the new status has to be named where a person reads it.

    Neither is a data question, so neither belongs in
    scripts/bigquery/tests/SEAT_SURFACE_acceptance.sql, which asserts everything
    that IS one (and asserts, at C04/C05/C06, that no live row is currently
    falling through those ELSE arms).

HOW IT READS THE CUBE
    By EVALUATING it, not by regex. cube/schema/SeatRegister.js is JavaScript; a
    regex over it would be fooled by a dimension inside a comment and by a comment
    inside a dimension. The file is run in node with `cube` stubbed, and the
    resulting object is dumped as JSON — so what this check inspects is exactly
    what Cube itself would load.

EXIT CODES
    0  both checks pass
    1  a check failed (the offending columns / statuses are printed)
    2  the check could not run (node missing, bq failed) — never a silent pass

USAGE
    python3 scripts/bigquery/tests/check_seat_surface_labels.py
"""

import json
import os
import re
import shutil
import subprocess
import sys

# ---- Declared constants -----------------------------------------------------
PROJECT = "onyga-482313"
TABLE = "OI.T_FAMILY_SEAT_REGISTER"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CUBE_FILE = os.path.join(ROOT, "cube", "schema", "SeatRegister.js")
REGISTER_SQL = os.path.join(ROOT, "scripts", "bigquery", "views",
                            "V_FAMILY_SEAT_REGISTER.sql")
SURFACES = [
    os.path.join(ROOT, "scripts", "bigquery", "views", "V_DAILY_BRIEF.sql"),
    os.path.join(ROOT, "scripts", "bigquery", "views", "V_RUN_SUMMARY.sql"),
]
# Ori's node lives under nvm; PATH is not guaranteed inside a hook or a CI shell.
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


def cube_definition():
    """Load SeatRegister.js the way Cube would, and hand back its definition."""
    stub = (
        "let captured = null;"
        "global.cube = (name, def) => { captured = { name, def }; };"
        "require(%s);"
        "const d = captured.def;"
        "process.stdout.write(JSON.stringify({"
        "  name: captured.name,"
        "  sql: String(d.sql),"
        "  dimensions: Object.fromEntries("
        "    Object.entries(d.dimensions || {}).map(([k, v]) => [k, String(v.sql)])),"
        "  measures: Object.fromEntries("
        "    Object.entries(d.measures || {}).map(([k, v]) => [k, String(v.sql || '')])),"
        "}));"
    ) % json.dumps(CUBE_FILE)
    r = subprocess.run([node_binary(), "-e", stub], capture_output=True, text=True)
    if r.returncode != 0:
        die("node could not load %s:\n%s" % (CUBE_FILE, r.stderr.strip()))
    return json.loads(r.stdout)


def table_columns():
    sql = ("SELECT column_name FROM `%s.OI.INFORMATION_SCHEMA.COLUMNS` "
           "WHERE table_name = '%s' ORDER BY ordinal_position"
           % (PROJECT, TABLE.split(".", 1)[1]))
    r = subprocess.run(
        ["bq", "query", "--project_id=%s" % PROJECT, "--use_legacy_sql=false",
         "--nouse_cache", "--format=json", sql],
        capture_output=True, text=True)
    if r.returncode != 0:
        die("bq failed reading %s columns:\n%s" % (TABLE, r.stderr.strip()))
    return [row["column_name"] for row in json.loads(r.stdout)]


def statuses_the_register_can_emit():
    """Every literal the register can publish as doctrine_status: the arms of its CASE, AND every
    bare literal selected as the column in another branch of the UNION. The UNMAPPED block emits
    `'UNMAPPED' AS doctrine_status` with no CASE at all, and until 2026-08-23 this function read
    the CASE only — so a status the register really publishes was invisible to the check that
    exists to make every consumer learn it."""
    text = open(REGISTER_SQL).read()
    end = text.find("END AS doctrine_status")
    if end < 0:
        die("no `END AS doctrine_status` in %s — the register's CASE moved or was "
            "renamed; this check must be repointed rather than deleted" % REGISTER_SQL)
    start = text.rfind("CASE", 0, end)
    block = text[start:end]
    found = re.findall(r"(?:THEN|ELSE)\s+'([A-Za-z_]+)'", block)
    if not found:
        die("found the doctrine_status CASE but no literals in it — refusing to "
            "report a vacuous pass")
    bare = re.findall(r"'([A-Za-z_]+)'\s+AS\s+doctrine_status", text)
    return sorted(set(found) | set(bare))


def statuses_a_surface_names(path):
    """Every status each doctrine_status CASE in a surface view names explicitly.

    Returns a list of (case_ordinal, set_of_statuses) so a view carrying two such
    CASEs — the brief carries one for the action column and one for the sentence —
    is checked arm by arm rather than by their union.
    """
    text = open(path).read()
    out = []
    for i, m in enumerate(re.finditer(
            r"CASE\s+\w+\.doctrine_status(.*?)\bEND\b", text, re.S)):
        out.append((i, set(re.findall(r"WHEN\s+'([A-Za-z_]+)'", m.group(1)))))
    return out


def main():
    failures = []

    # ---- 1. a dimension for every column a person reads ---------------------
    definition = cube_definition()
    dims = definition["dimensions"]
    cols = table_columns()
    if not cols:
        die("%s reported no columns — refusing to report a vacuous pass" % TABLE)
    referenced = set()
    for expr in dims.values():
        referenced.update(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", expr))
    missing = [c for c in cols if c not in referenced]
    print("cube %s: %d dimensions, %d measures, over %d table columns"
          % (definition["name"], len(dims), len(definition["measures"]), len(cols)))
    if missing:
        failures.append(
            "SeatRegister.js has no dimension reading these columns of %s: %s"
            % (TABLE, ", ".join(missing)))
    if TABLE.split(".", 1)[1] not in definition["sql"]:
        failures.append("SeatRegister.js does not read %s — it reads: %s"
                        % (TABLE, definition["sql"]))

    # ---- 2. every label CASE has learned every status -----------------------
    known = statuses_the_register_can_emit()
    print("register can emit doctrine_status: %s" % ", ".join(known))
    for path in SURFACES:
        cases = statuses_a_surface_names(path)
        if not cases:
            failures.append("%s has no doctrine_status CASE at all — the SEATS "
                            "section is missing or was re-written another way"
                            % os.path.basename(path))
            continue
        for ordinal, named in cases:
            gap = [s for s in known if s not in named]
            if gap:
                failures.append(
                    "%s, doctrine_status CASE #%d does not name: %s"
                    % (os.path.basename(path), ordinal + 1, ", ".join(gap)))
        print("%s: %d doctrine_status CASE(s), each naming %s"
              % (os.path.basename(path), len(cases),
                 " / ".join(sorted(cases[0][1]))))

    if failures:
        print("\nFAIL")
        for f in failures:
            print("  - %s" % f)
        return 1
    print("\nPASS — every register column has a dimension; every label CASE has "
          "learned every status the register can emit")
    return 0


if __name__ == "__main__":
    sys.exit(main())
