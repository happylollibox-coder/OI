#!/usr/bin/env python3
"""Run V_PLAN_WINDOW_JUDGMENT_acceptance.sql on the live judgement and on doctored copies.

WHY THIS EXISTS
    The house rule is that every acceptance check has a negative control run on a temp copy.
    The judge's memory checks (G1..G4, piece-1 plan Task 2, v27.156) and the two checks Task 2
    restated (C12, C22) read the judgement view AND the live plan's history. The deployed view
    cannot be pointed at a doctored history, so this script runs the acceptance file's OWN text
    with the names swapped for copies (each a subquery over a temp table, so that a copy is ONE
    statement: bq prints the results of about 100 statements of a script and no more):
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
  v27.157 (piece-1 plan Task 3, P-19 / P-20 / P-25). The judge's deployed definition is swapped too:
        `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS` -> vv  (the judge's row of it, or a doctored one)
    NC_P1_RAISED             a non-probe not-good row under the bar that P-19 did not label (its P-6
                             price was not a raise), priced at its current bid + $0.05: P1 1.
    NC_P1_COST_ABOVE_SPEND   the same row costed $0.01 a day above its window spend per day: P1 1.
    HC_P1_AT_BAR_RAISED      a non-probe not-good row AT OR ABOVE the bar raised by $0.05: P1 0.
    NC_P1_LABEL_DISHONEST    that at-bar row labelled P19_HELD_AT_CURRENT: P1 >= 1 (2 when it is a
                             candidate: the label term and the silent-sentence term both count it).
    NC_P1_SENTENCE_SILENT    a P-19 candidate whose sentence lost "(P-19, Ori 2026-10-02)": P1 1.
    NC_EMPTY_JUDGEMENT       no judgement rows at all: P1 1, P2 1, P3 1 (the emptiness terms).
    NC_P2_SWAPPED            two no-positive-score candidates of one family with different
                             rank_money_burned, the values swapped: P2 2.
    NC_P2_ORDER_BY_CLICKS    the definition's ORDER BY put back to v27.156's (score, then clicks): P2 1.
    NC_P3_OLD_FORMULA        a probe with a LIFT price put back to its v27.156 price and cost ($0.21,
                             $0.80 a day): P3 1.
    NC_P3_SENTENCE_SILENT    that probe's sentence without "PROBE_START bid": P3 1.
    NC_P3_NO_PRICE_SILENT    that probe's keyword renamed so LIFT holds no bid for it, label left at
                             P25: P3 1.
    HC_P3_NO_PRICE_SAID      the same, labelled P6_PROBE_NO_LIFT_PRICE, priced at repair_bid_p6, and
                             saying "no single PROBE_START bid": P3 0.
    NC_C08_UNDER_FLOOR       a not-good row whose current bid is at or above its floor, priced $0.05
                             under the floor: C08 1.
    NC_C08_SUBFLOOR_UNLABELLED  a row P-19 held under the floor, its label changed to P6_REPAIR: C08 1.
    NC_C18_PROMISE           a not-good non-candidate whose sentence promises a seat "at its current
                             price" (v27.156's regex, "at the repaired price", missed it): C18 1.
    A copy's other checks are printed and not asserted: doctoring one row can trip another check.
  v27.161 (piece-1 plan Task 7, audit fix #18: C02 restated to test the brand-defense DERIVATION). Two
  more sources are swapped, each by default for itself:
        `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` -> ec  (experiment_id, campaign_id; or a doctored copy)
        `onyga-482313.OI.FACT_KEYWORD_STATE`      -> ks  (the ladder snapshot C02's emptiness term reads)
    NC_C02_DOCTORED_NAME     one universe row's campaign_name given " (Brand Defense)": C02 1.
    HC_C02_PRODUCT_DEFENSE   the same row given " (Product Defense)" instead: C02 0 (product defense is
                             not brand defense; extending it is a ruling).
    NC_C02_STRATEGY          that row's campaign added to a BRAND_DEFENSE experiment in the copy of
                             DIM_EXPERIMENT_CAMPAIGN, its name untouched: C02 = the number of universe
                             rows of that campaign (every keyword of a defense campaign is out; the
                             first run expected 1 and read 9, the campaign's 9 rows).
    HC_C02_OTHER_STRATEGY    the same campaign added to a PRODUCT_DEFENSE experiment instead: C02 0.
    NC_C02_NO_POPULATION     an empty ladder snapshot (no defense keyword for the exclusion to act on):
                             C02 1 (the emptiness term). NC_EMPTY_JUDGEMENT now also expects C02 2
                             (no judgement row; and the population is read over the judgement's own
                             HARVEST families, so an empty judgement has none).
  v27.165 (piece-1 follow-up F3: C22 restated — a GRACE sentence states the anchored rule of its own
  run, no sentence says "ONE quiet window" / "ONE-WINDOW LIMIT", and no GRACE row reads 1):
    NC_C22_ONE_QUIET_WINDOW  the lowest GRACE row's rule put back to the v27.160 wording ("keeps the good
                             side for ONE quiet window (P-5), held, not cut: grace lasts N nightly
                             judgments from <date>, the night it was granted, through <date>"): C22 2
                             (the anchored rule missing, and the retired words present).
    NC_C22_WRONG_LENGTH      the lowest GRACE row whose run length differs from tonight's window states
                             tonight's window_days as its length: C22 1 (0 when no such row exists).
    NC_C22_NO_GRACE_ROW      every GRACE verdict made GOOD: C22 1 (the emptiness term).
    NC_EMPTY_JUDGEMENT now also expects C22 1, and NC_C22_NO_END_DATE expects 1 on every night (on a
    night with no GRACE row the emptiness term reads it).

EXIT CODES
    0  LIVE read 0 on every check and every copy read its expected value on its target check
    1  a copy did not (each mismatch is printed)
    2  the check could not run (bq failed, or the acceptance file did not parse)

USAGE (one BigQuery script job; v27.161: every copy INSERTs into one temp table and the last statement
reads it, so the job can be submitted asynchronously and collected with bq wait / bq head)
    python3 scripts/bigquery/tests/check_judge_memory_controls.py [--judge-table PROJECT.DATASET.TABLE]
    python3 scripts/bigquery/tests/check_judge_memory_controls.py --submit [--judge-table ...]
    python3 scripts/bigquery/tests/check_judge_memory_controls.py --collect JOB
    --judge-table reads a snapshot of the judgement instead of the deployed view (its extra
    columns are ignored; it must carry every column the view publishes). Without --submit or --collect
    the script submits, then polls (bq wait, 60 s a call, the status printed on each) and collects.
"""
import json
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
ACC_FILE = os.path.join(ROOT, "scripts", "bigquery", "tests", "V_PLAN_WINDOW_JUDGMENT_acceptance.sql")
VIEW = "`onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`"
PLAN = "`onyga-482313.OI.FACT_PLAN_NEXT_WEEK`"
DEFS = "`onyga-482313.OI.INFORMATION_SCHEMA.VIEWS`"
EXPC = "`onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN`"
KSTATE = "`onyga-482313.OI.FACT_KEYWORD_STATE`"
BQ = ["bq", "--project_id=onyga-482313"]


