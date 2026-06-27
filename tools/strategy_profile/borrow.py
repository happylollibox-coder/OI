# tools/strategy_profile/borrow.py
"""Fill non-CONCLUSIVE profile cells by borrowing a similar CONCLUSIVE donor (capped, labeled)."""
from __future__ import annotations
import pandas as pd
from . import config as C

STEER_COLS = ["enabled", "cpc_target", "cpc_min", "cpc_max", "launch_cpc",
              "raise_pace_pct", "net_per_dollar", "tos_target_pct"]

def _key(r) -> str:
    return f"{r['parent_name']}|{r['season']}|{r['match_type']}|{r['intent_class']}"

def _match_distance(a: str, b: str) -> int:
    if a == b:
        return 0
    return C.MATCH_DISTANCE.get((a, b)) or C.MATCH_DISTANCE.get((b, a), 99)

def _rank_donor(gap, cand) -> tuple | None:
    """Lower tuple = better donor. None if cand is not a valid donor for gap."""
    if cand["confidence"] != "CONCLUSIVE":
        return None
    if cand["intent_class"] != gap["intent_class"]:
        return None
    same_parent = cand["parent_name"] == gap["parent_name"]
    same_match = cand["match_type"] == gap["match_type"]
    if same_parent and same_match:                       # ladder 1: other season, same cell
        return (1, 0)
    if same_parent:                                      # ladder 2: same parent, nearest match
        return (2, _match_distance(gap["match_type"], cand["match_type"]))
    if same_match:                                       # ladder 3: sibling parent, same match
        return (3, 0)
    return (4, 0)                                        # ladder 4: same intent aggregate

def fill_gaps(profile: pd.DataFrame, cpc_by_pm: dict) -> pd.DataFrame:
    """profile: the full DE_PRODUCT_STRATEGY_PROFILE-shaped frame (DERIVED+MANUAL).
    cpc_by_pm: {(parent, match_type): observed p50 cost_per_click} for cross-match cost-adjust.
    Returns the frame with BORROWED rows filled in for gap cells that have a donor."""
    df = profile.copy()
    donors = df[df["confidence"] == "CONCLUSIVE"].to_dict("records")
    out_rows = []
    for _, gap in df.iterrows():
        g = gap.to_dict()
        is_gap = (g.get("source") != "MANUAL") and (g.get("confidence") != "CONCLUSIVE")
        if not is_gap:
            out_rows.append(g)
            continue
        ranked = sorted(
            ((_rank_donor(g, d), d) for d in donors),
            key=lambda t: (t[0] is None, t[0] if t[0] else (99, 99)))
        best = next(((r, d) for r, d in ranked if r is not None), None)
        if best is None:
            out_rows.append(g)                           # no donor -> leave as-is (probe path)
            continue
        _, donor = best
        new = dict(g)
        for col in STEER_COLS:
            new[col] = donor.get(col)
        # cap: 80% haircut on cpc_target, clamp cpc_* to <= donor and <= global ceiling
        haircut = (donor["cpc_target"] or 0) * C.BORROW_HAIRCUT
        # cross-match cost-adjust: scale to the TARGET cell's own match-type CPC level
        donor_cpc = cpc_by_pm.get((donor["parent_name"], donor["match_type"]))
        gap_cpc = cpc_by_pm.get((g["parent_name"], g["match_type"]))
        scale = (gap_cpc / donor_cpc) if (donor_cpc and gap_cpc and donor["match_type"] != g["match_type"]) else 1.0
        for col in ("cpc_target", "cpc_min", "cpc_max", "launch_cpc"):
            v = new.get(col)
            if v is None:
                continue
            v = min(v, haircut if col == "cpc_target" else v) * scale
            new[col] = round(min(v, donor.get(col, v), C.GLOBAL_BID_CAP), 2)
        new["source"] = "BORROWED"
        new["borrowed_from"] = _key(donor)
        new["confidence"] = donor["confidence"]
        out_rows.append(new)
    return pd.DataFrame(out_rows)
