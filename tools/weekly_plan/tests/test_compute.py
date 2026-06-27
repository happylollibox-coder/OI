import pandas as pd
from tools.weekly_plan.compute import assign_purpose, expected_value, allocate_budget
from tools.weekly_plan import config as C

def _cell(**kw):
    base = dict(parent_name="Fresh", season="OFF", match_type="EXACT", intent_class="PRODUCT",
                confidence="CONCLUSIVE", net_per_dollar=0.5, cpc_target=0.9, source="DERIVED",
                is_gap=False, is_brand=False, probe_active=False, net_trend=100.0, is_bleeder=False)
    base.update(kw); return base

def test_assign_purpose_scale_map_defend_cut():
    assert assign_purpose(_cell(confidence="CONCLUSIVE", net_per_dollar=0.5)) == "SCALE"
    assert assign_purpose(_cell(confidence="WEAK", is_gap=True, net_per_dollar=0.0)) == "MAP"
    assert assign_purpose(_cell(is_brand=True)) == "DEFEND"
    assert assign_purpose(_cell(is_bleeder=True, net_per_dollar=-0.3, confidence="WEAK")) == "CUT"

def test_expected_value_by_purpose():
    assert expected_value("MAP", _cell(), planned_spend=20) == C.PROBE_CLICKS
    # SCALE expected NP = net_per_dollar * planned_spend
    assert round(expected_value("SCALE", _cell(net_per_dollar=0.5), planned_spend=200), 1) == 100.0

def test_allocate_budget_scale_uncapped_cap_limited():
    cells = pd.DataFrame([
        _cell(parent_name="Fresh", match_type="EXACT", net_per_dollar=0.6),
        _cell(parent_name="Fresh", match_type="BROAD", net_per_dollar=0.0, confidence="WEAK", is_gap=True),
    ])
    cells["purpose"] = [assign_purpose(r) for _, r in cells.iterrows()]
    out = allocate_budget(cells, weekly_budget=1000.0, peak=False)
    scale = out[out.purpose == "SCALE"].iloc[0]
    cap = out[out.purpose == "MAP"].iloc[0]
    assert scale["spend_mode"] == "SCALE"
    assert cap["spend_mode"] == "CAP"
    # CAP cells together <= EXPLORE_CAP_FRAC * budget
    assert out[out.spend_mode == "CAP"]["planned_spend"].sum() <= C.EXPLORE_CAP_FRAC * 1000 + 1e-6
    # SCALE gets the rest (the floor)
    assert scale["planned_spend"] > cap["planned_spend"]
