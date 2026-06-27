#!/usr/bin/env bash
# Refresh the coacher's strategy + plan. Run WEEKLY (e.g. Monday morning).
# The SQL half (review write-back + probe log) is already scheduled daily as `daily_coach_loop`;
# this is the Python half that re-derives the strategy and rolls the weekly plan forward.
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root (OI/)

echo "==> 1/3  re-derive per-product strategy profile (B/C: bands, confidence, borrow)"
.venv/bin/python -m tools.strategy_profile.run

echo "==> 2/3  re-seed TOS targets (A: tos_target_pct, floored at 3%)"
bq query --use_legacy_sql=false < scripts/bigquery/queries/derive_tos_targets.sql

echo "==> 3/3  roll the weekly plan forward (D: current + 3 weeks, budget-allocated)"
.venv/bin/python -m tools.weekly_plan.run

echo "==> 4/4  generate the This Week report"
.venv/bin/python -m tools.coacher_report
echo "==> done. Open the report:  open .tmp/coacher_this_week.html"
