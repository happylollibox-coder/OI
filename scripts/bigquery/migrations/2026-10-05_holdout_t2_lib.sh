# shellcheck shell=bash
# =============================================================================================
# Shared helpers of the holdout trial 2 runbook (2026-10-05_holdout_t2_deploy.sh and _rollback.sh).
# Sourced, never run. bash 3.2 (macOS /bin/bash): no mapfile, no associative arrays, and an empty
# array is expanded as ${a[@]+"${a[@]}"} under set -u.
# Plan: docs/superpowers/plans/2026-10-03-holdout-restart.md, Task 8 (the runbook = Task R).
# =============================================================================================
PROJECT=onyga-482313
DS=OI
T2=HOLDOUT-2026Q4-CAMPAIGN-T2
DEPLOY_DATE=2026-10-05
REHEARSE_PREFIX=TMP_HT2_R_
REHEARSE_PIN=2026-10-05
MIG=scripts/bigquery/migrations
TOOL=$MIG/2026-10-05_holdout_t2_sqltool.py
# the objects the deploy replaces, in deploy order (the rollback restores them in the reverse order)
REPLACED="SP_ASSIGN_HOLDOUT V_HOLDOUT_ELIGIBLE SP_ENGINE_PREFLIGHT V_PLAN_WINDOW_JUDGMENT V_FAMILY_SEAT_REGISTER V_HOLDOUT_READOUT V_ENGINE_HEALTH"

PFX=""            # '' when deploying; REHEARSE_PREFIX when rehearsing
XF=""             # extra sqltool xform options ('' or '--prefix P --pin D')
WORK=""           # this run's scratch directory (.tmp/...)
LOG=""            # this run's log file
RECORD=""         # this run's check record (TSV)
RUN_TAG=run

log() {
  local line
  line="$(date -u '+%H:%M:%S') $*"
  printf '%s\n' "$line" >&2      # stderr: a function's stdout may be a value captured by $( )
  if [ -n "$LOG" ]; then printf '%s\n' "$line" >> "$LOG"; fi
}
die() { log "STOP: $*"; exit 1; }
tool() { python3 "$TOOL" "$@"; }
obj() { printf '%s%s' "$PFX" "$1"; }                       # the name written in this mode
file_of() { case $1 in SP_*) printf 'scripts/bigquery/procedures/%s.sql' "$1" ;; *) printf 'scripts/bigquery/views/%s.sql' "$1" ;; esac; }
record() { printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u '+%F %T')" "$1" "$2" "$3" "$4" >> "$RECORD"; }

# xf FILE OUT [xform options]: the text this mode sends (whole-line comments stripped; renamed and
# date-pinned when rehearsing)
xf() {
  local f=$1 out=$2
  shift 2
  # shellcheck disable=SC2086
  tool xform "$f" $XF "$@" > "$out"
}

