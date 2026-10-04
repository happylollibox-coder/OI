#!/usr/bin/env python3
"""Run the grader's own text on copies, and PREDICTION_CONTRACT_acceptance.sql's C statement on what
each copy graded — the parts of the learning contract (spec §11) that need a grader RUN.

WHY THIS EXISTS
    Learning-contract piece 2, plan Task 7 (docs/superpowers/plans/2026-10-03-learning-piece2-ledger-
    grader.md). The acceptance file checks the grade table's RECORD (C2-C4, F, P) and never runs the
    grader. Three guarantees need runs: a grader re-run inserts zero rows and a regrade_from run
    re-grades exactly the named band (spec §11 check 3); three fabricated predictions under
    predictor = 'FIXTURE' grade RIGHT, WRONG and INCONCLUSIVE and stay out of every aggregate (check
    5); and the grader on FN_PLAN_SCORECARD's clock agrees with FN_PLAN_SCORECARD to the cent (ruling
    D5's parity, which on the live record compares nothing yet: every stored night was written after
    Los Angeles midnight of its as_of, so its horizon starts a day after FN's window — the
    acceptance's P2 header). FACT_PREDICTION_GRADE is append-only (house rule), so nothing here writes
    it: every run is on a copy.
    A copy is scripts/bigquery/procedures/SP_GRADE_PREDICTIONS.sql with its comment lines stripped
    and only these names swapped (asserted present before the swap, absent after it):
        `onyga-482313.OI.SP_GRADE_PREDICTIONS`   -> `onyga-482313.OI._tmp_t7c_sp` (or _sp_ng, below)
        `onyga-482313.OI.FACT_PREDICTION_GRADE`  -> `onyga-482313.OI._tmp_t7c_grade` (CREATE ... LIKE the
                                                    real table, then loaded from it per copy)
        `onyga-482313.OI.T_PREDICTION_SCORECARD` -> `onyga-482313.OI._tmp_t7c_sc`
        `onyga-482313.OI.V_PREDICTION_LEDGER`    -> `onyga-482313.OI._tmp_t7c_led` (the view read ONCE
                                                    into _tmp_t7c_led_base, then per copy)
        `onyga-482313.OI.FACT_AMAZON_ADS`        -> `onyga-482313.OI._tmp_t7c_ads` (the seven columns the
                                                    grader reads, every day from the ledger's earliest
                                                    horizon_from, so the house watermark is the same;
                                                    plus the fixtures' outcome rows)
    Everything else the grader reads is read live (DE_COACH_THRESHOLDS, the change log, DIM_KEYWORD,
    DIM_CAMPAIGN, FACT_KEYWORD_STATE_HISTORY). Before submitting, the script checks that the DEPLOYED
    SP_GRADE_PREDICTIONS body equals the file's (whitespace-normalised), so the copy is the grader
    that runs. One script job; each copy is one CALL of the copy (the grader's temp tables are
    dropped after each CALL: they outlive a CALL inside a script). The acceptance file's own C
    statement (c_out), its fd function, its wmx (the house watermark) and fnr (FN_PLAN_SCORECARD at
    today's two clocks) statements are cut out of the file and run as written on labelled inputs
    (cm, cg, cl, cf, ch, cc), so nothing here restates a check of the file. The scratch objects are
    dropped at the end (and expire after a day if a run dies first; --cleanup drops them).

THE COPIES (copy: what was run; the readings asserted). C2..P2n are the acceptance's checks run on the
copy's grades; C3f, C3i, C3n, C5x are this script's.
    RERUN            the real grades without the latest graded night (rerun_night), then two runs
                     (NULL, NULL): C3f 0 (the first run inserted exactly the predictions removed),
                     C3i 0 (the second run inserted 0 rows); C2, C3, C4a, C4b, F, P1, P2, C5z 0; C8c 0.
    NC_NOGUARD       the plan's control for "a re-run inserts 0": the grader with its graded-once
                     guard (the `AND (c.predictor IS NULL OR (regrade_from IS NOT NULL AND l.as_of >=
                     regrade_from))` of _due) removed, run on the real grades: C3i >= 1, C3 >= 1.
    BASE             the real grades and ledger, one run: C3i 0 (the live record re-run); C2, C3, C4a,
                     C4b, F, P1, C5z 0; its report card is the one C5x compares with.
    REGRADE          the real grades, a run (rg_from, a reason), rg_from = the third most recent
                     graded night: C3n 0 — every current grade of the nights >= rg_from has exactly one
                     row from the run, regrade_seq one higher, the reason on it, and no other
                     prediction has a row from it (+1 when the band is empty, +1 when no night is
                     outside it); C2, C3, C4a, C4b, F, P1 0.
    NC_REGRADE_LOST  the run's first row (key order) removed: C3n >= 1, C3 >= 1.
    NC_REGRADE_OUTSIDE  the current grade of the first prediction of a night before rg_from re-graded
                     in the run too: C3n >= 1, C3 >= 1.
    FIX              the real grades; the ledger with 34 fixture predictions x 2 scenarios under
                     predictor 'FIXTURE' (family FIXTURE, as_of 2026-08-20, horizon 08-21 .. 08-23,
                     min_orders 1, family_bar 0.5, built from the first plan-B ledger row's columns),
                     their outcomes in the ads copy on 08-21; one run. FIXTURE_RIGHT (side called
                     GOOD, settled GOOD, 12 clicks), FIXTURE_WRONG (GOOD, settled not good, 12),
                     FIXTURE_INCONCLUSIVE (GOOD, not good, 3 clicks: below the line), and the rows that
                     put the line at 6 clicks under the live bar (MIN_INVEST_SIDE_ACCURACY 0.80,
                     MIN_INVEST_MIN_ROWS 20): FIXTURE_RIGHT_01..20 (GOOD, GOOD, 10 clicks),
                     FIXTURE_INCONCLUSIVE_01..10 (GOOD, not good, 2 clicks: floor 1 reads 210 / 330 =
                     0.636, floor 6 reads 210 / 220 = 0.955 over 22 rows) and FIXTURE_INCONCLUSIVE_DARK
                     (no click). Readings: C5 0 (every fixture reads the label its keyword names, the
                     three named ones on both scenarios), C4a 0, C4b 0 (both arms: RIGHT / WRONG at or
                     above the line, INCONCLUSIVE with clicks below it), C2, C3, F, P1 0, C3f 0 (68
                     inserted), C5z >= 1 (the fixtures are in the copy's grades), C5x 0 (its report
                     card equals BASE's, every column but scored_at, floats within 1e-6: the fixtures
                     are in no aggregate).
    NC_FIX_FLIP      FIXTURE_RIGHT's current grades relabelled WRONG: C5 >= 1.
    NC_FIX_LINE      FIXTURE_INCONCLUSIVE given a line at its own clicks: C4b >= 1.
    NC_FIX_MISSING   FIXTURE_WRONG's grades removed: C5 >= 1, C2 >= 1.
    NC_FIXB          the same fixtures under predictor PLAN_B, one run: C5x >= 1.
    NC_CARD_EMPTY    an empty card against BASE's: C5x >= 1.
    FNCLK            the real grades without fn_night (the latest FN FAMILY_WEEK night the grade table
                     grades), the ledger with that night's horizon set to FN's window (as_of .. as_of +
                     window_days - 1); one run: P1 0, P2 0, P2n >= 1 (the grader's own numbers, on FN's
                     clock, equal FN's allocation, realised net, net at realised returns and unrealised
                     allocation within a cent), C3f 0, C2, C3, C4a, F 0.
    NC_FNCLK_DOC     the same against FN with its first FAMILY_WEEK row of fn_night given
                     net_at_realized_a + 0.02: P2 >= 1.
    INPUTS           WM 0: the ads copy's house watermark equals FACT_AMAZON_ADS's.
    The board is not read (ch is empty): C8a and C8b are the live suite's. A copy's other readings are
    printed and not asserted. NOT EXERCISED: rerun_night, fn_night or rg_from NULL (nothing to copy);
    reported, and the script exits 1.

EXIT CODES
    0  every asserted reading held
    1  one did not, a copy was not exercised, or the deployed grader is not the file's
    2  the check could not run (bq failed, the file texts were not found)
    3  --collect: the job is still running (poll it with bq wait JOB 60, then collect again)

USAGE
    python3 scripts/bigquery/tests/check_prediction_contract_controls.py --submit
        prints JOB=<id>; poll with `bq wait --project_id=onyga-482313 <id> 60`, one call at a time
    python3 scripts/bigquery/tests/check_prediction_contract_controls.py --collect JOB
    python3 scripts/bigquery/tests/check_prediction_contract_controls.py --cleanup
    PREDICTION_CONTROLS_SQL=/path writes the script it submits.

RUN RECORD (each entry dated; the numbers are the run's)
    2026-10-04 00:47-01:01 UTC (Task 7), job bqjob_r68f8c321bb6f68ea_000001a104611486_1, 632 child
    jobs, 1,972.1 slot-seconds, 1,582,040,784 bytes processed (6,598,688,768 billed), 853 s: exit 0,
    every asserted reading held. Picks: rerun_night = fn_night = 2026-08-28 (1,492 predictions),
    rg_from 2026-08-26, watermark 2026-10-02. RERUN C3f 0 (1,492 inserted), C3i 0; NC_NOGUARD C3i
    8,944, C3 8,944; BASE C3i 0; REGRADE C3n 0 (4,476 re-graded); NC_REGRADE_LOST C3n 1, C3 1;
    NC_REGRADE_OUTSIDE C3n 1, C3 4,467; FIX C5 0, C4b 0, C5x 0 (357 card rows equal), C3f 0 (68
    inserted), fixture line 6 on every fixture row, labels RIGHT 42, WRONG 2, INCONCLUSIVE 24;
    NC_FIX_FLIP C5 2; NC_FIX_LINE C4b 2; NC_FIX_MISSING C5 2, C2 2; NC_FIXB C5x 67 (402 card rows);
    NC_CARD_EMPTY C5x 357; FNCLK P1 0, P2 0, P2n 4, C3f 0 (1,492); NC_FNCLK_DOC P2 1; INPUTS WM 0.
    architecture/LEARNING.md §10 "Task 7" has the full record.
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
ACC = os.path.join(ROOT, "scripts", "bigquery", "tests", "PREDICTION_CONTRACT_acceptance.sql")
GRADER = os.path.join(ROOT, "scripts", "bigquery", "procedures", "SP_GRADE_PREDICTIONS.sql")
CARD_DDL = os.path.join(ROOT, "scripts", "bigquery", "tables", "T_PREDICTION_SCORECARD.sql")
BQ = ["bq", "--project_id=onyga-482313"]

S = "onyga-482313.OI._tmp_t7c_"
T_GRADE, T_SC, T_LED, T_LED_BASE, T_ADS = (f"`{S}grade`", f"`{S}sc`", f"`{S}led`", f"`{S}led_base`", f"`{S}ads`")
P_SP, P_SP_NG = f"`{S}sp`", f"`{S}sp_ng`"
SWAP = {
    "`onyga-482313.OI.FACT_PREDICTION_GRADE`": T_GRADE,
    "`onyga-482313.OI.T_PREDICTION_SCORECARD`": T_SC,
    "`onyga-482313.OI.V_PREDICTION_LEDGER`": T_LED,
    "`onyga-482313.OI.FACT_AMAZON_ADS`": T_ADS,
}
GUARD = "AND (c.predictor IS NULL OR (regrade_from IS NOT NULL AND l.as_of >= regrade_from))"
EXP = "OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 1 DAY))"
REAL_GRADE = "`onyga-482313.OI.FACT_PREDICTION_GRADE`"
CARD_KEY = ["predictor", "variant", "family", "calendar_state", "level", "row_type", "scenario", "bucket",
            "window_from"]


def stripped(path):
    return "\n".join(l for l in open(path).read().split("\n") if not re.match(r"^\s*--", l))


def norm(s):
    return re.sub(r"\s+", " ", s).strip()


def grader_copy(proc, no_guard=False):
    t = stripped(GRADER).strip()
    head = "`onyga-482313.OI.SP_GRADE_PREDICTIONS`"
    if t.count(head) != 1:
        raise ValueError("SP_GRADE_PREDICTIONS.sql: the procedure name is not there once")
    t = t.replace(head, proc)
    for real, copy in SWAP.items():
        if real not in t:
            raise ValueError(f"SP_GRADE_PREDICTIONS.sql no longer reads {real}")
        t = t.replace(real, copy)
    if no_guard:
        if t.count(GUARD) != 1:
            raise ValueError("SP_GRADE_PREDICTIONS.sql: the graded-once guard of _due is not there once")
        t = t.replace(GUARD, "")
    for real in SWAP:
        if real in t:
            raise ValueError(f"the copy still reads {real}")
    return t


def grader_body():
    t = stripped(GRADER)
    m = re.search(r"^BEGIN\b.*^END;", t, re.S | re.M)
    if not m:
        raise ValueError("SP_GRADE_PREDICTIONS.sql: BEGIN ... END not found")
    return m.group(0)[:-1]


def temp_tables():
    names = re.findall(r"CREATE TEMP TABLE (\w+)", stripped(GRADER))
    if not names:
        raise ValueError("SP_GRADE_PREDICTIONS.sql creates no temp table")
    return names


def acc_parts():
    t = stripped(ACC)
    parts = {}
    pats = {
        "fd": r"^CREATE TEMP FUNCTION fd\(.*?\);$",
        "wmx": r"^CREATE TEMP TABLE wmx AS$.*?;$",
        "fnr": r"^CREATE TEMP TABLE fnr AS$.*?;$",
        "c_out": r"^CREATE OR REPLACE TEMP TABLE c_out AS$.*?^SELECT copy, chk, n FROM c_all;$",
    }
    for k, p in pats.items():
        m = re.search(p, t, re.S | re.M)
        if not m:
            raise ValueError(f"PREDICTION_CONTRACT_acceptance.sql: the {k} statement was not found")
        parts[k] = m.group(0)
    if "`onyga-482313.OI.FACT_PREDICTION_GRADE`" in parts["c_out"] or "V_PREDICTION_LEDGER" in parts["c_out"]:
        raise ValueError("the C statement reads the grade table or the ledger by name; it must read cg / cl only")
    return parts


def card_columns():
    cols = re.findall(r"^\s+(\w+)\s+(STRING|INT64|FLOAT64|DATE|TIMESTAMP|BOOL)\b", open(CARD_DDL).read(), re.M)
    if len(cols) < 10:
        raise ValueError("T_PREDICTION_SCORECARD.sql: the column list was not found")
    return cols


def c5x_sql():
    cols = card_columns()
    diffs = []
    for name, typ in cols:
        if name in CARD_KEY or name == "scored_at":
            continue
        diffs.append(f"fd(x.{name}, b.{name})" if typ == "FLOAT64" else f"x.{name} IS DISTINCT FROM b.{name}")
    kj = "TO_JSON_STRING(STRUCT(" + ", ".join(CARD_KEY) + "))"
    return f"""CREATE TEMP TABLE c5x AS
