"""RULE B, tested on fixtures — no BigQuery, no sheet, no upload.

Rule B (spec docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md, rulings P-1..P-13)
judges a keyword on the WINDOW — the declared number of COMPLETE days ending at the ads
watermark minus one — and not on the ladder's 90-day record. The good side is never cut and is
never re-priced (P-4), so the reprice book's --rule-b arm drops every row on a good keyword in
BOTH directions and keeps every row on a keyword the window does not call good.

Every rule below is a pure function in tools/build_reprice_bulksheet.py, so it can be read and
challenged without a warehouse. The live-data assertions (the window is complete days only; the
dropped rows are named in the audit and the README) run inside the generator itself.
"""
import os
import sys
from datetime import date

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

from build_reprice_bulksheet import (  # noqa: E402
    EXECUTABLE, GRACE_LADDER_STATES, PLAN_WINDOW_DAYS, RULE_B_GOOD, RULE_B_MIN_ORDERS,
    assert_window_complete, build_parser, calendar_state, rule_b, rule_b_gate, window_bounds)

WM = date(2026, 8, 22)          # the ads watermark: the newest ads day, still filling
BAR = 1.20                      # a family bar (T_FAMILY_BAR), the ladder's own number


def kw(**over):
    """A keyword row as the generator's query hands it over: a LOSING window by default —
    2 settled orders in the window at a return under its family bar."""
    r = dict(
        campaign_id='1', keyword_id='9', target_text='school gifts for teens',
        campaign_name='BOX-SP/EXACT (Back to School)', family='Lollibox',
        state='REPRICE', family_bar=BAR,
        w_ord=2, w_clk=40, w_sp=20.00, w_gp=12.00,          # 0.60x — below the 1.20 bar
        window_from='2026-08-19', window_to='2026-08-21', window_days=3,
        calendar_state='PEAK',
    )
    r.update(over)
    return r


# ── P-3: what the window calls good ───────────────────────────────────────────────────────────

def test_two_orders_at_or_above_the_bar_is_good():
    v = rule_b(kw(w_ord=2, w_sp=20.00, w_gp=24.00))     # exactly 1.20x — at the bar
    assert v['good'] is True
    assert v['verdict'] == 'GOOD'


def test_two_orders_below_the_bar_is_losing_not_good():
    v = rule_b(kw())
    assert v['good'] is False
    assert v['verdict'] == 'LOSING'


def test_one_order_is_never_good_whatever_the_return():
    """P-3: one order at 3x is mostly luck; the 2-order floor is the cheapest guard."""
    v = rule_b(kw(w_ord=1, w_sp=10.00, w_gp=36.00))     # 3.6x on one order
    assert v['good'] is False
    assert v['verdict'] == 'ONE_ORDER'


def test_spent_with_no_order_is_never_good():
    v = rule_b(kw(w_ord=0, w_clk=25, w_sp=18.00, w_gp=0.0))
    assert v['good'] is False
    assert v['verdict'] == 'NO_SALE'


def test_no_spend_and_no_clicks_is_not_serving_and_not_good():
    v = rule_b(kw(w_ord=0, w_clk=0, w_sp=0.0, w_gp=0.0))
    assert v['good'] is False
    assert v['verdict'] == 'NOT_SERVING'


def test_the_order_floor_is_the_declared_two():
    assert RULE_B_MIN_ORDERS == 2


# ── P-4: the good side is dropped in BOTH directions ──────────────────────────────────────────

def test_a_good_keyword_is_dropped_when_the_book_would_cut_it():
    r = kw(w_ord=3, w_sp=20.00, w_gp=30.00)             # 1.50x on 3 orders — good
    bits = {}
    disp, v = rule_b_gate('BID_DOWN', r, bits)
    assert disp == RULE_B_GOOD
    assert bits['rule_b'] is v and v['good'] is True


def test_a_good_keyword_is_dropped_when_the_book_would_raise_it():
    r = kw(w_ord=3, w_sp=20.00, w_gp=30.00)
    disp, v = rule_b_gate('BID_UP', r, {})
    assert disp == RULE_B_GOOD


def test_a_good_keyword_is_dropped_when_the_book_would_pause_it():
    r = kw(state='LOSER', w_ord=3, w_sp=20.00, w_gp=30.00)
    disp, _ = rule_b_gate('PAUSE', r, {})
    assert disp == RULE_B_GOOD


def test_a_losing_keyword_keeps_its_row():
    for d in EXECUTABLE:
        disp, v = rule_b_gate(d, kw(), {})
        assert disp == d, f"{d} on a losing window must survive rule B"
        assert v['good'] is False


def test_a_one_order_keyword_keeps_its_row():
    disp, _ = rule_b_gate('BID_DOWN', kw(w_ord=1, w_sp=10.00, w_gp=36.00), {})
    assert disp == 'BID_DOWN'


