"""Token builder for the Research page's Direct / Phrase search modes.

No Flask/BigQuery imports — safe to unit-test in isolation. Broad mode (synonym
expansion) is handled inline in app.py, not here.

The matching mirrors the recommendation `coverage_count` logic in
SP_REFRESH_RESEARCH_RECOMMENDATIONS.sql exactly, so a Phrase search returns the same
terms the card's "covers N" counts. Tokenization: split on non-alphanumeric runs
(so ``8-10`` -> ``8``, ``10``), drop stop words, strip one trailing ``s`` per token
(Amazon-style plural tolerance: ``girl`` == ``girls``). The caller normalizes the
candidate column the same way and matches with whole-word, space-padded ``STRPOS``.
"""
import re


def _coverage_stems(term, stop_words):
    """Tokenize like SP coverage and return space-stripped, singularized stems.

    Split on any non-alphanumeric run, lowercase, drop stop words + empties, then
    strip one trailing 's' per token. Returns [] only when the term has no usable
    alphanumeric content (the caller guards that case).
    """
    toks = [t for t in re.split(r'[^a-z0-9]+', term.lower()) if t and t not in stop_words]
    return [re.sub(r's$', '', t) for t in toks]


def research_match_predicate(term, mode, stop_words):
    """Build STRPOS parameters for a Direct / Phrase search, matching coverage_count.

    Args:
        term:       the raw search term (tokenized here, mirroring SP coverage).
        mode:       'direct' -> exact term (whole normalized string equality).
                    anything else -> 'phrase': every token present, any order.
        stop_words: the set of stop words to drop (passed in to stay single-source).

    Returns:
        (param_map, rx_names):
          param_map: list of (param_name, value) for ScalarQueryParameter(STRING).
          rx_names:  param names; composition depends on mode (see below).

    The caller normalizes the candidate column with
      NORM(col) = REGEXP_REPLACE(CONCAT(' ',
                    REGEXP_REPLACE(LOWER(col), r'[^a-z0-9]+', ' '), ' '), r's ', ' ')
    then:
      - phrase: AND of  STRPOS(NORM(col), @rx_i) > 0   (each value is ' <stem> ')
      - direct: NORM(col) = @rx_0                       (value is ' <stem1> <stem2> ... ')

    For a term with no usable tokens, returns ([], []) so the caller can short-circuit.
    """
    stems = _coverage_stems(term, stop_words)
    if not stems:
        return [], []
    if mode == 'direct':
        return [('rx_0', ' ' + ' '.join(stems) + ' ')], ['rx_0']
    param_map = [(f'rx_{i}', f' {s} ') for i, s in enumerate(stems)]
    return param_map, [name for name, _ in param_map]