WITH vv AS (SELECT v FROM UNNEST(['FIX', 'FIXB', 'EMPTY']) AS v),
b0 AS (SELECT {kj} AS kj, * FROM cardv WHERE v = 'BASE'),
b AS (SELECT vv.v AS cv, b0.* EXCEPT (v) FROM vv CROSS JOIN b0),
x AS (SELECT {kj} AS kj, * FROM cardv WHERE v IN ('FIX', 'FIXB', 'EMPTY')),
j AS (
  SELECT COALESCE(x.v, b.cv) AS cv,
         x.v IS NULL OR b.cv IS NULL
         OR {' OR '.join(diffs)} AS bad
  FROM b FULL OUTER JOIN x ON x.v = b.cv AND x.kj = b.kj
)
SELECT CASE vv.v WHEN 'FIX' THEN 'FIX' WHEN 'FIXB' THEN 'NC_FIXB' ELSE 'NC_CARD_EMPTY' END AS copy,
       COUNTIF(COALESCE(j.bad, FALSE)) + IF((SELECT COUNT(*) FROM b0) = 0, 1, 0) AS n
FROM vv LEFT JOIN j ON j.cv = vv.v
GROUP BY vv.v;"""


def run_copy(proc, args):
    """count, CALL, count, then drop the grader's temp tables (they outlive a CALL inside a script, and
    the next CALL creates them again; a temp table not yet created cannot be named, so the drop
    follows the CALL)"""
    s = [f"SET n0 = (SELECT COUNT(*) FROM {T_GRADE});",
         f"CALL {proc}({args});",
         f"SET n1 = (SELECT COUNT(*) FROM {T_GRADE});",
         f"ALTER TABLE {T_SC} SET {EXP};"]
    s += [f"DROP TABLE IF EXISTS {t};" for t in temp_tables()]
    return s


def load_copy(grade_where, led_sql):
    return [f"CREATE OR REPLACE TABLE {T_GRADE} LIKE {REAL_GRADE} {EXP};",
            f"INSERT INTO {T_GRADE} SELECT * FROM live_grade WHERE {grade_where};",
            f"CREATE OR REPLACE TABLE {T_LED} {EXP} AS {led_sql};"]


def snap(v, card=False):
    s = [f"INSERT INTO cg SELECT '{v}', * FROM {T_GRADE};",
         f"INSERT INTO cc SELECT '{v}', COUNT(*), COUNTIF(predictor = 'FIXTURE'), MAX(scored_at) FROM {T_SC};"]
    if card:
        s.append(f"INSERT INTO cardv SELECT '{v}', * FROM {T_SC};")
    return s


KEY = "hkey(predictor, variant, as_of, campaign_id, keyword_id, scenario)"
PLAN_ROW = "STARTS_WITH(predictor, 'PLAN_')"
FX_LED = f"SELECT * FROM {T_LED_BASE} UNION ALL SELECT * EXCEPT (fx_predictor) FROM fx_led WHERE fx_predictor = '%s'"
FN_LED = (f"SELECT * REPLACE (IF(as_of = fn_night AND {PLAN_ROW}, as_of, horizon_from) AS horizon_from, "
          f"IF(as_of = fn_night AND {PLAN_ROW}, DATE_ADD(as_of, INTERVAL window_days - 1 DAY), horizon_to) AS horizon_to) "
          f"FROM {T_LED_BASE}")

# copy -> (grade variant, ledger variant, FN variant, board variant, card variant) for the C statement
CM = [
    ("RERUN", "RERUN", "BASE", "LIVE", "NONE", "RERUN"),
    ("NC_NOGUARD", "NOGUARD", "BASE", "LIVE", "NONE", "NOGUARD"),
    ("BASE", "BASE", "BASE", "LIVE", "NONE", "BASE"),
    ("REGRADE", "REGRADE", "BASE", "LIVE", "NONE", "REGRADE"),
    ("NC_REGRADE_LOST", "REGRADE_LOST", "BASE", "LIVE", "NONE", "REGRADE"),
    ("NC_REGRADE_OUTSIDE", "REGRADE_OUT", "BASE", "LIVE", "NONE", "REGRADE"),
    ("FIX", "FIX", "FIX", "LIVE", "NONE", "FIX"),
    ("NC_FIX_FLIP", "FIX_FLIP", "FIX", "LIVE", "NONE", "FIX"),
    ("NC_FIX_LINE", "FIX_LINE", "FIX", "LIVE", "NONE", "FIX"),
    ("NC_FIX_MISSING", "FIX_MISS", "FIX", "LIVE", "NONE", "FIX"),
    ("NC_FIXB", "FIXB", "FIXB", "LIVE", "NONE", "FIXB"),
    ("FNCLK", "FNCLK", "FNCLK", "LIVE", "NONE", "FNCLK"),
    ("NC_FNCLK_DOC", "FNCLK", "FNCLK", "FN_DOC", "NONE", "FNCLK"),
]

# copy -> [(check, expected)]: an int must read exactly; "GE1" at least 1
EXPECT = {
    "INPUTS": [("WM", 0)],
    "RERUN": [("C3f", 0), ("C3i", 0), ("C2", 0), ("C3", 0), ("C4a", 0), ("C4b", 0), ("F", 0), ("P1", 0),
              ("P2", 0), ("C5z", 0), ("C8c", 0)],
    "NC_NOGUARD": [("C3i", "GE1"), ("C3", "GE1")],
    "BASE": [("C3i", 0), ("C2", 0), ("C3", 0), ("C4a", 0), ("C4b", 0), ("F", 0), ("P1", 0), ("C5z", 0), ("C8c", 0)],
    "REGRADE": [("C3n", 0), ("C2", 0), ("C3", 0), ("C4a", 0), ("C4b", 0), ("F", 0), ("P1", 0), ("C8c", 0)],
    "NC_REGRADE_LOST": [("C3n", "GE1"), ("C3", "GE1")],
    "NC_REGRADE_OUTSIDE": [("C3n", "GE1"), ("C3", "GE1")],
    "FIX": [("C5", 0), ("C4a", 0), ("C4b", 0), ("C5x", 0), ("C3f", 0), ("C2", 0), ("C3", 0), ("F", 0), ("P1", 0),
            ("C5z", "GE1"), ("C8c", 0)],
    "NC_FIX_FLIP": [("C5", "GE1")],
    "NC_FIX_LINE": [("C4b", "GE1")],
    "NC_FIX_MISSING": [("C5", "GE1"), ("C2", "GE1")],
    "NC_FIXB": [("C5x", "GE1")],
    "NC_CARD_EMPTY": [("C5x", "GE1")],
    "FNCLK": [("P1", 0), ("P2", 0), ("P2n", "GE1"), ("C3f", 0), ("C2", 0), ("C3", 0), ("C4a", 0), ("F", 0),
              ("C8c", 0)],
    "NC_FNCLK_DOC": [("P2", "GE1")],
}
NEEDS = ["rerun_night", "fn_night", "rg_from"]


def build_script():
    a = acc_parts()
    cm = ",\n  ".join(
        (f"STRUCT('{c}' AS copy, '{g}' AS gv, '{l}' AS lv, '{f}' AS fv, '{h}' AS hv, '{k}' AS cv)" if i == 0
         else f"('{c}', '{g}', '{l}', '{f}', '{h}', '{k}')")
        for i, (c, g, l, f, h, k) in enumerate(CM))
    s = [
        "DECLARE n0 INT64;",
        "DECLARE n1 INT64;",
        "DECLARE g_max TIMESTAMP;",
        "DECLARE rerun_night DATE;",
        "DECLARE fn_night DATE;",
        "DECLARE rg_from DATE;",
        "DECLARE rg_reason STRING DEFAULT 'PREDICTION_CONTRACT controls: a re-grade on a copy (check_prediction_contract_controls.py)';",
        "CREATE TEMP FUNCTION hkey(p STRING, v STRING, d DATE, c STRING, k STRING, s STRING) AS "
        "(FORMAT('%s|%s|%t|%s|%s|%s', p, v, d, c, k, s));",
        a["fd"],
        a["wmx"],
        a["fnr"],
        f"CREATE TEMP TABLE live_grade AS SELECT * FROM {REAL_GRADE};",
        "SET g_max = (SELECT MAX(graded_at) FROM live_grade);",
        f"SET rerun_night = (SELECT MAX(as_of) FROM live_grade WHERE {PLAN_ROW});",
        "SET fn_night = (SELECT MAX(graded_night) FROM fnr WHERE row_type = 'FAMILY_WEEK' "
        f"AND graded_night IN (SELECT as_of FROM live_grade WHERE {PLAN_ROW}));",
        f"SET rg_from = (SELECT as_of FROM (SELECT DISTINCT as_of FROM live_grade WHERE {PLAN_ROW}) "
        "ORDER BY as_of DESC LIMIT 1 OFFSET 2);",
        f"CREATE OR REPLACE TABLE {T_LED_BASE} {EXP} AS SELECT * FROM `onyga-482313.OI.V_PREDICTION_LEDGER`;",
        # the fixtures: keyword, the side the prediction called (1 = GOOD), and what happened
        """CREATE TEMP TABLE fx AS
