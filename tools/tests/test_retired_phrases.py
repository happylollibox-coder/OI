"""The retired-phrase check, tested on the two ways its predecessor failed.

The instrument this replaces was a `grep -nE` written inside the acceptance suite's comment. It
passed while a retired belief was published in four places, for two structural reasons, and both
are pinned here so the replacement cannot regress into them.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

from check_retired_phrases import (  # noqa: E402
    RETIRED, FILES, collapse, inside_quotes, line_of, scan)


def test_a_phrase_that_wraps_across_a_line_is_still_found():
    """Failure 1: line-based, against hard-wrapped Markdown. 'the sheet that would pause it does
    not exist' IS in the SOP and the documented grep did not return it."""
    raw = ("…and stated that neither projection takes a leak to $0 \"because the sheet\n"
           "that would pause it does not exist\". Both were true only between…")
    text, _ = collapse(raw)
    assert 'the sheet that would pause it does not exist' in text


def test_the_line_number_points_back_into_the_original_file():
    raw = "one\ntwo\nthe sheet that would\npause it does not exist\nfive\n"
    text, offs = collapse(raw)
    pos = text.index('the sheet that would')
    assert line_of(raw, pos, offs) == 3


def _at(t, phrase, **kw):
    i = t.index(phrase)
    return inside_quotes(t, i, i + len(phrase), **kw)


def test_a_quoted_phrase_is_allowed_and_a_bare_one_is_not():
    quoted = 'the pass recorded it as "leaks stay paused" and retired it'
    bare = 'the projection assumes leaks stay paused, which is the defect'
    assert _at(quoted, 'leaks stay paused')
    assert not _at(bare, 'leaks stay paused')


def test_a_typographic_pair_counts_as_a_quotation_too():
    t = 'it used to read “leaks stay paused” and no longer does'
    assert _at(t, 'leaks stay paused')


def test_one_stray_quote_elsewhere_cannot_invert_the_answer():
    """The parity version this replaced was flipped by a single Markdown code span containing
    three quote characters, and reported every match after it with the opposite verdict."""
    bare = ('a code span `WM_CTE + \'\'\'…` appears far above. ' + 'x' * 400 +
            ' the projection assumes leaks stay paused, which is the defect')
    assert not _at(bare, 'leaks stay paused')


def test_a_straight_quote_in_config_yaml_is_a_delimiter_not_a_quotation():
    """Failure 2: the grep read two files and three carry the doctrine. config.yaml wraps every
    description in one straight ", so counting it as quotation would mark every retired clause in
    the registry 'quoted, therefore allowed' — which is how the stale R-l(d) reasoning survived."""
    t = ('    description: "…the shipped generator builds that pause row today — leaks stay '
         'paused, and the rest of the entry continues here."')
    assert _at(t, 'leaks stay paused', straight_quotes=True)
    assert not _at(t, 'leaks stay paused', straight_quotes=False)


def test_config_yaml_is_scanned_with_delimiters_not_counted():
    policy = dict(FILES)
    assert 'config.yaml' in policy, 'the registry must be scanned — it carries the doctrine too'
    assert policy['config.yaml'] is False


def test_the_view_the_sop_and_the_leak_book_are_all_scanned():
    scanned = {p for p, _ in FILES}
    assert 'scripts/bigquery/views/V_FAMILY_SEAT_REGISTER.sql' in scanned
    assert 'architecture/FAMILY_SEAT_REGISTER.md' in scanned
    assert 'tools/build_seat_moves_bulksheet.py' in scanned


def test_every_retired_entry_carries_the_date_and_what_replaced_it():
    for pat, when, why in RETIRED:
        assert pat and when and why, pat
        assert when.startswith('2026-'), pat


def test_the_repo_publishes_no_retired_phrase_outside_quotation_marks():
    bad = [h for h in scan() if not h[3]]
    assert not bad, '\n'.join(f"{h[0]}:{h[1]} /{h[2]}/ …{h[4]}…" for h in bad)


# ── negative controls: the two clauses this check was built to catch, as they were shipped ────

def test_it_flags_the_sop_sentence_that_offered_a_command_with_no_executable_path():
    import re
    from check_retired_phrases import RETIRED
    shipped = ("`PENDING_UPLOAD` keeps the rows out of `V_PPC_CHANGE_LOG_APPLIED`, so the state "
               "machine never re-reads a file that is still on disk as changes that happened. "
               "`--mark-uploaded BATCH` when Ori has uploaded; `--supersede BATCH` labels an "
               "earlier never-uploaded book `SUPERSEDED_NEVER_UPLOADED`. **A log row is never "
               "deleted.**")
    pat = next(p for p, _w, _y in RETIRED if 'supersede BATCH' in p)
    m = re.search(pat, shipped, re.IGNORECASE)
    assert m, 'the phrase must be in the retired list'
    assert not _at(shipped, m.group(0)), 'and it must read as published, not quoted'


def test_it_flags_the_registry_clause_that_task_3_killed():
    shipped = ('    description: "…The FAILED half is unchanged and still reaches $0 on re-judged '
               'because the shipped generator builds that pause row today — same rule, opposite '
               'answer, because one sheet exists and the other does not (B35)), CATEGORY (sum to '
               'the family spend to the cent), SEAT (one per occupant…"')
    phrase = 'same rule, opposite answer, because one sheet exists and the other does not'
    assert not _at(shipped, phrase, straight_quotes=False)
