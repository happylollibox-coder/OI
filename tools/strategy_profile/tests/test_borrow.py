import pandas as pd
from tools.strategy_profile.borrow import fill_gaps
from tools.strategy_profile import config as C

def _profile(rows):
    cols = ["parent_name","season","match_type","intent_class","enabled",
            "cpc_target","cpc_min","cpc_max","launch_cpc","raise_pace_pct",
            "net_per_dollar","confidence","tos_target_pct","borrowed_from","source"]
    return pd.DataFrame([{**{c: None for c in cols}, **r} for r in rows])

def test_borrow_same_cell_other_season_with_haircut():
    # Fresh PEAK EXACT PRODUCT is CONCLUSIVE; Fresh OFF EXACT PRODUCT is WEAK -> borrow cross-season
    prof = _profile([
        dict(parent_name="Fresh", season="PEAK", match_type="EXACT", intent_class="PRODUCT",
             enabled=True, cpc_target=1.00, cpc_min=0.60, cpc_max=1.40, confidence="CONCLUSIVE", source="DERIVED"),
        dict(parent_name="Fresh", season="OFF", match_type="EXACT", intent_class="PRODUCT",
             enabled=True, cpc_target=0.50, cpc_min=0.30, cpc_max=0.70, confidence="WEAK", source="DERIVED"),
    ])
    cpc_by_pm = {("Fresh","EXACT"): 0.90}  # observed p50 CPC for this parent×match
    out = fill_gaps(prof, cpc_by_pm)
    off = out[(out.parent_name=="Fresh") & (out.season=="OFF") & (out.match_type=="EXACT") & (out.intent_class=="PRODUCT")].iloc[0]
    assert off["source"] == "BORROWED"
    assert off["borrowed_from"] == "Fresh|PEAK|EXACT|PRODUCT"
    assert round(off["cpc_target"], 2) == 0.80   # 80% of donor 1.00, same match -> no cost-adjust

def test_cross_match_cost_adjusts_to_target_cpc():
    # donor is EXACT (cpc_target 1.00), gap is PHRASE; borrowed cpc scales to PHRASE's own CPC level
    prof = _profile([
        dict(parent_name="Bottle", season="OFF", match_type="EXACT", intent_class="GENERIC",
             enabled=True, cpc_target=1.00, cpc_min=0.60, cpc_max=1.40, confidence="CONCLUSIVE", source="DERIVED"),
        dict(parent_name="Bottle", season="OFF", match_type="PHRASE", intent_class="GENERIC",
             enabled=True, cpc_target=None, cpc_min=None, cpc_max=None, confidence="WEAK", source="DERIVED"),
    ])
    cpc_by_pm = {("Bottle","EXACT"): 1.00, ("Bottle","PHRASE"): 0.50}
    out = fill_gaps(prof, cpc_by_pm)
    ph = out[(out.parent_name=="Bottle") & (out.match_type=="PHRASE")].iloc[0]
    assert ph["source"] == "BORROWED"
    # donor target 1.00 -> 80% haircut 0.80 -> cost-adjust by 0.50/1.00 -> 0.40
    assert round(ph["cpc_target"], 2) == 0.40

def test_manual_and_conclusive_untouched_no_donor_skipped():
    prof = _profile([
        dict(parent_name="X", season="OFF", match_type="EXACT", intent_class="BRAND",
             cpc_target=0.9, confidence="WEAK", source="MANUAL"),         # MANUAL: untouched
        dict(parent_name="X", season="OFF", match_type="BROAD", intent_class="GENERIC",
             cpc_target=0.4, confidence="WEAK", source="DERIVED"),         # no donor: skipped
    ])
    out = fill_gaps(prof, {})
    assert out[(out.source=="MANUAL")].iloc[0]["cpc_target"] == 0.9
    broad = out[(out.match_type=="BROAD")].iloc[0]
    assert broad["source"] == "DERIVED"           # unchanged, no donor