SELECT * FROM UNNEST([
  STRUCT('FIXTURE_RIGHT' AS kw, 1 AS pred_side, 12 AS clk, 2 AS ord, 10.0 AS sp, 10.0 AS gp),
  ('FIXTURE_WRONG', 1, 12, 0, 10.0, 0.0),
  ('FIXTURE_INCONCLUSIVE', 1, 3, 0, 10.0, 0.0),
  ('FIXTURE_INCONCLUSIVE_DARK', 1, 0, 0, 0.0, 0.0)])
UNION ALL
SELECT FORMAT('FIXTURE_RIGHT_%02d', i), 1, 10, 2, 10.0, 10.0 FROM UNNEST(GENERATE_ARRAY(1, 20)) AS i
UNION ALL
SELECT FORMAT('FIXTURE_INCONCLUSIVE_%02d', i), 1, 2, 0, 10.0, 0.0 FROM UNNEST(GENERATE_ARRAY(1, 10)) AS i;""",
        f"""CREATE OR REPLACE TABLE {T_ADS} {EXP} AS
SELECT date, campaign_id, keyword_id, Ads_clicks, Ads_cost, Ads_orders, GROSS_PROFIT
FROM `onyga-482313.OI.FACT_AMAZON_ADS`
WHERE date >= (SELECT MIN(horizon_from) FROM {T_LED_BASE})
UNION ALL
SELECT DATE '2026-08-21', 'FIXTURE_CAMPAIGN', kw, clk, sp, ord, gp FROM fx WHERE clk > 0;""",
        f"""CREATE TEMP TABLE fx_led AS
