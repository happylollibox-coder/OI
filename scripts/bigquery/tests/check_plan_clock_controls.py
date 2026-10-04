#!/usr/bin/env python3
"""Run FACT_PLAN_NEXT_WEEK_acceptance.sql and V_ENGINE_HEALTH's plan_window_complete_days (c23) on the
live plan and on doctored copies of it — the negative controls of piece-1 plan Task 6 (v27.160).

WHY THIS EXISTS
    The house rule is that every acceptance check has a negative control run on a temp copy, and
    that an empty input fails rather than passes. Task 6 (Ori's ruling R11 of 2026-10-02 = spec P-24,
    and audit fix #25) keyed a night on the New York date, restated C01 (the age-2 fence is two days
    before the LOS ANGELES date of the build, not before as_of) and V_ENGINE_HEALTH's c23 with it, and
    added K1 (as_of is the New York date of the build), K2 (one calendar state per partition, and the
    latest partition carries its own date's state) and K3 (no shadow row names a side its side column
    does not hold; no priced row says it carries no price). The table cannot be doctored, so this
    script runs each file's OWN text with names swapped:
        `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`      -> a copy of EVERY partition (K1, K2 read the
                                                      history), doctored per copy
        `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`   -> one snapshot of the judgement, read ONCE
    and, for the board, the `pl` / `plb` / `c23` CTEs cut out of scripts/bigquery/views/V_ENGINE_HEALTH.sql
    (comment lines stripped) with the plan table swapped the same way; before submitting, the script
    checks that the DEPLOYED view's definition carries that text. Each copy is materialized, then each
    check runs on it. Nothing here restates a check. Doctored rows are chosen deterministically
    (lowest rn) in the latest partition.

THE COPIES (check: expected value on that copy; H23M = plan_window_complete_days' measured value,
H23S = 1 when its status is RED)
    LIVE                          every check 0, H23M 0, H23S 0.
    NC_EMPTY                      no rows: K1 1, K2 1, K3 1 (emptiness terms), H23S 1.
    NC_C01_WINDOW_SHIFTED         one live row's window moved a day earlier (window_from and
                                  window_to, so its length holds): C01 1, H23M 1, H23S 1.
    NC_K1_NOT_NY_DATE             every row of the latest partition stamped as built at 22:40 Los
                                  Angeles on its as_of — the New York date is the next day, which is
                                  how a Los Angeles-keyed 22:35 pass wrote: K1 1.
    NC_K2_TWO_STATES              one row of the latest partition given another calendar state:
                                  K2 2 (two states in one partition; not its date's state).
    NC_K2_REWRITTEN_WHOLE         every row of the latest partition given another state — the
                                  2026-09-30 defect, a partition rewritten whole under another night's
                                  state: K2 1 (one state per partition cannot see it; the date term does).
    NC_K3_RULE_B_WORDS_ON_GOOD    a plan-A GOOD row whose live row is NOT_GOOD and competes for a seat,
                                  given v27.159's sentence (the P-9 prefix + the live row's sentence):
                                  K3 2 (plan A's side unnamed; the not-good side's words).
    NC_K3_RULE_B_WORDS_ON_NOT_GOOD  a priced plan-A NOT_GOOD row whose live row is GOOD, given
                                  v27.159's sentence: K3 3 (side unnamed; the good side's words; a
                                  priced row saying it carries no planned price).
    NC_K3_PRICED_SAYS_NONE        a priced plan-A row on the live plan's side with "this row carries
                                  no planned price" appended: K3 1.
    NC_K3_FOREIGN_WORDS_SAME_SIDE a plan-A GOOD row on the live plan's side with "It competes for a
                                  seat at $1.00." appended: K3 1.
    NC_K3_NO_SHADOW               every plan-A row removed: K3 1 (emptiness), C02 >= 1.
  v27.170 (learning piece 2 Task 3, Ori's ruling D2 (c)): F1 (no night written since the cutover was
  rewritten after Los Angeles midnight of its as_of; a late first write is allowed) and F2 (every row
  written since the cutover carries builder_version, the deployed builder's on rows written since its
  deploy). F1 also reads the plan table's WRITE RECORD — the INSERT / DELETE child jobs on it in
  `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT since the cutover — which this script swaps too:
        `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT -> jbase (those jobs, read ONCE; with
                                                      --jobs-table-id, the jobs on that table of OI,
                                                      relabelled as the plan table's), doctored per copy
  The doctored night is the latest one written since the cutover (NULL when there is none: NOT
  EXERCISED); its write is the first INSERT on the table within the hour after its built_at, and that
  INSERT's script's last DELETE before it.
    LIVE (on such a night)        the late first write: F1 0, F2 0.
    NC_EMPTY                      also F1 1, F2 1 (emptiness terms).
    NC_F1_SECOND_WRITE_AFTER_MIDNIGHT  the plan's control — its DELETE recorded as removing the
                                  night's rows (a second write), the night restamped 00:35 Los Angeles
                                  on its own as_of (after Los Angeles midnight; not re-keyed), its two
                                  jobs moved with it: F1 1. Until 2026-10-04 the copy kept the write's
                                  stamp, so on a night written on time (22:30 Los Angeles the evening
                                  before) it was a rewrite before midnight and read F1 0.
    HC_F1_REWRITE_BEFORE_MIDNIGHT that rewrite re-keyed to the next New York night and stamped 22:35
                                  Los Angeles on its original date (the 05:00 UTC pass's hour, before
                                  Los Angeles midnight of the new as_of), its two jobs moved with it: F1 0, F2 0.
    NC_F1_REWRITE_AT_MIDNIGHT     the same stamped at Los Angeles midnight of the new as_of: F1 1.
    NC_F1_WRITE_NOT_ON_RECORD     the night's INSERT removed from the record: F1 1.
    NC_F2_NULL                    one row of the night with builder_version NULL: F2 2 (it carries no
                                  version, and not the deployed builder's).
    NC_F2_STALE_VERSION           one row of the night with builder_version 'v27.169' (a deploy that
                                  forgot to bump builder_version_d): F2 1.
  v27.171 (learning piece 2 Task 3 follow-up 2): C13 compares the latest night with the judgement it
  was BUILT ON, which SP_BUILD_NEXT_WEEK_PLAN v27.171 saves with the night in T_PLAN_BUILD_JUDGMENT
  (keyed on as_of and built_at), not with the live view, whose window fence moves at Los Angeles
  midnight while a frozen night stays. That table is swapped too:
        `onyga-482313.OI.T_PLAN_BUILD_JUDGMENT`    -> bjbase (read ONCE; with --build-judge-table, a
                                                      copy a simulated pass wrote), doctored per copy
  The doctored saved row is the one of the latest night's lowest-numbered live row (live_rn); bj_n is
  the number of saved rows for the latest night's write (NULL: NOT EXERCISED).
    NC_EMPTY                      also C13 2 (nothing saved for an empty night, and no live row).
    NC_C13_VERDICT_MOVED          that live row's verdict changed in the plan: C13 1.
    NC_C13_NOT_SAVED              no judgement saved (a night written before v27.171): C13 1.
    NC_C13_OTHER_WRITE            the saved judgement stamped one second later (saved by another write
                                  of the night): C13 1.
    NC_C13_ROW_NOT_SAVED          that row's saved judgement removed: C13 1.
    NC_C13_SIDE_DIFFERS / _CANDIDACY_DIFFERS / _WINDOW_DIFFERS (window_from and window_to a day later)
    / _STATE_DIFFERS              that row's saved side_b, is_candidate, window or calendar_state
                                  changed: C13 1 each.
    LIVE on the REAL table reads 0 on every check, at any hour, once a night has been written by
    v27.171 (its first write records the judgement C13 reads, and F1 / F2 read that night). Until then
    it reads C13 1 (the latest night's judgement is not on record), F1 1 and F2 1 (emptiness) and the
    script exits 1; run it on a simulated pass (--plan-table, --jobs-table-id, --judge-table,
    --build-judge-table) as the v27.170 and v27.171 deploys did.
    A copy's other checks are printed and not asserted. NOT EXERCISED: a copy whose doctored row does
    not exist on the partition (its pick column is NULL) tests nothing; it is reported and the script
    exits 1.

EXIT CODES
    0  LIVE read 0 on every check, every copy was exercised, and every copy read its expected value
    1  a copy did not, or was not exercised, or the deployed V_ENGINE_HEALTH does not carry this file's
       c23 text, or the acceptance still carries the K1 cutover placeholder
    2  the check could not run

USAGE (one BigQuery script job of 41 statements, submitted asynchronously and polled: 2,642.4
slot-seconds and about 2 minutes on 2026-10-03 02:51 UTC, job bqjob_r28d04f5d6d9da7e1_000001a0ffabd93a_1,
exit 0 on the live table; 2,407.5 slot-seconds and exit 0 on a simulated 22:40 Los Angeles pass,
--plan-table OI._tmp_t6_sim_plan --judge-table OI._tmp_t6_sim_judge, job
bqjob_r3b355b0a9c44aefd_000001a0ffb852de_1; with the eight v27.171 C13 copies, 25 copies, 10,134.5
slot-seconds and about 6 minutes on 2026-10-03 18:40 UTC, exit 0 on a simulated pass, --plan-table
OI._tmp_c13_plan --jobs-table-id _tmp_c13_plan --judge-table OI._tmp_c13_judge --build-judge-table
OI._tmp_c13_bj, job bqjob_r2bf99b8d41e5b9f7_000001a10310eb8f_1; with NC_F1_SECOND_WRITE_AFTER_MIDNIGHT
restamped, defaults on the real 10-04 night (written 05:30:18 UTC), 12,702.4 slot-seconds and about 7
minutes on 2026-10-04 14:16 UTC, exit 0, that copy F1 1, job bqjob_r7679d928f877cc68_000001a10745edc6_1)
    python3 scripts/bigquery/tests/check_plan_clock_controls.py [--judge-table PROJECT.DATASET.TABLE]
        [--plan-table PROJECT.DATASET.TABLE --jobs-table-id TABLE_ID --build-judge-table PROJECT.DATASET.TABLE]
    python3 scripts/bigquery/tests/check_plan_clock_controls.py --submit [--judge-table ...]
    python3 scripts/bigquery/tests/check_plan_clock_controls.py --collect JOB
    --judge-table reads a snapshot of the judgement instead of the deployed view. Since v27.171 only
    T1's click goal (a constant the view declares) reads it; C13 reads the saved judgement below.
    --plan-table reads a copy of the plan table instead of FACT_PLAN_NEXT_WEEK (a simulated pass
    written to a copy, with --judge-table the judgement that pass read).
    --jobs-table-id reads the write record of that copy (a table id in OI, e.g. _tmp_t3_plan) instead
    of FACT_PLAN_NEXT_WEEK's (v27.170).
    --build-judge-table reads a copy of T_PLAN_BUILD_JUDGMENT (the judgement a simulated pass saved with
    the night it wrote to --plan-table) instead of the real one (v27.171).
"""
import json
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
ACC_PLAN = os.path.join(ROOT, "scripts", "bigquery", "tests", "FACT_PLAN_NEXT_WEEK_acceptance.sql")
HEALTH = os.path.join(ROOT, "scripts", "bigquery", "views", "V_ENGINE_HEALTH.sql")
VIEW = "`onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`"
PLAN = "`onyga-482313.OI.FACT_PLAN_NEXT_WEEK`"
JOBS = "`region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT"
# v27.171 (Task 3 follow-up 2): C13 reads the judgement each night was built on, which the builder saves
BUILD_J = "`onyga-482313.OI.T_PLAN_BUILD_JUDGMENT`"
BQ = ["bq", "--project_id=onyga-482313"]


