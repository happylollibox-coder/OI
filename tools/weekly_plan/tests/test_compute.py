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

def test_allocate_budget_capacity_caps_defend_hog():
    # A hyper-efficient but volume-tiny DEFEND cell (brand) must NOT hog the budget: its floor is
    # capped at recent_spend x 1.5, and a real SCALE cell with capacity absorbs the freed budget.
    cells = pd.DataFrame([
        _cell(parent_name="LolliME", match_type="PHRASE", intent_class="BRAND",
              is_brand=True, net_per_dollar=6.2, recent_spend=8.0),      # DEFEND, tiny capacity
        _cell(parent_name="LolliME", match_type="BROAD", intent_class="PRODUCT",
              net_per_dollar=0.33, recent_spend=610.0),                  # SCALE, big capacity
    ])
    cells["purpose"] = [assign_purpose(r) for _, r in cells.iterrows()]
    out = allocate_budget(cells, weekly_budget=2000.0, peak=False)
    defend = out[out.purpose == "DEFEND"].iloc[0]
    scale = out[out.purpose == "SCALE"].iloc[0]
    # DEFEND floor capped at ~8 * 1.5 = 12 (was ~1,456 under the old net_per_dollar-only split)
    assert defend["planned_spend"] <= 8.0 * C.GROWTH_MULT_OFF + 1e-6
    # the SCALE cell absorbs the freed budget, up to its own cap (610 * 1.5 = 915)
    assert scale["planned_spend"] > defend["planned_spend"]
    assert scale["planned_spend"] <= 610.0 * C.GROWTH_MULT_OFF + 1e-6

def test_allocate_budget_peak_gives_more_headroom():
    # same cell, peak season → 3x cap instead of 1.5x
    cells = pd.DataFrame([
        _cell(parent_name="LolliME", match_type="BROAD", intent_class="PRODUCT",
              net_per_dollar=0.33, recent_spend=200.0),
    ])
    cells["purpose"] = [assign_purpose(r) for _, r in cells.iterrows()]
    off = allocate_budget(cells.copy(), weekly_budget=5000.0, peak=False).iloc[0]["planned_spend"]
    pk = allocate_budget(cells.copy(), weekly_budget=5000.0, peak=True).iloc[0]["planned_spend"]
    assert round(off, 0) == round(200.0 * C.GROWTH_MULT_OFF, 0)   # 300
    assert round(pk, 0) == round(200.0 * C.GROWTH_MULT_PEAK, 0)   # 600
