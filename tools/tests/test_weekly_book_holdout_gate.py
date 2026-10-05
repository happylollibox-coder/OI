"""The weekly book's final holdout gate (holdout restart, 2026-10-05): a row from any source, a reused
stage included, on a campaign whose arm binds today goes to Refused with a HOLDOUT reason."""
import importlib.util
import os

_spec = importlib.util.spec_from_file_location(
    'build_weekly_book', os.path.join(os.path.dirname(__file__), '..', 'build_weekly_book.py'))
wb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wb)

ARM = [{'campaign_id': '537046793426450', 'gate_from': '2026-10-05', 'gate_to': '2027-01-26',
        'trial_id': 'HOLDOUT-2026Q4-CAMPAIGN-T2'}]


def _rec(source, cid, story='kept story'):
    return {'source': source, 'sheet': 'Sponsored Products Campaigns', 'cells': {'Bid': 1.0},
            'audit': {'campaign_id': cid, 'story': story}}


def test_a_control_row_from_any_source_is_refused():
    recs = [_rec('reprice', '537046793426450'), _rec('seats', 537046793426450),
            _rec('mend', '537046793426450'), _rec('plan-budgets', '27660342907703')]
    kept, held = wb.final_holdout_gate(recs, arm=ARM)
    assert [r['audit']['campaign_id'] for r in kept] == ['27660342907703']
    assert len(held) == 3
    for r in held:
        assert r['sheet'] is None and r['cells'] is None
        assert r['audit']['story'].startswith('HOLDOUT:')
        assert r['audit']['reason'] == r['audit']['story']


def test_the_input_rows_are_not_mutated():
    rec = _rec('reprice', '537046793426450')
    wb.final_holdout_gate([rec], arm=ARM)
    assert rec['audit']['story'] == 'kept story' and rec['sheet'] is not None


def test_an_empty_arm_holds_nothing():
    recs = [_rec('reprice', '537046793426450'), _rec('seats', '1')]
    kept, held = wb.final_holdout_gate(recs, arm=[])
    assert len(kept) == 2 and held == []