def stripped(path):
    return "\n".join(l for l in open(path).read().split("\n") if not re.match(r"^\s*--", l))


def acceptance_query():
    q = stripped(ACC_PLAN).strip().rstrip(";")
    if PLAN not in q or VIEW not in q or JOBS not in q or BUILD_J not in q:
        raise ValueError("the acceptance no longer reads the plan table, the view, the job record and the "
                         "saved judgement by name")
    if "__K1_CUTOVER__" in q:
        raise ValueError("the acceptance still carries the K1 cutover placeholder")
    if "__F_CUTOVER__" in q:
        raise ValueError("the acceptance still carries the F1/F2 cutover placeholder")
    return q.replace(VIEW, "jsnap").replace(PLAN, "__HH__").replace(JOBS, "__JJ__").replace(BUILD_J, "__BJ__")


def f_cutover():
    """The v27.170 cutover F1 and F2 read, as the acceptance's f_dml CTE states it."""
    m = re.search(r"^f_dml AS \(.*?creation_time >= TIMESTAMP '([^']+)'", stripped(ACC_PLAN), re.S | re.M)
    if not m:
        raise ValueError("the acceptance's f_dml CTE (F1) was not found")
    return m.group(1)


def health_ctes():
    text = stripped(HEALTH)
    m_pl = re.search(r"^pl AS \(.*?^plb AS \(SELECT \* FROM pl WHERE is_live_plan\),", text, re.S | re.M)
    m_c23 = re.search(r"^c23 AS \(.*?(?=^pot_rec AS \()", text, re.S | re.M)
    if not m_pl or not m_c23 or "'plan_window_complete_days'" not in m_c23.group(0) or PLAN not in m_pl.group(0):
        raise ValueError("V_ENGINE_HEALTH.sql: the pl / plb / c23 (plan_window_complete_days) CTEs were not found")
    return m_pl.group(0).rstrip().rstrip(","), m_c23.group(0).rstrip().rstrip(",")


