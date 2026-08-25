"""Preflight must REFUSE, not warn — and these prove the checks have teeth.

Every case here poisons a row that is otherwise real and asserts the build dies. Written after a
defect in build_weekly_book.py itself: the portfolio echo was joined and never SELECTed, so
`echo_portfolio_id` was always None, `never_had` read that as "this campaign never belonged to a
portfolio", and preflight waved through three Campaign rows whose blank Portfolio ID would have
DETACHED them. The lesson is in the second test: an escape hatch keyed on a NULL cannot tell absence
from breakage.

Run: /usr/bin/python3 -m pytest tools/tests/test_weekly_book_preflight.py -q
"""
import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import build_weekly_book as w  # noqa: E402


def _campaign_row(is_sb=False, **audit):
    headers = w.SB_HEADERS if is_sb else w.SP_HEADERS
    cells = {h: '' for h in headers}
    cells.update({'Product': 'Sponsored Brands' if is_sb else 'Sponsored Products',
                  'Entity': 'Campaign', 'Operation': 'Update'})
    cells['Portfolio Id' if is_sb else 'Portfolio ID'] = '41310184067669'
    a = {'campaign': 'TEST-CAMPAIGN', 'campaign_id': '123', 'target': '(whole campaign)',
         'disposition': 'BUDGET_DOWN', '_never_had_portfolio': False,
         '_old_budget': 10.0, '_new_budget': 5.0}
    a.update(audit)
    return {'source': 'plan-budgets', 'sheet': w.SB_SHEET if is_sb else w.SP_SHEET,
            'cells': cells, 'audit': a}


def test_clean_row_passes():
    assert w.preflight([_campaign_row()]) is True


@pytest.mark.parametrize('is_sb', [False, True])
def test_blank_portfolio_on_campaign_row_is_refused(is_sb):
    """Blank is not 'unchanged' on a Campaign Update row — it DETACHES."""
    rec = _campaign_row(is_sb)
    rec['cells']['Portfolio Id' if is_sb else 'Portfolio ID'] = ''
    with pytest.raises(SystemExit) as e:
        w.preflight([rec])
    assert 'DETACH' in str(e.value)


def test_blank_portfolio_allowed_only_when_history_was_actually_read():
    """The escape hatch must be keyed on a fact the query asserts, not on a NULL.

    A campaign genuinely absent from every portfolio may ship a blank. A campaign whose history was
    never consulted may NOT — that is indistinguishable from a broken join, which is exactly the
    defect this file was written for."""
    genuine = _campaign_row(_never_had_portfolio=True)
    genuine['cells']['Portfolio ID'] = ''
    assert w.preflight([genuine]) is True

    broken_lookup = _campaign_row(_never_had_portfolio=False)
    broken_lookup['cells']['Portfolio ID'] = ''
    with pytest.raises(SystemExit):
        w.preflight([broken_lookup])


def test_filled_sb_campaign_name_is_refused():
    """'Campaign Name' is a REAL column on the SB sheet — filling it RENAMES the campaign."""
    rec = _campaign_row(is_sb=True)
    rec['cells']['Campaign Name'] = 'WHATEVER THE WAREHOUSE HELD AT BUILD TIME'
    with pytest.raises(SystemExit) as e:
        w.preflight([rec])
    assert 'RENAME' in str(e.value)


@pytest.mark.parametrize('col', ['Product', 'Entity', 'Operation'])
def test_missing_required_column_is_refused(col):
    rec = _campaign_row()
    rec['cells'][col] = ''
    with pytest.raises(SystemExit) as e:
        w.preflight([rec])
    assert col in str(e.value)


def test_bid_move_with_empty_bid_is_refused():
    """A bid row with no bid is a silent no-op that still consumes a change-log row, so the log
    would claim a change that never happened."""
    cells = {h: '' for h in w.SP_HEADERS}
    cells.update({'Product': 'Sponsored Products', 'Entity': 'Keyword', 'Operation': 'Update',
                  'Bid': ''})
    rec = {'source': 'reprice', 'sheet': w.SP_SHEET, 'cells': cells,
           'audit': {'disposition': 'BID_UP', 'campaign': 'C', 'target': 'kw', 'campaign_id': '1'}}
    with pytest.raises(SystemExit) as e:
        w.preflight([rec])
    assert 'empty Bid' in str(e.value)


