"""The leak arm's doctrine, tested on fixtures — no BigQuery, no sheet, no upload.

Every rule the generator applies to a LEAK row or a negate candidate is a pure function here, so
the rule can be read and challenged without a warehouse. The live-data assertions (every register
LEAK row maps to exactly one sheet row or one stated no-action reason; zero holdout rows; zero
negates on terms profitable at ad-group grain; the restore sheet round-trips) run inside the
generator itself against the day's data and are printed by it.
"""
import os
import sys
from datetime import date

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

from build_seat_moves_bulksheet import (  # noqa: E402
    classify_leak, classify_negate, is_asin_term, target_asin, routing_note,
    sp_negative_keyword_row, sp_negative_target_row, sb_negative_keyword_row,
    PAUSE, NEGATE_KEYWORD, NEGATE_TARGET, EXECUTABLE)

TODAY = date(2026, 8, 22)
SNAP = date(2026, 8, 22)


def leak(**kw):
    """A live, pausable DEAD leak — the shape every no-action rule is tested against."""
    base = dict(
        family='Fresh', campaign_id='1', keyword_id='9', ad_group_id='7',
        campaign_name='FRESH-SP/BROAD (Back to School)', target_text='school gifts for teens',
        match_type='BROAD', channel='SP', state='DEAD', is_auto=False, is_pt=False,
        current_bid=1.0, cost_per_day=5.76, sp7=40.33,
        live_state='ENABLED', next_check_date=None, snapshot_date=SNAP,
        holdout_eligible_from=None, block_cut_reason=None, is_brand_defense=False,
        book='HARVEST',
    )
    base.update(kw)
    return base


def cand(**kw):
    """A negate candidate that clears every block-grain gate."""
    base = dict(
        family='LolliME', campaign_id='1', keyword_id='9', ad_group_id='7',
        campaign_name='ME-SBS/BROAD (Discovery, Journal)', channel='SB',
        target_text='gift for 14 year old girls best sellers', search_term='cheap junk gift',
        leak_state='PARKED', leak_is_pt=False,
        ng_clicks_8w=40, ng_orders_8w=0, ng_net_profit_8w=-22.0,
        ng_lt_net_profit=-31.0, ng_lt_clicks=60, ng_lt_orders=0,
        ng_organic_units_8w=0, ng_clicks_recent_5d=3,
        own_kw_clicks_8w=12, min_clicks=15,
        holdout_eligible_from=None, already_negated=False, is_brand_defense=False,
    )
    base.update(kw)
    return base


# ── the pause rule ────────────────────────────────────────────────────────────────────────────

def test_dead_leak_still_serving_is_pausable():
    """DEAD is the ladder's FIRST rung — >=15 settled clicks with 0 orders, fired whatever the
    bid, with no re-check date. Nothing is pending on it, so the pause is executable today."""
    disp, reason = classify_leak(leak(), TODAY)
    assert disp == PAUSE
    assert 'probation' not in reason.lower()


def test_probation_does_not_gate_the_leak_pause():
    """The ladder's ONLY probation-gated kill is LOSER (probation elapsed AT the floor), which
    the reprice book owns. A leak is DEAD or PARKED-past-appointment and never reaches it."""
    disp, _ = classify_leak(leak(state='DEAD', current_bid=1.00), TODAY)
    assert disp == PAUSE, 'a DEAD leak above its floor is pausable — probation governs LOSER only'


def test_parked_past_its_appointment_is_pausable():
    disp, _ = classify_leak(leak(state='PARKED', next_check_date=date(2026, 8, 8)), TODAY)
    assert disp == PAUSE


def test_parked_with_an_appointment_ahead_is_not_paused():
    """R-h: until its re-verdict date the revive cycle is still testing it — that is a seat, and
    the register never publishes it as a LEAK. If one arrives, the generator refuses it."""
    disp, reason = classify_leak(leak(state='PARKED', next_check_date=date(2026, 8, 30)), TODAY)
    assert disp not in EXECUTABLE
    assert '2026-08-30' in reason


def test_already_paused_in_amazon_is_not_pausable():
    """Trailing spend: the keyword is already off, so a pause row changes nothing."""
    disp, reason = classify_leak(leak(live_state='PAUSED'), TODAY)
    assert disp not in EXECUTABLE
    assert 'already' in reason.lower()