def norm(s):
    return re.sub(r"\s+", " ", s).strip()


LIVE = "SELECT * EXCEPT (rn) FROM hbase"


def rows(cond, **repl):
    sets = ", ".join(f"IF({cond}, {v}, {k}) AS {k}" for k, v in repl.items())
    return f"SELECT * EXCEPT (rn) REPLACE ({sets}) FROM hbase"


def at(col, **repl):
    return rows(f"rn = (SELECT {col} FROM pick)", **repl)


LATEST = "as_of = (SELECT mx FROM pick)"
OTHER_STATE = "IF(calendar_state = 'OFF_PEAK', 'PEAK', 'OFF_PEAK')"
V159 = "'SHADOW PLAN A, recorded for grading and never uploaded (P-9). '"

# v27.170 (learning piece 2 Task 3): F1 / F2 read the plan table's write record as well. jbase is that
# record (INSERT / DELETE jobs on the table since the F cutover); a copy names its own doctored record
# in JCOPIES, every other copy reads jbase as it is.
JLIVE = "SELECT * EXCEPT (jrn) FROM jbase"
F_LATEST = "as_of = (SELECT f_as_of FROM pick)"
F_DEL_IS_REWRITE = ("IF(jrn = (SELECT f_del_jrn FROM pick), STRUCT(dml_statistics.inserted_row_count AS inserted_row_count, "
                    "(SELECT f_n FROM pick) AS deleted_row_count), dml_statistics) AS dml_statistics")


