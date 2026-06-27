"""Pure planning logic for the weekly plan (Coacher D). No I/O."""
from __future__ import annotations
import pandas as pd
from . import config as C

def assign_purpose(cell) -> str:
    """cell: dict-like with confidence, net_per_dollar, is_gap, is_brand, probe_active, is_bleeder."""
    if cell.get("is_brand"):
        return "DEFEND"
    if cell.get("is_bleeder") or (cell.get("net_per_dollar", 0) < 0 and cell.get("confidence") != "CONCLUSIVE"):
        return "CUT"
    if cell.get("probe_active"):
        return "PROBE"
    if cell.get("confidence") == "CONCLUSIVE" and cell.get("net_per_dollar", 0) > 0:
        return "SCALE"
    if cell.get("is_gap"):
        return "MAP"
    return "HOLD"

SUCCESS_METRIC = {"SCALE": "NET_PROFIT", "MAP": "CLICKS", "PROBE": "CLICKS",
                  "DEFEND": "TOS_SHARE", "CUT": "SPEND_DOWN", "HOLD": "HOLD"}

def expected_value(purpose: str, cell, planned_spend: float):
    if purpose in ("MAP", "PROBE"):
        return float(C.PROBE_CLICKS)
    if purpose == "SCALE":
        return round((cell.get("net_per_dollar") or 0) * (planned_spend or 0), 2)
    return None  # DEFEND/CUT/HOLD measured but no single expected scalar in v1

def allocate_budget(cells: pd.DataFrame, weekly_budget: float, peak: bool) -> pd.DataFrame:
    """Split weekly_budget across a product's cells. CAP (unproven) cells share <= EXPLORE_CAP_FRAC;
    SCALE/DEFEND cells take the remainder as a floor (they may run beyond it while profitable)."""
    df = cells.copy()
    if "purpose" not in df:
        df["purpose"] = [assign_purpose(r) for _, r in df.iterrows()]
    df["spend_mode"] = df["purpose"].map(lambda p: "SCALE" if p in ("SCALE", "DEFEND") else "CAP")
    cap_pool = C.EXPLORE_CAP_FRAC * weekly_budget
    cap_mask = df["spend_mode"] == "CAP"
    n_cap = int(cap_mask.sum())
    df.loc[cap_mask, "planned_spend"] = round(cap_pool / n_cap, 2) if n_cap else 0.0
    # SCALE/DEFEND share the remainder, weighted by net_per_dollar (peak cells boosted)
    scale_mask = ~cap_mask
    remainder = max(weekly_budget - cap_pool, 0.0)
    w = (df.loc[scale_mask, "net_per_dollar"].clip(lower=0.01)
         * (C.PEAK_BUDGET_MULT if peak else 1.0))
    wsum = w.sum()
    df.loc[scale_mask, "planned_spend"] = (
        (w / wsum * remainder).round(2) if wsum > 0 else 0.0)
    return df