def test_holdout_from_eligible_from_gets_no_row():
    disp, _ = classify_leak(leak(holdout_eligible_from=date(2026, 9, 1)), date(2026, 9, 1))
    assert disp not in EXECUTABLE


def test_holdout_before_eligible_from_is_still_actionable():
    disp, _ = classify_leak(leak(holdout_eligible_from=date(2026, 9, 1)), date(2026, 8, 22))
    assert disp == PAUSE


def test_season_block_cut_holds_the_pause():
    disp, reason = classify_leak(leak(block_cut_reason='inside the gift-season boost window'), TODAY)
    assert disp not in EXECUTABLE
    assert 'season' in reason.lower()


def test_brand_defense_is_never_paused_on_profit():
    disp, reason = classify_leak(leak(is_brand_defense=True), TODAY)
    assert disp not in EXECUTABLE
    assert 'defense' in reason.lower()


def test_every_leak_gets_exactly_one_disposition_and_a_reason():
    for row in (leak(), leak(live_state='PAUSED'), leak(is_brand_defense=True),
                leak(holdout_eligible_from=date(2026, 9, 1)),
                leak(block_cut_reason='x'), leak(state='PARKED', next_check_date=date(2026, 9, 9))):
        disp, reason = classify_leak(row, TODAY)
        assert isinstance(disp, str) and disp
        assert isinstance(reason, str) and len(reason) > 20, 'a no-action row states its reason'


# ── the negate rule (V_ADS_COACH block grain) ─────────────────────────────────────────────────

def test_a_losing_term_under_a_parked_leak_is_negated_at_the_ad_group():
    disp, _ = classify_negate(cand(), TODAY)
    assert disp == NEGATE_KEYWORD


def test_never_negate_a_term_the_ad_group_earns_on():
    disp, reason = classify_negate(cand(ng_orders_8w=2, ng_net_profit_8w=14.0), TODAY)
    assert disp not in EXECUTABLE
    assert 'ad group' in reason.lower()


def test_never_negate_a_term_profitable_at_block_grain_even_with_zero_orders():
    disp, _ = classify_negate(cand(ng_net_profit_8w=3.0), TODAY)
    assert disp not in EXECUTABLE


def test_never_negate_a_term_that_paid_its_keep_over_its_lifetime():
    """A block is permanent; a term having a bad eight weeks is a bid or a season problem."""
    disp, reason = classify_negate(cand(ng_lt_net_profit=12.0), TODAY)
    assert disp not in EXECUTABLE
    assert 'lifetime' in reason.lower()


def test_organic_guard():
    disp, reason = classify_negate(cand(ng_organic_units_8w=4), TODAY)
    assert disp not in EXECUTABLE
    assert 'organic' in reason.lower()


def test_too_few_clicks_at_block_grain():
    disp, _ = classify_negate(cand(ng_clicks_8w=9), TODAY)
    assert disp not in EXECUTABLE


def test_not_bleeding_now():
    disp, _ = classify_negate(cand(ng_clicks_recent_5d=0), TODAY)
    assert disp not in EXECUTABLE


def test_holdout_excluded_from_negates_too():
    disp, _ = classify_negate(cand(holdout_eligible_from=date(2026, 9, 1)), date(2026, 9, 1))
    assert disp not in EXECUTABLE


def test_self_target_covered_by_its_own_pause_is_not_negated():
    """A PT leak whose search term IS the ASIN it targets: the whole block-grain spend is drawn by
    the target the sheet already pauses, so the negative adds nothing and contradicts the group's
    own deliberate target."""
    c = cand(target_text='asin="B0D7ZVMXLM"', search_term='b0d7zvmxlm', leak_is_pt=True,
             ng_clicks_8w=86, own_kw_clicks_8w=86)
    disp, reason = classify_negate(c, TODAY)
    assert disp not in EXECUTABLE
    assert 'pause' in reason.lower()


def test_self_target_still_drawn_by_other_keywords_is_negated_as_a_product_target():
    c = cand(target_text='asin="B0D7ZVMXLM"', search_term='b0d7zvmxlm', leak_is_pt=True,
             ng_clicks_8w=86, own_kw_clicks_8w=40)
    disp, _ = classify_negate(c, TODAY)
    assert disp == NEGATE_TARGET