# cost TAG JOB: slot-seconds, MB billed and wall time of a finished job, into the log and the record
cost() {
  local tag=$1 job=$2 c
  c=$(bq --project_id="$PROJECT" show -j --format=json "$job" 2>/dev/null | python3 -c '
import sys, json
d = json.load(sys.stdin); s = d.get("statistics", {})
slot = float(s.get("totalSlotMs") or 0) / 1000
mb = float((s.get("query") or {}).get("totalBytesBilled") or 0) / 1e6
wall = (float(s.get("endTime") or 0) - float(s.get("startTime") or 0)) / 1000
print("%.1f slot-s, %.1f MB billed, %.0f s" % (slot, mb, wall))' 2>/dev/null || echo "cost unavailable")
  log "    cost $tag ($job): $c"
  record "cost" "$tag" "$job" "$c"
}

# q TAG SQLFILE: a synchronous query (prettyjson) -> $WORK/TAG.out; stops the run on an error
q() {
  local tag=$1 sql=$2 job
  job="ht2_${RUN_TAG}_${tag}_$(date +%s)_$RANDOM"
  if ! bq query --project_id="$PROJECT" --use_legacy_sql=false --nouse_cache --format=prettyjson \
         --max_rows=10000 --job_id="$job" "$(cat "$sql")" > "$WORK/$tag.out" 2> "$WORK/$tag.err"; then
    log "  query $tag failed (job $job):"
    tail -c 3000 "$WORK/$tag.out" | sed 's/^/    /'
    tail -c 1000 "$WORK/$tag.err" | sed 's/^/    /'
    die "query $tag failed"
  fi
  cost "$tag" "$job"
}

# qlong TAG SQLFILE: a long job, --nosync, polled with 'bq wait JOB 60' until DONE. Sets LONG_JOB.
LONG_JOB=""
qlong() {
  local tag=$1 sql=$2 job state t0 err
  job="ht2_${RUN_TAG}_${tag}_$(date +%s)_$RANDOM"
  t0=$(date +%s)
  if ! bq query --project_id="$PROJECT" --use_legacy_sql=false --nouse_cache --nosync --job_id="$job" \
         "$(cat "$sql")" > "$WORK/$tag.submit" 2>&1; then
    sed 's/^/    /' "$WORK/$tag.submit"
    die "could not submit $tag"
  fi
  log "  $tag submitted as $job (--nosync; polling with bq wait 60)"
  while :; do
    bq --project_id="$PROJECT" wait --fail_on_error=false "$job" 60 > /dev/null 2>&1 || true
    state=$(bq --project_id="$PROJECT" show -j --format=json "$job" | python3 -c 'import sys, json; print(json.load(sys.stdin)["status"]["state"])')
    if [ "$state" = DONE ]; then break; fi
    log "    $tag $state after $(( $(date +%s) - t0 )) s"
  done
  err=$(bq --project_id="$PROJECT" show -j --format=json "$job" | python3 -c '
import sys, json
e = json.load(sys.stdin)["status"].get("errorResult")
print(e["message"] if e else "")')
  if [ -n "$err" ]; then
    log "  $tag FAILED: $err"
    die "job $job failed"
  fi
  LONG_JOB=$job
  cost "$tag" "$job"
}

# last_rows JOB OUT: the result of a script's last statement (the suites end with their result SELECT)
last_rows() {
  local job=$1 out=$2 child
  child=$(bq --project_id="$PROJECT" ls -j --parent_job_id="$job" -n 5000 --format=json | python3 -c '
import sys, json
d = json.load(sys.stdin)
d.sort(key=lambda j: int(j["statistics"]["creationTime"]))
print(d[-1]["jobReference"]["jobId"] if d else "")')
  if [ -z "$child" ]; then
    bq --project_id="$PROJECT" --format=json head -n 5000 -j "$job" > "$out"
  else
    bq --project_id="$PROJECT" --format=json head -n 5000 -j "$child" > "$out"
  fi
}

# ddl_of NAME OUT: the deployed DDL of table / view / routine NAME (as written in this mode) -> OUT.
# Returns 1 when the object does not exist.
ddl_of() {
  local n=$1 out=$2
  bq query --project_id="$PROJECT" --use_legacy_sql=false --nouse_cache --format=json --max_rows=10 \
    "SELECT ddl FROM \`$PROJECT.$DS.INFORMATION_SCHEMA.TABLES\` WHERE table_name = '$n'
     UNION ALL SELECT ddl FROM \`$PROJECT.$DS.INFORMATION_SCHEMA.ROUTINES\` WHERE routine_name = '$n'" \
    > "$WORK/ddl_$n.json" 2> /dev/null || die "could not read INFORMATION_SCHEMA for $n"
  python3 - "$WORK/ddl_$n.json" "$out" <<'PY'
import sys, json
rows = json.load(open(sys.argv[1]))
if not rows:
    sys.exit(1)
if len(rows) != 1:
    sys.exit('more than one object named like that')
open(sys.argv[2], 'w').write(rows[0]['ddl'])
PY
}

# columns_of NAME OUT: 'name TYPE [NOT NULL]' per column of the deployed table
columns_of() {
  bq query --project_id="$PROJECT" --use_legacy_sql=false --nouse_cache --format=json --max_rows=200 \
    "SELECT column_name, data_type, is_nullable, ordinal_position FROM \`$PROJECT.$DS.INFORMATION_SCHEMA.COLUMNS\` WHERE table_name = '$1'" \
    | tool bqcolumns > "$2"
}

# pass_guard NEED_MINUTES: the deploy window (plan Task 8), read from BigQuery. 0 = open, 3 = refused.
# The definition of a pass, and why, is in the deploy script's header ("THE WINDOW").
pass_guard() {
  local need=${1:-0} rc=0
  cat > "$WORK/guard.sql" <<SQL
WITH
o AS (SELECT REGEXP_EXTRACT_ALL(routine_definition, r"SET procedure_name = '([A-Za-z0-9_]+)'") AS steps
      FROM \`$PROJECT.$DS.INFORMATION_SCHEMA.ROUTINES\` WHERE routine_name = 'SP_ORCHESTRATE_DAILY_REFRESH'),
k AS (SELECT steps[SAFE_OFFSET(0)] AS first_step, steps[SAFE_OFFSET(ARRAY_LENGTH(steps) - 1)] AS last_step,
             ARRAY_LENGTH(steps) AS n_steps FROM o),
r AS (SELECT run_id, procedure_name, started_at, finished_at FROM \`$PROJECT.$DS.LOG_PIPELINE_RUNS\`
      WHERE started_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 36 HOUR)),
p AS (SELECT r.run_id,
             MIN(IF(r.procedure_name = k.first_step, r.started_at, NULL)) AS pass_start,
             MAX(IF(r.procedure_name = k.last_step, r.finished_at, NULL)) AS pass_end,
             MAX(r.finished_at) AS last_row_at
      FROM r CROSS JOIN k GROUP BY 1),
j AS (SELECT job_id, state, creation_time
      FROM \`$PROJECT\`.\`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
      WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 36 HOUR) AND state != 'DONE'
        AND job_type = 'QUERY'
        AND REGEXP_CONTAINS(query, r'^\s*CALL\s+\`?$PROJECT\`?\.\`?$DS\`?\.\`?SP_ORCHESTRATE_DAILY_REFRESH'))
SELECT CAST(CURRENT_DATE('America/Los_Angeles') AS STRING) AS la_date,
       FORMAT_TIMESTAMP('%F %T', CURRENT_TIMESTAMP()) AS now_utc,
       k.first_step, k.last_step, k.n_steps,
       (SELECT TO_JSON_STRING(ARRAY_AGG(STRUCT(run_id, FORMAT_TIMESTAMP('%F %T', pass_start) AS pass_start,
                                               FORMAT_TIMESTAMP('%F %T', pass_end) AS pass_end,
                                               FORMAT_TIMESTAMP('%F %T', last_row_at) AS last_row_at)))
        FROM p WHERE pass_start IS NOT NULL) AS passes_json,
       (SELECT TO_JSON_STRING(ARRAY_AGG(STRUCT(job_id, state, FORMAT_TIMESTAMP('%F %T', creation_time) AS creation_time)))
        FROM j) AS jobs_json
FROM k
SQL
  bq query --project_id="$PROJECT" --use_legacy_sql=false --nouse_cache --format=json "$(cat "$WORK/guard.sql")" \
    > "$WORK/guard.json" 2> "$WORK/guard.err" \
    || { sed 's/^/    /' "$WORK/guard.json" "$WORK/guard.err"; die "the guard query failed"; }
  tool guard --date "$DEPLOY_DATE" --need-minutes "$need" ${GUARD_OPTS:-} < "$WORK/guard.json" | tee -a "$LOG" >&2 || rc=$?
  return "$rc"
}