WITH base AS (
  SELECT l.* FROM {T_LED_BASE} l
  JOIN (SELECT as_of, campaign_id, keyword_id FROM {T_LED_BASE} WHERE predictor = 'PLAN_B'
        ORDER BY as_of, campaign_id, keyword_id LIMIT 1) p
    ON p.as_of = l.as_of AND p.campaign_id = l.campaign_id AND p.keyword_id = l.keyword_id
  WHERE l.predictor = 'PLAN_B'
)
SELECT pv.predictor AS fx_predictor, b.* REPLACE (
         pv.predictor AS predictor, pv.variant AS variant, DATE '2026-08-20' AS as_of,
         'FIXTURE_CAMPAIGN' AS campaign_id, f.kw AS keyword_id, 'FIXTURE' AS family,
         TIMESTAMP '2026-08-20 12:00:00 America/Los_Angeles' AS built_at,
         DATE '2026-08-21' AS horizon_from, DATE '2026-08-23' AS horizon_to, 3 AS window_days,
         f.pred_side AS pred_side, 1 AS min_orders, 0.5 AS family_bar, FALSE AS is_live_plan)
FROM base b CROSS JOIN fx f
CROSS JOIN UNNEST([STRUCT('FIXTURE' AS predictor, 'F' AS variant), ('PLAN_B', 'B')]) AS pv;""",
        # the copies' tables exist before the grader's copies are created (a procedure body is
        # validated against the tables it names when it is created)
        f"CREATE OR REPLACE TABLE {T_GRADE} LIKE {REAL_GRADE} {EXP};",
        f"CREATE OR REPLACE TABLE {T_LED} {EXP} AS SELECT * FROM {T_LED_BASE};",
        f"CREATE OR REPLACE TABLE {T_SC} LIKE `onyga-482313.OI.T_PREDICTION_SCORECARD` {EXP};",
        # the grader's copies: as written, and without its graded-once guard (NC_NOGUARD)
        grader_copy(P_SP),
        grader_copy(P_SP_NG, no_guard=True),
        # the C statement's inputs
        f"CREATE TEMP TABLE cg AS SELECT CAST(NULL AS STRING) AS v, * FROM {REAL_GRADE} WHERE FALSE;",
        f"CREATE TEMP TABLE cl AS SELECT 'BASE' AS v, * FROM {T_LED_BASE};",
        "CREATE TEMP TABLE cf AS SELECT 'LIVE' AS v, * FROM fnr;",
        "CREATE TEMP TABLE ch (v STRING, check_name STRING, status STRING, measured FLOAT64);",
        "CREATE TEMP TABLE cc (v STRING, n_rows INT64, n_fixture INT64, scored_at TIMESTAMP);",
        "CREATE TEMP TABLE cardv AS SELECT CAST(NULL AS STRING) AS v, * FROM `onyga-482313.OI.T_PREDICTION_SCORECARD` WHERE FALSE;",
        "CREATE TEMP TABLE hres (copy STRING, chk STRING, n INT64);",
        f"INSERT INTO hres SELECT 'INPUTS', 'WM', IF((SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) FROM {T_ADS}) "
        "IS NOT DISTINCT FROM (SELECT wm FROM wmx), 0, 1);",
    ]
    # RERUN: the latest graded night removed, two runs
    s += load_copy(f"NOT (as_of = rerun_night AND {PLAN_ROW})", f"SELECT * FROM {T_LED_BASE}")
    s += run_copy(P_SP, "NULL, NULL")
    s.append("INSERT INTO hres SELECT 'RERUN', 'C3f', ABS((n1 - n0) - r.k) + IF(r.k = 0, 1, 0) "
             f"FROM (SELECT COUNT(DISTINCT {KEY}) AS k FROM live_grade WHERE as_of = rerun_night AND {PLAN_ROW}) r;")
    s += run_copy(P_SP, "NULL, NULL")
    s.append("INSERT INTO hres SELECT 'RERUN', 'C3i', n1 - n0;")
    s += snap("RERUN")
    # NC_NOGUARD: the grader without its guard, on the real grades
    s += load_copy("TRUE", f"SELECT * FROM {T_LED_BASE}")
    s += run_copy(P_SP_NG, "NULL, NULL")
    s.append("INSERT INTO hres SELECT 'NC_NOGUARD', 'C3i', n1 - n0;")
    s += snap("NOGUARD")
    # BASE: the live record re-run; its card is C5x's reference
    s += load_copy("TRUE", f"SELECT * FROM {T_LED_BASE}")
    s += run_copy(P_SP, "NULL, NULL")
    s.append("INSERT INTO hres SELECT 'BASE', 'C3i', n1 - n0;")
    s += snap("BASE", card=True)
    # REGRADE: a regrade_from run, and its two doctored records
    s += load_copy("TRUE", f"SELECT * FROM {T_LED_BASE}")
    s += run_copy(P_SP, "rg_from, rg_reason")
    s += snap("REGRADE")
    s.append(f"""INSERT INTO cg
