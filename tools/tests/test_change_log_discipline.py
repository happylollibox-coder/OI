"""THE CHANGE-LOG DISCIPLINE — both books, one rule: a label is written on PENDING_UPLOAD rows
only, and a row is never deleted.

WHY THIS FILE EXISTS (2026-08-23, the first-production-night cleanup). Both generators' --supersede
matched `upload_status IS NULL OR upload_status = 'PENDING_UPLOAD'`. NULL is not "never uploaded":
NULL is the APPLIED state — V_PPC_CHANGE_LOG_APPLIED selects it, and --mark-uploaded WRITES it. So
a --supersede naming a batch Ori had really uploaded would have re-labelled it
SUPERSEDED_NEVER_UPLOADED, silently un-applying a change that had reached Amazon: the state
machine would stop reading it, the scorecard would stop grading it, and nothing would say so.
prior_unmarked_batches() had the same clause, so a book marked uploaded was still listed as "not
yet uploaded or labelled" on the next build — the listing ate its own tail and invited exactly
that --supersede.

The rule now, in both files: --supersede, --mark-uploaded and the "earlier batches" listing act
on PENDING_UPLOAD rows and nothing else; a --supersede that finds no PENDING_UPLOAD row STOPS
before any UPDATE and says why; no code path issues a DELETE. The SQL is built by small pure
functions so these tests can read it without a warehouse; the live proof on a TMP_ copy of the
change log is recorded in architecture/FAMILY_SEAT_REGISTER.md.
"""
import os
import re
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

import build_seat_moves_bulksheet as leak  # noqa: E402
import build_reprice_bulksheet as reprice  # noqa: E402
import build_seasonal_unpause_bulksheet as unpause  # noqa: E402

# Every book that writes a row into FACT_PPC_CHANGE_LOG obeys the same discipline, so every book
# is parametrised here. The seasonal unpause book (2026-08-24) joined the day it was written: it
# labels and lists exactly like its siblings, and it reverses a pause rather than making one.
BOOKS = [leak, reprice, unpause]


def _pending_only(sql):
    """The predicate every label/list statement must carry, and the one it must not."""
    assert "upload_status = 'PENDING_UPLOAD'" in sql, sql
    assert 'IS NULL OR' not in sql, sql
    assert 'upload_status IS NULL' not in sql, sql


@pytest.mark.parametrize('book', BOOKS)
def test_supersede_labels_pending_rows_only(book):
    _pending_only(book.supersede_sql('reprice_book_20260822_1614', 'note'))


@pytest.mark.parametrize('book', BOOKS)
def test_the_earlier_batches_listing_names_pending_rows_only(book):
    """A batch marked uploaded (NULL) is APPLIED and must never be listed as waiting."""
    _pending_only(book.prior_unmarked_sql())


@pytest.mark.parametrize('book', BOOKS)
def test_mark_uploaded_flips_pending_rows_only(book):
    _pending_only(book.mark_uploaded_sql('reprice_book_20260822_1614', ' | note'))


@pytest.mark.parametrize('book', BOOKS)
def test_no_statement_in_either_book_deletes_a_change_log_row(book):
    src = open(book.__file__, encoding='utf-8').read()
    assert not re.search(r'\bDELETE\s+FROM\b', src, re.IGNORECASE), book.__file__


@pytest.mark.parametrize('book', BOOKS)
def test_supersede_refuses_an_applied_batch_before_any_update(book, monkeypatch):
    """Zero PENDING_UPLOAD rows under the batch id => exit with a sentence, no UPDATE issued.
    This is the applied-batch case: the rows are NULL, and NULL means Amazon has them."""
    issued = []
    monkeypatch.setattr(book, 'bq', lambda sql: [{'n': '0'}])
    monkeypatch.setattr(book, 'run_update', lambda sql, what=None: issued.append(sql))
    with pytest.raises(SystemExit) as e:
        book.supersede(['reprice_book_20260822_1614'], 'new_batch')
    assert issued == [], 'an UPDATE was issued against a batch with no PENDING_UPLOAD row'
    assert 'PENDING_UPLOAD' in str(e.value)


