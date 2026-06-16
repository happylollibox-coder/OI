import unittest
from research_match import research_match_predicate


class DirectMode(unittest.TestCase):
    def test_single_token_anchored_plural(self):
        params, names = research_match_predicate(['girl'], 'direct')
        self.assertEqual(names, ['rx_0'])
        self.assertEqual(params, [('rx_0', r'^\s*girls?\s*$')])

    def test_multi_token_in_order(self):
        params, names = research_match_predicate(['girl', 'gift'], 'direct')
        self.assertEqual(names, ['rx_0'])
        self.assertEqual(params, [('rx_0', r'^\s*girls?\s+gifts?\s*$')])


class PhraseMode(unittest.TestCase):
    def test_one_regex_per_token_any_order(self):
        params, names = research_match_predicate(['girl', 'gift'], 'phrase')
        self.assertEqual(names, ['rx_0', 'rx_1'])
        self.assertEqual(params, [('rx_0', r'\bgirls?\b'), ('rx_1', r'\bgifts?\b')])

    def test_number_token_keeps_word_boundary(self):
        # \b means the BQ-side regex won't match 7 inside 17 (RE2 semantics checked in Task 2)
        params, names = research_match_predicate(['7'], 'phrase')
        self.assertEqual(params, [('rx_0', r'\b7s?\b')])

    def test_tokens_lowercased(self):
        params, _ = research_match_predicate(['Girl'], 'phrase')
        self.assertEqual(params, [('rx_0', r'\bgirls?\b')])

    def test_special_char_token_is_escaped(self):
        # Regex-special chars are escaped literally; the trailing 's?' binds only to the
        # appended 's', so escaping a token never corrupts the plural-tolerance suffix.
        params, _ = research_match_predicate(['c++'], 'phrase')
        self.assertEqual(params, [('rx_0', r'\bc\+\+s?\b')])


if __name__ == '__main__':
    unittest.main()