def f_moved(stamp, rekey=True):
    """The latest night stamped at `stamp` (Los Angeles time; {d} is its original as_of) and, with
    `rekey`, re-keyed to the next New York date; its write's two jobs moved by the same amount, the
    DELETE recorded as a rewrite."""
    new_built = f"TIMESTAMP(DATETIME({stamp}), 'America/Los_Angeles')"
    moved = {"as_of": "DATE_ADD(as_of, INTERVAL 1 DAY)"} if rekey else {}
    plan = rows(F_LATEST, **moved, built_at=new_built.replace("{d}", "as_of"))
    delta = (f"TIMESTAMP_DIFF({new_built.replace('{d}', '(SELECT f_as_of FROM pick)')}, "
             "(SELECT f_built_at FROM pick), MICROSECOND)")
    jobs = ("SELECT * EXCEPT (jrn) REPLACE ("
            f"IF(jrn IN ((SELECT f_ins_jrn FROM pick), (SELECT f_del_jrn FROM pick)), "
            f"TIMESTAMP_ADD(creation_time, INTERVAL {delta} MICROSECOND), creation_time) AS creation_time, "
            f"{F_DEL_IS_REWRITE}) FROM jbase")
    return plan, jobs


F_HC_PLAN, F_HC_JOBS = f_moved("{d}, TIME '22:35:00'")
F_NC_PLAN, F_NC_JOBS = f_moved("DATE_ADD({d}, INTERVAL 1 DAY), TIME '00:00:00'")
# 2026-10-04: the second write is restamped 00:35 Los Angeles on the night's own as_of. The copy used to
# keep the write's stamp, which on an on-time night (the 05:00 UTC pass, 22:30 Los Angeles the evening
# before) is a rewrite BEFORE midnight, which D2 (c) allows: F1 0 on the real 10-04 night.
F_2ND_PLAN, F_2ND_JOBS = f_moved("{d}, TIME '00:35:00'", rekey=False)
F_NEEDS = ["f_as_of", "f_ins_jrn", "f_del_jrn"]

# name -> doctored write record (copies not named read JLIVE)
JCOPIES = {
    "NC_F1_SECOND_WRITE_AFTER_MIDNIGHT": F_2ND_JOBS,
    "HC_F1_REWRITE_BEFORE_MIDNIGHT": F_HC_JOBS,
    "NC_F1_REWRITE_AT_MIDNIGHT": F_NC_JOBS,
    "NC_F1_WRITE_NOT_ON_RECORD": f"{JLIVE} WHERE jrn != (SELECT f_ins_jrn FROM pick)",
}

# v27.171 (Task 3 follow-up 2): C13 reads the judgement the latest night was built on, saved by the builder
# in T_PLAN_BUILD_JUDGMENT and keyed on (as_of, built_at). bjbase is that table (or --build-judge-table's
# copy), read ONCE; a copy names its own doctored record in BJCOPIES, every other copy reads bjbase as it is.
BJLIVE = "SELECT * FROM bjbase"
# the saved row of the live row C13's copies doctor (the latest night's lowest-numbered live row)
BJ_ROW = ("(as_of = (SELECT mx FROM pick) AND campaign_id = (SELECT campaign_id FROM hbase WHERE rn = (SELECT live_rn FROM pick)) "
          "AND keyword_id = (SELECT keyword_id FROM hbase WHERE rn = (SELECT live_rn FROM pick)))")


def bj_row(**repl):
    sets = ", ".join(f"IF({BJ_ROW}, {v}, {k}) AS {k}" for k, v in repl.items())
    return f"SELECT * REPLACE ({sets}) FROM bjbase"