@pytest.mark.parametrize('book', BOOKS)
def test_supersede_labels_exactly_the_pending_rows_it_counted(book, monkeypatch):
    calls = {'n': 0}
    issued = []

    def fake_bq(sql):
        calls['n'] += 1
        # first read: how many PENDING rows; second read: how many now carry the label
        return [{'n': '16'}]

    monkeypatch.setattr(book, 'bq', fake_bq)
    monkeypatch.setattr(book, 'run_update', lambda sql, what=None: issued.append(sql))
    book.supersede(['seat_moves_20260822_0431'], 'seat_moves_20260823_1200')
    assert len(issued) == 1
    _pending_only(issued[0])
    assert "SUPERSEDED_NEVER_UPLOADED" in issued[0]


@pytest.mark.parametrize('book', BOOKS)
def test_a_change_log_override_must_be_a_tmp_copy(book):
    """The live proof runs on a TMP_ copy; the flag that points the book there refuses any other
    name, so a test can never be aimed at the production log by a typo."""
    with pytest.raises(AssertionError):
        book.set_change_log_table('FACT_PPC_CHANGE_LOG_COPY')
    book.set_change_log_table('TMP_PPC_CHANGE_LOG_PROOF')
    assert 'TMP_PPC_CHANGE_LOG_PROOF' in book.supersede_sql('x', 'n')
    book.set_change_log_table(book.LIVE_CHANGE_LOG)
    assert 'FACT_PPC_CHANGE_LOG' in book.supersede_sql('x', 'n')


def test_the_leak_book_names_the_replacement_when_it_replaces_a_pending_book():
    """A build that carries every leak the old book carried labels the old book as superseded BY
    the new batch — the note must name it, because 'no later book replaces it' would be a lie."""
    note = leak.supersede_note('seat_moves_20260823_1200')
    assert 'superseded by seat_moves_20260823_1200' in note


def test_the_leak_book_refuses_to_log_a_second_pending_book_silently():
    """Two PENDING leak books credit the same keyword twice on the register's projections and
    hand Ori two sheets for one pause. A build that finds a pending leak book stops unless told
    which book it replaces (--replaces), and a terminal --supersede is still allowed alone."""
    ap = leak.build_parser()
    args = ap.parse_args(['--replaces', 'seat_moves_20260822_0431'])
    assert args.replaces == ['seat_moves_20260822_0431']
    with pytest.raises(SystemExit):
        leak.refuse_second_pending_book([{'batch_id': 'seat_moves_20260822_0431', 'n': 16,
                                          'upload_status': 'PENDING_UPLOAD'}], replaces=[])
    # naming the pending book is what lets the build proceed
    leak.refuse_second_pending_book([{'batch_id': 'seat_moves_20260822_0431', 'n': 16,
                                      'upload_status': 'PENDING_UPLOAD'}],
                                    replaces=['seat_moves_20260822_0431'])
    # and naming a book that is NOT pending is refused too: nothing is labelled blind
    with pytest.raises(SystemExit):
        leak.refuse_second_pending_book([], replaces=['seat_moves_20260822_0431'])


def test_the_reprice_sql_orders_totally_beyond_the_target_text():
    """House rule 9, the sibling book: state / family / campaign / target_text is not a key —
    FACT_KEYWORD_STATE can hold two rows with one (campaign_id, target_text) — so the tiebreak
    must reach (campaign_id, keyword_id) or two builds of one snapshot can differ in row order."""
    order = reprice.SQL.rstrip().rsplit('ORDER BY', 1)[1]
    assert 'target_text' in order and 'campaign_id' in order and 'keyword_id' in order


def test_the_leak_sql_orders_totally_beyond_the_rounded_cost():
    """House rule 9: cost_per_day is rounded in the register, so ties are ordinary; the tiebreak
    must reach a unique key (campaign_id, keyword_id) or two builds of one snapshot differ."""
    order = leak.LEAK_SQL.rstrip().rsplit('ORDER BY', 1)[1]
    assert 'cost_per_day DESC' in order and 'campaign_id' in order and 'keyword_id' in order
