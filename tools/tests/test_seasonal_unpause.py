"""THE SEASONAL UNPAUSE BOOK — the pure rules that decide what one row does.

WHY THIS FILE EXISTS (2026-08-24). The leak book paused keywords on a trailing settled window.
Six of them had sold through last year's holiday season and were silent only because it is
August — `NOT_WORTH_NOW`, not `NOT_WORTH` (architecture/THREE_LAYERS.md §4). A pause removes a
keyword from FACT_KEYWORD_STATE altogether, so no layer can see it, judge it or revive it: a door
that only closes. This book re-opens exactly that door for a named list of keywords, and it parks
them — alive and visible, not funded.

Every rule the tests below pin exists because getting it wrong costs money in one direction or
the other:
  - the park price is READ from the warehouse (the engine's published `bid_park`, else the
    channel+creative floor `V_BID_FLOOR`/`FN_BID_FLOOR`), never a literal in this repo. The floor
    is a property of the CHANNEL and the CREATIVE — $0.10 under a product-collection creative and
    $0.25 under a video one — and a generator carrying its own copy is exactly the defect
    FN_BID_FLOOR was created to end.
  - a row whose park price cannot be read is REFUSED, loudly, rather than guessed at.
  - the row sets the state to enabled AND the bid in one line; re-enabling without repricing
    would put `gift for 18 year old girl` back on the $1.00 bid it was paused from, which is
    funding a keyword we have just said is worth nothing THIS season.
  - SB routing and a total row ordering, so the sheet is byte-reproducible and never carries an
    SP row into an SB campaign (which fails the whole upload).
"""
import os
import re
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

import build_seasonal_unpause_bulksheet as book  # noqa: E402
from build_stop_nonconverting_bulksheet import SP_HEADERS, SB_HEADERS  # noqa: E402


def row(**over):
    """One warehouse row as the book's SQL returns it — SB video, paused, park price readable."""
    r = {
        'keyword_id': '428298100225290', 'campaign_id': '292848303399755',
        'ad_group_id': '291025799038676', 'target_text': 'gift for 18 year old girl',
        'match_type': 'broad', 'campaign_name': 'FRESH SP/BROAD (Hunter ,Pink, Gift)',
        'campaign_type': 'SB', 'channel': 'SB', 'creative_type': 'BRAND_VIDEO',
        'is_pt': False, 'is_brand_defense': False,
        'live_state': 'PAUSED', 'dim_state': 'paused',
        'bid_park': None, 'bid_floor': '0.25', 'bid_floor_source': 'SB_VIDEO_0.25',
        'dim_bid': '1.0', 'paused_from_bid': '1.0', 'paused_by_batch': 'seat_moves_20260823_1045',
        'echo_portfolio_id': '19847592608433', 'latest_portfolio_id': '19847592608433',
        'holdout_eligible_from': None,
        'season_clicks': 27, 'season_orders': 2, 'season_sales': '146.4', 'season_cost': '15.5',
    }
    r.update(over)
    return r


# ── the park price: read, never written here ──────────────────────────────────────────────────

def test_the_park_price_is_the_channel_floor_the_warehouse_published():
    """No row in T_OOB_SEAT_ECONOMICS (a paused keyword has none — that is the whole problem),
    so the price is the channel+creative floor V_BID_FLOOR resolved for this ad group."""
    price, source = book.park_price(row())
    assert price == 0.25 and source == 'CHANNEL_FLOOR'
    price, source = book.park_price(row(bid_floor='0.10', bid_floor_source='SB_COLLECTION_0.10'))
    assert price == 0.10 and source == 'CHANNEL_FLOOR', \
        'the floor is a property of the creative: a collection ad group parks at $0.10, not $0.25'


def test_the_engine_park_price_wins_when_the_engine_publishes_one():
    price, source = book.park_price(row(bid_park='0.25', bid_floor='0.10'))
    assert price == 0.25 and source == 'ENGINE_BID_PARK'