def test_an_asin_term_under_a_keyword_leak_is_a_product_target_negative():
    c = cand(search_term='b0abcdefgh', leak_is_pt=False, own_kw_clicks_8w=0)
    assert is_asin_term('b0abcdefgh')
    disp, _ = classify_negate(c, TODAY)
    assert disp == NEGATE_TARGET


def test_already_registered_negative_is_not_re_emitted():
    disp, reason = classify_negate(cand(already_negated=True), TODAY)
    assert disp not in EXECUTABLE
    assert 'already' in reason.lower()


# ── helpers ───────────────────────────────────────────────────────────────────────────────────

def test_target_asin_reads_the_expression_not_a_substring():
    assert target_asin('asin="B0D7ZVMXLM"') == 'B0D7ZVMXLM'
    assert target_asin('category="12345"') is None
    assert target_asin('school gifts for teens') is None


def test_is_asin_term():
    assert is_asin_term('B0D7ZVMXLM')
    assert is_asin_term('b0d7zvmxlm')
    assert not is_asin_term('gift for 13 year old girl')
    assert not is_asin_term('b0d7zvmxl')      # nine characters is not an ASIN
    assert not is_asin_term('')


# ── the sheet rows ────────────────────────────────────────────────────────────────────────────

def test_sp_negative_keyword_row_is_a_create_at_the_ad_group():
    r = sp_negative_keyword_row(cand(channel='SP'), portfolio_id='55')
    assert r['Entity'] == 'Negative Keyword'
    assert r['Operation'] == 'Create'
    assert r['Match Type'] == 'negativeExact'
    assert r['Ad Group ID'] == '7' and r['Campaign ID'] == '1'
    assert r['Keyword Text'] == 'cheap junk gift'
    assert r['State'] == 'ENABLED'
    assert r['Bid'] == '', 'a negative carries no bid'


def test_sp_negative_target_row_carries_the_expression():
    c = cand(search_term='b0d7zvmxlm', leak_is_pt=True)
    r = sp_negative_target_row(c, portfolio_id='55')
    assert r['Entity'] == 'Negative Product Targeting'
    assert r['Product Targeting Expression'] == 'asin="B0D7ZVMXLM"'
    assert r['Keyword Text'] == ''


def test_sb_negative_keyword_row_uses_the_sb_casing():
    r = sb_negative_keyword_row(cand(channel='SB'), portfolio_id='55')
    assert r['Entity'] == 'Negative Keyword'
    assert r['Campaign Id'] == '1' and r['Ad Group Id'] == '7'
    assert r['Match Type'] == 'negativeExact'
    assert 'Campaign ID' not in r, 'the SB sheet uses its own casing'


# ── the README's sheet-check note ────────────────────────────────────────────────────────────
# Amazon's SB Multi Ad Group sheet has no campaign-name column, so every SB line in the workbook
# is bare ids and the README is the only human-readable cross-reference. A campaign NAMED SP that
# Amazon holds as SB therefore reads like a misroute — and "fixing" it fails the whole upload.


def test_an_sp_named_campaign_on_the_sb_sheet_is_flagged_as_correctly_routed():
    note = routing_note('FRESH SP/BROAD (Hunter ,Pink, Gift)', is_sb=True)
    assert note and 'NAMED SP' in note
    assert 'fails the whole upload' in note


def test_an_sb_named_campaign_on_the_sp_sheet_is_flagged_too():
    note = routing_note('ME-SB/VIDEO (Gift)', is_sb=False)
    assert note and 'NAMED SB' in note


def test_a_campaign_whose_name_agrees_with_its_sheet_gets_no_note():
    assert routing_note('FRESH-SP/BROAD (Back to School)', is_sb=False) is None
    assert routing_note('BOX-SB/VIDEO (Blue)', is_sb=True) is None


def test_a_name_with_no_channel_token_gets_no_note():
    assert routing_note('BOX -AUTO (Blue)', is_sb=True) is None
    assert routing_note('', is_sb=False) is None


def test_the_token_is_a_word_not_a_substring():
    # 'SPRING' must never read as SP, nor 'SBX' as SB
    assert routing_note('FRESH SPRING GIFTS', is_sb=True) is None
    assert routing_note('FRESH SBX GIFTS', is_sb=False) is None


