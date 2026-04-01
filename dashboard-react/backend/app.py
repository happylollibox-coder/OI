#!/usr/bin/env python3
"""Admin API backend for OI dashboard. Runs refresh_data, tests, serves /data, conclusions/ground truths CRUD."""

import json
import os
import subprocess
import sys
from pathlib import Path

from flask import Flask, jsonify, request, send_from_directory
from flask_cors import CORS

# Set SKIP_BQ_API=1 to use in-memory store only (faster startup, no BigQuery import)
SKIP_BQ = os.environ.get("SKIP_BQ_API", "").strip() in ("1", "true", "yes")

app = Flask(__name__)
CORS(app, origins=["http://localhost:5173", "http://127.0.0.1:5173", "http://localhost:5174", "http://localhost:5175"])

# Project root: dashboard-react/backend/ -> OI/
BACKEND_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = BACKEND_DIR.parent.parent
DASHBOARD_DIR = PROJECT_ROOT / "dashboard"
DATA_DIR = DASHBOARD_DIR / "data"
SCRIPTS_DIR = PROJECT_ROOT / "scripts"
DASHBOARD_REACT = BACKEND_DIR.parent
E2E_DIR = DASHBOARD_REACT / "tests" / "e2e"


@app.route("/api/admin/refresh", methods=["POST"])
def admin_refresh():
    """Run refresh_data.py and return output."""
    script = DASHBOARD_DIR / "refresh_data.py"
    if not script.exists():
        return jsonify({"success": False, "exitCode": -1, "output": f"Script not found: {script}"}), 500
    try:
        result = subprocess.run(
            [sys.executable, str(script)],
            cwd=str(PROJECT_ROOT),
            capture_output=True,
            text=True,
            timeout=600,
        )
        output = (result.stdout or "") + (result.stderr or "")
        return jsonify(
            {"success": result.returncode == 0, "exitCode": result.returncode, "output": output}
        )
    except subprocess.TimeoutExpired:
        return jsonify({"success": False, "exitCode": -1, "output": "Refresh timed out after 10 minutes"}), 500
    except Exception as e:
        return jsonify({"success": False, "exitCode": -1, "output": str(e)}), 500


@app.route("/api/admin/tests/run", methods=["POST"])
def admin_tests_run():
    """Run run_tests.sh and return output."""
    mode = "all"
    if request.is_json:
        body = request.get_json() or {}
        mode = body.get("mode", "all")
    script = SCRIPTS_DIR / "run_tests.sh"
    if not script.exists():
        return jsonify({"success": False, "exitCode": -1, "output": f"Script not found: {script}"}), 500
    try:
        result = subprocess.run(
            ["bash", str(script), mode],
            cwd=str(PROJECT_ROOT),
            capture_output=True,
            text=True,
            timeout=300,
        )
        output = (result.stdout or "") + (result.stderr or "")
        return jsonify(
            {"success": result.returncode == 0, "exitCode": result.returncode, "output": output}
        )
    except subprocess.TimeoutExpired:
        return jsonify({"success": False, "exitCode": -1, "output": "Tests timed out after 5 minutes"}), 500
    except Exception as e:
        return jsonify({"success": False, "exitCode": -1, "output": str(e)}), 500


@app.route("/api/admin/tests/playwright/specs", methods=["GET"])
def admin_playwright_specs():
    """List available Playwright spec files."""
    if not E2E_DIR.exists():
        return jsonify([])
    specs = []
    for f in sorted(E2E_DIR.glob("*.spec.ts")):
        # f.stem for "home.spec.ts" is "home.spec"; we need "home" for path construction
        spec_id = f.stem.removesuffix(".spec") if f.stem.endswith(".spec") else f.stem
        specs.append({"id": spec_id, "path": str(f.relative_to(DASHBOARD_REACT))})
    return jsonify(specs)