def test_an_engine_park_price_below_the_channel_floor_is_raised_to_the_floor():
    """A bid under the platform minimum is REJECTED by Amazon, so a park below the floor parks
    nothing at all."""
    price, source = book.park_price(row(bid_park='0.05', bid_floor='0.20'))
    assert price == 0.20 and source == 'ENGINE_BID_PARK_RAISED_TO_FLOOR'


def test_an_unreadable_park_price_is_refused_loudly_and_never_guessed():
    with pytest.raises(book.ParkPriceUnreadable) as e:
        book.park_price(row(bid_park=None, bid_floor=None))
    assert '428298100225290' in str(e.value), 'a refusal must name the row it refused'


def test_the_refusal_reaches_the_disposition_so_no_sheet_row_is_written():
    disp, reason = book.classify(row(bid_park=None, bid_floor=None), book.date(2026, 8, 24))
    assert disp == 'PARK_PRICE_UNREADABLE'
    assert disp not in book.EXECUTABLE
    assert 'park price' in reason.lower()


def test_no_price_literal_is_written_anywhere_in_this_generator():
    """The defect FN_BID_FLOOR exists to end: an engine holding its own copy of a floor. If a
    price appears in this file it is no longer read from the warehouse, whatever the comment
    above it says."""
    src = open(book.__file__, encoding='utf-8').read()
    code = '\n'.join(ln for ln in src.split('\n') if not ln.lstrip().startswith('#'))
    assert not re.search(r'(?<![\w.])0\.(?:05|10|20|25|30)(?![\w])', code), \
        'a bid price literal appears in the generator — read it from V_BID_FLOOR instead'


# ── what one row actually does ────────────────────────────────────────────────────────────────

def test_the_sb_row_sets_the_state_to_enabled_and_the_bid_to_the_park_price():
    r = book.sb_unpause_row(row(), 0.25)
    assert set(r) == set(SB_HEADERS)
    assert r['Product'] == 'Sponsored Brands'
    assert r['Entity'] == 'Keyword' and r['Operation'] == 'Update'
    assert r['State'] == 'enabled'
    assert r['Bid'] == '0.25'
    assert r['Keyword Id'] == '428298100225290'
    assert r['Campaign Id'] == '292848303399755' and r['Ad Group Id'] == '291025799038676'
    assert r['Portfolio Id'] == '19847592608433', 'the portfolio echo is read live and carried'


def test_the_sp_row_sets_the_state_to_enabled_and_the_bid_to_the_park_price():
    r = book.sp_unpause_row(row(campaign_type='SP', channel='SP', creative_type=None), 0.20)
    assert set(r) == set(SP_HEADERS)
    assert r['Product'] == 'Sponsored Products' and r['Entity'] == 'Keyword'
    assert r['State'] == 'ENABLED' and r['Bid'] == '0.20'
    assert r['Keyword ID'] == '428298100225290'


def test_a_product_target_row_carries_the_target_id_not_the_keyword_id():
    r = book.sp_unpause_row(row(campaign_type='SP', channel='SP', is_pt=True), 0.20)
    assert r['Entity'] == 'Product Targeting'
    assert r['Product Targeting ID'] == '428298100225290' and r['Keyword ID'] == ''


def test_one_row_per_keyword_carries_both_changes_never_two_rows():
    """One line sets the switch and the price together. Two lines — one enabling, one repricing —
    leave a window in which the keyword is live at its old bid."""
    r = book.sb_unpause_row(row(), 0.25)
    assert r['State'] and r['Bid'], 'the state and the bid must travel on the same row'


# ── the bid a park may never be ───────────────────────────────────────────────────────────────

def test_a_park_may_never_hand_a_keyword_back_the_bid_it_was_paused_from():
    """`gift for 18 year old girl` was paused from $1.00. It is NOT_WORTH_NOW, not WORTH: it comes
    back visible, not funded."""
    with pytest.raises(AssertionError) as e:
        book.assert_park_is_not_a_restore(row(), 1.00, 1.00)
    assert '1.0' in str(e.value) or '1.00' in str(e.value)
    book.assert_park_is_not_a_restore(row(), 0.25, 0.25)   # at the floor: fine


def test_a_keyword_paused_from_under_the_floor_may_rise_to_the_floor():
    """The only legal raise: the platform minimum. Anything else is funding."""
    book.assert_park_is_not_a_restore(row(bid_floor='0.25'), 0.15, 0.25)


