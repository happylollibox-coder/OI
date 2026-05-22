"""
MCP Server for Google Cloud Storage.

Provides tools to interact with GCS buckets for the OI project.
Uses ADC credentials from ~/.config/gcloud/application_default_credentials.json
"""

import json
import mimetypes
import os
from datetime import datetime

from google.cloud import storage
from mcp.server.fastmcp import FastMCP

GCP_PROJECT = "onyga-482313"
DEFAULT_BUCKET = "onyga-482313-hot-folder"

HOT_FOLDER_PREFIXES = [
    "incoming/csv/payoneer/",
    "incoming/csv/leumi/",
    "incoming/csv/Inventory_Ledger_Summary/",
    "incoming/excel/reports/",
]

mcp = FastMCP("GCS")
client = storage.Client(project=GCP_PROJECT)


@mcp.tool()
def list_buckets() -> str:
    """List all GCS buckets in the project. Returns bucket name, creation date, and location."""
    try:
        buckets = list(client.list_buckets())
        results = [
            {
                "name": b.name,
                "created": b.time_created.isoformat() if b.time_created else None,
                "location": b.location,
            }
            for b in buckets
        ]
        return json.dumps(results, default=str)
    except Exception as e:
        return json.dumps({"error": str(e)})


@mcp.tool()
def list_files(
    bucket: str = DEFAULT_BUCKET,
    prefix: str | None = None,
    limit: int = 50,
) -> str:
    """List files in a GCS bucket, optionally filtered by prefix.

    Args:
        bucket: GCS bucket name (default: onyga-482313-hot-folder)
        prefix: Optional path prefix to filter results
        limit: Maximum number of files to return (default: 50)
    """
    try:
        bkt = client.bucket(bucket)
        blobs = bkt.list_blobs(prefix=prefix, max_results=limit)
        results = []
        for blob in blobs:
            results.append(
                {
                    "name": blob.name,
                    "size_bytes": blob.size,
                    "updated": blob.updated.isoformat() if blob.updated else None,
                }
            )
        return json.dumps(results, default=str)
    except Exception as e:
        return json.dumps({"error": str(e)})


@mcp.tool()
def read_file(
    bucket: str,
    path: str,
    max_bytes: int = 10000,
) -> str:
    """Read a text or CSV file from GCS. Refuses to read binary files.

    Args:
        bucket: GCS bucket name
        path: Full object path within the bucket
        max_bytes: Maximum bytes to read (default: 10000). File is truncated if larger.
    """
    try:
        bkt = client.bucket(bucket)
        blob = bkt.blob(path)

        if not blob.exists():
            return json.dumps({"error": f"File not found: gs://{bucket}/{path}"})

        blob.reload()

        # Detect binary files by content type or extension
        content_type = blob.content_type or ""
        mime_guess, _ = mimetypes.guess_type(path)
        effective_type = content_type or mime_guess or ""

        binary_indicators = [
            "image/",
            "audio/",
            "video/",
            "application/octet-stream",
            "application/zip",
            "application/gzip",
            "application/x-tar",
            "application/pdf",
            "application/x-executable",
        ]
        if any(effective_type.startswith(ind) for ind in binary_indicators):
            return json.dumps(
                {
                    "error": f"Binary file detected (type: {effective_type}). Cannot read binary files.",
                    "path": f"gs://{bucket}/{path}",
                    "size_bytes": blob.size,
                }
            )

        # Check common binary extensions as fallback
        binary_extensions = {
            ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".ico", ".webp",
            ".mp3", ".mp4", ".avi", ".mov", ".wav", ".flac",
            ".zip", ".gz", ".tar", ".rar", ".7z",
            ".pdf", ".exe", ".bin", ".dll", ".so", ".dylib",
            ".parquet", ".avro", ".orc",
        }
        _, ext = os.path.splitext(path)
        if ext.lower() in binary_extensions:
            return json.dumps(
                {
                    "error": f"Binary file detected (extension: {ext}). Cannot read binary files.",
                    "path": f"gs://{bucket}/{path}",
                    "size_bytes": blob.size,
                }
            )

        data = blob.download_as_bytes(start=0, end=max_bytes)

        # Final binary check on actual content
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            return json.dumps(
                {
                    "error": "File contains non-UTF-8 binary content. Cannot read.",
                    "path": f"gs://{bucket}/{path}",
                    "size_bytes": blob.size,
                }
            )

        truncated = blob.size is not None and blob.size > max_bytes
        result = {
            "path": f"gs://{bucket}/{path}",
            "size_bytes": blob.size,
            "truncated": truncated,
            "content": text,
        }
        if truncated:
            result["note"] = f"Showing first {max_bytes} bytes of {blob.size} total"

        return json.dumps(result, default=str)
    except Exception as e:
        return json.dumps({"error": str(e)})


