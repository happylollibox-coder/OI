#!/usr/bin/env bash
# =============================================================================================
# 2026-10-05 — HOLDOUT TRIAL 2: ROLLBACK of 2026-10-05_holdout_t2_deploy.sh (plan
# docs/superpowers/plans/2026-10-03-holdout-restart.md, Task 8 / Task R).
#
#   --deploy     restore the live objects from .tmp/holdout_t2_predeploy/ (refuses while a pass runs)
#   --rehearse   restore the TMP_HT2_R_ copies from .tmp/holdout_t2_rehearse/predeploy/ and MEASURE the
#                gate the old bodies give on the copies (the numbers below come from that)
#   --dir DIR    restore from DIR instead
# Run from the repo root of the checkout the deploy ran from (the script cds to the git top level).
#
# WHAT IT DOES. Each object the deploy REPLACED has its pre-deploy DDL saved by the deploy in the
# directory above (<name>.ddl.sql, INFORMATION_SCHEMA's ddl, saved only when the deployed body equalled
# its pre-branch file). The rollback restores them in the REVERSE deploy order:
#   V_ENGINE_HEALTH, V_HOLDOUT_READOUT, V_FAMILY_SEAT_REGISTER, V_PLAN_WINDOW_JUDGMENT, SP_ENGINE_PREFLIGHT,
#   V_HOLDOUT_ELIGIBLE, SP_ASSIGN_HOLDOUT
# (CREATE VIEW / PROCEDURE turned into CREATE OR REPLACE), re-reads each body from INFORMATION_SCHEMA and
# compares it with the saved one. An object with no saved DDL was not replaced and is left as it is.
# V_HOLDOUT_ELIGIBLE goes back BEFORE SP_ASSIGN_HOLDOUT: the old procedure under the new population view
# appends the 5 Bunny campaigns to trial 1 for good (review fix 3); the reverse order never pairs them.
#
# WHAT STAYS. DE_HOLDOUT_TRIAL (3 registry rows), DE_HOLDOUT_BASELINE (the founding baseline), trial 2's
# 59 rows in DE_HOLDOUT_ASSIGNMENT, V_HOLDOUT_TRIAL and V_HOLDOUT_ARM. The tables are append-only (plan
# house rules): nothing here deletes a row. The three bulksheet tools are code: they keep reading
# V_HOLDOUT_ARM (trial 2's 12 controls, gate 2026-10-05 .. 2027-01-26) until the merge is reverted in git.
#
# WHAT THE GATE DOES AFTER A ROLLBACK. The old readers read DE_HOLDOUT_ASSIGNMENT directly, every trial, and
# none reads the registry, so they take the UNION of trial 1's 14 controls and trial 2's 12 (no campaign is a
# control of both). MEASURED on copies (REHEARSED below): each restored reader's own holdout CTE text over the
# assignment copy holding both trials, the LA day varied; campaigns held:
#                                 10-05   10-06   12-22   12-23   2027-01-26   2027-01-27
#   SP_ENGINE_PREFLIGHT hold        14      26      26      12        12            0
#     (trial 1 to its trial_end 2026-12-22; trial 2 from its eligible_from 2026-10-06 to 2027-01-26)
#   V_PLAN_WINDOW_JUDGMENT holdout  14      26      26      26        26           26
#   V_FAMILY_SEAT_REGISTER no-sheet 14      26      26      26        26           26
#     (MIN(eligible_from) over every trial and no end: trial 1's 14 and trial 2's 12 held for good)
#   on 10-05 the 14 are all trial 1; from 10-06 to 12-22 14 trial 1 + 12 trial 2; the preflight's 12 are trial 2.
#   SP_ASSIGN_HOLDOUT (trial 1's constants) under the restored population view, CALLed on the copy: appended 0
#     rows (trial 1 69, trial 2 59 before and after); K2 then 0.
#   V_HOLDOUT_READOUT: trial 1 by its literal (69 rows; NOT_YET names 2027-01-05, CENSORED and PRE_WINDOW_CHANGE
#     rows of trial 1).
#   V_ENGINE_HEALTH c33 holdout_unit_changed: trial 1 by its literal, AMBER on trial 1's pre-window changes;
#     trial 2's controls are not watched. c18 seat_holdout_row_on_sheet: GREEN, "the arm starts 2026-09-01"
#     (every trial's HOLDOUT rows, no end).
# So after a rollback the engine holds both trials' controls from 2026-10-06 (trial 1's register and plan
# holds never end), the bulksheet tools hold trial 2's only, and no alarm watches trial 2. Fix forward and
# re-run the deploy (steps 1-2 stay written and are skipped; each replaced object is drift-checked against
# the restored body, which equals its saved DDL).
#
# REHEARSED 2026-10-04 09:34:28-09:36:52 UTC on the TMP_HT2_R_ copies left by the deploy rehearsal (dates
# pinned to 2026-10-05), exit 0: the seven restored in the order above, each re-read body = its saved DDL; the
# measurements above (the gate read 0.9 slot-s, the CALL 104.3 slot-s, the readout and board rows 101.0 slot-s).
# Every copy was dropped afterwards.
# =============================================================================================
set -euo pipefail