def acceptance_query():
    lines = [l for l in open(ACC_FILE).read().split("\n") if not l.startswith("--")]
    q = "\n".join(lines).strip().rstrip(";")
    if any(name not in q for name in (VIEW, PLAN, DEFS, EXPC, KSTATE)):
        raise ValueError("the acceptance file no longer reads the view, the plan table, the view definitions, "
                         "the experiment campaigns and the ladder snapshot by name")
    return (q.replace(VIEW, "__JJ__").replace(PLAN, "__HH__").replace(DEFS, "__VV__")
             .replace(EXPC, "__EC__").replace(KSTATE, "__KS__"))


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


def j_at(pick_col, **repl):
    """one row, chosen by a column of the pick table, doctored"""
    sets = ", ".join(f"IF(rn = (SELECT {pick_col} FROM pick), {v}, {k}) AS {k}" for k, v in repl.items())
    return f"SELECT * EXCEPT (rn) REPLACE ({sets}) FROM jbase"


V_LIVE = "SELECT * FROM vbase"
# v27.161: the sources C02 reads besides the judgement, each live unless a copy doctors it
EXTRA_LIVE = {"__EC__": f"SELECT experiment_id, campaign_id FROM {EXPC}", "__KS__": f"SELECT * FROM {KSTATE}"}


