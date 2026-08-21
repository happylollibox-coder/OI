#!/usr/bin/env python3
"""Standing assertion: one keyword, one lever, one price, per day.

WHY THIS EXISTS
    Ori builds the Amazon bulksheet BY HAND, copying rows off the engine's
    daily list. If one keyword appears twice on that list at two prices, the
    bid the account actually gets is decided by which line the eye landed on
    first. That is not a reporting untidiness — it is an unowned bid.

    SP_ENGINE_PREFLIGHT already resolves every contention to a single surviving
    instruction and stamps its verdict onto FACT_ENGINE_PROPOSALS. The failure
    this file exists for is the OTHER half: a consumer that reads that table and
    never reads the verdict. V_DAILY_BRIEF did exactly that from the day both
    objects were born, printing every refused instruction beside the one that
    beat it, at its own price, with nothing on the row to say it had lost. The
    gate's own health check stayed green throughout — because it measures the
    gate's table, and the gate's table was fine.

    So this checks BOTH halves, and the second one is the point:

      1. THE JUDGEMENT — the exportable rows of the newest proposal snapshot
         carry one price per (campaign, key, lever). Catches a gate that failed
         to resolve a contention, or a verdict whose stamp never landed.
      2. THE SURFACE — V_DAILY_BRIEF's PLANNED section carries one price per
         (campaign, key, lever). Catches a reader that stopped applying the
         verdict. This is the one that would have caught the original defect,
         because on that day check 1 was clean and the list was not.

WHAT "EXPORTABLE" MEANS
      hold_source IS NULL AND COALESCE(verdict,'GO') != 'EXCLUDE'
    A veto-held row is not an instruction. An unstamped row fails OPEN into the
    plan, so this never goes quiet just because a procedure did not run.
    key   = the term text for NEGATE rows, the keyword id otherwise — the same
            key_id SP_ENGINE_PREFLIGHT partitions its contention on.
    lever = BID | BUDGET | NEGATE, from grain.
    price = COALESCE(suggested_bid, suggested_budget). NULL on negates, and
            COUNT(DISTINCT) ignores NULL, so a negate can never trip this.

    The deployed twin of check 1 is V_ENGINE_HEALTH's `plan_price_ambiguity`.
    Check 2 lives only here, because V_DAILY_BRIEF embeds a planning-ceiling
    view and must never be inlined into the health board.

EXIT CODES
    0  both checks pass
    1  at least one key carries two or more exportable prices  (failing check)
    2  a check could not be asked (no credentials, object missing, bq
       unavailable). Reported loudly and NOT counted as a pass.

USAGE
    python3 scripts/bigquery/check_one_price_per_key.py
    python3 scripts/bigquery/check_one_price_per_key.py --table OI.SOME_COPY
        Point check 1 at another table — how the negative test is run, against
        a deliberately broken copy of a real partition. Skips check 2.
    python3 scripts/bigquery/check_one_price_per_key.py --date 2026-08-20
        Ask check 1 about a specific snapshot instead of the newest one.
"""

import json
import subprocess
import sys

# ---- Declared constants -----------------------------------------------------
PROJECT = "onyga-482313"
DEFAULT_TABLE = "OI.FACT_ENGINE_PROPOSALS"
BRIEF = "OI.V_DAILY_BRIEF"
# How many offending keys to print in full before summarising the rest.
MAX_SHOWN = 20

# Check 1 — the judgement, on the proposal table every consumer reads.
JUDGEMENT_SQL = """
SELECT campaign_name, item, k, lever, n_prices, offers FROM (
  SELECT
    ANY_VALUE(campaign_name) AS campaign_name,
    ANY_VALUE(COALESCE(target_text, '')) AS item,
    IF(grain = 'NEGATE', CONCAT('term|', LOWER(TRIM(COALESCE(target_text, '')))),
       COALESCE(keyword_id, '')) AS k,
    CASE grain WHEN 'BUDGET' THEN 'BUDGET' WHEN 'NEGATE' THEN 'NEGATE' ELSE 'BID' END AS lever,
    COUNT(DISTINCT COALESCE(suggested_bid, suggested_budget)) AS n_prices,
    STRING_AGG(CONCAT(engine, ' $',
                      FORMAT('%.2f', COALESCE(suggested_bid, suggested_budget, 0))),
               ', ' ORDER BY engine) AS offers
  FROM `{project}.{table}`
  WHERE snapshot_date = {date_expr}
    AND hold_source IS NULL
    AND COALESCE(verdict, 'GO') != 'EXCLUDE'
  GROUP BY campaign_id, k, lever
)
WHERE n_prices > 1
ORDER BY campaign_name, item
"""