SELECT 'REGRADE_LOST', g.* EXCEPT (v) FROM cg g
WHERE g.v = 'REGRADE'
  AND NOT COALESCE(g.graded_at > g_max
                   AND hkey(g.predictor, g.variant, g.as_of, g.campaign_id, g.keyword_id, g.scenario)
                       = (SELECT MIN({KEY}) FROM cg WHERE v = 'REGRADE' AND graded_at > g_max), FALSE);""")
    s.append("""INSERT INTO cg
SELECT 'REGRADE_OUT', g.* EXCEPT (v) FROM cg g WHERE g.v = 'REGRADE'
UNION ALL
SELECT 'REGRADE_OUT', x.* EXCEPT (v) REPLACE (x.regrade_seq + 1 AS regrade_seq,
       (SELECT MAX(graded_at) FROM cg WHERE v = 'REGRADE') AS graded_at, rg_reason AS regrade_reason)
FROM (SELECT * FROM cg WHERE v = 'REGRADE' AND as_of < rg_from
      QUALIFY ROW_NUMBER() OVER (ORDER BY predictor, variant, as_of, campaign_id, keyword_id, scenario,
                                          regrade_seq DESC) = 1) x;""")
    # FIX: the fixtures under 'FIXTURE'
    s += load_copy("TRUE", FX_LED % "FIXTURE")
    s += run_copy(P_SP, "NULL, NULL")
    s.append("INSERT INTO hres SELECT 'FIX', 'C3f', ABS((n1 - n0) - 2 * (SELECT COUNT(*) FROM fx)) "
             "+ IF((SELECT COUNT(*) FROM fx) = 0, 1, 0);")
    s += snap("FIX", card=True)
    s.append(f"INSERT INTO cl SELECT 'FIX', * FROM {T_LED};")
    s.append("""INSERT INTO cg