@mcp.tool()
def upload_file(
    local_path: str,
    bucket: str,
    destination_path: str,
) -> str:
    """Upload a local file to GCS.

    Args:
        local_path: Absolute path to the local file
        bucket: GCS bucket name
        destination_path: Destination object path within the bucket
    """
    try:
        if not os.path.exists(local_path):
            return json.dumps({"error": f"Local file not found: {local_path}"})

        bkt = client.bucket(bucket)
        blob = bkt.blob(destination_path)

        mime_type, _ = mimetypes.guess_type(local_path)
        blob.upload_from_filename(local_path, content_type=mime_type)

        gcs_uri = f"gs://{bucket}/{destination_path}"
        file_size = os.path.getsize(local_path)

        return json.dumps(
            {
                "uri": gcs_uri,
                "size_bytes": file_size,
                "content_type": mime_type,
                "message": f"Uploaded {local_path} to {gcs_uri}",
            },
            default=str,
        )
    except Exception as e:
        return json.dumps({"error": str(e)})


@mcp.tool()
def delete_file(
    bucket: str,
    path: str,
) -> str:
    """Delete a file from GCS.

    Args:
        bucket: GCS bucket name
        path: Full object path within the bucket
    """
    try:
        bkt = client.bucket(bucket)
        blob = bkt.blob(path)

        if not blob.exists():
            return json.dumps({"error": f"File not found: gs://{bucket}/{path}"})

        blob.delete()
        return json.dumps(
            {"message": f"Deleted gs://{bucket}/{path}"},
            default=str,
        )
    except Exception as e:
        return json.dumps({"error": str(e)})


@mcp.tool()
def get_hot_folder_status() -> str:
    """Show recent files in all hot-folder incoming paths, grouped by folder.

    Checks the following paths in the hot-folder bucket:
    - incoming/csv/payoneer/
    - incoming/csv/leumi/
    - incoming/csv/Inventory_Ledger_Summary/
    - incoming/excel/reports/
    """
    try:
        bkt = client.bucket(DEFAULT_BUCKET)
        results = {}

        for prefix in HOT_FOLDER_PREFIXES:
            folder_name = prefix.rstrip("/")
            blobs = list(bkt.list_blobs(prefix=prefix, max_results=50))

            # Filter out the "directory" placeholder blobs
            files = []
            for blob in blobs:
                if blob.name == prefix:
                    continue
                files.append(
                    {
                        "name": blob.name.removeprefix(prefix),
                        "full_path": blob.name,
                        "size_bytes": blob.size,
                        "updated": blob.updated.isoformat() if blob.updated else None,
                    }
                )

            # Sort by updated descending (most recent first)
            files.sort(
                key=lambda f: f["updated"] or "",
                reverse=True,
            )

            results[folder_name] = {
                "file_count": len(files),
                "files": files,
            }

        return json.dumps(results, default=str)
    except Exception as e:
        return json.dumps({"error": str(e)})


if __name__ == "__main__":
    mcp.run()