# ── routing, population, ordering ─────────────────────────────────────────────────────────────

def test_sb_routing_follows_the_campaign_dimension():
    assert book.is_sb(row()) is True
    assert book.is_sb(row(campaign_type='SP', channel='SP')) is False
    assert book.is_sb(row(campaign_type='', channel='SB')) is True, 'the ladder is the fallback'


def test_a_channel_disagreement_is_raised_and_never_resolved_silently():
    with pytest.raises(AssertionError):
        book.is_sb(row(campaign_type='SP', channel='SB'))


def test_the_population_is_explicit_and_never_re_derived():
    ids = book.parse_keyword_ids([
        '# the six seasonal keywords from seat_moves_20260823_1045',
        '428298100225290  gift for 18 year old girl', '', '500617324681575',
        '428298100225290',
    ])
    assert ids == ['428298100225290', '500617324681575'], 'in order, deduped'
    with pytest.raises(SystemExit):
        book.parse_keyword_ids(['not-a-keyword-id'])
    with pytest.raises(SystemExit):
        book.parse_keyword_ids([])


def test_the_sql_selects_only_the_named_ids():
    sql = book.SQL.format(p='onyga-482313', ids="'1','2'", season_from='2025-11-01',
                          season_to='2025-12-31')
    assert "'1','2'" in sql
    assert 'IN (' in sql


def test_the_sql_orders_totally():
    """House rule 9: two builds of one snapshot must diff byte for byte, so the ordering has to
    reach a unique key — last season's orders tie freely."""
    order = book.SQL.rstrip().rsplit('ORDER BY', 1)[1]
    assert 'campaign_id' in order and 'keyword_id' in order


# ── the doctrine the whole book exists to obey ────────────────────────────────────────────────

def test_a_holdout_campaign_gets_no_row_of_any_kind():
    disp, reason = book.classify(row(holdout_eligible_from='2026-08-01'), book.date(2026, 8, 24))
    assert disp == 'HOLDOUT_EXCLUDED' and disp not in book.EXECUTABLE


def test_a_keyword_already_enabled_gets_no_row():
    disp, _ = book.classify(row(live_state='ENABLED', dim_state='enabled'), book.date(2026, 8, 24))
    assert disp == 'ALREADY_ENABLED' and disp not in book.EXECUTABLE


def test_a_keyword_whose_live_state_cannot_be_read_gets_no_row():
    disp, _ = book.classify(row(live_state='', dim_state=None), book.date(2026, 8, 24))
    assert disp == 'LIVE_STATE_UNKNOWN' and disp not in book.EXECUTABLE


def test_a_paused_seasonal_keyword_is_unpaused_and_parked():
    disp, reason = book.classify(row(), book.date(2026, 8, 24))
    assert disp == book.UNPAUSE_PARK and disp in book.EXECUTABLE
    assert 'park' in reason.lower()


def test_a_second_pending_book_is_refused_unless_it_names_the_one_it_replaces():
    """Two pending books hand Ori two sheets for one keyword, and uploading both would set the
    price twice from two different reads."""
    pending = [{'batch_id': 'seasonal_unpause_20260824_1325', 'n': 6,
                'upload_status': 'PENDING_UPLOAD'}]
    with pytest.raises(SystemExit):
        book.refuse_second_pending_book(pending, replaces=[])
    book.refuse_second_pending_book(pending, replaces=['seasonal_unpause_20260824_1325'])
    # and a book that is NOT pending may not be named: nothing is labelled blind
    with pytest.raises(SystemExit):
        book.refuse_second_pending_book([], replaces=['seasonal_unpause_20260824_1325'])
    assert book.build_parser().parse_args(
        ['--replaces', 'seasonal_unpause_20260824_1325']).replaces == \
        ['seasonal_unpause_20260824_1325']