SELECT 'FIX_FLIP', g.* EXCEPT (v) REPLACE (IF(g.keyword_id = 'FIXTURE_RIGHT' AND g.predictor = 'FIXTURE', 'WRONG', g.grade) AS grade)
FROM cg g WHERE g.v = 'FIX'
UNION ALL
SELECT 'FIX_LINE', g.* EXCEPT (v) REPLACE (
         IF(g.keyword_id = 'FIXTURE_INCONCLUSIVE' AND g.predictor = 'FIXTURE', g.real_clicks, g.min_clicks_at_grade) AS min_clicks_at_grade)
FROM cg g WHERE g.v = 'FIX'
UNION ALL
SELECT 'FIX_MISS', g.* EXCEPT (v) FROM cg g
WHERE g.v = 'FIX' AND NOT (g.keyword_id = 'FIXTURE_WRONG' AND g.predictor = 'FIXTURE');""")
    # NC_FIXB: the same fixtures under PLAN_B
    s += load_copy("TRUE", FX_LED % "PLAN_B")
    s += run_copy(P_SP, "NULL, NULL")
    s += snap("FIXB", card=True)
    s.append(f"INSERT INTO cl SELECT 'FIXB', * FROM {T_LED};")
    # FNCLK: fn_night graded on FN's window
    s += load_copy(f"NOT (as_of = fn_night AND {PLAN_ROW})", FN_LED)
    s += run_copy(P_SP, "NULL, NULL")
    s.append("INSERT INTO hres SELECT 'FNCLK', 'C3f', ABS((n1 - n0) - r.k) + IF(r.k = 0, 1, 0) "
             f"FROM (SELECT COUNT(DISTINCT {KEY}) AS k FROM live_grade WHERE as_of = fn_night AND {PLAN_ROW}) r;")
    s += snap("FNCLK")
    s.append(f"INSERT INTO cl SELECT 'FNCLK', * FROM {T_LED};")
    s.append("""INSERT INTO cf
