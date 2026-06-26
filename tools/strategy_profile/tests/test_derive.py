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

def test_derive_profile_groups_by_intent_and_brand_is_enabled():
    import pandas as pd
    from tools.strategy_profile.derive import derive_profile
    rows = []
    # LolliME EXACT, two intents: PRODUCT profits, GENERIC loses; plus a BRAND losing cell
    for cpc, net in [(0.75, 30.0)]*6:
        rows.append(("LolliME","Christmas_PEAK","exact","PRODUCT",cpc,net,40,2,"journal for girls"))
    for cpc, net in [(0.80, -25.0)]*6:
        rows.append(("LolliME","Christmas_PEAK","exact","GENERIC",cpc,net,40,2,"gift for girls"))
    for cpc, net in [(0.50, -10.0)]*6:
        rows.append(("LolliME","Christmas_PEAK","exact","BRAND",cpc,net,40,2,"happy lolli journal"))
    df = pd.DataFrame(rows, columns=["parent_name","calendar_segment","targeting_type","intent_class",
                                     "cpc","net_profit","clicks","orders","targeting"])
    prof = derive_profile(df)
    prod = prof[(prof.intent_class=="PRODUCT")].iloc[0]
    gen  = prof[(prof.intent_class=="GENERIC")].iloc[0]
    brand= prof[(prof.intent_class=="BRAND")].iloc[0]
    assert set(["parent_name","season","match_type","intent_class","enabled"]).issubset(prof.columns)
    assert prod.enabled == True                 # product profits -> enabled
    assert gen.enabled == False                 # generic loses -> disabled
    assert brand.enabled == True                # BRAND always enabled (defense) despite negative net


from tools.strategy_profile.load import to_json_rows

def test_to_json_rows_stamps_audit_fields():
    import pandas as pd
    df = pd.DataFrame([{"parent_name":"Fresh","season":"OFF","match_type":"BROAD",
                        "enabled":True,"cpc_target":0.55,"cpc_min":0.4,"cpc_max":0.7,
                        "launch_cpc":0.4,"raise_pace_pct":15.0,"net_per_dollar":0.8,
                        "confidence":"CONCLUSIVE","tos_target_pct":None,"borrowed_from":None,
                        "source":"DERIVED"}])
    rows = to_json_rows(df, updated_by="strategy_profile_tool")
    assert rows[0]["updated_by"] == "strategy_profile_tool"
    assert "updated_at" in rows[0] and rows[0]["enabled"] is True
