"""Pure regex-predicate builder for the Research page's Direct / Phrase search modes.

No Flask/BigQuery imports — safe to unit-test in isolation. Broad mode (synonym
expansion) is handled inline in app.py, not here.
"""
import re


def _token_regex(token):
    """Escaped, lowercased token with an optional trailing 's' for plural tolerance."""
    return re.escape(token.lower()) + 's?'


def research_match_predicate(words, mode):
    """Build REGEXP_CONTAINS parameters for a search mode.

    Args:
        words: significant search tokens (stop-words already removed), e.g. ['girl', 'gift'].
        mode:  'direct' -> exact term + plurals, whole string (one anchored regex).
               anything else -> 'phrase': every token present, any order, extra words
               allowed (one whole-word regex per token, AND-ed by the caller).

    Returns:
        (param_map, rx_names):
          param_map: list of (param_name, regex_string) for ScalarQueryParameter(STRING).
          rx_names:  param names the caller ANDs as REGEXP_CONTAINS(LOWER(col), @name).

    Whole-word + plural-tolerant: '\\b' boundaries mean '7' != '17'; 'girls?' matches
    'girl' and 'girls'.
    """
    toks = [w for w in words if w]
    if mode == 'direct':
        body = r'\s+'.join(_token_regex(t) for t in toks)
        return [('rx_0', r'^\s*' + body + r'\s*$')], ['rx_0']
    param_map = []
    rx_names = []
    for i, t in enumerate(toks):
        name = f'rx_{i}'
        param_map.append((name, r'\b' + _token_regex(t) + r'\b'))
        rx_names.append(name)
    return param_map, rx_names