# ── the basis window (2026-08-23): the book must measure the week the register measures ───────
# The register anchors at LEAST(MAX(date), FN_ADS_ANCHOR_CAP()); the cap is YESTERDAY (LA) for the
# 22 hours before 22:00 LA. A generator that anchors at a bare MAX(date) therefore prints the
# register's cost_per_day (capped week) beside its own 7-day spend (uncapped week) in the same row
# of the same query, and states a watermark the dollars did not come from.

def test_both_queries_anchor_on_the_register_s_capped_watermark():
    from build_seat_moves_bulksheet import LEAK_SQL, NEGATE_SQL
    for name, sql in (('LEAK_SQL', LEAK_SQL), ('NEGATE_SQL', NEGATE_SQL)):
        assert 'FN_ADS_ANCHOR_CAP' in sql, f"{name} does not apply the register's anchor cap"
        assert 'SELECT MAX(date) AS wm' not in sql, (
            f"{name} still anchors on a bare MAX(date) — one day ahead of the register for 22 "
            f"hours of every day")


def test_the_anchor_cte_is_one_definition_shared_by_both_queries():
    from build_seat_moves_bulksheet import WM_CTE, LEAK_SQL, NEGATE_SQL
    assert WM_CTE in LEAK_SQL and WM_CTE in NEGATE_SQL


# ── labelling a book never uploaded (2026-08-23) ──────────────────────────────────────────────
# Every LEAK row tells Ori to upload the pending book "or label it never uploaded". Before this
# fix the label had exactly one mechanism and it fired only at the end of a build that logged a
# NEW batch — so the only way to obey the second half of the instruction was to build another
# book, which the same sentence forbids.

def test_supersede_note_names_the_replacement_when_a_new_book_replaces_it():
    from build_seat_moves_bulksheet import supersede_note
    note = supersede_note('seat_moves_20260901_0700')
    assert 'superseded by seat_moves_20260901_0700' in note


def test_supersede_note_says_so_plainly_when_no_later_book_replaces_it():
    from build_seat_moves_bulksheet import supersede_note
    note = supersede_note(None)
    assert 'superseded by' not in note
    assert 'no later book replaces it' in note


def test_supersede_is_a_terminal_action_that_builds_nothing():
    from build_seat_moves_bulksheet import build_parser
    args = build_parser().parse_args(['--supersede', 'seat_moves_20260822_0431'])
    assert args.supersede == ['seat_moves_20260822_0431']


# ── the README of a book already logged (2026-08-23) ──────────────────────────────────────────
# The README is the only human-readable cross-reference for a workbook whose SB sheet is bare ids.
# When the writer gains a note, the READMEs already on disk do not — and regenerating one by
# building another book is exactly what the register forbids. So a README is rewritable from its
# own audit CSV, with no batch logged and no sheet written.

def _audit_fixture(tmpdir):
    import csv as _csv
    path = os.path.join(tmpdir, 'seat_moves_test_audit.csv')
    with open(path, 'w', newline='') as f:
        w = _csv.writer(f)
        w.writerow(['sheet', 'excel_row', 'kind', 'disposition', 'family', 'campaign_id',
                    'campaign', 'ad_group_id', 'keyword_id', 'target', 'search_term',
                    'match', 'channel', 'is_auto', 'is_pt', 'ladder_state', 'live_state',
                    'old_state', 'old_bid', 'portfolio_id', 'latest_history_portfolio_id',
                    'next_check_date', 'settled_clk90', 'settled_ord90',
                    'cost_per_day', 'spend_7d',
                    'ng_clicks_8w', 'ng_orders_8w', 'ng_spend_8w', 'ng_net_profit_8w',
                    'ng_clicks_recent_5d', 'ng_lt_clicks', 'ng_lt_orders', 'ng_lt_net_profit',
                    'ng_organic_units_8w', 'own_kw_clicks_8w', 'block_min_clicks',
                    'holdout_eligible_from', 'season_block', 'engine_reason', 'reason'])
        w.writerow(['SB Multi Ad Group Campaigns', '2', 'LEAK', 'PAUSE', 'Fresh', '1',
                    'FRESH SP/BROAD (Hunter ,Pink, Gift)', '7', '9', 'gift for 18 year old girl',
                    '', 'BROAD', 'SB', 'False', 'False', 'DEAD', 'ENABLED', 'ENABLED', '1.0',
                    '', '', '', '15', '0', '1.24', '8.68',
                    '', '', '', '', '', '', '', '', '', '', '',
                    '', '', '', 'it is DEAD on the ladder => pause it.'])
    return path


