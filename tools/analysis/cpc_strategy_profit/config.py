# tools/analysis/cpc_strategy_profit/config.py
"""Tunable constants + paths for the CPC strategy → net profit analysis."""
from pathlib import Path

PROJECT = "onyga-482313"
DATASET = "OI"
START_DATE = "2025-09-23"          # first day of placement/ads coverage

# Regime segmentation
BOUNDARY_PCT = 0.15                # CPC move > 15% of regime level => boundary
BOUNDARY_ABS = 0.10                # ...or > $0.10 absolute, whichever larger
GAP_DAYS = 5                       # inactivity gap (days) forces a new regime
SMOOTH_WINDOW = 3                  # centered median smoothing window
CONSTANT_MIN_DAYS = 14             # regime this long (active days) => CPC_HELD

# Magnitude tiers (|entry_pct|)
MAG_SMALL = 0.25
MAG_MEDIUM = 0.60

# Phase-2 power gate (a parent × calendar-segment × strategy cell)
MIN_REGIMES = 5
MIN_CLICKS = 200
MIN_ORDERS = 10

# Attribution / hygiene
MIN_CLICKS_ACTIVE_DAY = 1          # a day counts as "active" if clicks >= this
LAG_TRIM_DAYS = 2                  # drop the most recent N days (ads lag)

ROOT = Path(__file__).resolve().parents[3]          # OI/
TMP = ROOT / ".tmp" / "cpc_strategy"
BASE_CSV = TMP / "cpc_base.csv"
REGIMES_CSV = TMP / "regimes.csv"
POWER_CSV = TMP / "power_matrix.csv"
RECS_CSV = TMP / "recommendations.csv"
CHARTS_DIR = TMP / "charts"
SQL_DIR = Path(__file__).resolve().parent / "sql"
FINDINGS_DOC = ROOT / "architecture" / "CPC_STRATEGY_FINDINGS_2026-06.md"
