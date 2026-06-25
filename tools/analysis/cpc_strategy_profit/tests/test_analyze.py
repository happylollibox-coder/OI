# tools/analysis/cpc_strategy_profit/tests/test_analyze.py
import pandas as pd
from tools.analysis.cpc_strategy_profit.analyze import rank_strategies, merge_segments

def _cell(rows):
    cols = ["parent_name", "calendar_segment", "strategy",
            "n_regimes", "clicks", "orders", "net_profit", "net_profit_per_day", "verdict"]
    return pd.DataFrame(rows, columns=cols)

def test_rank_picks_highest_npd_among_conclusive():
    cells = _cell([
        ["Bottle", "EVERYDAY_2026-01", "CPC_RAISED", 5, 999, 99, 100.0, 9.0, "CONCLUSIVE"],
        ["Bottle", "EVERYDAY_2026-01", "CPC_HELD",   5, 999, 99, 100.0, 4.0, "CONCLUSIVE"],
        ["Bottle", "EVERYDAY_2026-01", "CPC_LOWERED",5, 999, 99,  50.0, 12.0, "WEAK"],
    ])
    ranked = rank_strategies(cells)
    top = ranked[(ranked["parent_name"] == "Bottle") & (ranked["rank"] == 1)].iloc[0]
    assert top["strategy"] == "CPC_RAISED"   # WEAK cell ignored despite higher npd

def test_merge_collapses_segments_with_same_winner():
    ranked = pd.DataFrame([
        ["Bottle", "EVERYDAY_2026-01", "CPC_RAISED", 1],
        ["Bottle", "XMAS_PRE",         "CPC_RAISED", 1],
        ["Bottle", "XMAS_PEAK",        "CPC_HELD",   1],
    ], columns=["parent_name", "calendar_segment", "strategy", "rank"])
    merged = merge_segments(ranked)
    g = merged[merged.parent_name == "Bottle"].set_index("calendar_segment")["merged_group"]
    assert g["EVERYDAY_2026-01"] == g["XMAS_PRE"]      # same winner -> merged
    assert g["XMAS_PEAK"] != g["EVERYDAY_2026-01"]     # different winner -> separate