def test_this_book_never_emits_a_pause_or_an_archive():
    """It is the reverse of a one-way door: nothing it writes may close one. Every row either
    builder can produce, on any input, opens the switch."""
    for r in (row(), row(is_pt=True), row(campaign_type='SP', channel='SP')):
        built = book.sb_unpause_row(r, 0.25) if book.is_sb(r) else book.sp_unpause_row(r, 0.20)
        assert built['State'].lower() == 'enabled', built['State']
        assert built['Operation'] == 'Update', 'a create or an archive is not this book'


# ── §2.8 market volume: evidence in the README, never a filter ─────────────────────────────────
# Added 2026-08-24. "Volume is a market fact, not only our history" — a query the market buys every
# week, on which we hold a fraction of a percent of impressions, is not evidence the subject is
# dead. SQP is on probation (§2.3): it may inform the reader and it may NOT move a verdict, so
# every test below pins one of the two halves — it must be reported, and it must not decide.

def sqp(**over):
    """The SQP columns as the book's SQL returns them for one keyword."""
    r = {
        'sqp_weeks_all': 31, 'sqp_season_weeks': 4,
        'sqp_season_mkt_impr_wk': 170000.0, 'sqp_season_mkt_clicks_wk': 2100.0,
        'sqp_season_mkt_purch_wk': 119.0, 'sqp_season_volume_wk': 6675.0,
        'sqp_season_our_impr_wk': 38.0, 'sqp_season_share_pct': 0.02,
        'sqp_last_week': '2026-02-01', 'sqp_last_mkt_impr': 169886, 'sqp_last_mkt_clicks': 2000,
        'sqp_last_mkt_purch': 119, 'sqp_last_our_impr': 38, 'sqp_last_share_pct': 0.02,
        'sqp_last_volume': 6675,
    }
    r.update(over)
    return r


def test_the_market_line_reports_what_the_market_buys_and_the_share_we_hold():
    line = book.market_line(row(**sqp()))
    assert '119' in line, 'the market purchases per week must be in the line'
    assert '0.02' in line, "our share of impressions must be in the line"
    assert '%' in line


def test_a_query_with_no_sqp_row_says_so_and_never_invents_a_zero():
    """§2.3 ground 4: SQP coverage is partial in this account. 'No row' is a gap in the source,
    not a market of size zero, and a README that prints 0 would be asserting the opposite."""
    line = book.market_line(row(**sqp(sqp_weeks_all=0, sqp_season_weeks=0, sqp_last_week=None,
                                     sqp_season_mkt_purch_wk=None, sqp_season_share_pct=None,
                                     sqp_last_mkt_purch=None, sqp_last_share_pct=None)))
    assert 'no ' in line.lower() and 'sqp' in line.lower()
    assert 'buys 0' not in line and '0 purchases' not in line
    assert 'coverage' in line.lower() or 'not a zero' in line.lower()


def test_a_query_seen_by_sqp_but_never_in_the_season_falls_back_to_the_week_it_was_seen():
    line = book.market_line(row(**sqp(sqp_season_weeks=0, sqp_season_mkt_purch_wk=None,
                                      sqp_season_share_pct=None)))
    assert '2026-02-01' in line, 'the last observed week must be named when the season has none'
    assert '119' in line


def test_the_median_click_price_columns_are_never_read_as_a_cost():
    """total_median_click_price / asin_median_click_price are the median PRICE OF THE ITEM
    CLICKED, not a CPC. Presenting one as a cost would misprice a park by an order of magnitude,
    so this generator does not touch them at all."""
    src = open(book.__file__).read()
    for col in ('median_click_price', 'total_median_click_price', 'asin_median_click_price'):
        assert col not in src, f'{col} must not appear in the generator: it is not a cost'


def test_market_volume_never_changes_a_disposition():
    """SQP is on probation: it is evidence, never a filter. A keyword the market buys 10,000
    times a week and one SQP has never heard of must classify identically."""
    huge = book.classify(row(**sqp(sqp_season_mkt_purch_wk=10000.0)), book.date(2026, 8, 24))
    none = book.classify(row(**sqp(sqp_weeks_all=0, sqp_season_weeks=0, sqp_last_week=None,
                                   sqp_season_mkt_purch_wk=None, sqp_last_mkt_purch=None)),
                         book.date(2026, 8, 24))
    assert huge == none, 'a demand figure moved a verdict — §2.3 forbids exactly this'