BJCOPIES = {
    "NC_C13_NOT_SAVED": f"{BJLIVE} WHERE FALSE",
    "NC_C13_OTHER_WRITE": "SELECT * REPLACE (TIMESTAMP_ADD(built_at, INTERVAL 1 SECOND) AS built_at) FROM bjbase",
    "NC_C13_ROW_NOT_SAVED": f"{BJLIVE} WHERE NOT {BJ_ROW}",
    "NC_C13_SIDE_DIFFERS": bj_row(side_b="IF(side_b = 'GOOD', 'NOT_GOOD', 'GOOD')"),
    "NC_C13_CANDIDACY_DIFFERS": bj_row(is_candidate="NOT is_candidate"),
    "NC_C13_WINDOW_DIFFERS": bj_row(window_from="DATE_ADD(window_from, INTERVAL 1 DAY)",
                                    window_to="DATE_ADD(window_to, INTERVAL 1 DAY)"),
    "NC_C13_STATE_DIFFERS": bj_row(calendar_state="CONCAT(calendar_state, '_DOCTORED')"),
}
BJ_NEEDS = ["bj_n", "live_rn"]

# name -> (copy SQL, [(check, expected)], pick columns the copy needs: NULL = NOT EXERCISED)
COPIES = {
    "LIVE": (LIVE, None, []),
    "NC_EMPTY": (f"{LIVE} WHERE FALSE", [("K1", 1), ("K2", 1), ("K3", 1), ("H23S", 1), ("F1", 1), ("F2", 1),
                                         ("C13", 2)], []),
    # v27.171 (Task 3 follow-up 2): C13 against the judgement the night was built on. The plan's side
    # of the comparison (one live row's verdict moved), the record's presence (none saved; one saved by
    # another write of the night; one row missing) and the record's side of each compared column.
    "NC_C13_VERDICT_MOVED": (at("live_rn", verdict="CONCAT(verdict, '_DOCTORED')"), [("C13", 1)], BJ_NEEDS),
    "NC_C13_NOT_SAVED": (LIVE, [("C13", 1)], BJ_NEEDS),
    "NC_C13_OTHER_WRITE": (LIVE, [("C13", 1)], BJ_NEEDS),
    "NC_C13_ROW_NOT_SAVED": (LIVE, [("C13", 1)], BJ_NEEDS),
    "NC_C13_SIDE_DIFFERS": (LIVE, [("C13", 1)], BJ_NEEDS),
    "NC_C13_CANDIDACY_DIFFERS": (LIVE, [("C13", 1)], BJ_NEEDS),
    "NC_C13_WINDOW_DIFFERS": (LIVE, [("C13", 1)], BJ_NEEDS),
    "NC_C13_STATE_DIFFERS": (LIVE, [("C13", 1)], BJ_NEEDS),
    # v27.170 (D2 (c)): the freeze. LIVE (on a night written since the cutover by its first write,
    # however late) is the late-first-write case and reads F1 0, F2 0.
    "NC_F1_SECOND_WRITE_AFTER_MIDNIGHT": (F_2ND_PLAN, [("F1", 1)], F_NEEDS),
    "HC_F1_REWRITE_BEFORE_MIDNIGHT": (F_HC_PLAN, [("F1", 0), ("F2", 0)], F_NEEDS),
    "NC_F1_REWRITE_AT_MIDNIGHT": (F_NC_PLAN, [("F1", 1)], F_NEEDS),
    "NC_F1_WRITE_NOT_ON_RECORD": (LIVE, [("F1", 1)], F_NEEDS),
    # a NULL fails both F2 terms: it carries no version, and not the deployed builder's
    "NC_F2_NULL": (at("f_rn", builder_version="CAST(NULL AS STRING)"), [("F2", 2)], ["f_rn"]),
    "NC_F2_STALE_VERSION": (at("f_rn", builder_version="'v27.169'"), [("F2", 1)], ["f_rn"]),
    "NC_C01_WINDOW_SHIFTED": (at("live_rn", window_from="DATE_SUB(window_from, INTERVAL 1 DAY)",
                                 window_to="DATE_SUB(window_to, INTERVAL 1 DAY)"),
                              [("C01", 1), ("H23M", 1), ("H23S", 1)], ["live_rn"]),
    "NC_K1_NOT_NY_DATE": (rows(LATEST, built_at="TIMESTAMP(DATETIME(as_of, TIME '22:40:00'), 'America/Los_Angeles')"),
                          [("K1", 1)], ["mx"]),
    "NC_K2_TWO_STATES": (at("live_rn", calendar_state=OTHER_STATE), [("K2", 2)], ["live_rn"]),
    "NC_K2_REWRITTEN_WHOLE": (rows(LATEST, calendar_state=OTHER_STATE), [("K2", 1)], ["mx"]),
    "NC_K3_RULE_B_WORDS_ON_GOOD": (at("a_good_rn", sentence=f"CONCAT({V159}, (SELECT sentence FROM hbase WHERE rn = (SELECT a_good_live_rn FROM pick)))"),
                                   [("K3", 2)], ["a_good_rn", "a_good_live_rn"]),
    "NC_K3_RULE_B_WORDS_ON_NOT_GOOD": (at("a_ng_rn", sentence=f"CONCAT({V159}, (SELECT sentence FROM hbase WHERE rn = (SELECT a_ng_live_rn FROM pick)))"),
                                       [("K3", 3)], ["a_ng_rn", "a_ng_live_rn"]),
    "NC_K3_PRICED_SAYS_NONE": (at("a_same_priced_rn", sentence="CONCAT(sentence, ' No move: this row carries no planned price.')"),
                               [("K3", 1)], ["a_same_priced_rn"]),
    "NC_K3_FOREIGN_WORDS_SAME_SIDE": (at("a_same_good_rn", sentence="CONCAT(sentence, ' It competes for a seat at $1.00.')"),
                                      [("K3", 1)], ["a_same_good_rn"]),
    "NC_K3_NO_SHADOW": (f"{LIVE} WHERE is_live_plan OR as_of != (SELECT mx FROM pick)",
                        [("K3", 1), ("C02", "GE1")], ["mx"]),
}

