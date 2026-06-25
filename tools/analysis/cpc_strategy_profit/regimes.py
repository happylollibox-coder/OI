# tools/analysis/cpc_strategy_profit/regimes.py
"""Segment each target's daily CPC series into regimes; label strategy + magnitude."""
from __future__ import annotations
import pandas as pd
from . import config as C

def median_smooth(s: pd.Series, window: int = C.SMOOTH_WINDOW) -> pd.Series:
    return s.rolling(window, min_periods=1, center=True).median()

def magnitude_tier(pct: float) -> str:
    a = abs(pct or 0.0)
    if a < C.MAG_SMALL:  return "SMALL"
    if a < C.MAG_MEDIUM: return "MEDIUM"
    return "LARGE"

def assign_regimes(daily: pd.DataFrame,
                   boundary_pct: float = C.BOUNDARY_PCT,
                   boundary_abs: float = C.BOUNDARY_ABS,
                   gap_days: int = C.GAP_DAYS) -> pd.DataFrame:
    """One target_key's active-day rows. Adds regime_id, entry_transition, entry_pct."""
    d = daily.sort_values("date").reset_index(drop=True).copy()
    n = len(d)
    if n == 0:
        for col, typ in [("regime_id", int), ("entry_transition", str), ("entry_pct", float)]:
            d[col] = pd.Series(dtype=typ)
        return d
    smooth = median_smooth(d["cpc"]).tolist()
    dates = [pd.Timestamp(x).date() for x in d["date"]]
    regime_id = [0] * n
    label = {0: "LAUNCH"}
    pct = {0: 0.0}
    ref, cur = smooth[0], 0
    for i in range(1, n):
        gap = (dates[i] - dates[i - 1]).days
        thresh = max(ref * boundary_pct, boundary_abs)
        if gap >= gap_days:
            cur += 1; label[cur] = "REACTIVATE"
            pct[cur] = (smooth[i] - ref) / ref if ref else 0.0; ref = smooth[i]
        elif abs(smooth[i] - ref) > thresh:
            cur += 1; label[cur] = "INCREASE" if smooth[i] > ref else "DECREASE"
            pct[cur] = (smooth[i] - ref) / ref if ref else 0.0; ref = smooth[i]
        regime_id[i] = cur
    d["regime_id"] = regime_id
    d["entry_transition"] = d["regime_id"].map(label)
    d["entry_pct"] = d["regime_id"].map(pct)
    return d

def _strategy(entry_transition: str, regime_total_days: int,
              constant_min_days: int = C.CONSTANT_MIN_DAYS) -> str:
    if regime_total_days >= constant_min_days:
        return "CPC_HELD"
    return {"INCREASE": "CPC_RAISED", "DECREASE": "CPC_LOWERED",
            "LAUNCH": "LAUNCH", "REACTIVATE": "REACTIVATE"}.get(entry_transition, "CPC_HELD")

def summarize_regime_segments(daily_with_regimes: pd.DataFrame,
                              constant_min_days: int = C.CONSTANT_MIN_DAYS) -> pd.DataFrame:
    """Group by regime × calendar_segment → one row per regime-segment."""
    d = daily_with_regimes
    keys = ["parent_name", "campaign_id", "target_key", "regime_id",
            "calendar_segment", "entry_transition"]
    g = (d.groupby(keys, dropna=False)
           .agg(days=("date", "nunique"), start=("date", "min"), end=("date", "max"),
                clicks=("clicks", "sum"), cost=("cost", "sum"), orders=("orders", "sum"),
                units=("units", "sum"), sales=("sales", "sum"),
                gross_profit=("gross_profit", "sum"), net_profit=("net_profit", "sum"),
                entry_pct=("entry_pct", "first"),
                tos_cost_share=("tos_cost_share", "mean"),
                tos_bid_adj_pct=("tos_bid_adj_pct", "mean"))
           .reset_index())
    g["cpc"] = g["cost"] / g["clicks"].where(g["clicks"] != 0)
    g["net_profit_per_day"] = g["net_profit"] / g["days"].where(g["days"] != 0)
    dur = (d.groupby(["target_key", "regime_id"])["date"].nunique()
             .rename("regime_total_days").reset_index())
    g = g.merge(dur, on=["target_key", "regime_id"], how="left")
    g["magnitude"] = g["entry_pct"].apply(magnitude_tier)
    g["strategy"] = [
        _strategy(t, rd, constant_min_days)
        for t, rd in zip(g["entry_transition"], g["regime_total_days"])]
    return g
