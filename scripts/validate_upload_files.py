#!/usr/bin/env python3
"""
Validate files before DB upload: all must exist and there must be no duplicates.
Exits 0 if valid, 1 otherwise. Use before running bq load or SP_PROCESS_MANUAL_UPLOADS.
Usage: python3 validate_upload_files.py <file1> [file2 ...]
"""
import os
import sys


def main():
    if len(sys.argv) < 2:
        print("Usage: validate_upload_files.py <file1> [file2 ...]", file=sys.stderr)
        sys.exit(1)

    paths = [p.strip() for p in sys.argv[1:] if p.strip()]
    if not paths:
        print("No file paths provided.", file=sys.stderr)
        sys.exit(1)

    errors = []

    # 1. Check for duplicate paths (normalize for comparison)
    seen = set()
    for p in paths:
        norm = os.path.normpath(os.path.abspath(p))
        if norm in seen:
            errors.append(f"Duplicate file: {p}")
        seen.add(norm)

    # 2. Check all files exist, are files, and are non-empty
    for p in paths:
        if not os.path.exists(p):
            errors.append(f"File does not exist: {p}")
        elif not os.path.isfile(p):
            errors.append(f"Not a file: {p}")
        elif os.path.getsize(p) == 0:
            errors.append(f"File is empty: {p}")

    if errors:
        print("Validation failed. Fix before uploading to DB:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        sys.exit(1)

    print(f"OK: {len(paths)} file(s) validated (all exist, no duplicates).")
    sys.exit(0)


if __name__ == "__main__":
    main()