PICK = """CREATE TEMP TABLE pick AS
WITH t AS (SELECT * FROM hbase WHERE as_of = (SELECT MAX(as_of) FROM hbase)),
pair AS (SELECT a.rn, l.rn AS live_rn, a.side, l.side AS live_side, a.planned_bid, l.sentence AS live_sentence
         FROM t a JOIN t l ON l.campaign_id = a.campaign_id AND l.keyword_id = a.keyword_id
         WHERE NOT a.is_live_plan AND l.is_live_plan)
SELECT
  (SELECT MAX(as_of) FROM hbase) AS mx,
  (SELECT MIN(rn) FROM t WHERE is_live_plan) AS live_rn,
  (SELECT MIN(rn) FROM pair WHERE side = 'GOOD' AND live_side = 'NOT_GOOD'
     AND live_sentence LIKE '%competes for a seat%') AS a_good_rn,
  (SELECT live_rn FROM pair WHERE rn = (SELECT MIN(rn) FROM pair WHERE side = 'GOOD' AND live_side = 'NOT_GOOD'
     AND live_sentence LIKE '%competes for a seat%')) AS a_good_live_rn,
  (SELECT MIN(rn) FROM pair WHERE side = 'NOT_GOOD' AND live_side = 'GOOD' AND planned_bid IS NOT NULL) AS a_ng_rn,
  (SELECT live_rn FROM pair WHERE rn = (SELECT MIN(rn) FROM pair WHERE side = 'NOT_GOOD' AND live_side = 'GOOD'
     AND planned_bid IS NOT NULL)) AS a_ng_live_rn,
  (SELECT MIN(rn) FROM pair WHERE side = 'NOT_GOOD' AND live_side = 'NOT_GOOD' AND planned_bid IS NOT NULL) AS a_same_priced_rn,
  (SELECT MIN(rn) FROM pair WHERE side = 'GOOD' AND live_side = 'GOOD') AS a_same_good_rn,
  -- v27.170: the latest night written since the F cutover, and its write's INSERT and DELETE
  (SELECT f_as_of FROM fpick) AS f_as_of, (SELECT f_built_at FROM fpick) AS f_built_at,
  (SELECT f_n FROM fpick) AS f_n, (SELECT f_rn FROM fpick) AS f_rn,
  (SELECT f_ins_jrn FROM fpick) AS f_ins_jrn, (SELECT f_del_jrn FROM fpick) AS f_del_jrn,
  -- v27.171: the saved judgement's rows for the latest night's write (NULL when none: C13's copies
  -- would test nothing)
  (SELECT NULLIF(COUNT(*), 0) FROM bjbase
   WHERE as_of = (SELECT MAX(as_of) FROM hbase)
     AND built_at = (SELECT MAX(built_at) FROM hbase WHERE as_of = (SELECT MAX(as_of) FROM hbase))) AS bj_n;
"""

# v27.170: the write record F1 reads, as the acceptance's f_dml reads it (plan table id swappable for a
# simulated pass written to a copy), and the night F1's copies doctor
JBASE = """CREATE TEMP TABLE jbase AS
SELECT parent_job_id, creation_time, statement_type, 'DONE' AS state,
       CAST(NULL AS STRUCT<reason STRING>) AS error_result,
       STRUCT('onyga-482313' AS project_id, 'OI' AS dataset_id, 'FACT_PLAN_NEXT_WEEK' AS table_id) AS destination_table,
       STRUCT(dml_statistics.inserted_row_count AS inserted_row_count,
              dml_statistics.deleted_row_count AS deleted_row_count) AS dml_statistics,
       ROW_NUMBER() OVER (ORDER BY creation_time, job_id) AS jrn
FROM {jobs}
WHERE creation_time >= TIMESTAMP '{cut}' AND state = 'DONE' AND error_result IS NULL
  AND statement_type IN ('INSERT', 'DELETE')
  AND destination_table.project_id = 'onyga-482313' AND destination_table.dataset_id = 'OI'
  AND destination_table.table_id = '{table_id}';
"""