MODE=""
DIR=""
while [ $# -gt 0 ]; do
  case $1 in
    --deploy) MODE=deploy ;;
    --rehearse) MODE=rehearse ;;
    --dir) DIR=${2:?--dir needs a directory}; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) sed -n '2,12p' "$0" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$MODE" ] || { sed -n '2,12p' "$0" >&2; exit 2; }

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
# shellcheck source=scripts/bigquery/migrations/2026-10-05_holdout_t2_lib.sh
. scripts/bigquery/migrations/2026-10-05_holdout_t2_lib.sh

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
if [ "$MODE" = rehearse ]; then
  PFX=$REHEARSE_PREFIX
  XF="--prefix $REHEARSE_PREFIX --pin $REHEARSE_PIN"
  DIR=${DIR:-.tmp/holdout_t2_rehearse/predeploy}
  WORK=.tmp/holdout_t2_rehearse/rollback_$STAMP
  RUN_TAG=rehrb
else
  DIR=${DIR:-.tmp/holdout_t2_predeploy}
  WORK=.tmp/holdout_t2_rollback_$STAMP
  RUN_TAG=rollback
fi
mkdir -p "$WORK"
LOG=$WORK/run.log
RECORD=$WORK/checks.tsv
: > "$RECORD"
[ -d "$DIR" ] || die "no saved DDL directory $DIR"
log "holdout trial 2 rollback: mode $MODE, from $DIR, log $LOG"

if [ "$MODE" = deploy ]; then
  log "no pass may run while the readers change"
  GUARD_OPTS=--running-only pass_guard 0 || die "a pass is running: wait for it to log its last step"
fi

REVERSE=$(printf '%s\n' $REPLACED | sed -n '1!G;h;$p' | tr '\n' ' ')
for n in $REVERSE; do
  saved=$DIR/$n.ddl.sql
  if [ ! -f "$saved" ]; then
    log "  $(obj "$n"): no saved DDL (the deploy did not replace it): left as is"
    record rollback "$n" "not replaced" "-"
    continue
  fi
  xf "$saved" "$WORK/$n.restore.sql" --create-or-replace --expect "$n"
  if ddl_of "$(obj "$n")" "$WORK/$n.current.sql" \
     && tool same "$WORK/$n.current.sql" "$WORK/$n.restore.sql" > /dev/null; then
    log "  $(obj "$n"): already the saved body: left as is"
    record rollback "$n" "already restored" "-"
    continue
  fi
  q "restore_$n" "$WORK/$n.restore.sql"
  ddl_of "$(obj "$n")" "$WORK/$n.after.sql" || die "$(obj "$n") not found after the restore"
  tool same "$WORK/$n.after.sql" "$WORK/$n.restore.sql" > "$WORK/$n.after.txt" \
    || { cat "$WORK/$n.after.txt"; die "$(obj "$n"): restored body != saved DDL"; }
  log "  $(obj "$n"): restored; re-read body = saved DDL ($(cat "$WORK/$n.after.txt"))"
  record rollback "$n" restored "body = $saved"
