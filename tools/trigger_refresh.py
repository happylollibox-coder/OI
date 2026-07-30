import uuid
import time
from datetime import datetime, timezone
from google.cloud import bigquery

project_id = "onyga-482313"
client = bigquery.Client(project=project_id)

print("Starting SP_REFRESH_CUBE_TABLES...")
started = datetime.now(timezone.utc)
start = time.time()
try:
    client.query("CALL `onyga-482313.OI.SP_REFRESH_CUBE_TABLES`();").result()
    end = time.time()
    finished = datetime.now(timezone.utc)
    print(f"Successfully refreshed cube tables in {(end - start) / 60:.2f} minutes!")

    # Stamp LOG_PIPELINE_RUNS. The Cube caches for the launch/run cubes key their refreshKey on
    # MAX(finished_at) WHERE procedure_name='SP_REFRESH_CUBE_TABLES', so they only invalidate when this
    # stamp changes. The daily orchestrator (SP_ORCHESTRATE_DAILY_REFRESH) writes it via its wrapper, but a
    # direct CALL here does NOT — so without this row a manual refresh rebuilds the T_* tables yet the
    # dashboard keeps serving the previously-cached result until the next scheduled run. This closes that gap.
    row = {
        "run_id": f"manual-{uuid.uuid4()}",
        "run_date": started.date().isoformat(),
        "procedure_name": "SP_REFRESH_CUBE_TABLES",
        "status": "OK",
        "error_message": None,
        "started_at": started.isoformat(),
        "finished_at": finished.isoformat(),
        "duration_seconds": int(end - start),
        "inserted_at": datetime.now(timezone.utc).isoformat(),
    }
    errors = client.insert_rows_json("onyga-482313.OI.LOG_PIPELINE_RUNS", [row])
    if errors:
        print(f"WARNING: cube tables refreshed but stamping LOG_PIPELINE_RUNS failed: {errors}")
        print("The dashboard cubes may not pick up this refresh until the next orchestration run.")
    else:
        print("Stamped LOG_PIPELINE_RUNS -> launch/run cube caches will invalidate on their next check.")
except Exception as e:
    print(f"Error refreshing cube tables: {e}")
