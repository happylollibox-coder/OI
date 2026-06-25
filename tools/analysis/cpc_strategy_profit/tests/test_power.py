# tools/analysis/cpc_strategy_profit/tests/test_power.py
import pandas as pd
from tools.analysis.cpc_strategy_profit.power import build_power_matrix

def _segs(rows):
    cols = ["parent_name", "calendar_segment", "cpc_action", "regime_id",
            "clicks", "orders", "net_profit", "net_profit_per_day"]
    return pd.DataFrame(rows, columns=cols)

def test_conclusive_when_all_thresholds_met():
    rows = [["Bottle", "EVERYDAY_2026-01", "RAISE", i, 100, 3, 50.0, 5.0]
            for i in range(5)]
    cell = build_power_matrix(_segs(rows))
    assert cell.iloc[0]["verdict"] == "CONCLUSIVE"
    assert cell.iloc[0]["n_regimes"] == 5

def test_weak_when_too_few_orders():
    rows = [["Bottle", "EVERYDAY_2026-01", "RAISE", i, 100, 0, 5.0, 1.0]
            for i in range(6)]
    cell = build_power_matrix(_segs(rows))
    assert cell.iloc[0]["verdict"] == "WEAK"

def test_weak_when_too_few_regimes():
    rows = [["Bottle", "EVERYDAY_2026-01", "RAISE", 0, 5000, 99, 5.0, 1.0]]
    cell = build_power_matrix(_segs(rows))
    assert cell.iloc[0]["verdict"] == "WEAK"
