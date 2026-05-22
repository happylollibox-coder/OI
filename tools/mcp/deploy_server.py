"""OI Deploy MCP Server.

Wraps BigQuery deployment scripts with safety guardrails.
Provides tools for checking deployment status, validating,
deploying individual views or all views in dependency order.
"""

import json
import os
import shutil
import subprocess
from pathlib import Path

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("OI Deploy")

PROJECT_ROOT = "/Users/ori/Develop/OI"
PROJECT_ID = "onyga-482313"
DATASET = "OI"
QUALIFIED_DATASET = f"{PROJECT_ID}:{DATASET}"

SUBPROCESS_TIMEOUT = 300  # 5 minutes max

ENV = os.environ.copy()
ENV["PATH"] = (
    "/Users/ori/.nvm/versions/node/v22.22.1/bin"
    ":/usr/local/share/google-cloud-sdk/bin"
    ":/usr/local/bin:/usr/bin:/bin"
)

VIEWS_DIR = Path(PROJECT_ROOT) / "scripts" / "bigquery" / "views"
INTERFACE_VIEWS_DIR = Path(PROJECT_ROOT) / "scripts" / "bigquery" / "interface_views"


def _check_bq() -> None:
    """Raise RuntimeError if bq CLI is not available."""
    if shutil.which("bq", path=ENV["PATH"]) is None:
        raise RuntimeError(
            "bq CLI not found on PATH. Ensure Google Cloud SDK is installed "
            "and /usr/local/share/google-cloud-sdk/bin is in PATH."
        )


def _run(cmd: list[str], cwd: str = PROJECT_ROOT) -> subprocess.CompletedProcess:
    """Run a subprocess with standard safety guardrails."""
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=SUBPROCESS_TIMEOUT,
        cwd=cwd,
        env=ENV,
    )


@mcp.tool()
def deploy_status() -> str:
    """Show current BigQuery deployment state — view counts, table counts, procedure counts, and latest modification times."""
    _check_bq()

    result = _run([
        "bq", "ls",
        "--format=json",
        "--max_results=1000",
        QUALIFIED_DATASET,
    ])

    if result.returncode != 0:
        return json.dumps({
            "error": f"bq ls failed: {result.stderr.strip()}"
        })

    try:
        objects = json.loads(result.stdout)
    except json.JSONDecodeError:
        return json.dumps({
            "error": "Failed to parse bq ls output",
            "raw_output": result.stdout[:2000],
        })

    # Categorize objects
    views = []
    tables = []
    procedures = []
    other = []

    for obj in objects:
        obj_type = obj.get("type", "UNKNOWN")
        ref = obj.get("tableReference", {})
        name = ref.get("tableId", "unknown")
        last_modified_ms = obj.get("lastModifiedTime")
        last_modified = None
        if last_modified_ms:
            from datetime import datetime, timezone
            last_modified = datetime.fromtimestamp(
                int(last_modified_ms) / 1000, tz=timezone.utc
            ).isoformat()

        entry = {"name": name, "type": obj_type, "last_modified": last_modified}

        if obj_type == "VIEW":
            views.append(entry)
        elif obj_type == "TABLE":
            tables.append(entry)
        elif obj_type in ("ROUTINE", "PROCEDURE"):
            procedures.append(entry)
        else:
            other.append(entry)

    # Find latest modification across all objects
    all_entries = views + tables + procedures + other
    latest = None
    if all_entries:
        modified_times = [e["last_modified"] for e in all_entries if e["last_modified"]]
        if modified_times:
            latest = max(modified_times)

    summary = {
        "dataset": QUALIFIED_DATASET,
        "total_objects": len(objects),
        "views": len(views),
        "tables": len(tables),
        "procedures": len(procedures),
        "other": len(other),
        "latest_modification": latest,
        "view_names": sorted([v["name"] for v in views]),
        "table_names": sorted([t["name"] for t in tables]),
    }

    return json.dumps(summary, default=str, indent=2)


@mcp.tool()
def validate_deployment() -> str:
    """Run validation checks on BigQuery views without deploying anything.

    Checks that all SQL files parse correctly and that referenced
    tables/views exist in the dataset.
    """
    _check_bq()

    validation_script = Path(PROJECT_ROOT) / "deployment" / "validate.sh"
    errors = []
    warnings = []
    checked = 0

    # If validate.sh exists, run it
    if validation_script.exists():
        result = _run(["bash", str(validation_script)])
        return json.dumps({
            "method": "validate.sh",
            "returncode": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr,
            "success": result.returncode == 0,
        }, default=str, indent=2)

    # Otherwise, do manual validation: dry-run each SQL file
    sql_dirs = [INTERFACE_VIEWS_DIR, VIEWS_DIR]

    for sql_dir in sql_dirs:
        if not sql_dir.exists():
            warnings.append(f"Directory not found: {sql_dir}")
            continue

        for sql_file in sorted(sql_dir.glob("*.sql")):
            checked += 1
            view_name = sql_file.stem

            # Use --dry_run to validate without executing
            result = _run([
                "bq", "query",
                "--use_legacy_sql=false",
                "--dry_run",
                f"--project_id={PROJECT_ID}",
            ] + [sql_file.read_text()])

            if result.returncode != 0:
                errors.append({
                    "view": view_name,
                    "file": str(sql_file),
                    "error": result.stderr.strip(),
                })

    summary = {
        "method": "dry_run_validation",
        "files_checked": checked,
        "errors": len(errors),
        "warnings": warnings,
        "error_details": errors,
        "success": len(errors) == 0,
    }

    return json.dumps(summary, default=str, indent=2)


