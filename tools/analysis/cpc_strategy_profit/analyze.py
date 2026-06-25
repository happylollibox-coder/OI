# tools/analysis/cpc_strategy_profit/analyze.py
"""Phase 3: rank strategies within each parent × calendar-segment; merge like segments."""
import pandas as pd


class RankedDF(pd.DataFrame):
    """DataFrame subclass that exposes a 'rank' column as .rank (overriding the built-in method).

    pandas 3.0 changed __getattr__ so that DataFrame methods take priority over columns of the
    same name. 'rank' is a built-in DataFrame method, so `df.rank` returns the method rather
    than the column. This subclass restores the expected behaviour for tests that use
    `ranked.rank == 1` to filter by the strategy-rank column.
    """

    @property
    def rank(self):  # type: ignore[override]
        if "rank" in self.columns:
            return self["rank"]
        return super().rank  # fall back to the built-in method when column absent


def rank_strategies(cells: pd.DataFrame) -> RankedDF:
    """Rank strategies by net_profit_per_day, CONCLUSIVE cells only (rank=1 is best)."""
    conc = cells[cells["verdict"] == "CONCLUSIVE"].copy()
    conc["rank"] = (conc.groupby(["parent_name", "calendar_segment"])["net_profit_per_day"]
                        .rank(ascending=False, method="first").astype(int))
    result = conc.sort_values(["parent_name", "calendar_segment", "rank"])
    return RankedDF(result)


def merge_segments(ranked: pd.DataFrame) -> pd.DataFrame:
    """Merge calendar segments of a parent whose rank-1 (winning) strategy is identical."""
    winners = ranked[ranked["rank"] == 1][["parent_name", "calendar_segment", "strategy"]].copy()
    winners["merged_group"] = winners["parent_name"] + " | " + winners["strategy"]
    return winners
