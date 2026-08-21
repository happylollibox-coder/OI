#!/usr/bin/env bash
# Test orchestrator: run DB and/or dashboard tests based on mode.
# Usage: ./scripts/run_tests.sh [--mode=all|db|dashboard]
# Default: dashboard (Playwright only)

set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-dashboard}"

case "$MODE" in
  all|--mode=all)
    DB_EXIT=0
    DASH_EXIT=0
    SIZE_EXIT=0
    PRICE_EXIT=0
    echo "=== Checking view-body headroom ==="
    (cd "$ROOT" && python3 scripts/bigquery/check_view_body_size.py) || SIZE_EXIT=$?
    echo ""
    echo "=== Checking one price per keyword ==="
    (cd "$ROOT" && python3 scripts/bigquery/check_one_price_per_key.py) || PRICE_EXIT=$?
    echo ""
    echo "=== Running DB tests ==="
    (cd "$ROOT" && python3 scripts/bigquery/tests/run_all_tests.py) || DB_EXIT=$?
    echo ""
    echo "=== Running Dashboard (Playwright) tests ==="
    (cd "$ROOT/dashboard-react" && npm run test) || DASH_EXIT=$?
    if [ $SIZE_EXIT -ne 0 ] || [ $PRICE_EXIT -ne 0 ] || [ $DB_EXIT -ne 0 ] || [ $DASH_EXIT -ne 0 ]; then exit 1; fi
    exit 0
    ;;
  db|--mode=db)
    DB_EXIT=0
    SIZE_EXIT=0
    PRICE_EXIT=0
    echo "=== Checking view-body headroom ==="
    (cd "$ROOT" && python3 scripts/bigquery/check_view_body_size.py) || SIZE_EXIT=$?
    echo ""
    echo "=== Checking one price per keyword ==="
    (cd "$ROOT" && python3 scripts/bigquery/check_one_price_per_key.py) || PRICE_EXIT=$?
    echo ""
    echo "=== Running DB tests ==="
    (cd "$ROOT" && python3 scripts/bigquery/tests/run_all_tests.py) || DB_EXIT=$?
    if [ $SIZE_EXIT -ne 0 ] || [ $PRICE_EXIT -ne 0 ] || [ $DB_EXIT -ne 0 ]; then exit 1; fi
    exit 0
    ;;
  dashboard|--mode=dashboard)
    cd "$ROOT/dashboard-react" && npm run test
    ;;
  *)
    echo "Usage: $0 [all|db|dashboard]"
    exit 1
    ;;
esac