def test_tier_is_the_tier_that_decided_not_the_one_that_executes():
    """A probation pause is executed by Pacing but decided by the ladder's DEAD verdict, so it is a
    CATALOG row. Filing it under Pacing puts a worth verdict in the layer §1.1 forbids to make one."""
    pause = {'source': 'seats', 'sheet': w.SP_SHEET, 'cells': {},
             'audit': {'disposition': 'PAUSE', 'kind': 'LEAK', 'ladder_state': 'DEAD'}}
    assert w.tier_of(pause) == w.CATALOG
    bid = {'source': 'reprice', 'sheet': w.SP_SHEET, 'cells': {},
           'audit': {'disposition': 'BID_UP'}}
    assert w.tier_of(bid) == w.PACING
    budget = {'source': 'plan-budgets', 'sheet': w.SP_SHEET, 'cells': {},
              'audit': {'disposition': 'BUDGET_DOWN'}}
    assert w.tier_of(budget) == w.BRAIN


def test_precedence_drops_the_lower_tier_and_records_the_conflict():
    """Catalog > Brain > Pacing, loser dropped not blended, never silent."""
    subj = {'campaign_id': '9', 'keyword_id': '77', 'target': 'kw', 'campaign': 'C'}
    catalog = {'source': 'seats', 'sheet': w.SP_SHEET, 'cells': {},
               'audit': dict(subj, disposition='PAUSE', kind='LEAK', ladder_state='DEAD')}
    pacing = {'source': 'reprice', 'sheet': w.SP_SHEET, 'cells': {},
              'audit': dict(subj, disposition='BID_UP')}
    kept, conflicts = w.resolve([pacing, catalog])
    assert len(kept) == 1 and kept[0] is catalog
    assert len(conflicts) == 1 and conflicts[0]['loser'] is pacing
    assert conflicts[0]['same_tier'] is False


def test_same_tier_collision_keeps_both_and_flags_it():
    """The doctrine does not rank two rows from one tier, so picking one would be inventing a
    decision. Both are kept and flagged for a human."""
    subj = {'campaign_id': '9', 'keyword_id': '77', 'target': 'kw', 'campaign': 'C'}
    a = {'source': 'reprice', 'sheet': w.SP_SHEET, 'cells': {},
         'audit': dict(subj, disposition='BID_UP')}
    b = {'source': 'reprice', 'sheet': w.SP_SHEET, 'cells': {},
         'audit': dict(subj, disposition='BID_DOWN')}
    kept, conflicts = w.resolve([a, b])
    assert len(kept) == 2
    assert conflicts and conflicts[0]['same_tier'] is True


def test_campaign_and_keyword_rows_are_not_a_conflict():
    """A budget on a campaign and a bid on a keyword inside it are the two layers doing their own
    jobs — that is the doctrine working, not a contradiction."""
    budget = {'source': 'plan-budgets', 'sheet': w.SP_SHEET, 'cells': {},
              'audit': {'campaign_id': '9', 'keyword_id': '', 'disposition': 'BUDGET_UP'}}
    bid = {'source': 'reprice', 'sheet': w.SP_SHEET, 'cells': {},
           'audit': {'campaign_id': '9', 'keyword_id': '77', 'disposition': 'BID_UP'}}
    kept, conflicts = w.resolve([budget, bid])
    assert len(kept) == 2 and not conflicts


# --- the change-log vocabulary -------------------------------------------------------------------
# Added after the first cut invented INCREASE_BUDGET / REDUCE_BUDGET while the log has carried
# BUDGET_CHANGE since 2026-07-18, and NEGATE while the log uses NEGATE_TERM. A synonym in a log is
# worse than a typo: every existing query for budget history silently misses the rows, and the miss
# reads as "no budget changed". These are the strings the log actually holds.

LIVE_ACTIONS = {'INCREASE_BID', 'REDUCE_BID', 'BUDGET_CHANGE', 'NEGATE_TERM', 'KEYWORD_PAUSE',
                'KEYWORD_UNPAUSE_PARK', 'CAMPAIGN_PAUSE', 'ADD_COMPETITOR_TARGET'}