@app.route("/api/admin/tests/playwright/run", methods=["POST"])
def admin_playwright_run():
    """Run Playwright tests. Body: { spec?: string, updateSnapshots?: bool }."""
    body = request.get_json() or {}
    spec = body.get("spec")
    update_snapshots = body.get("updateSnapshots", False)
    # Use quick script for update-snapshots (dev + test in parallel) — completes in ~15s vs 1+ min
    if update_snapshots and not spec:
        cmd = ["npm", "run", "test:update-snapshots:quick"]
    else:
        cmd = ["npx", "playwright", "test"]
        if update_snapshots:
            cmd.append("--update-snapshots")
        if spec:
            # Normalize: "home.spec" (from old API) or "home" both resolve to home.spec.ts
            spec_base = spec.removesuffix(".spec") if spec.endswith(".spec") else spec
            spec_path = E2E_DIR / f"{spec_base}.spec.ts"
            if spec_path.exists():
                cmd.append(str(spec_path.relative_to(DASHBOARD_REACT)))
            else:
                return jsonify({"success": False, "exitCode": -1, "output": f"Spec not found: {spec}"}), 400
    try:
        result = subprocess.run(
            cmd,
            cwd=str(DASHBOARD_REACT),
            capture_output=True,
            text=True,
            timeout=180,
        )
        output = (result.stdout or "") + (result.stderr or "")
        return jsonify(
            {"success": result.returncode == 0, "exitCode": result.returncode, "output": output}
        )
    except subprocess.TimeoutExpired:
        return jsonify({"success": False, "exitCode": -1, "output": "Playwright timed out after 3 minutes"}), 500
    except Exception as e:
        return jsonify({"success": False, "exitCode": -1, "output": str(e)}), 500


@app.route("/api/admin/tests/explain", methods=["GET"])
def admin_tests_explain():
    """Return test metadata from manifest."""
    manifest_path = SCRIPTS_DIR / "bigquery" / "tests" / "tests_manifest.json"
    if not manifest_path.exists():
        return jsonify([])
    with open(manifest_path, encoding="utf-8") as f:
        data = json.load(f)
    return jsonify(data)


# ---------------------------------------------------------------------------
# Conclusions & Ground Truths (CRUD)
# Uses in-memory store for dev. When DIM_BUSINESS_CONCLUSIONS/DIM_GROUND_TRUTHS
# exist in BigQuery and GOOGLE_APPLICATION_CREDENTIALS is set, reads/writes to BQ.
# ---------------------------------------------------------------------------

import datetime
import secrets
import time

_conclusions_store: list = []
_ground_truths_store: list = []


_bq_client_cache = None
_bq_client_tried = False


def _get_bq_client():
    """Return BigQuery client if credentials available, else None. Cached to avoid slow re-imports."""
    global _bq_client_cache, _bq_client_tried
    if SKIP_BQ:
        return None
    if _bq_client_tried:
        return _bq_client_cache
    _bq_client_tried = True
    try:
        from google.cloud import bigquery
        _bq_client_cache = bigquery.Client(project="onyga-482313")
        return _bq_client_cache
    except Exception:
        _bq_client_cache = None
        return None


def _row_to_dict(row):
    """Convert BigQuery row to dict, handling date/timestamp."""
    d = dict(row)
    for k, v in d.items():
        if hasattr(v, "isoformat"):
            d[k] = v.isoformat() if hasattr(v, "date") else str(v)
        elif isinstance(v, list):
            d[k] = list(v)
    return d


@app.route("/api/conclusions", methods=["GET"])
def api_conclusions_list():
    """List all business conclusions."""
    client = _get_bq_client()
    if client:
        try:
            rows = list(client.query("""
                SELECT id, conclusion, evidence, recommendation, family, experiment_id,
                       impact, status, created_at, tags
                FROM `onyga-482313.OI.DIM_BUSINESS_CONCLUSIONS`
                ORDER BY created_at DESC
            """).result())
            return jsonify([_row_to_dict(r) for r in rows])
        except Exception as e:
            return jsonify({"error": str(e)}), 500
    return jsonify(_conclusions_store)