done

if [ "$MODE" = deploy ]; then
  log "ROLLED BACK. The registry, the baseline and trial 2's rows stay; the tools read V_HOLDOUT_ARM until the merge is reverted."
  exit 0
fi

# ---------------------------------------------------------------------------------------------
# rehearsal: measure what the restored (old) bodies do on the copies
# ---------------------------------------------------------------------------------------------
log "MEASURE the gate after the rollback, on the copies (old CTE texts as restored, the LA day varied)"
ASG='`'"$PROJECT.$DS.$(obj DE_HOLDOUT_ASSIGNMENT)"'`'
python3 - "$WORK" "$REHEARSE_PIN" "$ASG" > "$WORK/gate.sql" <<'PY'
import re, subprocess, sys
work, pin, asg = sys.argv[1:4]
def cte(name, cte_name):
    return subprocess.check_output(['python3', 'scripts/bigquery/migrations/2026-10-05_holdout_t2_sqltool.py',
                                    'cte', '%s/%s.restore.sql' % (work, name), cte_name], text=True)
days = ['2026-10-05', '2026-10-06', '2026-12-22', '2026-12-23', '2027-01-26', '2027-01-27']
hold, judg, reg = cte('SP_ENGINE_PREFLIGHT', 'hold'), cte('V_PLAN_WINDOW_JUDGMENT', 'holdout'), cte('V_FAMILY_SEAT_REGISTER', 'holdout')
pinned = "DATE '%s'" % pin
assert pinned in hold, 'the restored preflight hold CTE does not carry the pinned date'
blocks = []
for d in days:
    blocks.append("SELECT DATE '%s' AS d, 'SP_ENGINE_PREFLIGHT hold' AS reader, h.cid AS cid FROM (%s) h" % (d, hold.replace(pinned, "DATE '%s'" % d)))
    blocks.append("SELECT DATE '%s', 'V_PLAN_WINDOW_JUDGMENT holdout', h.cid FROM (%s) h WHERE DATE '%s' >= h.eligible_from" % (d, judg, d))
    blocks.append("SELECT DATE '%s', 'V_FAMILY_SEAT_REGISTER holdout (no sheet row)', h.campaign_id FROM (%s) h WHERE DATE '%s' >= h.eligible_from" % (d, reg, d))
print("""WITH c AS (
  SELECT unit_id AS cid, LOGICAL_OR(trial_id = 'HOLDOUT-2026Q4-CAMPAIGN') AS t1,
         LOGICAL_OR(trial_id = 'HOLDOUT-2026Q4-CAMPAIGN-T2') AS t2
  FROM %s WHERE unit_type = 'CAMPAIGN' AND arm = 'HOLDOUT' GROUP BY 1),
g AS (
%s)
SELECT FORMAT('gate %%t %%s', g.d, g.reader) AS check_name, COUNT(DISTINCT g.cid) AS violations,
       FORMAT('held %%d: trial-1-only %%d, trial-2-only %%d, both %%d, neither %%d', COUNT(DISTINCT g.cid),
              COUNT(DISTINCT IF(c.t1 AND NOT c.t2, g.cid, NULL)), COUNT(DISTINCT IF(c.t2 AND NOT c.t1, g.cid, NULL)),
              COUNT(DISTINCT IF(c.t1 AND c.t2, g.cid, NULL)), COUNT(DISTINCT IF(c.cid IS NULL, g.cid, NULL))) AS detail
FROM g LEFT JOIN c ON c.cid = g.cid
GROUP BY g.d, g.reader ORDER BY g.d, g.reader""" % (asg, '\n  UNION ALL '.join(blocks)))
PY
q gate "$WORK/gate.sql"
tool rows < "$WORK/gate.out" > "$WORK/gate.rows" || die "gate measurement returned no row"
python3 - "$WORK/gate.rows" "$RECORD" <<'PY' | tee -a "$LOG"
import sys, json, datetime
with open(sys.argv[2], 'a') as out:
    for l in open(sys.argv[1]):
        r = json.loads(l)
        print('  %s | %s' % (r['check_name'], r['detail']))
        out.write('%s\tafter-rollback\t%s\t%s\t%s\n' % (datetime.datetime.now(datetime.timezone.utc).strftime('%F %T'), r['check_name'], r['violations'], r['detail']))