SELECT 'FN_DOC', f.* REPLACE (
         IF(f.row_type = 'FAMILY_WEEK' AND f.graded_night = fn_night
            AND f.family = (SELECT MIN(family) FROM fnr WHERE row_type = 'FAMILY_WEEK' AND graded_night = fn_night),
            f.net_at_realized_a + 0.02, f.net_at_realized_a) AS net_at_realized_a)
FROM fnr f;""")
    s.append(f"CREATE TEMP TABLE cm AS SELECT * FROM UNNEST([\n  {cm}\n]);")
    s.append(a["c_out"])
    # C3n: exactly the named band
    s.append(f"""CREATE TEMP TABLE c3n AS
WITH vv AS (SELECT v FROM UNNEST(['REGRADE', 'REGRADE_LOST', 'REGRADE_OUT']) AS v),
pre AS (SELECT predictor, variant, as_of, campaign_id, keyword_id, scenario, MAX(regrade_seq) AS seq
        FROM live_grade GROUP BY 1, 2, 3, 4, 5, 6),
band AS (SELECT vv.v, p.* FROM vv CROSS JOIN pre p WHERE p.as_of >= rg_from),
run AS (
  SELECT v, predictor, variant, as_of, campaign_id, keyword_id, scenario,
         COUNT(*) AS n, MIN(regrade_seq) AS seq_lo,
         LOGICAL_AND(COALESCE(regrade_reason = rg_reason, FALSE)) AS reason_ok
  FROM cg
  WHERE v IN (SELECT v FROM vv) AND graded_at > g_max
  GROUP BY 1, 2, 3, 4, 5, 6, 7
),
j AS (
  SELECT COALESCE(b.v, r.v) AS v,
         (b.v IS NULL OR r.v IS NULL OR r.n <> 1 OR r.seq_lo <> b.seq + 1 OR NOT r.reason_ok) AS bad
  FROM band b
  FULL OUTER JOIN run r
    ON r.v = b.v AND r.predictor = b.predictor AND r.variant = b.variant AND r.as_of = b.as_of
   AND r.campaign_id = b.campaign_id AND r.keyword_id = b.keyword_id AND r.scenario = b.scenario
)
SELECT CASE vv.v WHEN 'REGRADE' THEN 'REGRADE' WHEN 'REGRADE_LOST' THEN 'NC_REGRADE_LOST' ELSE 'NC_REGRADE_OUTSIDE' END AS copy,
       COUNTIF(COALESCE(j.bad, FALSE))
       + IF((SELECT COUNT(*) FROM pre WHERE as_of >= rg_from) = 0, 1, 0)
       + IF((SELECT COUNT(*) FROM pre WHERE as_of < rg_from) = 0, 1, 0) AS n
FROM vv LEFT JOIN j ON j.v = vv.v
GROUP BY vv.v;""")
    s.append(c5x_sql())
    # the record of the picks, then the scratch objects dropped
    s.append(f"""CREATE TEMP TABLE pick AS
SELECT rerun_night, fn_night, rg_from, g_max, (SELECT wm FROM wmx) AS wm,
       (SELECT COUNT(DISTINCT {KEY}) FROM live_grade WHERE as_of = rerun_night AND {PLAN_ROW}) AS rerun_keys,
       (SELECT COUNT(DISTINCT {KEY}) FROM live_grade WHERE as_of = fn_night AND {PLAN_ROW}) AS fn_keys,
       (SELECT COUNT(*) FROM cg WHERE v = 'REGRADE' AND graded_at > g_max) AS regrade_rows,
       (SELECT COUNT(*) FROM cg WHERE v = 'NOGUARD' AND graded_at > g_max) AS noguard_rows,
       (SELECT COUNT(*) FROM fx) AS fixtures,
       (SELECT STRING_AGG(DISTINCT CAST(min_clicks_at_grade AS STRING)) FROM cg WHERE v = 'FIX' AND predictor = 'FIXTURE') AS fixture_line,
       (SELECT STRING_AGG(FORMAT('%s %s', grade, CAST(n AS STRING)) ORDER BY grade) FROM (
          SELECT grade, COUNT(*) AS n FROM cg WHERE v = 'FIX' AND predictor = 'FIXTURE' GROUP BY grade)) AS fixture_labels,
       (SELECT COUNT(*) FROM cardv WHERE v = 'BASE') AS base_card_rows,
       (SELECT COUNT(*) FROM cardv WHERE v = 'FIX') AS fix_card_rows,
       (SELECT COUNT(*) FROM cardv WHERE v = 'FIXB') AS fixb_card_rows;""")
    for t in (T_GRADE, T_SC, T_LED, T_LED_BASE, T_ADS):
        s.append(f"DROP TABLE IF EXISTS {t};")
    for p in (P_SP, P_SP_NG):
        s.append(f"DROP PROCEDURE IF EXISTS {p};")
    s.append("""SELECT copy, chk, n, CAST(NULL AS STRING) AS detail FROM c_out
