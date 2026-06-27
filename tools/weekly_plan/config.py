"""Constants for the weekly plan generator (Coacher D)."""
PROJECT = "onyga-482313"
DATASET = "OI"
HORIZON_WEEKS = 4          # current + 3 future
TREND_WEEKS = 8            # trailing weeks for the net-profit trend
BOOTSTRAP_WEEKS = 8        # trailing weeks for the budget bootstrap
EXPLORE_CAP_FRAC = 0.10    # CAP (unproven) cells share at most this fraction of budget
ON_PLAN_TOL = 0.90         # actual >= TOL * expected => ON_PLAN
PEAK_BUDGET_MULT = 2.5     # in-window peak cells weighted up by this
PROBE_CLICKS = 15          # MAP/PROBE success target