PY

# the restored procedure on the copies: does it append anything (to trial 1)?
tool writes "$WORK/SP_ASSIGN_HOLDOUT.restore.sql" | grep -v "$PFX" && die "the restored procedure writes a live object" || true
cat > "$WORK/asg_count.sql" <<SQL
SELECT 'assignment_rows' AS check_name, COUNT(*) AS violations,
       FORMAT('trial 1 %d, trial 2 %d', COUNTIF(trial_id = 'HOLDOUT-2026Q4-CAMPAIGN'), COUNTIF(trial_id = '$T2')) AS detail
FROM $ASG
SQL
q asg_before "$WORK/asg_count.sql"
before=$(tool rows < "$WORK/asg_before.out" | python3 -c 'import sys, json; print(json.loads(sys.stdin.readline())["detail"])')
printf 'CALL `%s.%s.%s`();\n' "$PROJECT" "$DS" "$(obj SP_ASSIGN_HOLDOUT)" > "$WORK/call.sql"
qlong call_old_assign "$WORK/call.sql"
q asg_after "$WORK/asg_count.sql"
after=$(tool rows < "$WORK/asg_after.out" | python3 -c 'import sys, json; print(json.loads(sys.stdin.readline())["detail"])')
log "  restored SP_ASSIGN_HOLDOUT CALLed on the copies: $before -> $after"
record after-rollback "CALL restored SP_ASSIGN_HOLDOUT" "-" "$before -> $after"
tool select scripts/bigquery/tests/HOLDOUT_RESTART_acceptance.sql K2 > "$WORK/k2.raw.sql"
xf "$WORK/k2.raw.sql" "$WORK/k2.sql" --script --quoted
q k2 "$WORK/k2.sql"
tool rows < "$WORK/k2.out" | python3 -c 'import sys, json; r = json.loads(sys.stdin.readline()); print("  K2 on the copy after the CALL: %s | %s" % (r["violations"], r["detail"]))' | tee -a "$LOG"

# the restored readout and board rows (date pinned)
cat > "$WORK/ro.sql" <<SQL
SELECT 'readout' AS check_name, COUNT(*) AS violations,
       FORMAT('states %s · NOT_YET verdict: %s', STRING_AGG(DISTINCT state, ', '), IFNULL(MAX(IF(state = 'NOT_YET', verdict, NULL)), 'none')) AS detail
FROM \`$PROJECT.$DS.$(obj V_HOLDOUT_READOUT)\`;
SELECT CONCAT('board ', check_name) AS check_name, CAST(measured AS INT64) AS violations,
       FORMAT('%s · %s', status, SUBSTR(detail, 1, 300)) AS detail
FROM \`$PROJECT.$DS.$(obj V_ENGINE_HEALTH)\`
WHERE check_name IN ('seat_holdout_row_on_sheet', 'holdout_unit_changed')
SQL
q ro "$WORK/ro.sql"
tool rows < "$WORK/ro.out" | python3 -c '
import sys, json
for l in sys.stdin:
    r = json.loads(l); print("  %s = %s | %s" % (r["check_name"], r["violations"], r["detail"]))' | tee -a "$LOG"
log "REHEARSED ROLLBACK DONE. Record: $RECORD"