FPICK = """CREATE TEMP TABLE fpick AS
WITH fp AS (SELECT as_of, MAX(built_at) AS built_at, COUNT(*) AS n, MIN(rn) AS rn
            FROM hbase WHERE built_at >= TIMESTAMP '{cut}' GROUP BY as_of
            QUALIFY ROW_NUMBER() OVER (ORDER BY as_of DESC) = 1),
fi AS (SELECT j.jrn, j.parent_job_id, j.creation_time
       FROM fp JOIN jbase j ON j.statement_type = 'INSERT' AND j.creation_time >= fp.built_at
                           AND j.creation_time < TIMESTAMP_ADD(fp.built_at, INTERVAL 1 HOUR)
       WHERE TRUE QUALIFY ROW_NUMBER() OVER (ORDER BY j.creation_time) = 1),
fd AS (SELECT d.jrn
       FROM fi JOIN jbase d ON d.parent_job_id = fi.parent_job_id AND d.statement_type = 'DELETE'
                           AND d.creation_time <= fi.creation_time
       WHERE TRUE QUALIFY ROW_NUMBER() OVER (ORDER BY d.creation_time DESC) = 1)
SELECT (SELECT as_of FROM fp) AS f_as_of, (SELECT built_at FROM fp) AS f_built_at,
       (SELECT n FROM fp) AS f_n, (SELECT rn FROM fp) AS f_rn,
       (SELECT jrn FROM fi) AS f_ins_jrn, (SELECT jrn FROM fd) AS f_del_jrn;
"""


def raw(s):
    if '"""' in s or s.endswith('"'):
        raise ValueError("a check text cannot be held in a raw triple-quoted string")
    return 'r"""' + s + '"""'


def build_script(judge_source, plan_source=PLAN, jobs_table_id="FACT_PLAN_NEXT_WEEK", build_judge_source=BUILD_J):
    acc_plan = acceptance_query()
    cut = f_cutover()
    pl, c23 = health_ctes()
    acc_health = (f"WITH {pl.replace(PLAN, '__HH__')},\n{c23},\n"
                  "b AS (SELECT '' AS n, 0.0 AS measured, '' AS threshold, '' AS status, '' AS detail\n"
                  "      FROM UNNEST([1]) WHERE FALSE UNION ALL SELECT * FROM c23)\n"
                  "SELECT 'H23M plan_window_complete_days measured (V_ENGINE_HEALTH c23)' AS check_name,\n"
                  "       CAST(measured AS INT64) AS violations, status AS detail FROM b\n"
                  "UNION ALL\n"
                  "SELECT 'H23S plan_window_complete_days status is RED (V_ENGINE_HEALTH c23)',\n"
                  "       IF(status = 'RED', 1, 0), detail FROM b")
    parts = [
        f"DECLARE acc_plan STRING DEFAULT {raw(acc_plan)};",
        f"DECLARE acc_health STRING DEFAULT {raw(acc_health)};",
        f"CREATE TEMP TABLE jsnap AS SELECT * FROM {judge_source};",
        "CREATE TEMP TABLE hbase AS SELECT *, ROW_NUMBER() OVER (ORDER BY as_of, plan, campaign_id, keyword_id) AS rn "
        f"FROM {plan_source};",
        JBASE.format(jobs=JOBS, cut=cut, table_id=jobs_table_id),
        f"CREATE TEMP TABLE bjbase AS SELECT * FROM {build_judge_source};",
        FPICK.format(cut=cut),
        PICK,
        "CREATE TEMP TABLE res (copy STRING, check_name STRING, violations INT64, detail STRING);",
        "INSERT INTO res SELECT 'PICK', 'PICK', 0, TO_JSON_STRING(p) FROM pick p;",
    ]
    for i, (name, (hsql, _, _)) in enumerate(COPIES.items()):
        hh, jj, bj = f"hh{i}", f"jj{i}", f"bj{i}"
        parts.append(f"CREATE TEMP TABLE {hh} AS {hsql};")
        parts.append(f"CREATE TEMP TABLE {jj} AS {JCOPIES.get(name, JLIVE)};")
        parts.append(f"CREATE TEMP TABLE {bj} AS {BJCOPIES.get(name, BJLIVE)};")
        parts.append("EXECUTE IMMEDIATE FORMAT(\"INSERT INTO res SELECT '%s', check_name, violations, NULL "
                     f"FROM (%s)\", '{name}', REPLACE(REPLACE(REPLACE(acc_plan, '__HH__', '{hh}'), '__JJ__', '{jj}'), "
                     f"'__BJ__', '{bj}'));")
        parts.append("EXECUTE IMMEDIATE FORMAT(\"INSERT INTO res SELECT '%s', check_name, violations, detail "
                     f"FROM (%s)\", '{name}', REPLACE(acc_health, '__HH__', '{hh}'));")
    parts.append("SELECT copy, check_name, violations, detail FROM res ORDER BY copy, check_name;")
    return "\n".join(parts)


