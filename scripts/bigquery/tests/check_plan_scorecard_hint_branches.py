#!/usr/bin/env python3
"""Run FN_PLAN_SCORECARD's RULE_HINT on doctored copies of the plan table, one per branch.

WHY THIS EXISTS
    The hint's real input cannot reach most of its branches yet. On the plan
    history to 2026-10-01 no clock has 16 graded holds or 16 graded band rows (min_group_rows,
    Ori ruled 16 on 2026-10-02; the scenarios below are sized around it)
    (at most 9 and 2, read at 2026-10-31 when all 117 are graded; the band was
    4 there before it left out expired-clock releases), so every real reading
    is WAIT, and
    PLAN_SCORECARD_acceptance.sql can only test the hint's OUTPUT against its own
    published counts. This check runs the function's own arithmetic on inputs
    built to reach each branch: LOWER, RAISE, KEEP, NO_CLEAN_SIGNAL, the two
    "one group too small" WAITs (including 46 graded decisions with ONE band
    row, which must still WAIT), a rule change (decisions made under 1.5x while
    the latest night carries 2x) and a latest night with no rule recorded.
    Since the second follow-up (after commit 46ae335) it also runs the band's
    two exclusions: releases at 1.2x the bar whose hold clock had run out
    (hold_expired TRUE), and releases at 1.2x with no order on the last day. A
    lower multiplier would have held neither, so neither may count in band_rows.

HOW IT AVOIDS A SECOND COPY OF THE FUNCTION
    It reads scripts/bigquery/functions/FN_PLAN_SCORECARD.sql at run time, strips
    the comments, takes the body after `AS`, and points it at a temp table instead
    of FACT_PLAN_NEXT_WEEK. Nothing here restates a threshold or a sentence the
    function owns, except the sentence openings asserted below, which are the
    house's twin-of-the-words pattern (acceptance C08, C09).

THE DOCTORED INPUT
    Every live-plan row written under P-14c that has settled by 2026-10-31 and
    whose verdict is GOOD, LOSING, NO_SALE or ONE_ORDER is split by whether its
    window was GOOD once settled, computed the grader's way (orders >= 2, the
    floor DE_PLAN_CONFIG carries in every state, and gross profit per ad dollar
    >= family_bar over the same window). Rows from those two pools are turned
    into holds (verdict HELD_UNSETTLED), band releases (LAST_DAY_NOT_STRONG with
    a last day of 1.2x the bar, 1 order that day and the hold clock still
    running: hold_expired FALSE), expired-clock releases (the same with
    hold_expired TRUE), short-day releases (the same with 0 orders that day) or
    other releases (HOLD_EXPIRED). The outcome of each row is the real one; only
    the decision is doctored. Nothing is written outside the script's temp
    tables.

EXIT CODES
    0  every scenario returned the expected recommendation and sentence opening
    1  a scenario did not (each mismatch is printed)
    2  the check could not run (bq failed, or the function file did not parse)

USAGE
    python3 scripts/bigquery/tests/check_plan_scorecard_hint_branches.py [FUNCTION_FILE]
    FUNCTION_FILE defaults to the committed FN_PLAN_SCORECARD.sql; pass a doctored copy to
    prove the check fires (the negative control recorded in PLAN_SCORECARD_acceptance.sql).
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
FN_FILE = os.path.join(ROOT, "scripts", "bigquery", "functions", "FN_PLAN_SCORECARD.sql")
PLAN_TABLE = "`onyga-482313.OI.FACT_PLAN_NEXT_WEEK`"


def function_body(path):
    lines = [l for l in open(path).read().split("\n") if not l.lstrip().startswith("--")]
    text = "\n".join(lines)
    i = text.find("\nAS\nWITH k AS (")
    if i < 0:
        raise ValueError("could not find the function body (AS / WITH k AS) in " + path)
    return text[i + 4:].rstrip().rstrip(";")


HEADER = """DECLARE grade_date DATE DEFAULT DATE '2026-10-31';
CREATE TEMP TABLE base AS
SELECT p.* FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p
WHERE p.is_live_plan AND p.last_day_strong IS NOT NULL AND p.settle_due_on <= grade_date
  AND p.verdict IN ('GOOD', 'LOSING', 'NO_SALE', 'ONE_ORDER');
CREATE TEMP TABLE outc AS
SELECT b.as_of, b.campaign_id, b.keyword_id,
       (COALESCE(SUM(f.Ads_orders), 0) >= 2
        AND COALESCE(SAFE_DIVIDE(SUM(f.GROSS_PROFIT), NULLIF(SUM(f.Ads_cost), 0)), -1) >= b.family_bar) AS good
FROM base b
LEFT JOIN `onyga-482313.OI.FACT_AMAZON_ADS` f
  ON f.campaign_id = b.campaign_id AND f.keyword_id = b.keyword_id
 AND f.date BETWEEN b.window_from AND b.window_to AND f.date < grade_date