UNION ALL SELECT copy, chk, n, NULL FROM hres
UNION ALL SELECT copy, 'C3n', n, NULL FROM c3n
UNION ALL SELECT copy, 'C5x', n, NULL FROM c5x
UNION ALL SELECT 'PICK', 'PICK', 0, TO_JSON_STRING(p) FROM pick p
ORDER BY copy, chk;""")
    return "\n".join(s)


def run(args):
    return subprocess.run(BQ + args, capture_output=True, text=True)


def grader_tie():
    r = run(["--format=json", "query", "--use_legacy_sql=false", "--nouse_cache",
             "SELECT routine_definition FROM `onyga-482313.OI.INFORMATION_SCHEMA.ROUTINES` "
             "WHERE routine_name = 'SP_GRADE_PREDICTIONS'"])
    if r.returncode != 0:
        print(r.stdout[-2000:], r.stderr[-2000:])
        return 2
    rows = json.loads(r.stdout)
    deployed = norm(rows[0]["routine_definition"]) if rows else ""
    if norm(grader_body()) != deployed:
        print("the deployed SP_GRADE_PREDICTIONS body is not the file's (comment lines stripped): deploy it first")
        return 1
    print("the deployed SP_GRADE_PREDICTIONS body equals the file's")
    return 0


def submit():
    try:
        script = build_script()
    except Exception as e:  # noqa: BLE001
        print("could not build the script:", e)
        return 2
    if os.environ.get("PREDICTION_CONTROLS_SQL"):
        open(os.environ["PREDICTION_CONTROLS_SQL"], "w").write(script)
    tie = grader_tie()
    if tie:
        return tie
    r = run(["query", "--nosync", "--format=none", "--use_legacy_sql=false", "--nouse_cache", script])
    m = re.search(r"bqjob_[A-Za-z0-9_]+", r.stdout + r.stderr)
    if r.returncode != 0 or not m:
        print(r.stdout[-3000:], r.stderr[-3000:])
        return 2
    print("JOB=" + m.group(0), flush=True)
    return 0


def collect(job):
    r = run(["--format=json", "show", "-j", job])
    if r.returncode != 0:
        print(r.stdout[-2000:], r.stderr[-2000:])
        return 2
    info = json.loads(r.stdout)
    state = info.get("status", {}).get("state")
    if state != "DONE":
        print(job, state, "- poll with: bq wait --project_id=onyga-482313", job, "60")
        return 3
    err = info.get("status", {}).get("errorResult")
    if err:
        print("the job failed:", err)
        return 2
    st = info.get("statistics", {})
    slot_s = int(st.get("totalSlotMs", 0)) / 1000.0
    secs = (int(st.get("endTime", 0)) - int(st.get("startTime", 0))) / 1000.0
    r = run(["--format=json", "head", "-j", "-n", "10000", job])
    if r.returncode != 0:
        print(r.stdout[-2000:], r.stderr[-2000:])
        return 2
    objs = json.loads(r.stdout)
    print(f"job {job}: {slot_s:,.1f} slot-seconds, {secs:,.0f} s, {len(objs)} result rows")
    pick = next((json.loads(x["detail"]) for x in objs if x.get("copy") == "PICK"), {})
    if not pick:
        print("the PICK row did not parse")
        return 2
    print("picks:", pick)
    got = {(x["copy"], x["chk"]): int(x["n"]) for x in objs if x.get("copy") != "PICK"}
    bad = []
    missing = [c for c in NEEDS if pick.get(c) is None]
    if missing:
        print("NOT EXERCISED: nothing to copy (" + ", ".join(missing) + " NULL)")
        bad.append(("NOT EXERCISED", missing))
    for name, targets in EXPECT.items():
        for chk, want in targets:
            v = got.get((name, chk))
            ok = (v is not None and v >= 1) if want == "GE1" else (v == want)
            print(f"{'ok ' if ok else 'BAD'} {name:20} {chk:4} = {v} (expected {'>= 1' if want == 'GE1' else want})")
            if not ok:
                bad.append((name, chk, v, want))
        others = {k[1]: x for k, x in got.items() if k[0] == name and k[1] not in [t[0] for t in targets]}
        if others:
            print(f"    {name:20} not asserted: {others}")
    if bad:
        print("MISMATCHES / NOT EXERCISED:", bad)
        return 1
    return 0


def cleanup():
    stmts = [f"DROP TABLE IF EXISTS {t};" for t in (T_GRADE, T_SC, T_LED, T_LED_BASE, T_ADS)]
    stmts += [f"DROP PROCEDURE IF EXISTS {p};" for p in (P_SP, P_SP_NG)]
    r = run(["query", "--use_legacy_sql=false", "--nouse_cache", "\n".join(stmts)])
    print(r.stdout[-2000:], r.stderr[-2000:])
    return 0 if r.returncode == 0 else 2


def main():
    if "--cleanup" in sys.argv:
        return cleanup()
    if "--collect" in sys.argv:
        return collect(sys.argv[sys.argv.index("--collect") + 1])
    if "--submit" in sys.argv:
        return submit()
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
