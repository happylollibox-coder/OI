"""The README must be EXECUTABLE by a reader who has only that file, and a build that dies
before it logs must not leave a book behind (F8).

Two defects this covers, both found reading the 2026-08-23 book:

  1. The README told Ori to label the batch SUPERSEDED_NEVER_UPLOADED and to label a deleted
     line FAILED_UPLOAD, and never showed a single command — no upload destination, no
     --mark-uploaded, no --supersede, and not even the restore sheet's filename. A reader with
     only that file could not run the lifecycle it instructs.

  2. A build that wrote its book, audit and README and then died (or was killed) before the
     change-log insert left a complete-looking trio at the DEFAULT path naming a batch id that
     has no rows behind it. Uploading that sheet would be invisible to the scorecard and the
     guard. Outputs are therefore written as drafts and published together, after the log.

Pure functions, no BigQuery, no sheet, no upload.
"""
import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

from build_reprice_bulksheet import (  # noqa: E402
    DRAFT_SUFFIX, draft_path, lifecycle_section, publish_drafts, restore_path_for)

BATCH = 'reprice_book_20260823_1830'
OUT = '.tmp/reprice_book_20260823.xlsx'
AUDIT = '.tmp/reprice_book_20260823_audit.csv'


def section(**over):
    kw = dict(batch_id=BATCH, out_path=OUT, audit_path=AUDIT,
              restore_path=restore_path_for(OUT), no_log=False)
    kw.update(over)
    return lifecycle_section(**kw)


# ---- the reader can run the whole lifecycle from this file alone ----------------------

def test_names_where_the_sheet_goes():
    s = section()
    assert 'Bulk operations' in s, 'the README never says where the sheet is uploaded'


def test_says_no_script_uploads():
    assert 'by hand' in section().lower() or 'manually' in section().lower()


def test_gives_the_mark_uploaded_command_with_this_batch_id():
    s = section()
    assert f'--mark-uploaded {BATCH}' in s


def test_gives_the_supersede_command_with_this_batch_id():
    s = section()
    assert f'--supersede {BATCH}' in s


def test_supersede_is_shown_as_the_next_build_not_a_standalone_flag():
    """--supersede only fires on a build that logs; the sentence must not promise otherwise."""
    s = section()
    line = [ln for ln in s.splitlines() if '--supersede' in ln][0]
    assert 'build_reprice_bulksheet.py' in line


def test_gives_the_restore_command_with_this_audit_path():
    s = section()
    assert 'build_restore_reprice_bulksheet.py' in s
    assert f'--audit {AUDIT}' in s


def test_names_the_restore_sheet_file():
    s = section()
    assert os.path.basename(restore_path_for(OUT)) in s


def test_restore_path_follows_the_restore_builders_own_default():
    assert restore_path_for('.tmp/reprice_book_20260823.xlsx') == \
        '.tmp/restore_reprice_20260823.xlsx'
    assert restore_path_for('.tmp/reprice_book_20260823_ruleb.xlsx') == \
        '.tmp/restore_reprice_20260823.xlsx'


def test_every_command_uses_the_house_python():
    for line in section().splitlines():
        if 'build_reprice_bulksheet.py' in line or 'build_restore_reprice_bulksheet.py' in line:
            assert 'python3' in line, f'command without an interpreter: {line}'


def test_failed_upload_instruction_is_still_there():
    assert 'FAILED_UPLOAD' in section()


def test_no_log_build_says_the_batch_was_not_logged():
    s = section(no_log=True)
    assert 'not logged' in s.lower()
    # ... and must not hand the reader a --mark-uploaded for an id with no rows behind it
    assert '--mark-uploaded' not in s


def test_section_has_a_heading_so_it_is_findable():
    assert section().lstrip().startswith('#')


# ---- a build that dies before the log publishes nothing --------------------------------

def test_draft_path_is_the_final_path_plus_a_visible_suffix():
    assert draft_path(OUT) == OUT + DRAFT_SUFFIX
    assert DRAFT_SUFFIX.startswith('.')
    assert 'partial' in DRAFT_SUFFIX


def test_publish_moves_every_draft_onto_its_final_name(tmp_path):
    finals = [str(tmp_path / n) for n in ('book.xlsx', 'book_audit.csv', 'book_README.md')]
    for p in finals:
        with open(draft_path(p), 'w') as f:
            f.write(os.path.basename(p))
    publish_drafts(finals)
    for p in finals:
        assert os.path.exists(p), f'{p} was never published'
        assert not os.path.exists(draft_path(p)), 'the draft was left behind'
        assert open(p).read() == os.path.basename(p)


def test_publish_overwrites_an_older_book_at_the_same_name(tmp_path):
    final = str(tmp_path / 'book.xlsx')
    with open(final, 'w') as f:
        f.write('yesterday')
    with open(draft_path(final), 'w') as f:
        f.write('today')
    publish_drafts([final])
    assert open(final).read() == 'today'


def test_publish_refuses_a_missing_draft_and_moves_nothing(tmp_path):
    a, b = str(tmp_path / 'a.csv'), str(tmp_path / 'b.csv')
    with open(draft_path(a), 'w') as f:
        f.write('a')
    with pytest.raises(AssertionError):
        publish_drafts([a, b])
    assert not os.path.exists(a), 'a partial build published one of its files'


def test_restore_path_falls_back_to_today_when_the_book_name_carries_no_date():
    """A book built to an ad-hoc name (a dry run, a scratch path) must still name a real
    restore file — never `restore_reprice_.xlsx`."""
    from datetime import date
    p = restore_path_for('/tmp/scratch/dryrun_book.xlsx')
    assert os.path.basename(p) == f"restore_reprice_{date.today():%Y%m%d}.xlsx"