GROUP BY b.as_of, b.campaign_id, b.keyword_id, b.family_bar;
CREATE TEMP TABLE pool AS
SELECT b.*, o.good,
       ROW_NUMBER() OVER (PARTITION BY o.good ORDER BY b.as_of, b.campaign_id, b.keyword_id) AS ix
FROM base b JOIN outc o USING (as_of, campaign_id, keyword_id);
CREATE TEMP TABLE res (scen STRING, graded_rows INT64, held_rows INT64, held_rows_wrong INT64,
  band_rows INT64, band_released_wrong INT64, rule_value FLOAT64, rule_min_orders INT64,
  other_rule_rows INT64, min_group_rows INT64, recommendation STRING, sentence STRING);
"""


def held(good, lo, hi):
    return (f"SELECT * EXCEPT (good, ix) REPLACE ('HELD_UNSETTLED' AS verdict, CAST(NULL AS STRING) AS guard_released_by) "
            f"FROM pool WHERE good = {good} AND ix BETWEEN {lo} AND {hi}")


def band(good, lo, hi, hold_expired="FALSE", last_day_ord=1):
    return (f"SELECT * EXCEPT (good, ix) REPLACE ('LOSING' AS verdict, 'LAST_DAY_NOT_STRONG' AS guard_released_by, "
            f"family_bar * 1.2 AS last_day_ret, {hold_expired} AS hold_expired, {last_day_ord} AS last_day_ord) "
            f"FROM pool WHERE good = {good} AND ix BETWEEN {lo} AND {hi}")


def band_expired(good, lo, hi):
    # labelled LAST_DAY_NOT_STRONG at 1.2x, but the hold clock had run out: no lower multiplier holds it
    return band(good, lo, hi, hold_expired="TRUE")


def band_short_day(good, lo, hi):
    # at 1.2x with the clock running, but no order on the last day: no lower multiplier holds it
    return band(good, lo, hi, last_day_ord=0)


def other_release(lo, hi):
    return (f"SELECT * EXCEPT (good, ix) REPLACE ('LOSING' AS verdict, 'HOLD_EXPIRED' AS guard_released_by) "
            f"FROM pool WHERE good = FALSE AND ix BETWEEN {lo} AND {hi}")


def later_night(mult):
    m = "CAST(NULL AS FLOAT64)" if mult is None else repr(float(mult))
    o = "CAST(NULL AS INT64)" if mult is None else "1"
    return (f"SELECT * EXCEPT (good, ix) REPLACE (DATE '2026-10-02' AS as_of, 'GOOD' AS verdict, "
            f"CAST(NULL AS STRING) AS guard_released_by, DATE '2026-12-31' AS settle_due_on, "
            f"{m} AS strong_day_mult, {o} AS strong_day_min_orders) FROM pool WHERE good = TRUE AND ix = 1")


# scenario -> (input parts, expected recommendation, expected sentence opening or fragment)
SCENARIOS = {
    "S_RAISE": ([held("FALSE", 1, 16), band("FALSE", 17, 32)], "RAISE_STRONG_DAY_MULT",
                ("starts", "THE LAST-DAY BAR LOOKS TOO LOW from 16 keyword-nights held")),
    "S_LOWER": ([held("TRUE", 1, 16), band("TRUE", 17, 32)], "LOWER_STRONG_DAY_MULT",
                ("starts", "THE LAST-DAY BAR LOOKS TOO HIGH from 16 keyword-nights let through")),
    "S_KEEP": ([held("TRUE", 1, 16), band("FALSE", 1, 16)], "KEEP_STRONG_DAY_MULT",
               ("starts", "THE LAST-DAY BAR HOLDS from 16 held and 16 let through in the band")),
    "S_NOCLEAN": ([held("FALSE", 1, 16), band("TRUE", 1, 16)], "NO_CLEAN_SIGNAL",
                  ("starts", "NO CLEAN SIGNAL from 16 held and 16 let through in the band")),
    "S_HELD_SMALL": ([held("FALSE", 1, 15), band("FALSE", 16, 31), other_release(32, 46)], "WAIT",
                     ("starts", "WAIT: the held group is too small: 15 held of the 16 needed")),
    "S_BAND_SMALL": ([held("FALSE", 1, 16), band("FALSE", 17, 17), other_release(18, 46)], "WAIT",
                     ("starts", "WAIT: the band is too small: 1 let through in the band of the 16 needed")),
    "S_OTHER_RULE": ([held("FALSE", 1, 16), band("FALSE", 17, 32), later_night(2.0)], "WAIT",
                     ("starts", "WAIT: both groups this hint compares are too small: 0 held of the 16 needed, "
                                "and 0 let through in the band of the 16 needed")),
    "S_NULL_RULE": ([held("FALSE", 1, 16), band("FALSE", 17, 32), later_night(None)], "WAIT",
                    ("starts", "WAIT: the live plan's latest night (2026-10-02) carries no last-day rule")),
    # 24 good releases at 1.2x the bar whose hold clock had run out: counted in the band they would make it
    # 40 rows with 24 wrong and read LOWER; left out, the band is the 16 not-good ones and the hint KEEPs
    "S_BAND_EXPIRED": ([held("TRUE", 1, 16), band("FALSE", 1, 16), band_expired("TRUE", 17, 40)],
                       "KEEP_STRONG_DAY_MULT",
                       ("starts", "THE LAST-DAY BAR HOLDS from 16 held and 16 let through in the band")),
    # the same with the clock running but 0 orders on the last day (below the 1-order minimum)
    "S_BAND_SHORT_DAY": ([held("TRUE", 1, 16), band("FALSE", 1, 16), band_short_day("TRUE", 17, 40)],
                         "KEEP_STRONG_DAY_MULT",
                         ("starts", "THE LAST-DAY BAR HOLDS from 16 held and 16 let through in the band")),
}

# what each scenario's counts must read, so a branch is reached for the reason it names
EXPECT_COUNTS = {
    "S_RAISE": dict(held_rows=16, held_rows_wrong=16, band_rows=16, band_released_wrong=0),
    "S_LOWER": dict(held_rows=16, held_rows_wrong=0, band_rows=16, band_released_wrong=16),
    "S_KEEP": dict(held_rows=16, held_rows_wrong=0, band_rows=16, band_released_wrong=0),
    "S_NOCLEAN": dict(held_rows=16, held_rows_wrong=16, band_rows=16, band_released_wrong=16),
    "S_HELD_SMALL": dict(held_rows=15, band_rows=16, graded_rows=46),
    "S_BAND_SMALL": dict(held_rows=16, band_rows=1, graded_rows=46),
    "S_OTHER_RULE": dict(held_rows=0, band_rows=0, other_rule_rows=32, graded_rows=32),
    "S_NULL_RULE": dict(held_rows=0, band_rows=0, other_rule_rows=32, graded_rows=32),
    "S_BAND_EXPIRED": dict(held_rows=16, held_rows_wrong=0, band_rows=16, band_released_wrong=0, graded_rows=56),
    "S_BAND_SHORT_DAY": dict(held_rows=16, held_rows_wrong=0, band_rows=16, band_released_wrong=0, graded_rows=56),
}


def build_script(body):
    if PLAN_TABLE not in body:
        raise ValueError("the function body no longer reads " + PLAN_TABLE)
    out = HEADER
    for scen, (parts, _, _) in SCENARIOS.items():
        t = "fp_" + scen.lower()
        out += f"CREATE TEMP TABLE {t} AS\n" + "\nUNION ALL\n".join(parts) + ";\n"
        out += (f"INSERT INTO res SELECT '{scen}', graded_rows, held_rows, held_rows_wrong, band_rows, "
                f"band_released_wrong, rule_value, rule_min_orders, other_rule_rows, min_group_rows, "
                f"recommendation, sentence FROM (\n{body.replace(PLAN_TABLE, t)}\n) WHERE row_type = 'RULE_HINT';\n")
    out += "SELECT * FROM res ORDER BY scen;\n"
    return out


def main():
    try:
        script = build_script(function_body(sys.argv[1] if len(sys.argv) > 1 else FN_FILE))
        run = subprocess.run(["bq", "query", "--project_id=onyga-482313", "--use_legacy_sql=false",
                              "--nouse_cache", "--format=json"],
                             input=script, capture_output=True, text=True, timeout=900)
        if run.returncode != 0:
            print("bq failed:\n" + run.stdout[-2000:] + run.stderr[-2000:])
            return 2
        rows = json.loads(run.stdout)[-1]
    except Exception as e:  # never a silent pass
        print("could not run: %s" % e)
        return 2
    got = {r["scen"]: r for r in rows}
    bad = []
    for scen, (_, rec, (how, text)) in SCENARIOS.items():
        r = got.get(scen)
        if r is None:
            bad.append(f"{scen}: no RULE_HINT row")
            continue
        if r["recommendation"] != rec:
            bad.append(f"{scen}: recommendation {r['recommendation']}, expected {rec}")
        if not r["sentence"].startswith(text):
            bad.append(f"{scen}: sentence does not open with {text!r}: {r['sentence'][:160]!r}")
        for col, want in EXPECT_COUNTS[scen].items():
            if r.get(col) is None or int(r[col]) != want:
                bad.append(f"{scen}: {col} = {r.get(col)}, expected {want}")
        print(f"{scen:16s} {r['recommendation']:22s} graded {r['graded_rows']:>3s}  held {r['held_rows']}/{r['held_rows_wrong']} wrong  "
              f"band {r['band_rows']}/{r['band_released_wrong']} wrong  rule {r['rule_value']}  other {r['other_rule_rows']}")
    if bad:
        print("\nFAIL:\n  " + "\n  ".join(bad))
        return 1
    print("\nPASS: every branch of the hint returned what its doctored input demands.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