@mcp.tool()
def deploy_view(view_name: str) -> str:
    """Deploy a single BigQuery view by name.

    Args:
        view_name: The view name without .sql extension, e.g. "V_ADS_COACH".
                   Searches in both scripts/bigquery/views/ and
                   scripts/bigquery/interface_views/.
    """
    _check_bq()

    # Find the SQL file
    sql_file = None
    candidates = [
        VIEWS_DIR / f"{view_name}.sql",
        INTERFACE_VIEWS_DIR / f"{view_name}.sql",
    ]

    for candidate in candidates:
        if candidate.exists():
            sql_file = candidate
            break

    if sql_file is None:
        # List available files that partially match
        matches = []
        for d in [VIEWS_DIR, INTERFACE_VIEWS_DIR]:
            if d.exists():
                matches.extend(
                    f.stem for f in d.glob("*.sql")
                    if view_name.upper() in f.stem.upper()
                )
        return json.dumps({
            "error": f"SQL file not found for view: {view_name}",
            "searched": [str(c) for c in candidates],
            "partial_matches": matches,
        }, indent=2)

    # Read SQL content and execute
    sql_content = sql_file.read_text()

    result = _run([
        "bq", "query",
        "--use_legacy_sql=false",
        f"--project_id={PROJECT_ID}",
    ] + [sql_content])

    output = {
        "view": view_name,
        "file": str(sql_file),
        "success": result.returncode == 0,
        "stdout": result.stdout.strip() if result.stdout else "",
        "stderr": result.stderr.strip() if result.stderr else "",
    }

    return json.dumps(output, default=str, indent=2)


@mcp.tool()
def deploy_all() -> str:
    """Deploy all BigQuery views in dependency order (5 layers).

    Runs deployment/deploy_all.sh with the 'bigquery' target,
    which deploys views in this order:
      Layer 1: Interface views (V_SRC_*)
      Layer 2: Foundation views
      Layer 3: Experiment views (V_EXPERIMENT_*)
      Layer 4: Coach & Ads views
      Layer 5: Catch-all remaining views

    Returns the full output from each layer.
    """
    _check_bq()

    deploy_script = Path(PROJECT_ROOT) / "deployment" / "deploy_all.sh"

    if not deploy_script.exists():
        return json.dumps({
            "error": f"Deploy script not found: {deploy_script}",
        })

    result = _run([
        "bash", str(deploy_script), "bigquery",
    ])

    output = {
        "success": result.returncode == 0,
        "returncode": result.returncode,
        "stdout": result.stdout,
        "stderr": result.stderr,
    }

    return json.dumps(output, default=str, indent=2)


@mcp.tool()
def list_pending_changes() -> str:
    """Show SQL files modified since last commit (unstaged + staged).

    Uses git to detect changed .sql files in the scripts/bigquery/
    directory tree. Useful to see what needs deploying.
    """
    changed_files = []

    # Staged changes
    result_staged = _run([
        "git", "diff", "--cached", "--name-only", "--",
        "scripts/bigquery/",
    ])

    # Unstaged changes
    result_unstaged = _run([
        "git", "diff", "--name-only", "--",
        "scripts/bigquery/",
    ])

    # Untracked SQL files
    result_untracked = _run([
        "git", "ls-files", "--others", "--exclude-standard", "--",
        "scripts/bigquery/",
    ])

    all_files = set()

    for result, change_type in [
        (result_staged, "staged"),
        (result_unstaged, "modified"),
        (result_untracked, "untracked"),
    ]:
        if result.returncode == 0 and result.stdout.strip():
            for f in result.stdout.strip().split("\n"):
                f = f.strip()
                if f.endswith(".sql"):
                    all_files.add(f)
                    changed_files.append({
                        "file": f,
                        "view_name": Path(f).stem,
                        "status": change_type,
                    })

    # Deduplicate by file path (a file could appear in both staged and modified)
    seen = set()
    deduplicated = []
    for entry in changed_files:
        if entry["file"] not in seen:
            seen.add(entry["file"])
            deduplicated.append(entry)

    summary = {
        "total_changed_sql_files": len(deduplicated),
        "files": deduplicated,
    }

    return json.dumps(summary, default=str, indent=2)


if __name__ == "__main__":
    mcp.run()
