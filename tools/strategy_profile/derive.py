# tools/strategy_profile/derive.py
"""Pure derivation of the per-product strategy profile + main keywords from the keyword-day base."""
from __future__ import annotations
import math
import pandas as pd
from . import config as C

def normalize_match_type(targeting_type: str) -> str:
    return C.MATCH_MAP.get(str(targeting_type).lower(), "OTHER")

def season_of(calendar_segment: str) -> str:
    s = str(calendar_segment)
    return "PEAK" if (s.endswith("_BOOST") or s.endswith("_PEAK")) else "OFF"

def best_cpc_band(cell: pd.DataFrame, cpc_bin: float = C.CPC_BIN):
    """Return (target, lo, hi) for the most profitable contiguous run of CPC bins, or (None,None,None)."""
    if cell.empty:
        return (None, None, None)
    b = cell.assign(band=(cell["cpc"] / cpc_bin).apply(math.floor).astype(int))
    net = b.groupby("band")["net_profit"].sum().sort_index()
    pos = net[net > 0]
    if pos.empty:
        return (None, None, None)
    best = int(net.idxmax())
    if net.get(best, 0) <= 0:
        return (None, None, None)
    lo = best
    while (lo - 1) in net.index and net[lo - 1] > 0:
        lo -= 1
    hi = best
    while (hi + 1) in net.index and net[hi + 1] > 0:
        hi += 1
    target = round((best + 0.5) * cpc_bin, 2)
    return (target, round(lo * cpc_bin, 2), round((hi + 1) * cpc_bin, 2))

def derive_profile(base: pd.DataFrame) -> pd.DataFrame:
    """base: keyword-day rows with parent_name, calendar_segment, targeting_type, intent_class, cpc, net_profit, clicks, orders."""
    d = base.copy()
    d["match_type"] = d["targeting_type"].map(normalize_match_type)
    d["season"] = d["calendar_segment"].map(season_of)
    if "intent_class" not in d.columns:
        d["intent_class"] = "GENERIC"
    rows = []
    for (parent, season, mt, intent), cell in d.groupby(["parent_name", "season", "match_type", "intent_class"]):
        cost = cell["cost"].sum() if "cost" in cell else (cell["cpc"] * cell["clicks"]).sum()
        net = cell["net_profit"].sum()
        npd = net / cost if cost else 0.0
        target, lo, hi = best_cpc_band(cell)
        conclusive = cell["clicks"].sum() >= C.MIN_CLICKS and cell["orders"].sum() >= C.MIN_ORDERS
        enabled = bool(npd > 0) or (intent == "BRAND")   # BRAND always defended
        rows.append(dict(
            parent_name=parent, season=season, match_type=mt, intent_class=intent,
            enabled=enabled, cpc_target=target, cpc_min=lo, cpc_max=hi,
            launch_cpc=lo, raise_pace_pct=C.RAISE_PACE_PCT,
            net_per_dollar=round(npd, 3),
            confidence="CONCLUSIVE" if conclusive else "WEAK",
            tos_target_pct=None, borrowed_from=None, source="DERIVED"))
    return pd.DataFrame(rows)

def derive_main_keywords(base: pd.DataFrame, top_n: int = C.TOP_N_KEYWORDS) -> pd.DataFrame:
    d = base.copy()
    d["match_type"] = d["targeting_type"].map(normalize_match_type)
    g = (d.groupby(["parent_name", "match_type", "targeting"], dropna=False)
           .agg(net_profit_90d=("net_profit", "sum"),
                keyword_id=("keyword_id", "first") if "keyword_id" in d else ("targeting", "first"))
           .reset_index())
    g["rank"] = (g.groupby(["parent_name", "match_type"])["net_profit_90d"]
                   .rank(ascending=False, method="first").astype(int))
    g = g[g["rank"] <= top_n].copy()
    g = g.rename(columns={"targeting": "keyword_text"})
    g["is_anchor"] = True
    g["source"] = "DERIVED"
    return g[["parent_name", "keyword_text", "keyword_id", "match_type",
              "rank", "net_profit_90d", "is_anchor", "source"]]
