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

def _waterfill(weights: pd.Series, caps: pd.Series, budget: float) -> pd.Series:
    """Distribute `budget` across cells proportional to `weights`, with no cell exceeding its `caps`.
    Overflow from capped cells cascades to the cells still under their cap. Returns the allocation
    (may sum to < budget if every cell hits its cap — that leftover is genuine unabsorbable headroom)."""
    alloc = pd.Series(0.0, index=weights.index)
    active = [i for i in weights.index if weights[i] > 0 and caps[i] > 0]
    remaining = budget
    while remaining > 1e-6 and active:
        wsum = weights[active].sum()
        if wsum <= 0:
            break
        share = {i: remaining * weights[i] / wsum for i in active}
        over = [i for i in active if alloc[i] + share[i] > caps[i] + 1e-9]
        if not over:                          # everyone fits → place their share and finish
            for i in active:
                alloc[i] += share[i]
            break
        for i in over:                        # cap the overflowing cells, recycle the excess
            remaining -= (caps[i] - alloc[i])
            alloc[i] = caps[i]
            active.remove(i)
    return alloc


def allocate_budget(cells: pd.DataFrame, weekly_budget: float, peak: bool) -> pd.DataFrame:
    """Split weekly_budget across a product's cells. CAP (unproven) cells share <= EXPLORE_CAP_FRAC;
    SCALE/DEFEND cells take the remainder as a floor (they may run beyond it while profitable).

    Capacity cap: a SCALE/DEFEND cell's floor is capped at its trailing actual weekly spend
    (`recent_spend` column) x GROWTH_MULT (peak vs off), so a hyper-efficient but volume-tiny cell
    (e.g. brand-defense) can't hog budget it can't spend — the freed budget water-fills to the cells
    that can absorb it. Falls back to the old uncapped net_per_dollar split when no capacity data
    is available (no `recent_spend`, or none of the SCALE/DEFEND cells have spend history)."""
    df = cells.copy()
    if "purpose" not in df:
        df["purpose"] = [assign_purpose(r) for _, r in df.iterrows()]
    df["spend_mode"] = df["purpose"].map(lambda p: "SCALE" if p in ("SCALE", "DEFEND") else "CAP")
    cap_pool = C.EXPLORE_CAP_FRAC * weekly_budget
    cap_mask = df["spend_mode"] == "CAP"
    n_cap = int(cap_mask.sum())
    df.loc[cap_mask, "planned_spend"] = round(cap_pool / n_cap, 2) if n_cap else 0.0

    scale_mask = ~cap_mask
    remainder = max(weekly_budget - cap_pool, 0.0)
    w = df.loc[scale_mask, "net_per_dollar"].clip(lower=0.01)

    recent = (df.loc[scale_mask, "recent_spend"] if "recent_spend" in df.columns
              else pd.Series(0.0, index=df.index[scale_mask])).fillna(0.0)
    has_capacity = (recent > 0).any()
    if not has_capacity:
        # No per-cell spend history for this product → old behaviour (uncapped, peak-weighted).
        wp = w * (C.PEAK_BUDGET_MULT if peak else 1.0)
        wsum = wp.sum()
        df.loc[scale_mask, "planned_spend"] = (wp / wsum * remainder).round(2) if wsum > 0 else 0.0
        return df

    # Capacity-aware: cap each cell's floor at recent_spend x growth mult; cells with no history
    # (a freshly-filled gap) get a small default cap so they aren't starved to $0.
    mult = C.GROWTH_MULT_PEAK if peak else C.GROWTH_MULT_OFF
    caps = recent * mult
    caps = caps.where(recent > 0, C.NEW_CELL_CAP_FRAC * weekly_budget)
    alloc = _waterfill(w, caps, remainder)
    df.loc[scale_mask, "planned_spend"] = alloc.round(2)
    return df