def test_a_no_sale_keyword_keeps_its_row():
    disp, _ = rule_b_gate('BID_DOWN', kw(w_ord=0, w_clk=25, w_sp=18.00, w_gp=0.0), {})
    assert disp == 'BID_DOWN'


def test_the_gate_never_invents_a_row_out_of_a_non_executable_one():
    """A row the book already declined stays declined — rule B only ever REMOVES."""
    disp, _ = rule_b_gate('TOO_THIN', kw(w_ord=3, w_sp=20.00, w_gp=30.00), {})
    assert disp == 'TOO_THIN'


def test_every_dropped_row_carries_a_reason():
    _, v = rule_b_gate('BID_DOWN', kw(w_ord=3, w_sp=20.00, w_gp=30.00), {})
    assert v['reason'] and len(v['reason']) > 20, "a dropped row is never silent"


# ── P-5: grace for a proven winner with a quiet window ────────────────────────────────────────

def test_a_ladder_winner_with_a_quiet_window_is_dropped_by_grace():
    for state in GRACE_LADDER_STATES:
        r = kw(state=state, w_ord=0, w_clk=6, w_sp=4.00, w_gp=0.0)
        v = rule_b(r)
        assert v['good'] is True, f"{state} with a quiet window keeps the good side for one window"
        assert v['verdict'] == 'GRACE'
        disp, _ = rule_b_gate('BID_DOWN', r, {})
        assert disp == RULE_B_GOOD


def test_grace_covers_the_one_order_window_too():
    v = rule_b(kw(state='WINNER', w_ord=1, w_sp=10.00, w_gp=2.00))
    assert v['good'] is True and v['verdict'] == 'GRACE'


def test_grace_does_not_cover_a_window_that_actually_lost():
    """A window with 2+ orders is evidence, not quiet: rule B stands over the ladder."""
    v = rule_b(kw(state='WINNER', w_ord=2, w_sp=20.00, w_gp=12.00))
    assert v['good'] is False
    assert v['verdict'] == 'LOSING'


def test_grace_is_not_granted_to_a_ladder_state_that_is_not_a_winner():
    v = rule_b(kw(state='REPRICE', w_ord=0, w_clk=6, w_sp=4.00, w_gp=0.0))
    assert v['good'] is False and v['verdict'] == 'NO_SALE'


# ── P-10: complete days only ──────────────────────────────────────────────────────────────────

def test_the_window_ends_the_day_before_the_watermark():
    lo, hi = window_bounds(WM, 7)
    assert hi == date(2026, 8, 21), "the filling day never enters a window"
    assert lo == date(2026, 8, 15)
    assert (hi - lo).days + 1 == 7, "seven complete days, inclusive"


def test_a_peak_window_is_three_complete_days():
    lo, hi = window_bounds(WM, 3)
    assert (lo, hi) == (date(2026, 8, 19), date(2026, 8, 21))


def test_a_window_that_touches_the_filling_day_is_refused():
    with pytest.raises(AssertionError):
        assert_window_complete(WM, date(2026, 8, 16), WM, 7)


def test_a_window_of_the_wrong_length_is_refused():
    with pytest.raises(AssertionError):
        assert_window_complete(WM, date(2026, 8, 17), date(2026, 8, 21), 7)


def test_the_declared_window_matches_the_asserted_one():
    lo, hi = window_bounds(WM, PLAN_WINDOW_DAYS['OFF_PEAK'])
    assert_window_complete(WM, lo, hi, PLAN_WINDOW_DAYS['OFF_PEAK'])


# ── P-13: the calendar states and their declared windows ──────────────────────────────────────

def test_the_declared_windows_are_seven_off_peak_and_three_in_a_peak():
    assert PLAN_WINDOW_DAYS == {'OFF_PEAK': 7, 'BOOST': 3, 'PEAK': 3}


def test_the_calendar_state_reads_the_house_calendar():
    assert calendar_state(False, None, date(2026, 3, 1)) == 'OFF_PEAK'
    assert calendar_state(True, date(2026, 8, 10), date(2026, 8, 5)) == 'BOOST'
    assert calendar_state(True, date(2026, 8, 10), date(2026, 8, 23)) == 'PEAK'
    assert calendar_state(True, None, date(2026, 8, 23)) == 'PEAK', \
        "a peak whose peak_start the calendar does not carry is judged as a peak (same window)"


# ── the flag itself ───────────────────────────────────────────────────────────────────────────

def test_rule_b_is_off_by_default():
    args = build_parser().parse_args([])
    assert args.rule_b is False, "nothing else changes unless --rule-b is asked for"


def test_rule_b_turns_on_with_the_flag():
    assert build_parser().parse_args(['--rule-b']).rule_b is True
