#!/usr/bin/env python3
"""K13 (plan §5, review of holdout-t2 2026-10-04): the weekly book's MEND arm 2 never prices a control.

tools/build_weekly_book.py trims bids in every losing campaign (MEND_SQL, on unless --no-mend). Its
holdout gate is in MEND_SQL itself. This check reads MEND_SQL from the tool's source (ast, no import, so
it runs the text the book runs), and runs it on the live trial's HOLDOUT units:
  gated     MEND_SQL as written                      violations = its rows on the controls; PASS = 0
  ungated   the same text with the gate removed      the negative control: > 0 whenever a control loses
                                                    (measured 2026-10-04 on the 12 trial-2 controls: 5)
Also: MEND_SQL carries exactly one V_HOLDOUT_ARM reference and exactly one gate predicate (K7b's half).

The gate binds from CURRENT_DATE('America/Los_Angeles') >= gate_from; trial 2's own controls bind from
LA 2026-10-06. Run it on LA 2026-10-06 or later, before the first weekly book (plan Task 8), or pass
--as-of to read the gate on a given LA date. Read-only. Exit 0 = PASS, 1 = FAIL, 2 = could not run.

  --arm-view T     read T instead of `onyga-482313.OI.V_HOLDOUT_ARM` (a TMP_ copy, for a rehearsal)
  --controls IDS   comma-separated campaign ids instead of the live trial's HOLDOUT units
  --as-of DATE     the LA date the gate is read on (default: CURRENT_DATE('America/Los_Angeles'))
  --prefix P       read OI.<P>V_HOLDOUT_ARM, <P>DE_HOLDOUT_ASSIGNMENT and <P>V_HOLDOUT_TRIAL (the runbook's
                   rehearsal copies, P = TMP_HT2_R_)
"""
import argparse
import ast
import json
import os
import subprocess
import sys

PROJECT = 'onyga-482313'
TOOL = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'tools', 'build_weekly_book.py')
GATE = "AND NOT (h.cid IS NOT NULL AND CURRENT_DATE('America/Los_Angeles') >= h.gate_from)"
CLOCK = "CURRENT_DATE('America/Los_Angeles') >= h.gate_from"
ARM = f'`{PROJECT}.OI.V_HOLDOUT_ARM`'


def consts():
    tree = ast.parse(open(TOOL).read())
    out = {}
    for n in tree.body:
        if isinstance(n, ast.Assign) and len(n.targets) == 1 and isinstance(n.targets[0], ast.Name) \
                and n.targets[0].id in ('MEND_SQL', 'MEND_MIN_SPEND_28D'):
            out[n.targets[0].id] = ast.literal_eval(n.value)
    return out


def bq(sql):
    r = subprocess.run(['bq', 'query', f'--project_id={PROJECT}', '--use_legacy_sql=false', '--nouse_cache',
                        '--format=json', '--max_rows=1000', sql], capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stdout + r.stderr)
        sys.exit(2)
    t = r.stdout
    return json.loads(t[t.index('['):]) if '[' in t else []


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--arm-view')
    ap.add_argument('--controls')
    ap.add_argument('--as-of')
    ap.add_argument('--prefix', default='')
    a = ap.parse_args()
    c = consts()
    text = c.get('MEND_SQL', '')
    n_arm, n_gate = text.count('V_HOLDOUT_ARM'), text.count(GATE)
    print(f'K13 text: MEND_SQL V_HOLDOUT_ARM references {n_arm} (expected 1), gate predicates {n_gate} (expected 1)')
    if n_arm != 1 or n_gate != 1:
        print('K13 FAIL: the gate is not in MEND_SQL exactly once')
        return 1
    sql = text.replace('{P}', PROJECT).replace('{MINSPEND}', repr(float(c['MEND_MIN_SPEND_28D'])))
    if a.prefix and not a.prefix.startswith('TMP_'):
        print('K13: --prefix must start with TMP_')
        return 2
    arm_view = a.arm_view or (a.prefix + 'V_HOLDOUT_ARM' if a.prefix else None)
    if arm_view:
        sql = sql.replace(ARM, f'`{arm_view}`' if '.' in arm_view else f'`{PROJECT}.OI.{arm_view}`')
    if a.as_of:
        sql = sql.replace(CLOCK, f"DATE '{a.as_of}' >= h.gate_from")
    if a.controls:
        ids = [x.strip() for x in a.controls.split(',') if x.strip()]
        ctl = 'SELECT id FROM UNNEST([%s]) AS id' % ', '.join("'%s'" % i for i in ids)
    else:
        ctl = (f"SELECT a.unit_id FROM `{PROJECT}.OI.{a.prefix}DE_HOLDOUT_ASSIGNMENT` a "
               f"JOIN `{PROJECT}.OI.{a.prefix}V_HOLDOUT_TRIAL` t "
               f"USING (trial_id) WHERE t.is_live AND a.arm = 'HOLDOUT' AND a.unit_type = 'CAMPAIGN'")
    ungated = sql.replace(GATE if not a.as_of else GATE.replace(CLOCK, f"DATE '{a.as_of}' >= h.gate_from"), '')
    res = {}
    for name, body in (('gated', sql), ('ungated', ungated)):
        rows = bq(f"WITH ctl AS ({ctl}) SELECT COUNT(*) AS n, COUNT(DISTINCT m.campaign_id) AS c, "
                  f"(SELECT COUNT(*) FROM ctl) AS n_ctl, "
                  f"STRING_AGG(DISTINCT m.campaign_id ORDER BY m.campaign_id) AS ids "
                  f"FROM ({body}) m WHERE m.campaign_id IN (SELECT * FROM ctl)")
        res[name] = rows[0] if rows else {'n': None}
        r = res[name]
        print(f"K13 {name:8s}: {r.get('n')} trim(s) on {r.get('c')} of {r.get('n_ctl')} control(s) {r.get('ids') or ''}")
    if res['gated'].get('n') is None or int(res['gated'].get('n_ctl') or 0) == 0:
        print('K13 FAIL: no control was read (an empty input passes nothing)')
        return 1
    if int(res['gated']['n']) != 0:
        print('K13 FAIL: the gated mend prices a control')
        return 1
    if int(res['ungated']['n'] or 0) == 0:
        print('K13 PASS (vacuous today: no control is losing with a trimmable keyword, so the ungated text reads 0 too)')
    else:
        print(f"K13 PASS: gated 0, ungated {res['ungated']['n']} (the gate withholds them)")
    return 0


if __name__ == '__main__':
    sys.exit(main())
