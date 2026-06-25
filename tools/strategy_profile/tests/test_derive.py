import pandas as pd
from tools.strategy_profile.derive import (
    normalize_match_type, season_of, best_cpc_band, derive_profile, derive_main_keywords)

def test_normalize_match_type():
    assert normalize_match_type("broad") == "BROAD"
    assert normalize_match_type("EXACT") == "EXACT"
    assert normalize_match_type("asin") == "PRODUCT"
    assert normalize_match_type("weird") == "OTHER"

def test_season_of():
    assert season_of("Christmas_PEAK") == "PEAK"
    assert season_of("Easter_BOOST") == "PEAK"
    assert season_of("EVERYDAY_2026-01") == "OFF"
    assert season_of("Christmas_COOLDOWN") == "OFF"

def test_best_cpc_band_picks_most_profitable_contiguous_band():
    # net is highest in $0.50-0.60; positive contiguous 0.40-0.70; negative at 0.90
    df = pd.DataFrame({
        "cpc":        [0.45, 0.55, 0.65, 0.95],
        "net_profit": [10.0, 40.0, 15.0, -20.0],
        "clicks":     [10,   20,   10,   10],
    })
    target, lo, hi = best_cpc_band(df)
    assert 0.50 <= target <= 0.60          # midpoint of best band
    assert lo == 0.40 and hi == 0.70       # contiguous positive band edges

def test_best_cpc_band_all_negative_returns_none():
    df = pd.DataFrame({"cpc":[0.9,1.1], "net_profit":[-5.0,-9.0], "clicks":[5,5]})
    assert best_cpc_band(df) == (None, None, None)

def _base():
    # Fresh EXACT loses; Fresh BROAD profits; both off-season
    rows = []
    for cpc, net in [(0.55, 50.0)]*6:           # BROAD profitable, enough clicks/orders
        rows.append(("Fresh","EVERYDAY_2026-01","broad",cpc,net,40,2,"bath term"))
    for cpc, net in [(0.80, -30.0)]*6:          # EXACT loses
        rows.append(("Fresh","EVERYDAY_2026-01","exact",cpc,net,40,2,"exact bath"))
    return pd.DataFrame(rows, columns=["parent_name","calendar_segment","targeting_type",
                                       "cpc","net_profit","clicks","orders","targeting"])

def test_derive_profile_enables_profitable_suppresses_losing():
    prof = derive_profile(_base())
    broad = prof[(prof.match_type=="BROAD")].iloc[0]
    exact = prof[(prof.match_type=="EXACT")].iloc[0]
    assert broad.enabled == True and broad.net_per_dollar > 0
    assert exact.enabled == False and exact.net_per_dollar < 0
    assert broad.season == "OFF" and broad.parent_name == "Fresh"
    assert broad.source == "DERIVED"

def test_derive_main_keywords_ranks_top_n():
    df = pd.DataFrame({
        "parent_name":["Fresh"]*3, "targeting_type":["broad"]*3,
        "targeting":["a","b","c"], "keyword_id":["1","2","3"],
        "net_profit":[5.0, 50.0, 20.0], "clicks":[10,10,10],
    })
    mk = derive_main_keywords(df, top_n=2)
    assert list(mk.sort_values("rank")["keyword_text"]) == ["b","c"]   # top 2 by net
    assert (mk["is_anchor"] == True).all() and (mk["source"]=="DERIVED").all()
