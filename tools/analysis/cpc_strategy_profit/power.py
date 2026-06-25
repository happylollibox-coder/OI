# tools/analysis/cpc_strategy_profit/power.py
"""Phase 2: classify each parent × calendar-segment × cpc_action cell by statistical power."""
import pandas as pd
from . import config as C

def build_power_matrix(segs: pd.DataFrame,
                       min_regimes: int = C.MIN_REGIMES,
                       min_clicks: int = C.MIN_CLICKS,
                       min_orders: int = C.MIN_ORDERS) -> pd.DataFrame:
    cell = (segs.groupby(["parent_name", "calendar_segment", "cpc_action"], dropna=False)
                .agg(n_regimes=("regime_id", "count"), clicks=("clicks", "sum"),
                     orders=("orders", "sum"), net_profit=("net_profit", "sum"),
                     net_profit_per_day=("net_profit_per_day", "median"))
                .reset_index())
    def verdict(r):
        if r.n_regimes == 0:
            return "EMPTY"
        if r.n_regimes >= min_regimes and r.clicks >= min_clicks and r.orders >= min_orders:
            return "CONCLUSIVE"
        return "WEAK"
    cell["verdict"] = cell.apply(verdict, axis=1)
    return cell