# Check 2 — the surface, on the list the bulksheet is actually copied from.
# The brief's uniform row shape carries keyword_id, item (the target text) and
# status (the grain), which is enough to rebuild the same key.
SURFACE_SQL = """
SELECT campaign_name, item, k, lever, n_prices, offers FROM (
  SELECT
    campaign_name,
    ANY_VALUE(COALESCE(item, '')) AS item,
    IF(status = 'NEGATE', CONCAT('term|', LOWER(TRIM(COALESCE(item, '')))),
       COALESCE(keyword_id, '')) AS k,
    CASE status WHEN 'BUDGET' THEN 'BUDGET' WHEN 'NEGATE' THEN 'NEGATE' ELSE 'BID' END AS lever,
    COUNT(DISTINCT to_value) AS n_prices,
    STRING_AGG(CONCAT(source, ' $', FORMAT('%.2f', COALESCE(to_value, 0))),
               ', ' ORDER BY source) AS offers
  FROM `{project}.{brief}`
  WHERE section = 'PLANNED'
  GROUP BY campaign_id, campaign_name, k, lever
)
WHERE n_prices > 1
ORDER BY campaign_name, item
"""


def query(sql):
    cmd = ["bq", "query", "--project_id=" + PROJECT, "--use_legacy_sql=false",
           "--nouse_cache", "--format=json", sql]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or "bq exited %d" % proc.returncode)
    out = proc.stdout.strip()
    return json.loads(out) if out else []


def report(label, rows):
    """Print one check's result. Returns True if it passed."""
    if not rows:
        print("  ok — every key carries at most one price")
        return True
    print("  %-44s %-32s %-7s %s" % ("CAMPAIGN", "ITEM", "LEVER", "COMPETING OFFERS"))
    for r in rows[:MAX_SHOWN]:
        print("  %-44s %-32s %-7s %s"
              % ((r["campaign_name"] or "")[:44], (r["item"] or r["k"])[:32],
                 r["lever"], r["offers"]))
    if len(rows) > MAX_SHOWN:
        print("  ... %d more" % (len(rows) - MAX_SHOWN))
    print("\nFAIL (%s): %d key(s) carry more than one price. A bulksheet built by hand off this "
          "list would send whichever row was read first." % (label, len(rows)), file=sys.stderr)
    return False


def main(argv):
    table, date = DEFAULT_TABLE, None
    i = 0
    while i < len(argv):
        if argv[i] == "--table" and i + 1 < len(argv):
            table = argv[i + 1]; i += 2
        elif argv[i] == "--date" and i + 1 < len(argv):
            date = argv[i + 1]; i += 2
        else:
            print("unrecognised argument: %s" % argv[i], file=sys.stderr)
            return 2

    probing = table != DEFAULT_TABLE
    date_expr = ("DATE('%s')" % date) if date else (
        "(SELECT MAX(snapshot_date) FROM `%s.%s`)" % (PROJECT, table))

    checks = [("the judgement", JUDGEMENT_SQL.format(project=PROJECT, table=table,
                                                    date_expr=date_expr),
               "%s.%s%s" % (PROJECT, table, (" @ " + date) if date else " (newest snapshot)"))]
    if not probing:
        checks.append(("the surface", SURFACE_SQL.format(project=PROJECT, brief=BRIEF),
                       "%s.%s PLANNED — the list the bulksheet is copied from" % (PROJECT, BRIEF)))

    failed = False
    for label, sql, where in checks:
        print("one price per (campaign, key, lever) — %s: %s" % (label, where))
        try:
            rows = query(sql)
        except (RuntimeError, ValueError) as exc:
            print("\nCOULD NOT ASK (%s): %s" % (label, exc), file=sys.stderr)
            print("This is not a pass. The assertion did not run.", file=sys.stderr)
            return 2
        if not report(label, rows):
            failed = True

    if failed:
        print("\nThe losing rows must be EXCLUDEd with their reason by SP_ENGINE_PREFLIGHT — "
              "never deleted — and every consumer of the proposal table must read the verdict.",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
