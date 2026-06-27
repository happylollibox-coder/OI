"""Load DERIVED weekly-plan rows for the current+future window, preserving MANUAL + past weeks."""
import datetime as dt, json, subprocess, tempfile
from . import config as C

def _bq(sql):
    out = subprocess.run(["bq", f"--project_id={C.PROJECT}", "query", "--use_legacy_sql=false"],
                         input=sql, capture_output=True, text=True)
    if out.returncode:
        raise SystemExit(out.stderr)

def load_plan(df, from_week: str):
    """Replace DERIVED rows with week_start >= from_week; MANUAL + past weeks untouched."""
    _bq(f"DELETE FROM `{C.PROJECT}.{C.DATASET}.DE_WEEKLY_PLAN` "
        f"WHERE source='DERIVED' AND week_start >= DATE('{from_week}')")
    now = dt.datetime.utcnow().isoformat()
    rows = df.where(df.notna(), None).to_dict("records")
    for r in rows:
        for k, v in r.items():
            if isinstance(v, float) and v != v:
                r[k] = None
        r["updated_at"] = now
        r["updated_by"] = "weekly_plan_tool"
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        for r in rows:
            f.write(json.dumps(r, default=str) + "\n")
        path = f.name
    out = subprocess.run(["bq", f"--project_id={C.PROJECT}", "load",
        "--source_format=NEWLINE_DELIMITED_JSON", f"{C.DATASET}.DE_WEEKLY_PLAN", path],
        capture_output=True, text=True)
    if out.returncode:
        raise SystemExit(out.stderr)
    print(f"loaded {len(rows)} DERIVED plan rows from {from_week}")