def test_the_sql_reads_the_market_for_the_named_ids_only():
    sql = book.SQL.format(p='onyga-482313', ids="'1','2'", season_from='2025-11-01',
                          season_to='2025-12-31')
    assert 'FACT_SEARCH_QUERY' in sql
    body = sql.split('FACT_SEARCH_QUERY', 1)[1]
    assert 'dimk' in body.split('GROUP BY', 1)[0], \
        'the market read must be restricted to the named keywords, never the whole table'


# ── the README counts its own rows ────────────────────────────────────────────────────────────

def test_the_readme_headline_counts_the_rows_it_carries(tmp_path):
    """The first build of this book carried six keywords and the headline said 'six' in words.
    A book that carries twelve must not greet the reader with 'six'."""
    def build(n):
        rows = [{'disp': book.UNPAUSE_PARK, 'reason': 'r', 'sheet': 'Sponsored Products Campaigns',
                 'sheet_line': i + 2, 'is_sb': False, 'target_text': f'kw{i}',
                 'campaign_name': 'C', 'season_orders': 5, 'season_sales': 100.0,
                 'season_clicks': 10, 'recent_orders': 0, 'recent_clicks': 0, 'recent_cost': 0.0,
                 'old_bid': 1.0, 'price': 0.2, 'price_source': 'CHANNEL_FLOOR',
                 'price_provenance': 'V_BID_FLOOR', 'paused_by_batch': 'b', 'paused_on': None,
                 'keyword_id': f'{i}', 'market': 'no SQP row'} for i in range(n)]
        p = tmp_path / f'r{n}.md'
        book.write_readme(str(p), 'x.xlsx', 'batch', book.date(2026, 8, 24), '2026-08-23', True,
                          rows, {'from': '2025-11-01', 'to': '2025-12-31'})
        return p.read_text()

    twelve = build(12)
    assert 'twelve' in twelve.split('\n')[0].lower(), twelve.split('\n')[0]
    assert 'six' not in twelve.lower().replace('superseded', ''), \
        'a count from the first build leaked into a book of a different size'
    assert 'three' in build(3).split('\n')[0].lower()


def test_the_readme_carries_the_market_line_for_every_row(tmp_path):
    rows = [{'disp': book.UNPAUSE_PARK, 'reason': 'r', 'sheet': 'Sponsored Products Campaigns',
             'sheet_line': 2, 'is_sb': False, 'target_text': 'bath accessories',
             'campaign_name': 'C', 'season_orders': 14, 'season_sales': 910.8,
             'season_clicks': 60, 'recent_orders': 0, 'recent_clicks': 0, 'recent_cost': 0.0,
             'old_bid': 1.0, 'price': 0.25, 'price_source': 'CHANNEL_FLOOR',
             'price_provenance': 'V_BID_FLOOR', 'paused_by_batch': 'b', 'paused_on': None,
             'keyword_id': '1', 'market': 'the market buys this 119 times a week; we hold 0.02% of its impressions'}]
    p = tmp_path / 'r.md'
    book.write_readme(str(p), 'x.xlsx', 'batch', book.date(2026, 8, 24), '2026-08-23', True, rows,
                      {'from': '2025-11-01', 'to': '2025-12-31'})
    text = p.read_text()
    assert '119 times a week' in text
    assert '0.02%' in text


# ── the README may not overclaim, and must be able to carry the population argument ───────────

def readme_row(**over):
    r = {'disp': book.UNPAUSE_PARK, 'reason': 'r', 'sheet': 'Sponsored Products Campaigns',
         'sheet_line': 2, 'is_sb': False, 'target_text': 'kw', 'campaign_name': 'C',
         'season_orders': 5, 'season_sales': 100.0, 'season_clicks': 10, 'recent_orders': 0,
         'recent_clicks': 0, 'recent_cost': 0.0, 'old_bid': 0.8, 'price': 0.2,
         'price_source': 'CHANNEL_FLOOR', 'price_provenance': 'V_BID_FLOOR',
         'paused_by_batch': None, 'paused_on': None, 'bid_is_recorded': False,
         'keyword_id': '534864099331513', 'market': 'no SQP row'}
    r.update(over)
    return r


