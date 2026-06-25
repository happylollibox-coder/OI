# tools/analysis/cpc_strategy_profit/tests/test_regimes.py
import datetime as dt
import pandas as pd
from tools.analysis.cpc_strategy_profit.regimes import (
    assign_regimes, summarize_regime_segments, magnitude_tier)

def _daily(cpcs, start="2026-01-01", seg="EVERYDAY_2026-01"):
    base = dt.date.fromisoformat(start)
    return pd.DataFrame({
        "parent_name": "Bottle", "campaign_id": "c1", "target_key": "k1",
        "date": [base + dt.timedelta(days=i) for i in range(len(cpcs))],
        "cpc": cpcs, "clicks": 10, "cost": [c*10 for c in cpcs],
        "orders": 1, "units": 1, "sales": 30.0, "gross_profit": 12.0,
        "net_profit": [12.0 - c*10 for c in cpcs],
        "calendar_segment": seg, "tos_cost_share": 0.4, "tos_bid_adj_pct": 50})

def test_stable_cpc_is_one_regime():
    d = assign_regimes(_daily([1.00, 1.02, 0.99, 1.01, 1.00]))
    assert d["regime_id"].nunique() == 1
    assert (d["entry_transition"] == "LAUNCH").all()

def test_upward_step_creates_increase_regime():
    d = assign_regimes(_daily([1.00, 1.00, 1.00, 1.50, 1.52, 1.50]))
    assert d["regime_id"].nunique() == 2
    second = d[d["regime_id"] == 1]
    assert (second["entry_transition"] == "INCREASE").all()
    assert second["entry_pct"].iloc[0] > 0

def test_downward_step_creates_decrease_regime():
    d = assign_regimes(_daily([2.00, 2.00, 2.00, 1.00, 1.00]))
    assert d[d["regime_id"] == 1]["entry_transition"].iloc[0] == "DECREASE"

def test_gap_creates_reactivate_regime():
    df = _daily([1.00, 1.00])
    df.loc[1, "date"] = df.loc[0, "date"] + dt.timedelta(days=9)  # 9-day gap
    d = assign_regimes(df)
    assert d["regime_id"].nunique() == 2
    assert d[d["regime_id"] == 1]["entry_transition"].iloc[0] == "REACTIVATE"

def test_magnitude_tiers():
    assert magnitude_tier(0.10) == "SMALL"
    assert magnitude_tier(0.40) == "MEDIUM"
    assert magnitude_tier(0.90) == "LARGE"

def test_long_stable_regime_is_held():
    d = assign_regimes(_daily([1.00]*20))
    segs = summarize_regime_segments(d)
    assert (segs["strategy"] == "CPC_HELD").all()
    assert segs["days"].iloc[0] == 20

def test_summary_one_row_per_regime_segment_and_npd():
    d = assign_regimes(_daily([1.00, 1.00, 1.50, 1.50]))
    segs = summarize_regime_segments(d)
    assert len(segs) == 2
    assert "net_profit_per_day" in segs.columns
    assert (segs["net_profit_per_day"] == segs["net_profit"] / segs["days"]).all()