def ec_plus(strategy):
    """the experiment campaigns, plus the C02 row's campaign in the lowest experiment of `strategy`"""
    return (f"SELECT experiment_id, campaign_id FROM {EXPC} UNION ALL "
            "SELECT (SELECT MIN(experiment_id) FROM `onyga-482313.OI.DIM_EXPERIMENT` "
            f"WHERE strategy_id = '{strategy}'), (SELECT campaign_id FROM jbase WHERE rn = (SELECT c02_rn FROM pick))")

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
    # v27.165 (follow-up F3): C22 has an emptiness term, so a night with no GRACE row reads 1 here too
    "NC_C22_NO_END_DATE": (
        "SELECT * EXCEPT (rn) REPLACE (IF(rn = (SELECT grace_rn FROM pick), REPLACE(sentence, FORMAT('through %t', grace_ends_on), 'through then'), sentence) AS sentence) FROM jbase",
        H_LIVE, ("C22", 1)),
    # ---- v27.165 (piece-1 follow-up F3): the GRACE sentence states the anchored rule ----
    "NC_C22_ONE_QUIET_WINDOW": (
        j_at("grace_rn", sentence=(
            "REPLACE(sentence, FORMAT('keeps the good side, held, not cut (P-5): grace lasts %d nightly judgments "
            "(the window length in force when it was granted, %t) through %t', grace_window_days, grace_since, grace_ends_on), "
            "FORMAT('keeps the good side for ONE quiet window (P-5), held, not cut: grace lasts %d nightly judgments "
            "from %t, the night it was granted, through %t', grace_window_days, grace_since, grace_ends_on))")),
        H_LIVE, ("C22", "2_IF_GRACE")),
    "NC_C22_WRONG_LENGTH": (
        j_at("grace7_rn", sentence=(
            "REPLACE(sentence, FORMAT('grace lasts %d nightly judgments', grace_window_days), "
            "FORMAT('grace lasts %d nightly judgments', window_days))")),
        H_LIVE, ("C22", "1_IF_GRACE7")),
    "NC_C22_NO_GRACE_ROW": (
        "SELECT * EXCEPT (rn) REPLACE (IF(verdict = 'GRACE', 'GOOD', verdict) AS verdict) FROM jbase",
        H_LIVE, ("C22", 1)),
    # ---- v27.157 (piece-1 plan Task 3): P-19 / P-20 / P-25 ----
    "NC_P1_RAISED": (j_at("p1_rn", planned_bid="current_bid + 0.05"), H_LIVE, ("P1", 1)),
    "NC_P1_COST_ABOVE_SPEND": (j_at("p1_rn", seat_cost_per_day="w_sp / window_days + 0.01"), H_LIVE, ("P1", 1)),
    "HC_P1_AT_BAR_RAISED": (j_at("p1_bar_rn", planned_bid="current_bid + 0.05"), H_LIVE, ("P1", 0)),
    "NC_P1_LABEL_DISHONEST": (j_at("p1_bar_rn", planned_bid_basis="'P19_HELD_AT_CURRENT'"), H_LIVE, ("P1", "GE1")),
    "NC_P1_SENTENCE_SILENT": (j_at("p19c_rn", sentence="REPLACE(sentence, '(P-19, Ori 2026-10-02)', '')"), H_LIVE, ("P1", 1)),
    "NC_EMPTY_JUDGEMENT": (f"{J_LIVE} WHERE FALSE", H_LIVE, [("P1", 1), ("P2", 1), ("P3", 1), ("C02", 2), ("C22", 1)]),
    "NC_P2_SWAPPED": (
        "SELECT * EXCEPT (rn) REPLACE ("
        "CASE WHEN rn = (SELECT a_rn FROM p2pair) THEN (SELECT b_rmb FROM p2pair) "
        "     WHEN rn = (SELECT b_rn FROM p2pair) THEN (SELECT a_rmb FROM p2pair) "
        "     ELSE rank_money_burned END AS rank_money_burned) FROM jbase",
        H_LIVE, ("P2", 2)),
    "NC_P2_ORDER_BY_CLICKS": (J_LIVE, H_LIVE, ("P2", 1),
        r"SELECT table_name, REGEXP_REPLACE(view_definition, r'GREATEST\(f\.rank_score, 0\) DESC, f\.rank_money_burned DESC', 'f.rank_score DESC') AS view_definition FROM vbase"),
    "NC_P3_OLD_FORMULA": (j_at("p3_rn", planned_bid="0.21", seat_cost_per_day="0.8"), H_LIVE, ("P3", 1)),
    "NC_P3_SENTENCE_SILENT": (j_at("p3_rn", sentence="REPLACE(sentence, 'PROBE_START bid', 'probe bid')"), H_LIVE, ("P3", 1)),
    "NC_P3_NO_PRICE_SILENT": (j_at("p3_rn", keyword_id="'NC_P3'"), H_LIVE, ("P3", 1)),
    "HC_P3_NO_PRICE_SAID": (
        j_at("p3_rn", keyword_id="'NC_P3'", planned_bid_basis="'P6_PROBE_NO_LIFT_PRICE'",
             planned_bid="repair_bid_p6", sentence="CONCAT(sentence, ' LIFT holds no single PROBE_START bid.')"),
        H_LIVE, ("P3", 0)),
    "NC_C08_UNDER_FLOOR": (j_at("c08_rn", planned_bid="bid_floor - 0.05"), H_LIVE, ("C08", 1)),
    "NC_C08_SUBFLOOR_UNLABELLED": (j_at("sub_rn", planned_bid_basis="'P6_REPAIR'"), H_LIVE, ("C08", "1_IF_SUBFLOOR")),
    "NC_C18_PROMISE": (j_at("c18_rn", sentence="CONCAT(sentence, ' It competes for a seat at its current price.')"), H_LIVE, ("C18", 1)),
    # ---- v27.161 (piece-1 plan Task 7, audit fix #18): C02 tests the brand-defense derivation ----
    "NC_C02_DOCTORED_NAME": (j_at("c02_rn", campaign_name="CONCAT(COALESCE(campaign_name, ''), ' (Brand Defense)')"),
                             H_LIVE, ("C02", 1)),
    "HC_C02_PRODUCT_DEFENSE": (j_at("c02_rn", campaign_name="CONCAT(COALESCE(campaign_name, ''), ' (Product Defense)')"),
                               H_LIVE, ("C02", 0)),
    "NC_C02_STRATEGY": (J_LIVE, H_LIVE, ("C02", "C02_CAMPAIGN_ROWS"), V_LIVE, {"__EC__": ec_plus("BRAND_DEFENSE")}),
    "HC_C02_OTHER_STRATEGY": (J_LIVE, H_LIVE, ("C02", 0), V_LIVE, {"__EC__": ec_plus("PRODUCT_DEFENSE")}),
    "NC_C02_NO_POPULATION": (J_LIVE, H_LIVE, ("C02", 1), V_LIVE, {"__KS__": f"SELECT * FROM {KSTATE} WHERE FALSE"}),
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
        # v27.165 (F3): a GRACE row whose run length is not tonight's window length
        "(SELECT MIN(rn) FROM jbase WHERE verdict = 'GRACE' AND grace_window_days != window_days) AS grace7_rn, "
        "(SELECT MIN(rn) FROM jbase WHERE memory_cleared_by_gap IN ('GRACE', 'GRACE_AND_HOLD')) AS cleared_rn, "
        # v27.157: the rows Task 3's controls doctor
        "(SELECT MIN(rn) FROM jbase WHERE side_b = 'NOT_GOOD' AND NOT is_probe AND COALESCE(ret_corrected, 0) < family_bar "
        "   AND planned_bid IS NOT NULL AND w_sp > 0 AND planned_bid_basis = 'P6_REPAIR') AS p1_rn, "
        "(SELECT MIN(rn) FROM jbase WHERE side_b = 'NOT_GOOD' AND NOT is_probe AND ret_corrected >= family_bar "
        "   AND planned_bid IS NOT NULL) AS p1_bar_rn, "
        "(SELECT MIN(rn) FROM jbase WHERE is_candidate AND planned_bid_basis = 'P19_HELD_AT_CURRENT') AS p19c_rn, "
        "(SELECT MIN(rn) FROM jbase WHERE is_candidate AND is_probe AND planned_bid_basis = 'P25_LIFT_PROBE_START') AS p3_rn, "
        "(SELECT MIN(rn) FROM jbase WHERE side_b = 'NOT_GOOD' AND NOT is_probe AND bid_floor IS NOT NULL "
        "   AND current_bid >= bid_floor) AS c08_rn, "
        "(SELECT MIN(rn) FROM jbase WHERE side_b = 'NOT_GOOD' AND planned_bid_basis = 'P19_HELD_AT_CURRENT' "
        "   AND current_bid < bid_floor - 0.005) AS sub_rn, "
        "(SELECT MIN(rn) FROM jbase WHERE side_b = 'NOT_GOOD' AND NOT is_candidate) AS c18_rn, "
        # v27.161: the row C02's controls doctor (any universe row: LIVE C02 0 means none is defense)
        "(SELECT MIN(rn) FROM jbase) AS c02_rn;",
        # NC_P2's pair: the lowest-numbered candidate with no positive score whose family holds another
        # one with a different rank_money_burned, and the lowest-numbered such other one
        "CREATE TEMP TABLE p2pair AS "
        "WITH z AS (SELECT rn, family, rank_money_burned AS rmb FROM jbase WHERE is_candidate AND rank_score <= 0), "
        "a AS (SELECT z1.* FROM z z1 WHERE EXISTS (SELECT 1 FROM z z2 WHERE z2.family = z1.family "
        "      AND ABS(z2.rmb - z1.rmb) > 1e-6) ORDER BY z1.rn LIMIT 1), "
        "b AS (SELECT z.* FROM z JOIN a ON z.family = a.family AND ABS(z.rmb - a.rmb) > 1e-6 ORDER BY z.rn LIMIT 1) "
        "SELECT a.rn AS a_rn, a.rmb AS a_rmb, b.rn AS b_rn, b.rmb AS b_rmb FROM a CROSS JOIN b;",
        "CREATE TEMP TABLE vbase AS SELECT table_name, view_definition "
        f"FROM {DEFS} WHERE table_name = 'V_PLAN_WINDOW_JUDGMENT';",
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
        # v27.161: every copy INSERTs into res and the LAST statement reads it, so the parent job's
        # result is the whole run (bq head -j) and the job can be submitted asynchronously
        "CREATE TEMP TABLE res (copy STRING, check_name STRING, violations INT64, detail STRING);",
        "INSERT INTO res SELECT 'PICK', 'PICK', 0, TO_JSON_STRING(STRUCT("
        "(SELECT held_rn FROM pick) AS held_rn, (SELECT grace_rn FROM pick) AS grace_rn, "
        "(SELECT grace7_rn FROM pick) AS grace7_rn, "
        "(SELECT cleared_rn FROM pick) AS cleared_rn, (SELECT k FROM g4key) AS g4key, "
        "(SELECT p1_rn FROM pick) AS p1_rn, (SELECT p1_bar_rn FROM pick) AS p1_bar_rn, "
        "(SELECT p19c_rn FROM pick) AS p19c_rn, (SELECT p3_rn FROM pick) AS p3_rn, "
        "(SELECT c08_rn FROM pick) AS c08_rn, (SELECT sub_rn FROM pick) AS sub_rn, "
        "(SELECT c18_rn FROM pick) AS c18_rn, (SELECT a_rn FROM p2pair) AS p2_a_rn, "
        "(SELECT b_rn FROM p2pair) AS p2_b_rn, (SELECT COUNT(*) FROM vbase) AS view_defs, "
        "(SELECT c02_rn FROM pick) AS c02_rn, "
        "(SELECT campaign_id FROM jbase WHERE rn = (SELECT c02_rn FROM pick)) AS c02_campaign_id, "
        # the strategy controls make every universe row of that campaign defense, not one row
        "(SELECT COUNT(*) FROM jbase WHERE campaign_id = (SELECT campaign_id FROM jbase "
        "  WHERE rn = (SELECT c02_rn FROM pick))) AS c02_campaign_rows));",
    ]
    for name, spec in COPIES.items():
        jsql, hsql = spec[0], spec[1]
        vsql = spec[3] if len(spec) > 3 else V_LIVE
        extra = {**EXTRA_LIVE, **(spec[4] if len(spec) > 4 else {})}
        # ONE statement per copy: the copies are inlined as subqueries (v27.157: bq printed the
        # results of at most about 100 statements of a script; from v27.161 nothing is printed per
        # statement, but a copy stays one INSERT)
        q = acc.replace("__JJ__", f"({jsql})").replace("__HH__", f"({hsql})").replace("__VV__", f"({vsql})")
        for token, sql in extra.items():
            q = q.replace(token, f"({sql})")
        parts.append(f"INSERT INTO res SELECT '{name}', check_name, violations, CAST(NULL AS STRING) FROM (\n{q}\n);")
    parts.append("SELECT copy, check_name, violations, detail FROM res ORDER BY copy, check_name;")
    return "\n".join(parts)