def make_readme(tmp_path, rows, **kw):
    p = tmp_path / 'r.md'
    book.write_readme(str(p), 'x.xlsx', 'batch', book.date(2026, 8, 24), '2026-08-23', True, rows,
                      {'from': '2025-11-01', 'to': '2025-12-31'}, **kw)
    return p.read_text()


def test_a_bid_no_pause_row_recorded_is_never_called_the_bid_it_was_paused_from(tmp_path):
    """Only ONE of the twelve keywords in the 2026-08-24 book was switched off by a book of ours;
    the other eleven were paused by hand or by Amazon, so no change-log row records the bid they
    were paused FROM. The column then falls back to DIM_KEYWORD's stored bid, which is a different
    claim, and the README must not present the two as the same thing."""
    text = make_readme(tmp_path, [readme_row(bid_is_recorded=False)])
    assert 'stored bid' in text.lower()
    text2 = make_readme(tmp_path, [readme_row(bid_is_recorded=True, paused_on='2026-08-23',
                                              paused_by_batch='seat_moves_20260823_1045')])
    assert 'seat_moves_20260823_1045' in text2


def test_the_readme_counts_agree_in_number(tmp_path):
    """'1 come back at the same price' is the kind of sentence that makes a reader stop trusting
    the arithmetic around it."""
    text = make_readme(tmp_path, [readme_row(old_bid=0.8, price=0.2),
                                  readme_row(old_bid=0.2, price=0.2)])
    assert '1 come back' not in text and '1 comes back' in text


def test_the_population_note_is_carried_verbatim(tmp_path):
    """The rule that chose the twelve lives OUTSIDE this generator on purpose — the book never
    derives a population (see the module docstring). So the argument for the population travels
    with it as text the book prints and never interprets."""
    note = "## How these twelve were chosen\n\n42 others were dropped: covered elsewhere.\n"
    text = make_readme(tmp_path, [readme_row()], population_note=note)
    assert '42 others were dropped: covered elsewhere.' in text
    assert text.index('How these twelve were chosen') < text.index('## Row by row')


def test_a_population_note_cannot_add_or_remove_a_sheet_row(tmp_path):
    """It is prose. If it could change the sheet it would be a population, and this book has
    exactly one source for that: the explicit id list."""
    with_note = make_readme(tmp_path, [readme_row()], population_note='## anything\n')
    without = make_readme(tmp_path, [readme_row()])
    assert with_note.count('| 2 |') == without.count('| 2 |')
    assert book.build_parser().parse_args(['--keyword', '1', '--population-note', 'f']) \
        .population_note == 'f'


def test_the_readme_never_blames_a_book_of_ours_for_a_pause_it_did_not_take(tmp_path):
    """§6.3, turned on the README itself. Eleven of the twelve keywords in the 2026-08-24 book have
    no applied pause row in the change log — nothing of ours switched them off. Prose that says
    'yesterday's leak book paused these' would be asserting an authorship the record does not
    support, in the same document that asks the reader to distrust asserted losses."""
    text = make_readme(tmp_path, [readme_row(bid_is_recorded=False)])
    assert "leak book read the second as the first" not in text
    both = make_readme(tmp_path, [readme_row(bid_is_recorded=True, paused_by_batch='b1'),
                                  readme_row(bid_is_recorded=False)])
    assert '1 of the 2' in both or '1 of 2' in both


def test_the_readme_never_calls_an_unattributed_bid_a_leak(tmp_path):
    """The keyword that comes back cheapest is worth pointing at. Calling the bid it held 'the bid
    that made it a leak' is a verdict on money nobody measured here."""
    text = make_readme(tmp_path, [readme_row(old_bid=0.80, price=0.20, target_text='x',
                                             bid_is_recorded=False)])
    # 'a later leak book' names a real tool and is fine; 'the bid that made it a leak' is a
    # verdict on money this book never measured.
    assert 'made it a leak' not in text.lower()
    assert 'a leak in the first place' not in text.lower()