def run(args, timeout=None):
    return subprocess.run(BQ + args, capture_output=True, text=True, timeout=timeout)


def view_tie():
    pl, c23 = health_ctes()
    r = run(["--format=json", "query", "--use_legacy_sql=false", "--nouse_cache",
             "SELECT view_definition FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS` "
             "WHERE table_name = 'V_ENGINE_HEALTH'"])
    if r.returncode != 0:
        print(r.stdout[-2000:], r.stderr[-2000:])
        return 2
    rows_ = json.loads(r.stdout)
    deployed = norm(rows_[0]["view_definition"]) if rows_ else ""
    missing = [n for n, t in (("pl/plb", pl), ("c23", c23)) if norm(t) not in deployed]
    if missing:
        print("the deployed V_ENGINE_HEALTH does not carry this file's", missing, "text: run it on the deployed body")
        return 1
    print("the deployed V_ENGINE_HEALTH carries the file's pl / plb / c23 text")
    return 0


def submit(judge_source, plan_source=PLAN, jobs_table_id="FACT_PLAN_NEXT_WEEK", build_judge_source=BUILD_J):
    try:
        script = build_script(judge_source, plan_source, jobs_table_id, build_judge_source)
    except Exception as e:  # noqa: BLE001
        print("could not build the script:", e)
        return None, (1 if "placeholder" in str(e) else 2)
    if os.environ.get("PLAN_CLOCK_CONTROLS_SQL"):
        open(os.environ["PLAN_CLOCK_CONTROLS_SQL"], "w").write(script)
    tie = view_tie()
    if tie:
        return None, tie
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
    objs = json.loads(r.stdout)
    print(f"job {job}: {slot_s:,.1f} slot-seconds, {len(objs)} result rows")
    pick = next((json.loads(x["detail"]) for x in objs if x.get("copy") == "PICK"), {})
    if not pick:
        print("the PICK row did not parse")
        return 2
    print("doctored rows:", pick)
    got = {}
    for x in objs:
        if x.get("copy") != "PICK":
            key = x["check_name"].split(" ")[0]
            got[(x["copy"], key)] = int(x["violations"])
    bad = []
    live = {k[1]: v for k, v in got.items() if k[0] == "LIVE"}
    print("LIVE:", len(live), "readings;", "non-zero:", {k: v for k, v in live.items() if v} or "none")
    if not live or any(live.values()):
        bad.append(("LIVE", "every check 0", live))
    for name, (_, targets, needs) in COPIES.items():
        if targets is None:
            continue
        missing = [c for c in needs if pick.get(c) is None]
        if missing:
            print(f"NOT EXERCISED {name:32} no row to doctor on this partition ({', '.join(missing)} NULL)")
            bad.append((name, "NOT EXERCISED", missing))
            continue
        for chk, want in targets:
            v = got.get((name, chk))
            ok = (v is not None and v >= 1) if want == "GE1" else (v == want)
            others = {k[1]: x for k, x in got.items()
                      if k[0] == name and k[1] not in [t[0] for t in targets] and x != live.get(k[1])}
            flag = "ok " if ok else "BAD"
            print(f"{flag} {name:32} {chk} = {v} (expected {want}); other checks that moved: {others or 'none'}")
            if not ok:
                bad.append((name, chk, v, want))
    if bad:
        print("MISMATCHES / NOT EXERCISED:", bad)
        return 1
    return 0


def main():
    judge_source = VIEW
    if "--judge-table" in sys.argv:
        judge_source = "`" + sys.argv[sys.argv.index("--judge-table") + 1] + "`"
    plan_source = PLAN
    if "--plan-table" in sys.argv:
        plan_source = "`" + sys.argv[sys.argv.index("--plan-table") + 1] + "`"
    jobs_table_id = "FACT_PLAN_NEXT_WEEK"
    if "--jobs-table-id" in sys.argv:
        jobs_table_id = sys.argv[sys.argv.index("--jobs-table-id") + 1]
    build_judge_source = BUILD_J
    if "--build-judge-table" in sys.argv:
        build_judge_source = "`" + sys.argv[sys.argv.index("--build-judge-table") + 1] + "`"
    if "--collect" in sys.argv:
        return collect(sys.argv[sys.argv.index("--collect") + 1])
    job, rc = submit(judge_source, plan_source, jobs_table_id, build_judge_source)
    if rc or "--submit" in sys.argv:
        return rc
    return collect(job)


if __name__ == "__main__":
    sys.exit(main())