def test_every_mapped_action_is_one_the_log_already_uses():
    for disp, action in w.ACTION_OF.items():
        assert action in LIVE_ACTIONS, f"{disp} -> {action} is not a string the change log uses"


def test_budget_direction_lives_in_the_amounts_not_the_verb():
    """BUDGET_CHANGE both ways — old_bid/new_bid carry the direction, as the log's own rows do."""
    assert w.ACTION_OF['BUDGET_UP'] == w.ACTION_OF['BUDGET_DOWN'] == 'BUDGET_CHANGE'


def test_a_negative_logs_as_NEGATE_TERM():
    rec = {'source': 'seats', 'sheet': w.SP_SHEET, 'cells': {},
           'audit': {'kind': 'NEGATIVE_KEYWORD', 'disposition': 'NEGATE'}}
    assert w.log_action(rec) == 'NEGATE_TERM'


# --- STEP 2: the budget-carry check (violation 28) -----------------------------------------------
# A campaign budget row and a bid row inside that campaign are NOT a precedence conflict - the two
# tiers are doing their own jobs. But a budget being CUT while bids inside it are RAISED is a
# request the campaign may not be able to carry, and the book showed the two rows 25 lines apart
# with nothing relating them. Measured 2026-08-25: BOX-SP/EXACT cut 32% while a bid inside it rose.

def _budget_row(cid, old, new, campaign='C'):
    return {'source': 'plan-budgets', 'sheet': w.SP_SHEET, 'cells': {},
            'audit': {'campaign_id': cid, 'keyword_id': '', 'campaign': campaign,
                      'disposition': 'BUDGET_DOWN' if new < old else 'BUDGET_UP',
                      '_old_budget': old, '_new_budget': new}}


def _bid_row(cid, kid, old, new, campaign='C', target='kw'):
    return {'source': 'reprice', 'sheet': w.SP_SHEET, 'cells': {},
            'audit': {'campaign_id': cid, 'keyword_id': kid, 'campaign': campaign,
                      'target': target, 'old_bid': str(old), 'new_bid': str(new),
                      'disposition': 'BID_UP' if new > old else 'BID_DOWN'}}


def test_bid_raise_inside_a_budget_cut_is_surfaced():
    notes = w.budget_carry_check([_budget_row('9', 20.48, 13.94),
                                  _bid_row('9', '77', 0.72, 0.83)])
    assert len(notes) == 1
    assert notes[0]['campaign_id'] == '9'
    assert notes[0]['raises'] == 1
    assert 'cut' in notes[0]['note'].lower()


def test_a_budget_cut_with_no_raises_inside_is_not_flagged():
    notes = w.budget_carry_check([_budget_row('9', 20.48, 13.94),
                                  _bid_row('9', '77', 0.83, 0.72)])
    assert notes == []


def test_a_budget_raise_with_raises_inside_is_not_flagged():
    """Agreement, not tension — the Brain is funding what Pacing is pricing up."""
    notes = w.budget_carry_check([_budget_row('9', 13.94, 20.48),
                                  _bid_row('9', '77', 0.72, 0.83)])
    assert notes == []


def test_a_bid_raise_with_no_budget_row_is_not_flagged():
    assert w.budget_carry_check([_bid_row('9', '77', 0.72, 0.83)]) == []


def test_the_note_counts_every_raise_in_the_campaign():
    notes = w.budget_carry_check([_budget_row('9', 20.48, 13.94),
                                  _bid_row('9', '77', 0.72, 0.83),
                                  _bid_row('9', '78', 0.50, 0.60),
                                  _bid_row('9', '79', 0.90, 0.80)])
    assert len(notes) == 1 and notes[0]['raises'] == 2


def test_carry_check_never_drops_a_row():
    """It WARNS. Refusing would make a legitimate rebalance undeliverable."""
    recs = [_budget_row('9', 20.48, 13.94), _bid_row('9', '77', 0.72, 0.83)]
    kept, conflicts = w.resolve(recs)
    assert len(kept) == 2