# ── repair pass 2026-08-24: five README/generator overclaims a verifier caught ────────────────

def test_the_intro_never_says_no_row_returns_to_its_pause_bid_when_one_does(tmp_path):
    """VERIFIER (repair pass 1). The intro said in bold 'Not one of them returns to the bid it was
    paused from', and twenty lines later the table paragraph said '1 comes back at the same price'
    — true for `gift for 20 year old female`, paused at $0.25 by seat_moves_20260823_1045 and
    returned at $0.25. The defensible claim is the one about direction: no row comes back HIGHER.
    A reader who hits both sentences stops trusting the arithmetic between them."""
    text = make_readme(tmp_path, [readme_row(old_bid=0.25, price=0.25, bid_is_recorded=True,
                                             paused_by_batch='seat_moves_20260823_1045'),
                                  readme_row(old_bid=0.80, price=0.20)])
    assert 'not one of them returns to the bid it was paused from' not in text.lower()
    assert 'higher' in text.lower()
    # and when every row really is cheaper, the stronger sentence is allowed back
    all_cut = make_readme(tmp_path, [readme_row(old_bid=0.80, price=0.20)])
    assert 'same price' not in all_cut.lower()


def test_a_row_whose_recent_window_took_clicks_is_never_called_silent():
    """VERIFIER (repair pass 1), and THREE_LAYERS.md §6.3. classify() asserted every row was
    'paused on a trailing window that was silent because of the season'. For
    `gift for 20 year old female` that window was 59 clicks and $48.41 with no orders — loud and
    unprofitable, not silent. FACT_KEYWORD_SEASON_VERDICT records it OFF/LOSS, 52 clicks 0 orders.
    The unpause is still right on §4 and §5; the stated REASON must match the record."""
    disp, reason = book.classify(row(recent_clicks=59, recent_orders=0, recent_cost='48.41'),
                                 book.date(2026, 8, 24))
    assert disp == book.UNPAUSE_PARK
    assert 'window was silent' not in reason.lower(), reason
    assert 'was not silent' in reason.lower(), reason
    assert '59' in reason and '48.41' in reason, reason
    quiet_disp, quiet = book.classify(row(recent_clicks=0, recent_orders=0, recent_cost='0'),
                                      book.date(2026, 8, 24))
    assert quiet_disp == book.UNPAUSE_PARK
    assert 'window was silent' in quiet.lower(), quiet


def test_the_readme_opening_never_asserts_silence_over_a_row_that_took_clicks(tmp_path):
    """The same overclaim at the top of the document, asserted over the whole population."""
    text = make_readme(tmp_path, [readme_row(recent_clicks=59, recent_cost=48.41),
                                  readme_row(recent_clicks=0)])
    assert 'their last few weeks were silent' not in text.lower()
    all_quiet = make_readme(tmp_path, [readme_row(recent_clicks=0), readme_row(recent_clicks=0)])
    assert 'silent' in all_quiet.lower()


def test_a_deleted_line_has_a_remedy_the_reader_can_actually_run(tmp_path):
    """VERIFIER (repair pass 1). Every row said 'then label its change-log row FAILED_UPLOAD' and
    no command anywhere could do it: --supersede labels the WHOLE batch, and --mark-uploaded flips
    every PENDING row to applied, after which no documented path can ever label the deleted one.
    An instruction the reader cannot execute is worse than none: the change log ends up recording
    a keyword as re-enabled that was deliberately removed from the sheet."""
    text = make_readme(tmp_path, [readme_row(target_text='kw-a')])
    assert 'FAILED_UPLOAD' in text
    assert '--mark-row-failed' in text, 'the README names a state with no way to reach it'
    # and the ordering hazard is spelled out where the reader meets --mark-uploaded
    upload = text[text.index('## How to upload it'):]
    assert 'before' in upload.lower() and '--mark-row-failed' in upload


