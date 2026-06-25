# tools/strategy_profile/load.py
"""Load derived profile/main-keyword rows into BQ, preserving source='MANUAL' rows.

Strategy: DELETE the DERIVED rows for the keys we're refreshing, then INSERT the new
DERIVED rows. MANUAL rows are never touched.
"""
import datetime as dt, json, subprocess, tempfile
from . import config as C

def to_json_rows(df, updated_by: str):
    now = dt.datetime.utcnow().isoformat()
    rows = df.where(df.notna(), None).to_dict("records")
    for r in rows:
        # pandas 3.0 leaves float NaN in dict even after .where(); convert to None for valid JSON
        for k, v in r.items():
            if isinstance(v, float) and v != v:  # NaN check
                r[k] = None
        r["updated_at"] = now
        r["updated_by"] = updated_by
    return rows

def _bq(sql: str):
    out = subprocess.run(["bq", f"--project_id={C.PROJECT}", "query", "--use_legacy_sql=false"],
                         input=sql, capture_output=True, text=True)
    if out.returncode:
        raise SystemExit(out.stderr)

def load_table(df, table: str, updated_by="strategy_profile_tool"):
    """Replace only the DERIVED rows of `table` with df's rows (MANUAL rows preserved)."""
    _bq(f"DELETE FROM `{C.PROJECT}.{C.DATASET}.{table}` WHERE source='DERIVED'")
    rows = to_json_rows(df, updated_by)
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
        path = f.name
    out = subprocess.run(
        ["bq", f"--project_id={C.PROJECT}", "load", "--source_format=NEWLINE_DELIMITED_JSON",
         f"{C.DATASET}.{table}", path], capture_output=True, text=True)
    if out.returncode:
        raise SystemExit(out.stderr)
    print(f"loaded {len(rows)} DERIVED rows into {table}")