def run(args, timeout=None):
    return subprocess.run(BQ + args, capture_output=True, text=True, timeout=timeout)


def submit(judge_source):
    try:
        script = build_script(judge_source)
    except Exception as e:  # noqa: BLE001
        print("could not build the script:", e)
        return None, 2
    if os.environ.get("JUDGE_CONTROLS_SQL"):
        open(os.environ["JUDGE_CONTROLS_SQL"], "w").write(script)
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
    if os.environ.get("JUDGE_CONTROLS_RAW"):
        open(os.environ["JUDGE_CONTROLS_RAW"], "w").write(r.stdout)
    rows = json.loads(r.stdout)
    print(f"job {job}: {slot_s:,.1f} slot-seconds, {len(rows)} result rows")
    pick = next((json.loads(x["detail"]) for x in rows if x.get("copy") == "PICK"), {})
    if not pick:
        print("the PICK row did not parse")
        return 2
    print("doctored rows:", pick)
    got = {}
    for x in rows:
        if x.get("copy") != "PICK":
            got[(x["copy"], x["check_name"][:3].strip())] = int(x["violations"])
    bad = []
    live = {k[1]: v for k, v in got.items() if k[0] == "LIVE"}
    print("LIVE:", len(live), "checks;", "non-zero:", {k: v for k, v in live.items() if v} or "none")
    if not live or any(live.values()):
        bad.append(("LIVE", "every check 0", live))
    for name, spec in COPIES.items():
        targets = spec[2]
        if targets is None:
            continue
        if isinstance(targets, tuple):
            targets = [targets]
        for chk, want in targets:
            v = got.get((name, chk))
            if want == "1_IF_CLEARED":
                want = 1 if pick.get("cleared_rn") else 0
            if want == "1_IF_GRACE":
                want = 1 if pick.get("grace_rn") else 0
            # v27.165 (F3): with no GRACE row, C22's emptiness term reads 1 on every copy
            if want == "2_IF_GRACE":
                want = 2 if pick.get("grace_rn") else 1
            if want == "1_IF_GRACE7":
                want = 1 if (pick.get("grace7_rn") or not pick.get("grace_rn")) else 0
            if want == "1_IF_SUBFLOOR":
                want = 1 if pick.get("sub_rn") else 0
            if want == "C02_CAMPAIGN_ROWS":
                want = int(pick.get("c02_campaign_rows") or 0) or "NOT EXERCISED"
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


def main():
    judge_source = VIEW
    if "--judge-table" in sys.argv:
        judge_source = "`" + sys.argv[sys.argv.index("--judge-table") + 1] + "`"
    if "--collect" in sys.argv:
        return collect(sys.argv[sys.argv.index("--collect") + 1])
    job, rc = submit(judge_source)
    if rc or "--submit" in sys.argv:
        return rc
    return collect(job)


if __name__ == "__main__":
    sys.exit(main())
