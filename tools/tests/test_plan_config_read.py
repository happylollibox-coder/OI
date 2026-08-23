"""read_plan_config() — the generator's settings come from DE_PLAN_CONFIG, never from itself.

v27.131. The defect this covers: tools/build_reprice_bulksheet.py declared PLAN_WINDOW_DAYS and
RULE_B_MIN_ORDERS as module constants and printed, in every book, that the plan's settings table
"does not exist yet". The table exists and is deployed, so a setting Ori changed there would never
have reached the one book that currently moves money, and the book said so in words that were
false. These tests stub the `bq` subprocess so they run offline and prove the wiring, not the
warehouse.
"""
import json
import subprocess
import sys
import os
from types import SimpleNamespace

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import build_reprice_bulksheet as m  # noqa: E402


def _rows(off=7, boost=3, peak=3, floor=2):
    return json.dumps([
        {'calendar_state': 'OFF_PEAK', 'window_days': off,   'min_orders': floor,
         'allowance_share': 0.2, 'ramp_steps': 3, 'live_plan': 'B'},
        {'calendar_state': 'BOOST',    'window_days': boost, 'min_orders': floor,
         'allowance_share': 0.5, 'ramp_steps': 3, 'live_plan': 'B'},
        {'calendar_state': 'PEAK',     'window_days': peak,  'min_orders': floor,
         'allowance_share': 0.2, 'ramp_steps': 3, 'live_plan': 'B'},
    ])


@pytest.fixture(autouse=True)
def reset_module_settings():
    """Every test starts from the declared fallback, and leaves it there."""
    m.PLAN_WINDOW_DAYS = {'OFF_PEAK': 7, 'BOOST': 3, 'PEAK': 3}
    m.RULE_B_MIN_ORDERS = 2
    m.PLAN_CONFIG_SOURCE = 'fallback'
    yield
    m.PLAN_WINDOW_DAYS = {'OFF_PEAK': 7, 'BOOST': 3, 'PEAK': 3}
    m.RULE_B_MIN_ORDERS = 2
    m.PLAN_CONFIG_SOURCE = 'fallback'


def _stub(monkeypatch, returncode=0, stdout='[]', stderr=''):
    monkeypatch.setattr(subprocess, 'run',
                        lambda *a, **k: SimpleNamespace(returncode=returncode,
                                                        stdout=stdout, stderr=stderr))


def test_a_changed_setting_reaches_the_generator(monkeypatch):
    """The whole point: Ori widens the peak window to 5 and raises the floor to 3, with no deploy."""
    _stub(monkeypatch, stdout=_rows(off=10, boost=4, peak=5, floor=3))
    m.read_plan_config()
    assert m.PLAN_WINDOW_DAYS == {'OFF_PEAK': 10, 'BOOST': 4, 'PEAK': 5}
    assert m.RULE_B_MIN_ORDERS == 3
    assert m.PLAN_CONFIG_SOURCE == 'DE_PLAN_CONFIG'


def test_the_source_is_recorded_so_the_readme_can_say_which_it_used(monkeypatch):
    _stub(monkeypatch, stdout=_rows())
    m.read_plan_config()
    assert m.PLAN_CONFIG_SOURCE == 'DE_PLAN_CONFIG'


def test_an_unreadable_table_falls_back_and_says_so(monkeypatch, capsys):
    _stub(monkeypatch, returncode=1, stderr='Not found: Table OI.DE_PLAN_CONFIG')
    assert m.read_plan_config() == {}
    assert m.PLAN_WINDOW_DAYS == {'OFF_PEAK': 7, 'BOOST': 3, 'PEAK': 3}
    assert m.PLAN_CONFIG_SOURCE == 'fallback'
    assert 'fallback' in capsys.readouterr().out


def test_a_missing_state_falls_back_rather_than_guessing(monkeypatch):
    partial = json.dumps([{'calendar_state': 'PEAK', 'window_days': 3, 'min_orders': 2,
                           'allowance_share': 0.2, 'ramp_steps': 3, 'live_plan': 'B'}])
    _stub(monkeypatch, stdout=partial)
    assert m.read_plan_config() == {}
    assert m.PLAN_CONFIG_SOURCE == 'fallback'


def test_disagreeing_order_floors_stop_the_build(monkeypatch):
    """Rule B has ONE order floor (P-3). Two different ones is a contradiction, not a setting."""
    rows = json.loads(_rows())
    rows[1]['min_orders'] = 5
    _stub(monkeypatch, stdout=json.dumps(rows))
    with pytest.raises(SystemExit) as e:
        m.read_plan_config()
    assert 'min_orders' in str(e.value)
