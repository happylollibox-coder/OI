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

def _surviving_keys(table: str):
    """6-part keys currently held by rows the DELETE above did NOT remove (custom/MANUAL sources)."""
    sql = (
        "SELECT COALESCE(parent_name,'ALL') p, COALESCE(season,'ALL') s, COALESCE(match_type,'ALL') m, "
        "COALESCE(intent_class,'ALL') i, COALESCE(campaign_type,'ALL') c, COALESCE(ad_format,'ALL') a "
        f"FROM `{C.PROJECT}.{C.DATASET}.{table}` GROUP BY 1,2,3,4,5,6"
    )
    out = subprocess.run(["bq", f"--project_id={C.PROJECT}", "query", "--use_legacy_sql=false",
                          "--format=json", "--max_rows=10000"],
                         input=sql, capture_output=True, text=True)
    if out.returncode:
        raise SystemExit(out.stderr)
    import json as _json
    return {tuple(r[k] for k in ("p", "s", "m", "i", "c", "a")) for r in _json.loads(out.stdout or "[]")}

PROFILE_KEY = ("parent_name", "season", "match_type", "intent_class", "campaign_type", "ad_format")

def load_table(df, table: str, updated_by="strategy_profile_tool", replace_sources=("DERIVED",)):
    """Replace only rows whose source is in replace_sources (MANUAL preserved).

    Fan-out guard (2026-08-01): V_ADS_COACH_DATA joins the profile on the 6-part key assuming at
    most ONE row per key. Rows with a custom source (MANUAL, derived-from-realized-cpc …) survive
    the DELETE below, so re-emitting the same cell as DERIVED would create a duplicate key and fan
    out every matching keyword row in the coach (June fan-out incident class). Drop any outgoing
    row whose key is already held by a survivor.
    """
    in_list = ",".join(f"'{s}'" for s in replace_sources)
    _bq(f"DELETE FROM `{C.PROJECT}.{C.DATASET}.{table}` WHERE source IN ({in_list})")
    if table == "DE_PRODUCT_STRATEGY_PROFILE" and all(k in df.columns for k in PROFILE_KEY):
        held = _surviving_keys(table)
        if held:
            key_of = lambda r: tuple("ALL" if r[k] is None or r[k] != r[k] else str(r[k]) for k in PROFILE_KEY)
            before = len(df)
            df = df[[key_of(r) not in held for r in df.to_dict("records")]]
            if before - len(df):
                print(f"fan-out guard: skipped {before - len(df)} cell(s) held by custom-source rows")
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
    print(f"loaded {len(rows)} rows ({'/'.join(replace_sources)}) into {table}")