def test_a_readme_rewritten_from_its_audit_carries_the_sheet_check(tmp_path):
    from build_seat_moves_bulksheet import rewrite_readme_from_audit
    audit = _audit_fixture(str(tmp_path))
    out = rewrite_readme_from_audit(audit, batch_id='seat_moves_test', watermark='2026-08-21',
                                    today_la='2026-08-22')
    text = open(out).read()
    assert 'Sheet check' in text
    assert 'NAMED SP but Amazon has it as a Sponsored Brands campaign' in text
    assert 'row 2: `gift for 18 year old girl`' in text


def test_rewriting_a_readme_writes_no_workbook_and_logs_no_batch(tmp_path):
    from build_seat_moves_bulksheet import rewrite_readme_from_audit
    audit = _audit_fixture(str(tmp_path))
    out = rewrite_readme_from_audit(audit, batch_id='seat_moves_test', watermark='2026-08-21',
                                    today_la='2026-08-22')
    names = sorted(os.listdir(str(tmp_path)))
    assert names == ['seat_moves_test_README.md', 'seat_moves_test_audit.csv']
    assert out.endswith('seat_moves_test_README.md')


def test_a_rewrite_states_the_window_the_dollars_came_from_never_invents_one(tmp_path):
    """A rewritten README must not quietly restate the week. The audit CSV carries it now; for a
    book built before it did, the README being replaced is the record."""
    from build_seat_moves_bulksheet import rewrite_readme_from_audit
    audit = _audit_fixture(str(tmp_path))
    readme = os.path.join(str(tmp_path), 'seat_moves_test_README.md')
    with open(readme, 'w') as f:
        f.write("# The leak book — what each row does and why\n\n"
                "Built 2026-08-23 04:31 UTC from `seat_moves_test.xlsx` (ads watermark "
                "2026-08-21, register of 2026-08-22). Change-log batch: "
                "**`seat_moves_20260822_0431`**.\n\n")
    out = rewrite_readme_from_audit(audit)
    text = open(out).read()
    assert 'Built 2026-08-23 04:31 UTC' in text          # the build time is preserved
    assert 'REWRITTEN' in text                            # and the rewrite is declared
    assert 'ads watermark 2026-08-21' in text             # the week is the one it was built on
    assert 'seat_moves_20260822_0431' in text             # and so is the batch


def test_a_rewrite_refuses_rather_than_state_a_week_it_cannot_prove(tmp_path):
    from build_seat_moves_bulksheet import rewrite_readme_from_audit
    audit = _audit_fixture(str(tmp_path))
    try:
        rewrite_readme_from_audit(audit)
    except AssertionError as e:
        assert 'window' in str(e)
    else:
        raise AssertionError('a README with no provable window must not be written')


def test_the_audit_csv_carries_the_window_on_every_row():
    src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..',
                            'build_seat_moves_bulksheet.py')).read()
    assert "'watermark', 'register_day'])" in src


def test_the_readme_names_the_seven_days_not_only_the_anchor(tmp_path):
    """The watermark is the ANCHOR; the basis window is the seven complete days ending the day
    BEFORE it. Stating only the anchor is what let a book claim watermark 2026-08-22 while its
    dollars came from 2026-08-14..2026-08-20."""
    from build_seat_moves_bulksheet import basis_window
    assert basis_window('2026-08-21') == ('2026-08-14', '2026-08-20')
    assert basis_window('2026-08-22') == ('2026-08-15', '2026-08-21')


def test_a_rewrite_that_corrects_the_stated_week_says_so(tmp_path):
    from build_seat_moves_bulksheet import rewrite_readme_from_audit
    audit = _audit_fixture(str(tmp_path))
    readme = os.path.join(str(tmp_path), 'seat_moves_test_README.md')
    with open(readme, 'w') as f:
        f.write("# The leak book — what each row does and why\n\n"
                "Built 2026-08-23 04:31 UTC from `seat_moves_test.xlsx` (ads watermark "
                "2026-08-22, register of 2026-08-22). Change-log batch: "
                "**`seat_moves_20260822_0431`**.\n\n")
    out = rewrite_readme_from_audit(audit, watermark='2026-08-21')
    text = open(out).read()
    assert 'ads watermark 2026-08-21' in text
    assert 'previously stated 2026-08-22' in text
    assert '2026-08-14' in text and '2026-08-20' in text
