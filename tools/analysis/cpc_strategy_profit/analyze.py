# tools/analysis/cpc_strategy_profit/analyze.py
"""Phase 3: rank CPC actions within each parent × calendar-segment; merge like segments."""
import pandas as pd


def rank_strategies(cells: pd.DataFrame) -> pd.DataFrame:
    """Rank cpc_actions by net_profit_per_day, CONCLUSIVE cells only (rank=1 is best).

    Note: the result has a column named ``rank``; access it as ``df["rank"]``, not
    ``df.rank`` (that attribute is the built-in DataFrame.rank method in every pandas version).
    """
    conc = cells[cells["verdict"] == "CONCLUSIVE"].copy()
    conc["rank"] = (conc.groupby(["parent_name", "calendar_segment"])["net_profit_per_day"]
                        .rank(ascending=False, method="first").astype(int))
    return conc.sort_values(["parent_name", "calendar_segment", "rank"])


def merge_segments(ranked: pd.DataFrame) -> pd.DataFrame:
    """Merge calendar segments of a parent whose rank-1 (winning) cpc_action is identical."""
    winners = ranked[ranked["rank"] == 1][["parent_name", "calendar_segment", "cpc_action"]].copy()
    winners["merged_group"] = winners["parent_name"] + " | " + winners["cpc_action"]
    return winners
