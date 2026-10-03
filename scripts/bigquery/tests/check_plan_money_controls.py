#!/usr/bin/env python3
"""Run FACT_PLAN_NEXT_WEEK_acceptance.sql on the live plan and on doctored copies of it.

WHY THIS EXISTS
    The house rule is that every acceptance check has a negative control run on a temp copy, and
    that an empty input fails rather than passes. Piece-1 plan Task 4 (v27.158, 2026-10-02) restated
    C03, C04, C08, C11, C15 and C16 and added M1, M2 and M3 to the plan's acceptance (Ori's rulings
    R1 / R7 / R8 = spec P-15 / P-21 / P-22, audit fixes #11 #12 #15 #24). The table cannot be
    doctored, so this script runs the acceptance file's OWN text with two names swapped:
        `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`      -> a copy of the plan's latest two partitions
                                                      (C23 reads the earlier one), doctored per copy
        `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`   -> one snapshot of the judgement, read ONCE
    Each copy is ONE statement (bq prints the results of about 100 statements of a script, no more).
    Nothing here restates a check: a change to the acceptance file is what gets tested.

THE COPIES (doctored rows are chosen deterministically in the latest partition, live plan B)
    LIVE                        every check 0.
    NC_EMPTY                    no rows: C03, C04, C08, C15, C16, M1, M2, M3 read 1 (emptiness terms).
    NC_C03_POT_WITHOUT_HOLDOUT  one family's pot put back to v27.157's reading (GOOD outside the
                                holdout): C03 1.
    NC_C15_NOTGOOD_WITH_HOLDOUT one family's not-good side made to count its holdout not-good rows: C15 1.
    NC_M1_ABOVE_NOTGOOD         a family whose target is above its not-good side given v27.157's
                                allowance (the whole target): M1 1, C04 1.
    NC_C08_HOLDOUT_CAP_MOVED    one holdout row's cap delta set to +$5.00: C08 1.
    NC_C08_HOLDOUT_BASIS        one holdout row's basis set to RAMPED: C08 1.
    NC_C08_HOLDOUT_SILENT       one GOOD holdout row's sentence without "measurement control (HOLDOUT
                                from": C08 1.
    NC_C11_MOVED_UNDER_NEED     a RAMPED campaign's cap set to $1.00 (need above $1.01): C11 >= 1 (2 when
                                its good side alone is also above $1.00: the good-side term counts it too).
    NC_M2_RAMPED_OFF            a RAMPED campaign's cap and delta + $1.00: M2 1.
    NC_M2_FLOORED_OFF           a FLOORED_AT_NEED campaign's cap and delta + $1.00: M2 1 (0 when none).
    NC_M2_SENTENCE_SAYS_RAMP    a non-RAMPED moved cap's row saying "tonight the one-third ramp decided
                                it": M2 1 (0 when no such cap).
    NC_M3_SEAT_DROPPED          one seated row removed: M3 1.
    HC_M3_QUEUE_COUNTED         follow-up F9 (2026-10-03): the lowest-numbered queued non-PAUSE row
                                (queue_rn) INJECTED with $3.00 a day more window spend, and its family's
                                published figures restated to count it — expected_after_upload_per_day
                                + $3.00 x (planned bid / current bid, 1 with no planned bid), share_closed
                                recomputed from it (NULL stays NULL: no gap), and both printed figures
                                replaced in every row's sentence of that plan-B family: M3 0.
    NC_M3_QUEUE_DROPPED         the plan's control — that queued row removed from HC_M3_QUEUE_COUNTED:
                                M3 1. Until F9 it removed the row as published, and every queued row
                                the copy picked on 2026-10-02 and 2026-10-03 had bought nothing in the
                                window ($0.00 queue spend), so it read 0 and expected 0. With no queued
                                row, or a queued row the injection adds no money to: NOT EXERCISED, and
                                the script exits 1 (both copies).
    NC_M3_QUEUE_UNCOUNTED       that queued row given $3.00 a day more window spend than the published
                                expected figure counted: M3 1.
    NC_M3_SHARE_OFF             a family with a gap given share_closed + 0.10 on every live row: M3 >= 1
                                (the family term and every row whose sentence no longer matches; 0 when
                                no family has a gap).
    NC_M3_SENTENCE_SILENT       one row's sentence without "Expected after the upload: $": M3 1.
    NC_C16_STEP_WITHOUT_UPLOAD  one row with ramp_step 1 and no upload landed: C16 1.
    NC_C16_SENTENCE             one row whose family has no upload saying "Ramp: step 1": C16 1.
    HC_C16_UPLOADS_LANDED       one family given 2 landed uploads, ramp_step 2 and "Ramp: step 2 of 3"
                                on every row of both plans: C16 0.
    A copy's other checks are printed and not asserted: doctoring one row can trip another check.

EXIT CODES
    0  LIVE read 0 on every check and every copy read its expected value on its target check
    1  a copy did not (each mismatch is printed)
    2  the check could not run (bq failed, or the acceptance file did not parse)

USAGE
    python3 scripts/bigquery/tests/check_plan_money_controls.py [--judge-table PROJECT.DATASET.TABLE]
        [--build-judge-table PROJECT.DATASET.TABLE]
    --judge-table reads a snapshot of the judgement instead of the deployed view. Since v27.171 the
    acceptance reads it only for T1's click goal (a constant the view declares); C13 reads the
    judgement each night was BUILT ON, which SP_BUILD_NEXT_WEEK_PLAN v27.171 saves with the night:
        `onyga-482313.OI.T_PLAN_BUILD_JUDGMENT`    -> bjsnap (with --build-judge-table, a copy of it)
    LIVE (every check 0) holds on the real table at any hour once a night has been written by v27.171.
    Until then LIVE reads C13 1 (the latest night's judgement is not on record), F1 1 and F2 1
    (emptiness) and the script exits 1 whatever the copies read. Before v27.171, C13 read the live
    view, whose fence moves at Los Angeles midnight while a frozen night (v27.170) stays. Run on the
    real table 2026-10-03 18:47-19:02 UTC after the v27.171 deploy (job
    bqjob_r114f15b1e643729a_000001a103173577_1, 949,116.0 slot-seconds, 921.9 s, 2,296,381,440 bytes):
    exit 1 by LIVE alone — 39 readings, non-zero exactly C13 1, F1 1, F2 1 (the 10-03 night was
    written by v27.169) — and every copy read its expected value (28 assertions). The 2026-10-03
    11:52 UTC run of this script cost 120,513.8 slot-seconds; where the increase comes from was not
    measured.
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
ACC_FILE = os.path.join(ROOT, "scripts", "bigquery", "tests", "FACT_PLAN_NEXT_WEEK_acceptance.sql")
VIEW = "`onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`"
PLAN = "`onyga-482313.OI.FACT_PLAN_NEXT_WEEK`"
# v27.171 (learning piece 2 Task 3 follow-up 2): C13 reads the judgement each night was built on
BUILD_J = "`onyga-482313.OI.T_PLAN_BUILD_JUDGMENT`"


def acceptance_query():
    lines = [l for l in open(ACC_FILE).read().split("\n") if not l.startswith("--")]
    q = "\n".join(lines).strip().rstrip(";")
    if VIEW not in q or PLAN not in q or BUILD_J not in q:
        raise ValueError("the acceptance file no longer reads the plan table, the judgement view and the "
                         "saved judgement by name")
    return q.replace(VIEW, "jsnap").replace(PLAN, "__HH__").replace(BUILD_J, "bjsnap")


LIVE = "SELECT * EXCEPT (rn) FROM hbase"


def at(pick_col, **repl):
    """one row, chosen by a column of the pick table, doctored"""
    sets = ", ".join(f"IF(rn = (SELECT {pick_col} FROM pick), {v}, {k}) AS {k}" for k, v in repl.items())
    return f"SELECT * EXCEPT (rn) REPLACE ({sets}) FROM hbase"


def fam(fam_col, plans="('B')", **repl):
    """every row of one family in the latest partition (live plan B unless told otherwise), doctored"""
    cond = f"as_of = (SELECT mx FROM pick) AND plan IN {plans} AND family = (SELECT {fam_col} FROM pick)"
    sets = ", ".join(f"IF({cond}, {v}, {k}) AS {k}" for k, v in repl.items())
    return f"SELECT * EXCEPT (rn) REPLACE ({sets}) FROM hbase"


def camp(camp_col, **repl):
    """every live-plan row of one campaign in the latest partition, doctored"""
    cond = f"as_of = (SELECT mx FROM pick) AND plan = 'B' AND campaign_id = (SELECT {camp_col} FROM pick)"
    sets = ", ".join(f"IF({cond}, {v}, {k}) AS {k}" for k, v in repl.items())
    return f"SELECT * EXCEPT (rn) REPLACE ({sets}) FROM hbase"


def drop(pick_col):
    return f"SELECT * EXCEPT (rn) FROM hbase WHERE rn != COALESCE((SELECT {pick_col} FROM pick), -1)"


# follow-up F9: the plan-B rows of the injected queued row's family in the latest partition
QFAM = "as_of = (SELECT mx FROM pick) AND plan = 'B' AND family = (SELECT queue_fam FROM pick)"
EXP_FMT = "'Expected after the upload: $%.2f a day'"
SHARE_FMT = "'%.0f%% of the gap to the allowance target closes'"


def queue_counted():
    """the queued row queue_rn given $3.00 a day more window spend, and its family's expected figure,
    share_closed and sentences restated to count it (the injected values are in qinj); the REPLACE
    expressions read the row's published values, so each sentence swaps the old figures for the new.
    rn is kept: build_script materializes this as hq, and NC_M3_QUEUE_DROPPED drops queue_rn from it"""
    return ("SELECT * REPLACE ("
            "IF(rn = (SELECT queue_rn FROM pick), w_sp + 3.0 * window_days, w_sp) AS w_sp, "
            f"IF({QFAM}, (SELECT ex_new FROM qinj), expected_after_upload_per_day) AS expected_after_upload_per_day, "
            f"IF({QFAM}, (SELECT sh_new FROM qinj), share_closed) AS share_closed, "
            f"IF({QFAM}, REPLACE(IF(share_closed IS NULL, sentence, REPLACE(sentence, "
            f"FORMAT({SHARE_FMT}, 100 * share_closed), FORMAT({SHARE_FMT}, 100 * (SELECT sh_new FROM qinj)))), "
            f"FORMAT({EXP_FMT}, expected_after_upload_per_day), FORMAT({EXP_FMT}, (SELECT ex_new FROM qinj))), "
            "sentence) AS sentence) FROM hbase")


COPIES = {
    "LIVE": (LIVE, None),
    "NC_EMPTY": (f"{LIVE} WHERE FALSE",
                 [("C03", 1), ("C04", 1), ("C08", 1), ("C15", 1), ("C16", 1), ("M1", 1), ("M2", 1), ("M3", 1)]),
    "NC_C03_POT_WITHOUT_HOLDOUT": (fam("pot_fam", pot_per_day="(SELECT pot_fam_old FROM pick)"), ("C03", 1)),
    "NC_C15_NOTGOOD_WITH_HOLDOUT": (fam("ng_fam", notgood_today_per_day="notgood_today_per_day + (SELECT ng_fam_hold FROM pick)"),
                                    ("C15", 1)),
    "NC_M1_ABOVE_NOTGOOD": (fam("m1_fam", allowance_ramped_per_day="allowance_target_per_day"), [("M1", 1), ("C04", 1)]),
    "NC_C08_HOLDOUT_CAP_MOVED": (at("hold_rn", campaign_planned_budget_delta_per_day="5.0"), ("C08", 1)),
    "NC_C08_HOLDOUT_BASIS": (at("hold_rn", campaign_budget_basis="'RAMPED'"), ("C08", 1)),
    "NC_C08_HOLDOUT_SILENT": (at("hold_good_rn", sentence="REPLACE(sentence, 'measurement control (HOLDOUT from', 'measurement control (from')"),
                              ("C08", 1)),
    "NC_C11_MOVED_UNDER_NEED": (camp("ramped_cid", campaign_planned_budget="1.00",
                                     campaign_planned_budget_delta_per_day="1.00 - COALESCE(campaign_current_budget, 1.00)"),
                                ("C11", "GE1")),
    "NC_M2_RAMPED_OFF": (camp("ramped_cid", campaign_planned_budget="campaign_planned_budget + 1.00",
                              campaign_planned_budget_delta_per_day="campaign_planned_budget_delta_per_day + 1.00"),
                         ("M2", 1)),
    "NC_M2_FLOORED_OFF": (camp("floored_cid", campaign_planned_budget="campaign_planned_budget + 1.00",
                               campaign_planned_budget_delta_per_day="campaign_planned_budget_delta_per_day + 1.00"),
                          ("M2", "1_IF_FLOORED")),
    "NC_M2_SENTENCE_SAYS_RAMP": (at("other_moved_rn", sentence="CONCAT(sentence, ' — tonight the one-third ramp decided it')"),
                                 ("M2", "1_IF_OTHER_MOVED")),
    "NC_M3_SEAT_DROPPED": (drop("seat_rn"), ("M3", 1)),
    # follow-up F9: the queued row is injected with money before it is dropped. The injected copy is
    # materialized once (hq): inlined, its scalar subqueries are re-read wherever the file reads the
    # plan table, and the first run failed on BigQuery's stage limit at that copy
    "HC_M3_QUEUE_COUNTED": ("SELECT * EXCEPT (rn) FROM hq", ("M3", "0_IF_QUEUE_INJECTED")),
    "NC_M3_QUEUE_DROPPED": ("SELECT * EXCEPT (rn) FROM hq WHERE rn != COALESCE((SELECT queue_rn FROM pick), -1)",
                            ("M3", "1_IF_QUEUE_INJECTED")),
    "NC_M3_QUEUE_UNCOUNTED": (at("queue_rn", w_sp="w_sp + 3.0 * window_days"), ("M3", 1)),
    "NC_M3_SHARE_OFF": (fam("gap_fam", share_closed="share_closed + 0.10"), ("M3", "GE1_IF_GAP")),
    "NC_M3_SENTENCE_SILENT": (at("first_rn", sentence="REPLACE(sentence, 'Expected after the upload: $', 'Expected: $')"),
                              ("M3", 1)),
    "NC_C16_STEP_WITHOUT_UPLOAD": (at("no_upload_rn", ramp_step="1"), ("C16", 1)),
    "NC_C16_SENTENCE": (at("no_upload_rn", sentence="REPLACE(sentence, 'Ramp: no step taken yet', 'Ramp: step 1')"),
                        ("C16", 1)),
    "HC_C16_UPLOADS_LANDED": (fam("pot_fam", plans="('A', 'B')", plan_uploads_landed="2", ramp_step="LEAST(ramp_steps, 2)",
                                  sentence="REPLACE(sentence, 'Ramp: no step taken yet', 'Ramp: step 2 of 3')"),
                              ("C16", 0)),
}


def build_script(judge_source, build_judge_source=BUILD_J):
    acc = acceptance_query()
    latest = "(SELECT MAX(as_of) FROM hbase)"
    parts = [
        f"CREATE TEMP TABLE jsnap AS SELECT * FROM {judge_source};",
        f"CREATE TEMP TABLE bjsnap AS SELECT * FROM {build_judge_source};",
        # the latest two partitions: the acceptance reads the latest, and C23 the one before it
        "CREATE TEMP TABLE hbase AS SELECT *, ROW_NUMBER() OVER (ORDER BY as_of, plan, campaign_id, keyword_id) AS rn "
        f"FROM {PLAN} WHERE as_of >= (SELECT MAX(as_of) FROM {PLAN} WHERE as_of < (SELECT MAX(as_of) FROM {PLAN}));",
        "CREATE TEMP TABLE b0 AS SELECT * FROM hbase WHERE as_of = " + latest + " AND plan = 'B';",
        "CREATE TEMP TABLE capb AS SELECT campaign_id, MAX(campaign_budget_basis) basis, "
        "SUM(planned_spend_per_day) + SUM(IF(is_candidate AND seat_no IS NULL AND move != 'PAUSE', "
        "COALESCE(SAFE_DIVIDE(w_sp, window_days), 0), 0)) need, MAX(campaign_current_budget) cur "
        "FROM b0 GROUP BY 1;",
        "CREATE TEMP TABLE famb AS SELECT family, MAX(window_days) wd, "
        "SAFE_DIVIDE(SUM(IF(side = 'GOOD' AND COALESCE(holdout, FALSE), w_sp, 0)), MAX(window_days)) hold_good, "
        "SAFE_DIVIDE(SUM(IF(side = 'GOOD' AND NOT COALESCE(holdout, FALSE), w_sp, 0)), MAX(window_days)) good_out, "
        "SAFE_DIVIDE(SUM(IF(side = 'NOT_GOOD' AND COALESCE(holdout, FALSE), w_sp, 0)), MAX(window_days)) hold_ng, "
        "MAX(allowance_target_per_day) tgt, MAX(notgood_today_per_day) ng, MAX(share_closed) sh, "
        "MAX(expected_after_upload_per_day) ex "
        "FROM b0 GROUP BY 1;",
        "CREATE TEMP TABLE pick AS SELECT "
        f"{latest} AS mx, "
        "(SELECT MIN(family) FROM famb WHERE hold_good > 0.01) AS pot_fam, "
        "(SELECT good_out FROM famb WHERE family = (SELECT MIN(family) FROM famb WHERE hold_good > 0.01)) AS pot_fam_old, "
        "(SELECT MIN(family) FROM famb WHERE hold_ng > 0.01) AS ng_fam, "
        "(SELECT hold_ng FROM famb WHERE family = (SELECT MIN(family) FROM famb WHERE hold_ng > 0.01)) AS ng_fam_hold, "
        "(SELECT MIN(family) FROM famb WHERE tgt > ng + 0.01) AS m1_fam, "
        "(SELECT MIN(family) FROM famb WHERE sh IS NOT NULL) AS gap_fam, "
        "(SELECT MIN(rn) FROM b0 WHERE holdout) AS hold_rn, "
        "(SELECT MIN(rn) FROM b0 WHERE holdout AND side = 'GOOD') AS hold_good_rn, "
        "(SELECT MIN(campaign_id) FROM capb WHERE basis = 'RAMPED' AND need > 1.01) AS ramped_cid, "
        "(SELECT MIN(campaign_id) FROM capb WHERE basis = 'FLOORED_AT_NEED') AS floored_cid, "
        "(SELECT MIN(rn) FROM b0 WHERE campaign_budget_basis IN ('FLOORED_AT_NEED', 'BAND_SNAPPED_UP', "
        "   'BAND_SNAPPED_DOWN', 'FLOORED_AT_MINIMUM')) AS other_moved_rn, "
        "(SELECT MIN(rn) FROM b0 WHERE seat_no IS NOT NULL AND seat_cost_per_day > 0.01) AS seat_rn, "
        "(SELECT MIN(rn) FROM b0 WHERE is_candidate AND seat_no IS NULL AND move != 'PAUSE') AS queue_rn, "
        "(SELECT COALESCE(SAFE_DIVIDE(w_sp, window_days), 0) * COALESCE(SAFE_DIVIDE(planned_bid, NULLIF(current_bid, 0)), 1) "
        "   FROM b0 WHERE rn = (SELECT MIN(rn) FROM b0 WHERE is_candidate AND seat_no IS NULL AND move != 'PAUSE')) AS queue_rn_spend, "
        # follow-up F9: the queued row's family, and what $3.00 a day more window spend adds to its
        # expected figure (M3's recount: window spend per day x planned / current bid, 1 with none)
        "(SELECT family FROM b0 WHERE rn = (SELECT MIN(rn) FROM b0 WHERE is_candidate AND seat_no IS NULL AND move != 'PAUSE')) AS queue_fam, "
        "(SELECT 3.0 * COALESCE(SAFE_DIVIDE(planned_bid, NULLIF(current_bid, 0)), 1) "
        "   FROM b0 WHERE rn = (SELECT MIN(rn) FROM b0 WHERE is_candidate AND seat_no IS NULL AND move != 'PAUSE')) AS queue_add, "
        "(SELECT MIN(rn) FROM b0) AS first_rn, "
        "(SELECT MIN(rn) FROM b0 WHERE plan_uploads_landed = 0) AS no_upload_rn, "
        "(SELECT COUNTIF(STARTS_WITH(basis, 'NO_MOVE_HOLDOUT') AND need > cur + 0.005) FROM capb) AS holdout_caps_under_need;",
        # follow-up F9: the injected family's figures, published and restated (share as M3 states it:
        # recomputed only where the gap is above $0.005 a day, NULL otherwise)
        "CREATE TEMP TABLE qinj AS SELECT f.ex AS ex_old, f.ex + p.queue_add AS ex_new, f.sh AS sh_old, "
        "IF(f.ng - f.tgt > 0.005, (f.ng - (f.ex + p.queue_add)) / (f.ng - f.tgt), NULL) AS sh_new "
        "FROM famb f JOIN pick p ON f.family = p.queue_fam;",
        f"CREATE TEMP TABLE hq AS {queue_counted()};",
        # flat columns, not a JSON string: the row parser below reads objects with no nested braces
        "SELECT 'PICK' AS copy, p.*, q.* FROM pick p LEFT JOIN qinj q ON TRUE;",
    ]
    for name, (hsql, _) in COPIES.items():
        q = acc.replace("__HH__", f"({hsql})")
        parts.append(f"SELECT '{name}' AS copy, check_name, violations FROM (\n{q}\n);")
    return "\n".join(parts)


def main():
    judge_source = VIEW
    if "--judge-table" in sys.argv:
        judge_source = "`" + sys.argv[sys.argv.index("--judge-table") + 1] + "`"
    build_judge_source = BUILD_J
    if "--build-judge-table" in sys.argv:
        build_judge_source = "`" + sys.argv[sys.argv.index("--build-judge-table") + 1] + "`"
    try:
        script = build_script(judge_source, build_judge_source)
    except Exception as e:  # noqa: BLE001
        print("could not build the script:", e)
        return 2
    r = subprocess.run(["bq", "query", "--project_id=onyga-482313", "--use_legacy_sql=false", "--nouse_cache",
                        "--format=json", "--max_rows=1000", script], capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-3000:], r.stderr[-3000:])
        return 2
    if os.environ.get("PLAN_CONTROLS_RAW"):
        open(os.environ["PLAN_CONTROLS_RAW"], "w").write(r.stdout)
    # bq prints one JSON array per statement: parse the row objects, not the whole output
    rows = [json.loads(m) for m in re.findall(r'\{[^{}]*"copy":[^{}]*\}', r.stdout)]
    pick = next((x for x in rows if x.get("copy") == "PICK"), {})
    if not pick:
        print("the PICK row did not parse")
        return 2
    for k in ("queue_rn_spend", "queue_add"):
        pick[k] = float(pick[k]) if pick.get(k) is not None else None
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
    for name, (_, targets) in COPIES.items():
        if targets is None:
            continue
        if isinstance(targets, tuple):
            targets = [targets]
        for chk, want in targets:
            v = got.get((name, chk))
            if want == "1_IF_FLOORED":
                want = 1 if pick.get("floored_cid") else 0
            if want == "1_IF_OTHER_MOVED":
                want = 1 if pick.get("other_moved_rn") else 0
            # follow-up F9: a queued row the injection could not give money to is a control that did not run
            if want in ("0_IF_QUEUE_INJECTED", "1_IF_QUEUE_INJECTED"):
                want = int(want[0]) if (pick.get("queue_add") or 0) > 0.001 else "NOT EXERCISED"
            if want == "GE1_IF_GAP":
                want = "GE1" if pick.get("gap_fam") else 0
            ok = (v is not None and v >= 1) if want == "GE1" else (v == want)
            others = {k[1]: x for k, x in got.items()
                      if k[0] == name and k[1] not in [t[0] for t in targets] and x != live.get(k[1])}
            flag = "ok " if ok else "BAD"
            print(f"{flag} {name:28} {chk} = {v} (expected {want}); other checks that moved: {others or 'none'}")
            if not ok:
                bad.append((name, chk, v, want))
    if bad:
        print("MISMATCHES:", bad)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