@app.route("/api/conclusions", methods=["POST"])
def api_conclusions_add():
    """Add a business conclusion."""
    body = request.get_json() or {}
    c = {
        "id": body.get("id") or f"bc_{int(time.time() * 1000)}_{secrets.token_hex(2)}",
        "conclusion": body.get("conclusion", ""),
        "evidence": body.get("evidence", ""),
        "recommendation": body.get("recommendation", ""),
        "family": body.get("family"),
        "experiment_id": body.get("experiment_id"),
        "impact": body.get("impact", "test"),
        "status": body.get("status", "active"),
        "created_at": body.get("created_at") or datetime.date.today().isoformat(),
        "tags": body.get("tags") or [],
    }
    client = _get_bq_client()
    if client:
        try:
            from google.cloud.bigquery import QueryJobConfig, ScalarQueryParameter, ArrayQueryParameter
            tags_json = json.dumps(c["tags"])
            client.query(f"""
                INSERT INTO `onyga-482313.OI.DIM_BUSINESS_CONCLUSIONS`
                (id, conclusion, evidence, recommendation, family, experiment_id, impact, status, created_at, tags, updated_at)
                VALUES (@id, @conclusion, @evidence, @recommendation, @family, @experiment_id, @impact, @status, @created_at, @tags, CURRENT_TIMESTAMP())
            """, job_config=QueryJobConfig(
                query_parameters=[
                    ScalarQueryParameter("id", "STRING", c["id"]),
                    ScalarQueryParameter("conclusion", "STRING", c["conclusion"]),
                    ScalarQueryParameter("evidence", "STRING", c["evidence"]),
                    ScalarQueryParameter("recommendation", "STRING", c.get("recommendation") or ""),
                    ScalarQueryParameter("family", "STRING", c.get("family") or ""),
                    ScalarQueryParameter("experiment_id", "STRING", c.get("experiment_id") or ""),
                    ScalarQueryParameter("impact", "STRING", c["impact"]),
                    ScalarQueryParameter("status", "STRING", c["status"]),
                    ScalarQueryParameter("created_at", "DATE", c["created_at"]),
                    ScalarQueryParameter("tags", "STRING", tags_json),
                ]
            ))
            return jsonify(c)
        except Exception as e:
            return jsonify({"error": str(e)}), 500
    _conclusions_store.append(c)
    return jsonify(c)


@app.route("/api/conclusions/<id>", methods=["PATCH", "DELETE"])
def api_conclusions_update(id):
    """Update (archive) or delete a conclusion."""
    if request.method == "DELETE":
        client = _get_bq_client()
        if client:
            try:
                from google.cloud.bigquery import QueryJobConfig, ScalarQueryParameter
                client.query(
                    "DELETE FROM `onyga-482313.OI.DIM_BUSINESS_CONCLUSIONS` WHERE id = @id",
                    job_config=QueryJobConfig(
                        query_parameters=[ScalarQueryParameter("id", "STRING", id)]
                    ),
                )
                return jsonify({"ok": True})
            except Exception as e:
                return jsonify({"error": str(e)}), 500
        global _conclusions_store
        _conclusions_store = [x for x in _conclusions_store if x.get("id") != id]
        return jsonify({"ok": True})
    body = request.get_json() or {}
    status = body.get("status")
    if status:
        client = _get_bq_client()
        if client:
            try:
                from google.cloud.bigquery import QueryJobConfig, ScalarQueryParameter
                client.query(
                    """
                    UPDATE `onyga-482313.OI.DIM_BUSINESS_CONCLUSIONS`
                    SET status = @status, updated_at = CURRENT_TIMESTAMP() WHERE id = @id
                    """,
                    job_config=QueryJobConfig(
                        query_parameters=[
                            ScalarQueryParameter("status", "STRING", status),
                            ScalarQueryParameter("id", "STRING", id),
                        ]
                    ),
                )
                return jsonify({"ok": True})
            except Exception as e:
                return jsonify({"error": str(e)}), 500
        for x in _conclusions_store:
            if x.get("id") == id:
                x["status"] = status
                break
    return jsonify({"ok": True})


@app.route("/api/ground-truths", methods=["GET"])
def api_ground_truths_list():
    """List all ground truths."""
    client = _get_bq_client()
    if client:
        try:
            rows = list(client.query("""
                SELECT id, experiment_id, experiment_name, metric, op, ref, source_week, description, approved_at, keyword
                FROM `onyga-482313.OI.DIM_GROUND_TRUTHS`
                ORDER BY approved_at DESC
            """).result())
            return jsonify([_row_to_dict(r) for r in rows])
        except Exception as e:
            return jsonify({"error": str(e)}), 500
    return jsonify(_ground_truths_store)


