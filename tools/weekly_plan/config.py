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
# Capacity cap for SCALE/DEFEND floors: a cell's floor can't exceed its trailing actual weekly
# spend x this multiplier (stops a hyper-efficient but volume-tiny cell — e.g. brand-defense —
# hogging budget it can't physically spend). Peak allows more headroom (gift-season volume spikes).
GROWTH_MULT_OFF = 1.5      # off-season: floor up to 1.5x recent actual spend
GROWTH_MULT_PEAK = 3.0     # peak-season: floor up to 3x recent actual spend
NEW_CELL_CAP_FRAC = 0.05   # cells with no spend history cap at this fraction of the weekly budget
