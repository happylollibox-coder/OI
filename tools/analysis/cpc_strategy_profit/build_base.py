# tools/analysis/cpc_strategy_profit/build_base.py
"""Run enriched_base.sql via the bq CLI, save to .tmp/cpc_strategy/cpc_base.csv."""
import subprocess, sys
from . import config as C

def build_base() -> str:
    C.TMP.mkdir(parents=True, exist_ok=True)
    sql = (C.SQL_DIR / "enriched_base.sql").read_text()
    out = subprocess.run(
        ["bq", f"--project_id={C.PROJECT}", "query", "--use_legacy_sql=false",
         "--format=csv", "--max_rows=10000000"],
        input=sql, capture_output=True, text=True)
    if out.returncode != 0:
        sys.stderr.write(out.stderr)
        raise SystemExit(f"bq query failed: {out.returncode}")
    C.BASE_CSV.write_text(out.stdout)
    n = out.stdout.count("\n") - 1
    print(f"wrote {C.BASE_CSV} ({n} rows)")
    return str(C.BASE_CSV)

if __name__ == "__main__":
    build_base()