def test_mark_row_failed_labels_exactly_one_pending_row():
    """PENDING_UPLOAD only, one keyword, never a delete — the same discipline --supersede keeps."""
    sql = book.mark_row_failed_sql('seasonal_unpause_20260824_1643', '534864099331513', 'note')
    assert sql.strip().upper().startswith('UPDATE')
    assert 'FAILED_UPLOAD' in sql
    assert "upload_status = 'PENDING_UPLOAD'" in sql
    assert '534864099331513' in sql and 'seasonal_unpause_20260824_1643' in sql
    assert 'DELETE' not in sql.upper()
    assert book.build_parser().parse_args(
        ['--mark-row-failed', 'b1', '99']).mark_row_failed == ['b1', '99']


def test_the_summer_window_is_not_labelled_silence_over_a_row_that_took_clicks(tmp_path):
    """The table caption called the trailing window 'the silence the pause was read from' — the
    same §6.3 overclaim as the opening paragraph, in the caption of the table that disproves it."""
    text = make_readme(tmp_path, [readme_row(recent_clicks=59, recent_cost=48.41),
                                  readme_row(recent_clicks=0)])
    assert 'the silence the pause was read from' not in text.lower()
    assert 'the trailing window the pause was read from' in text.lower()


def test_the_pause_attribution_sentence_agrees_in_number(tmp_path):
    """'1 of the 11 were switched off' reads like the arithmetic around it was not checked."""
    text = make_readme(tmp_path, [readme_row(bid_is_recorded=True, paused_by_batch='b1'),
                                  readme_row(bid_is_recorded=False),
                                  readme_row(bid_is_recorded=False)])
    assert '1 of the 3 was switched off' in text, text[:1500]
    two = make_readme(tmp_path, [readme_row(bid_is_recorded=True, paused_by_batch='b1'),
                                 readme_row(bid_is_recorded=True, paused_by_batch='b2'),
                                 readme_row(bid_is_recorded=False)])
    assert '2 of the 3 were switched off' in two


# ── repair pass 2026-08-24 (second): identifying a row you are about to delete ────────────────

def test_every_row_heading_carries_the_keyword_id_the_sheet_can_be_matched_on(tmp_path):
    """VERIFIER (repair pass 2). The workbook carries NO human-readable identifier: Keyword Text
    and Campaign Name are blank on every row, and correctly so — a blank cell means 'leave
    unchanged'. The only column that names the subject is **Keyword Id**. The README addressed
    every keyword by SPREADSHEET ROW NUMBER, and step 1 invites the reader to delete lines. Delete
    one and every row number below it shifts, after which 'row 7' points at a different keyword
    and nothing in the document tells the reader how to re-find it. So the id the sheet actually
    carries must be in the heading, next to the row number."""
    rows = [readme_row(sheet_line=2, keyword_id='534864099331513', target_text='kw-a'),
            readme_row(sheet_line=3, keyword_id='389779878299034', target_text='kw-b')]
    text = make_readme(tmp_path, rows)
    for r in rows:
        headings = [ln for ln in text.splitlines()
                    if ln.startswith('### ') and r['target_text'] in ln]
        assert headings, f"no heading for {r['target_text']}"
        assert r['keyword_id'] in headings[0], \
            f"heading {headings[0]!r} names a row number but not the Keyword Id the sheet carries"


def test_the_record_table_carries_the_keyword_id_beside_the_row_number(tmp_path):
    """The same reason, in the table the reader reads first."""
    text = make_readme(tmp_path, [readme_row(keyword_id='534864099331513')])
    table = text[text.index('## The record each one is coming back on'):]
    table = table[:table.index('\n\n', table.index('|---'))]
    assert 'Keyword Id' in table, 'the table names rows only by a number that deletion invalidates'
    assert '534864099331513' in table


def test_the_upload_step_tells_the_reader_to_match_on_keyword_id_not_row_number(tmp_path):
    """Deleting a line is the one thing step 1 asks the reader to do, and it is the thing that
    breaks every row number in the document. Say so where they are about to do it."""
    text = make_readme(tmp_path, [readme_row(), readme_row(sheet_line=3, target_text='b')])
    upload = text[text.index('## How to upload it'):]
    step1 = upload[:upload.index('\n2. ')]
    assert 'Keyword Id' in step1, step1
    low = step1.lower()
    assert 'shift' in low or 'shifts' in low, \
        'the reader is never warned that deleting a row renumbers every row below it'