@app.route("/api/ground-truths", methods=["POST"])
def api_ground_truths_add():
    """Add a ground truth."""
    body = request.get_json() or {}
    gt = {
        "id": body.get("id") or f"gt_{int(time.time() * 1000)}_{secrets.token_hex(2)}",
        "experiment_id": body.get("experiment_id", ""),
        "experiment_name": body.get("experiment_name", ""),
        "metric": body.get("metric", ""),
        "op": body.get("op", ""),
        "ref": body.get("ref", ""),
        "source_week": body.get("source_week", ""),
        "description": body.get("description", ""),
        "approved_at": body.get("approved_at") or datetime.date.today().isoformat(),
        "keyword": body.get("keyword"),
    }
    client = _get_bq_client()
    if client:
        try:
            from google.cloud.bigquery import QueryJobConfig, ScalarQueryParameter
            client.query(
                """
                INSERT INTO `onyga-482313.OI.DIM_GROUND_TRUTHS`
                (id, experiment_id, experiment_name, metric, op, ref, source_week, description, approved_at, keyword, updated_at)
                VALUES (@id, @experiment_id, @experiment_name, @metric, @op, @ref, @source_week, @description, @approved_at, @keyword, CURRENT_TIMESTAMP())
                """,
                job_config=QueryJobConfig(
                    query_parameters=[
                        ScalarQueryParameter("id", "STRING", gt["id"]),
                        ScalarQueryParameter("experiment_id", "STRING", gt.get("experiment_id") or ""),
                        ScalarQueryParameter("experiment_name", "STRING", gt.get("experiment_name") or ""),
                        ScalarQueryParameter("metric", "STRING", gt.get("metric") or ""),
                        ScalarQueryParameter("op", "STRING", gt.get("op") or ""),
                        ScalarQueryParameter("ref", "STRING", gt.get("ref") or ""),
                        ScalarQueryParameter("source_week", "STRING", gt.get("source_week") or ""),
                        ScalarQueryParameter("description", "STRING", gt.get("description") or ""),
                        ScalarQueryParameter("approved_at", "DATE", gt["approved_at"]),
                        ScalarQueryParameter("keyword", "STRING", gt.get("keyword") or ""),
                    ]
                ),
            )
            return jsonify(gt)
        except Exception as e:
            return jsonify({"error": str(e)}), 500
    _ground_truths_store.append(gt)
    return jsonify(gt)


@app.route("/api/ground-truths/<id>", methods=["DELETE"])
def api_ground_truths_delete(id):
    """Delete a ground truth."""
    client = _get_bq_client()
    if client:
        try:
            from google.cloud.bigquery import QueryJobConfig, ScalarQueryParameter
            client.query(
                "DELETE FROM `onyga-482313.OI.DIM_GROUND_TRUTHS` WHERE id = @id",
                job_config=QueryJobConfig(
                    query_parameters=[ScalarQueryParameter("id", "STRING", id)]
                ),
            )
            return jsonify({"ok": True})
        except Exception as e:
            return jsonify({"error": str(e)}), 500
    global _ground_truths_store
    _ground_truths_store = [x for x in _ground_truths_store if x.get("id") != id]
    return jsonify({"ok": True})


@app.route("/data/<path:filename>")
def serve_data(filename):
    """Serve JSON files from dashboard/data/."""
    if not filename.endswith(".json"):
        return jsonify({"error": "Only .json files allowed"}), 400
    filepath = (DATA_DIR / filename).resolve()
    data_root = DATA_DIR.resolve()
    if not str(filepath).startswith(str(data_root)) or not filepath.exists():
        return jsonify({"error": "Not found"}), 404
    return send_from_directory(DATA_DIR, filename)


if __name__ == "__main__":
    # use_reloader=False: refresh_data.py writes 20+ JSON files to dashboard/data/,
    # which would trigger the reloader repeatedly during the ~2 min refresh
    app.run(host="127.0.0.1", port=5001, debug=True, use_reloader=False)
