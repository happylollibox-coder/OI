#!/usr/bin/env python3
"""Standing alarm: no view body may creep up on BigQuery's hard ceiling again.

WHY THIS EXISTS
    V_KEYWORD_LIFT reached 99.78% of BigQuery's view-body ceiling before anyone
    noticed, because nothing measured it. At that point the next change to the
    file is not "a change" — it is a migration. The alarm has to fire while
    there is still room to act, which means well below 100%.

WHAT IT MEASURES
    The number of CHARACTERS BigQuery will store as the view body, which is:
      1. the file with every line that starts at column 0 with `--` removed,
         because that is exactly what the deploy pipeline strips:
             bq query ... "$(grep -v '^--' FILE)"
      2. minus the `CREATE OR REPLACE VIEW ... AS` prefix and the trailing `;`,
         because BigQuery stores only the query text after AS.

    Two traps this deliberately avoids:
      * CHARACTERS, NOT BYTES. `wc -c` counts bytes. These files carry a few
        thousand non-ASCII characters in their commentary, so a byte count
        overstates the body and a naive check disagrees with BigQuery.
      * Comment lines that are INDENTED still count. Only a `--` in column 0 is
        free, because only that is what the deploy grep removes. An indented
        comment is shipped to BigQuery and charged against the ceiling.

    Cross-check the numbers this prints against reality with:
      SELECT table_name, LENGTH(view_definition)
      FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS`

EXIT CODES
    0  every view at or below AMBER_SHARE
    1  at least one view above RED_SHARE   (failing check)
    2  at least one view above AMBER_SHARE (warning; --strict makes this fail)

USAGE
    python3 scripts/bigquery/check_view_body_size.py [--strict] [PATH ...]
"""

import glob
import os
import sys

# ---- Declared constants -----------------------------------------------------
# BigQuery's hard maximum length of a view's query text, in characters.
CEILING_CHARS = 262_144
# Fire early enough that a fix is still an edit rather than a migration.
AMBER_SHARE = 0.70   # "start factoring"
RED_SHARE = 0.85     # "do not add to this file"

DEFAULT_GLOBS = [
    "scripts/bigquery/views/*.sql",
    "scripts/bigquery/interface_views/*.sql",
]


def stored_body_chars(path):
    """Characters BigQuery will store for this file's view, or None if not a view."""
    with open(path, encoding="utf-8") as fh:
        text = fh.read()

    # 1. what the deploy pipeline sends: `grep -v '^--'`
    sent = "\n".join(ln for ln in text.split("\n") if not ln.startswith("--"))

    # 2. what BigQuery keeps: everything after the `... AS` of the CREATE
    upper = sent.upper()
    at = upper.find("CREATE OR REPLACE VIEW")
    if at < 0:
        at = upper.find("CREATE VIEW")
    if at < 0:
        return None
    nl = sent.find("\n", at)
    if nl < 0:
        return None
    head, body = sent[at:nl], sent[nl + 1:]
    if not head.rstrip().upper().endswith(" AS"):
        # `AS` on its own line, or an OPTIONS(...) block: fall back to the token.
        marker = upper.find("\nAS\n", at)
        if marker < 0:
            return None
        body = sent[marker + 4:]

    return len(body.strip().rstrip(";").rstrip())


def main(argv):
    strict = "--strict" in argv
    args = [a for a in argv if not a.startswith("--")]

    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    explicit = bool(args)
    if explicit:
        paths = args
    else:
        paths = []
        for pattern in DEFAULT_GLOBS:
            paths.extend(sorted(glob.glob(os.path.join(root, pattern))))

    rows = []
    for path in paths:
        # Backups are noise when sweeping the tree, but an explicitly named path is
        # always measured — otherwise "check this file" can silently check nothing.
        if not explicit and (path.endswith(".bak") or ".bak." in os.path.basename(path)):
            continue
        try:
            chars = stored_body_chars(path)
        except (OSError, UnicodeDecodeError) as exc:
            print("SKIP  %s (%s)" % (path, exc), file=sys.stderr)
            continue
        if chars is None:
            continue
        rows.append((chars, os.path.basename(path)))

    rows.sort(reverse=True)

    red = [r for r in rows if r[0] > CEILING_CHARS * RED_SHARE]
    amber = [r for r in rows if CEILING_CHARS * AMBER_SHARE < r[0] <= CEILING_CHARS * RED_SHARE]

    print("view body vs BigQuery ceiling of %s characters "
          "(amber %.0f%%, red %.0f%%)" % (f"{CEILING_CHARS:,}", AMBER_SHARE * 100, RED_SHARE * 100))
    print("%-9s %-12s %8s  %s" % ("STATUS", "SHARE", "CHARS", "VIEW"))
    for chars, name in rows[:20]:
        share = chars / CEILING_CHARS
        status = "RED" if share > RED_SHARE else "AMBER" if share > AMBER_SHARE else "ok"
        print("%-9s %11.2f%% %8d  %s" % (status, share * 100, chars, name))
    if len(rows) > 20:
        print("... %d more, all below amber" % (len(rows) - 20))

    if red:
        print("\nFAIL: %d view(s) above %.0f%% of the ceiling. Do not add to them; "
              "move commentary to column 0 or factor the body." % (len(red), RED_SHARE * 100),
              file=sys.stderr)
        return 1
    if amber:
        print("\nWARN: %d view(s) above %.0f%% of the ceiling." % (len(amber), AMBER_SHARE * 100),
              file=sys.stderr)
        return 1 if strict else 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
